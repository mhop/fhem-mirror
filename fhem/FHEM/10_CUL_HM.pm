##############################################
# CUL HomeMatic handler
# $Id$

package main;

# update actiondetector is supported with lines marked as "#todo Updt1 remove"
#        the lines can be removed after some soak time - around version 2600
use strict;
use warnings;
#use Time::HiRes qw(gettimeofday);

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
# ----------------modul globals-----------------------
my $respRemoved; # used to control trigger of stach processing
                 # need to take care that ACK is first

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
  "0012" => {name=>"HM-LC-DIM1L-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0013" => {name=>"HM-LC-DIM1L-PL"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"",},
  "0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:4",},
  "0016" => {name=>"HM-LC-DIM2L-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
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
  "002E" => {name=>"HM-LC-DIM2L-SM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
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
  "004A" => {name=>"HM-SEC-MDIR"             ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
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
  "0057" => {name=>"HM-LC-DIM1T-PL"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0058" => {name=>"HM-LC-DIM1T-CV"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "0059" => {name=>"HM-LC-DIM1T-FM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"",},
  "005A" => {name=>"HM-LC-DIM2T-SM"          ,cyc=>''      ,rxt=>''    ,lst=>'1,3'          ,chn=>"Sw:1:2",},
  "005C" => {name=>"HM-OU-CF-PL"             ,cyc=>''      ,rxt=>''    ,lst=>'3'            ,chn=>"Led:1:1,Sound:2:2",},
  "005D" => {name=>"HM-Sen-MDIR-O"           ,cyc=>'00:10' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"",},
  "005F" => {name=>"HM-SCI-3-FM"             ,cyc=>'28:00' ,rxt=>'c:w' ,lst=>'1,4'          ,chn=>"Sw:1:3",},
  "0060" => {name=>"HM-PB-4DIS-WM"           ,cyc=>''      ,rxt=>'c'   ,lst=>'1,4'          ,chn=>"Btn:1:20",},
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
					   "event-on-change-reading event-on-update-reading ".
                       "hmClass:receiver,sender serialNr firmware devInfo ".
                       "rawToReadable unit ".
					   "peerList ". #todo Updt1 remove
					   "peerIDs ".
					   "actCycle actStatus autoReadReg:1,0 ".
					   "";
  my @modellist;
  foreach my $model (keys %culHmModel){
    push @modellist,$culHmModel{$model}{name};
  }
  $hash->{AttrList}  .= " model:"  .join(",", sort @modellist);
  $hash->{AttrList}  .= " subType:".join(",", sort 
                map { $culHmDevProps{$_}{st} } keys %culHmDevProps);
  CUL_HM_initRegHash();
  
}
sub
CUL_HM_updateConfig($){
  foreach (@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    my $name = shift(@{$modules{CUL_HM}{helper}{updtCfgLst}});
    if (1 == AttrVal($name,"autoReadReg","0")){
	  CUL_HM_Set(CUL_HM_name2Hash($name),$name,"getConfig");
	  CUL_HM_Set(CUL_HM_name2Hash($name),$name,"statusRequest");
	  InternalTimer(gettimeofday()+15,"CUL_HM_updateConfig", "updateConfig", 0);
	  last;
    }
    else{
    }
  }
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
  if(length($a[2]) == 8) {# define a channel
    my $devHmId = uc(substr($a[2], 0, 6));
    my $chn = substr($a[2], 6, 2);
    my $devHash = $modules{CUL_HM}{defptr}{$devHmId};
	return "please define a device with hmId:".$devHmId." first" if(!$devHash);
	
    $modules{CUL_HM}{defptr}{$HMid} = $hash;
    AssignIoPort($hash);
    my $devName = $devHash->{NAME};
	$hash->{device} = $devName; 
    $hash->{chanNo} = $chn; 
    $attr{$name}{model} = $attr{$devName}{model} if ($attr{$devName}{model});
	$devHash->{"channel_$chn"} = $name;
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
  RemoveInternalTimer("updateConfig");
  InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
 
  my @arr;
  if(!$modules{CUL_HM}{helper}{updtCfgLst}){
    $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
  }
  push(@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name);

  return undef;
}
#############################
sub
CUL_HM_Undef($$)
{
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
#############################
sub
CUL_HM_Rename($$$)
{
  #my ($hash, $name,$newName) = @_;
  my ($name, $oldName) = @_;
  my $HMid = CUL_HM_name2Id($name);
  my $hash = CUL_HM_name2Hash($name);
  if (length($HMid) == 8){# we are channel, inform the device
    $hash->{chanNo} = substr($HMid,6,2);
	my $device = $hash->{device}?$hash->{device}:"";
	my $devHash = CUL_HM_name2Hash($device);
	$devHash->{"channel_".$hash->{chanNo}} = $name if ($device);
  }
  else{# we are a device - inform channels if exist
    for (my$chn = 1; $chn <25;$chn++){
	  my $chnName =  $hash->{sprintf("channel_%02X",$chn)};
	  my $chnHash = CUL_HM_name2Hash($chnName);
	  $chnHash->{device} = $name if ($chnName);
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
  my ($len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p) = ($1,$2,$3,$4,$5,$6,$7);
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

  $respRemoved = 0;  #set to 'no response in this message' at start
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
    if(($id eq $dst)&& (hex($msgFlag)&0x20)){
	  CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."0101C800");  # Send Ack
      Log GetLogLevel($name,4), "CUL_HM $name dup mesg - ack and ignore";
	}
	else{
      Log GetLogLevel($name,4), "CUL_HM $name dup mesg - ignore";
	}

    return ""; #return something to please dispatcher
  }
  $shash->{lastMsg} = $msgX;
  $iohash->{HM_CMDNR} = hex($msgcnt) if($dst eq $id);# update messag counter to receiver

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
#  elsif(($cmd =~ m/^A0[01]{2}$/ && $dst eq $id) && $st ne "keyMatic") {#### Pairing-Request-Convers.
#    push @event, "";    #todo why end here?
#  } General check operation after removal
  elsif($model eq "KS550" || $model eq "HM-WDS100-C6-O") { ############

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
  elsif($model eq "HM-CC-TC") { ####################################
    my ($sType,$chn) = ($1,$2) if($p =~ m/^(..)(..)/);
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
	  my $dTemp = sprintf("%0.1f", hex(substr($p,4,2))/2);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  readingsSingleUpdate($chnHash,"desired-temp",$dTemp,1) if($chnHash);
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
  elsif($model eq "HM-CC-VD") { ###################
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
	           if(($model eq "HM-LC-SW1-BA-PCB")&&($err&0x80));
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
	  $shash->{helper}{addVal} = $buttonField;   #store to handle changes
	  readingsSingleUpdate($chnHash,"state",$target,1);#trigger chan evt also 
      push @event,"battery:". (($buttonField&0x80)?"low":"ok");
      push @event,"state:$btnName $state$target";
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
  elsif($st eq "motionDetector") { #####################################
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
    elsif($msgType eq "41" && $p =~ m/^01(..)(..)(..)/) {#01 is "motion"
	  my($cnt,$nextTr) = (hex($1),(hex($3)>>4));
	  $state = $2;
	  my $bright = hex($state);
      push @event, "state:motion";
      push @event, "motion:on$target"; #added peterp
      push @event, "motionCount:".$cnt."_next:".$nextTr;
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
  elsif($st eq "smokeDetector") { #####################################
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
	  if($dhash){ # the source is in dst
	    if (!$dhash->{helper}{alarmNo} || $dhash->{helper}{alarmNo} ne $No){
		  $dhash->{helper}{alarmNo} = $No;
		  readingsSingleUpdate($dhash,'state',
		                              (($state eq "01")?"all-clear":"on"),1);
		}
	  }
      push @event,"state:".(($state eq "01")?"all-clear":"on").":from:".$dname;
      push @event,"smoke_detect:on $dname";
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
	
	if($id eq $dst && $cmd ne "8002"){  # Send Ack/Nack
      CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src.($cmd eq "A001" ? "80":"00"));
      $sendAck = ""; #todo why is this special?
	}
  } 
  elsif($st eq "threeStateSensor") { #####################################
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
        CUL_HM_SndCmd($shash, $msgcnt."8002".$id.$src."0101".$lst."00")  
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

      my $stErr = ($err >>1) & 0x7;      
      my $error = 'unknown_'.$stErr;
      $error = 'motor aborted'  if ($stErr == 2);
      $error = 'clutch failure' if ($stErr == 1);
      $error = 'none'           if ($stErr == 0);

      push @event, "unknown:40"   if($err&0x40);
	  push @event, "battery:".   (($err&0x80) ? "low":"ok");
      push @event, "uncertain:" .(($err&0x30) ? "yes":"no");
      push @event, "error:" .    ($error);
      my $state = ($err & 0x30) ? " (uncertain)" : "";
      push @event, "lock:"	.	(($val == 1) ? "unlocked" : "locked");
      push @event, "state:"	.	(($val == 1) ? "unlocked" : "locked") . $state;
    }
  }  
  else{#####################################
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
	    my @peerIDs = split(',',AttrVal($dChName,"peerIDs",""));

		if (AttrVal($dChName,"peerIDs","") =~m/$recId/){# is in peerlist?
		  my $dChHash = CUL_HM_name2Hash($dChName);
		  $dChHash->{helper}{trgLgRpt} = 0 if (!defined($dChHash->{helper}{trgLgRpt}));
		  $dChHash->{helper}{trgLgRpt} +=1;
		  
		  my $state = ReadingsVal($dChName,"virtActState","ON");
		  $state = ($state eq "OFF")?"ON":"OFF" 
		        if ($dChHash->{helper}{trgLgRpt} == 1);# toggle first
		  if (hex($msgFlag)&0x20){
		    $longPress .= "_Release";
			$dhash->{helper}{trgLgRpt}=0;
		    CUL_HM_SndCmd($dChHash,$msgcnt."8002".$dst.$src.'01'.$dChNo.
                  (($state eq "ON")?"C8":"00")."00");
			$sendAck = "";
		  }
		  CUL_HM_UpdtReadBulk($dChHash,1,"virtActState:".$state,
			                       "virtActTrigger:".CUL_HM_id2Name($recId),
						           "virtActTrigType:".$longPress,
						           "virtActTrigRpt:".$dChHash->{helper}{trgLgRpt},
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
  CUL_HM_UpdtReadBulk($shash,1,@event);
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
	# lit: if the command is a literal options will be entered here
	# d: if '1' the register will appear in Readings
	#
my %culHmRegDefShLg = (# register that are available for short AND long button press. Will be merged to rgister list at init
#blindActuator mainly   
  maxTimeF        =>{a=> 29.0,s=>1.0,l=>3,min=>0  ,max=>25.4    ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"max time first direction"},
  driveMode       =>{a=> 31.0,s=>1.0,l=>3,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{direct=>0,viaUpperEnd=>1,viaLowerEnd=>2,viaNextEnd=>3}},
  actionType      =>{a=> 10.0,s=>0.2,l=>3,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""             ,lit=>{off=>0,jmpToTarget=>1,toggleToCnt=>2,toggleToCntInv=>3}},
  OnTimeMode      =>{a=> 10.0,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"on time mode" ,lit=>{absolut=>0,minimal=>1}},
  OffTimeMode     =>{a=> 10.6,s=>0.1,l=>3,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"off time mode",lit=>{absolut=>0,minimal=>1}},
#dimmer mainly                                                                                 
  OnDly           =>{a=>  6.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on delay "},
  OnTime          =>{a=>  7.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"on time"},
  OffDly          =>{a=>  8.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off delay"},
  OffTime         =>{a=>  9.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"off time"},

  OffLevel        =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>1,t=>"PowerLevel Off"},
  OnMinLevel      =>{a=> 16.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"minimum PowerLevel"},
  OnLevel         =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>1,t=>"PowerLevel on"},

  OffLevelKm      =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnLevelKm       =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>127.5   ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"OnLevel 127.5=locked"},
  OnRampOnSp      =>{a=> 34.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp On speed"},
  OnRampOffSp     =>{a=> 35.0,s=>1.0,l=>3,min=>0  ,max=>1       ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>0,t=>"Ramp Off speed"},

  rampSstep       =>{a=> 18.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"rampStartStep"},
  rampOnTime      =>{a=> 19.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOnTime"},
  rampOffTime     =>{a=> 20.0,s=>1.0,l=>3,min=>0  ,max=>111600  ,c=>'fltCvT'   ,f=>''      ,u=>'s'   ,d=>0,t=>"rampOffTime"},
  dimMinLvl       =>{a=> 21.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMinLevel"},
  dimMaxLvl       =>{a=> 22.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimMaxLevel"},
  dimStep         =>{a=> 23.0,s=>1.0,l=>3,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>'%'   ,d=>0,t=>"dimStep"},
#output Unit                                                                                       
  ActType         =>{a=>36   ,s=>1  ,l=>3,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Action type(LED or Tone)"},
  ActNum          =>{a=>37   ,s=>1  ,l=>3,min=>1  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Action Number"},
  Intense         =>{a=>47   ,s=>1  ,l=>3,min=>10 ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>0,t=>"Volume - Tone channel only!"},
# statemachines
  BlJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOn      =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRampOff     =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOn       =>{a=> 28.0,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOn"   ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  BlJtRefOff      =>{a=> 28.4,s=>0.4,l=>3,min=>0  ,max=>9       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from refOff"  ,lit=>{no=>0,onDly=>1,refOn=>2,on=>3,dlyOff=>4,refOff=>5,off=>6,rampOn=>8,rampOff=>9}},
  
  DimJtOn         =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtOff        =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtDlyOn      =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtDlyOff     =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtRampOn     =>{a=> 13.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOn"  ,lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  DimJtRampOff    =>{a=> 13.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from rampOff" ,lit=>{no=>0,onDly=>1,rampOn=>2,on=>3,dlyOff=>4,rampOff=>5,Off=>6}},
  
  SwJtOn          =>{a=> 11.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from On"      ,lit=>{no=>0,onDly=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtOff         =>{a=> 11.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from Off"     ,lit=>{no=>0,onDly=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOn       =>{a=> 12.0,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOn" ,lit=>{no=>0,onDly=>1,on=>3,dlyOff=>4,off=>6}},
  SwJtDlyOff      =>{a=> 12.4,s=>0.4,l=>3,min=>0  ,max=>6       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jump from delayOff",lit=>{no=>0,onDly=>1,on=>3,dlyOff=>4,off=>6}},
  
  CtOn            =>{a=>  3.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from On"       ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
  CtOff           =>{a=>  3.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from Off"      ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
  CtDlyOn         =>{a=>  2.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOn"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
  CtDlyOff        =>{a=>  2.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from delayOff" ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
  CtRampOn        =>{a=>  1.0,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOn"   ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
  CtRampOff       =>{a=>  1.4,s=>0.4,l=>3,min=>0  ,max=>5       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Jmp on condition from rampOff"  ,lit=>{geLo=>0,geHi=>1,ltLo=>2,ltHi=>3,in=>4,out=>5}},
);



my %culHmRegDefine = (
  intKeyVisib     =>{a=>  2.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>'visibility of internal channel',lit=>{invisib=>0,visib=>1}},
  pairCentral     =>{a=> 10.0,s=>3.0,l=>0,min=>0  ,max=>16777215,c=>'hex'      ,f=>''      ,u=>''    ,d=>0,t=>'pairing to central'},
#blindActuator mainly                                                                             
  driveUp         =>{a=> 13.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveDown       =>{a=> 11.0,s=>2.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"drive time up"},
  driveTurn       =>{a=> 15.0,s=>1.0,l=>1,min=>0  ,max=>6000.0  ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>1,t=>"fliptime up <=>down"},
#remote mainly                                                                                      
  language        =>{a=>  7.0,s=>1.0,l=>0,min=>0  ,max=>1       ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Language 0:English, 1:German"},
  stbyTime        =>{a=> 14.0,s=>1.0,l=>0,min=>1  ,max=>99      ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Standby Time"},
  backAtKey       =>{a=> 13.7,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at keystroke",lit=>{off=>0,on=>1}},
  backAtMotion    =>{a=> 13.6,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight at motion"   ,lit=>{off=>0,on=>1}},
  backOnTime      =>{a=> 14.0,s=>1.0,l=>0,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>'s'   ,d=>1,t=>"Backlight On Time"},
  longPress       =>{a=>  4.4,s=>0.4,l=>1,min=>0.3,max=>1.8     ,c=>'m10s3'    ,f=>''      ,u=>'s'   ,d=>0,t=>"time to detect key long press"},
  dblPress        =>{a=>  9.0,s=>0.4,l=>1,min=>0  ,max=>1.5     ,c=>'factor'   ,f=>10      ,u=>'s'   ,d=>0,t=>"time to detect double press"},
  peerNeedsBurst  =>{a=>  1.0,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"peer expects burst",lit=>{off=>0,on=>1}},
  expectAES       =>{a=>  1.7,s=>0.1,l=>4,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"expect AES"        ,lit=>{off=>0,on=>1}},
  lcdSymb         =>{a=>  2.0,s=>0.1,l=>4,min=>0  ,max=>255     ,c=>'hex'      ,f=>''      ,u=>''    ,d=>0,t=>"bitmask which symbol to display on message"},
  lcdLvlInterp    =>{a=>  3.0,s=>0.1,l=>4,min=>0  ,max=>255     ,c=>'hex'      ,f=>''      ,u=>''    ,d=>0,t=>"bitmask fro symbols"},
  msgShowTime     =>{a=> 45.0,s=>1.0,l=>1,min=>0.0,max=>120     ,c=>'factor'   ,f=>2       ,u=>'s'   ,d=>1,t=>"Message show time(RC19). 0=always on"},
  beepAtAlarm     =>{a=> 46.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Alarm"        ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtService   =>{a=> 46.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Service"      ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  beepAtInfo      =>{a=> 46.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Beep Info"         ,lit=>{none=>0,tone1=>1,tone2=>2,tone3=>3}},
  backlAtAlarm    =>{a=> 47.0,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Alarm"   ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtService  =>{a=> 47.2,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Service" ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
  backlAtInfo     =>{a=> 47.4,s=>0.2,l=>1,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Backlight Info"    ,lit=>{off=>0,on=>1,blinkSlow=>2,blinkFast=>3}},
#dimmer  mainly                                                                                  
  ovrTempLvl      =>{a=> 50.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>1,t=>"overtemperatur level"},
  redTempLvl      =>{a=> 52.0,s=>1.0,l=>1,min=>30 ,max=>100     ,c=>''         ,f=>''      ,u=>"C"   ,d=>1,t=>"reduced temperatur recover"},
  redLvl          =>{a=> 53.0,s=>1.0,l=>1,min=>0  ,max=>100     ,c=>'factor'   ,f=>2       ,u=>"%"   ,d=>1,t=>"reduced power level"},
#CC-TC                                                                                        
  BacklOnTime     =>{a=>5.0  ,s=>0.6,l=>0,min=>1  ,max=>25      ,c=>""         ,f=>''      ,u=>'s'   ,d=>0,t=>"Backlight ontime"},
  BacklOnMode     =>{a=>5.6  ,s=>0.2,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Backlight mode"  ,lit=>{off=>0,auto=>1}},
  BtnLock         =>{a=>15   ,s=>1  ,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Button Lock"     ,lit=>{unlock=>0,lock=>1}},
  DispTempHum     =>{a=>1.0  ,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{temp=>0,tempHumidity=>1}},
  DispTempInfo    =>{a=>1.1  ,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{actual=>0,setPoint=>1}},
  DispTempUnit    =>{a=>1.2  ,s=>0.1,l=>5,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{Celsius=>0,Fahrenheit=>1}},
  MdTempReg       =>{a=>1.3  ,s=>0.2,l=>5,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{manual=>0,auto=>1,central=>2,party=>3}},
  MdTempValve     =>{a=>2.6  ,s=>0.2,l=>5,min=>0  ,max=>2       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>""                ,lit=>{auto=>0,close=>1,open=>2}},
                                                                                                 
  TempComfort     =>{a=>3    ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"comfort temp value"},
  TempLower       =>{a=>4    ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"comfort temp value"},
  PartyEndDay     =>{a=>98   ,s=>1  ,l=>6,min=>0  ,max=>200     ,c=>''         ,f=>''      ,u=>'d'   ,d=>1,t=>"Party end Day"},
  PartyEndMin     =>{a=>97.7 ,s=>1  ,l=>6,min=>0  ,max=>1       ,c=>''         ,f=>''      ,u=>'min' ,d=>1,t=>"Party end 0=:00, 1=:30"},
  PartyEndHr      =>{a=>97   ,s=>0.6,l=>6,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Party end Hour"},
  TempParty       =>{a=>6    ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Party"},
  TempWinOpen     =>{a=>5    ,s=>0.6,l=>5,min=>6  ,max=>30      ,c=>'factor'   ,f=>2       ,u=>'C'   ,d=>1,t=>"Temperature for Win open !chan 3 only!"},
  DecalDay        =>{a=>1.5  ,s=>0.3,l=>5,min=>0  ,max=>7       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"Decalc weekday"  ,lit=>{sat=>0,sun=>1,mon=>2,tue=>3,wed=>4,thu=>5,fri=>6}},
  DecalHr         =>{a=>8.3  ,s=>0.5,l=>5,min=>0  ,max=>23      ,c=>''         ,f=>''      ,u=>'h'   ,d=>1,t=>"Decalc hour"},
  DecalMin        =>{a=>8    ,s=>0.3,l=>5,min=>0  ,max=>50      ,c=>'factor'   ,f=>0.1     ,u=>'min' ,d=>1,t=>"Decalc min"},
#Thermal-cc-VD                                                                                  
  ValveOffset     =>{a=>9    ,s=>0.5,l=>5,min=>0  ,max=>25      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve offset"},             # size actually 0.5
  ValveError      =>{a=>10   ,s=>1  ,l=>5,min=>0  ,max=>99      ,c=>''         ,f=>''      ,u=>'%'   ,d=>1,t=>"Valve position when error"},# size actually 0.7
# keymatic secific register                                                                     
  signal          =>{a=>3.4  ,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Confirmation beep"             ,lit=>{off=>0,on=>1}},
  signalTone      =>{a=>3.6  ,s=>0.2,l=>0,min=>0  ,max=>3       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>""                              ,lit=>{low=>0,mid=>1,high=>2,veryHigh=>3}},
  keypressSignal  =>{a=>3.0  ,s=>0.1,l=>0,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Keypress beep"                 ,lit=>{off=>0,on=>1}},
  holdTime        =>{a=>20   ,s=>1,  l=>1,min=>0  ,max=>8.16    ,c=>'factor'   ,f=>31.25   ,u=>'s'   ,d=>0,t=>"Holdtime for door opening"},
  setupDir        =>{a=>22   ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"Rotation direction for locking",lit=>{right=>0,left=>1}},
  setupPosition   =>{a=>23   ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>15      ,u=>'%'   ,d=>0,t=>"Rotation angle neutral position"},
  angelOpen       =>{a=>24   ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>15      ,u=>'%'   ,d=>0,t=>"Door opening angle"},
  angelMax        =>{a=>25   ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>15      ,u=>'%'   ,d=>0,t=>"Angle locked"},
  angelLocked     =>{a=>26   ,s=>1  ,l=>1,min=>0  ,max=>3000    ,c=>'factor'   ,f=>15      ,u=>'%'   ,d=>0,t=>"Angle Locked position"},
  ledFlashUnlocked=>{a=>31.3 ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when not locked",lit=>{off=>0,on=>1}},
  ledFlashLocked  =>{a=>31.6 ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>0,t=>"LED blinks when locked"    ,lit=>{off=>0,on=>1}},
# sec_mdir                                                                                   
  evtFltrPeriod   =>{a=>1.0  ,s=>0.4,l=>1,min=>0.5,max=>7.5     ,c=>'factor'   ,f=>2       ,u=>'s'   ,d=>1,t=>"event filter period"},
  evtFltrNum      =>{a=>1.4  ,s=>0.4,l=>1,min=>1  ,max=>15      ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"sensitivity - read sach n-th puls"},
  minInterval     =>{a=>2.0  ,s=>0.3,l=>1,min=>0  ,max=>4       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"minimum interval in sec"   ,lit=>{0=>0,15=>1,20=>2,60=>3,120=>4}},
  captInInterval  =>{a=>2.3  ,s=>0.1,l=>1,min=>0  ,max=>1       ,c=>'lit'      ,f=>''      ,u=>''    ,d=>1,t=>"capture within interval"   ,lit=>{off=>0,on=>1}},
  brightFilter    =>{a=>2.4  ,s=>0.4,l=>1,min=>0  ,max=>7       ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"brightness filter"},
  ledOnTime       =>{a=>34   ,s=>1  ,l=>1,min=>0  ,max=>1.275   ,c=>'factor'   ,f=>200     ,u=>'s'   ,d=>1,t=>"LED ontime"},
# weather units                                                                                  
  stormUpThresh   =>{a=>6    ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm upper threshold"},
  stormLowThresh  =>{a=>7    ,s=>1  ,l=>1,min=>0  ,max=>255     ,c=>''         ,f=>''      ,u=>''    ,d=>1,t=>"Storm lower threshold"},
  
  );
my %culHmRegGeneral = (
  intKeyVisib=>1,pairCentral=>1,
	);
my %culHmRegType = (
  remote=> {expectAES=>1,peerNeedsBurst=>1,dblPress=>1,longPress=>1},
  blindActuator=> {driveUp  =>1, driveDown=>1 , driveTurn=>1,
                   maxTimeF =>1,
                   OnDly    =>1, OnTime     =>1,OffDly     =>1,  OffTime    =>1,
  	   		       OffLevel =>1, OnLevel    =>1,
                   driveMode=>1, actionType =>1,OnTimeMode =>1,  OffTimeMode=>1,
				   BlJtOn          =>1,BlJtOff         =>1,BlJtDlyOn       =>1,BlJtDlyOff      =>1,
                   BlJtRampOn      =>1,BlJtRampOff     =>1,BlJtRefOn       =>1,BlJtRefOff      =>1,
                   CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,
				   CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,
				   },
  dimmer=> {ovrTempLvl      =>1,redTempLvl      =>1,redLvl          =>1,
            OnDly           =>1,OnTime          =>1,OffDly          =>1,OffTime         =>1,
			OffLevel        =>1,OnMinLevel      =>1,OnLevel         =>1,               
            rampSstep       =>1,rampOnTime      =>1,rampOffTime     =>1,dimMinLvl       =>1,
            dimMaxLvl       =>1,dimStep         =>1,
            DimJtOn         =>1,DimJtOff        =>1,DimJtDlyOn      =>1,
            DimJtDlyOff     =>1,DimJtRampOn     =>1,DimJtRampOff    =>1,
            CtOn            =>1,CtDlyOn         =>1,CtRampOn        =>1,
            CtOff           =>1,CtDlyOff        =>1,CtRampOff       =>1,
			},
  switch=> {OnTime          =>1,OffTime         =>1, OnDly          =>1,OffDly          =>1,
            SwJtOn          =>1,SwJtOff         =>1,SwJtDlyOn       =>1,SwJtDlyOff      =>1,
            CtOn            =>1,CtDlyOn         =>1,
            CtOff           =>1,CtDlyOff        =>1,
			},
  outputUnit=>{
			OnDly   =>1,OnTime  =>1,OffDly  =>1,OffTime =>1,
			ActType =>1,ActNum  =>1,Intense =>1,
			},
  winMatic=>{	                                    		 
            OnTime          =>1,OffTime         =>1,OffLevelKm      =>1,
            OnLevelKm       =>1,OnRampOnSp      =>1,OnRampOffSp     =>1,
			},                                  
  keyMatic=>{                                   
			signal          =>1,signalTone      =>1,keypressSignal  =>1,
			holdTime        =>1,setupDir        =>1,setupPosition   =>1,
			angelOpen       =>1,angelMax        =>1,angelLocked     =>1,
			ledFlashUnlocked=>1,ledFlashLocked  =>1,
			},
  motionDetector=>{                               
            evtFltrPeriod =>1,evtFltrNum      =>1,minInterval     =>1,
			captInInterval=>1,brightFilter    =>1,ledOnTime       =>1,
			},
);
my %culHmRegModel = (
  "HM-RC-12"   => {backAtKey    =>1, backAtMotion =>1, backOnTime   =>1},
  "HM-RC-12-B" => {backAtKey    =>1, backAtMotion =>1, backOnTime   =>1},
  "HM-RC-12-SW"=> {backAtKey    =>1, backAtMotion =>1, backOnTime   =>1},
       
  "HM-RC-19"   => { language =>1,},
  "HM-RC-19-B" => { language =>1,},
  "HM-RC-19-SW"=> { language =>1,},
 
  "HM-CC-VD"      => {ValveOffset     =>1,ValveError      =>1},
  "HM-PB-4DIS-WM" => {language        =>1,stbyTime        =>1},
  "HM-WDS100-C6-O"=> {stormUpThresh   =>1,stormLowThresh  =>1},
  "KS550"         => {stormUpThresh   =>1,stormLowThresh  =>1},
);
my %culHmRegChan = (# if channelspecific then enter them here 
  "HM-CC-TC02"=> {
			DispTempHum  =>1,DispTempInfo =>1,DispTempUnit =>1,MdTempReg   =>1,
			MdTempValve  =>1,TempComfort  =>1,TempLower    =>1,PartyEndDay =>1,
			PartyEndMin  =>1,PartyEndHr   =>1,TempParty    =>1,DecalDay    =>1,
			DecalHr      =>1,DecalMin     =>1, 
            BacklOnTime  =>1,BacklOnMode  =>1,BtnLock      =>1,
              },
  "HM-CC-TC03"   => {TempWinOpen  =>1, }, #window channel
  "HM-RC-1912"   => {msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                     backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                     lcdSymb      =>1, lcdLvlInterp   =>1},
  "HM-RC-19-B12" => {msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                     backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                     lcdSymb      =>1, lcdLvlInterp   =>1},
  "HM-RC-19-SW12"=> {msgShowTime  =>1, beepAtAlarm    =>1, beepAtService =>1,beepAtInfo  =>1,
                     backlAtAlarm =>1, backlAtService =>1, backlAtInfo   =>1,
                     lcdSymb      =>1, lcdLvlInterp   =>1},
 );

##--------------- Conversion routines for register settings
my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111600);
			  
sub
CUL_HM_initRegHash()
{ #duplicate short and long press register 
  foreach my $reg (keys %culHmRegDefShLg){ #update register list
    %{$culHmRegDefine{"Sh".$reg}} = %{$culHmRegDefShLg{$reg}};
    %{$culHmRegDefine{"Lg".$reg}} = %{$culHmRegDefShLg{$reg}};
	$culHmRegDefine{"Lg".$reg}{a} +=0x80;
  }
  foreach my $type(sort(keys %culHmRegType)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegType{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegType{$type}{$reg};
	    $culHmRegType{$type}{"Sh".$reg} = 1;
	    $culHmRegType{$type}{"Lg".$reg} = 1;
	  }
    }
  }
  foreach my $type(sort(keys %culHmRegModel)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegModel{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegModel{$type}{$reg};
	    $culHmRegModel{$type}{"Sh".$reg} = 1;
	    $culHmRegModel{$type}{"Lg".$reg} = 1;
	  }
    }
  }
  foreach my $type(sort(keys %culHmRegChan)){ #update references to register
    foreach my $reg (sort(keys %{$culHmRegChan{$type}})){
      if ($culHmRegDefShLg{$reg}){
	    delete $culHmRegChan{$type}{$reg};
	    $culHmRegChan{$type}{"Sh".$reg} = 1;
	    $culHmRegChan{$type}{"Lg".$reg} = 1;
	  }
    }
  }
}

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
sub
CUL_HM_TCtempReadings($)
{
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $reg5 = ReadingsVal($name,"RegL_05:","");
  my $reg6 = ReadingsVal($name,"RegL_06:","");
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
                ($hash->{helper}{shadowReg}{"RegL_05:"}?"set":"verified"));
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

###################################
sub
CUL_HM_Get($@)
{
  my ($hash, @a) = @_;
  return "no get value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $devName = $hash->{device}?$hash->{device}:$name;
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");
  my $mId = CUL_HM_getMId($hash);
  my $rxType = CUL_HM_getRxType($hash);

  my $class = AttrVal($devName, "hmClass", "");#relevant is the device
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
	  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st}); 
	  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md}); 
	  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn}); 
	  
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
	  my $regHeader = "list:peer\tregister         :value\n";
	  foreach my $regName (@regArr){
	    my $regL  = $culHmRegDefine{$regName}->{l};
		my @peerExe = (grep (/$regL/,@listWp))?@peers:("00000000");
		foreach my $peer(@peerExe){
		  next if($peer eq "");
	      my $regVal = CUL_HM_getRegFromStore($name,$regName,0,$peer); #determine
		  my $peerN = CUL_HM_id2Name($peer);
		  $peerN = "      " if ($peer  eq "00000000");
		  push @regValList,sprintf("   %d:%s\t%-16s :%s\n",
		          $regL,$peerN,$regName,$regVal)
		        if ($regVal ne 'invalid');
		}
	  }
	  my $addInfo = ""; #todo - find a generic way to handle special devices
	  $addInfo = CUL_HM_TCtempReadings($hash)
	        if ($md eq "HM-CC-TC" && $chn eq "02");
			
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
	  $help .= " options:".join(",",keys%{$reg->{lit}})if (defined($reg->{lit}));
	  push @rI,sprintf("%4d: %16s | %3d to %-11s | %8s | %s\n",
			  $reg->{l},$regName,$reg->{min},$reg->{max}.$reg->{u},
              ((($reg->{l} == 3)||($reg->{l} == 4))?"required":""),$help)
	        if (!($isChannel && $reg->{l} == 0));
	}
	
    my $info = sprintf("list: %16s | %-18s | %-8s | %s\n",
	                 "register","range","peer","description");
	foreach(sort(@rI)){$info .= $_;}
	return $info;
  }

  Log GetLogLevel($name,4), "CUL_HM get $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($devHash) if ($rxType & 0x03);#burst/all
  return "";
}
###################################
my %culHmGlobalSets = (
  raw      	    => "data ...",
  reset    	    => "",
  pair     	    => "",
  unpair   	    => "",
  sign     	    => "[on|off]",
  regRaw   	    =>"[List0|List1|List2|List3|List4|List5|List6] <addr> <data> ... <PeerChannel>",
  statusRequest => "",
  getpair       => "", 
  getdevicepair => "",
  getRegRaw     =>"[List0|List1|List2|List3|List4|List5|List6] ... <PeerChannel>",
  getConfig     => "",
  regSet        =>"<regName> <value> ... <peerChannel>",
  virtual       =>"<noButtons>",
  actiondetect  =>"<hh:mm|off>",
  clear         =>"[readings|msgEvents]",
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
        { raw        => "data ...",
		  devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
		  press      => "[long|short]...",
          valvePos   => "position",#acting as TC
		  virtual    =>"<noButtons>",}, #redef necessary for virtual
  smokeDetector =>
        { test => "", "alarmOn"=>"", "alarmOff"=>"", 
		  devicepair => "<btnNumber> device ... single [set|unset] actor"},
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
  "ROTO_ZEL-STG-RM-FDK"=>{
          devicepair    => "<btnNumber> device ... single [set|unset] [actor|remote|both]",},
  "HM-SEC-RHS"=>{
          devicepair    => "<btnNumber> device ... single [set|unset] [actor|remote|both]",},
);

my %culHmChanSets = (
  "HM-CC-TC00"=>{ 
          devicepair    => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
          "day-temp"     => "temp",
          "night-temp"   => "temp",
          "party-temp"   => "temp",
          "desired-temp" => "temp", 
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
          "day-temp"     => "temp",
          "night-temp"   => "temp",
          "party-temp"   => "temp",
          "desired-temp" => "temp", 
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
  my $devName = $hash->{device}?$hash->{device}:$name;
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

  my $mdCh      = $md.($isChannel?$chn:"00"); # chan specific commands?
  my $h = $culHmGlobalSets{$cmd} if($st ne "virtual");
  $h = $culHmSubTypeSets{$st}{$cmd} if(!defined($h) && $culHmSubTypeSets{$st});
  $h = $culHmModelSets{$md}{$cmd}   if(!defined($h) && $culHmModelSets{$md});
  $h = $culHmChanSets{$mdCh}{$cmd}  if(!defined($h) && $culHmChanSets{$mdCh});

  my @h;
  @h = split(" ", $h) if($h);

  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
    $cmd = "pct";
  } 
  elsif(!defined($h)) {
    my @arr;
    @arr = keys %culHmGlobalSets if($st ne "virtual");
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

  my $id = CUL_HM_Id($hash->{IODev});
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);

  if($cmd eq "raw") {  ##################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
	$state = "";
    for (my $i = 2; $i < @a; $i++) {
      CUL_HM_PushCmdStack($hash, $a[$i]);
    }
  } 
  elsif($cmd eq "clear") { ############################################
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
      }
	  $hash->{protState} = "Info_Cleared" ;
	}
	else{
	  return "unknown section. User readings or msgEvents";
	}
	$state = "";
  } 
  elsif($cmd eq "reset") { ############################################
	CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  } 
  elsif($cmd eq "pair") { #############################################
	$state = "";
    return "pair is not enabled for this type of device, ".
                "use set <IODev> hmPairForSec"
        if($class eq "sender");
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
  elsif($cmd eq "regRaw" ||$cmd eq "getRegRaw") { #############################
    my ($list,$addr,$data,$peerID);
	$state = "";
	($list,$addr,$data,$peerID) = ($a[2],hex($a[3]),hex($a[4]),$a[5])
	                               if ($cmd eq "regRaw");
	($list,$peerID) = ($a[2],$a[3])if ($cmd eq "getRegRaw");
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
	else{
	  $chn = "00" if ($list eq "00");
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
	        if (($data < $reg->{min} ||$data > $reg->{max})&&
			    !($reg->{c} eq 'lit'||$reg->{c} eq 'hex')); # none number
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
    $tval = CUL_HM_encodeTime16(((@a > 2)&&$a[2]!=0)?$a[2]:6709248);# onTime   0.0..6709248, 0=forever
    $rval = CUL_HM_encodeTime16((@a > 3)?$a[3]:2.5);     # rampTime 0.0..6709248, 0=immediate
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
  elsif($cmd eq "desired-temp") { ##################
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'0202'.$temp);
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
	readingsSingleUpdate($hash,"tempList$wd",$msg,0);
  } 
  elsif($cmd eq "valvePos") { ##################
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
    CUL_HM_SndCmd($hash, sprintf("++9440%s%s00%02X",$dst,$dst,$testnr));
  } 
  elsif($cmd =~ m/alarm(.*)/) { ###############################################
    CUL_HM_SndCmd($hash, sprintf("++9441%s%s01%s",
        $dst,$dst, $1 eq "On" ? "0BC8" : "0C01"));
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
	foreach my $channel (keys %{$hash}){# remove higher numbers
	  my $chNo = $1 if($channel =~ m/^channel_(.*)/);
	  CommandDelete(undef,$hash->{$channel})
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
	foreach my $peer (sort(split(',',AttrVal($name,"peerIDs","")))) {
	  push (@peerList,substr($peer,0,6));
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
	$peerHash = $modules{CUL_HM}{defptr}{$peerDst.$peerChn} 
	      if ($modules{CUL_HM}{defptr}{$peerDst.$peerChn});
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst} if (!$peerHash);
    return "$peerN not a CUL_HM device"                           if($target && ($target ne "remote") &&(!$peerHash ||$peerHash->{TYPE} ne "CUL_HM"));
    return "$single must be single or dual"                       if(defined($single) && (($single ne"single") &&($single ne"dual")));
    return "$set must be set or unset"                            if(defined($set) && (($set ne"set") &&($set ne"unset")));  
    return "$target must be [actor|remote|both]"                  if(defined($target) && (($target ne"actor") &&
		                                                             ($target ne"remote")&&($target ne"both")));  
	return "use climate chan to pair TC"                          if($md eq "HM-CC-TC" &&$chn ne "02");
	return "use - single [set|unset] actor - for smoke detector"  if($st eq "smokeDetector" && 
		                                                             (!$single || $single ne "single" || $target ne "actor"));
	return "use - single - for this sensor"                       if(($md eq "ROTO_ZEL-STG-RM-FDK" || $md eq "HM-SEC-RHS") &&
		                                                             (!$single || $single ne "single"));
			   
	$single = ($single eq "single")?1:"";#default to dual
	$set = ($set eq "unset")?0:1;

	my ($b1,$b2,$nrCh2Pair);
	$b1 = ($isChannel) ? hex($chn):(!$bNo?"01":sprintf("%02X",$bNo));
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
  	              "++".$flag."01${id}${dst}${bStr}$cmd${peerDst}${peerChn}00");
  	      CUL_HM_pushConfig($hash,$id, $dst,$b,$peerDst,hex($peerChn),4,"0100")
				   if($md ne "HM-CC-TC");
	    }
      }
	}
	if (!$target || $target eq "actor" || $target eq "both"){
	  if (AttrVal( CUL_HM_id2Name($peerDst), "subType", "") eq "virtual"){
		CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b1),$set); #update peerlist
	  }
	  else{
	    my $peerFlag = CUL_HM_getFlag($peerHash);
        CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",
            $peerFlag,$id,$peerDst,$peerChn,$cmd,$dst,$b2,$b1 ));
	  }
	}
	return ("",1) if ($target && $target eq "remote");#Nothing to transmit for actor
    $devHash = $peerHash; # Exchange the hash, as the switch is always alive.
  }
  
  readingsSingleUpdate($hash,"state",$state,1) if($state);

  $rxType = CUL_HM_getRxType($devHash);
  Log GetLogLevel($name,2), "CUL_HM set $name " . join(" ", @a[1..$#a])." rxt:".$rxType;
  CUL_HM_ProcessCmdStack($devHash) if($rxType & 0x03);#all/burst
  return ("",1);# no not generate trigger outof command
}

###################################
my $updtValveCnt = 0;

sub
CUL_HM_valvePosUpdt(@)
{# update valve position periodically to please valve
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
	    #DoTrigger("global",  'UNDEFINED '.$chnName.' CUL_HM '.$chnId);
      }
	  $attr{CUL_HM_id2Name($chnId)}{model} = $model;
	  $chnNoTyp++;
	}
  }
  if ($culHmModel{$mId}{cyc}){
    CUL_HM_ActAdd($hash->{DEF},$culHmModel{$mId}{cyc});
  }

}
sub    #---------------------------------
CUL_HM_infoUpdtChanData(@)
{# delay this to ensure the device is already available
  my($in ) = @_;
  my($chnName,$chnId,$model ) = split(',',$in);
  DoTrigger("global",  'UNDEFINED '.$chnName.' CUL_HM '.$chnId);
  $attr{CUL_HM_id2Name($chnId)}{model} = $model;
}
sub    #---------------------------------
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
sub    #---------------------------------
CUL_HM_getConfig($$$$$){
  my ($hash,$chnhash,$id,$dst,$chn) = @_;
  my $flag = CUL_HM_getFlag($hash);
  
  foreach my $readEntry (keys %{$chnhash->{READINGS}}){
	  delete $chnhash->{READINGS}{$readEntry} if ($readEntry =~ m/^RegL_/);
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
sub    #---------------------------------
CUL_HM_SndCmd($$)
{
  my ($hash, $cmd) = @_;
  my $io = $hash->{IODev};

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
  CUL_HM_responseSetup($hash,$cmd);	
}
sub    #---------------------------------
CUL_HM_responseSetup($$)
{#store all we need to handle the response
 #setup repeatTimer and cmdStackControll
  my ($hash,$cmd) =  @_;
  my ($msgId, $msgFlag,$msgType,$dst,$p) = ($2,hex($3),$4,$6,$7)
      if ($cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/);
  my ($chn,$subType) = ($1,$2) if($p =~ m/^(..)(..)/); 
  my $rTo = 2; #default response timeout
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
	  $attr{$chnhash->{NAME}}{peerIDs} = '';
	  return;
    }
    elsif($subType eq "04"){ #RegisterRead-------
      my ($peer, $list) = ($1,$2) if ($p =~ m/..04(........)(..)/);
	  $peer = ($peer ne "00000000")?CUL_HM_peerChName($peer,$dst,""):"";
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending} = "RegisterRead";
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
      $chnhash->{READINGS}{"RegL_".$list.":".$peer}{VAL}=""; 
      delete ($chnhash->{READINGS}{"RegL_".$list.":".$peer}{TIME}); 
	  return;
    }
#    elsif($subType eq "0A"){ #Pair Serial----------
#	  #--- set messaging items
#	  $hash->{helper}{respWait}{Pending} = "PairSerial";
#	  $hash->{helper}{respWait}{forChn} = substr($p,4,20);
#      
#      # define timeout - holdup cmdStack until response complete or timeout
#	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
#	  return;
#    }
    elsif($subType eq "0E"){ #StatusReq----------
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending} = "StatusReq";
	  $hash->{helper}{respWait}{forChn} = $chn;
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+$rTo, "CUL_HM_respPendTout", "respPend:$dst", 0);
	  return;
    }
  }
  
  if (($msgFlag & 0x20) && ($dst ne '000000')){
    my $iohash = $hash->{IODev};
    $hash->{helper}{respWait}{cmd}    = $cmd;
    $hash->{helper}{respWait}{msgId}  = $msgId; #msgId we wait to ack
    $hash->{helper}{respWait}{reSent} = 1;
    
    my $off = 2;
    #$off += 0.15*int(@{$iohash->{QUEUE}}) if($iohash->{QUEUE});
    InternalTimer(gettimeofday()+$off, "CUL_HM_Resend", $hash, 0);
  }
}
sub    #---------------------------------
CUL_HM_eventP($$)
{ # handle protocol events
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
  }
}
sub    #---------------------------------
CUL_HM_respPendRm($)
{  # delete all response related entries in messageing entity
  my ($hash) =  @_;  
  delete ($hash->{helper}{respWait});
  RemoveInternalTimer($hash);          # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer
  $respRemoved = 1;
}
sub    #---------------------------------
CUL_HM_respPendTout($)
{
  my ($HMid) =  @_;  
  $HMid =~ s/.*://; #remove timer identifier
  my $hash = $modules{CUL_HM}{defptr}{$HMid};
  if ($hash && $hash->{DEF} ne '000000'){
    CUL_HM_eventP($hash,"Tout") if ($hash->{helper}{respWait}{cmd});
	my $pendCmd = $hash->{helper}{respWait}{Pending};# save before remove
    CUL_HM_eventP($hash,"ToutResp") if ($pendCmd);
	CUL_HM_respPendRm($hash);
	CUL_HM_ProcessCmdStack($hash); # continue processing commands
	readingsSingleUpdate($hash,"state","RESPONSE TIMEOUT:".$pendCmd,1);
  }
}
sub    #---------------------------------
CUL_HM_respPendToutProlong($) 
{#used when device sends part responses
  my ($hash) =  @_;  

  RemoveInternalTimer("respPend:$hash->{DEF}");
  InternalTimer(gettimeofday()+1, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}
sub    #---------------------------------
CUL_HM_PushCmdStack($$)
{
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
sub    #---------------------------------
CUL_HM_ProcessCmdStack($)
{
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
sub    #---------------------------------
CUL_HM_Resend($)
{#resend a message if there is no answer
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
    InternalTimer(gettimeofday()+1, "CUL_HM_Resend", $hash, 0);
  }
}
###################-----------helper and shortcuts--------################
################### Peer Handling ################
sub
CUL_HM_ID2PeerList ($$$)
{
  my($name,$peerID,$set) = @_;
  my $peerIDs = AttrVal($name,"peerIDs",""); 
  my $hash = CUL_HM_name2Hash($name);
  if (length($peerID) == 8){# wont add if not a channel - still update names
    $peerID = $peerID.",";
    $peerIDs =~ s/$peerID//;#avoid duplicate
    $peerIDs.= $peerID if($set);
  }
  if (!$peerIDs){ #list now empty
	delete $attr{$name}{peerIDs};
	delete ($hash->{READINGS}{peerList}); 
  }
  else{# update the human readable list
    $attr{$name}{peerIDs} = $peerIDs;
	my $dId = substr(CUL_HM_name2Id($name),0,6);
	my $peerListTmp = "";
    foreach my $pId (split(",",$peerIDs)){
	  next if (!$pId);
	  $peerListTmp .= (($dId eq substr($pId,0,6))?
	                                    ("self".substr($pId,6,2).","):
	                                    (CUL_HM_id2Name($pId).","));
    }
	readingsSingleUpdate($hash,"peerList",$peerListTmp,0);
  }
}
###################  Conversions  ################
sub    #---------------------------------
CUL_HM_getAssChnIds($)
{ # will return the list of assotiated channel of a device
  # if it is a channel only return itself
  # if device and no channel 
  my ($name) = @_;
  my @chnIdList;
  my $hash = CUL_HM_name2Hash($name);
  foreach my $channel (keys %{$hash}){
	next if ($channel !~ m/^channel_/);
	my $chnHash = CUL_HM_name2Hash($hash->{$channel});
	push @chnIdList,$chnHash->{DEF} if ($chnHash);
  }
  my $dId = CUL_HM_name2Id($name);

  push @chnIdList,$dId."01" if (length($dId) == 6 && !$hash->{channel_01});
  push @chnIdList,$dId if (length($dId) == 8);
  return sort(@chnIdList);
}
sub    #---------------------------------
CUL_HM_Id($)
{#in ioHash out ioHMid 
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME}, "hmId", "F1$fhtid");
}
sub    #---------------------------------
CUL_HM_hash2Id($)
{# in: id, out:hash
  my ($hash) = @_;
  return $hash->{DEF};
}
sub    #---------------------------------
CUL_HM_id2Hash($)
{# in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if ($modules{CUL_HM}{defptr}{$id});
  return $modules{CUL_HM}{defptr}{substr($id,0,6)}; # could be chn 01 of dev
}
sub    #---------------------------------
CUL_HM_name2Hash($)
{# in: name, out:hash
  my ($name) = @_;
  return $defs{$name};
}
sub    #---------------------------------
CUL_HM_name2Id(@)
{ # in: name or HMid ==>out: HMid, "" if no match
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
sub    #---------------------------------
CUL_HM_peerChId($$$)
{# peer Channel name from/for user entry. <IDorName> <deviceID> <ioID>
  my($pId,$dId,$iId)=@_;
  my $pSc = substr($pId,0,4); #helper for shortcut spread
  return $dId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'self');
  return $iId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'fhem');
  return "all"                                   if ($pId eq 'all');#used by getRegList
  my $repID = CUL_HM_name2Id($pId);
  $repID .= '01' if (length( $repID) == 6);# add default 01 if this is a device
  return $repID;                  
}
sub    #---------------------------------
CUL_HM_peerChName($$$)
{# peer Channel ID to user entry. <peerChId> <deviceID> <ioID>
  my($pId,$dId,$iId)=@_;
  my($pDev,$pChn) = ($1,$2) if ($pId =~ m/(......)(..)/);
  return 'self'.$pChn if ($pDev eq $dId);
  return 'fhem'.$pChn if ($pDev eq $iId);
  return CUL_HM_id2Name($pId);                
}
sub    #---------------------------------
CUL_HM_id2Name($)
{ # in: name or HMid out: name
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
sub    #---------------------------------
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
my @culHmCmdFlags = ("WAKEUP", "WAKEMEUP", "CFG", "Bit3",
                     "BURST", "BIDI", "RPTED", "RPTEN");
					 #RPTEN    0x80: set in every message. Meaning?
					 #RPTED    0x40: ???
                     #BIDI     0x20: response is expected
					 #Burst    0x10: set if burst is required by device
					 #Bit3     0x08:
					 #CFG      0x04: Device in Config mode 
					 #WAKEMEUP 0x02: awake - hurry up to send messages
					 #WAKEUP   0x01: send initially to keep the device awake

sub #------------------------
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
  	CUL_HM_SndCmd($shash, '++A112'.CUL_HM_Id($shash->{IODev}).$src);
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
	else{	  #ACK
	  $reply = ($subType eq "01")?"ACKStatus":"ACK"; 
	  $success = "yes";
	}
	readingsSingleUpdate($chnhash,"CommandAccepted",$success,1);
    CUL_HM_ProcessCmdStack($shash) 
	      if($dhash->{DEF} && (CUL_HM_Id($shash->{IODev}) eq $dhash->{DEF}));
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
    my $subtype = substr($p,0,2);
	if($subtype eq "01"){ #storePeerList#################
	  if ($pendType eq "PeerList"){
		my $chn = $shash->{helper}{respWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$src.$chn}; 
		$chnhash = $shash if (!$chnhash);
	    my $chnNname = $chnhash->{NAME};
		my @peers = substr($p,2,) =~ /(.{8})/g;
		foreach my $peer(@peers){	
    	  CUL_HM_ID2PeerList ($chnNname,$peer,1) if ($peer !~ m/^000000../);
		}
		
		if ($p =~ m/000000..$/) {# last entry, peerList is complete
          CUL_HM_respPendRm($shash);		  
		  # check for request to get List3 data
		  my $reqPeer = $chnhash->{helper}{getCfgList};
		  if ($reqPeer){
		    my $flag = CUL_HM_getFlag($shash);
		    my $id = CUL_HM_Id($shash->{IODev});
		    my $listNo = "0".$chnhash->{helper}{getCfgListNo};
		    my @peerID = split(",", AttrVal($chnNname,"peerIDs",""));
		    foreach my $peer (@peerID){
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
	elsif($subtype eq "02" ||$subtype eq "03"){ #ParamResp##################
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
		my $peerName = $shash->{helper}{respWait}{forPeer};
		my $regLN = "RegL_".$list.":".$peerName;
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
		        CUL_HM_peerChId($peerName,
						substr(CUL_HM_hash2Id($chnHash),0,6),"00000000"));
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		return "done";
	  }
	}  
	elsif($subtype eq "04"){ #ParamChange###################
	  my($chn,$peerID,$list,$data) = ($1,$2,$3,$4) if($p =~ m/^04(..)(........)(..)(.*)/);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  $chnHash = $shash if(!$chnHash); # will add param to dev if no chan
	  my $regLN = "RegL_".$list.":".CUL_HM_id2Name($peerID);
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
	elsif($subtype eq "06"){ #reply to status request#######
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
#  	CUL_HM_SndCmd($shash, '++A112'.CUL_HM_Id($shash->{IODev}).$src);
#	CUL_HM_ProcessCmdStack($shash);
  }
  return "";
}
#############################
sub
CUL_HM_getRegFromStore($$$$)
{#read a register from backup data
  my($name,$regName,$list,$peerId)=@_;
  my $hash = CUL_HM_name2Hash($name);
  my ($size,$pos,$conversion,$factor,$unit) = (8,0,"",1,""); # default
  my $addr = $regName;
  my $dId = substr(CUL_HM_name2Id($name),0,6);#id of device
  my $iId = CUL_HM_Id($hash->{IODev});        #id of IO device
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
							    
  my $regLN = "RegL_".sprintf("%02X",$list).":".CUL_HM_peerChName($peerId,$dId,$iId);
  $regLN =~ s/broadcast//;
  
  my $data=0;
  my $convFlg = "";# confirmation flag - indicates data not confirmed by device
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
    
	my $dReadS;
    if ($hash->{helper}{shadowReg}&&$hash->{helper}{shadowReg}{$regLN}){
      $dReadS = $1 if($hash->{helper}{shadowReg}{$regLN} =~ m/$addrS:(..)/);
    }
	my $dReadR;
    if ($hash->{READINGS}{$regLN}) {
      $dReadR = $1 if($hash->{READINGS}{$regLN}{VAL} =~ m/$addrS:(..)/);
    }
	$convFlg = "set_" if ($dReadS && $dReadR ne $dReadS);
    my $dRead = $dReadS?$dReadS:$dReadR;
	return "invalid" if (!defined($dRead));

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
#----------------------
sub
CUL_HM_updtRegDisp($$$)
{
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
  foreach my $regName (@regArr){
    next if (!$culHmRegDefine{$regName}->{d}            ||
	         ($culHmRegDefine{$regName}->{l} != $listNo));
    my $rgVal = CUL_HM_getRegFromStore($name,$regName,$list,$peerId);
	next if (!$rgVal || $rgVal eq "invalid");
	my $readName = "R-".$peer.$regName;
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
  my $m = int($v>>5);
  my $e = $v & 0x1f;
  my $mul = 0.1;
  return 2^$e*$m*0.1;
}
#############################
sub
CUL_HM_pushConfig($$$$$$$$)
{#routine will generate messages to write cnfig data to register
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
sub
CUL_HM_secSince2000()
{
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
  if ($attr{$actName}{peerList} && !$attr{$actName}{peerIDs}){#todo Updt1 remove
    $attr{$actName}{peerIDs} = $attr{$actName}{peerList};     #todo Updt1 remove
	delete ($attr{$actName}{peerList});                       #todo Updt1 remove
  }                                                           #todo Updt1 remove
  if (!$actHash->{helper}{first}){ # if called first time attributes are no yet
                                   #recovered
  	InternalTimer(gettimeofday()+3, "CUL_HM_ActGetCreateHash", "ActionDetector", 0);
	$actHash->{helper}{first} = 1;
	return;
  }
  if (!$actHash->{helper}{actCycle} ){ #This is the first call
    my $peerIDs = AttrVal($actName,"peerIDs","");
    my $tn = TimeNow();
	foreach my $devId (split(",",$peerIDs)){
	  $actHash->{helper}{$devId}{start} = $tn;
	  my $devName = CUL_HM_id2Name($devId);
	  readingsSingleUpdate($actHash,"status_".$devName,"unknown",1);	
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

  my $peerIDs = AttrVal($actName,"peerIDs","");
  $peerIDs .= $devId."," if($peerIDs !~ m/$devId,/);#add if not in
  $attr{$actName}{peerIDs} = $peerIDs; 
  my $tn = TimeNow();  
  $actHash->{helper}{$devId}{start} = $tn;
  readingsSingleUpdate($actHash,"status_".$devName,"unknown",1);	  
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

  $attr{$actName}{peerIDs} = "" if (!defined($attr{$actName}{peerIDs}));
  $attr{$actName}{peerIDs} =~ s/$devId,//g; 
  Log GetLogLevel($actName,3),"Device ".$devName." removed from ActionDetector";
}
sub
CUL_HM_ActCheck()
{# perform supervision
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $actName = $actHash->{NAME};
  my $peerIDs = AttrVal($actName,"peerIDs","none");
#  delete ($actHash->{READINGS}); #cleansweep
  my @event;
  push @event, "state:check_performed";

  foreach my $devId (split(",",$peerIDs)){
    my $devName = CUL_HM_id2Name($devId);
	if(!$devName || !defined($attr{$devName}{actCycle})){
	  CUL_HM_ActDel($devId); 
	  next;
	}
	my $rdName = "status_".$devName;
	my $state;
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
	if ($tSec == 0){# detection switched off
	  $state = "switchedOff";
	}
	else{
      my $devHash = CUL_HM_name2Hash($devName);
	  my $tLast = $devHash->{"protLastRcv"};
      my @t = localtime($tod - $tSec); #time since when a trigger is expected
	  my $tSince = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                             $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
      
	  if ((!$tLast || $tSince gt $tLast)){      #no message received in timeframe
            $state = "dead" if ($tSince gt $actHash->{helper}{$devId}{start});
 	  }else{$state = "alive";}
	}  
	if ($state && $attr{$devName}{actStatus} ne $state){

	  DoTrigger($devName,"Activity:".$state);
	  $attr{$devName}{actStatus} = $state;
      push @event, $rdName.":".$state;
	  Log GetLogLevel($actName,4),"Device ".$devName." is ".$state;
	}
  }
  CUL_HM_UpdtReadBulk($actHash,0,@event);
  
  $attr{$actName}{actCycle} = 600 if($attr{$actName}{actCycle}<30); 
  $actHash->{helper}{actCycle} = $attr{$actName}{actCycle};
  InternalTimer(gettimeofday()+$attr{$actName}{actCycle}, 
  								   "CUL_HM_ActCheck", "ActionDetector", 0);
}
sub
CUL_HM_UpdtReadBulk(@)
{ # update a bunch of readings and trigger the events
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
    module, together with the necessary hmClass and subType attributes.
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
      <li>the hmClass attribute<br>
          which is either sender or receiver</li>
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
      </ul>
    </li>

  </ul><br>

  <a name="CUL_HMset"></a>
  <b>Set</b>
  <ul>
     Note: devices which are normally send-only (remote/sensor/etc) must be set
     into pairing/learning mode in order to receive the following commands.
     <br>
     <br>

     General commands (available to most hm devices):
     <ul>
	 <li><B>actiondetect &lt;[hhh:mm]|off&gt;</B><a name="CUL_HMactiondetect"></a><br>
         Supports 'alive' or better 'not alive' detection for devices. [hhh:mm] is the maxumin silent time for the device. Upon no message received in this period an event will be raised "&lt;device&gt; is dead". If the device sends again another notification is posted "&lt;device&gt; is alive". <br>
		 This actiondetect will be autocreated for each device with build in cyclic status report. <br>
		 Controlling entity is a pseudo device "ActionDetector" with HMId "000000". <br>
		 Due to performance considerations the report latency is set to 600sec (10min). It can be controlled by the attribute "actCycle" of "ActionDetector".<br>
		 Once entered to the supervision the HM device has 2 attributes:<br>
		 <ul>
		 actStatus: activity status of the device<br>
		 actCycle:  detection period [hhh.mm]<br>
		 </ul>
		 Furthermore the overall function can be viewed checking out the "ActionDetector" entity. Here the status of all entities is present in the READING section. <br>
		 Note: This function can be enabled for devices with non-cyclic messages as well. It is up to the user to enter a reasonable cycletime.
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
         the 'internal links' it is necessary to issue 'set &lt;name&gt; setReg
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
     <li><B>regRaw [List0|List1|List2|List3|List4] &lt;addr&gt; &lt;data&gt;
         &lt;peerChannel&gt; </B><a name="CUL_HMregRaw"></a><br>
         Will set register for device or channel. See also <a
         href="#CUL_HMgetRegRaw">getRegRaw</a>.<br> &lt;addr&gt; and
         &lt;data&gt; are 1 byte values that need to be given in hex.<br>
	 Example:<br>
	 <ul><code>
	 set mydimmer regRaw List1 0B 10 00000000 <br>
	 set mydimmer regRaw List1 0C 00 00000000 <br>
	 </code></ul>
	 will set the max drive time up for a blind actor to 25,6sec</li>
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
         see also <a href="#CUL_HMpress">press</a></li>
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
	      Currently a max of 24h is supported with endtime.<br></li>
          <li><B>toggle</B> - toggle the switch.</li>
       </ul>
     <br></li>
    <li>dimmer, blindActuator
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
         <li><B>toggle</B> - toggle between off and the last on-value</li>
         <li><B><a href="#CUL_HMonForTimer">on-for-timer &lt;sec&gt;</a></B> - Dimmer only! <br></li>
         <li><B><a href="#CUL_HMonForTimer">on-till &lt;time&gt;</a></B> - Dimmer only! <br></li>
         <li><B>stop</B> - stop motion or dim ramp</li>
       </ul>
    <br></li>
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

         Example:<ul> <code>
           set myRemote devicepair 2 mySwActChn single set       # pair second button to an actuator channel<br>
           set myRmtBtn devicepair 0 mySwActChn single set       #myRmtBtn is a button of the remote. '0' is not processed here<br>
           set myRemote devicepair 2 mySwActChn dual set         #pair button 3 and 4<br>
           set myRemote devicepair 3 mySwActChn dual unset       #remove pairing for button 5 and 6<br>
           set myRemote devicepair 3 mySwActChn dual unset aktor #remove pairing for button 5 and 6 in actor only<br>
           set myRemote devicepair 3 mySwActChn dual set remote  #pair button 5 and 6 on remote only. Link settings il mySwActChn will be maintained<br>
         </code></ul>
    </li>
       </ul>
	<br></li>
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
       have to guess which of the detectors is the master.
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
          <ul><code>
          set 4Dis text 1 on On Lamp<br>
          set 4Dis text 1 off Kitchen Off<br>
          </code></ul>
    </ul></li>
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
    </ul></li><br>
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
    </ul><br></li>
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
    </ul><br></li>
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
      </ul><br></li>
    <li>keyMatic<br><br>
      <ul>The Keymatic uses the AES signed communication. Therefore the control
      of the Keymatic is only together with the HM-LAN adapter possible. But
      the CUL can read and react on the status information of the
      Keymatic.</ul><br>
      <ul>
      <li><B>lock</B><br>
         The lock bolt moves to the locking position<br></li>
      <li><B>unlock [sec]</B><br>
         The lock bolt moves to the unlocking position.<br> [sec]: Sets the
         delay in seconds after the lock automatically locked again.<br>0 -
         65535 seconds</li>
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
      </ul></li>
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
  </ul><br>

  <a name="CUL_HMget"></a>
  <b>Get</b><br>
     <ul>
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
    <li><a name="hmClass">hmClass</a>,
        <a name="model">model</a>,
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
      T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b
  <li>HM-CC-TC:<br>
      T: $t H: $h<br>
      temperature $t<br>
      humidity $h<br>
      actuator $vp%<br>
      desired-temp $t<br>
      desired-temp-ack $t<br>
      tempList$wd  hh:mm $t hh:mm $t ...<br>
      ValveErrorPosition $dname $vep%<br>
      ValveOffset $dname $of%<br>
      windowopentemp-$tchan $t (sensor:$tdev)<br>
  <li>HM-CC-VD:<br>
      actuator $vp%<br>
      motor [opening|closing|blocked|loose|adjusting range too small|ok]<br>
      battery [low|ok]<br>
      ValveErrorPosition $vep%<br>
      ValveOffset $dname $of%<br>
  <li>KFM100:<br>
      rawValue $v<br>
      Sequence $s<br>
      $cv $unit<br>
  <li>switch/dimmer/blindActuator:<br>
      deviceMsg [on|off|$val %]<br>
      poweron [on|off|$val]<br>
  <li>dimmer:<br>
      dim: [up|down|stop]<br>
  <li>HM-LC-BL1-PB-FM:<br>
      motor: [opening|closing]<br>
  <li>remote/pushButton<br>
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
      battery: [low|ok]<br>
  <li>swi<br>
      Btn$x toggle<br>
      Btn$x toggle (to $dest)<br>
      battery: [low|ok]<br>
  <li>motionDetector<br>
      brightness:$b<br>
      alive<br>
      motion<br>
      cover closed<br>
      cover open<br>
  <li>smokeDetector<br>
      state: [on|all-clear|alive]<br>
      smoke_detect on from $src<br>
      test:from $src<br>
      battery: [low|ok]<br>
	  SDteam:[add|remove]_$name<br>
  <li>threeStateSensor (all)<br>
      sabotage<br>
      alive<br>
  <li>threeStateSensor (HM-SEC-WDS)<br>
      contact wet<br>
      contact damp<br>
      contact dry<br>
  <li>threeStateSensor (generic)<br>
      contact closed<br>
      contact open<br>
      contact tilted<br>
  <li>THSensor<br>
      T: $t H: $h<br>
      temperature $t<br>
      humidity $h<br>
  <li>WDC7000<br>
      T: $t H: $h AP: $ap<br>
      temperature $t<br>
      humidity $h<br>
      airpress $ap<br>
  <li>winMatic<br>
      contact closed<br>
      contact open<br>
      contact tilted<br>
      contact movement_tilted<br>
      contact movement_closed<br>
      contact lock_on<br>
      airing: $air<br>
      course: tilt<br>
      course: close<br>
  </ul>
  <br>
</ul>
=end html
=cut
