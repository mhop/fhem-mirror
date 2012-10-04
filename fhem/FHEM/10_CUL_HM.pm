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
sub CUL_HM_convPendTout($);
sub CUL_HM_respPendRm($);
sub CUL_HM_respPendTout($);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_Resend($);
sub CUL_HM_Id($);
sub CUL_HM_name2hash($);
sub CUL_HM_Name2Id($);
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
  "C0" => { st => "keyMatic",        cl => "sender"   },
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
my %culHmModel=(
  "0001" => {name=>"HM-LC-SW1-PL-OM54"       ,rxt=>''       ,chn=>"",},
  "0002" => {name=>"HM-LC-SW1-SM"            ,rxt=>''       ,chn=>"",},
  "0003" => {name=>"HM-LC-SW4-SM"            ,rxt=>''       ,chn=>"Sw:1:4",},
  "0004" => {name=>"HM-LC-SW1-FM"            ,rxt=>''       ,chn=>"",},
  "0005" => {name=>"HM-LC-BL1-FM"            ,rxt=>''       ,chn=>"",},
  "0006" => {name=>"HM-LC-BL1-SM"            ,rxt=>''       ,chn=>"",},
  "0007" => {name=>"KS550"                   ,rxt=>''       ,chn=>"",},
  "0008" => {name=>"HM-RC-4"                 ,rxt=>'c'      ,chn=>"Btn:1:4",},
  "0009" => {name=>"HM-LC-SW2-FM"            ,rxt=>''       ,chn=>"Sw:1:2",},
  "000A" => {name=>"HM-LC-SW2-SM"            ,rxt=>''       ,chn=>"Sw:1:2",},
  "000B" => {name=>"HM-WDC7000"              ,rxt=>''       ,chn=>"",},
  "000D" => {name=>"ASH550"                  ,rxt=>'c:w'    ,chn=>"",},
  "000E" => {name=>"ASH550I"                 ,rxt=>'c:w'    ,chn=>"",},
  "000F" => {name=>"S550IA"                  ,rxt=>'c:w'    ,chn=>"",},
  "0011" => {name=>"HM-LC-SW1-PL"            ,rxt=>''       ,chn=>"",},
  "0012" => {name=>"HM-LC-DIM1L-CV"          ,rxt=>''       ,chn=>"",},
  "0013" => {name=>"HM-LC-DIM1L-PL"          ,rxt=>''       ,chn=>"",},
  "0014" => {name=>"HM-LC-SW1-SM-ATMEGA168"  ,rxt=>''       ,chn=>"",},
  "0015" => {name=>"HM-LC-SW4-SM-ATMEGA168"  ,rxt=>''       ,chn=>"Sw:1:4",},
  "0016" => {name=>"HM-LC-DIM2L-CV"          ,rxt=>''       ,chn=>"Sw:1:2",},
  "0018" => {name=>"CMM"                     ,rxt=>''       ,chn=>"",},
  "0019" => {name=>"HM-SEC-KEY"              ,rxt=>''       ,chn=>"",},
  "001A" => {name=>"HM-RC-P1"                ,rxt=>'c'      ,chn=>"",},
  "001B" => {name=>"HM-RC-SEC3"              ,rxt=>'c'      ,chn=>"Btn:1:3",},
  "001C" => {name=>"HM-RC-SEC3-B"            ,rxt=>'c'      ,chn=>"Btn:1:3",},
  "001D" => {name=>"HM-RC-KEY3"              ,rxt=>'c'      ,chn=>"Btn:1:3",},
  "001E" => {name=>"HM-RC-KEY3-B"            ,rxt=>'c'      ,chn=>"Btn:1:3",},
  "0022" => {name=>"WS888"                   ,rxt=>''       ,chn=>"",},
  "0026" => {name=>"HM-SEC-KEY-S"            ,rxt=>''       ,chn=>"",},
  "0027" => {name=>"HM-SEC-KEY-O"            ,rxt=>''       ,chn=>"",},
  "0028" => {name=>"HM-SEC-WIN"              ,rxt=>'b'      ,chn=>"",},
  "0029" => {name=>"HM-RC-12"                ,rxt=>'c'      ,chn=>"Btn:1:12",},
  "002A" => {name=>"HM-RC-12-B"              ,rxt=>'c'      ,chn=>"Btn:1:12",},
  "002D" => {name=>"HM-LC-SW4-PCB"           ,rxt=>''       ,chn=>"Sw:1:4",},
  "002E" => {name=>"HM-LC-DIM2L-SM"          ,rxt=>''       ,chn=>"Sw:1:2",},
  "002F" => {name=>"HM-SEC-SC"               ,rxt=>'c:w'    ,chn=>"",},
  "0030" => {name=>"HM-SEC-RHS"              ,rxt=>'c:w'    ,chn=>"",},
  "0034" => {name=>"HM-PBI-4-FM"             ,rxt=>'c'      ,chn=>"Btn:1:4",},
  "0035" => {name=>"HM-PB-4-WM"              ,rxt=>'c'      ,chn=>"Btn:1:4",},
  "0036" => {name=>"HM-PB-2-WM"              ,rxt=>'c'      ,chn=>"Btn:1:2",},
  "0037" => {name=>"HM-RC-19"                ,rxt=>'c:b'    ,chn=>"Btn:1:17,Disp:18",},
  "0038" => {name=>"HM-RC-19-B"              ,rxt=>'c:b'    ,chn=>"Btn:1:17,Disp:18",},
  "0039" => {name=>"HM-CC-TC"                ,rxt=>'c:w'    ,chn=>"",},
  "003A" => {name=>"HM-CC-VD"                ,rxt=>'c:w'    ,chn=>"",},
  "003B" => {name=>"HM-RC-4-B"               ,rxt=>'c'      ,chn=>"Btn:1:4",},
  "003C" => {name=>"HM-WDS20-TH-O"           ,rxt=>'c:w'    ,chn=>"",},
  "003D" => {name=>"HM-WDS10-TH-O"           ,rxt=>'c:w'    ,chn=>"",},
  "003E" => {name=>"HM-WDS30-T-O"            ,rxt=>'c:w'    ,chn=>"",},
  "003F" => {name=>"HM-WDS40-TH-I"           ,rxt=>'c:w'    ,chn=>"",},
  "0040" => {name=>"HM-WDS100-C6-O"          ,rxt=>'c:w'    ,chn=>"",},
  "0041" => {name=>"HM-WDC7000"              ,rxt=>''       ,chn=>"",},
  "0042" => {name=>"HM-SEC-SD"               ,rxt=>''       ,chn=>"",},
  "0043" => {name=>"HM-SEC-TIS"              ,rxt=>'c:w'    ,chn=>"",},
  "0044" => {name=>"HM-SEN-EP"               ,rxt=>'c:w'    ,chn=>"",},
  "0045" => {name=>"HM-SEC-WDS"              ,rxt=>'c:w'    ,chn=>"",},
  "0047" => {name=>"KFM-Sensor"              ,rxt=>''       ,chn=>"",},
  "0046" => {name=>"HM-SWI-3-FM"             ,rxt=>'c'      ,chn=>"Sw:1:3",},
  "0048" => {name=>"IS-WDS-TH-OD-S-R3"       ,rxt=>'c:w'    ,chn=>"",},
  "0049" => {name=>"KFM-Display"             ,rxt=>''       ,chn=>"",},
  "004A" => {name=>"HM-SEC-MDIR"             ,rxt=>'c:w'    ,chn=>"",},
  "004B" => {name=>"HM-Sec-Cen"              ,rxt=>''       ,chn=>"",},
  "004C" => {name=>"HM-RC-12-SW"             ,rxt=>'c'      ,chn=>"Btn:1:12",},
  "004D" => {name=>"HM-RC-19-SW"             ,rxt=>'c:b'    ,chn=>"Btn:1:17,Disp:18",},
  "004E" => {name=>"HM-LC-DDC1-PCB"          ,rxt=>''       ,chn=>"",},
  "004F" => {name=>"HM-SEN-MDIR-SM"          ,rxt=>'c:w'    ,chn=>"",},
  "0050" => {name=>"HM-SEC-SFA-SM"           ,rxt=>''       ,chn=>"",},
  "0051" => {name=>"HM-LC-SW1-PB-FM"         ,rxt=>''       ,chn=>"",},
  "0052" => {name=>"HM-LC-SW2-PB-FM"         ,rxt=>''       ,chn=>"Sw:1:2",},
  "0053" => {name=>"HM-LC-BL1-PB-FM"         ,rxt=>''       ,chn=>"",},
  "0054" => {name=>"DORMA_RC-H"              ,rxt=>'c'      ,chn=>"",},
  "0056" => {name=>"HM-CC-SCD"	             ,rxt=>'c:w'    ,chn=>"",},
  "0057" => {name=>"HM-LC-DIM1T-PL"          ,rxt=>''       ,chn=>"",},
  "0058" => {name=>"HM-LC-DIM1T-CV"          ,rxt=>''       ,chn=>"",},
  "0059" => {name=>"HM-LC-DIM1T-FM"          ,rxt=>''       ,chn=>"",},
  "005A" => {name=>"HM-LC-DIM2T-SM"          ,rxt=>''       ,chn=>"Sw:1:2",},
  "005C" => {name=>"HM-OU-CF-PL"             ,rxt=>''       ,chn=>"",},
  "005D" => {name=>"HM-Sen-MDIR-O"           ,rxt=>'c:w'    ,chn=>"",},
  "005F" => {name=>"HM-SCI-3-FM"             ,rxt=>'c:w'    ,chn=>"",},
  "0060" => {name=>"HM-PB-4DIS-WM"           ,rxt=>'c'      ,chn=>"",},
  "0061" => {name=>"HM-LC-SW4-DR"            ,rxt=>''       ,chn=>"Sw:1:4",},
  "0062" => {name=>"HM-LC-SW2-DR"            ,rxt=>''       ,chn=>"Sw:1:2",},
  "0064" => {name=>"DORMA_atent"             ,rxt=>'c'      ,chn=>"",},
  "0065" => {name=>"DORMA_BRC-H"             ,rxt=>'c'      ,chn=>"",},
  "0066" => {name=>"HM_LC_Sw4-WM"            ,rxt=>'b'      ,chn=>"Sw:1:4",},
  "0067" => {name=>"HM-LC_Dim1PWM-CV"        ,rxt=>''       ,chn=>"",},
  "0068" => {name=>"HM-LC_Dim1TPBU-FM"       ,rxt=>''       ,chn=>"",},
  "0069" => {name=>"HM-LC_Sw1PBU-FM"         ,rxt=>''       ,chn=>"",},
  "006A" => {name=>"HM-LC_Bl1PBU-FM"         ,rxt=>''       ,chn=>"",},
  "006B" => {name=>"HM-PB-2-WM55"            ,rxt=>'c:w'    ,chn=>"",},
  "006C" => {name=>"HM-LC-SW1-BA-PCB"        ,rxt=>'b'      ,chn=>"",},
  "006D" => {name=>"HM-OU-LED16"             ,rxt=>''       ,chn=>"Led:1:16",},
  "0075" => {name=>"HM-OU-CFM-PL"            ,rxt=>''       ,chn=>"Led:1:1,Mp3:2:2",},
  "0078" => {name=>"HM-Dis-TD-T"             ,rxt=>'b'      ,chn=>"",},
  "0079" => {name=>"ROTO_ZEL-STG-RM-FWT"     ,rxt=>'c:w'    ,chn=>"",},
  "0x7A" => {name=>"ROTO_ZEL-STG-RM-FSA"     ,rxt=>''       ,chn=>"",},
  "007B" => {name=>"ROTO_ZEL-STG-RM-FEP-230V",rxt=>''       ,chn=>"",},
  "007D" => {name=>"ROTO_ZEL-STG-RM-WT-2"    ,rxt=>'c:w'    ,chn=>"",},
  "007E" => {name=>"ROTO_ZEL-STG-RM-DWT-10"  ,rxt=>'c'      ,chn=>"",},
  "007F" => {name=>"ROTO_ZEL-STG-RM-FST-UP4" ,rxt=>'c'      ,chn=>"",},
  "0080" => {name=>"ROTO_ZEL-STG-RM-HS-4"    ,rxt=>'c'      ,chn=>"",},
  "0081" => {name=>"ROTO_ZEL-STG-RM-FDK"     ,rxt=>'c:w'    ,chn=>"",},
  "0082" => {name=>"Roto_ZEL-STG-RM-FFK"     ,rxt=>'c:w'    ,chn=>"",},  
  "0083" => {name=>"Roto_ZEL-STG-RM-FSS-UP3" ,rxt=>'c'      ,chn=>"",},  
  "0084" => {name=>"Schueco_263-160"         ,rxt=>'c:w'    ,chn=>"",},  
  "0086" => {name=>"263-146"                 ,rxt=>''       ,chn=>"",},
  "008D" => {name=>"Schueco_263-1350"        ,rxt=>'c:w'    ,chn=>"",},
  "008E" => {name=>"263-155"                 ,rxt=>'c'      ,chn=>"",},
  "008F" => {name=>"263-145"                 ,rxt=>'c'      ,chn=>"",},
  "0090" => {name=>"Schueco_263-162"         ,rxt=>'c:w'    ,chn=>"",},  
  "0092" => {name=>"Schueco_263-144"         ,rxt=>'c'      ,chn=>"",},  
  "0093" => {name=>"263-158"                 ,rxt=>'c:w'    ,chn=>"",},
  "0094" => {name=>"263-157"                 ,rxt=>'c:w'    ,chn=>"",},
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
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:1,0 dummy:1,0 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 " .
                       "hmClass:receiver,sender serialNr firmware devInfo ".
                       "rawToReadable unit ".
					   "chanNo device ".
					   "protCmdPend protLastRcv protSndCnt protSndLast protCmdDel protNackCnt protNackLast rxType ".
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
  return ""if ($src eq $id);#discard mirrored messages

  CUL_HM_DumpProtocol("RCV",$iohash,$len,$msgcnt,$msgFlag,$msgType,$src,$dst,$p);
  
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

      } elsif($culHmModel{$model}{name}) {
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

  # msgX used for duplicate detection - msgFlag and len removed
  my $msgX = "No:$msgcnt - t:$msgType s:$src d:$dst $p";
  if($shash->{lastMsg} && $shash->{lastMsg} eq $msgX) {
    Log GetLogLevel($name,4), "CUL_HM $name dup mesg";
    return ""; #return something to please dispatcher
  }else{
    $shash->{lastMsg} = $msgX;
  }
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

    if($shash->{cmdStack} && ($attr{$name}{rxType} =~ m/config/)) {
      CUL_HM_ProcessCmdStack($shash);# sender devices may have msgs stacked
	  push @event,"";
    } 
	else {
      push @event, CUL_HM_Pair($name, $shash,$cmd,$src,$dst,$p);
    }
    $sendAck = ""; #todo why is this special?
	
  } 
  elsif($cmd =~ m/^A0[01]{2}$/ && $dst eq $id) {#### Pairing-Request-Convers.
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

    if($cmd eq "8670" && $p =~ m/^(....)(..)/) {# weather event
      my (    $t,      $h) =  (hex($1), hex($2));# temp is 15 bit signed
      $t = ($t & 0x3fff)/10*(($t & 0x4000)?-1:1);
      push @event, "state:T: $t H: $h";
      push @event, "measured-temp:$t";# todo - why report this twice? Check and remove!
      push @event, "temperature:$t";
      push @event, "humidity:$h";

    }
    elsif($cmd eq "A258" && $p =~ m/^(..)(..)/) {#climate event
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $1, hex($2));
      $vp = int($vp/2.56+0.5);   # valve position in %
      push @event, "actuator:$vp %";

      # Set the valve state too, without an extra trigger
      if($dhash) {
        $dhash->{STATE} = "$vp %";
        $dhash->{READINGS}{state}{TIME} = $tn;
        $dhash->{READINGS}{state}{VAL} = "$vp %";
      }
    }
    # 0403 167DE9 01 05 05 16 0000 windowopen-temp chan 03, dev 167DE9 on slot 01
    elsif($cmd eq "A410" && $p =~ m/^0403(......)(..)0505(..)0000/) {
	  # change of chn 3(window) list 5 register 5 - a peer window changed!
      my ( $tdev,   $tchan,     $v1) = (($1), hex($2), hex($3));
	   push @event, sprintf("windowopen-temp-%d: %.1f (sensor:%s)"
	                        ,$tchan, $v1/2, $tdev);
    }
    # idea: remember  all possible 24 value-pairs per day and reconstruct list
    # everytime new values are set or received.
    elsif($cmd eq "A410" &&
       $p =~ m/^0402000000000(.)(..)(..)(..)(..)(..)(..)(..)(..)/) {
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
        my $msg = sprintf("tempList%s:", $wd);
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
	elsif($cmd eq "A410" && $p =~ m/^04020000000005(..)(..)/) {
      my ( $o1,    $v1) = (hex($1),hex($2));# only parse list 5 for chn 2
      my $msg;
      my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
      if($o1 == 1) { ### bitfield containing multiple values...
	    my %mode = (0 => "manual",1 => "auto",2 => "central",3 => "party");
        push @event,"displayMode:temperature ".(($v1 & 1)?" and humidity":" only");
        push @event,"displayTemp:"            .(($v1 & 2)?"setpoint"     :"actual");
        push @event,"displayTempUnit:"        .(($v1 & 4)?"fahrenheit"   :"celsius");
        push @event,"controlMode:"            .($mode{(($v1 & 0x18)>>3)});
        push @event,sprintf("decalcDay:%s", $days[($v1 & 0xE0)>>5]);

      } 
	  elsif($o1 == 2) {
	    my %pos = (0=>"Auto",1=>"Closed",2=>"Open",3=>"unknown");		  
        push @event,"tempValveMode:".$pos{(($v1 & 0xC0)>>6)};
      } 
	  else{
	    push @event,sprintf("param-change: offset=%s, value=%s", $o1, $v1);
	  }
    }
    elsif($cmd eq "A001" && $p =~ m/^01080900(..)(..)/) {
      my (   $of,     $vep) = 
         (hex($1), hex($2));
      push @event, "ValveErrorPosition $dname: $vep %";
      push @event, "ValveOffset $dname: $of %";
    }
    elsif(($cmd eq "A410" && $p =~ m/^0602(..)........$/) ||
          ($cmd eq "A112" && $p =~ m/^0202(..)$/)) {    # Set desired temp
      push @event, "desired-temp:" .sprintf("%0.1f", hex($1)/2);
    }
    elsif($cmd eq "8002" && $p =~ m/^0102(..)(....)/) { # Ack for fhem-command
      push @event, "desired-temp-ack:" .sprintf("%0.1f", hex($1)/2);
      # FIXME: following is needed, else a set won't show up.
      push @event, "desired-temp:" .sprintf("%0.1f", hex($1)/2);
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
	CUL_HM_ProcessCmdStack($shash);
  } 
  elsif($model eq "HM-CC-VD") { ###################
    # CMD:8202 SRC:13F251 DST:15B50D 010100002A
    # status ACK to controlling HM-CC-TC
    if($msgType eq "02" && $p =~ m/^(..)(..)(..)(..)/) {#subtype+chn+value+err
      my (   $vp,     $st) =
         (hex($3), hex($4));
      $vp = int($vp)/2;   # valve position in %
      push @event, "actuator:$vp %";

      # Status-Byte Auswertung
      push @event, "motor:opening" if($st&0x10);
      push @event, "motor:closing" if($st&0x20);
      push @event, "motor:blocked" if($st&0x06) == 2;
      push @event, "motor:loose" if($st&0x06) == 4;
      push @event, "motor:adjusting range too small" if($st&0x06) == 6;
      push @event, "motor:ok" if($st&0x06) == 0;
      push @event, "battery:". (($st&0x08)?"low":"ok");
    }

    # CMD:A010 SRC:13F251 DST:5D24C9 0401 00000000 05 09:00 0A:07 00:00
    # status change report to paired central unit
	#read List5 reg 09 (offset) and 0A (err-pos)
	#list 5 is channel-dependant not link dependant
	#        => Link discriminator (00000000) is fixed
    elsif($msgType eq "10" && $p =~ m/^0401000000000509(..)0A(..)/) {
      my (    $of,     $vep) = 
        (hex($1), hex($2));
      push @event, "valve error position:$vep %";
      push @event, "ValveOffset $dname: $of %";
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

      my ($subType,$chn,$level,$addVal) = ($1,$2,$3,hex($4)) 
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
      push @event, "$eventName:up:$val"   if($addVal&0x10);# see HM-CC-VDstates
      push @event, "$eventName:down:$val" if($addVal&0x20);#       align names
      push @event, "$eventName:stop:$val" if($addVal&0x40 || (($addVal == 0) &&
	                                                       ($st ne "switch")));
	  push @event, "battery:" . (($addVal&0x80) ? "low" : "ok" )
	                                     if($model eq "HM-LC-SW1-BA-PCB");
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
	  }else{# Button not defined, use default naming
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
      }else{
        $state .= ($st eq "swi")?"toggle":"Short";#swi only support toggle
      }

      push @event, "state:$btnName $state$target";
      push @event, "battery:". (($buttonField & 0x80) ? "low" : "ok"); #By peterp
      if($id eq $dst && $msgType ne "02") {  # Send Ack
        CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."0101".
                ($state =~ m/on/?"C8":"00")."00", 1, 0);#todo why that???
				                         # did someone simulate an actor?
										 # a normal ack should do - or?
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
        my $devState = $shash->{READINGS}{color}{VAL};
	    $devState = "00000000" if (!$devState);
		if($parse eq "powerOn"){# reset LEDs after power on
		  CUL_HM_PushCmdStack($shash,sprintf("++A011%s%s8100%s",$id,$src,$devState));
		  CUL_HM_ProcessCmdStack($shash);
		}
		else {# just update datafields in storage
 	      my $bitLoc = ((hex($msgChn)-1)*2);#calculate bit location
 	      my $mask = 3<<$bitLoc;
 	      my $value = (hex($devState) &~$mask)|($msgState<<$bitLoc);
          $shash->{READINGS}{color}{TIME} = $tn;
          $shash->{READINGS}{color}{VAL} = sprintf("%08X",$value);	 
 	      if ($chnHash){
 	      $shash = $chnHash;
 	        my %colorTable=("00"=>"off","01"=>"red","02"=>"green","03"=>"orange");
 	        my $actColor = $colorTable{$msgState};
 	        $actColor = "unknown" if(!$actColor);
            $chnHash->{READINGS}{color}{TIME} = $tn;
            $chnHash->{READINGS}{color}{VAL} = $actColor;
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
    if($msgType eq "10" && $p =~ m/^06..(..)(..)/) {#InfoLevel
	  my $addVal;
      ($state, $addVal) = ($1, hex($2));
      push @event, "brightness:".hex($state);
      push @event, "state:alive";
      push @event, "cover:".   (($addVal&0x0E eq "00")?"closed":"open");        
	  push @event, "battery:". (($addVal&0x80)        ?"low"   :"ok"  );
    }
    elsif($msgType eq "41" && $p =~ m/^..(......)/) {
      $state = $1;
      push @event, "state:motion";
      push @event, "motion:on$target"; #added peterp
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
      my ($b12, $b34, $state, $err) = ($1, $2, $3, $4);
      my $chn = ($msgType eq "41")?$b12:$b34;
      my $addState = "";
      
	  if ($msgType eq "02"||$msgType eq "10"){
		push @event, "alive:yes";
        if($err) {
          push @event, "battery:". ((hex($err) & 0x80) ? "low" : "ok");
		  if (!$model eq "HM-SEC-WDS"){
			$addState =" cover: ".(($err =~ m/^.E/) ? "open" : "closed");		  
		  }
        }
	  }

      my %txt;
      %txt = ("C8"=>"open", "64"=>"tilted", "00"=>"closed");
      %txt = ("C8"=>"wet",  "64"=>"damp",   "00"=>"dry")  # by peterp
                   if($model eq "HM-SEC-WDS");
      my $txt = $txt{$state};
      $txt = "unknown:$state" if(!$txt);
      push @event, "state:$txt$addState";
	  push @event, "contact:$txt$target";

      # Multi-channel device: Switch to channel hash
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  
      CUL_HM_SendCmd($shash, $msgcnt."8002$id$src${chn}00",1,0)  # Send Ack
                             if($id eq $dst);
      $sendAck = ""; #todo why is this special?
    }

    push @event, "3SSunknownMsg:$p" if(!@event);
  } 
  elsif($model eq "HM-WDC7000" ||$st eq "THSensor") { ####################

	my $t =  hex(substr($p,0,4))/10;
    $t -= 3276.8 if($t > 1638.4);
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
    
    if($msgType eq "10" && $p =~ m/^0601(..)(..)/) {
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

    if($msgType eq "10" && $p =~ m/^0287(..)89(..)8B(..)/) {
      my ($air, undef, $course) = ($1, $2, $3);
      push @event, "airing:".
      ($air eq "FF" ? "inactiv" : CUL_HM_decodeTime8($air));
      push @event, "course:".($course eq "FF" ? "tilt" : "close");
    }

    if($msgType eq "10" &&
       $p =~ m/^0201(..)03(..)04(..)05(..)07(..)09(..)0B(..)0D(..)/) {

      my ($flg1, $flg2, $flg3, $flg4, $flg5, $flg6, $flg7, $flg8) =
         ($1, $2, $3, $4, $5, $6, $7, $8);
      push @event, "airing:".($flg5 eq "FF" ? "inactiv" : CUL_HM_decodeTime8($flg5));
      push @event, "contact:tesed";
    } 

  }
  else{#####################################
    ; # no one wants the message
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
      push @changed, "$vn: $vv";

    }
    $shash->{READINGS}{$vn}{TIME} = $tn;
    $shash->{READINGS}{$vn}{VAL} = $vv;
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
	# uc: unconversion, revert conversion to make data visible
	# u: unit for description
	# t: txt description
	# caution: !!! bitfield setting will zero the rest of the register
	#              if  less then a byte                    !!!!!!!!!!!
my %culHmRegDefine = (

  intKeyVisib  =>{a=>  2.7,s=>0.1,l=>0,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"bool",t=>"visibility of internal keys"},
  #blindActuator mainly   
  driveUp      =>{a=> 13.0,s=>2.0,l=>1,min=>0  ,max=>6000.0,c=>'$d=$d*10'            ,uc=>'$d=$d/10'            ,u=>"s"   ,t=>"drive time up"},
  driveDown    =>{a=> 11.0,s=>2.0,l=>1,min=>0  ,max=>6000.0,c=>'$d=$d*10'            ,uc=>'$d=$d/10'            ,u=>"s"   ,t=>"drive time up"},
  driveTurn    =>{a=> 15.0,s=>2.0,l=>1,min=>0  ,max=>6000.0,c=>'$d=$d*10'            ,uc=>'$d=$d/10'            ,u=>"s"   ,t=>"fliptime up <=>down"},
  maxTimeFSh   =>{a=> 29.0,s=>1.0,l=>3,min=>0  ,max=>25.4  ,c=>'$d=$d*10'            ,uc=>'$d=$d/10'            ,u=>"s"   ,t=>"Short:max time first direction"},
  maxTimeFLg   =>{a=>157.0,s=>1.0,l=>3,min=>0  ,max=>25.4  ,c=>'$d=$d*10'            ,uc=>'$d=$d/10'            ,u=>"s"   ,t=>"Long:max time first direction"},
  #remote mainly                                                                                                
  backOnTime   =>{a=> 14.0,s=>1.0,l=>0,min=>0  ,max=>255   ,c=>""                    ,uc=>""                    ,u=>"s"   ,t=>"Backlight On Time"},
  backAtEvnt   =>{a=> 13.5,s=>0.3,l=>0,min=>0  ,max=>8     ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Backlight at key=4,motion=2,charge=1"},
  longPress    =>{a=>  4.4,s=>0.4,l=>1,min=>0.3,max=>1.8   ,c=>'$d=$d*10-3'          ,uc=>'$d=($d+3)/10'        ,u=>"s"   ,t=>"time to detect key long press"},
  msgShowTime  =>{a=> 45.0,s=>1.0,l=>1,min=>0.0,max=>120   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"s"   ,t=>"Message show time(RC19). 0=always on"},
  #dimmer  mainly                                                                                               
  ovrTempLvl   =>{a=> 50.0,s=>1.0,l=>1,min=>30 ,max=>100   ,c=>""                    ,uc=>""                    ,u=>"degC",t=>"overtemperatur level"},
  redTempLvl   =>{a=> 52.0,s=>1.0,l=>1,min=>30 ,max=>100   ,c=>""                    ,uc=>""                    ,u=>"degC",t=>"reduced temperatur recover"},
  redLvl       =>{a=> 53.0,s=>1.0,l=>1,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"reduced power level"},

  OnDlySh      =>{a=>  6.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:on delay "},
  OnTimeSh     =>{a=>  7.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:on time"},
  OffDlySh     =>{a=>  8.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:off delay"},
  OffTimeSh    =>{a=>  9.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:off time"},

  OffLevelSh   =>{a=> 15.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:PowerLevel Off"},
  OnMinLevelSh =>{a=> 16.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:minimum PowerLevel"},
  OnLevelSh    =>{a=> 17.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:PowerLevel on"},

  rampSstepSh  =>{a=> 18.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:rampStartStep"},
  rampOnTimeSh =>{a=> 19.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:rampOnTime"},
  rampOffTimeSh=>{a=> 20.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Short:rampOffTime"},
  dimMinLvlSh  =>{a=> 21.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:dimMinLevel"},
  dimMaxLvlSh  =>{a=> 22.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:dimMaxLevel"},
  dimStepSh    =>{a=> 23.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Short:dimStep"},

  OnDlyLg      =>{a=>134.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:on delay"},
  OnTimeLg     =>{a=>135.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:on time"},
  OffDlyLg     =>{a=>136.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:off delay"},
  OffTimeLg    =>{a=>137.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:off time"},

  OffLevelLg   =>{a=>143.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:PowerLevel Off"},
  OnMinLevelLg =>{a=>144.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:minimum PowerLevel"},
  OnLevelLg    =>{a=>145.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:PowerLevel on"},

  rampSstepLg  =>{a=>146.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:rampStartStep"},
  rampOnTimeLg =>{a=>147.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:off delay"},
  rampOffTimeLg=>{a=>148.0,s=>1.0,l=>3,min=>0  ,max=>111600,c=>'$d=CUL_HM_fltCvT($d)',uc=>'$d=CUL_HM_CvTflt($d)',u=>"s"   ,t=>"Long:off delay"},
  dimMinLvlLg  =>{a=>149.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:dimMinLevel"},
  dimMaxLvlLg  =>{a=>150.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:dimMaxLevel"},
  dimStepLg    =>{a=>151.0,s=>1.0,l=>3,min=>0  ,max=>100   ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"%"   ,t=>"Long:dimStep"},
  #tc
  BacklOnTime  =>{a=>5.0  ,s=>0.6,l=>0,min=>1  ,max=>25    ,c=>""                    ,uc=>""                    ,u=>"s"   ,t=>"Backlight ontime"},
  BacklOnMode  =>{a=>5.6  ,s=>0.2,l=>0,min=>0  ,max=>1     ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"bool",t=>"Backlight mode 0=OFF, 1=AUTO"},
  BtnLock      =>{a=>15   ,s=>1  ,l=>0,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"bool",t=>"Button Lock 0=OFF, 1=Lock"},
  DispTempHum  =>{a=>1.0  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"bool",t=>"0=temp ,1=temp-humidity"},
  DispTempInfo =>{a=>1.1  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"bool",t=>"0=actual ,1=setPoint"},
  DispTempUnit =>{a=>1.2  ,s=>0.1,l=>5,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"bool",t=>"0=Celsius ,1=Fahrenheit"},
  MdTempReg    =>{a=>1.3  ,s=>0.2,l=>5,min=>0  ,max=>3     ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"0=MANUAL ,1=AUTO ,2=CENTRAL ,3=PARTY"},
  MdTempValve  =>{a=>2.6  ,s=>0.2,l=>5,min=>0  ,max=>2     ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"0=auto ,1=close ,2=open"},
  TempComfort  =>{a=>3    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"C"   ,t=>"confort temp value"},
  TempLower    =>{a=>4    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"C"   ,t=>"confort temp value"},
  PartyEndDay  =>{a=>98   ,s=>1  ,l=>6,min=>0  ,max=>200   ,c=>""                    ,uc=>""                    ,u=>"d"   ,t=>"Party end Day"},
  PartyEndMin  =>{a=>97.7 ,s=>1  ,l=>6,min=>0  ,max=>1     ,c=>""                    ,uc=>""                    ,u=>"min" ,t=>"Party end 0=:00, 1=:30"},
  PartyEndHr   =>{a=>97   ,s=>0.6,l=>6,min=>0  ,max=>23    ,c=>""                    ,uc=>""                    ,u=>"h"   ,t=>"Party end Hour"},
  TempParty    =>{a=>6    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"C"   ,t=>"Temperature for Party"},
  TempWinOpen  =>{a=>5    ,s=>0.6,l=>5,min=>6  ,max=>30    ,c=>'$d=$d*2'             ,uc=>'$d=$d/2'             ,u=>"C"   ,t=>"Temperature for Win open !chan 3 only!"},
  DecalDay     =>{a=>1.5  ,s=>0.3,l=>5,min=>0  ,max=>7     ,c=>""                    ,uc=>""                    ,u=>"d"   ,t=>"Decalc weekday 0=Sat...6=Fri"},
  DecalHr      =>{a=>8.3  ,s=>0.5,l=>5,min=>0  ,max=>23    ,c=>""                    ,uc=>""                    ,u=>"h"   ,t=>"Decalc hour"},
  DecalMin     =>{a=>8    ,s=>0.5,l=>5,min=>0  ,max=>50    ,c=>'$d=$d/10'            ,uc=>'$d=$d/10'            ,u=>"min" ,t=>"Decalc min"},
  #output Unit
  ActTypeSh     =>{a=>36  ,s=>1  ,l=>3,min=>0  ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Short:Action type(LED or Tone)"},
  ActNumSh      =>{a=>37  ,s=>1  ,l=>3,min=>1  ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Short:Action Number"},
  IntenseSh     =>{a=>47  ,s=>1  ,l=>3,min=>10 ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Short:Volume - Tone channel only!"},
  
  ActTypeLg     =>{a=>164 ,s=>1  ,l=>3,min=>0  ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Long:Action type(LED or Tone)"},
  ActNumLg      =>{a=>165 ,s=>1  ,l=>3,min=>1  ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Long:Action Number"},
  IntenseLg     =>{a=>175 ,s=>1  ,l=>3,min=>10 ,max=>255   ,c=>""                    ,uc=>""                    ,u=>""    ,t=>"Long:Volume - Tone channel only!"},

  );
my %culHmRegGeneral = (
  intKeyVisib=>1,
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
  ClimateControl=>{	
			DispTempHum  =>1,DispTempInfo =>1,DispTempUnit =>1,MdTempReg   =>1,
			MdTempValve  =>1,TempComfort  =>1,TempLower    =>1,PartyEndDay =>1,
			PartyEndMin  =>1,PartyEndHr   =>1,TempParty    =>1,DecalDay    =>1,
			TempWinOpen  =>1,
			DecalHr      =>1,DecalMin     =>1, 
            BacklOnTime  =>1,BacklOnMode  =>1,BtnLock      =>1,
			},	
  outputUnit=>{
			OnDlySh   =>1,OnTimeSh  =>1,OffDlySh  =>1,OffTimeSh =>1,
			OnDlyLg   =>1,OnTimeLg  =>1,OffDlyLg  =>1,OffTimeLg =>1,
			ActTypeSh =>1,ActNumSh  =>1,IntenseSh =>1,
			ActTypeLg =>1,ActNumLg  =>1,IntenseLg =>1,
			},
);
##--------------- Conversion routines for register settings
my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111600);
sub 
CUL_HM_fltCvT($) #float config time
{  
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT){
    $div2 = $div;
	last if ($inValue < $fltCvT{$div});
	$exp++;
  }
  return ($exp<<5)+int($inValue/$div2);
}
sub 
CUL_HM_CvTflt($) # config time -> float
{
  my ($inValue) = @_;
  return ($inValue & 0x1f)*((sort {$a <=> $b} keys(%fltCvT))[$inValue>>5]);
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
  my $class = AttrVal($devName, "hmClass", "");#relevant is the chief
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $chn = "01";
  if(length($dst) == 8) {       # shadow switch device for multi-channel switch
    $chn = substr($dst, 6, 2);
    $dst = substr($dst, 0, 6);
  }
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $h = $culHmGlobalGets{$cmd};
  $h = $culHmSubTypeGets{$st}{$cmd} if(!defined($h) && $culHmSubTypeGets{$st});
  $h = $culHmModelGets{$md}{$cmd}   if(!defined($h) && $culHmModelGets{$md});
  my @h;
  @h = split(" ", $h) if($h);
  my $isSender = ($class eq "sender");

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
  my $state = join(" ", @a[1..(int(@a)-1)]);

  #----------- now start processing --------------
  if($cmd eq "param") {  ###################################################
	my $entityName = $name;
	my $entityHash = $hash;
	foreach (1,2){                                #search channel and device
	  foreach my $entAttr (keys %{$attr{$entityName}}){ 
	    if (ref($attr{$entAttr}) eq "HASH"){
	      foreach my $entAttr2 (keys %{{$attr{$entityName}{$entAttr}}}){ 	
	        return $attr{$entityName}{$entAttr}{$entAttr2} if ($a[2] eq $entAttr2);
	      }
	    }
		else{
		  return $attr{$entityName}{$entAttr} if ($a[2] eq $entAttr);
		}
	  }
      foreach my $entAttr (keys %{$entityHash}){ 		
	    if (ref($entityHash->{$entAttr}) eq "HASH"){
	      foreach my $entAttr2 (keys %{$entityHash->{$entAttr}}){ 
            if ($entAttr eq "READINGS" && $entAttr2 eq $a[2]){
			  return $entityHash->{$entAttr}{$entAttr2}{VAL};# if ($entAttr2{VAL});
            }
			if (ref($entityHash->{$entAttr}{$entAttr2}) eq "HASH"){
	          foreach my $entAttr3 (keys %{$entityHash->{$entAttr}{$entAttr2}}){ 	
	            return "3:".$entAttr.":".$entAttr2.":".$entityHash->{$entAttr}{$entAttr2}{$entAttr3} if ($a[2] eq $entAttr3);
	          }
			}
			else {
	          return "2:".$entityHash->{$entAttr}{$entAttr2} if ($a[2] eq $entAttr2);
			}
	      }
	    }
	    else{
	      return "1:".$entityHash->{$entAttr} if ($a[2] eq $entAttr);
	    }
     }
	  last if ($entityName eq $devName);
	  $entityName = $devName; # search deivce if nothing was found in channel
	  $entityHash = $devHash;
	}
	
	return "undefined";	
  }
  elsif($cmd eq "reg") {  ##################################################
    my (undef,undef,$addr,$list,$peerId) = @a;
    my $regVal = CUL_HM_getRegFromStore($name,$addr,$list,$peerId);
	return ($regVal eq "invalid")? "Value not captured" 
	                             : "0x".sprintf("%X",$regVal)." dec:".$regVal;
  }
  elsif($cmd eq "regList") {  ##################################################
    my @arr = keys %culHmRegGeneral ;
	push @arr, keys %{$culHmRegSupported{$st}} if($culHmRegSupported{$st});  
    my $info = $st." - \n";	
	foreach my $regName (@arr){
	  my $reg  = $culHmRegDefine{$regName};	  
	  $info .= $regName." range:". $reg->{min}." to ".$reg->{max}.$reg->{u}.
	          ((($reg->{l} == 3)||($reg->{l} == 4))?" peer required":"")
			  ." : ".$reg->{t}."\n";
	}
	return $info;
  }

  $hash->{STATE} = $state if($state);
  Log GetLogLevel($name,2), "CUL_HM set $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($devHash) 
           if(!$attr{$name}{rxType}||$attr{$name}{rxType}=~ m/burst/);
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
        { devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]",
		  press => "[long|short]...",
		  virtual       =>"<noButtons>",}, #redef necessary for virtual
  smokeDetector =>
        { test => "", "alarmOn"=>"", "alarmOff"=>"", },
  winMatic =>
        { matic  => "<btn>",
          read   => "<btn>",
          keydef => "<btn> <txt1> <txt2>",
          create => "<txt>" },
);
my %culHmModelSets = (
  "HM-CC-TC"=>{ 
          "day-temp"     => "temp",
          "night-temp"   => "temp",
          "party-temp"   => "temp",
          "desired-temp" => "temp", # does not work - only in manual mode??
          "tempListSat"  => "HH:MM temp ...",
          "tempListSun"  => "HH:MM temp ...",
          "tempListMon"  => "HH:MM temp ...",
          "tempListTue"  => "HH:MM temp ...",
          "tempListThu"  => "HH:MM temp ...",
          "tempListWed"  => "HH:MM temp ...",
          "tempListFri"  => "HH:MM temp ...",
          "displayMode"  => "[temp-only|temp-hum]",
          "displayTemp"  => "[actual|setpoint]",
          "displayTempUnit" => "[celsius|fahrenheit]",
          "controlMode"  => "[manual|auto|central|party]",
          "decalcDay"    => "day",        },
	"HM-RC-19"=>  {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
	"HM-RC-19-B"=>  {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
	"HM-RC-19-SW"=>  {	
		  service   => "<count>", 
		  alarm     => "<count>", 
		  display   => "<text> [comma,no] [unit] [off|1|2|3] [off|on|slow|fast] <symbol>",},
    "HM-PB-4DIS-WM"=> {
	      text      => "<btn> [on|off] <txt1> <txt2>",},
	"HM-OU-LED16" =>{
		  led    =>"[off|red|green|orange]" ,
		  ilum   =>"[0-15] [0-127]" },
    "HM-OU-CFM-PL"=>{
	      led       => "<color>[,<color>..]",
		  playTone  => "<MP3No>[,<MP3No>..]",},
);

sub
CUL_HM_Set($@)
{
  my ($hash, @a) = @_;
  my ($ret, $tval, $rval); #added rval for ramptime by unimatrix

  return "no set value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $devName = $attr{$name}{device};# get devName as protocol entity
  $devName = $name if (!$devName); # we control ourself if no chief available
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");
  my $class = AttrVal($devName, "hmClass", "");#relevant is the device
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $chn = (length($dst) == 8)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);

  my $chash = CUL_HM_getDeviceHash($hash);

  my $h = $culHmGlobalSets{$cmd} if($st ne "virtual");
  $h = $culHmSubTypeSets{$st}{$cmd} if(!defined($h) && $culHmSubTypeSets{$st});
  $h = $culHmModelSets{$md}{$cmd}   if(!defined($h) && $culHmModelSets{$md});
  my @h;
  @h = split(" ", $h) if($h);

  my $isSender = ($class eq "sender");

  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
    $cmd = "pct";

  } 
  elsif(!defined($h)) {
    my @arr = keys %culHmGlobalSets if($st ne "virtual");
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
  my $state = join(" ", @a[1..(int(@a)-1)]);

  if($cmd eq "raw") {  ##################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
    for (my $i = 2; $i < @a; $i++) {
      CUL_HM_PushCmdStack($hash, $a[$i]);
    }
    $state = "";

  } 
  elsif($cmd eq "reset") { ############################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s0400", $id,$dst));

  } 
  elsif($cmd eq "pair") { #############################################
    return "pair is not enabled for this type of device, ".
                "use set <IODev> hmPairForSec"
        if($isSender);

    my $serialNr = AttrVal($name, "serialNr", undef);
    return "serialNr is not set" if(!$serialNr);
    CUL_HM_PushCmdStack($hash,
        sprintf("++A401%s000000010A%s", $id, unpack("H*",$serialNr)));
    $hash->{hmPairSerial} = $serialNr;

  } 
  elsif($cmd eq "unpair") { ###########################################
    CUL_HM_pushConfig($hash, $id, $dst, 0,0,0,0, "02010A000B000C00");

  } 
  elsif($cmd eq "sign") { ############################################
    CUL_HM_pushConfig($hash, $id, $dst, $chn,0,0,$chn,
                    "08" . ($a[2] eq "on" ? "01":"02"));

  } 
  elsif($cmd eq "statusRequest") { ############################################
	my $chnFound;
    foreach my $channel (keys %{$attr{$name}}){
	  next if ($channel !~ m/^channel_/);
	  my $chnHash = CUL_HM_name2hash($attr{$name}{$channel});
	  if ($chnHash){
	    my $chnNo = $chnHash->{DEF};
		$chnNo = substr($chnNo,6,2);
	    $chnFound = 1 if ($chnNo eq "01");
		CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s0E", $id,$dst,$chnNo));
	  }
    }
	# if channel or single channel device
	CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s0E", $id,$dst,$chn))
	    if (!$chnFound);
  } 
  elsif($cmd eq "getpair") { ##################################################
    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s00040000000000", $id,$dst));
	
  } 
  elsif($cmd eq "getdevicepair") { ############################################
    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s03", $id,$dst, $chn));

  } 
  elsif($cmd eq "getConfig") { ################################################
    CUL_HM_PushCmdStack($hash, "++A112$id$dst") if($attr{$name}{rxType} =~ m/wakeup/);     # Wakeup...
    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s00040000000000",$id,$dst))
	    if (length($dst) == 6);
	my $chnFound;
    foreach my $channel (keys %{$attr{$name}}){
	  next if ($channel !~ m/^channel_/);
	  my $chnHash = CUL_HM_name2hash($attr{$name}{$channel});
	  if ($chnHash){
	    my $chnNo = $chnHash->{DEF};
		$chnNo = substr($chnNo,6,2);
	    $chnFound = 1 if ($chnNo eq "01");
		CUL_HM_getConfig($hash,$chnHash,$id,$dst,$chnNo);
	  }
    }
	# if channel or single channel device
	CUL_HM_getConfig($hash,$hash,$id,$dst,$chn)if (!$chnFound);

  } 
  elsif($cmd eq "regRaw" ||$cmd eq "getRegRaw") { #############################
    my ($list,$addr,$data,$peerID);
	($list,$addr,$data,$peerID) = ($a[2],hex($a[3]),hex($a[4]),$a[5])
	                               if ($cmd eq "regRaw");
	($list,$peerID) = ($a[2],$a[3])if ($cmd eq "getRegRaw");
	$list =~ s/List/0/;# convert Listy to 0y
	# as of now only hex value allowed check range and convert

	$chn = "00" if ($list eq "00");
    if ($list =~m /0[34]/){# peer required for List 3 and 4
	  my $tmpPeerID = ($peerID eq "all")?"all": CUL_HM_Name2Id($peerID); 
	  $tmpPeerID = $dst if($peerID =~ m/^self(.*)/);
	  $tmpPeerID = $tmpPeerID.sprintf("%02X",$1) if($tmpPeerID eq $dst);
	  return "cannot identify peer:".$peerID if(!$tmpPeerID);
	  $peerID = $tmpPeerID.((length($peerID) == 6)?"01":"");
	} 
	else {
	  $peerID = "00000000";# Peerlist only for List3
	}

	my $peerChn = substr($peerID,6,2);# have to split chan and id
	$peerID = substr($peerID,0,6);

	if($cmd eq "getRegRaw"){
	  if ($list eq "00"){
	    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s00040000000000",
		                        $id,$dst));
	  }
	  else{# for all channels assotiated
	    my $chnFound;
		foreach my $channel (keys %{$attr{$name}}){
		  next if ($channel !~ m/^channel_/);
	      $chnFound = 1;
	      my $chnHash = CUL_HM_name2hash($attr{$name}{$channel});
	      if ($chnHash){
	        my $chnNo = $chnHash->{DEF};
		    $chnNo = substr($chnNo,6,2);
			if ($list =~m /0[34]/){#getPeers to see if list3 is available 
			  CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s03", 
			                          $id,$dst,$chnNo));
		      $chnHash->{helper}{getCfgList3} = $peerID.$peerChn;#list3 regs 
			}
			else{
			  CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s04%s%s%s", 
	                                  $id,$dst,$chnNo,$peerID,$peerChn,$list));
			}
	      }
        }
		if (!$chnFound){
		  if ($list =~m /0[34]/){#getPeers to see if list3 is available 
		    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s03",$id,$dst,$chn));
		    $hash->{helper}{getCfgList3} = $peerID.$peerChn;#list3 regs
		  }
		  else{
		    CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s0400000000%s", 
	                                 $id,$dst,$chn,$list));
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

    if (!$culHmRegSupported{$st}{$regName} && !$culHmRegGeneral{$regName} ){
      my @arr = keys %culHmRegGeneral ;
	  push @arr, keys %{$culHmRegSupported{$st}} if($culHmRegSupported{$st});
	  return "supported register are ".join(" ",sort @arr);
	}
	   
    my $reg  = $culHmRegDefine{$regName};
	return $st." - ".$regName            # give some help
	       ." range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
		   .($reg->{l} == 3)?" peer required":""." : ".$reg->{t}."\n" 
		        if ($data eq "?");
	return "value:".$data." out of range for Reg \"".$regName."\""
	        if ($data < $reg->{min} ||$data > $reg->{max});

	no strict; # convert data to register value
	my $d = $data;
	eval $reg->{c} if ($reg->{c});	
	$data = $d; # conversion as specified
	use strict;
	
	my $addr = int($reg->{a});        # bit location later
	my $list = $reg->{l};
	my $bit  = ($reg->{a}*10)%10; # get fraction
	
	my $dLen = $reg->{s};             # datalength in bit
	$dLen = int($dLen)*8+(($dLen*10)%10);
	# only allow it level if length less then one byte!!
	return "partial Word error: ".$dLen if($dLen != 8*int($dLen/8) && $dLen>7);
	
	my $mask = (0xffffffff>>(32-$dLen));
	my $dataStr = substr(sprintf("%08X",($data & $mask) << $bit),
	                                       8-int($reg->{s}+0.99)*2,);
    my $addrData;
	for (my $cnt = 0;$cnt<int($reg->{s}+0.99);$cnt++){
	  $addrData.=sprintf("%02X",$addr+$cnt).substr($dataStr,$cnt*2,2);
	}
    my ($lChn,$peerID,$peerChn) = ($chn,"000000","00");
	
	if (($list == 3) ||($list == 4)){ # peer is necessary for list 3/4
	  return "Peer not specified" if (!$peerChnIn);
	  $peerID = ($peerChnIn =~ m/^self(.*)/)?$dst:CUL_HM_Name2Id($peerChnIn);
	  $peerChn = ($1)?sprintf("%02X",$1):"";
 	  $peerChn = ((length($peerID) == 8)?substr($peerID,6,2):"01") if (!$peerChn);
      $peerID = substr($peerID,0,6);	
      return "Peer not specified" if (!$peerID);	  
	}
	elsif($list == 0){
      $lChn = "00";
	}
	else{  #if($list == 1/5/6){
      $lChn = "01" if ($chn eq "00"); #by default select chan 01 for device
	}
	if ($dLen < 8){# fractional byte see whether we have stored the register
	  #read full 8 bit!!!
	  my $curVal = CUL_HM_getRegFromStore(CUL_HM_id2Name($dst.$lChn),
	                                      $addr,$list,$peerID.$peerChn);
	  return "cannot read current value for Bitfield - retrieve Data first" 
	             if (!$curVal);
	  $data = ($curVal & (~($mask<<$bit)))||hex($data);
	}
    CUL_HM_pushConfig($hash,$id,$dst,$lChn,$peerID,$peerChn,$list,$addrData);
  } 
  elsif($cmd eq "on") { ###############################################
  	my $headerbytes = $md eq "HM-LC-SW1-BA-PCB" ? "FF" : "A0"; # Needs Burst Headerbyte See CC1100 FM transceiver
    CUL_HM_PushCmdStack($hash,
        sprintf("++%s11%s%s02%sC80000", $headerbytes, $id,$dst, $chn));

  } 
  elsif($cmd eq "off") { ##############################################
 	my $headerbytes = $md eq "HM-LC-SW1-BA-PCB" ? "FF" : "A0"; # Needs Burst Headerbyte See CC1100 FM transceiver
    CUL_HM_PushCmdStack($hash,
        sprintf("++%s11%s%s02%s000000", $headerbytes, $id,$dst,$chn));

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
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s02%sC80000%s",$id,$dst,$chn,$tval));
  } 
  elsif($cmd eq "toggle") { ###################################################
    $hash->{toggleIndex} = 1 if(!$hash->{toggleIndex});
    $hash->{toggleIndex} = (($hash->{toggleIndex}+1) % 128);
    CUL_HM_PushCmdStack($hash, sprintf("++A03E%s%s%s40%s%02X", $id, $dst,
                                      $dst, $chn, $hash->{toggleIndex}));

  } 
  elsif($cmd eq "pct") { ######################################################
    $a[1] = 100 if ($a[1] > 100);
    $tval = CUL_HM_encodeTime16((@a > 2)?$a[2]:85825945);# onTime   0.0..85825945.6, 0=forever
    $rval = CUL_HM_encodeTime16((@a > 3)?$a[3]:2.5);# rampTime 0.0..85825945.6, 0=immediate
    CUL_HM_PushCmdStack($hash, 
	    sprintf("++A011%s%s02%s%02X%s%s",$id,$dst,$chn,$a[1]*2,$rval,$tval));

  } 
  elsif($cmd eq "stop") { #####################################
    my $headerbytes = $md eq "HM-LC-SW1-BA-PCB" ? "FF" : "A0";
    CUL_HM_PushCmdStack($hash,
        sprintf("++%s11%s%s03%s", $headerbytes, $id,$dst, $chn));

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

    CUL_HM_PushCmdStack($hash,
        sprintf("++B011%s%s8012%s%04X%02X",$id,$dst,$text,$symbAdd,$beepBack));
  } 
  elsif($cmd eq "alarm"||$cmd eq "service") { #################################
	return "$a[2] must be below 255"  if ($a[2] >255 );
	$chn = 18 if ($chn eq "01");
	my $subtype = ($cmd eq "alarm")?"81":"82";
    CUL_HM_PushCmdStack($hash,
          sprintf("++B011%s%s%s%s%02X", $id,$dst,$subtype,$chn, $a[2]));
  } 
  elsif($cmd eq "led") { ######################################################
	if ($md eq "HM-OU-LED16"){
	  my %color=(off=>0,red=>1,green=>2,orange=>3);
	  return "$a[2] unknown. use: ".join(" ",sort keys(%color))
	     if (!$color{$a[2]} && $a[2] ne "off" );
	  if (length($hash->{DEF}) == 6){# command called for a device, not a channel
	    my $col4all = sprintf("%02X",$color{$a[2]}*85);#Color for 4 LEDS
	    $col4all = $col4all.$col4all.$col4all.$col4all;#and now for 16
        CUL_HM_PushCmdStack($hash,sprintf("++A011%s%s8100%s",$id,$dst,$col4all));
	  }else{# operating on a channel
        CUL_HM_PushCmdStack($hash,
            sprintf("++A011%s%s80%s0%s", $id,$dst,$chn, $color{$a[2]}));
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
      CUL_HM_PushCmdStack($hash,
            sprintf("++A011%s%s80%s0101%s", $id,$dst,$chn, $ledBytes));
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
    CUL_HM_PushCmdStack($hash,
          sprintf("++A011%s%s80%s0202%s", $id,$dst,$chn,$mp3Bytes));
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
                displayMode     =>{"temp-hum"=>1,"temp-only"=>1},
                displayTempUnit =>{celsius=>1,fahrenheit=>4},
                controlMode     =>{manual=>0,auto=>8,central=>16,party=>24},
  			    decalcDay       =>{"Sat"=>0  ,"Sun"=>32 ,"Mon"=>64,"Tue"=>96, 
				                   "Wed"=>128,"Thu"=>160,"Fri"=>192});
	return $a[2]."invalid for ".$cmd." select one of ". 
	               join (" ",sort keys %{$regs{$cmd}}) if(!$regs{$cmd}{$a[2]});
    $hash->{READINGS}{$cmd}{TIME} = TimeNow(); # update new value
    $hash->{READINGS}{$cmd}{VAL} = $a[2];
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
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
    CUL_HM_PushCmdStack($hash,
                sprintf("++A011%s%s0202%s", $id,$dst,$temp));

  } 
  elsif($cmd =~ m/^(day|night|party)-temp$/) { ##################
    my %tt = (day=>"03", night=>"04", party=>"06");
    my $tt = $tt{$1};
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
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
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
    CUL_HM_pushConfig($hash, $id, $dst, 2,0,0,$list, $data);

    my $vn = "tempList$wd";
    $hash->{READINGS}{$vn}{TIME} = TimeNow();
    $hash->{READINGS}{$vn}{VAL} = $msg;

  } 
  elsif($cmd eq "matic") { ##################################### 
    # Trigger pre-programmed action in the winmatic. These actions must be
    # programmed via the original software.

    CUL_HM_PushCmdStack($hash,
        sprintf("++B03E%s%s%s40%02X%s", $id, $dst, $id, $a[2], $chn));

  } elsif($cmd eq "create") { ###################################
    CUL_HM_PushCmdStack($hash, 
        sprintf("++B001%s%s0101%s%02X%s", $id, $dst, $id, $a[2], $chn));
    CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s0104%s%02X%s", $id, $dst, $id, $a[2], $chn));

  } elsif($cmd eq "read") { ###################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++B001%s%s0104%s%02X03", $id, $dst, $id, $a[2]));

  } elsif($cmd eq "keydef") { #####################################

    my $cmd;
    if ($a[3] eq "tilt") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],"0B220D838B228D83");

    } elsif ($a[3] eq "close") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0B550D838B558D83");

    } elsif ($a[3] eq "closed") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0F008F00");

    } elsif ($a[3] eq "bolt") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0FFF8FFF");

    } elsif ($a[3] eq "delete") {
      $cmd = sprintf("++B001%s%s0102%s%02X%s", $id, $dst, $id, $a[2], $chn);

    } elsif ($a[3] eq "speedclose") {
      $cmd = $a[4]*2;
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],
                                sprintf("23%02XA3%02X", $cmd, $cmd));

    } elsif ($a[3] eq "speedtilt") {
      $cmd = $a[4]*2;
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],
                                sprintf("22%02XA2%02X", $cmd, $cmd));
    } else {
      return "unknown argument $a[3]";

    }
    CUL_HM_PushCmdStack($hash, $cmd) if($cmd);

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
    my (undef,undef,$maxBtnNo) = @a;
	return "please give a number between 1 and 255"
	   if ($maxBtnNo < 1 ||$maxBtnNo > 255);# arbitrary - 255 should be max
    return $name." already defines as ".$attr{$name}{subType}
	   if ($attr{$name}{subType} && $attr{$name}{subType} ne "virtual");
    $attr{$name}{subType} = "virtual";
    $attr{$name}{hmClass} = "sender";
    $attr{$name}{model}   = "virtual_".$maxBtnNo;
    my $devId = $hash->{DEF};
    for (my $btn=1;$btn < $maxBtnNo;$btn++){
	  my $chnName = $name."_Btn".$btn;
	  my $chnId = $devId.sprintf("%02X",$btn);
	  DoTrigger("global",  "UNDEFINED $chnName CUL_HM $chnId")
		  if (!$modules{CUL_HM}{defptr}{$chnId});
	}
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
	foreach my $peer (sort(split(',',$attr{$name}{peerList}))) {
	  $peer =~ s/ .*//;
	  push (@peerList,substr(CUL_HM_Name2Id($peer),0,6));
	}
	my $oldPeer; # only once to device, not channel!
	foreach my $peer (sort @peerList){
	  next if ($oldPeer eq $peer);
      CUL_HM_SendCmd($hash, sprintf("++8440%s%s%s%s%02X",
	                    $srcId,$peer,$srcChn,$btn,$pressCnt),1,0);
	  $oldPeer = $peer;
	}
	$hash->{helper}{count}=$pressCnt;
  } 
  elsif($cmd eq "devicepair") { ###############################################
    #devicepair => "<btnNumber> device ... [single|dual] [set|unset] [actor|remote|both]"
	my ($bNo,$dev,$single,$set,$target) = ($a[2],$a[3],$a[4],$a[5],$a[6]);
	return "$bNo is not a button number" if(($bNo < 1) && !$chn);
    my $peerHash = $defs{$dev} if ($dev);
    return "$dev not a CUL_HM device" 
	      if(!$peerHash ||$peerHash->{TYPE} ne "CUL_HM");
    return "$single must be single or dual" 
	      if(defined($single) && (($single ne"single") &&($single ne"dual")));  
    return "$set must be set or unset" 
	      if(defined($set) && (($set ne"set") &&($set ne"unset")));  
    return "$target must be [actor|remote|both]" 
	      if(defined($target) && (($target ne"actor") &&
		     ($target ne"remote")&&($target ne"both")));  
	$single = ($single eq "single")?1:"";#default to dual
	$set = ($set eq "set")?1:"";

	my ($b1,$b2,$nrCh2Pair);
	$b1 = $chn ? hex($chn):sprintf("%02X",$bNo);
	$b1 = $b1*2 - 1 if($single && !$chn);
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
		
		my $devhash = CUL_HM_getDeviceHash($hash);
		my $devName = $devhash->{NAME};
		
  	    if ($attr{$devName}{subType} eq "virtual"){
		  my $btnName = CUL_HM_id2Name($dst.sprintf("%02X",$b));
		  return "button ".$b." not defined for virtual remote ".$name
		      if (!defined $attr{$btnName});
		  my $peerlist = $attr{$btnName}{peerList};
		  $peerlist = "" if (!$peerlist);
		  my $repl = CUL_HM_id2Name($peerDst.$peerChn).",";
  	      $peerlist =~ s/$repl//;#avoid duplicate
  	      $peerlist.= $repl if($set == 1);
		  $attr{$btnName}{peerList} = $peerlist;
	    }
		else{
		  my $bStr = sprintf("%02X",$b);
  	      CUL_HM_PushCmdStack($hash, 
  	               "++A001${id}${dst}${bStr}$cmd${peerDst}${peerChn}00");
  	      CUL_HM_pushConfig($hash,$id, $dst,$b,
  	               $peerDst,hex($peerChn),4,"0100");
	    }
      }
	}
	if (!$target || $target eq "actor" || $target eq "both"){
      CUL_HM_PushCmdStack($peerHash, sprintf("++A001%s%s%s%s%s%02X%02X",
	                              $id,$peerDst,$peerChn,$cmd,$dst,$b2,$b1 ));
	}
    $chash = $peerHash; # Exchange the hash, as the switch is always alive.
  }

  $hash->{STATE} = $state if($state); #todo: this is not the device state
  Log GetLogLevel($name,2), "CUL_HM set $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($chash) 
     if(!$attr{$chash->{NAME}}{rxType}||
	     $attr{$chash->{NAME}}{rxType}=~ m/burst/);
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
  
  delete $attr{$name}{rxType};
  if ($culHmModel{$mId}{rxt}){
	foreach my $rxt (split(':',$culHmModel{$mId}{rxt})){
	  $attr{$name}{rxType} .= "config," if ($rxt eq "c");
	  $attr{$name}{rxType} .= "wakeup," if ($rxt eq "w");
	  $attr{$name}{rxType} .= "burst,"  if ($rxt eq "b");
	}
  }
  #set rxType
  
  # autocreate undefined channels  
  my @chanTypesList = split(',',$culHmModel{$mId}{chn});
  foreach my $chantype (@chanTypesList){
    my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
	my $chnNoTyp = 1;
	for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
	  my $chnName = $name.$chnTpName.(($chnStart == $chnEnd)?"":"_".$chnNoTyp);
	  my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
	  if (!$modules{CUL_HM}{defptr}{$chnId}){
	    DoTrigger("global",  "UNDEFINED $chnName CUL_HM $chnId");
      }
	  $chnNoTyp++;
	}
  }

}
###################################
sub
CUL_HM_Pair(@)
{
  my ($name, $hash,$cmd,$src,$dst,$p) = @_;
  my $iohash = $hash->{IODev};
  my $id = CUL_HM_Id($iohash);
  my $l4 = GetLogLevel($name,4);
  my $serNo = $attr{$name}{serialNr};

  Log GetLogLevel($name,2),
      "CUL_HM pair: $name $attr{$name}{subType}, model $attr{$name}{model} serialNr $serNo";

  # Abort if we are not authorized
  if($dst eq "000000") {
    if(!$iohash->{hmPair} &&
       (!$iohash->{hmPairSerial} || $iohash->{hmPairSerial} ne $serNo)) {
      Log GetLogLevel($name,2),
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
  #getList1
  CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s040000000001",$id,$dst,$chn));
  
  #getPeers and config what List3 shall be retrieved
  CUL_HM_PushCmdStack($hash,sprintf("++A001%s%s%s03", $id,$dst,$chn));	       
  $chnhash->{helper}{getCfgList3} = "all";#get list3 regs of first peer in list
 }
###################################
sub
CUL_HM_SendCmd($$$$)
{
  my ($hash, $cmd, $sleep, $waitforack) = @_;
  my $io = $hash->{IODev};

  select(undef, undef, undef, 0.1*$sleep) if($sleep);

  $cmd =~ m/^(..)(.*)$/;
  my ($mn, $cmd2) = ($1, $2);

  if($mn eq "++") {
    $mn = $io->{HM_CMDNR} ? ($io->{HM_CMDNR} +1) : 1;
    $mn = 0 if($mn > 255);

  } else {
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
    
  if ($msgType eq "01" && $subType){ 
    if ($subType eq "03"){ #PeerList-------------
  	  #--- remember request params in device level
  	  $hash->{helper}{respWait}{Pending} = "PeerList";
  	  $hash->{helper}{respWait}{forChn} = substr($p,0,2);#channel info we await
      
      # define timeout - holdup cmdStack until response complete or timeout
  	  InternalTimer(gettimeofday()+3, "CUL_HM_respPendTout", "respPend:$dst", 0);
  		  
  	  #--- remove readings in channel
  	  my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"}; 
  	  $chnhash = $hash if (!$chnhash);
  	  $chnhash->{READINGS}{peerList}{VAL}="";#empty old list
	  return;
    }
    elsif($subType eq "04"){ #RegisterRead-------
      my ($peerID, $list) = ($1,$2) if ($p =~ m/..04(........)(..)/);
	  $peerID = CUL_HM_id2Name($peerID);
	  $peerID =~ s/ /_/g;#remote blanks
	  #--- set messaging items
	  $hash->{helper}{respWait}{Pending} = "RegisterRead";
	  $hash->{helper}{respWait}{forChn} = $chn;
	  $hash->{helper}{respWait}{forList}= $list;
	  $hash->{helper}{respWait}{forPeer}= $peerID;# this is the HMid + channel
      
      # define timeout - holdup cmdStack until response complete or timeout
	  InternalTimer(gettimeofday()+3,"CUL_HM_respPendTout","respPend:$dst", 0);
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
	  InternalTimer(gettimeofday()+3, "CUL_HM_respPendTout", "respPend:$dst", 0);
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
CUL_HM_convPendTout($)
{
  my ($HMid) =  @_;  
  $HMid =~ s/.*://; #remove timer identifier
  my $hash = $modules{CUL_HM}{defptr}{$HMid};

  if ($hash){
	delete ($hash->{helper}{respWait}{RegWrite});
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
  }
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
{
  my $hash = shift;
  my $name = $hash->{NAME};
  return if(!$hash->{helper}{respWait}{reSent});      # Double timer?
  if($hash->{helper}{respWait}{reSent} >= 3) {
  	CUL_HM_eventP($hash,"ResndFail");
    CUL_HM_respPendRm($hash);
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
    DoTrigger($name, "resend nr ".$hash->{helper}{respWait}{reSent});
    InternalTimer(gettimeofday()+0.5, "CUL_HM_Resend", $hash, 0);
  }
}

###################################
sub
CUL_HM_Id($)
{
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME}, "hmId", "F1$fhtid");
}

###################################
sub
CUL_HM_name2hash($)
{
  my ($name) = @_;
  return $defs{$name};
}

###################################
sub
CUL_HM_Name2Id($)
{ # get name for a hmId or a hmId channel combination

  my ($idName) = @_;
  my $hash = $defs{$idName};
  my $hmId;
  $hmId = $hash->{DEF} if ($hash);
  $hmId =$idName if(!$hmId &&($idName =~ m/^[A-F0-9]{6,8}$/i));
  return $hmId;
}
###################################
sub
CUL_HM_id2Name($)
{ # get name for a HMid or a HMid channel combination
  my ($p) = @_;
  my $devId= substr($p, 0, 6);
  my $chn;
  my $chnId;
  return $p if($attr{$p}); # is already name
  if (length($p) == 8){
	$chn = substr($p, 6, 2);;
	$chnId = $p;
  }
  return "broadcast" if($devId eq "000000"); 
  my $name;
  my $defPtr = $modules{CUL_HM}{defptr};
  $name = $defPtr->{$chnId}{NAME} if($chnId && $defPtr->{$chnId});
  if (!$name){
    $name = $defPtr->{$devId}{NAME} if($defPtr->{$devId});
    $name = $devId if(!$name);
    $name .= ($chn ? (" chn:".$chn):"");
  }
  return $name;
}
###################################
sub
CUL_HM_getDeviceHash($){
  my ($hash) = @_;
  my $HMid = substr($hash->{DEF},0,6) if ($hash->{DEF});
  return $hash if(!$hash->{DEF});
  my $devHash = $modules{CUL_HM}{defptr}{$HMid};
  $devHash = $modules{CUL_HM}{defptr}{$HMid."01"} if (!$devHash);
  $devHash = $hash if (!$devHash);
  return $devHash;
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
  "01;p11=0A" =>   { txt => "PAIR_SERIAL", params => {
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
  my $ev = AttrVal($iname, "hmProtocolEvents", 0);
  my $l4 = GetLogLevel($iname, 4);
  return if(!$ev && $attr{global}{verbose} < $l4);

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
  $ps = $culHmBits{"$msgType"}         if(!$ps);
  my $txt = "";
  if($ps) {
    $txt = $ps->{txt};
    if($ps->{params}) {
      $ps = $ps->{params};
      foreach my $k (sort {$ps->{$a} cmp $ps->{$b} } keys %{$ps}) {
        my ($o,$l,$expr) = split(",", $ps->{$k}, 3);
        last if(length($p) <= $o);
        my $val = $l ? substr($p,$o,$l) : substr($p,$o);
        eval $expr if($expr);
        $txt .= " $k:$val";
      }
    }
    $txt = " ($txt)" if($txt);
  }
  $src=CUL_HM_id2Name($src);
  $dst=CUL_HM_id2Name($dst);
  my $msg ="$prefix L:$len N:$cnt F:$msgFlags CMD:$msgType SRC:$src DST:$dst $p$txt ($msgFlLong)";
  Log $l4, $msg;
  DoTrigger($iname, $msg) if($ev);

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
    $chnhash->{READINGS}{CommandAccepted}{TIME} = TimeNow();
    $chnhash->{READINGS}{CommandAccepted}{VAL} = $success;
    CUL_HM_ProcessCmdStack($shash); # see if there is something left
	return $reply;
  }
  elsif($msgType eq "10" && $p =~ m/^01/){ #storePeerList#################
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
 	  $chnhash->{READINGS}{peerList}{VAL}.= ",".$peerFound;
 	  $chnhash->{READINGS}{peerList}{TIME} = TimeNow();
 	  
 	  $peerFound = join (',',@peerID);
 	  $peerFound =~ s/00000000//;
 	  $chnhash->{helper}{peerList}.= ",".$peerFound;
 	  
 	  if ($p =~ m/00000000$/) {# last entry, peerList is complete
 	    CUL_HM_respPendRm($shash);
 		# check for request to get List3 data
 		my $reqPeer = $chnhash->{helper}{getCfgList3};
 	    if ($reqPeer){
 	      my $id = CUL_HM_Id($shash->{IODev});
 		  @peerID = split(",", $chnhash->{helper}{peerList});
 		  my $class = AttrVal(CUL_HM_id2Name($src), "hmClass", "");
          my $listNo = ($class eq "sender")?"04":"03";#list4 for sender
  	      $reqPeer = $peerID[$reqPeer] if ($reqPeer < 100 && $reqPeer > 0 );
 		  foreach my $peer (@peerID){
 			$peer .="01" if (length($peer) == 6); # add the default
 			if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
 			  CUL_HM_PushCmdStack($shash,sprintf("++A001%s%s%s04%s%s",$id,
 			              $src,$chn,$peer,$listNo));# List3 or 4 
 			}
 		  }
 		  CUL_HM_ProcessCmdStack($shash) if($listNo ne "04");
 	    }
 		delete $chnhash->{helper}{getCfgList3};
 		delete $chnhash->{helper}{peerList};
 	  }
 	  return "done";
 	}
  }
  elsif($msgType eq "10" && $p =~ m/^0[23]/){ #ParamResp##################
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
        $data =~s/(..)/$1:/g;
        foreach my $d1 (split(":",$data)){
          push (@dataList,sprintf("%02X:%s",$addr++,$d1));
        }
        $data = join(" ",@dataList);		
 	  }
	  my $peerN  =($list =~ m/^0[34]$/)?$shash->{helper}{respWait}{forPeer}:"";
      $chnhash->{READINGS}{"RegL_".$list.":".$peerN}{VAL}.= " ".$data if($data);
      $chnhash->{READINGS}{"RegL_".$list.":".$peerN}{TIME}= TimeNow();

 	  if ($data =~m/00:00$/){ # this was the last message in the block
	    if($list eq "00"){
		  my $name = CUL_HM_id2Name($src);
		  $shash->{READINGS}{PairedTo}{VAL} = sprintf("%02X%02X%02X",
		                        CUL_HM_getRegFromStore($name,10,0,"00000000"),
		                        CUL_HM_getRegFromStore($name,11,0,"00000000"),
		                        CUL_HM_getRegFromStore($name,12,0,"00000000"));
		  $shash->{READINGS}{PairedTo}{TIME} = TimeNow();
		}
        CUL_HM_respPendRm($shash);
	  }
	  return "done";
    }
  }  
  elsif($msgType eq "10" && $p =~ m/^04/){ #ParamChange###################
    my($chn,$peerID,$list,$data) = @_ if($p =~ m/^04(..)(........)(..)(.*)/);
    my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	$chnHash = $shash if(!$chnHash); # will add param to dev if no chan
	my $listName = "RegL_".$list.":".CUL_HM_id2Name($peerID);
	$listName =~ s/ /_/g; #remove blanks
    $chnHash->{READINGS}{$listName}{VAL} = "" 
	        if ($chnHash->{READINGS}{$listName}{VAL} =~m/00:00$/);
	$data =~ s/(..)(..)/ $1:$2/g;
    $chnHash->{READINGS}{$listName}{VAL}.= " ".$data;
    $chnHash->{READINGS}{$listName}{TIME}= TimeNow();
   }  
  elsif($msgType eq "10" && $p =~ m/^06/){ #reply to status request#######
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
  elsif($msgType eq "70"){ #wakeup #######################################
	CUL_HM_ProcessCmdStack($shash) 
	       if ($attr{$shash->{NAME}}{rxType} =~ m/wakeup/);
  }
  return "";
}

#############################
sub
CUL_HM_getRegFromStore($$$$){
  my($name,$addr,$list,$peerId)=@_;
  my $hash = CUL_HM_name2hash($name);
  my ($size,$pos,$conv,$unit) = (8,0,"",""); # default 8bit, pos=0, no convertion

  if ($culHmRegDefine{$addr}) {
    my $regName = $addr;
    $addr = $culHmRegDefine{$regName}{a};
	$pos = ($addr*10)%10;
	$addr = int($addr);
    $list = $culHmRegDefine{$regName}{l};
	$size = $culHmRegDefine{$regName}{s};
	$size = int($size)*8 + ($size*10)%10;
	$conv = $culHmRegDefine{$regName}{uc}; #unconvert formula
	$unit = $culHmRegDefine{$regName}{u};
  }
  $peerId = substr(CUL_HM_Name2Id($name),0,6).                 #deviceID
            sprintf("%02X",$1) if($peerId =~ m/^self(.*)/);    # plus channel

  my $listName = "RegL_".sprintf("%02X",$list).":".
                 (($list<3)?"":CUL_HM_id2Name($peerId)); 
  $listName =~ s/ /_/g;
  my $listRegs = $hash->{READINGS}{$listName}{VAL} if ($listName);
  return "unknown" if (!$listRegs);
  my $d = 0;
  my $size2go = $size;
  foreach my $AD(split(" ",$listRegs)){
    my ($a,$dRead) = split(":",$AD);
	if(hex($a) == $addr){
	  if ($size2go<9){
	    $d += hex($dRead);
		$d = ($d>>$pos) & (0xffffffff>>(32-$size));
		eval $conv;	
		return $d.$unit;
      }
	  else{
	    $size2go -=8;
		$d = ($d+hex($dRead))<<8;
		$addr++;
	  }
	}
  }
  return "invalid";
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
  Log 1, "Timeout $v rounded to $v2" if($v != $v2);
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
{
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content) = @_;

  $peerAddr = "000000" if(!$peerAddr);
  CUL_HM_PushCmdStack($hash, sprintf("++A001%s%s%02X05%s%02X%02X",
        $src, $dst, $chn, $peerAddr, $peerChn, $list));
  my $tl = length($content);
  for(my $l = 0; $l < $tl; $l+=28) {
    my $ml = $tl-$l < 28 ? $tl-$l : 28;
    CUL_HM_PushCmdStack($hash,
      sprintf("++A001%s%s%02X08%s", $src,$dst,$chn, substr($content,$l,$ml)));
  }
  CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s%02X06",$src,$dst,$chn));
}

sub
CUL_HM_maticFn($$$$$)
{
  my ($hash, $id, $dst, $a2, $cfg) = @_;
  my $sndcmd =  sprintf("++B001%s%s0105%s%02X03", $id, $dst, $id, $a2);
  CUL_HM_SendCmd ($hash, $sndcmd, 10, 2);
  $sndcmd =  sprintf("++A001%s%s0108%s", $id, $dst, $cfg);
  CUL_HM_SendCmd ($hash, $sndcmd, 10, 2);
  $sndcmd = sprintf("++A001%s%s0106", $id, $dst);
  return $sndcmd;
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


1;
