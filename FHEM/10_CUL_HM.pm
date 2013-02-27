##############################################
# CUL HomeMatic handler
# $Id$

#peerlisten check
#virtual channel for dimmer check

package main;

# update regRaw warnings                                  "#todo Updt2 remove"
# update actiondetect                                     "#todo Updt3 remove"
#        the lines can be removed after some soak time - around version 2600
use strict;
use warnings;

sub CUL_HM_Initialize($);
sub CUL_HM_Define($$);
sub CUL_HM_Undef($$);
sub CUL_HM_Parse($$);
sub CUL_HM_Get($@);
sub CUL_HM_fltCvT($);
sub CUL_HM_Set($@);
sub CUL_HM_infoUpdtDevData($$$);
sub CUL_HM_Pair(@);
sub CUL_HM_getConfig($$$$$);
sub CUL_HM_SndCmd($$);
sub CUL_HM_responseSetup($$);
sub CUL_HM_eventP($$);
sub CUL_HM_respPendRm($);
sub CUL_HM_respPendTout($);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_Resend($);
sub CUL_HM_Id($);
sub CUL_HM_name2Hash($);
sub CUL_HM_name2Id(@);
sub CUL_HM_id2Name($);
sub CUL_HM_getDeviceHash($);
sub CUL_HM_DumpProtocol($$@);
sub CUL_HM_parseCommon(@);
sub CUL_HM_encodeTime8($);
sub CUL_HM_decodeTime8($);
sub CUL_HM_encodeTime16($);
sub CUL_HM_convTemp($);
sub CUL_HM_updtRegDisp($$$);
sub CUL_HM_decodeTime16($);
sub CUL_HM_pushConfig($$$$$$$$);
sub CUL_HM_maticFn($$$$$);
sub CUL_HM_secSince2000();
sub CUL_HM_noDup(@);        #return list with no duplicates
sub CUL_HM_noDupInString($);#return string with no duplicates, comma separated

# ----------------modul globals-----------------------
my $respRemoved; # used to control trigger of stach processing
                 # need to take care that ACK is first
my $K_actDetID = '000000'; # id of actionDetector 

#my %culHmDevProps=(
#  "01" => { st => "AlarmControl",    cl => " "        }, # by peterp
#  "12" => { st => "outputUnit",      cl => "receiver" }, # Test Pending
#  "10" => { st => "switch",          cl => "receiver" }, # Parse,Set
#  "20" => { st => "dimmer",          cl => "receiver" }, # Parse,Set
#  "30" => { st => "blindActuator",   cl => "receiver" }, # Parse,Set
#  "39" => { st => "ClimateControl",  cl => "sender"   },
#  "40" => { st => "remote",          cl => "sender"   }, # Parse
#  "41" => { st => "sensor",          cl => "sender"   },
#  "42" => { st => "swi",             cl => "sender"   }, # e.g. HM-SwI-3-FM
#  "43" => { st => "pushButton",      cl => "sender"   },
#  "58" => { st => "thermostat",      cl => "receiver" }, 
#  "60" => { st => "KFM100",          cl => "sender"   }, # Parse,unfinished
#  "70" => { st => "THSensor",        cl => "sender"   }, # Parse,unfinished
#  "80" => { st => "threeStateSensor",cl => "sender"   }, # e.g.HM-SEC-RHS
#  "81" => { st => "motionDetector",  cl => "sender"   },
#  "C0" => { st => "keyMatic",        cl => "receiver" },
#  "C1" => { st => "winMatic",        cl => "receiver" },
#  "CD" => { st => "smokeDetector",   cl => "receiver" }, # Parse,set unfinished
#);
# chan supports autocreate of channels for the device
# Syntax  <chnName>:<chnNoStart>:<chnNoEnd> 
# chn=>{btn:1:3,disp:4,aux:5:7} wil create
# <dev>_btn1,<dev>_btn2,<dev>_btn3 as channel 1 to 3
# <dev>_disp as channel 4
# <dev>_aux1,<dev>_aux2,<dev>_aux7 as channel 5 to 7
# autocreate for single channel devices is possible not recommended
#rxt - receivetype of the device------
# c: receive on config
# w: receive in wakeup
# b: receive on burst
#register list definition - identifies valid register lists
# 1,3,5:3p.4.5 => list 1 valid for all channel
#             => list 3 for all channel
#             => list 5 only for channel 3 but assotiated with peers
#             => list 5 for channel 4 and 5 with peer=00000000
#
my %culHmModel=(
  "0001" => {name=>"HM-LC-SW1-PL-OM54"       ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0002" => {name=>"HM-LC-SW1-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0003" => {name=>"HM-LC-SW4-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0004" => {name=>"HM-LC-SW1-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0005" => {name=>"HM-LC-BL1-FM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0006" => {name=>"HM-LC-BL1-SM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0007" => {name=>"KS550"                   ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>''    ,lst=>'1'            ,chn=>"",},
  "0008" => {name=>"HM-RC-4"                 ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0009" => {name=>"HM-LC-SW2-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000A" => {name=>"HM-LC-SW2-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000B" => {name=>"HM-WDC7000"              ,st=>'THSensor'          ,cyc=>''      ,rxt=>''    ,lst=>''             ,chn=>"",},
  "000D" => {name=>"ASH550"                  ,st=>'THSensor'          ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "000E" => {name=>"ASH550I"                 ,st=>'THSensor'          ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "000F" => {name=>"S550IA"                  ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "0011" => {name=>"HM-LC-SW1-PL"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0012" => {name=>"HM-LC-DIM1L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0013" => {name=>"HM-LC-DIM1L-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "0016" => {name=>"HM-LC-DIM2L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "0018" => {name=>"CMM"                     ,st=>'remote'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0019" => {name=>"HM-SEC-KEY"              ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "001A" => {name=>"HM-RC-P1"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "001B" => {name=>"HM-RC-SEC3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001C" => {name=>"HM-RC-SEC3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001D" => {name=>"HM-RC-KEY3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001E" => {name=>"HM-RC-KEY3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "0022" => {name=>"WS888"                   ,st=>''                  ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0026" => {name=>"HM-SEC-KEY-S"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "0027" => {name=>"HM-SEC-KEY-O"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "0028" => {name=>"HM-SEC-WIN"              ,st=>'winMatic'          ,cyc=>''      ,rxt=>'b'   ,lst=>'1,3'          ,chn=>"Win:1:1,Akku:2:2",},
  "0029" => {name=>"HM-RC-12"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002A" => {name=>"HM-RC-12-B"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002D" => {name=>"HM-LC-SW4-PCB"           ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "002E" => {name=>"HM-LC-DIM2L-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "002F" => {name=>"HM-SEC-SC"               ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0030" => {name=>"HM-SEC-RHS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0034" => {name=>"HM-PBI-4-FM"             ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",}, # HM Push Button Interface
  "0035" => {name=>"HM-PB-4-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0036" => {name=>"HM-PB-2-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:2",},
  "0037" => {name=>"HM-RC-19"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18:18",},
  "0038" => {name=>"HM-RC-19-B"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18:18",},
  "0039" => {name=>"HM-CC-TC"                ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'5:2.3p,6:2'   ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3",},
  "003A" => {name=>"HM-CC-VD"                ,st=>'thermostat'        ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'5'            ,chn=>"",},
  "003B" => {name=>"HM-RC-4-B"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "003C" => {name=>"HM-WDS20-TH-O"           ,st=>'THSensor'          ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003D" => {name=>"HM-WDS10-TH-O"           ,st=>'THSensor'          ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003E" => {name=>"HM-WDS30-T-O"            ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003F" => {name=>"HM-WDS40-TH-I"           ,st=>'THSensor'          ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "0040" => {name=>"HM-WDS100-C6-O"          ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1'            ,chn=>"",},
  "0041" => {name=>"HM-WDC7000"              ,st=>'THSensor'          ,cyc=>''      ,rxt=>''    ,lst=>'1,4'          ,chn=>"",},
  "0042" => {name=>"HM-SEC-SD"               ,st=>'smokeDetector'     ,cyc=>'99:00' ,rxt=>'b'   ,lst=>''             ,chn=>"",},
  "0043" => {name=>"HM-SEC-TIS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0044" => {name=>"HM-SEN-EP"               ,st=>'sensor'            ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0045" => {name=>"HM-SEC-WDS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0046" => {name=>"HM-SWI-3-FM"             ,st=>'swi'               ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"Sw:1:3",},
  "0047" => {name=>"KFM-Sensor"              ,st=>'KFM100'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0048" => {name=>"IS-WDS-TH-OD-S-R3"       ,st=>''                  ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},
  "0049" => {name=>"KFM-Display"             ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "004A" => {name=>"HM-SEC-MDIR"             ,st=>'motionDetector'    ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "004B" => {name=>"HM-Sec-Cen"              ,st=>'AlarmControl'      ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "004C" => {name=>"HM-RC-12-SW"             ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "004D" => {name=>"HM-RC-19-SW"             ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18:18",},
  "004E" => {name=>"HM-LC-DDC1-PCB"          ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # door drive controller 1-channel (PCB)
  "004F" => {name=>"HM-SEN-MDIR-SM"          ,st=>'motionDetector'    ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0050" => {name=>"HM-SEC-SFA-SM"           ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Siren:1:1,Flash:2:2",},
  "0051" => {name=>"HM-LC-SW1-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0052" => {name=>"HM-LC-SW2-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:2",},
  "0053" => {name=>"HM-LC-BL1-PB-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0054" => {name=>"DORMA_RC-H"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",}, # DORMA Remote 4 buttons 
  "0056" => {name=>"HM-CC-SCD"	             ,st=>'smokeDetector'     ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0057" => {name=>"HM-LC-DIM1T-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0058" => {name=>"HM-LC-DIM1T-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0059" => {name=>"HM-LC-DIM1T-FM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "005A" => {name=>"HM-LC-DIM2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},#4virt- is this a faulty entry?
  "005C" => {name=>"HM-OU-CF-PL"             ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Led:1:1,Sound:2:2",},
  "005D" => {name=>"HM-Sen-MDIR-O"           ,st=>'motionDetector'    ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "005F" => {name=>"HM-SCI-3-FM"             ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"Sw:1:3",},
  "0060" => {name=>"HM-PB-4DIS-WM"           ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:20",},
  "0061" => {name=>"HM-LC-SW4-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0062" => {name=>"HM-LC-SW2-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "0064" => {name=>"DORMA_atent"             ,st=>''                  ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",}, # DORMA Remote 3 buttons
  "0065" => {name=>"DORMA_BRC-H"             ,st=>''                  ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",}, # Dorma Remote 4 single buttons
  "0066" => {name=>"HM-LC-SW4-WM"            ,st=>'switch'            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0067" => {name=>"HM-LC-Dim1PWM-CV"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},#Sw:1:1,
  "0068" => {name=>"HM-LC-Dim1TPBU-FM"       ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},#Sw:1:1,
  "0069" => {name=>"HM-LC-Sw1PBU-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "006A" => {name=>"HM-LC-Bl1PBU-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "006B" => {name=>"HM-PB-2-WM55"            ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"Btn:1:2",},
  "006C" => {name=>"HM-LC-SW1-BA-PCB"        ,st=>'switch'            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "006D" => {name=>"HM-OU-LED16"             ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''    ,lst=>''             ,chn=>"Led:1:16",},
  "006E" => {name=>"HM-LC-Dim1L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},# Sw:1:1,	
  "006F" => {name=>"HM-LC-Dim1L-Pl"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},# Sw:1:1,
  "0070" => {name=>"HM-LC-Dim2L-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "0071" => {name=>"HM-LC-Dim1T-Pl"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},# Sw:1:1,
  "0072" => {name=>"HM-LC-Dim1T-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},# Sw:1:1,
  "0073" => {name=>"HM-LC-Dim1T-FM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw1_V:2:3",},# Sw:1:1,
  "0074" => {name=>"HM-LC-Dim2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "0075" => {name=>"HM-OU-CFM-PL"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Led:1:1,Mp3:2:2",},
  "0076" => {name=>"HM-Sys-sRP-Pl"           ,st=>'repeater'          ,cyc=>''      ,rxt=>''    ,lst=>'2'            ,chn=>"",}, # repeater
  "0078" => {name=>"HM-Dis-TD-T"             ,st=>'switch'            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",}, #
  "0079" => {name=>"ROTO_ZEL-STG-RM-FWT"     ,st=>''                  ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",}, #
  "007A" => {name=>"ROTO_ZEL-STG-RM-FSA"     ,st=>''                  ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, #
  "007B" => {name=>"ROTO_ZEL-STG-RM-FEP-230V",st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)
  "007C" => {name=>"ROTO_ZEL-STG-RM-FZS"     ,st=>'remote'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled socket adapter switch actuator 1-channel				
  "007D" => {name=>"ROTO_ZEL-STG-RM-WT-2"    ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",}, # HM Push Button 2
  "007E" => {name=>"ROTO_ZEL-STG-RM-DWT-10"  ,st=>'remote'            ,cyc=>'00:10' ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",}, # HM Remote Display 4 buttons Roto
  "007F" => {name=>"ROTO_ZEL-STG-RM-FST-UP4" ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",}, # HM Push Button Interface
  "0080" => {name=>"ROTO_ZEL-STG-RM-HS-4"    ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",}, # HM Remote 4 buttons
  "0081" => {name=>"ROTO_ZEL-STG-RM-FDK"     ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",}, # HM Rotary Handle Sensor
  "0082" => {name=>"Roto_ZEL-STG-RM-FFK"     ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",}, # HM Shutter Contact
  "0083" => {name=>"Roto_ZEL-STG-RM-FSS-UP3" ,st=>'switch'            ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"",}, # HM Switch Interface 3 switches
  "0084" => {name=>"Schueco_263-160"         ,st=>'smokeDetector'     ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",}, # HM SENSOR_FOR_CARBON_DIOXIDE
  "0086" => {name=>"Schueco_263-146"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)
  "0087" => {name=>"Schueco_263-147"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)   						
  "0088" => {name=>"Schueco_263-132" 		 ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer L (ceiling voids)				
  "0089" => {name=>"Schueco_263-134"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer T (ceiling voids)							
  "008A" => {name=>"Schueco_263-133"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer TPBU (flush mount) 						
  "008B" => {name=>"Schueco_263-130"         ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled switch actuator 1-channel (flush-mount)							
  "008C" => {name=>"Schueco_263-131"         ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, # radio-controlled switch actuator 1-channel (flush-mount)						
  "008D" => {name=>"Schueco_263-135"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",}, # HM Push Button 2
  "008E" => {name=>"Schueco_263-155"         ,st=>'remote'            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",}, # HM Remote Display 4 buttons
  "008F" => {name=>"Schueco_263-145"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",}, # HM Push Button Interface
  "0090" => {name=>"Schueco_263-162"         ,st=>'motionDetector'    ,cyc=>'00:30' ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",}, # HM radio-controlled motion detector
  "0092" => {name=>"Schueco_263-144"         ,st=>'switch'            ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"",}, # HM Switch Interface 3 switches 
  "0093" => {name=>"Schueco_263-158"         ,st=>'switch'            ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",}, #
  "0094" => {name=>"Schueco_263-157"         ,st=>''                  ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",}, #
  "009F" => {name=>"HM-Sen-Wa-Od"            ,st=>'sensor'            ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",}, #capacitive filling level sensor
  "00A1" => {name=>"HM-LC-SW1-PL2"           ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",}, #
  "00A2" => {name=>"ROTO_ZEL-STG-RM-FZS-2"   ,st=>'switch'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",}, #radio-controlled socket adapter switch actuator 1-channel
  "00A3" => {name=>"HM-LC-Dim1L-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "00A4" => {name=>"HM-LC-Dim1T-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "00A7" => {name=>"HM-Sen-RD-O"             ,st=>''                  ,cyc=>''      ,rxt=>''    ,lst=>'1:1,4:1'      ,chn=>"Rain:1:1,Sw:2:2",}, 						
  #263 167                        HM Smoke Detector Schueco 
);

sub CUL_HM_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}     = "^A....................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{UndefFn}   = "CUL_HM_Undef";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{GetFn}     = "CUL_HM_Get";
  $hash->{RenameFn}  = "CUL_HM_Rename";
  $hash->{AttrFn}    = "CUL_HM_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:1,0 dummy:1,0 ".
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
                       "serialNr firmware ".
                       "rawToReadable unit ".#"KFM-Sensor" only
                       "peerIDs ".
                       "actCycle actStatus autoReadReg:1,0 ".
					   "expert:0_off,1_on,2_full ".

                       "hmClass:obsolete devInfo:obsolete ". #unused
					   ".stc .devInfo ".
                       $readingFnAttributes;
  my @modellist;
  foreach my $model (keys %culHmModel){
    push @modellist,$culHmModel{$model}{name};
  }
  $hash->{AttrList}  .= " model:"  .join(",", sort @modellist);
  $hash->{AttrList}  .= " subType:".join(",",
               CUL_HM_noDup(map { $culHmModel{$_}{st} } keys %culHmModel));
  CUL_HM_initRegHash();
}
sub CUL_HM_autoReadConfig($){
  # will trigger a getConfig and statusrequest for each device assigned.
  #
  while(@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    my $name = shift(@{$modules{CUL_HM}{helper}{updtCfgLst}});
    my $hash = CUL_HM_name2Hash($name);
	if (1 == AttrVal($name,"autoReadReg","0")){
	  CUL_HM_Set($hash,$name,"getConfig");
	  CUL_HM_Set($hash,$name,"statusRequest");
	  InternalTimer(gettimeofday()+15,"CUL_HM_autoReadConfig","updateConfig",0);
	  last;
	}
  }
}
sub CUL_HM_updateConfig($){
  # this routine is called 5 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes
  # it will also be called after each manual definition
  # Purpose is to parse attributes and read config
  my @getConfList;
  my @nameList = CUL_HM_noDup(@{$modules{CUL_HM}{helper}{updtCfgLst}});
  while(@nameList){
    my $name = shift(@nameList);
    my $hash = CUL_HM_name2Hash($name);
	if (CUL_HM_hash2Id($hash) ne $K_actDetID){# if not action detector
 	  CUL_HM_ID2PeerList($name,"",1);       # update peerList out of peerIDs
      my $actCycle = AttrVal($name,"actCycle",undef);
	  CUL_HM_ActAdd(CUL_HM_hash2Id($hash),$actCycle) if ($actCycle);# re-read start values 
	}
	else{
	  ;#delete $attr{$name}{peerIDs}; # remove historical data
	}
	
	# convert variables, delete obsolete, move to hidden level
    $attr{$name}{".devInfo"} = $attr{$name}{devInfo} if ($attr{$name}{devInfo});
	delete $attr{$name}{devInfo};
	delete $attr{$name}{hmClass};

	if ("dimmer" eq CUL_HM_Get($hash,$name,"param","subType")) {
	  #configure Dimmer virtual channel assotiation

	  my $id = CUL_HM_hash2Id($hash);
	  if (length($id) == 8 || !$hash->{"channel_01"}){
	    my $chn = substr($id,6,2);
	    my $devId = substr($id,0,6);
		$chn = "01" if (!$chn); # device acts as channel 01
	    my $model = CUL_HM_Get($hash,$name,"param","model");
	    my $mId = CUL_HM_getMId($hash);
	    my $chSet = $culHmModel{$mId}{chn};
	    $hash->{helper}{vDim}{chnSet} = $chSet;
		
		my @chnPh = (grep{$_ =~ m/Sw:/ } split ',',$chSet);
		@chnPh = split ':',$chnPh[0] if (@chnPh);
		my $chnPhyMax = $chnPh[2]?$chnPh[2]:1;   # max Phys channels
		my $chnPhy = int(($chn-$chnPhyMax+1)/2); # my phys chn

		my $idPhy = $devId.sprintf("%02X",$chnPhy);
		my $pHash = CUL_HM_id2Hash($idPhy);
		$idPhy = CUL_HM_hash2Id($pHash);

		if ($pHash){
		  $pHash->{helper}{vDim}{idPhy} = $idPhy;
		  my $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy-1));
		  if ($vHash){
		    $pHash->{helper}{vDim}{idV2}  = CUL_HM_hash2Id($vHash);
		    $vHash->{helper}{vDim}{idPhy} = $idPhy;
		  }
		  else{
		    delete $pHash->{helper}{vDim}{idV2};
		  }
		  $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy));
		  if ($vHash){
		    $pHash->{helper}{vDim}{idV3}  = CUL_HM_hash2Id($vHash);
		    $vHash->{helper}{vDim}{idPhy} = $idPhy;
		  }
		  else{
		    delete $pHash->{helper}{vDim}{idV3};
		  }
		}
        my %logicCombination=(
		              inactive=>'$val=$val',
                      or      =>'$val=$in>$val            ?$in            :$val' ,#max
					  and     =>'$val=$in<$val            ?$in            :$val' ,#min
					  xor     =>'$val=($in!=0&&$val!=0)   ?0              :($in>$val?$in:$val)',#0 if both are != 0, else max
					  nor     =>'$val=100-($in>$val       ?$in            :$val)',#100-max
					  nand    =>'$val=100-($in<$val       ?$in            :$val)',#100-min
					  orinv   =>'$val=(100-$in)>$val      ?(100-$in)      :$val' ,#max((100-chn),other)
					  andinv  =>'$val=(100-$in)<$val      ?(100-$in)      :$val' ,#min((100-chn),other)
					  plus    =>'$val=($in + $val)<100    ?($in + $val)   :100'  ,#other + chan
					  minus   =>'$val=($in - $val)>0      ?($in + $val)   :0'    ,#other - chan
					  mul     =>'$val=($in * $val)<100    ?($in + $val)   :100'  ,#other * chan
					  plusinv =>'$val=($val+100-$in)<100  ?($val+100-$in) :100'  ,#other + 100 - chan
					  minusinv=>'$val=($val-100+$in)>0    ?($val-100+$in) : 0'   ,#other - 100 + chan
					  mulinv  =>'$val=((100-$in)*$val)<100?(100-$in)*$val):100'  ,#other * (100 - chan)
					  invPlus =>'$val=(100-$val-$in)>0    ?(100-$val-$in) :0'    ,#100 - other - chan
					  invMinus=>'$val=(100-$val+$in)<100  ?(100-$val-$in) :100'  ,#100 - other + chan
					  invMul  =>'$val=(100-$val*$in)>0    ?(100-$val*$in) :0'    ,#100 - other * chan
		);
		if ($pHash->{helper}{vDim}{idPhy}){
		  my $vName = CUL_HM_id2Name($pHash->{helper}{vDim}{idPhy});
		  $pHash->{helper}{vDim}{oper1} = ReadingsVal($vName,"logicCombination","inactive");	
		  $pHash->{helper}{vDim}{operExe1} = $logicCombination{$pHash->{helper}{vDim}{oper1}} ;	
		}
	  }
	  
	}

	# add default web-commands
    my $webCmd;
    my $st = AttrVal(($hash->{device}?$hash->{device}:$name), "subType", "");
    $webCmd  = AttrVal($name,"webCmd","");
    if (!$webCmd){
	  if((length (CUL_HM_hash2Id($hash)) == 6)&&
	         $hash->{channel_01}  &&
	         $st ne "virtual"     &&
			 $st ne "thermostat"   ){$webCmd="getConfig";
	  }elsif($st eq "blindActuator"){$webCmd="toggle:on:off:stop:statusRequest";
	  }elsif($st eq "dimmer"       ){$webCmd="toggle:on:off:statusRequest";
	  }elsif($st eq "switch"       ){$webCmd="toggle:on:off:statusRequest";
	  }elsif($st eq "virtual"      ){$webCmd="press short:press long";
	  }elsif($st eq "smokeDetector"){$webCmd="test:alarmOn:alarmOff";
	  }elsif($st eq "keyMatic"     ){$webCmd="lock:inhibit on:inhibit off";
	  }
	  my $eventMap  = AttrVal($name,"eventMap",undef);
	  if (defined $eventMap){
	    foreach (split " ",$eventMap){
	      my ($old,$new) = split":",$_;
		  my $nW = $webCmd;
		  $nW =~ s/^$old:/$new:/;
		  $nW =~ s/$old$/$new/;#General check
		  $nW =~ s/:$old:/:$new:/;
		  $webCmd = $nW;
		}
	  }
	}
	$attr{$name}{webCmd} = $webCmd if ($webCmd);
	push @getConfList,$name if (1 == AttrVal($name,"autoReadReg","0"));
  }
  $modules{CUL_HM}{helper}{updtCfgLst} = \@getConfList;
  CUL_HM_autoReadConfig("updateConfig");
}
sub CUL_HM_Define($$) {#############################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $HMid = uc($a[2]);
  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $HMid !~ m/^[A-F0-9]{6,8}$/i);
  return  "HMid DEF already used by " .	CUL_HM_id2Name($HMid)	 
        if ($modules{CUL_HM}{defptr}{$HMid}); 
  my $name = $hash->{NAME};
  if(length($HMid) == 8) {# define a channel
    my $devHmId = substr($HMid, 0, 6);
    my $chn = substr($HMid, 6, 2);
    my $devHash = $modules{CUL_HM}{defptr}{$devHmId};
	return "please define a device with hmId:".$devHmId." first" if(!$devHash);
	
    my $devName = $devHash->{NAME};
	$hash->{device} = $devName;          #readable ref to device name
    $hash->{chanNo} = $chn;              #readable ref to Channel
	$devHash->{"channel_$chn"} = $name;  #reference in device as well
    $attr{$name}{model} = AttrVal($devName, "model", undef);
  }
  else{# define a device
    AssignIoPort($hash);
  }
  $modules{CUL_HM}{defptr}{$HMid} = $hash;
  
  #- - - - create auto-update - - - - - -
  CUL_HM_ActGetCreateHash() if($HMid eq '000000');#startTimer
  $hash->{DEF} = $HMid;
  CUL_HM_Parse($hash, $a[3]) if(int(@a) == 4);
  RemoveInternalTimer("updateConfig");
  InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
 
  my @arr;
  if(!$modules{CUL_HM}{helper}{updtCfgLst}){
    $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
  }
  push(@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name);
  return undef;
}
sub CUL_HM_Undef($$) {#############################
  my ($hash, $name) = @_;
  my $devName = $hash->{device};
  my $HMid = $hash->{DEF};
  my $chn = substr($HMid,6,2);
  if ($chn){# delete a channel
	my $devHash = CUL_HM_name2Hash($devName);
    delete $devHash->{"channel_$chn"} if ($devName);
  }
  else{# delete a device
    foreach my $channel (keys %{$hash}){
	  CommandDelete(undef,$hash->{$channel})
	        if ($channel =~ m/^channel_/);
    }
  }
  delete($modules{CUL_HM}{defptr}{$HMid});
  return undef;
}
sub CUL_HM_Rename($$$) {#############################
  my ($name, $oldName) = @_;
  my $HMid = CUL_HM_name2Id($name);
  my $hash = CUL_HM_name2Hash($name);
  if (length($HMid) == 8){# we are channel, inform the device
    $hash->{chanNo} = substr($HMid,6,2);
	my $devHash = CUL_HM_id2Hash(substr($HMid,0,6));
    $hash->{device} = CUL_HM_hash2Name($devHash);
	$devHash->{"channel_".$hash->{chanNo}} = $name;
  }
  else{# we are a device - inform channels if exist
    foreach (grep {$_ =~m/^channel_/} keys%{$hash}){
	  Log 1,"General notify channel:".$hash->{$_}." for:".$name;
	  my $chnHash = CUL_HM_name2Hash($hash->{$_});
	  $chnHash->{device} = $name;
	}
  }
  return;
}
sub CUL_HM_Parse($$) {#############################
  my ($iohash, $msg) = @_;
  my $id = CUL_HM_Id($iohash);
  my $ioName = $iohash->{NAME};
  # Msg format: Allnnffttssssssddddddpp...
  $msg =~ m/A(..)(..)(..)(..)(......)(......)(.*)/;
  my ($len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p1) = ($1,$2,$3,$4,$5,$6,$7);
  $p1 = "" if(!defined($p1));
  my $cmd = "$msgFlag$msgType"; #still necessary to maintain old style
  my $lcm = "$len$cmd";
  # $shash will be replaced for multichannel commands
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  my $dname = ($dst eq "000000") ? "broadcast" :
                                   ($dhash ? $dhash->{NAME} : 
								             ($dst eq $id ? $ioName : 
											                $dst));
  my $target = " (to $dname)";
  my ($p,$msgStat,$myRSSI,$msgIO) = split(":",$p1,4);

  return "" if($msgStat && $msgStat eq 'NACK');#discard if lowlevel error
  return "" if($src eq $id);#discard mirrored messages
  
  $respRemoved = 0;  #set to 'no response in this message' at start
  if(!$shash) {      #  Unknown source
    # Generate an UNKNOWN event for pairing requests, ignore everything else
    if($msgType eq "00") {
      my $model = substr($p, 2, 4);
	  $model = $culHmModel{$model}{name}  ?
	            $culHmModel{$model}{name} :
				"ID_".$model;
	  my $sname = "CUL_HM_".$model."_$src";
	  $sname =~ s/-/_/g;
      Log 3, "CUL_HM Unknown device $sname, please define it";
      return "UNDEFINED $sname CUL_HM $src $msg";
    }
   return "";
  }
  CUL_HM_eventP($shash,"Rcv");
  my $name = $shash->{NAME};
  my @event;
  my $st = AttrVal($name, "subType", "");
  my $model = AttrVal($name, "model", "");
  my $tn = TimeNow();

  CUL_HM_storeRssi($name,
                   "to_".((hex($msgFlag)&0x40)?"rpt_":"").$ioName,# repeater?
                   $myRSSI);

  my $msgX = "No:$msgcnt - t:$msgType s:$src d:$dst ".($p?$p:"");

  if($shash->{lastMsg} && $shash->{lastMsg} eq $msgX) {
    Log GetLogLevel($name,4), "CUL_HM $name dup mesg";
    if(($id eq $dst)&& (hex($msgFlag)&0x20)){
#	  CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."00");  # Send Ack
      Log GetLogLevel($name,4), "CUL_HM $name dup mesg - ack and ignore";
	}
	else{
      Log GetLogLevel($name,4), "CUL_HM $name dup mesg - ignore";
	}

    return $name; #return something to please dispatcher
  }
  $shash->{lastMsg} = $msgX;
  $iohash->{HM_CMDNR} = hex($msgcnt) if($dst eq $id);# updt message cnt to rec

  CUL_HM_DumpProtocol("RCV",$iohash,$len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p);

  #----------start valid messages parsing ---------
  my $parse = CUL_HM_parseCommon($msgcnt,$msgFlag,$msgType,$src,$dst,$p);
  push @event, "powerOn"   if($parse eq "powerOn");
  
  my $sendAck = "yes";# if yes Ack will be determined automatically
	
  if ($parse eq "ACK"){# remember - ACKinfo will be passed on
    push @event, "";
  }
  elsif($parse eq "NACK"){
	push @event, "state:NACK";
  }
  elsif($parse eq "done"){
    push @event, "";
  } 
  elsif($lcm eq "09A112") {      #### Another fhem wants to talk (HAVE_DATA)
    ;
  } 
  elsif($msgType eq "00" ){      #### DEVICE_INFO,  Pairing-Request 
 	CUL_HM_ProcessCmdStack($shash) if(CUL_HM_getRxType($shash) & 0x04);#config
    CUL_HM_infoUpdtDevData($name, $shash,$p);#update data

    if($shash->{cmdStack} && (CUL_HM_getRxType($shash) & 0x04)) {
	  push @event,"";
    } 
	else {
      push @event, CUL_HM_Pair($name, $shash,$cmd,$src,$dst,$p);
    }
  } 
  elsif($model eq "KS550" || $model eq "HM-WDS100-C6-O") { ####################

    if($msgType eq "70" && $p =~ m/^(....)(..)(....)(....)(..)(..)(..)/) {

      my (    $t,      $h,      $r,      $w,     $wd,      $s,      $b ) =
         (hex($1), hex($2), hex($3), hex($4), hex($5), hex($6), hex($7));
      my $tsgn = ($t & 0x4000);
      $t = ($t & 0x3fff)/10;
      $t = sprintf("%0.1f", $t-1638.4) if($tsgn);
      my $ir = $r & 0x8000;
      $r = ($r & 0x7fff) * 0.295;
      my $wdr = ($w>>14)*22.5;
      $w = ($w & 0x3fff)/10;
      $wd = $wd * 5;

      push @event,
        "state:T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b";
      push @event, "temperature:$t";
      push @event, "humidity:$h";
      push @event, "windSpeed:$w";
      push @event, "windDirection:$wd";
      push @event, "windDirRange:$wdr";
      push @event, "rain:$r";
      push @event, "isRaining:$ir";
      push @event, "sunshine:$s";
      push @event, "brightness:$b";
    } 
	else {
      push @event, "unknown:$p";
    }
  } 
  elsif($model eq "HM-CC-TC") { ###############################################
    my ($sType,$chn) = ($1,$2) if($p && $p =~ m/^(..)(..)/);
    if($msgType eq "70" && $p =~ m/^(....)(..)/) { # weather event
	  $chn = '01'; # fix definition
      my (    $t,      $h) =  (hex($1), hex($2));# temp is 15 bit signed
      $t = ($t & 0x3fff)/10*(($t & 0x4000)?-1:1);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  CUL_HM_UpdtReadBulk($chnHash,1,"state:T: $t H: $h",  # update weather channel
	                                 "measured-temp:$t",
	                                 "humidity:$h")
				  if ($chnHash);
      push @event, "state:T: $t H: $h";
      push @event, "measured-temp:$t";
      push @event, "humidity:$h";
    }
    elsif($msgType eq "58" && $p =~ m/^(..)(..)/) {# climate event
	  $chn = '02'; # fix definition
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $1, hex($2));
      $vp = int($vp/2.56+0.5);   # valve position in %
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  readingsSingleUpdate($chnHash,"state","$vp %",1) if($chnHash);
      push @event, "actuator:$vp %";

      # Set the valve state too, without an extra trigger
      readingsSingleUpdate($dhash,"state","set_$vp %",1) if($dhash);
    }
    elsif(($msgType eq '02' &&$sType eq '01')||    # ackStatus
	      ($msgType eq '10' &&$sType eq '06')){    # infoStatus
	  $chn = substr($p,2,2); 


	  my $temp = substr($p,4,2);
	  my $dTemp =  ($temp eq '00')?'off':
	              (($temp eq 'C8')?'on' :
				                    sprintf("%0.1f", hex($temp)/2));
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  if($chnHash){
	    my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-MdTempReg","");	
	    readingsSingleUpdate($chnHash,"desired-temp",$dTemp,1);
	    readingsSingleUpdate($chnHash,"desired-temp-manu",$dTemp,1) if($mode eq 'manual '  && $msgType eq '10');
#	    readingsSingleUpdate($chnHash,"desired-temp-cent",$dTemp,1) if($mode eq 'central ' && $msgType eq '02');
#		removed - shall not be changed automatically - change is  only temporary
#       CUL_HM_Set($chnHash,$chnName,"desired-temp",$dTemp)         if($mode eq 'central ' && $msgType eq '10');
       }
      push @event, "desired-temp:" .$dTemp;
    }
    elsif($msgType eq "10"){                       # Config change report
	  $chn = substr($p,2,2);
      if(   $p =~ m/^0403(......)(..)0505(..)0000/) {# param change
	    # change of chn 3(window) list 5 register 5 - a peer window changed!
        my ( $tdev,   $tchan,     $v1) = (($1), hex($2), hex($3));
	    push @event, sprintf("windowopen-temp-%d: %.1f (sensor:%s)"
	                        ,$tchan, $v1/2, $tdev);
							#todo: This will never cleanup if a peer is deleted
      }
	  elsif($p =~ m/^0402000000000(.)(..)(..)(..)(..)(..)(..)(..)(..)/) {
        # param list 5 or 6, 4 value pairs.
        my ($plist, $o1,    $v1,    $o2,    $v2,    $o3,    $v3,    $o4,    $v4) =
           (hex($1),hex($2),hex($3),hex($4),hex($5),hex($6),hex($7),hex($8),hex($9));

        my ($dayoff, $maxdays, $basevalue);
        my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");

        if($plist == 5 || $plist == 6) {
          if($plist == 5) {
            $dayoff = 0; $maxdays = 5; $basevalue = hex("0B");
          } 
		  else {
            $dayoff = 5; $maxdays = 2; $basevalue = hex("01");
          }
          my $idx = ($o1-$basevalue);
          my $dayidx = int($idx/48);
          if($idx % 4 == 0 && $dayidx < $maxdays) {
            $idx -= 48*$dayidx;
            $idx /= 2;
            my $ptr = $shash->{TEMPLIST}{$days[$dayidx+$dayoff]};
            $ptr->{$idx}{HOUR} = int($v1/6);
            $ptr->{$idx}{MINUTE} = ($v1%6)*10;
            $ptr->{$idx}{TEMP} = $v2/2;
            $ptr->{$idx+1}{HOUR} = int($v3/6);
            $ptr->{$idx+1}{MINUTE} = ($v3%6)*10;
            $ptr->{$idx+1}{TEMP} = $v4/2;
          }
        }
        foreach my $wd (@days) {
          my $twentyfour = 0;
          my $msg = 'tempList'.$wd.':';
          foreach(my $idx=0; $idx<24; $idx++) {
            my $ptr = $shash->{TEMPLIST}{$wd}{$idx};
            if(defined ($ptr->{TEMP}) && $ptr->{TEMP} ne "") {
              if($twentyfour == 0) {
                $msg .= sprintf(" %02d:%02d %.1f",
                                $ptr->{HOUR}, $ptr->{MINUTE}, $ptr->{TEMP});
              } else {
                $ptr->{HOUR} = $ptr->{MINUTE} = $ptr->{TEMP} = "";
              }
            }
            if($ptr->{HOUR} && 0+$ptr->{HOUR} == 24) {
              $twentyfour = 1;  # next value uninteresting, only first counts.
            }
      	  }
          push @event, $msg; # generate one event per day entry
        }
      } 
	  elsif($p =~ m/^04020000000005(..)(..)/) {   # paramchanged L5
        my ( $o1,    $v1) = (hex($1),hex($2));# only parse list 5 for chn 2
        my $msg;
        my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
        if($o1 == 1) { ### bitfield containing multiple values...
		               # MUST be IDENTICAL to the set commands assotiated
	      my %mode = (0 => "manual",1 => "auto",2 => "central",3 => "party");
          push @event,'displayMode:temp-'.(($v1 & 1)?"hum"       :"only");
          push @event,'displayTemp:'     .(($v1 & 2)?"setpoint"  :"actual");
          push @event,'displayTempUnit:' .(($v1 & 4)?"fahrenheit":"celsius");
          push @event,'controlMode:'     .($mode{(($v1 & 0x18)>>3)});
          push @event,'decalcDay:'       .$days[($v1 & 0xE0)>>5];
	      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
          my $dTemp;
	      if($chnHash){
	        my $chnName = $chnHash->{NAME};
            my $mode = ReadingsVal($chnName,"R-MdTempReg","");	
            $dTemp = ReadingsVal($chnName,"desired-temp","21.0");
		    if (!$chnHash->{helper}{oldMode} || $chnHash->{helper}{oldMode} ne $mode){
		      $dTemp = ReadingsVal($chnName,"desired-temp-manu",$dTemp)if ($mode eq 'manual ');
		      $dTemp = ReadingsVal($chnName,"desired-temp-cent",$dTemp)if ($mode eq 'central ');
		      $chnHash->{helper}{oldMode} = $mode;
		    }
	        readingsSingleUpdate($chnHash,"desired-temp",$dTemp,1);
           }
          push @event, "desired-temp:" .$dTemp;
        } 
	    elsif($o1 == 2) {
	      my %pos = (0=>"Auto",1=>"Closed",2=>"Open",3=>"unknown");		  
          push @event,"tempValveMode:".$pos{(($v1 & 0xC0)>>6)};
        } 
	    else{
	      push @event,'param-change: offset='.$o1.', value='.$v1;
	    }
      }
	  elsif($p =~ m/^0[23]/){                     # param response
	    push @event,'';#cannot be handled here as request missing
	  }
	}
    elsif($msgType eq "01"){                       # status reports
      if($p =~ m/^010809(..)0A(..)/) { # TC set valve  for VD => post events to VD
        my (   $of,     $vep) = (hex($1), hex($2));
        push @event, "ValveErrorPosition_for_$dname: $vep %";
        push @event, "ValveOffset_for_$dname: $of %";
		CUL_HM_UpdtReadBulk($dhash,1,'ValveErrorPosition:set_'.$vep.' %',
		                             'ValveOffset:set_'.$of.' %');
	  }
	  elsif($p =~ m/^010[56]/){ # 'prepare to set' or 'end set'
	  	push @event,""; # 
	  }
    }
    elsif($cmd eq "A03F" && $id eq $dst) {         # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      CUL_HM_SndCmd($shash, "++803F$id${src}0204$s2000");
      push @event, "time-request";
	  $sendAck = ""; 
    } 
  } 
  elsif($model eq "HM-CC-VD") { ###############################################
    # CMD:8202 SRC:13F251 DST:15B50D 010100002A
    # status ACK to controlling HM-CC-TC
    if($msgType eq "02" && $p =~ m/^(..)(..)(..)(..)/) {#subtype+chn+value+err
      my ($chn,$vp, $err) = ($2,hex($3), hex($4));
      $vp = int($vp)/2;   # valve position in %
	  push @event, "ValvePosition:$vp %";
      push @event, "state:$vp %";
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

      # Status-Byte Auswertung

	  my $stErr = ($err >>1) & 0x7;    
	  push @event,"battery:".(($stErr == 4)?"critical":($err&0x80?"low":"ok"));  
	  if (!$stErr){#remove both conditions
        push @event, "motorErr:ok";
	  }
	  else{
        push @event, "motorErr:blocked"                   if($stErr == 1);
        push @event, "motorErr:loose"                     if($stErr == 2);
        push @event, "motorErr:adjusting range too small" if($stErr == 3);
#		push @event, "battery:critical"                   if($stErr == 4);
	  }
      push @event, "motor:opening" if(($err&0x30) == 0x10);
      push @event, "motor:closing" if(($err&0x30) == 0x20);
      push @event, "motor:stop"    if(($err&0x30) == 0x00);
	  push @event, ""; # just in case - mark message as confirmed
    }


    # CMD:A010 SRC:13F251 DST:5D24C9 0401 00000000 05 09:00 0A:07 00:00
    # status change report to paired central unit
	#read List5 reg 09 (offset) and 0A (err-pos)
	#list 5 is channel-dependant not link dependant
	#        => Link discriminator (00000000) is fixed
    elsif($msgType eq "10" && $p =~ m/^04..........0509(..)0A(..)/) {
      my (    $of,     $vep) = (hex($1), hex($2));
      push @event, "ValveErrorPosition:$vep %";
      push @event, "ValveOffset:$of %";
    }
  } 
  elsif($model eq "HM-Sen-Wa-Od"||
        $model eq "HM-CC-SCD"   ){ ############################################
    if (($msgType eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
	    ($msgType eq "10" && $p =~ m/^06/) ||  #or Info_Status message here
	    ($msgType eq "41"))                { 
	  my $level = substr($p,4,2);
	  my %lvl=("00"=>"normal","64"=>"added","C8"=>"addedStrong");
      $level = hex($level)   if($model eq "HM-Sen-Wa-Od");
	  $level = $lvl{$level}  if($model eq "HM-CC-SCD");
	  push @event, "state:".$level."%";
	  
	  my $err = hex(substr($p,6,2));
	  push @event, "battery:".($err&0x80?"low":"ok") if (defined $err);
	}  
  }
  elsif($st eq "KFM100" && $model eq "KFM-Sensor") { ##########################
    if ($msgType eq "53"){
      if($p =~ m/.14(.)0200(..)(..)(..)/) {
        my ($seq, $k_v1, $k_v2, $k_v3) = (hex($1),$2,hex($$3),hex($4));
        my $v = 128-$k_v2;                  # FIXME: calibrate
        $v += 256 if(!($k_v3 & 1));
        push @event, "rawValue:$v";
        my $nextSeq = (ReadingsVal($name,"Sequence","") %15)+1;
        push @event, "Sequence:$seq".($nextSeq ne $seq?"_seqMiss":"");
      
        my $r2r = AttrVal($name, "rawToReadable", undef);
        if($r2r) {
          my @r2r = split("[ :]", $r2r);
          foreach(my $idx = 0; $idx < @r2r-2; $idx+=2) {
            if($v >= $r2r[$idx] && $v <= $r2r[$idx+2]) {
              my $f = (($v-$r2r[$idx])/($r2r[$idx+2]-$r2r[$idx]));
              my $cv = ($r2r[$idx+3]-$r2r[$idx+1])*$f + $r2r[$idx+1];
              my $unit = AttrVal($name, "unit", "");
              push @event, sprintf("state:%.1f %s",$cv,$unit);
              push @event, sprintf("content:%.1f %s",$cv,$unit);
              last;
            }
          }
        } else {
          push @event, "state:$v";
        }
      }
	}
  } 
  elsif($st eq "switch" || ####################################################
        $st eq "dimmer" ||
        $st eq "blindActuator") {
    if (($msgType eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
	    ($msgType eq "10" && $p =~ m/^06/))	{ #    or Info_Status message here

      my ($subType,$chn,$val,$err) = ($1,$2,hex($3)/2,hex($4)) 
 	                     if($p =~ m/^(..)(..)(..)(..)/);
      my ($x,$pl) = ($1,hex($2)/2)  if($p =~ m/^........(..)(..)/);
	  if (defined $pl){# device with virtual channels...
	    $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
	    push @event, "virtLevel:$val";
		$val = $pl;
	  }

      # Multi-channel device: Use channel if defined
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
      $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
      push @event, "deviceMsg:$val$target" if($chn ne "00");

      my $eventName = "unknown"; # different names for events
      $eventName = "switch"  if($st eq "switch");
      $eventName = "motor"   if($st eq "blindActuator");
	  $eventName = "dim"     if($st eq "dimmer");
	  my $action; #determine action
	  if ($st ne "switch"){
        push @event, "$eventName:up:$val"   if(($err&0x30) == 0x10);
        push @event, "$eventName:down:$val" if(($err&0x30) == 0x20);
        push @event, "$eventName:stop:$val" if(($err&0x30) == 0x00);
	  }
	  if ($st eq "dimmer"){
        push @event,"overload:".(($err&0x02)?"on":"off");
        push @event,"overheat:".(($err&0x04)?"on":"off");
        push @event,"reduced:" .(($err&0x08)?"on":"off");
	     #hack for blind  - other then behaved devices blind does not send
		 #        a status info for chan 0 at power on
		 #        chn3 (virtual chan) and not used up to now
		 #        info from it is likely a power on!
	    push @event,"powerOn"   if($chn eq "03");
	  }
	  elsif ($model eq "HM-SEC-SFA-SM"){ # && $chn eq "00")
  	    CUL_HM_UpdtReadBulk(CUL_HM_getDeviceHash($shash),1,
		        "powerError:"   .(($err&0x02) ? "on":"off"),
	            "sabotageError:".(($err&0x04) ? "on":"off"),
	            "battery:".(($err&0x08)?"critical":($err&0x80?"low":"ok")));
	  }
	  elsif ($model eq "HM-LC-SW1-BA-PCB"){
	    push @event, "battery:" . (($err&0x80) ? "low" : "ok" );
	  }
	  push @event, "state:$val";
    }
  } 
  elsif($st eq "remote" || $st eq "pushButton" || $st eq "swi") { #############
    if($msgType =~ m/^4./ && $p =~ m/^(..)(..)$/) {
      my ($buttonField, $bno) = (hex($1), hex($2));# button number/event count
	  my $buttonID = $buttonField&0x3f;# only 6 bit are valid
	  my $btnName;
	  my $state = "";
      my $chnHash = $modules{CUL_HM}{defptr}{$src.uc(sprintf("%02x",$buttonID))};	  
	  
	  if ($chnHash){# use userdefined name - ignore this irritating on-off naming
		$btnName = $chnHash->{NAME};
	  }
	  else{# Button not defined, use default naming
	    $chnHash = $shash;
	    if ($st eq "swi"){#maintain history for event naming
			$btnName = "Btn$buttonField";
		}
		else{
			my $btn = int((($buttonField&0x3f)+1)/2);
			$btnName = "Btn$btn";
			$state = ($buttonField&1 ? "off" : "on")
		}
	  }

      if($buttonField & 0x40){
		if(!$shash->{BNO} || $shash->{BNO} ne $bno){#bno = event counter
			$shash->{BNO}=$bno;
			$shash->{BNOCNT}=1; # message counter reest
		}
		$shash->{BNOCNT}+=1;
        $state .= "Long" .($msgFlag eq "A0" ? "Release" : "").
				  " ".$shash->{BNOCNT}."-".$cmd."-";
      }
	  else{
        $state .= ($st eq "swi")?"toggle":"Short";#swi only support toggle
      }
	  $shash->{helper}{addVal} = $buttonField;   #store to handle changes
	  readingsSingleUpdate($chnHash,"state",$state.$target,1);#trig chan also 
      push @event,"battery:". (($buttonField&0x80)?"low":"ok");
      push @event,"state:$btnName $state$target";
    }
  }
  elsif($st eq "repeater"){ ###################################################
    if (($msgType eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
        ($msgType eq "10" && $p =~ m/^06/)) {  #or Info_Status message here
      my ($state,$err) = ($1,hex($2)) if ($p =~ m/^....(..)(..)/);
      # not sure what level are possible
      push @event, "state:".($state eq '00'?"ok":"level:".$state);
      push @event, "battery:".   (($err&0x80)?"low"  :"ok"  );
      my $flag = ($err>>4) &0x7;
      push @event, "flags:".     (($flag)?"none"     :$flag  );
	}
  }
  elsif($st eq "virtual"){#####################################################
    # possibly add code to count all acks that are paired. 
    if($msgType eq "02") {# this must be a reflection from what we sent, ignore
      push @event, "";
	}
  }
  elsif($st eq "outputUnit"){##################################################
    if($msgType eq "40" && $p =~ m/^(..)(..)$/){
      my ($button, $bno) = (hex($1), hex($2));
      if(!(exists($shash->{BNO})) || $shash->{BNO} ne $bno){
        $shash->{BNO}=$bno;
		  $shash->{BNOCNT}=1;
      }
	  else{
        $shash->{BNOCNT}+=1;
      }
      my $btn = int($button&0x3f);
      push @event, "state:Btn$btn on$target";
    }
	elsif(($msgType eq "02" && $p =~ m/^01/) ||   # handle Ack_Status
	      ($msgType eq "10" && $p =~ m/^06/)){    #    or Info_Status message
	  my ($msgChn,$msgState) = ($1,$2) if ($p =~ m/..(..)(..)/);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$msgChn};
	  if ($model eq "HM-OU-LED16") {
	    #special: all LEDs map to device state
        my $devState = ReadingsVal($name,"color","00000000");
		if($parse eq "powerOn"){# reset LEDs after power on
		  CUL_HM_PushCmdStack($shash,'++A011'.$id.$src."8100".$devState);
		  CUL_HM_ProcessCmdStack($shash);
		  # no event necessary, all the same as before
		}
		else {# just update datafields in storage
 	      my $bitLoc = ((hex($msgChn)-1)*2);#calculate bit location
 	      my $mask = 3<<$bitLoc;
 	      my $value = sprintf("%08X",(hex($devState) &~$mask)|($msgState<<$bitLoc));
		  CUL_HM_UpdtReadBulk($shash,1,"color:".$value,
		                               "state:".$value);
 	      if ($chnHash){
 	        $shash = $chnHash;
 	        my %colorTable=("00"=>"off","01"=>"red","02"=>"green","03"=>"orange");
 	        my $actColor = $colorTable{$msgState};
 	        $actColor = "unknown" if(!$actColor);
		    push @event, "color:$actColor";           #todo duplicate
            push @event, "state:$actColor";			
 	      }
		}
	  }
	  elsif ($model eq "HM-OU-CFM-PL"){
	    if ($chnHash){
	      $shash = $chnHash;
	      my $val = hex($msgState)/2;
          $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
          push @event, "state:$val";			
	    }
	  }
	}  
  } 
  elsif($st eq "motionDetector") { ############################################
    # Code with help of Bassem
    my $state;
    if(($msgType eq "10" ||$msgType eq "02") && $p =~ m/^0601(..)(..)/) {
	  my $err;
      ($state, $err) = ($1, hex($2));
	  my $bright = hex($state);
      push @event, "brightness:".$bright;
      push @event, "cover:".     (($err&0x0E)?"open" :"closed");        
	  push @event, "battery:".   (($err&0x80)?"low"  :"ok"  );
    }
    elsif($msgType eq "41" && $p =~ m/^01(..)(..)(..)/) {#01 is channel
	  my($cnt,$bright,$nextTr);
      ($cnt,$state,$nextTr)	  = (hex($1),$2,(hex($3)>>4));
	  $bright = hex($state);
	  my @nextVal = ("0x0","0x1","0x2","0x3","15" ,"30" ,"60" ,"120",
	                 "240","0x9","0xa","0xb","0xc","0xd","0xe","0xf");
      push @event, "state:motion";
      push @event, "motion:on$target"; #added peterp
      push @event, "motionCount:".$cnt."_next:".$nextTr."-".$nextVal[$nextTr];
      push @event, "brightness:".$bright;
    }
    elsif($msgType eq "70" && $p =~ m/^7F(..)(.*)/) {
	  my($d1, $d2) = ($1, $2);
      push @event, 'devState_raw'.$d1.':'.$d2;
    }
	
	if($id eq $dst && $cmd ne "8002" && $state){
      CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."0101${state}00");
	  $sendAck = ""; #todo why is this special?
	}
  } 
  elsif($st eq "smokeDetector") { #############################################
	#Info Level: msgType=0x10 p(..)(..)(..) subtype=06, channel, state (1 byte)
	#Event:      msgType=0x41 p(..)(..)(..) channel   , unknown, state (1 byte)

	if ($msgType eq "10" && $p =~ m/^06..(..)/) {
	  my $state = hex($1);
      push @event, "battery:". (($state&0x04)?"low"  :"ok"  );
      push @event, "state:alive";
    } 
    elsif ($msgType eq "40"){ #autonomous event
	  if($dhash){ # the source is in dst
	    my ($state,$trgCnt) = (hex(substr($p,0,2)),hex(substr($p,2,2)));
		readingsSingleUpdate($dhash,'test',"from $dname:$state",1)
		      if (!($state & 1));
		readingsSingleUpdate($dhash,'battery',(($state & 0x04)?"low":"ok"),1)
		      if($state&0x80);
	  }
      push @event, "";
    }
    elsif ($msgType eq "41"){ #Alarm detected
	  my ($No,$state) = (substr($p,2,2),substr($p,4,2));
	  if($dhash && $dname ne $name){ # update source(ID is reported in $dst...)
	    if (!$dhash->{helper}{alarmNo} || $dhash->{helper}{alarmNo} ne $No){
		  $dhash->{helper}{alarmNo} = $No;
		  readingsSingleUpdate($dhash,'state',
		                              (($state eq "01")?"off":
									  (($state eq "C7")?"smoke-forward":
									                    "smoke-alarm")),1);
		}
	  }
	  # - - - - - - now handle the team - - - - - - 
	  $shash->{helper}{alarmList} = "" if (!$dhash->{helper}{alarmList});
	  $shash->{helper}{alarmFwd}  = "" if (!$dhash->{helper}{alarmFwd});
	  if ($state eq "01") { # clear Alarm for one sensor
		$shash->{helper}{alarmList} =~ s/",".$dst//;
	  }
	  elsif($state eq "C7"){# add alarm forwarding
		$shash->{helper}{alarmFwd} .= ",".$dst;
	  }
	  else{                 # add alarm for Sensor
		$shash->{helper}{alarmList} .= ",".$dst;
	  }
	  my $alarmList; # make alarm ID list readable
	  foreach(split(",",$shash->{helper}{alarmList})){
	    $alarmList .= CUL_HM_id2Name($_)."," if ($_);
	  }
	  if (!$alarmList){# all alarms are gone - clear forwarding
		  foreach(split(",",$shash->{helper}{alarmFwd})){	
			my $fHash = CUL_HM_id2Hash($1) if ($1);
		    readingsSingleUpdate($fHash,'state',"off",1)if ($fHash);
		  }
		$shash->{helper}{alarmList} = "";
		$shash->{helper}{alarmFwd}  = "";
	  }
	  my $alarmFwd; # make forward ID list readable
	  foreach(split(",",$shash->{helper}{alarmFwd})){
	    $alarmFwd .= CUL_HM_id2Name($_)."," if ($_);
	  }
      push @event,"state:"        .($alarmList?"smoke-Alarm":"off" );
      push @event,"smoke_detect:" .($alarmList?$alarmList   :"none");
      push @event,"smoke_forward:".($alarmFwd ?$alarmFwd    :"none");
    } 
    elsif ($msgType eq "01"){ #Configs
	  my $sType = substr($p,0,2);
	  if($sType eq "01"){#add peer to group
		push @event,"SDteam:add_".$dname;
	  }
	  elsif($sType eq "02"){# remove from group
		push @event,"SDteam:remove_".$dname;
	  }
	  elsif($sType eq "05"){# set param List 3 and 4
		push @event,"";
	  }
	}
	else{
      push @event, "SDunknownMsg:$p" if(!@event);
	}
	
	if($id eq $dst && (hex($msgFlag)&0x20)){  # Send Ack/Nack
      CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src.($cmd eq "A001" ? "80":"00"));
      $sendAck = ""; #todo why is this special?
	}
  } 
  elsif($st eq "threeStateSensor") { ##########################################
    #todo: check for correct msgType, see below
	#Event:      msgType=0x41 p(..)(..)(..)     channel   , unknown, state
	#Info Level: msgType=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  msgType=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)
	my ($chn,$state,$err,$cnt); #define locals
    if($msgType eq "10" || $msgType eq "02"){
	  my $mT = $msgType.substr($p,0,2);
	  if ($mT eq "1006" ||$$mT eq "0201"){
	    $p =~ m/^..(..)(..)(..)?$/;
        ($chn,$state,$err) = ($1, $2, hex($3));
		$shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
		push @event, "alive:yes";
	    push @event, "battery:". (($err&0x80)?"low"  :"ok"  );
		if ($model ne "HM-SEC-WDS"){	  
		  push @event, "cover:". (($err&0x0E)?"open" :"closed");
	    }
	  }
	}
	elsif($msgType eq "41"){
	  ($chn,$cnt,$state)=($1,$2,$3) if($p =~ m/^(..)(..)(..)/);
	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	
	}

	if (defined($state)){# if state was detected post events
      my %txt;
      %txt = ("C8"=>"open", "64"=>"tilted", "00"=>"closed");
      %txt = ("C8"=>"wet",  "64"=>"damp",   "00"=>"dry")  
                 if($model eq "HM-SEC-WDS");
	  my $txt = $txt{$state};
	  $txt = "unknown:$state" if(!$txt);
	  push @event, "state:$txt";
	  push @event, "contact:$txt$target";
	  
    }
    else{push @event, "3SSunknownMsg:$p" if(!@event);}
  } 
  elsif($model eq "HM-WDC7000" ||$st eq "THSensor") { #########################
    my $t =  hex(substr($p,0,4));
    $t -= 32768 if($t > 1638.4);
    $t = sprintf("%0.1f", $t/10);
    my $h =  hex(substr($p,4,2));
    my $ap = hex(substr($p,6,4));
    my $statemsg = "state:T: $t";
    $statemsg .= " H: $h"   if ($h);
    $statemsg .= " AP: $ap" if ($ap);
    push @event, $statemsg;
    push @event, "temperature:$t";#temp is always there
    push @event, "humidity:$h"      if ($h);
    push @event, "airpress:$ap"     if ($ap);
  } 
  elsif($st eq "winMatic") {  #################################################
    my($sType,$chn,$lvl,$stat) = ($1,$2,$3,$4) if ($p =~ m/^(..)(..)(..)(..)/);
    if(($msgType eq "10" && $sType eq "06") ||
	   ($msgType eq "02" && $sType eq "01")){
	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
	  # stateflag meaning unknown
	  push @event, "state:".(($lvl eq "FF")?"locked":((hex($lvl)/2)." %"));
	  if ($chn eq "01"){
	    my %err = (0=>"no",1=>"TurnError",2=>"TiltError");
	    my %dir = (0=>"no",1=>"up",2=>"down",3=>"undefined");
	    push @event, "motorError:".$err{(hex($stat)>>1)&0x02};
	    push @event, "direction:".$dir{(hex($stat)>>4)&0x02};
#	  CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."0101".$lst."00")  
#          if($id eq $dst);# Send AckStatus
#	  $sendAck = "";
	  }
	  else{ #should be akku
	    my %statF = (0=>"trickleCharge",1=>"charge",2=>"dischange",3=>"unknown");
	    push @event, "charge:".$statF{(hex($stat)>>4)&0x02}; 
	  }
	}
	if ($p =~ m/^0287(..)89(..)8B(..)/) {
	  my ($air, undef, $course) = ($1, $2, $3);
      push @event, "airing:".($air eq "FF" ? "inactiv" : CUL_HM_decodeTime8($air));
      push @event, "course:".($course eq "FF" ? "tilt" : "close");
	}
	elsif($p =~ m/^0201(..)03(..)04(..)05(..)07(..)09(..)0B(..)0D(..)/) {
      my ($flg1, $flg2, $flg3, $flg4, $flg5, $flg6, $flg7, $flg8) =
         ($1, $2, $3, $4, $5, $6, $7, $8);
      push @event, "airing:".($flg5 eq "FF" ? "inactiv" : CUL_HM_decodeTime8($flg5));
      push @event, "contact:tesed";
	}
  }
  elsif($st eq "keyMatic") {  #################################################
	#Info Level: msgType=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  msgType=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if(($msgType eq "10" && $p =~ m/^06/) ||
	   ($msgType eq "02" && $p =~ m/^01/)) {
	  $p =~ m/^..(..)(..)(..)/; 
      my ($chn,$val, $err) = ($1,hex($2), hex($3));
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

      my $stErr = ($err >>1) & 0x7;      
      my $error = 'unknown_'.$stErr;
      $error = 'motor aborted'  if ($stErr == 2);
      $error = 'clutch failure' if ($stErr == 1);
      $error = 'none'           if ($stErr == 0);
      my %dir = (0=>"none",1=>"up",2=>"down",3=>"undef");

      push @event, "unknown:40" if($err&0x40);
	  push @event, "battery:"   .(($err&0x80) ? "low":"ok");
      push @event, "uncertain:" .(($err&0x30) ? "yes":"no");
      push @event, "direction:" .$dir{($err>>4)&3};
      push @event, "error:" .    ($error);
      my $state = ($err & 0x30) ? " (uncertain)" : "";
      push @event, "lock:"	.	(($val == 1) ? "unlocked" : "locked");
      push @event, "state:"	.	(($val == 1) ? "unlocked" : "locked") . $state;
    }
  }  
  else{########################################################################
    ; # no one wants the message
  }

  #------------ parse if FHEM or virtual actor is destination   ---------------

  if(AttrVal($dname, "subType", "none") eq "virtual"){# see if need for answer
    if($msgType =~ m/^4./ && $p =~ m/^(..)(..)/) { #Push Button event
      my ($recChn,$trigNo) = (hex($1),hex($2));# button number/event count
	  my $longPress = ($recChn & 0x40)?"long":"short";
	  my $recId = $src.sprintf("%02X",($recChn&0x3f));
	  foreach my $dChId (CUL_HM_getAssChnIds($dname)){# need to check all chan
	    next if (!$modules{CUL_HM}{defptr}{$dChId});
		my $dChNo = substr($dChId,6,2);
		my $dChName = CUL_HM_id2Name($dChId);

		if (AttrVal($dChName,"peerIDs","") =~m/$recId/){# is in peerlist?
		  my $dChHash = CUL_HM_name2Hash($dChName);
		  $dChHash->{helper}{trgLgRpt} = 0 
		        if (!defined($dChHash->{helper}{trgLgRpt}));
		  $dChHash->{helper}{trgLgRpt} +=1;
		  my $trgLgRpt = $dChHash->{helper}{trgLgRpt};
		  
		  my $state  = ReadingsVal($dChName,"virtActState","OFF");
		  my $tNoOld = ReadingsVal($dChName,"virtActTrigNo","0");
		  $state = ($state eq "OFF")?"ON":"OFF" if ($trigNo ne $tNoOld);
		  if (hex($msgFlag)&0x20){
		    $longPress .= "_Release";
			$dChHash->{helper}{trgLgRpt}=0;
		    CUL_HM_SndCmd($dhash,$msgcnt."8002".$dst.$src.'01'.$dChNo.
                  (($state eq "ON")?"C8":"00")."00");
			$sendAck = "";
		  }
		  CUL_HM_UpdtReadBulk($dChHash,1,"state:".$state,
		                           "virtActState:".$state,
			                       "virtActTrigger:".CUL_HM_id2Name($recId),
						           "virtActTrigType:".$longPress,
						           "virtActTrigRpt:".$trgLgRpt,
						           "virtActTrigNo:".$trigNo	);
        }	
	  }
	}
	elsif($msgType eq "58" && $p =~ m/^(..)(..)/) {# climate event
      my ($d1,$vp) =($1,hex($2)); # adjust_command[0..4] adj_data[0..250]
      $vp = int($vp/2.56+0.5);    # valve position in %
	  my $chnHash = $modules{CUL_HM}{defptr}{$dst."01"};
 	  CUL_HM_UpdtReadBulk($chnHash,1,"ValvePosition:$vp %",
	                               "ValveAdjCmd:".$d1);
      CUL_HM_SndCmd($chnHash,$msgcnt."8002".$dst.$src.'0101'.
	                       sprintf("%02X",$vp*2)."0000");#$vp, $err,$??
	  $sendAck = "";
	}
	elsif($msgType eq "02"){
	  if ($dhash->{helper}{respWait}{msgId}             && 
	      $dhash->{helper}{respWait}{msgId} eq $msgcnt ){
	    #ack we waited for - stop Waiting
	    CUL_HM_respPendRm($dhash);
	  } 
	}
	if (hex($msgFlag)&0x20 && ($sendAck eq "yes")){
	  CUL_HM_SndCmd($dhash, $msgcnt."8002".$dst.$src."00");#virtual must ack
	}
  }
  elsif($id eq $dst){# if fhem is destination check if we need to react
    if($msgType =~ m/^4./ && $p =~ m/^(..)/ &&  #Push Button event
	   (hex($msgFlag)&0x20)){ 	#response required Flag
      my ($recChn) = ($1);# button number/event count
	            # fhem CUL shall ack a button press
      CUL_HM_SndCmd($shash, $msgcnt."8002".$dst.$src."0101".
                ((hex($recChn)&1)?"C8":"00")."00");#Actor simulation
      $sendAck = "";
	}
  }
  
  #------------ send default ACK if not applicable------------------
  #    ack if we are destination, anyone did accept the message (@event)
  #        parser did not supress 
  CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."00")  # Send Ack
      if(   ($id eq $dst) 			#are we adressee 
	     && (hex($msgFlag)&0x20) 	#response required Flag
		 && @event  				#only ack of we identified it
		 && ($sendAck eq "yes")		#sender requested ACK
		 );  	
		 
  CUL_HM_ProcessCmdStack($shash) if ($respRemoved); # cont stack if a response is complete
  #------------ process events ------------------

  push @event, "noReceiver:src:$src ($cmd) $p" if(!@event);
  CUL_HM_UpdtReadBulk($shash,1,@event); #events to the channel
  $defs{$shash->{NAME}}{EVENTS}++;  # count events for channel
  return $name ;#general notification to the device
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
my %culHmRegDefShLg = (# register that are available for short AND long button press. Will be merged to rgister list at init
#blindActuator mainly   
  ActionType      =>{a=> 10.0,s=>0.2,l=>3,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3}},
  OffTimeMode     =>{a=> 10.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"off time mode",lit=>{absolut=>0,minimal=>1}},
  OnTimeMode      =>{a=> 10.7,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"on time mode" ,lit=>{absolut=>0,minimal=>1}},
  MaxTimeF        =>{a=> 29.0,s=>1.0,l=>3,min=>0  ,max=>25.4    ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"max time first direction"},
  DriveMode       =>{a=> 31.0,s=>1.0,l=>3,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{direct=>0,viaUpperEnd=>1,viaLowerEnd=>2,viaNextEnd=>3}},
#dimmer mainly                                                                                 
  OnDly           =>{a=>  6.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on delay "},
  OnTime          =>{a=>  7.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on time"},
  OffDly          =>{a=>  8.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off delay"},
  OffTime         =>{a=>  9.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off time"},

  ActionTypeDim   =>{a=> 10.0,s=>0.4,l=>3,min=>0  ,max=>8       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
  OffDlyBlink     =>{a=> 14.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{off=>0,on=>1}},
  OnLvlPrio       =>{a=> 14.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{high=>0,low=>1}},
  OnDlyMode       =>{a=> 14.7,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{setToOff=>0,NoChange=>1}},
  OffLevel        =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"PowerLevel Off"},
  OnMinLevel      =>{a=> 16.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"minimum PowerLevel"},
  OnLevel         =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>1,t=>"PowerLevel on"},

  OffLevelKm      =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnLevelKm       =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnRampOnSp      =>{a=> 34.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp On speed"},
  OnRampOffSp     =>{a=> 35.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp Off speed"},

  RampSstep       =>{a=> 18.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"rampStartStep"},
  RampOnTime      =>{a=> 19.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOnTime"},
  RampOffTime     =>{a=> 20.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOffTime"},
  DimMinLvl       =>{a=> 21.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMinLevel"},
  DimMaxLvl       =>{a=> 22.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMaxLevel"},
  DimStep         =>{a=> 23.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimStep"},

  OffDlyNewTime   =>{a=> 25.0,s=>1.0,l=>3,min=>0.1,max=>25.6    ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"off delay new time"},
  OffDlyNewTime   =>{a=> 26.0,s=>1.0,l=>3,min=>0.1,max=>25.6    ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"off delay old time"},
  DimElsOffTimeMd =>{a=> 38.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{absolut=>0,minimal=>1}},
  DimElsOnTimeMd  =>{a=> 38.7,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{absolut=>0,minimal=>1}},
  DimElsActionType=>{a=> 38.0,s=>0.4,l=>3,min=>0  ,max=>8       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
#output Unit                                                                                       
  ActType         =>{a=> 36  ,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Action type(LED or Tone)"},
  ActNum          =>{a=> 37  ,s=>1  ,l=>3,min=>1  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Action Number"},
  Intense         =>{a=> 43  ,s=>1  ,l=>3,min=>10 ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Volume",lit=>{vol_0=>255,vol_1=>250,vol_2=>246,vol_3=>240,vol_4=>234,vol_5=>227,vol_6=>218,vol_7=>207,vol_8=>190,vol_9=>162,vol_00=>10}},  
# statemachines
  BlJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOn      =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOff     =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOn       =>{a=> 28.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOn"   ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOff      =>{a=> 28.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOff"  ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  
  DimJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtDlyOn      =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtDlyOff     =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},

  DimElsJtOn      =>{a=> 39.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from On"      ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimElsJtOff     =>{a=> 39.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from Off"     ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimElsJtDlyOn   =>{a=> 40.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimElsJtDlyOff  =>{a=> 40.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOff",lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimElsJtRampOn  =>{a=> 41.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimElsJtRampOff =>{a=> 41.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  
  SwJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},

  KeyJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,lock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},
  KeyJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,lock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},

  WinJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,ramoOffDly=>4,rampOff=>5,Off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,ramoOffDly=>4,rampOff=>5,Off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,ramoOffDly=>4,rampOff=>5,Off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,ramoOffDly=>4,rampOff=>5,Off=>6,rampOnFast=>8,rampOffFast=>9}},
  
  CtRampOn        =>{a=>  1.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOn"   ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRampOff       =>{a=>  1.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOff"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOn         =>{a=>  2.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOn"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOff        =>{a=>  2.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOff" ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOn            =>{a=>  3.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from On"       ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOff           =>{a=>  3.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from Off"      ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtValLo         =>{a=>  4.0,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Condition value low for CT table"  },
  CtValHi         =>{a=>  5.0,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Condition value high for CT table" },
  CtRefOn         =>{a=> 28.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOn"    ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRefOff        =>{a=> 28.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOff"   ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
);

my %culHmRegDefine = (
  intKeyVisib     =>{a=>  2.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>'visibility of internal channel',lit=>{invisib=>0,visib=>1}},
  pairCentral     =>{a=> 10.0,s=>3.0,l=>0,min=>0  ,max=>16777215,c=>'hex'      ,f=>''      ,u=>''    ,d=>1,t=>'pairing to central'},
#blindActuator mainly                                                                             
  lgMultiExec     =>{a=>138.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"multiple execution per repeat of long trigger"    ,lit=>{off=>0,on=>1}},
  driveDown       =>{a=> 11.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveUp         =>{a=> 13.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveTurn       =>{a=> 15.0,s=>1.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"fliptime up <=>down"},
  refRunCounter   =>{a=> 16.0,s=>1.0,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"reference run counter"},
  
#repeater                                                                                      
  compMode        =>{a=> 23.0,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"compatibility moden"   ,lit=>{off=>0,on=>1}},
#remote mainly                                                                                      
  language        =>{a=>  7.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Language"              ,lit=>{English=>0,German=>1}},
  backAtKey       =>{a=> 13.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at keystroke",lit=>{off=>0,on=>1}},
  backAtMotion    =>{a=> 13.6,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at motion"   ,lit=>{off=>0,on=>1}},
  backAtCharge    =>{a=> 13.5,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at Charge"   ,lit=>{off=>0,on=>1}},
  stbyTime        =>{a=> 14.0,s=>1.0,l=>0,min=>1  ,max=>99      ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Standby Time"},
  backOnTime      =>{a=> 14.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Backlight On Time"},

  longPress       =>{a=>  4.4,s=>0.4,l=>1,min=>0.3,max=>1.8     ,c=>'m10s3'    ,f=>''      ,u=>'s'   ,d=>0,t=>"time to detect key long press"},
  dblPress        =>{a=>  9.0,s=>0.4,l=>1,min=>0  ,max=>1.5     ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"time to detect double press"},
  msgShowTime     =>{a=> 45.0,s=>1.0,l=>1,min=>0.0,max=>120     ,c=>'factor'   ,f=>2       ,u=>'s'   ,d=>1,t=>"Message show time(RC19). 0=always on"},
  beepAtAlarm     =>{a=> 46.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Alarm"        ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtService   =>{a=> 46.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Service"      ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtInfo      =>{a=> 46.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Info"         ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  backlAtAlarm    =>{a=> 47.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Alarm"   ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtService  =>{a=> 47.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Service" ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtInfo     =>{a=> 47.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Info"    ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},

  peerNeedsBurst  =>{a=>  1.0,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"peer expects burst",lit=>{off=>0,on=>1}},
  expectAES       =>{a=>  1.7,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"expect AES"        ,lit=>{off=>0,on=>1}},
  lcdSymb         =>{a=>  2.0,s=>0.1,l=>4,min=>0  ,max=>255     ,c=>'hex'      ,f=>''      ,u=>''    ,d=>0,t=>"bitmask which symbol to display on message"},
  lcdLvlInterp    =>{a=>  3.0,s=>0.1,l=>4,min=>0  ,max=>255     ,c=>'hex'      ,f=>''      ,u=>''    ,d=>0,t=>"bitmask fro symbols"},
#dimmer  mainly                                                                                  
  loadErrCalib	  =>{a=> 18.0,s=>1.0,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>""    ,d=>0,t=>"Load Error Calibration"},
  transmitTryMax  =>{a=> 48.0,s=>1.0,l=>1,min=>1  ,max=>10      ,c=>''         ,f=>''      ,u=>""    ,d=>0,t=>"max message re-transmit"},
  loadAppearBehav =>{a=> 49.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>"behavior on load appearence at restart",lit=>{off=>0,last=>1,btnPress=>2,btnPressIfWasOn=>3}},
  ovrTempLvl      =>{a=> 50.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>0,t=>"overtemperatur level"},
  fuseDelay		  =>{a=> 51.0,s=>1.0,l=>1,min=>0  ,max=>2.55    ,c=>'factor'   ,f=>100     ,u=>"s"   ,d=>0,t=>"fuse delay"},
  redTempLvl      =>{a=> 52.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>0,t=>"reduced temperatur recover"},
  redLvl          =>{a=> 53.0,s=>1.0,l=>1,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>"%"   ,d=>0,t=>"reduced power level"},
  powerUpAction	  =>{a=> 86.0,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>"behavior on power up"                  ,lit=>{off=>0,on=>1}},
  statusInfoMinDly=>{a=> 87.0,s=>0.5,l=>1,min=>0.5,max=>15.5    ,c=>'factor'   ,f=>2       ,u=>"s"   ,d=>0,t=>"status message min delay"},
  statusInfoRandom=>{a=> 87.5,s=>0.3,l=>1,min=>0  ,max=>7       ,c=>''         ,f=>''      ,u=>"s"   ,d=>0,t=>"status message random delay"},
  characteristic  =>{a=> 88.0,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>""                                      ,lit=>{linear=>0,square=>1}},
  logicCombination=>{a=> 89.0,s=>0.5,l=>1,min=>0  ,max=>16      ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{inactive=>0,or=>1,and=>2,xor=>3,nor=>4,nand=>5,orinv=>6,andinv=>7,plus=>8,minus=>9,mul=>10,plusinv=>11,minusinv=>12,mulinv=>13,invPlus=>14,invMinus=>15,invMul=>16}},
#CC-TC                                                                                        
  backlOnTime     =>{a=>  5.0,s=>0.6,l=>0,min=>1  ,max=>25      ,c=>""         ,f=>''      ,u=>'s'   ,d=>0,t=>"Backlight ontime"},
  backlOnMode     =>{a=>  5.6,s=>0.2,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Backlight mode"  ,lit=>{off=>0,auto=>1}},
  btnLock         =>{a=> 15  ,s=>1  ,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Button Lock"     ,lit=>{unlock=>0,lock=>1}},

  dispTempHum     =>{a=>  1.0,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{temp=>0,tempHumidity=>1}},
  dispTempInfo    =>{a=>  1.1,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{actual=>0,setPoint=>1}},
  dispTempUnit    =>{a=>  1.2,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{Celsius=>0,Fahrenheit=>1}},
  mdTempReg       =>{a=>  1.3,s=>0.2,l=>5,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{manual=>0,auto=>1,central=>2,party=>3}},
  decalDay        =>{a=>  1.5,s=>0.3,l=>5,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Decalc weekday"  ,lit=>{sat=>0,sun=>1,mon=>2,tue=>3,wed=>4,thu=>5,fri=>6}},
  mdTempValve     =>{a=>  2.6,s=>0.2,l=>5,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{auto=>0,close=>1,open=>2}},
  tempComfort     =>{a=>  3  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"comfort temp value"},
  tempLower       =>{a=>  4  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"comfort temp value"},
  tempWinOpen     =>{a=>  5  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Win open !chan 3 only!"},
  tempParty       =>{a=>  6  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Party"},
  decalMin        =>{a=>  8  ,s=>0.3,l=>5,min=>0  ,max=>50      ,c=>'factor'   ,f=>0.1     ,u=>'min' ,d=>1,t=>"Decalc min"},
  decalHr         =>{a=>  8.3,s=>0.5,l=>5,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Decalc hour"},
  partyEndHr      =>{a=> 97  ,s=>0.6,l=>6,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Party end Hour"},
  partyEndMin     =>{a=> 97.7,s=>0.1,l=>6,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>'min' ,d=>1,t=>"Party end min",lit=>{"00"=>0,"30"=>1}},
  partyEndDay     =>{a=> 98  ,s=>1  ,l=>6,min=>0  ,max=>200     ,c=>''         ,f=>''      ,u=>'d'   ,d=>1,t=>"Party end Day"},
#Thermal-cc-VD                                                                                  
  valveOffset     =>{a=>  9  ,s=>0.5,l=>5,min=>0  ,max=>25      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve offset"},             # size actually 0.5
  valveError      =>{a=> 10  ,s=>1  ,l=>5,min=>0  ,max=>99      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve position when error"},# size actually 0.7
#SCD                                                                                  
  msgScdPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,lvlNormal=>1}},
  msgScdPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position C",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosD      =>{a=> 32.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position D",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  evtFltrTime     =>{a=> 35.0,s=>1  ,l=>1,min=>600,max=>1200    ,c=>''         ,f=>1.6     ,u=>'s'   ,d=>0,t=>"Event filter time",},#todo check calculation
#rhs - different literals
  msgRhsPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position C",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  evtDly          =>{a=> 33  ,s=>1  ,l=>1,min=>0  ,max=>7620    ,c=>'factor'   ,f=>1.6     ,u=>'s'   ,d=>0,t=>"Event delay time",},#todo check calculation
# keymatic/winmatic secific register                                                                     
  signal          =>{a=>  3.4,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Confirmation beep"             ,lit=>{off=>0,on=>1}},
  signalTone      =>{a=>  3.6,s=>0.2,l=>0,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""                              ,lit=>{low=>0,mid=>1,high=>2,veryHigh=>3}},
  keypressSignal  =>{a=>  3.0,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Keypress beep"                 ,lit=>{off=>0,on=>1}},
  holdTime        =>{a=> 20  ,s=>1,  l=>1,min=>0  ,max=>8.16    ,c=>'factor'   ,f=>31.25   ,u=>'s'   ,d=>0,t=>"Holdtime for door opening"},
  holdPWM         =>{a=> 21  ,s=>1,  l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Holdtime pulse wide modulation"},
  setupDir        =>{a=> 22  ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Rotation direction for locking",lit=>{right=>0,left=>1}},
  setupPosition   =>{a=> 23  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Rotation angle neutral position"},
  angelOpen       =>{a=> 24  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Door opening angle"},
  angelMax        =>{a=> 25  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle maximum"},
  angelLocked     =>{a=> 26  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle Locked position"},
  pullForce       =>{a=> 28  ,s=>1  ,l=>1,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>1,t=>"pull force level"},
  pushForce       =>{a=> 29  ,s=>1  ,l=>1,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>1,t=>"push force level"},
  tiltMax         =>{a=> 30  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"maximum tilt level"},
  ledFlashUnlocked=>{a=> 31.3,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when not locked",lit=>{off=>0,on=>1}},
  ledFlashLocked  =>{a=> 31.6,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when locked"    ,lit=>{off=>0,on=>1}},
# sec_mdir                                                                                   
  cyclicInfoMsg   =>{a=>  9  ,s=>1  ,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"cyclic message",lit=>{off=>0,on=>1}},
  sabotageMsg     =>{a=> 16.0,s=>1  ,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"enable sabotage message"   ,lit=>{off=>0,on=>1}},
  lowBatLimit     =>{a=> 18.0,s=>1  ,l=>0,min=>10 ,max=>12      ,c=>'factor'   ,f=>10      ,u=>'V'   ,d=>1,t=>"low batterie limit"},
  batDefectLimit  =>{a=> 19.0,s=>1  ,l=>0,min=>0.1,max=>2       ,c=>'factor'   ,f=>100     ,u=>'Ohm' ,d=>1,t=>"batterie defect detection"},
  transmDevTryMax =>{a=> 20.0,s=>1.0,l=>0,min=>1  ,max=>10      ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"max message re-transmit"},
  localResDis     =>{a=> 24.0,s=>1.0,l=>0,min=>1  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"local reset disable"       ,lit=>{off=>0,on=>1}},

  waterUppThr     =>{a=>  6.0,s=>1  ,l=>1,min=>0  ,max=>256     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"water upper threshold"},
  waterlowThr     =>{a=>  7.0,s=>1  ,l=>1,min=>0  ,max=>256     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"water lower threshold"},
  caseDesign      =>{a=> 90.0,s=>1  ,l=>1,min=>1  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"case desing"               ,lit=>{verticalBarrel=>1,horizBarrel=>2,rectangle=>3}},
  caseHigh        =>{a=> 94.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case hight"},
  fillLevel       =>{a=> 98.0,s=>2  ,l=>1,min=>100,max=>300     ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"fill level"},
  caseWidth       =>{a=>102.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case width"},
  caseLength      =>{a=>106.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case length"},
  meaLength       =>{a=>108.0,s=>2  ,l=>1,min=>110,max=>310     ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>""},
  useCustom       =>{a=>110.0,s=>1  ,l=>1,min=>110,max=>310     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"use custom"      ,lit=>{off=>0,on=>1}},

  fillLvlUpThr    =>{a=>  4.0,s=>1  ,l=>4,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"fill level upper threshold"},
  fillLvlLoThr    =>{a=>  5.0,s=>1  ,l=>4,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"fill level lower threshold"},

  evtFltrPeriod   =>{a=>  1.0,s=>0.4,l=>1,min=>0.5,max=>7.5     ,c=>'factor'   ,f=>2       ,u=>'s'   ,d=>1,t=>"event filter period"},
  evtFltrNum      =>{a=>  1.4,s=>0.4,l=>1,min=>1  ,max=>15      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"sensitivity - read sach n-th puls"},
  minInterval     =>{a=>  2.0,s=>0.3,l=>1,min=>0  ,max=>4       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"minimum interval in sec"   ,lit=>{15=>0,30=>1,60=>2,120=>3,240=>4}},
  captInInterval  =>{a=>  2.3,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"capture within interval"   ,lit=>{off=>0,on=>1}},
  brightFilter    =>{a=>  2.4,s=>0.4,l=>1,min=>0  ,max=>7       ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"brightness filter - ignore light at night"},
  msgScPosA       =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,closed=>1,open=>2}},
  msgScPosB       =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,closed=>1,open=>2}},
  eventDlyTime    =>{a=> 33  ,s=>1  ,l=>1,min=>0  ,max=>7620    ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>1,t=>"event delay time"},
  ledOnTime       =>{a=> 34  ,s=>1  ,l=>1,min=>0  ,max=>1.275   ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>0,t=>"LED ontime"},
  eventFilterTime =>{a=> 35  ,s=>1  ,l=>1,min=>0  ,max=>7620    ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"evetn filter time"},

# weather units                                                                                  
  stormUpThresh   =>{a=>  6  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm upper threshold"},
  stormLowThresh  =>{a=>  7  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm lower threshold"},
# others
  localResetDis   =>{a=>  7  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"LocalReset disable",lit=>{off=>0,on=>1}},
  );
  
my %culHmRegGeneral = (
  intKeyVisib=>1,pairCentral=>1,
	);
my %culHmRegType = (
  remote            =>{expectAES       =>1,peerNeedsBurst  =>1,dblPress        =>1,longPress       =>1},
  blindActuator     =>{driveUp         =>1,driveDown       =>1,driveTurn       =>1,refRunCounter   =>1,
                       transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1, # nt present in all files
                       MaxTimeF        =>1,                                    
                       OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1,
  	   		           OffLevel        =>1,OnLevel         =>1,                                    
                       ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1,DriveMode       =>1,
				       BlJtOn          =>1,BlJtOff         =>1,BlJtDlyOn       =>1,BlJtDlyOff      =>1,
                       BlJtRampOn      =>1,BlJtRampOff     =>1,BlJtRefOn       =>1,BlJtRefOff      =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,CtRefOn         =>1,
				       CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,CtRefOff        =>1,
				       lgMultiExec     =>1,
				       },
  dimmer            =>{transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,powerUpAction   =>1,
                       ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1,fuseDelay	   =>1,#not dim.L
                       OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1,
                       OffDlyBlink     =>1,OnLvlPrio       =>1,OnDlyMode       =>1,
		               ActionTypeDim   =>1,OnTimeMode      =>1,OffTimeMode     =>1,
		               OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1,               
                       RampSstep       =>1,RampOnTime      =>1,RampOffTime     =>1,
		               DimMinLvl       =>1,DimMaxLvl       =>1,DimStep         =>1,
                       DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1,
                       DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,
                       CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,
		               OffDlyNewTime   =>1,OffDlyNewTime   =>1,
		               DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1,
		               DimElsActionType=>1,
		               DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1,
		               DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1,			
		               lgMultiExec     =>1,
		               logicCombination=>1,
		               },
  switch            =>{OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1,
                       SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1,
		               ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1,
 		               lgMultiExec     =>1,
		               },
  winMatic          =>{signal          =>1,signalTone      =>1,keypressSignal  =>1},                                  
  keyMatic          =>{signal          =>1,signalTone      =>1,keypressSignal  =>1,
			           holdTime        =>1,holdPWM         =>1,setupDir        =>1,setupPosition   =>1,
			           angelOpen       =>1,angelMax        =>1,angelLocked     =>1,
			           ledFlashUnlocked=>1,ledFlashLocked  =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtOff           =>1,
                       KeyJtOn         =>1,KeyJtOff        =>1,
					   OnTime          =>1,
			           },
  motionDetector    =>{evtFltrPeriod =>1,evtFltrNum      =>1,minInterval     =>1,
			           captInInterval=>1,brightFilter    =>1,ledOnTime       =>1,
			           },
);

my %culHmRegModel = (
  "HM-RC-12"        =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1},
  "HM-RC-12-B"      =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1},
  "HM-RC-12-SW"     =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1},
                                                                               
  "HM-RC-19"        =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1,backAtCharge    =>1,language =>1,},
  "HM-RC-19-B"      =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1,backAtCharge    =>1,language =>1,},
  "HM-RC-19-SW"     =>{backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1,backAtCharge    =>1,language =>1,},
 
  "HM-LC-Dim1PWM-CV"=>{characteristic  =>1},
  "HM-LC-Dim1L-P"   =>{loadAppearBehav =>1,loadErrCalib	   =>1},
  "HM-LC-Dim1L-CV"  =>{loadAppearBehav =>1,loadErrCalib	   =>1},
  "HM-LC-Dim2L-SM"  =>{loadAppearBehav =>1,loadErrCalib	   =>1},
  
  "HM-CC-VD"        =>{valveOffset     =>1,valveError      =>1},
  "HM-PB-4DIS-WM"   =>{peerNeedsBurst  =>1,expectAES       =>1,language        =>1,stbyTime        =>1},
  "HM-WDS100-C6-O"  =>{stormUpThresh   =>1,stormLowThresh  =>1},
  "KS550"           =>{stormUpThresh   =>1,stormLowThresh  =>1},
  "HM-OU-CFM-PL"    =>{localResetDis   =>1,
  			           OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1,
			           OnTimeMode      =>1,OffTimeMode     =>1, 
                       SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1,
			           ActType         =>1,ActNum          =>1,lgMultiExec     =>1},
  "HM-SEC-MDIR"     =>{                    sabotageMsg     =>1,},
  "HM-CC-TC"        =>{backlOnTime     =>1,backlOnMode     =>1,btnLock         =>1},
  "HM-CC-SCD"       =>{peerNeedsBurst  =>1,expectAES       =>1,
                                                               transmitTryMax  =>1,evtFltrTime     =>1,
                       msgScdPosA      =>1,msgScdPosB      =>1,msgScdPosC      =>1,msgScdPosD      =>1,},
  "HM-SEC-RHS"      =>{peerNeedsBurst  =>1,expectAES       =>1,
                       cyclicInfoMsg   =>1,                    transmDevTryMax =>1,
                       msgRhsPosA      =>1,msgRhsPosB      =>1,msgRhsPosC      =>1,
                       evtDly          =>1,ledOnTime       =>1,transmitTryMax  =>1,},
  "HM-SEC-SC"       =>{cyclicInfoMsg   =>1,sabotageMsg     =>1,transmDevTryMax =>1,
                       msgScPosA       =>1,msgScPosB       =>1,
					                       ledOnTime       =>1,transmitTryMax  =>1,eventDlyTime    =>1,
                       peerNeedsBurst  =>1,expectAES       =>1,},
  "HM-SCI-3-FM"     =>{cyclicInfoMsg   =>1                    ,transmDevTryMax =>1,
                       msgScPosA       =>1,msgScPosB       =>1,
					                                           transmitTryMax  =>1,eventDlyTime    =>1,
                       peerNeedsBurst  =>1,expectAES       =>1,},
  "HM-SEC-TIS"      =>{cyclicInfoMsg   =>1,sabotageMsg     =>1,transmDevTryMax =>1,
                       msgScPosA       =>1,msgScPosB       =>1,
					                       ledOnTime       =>1,transmitTryMax  =>1,eventFilterTime =>1,
                       peerNeedsBurst  =>1,expectAES       =>1,},
  "HM-SEC-SFA-SM"   =>{cyclicInfoMsg   =>1,sabotageMsg     =>1,transmDevTryMax =>1,
                       lowBatLimit     =>1,batDefectLimit  =>1,
                                                               transmitTryMax  =>1,},
  "HM-Sys-sRP-Pl"   =>{compMode        =>1,},
  "KFM-Display"     =>{CtDlyOn         =>1,CtDlyOff        =>1,
                       CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       ActionType      =>1,OffTimeMode     =>1,OnTimeMode      =>1,
                       DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1,DimJtDlyOff     =>1,
                       DimJtRampOn     =>1,DimJtRampOff    =>1,
                       lgMultiExec     =>1,
					   },
  "HM-Sen-Wa-Od"    =>{cyclicInfoMsg   =>1,                    transmDevTryMax =>1,
                       localResDis     =>1,ledOnTime       =>1,transmitTryMax  =>1,
                       waterUppThr     =>1,waterlowThr     =>1,caseDesign      =>1,caseHigh        =>1,
                       fillLevel       =>1,caseWidth       =>1,caseLength      =>1,meaLength       =>1,
                       useCustom       =>1,					   
                       fillLvlUpThr    =>1,fillLvlLoThr    =>1,
                       expectAES       =>1,peerNeedsBurst  =>1,},
  );
my %culHmRegChan = (# if channelspecific then enter them here 
  "HM-CC-TC02"      =>{dispTempHum  =>1,dispTempInfo =>1,dispTempUnit =>1,mdTempReg   =>1,
			           mdTempValve  =>1,tempComfort  =>1,tempLower    =>1,partyEndDay =>1,
			           partyEndMin  =>1,partyEndHr   =>1,tempParty    =>1,decalDay    =>1,
			           decalHr      =>1,decalMin     =>1, 
              },    
  "HM-CC-TC03"      =>{tempWinOpen  =>1, }, #window channel
  "HM-RC-1912"      =>{msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                       backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                       lcdSymb      =>1, lcdLvlInterp   =>1},
  "HM-RC-19-B12"    =>{msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                       backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                       lcdSymb      =>1, lcdLvlInterp   =>1},
  "HM-RC-19-SW12"   =>{msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                       backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                       lcdSymb      =>1, lcdLvlInterp   =>1},
  "HM-OU-CFM-PL02"  =>{Intense=>1},
  "HM-SEC-WIN01"    =>{setupDir        =>1,pullForce       =>1,pushForce       =>1,tiltMax         =>1,
                       CtValLo         =>1,CtValHi         =>1,
                       CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1,
			           WinJtOn         =>1,WinJtOff        =>1,WinJtRampOn     =>1,WinJtRampOff    =>1,
                       OnTime          =>1,OffTime         =>1,OffLevelKm      =>1,
                       OnLevelKm       =>1,OnRampOnSp      =>1,OnRampOffSp     =>1
                      }
 );

##--------------- Conversion routines for register settings
my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111600);
sub CUL_HM_Attr(@) {#############################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  my @hashL;
  if ($attrName eq "expert"){#[0,1,2]
    $attr{$name}{expert} = $attrVal;
	my $eHash = CUL_HM_name2Hash($name);
    foreach my $chId (CUL_HM_getAssChnIds($name)){ 
	  my $cHash = CUL_HM_id2Hash($chId);
	  push(@hashL,$cHash) if ($eHash ne $cHash);
	}
    push(@hashL,$eHash);
    foreach my $hash (@hashL){
	  my $exLvl = CUL_HM_getExpertMode($hash);
	  if ($exLvl eq "0"){# off
        foreach my $rdEntry (keys %{$hash->{READINGS}}){
	      my $rdEntryNew;
	  	  $rdEntryNew = ".".$rdEntry       if ($rdEntry =~m /^RegL_/);
	  	  if ($rdEntry =~m /^R-/){
	  	    my $reg = $rdEntry;
	  	    $reg =~ s/.*-//;
	  	    $rdEntryNew = ".".$rdEntry if($culHmRegDefine{$reg}{d} eq '0' );
	  	  }
	  	  next if (!defined($rdEntryNew)); # no change necessary
          delete $hash->{READINGS}{$rdEntryNew};
          $hash->{READINGS}{$rdEntryNew} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  elsif ($exLvl eq "1"){# on: Only register values, no raw data
	    # move register to visible if available
        foreach my $rdEntry (keys %{$hash->{READINGS}}){
	      my $rdEntryNew;
	  	  $rdEntryNew = substr($rdEntry,1) if ($rdEntry =~m /^\.R-/);
	  	  $rdEntryNew = ".".$rdEntry       if ($rdEntry =~m /^RegL_/);
	  	  next if (!$rdEntryNew); # no change necessary
          delete $hash->{READINGS}{$rdEntryNew};
          $hash->{READINGS}{$rdEntryNew} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  elsif ($exLvl eq "2"){# full - incl raw data
        foreach my $rdEntry (keys %{$hash->{READINGS}}){
	      my $rdEntryNew;
	  	  $rdEntryNew = substr($rdEntry,1) if (($rdEntry =~m /^\.RegL_/) ||
	  	                                     ($rdEntry =~m /^\.R-/));
	  	  next if (!$rdEntryNew); # no change necessary
          delete $hash->{READINGS}{$rdEntryNew};
          $hash->{READINGS}{$rdEntryNew} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  else{;
	  }
    }
  }
  elsif($attrName eq "actCycle"){#"000:00" or 'off'
    return if (CUL_HM_name2Id($name) eq $K_actDetID);
	# Add to ActionDetector. Wait a little - config might not be finished
    my @arr;
    if(!$modules{CUL_HM}{helper}{updtCfgLst}){
      $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
    }
    push(@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name);

	RemoveInternalTimer("updateConfig");
    InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
  }
  return;
}
sub CUL_HM_initRegHash() { #duplicate short and long press register 
  foreach my $reg (keys %culHmRegDefShLg){ #update register list
    %{$culHmRegDefine{"sh".$reg}} = %{$culHmRegDefShLg{$reg}};
    %{$culHmRegDefine{"lg".$reg}} = %{$culHmRegDefShLg{$reg}};
	$culHmRegDefine{"lg".$reg}{a} +=0x80;
  }
  foreach my $type(sort(keys %culHmRegType)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegType{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegType{$type}{$reg};
	    $culHmRegType{$type}{"sh".$reg} = 1;
	    $culHmRegType{$type}{"lg".$reg} = 1;
	  }
    }
  }
  foreach my $type(sort(keys %culHmRegModel)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegModel{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegModel{$type}{$reg};
	    $culHmRegModel{$type}{"sh".$reg} = 1;
	    $culHmRegModel{$type}{"lg".$reg} = 1;
	  }
    }
  }
  foreach my $type(sort(keys %culHmRegChan)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegChan{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegChan{$type}{$reg};
	    $culHmRegChan{$type}{"sh".$reg} = 1;
	    $culHmRegChan{$type}{"lg".$reg} = 1;
	  }
    }
  }
}
sub CUL_HM_fltCvT($) { # float -> config time
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT){
    $div2 = $div;
	last if ($inValue < $fltCvT{$div});
	$exp++;
  }
  return ($exp << 5)+int($inValue/$div2);
}
sub CUL_HM_CvTflt($) { # config time -> float
  my ($inValue) = @_;
  return ($inValue & 0x1f)*((sort {$a <=> $b} keys(%fltCvT))[$inValue >> 5]);
}


#define gets - try use same names as for set
my %culHmGlobalGets = (
  param      => "<param>",
  reg        => "<addr> ... <list> <peer>",
  regList    => "",
  saveConfig => "<filename>",
);
my %culHmSubTypeGets = (
  none4Type  =>{ "test"=>"" },
);
my %culHmModelGets = (
  none4Mod   =>{ "none"=>"" },
);
sub CUL_HM_TCtempReadings($) {
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regLN = ((CUL_HM_getExpertMode($hash) eq "2")?"":".")."RegL_";
  my $reg5 = ReadingsVal($name,$regLN."05:" ,"");
  my $reg6 = ReadingsVal($name,$regLN."06:" ,"");
  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
  $reg5 =~ s/.* 0B://;     #remove register up to addr 11 from list 5
  my $tempRegs = $reg5.$reg6;  #one row
  $tempRegs =~ s/ 00:00/ /g;   #remove regline termination
  $tempRegs =~ s/ ..:/,/g;     #remove addr Info
  $tempRegs =~ s/ //g;         #blank
  my @Tregs = split(",",$tempRegs);
  my @time  = @Tregs[grep !($_ % 2), 0..$#Tregs]; # even-index =time
  my @temp  = @Tregs[grep $_ % 2, 0..$#Tregs];    # odd-index  =data
  return "reglist incomplete\n" if (scalar( @time )<168);
  foreach  (@time){$_=hex($_)*10};
  foreach  (@temp){$_=hex($_)/2};
  my $setting;
  my @changedRead;
  push (@changedRead,"tempList_State:".
                (($hash->{helper}{shadowReg}{$regLN."05:"} ||
				  $hash->{helper}{shadowReg}{$regLN."06:"} )?"set":"verified"));
  for (my $day = 0;$day<7;$day++){
    my $tSpan  = 0;
	my $dayRead = "";
    for (my $entry = 0;$entry<24;$entry++){
      my $reg = $day *24 + $entry; 
      last if ($tSpan > 1430);
	  $tSpan = $time[$reg];
	  my $entry = sprintf("%02d:%02d %3.01f",($tSpan/60),($tSpan%60),$temp[$reg]);
  	  $setting .= "Temp set: ".$days[$day]." ".$entry." C\n";
  	  $dayRead .= " ".$entry;
	  $tSpan = $time[$reg];
    }
	push (@changedRead,"tempList".$days[$day].":".$dayRead);
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
  return $setting;
}
sub CUL_HM_repReadings($) {
  my ($hash)=@_;
  my %pCnt;
  foreach my$pId(split',',$hash->{helper}{peerIDsRaw}){
    next if (!$pId || $pId eq "00000000");
	$pCnt{$pId}{cnt}++;
  }
  my $ret;
  foreach my$pId(sort keys %pCnt){
	my ($pdID,$bdcst) = ($1,$2) if ($pId =~ m/(......)(..)/);
	$ret .= "source ".$pCnt{$pId}{cnt}." entry for: ".CUL_HM_id2Name($pdID)
	       .($bdcst eq "01"?" broadcast enabled":"")."\n";
  }
  return $ret;
}
###################################
sub CUL_HM_Get($@) {
  my ($hash, @a) = @_;
  return "no get value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $devName = $hash->{device}?$hash->{device}:$name;
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");
  my $mId = CUL_HM_getMId($hash);
  my $rxType = CUL_HM_getRxType($hash);

  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);

  my $h = $culHmGlobalGets{$cmd};
  $h = $culHmSubTypeGets{$st}{$cmd} if(!defined($h) && $culHmSubTypeGets{$st});
  $h = $culHmModelGets{$md}{$cmd}   if(!defined($h) && $culHmModelGets{$md});
  my @h;
  @h = split(" ", $h) if($h);

  if(!defined($h)) {
    my @arr = keys %culHmGlobalGets;
    push @arr, keys %{$culHmSubTypeGets{$st}} if($culHmSubTypeGets{$st});
    push @arr, keys %{$culHmModelGets{$md}} if($culHmModelGets{$md});
    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @arr); 

    return $usg;
  }elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";
    
  } elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";
  }
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $id = CUL_HM_IOid($hash);

  #----------- now start processing --------------
  if($cmd eq "param") {  ######################################################
	return $attr{$name}{$a[2]}              if ($attr{$name}{$a[2]});
	return $hash->{READINGS}{$a[2]}{VAL}    if ($hash->{READINGS}{$a[2]});
	return $attr{$devName}{$a[2]}           if ($attr{$devName}{$a[2]});
	return $devHash->{READINGS}{$a[2]}{VAL} if ($devHash->{READINGS}{$a[2]});
	return $hash->{$a[2]}                   if ($hash->{$a[2]});
	return $devHash->{$a[2]}                if ($devHash->{$a[2]});
	return $hash->{helper}{$a[2]}           if ($hash->{helper}{$a[2]} && ref($hash->{helper}{$a[2]}) ne "HASH");
	return $devHash->{helper}{$a[2]}        if ($devHash->{helper}{$a[2]});
	return "undefined";
  }
  elsif($cmd eq "reg") {  #####################################################
    my (undef,undef,$regReq,$list,$peerId) = @a;
	if ($regReq eq 'all'){
	  my @regArr = keys %culHmRegGeneral;
	  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st}); 
	  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md}); 
	  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn}); 
	  
	  my @peers; # get all peers we have a reglist 
	  my @listWp; # list that require peers
	  foreach my $readEntry (keys %{$hash->{READINGS}}){
	    if ($readEntry =~m /^[\.]?RegL_(.*)/){ #reg Reading "RegL_<list>:peerN
		  my $peer = substr($1,3);
		  next if (!$peer);
		  push(@peers,$peer);
		  push(@listWp,substr($1,1,1));
		}
	  }
	  my @regValList; #storage of results
	  my $regHeader = "list:peer\tregister         :value\n";
	  foreach my $regName (@regArr){
	    my $regL  = $culHmRegDefine{$regName}->{l};
		my @peerExe = (grep (/$regL/,@listWp))?@peers:("00000000");
		foreach my $peer(@peerExe){
		  next if($peer eq "");
	      my $regVal= CUL_HM_getRegFromStore($name,$regName,0,$peer);#determine
		  my $peerN = CUL_HM_id2Name($peer);
		  $peerN = "      " if ($peer  eq "00000000");
		  push @regValList,sprintf("   %d:%s\t%-16s :%s\n",
		          $regL,$peerN,$regName,$regVal)
		        if ($regVal ne 'invalid');
		}
	  }
	  my $addInfo = "";
	  $addInfo = CUL_HM_TCtempReadings($hash)
	        if ($md eq "HM-CC-TC" && $chn eq "02");
		
      $addInfo = CUL_HM_repReadings($hash) if ($md eq "HM-Sys-sRP-Pl");
	
	  return $name." type:".$st." - \n".
	         $regHeader.join("",sort(@regValList)).
			 $addInfo;
	}
	else{	  
      my $regVal = CUL_HM_getRegFromStore($name,$regReq,$list,$peerId);
	  return ($regVal eq "invalid")? "Value not captured" 
	                             : $regVal;
	}
  }
  elsif($cmd eq "regList") {  #################################################
    my @regArr = keys %culHmRegGeneral ;
	push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st});  
    push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md}); 
     
	if ($isChannel){
	  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn});
	}
	else{# add all ugly channel register to device view
	  for my $chnId (CUL_HM_getAssChnIds($name)){
	    my $chnN = substr($chnId,6,2);
	    push @regArr, keys %{$culHmRegChan{$md.$chnN}} 
		      if($culHmRegChan{$md.$chnN}); 
	  }
	}

	my @rI;
	foreach my $regName (@regArr){
	  my $reg  = $culHmRegDefine{$regName};	  
	  my $help = $reg->{t};
	  my ($min,$max) = ($reg->{min},$reg->{max});
	  if (defined($reg->{lit})){
	    $help .= " options:".join(",",keys%{$reg->{lit}});
	    $min =$max ="-";
	  }
	  push @rI,sprintf("%4d: %-16s | %3s to %-11s | %8s |%-3s| %s\n",
			  $reg->{l},$regName,$min,$max.$reg->{u},
              ((($reg->{l} == 3)||($reg->{l} == 4))?"required":""),
              (($reg->{d} != 1)?"exp":""),
			  $help)
	        if (!($isChannel && $reg->{l} == 0));
	}
	
    my $info = sprintf("list: %16s | %-18s | %-8s |%-3s| %s\n",
	                 "register","range","peer","exp","description");
	foreach(sort(@rI)){$info .= $_;}
	return $info;
  }
  elsif($cmd eq "saveConfig"){  ###############################################
    my $fName = $a[2];
	open(aSave, ">>$fName") || return("Can't open $fName: $!");
    
	print aSave "\n\n#======== store device data:".$devName." === from: ".TimeNow();
	my @eNames;
	push @eNames,$devName;
	foreach my $e (CUL_HM_getAssChnIds($name)){
	  my $eName = CUL_HM_id2Name($e);
	  push @eNames, $eName if($eName !~ m/_chn:/);
	}
	
	foreach my $eName (@eNames){
	  print aSave "\n#---      entity:".$eName;
	  my $pIds = AttrVal($eName, "peerIDs", "");
	  my $timestamps = "\n#     timestamp of the readings for reference";
	  if ($pIds){
	    print aSave "\n# Peer Names:".ReadingsVal($eName,"peerList","");
		$timestamps .= "\n#        ".ReadingsTimestamp($eName,"peerList","")." :peerList";
	    print aSave "\nset ".$eName." peerBulk ".$pIds;
	  }
	  my $ehash = CUL_HM_name2Hash($eName);
	  foreach my $read (sort keys %{$ehash->{READINGS}}){
	    next if ($read !~ m/^[\.]?RegL_/);
	    print aSave "\nset ".$eName." regBulk ".$read." ".ReadingsVal($eName,$read,"");
		$timestamps .= "\n#        ".ReadingsTimestamp($eName,$read,"")." :".$read;
	  }
	  print aSave $timestamps;
	}
	print aSave "\n======= finished ===\n";
	close(aSave);
  }

  Log GetLogLevel($name,4), "CUL_HM get $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($devHash) if ($rxType & 0x03);#burst/all
  return "";
}
###################################
my %culHmGlobalSetsDevice = (# general commands for devices only
  raw      	    => "data ...",
  reset    	    => "",
  pair     	    => "",
  unpair   	    => "",
  getpair       => "",
  virtual       =>"<noButtons>",
  actiondetect  =>"outdated",#todo Updt3 remove
);
my %culHmGlobalSets = (
  sign     	    => "[on|off]",
  regRaw   	    => "[List0|List1|List2|List3|List4|List5|List6] <addr> <data> ... <PeerChannel>", #todo Updt2 remove
  regBulk       => "<list>:<peer> <addr1:data1> <addr2:data2> ...",
  peerBulk      => "<peer1,peer2,...>",
  statusRequest => "",
  getdevicepair => "",
  getRegRaw     =>"[List0|List1|List2|List3|List4|List5|List6] ... <PeerChannel>",
  getConfig     => "",
  regSet        =>"<regName> <value> ... <peerChannel>",
  clear         =>"[readings|msgEvents]",
);
my %culHmSubTypeSets = (
  switch           =>{ "on-for-timer"=>"sec", "on-till"=>"time",
		               on=>"", off=>"", toggle=>"",
					   press      => "[long|short] [on|off] ..."},
  dimmer           =>{ "on-for-timer"=>"sec", "on-till"=>"time",
		               on=>"", off=>"", toggle=>"", pct=>"", stop=>"",
					   press      => "[long|short] [on|off] ..."},
  blindActuator    =>{ on=>"", off=>"", toggle=>"", pct=>"", stop=>"",
					   press      => "[long|short] [on|off] ..."},
  remote           =>{ devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",},
  pushButton       =>{ devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",},
  threeStateSensor =>{ devicepair => "<btnNumber> device ... single [set|unset] [actor|remote|both]",},
  motionDetector   =>{ devicepair => "<btnNumber> device ... single [set|unset] [actor|remote|both]",},
  virtual          =>{ raw        => "data ...",
		               devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
		               press      => "[long|short]...",
                       valvePos   => "position",#acting as TC
		               virtual    =>"<noButtons>",}, #redef necessary for virtual
  smokeDetector    =>{ test       => "", alarmOn=>"", alarmOff=>"", 
		               devicepair => "<btnNumber> device ... single [set|unset] actor",},
  winMatic         =>{ matic      => "<btn>",
                       keydef     => "<btn> <txt1> <txt2>",
                       create     => "<txt>" },
  keyMatic         =>{ lock       =>"",
  	                   unlock     =>"[sec] ...",
  	                   open       =>"[sec] ...",
  	                   inhibit    =>"[on|off]"},
);
my %culHmModelSets = (
  "HM-CC-VD"=>{ 
          valvePos     => "position"},
  "HM-RC-19"=>    {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>"},
  "HM-RC-19-B"=>  {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>"},
  "HM-RC-19-SW"=> {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>"},
  "HM-PB-4DIS-WM"=>{
	      text      => "<btn> [on|off] <txt1> <txt2>"},
  "HM-OU-LED16" =>{
		  led    =>"[off|red|green|orange]" ,
		  ilum   =>"[0-15] [0-127]" },
  "HM-OU-CFM-PL"=>{
	      led       => "<color>[,<color>..]",
		  playTone  => "<MP3No>[,<MP3No>..]"},
  "HM-Sys-sRP-Pl"=>{
	      setRepeat => "[no1..36] <sendName> <recName> [bdcast-yes|no]"},
);

my %culHmChanSets = (
  "HM-CC-TC00"=>{ 
          devicepair    => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
          "day-temp"     => "[on,off,6.0..30.0]",
          "night-temp"   => "[on,off,6.0..30.0]",
          "party-temp"   => "[on,off,6.0..30.0]",
          "desired-temp" => "[on,off,6.0..30.0]", 
          tempListSat    => "HH:MM temp ...",
          tempListSun    => "HH:MM temp ...",
          tempListMon    => "HH:MM temp ...",
          tempListTue    => "HH:MM temp ...",
          tempListThu    => "HH:MM temp ...",
          tempListWed    => "HH:MM temp ...",
          tempListFri    => "HH:MM temp ...",
          displayMode    => "[temp-only|temp-hum]",
          displayTemp    => "[actual|setpoint]",
          displayTempUnit => "[celsius|fahrenheit]",
          controlMode    => "[manual|auto|central|party]",
          decalcDay      => "day",        },
  "HM-CC-TC02"=>{ 
          devicepair    => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
          "day-temp"     => "[on,off,6.0..30.0]",
          "night-temp"   => "[on,off,6.0..30.0]",
          "party-temp"   => "[on,off,6.0..30.0]",
          "desired-temp" => "[on,off,6.0..30.0]", 
          tempListSat    => "HH:MM temp ...",
          tempListSun    => "HH:MM temp ...",
          tempListMon    => "HH:MM temp ...",
          tempListTue    => "HH:MM temp ...",
          tempListThu    => "HH:MM temp ...",
          tempListWed    => "HH:MM temp ...",
          tempListFri    => "HH:MM temp ...",
          displayMode    => "[temp-only|temp-hum]",
          displayTemp    => "[actual|setpoint]",
          displayTempUnit => "[celsius|fahrenheit]",
          controlMode    => "[manual|auto|central|party]",
          decalcDay      => "day",        },
  "HM-SEC-WIN01"=>{  stop         =>"",
                     level        =>"<level> <relockDly> <speed>..."},
);

##############################################
sub CUL_HM_getMId($) {#in: hash(chn or dev) out:model key (key for %culHmModel). 
 # Will store result in device helper
  my ($hash) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  my $mId = $hash->{helper}{mId};
  if (!$mId){   
    my $model = AttrVal($hash->{NAME}, "model", "");
    foreach my $mIdKey(grep {$culHmModel{$_}{name} eq $model}keys%culHmModel){
	  $mId = $hash->{helper}{mId} = $mIdKey;
	  return $mIdKey;
    }
  }
  return $mId;
}
##############################################
sub CUL_HM_getRxType($) { #in:hash(chn or dev) out:binary coded Rx type 
 # Will store result in device helper
  my ($hash) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  no warnings; #convert regardless of content
  my $rxtEntity = int($hash->{helper}{rxType});
  use warnings;
  if (!$rxtEntity){ #at least one bit must be set
    my $MId = CUL_HM_getMId($hash);
    my $rxtOfModel = $culHmModel{$MId}{rxt} if ($MId && $culHmModel{$MId}{rxt});
	if ($rxtOfModel){
      $rxtEntity |= ($rxtOfModel =~ m/b/)?0x02:0;#burst
      $rxtEntity |= ($rxtOfModel =~ m/c/)?0x04:0;#config
      $rxtEntity |= ($rxtOfModel =~ m/w/)?0x08:0;#wakeup
	}
	$rxtEntity = 1 if (!$rxtEntity);#always
	$hash->{helper}{rxType} = $rxtEntity;
  }
  return $rxtEntity;  
}
##############################################
sub CUL_HM_getFlag($) {#msgFlag set to 'A0' for normal and 'B0' for burst devices
 # currently not supported is the wakeupflag since it is hardly used
  my ($hash) = @_;
  return (CUL_HM_getRxType($hash) & 0x02)?"B0":"A0"; #set burst flag
}
sub CUL_HM_Set($@) {
  my ($hash, @a) = @_;
  my ($ret, $tval, $rval); #added rval for ramptime by unimatrix

  return "no set value specified" if(@a < 2);

  my $name    = $hash->{NAME};
  my $devName = $hash->{device}?$hash->{device}:$name;
  my $st      = AttrVal($devName, "subType", "");
  my $md      = AttrVal($devName, "model"  , "");
  
  my $rxType = CUL_HM_getRxType($hash);
  my $flag = CUL_HM_getFlag($hash); #set burst flag
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);

  my $mdCh = $md.($isChannel?$chn:"00"); # chan specific commands?
  my $h = $culHmGlobalSets{$cmd}    if($st ne "virtual");
  $h = $culHmGlobalSetsDevice{$cmd} if(!defined($h) && $st ne "virtual" && !$isChannel);
  $h = $culHmSubTypeSets{$st}{$cmd} if(!defined($h) && $culHmSubTypeSets{$st});
  $h = $culHmModelSets{$md}{$cmd}   if(!defined($h) && $culHmModelSets{$md}  );
  $h = $culHmChanSets{$mdCh}{$cmd}  if(!defined($h) && $culHmChanSets{$mdCh} );

  my @h;
  @h = split(" ", $h) if($h);

  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
    $cmd = "pct";
  } 
  elsif(!defined($h)) {
    my @arr;
    @arr = keys %culHmGlobalSets if($st ne "virtual");
    push @arr, keys %culHmGlobalSetsDevice    if($st ne "virtual" && !$isChannel);
    push @arr, keys %{$culHmSubTypeSets{$st}} if($culHmSubTypeSets{$st});
    push @arr, keys %{$culHmModelSets{$md}}   if($culHmModelSets{$md});
    push @arr, keys %{$culHmChanSets{$mdCh}}  if($culHmChanSets{$mdCh});
    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @arr); 

    if($usg =~ m/ pct/) {
      $usg =~ s/ pct/ pct:slider,0,1,100/;
    } 	
	elsif($md eq "HM-CC-TC") {
      my @list = map { ($_.".0", $_+0.5) } (6..30);
      pop @list;
      my $list = "on,off," . join(",",@list);
      $usg =~ s/-temp/-temp:$list/g;
    }
    return $usg;
  } 
  elsif($cmd eq "pct") {
    splice @a, 1, 1;
  } 
  elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";
  } 
  elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";
  }

     #if chn cmd is executed on device but refers to a channel?
  my $chnHash = (!$isChannel && $modules{CUL_HM}{defptr}{$dst."01"})?
                 $modules{CUL_HM}{defptr}{$dst."01"}:$hash;
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $id = CUL_HM_IOid($hash);
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);

  if($cmd eq "raw") {  ########################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
	$state = "";
    for (my $i = 2; $i < @a; $i++) {
      CUL_HM_PushCmdStack($hash, $a[$i]);
    }
  } 
  elsif($cmd eq "clear") { ####################################################
    my (undef,undef,$sect) = @a;
	if ($sect eq "readings"){
	  delete $hash->{READINGS};
	}
	elsif($sect eq "msgEvents"){
	  CUL_HM_respPendRm($hash);
	  delete ($hash->{helper}{burstEvtCnt});
	  delete ($hash->{cmdStack});
	  foreach my $var (keys %{$attr{$name}}){ # can be removed versions later
	    delete ($attr{$name}{$var}) if ($var =~ m/^prot/);
      }
	  foreach my $var (keys %{$hash}){
		delete ($hash->{$var}) if ($var =~ m/^prot/);
		delete ($hash->{EVENTS});
		delete ($hash->{helper}{rssi});
      }
	  $hash->{protState} = "Info_Cleared" ;
	}
	else{
	  return "unknown section. User readings or msgEvents";
	}
	$state = "";
  } 
  elsif($cmd eq "reset") { ####################################################
	CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  } 
  elsif($cmd eq "pair") { #####################################################
	$state = "";
    my $serialNr = AttrVal($name, "serialNr", undef);
    return "serialNr is not set" if(!$serialNr);
    CUL_HM_PushCmdStack($hash,"++A401".$id."000000010A".unpack("H*",$serialNr));
    $hash->{hmPairSerial} = $serialNr;
  } 
  elsif($cmd eq "unpair") { ###################################################
    CUL_HM_pushConfig($hash, $id, $dst, 0,0,0,0, "02010A000B000C00");
    $state = "";
  } 
  elsif($cmd eq "sign") { #####################################################
    CUL_HM_pushConfig($hash, $id, $dst, $chn,0,0,$chn,
                    "08" . ($a[2] eq "on" ? "01":"02"));
	$state = "";
  }
  elsif($cmd eq "statusRequest") { ############################################
    my @chnIdList = CUL_HM_getAssChnIds($name);
    foreach my $channel (@chnIdList){
	  my $chnNo = substr($channel,6,2);
	  CUL_HM_PushCmdStack($hash,"++".$flag.'01'.$id.$dst.$chnNo.'0E');
    }
	$state = "";
  } 
  elsif($cmd eq "getpair") { ##################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000');
	$state = "";	
  } 
  elsif($cmd eq "getdevicepair") { ############################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chn.'03');
	$state = "";
  } 
  elsif($cmd eq "getConfig") { ################################################
	my $chFound = 0;
	CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000')
	       if (!$isChannel);
	my @chnIdList = CUL_HM_getAssChnIds($name);
	foreach my $channel (@chnIdList){
	  my $chnHash = CUL_HM_id2Hash($channel);
	  CUL_HM_getConfig($hash,$chnHash,$id,$dst,substr($channel,6,2));
	}
	$state = "";
  } 
  elsif($cmd eq "peerBulk") { #################################################
	$state = "";
	my $pL = $a[2];
	foreach my $peer (split(',',$pL)){
	  next if ($peer =~ m/^self/);
	  my $pID = CUL_HM_peerChId($peer,$dst,$id);
	  return "unknown peer".$peer if (length($pID) != 8);# peer only to channel
	  my $pCh1 = substr($pID,6,2);
	  my $pCh2 = $pCh1;
      if($culHmSubTypeSets{$st}{devicepair}||
         $culHmModelSets{$md}{devicepair}||
         $culHmChanSets{$mdCh}{devicepair}){
	    $pCh2 = "00";                        # button behavior
      }
	  CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chn.'01'.
	                      substr($pID,0,6).$pCh1.$pCh2);
	}
  } 
  elsif($cmd eq "regRaw" ||$cmd eq "regBulk"||$cmd eq "getRegRaw") { ##########
    my ($list,$addr,$data,$peerID);
	$state = "";
	($list,$addr,$data,$peerID) = ($a[2],hex($a[3]),hex($a[4]),$a[5])
	                               if ($cmd eq "regRaw");
	if ($cmd eq "regBulk"){
	  ($list) = ($a[2]);
	  $list =~ s/[\.]?RegL_//;
	  ($list,$peerID) = split(":",$list);
	  return "unknown list Number:".$list if(hex($list)>6);
	}

	($list,$peerID) = ($a[2],$a[3])if ($cmd eq "getRegRaw");#todo Updt2 remove
	$list =~ s/List/0/;# convert Listy to 0y
	# as of now only hex value allowed check range and convert
	
    $peerID  = CUL_HM_peerChId(($peerID?$peerID:"00000000"),$dst,$id);	  
	my $peerChn = ((length($peerID) == 8)?substr($peerID,6,2):"01");# have to split chan and id
	$peerID = substr($peerID,0,6);

	if($cmd eq "getRegRaw"){
	  if ($list eq "00"){
	    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000');
	  }
	  else{# other lists are per channel
	    my @chnIdList = CUL_HM_getAssChnIds($name);
        foreach my $channel (@chnIdList){
		  my $chnNo = substr($channel,6,2);
		  if ($list =~m /0[34]/){#getPeers to see if list3 is available 
			CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chnNo.'03');
			my $chnHash = CUL_HM_id2Hash($channel);
		    $chnHash->{helper}{getCfgList} = $peerID.$peerChn;#list3 regs 
		    $chnHash->{helper}{getCfgListNo} = int($list);
		  }
		  else{
			CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chnNo.'04'
			                              .$peerID.$peerChn.$list);
		  }
		}
	  }
	}
	elsif($cmd eq "regBulk"){;
	  my @adIn = @a;
	  shift @adIn;shift @adIn;shift @adIn;
	  my $adList;
	  foreach my $ad (sort @adIn){
	    ($addr,$data) = split(":",$ad);
		$adList .= sprintf("%02X%02X",hex($addr),hex($data)) if ($addr ne "00");
		return "wrong addr or data:".$ad if (hex($addr)>255 || hex($data)>255);
	  }
      CUL_HM_pushConfig($hash,$id,$dst,$chn,$peerID,$peerChn,$list,$adList);
	}
	else{                                                    #todo Updt2 remove
	  return "outdated - use regBulk with changed format";   #todo Updt2 remove
	}                                                        #todo Updt2 remove
  } 
  elsif($cmd eq "regSet") { ###################################################
    #set <name> regSet <regName> <value> <peerChn> 
	my ($regName,$data,$peerChnIn) = ($a[2],$a[3],$a[4]);
	$state = "";
    if (!$culHmRegType{$st}{$regName}      && 
	    !$culHmRegGeneral{$regName}        &&
	    !$culHmRegModel{$md}{$regName}     && 
	    !$culHmRegChan{$md.$chn}{$regName} 	){
      my @regArr = keys %culHmRegGeneral ;
	  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st});
	  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md});
	  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn});
	  return "supported register are ".join(" ",sort @regArr);
	}
	   
    my $reg  = $culHmRegDefine{$regName};
	return $st." - ".$regName            # give some help
	       ." range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
		   .(($reg->{l} == 3)?" peer required":"")." : ".$reg->{t}."\n"
		          if ($data eq "?");
	return "value:".$data." out of range for Reg \"".$regName."\""
	        if (!($reg->{c} eq 'lit'||$reg->{c} eq 'hex')&&
			    ($data < $reg->{min} ||$data > $reg->{max})); # none number
    return"invalid value. use:". join(",",keys%{$reg->{lit}}) 
	        if ($reg->{c} eq 'lit' && !defined($reg->{lit}{$data}));
	
	my $conversion = $reg->{c};
	if (!$conversion){;# do nothing
	}elsif($conversion eq "factor"){$data *= $reg->{f};# use factor
	}elsif($conversion eq "fltCvT"){$data = CUL_HM_fltCvT($data);
	}elsif($conversion eq "m10s3") {$data = $data*10-3;
	}elsif($conversion eq "hex")   {$data = hex($data);
	}elsif($conversion eq "lit")   {$data = $reg->{lit}{$data};
	}else{return " conversion undefined - please contact admin";
	}
	
	my $addr = int($reg->{a});        # bit location later
	my $list = $reg->{l};
	my $bit  = ($reg->{a}*10)%10; # get fraction
	
	my $dLen = $reg->{s};             # datalength in bit
	$dLen = int($dLen)*8+(($dLen*10)%10);
	# only allow it level if length less then one byte!!
	return "partial Word error: ".$dLen if($dLen != 8*int($dLen/8) && $dLen>7);
	no warnings qw(overflow portable);
	my $mask = (0xffffffff>>(32-$dLen));
	use warnings qw(overflow portable);
	my $dataStr = substr(sprintf("%08X",($data & $mask) << $bit),
	                                       8-int($reg->{s}+0.99)*2,);
	
    my ($lChn,$peerID,$peerChn) = ($chn,"000000","00");
	if (($list == 3) ||($list == 4)){ # peer is necessary for list 3/4
	  return "Peer not specified" if (!$peerChnIn);
	  $peerID  = CUL_HM_peerChId($peerChnIn,$dst,$id);	  
 	  $peerChn = ((length($peerID) == 8)?substr($peerID,6,2):"01");
      $peerID  = substr($peerID,0,6);	
      return "Peer not specified" if (!$peerID);	  
	}
	elsif($list == 0){
      $lChn = "00";
	}
	else{  #if($list == 1/5/6){
      $lChn = "01" if ($chn eq "00"); #by default select chan 01 for device
	}
	
    my $addrData;
	if ($dLen < 8){# fractional byte see whether we have stored the register
	  #read full 8 bit!!!
	  my $rName = CUL_HM_id2Name($dst.$lChn);
	  $rName =~ s/_chn:.*//;
	  my $curVal = CUL_HM_getRegFromStore($rName,
	                                      $addr,$list,$peerID.$peerChn);
	  return "cannot read current value for Bitfield - retrieve Data first" 
	             if (!$curVal);
	  $curVal =~ s/set_//; # set is not relevant, we take it as given
	  $data = ($curVal & (~($mask<<$bit)))|($data<<$bit);
	  $addrData.=sprintf("%02X%02X",$addr,$data);
	}
	else{
	  for (my $cnt = 0;$cnt<int($reg->{s}+0.99);$cnt++){
	    $addrData.=sprintf("%02X",$addr+$cnt).substr($dataStr,$cnt*2,2);
	  }
	}
    CUL_HM_pushConfig($hash,$id,$dst,$lChn,$peerID,$peerChn,$list,$addrData);
  } 
  elsif($cmd eq "level") { ####################################################
	#level        =>"<level> <relockDly> <speed>..."
    my (undef,undef,$lvl,$rLocDly,$speed) = @a; 
	return "please enter level 0 to 100" if (!defined($lvl)    || $lvl>100);
	return "reloclDelay range 0..65535 or ignore"
	                                     if (defined($rLocDly) && 
										     ($rLocDly > 65535 || 
											  ($rLocDly < 0.1 && $rLocDly ne 'ignore' && $rLocDly ne '0' )));
	return "select speed range 0 to 100" if (defined($speed)   && $speed>100);
    $rLocDly = 111600 if (!defined($rLocDly)||$rLocDly eq "ignore");# defaults
    $speed = 30 if (!defined($rLocDly));
	$rLocDly = CUL_HM_encodeTime8($rLocDly);# calculate hex value
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'81'.$chn.
	                    sprintf("%02X%02s%02X",$lvl*2,$rLocDly,$speed*2));
  } 
  elsif($cmd eq "on") { #######################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.'C80000');
	$hash = $chnHash; # report to channel if defined
  } 
  elsif($cmd eq "off") { ######################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.'000000');
	$hash = $chnHash; # report to channel if defined
  } 
  elsif($cmd eq "on-for-timer"||$cmd eq "on-till") { ##########################
    my (undef,undef,$duration,$edate) = @a; #date prepared extention to entdate
    if ($cmd eq "on-till"){
	  # to be extended to handle end date as well
	  my ($eH,$eM,$eSec)  = split(':',$duration); 
	  $eSec += $eH*3600 + $eM*60;
	  my @lt = localtime;	  
	  my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
	  $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
	  $duration = $eSec - $ltSec;	  
    }
	return "please enter the duration in seconds" if (!defined ($duration));
    $tval = CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.'C80000'.$tval);
 	$hash = $chnHash; # report to channel if defined
 } 
  elsif($cmd eq "toggle") { ###################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.
	            (ReadingsVal($name,"state","on") eq "off" ?"C80000":"000000"));
	$hash = $chnHash; # report to channel if defined
  }
  elsif($cmd eq "lock") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800100FF');	# LEVEL_SET
  }
  elsif($cmd eq "unlock") { ###################################################
  	$tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800101'.$delay);# LEVEL_SET
  }
  elsif($cmd eq "open") { #####################################################
  	$tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'8001C8'.$delay);# OPEN
	$state = "";
  }
  elsif($cmd eq "inhibit") { ##################################################
  	return "$a[2] is not on or off" if($a[2] !~ m/^(on|off)$/);
 	my $val = ($a[2] eq "on") ? "01" : "00";
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$val.'01');	# SET_LOCK
	$state = "";
  }
  elsif($cmd eq "pct") { ######################################################
    $a[1] = 100 if ($a[1] > 100);
    $tval = CUL_HM_encodeTime16(((@a > 2)&&$a[2]!=0)?$a[2]:6709248);# onTime   0.0..6709248, 0=forever
    $rval = CUL_HM_encodeTime16((@a > 3)?$a[3]:2.5);     # rampTime 0.0..6709248, 0=immediate
    CUL_HM_PushCmdStack($hash, 
	    sprintf("++%s11%s%s02%s%02X%s%s",$flag,$id,$dst,$chn,$a[1]*2,$rval,$tval));
  } 
  elsif($cmd eq "stop") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
  } 
  elsif($cmd eq "text") { #####################################################
    $state = "";
    return "$a[2] is not a button number" if($a[2] !~ m/^\d$/ || $a[2] < 1);
    return "$a[3] is not on or off" if($a[3] !~ m/^(on|off)$/);
    my $bn = $a[2]*2-($a[3] eq "on" ? 0 : 1);

    my ($l1, $l2, $s);     # Create CONFIG_WRITE_INDEX string
    $l1 = $a[4] . "\x00";
    $l1 = substr($l1, 0, 13);
    $s = 54;
    $l1 =~ s/(.)/sprintf("%02X%02X",$s++,ord($1))/ge;

    $l2 = $a[5] . "\x00";
    $l2 = substr($l2, 0, 13);
    $s = 70;
    $l2 =~ s/(.)/sprintf("%02X%02X",$s++,ord($1))/ge;
    $l1 .= $l2;

    CUL_HM_pushConfig($hash, $id, $dst, $bn,0,0,1, $l1);
  } 
  elsif($cmd eq "setRepeat") { ################################################
    #      setRepeat    => "[no1..36] <sendName> <recName> [bdcast-yes|no]"}
    $state = "";
    return "entry must be between 1 and 36" if ($a[2] < 1 || $a[2] > 36);	
	my $sndID = CUL_HM_name2Id($a[3]);
	my $recID = CUL_HM_name2Id($a[4]);
    return "sender ID unknown:".$sndID    if ($sndID !~ m/(^[0-9A-F]{6})$/);	
    return "receiver ID unknown:".$recID  if ($recID !~ m/(^[0-9A-F]{6})$/);	
    return "broadcast must be yes or now" if ($a[5] ne "yes" && $a[5] ne "no");
	my $pattern = $sndID.$recID.(($a[5] eq "no")?"00":"01");
    my $cnt = ($a[2]-1)*7+1;
	my $addrData;
    foreach ($pattern =~ /(.{2})/g){
      $addrData .= sprintf("%02X%s",$cnt++,$_);
    }
    CUL_HM_pushConfig($hash, $id, $dst, 1,0,0,2, $addrData);
	
  }
  elsif($cmd eq "display") { ################################################## 
	my (undef,undef,undef,$t,$c,$u,$snd,$blk,$symb) = @_;
	return "cmd only possible for device or its display channel"
	       if ($isChannel && $chn ne "12");
	my %symbol=(off => 0x0000,
	            bulb =>0x0100,switch =>0x0200,window   =>0x0400,door=>0x0800,
                blind=>0x1000,scene  =>0x2000,phone    =>0x4000,bell=>0x8000,
                clock=>0x0001,arrowUp=>0x0002,arrowDown=>0x0004);
    my %light=(off=>0,on=>1,slow=>2,fast=>3);
    my %unit=(off =>0,Proz=>1,Watt=>2,x3=>3,C=>4,x5=>5,x6=>6,x7=>7,
		      F=>8,x9=>9,x10=>10,x11=>11,x12=>12,x13=>13,x14=>14,x15=>15);
		
    my @symbList = split(',',$symb);
    my $symbAdd = "";
    foreach my $symb (@symbList){
      if (!defined($symbol{$symb})){# wrong parameter
	    return "'$symb ' unknown. Select one of ".join(" ",sort keys(%symbol));
	  }
      $symbAdd |= $symbol{$symb};
    }
	
	return "$c not specified. Select one of [comma|no]" 
	       if ($c ne "comma" && $c ne "no");
	return "'$u' unknown. Select one of ".join(" ",sort keys(%unit)) 
	       if (!defined($unit{$u}));
    return "'$snd' unknown. Select one of [off|1|2|3]"
           if ($snd ne "off" && $snd > 3);
    return "'$blk' unknown. Select one of ".join(" ",sort keys(%light))
           if (!defined($light{$blk}));
    my $beepBack = $snd | $light{$blk}*4;

    $symbAdd |= 0x0004 if ($c eq "comma");
	$symbAdd |= $unit{$u};
	  
	my $text = sprintf("%5.5s",$t);#pad left with space
	$text = uc(unpack("H*",$text));

    CUL_HM_PushCmdStack($hash,sprintf("++%s11%s%s8012%s%04X%02X",
	                                  $flag,$id,$dst,$text,$symbAdd,$beepBack));
  } 
  elsif($cmd eq "alarm"||$cmd eq "service") { #################################
	return "$a[2] must be below 255"  if ($a[2] >255 );
	$chn = 18 if ($chn eq "01");
	my $subtype = ($cmd eq "alarm")?"81":"82";
    CUL_HM_PushCmdStack($hash,
          sprintf("++%s11%s%s%s%s%02X",$flag,$id,$dst,$subtype,$chn, $a[2]));
  } 
  elsif($cmd eq "led") { ######################################################
	if ($md eq "HM-OU-LED16"){
	  my %color=(off=>0,red=>1,green=>2,orange=>3);
	  if (length($hash->{DEF}) == 6){# command called for a device, not a channel
	    my $col4all;
	    if (defined($color{$a[2]})){
	      $col4all = sprintf("%02X",$color{$a[2]}*85);#Color for 4 LEDS
	      $col4all = $col4all.$col4all.$col4all.$col4all;#and now for 16
		}
		elsif ($a[2] =~ m/^[A-Fa-f0-9]{1,8}$/i){
		  $col4all = sprintf("%08X",hex($a[2]));
		}
        else{
  	      return "$a[2] unknown. use hex or: ".join(" ",sort keys(%color));
		}
		CUL_HM_UpdtReadBulk($hash,1,"color:".$col4all,
		                            "state:set_".$col4all);
        CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."8100".$col4all);
	  }else{# operating on a channel
  	    return "$a[2] unknown. use: ".join(" ",sort keys(%color))
	       if (!defined($color{$a[2]}) );
        CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.'0'.$color{$a[2]});
	  }
	}
	elsif($md eq "HM-OU-CFM-PL"){
	  return "use channel 1 of the device for LED" if ($chn != 1);
	  my %color = (redL =>18,greenL =>34,orangeL =>50,
	               redS =>17,greenS =>33,orangeS =>49);
	  my @ledList = split(',',$a[2]);
	  my $ledBytes;
	  foreach my $led (@ledList){
        if (!$color{$led} ){# wrong parameter
	        return "'$led' unknown. use: ".join(" ",sort keys(%color));
	    }
        $ledBytes .= sprintf("%02X",$color{$led});
	  }
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.'0101'.$ledBytes);
	}
	else{
	  return "device for command cannot be identified";
	}
  } 
  elsif($cmd eq "playTone") { #################################################
    $chn = "02" if (length($hash->{DEF}) == 6);# be nice, select implicite
	return "use channel 2 of the device to play MP3" if ($chn != 2);
	my @mp3List = split(',',$a[2]);
	my $mp3Bytes;
	foreach my $mp3 (@mp3List){
      $mp3Bytes .= sprintf("%02X",$mp3);
	}
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.'0202'.$mp3Bytes);
  } 
  elsif($cmd eq "ilum") { #####################################################
	return "$a[2] not specified. choose 0-15 for brightness"  if ($a[2]>15);
	return "$a[3] not specified. choose 0-127 for duration"  if ($a[3]>127);
	return "unsupported for HMid:".$hash->{DEF}.", use HMId:".substr($hash->{DEF},0,6)
	                  if (length($hash->{DEF}) != 6);
	my $addrData = sprintf("04%02X08%02X",$a[2],$a[3]*2);
	# write list0,
	CUL_HM_pushConfig($hash,$id,$dst,0,0,0,0,$addrData);
  } 
  elsif(($cmd eq "displayMode")||($cmd eq "displayTemp")||
		($cmd eq "controlMode")||($cmd eq "decalcDay")  ||
		($cmd eq "displayTempUnit") ){ ########################################
    my %regs = (displayTemp     =>{actual=>0,setpoint=>2},
                displayMode     =>{"temp-only"=>0,"temp-hum"=>1},
                displayTempUnit =>{celsius=>0,fahrenheit=>4},
                controlMode     =>{manual=>0,auto=>8,central=>16,party=>24},
  			    decalcDay       =>{Sat=>0  ,Sun=>32 ,Mon=>64,Tue=>96, 
				                   Wed=>128,Thu=>160,Fri=>192});
	return $a[2]."invalid for ".$cmd." select one of ". 
	      join (" ",sort keys %{$regs{$cmd}}) if(!defined($regs{$cmd}{$a[2]}));
    readingsSingleUpdate($hash,$cmd,$a[2],1);
    my $tcnf = 0;
    my $missingEntries; 
    foreach my $entry (keys %regs){
      if (!$hash->{READINGS}{$entry}){
        $missingEntries .= $entry." ";
	  }
	  else{
	    $tcnf |=  $regs{$entry}{$hash->{READINGS}{$entry}{VAL}};
	  }
    }
    return "please complete settings for ".$missingEntries if($missingEntries);

	CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,5, "01".sprintf("%02X",$tcnf));
  } 
  elsif($cmd eq "desired-temp") { #############################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'0202'.
	                                                   CUL_HM_convTemp($a[2]));
    my $chnHash = CUL_HM_id2Hash($dst."02");
	my $mode = ReadingsVal($chnHash->{NAME},"R-MdTempReg","");
	readingsSingleUpdate($chnHash,"desired-temp-cent",$a[2],1) 
	      if($mode eq 'central ');
  } 
  elsif($cmd =~ m/^(day|night|party)-temp$/) { ################################
    my %tt = (day=>"03", night=>"04", party=>"06");
    my $tt = $tt{$1};
    CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,5, "$tt".CUL_HM_convTemp($a[2])); 
  } 
  elsif($cmd =~ m/^tempList(...)/) { ##########################################
    my %day2off = ( "Sat"=>"5 0B", "Sun"=>"5 3B", "Mon"=>"5 6B",
                    "Tue"=>"5 9B", "Wed"=>"5 CB", "Thu"=>"6 01",
                    "Fri"=>"6 31");
    my $wd = $1;
    my ($list,$addr) = split(" ", $day2off{$wd});
    $addr = hex($addr);

    return "To few arguments"                   if(@a < 4);
    return "To many arguments, max is 24 pairs" if(@a > 50);
    return "Bad format, use HH:MM TEMP ..."     if(@a % 2);
    return "Last time spec must be 24:00"       if($a[@a-2] ne "24:00");
    my $data = "";
    my $msg = "";
    for(my $idx = 2; $idx < @a; $idx += 2) {
      return "$a[$idx] is not in HH:MM format"
                                if($a[$idx] !~ m/^([0-2]\d):([0-5]\d)/);
      my ($h, $m) = ($1, $2);
      $data .= sprintf("%02X%02X%02X%s", $addr, $h*6+($m/10), $addr+1,
	                                              CUL_HM_convTemp($a[$idx+1]));
      $addr += 2;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{HOUR} = $h;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{MINUTE} = $m;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{TEMP} = $a[$idx+1];
      $msg .= sprintf(" %02d:%02d %.1f", $h, $m, $a[$idx+1]);
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,$list, $data);
	readingsSingleUpdate($hash,"tempList$wd",$msg,0);
  } 
  elsif($cmd eq "valvePos") { #################################################
	return "only number <= 100  or 'off' allowed" 
	   if (!($a[2] eq "off" ||$a[2]+0 ne $a[2] ||$a[2] <100 ));
    if ($a[2] eq "off"){
	  $state = "ValveAdjust:stopped";
	  RemoveInternalTimer("valvePos:$dst$chn");# remove responsePending timer
	  delete($hash->{helper}{virtTC});
	}
	else {
	  my $vp = $a[2];
	  readingsSingleUpdate($hash,"valvePosTC","$vp %",0);
	  CUL_HM_valvePosUpdt("valvePos:$dst$chn") if (!$hash->{helper}{virtTC});
	  $hash->{helper}{virtTC} = "03";
	  $state = "ValveAdjust:$vp %";
	}
  } 
  elsif($cmd eq "matic") { ####################################################
    # Trigger pre-programmed action in the winmatic. These actions must be
    # programmed via the original software.
    CUL_HM_PushCmdStack($hash,
        sprintf("++%s3E%s%s%s40%02X%s", $flag,$id, $dst, $id, $a[2], $chn));
  } 
  elsif($cmd eq "create") { ###################################################
    CUL_HM_PushCmdStack($hash, 
        sprintf("++%s01%s%s0101%s%02X%s",$flag,$id, $dst, $id, $a[2], $chn));
    CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s0104%s%02X%s", $id, $dst, $id, $a[2], $chn));
  } 
  elsif($cmd eq "keydef") { ###################################################
    if (     $a[3] eq "tilt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B220D838B228D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "close")     {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B550D838B558D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "closed")    {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0F008F00");        #offLevel (also thru register)
    } elsif ($a[3] eq "bolt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0FFF8FFF");        #offLevel (also thru register)
    } elsif ($a[3] eq "speedclose"){CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("23%02XA3%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } elsif ($a[3] eq "speedtilt") {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("22%02XA2%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } elsif ($a[3] eq "delete")    {CUL_HM_PushCmdStack($hash,sprintf("++%s01%s%s0102%s%02X%s",$flag,$id, $dst, $id, $a[2], $chn));#unlearn key
    } else {
      return 'unknown argument '.$a[3];
    }
  } 
  elsif($cmd eq "test") { #####################################################
    my $testnr = $hash->{TESTNR} ? ($hash->{TESTNR} +1) : 1;
    $hash->{TESTNR} = $testnr;
	my $msg = sprintf("++9440%s%s00%02X",$dst,$dst,$testnr);
    CUL_HM_SndCmd($hash, $msg);# repeat non-ack messages - delivery uncertain
    CUL_HM_SndCmd($hash, $msg);
    CUL_HM_SndCmd($hash, $msg);
  } 
  elsif($cmd =~ m/alarm(.*)/) { ###############################################
    my $msg = sprintf("++9441%s%s01%s",$dst,$dst,(($1 eq "On")?"0BC8":"0C01"));
    CUL_HM_SndCmd($hash, $msg);# repeat non-ack messages - delivery uncertain
    CUL_HM_SndCmd($hash, $msg);
    CUL_HM_SndCmd($hash, $msg);
  } 
  elsif($cmd eq "virtual") { ##################################################
  	$state = "";
    my (undef,undef,$maxBtnNo) = @a;
	return "please give a number between 1 and 255"
	   if ($maxBtnNo < 1 ||$maxBtnNo > 255);# arbitrary - 255 should be max
    return $name." already defines as ".$attr{$name}{subType}
	   if ($attr{$name}{subType} && $attr{$name}{subType} ne "virtual");
    $attr{$name}{subType} = "virtual";
    $attr{$name}{model}   = "virtual_".$maxBtnNo;
    my $devId = $hash->{DEF};
    for (my $btn=1;$btn <= $maxBtnNo;$btn++){
	  my $chnName = $name."_Btn".$btn;
	  my $chnId = $devId.sprintf("%02X",$btn);
	  DoTrigger("global",  "UNDEFINED $chnName CUL_HM $chnId")
		  if (!$modules{CUL_HM}{defptr}{$chnId});
	}
	foreach my $channel (keys %{$hash}){# remove higher numbers
	  my $chNo = $1 if($channel =~ m/^channel_(.*)/);
	  next if (!defined($chNo));
	  CommandDelete(undef,$hash->{$channel})
	        if (hex($chNo) > $maxBtnNo);
	}
  }
  elsif($cmd eq "actiondetect"){###############################################todo Updt3 remove
    return "outdated - use attr <name> actCycle instead";
  }
  elsif($cmd eq "press") { ####################################################
    my (undef,undef,$mode,$vChn) = @a;
	my $pressCnt = (!$hash->{helper}{count}?1:$hash->{helper}{count}+1)%256;
	$hash->{helper}{count}=$pressCnt;# remember for next round

	my @peerList;
	if ($st eq 'virtual'){#serve all peers of virtual button
	  foreach my $peer (sort(split(',',AttrVal($name,"peerIDs","")))) {
	    push (@peerList,substr($peer,0,6));
	  }
	  @peerList = CUL_HM_noDup(@peerList);
	  push @peerList,'00000000' if (!@peerList);#send to broadcast if no peer
	  foreach my $peer (sort @peerList){
	    my $peerFlag = $peer eq '00000000'?'A4':
	                                       CUL_HM_getFlag(CUL_HM_id2Hash($peer));
	    $peerFlag =~ s/0/4/;# either 'A4' or 'B4'
        CUL_HM_PushCmdStack($hash, sprintf("++%s40%s%s%02X%02X",
	                   $peerFlag,$dst,$peer,
					   $chn+(($mode && $mode eq "long")?64:0),
					   $pressCnt));
	  }
	}
	else{#serve internal channels for actor
	  my $pChn = $chn; # simple device, only one button per channel
	  $pChn = (($vChn && $vChn eq "off")?-1:0) + $chn*2 if($st ne 'switch');
      CUL_HM_PushCmdStack($hash, sprintf("++%s3E%s%s%s40%02X%02X",$flag,
	                                  $id,$dst,$dst,
                                     $pChn+(($mode && $mode eq "long")?64:0),
									  $pressCnt));                                     
	}
  } 
  elsif($cmd eq "devicepair") { ###############################################
    #devicepair <btnN> device ... [single|dual] [set|unset] [actor|remote|both]
	my ($bNo,$peerN,$single,$set,$target) = ($a[2],$a[3],$a[4],$a[5],$a[6]);
	$state = "";
	return "$bNo is not a button number"                          if(($bNo < 1) && !$chn);
	my $peerDst = CUL_HM_name2Id($peerN);
	$peerDst .= "01" if( length($peerDst)==6);
    return "please enter peer"                                    if(!$peerDst);
	my $peerChn = substr($peerDst,6,2);
	$peerDst = substr($peerDst,0,6);
    my $peerHash;
	$peerHash = $modules{CUL_HM}{defptr}{$peerDst.$peerChn}if ($modules{CUL_HM}{defptr}{$peerDst.$peerChn});
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst}         if (!$peerHash);
    return "$peerN not a CUL_HM device"                           if($target && ($target ne "remote") &&(!$peerHash ||$peerHash->{TYPE} ne "CUL_HM"));
    return "$single must be single or dual"                       if(defined($single) && (($single ne"single") &&($single ne"dual")));
    return "$set must be set or unset"                            if(defined($set) && (($set ne"set") &&($set ne"unset")));  
    return "$target must be [actor|remote|both]"                  if(defined($target) && (($target ne"actor")&&($target ne"remote")&&($target ne"both")));  
	return "use climate chan to pair TC"                          if( $md eq "HM-CC-TC" &&$chn ne "02");
	return "use - single [set|unset] actor - for smoke detector"  if( $st eq "smokeDetector"       && (!$single || $single ne "single" || $target ne "actor"));
	return "use - single - for ".$st                              if(($st eq "threeStateSensor"||
	                                                                  $st eq "motionDetector" )    && (!$single || $single ne "single"));

	$single = ($single eq "single")?1:"";#default to dual
	$set = ($set eq "unset")?0:1;

	my ($b1,$b2,$nrCh2Pair);
	$b1 = ($isChannel) ? hex($chn):(!$bNo?"01":$bNo);
	$b1 = $b1*2 - 1 if(!$single && !$isChannel);
	if ($single){
	  $b2 = $b1;
	  $b1 = 0 if ($st eq "smokeDetector");
	  $nrCh2Pair = 1;
	}
	else{
	    $b2 = $b1 + 1;
	    $nrCh2Pair = 2;
	}
	my $cmdB = ($set)?"01":"02";# do we set or remove?

    # First the remote (one loop for on, one for off)
	if (!$target || $target eq "remote" || $target eq "both"){
      for(my $i = 1; $i <= $nrCh2Pair; $i++) {
        my $b = ($i==1 ? $b1 : $b2);		
  	    if ($st eq "virtual"){
		  my $btnName = CUL_HM_id2Name($dst.sprintf("%02X",$b));
		  return "button ".$b." not defined for virtual remote ".$name
		      if (!defined $attr{$btnName});
		  CUL_HM_ID2PeerList ($btnName,$peerDst.$peerChn,$set); #update peerlist
	    }
		else{
		  my $bStr = sprintf("%02X",$b);
  	      CUL_HM_PushCmdStack($hash, 
  	              "++".$flag."01${id}${dst}${bStr}$cmdB${peerDst}${peerChn}00");
  	      CUL_HM_pushConfig($hash,$id, $dst,$b,$peerDst,hex($peerChn),4,"0100")
				   if($md ne "HM-CC-TC");
	    }
      }
	}
	if (!$target || $target eq "actor" || $target eq "both"){
	  if (AttrVal( CUL_HM_id2Name($peerDst), "subType", "") eq "virtual"){
		CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b2),$set); #update peerlist
		CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b1),$set) if ($b1 & !$single); #update peerlist
	  }
	  else{
	    my $peerFlag = CUL_HM_getFlag($peerHash);
        CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",
            $peerFlag,$id,$peerDst,$peerChn,$cmdB,$dst,$b2,$b1 ));
	  }
	}
	return ("",1) if ($target && $target eq "remote");#Nothing to transmit for actor
    $devHash = $peerHash; # Exchange the hash, as the switch is always alive.
  }
  
  readingsSingleUpdate($hash,"state",$state,1) if($state);

  $rxType = CUL_HM_getRxType($devHash);
  Log GetLogLevel($name,2), "CUL_HM set $name " . 
                            join(" ", @a[1..$#a])." rxt:".$rxType;
  CUL_HM_ProcessCmdStack($devHash) if($rxType & 0x03);#all/burst
  return ("",1);# no not generate trigger outof command
}

###################################
my $updtValveCnt = 0;

sub CUL_HM_valvePosUpdt(@) {# update valve position periodically to please valve
  my($in ) = @_;
  my(undef,$vId) = split(':',$in);
  my $hash = CUL_HM_id2Hash($vId);
  my $vDevId = substr($vId,0,6);
  my $nextTimer = 150;

#  if ($updtValveCnt++ %2){
#    $nextTimer = 20;
#    CUL_HM_PushCmdStack($hash,"++8670".$vDevId."00000000D036");# some weather event - 
#  }
#  else{
    my $name = $hash->{NAME};
    my $vp = ReadingsVal($name,"valvePosTC","15 %");
    $vp =~ s/ %//;
    $vp *=2.56;
	foreach my $peer (sort(split(',',AttrVal($name,"peerIDs","")))) {
	  next if (length($peer) != 8);
	  $peer = substr($peer,0,6);	
	  CUL_HM_PushCmdStack($hash,sprintf("++A258%s%s%s%02X",$vDevId,$peer,$hash->{helper}{virtTC},$vp));
	}
#  }
  $hash->{helper}{virtTC} = "00";
  CUL_HM_ProcessCmdStack($hash);
  InternalTimer(gettimeofday()+$nextTimer,"CUL_HM_valvePosUpdt","valvePos:$vId",0);
}
sub CUL_HM_infoUpdtDevData($$$) {#autoread config
  my($name,$hash,$p) = @_;
  my($fw,$mId,$serNo,$stc,$devInfo) = ($1,$2,$3,$4,$5) 
	                   if($p =~ m/(..)(.{4})(.{20})(.{2})(.*)/);
  my $model = $culHmModel{$mId}{name} ? $culHmModel{$mId}{name}:"unknown";
  $attr{$name}{model}    = $model;
  $attr{$name}{subType}  = $culHmModel{$mId}{st};
  $attr{$name}{serialNr} = pack('H*',$serNo);
  #expert level attributes
  $attr{$name}{firmware} = 
        sprintf("%d.%d", hex(substr($p,0,1)),hex(substr($p,1,1)));
  $attr{$name}{".devInfo"} = $devInfo;
  $attr{$name}{".stc"}     = $stc;
  
  delete $hash->{helper}{rxType};
  CUL_HM_getRxType($hash); #will update rxType
  $mId = CUL_HM_getMId($hash);# set helper valiable and use result 
  
  # autocreate undefined channels  
  my @chanTypesList = split(',',$culHmModel{$mId}{chn});
  my $startime = gettimeofday()+1;
  foreach my $chantype (@chanTypesList){
    my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
	my $chnNoTyp = 1;
	for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
	  my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
	  if (!$modules{CUL_HM}{defptr}{$chnId}){
        my $chnName = $name."_".$chnTpName.(($chnStart == $chnEnd)?
	                            '':'_'.sprintf("%02d",$chnNoTyp));
		InternalTimer($startime++,"CUL_HM_infoUpdtChanData",
		"$chnName,$chnId,$model",0);
      }
	  $attr{CUL_HM_id2Name($chnId)}{model} = $model;
	  $chnNoTyp++;
	}
  }
  if ($culHmModel{$mId}{cyc}){
    CUL_HM_ActAdd($hash->{DEF},AttrVal($name,"actCycle",
	                                         $culHmModel{$mId}{cyc}));
  }

}
sub CUL_HM_infoUpdtChanData(@) {# verify attributes after reboot
  my($in ) = @_;
  my($chnName,$chnId,$model ) = split(',',$in);
  DoTrigger("global",  'UNDEFINED '.$chnName.' CUL_HM '.$chnId);
  $attr{CUL_HM_id2Name($chnId)}{model} = $model;
}
sub CUL_HM_Pair(@) {
  my ($name, $hash,$cmd,$src,$dst,$p) = @_;
  my $iohash = $hash->{IODev};
  my $id = CUL_HM_Id($iohash);
  my $serNo = $attr{$name}{serialNr};

  Log GetLogLevel($name,3),
      "CUL_HM pair: $name $attr{$name}{subType}, model $attr{$name}{model} serialNr $serNo";

  # Abort if we are not authorized
  if($dst eq "000000") {
    if(!$iohash->{hmPair} &&
       (!$iohash->{hmPairSerial} || $iohash->{hmPairSerial} ne $serNo)) {
      Log GetLogLevel($name,3),
        $iohash->{NAME}. " pairing (hmPairForSec) not enabled";
      return "";
    }
  } 
  elsif($dst ne $id) {
    return "" ;
  } 
  elsif($cmd eq "0400") {     # WDC7000
    return "" ;
  } 
  elsif($iohash->{hmPairSerial}) {
    delete($iohash->{hmPairSerial});
  }
  
  my ($idstr, $s) = ($id, 0xA);
  $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;
  CUL_HM_pushConfig($hash, $id, $src,0,0,0,0, "0201$idstr");
  CUL_HM_ProcessCmdStack($hash); # start processing immediately
  return "";
}
sub CUL_HM_getConfig($$$$$){
  my ($hash,$chnhash,$id,$dst,$chn) = @_;
  my $flag = CUL_HM_getFlag($hash);

  foreach my $readEntry (keys %{$chnhash->{READINGS}}){
	  delete $chnhash->{READINGS}{$readEntry} if ($readEntry =~ m/^[\.]?RegL_/);
  }
  #get Peer-list in any case - it is part of config
  CUL_HM_PushCmdStack($hash,sprintf("++%s01%s%s%s03",$flag,$id,$dst,$chn));
  my $lstAr = $culHmModel{CUL_HM_getMId($hash)}{lst};
  my @list = split(",",$lstAr); #get valid lists e.g."1, 5:2:3.p ,6:2"
  foreach my$listEntry (@list){# each list that is define for this channel
    my ($peerReq,$chnValid)= (0,0);
    my ($listNo,$chnLst1) = split(":",$listEntry); 
	if (!$chnLst1){
	  $chnValid = 1; #if no entry channel is valid
	  $peerReq = 1 if($listNo==3 ||$listNo==4); #default
	}
	else{
	  my @chnLst = split('\.',$chnLst1);
	  foreach my $lchn (@chnLst){
	    $peerReq = 1 if ($lchn =~ m/p/);
		no warnings;#know that lchan may be followed by a 'p' causing a warning
	    $chnValid = 1 if (int($lchn) == hex($chn));
		use warnings;
	    last if ($chnValid);
      }
	}
	if ($chnValid){# yes, we will go for a list
	  if ($peerReq){# need to get the peers first
        $chnhash->{helper}{getCfgList} = "all";      # peers first
        $chnhash->{helper}{getCfgListNo} = $listNo;
	  }
	  else{
        CUL_HM_PushCmdStack($hash,sprintf("++%s01%s%s%s0400000000%02X",$flag,$id,$dst,$chn,$listNo));
	  }
	}	
  }
 }
###################-------send related --------################
sub CUL_HM_SndCmd($$) {
  my ($hash, $cmd) = @_;
  $hash = CUL_HM_getDeviceHash($hash); 
  my $io = $hash->{IODev};
  return if(!$io);  

  $cmd =~ m/^(..)(.*)$/;
  my ($mn, $cmd2) = ($1, $2);

  if($mn eq "++") {
    $mn = $io->{HM_CMDNR} ? (($io->{HM_CMDNR} +1)&0xff) : 1;
  } 
  elsif($cmd =~ m/^[+-]/){; #continue pure
    IOWrite($hash, "", $cmd);
	return;
  }
  else {
    $mn = hex($mn);
  }
  $io->{HM_CMDNR} = $mn;
  $cmd = sprintf("As%02X%02X%s", length($cmd2)/2+1, $mn, $cmd2);
  IOWrite($hash, "", $cmd);
  CUL_HM_responseSetup($hash,$cmd);	
  $cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6,$7));
}
sub CUL_HM_responseSetup($$) {#store all we need to handle the response
 #setup repeatTimer and cmdStackControll
  my ($hash,$cmd) =  @_;
  my ($msgId, $msgFlag,$msgType,$dst,$p) = ($2,hex($3),$4,$6,$7)
      if ($cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/);
  my ($chn,$subType) = ($1,$2) if($p =~ m/^(..)(..)/); 
  my $rTo = rand(20)/10+4; #default response timeout
  if ($msgType eq "01" && $subType){ 
    if ($subType eq "03"){ #PeerList-------------
  	  #--- remember request params in device level
  	  $hash->{helper}{respWait}{Pending} = "PeerList";
  	  $hash->{helper}{respWait}{PendCmd} = $cmd;
  	  $hash->{helper}{respWait}{forChn} = substr($p,0,2);#channel info we await
      
      # define timeout - holdup cmdStack until response complete or timeout
  	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
	  
  	  #--- remove readings in channel
  	  my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"}; 
  	  $chnhash = $hash if (!$chnhash);
  	  delete $chnhash->{READINGS}{peerList};#empty old list
	  delete $chnhash->{helper}{peerIDsRaw};
	  $attr{$chnhash->{NAME}}{peerIDs} = '';
	  return;
    }
    elsif($subType eq "04"){ #RegisterRead-------
      my ($peer, $list) = ($1,$2) if ($p =~ m/..04(........)(..)/);
	  $peer = ($peer ne "00000000")?CUL_HM_peerChName($peer,$dst,""):"";
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending}= "RegisterRead";
   	  $hash->{helper}{respWait}{PendCmd}= $cmd;
	  $hash->{helper}{respWait}{forChn} = $chn;
	  $hash->{helper}{respWait}{forList}= $list;
	  $hash->{helper}{respWait}{forPeer}= $peer;
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+$rTo,"CUL_HM_respPendTout","respPend:$dst", 0);
	  #--- remove channel entries that will be replaced
      my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
      $chnhash = $hash if(!$chnhash);   

	  $peer ="" if($list !~ m/^0[34]$/);
	  #empty val since reading will be cumulative 
	  my $rlName = ((CUL_HM_getExpertMode($hash) eq "2")?"":".")."RegL_".$list.":".$peer;
      $chnhash->{READINGS}{$rlName}{VAL}=""; 
      delete ($chnhash->{READINGS}{$rlName}{TIME}); 
	  return;
    }
#    elsif($subType eq "0A"){ #Pair Serial----------
#	  #--- set messaging items
#	  $hash->{helper}{respWait}{Pending} = "PairSerial";
#  	  $hash->{helper}{respWait}{PendCmd} = $cmd;
#	  $hash->{helper}{respWait}{forChn} = substr($p,4,20);
#      
#      # define timeout - holdup cmdStack until response complete or timeout
#	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
#	  return;
#    }
    elsif($subType eq "0E"){ #StatusReq----------
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending}= "StatusReq";
  	  $hash->{helper}{respWait}{PendCmd}= $cmd;
	  $hash->{helper}{respWait}{forChn} = $chn;
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
	  return;
    }
  }
  
  if (($msgFlag & 0x20) && ($dst ne '000000')){
    $hash->{helper}{respWait}{cmd}    = $cmd;
    $hash->{helper}{respWait}{msgId}  = $msgId; #msgId we wait to ack
    $hash->{helper}{respWait}{reSent} = 1;
    
    my $off = 2;
    InternalTimer(gettimeofday()+$off, "CUL_HM_Resend", $hash, 0);
  }
}
sub CUL_HM_eventP($$) {#handle protocol events
  #todo: add severity, counter, history and acknowledge
  my ($hash, $evntType) = @_;
  my $name = $hash->{NAME};
  my $nAttr = $hash;
  return if (!$name);
  if ($evntType eq "Rcv"){
    $nAttr->{"protLastRcv"} = TimeNow();
	return;
  }
  
  my $evnt = $nAttr->{"prot".$evntType}?$nAttr->{"prot".$evntType}:"0 > x";
  my ($evntCnt,undef) = split(' last_at:',$evnt);
  $nAttr->{"prot".$evntType} = ++$evntCnt." last_at:".TimeNow();
  
  if ($evntType ne "Snd"){#count unusual events
    if ($hash->{helper}{burstEvtCnt}){
	       $hash->{helper}{burstEvtCnt}++;
	}else {$hash->{helper}{burstEvtCnt}=1;};
  }
  if ($evntType eq "Nack" ||$evntType eq "ResndFail"){
    my $delMsgSum;
    $nAttr->{protCmdDel} = 0 if(!$nAttr->{protCmdDel});
    $nAttr->{protCmdDel} += scalar @{$hash->{cmdStack}} if ($hash->{cmdStack});
	my $burstEvt = ($hash->{helper}{burstEvtCnt})? 
	                $hash->{helper}{burstEvtCnt}:0;
    $hash->{protState} = "CMDs_done".
	      (($burstEvt)?("_events:".$burstEvt):"");
  }
}
sub CUL_HM_respPendRm($) {#del response related entries in messageing entity
  my ($hash) =  @_;  
  delete ($hash->{helper}{respWait});
  RemoveInternalTimer($hash);          # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer
  $respRemoved = 1;
}
sub CUL_HM_respPendTout($) {
  my ($HMid) =  @_;  
  $HMid =~ s/.*://; #remove timer identifier
  my $hash = $modules{CUL_HM}{defptr}{$HMid};
  if ($hash && $hash->{DEF} ne '000000'){
	my $pendCmd = $hash->{helper}{respWait}{Pending};# secure before remove

    my $pendRsndCnt = $hash->{helper}{respWait}{PendingRsend};
	$pendRsndCnt = 1 if (!$pendRsndCnt);
	if ($pendRsndCnt <7 &&                     # some retries
	    (CUL_HM_getRxType($hash) & 0x03) != 0){# to slow for wakeup and config
      my $name = $hash->{NAME};
      Log GetLogLevel($name,4),"CUL_HM_Resend: ".$name. " nr ".$pendRsndCnt;
	  $hash->{helper}{respWait}{PendingRsend} = $pendRsndCnt + 1;
      CUL_HM_SndCmd($hash,substr($hash->{helper}{respWait}{PendCmd},4));
	  CUL_HM_eventP($hash,"Resnd") if ($pendCmd);
	}
	else{
      CUL_HM_eventP($hash,"ResndFail") if ($pendCmd);
	  CUL_HM_respPendRm($hash);
	  CUL_HM_ProcessCmdStack($hash); # continue processing commands
	  readingsSingleUpdate($hash,"state","RESPONSE TIMEOUT:".$pendCmd,1);
	}
  }
}
sub CUL_HM_respPendToutProlong($) {#used when device sends part responses
  my ($hash) =  @_;  
  RemoveInternalTimer("respPend:$hash->{DEF}");
  InternalTimer(gettimeofday()+1, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}
sub CUL_HM_PushCmdStack($$) {
  my ($chnhash, $cmd) = @_;
  my @arr = ();
  my $hash = CUL_HM_getDeviceHash($chnhash);
  my $name = $hash->{NAME};
  if(!$hash->{cmdStack}){
    $hash->{cmdStack} = \@arr;
	delete ($hash->{helper}{burstEvtCnt}) if (!$hash->{helper}{respWait});
  }
  push(@{$hash->{cmdStack}}, $cmd);
  my $entries = scalar @{$hash->{cmdStack}};
  $hash->{protCmdPend} = $entries." CMDs_pending";
  $hash->{protState} = "CMDs_pending"             
        if (!$hash->{helper}{respWait}{cmd} && 
            !$hash->{helper}{respWait}{Pending});
}
sub CUL_HM_ProcessCmdStack($) {
  my ($chnhash) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);
  my $name = $hash->{NAME};
  my $sent;
  if($hash->{cmdStack} && !$hash->{helper}{respWait}{cmd} && 
                          !$hash->{helper}{respWait}{Pending}){
    if(@{$hash->{cmdStack}}) {
      CUL_HM_SndCmd($hash, shift @{$hash->{cmdStack}});
      $sent = 1;
      $hash->{protCmdPend} = scalar @{$hash->{cmdStack}}." CMDs pending";
      $hash->{protState} = "CMDs_processing...";                         
	  CUL_HM_eventP($hash,"Snd");	  
    }
    if(!@{$hash->{cmdStack}}) {
      delete($hash->{cmdStack});
      delete($hash->{protCmdPend}); 
	  #-- update info ---
	  my $burstEvt = ($hash->{helper}{burstEvtCnt})? 
	                  $hash->{helper}{burstEvtCnt}:0;
      $hash->{protState} = "CMDs_done".
	      (($burstEvt)?("_events:".$burstEvt):"");
    }
  }
  return $sent;
}
sub CUL_HM_Resend($) {#resend a message if there is no answer
  my $hash = shift;
  my $name = $hash->{NAME};
  return if(!$hash->{helper}{respWait}{reSent});      # Double timer?
  if($hash->{helper}{respWait}{reSent} >= 3) {
  	CUL_HM_eventP($hash,"ResndFail");
    delete($hash->{cmdStack});
    delete($hash->{protCmdPend});
	CUL_HM_respPendRm($hash);
	my $burstEvt = ($hash->{helper}{burstEvtCnt})? 
	                $hash->{helper}{burstEvtCnt}:0;
	$hash->{protState} = "CMDs_done".
	                          (($burstEvt)?("_events:".$burstEvt):"");
	readingsSingleUpdate($hash,"state","MISSING ACK",1);
  }
  else {
  	CUL_HM_eventP($hash,"Resnd");
    IOWrite($hash, "", $hash->{helper}{respWait}{cmd});
    $hash->{helper}{respWait}{reSent}++;
    Log GetLogLevel($name,4),"CUL_HM_Resend: ".$name. " nr ".$hash->{helper}{respWait}{reSent};
    InternalTimer(gettimeofday()+rand(40)/10+1, "CUL_HM_Resend", $hash, 0);
  }
}
###################-----------helper and shortcuts--------################
################### Peer Handling ################
sub CUL_HM_ID2PeerList ($$$) {
  my($name,$peerID,$set) = @_;
  my $peerIDs = AttrVal($name,"peerIDs",""); 
  my $hash = CUL_HM_name2Hash($name);
  $peerIDs =~ s/$peerID//g;         #avoid duplicate, support unset
  $peerID =~ s/^000000../00000000/;  #correct end detector
  $peerIDs.= $peerID."," if($set);

  my %tmpHash = map { $_ => 1 } split(",",$peerIDs);#remove duplicates
  $peerIDs = "";                                    #clear list
  my $peerNames = "";                               #prepare names
  my $dId = substr(CUL_HM_name2Id($name),0,6);      #get own device ID
  foreach my $pId (sort(keys %tmpHash)){
    next if ($pId !~ m/^[0-9A-F]{8}$/);             #ignore non-channel IDs
	$peerIDs .= $pId.",";                           #append ID
    next if ($pId eq "00000000");                   # and end detection
	$peerNames .= (($dId eq substr($pId,0,6))?      #is own channel?
	                  ("self".substr($pId,6,2)):    #yes, name it 'self'
	                  (CUL_HM_id2Name($pId)))       #find name otherwise
				  .",";                             # dont forget separator
  }
  $attr{$name}{peerIDs} = $peerIDs;                 # make it public
  if ($peerNames){
    readingsSingleUpdate($hash,"peerList",$peerNames,0) ;
  }
  else{ 
    delete $hash->{READINGS}{peerList};
  }
}
###################  Conversions  ################
sub CUL_HM_getExpertMode($) { # get expert level for the entity. 
  # if expert level is not set try to get it for device
  my ($hash) = @_;
  my $expLvl = AttrVal($hash->{NAME},"expert","");
  my $dHash = CUL_HM_getDeviceHash($hash);
  $expLvl = AttrVal($dHash->{NAME},"expert","0") 
        if ($expLvl eq "");
  return substr($expLvl,0,1);
}
sub CUL_HM_getAssChnIds($) { #in: name out:ID list of assotiated channels
  # if it is a channel only return itself
  # if device and no channel 
  my ($name) = @_;
  my @chnIdList;
  my $hash = CUL_HM_name2Hash($name);
  foreach my $channel (grep {$_ =~m/^channel_/} keys %{$hash}){
	my $chnHash = CUL_HM_name2Hash($hash->{$channel});
	push @chnIdList,$chnHash->{DEF} if ($chnHash);
  }
  my $dId = CUL_HM_name2Id($name);

  push @chnIdList,$dId."01" if (length($dId) == 6 && !$hash->{channel_01});
  push @chnIdList,$dId if (length($dId) == 8);
  return sort(@chnIdList);
}
sub CUL_HM_Id($) {#in: ioHash out: ioHMid 
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME}, "hmId", "F1$fhtid");
}
sub CUL_HM_IOid($) {#in: hash out: id of IO device  
  my ($hash) = @_;
  my $dHash = CUL_HM_getDeviceHash($hash);
  my $ioHash = $dHash->{IODev};
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return AttrVal($ioHash->{NAME}, "hmId", "F1$fhtid");
}
sub CUL_HM_hash2Id($) {#in: id, out:hash
  my ($hash) = @_;
  return $hash->{DEF};
}
sub CUL_HM_hash2Name($) {#in: id, out:name
  my ($hash) = @_;
  return $hash->{NAME};
}
sub CUL_HM_name2Hash($) {#in: name, out:hash
  my ($name) = @_;
  return $defs{$name};
}
sub CUL_HM_name2Id(@) { #in: name or HMid ==>out: HMid, "" if no match
  my ($name,$idHash) = @_;
  my $hash = $defs{$name};
  return $hash->{DEF}        if ($hash);                      #name is entity
  return "000000"            if($name eq "broadcast");        #broadcast
  return $defs{$1}->{DEF}.$2 if($name =~ m/(.*)_chn:(..)/);   #<devname> chn:xx
  return $name               if($name =~ m/^[A-F0-9]{6,8}$/i);#was already HMid
  return $idHash->{DEF}.sprintf("%02X",$1) 
                             if($idHash && ($name =~ m/self(.*)/));
  return "";
}
sub CUL_HM_id2Name($) { #in: name or HMid out: name
  my ($p) = @_;
  return $p                      if($attr{$p}); # is already name
  return $p                      if ($p =~ m/_chn:/);
  my $devId= substr($p, 0, 6);
  return "broadcast"             if($devId eq "000000"); 
  my ($chn,$chnId);
  if (length($p) == 8){
	$chn = substr($p, 6, 2);;
	$chnId = $p;
  }
  my $defPtr = $modules{CUL_HM}{defptr};
  return $defPtr->{$chnId}{NAME} if( $chnId && $defPtr->{$chnId});#channel 
  return $defPtr->{$devId}{NAME} if(!$chnId && $defPtr->{$devId});#device only

  return $defPtr->{$devId}{NAME}."_chn:".$chn 
                                 if( $chnId && $defPtr->{$devId});#device, add chn
  return $devId. ($chn ? ("_chn:".$chn):"");                      #not defined, return ID only
}
sub CUL_HM_id2Hash($) {#in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if ($modules{CUL_HM}{defptr}{$id});
  return $modules{CUL_HM}{defptr}{substr($id,0,6)}; # could be chn 01 of dev
}
sub CUL_HM_peerChId($$$) {# peer Channel name from/for user entry. <IDorName> <deviceID> <ioID>
  my($pId,$dId,$iId)=@_;
  my $pSc = substr($pId,0,4); #helper for shortcut spread
  return $dId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'self');
  return $iId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'fhem');
  return "all"                                   if ($pId eq 'all');#used by getRegList
  my $repID = CUL_HM_name2Id($pId);
  $repID .= '01' if (length( $repID) == 6);# add default 01 if this is a device
  return $repID;                  
}
sub CUL_HM_peerChName($$$) {# peer Channel ID to user entry. <peerChId> <deviceID> <ioID>
  my($pId,$dId,$iId)=@_;
  my($pDev,$pChn) = ($1,$2) if ($pId =~ m/(......)(..)/);
  return 'self'.$pChn if ($pDev eq $dId);
  return 'fhem'.$pChn if ($pDev eq $iId);
  return CUL_HM_id2Name($pId);                
}
sub CUL_HM_getDeviceHash($) {#in: hash (chn or dev) out: hash of the device (used e.g. for send messages)
  my ($hash) = @_;
  return $hash if(!$hash->{DEF});
  my $devHash = $modules{CUL_HM}{defptr}{substr($hash->{DEF},0,6)};
  return ($devHash)?$devHash:$hash;
}


#############################
my %culHmBits = (
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
  "01;p11=08"   => { txt => "CONFIG_WRITE_INDEX", params => {
                     CHANNEL => "0,2",
                     DATA => '4,,$val =~ s/(..)(..)/ $1:$2/g', } },
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
  "02;p01=04"   => { txt => "ACK-proc",  params => {
                     Para1          => "02,4",
                     Para2          => "06,4",
                     Para3          => "10,4",
                     Para4          => "14,2",}}, # remote?
  "02;p01=80"   => { txt => "NACK"},
  "02;p01=84"   => { txt => "NACK_TARGET_INVALID"},
  "02"          => { txt => "ACK/NACK_UNKNOWN   "},
  
  "02"          => { txt => "Request AES", params => {  #todo check data
                     DATA =>  "0," } },

  "03"          => { txt => "AES reply",   params => {
                     DATA =>  "0," } },
					 
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
  "11;p02=0400" => { txt => "RESET" },
  "11;p01=02"   => { txt => "SET" , params => {
                     CHANNEL  => "02,2", 
                     VALUE    => "04,2", 
                     RAMPTIME => '06,4,$val=CUL_HM_decodeTime16($val)', 
                     DURATION => '10,4,$val=CUL_HM_decodeTime16($val)', } }, 
  "11;p01=80"   => { txt => "LED" , params => {
                     CHANNEL  => "02,2", 
                     COLOR    => "04,2", } }, 
  "11;p01=81"   => { txt => "LEDall" , params => {
                     Led1To16 => '04,8,$val= join(":",sprintf("%b",hex($val))=~ /(.{2})/g)',
					 } }, 
  "12"          => { txt => "HAVE_DATA"},
  "3E"          => { txt => "SWITCH", params => {
                     DST      => "00,6", 
                     UNKNOWN  => "06,2", 
                     CHANNEL  => "08,2", 
                     COUNTER  => "10,2", } },
  "3F"          => { txt => "TimeStamp", params => {
                     UNKNOWN  => "00,4", 
                     TIME     => "04,2", } },
  "40"          => { txt => "REMOTE", params => {
                     BUTTON   => '00,2,$val=(hex($val)&0x3F)',
                     LONG     => '00,2,$val=(hex($val)&0x40)?1:0',
                     LOWBAT   => '00,2,$val=(hex($val)&0x80)?1:0',
                     COUNTER  => "02,2", } },
  "41"          => { txt => "Sensor_event", params => {
                     BUTTON   => '00,2,$val=(hex($val)&0x3F)',
                     LONG     => '00,2,$val=(hex($val)&0x40)?1:0',
                     LOWBAT   => '00,2,$val=(hex($val)&0x80)?1:0',
                     VALUE    => '02,2,$val=(hex($val))',
                     NEXT     => '04,2,$val=(hex($val))',} },
  "53"          => { txt => "WaterSensor", params => {
                     CMD      => "00,2",
                     SEQ => '02,2,$val=(hex($val))-64', 
                     V1  => '08,2,$val=(hex($val))', 
                     V2  => '10,2,$val=(hex($val))', 
                     V3  => '12,2,$val=(hex($val))'} },
  "58"          => { txt => "ClimateEvent", params => {
                     CMD      => "00,2",
                     ValvePos => '02,2,$val=(hex($val))', } },
  "70"          => { txt => "WeatherEvent", params => {
                     TEMP     => '00,4,$val=((hex($val)&0x3FFF)/10)*((hex($val)&0x4000)?-1:1)',
                     HUM      => '04,2,$val=(hex($val))', } },

);
# RC send BCAST to specific address. Is the meaning understood?
my @culHmCmdFlags = ("WAKEUP", "WAKEMEUP", "CFG", "Bit3",
                     "BURST", "BIDI", "RPTED", "RPTEN");
					 #RPTEN    0x80: set in every message. Meaning?
					 #RPTED    0x40: repeated (repeater operation)
                     #BIDI     0x20: response is expected
					 #Burst    0x10: set if burst is required by device
					 #Bit3     0x08:
					 #CFG      0x04: Device in Config mode 
					 #WAKEMEUP 0x02: awake - hurry up to send messages
					 #WAKEUP   0x01: send initially to keep the device awake
sub CUL_HM_DumpProtocol($$@) {
  my ($prefix, $iohash, $len,$cnt,$msgFlags,$msgType,$src,$dst,$p) = @_;
  my $iname = $iohash->{NAME};
  no warnings;# conv 2 number would cause a warning - which is ok
  my $hmProtocolEvents = int(AttrVal($iname, "hmProtocolEvents", 0));
  use warnings;
  return if(!$hmProtocolEvents);

  my $p01 = substr($p,0,2);
  my $p02 = substr($p,0,4);
  my $p11 = (length($p) > 2 ? substr($p,2,2) : "");

  # decode message flags for printing
  my $msgFlLong="";
  my $msgFlagsHex = hex($msgFlags);
  for(my $i = 0; $i < @culHmCmdFlags; $i++) {
    $msgFlLong .= ",$culHmCmdFlags[$i]" if($msgFlagsHex & (1<<$i));
  }

  my $ps;
  $ps = $culHmBits{"$msgType;p11=$p11"} if(!$ps);
  $ps = $culHmBits{"$msgType;p01=$p01"} if(!$ps);
  $ps = $culHmBits{"$msgType;p02=$p02"} if(!$ps);
  $ps = $culHmBits{"$msgType"}          if(!$ps);
  my $txt = "";
  if($ps) {
    $txt = $ps->{txt};
    if($ps->{params}) {
      $ps = $ps->{params};
      foreach my $k (sort {$ps->{$a} cmp $ps->{$b} } keys %{$ps}) {
        my ($o,$l,$expr) = split(",", $ps->{$k}, 3);
        last if(length($p) <= $o);
        my $val = $l ? substr($p,$o,$l) : substr($p,$o);
        eval $expr if($hmProtocolEvents > 1 && $expr);
        $txt .= " $k:".(($hmProtocolEvents > 1 && $expr)?"":"0x")."$val";
      }
    }
    $txt = " ($txt)" if($txt);
  }
  $src=CUL_HM_id2Name($src);
  $dst=CUL_HM_id2Name($dst);
  my $msg ="$prefix L:$len N:$cnt F:$msgFlags CMD:$msgType SRC:$src DST:$dst $p$txt ($msgFlLong)";
  Log GetLogLevel($iname, 4), $msg;
  DoTrigger($iname, $msg) if($hmProtocolEvents > 2);
}
sub CUL_HM_parseCommon(@){#############################
  # parsing commands that are device independant
  my ($msgId,$msgFlag,$msgType,$src,$dst,$p) = @_;
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  return "" if(!$shash->{DEF});# this should be from ourself 
  
  my $pendType = $shash->{helper}{respWait}{Pending}? 
                           $shash->{helper}{respWait}{Pending}:"";
  #------------ parse message flag for start processing command Stack
  # TC wakes up with 8270, not with A258
  # VD wakes up with 8202 
  if(  $shash->{cmdStack}              && 
      ((hex($msgFlag) & 0xA2) == 0x82) && 
	  (CUL_HM_getRxType($shash) & 0x08)){ #wakeup #####
	#send wakeup and process command stack
  	CUL_HM_SndCmd($shash, '++A112'.CUL_HM_IOid($shash).$src);
	CUL_HM_ProcessCmdStack($shash);
  }
  
  if ($msgType eq "02"){# Ack/Nack #######################################
	if ($shash->{helper}{respWait}{msgId}             && 
	    $shash->{helper}{respWait}{msgId} eq $msgId ){
	  #ack we waited for - stop Waiting
	  CUL_HM_respPendRm($shash);
	}
	if ($pendType eq "StatusReq"){#possible answer for status request
	  my $chnSrc = $src.$shash->{helper}{respWait}{forChn};
	  my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc}; 
	  $chnhash = $shash if (!$chnhash);
	  CUL_HM_respPendRm($shash);
	} 

	#see if the channel is defined separate - otherwise go for chief
    my $subType = substr($p,0,2);
    my $chn = substr($p,2,2);
    #mark timing on the channel, not the device
	my $HMid = $chn?$src.$chn:$src;
    my $chnhash = $modules{CUL_HM}{defptr}{$HMid};
    $chnhash = $shash if(!$chnhash);
   
	my $reply;
	my $success;

	if ($subType =~ m/^8/){	  #NACK
	  $success = "no";
	  CUL_HM_eventP($shash,"Nack");
      delete($shash->{cmdStack});
	  delete($shash->{protCmdPend});
	  CUL_HM_respPendRm($shash);
	  $reply = "NACK"; 
	}
	elsif($subType eq "01"){ #ACKinfo#################
      
	  my $rssi = substr($p,8,2);# --calculate RSSI
      CUL_HM_storeRssi(CUL_HM_hash2Name($shash),
                        ($dhash?CUL_HM_hash2Name($dhash):$shash->{IODev}{NAME}),
						(-1)*(hex($rssi)))
			if ($rssi && $rssi ne '00' && $rssi ne'80');
	  $reply = "ACKStatus"; 
	}
	else{	  #ACK
	  $reply = "ACK"; 
	  $success = "yes";
	}
	readingsSingleUpdate($chnhash,"CommandAccepted",$success,1);
    CUL_HM_ProcessCmdStack($shash) 
	      if($dhash->{DEF} && (CUL_HM_IOid($shash) eq $dhash->{DEF}));
	return $reply;
  }
  elsif($msgType eq "00"){
    if ($pendType eq "PairSerial"){
	  if($shash->{helper}{respWait}{forChn} = substr($p,6,20)){
	    CUL_HM_respPendRm($shash);
	  }
	} 
  }
  elsif($msgType eq "10"){
    my $subType = substr($p,0,2);
	if($subType eq "01"){ #storePeerList#################
	  if ($pendType eq "PeerList"){
		my $chn = $shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$src.$chn}; 
		$chnhash = $shash if (!$chnhash);
	    my $chnNname = $chnhash->{NAME};
		my @peers = substr($p,2,) =~ /(.{8})/g;
	    $chnhash->{helper}{peerIDsRaw}.= ",".join",",@peers;
		
		foreach my $peer(@peers){	
    	  CUL_HM_ID2PeerList ($chnNname,$peer,1);
		}
		if ($p =~ m/000000..$/) {# last entry, peerList is complete
          CUL_HM_respPendRm($shash);		  
		  # check for request to get List3 data
		  my $reqPeer = $chnhash->{helper}{getCfgList};
		  if ($reqPeer){
		    my $flag = CUL_HM_getFlag($shash);
		    my $id = CUL_HM_IOid($shash);
		    my $listNo = "0".$chnhash->{helper}{getCfgListNo};
		    my @peerID = split(",", AttrVal($chnNname,"peerIDs",""));
		    foreach my $peer (@peerID){
			  next if ($peer eq '00000000');# ignore termination 
			  $peer .="01" if (length($peer) == 6); # add the default
			  if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
				CUL_HM_PushCmdStack($shash,sprintf("++%s01%s%s%s04%s%s",
						$flag,$id,$src,$chn,$peer,$listNo));# List3 or 4 
			  }
			}
		  }
		  delete $chnhash->{helper}{getCfgList};
		  delete $chnhash->{helper}{getCfgListNo};
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		return "done";
	  }
	}
	elsif($subType eq "02" ||$subType eq "03"){ #ParamResp==================
	  if ($pendType eq "RegisterRead"){
		my $chnSrc = $src.$shash->{helper}{respWait}{forChn};
		my $chnHash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnHash = $shash if (!$chnHash);
		my $chnName = $chnHash->{NAME};
		my ($format,$data) = ($1,$2) if ($p =~ m/^(..)(.*)/);
		my $list = $shash->{helper}{respWait}{forList};
		$list = "00" if (!$list); #use the default
		if ($format eq "02"){ # list 2: format aa:dd aa:dd ...
		  $data =~ s/(..)(..)/ $1:$2/g;
		}
		elsif ($format eq "03"){ # list 3: format aa:dddd
		  my $addr;
		  my @dataList;
		  ($addr,$data) = (hex($1),$2) if ($data =~ m/(..)(.*)/);
		  if ($addr == 0){
		   $data = "00:00";
		  }
		  else{
		    $data =~s/(..)/$1:/g;
		    foreach my $d1 (split(":",$data)){
			  push (@dataList,sprintf("%02X:%s",$addr++,$d1));
		    }
		    $data = join(" ",@dataList);		
		  }
		}
		my $peer = $shash->{helper}{respWait}{forPeer};
		my $regLN = ((CUL_HM_getExpertMode($chnHash) eq "2")?"":".")."RegL_".$list.":".$peer;
		readingsSingleUpdate($chnHash,$regLN,
		             ReadingsVal($chnName,$regLN,"")." ".$data,0);
		if ($data =~m/00:00$/){ # this was the last message in the block
		  if($list eq "00"){
			my $name = CUL_HM_id2Name($src);
			readingsSingleUpdate($shash,"PairedTo",
		                    CUL_HM_getRegFromStore($name,"pairCentral",0,"00000000"),0);
		  }		  
		  CUL_HM_respPendRm($shash);
		  delete $chnHash->{helper}{shadowReg}{$regLN};#remove shadowhash
		  # peer Channel name from/for user entry. <IDorName> <deviceID> <ioID>
		  CUL_HM_updtRegDisp($chnHash,$list,
		        CUL_HM_peerChId($peer,
						substr(CUL_HM_hash2Id($chnHash),0,6),"00000000"));
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		return "done";
	  }
	}  
	elsif($subType eq "04"){ #ParamChange===================================
	  my($chn,$peerID,$list,$data) = ($1,$2,$3,$4) if($p =~ m/^04(..)(........)(..)(.*)/);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  $chnHash = $shash if(!$chnHash); # will add param to dev if no chan
	  my $regLN = ((CUL_HM_getExpertMode($chnHash) eq "2")?"":".")."RegL_".$list.":".CUL_HM_id2Name($peerID);
      $regLN =~ s/broadcast//;
	  $regLN =~ s/ /_/g; #remove blanks

	  $data =~ s/(..)(..)/ $1:$2/g;	  
	  
	  my $lN = ReadingsVal($chnHash->{NAME},$regLN,"");
	  my $shdwReg = $chnHash->{helper}{shadowReg}{$regLN};
	  foreach my $entry(split(' ',$data)){
	    my ($a,$d) = split(":",$entry);	
        last if ($a eq "00");		
		if ($lN =~m/$a:/){$lN =~ s/$a:../$a:$d/;
		}else{  		  $lN .= " ".$entry;}
		$shdwReg =~ s/ $a:..// if ($shdwReg);# confirmed: remove from shadow
	  }
	  $chnHash->{helper}{shadowReg}{$regLN} = $shdwReg;
	  $lN = join(' ',sort(split(' ',$lN)));# re-order
	  if ($lN =~ s/00:00//){$lN .= " 00:00"};
      readingsSingleUpdate($chnHash,$regLN,$lN,0);
	  CUL_HM_updtRegDisp($chnHash,$list,$peerID);
	}  
	elsif($subType eq "06"){ #reply to status request=======================
	  my $rssi = substr($p,8,2);# --calculate RSSI
      CUL_HM_storeRssi(CUL_HM_hash2Name($shash),
                        ($dhash?CUL_HM_hash2Name($dhash):$shash->{IODev}{NAME}),
						(-1)*(hex($rssi)))
			if ($rssi && $rssi ne '00' && $rssi ne'80');
	  #todo = what is the answer to a status request
	  if ($pendType eq "StatusReq"){#it is the answer to our request
		my $chnSrc = $src.$shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnhash = $shash if (!$chnhash);
		CUL_HM_respPendRm($shash);
		return "STATresp";
	  }
	  else{
		my ($chn) = ($1) if($p =~ m/^..(..)/);
		return "powerOn" if ($chn eq "00");# check dst eq "000000" as well?
	  }
	}
  }
  elsif($msgType eq "70"){ #Time to trigger TC##################
    #send wakeup and process command stack
#  	CUL_HM_SndCmd($shash, '++A112'.CUL_HM_IOid($shash).$src);
#	CUL_HM_ProcessCmdStack($shash);
  }
  return "";
}
#############################
sub CUL_HM_getRegFromStore($$$$) {#read a register from backup data
  my($name,$regName,$list,$peerId)=@_;
  my $hash = CUL_HM_name2Hash($name);
  my ($size,$pos,$conversion,$factor,$unit) = (8,0,"",1,""); # default
  my $addr = $regName;
  my $dId = substr(CUL_HM_name2Id($name),0,6);#id of device
  my $iId = CUL_HM_IOid($hash);       #id of IO device
  my $reg  = $culHmRegDefine{$regName};
  if ($reg) { # get the register's information
    $addr = $reg->{a};
	$pos = ($addr*10)%10;
	$addr = int($addr);
    $list = $reg->{l};
	$size = $reg->{s};
	$size = int($size)*8 + ($size*10)%10;
	$conversion = $reg->{c}; #unconvert formula
	$factor = $reg->{f};
	$unit = $reg->{u};
  }
  else{
	;# use address instead of 
  }
  $peerId  = CUL_HM_peerChId(($peerId?$peerId:"00000000"),$dId,$iId);
							    
  my $regLN = ((CUL_HM_getExpertMode($hash) eq "2")?"":".").
              "RegL_".sprintf("%02X",$list).":".CUL_HM_peerChName($peerId,$dId,$iId);
  $regLN =~ s/broadcast//;
  
  my $data=0;
  my $convFlg = "";# confirmation flag - indicates data not confirmed by device
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
    
	my $dReadS;
    if ($hash->{helper}{shadowReg}&&$hash->{helper}{shadowReg}{$regLN}){
      $dReadS = $1 if($hash->{helper}{shadowReg}{$regLN} =~ m/$addrS:(..)/);
    }
	my $dReadR = " ";
    if ($hash->{READINGS}{$regLN}) {
      $dReadR = $1 if($hash->{READINGS}{$regLN}{VAL} =~ m/$addrS:(..)/);
    }
	$convFlg = "set_" if ($dReadS && $dReadR ne $dReadS);
    my $dRead = $dReadS?$dReadS:$dReadR;
	return "invalid" if (!defined($dRead) || $dRead eq ""|| $dRead eq " ");
    
	$data = ($data<< 8)+hex($dRead);
	$addr++;
  }

   $data = ($data>>$pos) & (0xffffffff>>(32-$size));
   if (!$conversion){                ;# do nothing
   } elsif($conversion eq "factor"){ $data /= $factor;
   } elsif($conversion eq "fltCvT"){ $data = CUL_HM_CvTflt($data);
   } elsif($conversion eq "m10s3") { $data = ($data+3)/10;
   } elsif($conversion eq "hex"  ) { $data = sprintf("0x%X",$data);
   } elsif(defined($reg->{lit}))   { 
	 foreach (keys%{$reg->{lit}}){ 
	   if ($data == $reg->{lit}{$_}){ $data = $_; last; }
	 }   
   } else { return " conversion undefined - please contact admin";
   } 
   return $convFlg.$data.' '.$unit;

}
sub CUL_HM_updtRegDisp($$$) {
  my $starttime = gettimeofday();
  my($hash,$list,$peerId)=@_;
  my $listNo = $list+0;
  my $name = $hash->{NAME};
  my $peer = ($peerId && $peerId ne '00000000' )?
     CUL_HM_peerChName($peerId,substr($hash->{DEF},0,6),"")."-":"";
  $peer=~s/:/-/;
  my $devName =CUL_HM_getDeviceHash($hash)->{NAME};# devName as protocol entity
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");
  my $chn = $hash->{DEF};
  $chn = (length($chn) == 8)?substr($chn,6,2):"";
  my @regArr = keys %culHmRegGeneral;
  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st}); 
  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md}); 
  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn}); 
  my @changedRead;
  my $expLvl = (CUL_HM_getExpertMode($hash) ne  "0")?1:0;
  foreach my $regName (@regArr){
    next if ($culHmRegDefine{$regName}->{l} ne $listNo);
    my $rgVal = CUL_HM_getRegFromStore($name,$regName,$list,$peerId);
	next if (!$rgVal || $rgVal eq "invalid");
	my $readName = "R-".$peer.$regName;
	$readName = ($culHmRegDefine{$regName}->{d}?"":".").$readName if (!$expLvl); #expert?
	push (@changedRead,$readName.":".$rgVal)
	      if (ReadingsVal($name,$readName,"") ne $rgVal);
  }

  # ---  handle specifics -  no general approach so far.  
  CUL_HM_TCtempReadings($hash) 
        if (($list == 5 ||$list == 6)     && 
             substr($hash->{DEF},6,2) eq "02" &&
             CUL_HM_Get($hash,$name,"param","model") eq "HM-CC-TC");

  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
}
#############################
my @culHmTimes8 = ( 0.1, 1, 5, 10, 60, 300, 600, 3600 );
sub CUL_HM_encodeTime8($) {
  my $v = shift;
  return "00" if($v < 0.1);
  for(my $i = 0; $i < @culHmTimes8; $i++) {
    if($culHmTimes8[$i] * 32 > $v) {
      for(my $j = 0; $j < 32; $j++) {
        if($j*$culHmTimes8[$i] >= $v) {
          return sprintf("%X", $i*32+$j);
        }
      }
    }
  }
  return "FF";
}
sub CUL_HM_decodeTime8($) {#############################
  my $v = hex(shift);
  return "undef" if($v > 255);
  my $v1 = int($v/32);
  my $v2 = $v%32;
  return $v2 * $culHmTimes8[$v1];
}
sub CUL_HM_encodeTime16($) {#############################
  my $v = shift;
  return "0000" if($v < 0.05);
  
  my $ret = "FFFF";
  my $mul = 10;
  for(my $i = 0; $i < 32; $i++) {
    if($v*$mul < 0x7ff) {
     $ret=sprintf("%04X", ((($v*$mul)<<5)+$i));
     last;
    }
    $mul /= 2;
  }
  my $v2 = CUL_HM_decodeTime16($ret);
  return ($ret);
}
sub CUL_HM_convTemp($) {
  my ($val) = @_;

  if(!($val eq "on" || $val eq "off" ||
      ($val =~ m/^\d*\.?\d+$/ && $val >= 6 && $val <= 30))) {
    my @list = map { ($_.".0", $_+0.5) } (6..30);
    pop @list;
    return "Invalid temperature $val, choose one of on off " . join(" ",@list);
  }
  $val = 100 if($val eq "on");
  $val =   0 if($val eq "off");
  return sprintf("%02X", $val*2);
}
sub CUL_HM_decodeTime16($) {#############################
  my $v = hex(shift);
  my $m = int($v>>5);
  my $e = $v & 0x1f;
  my $mul = 0.1;
  return 2^$e*$m*0.1;
}
#############################
sub CUL_HM_pushConfig($$$$$$$$) {#routine will generate messages to write cnfig data to register
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content) = @_;
  my $flag = CUL_HM_getFlag($hash);
  my $tl = length($content);
  $chn =     sprintf("%02X",$chn);
  $peerChn = sprintf("%02X",$peerChn);
  $list =    sprintf("%02X",$list);

  # --store pending changes in shadow to handle bit manipulations cululativ--
  $peerAddr = "000000" if(!$peerAddr);
  my $peerN = ($peerAddr ne "000000")?CUL_HM_id2Name($peerAddr.$peerChn):"";
  $peerN =~ s/broadcast//;
  $peerN =~ s/ /_/g;#remote blanks
  my $regLN = ((CUL_HM_getExpertMode($hash) eq "2")?"":".").
              "RegL_".$list.":".$peerN;
  #--- copy data from readings to shadow
  my $chnhash = $modules{CUL_HM}{defptr}{$dst.$chn};
  $chnhash = $hash if (!$chnhash);
  if (!$chnhash->{helper}{shadowReg} ||
      !$chnhash->{helper}{shadowReg}{$regLN}){
	$chnhash->{helper}{shadowReg}{$regLN} = 
	           ReadingsVal($chnhash->{NAME},$regLN,"");
  }
  #--- update with ne value
  my $regs = $chnhash->{helper}{shadowReg}{$regLN};
  for(my $l = 0; $l < $tl; $l+=4) { #substitute changed bytes in shadow
    my $addr = substr($content,$l,2);
    my $data = substr($content,$l+2,2);
    if(!$regs || !($regs =~ s/$addr:../$addr:$data/)){
      $regs .= " ".$addr.":".$data;
    }
  }
  $chnhash->{helper}{shadowReg}{$regLN} = $regs;
  CUL_HM_updtRegDisp($hash,$list,$peerAddr.$peerChn);
  CUL_HM_PushCmdStack($hash, "++".$flag.'01'.$src.$dst.$chn.'05'.
                                        $peerAddr.$peerChn.$list);
  for(my $l = 0; $l < $tl; $l+=28) {
    my $ml = $tl-$l < 28 ? $tl-$l : 28;
    CUL_HM_PushCmdStack($hash, "++A001".$src.$dst.$chn."08".
	                                 substr($content,$l,$ml));
  }
  CUL_HM_PushCmdStack($hash,"++A001".$src.$dst.$chn."06");
}
sub CUL_HM_secSince2000() {
  # Calculate the local time in seconds from 2000.
  my $t = time();
  my @l = localtime($t);
  my @g = gmtime($t);
  $t += 60*(($l[2]-$g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24 + $l[8]) * 60 + $l[1]-$g[1]) 
                           # timezone and daylight saving...
        - 946684800        # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
        - 7200;            # HM Special
  return $t;
}
############### Activity supervision section ################
# verify that devices are seen in a certain period of time
# It will generate events if no message is seen sourced by the device during 
# that period.
# ActionDetector will use the fixed HMid 000000
sub CUL_HM_ActGetCreateHash() {# return hash of ActionDetector - create one if not existant
  if (!$modules{CUL_HM}{defptr}{"000000"}){
    DoTrigger("global",  "UNDEFINED ActionDetector CUL_HM 000000");
	$attr{ActionDetector}{actCycle} = 600;
	$attr{ActionDetector}{"event-on-change-reading"} = ".*";
  }
  my $actHash = $modules{CUL_HM}{defptr}{"000000"};
  my $actName = $actHash->{NAME} if($actHash);
  
  if (!$actHash->{helper}{actCycle} ||
      $actHash->{helper}{actCycle} != $attr{$actName}{actCycle}){
	$attr{$actName}{actCycle} = 30 if(!$attr{$actName}{actCycle} ||
	                                   $attr{$actName}{actCycle}<30);
	$actHash->{helper}{actCycle} = $attr{$actName}{actCycle};
	RemoveInternalTimer("ActionDetector");
	$actHash->{STATE} = "active";
	InternalTimer(gettimeofday()+$attr{$actName}{actCycle}, 
									   "CUL_HM_ActCheck", "ActionDetector", 0);
  }
  return $actHash;
}
sub CUL_HM_time2sec($) {
  my ($timeout) = @_;
  my ($h,$m) = split(":",$timeout);
  no warnings;
  $h = int($h);
  $m = int($m);
  use warnings;
  return ((sprintf("%03s:%02d",$h,$m)),((int($h)*60+int($m))*60));
}
sub CUL_HM_ActAdd($$) {# add an HMid to list for activity supervision
  my ($devId,$timeout) = @_; #timeout format [hh]h:mm
  $timeout = 0 if (!$timeout);
  return $devId." is not an HM device - action detection cannot be added"
       if (length($devId) != 6);
  my ($cycleString,undef)=CUL_HM_time2sec($timeout);
  my $devName = CUL_HM_id2Name($devId);
  my $devHash = CUL_HM_name2Hash($devName);
  
  $attr{$devName}{actCycle} = $cycleString; 
  $attr{$devName}{actStatus}=""; # force trigger
  # get last reading timestamp-------
  my $recent = "";
  my @entities = CUL_HM_getAssChnIds($devName);
  for (@entities){$_ = CUL_HM_id2Hash($_)}
  push @entities,$devHash if ($devHash->{channel_01});
  foreach my $ehash (@entities){
    no strict; #convert regardless of content
    next if (!defined $ehash->{NAME});
    use strict;
    my $eName = CUL_HM_hash2Name($ehash);
	next if (!$eName);
    foreach my $rName (keys %{$ehash->{READINGS}}){
      next if (!$rName            ||
	         $rName eq "PairedTo" ||                     # derived
	         $rName eq "peerList" ||                     # derived
	         $rName eq "Activity:"||                     # derived
	         $rName =~ m/^[.]?R-/ ||                     # no Regs - those are derived from Reg
	         ReadingsVal($eName,$rName,"") =~ m/^set_/); # ignore setting
	  my $ts = ReadingsTimestamp($eName,$rName,"");
	  $recent = $ts if ($ts gt $recent);
	}
  }
  my $actHash = CUL_HM_ActGetCreateHash();
  $actHash->{helper}{$devId}{start} = TimeNow();
  $actHash->{helper}{$devId}{recent} = $recent;
  $actHash->{helper}{peers} = CUL_HM_noDupInString(
                       ($actHash->{helper}{peers}?$actHash->{helper}{peers}:"")
                       .",$devId");
  Log 3,"Device ".$devName." added to ActionDetector with "
      .$cycleString." time";
  #run ActionDetector
  RemoveInternalTimer("ActionDetector");
  CUL_HM_ActCheck();
  return;
}
sub CUL_HM_ActDel($) {# delete HMid for activity supervision
  my ($devId) = @_; 
  my $devName = CUL_HM_id2Name($devId);
  CUL_HM_setAttrIfCh($devName,"actStatus","deleted","Activity");#post trigger
  delete $attr{$devName}{actCycle};
  delete $attr{$devName}{actStatus};

  my $actHash = CUL_HM_ActGetCreateHash();
  delete ($actHash->{helper}{$devId});

  my $peerIDs = $actHash->{helper}{peers};
  $peerIDs =~ s/$devId//g if($peerIDs); 
  $actHash->{helper}{peers} = CUL_HM_noDupInString($peerIDs);
  Log 3,"Device ".$devName
                                     ." removed from ActionDetector";
  RemoveInternalTimer("ActionDetector");
  CUL_HM_ActCheck();
  return;
}
sub CUL_HM_ActCheck() {# perform supervision
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $actName = $actHash->{NAME};
  my $peerIDs = $actHash->{helper}{peers}?$actHash->{helper}{peers}:"";
  delete ($actHash->{READINGS}); #cleansweep
  my @event;
  my ($cntUnkn,$cntAlive,$cntDead,$cntOff) =(0,0,0,0);
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
	if(!$devName || !defined($attr{$devName}{actCycle})){
	  CUL_HM_ActDel($devId); 
	  next;
	}
    my $devHash = CUL_HM_name2Hash($devName);
	my $state;
	my $oldState = AttrVal($devName,"actStatus","unset");
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
	if ($tSec == 0){# detection switched off
	  $cntOff++;
	  $state = "switchedOff";
	}
	else{
	  $actHash->{helper}{$devId}{recent} = $devHash->{"protLastRcv"} #update recent
	        if ($devHash->{"protLastRcv"});
	  my $tLast = $actHash->{helper}{$devId}{recent};
      my @t = localtime($tod - $tSec); #time since when a trigger is expected
	  my $tSince = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                             $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
      
	  if (!$tLast){                #cannot determine time
	    if ($actHash->{helper}{$devId}{start} lt $tSince){
		  $state = "dead";	    
		  $cntDead++;
		}
		else{
		  $state = "unknown";	    
		  $cntUnkn++;
		}
	  }
	  elsif ($tSince gt $tLast){    #no message received in window
		$cntDead++;
		$state = "dead";
	  }
	  else{                         #message in time
	    $cntAlive++;
	    $state = "alive";
	  }
	}  
	if ($oldState ne $state){
	  readingsSingleUpdate($devHash,"Activity:",$state,1);
	  $attr{$devName}{actStatus} = $state;
	  Log 4,"Device ".$devName." is ".$state;
	}
    push @event, "status_".$devName.":".$state;
  }
  push @event, "state:"."alive:".$cntAlive
                       ." dead:".$cntDead
                       ." unkn:".$cntUnkn
                       ." off:" .$cntOff;
 
  CUL_HM_UpdtReadBulk($actHash,1,@event);
  
  $attr{$actName}{actCycle} = 600 if($attr{$actName}{actCycle}<30); 
  $actHash->{helper}{actCycle} = $attr{$actName}{actCycle};
  InternalTimer(gettimeofday()+$attr{$actName}{actCycle}, 
  								   "CUL_HM_ActCheck", "ActionDetector", 0);
}
sub CUL_HM_UpdtReadBulk(@) { #update a bunch of readings and trigger the events
  my ($hash,$doTrg,@readings) = @_; 
  return if (!@readings);
  readingsBeginUpdate($hash);
  foreach my $rd (@readings){
    next if (!$rd);
    my ($rdName, $rdVal) = split(":",$rd, 2);
	readingsBulkUpdate($hash,$rdName, 
	                         ((defined($rdVal) && $rdVal ne "")?$rdVal:"-"));
  }
  readingsEndUpdate($hash,$doTrg);
}
sub CUL_HM_setAttrIfCh($$$$) {
  my ($name,$att,$val,$trig) = @_; 
  if($attr{$name}{$att} ne $val){
    DoTrigger($name,$trig.":".$val) if($trig);
	$attr{$name}{$att} = $val;
  }
}
sub CUL_HM_putHash($) {# provide data to HMinfo
  my ($info) = @_;
  return %culHmModel if ($info eq "culHmModel");
}
sub CUL_HM_noDup(@) {#return list with no duplicates
  my %all;
  $all{$_}=0 for @_;
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}
sub CUL_HM_noDupInString($) {#return string with no duplicates, comma separated
  my ($str) = @_;
  return join ",",CUL_HM_noDup(split ",",$str);
}
sub CUL_HM_storeRssi(@){
  my ($name,$peerName,$val) = @_;
  $defs{$name}{helper}{rssi}{$peerName}{lst} = $val;
  $defs{$name}{helper}{rssi}{$peerName}{min} = $val if (!$defs{$name}{helper}{rssi}{$peerName}{min} || $defs{$name}{helper}{rssi}{$peerName}{min} > $val);
  $defs{$name}{helper}{rssi}{$peerName}{max} = $val if (!$defs{$name}{helper}{rssi}{$peerName}{max} || $defs{$name}{helper}{rssi}{$peerName}{max} < $val);
  $defs{$name}{helper}{rssi}{$peerName}{cnt} ++;
  if ($defs{$name}{helper}{rssi}{$peerName}{cnt} == 1){
    $defs{$name}{helper}{rssi}{$peerName}{avg} = $val;
  }
  else{
    $defs{$name}{helper}{rssi}{$peerName}{avg} += ($val - $defs{$name}{helper}{rssi}{$peerName}{avg}) /$defs{$name}{helper}{rssi}{$peerName}{cnt};
  }
  return ;
}

1;

=pod
=begin html

<a name="CUL_HM"></a>
<h3>CUL_HM</h3>
<ul>
  Support for eQ-3 HomeMatic devices via the <a href="#CUL">CUL</a> or the <a
  href="#HMLAN">HMLAN</a>.<br>
  <br>
  <a name="CUL_HMdefine"></a>
  <b>Define</b>
  <ul>
    <code><B>define &lt;name&gt; CUL_HM &lt;6-digit-hex-code|8-digit-hex-code&gt;</B></code>

    <br><br>
    Correct device definition is the key for HM environment simple maintenance.
    <br>

    Background to define entities:<br>
    HM devices has a 3 byte (6 digit hex value) HMid - which is key for
    addressing. Each device hosts one or more channels. HMid for a channel is
    the device's HMid plus the channel number (1 byte, 2 digit) in hex.
    Channels should be defined for all multi-channel devices. Channel entities
    cannot be defined if the hosting device does not exist<br> Note: FHEM
    mappes channel 1 to the device if it is not defined explicitely. Therefore
    it does not need to be defined for single channel devices.<br>

    Note: if a device is deleted all assotiated channels will be removed as
    well. <br> An example for a full definition of a 2 channel switch is given
    below:<br>

	<ul><code>
	define livingRoomSwitch CUL_HM 123456<br>
	define LivingroomMainLight CUL_HM 12345601<br> 
	define LivingroomBackLight CUL_HM 12345602<br><br></code>
        </ul>

    livingRoomSwitch is the device managing communication. This device is
    defined prior to channels to be able to setup references. <br>
    LivingroomMainLight is channel 01 dealing with status of light, channel
    peers and channel assotiated register. If not defined channel 01 is covered
    by the device entity.<br> LivingRoomBackLight is the second 'channel',
    channel 02. Its definition is mandatory to operate this function.<br><br>

    Sender specials: HM threats each button of remotes, push buttons and
    similar as channels. It is possible (not necessary) to define a channel per
    button. If all channels are defined access to pairing informatin is
    possible as well as access to channel related register. Furthermore names
    make the traces better readable.<br><br>

    define may also be invoked by the <a href="#autocreate">autocreate</a>
    module, together with the necessary subType attribute.
    Usually you issue a <a href="#CULset">hmPairForSec</a> and press the
    corresponding button on the device to be paired, or issue a <a
    href="#CULset">hmPairSerial</a> set command if the device is a receiver
    and you know its serial number. Autocreate will then create a fhem
    device and set all necessary attributes. Without pairing the device
    will not accept messages from fhem. fhem may create the device even if
    the pairing is not successful. Upon a successful pairing you'll see a
    CommandAccepted entry in the details section of the CUL_HM device.<br><br>

    If you cannot use autocreate, then you have to specify:<br>
    <ul>
      <li>the &lt;6-digit-hex-code&gt;or HMid+ch &lt;8-digit-hex-code&gt;<br>
          It is the unique, hardcoded device-address and cannot be changed (no,
          you cannot choose it arbitrarily like for FS20 devices). You may
          detect it by inspecting the fhem log.</li>
      <li>the subType attribute<br>
          which is one of switch dimmer blindActuator remote sensor  swi
          pushButton threeStateSensor motionDetector  keyMatic winMatic
          smokeDetector</li>
    </ul>
    Without these attributes fhem won't be able to decode device messages
    appropriately. <br><br>

    <b>Notes</b>
    <ul>
    <li>If the interface is a CUL device, the <a href="#rfmode">rfmode </a>
        attribute of the corresponding CUL/CUN device must be set to HomeMatic.
        Note: this mode is BidCos/Homematic only, you will <b>not</b> receive
        FS20/HMS/EM/S300 messages via this device. Previously defined FS20/HMS
        etc devices must be assigned to a different input device (CUL/FHZ/etc).
        </li>
    <li>Currently supported device families: remote, switch, dimmer,
        blindActuator, motionDetector, smokeDetector, threeStateSensor,
        THSensor, winmatic. Special devices: KS550, HM-CC-TC and the KFM100.
        </li>
    <li>Device messages can only be interpreted correctly if the device type is
        known. fhem will extract the device type from a "pairing request"
        message, even if it won't respond to it (see <a
        href="#hmPairSerial">hmPairSerial</a> and <a
        href="#hmPairForSec">hmPairForSec</a> to enable pairing).
        As an alternative, set the correct subType and model attributes, for a
        list of possible subType values see "attr hmdevice ?".</li>
    <a name="HMAES"></a>
    <li>The so called "AES-Encryption" is in reality a signing request: if it is
        enabled, an actor device will only execute a received command, if a
        correct answer to a request generated by the actor is received.  This
        means:
        <ul>
        <li>Reaction to commands is noticably slower, as 3 messages are sent
            instead of one before the action is processed by the actor.</li>
        <li>Every command and its final ack from the device is sent in clear,
            so an outside observer will know the status of each device.</li>
        <li>The firmware implementation is buggy: the "toggle" event is executed
            <b>before</b> the answer for the signing request is received, at
            least by some switches (HM-LC-Sw1-Pl and HM-LC-SW2-PB-FM).</li>
        <li>The <a href="#HMLAN">HMLAN</a> configurator will answer signing
            requests by itself, and if it is configured with the 3-byte address
            of a foreign CCU which is still configurerd with the default
            password, it is able to answer signing requests correctly.</li>
        <li>AES-Encryption is not useable with a CUL device as the interface,
            but it is supported with a HMLAN. Due to the issues above I do not
            recommend using Homematic encryption at all.</li>
        </ul>
    </li>
    </ul>
  </ul><br>

  <a name="CUL_HMset"></a>
  <b>Set</b>
  <ul>
     Note: devices which are normally send-only (remote/sensor/etc) must be set
     into pairing/learning mode in order to receive the following commands.
     <br>
     <br>

     Universal commands (available to most hm devices):
     <ul>
	 <li><B>actiondetect &lt;[hhh:mm]|off&gt;</B><a name="CUL_HMactiondetect"></a><br>
         outdated command. This functionality is started by entering or modify of the attribute actCycle. see attribure section for details<br>
	 </li>
	 <li><B>clear &lt;[readings|msgEvents]&gt;</B><a name="CUL_HMclear"></a><br>
         A set of variables can be removed.<br>
		 <ul>
		 readings: all readings will be deleted. Any new reading will be added usual. May be used to eliminate old data<br>
		 msgEvents:  all message event counter will be removed. Also commandstack will be cleared. <br>
		 </ul>
	 </li>
	 <li><B>getConfig</B><a name="CUL_HMgetConfig"></a><br>
         Will read major configuration items stored in the HM device. Executed
         on a channel it will read pair Inforamtion, List0, List1 and List3 of
         the 1st internal peer. Furthermore the peerlist will be retrieved for
         teh given channel. If executed on a device the command will get the
         above info or all assotated channels. Not included will be the
         configuration for additional peers.  <br> The command is a shortcut
         for a selection of other commands. 
	 </li>
	 <li><B>getdevicepair</B><a name="CUL_HMgetdevicepair"></a><br>
         will read the peers (see devicepair) that are assigned to a channel.
         This command needs to be executed per channel. Information will be
         stored in the field Peers of the channel (see devicepair for specials
         about single-channel deivces). <br> For sender the same procedure as
         described in devicepair is necessary to get a reading. Also note that
         a proper diaplay will only be possible if define per channel (button)
         was done - see define.  </li>
     <li><B>getpair</B><a name="CUL_HMgetpair"></a><br>
         read pair information of the device. See also <a
         href="#CUL_HMpair">pair</a></li>
     <li><B>getRegRaw [List0|List1|List2|List3|List4|List5|List6]
         &lt;peerChannel&gt; </B><a name="CUL_HMgetRegRaw"></a><br>

         Read registerset in raw format. Description of the registers is beyond
         the scope of this documentation.<br>

         Registers are structured in so called lists each containing a set of
         registers.<br>

         List0: device-level settings e.g. CUL-pairing or dimmer thermal limit
         settings.<br>

         List1: per channel settings e.g. time to drive the blind up and
         down.<br>

         List3: per 'link' settings - means per peer-channel. This is a lot of
         data!. It controlls actions taken upon receive of a trigger from the
         peer.<br>

	 List4: settings for channel (button) of a remote<br><br>

         &lt;PeerChannel&gt; paired HMid+ch, i.e. 4 byte (8 digit) value like
         '12345601'. It is mendatory for List 3 and 4 and can be left out for
         List 0 and 1. <br>

	 'all' can be used to get data of each paired link of the channel. <br>

         'selfxx' can be used to address data for internal channels (associated
         with the build-in switches if any). xx is the number of the channel in
         decimal.<br>

         Note1: execution depends on the entity. If List1 is requested on a
         device rather then a channel the command will retrieve List1 for all
         channels assotiated. List3 with peerChannel = all will get all link
         for all channel if executed on a device.<br>

         Note2: for 'sender' see <a href="#CUL_HMremote">remote</a> <br>

         Note3: the information retrieval may take a while - especially for
         devices with a lot of channels and links. It may be necessary to
         refresh the web interface manually to view the results <br>

         Note4: the direct buttons on a HM device are hidden by default.
         Nevertheless those are implemented as links as well. To get access to
         the 'internal links' it is necessary to issue 'set &lt;name&gt; regSet
         intKeyVisib 1' or 'set &lt;name&gt; setRegRaw List0 2 81'. Reset it
         by replacing '81' with '01'<br> example:<br>

	 <ul><code>
	 set mydimmer getRegRaw List1<br>
	 set mydimmer getRegRaw List3 all <br>
	 </code></ul>
	 </li>
     <li><B>pair</B><a name="CUL_HMpair"></a><br>
         Pair the device again with its known serialNumber (e.g. after a device
         reset) to the CUL. If paired, devices will report status information to
         the CUL. If not paired, the device wont respond to requests, and
         certain status information is also not reported.  Paring is on device
         level and is common for all channels. See also <a
         href="#CUL_HMgetpair">getPair</a>  and <a
         href="#CUL_HMunpair">unpair</a>.</li>
     <li><B>peerBulk</B> <peerch1,peerch2,...<a name="CUL_HMpeerBulk"></a><br>
	     peerBulk will add peer channels to the channel. All channels in the 
		 list will be added. This includes that the parameter and behavior 
		 defined for this 'link' will return to the defaults. peerBulk is only
		 meant to add peers. More suffisticated funktionality as provided by
		 <a href="#CUL_HMdevicepair">devicepair</a> is not supported. peerBulk
		 will only add channels in 'single' button mode.<br>
		 Also note that peerBulk will not delete any existing peers, just add
		 and re-add given peers.<br>
		 Main purpose of this command is the usage for re-store data to a 
		 device. It is recommended to restore register configuration utilising
		 <a href="#CUL_HMregBulk">regBulk</a>
	 Example:<br>
	 <ul><code>
	 set myChannel peerBulk 12345601,<br>
	 set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
	 </code></ul>
	 </li>
     <li><B>regRaw [List0|List1|List2|List3|List4] &lt;addr&gt; &lt;data&gt;</B>
         replaced by regBulk</li>
     <li><B>regBulk  &lt;reg List&gt;:&lt;peer&gt; &lt;addr1:data1&gt; &lt;addr2:data2&gt;...
	     </B><a name="CUL_HMregBulk"></a><br>
		 This command will replace the former regRaw. It allows to set register
		 in raw format. Its main purpose is to restore a complete register list 
		 to values secured before. <br>
		 Values may be read by <a href="#CUL_HMgetConfig">getConfig</a>. The 
		 resulting readings can be used directly for this command.<br>
		 &lt;reg List&gt; is the list data should be written to. Format could be 
		 '00', 'RegL_00', '01'...<br>
		 &lt;peer&gt; is an optional adder in case the list requires a peer. 
		 The peer can be given as channel name or the 4 byte (8 chars) HM 
		 channel ID.<br>
		 &lt;addr1:data1&gt; is the list of register to be written in hex 
		 format.<br>
	 Example:<br>
	 <ul><code>
	 set myChannel regBulk RegL_00:	02:01 0A:17 0B:43 0C:BF 15:FF 00:00<br>
	 RegL_03:FB_Btn_07
	01:00 02:00 03:00 04:32 05:64 06:00 07:FF 08:00 09:FF 0A:01 0B:44 0C:54 0D:93 0E:00 0F:00 11:C8 12:00 13:00 14:00 15:00 16:00 17:00 18:00 19:00 1A:00 1B:00 1C:00 1D:FF 1E:93 1F:00 81:00 82:00 83:00 84:32 85:64 86:00 87:FF 88:00 89:FF 8A:21 8B:44 8C:54 8D:93 8E:00 8F:00 91:C8 92:00 93:00 94:00 95:00 96:00 97:00 98:00 99:00 9A:00 9B:00 9C:00 9D:05 9E:93 9F:00 00:00<br>
	 set myblind regBulk 01 0B:10<br>
	 set myblind regBulk 01 0C:00<br>
	 </code></ul>
	 myblind will set the max drive time up for a blind actor to 25,6sec</li>
     <li><B>regSet &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><a name="CUL_HMregSet"></a><br>
        For some major register a readable version is implemented supporting
        register names &lt;regName&gt; and value conversionsing. Only a subset
        of register can be supproted.<br>
        &lt;value&gt; is the data in human readable manner that will be written
        to the register.<br>
        &lt;peerChannel&gt; is required if this register is defined on a per
        'devicepair' base. It can be set to '0' other wise.See <a
        href="CUL_HMgetRegRaw">getRegRaw</a>  for full description<br>
        Supported register for a device can be explored using<br>
          <ul><code>set regSet ? 0 0</code></ul>
        Condensed register description will be printed
        using<br>
          <ul><code>set regSet &lt;regname&gt; ? 0</code></ul>
     </li>
     <li><B>reset</B><a name="CUL_HMreset"></a><br>
         Factory reset the device. You need to pair it again to use it with
         fhem.
     </li>
     <li><B>sign [on|off]</B><a name="CUL_HMsign"></a><br>
         Activate or deactivate signing (also called AES encryption, see the <a
         href="#HMAES">note</a> above). Warning: if the device is attached via
         a CUL, you won't be able to switch it (or deactivate signing) from
         fhem before you reset the device directly.
     </li> 
     <li><B>statusRequest</B><a name="CUL_HMstatusRequest"></a><br>
         Update device status. For multichannel devices it should be issued on
         an per channel base
     </li>
     <li><B>unpair</B><a name="CUL_HMunpair"></a><br>
         "Unpair" the device, i.e. make it available to pair with other master
         devices. See <a href="#CUL_HMpair">pair</a> for description.</li>
     <li><B>virtual &lt;number of buttons&gt;</B><a name="CUL_HMvirtual"></a><br>
         configures a defined curcuit as virtual remote controll.  Then number
         of button being added is 1 to 255. If the command is issued a second
         time for the same entity additional buttons will be added. <br>
         Example for usage:
         <ul><code>
            define vRemote CUL_HM 100000  # the selected HMid must not be in use<br>
            set vRemote virtual 20        # define 20 button remote controll<br>
            set vRemote_Btn4 devicepair 0 &lt;actorchannel&gt;  # pairs Button 4 and 5 to the given channel<br>
            set vRemote_Btn4 press<br>
            set vRemote_Btn5 press long<br>
        </code></ul>
         see also <a href="#CUL_HMpress">press</a>
	 </li>
     </ul>

     <br>
     subType (i.e family) dependent commands:
     <ul>
     <br>
    <li>switch
       <ul>
          <li><B>on</B>  - set the switch on</li>
          <li><B>off</B> - set the switch off</li>
          <li><B>on-for-timer &lt;sec&gt;</B><a name="CUL_HMonForTimer"></a> -
              set the switch on for the given seconds [0-85825945].<br> Note:
              off-for-timer like FS20 is not supported. It needs to be programmed
              on link level.</li>
          <li><B>on-till &lt;time&gt;</B><a name="CUL_HMonTill"></a> - set the switch on for the given end time.<br>
	      <ul><code>set &lt;name&gt; on-till 20:32:10<br></code></ul>
	      Currently a max of 24h is supported with endtime.<br>
		  </li>
          <li><B>press &lt;[short|long]&gt;&lt;[on|off]&gt;</B><a name="CUL_HMpress"></a>
		      simulate a press of the local button or direct connected switch of the actor.<br>
			  [short|long] choose whether to simulate a short or long press of the button.<br>
			  [on|off] is relevant only for devices with direct buttons per channel. 
			  Those are available for dimmer and blind-actor, usually not for switches<br>
		  </li>
          <li><B>toggle</B> - toggle the switch.</li>
       </ul>
     <br>
	 </li>
    <li>dimmer, blindActuator
	   Dimmer may support virtual channels. Those are autocrated if applicable. Usually there are 2 virtual channels
	   in addition to the primary channel. Virtual dimmer channels are inactive by default but can be used in 
	   in parallel to the primay channel to control light. <br>
	   Virtual channels have default naming SW<channel>_V<no>. e.g. Dimmer_SW1_V1 and Dimmer_SW1_V2.<br>
	   Dimmer virtual channels are completely different from FHEM virtual buttons and actors but 
	   are part of the HM device. Documentation and capabilities for virtual channels is out of scope.<br>
       <ul>
         <li><B>0 - 100 [on-time] [ramp-time]</B><br>
             set the actuator to the given value (in percent)
             with a resolution of 0.5.<br>
             Optional for dimmer on-time and ramp time can be choosen, both in seconds with 0.1s granularity.<br>
             On-time is analog "on-for-timer".<br>
             Ramp-time default is 2.5s, 0 means instantanous<br>
             </li>
         <li><B>on</B> set level to 100%<br></li>
         <li><B>off</B> set level to 0%<br></li>
         <li><B><a href="#CUL_HMpress">press &lt;[short|long]&gt;&lt;[on|off]&gt;</B></li>
         <li><B>toggle</B> - toggle between off and the last on-value</li>
         <li><B><a href="#CUL_HMonForTimer">on-for-timer &lt;sec&gt;</a></B> - Dimmer only! <br></li>
         <li><B><a href="#CUL_HMonForTimer">on-till &lt;time&gt;</a></B> - Dimmer only! <br></li>
         <li><B>stop</B> - stop motion or dim ramp</li>
       </ul>
    <br>
	</li>
    <li>remotes, pushButton<a name="CUL_HMremote"></a><br>
         This class of devices does not react on requests unless they are put
         to learn mode. FHEM obeys this behavior by stacking all requests until
         learn mode is detected. Manual interaction of the user is necessary to
         activate learn mode. Whether commands are pending is reported on
         device level with parameter 'protCmdPend'.
       <ul>
        <li><B>devicepair &lt;btn_no&gt; &lt;hmDevice&gt; [single|dual]
        [set|unset] [actor|remote]</B><a name="CUL_HMdevicepair"></a><br>

         Pair/unpair will establish a connection between a sender-channel and
         an actuator-channel called link in HM nomenclatur. Trigger from
         sender-channel, e.g. button press, will be processed by the
         actuator-channel without CCU interaction. Sender-channel waits for an
         acknowledge of each actuator paired to it. Positive indication will be
         given once all actuator responded. <br>

         Sender must be set into learning mode after command execution. FHEM
         postpones the commands until then.<br>

         devicepair can be repeated for an existing devicepair. This will cause
         parameter reset to HM defaults for this link.<br>

         Even though the command is executed on a remote or push-button it will
         as well take effect on the actuator directly. Both sides' pairing is
         virtually independant and has different impact on sender and receiver
         side.<br>

         Devicepairing of one actuator-channel to multiple sender-channel as
         well as one sender-channel to multiple Actuator-channel is
         possible.<br>

         &lt;hmDevice&gt; is the actuator-channel to be paired.<br>

         &lt;btn_no&gt; is the sender-channel (button) to be paired. If
         'single' is choosen buttons are counted from 1. For 'dual' btn_no is
         the number of the Button-pair to be used. I.e. '3' in dual is the
         3rd button pair correcponding to button 5 and 6 in single mode.<br>

         If the command is executed on a channel the btn_no is ignored.<br>

         [single|dual]: this mode impacts the default behavior of the 
         Actuator upon using this button. E.g. a dimmer can be learned to a 
         single button or to a button pair. <br>

         'dual' (default) Button pairs two buttons to one actuator. With a 
         dimmer this means one button for dim-up and one for dim-down. <br>

         'single' uses only one button of the sender. It is useful for e.g. for
         simple switch actuator to toggle on/off. Nevertheless also dimmer can
         be learned to only one button. <br>

         'set'   will setup pairing for the channels<br>

         'unset' will remove the pairing for the channels<br>

         [actor|remote|both] limits the execution to only actor or only remote.
         This gives the user the option to redo the pairing on the remote
         channel while the settings in the actor will not be removed.<br>

         Example:
		 <ul> 
		 <code>
           set myRemote devicepair 2 mySwActChn single set       # pair second button to an actuator channel<br>
           set myRmtBtn devicepair 0 mySwActChn single set       #myRmtBtn is a button of the remote. '0' is not processed here<br>
           set myRemote devicepair 2 mySwActChn dual set         #pair button 3 and 4<br>
           set myRemote devicepair 3 mySwActChn dual unset       #remove pairing for button 5 and 6<br>
           set myRemote devicepair 3 mySwActChn dual unset aktor #remove pairing for button 5 and 6 in actor only<br>
           set myRemote devicepair 3 mySwActChn dual set remote  #pair button 5 and 6 on remote only. Link settings il mySwActChn will be maintained<br>
         </code>
		 </ul>
    </li>
       </ul>
	<br>
	</li>
    <li>virtual<a name="CUL_HMvirtual"></a><br>
       <ul>
       <li><B><a href="#CUL_HMdevicepair">devicepair</a></B> see remote</li>
       <li><B>press [long|short]<a name="CUL_HMpress"></a></B>
         simulates a button press short (default) or long. Note that the current
         implementation will not specify the duration for long. Only one trigger
         will be sent of type "long".
	   </li>
       </ul>
    </li>   
    <li>smokeDetector<br>
       Note: All these commands work right now only if you have more then one
       smoekDetector, and you paired them to form a group. For issuing the
       commands you have to use the master of this group, and currently you
       have to guess which of the detectors is the master.<br>
	   smokeDetector can be setup to teams using 
	   <a href="#CUL_HMdevicepair">devicepair</a>. You need to pair all 
	   team-members to the master. Don't forget to also devicepair the master
	   itself to the team - i.e. pair it to itself! doing that you have full 
	   controll over the team and don't need to guess.<br>
     <ul>
       <li><B>test</B> - execute a network test</li>
       <li><B>alarmOn</B> - initiate an alarm</li>
       <li><B>alarmOff</B> - switch off the alarm</li>
     </ul>
    </li>
    <li>4Dis (HM-PB-4DIS-WM)
    <ul>
      <li><B>text &lt;btn_no&gt; [on|off] &lt;text1&gt; &lt;text2&gt;</B><br>
          Set the text on the display of the device. To this purpose issue
          this set command first (or a number of them), and then choose from
          the teach-in menu of the 4Dis the "Central" to transmit the data.
          Example:
          <ul>
		  <code>
          set 4Dis text 1 on On Lamp<br>
          set 4Dis text 1 off Kitchen Off<br>
          </code>
		  </ul>
	  </li>
	</ul>
    <br></li>
    <li>Climate-Control (HM-CC-TC)
    <ul>
      <li>day-temp &lt;tmp&gt;<br>
          night-temp &lt;tmp&gt;<br>
          party-temp &lt;tmp&gt;<br>
          desired-temp &lt;tmp&gt;<br>
          Set different temperatures. Temp must be between 6 and 30
          Celsius, and precision is half a degree.</li>
      <li>tempListSat HH:MM temp ... 24:00 temp<br>
          tempListSun HH:MM temp ... 24:00 temp<br>
          tempListMon HH:MM temp ... 24:00 temp<br>
          tempListTue HH:MM temp ... 24:00 temp<br>
          tempListThu HH:MM temp ... 24:00 temp<br>
          tempListWed HH:MM temp ... 24:00 temp<br>
          tempListFri HH:MM temp ... 24:00 temp<br>
          Specify a list of temperature intervals. Up to 24 intervals can be
          specified for each week day, the resolution is 10 Minutes. The
          last time spec must always be 24:00.<br>
          Example: set th tempListSat 06:00 19 23:00 22.5 24:00 19<br>
          Meaning: until 6:00 temperature shall be 19, from then until 23:00 temperature shall be 
          22.5, thereafter until midnight, 19 degrees celsius is desired.</li>
      <li>displayMode [temp-only|temp-hum]<br>
          displayTemp [actual|setpoint]<br>
          displayTempUnit [celsius|fahrenheit]<br>
          controlMode [manual|auto|central|party]<br>
          decalcDay &lt;day&gt;</li>
    </ul><br>
	</li>
    <li>OutputUnit (HM-OU-LED16)
    <ul>
    <li><B>led [off|red|green|yellow]</B><br>
        switches the LED of the channel to the color. If the command is
        executed on a device it will set all LEDs to the specified
        color.<br>
		For Expert all LEDs can be set individual by providing a 8-digit hex number to the device.<br></li>
    <li><B>ilum &lt;brightness&gt;&lt;duration&gt; </B><br>
        &lt;brightness&gt; [0-15] of backlight.<br>
        &lt;duration&gt; [0-127] in sec. 0 is permanent 'on'.<br>
    </li>
    </ul><br>
	</li>
    <li>OutputUnit (HM-OU-CFM-PL)
    <ul>
      <li><B>led &lt;color&gt;[,&lt;color&gt;..]</B><br>
          Possible colors are [redL|greenL|yellowL|redS|greenS|yellowS]. A
          sequence of colors can be given separating the color entries by ','.
          White spaces must not be used in the list. 'S' indicates short and
          'L' long ilumination. <br></li>
      <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt..]</B><br>
         Play a series of tones. List is to be entered separated by ','. White
         spaces must not be used in the list.<br></li>
    </ul><br>
	</li>
    <li>HM-RC-19xxx
      <ul>
      <li><B>alarm &lt;count&gt;</B><br>
          issue an alarm message to the remote<br></li>
      <li><B>service &lt;count&gt;</B><br>
          issue an service message to the remote<br></li>
      <li><B>symbol &lt;symbol&gt; [set|unset]</B><br>
          activate a symbol as available on the remote.<br></li>
      <li><B>beep [off|1|2|3]</B><br>
          activate tone<br></li>
      <li><B>backlight [off|on|slow|fast]</B><br> 
          activate backlight<br></li>
      <li><B>display &lt;text&gt; comma unit tone backlight &lt;symbol(s)&gt;
         </B><br>
         control display of the remote<br>
         &lt;text&gt; : up to 5 chars <br>
         comma : 'comma' activates the comma, 'no' leaves it off <br>
         [unit] : set the unit symbols.
         [off|Proz|Watt|x3|C|x5|x6|x7|F|x9|x10|x11|x12|x13|x14|x15]. Currently
         the x3..x15 display is not tested. <br>

         tone : activate one of the 3 tones [off|1|2|3]<br>

         backlight: activate backlight flash mode [off|on|slow|fast]<br>

         &lt;symbol(s)&gt; activate symbol display. Multople symbols can be
         acticated at the same time, concatinating them comma separated. Don't
         use spaces here. Possiblesymbols are			

         [bulb|switch|window|door|blind|scene|phone|bell|clock|arrowUp|arrowDown]<br><br>
         Example:
           <ul><code>
           # "hello" in display, symb bulb on, backlight, beep<br>
           set FB1 display Hello no off 1 on bulb<br>
           # "1234,5" in display with unit 'W'. Symbols scene,phone,bell and
           # clock are active. Backlight flashing fast, Beep is second tone<br>
           set FB1 display 12345 comma Watt 2 fast scene,phone,bell,clock
           </ul></code>  
         </li>
      </ul><br>
	  </li>
    <li>keyMatic<br><br>
      <ul>The Keymatic uses the AES signed communication. Therefore the control
      of the Keymatic is only together with the HM-LAN adapter possible. But
      the CUL can read and react on the status information of the
      Keymatic.</ul><br>
      <ul>
      <li><B>lock</B><br>
         The lock bolt moves to the locking position<br></li>
      <li><B>unlock [sec]</B><br>
         The lock bolt moves to the unlocking position.<br>
		 [sec]: Sets the delay in seconds after the lock automatically locked again.<br>
		 0 - 65535 seconds</li>
      <li><B>open [sec]</B><br>
         Unlocked the door so that the door can be opened.<br>
         [sec]: Sets the delay in seconds after the lock automatically locked
         again.<br>0 - 65535 seconds</li>
      <li><B>inhibit [on|off]</B><br>
         Block / unblock all directly paired remotes and the hardware buttons of the
         keyMatic. If inhibit set on, the door lock drive can be controlled only by
         FHEM.<br><br>
         Examples:
         <ul><code>
           # Lock the lock<br>
           set keymatic lock<br><br>
           # open the door and relock the lock after 60 seconds<br>
          set keymatic unlock 60
        </ul></code>  
        </li>
      </ul>
	</li>
	  
	<li>winMatic <br><br>
      <ul>winMatic provides 2 channels, one for the window control and a second
	  for the accumulator.</ul><br>
      <ul>
      <li><B>level &lt;level&gt; &lt;relockDelay&gt; &lt;speed&gt;</B><br>
         set the level. <br>
		 &lt;level&gt;:  range is 0 to 100%<br>
		 &lt;relockDelay&gt;: range 0 to 65535 sec. 'ignore' can be used to igneore the value alternaly <br>
		 &lt;speed&gt;: range is 0 to 100%<br>
		 </li>
      <li><B>stop</B><br>
         stop movement<br>
		 </li>
      </ul></li>
   <li>HM-Sys-sRP-Pl<br><br>
	setRepeat => "[no1..36] <sendName> <recName> [bdcast-yes|no]"
    <ul>
      <li><B>setRepeat    &lt;entry&gt; &lt;sender&gt; &lt;receiver&gt; &lt;broadcast&gt;</B><br>
      &lt;entry&gt; [1..36] entry number in repeater table. The repeater can handle up to 36 entries.<br>
      &lt;sender&gt; name or HMID of the sender or source which shall be repeated<br>
      &lt;receiver&gt; name or HMID of the receiver or destination which shall be repeated<br>
      &lt;broadcast&gt; [yes|no] determines whether broadcast from this ID shall be repeated<br>
    </ul><br></li>
	</li>
   </ul>
   <br>
     Debugging:
       <ul>
         <li><B>raw &lt;data&gt; ...</B><br>
             Only needed for experimentation.
             send a list of "raw" commands. The first command will be
             immediately sent, the next one after the previous one is acked by
             the target.  The length will be computed automatically, and the
             message counter will be incremented if the first two charcters are
             ++. Example (enable AES):<pre>
   set hm1 raw ++A001F100001234560105000000001\
               ++A001F10000123456010802010AF10B000C00\
               ++A001F1000012345601080801\
               ++A001F100001234560106</pre>
         </li>
       </ul>
  </ul>
  <br>
  
  <a name="CUL_HMget"></a>
  <b>Get</b><br>
     <ul>
     <li><B>configSave &lt;filename&gt;</B><a name="CUL_HMconfigSave"></a><br>
         Saves the configuration of an entity into a file. Data is stored in a
		 format to be executed from fhem command prompt.<br>
		 The file is located in the fhem home directory aside of fhem.cfg. Data 
		 will be stored cumulative - i.e. new data will be appended to the 
		 file. It is up to the user to avoid duplicate storage of the same 
		 entity.<br>
		 Target of the data is ONLY the HM-device information which is located
		 IN the HM device. Explicitely this is the peer-list and the register.
		 With the register also the pairing is included.<br>
		 The file is readable and editable by the user. Additionaly timestamps 
		 are stored to help user to validate.<br>
		 Restrictions:<br>
		 Even though all data of the entity will be secured to the file FHEM 
		 stores the data that is avalilable to FHEM at time of save!. It is up 
		 to the user to read the data from the HM-hardware prior to execution. 
		 See recommended flow below.<br>
		 This command will not store any FHEM attributes o device definitions.
		 This continues to remain in fhem.cfg.<br>
		 Furthermore the secured data will not automatically be reloaded to the 
		 HM-hardware. It is up to the user to perform a restore.<br><br>
		 As with other commands also 'configSave' is best executed on a device 
		 rather then on a channel. If executed on a device also the assotiated 
		 channel data will be secured. <br><br>
		 <code>
		 Recommended work-order for device 'HMdev':<br>
		 set HMdev clear msgEvents  # clear old events to better check flow<br>
		 set HMdev getConfig        # read device & channel inforamtion<br>
		 # wait untill operation is complete<br>
		 # protState should be CMDs_done<br>
		 #           there shall be no warnings amongst prot... variables<br>
		 get configSave myActorFile<br>
		 </code>
         </li>
     <li><B>param &lt;paramName&gt;</B><br>
         returns the content of the relevant parameter for the entity. <br>
         Note: if this command is executed on a channel and 'model' is
         requested the content hosting device's 'model' will be returned.
         </li>
     <li><B>reg &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
         returns the value of a register. The data is taken from the storage in FHEM and not read directly outof the device. If register content is not present please use getConfig, getReg in advance.<br>

         &lt;addr&gt; address in hex of the register. Registername can be used alternaly if decoded by FHEM. "all" will return all decoded register for this entity in one list.<br>
         &lt;list&gt; list from which the register is taken. If rgistername is used list is ignored and can be set to 0.<br>
         &lt;peerID&gt; identifies the registerbank in case of list3 and list4. It an be set to dummy if not used.<br>
         </li>
     <li><B>regList</B><br>
         returns a list of register that are decoded by FHEM for this device.<br>
		 Note that there could be more register implemented for a device.<br>
         </li>
	 <br></ul>

  <a name="CUL_HMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#actCycle">actCycle</a>
	     actCycle &lt;[hhh:mm]|off&gt;<br>
         Supports 'alive' or better 'not alive' detection for devices. [hhh:mm] is the maxumin silent time for the device. Upon no message received in this period an event will be raised "&lt;device&gt; is dead". If the device sends again another notification is posted "&lt;device&gt; is alive". <br>
		 This actiondetect will be autocreated for each device with build in cyclic status report.<br>
		 Controlling entity is a pseudo device "ActionDetector" with HMId "000000".<br>
		 Due to performance considerations the report latency is set to 600sec (10min). It can be controlled by the attribute "actCycle" of "ActionDetector".<br>
		 Once entered to the supervision the HM device has 2 attributes:<br>
		 <ul>
		 actStatus: activity status of the device<br>
		 actCycle:  detection period [hhh:mm]<br>
		 </ul>
		 The overall function can be viewed checking out the "ActionDetector" entity. The status of all entities is present in the READING section.<br>
		 Note: This function can be enabled for devices with non-cyclic messages as well. It is up to the user to enter a reasonable cycletime.
	</li>
    <li><a name="expert">expert</a><br>
        This attribut controls the visibility of the readings. This attibute controlls 
		the presentation of device parameter in the readings.<br> 
		3 level can be choosen:<br>
		<ul>
		0_off: standart level. Display commonly used parameter<br>
		1_on: enhanced level. Display all decoded device parameter<br>
		2_full: display all parameter plus raw register information as well. <br>
		</ul>
		If expert is applied a device it is used for assotiated channels. 
		It can be overruled if expert attibute is also applied to the channel device.<br>
		Make sure to check out attribut showInternalValues in the global values as well. 
		extert takes benefit of the implementation. 
		Nevertheless  - by definition - showInternalValues overrules expert. 
		</li>
    <li><a name="model">model</a>,
        <a name="subType">subType</a><br>
        These attributes are set automatically after a successful pairing.
        They are not supposed to be set by hand, and are necessary in order to
        correctly interpret device messages or to be able to send them.</li>
    <li><a name="rawToReadable">rawToReadable</a><br>
        Used to convert raw KFM100 values to readable data, based on measured
        values. E.g.  fill slowly your container, while monitoring the
        values reported with <a href="#inform">inform</a>. You'll see:
        <ul>
          10 (at 0%)<br>
          50 (at 20%)<br>
          79 (at 40%)<br>
         270 (at 100%)<br>
        </ul>
        Apply these values with: "attr KFM100 rawToReadable 10:0 50:20 79:40 270:100".
        fhem will do a linear interpolation for values between the bounderies.
        </li>
    <li><a name="unit">unit</a><br>
        set the reported unit by the KFM100 if rawToReadable is active. E.g.<br>
        attr KFM100 unit Liter
        </li>
    <li><a name="autoReadReg">autoReadReg</a><br>
        set to '1' will execute a getConfig for the device automatically after each reboot of FHEM. 
		Execution will be delayed in order to prevent congestion at startup. Therefore the update 
		of the readings and the display will be delayed depending on the sice of the database.<br>
		Recommendations and constrains upon usage:<br>
        <ul>
          use this attribute on the device or channel 01. Do not use it separate on each channel 
		  of a multi-channel device to avoid duplicate execution<br>
          usage on devices which only react to 'config' mode is not recommended since executen will 
		  not start until config is triggered by the user<br>
          usage on devices which support wakeup-mode is usefull. But consider that execution is delayed 
		  until the device "wakes up".<br>
        </ul>
        </li>
  </ul>
  <br>
  <a name="CUL_HMevents"></a>
  <b>Generated events:</b>
  <ul>
  <li>KS550/HM-WDS100-C6-O:<br>
      T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b<br>
      temperature $t<br>
      humidity $h<br>
      windSpeed $w<br>
      windDirection $wd<br>
      windDirRange $wdr<br>
      rain $r<br>
      isRaining $ir<br>
      sunshine $s<br>
      brightness $b<br>
      unknown $p<br>
	  </li>
  <li>HM-CC-TC:<br>
      T: $t H: $h<br>
      measured-temp $t<br>
      humidity $h<br>
      actuator $vp %<br>
	  desired-temp $dTemp<br>
	  desired-temp-manu $dTemp<br>
	  windowopen-temp-%d  %.1f (sensor:%s)<br>
	  tempList$wd  hh:mm $t hh:mm $t ...<br>
      displayMode temp-[hum|only]<br>
      displayTemp [setpoint|actual]<br>
      displayTempUnit [fahrenheit|celsius]<br>
      controlMode [manual|auto|central|party]<br>
      decalcDay [Sat|Sun|Mon|Tue|Wed|Thu|Fri]<br>
      tempValveMode [Auto|Closed|Open|unknown]<br>
	  param-change  offset=$o1, value=$v1<br>
      ValveErrorPosition_for_$dname  $vep %<br>
      ValveOffset_for_$dname : $of %<br>
	  ValveErrorPosition $vep %<br>
	  ValveOffset $of %<br>
      time-request<br>
  </li>
  <li>HM-CC-VD:<br>
      $vp %<br>
	  battery:[critical|low|ok]<br>
      motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
	  ValvePosition:$vp %<br>
      ValveErrorPosition:$vep %<br>
      ValveOffset:$of %<br>
  </li>
  <li>KFM100:<br>
      $v<br>
      $cv,$unit<br>
      rawValue:$v<br>
      Sequence:$seq<br>
      content:$cv,$unit<br>
  </li>
  <li>HM-LC-BL1-PB-FM:<br>
      motor: [opening|closing]<br>
	  </li>
  <li>HM-SEC-SFA-SM:<br>
	  powerError [on|off]<br>
	  sabotageError [on|off]<br>
	  battery: [critical|low|ok]<br>
  </li>
  <li>HM-LC-SW1-BA-PCB:<br>
	  battery: [low|ok]<br>
  </li>
  <li>HM-OU-LED16<br>
  	  color $value                  # hex - for device only<br>
	  $value                        # hex - for device only<br>
	  color [off|red|green|orange]  # for channel <br>
      [off|red|green|orange]	    # for channel <br>
  </li>
  <li>HM-OU-CFM-PL<br>
	  [on|off|$val]<br>
  </li>
  <li>switch/dimmer/blindActuator:<br>
	  $val<br>
	  powerOn [on|off|$val]<br>
      [unknown|motor|dim] [up|down|stop]:$val<br>
  </li>
  <li>dimmer:<br>
      overload [on|off]<br>
      overheat [on|off]<br>
      reduced [on|off]<br>
      dim: [up|down|stop]<br>
  </li>
  <li>remote/pushButton/outputUnit<br>
	  <ul> (to $dest) is added if the button is peered and does not send to broadcast<br>
	  Release is provided for peered channels only</ul>
      Btn$x onShort<br>
      Btn$x offShort<br>
      Btn$x onLong $counter<br>
      Btn$x offLong $counter<br>
      Btn$x onLongRelease $counter<br>
      Btn$x offLongRelease $counter<br>
      Btn$x onShort (to $dest)<br>
      Btn$x offShort (to $dest)<br>
      Btn$x onLong $counter (to $dest)<br>
      Btn$x offLong $counter (to $dest)<br>
      Btn$x onLongRelease $counter (to $dest)<br>
      Btn$x offLongRelease $counter (to $dest)<br>
  </li>
  <li>remote/pushButton<br>
      battery [low|ok]<br>
  </li>
  <li>swi<br>
      Btn$x toggle<br>
      Btn$x toggle (to $dest)<br>
      battery: [low|ok]<br>
  </li>
  <li>motionDetector<br>
      brightness:$b<br>
      alive<br>
      motion on (to $dest)<br>
      motionCount $cnt _next:$nextTr"-"[0x0|0x1|0x2|0x3|15|30|60|120|240|0x9|0xa|0xb|0xc|0xd|0xe|0xf]<br>
      cover [closed|open]<br>
      battery [low|ok]<br>
	  devState_raw.$d1 $d2<br>
  </li>
  <li>smokeDetector<br>
      [off|smoke-Alarm|alive]             # for team leader<br>
	  [off|smoke-forward|smoke-alarm]     # for team members<br>
 	  SDteam [add|remove]_$dname<br>
      battery [low|ok]<br>
      smoke_detect on from $src<br>
      test:from $src<br>
  </li>
  <li>threeStateSensor<br>
      [open|tilted|closed]]<br>
      [wet|damp|dry]                 #HM-SEC-WDS only<br>
	  cover [open|closed]            #HM-SEC-WDS only<br>
	  alive yes<br>
      battery [low|ok]<br>
      contact [open|tilted|closed]<br>
	  contact [wet|damp|dry]         #HM-SEC-WDS only<br>
  </li>
  <li>THSensor  and HM-WDC7000<br>
      T: $t H: $h AP: $ap<br>
      temperature $t<br>
      humidity $h<br>
      airpress $ap                   #HM-WDC7000 only<br>
  </li>
  <li>winMatic<br>
	  [locked|$value]<br>
	  motorError [no|TurnError|TiltError]<br>
	  direction [no|up|down|undefined]<br>	 
	  charge [trickleCharge|charge|dischange|unknown]<br>
      airing [inactiv|$air]<br>
      course [tilt|close]<br>
      airing [inactiv|$value]<br>
      contact tesed<br>
  </li>
  <li>keyMatic<br>
      unknown:40<br>
      battery [low|ok]<br>
      uncertain [yes|no]<br>
      error [unknown|motor aborted|clutch failure|none']<br>
      lock [unlocked|locked]<br>
      [unlocked|locked|uncertain]<br>
  </li>
  </ul>
  <br>
</ul>
=end html
=cut
