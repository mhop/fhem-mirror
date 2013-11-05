##############################################
##############################################
# CUL HomeMatic handler
# $Id$

package main;

# attribut conversion                                     "#todo Updt4 remove"
#        the lines can be removed after some soak time - around version 2600
use strict;
use warnings;
use HMConfig;

# ========================import constants=====================================
my %culHmModel            =HMConfig::HMConfig_getHash("culHmModel");
my %culHmRegDefShLg       =HMConfig::HMConfig_getHash("culHmRegDefShLg");
my %culHmRegDefine        =HMConfig::HMConfig_getHash("culHmRegDefine");
my %culHmRegGeneral       =HMConfig::HMConfig_getHash("culHmRegGeneral");
my %culHmRegType          =HMConfig::HMConfig_getHash("culHmRegType");
my %culHmRegModel         =HMConfig::HMConfig_getHash("culHmRegModel");
my %culHmRegChan          =HMConfig::HMConfig_getHash("culHmRegChan");
my %culHmGlobalGets       =HMConfig::HMConfig_getHash("culHmGlobalGets");
my %culHmSubTypeGets      =HMConfig::HMConfig_getHash("culHmSubTypeGets");
my %culHmModelGets        =HMConfig::HMConfig_getHash("culHmModelGets");
my %culHmGlobalSetsDevice =HMConfig::HMConfig_getHash("culHmGlobalSetsDevice");
my %culHmSubTypeDevSets   =HMConfig::HMConfig_getHash("culHmSubTypeDevSets");
my %culHmGlobalSetsChn    =HMConfig::HMConfig_getHash("culHmGlobalSetsChn");
my %culHmGlobalSets       =HMConfig::HMConfig_getHash("culHmGlobalSets");
my %culHmGlobalSetsVrtDev =HMConfig::HMConfig_getHash("culHmGlobalSetsVrtDev");
my %culHmSubTypeSets      =HMConfig::HMConfig_getHash("culHmSubTypeSets");
my %culHmModelSets        =HMConfig::HMConfig_getHash("culHmModelSets");
my %culHmChanSets         =HMConfig::HMConfig_getHash("culHmChanSets");
my %culHmBits             =HMConfig::HMConfig_getHash("culHmBits");
my @culHmCmdFlags         =HMConfig::HMConfig_getHash("culHmCmdFlags");
my $K_actDetID            =HMConfig::HMConfig_getHash("K_actDetID");

############################################################

sub CUL_HM_Initialize($);
sub CUL_HM_reqStatus($);
sub CUL_HM_autoReadConfig();
sub CUL_HM_updateConfig($);
sub CUL_HM_Define($$);
sub CUL_HM_Undef($$);
sub CUL_HM_Rename($$$);
sub CUL_HM_Attr(@);
sub CUL_HM_Parse($$);
sub CUL_HM_parseCommon(@);
sub CUL_HM_qAutoRead($$);
sub CUL_HM_Get($@);
sub CUL_HM_Set($@);
sub CUL_HM_valvePosUpdt(@);
sub CUL_HM_infoUpdtDevData($$$);
sub CUL_HM_infoUpdtChanData(@);
sub CUL_HM_getConfig($);
sub CUL_HM_SndCmd($$);
sub CUL_HM_responseSetup($$);
sub CUL_HM_eventP($$);
sub CUL_HM_protState($$);
sub CUL_HM_respPendRm($);
sub CUL_HM_respPendTout($);
sub CUL_HM_respPendToutProlong($);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_pushConfig($$$$$$$$@);
sub CUL_HM_ID2PeerList ($$$);
sub CUL_HM_peerChId($$$);
sub CUL_HM_peerChName($$$);
sub CUL_HM_getMId($);
sub CUL_HM_getRxType($);
sub CUL_HM_getFlag($);
sub CUL_HM_getAssChnIds($);
sub CUL_HM_Id($);
sub CUL_HM_IOid($);
sub CUL_HM_hash2Id($);
sub CUL_HM_hash2Name($);
sub CUL_HM_name2Hash($);
sub CUL_HM_name2Id(@);
sub CUL_HM_id2Name($);
sub CUL_HM_id2Hash($);
sub CUL_HM_getDeviceHash($);
sub CUL_HM_getDeviceName($);
sub CUL_HM_DumpProtocol($$@);
sub CUL_HM_getRegFromStore($$$$@);
sub CUL_HM_updtRegDisp($$$);
sub CUL_HM_encodeTime8($);
sub CUL_HM_decodeTime8($);
sub CUL_HM_encodeTime16($);
sub CUL_HM_convTemp($);
sub CUL_HM_decodeTime16($);
sub CUL_HM_secSince2000();
sub CUL_HM_getChnLvl($);
sub CUL_HM_initRegHash();
sub CUL_HM_fltCvT($);
sub CUL_HM_CvTflt($);
sub CUL_HM_4DisText($);
sub CUL_HM_TCtempReadings($);
sub CUL_HM_repReadings($);
sub CUL_HM_dimLog($);
sub CUL_HM_ActGetCreateHash();
sub CUL_HM_time2sec($);
sub CUL_HM_ActAdd($$);
sub CUL_HM_ActDel($);
sub CUL_HM_ActCheck();
sub CUL_HM_UpdtReadBulk(@);
sub CUL_HM_UpdtReadSingle(@);
sub CUL_HM_setAttrIfCh($$$$);
sub CUL_HM_noDup(@);        #return list with no duplicates
sub CUL_HM_noDupInString($);#return string with no duplicates, comma separated
sub CUL_HM_storeRssi(@);
sub CUL_HM_qStateUpdatIfEnab($@);
sub CUL_HM_getAttrInt($@);
sub CUL_HM_putHash($);
sub CUL_HM_appFromQ($$);

# ----------------modul globals-----------------------
my $respRemoved; # used to control trigger of stack processing
my $IOpoll     = 0.2;# poll speed to scan IO device out of order

my $maxPendCmds = 10;  #number of parallel requests

                 # need to take care that ACK is first
#+++++++++++++++++ startup, init, definition+++++++++++++++++++++++++++++++++++
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
                       "peerIDs repPeers ".
                       "actCycle actStatus ".
					   "autoReadReg:0_off,1_restart,2_pon-restart,3_onChange,4_reqStatus,8_stateOnly ".
					   "expert:0_off,1_on,2_full ".
					   "burstAccess:0_off,1_auto ".
                       "param msgRepeat ".
					   ".stc .devInfo ".
                       $readingFnAttributes;
  #autoReadReg:  
  #		        ,6_allForce
  #		        ,4_backUpdt
  
  my @modellist;
  foreach my $model (keys %culHmModel){
    push @modellist,$culHmModel{$model}{name};
  }
  $hash->{AttrList}  .= " model:"  .join(",", sort @modellist);
  $hash->{AttrList}  .= " subType:".join(",",
               CUL_HM_noDup(map { $culHmModel{$_}{st} } keys %culHmModel));

  $hash->{prot}{rspPend} = 0;#count Pending responses
  my @statQArr = ();
  my @statQWuArr = ();
  my @confQArr = ();
  my @confQWuArr = ();
  $hash->{helper}{qReqStat}   = \@statQArr;
  $hash->{helper}{qReqStatWu} = \@statQWuArr;
  $hash->{helper}{qReqConf}   = \@confQArr;
  $hash->{helper}{qReqConfWu} = \@confQWuArr;
  CUL_HM_initRegHash();
  $hash->{hmIoMaxDly}     = 60;# poll timeout - stop poll and discard
  $hash->{hmAutoReadScan} = 4; # delay autoConf readings
  $hash->{helper}{hmManualOper} = 0;# default automode
}

sub CUL_HM_updateConfig($){
  # this routine is called 5 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes
  # it will also be called after each manual definition
  # Purpose is to parse attributes and read config
  foreach my $name (@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    my $hash = $defs{$name};
	my $id = $hash->{DEF};
    my $chn = substr($id."00",6,2);
	
	if ($id ne $K_actDetID){# if not action detector
 	  CUL_HM_ID2PeerList($name,"",1);       # update peerList out of peerIDs
      my $actCycle = AttrVal($name,"actCycle",undef);
	  CUL_HM_ActAdd($id,$actCycle) if ($actCycle);# add to ActionDetect?
	  # --- set default attrubutes if missing ---
      if (   $hash->{helper}{role}{dev}
	      && AttrVal($name,"subType","") ne "virtual"){
	    $attr{$name}{expert}     = AttrVal($name,"expert"     ,"2_full");
	    $attr{$name}{autoReadReg}= AttrVal($name,"autoReadReg","4_reqStatus")
		    if(CUL_HM_getRxType($hash)&0xEB);
	  }
	  CUL_HM_Attr("attr",$name,"expert",$attr{$name}{expert});#need update after readings are available
	}
	else{# Action Detector only
	  $attr{$name}{"event-on-change-reading"} = AttrVal($name, "event-on-change-reading", ".*");
	  delete $hash->{helper}{role};
	  $hash->{helper}{role}{vrt} = 1;
	  next;
	  #delete $attr{$name}{peerIDs}; # remove historical data
	}

    my $st  = CUL_HM_Get($hash,$name,"param","subType");
    my $md  = CUL_HM_Get($hash,$name,"param","model");
    if ($md =~ /(HM-CC-TC)/){
	  $hash->{helper}{role}{chn} = 1 if (length($id) == 6); #tc special
	  $attr{$name}{stateFormat} = "last:trigLast" if ($chn eq "03");
	}
    elsif ($md =~ m/HM-CC-RT-DN/){
	  $attr{$name}{stateFormat} = "last:trigLast" if ($chn eq "03");
	}
	elsif ("dimmer"  eq $st) {#setup virtual dimmer channels
	  my $mId = CUL_HM_getMId($hash);
	  #configure Dimmer virtual channel assotiation
	  if ($hash->{helper}{role}{chn}){
	    my $chn = (length($id) == 8)?substr($id,6,2):"01";
	    my $devId = substr($id,0,6);
		if ($culHmModel{$mId} && $culHmModel{$mId}{chn} =~ m/Sw._V/){#virtual?
		  my @chnPh = (grep{$_ =~ m/Sw:/ } split ',',$culHmModel{$mId}{chn});
		  @chnPh = split ':',$chnPh[0] if (@chnPh);
		  my $chnPhyMax = $chnPh[2]?$chnPh[2]:1;         # max Phys channels
		  my $chnPhy    = int(($chn-$chnPhyMax+1)/2);    # assotiated phy chan
		  my $idPhy     = $devId.sprintf("%02X",$chnPhy);# ID assot phy chan
		  my $pHash     = CUL_HM_id2Hash($idPhy);        # hash assot phy chan
		  $idPhy        = $pHash->{DEF};                 # could be device!!!
		  if ($pHash){
		    $pHash->{helper}{vDim}{idPhy} = $idPhy;
		    my $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy-1));
		    if ($vHash){
		      $pHash->{helper}{vDim}{idV2}  = $vHash->{DEF};
		      $vHash->{helper}{vDim}{idPhy} = $idPhy;
		    }
		    else{
		      delete $pHash->{helper}{vDim}{idV2};
		    }
		    $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy));
		    if ($vHash){
		      $pHash->{helper}{vDim}{idV3}  = $vHash->{DEF};
		      $vHash->{helper}{vDim}{idPhy} = $idPhy;
		    }
		    else{
		      delete $pHash->{helper}{vDim}{idV3};
		    }
		  }
		}
	  }
	}
	elsif ("virtual" eq $st) {#setup virtuals
	  $hash->{helper}{role}{vrt} = 1;
	}

    if ( $hash->{helper}{role}{dev} && CUL_HM_getRxType($hash)&0x02){#burst dev
	  #burst devices must restrict retries!
	  $attr{$name}{msgRepeat} = 1 if (!$attr{$name}{msgRepeat});
	}
	# -+-+-+-+-+ add default web-commands
    my $webCmd;
    $webCmd  = AttrVal($name,"webCmd",undef);
    if(!defined $webCmd){
      if    ($st eq "virtual"      ){$webCmd="press short:press long";
	  }elsif((!$hash->{helper}{role}{chn} &&
			   $md ne "HM-CC-TC")
		    ||$st eq "repeater"
			||$md eq "HM-CC-VD"	   ){$webCmd="getConfig";
	  }elsif($st eq "blindActuator"){$webCmd="toggle:on:off:up:down:stop:statusRequest";
	  }elsif($st eq "dimmer"       ){$webCmd="toggle:on:off:up:down:statusRequest";
	  }elsif($st eq "switch"       ){$webCmd="toggle:on:off:statusRequest";
	  }elsif($st eq "smokeDetector"){$webCmd="test:alarmOn:alarmOff";
	  }elsif($st eq "keyMatic"     ){$webCmd="lock:inhibit on:inhibit off";
	  }elsif($md eq "HM-OU-CFM-PL" ){$webCmd="press short:press long"
	                                   .($chn eq "02"?":playTone replay":"");
	  }
	  if    (!$hash->{helper}{role}{chn} 
	       && $md =~ m/HM-CC-RT-DN/) {$webCmd.=":burstXmit";}
		   
	  if ($webCmd){
	    my $eventMap  = AttrVal($name,"eventMap",undef);
	  
	    my @wc;
	    push @wc,ReplaceEventMap($name, $_, 1) foreach (split ":",$webCmd);
	    $webCmd = join ":",@wc;
	  }
	}
	$attr{$name}{webCmd} = $webCmd if ($webCmd);

	CUL_HM_qStateUpdatIfEnab($name);
    next if (0 == (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
	if(!CUL_HM_peersValid($name)){
	  CUL_HM_qAutoRead($name,1);
	}
	else{
	  foreach(CUL_HM_reglUsed($name)){
	    next if (!$_);
	    if(ReadingsVal($name,$_,"x") !~ m/00:00/){
	      CUL_HM_qAutoRead($name,1);
		  last;
	    }
	  }
	}
  }
  delete $modules{CUL_HM}{helper}{updtCfgLst};
}
sub CUL_HM_Define($$) {##############################
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
    $hash->{helper}{role}{chn}=1;
	if($chn eq "01"){
	  $attr{$name}{peerIDs} = AttrVal($devName, "peerIDs", "");
	  $hash->{READINGS}{peerList}{VAL} = ReadingsVal($devName,"peerList","");
	  $hash->{peerList} = $devHash->{peerList} if($devHash->{peerList});
	  
	  delete $devHash->{helper}{role}{chn};#device no longer
	  delete $devHash->{peerList};
	  delete $devHash->{READINGS}{peerList};
	}
  }
  else{# define a device
    $hash->{helper}{role}{dev}=1;
    $hash->{helper}{role}{chn}=1;# take role of chn 01 until it is defined
    $hash->{helper}{q}{qReqConf}=""; # queue autoConfig requests for this device
    $hash->{helper}{q}{qReqStat}=""; # queue autoConfig requests for this device
	CUL_HM_prtInit ($hash);
    AssignIoPort($hash);
  }
  $modules{CUL_HM}{defptr}{$HMid} = $hash;
  
  #- - - - create auto-update - - - - - -
  CUL_HM_ActGetCreateHash() if($HMid eq '000000');#startTimer
  $hash->{DEF} = $HMid;
  CUL_HM_Parse($hash, $a[3]) if(int(@a) == 4);
  
  CUL_HM_queueUpdtCfg($name);
  return undef;
}
sub CUL_HM_Undef($$) {###############################
  my ($hash, $name) = @_;
  my $devName = $hash->{device};
  my $HMid = $hash->{DEF};
  my $chn = substr($HMid,6,2);
  if ($chn){# delete a channel
	my $devHash = $defs{$devName};
    delete $devHash->{"channel_$chn"} if ($devName);
    $devHash->{helper}{role}{chn}=1 if($chn eq "01");# return chan 01 role
  }
  else{# delete a device
 	CommandDelete(undef,$hash->{$_}) foreach (grep(/^channel_/,keys %{$hash}));
  }
  delete($modules{CUL_HM}{defptr}{$HMid});
  return undef;
}
sub CUL_HM_Rename($$$) {#############################
  my ($name, $oldName) = @_;
  my $HMid = CUL_HM_name2Id($name);
  my $hash = $defs{$name};
  if (length($HMid) == 8){# we are channel, inform the device
    $hash->{chanNo} = substr($HMid,6,2);
	my $devHash = CUL_HM_id2Hash(substr($HMid,0,6));
    $hash->{device} = $devHash->{NAME};
	$devHash->{"channel_".$hash->{chanNo}} = $name;
  }
  else{# we are a device - inform channels if exist
    foreach (grep (/^channel_/, keys%{$hash})){
	  my $chnHash = $defs{$hash->{$_}};
	  $chnHash->{device} = $name;
	}
  }
  return;
}
sub CUL_HM_Attr(@) {#################################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  my @hashL;
  my $updtReq = 0;
  my $hash = CUL_HM_name2Hash($name);
  if   ($attrName eq "expert"){#[0,1,2]
    $attr{$name}{expert} = $attrVal;
	my $eHash = $defs{$name};
    foreach my $chId (CUL_HM_getAssChnIds($name)){ 
	  my $cHash = CUL_HM_id2Hash($chId);
	  push(@hashL,$cHash) if ($eHash ne $cHash);
	}
    push(@hashL,$eHash);
    foreach my $hash (@hashL){
	  my $exLvl = CUL_HM_getAttrInt($hash->{NAME},"expert");
	  if    ($exLvl eq "0"){# off
        foreach my $rdEntry (grep /^RegL_/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
        foreach my $rdEntry (grep /^R-/   ,keys %{$hash->{READINGS}}){
 		  my $reg = $rdEntry;
	  	  $reg =~ s/.*-//;
          next if(!$culHmRegDefine{$reg} || $culHmRegDefine{$reg}{d} eq '1');
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  elsif ($exLvl eq "1"){# on: Only register values, no raw data
	    # move register to visible if available
        foreach my $rdEntry (grep /^RegL_/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
        foreach my $rdEntry (grep /^\.R-/ ,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{substr($rdEntry,1)} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  elsif ($exLvl eq "2"){# full - incl raw data
        foreach my $rdEntry (grep /^\.R(egL_|-)/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{substr($rdEntry,1)} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
	    }
	  }
	  else{;
	  }
    }
  }
  elsif($attrName eq "actCycle"){#"000:00" or 'off'
    return if (CUL_HM_name2Id($name) eq $K_actDetID);
	return "attribut not allowed for channels" 
	                if (!$hash->{helper}{role}{dev});
	$updtReq = 1; 
  }
  elsif($attrName eq "param"){
    my $md  = CUL_HM_Get($hash,$name,"param","model");
	my $chn = substr(CUL_HM_hash2Id($hash),6,2);
    if ($md eq "HM-Sen-RD-O" && $chn eq "02"){
	  delete $hash->{helper}{param};
	  my @param = split ",",$attrVal;
	  foreach (@param){
        if    ($_ eq "offAtPon"){$hash->{helper}{param}{offAtPon} = 1}
        elsif ($_ eq "onAtRain"){$hash->{helper}{param}{onAtRain} = 1}
		else {return "param $_ unknown, use offAtPon or onAtRain";}
	  }
	}
	else{
	  return "attribut param not defined for this entity";
	}
  }
  elsif($attrName eq "peerIDs"   &&!$hash->{helper}{role}{chn}){#only for chan
    return "$attrName not usable for devices";
  }
  elsif($attrName eq "msgRepeat"){
    return if ($cmd ne "set");
    return "$attrName not usable for channels" if(!$hash->{helper}{role}{dev});#only for device
	return "value $attrVal ignored, must be an integer" if ($attrVal !~ m/^(\d+)$/);
  }
  elsif($attrName eq "model" && $hash->{helper}{role}{dev}){
    delete $hash->{helper}{rxType}; # needs new calculation
	delete $hash->{helper}{mId};
  }
  elsif($attrName eq "burstAccess"){
    if ($cmd eq "set"){
      return "use burstAccess only for device"                 if (!$hash->{helper}{role}{dev});
	  return "$attrVal not a valid option for burstAccess"     if ($attrVal !~ m/^[01]/);
	  if ($attrVal =~ m/^0/){$hash->{protCondBurst} = "forced_off";}
	  else                  {$hash->{protCondBurst} = "unknown";}
	}
	else{                    $hash->{protCondBurst} = "forced_off";}
    delete $hash->{helper}{rxType}; # needs new calculation
  }
  CUL_HM_queueUpdtCfg($name) if ($updtReq);
  return;
}

#+++++++++++++++++ msg receive, parsing++++++++++++++++++++++++++++++++++++++++
# translate level to readable
    my %lvlStr = ( md  =>{ "HM-SEC-WDS"      =>{"00"=>"dry"     ,"64"=>"damp"    ,"C8"=>"wet"        }
	                      ,"HM-CC-SCD"       =>{"00"=>"normal"  ,"64"=>"added"   ,"C8"=>"addedStrong"}
	                      ,"HM-Sen-RD-O"     =>{"00"=>"dry"                      ,"C8"=>"rain"}
	                     }
                  ,mdCh=>{ "HM-Sen-RD-O01"   =>{"00"=>"dry"                      ,"C8"=>"rain"}
	                      ,"HM-Sen-RD-O02"   =>{"00"=>"off"                      ,"C8"=>"on"}
	                     }
				  ,st  =>{ "smokeDetector"   =>{"01"=>"no alarm","C7"=>"tone off","C8"=>"Smoke Alarm"}
				          ,"threeStateSensor"=>{"00"=>"closed"  ,"64"=>"tilted"  ,"C8"=>"open"}
		                 }
	              );
sub CUL_HM_Parse($$) {##############################
  my ($iohash, $msgIn) = @_;
  my $id = CUL_HM_Id($iohash);
  my $ioName = $iohash->{NAME};
  my ($msg,$msgStat,$myRSSI,$msgIO) = split(":",$msgIn,4);
  # Msg format: Allnnffttssssssddddddpp...
  $msg =~ m/A(..)(..)(..)(..)(......)(......)(.*)/;
  my ($len,$mNo,$mFlg,$mTp,$src,$dst,$p) = ($1,$2,$3,$4,$5,$6,$7);
  $p = "" if(!defined($p));
  my @mI = unpack '(A2)*',$p; # split message info to bytes

  return "" if(  ($msgStat && $msgStat eq 'NACK')# lowlevel error
               ||($src eq $id));                 # mirrored messages
  # $shash will be replaced for multichannel commands
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};

  $respRemoved = 0;  #set to 'no response in this message' at start
  if(!$shash) {      #  Unknown source
    # Generate an UNKNOWN event for pairing requests, ignore everything else
    if($mTp eq "00") {
      my $md = substr($p, 2, 4);
	  $md = $culHmModel{$md}{name}  ?
	            $culHmModel{$md}{name} :
				"ID_".$md;
	  my $sname = "CUL_HM_".$md."_$src";
	  $sname =~ s/-/_/g;
      Log 3, "CUL_HM Unknown device $sname, please define it";
      return "UNDEFINED $sname CUL_HM $src $msg";
    }
   return "";
  }
  my @event;    #events to be posted for main entity
  my @entities; #additional entities with events to be notifies
			   
  my $name = $shash->{NAME};
  return if (CUL_HM_getAttrInt($name,"ignore"));

  if ($msgStat && $msgStat =~ m/AESKey/){
    push @entities,CUL_HM_UpdtReadSingle($shash,"aesKeyNbr",substr($msgStat,7),1);
    $msgStat = ""; # already processed
  }
  CUL_HM_eventP($shash,"Evt_$msgStat")if ($msgStat);#log io-events
  CUL_HM_eventP($shash,"Rcv");
  my $dname = ($dst eq "000000") ? "broadcast" :
                                   ($dhash ? $dhash->{NAME} : 
								             ($dst eq $id ? $ioName : 
											                $dst));
  my $target = " (to $dname)";
  my $st = AttrVal($name, "subType", "");
  my $md = AttrVal($name, "model"  , "");
  my $tn = TimeNow();
  CUL_HM_storeRssi($name,
                   "at_".((hex($mFlg)&0x40)?"rpt_":"").$ioName,# repeater?
                   $myRSSI);

  my $msgX = "No:$mNo - t:$mTp s:$src d:$dst ".($p?$p:"");
  if($shash->{lastMsg} && $shash->{lastMsg} eq $msgX) { #duplicate -lost 'ack'?
    if(   $shash->{helper}{rpt}                           #was responded
       && $shash->{helper}{rpt}{IO}  eq $ioName           #from same IO
       && $shash->{helper}{rpt}{flg} eq substr($msg,5,1)  #not from repeater
       && $shash->{helper}{rpt}{ts}  < gettimeofday()-0.24 # again if older then 240ms (typ repeat time)
	                                                      #todo: hack since HMLAN sends duplicate status messages
	   ){
	  my $ack = $shash->{helper}{rpt}{ack};#shorthand
	  my $i=0;
	  $shash->{helper}{rpt}{ts} = gettimeofday();
      CUL_HM_SndCmd(${$ack}[$i++],${$ack}[$i++]) while ($i<@{$ack});
      Log GetLogLevel($name,4), "CUL_HM $name dup: repeat ack, dont process";
	}
	else{
      Log GetLogLevel($name,4), "CUL_HM $name dup: dont process";
	}
    return $name; #return something to please dispatcher
  }
  $shash->{lastMsg} = $msgX;
  delete $shash->{helper}{rpt};# new message, rm recent ack
  my @ack; # ack and responses, might be repeated
  
  CUL_HM_DumpProtocol("RCV",$iohash,$len,$mNo,$mFlg,$mTp,$src,$dst,$p);

  #----------start valid messages parsing ---------
  my $parse = CUL_HM_parseCommon($mNo,$mFlg,$mTp,$src,$dst,$p,$st,$md);
  push @event, "powerOn"   if($parse eq "powerOn");
  push @event, ""          if($parse eq "parsed"); # msg is parsed but may
                                                   # be processed further 
  foreach my $r (split";",$parse){
    if ($r =~ s/entities://){#common generated trigger for some entities
      push @entities,split(",",$r);
    }
	else{
	  $parse = $r;
	}
  }

  if   ($parse eq "ACK"){# remember - ACKinfo will be passed on
    push @event, "";
  }
  elsif($parse eq "NACK"){
	push @event, "state:NACK";
  }
  elsif($parse eq "done"){
    push @event, "";
  } 
  elsif($mTp eq "12") {#$lcm eq "09A112" Another fhem request (HAVE_DATA)
    ;
  } 
  elsif($md =~ m/^(KS550|HM-WDS100-C6-O)$/) { #################################

    if($mTp eq "70" && $p =~ m/^(....)(..)(....)(....)(..)(..)(..)/) {

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
  elsif($md eq "HM-CC-TC") { ##################################################
    my ($sType,$chn) = ($1,$2) if($p && $p =~ m/^(..)(..)/);
    if($mTp eq "70" && $p =~ m/^(....)(..)/) { # weather event
	  $chn = '01'; # fix definition
      my (    $t,      $h) =  (hex($1), hex($2));# temp is 15 bit signed
      $t = sprintf("%2.1f",($t & 0x3fff)/10*(($t & 0x4000)?-1:1));
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  push @entities,CUL_HM_UpdtReadBulk($chnHash,1,"state:T: $t H: $h", 
	                                                "measured-temp:$t",
	                                                "humidity:$h")
				  if ($chnHash);
      push @event, "state:T: $t H: $h";
      push @event, "measured-temp:$t";
      push @event, "humidity:$h";
    }
    elsif($mTp eq "58" && $p =~ m/^(..)(..)/) {# climate event
	  $chn = '02'; # fix definition
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $1, hex($2));
      $vp = int($vp/2.56+0.5);   # valve position in %
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  if($chnHash){
  	    push @entities,CUL_HM_UpdtReadSingle($chnHash,"state","$vp %",1);
	    if ($chnHash->{helper}{needUpdate}){
		  if ($chnHash->{helper}{needUpdate} == 1){
		    $chnHash->{helper}{needUpdate}++;
		  }
		  else{
	        CUL_HM_qStateUpdatIfEnab(":".$chnHash->{NAME});
		    delete $chnHash->{helper}{needUpdate};
		  }
	    }
	  }
      push @event, "actuator:$vp %";

      # Set the valve state too, without an extra trigger
	  push @entities,CUL_HM_UpdtReadBulk($dhash,1,
		               "state:set_$vp %",
		               "ValveDesired:$vp %")
            if($dhash);
    }
    elsif(($mTp eq '02' &&$sType eq '01')||    # ackStatus
	      ($mTp eq '10' &&$sType eq '06')){    # infoStatus
	  $chn = substr($p,2,2); 
	  my $dTemp = hex(substr($p,4,2))/2;
	  $dTemp = ($dTemp < 6 )?'off':
	           ($dTemp >30 )?'on' :sprintf("%0.1f", $dTemp);
	  my $err = hex(substr($p,6,2));
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  if($chnHash){
	    my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-controlMode","");	
	    push @entities,CUL_HM_UpdtReadSingle($chnHash,"desired-temp",$dTemp,1);
	    CUL_HM_UpdtReadSingle($chnHash,"desired-temp-manu",$dTemp,1) if($mode =~ m /manual/  && $mTp eq '10');
#	    readingsSingleUpdate($chnHash,"desired-temp-cent",$dTemp,1) if($mode =~ m /central/ && $mTp eq '02');
#		removed - shall not be changed automatically - change is  only temporary
#       CUL_HM_Set($chnHash,$chnName,"desired-temp",$dTemp)         if($mode =~ m /central/ && $mTp eq '10');
        $chnHash->{helper}{needUpdate} = 1                          if($mode =~ m /central/ && $mTp eq '10');
       }
      push @event, "desired-temp:" .$dTemp;
	  push @event, "battery:".($err&0x80?"low":"ok");  
    }
    elsif($mTp eq "10" &&                   # Config change report
          ($p =~ m/^0402000000000501/)) {   # paramchanged L5
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      my $dTemp;
	  if($chnHash){
	    my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-controlMode","");	
        $dTemp = ReadingsVal($chnName,"desired-temp","21.0");
		if (!$chnHash->{helper}{oldMode} || $chnHash->{helper}{oldMode} ne $mode){
		  $dTemp = ReadingsVal($chnName,"desired-temp-manu",$dTemp)if ($mode =~ m /manual/);
		  $dTemp = ReadingsVal($chnName,"desired-temp-cent",$dTemp)if ($mode =~ m /central/);
		  $chnHash->{helper}{oldMode} = $mode;
		}
		push @entities,CUL_HM_UpdtReadSingle($chnHash,"desired-temp",$dTemp,1);
      }
      push @event, "desired-temp:" .$dTemp;
	}
    elsif($mTp eq "01"){                       # status reports
      if($p =~ m/^010809(..)0A(..)/) { # TC set valve  for VD => post events to VD
        my (   $of,     $vep) = (hex($1), hex($2));
        push @event, "ValveErrorPosition_for_$dname: $vep %";
        push @event, "ValveOffset_for_$dname: $of %";
	    push @entities,
		CUL_HM_UpdtReadBulk($dhash,1,'ValveErrorPosition:set_'.$vep.' %',
		                             'ValveOffset:set_'.$of.' %');
	  }
	  elsif($p =~ m/^010[56]/){ # 'prepare to set' or 'end set'
	  	push @event,""; # 
	  }
    }
    elsif($mTp eq "3F" && $id eq $dst) {       # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$shash,"++803F$id${src}0204$s2000";
      push @event, "time-request";
    } 
  } 
  elsif($md eq "HM-CC-VD") { ##################################################
    if($mTp eq "02" && $p =~ m/^(..)(..)(..)(..)/) {#subtype+chn+value+err
      my ($chn,$vp, $err) = (hex($2),hex($3), hex($4));
  	  $chn = sprintf("%02X",$chn&0x3f);
      $vp = int($vp)/2;   # valve position in %
	  push @event, "ValvePosition:$vp %";
      push @event, "state:$vp %";
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

	  my $stErr = ($err >>1) & 0x7;    # Status-Byte Evaluation
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
      
	  #VD hang detection
	  my $des = ReadingsVal($name, "ValveDesired", "");
	  $des =~ s/ .*//; # remove unit
	  if ($des ne $vp && ($err&0x30) == 0x00){
	    push @event, "operState:errorTargetNotMet";
	    push @event, "operStateErrCnt:".
	               (ReadingsVal($name,"operStateErrCnt","0")+1);
	  }
	  else{
	    push @event, "operState:".((($err&0x30) == 0x00)?"onTarget":"adjusting");
	  }
    }
  } 
  elsif($md =~ m/HM-CC-RT-DN/) { ##############################################
    my %ctlTbl=( 0=>"auto", 1=>"manu", 2=>"party",3=>"boost");
    if   ($mTp eq "10" && $p =~ m/^0A(....)(..)(..)(..)/) {#info-level
      my ($chn,$setTemp,$actTemp,$err,$bat,$vp,$ctrlMode) = 
	      ("04",hex($1),hex($1),hex($2),hex($2),hex($3), hex($4));
	  $setTemp    =(($setTemp    >>10) & 0x3f )/2;
	  $actTemp    =(($actTemp        ) & 0x3ff)/10;
	  $err        = ($err        >> 5) & 0x7  ;
	  $bat        =(($bat            ) & 0x1f)/10+1.5;
	  $vp         = ($vp             ) & 0x7f ;
	  my $uk0     = ($ctrlMode       ) & 0x3f ;#unknown
	  $ctrlMode   = ($ctrlMode   >> 6) & 0x3  ;
      $actTemp = sprintf("%2.1f",$actTemp);
	  
	  my $dHash = $shash;
 	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	  

      my %errTbl=( 0=>"ok", 1=>"ValveTight", 2=>"adjustRangeTooLarge"
                  ,3=>"adjustRangeTooSmall" , 4=>"communicationERR"         
                  ,5=>"unknown" , 6=>"lowBat" , 7=>"ValveErrorPosition" );

      push @event, "motorErr:$errTbl{$err}";
      push @event, "measured-temp:$actTemp";
      push @event, "desired-temp:$setTemp";
	  push @event, "ValvePosition:$vp %";
      push @event, "mode:$ctlTbl{$ctrlMode}";
      push @event, "unknown0:$uk0";
      push @event, "unknown1:".$2 if ($p =~ m/^0A(.10)(.*)/);
      push @event, "state:T: $actTemp desired: $setTemp valve: $vp %";
      push @entities,CUL_HM_UpdtReadBulk($dHash,1
	                                        ,"battery:".($err&0x80?"low":"ok")
	                                        ,"batteryLevel:$bat V"
                                            ,"measured-temp:$actTemp" # values to please HCS
                                            ,"desired-temp:$setTemp"
	                                        ,"actuator:$vp %"
											);
    }
    elsif($mTp eq "59" && $p =~ m/^(..)/) {#inform team about new value
	  my $setTemp = int(hex($1)/4)/2;
	  my $ctrlMode = hex($1)&0x3;
      push @event, "desired-temp:$setTemp";
      push @event, "mode:$ctlTbl{$ctrlMode}";

	  my $tHash = $modules{CUL_HM}{defptr}{$dst."04"};
      push @entities,CUL_HM_UpdtReadBulk($tHash,1
	                                        ,"desired-temp:$setTemp"
											,"mode:$ctlTbl{$ctrlMode}"
											)
	        if ($tHash);
	  }
    elsif($mTp eq "3F" && $id eq $dst) {       # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$shash,"++803F$id${src}0204$s2000";
      push @event, "time-request";
    } 
  } 
  elsif($md =~ m/^(HM-Sen-Wa-Od|HM-CC-SCD)$/){ ################################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
	    ($mTp eq "10" && $p =~ m/^06/) ||  #or Info_Status message here
	    ($mTp eq "41"))                { 
	  my $lvl = substr($p,4,2);
	  my $err = hex(substr($p,6,2));
	  if    ($lvlStr{md}{$md}){$lvl = $lvlStr{md}{$md}{$lvl}}
	  elsif ($lvlStr{st}{$st}){$lvl = $lvlStr{st}{$st}{$lvl} }
	  else                    {$lvl = hex($lvl)/2}

	  push @event, "level:$lvl %" if($md eq "HM-Sen-Wa-Od");
	  push @event, "state:$lvl %";	  
	  push @event, "battery:".($err&0x80?"low":"ok") if (defined $err);
	}  
  }
  elsif($md eq "KFM-Sensor") { ################################################
    if ($mTp eq "53"){
      if($p =~ m/.14(.)0200(..)(..)(..)/) {
        my ($seq, $k_v1, $k_v2, $k_v3) = (hex($1),$2,hex($3),hex($4));
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
  elsif($st eq "THSensor") { ##################################################
    if    ($mTp eq "70"){
	  my $chn = 1;
	  $chn = 10 if ($md =~  m/^(WS550|WS888|HM-WDC7000)/);#todo use channel correct
      my $t =  hex(substr($p,0,4));
      $t -= 32768 if($t > 1638.4);
      $t = sprintf("%0.1f", $t/10);
      my $statemsg = "state:T: $t";
      push @event, "temperature:$t";#temp is always there
	  if ($md eq "HM-WDS30-OT2-SM"){
	    $chn = 5;
		my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
		push @entities,CUL_HM_UpdtReadBulk($chnHash,1,$statemsg, 
	                                                "temperature:$t")
				  if ($chnHash);
	  }
	  elsif ($md !~ m/^(S550IA|HM-WDS30-T-O)$/){#skip temp-only sens
        my $h =  hex(substr($p,4,2));
        $statemsg .= " H: $h";
        push @event, "humidity:$h";
	    if ($md eq "HM-WDC7000"){#airpressure sensor
          my $ap = hex(substr($p,6,4));
          $statemsg .= " AP: $ap";
          push @event, "airpress:$ap";
	    }
	  }
      push @event, $statemsg;
	}
    elsif ($mTp eq "53"){
      my ($mChn,@dat) = unpack 'A2(A6)*',$p;
	  foreach (@dat){
	    my ($a,$d) = unpack 'A2A4',$_;
		$d = hex($d);
		$d -= 0x10000 if($d & 0xC000); 
		$d = sprintf("%0.1f",$d/10);
		my $chId = sprintf("%02X",hex($a) & 0x3f);
		my $chnHash = $modules{CUL_HM}{defptr}{$src.$chId};									 
		if ($chnHash){
		  push @entities,CUL_HM_UpdtReadBulk($chnHash,1
		                                      ,"state:T: $d"
	                                          ,"temperature:$d");
		}
		else{
          push @event, "Chan_$chId:T: $d"; 
		}
	  }
	}
  } 
  elsif($st eq "sensRain") {###################################################
    my $hHash = CUL_HM_id2Hash($src."02");# hash for heating
	my $pon = 0;# power on if mNo == 0 and heating status plus second msg
	            # status or trigger from rain channel 
	my $devHash = $shash;
    if (($mTp eq "02" && $p =~ m/^01/) || #Ack_Status
	    ($mTp eq "10" && $p =~ m/^06/))	{ #Info_Status

      my ($subType,$chn,$val,$err) = ($1,hex($2),$3,hex($4)) 
 	                     if($p =~ m/^(..)(..)(..)(..)/);
	  $chn = sprintf("%02X",$chn&0x3f);
	  my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId} 
	                         if($modules{CUL_HM}{defptr}{$chId});
							 
      push @event, "timedOn:".(($err&0x40 && $chn eq "02")?"running":"off");
	  
	  my $mdCh = $md.$chn;
	  if($lvlStr{mdCh}{$mdCh} && $lvlStr{mdCh}{$mdCh}{$val}){
	    $val = $lvlStr{mdCh}{$mdCh}{$val};
      }
	  else{
	    $val = hex($val)/2;
	  }
	  push @event, "state:$val";

	  if ($val eq "rain"){#--- handle lastRain---
        $shash->{helper}{lastRain} = $tn;
      }	  
	  elsif ($val eq "dry" && $shash->{helper}{lastRain}){
 	    CUL_HM_UpdtReadSingle($shash,'lastRain',$shash->{helper}{lastRain},0);
        delete $shash->{helper}{lastRain};
      }	  

 	  CUL_HM_UpdtReadSingle($shash,'.level',#store level invisible
	                                 ($val eq "off"?"0 %":"100 %"),0);
 	  
	  if ($mNo eq "00" && $chn eq "02" && $val eq "on"){
	    $hHash->{helper}{pOn} = 1;
	  }
	  elsif ($mNo eq "01" && $chn eq "01" && 
	         $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
		$pon = 1;
	  }
	  else{
	    delete $hHash->{helper}{pOn};
		my $hHash = CUL_HM_id2Hash($src."02");# hash for heating
		if ($chn eq "01" &&
		    $hHash->{helper}{param} && $hHash->{helper}{param}{onAtRain}){
	      CUL_HM_Set($hHash,$hHash->{NAME},$val eq "rain"?"on":"off");
		}
	  }
	}
    elsif ($mTp eq "41")	{ #eventonAtRain
      my ($chn,$bno,$val) = unpack('(A2)*',$p);
	  my $mdCh = $md.$chn;
	  $chn = sprintf("%02X",hex($chn)&0x3f);
	  my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId} 
	                         if($modules{CUL_HM}{defptr}{$chId});
	  push @event,"trigger:".hex($bno).":".$lvlStr{mdCh}{$mdCh}{$val}.$target;
	  if ($mNo eq "01" && $bno eq "01" &&
	      $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
		$pon = 1;
	  }
	  delete $shash->{helper}{pOn};
	}
	if ($pon){# we have power ON, perform action
	  push @entities,CUL_HM_UpdtReadSingle($devHash,'powerOn',"-",1);
	  CUL_HM_Set($hHash,$hHash->{NAME},"off")
		         if ($hHash && $hHash->{helper}{param}{offAtPon});
	}
  } 
  elsif($st =~ m /^(switch|dimmer|blindActuator)$/) {##########################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
	    ($mTp eq "10" && $p =~ m/^06/))	{ #    or Info_Status message here

	  my $rSUpdt = 0;# require status update
      my ($subType,$chn,$val,$err) = ($1,hex($2),hex($3)/2,hex($4)) 
 	                     if($p =~ m/^(..)(..)(..)(..)/);
	  $chn = sprintf("%02X",$chn&0x3f);
	  my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId} 
	                         if($modules{CUL_HM}{defptr}{$chId});
	  my $physLvl;                             #store phys level if available
	  if(   $p =~ m/^........(..)(..)$/        #message with physical level?
	     && $st eq "dimmer"){ 
	    my $pl = hex($2)/2;
		my $vDim = $shash->{helper}{vDim};     #shortcut
        if ($vDim->{idPhy} && 
		    CUL_HM_id2Hash($vDim->{idPhy})){   #has virt chan
	      RemoveInternalTimer("sUpdt:".$chId); 
		  if ($mTp eq "10"){                   #valid PhysLevel                         
		    foreach my $tmpKey ("idPhy","idV2","idV3",){#update all virtuals
			  my $vh = CUL_HM_id2Hash($vDim->{$tmpKey}) if ($vDim->{$tmpKey});
			  next if (!$vh || $vDim->{$tmpKey} eq $chId);
			  my $vl = ReadingsVal($vh->{NAME},"level","???");
			  my $vs = ($vl eq "100 %"?"on":($vl eq "0 %"?"off":"$vl"));
			  $vs = (($pl." %") ne $vl)?"chn:$vs  phys:$pl %":$vs;
		      push @entities,CUL_HM_UpdtReadBulk($vh ,1,"state:$vs",
										                "phyLevel:$pl %");
			}
			push @event,"phyLevel:$pl %";      #phys level 
			$physLvl = $pl." %";
		  }
		  else{                                #invalid PhysLevel
            $rSUpdt = 1;		  
		    CUL_HM_stateUpdatDly($shash->{NAME},5);     # update to get level
		  }
		}
	  }
	  $physLvl = ReadingsVal($name,"phyLevel",$val." %") 
	        if(!$physLvl);                     #not updated? use old or ignore
      my $vs = ($val==100 ? "on":($val==0 ? "off":"$val %")); # user string...

	  push @event,"level:$val %";
	  push @event,"pct:$val"; # duplicate to level - necessary for "slider"
      push @event,"deviceMsg:$vs$target" if($chn ne "00");
	  push @event,"state:".(($physLvl ne $val." %")?"chn:$vs phys:$physLvl":
	                                                $vs);
      my $eventName = "unknown"; # different names for events
      $eventName = "switch"  if($st eq "switch");
      $eventName = "motor"   if($st eq "blindActuator");
	  $eventName = "dim"     if($st eq "dimmer");
	  my $action; #determine action
      push @event, "timedOn:".(($err&0x40)?"running":"off");

	  if ($st ne "switch"){
        push @event, "$eventName:up:$vs"   if(($err&0x30) == 0x10);
        push @event, "$eventName:down:$vs" if(($err&0x30) == 0x20);
        push @event, "$eventName:stop:$vs" if(($err&0x30) == 0x00);
		if (!$rSUpdt){#dont touch if necessary for dimmer
		  if(($err&0x30) != 0x00){CUL_HM_stateUpdatDly($shash->{NAME},120);}
		  else                   {CUL_HM_unQEntity($shash->{NAME},"qReqStat");}
		}
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
	  elsif ($md eq "HM-SEC-SFA-SM"){ # && $chn eq "00")
	    push @entities,
  	        CUL_HM_UpdtReadBulk(CUL_HM_getDeviceHash($shash),1,
		        "powerError:"   .(($err&0x02) ? "on":"off"),
	            "sabotageError:".(($err&0x04) ? "on":"off"),
	            "battery:".(($err&0x08)?"critical":($err&0x80?"low":"ok")));
	  }
	  elsif ($md eq "HM-LC-SW1-BA-PCB"){
	    push @event,"battery:" . (($err&0x80) ? "low" : "ok" );
	  }
    }
  } 
  elsif($st =~ m /^(remote|pushButton|swi)$/) { ###############################
    if($mTp =~ m/^4./ && $p =~ m/^(..)(..)/) {
      my ($chn, $bno) = (hex($1), hex($2));# button number/event count
	  my $buttonID = $chn&0x3f;# only 6 bit are valid
	  my $btnName;
	  my $state = "";
      my $chnHash = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$buttonID)};	  
	  
	  if ($chnHash){# use userdefined name - ignore this irritating on-off naming
		$btnName = $chnHash->{NAME};
	  }
	  else{# Button not defined, use default naming
	    $chnHash = $shash;
	    if ($st eq "swi"){#maintain history for event naming
			$btnName = "Btn$chn";
		}
		else{
		  my $btn = int((($chn&0x3f)+1)/2);
		  $btnName = "Btn$btn";
		  $state = ($chn&1 ? "off" : "on")
		}
	  }
      my $trigType;
      if($chn & 0x40){
		if(!$shash->{BNO} || $shash->{BNO} ne $bno){#bno = event counter
		  $shash->{BNO}=$bno;
		  $shash->{BNOCNT}=0; # message counter reest
		}
		$shash->{BNOCNT}+=1;
        $state .= "Long" .($mFlg eq "A0" ? "Release" : "").
				  " ".$shash->{BNOCNT}."-".$mFlg.$mTp."-";
		$trigType = "Long";
      }
	  else{
        $state .= ($st eq "swi")?"toggle":"Short";#swi only support toggle
		$trigType = "Short";
      }
	  $shash->{helper}{addVal} = $chn;   #store to handle changesFread
	  push @entities,CUL_HM_UpdtReadBulk($chnHash,1,
	                                         ,"state:".$state.$target
	                                         ,"trigger:".$trigType."_".$bno);
      push @event,"battery:". (($chn&0x80)?"low":"ok");
      push @event,"state:$btnName $state$target";
    }
  }
  elsif($st eq "repeater"){ ###################################################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
        ($mTp eq "10" && $p =~ m/^06/)) {  #or Info_Status message here
      my ($state,$err) = ($1,hex($2)) if ($p =~ m/^....(..)(..)/);
      # not sure what level are possible
      push @event, "state:".($state eq '00'?"ok":"level:".$state);
      push @event, "battery:".   (($err&0x80)?"low"  :"ok"  );
      my $flag = ($err>>4) &0x7;
      push @event, "flags:".     (($flag)?"none"     :$flag  );
	}
  }
  elsif($st eq "virtual"){ ####################################################
    # possibly add code to count all acks that are paired. 
    if($mTp eq "02") {# this must be a reflection from what we sent, ignore
      push @event, "";
	}
  }
  elsif($st eq "outputUnit"){ #################################################
    if($mTp eq "40" && @mI == 2){
      my ($button, $bno) = (hex($mI[0]), hex($mI[1]));
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
	elsif(($mTp eq "02" && $mI[0] eq "01") ||   # handle Ack_Status
	      ($mTp eq "10" && $mI[0] eq "06")){    #    or Info_Status message
      my ($msgChn,$msgState) = ((hex($mI[1])&0x1f),$mI[2]) if (@mI > 2);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$msgChn)};
	  if ($md eq "HM-OU-LED16") {
	    #special: all LEDs map to device state
        my $devState = ReadingsVal($name,"color","00000000");
		if($parse eq "powerOn"){# reset LEDs after power on
		  CUL_HM_PushCmdStack($shash,'++A011'.$id.$src."8100".$devState);
		  CUL_HM_ProcessCmdStack($shash);
		  # no event necessary, all the same as before
		}
		else {# just update datafields in storage
          if (@mI > 8){#status for all channel included
		    # open to decode byte $mI[4] - related to backlight? seen 20 and 21
		    my $lStat = join("",@mI[5..8]); # all LED status in one long
 	        my %colTbl=("00"=>"off","01"=>"red","10"=>"green","11"=>"orange");
		    my @leds = reverse(unpack('(A2)*',sprintf("%032b",hex($lStat))));
			$_ = $colTbl{$_} foreach (@leds);
			for(my $cCnt = 0;$cCnt<16;$cCnt++){# go for all channels
			  my $cH = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$cCnt+1)};
			  next if (!$cH);
			  if (ReadingsVal($cH->{NAME},"state","") ne $leds[$cCnt]) {
                push @entities,CUL_HM_UpdtReadBulk($cH,1,"color:".$leds[$cCnt],
		                                                "state:".$leds[$cCnt]);			    
			  }
			}
	        push @entities,CUL_HM_UpdtReadBulk($shash,1,"color:".$lStat,
		                                                "state:".$lStat);
		  }
		  else{# branch can be removed if message is always that long
 	        my $bitLoc = ($msgChn-1)*2;#calculate bit location
 	        my $mask = 3<<$bitLoc;
 	        my $value = sprintf("%08X",(hex($devState) &~$mask)|($msgState<<$bitLoc));
	        push @entities,CUL_HM_UpdtReadBulk($shash,1,"color:".$value,
		                                                "state:".$value);
		    if ($chnHash){
 	          $shash = $chnHash;
 	          my %colorTable=("00"=>"off","01"=>"red","02"=>"green","03"=>"orange");
 	          my $actColor = $colorTable{$msgState};
 	          $actColor = "unknown" if(!$actColor);
		      push @event, "color:$actColor";  
              push @event, "state:$actColor";
            }			  
 	      }
		}
	  }
	  elsif ($md eq "HM-OU-CFM-PL"){
	    if ($chnHash){
	      $shash = $chnHash;
	      my $val = hex($mI[2])/2;
          $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
          push @event, "state:$val";			
	    }
	  }
	}  
  } 
  elsif($st eq "motionDetector") { ############################################
    # Code with help of Bassem
    my $state;
    if(($mTp eq "10" ||$mTp eq "02") && $p =~ m/^0601(..)(..)/) {
	  my $err;
      ($state, $err) = ($1, hex($2));
	  my $bright = hex($state);
      push @event, "brightness:".$bright;
	  if ($md eq "HM-Sec-MDIR"){
	    push @event, "sabotageError:".(($err&0x0E)?"on":"off");   
	  }
	  else{
  	    push @event, "cover:".        (($err&0x0E)?"open" :"closed");
	  }
	  push @event, "battery:".   (($err&0x80)?"low"  :"ok"  );
    }
    elsif($mTp eq "41" && $p =~ m/^01(..)(..)(..)/) {#01 is channel
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
    elsif($mTp eq "70" && $p =~ m/^7F(..)(.*)/) {
	  my($d1, $d2) = ($1, $2);
      push @event, 'devState_raw'.$d1.':'.$d2;
    }
	
	if($id eq $dst && hex($mFlg)&0x20 && $state){
      push @ack,$shash,$mNo."8002".$id.$src."0101${state}00";
	}
  } 
  elsif($st eq "smokeDetector") { #############################################
	#Info Level: mTp=0x10 p(..)(..)(..) subtype=06, channel, state (1 byte)
	#Event:      mTp=0x41 p(..)(..)(..) channel   , unknown, state (1 byte)

	if ($mTp eq "10" && $p =~ m/^06..(..)/) {
	  my $state = hex($1);
      push @event, "battery:". (($state&0x04)?"low"  :"ok"  );
      push @event, "state:alive";
    } 
    elsif ($mTp eq "40"){ #autonomous event
	  if($dhash){ # the source is in dst
	    my ($state,$trgCnt) = (hex(substr($p,0,2)),hex(substr($p,2,2)));
		push @entities,CUL_HM_UpdtReadSingle($dhash,'test',"from $dname:$state",1)
		      if (!($state & 1));
		push @entities,CUL_HM_UpdtReadSingle($dhash,'battery',(($state & 0x04)?"low":"ok"),1)
		      if($state&0x80);
	  }
      push @event, "";
    }
    elsif ($mTp eq "41"){ #Alarm detected
	  #C8: Smoke Alarm
	  #C7: tone off
	  #01: no alarm
	  my ($No,$state) = (substr($p,2,2),substr($p,4,2));
	  if(($dhash && $dname ne $name) && # update source(ID reported in $dst)
	     (!$dhash->{helper}{alarmNo} || $dhash->{helper}{alarmNo} ne $No)){
		$dhash->{helper}{alarmNo} = $No;
		push @entities,
		     CUL_HM_UpdtReadBulk($dhash,1,
			           'state:'.(($state eq "01")?"off":"smoke-Alarm_".$No),
			   	       "eventNo:".$No
			           );
	  }
	  # - - - - - - now handle the team - - - - - - 
	  my @alarmArry;
	  @alarmArry = split(",",$shash->{helper}{alarmList}) 
	        if ($shash->{helper}{alarmList});
	  if ($state eq "01") { # clear alarm for sensor
		@alarmArry = grep !/$dst/,@alarmArry;
	  }
	  else{                 # add alarm for Sensor
		@alarmArry = CUL_HM_noDup(@alarmArry,$dst);
	  }
	  my $alarmList;        # make alarm ID list readable
	  foreach(@alarmArry){
	    $alarmList .= CUL_HM_id2Name($_)."," if ($_);
	  }
	  $shash->{helper}{alarmList} = join",",@alarmArry;
      push @event,"state:"        .($alarmList?"smoke-Alarm":"off" );
      push @event,"smoke_detect:" .($alarmList?$alarmList   :"none");
	  #--- check out teamstatus, members might be shy ---
	  my $peerList = $shash->{peerList}?$shash->{peerList}:"";
	  foreach my $pNm (split(",",$peerList)){
		CUL_HM_qStateUpdatIfEnab($pNm,1)if ($pNm);
	  }
    } 
    elsif ($mTp eq "01"){ #Configs
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
	
	if($id eq $dst && (hex($mFlg)&0x20)){  # Send Ack/Nack
      push @ack,$shash,$mNo."8002".$id.$src.($mFlg.$mTp eq "A001" ? "80":"00");
	}
  } 
  elsif($st eq "threeStateSensor") { ##########################################
	#Event:      mTp=0x41 p(..)(..)(..)     channel   , unknown, state
	#Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)
	my ($chn,$state,$err,$cnt); #define locals
    if(($mTp eq "10" && $p =~ m/^06/) ||
	   ($mTp eq "02" && $p =~ m/^01/)) {
	  $p =~ m/^..(..)(..)(..)?$/;
      ($chn,$state,$err) = (hex($1), $2, hex($3));
	  $chn = sprintf("%02X",$chn&0x3f);
	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
	  push @event, "alive:yes";
	  push @event, "battery:". (($err&0x80)?"low"  :"ok"  );
	  if (   $md eq "HM-SEC-SC" ||
	         $md eq "HM-Sec-RHS"){push @event, "sabotageError:".(($err&0x0E)?"on":"off");
	  }elsif($md ne "HM-SEC-WDS"){push @event, "cover:"        .(($err&0x0E)?"open" :"closed");
	  }
	}
	elsif($mTp eq "41"){
	  ($chn,$cnt,$state)=(hex($1),$2,$3) if($p =~ m/^(..)(..)(..)/);
	  $chn = sprintf("%02X",$chn&0x3f);
	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});	
	}
	if (defined($state)){# if state was detected post events
	  my $txt;
	  if    ($lvlStr{md}{$md}){$txt = $lvlStr{md}{$md}{$state}}
	  elsif ($lvlStr{st}{$st}){$txt = $lvlStr{st}{$st}{$state}}
	  else                    {$txt = "unknown:$state"}

	  push @event, "state:$txt";
	  push @event, "contact:$txt$target";
    }
    else{push @event, "3SSunknownMsg:$p" if(!@event);}
  } 
  elsif($st eq "winMatic") {  #################################################
    my($sType,$chn,$lvl,$stat) = ($1,$2,$3,$4) if ($p =~ m/^(..)(..)(..)(..)/);
    if(($mTp eq "10" && $sType eq "06") ||
	   ($mTp eq "02" && $sType eq "01")){
	  $shash = $modules{CUL_HM}{defptr}{"$src$chn"} 
	                         if($modules{CUL_HM}{defptr}{"$src$chn"});
	  # stateflag meaning unknown
	  push @event, "state:".(($lvl eq "FF")?"locked":((hex($lvl)/2)." %"));
	  if ($chn eq "01"){
	    my %err = (0=>"no",1=>"TurnError",2=>"TiltError");
	    my %dir = (0=>"no",1=>"up",2=>"down",3=>"undefined");
	    push @event, "motorError:".$err{(hex($stat)>>1)&0x02};
	    push @event, "direction:".$dir{(hex($stat)>>4)&0x02};
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
	#Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
	#AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if(($mTp eq "10" && $p =~ m/^06/) ||
	   ($mTp eq "02" && $p =~ m/^01/)) {
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
    if($mTp =~ m/^4/ && @mI > 1) { #Push Button event
      my ($recChn,$trigNo) = (hex($mI[0]),hex($mI[1]));# button number/event count
	  my $longPress = ($recChn & 0x40)?"long":"short";
	  my $recId = $src.sprintf("%02X",($recChn&0x3f));
	  foreach my $dChId (CUL_HM_getAssChnIds($dname)){# need to check all chan
	    next if (!$modules{CUL_HM}{defptr}{$dChId});
		my $dChNo = substr($dChId,6,2);
		my $dChName = CUL_HM_id2Name($dChId);

		if(($attr{$dChName}{peerIDs}?$attr{$dChName}{peerIDs}:"") =~m/$recId/){
		  my $dChHash = $defs{$dChName};
		  $dChHash->{helper}{trgLgRpt} = 0 
		        if (!defined($dChHash->{helper}{trgLgRpt}));
		  $dChHash->{helper}{trgLgRpt} +=1;
		  my $trgLgRpt = $dChHash->{helper}{trgLgRpt};
		  
		  my $state  = ReadingsVal($dChName,"virtActState","OFF");
		  my $tNoOld = ReadingsVal($dChName,"virtActTrigNo","0");
		  $state = ($state eq "OFF")?"ON":"OFF" if ($trigNo ne $tNoOld);
		  if (hex($mFlg)&0x20){
		    $longPress .= "_Release";
			$dChHash->{helper}{trgLgRpt}=0;
            push @ack,$dhash,$mNo."8002".$dst.$src.'01'.$dChNo.
				  (($state eq "ON")?"C8":"00")."00";
		  }
	      push @entities,
		  CUL_HM_UpdtReadBulk($dChHash,1,"state:".$state,
		                           "virtActState:".$state,
			                       "virtActTrigger:".CUL_HM_id2Name($recId),
						           "virtActTrigType:".$longPress,
						           "virtActTrigRpt:".$trgLgRpt,
						           "virtActTrigNo:".$trigNo	);
        }	
	  }
	}
	elsif($mTp eq "58" && $p =~ m/^(..)(..)/) {# climate event
      my ($d1,$vp) =($1,hex($2)); # adjust_command[0..4] adj_data[0..250]
      $vp = int($vp/2.56+0.5);    # valve position in %
	  my $chnHash = $modules{CUL_HM}{defptr}{$dst."01"};
	  push @entities, CUL_HM_UpdtReadBulk($chnHash,1,"ValvePosition:$vp %",
	                                                 "ValveAdjCmd:".$d1);
      push @ack,$chnHash,$mNo."8002".$dst.$src.'0101'.
	                     sprintf("%02X",$vp*2)."0000";
	}
	elsif($mTp eq "02"){
	  if ($dhash->{helper}{prt}{rspWait}{mNo}             && 
	      $dhash->{helper}{prt}{rspWait}{mNo} eq $mNo ){
	    #ack we waited for - stop Waiting
	    CUL_HM_respPendRm($dhash);
	  } 
	}
    push @ack,$dhash,$mNo."8002".$dst.$src."00" if (hex($mFlg)&0x20 && (!@ack));
  }
  elsif($id eq $dst){# if fhem is destination check if we need to react
    if($mTp =~ m/^4./ && $p =~ m/^(..)/ &&  #Push Button event
	   (hex($mFlg)&0x20)){ 	#response required Flag
      my ($recChn) = (hex($1));# button number/event count
	            # fhem CUL shall ack a button press
      push @ack,$shash,$mNo."8002".$dst.$src."0101".(($recChn&1)?"C8":"00")."00";
	}
  }
  
  #------------ send default ACK if not applicable------------------
  #    ack if we are destination, anyone did accept the message (@event)
  #        parser did not supress 
  push @ack,$shash, $mNo."8002".$id.$src."00"
      if(   ($id eq $dst) 	  #are we adressee 
	     && (hex($mFlg)&0x20) #response required Flag
		 && @event  		  #only ack if we identified it
		 && (!@ack)		      #sender requested ACK
		 );  	

  if (@ack)	{# send acks and store for repeat
    my $sRptHash = $modules{CUL_HM}{defptr}{$src}{helper}{rpt};
    $sRptHash->{IO}  = $ioName;
    $sRptHash->{flg} = substr($msg,5,1);
    $sRptHash->{ack} = \@ack;
	$sRptHash->{ts}  = gettimeofday();
	my $i=0;
    CUL_HM_SndCmd($ack[$i++],$ack[$i++])while ($i<@ack);
    Log GetLogLevel($name,6), "CUL_HM $name sent ACK:".(int(@ack));
  }

  CUL_HM_ProcessCmdStack($shash) if ($respRemoved); # cont if complete
  #------------ process events ------------------
  push @event, "noReceiver:src:$src ".$mFlg.$mTp." $p" if(!@event && !@entities);
  CUL_HM_UpdtReadBulk($shash,1,@event); #events to the channel
  $defs{$shash->{NAME}}{EVENTS}++;  # count events for channel
  push @entities,$shash->{NAME};
  foreach (CUL_HM_noDup(@entities)){
    DoTrigger($_, undef) if ($_ ne $name);
  }
  
  return $name ;
}
sub CUL_HM_parseCommon(@){#####################################################
  # parsing commands that are device independent
  my ($mNo,$mFlg,$mTp,$src,$dst,$p,$st,$md) = @_;
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  return "" if(!$shash->{DEF});# this should be from ourself 
  my $ret = "";
  my $pendType = $shash->{helper}{prt}{rspWait}{Pending}? 
                           $shash->{helper}{prt}{rspWait}{Pending}:"";
  #------------ parse message flag for start processing command Stack
  # TC wakes up with 8270, not with A258
  # VD wakes up with 8202 
  #                  9610

  if( ((hex($mFlg) & 0xA2) == 0x82) &&
	  (CUL_HM_getRxType($shash) & 0x08)){ #wakeup and process stack
	CUL_HM_appFromQ($shash->{NAME},"wu");# stack cmds if waiting
	if ($shash->{cmdStack}){
      CUL_HM_SndCmd($shash, '++A112'.CUL_HM_IOid($shash).$src);
	  CUL_HM_ProcessCmdStack($shash);
	}
  }
  my $repeat;
  if   ($mTp eq "02"){# Ack/Nack ###########################

	#see if the channel is defined separate - otherwise go for chief
    my $subType = substr($p,0,2);  
	my $reply;
	my $success;

	if ($shash->{helper}{prt}{rspWait}{wakeup}){
	  if ($shash->{helper}{prt}{rspWait}{mNo} eq $mNo &&
		  $subType eq "00"		){
		if ($shash->{helper}{prt}{awake} && $shash->{helper}{prt}{awake}==4){#re-wakeup
		  delete $shash->{helper}{prt}{rspWait};#clear wakeup values
  		  $shash->{helper}{prt}{rspWait}{$_} = $shash->{helper}{prt}{rspWaitSec}{$_} 
		          foreach (keys%{$shash->{helper}{prt}{rspWaitSec}});	#back to original message		
		  delete $shash->{helper}{prt}{rspWaitSec};
		  IOWrite($shash, "", $shash->{helper}{prt}{rspWait}{cmd});     # and send
		  #General set timer
		  return "done"
		}
		$shash->{protCondBurst} = "on" if ($shash->{protCondBurst} !~ m/forced/);
		$shash->{helper}{prt}{awake}=2;#awake
	  }
	  else{
		$shash->{protCondBurst} = "off" if ($shash->{protCondBurst} !~ m/forced/);
		$shash->{helper}{prt}{awake}=3;#reject
		return "done";
	  }
	}
	
	if   ($subType =~ m/^8/){#NACK
	  $success = "no";
	  CUL_HM_eventP($shash,"Nack");
	  $reply = "NACK"; 
	}
	elsif($subType eq "01"){ #ACKinfo#################
      $success = "yes";
	  my $rssi = substr($p,8,2);# --calculate RSSI
      CUL_HM_storeRssi($shash->{NAME},
                        ($dhash?$dhash->{NAME}:$shash->{IODev}{NAME}),
						(-1)*(hex($rssi)))
			if ($rssi && $rssi ne '00' && $rssi ne'80');
	  $reply = "ACKStatus"; 
	  if ($shash->{helper}{tmdOn}){
		if (not hex(substr($p,6,2))&0x40){# not timedOn, we have to repeat
          my ($pre,$nbr,$msg) = unpack 'A4A2A*',$shash->{helper}{prt}{rspWait}{cmd};
          $shash->{helper}{prt}{rspWait}{cmd} = sprintf("%s%02X%s",
		                                            $pre,hex($nbr)+1,$msg);
	      CUL_HM_eventP($shash,"TimedOn");
	      $success = "no";
		  $repeat = 1;
	      $reply = "NACK"; 
		}
	  }
	}
	elsif($subType eq "04"){ #ACK-AES, interim########
      #$success = ""; #result not final, another response should come
	  $reply = "done"; 
	}
	else{	                 #ACK
	  $success = "yes";
	  $reply = "ACK"; 
	}

    if (   $shash->{helper}{prt}{mmcS} 
		&& $shash->{helper}{prt}{mmcS} == 3){
	  if ($success eq 'yes'){
		delete $shash->{helper}{prt}{mmcA};
		delete $shash->{helper}{prt}{mmcS};
	  }
	};
	
	if($success){#do we have a final ack?
      #mark timing on the channel, not the device
      my $chn = sprintf("%02X",hex(substr($p,2,2))&0x3f);
      my $chnhash = $modules{CUL_HM}{defptr}{$chn?$src.$chn:$src};
      $chnhash = $shash if(!$chnhash);
	  readingsSingleUpdate($chnhash,"CommandAccepted",$success,0);
      CUL_HM_ProcessCmdStack($shash) if(CUL_HM_IOid($shash) eq $dst);
	}
	$ret = $reply;
  }
  elsif($mTp eq "00"){######################################
    my $iohash = $shash->{IODev};
    my $id = CUL_HM_Id($iohash);
    CUL_HM_infoUpdtDevData($shash->{NAME}, $shash,$p)  
	           if (!$modules{CUL_HM}{helper}{hmManualOper}#no autoaction
			       ||$iohash->{hmPair} 
                   ||$iohash->{hmPairSerial} );  	

    if(  $dst =~ m /(000000|$id)/ #--- see if we need to pair
       &&($iohash->{hmPair} 
          ||(    $iohash->{hmPairSerial} 
		      && $iohash->{hmPairSerial} eq $attr{$shash->{NAME}}{serialNr}))
	   &&( $mFlg.$mTp ne "0400") ) {
	  #-- try to pair 
      Log GetLogLevel($shash->{NAME},3), "CUL_HM pair: $shash->{NAME} "
	                       ."$attr{$shash->{NAME}}{subType}, "
	                       ."model $attr{$shash->{NAME}}{model} "
						   ."serialNr $attr{$shash->{NAME}}{serialNr}";
	  delete $iohash->{hmPairSerial};
	  CUL_HM_respPendRm($shash); # remove all pending messages
	  delete $shash->{cmdStack};
	  delete $shash->{EVENTS};
	  delete $shash->{helper}{prt}{rspWait};
	  delete $shash->{helper}{prt}{rspWaitSec};
	  
      my ($idstr, $s) = ($id, 0xA);
      $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;
      CUL_HM_pushConfig($shash, $id, $src,0,0,0,0, "0201$idstr");
      CUL_HM_ProcessCmdStack($shash); # start processing immediately
	}
	elsif(CUL_HM_getRxType($shash) & 0x04){# nothing to pair - maybe send config
	  CUL_HM_appFromQ($shash->{NAME},"cf");   # stack cmds if waiting
	  if (hex($mFlg)&0x20){CUL_HM_SndCmd($shash,$mNo."8002".$id.$src."00");}
	  else{ 	           CUL_HM_ProcessCmdStack($shash);} ;#config
	}
	$ret = "done";
  } 
  elsif($mTp eq "10"){######################################
    my $subType = substr($p,0,2);
	if   ($subType eq "00"){ #SerialRead====================================
	  $attr{$shash->{NAME}}{serialNr} = pack("H*",substr($p,2,20));
	  if ($pendType eq "SerialRead"){
        CUL_HM_respPendRm($shash);	  
	  }
	  $ret = "done";
	}
	elsif($subType eq "01"){ #storePeerList=================================
	  if ($pendType eq "PeerList"){
		my $chn = $shash->{helper}{prt}{rspWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$src.$chn}; 
		$chnhash = $shash if (!$chnhash);
	    my $chnName = $chnhash->{NAME};
	    my (undef,@peers) = unpack 'A2(A8)*',$p;
        $_ = '00000000' foreach (grep /^000000/,@peers);#correct bad term(6 chars) from rain sens)
	    $chnhash->{helper}{peerIDsRaw}.= ",".join",",@peers;

    	CUL_HM_ID2PeerList ($chnName,$_,1) foreach (@peers);
		if (grep /00000000/,@peers) {# last entry, peerList is complete
		  # check for request to get List3 data
		  my $reqPeer = $chnhash->{helper}{getCfgList};
		  if ($reqPeer){
		    my $flag = CUL_HM_getFlag($shash);
		    my $id = CUL_HM_IOid($shash);
		    my $listNo = "0".$chnhash->{helper}{getCfgListNo};
		    my @peerID = split(",",($attr{$chnName}{peerIDs}?
			                        $attr{$chnName}{peerIDs}:""));
		    foreach my $peer (grep (!/00000000/,@peerID)){
			  $peer .="01" if (length($peer) == 6); # add the default
			  if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
				CUL_HM_PushCmdStack($shash,sprintf("++%s01%s%s%s04%s%s",
						$flag,$id,$src,$chn,$peer,$listNo));# List3 or 4 
			  }
			}
		  }
          CUL_HM_respPendRm($shash);	  
		  delete $chnhash->{helper}{getCfgList};
		  delete $chnhash->{helper}{getCfgListNo};
          CUL_HM_rmOldRegs($chnName);	  
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		}
		$ret = "done";
	  }
	}
	elsif($subType eq "02" ||$subType eq "03"){ #ParamResp==================
	  if ($pendType eq "RegisterRead"){
		my $chnSrc = $src.$shash->{helper}{prt}{rspWait}{forChn};
		my $chnHash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnHash = $shash if (!$chnHash);
		my $chnName = $chnHash->{NAME};
		my ($format,$data) = ($1,$2) if ($p =~ m/^(..)(.*)/);
		my $list = $shash->{helper}{prt}{rspWait}{forList};
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

		my $peer = $shash->{helper}{prt}{rspWait}{forPeer};
		my $regLNp = "RegL_$list:$peer";# pure, no expert
		my $regLN = ((CUL_HM_getAttrInt($chnName,"expert") == 2)?"":".").$regLNp;
		readingsSingleUpdate($chnHash,$regLN,
		             ReadingsVal($chnName,$regLN,"")." ".$data,0);
		if ($data =~m/00:00$/){ # this was the last message in the block
		  if($list eq "00"){
			my $name = CUL_HM_id2Name($src);
			readingsSingleUpdate($shash,"PairedTo",
		                    CUL_HM_getRegFromStore($name,"pairCentral",0,""),0);
		  }		  
		  CUL_HM_respPendRm($shash);
		  delete $chnHash->{helper}{shadowReg}{$regLNp};   #rm shadow
		  # peer Channel name from/for user entry. <IDorName> <deviceID> <ioID>
		  CUL_HM_updtRegDisp($chnHash,$list,
		        CUL_HM_peerChId($peer,
						substr($chnHash->{DEF},0,6),"00000000"));
		  $ret = "done;entities:$chnName";
		}
		else{
		  CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
		  $ret = "done";
		}
	  }
	  else{#response without request - discard
		$ret = "done";
	  }
	}  
	elsif($subType eq "04"){ #ParamChange===================================
	  my($chn,$peerID,$list,$data) = ($1,$2,$3,$4) if($p =~ m/^04(..)(........)(..)(.*)/);
	  my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
	  $chnHash = $shash if(!$chnHash); # will add param to dev if no chan
	  my $regLNp = "RegL_$list:".CUL_HM_id2Name($peerID);
      $regLNp =~ s/broadcast//;
	  $regLNp =~ s/ /_/g; #remove blanks
	  my $regLN = ((CUL_HM_getAttrInt($chnHash->{NAME},"expert") == 2)?"":".").$regLNp;

	  $data =~ s/(..)(..)/ $1:$2/g;	  
	  
	  my $lN = ReadingsVal($chnHash->{NAME},$regLN,"");
	  my $shdwReg = $chnHash->{helper}{shadowReg}{$regLNp};
	  foreach my $entry(split(' ',$data)){
	    my ($a,$d) = split(":",$entry);	
        last if ($a eq "00");		
		if ($lN =~m/$a:/){$lN =~ s/$a:../$a:$d/;
		}else{  		  $lN .= " ".$entry;}
		$shdwReg =~ s/ $a:..// if ($shdwReg);# confirmed: remove from shadow
	  }
	  $chnHash->{helper}{shadowReg}{$regLNp} = $shdwReg;
	  $lN = join(' ',sort(split(' ',$lN)));# re-order
	  if ($lN =~ s/00:00//){$lN .= " 00:00"};
      readingsSingleUpdate($chnHash,$regLN,$lN,0);
	  CUL_HM_updtRegDisp($chnHash,$list,$peerID);
	  $ret= "parsed";
	}  
	elsif($subType eq "06"){ #reply to status request=======================
	  my $rssi = substr($p,8,2);# --calculate RSSI
      CUL_HM_storeRssi($shash->{NAME},
                       ($dhash?$dhash->{NAME}:$shash->{IODev}{NAME}),
					   (-1)*(hex($rssi)))
			if ($rssi && $rssi ne '00' && $rssi ne'80');
	  @{$modules{CUL_HM}{helper}{qReqStat}} = grep { $_ ne $shash->{NAME} }
                                       @{$modules{CUL_HM}{helper}{qReqStat}};
      if ($pendType eq "StatusReq"){#it is the answer to our request
		my $chnSrc = $src.$shash->{helper}{prt}{rspWait}{forChn};
		my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc}; 
		$chnhash = $shash if (!$chnhash);
		CUL_HM_respPendRm($shash);
		$ret = "STATresp";
	  }
	  else{
		my ($chn) = ($1) if($p =~ m/^..(..)/);
		if ($chn eq "00"){# this is power on
		  my $name = $shash->{NAME};
	      CUL_HM_qStateUpdatIfEnab($name);
		  CUL_HM_qAutoRead($name,2);
		  $ret = "powerOn" ;# check dst eq "000000" as well?
		}
	  }
	}
  }
  elsif($mTp =~ m /^4[01]/){ #someone is triggered##########
	CUL_HM_qStateUpdatIfEnab($dst)if (hex($mFlg) & 0x20 && $dhash);
	my $chn = hex(substr($p,0,2));
	my $long = ($chn & 0x40)?"long":"short";
	$chn = $chn & 0x3f;
    my $cName = CUL_HM_id2Hash($src.sprintf("%02X",$chn));
	$cName = $cName->{NAME};
	my $level = "-";
    
	if (length($p)>5){
	  my $l = substr($p,4,2);
	  if    ($lvlStr{md}{$md} && $lvlStr{md}{$md}{$l}){$level = $lvlStr{md}{$md}{$l}}
	  elsif ($lvlStr{st}{$st} && $lvlStr{st}{$st}{$l}){$level = $lvlStr{st}{$st}{$l}}
	  else                                            {$level = hex($l)};
	}
	elsif($mTp eq "40"){
	  $level = $long;
	}

	my @peers = split(",",AttrVal($cName,"peerIDs",""));
	my @entities;
	foreach my $peer (@peers){
	  my $pName = CUL_HM_id2Name($peer);
	  $pName = CUL_HM_id2Name(substr($peer,0,6)) if (!$defs{$pName});
	  next if (!$defs{$pName});#||substr($peer,0,6) ne $dst
	  push @entities,CUL_HM_UpdtReadBulk($defs{$pName},1
	                      ,"trig_$cName:$level"
	                      ,"trigLast:$cName ".(($level ne "-")?":$level":""));
	}

	return "entities:".join(",",@entities);
  }
  elsif($mTp eq "70"){ #Time to trigger TC##################
    #send wakeup and process command stack
#  	CUL_HM_SndCmd($shash, '++A112'.CUL_HM_IOid($shash).$src);
#	CUL_HM_ProcessCmdStack($shash);
  }

  if ($shash->{helper}{prt}{rspWait}{mNo}             && 
	  $shash->{helper}{prt}{rspWait}{mNo} eq $mNo     &&
	  !$repeat){
	#response we waited for - stop Waiting
	CUL_HM_respPendRm($shash);
  }

  return $ret;
}
sub CUL_HM_queueUpdtCfg($){
  my $name = shift;
  if ($modules{CUL_HM}{helper}{hmManualOper}){ # no update when manual operation
    delete $modules{CUL_HM}{helper}{updtCfgLst};
	return;
  }
  my @arr;
  if ($modules{CUL_HM}{helper}{updtCfgLst}){
    @arr = CUL_HM_noDup((@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name));
  }
  else{
    push @arr,$name;
  }
  $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
  RemoveInternalTimer("updateConfig");
  InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
}

#+++++++++++++++++ get command+++++++++++++++++++++++++++++++++++++++++++++++++
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
  return "" if (!$dst);

  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);
  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;

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
	return $hash->{$a[2]}                   if ($hash->{$a[2]});
	return $hash->{helper}{$a[2]}           if ($hash->{helper}{$a[2]} && ref($hash->{helper}{$a[2]}) ne "HASH");
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
	  if    ($md eq "HM-CC-TC"     && $chn eq "02"){$addInfo = CUL_HM_TCtempReadings($hash)}
      elsif ($md =~ m/HM-CC-RT-DN/ && $chn eq "04"){$addInfo = CUL_HM_RTtempReadings($hash)}
      elsif ($md eq "HM-PB-4DIS-WM")               {$addInfo = CUL_HM_4DisText($hash)}
	  elsif ($md eq "HM-Sys-sRP-Pl")               {$addInfo = CUL_HM_repReadings($hash)}

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
	  my ($min,$max) = ($reg->{min},"to ".$reg->{max});
	  if (defined($reg->{lit})){
	    $help .= " options:".join(",",keys%{$reg->{lit}});
	    $min = "";
		$max = "literal";
	  }
	  push @rI,sprintf("%4d: %-16s | %3s %-14s | %8s | %s\n",
			  $reg->{l},$regName,$min,$max.$reg->{u},
              ((($reg->{l} == 3)||($reg->{l} == 4))?"required":""),
			  $help)
	        if (($roleD && $reg->{l} == 0)||
			    ($roleC && $reg->{l} != 0));
	}
	
    my $info = sprintf("list: %16s | %-18s | %-8s | %s\n",
	                 "register","range","peer","description");
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
	    print aSave "\n# Peer Names:"
		            .($defs{$name}{peerList}?$defs{$name}{peerList}:"");
		$timestamps .= "\n#        "
					  .($defs{$eName}{peerList}?$defs{$eName}{peerList}:"")
					  ." :peerList";
	    print aSave "\nset ".$eName." peerBulk ".$pIds;
	  }
	  my $ehash = $defs{$eName};
	  foreach my $read (sort grep(/^[\.]?RegL_/,keys %{$ehash->{READINGS}})){
	    print aSave "\nset ".$eName." regBulk ".$read." "
		      .ReadingsVal($eName,$read,"");
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

#+++++++++++++++++ set command+++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_Set($@) {
  my ($hash, @a) = @_;
  my $act = join(" ", @a[1..$#a]);
  my $ret;
  return "no set value specified" if(@a < 2);
  my $name    = $hash->{NAME};
  return "device ignored due to attr 'ignore'" 
        if (CUL_HM_getAttrInt($name,"ignore"));
  my $devName = $hash->{device}?$hash->{device}:$name;
  my $st      = AttrVal($devName, "subType", "");
  my $md      = AttrVal($devName, "model"  , "");
  my $flag = CUL_HM_getFlag($hash); #set burst flag
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $isChannel = (length($dst) == 8)?"true":"";
  my $chn = ($isChannel)?substr($dst,6,2):"01";
  $dst = substr($dst,0,6);
  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;
  my $mdCh = $md.($isChannel?$chn:"00"); # chan specific commands?
  my $id = CUL_HM_IOid($hash);
  my $h = $culHmGlobalSets{$cmd}      if(                $st ne "virtual");
  $h = $culHmGlobalSetsVrtDev{$cmd}   if(!defined($h) &&($st eq "virtual"||!$st)  && $roleD);
  $h = $culHmGlobalSetsDevice{$cmd}   if(!defined($h) && $st ne "virtual"         && $roleD);
  $h = $culHmSubTypeDevSets{$st}{$cmd}if(!defined($h) && $st ne "virtual"         && $roleD);
  $h = $culHmGlobalSetsChn{$cmd}      if(!defined($h) && $st ne "virtual"         && $roleC);
  $h = $culHmSubTypeSets{$st}{$cmd}   if(!defined($h) && $culHmSubTypeSets{$st}   && $roleC);
  $h = $culHmModelSets{$md}{$cmd}     if(!defined($h) && $culHmModelSets{$md}  );
  $h = $culHmChanSets{$md."00"}{$cmd} if(!defined($h) && $culHmChanSets{$md."00"} && $roleD);
  $h = $culHmChanSets{$md.$chn}{$cmd} if(!defined($h) && $culHmChanSets{$md.$chn} && $roleC);

  my @h;
  @h = split(" ", $h) if($h);
  my @postCmds=(); #Commands to be appended after regSet (ugly...)
  
  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
	splice @a, 1, 0,"pct";#insert the actual command
  } 
  elsif(!defined($h)) {
    my @arr1 = ();
	
	if( $st ne "virtual")                  {foreach(keys %culHmGlobalSets            ){push @arr1,"$_:$culHmGlobalSets{$_}"            }};
    if(($st eq "virtual"||!$st)  && $roleD){foreach(keys %culHmGlobalSetsVrtDev      ){push @arr1,"$_:$culHmGlobalSetsVrtDev{$_}"      }};
    if( $st ne "virtual"         && $roleD){foreach(keys %culHmGlobalSetsDevice      ){push @arr1,"$_:$culHmGlobalSetsDevice{$_}"      }};
    if( $st ne "virtual"         && $roleD){foreach(keys %{$culHmSubTypeDevSets{$st}}){push @arr1,"$_:${$culHmSubTypeDevSets{$st}}{$_}"}};
    if( $st ne "virtual"         && $roleC){foreach(keys %culHmGlobalSetsChn         ){push @arr1,"$_:$culHmGlobalSetsChn{$_}"         }};
    if( $culHmSubTypeSets{$st}   && $roleC){foreach(keys %{$culHmSubTypeSets{$st}}   ){push @arr1,"$_:${$culHmSubTypeSets{$st}}{$_}"   }};
    if( $culHmModelSets{$md})              {foreach(keys %{$culHmModelSets{$md}}     ){push @arr1,"$_:${$culHmModelSets{$md}}{$_}"     }};
    if( $culHmChanSets{$md."00"} && $roleD){foreach(keys %{$culHmChanSets{$md."00"}} ){push @arr1,"$_:".${$culHmChanSets{$md."00"}}{$_}}};
    if( $culHmChanSets{$md.$chn} && $roleC){foreach(keys %{$culHmChanSets{$md.$chn}} ){push @arr1,"$_:".${$culHmChanSets{$md.$chn}}{$_}}};
	@arr1 = CUL_HM_noDup(@arr1);
	foreach(@arr1){
	  my ($cmd,$val) = split(":",$_,2);
	  if (!$val               || 
	      $val !~ m/^\[.*\]$/ ||
		  $val =~ m/\[.*\[/   ||
		  $val =~ m/(\<|\>)]/  
		  ){
	    $_ = $cmd;
	  }
	  else{
	    $val =~ s/(\[|\])//g;
		my @vArr = split('\|',$val);
		foreach (@vArr){
		  if ($_ =~ m/(.*)\.\.(.*)/ ){
		    my @list = map { ($_.".0", $_+0.5) } ($1..$2);
			pop @list;
			$_ = join(",",@list);
		  }
		}
	    $_ = "$cmd:".join(",",@vArr);
	  }
	}
    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @arr1); 
    $usg =~ s/ pct/ pct:slider,0,1,100/;
    $usg =~ s/ virtual/ virtual:slider,1,1,40/;

    return $usg;
  } 
  elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";
  } 
  elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";
  }

  #convert 'old' commands to current methodes like regSet and regBulk...
  # Unify the interface
  if(   $cmd eq "sign"){
	splice @a,1,0,"regSet";# make hash,regSet,reg,value 
  }
  elsif($cmd eq "unpair"){
	splice @a,1,3, ("regSet","pairCentral","000000");
  }
  elsif($cmd eq "ilum") { ################################################# reg
	return "$a[2] not specified. choose 0-15 for brightness"  if ($a[2]>15);
	return "$a[3] not specified. choose 0-127 for duration"   if ($a[3]>127);
	return "unsupported for channel, use $devName"            if (!$roleD);
	splice @a,1,3, ("regBulk","RegL_00:",sprintf("04:%02X",$a[2]),sprintf("08:%02X",$a[3]*2));
  } 
  elsif($cmd eq "text") { ################################################# reg
    my ($bn,$l1, $l2) = ($chn,$a[2],$a[3]); # Create CONFIG_WRITE_INDEX string
	if (!$roleC){# if used on device. 
      return "$a[2] is not a button number" if($a[2] !~ m/^\d$/ || $a[2] < 1);
      return "$a[3] is not on or off" if($a[3] !~ m/^(on|off)$/);
      $bn = $a[2]*2-($a[3] eq "on" ? 0 : 1);
	  ($l1, $l2) = ($a[4],$a[5]);
	}
	else{
	  return "to many parameter. Try set $a[0] text $a[2] $a[3]" if($a[4]);
	}

    my $s = 54;
    $l1 = substr($l1."\x00", 0, 13);
    $l1 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;

    $s = 70;
    $l2 = substr($l2."\x00", 0, 13);
    $l2 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;

	@a = ($a[0],"regBulk","RegL_01:",split(" ",$l1.$l2));
  }
  elsif($cmd =~ m /(displayMode|displayTemp|displayTempUnit|controlMode)/) {
    if ($md eq "HM-CC-TC"){#controlMode different for RT
	  splice @a,1,3, ("regSet",$a[1],$a[2]);
	  push @postCmds,"++803F$id${dst}0204".sprintf("%02X",CUL_HM_secSince2000());
	}
  }
  elsif($cmd eq "partyMode") { ################################################
	my ($eH,$eM,$days,$prep) = ("","","","");
    if ($a[2] =~ m/^(prep|exec)$/){
	  $prep = $a[2];
	  splice  @a,2,1;#remove prep 
	}
	$days = $a[3];
	($eH,$eM)  = split(':',$a[2]); 

	return "$eM illegal - use 00 or 30 minutes only"        if ($eM !~ m/^(00|30)$/);
	return "$eH illegal - hour must be between 0 and 23"    if ($eH < 0 || $eH > 23);
	return "$days illegal - days must be between 0 and 200" if ($days < 0 || $days > 200);
	$eH += 128 if ($eM eq "30");
	my $cHash = CUL_HM_id2Hash($dst."02");
	$cHash->{helper}{partyReg} = sprintf("61%02X62%02X0000",$eH,$days);
	$cHash->{helper}{partyReg} =~ s/(..)(..)/ $1:$2/g;
	if ($cHash->{READINGS}{"RegL_06:"}){#remove old settings
	  $cHash->{READINGS}{"RegL_06:"}{VAL} =~ s/ 61:.*//;
	  $cHash->{READINGS}{"RegL_06:"}{VAL} =~ s/ 00:00//;
	  $cHash->{READINGS}{"RegL_06:"}{VAL} .= $cHash->{helper}{partyReg};
	}
	else{
	  $cHash->{READINGS}{"RegL_06:"}{VAL} = $cHash->{helper}{partyReg};
	}
	CUL_HM_pushConfig($hash,$id,$dst,2,"000000","00",6,
	                  sprintf("61%02X62%02X",$eH,$days),$prep);
    splice @a,1,3, ("regSet","controlMode","party");
    splice @a,2,0, ($prep) if ($prep);
	push @postCmds,"++803F$id${dst}0204".sprintf("%02X",CUL_HM_secSince2000());
  } 

  $cmd = $a[1];# get converted command
  
     #if chn cmd is executed on device but refers to a channel?
  my $chnHash = (!$isChannel && $modules{CUL_HM}{defptr}{$dst."01"})?
                 $modules{CUL_HM}{defptr}{$dst."01"}:$hash;
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);

  if   ($cmd eq "raw") {  #####################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
	$state = "";
    foreach (@a[2..$#a]) {
	  CUL_HM_PushCmdStack($hash, $_);
    }
  } 
  elsif($cmd eq "clear") { ####################################################
    my (undef,undef,$sect) = @a;
	if   ($sect eq "readings"){
	  my @cH = ($hash);
	  push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,keys %{$hash});

	  delete $_->{READINGS}foreach (@cH);
	}
	elsif($sect eq "register"){
	  my @cH = ($hash);
	  push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,keys %{$hash});

	  foreach my $h(@cH){
	    delete $h->{READINGS}{$_}
		     foreach (grep /^(\.?)(R-|RegL)/,keys %{$h->{READINGS}});
	  }
	}
	elsif($sect eq "msgEvents"){
	  return if (!$hash->{IODev}{NAME});
	  CUL_HM_respPendRm($hash);		  

	  $hash->{helper}{prt}{bErr}=0;
	  delete $hash->{cmdStack};
	  delete $hash->{EVENTS};
	  delete $hash->{helper}{prt}{rspWait};
	  delete $hash->{helper}{prt}{rspWaitSec};
	  delete $hash->{helper}{prt}{mmcA};
	  delete $hash->{helper}{prt}{mmcS};
	  #rescue "protLastRcv" for action detector. 
	  my $protLastRcv = $hash->{protLastRcv} if ($hash->{protLastRcv});
      delete ($hash->{$_}) foreach (grep(/^prot/,keys %{$hash}));
	  $hash->{protLastRcv} = $protLastRcv if ($protLastRcv);
	  if ($modules{CUL_HM}{$hash->{IODev}{NAME}} && 
	      $modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}){
		@{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}} = 
		      grep !/$name/,@{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}};
	  }
	  CUL_HM_unQEntity($name,"qReqConf");
	  CUL_HM_unQEntity($name,"qReqStat");
	  CUL_HM_protState($hash,"Info_Cleared");
	}
	elsif($sect eq "rssi"){
	  delete $defs{$name}{helper}{rssi};
	  delete ($hash->{$_}) foreach (grep(/^rssi/,keys %{$hash}))
	}
	else{
	  return "unknown section. User readings, msgEvents or rssi";
	}
	$state = "";
  } 
  elsif($cmd eq "reset") { ####################################################
	CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  } 
  elsif($cmd eq "burstXmit") { ################################################
	$hash->{helper}{prt}{wakeup}=1;# start wakeup
    CUL_HM_SndCmd($hash,"++B112$id$dst");
  } 
  elsif($cmd eq "pair") { #####################################################
	$state = "";
    my $serialNr = AttrVal($name, "serialNr", undef);
    return "serialNr is not set" if(!$serialNr);
    CUL_HM_PushCmdStack($hash,"++A401".$id."000000010A".uc( unpack("H*",$serialNr)));
    $hash->{hmPairSerial} = $serialNr;
  } 
  elsif($cmd eq "statusRequest") { ############################################
    my @chnIdList = CUL_HM_getAssChnIds($name);
    foreach my $channel (@chnIdList){
	  my $chnNo = substr($channel,6,2);
	  CUL_HM_PushCmdStack($hash,"++".$flag.'01'.$id.$dst.$chnNo.'0E');
    }
	$state = "";
  } 
  elsif($cmd eq "getSerial") { ################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'0009');
	$state = "";
  } 
  elsif($cmd eq "getConfig") { ################################################
    CUL_HM_unQEntity($name,"qReqConf");
	CUL_HM_getConfig($hash);
	$state = "";
  } 
  elsif($cmd eq "peerBulk") { #################################################
	$state = "";
	my $pL = $a[2];
	return "unknown action: $a[3] - use set or unset" 
	         if ($a[3] && $a[3] !~ m/^(set|unset)/);
	my $set = ($a[3] eq "unset")?"02":"01";
	foreach my $peer (grep(!/^self/,split(',',$pL))){
	  my $pID = CUL_HM_peerChId($peer,$dst,$id);
	  return "unknown peer".$peer if (length($pID) != 8);# peer only to channel
	  my $pCh1 = substr($pID,6,2);
	  my $pCh2 = $pCh1;
      if(($culHmSubTypeSets{$st}   &&$culHmSubTypeSets{$st}{peerChan}  )||
         ($culHmModelSets{$md}     &&$culHmModelSets{$md}{peerChan}    )||
         ($culHmChanSets{$md.$chn} &&$culHmChanSets{$md.$chn}{peerChan})  ){
	    $pCh2 = "00";                        # button behavior
      }
	  CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chn.$set.
	                      substr($pID,0,6).$pCh1.$pCh2);
	}
	CUL_HM_qAutoRead($name,3);
  } 
  elsif($cmd =~ m/^(regBulk|getRegRaw)$/) { ############################### reg
    my ($list,$addr,$data,$peerID);
	$state = "";
	if ($cmd eq "regBulk"){
	  $list = $a[2];
	  $list =~ s/[\.]?RegL_//;
	  ($list,$peerID) = split(":",$list);
	  return "unknown list Number:".$list if(hex($list)>6);
	}
    elsif ($cmd eq "getRegRaw"){
	  ($list,$peerID) = ($a[2],$a[3]);
	  return "Enter valid List0-6" if ($list !~ m/^List([0-6])$/);
	  $list ='0'.$1;
	}
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
	  $chn = 0 if ($list == 0);
      CUL_HM_pushConfig($hash,$id,$dst,hex($chn),$peerID,$peerChn,$list,$adList);
	}
  } 
  elsif($cmd eq "regSet") { ############################################### reg
    #set <name> regSet [prep] <regName>  <value> [<peerChn>] 
	#prep is internal use only. It allowes to prepare shadowReg only but supress
	#writing. Application necessarily needs to execute writing subsequent.
	my $prep = "";
    if ($a[2] =~ m/^(prep|exec)$/){
	  $prep = $a[2];
	  splice  @a,2,1;#remove prep 
	}

	my (undef,undef,$regName,$data,$peerChnIn) = @a;
	$state = "";
    if (!$culHmRegType{$st}{$regName}      && 
	    !$culHmRegGeneral{$regName}        &&
	    !$culHmRegModel{$md}{$regName}     && 
	    !$culHmRegChan{$md.$chn}{$regName} 	){
      my @regArr = keys %culHmRegGeneral ;
	  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st});
	  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md});
	  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn});
	  return "$regName failed: supported register are ".join(" ",sort @regArr);
	}
	   
    my $reg  = $culHmRegDefine{$regName};
	return $st." - ".$regName            # give some help
	       .($reg->{lit}? " literal:".join(",",keys%{$reg->{lit}})." "
	                    : " range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
			)
		   .(($reg->{l} == 3)?" peer required":"")." : ".$reg->{t}."\n"
		          if ($data eq "?");
	return "value:".$data." out of range $reg->{min} to $reg->{max} for Reg \""
	       .$regName."\""
	        if (!($reg->{c} =~ m/^(lit|hex|min2time)$/)&&
			    ($data < $reg->{min} ||$data > $reg->{max})); # none number
    return"invalid value. use:". join(",",sort keys%{$reg->{lit}}) 
	        if ($reg->{c} eq 'lit' && !defined($reg->{lit}{$data}));
	
	$data *= $reg->{f} if($reg->{f});# obey factor befor possible conversion
	my $conversion = $reg->{c};
	if (!$conversion){;# do nothing
	}elsif($conversion eq "fltCvT"  ){$data = CUL_HM_fltCvT($data);
	}elsif($conversion eq "fltCvT60"){$data = CUL_HM_fltCvT60($data);
	}elsif($conversion eq "min2time"){$data = CUL_HM_time2min($data);
	}elsif($conversion eq "m10s3")   {$data = $data*10-3;
	}elsif($conversion eq "hex")     {$data = hex($data);
	}elsif($conversion eq "lit")     {$data = $reg->{lit}{$data};
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
	
    my ($lChn,$peerId,$peerChn) = ($chn,"000000","00");
	if (($list == 3) ||($list == 4)){ # peer is necessary for list 3/4
	  return "Peer not specified" if ($peerChnIn eq "");
	  $peerId  = CUL_HM_peerChId($peerChnIn,$dst,$id);	  
 	  $peerChn = ((length($peerId) == 8)?substr($peerId,6,2):"01");
      $peerId  = substr($peerId,0,6);
      return "Peer not valid" if (!$peerId);	  
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
	  my $curVal = CUL_HM_getRegFromStore($rName,$addr,$list,$peerId.$peerChn);
  	  return "cannot calculate value. Please issue set $name getConfig first" 
	             if ($curVal !~ m/^(set_|)(\d+)$/);
	  $curVal = $2; # we expect one byte in int, strap 'set_' possibly
	  $data = ($curVal & (~($mask<<$bit)))|($data<<$bit);
	  $addrData.=sprintf("%02X%02X",$addr,$data);
	}
	else{
	  for (my $cnt = 0;$cnt<int($reg->{s}+0.99);$cnt++){
	    $addrData.=sprintf("%02X",$addr+$cnt).substr($dataStr,$cnt*2,2);
	  }
	}

    $lChn = "00" if($list == 7);#face to send

	my $cHash = CUL_HM_id2Hash($dst.($lChn eq '00'?"":$lChn));
	$cHash = $hash if (!$cHash);
    CUL_HM_pushConfig($cHash,$id,$dst,$lChn,$peerId,hex($peerChn),$list
	                 ,$addrData,$prep);

    CUL_HM_PushCmdStack($hash,$_) foreach(@postCmds);#ugly commands after regSet
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
  elsif($cmd =~ m/^(on|off|toggle)$/) { #######################################
    my $lvl = ($cmd eq 'on')  ? 'C8':
	         (($cmd eq 'off') ? '00':(CUL_HM_getChnLvl($name) != 0 ?"00":"C8"));
    CUL_HM_PushCmdStack($hash,"++$flag"."11$id$dst"."02$chn$lvl".'0000');
	$hash = $chnHash; # report to channel if defined
  }
  elsif($cmd =~ m/^(on-for-timer|on-till)$/) { ################################
    my (undef,undef,$duration,$edate) = @a; #date prepared extention to entdate
    if ($cmd eq "on-till"){
	  # to be extended to handle end date as well
	  my ($eH,$eM,$eSec)  = split(':',$duration); 
	  return "please enter time informat hh:mm:ss" if (!$eSec);
	  $eSec += $eH*3600 + $eM*60;
	  my @lt = localtime;	  
	  my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
	  $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
	  $duration = $eSec - $ltSec;
    }
	return "please enter the duration in seconds" 
	      if (!defined $duration || $duration !~ m/^[+-]?\d+(\.\d+)?$/);
    my $tval = CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
	return "timer value to low" if ($tval eq "0000");
    CUL_HM_PushCmdStack($hash,"++$flag"."11$id$dst"."02$chn"."C80000$tval");
 	$hash = $chnHash; # report to channel if defined
  } 
  elsif($cmd eq "lock") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800100FF');	# LEVEL_SET
  }
  elsif($cmd eq "unlock") { ###################################################
  	my $tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800101'.$delay);# LEVEL_SET
  }
  elsif($cmd eq "open") { #####################################################
  	my $tval = (@a > 2) ? int($a[2]) : 0;
  	my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";	# RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'8001C8'.$delay);# OPEN
  }
  elsif($cmd eq "inhibit") { ##################################################
  	return "$a[2] is not on or off" if($a[2] !~ m/^(on|off)$/);
 	my $val = ($a[2] eq "on") ? "01" : "00";
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$val.$chn);	# SET_LOCK
  }
  elsif($cmd =~ m/^(up|down|pct)$/) { #########################################
	my ($lvl,$tval,$rval) = ($a[2],"","");
	if ($cmd ne "pct"){#dim [<changeValue>] ... [ontime] [ramptime]
	  $lvl = 10 if (!defined $a[2]); #set default step
	  $lvl = -1*$lvl if ($cmd eq "down");
	  $lvl += CUL_HM_getChnLvl($name);
	}
    $lvl = ($lvl > 100)?100:(($lvl < 0)?0:$lvl);
	if ($st eq "dimmer"){# at least blind cannot stand ramp time...
      $tval = $a[3]?CUL_HM_encodeTime16($a[3]):"FFFF";# onTime 0.05..85825945.6, 0=forever
      $rval = CUL_HM_encodeTime16((@a > 4)?$a[4]:2.5);# rampTime 0.0..85825945.6, 0=immediate
	}
    CUL_HM_PushCmdStack($hash,sprintf("++%s11%s%s02%s%02X%s%s",
	                                 $flag,$id,$dst,$chn,$lvl*2,$rval,$tval));
    readingsSingleUpdate($hash,"level","set_".$lvl,1);
	$state = "set_".$lvl;
  } 
  elsif($cmd eq "stop") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
  } 
  elsif($cmd eq "setRepeat") { ################################################
    #      setRepeat    => "[no1..36] <sendName> <recName> [bdcast-yes|no]"}
    $state = "";
	my (undef,undef,$eNo,$sId,$rId,$bCst) = @a;
	my ($pattern,$cnt);
	my $repPeers = AttrVal($name,"repPeers",undef);
	my @rPeer;
	@rPeer = split ",",$repPeers;
	if ($eNo eq "setAll"){
	  return " too many entries in repPeer" if (int(@rPeer) > 36);
	  return "setAll: attr repPeers undefined" if (!defined $repPeers);
	  my $entry = 0;
	  foreach my $repData (@rPeer){
	    $entry++;
	    my ($s,$d,$b) =split":",$repData;
		$s = CUL_HM_name2Id($s);
		$d = CUL_HM_name2Id($d);
		return "attr repPeers entry $entry irregular:$repData" 
		  if (!$s || !$d || !$b
		       || $s !~ m/(^[0-9A-F]{6})$/
		       || $d !~ m/(^[0-9A-F]{6})$/
		       || $b !~ m/^[yn]$/
			   );
	    $pattern .= $s.$d.(($b eq "n")?"00":"01");
	  }
	  while ($entry < 36){
	    $entry++;
	    $pattern .= "000000"."000000"."00";
	  }
	  $cnt = 1;# set first address byte
	}
	else{
      return "entry must be between 1 and 36" if ($eNo < 1 || $eNo > 36);	
	  my $sndID = CUL_HM_name2Id($sId);
	  my $recID = CUL_HM_name2Id($rId);
      if ($sndID !~ m/(^[0-9A-F]{6})$/){$sndID = AttrVal($sId,"hmId","");};	
	  if ($recID !~ m/(^[0-9A-F]{6})$/){$recID = AttrVal($rId,"hmId","");};
      return "sender ID $sId unknown:".$sndID    if ($sndID !~ m/(^[0-9A-F]{6})$/);	
      return "receiver ID $rId unknown:".$recID  if ($recID !~ m/(^[0-9A-F]{6})$/);	
      return "broadcast must be yes or now"      if ($bCst  !~ m/^(yes|no)$/);
	  $pattern = $sndID.$recID.(($bCst eq "no")?"00":"01");
      $cnt = ($eNo-1)*7+1;
	  $rPeer[$eNo-1] = "$sId:$rId:".(($bCst eq "no")?"n":"y");
	  $attr{$name}{repPeers} = join",",@rPeer;
	}
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
  elsif($cmd =~ m/^(alarm|service)$/) { #######################################
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
	  }
	  else{# operating on a channel
  	    return "$a[2] unknown. use: ".join(" ",sort keys(%color))
	          if (!defined($color{$a[2]}) );
        CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.'0'.$color{$a[2]});
	  }
	}
	elsif($md eq "HM-OU-CFM-PL"){
	  my %color = (redL =>18,greenL =>34,orangeL =>50,
	               redS =>17,greenS =>33,orangeS =>49,
				   pause=>01);
	  my @itemList = split(',',$a[2]);
	  my $repeat = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt = int(@itemList);
	  return "no more then 10 entries please"      if ($itemCnt>10);
	  return "at least one entry must be entered"  if ($itemCnt<1);
	  return "repetition $repeat out of range [1..255]"
          if($repeat < 1 ||	$repeat > 255);
      #<entries><multiply><MP3><MP3>
	  my $msgBytes = sprintf("01%02X",$repeat);
	  foreach my $led (@itemList){
        if (!$color{$led} ){# wrong parameter
	        return "'$led' unknown. use: ".join(" ",sort keys(%color));
	    }
        $msgBytes .= sprintf("%02X",$color{$led});
	  }
	  $msgBytes .= "01" if ($itemCnt == 1 && $repeat == 1);#add pause to term LED
	  # need to fill up empty locations  for LED channel
	  $msgBytes = substr($msgBytes."000000000000000000",0,(10+2)*2);
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes);
	}
	else{
	  return "device for command cannot be identified";
	}
  } 
  elsif($cmd eq "playTone") { #################################################
	my $msg;
	if ($a[2] eq 'replay'){
	  $msg = ReadingsVal($chnHash->{NAME},".lastTone","");
	}
	else{
	  my @itemList = split(',',$a[2]);
	  my $repeat = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt = int(@itemList);
	  return "no more then 12 entries please"  if ($itemCnt>12);
	  return "repetition $repeat out of range [1..255]"
            if($repeat < 1 ||	$repeat > 255);
      #<entries><multiply><MP3><MP3>
	  my $msgBytes = sprintf("%02X%02X",$itemCnt,$repeat);
	  foreach my $mp3 (@itemList){
        $msgBytes .= sprintf("%02X",$mp3);
	  }
	  $msg = '++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes;
	  CUL_HM_UpdtReadSingle($chnHash,".lastTone",$msg,0);
	}
    CUL_HM_PushCmdStack($hash,$msg) if ($msg);
  } 
  elsif($cmd =~ m/^(controlMode|controlManu|controlParty)$/) { ################
    my $mode = $a[2];
    if ($cmd ne "controlMode"){
	  $mode = substr($a[1],7);
      $a[2] = ($a[2] eq "off")?4.5:($a[2] eq "on"?30.5:$a[2]);
	}
	$mode = lc $mode;
    return "invalid $mode:select of mode [auto|boost|day|night] or"
	      ." controlManu,controlParty"
                if ($mode !~ m/^(auto|manu|party|boost|day|night)$/);
    my ($temp,$party);
	if ($mode =~ m/^(auto|boost|day|night)$/){
	  return "no additional params for $mode" if ($a[3]);
	}
	if($mode eq "manu"){
	  return "temperatur for manu  4.5 to 30.5 C"
	            if (!$a[2] || $a[2] < 4.5 || $a[2] > 30.5);
	  $temp = $a[2]*2;
	}
	elsif($mode eq "party"){
	  return  "use party <temp> <from-time> <from-date> <to-time> <to-date>\n"
             ."temperatur: 5 to 30 C\n"
			 ."date format: party 10 03.8.13 11:30 5.8.13 12:00"
	            if (!$a[2] || $a[2] < 5 || $a[2] > 30 || !$a[6] );
	  $temp = $a[2]*2;	  
	  # party format 03.8.13 11:30 5.8.13 12:00
	  my ($sd,$sm,$sy) = split('\.',$a[3]);
	  my ($sh,$smin)   = split(':' ,$a[4]);
	  my ($ed,$em,$ey) = split('\.',$a[5]);
	  my ($eh,$emin)   = split(':' ,$a[6]);
	  
	  return "wrong start day $sd"   if ($sd < 0 || $sd > 31);
	  return "wrong start month $sm" if ($sm < 0 || $sm > 12);
	  return "wrong start year $sy"  if ($sy < 0 || $sy > 99);
	  return "wrong start hour $sh"  if ($sh < 0 || $sh > 23);
	  return "wrong start minute $smin, ony 00 or 30" if ($smin != 0 && $smin != 30);
      $sh = $sh * 2 + $smin/30;
	  
	  return "wrong end day $ed"   if ($ed < 0 || $ed > 31);
	  return "wrong end month $em" if ($em < 0 || $em > 12);
	  return "wrong end year $ey"  if ($ey < 0 || $ey > 99);
	  return "wrong end hour $eh"  if ($eh < 0 || $eh > 23);
	  return "wrong end minute $emin, ony 00 or 30" if ($emin != 0 && $emin != 30);
      $eh = $eh * 2 + $emin/30;
	  
	  $party = sprintf("%02X%02X%02X%02X%02X%02X%02X",
	                    $sh,$sd,$sy,$eh,$ed,$ey,($sm*16+$em));
	}
	my %mCmd = (auto=>0,manu=>1,party=>2,boost=>3,day=>4,night=>5);
    readingsSingleUpdate($hash,"mode","set_".$mode,1);
	my $msg = '8'.($mCmd{$mode}).$chn;
	$msg .= sprintf("%02X",$temp) if ($temp);
	$msg .= $party if ($party);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$msg);
  }
  elsif($cmd eq "desired-temp") { #############################################
	if ($md =~ m/HM-CC-RT-DN/){
	  my $temp = ($a[2] eq "off")?9:($a[2] eq "on"?61:$a[2]*2);
	  return "invalid temp:$a[2]" if($temp <9 ||$temp > 60);
	  $temp = sprintf ("%02X",$temp);
      CUL_HM_PushCmdStack($hash,'++'.$flag."11$id$dst"."8604$temp");
	}
	else{
	  my $temp = CUL_HM_convTemp($a[2]);
	  return $temp if($temp =~ m/Invalid/);
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'0202'.$temp);
      my $chnHash = CUL_HM_id2Hash($dst."02");
	  my $mode = ReadingsVal($chnHash->{NAME},"R-controlMode","");
	  $mode =~ s/set_//;#consider set as given
	  readingsSingleUpdate($chnHash,"desired-temp-cent",$a[2],1) 
	        if($mode =~ m/central/);
	}
  } 
  elsif($cmd =~ m/^tempList(...)/) { ###################################### reg
    my $wd = $1;
	$state= "";
    my ($list,$addr,$prgChn);
	if ($md =~ m/HM-CC-RT-DN/){
      my %day2off = ( "Sat"=>"20", "Sun"=>"46", "Mon"=>"72", "Tue"=>"98", 
	                  "Wed"=>"124","Thu"=>"150","Fri"=>"176");
	  ($list,$addr,$prgChn) = (7,$day2off{$wd},0);
	}
	else{
      my %day2off = ( "Sat"=>"5 0B", "Sun"=>"5 3B", "Mon"=>"5 6B",
                      "Tue"=>"5 9B", "Wed"=>"5 CB", "Thu"=>"6 01",
                      "Fri"=>"6 31");
      ($list,$addr) = split(" ", $day2off{$wd},2);
	  $prgChn = 2;
      $addr = hex($addr);
	}

	my $prep = "";
    if ($a[2] =~ m/^(prep|exec)$/){
	  $prep = $a[2];
	  splice  @a,2,1;#remove prep 
	}
    return "To few arguments"                if(@a < 4);
    return "To many arguments, max 24 pairs" if(@a > (($md =~ m/HM-CC-RT-DN/)?28:50));
    return "Bad format, use HH:MM TEMP ..."  if(@a % 2);
    return "Last time spec must be 24:00"    if($a[@a-2] ne "24:00");
	
    my ($data,$msg) = ("","");
    for(my $idx = 2; $idx < @a; $idx += 2) {
      return "$a[$idx] is not in HH:MM format"
                                if($a[$idx] !~ m/^([0-2]\d):([0-5]\d)/);
      my ($h, $m) = ($1, $2);
	  my ($hByte,$lByte);
	  my $temp = $a[$idx+1];
	  if ($md =~ m/HM-CC-RT-DN/){
	    $temp = (int($temp*2)<<9) + ($h*12+($m/5));
		$hByte = $temp>>8;
		$lByte = $temp & 0xff;
	  }
	  else{
        $temp = CUL_HM_convTemp($temp);
	    return $temp if($temp =~ m/Invalid/);
		$hByte = $h*6+($m/10);
		$lByte = hex($temp);
	  }
      $data .= sprintf("%02X%02X%02X%02X", $addr, $hByte, $addr+1,$lByte);
      $addr += 2;

      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{HOUR} = $h;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{MINUTE} = $m;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{TEMP} = $a[$idx+1];
      $msg .= sprintf(" %02d:%02d %.1f", $h, $m, $a[$idx+1]);
    }
    CUL_HM_pushConfig($hash, $id, $dst, $prgChn,0,0,$list, $data,$prep);
  } 
  elsif($cmd eq "sysTime") { ##################################################
    $state = "";
	my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
    CUL_HM_PushCmdStack($hash,"++A03F$id${dst}0204$s2000");
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
  elsif($cmd eq "keydef") { ############################################### reg
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
    CUL_HM_PushCmdStack($hash, $msg);# repeat non-ack messages 3 times
    CUL_HM_PushCmdStack($hash, $msg);
    CUL_HM_PushCmdStack($hash, $msg);
  } 
  elsif($cmd =~ m/alarm(.*)/) { ###############################################
    my $msg = sprintf("++9441%s%s01%s",$dst,$dst,(($1 eq "On")?"0BC8":"0C01"));
    CUL_HM_PushCmdStack($hash, $msg);# repeat non-ack messages 3 times
    CUL_HM_PushCmdStack($hash, $msg);
    CUL_HM_PushCmdStack($hash, $msg);
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
	  $pChn = (($vChn && $vChn eq "off")?-1:0) + $chn*2 
	          if($st eq 'blindActuator'||$st eq 'dimmer');
      CUL_HM_PushCmdStack($hash, sprintf("++%s3E%s%s%s40%02X%02X",$flag,
	                                 $id,$dst,$dst,
                                     $pChn+(($mode && $mode eq "long")?64:0),
									 $pressCnt));                                     
	}
  } 
  elsif($cmd eq "postEvent") { ################################################
    #General add thermal event simulator
	my (undef,undef,$cond) = @a;
	if ($cond =~ m/[+-]?\d+/){
	  return "condition value:$cond above 200 illegal" if ($cond > 200);
	}
	else{
	  my $val;
	  my @keys;
	  foreach my $tp (keys %lvlStr){
	    foreach my $mk (keys %{$lvlStr{$tp}}){
	      foreach (keys %{$lvlStr{$tp}{$mk}}){
	        $val = hex($_) if ($cond eq $lvlStr{$tp}{$mk}{$_});
	  	    push @keys,$lvlStr{$tp}{$mk}{$_};
	      }
	    }
	  }
	  return "cond:$cond not allowed. choose one of:[0..200],"
	        .join(",",sort @keys)
	    if (!defined $val);
	  $cond = $val;
	}
	my $pressCnt = (!$hash->{helper}{count}?1:$hash->{helper}{count}+1)%256;
	$hash->{helper}{count}=$pressCnt;# remember for next round
    
	my @peerLChn = split(',',AttrVal($name,"peerIDs",""));
	my @peerDev;
	push (@peerDev,substr($_,0,6)) foreach (@peerLChn);
    @peerDev = CUL_HM_noDup(@peerDev);#only once per device!
	
	push @peerDev,'000000' if (!@peerDev);#send to broadcast if no peer
	foreach my $peer (@peerDev){
	  my $pHash = CUL_HM_id2Hash($peer);
	  my $peerFlag = $peer eq '00000000'?'A4':CUL_HM_getFlag($pHash);
	  $peerFlag =~ s/0/4/;# either 'A4' or 'B4'
      CUL_HM_SndCmd($pHash, "++B112$id".substr($peer,0,6)) 
	         if (CUL_HM_getRxType($pHash) & 0x80);
      CUL_HM_SndCmd($pHash, sprintf("++%s41%s%s%02X%02X%02X"
	                 ,$peerFlag,$dst,$peer
			         ,$chn
			         ,$pressCnt
			         ,$cond));
	}

	foreach my $peer (@peerLChn){#inform each channel
	  my $pName = CUL_HM_id2Name($peer);
	  $pName = CUL_HM_id2Name(substr($peer,0,6)) if (!$defs{$pName});
	  next if (!$defs{$pName});
	  CUL_HM_UpdtReadBulk($defs{$pName},1
	                        ,"trig_$name:$cond"
	                        ,"trigLast:$name:$cond");
	}
  } 
  elsif($cmd eq "peerChan") { ############################################# reg
    #peerChan <btnN> <device> ... [single|dual] [set|unset] [actor|remote|both]
	my ($bNo,$peerN,$single,$set,$target) = ($a[2],$a[3],$a[4],$a[5],$a[6]);
	$state = "";
	return "$bNo is not a button number"                          if(($bNo < 1) && !$roleC);
	my $peerId = CUL_HM_name2Id($peerN);
    return "please enter peer"                                    if(!$peerId);
	$peerId .= "01" if( length($peerId)==6);
	
	my ($peerChn,$peerBtn,$peerHash,$myBtn);	 
	my $peerDst = substr($peerId,0,6);

	if ($md =~ m/HM-CC-RT-DN/ && $chn eq "05" ){# rt team peers cross from 05 to 04
	  $myBtn = $peerBtn = "04";
	  $peerChn = "05";
	}
	else{ # normal devices
	  $peerBtn = $peerChn = substr($peerId,6,2);	# chan peeredd to remote
	  $myBtn = $chn;
	}
	$peerHash = $modules{CUL_HM}{defptr}{$peerDst.$peerChn}if ($modules{CUL_HM}{defptr}{$peerDst.$peerChn});
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst}         if (!$peerHash);
	
	return "$peerN not a CUL_HM device"                           if($target && ($target ne "remote") &&(!$peerHash ||$peerHash->{TYPE} ne "CUL_HM"));
    return "$single must be single or dual"                       if(defined($single) && ($single !~ m/^(single|dual)$/));
    return "$set must be set or unset"                            if(defined($set)    && ($set    !~ m/^(set|unset)$/));
    return "$target must be [actor|remote|both]"                  if(defined($target) && ($target !~ m/^(actor|remote|both)$/));
	return "use climate chan to pair TC"                          if( $md eq "HM-CC-TC" && $myBtn ne "02");
	return "use - single [set|unset] actor - for smoke detector"  if( $st eq "smokeDetector"       && (!$single || $single ne "single" || $target ne "actor"));
	return "use - single - for ".$st                              if(($st =~ m/(threeStateSensor|thermostat|motionDetector)/)
	                                                                      && (!$single || $single ne "single"));

	$single = ($single eq "single")?1:"";#default to dual
	$set = ($set && $set eq "unset")?0:1;

	my ($b1,$b2,$nrCh2Pair);
	$b1 = ($roleC) ? hex($myBtn) : ($single?$bNo : ($bNo*2 - 1));
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
	my $pSt = CUL_HM_Get($peerHash,$peerHash->{NAME},"param","subType");
	if (!$target || $target =~ m/^(remote|both)$/){
	  my $burst = ($pSt eq "thermostat"?"0101":"0100");#set burst for target 
	  my $pnb = 1 if ($culHmRegModel{$md}{peerNeedsBurst}|| #supported?
	                  $culHmRegType{$st}{peerNeedsBurst});
      for(my $i = 1; $i <= $nrCh2Pair; $i++) {
        my $b = ($i==1 ? $b1 : $b2);		
  	    if ($st eq "virtual"){
		  my $btnName = CUL_HM_id2Name($dst.sprintf("%02X",$b));
		  return "button ".$b." not defined for virtual remote ".$name
		      if (!defined $attr{$btnName});
		  CUL_HM_ID2PeerList ($btnName,$peerDst.$peerBtn,$set); #upd. peerlist
	    }
		else{
		  my $bStr = sprintf("%02X",$b);
  	      CUL_HM_PushCmdStack($hash, 
  	            "++".$flag."01${id}${dst}${bStr}$cmdB${peerDst}${peerBtn}00");
  	      CUL_HM_pushConfig($hash,$id, $dst,$b,$peerDst,hex($peerBtn),4,$burst)
				   if($pnb);
		  CUL_HM_qAutoRead($name,3);
	    }
      }
	}
	if (!$target || $target =~ m/^(actor|both)$/ ){
	  if ($pSt eq "virtual"){
		CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b2),$set); #update peerlist
		CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b1),$set) if ($b1 & !$single);
	  }
	  else{
	    my $peerFlag = CUL_HM_getFlag($peerHash);
        CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",
            $peerFlag,$id,$peerDst,$peerChn,$cmdB,$dst,$b2,$b1 ));
		CUL_HM_pushConfig($peerHash,$id,$peerDst,0,0,0,0,"0101")#set burstRx
				   if(CUL_HM_getRxType($peerHash) & 0x80);      #if conBurst
		CUL_HM_qAutoRead($peerHash->{NAME},3);
	  }
	}
	return ("",1) if ($target && $target eq "remote");#Nothing to transmit for actor
    $devHash = $peerHash; # Exchange the hash, as the switch is always alive.
  }
  else{
    return "$cmd not impelmented - contact sysop";
  }
 
  readingsSingleUpdate($hash,"state",$state,1) if($state);

  my $rxType = CUL_HM_getRxType($devHash);
  Log GetLogLevel($name,2), "CUL_HM set $name $act";
  Log 1,"General send $name rxt:$rxType p:".$devHash->{helper}{prt}{sProc};
  if($rxType & 0x03){#all/burst
    CUL_HM_ProcessCmdStack($devHash);
  }
  elsif(($rxType & 0x80)                   &&  #burstConditional - have a try
        $devHash->{cmdStack}               && 
		$devHash->{helper}{prt}{sProc} != 1    # not pocessing
		){
	$hash->{helper}{prt}{wakeup}=1;# start auto-wakeup
    CUL_HM_SndCmd($devHash,"++B112$id$dst");
  }
  return ("",1);# no not generate trigger outof command
}

#+++++++++++++++++ set/get support subroutines+++++++++++++++++++++++++++++++++
my $updtValveCnt = 0;
sub CUL_HM_valvePosUpdt(@) {#update valve position periodically to please valve
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
	  CUL_HM_PushCmdStack($hash,sprintf("++A258%s%s%s%02X",$vDevId
	                                    ,$peer,$hash->{helper}{virtTC},$vp));
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
  my $md = $culHmModel{$mId}{name} ? $culHmModel{$mId}{name}:"unknown";
  $attr{$name}{model}    = $md;
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
		"$chnName,$chnId,$md",0);
      }
	  $attr{CUL_HM_id2Name($chnId)}{model} = $md;
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
sub CUL_HM_getConfig($){
  my $hash = shift;
  my $flag = CUL_HM_getFlag($hash);
  my $id = CUL_HM_IOid($hash);
  my $dst = substr($hash->{DEF},0,6);
  my $name = $hash->{NAME};
  
  CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000')
	       if ($hash->{helper}{role}{dev});
  my @chnIdList = CUL_HM_getAssChnIds($name);
  foreach my $channel (@chnIdList){
    my $cHash = CUL_HM_id2Hash($channel);
    my $chn = substr($channel,6,2);
    delete $cHash->{READINGS}{$_}
          foreach (grep /^[\.]?(RegL_)/,keys %{$cHash->{READINGS}});
    my $lstAr = $culHmModel{CUL_HM_getMId($cHash)}{lst};
    if($lstAr){
      my @list = split(",",$lstAr); #get valid lists e.g."1, 5:2.3p ,6:2"
      my $pReq = 0; # Peer request not issued, do only once for channel
      foreach my$listEntry (@list){# each list that is define for this channel
        my ($peerReq,$chnValid)= (0,0);
        my ($listNo,$chnLst1) = split(":",$listEntry); 
        if (!$chnLst1){
          $chnValid = 1; #if no entry go for all channels
          $peerReq = 1 if($listNo eq 'p' || $listNo==3 ||$listNo==4); #default
        }
        else{
          my @chnLst = split('\.',$chnLst1);
          foreach my $lchn (@chnLst){
            $peerReq = 1 if ($lchn =~ m/p/);
  	        no warnings;#know that lchan may be followed by 'p' causing a warning
              $chnValid = 1 if (int($lchn) == hex($chn));
  	        use warnings;
            last if ($chnValid);
          }
        }
        if ($chnValid){# yes, we will go for a list
          if ($peerReq){# need to get the peers first
            if($listNo ne 'p'){# not if 'only peers'!
	          $cHash->{helper}{getCfgList} = "all";
              $cHash->{helper}{getCfgListNo} = $listNo;
	        }
	        if (!$pReq){#get peers first, but only once per channel
	          CUL_HM_PushCmdStack($cHash,sprintf("++%s01%s%s%s03"
		                                 ,$flag,$id,$dst,$chn));
		      $pReq = 1;
	        }
          }
          else{
            CUL_HM_PushCmdStack($cHash,sprintf("++%s01%s%s%s0400000000%02X"
	                                    ,$flag,$id,$dst,$chn,$listNo));
          }
        }	
      }
    }
  }
}

#+++++++++++++++++ Protocol stack, sending, repeat+++++++++++++++++++++++++++++
sub CUL_HM_pushConfig($$$$$$$$@) {#generate messages to config data to register
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content,$prep) = @_;
  my $flag = CUL_HM_getFlag($hash);
  my $tl = length($content);

  $chn     = sprintf("%02X",$chn);
  $peerChn = sprintf("%02X",$peerChn);
  $list    = sprintf("%02X",$list);
  $prep    = "" if (!defined $prep);
  # --store pending changes in shadow to handle bit manipulations cululativ--
  $peerAddr = "000000" if(!$peerAddr);
  my $peerN = ($peerAddr ne "000000")?CUL_HM_peerChName($peerAddr.$peerChn,$dst,""):"";
  $peerN =~ s/broadcast//;
  $peerN =~ s/ /_/g;#remote blanks
  my $regLNp = "RegL_".$list.":".$peerN;
  my $regPre = ((CUL_HM_getAttrInt($hash->{NAME},"expert") == 2)?"":".");
  my $regLN = $regPre.$regLNp;
  #--- copy data from readings to shadow
  my $chnhash = $modules{CUL_HM}{defptr}{$dst.$chn};
  $chnhash = $hash if (!$chnhash);
  my $rRd = ReadingsVal($chnhash->{NAME},$regLN,"");
  if (!$chnhash->{helper}{shadowReg} ||
      !$chnhash->{helper}{shadowReg}{$regLNp}){
	$chnhash->{helper}{shadowReg}{$regLNp} = $rRd;
  }
  #--- update with ne value
  my $regs = $chnhash->{helper}{shadowReg}{$regLNp};
  for(my $l = 0; $l < $tl; $l+=4) { #substitute changed bytes in shadow
    my $addr = substr($content,$l,2);
    my $data = substr($content,$l+2,2);
    if(!$regs || !($regs =~ s/$addr:../$addr:$data/)){
      $regs .= " ".$addr.":".$data;
    }
  }
  $chnhash->{helper}{shadowReg}{$regLNp} = $regs; # update shadow
  my @changeList;
  if ($prep eq "exec"){#update complete registerset
	@changeList = keys%{$chnhash->{helper}{shadowReg}};
  }
  elsif ($prep eq "prep"){
    return; #prepare shadowReg only. More data expected. 
  }
  else{
	push @changeList,$regLNp;
  }
  my $changed = 0;# did we write
  foreach my $nrn(@changeList){
    my $change;
	my $nrRd = ReadingsVal($chnhash->{NAME},$regPre.$nrn,"");
    foreach (sort split " ",$chnhash->{helper}{shadowReg}{$nrn}){
	  $change .= $_." " if ($nrRd !~ m /$_/);# filter only changes
	}
	next if (!$change);#no changes
	$change =~ s/00:00//;
	$change =~ s/(\ |:)//g;
	my $peerN;
	$changed = 1;# yes, we did
	($list,$peerN) = ($1,$2) if($nrn =~ m/RegL_(..):(.*)/);
	if ($peerN){($peerAddr,$peerChn) = unpack('A6A2', CUL_HM_name2Id($peerN,$hash));}
	else       {($peerAddr,$peerChn) = ('000000','00');}
    CUL_HM_updtRegDisp($hash,$list,$peerAddr.$peerChn);
	############partition
#	my @chSplit = unpack('(A28)*',$change);
	my @chSplit = unpack('(A1120)*',$change);# makes max 40 lines, 280 byte
	foreach my $chSpl(@chSplit){
      CUL_HM_PushCmdStack($hash, "++".$flag.'01'.$src.$dst.$chn.'05'.
                                          $peerAddr.$peerChn.$list);
      $tl = length($chSpl);
	  for(my $l = 0; $l < $tl; $l+=28) {
        my $ml = $tl-$l < 28 ? $tl-$l : 28;
        CUL_HM_PushCmdStack($hash, "++A001".$src.$dst.$chn."08".
	                                   substr($chSpl,$l,$ml));
      }
      CUL_HM_PushCmdStack($hash,"++A001".$src.$dst.$chn."06");
	}
	#########
  }
  CUL_HM_qAutoRead($hash->{NAME},3) if ($changed);
}
sub CUL_HM_PushCmdStack($$) {
  my ($chnhash, $cmd) = @_;
  my @arr = ();
  my $hash = CUL_HM_getDeviceHash($chnhash);
  my $name = $hash->{NAME};
  if(!$hash->{cmdStack}){# this is a new 'burst' of messages
    $hash->{cmdStack} = \@arr;
	$hash->{helper}{prt}{bErr}=0 if ($hash->{helper}{prt}{sProc} != 1);# not processing
  }
  push(@{$hash->{cmdStack}}, $cmd);
  my $entries = scalar @{$hash->{cmdStack}};
  $hash->{protCmdPend} = $entries." CMDs_pending";
  CUL_HM_protState($hash,"CMDs_pending") if($hash->{helper}{prt}{sProc} != 1);# not processing
}
sub CUL_HM_ProcessCmdStack($) {
  my ($chnhash) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);
  if($hash->{cmdStack} && !$hash->{helper}{prt}{rspWait}{cmd}){
    if(@{$hash->{cmdStack}}) {
      CUL_HM_SndCmd($hash, shift @{$hash->{cmdStack}});
    }
    elsif(!@{$hash->{cmdStack}}) {
	  #-- update info ---
	  CUL_HM_protState($hash,"CMDs_done".($hash->{helper}{prt}{bErr}? 
	                            ("_Errors:".$hash->{helper}{prt}{bErr}):""));
    }
  }
  return;
}

sub CUL_HM_prtInit($){ #setup protocol variables after define
  my ($hash)=@_;
  $hash->{helper}{prt}{sProc} = 0; # stack not being processed by now
  $hash->{helper}{prt}{bErr}=0;
}
sub CUL_HM_respWaitSu($@){ #setup response for multi-message response
  # single commands
  # cmd: single msg that needs to be ACKed
  # mNo: number of message (needs to be in ACK)
  # mNoWu: number of message if wakeup 
  # reSent: number of resends already done - usually init with 1
  # wakeup: was wakeup message (burst devices)
  #
  # commands with multi-message answer
  # PendCmd: command message
  # Pending: type of answer we are awaiting
  # forChn:  which channel are we working on?
  # forList: which list are we waiting for? (optional)
  # forPeer: which peer are we waiting for? (optional)
  my ($hash,@a)=@_;
  my $mHsh = $hash->{helper}{prt};
  $modules{CUL_HM}{prot}{rspPend}++ if(!$mHsh->{rspWait}{cmd});
  foreach (@a){
	my ($f,$d)=split ":=",$_;
	$mHsh->{rspWait}{$f}=$d;
  }
  my $to = gettimeofday() + (($mHsh->{rspWait}{Pending})?rand(20)/10+4:
				                                         rand(40)/10+1);
  InternalTimer($to,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);                       
 }
sub CUL_HM_responseSetup($$) {#store all we need to handle the response
 #setup repeatTimer and cmdStackControll
  my ($hash,$cmd) =  @_;
  my ($mNo,$mFlg,$mTp,$dst,$p) = ($2,hex($3),$4,$6,$7)
      if ($cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/);
  my ($chn,$subType) = ($1,$2) if($p =~ m/^(..)(..)/); 

  if (($mFlg & 0x20) && ($dst ne '000000')){
    if   ($mTp eq "01" && $subType){ 
      if   ($subType eq "03"){ #PeerList-----------
    	#--- remember request params in device level
		CUL_HM_respWaitSu ($hash,"Pending:=PeerList"
		                        ,"cmd:=$cmd" ,"forChn:=".substr($p,0,2)
								,"reSent:=1");
								
    	#--- remove readings in channel
    	my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"}; 
    	$chnhash = $hash if (!$chnhash);
    	delete $chnhash->{READINGS}{peerList};#empty old list
    	delete $chnhash->{peerList};#empty old list
	    delete $chnhash->{helper}{peerIDsRaw};
	    $attr{$chnhash->{NAME}}{peerIDs} = '';
      }
      elsif($subType eq "04"){ #RegisterRead-------
        my ($peer, $list) = ($1,$2) if ($p =~ m/..04(........)(..)/);
	    $peer = ($peer ne "00000000")?CUL_HM_peerChName($peer,$dst,""):"";
	    #--- set messaging items
		CUL_HM_respWaitSu ($hash,"Pending:=RegisterRead"
		                        ,"cmd:=$cmd" ,"forChn:=$chn"
								,"forList:=$list","forPeer:=$peer"
								,"reSent:=1");
	    #--- remove channel entries that will be replaced
        my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
        $chnhash = $hash if(!$chnhash);   
    
	    $peer ="" if($list !~ m/^0[34]$/);
	    #empty val since reading will be cumulative 
	    my $rlName = ((CUL_HM_getAttrInt($chnhash->{NAME},"expert") == 2)?
		                                 "":".")."RegL_".$list.":".$peer;
        $chnhash->{READINGS}{$rlName}{VAL}=""; 
        delete ($chnhash->{READINGS}{$rlName}{TIME}); 
      }
      elsif($subType eq "09"){ #SerialRead-------
		CUL_HM_respWaitSu ($hash,"Pending:=SerialRead"
		                        ,"cmd:=$cmd" ,"reSent:=1");
      }
	  else{
	    CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=1");
	  }
    }
    elsif($mTp eq '11' && $chn =~ m/^(02|81)$/){#!!! chn is subtype!!!
#      CUL_HM_qStateUpdatIfEnab($dst.$subType);# subtype actually is channel
      if ($p =~ m/02..(..)....(....)/){#lvl ne 0 and timer on
 	    $hash->{helper}{tmdOn} = $2 if ($1 ne "00" && $2 !~ m/(0000|FFFF)/);
	    CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo"
		                        ,"reSent:=1","timedOn:=1");
	  }
    }
	elsif($mTp eq '12' && $mFlg & 0x10){#wakeup with burst
	  # response setup - do not repeat, set counter to 250
	  CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=1","wakeup:=1");
	}
	else{
	  CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=1");
	}

	CUL_HM_protState($hash,"CMDs_processing...");                         
  }
  else{# no answer expected
	if($hash->{cmdStack} && scalar @{$hash->{cmdStack}}){
	  CUL_HM_protState($hash,"CMDs_processing..."); 
      InternalTimer(gettimeofday()+.5, "CUL_HM_ProcessCmdStack", $hash, 0);
	}
	elsif(!$hash->{helper}{prt}{rspWait}{cmd}){
      CUL_HM_protState($hash,"CMDs_done".($hash->{helper}{prt}{bErr}? 
	                            ("_Errors:".$hash->{helper}{prt}{bErr}):""));
	}
  }

  my $mmcS = $hash->{helper}{prt}{mmcS}?$hash->{helper}{prt}{mmcS}:0;
  if ($mTp eq '01'){
    my ($chn,$sTp) = unpack 'A2A2',$p;
	my $oCmd = "++".substr($cmd,6);
	if    ($sTp eq "05"){
	  my @arr = ($oCmd);
	  $hash->{helper}{prt}{mmcA}=\@arr;
	  $hash->{helper}{prt}{mmcS} = 1;
	}
	elsif ($sTp =~ m/(07|08)/ && ($mmcS == 1||$mmcS == 2)){
	  push @{$hash->{helper}{prt}{mmcA}},$oCmd;
	  $hash->{helper}{prt}{mmcS} = 2;
	}
	elsif ($sTp eq "06" && ($mmcS == 2)){
	  push @{$hash->{helper}{prt}{mmcA}},$oCmd;
	  $hash->{helper}{prt}{mmcS} = 3;
	}
    elsif ($mmcS){ #
	  delete $hash->{helper}{prt}{mmcA};
	  delete $hash->{helper}{prt}{mmcS};
    }
  }
  elsif($mmcS){
    delete $hash->{helper}{prt}{mmcA};
	delete $hash->{helper}{prt}{mmcS};
  }
  
  if($hash->{cmdStack} && scalar @{$hash->{cmdStack}}){
    $hash->{protCmdPend} = scalar @{$hash->{cmdStack}}." CMDs pending";
  }
  else{
    delete($hash->{protCmdPend});
  }
}

sub CUL_HM_sndIfOpen($) {
  my(undef,$io) = split(':',$_[0]);
  RemoveInternalTimer("sndIfOpen:$io");# should not be necessary, but
  my $ioHash = $defs{$io};
  if (   $ioHash->{STATE} !~ m/^(opened|Initialized)$/ 
      ||(defined $ioHash->{XmitOpen} && $ioHash->{XmitOpen} == 0) 
#	  ||$modules{CUL_HM}{prot}{rspPend}>=$maxPendCmds
	   ){#still no send allowed
    if ($modules{CUL_HM}{$io}{tmrStart} < gettimeofday() - $modules{CUL_HM}{hmIoMaxDly}){
	  # we need to clean up - this is way to long Stop delay
	  if ($modules{CUL_HM}{$io}{pendDev}) {
        while(@{$modules{CUL_HM}{$io}{pendDev}}){
	      my $name = shift(@{$modules{CUL_HM}{$io}{pendDev}});
          CUL_HM_eventP($defs{$name},"IOerr");
		}
	  }
	  $modules{CUL_HM}{$io}{tmr} = 0;
	}
	else{
   	  InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
	                                "sndIfOpen:$io", 0);	
	}
  }
  else{
    $modules{CUL_HM}{$io}{tmr} = 0;
	my $name = shift(@{$modules{CUL_HM}{$io}{pendDev}});
	CUL_HM_ProcessCmdStack($defs{$name});
	if (@{$modules{CUL_HM}{$io}{pendDev}}){#tmr = 0, clearing queue slowly
   	  InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
	                                "sndIfOpen:$io", 0);
	}
  }
}
sub CUL_HM_SndCmd($$) {
  my ($hash, $cmd) = @_;
  $hash = CUL_HM_getDeviceHash($hash); 
  my $io = $hash->{IODev};
  return if(  !$io 
            || AttrVal($hash->{NAME},"ignore","")
			|| AttrVal($hash->{NAME},"dummy",""));  
  my $ioName = $io->{NAME};
  if (  $io->{STATE} !~ m/^(opened|Initialized)$/          # we need to queue
      ||(hex substr($cmd,2,2) & 0x20) && (                 # check for commands with resp-req
           $modules{CUL_HM}{$ioName}{tmr}                  # queue already running
         ||(defined $io->{XmitOpen} && $io->{XmitOpen} == 0)#overload, dont send
	    )
	  ){

	# shall we delay commands if IO device is not present?
	# it could cause trouble if light switches on after a long period
	# repetition will be stopped after 1min forsecurity reason. 
    my @arr = ();
    $hash->{cmdStack} = \@arr if(!$hash->{cmdStack});
    unshift (@{$hash->{cmdStack}}, $cmd);#pushback cmd, wait for opportunity

	# push device to list
	if (!defined $modules{CUL_HM}{$ioName}{tmr}){
	  # some setup work for this timer
	  $modules{CUL_HM}{$ioName}{tmr} = 0; 
	  if (!$modules{CUL_HM}{$ioName}{pendDev}){# generate if not exist
	    my @arr2 = ();
        $modules{CUL_HM}{$ioName}{pendDev} = \@arr2;
	  }
	}
    @{$modules{CUL_HM}{$ioName}{pendDev}} = 
	      CUL_HM_noDup(@{$modules{CUL_HM}{$ioName}{pendDev}},$hash->{NAME});
	CUL_HM_respPendRm($hash);#rm timer - we are out
	if ($modules{CUL_HM}{$ioName}{tmr} != 1){# need to start timer
	  my $tn = gettimeofday();
   	  InternalTimer($tn+$IOpoll, "CUL_HM_sndIfOpen", "sndIfOpen:$ioName", 0);
      $modules{CUL_HM}{$ioName}{tmr} = 1;
      $modules{CUL_HM}{$ioName}{tmrStart} = $tn; # abort if to long
	}
	return;
  }
  
  $cmd =~ m/^(..)(.*)$/;
  my ($mn, $cmd2) = ($1, $2);

  if($mn eq "++") {
    $mn = $io->{HM_CMDNR} ? (($io->{HM_CMDNR} +1)&0xff) : 1;
    $io->{HM_CMDNR} = $mn;
  } 
  elsif($cmd =~ m/^[+-]/){; #continue pure
    IOWrite($hash, "", $cmd);
	return;
  }
  else {
    $mn = hex($mn);
  }
  $cmd = sprintf("As%02X%02X%s", length($cmd2)/2+1, $mn, $cmd2);
  IOWrite($hash, "", $cmd);
  CUL_HM_eventP($hash,"Snd");	  
  CUL_HM_responseSetup($hash,$cmd);	
  $cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6,$7));
}

sub CUL_HM_respPendRm($) {#del response related entries in messageing entity
  my ($hash) =  @_;  
  $modules{CUL_HM}{prot}{rspPend}-- if($hash->{helper}{prt}{rspWait}{cmd});
  delete ($hash->{helper}{prt}{rspWait});
  delete $hash->{helper}{tmdOn};
  delete $hash->{helper}{prt}{mmcA};
  delete $hash->{helper}{prt}{mmcS};
  RemoveInternalTimer($hash);                  # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer
  $respRemoved = 1;
}
sub CUL_HM_respPendTout($) {
  my ($HMid) =  @_; 
  (undef,$HMid) = split(":",$HMid,2); 
  my $hash = $modules{CUL_HM}{defptr}{$HMid}; 
  my $pHash = $hash->{helper}{prt};#shortcut
  if ($hash && $hash->{DEF} ne '000000'){# we know the device
    my $name = $hash->{NAME};
    $pHash->{awake} = 0 if (defined $pHash->{awake});# set to asleep
    return if(!$pHash->{rspWait}{reSent});      # Double timer?
    if ($pHash->{rspWait}{wakeup}){
	  CUL_HM_respPendRm($hash);# do not count problems with wakeup try, just wait
	  $hash->{protCondBurst} = "off" if (!$hash->{protCondBurst}||
	                                      $hash->{protCondBurst} !~ m/forced/);;
	  $pHash->{wakeup} = 0;# finished
	  $pHash->{awake} = 0;# set to asleep
	  CUL_HM_protState($hash,"CMDs_pending");
	}
	elsif ($hash->{IODev}->{STATE} !~ m/^(opened|Initialized)$/){#IO errors
      CUL_HM_eventP($hash,"IOdly");
	  CUL_HM_ProcessCmdStack($hash) if(CUL_HM_getRxType($hash) & 0x03);
	}
	elsif ($pHash->{rspWait}{reSent} > AttrVal($hash->{NAME},"msgRepeat",3) # too much
	     ||((CUL_HM_getRxType($hash) & 0x83) == 0)){                        #to slow
      my $pendCmd = ($pHash->{rspWait}{Pending}
					            ?"RESPONSE TIMEOUT:".$pHash->{rspWait}{Pending}
								:"MISSING ACK");# save before remove
	  CUL_HM_eventP($hash,"ResndFail");
	  readingsSingleUpdate($hash,"state",$pendCmd,1);
	  CUL_HM_ProcessCmdStack($hash); # continue processing commands if any
	}
	else{# manage retries
	  if ($hash->{protCondBurst}&&$hash->{protCondBurst} eq "on" ){
		#timeout while conditional burst was active. try re-wakeup
        $pHash->{rspWait}{reSent}++;

		my (undef,$addr,$msg) = unpack 'A10A12A*',$hash->{helper}{prt}{rspWait}{cmd};		  
		$pHash->{rspWaitSec}{$_} = $pHash->{rspWait}{$_} 
		            foreach (keys%{$pHash->{rspWait}});
		CUL_HM_SndCmd($hash,"++B112$addr");
	    $hash->{helper}{prt}{awake}=4;# start re-wakeup
	  }
	  else{# normal device resend
	    CUL_HM_eventP($hash,"Resnd");
        IOWrite($hash, "", $pHash->{rspWait}{cmd});
        $pHash->{rspWait}{reSent}++;
        Log GetLogLevel($name,4),"CUL_HM_Resend: ".$name. " nr ".$pHash->{rspWait}{reSent};
	    InternalTimer(gettimeofday()+rand(20)/10+4,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
	  }
	}
  }
}
sub CUL_HM_respPendToutProlong($) {#used when device sends part responses
  my ($hash) =  @_;  
  RemoveInternalTimer("respPend:$hash->{DEF}");
  InternalTimer(gettimeofday()+2, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}

sub CUL_HM_eventP($$) {#handle protocol events
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv
  my ($hash, $evntType) = @_;
  my $nAttr = $hash;
  if ($evntType eq "Rcv"){
    $nAttr->{"protLastRcv"} = TimeNow();
	return;
  }
  
  my $evnt = $nAttr->{"prot".$evntType}?$nAttr->{"prot".$evntType}:"0 > x";
  my ($evntCnt,undef) = split(' last_at:',$evnt);
  $nAttr->{"prot".$evntType} = ++$evntCnt." last_at:".TimeNow();
  
  if ($evntType =~ m/(Nack|ResndFail|IOerr)/){# unrecoverable Error
	readingsSingleUpdate($hash,"state",$evntType,1);
    $hash->{helper}{prt}{bErr}++;
    $nAttr->{protCmdDel} = 0 if(!$nAttr->{protCmdDel});
    $nAttr->{protCmdDel} += scalar @{$hash->{cmdStack}} + 1
	        if ($hash->{cmdStack});
	CUL_HM_protState($hash,"CMDs_done".($hash->{helper}{prt}{bErr}? 
	                        ("_Errors:".$hash->{helper}{prt}{bErr}):""));
	CUL_HM_respPendRm($hash);
  }
  elsif($evntType eq "IOdly"){ # IO problem - will see whether it recovers 
    my $pHash = $hash->{helper}{prt};
	if ($pHash->{mmcA}){
	  unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
	  delete $pHash->{mmcA};
	  delete $pHash->{mmcS};
	}
	else{
      unshift @{$hash->{cmdStack}}, $pHash->{rspWait}{cmd};#pushback
	}
	CUL_HM_respPendRm($hash);
  }
}
sub CUL_HM_protState($$){
  my ($hash,$state) = @_;
  $hash->{protState} = $state;
  my $name = $hash->{NAME};
  readingsSingleUpdate($hash,"state",$state,0) if (!$hash->{helper}{role}{chn});
  Log GetLogLevel($name,6),"CUL_HM $name protEvent:$state".
            ($hash->{cmdStack}?" pending:".scalar @{$hash->{cmdStack}}:"");
  if   ($state =~ m/processing/) {$hash->{helper}{prt}{sProc} = 1;
								 }
  elsif($state =~ m/^CMDs_done/) {DoTrigger($name, undef);
                                  delete($hash->{cmdStack});
								  delete($hash->{protCmdPend}); 
	                              $hash->{helper}{prt}{sProc} = 0;
						  		  $hash->{helper}{prt}{awake} = 0 if (defined$hash->{helper}{prt}{awake}); # asleep
                                 }
  elsif($state eq "Info_Cleared"){$hash->{helper}{prt}{sProc} = 0;
						  		  $hash->{helper}{prt}{awake} = 0 if (defined$hash->{helper}{prt}{awake}); # asleep
                                 }
  elsif($state eq "CMDs_pending"){$hash->{helper}{prt}{sProc} = 2;
                                 }
}

###################-----------helper and shortcuts--------#####################
################### Peer Handling ################
sub CUL_HM_ID2PeerList ($$$) {
  my($name,$peerID,$set) = @_;
  my $peerIDs = $attr{$name}{peerIDs}?$attr{$name}{peerIDs}:"";
  my $hash = $defs{$name};
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
	$peerNames .= CUL_HM_peerChName($pId,$dId,"").","; 
  }
  $attr{$name}{peerIDs} = $peerIDs;                 # make it public
  if ($peerNames){
    $peerNames =~ s/_chn:01//g; # channel 01 is part of device
    readingsSingleUpdate($hash,"peerList",$peerNames,0) ;
    $hash->{peerList} = $peerNames;
  }
  else{ 
    delete $hash->{READINGS}{peerList};
    delete $hash->{peerList};
  }
}
sub CUL_HM_peerChId($$$) {# in:<IDorName> <deviceID> <ioID>, out:channelID
  my($pId,$dId,$iId)=@_;
  my $pSc = substr($pId,0,4); #helper for shortcut spread
  return $dId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'self');
  return $iId.sprintf("%02X",'0'.substr($pId,4)) if ($pSc eq 'fhem');
  return "all"                                   if ($pId eq 'all');#used by getRegList
  my $repID = CUL_HM_name2Id($pId);
  $repID .= '01' if (length( $repID) == 6);# add default 01 if this is a device
  return $repID;                  
}
sub CUL_HM_peerChName($$$) {#in:<IDorName> <deviceID> <ioID>, out:name
  my($pId,$dId,$iId)=@_;
  my($pDev,$pChn) = unpack'A6A2',$pId;
  return 'self'.$pChn if ($pDev eq $dId);
  return 'fhem'.$pChn if ($pDev eq $iId);
  return CUL_HM_id2Name($pId);                
}
sub CUL_HM_getMId($) {#in: hash(chn or dev) out:model key (key for %culHmModel)
 # Will store result in device helper
  my $hash = shift;
  $hash = CUL_HM_getDeviceHash($hash);
  my $mId = $hash->{helper}{mId};
  if (!$mId){   
    my $model = AttrVal($hash->{NAME}, "model", "");
    foreach my $mIdKey(keys%culHmModel){
	  next if (!$culHmModel{$mIdKey}{name} || 
	            $culHmModel{$mIdKey}{name} ne $model);
	  $hash->{helper}{mId} = $mIdKey ;
	  return $mIdKey;
    }
	return "";
  }
  return $mId;
}
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
      $rxtEntity |= ($rxtOfModel =~ m/l/)?0x10:0;#lazyConfig
      $rxtEntity |= ($rxtOfModel =~ m/f/)?0x80:0 #burstConditional
	        if(CUL_HM_getAttrInt($hash->{NAME},"burstAccess",0));
	}
	$rxtEntity = 1 if (!$rxtEntity);#always
	$hash->{helper}{rxType} = $rxtEntity;
  }
  return $rxtEntity;  
}
sub CUL_HM_getFlag($) {#mFlg 'A0' or 'B0' for burst/normal devices
 # currently not supported is the wakeupflag since it is hardly used
  my ($hash) = @_;
  return (CUL_HM_getRxType($hash) & 0x02)?"B0":"A0"; #set burst flag
}
sub CUL_HM_getAssChnIds($) { #in: name out:ID list of assotiated channels
  # if it is a channel only return itself
  # if device and no channel 
  my ($name) = @_;
  my @chnIdList;
  my $hash = $defs{$name};
  foreach my $channel (grep /^channel_/, keys %{$hash}){
	my $chnHash = $defs{$hash->{$channel}};
	push @chnIdList,$chnHash->{DEF} if ($chnHash);
  }
  my $dId = CUL_HM_name2Id($name);

  push @chnIdList,$dId."01" if (length($dId) == 6 && !$hash->{channel_01});
  push @chnIdList,$dId if (length($dId) == 8);
  return sort(@chnIdList);
}

#+++++++++++++++++ Conversions names, hashes, ids++++++++++++++++++++++++++++++
#Performance opti: subroutines may consume up to 5 times the performance
# 
#get Attr: $val  = $attr{$hash->{NAME}}{$attrName}?$attr{$hash->{NAME}}{$attrName}      :"";
#          $val  = $attr{$name}{$attrName}        ?$attr{$name}{$attrName}              :"";
#getRead:  $val  = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{VAL}      :""; 
#          $val  = $defs{$name}{READINGS}{$rlName}?$defs{$name}{READINGS}{$rlName}{VAL} :""; 
#          $time = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{time}     :""; 

sub CUL_HM_Id($) {#in: ioHash out: ioHMid 
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return $attr{$io->{NAME}}{hmId}?$attr{$io->{NAME}}{hmId}:"F1$fhtid";
}
sub CUL_HM_IOid($) {#in: hash out: id of IO device  
  my ($hash) = @_;
  my $dHash = CUL_HM_getDeviceHash($hash);
  my $ioHash = $dHash->{IODev};
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return $attr{$ioHash->{NAME}}{hmId}?$attr{$ioHash->{NAME}}{hmId}:"F1$fhtid";
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
  return $hash->{DEF}        if($hash && $hash->{TYPE} eq "CUL_HM");#name is entity
  return "000000"            if($name eq "broadcast");        #broadcast
  return $defs{$1}->{DEF}.$2 if($name =~ m/(.*)_chn:(..)/);   #<devname> chn:xx
  return $name               if($name =~ m/^[A-F0-9]{6,8}$/i);#was already HMid
  return substr($idHash->{DEF},0,6).sprintf("%02X",$1) 
                             if($idHash && ($name =~ m/self(.*)/));
  return AttrVal($name,"hmId",""); # could be IO device
}
sub CUL_HM_id2Name($) { #in: name or HMid out: name
  my ($p) = @_;
  return $p                               if($defs{$p}||$p =~ m/_chn:/);
  my $devId= substr($p, 0, 6);
  return "broadcast"                      if($devId eq "000000"); 

  my $defPtr = $modules{CUL_HM}{defptr};
  if (length($p) == 8){
	return $defPtr->{$p}{NAME}            if($defPtr->{$p});#channel 
    return $defPtr->{$devId}{NAME}."_chn:".substr($p,6,2)   
	                                      if($defPtr->{$devId});#dev, add chn
    return $p;                               #not defined, return ID only
  }
  else{
    return $defPtr->{$devId}{NAME}        if($defPtr->{$devId});#device only
    return $devId;                           #not defined, return ID only
  }
}
sub CUL_HM_id2Hash($) {#in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if ($modules{CUL_HM}{defptr}{$id});
  return $modules{CUL_HM}{defptr}{substr($id,0,6)}; # could be chn 01 of dev
}
sub CUL_HM_getDeviceHash($) {#in: hash out: devicehash
  my ($hash) = @_;
  return $hash if(!$hash->{DEF});
  my $devHash = $modules{CUL_HM}{defptr}{substr($hash->{DEF},0,6)};
  return ($devHash)?$devHash:$hash;
}
sub CUL_HM_getDeviceName($) {#in: name out: name of device
  my $name = shift;
  return $name if(!$defs{$name});#unknown, return input
  my $devHash = $modules{CUL_HM}{defptr}{substr($defs{$name}{DEF},0,6)};
  return ($devHash)?$devHash->{NAME}:$name;
}

#+++++++++++++++++ debug ++++++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_DumpProtocol($$@) {
  my ($prefix, $iohash, $len,$cnt,$msgFlags,$mTp,$src,$dst,$p) = @_;
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
  $ps = $culHmBits{"$mTp;p11=$p11"} if(!$ps);
  $ps = $culHmBits{"$mTp;p01=$p01"} if(!$ps);
  $ps = $culHmBits{"$mTp;p02=$p02"} if(!$ps);
  $ps = $culHmBits{"$mTp"}          if(!$ps);
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
  my $msg ="$prefix L:$len N:$cnt F:$msgFlags CMD:$mTp SRC:$src DST:$dst $p$txt ($msgFlLong)";
  Log GetLogLevel($iname, 4), $msg;
  DoTrigger($iname, $msg) if($hmProtocolEvents > 2);
}

#+++++++++++++++++ handling register updates ++++++++++++++++++++++++++++++++++
sub CUL_HM_getRegFromStore($$$$@) {#read a register from backup data
  my($name,$regName,$list,$peerId,$regLN)=@_;
  my $hash = $defs{$name};
  my ($size,$pos,$conversion,$factor,$unit) = (8,0,"",1,""); # default
  my $addr = $regName;
  my $reg = $culHmRegDefine{$regName};
  if ($reg) { # get the register's information
    $addr = $reg->{a};
	$pos = ($addr*10)%10;
	$addr = int($addr);
    $list = $reg->{l};
	$size = $reg->{s};
	$size = int($size)*8 + ($size*10)%10;
	$conversion = $reg->{c}; #unconvert formula
	$factor = $reg->{f};
	$unit = " ".$reg->{u};
  }
  if(!$regLN){
    $regLN = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".")
              .sprintf("RegL_%02X:",$list)
			  .($peerId?CUL_HM_peerChName($peerId,
			                              substr(CUL_HM_name2Id($name),0,6),
										  CUL_HM_IOid($hash)):"");
  }
  $regLN =~ s/broadcast//;
  my $regLNp = $regLN;
  $regLNp =~s/^\.//; #remove leading '.' in case ..

  my $data=0;
  my $convFlg = "";# confirmation flag - indicates data not confirmed by device
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
	my ($dReadS,$dReadR) = (undef,"");
    $dReadS = $1 if(   $hash->{helper}{shadowReg}
	                && $hash->{helper}{shadowReg}{$regLNp}
					&& $hash->{helper}{shadowReg}{$regLNp} =~ m/$addrS:(..)/);
    $dReadR = $1 if(  $hash->{READINGS}{$regLN}
	                &&$hash->{READINGS}{$regLN}{VAL}      =~ m/$addrS:(..)/);	
    my $dRead = $dReadR;
	if (defined $dReadS){
	  $convFlg = "set_" if ($dReadR ne $dReadS);
	  $dRead = $dReadS;
	}
	else{
	  return "invalid" if (!defined($dRead) || $dRead eq "");
	}
    
	$data = ($data<< 8)+hex($dRead);
	$addr++;
  }

  $data = ($data>>$pos) & (0xffffffff>>(32-$size));
  if (!$conversion){                ;# do nothing
  } elsif($conversion eq "lit"     ){$data = $reg->{litInv}{$data}?$reg->{litInv}{$data}:"undef lit";
  } elsif($conversion eq "fltCvT"  ){$data = CUL_HM_CvTflt($data);
  } elsif($conversion eq "fltCvT60"){$data = CUL_HM_CvTflt60($data);
  } elsif($conversion eq "min2time"){$data = CUL_HM_min2time($data);
  } elsif($conversion eq "m10s3"   ){$data = ($data+3)/10;
  } elsif($conversion eq "hex"     ){$data = sprintf("0x%X",$data);
  } else { return " conversion undefined - please contact admin";
  } 
  $data /= $factor if ($factor);# obey factor after possible conversion
  return $convFlg.$data.$unit;
}
sub CUL_HM_updtRegDisp($$$) {
  my($hash,$list,$peerId)=@_;
  my $listNo = $list+0;
  my $name = $hash->{NAME};
  my $pReg = ($peerId && $peerId ne '00000000' )?
     CUL_HM_peerChName($peerId,substr($hash->{DEF},0,6),"")."-":"";
  $pReg=~s/:/-/;
  $pReg="R-".$pReg;
  my $devName =CUL_HM_getDeviceHash($hash)->{NAME};# devName as protocol entity
  my $st = $attr{$devName}{subType} ?$attr{$devName}{subType} :"";
  my $md = $attr{$devName}{model}   ?$attr{$devName}{model}   :"";
  my $chn = $hash->{DEF};
  $chn = (length($chn) == 8)?substr($chn,6,2):"";
  my @regArr = keys %culHmRegGeneral;
  push @regArr, keys %{$culHmRegType{$st}} if($culHmRegType{$st}); 
  push @regArr, keys %{$culHmRegModel{$md}} if($culHmRegModel{$md}); 
  push @regArr, keys %{$culHmRegChan{$md.$chn}} if($culHmRegChan{$md.$chn}); 
  my @changedRead;
  my $expL = CUL_HM_getAttrInt($name,"expert");
  my $expLvl = ($expL != 0)?1:0;
  my $regLN = (($expL == 2)?"":".")
              .sprintf("RegL_%02X:",$listNo)
			  .($peerId?CUL_HM_peerChName($peerId,
			                              substr(CUL_HM_name2Id($name),0,6),
										  CUL_HM_IOid($hash)):"");
  foreach my $rgN (@regArr){
    next if ($culHmRegDefine{$rgN}->{l} ne $listNo);
    my $rgVal = CUL_HM_getRegFromStore($name,$rgN,$list,$peerId,$regLN);	
	next if (!$rgVal || $rgVal eq "invalid");
	my $rdN = ((!$expLvl && !$culHmRegDefine{$rgN}->{d})?".":"").$pReg.$rgN;
	push (@changedRead,$rdN.":".$rgVal)
	      if (ReadingsVal($name,$rdN,"") ne $rgVal);
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  # ---  handle specifics -  Devices with abnormal or long register
  if ($md eq "HM-CC-TC"){#handle temperature readings
    CUL_HM_TCtempReadings($hash)  if (($list == 5 ||$list == 6) && 
                      substr($hash->{DEF},6,2) eq "02");
  }
  elsif ($md =~ m/HM-CC-RT-DN/){#handle temperature readings
    CUL_HM_RTtempReadings($hash)  if ($list == 7);
  }
  elsif ($md eq "HM-PB-4DIS-WM"){#add text
    CUL_HM_4DisText($hash)  if ($list == 1) ;
  }
  elsif ($st eq "repeater"){
    CUL_HM_repReadings($hash) if ($list == 2);
  }
#  CUL_HM_dimLog($hash) if(CUL_HM_Get($hash,$name,"param","subType") eq "dimmer");
}
sub CUL_HM_rmOldRegs($){ # remove register i outdated
  #will remove register for deleted peers
  my $name = shift;
  my $hash = $defs{$name};
  return if (!$hash->{peerList});# so far only peer-regs are removed
  my @pList = split",",$hash->{peerList};
  my @rpList;
  foreach(grep /^R-(.*)-/,keys %{$hash->{READINGS}}){
    push @rpList,$1 if ($_ =~m /^R-(.*)-/);
  }
  @rpList = CUL_HM_noDup(@rpList);
  return if (!@rpList);
  foreach my $peer(@rpList){
	next if($hash->{peerList} =~ m /\b$peer\b/);
	delete $hash->{READINGS}{$_} foreach (grep /^R-$peer-/,keys %{$hash->{READINGS}})
  }
}

#############################
#+++++++++++++++++ parameter cacculations +++++++++++++++++++++++++++++++++++++
my @culHmTimes8 = ( 0.1, 1, 5, 10, 60, 300, 600, 3600 );
sub CUL_HM_encodeTime8($) {#####################
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
sub CUL_HM_decodeTime8($) {#####################
  my $v = hex(shift);
  return "undef" if($v > 255);
  my $v1 = int($v/32);
  my $v2 = $v%32;
  return $v2 * $culHmTimes8[$v1];
}
sub CUL_HM_encodeTime16($) {####################
  my $v = shift;
  return "0000" if($v < 0.05 || $v !~ m/^[+-]?\d+(\.\d+)?$/);

  my $ret = "FFFF";
  my $mul = 10;
  for(my $i = 0; $i < 32; $i++) {
    if($v*$mul < 0x7ff) {
      $ret=sprintf("%04X", ((($v*$mul)<<5)+$i));
      last;
    }
    $mul /= 2;
  }
  return ($ret);
}
sub CUL_HM_convTemp($) {########################
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
sub CUL_HM_decodeTime16($) {####################
  my $v = hex(shift);
  my $m = int($v>>5);
  my $e = $v & 0x1f;
  my $mul = 0.1;
  return 2^$e*$m*0.1;
}
sub CUL_HM_secSince2000() {#####################
  # Calculate the local time in seconds from 2000.
  my $t = time();

  my @l = localtime($t);
  my @g = gmtime($t);
  my $t2 = $t + 60*(($l[2]-$g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1]-$g[1]) 
                           # timezone and daylight saving...
        - 946684800        # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
        - 7200;            # HM Special
  return $t2;
}
sub CUL_HM_getChnLvl($){# in: name out: vit or phys level
  my $name = shift;
  my $curVal = ReadingsVal($name,"level",undef);
  $curVal = ReadingsVal($name,".level",0)if (!defined $curVal);
  $curVal =~ s/set_//;
  $curVal =~ s/ .*//;#strip unit
  return $curVal;
}

#--------------- Conversion routines for register settings---------------------
sub CUL_HM_initRegHash() { #duplicate short and long press register 

  foreach my $reg (keys %culHmRegDefShLg){ #update register list
    %{$culHmRegDefine{"sh".$reg}} = %{$culHmRegDefShLg{$reg}};
    %{$culHmRegDefine{"lg".$reg}} = %{$culHmRegDefShLg{$reg}};
	$culHmRegDefine{"lg".$reg}{a} +=0x80;
  }
  foreach my $rN (keys %culHmRegDefine){#create literal inverse for fast search
    if ($culHmRegDefine{$rN}{lit}){# literal assigned => create inverse
	  foreach my $lit (keys %{$culHmRegDefine{$rN}{lit}}){
	    $culHmRegDefine{$rN}{litInv}{$culHmRegDefine{$rN}{lit}{$lit}}=$lit;
	  }
	}
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

my %fltCvT60 = (1=>127,60=>7620);
sub CUL_HM_fltCvT60($) { # float -> config time
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT60){
    $div2 = $div;
	last if ($inValue < $fltCvT60{$div});
	$exp++;
  }
  return ($exp << 7)+int($inValue/$div2+.1);
}
sub CUL_HM_CvTflt60($) { # config time -> float
  my ($inValue) = @_;
  return ($inValue & 0x7f)*((sort {$a <=> $b} keys(%fltCvT60))[$inValue >> 7]);
}

my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111601);
sub CUL_HM_fltCvT($) { # float -> config time
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT){
    $div2 = $div;
	last if ($inValue < $fltCvT{$div});
	$exp++;
  }
  return ($exp << 5)+int($inValue/$div2+.1);
}
sub CUL_HM_CvTflt($) { # config time -> float
  my ($inValue) = @_;
  return ($inValue & 0x1f)*((sort {$a <=> $b} keys(%fltCvT))[$inValue >> 5]);
}
sub CUL_HM_min2time($) { # minutes -> time
  my $min = shift;
  $min = $min * 30;
  return sprintf("%02d:%02d",int($min/60),$min%60);
}
sub CUL_HM_time2min($) { # minutes -> time
  my $time = shift;
  my ($h,$m) = split ":",$time;
  $m = ($h*60 + $m)/30;
  $m = 0 if($m < 0);
  $m = 47 if($m > 47);
  return $m;
}

sub CUL_HM_4DisText($) {      # convert text for 4dis
  #text1: start at 54 (0x36) length 12 (0x0c)
  #text2: start at 70 (0x46) length 12 (0x0c)
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my $reg1 = ReadingsVal($name,$regPre."RegL_01:" ,"");
  my $pref = "";
  if ($hash->{helper}{shadowReg}{"RegL_01:"}){
    $pref = "set_";
    $reg1 = $hash->{helper}{shadowReg}{"RegL_01:"};
  }
  my %txt;
  foreach my $sAddr (54,70){
    my $txtHex = $reg1;  #one row
	my $sStr = sprintf("%02X:",$sAddr);
    $txtHex =~ s/.* $sStr//;       #remove reg prior to string
	$sStr = sprintf("%02X:",$sAddr+11);
    $txtHex =~ s/$sStr(..).*/,$1/; #remove reg after string
    $txtHex =~ s/ ..:/,/g;         #remove addr 
    $txtHex =~ s/,00.*//;          #remove trailing string
    my @ch = split(",",$txtHex,12);
    foreach (@ch){$txt{$sAddr}.=chr(hex($_))};
  }  
  CUL_HM_UpdtReadBulk($hash,1,"text1:".$pref.$txt{54},
                              "text2:".$pref.$txt{70});
  return "text1:".$txt{54}."\n".
         "text2:".$txt{70}."\n";
}
sub CUL_HM_TCtempReadings($) {# parse TC temperature readings
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my $reg5 = ReadingsVal($name,$regPre."RegL_05:" ,"");
  my $reg6 = ReadingsVal($name,$regPre."RegL_06:" ,"");

  if (ReadingsVal($name,"R-controlMode","") =~ m/^party/){
    if (   $reg6                # ugly handling to add vanishing party register
        && $reg6 !~ m/ 61:/ 
        && $hash->{helper}{partyReg}){
      $hash->{READINGS}{"RegL_06:"}{VAL} =~s/ 00:00/$hash->{helper}{partyReg}/;
    }
   }
  else{
    delete $hash->{helper}{partyReg};
  }

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
                (($hash->{helper}{shadowReg}{"RegL_05:"} ||
				  $hash->{helper}{shadowReg}{"RegL_06:"} )?"set":"verified"));
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
  { #update readings in device - oldfashioned style, copy from Readings
    my @histVals;
    foreach my $var ("displayMode","displayTemp","controlMode","decalcDay","displayTempUnit","day-temp","night-temp","party-temp"){
	  push @histVals,$var.":".ReadingsVal($name,"R-".$var,"???");
    }
    CUL_HM_UpdtReadBulk(CUL_HM_getDeviceHash($hash),1,@histVals) if (@histVals);
  }
  return $setting;
}
sub CUL_HM_RTtempReadings($) {# parse RT temperature readings
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my $tempRegs = ReadingsVal($name,$regPre."RegL_07:","");
  my $stmpRegs = ($hash->{helper}{shadowReg}{"RegL_07:"})? # need to compare actual data
                   ($hash->{helper}{shadowReg}{"RegL_07:"})
				   :$tempRegs;
  return "reglist incomplete\n" if ($tempRegs !~ m/00:00/);
  
  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");

  $tempRegs =~ s/.* 14://;     #remove register up to addr 20 from list
  $tempRegs =~ s/ 00:00/ /g;   #remove regline termination
  $tempRegs =~ s/ ..://g;      #remove addr Info
  $tempRegs =~ s/ //g;         #blank
  
  $stmpRegs =~ s/.* 14://;     
  $stmpRegs =~ s/ 00:00/ /g;   
  $stmpRegs =~ s/ ..://g;      
  $stmpRegs =~ s/ //g;         

  my $setting;
  my @changedRead;
  push (@changedRead,"tempList_State:".
                ($hash->{helper}{shadowReg}{"RegL_07:"} ?"set":"verified"));
  for (my $day = 0;$day<7;$day++){
	my $dayRead = "";
	my $pre ="";
    my @time;
    my @temp;
    my $str;
	if (substr($stmpRegs,$day *13*4,13*4) eq 
	    substr($tempRegs,$day *13*4,13*4)   ){
	  $str = substr($tempRegs,$day *13*4,13*4);
	}
	else{
	  $str = substr($stmpRegs,$day *13*4,13*4);
	  $pre = "set_";
	}
    foreach (unpack '(A4)*',$str){
      my $h = hex($_);
	  push @temp,($h >> 9)/2;
	  $h = ($h & 0x1ff) * 5;
	  $h = sprintf("%02d:%02d",int($h / 60),($h%60));
      push @time,$h;
    }

    for (my $idx = 0;$idx<13;$idx++){
	  my $entry = sprintf(" %s %3.01f",$time[$idx],$temp[$idx]);
  	  $setting .= "Temp set: ".$days[$day].$entry." C\n";
  	  $dayRead .= $entry;
      last if ($time[$idx] eq "24:00");
    }
	push (@changedRead,"tempList".$days[$day].":".$pre." ".$dayRead);
  }  
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  # transport some readings to relevant channels (window receivce here)
  my $wHash = $modules{CUL_HM}{defptr}{substr($hash->{DEF},0,6)."03"};
  CUL_HM_UpdtReadBulk($wHash,1,
        "R-winOpnTemp:"  .ReadingsVal($name,"R-winOpnTemp"  ,"unknown"),
        "R-winOpnPeriod:".ReadingsVal($name,"R-winOpnPeriod","unknown"),
        "R-winOpnBoost:" .ReadingsVal($name,"R-winOpnBoost" ,"unknown"),
		"R-winOpnMode:"  .ReadingsVal($name,"R-winOpnMode"  ,"unknown"),
		"R-winOpnDetFall:".ReadingsVal($name,"R-winOpnDetFall"  ,"unknown"),);
  return $setting;
}
sub CUL_HM_repReadings($) {   # parse repeater 
  my ($hash)=@_;
  my %pCnt;
  my $cnt = 0;
  return "" if (!$hash->{helper}{peerIDsRaw});
  foreach my$pId(split',',$hash->{helper}{peerIDsRaw}){
    next if (!$pId || $pId eq "00000000");
	$pCnt{$pId.$cnt}{cnt}=$cnt++;
  }

  my @pS;
  my @pD;
  my @pB;  
  foreach (split",",(AttrVal($hash->{NAME},"repPeers",undef))){
    my ($s,$d,$b) = split":",$_;
	push @pS,$s;
	push @pD,$d;
	push @pB,$b;
  }
  my @readList;
  push @readList,"repPeer_$_:undefined" for(0..35);#set default empty

  my @retL;
  foreach my$pId(sort keys %pCnt){
	my ($pdID,$bdcst,$no) = unpack('A6A2A2',$pId);
	my $fNo = $no-1;#shorthand field number, often used
	my $sName = CUL_HM_id2Name($pdID);
	
	if ($sName eq $pdID && $pD[$fNo]){
	  $sName = $defs{$pD[$fNo]}->{IODev}{NAME}
	        if($attr{$defs{$pD[$fNo]}->{IODev}{NAME}}{hmId} eq $pdID);
	}
	my $eS = sprintf("%02d %-15s %-15s %-3s %-4s",
	           $no
			  ,$sName
		      ,((!$pS[$fNo] || $pS[$fNo] ne $sName)?"unknown":" dst>$pD[$fNo]")
		      ,($bdcst eq "01"?"yes":"no ")
	          ,($pB[$fNo] && (  ($bdcst eq "01" && $pB[$fNo] eq "y")
			                  ||($bdcst eq "00" && $pB[$fNo] eq "n")) ?"ok":"fail")
			  );
	push @retL, $eS;
	$readList[$fNo]=sprintf("repPeer_%02d:%s",$no,$eS);
  }
  CUL_HM_UpdtReadBulk($hash,0,@readList);
  return "No Source          Dest            Bcast\n". join"\n", sort @retL;
}
sub CUL_HM_dimLog($) {# dimmer readings - support virtual chan - unused so far
  my ($hash)=@_;
  my $lComb = CUL_HM_Get($hash,$hash->{NAME},"reg","logicCombination");
  return if (!$lComb);
  my %logicComb=(					                                                                                  
		              inactive=>{calc=>'$val=$val'                                      ,txt=>'unused'},
                      or      =>{calc=>'$val=$in>$val?$in:$val'                         ,txt=>'max(state,chan)'},
					  and     =>{calc=>'$val=$in<$val?$in:$val'                         ,txt=>'min(state,chan)'},
					  xor     =>{calc=>'$val=!($in!=0&&$val!=0)?($in>$val?$in:$val): 0' ,txt=>'0 if both are != 0, else max'},
					  nor     =>{calc=>'$val=100-($in>$val?$in : $val)'                 ,txt=>'100-max(state,chan)'},
					  nand    =>{calc=>'$val=100-($in<$val?$in : $val)'                 ,txt=>'100-min(state,chan)'},
					  orinv   =>{calc=>'$val=(100-$in)>$val?(100-$in) : $val'           ,txt=>'max((100-chn),state)'},
					  andinv  =>{calc=>'$val=(100-$in)<$val?(100-$in) : $val'           ,txt=>'min((100-chn),state)'},
					  plus    =>{calc=>'$val=($in + $val)<100?($in + $val) : 100'       ,txt=>'state + chan'},
					  minus   =>{calc=>'$val=($in - $val)>0?($in + $val) : 0'           ,txt=>'state - chan'},
					  mul     =>{calc=>'$val=($in * $val)<100?($in + $val) : 100'       ,txt=>'state * chan'},
					  plusinv =>{calc=>'$val=($val+100-$in)<100?($val+100-$in) : 100'   ,txt=>'state + 100 - chan'},
					  minusinv=>{calc=>'$val=($val-100+$in)>0?($val-100+$in) : 0'       ,txt=>'state - 100 + chan'},
					  mulinv  =>{calc=>'$val=((100-$in)*$val)<100?(100-$in)*$val) : 100',txt=>'state * (100 - chan)'},
					  invPlus =>{calc=>'$val=(100-$val-$in)>0?(100-$val-$in) : 0'       ,txt=>'100 - state - chan'},
					  invMinus=>{calc=>'$val=(100-$val+$in)<100?(100-$val-$in) : 100'   ,txt=>'100 - state + chan'},
					  invMul  =>{calc=>'$val=(100-$val*$in)>0?(100-$val*$in) : 0'       ,txt=>'100 - state * chan'},
					  );
  readingsSingleUpdate($hash,"R-logicCombTxt" ,$logicComb{$lComb}{txt},0);
  readingsSingleUpdate($hash,"R-logicCombCalc",$logicComb{$lComb}{calc},0);
  return "";
}

#+++++++++++++++++ Action Detector ++++++++++++++++++++++++++++++++++++++++++++
# verify that devices are seen in a certain period of time
# It will generate events if no message is seen sourced by the device during 
# that period.
# ActionDetector will use the fixed HMid 000000
sub CUL_HM_ActGetCreateHash() {# get ActionDetector - create if necessary
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
  no warnings 'numeric';
  $h = int($h);
  $m = int($m);
  use warnings 'numeric';
  return ((sprintf("%03s:%02d",$h,$m)),((int($h)*60+int($m))*60));
}
sub CUL_HM_ActAdd($$) {# add an HMid to list for activity supervision
  my ($devId,$timeout) = @_; #timeout format [hh]h:mm
  $timeout = 0 if (!$timeout);
  return $devId." is not an HM device - action detection cannot be added"
       if (length($devId) != 6);
  my ($cycleString,undef)=CUL_HM_time2sec($timeout);
  my $devName = CUL_HM_id2Name($devId);
  my $devHash = $defs{$devName};
  
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
    my $eName = $ehash->{NAME};
	next if (!$eName);
    foreach my $rName (keys %{$ehash->{READINGS}}){
      next if (!$rName            ||
	         $rName eq "PairedTo" ||                     # derived
	         $rName eq "peerList" ||                     # derived
	         $rName eq "Activity" ||                     # derived
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
  my @event;
  my ($cntUnkn,$cntAlive,$cntDead,$cntOff) =(0,0,0,0);
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
	if(!$devName || !defined($attr{$devName}{actCycle})){
	  CUL_HM_ActDel($devId); 
	  next;
	}
    my $devHash = $defs{$devName};
	my $state;
	my $oldState = AttrVal($devName,"actStatus","unset");
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
	if ($tSec == 0){# detection switched off
	  $cntOff++;
	  $state = "switchedOff";
	}
	else{
	  $actHash->{helper}{$devId}{recent} = ($devHash->{"protLastRcv"})?#update recent
	                                        $devHash->{"protLastRcv"} 
											:0;
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
	  readingsSingleUpdate($devHash,"Activity",$state,1);
	  $attr{$devName}{actStatus} = $state;
	  Log 4,"Device ".$devName." is ".$state;
	}
    push @event, "status_".$devName.":".$state;
  }
  push @event, "state:"."alive:".$cntAlive
                       ." dead:".$cntDead
                       ." unkn:".$cntUnkn
                       ." off:" .$cntOff;

  my $allState = join " ",@event;# search and remove outdated readings
  foreach (keys %{$actHash->{READINGS}}){
    delete $actHash->{READINGS}{$_} if ($allState !~ m/$_:/);
  }

  CUL_HM_UpdtReadBulk($actHash,1,@event);
  
  $attr{$actName}{actCycle} = 600 if($attr{$actName}{actCycle}<30); 
  $actHash->{helper}{actCycle} = $attr{$actName}{actCycle};
  InternalTimer(gettimeofday()+$attr{$actName}{actCycle}, 
  								   "CUL_HM_ActCheck", "ActionDetector", 0);
}

#+++++++++++++++++ helper +++++++++++++++++++++++++++++++++++++++++++++++++++++
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
  return $hash->{NAME};
}
sub CUL_HM_UpdtReadSingle(@) { #update single reading and trigger the event
  my ($hash,$rName,$val,$updt) = @_; 
  readingsSingleUpdate($hash,$rName,$val,$updt);
  return $hash->{NAME};
}
sub CUL_HM_setAttrIfCh($$$$) {
  my ($name,$att,$val,$trig) = @_; 
  if($attr{$name}{$att} ne $val){
    DoTrigger($name,$trig.":".$val) if($trig);
	$attr{$name}{$att} = $val;
  }
}
sub CUL_HM_noDup(@) {#return list with no duplicates
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep !/^$/,@_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}
sub CUL_HM_noDupInString($) {#return string with no duplicates, comma separated
  my ($str) = @_;
  return join ",",CUL_HM_noDup(split ",",$str);
}
sub CUL_HM_storeRssi(@){
  my ($name,$peerName,$val) = @_;
  return if (!$val);
  $defs{$name}{helper}{rssi}{$peerName}{lst} = $val;
  my $rssiP = $defs{$name}{helper}{rssi}{$peerName};
  $rssiP->{min} = $val if (!$rssiP->{min} || $rssiP->{min} > $val);
  $rssiP->{max} = $val if (!$rssiP->{max} || $rssiP->{max} < $val);
  $rssiP->{cnt} ++;
  if ($rssiP->{cnt} == 1){
    $rssiP->{avg} = $val;
  }
  else{
    $rssiP->{avg} += ($val - $rssiP->{avg}) /$rssiP->{cnt};
  }
  my $hash = $defs{$name};
  my $rssi;
  foreach (keys %{$rssiP}){
    my $val = $rssiP->{$_}?$rssiP->{$_}:0;
	$rssi .= $_.":".(int($val*100)/100)." ";
  }  
  $hash->{"rssi_".$peerName} = $rssi;
 return ;
}

sub CUL_HM_stateUpdatDly($$){#delayed queue of status-request
  my ($name,$time) = @_;
  CUL_HM_unQEntity($name,"qReqStat");#remove requests, wait for me.
  RemoveInternalTimer("sUpdt:$name");
  InternalTimer(gettimeofday()+$time,"CUL_HM_qStateUpdatIfEnab","sUpdt:$name",0);
}
sub CUL_HM_qStateUpdatIfEnab($@){#in:name or id, queue stat-request after 12 s
  my ($name,$force) = @_;
  $name = substr($name,6) if ($name =~ m/^sUpdt:/);
  $name = CUL_HM_id2Name($name) if ($name =~ m/^[A-F0-9]{6,8}$/i);
  $name =~ s /_chn:..$//;
  return if (!$defs{$name}); #device unknown, ignore
  if ($force || ((CUL_HM_getAttrInt($name,"autoReadReg") & 0x0f) > 3)){
    CUL_HM_qEntity($name,"qReqStat") ;
  }
}
sub CUL_HM_qAutoRead($$){
  my ($name,$lvl) = @_;
  return if (!$defs{$name}
             ||$lvl >= (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
  CUL_HM_qEntity($name,"qReqConf");
}
sub CUL_HM_unQEntity($$){# remove entity from q 
  my ($name,$q) = @_;
  
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  my $dq = $defs{$devN}{helper}{q};
  return if ($dq->{$q} eq "");

  if ($devN eq $name){#all channels included
    $dq->{$q}=""; 
  }
  else{
    my @chns = split(",",$dq->{$q});
	my $chn = substr(CUL_HM_name2Id($name),6,2);
	@chns = grep !/$chn/,@chns;
	$dq->{$q} = join",",@chns;
  }
  my $mQ = $q."Wu" if (CUL_HM_getRxType($defs{$name}) & 0x1C);
  $mQ = $modules{CUL_HM}{helper}{$q};  
  @{$mQ} = grep !/^$devN$/,@{$mQ} if ($dq->{$q} eq "");
  RemoveInternalTimer("sUpdt:$name") if ($q eq "qReqStat");#remove delayed
}
sub CUL_HM_qEntity($$){  # add to queue
  my ($name,$q) = @_;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  return if ($defs{$devN}{helper}{q}{$q} eq "00"); #already requesting all
  if ($devN eq $name){#config for all device
    $defs{$devN}{helper}{q}{$q}="00"; 
  }
  else{
	$defs{$devN}{helper}{q}{$q} = CUL_HM_noDupInString(
	                                  $defs{$devN}{helper}{q}{$q}
	                                  .",".substr(CUL_HM_name2Id($name),6,2));
  }

  $q .= "Wu" if (CUL_HM_getRxType($defs{$name}) & 0x1C);#normal or wakeup q?
  $q = $modules{CUL_HM}{helper}{$q};
  @{$q} = CUL_HM_noDup(@{$q},$devN);

  my $wT = (@{$modules{CUL_HM}{helper}{qReqStat}})?
                              "1":
							  $modules{CUL_HM}{hmAutoReadScan};
  RemoveInternalTimer("CUL_HM_procQs");
  InternalTimer(gettimeofday()+ $wT,"CUL_HM_procQs","CUL_HM_procQs", 0);
}

sub CUL_HM_procQs($){#process non-wakeup queues
  # --- verify send is possible

  my $mq = $modules{CUL_HM}{helper};
  foreach my $q ("qReqStat","qReqConf"){
    if   (@{$mq->{$q}}){
	  my $devN = ${$mq->{$q}}[0]; 
	  my $ioName = $defs{$devN}{IODev}{NAME};
	  if (   (   ReadingsVal($ioName,"cond","") =~ m /^(ok|Overload-released|init)$/
	          && $q eq "qReqStat")
		   ||(   CUL_HM_autoReadReady($ioName)
	          && $q eq "qReqConf")){
        my $dq = $defs{$devN}{helper}{q};
        my @chns = split(",",$dq->{$q});
	    if (@chns > 1){$dq->{$q} = join ",",@chns[1..@chns];}
	    else{          $dq->{$q} = "";
	                   @{$mq->{$q}} = grep !/^$devN$/,@{$mq->{$q}};
	    }
		my $dId = CUL_HM_name2Id($devN);
	    my $eN=($chns[0]ne "00")?CUL_HM_id2Name($dId.$chns[0]):$devN;
		if ($q eq "qReqConf"){
          $mq->{autoRdActive} = $devN;
	      CUL_HM_Set($defs{$eN},$eN,"getConfig");
		}
		else{
 	      CUL_HM_Set($defs{$eN},$eN,"statusRequest");
		}
	  }
	  last; # execute only one!
    }
  }

  delete $mq->{autoRdActive} 
        if ($mq->{autoRdActive} &&
            $defs{$mq->{autoRdActive}}{helper}{prt}{sProc} != 1);
  my $next;# how long to wait for next timer
  if    (@{$mq->{qReqStat}}){$next = 1}
  elsif (@{$mq->{qReqConf}}){$next = $modules{CUL_HM}{hmAutoReadScan}}
  
  InternalTimer(gettimeofday()+$next,"CUL_HM_procQs","CUL_HM_procQs",0)
      if ($next); 
}
sub CUL_HM_appFromQ($$){#stack commands if pend in WuQ 
  my ($name,$reason) = @_;
  my $devN = CUL_HM_getDeviceName($name); 
  my $dId = CUL_HM_name2Id($devN);
  my $dq = $defs{$devN}{helper}{q};
  if ($reason eq "cf"){# reason is config. add all since User has control
    foreach my $q ("qReqStat","qReqConf"){
      if ($dq->{$q} ne ""){# need update
 	    my @eName;
	    if ($dq->{$q} eq "00"){
		  push @eName,$devN;
		}
		else{
          my @chns = split(",",$dq->{$q});
	      push @eName,CUL_HM_id2Name($dId.$_)foreach (@chns);
		}
	    $dq->{$q} = "";
	    @{$modules{CUL_HM}{helper}{$q."Wu"}} = 
	                grep !/^$devN$/,@{$modules{CUL_HM}{helper}{$q."Wu"}};
        foreach my $eN(@eName){
          next if (!$eN);
	      CUL_HM_Set($defs{$eN},$eN,"getConfig")     if ($q eq "qReqConf");
	      CUL_HM_Set($defs{$eN},$eN,"statusRequest") if ($q eq "qReqStat");
        }
	  }
	}
  }
  elsif($reason eq "wu"){#wakeup - just add one step
    my $ioName = $defs{$devN}{IODev}{NAME};
    return if (!CUL_HM_autoReadReady($ioName));# no sufficient performance 
    foreach my $q ("qReqStat","qReqConf"){
	  if ($dq->{$q} ne ""){# need update
        my @chns = split(",",$dq->{$q});
	    my $nOpen = scalar @chns;
	    if ($nOpen > 1){$dq->{$q} = join ",",@chns[1..$nOpen];}
	    else{           $dq->{$q} = "";
	                  @{$modules{CUL_HM}{helper}{$q."Wu"}} = 
	                     grep !/^$devN$/,@{$modules{CUL_HM}{helper}{$q."Wu"}};
	    }
	    my $eN=($chns[0]ne "00")?CUL_HM_id2Name($dId.$chns[0]):$devN;
	    CUL_HM_Set($defs{$eN},$eN,"getConfig")     if ($q eq "qReqConf");
	    CUL_HM_Set($defs{$eN},$eN,"statusRequest") if ($q eq "qReqStat");
		return;# Only one per step - very defensive. 
	  }
	}
  }
}
sub CUL_HM_autoReadReady($){# capacity for autoread available?
  my $ioName = shift;
  my $mHlp = $modules{CUL_HM}{helper};
  if (   $mHlp->{autoRdActive}  # predecessor available
      && $defs{$mHlp->{autoRdActive}}){
    return 0 if ($defs{$mHlp->{autoRdActive}}{helper}{prt}{sProc} == 1); # predecessor still on
  }
  if (  ReadingsVal($ioName,"cond","") !~ m /^(ok|Overload-released|init)$/
	  || (    $defs{$ioName}{helper}{q}
		  && ($defs{$ioName}{helper}{q}{cap}{sum}/16.8)>
		       AttrVal($ioName,"hmMsgLowLimit",40))){
	return 0;
  }
  return 1;
}

sub CUL_HM_getAttrInt($@){#return attrValue as integer
  my ($name,$attrName,$default) = @_;
  my $val = $attr{$name}{$attrName}?$attr{$name}{$attrName}:"";
  no warnings 'numeric';
  my $devN = $defs{$name}{device}?$defs{$name}{device}:$name;
  $default = 0 if (!defined $default);
  $val = int($attr{$devN}{$attrName}?$attr{$devN}{$attrName}:$default)+0 
        if($val eq "");
  use warnings 'numeric';
  return substr($val,0,1);
}

#+++++++++++++++++ external use +++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_putHash($) {# provide data for HMinfo
  my ($info) = @_;
  return %culHmModel if ($info eq "culHmModel");
}

sub CUL_HM_peerUsed($) {# are peers expected?
  my $name = shift;
  my $hash = $defs{$name};
  return 0 if (!$hash->{helper}{role}{chn});#device has no channels
  my $devId = substr($hash->{DEF},0,6);
  my $peerIDs = AttrVal($name,"peerIDs",undef);
  return 0 if (AttrVal(CUL_HM_id2Name($devId),"subType","") eq "virtual"); 
	  
  my $mId = CUL_HM_getMId($hash);
  my $cNo = hex(substr($hash->{DEF}."01",6,2))."p"; #default to channel 01
  return 0 if (!$mId || !$culHmModel{$mId});
  foreach my $ls (split ",",$culHmModel{$mId}{lst}){
	my ($l,$c) = split":",$ls;
    if (  ($l =~ m/^(p|3|4)$/ && !$c )  # 3,4,p without chanspec
		||($c && $c =~ m/$cNo/       )){   
	  return 1;
	}
  }
}
sub CUL_HM_peersValid($) {# is list valid?
  my $name = shift;
  if (CUL_HM_peerUsed($name)
      && AttrVal($name,"peerIDs","") !~ m/00000000/){
	return 0;
  }
  return 1;
}

sub CUL_HM_reglUsed($) {# provide data for HMinfo
  my $name = shift;
  my $hash = $defs{$name};
  my $devId = substr($hash->{DEF},0,6);
  my $chn   = substr($hash->{DEF}."01",6,2);
  return undef if (AttrVal(CUL_HM_id2Name($devId),"subType","") eq "virtual"); 

  my @pNames;
  push @pNames,CUL_HM_peerChName($_,$devId,"") 
             foreach (grep !/00000000/,split(",",AttrVal($name,"peerIDs","")));
			 
  my @lsNo;
  my $mId = CUL_HM_getMId($hash);
  return undef if (!$mId || !$culHmModel{$mId});
  if ($hash->{helper}{role}{dev}){
    push @lsNo,"0:";
  }
  elsif ($hash->{helper}{role}{chn}){
	
	foreach my $ls (split ",",$culHmModel{$mId}{lst}){
	  my ($l,$c) = split":",$ls;
	  if ($l ne "p"){# ignore peer-only entries
		if ($c){
		  my $chNo = hex($chn);
		  if   ($c =~ m/($chNo)p/){push @lsNo,"$l:$_" foreach (@pNames);}
		  elsif($c =~ m/$chNo/   ){push @lsNo,"$l:";}
		}
		else{
		  if ($l == 3 || $l == 4){push @lsNo,"$l:$_" foreach (@pNames);
		  }else{                  push @lsNo,"$l:" ;}
		}
	  }
	}
  }
  my $pre = (CUL_HM_getAttrInt($name,"expert") == 2)?"":".";
  
  $_ = $pre."RegL_0".$_ foreach (@lsNo);
  return @lsNo;
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
	 <li><B>clear &lt;[readings|register|msgEvents]&gt;</B><a name="CUL_HMclear"></a><br>
         A set of variables can be removed.<br>
		 <ul>
		 readings: all readings will be deleted. Any new reading will be added usual. May be used to eliminate old data<br>
		 register: all captured register-readings in FHEM will be removed. This has NO impact to the values in the device.<br>
		 msgEvents:  all message event counter will be removed. Also commandstack will be cleared. <br>
		 rssi:  collected rssi values will be cleared. <br>
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
        the 'internal links' it is necessary to issue <br>
		'set &lt;name&gt; <a href="#CUL_HMregSet">regSet</a> intKeyVisib visib'<br>
		or<br> 
		'set &lt;name&gt; <a href="#CUL_HMregBulk">regBulk</a> RegL_0: 2:81'<br> 
		
		Reset it by replacing '81' with '01'<br> example:<br>

	  <ul><code>
	    set mydimmer getRegRaw List1<br>
	    set mydimmer getRegRaw List3 all <br>
	  </code></ul>
	  </li>
 	  <li><B>getSerial</B><a name="CUL_HMgetSerial"></a><br>
         Read serial number from device and write it to attribute serialNr.
	  </li>
	  <li><B>inhibit [on|off]</B><br>
         Block / unblock all changes to the actor channel, i.e. actor state is frozen 
		 until inhibit is set off again. Inhibit can be executed on any actor channel 
		 but obviously not on sensors - would not make any sense.<br>
		 Practically it can be used to suspend any notifies as well as peered channel action 
		 temporarily without the need to delete them. <br>
         Examples:
         <ul><code>
           # Block operation<br>
           set keymatic inhibit on <br><br>
        </ul></code>  
      </li>

     <li><B>pair</B><a name="CUL_HMpair"></a><br>
         Pair the device with a known serialNumber (e.g. after a device reset) 
		 to FHEM Central unit. FHEM Central is usualy represented by CUL/CUNO, 
		 HMLAN,...
		 If paired, devices will report status information to
         FHEM. If not paired, the device won't respond to some requests, and
         certain status information is also not reported.  Paring is on device
         level. Channels cannot be paired to central separate from the device. 
		 See also <a href="#CUL_HMgetpair">getPair</a>  and 
		 <a href="#CUL_HMunpair">unpair</a>.<br>
		 Don't confuse pair (to a central) with peer (channel to channel) with
		 <a href="#CUL_HMpeerChan">peerChan</a>.<br>
	 </li>
     <li><B>peerBulk</B> &lt;peerch1,peerch2,...&gt; [set|unset]<a name="CUL_HMpeerBulk"></a><br>
	     peerBulk will add peer channels to the channel. All peers in the 
		 list will be added. <br>
		 peering sets the configuration of this link to its defaults. As peers are not 
		 added in pairs default will be as defined for 'single' by HM for this device. <br> 
		 More suffisticated funktionality is provided by
		 <a href="#CUL_HMpeerChan">peerChan</a>.<br>
		 peerBulk will not delete existing peers, just handle the given peerlist. 
		 Other already installed peers will not be touched.<br>
		 peerBulk may be used to remove peers using <B>unset</B> option while default ist set.<br>
		 
		 Main purpose of this command is to re-store data to a device. 
		 It is recommended to restore register configuration utilising
		 <a href="#CUL_HMregBulk">regBulk</a> subsequent. <br>
	 Example:<br>
	 <ul><code>
	 set myChannel peerBulk 12345601,<br>
	 set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
	 set myChannel peerBulk 12345601 unset # remove peer 123456 channel 01<br>
	 </code></ul>
	 </li>
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
     <li><B>regSet [prep|exec] &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><a name="CUL_HMregSet"></a><br>
        For some major register a readable version is implemented supporting
        register names &lt;regName&gt; and value conversionsing. Only a subset
        of register can be supproted.<br>
		Optional parameter [prep|exec] allowes to pack the messages and therefore greatly 
		improve data transmission.
		Usage is to send the commands with paramenter "prep". The data will be accumulated for send. 
		The last command must have the parameter "exec" in order to transmitt the information.<br>

        &lt;value&gt; is the data in human readable manner that will be written
        to the register.<br>
        &lt;peerChannel&gt; is required if this register is defined on a per
        'peerChan' base. It can be set to '0' other wise.See <a
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
            set vRemote_Btn4 peerChan 0 &lt;actorchannel&gt;  # peers Button 4 and 5 to the given channel<br>
            set vRemote_Btn4 press<br>
            set vRemote_Btn5 press long<br>
        </code></ul>
         see also <a href="#CUL_HMpress">press</a>
	 </li>
     </ul>

     <br>
     <B>subType dependent commands:</B>
     <ul>
     <br>
    <li>switch
       <ul>
          <li><B>on</B> <a name="CUL_HMon"> </a> - set level to 100%</li>
          <li><B>off</B><a name="CUL_HMoff"></a> - set level to 0%</li>
          <li><B>on-for-timer &lt;sec&gt;</B><a name="CUL_HMonForTimer"></a> -
              set the switch on for the given seconds [0-85825945].<br> Note:
              off-for-timer like FS20 is not supported. It may to be programmed
              thru channel register.</li>
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
          <li><B>toggle</B><a name="CUL_HMtoggle"></a> - toggle the Actor. It will switch from any current 
		         level to off or from off to 100%</li>
       </ul>
     <br>
	 </li>
    <li>dimmer, blindActuator<br>
	   Dimmer may support virtual channels. Those are autocrated if applicable. Usually there are 2 virtual channels
	   in addition to the primary channel. Virtual dimmer channels are inactive by default but can be used in 
	   in parallel to the primay channel to control light. <br>
	   Virtual channels have default naming SW&lt;channel&gt;_V&lt;no&gt;. e.g. Dimmer_SW1_V1 and Dimmer_SW1_V2.<br>
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
         <li><B><a href="#CUL_HMon">on</a></B></li>
         <li><B><a href="#CUL_HMoff">off</a></B></li>
         <li><B><a href="#CUL_HMpress">press &lt;[short|long]&gt;&lt;[on|off]&gt;</a></B></li>
         <li><B><a href="#CUL_HMtoggle">toggle</a></B></li>
         <li><B><a href="#CUL_HMonForTimer">on-for-timer &lt;sec&gt;</a></B> - Dimmer only! <br></li>
         <li><B><a href="#CUL_HMonTill">on-till &lt;time&gt;</a></B> - Dimmer only! <br></li>
         <li><B>stop</B> - stop motion (blind) or dim ramp</li>
         <li><B>pct &lt;level&gt [&lt;ontime&gt] [&lt;ramptime&gt]</B> - set actor to a desired <B>absolut level</B>. 
		            Optional ontime and ramptime could be given for dimmer.</li>
         <li><B>up [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step</li>
         <li><B>down [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step<br>
		     changeValue is optional an gives the level to be changed up or down in percent. Granularity is 0.5%, default is 10%. <br>
			 ontime is optional an gives the duration of the level to be kept. '0' means forever and is default.<br>
			 ramptime is optional an defines the change speed to reach the new level. It is meaningful only for dimmer.
		     <br></li>
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
    <li><B>peerChan &lt;btn_no&gt; &lt;actChan&gt; [single|<u>dual</u>]
        [<u>set</u>|unset] [<u>both</u>|actor|remote]</B><a name="CUL_HMpeerChan"></a><br>

         peerChan will establish a connection between a sender-<B>channel</B> and
         an actuator-<B>channel</B> called link in HM nomenclatur. Peering must not be 
		 confused with pairing.<br>
		 <B>Pairing</B> refers to assign a <B>device</B> to the central.<br> 
		 <B>Peering</B> refers to virtally connect two <B>channels</B>.<br> 
		 Peering allowes direkt interaction between sender and aktor without 
		 the necessity of a CCU<br>
		 Peering a sender-channel causes the sender to expect an ack from -each- 
		 of its peers after sending a trigger. It will give positive feedback (e.g. LED green)
		 only if all peers acknowledged.<br>
		 Peering an aktor-channel will setup a parameter set which defines the action to be
		 taken once a trigger from -this- peer arrived. In other words an aktor will <br> 
		 - process trigger from peers only<br> 
		 - define the action to be taken dedicated for each peer's trigger<br> 
		 An actor channel will setup a default action upon peering - which is actor dependant.
		 It may also depend whether one or 2 buttons are peered <B>in one command</B>.
		 A swich may setup oen button for 'on' and the other for 'off' if 2 button are 
		 peered. If only one button is peered the funktion will likely be 'toggle'.<br>
		 The funtion can be modified by programming the register (aktor dependant).<br>
		 
         Even though the command is executed on a remote or push-button it will
         as well take effect on the actuator directly. Both sides' peering is
         virtually independant and has different impact on sender and receiver
         side.<br>

         Peering of one actuator-channel to multiple sender-channel as
         well as one sender-channel to multiple Actuator-channel is
         possible.<br>

         &lt;actChan&gt; is the actuator-channel to be peered.<br>

         &lt;btn_no&gt; is the sender-channel (button) to be peered. If
         'single' is choosen buttons are counted from 1. For 'dual' btn_no is
         the number of the Button-pair to be used. I.e. '3' in dual is the
         3rd button pair correcponding to button 5 and 6 in single mode.<br>

         If the command is executed on a channel the btn_no is ignored.
		 It needs to be set, should be 0<br>

         [single|dual]: this mode impacts the default behavior of the 
         Actuator upon using this button. E.g. a dimmer can be learned to a 
         single button or to a button pair. <br>
		 Defaults to dual.<br>

         'dual' (default) Button pairs two buttons to one actuator. With a 
         dimmer this means one button for dim-up and one for dim-down. <br>

         'single' uses only one button of the sender. It is useful for e.g. for
         simple switch actuator to toggle on/off. Nevertheless also dimmer can
         be learned to only one button. <br>

         [set|unset]: selects either enter a peering or remove it.<br>
		 Defaults to set.<br>
         'set'   will setup peering for the channels<br>
         'unset' will remove the peering for the channels<br>

         [actor|remote|both] limits the execution to only actor or only remote.
         This gives the user the option to redo the peering on the remote
         channel while the settings in the actor will not be removed.<br>
		 Defaults to both.<br>

         Example:
		 <ul> 
		 <code>
           set myRemote peerChan 2 mySwActChn single set       #peer second button to an actuator channel<br>
           set myRmtBtn peerChan 0 mySwActChn single set       #myRmtBtn is a button of the remote. '0' is not processed here<br>
           set myRemote peerChan 2 mySwActChn dual set         #peer button 3 and 4<br>
           set myRemote peerChan 3 mySwActChn dual unset       #remove peering for button 5 and 6<br>
           set myRemote peerChan 3 mySwActChn dual unset aktor #remove peering for button 5 and 6 in actor only<br>
           set myRemote peerChan 3 mySwActChn dual set remote  #peer button 5 and 6 on remote only. Link settings il mySwActChn will be maintained<br>
         </code>
		 </ul>
    </li>
       </ul>
	</li>
    <li>virtual<a name="CUL_HMvirtual"></a><br>
       <ul>
       <li><B><a href="#CUL_HMpeerChan">peerChan</a></B> see remote</li>
       <li><B>press [long|short]<a name="CUL_HMpress"></a></B>
         simulates a button press short (default) or long. Note that the current
         implementation will not specify the duration for long. Only one trigger
         will be sent of type "long".
	   </li>
       <li><B>postEvent &lt;[0..200]&gt;<a name="CUL_HMpostEvents"></a></B>
         simulates an event. A value must be given between 0 and 200.<br>
		 Alternally a literal ca be given as used by other sensors. enter <br>
		 postEvent ?<br>
		 to get options<br>
	   </li>
       </ul>
    </li>   
    <li>smokeDetector<br>
       Note: All these commands work right now only if you have more then one
       smoekDetector, and you peered them to form a group. For issuing the
       commands you have to use the master of this group, and currently you
       have to guess which of the detectors is the master.<br>
	   smokeDetector can be setup to teams using 
	   <a href="#CUL_HMpeerChan">peerChan</a>. You need to peer all 
	   team-members to the master. Don't forget to also peerChan the master
	   itself to the team - i.e. peer it to itself! doing that you have full 
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
          the teach-in menu of the 4Dis the "Central" to transmit the data.<br>
		  If used on a channel btn_no and on|off must not be given but only pure text.
          Example:
          <ul>
		  <code>
          set 4Dis text 1 on On Lamp<br>
          set 4Dis text 1 off Kitchen Off<br>
		  <br>
          set 4Dis_chn4 text Kitchen Off<br>
          </code>
		  </ul>
	  </li>
	</ul>
    <br></li>
    <li>Climate-Control (HM-CC-TC)
    <ul>
      <li><B>desired-temp &lt;temp&gt;</B><br>
          Set different temperatures. &lt;temp&gt; must be between 6 and 30
          Celsius, and precision is half a degree.</li>
      <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
          Specify a list of temperature intervals. Up to 24 intervals can be
          specified for each week day, the resolution is 10 Minutes. The
          last time spec must always be 24:00.<br>
          Example: until 6:00 temperature shall be 19, from then until 23:00 temperature shall be 
          22.5, thereafter until midnight, 19 degrees celsius is desired.<br>
		  <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
          </li>
      <li><B>partyMode &lt;HH:MM&gt;&lt;durationDays&gt;</B><br>
	  set control mode to party and device ending time. Add the time it ends 
	  and the <b>number of days</b> it shall last. If it shall end next day '1' 
	  must be entered<br>	  </li>
      <li><B>systime</B><br>
          set time in climate channel to system time</li>
    </ul><br>
	</li>
	
	<li>Climate-Control (HM-CC-RT-DN|HM-CC-RT-DN-BoM)
    <ul>
	  <li><B>controlMode &lt;auto|boost|day|night&gt;</B><br></li>
	  <li><B>controlManu &lt;temp&gt;</B><br></li>
	  <li><B>controlParty &lt;temp&gt;&lt;startDate&gt;&lt;startTime&gt;&lt;endDate&gt;&lt;endTime&gt;</B><br>
	      set control mode to party, define temp and timeframe.<br>	  
	      example:<br>
	      <code>set controlParty 15 03.8.13 20:30 5.8.13 11:30</code></li>
      <li><B>systime</B><br>
          set time in climate channel to system time</li>
	  <li><B>desired-temp &lt;temp&gt;</B><br>
          Set different temperatures. &lt;temp&gt; must be between 6 and 30
          Celsius, and precision is half a degree.</li>
	  <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
      <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
          Specify a list of temperature intervals. Up to 24 intervals can be
          specified for each week day, the resolution is 10 Minutes. The
          last time spec must always be 24:00.<br>
		  Optional parameter [prep|exec] allowes to pack the messages and therefore greatly 
		  improve data transmission. This is especially helpful if device is operated in wakeup mode.
		  Usage is to send the commands with paramenter "prep". The data will be accumulated for send. 
		  The last command must have the parameter "exec" in order to transmitt the information.<br>
          Example: until 6:00 temperature shall be 19, from then until 23:00 temperature shall be 
          22.5, thereafter until midnight, 19 degrees celsius is desired.<br>
		  <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
		  <br>
		  <code> set th tempListSat prep 06:00 19 23:00 22.5 24:00 19<br>
		         set th tempListSun prep 06:00 19 23:00 22.5 24:00 19<br>
		         set th tempListMon prep 06:00 19 23:00 22.5 24:00 19<br>
		         set th tempListTue exec 06:00 19 23:00 22.5 24:00 19<br></code>
		  </li>
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
        &lt;duration&gt; [0-127] in sec. 0 is permanent 'on'.<br></li>
    </ul><br></li>
    <li>OutputUnit (HM-OU-CFM-PL)
    <ul>
      <li><B>led &lt;color&gt;[,&lt;color&gt;..] [&lt;repeat&gt..]</B><br>
        Possible colors are [redL|greenL|yellowL|redS|greenS|yellowS|pause]. A
        sequence of colors can be given separating the color entries by ','.
        White spaces must not be used in the list. 'S' indicates short and
        'L' long ilumination. <br>
        <b>repeat</b> defines how often the sequence shall be executed. Defaults to 1.<br>
	  </li>
      <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt..] [&lt;repeat&gt..]</B><br>
        Play a series of tones. List is to be entered separated by ','. White
        spaces must not be used in the list.<br>
        <b>replay</b> can be entered to repeat the last sound played once more.<br>
        <b>repeat</b> defines how often the sequence shall be played. Defaults to 1.<br>
		Example:
		<ul><code>
           # "hello" in display, symb bulb on, backlight, beep<br>
           set cfm_Mp3 playTone 3  # MP3 title 3 once<br>
           set cfm_Mp3 playTone 3 3 # MP3 title 3  3 times<br>
           set cfm_Mp3 playTone 3,6,8,3,4 # MP3 title list 3,6,8,3,4 once<br>
           set cfm_Mp3 playTone 3,6,8,3,4 255# MP3 title list 3,6,8,3,4 255 times<br>
           set cfm_Mp3 playTone replay # repeat last sequence<br>
		   <br>
           set cfm_Led led redL 4 # led red blink 3 times long<br>
           set cfm_Led led redS,redS,redS,redL,redL,redL,redS,redS,redS 255 # SOS 255 times<br>
           </ul></code>  

	  </li>
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
      </ul></li>	  
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
	setup the repeater's entries. Up to 36entries can be applied.
    <ul>
      <li><B>setRepeat    &lt;entry&gt; &lt;sender&gt; &lt;receiver&gt; &lt;broadcast&gt;</B><br>
      &lt;entry&gt; [1..36] entry number in repeater table. The repeater can handle up to 36 entries.<br>
      &lt;sender&gt; name or HMID of the sender or source which shall be repeated<br>
      &lt;receiver&gt; name or HMID of the receiver or destination which shall be repeated<br>
      &lt;broadcast&gt; [yes|no] determines whether broadcast from this ID shall be repeated<br>
	  <br>
	  short application: <br>
	  <code>setRepeat setAll 0 0 0<br></code>
	  will rewrite the complete list to the deivce. Data will be taken from attribut repPeer. <br>
	  attribut repPeer is formated:<br>
	  src1:dst1:[y/n],src2:dst2:[y/n],src2:dst2:[y/n],...<br>
	  <br>
	  Reading repPeer is formated:<br>
	  Number src dst broadcast verify<br>
	  number: entry sequence number<br>
	  src: message source device - read from repeater<br>
	  dst: message destination device - assembled from attributes<br>
	  broadcast: shall broadcast be repeated for this source - read from repeater<br>
	  verify: do attributes and readings match?<br>
    </li>
	</ul>
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
		 With the register also the peering is included.<br>
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
		 # wait until operation is complete<br>
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
	 
     <li><B>saveConfig &lt;file&gt;</B><a name="CUL_HMsaveConfig"></a><br>
         stores peers and register to the file.<br>
		 Stored will be the data as available in fhem. It is necessary to read the information from the device prior to the save.<br>
		 The command supports device-level action. I.e. if executed on a device also all related channel entities will be stored implicitely.<br>
		 Storage to the file will be cumulative. If an entity is stored multiple times to the same file data will be appended. User can identify time of storage in the file if necessary.<br>
		 Content of the file can be used to restore device configuration. It will restore all peers and all register to the entity.<br>		 
		 Constrains/Restrictions:<br>
		 prior to rewrite data to an entity it is necessary to pair the device with FHEM.<br>
		 restore will not delete any peered channels, it will just add peer channels.<br>
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
         Supports 'alive' or better 'not alive' detection for devices. [hhh:mm] is the maximum silent time for the device. Upon no message received in this period an event will be raised "&lt;device&gt; is dead". If the device sends again another notification is posted "&lt;device&gt; is alive". <br>
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
    <li><a name="param">param</a><br>
        param defines model specific behavior or functions. See models for details</li>
    <li><a name="msgRepeat">msgRepeat</a><br>
        defines number of repetitions if a device doesn't answer in time</li>
    <li><a name="burstAccess">burstAccess</a><br>
        can be set for the device entity if the model allowes conditionalBurst. 
		The attribut will switch off burst operations (0_off) which causes less message load 
		on HMLAN and therefore reduces the chance of HMLAN overload.<br>
		Setting it on (1_auto) allowes shorter reaction time of the device. User does not 
		need to wait for the device to wake up. <br>
		Note that also the register burstRx needs to be set in the device.</li>
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
        '0' autoReadReg will be ignored.<br>
        '1' will execute a getConfig for the device automatically after each reboot of FHEM. <br>
		'2' like '1' plus execute after power_on.<br>
		'3' includes '2' plus updates on writes to the device<br>
		'4' includes '3' plus tries to request status if it seems to be missing<br>
		'8_stateOnly' will only update status information but not configuration
		               data like register and peer<br>
		Execution will be delayed in order to prevent congestion at startup. Therefore the update 
		of the readings and the display will be delayed depending on the size of the database.<br>
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
  <a name="CUL_HMparams"></a>
  <b>available paramter "param"</b>
  <ul>
  <li><B>HM-Sen-RD-O</B><br>
  offAtPon: heat channel only: force heating off after powerOn<br>
  onAtRain: heat channel only: force heating on while status changes to 'rain' and off when it changes to 'dry'<br>
  </li>
  
  </ul>
  <a name="CUL_HMevents"></a>
  <b>Generated events:</b>
  <ul>
  <li><B>HM-CC-TC</B><br>
      T: $t H: $h<br>
  	  battery:[low|ok]<br>
      measured-temp $t<br>
      humidity $h<br>
      actuator $vp %<br>
	  desired-temp $dTemp<br>
	  desired-temp-manu $dTemp #temperature if switchen to manual mode<br>
	  desired-temp-cent $dTemp #temperature if switchen to central mode<br>
	  windowopen-temp-%d  %.1f (sensor:%s)<br>
	  tempList$wd  hh:mm $t hh:mm $t ...<br>
      displayMode temp-[hum|only]<br>
      displayTemp [setpoint|actual]<br>
      displayTempUnit [fahrenheit|celsius]<br>
      controlMode [manual|auto|central|party]<br>
      tempValveMode [Auto|Closed|Open|unknown]<br>
	  param-change  offset=$o1, value=$v1<br>
      ValveErrorPosition_for_$dname  $vep %<br>
      ValveOffset_for_$dname : $of %<br>
	  ValveErrorPosition $vep %<br>
	  ValveOffset $of %<br>
      time-request<br>
	  trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel. 
	  This event relies on complete reading of channels configuration, otherwise Data can be
	  incomplete or incorrect.<br>
	  trigLast &lt;channel&gt; #last receiced trigger<br>
  </li>
  <li><B>HM-CC-RT-DN and HM-CC-RT-DN-BoM</B><br>
      state:T: $actTemp desired: $setTemp valve: $vp %<br>
      motorErr: [ok|ValveTight|adjustRangeTooLarge|adjustRangeTooSmall|communicationERR|unknown|lowBat|ValveErrorPosition]
      measured-temp $actTemp<br>
      desired-temp $setTemp<br>
	  ValvePosition $vp %<br>
      mode  [auto|manu|party|boost]<br>
      battery [low|ok]<br>
	  batteryLevel $bat V<br>
      measured-temp $actTemp<br>
      desired-temp $setTemp<br>
	  actuator $vp %<br>
      time-request<br>
	  trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel. 
  </li>
  <li><B>HM-CC-VD</B><br>
      $vp %<br>
	  battery:[critical|low|ok]<br>
      motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
	  ValvePosition:$vp %<br>
      ValveErrorPosition:$vep %<br>
      ValveOffset:$of %<br>
	  ValveDesired:$vp %            # set by TC <br>
	  operState:[errorTargetNotMet|onTarget|adjusting]  # operational condition<br>
	  operStateErrCnt:$cnt          # number of failed settings<br>
  </li>
  <li><B>HM-CC-SCD</B><br>
	  [normal|added|addedStrong]<br>
      battery [low|ok]<br>
  </li>
  <li><B>HM-SEC-SFA-SM</B><br>
	  powerError [on|off]<br>
	  sabotageError [on|off]<br>
	  battery: [critical|low|ok]<br>
  </li>
  <li><B>HM-LC-BL1-PB-FM</B><br>
      motor: [opening|closing]<br>
  </li>
  <li><B>HM-LC-SW1-BA-PCB</B><br>
	  battery: [low|ok]<br>
  </li>
  <li><B>HM-OU-LED16</B><br>
  	  color $value                  # hex - for device only<br>
	  $value                        # hex - for device only<br>
	  color [off|red|green|orange]  # for channel <br>
      [off|red|green|orange]	    # for channel <br>
  </li>
  <li><B>HM-OU-CFM-PL</B><br>
	  [on|off|$val]<br>
  </li>
  <li><B>HM-Sen-Wa-Od</B><br>
	  $level%<br>
	  level $level%<br>
  </li>
  <li><B>KFM100</B><br>
      $v<br>
      $cv,$unit<br>
      rawValue:$v<br>
      Sequence:$seq<br>
      content:$cv,$unit<br>
  </li>
  <li><B>KS550/HM-WDS100-C6-O</B><br>
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
  <li><B>HM-Sen-RD-O</B><br>
    lastRain: timestamp # no trigger generated. Begin of previous Rain -
   	     timestamp of the reading is the end of rain. <br>
  </li>
  <li><B>THSensor  and HM-WDC7000</B><br>
      T: $t H: $h AP: $ap<br>
      temperature $t<br>
      humidity $h<br>
      airpress $ap                   #HM-WDC7000 only<br>
  </li>
  <li><B>dimmer</B><br>
      overload [on|off]<br>
      overheat [on|off]<br>
      reduced [on|off]<br>
      dim: [up|down|stop]<br>
  </li>
  <li><B>motionDetector</B><br>
      brightness:$b<br>
      alive<br>
      motion on (to $dest)<br>
      motionCount $cnt _next:$nextTr"-"[0x0|0x1|0x2|0x3|15|30|60|120|240|0x9|0xa|0xb|0xc|0xd|0xe|0xf]<br>
      cover [closed|open]        # not for HM-Sec-MDIR<br>
	  sabotageError [on|off]     # only HM-Sec-MDIR<br>
      battery [low|ok]<br>
	  devState_raw.$d1 $d2<br>
  </li>
  <li><B>remote/pushButton/outputUnit</B><br>
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
  <li><B>remote/pushButton</B><br>
      battery [low|ok]<br>
	  trigger [Long|Short]_$no trigger event from channel<br>
  </li>
  <li><B>swi</B><br>
      Btn$x toggle<br>
      Btn$x toggle (to $dest)<br>
      battery: [low|ok]<br>
  </li>
  <li><B>switch/dimmer/blindActuator</B><br>
	  $val<br>
	  powerOn [on|off|$val]<br>
      [unknown|motor|dim] [up|down|stop]:$val<br>
  	  timedOn [running|off]<br> # on is temporary - e.g. started with on-for-timer
  </li>
  <li><B>sensRain</B><br>
	  $val<br>
	  powerOn <br>
      level <val><br>
  	  timedOn [running|off]<br> # on is temporary - e.g. started with on-for-timer
	  trigger [Long|Short]_$no trigger event from channel<br>
  </li>
  <li><B>smokeDetector</B><br>
      [off|smoke-Alarm|alive]             # for team leader<br>
	  [off|smoke-forward|smoke-alarm]     # for team members<br>
	  [normal|added|addedStrong]          #HM-CC-SCD<br>
 	  SDteam [add|remove]_$dname<br>
      battery [low|ok]<br>
      smoke_detect [none|&lt;src&gt;]<br>
      test:from $src<br>
  </li>
  <li><B>threeStateSensor</B><br>
      [open|tilted|closed]<br>
      [wet|damp|dry]                 #HM-SEC-WDS only<br>
	  cover [open|closed]            #HM-SEC-WDS and HM-Sec-RHS<br>
	  alive yes<br>
      battery [low|ok]<br>
      contact [open|tilted|closed]<br>
	  contact [wet|damp|dry]         #HM-SEC-WDS only<br>
	  sabotageError [on|off]         #HM-SEC-SC only<br>
  </li>
  <li><B>winMatic</B><br>
	  [locked|$value]<br>
	  motorError [no|TurnError|TiltError]<br>
	  direction [no|up|down|undefined]<br>	 
	  charge [trickleCharge|charge|dischange|unknown]<br>
      airing [inactiv|$air]<br>
      course [tilt|close]<br>
      airing [inactiv|$value]<br>
      contact tesed<br>
  </li>
  <li><B>keyMatic</B><br>
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
