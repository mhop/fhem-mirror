##############################################
# CUL HomeMatic handler
# $Id$

package main;

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
sub CUL_HM_SendCmd($$$$);
sub CUL_HM_responseSetup($$$);
sub CUL_HM_eventP($$);
sub CUL_HM_respPendRm($);
sub CUL_HM_respPendTout($);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_Resend($);
sub CUL_HM_Id($);
sub CUL_HM_name2hash($);
sub CUL_HM_Name2Id(@);
sub CUL_HM_id2Name($);
sub CUL_HM_getDeviceHash($);
sub CUL_HM_DumpProtocol($$@);
sub CUL_HM_parseCommon(@);
sub CUL_HM_encodeTime8($);
sub CUL_HM_decodeTime8($);
sub CUL_HM_encodeTime16($);
sub CUL_HM_convTemp($);
sub CUL_HM_decodeTime16($);
sub CUL_HM_pushConfig($$$$$$$$);
sub CUL_HM_maticFn($$$$$);
sub CUL_HM_secSince2000();

my %culHmDevProps=(
  "01" => { st => "AlarmControl",    cl => "controller" }, # by peterp
  "12" => { st => "outputUnit",      cl => "receiver" }, # Test Pending
  "10" => { st => "switch",          cl => "receiver" }, # Parse,Set
  "20" => { st => "dimmer",          cl => "receiver" }, # Parse,Set
  "30" => { st => "blindActuator",   cl => "receiver" }, # Parse,Set
  "39" => { st => "ClimateControl",  cl => "sender"   },
  "40" => { st => "remote",          cl => "sender"   }, # Parse
  "41" => { st => "sensor",          cl => "sender"   },
  "42" => { st => "swi",             cl => "sender"   }, # e.g. HM-SwI-3-FM
  "43" => { st => "pushButton",      cl => "sender"   },
  "58" => { st => "thermostat",      cl => "receiver" }, 
  "60" => { st => "KFM100",          cl => "sender"   }, # Parse,unfinished
  "70" => { st => "THSensor",        cl => "sender"   }, # Parse,unfinished
  "80" => { st => "threeStateSensor",cl => "sender"   }, # e.g.HM-SEC-RHS
  "81" => { st => "motionDetector",  cl => "sender"   },
  "C0" => { st => "keyMatic",        cl => "receiver" },
  "C1" => { st => "winMatic",        cl => "receiver" },
  "CD" => { st => "smokeDetector",   cl => "receiver" }, # Parse,set unfinished
);
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
  "0001" => {name=>"HM-LC-SW1-PL-OM54"       ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0002" => {name=>"HM-LC-SW1-SM"            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0003" => {name=>"HM-LC-SW4-SM"            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0004" => {name=>"HM-LC-SW1-FM"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0005" => {name=>"HM-LC-BL1-FM"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0006" => {name=>"HM-LC-BL1-SM"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0007" => {name=>"KS550"                   ,cyc=>'00:10' ,rxt=>''    ,lst=>'1'            ,chn=>"",},
  "0008" => {name=>"HM-RC-4"                 ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0009" => {name=>"HM-LC-SW2-FM"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000A" => {name=>"HM-LC-SW2-SM"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "000B" => {name=>"HM-WDC7000"              ,cyc=>''      ,rxt=>''    ,lst=>''             ,chn=>"",},
  "000D" => {name=>"ASH550"                  ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "000E" => {name=>"ASH550I"                 ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "000F" => {name=>"S550IA"                  ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "0011" => {name=>"HM-LC-SW1-PL"            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0012" => {name=>"HM-LC-DIM1L-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Vtr:2:3",},
  "0013" => {name=>"HM-LC-DIM1L-PL"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "0016" => {name=>"HM-LC-DIM2L-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2,Vtr:3:6",},
  "0018" => {name=>"CMM"                     ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0019" => {name=>"HM-SEC-KEY"              ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "001A" => {name=>"HM-RC-P1"                ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "001B" => {name=>"HM-RC-SEC3"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001C" => {name=>"HM-RC-SEC3-B"            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001D" => {name=>"HM-RC-KEY3"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "001E" => {name=>"HM-RC-KEY3-B"            ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:3",},
  "0022" => {name=>"WS888"                   ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0026" => {name=>"HM-SEC-KEY-S"            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "0027" => {name=>"HM-SEC-KEY-O"            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "0028" => {name=>"HM-SEC-WIN"              ,cyc=>''      ,rxt=>'b'   ,lst=>'1,3'          ,chn=>"",},
  "0029" => {name=>"HM-RC-12"                ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002A" => {name=>"HM-RC-12-B"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "002D" => {name=>"HM-LC-SW4-PCB"           ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "002E" => {name=>"HM-LC-DIM2L-SM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2,Vtr:3:6",},
  "002F" => {name=>"HM-SEC-SC"               ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0030" => {name=>"HM-SEC-RHS"              ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0034" => {name=>"HM-PBI-4-FM"             ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0035" => {name=>"HM-PB-4-WM"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "0036" => {name=>"HM-PB-2-WM"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:2",},
  "0037" => {name=>"HM-RC-19"                ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18",},
  "0038" => {name=>"HM-RC-19-B"              ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18",},
  "0039" => {name=>"HM-CC-TC"                ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'5:2.3p,6:2'   ,chn=>"Weather:1:1,Climate:2:2,WindowRec:3:3",},
  "003A" => {name=>"HM-CC-VD"                ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'5'            ,chn=>"",},
  "003B" => {name=>"HM-RC-4-B"               ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:4",},
  "003C" => {name=>"HM-WDS20-TH-O"           ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003D" => {name=>"HM-WDS10-TH-O"           ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003E" => {name=>"HM-WDS30-T-O"            ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "003F" => {name=>"HM-WDS40-TH-I"           ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "0040" => {name=>"HM-WDS100-C6-O"          ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1'            ,chn=>"",},
  "0041" => {name=>"HM-WDC7000"              ,cyc=>''      ,rxt=>''    ,lst=>'1,4'          ,chn=>"",},
  "0042" => {name=>"HM-SEC-SD"               ,cyc=>'90:00' ,rxt=>'b'   ,lst=>''             ,chn=>"",},
  "0043" => {name=>"HM-SEC-TIS"              ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0044" => {name=>"HM-SEN-EP"               ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0045" => {name=>"HM-SEC-WDS"              ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0047" => {name=>"KFM-Sensor"              ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0046" => {name=>"HM-SWI-3-FM"             ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"Sw:1:3",},
  "0048" => {name=>"IS-WDS-TH-OD-S-R3"       ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},
  "0049" => {name=>"KFM-Display"             ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "004A" => {name=>"HM-SEC-MDIR"             ,cyc=>'00:20' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "004B" => {name=>"HM-Sec-Cen"              ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "004C" => {name=>"HM-RC-12-SW"             ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:12",},
  "004D" => {name=>"HM-RC-19-SW"             ,cyc=>''      ,rxt=>'c:b' ,lst=>'1,4'          ,chn=>"Btn:1:17,Disp:18",},
  "004E" => {name=>"HM-LC-DDC1-PCB"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "004F" => {name=>"HM-SEN-MDIR-SM"          ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0050" => {name=>"HM-SEC-SFA-SM"           ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0051" => {name=>"HM-LC-SW1-PB-FM"         ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0052" => {name=>"HM-LC-SW2-PB-FM"         ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:2",},
  "0053" => {name=>"HM-LC-BL1-PB-FM"         ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0054" => {name=>"DORMA_RC-H"              ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",},
  "0056" => {name=>"HM-CC-SCD"	             ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0057" => {name=>"HM-LC-DIM1T-PL"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Vtr:2:3",},
  "0058" => {name=>"HM-LC-DIM1T-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Vtr:2:3",},
  "0059" => {name=>"HM-LC-DIM1T-FM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Vtr:2:3",},
  "005A" => {name=>"HM-LC-DIM2T-SM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2,Vtr:3:6",},
  "005C" => {name=>"HM-OU-CF-PL"             ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Led:1:1,Sound:2:2",},
  "005D" => {name=>"HM-Sen-MDIR-O"           ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "005F" => {name=>"HM-SCI-3-FM"             ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "0060" => {name=>"HM-PB-4DIS-WM"           ,cyc=>'00:10' ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:20",},
  "0061" => {name=>"HM-LC-SW4-DR"            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0062" => {name=>"HM-LC-SW2-DR"            ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "0064" => {name=>"DORMA_atent"             ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",},
  "0065" => {name=>"DORMA_BRC-H"             ,cyc=>''      ,rxt=>'c'   ,lst=>'1,3'          ,chn=>"",},
  "0066" => {name=>"HM-LC-SW4-WM"            ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"Sw:1:4",},
  "0067" => {name=>"HM-LC-Dim1PWM-CV"        ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0068" => {name=>"HM-LC-Dim1TPBU-FM"       ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0069" => {name=>"HM-LC-Sw1PBU-FM"         ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "006A" => {name=>"HM-LC-Bl1PBU-FM"         ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "006B" => {name=>"HM-PB-2-WM55"            ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "006C" => {name=>"HM-LC-SW1-BA-PCB"        ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "006D" => {name=>"HM-OU-LED16"             ,cyc=>''      ,rxt=>''    ,lst=>''             ,chn=>"Led:1:16",},
  "0075" => {name=>"HM-OU-CFM-PL"            ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Led:1:1,Mp3:2:2",},
  "0078" => {name=>"HM-Dis-TD-T"             ,cyc=>''      ,rxt=>'b'   ,lst=>'3'            ,chn=>"",},
  "0079" => {name=>"ROTO_ZEL-STG-RM-FWT"     ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},
  "0x7A" => {name=>"ROTO_ZEL-STG-RM-FSA"     ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "007B" => {name=>"ROTO_ZEL-STG-RM-FEP-230V",cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "007D" => {name=>"ROTO_ZEL-STG-RM-WT-2"    ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "007E" => {name=>"ROTO_ZEL-STG-RM-DWT-10"  ,cyc=>'00:10' ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "007F" => {name=>"ROTO_ZEL-STG-RM-FST-UP4" ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "0080" => {name=>"ROTO_ZEL-STG-RM-HS-4"    ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "0081" => {name=>"ROTO_ZEL-STG-RM-FDK"     ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},
  "0082" => {name=>"Roto_ZEL-STG-RM-FFK"     ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},  
  "0083" => {name=>"Roto_ZEL-STG-RM-FSS-UP3" ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"",},  
  "0084" => {name=>"Schueco_263-160"         ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},  
  "0086" => {name=>"Schueco_263-146"         ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "008D" => {name=>"Schueco_263-1350"        ,cyc=>''      ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},
  "008E" => {name=>"Schueco_263-155"         ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "008F" => {name=>"Schueco_263-145"         ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"",},
  "0090" => {name=>"Schueco_263-162"         ,cyc=>'00:30' ,rxt=>'c:w' ,lst=>'1,3'          ,chn=>"",},  
  "0092" => {name=>"Schueco_263-144"         ,cyc=>''      ,rxt=>'c'   ,lst=>'4'            ,chn=>"",},  
  "0093" => {name=>"Schueco_263-158"         ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
  "0094" => {name=>"Schueco_263-157"         ,cyc=>''      ,rxt=>'c:w' ,lst=>''             ,chn=>"",},
);
sub
CUL_HM_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^A....................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{UndefFn}   = "CUL_HM_Undef";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{GetFn}     = "CUL_HM_Get";
  $hash->{RenameFn}  = "CUL_HM_Rename";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:1,0 dummy:1,0 ".
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
                       "hmClass:receiver,sender serialNr firmware devInfo ".
                       "rawToReadable unit ".
					   "chanNo device peerList peerIDs ".
					   "actCycle actStatus ".
					   "protCmdPend protLastRcv protSndCnt protSndLast protCmdDel protNackCnt protNackLast ".
					   "protResndFailLast protResndLast protResndFailCnt protResndCnt protToutRespLast protToutRespCnt ".
					   "channel_01 channel_02 channel_03 channel_04 channel_05 channel_06 ".
					   "channel_07 channel_08 channel_09 channel_0A channel_0B channel_0C ". 
					   "channel_0D channel_0E channel_0F channel_10 channel_11 channel_12 ".
					   "channel_13 channel_14 channel_15 channel_16 channel_17 channel_18 ";
  my @modellist;
  foreach my $model (keys %culHmModel){
    push @modellist,$culHmModel{$model}{name};
  }
  $hash->{AttrList}  .= " model:"  .join(",", sort @modellist);
  $hash->{AttrList}  .= " subType:".join(",", sort 
                map { $culHmDevProps{$_}{st} } keys %culHmDevProps);
}
#############################
sub
CUL_HM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $a[2] !~ m/^[A-F0-9]{6,8}$/i);
  
  my $HMid = uc($a[2]);
  return  "HMid DEF already used by " .	CUL_HM_id2Name($HMid)	 
        if ($modules{CUL_HM}{defptr}{$HMid}); 
  if(length($a[2]) == 8) {
    my $devHmId = uc(substr($a[2], 0, 6));
    my $chn = substr($a[2], 6, 2);
    my $devHash = $modules{CUL_HM}{defptr}{$devHmId};
    if($devHash) {# define a channel
      $modules{CUL_HM}{defptr}{$HMid} = $hash;
      AssignIoPort($hash);
      my $devName = $devHash->{NAME};
      $attr{$name}{device} = $devName; 
      $attr{$name}{chanNo} = $chn; 
      $attr{$name}{model} = $attr{$devName}{model} if ($attr{$devName}{model});
	  $attr{$devName}{"channel_$chn"} = $name; 
    }
	else{
	  return "please define a device with hmId:".$devHmId." first";
	}
  }
  else{# define a device
    $modules{CUL_HM}{defptr}{$HMid} = $hash;
    AssignIoPort($hash);
  }
  CUL_HM_ActGetCreateHash() if($HMid eq '000000');#startTimer
  if(int(@a) == 4) {
    $hash->{DEF} = $a[2];
    CUL_HM_Parse($hash, $a[3]);
  }
  return undef;
}

#############################
sub
CUL_HM_Undef($$)
{
  my ($hash, $name) = @_;
  my $devName = $attr{$name}{device};
  my $HMid = $hash->{DEF};
  my $chn = substr($HMid,6,2);
  if ($chn){# delete a channel
    delete $attr{$devName}{"channel_$chn"} if ($devName);
  }
  else{# delete a device
    foreach my $channel (keys %{$attr{$name}}){
	  CommandDelete(undef,$attr{$name}{$channel})
	        if ($channel =~ m/^channel_/);
    }
  }
  delete($modules{CUL_HM}{defptr}{$HMid});
  return undef;
}
#############################
sub
CUL_HM_Rename($$$)
{
  #my ($hash, $name,$newName) = @_;
  my ($name, $oldName) = @_;
  my $HMid = CUL_HM_Name2Id($name);
  if (length($HMid) == 8){# we are channel, inform the device
    $attr{$name}{chanNo} = substr($HMid,6,2);
	my $device = AttrVal($name, "device", "");
	$attr{$device}{"channel_".$attr{$name}{chanNo}} = $name if ($device);
  }
  else{# we are a device - inform channels if exist
    for (my$chn = 1; $chn <25;$chn++){
	  my $chnName = AttrVal($name, sprintf("channel_%02X",$chn), "");
	  $attr{$chnName}{device} = $name if ($chnName);
	}
  }
  return;
}

#############################
sub
CUL_HM_Parse($$)
{
  my ($iohash, $msg) = @_;
  my $id = CUL_HM_Id($iohash);
  # Msg format: Allnnffttssssssddddddpp...
  $msg =~ m/A(..)(..)(..)(..)(......)(......)(.*)/;
  my @msgarr = ($1,$2,$3,$4,$5,$6,$7);
  my ($len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p) = @msgarr;
  $p = "" if(!defined($p));
  my $cmd = "$msgFlag$msgType"; #still necessary to maintain old style
  my $lcm = "$len$cmd";
  # $shash will be replaced for multichannel commands
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  my $dname = $dhash ? $dhash->{NAME} :
                       ($dst eq "000000" ? "broadcast" : 
                       ($dst eq $id ? $iohash->{NAME} : $dst));
  my $target = " (to $dname)";

  return "" if($p =~ m/NACK$/);#discard TCP errors from HMlan. Resend will cover it
  return "" if($src eq $id);#discard mirrored messages
  
  if(!$shash) {      #  Unknown source
    # Generate an UNKNOWN event for pairing requests, ignore everything else
    if($msgType eq "00") {
      my $sname = "CUL_HM_$src";
      # prefer subType over model to make autocreate easier
      # model names are quite cryptic anyway
      my $model = substr($p, 2, 4);
      my $stc = substr($p, 26, 2);        # subTypeCode
      if($culHmDevProps{$stc}) {
        $sname = "CUL_HM_".$culHmDevProps{$stc}{st} . "_" . $src;
      } 
	  elsif($culHmModel{$model}{name}) {
        $sname = "CUL_HM_".$culHmModel{$model}{name} . "_" . $src;
        $sname =~ s/-/_/g;
      }
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

  # return if duplicate
  my $msgX = "No:$msgcnt - t:$msgType s:$src d:$dst $p";
  if($shash->{lastMsg} && $shash->{lastMsg} eq $msgX) {
    Log GetLogLevel($name,4), "CUL_HM $name dup mesg";
    return ""; #return something to please dispatcher
  }
  $shash->{lastMsg} = $msgX;
  $iohash->{HM_CMDNR} = hex($msgcnt) if($dst eq $id);# update messag counter to receiver

  CUL_HM_DumpProtocol("RCV",$iohash,$len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p);

  #----------start valid messages parsing ---------
  my $parse = CUL_HM_parseCommon($msgcnt,$msgType,$src,$dst,$p);
  push @event, "powerOn"   if($parse eq "powerOn");
  
  my $sendAck = "yes";# if yes Ack will be determined automatically
  $sendAck = "" if ($parse eq "STATresp");

  if ($parse eq "ACK"){# remember - ACKinfo will be passed on
    push @event, "";
  }
  elsif($parse eq "NACK"){
	push @event, "state:NACK";
  }
  elsif($parse eq "done"){
    push @event, "";
	$sendAck = ""; 
  } 
  elsif($lcm eq "09A112") {      #### Another fhem wants to talk (HAVE_DATA)
    ;
  } 
  elsif($msgType eq "00" ){      #### DEVICE_INFO,  Pairing-Request 
    CUL_HM_infoUpdtDevData($name, $shash,$p);#update data

    if($shash->{cmdStack} && (CUL_HM_getRxType($shash) & 0x04)) {
      CUL_HM_ProcessCmdStack($shash);# sender devices may have msgs stacked
	  push @event,"";
    } 
	else {
      push @event, CUL_HM_Pair($name, $shash,$cmd,$src,$dst,$p);
    }
    $sendAck = ""; #todo why is this special?
	
  } 
  elsif(($cmd =~ m/^A0[01]{2}$/ && $dst eq $id) && $st ne "keyMatic") {#### Pairing-Request-Convers.
    push @event, "";    #todo why end here?

  } 
  elsif($model eq "KS550" || $model eq "HM-WDS100-C6-O") { ############

    if($cmd eq "8670" && $p =~ m/^(....)(..)(....)(....)(..)(..)(..)/) {

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

    } else {
      push @event, "unknown:$p";

    }
	$sendAck = ""; #todo why is this special?

  } 
  elsif($model eq "HM-CC-TC") {  ####################################
    my ($sType,$chn) = ($1,$2) if($p =~ m/^(..)(..)/);
    if($msgType eq "70" && $p =~ m/^(....)(..)/) {# weather event
	  $chn = '01'; # fix definition
      my (    $t,      $h) =  (hex($1), hex($2));# temp is 15 bit signed
      $t = ($t & 0x3fff)/10*(($t & 0x4000)?-1:1);
      push @event, "state:T: $t H: $h";
      push @event, "measured-temp:$t";
      push @event, "humidity:$h";
    }
    elsif($msgType eq "58" && $p =~ m/^(..)(..)/) {#climate event
	  $chn = '02'; # fix definition
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $1, hex($2));
      $vp = int($vp/2.56+0.5);   # valve position in %
      push @event, "actuator:$vp %";

      # Set the valve state too, without an extra trigger
      if($dhash) {
	    DoTrigger($dname,'ValvePosition:set_'.$vp.'%');
        $dhash->{STATE} = "$vp %";
		CUL_HM_setRd($dhash,"state","set_$vp %",$tn);
      }
    }
    elsif($msgType eq "10"){
      if(   $p =~ m/^0403(......)(..)0505(..)0000/) {
	    # change of chn 3(window) list 5 register 5 - a peer window changed!
        my ( $tdev,   $tchan,     $v1) = (($1), hex($2), hex($3));
	    push @event, sprintf("windowopen-temp-%d: %.1f (sensor:%s)"
	                        ,$tchan, $v1/2, $tdev);
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
            if(defined ($ptr->{HOUR}) && 0+$ptr->{HOUR} == 24) {
              $twentyfour = 1;  # next value uninteresting, only first counts.
            }
      	  }
          push @event, $msg; # generate one event per day entry
        }
      } 
	  elsif($p =~ m/^04020000000005(..)(..)/) {
        my ( $o1,    $v1) = (hex($1),hex($2));# only parse list 5 for chn 2
        my $msg;
        my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
        if($o1 == 1) { ### bitfield containing multiple values...
	      my %mode = (0 => "manual",1 => "auto",2 => "central",3 => "party");
          push @event,'displayMode:temperature '.(($v1 & 1)?" and humidity":" only");
          push @event,'displayTemp:'            .(($v1 & 2)?"setpoint"     :"actual");
          push @event,'displayTempUnit:'        .(($v1 & 4)?"fahrenheit"   :"celsius");
          push @event,'controlMode:'            .($mode{(($v1 & 0x18)>>3)});
          push @event,'decalcDay:'              .$days[($v1 & 0xE0)>>5];
        } 
	    elsif($o1 == 2) {
	      my %pos = (0=>"Auto",1=>"Closed",2=>"Open",3=>"unknown");		  
          push @event,"tempValveMode:".$pos{(($v1 & 0xC0)>>6)};
        } 
	    else{
	      push @event,'param-change: offset='.$o1.', value='.$v1;
	    }
      }
	  elsif($p =~ m/^0[23]/){#param response
	    push @event,'';#cannot be handled here as request missing
	  }
	}
    elsif($msgType eq "01"){
      if($p =~ m/^010809(..)0A(..)/) { # TC set valve  for VD => post events to VD
        my (   $of,     $vep) = (hex($1), hex($2));
      push @event, "ValveErrorPosition for $dname: $vep %";
      push @event, "ValveOffset for $dname: $of %";
	    DoTrigger($dname,'ValveErrorPosition:set_'.$vep.'%');
	    DoTrigger($dname,'ValveOffset:set_'.$of.'%');
	    push @event,""; # nothing to report for TC
	  }
	  elsif($p =~ m/^010[56]/){ # 'prepare to set' or 'end set'
	  	push @event,""; # 
	  }
    }
#          ($cmd eq "A112" && $p =~ m/^0202(..)$/)) {    # Set desired temp
    elsif(($msgType eq '02' &&$sType eq '01')|| # ackStatus
	      ($msgType eq '10' &&$sType eq '06')){  #infoStatus
      push @event, "desired-temp:" .sprintf("%0.1f", hex(substr($p,4,2))/2);
    }
    elsif($cmd eq "A03F" && $id eq $dst) {              # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      CUL_HM_SendCmd($shash, "++803F$id${src}0204$s2000",1,0);
      push @event, "time-request";
	  $sendAck = ""; 
    } 
	
	if($cmd ne "8002" && $cmd ne "A03F" && $id eq $dst) {
        CUL_HM_SendCmd($shash, $msgcnt."8002$id${src}00",1,0)  # Send Ack
    }
	$sendAck = ""; #todo why is this special?
  } 
  elsif($model eq "HM-CC-VD") { ###################
    # CMD:8202 SRC:13F251 DST:15B50D 010100002A
    # status ACK to controlling HM-CC-TC
    if($msgType eq "02" && $p =~ m/^(..)(..)(..)(..)/) {#subtype+chn+value+err
      my ($chn,$vp, $err) = ($2,hex($3), hex($4));
      $vp = int($vp)/2;   # valve position in %
      push @event, "ValvePosition:$vp%";
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

      my $cmpVal = defined($shash->{helper}{addVal})?$shash->{helper}{addVal}:0xff;
	  $cmpVal = (($cmpVal ^ $err)|$err); # all error,only one goto normal
	  $shash->{helper}{addVal} = $err;   #store to handle changes

      # Status-Byte Auswertung
	  my $stErr = ($err >>1) & 0x7;      
	  if ($cmpVal&0x0E){# report bad always, good only once
	    if (!$stErr){#remove both conditions
          push @event, "battery:ok";
          push @event, "motorErr:ok";
		}
		else{
          push @event, "motorErr:blocked"                   if($stErr == 1);
          push @event, "motorErr:loose"                     if($stErr == 2);
          push @event, "motorErr:adjusting range too small" if($stErr == 3);
          push @event, "battery:low"                        if($stErr == 4);
		}
	  }
      push @event, "motor:opening" if(($err&0x30) == 0x10);
      push @event, "motor:closing" if(($err&0x30) == 0x20);
      push @event, "motor:stop"    if(($err&0x30) == 0x00);
    }

    # CMD:A010 SRC:13F251 DST:5D24C9 0401 00000000 05 09:00 0A:07 00:00
    # status change report to paired central unit
	#read List5 reg 09 (offset) and 0A (err-pos)
	#list 5 is channel-dependant not link dependant
	#        => Link discriminator (00000000) is fixed
    elsif($msgType eq "10" && $p =~ m/^04..........0509(..)0A(..)/) {
      my (    $of,     $vep) = (hex($1), hex($2));
      push @event, "ValveErrorPosition:$vep%";
      push @event, "ValveOffset:$of%";
    }
  
  } 
  elsif($st eq "KFM100" && $model eq "KFM-Sensor") { ###################

    if($p =~ m/.14(.)0200(..)(..)(..)/) {# todo very risky - no start...
      my ($k_cnt, $k_v1, $k_v2, $k_v3) = ($1,$2,$3,$4);
      my $v = 128-hex($k_v2);                  # FIXME: calibrate
      # $v = 256+$v if($v < 0);
      $v += 256 if(!($k_v3 & 1));
      push @event, "rawValue:$v";

      my $seq = hex($k_cnt);
      push @event, "Sequence:$seq";

      my $r2r = AttrVal($name, "rawToReadable", undef);
      if($r2r) {
        my @r2r = split("[ :]", $r2r);
        foreach(my $idx = 0; $idx < @r2r-2; $idx+=2) {
          if($v >= $r2r[$idx] && $v <= $r2r[$idx+2]) {
            my $f = (($v-$r2r[$idx])/($r2r[$idx+2]-$r2r[$idx]));
            my $cv = ($r2r[$idx+3]-$r2r[$idx+1])*$f + $r2r[$idx+1];
            my $unit = AttrVal($name, "unit", "");
            $unit = " $unit" if($unit);
            push @event, sprintf("state:%.1f %s",$cv,$unit);
            push @event, sprintf("content:%.1f %s",$cv,$unit);
            last;
          }
        }
      } else {
        push @event, "state:$v";
      }
	  $sendAck = ""; #todo why no ack?
    }
    
  } 
  elsif($st eq "switch" || ############################################
          $st eq "dimmer" ||
          $st eq "blindActuator") {

    if (($msgType eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
	    ($msgType eq "10" && $p =~ m/^06/))	{ #    or Info_Status message here

      my ($subType,$chn,$level,$err) = ($1,$2,$3,hex($4)) 
	                     if($p =~ m/^(..)(..)(..)(..)/);
      # Multi-channel device: Use channel if defined
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
      my $cmpVal = defined($shash->{helper}{addVal})?$shash->{helper}{addVal}:0xff;
	  $cmpVal = (($cmpVal ^ $err)|$err); # all error,only one goto normal
	  $shash->{helper}{addVal} = $err;   #store to handle changes

      my $val = hex($level)/2;
      $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));

      push @event, "deviceMsg:$val$target" if($chn ne "00");
	     #hack for blind  - other then behaved devices blind does not send
		 #        a status info fo rchan 0 at power on
		 #        chn3 (virtual chan) and not used up to now
		 #        info from it is likely a power on!
	  push @event, "powerOn"   if($chn eq "03"&&$st eq "dimmer");

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
	  push @event, "battery:" . (($err&0x80) ? "low" : "ok" )
	           if(($model eq "HM-LC-SW1-BA-PCB")&&($cmpVal&0x80));
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
		}else{
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
      my $cmpVal = defined($shash->{helper}{addVal})?$shash->{helper}{addVal}:0xff;
	  $cmpVal = (($cmpVal ^ $buttonField)|$buttonField); # all error,only one goto normal
	  $shash->{helper}{addVal} = $buttonField;   #store to handle changes
      push @event,"battery:". (($buttonField&0x80)?"low":"ok")if($cmpVal&0x80);
      push @event, "state:$btnName $state$target";
	  
	  $chnHash->{STATE} = $state.$target;   #handle channel manually, others to device
	  DoTrigger($btnName,"$state$target");

      if($id eq $dst) {  # Send Ack
        CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."0101".
                ($state =~ m/on/?"C8":"00")."00", 1, 0);#Actor simulation
      }
      $sendAck = ""; #todo why is this special?
    }
  }
  elsif($st eq "virtual"){#####################################################
    # possibly add code to count all acks that are paired. 
    if($msgType eq "02") {
      push @event, "ackFrom ".$name;
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
		}
		else {# just update datafields in storage
 	      my $bitLoc = ((hex($msgChn)-1)*2);#calculate bit location
 	      my $mask = 3<<$bitLoc;
 	      my $value = (hex($devState) &~$mask)|($msgState<<$bitLoc);
		  push @event,"color:".sprintf("%08X",$value);
 	      if ($chnHash){
 	        $shash = $chnHash;
 	        my %colorTable=("00"=>"off","01"=>"red","02"=>"green","03"=>"orange");
 	        my $actColor = $colorTable{$msgState};
 	        $actColor = "unknown" if(!$actColor);
		    CUL_HM_setRd($chnHash,"color",$actColor,$tn);
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
	    $sendAck = ""; ##no ack for those messages!
	  }
	}  
  } 
  elsif($st eq "motionDetector") { #####################################
    # Code with help of Bassem
    my $state;
    if(($msgType eq "10" ||$msgType eq "02") && $p =~ m/^0601(..)(..)/) {
	  my $err;
      ($state, $err) = ($1, hex($2));
	  my $cmpVal = defined($shash->{helper}{addVal})?
	                      $shash->{helper}{addVal}:0xff;
	  $cmpVal = (($cmpVal ^ $err)|$err); # all error,only one goto normal
	  $shash->{helper}{addVal} = $err;#store to handle changes
	  my $bright = hex($state);
      push @event, "brightness:".$bright    
	       if (ReadingsVal($name,"brightness","") != $bright);# post if changed
      push @event, "cover:".   (($err&0x0E)?"open" :"closed") if ($cmpVal&0x0E);        
	  push @event, "battery:". (($err&0x80)?"low"  :"ok"  )   if ($cmpVal&0x80);
    }
    elsif($msgType eq "41" && $p =~ m/^..(..)(..)(..)/) {
	  my($cnt, $bright,$nextTr) = (hex($1), hex($2),(hex($3)>>4));
      push @event, "state:motion";
      push @event, "motion:on$target"; #added peterp
      push @event, "motionCount:".$cnt."_next:".$nextTr;
      push @event, "brightness:".$bright    
	       if (ReadingsVal($name,"brightness","") != $bright);# post if changed
    }
    elsif($msgType eq "70" && $p =~ m/^7F(..)(.*)/) {
	  my($d1, $d2) = ($1, $2);
      push @event, 'devState_raw'.$d1.':'.$d2;
    }

    CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."0101${state}00",1,0)
      if($id eq $dst && $cmd ne "8002");  # Send AckStatus
	$sendAck = ""; #todo why is this special?
    
  } 
  elsif($st eq "smokeDetector") { #####################################
    #todo: check for correct msgType, see below
	#AckStatus : msgType=0x02 p(..)(..)(..) subtype=01, channel, state (1 byte)
	#Info Level: msgType=0x10 p(..)(..)(..) subtype=06, channel, state (1 byte)
	#Event:      msgType=0x41 p(..)(..)(..) channel   , unknown, state (1 byte)

    my $level = $1 if($p =~ m/01..(..)/);# todo: fancy incomplete way to parse an AckStatus
	if ($level) {
	  if ($level eq "C8"){
        push @event, "state:on";
        push @event, "smoke_detect:on$target";
      }elsif($level eq "01"){
        push @event, "state:all-clear";
	  }else{
	    push @event, "state:$level";#todo - maybe calculate the level in %
	  }
	}
    if ($msgType eq "10"){ #todo: why is the information in InfoLevel ignored?
      push @event, "state:alive";
    } 
	if($p =~ m/^00(..)$/) {
      push @event, "test:$1";
    }
    push @event, "SDunknownMsg:$p" if(!@event);
	
    CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src.($cmd eq "A001" ? "80":"00"),1,0)
      if($id eq $dst && $cmd ne "8002");  # Send Ack/Nack
	$sendAck = ""; #todo why is this special?

  } 
  elsif($st eq "threeStateSensor") { #####################################
    #todo: check for correct msgType, see below
	#Event:      msgType=0x41 p(..)(..)(..)     channel   , unknown, state
	#Info Level: msgType=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  msgType=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if($p =~ m/^(..)(..)(..)(..)?$/) {
      my ($b12, $b34, $state) = ($1, $2, $3);
	  my $err;
	  $err = hex($4) if(defined($4));
      my $chn = ($msgType eq "41")?$b12:$b34;
      # Multi-channel device: Switch to channel hash
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  
      
	  if ($msgType eq "02"||$msgType eq "10"){
	  	my $cmpVal = defined($shash->{helper}{addVal})?$shash->{helper}{addVal}:0xff;
	    $cmpVal = (defined($err))?(($cmpVal ^ $err)|$err):0; # all error,one normal
	    $shash->{helper}{addVal} = $err;#store to handle changes

		push @event, "alive:yes";
	    push @event, "battery:". (($err&0x80)?"low"  :"ok"  )  if($cmpVal&0x80);
		if ($model ne "HM-SEC-WDS"){	  
		  push @event, "cover:". (($err&0x0E)?"open" :"closed")if($cmpVal&0x0E);
		}
	  }

      my %txt;
      %txt = ("C8"=>"open", "64"=>"tilted", "00"=>"closed");
      %txt = ("C8"=>"wet",  "64"=>"damp",   "00"=>"dry")  # by peterp
                   if($model eq "HM-SEC-WDS");
      my $txt = $txt{$state};
      $txt = "unknown:$state" if(!$txt);
      push @event, "state:$txt";
	  push @event, "contact:$txt$target";

      CUL_HM_SendCmd($shash, $msgcnt."8002$id$src${chn}00",1,0)  # Send Ack
                             if($id eq $dst);
      $sendAck = ""; #todo why is this special?
    }
    push @event, "3SSunknownMsg:$p" if(!@event);
  } 
  elsif($model eq "HM-WDC7000" ||$st eq "THSensor") { ####################
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
    $sendAck = "";

  } 
  elsif($st eq "winMatic") {  ####################################
    
    if($msgType eq "10"){
      if ($p =~ m/^0601(..)(..)/) {
        my ($lst, $flg) = ($1, $2);
             if($lst eq "C8" && $flg eq "00") { push @event, "contact:tilted";
        } elsif($lst eq "FF" && $flg eq "00") { push @event, "contact:closed";
        } elsif($lst eq "FF" && $flg eq "10") { push @event, "contact:lock_on";
        } elsif($lst eq "00" && $flg eq "10") { push @event, "contact:movement_tilted";
        } elsif($lst eq "00" && $flg eq "20") { push @event, "contact:movement_closed";
        } elsif($lst eq "00" && $flg eq "30") { push @event, "contact:open";
        }
        CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."0101".$lst."00",1,0)  
          if($id eq $dst);# Send AckStatus
	    $sendAck = "";
	  }
	  elsif ($p =~ m/^0287(..)89(..)8B(..)/) {
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

  }
  elsif($st eq "keyMatic") {  ####################################
	#Info Level: msgType=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  msgType=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if(($msgType eq "10" && $p =~ m/^06/) ||
	   ($msgType eq "02" && $p =~ m/^01/)) {
	  $p =~ m/^..(..)(..)(..)/; 
      my ($chn,$val, $err) = ($1,hex($2), hex($3));
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

      my $cmpVal = defined($shash->{helper}{addVal})?$shash->{helper}{addVal}:0xff;
	  $cmpVal = (($cmpVal ^ $err)|$err); # all error,only one goto normal
	  $shash->{helper}{addVal} = $err;   #store to handle changes

      my $stErr = ($err >>1) & 0x7;      
      my $error = 'unknown_'.$stErr;
      $error = 'motor aborted'  if ($stErr == 2);
      $error = 'clutch failure' if ($stErr == 1);
      $error = 'none'           if ($stErr == 0);

      push @event, "unknown:" .  (($err&0x40) ? "40" :"")   if($cmpVal&0x40);
	  push @event, "battery:".   (($err&0x80) ? "low":"ok") if($cmpVal&0x80);
      push @event, "uncertain:" .(($err&0x30) ? "yes":"no") if($cmpVal&0x30);
      push @event, "error:" .    ($error)                   if($cmpVal&0x0E);
      my $state = ($err & 0x30) ? " (uncertain)" : "";
      push @event, "lock:"	.	(($val == 1) ? "unlocked" : "locked");
      push @event, "state:"	.	(($val == 1) ? "unlocked" : "locked") . $state;
    }
  }  
  else{#####################################
    ; # no one wants the message
  }
  #------------ parse for virtual destination     ------------------
  if (AttrVal($dname, "subType", "none") eq "virtual"){# see if need for answer
    if($msgType =~ m/^4./ && $p =~ m/^(..)/) {
      my ($recChn) = ($1);# button number/event count
	  my $recId = $src.$recChn;
	  for (my $cnt=1;$cnt<25;$cnt++)  {#need to check each channel
	    my $dChNo = sprintf("%02X",$cnt);
	    my $dChName = AttrVal($dname,"channel_".$dChNo,"");
		if (!$dChName){next;} # not channel provisioned
	    my @peerIDs = split(',',AttrVal($dChName,"peerIDs",""));
	    foreach my $pId (@peerIDs){
	      if ($pId eq $recId){ #match: we have to ack 
		    my $dChHash = CUL_HM_name2hash($dChName);
		    my $state = ReadingsVal($dChName,"virtActState","C8");
		    $state = ($state eq "00")?"C8":"00";
		    setReadingsVal($dChHash,"virtActState",$state,$tn);
		    setReadingsVal($dChHash,"virtActTrigger",$name,$tn);
            CUL_HM_SendCmd($dChHash,$msgcnt."8002".$dst.$src.'01'.$dChNo.
                  $state."00", 1, 0);
	      }
        }
	  }
	}
  }
  #------------ send default ACK if not applicable------------------
  #    ack if we are destination, anyone did accept the message (@event)
  #        parser did not supress 
  CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."00",1,0)  # Send Ack
      if(   ($id eq $dst) 			#are we adressee 
	     && ($msgType ne "02") 		#no ack for ack
		 && @event  				#only ack of we identified it
		 && ($sendAck eq "yes"));  	#sender requested ACK
	  
  #------------ process events ------------------
  push @event, "noReceiver:src:$src ($cmd) $p" if(!@event);

  my @changed;
  for(my $i = 0; $i < int(@event); $i++) {
    next if($event[$i] eq "");

    my ($vn, $vv) = split(":", $event[$i], 2);
    if($vn eq "state") {
      if($shash->{cmdSent} && $shash->{cmdSent} eq $vv) {
        delete($shash->{cmdSent}); # Skip second "on/off" after our own command
      } 
	  else {
        $shash->{STATE} = $vv;
        push @changed, $vv;
      }
    } 
	else {
      push @changed, ($vn.": ".(($vv)?$vv:"-"));
    }
	CUL_HM_setRd($shash,$vn,$vv,$tn);
  }
  $shash->{CHANGED} = \@changed;
  return $shash->{NAME} ;# shash could have changed to support channel
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
	# caution: !!! bitfield setting will zero the rest of the register
	#              if  less then a byte                    !!!!!!!!!!!
my %culHmRegDefine = (

  intKeyVisib  =>{a=>  2.7,s=>0.1,l=>0,min=>0  ,max=>1     ,c=>""         ,f=>""      ,u=>'bool',t=>'visibility of internal keys'},
  pairCentral  =>{a=> 10.0,s=>3.0,l=>0,min=>0  ,max=>16777215,c=>''       ,f=>""      ,u=>'dec' ,t=>'pairing to central'},
  #blindActuator mainly   
  driveUp      =>{a=> 13.0,s=>2.0,l=>1,min=>0  ,max=>6000.0,c=>'factor'   ,f=>10      ,u=>'s'   ,t=>"drive time up"},
  driveDown    =>{a=> 11.0,s=>2.0,l=>1,min=>0  ,max=>6000.0,c=>'factor'   ,f=>10      ,u=>'s'   ,t=>"drive time up"},
  driveTurn    =>{a=> 15.0,s=>1.0,l=>1,min=>0  ,max=>6000.0,c=>'factor'   ,f=>10      ,u=>'s'   ,t=>"fliptime up <=>down"},
  maxTimeFSh   =>{a=> 29.0,s=>1.0,l=>3,min=>0  ,max=>25.4  ,c=>'factor'   ,f=>10      ,u=>'s'   ,t=>"Short:max time first direction"},
  maxTimeFLg   =>{a=>157.0,s=>1.0,l=>3,min=>0  ,max=>25.4  ,c=>'factor'   ,f=>10      ,u=>'s'   ,t=>"Long:max time first direction"},
  #remote mainly                                                                       
  language     =>{a=>  7.0,s=>1.0,l=>0,min=>0  ,max=>1     ,c=>""         ,f=>""      ,u=>''    ,t=>"Language 0:English, 1:German"},
  stbyTime     =>{a=> 14.0,s=>1.0,l=>0,min=>1  ,max=>99    ,c=>""         ,f=>""      ,u=>'s'   ,t=>"Standby Time"},
  backOnTime   =>{a=> 14.0,s=>1.0,l=>0,min=>0  ,max=>255   ,c=>""         ,f=>""      ,u=>'s'   ,t=>"Backlight On Time"},
  backAtEvnt   =>{a=> 13.5,s=>0.3,l=>0,min=>0  ,max=>8     ,c=>""         ,f=>""      ,u=>''    ,t=>"Backlight at key=4,motion=2,charge=1"},
  longPress    =>{a=>  4.4,s=>0.4,l=>1,min=>0.3,max=>1.8   ,c=>'m10s3'    ,f=>""      ,u=>'s'   ,t=>"time to detect key long press"},
  msgShowTime  =>{a=> 45.0,s=>1.0,l=>1,min=>0.0,max=>120   ,c=>'factor'   ,f=>2       ,u=>'s'   ,t=>"Message show time(RC19). 0=always on"},
  #dimmer  mainly                                                                      
  ovrTempLvl   =>{a=> 50.0,s=>1.0,l=>1,min=>30 ,max=>100   ,c=>""         ,f=>""      ,u=>"degC",t=>"overtemperatur level"},
  redTempLvl   =>{a=> 52.0,s=>1.0,l=>1,min=>30 ,max=>100   ,c=>""         ,f=>""      ,u=>"degC",t=>"reduced temperatur recover"},
  redLvl       =>{a=> 53.0,s=>1.0,l=>1,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>"%"   ,t=>"reduced power level"},

  OnDlySh      =>{a=>  6.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:on delay "},
  OnTimeSh     =>{a=>  7.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:on time"},
  OffDlySh     =>{a=>  8.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:off delay"},
  OffTimeSh    =>{a=>  9.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:off time"},

  OffLevelSh   =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:PowerLevel Off"},
  OnMinLevelSh =>{a=> 16.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:minimum PowerLevel"},
  OnLevelSh    =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:PowerLevel on"},

  OffLevelKmSh =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>127.5 ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:OnLevel 127.5=locked"},
  OnLevelKmSh  =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>127.5 ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:OnLevel 127.5=locked"},
  OnRampOnSpSh =>{a=> 34.0,s=>1.0,l=>3,min=>0  ,max=>1     ,c=>'factor'   ,f=>200     ,u=>'s'   ,t=>"Short:Ramp On speed"},
  OnRampOffSpSh=>{a=> 35.0,s=>1.0,l=>3,min=>0  ,max=>1     ,c=>'factor'   ,f=>200     ,u=>'s'   ,t=>"Short:Ramp Off speed"},

  rampSstepSh  =>{a=> 18.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:rampStartStep"},
  rampOnTimeSh =>{a=> 19.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:rampOnTime"},
  rampOffTimeSh=>{a=> 20.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Short:rampOffTime"},
  dimMinLvlSh  =>{a=> 21.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:dimMinLevel"},
  dimMaxLvlSh  =>{a=> 22.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:dimMaxLevel"},
  dimStepSh    =>{a=> 23.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Short:dimStep"},

  OnDlyLg      =>{a=>134.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:on delay"},
  OnTimeLg     =>{a=>135.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:on time"},
  OffDlyLg     =>{a=>136.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:off delay"},
  OffTimeLg    =>{a=>137.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:off time"},

  OffLevelLg   =>{a=>143.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:PowerLevel Off"},
  OnMinLevelLg =>{a=>144.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:minimum PowerLevel"},
  OnLevelLg    =>{a=>145.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:PowerLevel on"},

  rampSstepLg  =>{a=>146.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:rampStartStep"},
  rampOnTimeLg =>{a=>147.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:off delay"},
  rampOffTimeLg=>{a=>148.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,t=>"Long:off delay"},
  dimMinLvlLg  =>{a=>149.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:dimMinLevel"},
  dimMaxLvlLg  =>{a=>150.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:dimMaxLevel"},
  dimStepLg    =>{a=>151.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:dimStep"},

  OffLevelKmLg =>{a=>143.0,s=>1.0,l=>3,min=>0  ,max=>127.5 ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:OnLevel 127.5=locked"},
  OnLevelKmLg  =>{a=>145.0,s=>1.0,l=>3,min=>0  ,max=>127.5 ,c=>'factor'   ,f=>2       ,u=>'%'   ,t=>"Long:OnLevel 127.5=locked"},
  OnRampOnSpLg =>{a=>162.0,s=>1.0,l=>3,min=>0  ,max=>1     ,c=>'factor'   ,f=>200     ,u=>'s'   ,t=>"Long:Ramp On speed"},
  OnRampOffSpLg=>{a=>163.0,s=>1.0,l=>3,min=>0  ,max=>1     ,c=>'factor'   ,f=>200     ,u=>'s'   ,t=>"Long:Ramp Off speed"},
  #tc
  BacklOnTime  =>{a=>5.0  ,s=>0.6,l=>0,min=>1  ,max=>25    ,c=>""         ,f=>''      ,u=>'s'   ,t=>"Backlight ontime"},
  BacklOnMode  =>{a=>5.6  ,s=>0.2,l=>0,min=>0  ,max=>1     ,c=>'factor'   ,f=>2       ,u=>'bool',t=>"Backlight mode 0=OFF, 1=AUTO"},
  BtnLock      =>{a=>15   ,s=>1  ,l=>0,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"Button Lock 0=OFF, 1=Lock"},
  DispTempHum  =>{a=>1.0  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"0=temp ,1=temp-humidity"},
  DispTempInfo =>{a=>1.1  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"0=actual ,1=setPoint"},
  DispTempUnit =>{a=>1.2  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"0=Celsius ,1=Fahrenheit"},
  MdTempReg    =>{a=>1.3  ,s=>0.2,l=>5,min=>0  ,max=>3     ,c=>''         ,f=>''      ,u=>''    ,t=>"0=MANUAL ,1=AUTO ,2=CENTRAL ,3=PARTY"},
  MdTempValve  =>{a=>2.6  ,s=>0.2,l=>5,min=>0  ,max=>2     ,c=>''         ,f=>''      ,u=>''    ,t=>"0=auto ,1=close ,2=open"},
  TempComfort  =>{a=>3    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'factor'   ,f=>2       ,u=>'C'   ,t=>"confort temp value"},
  TempLower    =>{a=>4    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'factor'   ,f=>2       ,u=>'C'   ,t=>"confort temp value"},
  PartyEndDay  =>{a=>98   ,s=>1  ,l=>6,min=>0  ,max=>200   ,c=>''         ,f=>''      ,u=>'d'   ,t=>"Party end Day"},
  PartyEndMin  =>{a=>97.7 ,s=>1  ,l=>6,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'min' ,t=>"Party end 0=:00, 1=:30"},
  PartyEndHr   =>{a=>97   ,s=>0.6,l=>6,min=>0  ,max=>23    ,c=>''         ,f=>''      ,u=>'h'   ,t=>"Party end Hour"},
  TempParty    =>{a=>6    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'factor'   ,f=>2       ,u=>'C'   ,t=>"Temperature for Party"},
  TempWinOpen  =>{a=>5    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'factor'   ,f=>2       ,u=>'C'   ,t=>"Temperature for Win open !chan 3 only!"},
  DecalDay     =>{a=>1.5  ,s=>0.3,l=>5,min=>0  ,max=>7     ,c=>''         ,f=>''      ,u=>'d'   ,t=>"Decalc weekday 0=Sat...6=Fri"},
  DecalHr      =>{a=>8.3  ,s=>0.5,l=>5,min=>0  ,max=>23    ,c=>''         ,f=>''      ,u=>'h'   ,t=>"Decalc hour"},
  DecalMin     =>{a=>8    ,s=>0.3,l=>5,min=>0  ,max=>50    ,c=>'factor'   ,f=>0.1     ,u=>'min' ,t=>"Decalc min"},
#Thermal-cc-VD
  ValveOffset  =>{a=>9    ,s=>0.5,l=>5,min=>0  ,max=>25    ,c=>''         ,f=>''      ,u=>'%'   ,t=>"Valve offset"},             # size actually 0.5
  ValveError   =>{a=>10   ,s=>1  ,l=>5,min=>0  ,max=>99    ,c=>''         ,f=>''      ,u=>'%'   ,t=>"Valve position when error"},# size actually 0.7
#output Unit
  ActTypeSh     =>{a=>36  ,s=>1  ,l=>3,min=>0  ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Short:Action type(LED or Tone)"},
  ActNumSh      =>{a=>37  ,s=>1  ,l=>3,min=>1  ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Short:Action Number"},
  IntenseSh     =>{a=>47  ,s=>1  ,l=>3,min=>10 ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Short:Volume - Tone channel only!"},
  
  ActTypeLg     =>{a=>164 ,s=>1  ,l=>3,min=>0  ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Long:Action type(LED or Tone)"},
  ActNumLg      =>{a=>165 ,s=>1  ,l=>3,min=>1  ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Long:Action Number"},
  IntenseLg     =>{a=>175 ,s=>1  ,l=>3,min=>10 ,max=>255   ,c=>''         ,f=>''      ,u=>''    ,t=>"Long:Volume - Tone channel only!"},
# keymatic secific register
  signal        =>{a=>3.4 ,s=>0.1,l=>0,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"Confirmation beep 0=OFF, 1=On"},
  signalTone    =>{a=>3.6 ,s=>0.2,l=>0,min=>0  ,max=>3     ,c=>''         ,f=>''      ,u=>'%'   ,t=>"0=low 1=mid 2=high 3=very high"},
  keypressSignal=>{a=>3.0 ,s=>0.1,l=>0,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"Keypress beep 0=OFF, 1=On"},
  holdTime      =>{a=>20  ,s=>1,  l=>1,min=>0  ,max=>8.16  ,c=>'factor'   ,f=>31.25   ,u=>'s'   ,t=>"Holdtime for door opening"},
  setupDir      =>{a=>22  ,s=>0.1,l=>1,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"Rotation direction for locking. ,0=right, 1=left"},
  setupPosition =>{a=>23  ,s=>1  ,l=>1,min=>0  ,max=>3000  ,c=>'factor'   ,f=>15      ,u=>'%'   ,t=>"Rotation angle neutral position"},
  angelOpen     =>{a=>24  ,s=>1  ,l=>1,min=>0  ,max=>3000  ,c=>'factor'   ,f=>15      ,u=>'%'   ,t=>"Door opening angle"},
  angelMax      =>{a=>25  ,s=>1  ,l=>1,min=>0  ,max=>3000  ,c=>'factor'   ,f=>15      ,u=>'%'   ,t=>"Angle locked"},
  angelLocked   =>{a=>26  ,s=>1  ,l=>1,min=>0  ,max=>3000  ,c=>'factor'   ,f=>15      ,u=>'%'   ,t=>"Angle Locked position"},
  ledFlashUnlocked=>{a=>31.3,s=>0.1,l=>1,min=>0,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"1=LED blinks when not locked"},
  ledFlashLocked=>{a=>31.6,s=>0.1,l=>1,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"1=LED blinks when locked"},
# sec_mdir
  evtFltrPeriod =>{a=>1.0 ,s=>0.4,l=>1,min=>0.5,max=>7.5   ,c=>'factor'   ,f=>2       ,u=>'s'   ,t=>"event filter period"},
  evtFltrNum    =>{a=>1.4 ,s=>0.4,l=>1,min=>1  ,max=>15    ,c=>''         ,f=>''      ,u=>''    ,t=>"sensitivity - read sach n-th puls"},
  minInterval   =>{a=>2.0 ,s=>0.3,l=>1,min=>0  ,max=>4     ,c=>''         ,f=>''      ,u=>''    ,t=>"minimum interval 0,15,20,60,120s"},
  captInInterval=>{a=>2.3 ,s=>0.1,l=>1,min=>0  ,max=>1     ,c=>''         ,f=>''      ,u=>'bool',t=>"capture within interval"},
  brightFilter  =>{a=>2.4 ,s=>0.4,l=>1,min=>0  ,max=>7     ,c=>''         ,f=>''      ,u=>''    ,t=>"brightness filter"},
  ledOnTime     =>{a=>34  ,s=>1  ,l=>1,min=>0  ,max=>1.275 ,c=>'factor'   ,f=>200     ,u=>'s'   ,t=>"LED ontime"},
  
  );
my %culHmRegGeneral = (
  intKeyVisib=>1,pairCentral=>1,
	);
my %culHmRegSupported = (
  remote=> {backOnTime=>1,backAtEvnt=>1,longPress=>1,msgShowTime=>1,},
  blindActuator=> {driveUp=>1, driveDown=>1 , driveTurn=>1,
                   maxTimeFSh =>1,
                   maxTimeFLg =>1,
                   OnDlySh=>1,  OnTimeSh=>1,  OffDlySh =>1,  OffTimeSh=>1,
                   OnDlyLg=>1,  OnTimeLg=>1,  OffDlyLg =>1,  OffTimeLg=>1,
  	   		       OffLevelSh =>1, OnLevelSh    =>1,
			       OffLevelLg =>1, OnLevelLg    =>1,
				   },
  dimmer=> {ovrTempLvl =>1,redTempLvl  =>1,redLvl       =>1,
            OnDlySh    =>1,OnTimeSh    =>1,OffDlySh     =>1,OffTimeSh  =>1,
            OnDlyLg    =>1,OnTimeLg    =>1,OffDlyLg     =>1,OffTimeLg  =>1,
			OffLevelSh =>1,OnMinLevelSh=>1,OnLevelSh    =>1,
			OffLevelLg =>1,OnMinLevelLg=>1,OnLevelLg    =>1,
            rampSstepSh=>1,rampOnTimeSh=>1,rampOffTimeSh=>1,dimMinLvlSh=>1,
            dimMaxLvlSh=>1,dimStepSh   =>1,
            rampSstepLg=>1,rampOnTimeLg=>1,rampOffTimeLg=>1,dimMinLvlLg=>1,
            dimMaxLvlLg=>1,dimStepLg   =>1,  
			},
  switch=> {OnTimeSh   =>1,OnTimeLg    =>1,OffTimeSh    =>1,OffTimeLg  =>1,
            OnDlySh    =>1,OnDlyLg     =>1,OffDlySh     =>1,OffDlyLg   =>1,
			},
  thermostat=>{	
			DispTempHum  =>1,DispTempInfo =>1,DispTempUnit =>1,MdTempReg   =>1,
			MdTempValve  =>1,TempComfort  =>1,TempLower    =>1,PartyEndDay =>1,
			PartyEndMin  =>1,PartyEndHr   =>1,TempParty    =>1,DecalDay    =>1,
			TempWinOpen  =>1,
			DecalHr      =>1,DecalMin     =>1, 
            BacklOnTime  =>1,BacklOnMode  =>1,BtnLock      =>1,
            ValveOffset  =>1,ValveError   =>1,
			},	
  outputUnit=>{
			OnDlySh   =>1,OnTimeSh  =>1,OffDlySh  =>1,OffTimeSh =>1,
			OnDlyLg   =>1,OnTimeLg  =>1,OffDlyLg  =>1,OffTimeLg =>1,
			ActTypeSh =>1,ActNumSh  =>1,IntenseSh =>1,
			ActTypeLg =>1,ActNumLg  =>1,IntenseLg =>1,
			},
  winMatic=>{			 
            OnTimeSh      =>1,OffTimeSh     =>1,OffLevelKmSh  =>1,
            OnLevelKmSh   =>1,OnRampOnSpSh  =>1,OnRampOffSpSh =>1,
            OnTimeLg      =>1,OffTimeLg     =>1,OffLevelKmLg  =>1,
            OnLevelKmLg   =>1,OnRampOnSpLg  =>1,OnRampOffSpLg =>1,
			},
  keyMatic=>{
			signal    =>1,signalTone=>1,keypressSignal=>1,
			holdTime  =>1,setupDir  =>1,setupPosition =>1,
			angelOpen =>1,angelMax  =>1,angelLocked   =>1,
			ledFlashUnlocked=>1,ledFlashLocked=>1,
			},
  dis4=> 	{language => 1,stbyTime => 1, #todo insert correct name
            },	
  motionDetector=>{
            evtFltrPeriod =>1,evtFltrNum    =>1,minInterval   =>1,
			captInInterval=>1,brightFilter  =>1,ledOnTime     =>1,
			},
);
##--------------- Conversion routines for register settings
my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111600);
sub 
CUL_HM_fltCvT($) # float -> config time
{  
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
sub 
CUL_HM_CvTflt($) # config time -> float
{
  my ($inValue) = @_;
  return ($inValue & 0x1f)*((sort {$a <=> $b} keys(%fltCvT))[$inValue >> 5]);
}


#define gets - try use same names as for set
my %culHmGlobalGets = (
  param      => "<param>",
  reg        => "<addr> ... <list> <peer>",
  regList    => "",
);
my %culHmSubTypeGets = (
  none4Type =>
        { "test"=>"" },
);
my %culHmModelGets = (
  none4Mod=>
        { "none"     => "",
        },
);

###################################
sub
CUL_HM_Get($@)
{
  my ($hash, @a) = @_;
  return "no get value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $devName = $attr{$name}{device};# get devName as protocol entity
  $devName = $name if (!$devName); # we control ourself if no chief available
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");
  my $mId = CUL_HM_getMId($hash);
  my $rxType = CUL_HM_getRxType($hash);

  my $class = AttrVal($devName, "hmClass", "");#relevant is the chief
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);

  my $devHash = CUL_HM_getDeviceHash($hash);
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
  my $id = CUL_HM_Id($hash->{IODev});

  #----------- now start processing --------------
  if($cmd eq "param") {  ######################################################
	my $val;
	$val = AttrVal($name, $a[2], "");
	$val = $hash->{READINGS}{$a[2]}{VAL}    if (!$val && $hash->{READINGS}{$a[2]});
	$val = AttrVal($devName, $a[2], "")     if (!$val);
	$val = $devHash->{READINGS}{$a[2]}{VAL} if (!$val && $devHash->{READINGS}{$a[2]});
	$val = $hash->{$a[2]}                   if (!$val && $hash->{$a[2]});
	$val = $devHash->{$a[2]}                if (!$val && $devHash->{$a[2]});
	$val = $hash->{helper}{$a[2]}           if((!$val)&& (ref($hash->{helper}{$a[2]}) ne "HASH"));
	$val = $devHash->{helper}{$a[2]}        if (!$val);

	return (defined ($val))?$val:"undefined";
  }
  elsif($cmd eq "reg") {  #####################################################
    my (undef,undef,$regReq,$list,$peerId) = @a;
	if ($regReq eq 'all'){
	  my @regArr = keys %culHmRegGeneral;
	  push @regArr, keys %{$culHmRegSupported{$st}} if($culHmRegSupported{$st}); 
	  
	  my @peers; # get all peers we have a reglist 
	  my @listWp; # list that require peers
	  foreach my $readEntry (keys %{$hash->{READINGS}}){
        my $regs = ReadingsVal($hash->{NAME},$readEntry,"");
	    if ($readEntry =~m /^RegL_/){ #this is a reg Reading "RegL_<list>:peerN
		  my $peer = substr($readEntry,8);
		  my $listP = substr($readEntry,6,1);
		  push(@peers,$peer)   if ($peer);
		  push(@listWp,$listP) if ($peer);
		}
	  }
	  
	  my @regValList; #storage of results
	  foreach my $regName (@regArr){
	    my $regL  = $culHmRegDefine{$regName}->{l};
		my @peerExe = (grep (/$regL/,@listWp))?@peers:("00000000");
		foreach my $peer(@peerExe){
		  next if($peer eq "");
	      my $regVal = CUL_HM_getRegFromStore($name,$regName,0,$peer); #determine peerID
	      push @regValList,"List:".$regL.
		         " Peer:".$peer.
		         "\t".$regName.
				 ":\tvalue:". $regVal."\n" if ($regVal ne 'unknown') ; 
		}
	  }
	  return $name." type:".$st." - \n".join("",sort(@regValList));
	}
	else{
      my $regVal = CUL_HM_getRegFromStore($name,$regReq,$list,$peerId);
	  return ($regVal eq "invalid")? "Value not captured" 
	                             : "0x".sprintf("%X",$regVal)." dec:".$regVal;
	}
  }
  elsif($cmd eq "regList") {  #################################################
    my @arr = keys %culHmRegGeneral ;
	push @arr, keys %{$culHmRegSupported{$st}} if($culHmRegSupported{$st});  
    my $info = $st." - \n";	
	foreach my $regName (@arr){
	  my $reg  = $culHmRegDefine{$regName};	  
	  $info .= $regName."\trange:". $reg->{min}." to ".$reg->{max}.$reg->{u}.
	          ((($reg->{l} == 3)||($reg->{l} == 4))?"\tpeer required":"")
			  ."\t: ".$reg->{t}."\n";
	}
	return $info;
  }

  Log GetLogLevel($name,4), "CUL_HM get $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($devHash) if ($rxType & 0x03);#burst/all
  return "";
}
###################################
my %culHmGlobalSets = (
  raw      => "data ...",
  reset    => "",
  pair     => "",
  unpair   => "",
  sign     => "[on|off]",
  regRaw   =>"[List0|List1|List2|List3|List4|List5|List6] <addr> <data> ... <PeerChannel>",
  statusRequest => "",
  getpair       => "", 
  getdevicepair => "",
  getRegRaw     =>"[List0|List1|List2|List3|List4|List5|List6] ... <PeerChannel>",
  getConfig     => "",
  regSet        =>"<regName> <value> ... <peerChannel>",
  virtual       =>"<noButtons>",
  actiondetect  =>"<hh:mm|off>",
);
my %culHmSubTypeSets = (
  switch =>
        { "on-for-timer"=>"sec", "on-till"=>"time",
		  on=>"", off=>"", toggle=>"" },
  dimmer =>
        { "on-for-timer"=>"sec", , "on-till"=>"time",
		  on=>"", off=>"", toggle=>"", pct=>"", stop=>""},
  blindActuator=>
        { on=>"", off=>"", toggle=>"", pct=>"", stop=>""},
  remote =>
        { devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",},
  pushButton =>										
        { devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",},
  virtual => 
        { raw      => "data ...",
		  devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
		  press      => "[long|short]...",
		  virtual    =>"<noButtons>",}, #redef necessary for virtual
  smokeDetector =>
        { test => "", "alarmOn"=>"", "alarmOff"=>"", },
  winMatic =>{matic  => "<btn>",
              read   => "<btn>",
              keydef => "<btn> <txt1> <txt2>",
              create => "<txt>" },
  keyMatic =>{lock   =>"",
  	          unlock =>"[sec] ...",
  	          open   =>"[sec] ...",
  	          inhibit=>"[on|off]",
  },

);
my %culHmModelSets = (
  "HM-CC-TC"=>{ 
          devicepair    => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
          "day-temp"     => "temp",
          "night-temp"   => "temp",
          "party-temp"   => "temp",
          "desired-temp" => "temp", # does not work - only in manual mode??
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
  "HM-CC-VD"=>{ 
          valvePos     => "position",},
  "HM-RC-19"=>    {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
  "HM-RC-19-B"=>  {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
  "HM-RC-19-SW"=> {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
  "HM-PB-4DIS-WM"=>{
	      text      => "<btn> [on|off] <txt1> <txt2>",},
  "HM-OU-LED16" =>{
		  led    =>"[off|red|green|orange]" ,
		  ilum   =>"[0-15] [0-127]" },
  "HM-OU-CFM-PL"=>{
	      led       => "<color>[,<color>..]",
		  playTone  => "<MP3No>[,<MP3No>..]",},
);
##############################################
sub
CUL_HM_getMId($)
{#in: hash(chn or dev) out:model key (key for %culHmModel). 
 # Will store result in device helper
  my ($hash) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  my $mId = $hash->{helper}{mId};
  if (!$mId){   
    my $model = AttrVal($hash->{NAME}, "model", "");
    foreach my $mIdKey(keys%culHmModel){
      if ($culHmModel{$mIdKey}{name} && $culHmModel{$mIdKey}{name} eq $model){
	    $mId = $hash->{helper}{mId} = $mIdKey;
		return $mIdKey;
	  }
    }
  }
  return $mId;
}
##############################################
sub
CUL_HM_getRxType($)
{ #in:hash(chn or dev) out:binary coded Rx type 
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
sub
CUL_HM_getFlag($)
{#msgFlag set to 'A0' for normal and 'B0' for burst devices
 # currently not supported is the wakeupflag since it is hardly used
  my ($hash) = @_;
  return (CUL_HM_getRxType($hash) & 0x02)?"B0":"A0"; #set burst flag
}

sub
CUL_HM_Set($@)
{
  my ($hash, @a) = @_;
  my ($ret, $tval, $rval); #added rval for ramptime by unimatrix

  return "no set value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $devName = AttrVal($name,    "device" , $name);# devName as protocol entity
  my $st      = AttrVal($devName, "subType", "");
  my $md      = AttrVal($devName, "model"  , "");
  my $class   = AttrVal($devName, "hmClass", "");#relevant is the device
  
  my $rxType = CUL_HM_getRxType($hash);
  my $flag = CUL_HM_getFlag($hash); #set burst flag
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);

  my $devHash = CUL_HM_getDeviceHash($hash);

  my $h = $culHmGlobalSets{$cmd} if($st ne "virtual");
  $h = $culHmSubTypeSets{$st}{$cmd} if(!defined($h) && $culHmSubTypeSets{$st});
  $h = $culHmModelSets{$md}{$cmd}   if(!defined($h) && $culHmModelSets{$md});
  my @h;
  @h = split(" ", $h) if($h);

  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
    $cmd = "pct";
  } 
  elsif(!defined($h)) {
    my @arr;
    @arr = keys %culHmGlobalSets if($st ne "virtual");
    push @arr, keys %{$culHmSubTypeSets{$st}} if($culHmSubTypeSets{$st});
    push @arr, keys %{$culHmModelSets{$md}} if($culHmModelSets{$md});
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

  my $id = CUL_HM_Id($hash->{IODev});
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);

  if($cmd eq "raw") {  ##################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
	$state = "";
    for (my $i = 2; $i < @a; $i++) {
      CUL_HM_PushCmdStack($hash, $a[$i]);
    }
  } 
  elsif($cmd eq "reset") { ############################################
	CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  } 
  elsif($cmd eq "pair") { #############################################
    return "pair is not enabled for this type of device, ".
                "use set <IODev> hmPairForSec"
        if($class eq "sender");
	$state = "";
    my $serialNr = AttrVal($name, "serialNr", undef);
    return "serialNr is not set" if(!$serialNr);
    CUL_HM_PushCmdStack($hash,"++A401".$id."000000010A".unpack("H*",$serialNr));
    $hash->{hmPairSerial} = $serialNr;
  } 
  elsif($cmd eq "unpair") { ###########################################
    CUL_HM_pushConfig($hash, $id, $dst, 0,0,0,0, "02010A000B000C00");
    $state = "";
  } 
  elsif($cmd eq "sign") { ############################################
    CUL_HM_pushConfig($hash, $id, $dst, $chn,0,0,$chn,
                    "08" . ($a[2] eq "on" ? "01":"02"));
	$state = "";
  }
  elsif($cmd eq "statusRequest") { ############################################
    my @chnIdList = CUL_HM_getAssChnId($name);
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
	my @chnIdList = CUL_HM_getAssChnId($name);
	foreach my $channel (@chnIdList){
	  my $chnHash = CUL_HM_id2hash($channel);
	  CUL_HM_getConfig($hash,$chnHash,$id,$dst,substr($channel,6,2));
	}
	$state = "";
  } 
  elsif($cmd eq "regRaw" ||$cmd eq "getRegRaw") { #############################
    my ($list,$addr,$data,$peerID);
	$state = "";
	($list,$addr,$data,$peerID) = ($a[2],hex($a[3]),hex($a[4]),$a[5])
	                               if ($cmd eq "regRaw");
	($list,$peerID) = ($a[2],$a[3])if ($cmd eq "getRegRaw");
	$list =~ s/List/0/;# convert Listy to 0y
	# as of now only hex value allowed check range and convert

	$chn = "00" if ($list eq "00");
	my $pSc = substr($peerID,0,4); #helper for shortcut spread
    if     ($pSc eq 'self'){$peerID=$dst.sprintf("%02X",'0'.substr($peerID,4));
	}elsif ($pSc eq 'fhem'){$peerID=$id .sprintf("%02X",'0'.substr($peerID,4));
	}elsif($peerID eq 'all'){;# keep all
	}else                  {$peerID = CUL_HM_Name2Id($peerID);
	}
	$peerID = $peerID.((length($peerID) == 6)?"01":"");# default chn 1, if none
	$peerID = "00000000" if (length($peerID) != 8 && $peerID ne 'all');# none?

	my $peerChn = substr($peerID,6,2);# have to split chan and id
	$peerID = substr($peerID,0,6);

	if($cmd eq "getRegRaw"){
	  if ($list eq "00"){
	    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000');
	  }
	  else{# other lists are per channel
	    my @chnIdList = CUL_HM_getAssChnId($name);
        foreach my $channel (@chnIdList){
		  my $chnNo = substr($channel,6,2);
		  if ($list =~m /0[34]/){#getPeers to see if list3 is available 
			CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chnNo.'03');
			my $chnHash = CUL_HM_id2hash($channel);
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
	else{
	  # as of now only hex value allowed check range and convert
	  return "invalid address or data" if ($addr > 255 || $data > 255);
	  my $addrData = uc(sprintf("%02x%02x",$addr,$data));
      CUL_HM_pushConfig($hash,$id,$dst,$chn,$peerID,$peerChn,$list,$addrData);
	}
  } 
  elsif($cmd eq "regSet") { ###################################################
    #set <name> regSet <regName> <value> <peerChn> 
	my ($regName,$data,$peerChnIn) = ($a[2],$a[3],$a[4]);
	$state = "";
    if (!$culHmRegSupported{$st}{$regName} && !$culHmRegGeneral{$regName} ){
      my @arr = keys %culHmRegGeneral ;
	  push @arr, keys %{$culHmRegSupported{$st}} if($culHmRegSupported{$st});
	  return "supported register are ".join(" ",sort @arr);
	}
	   
    my $reg  = $culHmRegDefine{$regName};
	return $st." - ".$regName            # give some help
	       ." range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
		   .(($reg->{l} == 3)?" peer required":"")." : ".$reg->{t}."\n"
		        if ($data eq "?");
	return "value:".$data." out of range for Reg \"".$regName."\""
	        if ($data < $reg->{min} ||$data > $reg->{max});

	my $conversion = $reg->{c};
	if (!$conversion){;# do nothing
	}elsif($conversion eq "factor"){$data *= $reg->{f};# use factor
	}elsif($conversion eq "fltCvT"){$data = CUL_HM_fltCvT($data);
	}elsif($conversion eq "m10s3") {$data = $data*10-3;
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
	  
	  my $pSc = substr($peerID,0,4); #helper for shortcut spread
      if     ($pSc eq 'self'){$peerID=$dst.sprintf("%02X",'0'.substr($peerID,4));
	  }elsif ($pSc eq 'fhem'){$peerID=$id .sprintf("%02X",'0'.substr($peerID,4));
	  }else                  {$peerID = CUL_HM_Name2Id($peerID);
	  }

 	  $peerChn = ((length($peerID) == 8)?substr($peerID,6,2):"01");
      $peerID = substr($peerID,0,6);	
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
	  my $curVal = CUL_HM_getRegFromStore(CUL_HM_id2Name($dst.$lChn),
	                                      $addr,$list,$peerID.$peerChn);
	  return "cannot read current value for Bitfield - retrieve Data first" 
	             if (!$curVal);
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
  elsif($cmd eq "on") { ###############################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.'C80000');
  } 
  elsif($cmd eq "off") { ##############################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.'000000');
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
  } 
  elsif($cmd eq "toggle") { ###################################################
    $hash->{toggleIndex} = 1 if(!$hash->{toggleIndex});
    $hash->{toggleIndex} = (($hash->{toggleIndex}+1) % 128);
    CUL_HM_PushCmdStack($hash, sprintf("++%s3E%s%s%s40%s%02X",$flag,$id, $dst,
                                      $dst, $chn, $hash->{toggleIndex}));                                     
  }
  elsif($cmd eq "lock") { ###################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800100FF');	# LEVEL_SET
  }
  elsif($cmd eq "unlock") { ###################################################
  	$tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800101'.$delay);# LEVEL_SET
  }
  elsif($cmd eq "open") { ###################################################
  	$tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'8001C8'.$delay);# OPEN
	$state = "";
  }
  elsif($cmd eq "inhibit") { ###############################################
  	return "$a[2] is not on or off" if($a[2] !~ m/^(on|off)$/);
 	my $val = ($a[2] eq "on") ? "01" : "00";
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$val.'01');	# SET_LOCK
	$state = "";
  }
  elsif($cmd eq "pct") { ######################################################
    $a[1] = 100 if ($a[1] > 100);
    $tval = CUL_HM_encodeTime16(((@a > 2)&&$a[2]!=0)?$a[2]:85825945);# onTime   0.0..85825945.6, 0=forever
    $rval = CUL_HM_encodeTime16((@a > 3)?$a[3]:2.5);     # rampTime 0.0..85825945.6, 0=immediate
    CUL_HM_PushCmdStack($hash, 
	    sprintf("++%s11%s%s02%s%02X%s%s",$flag,$id,$dst,$chn,$a[1]*2,$rval,$tval));
  } 
  elsif($cmd eq "stop") { #####################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
  } 
  elsif($cmd eq "text") { #############################################
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
  elsif($cmd eq "display") { ################################################## 
	my (undef,undef,undef,$t,$c,$u,$snd,$blk,$symb) = @_;
	return "cmd only possible for device or its display channel"
	       if (length($hash->{DEF}) ne 6 && $chn ne 18);
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
        CUL_HM_PushCmdStack($hash,sprintf("++%s11%s%s8100%s",
		                                   $flag,$id,$dst,$col4all));
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
    CUL_HM_setRd($hash,$cmd,$a[2],"");
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
  elsif($cmd eq "desired-temp") { ##################
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_PushCmdStack($hash,
                sprintf("++%s11%s%s0202%s",$flag,$id,$dst,$temp));
  } 
  elsif($cmd =~ m/^(day|night|party)-temp$/) { ##################
    my %tt = (day=>"03", night=>"04", party=>"06");
    my $tt = $tt{$1};
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,5, "$tt$temp");      # List 5
  } 
  elsif($cmd =~ m/^tempList(...)/) { ##################################
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
      my $temp = CUL_HM_convTemp($a[$idx+1]);
      return $temp if(length($temp) > 2);
      $data .= sprintf("%02X%02X%02X%s", $addr, $h*6+($m/10), $addr+1, $temp);
      $addr += 2;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{HOUR} = $h;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{MINUTE} = $m;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{TEMP} = $a[$idx+1];
      $msg .= sprintf(" %02d:%02d %.1f", $h, $m, $a[$idx+1]);
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,$list, $data);

    my $vn = "tempList$wd";
	CUL_HM_setRd($hash,$vn,$msg,'');
  } 
  elsif($cmd eq "valvePos") { ##################
    my $vp = ($a[2]+0.5)*2.56;
    my $d1 = 0;
    CUL_HM_PushCmdStack($hash,sprintf("++A258%s%s%02X%02X",$id,$dst,$d1,$vp));
  } 
  elsif($cmd eq "matic") { ##################################### 
    # Trigger pre-programmed action in the winmatic. These actions must be
    # programmed via the original software.
    CUL_HM_PushCmdStack($hash,
        sprintf("++%s3E%s%s%s40%02X%s", $flag,$id, $dst, $id, $a[2], $chn));
  } 
  elsif($cmd eq "create") { ###################################
    CUL_HM_PushCmdStack($hash, 
        sprintf("++%s01%s%s0101%s%02X%s",$flag,$id, $dst, $id, $a[2], $chn));
    CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s0104%s%02X%s", $id, $dst, $id, $a[2], $chn));
  } 
  elsif($cmd eq "read") { ###################################
    return "read is discontinued since duplicate.\n".
	       "please use getRegRaw instead. Syntax getRegRaw List3 fhem<btn> \n".
		   "or getConfig for a complete configuratin list";
  } 
  elsif($cmd eq "keydef") { #####################################
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
    CUL_HM_SendCmd($hash, sprintf("++9440%s%s00%02X",$dst,$dst,$testnr), 1, 0);
  } 
  elsif($cmd =~ m/alarm(.*)/) { ###############################################
    CUL_HM_SendCmd($hash, sprintf("++9441%s%s01%s",
        $dst,$dst, $1 eq "On" ? "0BC8" : "0C01"), 1, 0);
  } 
  elsif($cmd eq "virtual") { ##################################################
  	$state = "";
    my (undef,undef,$maxBtnNo) = @a;
	return "please give a number between 1 and 255"
	   if ($maxBtnNo < 1 ||$maxBtnNo > 255);# arbitrary - 255 should be max
    return $name." already defines as ".$attr{$name}{subType}
	   if ($attr{$name}{subType} && $attr{$name}{subType} ne "virtual");
    $attr{$name}{subType} = "virtual";
    $attr{$name}{hmClass} = "sender";
    $attr{$name}{model}   = "virtual_".$maxBtnNo;
    my $devId = $hash->{DEF};
    for (my $btn=1;$btn <= $maxBtnNo;$btn++){
	  my $chnName = $name."_Btn".$btn;
	  my $chnId = $devId.sprintf("%02X",$btn);
	  DoTrigger("global",  "UNDEFINED $chnName CUL_HM $chnId")
		  if (!$modules{CUL_HM}{defptr}{$chnId});
	}
	foreach my $channel (keys %{$attr{$name}}){# remove higher numbers
	  my $chNo = $1 if($channel =~ m/^channel_(.*)/);
	  CommandDelete(undef,$attr{$name}{$channel})
	        if (hex($chNo) > $maxBtnNo);
	}
  }
  elsif($cmd eq "actiondetect"){
    $state = "";
    my (undef,undef,$cyctime) = @a;
    return ($cyctime eq 'off')?CUL_HM_ActDel($dst):CUL_HM_ActAdd($dst,$cyctime);
  }
  elsif($cmd eq "press") { ####################################################
    my (undef,undef,$mode) = @a;
    my ($srcId,$srcChn) = ($1,$2) if ($hash->{DEF} =~ m/(......)(..)/);
	return "invalid channel:".$srcId.$srcChn if (!$srcChn);
    my $rcvId = "000000"; #may have to change
	my $btn = sprintf("%02X",$srcChn+(($mode && $mode eq "long")?64:0));
	my $pressCnt = (!$hash->{helper}{count})?1:$hash->{helper}{count}+1;
	$pressCnt %= 256;
	my @peerList;
	foreach my $peer (sort(split(',',AttrVal($name,"peerList","")))) {
	  $peer =~ s/ .*//;
	  push (@peerList,substr(CUL_HM_Name2Id($peer),0,6));
	}
	my $oldPeer; # only once to device, not channel!
	 
	foreach my $peer (sort @peerList){
	  next if ($oldPeer eq $peer);

	  my $peerHash = $modules{CUL_HM}{defptr}{$peer};
	  my $peerSt = AttrVal($peerHash->{NAME}, "subType", "");
	  my $peerFlag = ($peerSt ne "keyMatic") ? "A4" : "B4"; 
      CUL_HM_PushCmdStack($hash, sprintf("++%s40%s%s%s%02X",
	                 $peerFlag,$srcId,$peer,$btn,$pressCnt));
	  $oldPeer = $peer;
	}

	CUL_HM_PushCmdStack($hash, sprintf("++%s40%s000000%s%02X",
	               $flag,$srcId,$btn,$pressCnt))if (!@peerList);
	$hash->{helper}{count}=$pressCnt;
  } 
  elsif($cmd eq "devicepair") { ###############################################
    #devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]"
	my ($bNo,$peerN,$single,$set,$target) = ($a[2],$a[3],$a[4],$a[5],$a[6]);
	$state = "";
	return "$bNo is not a button number" if(($bNo < 1) && !$chn);
    my $peerHash = $defs{$peerN} if ($peerN);
    return "$peerN not a CUL_HM device" 
	      if(!$peerHash ||$peerHash->{TYPE} ne "CUL_HM");
    return "$single must be single or dual" 
	      if(defined($single) && (($single ne"single") &&($single ne"dual")));  
    return "$set must be set or unset" 
	      if(defined($set) && (($set ne"set") &&($set ne"unset")));  
    return "$target must be [actor|remote|both]" 
	      if(defined($target) && (($target ne"actor") &&
		     ($target ne"remote")&&($target ne"both")));  
	return "use climate chan to pair TC" if($md eq "HM-CC-TC" &&$chn ne "02");
	$single = ($single eq "single")?1:"";#default to dual
	$set = ($set eq "unset")?0:1;

	my ($b1,$b2,$nrCh2Pair);
	$b1 = ($isChannel) ? hex($chn):sprintf("%02X",$bNo);
	$b1 = $b1*2 - 1 if(!$single && !$isChannel);
	if ($single){ 
        $b2 = $b1;
	    $nrCh2Pair = 1;
	}
	else{
	    $b2 = $b1 + 1;
	    $nrCh2Pair = 2;
	}
	my $cmd = ($set)?"01":"02";# do we set or remove?

    my $peerDst = $peerHash->{DEF};

    my $peerChn = "01";
    if(length($peerDst) == 8) { # shadow switch device for multi-channel switch
      ($peerDst,$peerChn) = ($1,$2) if($peerDst =~ m/(......)(..)/);
      $peerHash = $modules{CUL_HM}{defptr}{$peerDst};
    }

    # First the remote (one loop for on, one for off)
	if (!$target || $target eq "remote" || $target eq "both"){
      for(my $i = 1; $i <= $nrCh2Pair; $i++) {
        my $b = ($i==1 ? $b1 : $b2);		
  	    if ($st eq "virtual"){
		  my $btnName = CUL_HM_id2Name($dst.sprintf("%02X",$b));
		  return "button ".$b." not defined for virtual remote ".$name
		      if (!defined $attr{$btnName});
		  my $peerlist = $attr{$btnName}{peerList};
		  $peerlist = "" if (!$peerlist);
		  my $repl = CUL_HM_id2Name($peerDst.$peerChn).",";
  	      $peerlist =~ s/$repl//;#avoid duplicate
  	      $peerlist.= $repl if($set == 1);
		  $attr{$btnName}{peerList} = $peerlist;
		  delete $attr{$btnName}{peerList} if (!$peerlist);
	    }
		else{
		  my $bStr = sprintf("%02X",$b);
  	      CUL_HM_PushCmdStack($hash, 
  	              "++".$flag."01${id}${dst}${bStr}$cmd${peerDst}${peerChn}00");
  	      CUL_HM_pushConfig($hash,$id, $dst,$b,$peerDst,hex($peerChn),4,"0100")
				   if($md ne "HM-CC-TC");
	    }
      }
	}
	if (!$target || $target eq "actor" || $target eq "both"){
	  if (AttrVal( CUL_HM_id2Name($peerDst), "subType", "") eq "virtual"){
		my $peerIDs = AttrVal($peerN,"peerIDs","");
	    my $pId = $dst.sprintf("%02X",$b1);
		$peerIDs .= $pId."," if($peerIDs !~ m/$pId,/);
        $attr{$peerN}{peerIDs} = $peerIDs; 
		my $peerList = "";
		foreach my$tmpId (split(",",$peerIDs)){
		  $peerList .= CUL_HM_id2Name($tmpId);
		}
		$attr{$peerN}{peerList} = $peerList;
	  }
	  else{
	    my $peerFlag = CUL_HM_getFlag($peerHash);
        CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",
            $peerFlag,$id,$peerDst,$peerChn,$cmd,$dst,$b2,$b1 ));
	  }
	}
    $devHash = $peerHash; # Exchange the hash, as the switch is always alive.
  }

  $hash->{STATE} = $state if($state); 
  Log GetLogLevel($name,3), "CUL_HM set $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($devHash) if($rxType & 0x03);#all/burst
  return "";
}

###################################
sub
CUL_HM_infoUpdtDevData($$$){
  my($name,$hash,$p) = @_;
  my($fw,$mId,$serNo,$stc,$devInfo) = ($1,$2,$3,$4,$5) 
	                   if($p =~ m/(..)(.{4})(.{20})(.{2})(.*)/);
  
  my $model = $culHmModel{$mId}{name} ? $culHmModel{$mId}{name}:"unknown";
  $attr{$name}{model}    = $model;
  my $dp = $culHmDevProps{$stc};
  $attr{$name}{subType}  = $dp ? $dp->{st} : "unknown";
  $attr{$name}{hmClass}  = $dp ? $dp->{cl} : "unknown";
  $attr{$name}{serialNr} = pack('H*',$serNo);
  $attr{$name}{firmware} = 
        sprintf("%d.%d", hex(substr($p,0,1)),hex(substr($p,1,1)));
  $attr{$name}{devInfo}  = $devInfo;
  
  delete $hash->{helper}{rxType};
  CUL_HM_getRxType($hash); #will update rxType
  $mId = CUL_HM_getMId($hash);# set helper valiable and use result 
  
  # autocreate undefined channels  
  my @chanTypesList = split(',',$culHmModel{$mId}{chn});
  foreach my $chantype (@chanTypesList){
    my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
	my $chnNoTyp = 1;
	for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
	  my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
	  if (!$modules{CUL_HM}{defptr}{$chnId}){
        my $chnName = $name."_".$chnTpName.(($chnStart == $chnEnd)?
	                            '':'_'.sprintf("%02d",$chnNoTyp));
	    DoTrigger("global",  'UNDEFINED '.$chnName.' CUL_HM '.$chnId);
      }
	  $attr{CUL_HM_id2Name($chnId)}{model} = $model;
	  $chnNoTyp++;
	}
  }
  if ($culHmModel{$mId}{cyc}){
    CUL_HM_ActAdd($hash->{DEF},$culHmModel{$mId}{cyc});
  }

}
###################################
sub
CUL_HM_Pair(@)
{
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

  } elsif($dst ne $id) {
    return "" ;
	
  } elsif($cmd eq "0400") {     # WDC7000
    return "" ;

  } elsif($iohash->{hmPairSerial}) {
    delete($iohash->{hmPairSerial});
  }
  
  my ($idstr, $s) = ($id, 0xA);
  $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;
  CUL_HM_pushConfig($hash, $id, $src,0,0,0,0, "0201$idstr");
  CUL_HM_SendCmd($hash, shift @{$hash->{cmdStack}}, 1, 1);

  return "";
}
###################################
sub
CUL_HM_getConfig($$$$$){
  my ($hash,$chnhash,$id,$dst,$chn) = @_;
  my $flag = CUL_HM_getFlag($hash);
  
  foreach my $readEntry (keys %{$chnhash->{READINGS}}){
	if ($readEntry =~ m/^RegL_/){#remove old lists, no longer valid
	  delete $chnhash->{READINGS}{$readEntry};
	}
  }
  #get Peer-list in any case - it is part of the config
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
		no warnings;# know that lchan may be followed by a 'p' causing a warning
	    $chnValid = 1 if (int($lchn) == hex($chn));
		use warnings;
	    last if ($chnValid);
      }
	}
	#$listNo,$chnValid $peerReq  
	if ($chnValid){# yes, we will go for a list
	  if ($peerReq){# need to get the peers first
#        CUL_HM_PushCmdStack($hash,sprintf("++%s01%s%s%s03",$flag,$id,$dst,$chn));
        $chnhash->{helper}{getCfgList} = "all";# peers first
        $chnhash->{helper}{getCfgListNo} = $listNo;
	  }
	  else{
        CUL_HM_PushCmdStack($hash,sprintf("++%s01%s%s%s0400000000%02X",$flag,$id,$dst,$chn,$listNo));
	  }
	}	
  }
 }
###################-------send related --------################
sub
CUL_HM_SendCmd($$$$)
{
  my ($hash, $cmd, $sleep, $waitforack) = @_;
  my $io = $hash->{IODev};
  select(undef, undef, undef, 0.1) if($io->{TYPE} ne 'HMLAN');
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
	
  $cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6,$7));
  CUL_HM_responseSetup($hash,$cmd,$waitforack);
}
###################################
sub
CUL_HM_responseSetup($$$)
{#store all we need to handle the response
 #setup repeatTimer and cmdStackControll
  my ($hash,$cmd,$waitForAck) =  @_;
  my ($msgId, $msgType,$dst,$p) = ($2,$4,$6,$7)
      if ($cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/);
  my ($chn,$subType) = ($1,$2) if($p =~ m/^(..)(..)/); 
  my $rTo = 1.5; #default rsponse timeout
  if ($msgType eq "01" && $subType){ 
    if ($subType eq "03"){ #PeerList-------------
  	  #--- remember request params in device level
  	  $hash->{helper}{respWait}{Pending} = "PeerList";
  	  $hash->{helper}{respWait}{forChn} = substr($p,0,2);#channel info we await
      
      # define timeout - holdup cmdStack until response complete or timeout
  	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
  	  #--- remove readings in channel
  	  my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"}; 
  	  $chnhash = $hash if (!$chnhash);
  	  $chnhash->{READINGS}{peerList}{VAL}="";#empty old list
	  return;
    }
    elsif($subType eq "04"){ #RegisterRead-------
      my ($peerID, $list) = ($1,$2) if ($p =~ m/..04(........)(..)/);
	  $peerID = ($peerID ne "00000000")?CUL_HM_id2Name($peerID):"";
	  $peerID =~ s/ /_/g;#subs blanks
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending} = "RegisterRead";
	  $hash->{helper}{respWait}{forChn} = $chn;
	  $hash->{helper}{respWait}{forList}= $list;
	  $hash->{helper}{respWait}{forPeer}= $peerID;# this is the HMid + channel
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+$rTo,"CUL_HM_respPendTout","respPend:$dst", 0);
	  #--- remove channel entries that will be replaced
      my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
      $chnhash = $hash if(!$chnhash);   

	  $peerID ="" if($list !~ m/^0[34]$/);
	  #empty val since reading will be cumulative 
      $chnhash->{READINGS}{"RegL_".$list.":".$peerID}{VAL}=""; 
      delete ($chnhash->{READINGS}{"RegL_".$list.":".$peerID}{TIME}); 
	  return;
    }
    elsif($subType eq "0E"){ #StatusReq----------
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending} = "StatusReq";
	  $hash->{helper}{respWait}{forChn} = $chn;
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
	  return;
    }
  }
  if ($waitForAck){
    my $iohash = $hash->{IODev};
    #$hash->{helper}{respWait}{Pending}= "Ack";
    $hash->{helper}{respWait}{cmd}    = $cmd;
    $hash->{helper}{respWait}{msgId}  = $msgId; #msgId we wait to ack
    $hash->{helper}{respWait}{reSent} = 1;
    
    my $off = 2;
    #$off += 0.15*int(@{$iohash->{QUEUE}}) if($iohash->{QUEUE});
    InternalTimer(gettimeofday()+$off, "CUL_HM_Resend", $hash, 0);
  }
}
###################################
sub
CUL_HM_eventP($$)
{  # handle protocol events
  #todo: add severity, counter, history and acknowledge
  my ($hash, $evntType) = @_;
  my $name = $hash->{NAME};
  return if (!$name);
  if ($evntType eq "Rcv"){
    $attr{$name}{"protLastRcv"} = TimeNow();
	return;
  }
  $attr{$name}{"prot".$evntType."Cnt"} = 0 
          if (!$attr{$name}{"prot".$evntType."Cnt"});
  $attr{$name}{"prot".$evntType."Cnt"}++;
  $attr{$name}{"prot".$evntType."Last"} = TimeNow();
  if ($evntType eq "Nack" ||$evntType eq "ResndFail"){
    my $delMsgSum;
    $attr{$name}{protCmdDel} = 0 if(!$attr{$name}{protCmdDel});
    $attr{$name}{protCmdDel} += scalar @{$hash->{cmdStack}} if ($hash->{cmdStack});
  }
}
###################################
sub
CUL_HM_respPendRm($)
{  # delete all response related entries in messageing entity
  my ($hash) =  @_;  
  delete ($hash->{helper}{respWait});
  RemoveInternalTimer($hash);          # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer

  CUL_HM_ProcessCmdStack($hash); # continue processing commands
}
###################################
sub
CUL_HM_respPendTout($)
{
  my ($HMid) =  @_;  
  $HMid =~ s/.*://; #remove timer identifier
  my $hash = $modules{CUL_HM}{defptr}{$HMid};
  if ($hash){
    CUL_HM_eventP($hash,"Tout") if ($hash->{helper}{respWait}{cmd});
    CUL_HM_eventP($hash,"ToutResp") if ($hash->{helper}{respWait}{Pending});
	CUL_HM_respPendRm($hash);
	DoTrigger($hash->{NAME}, "RESPONSE TIMEOUT");
  }
}
###################################
sub
CUL_HM_respPendToutProlong($) 
{#used when device sends part responses
  my ($hash) =  @_;  

  #RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer?
  InternalTimer(gettimeofday()+1, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}
###################################
sub
CUL_HM_PushCmdStack($$)
{
  my ($chnhash, $cmd) = @_;
  my @arr = ();
  my $hash = CUL_HM_getDeviceHash($chnhash);
  $hash->{cmdStack} = \@arr if(!$hash->{cmdStack});
  push(@{$hash->{cmdStack}}, $cmd);
  my $entries = scalar @{$hash->{cmdStack}};
  $attr{$hash->{NAME}}{protCmdPend} = $entries." CMDs pending";
}
###################################
sub
CUL_HM_ProcessCmdStack($)
{
  my ($chnhash) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);
  my $sent;
  if($hash->{cmdStack} && !$hash->{helper}{respWait}{Pending} &&!$hash->{helper}{respWait}{cmd}){
    if(@{$hash->{cmdStack}}) {
      CUL_HM_SendCmd($hash, shift @{$hash->{cmdStack}}, 1, 1);
      $sent = 1;
      $attr{$hash->{NAME}}{protCmdPend} = scalar @{$hash->{cmdStack}} ." CMDs pending";
	  CUL_HM_eventP($hash,"Snd");	  
    }
    if(!@{$hash->{cmdStack}}) {
      delete($hash->{cmdStack});
      delete($attr{$hash->{NAME}}{protCmdPend});
    }
  }
  return $sent;
}
###################################
sub
CUL_HM_Resend($)
{#resend a message if there is no answer
  my $hash = shift;
  my $name = $hash->{NAME};
  return if(!$hash->{helper}{respWait}{reSent});      # Double timer?
  if($hash->{helper}{respWait}{reSent} >= 3) {
  	CUL_HM_eventP($hash,"ResndFail");
    delete($hash->{cmdStack});
    delete($attr{$hash->{NAME}}{protCmdPend});
	CUL_HM_respPendRm($hash);
    $hash->{STATE} = "MISSING ACK";
    DoTrigger($name, "MISSING ACK");
  }
  else {
  	CUL_HM_eventP($hash,"Resnd");
    IOWrite($hash, "", $hash->{helper}{respWait}{cmd});
    $hash->{helper}{respWait}{reSent}++;
    Log GetLogLevel($name,4),"CUL_HM_Resend: ".$name. " nr ".$hash->{helper}{respWait}{reSent};
    InternalTimer(gettimeofday()+1, "CUL_HM_Resend", $hash, 0);
  }
}
###################-----------helper and shortcuts--------################
sub
CUL_HM_getAssChnId($)
{ # will return the list of assotiated channel of a device
  # if it is a channel only return itself
  # if device and no channel 
  my ($name) = @_;
  my @chnIdList;
  foreach my $channel (keys %{$attr{$name}}){
	next if ($channel !~ m/^channel_/);
	my $chnHash = CUL_HM_name2hash($attr{$name}{$channel});
	push @chnIdList,$chnHash->{DEF} if ($chnHash);
  }
  my $dId = CUL_HM_Name2Id($name);

  push @chnIdList,$dId."01" if (length($dId) == 6 && !$attr{$name}{channel_01});
  push @chnIdList,$dId if (length($dId) == 8);
  return sort(@chnIdList);
}
###################################
sub
CUL_HM_Id($)
{#in ioHash out ioHMid 
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME}, "hmId", "F1$fhtid");
}
###################################
sub
CUL_HM_id2hash($)
{# in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if ($modules{CUL_HM}{defptr}{$id});
  return $modules{CUL_HM}{defptr}{substr($id,0,6)}; # could be chn 01 of dev
}
###################################
sub
CUL_HM_name2hash($)
{# in: name, out:hash
  my ($name) = @_;
  return $defs{$name};
}
###################################
sub
CUL_HM_Name2Id(@)
{ # in: name or HMid out: HMid, undef if no match
  my ($idName,$idHash) = @_;
  my $hash = $defs{$idName};
  return $hash->{DEF} if ($hash);                           #idName is entity
  return "000000"     if($idName eq "broadcast");           #broadcast

  return $defs{$1}.$2 if($idName =~ m/(.*)_chn:(.*)/);      #<devname> chn:xx
  return $idName      if($idName =~ m/^[A-F0-9]{6,8}$/i);   #was already HMid
  return $idHash->{DEF}.sprintf("%02X",$1) 
                      if($idHash && $idName =~ m/self(.*)/);
  return;
}
###################################
sub
CUL_HM_id2Name($)
{ # in: name or HMid out: name
  my ($p) = @_;
  return $p                      if($attr{$p}); # is already name
  my $devId= substr($p, 0, 6);
  return "broadcast"             if($devId eq "000000"); 
  my ($chn,$chnId);
  if (length($p) == 8){
	$chn = substr($p, 6, 2);;
	$chnId = $p;
  }
  my $defPtr = $modules{CUL_HM}{defptr};
  return $defPtr->{$chnId}{NAME} if($chnId && $defPtr->{$chnId});
  return $defPtr->{$devId}{NAME} if($defPtr->{$devId});
  return $devId. ($chn ? ("_chn:".$chn):"");
}
###################################
sub
CUL_HM_getDeviceHash($)
{#in: hash (chn or dev) out: hash of the device (used e.g. for send messages)
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
  "58"          => { txt => "ClimateEvent", params => {
                     CMD      => "00,2",
                     ValvePos => '02,2,$val=(hex($val))', } },
  "70"          => { txt => "WeatherEvent", params => {
                     TEMP     => '00,4,$val=((hex($val)&0x3FFF)/10)*((hex($val)&0x4000)?-1:1)',
                     HUM      => '04,2,$val=(hex($val))', } },

);
# RC send BCAST to specific address. Is the meaning understood?
my @culHmCmdFlags = ("WAKEUP", "WAKEMEUP", "BCAST", "Bit3",
                     "BURST", "BIDI", "RPTED", "RPTEN");


sub
CUL_HM_DumpProtocol($$@)
{
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
#############################
sub
CUL_HM_parseCommon(@){
  # parsing commands that are device independant
  my ($msgId,$msgType,$src,$dst,$p) = @_;
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  return "" if(!$shash->{DEF});# this should be from ourself 
  
  my $pendType = $shash->{helper}{respWait}{Pending}? 
                           $shash->{helper}{respWait}{Pending}:"";
  if ($msgType eq "02"){# Ack/Nack #######################################
	if ($shash->{helper}{respWait}{msgId}             && 
	    $shash->{helper}{respWait}{msgId}   eq $msgId ){
	  #ack we waited for - stop Waiting
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
	  delete($attr{$shash->{NAME}}{protCmdPend});
	  CUL_HM_respPendRm($shash);
	  $reply = "NACK"; 
	}
	else{	  #ACK
	  $reply = ($subType eq "01")?"ACKStatus":"ACK"; 
	  $success = "yes";
	}
	CUL_HM_setRd($chnhash,"CommandAccepted",$success,"");
    CUL_HM_ProcessCmdStack($shash); # see if there is something left
	return $reply;
  }
  elsif($msgType eq "10"){
    my $subtype = substr($p,0,2);
	if($subtype eq "01"){ #storePeerList#################
	  if ($pendType eq "PeerList"){
		my $chn = $shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$src.$chn}; 
		$chnhash = $shash if (!$chnhash);
		my @peers = substr($p,2,) =~ /(.{8})/g;
		my @peerList;
		my @peerID;
		foreach my $peer(@peers){
		  push(@peerList,CUL_HM_id2Name($peer));
		  push(@peerID,$peer);
		}
		my $peerFound = join (',',@peerList);
		$peerFound =~ s/broadcast//;  # remove end indication, not a peer
		my $pl = ReadingsVal($chnhash->{NAME},"peerList","").",".$peerFound;
		CUL_HM_setRd($chnhash,"peerList",$pl,'');
		
		$peerFound = join (',',@peerID);
		$peerFound =~ s/00000000//;
		$chnhash->{helper}{peerList}.= ",".$peerFound;
		
		if ($p =~ m/00000000$/) {# last entry, peerList is complete
		  CUL_HM_respPendRm($shash);

		  # check for request to get List3 data
		  my $reqPeer = $chnhash->{helper}{getCfgList};
		  if ($reqPeer){
		    my $flag = CUL_HM_getFlag($shash);
		    my $id = CUL_HM_Id($shash->{IODev});
		    @peerID = split(",", $chnhash->{helper}{peerList});
		    my $class = AttrVal(CUL_HM_id2Name($src), "hmClass", "");
		    my $listNo = "0".$chnhash->{helper}{getCfgListNo};
		    foreach my $peer (@peerID){
			  $peer .="01" if (length($peer) == 6); # add the default
			  if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
				CUL_HM_PushCmdStack($shash,sprintf("++%s01%s%s%s04%s%s",
						$flag,$id,$src,$chn,$peer,$listNo));# List3 or 4 
			  }
			}
			CUL_HM_ProcessCmdStack($shash);
		  }
		  delete $chnhash->{helper}{getCfgList};
		  delete $chnhash->{helper}{getCfgListNo};
		  delete $chnhash->{helper}{peerList};
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		return "done";
	  }
	}
	elsif($subtype eq "02" ||$subtype eq "03"){ #ParamResp##################
	  if ($pendType eq "RegisterRead"){
		my $chnSrc = $src.$shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnhash = $shash if (!$chnhash);
		my $chnName = $chnhash->{NAME};
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
		my $regLN = "RegL_".$list.":".$shash->{helper}{respWait}{forPeer};
		CUL_HM_setRd($chnhash,$regLN,
		             ReadingsVal($chnName,$regLN,"")." ".$data,'');
		if ($data =~m/00:00$/){ # this was the last message in the block
		  if($list eq "00"){
			my $name = CUL_HM_id2Name($src);
			CUL_HM_setRd($shash,"PairedTo",
		                 sprintf("%02X%02X%02X",
		                    CUL_HM_getRegFromStore($name,10,0,"00000000"),
		                    CUL_HM_getRegFromStore($name,11,0,"00000000"),
		                    CUL_HM_getRegFromStore($name,12,0,"00000000")),"");
		  }
		  CUL_HM_respPendRm($shash);
		  delete $chnhash->{helper}{shadowReg}{$regLN};#remove shadowhash
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		return "done";
	  }
	}  
	elsif($subtype eq "04"){ #ParamChange###################
	  my($chn,$peerID,$list,$data) = @_ if($p =~ m/^04(..)(........)(..)(.*)/);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  $chnHash = $shash if(!$chnHash); # will add param to dev if no chan
	  my $listName = "RegL_".$list.":".CUL_HM_id2Name($peerID);
	  $listName =~ s/ /_/g; #remove blanks
	  $data =~ s/(..)(..)/ $1:$2/g;	  
	  
	  my $lN = ReadingsVal($chnHash->{NAME},$listName,"");
	  $lN = "" if($lN =~m/00:00$/);#clear data if it was finished before
	  $lN .= " ".$data;
	  CUL_HM_setRdIfCh($chnHash,$listName,$lN,"");

	  # todo: this is likely a set of messages. Postpone command stack processing
	  # until end of transmission. Verify whether there is a conflict with a 
	  # current operation and use timer supervision to abort
	}  
	elsif($subtype eq "06"){ #reply to status request#######
	  #todo = what is the answer to a status request
	  if ($pendType eq "StatusReq"){#it is the answer to our request
		my $chnSrc = $src.$shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnhash = $shash if (!$chnhash);
		CUL_HM_respPendRm($shash);
		return "STATresp";# todo dont send ACK - check what others do
	  }
	  else{
		my ($chn) = ($1) if($p =~ m/^..(..)/);
		return "powerOn" if ($chn eq "00");# check dst eq "000000" as well?
	  }
	}
  }
  elsif($msgType eq "70"){ #wakeup #######################################
  #CUL_HM_Id($hash->{IODev})
    if((CUL_HM_getRxType($shash) & 0x08) && $shash->{cmdStack}){
	  #send wakeup and process command stack if applicable
   	  CUL_HM_SendCmd($shash, '++A112'.CUL_HM_Id($shash->{IODev}).$src, 1, 1);
	  CUL_HM_ProcessCmdStack($shash);
	}
  }
  return "";
}

#############################
sub
CUL_HM_getRegFromStore($$$$)
{#read a register from backup data
  my($name,$regName,$list,$peerId)=@_;
  my $hash = CUL_HM_name2hash($name);
  my ($size,$pos,$conversion,$factor,$unit) = (8,0,"",1,""); # default
  my $addr = $regName;
  if ($culHmRegDefine{$regName}) { # get the register's information
    $addr = $culHmRegDefine{$regName}{a};
	$pos = ($addr*10)%10;
	$addr = int($addr);
    $list = $culHmRegDefine{$regName}{l};
	$size = $culHmRegDefine{$regName}{s};
	$size = int($size)*8 + ($size*10)%10;
	$conversion = $culHmRegDefine{$regName}{c}; #unconvert formula
	$factor = $culHmRegDefine{$regName}{f};
	$unit = $culHmRegDefine{$regName}{u};
  }
  $peerId = substr(CUL_HM_Name2Id($name),0,6).sprintf("%02X",$1) 
                     if($peerId =~ m/^self(.*)/);    # plus channel

  my $regLN = "RegL_".sprintf("%02X",$list).":".CUL_HM_id2Name($peerId); 
  $regLN =~ s/broadcast//;
  $regLN =~ s/ /_/g;
  
  my $data=0;
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
	my $dRead;
    if ($hash->{helper}{shadowReg}&&$hash->{helper}{shadowReg}{$regLN}){
      $dRead = $1 if($hash->{helper}{shadowReg}{$regLN} =~ m/$addrS:(..)/);
    }
    if (!$dRead && $hash->{READINGS}{$regLN}) {
      $dRead = $1 if($hash->{READINGS}{$regLN}{VAL} =~ m/$addrS:(..)/);
    }
	return "unknown" if (!$dRead);
	$data = ($data<< 8)+hex($dRead);

	$addr++;
  }

  $data = ($data>>$pos) & (0xffffffff>>(32-$size));
   if (!$conversion){                ;# do nothing
   } elsif($conversion eq "factor"){ $data /= $factor;
   } elsif($conversion eq "fltCvT"){ $data = CUL_HM_CvTflt($data);
   } elsif($conversion eq "m10s3") { $data = ($data+3)/10;
   } else { return " conversion undefined - please contact admin";
   } 
   return $data.$unit;

}
#############################
my @culHmTimes8 = ( 0.1, 1, 5, 10, 60, 300, 600, 3600 );
sub
CUL_HM_encodeTime8($)
{
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
#############################
sub
CUL_HM_decodeTime8($)
{
  my $v = hex(shift);
  return "undef" if($v > 255);
  my $v1 = int($v/32);
  my $v2 = $v%32;
  return $v2 * $culHmTimes8[$v1];
}
#############################
sub
CUL_HM_encodeTime16($)
{
  my $v = shift;
  my $ret = "FFFF";
  my $mul = 20;

  return "0000" if($v < 0.05);
  for(my $i = 0; $i < 16; $i++) {
    if($v*$mul < 0xfff) {
     $ret=sprintf("%03X%X", $v*$mul, $i);
     last;
    }
    $mul /= 2;
  }
  my $v2 = CUL_HM_decodeTime16($ret);
  Log 2, "Timeout $v rounded to $v2" if($v != $v2);
  return ($ret);
}
sub
CUL_HM_convTemp($)
{
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
#############################
sub
CUL_HM_decodeTime16($)
{
  my $v = hex(shift);
  my $m = int($v/16);
  my $e = $v % 16;
  my $mul = 0.05;
  while($e--) {
    $mul *= 2;
  }
  return $mul*$m;
}
#############################
sub
CUL_HM_pushConfig($$$$$$$$)
{#routine will generate messages to write cnfig data to register
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content) = @_;
  my $flag = CUL_HM_getFlag($hash);
  $peerAddr = "000000" if(!$peerAddr);
  my $tl = length($content);
  ($chn,$peerChn,$list) = split(':',sprintf("%02X:%02X:%02X",$chn,$peerChn,$list));

  # --store pending changes in shadow to handle bit manipulations cululativ--
  my $peerN = ($peerAddr eq "000000")?CUL_HM_id2Name($peerAddr.$peerChn):"";
  $peerN =~ s/broadcast//;
  $peerN =~ s/ /_/g;#remote blanks
  my $regLN = "RegL_".$list.":".$peerN;
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
  
  CUL_HM_PushCmdStack($hash, "++".$flag.'01'.$src.$dst.$chn.'05'.
                                        $peerAddr.$peerChn.$list);
  for(my $l = 0; $l < $tl; $l+=28) {
    my $ml = $tl-$l < 28 ? $tl-$l : 28;
    CUL_HM_PushCmdStack($hash, "++A001".$src.$dst.$chn."08".
	                                 substr($content,$l,$ml));
  }
  CUL_HM_PushCmdStack($hash,"++A001".$src.$dst.$chn."06");
}
sub
CUL_HM_secSince2000()
{
  # Calculate the local time in seconds from 2000.
  my $t = time();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
  $t -= 946684800; # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
  $t -= 7200;   # HM Special
  $t += fhemTzOffset($t);
  return $t;
}

############### Activity supervision section ################
# verify that devices are seen in a certain period of time
# It will generate events if no message is seen sourced by the device during 
# that period.
# ActionDetector will use the fixed HMid 000000
sub
CUL_HM_ActGetCreateHash()
{# return hash of ActionDetector - create one if not existant
  if (!$modules{CUL_HM}{defptr}{"000000"}){
    DoTrigger("global",  "UNDEFINED ActionDetector CUL_HM 000000");
	$attr{ActionDetector}{actCycle} = 600;
  
  }
  my $defPtr = $modules{CUL_HM}{defptr};
  my $actName = $defPtr->{"000000"}{NAME} if($defPtr->{"000000"});
  my $actHash = $modules{CUL_HM}{defptr}{"000000"};
  if (!$actHash->{helper}{first}){ # if called first time arrributes are no yet
                                   #recovered
  	InternalTimer(gettimeofday()+3, "CUL_HM_ActGetCreateHash", "ActionDetector", 0);
	$actHash->{helper}{first} = 1;
	return;
  }
  if (!$actHash->{helper}{actCycle} ){ #This is the first call
    my $peerList = $attr{$actName}{peerList};
	$peerList = "" if (!$peerList);
    my $tn = TimeNow();
	foreach my $devId (split(",",$peerList)){
	  $actHash->{helper}{$devId}{start} = $tn;
	   my $devName = CUL_HM_id2Name($devId);
	  setReadingsVal($actHash,"status_".$devName,"unknown",$tn);	
	  $attr{$devName}{actStatus}=""; # force trigger
      CUL_HM_setAttrIfCh($devName,"actStatus","unknown","Activity");	  
	}
  }
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
sub
CUL_HM_time2sec($)
{
  my ($timeout) = @_;
  my ($h,$m) = split(":",$timeout);
  no warnings;
  $h = int($h);
  $m = int($m);
  use warnings;
  return ((sprintf("%03s:%02d",$h,$m)),((int($h)*60+int($m))*60));
}
sub
CUL_HM_ActAdd($$)
{# add an HMid to list for activity supervision
  my ($devId,$timeout) = @_; #timeout format [hh]h:mm

  return $devId." is not an HM device - action detection cannot be added"
       if (length($devId) != 6);
  my ($cycleString,undef)=CUL_HM_time2sec($timeout);
  my $devName = CUL_HM_id2Name($devId);
  $attr{$devName}{actCycle} = $cycleString; 
  $attr{$devName}{actStatus}=""; # force trigger
  CUL_HM_setAttrIfCh($devName,"actStatus","unknown","Activity");
  
  my $actHash = CUL_HM_ActGetCreateHash();
  my $actName = $actHash->{NAME}; # could have been renamed

  my $peerList = (!defined($attr{$actName}{peerList}))?"":$attr{$actName}{peerList};
  $peerList .= $devId."," if($peerList !~ m/$devId,/);#add if not in
  $attr{$actName}{peerList} = $peerList; 
  my $tn = TimeNow();  
  $actHash->{helper}{$devId}{start} = $tn;
  setReadingsVal($actHash,"status_".$devName,"unknown",$tn);	  
  Log GetLogLevel($actName,3),"Device ".$devName." added to ActionDetector with "
      .$cycleString." time";
}
sub
CUL_HM_ActDel($)
{# delete HMid for activity supervision
  my ($devId) = @_; 

  return $devId." is not an HM device - action detection cannot be added"
       if (length($devId) != 6);
	   
  my $devName = CUL_HM_id2Name($devId);
  delete ($attr{$devName}{actCycle});
  CUL_HM_setAttrIfCh($devName,"actStatus","deleted","Activity");#post trigger
  delete ($attr{$devName}{actStatus});

  my $acthash = CUL_HM_ActGetCreateHash();
  my $actName = $acthash->{NAME};

  delete ($acthash->{helper}{$devId});

  $attr{$actName}{peerList} = "" if (!defined($attr{$actName}{peerList}));
  $attr{$actName}{peerList} =~ s/$devId,//g; 
  Log GetLogLevel($actName,3),"Device ".$devName." removed from ActionDetector";
}
sub
CUL_HM_ActCheck()
{# perform supervision
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tn = TimeNow();
  my $tod = int(gettimeofday());
  my $actName = $actHash->{NAME};
  delete ($actHash->{READINGS}); #cleansweep
  CUL_HM_setRd($actHash,"status","check performed",$tn);
  foreach my $devId (split(",",AttrVal($actName,"peerList","none"))){
    my $devName = CUL_HM_id2Name($devId);
	if(!$devName || !defined($attr{$devName}{actCycle})){
	  CUL_HM_ActDel($devId); 
	  next;
	}
	my $rdName = "status_".$devName;

    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
	if ($tSec == 0){# detection switched off
	  CUL_HM_setRdIfCh($actHash,$rdName,"switchedOff",$tn);
	  CUL_HM_setAttrIfCh($devName,"actStatus","switchedOff","Activity");
	  next;
	}
	my $tLast = $attr{$devName}{"protLastRcv"};
    my @t = localtime($tod - $tSec); #time since when a trigger is expected
	my $tSince = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                           $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);					   
	if ((!$tLast || $tSince gt $tLast)){      #no message received in timeframe
	  if ($tSince gt $actHash->{helper}{$devId}{start}){
	    CUL_HM_setRdIfCh($actHash,$rdName,"timedOut - last: ".$tLast,$tn);
        CUL_HM_setAttrIfCh($devName,"actStatus","dead","Activity");
        Log GetLogLevel($actName,2),"Device ".$devName." is dead";
	  }
	  # no action otherwise
 	}
	else{
      CUL_HM_setRdIfCh($actHash,$rdName,"alive",$tn);	
      CUL_HM_setAttrIfCh($devName,"actStatus","alive","Activity");
      Log GetLogLevel($actName,5),"Device ".$devName." is alive";
	}
  }

  $attr{$actName}{actCycle} = 600 if($attr{$actName}{actCycle}<30); 
  $actHash->{helper}{actCycle} = $attr{$actName}{actCycle};
  InternalTimer(gettimeofday()+$attr{$actName}{actCycle}, 
  								   "CUL_HM_ActCheck", "ActionDetector", 0);
}
sub
CUL_HM_setRd($$$$) #$hash,$rd,$val,$ts
{#change all readings from here - till fhem.pl provides solution
  my ($hash,$rd,$val,$ts) = @_; 
  $ts = TimeNow() if (!$ts);
  setReadingsVal($hash,$rd,$val,$ts);
}
sub
CUL_HM_setRdIfCh($$$$)
{
  my ($hash,$rd,$val,$ts) = @_; 
  $ts = TimeNow() if (!$ts);
  setReadingsVal($hash,$rd,$val,$ts) 
              if(ReadingsVal($hash->{NAME},$rd,"") ne $val);
}
sub
CUL_HM_setAttrIfCh($$$$)
{
  my ($name,$att,$val,$trig) = @_; 
  if($attr{$name}{$att} ne $val){
    DoTrigger($name,$trig.":".$val) if($trig);
	$attr{$name}{$att} = $val;
  }
}

1;
