##############################################
# CUL HomeMatic device configuration data
# $Id: HMConfig.pm 4170 2013-11-07 14:13:43Z martinp876 $

#####################################################
# configuration data for CUL_HM -used to split code and configuration
package HMConfig;

use strict;
use warnings;

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
#register list definition - identifies valid register lists
# 1,3,5:3p.4.5 => list 1 valid for all channel
#              => list 3 for all channel
#              => list 5 only for channel 3 but assotiated with peers
#              => list 5 for channel 4 and 5 with peer=00000000
#
my %culHmModel=(
  "0001" => {name=>"HM-LC-SW1-PL-OM54"       ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0002" => {name=>"HM-LC-SW1-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0003" => {name=>"HM-LC-SW4-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0004" => {name=>"HM-LC-SW1-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0005" => {name=>"HM-LC-BL1-FM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0006" => {name=>"HM-LC-BL1-SM"            ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0007" => {name=>"KS550"                   ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",},
  "0008" => {name=>"HM-RC-4"                 ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0009" => {name=>"HM-LC-SW2-FM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000A" => {name=>"HM-LC-SW2-SM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000B" => {name=>"HM-WS550"                ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",},
  "000D" => {name=>"ASH550"                  ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "000E" => {name=>"ASH550I"                 ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "000F" => {name=>"S550IA"                  ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",},
  "0011" => {name=>"HM-LC-SW1-PL"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0012" => {name=>"HM-LC-DIM1L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0013" => {name=>"HM-LC-DIM1L-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "0016" => {name=>"HM-LC-DIM2L-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "0018" => {name=>"CMM"                     ,st=>'remote'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0019" => {name=>"HM-SEC-KEY"              ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",},
  "001A" => {name=>"HM-RC-P1"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",},
  "001B" => {name=>"HM-RC-SEC3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001C" => {name=>"HM-RC-SEC3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001D" => {name=>"HM-RC-KEY3"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001E" => {name=>"HM-RC-KEY3-B"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001F" => {name=>"KS888"                   ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",},
  "0022" => {name=>"WS888"                   ,st=>''                  ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0026" => {name=>"HM-SEC-KEY-S"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",},
  "0027" => {name=>"HM-SEC-KEY-O"            ,st=>'keyMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",},
  "0028" => {name=>"HM-SEC-WIN"              ,st=>'winMatic'          ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"Win:1:1,Akku:2:2",},
  "0029" => {name=>"HM-RC-12"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002A" => {name=>"HM-RC-12-B"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002B" => {name=>"HM-WS550Tech"            ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",},
  "002C" => {name=>"KS550TECH"               ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",},
  "002D" => {name=>"HM-LC-SW4-PCB"           ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"Sw:1:4",},
  "002E" => {name=>"HM-LC-DIM2L-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "002F" => {name=>"HM-SEC-SC"               ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0030" => {name=>"HM-SEC-RHS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0031" => {name=>"HM-WS550LCB"             ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",},
  "0032" => {name=>"HM-WS550LCW"             ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"",},
  "0033" => {name=>"KS550LC"                 ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",},
  "0034" => {name=>"HM-PBI-4-FM"             ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",}, # HM Push Button Interface
  "0035" => {name=>"HM-PB-4-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0036" => {name=>"HM-PB-2-WM"              ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:2",},
                                                                                                   
  "0037" => {name=>"HM-RC-19"                ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:1p.2p.3p.4p.5p.6p.7p.8p.9p.10p.11p.12p.13p.14p.15p.16p'
                                                                                                                        ,chn=>"Btn:1:17,Disp:18:18",},
  "0038" => {name=>"HM-RC-19-B"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:1p.2p.3p.4p.5p.6p.7p.8p.9p.10p.11p.12p.13p.14p.15p.16p'
                                                                                                                        ,chn=>"Btn:1:17,Disp:18:18",},
  "0039" => {name=>"HM-CC-TC"                ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:2p,5:2.3p,6:2',chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3",},
  "003A" => {name=>"HM-CC-VD"                ,st=>'thermostat'        ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'p,5'          ,chn=>"",},
  "003B" => {name=>"HM-RC-4-B"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "003C" => {name=>"HM-WDS20-TH-O"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "003D" => {name=>"HM-WDS10-TH-O"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "003E" => {name=>"HM-WDS30-T-O"            ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",},
  "003F" => {name=>"HM-WDS40-TH-I"           ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "0040" => {name=>"HM-WDS100-C6-O"          ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p,1'          ,chn=>"",},
  "0041" => {name=>"HM-WDC7000"              ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>''       ,lst=>'1,4'          ,chn=>"",},
  "0042" => {name=>"HM-SEC-SD"               ,st=>'smokeDetector'     ,cyc=>'28:00' ,rxt=>'b'      ,lst=>'p'            ,chn=>"",},
  "0043" => {name=>"HM-SEC-TIS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0044" => {name=>"HM-SEN-EP"               ,st=>'sensor'            ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0045" => {name=>"HM-SEC-WDS"              ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0046" => {name=>"HM-SWI-3-FM"             ,st=>'swi'               ,cyc=>''      ,rxt=>'c'      ,lst=>'4'            ,chn=>"Sw:1:3",},
  "0047" => {name=>"KFM-Sensor"              ,st=>'KFM100'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0048" => {name=>"IS-WDS-TH-OD-S-R3"       ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",},
  "0049" => {name=>"KFM-Display"             ,st=>'KFM100'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "004A" => {name=>"HM-SEC-MDIR"             ,st=>'motionDetector'    ,cyc=>'00:20' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",},
  "004B" => {name=>"HM-Sec-Cen"              ,st=>'AlarmControl'      ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "004C" => {name=>"HM-RC-12-SW"             ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "004D" => {name=>"HM-RC-19-SW"             ,st=>'remote'            ,cyc=>''      ,rxt=>'c:b'    ,lst=>'1,4:1p.2p.3p.4p.5p.6p.7p.8p.9p.10p.11p.12p.13p.14p.15p.16p'
                                                                                                                        ,chn=>"Btn:1:17,Disp:18:18",},
  "004E" => {name=>"HM-LC-DDC1-PCB"          ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # door drive controller 1-channel (PCB)
  "004F" => {name=>"HM-SEN-MDIR-SM"          ,st=>'motionDetector'    ,cyc=>''      ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",},
  "0050" => {name=>"HM-SEC-SFA-SM"           ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Siren:1:1,Flash:2:2",},
  "0051" => {name=>"HM-LC-SW1-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "0052" => {name=>"HM-LC-SW2-PB-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Sw:1:2",},
  "0053" => {name=>"HM-LC-BL1-PB-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0054" => {name=>"DORMA_RC-H"              ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"",}, # DORMA Remote 4 buttons 
  "0056" => {name=>"HM-CC-SCD"	             ,st=>'smokeDetector'     ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "0057" => {name=>"HM-LC-DIM1T-PL"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0058" => {name=>"HM-LC-DIM1T-CV"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "0059" => {name=>"HM-LC-DIM1T-FM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "005A" => {name=>"HM-LC-DIM2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},#4virt- is this a faulty entry?
  "005C" => {name=>"HM-OU-CF-PL"             ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Led:1:1,Sound:2:2",},
  "005D" => {name=>"HM-Sen-MDIR-O"           ,st=>'motionDetector'    ,cyc=>'00:10' ,rxt=>'c:w:l'  ,lst=>'1,4'          ,chn=>"",},
  "005F" => {name=>"HM-SCI-3-FM"             ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"Sw:1:3",},
  "0060" => {name=>"HM-PB-4DIS-WM"           ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:20",},
  "0061" => {name=>"HM-LC-SW4-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0062" => {name=>"HM-LC-SW2-DR"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "0064" => {name=>"DORMA_atent"             ,st=>''                  ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"Btn:1:3",}, # DORMA Remote 3 buttons
  "0065" => {name=>"DORMA_BRC-H"             ,st=>'singleButton'      ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"Btn:1:4",}, # Dorma Remote 4 single buttons
  "0066" => {name=>"HM-LC-SW4-WM"            ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0067" => {name=>"HM-LC-Dim1PWM-CV"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0068" => {name=>"HM-LC-Dim1TPBU-FM"       ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0069" => {name=>"HM-LC-Sw1PBU-FM"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "006A" => {name=>"HM-LC-Bl1PBU-FM"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "006B" => {name=>"HM-PB-2-WM55"            ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"Btn:1:2",},
  "006C" => {name=>"HM-LC-SW1-BA-PCB"        ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",},
  "006D" => {name=>"HM-OU-LED16"             ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'p'            ,chn=>"Led:1:16",},
  "006E" => {name=>"HM-LC-Dim1L-CV-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},	
  "006F" => {name=>"HM-LC-Dim1L-Pl-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0070" => {name=>"HM-LC-Dim2L-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "0071" => {name=>"HM-LC-Dim1T-Pl-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0072" => {name=>"HM-LC-Dim1T-CV-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0073" => {name=>"HM-LC-Dim1T-FM-644"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "0074" => {name=>"HM-LC-Dim2T-SM"          ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "0075" => {name=>"HM-OU-CFM-PL"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"Led:1:1,Mp3:2:2",},
  "0076" => {name=>"HM-Sys-sRP-Pl"           ,st=>'repeater'          ,cyc=>''      ,rxt=>''       ,lst=>'p,2'          ,chn=>"",}, # repeater
  "0078" => {name=>"HM-Dis-TD-T"             ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'3'            ,chn=>"",}, #
  "0079" => {name=>"ROTO_ZEL-STG-RM-FWT"     ,st=>''                  ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,3'          ,chn=>"",}, #
  "007A" => {name=>"ROTO_ZEL-STG-RM-FSA"     ,st=>''                  ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, #
  "007B" => {name=>"ROTO_ZEL-STG-RM-FEP-230V",st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)
  "007C" => {name=>"ROTO_ZEL-STG-RM-FZS"     ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled socket adapter switch actuator 1-channel				
  "007D" => {name=>"ROTO_ZEL-STG-RM-WT-2"    ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}, # HM Push Button 2
  "007E" => {name=>"ROTO_ZEL-STG-RM-DWT-10"  ,st=>'remote'            ,cyc=>'00:10' ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}, # HM Remote Display 4 buttons Roto
  "007F" => {name=>"ROTO_ZEL-STG-RM-FST-UP4" ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}, # HM Push Button Interface
  "0080" => {name=>"ROTO_ZEL-STG-RM-HS-4"    ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}, # HM Remote 4 buttons
  "0081" => {name=>"ROTO_ZEL-STG-RM-FDK"     ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}, # HM Rotary Handle Sensor
  "0082" => {name=>"Roto_ZEL-STG-RM-FFK"     ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}, # HM Shutter Contact
  "0083" => {name=>"Roto_ZEL-STG-RM-FSS-UP3" ,st=>'swi'               ,cyc=>''      ,rxt=>'c'      ,lst=>'4'            ,chn=>"",}, # HM Switch Interface 3 switches
  "0084" => {name=>"Schueco_263-160"         ,st=>'smokeDetector'     ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}, # HM SENSOR_FOR_CARBON_DIOXIDE
  "0086" => {name=>"Schueco_263-146"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)
  "0087" => {name=>"Schueco_263-147"         ,st=>'blindActuator'     ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled blind actuator 1-channel (flush-mount)   						
  "0088" => {name=>"Schueco_263-132" 		 ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer L (ceiling voids)				
  "0089" => {name=>"Schueco_263-134"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer T (ceiling voids)							
  "008A" => {name=>"Schueco_263-133"         ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # 1 channel dimmer TPBU (flush mount) 						
  "008B" => {name=>"Schueco_263-130"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled switch actuator 1-channel (flush-mount)							
  "008C" => {name=>"Schueco_263-131"         ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, # radio-controlled switch actuator 1-channel (flush-mount)						
  "008D" => {name=>"Schueco_263-135"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c:w'    ,lst=>'1,3'          ,chn=>"",}, # HM Push Button 2
  "008E" => {name=>"Schueco_263-155"         ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}, # HM Remote Display 4 buttons
  "008F" => {name=>"Schueco_263-145"         ,st=>'pushButton'        ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"",}, # HM Push Button Interface
  "0090" => {name=>"Schueco_263-162"         ,st=>'motionDetector'    ,cyc=>'00:30' ,rxt=>'c:w:l'  ,lst=>'1,3'          ,chn=>"",}, # HM radio-controlled motion detector
  "0092" => {name=>"Schueco_263-144"         ,st=>'switch'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,3'          ,chn=>"",}, # HM Switch Interface 3 switches 
  "0093" => {name=>"Schueco_263-158"         ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"",}, #
  "0094" => {name=>"IS-WDS-TH-OD-S-R3"       ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p'            ,chn=>"",}, #
  "0095" => {name=>"HM-CC-RT-DN"             ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:1p.2p.5p.6p,3:3p.6p,1,7:4'
                                                                                                                        ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3,ClimRT_tr:4:4,ClimaTeam:5:5,remote:6:6"}, #
  "0096" => {name=>"WDF-solar"               ,st=>'blindActuatorSol'  ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"win:1:1,blind:2:3",}, #
  "009B" => {name=>"Schueco_263-xxx"         ,st=>'tipTronic'         ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1:1.2,3:1p.3p',chn=>"act:1:1,sen:2:2,sec:3:3",}, #
  "009F" => {name=>"HM-Sen-Wa-Od"            ,st=>'sensor'            ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",}, #capacitive filling level sensor
  "00A0" => {name=>"HM-RC-4-2"               ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"Btn:1:4",},# init : ,01,01,1E
  "00A1" => {name=>"HM-LC-SW1-PL2"           ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",}, #
  "00A2" => {name=>"ROTO_ZEL-STG-RM-FZS-2"   ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",}, #radio-controlled socket adapter switch actuator 1-channel
  "00A3" => {name=>"HM-LC-Dim1L-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "00A4" => {name=>"HM-LC-Dim1T-Pl-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"",},
  "00A5" => {name=>"HM-RC-Sec4-2"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"Btn:1:2,BTN_T:3:1,BTN_A:4:1",},#only 1 and 2 canbe peered???
  "00A6" => {name=>"HM-RC-Key4-2"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c:l'    ,lst=>'1,4'          ,chn=>"Btn:1:2,BTN_T:3:1,BTN_A:4:1",},#only 1 and 2 canbe peered???
  "00A7" => {name=>"HM-Sen-RD-O"             ,st=>'sensRain'          ,cyc=>''      ,rxt=>''       ,lst=>'1:1,4:1p'     ,chn=>"Rain:1:1,Heating:2:2",},#stc:70 THSensor
  "00A8" => {name=>"HM-WDS30-OT2-SM"         ,st=>'THSensor'          ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p'            ,chn=>"T1:1:1,T2:2:2,T1_T2:3:3,T2_T1:4:4,Event:5:5",},
  "00A9" => {name=>"HM-PB-6-WM55"            ,st=>'remote'            ,cyc=>''      ,rxt=>'c'      ,lst=>'1,4'          ,chn=>"Btn:1:6",},
  "00AB" => {name=>"HM-LC-SW4-BA-PCB"        ,st=>'switch'            ,cyc=>''      ,rxt=>'b'      ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "00AC" => {name=>"HM-ES-PMSw1-Pl"          ,st=>'powerMeter'        ,cyc=>'00:10' ,rxt=>''       ,lst=>'1,1:2.3.4.5.6,3:1'
                                                                                                                        ,chn=>"Sw:1:4,Pwr:2:2,CondP:3:3,CondI:4:4,CondU:5:5,CondF:6:6",},
  "00AD" => {name=>"HM-TC-IT-WM-W-EU"        ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w'    ,lst=>'p:1p.2p.6p.7p,3:3p.6p,1,7:2,8:2,9:2'
                                                                                                                        ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3,remote:6:6,SwitchTr:7:7",},
  "00AF" => {name=>"HM-OU-CM-PCB"            ,st=>'outputUnit'        ,cyc=>''      ,rxt=>''       ,lst=>'3'            ,chn=>"",},
  "00B1" => {name=>"HM-SEC-SC-2"             ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "00B2" => {name=>"HM-SEC-WDS-2"            ,st=>'threeStateSensor'  ,cyc=>'28:00' ,rxt=>'c:w'    ,lst=>'1,4'          ,chn=>"",},
  "00B3" => {name=>"HM-LC-Dim1L-Pl-3"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},	
  "00B4" => {name=>"HM-LC-Dim1T-Pl-3"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00B5" => {name=>"HM-LC-Dim1PWM-CV-2"      ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00B6" => {name=>"HM-LC-Dim1TPBU-FM-2"     ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00B7" => {name=>"HM-LC-Dim1L-CV-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00B8" => {name=>"HM-LC-Dim2L-SM-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "00B9" => {name=>"HM-LC-Dim1T-CV-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00BA" => {name=>"HM-LC-Dim1T-FM-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:1,Sw1_V:2:3",},
  "00BB" => {name=>"HM-LC-Dim2T-SM-2"        ,st=>'dimmer'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:2,Sw1_V:3:4,Sw2_V:5:6",},#
  "00BD" => {name=>"HM-CC-RT-DN-BoM"         ,st=>'thermostat'        ,cyc=>'00:10' ,rxt=>'c:w:f'  ,lst=>'p:1p.2p.5p.6p,3:3p.6p,1,7:4'                                                                                                                        
                                                                                                                        ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3,ClimRT_tr:4:4,ClimaTeam:5:5,remote:6:6"}, #
  "8001" => {name=>"PS-switch"               ,st=>'switch'            ,cyc=>''      ,rxt=>''       ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "8002" => {name=>"PS-Th-Sens"              ,st=>'THSensor'          ,cyc=>''      ,rxt=>''       ,lst=>'1,4'          ,chn=>"Sen:1:4",},
  #263 167                        HM Smoke Detector Schueco 
  #"HM-RC-Key4-2"
  #"HM-RC-Sec4-2"
  
);



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
  MaxTimeF        =>{a=> 29.0,s=>1.0,l=>3,min=>0  ,max=>25.4    ,c=>''         ,f=>10      ,u=>'s'   ,d=>0,t=>"max time first direction"},
  DriveMode       =>{a=> 31.0,s=>1.0,l=>3,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{direct=>0,viaUpperEnd=>1,viaLowerEnd=>2,viaNextEnd=>3}},
#dimmer mainly                                                                                 
  OnDly           =>{a=>  6.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on delay"},
  OnTime          =>{a=>  7.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on time, 111600 = infinite"},
  OffDly          =>{a=>  8.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off delay"},
  OffTime         =>{a=>  9.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off time, 111600 = infinite"},

  ActionTypeDim   =>{a=> 10.0,s=>0.4,l=>3,min=>0  ,max=>8       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
  OffDlyBlink     =>{a=> 14.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{off=>0,on=>1}},
  OnLvlPrio       =>{a=> 14.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{high=>0,low=>1}},
  OnDlyMode       =>{a=> 14.7,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{setToOff=>0,NoChange=>1}},
  OffLevel        =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"PowerLevel off"},
  OnMinLevel      =>{a=> 16.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"minimum PowerLevel"},
  OnLevel         =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>1,t=>"PowerLevel on"},

  OffLevelKm      =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnLevelKm       =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  RampOnSp        =>{a=> 34.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>''         ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp on speed"},
  RampOffSp       =>{a=> 35.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>''         ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp off speed"},

  RampSstep       =>{a=> 18.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"rampStartStep"},
  RampOnTime      =>{a=> 19.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOnTime"},
  RampOffTime     =>{a=> 20.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOffTime"},
  DimMinLvl       =>{a=> 21.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMinLevel"},
  DimMaxLvl       =>{a=> 22.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMaxLevel"},
  DimStep         =>{a=> 23.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>0,t=>"dimStep"},

  OffDlyNewTime   =>{a=> 25.0,s=>1.0,l=>3,min=>0.1,max=>25.6    ,c=>''         ,f=>10      ,u=>'s'   ,d=>0,t=>"off delay new time"},
  OffDlyOldTime   =>{a=> 26.0,s=>1.0,l=>3,min=>0.1,max=>25.6    ,c=>''         ,f=>10      ,u=>'s'   ,d=>0,t=>"off delay old time"},
  DimElsOffTimeMd =>{a=> 38.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{absolut=>0,minimal=>1}},
  DimElsOnTimeMd  =>{a=> 38.7,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{absolut=>0,minimal=>1}},
  DimElsActionType=>{a=> 38.0,s=>0.4,l=>3,min=>0  ,max=>8       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3,upDim=>4,downDim=>5,toggelDim=>6,toggelDimToCnt=>7,toggelDimToCntInv=>8}},
#output Unit                                                                                       
  ActTypeMp3      =>{a=> 36  ,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Tone or MP3 to be played"},
  ActTypeLed      =>{a=> 36  ,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED color"          ,lit=>{no=>0x00,red_short=>0x11,red_long=>0x12,green_short=>0x21,green_long=>0x22,orange_short=>0x31,orange_long=>0x32}},
  ActTypeOuCf     =>{a=> 36  ,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"type sound or LED"  ,lit=>{no=>0,short=>1,long=>2}},
  ActNum          =>{a=> 37  ,s=>1  ,l=>3,min=>1  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Number of repetitions"},
  Intense         =>{a=> 43  ,s=>1  ,l=>3,min=>10 ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Volume",lit=>{vol_100=>255,vol_90=>250,vol_80=>246,vol_70=>240,vol_60=>234,vol_50=>227,vol_40=>218,vol_30=>207,vol_20=>190,vol_10=>162,vol_00=>10}},  
# statemachines
  BlJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from on"      ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOn      =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOff     =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOn       =>{a=> 30.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOn"   ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOff      =>{a=> 30.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOff"  ,lit=>{no=>0,dlyOn=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  
  DimJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from on"      ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtDlyOn      =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtDlyOff     =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},

  DimElsJtOn      =>{a=> 39.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from on"      ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtOff     =>{a=> 39.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from off"     ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtDlyOn   =>{a=> 40.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtDlyOff  =>{a=> 40.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from delayOff",lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtRampOn  =>{a=> 41.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOn"  ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  DimElsJtRampOff =>{a=> 41.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"else Jump from rampOff" ,lit=>{no=>0,dlyOn=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,off=>6}},
  
  ttJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from on"      ,lit=>{no=>0,on=>2,off=>5}},
  ttJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,on=>2,off=>5}},

  SwJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from on"      ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,dlyOn=>1,on=>3,dlyOff=>4,off=>6}},

  KeyJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from on"      ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,unLock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},
  KeyJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,dlyUnlock=>1,rampUnlock=>2,unLock=>3,dlyLock=>4,rampLock=>5,lock=>6,open=>8}},

  WinJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  WinJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from off"     ,lit=>{no=>0,rampOnDly=>1,rampOn=>2,on=>3,rampOffDly=>4,rampOff=>5,off=>6,rampOnFast=>8,rampOffFast=>9}},
  
  CtRampOn        =>{a=>  1.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOn"   ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRampOff       =>{a=>  1.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOff"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOn         =>{a=>  2.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOn"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtDlyOff        =>{a=>  2.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOff" ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOn            =>{a=>  3.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from on"       ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtOff           =>{a=>  3.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from off"      ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtValLo         =>{a=>  4.0,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Condition value low for CT table"  },
  CtValHi         =>{a=>  5.0,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Condition value high for CT table" },
  CtRefOn         =>{a=> 28.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOn"    ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},
  CtRefOff        =>{a=> 28.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from refOff"   ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,between=>4,outside=>5}},

  CtrlRc          =>{a=> 46  ,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"set mode and/or temperature"   ,lit=>{no=>0,tempOnly=>1,auto=>2,autoAndTemp=>3,manuAndTemp=>4,boost=>5,toggle=>6}},
  TempRC          =>{a=> 45  ,s=>0.6,l=>3,min=>5  ,max=>30      ,c=>''         ,f=>2       ,u=>'C'   ,d=>0,t=>"temperature repated to CtrlRc reg"},
);

my %culHmRegDefine = (
#--- list 0, device  and protocol level-----------------
  burstRx         =>{a=>  1.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>'device reacts on Burst'        ,lit=>{off=>0,on=>1}},
  intKeyVisib     =>{a=>  2.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>'visibility of internal channel',lit=>{invisib=>0,visib=>1}},
  pairCentral     =>{a=> 10.0,s=>3.0,l=>0,min=>0  ,max=>16777215,c=>'hex'      ,f=>''      ,u=>''    ,d=>1,t=>'pairing to central'},
#remote mainly                                                                                      
  backlOnTime     =>{a=>  5.0,s=>0.6,l=>0,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Backlight ontime[s]"     ,lit=>{0=>0,5=>1,10=>2,15=>3,20=>4,25=>5}},
  backlOnMode     =>{a=>  5.6,s=>0.2,l=>0,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Backlight mode"          ,lit=>{off=>0,auto=>2}},
  ledMode         =>{a=>  5.6,s=>0.2,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED mode"                ,lit=>{off=>0,on=>1}},
  language        =>{a=>  7.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Language"                ,lit=>{English=>0,German=>1}},
  backAtKey       =>{a=> 13.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at keystroke"  ,lit=>{off=>0,on=>1}},
  backAtMotion    =>{a=> 13.6,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at motion"     ,lit=>{off=>0,on=>1}},
  backAtCharge    =>{a=> 13.5,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at Charge"     ,lit=>{off=>0,on=>1}},
  stbyTime        =>{a=> 14.0,s=>1.0,l=>0,min=>1  ,max=>99      ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Standby Time"},          
  backOnTime      =>{a=> 14.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Backlight On Time"},     
  btnLock         =>{a=> 15.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Button Lock"             ,lit=>{unlock=>0,lock=>1}},
                                                                                                                                       
# keymatic/winmatic secific register                                                                                                    
  keypressSignal  =>{a=>  3.0,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Keypress beep"           ,lit=>{off=>0,on=>1}},
  signal          =>{a=>  3.4,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Confirmation beep"       ,lit=>{off=>0,on=>1}},
  signalTone      =>{a=>  3.6,s=>0.2,l=>0,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""                        ,lit=>{low=>0,mid=>1,high=>2,veryHigh=>3}},

  brightness      =>{a=>  4.0,s=>0.4,l=>0,min=>0  ,max=>15      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Display brightness"},
  energyOpt       =>{a=>  8.0,s=>1.0,l=>0,min=>0  ,max=>127     ,c=>''         ,f=>2       ,u=>'s'   ,d=>1,t=>"energy Option: Duration of ilumination"},
# sec_mdir                                                                                   
  cyclicInfoMsg   =>{a=>  9.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"cyclic message"          ,lit=>{off=>0,on=>1}},
  sabotageMsg     =>{a=> 16.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"enable sabotage message" ,lit=>{off=>0,on=>1}},
  cyclicInfoMsgDis=>{a=> 17.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"cyclic message"},
  lowBatLimit     =>{a=> 18.0,s=>1.0,l=>0,min=>10 ,max=>12      ,c=>''         ,f=>10      ,u=>'V'   ,d=>1,t=>"low batterie limit, step .1V"},
  lowBatLimitBA   =>{a=> 18.0,s=>1.0,l=>0,min=>5  ,max=>15      ,c=>''         ,f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitFS   =>{a=> 18.0,s=>1.0,l=>0,min=>2  ,max=>3       ,c=>''         ,f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  lowBatLimitRT   =>{a=> 18.0,s=>1.0,l=>0,min=>2  ,max=>2.5     ,c=>''         ,f=>10      ,u=>'V'   ,d=>0,t=>"low batterie limit, step .1V"},
  batDefectLimit  =>{a=> 19.0,s=>1.0,l=>0,min=>0.1,max=>2       ,c=>''         ,f=>100     ,u=>'Ohm' ,d=>1,t=>"batterie defect detection"},
  transmDevTryMax =>{a=> 20.0,s=>1.0,l=>0,min=>1  ,max=>10      ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"max message re-transmit"},
  confBtnTime     =>{a=> 21.0,s=>1.0,l=>0,min=>1  ,max=>255     ,c=>''         ,f=>''      ,u=>'min' ,d=>0,t=>"255=permanent"},         
#repeater                                                                                      
  compMode        =>{a=> 23.0,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"compatibility moden"     ,lit=>{off=>0,on=>1}},
  localResDis     =>{a=> 24.0,s=>1.0,l=>0,min=>1  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"local reset disable"     ,lit=>{off=>0,on=>1}},
  globalBtnLock   =>{a=> 25.0,s=>1.0,l=>0,min=>1  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"global button lock"      ,lit=>{off=>0,on=>200}},
  modusBtnLock    =>{a=> 26.0,s=>1.0,l=>0,min=>1  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"mode button lock"        ,lit=>{off=>0,on=>200}},
  paramSel        =>{a=> 27.0,s=>1.0,l=>0,min=>0  ,max=>4       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"data transfered to peer" ,lit=>{off=>0,T1=>1,T2=>2,T1_T2=>3,T2_T1=>4}},
  RS485IdleTime   =>{a=> 29.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>'s'   ,d=>0,t=>"Idle Time"},
#un-identified List0
# addr Dec!!
# SEC-WM55 02:01 (AES on?)
# CC-RT    02:01 16:00
# SEC-WDS  02:01 16:01(sabotage) ?
# HM-SEC-MDIR  02:01 ?
# SEC-SC   02:00 ?
# Blind          9:00 10:00 20:00
# BL1TPBU  02:01 21:FF
# Dim1TPBU 02:01 21:FF 22:00
#Keymatic 3.3 unknown, seen 1 here

#--- list 1, Channel level------------------
#blindActuator mainly                                                                             
  sign            =>{a=>  8.0,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"signature (AES)",lit=>{off=>0,on=>1}},

  driveDown       =>{a=> 11.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>''         ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveUp         =>{a=> 13.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>''         ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveTurn       =>{a=> 15.0,s=>1.0,l=>1,min=>0.5,max=>25.5    ,c=>''         ,f=>10      ,u=>'s'   ,d=>1,t=>"engine uncharge - fhem min = 0.5s for protection. HM min= 0s (use regBulk if necessary)"},
  refRunCounter   =>{a=> 16.0,s=>1.0,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"reference run counter"},
#remote mainly                                                                                      
  longPress       =>{a=>  4.4,s=>0.4,l=>1,min=>0.3,max=>1.8     ,c=>'m10s3'    ,f=>''      ,u=>'s'   ,d=>0,t=>"time to detect key long press"},
  dblPress        =>{a=>  9.0,s=>0.4,l=>1,min=>0  ,max=>1.5     ,c=>''         ,f=>10      ,u=>'s'   ,d=>0,t=>"time to detect double press"},
  msgShowTime     =>{a=> 45.0,s=>1.0,l=>1,min=>0.0,max=>120     ,c=>''         ,f=>2       ,u=>'s'   ,d=>1,t=>"Message show time(RC19). 0=always on"},
  beepAtAlarm     =>{a=> 46.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Alarm"        ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtService   =>{a=> 46.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Service"      ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtInfo      =>{a=> 46.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Info"         ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  backlAtAlarm    =>{a=> 47.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Alarm"   ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtService  =>{a=> 47.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Service" ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtInfo     =>{a=> 47.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Info"    ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},

#dimmer  mainly                                                                                  
  loadErrCalib	  =>{a=> 18.0,s=>1.0,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>""    ,d=>0,t=>"Load Error Calibration"},
  transmitTryMax  =>{a=> 48.0,s=>1.0,l=>1,min=>1  ,max=>10      ,c=>''         ,f=>''      ,u=>""    ,d=>0,t=>"max message re-transmit"},
  loadAppearBehav =>{a=> 49.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>"behavior on load appearence at restart",lit=>{off=>0,last=>1,btnPress=>2,btnPressIfWasOn=>3}},
  ovrTempLvl      =>{a=> 50.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>0,t=>"overtemperatur level"},
  fuseDelay		  =>{a=> 51.0,s=>1.0,l=>1,min=>0  ,max=>2.55    ,c=>''         ,f=>100     ,u=>"s"   ,d=>0,t=>"fuse delay"},
  redTempLvl      =>{a=> 52.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>0,t=>"reduced temperatur recover"},
  redLvl          =>{a=> 53.0,s=>1.0,l=>1,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>"%"   ,d=>0,t=>"reduced power level"},
  powerUpAction	  =>{a=> 86.0,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>"behavior on power up"                  ,lit=>{off=>0,on=>1}},
  statusInfoMinDly=>{a=> 87.0,s=>0.5,l=>1,min=>0.5,max=>15.5    ,c=>''         ,f=>2       ,u=>"s"   ,d=>0,t=>"status message min delay"},
  statusInfoRandom=>{a=> 87.5,s=>0.3,l=>1,min=>0  ,max=>7       ,c=>''         ,f=>''      ,u=>"s"   ,d=>0,t=>"status message random delay"},
  characteristic  =>{a=> 88.0,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>""    ,d=>1,t=>""                                      ,lit=>{linear=>0,square=>1}},
  logicCombination=>{a=> 89.0,s=>0.5,l=>1,min=>0  ,max=>16      ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""             ,lit=>{inactive=>0,or=>1,and=>2,xor=>3,nor=>4,nand=>5,orinv=>6,andinv=>7,plus=>8,minus=>9,mul=>10,plusinv=>11,minusinv=>12,mulinv=>13,invPlus=>14,invMinus=>15,invMul=>16}},
#SCD                                                                                  
  msgScdPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,lvlNormal=>1}},
  msgScdPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position C",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
  msgScdPosD      =>{a=> 32.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position D",lit=>{noMsg=>0,lvlNormal=>1,lvlAddStrong=>2,lvlAdd=>3}},
#wds - different literals
  msgWdsPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,dry=>1}},
  msgWdsPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,dry=>1,water=>2,wet=>3}},
  msgWdsPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position C",lit=>{noMsg=>0,       water=>2,wet=>3}},
#rhs - different literals
  msgRhsPosA      =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosB      =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
  msgRhsPosC      =>{a=> 32.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position C",lit=>{noMsg=>0,closed=>1,open=>2,tilted=>3}},
#SC - different literals
  msgScPosA       =>{a=> 32.6,s=>0.2,l=>1,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position A",lit=>{noMsg=>0,closed=>1,open=>2}},
  msgScPosB       =>{a=> 32.4,s=>0.2,l=>1,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Message for position B",lit=>{noMsg=>0,closed=>1,open=>2}},
# keymatic/winmatic secific register                                                                     
  holdTime        =>{a=> 20  ,s=>1,  l=>1,min=>0  ,max=>8.16    ,c=>''         ,f=>31.25   ,u=>'s'   ,d=>0,t=>"Holdtime for door opening"},
  holdPWM         =>{a=> 21  ,s=>1,  l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Holdtime pulse wide modulation"},
  setupDir        =>{a=> 22  ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Rotation direction for locking",lit=>{right=>0,left=>1}},
  setupPosition   =>{a=> 23  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Rotation angle neutral position"},
  angelOpen       =>{a=> 24  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Door opening angle"},
  angelMax        =>{a=> 25  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle maximum"},
  angelLocked     =>{a=> 26  ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>0.06666 ,u=>'deg' ,d=>1,t=>"Angle Locked position"},
  pullForce       =>{a=> 28  ,s=>1  ,l=>1,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>1,t=>"pull force level"},
  pushForce       =>{a=> 29  ,s=>1  ,l=>1,min=>0  ,max=>100     ,c=>''         ,f=>2       ,u=>'%'   ,d=>1,t=>"push force level"},
  tiltMax         =>{a=> 30  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"maximum tilt level"},
  ledFlashUnlocked=>{a=> 31.3,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when not locked",lit=>{off=>0,on=>1}},
  ledFlashLocked  =>{a=> 31.6,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when locked"    ,lit=>{off=>0,on=>1}},

  waterUppThr     =>{a=>  6.0,s=>1  ,l=>1,min=>0  ,max=>256     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"water upper threshold"},
  waterlowThr     =>{a=>  7.0,s=>1  ,l=>1,min=>0  ,max=>256     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"water lower threshold"},
  caseDesign      =>{a=> 90.0,s=>1  ,l=>1,min=>1  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"case desing"               ,lit=>{verticalBarrel=>1,horizBarrel=>2,rectangle=>3}},
  caseHigh        =>{a=> 94.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case hight"},
  fillLevel       =>{a=> 98.0,s=>2  ,l=>1,min=>100,max=>300     ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"fill level"},
  caseWidth       =>{a=>102.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case width"},
  caseLength      =>{a=>106.0,s=>2  ,l=>1,min=>100,max=>10000   ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>"case length"},
  meaLength       =>{a=>108.0,s=>2  ,l=>1,min=>110,max=>310     ,c=>''         ,f=>''      ,u=>'cm'  ,d=>1,t=>""},
  useCustom       =>{a=>110.0,s=>1  ,l=>1,min=>110,max=>310     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"use custom"      ,lit=>{off=>0,on=>1}},

  averaging       =>{a=>122.0,s=>1  ,l=>1,min=>1    ,max=>16      ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"averaging period"},
  txMinDly        =>{a=>123.0,s=>0.7,l=>1,min=>0    ,max=>16      ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"min transmit delay"},
  txThrPwr        =>{a=>124.0,s=>3  ,l=>1,min=>0.01 ,max=>3680    ,c=>''         ,f=>100     ,u=>'W'   ,d=>1,t=>"threshold power"},
  txThrCur        =>{a=>127.0,s=>2  ,l=>1,min=>1    ,max=>16000   ,c=>''         ,f=>''      ,u=>'mA'  ,d=>1,t=>"threshold current"},
  txThrVlt        =>{a=>129.0,s=>2  ,l=>1,min=>0.1  ,max=>230     ,c=>''         ,f=>10      ,u=>'V'   ,d=>1,t=>"threshold voltage"},
  txThrFrq        =>{a=>131.0,s=>1  ,l=>1,min=>0.01 ,max=>2.55    ,c=>''         ,f=>100     ,u=>'Hz'  ,d=>1,t=>"threshold frequency"},

  txThrLoPwr      =>{a=>135.0,s=>4  ,l=>1,min=>0    ,max=>3680    ,c=>''         ,f=>'100'   ,u=>'W'   ,d=>1,t=>"threshold low power"},
  txThrHiPwr      =>{a=>139.0,s=>4  ,l=>1,min=>0    ,max=>3680    ,c=>''         ,f=>'100'   ,u=>'W'   ,d=>1,t=>"threshold high power"},
  txThrLoCur      =>{a=>135.0,s=>4  ,l=>1,min=>0    ,max=>16000   ,c=>''         ,f=>'100'   ,u=>'mA'  ,d=>1,t=>"threshold low current"},
  txThrHiCur      =>{a=>139.0,s=>4  ,l=>1,min=>0    ,max=>16000   ,c=>''         ,f=>'100'   ,u=>'mA'  ,d=>1,t=>"threshold high current"},
  txThrLoVlt      =>{a=>135.0,s=>4  ,l=>1,min=>115  ,max=>255     ,c=>''         ,f=>'100'   ,u=>'V'   ,d=>1,t=>"threshold low voltage"},
  txThrHiVlt      =>{a=>139.0,s=>4  ,l=>1,min=>115  ,max=>255     ,c=>''         ,f=>'100'   ,u=>'V'   ,d=>1,t=>"threshold high voltage"},
  txThrLoFrq      =>{a=>135.0,s=>4  ,l=>1,min=>48.72,max=>51.27   ,c=>''         ,f=>'100'   ,u=>'Hz'  ,d=>1,t=>"threshold low frequency"},
  txThrHiFrq      =>{a=>139.0,s=>4  ,l=>1,min=>48.72,max=>51.27   ,c=>''         ,f=>'100'   ,u=>'Hz'  ,d=>1,t=>"threshold high frequency"},

  evtFltrPeriod   =>{a=>  1.0,s=>0.4,l=>1,min=>0.5,max=>7.5     ,c=>''         ,f=>2       ,u=>'s'   ,d=>1,t=>"event filter period"},
  evtFltrNum      =>{a=>  1.4,s=>0.4,l=>1,min=>1  ,max=>15      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"sensitivity - read each n-th puls"},
  minInterval     =>{a=>  2.0,s=>0.3,l=>1,min=>0  ,max=>4       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"minimum interval in sec"   ,lit=>{15=>0,30=>1,60=>2,120=>3,240=>4}},
  captInInterval  =>{a=>  2.3,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"capture within interval"   ,lit=>{off=>0,on=>1}},
  brightFilter    =>{a=>  2.4,s=>0.4,l=>1,min=>0  ,max=>7       ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"brightness filter - ignore light at night"},
  eventDlyTime    =>{a=> 33  ,s=>1  ,l=>1,min=>0  ,max=>7620    ,c=>'fltCvT60' ,f=>''      ,u=>'s'   ,d=>1,t=>"event delay time"},
  ledOnTime       =>{a=> 34  ,s=>1  ,l=>1,min=>0  ,max=>1.275   ,c=>''         ,f=>200     ,u=>'s'   ,d=>0,t=>"LED ontime"},
  eventFilterTime =>{a=> 35  ,s=>1  ,l=>1,min=>0  ,max=>7620    ,c=>'fltCvT60' ,f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},
  eventFilterTimeB=>{a=> 35  ,s=>1  ,l=>1,min=>5  ,max=>7620    ,c=>'fltCvT60' ,f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},
# - different range
  evtFltrTime     =>{a=> 35.0,s=>1  ,l=>1,min=>600,max=>1200    ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"event filter time"},

# weather units                                                                                  
  sunThresh       =>{a=>  5  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Sunshine threshold"},
  stormUpThresh   =>{a=>  6  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm upper threshold"},
  stormLowThresh  =>{a=>  7  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm lower threshold"},
# others
  localResetDis   =>{a=>  7  ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"LocalReset disable",lit=>{off=>0,on=>1}},

  condTxThrhHi    =>{a=>135  ,s=>2  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>''      ,u=>'mV'  ,d=>0,t=>"threshold high condition"},
  condTxThrhHi    =>{a=>139  ,s=>2  ,l=>1,min=>0  ,max=>3000    ,c=>''         ,f=>''      ,u=>'mV'  ,d=>0,t=>"threshold high condition"},
  highHoldTime    =>{a=>143  ,s=>1  ,l=>1,min=>60 ,max=>7620    ,c=>'fltCvT60' ,f=>''      ,u=>'s'   ,d=>0,t=>"hold time on high state"},
  evntRelFltTime  =>{a=>145  ,s=>1  ,l=>1,min=>1  ,max=>7620    ,c=>'fltCvT60' ,f=>''      ,u=>'s'   ,d=>0,t=>"event filter release time "},

  #un-identified List1
# SEC-WM55 08:01 (AES on?)
# SEC-WDS  34:0x64 ?
# SEC-SC   08:00 ?
# RC19     08:00 ? RC19 Button 08:08
# Bl1PBU   08:00 09:00 10:00


#  logicCombination=>{a=> 89.0,s=>0.5,l=>1,min=>0  ,max=>16      ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"".
#		                                                                                                      "inactive=>unused\n".
#                                                                                                             "or      =>max(state,chan)\n".
#					                                                                                          "and     =>min(state,chan)\n".
#					                                                                                          "xor     =>0 if both are != 0, else max\n".
#					                                                                                          "nor     =>100-max(state,chan)\n".
#					                                                                                          "nand    =>100-min(state,chan)\n".
#					                                                                                          "orinv   =>max((100-chn),state)\n".
#					                                                                                          "andinv  =>min((100-chn),state)\n".
#					                                                                                          "plus    =>state + chan\n".
#					                                                                                          "minus   =>state - chan\n".
#					                                                                                          "mul     =>state * chan\n".
#					                                                                                          "plusinv =>state + 100 - chan\n".
#					                                                                                          "minusinv=>state - 100 + chan\n".
#					                                                                                          "mulinv  =>state * (100 - chan)\n".
#					                                                                                          "invPlus =>100 - state - chan\n".
#					                                                                                          "invMinus=>100 - state + chan\n".
#					                                                                                          "invMul  =>100 - state * chan\n",lit=>{inactive=>0,or=>1,and=>2,xor=>3,nor=>4,nand=>5,orinv=>6,andinv=>7,plus=>8,minus=>9,mul=>10,plusinv=>11,minusinv=>12,mulinv=>13,invPlus=>14,invMinus=>15,invMul=>16}},
#
#					  
#CC-TC                                                                                        

#--- list 3, link level for actor - mainly in short/long hash, only specials here------------------
  lgMultiExec     =>{a=>138.5,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"multiple execution per repeat of long trigger"    ,lit=>{off=>0,on=>1}},

#--- list 4, link level for Button ------------------                                                                                     
  peerNeedsBurst  =>{a=>  1.0,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"peer expects burst",lit=>{off=>0,on=>1}},
  expectAES       =>{a=>  1.7,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"expect AES"        ,lit=>{off=>0,on=>1}},
  lcdSymb         =>{a=>  2.0,s=>0.1,l=>4,min=>0  ,max=>8       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"symbol to display on message",lit=>{"none"=>0,"bulb"=>1,"switch"=>2,"window"=>3,"door"=>4,"blind"=>5,"scene"=>6,"phone"=>7,"bell"=>8}},
  lcdLvlInterp    =>{a=>  3.0,s=>0.1,l=>4,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"bitmask for symbols",lit=>{"none"=>0,"light"=>1,"blind"=>2,"marquee"=>3,"door"=>4,"window"=>5}},

  fillLvlUpThr    =>{a=>  4.0,s=>1  ,l=>4,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"fill level upper threshold"},
  fillLvlLoThr    =>{a=>  5.0,s=>1  ,l=>4,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"fill level lower threshold"},

#--- list 5,6 parameter for channel ------------------
  displayMode     =>{a=>  1.0,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{"temp-only"=>0,"temp-hum"=>1}},
  displayTemp     =>{a=>  1.1,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{actual=>0,setpoint=>1}},
  displayTempUnit =>{a=>  1.2,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{celsius=>0,fahrenheit=>1}},
  controlMode     =>{a=>  1.3,s=>0.2,l=>5,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{manual=>0,auto=>1,central=>2,party=>3}},
  decalcDay       =>{a=>  1.5,s=>0.3,l=>5,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Decalc weekday"  ,lit=>{Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6}},
  mdTempValve     =>{a=>  2.6,s=>0.2,l=>5,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{auto=>0,close=>1,open=>2}},
  "day-temp"      =>{a=>  3  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>''         ,f=>2       ,u=>'C'   ,d=>1,t=>"comfort or day temperatur"},
  "night-temp"    =>{a=>  4  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>''         ,f=>2       ,u=>'C'   ,d=>1,t=>"lower or night temperatur"},
  tempWinOpen     =>{a=>  5  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>''         ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Win open !chan 3 only!"},
  "party-temp"    =>{a=>  6  ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>''         ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Party"},
  decalMin        =>{a=>  8  ,s=>0.3,l=>5,min=>0  ,max=>50      ,c=>''         ,f=>0.1     ,u=>'min' ,d=>1,t=>"Decalc min"},
  decalHr         =>{a=>  8.3,s=>0.5,l=>5,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Decalc hour"},

  partyEndHr      =>{a=> 97  ,s=>0.6,l=>6,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Party end hour. Use cmd partyMode to set"},
  partyEndMin     =>{a=> 97.7,s=>0.1,l=>6,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>'min' ,d=>1,t=>"Party end min. Use cmd partyMode to set"   ,lit=>{"00"=>0,"30"=>1}},
  partyEndDay     =>{a=> 98  ,s=>1  ,l=>6,min=>0  ,max=>200     ,c=>''         ,f=>''      ,u=>'d'   ,d=>1,t=>"Party duration days. Use cmd partyMode to set"},
#Thermal-cc-VD                                                                                  
  valveOffset     =>{a=>  9  ,s=>0.5,l=>5,min=>0  ,max=>25      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve offset"},             # size actually 0.5
  valveErrorPos   =>{a=> 10  ,s=>1  ,l=>5,min=>0  ,max=>99      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve position when error"},# size actually 0.7

  dayTemp         =>{a=>  1  ,s=>0.6,l=>7,min=>15 ,max=>30      ,c=>''         ,f=>'2'     ,u=>'C'   ,d=>1,t=>"comfort or day temperatur"},
  nightTemp       =>{a=>  2  ,s=>0.6,l=>7,min=>5  ,max=>25      ,c=>''         ,f=>'2'     ,u=>'C'   ,d=>1,t=>"lower or night temperatur"},
  tempMin         =>{a=>  3  ,s=>0.6,l=>7,min=>4.5,max=>14.5    ,c=>''         ,f=>'2'     ,u=>'C'   ,d=>1,t=>"minimum temperatur"},
  tempMax         =>{a=>  4  ,s=>0.6,l=>7,min=>15 ,max=>30.5    ,c=>''         ,f=>'2'     ,u=>'C'   ,d=>1,t=>"maximum temperatur"},
  winOpnTemp      =>{a=>  5  ,s=>0.6,l=>7,min=>5  ,max=>30      ,c=>''         ,f=>'2'     ,u=>'C'   ,d=>1,t=>"lowering temp whenWindow is opened"},
  winOpnPeriod    =>{a=>  6  ,s=>0.4,l=>7,min=>0  ,max=>60      ,c=>''         ,f=>'0.2'   ,u=>'min' ,d=>1,t=>"period lowering when window is open"},
  decalcWeekday   =>{a=>  7  ,s=>0.3,l=>7,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"decalc at day"      ,lit=>{Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6}},
  decalcTime      =>{a=>  8  ,s=>0.6,l=>7,min=>0  ,max=>1410    ,c=>'min2time' ,f=>''      ,u=>''    ,d=>1,t=>"decalc at hour"},
  tempOffset      =>{a=>  9  ,s=>0.4,l=>7,min=>0  ,max=>15      ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"temperature offset",lit=>{"-3.5K"=>0,"-3.0K"=>1,"-2.5K"=>2,"-2.0K"=>3,"-1.5K"=>4,"-1.0K"=>5,"-0.5K"=>6, 
                                                                                                                                        "0.0K"=>7, "0.5K"=>8, "1.0K"=>9, "1.5K"=>10, "2.0K"=>11, "2.5K"=>12, "3.0K"=>13, "3.5K"=>14}},
  btnNoBckLight   =>{a=>  9.4,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"button response without backlight",lit=>{off=>0,on=>1}},
  showSetTemp     =>{a=>  9.5,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"show set or actual temperature"   ,lit=>{actTemp=>0,setTemp=>1}},
  showHumitidy    =>{a=>  9.6,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"show temp only or also humidity"  ,lit=>{temp=>0,tempHum=>1}},
  sendWeatherData =>{a=>  9.7,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"send  weather data"               ,lit=>{off=>0,on=>1}},

  boostPos        =>{a=> 10.0,s=>0.5,l=>7,min=>0  ,max=>100     ,c=>''         ,f=>'0.2'   ,u=>'%'   ,d=>1,t=>"valve boost position"},
  boostPeriod     =>{a=> 10.5,s=>0.3,l=>7,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>'min' ,d=>1,t=>"boost period [min]"                          ,lit=>{0=>0,5=>1,10=>2,15=>3,20=>4,25=>5,30=>6}},
  valveOffset     =>{a=> 11  ,s=>0.7,l=>7,min=>0  ,max=>100     ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"offset for valve"},
  valveMaxPos     =>{a=> 12  ,s=>0.7,l=>7,min=>0  ,max=>100     ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"valve maximum position"},
  valveErrPos     =>{a=> 13  ,s=>0.7,l=>7,min=>0  ,max=>100     ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"valve error position"},
                                    
  daylightSaveTime=>{a=> 14  ,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"set daylight saving time"                    ,lit=>{off=>0,on=>1}},
  regAdaptive     =>{a=> 14.1,s=>0.2,l=>7,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"adaptive regulation: offDef, offdetrmine, on",lit=>{off=>0,offDeter=>1,on=>2}},
  showInfo        =>{a=> 14.3,s=>0.2,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"show date or time"                           ,lit=>{time=>0,date=>1}},
  winOpnBoost     =>{a=> 14.5,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"boost after window closed"                   ,lit=>{off=>0,on=>1}},
  noMinMax4Manu   =>{a=> 14.6,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"min/max is irrelevant for manual mode"       ,lit=>{off=>0,on=>1}},
  showWeekday     =>{a=> 14.7,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"show weekday"                                ,lit=>{off=>0,on=>1}},

  hyst2point      =>{a=> 15.0,s=>0.5,l=>7,min=>0  ,max=>2       ,c=>''         ,f=>'10'    ,u=>'C'   ,d=>1,t=>"hysteresis range",},
  heatCool        =>{a=> 15.7,s=>0.1,l=>7,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"select heating or cooling"                   ,lit=>{heating=>0,cooling=>1}},
  weekPrgSel      =>{a=> 16.0,s=>1.0,l=>7,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"select week program"                         ,lit=>{prog1=>0,prog2=>1,prog1=>2}},

  modePrioParty   =>{a=> 18.0,s=>0.3,l=>7,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"allow tempChange for party only by..."            ,lit=>{RT_TC_SC_SELF=>0,all=>1,RT_TC_CCU_SELF=>2,CCU=>3,self=>4}},
  modePrioManu    =>{a=> 18.3,s=>0.3,l=>7,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"allow tempChange for manual only by..."           ,lit=>{RT_TC_SC_SELF=>0,all=>1,RT_TC_CCU_SELF=>2,CCU=>3,self=>4}},

  winOpnMode      =>{a=> 19.5,s=>0.3,l=>7,min=>0  ,max=>4       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"enable internal Windoe open in modes: "      ,lit=>{off=>0,auto=>1,auto_manu=>2,auto_party=>3,on=>4}},
  winOpnDetFall   =>{a=> 19.0,s=>0.5,l=>7,min=>0.5,max=>2.5     ,c=>''         ,f=>'10'    ,u=>'K'   ,d=>1,t=>"detect Window Open if temp falls more then..."},
                                    
  reguIntI        =>{a=>202.0,s=>1  ,l=>7,min=>10 ,max=>20      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator I-param internal mode"},
  reguIntP        =>{a=>203.0,s=>1  ,l=>7,min=>25 ,max=>35      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator P-param internal mode"},
  reguIntPstart   =>{a=>204.0,s=>1  ,l=>7,min=>5  ,max=>45      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator P-param internal mode start value"},
  reguExtI        =>{a=>205.0,s=>1  ,l=>7,min=>10 ,max=>20      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator I-param extern mode"},
  reguExtP        =>{a=>206.0,s=>1  ,l=>7,min=>25 ,max=>35      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator P-param extern mode"},
  reguExtPstart   =>{a=>207.0,s=>1  ,l=>7,min=>5  ,max=>45      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"regulator P-param extern mode start value"},
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

my %culHmRegGeneral = (
  pairCentral=>1,
);
my %culHmRegType = (
  swi                 =>{ peerNeedsBurst  =>1,expectAES       =>1},
  remote              =>{ peerNeedsBurst  =>1,expectAES       =>1,dblPress        =>1,longPress       =>1
					     ,sign            =>1
                        },
  blindActuator       =>{ intKeyVisib     =>1
                         ,driveUp         =>1,driveDown       =>1,driveTurn       =>1,refRunCounter   =>1
                         ,sign            =>1
                         ,MaxTimeF        =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
  	   		             ,OffLevel        =>1,OnLevel         =>1
                         ,ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1,DriveMode       =>1
				         ,BlJtOn          =>1,BlJtOff         =>1,BlJtDlyOn       =>1,BlJtDlyOff      =>1
                         ,BlJtRampOn      =>1,BlJtRampOff     =>1,BlJtRefOn       =>1,BlJtRefOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,CtRefOn         =>1
				         ,CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,CtRefOff        =>1
				         ,lgMultiExec     =>1
				        },
  dimmer              =>{ intKeyVisib     =>1
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
		                 ,OffDlyNewTime   =>1,OffDlyOldTime   =>1
		                 ,lgMultiExec     =>1
		                },
  switch              =>{ intKeyVisib     =>1,sign            =>1
                         ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
		                 ,ActionType      =>1,OnTimeMode      =>1,OffTimeMode     =>1
 		                 ,lgMultiExec     =>1
		                },
  winMatic            =>{ signal          =>1,signalTone      =>1,keypressSignal  =>1},                                  
  keyMatic            =>{ signal          =>1,signalTone      =>1,keypressSignal  =>1
			             ,holdTime        =>1,holdPWM         =>1,setupDir        =>1,setupPosition   =>1
			             ,angelOpen       =>1,angelMax        =>1,angelLocked     =>1
			             ,ledFlashUnlocked=>1,ledFlashLocked  =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1
                         ,KeyJtOn         =>1,KeyJtOff        =>1
					     ,OnTime          =>1
			            },
  motionDetector      =>{ evtFltrPeriod   =>1,evtFltrNum      =>1,minInterval     =>1
			             ,captInInterval  =>1,brightFilter    =>1,ledOnTime       =>1
					     ,peerNeedsBurst  =>1
			            },
  threeStateSensor    =>{ cyclicInfoMsg   =>1,                    transmDevTryMax =>1
					     ,                                        transmitTryMax  =>1
                         ,peerNeedsBurst  =>1,expectAES       =>1
					    },
  sensRain            =>{ transmDevTryMax =>1,localResDis     =>1},
  tipTronic           =>{ cyclicInfoMsg   =>1,cyclicInfoMsgDis=>1,localResDis     =>1,RS485IdleTime   =>1},
  powerMeter          =>{ intKeyVisib     =>1},
                          
);
#clones - - - - - - - - - - - - - - -   
$culHmRegType{pushButton}     = $culHmRegType{remote};

my %culHmRegModel = (
  "HM-RC-12"          =>{ backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1},
  "HM-RC-19"          =>{ backAtKey       =>1, backAtMotion   =>1, backOnTime     =>1,backAtCharge    =>1,language =>1
                         ,lcdSymb         =>1, lcdLvlInterp   =>1
                        },
  "HM-RC-4-2"         =>{ localResDis     =>1},
 
  "HM-LC-Bl1PBU-FM"   =>{ transmitTryMax  =>1,statusInfoMinDly=>1,statusInfoRandom=>1,localResDis     =>1},

  "HM-LC-Dim1L-Pl"    =>{ confBtnTime     =>1,loadAppearBehav =>1,loadErrCalib	   =>1},
  "HM-LC-Dim1L-CV-2"  =>{ confBtnTime     =>1,loadAppearBehav =>1,loadErrCalib	   =>1
		                 ,logicCombination=>1
		                 ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
		                 ,DimElsActionType=>1
		                 ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
		                 ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1	
                        },
  "HM-LC-Dim1PWM-CV"  =>{ confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
		                 ,characteristic  =>1,localResDis     =>1
					     ,logicCombination=>1
		                 ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
		                 ,DimElsActionType=>1
		                 ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
		                 ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1	
                        },
  "HM-LC-Dim1T-Pl"    =>{ confBtnTime     =>1,ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,fuseDelay	      =>1
                       },
  "HM-LC-Dim1TPBU-FM" =>{                     ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1
                         ,fuseDelay	      =>1,localResDis     =>1
		                 ,logicCombination=>1
		                 ,DimElsOffTimeMd =>1,DimElsOnTimeMd  =>1
		                 ,DimElsActionType=>1
		                 ,DimElsJtOn      =>1,DimElsJtOff     =>1,DimElsJtDlyOn   =>1
		                 ,DimElsJtDlyOff  =>1,DimElsJtRampOn  =>1,DimElsJtRampOff =>1	
                        },

  "HM-CC-VD"          =>{ valveOffset     =>1,valveErrorPos   =>1},
  "HM-CC-TC"          =>{ burstRx         =>1,backlOnTime     =>1,backlOnMode     =>1,btnLock         =>1},
  "HM-CC-RT-DN"       =>{ btnLock         =>1,localResDis     =>1,globalBtnLock   =>1,modusBtnLock    =>1
                         ,cyclicInfoMsg   =>1,cyclicInfoMsgDis=>1
                         ,burstRx         =>1,lowBatLimitRT   =>1,backOnTime      =>1
					     ,sign            =>1
                        },
					  
  "HM-PB-4DIS-WM"     =>{ peerNeedsBurst  =>1,expectAES       =>1,language        =>1,stbyTime        =>1},
  "HM-WDS100-C6-O"    =>{ burstRx         =>1,sunThresh       =>1,stormUpThresh   =>1,stormLowThresh  =>1},
  "KS550"             =>{ stormUpThresh   =>1,stormLowThresh  =>1},
  "HM-OU-LED16"       =>{ brightness      =>1,energyOpt       =>1,localResDis     =>1},
  "HM-OU-CFM-PL"      =>{ localResetDis   =>1
  			             ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
			             ,OnTimeMode      =>1,OffTimeMode     =>1,
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
			             ,ActionType      =>1,ActNum          =>1,lgMultiExec     =>1},
  "HM-OU-CF-PL"       =>{ ActTypeOuCf     =>1,ActNum          =>1},
  "HM-OU-CM-PCB"      =>{ localResetDis   =>1,
  			             ,OnTime          =>1,OffTime         =>1,OnDly           =>1,OffDly          =>1
			             ,OnTimeMode      =>1,OffTimeMode     =>1,
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtDlyOn         =>1,CtOff           =>1,CtDlyOff        =>1
			             ,ActionType      =>1
					     ,ActTypeMp3      =>1,ActNum          =>1,Intense         =>1,lgMultiExec     =>1},
  "HM-SEC-MDIR"       =>{                     sabotageMsg     =>1},
  "HM-CC-SCD"         =>{ peerNeedsBurst  =>1,expectAES       =>1
                         ,                                        transmitTryMax  =>1,evtFltrTime     =>1
                         ,msgScdPosA      =>1,msgScdPosB      =>1,msgScdPosC      =>1,msgScdPosD      =>1},
  "HM-SEC-RHS"        =>{ msgRhsPosA      =>1,msgRhsPosB      =>1,msgRhsPosC      =>1
                         ,                    ledOnTime       =>1,eventDlyTime    =>1},
  "HM-SEC-SC"         =>{                     sabotageMsg     =>1
                         ,msgScPosA       =>1,msgScPosB       =>1
					     ,                    ledOnTime       =>1,eventDlyTime    =>1},
  "HM-SCI-3-FM"       =>{ msgScPosA       =>1,msgScPosB       =>1
					     ,                                        eventDlyTime    =>1},
  "HM-SEC-TIS"        =>{                     sabotageMsg     =>1
                         ,msgScPosA       =>1,msgScPosB       =>1
					     ,                    ledOnTime       =>1,eventFilterTime =>1},
  "HM-SEC-WDS"        =>{ msgWdsPosA      =>1,msgWdsPosB      =>1,msgWdsPosC      =>1
					     ,                                        eventFilterTimeB=>1},
  "HM-SEC-SFA-SM"     =>{ cyclicInfoMsg   =>1,sabotageMsg     =>1,transmDevTryMax =>1
                         ,lowBatLimit     =>1,batDefectLimit  =>1
                         ,                                        transmitTryMax  =>1},
  "HM-Dis-TD-T"       =>{ lowBatLimitFS   =>1,ledMode         =>1},
  "HM-LC-SW1-BA-PCB"  =>{ lowBatLimitBA   =>1,ledMode         =>1},
  "HM-Sys-sRP-Pl"     =>{ compMode        =>1},
  "KFM-Display"       =>{ CtDlyOn         =>1,CtDlyOff        =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,ActionType      =>1,OffTimeMode     =>1,OnTimeMode      =>1
                         ,DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1,DimJtDlyOff     =>1
                         ,DimJtRampOn     =>1,DimJtRampOff    =>1
                         ,lgMultiExec     =>1
					      },
  "HM-Sen-Wa-Od"      =>{ cyclicInfoMsgDis=>1,                    transmDevTryMax =>1,localResDis     =>1
                         ,                    ledOnTime       =>1,transmitTryMax  =>1
                         ,waterUppThr     =>1,waterlowThr     =>1,caseDesign      =>1,caseHigh        =>1
                         ,fillLevel       =>1,caseWidth       =>1,caseLength      =>1,meaLength       =>1
                         ,useCustom       =>1,				   
                         ,fillLvlUpThr    =>1,fillLvlLoThr    =>1
                         ,expectAES       =>1,peerNeedsBurst  =>1},
  "HM-WDS10-TH-O"     =>{ burstRx         =>1},
  "HM-WDS30-OT2-SM"   =>{ burstRx         =>1,cyclicInfoMsgDis=>1,localResDis     =>1,paramSel        =>1},
  "HM-TC-IT-WM-W-EU"  =>{ burstRx         =>1,cyclicInfoMsgDis=>1,localResDis     =>1,cyclicInfoMsg   =>1
                         ,btnLock         =>1,globalBtnLock   =>1,modusBtnLock    =>1,lowBatLimitRT   =>1
					    },
  "HM-ES-PMSw1-Pl"    =>{ localResDis     =>1},
  );

#clones - - - - - - - - - - - - - - -   
$culHmRegModel{"HM-RC-12-B"}          = $culHmRegModel{"HM-RC-12"};
$culHmRegModel{"HM-RC-12-SW"}         = $culHmRegModel{"HM-RC-12"};
$culHmRegModel{"HM-RC-19-B"}          = $culHmRegModel{"HM-RC-19"};
$culHmRegModel{"HM-RC-19-SW"}         = $culHmRegModel{"HM-RC-19"};

$culHmRegModel{"KS550"}               = $culHmRegModel{"HM-WDS100-C6-O"};
$culHmRegModel{"KS550TECH"}           = $culHmRegModel{"HM-WDS100-C6-O"};
$culHmRegModel{"KS550LC"}             = $culHmRegModel{"HM-WDS100-C6-O"};
$culHmRegModel{"KS888"}               = $culHmRegModel{"HM-WDS100-C6-O"};
                                
$culHmRegModel{"HM-LC-Dim1L-Pl-2"}    = $culHmRegModel{"HM-LC-Dim1L-Pl"};#rf_d
$culHmRegModel{"HM-LC-Dim1L-CV"}      = $culHmRegModel{"HM-LC-Dim1L-Pl"};
$culHmRegModel{"Schueco-263-132"}     = $culHmRegModel{"HM-LC-Dim1L-Pl"};
$culHmRegModel{"HM-LC-Dim2L-CV"}      = $culHmRegModel{"HM-LC-Dim1L-Pl"};
$culHmRegModel{"HM-LC-Dim2L-SM"}      = $culHmRegModel{"HM-LC-Dim1L-Pl"};

$culHmRegModel{"HM-LC-Dim1L-Pl-644"}  = $culHmRegModel{"HM-LC-Dim1L-CV-2"};#RF_DIM_1l_644
$culHmRegModel{"HM-LC-Dim1L-CV-644"}  = $culHmRegModel{"HM-LC-Dim1L-CV-2"};
$culHmRegModel{"HM-LC-Dim1L-Pl-3"}    = $culHmRegModel{"HM-LC-Dim1L-CV-2"};

$culHmRegModel{"HM-LC-Dim1PWM-CV-2"}  = $culHmRegModel{"HM-LC-Dim1PWM-CV"};#rf_dim_1pwm_644

#rf_dim_1t_644

$culHmRegModel{"HM-LC-Dim1TPBU-FM-2"} = $culHmRegModel{"HM-LC-Dim1TPBU-FM"};#rf_dim_1tconf_644
$culHmRegModel{"Schueco-263-133"}     = $culHmRegModel{"HM-LC-Dim1TPBU-FM"};

#rf_dim_2l_644

$culHmRegModel{"HM-LC-Dim1T-CV"}      = $culHmRegModel{"HM-LC-Dim1T-Pl"};#rf_dim_t
$culHmRegModel{"HM-LC-Dim1T-FM"}      = $culHmRegModel{"HM-LC-Dim1T-Pl"};
$culHmRegModel{"HM-LC-Dim2T-SM"}      = $culHmRegModel{"HM-LC-Dim1T-Pl"};
$culHmRegModel{"HM-LC-Dim1T-Pl-2"}    = $culHmRegModel{"HM-LC-Dim1T-Pl"};
$culHmRegModel{"Schueco-263-134"}     = $culHmRegModel{"HM-LC-Dim1T-Pl"};
                                      
$culHmRegModel{"ASH550I"}             = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"ASH550"}              = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"Schueco_263-158"}     = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"HM-WDS20-TH-O"}       = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"HM-WDS40-TH-I"}       = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"Schueco_263-157"}     = $culHmRegModel{"HM-WDS10-TH-O"};
$culHmRegModel{"IS-WDS-TH-OD-S-R3"}   = $culHmRegModel{"HM-WDS10-TH-O"};
                                      
$culHmRegModel{"HM-LC-Sw1PBU-FM"}     = $culHmRegModel{"HM-LC-Bl1PBU-FM"};
                                      
$culHmRegModel{"HM-RC-Sec4-2"}        = $culHmRegModel{"HM-RC-4-2"};
$culHmRegModel{"HM-RC-Key4-2"}        = $culHmRegModel{"HM-RC-4-2"};
                                      
$culHmRegModel{"HM-LC-SW4-BA-PCB"}    = $culHmRegModel{"HM-LC-SW1-BA-PCB"};

$culHmRegModel{"HM-CC-RT-DN-BoM"}     = $culHmRegModel{"HM-CC-RT-DN"};

my %culHmRegChan = (# if channelspecific then enter them here 
  "HM-CC-TC02"        =>{ displayMode     =>1,displayTemp     =>1,displayTempUnit =>1
                         ,controlMode     =>1,decalcDay       =>1
                         ,"day-temp"      =>1,"night-temp"    =>1,"party-temp"    =>1
			             ,mdTempValve     =>1,partyEndDay     =>1
			             ,partyEndMin     =>1,partyEndHr      =>1
			             ,decalHr         =>1,decalMin        =>1
                         },    
  "HM-CC-TC03"        =>{ tempWinOpen     =>1 }, #window channel
  "HM-RC-1912"        =>{ msgShowTime     =>1, beepAtAlarm    =>1, beepAtService  =>1,beepAtInfo  =>1
                         ,backlAtAlarm    =>1, backlAtService =>1, backlAtInfo    =>1
						 },
  "HM-OU-CFM-PL01"    =>{ ActTypeLed      =>1},
  "HM-OU-CFM-PL02"    =>{ ActTypeMp3      =>1,Intense         =>1},
  "HM-SEC-WIN01"      =>{ setupDir        =>1,pullForce       =>1,pushForce       =>1,tiltMax         =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
			             ,WinJtOn         =>1,WinJtOff        =>1,WinJtRampOn     =>1,WinJtRampOff    =>1
                         ,OnTime          =>1,OffTime         =>1,OffLevelKm      =>1
                         ,OnLevelKm       =>1,OnRampOnSp      =>1,OnRampOffSp     =>1
                         },
  "WDF-solar01"       =>{ WinJtOn         =>1,WinJtOff        =>1,WinJtRampOn     =>1,WinJtRampOff    =>1
                         ,OffLevel        =>1,OnLevel         =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,CtOn            =>1,CtOff           =>1,CtRampOn        =>1,CtRampOff       =>1
						 ,OnRampOnSp      =>1,OnRampOffSp     =>1
						 ,OnTime          =>1,OffTime         =>1
					     },
  "Schueco_263-xxx01" =>{ statusInfoMinDly=>1,statusInfoRandom=>1,
                         ,#no long here!!!
                         ,shCtValLo       =>1,shCtValHi       =>1
                         ,shCtOn          =>1,shCtDlyOn       =>1,shCtOff         =>1,shCtDlyOff      =>1
                         ,shOnTime        =>1,shOffTime       =>1,shOnDly         =>1,shOffDly        =>1
		                 ,shActionTypeDim =>1,shOnTimeMode    =>1,shOffTimeMode   =>1
                         ,shDimJtOn       =>1,shDimJtOff      =>1,shDimJtDlyOn    =>1
                         ,shDimJtDlyOff   =>1,shDimJtRampOn   =>1,shDimJtRampOff  =>1
					     ,shOnLevel       =>1
						 },
  "Schueco_263-xxx02" =>{ transmitTryMax  =>1,eventDlyTime    =>1},
  "Schueco_263-xxx03" =>{ ttJtOn          =>1,ttJtOff         =>1},
  "HM-Sen-RD-O01"     =>{ eventFilterTimeB=>1,transmitTryMax  =>1,peerNeedsBurst  =>1,expectAES       =>1
                         ,condTxThrhHi    =>1,condTxThrhHi    =>1,highHoldTime    =>1,evntRelFltTime  =>1 
						 },
  "HM-CC-RT-DN03"     =>{ shCtValLo       =>1},
  "HM-CC-RT-DN04"     =>{ btnNoBckLight   =>1
                         ,dayTemp         =>1,nightTemp       =>1,tempMin         =>1,tempMax         =>1
                         ,tempOffset      =>1
                         ,decalcWeekday   =>1,decalcTime      =>1
                         ,boostPos        =>1,boostPeriod     =>1
                         ,daylightSaveTime=>1,regAdaptive     =>1
                         ,showInfo        =>1,noMinMax4Manu   =>1,showWeekday     =>1
                         ,valveOffset     =>1,valveMaxPos     =>1,valveErrPos     =>1
                         ,modePrioManu    =>1,modePrioParty   =>1
                         ,reguIntI        =>1,reguIntP        =>1,reguIntPstart   =>1
                         ,reguExtI        =>1,reguExtP        =>1,reguExtPstart   =>1
                         ,winOpnTemp      =>1,winOpnPeriod    =>1,winOpnBoost     =>1,winOpnMode      =>1
						 ,winOpnDetFall   =>1
						 },
  "HM-CC-RT-DN06"     =>{ CtrlRc          =>1,TempRC          =>1},
  "HM-TC-IT-WM-W-EU02"=>{ dayTemp         =>1,nightTemp       =>1,tempMin         =>1,tempMax         =>1,tempOffset      =>1
                         ,hyst2point      =>1,heatCool        =>1,boostPeriod     =>1,winOpnBoost     =>1
                         ,showWeekday     =>1,showInfo        =>1,showSetTemp     =>1,showHumitidy    =>1
                         ,noMinMax4Manu   =>1,daylightSaveTime=>1,sendWeatherData =>1
                         ,modePrioParty   =>1,modePrioManu    =>1,weekPrgSel      =>1
						 },
  "HM-ES-PMSw1-Pl02"  =>{ averaging       =>1
                         ,txMinDly        =>1,txThrPwr        =>1,txThrCur        =>1,txThrVlt        =>1,txThrFrq        =>1
						 },
  "HM-ES-PMSw1-Pl04"  =>{ txThrLoPwr      =>1,txThrHiPwr      =>1
                         ,CtDlyOn         =>1,CtDlyOff        =>1,CtOn            =>1,CtOff           =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,ActionType      =>1
						 },
  "HM-ES-PMSw1-Pl04"  =>{ txThrLoCur      =>1,txThrHiCur      =>1
                         ,CtDlyOn         =>1,CtDlyOff        =>1,CtOn            =>1,CtOff           =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,ActionType      =>1
						 },
  "HM-ES-PMSw1-Pl05"  =>{ txThrLoVlt      =>1,txThrHiVlt      =>1
                         ,CtDlyOn         =>1,CtDlyOff        =>1,CtOn            =>1,CtOff           =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,ActionType      =>1
						 },
  "HM-ES-PMSw1-Pl06"  =>{ txThrLoFrq      =>1,txThrHiFrq      =>1
                         ,CtDlyOn         =>1,CtDlyOff        =>1,CtOn            =>1,CtOff           =>1
                         ,CtValLo         =>1,CtValHi         =>1
                         ,OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1
                         ,SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1
                         ,ActionType      =>1
						 },
  );

#clones - - - - - - - - - - - - - - -   
$culHmRegChan{"HM-RC-19-B12"}      = $culHmRegChan{"HM-RC-1912"};
$culHmRegChan{"HM-RC-19-SW12"}     = $culHmRegChan{"HM-RC-1912"};
                                   
$culHmRegChan{"WDF-solar02"}       = $culHmRegType{"dimmer"};
                                   
$culHmRegChan{"HM-CC-RT-DN-BoM03"} = $culHmRegType{"HM-CC-RT-DN03"};
$culHmRegChan{"HM-CC-RT-DN-BoM04"} = $culHmRegType{"HM-CC-RT-DN04"};
$culHmRegChan{"HM-CC-RT-DN-BoM06"} = $culHmRegType{"HM-CC-RT-DN06"};

$culHmRegChan{"HM-TC-IT-WM-W-EU03"}= $culHmRegType{"HM-CC-RT-DN03"};
$culHmRegChan{"HM-TC-IT-WM-W-EU06"}= $culHmRegType{"HM-CC-RT-DN06"};

##--------------- Conversion routines for register settings

##############################---get---########################################
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

##############################---set---########################################
my %culHmGlobalSets = (# all but virtuals
  regBulk       => "<list>:<peer> <addr1:data1> <addr2:data2> ...",
  getRegRaw     => "[List0|List1|List2|List3|List4|List5|List6] ... [<PeerChannel>]",
  getConfig     => "",
  regSet        => "[prep|exec] <regName> <value> ... [<peerChannel>]",
  clear         => "[readings|register|rssi|msgEvents]",
);
my %culHmGlobalSetsVrtDev = (# virtuals and devices without subtype
  raw      	    => "data ...",
  virtual       =>"<noButtons>",
);
my %culHmGlobalSetsDevice = (# all devices but virtuals
  raw      	    => "data ...",
  reset    	    => "",
  pair     	    => "",
  unpair   	    => "",
);

my %culHmSubTypeDevSets = (# device of this subtype
  switch           =>{ statusRequest => "",
                       getSerial     => ""},
  dimmer           =>{ statusRequest => "",
                       getSerial     => ""},
  blindActuator    =>{ statusRequest => "", 
                       getSerial     => ""},
#  remote           =>{ },
#  threeStateSensor =>{ statusRequest =>""},
#  THSensor         =>{ statusRequest =>""}, at least OT/OT2 do not support this 
#  virtual          =>{ },
#  smokeDetector    =>{ statusRequest => ""},#not SCD
  winMatic         =>{ statusRequest => ""},
  keyMatic         =>{ statusRequest => ""},
  repeater         =>{ statusRequest => "",
                       getSerial     => ""},
  outputUnit       =>{ statusRequest => ""},# also LED16? proof
);

my %culHmGlobalSetsChn = (# all channels but virtuals
  sign     	    => "[on|off]",
  peerBulk      => "<peer1,peer2,...>",
);
my %culHmSubTypeSets = (# channels of this subtype
  switch           =>{ "on-for-timer"=>"<sec>"
                      ,"on-till"     =>"<time>"
		              ,on            =>""
					  ,off           =>""
					  ,toggle        =>""
					  ,press         =>"[long|short] [on|off] ..."
					  ,inhibit       =>"[on|off]"
					  ,statusRequest =>""},
  dimmer           =>{ "on-for-timer"=>"<sec>"
                      ,"on-till"     =>"<time>"
		              ,on            =>""
					  ,off           =>""
					  ,toggle        =>""
					  ,pct           =>"<value> ... [<ontime>] [<ramptime>]"
					  ,stop          =>""
					  ,press         =>"[long|short] [on|off] ..."
					  ,up            =>"[<changeValue>] [<ontime>] [<ramptime>] ..."
					  ,down          =>"[<changeValue>] [<ontime>] [<ramptime>] ..."
					  ,inhibit       =>"[on|off]"
					  ,statusRequest =>""},
  blindActuator    =>{ on            =>""
                      ,off           =>""
                      ,toggle        =>""
                      ,pct           =>"[<value>] ... [<ontime>]"
					  ,stop          =>""
					  ,press         =>"[long|short] [on|off] ..."
					  ,up            =>"[<changeValue>] [<ontime>] [<ramptime>] ..."
					  ,down          =>"[<changeValue>] [<ontime>] [<ramptime>] ..."
					  ,inhibit       =>"[on|off]"
					  ,statusRequest =>""},
  remote           =>{ peerChan      =>"<btnNumber> <actChn> ... [single|dual] [set|unset] [actor|remote|both]"},
  threeStateSensor =>{ peerChan      =>"<btnNumber> <actChn> ... single [set|unset] [actor|remote|both]"
#					  ,statusRequest =>""
					  },
  THSensor         =>{ peerChan      =>"<btnNumber> <actChn> ... single [set|unset] [actor|remote|both]"},
  virtual          =>{ peerChan      =>"<btnNumber> <actChn> ... [single|dual] [set|unset] [actor|remote|both]"
		              ,press         =>"[long|short]..."
                      ,postEvent     =>"<condition>"
#                      ,valvePos      =>"<position>"
					  },#acting as TC
  smokeDetector    =>{ test          =>""
                      ,alarmOn       =>""
					  ,alarmOff      =>""
		              ,peerChan      =>"<btnNumber> <actChn> ... single [set|unset] actor"},
  winMatic         =>{ matic         =>"<btn>"
                      ,keydef        =>"<btn> <txt1> <txt2>"
                      ,create        =>"<txt>"
					  ,inhibit       =>"[on|off]"
					  ,statusRequest =>""},
  keyMatic         =>{ lock          =>""
  	                  ,unlock        =>"[<sec>] ..."
  	                  ,open          =>"[<sec>] ..."
  	                  ,inhibit       =>"[on|off]"
					  ,statusRequest =>""},
  repeater         =>{ setRepeat     => "[no1..36] <sendName> <recName> [bdcast-yes|no]"
					  ,inhibit       => "[on|off]"
					  ,statusRequest =>""},
  outputUnit       =>{ statusRequest =>""},
);
# clones- - - - - - - - - - - - - - - - - 
$culHmSubTypeSets{pushButton}      = $culHmSubTypeSets{remote};
$culHmSubTypeSets{swi}             = $culHmSubTypeSets{remote};

$culHmSubTypeSets{sensor}          = $culHmSubTypeSets{outputUnit};
$culHmSubTypeSets{KFM100}          = $culHmSubTypeSets{outputUnit};
$culHmSubTypeSets{blindActuatorSol}= $culHmSubTypeSets{outputUnit};
$culHmSubTypeSets{tipTronic}       = $culHmSubTypeSets{outputUnit};
$culHmSubTypeSets{powerMeter}      = $culHmSubTypeSets{outputUnit};

$culHmSubTypeSets{motionDetector}  = $culHmSubTypeSets{threeStateSensor};

my %culHmModelSets = (# channels of this subtype-------------
  "HM-CC-VD"       =>{ valvePos       => "position"},
  "HM-RC-19"       =>{ service        => "<count>"
		              ,alarm          => "<count>"
		              ,display        => "<text> [comma|no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>"},
  "HM-PB-4DIS-WM"  =>{ text           => "<txt1> <txt2>..."
                        #text         => "<btn> [on|off] <txt1> <txt2>...", old style will not be offered anymore
				     },               
  "HM-OU-LED16"    =>{ led            => "[off|red|green|orange]"
		              ,ilum           => "[0-15] [0-127]"},
  "HM-OU-CFM-PL"   =>{ "on-for-timer" =>"<sec>"
                      ,"on-till"      =>"<time>"
		              ,on             =>""
					  ,off            =>""
					  ,toggle         =>""
					  ,press          =>"[long|short] [on|off] ..."
					  ,inhibit        =>"[on|off]"},
  "HM-CC-TC"       =>{ burstXmit      =>""},
  "HM-CC-RT-DN"    =>{ burstXmit      =>""},
  "HM-CC-RT-DN-BoM"=>{ statusRequest  =>""},
);
# clones- - - - - - - - - - - - - - - - - 
$culHmModelSets{"HM-RC-19-B"}  = $culHmModelSets{"HM-RC-19"};
$culHmModelSets{"HM-RC-19-SW"} = $culHmModelSets{"HM-RC-19"};
$culHmModelSets{"HM-OU-CM-PCB"} = $culHmModelSets{"HM-OU-CFM-PL"};
#%{$culHmModelSets{"HM-RC-19-SW"}} = %{$culHmModelSets{"HM-RC-19"}}; copy

my %culHmChanSets = (
  "HM-CC-TC00"     =>{ "desired-temp" =>"[on|off|6.0..30.0]"
                      ,statusRequest  =>""
                      ,sysTime        =>""	  
					  ,getSerial      => ""},
  "HM-CC-TC02"     =>{ peerChan       =>" 0 <actChn> ... single [set|unset] [actor|remote|both]"
                      ,"desired-temp" =>"[on|off|6.0..30.0]" 
                      ,tempListSat    =>"[prep|exec] HH:MM temp ..."
                      ,tempListSun    =>"[prep|exec] HH:MM temp ..."
                      ,tempListMon    =>"[prep|exec] HH:MM temp ..."
                      ,tempListTue    =>"[prep|exec] HH:MM temp ..."
                      ,tempListThu    =>"[prep|exec] HH:MM temp ..."
                      ,tempListWed    =>"[prep|exec] HH:MM temp ..."
                      ,tempListFri    =>"[prep|exec] HH:MM temp ..."
                      ,partyMode      =>"[prep|exec] HH:MM durationDays ..."
                      ,displayMode    =>"[temp-only|temp-hum]"
                      ,displayTemp    =>"[actual|setpoint]"
                      ,displayTempUnit=>"[celsius|fahrenheit]"
                      ,controlMode    =>"[auto|manual|central|party]"
                      ,statusRequest  =>""
                      ,sysTime        =>""	  },
  "HM-SEC-WIN01"   =>{ stop           =>"",
                       level          =>"<level> <relockDly> <speed>..."},
  "HM-OU-CFM-PL01" =>{ led            =>"<color>[,<color>...] [<repeat>]"},
  "HM-OU-CFM-PL02" =>{ playTone       =>"<MP3No>[,<MP3No>...] [<repeat>]"},
                                      
  "WDF-solar01"    =>{ peerChan       =>" 0 <actChn> ... single [set|unset] [actor|remote|both]"},
  "HM-Sen-RD-O01"  =>{ peerChan       =>" 0 <actChn> ... single [set|unset] [actor|remote|both]"},
  "HM-Sen-RD-O02"  =>{ "on-for-timer" =>"<sec>"
                      ,"on-till"      =>"<time>"
		              ,on             =>""
					  ,off            =>""
					  ,toggle         =>""},
  "HM-CC-RT-DN00"  =>{ sysTime        =>""},
  "HM-CC-RT-DN02"  =>{ sysTime        =>""},
  "HM-CC-RT-DN04"  =>{ controlMode    =>"[auto|boost|day|night]"
                      ,controlManu    =>"[on|off|5.0..30.0]"
                      ,controlParty   =>"<temp> <startDate> <startTime> <enddate> <endTime>"
                      ,tempListSat    =>"[prep|exec] HH:MM temp ..."
                      ,tempListSun    =>"[prep|exec] HH:MM temp ..."
                      ,tempListMon    =>"[prep|exec] HH:MM temp ..."
                      ,tempListTue    =>"[prep|exec] HH:MM temp ..."
                      ,tempListThu    =>"[prep|exec] HH:MM temp ..."
                      ,tempListWed    =>"[prep|exec] HH:MM temp ..."
                      ,tempListFri    =>"[prep|exec] HH:MM temp ..."
					  ,"desired-temp" =>"[on|off|5.0..30.0]"
					  ,sysTime        =>""
                     },
  "HM-CC-RT-DN05"  =>{ peerChan       =>" 0 <actChn> ... [single] [set|unset] [actor|remote|both]"},
);
# clones- - - - - - - - - - - - - - - - - 
#$culHmChanSets{"HM-OU-CF-PL02"}  = $culHmChanSets{"HM-OU-CF-PL01"};
$culHmChanSets{"WDF-solar02"}      = $culHmSubTypeSets{"blindActuator"};
$culHmChanSets{"HM-CC-RT-DN-BoM00"}= $culHmSubTypeSets{"HM-CC-RT-DN00"};
$culHmChanSets{"HM-CC-RT-DN-BoM02"}= $culHmSubTypeSets{"HM-CC-RT-DN02"};
$culHmChanSets{"HM-CC-RT-DN-BoM04"}= $culHmSubTypeSets{"HM-CC-RT-DN04"};
$culHmChanSets{"HM-CC-RT-DN-BoM05"}= $culHmSubTypeSets{"HM-CC-RT-DN05"};

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

##############################---messages---###################################
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
  "02;p01=04"   => { txt => "ACK-proc",  params => {# connected to AES??
                     Para1          => "02,4",
                     Para2          => "06,4",
                     Para3          => "10,4",
                     Para4          => "14,2",}}, # remote?
  "02;p01=80"   => { txt => "NACK"},
  "02;p01=84"   => { txt => "NACK_TARGET_INVALID"},
  "02"          => { txt => "ACK/NACK_UNKNOWN   "},
  
  "02"          => { txt => "Request AES", params => {  #todo check data
                     DATA =>  "0," } },

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
  "11;p01=81"   => { txt => "LEVEL"       , params => {
                     CHANNEL  => "02,2",  
                     TIME     => '04,2,$val=hex($val)', 
                     SPEED    => '06,2,$val=hex($val)', 
					 } }, 
  "11;p01=82"   => { txt => "Sleepmode"   , params => {#only LED16? 
                     CHANNEL  => "02,2", 
                     MODE     => '04,2,$val=hex($val)', 
					 } }, 
  "12"          => { txt => "HAVE_DATA"},
  "3E"          => { txt => "SWITCH"      , params => {
                     DST      => "00,6", 
                     UNKNOWN  => "06,2", 
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
  "58"          => { txt => "ClimateEvent", params => {
                     CMD      => "00,2",
                     ValvePos => '02,2,$val=(hex($val))', } },
  "59"          => { txt => "setTeamTemp" , params => {
                     CMD      => "00,2", 
					 desTemp  => '02,2,$val=((hex($val)>>2) /2)',
					 mode     => '02,2,$val=(hex($val) & 0x3)',} },
  "70"          => { txt => "WeatherEvent", params => {
                     TEMP     => '00,4,$val=((hex($val)&0x3FFF)/10)*((hex($val)&0x4000)?-1:1)',
                     HUM      => '04,2,$val=(hex($val))', } },
);

sub HMConfig_getHash($){
  my $hn = shift;
  return %culHmModel            if($hn eq "culHmModel"           );
  return %culHmRegDefShLg       if($hn eq "culHmRegDefShLg"      );
  return %culHmRegDefine        if($hn eq "culHmRegDefine"       );
  return %culHmRegGeneral       if($hn eq "culHmRegGeneral"      );
  return %culHmRegType          if($hn eq "culHmRegType"         );
  return %culHmRegModel         if($hn eq "culHmRegModel"        );
  return %culHmRegChan          if($hn eq "culHmRegChan"         );
  
  return %culHmGlobalGets       if($hn eq "culHmGlobalGets"      );
  return %culHmSubTypeGets      if($hn eq "culHmSubTypeGets"     );
  return %culHmModelGets        if($hn eq "culHmModelGets"       );
  
  return %culHmGlobalSetsDevice if($hn eq "culHmGlobalSetsDevice");
  return %culHmSubTypeDevSets   if($hn eq "culHmSubTypeDevSets"  );
  return %culHmGlobalSetsChn    if($hn eq "culHmGlobalSetsChn"   );
  return %culHmGlobalSets       if($hn eq "culHmGlobalSets"      );
  return %culHmGlobalSetsVrtDev if($hn eq "culHmGlobalSetsVrtDev");
  return %culHmSubTypeSets      if($hn eq "culHmSubTypeSets"     );
  return %culHmModelSets        if($hn eq "culHmModelSets"       );
  return %culHmChanSets         if($hn eq "culHmChanSets"        );
  
  return %culHmBits             if($hn eq "culHmBits"            );
  return @culHmCmdFlags         if($hn eq "culHmCmdFlags"        );
  return $K_actDetID            if($hn eq "K_actDetID"           );
}
1;
