##############################################
##############################################
# CUL HomeMatic handler
# $Id$

package main;

use strict;
use warnings;
use HMConfig;
use Color;
use Digest::MD5 qw(md5);

eval "use Crypt::Rijndael";
my $cryptFunc = ($@)?0:1;

# ========================import constants=====================================

my $culHmModel            =\%HMConfig::culHmModel;
my $culHmModel2Id         =\%HMConfig::culHmModel2Id;

my $culHmRegDefShLg       =\%HMConfig::culHmRegDefShLg;
my $culHmRegDefine        =\%HMConfig::culHmRegDefine;
my $culHmRegGeneral       =\%HMConfig::culHmRegGeneral;
my $culHmRegType          =\%HMConfig::culHmRegType;
my $culHmRegModel         =\%HMConfig::culHmRegModel;
my $culHmRegChan          =\%HMConfig::culHmRegChan;

my $culHmGlobalGets       =\%HMConfig::culHmGlobalGets;
my $culHmVrtGets          =\%HMConfig::culHmVrtGets;

my $culHmSubTypeGets      =\%HMConfig::culHmSubTypeGets;
my $culHmModelGets        =\%HMConfig::culHmModelGets;
my $culHmGlobalGetsDev    =\%HMConfig::culHmGlobalGetsDev;

my $culHmSubTypeDevSets   =\%HMConfig::culHmSubTypeDevSets;
my $culHmGlobalSetsChn    =\%HMConfig::culHmGlobalSetsChn;
my $culHmReglSets         =\%HMConfig::culHmReglSets;
my $culHmGlobalSets       =\%HMConfig::culHmGlobalSets;
my $culHmGlobalSetsVrtDev =\%HMConfig::culHmGlobalSetsVrtDev;
my $culHmSubTypeSets      =\%HMConfig::culHmSubTypeSets;
my $culHmModelSets        =\%HMConfig::culHmModelSets;
my $culHmChanSets         =\%HMConfig::culHmChanSets;
my $culHmFunctSets        =\%HMConfig::culHmFunctSets;

my $culHmBits             =\%HMConfig::culHmBits;
my $culHmCmdFlags         =\@HMConfig::culHmCmdFlags;
my $K_actDetID            ="000000";

my %activeCmds = ( "valvePos"         => 1,"up"               => 1,"unlock"           => 1,"toggleDir"        => 1
                  ,"toggle"           => 1 
                  ,"tempListWed"      => 1,"tempListTue"      => 1,"tempListThu"      => 1,"tempListSun"      => 1
                  ,"tempListSat"      => 1,"tempListMon"      => 1,"tempListFri"      => 1
                  ,"stop"             => 1,"setRepeat"        => 1 
                  ,"reset"            => 1,"regSet"           => 1,"regBulk"          => 1
                  ,"press"            => 1,"postEvent"        => 1,"playTone"         => 1
                  ,"peerIODev"        => 1,"peerChan"         => 1,"peerBulk"         => 1
                  ,"pctSlat"          => 1,"pctLvlSlat"       => 1,"pct"              => 1,"pair"             => 1
                  ,"open"             => 1,"on"               => 1,"old"              => 1,"off"              => 1
                  ,"lock"             => 1,"level"            => 1,"led"              => 1
                  ,"keydef"           => 1,"fwUpdate"         => 1,"down"             => 1
                  ,"controlParty"     => 1,"controlManu"      => 1 
                  ,"color"            => 1,"colProgram"       => 1,"brightCol"        => 1,"brightAuto"       => 1
                  ,"on-till"          => 1,"on-for-timer"     => 1,"desired-temp"     => 1
                  );
############################################################

sub CUL_HM_Initialize($);
sub CUL_HM_reqStatus($);
sub CUL_HM_autoReadConfig();
sub CUL_HM_updateConfig($);
sub CUL_HM_Define($$);
sub CUL_HM_Undef($$);
sub CUL_HM_Rename($$);
sub CUL_HM_Attr(@);
sub CUL_HM_Parse($$);
sub CUL_HM_parseCommon(@);
sub CUL_HM_qAutoRead($$);
sub CUL_HM_Get($@);
sub CUL_HM_Set($@);
sub CUL_HM_valvePosUpdt(@);
sub CUL_HM_infoUpdtDevData($$$$);
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
sub CUL_HM_peerChId($$);
sub CUL_HM_peerChName($$);
sub CUL_HM_getMId($);
sub CUL_HM_getRxType($);
sub CUL_HM_getAssChnIds($);
sub CUL_HM_h2IoId($);
sub CUL_HM_IoId($);
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
sub CUL_HM_getRegN($$@);
sub CUL_HM_4DisText($);
sub CUL_HM_TCtempReadings($);
sub CUL_HM_repReadings($);
sub CUL_HM_dimLog($);
sub CUL_HM_ActGetCreateHash();
sub CUL_HM_time2sec($);
sub CUL_HM_ActAdd($$);
sub CUL_HM_ActDel($);
sub CUL_HM_ActCheck($);
sub CUL_HM_UpdtReadBulk(@);
sub CUL_HM_UpdtReadSingle(@);
sub CUL_HM_setAttrIfCh($$$$);
sub CUL_HM_noDup(@);        #return list with no duplicates
sub CUL_HM_noDupInString($);#return string with no duplicates, comma separated
sub CUL_HM_storeRssi(@);
sub CUL_HM_qStateUpdatIfEnab($@);
sub CUL_HM_getAttrInt($@);
sub CUL_HM_appFromQ($$);
sub CUL_HM_autoReadReady($);
sub CUL_HM_calcDisWm($$$);
sub CUL_HM_statCnt(@);
sub CUL_HM_trigLastEvent($$$$$);
sub CUL_HM_rmOldRegs($$);
sub CUL_HM_SetList($$);
sub CUL_HM_operIObyIOHash($);
sub CUL_HM_operIObyIOName($);
sub CUL_HM_hmInitMsgUpdt($;$);

# ----------------modul globals-----------------------
my $respRemoved; # used to control trigger of stack processing
my $IOpoll     = 0.2;# poll speed to scan IO device out of order

my $maxPendCmds = 10;  #number of parallel requests
my @evtEt = ();    #readings for entities. Format hash:trigger:reading:value
my $evtDly = 0;    # ugly switch to delay set readings if in parser - actually not our job, but fhem.pl refuses
                   # need to take care that ACK is first
my $mIdReverse = 0; # CUL_HM model ID reverse search is not supported by default. Check and update at startup
#+++++++++++++++++ startup, init, definition+++++++++++++++++++++++++++++++++++
sub CUL_HM_Initialize($) {
  my ($hash) = @_;

#  my @modellist = ();
#  foreach my $model (keys %{$culHmModel}){
#    next if (!$model);
#    push @modellist,$culHmModel->{$model}{name};
#  }
  
  $hash->{Match}     = "^A....................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{UndefFn}   = "CUL_HM_Undef";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{GetFn}     = "CUL_HM_Get";
  #$hash->{RenameFn}  = "CUL_HM_Rename"; # by own notify
  $hash->{AttrFn}    = "CUL_HM_Attr";
  $hash->{NotifyFn}  = "CUL_HM_Notify";
  CUL_HM_AttrInit($hash,"initAttrlist");
                         
  CUL_HM_initRegHash();
  my $time = gettimeofday();
  
  $hash->{prot}{rspPend} = 0;#count Pending responses
  my @statQArr     = ();
  my @statQWuArr   = ();
  my @confQArr     = ();
  my @confQWuArr   = ();
  my %confCheckH   ;
  my %confUpdt     ;         # entities with updated config
  $hash->{helper}{qReqStat}     = \@statQArr;
  $hash->{helper}{qReqStatWu}   = \@statQWuArr;
  $hash->{helper}{qReqConf}     = \@confQArr;
  $hash->{helper}{qReqConfWu}   = \@confQWuArr;
  $hash->{helper}{confCheckH}   = \%confCheckH;
  $hash->{helper}{confUpdt}     = \%confUpdt;
  $hash->{helper}{cfgCmpl}{init}= 1;# mark entities with complete config
  #statistics
  $hash->{stat}{s}{dummy}=0;
  $hash->{stat}{r}{dummy}=0;
  RemoveInternalTimer("StatCntRfresh");
  InternalTimer($time + 3600 * 20,"CUL_HM_statCntRfresh","StatCntRfresh", 0);

  $hash->{hmIoMaxDly}     = 60;# poll timeout - stop poll and discard
  $hash->{hmAutoReadScan} = 4; # delay autoConf readings
  $hash->{helper}{hmManualOper} = 0;# default automode
  $hash->{helper}{verbose}{none} = 1; # init hash
  $hash->{helper}{primary} = ""; # primary is one device in CUL_HM.It will be used for module notification. 
                                          # fhem does not provide module notifcation - so we streamline here. 
  $hash->{helper}{initDone} = 0;
  $hash->{NotifyOrderPrefix} = "48-"; #Beta-User: make sure, CUL_HM is up and running prior to User code e.g. in notify, and also prior to HMinfo
  InternalTimer($time + 1,"CUL_HM_updateConfig","startUp",0);
  #InternalTimer($time + 1,"CUL_HM_setupHMLAN", "initHMLAN", 0);#start asap once FHEM is operational

  return;
}

sub CUL_HM_updateConfig($){##########################
  my $type = shift;
  # this routine is called immedately after INITALIZED or REREADCFG 
  # so all attributes and stateFile content has been read.
  # it will also be called after each manual definition
  # Purpose is to parse attributes and read config
  RemoveInternalTimer("updateConfig");
  if (!$init_done){
    InternalTimer(gettimeofday() + 1,"CUL_HM_updateConfig", "updateConfig", 0);#start asap once FHEM is operational
    return;
  }
  if (!$modules{CUL_HM}{helper}{initDone}){ #= 0;$type eq "startUp"){
    # only once after startup - clean up definitions. During operation define function will take care
    Log 5,"CUL_HM start inital cleanup";
    $mIdReverse = 1 if (scalar keys %{$culHmModel2Id});
    my @hmdev = devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=DEF!=000000");   # devices only
    
    foreach my $name  (@hmdev){
      if ($attr{$name}{subType} && $attr{$name}{subType} eq "virtual"){
        $attr{$name}{model} = "VIRTUAL" if (!$attr{$name}{model} || $attr{$name}{model} =~ m/virtual_/);
      }
      if ($attr{$name}{".mId"} && $culHmModel->{$attr{$name}{".mId"}}){ #if mId is available set model to its original value -at least temporarliy
        $attr{$name}{model} = $culHmModel->{$attr{$name}{".mId"}}{name};
      }
      else{#if mId is not available use attr model and assign it. 
        if ($modules{CUL_HM}{AttrList} =~ m /\.mId/){# do not handle .mId if not restarted
          $attr{$name}{".mId"} = CUL_HM_getmIdFromModel($attr{$name}{model});
        }
      }
      CUL_HM_updtDeviceModel($name,AttrVal($name,"modelForce",AttrVal($name,"model","")),1) if($attr{$name}{".mId"});
      # update IOdev
      my $IOgrp = AttrVal($name,"IOgrp","");
      if($IOgrp ne ""){
        delete $attr{$name}{IODev};
        CUL_HM_Attr('set',$name,'IOList',AttrVal($name,'IOList','')) if (AttrVal($name,'IOList',undef));
        CUL_HM_Attr("set",$name,"IOgrp",$IOgrp);
      }
      my $h = $defs{$name};
      delete $h->{helper}{io}{restoredIO} if (   defined($h->{helper}{io})
                                              && defined($h->{helper}{io}{restoredIO})
                                              && !defined($defs{$h->{helper}{io}{restoredIO}})); # cleanup undefined restored IO
      if (!CUL_HM_operIObyIOHash($h->{IODev})) { # noansi: assign IO, if no currently operational  IO assigned
        CUL_HM_assignIO($h) if !IsDummy($name) && !IsIgnored($name);
        delete($h->{IODev}{'.clientArray'}) if ($h->{IODev}); # Force a recompute
      }
    }
  }

  foreach my $name (@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    my $hash = $defs{$name};
    next if (!$hash->{DEF}); # likely renamed
    foreach my $read (grep/(RegL_0.:|_chn:\d\d)/,keys%{$hash->{READINGS}}){
      my $readN = $read;
      $readN =~ s/(RegL_0.):/$1\./;
      $readN =~ s/_chn:(\d\d)/_chn-$1/;
      $hash->{READINGS}{$readN} = $hash->{READINGS}{$read};
      delete $hash->{READINGS}{$read};
    }
    
    my $id = $hash->{DEF};
    my $nAttr = $modules{CUL_HM}{helper}{hmManualOper};# no update for attr
    {####  find notification entity
      if(!$modules{CUL_HM}{helper}{primary}){
        CUL_HM_primaryDev(); # fake call to init primary device       
      }
      if ($modules{CUL_HM}{helper}{primary} && $modules{CUL_HM}{helper}{primary} ne $name){
        notifyRegexpChanged($defs{$name},0,1);#disable the notification
      }
    }
    if ($id eq $K_actDetID){# if action detector
      $attr{$name}{"event-on-change-reading"} = 
                AttrVal($name, "event-on-change-reading", ".*")
                if(!$nAttr);
      $attr{$name}{".mId"}  = CUL_HM_getmIdFromModel("ACTIONDETECTOR");
      $attr{$name}{model}   = $culHmModel->{"0000"}{name};
      $attr{$name}{subType} = $culHmModel->{"0000"}{st};
      delete $hash->{IODev};
      delete $hash->{READINGS}{IODev};
      delete $hash->{helper}{mRssi};
      delete $hash->{helper}{role};
      delete $attr{$name}{$_}
            foreach ( "autoReadReg","actStatus","burstAccess","serialNr"
                     ,"IODev","IOList","IOgrp","hmProtocolEvents","rssiLog"); 
      $hash->{helper}{role}{vrt} = 1;
      $hash->{helper}{role}{dev} = 1;
      delete $hash->{helper}{mId};
      delete $hash->{helper}{rxType};#will update rxType and mId
      CUL_HM_getMId($hash); # need to set regLst in helper
      next;
    }
    CUL_HM_getMId($hash); # need to set regLst in helper
    
    my $chn = substr($id."00",6,2);
    my $st  = CUL_HM_getAttr($name,"subType","");
    my $md  = CUL_HM_getAttr($name,"model","");
    
    my $dHash = CUL_HM_getDeviceHash($hash);
    $dHash->{helper}{role}{prs} = 1 if($hash->{helper}{regLst} && $hash->{helper}{regLst} =~ m/3p/);

    foreach my $rName ("D-firmware","D-serialNr",".D-devInfo",".D-stc"){
      # move certain attributes to readings for future handling
      my $aName = $rName;
      $aName =~ s/D-//;
      my $aVal = AttrVal($name,$aName,undef);
      CUL_HM_UpdtReadSingle($hash,$rName,$aVal,0)
           if (!defined ReadingsVal($name,$rName,undef) && defined($aVal));
    }

    if    ($md =~ /(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){
#      $hash->{helper}{role}{chn} = 1 if (length($id) == 6); #tc special
    }
    elsif ($md =~ m/^(HM-CC-RT-DN)/){
      $hash->{helper}{shRegR}{"07"} = "00" if ($chn eq "04");# shadowReg List 7 read from CH 0
      $hash->{helper}{shRegW}{"07"} = "04" if ($chn eq "00");# shadowReg List 7 write to CH 4
    }
    elsif ($md =~ m/^(HM-TC-IT-WM-W-EU)/){
      $hash->{helper}{shRegR}{"07"} = "00" if ($chn eq "02");# shadowReg List 7 read from CH 0
      $hash->{helper}{shRegW}{"07"} = "02" if ($chn eq "00");# shadowReg List 7 write to CH 4
    }
    elsif ($md =~ m/^(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/){
      $attr{$name}{msgRepeat} = 0 if ($hash->{helper}{role}{dev}); #noansi: force no repeat
      $hash->{helper}{oldDes} = "0";
    }
    elsif ($md =~ m/^(HM-DIS-WM55)/){
      foreach my $t ("s","l"){
        if(!defined $hash->{helper}{dispi}{$t}{"l1"}{d}){# setup if one is missing
          $hash->{helper}{dispi}{$t}{"l$_"}{d}=1 foreach (1,2,3,4,5,6);
        }
      }
    }
    elsif ($md =~ m/^(HM-DIS-EP-WM55)/){
      CUL_HM_UpdtReadSingle($hash,"state","-",0) if(InternalVal($name,"chanNo",0)>3);
    }
    elsif ($md =~ m/^(CCU-FHEM)/){
      $hash->{helper}{role}{vrt} = 1;
      delete $hash->{helper}{mId};
      if($hash->{helper}{role}{dev}){
        CUL_HM_UpdtCentral($name); # first update, then keys

        foreach my $io (split ",",AttrVal($name,"IOList","")) {
          next if(!$defs{$io});
          if($defs{$io}->{TYPE} eq "HMLAN" && eval "defined(&HMLAN_writeAesKey)"){
            HMLAN_writeAesKey($io);
          } 
          elsif ($defs{$io}->{TYPE} eq "HMUARTLGW") {
            CallFn($io,"WriteFn",$defs{$io},undef,"writeAesKey:${io}");
          }
          elsif (   $defs{$io}->{helper}{VTS_AES} # noansi: for TSCUL
                 && eval "defined(&TSCUL_WriteAesKeyHM)"){
            TSCUL_WriteAesKeyHM($io); # noansi: for TSCUL
          }
        }

        $hash->{helper}{io}{vccu} = $name if (!$hash->{helper}{io}{vccu}
                                               && AttrVal($name,"IOList","")); # noansi: help, if IOgrp is missing for VCCU
      }
    }
    elsif ($md =~ m/^HM-SEN-RD-O/ && $chn eq "02"){
      for my $params (split q{,},AttrVal($name,'param','')){
        if    ($params eq "offAtPon"){$hash->{helper}{param}{offAtPon} = 1}
        elsif ($params eq "onAtRain"){$hash->{helper}{param}{onAtRain} = 1}
      }
    }
    elsif ($st =~ m/^(motionDetector|motionAndBtn)$/ ){
      CUL_HM_UpdtReadSingle($hash,"state","-",0);
      CUL_HM_UpdtReadSingle($hash,"motion","-",0);
      RemoveInternalTimer($name.":motionCheck");
      InternalTimer(gettimeofday()+30+2,"CUL_HM_motionCheck", $name.":motionCheck", 0);
    }
    elsif ($st eq "dimmer"  ) {#setup virtual dimmer channels
      my $mId = CUL_HM_getMId($hash);
      #configure Dimmer virtual channel assotiation
      if ($hash->{helper}{role}{chn}){
        my $chn = (length($id) == 8)?substr($id,6,2):"01";
        my $devId = substr($id,0,6);
        if ($culHmModel->{$mId} && $culHmModel->{$mId}{chn} =~ m/Dim_V/){#virtual?
          my @chnPh = (grep{$_ =~ m/Sw:/ } split ',',$culHmModel->{$mId}{chn});
          @chnPh = split ':',$chnPh[0] if (@chnPh);
          my $chnPhyMax = $chnPh[2]?$chnPh[2]:1;         # max Phys channels
          my $chnPhy    = ($chnPhyMax == 2 && $chn >  4)?2:1;    # assotiated phy chan( either 1 or 2)
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
    elsif ($st eq "virtual" ) {#setup virtuals
      $hash->{helper}{role}{vrt} = 1;
      if (   $hash->{helper}{fkt} 
          && $hash->{helper}{fkt} =~ m/^(vdCtrl|virtThSens)$/){
        my $vId = substr($id."01",0,8);
        if (!defined $hash->{helper}{vd}{msgRed}) {
          $hash->{helper}{vd}{msgRed}= 0;
          my $attrVal = AttrVal($name,'param','');
          if ($attrVal =~ m/msgReduce/) {
            my (undef,$rCnt) = split(":",$attrVal,2);
            $hash->{helper}{vd}{msgRed} = (defined $rCnt && $rCnt =~ m/^\d$/) ? $rCnt : 1;
          }
        }
        if(!defined $hash->{helper}{vd}{next}){
          ($hash->{helper}{vd}{msgCnt},$hash->{helper}{vd}{next}) = 
                    split(";",ReadingsVal($name,".next","0;".gettimeofday()));
          $hash->{helper}{vd}{idl} = 0;
          $hash->{helper}{vd}{idh} = 0;
        }
        InternalTimer(time+10,'CUL_HM_initializeVirtuals', $hash,0); #Beta-User: make sure, CUL_HM is in toto up and running befor other devices want to use them, 

        # delete - virtuals dont have regs 
        delete $attr{$name}{$_} foreach ("autoReadReg","actCycle","actStatus","burstAccess","serialNr"); 
      }
    }
    elsif ($st eq "sensRain") {
      $hash->{helper}{lastRain} = ReadingsTimestamp($name,"state","")
            if (ReadingsVal($name,"state","") eq "rain");
    }
    next if ($nAttr);# stop if default setting if attributes is not desired

    # --- set default attributes if missing ---
    if ($hash->{helper}{role}{dev}){
      if( $st ne "virtual"){
        $attr{$name}{expert}     = AttrVal($name,"expert"     ,"rawReg");
        $attr{$name}{autoReadReg}= AttrVal($name,"autoReadReg","4_reqStatus");
        CUL_HM_hmInitMsg($hash);
      }
      my $rxt = CUL_HM_getRxType($hash);# set rxType and mId
      if($rxt & 0x02){#burst dev must restrict retries!
        $attr{$name}{msgRepeat} = 1 if (!$attr{$name}{msgRepeat});
      }
      elsif($rxt & 0x80){# frank: init conditional burst dev
        if($attr{$name}{burstAccess}){
          CUL_HM_Attr('set',$name,'burstAccess',$attr{$name}{burstAccess});
        }
        else{
          CUL_HM_Attr('del',$name,'burstAccess');
        }
      }
    }
    if ($attr{$name}{expert}){
      CUL_HM_Attr("set",$name,"expert",$attr{$name}{expert});
    }
    else{
      CUL_HM_Attr("del",$name,"expert"); # need to update settings and readings
    }
          ;#need update after readings are available
    if ($chn eq "03" && 
        $md =~ /(-TC|ROTO_ZEL-STG-RM-FWT|HM-CC-RT-DN)/){
      $attr{$name}{stateFormat} = "last:trigLast";
    }
    # -+-+-+-+-+ add default web-commands
    my $webCmd;
    $webCmd = AttrVal($name,"webCmd",undef);
    if(!defined $webCmd){
      if    ($st eq "virtual"      ){
        if   ($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "sdLead1")   {$webCmd="teamCall:alarmOn:alarmOff";}
        elsif($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "vdCtrl")    {$webCmd="valvePos";}
        elsif($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "virtThSens"){$webCmd="virtTemp:virtHum";}
        elsif(!$hash->{helper}{role}{dev})                                 {$webCmd="press short:press long";}
        elsif($md =~ m/^(virtual_|VIRTUAL)/)                               {$webCmd="virtual";}
        elsif($md eq "CCU-FHEM")                                           {$webCmd="virtual:update";}

      }
      elsif((!$hash->{helper}{role}{chn} &&
               $md !~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/)
            ||$st eq "repeater"
            ||$md =~ m/^(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/ ){$webCmd="getConfig:clear msgEvents";
        if ($md =~ m/^HM-CC-RT-DN/)                      {$webCmd.=":burstXmit";}
      }
      elsif($st eq "blindActuator"){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggleDir:on:off:up:down:stop";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "dimmer"       ){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggle:on:off:up:down";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "switch"       ){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggle:on:off";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "smokeDetector"){   $webCmd="statusRequest";
        if (defined $hash->{helper}{fkt} && $hash->{helper}{fkt} eq "sdLead1"){
                                        $webCmd.=":teamCall:alarmOn:alarmOff";}
      }
      elsif($st eq "keyMatic"     ){   $webCmd="lock:inhibit on:inhibit off";
      }
      elsif(  $md eq "HM-OU-CFM-PL" 
            ||$md eq "HM-OU-CFM-TW" ){ $webCmd="press short:press long"
                                        .($chn eq "02"?":playTone replay":"");
      }

      if ($webCmd){
        my $eventMap  = AttrVal($name,"eventMap",undef);

        my @wc;
        push @wc,ReplaceEventMap($name, $_, 1) foreach (split ":",$webCmd);
        $webCmd = join ":",@wc;
      }
    }
    $attr{$name}{webCmd} = $webCmd if ($webCmd);

    CUL_HM_SetList($name,"") if (!defined $defs{$name}{helper}{cmds}{cmdLst});
    #remove invalid attributes. After set commands fot templist
    CUL_HM_Attr("set",$name,"peerIDs",$attr{$name}{peerIDs}) if (defined $attr{$name}{peerIDs});# set attr again to update namings
    foreach(sort keys %{$attr{$name}}){
      delete $attr{$name}{$_} if (CUL_HM_AttrCheck($name,'set',$_,$attr{$name}{$_}));  
    }
    #CUL_HM_qStateUpdatIfEnab($name) if($hash->{helper}{role}{dev});
    next if (0 == (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
    if(CUL_HM_getPeers($name,"Config") == 2){
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
    
    CUL_HM_complConfig($name);
    CUL_HM_setAssotiat($name);
  }
  
  #delete $modules{CUL_HM}{helper}{updtCfgLst};
  if(!$modules{CUL_HM}{helper}{initDone}){
    Log 5,"CUL_HM finished initial cleanup";
    InternalTimer(gettimeofday() + 66, 'CUL_HM_startQueues', 'CUL_HM_startQueues', 0); #frank, https://forum.fhem.de/index.php/topic,125378.msg1202273.html#msg1202273 ff
    if (defined &HMinfo_init){# force reread
      $modules{HMinfo}{helper}{initDone} = 0;
      InternalTimer(gettimeofday() + 5,"HMinfo_init", "HMinfo_init", 0);
    }
  }
  $modules{CUL_HM}{helper}{initDone} = 1;# we made init once - now we are operational. Check with HMInfo as well
  ## configCheck will be issues by HMInfo once
}

sub CUL_HM_startQueues() { #frank, https://forum.fhem.de/index.php/topic,125378.msg1202273.html#msg1202273
  Log3('global',3,'CUL_HM start Queues'); #Beta-User: changed verbose level
  for my $name (@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    CUL_HM_qStateUpdatIfEnab($name) if($defs{$name}->{helper}{role}{dev});
  }
  delete $modules{CUL_HM}{helper}{updtCfgLst};
  return;
}

sub CUL_HM_initializeVirtuals {
    my $hash = shift // return;
    my $name = $hash->{NAME} // return;
    my $vId = substr($hash->{DEF}."01",0,8);
    if ($hash->{helper}{fkt} eq "vdCtrl"){
      my $d = ReadingsNum($name,'valvePosTC','50');
      CUL_HM_Set($hash,$name,"valvePos",$d);
      CUL_HM_UpdtReadSingle($hash,"valveCtrl","restart",1) if ($d =~ m/^[-+]?[0-9]+\.?[0-9]*$/);
      RemoveInternalTimer("valvePos:$vId");
      RemoveInternalTimer("valveTmr:$vId");
      InternalTimer($hash->{helper}{vd}{next},"CUL_HM_valvePosUpdt","valvePos:$vId",0);
    }
    elsif($hash->{helper}{fkt} eq "virtThSens"){
      my $d = ReadingsNum($name,'temperature','');
      CUL_HM_Set($hash,$name,"virtTemp",$d) if($d =~ m/^[-+]?[0-9]+\.?[0-9]*$/);
      $d = ReadingsNum($name,"humidity","");
      CUL_HM_Set($hash,$name,"virtHum" ,$d) if($d =~ m/^[-+]?[0-9]+\.?[0-9]*$/);
    }
    return;
}

sub CUL_HM_primaryDev() {############################
  # one - and only one  - CUL_HM entity will be primary device
  # primary device is a) CUL_HM and b) not ignored
  
  if ( !$modules{CUL_HM}{helper}{primary} 
      || AttrVal($modules{CUL_HM}{helper}{primary},"ignore",0) == 1
      || !defined $defs{$modules{CUL_HM}{helper}{primary}} ){# we need to check primary
    my ($prim ) = devspec2array("TYPE=CUL_HM"); # a non-ignore CUL_HM entity
    if ($prim && defined $defs{$prim}){
      notifyRegexpChanged($defs{$prim},"global",0);
      $modules{CUL_HM}{helper}{primary} = $prim;
    }
    else{
      $modules{CUL_HM}{helper}{primary} = "";
    }
  }
}
sub CUL_HM_Define($$) {##############################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $HMid = uc($a[2]);
  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $HMid !~ m/^[A-F0-9]{6}([A-F0-9]{2})?$/i );
  return  "HMid DEF already used by " . CUL_HM_id2Name($HMid)
        if ($modules{CUL_HM}{defptr}{$HMid});
  my $name = $hash->{NAME};
  
  if(length($HMid) == 8) {# define a channel
    my $devHmId = substr($HMid, 0, 6);
    my $chn = substr($HMid, 6, 2);
    my $devHash = $modules{CUL_HM}{defptr}{$devHmId};
    return "please define a device with hmId:".$devHmId." first" if(!$devHash);

    my $devName                = $devHash->{NAME};
    $hash->{device}            = $devName;  #readable ref to device name
    $hash->{chanNo}            = $chn;      #readable ref to Channel
    $devHash->{"channel_$chn"} = $name;     #reference in device as well
    $attr{$name}{model}        = AttrVal($devName, "model", undef);
    $hash->{helper}{role}{chn} = 1;
    delete $hash->{helper}{mId};
    delete $hash->{helper}{rxType};
    if($chn eq "01"){
      if (defined $devHash->{helper}{peerIDsH}){
        $hash->{helper}{peerIDsH}      = $devHash->{helper}{peerIDsH} ;
        $hash->{helper}{peerIDsState}  = $devHash->{helper}{peerIDsState};
      }
      $attr{$name}{peerIDs}            = AttrVal($devName, "peerIDs", "peerUnread");
      $hash->{READINGS}{peerList}{VAL} = ReadingsVal($devName,"peerList","peerUnread");
      $hash->{peerList}                = $devHash->{peerList} if($devHash->{peerList});

      delete $devHash->{helper}{role}{chn};#device no longer
      delete $devHash->{chanNo};           #readable ref to Channel
      delete $devHash->{peerList};
      delete $devHash->{READINGS}{peerList};
      delete $attr{$devName}{peerIDs};
      delete $devHash->{helper}{peerIDsH};
      delete $devHash->{helper}{peerIDsState};
      $devHash->{helper}{cmds}{cmdKey}  = ''; # noansi: rebuild required
      $devHash->{helper}{cmds}{TmplKey} = ''; # noansi: rebuild required
    }
  }
  else{# define a device
    $hash->{helper}{role}{dev}   = 1;
    delete $hash->{helper}{mId};
    delete $hash->{helper}{rxType};
    $hash->{helper}{role}{chn}   = 1;# take role of chn 01 until it is defined
    $hash->{helper}{q}{qReqConf} = ""; # queue autoConfig requests 
    $hash->{helper}{q}{qReqStat} = ""; # queue statusRequest for this device
    $hash->{helper}{mRssi}{mNo}  = "";
    $hash->{helper}{HM_CMDNR}    = int(rand(250));# should be different from previous
    CUL_HM_prtInit ($hash);
    $hash->{helper}{io}{vccu}    = "";
    my @a;
    $hash->{helper}{io}{prefIO}  = \@a;
    $hash->{chanNo}              = "01" if (!defined $defs{$HMid."01"}); #readable ref to Channel

    if (   !$modules{CUL_HM}{helper}{initDone}
        && $HMid ne "000000") {
      if (eval "defined(&TSCUL_RestoreHMDev)") {
        my $restoredIOname = TSCUL_RestoreHMDev($hash, $HMid); # noansi: restore IODev from TSCUL before the first CUL_HM_assignIO
                                                               #         here not all IOs may be defined allready, but we can try to restore as no IO is set
                                                               #         restore is working best, if IOs are defined first in cfg
        if (defined($restoredIOname)) {
          $hash->{IODev}                                 = $defs{$restoredIOname};
#          $attr{$name}{IODev}                            = $restoredIOname;
          $hash->{helper}{io}{restoredIO}                = $restoredIOname; # noansi: until attributes are filled, this should be the first choice
          @{$hash->{helper}{mRssi}{io}{$restoredIOname}} = (100,100);       # noansi: set IO high rssi for first autoassign
        }
      }
      # fhem.pl will set an IO from reading/attr IODev or AssignIoPort at end of init, we can not avoid and can not assign correctly
      #         but with reading IOdev fhem.pl will restore the IO unsed before normal restart
      CUL_HM_assignIO($hash) if (!$hash->{IODev} && $init_done);
      delete($hash->{IODev}{'.clientArray'}) if ($hash->{IODev}); # Force a recompute
    }
  }
  $hash->{helper}{cmds}{cmdKey}   = "";
  $hash->{helper}{cmds}{TmplKey}  = "";
  
  $modules{CUL_HM}{defptr}{$HMid} = $hash;
  notifyRegexpChanged($hash,"",1);# no notification required for this device
  CUL_HM_primaryDev() if devspec2array('TYPE=CUL_HM') == 2; #Beta-User: we need at least one entity to initialize startup procedure

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
  CUL_HM_unQEntity($name,"qReqConf");
  CUL_HM_unQEntity($name,"qReqStat");
  CUL_HM_complConfigTestRm($name);
  my $chn = substr($HMid,6,2);
  if ($chn){# delete a channel
    my $devHash = $defs{$devName};
    delete $devHash->{"channel_$chn"} if ($devName);
    $devHash->{helper}{role}{chn} = 1 if($chn eq "01");# return chan 01 role
    delete $hash->{helper}{mId};
  }
  else{# delete a device
    CommandDelete(undef,$hash->{$_}) foreach (grep(/^channel_/,keys %{$hash}));
  }
  delete($modules{CUL_HM}{defptr}{$HMid});
  delete $modules{CUL_HM}{helper}{primary} if (devspec2array('TYPE=CUL_HM') == 1);
  return undef;
}
sub CUL_HM_Rename($$) {##############################
  my ($name, $oldName) = @_;
  my $hash = $defs{$name};
  return if($hash->{TYPE} ne "CUL_HM");
  my $HMid = CUL_HM_name2Id($name);
  if (!$hash->{helper}{role}{dev}){# we are channel, inform the device
    $hash->{chanNo} = substr($HMid,6,2);
    my $devHash = CUL_HM_id2Hash(substr($HMid,0,6));
    $hash->{device} = $devHash->{NAME};
    $devHash->{"channel_".$hash->{chanNo}} = $name;
  }
  else{# we are a device - inform channels if exist
    foreach (grep (/^channel_/, keys%{$hash})){
      next if(!$_);
      my $chnHash = $defs{$hash->{$_}};
      $chnHash->{device} = $name;
    }
    if (!defined $defs{$HMid."01"}){$hash->{chanNo} = "01";}
    else                           {delete $hash->{chanNo};}
    
    CUL_HM_UpdtCentral($name) if (AttrVal($name, "model", "") eq "CCU-FHEM");
  }
  if ($hash->{helper}{role}{chn}){
    my $HMidCh = substr($HMid."01",0,8);
    foreach my $pId (keys %{$modules{CUL_HM}{defptr}}){#all devices for peer
      my $pH = $modules{CUL_HM}{defptr}{$pId};
      my $pN = $pH->{NAME};

      if (defined $hash->{helper}{peerIDsH}{$HMidCh}){
        CUL_HM_Attr("set",$pN,"peerIDs",$attr{$pN}{peerIDs}) if (defined $attr{$pN}{peerIDs});# set attr again to update namings
        foreach my $pR (grep /(-|\.)$oldName(-|$)/,keys%{$pH->{READINGS}}){#update reading of the peer
          my $pRn = $pR;
          $pRn =~ s/$oldName/$name/;
          $pH->{READINGS}{$pRn}{VAL}  = $pH->{READINGS}{$pR}{VAL};
          $pH->{READINGS}{$pRn}{TIME} = $pH->{READINGS}{$pR}{TIME};
          delete $pH->{READINGS}{$pR};
        }
        if (eval "defined(&HMinfo_templateMark)"){
          foreach my $pT (grep /$oldName:/,keys%{$pH->{helper}{tmpl}}){#update reading of the peer
            my $param = $pH->{helper}{tmpl}{$pT};
            my ($px,$tmpl) = split(">",$pT);
            HMinfo_templateDel($pN,$tmpl,$px);
            $px =~ s/$oldName/$name/;
            HMinfo_templateMark($pH,"$px>$tmpl",split(" ",$param));
          }
        }
      }
    }
  }
  if($modules{CUL_HM}{helper}{primary} eq $oldName){
      
  }
  notifyRegexpChanged($hash,"",1);# no notification required for this device
  return;
}
sub CUL_HM_Attr(@) {#################################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  return undef if (!$init_done);
  my $chk = CUL_HM_AttrCheck($name,$cmd, $attrName,$attrVal);
  return $chk if ($chk);
  my $hash = CUL_HM_name2Hash($name);
  my $updtReq = 0;
  if   ($attrName eq "expert"){
    my $ret = 0;
    if ($cmd eq "set"){
      my @expLst = ();
      if ($attrVal =~ m/^(\d+)/){# old style
        push @expLst, "defReg" if(!($1 & 0x04));#default register on
        push @expLst, "allReg" if( ($1 & 0x01));#detail register on
        push @expLst, "rawReg" if( ($1 & 0x02));#raw register on
        push @expLst, "templ"  if( ($1 & 0x08));#template on
        push @expLst, "none"   if( ($1 & 0x0F) == 0x04);#all off
        $ret = 1;
      }
      else{
        $modules{CUL_HM}{AttrList} =~ m/.*expert:multiple,(.*?) .*/;
        my $expOpts = $1;
        foreach (split(",",$attrVal)){
           if($expOpts =~ m/\b$_\b/){
             push @expLst,$_ ;
           }
           else{
             $ret = 1;
           }
        }
      }
      $attr{$name}{$attrName} = join(",",@expLst);
    }
    else{#delete
      delete $attr{$name}{$attrName};
    }
    CUL_HM_chgExpLvl($_) foreach ((map{CUL_HM_id2Hash($_)} CUL_HM_getAssChnIds($name)),$defs{$name});
    return $attr{$name}{$attrName} if ($ret);
  }
  elsif($attrName eq "readOnly"){#[0,1]
  }
  elsif($attrName eq "actCycle"){#"000:00" or 'off'
    if ($cmd eq "set"){
      if (CUL_HM_name2Id($name) eq $K_actDetID){
        return "$attrName must not be lower then 10, $attrVal not allowed"
              if ($attrVal < 10);
        #update and sync to new timing

        RemoveInternalTimer("ActionDetector");
        InternalTimer(gettimeofday()+5,"CUL_HM_ActCheck", "ActionDetector", 0);
      }
      else{
        return "attribut not allowed for channels"
                      if (!$hash->{helper}{role}{dev});
        
        my $attrValNew;
        if($attrVal =~ m/^(0+:0+|off)$/){
          $attrValNew = '000:00';
        }
        elsif($attrVal =~ m/^(\d+):(\d+)$/){
          my ($h,$m) = (int($1),int($2));
          return "format hhh:mm required. $attrVal incorrect" if( $h > 999 || $h < 0
                                                               || $m > 59  || $m < 0
                                                               || $h + $m <= 0);
          $attrValNew  = sprintf("%03d:%02d",$h,$m); 
        }
        my $addres = CUL_HM_ActAdd(CUL_HM_name2Id($name),$attrValNew);
        return $addres if defined($addres); # noansi: return errors from CUL_HM_ActAdd
        $attr{$name}{$attrName} = $attrValNew;
        return "reformated input:$attrValNew" if($attrValNew ne $attrVal);
        }
    }
    $updtReq = 1;
  }
  elsif($attrName eq "param"){
    my $md  = CUL_HM_getAttr($name,"model","");
    my $st  = CUL_HM_getAttr($name,"subType","");
    my $chn = substr(CUL_HM_hash2Id($hash),6,2);
    if    ($md eq "HM-SEN-RD-O"    && $chn eq "02"){
      delete $hash->{helper}{param};
      foreach (split ",",$attrVal){
        if    ($_ eq "offAtPon"){$hash->{helper}{param}{offAtPon} = 1}
        elsif ($_ eq "onAtRain"){$hash->{helper}{param}{onAtRain} = 1}
        else {return "param $_ unknown, use offAtPon or onAtRain";}
      }
    }
    elsif ($md eq "HM-DIS-EP-WM55" && $chn eq "03"){#reWriteDisplay
      if ($cmd eq "set"){
        if ($attrVal =~ m/^reWriteDisplay([0-9][0-9])$/){# no action, just set
          my $delay = $1;
          if($delay < 1 || $delay >99){
            return "invalid $delay- select between reWriteDisplay01 and reWriteDisplay99";
          }
        }
        else{
          return "attribut param $attrVal not valid for $name. Only reWriteDisplayxx allowed";
        }
      }
      else{
        delete $hash->{helper}{vd}{msgRed};
      }
    }
    elsif ($st eq "virtual"){
      if ($cmd eq "set"){
        if ($attrVal eq "noOnOff"){# no action
        }
        elsif ($attrVal =~ m/msgReduce/){# send only each other message
          my (undef,$rCnt) = split(":",$attrVal,2);
          $rCnt=(defined $rCnt && $rCnt =~ m/^\d$/)?$rCnt:1;
          $hash->{helper}{vd}{msgRed}=$rCnt;
        }
        else{
          return "attribut param $attrVal not valid for $name";
        }
      }
      else{
        delete $hash->{helper}{vd}{msgRed};
      }
    }
    else{
      if ($cmd eq "set"){
        if    ($attrVal =~ m/(levelInverse|ponRestore)/){# no action
        }
        elsif ($attrVal =~ m/(showTimed)/){# no action
          #we could check for those subtypes
          #sensRain
          #siren
          #powerMeter
          #switch
          #dimmer
          #rgb
        }
        else{
          return "attribut param $attrVal not valid for $name";
        }
      }
      else{
        delete $hash->{helper}{vd}{msgRed};
      }
    }
  }
  elsif($attrName eq "peerIDs"){
    if ($cmd eq "set"){
      return "$attrName not usable for devices" if(!$hash->{helper}{role}{chn});
      my $dId = substr(CUL_HM_name2Id($name),0,6);      #get own device ID
      if ($hash->{DEF} ne $K_actDetID && $attrVal){# if not action detector
        return "new $attrName val:$attrVal element $_ not a peerID. User (peerUnread|[0-9a-fA-Fx]{8})" if(grep!/^(peerUnread|[0-9a-fA-Fx]{8})$/,split(",",$attrVal));
        CUL_HM_ID2PeerList($name,$_,1) foreach("peerUnread",split(",",$attrVal));#first clear, then setup
      }
    }
    else{# delete
      delete $hash->{peerList};
      delete $hash->{READINGS}{peerList};
      CUL_HM_ID2PeerList($name," ","clear");
    }
  }
  elsif($attrName eq "msgRepeat"){
    if ($cmd eq "set"){
      return "$attrName not usable for channels" if(!$hash->{helper}{role}{dev});#only for device
      return "value $attrVal ignored, must be an integer" if ($attrVal !~ m/^(\d+)$/);
    }
    return;
  }
  elsif($attrName eq "model"){
    return "change not allowed for channels" if(!$hash->{helper}{role}{dev});
    if (  $attrVal eq "CCU-FHEM" 
      and $cmd eq "set"
      and AttrVal($name,"model","VIRTUAL") =~ m/^(VIRTUAL|)$/){
        delete $hash->{helper}{rxType}; # needs new calculation
        delete $hash->{helper}{mId};
        $attr{$name}{subType} = "virtual";
        $attr{$name}{".mId"} = CUL_HM_getmIdFromModel($attrVal);
        CUL_HM_updtDeviceModel($name,$attrVal);
        $updtReq = 1;
        CUL_HM_AttrAssign($name);
        CUL_HM_UpdtCentral($name);
    }
    else{
      return "$attrName must not be changed by User. \nUse modelForce instead" if (AttrVal($name,$attrName,"empty") !~ m/(empty|$attrVal)/);
      delete $hash->{helper}{rxType}; # needs new calculation
      delete $hash->{helper}{mId};
      CUL_HM_hmInitMsg($hash);# will update mId, rxType and others
      CUL_HM_updtDeviceModel($name,$attrVal);
    }
    $attr{$name}{$attrName} = $attrVal if ($cmd eq "set");
  }
  elsif($attrName eq "modelForce"){
    if ($cmd eq "set"){
      return "invalid model name$cmd. Please check options" if (!CUL_HM_getmIdFromModel($attrVal));
      if (!defined $attr{$name}{".mId"} && defined $attr{$name}{model}){ # set .mId in case it is missing
        $attr{$name}{".mId"} = CUL_HM_getmIdFromModel($attr{$name}{model});
      }
      CUL_HM_updtDeviceModel($name,$attrVal);
    }
    else{
      $attr{$name}{model} = $culHmModel->{$attr{$name}{".mId"}}{name} if ($attr{$name}{".mId"});# return to old model name
      CUL_HM_updtDeviceModel($name,$attr{$name}{model});
    }
  }
  elsif($attrName eq ".mId"){
    return "$attrName must not be changed by User. \nUse modelForce instead";
  }
  elsif($attrName eq "subType"){
    return "$attrName must not be changed by User. \nUse modelForce instead" if (AttrVal($name,$attrName,"empty") !~ m/(empty|$attrVal)/);
    $updtReq = 1;
  }
  elsif($attrName eq "aesCommReq" ){
    if ($cmd eq "set"){
      return "$attrName support 0 or 1 only"        if ($attrVal !~ m/[01]/);
      return "$attrName invalid for virtal devices" if ($hash->{role}{vrt});
      $attr{$name}{$attrName} = $attrVal;
      # if (   $attrVal eq "1"
      #     && $hash->{device}) { # is a channel
      #   $attr{$hash->{device}}{$attrName} = $attrVal; # automatically enable on device, too - does not make sense
      # }
    }
    else{
      delete $attr{$name}{$attrName};
    }
    CUL_HM_hmInitMsg(CUL_HM_getDeviceHash($hash));
  }
  elsif($attrName eq "aesKey" ){
    if ($cmd eq "set"){
      return "$attrName support 0 to 5 only"        if ($attrVal < 0 || $attrVal > 5);
      $attr{$name}{$attrName} = $attrVal;
    }
    else{
      delete $attr{$name}{$attrName};
    }
    CUL_HM_hmInitMsg(CUL_HM_getDeviceHash($hash));
  }
  elsif($attrName eq "burstAccess"){
    if ($cmd eq "set"){
      return "use burstAccess only for device"             if (!$hash->{helper}{role}{dev});
      return $name." not a conditional burst model"        if (!CUL_HM_getRxType($hash) & 0x80);
      return "$attrVal not a valid option for burstAccess" if ($attrVal !~ m/^[01]/);
      if ($attrVal =~ m/^0/){$hash->{protCondBurst} = "forced_off";}
      else                  {$hash->{protCondBurst} = "unknown";}
    }
    else{                    $hash->{protCondBurst} = "forced_off";}
    delete $hash->{helper}{rxType}; # needs new calculation
  }
  elsif($attrName eq "IODev") {
    if ($cmd eq "set") {
      return 'CUL_HM '.$name.': IOgpr set => ccu to control the IO. Delete attr IOgrp if unwanted'
             if (AttrVal($name,"IOgrp",undef));
      if ($attrVal) {
        my @IOnames = devspec2array('Clients=.*:CUL_HM:.*');
#        my @IOnames = grep {InternalVal($_,'Clients',
#                                           defined $modules{InternalVal($_,'TYPE','')}{Clients}
#                                           ? $modules{InternalVal($_,'TYPE','')}{Clients}
#                                           : '') 
#                            =~ m{:CUL_HM:}} 
#                            keys %defs;
        return 'CUL_HM '.$name.': Non suitable IODev '.$attrVal.' specified. Options are: ',join(",",@IOnames)
            if (!grep /^$attrVal$/,@IOnames);
        $attr{$name}{$attrName} = $attrVal;
        CUL_HM_assignIO($hash);
      }
    } 
    else {
        InternalTimer(gettimeofday(),'CUL_HM_assignIO',$hash,0); #Beta-User: as attribute is no longer mandatory, we should assign one after delete is done. Might collide with automatic deletion in initialisation
    }
  }
  elsif($attrName eq "IOList"){
    my @rmIO;  
    my $ret = "";
    if($cmd eq "set" ){
      $attrVal =~ s/ //g; 
      my @newIO = CUL_HM_noDup(split(",",$attrVal));
      foreach my $nIO (@newIO){
        return "$nIO does not support CUL_HM" if(InternalVal($nIO,"Clients","") !~ m /:CUL_HM:/);
        my $owner_ccu = InternalVal($nIO,'owner_CCU',undef);
        return "device $nIO already owned by $owner_ccu" if $owner_ccu && $owner_ccu ne $name;
        if (InternalVal($nIO,'TYPE','') eq 'HMLAN' ) {
            HMLAN_assignIDs($defs{$nIO}) if AttrVal($nIO,'hmId','') ne $hash->{DEF} && defined &HMLAN_assignIDs;
        }
      }
      if($attr{$name}{$attrName}){# see who we lost
        foreach my $oldIOs (split(",",$attr{$name}{$attrName})){
          next if(grep /$oldIOs/,@newIO); # IO still in use
          push @rmIO,$oldIOs;
        }
      }
      $attr{$name}{$attrName} = join(",",sort @newIO);
      $defs{$name}{helper}{io}{ioList} = \@newIO;
      $defs{$name}{IODev} = $defs{$newIO[0]};
    }
    else {
      delete $attr{$name}{$attrName};
      @rmIO = @{$defs{$name}{helper}{io}{ioList}};# delete all of them. #split(",",$attr{$name}{$attrName});
      my @newIO = ();
      $defs{$name}{helper}{io}{ioList} = \@newIO;
    }
    # update device clients if IOs are removed
    my $id = CUL_HM_name2Id($name);
    CommandAttr (undef,"$_ hmId $id") foreach (grep{AttrVal($_,"hmId","") ne $id} 
                                               split(",",$attr{$name}{$attrName})); # update our new friends

    if(scalar @rmIO){
      foreach (@rmIO){# not our friend anymore - release the IO
        next if (!defined $defs{$_});
        CommandDeleteAttr (undef,"$_ hmId") ; 
        delete $defs{$_}{owner}; 
        delete $defs{$_}{owner_CCU};
      }
      my @devUpdate = ();
      foreach my $ent (grep{AttrVal($_,"IOgrp","") =~ m/^$name:/}keys %defs){
        next if IsIgnored($ent);
        if(scalar @{$defs{$name}{helper}{io}{ioList}}){
          my $ea = AttrVal($ent,"IOgrp","");
          my $eaOrg = $ea;
          $ea =~ s/,?$_//  foreach (@rmIO);
          $ea =~ s/:,/:/; 
          $ea = $name if ($ea eq "$name:" || $ea eq "$name:none");
          if($eaOrg ne $ea){
            push @devUpdate,"IOgrp $eaOrg changed to $ea for $ent";
            CommandAttr (undef,"$ent IOgrp $ea");
          }
        }
        else{#no IOs anymore
          push @devUpdate,"IOgrp removed for $ent";
          CommandDeleteAttr (undef,"$ent IOgrp") ; 
        }
      }
      $ret .= join("\n",CUL_HM_noDup(@devUpdate));
    }
    CUL_HM_UpdtCentral($name);
    return "$attrName = $attr{$name}{$attrName}\n$ret" if (($cmd eq "set" && $attr{$name}{$attrName} ne $attrVal)
                                                         or($ret))
                                                         ;
  }
  elsif($attrName eq "IOgrp" ){
    if ($cmd eq "set"){
      $attrVal =~ s/\s//g;
      my ($ioCCU,$prefIO) = split(":",$attrVal,2);
      my $ioLst = AttrVal($ioCCU,"IOList","");
      return "vccu $ioCCU is no vccu with IOs assigned. It can't be used as IO" if (!$ioLst);# implicitely checks also for correct vccu
      my @prefIOarr;
      if ($prefIO){
        my @ioOpts = split(",",$ioLst);
        return "$ioCCU not a valid CCU with IOs assigned" if (!scalar @ioOpts);
        push @ioOpts, 'none';
        @prefIOarr = split(",",$prefIO);
        foreach my $pIO (@prefIOarr){
          return "$pIO is not allowed in preferred IO list. Leave unassigned or choose one or more of ".join(",",@ioOpts) if(1 != grep m{\A$pIO\z},@ioOpts);
          return "'none' may not be used without precedent other IO and has to be last!" if ($prefIO eq 'none' || $prefIO =~ m{\bnone[\b]*.+\z});
        }
      }
      else{
        @prefIOarr = ();
      }
      $hash->{helper}{io}{prefIO} = \@prefIOarr;
      $hash->{helper}{io}{vccu}   = $ioCCU;
      $attr{$name}{$attrName}     = $attrVal;
      delete $attr{$name}{IODev};# just in case
    }
    else{ # this is a delete
      my @a = ();
      $hash->{helper}{io}{vccu}   = "";
      $hash->{helper}{io}{prefIO} = \@a;
    }
    CUL_HM_assignIO($hash);
  }
  elsif($attrName eq "autoReadReg"){
    if ($cmd eq "set"){
      CUL_HM_complConfigTest($name)
        if (!CUL_HM_getAttrInt($name,"ignore"));;
    }
  }
  elsif($attrName eq "rssiLog" ){
    if ($cmd eq "set"){
      return "use $attrName only for device" if (!$hash->{helper}{role}{dev});
    }
  }
  elsif($attrName eq "levelRange" ){
    if ($cmd eq "set"){
      return "use $attrName only for dimmer" if (CUL_HM_getAttr($name,"subType","") ne "dimmer"
                                                );
      my ($min,$max) = split (",",$attrVal);
      return "use format min,max" if (!defined $max);
      return "min:$min must be between 0 and 100" if ($min<0 || $min >100);
      return "max:$max must be between 0 and 100" if ($max<0 || $max >100);
      return "min:$min must be lower then max:$max" if ($min >= $max);
    }
  }
  elsif($attrName eq "levelMap" ){
    if ($cmd eq "set"){
      delete $hash->{helper}{lm};
      foreach (split":",$attrVal){
        my ($val,$vNm) = split"=",$_;
        if ($val !~ m/^\d*$/){
          delete $hash->{helper}{lm};
          return "$val is not numeric";
        }
        $hash->{helper}{lm}{$val} = $vNm;
      }
    }
    else{
      delete $hash->{helper}{lm};
    }
  }
  elsif($attrName eq "actAutoTry" ){
    if ($cmd eq "set"){
      return "$attrName only usable for ActionDetector" if(CUL_HM_hash2Id($hash) ne "000000");#only for device
    }
  }
  elsif($attrName eq "tempListTmpl" ){
    if ($cmd eq "set"){
      CUL_HM_UpdtReadSingle($hash,"tempTmplSet",$attrVal,0)
    }
    else{
      delete $hash->{READINGS}{"tempTmplSet"};
    }
  }
  elsif($attrName =~ m/^hmKey/){
    my $retVal= "";
    return "use $attrName only for vccu device" 
            if (!$hash->{helper}{role}{dev}
                || AttrVal($name,"model","CCU-FHEM") ne "CCU-FHEM");
    if ($cmd eq "set"){
      # eQ3 default key A4E375C6B09FD185F27C4E96FC273AE4
      my $kno = ($attrName eq "hmKey")?1:substr($attrName,5,1);
      my ($no,$val) = (sprintf("%02X",$kno),$attrVal);
      if ($attrVal =~ m/:/){#number given
        ($no,$val) = split ":",$attrVal;
        return "illegal number:$no" if (hex($no) < 1 || hex($no) > 255 || length($no) != 2);
      }
      $attr{$name}{$attrName} = "$no:".
                               (($val =~ m/^[0-9A-Fa-f]{32}$/ )
                                 ? $val
                                 : unpack('H*', md5($val)));
      $retVal = "$attrName set to $attr{$name}{$attrName}"
            if($attrVal ne $attr{$name}{$attrName});
    }
    else{
      delete $attr{$name}{$attrName};
    }
    foreach my $io (split ",",AttrVal($name,"IOList","")) {
      next if(!$defs{$io});
      if    ($defs{$io}->{TYPE} eq "HMLAN" && eval "defined(&HMLAN_writeAesKey)"){
        HMLAN_writeAesKey($io);
      }
      elsif ($defs{$io}->{TYPE} eq "HMUARTLGW") {
        CallFn($io,"WriteFn",$defs{$io},undef,"writeAesKey:${io}");
      }
      elsif (   $defs{$io}->{helper}{VTS_AES}
             && eval "defined(&TSCUL_WriteAesKeyHM)"){
        TSCUL_WriteAesKeyHM($io); # noansi: for TSCUL
      }
    }
    return $retVal;
  }
  elsif($attrName eq "logIDs"){
    my $retVal= "";
    return "use $attrName only for vccu device" 
            if (!$hash->{helper}{role}{dev}
                || AttrVal($name,"model","CCU-FHEM") !~ "CCU-FHEM");
    if ($cmd eq "set"){
      my $newVal = "";
      my @logIds = split (",",$attrVal);
      if (grep /^none$/,@logIds){
        $newVal = "none";
      }
      elsif (grep /^all$/,@logIds){
        $newVal = "all";
      }
      else{
        $newVal = join(",",(grep!/000000/,
                            grep/./,
                            map{CUL_HM_name2Id($_)} @logIds)
                          ,(grep /^(sys|broadcast)$/,@logIds)
                       );
      }

      foreach my $IOname  (split(",",AttrVal($name,"IOList",""))){
        next if (   !defined $defs{$IOname});
        next if (   $modules{$defs{$IOname}{TYPE}}{AttrList} !~  m/logIDs/);
        my $r = CommandAttr(undef, "$IOname logIDs $newVal");
      }
    } else {
      CommandDeleteAttr(undef, AttrVal($name,'IOList','').' logIDs');
    }
  }
  elsif($attrName eq "ignore" || $attrName eq "dummy"){
    if ($cmd eq "set"){
      if ($attrVal) {
        return "Setting $attrName for CCU-FHEM model requires to delete IOList first!" if defined AttrVal($hash->{NAME},'IOList',undef);
        IOWrite($hash, '', 'remove:'.$hash->{DEF}) if defined $hash->{IODev}->{TYPE} && $hash->{IODev}->{TYPE} =~ m/^HM(?:LAN|UARTLGW)$/s && defined $hash->{DEF};
        #delete $hash->{IODev};
        delete $hash->{READINGS}{IODev};
      }
      $attr{$name}{".ignoreSet"} = $attrVal; # remember user desire
      foreach my $chNm(CUL_HM_getAssChnNames($name)){
        if( $attrVal == 1){
          $attr{$chNm}{$attrName} = 1;
          if ($modules{CUL_HM}{helper}{primary} eq $chNm){#we need to find a new primary 
            CUL_HM_primaryDev();
          }
        }
        elsif( defined $attr{$chNm}{".ignoreSet"} && $attrName eq 'ignore'){
          $attr{$chNm}{$attrName} = $attr{$chNm}{".ignoreSet"};
        }
        else{
          delete $attr{$chNm}{$attrName};
        }
      }
      if (!$attrVal) {
        CUL_HM_assignIO($hash) ;
      }
      delete $attr{$name}{".ignoreSet"}; #Beta-User: seems not to be used outside of this code part
    }
    else {
      delete $attr{$name}{".ignoreSet"};
      foreach my $chNm(CUL_HM_getAssChnNames($name)){
        if( defined $attr{$chNm}{".ignoreSet"}){
          $attr{$chNm}{$attrName} = $attr{$chNm}{".ignoreSet"};
        }
        else{
          delete $attr{$chNm}{$attrName};
        }
      }
      if ( $attrName eq 'ignore' && !IsDummy($hash) || $attrName eq 'dummy' && !IsIgnored($hash) ) {
        RemoveInternalTimer('ActionDetector'); #Beta-User: should solve https://forum.fhem.de/index.php/topic,125490.0.html
        InternalTimer(gettimeofday()+5,'CUL_HM_ActCheck', 'ActionDetector', 0);
        CUL_HM_assignIO($hash);
      }
    }
  }
  elsif($attrName eq "commStInCh"){
    if ($cmd eq "set" && $attrVal eq "off"){
      foreach my $chNm(CUL_HM_getAssChnNames($name)){
        delete $defs{$chNm}{READINGS}{commState} if(!$defs{$chNm}{helper}{role}{dev});
      }
    }
    else {
      my $commState = ReadingsVal($name,"commState",undef);
      foreach my $chNm(CUL_HM_getAssChnNames($name)){
        CUL_HM_UpdtReadSingle($defs{$chNm},"commState",$commState,0) if($commState && !$defs{$chNm}{helper}{role}{dev});
      }
    }
  }
 
  CUL_HM_queueUpdtCfg($name) if ($updtReq);
  return undef;
}
sub CUL_HM_AttrCheck(@) {############################
  #verify if attr is applicable
  my ($name,$cmd, $attrName,$attrVal) = @_;
  return undef if ($cmd ne "set");  # allow delete any time
  my $a = " ".getAllAttr($name)." ";
  if($a !~ m/ $attrName[ :]+/){
    $a =~ s/:.*? //g;
    return "attribut $attrName not valid. Use one of $a";
  }

  return undef if (!defined $modules{CUL_HM}{ModulAttr}{$attrName} # non CUL_HM attribut - dont check further
                 ||!defined $defs{$name}{'.AttrList'}              # device not init
                  ); 

  $defs{$name}{'.AttrList'} =~ m/ ?($attrName)(:*)(.*?) /;
  my ($attrFound,$attrOpt)  = ($1,$3);
#  return "$attrName not defined for $name" if (!defined $attrFound); # must not occure - already checked global
  return undef if (!$attrOpt || $attrOpt =~ m/^(multiple|textField-)/); # any value allowed
  return undef if(grep/^$attrVal$/,split(",",$attrOpt));   # attrval is valid option
  return "value $attrVal not allowed. Choose one of:$attrOpt";
}
sub CUL_HM_AttrInit($;$) {###########################
  # define attributes and their options that are relevant/defined/controlled by CUL_HM
  # for performance improvement the action with an update is restricted. 
  # dynamic Updates are expected and navigated for tempListTmpl and logIDs only. 
  my ($hash,$type) = @_;
  #called by HMinfo if templates are updated
  if ($type && $type eq "initAttrlist"){
    delete $hash->{AttrX}; # first clear me
    my @modellist = ();
    foreach my $model (keys %{$culHmModel}){
      next if (!$model);
      push @modellist,$culHmModel->{$model}{name};
    }
    $hash->{AttrX}{glb} = {                            # assign to any
                           do_not_notify     => '1,0'
                          ,showtime          => '1,0'
                          ,expert            => 'multiple,defReg,allReg,rawReg,templ,none'
                          ,param             => ''
                          ,readOnly          => '0,1'                       
                          ,aesCommReq        => '1,0'     # IO will request AES if 
                          ,model             => ''
                          };
    foreach (split(" ",$readingFnAttributes)){
      my ($a,$v) = split (":",$_);
      $hash->{AttrX}{glb}{$a} = defined $v ? $v:'';
    }
    $hash->{AttrX}{dev} = {                            # assign if role = device
                           ignore            => '1,0'
                          ,dummy             => '1,0'     # -- device only attributes
                          ,IODev             => '' 
                          ,IOgrp             => ''   
                          ,hmKey             => '' 
                          ,hmKey2            => '' 
                          ,hmKey3            => ''  # required for VCCU
                          ,subType           => join(",",CUL_HM_noDup(map { $culHmModel->{$_}{st} } keys %{$culHmModel}))
                          ,modelForce        => join(",", sort @modellist)
                          ,commStInCh        => 'on,off'
                          ,'.mId'            => ''
                          };
    $hash->{AttrX}{devPhy} = {                         # assign if role = device && subTyp <> virtual
                           serialNr          => ''  
                          ,firmware          => ''  
                          ,'.stc'            => ''  
                          ,'.devInfo'        => '' 
                          ,actStatus         => '' 
                          ,rssiLog           => '1,0'  # enable writing RSSI to Readings (device only)
                          ,autoReadReg       => '0_off,1_restart,2_pon-restart,3_onChange,4_reqStatus,5_readMissing,8_stateOnly'
                          ,msgRepeat         => ''                     
                          ,actCycle          => ''            
                          ,readingOnDead     => 'multiple,noChange,state,periodValues,periodString,channels'
                          ,hmProtocolEvents  => '0_off,1_dump,2_dumpFull,3_dumpTrigger'
                          ,aesKey            => '5,4,3,2,1,0'
                          ,burstAccess       => '0_off,1_auto' # conditional burst device only
                          };
    $hash->{AttrX}{chn} = {                            # assign if role = chn
                           peerIDs           => ''
                          ,levelRange        => ''
                          ,levelMap          => ''
                          };
    $hash->{AttrX}{VIRTUAL} = {                        # model = virtual ###=> virtual {helper}{fkt} eq "vdCtrl" for VD
                           cyclicMsgOffset   => ''
                          ,param             => ''
                          };

    $hash->{AttrX}{'blindActuator'} = {                # subType
                           param             => 'multiple,levelInverse,ponRestoreSmart,ponRestoreForce'
                          };
    $hash->{AttrX}{'sensRain'} = {                     # subType
                           param             => 'showTimed'
                          };
    $hash->{AttrX}{'siren'} = {                        # subType
                           param             => 'showTimed'
                          };
    $hash->{AttrX}{'powerMeter'} = {                   # subType
                           param             => 'showTimed'
                          };
    $hash->{AttrX}{'switch'} = {                       # subType
                           param             => 'showTimed,levelInverse'
                          };
    $hash->{AttrX}{'dimmer'} = {                       # subType
                           param             => 'showTimed'
                          };
    $hash->{AttrX}{'rgb'} = {                          # subType
                           param             => 'showTimed'
                          };
    $hash->{AttrX}{'HM-SEN-RD-O'} = {                  # model
                           param             => 'multiple,offAtPon,onAtRain'
                          };
    $hash->{AttrX}{'HM-DIS-EP-WM55'} = {               # model
                           param             => '' #reWriteDisplay([0-9][0-9])
                          };
    $hash->{AttrX}{'HM-SYS-SRP-PL'} = {                # model
                           repPeers          => ''
                          };
    $hash->{AttrX}{ACTIONDETECTOR} = {                 # model
                           actAutoTry        => '0_off,1_on'
                          ,actCycle          => ''     # also for action detector    
                          };
    $hash->{AttrX}{'KFM-SENSOR'} = {                   # model
                           unit              => ''
                          ,rawToReadable     => ''
                          };
    $hash->{AttrX}{'CCU-FHEM'} = {                     # model
                           logIDs            => 'multiple,none,sys,all,broadcast'
                          ,IOList            => '' 
                          };
    $hash->{AttrX}{tempTmplSet} = {                    # cmd
                           tempListTmpl      => ''     # set default - no list options by default
                          };
    foreach my $atTyp (keys %{$hash->{AttrX}}){
      foreach my $atDef (keys %{$hash->{AttrX}{$atTyp}}){
        $hash->{ModulAttr}{$atDef}{$atTyp} = 1;
      }
    }
    $hash->{AttrList} = join(" ",sort 
                                 map{my ($foo) = sort keys %{$hash->{ModulAttr}{$_}}; # use first option
                                       my $val = $hash->{AttrX}{$foo}{$_};
                                       $_.($val ? ':'.$val                         # add colon
                                                : '')
                                      }    
                                 CUL_HM_noDup(sort keys %{$hash->{ModulAttr}})         # each attr just once
                             );
  }
  # update dependant
  if(defined $hash->{tempListTmplLst} && $hash->{tempListTmplLst} ne $hash->{AttrX}{tempTmplSet}){
    $hash->{AttrX}{tempTmplSet} = {                    # cmd
                           tempListTmpl      => (defined $hash->{tempListTmplLst} ? $hash->{tempListTmplLst} : '')
                          };
    foreach (devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=subType!=virtual")){
      CUL_HM_AttrAssign($_) if(CUL_HM_SearchCmd($_,"tempTmplSet"));
    }
  }
  return;
}
sub CUL_HM_AttrAssign($) {###########################
  #define the list of valid attributes per entity
  #remove attributes that are illegal
  my ($name) = @_;
  my $entH = $defs{$name};
  my $modH = $modules{CUL_HM};
  return undef if (!$init_done); # we cannot determine now. if attributes are missing
  my   @attrGrp = ('glb'); # global for all CUL_HM
  push @attrGrp,'dev'         if ($entH->{helper}{role}{dev});
  push @attrGrp,'devPhy'      if ($entH->{helper}{role}{dev} && !$entH->{helper}{role}{vrt});
  push @attrGrp,'chn'         if ($entH->{helper}{role}{chn});
  push @attrGrp,'virtual'     if ($entH->{helper}{role}{vrt});
  push @attrGrp,'tempTmplSet' if ($entH->{helper}{cmds}{cmdLst}{tempTmplSet});
  push @attrGrp,AttrVal($name,'subType',''); # subType as final - will overwrite values like for param
  push @attrGrp,AttrVal($name,'model','');   # model   as final - will overwrite values like for param
  my %attrHash;
  foreach my $atTyp (@attrGrp){
    foreach my $atDef (keys %{$modH->{AttrX}{$atTyp}}){
      $attrHash{$atDef} = $modH->{AttrX}{$atTyp}{$atDef};
    }
  }
  $entH->{'.AttrList'} = join(" ",sort 
                       map{$_.($attrHash{$_} ? ':'.$attrHash{$_}                         # add colon
                                             : '')
                          }    
                       keys %attrHash         # each attr just once
  );
  foreach (keys %{$attr{$name}}){ # check if CUL_HM Attributs are used and are not compliant to current settings
    next if (!defined $modH->{ModulAttr}{$_} # attr not CUL_HM controlled
          || defined $attrHash{$_});         # attr allowed for entity
    Log3 $name,1,"CUL_HM attr $_ removed for $name. Inadequate";
    delete $attr{$name}{$_};
  }
  return;
}

sub CUL_HM_prtInit($){ #setup protocol variables after define
  my ($hash)=@_;
  $hash->{helper}{prt}{sProc} = 0; # stack not being processed by now
  $hash->{helper}{prt}{bErr} = 0;
}
sub CUL_HM_hmInitMsg($){ #define device init msg for HMLAN
  #message to be send to HMLAN/USB to define device communication defails
  #bit-usage is widely unknown. 
  #p[1]: 00000001 = request AES
  #p[1]: 00000010 = data pending - autosend wakeup and lazyConfig
  #                   if device send data
  #p[2]: is this the number of the AES key to be used? 
  return if (!$init_done);
  my ($hash)=@_;
  my $rxt = CUL_HM_getRxType($hash);
  my $id = CUL_HM_hash2Id($hash);
  my @p;
  my $name = $hash->{NAME};
  my $mask = ($hash->{helper}{role}{chn} && AttrVal($name,"aesCommReq",0))?2:0;
  foreach (grep /channel/,keys %{$hash}){
    $mask |= (2 **  hex(substr($_,8,2))) if(AttrVal($hash->{$_},"aesCommReq",0));
  }

  if    ($mask<256)   {$mask = join("",reverse unpack "(A2)*",sprintf("%02X",$mask));}
  elsif ($mask<65536) {$mask = join("",reverse unpack "(A2)*",sprintf("%04X",$mask));}
  else                {$mask = join("",reverse unpack "(A2)*",sprintf("%08X",$mask));}
  my ($highestKey, undef) = CUL_HM_getKeys($hash);
  my $key = sprintf("%02X",AttrVal($name,"aesKey",$highestKey));
  
  @p = ("$id","00",$key,$mask) if (!$hash->{helper}{role}{vrt});

  if (AttrVal($name,"aesCommReq",0)){
    $p[1] = sprintf("%02X",(hex($p[1]) + 1));
    $p[3] = ($p[3]eq "")?"1E":$p[3];
  }
  $hash->{helper}{io}{newChn} = "";
  $hash->{helper}{io}{rxt} = (($rxt & 0x18)            #wakeup || #lazyConfig
                             && AttrVal($name,"model",0) !~ m/HM-WDS100-C6-O/) #Todo - not completely clear how it works - O and O2
                                 ?2:0;
  $hash->{helper}{io}{p} = \@p;
  my $wu = $hash->{helper}{io}{flgs} ? ($hash->{helper}{io}{flgs} & 0x02) : 0;
  CUL_HM_hmInitMsgUpdt($hash, $wu);
}
sub CUL_HM_hmInitMsgUpdt($;$){ #update device init msg for HMLAN
  my ($hash, $wakeupPrep)=@_;
  return if (  $hash->{helper}{role}{vrt}
             ||!defined $hash->{helper}{io}{p});
  my $oldChn = $hash->{helper}{io}{newChn};
  my @p = @{$hash->{helper}{io}{p}}; # local copy of basic setting
  # General todo
  #  $p[1] |= 2; need to be set if data is pending for a wakeup device. 
  # it will force HMLAN to send A112 (have data). HMLAN will return 
  # status "81" ACK if the device answers the A112 - FHEM should start sending Data by then
  # 
  if (   $wakeupPrep
      || (   $hash->{cmdStack}
          && $hash->{helper}{prt}{sProc}
          && !$hash->{helper}{io}{supWu})
     ){
    $hash->{helper}{io}{flgs} = hex($p[1]) | $hash->{helper}{io}{rxt};
  }
  else{
    $hash->{helper}{io}{flgs} = hex($p[1]); # remove this wakup Bit if no more data to send
                                            # otherwise could cause continous send (e.g. from SC)
  }
  $p[1] = sprintf("%02X", $hash->{helper}{io}{flgs});
  $hash->{helper}{io}{newChn} = '+'.join(",",@p);
  if (   $wakeupPrep
      || (   $hash->{helper}{io}{newChn} ne $oldChn
          && $hash->{IODev} )
      ) {
    if (   $hash->{IODev}->{helper}{VTS_AES} # for TSCUL VTS0.14 up
        || (   $hash->{IODev}->{TYPE}
            && $hash->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s )) {
      IOWrite($hash, "", "init:$p[0]");
    }
    else {
      if ($hash->{helper}{io}{flgs} & 0x02) { $hash->{helper}{io}{sendWu} = 1;     } #noansi: for CUL
      else                                  { delete($hash->{helper}{io}{sendWu}); }
    }
  }
}

sub CUL_HM_Notify(@){###############################
  my ($ntfy, $dev) = @_;
  #$ntfy - whom to notify
  #$dev  - who changed
  return undef if(  $dev->{NAME} eq $ntfy->{NAME}
                  ||$dev->{NAME} ne "global"
                 );# no notification about myself
  my $events = $dev->{CHANGED};
  return undef if(!$events); # Some previous notify deleted the array.
  #my $cws = join(";#",@{$dev->{CHANGED}});
  my $count;

  foreach my $evnt(@{$events}){
    if($evnt =~ m/^(DELETEATTR)/){
    }
    elsif ($evnt =~ m/^(ATTR)/){#ATTR
      if($evnt =~ m/^ATTR (.*) ignore 1/){#ATTR ignore - was it the primary notification device?
        my (undef,$ent) =split(" ",$evnt);
        if ($ent eq $modules{CUL_HM}{helper}{primary}){
          $modules{CUL_HM}{helper}{primary} = ""; # force rescan  
          CUL_HM_primaryDev();
          $count++;
        }
      }
    }
    elsif ($evnt =~ m/^(DELETED|RENAMED) (.*?) ?/){
      my ($cmd,$ent,$new) =split(" ",$evnt." ");
      # $ent no longer exist
      # $new is the renamed (if rename)
      if (($evnt eq "DELETED" && $defs{$ent}{TYPE} eq "CUL_HM")
        ||($evnt eq "RENAMED" && $defs{$new}{TYPE} eq "CUL_HM")){
        CUL_HM_Rename($new,$ent) if($evnt eq "RENAMED");
        CUL_HM_primaryDev() if ($ent eq $modules{CUL_HM}{helper}{primary});
        if ($evnt eq 'DELETED' && $defs{$ent}{DEF} =~ m{\A[.]{6}\z} && defined $defs{$ent}->{IODev} && defined $defs{$ent}->{IODev}->{TYPE} && $defs{$ent}->{IODev}->{TYPE} =~ m/^(HMLAN|HMUARTLGW)$/) { 
          IOWrite($defs{$ent}, '', "remove:".CUL_HM_hash2Id($defs{$ent}));
        }
        $count++;
      }
      else{##------- update dependancies to IO devices used
        my @culHmDevs = grep{$defs{$_}{DEF} =~ m/^......$/} grep{$defs{$_}{TYPE} eq "CUL_HM"} keys %defs;
        ## ------ correct IOList and IOGrp
        foreach my $vccu (grep{AttrVal($_,"IOList","") =~ m/,?$ent/} @culHmDevs){# for each vccu
          my $ea = my $eaOld = AttrVal($vccu,"IOList","");
          $ea = join(",",map{my $foo = $_;$foo =~ s/$ent/$new/;$foo}
                         split(",",$ea));
          foreach my $HMdef(grep{AttrVal($_,"IOgrp","") =~ m/$vccu:.*$ent/} @culHmDevs){
            if($ea){#vccu still operational
              my (undef,$ios) = split(":",AttrVal($HMdef,"IOgrp",""));
              $ios = join(",",
                     grep{defined $defs{$_}}
                     map{my $foo = $_;$foo =~ s/$ent/$new/;$foo} 
                     split(",",$ios)
                     );
              $attr{$HMdef}{IOgrp} = "$vccu".($ios ? ":$ios" : "");
              $count++;
            }
            else {# the vccu has no IO anymore - delete clients
              CommandDeleteAttr (undef,"$HMdef IOgrp") ; 
              $count++;
            }
          }
          if ($ea ne $eaOld) {
            CommandAttr (undef,"$vccu IOList $ea");
            $count++;
          }
        }
        foreach my $HMdef (grep{AttrVal($_,"IODev","") eq $ent} @culHmDevs){# for each IODev
          next if IsDummy($HMdef) || IsIgnored($HMdef);
          CommandAttr (undef,"$HMdef IODev $new");
          $count++;
        }
      }
      return ($count ? "CUL_HM: $count device(s) renamed or attributes changed due to DELETED or RENAMED event"
                     : undef);
    }
    elsif (!$modules{CUL_HM}{helper}{initDone} && $evnt =~ m/INITIALIZED/){# grep the first initialize
      CUL_HM_updateConfig("startUp");
      InternalTimer(1,"CUL_HM_setupHMLAN", "initHMLAN", 0);#start asap once FHEM is operational
    }
    elsif ($evnt =~ m/REREADCFG/){
      Log3($ntfy,0,"[FAILURE] CUL_HM doesn't reliably support rereadcfg any longer! Restart FHEM instead.");
      delete $modules{CUL_HM}{helper}{initDone};
      InternalTimer(1,"CUL_HM_setupHMLAN", "initHMLAN", 0);
      CUL_HM_updateConfig("startUp");
    }
#    elsif($evnt =~ m/(DEFINED)/  ){ Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}
#    elsif($evnt =~ m/(SHUTDOWN)/ ){ Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}#SHUTDOWN|DELAYEDSHUTDOWN
#    elsif($evnt =~ m/(SAVE)/     ){ Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}
#    elsif($evnt =~ m/(REREADCFG)/){ Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}
#    elsif($evnt =~ m/(MODIFIED)/ ){ Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}
#    else                          { Log 1,"Info --- $dev->{NAME} -->$ntfy->{NAME} :  $evnt";}

  }

  return undef;
}

sub CUL_HM_setupHMLAN(@){#################################
  foreach (devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=subType!=virtual:FILTER=dummy!=1:FILTER=ignore!=1")){
    $defs{$_}{helper}{io}{newChn} = "";
    CUL_HM_hmInitMsg($defs{$_}); #update device init msg for HMLAN
  }
}

#+++++++++++++++++ msg receive, parsing++++++++++++++++++++++++++++++++++++++++
# translate level to readable
    my %lvlStr = ( md  =>{ "HM-SEC-WDS"      =>{"00"=>"dry"     ,"64"=>"damp"    ,"C8"=>"wet"        }
                          ,"HM-SEC-WDS-2"    =>{"00"=>"dry"     ,"64"=>"damp"    ,"C8"=>"wet"        }
                          ,"HM-CC-SCD"       =>{"00"=>"normal"  ,"64"=>"added"   ,"C8"=>"addedStrong"}
                          ,"HM-SEN-RD-O"     =>{"00"=>"dry"                      ,"C8"=>"rain"}
                          ,"HM-MOD-EM-8"     =>{"00"=>"closed"                   ,"C8"=>"open"}
                          ,"HM-WDS100-C6-O"  =>{"00"=>"quiet"                    ,"C8"=>"storm"}
                         }
                  ,mdCh=>{ "HM-SEN-RD-O01"   =>{"00"=>"dry"                      ,"C8"=>"rain"}
                          ,"HM-SEN-RD-O02"   =>{"00"=>"off"                      ,"C8"=>"on"}
                         }
                  ,st  =>{ "smokeDetector"   =>{"01"=>"no alarm","C7"=>"tone off","C8"=>"Smoke Alarm"}
                          ,"threeStateSensor"=>{"00"=>"closed"  ,"64"=>"tilted"  ,"C8"=>"open"}
                         }
                  );
                  
    my %disColor=(white=>0,red=>1,orange=>2,yellow=>3,green=>4,blue=>5);
    my %disIcon=( off =>0, on=>1, open=>2, closed=>3, error=>4, ok=>5
                 ,info=>6, newMsg=>7, serviceMsg=>8 
                 ,sigGreen=>9, sigYellow=>10, sigRed=>11
                 ,ic12=>12, ic13=>13
                 ,noIcon=>99
                );
    my %disBtn=(  txt01_1=>0, txt01_2=>1, txt02_1=>2, txt02_2=>3, txt03_1=>4 
                , txt03_2=>5, txt04_1=>6, txt04_2=>7, txt05_1=>8, txt05_2=>9
                , txt06_1=>10,txt06_2=>11,txt07_1=>12,txt07_2=>13,txt08_1=>14
                , txt08_2=>15,txt09_1=>16,txt09_2=>17,txt10_1=>18,txt10_2=>19
                );


sub CUL_HM_Parse($$) {#########################################################
  my ($iohash, $msgIn) = @_;
  
  my %mh; # hash for data of this message
  
  ($mh{msg},$mh{msgStat},$mh{myRSSI},$mh{msgIO},$mh{auth}) = split(":",$msgIn,5);
  ($mh{t},$mh{len},$mh{mNo},$mh{mFlg},$mh{mTp},$mh{src},$mh{dst},$mh{p}) = unpack 'A1A2A2A2A2A6A6A*',$mh{msg};
  $mh{mFlgH} = hex($mh{mFlg});

  # Msg format: Allnnffttssssssddddddpp...
  return if (!$iohash ||
             ref($iohash) ne 'HASH'  ||
             $mh{t} ne 'A'  || 
             length($mh{msg})<20);

  if ($modules{CUL_HM}{helper}{updating}){
    if ("done" eq CUL_HM_FWupdateSteps($mh{msg})){
      my $sH = CUL_HM_id2Hash($mh{src});
      my @e = CUL_HM_pushEvnts();
      $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$sH->{NAME}$/,@e);
      return (@e,$sH->{NAME}); #return something to please dispatcher
    }
    else{
      return "";
    }
  }
 
  return "" if($mh{msgStat} && $mh{msgStat} eq 'NACK');# lowlevel error

  $mh{rectm} = gettimeofday(); # take reception time 
  $mh{tmStr} = FmtDateTime($mh{rectm});
  $mh{p} = "" if(!defined($mh{p})); # generate some abreviations 
  my @mI = unpack '(A2)*',$mh{p}; # split message info to bytes
  $mh{mStp} = $mI[0] ? $mI[0] : ""; #message subtype
  $mh{mTyp} = $mh{mTp}.$mh{mStp};           #message type/subtype

  # $shash will be replaced for multichannel commands
  $mh{devH}   = CUL_HM_id2Hash($mh{src}); #sourcehash - will be modified to channel entity
  $mh{dstH}   = CUL_HM_id2Hash($mh{dst}); # destination device hash
  $mh{id}     = CUL_HM_h2IoId($iohash);
  $mh{ioName} = $iohash->{NAME};
  $evtDly     = 1;# switch delay trigger on
  CUL_HM_statCnt($mh{ioName},"r",$mh{mFlgH});
  $mh{dstN}   = ($mh{dst} eq "000000") ? "broadcast" :
                         ($mh{dstH} ? $mh{dstH}->{NAME} :
                    ($mh{dst} eq $mh{id} ? $mh{ioName} :
                                   $mh{dst}));
  if(!$mh{devH} && $mh{mTp} eq "00") { # generate device
    my $sname = "HM_$mh{src}";
    my $acdone;
    if ( InternalVal($mh{ioName},'hmPair',InternalVal(InternalVal($mh{ioName},'owner_CCU',''),'hmPair',0 ))) { # initiated via hm-pair-command => User wants actively have the device created
      if (IsDisabled((devspec2array('TYPE=autocreate'))[0]) ) { 
        my $defret = CommandDefine(undef,"$sname CUL_HM $mh{src}");
        Log 2,"CUL_HM Unknown device $sname is now defined ".(defined $defret ? " return: $defret" : "");
      } 
      else { 
        DoTrigger('global', "UNDEFINED $sname CUL_HM $mh{src}"); #Beta-User: procedure similar to ZWave
        CommandAttr(undef,"$sname room CUL_HM") if !AttrVal((devspec2array('TYPE=autocreate'))[0],'device_room',0); #Beta-User: see https://forum.fhem.de/index.php/topic,125507.msg1201540.html#msg1201540
      }
      $acdone = 1;
    } 
    elsif (!IsDisabled((devspec2array('TYPE=autocreate'))[0]) && !defined InternalVal($mh{ioName},'owner_CCU',undef)) {
      #Beta-User: no vccu, write Log
      Log3($mh{ioName},2,"CUL_HM received learning message from unknown id $mh{src} outside of pairing mode. Please enable pairing mode first or define a virtual device w. model: CCU-FHEM.");
    }
    if ($acdone) {
      $mh{devN} = $sname ;
      $mh{devH} = CUL_HM_id2Hash($mh{src}); #sourcehash - changed to channel entity
      $mh{devH}->{IODev} = $iohash;
      if (!$modules{CUL_HM}{helper}{hmManualOper}){
        my $ioOwn = InternalVal($mh{ioName},'owner_CCU','');
        $defs{$sname}{IODev} = $defs{$mh{ioName}}; 
        if ($ioOwn) {
          $attr{$sname}{IOgrp} = $ioOwn;
          $mh{devH}->{helper}{io}{vccu} = $ioOwn;
          if (   defined($mh{myRSSI})
              && $mh{myRSSI} ne ''
              && $mh{myRSSI} >= -50) { #noansi: on good rssi set prefered, too
            $attr{$sname}{IOgrp} .= ':'.$mh{ioName};
            my @a = ();
            $mh{devH}->{helper}{io}{prefIO} = \@a;
          }
        }
      }
      else{
        $attr{$sname}{IODev} = $mh{ioName}; 
      }
      $mh{devH}->{helper}{io}{nextSend} = $mh{rectm}+0.09 if(!defined($mh{devH}->{helper}{io}{nextSend}));# io couldn't set
    }
  }

  my @entities = ("global"); #additional entities with events to be notifies
  ####################  attack alarm detection#####################
  if (   $mh{dstH} && $mh{dst} ne "000000"
      && !CUL_HM_getAttrInt($mh{dstN},"ignore")
      && ($mh{mTp} =~ m/^(01|11|3E)$/
      )){
    my $ioId = AttrVal($mh{dstH}->{IODev}{NAME},"hmId","-");
    if($ioId ne $mh{src}){
      if (   !defined $mh{dstH}->{"prot"."ErrIoId_$mh{src}"} 
          && ReadingsVal($mh{dstN},"sabotageAttackId_ErrIoId_$mh{src}:",undef)){
        (undef,$mh{dstH}->{"prot"."ErrIoId_$mh{src}"}) =
          split(":",ReadingsVal($mh{dstN},"sabotageAttackId_ErrIoId_$mh{src}:",undef));
      }
      CUL_HM_eventP($mh{dstH},"ErrIoId_$mh{src}");
      my ($evntCnt,undef) = split(' last_at:',$mh{dstH}->{"prot"."ErrIoId_$mh{src}"},2);
      push @evtEt,[$mh{dstH},1,"sabotageAttackId_ErrIoId_$mh{src}: cnt:$evntCnt"];
    }
    my $tm = substr($mh{msg},7);
    if( !defined $mh{dstH}->{helper}{cSnd} || 
          $mh{dstH}->{helper}{cSnd} !~ m/$tm/){
      if (   !defined $mh{dstH}->{"prot"."ErrIoAttack"} 
          && ReadingsVal($mh{dstN},"sabotageAttack_ErrIoAttack_cnt:",undef)){
        $mh{dstH}->{"prot"."ErrIoAttack"} =
          ReadingsVal($mh{dstN},"sabotageAttack_ErrIoAttack_cnt:",undef);
      }
      
      Log3 $mh{dstN},3,"CUL_HM $mh{dstN} attack:".($mh{dstH}->{helper}{cSnd} ? $mh{dstH}->{helper}{cSnd} : "").":$tm";
      CUL_HM_eventP($mh{dstH},"ErrIoAttack");
      my ($evntCnt,undef) = split(' last_at:',$mh{dstH}->{"prot"."ErrIoAttack"},2);
      push @evtEt,[$mh{dstH},1,"sabotageAttack_ErrIoAttack_cnt:$evntCnt"];
    }
  }
  ###########

  #  return "" if($mh{src} eq $mh{id});# mirrored messages - covered by !$shash
  if(!$mh{devH}){    # Unknown source
    $evtDly    = 0;# switch delay trigger off
    return "" if ($mh{msg} =~ m/998112......000001/);# HMLAN internal message, consum 
    my $ccu = InternalVal($mh{ioName},"owner_CCU","");
    CUL_HM_DumpProtocol("RCV",$iohash,$mh{len},$mh{mNo},$mh{mFlg},$mh{mTp},$mh{src},$mh{dst},$mh{p});

    if ($defs{$ccu}){#
      push @evtEt,[$defs{$ccu},0,"unknown_$mh{src}:received"];# do not trigger

      return CUL_HM_pushEvnts();
    }
    return;
  }

  $mh{devN}   = $mh{devH}->{NAME};        # source device name
  if (CUL_HM_getAttrInt($mh{devN},"ignore")){
    $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devN}$/,@entities);
    return (CUL_HM_pushEvnts(),$mh{devN},@entities);
  }

  my $IOchanged = 0; # track a change of IO dev to ensure aesCommReq validation

  if (   !defined $mh{devH}->{IODev}
      || !$mh{devH}->{IODev}{NAME}){
    $IOchanged += CUL_HM_assignIO($mh{devH}); # this way the init and remove work even on startup for TSCUL.
    if (   !defined $mh{devH}->{IODev}
        || !$mh{devH}->{IODev}{NAME}){
      Log3 $mh{devH},1,"CUL_HM $mh{src} error: no IO deviced!!! correct it";
      $mh{devH}->{IODev} = $iohash;
      $IOchanged = 1;
    }
    delete($mh{devH}->{IODev}{'.clientArray'}) if ($mh{devH}->{IODev}); # Force a recompute
  }

  $respRemoved = 0;  #set to 'no response in this message' at start
  $mh{shash}  = $mh{devH};                # source hash - will be redirected to channel if applicable
  my $ioId = CUL_HM_h2IoId($mh{devH}->{IODev});
  $ioId = $mh{id} if(!$ioId);

  CUL_HM_storeRssi($mh{devN}
                  ,"at_".(($mh{mFlgH}&0x40)?"rpt_":"").$mh{ioName} # repeater?
                  ,$mh{myRSSI}
                  ,$mh{mNo});
  #----------CUL aesCommReq handling---------
  my $oldIo     = $mh{devH}{IODev}->{NAME};
  my $aComReq   = AttrVal($mh{devN},"aesCommReq",0); #aesCommReq enabled for device 
  my $dIoOk     = ($mh{devH}{IODev}{NAME} eq $mh{ioName}) ? 1 : 0;
  my $aIoAESCap = (   $mh{devH}{IODev}->{helper}{VTS_AES}
                   || AttrVal($mh{devH}{IODev}->{NAME},"rfmode","") ne "HomeMatic" ) ? 1 : 0; # assigned IO AES cappable
  $mh{devH}->{helper}{aesAuthBytes} = $mh{auth} if($mh{auth}); # let CUL_HM ACK with authbytes. tsculfw does default ACK automatically only. A default ACK may just update a default ACK in tsculfw buffer
  if (   $aComReq                      #aesCommReq enabled for device
      && (!$dIoOk || $IOchanged)       #message not received on assigned IO or change in IO
      && ($mh{msgStat} !~ m/^AES/) ) { #receiving IO did not already do AES processing for us
 
    my $oldIoAESCap = $aIoAESCap;
    $IOchanged += CUL_HM_assignIO($mh{devH}); #update IO in case of roaming
    $aIoAESCap = (   defined($mh{devH}->{IODev})
                  && (   $mh{devH}{IODev}->{helper}{VTS_AES}
                      || AttrVal($mh{devH}{IODev}->{NAME},"rfmode","") ne "HomeMatic" ) ) ? 1 : 0; # newly assigned IO AES cappable
    $dIoOk     = (   defined($mh{devH}->{IODev})
                  && ($mh{devH}{IODev}->{NAME} eq $mh{ioName}) ) ? 1 : 0; # newly assigned IO received message
    if (   !$dIoOk                      #message not received on assigned new IO
        || $IOchanged                   #IO changed, so AES state is unkown
        || $oldIoAESCap                 #old IO is AES cappable (not standard CUL) and should have handled it, as it was set to do so
        || $aIoAESCap   ) {             #new IO is AES cappable (not standard CUL), but did not handle it as it was not set to do so
      Log3 $mh{devH},5,"CUL_HM ignoring message for ${oldIo} received on $mh{ioName}";
      #Do not process message further, the assigned IO has to handle it
      $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devN}$/,@entities);
      return (CUL_HM_pushEvnts(),$mh{devN});
    }
  }
  #----------CUL aesCommReq handling---------
  if (   !$aIoAESCap               #IO is not aesCommReq cappable (standard CUL)
      && $aComReq                  #aesCommReq enabled for device
      && $dIoOk                    #message received on assigned IO
      && $cryptFunc == 1 
      && $ioId eq $mh{dst}) {

    if ($mh{devH}->{helper}{aesCommRq}{msgStat}) {
      #----------Message was already handled, pass on result---------
      $mh{msgStat} = $mh{devH}->{helper}{aesCommRq}{msgStat};
      delete($mh{devH}->{helper}{aesCommRq});

    } 
    elsif (   $mh{devH}->{helper}{aesCommRq}{msg} 
             && $mh{mTp} eq "03") {

      #----------Check AES response from device (CUL)---------
      my $aesM = $mh{devH}->{helper}{aesCommRq}{msg};
      my (undef, %keys) = CUL_HM_getKeys($mh{devH});
      my $key = $keys{$mh{devH}->{helper}{aesCommRq}{kNo}};
      $key = $key ^ pack("H12", $mh{devH}->{helper}{aesCommRq}{challenge});

      my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_ECB());
      my $iv = pack("H*", substr($aesM, 23));
      my $response =  $cipher->decrypt(pack("H32", $mh{p})) ^ $iv;
      my $authbytes = unpack("H8", $response);
      $response = $cipher->decrypt(substr($response, 0, 16));

      my $cmd = uc unpack("H20",substr($response, 6, 1) .
                             chr(ord(substr($response, 7, 1)) & 0xbf) . #~RPTED
                             substr($response, 8, 8));

      my $origcmd = uc substr($aesM, 3, 2) .
                    sprintf("%02X", (hex(substr($aesM, 5, 2)) & 0xbf)) . #~RPTED
                    substr($aesM, 7, 16);
 
      Log3 $mh{devH},5,"CUL_HM $mh{dstN} iv: ".unpack("H*", $iv)
                  ."\n             decrypted cmd: $cmd"
                  ."\n             original  cmd: $origcmd";
 
      if ($cmd eq $origcmd) {
        Log3 $mh{devH},4,"CUL_HM $mh{dstN} signature: good, authbytes: ${authbytes}";
        $mh{devH}->{helper}{aesAuthBytes} = $authbytes;
        $mh{devH}->{helper}{aesCommRq}{msgStat} = "AESCom-ok";
      } 
      else {
        Log3 $mh{devH},2,"CUL_HM $mh{dstN} signature: bad";
        $mh{devH}->{helper}{aesCommRq}{msgStat} = "AESCom-fail";
      }
 
      #continue with old message
      return CUL_HM_Parse($iohash, $mh{devH}->{helper}{aesCommRq}{msgIn});
    } 
    else {
      my $doAES = 1;
      my $chn;
      if($mh{mTp} =~ m/^4[01]/){ #someone is triggered##########
        $chn = $mI[0];
      } 
      elsif ($mh{mTp} eq "10") {
        if ($mh{mStp} =~ m/^0[46]/) {
          $chn = $mI[1];
        } 
        elsif ($mh{mStp} eq "05") {
          if ($mI[7] ne "00") { #m:1E A010 4CF663 1743BF 0500(00000000)(07)(00)  # 00 is finish packet
            $chn = $mI[1];
          }
          else {
            $doAES = 0;
          }
        }
        elsif (   $mh{mStp} eq "01"
              ||!($mh{mFlgH} & 0x20)) { #response required Flag
          $doAES = 0;
        }
        else {
          $doAES = 0; #noansi: no channel, no AES... or chn 00?
        }
      } 
      elsif ($mh{mTp} =~ m/^0[23]/) {
        $doAES = 0;
      }

      if ($doAES && defined $chn && defined(CUL_HM_id2Hash($mh{src}.sprintf("%02X",$chn)))) {
        CUL_HM_m_setCh(\%mh,$chn);
      }
    
      if (   $doAES
          && AttrVal($mh{cName},"aesCommReq",0)) { #aesCommReq enabled for channel

        #----------Generate AES challenge for device (CUL)---------
        my ($kNo, %keys) = CUL_HM_getKeys($mh{devH});
        $kNo = AttrVal($mh{devN},"aesKey",$kNo);
        if (defined($keys{$kNo})) {
          my $challenge = (defined($mh{devH}->{helper}{aesCommRq}{challenge}))
                            ? $mh{devH}->{helper}{aesCommRq}{challenge}
                            : sprintf("%08X%04X",rand(0xffffffff), rand(0xffff));

          Log3 $mh{cHash},5,"CUL_HM $mh{devN} requesting signature with challenge $challenge for key $kNo";

          $mh{devH}->{helper}{aesCommRq}{msg} = $mh{msg};
          $mh{devH}->{helper}{aesCommRq}{msgIn} = $msgIn;
          $mh{devH}->{helper}{aesCommRq}{challenge} = $challenge;
          $mh{devH}->{helper}{aesCommRq}{kNo} = $kNo;

          my $cmd = $mh{mNo}.($mh{devH}->{helper}{io}{sendWu}?'A1':'A0')."02$mh{dst}$mh{src}04$challenge".sprintf("%02X", $kNo*2);
          $cmd = sprintf("As%02X%s", length($cmd)/2, $cmd);
          IOWrite($mh{devH}, "", $cmd);
          $mh{msgStat}="AESpending";
        } 
        else {
          delete($mh{devH}->{helper}{aesCommRq});  # cleanup CUL aesCommReq -> we can check it in CUL_HM_assignIO not to change IO while CUL aesCommReq in progress
          Log3 $mh{cHash},1,"CUL_HM $mh{devN} required key $mh{kNo} not defined in VCCU!";
        }
      } 
      else {
        delete($mh{devH}->{helper}{aesCommRq});
      }
    }
  }

  if ($mh{msgStat}){
    if   ($mh{msgStat} =~ m/^AESKey/){
      push @evtEt,[$mh{devH},1,"aesKeyNbr:".substr($mh{msgStat},7)];
      $mh{msgStat} = ""; # already processed
    }
    elsif($mh{msgStat} =~ m/^AESpending/){# AES communication pending
      push @evtEt,[$mh{devH},1,"aesCommToDev:pending"];
      if ($mh{mTyp} eq "0204") {
        my $aesKeyNbr = substr($mh{p},14,2);
        push @evtEt,[$mh{devH},1,"aesKeyNbr:".$aesKeyNbr] if (defined $aesKeyNbr);
      }
      #Do not process message further, as it may be faked
      $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devN}$/,@entities);
      return (CUL_HM_pushEvnts(),$mh{devN});
    }
    elsif($mh{msgStat} =~ m/^AESCom/){# AES communication to central
      my $aesStat = substr($mh{msgStat},7);
      push @evtEt,[$mh{devH},1,"aesCommToDev:".$aesStat];
      ### General may need substential rework
      # activate AES only for dedicated channels?
      if($mh{mTp} =~ m/^4[01]/){ #someone is triggered##########
        my $chn = hex($mI[0])& 0x3f;
        my $cName = CUL_HM_id2Name($mh{src}.sprintf("%02X",$chn));
        $cName = CUL_HM_id2Name($mh{src}) if (!defined($defs{$cName}));
        my $bCnt = hex($mI[1]);
        push @evtEt,[$defs{$cName},1,"trig_aes_$mh{dstN}:$aesStat:$bCnt"] 
              if (defined $defs{$cName});

        if($aesStat eq "ok"                     #aes ok
           && defined $mh{devH}->{cmdStacAESPend}   #commands waiting
           && $ioId eq $mh{dst}){                   #aes from IO device
          foreach (@{$mh{devH}->{cmdStacAESPend}}) {
            my ($h,$c) = split(";",$_);
            CUL_HM_PushCmdStack(CUL_HM_id2Hash($h),$c);
          }
          CUL_HM_ProcessCmdStack($mh{devH});
        }
        delete $mh{devH}->{cmdStacAESPend};          

        my @peers = CUL_HM_getPeers($cName,"IDs");
        foreach my $peer (grep /$mh{dst}/,@peers){
          my $pName = CUL_HM_id2Name($peer);
          $pName = CUL_HM_id2Name(substr($peer,0,6)) if (!$defs{$pName});
          next if (!$defs{$pName});
          push @evtEt,[$defs{$pName},1,"trig_aes_$cName:$aesStat:$bCnt"];
        }
      }
      if ($aesStat ne "ok") { #unauthenticated message, abort
        $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devH}->{NAME}$/,@entities);
        return (CUL_HM_pushEvnts(),$mh{devN});
      }
    }
  }
  CUL_HM_eventP($mh{devH},"Evt_$mh{msgStat}")if ($mh{msgStat});#log io-events
  my $target = " (to $mh{dstN})";

  $mh{st} = defined $defs{$mh{devN}}{helper}{mId} ? $culHmModel->{$defs{$mh{devN}}{helper}{mId}}{st}   : AttrVal($mh{devN}, "subType", "");
  $mh{md} = defined $defs{$mh{devN}}{helper}{mId} ? $culHmModel->{$defs{$mh{devN}}{helper}{mId}}{name} : AttrVal($mh{devN}, "model"  , "");

#  $mh{st} = AttrVal($mh{devN}, "subType", "");
#  $mh{md} = AttrVal($mh{devN}, "model"  , "");

  # +++++ check for duplicate or repeat ++++
  my $msgX = "No:$mh{mNo} - t:$mh{mTp} s:$mh{src} d:$mh{dst} ".($mh{p}?$mh{p}:"");
  if (   defined($mh{devH}->{lastMsg})
      && $mh{devH}->{lastMsg} eq $msgX
      && (   $mh{mTp} ne '00'
          || (($mh{devH}->{helper}{lastMsgTm}+6) > $mh{rectm}) )
      ) { #duplicate -lost 'ack'?
           
    if(   $mh{devH}->{helper}{rpt}                           #was responded
       && $mh{devH}->{helper}{rpt}{IO}  eq $mh{ioName}           #from same IO
       && $mh{devH}->{helper}{rpt}{flg} eq substr($mh{msg},5,1)  #not from repeater
       && $mh{devH}->{helper}{rpt}{ts}  < $mh{rectm}-0.24 # again if older then 240ms (typ repeat time)
                                                          #todo: hack since HMLAN sends duplicate status messages
       ){
      my $ack = $mh{devH}->{helper}{rpt}{ack};#shorthand
      $mh{devH}->{helper}{rpt}{ts} = $mh{rectm};
      if (scalar(@{$ack})) {
        my $i = 0;
        my $wulzy =    defined($mh{devH}->{helper}{io}{flgs})
                    && ($mh{devH}->{helper}{io}{flgs} & 0x02)
                    && $mh{devH}->{cmdStack}
                    && scalar @{$mh{devH}->{cmdStack}}; #noansi: wakeup replacement required
        my ($h, $m);
        while ($i < scalar(@{$ack})) {
          $h = ${$ack}[$i++];
          $m = ${$ack}[$i++];
          if ($mh{devH}->{helper}{aesAuthBytes}) {
            $m .= $mh{devH}->{helper}{aesAuthBytes} if (!(   $mh{devH}->{IODev}->{helper}{VTS_AES} # tsculfw does default ACK automatically only. A default ACK may just update a default ACK in tsculfw buffer
                                                          && ($m =~ m/^..(..)02/s))); # append auth bytes to first answer to device after sign from device
            delete($mh{devH}->{helper}{aesAuthBytes});
          }
          if ($wulzy && ($m =~ m/^..(..)02/s)) { #noansi: wakeup replacement for acks
            my $flr = $1;
            next if (   ($flr eq '80')
                     && (   $mh{devH}->{IODev}->{helper}{VTS_LZYCFG} # for TSCUL VTS0.34 up, wakeup Ack automatically sent
                         || $mh{devH}->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s ) ); # also for HMLAN/HMUARTLGW?
            $flr = sprintf("%02X", hex($flr)|0x01);
          }
          CUL_HM_SndCmd($h, $m);
        }
        Log3 $mh{devN},5,"CUL_HM $mh{devN} dupe: repeat ".scalar(@{$ack})." ack, dont process";
      }
    }
    else{
      Log3 $mh{devN},5,"CUL_HM $mh{devN} dupe: dont process";
    }
    CUL_HM_pushEvnts();
    $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devH}->{NAME}$/,@entities);
    CUL_HM_sndIfOpen("x:$mh{ioName}");
    return (CUL_HM_pushEvnts(),$mh{devN},@entities); #return something to please dispatcher
  }
  delete $mh{devH}->{helper}{rpt};# new message, rm recent ack
  my @ack; # ack and responses, might be repeated
  
  CUL_HM_eventP($mh{devH},"Rcv");
  CUL_HM_eventP($mh{devH},"RcvB") if($mh{mFlgH} & 0x10);#burst msg received
  CUL_HM_DumpProtocol("RCV",$iohash,$mh{len},$mh{mNo},$mh{mFlg},$mh{mTp},$mh{src},$mh{dst},$mh{p});

  #----------start valid messages parsing ---------
  my $oldTry = ($mh{devH}->{helper}{prt}{try})? 1: 0;# frank: save old setting
  my $parse = CUL_HM_parseCommon($iohash,\%mh);
  if(!defined $mh{md} or $mh{md} eq '' or $mh{md} eq "unknown"){
    $mh{devN} = '' if (!defined($mh{devN}));
    Log3 $mh{devH},5, "CUL_HM drop msg for $mh{devN} with unknown model";
    $evtDly   = 0;#noansi: switch delay trigger off
    return;
  }
  
  $mh{devH}->{lastMsg}           = $msgX;# is used in parseCommon  and need previous setting. so set it here
  $mh{devH}->{helper}{lastMsgTm} = $mh{rectm};

  push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}"] if($parse eq "powerOn");
  push @evtEt,[$mh{devH},1,""]            if($parse eq "parsed"); # msg is parsed but may
                                                             # be processed further

  if   ($parse eq "ACK" ||
        $parse eq "done"   ){# remember - ACKinfo will be passed on
    delete $mh{devH}->{helper}{prt}{try} if($oldTry && $mh{devH}->{helper}{prt}{try});# frank: delete if the try cmd is successful
    push @evtEt,[$mh{devH},1,""];
  }
  elsif($parse eq "NACK"){
    push @evtEt,[$mh{shash},1,"state:NACK"];
  }
  elsif($parse eq "AES"){
    return CUL_HM_pushEvnts();# exit now, don't send ACK
  }
  elsif($mh{mTp} eq "12") {#$lcm eq "09A112" Another fhem request (HAVE_DATA)
    ;
  }
  elsif($mh{md} =~ m/^(KS550|KS888|HM-WDS100-C6-O)/) { ########################
    if($mh{mTp} eq "70") {
      my ($t,$h,$r,$w,$wd,$s,$b) = map{hex($_)} unpack 'A4A2A4A4(A2)*',$mh{p};
    push @evtEt,[$mh{devH},1,"battery:". (($t & 0x8000)?"low"  :"ok"  )] if ($mh{md} =~ m/^HM-WDS100-C6-O-2/); #has no battery
      my $tsgn = ($t & 0x4000);
      $t = ($t & 0x3fff)/10;
      $t = sprintf("%0.1f", $t-1638.4) if($tsgn);
      my $ir = ($r & 0x8000)?1:0;
      $r = ($r & 0x7fff) * 0.295;
      my $wdr = ($w>>14)*22.5;
      $w = ($w & 0x3fff)/10;
      $wd = $wd * 5;
      my $sM = "state:";
      if(defined $t)  {$sM .= "T: $t "    ;push @evtEt,[$mh{shash},1,"temperature:$t"    ];}
      if(defined $h)  {$sM .= "H: $h "    ;push @evtEt,[$mh{shash},1,"humidity:$h"       ];}
      if(defined $w)  {$sM .= "W: $w "    ;push @evtEt,[$mh{shash},1,"windSpeed:$w"      ];}
      if(defined $r)  {$sM .= "R: $r "    ;push @evtEt,[$mh{shash},1,"rain:$r"           ];}
      if(defined $ir) {$sM .= "IR: $ir "  ;push @evtEt,[$mh{shash},1,"isRaining:$ir"     ];}
      if(defined $wd) {$sM .= "WD: $wd "  ;push @evtEt,[$mh{shash},1,"windDirection:$wd" ];}
      if(defined $wdr){$sM .= "WDR: $wdr ";push @evtEt,[$mh{shash},1,"windDirRange:$wdr" ];}
      if(defined $s)  {$sM .= "S: $s "    ;push @evtEt,[$mh{shash},1,"sunshine:$s"       ];}
      if(defined $b)  {$sM .= "B: $b "    ;push @evtEt,[$mh{shash},1,"brightness:$b"     ];}
      push @evtEt,[$mh{shash},1,$sM];
    }
    elsif ($mh{mTp} eq "41"){
      my ($chn,$state)=(hex($mI[0]),$mI[2]);
      #my $cnt = hex($mI[1]);
      my $txt;
      if    ($mh{cHash}->{helper}{lm} && $mh{cHash}->{helper}{lm}{hex($state)}){$txt = $mh{cHash}->{helper}{lm}{hex($state)}}
      elsif ($lvlStr{md}{$mh{md}})                                             {$txt = $lvlStr{md}{$mh{md}}{$state}}
      elsif ($lvlStr{st}{$mh{st}})                                             {$txt = $lvlStr{st}{$mh{st}}{$state}}
      else                                                                     {$txt = "unknown:$state"}
      push @evtEt,[$mh{cHash},1,"storm:$txt"];
      push @evtEt,[$mh{devH} ,1,"trig_$mh{chnHx}:$mh{dstN}"];
      my $err = $chn & 0x80;
      push @evtEt,[$mh{devH},1,"battery:". ($err?"low"  :"ok"  )] if ($mh{md} =~ m/^HM-WDS100-C6-O-2/); #has no battery
    }
    else {
      push @evtEt,[$mh{shash},1,"unknown:$mh{p}"];
    }
  }
  elsif($mh{md} =~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/) { ######################
    my $chn = $mI[1];
    if(    $mh{mTp} eq "70") { # weather event
      $chn = '01'; # fix definition
      my ($t,$h) = (hex($mI[0].$mI[1]), hex($mI[2]));# temp is 15 bit signed
      $t &= 0x7fff;
      $t = -1 - ($t ^ 0x7FFF) if ($t & 0x4000);
      $t /= 10;
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
      if ($chnHash){
        push @evtEt,[$chnHash,1,"state:T: $t H: $h"];
        push @evtEt,[$chnHash,1,"measured-temp:$t"];
        push @evtEt,[$chnHash,1,"humidity:$h"];
      }
      push @evtEt,[$mh{shash},1,"state:T: $t H: $h"];
      push @evtEt,[$mh{shash},1,"measured-temp:$t"];
      push @evtEt,[$mh{shash},1,"humidity:$h"];
    }
    elsif( $mh{mTp} eq "58") {# climate event
      $chn = '02'; # fix definition
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $mI[0], hex($mI[1]));
      $vp = int($vp/2.56+0.5);   # valve position in %
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
      if($chnHash){
        push @evtEt,[$chnHash,1,"state:$vp"];
        if ($chnHash->{helper}{needUpdate}){
          if ($chnHash->{helper}{needUpdate} == 1){
            $chnHash->{helper}{needUpdate}++;
          }
          else{
            CUL_HM_qStateUpdatIfEnab($chnHash->{NAME});
            delete $chnHash->{helper}{needUpdate};
          }
        }
      }
      push @evtEt,[$mh{devH},1,"actuator:$vp"];

      # Set the valve state too, without an extra trigger
      if($mh{dstH}){
        push @evtEt,[$mh{dstH},1,"state:set_$vp"   ];
        push @evtEt,[$mh{dstH},1,"ValveDesired:$vp"];
      }
    }
    elsif(($mh{mTyp} eq '0201')||    # ackStatus
          ($mh{mTyp} eq '1006')){    # infoStatus
      my $dTemp = hex($mI[2])/2;
      $dTemp = ($dTemp < 6 )?'off':
               ($dTemp >30 )?'on' :sprintf("%0.1f", $dTemp);
      my $err = hex($mI[3]);
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
      if($chnHash){
        my $chnName = $chnHash->{NAME};
        CUL_HM_unQEntity($chnName,'qReqStat') if ($mh{mStp} eq '01'); #noansi: special, answer to status request for a TC
        my $mode = ReadingsVal($chnName,"R-controlMode","");
        push @evtEt,[$chnHash,1,"desired-temp:$dTemp"];
        push @evtEt,[$chnHash,1,"desired-temp-manu:$dTemp"] if($mode =~ m/manual/  && $mh{mTp} eq '10');
        $chnHash->{helper}{needUpdate} = 1                  if($mode =~ m/central/ && $mh{mTp} eq '10');
       }
      push @evtEt,[$mh{shash},1,"desired-temp:$dTemp"];
      push @evtEt,[$mh{devH},1,"battery:".($err&0x80?"low":"ok")];
    }
    elsif( $mh{mTp} eq "10" &&                   # Config change report
          ($mh{p} =~ m/^0402000000000501/)) {   # paramchanged L5
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
      my $dTemp;
      if($chnHash){
        my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-controlMode","");
        $dTemp = ReadingsVal($chnName,"desired-temp","21.0");
        if (!$chnHash->{helper}{oldMode} || $chnHash->{helper}{oldMode} ne $mode){
          $dTemp = ReadingsVal($chnName,"desired-temp-manu",$dTemp)if ($mode =~ m/manual/);
          $dTemp = ReadingsVal($chnName,"desired-temp-cent",$dTemp)if ($mode =~ m/central/);
          $chnHash->{helper}{oldMode} = $mode;
        }
        push @evtEt,[$chnHash,1,"desired-temp:$dTemp"];
      }
      push @evtEt,[$mh{shash},1,"desired-temp:$dTemp"]
    }
    elsif( $mh{mTp} eq "01"){                       # status reports
      if($mh{p} =~ m/^010809(..)0A(..)/) { # TC set valve  for VD => post events to VD
        my (   $of,     $vep) = (hex($1), hex($2));
        push @evtEt,[$mh{devH},1,"ValveErrorPosition_for_$mh{dstN}: $vep"];
        push @evtEt,[$mh{devH},1,"ValveOffset_for_$mh{dstN}: $of"];
        push @evtEt,[$mh{dstH},1,"ValveErrorPosition:set_$vep"];
        push @evtEt,[$mh{dstH},1,"ValveOffset:set_$of"];
      }
      elsif($mh{p} =~ m/^010[56]/){ # 'prepare to set' or 'end set'
        push @evtEt,[$mh{shash},1,""]; #
      }
    }
    elsif( $mh{mTp} eq "3F" && $ioId eq $mh{dst}) {     # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$mh{shash},"$mh{mNo}803F$ioId$mh{src}0202$s2000";
      push @evtEt,[$mh{shash},1,"time-request"];
    }
  }
  elsif($mh{md} =~ m/^(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/) { ######################
    if($mh{mTp} eq "02" && @mI > 2) {#subtype+chn+value+err
      my ($chn,$vp, $err) = map{hex($_)} @mI[1..3];
      $chn = sprintf("%02X",$chn&0x3f);
      $vp = int($vp)/2;   # valve position in %
      push @evtEt,[$mh{shash},1,"ValvePosition:$vp"];
      push @evtEt,[$mh{shash},1,"state:$vp"];
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});

      my $stErr = ($err >>1) & 0x7;    # Status-Byte Evaluation
      push @evtEt,[$mh{devH},1,"battery:".(($stErr == 4)?"critical":($err&0x80?"low":"ok"))];
      if (!$stErr){#remove both conditions
        push @evtEt,[$mh{devH},1,"motorErr:ok"];
      }
      else{
        push @evtEt,[$mh{devH},1,"motorErr:blocked"                  ]if($stErr == 1);
        push @evtEt,[$mh{devH},1,"motorErr:loose"                    ]if($stErr == 2);
        push @evtEt,[$mh{devH},1,"motorErr:adjusting range too small"]if($stErr == 3);
#       push @evtEt,[$mh{shash},1,"battery:critical"                  ]if($stErr == 4);
      }
      push @evtEt,[$mh{devH},1,"motor:opening"] if(($err&0x30) == 0x10);
      push @evtEt,[$mh{devH},1,"motor:closing"] if(($err&0x30) == 0x20);
      push @evtEt,[$mh{devH},1,"motor:stop"   ] if(($err&0x30) == 0x00);

      #VD hang detection
      my $des = ReadingsVal($mh{devN}, "ValveDesired", $vp);
      $des =~ s/ .*//; # remove unit     
      if (($des < $vp-1 || $des > $vp+1) && ($err&0x30) == 0x00){ 
        if ($mh{shash}->{helper}{oldDes} eq $des){#desired valve position stable
          push @evtEt,[$mh{shash},1,"operState:errorTargetNotMet"];
          push @evtEt,[$mh{shash},1,"operStateErrCnt:".(ReadingsVal($mh{devN},"operStateErrCnt","0")+1)];
        }
        else{
          push @evtEt,[$mh{shash},1,"operState:changed"];
        }
      }
      else{
        push @evtEt,[$mh{shash},1,"operState:".((($err&0x30) == 0x00)?"onTarget":"adjusting")];
      }
      $mh{shash}->{helper}{oldDes} = $des;
    }
  }
  elsif($mh{md} =~ m/^HM-CC-RT-DN/) { #########################################
    my %ctlTbl=( 0=>"auto", 1=>"manual", 2=>"party",3=>"boost");

    if(($mh{mTyp} eq "100A") || #info-level/
       ($mh{mTyp} eq "0201"))  {#ackInfo
      my %errTbl=( 0=>"ok", 1=>"ValveTight",  2=>"adjustRangeTooLarge"
                  ,3=>"adjustRangeTooSmall" , 4=>"communicationERR"
                  ,5=>"unknown", 6=>"lowBat", 7=>"ValveErrorPosition" );

      my ($err       ,$ctrlMode  ,$setTemp          ,$bTime,$pTemp,$pStart,$pEnd,$chn,$uk0,$lBat,$actTemp,$vp) = 
         (hex($mI[3]),undef      ,hex($mI[1].$mI[2]),"-"    ,"-"   ,"-"    ,"-"                             );
      
      if($mh{mTp} eq "10"){
        $chn = "04";#fixed
        my $bat  =(($err            ) & 0x1f)/10+1.5;
        $actTemp = sprintf("%2.1f",((($setTemp        ) & 0x3ff)/10));
        $vp      = (hex($mI[4])     ) & 0x7f ;
        $setTemp = ($setTemp    >>10);
        $err     = ($err        >> 5);
        $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"} if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
        push @evtEt,[$mh{shash},1,"measured-temp:$actTemp" ];
        push @evtEt,[$mh{shash},1,"ValvePosition:$vp"    ];
        #device---
        push @evtEt,[$mh{devH},1,"measured-temp:$actTemp"];
        push @evtEt,[$mh{devH},1,"batteryLevel:$bat"];
        push @evtEt,[$mh{devH},1,"actuator:$vp"];
        if   ($err == 6){ $lBat = "low";} 
        elsif($err == 0){ $lBat = "ok";}# we cannot determin bat if any other state!

        #weather Chan
        my $wHash = $modules{CUL_HM}{defptr}{$mh{src}."01"}; 
        if ($wHash){
          push @evtEt,[$wHash,1,"measured-temp:$actTemp"];
          push @evtEt,[$wHash,1,"state:$actTemp"];
        }
      }
      else{
        $chn        =  $mI[1];
        $setTemp    = ($setTemp        );
        $lBat       = $err & 0x80 ? "low" : "ok"; # prior to changes of $err!
        $err        = ($err        >> 1);
        $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"} if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
        $actTemp   = ReadingsVal($mh{devN},"measured-temp","");
        $vp        = ReadingsVal($mh{devN},"actuator","");
      }
      delete $mh{devH}->{helper}{getBatState};
      $setTemp    =(($setTemp        ) & 0x3f )/2;
      $err        = ($err            ) & 0x7  ;
      
      $setTemp = ($setTemp < 5 )?'off':
                 ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      
      if (defined $mI[12]){# message with party mode
        my @pt =  map{hex($_)} @mI[5..$#mI];
        $pTemp =(($pt[7]     )& 0x3f)/2 if (defined $pt[7]) ;
        my $sta = (    ($pt[0]      )& 0x3f)/2;
        $pStart =     (($pt[2]      )& 0x7f)   # year
                 ."-".(($pt[6]  >> 4)& 0x0f)   # month
                 ."-".(($pt[1]      )& 0x1f)   # day
                 ." ".int($sta)                 # Time h
                 .":".(int($sta)!=$sta?"30":"00")# Time min
                 ;
        my $et  = (    ($pt[3]      )& 0x3f)/2;
        $pEnd   =     (($pt[5]      )& 0x7f)   # year
                 ."-".(($pt[6]      )& 0x0f)   # month
                 ."-".(($pt[4]      )& 0x1f)   # day
                 ." ".int($et)                 # Time h
                 .":".(int($et)!=$et?"30":"00")# Time min
                 ;
      }
      elsif(defined $mI[5]){
        $ctrlMode   = hex($mI[5]);
        $bTime      = (($ctrlMode       ) & 0x3f)." min" if(($ctrlMode &0xc0) == 0xc0);#message with boost
#        $uk0        = ($ctrlMode       ) & 0x3f ;#unknown
        $ctrlMode   =  ($ctrlMode   >> 6) & 0x3  ;
      }

      my $climaHash = CUL_HM_id2Hash($mh{src}."04");# always to Clima channel
      push @evtEt,[$climaHash,1,"desired-temp:$setTemp"  ];
      push @evtEt,[$climaHash,1,"controlMode:$ctlTbl{$ctrlMode}"] if(defined $ctrlMode);
      push @evtEt,[$climaHash,1,"state:T: $actTemp desired: $setTemp valve: $vp"];
      push @evtEt,[$climaHash,1,"boostTime:$bTime"];
      push @evtEt,[$climaHash,1,"partyStart:$pStart"];
      push @evtEt,[$climaHash,1,"partyEnd:$pEnd"];
      push @evtEt,[$climaHash,1,"partyTemp:$pTemp"];
      #push @evtEt,[$mh{shash},1,"unknown0:$uk0"];
      #push @evtEt,[$mh{shash},1,"unknown1:".$2 if ($p =~ m/^0A(.10)(.*)/)];
      push @evtEt,[$mh{devH},1,"motorErr:$errTbl{$err}" ] if($mh{mTp} eq "10");
      push @evtEt,[$mh{devH},1,"battery:$lBat"] if ($lBat);
      push @evtEt,[$mh{devH},1,"desired-temp:$setTemp"];
    }
    elsif($mh{mTp} eq "59" && defined $mI[0]) {#inform team about new value
      my $setTemp = sprintf("%.1f",int(hex($mI[0])/4)/2);
      my $ctrlMode = hex($mI[0])&0x3;
      push @evtEt,[$mh{shash},1,"desired-temp:$setTemp"];
      push @evtEt,[$mh{shash},1,"controlMode:$ctlTbl{$ctrlMode}"];

      my $tHash = $modules{CUL_HM}{defptr}{$mh{dst}."04"};
      if ($tHash){
        push @evtEt,[$tHash,1,"desired-temp:$setTemp"];
        push @evtEt,[$tHash,1,"controlMode:$ctlTbl{$ctrlMode}"];
      }
    }
    elsif($mh{mTp} eq "3F" && $ioId eq $mh{dst}) { # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$mh{shash},"$mh{mNo}803F$ioId$mh{src}0202$s2000";
      push @evtEt,[$mh{shash},1,"time-request"];
      # schedule desired-temp just to get an AckInfo for battery
      $mh{shash}->{helper}{getBatState} = 1;
    }
  }
  elsif($mh{md} eq "HM-TC-IT-WM-W-EU") { ######################################
    my %ctlTbl=( 0=>"auto", 1=>"manual", 2=>"party",3=>"boost");
    if( ( $mh{mTp} eq "10" && $mI[0] eq '0B')  #info-level
      ||( $mh{mTp} eq "02" && $mI[0] eq '01')) {#ack-status
      my @d = map{hex($_)} unpack 'A2A4(A2)*',$mh{p};
      my ($setTemp,$actTemp, $cRep,$wRep,$bat ,$lbat,$ctrlMode,$bTime,$pTemp,$pStart,$pEnd) =
          ($d[1],$d[1],      $d[2],$d[2],$d[2],$d[2],""       ,"-"   ,"-"   ,"-"    ,"-");

      CUL_HM_m_setCh(\%mh,"02");
      $lbat       = ($lbat           ) & 0x80;

      if ($mh{mTp} eq "10"){
        $ctrlMode   = $d[3];
        $bat        =(($bat            ) & 0x1f)/10+1.5;
        $setTemp    =(($setTemp    >>10) & 0x3f )/2;
        $actTemp    =(($actTemp        ) & 0x3ff)/10;
        $actTemp    = -1 * $actTemp if ($d[1] & 0x200 );# obey signed
        $actTemp = sprintf("%2.1f",$actTemp);
        push @evtEt,[$mh{cHash},1,"measured-temp:$actTemp"];
        push @evtEt,[$mh{devH},1,"measured-temp:$actTemp"];
        push @evtEt,[$mh{devH},1,"batteryLevel:$bat"];
        $cRep = (($cRep    >>6) & 0x01 )?"on":"off";
        $wRep = (($wRep    >>5) & 0x01 )?"on":"off";        
      }
      else{#actTemp is not provided in ack message - use old value
        $ctrlMode   = $d[4];
        $actTemp = ReadingsVal($mh{devN},"measured-temp",0);
        $setTemp  =(hex($mI[2]) & 0x3f )/2;
        $cRep = (($cRep    >>2) & 0x01 )?"on":"off";
        $wRep = (($wRep    >>1) & 0x01 )?"on":"off";        
      }
      $ctrlMode = ($ctrlMode   >> 6) & 0x3  ;
      $setTemp  = ($setTemp < 5 )?'off':
                  ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      
      if (defined $d[11]){# message with party mode
        $pTemp =(($d[11]     )& 0x3f)/2 if (defined $d[11]) ;
        my @p;
        if ($mh{mTp} eq "10") {@p = @d[3..9]}
        else              {@p = @d[4..10]}
        my $sta = (($p[0]      )& 0x3f)/2;
        $pStart =     (($p[2]      )& 0x7f)    # year
                 ."-".(($p[6]  >> 4)& 0x0f)    # month
                 ."-".(($p[1]      )& 0x1f)    # day
                 ." ".int($sta)                 # Time h
                 .":".(int($sta)!=$sta?"30":"00")# Time min
                 ;
        my $et = (($p[3]      )& 0x3f)/2;
        $pEnd   =     (($p[5]      )& 0x7f)    # year
                 ."-".(($p[6]      )& 0x0f)    # month
                 ."-".(($p[4]      )& 0x1f)    # day
                 ." ".int($et)                 # Time h
                 .":".(int($et)!=$et?"30":"00")# Time min
                 ;
        push @evtEt,[$mh{cHash},1,"partyStart:$pStart"];
        push @evtEt,[$mh{cHash},1,"partyEnd:$pEnd"];
        push @evtEt,[$mh{cHash},1,"partyTemp:$pTemp"];
      }
      elsif(defined $d[3] && $ctrlMode == 3 ){#message with boost
        $bTime     = (($d[3]       ) & 0x3f)." min";
      }

      push @evtEt,[$mh{cHash},1,"desired-temp:$setTemp"];
      push @evtEt,[$mh{cHash},1,"controlMode:$ctlTbl{$ctrlMode}"];
      push @evtEt,[$mh{cHash},1,"state:T: $actTemp desired: $setTemp"];
      push @evtEt,[$mh{cHash},1,"commReporting:$cRep"];
      push @evtEt,[$mh{cHash},1,"winOpenReporting:$wRep"];
      push @evtEt,[$mh{cHash},1,"boostTime:$bTime"];
      push @evtEt,[$mh{devH},1,"battery:".($lbat?"low":"ok")];
      push @evtEt,[$mh{devH},1,"desired-temp:$setTemp"];
    }
    elsif($mh{mTp} eq "70"){
      my $chn = "01";
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
      my ($t,$h) =  map{hex($_)} unpack 'A4A2',$mh{p};
      $t &= 0x7fff;                 
      $t -= 0x8000 if($t & 0x4000); 
      $t = sprintf("%0.1f", $t/10);
      push @evtEt,[$mh{shash},1,"temperature:$t"];
      push @evtEt,[$mh{shash},1,"humidity:$h"];
      push @evtEt,[$mh{shash},1,"state:T: $t H: $h"];
    }
    elsif($mh{mTp} eq "5A"){# thermal control - might work with broadcast
      my $chn = "02";
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
      my ($t,$h) =  map{hex($_)} unpack 'A4A2',$mh{p};
      my $setTemp    =(($t    >>10) & 0x3f )/2;
      my $actTemp    =(($t        ) & 0x3ff)/10;
      $actTemp = sprintf("%2.1f",$actTemp);
      $setTemp = ($setTemp < 5 )?'off':
                 ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      push @evtEt,[$mh{shash},1,"measured-temp:$actTemp"];
      push @evtEt,[$mh{shash},1,"desired-temp:$setTemp"];
      push @evtEt,[$mh{shash},1,"humidity:$h"];
      push @evtEt,[$mh{shash},1,"state:T: $actTemp desired: $setTemp"];
    }
    elsif($mh{mTp} =~ m/^4./) {
      my ($chn,$lvl) = ($mI[0],hex($mI[2])/2);
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
      if ($chnHash){
        push @evtEt,[$chnHash,1,"level:$lvl"];
      }
    }
    elsif($mh{mTp} eq "3F" && $ioId eq $mh{dst}) { # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$mh{shash},"$mh{mNo}803F$ioId$mh{src}0202$s2000";
      push @evtEt,[$mh{shash},1,"time-request"];
    }
  }
  elsif($mh{md} =~ m/^(HM-SEN-WA-OD|HM-CC-SCD)$/){ ############################
    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006") ||  #or Info_Status message here
        ($mh{mTp} eq "41"))                {
      my $lvl = $mI[2];
      my $err = ($mh{mTp} eq "41") ? hex($mI[0]) : ($mI[3] ? hex($mI[3]) : "");
      if    ($lvlStr{md}{$mh{md}}){$lvl = $lvlStr{md}{$mh{md}}{$lvl}}
      elsif ($lvlStr{st}{$mh{st}}){$lvl = $lvlStr{st}{$mh{st}}{$lvl} }
      else                    {$lvl = hex($lvl)/2}

      push @evtEt,[$mh{shash},1,"level:$lvl"] if($mh{md} eq "HM-SEN-WA-OD");
      push @evtEt,[$mh{shash},1,"state:$lvl"];
      push @evtEt,[$mh{devH} ,1,"battery:".($err&0x80?"low":"ok")] if ($err ne "");
    }
  }
  elsif($mh{md} eq "KFM-SENSOR") { ############################################
    if ($mh{mTp} eq "53"){
      if($mh{p} =~ m/^(..)4(.)0200(..)(..)(..)/) {
        my ($chn,$seq, $k_v1, $k_v2, $k_v3) = (hex($1),hex($2),$3,hex($4),hex($5));
        push @evtEt,[$mh{devH},1,"battery:".($chn & 0x80?"low":"ok")];
        my $v = 1408 - ((($k_v3 & 0x07)<<8) + $k_v2);
        push @evtEt,[$mh{shash},1,"rawValue:$v"];
        my $nextSeq = ReadingsVal($mh{devN},"Sequence","");
        $nextSeq =~ s/_.*//;
        $nextSeq = ($nextSeq %15)+1;      
        push @evtEt,[$mh{shash},1,"Sequence:$seq".($nextSeq ne $seq?"_seqMiss":"")];

        my $r2r = AttrVal($mh{devN}, "rawToReadable", undef);
        if($r2r) {
          my @r2r = split("[ :]", $r2r);
          foreach(my $idx = 0; $idx < @r2r-2; $idx+=2) {
            if($v >= $r2r[$idx] && $v <= $r2r[$idx+2]) {
              my $f = (($v-$r2r[$idx])/($r2r[$idx+2]-$r2r[$idx]));
              my $cv = ($r2r[$idx+3]-$r2r[$idx+1])*$f + $r2r[$idx+1];
              my $unit = AttrVal($mh{devN}, "unit", "");
              push @evtEt,[$mh{shash},1,sprintf("state:%.1f %s",$cv,$unit)];
              push @evtEt,[$mh{shash},1,sprintf("content:%.1f %s",$cv,$unit)];
              last;
            }
          }
        } 
        else {
          push @evtEt,[$mh{shash},1,"state:$v"];
        }
      }
    }
  }
  elsif($mh{st} eq "THSensor") { ##############################################
    if    ($mh{mTp} eq "70"){
      my $chn;
      my ($d1,$h,$ap) = map{hex($_)} unpack 'A4A2A4',$mh{p};
      if    ($mh{md} =~ m/^(WS550|WS888|HM-WDC7000)/){$chn = "10"}
      elsif ($mh{md} =~ m/^HM-WDS30-OT2-SM/)         {$chn = "05";$h=""}
      elsif ($mh{md} =~ m/^(S550IA|HM-WDS30-T-O)/)   {$chn = "01";$h=""}
      else                                           {$chn = "01"}

      my $t =  $d1 & 0x7fff;
      $t -= 0x8000 if($t &0x4000);
      $t = sprintf("%0.1f", $t/10);
      my $statemsg = "state:T: $t";
      push @evtEt,[$mh{shash},1,"temperature:$t"];#temp is always there
      push @evtEt,[$mh{devH},1,"battery:".($d1 & 0x8000?"low":"ok")];
      if($modules{CUL_HM}{defptr}{$mh{src}.$chn}){
        my $ch = $modules{CUL_HM}{defptr}{$mh{src}.$chn};
        push @evtEt,[$ch,1,$statemsg];
        push @evtEt,[$ch,1,"temperature:$t"];
      }
      if ($h) {$statemsg .= " H: $h"  ; push @evtEt,[$mh{shash},1,"humidity:$h"]; }
      if ($ap){$statemsg .= " AP: $ap"; push @evtEt,[$mh{shash},1,"airpress:$ap"];}
      push @evtEt,[$mh{shash},1,$statemsg];
    }
    elsif ($mh{mTp} eq "53"){
      my ($chn,@dat) = unpack 'A2(A6)*',$mh{p};
      push @evtEt,[$mh{devH},1,"battery:".(hex($chn)&0x80?"low":"ok")];
      foreach (@dat){
        my ($a,$d) = unpack 'A2A4',$_;
        $d = hex($d);
        $d -= 0x10000 if($d & 0xC000);
        $d = sprintf("%0.1f",$d/10);
        my $chId = sprintf("%02X",hex($a) & 0x3f);
        my $chnHash = $modules{CUL_HM}{defptr}{$mh{src}.$chId};
        if ($chnHash){
          push @evtEt,[$chnHash,1,"state:T: $d"];
          push @evtEt,[$chnHash,1,"temperature:$d"];
        }
        else{
          push @evtEt,[$mh{shash},1,"Chan_$chId:T: $d"];
        }
      }
    }
  }
  elsif($mh{st} eq "sensRain") {###############################################
    my $hHash = CUL_HM_id2Hash($mh{src}."02");# hash for heating
    my $pon = 0;# power on if mNo == 0 and heating status plus second msg
                # status or trigger from rain channel
    if (($mh{mTyp} eq "0201") || #Ack_Status
        ($mh{mTyp} eq "1006")) { #Info_Status

      my ($subType,$chn,$val,$err) = ($mI[0],hex($mI[1]),$mI[2],hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $mh{src}.$chn;
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});

      my ($timedOn,$stateExt)=("off","");
      if($err&0x40 && $chn eq "02"){
        $timedOn = "running";
        $stateExt = "-till" if(AttrVal($mh{cName},"param","") =~ m/showTimed/ );
      }     
      push @evtEt,[$mh{cHash},1,"timedOn:$timedOn"];

      my $mdCh = $mh{md}.$chn;
      if($lvlStr{mdCh}{$mdCh} && $lvlStr{mdCh}{$mdCh}{$val}){
        $val = $lvlStr{mdCh}{$mdCh}{$val};
      }
      else{
        $val = hex($val)/2;
      }
      push @evtEt,[$mh{shash},1,"state:$val$stateExt"];

      if ($val eq "rain"){#--- handle lastRain---
        $mh{shash}->{helper}{lastRain} = $mh{tmStr};
      }
      elsif ($val eq "dry" && $mh{shash}->{helper}{lastRain}){
        push @evtEt,[$mh{shash},1,"lastRain:$mh{shash}->{helper}{lastRain}"];
        delete $mh{shash}->{helper}{lastRain};
      }

      push @evtEt,[$mh{shash},0,'.level:'.($val eq "off"?"0":"100")];

      if    ($mh{mNo} eq "00" && $chn eq "02" && $val eq "on"){
        $hHash->{helper}{pOn} = 1;
      }
      elsif ($mh{mNo} eq "01" && $chn eq "01" &&
             $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
        $pon = 1;
      }
      else{
        delete $hHash->{helper}{pOn};
        my $hHash = CUL_HM_id2Hash($mh{src}."02");# hash for heating
        if ($chn eq "01" &&
            $hHash->{helper}{param} && $hHash->{helper}{param}{onAtRain}){
          CUL_HM_Set($hHash,$hHash->{NAME},$val eq "rain"?"on":"off");
        }
      }
    }
    elsif ($mh{mTp} eq "41")   { #eventonAtRain
      my ($chn,$bno,$val) = @mI;
      $chn = sprintf("%02X",hex($chn)&0x3f);
      $mh{shash} = $modules{CUL_HM}{defptr}{$mh{src}.$chn}
                             if($modules{CUL_HM}{defptr}{$mh{src}.$chn});
      push @evtEt,[$mh{shash},1,"trigger:".hex($bno).":".$lvlStr{mdCh}{$mh{md}.$chn}{$val}.$target];
      if ($mh{mNo} eq "01" && $bno eq "01" &&
          $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
        $pon = 1;
      }
      delete $mh{shash}->{helper}{pOn};
    }
    if ($pon){# we have power ON, perform action
      if($mh{devH}->{helper}{PONtest}){
        push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",];
        $mh{devH}->{helper}{PONtest} = 0;
      }
      CUL_HM_Set($hHash,$hHash->{NAME},"off")
                 if ($hHash && $hHash->{helper}{param}{offAtPon});
    }
  }
  elsif($mh{st} =~ m/^(switch|dimmer|blindActuator|rgb)$/) {###################

    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006")) { #    or Info_Status message here
      my $rSUpdt = 0;# require status update
      my ($val,$err) = (hex($mI[2]),hex($mI[3]));
      $val /= 2 if ($mh{st} ne "rgb" || $mh{chn} != 3);
      CUL_HM_m_setCh(\%mh,$mI[1]);
      my($lvlMin,$lvlMax)=split",",AttrVal($mh{cName}, "levelRange", "0,100");
      my $physLvl;                             #store phys level if available
      if(   defined $mI[5]                     #message with physical level?
         && $mh{st} eq "dimmer"){
        my $pl = hex($mI[5])/2;
        my $vDim = $mh{cHash}->{helper}{vDim}; #shortcut
        if ($vDim->{idPhy} &&
            CUL_HM_id2Hash($vDim->{idPhy})){   #has virt chan
          RemoveInternalTimer("sUpdt:".CUL_HM_id2Name($mh{src}.$mh{chnM}));
          if ($mh{mTp} eq "10"){               #valid PhysLevel
            foreach my $tmpKey ("idPhy","idV2","idV3",){#update all virtuals
              my $vh = ($vDim->{$tmpKey} ? CUL_HM_id2Hash($vDim->{$tmpKey}) : "");
              next if (!$vh || $vDim->{$tmpKey} eq $mh{src}.$mh{chnM});
              my $vl = ReadingsVal($vh->{NAME},"level","???");
              my $vs = ($vl eq "100"?"on":($vl eq "0"?"off":"$vl"));
              my($clvlMin,$clvlMax)=split",",AttrVal($vh->{NAME}, "levelRange", "0,100");
              my $plc = int((($pl-$clvlMin)*200)/($clvlMax - $clvlMin))/2;
              $plc = 1 if ($pl && $plc <= 0);
              $vs = ($plc ne $vl)?"chn:$vs  phys:$plc":$vs;
              push @evtEt,[$vh,1,"state:$vs"];
              push @evtEt,[$vh,1,"phyLevel:$pl"];
            }
            push @evtEt,[$mh{cHash},1,"phyLevel:$pl"];      #phys level,don't use relative adjustment
            $pl = (($pl-$lvlMin)<=0 && $pl)
                     ? ($pl?1:0)
                     : int((($pl-$lvlMin)*200)/($lvlMax - $lvlMin))/2;
            $physLvl = $pl;
          }
          else{                                #invalid PhysLevel
            $rSUpdt = 1;
            CUL_HM_stateUpdatDly($mh{cName},5) if ($mh{cHash}->{helper}{dlvl});# update to get level
          }
        }
      }
      my $pVal = $val;# necessary for oper 'off', not logical off
      $val = (($val-$lvlMin)<=0)
                  ? ($val?1:0)
                  : int((($val-$lvlMin)*200)/($lvlMax - $lvlMin))/2;

      # blind option: reverse Level Meaning 0 = open, 100 = closed
      if (AttrVal($mh{cName}, "param", "") =~ m/levelInverse/){;
        $pVal = $val = 100-$val;
      }
      if(!defined $physLvl){             #not updated? use old or ignore
        $physLvl = ReadingsVal($mh{cName},"phyLevel",$val);
        $physLvl = (($physLvl-$lvlMin)<=0 && $physLvl)
                 ? ($physLvl?1:0)
                 : int((($physLvl-$lvlMin)*200)/($lvlMax - $lvlMin))/2;
      }

      my $vs = ($mh{cHash}->{helper}{lm} && $mh{cHash}->{helper}{lm}{$val})
                     ?$mh{cHash}->{helper}{lm}{$val}
                     :($val==100 ? "on"
                                 :($pVal==0 ? "off"
                                            : "$val")); # user string...
      
      #--    if timed on is set possibly show this in a state --
      my ($timedOn,$stateExt)=("off","");
      if($err&0x40){
        $timedOn = "running";
        $stateExt = "-till" if(AttrVal($mh{cName},"param","") =~ m/showTimed/ );
      }
      my $state = (($physLvl ne $val)?"chn:$vs phys:$physLvl":$vs.$stateExt);

      push @evtEt,[$mh{cHash},1,"level:$val"];
      push @evtEt,[$mh{cHash},1,"pct:$val"]; # duplicate to level - necessary for "slider"
      push @evtEt,[$mh{cHash},1,"deviceMsg:$vs$target"] if($mh{chnM} ne "00");
      push @evtEt,[$mh{cHash},1,"state:".$state];      
      push @evtEt,[$mh{cHash},1,"timedOn:$timedOn"];

      if ($mh{cHash}->{helper}{dlvl} && defined $err){#are we waiting?
        if ($mI[2] ne $mh{cHash}->{helper}{dlvl} #level not met?
            && !($err&0x70)){                    #and already stopped not timedOn
          #level not met, repeat
          Log3 $mh{cName},5,"CUL_HM $mh{cName} repeat, level $mI[2] instead of $mh{cHash}->{helper}{dlvl}";
          if ($mh{cHash}->{helper}{dlvlCmd}){# first try
            CUL_HM_PushCmdStack($mh{cHash},$mh{cHash}->{helper}{dlvlCmd});
            CUL_HM_ProcessCmdStack($mh{cHash});
            delete $mh{cHash}->{helper}{dlvlCmd};# will prevent second try
          }
          else{# no second try - alarm and stop
            push @evtEt,[$mh{cHash},1,"levelMissed:desired:".hex($mh{cHash}->{helper}{dlvl})/2];
            delete $mh{cHash}->{helper}{dlvl};# we only make one attempt
          }
        }
        else{# either level met, timed on or we are driving...
          delete $mh{cHash}->{helper}{dlvl};
        }
      }
      if ($mh{st} ne "switch"){
        my $eventName = "unknown"; # different names for events
        if   ($mh{st} eq "blindActuator")   {$eventName = "motor" ;}  
        elsif($mh{st} =~ m/^(dimmer|rgb)$/) {$eventName = "dim"   ;}
        my $dir = ($err >> 4) & 3;
        my %dirName = ( 0=>"stop" ,1=>"up" ,2=>"down" ,3=>"err" );
        my $dirNm = $dirName{$dir};
        push @evtEt,[$mh{cHash},1,"$eventName:$dirNm:$vs"  ];
        $mh{cHash}->{helper}{dir}{rct} = $mh{cHash}->{helper}{dir}{cur} 
                  if($mh{cHash}->{helper}{dir}{cur} &&
                     $mh{cHash}->{helper}{dir}{cur} ne $dirNm);
        $mh{cHash}->{helper}{dir}{cur} = $dirNm;
      }
      if (!$rSUpdt){#dont touch if necessary for dimmer
        if(($err & 0x70) == 0x10 || ($err & 0x70) == 0x20){
          my $wt = $mh{cHash}->{helper}{stateUpdatDly}
                         ?$mh{cHash}->{helper}{stateUpdatDly}
                         :120;
          CUL_HM_stateUpdatDly($mh{cName},$wt);
        }
        else {
          CUL_HM_unQEntity($mh{cName},"qReqStat");
        }
        delete $mh{cHash}->{helper}{stateUpdatDly};
      }
 
      if    ($mh{st} eq "dimmer"){
        if (lc($mh{md}) =~ m/^hm-lc-dim.l.*/){
          push @evtEt,[$mh{cHash},1,"loadFail:".(($err == 6)?"on":"off")];#note: err is times 2!
        }
        else{
          push @evtEt,[$mh{cHash},1,"overload:".(($err&0x02)?"on":"off")];
          push @evtEt,[$mh{cHash},1,"overheat:".(($err&0x04)?"on":"off")];
          push @evtEt,[$mh{cHash},1,"reduced:" .(($err&0x08)?"on":"off")];
        }
         #hack for blind  - other then behaved devices blind does not send
         #        a status info for chan 0 at power on
         #        chn3 (virtual chan) and not used up to now
         #        info from it is likely a power on!
        if($mh{devH}->{helper}{PONtest} && $mh{chn} == 3){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}"] ;
          $mh{devH}->{helper}{PONtest} = 0;
        }
      }
      elsif ($mh{st} eq "rgb"){
        if ($mh{chn} == 2){
          push @evtEt,[$mh{cHash},1,"color:$val"]; # duplicate to color - necessary for "colorpicker"
          push @evtEt,[$mh{cHash},1,"rgb:".(($val==100)?("FFFFFF"):(Color::hsv2hex($val/100,1,1)))];
          delete $mh{cHash}->{helper}{dlvl};
        }
        elsif($mh{chn} == 1){
          my $ch2Name = InternalVal($mh{devH}->{NAME},"channel_02","");
          if ($ch2Name && defined $defs{$ch2Name}  && defined $defs{$ch2Name}{helper}{dlvl}){
            CUL_HM_stateUpdatDly($ch2Name,2);
            delete $mh{$ch2Name}{helper}{dlvl};
          }
        }
        push @evtEt,[$mh{cHash},1,"colProgram:$val"] if ($mh{chn} == 3); # duplicate to colProgram - necessary for "slider"
      }
      elsif ($mh{st} eq "blindActuator"){
        my $param = AttrVal($mh{cName}, "param", "");
        if ($param =~ m/ponRestoreSmart/){
          if($parse eq "powerOn"){
            my $level = ReadingsVal($mh{cName},"level",0);# still the old level
            $mh{cHash}->{helper}{prePONlvl} = $level;
            $level = ($level<50)?0:100;
            CUL_HM_Set($mh{cHash},$mh{cName},"pct",$level);
          }
          elsif (   $mh{cHash}->{helper}{dir}{cur} eq "stop"
                 && defined $mh{cHash}->{helper}{prePONlvl} ){
            if ($val != 0 && $val != 100){
              CUL_HM_Set($mh{cHash},$mh{cName},"pct",$mh{cHash}->{helper}{prePONlvl});
            }
            delete $mh{cHash}->{helper}{prePONlvl};
          }
        }
        elsif ($param =~ m/ponRestoreForce/){
          if($parse eq "powerOn"){
            my $level = ReadingsVal($mh{cName},"level",0);# still the old level
            $mh{cHash}->{helper}{prePONlvl} = $level;
            CUL_HM_Set($mh{cHash},$mh{cName},"pct","0");
          }
          elsif (   $mh{cHash}->{helper}{dir}{cur} eq "stop"
                 && defined $mh{cHash}->{helper}{prePONlvl}){
            if ($val == 0){
              CUL_HM_Set($mh{cHash},$mh{cName},"pct",100);
            }
            elsif($val == 100){
              CUL_HM_Set($mh{cHash},$mh{cName},"pct",$mh{cHash}->{helper}{prePONlvl});
              delete $mh{cHash}->{helper}{prePONlvl};
            }
            else{
              delete $mh{cHash}->{helper}{prePONlvl};# some stop inbetween - maybe user action. stop processing
            }
          }
        }

        if ($mh{md} eq "HM-LC-JA1PBU-FM" && defined $mI[6]){
          my %dirName = ( 0=>"stop" ,1=>"up" ,2=>"down" ,3=>"err" );
          push @evtEt,[$mh{cHash},1,"pctSlat:".hex($mI[5])/2];
          push @evtEt,[$mh{cHash},1,"slatDir:".$dirName{hex($mI[6]) & 0x3}];          
        }
      }
      elsif ($mh{md} eq "HM-SEC-SFA-SM"){ 
        push @evtEt,[$mh{devH},1,"powerError:"   .(($err&0x02) ? "on":"off")];
        push @evtEt,[$mh{devH},1,"sabotageError:".(($err&0x04) ? "on":"off")];
        push @evtEt,[$mh{devH},1,"battery:".(($err&0x08)?"critical":($err&0x80?"low":"ok"))];
      }
      elsif ($mh{md} =~ m/^HM-(?:LC-SW.-BA-PCB|DIS-TD-T|MOD-RE-8)/s){
        push @evtEt,[$mh{devH},1,"battery:" . (($err&0x80) ? "low" : "ok" )];
      }
    }
  }
  elsif($mh{st} =~ m/^(remote|pushButton|swi|display)$/
      ||$mh{md} eq "HM-SEN-EP") { #############################################
    if($mh{mTp} eq "40") { 
      my $bat   = ($mh{chnraw} & 0x80)?"low":"ok";
      my $type  = ($mh{chnraw} & 0x40)?"l":"s";
      my $state = ($mh{chnraw} & 0x40)?"Long":"Short";     
      my $chId = $mh{src}.$mh{chnHx};

      my $btnName = $mh{cHash}->{helper}{role}{chn} 
                         ? $mh{cName}
                         : "Btn$mh{chn}";

      if($type eq "l"){# long press
        #$state .= ($mh{mFlgH} & 0x20 ? "Release" : "");# not sufficient
        $state .= ((($mh{mFlgH} & 0x24) == 0x20) ? "Release" : "");
      }

      push @evtEt,[$mh{devH},1,"battery:$bat"];
      push @evtEt,[$mh{devH},1,"state:$btnName $state"];
      if($mh{md} eq "HM-DIS-WM55"){
        if ($mh{devH}->{cmdStack}){# there are pending commands. we only send new ones
          delete $mh{devH}->{cmdStack};
          delete $mh{devH}->{cmdStacAESPend};
          delete $mh{devH}->{helper}{prt}{rspWait};
          #delete $mh{devH}->{helper}{prt}{rspWaitSec};
          delete $mh{devH}->{helper}{prt}{mmcA};
          delete $mh{devH}->{helper}{prt}{mmcS};
          delete $mh{devH}->{lastMsg};
        }

        CUL_HM_calcDisWm($mh{cHash},$mh{devN},$type);
        if (AttrVal($btnName,"aesCommReq",0)){
          my @arr = ();
          $mh{devH}->{cmdStacAESPend} = \@arr;
          push (@{$mh{devH}->{cmdStacAESPend} },"$mh{src};++A011$mh{id}$mh{src}$_")
                foreach (@{$mh{cHash}->{helper}{disp}{$type}});
       }
        else{
          CUL_HM_PushCmdStack($mh{devH},"++A011$mh{id}$mh{src}$_")
                foreach (@{$mh{cHash}->{helper}{disp}{$type}});
        }
      }
    }
    if($mh{md} eq "HM-DIS-EP-WM55"){
      my $disName = InternalVal($mh{devN},"channel_03",undef);
      if (defined $disName ){
        if (AttrVal($disName,"param","") =~ m/reWriteDisplay(..)/){
          my $delay = $1;
          RemoveInternalTimer($disName.":reWriteDisplay");
          InternalTimer($mh{rectm}+$delay,"CUL_HM_reWriteDisplay", $disName.":reWriteDisplay", 0);
        }
      }
    }
    else{# could be an Em8
      my($chn,$state,$err);
      if($mh{mTp} eq "41"){
        ($chn,$state)=(hex($mI[0]),$mI[2]);
        #my $cnt = hex($mI[1]);
        my $err = $chn & 0x80;
        $chn = sprintf("%02X",$chn & 0x3f);
        $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                               if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
        push @evtEt,[$mh{devH},1,"battery:". ($err?"low"  :"ok"  )];
      }
      elsif(($mh{mTp} eq "10" && $mI[0] eq "06") ||
            ($mh{mTp} eq "02" && $mI[0] eq "01")) {
        ($chn,$state,$err) = (hex($mI[1]), $mI[2], hex($mI[3]));
        $chn = sprintf("%02X",$chn&0x3f);
        $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                               if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
        push @evtEt,[$mh{devH},1,"alive:yes"];
        push @evtEt,[$mh{devH},1,"battery:". (($err&0x80)?"low"  :"ok"  )];
      }
      
      if (defined($state) && $chn ne "00"){# if state was detected post events
        my $txt;
        if    ($mh{shash}->{helper}{lm} && $mh{shash}->{helper}{lm}{hex($state)}){$txt = $mh{shash}->{helper}{lm}{hex($state)}}
        elsif ($lvlStr{md}{$mh{md}}){$txt = $lvlStr{md}{$mh{md}}{$state}}
        elsif ($lvlStr{st}{$mh{st}}){$txt = $lvlStr{st}{$mh{st}}{$state}}
        else                    {$txt = "unknown:$state"}
      
        push @evtEt,[$mh{shash},1,"state:$txt"];
        push @evtEt,[$mh{shash},1,"contact:$txt$target"];
      }
    }
  }

  elsif($mh{st} =~ m/^(siren)$/) {#############################################
    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006")) {  #   or Info_Status message here
        

      my ($chn,$val,$err) = (hex($mI[1]),hex($mI[2])/2,hex($mI[3]));
      my $vs = $val == 0 ? "off" : "on";
      
      #--    if timed on is set possibly show this in a state --
      my ($timedOn,$stateExt)=("off","");
      if($err&0x40){
        $timedOn = "running";
        $stateExt = "-till" if(AttrVal($mh{cName},"param","") =~ m/showTimed/ );
      }
      if ($chn == 4){
        my %lvlSet = ("00"=>"disarmed","32"=>"armExtSens","C8"=>"armAll","FF"=>"armBlocked");
        $vs = defined $lvlSet{$val}?$lvlSet{$val}:$val;
      }
      push @evtEt,[$mh{cHash},1,"level:$val"];
      push @evtEt,[$mh{cHash},1,"pct:$val"]; # duplicate to level - necessary for "slider"
      push @evtEt,[$mh{cHash},1,"deviceMsg:$vs$target"] if($mh{chnM} ne "00");
      push @evtEt,[$mh{cHash},1,"state:$vs$stateExt"];
      push @evtEt,[$mh{cHash},1,"timedOn:$timedOn"];
      push @evtEt,[$mh{devH} ,1,"powerOn:$mh{tmStr}",]  if ($chn == 0) ;
      push @evtEt,[$mh{devH} ,1,"sabotageError:".(($err&0x04)?"on" :"off")];
      push @evtEt,[$mh{devH} ,1,"battery:"      .(($err&0x80)?"low":"ok" )];
    }
  }
  elsif($mh{st} eq "senBright") { #############################################
    if ($mh{mTp} =~ m/^5[34]/){
      #Channel is fixed 1
      my ($chn,$unkn,$dat) = unpack 'A2A2A8',$mh{p};# chn = 01
      push @evtEt,[$mh{devH},1,"battery:".(hex($chn)&0x80?"low":"ok")];
      
      $dat = sprintf("%0.2f",hex($dat))/100; #down to 0.01lux per docu

      # verify whether we have a channel or will use the Device instead
      my $cHash = ($modules{CUL_HM}{defptr}{$mh{src}."01"})
                     ?$modules{CUL_HM}{defptr}{$mh{src}."01"}
                     :$mh{devH};
      push @evtEt,[$cHash,1,"state:B: $dat"];
      push @evtEt,[$cHash,1,"brightness:$dat"];
      #push @evtEt,[$cHash,1,"unknown: 0x".$unkn]; # read 0xC1, but what is it?
    }
  }
  elsif($mh{st} eq "powerSensor") {############################################
    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006")) {  #    or Info_Status message here

      my ($chn,$val,$err) = (hex($mI[1]),hex($mI[2])/2,hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $mh{src}.$chn;
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
                             
      push @evtEt,[$mh{devH},1,"battery:".(($err&0x80)?"low"  :"ok"  )];

      push @evtEt,[$mh{shash},1,"state:$val"];
    }
    elsif ($mh{mTp} eq "60" ||$mh{mTp} eq "61" ) {  #    IEC_POWER_EVENT_CYCLIC
      my ($chn,$eUnit,$eCnt,$pUnit,$pIEC) = map{hex($_)} unpack 'A2A2A10A2A8',$mh{p};

      push @evtEt,[$mh{devH},1,"battery:".(($chn&0x80)?"low"  :"ok"  )];
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $mh{src}.$chn;
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      
#      push @evtEt,[$mh{shash},1,"energyTariff:" .(( $eUnit       & 0xfe)?(-1*($eUnit >> 4)):($eUnit >> 4))];
#      push @evtEt,[$mh{shash},1,"powerTariff:"  .((($pUnit >> 4) & 0xfe)?(-1*($pUnit >> 4)):($pUnit >> 4))];
      push @evtEt,[$mh{shash},1,"energyTariff:" .(  $eUnit >> 4        )];
      push @evtEt,[$mh{shash},1,"energyUnit:"   .(  $eUnit       & 0x01)];
      push @evtEt,[$mh{shash},1,"powerTariff:"  .(  $pUnit >> 4        )];
      push @evtEt,[$mh{shash},1,"powerUnit:"    .(  $pUnit       & 0x01)];
      push @evtEt,[$mh{shash},1,"powerSign:"    .(( $pUnit >> 3) & 0x01)];
      push @evtEt,[$mh{shash},1,"powerIEC:"     .(  $pIEC              )];
      push @evtEt,[$mh{shash},1,"energyIEC:"    .(  $eCnt              )];
      
    }
    elsif ($mh{mTp} eq "53" ||$mh{mTp} eq "54" ) {  #    Gas_EVENT_CYCLIC
      $mh{shash} = $modules{CUL_HM}{defptr}{$mh{src}."01"}
                             if($modules{CUL_HM}{defptr}{$mh{src}."01"});
      my ($eCnt,$P) = map{hex($_)} unpack 'A8A6',$mh{p};
      $eCnt = ($eCnt&0x7fffffff)/1000;       #0.0  ..2147483.647 m3
      $P = $P   /1000;                       #0.0  ..16777.215 m3
      push @evtEt,[$mh{shash},1,"gasCnt:"   .$eCnt];
      push @evtEt,[$mh{shash},1,"gasPower:"    .$P];    
      my $sumState = "eState:E: $eCnt P: $P";
      push @evtEt,[$mh{shash},1,$sumState];    
      push @evtEt,[$mh{shash},1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      my $eo = ReadingsVal($mh{shash}->{NAME},"gasCntOffset",0);
      if($eCnt == 0 && hex($mh{mNo}) < 3 ){
        if($mh{devH}->{helper}{PONtest}){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",] ;
          $mh{devH}->{helper}{PONtest} = 0;
        }
        $eo += ReadingsVal($mh{shash}->{NAME},"gasCnt",0);
        push @evtEt,[$mh{shash},1,"gasCntOffset:".$eo];
      }
      push @evtEt,[$mh{shash},1,"gasCntCalc:".($eo + $eCnt)];
    }
    elsif ($mh{mTp} eq "5E" ||$mh{mTp} eq "5F" ) {  #    POWER_EVENT_CYCLIC
      $mh{shash} = $modules{CUL_HM}{defptr}{$mh{src}."01"}
                             if($modules{CUL_HM}{defptr}{$mh{src}."01"});
      my ($eCnt,$P) = map{hex($_)} unpack 'A6A6',$mh{p};
      $eCnt = ($eCnt&0x7fffff)/10;          #0.0  ..838860.7  Wh
      $P = $P   /100;                       #0.0  ..167772.15 W
      
      push @evtEt,[$mh{shash},1,"energy:"   .$eCnt];
      push @evtEt,[$mh{shash},1,"power:"    .$P];    

      my $sumState = "eState:E: $eCnt P: $P";
      
      push @evtEt,[$mh{shash},1,$sumState];    
      push @evtEt,[$mh{shash},1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      
      push @evtEt,[$defs{$mh{devH}->{channel_02}},1,"state:$eCnt"] if ($mh{devH}->{channel_02});
      push @evtEt,[$defs{$mh{devH}->{channel_03}},1,"state:$P"   ] if ($mh{devH}->{channel_03});

      my $el = ReadingsVal($mh{shash}->{NAME},"energy",0);# get Energy last
      my $eo = ReadingsVal($mh{shash}->{NAME},"energyOffset",0);
      if($eCnt == 0 && hex($mh{mNo}) < 3 && !$mh{shash}->{helper}{pon}){
        if($mh{devH}->{helper}{PONtest}){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",] ;
          $mh{devH}->{helper}{PONtest} = 0;
        }
        $eo += $el;
        push @evtEt,[$mh{shash},1,"energyOffset:".$eo];
        $mh{shash}->{helper}{pon} = 1;# power on is detected - only send once
      }
      elsif($el > 800000 && $el > $eCnt ){# handle overflow
        $eo += 838860.7;
        push @evtEt,[$mh{shash},1,"energyOffset:".$eo];
      }
      else{
        delete $mh{shash}->{helper}{pon};
      }
      push @evtEt,[$mh{shash},1,"energyCalc:".($eo + $eCnt)];
    }
  }
  elsif($mh{st} eq "powerMeter") {#############################################
    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006")) {  #    or Info_Status message here
      # powerOn
      # m:01 A45F 36D06A 123ABC 8000000000000000090CFE
      # m:02 A410 36D06A 123ABC 06010000
      my ($val,$err) = (hex($mI[2])/2,hex($mI[3]));
      my $chId = $mh{src}.$mh{chnHx};
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      my $vs = ($val==100 ? "on":($val==0 ? "off":"$val %")); # user string...

      #--    if timed on is set possibly show this in a state --
      my ($timedOn,$stateExt)=("off","");
      if($err&0x40){
        $timedOn = "running";
        $stateExt = "-till" if(AttrVal($mh{shash}->{NAME},"param","") =~ m/showTimed/ );
      }
      push @evtEt,[$mh{shash},1,"level:$val"];
      push @evtEt,[$mh{shash},1,"pct:$val"]; # duplicate to level - necessary for "slider"
      push @evtEt,[$mh{shash},1,"deviceMsg:$vs$target"] if($mh{chnHx} ne "00");
      push @evtEt,[$mh{shash},1,"state:$vs$stateExt"];
      push @evtEt,[$mh{shash},1,"timedOn:$timedOn"];
    }
    elsif ($mh{mTp} eq "5E" ||$mh{mTp} eq "5F" ) {  #    POWER_EVENT_CYCLIC
      $mh{shash} = $modules{CUL_HM}{defptr}{$mh{src}."02"}
                             if($modules{CUL_HM}{defptr}{$mh{src}."02"});
      my ($eCnt,$P,$I,$U,$F) = map{hex($_)} unpack 'A6A6A4A4A2',$mh{p};
      $eCnt = ($eCnt&0x7fffff)/10;          #0.0  ..838860.7  Wh
      $P = $P   /100;                       #0.0  ..167772.15 W
      $I = $I   /1;                         #0.0  ..65535.0   mA
      $U = $U   /10;                        #0.0  ..6553.5    mV
      $F -= 256 if ($F > 127);
      $F = $F/100+50;                      # 48.72..51.27     Hz
      
      push @evtEt,[$mh{shash},1,"energy:"   .$eCnt];
      push @evtEt,[$mh{shash},1,"power:"    .$P];    
      push @evtEt,[$mh{shash},1,"current:"  .$I];    
      push @evtEt,[$mh{shash},1,"voltage:"  .$U];    
      push @evtEt,[$mh{shash},1,"frequency:".$F];
      push @evtEt,[$mh{shash},1,"eState:E: $eCnt P: $P I: $I U: $U f: $F"];    
      push @evtEt,[$mh{shash},1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      
      push @evtEt,[$defs{$mh{devH}->{channel_02}},1,"state:$eCnt"] if ($mh{devH}->{channel_02});
      push @evtEt,[$defs{$mh{devH}->{channel_03}},1,"state:$P"   ] if ($mh{devH}->{channel_03});
      push @evtEt,[$defs{$mh{devH}->{channel_04}},1,"state:$I"   ] if ($mh{devH}->{channel_04});
      push @evtEt,[$defs{$mh{devH}->{channel_05}},1,"state:$U"   ] if ($mh{devH}->{channel_05});
      push @evtEt,[$defs{$mh{devH}->{channel_06}},1,"state:$F"   ] if ($mh{devH}->{channel_06});
      
      my $el = ReadingsVal($mh{shash}->{NAME},"energy",0);# get Energy last
      my $eo = ReadingsVal($mh{shash}->{NAME},"energyOffset",0);
      if($eCnt == 0 && hex($mh{mNo}) < 3 && !$mh{shash}->{helper}{pon}){
        if($mh{devH}->{helper}{PONtest}){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",] if ($mh{md} !~ m/^HM-ES-PMSW1/);
          $mh{devH}->{helper}{PONtest} = 0;
        }
        $eo += $el;
        push @evtEt,[$mh{shash},1,"energyOffset:".$eo];
        $mh{shash}->{helper}{pon} = 1;# power on is detected - only ssend once
      }
      elsif($el > 800000 && $el > $eCnt ){# handle overflow
        $eo += 838860.7;
        push @evtEt,[$mh{shash},1,"energyOffset:".$eo];
      }
      else{
        delete $mh{shash}->{helper}{pon};
      }
      push @evtEt,[$mh{shash},1,"energyCalc:".($eo + $eCnt)];
      CUL_HM_unQEntity($mh{shash}->{NAME},"qReqStat");
    }
  }
  elsif($mh{st} eq "repeater"){ ###############################################
    if (($mh{mTyp} eq "0201") ||  # handle Ack_Status
        ($mh{mTyp} eq "1006")) {  #or Info_Status message here
      my ($state,$err);
      ($state,$err) = ($1,hex($2)) if ($mh{p} =~ m/^....(..)(..)/);
      # not sure what level are possible
      push @evtEt,[$mh{cHash},1,"state:"  .($state eq '00'?"ok":"level:".$state)];
      push @evtEt,[$mh{devH} ,1,"battery:".(($err&0x80)?"low"  :"ok"  )];
      my $flag = ($err>>4) &0x7;
      push @evtEt,[$mh{cHash},1,"flags:"  .(($flag)?"none"     :$flag  )];
    }
  }
  elsif($mh{st} eq "virtual" && $mh{md} =~ m/^(virtual_|VIRTUAL)/){ ###########
    # possibly add code to count all acks that are paired.
    if($mh{mTp} eq "02") {# this must be a reflection from what we sent, ignore
      push @evtEt,[$mh{shash},1,""];
    }
    elsif ($mh{mTp} =~ m/^4[01]/){# if channel is SD team we have to act
      if ($mh{cHash}->{helper}{fkt} && $mh{cHash}->{helper}{fkt} eq "sdLead2"){
        CUL_HM_parseSDteam_2($mh{mTp},$mh{src},$mh{dst},$mh{p});
      }
      else{
        CUL_HM_parseSDteam($mh{mTp},$mh{src},$mh{dst},$mh{p});
      }
    }
  }
  elsif($mh{st} eq "outputUnit"){ #############################################
    if($mh{mTp} eq "40" && @mI == 2){
      my $bno = hex($mI[1]);

      push @evtEt,[$mh{cHash},1,"state:Btn$mh{chn} on$target"];
    }
    elsif(($mh{mTyp} eq "0201") ||   # handle Ack_Status
          ($mh{mTyp} eq "1006")){    #    or Info_Status message
      my $msgState = (@mI > 2 ? $mI[2] : "" );
      if ($mh{md} eq "HM-OU-LED16") {
        #special: all LEDs map to device state
        my $devState = ReadingsVal($mh{devN},"color","00000000");
        if($parse eq "powerOn"){# reset LEDs after power on
          CUL_HM_PushCmdStack($mh{devH},'++A011'.$ioId.$mh{src}."8100".$devState);
          CUL_HM_ProcessCmdStack($mh{devH});
          # no event necessary, all the same as before
        }
        else {# just update datafields in storage
          my %colTbl=("00"=>"off","01"=>"red","10"=>"green","11"=>"orange");
          if (@mI > 8){#status for all channel included
            # open to decode byte $mI[4] - related to backlight? seen 20 and 21
            my $lStat = join("",@mI[5..8]); # all LED status in one long
            my @leds = reverse(unpack('(A2)*',sprintf("%032b",hex($lStat))));
            $_ = $colTbl{$_} foreach (@leds);
            for(my $cCnt = 0;$cCnt<16;$cCnt++){# go for all channels
              my $cH = $modules{CUL_HM}{defptr}{$mh{src}.sprintf("%02X",$cCnt+1)};
              next if (!$cH);
              if (ReadingsVal($cH->{NAME},"state","") ne $leds[$cCnt]) {
                push @evtEt,[$cH,1,"color:$leds[$cCnt]"];
                push @evtEt,[$cH,1,"state:$leds[$cCnt]"];
              }
            }
            push @evtEt,[$mh{devH},1,"color:$lStat"];
            push @evtEt,[$mh{devH},1,"state:$lStat"];
          }
          else{# branch can be removed if message is always that long
            my $bitLoc = ($mh{chn}-1)*2;#calculate bit location
            my $mask = 3<<$bitLoc;
            my $value = sprintf("%08X",(hex($devState) &~$mask)|($msgState<<$bitLoc));
            push @evtEt,[$mh{devH},1,"color:$value"];
            push @evtEt,[$mh{devH},1,"state:$value"];
            if (!$mh{cHash}{helper}{role}{dev}){
              my $actColor = $colTbl{sprintf("%02b",hex($msgState))};
              $actColor = "unknown" if(!$actColor);
              push @evtEt,[$mh{cHash},1,"color:$actColor"];
              push @evtEt,[$mh{cHash},1,"state:$actColor"];
            }
           }
        }
      }
#      elsif ($mh{md} eq "HM-OU-CFM-PL"){
      else{
        my $val = hex($mI[2])/2;
        $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
        push @evtEt,[$mh{cHash},1,"state:$val"];
        push @evtEt,[$mh{devH} ,1,"battery:".(hex($mI[3]&0x80)?"low":"ok" )]if ($mh{md} eq "HM-OU-CFM-TW" && $mI[3]);
      }
      
    }
  }
  elsif($mh{st} =~ m/^(motionDetector|motionAndBtn)$/) { ######################
    my $state = $mI[2];
    if(($mh{mTyp} eq "0201") ||
       ($mh{mTyp} eq "1006")) {
      my ($chn,$err,$bright)=(hex($mI[1]),hex($mI[3]),hex($mI[2]));
      my $chId = $mh{src}.sprintf("%02X",$chn&0x3f);
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      push @evtEt,[$mh{shash},1,"brightness:".$bright];
      if ($mh{md} eq "HM-SEC-MDIR"){
        push @evtEt,[$mh{shash},1,"sabotageError:".(($err&0x0E)?"on":"off")];
      }
      else{
        push @evtEt,[$mh{shash},1,"cover:".        (($err&0x0E)?"open" :"closed")];
      }
      push @evtEt,[$mh{devH},1,"battery:".   (($err&0x80)?"low"  :"ok"  )];
    }
    elsif($mh{mTp} eq "41") {#01 is channel
      my($chn,$cnt,$bright,$nextTr) = map{hex($_)} (@mI,0);
      push @evtEt,[$mh{devH},1,"battery:".($chn&0x80?"low":"ok")]; # observed with HM-SEN-MDIR-SM FW V1.6
      if ($nextTr){
        $nextTr = (15 << ($nextTr >> 4) - 4); # strange mapping of literals
        RemoveInternalTimer($mh{cName}.":motionCheck");
        InternalTimer($mh{rectm}+$nextTr+2,"CUL_HM_motionCheck", $mh{cName}.":motionCheck", 0);
        $mh{cHash}->{helper}{moStart} = $mh{rectm} if (!defined $mh{cHash}->{helper}{moStart});
      }
      else{
        $nextTr = "none ";
      }
      
      my $chId = $mh{src}.sprintf("%02X",$chn & 0x3f);
      $mh{shash} = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
                             
      push @evtEt,[$mh{shash},1,"state:motion"];
      push @evtEt,[$mh{shash},1,"motion:on$target"];
      push @evtEt,[$mh{shash},1,"motionCount:$cnt"."_next:$nextTr"."s"];
      push @evtEt,[$mh{shash},1,"brightness:$bright"];
    }
    elsif($mh{mTp} eq "70" && $mh{p} =~ m/^7F(..)(.*)/) {
      my($d1, $d2) = ($1, $2);
      push @evtEt,[$mh{shash},1,"devState_raw$d1:$d2"];
      $state = 0;
    }

    if($ioId eq $mh{dst} && $mh{mFlgH}&0x20 && $state){
      push @ack,$mh{shash},$mh{mNo}."8002".$ioId.$mh{src}."0101".$state."00";
      $mh{AckDone} = 1;  #  mark allready done device specific
    }
  }
  elsif($mh{st} eq "smokeDetector") { #########################################
    #Info Level: mTp=0x10 p(..)(..)(..) subtype=06, channel, state (1 byte)
    #Event:      mTp=0x41 p(..)(..)(..) channel   , unknown, state (1 byte)

    if    ($mh{mTp} eq "10" && $mh{p} =~ m/^06..(..)(..)/) {
       # m:A0 A010 233FCE 1743BF 0601 01  00 31
      my ($state,$err) = (hex($1),hex($2));
      
      push @evtEt,[$mh{devH} ,1,"battery:"     .(($err&0x80)?"low"     :"ok")];
      push @evtEt,[$mh{cHash},1,"level:"  .hex($state)];
      $state = (($state < 2)?"off":"smoke-Alarm");
      push @evtEt,[$mh{cHash},1,"state:$state"];
      if ($mh{md} eq "HM-SEC-SD-2"){
        push @evtEt,[$mh{cHash},1,"alarmTest:"   .(($err&0x02)?"failed"  :"ok")];
        push @evtEt,[$mh{cHash},1,"smokeChamber:".(($err&0x04)?"degraded":"ok")];
        if(length($mh{p}) == 8 && $mh{mNo} eq "80"){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",] ;
        }
        CUL_HM_parseSDteam_2($mh{mTp},$mh{src},$mh{dst},$mh{p});
      }
      else{
        if($mh{devH}->{helper}{PONtest} &&(length($mh{p}) == 8 && $mh{mNo} eq "00")){
          push @evtEt,[$mh{devH},1,"powerOn:$mh{tmStr}",] ;
          $mh{devH}->{helper}{PONtest} = 0;
        }
      }
      my $tName = ReadingsVal($mh{cName},"peerList","");#inform team
      $tName =~ s/,.*//;
      CUL_HM_updtSDTeam($tName,$mh{cName},$state);
    }
    elsif ($mh{mTp} =~ m/^4[01]/){ #autonomous event
      #01 1441 44E347 44E347 0101960000048BAF3B0E
      #02 1441 44E347 44E347 01020000000445C4A14C
      if ($mh{md} eq "HM-SEC-SD-2"){
        CUL_HM_parseSDteam_2($mh{mTp},$mh{src},$mh{dst},$mh{p});
      }
      else{
        CUL_HM_parseSDteam($mh{mTp},$mh{src},$mh{dst},$mh{p});
      }
    }
    elsif ($mh{mTp} eq "01"){ #Configs
      my $sType = substr($mh{p},0,2);
      if   ($sType eq "01"){# add peer to group
        push @evtEt,[$mh{shash},1,"SDteam:add_$mh{dstN}"];
      }
      elsif($sType eq "02"){# remove from group
        push @evtEt,[$mh{shash},1,"SDteam:remove_".$mh{dstN}];
      }
      elsif($sType eq "05"){# set param List 3 and 4
        push @evtEt,[$mh{shash},1,""];
      }
    }
    else{
      push @evtEt,[$mh{shash},1,"SDunknownMsg:$mh{p}"] if(!@evtEt);
    }

    if($ioId eq $mh{dst} && ($mh{mFlgH}&0x20)){  # Send Ack/Nack
      if ($mh{mFlg}.$mh{mTp} eq 'A001') {
        push @ack,$mh{shash},$mh{mNo}.'8002'.$ioId.$mh{src}.'80';
      }
      else {
        push @ack,$mh{shash},$mh{mNo}.'8002'.$ioId.$mh{src}.'00'  #noansi: additional CUL ACK
            if (   $ioId eq $mh{dst}
                && !$mh{wakupAck} #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983 not if wakeup is sent
                && !$mh{devH}->{IODev}->{helper}{VTS_ACK} # for TSCUL VTS0.17 up
                && $mh{devH}->{IODev}->{TYPE} !~ m/^(?:HMLAN|HMUARTLGW)$/s ); #noansi: additional CUL ACK 
      }
    }
  }
  elsif($mh{st} eq "threeStateSensor") { ######################################
    #Event:      mTp=0x41 p(..)(..)(..)     channel   , unknown, state
    #Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
    #AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)
    my ($chn,$state,$err,$cnt); #define locals
    if(($mh{mTyp} eq "0201") ||
       ($mh{mTyp} eq "1006")) {
      ($chn,$state,$err) = (hex($mI[1]), $mI[2], hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
      push @evtEt,[$mh{devH},1,"alive:yes"];
      push @evtEt,[$mh{devH},1,"battery:". (($err&0x80)?"low"  :"ok"  )];
      if (  $mh{md} =~ m/^(HM-SEC-SC.*|HM-SEC-RHS|ROTO_ZEL-STG-RM-F.K)$/){
                                 push @evtEt,[$mh{devH},1,"sabotageError:".(($err&0x0E)?"on"   :"off")];}
      elsif($mh{md} ne "HM-SEC-WDS"){push @evtEt,[$mh{devH},1,"cover:"        .(($err&0x0E)?"open" :"closed")];}
    }
    elsif($mh{mTp} eq "41"){
      ($chn,$cnt,$state)=(hex($1),$2,$3) if($mh{p} =~ m/^(..)(..)(..)/);
      my $err = $chn & 0x80;
      $chn = sprintf("%02X",$chn & 0x3f);
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
      push @evtEt,[$mh{devH},1,"battery:". ($err?"low"  :"ok"  )];
      push @ack,$mh{shash},$mh{mNo}."8002".$mh{dst}.$mh{src}."00"
        if (   $ioId eq $mh{dst}
            && !$mh{wakupAck} #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983 not if wakeup is sent
            && !$mh{devH}->{IODev}->{helper}{VTS_ACK}
            && $mh{devH}->{IODev}->{TYPE} !~ m/^(HMLAN|HMUARTLGW)$/); #noansi: additional CUL ACK 
    }
    if (defined($state)){# if state was detected post events
      my $txt;
      if    ($mh{shash}->{helper}{lm} && $mh{shash}->{helper}{lm}{hex($state)}){$txt = $mh{shash}->{helper}{lm}{hex($state)}}
      elsif ($lvlStr{md}{$mh{md}}){$txt = $lvlStr{md}{$mh{md}}{$state}}
      elsif ($lvlStr{st}{$mh{st}}){$txt = $lvlStr{st}{$mh{st}}{$state}}
      else                    {$txt = "unknown:$state"}

      push @evtEt,[$mh{shash},1,"state:$txt"];
      push @evtEt,[$mh{shash},1,"contact:$txt$target"];
    }
    elsif(!@evtEt){push @evtEt,[$mh{devH},1,"3SSunknownMsg:$mh{p}"];}
  }
  elsif($mh{st} eq "winMatic") {  #############################################
    my($sType,$chn,$lvl,$stat) = @mI;
    if(($mh{mTyp} eq "0201") ||
       ($mh{mTyp} eq "1006")){
      $stat = hex($stat);
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});
      my $lvlS = $lvl eq "FF" ? 1:0;
      $lvl = hex($lvl)/2;
      my $dat4 = ($stat >> 4) & 0x03;
      if ($chn eq "01"){
        my %err = (0=>"ok",1=>"TurnError",2=>"TiltError");
        my %dir = (0=>"no",1=>"up",2=>"down",3=>"undefined");
        push @evtEt,[$mh{shash},1,"motorErr:"  .$err{($stat >> 1) & 0x03}];
        push @evtEt,[$mh{shash},1,"direction:" .$dir{$dat4}];
        push @evtEt,[$mh{shash},1,"level:"     .($lvlS ? "0"      : $lvl)      ] if($dat4 == 0);
        push @evtEt,[$mh{shash},1,"lock:"      .($lvlS ? "locked" : "unlocked")];
        push @evtEt,[$mh{shash},1,"state:"     .($lvlS ? "locked" : $lvl)      ];
      }
      else{ #should be akku
        my %statF = (0=>"trickleCharge",1=>"charge",2=>"discharge",3=>"unknown");
        push @evtEt,[$mh{shash},1,"charge:"    .$statF{$dat4}];
        push @evtEt,[$mh{shash},1,"batteryPercent:".($lvl)];
        push @evtEt,[$mh{shash},1,"battery:"   .($lvl>20 ? "ok" : "low")];
     }
      # stateflag meaning unknown
    }
  }
  elsif($mh{st} eq "keyMatic") {  #############################################
    #Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
    #AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if(($mh{mTyp} eq "1006") ||
       ($mh{mTyp} eq "0201")) {
      my ($chn,$val, $err) = ($mI[1],hex($mI[2]), hex($mI[3]));
      $mh{shash} = $modules{CUL_HM}{defptr}{"$mh{src}$chn"}
                             if($modules{CUL_HM}{defptr}{"$mh{src}$chn"});

      my $stErr = ($err >>1) & 0x7;
      my $error = 'unknown_'.$stErr;
      $error = 'motor aborted'  if ($stErr == 2);
      $error = 'clutch failure' if ($stErr == 1);
      $error = 'none'           if ($stErr == 0);
      my %dir = (0=>"none",1=>"up",2=>"down",3=>"undef");
      my $state = "";
      RemoveInternalTimer ($mh{devN}.":uncertain:permanent");
      CUL_HM_unQEntity($mh{devN},"qReqStat");
      if ($err & 0x30) { # uncertain - we have to check
        CUL_HM_stateUpdatDly($mh{devN},13) if(ReadingsVal($mh{devN},"uncertain","no") eq "no");
        InternalTimer($mh{rectm}+20,"CUL_HM_readValIfTO", $mh{devN}.":uncertain:permanent", 0);
        $state = " (uncertain)";
      }
      push @evtEt,[$mh{shash},1,"unknown:40"] if($err&0x40);
      push @evtEt,[$mh{devH} ,1,"battery:"   .(($err&0x80) ? "low":"ok")];
      push @evtEt,[$mh{shash},1,"uncertain:" .(($err&0x30) ? "yes":"no")];
      push @evtEt,[$mh{shash},1,"direction:" .$dir{($err>>4)&3}];
      push @evtEt,[$mh{shash},1,"error:" .    ($error)];
      push @evtEt,[$mh{shash},1,"lock:"  .   (($val == 1) ? "unlocked" : "locked")];
      push @evtEt,[$mh{shash},1,"state:" .   (($val == 1) ? "unlocked" : "locked") . $state];
    }
  }
  elsif($mh{md} eq "CCU-FHEM") {  #############################################
    push @evtEt,[$mh{shash},1,""];
  }
  elsif (eval "defined(&CUL_HM_Parse$mh{st})"){################################
    no strict "refs";
    my @ret = &{"CUL_HM_Parse$mh{st}"}($mh{mFlg},$mh{mTp},$mh{src},$mh{dst},$mh{p},$target);
    use strict "refs";
    push @evtEt,@ret;
  }
  else{########################################################################
    ; # no one wants the message
  }

  #------------ parse if FHEM or virtual actor is destination   ---------------

  if(   AttrVal($mh{dstN}, "subType", "none") eq "virtual"
     && AttrVal($mh{dstN}, "model", "none") =~ m/^(virtual_|VIRTUAL)/){# see if need for answer
    my $sendAck = 0;
    if   ($mh{mTp} =~ m/^4/ && @mI > 1) { #Push Button event
      my ($recChn,$trigNo) = (hex($mI[0]),hex($mI[1]));# button number/event count
      my $longPress = ($recChn & 0x40)?"long":"short";
      my $recId = $mh{src}.sprintf("%02X",($recChn&0x3f));
      foreach my $dChId (CUL_HM_getAssChnIds($mh{dstN})){# need to check all chan
        next if (!$modules{CUL_HM}{defptr}{$dChId});
        my $dChNo = substr($dChId,6,2);
        my $dChName = CUL_HM_id2Name($dChId);
        if(AttrVal($dChName,"peerIDs","peerUnread") =~ m/$recId/){
          my $dChHash = $defs{$dChName};
          $sendAck = 1;
          $dChHash->{helper}{trgLgRpt} = 0
                if (!defined($dChHash->{helper}{trgLgRpt}));
          $dChHash->{helper}{trgLgRpt} +=1;
          my $trgLgRpt = $dChHash->{helper}{trgLgRpt};

          my ($stT,$stAck) = ("ack","00");#state text and state Ack for Msg
          if (AttrVal($dChName,"param","") !~ m/noOnOff/){
            $stT  = ReadingsVal($dChName,"virtActState","OFF");
            $stT = ($stT eq "OFF")?"ON":"OFF" 
                if ($trigNo ne ReadingsVal($dChName,"virtActTrigNo","0"));
            $stAck = '01'.$dChNo.(($stT eq "ON")?"C8":"00")."00"
          }
          
          if ((($mh{mFlgH} & 0x24) == 0x20)){
            $longPress .= "_Release";
            $dChHash->{helper}{trgLgRpt}=0;
            push @ack,$mh{shash},$mh{mNo}."8002".$mh{dst}.$mh{src}.$stAck;
          }
          push @evtEt,[$dChHash,1,"state:$stT"];
          push @evtEt,[$dChHash,1,"virtActState:$stT"];
          push @evtEt,[$dChHash,1,"virtActTrigger:".CUL_HM_id2Name($recId)];
          push @evtEt,[$dChHash,1,"virtActTrigType:$longPress"];
          push @evtEt,[$dChHash,1,"virtActTrigRpt:$trgLgRpt"];
          push @evtEt,[$dChHash,1,"virtActTrigNo:$trigNo"];
        }
      }
    }
    elsif($mh{mTp} eq "58" && $mh{p} =~ m/^(..)(..)/) {# climate event
      my ($d1,$vp) =($1,hex($2)); # adjust_command[0..4] adj_data[0..250]
      $vp = int($vp/2.56+0.5);    # valve position in %
      my $chnHash = $modules{CUL_HM}{defptr}{$mh{dst}."01"};
      $chnHash = $mh{dstH} if (!$chnHash);
      push @evtEt,[$chnHash,1,"ValvePosition:$vp %"];
      push @evtEt,[$chnHash,1,"ValveAdjCmd:".$d1];
      push @ack,$chnHash,$mh{mNo}."8002".$mh{dst}.$mh{src}.'0101'.
                         sprintf("%02X",$vp*2)."0000";
    }
    elsif($mh{mTp} eq "02"){
      if (defined($mh{dstH})                                      &&
          $mh{dstH}->{helper}{prt}{rspWait}{mNo}                  &&
          $mh{dstH}->{helper}{prt}{rspWait}{mNo} == hex($mh{mNo}) ){
        #ack we waited for - stop Waiting
        CUL_HM_respPendRm($mh{dstH});
      }
    }
    else{
      $sendAck = 1;
    }
    push @ack,$mh{dstH},$mh{mNo}."8002".$mh{dst}.$mh{src}."00" if ($mh{mFlgH} & 0x20 && (!scalar(@ack)) && $sendAck && defined($mh{dstH}));
  }
  elsif($ioId eq $mh{dst}){# if fhem is destination check if we need to react
    if(   $mh{mTp} =~ m/^4./    #Push Button event
       && !$mh{AckDone}          #noansi: allready done device specific
       && ($mh{mFlgH} & 0x20)  #response required Flag
       && !$mh{wakupAck}        #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983 not if wakeup is sent
       ){
                # fhem CUL shall ack a button press
      if ($mh{md} =~ m/^(HM-SEC-SC.*|ROTO_ZEL-STG-RM-FFK)$/){# SCs - depending on FW version - do not accept ACK only. Especially if peered
        push @ack,$mh{shash},$mh{mNo}."8002".$mh{dst}.$mh{src}."0101".((hex($mI[0])&1)?"C8":"00")."00";
      }
      else{
        push @ack,$mh{shash},$mh{mNo}."8002$mh{dst}$mh{src}"."00";
      }
      Log3 $mh{devN},5,"CUL_HM $mh{devN} prep ACK for $mI[0]";
    }
  }

  #------------ send default ACK if not applicable------------------
  #    ack if we are destination, anyone did accept the message (@evtEt)
  #        parser did not supress
  push @ack,$mh{shash}, $mh{mNo}."8002".$ioId.$mh{src}."00"
      if(   ($ioId eq $mh{dst})   #are we adressee
         && ($mh{mFlgH} & 0x20)   #response required Flag
         && !$mh{wakupAck}        #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983 not if wakeup is sent
         && @evtEt            #only ack if we identified it
         && (!scalar(@ack))   #sender requested ACK
         );

  if (scalar(@ack)) {# send acks and store for repeat
    my $rr = $respRemoved;
    $mh{devH}->{helper}{rpt}{IO}  = $mh{ioName};
    $mh{devH}->{helper}{rpt}{flg} = substr($mh{msg},5,1);
    $mh{devH}->{helper}{rpt}{ack} = \@ack;
    $mh{devH}->{helper}{rpt}{ts}  = $mh{rectm};
    my $wulzy =    defined($mh{devH}->{helper}{io}{flgs})
                && ($mh{devH}->{helper}{io}{flgs} & 0x02)
                && $mh{devH}->{cmdStack}
                && scalar @{$mh{devH}->{cmdStack}}; #noansi: wakeup replacement required
    my ($h, $m);
    my $i = 0;
    while ($i < scalar(@ack)) {
      $h = $ack[$i++];
      $m = $ack[$i++];
      if ($mh{devH}->{helper}{aesAuthBytes}) {
        $m .= $mh{devH}->{helper}{aesAuthBytes} if (!(   $mh{devH}->{IODev}->{helper}{VTS_AES} # tsculfw does default ACK automatically only. A default ACK may just update a default ACK in tsculfw buffer
                                                      && ($m =~ m/^..(..)02/s))); # append auth bytes to first answer to device after sign from device
        delete($mh{devH}->{helper}{aesAuthBytes});
      }
      if ($wulzy && ($m =~ m/^..(..)02/s)) { #noansi: wakeup replacement for acks
        my $flr = $1;
        next if (   ($flr eq '80')
                 && (   $mh{devH}->{IODev}->{helper}{VTS_LZYCFG} # for TSCUL VTS0.34 up, wakeup Ack automatically sent
                     || $mh{devH}->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s ) ); # also for HMLAN/HMUARTLGW?
        $flr = sprintf("%02X", hex($flr)|0x01);
      }
      CUL_HM_SndCmd($h, $m);
    }
    $respRemoved = $rr;
    Log3 $mh{devN},5,"CUL_HM $mh{devN} sent ACK:".(int(@ack));
  }
  CUL_HM_ProcessCmdStack($mh{devH}) if ($respRemoved); # cont if complete
  CUL_HM_sndIfOpen("x:".$mh{ioName});

  #------------ process events ------------------
  push @evtEt,[$mh{devH},1,"noReceiver:src:$mh{src} ".$mh{mFlg}.$mh{mTp}." $mh{p}"] 
        if(!@entities && !@evtEt);
  push @entities,CUL_HM_pushEvnts();
  @entities = CUL_HM_noDup(@entities,$mh{devN});
  $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$mh{devN}$/,@entities);
  return @entities;
}
sub CUL_HM_parseCommon(@){#####################################################
  # parsing commands that are device independent
  my ($ioHash,$mhp) = @_;
  return "" if(!$mhp->{devH}{DEF});# this should be from ourself
  my ($p)     = $mhp->{p};
  my $devHlpr = $mhp->{devH}{helper};     
  my $ret = "";
  my $rspWait = $devHlpr->{prt}{rspWait};
  my $pendType = $rspWait->{Pending} ? $rspWait->{Pending} : "";
  my $mNoInt = hex($mhp->{mNo});
  #------------ parse message flag for start processing command Stack
  # TC wakes up with 8270, not with A258
  # VD wakes up with 8202
  #                  9610
  my $rxt = CUL_HM_getRxType($mhp->{shash});
  $devHlpr->{PONtest} = 1 if($mhp->{mNo} =~ m/^0[012]/ &&
                             $devHlpr->{HM_CMDNR} < 250 && 
                             $devHlpr->{HM_CMDNR} > 5);# this is power on
  $devHlpr->{HM_CMDNR} = hex($mhp->{mNo});# sync msgNo prior to any sending
  if ($mhp->{mFlgH} & 0x02) { # wakeup signal
    if ($mhp->{mFlgH} & 0x20) { # &0x22== 0x22 wakeup signal in lazy config device manner
      if    ($rxt & 0x10) { #lazy config device
        if ($devHlpr->{prt}{sleeping}) {
          CUL_HM_appFromQ($mhp->{devN},"cf");# stack cmds if waiting
          if (defined($mhp->{devH}->{helper}{io}{flgs}) && ($mhp->{devH}->{helper}{io}{flgs} & 0x02)) { #noansi: io prepared?
            if (!(   $mhp->{devH}->{IODev}->{helper}{VTS_LZYCFG} # for TSCUL VTS0.34 up, wakeup Ack was automatically sent
                  || $mhp->{devH}->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s )
                ) {
              CUL_HM_SndCmd($mhp->{devH}, $mhp->{mNo}.'8102'.CUL_HM_IoId($mhp->{devH}).$mhp->{src}.'00'); #noansi: Ack with wakeup bit set for CUL
            }
            $devHlpr->{prt}{sleeping} = 0;
            CUL_HM_ProcessCmdStack($mhp->{devH});
            $mhp->{wakupAck} = 1; #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983
          }
        }
        $devHlpr->{prt}{sleeping} = 1 if (!$devHlpr->{prt}{sProc}); # set back to sleeping with next trigger, if nothing to do
      }
      elsif ($rxt & 0x08) { #wakeup device
        CUL_HM_appFromQ($mhp->{devN},"wu");# stack cmd(s) if waiting
        if (defined($mhp->{devH}->{helper}{io}{flgs}) && ($mhp->{devH}->{helper}{io}{flgs} & 0x02)) { #noansi: io prepared?
          if (!(   $mhp->{devH}->{IODev}->{helper}{VTS_LZYCFG} # for TSCUL VTS0.34 up does it automatically if configured to lazy config
                || $mhp->{devH}->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s ) #HMLAN and HMUARTLGW does it automatically if configured to lazy config
              ) {
            CUL_HM_SndCmd($mhp->{devH}, $mhp->{mNo}.'8102'.CUL_HM_IoId($mhp->{devH}).$mhp->{src}.'00'); #noansi: Ack with wakeup bit set for CUL
          }
          CUL_HM_ProcessCmdStack($mhp->{devH});
          $mhp->{wakupAck} = 1; #frank: noansi from https://forum.fhem.de/index.php/topic,121139.msg1158983.html#msg1158983
        }
      }
    }
    else {                      # &0x22== 0x02 wakeup signal in wakeup device manner
      if ($rxt & 0x18) { #wakeup device or lazy config device
        CUL_HM_appFromQ($mhp->{devN},"wu");# stack cmd(s) if waiting
        if (defined($mhp->{devH}->{helper}{io}{flgs}) && ($mhp->{devH}->{helper}{io}{flgs} & 0x02)) { #noansi: io prepared?
          if (!(   $mhp->{devH}->{IODev}->{helper}{VTS_LZYCFG} # for TSCUL VTS0.34 up does it automatically if configured to lazy config
                || $mhp->{devH}->{IODev}->{TYPE} =~ m/^(?:HMLAN|HMUARTLGW)$/s ) #HMLAN and HMUARTLGW does it automatically if configured to lazy config
              ) {
            CUL_HM_SndCmd($mhp->{devH}, '++A112'.CUL_HM_IoId($mhp->{devH}).$mhp->{src}); #noansi: answer with wakeup received message for CUL
          }
          CUL_HM_ProcessCmdStack($mhp->{devH});
        }
      }
    }
  }
  else {
    if ($mhp->{mFlgH} & 0x20) { # &0x22== 0x20 no wakeup signal
      $devHlpr->{prt}{sleeping} = 1 if (   ($rxt & 0x10) # lazy config device
                                        && !$devHlpr->{prt}{sProc} ); # autonomous message from device
    }
  }
  
  my $repeat;
  $devHlpr->{supp_Pair_Rep} = 0 if ($mhp->{mTp} ne "00"); # noansi: reset pairing suppress flag as we got something different from device 
  if   ($mhp->{mTp} eq "02"){# Ack/Nack/aesReq ####################
    my $reply;
    my $success;

    if ($devHlpr->{prt}{rspWait}{brstWu}){
      if ($devHlpr->{prt}{rspWait}{mNo} == $mNoInt &&
          $mhp->{mStp} eq "00"){
        CUL_HM_appFromQ($mhp->{devN},"wu");# stack cmd(s) if waiting frank:
        if ($devHlpr->{prt}{awake} && $devHlpr->{prt}{awake}==4){#re-burstWakeup
          CUL_HM_respPendRm($mhp->{devH});
          return "done";
        }
        $mhp->{devH}{protCondBurst} = "on" if (   $mhp->{devH}{protCondBurst}
                                               && $mhp->{devH}{protCondBurst} !~ m/forced/);
        $devHlpr->{prt}{awake}=2;#awake
      }
      else{
        $mhp->{devH}{protCondBurst} = "off" if (  !$mhp->{devH}{protCondBurst}
                                                || $mhp->{devH}{protCondBurst} !~ m/forced/);
        $devHlpr->{prt}{awake}=3;#reject
        return "done";
      }
    }
    if (defined($devHlpr->{AESreqAck})) {
      if (   ((length($mhp->{p})-2) >= length($devHlpr->{AESreqAck}))
          && ($devHlpr->{AESreqAck} eq substr($mhp->{p}, -1 * length($devHlpr->{AESreqAck}))) ) {
        push @evtEt,[$mhp->{devH},1,"aesCommToDev:ok"];
      } 
      else {
        push @evtEt,[$mhp->{devH},1,"aesCommToDev:fail"];
      }
      delete $devHlpr->{AESreqAck};
    }

    if   ($mhp->{mStp} =~ m/^8/){#NACK
      #82 : peer not accepted - list full (VD)
      #84 : request undefined register
      #85 : peer not accepted - why? unknown
      
      my $lastMsg = "dummy";
      if($devHlpr->{cSnd}){
        $lastMsg = $devHlpr->{cSnd};
        $lastMsg =~ s/.*,// ;
      }
      if (defined $devHlpr->{prt}{tryMsg}{$lastMsg}){
        delete $devHlpr->{prt}{tryMsg}{$lastMsg};
        Log3 $mhp->{devH},2,"NACK for :$mhp->{mStp}: $lastMsg";
        CUL_HM_respPendToutProlong($mhp->{devH});
        $reply = "done";
      }
      else{
        $reply = "NACK";
        $success = "no";
        CUL_HM_eventP($mhp->{devH},"Nack");
      }
    }
    elsif($mhp->{mStp} eq "01"){ #ACKinfo#################
      $success = "yes";
      CUL_HM_m_setCh($mhp,substr($mhp->{p},2,2));
      push @evtEt,[$mhp->{cHash},0,"recentStateType:ack"];
      if (length($mhp->{p})>9){
        my $rssi = substr($mhp->{p},8,2);
        CUL_HM_storeRssi( $mhp->{devN}
                         ,$mhp->{dstN}
                         ,(-1)*(hex($rssi))
                         ,$mhp->{mNo})
              if ($rssi && $rssi ne '00' && $rssi ne'80');
      }
      $reply = "ACKStatus";
      if ($devHlpr->{tmdOn}){
        if ((not hex(substr($mhp->{p},6,2))&0x40) && # not timedOn, we have to repeat
            $devHlpr->{tmdOn} eq substr($mhp->{p},2,2) ){# virtual channels for dimmer may be incorrect
          my ($pre,$nbr,$msg) = unpack 'A4A2A*',$devHlpr->{prt}{rspWait}{cmd};
          $devHlpr->{prt}{rspWait}{cmd} = sprintf("%s%02X%s",
                                                    $pre,hex($nbr)+1,$msg);
          CUL_HM_eventP($mhp->{devH},"TimedOn");
          $success = "no";
          $repeat = 1;
          $reply = "NACK";
        }
      }
    }
    elsif($mhp->{mStp} eq "04"){ #ACK-AES, ###############
      my (undef,$challenge,$aesKeyNbr) = unpack'A2A12A2',$mhp->{p};
      push @evtEt,[$mhp->{devH},1,"aesKeyNbr:".$aesKeyNbr] if (defined $aesKeyNbr);# if   ($mh{msgStat} =~ m/AESKey/)

      if (AttrVal($mhp->{devH}{IODev}{NAME},"rfmode","") eq "HomeMatic" &&
          defined($aesKeyNbr)) {
        if ($mhp->{devH}->{IODev}{helper}{VTS_AES}) { #noansi: for TSCUL VTS0.14 up
          return "AES"; # noansi: TSCUL did it, now the normal ACK is expected
        }
        if ($cryptFunc == 1 &&                    #AES is available
          $devHlpr->{prt}{rspWait}{cmd}){       #There is a previously executed command
          my (undef, %keys) = CUL_HM_getKeys($mhp->{devH});
        
          my $kNo = hex($aesKeyNbr) / 2;
          Log3 $mhp->{devH},5,"CUL_HM $mhp->{devN} signing request for $devHlpr->{prt}{rspWait}{cmd} challenge: "
                        .$challenge." kNo: ".$kNo;
        
          if (!defined($keys{$kNo})) {
            Log3 $mhp->{devH},1,"CUL_HM $mhp->{devN} unknown key for index $kNo, define it in the VCCU!";
            $reply = "done";
          } 
          else {
            my $key = $keys{$kNo} ^ pack("H12", $challenge);
            my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_ECB());
            my($s,$us) = gettimeofday();
            my $respRaw = pack("NnH20", $s, $us, substr($devHlpr->{prt}{rspWait}{cmd}, 4, 20));
            my $response = $cipher->encrypt($respRaw);
            $devHlpr->{AESreqAck} = uc(unpack("H*", substr($response,0,4)));
            Log3 $mhp->{devH},5,"CUL_HM $mhp->{devN} signing response: ".unpack("H*", $respRaw)
                           ." should send $devHlpr->{AESreqAck} to authenticate";
            $response = $response ^ pack("H*", substr($devHlpr->{prt}{rspWait}{cmd}, 24));
            $response = $cipher->encrypt(substr($response, 0, 16));

            CUL_HM_SndCmd($mhp->{devH}, $mhp->{mNo}.$mhp->{mFlg}.'03'.CUL_HM_IoId($mhp->{devH}).$mhp->{src}.unpack("H*", $response));
            $reply = "AES";
            $repeat = 1;#prevent stop for messagenumber match
          }
        } 
        elsif ($cryptFunc != 1){                     #AES is not available
          Log3 $mhp->{devH},1,"CUL_HM $mhp->{devN} need Crypt::Rijndael to answer signing request with CUL";
          $reply = "done";
        } 
        else {
          $reply = 'AES'; #not expecting an AES answer
        }        
      }
      else {
        return "done";
      }
    }
    else{                    #ACK
      $success = "yes";
      $reply = "ACK";
    }
    if (defined $success && $success eq "yes"){# search if a trigger was accepted 
      if(defined($mhp->{dstH}) && $mhp->{dstH}{helper}{ack}{$mhp->{devN}}){
        my ($dChN,$mNo) = split(":",$mhp->{dstH}{helper}{ack}{$mhp->{devN}});
        my $rv = ReadingsVal($dChN,"triggerTo_$mhp->{devN}",undef);
        if ($mNo eq $mhp->{mNo} && $rv){
          push @evtEt,[$defs{$dChN},1,"triggerTo_$mhp->{devN}:${rv}_ack"];
        }
        delete $mhp->{dstH}{helper}{ack}{$mhp->{devN}};
      }
    }

    if (   $devHlpr->{prt}{mmcS}
        && $devHlpr->{prt}{mmcS} == 3){
      # after write device might need a break
      # allow for wake types only - and if commands are pending
      $devHlpr->{prt}{try} = 1 if(CUL_HM_getRxType($mhp->{devH}) & 0x08 #wakeup
                                         && $mhp->{devH}{cmdStack});
      if ($success eq 'yes'){
        delete $devHlpr->{prt}{mmcA};
        delete $devHlpr->{prt}{mmcS};
      }
    };

    if($success){#do we have a final ack?
      #mark timing on the channel, not the device
      my $chn = sprintf("%02X",hex(substr($mhp->{p},2,2))&0x3f);
      my $chnhash = $modules{CUL_HM}{defptr}{$chn?$mhp->{src}.$chn:$mhp->{src}};
      $chnhash = $mhp->{devH} if(!$chnhash);
      push @evtEt,[$chnhash,0,"CommandAccepted:$success"];
      CUL_HM_ProcessCmdStack($mhp->{devH}) if(CUL_HM_IoId($mhp->{devH}) eq $mhp->{dst});
      delete $devHlpr->{prt}{wuReSent}
              if ( !$devHlpr->{prt}{mmcS}
                  && $devHlpr->{prt}{rspWait}{cmd} 
                  && substr($devHlpr->{prt}{rspWait}{cmd},8,2) ne '12');
    }
    $ret = $reply;
  }
  elsif($mhp->{mTp} eq "03"){# AESack #############################
    #Reply to AESreq - only visible with CUL or in monitoring mode
    #not with HMLAN/USB
    #my $aesKey = $p;
    push @evtEt,[$mhp->{devH},1,"aesReqTo:".$mhp->{dstH}{NAME}] if (defined $mhp->{dstH});
    $ret = "done";
  }

  elsif($mhp->{mTp} eq "00"){######################################
    if ($devHlpr->{supp_Pair_Rep}){# repeated  # Change noansi, don`t let the user press pair button forever if first pair try failed
      $devHlpr->{supp_Pair_Rep} = 0; # noansi: reset flag, suppress only once not to lockup if device answer is not received
      return "done";  # suppress handling of a repeated pair request
    }
    $devHlpr->{supp_Pair_Rep} = 1; # noansi: suppress next handling of a repeated pair request (if nothing else arrives in between from device)

    my $paired = 0; #internal flag
    my $ioN = $ioHash->{NAME};
    # hmPair set in IOdev or  eventually in ccu!
    my $ioOwn  = InternalVal($ioN,"owner_CCU","");
    my $hmPair = InternalVal($ioN,"hmPair"      ,InternalVal($ioOwn,"hmPair"      ,0 ));
    my $hmPser = InternalVal($ioN,"hmPairSerial",InternalVal($ioOwn,"hmPairSerial",InternalVal($mhp->{devN},"hmPairSerial","")));
    
    Log3 $ioOwn,4,"CUL_HM received config CCU:$ioOwn device: $mhp->{devN}. PairForSec: ".($hmPair?"on":"off")." PairSerial: $hmPser";

    if ( $hmPair ){# pairing is active
      my $regser = ReadingsVal($mhp->{devN},"D-serialNr",AttrVal($mhp->{devN},'serialNr',''));
      if (!$hmPser || $hmPser eq $regser){
        CUL_HM_infoUpdtDevData($mhp->{devN}, $mhp->{devH}, $mhp->{p}, 1)
                  if (!$modules{CUL_HM}{helper}{hmManualOper});

        # pairing requested - shall we?      
        my $ioId = CUL_HM_h2IoId($ioHash);
        # pair now
        Log3 $ioOwn    ,3, "CUL_HM pair: $mhp->{devN} "
                      ."$attr{$mhp->{devN}}{subType}, "
                      ."model $attr{$mhp->{devN}}{model} "
                      ."serialNr ".$regser;
        CUL_HM_RemoveHMPair("hmPairForSec:$ioOwn:noReading");# just in case...
        CUL_HM_respPendRm($mhp->{devH}); # remove all pending messages
        delete $mhp->{devH}{cmdStack};
        delete $devHlpr->{prt}{rspWait};
        delete $mhp->{devH}{READINGS}{"RegL_00."};
        delete $mhp->{devH}{READINGS}{".RegL_00."};
        push @evtEt,[$defs{$ioOwn},1,"hmPair:name:$mhp->{devN} SN:".$regser." model:$attr{$mhp->{devN}}{model}"];
        if (!$modules{CUL_HM}{helper}{hmManualOper}){
          if($ioOwn){
            $attr{$mhp->{devN}}{IOgrp} = "$ioOwn:$ioHash->{NAME}";
          }
          else{
            $attr{$mhp->{devN}}{IODev} = $ioN;
          }
          CUL_HM_assignIO($mhp->{devH}) ;
        }

        my ($idstr, $s) = ($ioId, 0xA);
        $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;
        CUL_HM_pushConfig($mhp->{devH}, $ioId, $mhp->{src},0,0,0,0, "0201$idstr");
        
        $attr{$mhp->{devN}}{autoReadReg}= 
              AttrVal($mhp->{devN},"autoReadReg","4_reqStatus");
        CUL_HM_qAutoRead($mhp->{devN},0);
          # stack cmds if waiting. Do noch start if we have a burst device
          # it may not paire
        my $drxt = CUL_HM_getRxType($mhp->{devH});
        CUL_HM_appFromQ($mhp->{devN},'cf') if (!($drxt & 0x83) && ($drxt & 0x14)); #noansi: use fresh RxType, disallow burst and normal, allow config and lazyConfig
        
        $respRemoved = 1;#force command stack processing
        $paired = 1;
      }
    }
    if (!$paired) {
      CUL_HM_infoUpdtDevData($mhp->{devN}, $mhp->{devH}, $mhp->{p}, 0)
                if (!$modules{CUL_HM}{helper}{hmManualOper});
      if (CUL_HM_getRxType($mhp->{devH}) & 0x14) {#no pair -send config?
        CUL_HM_appFromQ($mhp->{devN},"cf") if (   !$mhp->{devH}->{cmdStack}
                                               || !scalar @{$mhp->{devH}->{cmdStack}}); # stack cmds if waiting and cmd stack empty, for pressing config button to continue in queue on config devices
        $respRemoved = 1;#force command stack processing
      }
    }

    $devHlpr->{HM_CMDNR} += 0x27;  # force new setting. Send will take care of module 255
    ### some lazy config devices send config as response to first message. We need to repeat our request by then. 
    CUL_HM_respPendTout("respPend:$mhp->{devH}{DEF}") if (defined $devHlpr->{prt}{rspWait});
    $ret = "done";
  }
  elsif($mhp->{mTp} eq "10"){######################################
    CUL_HM_m_setCh($mhp,substr($mhp->{p},2,2));
    Log3 $mhp->{devH},4,"mTp:$mhp->{mTp} wait:$pendType got mStp:$mhp->{mStp} mNo:".hex($mhp->{mNo})." :\n          "
             .join("\n          ",map{"$_:$rspWait->{$_}"}keys %{$rspWait});
    if(   $rspWait && $rspWait->{cmd} 
       && length($rspWait->{cmd})>10 
       && $devHlpr->{prt}{tryMsg}{substr($rspWait->{cmd},8)}){
      
      my $tryPid = substr($rspWait->{cmd},26,8); #CUL_HM_name2Id($rspWait->{forPeer});      
      delete $devHlpr->{prt}{tryMsg}{substr($rspWait->{cmd},8)};
      if( $rspWait->{Pending} eq "RegisterRead"){
        my $chName = CUL_HM_id2Name($mhp->{src}.$rspWait->{forChn});
        Log3 $mhp->{devH},3,"add peer by try message: $rspWait->{forPeer} to $chName";
        CUL_HM_ID2PeerList ($chName,$tryPid,1); # add the newly found
        CUL_HM_ID2PeerList ($chName,substr($tryPid,0,7)."x",0);# remove the placeholder. 
      }
    }
    if   ($mhp->{mStp} eq "00"){ #SerialRead====================================
      my $sn = pack("H*",substr($mhp->{p},2,20));
      push @evtEt,[$mhp->{devH},0,"D-serialNr:$sn"];
      $attr{$mhp->{devN}}{serialNr} = $sn;
      CUL_HM_respPendRm($mhp->{devH}) if ($pendType eq "SerialRead");
      $ret = "done";
    }
    elsif($mhp->{mStp} eq "01"){ #storePeerList=================================
      my $mNoWait = $rspWait->{mNo}; # hex($rspWait->{mNo}); 
      if ($pendType eq "PeerList"  && 
          ($mNoWait == $mNoInt || $mNoInt == ($mNoWait+1)%256)){ #noWait +1 modulo 256
        $rspWait->{mNo} = $mNoInt;
        $repeat = 1; #prevent stop for messagenumber match below, we match above
        my $chn = $devHlpr->{prt}{rspWait}{forChn};
        my $chnhash = $modules{CUL_HM}{defptr}{$mhp->{src}.$chn};
        $chnhash = $mhp->{devH} if (!$chnhash);
        my $chnName = $chnhash->{NAME};
        my @peers;
        if($mhp->{md} eq "HM-DIS-WM55"){
          #how ugly - this device adds one byte at begin - remove it. 
          (undef,@peers) = unpack 'A4(A8)*',$mhp->{p};
        }
        else{
          (undef,@peers) = unpack 'A2(A8)*',$mhp->{p};
        }

        if (scalar(@peers)) {
          $_ = '00000000' foreach (grep /^000000/ ,@peers);#correct bad term(6 chars) from rain sens)
          $_ .= '0x'      foreach (grep /^......$/,@peers);#if channel is unknown we assume at least a device
          $chnhash->{helper}{peerIDsRaw} .= ",".join(",",@peers);

          CUL_HM_ID2PeerList ($chnName,$_,1) foreach (@peers);
        }
        if (grep /00000000/,@peers) {# last entry, peerList is complete
          # check for request to get List3 data
          my $reqPeer = $chnhash->{helper}{getCfgList};
          my $readCont = 0;    # more to read?
          if ($reqPeer){
            my $flag = 'A0';
            my $ioId = CUL_HM_IoId($mhp->{devH});
            my @peerID = CUL_HM_getPeers($chnName,"IDs");
            foreach my $l (split ",",$chnhash->{helper}{getCfgListNo}){
              next if (!$l);
              my $listNo = "0".$l;
              foreach my $peer (@peerID){
                next if ($peer eq "peerUnread");
                if ($peer =~ m/0x$/){# if we face an incomplete peerID - bug in some devices. Search the correct peer
                  my %h;
                  $h{$_} = 1 foreach(map{substr(CUL_HM_name2Id($_)."00",0,8)} CUL_HM_getAssChnNames(CUL_HM_id2Name(substr($peer,0,6))));
                  delete $h{$_} foreach(@peerID) ;
                  my $pCnt = 0; # we will not try more than 10 peers. be devensive
                  foreach my $peerTest(sort keys %h){
                    Log3 $mhp->{devH},2,"got incomplete peer - try who we find . Test: $peerTest";
                    CUL_HM_PushCmdStack($mhp->{devH},sprintf("##%s01%s%s%s04%s%s",$flag,$ioId,$mhp->{src},$chn,$peerTest,$listNo));# List3 or 4
                    $devHlpr->{prt}{tryMsg}{sprintf("01%s%s%s04%s%s",$ioId,$mhp->{src},$chn,$peerTest,$listNo)} = 1;
                    last if (++$pCnt > 10);
                  }
                }
                else{
                  $peer .="01" if (length($peer) == 6); # add the default
                  if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
                    CUL_HM_PushCmdStack($mhp->{devH},sprintf("##%s01%s%s%s04%s%s",$flag,$ioId,$mhp->{src},$chn,$peer,$listNo));# List3 or 4
                    $readCont = 1;
                  }
                }
              }
            }
          }
          CUL_HM_respPendRm($mhp->{devH});
          delete $chnhash->{helper}{getCfgList};
          delete $chnhash->{helper}{getCfgListNo};
          CUL_HM_rmOldRegs($chnName,$readCont);
          $chnhash->{READINGS}{".peerListRDate"}{VAL} = $chnhash->{READINGS}{".peerListRDate"}{TIME} = $mhp->{tmStr};
          CUL_HM_cfgStateDelay($chnName);#schedule check when finished
          Log3 $mhp->{devH},5,'peerlist finished. cmds pending:'.scalar(@{$mhp->{devH}->{cmdStack}});
        }
        else{
          CUL_HM_respPendToutProlong($mhp->{devH});#wasn't last - reschedule timer
          Log3 $mhp->{devH},5,'waiting for Peerlist: msgNo:'.$rspWait->{mNo}.'+, rec:'.hex($mhp->{mNo});
        }
      }
      else {
        Log3 $mhp->{devH},4,'got unexpected PeerList, expected '.$pendType?$pendType.' ':''.'msgNo:'.$rspWait->{mNo}.'+, rec:'.hex($mhp->{mNo});
      }
      $ret = "done";
    }
    elsif($mhp->{mStp} eq "02" ||$mhp->{mStp} eq "03"){ #ParamResp==============
      my $mNoWait = $rspWait->{mNo}; 
      if (     $pendType eq "RegisterRead" 
          && !(defined($rspWait->{data}) && $rspWait->{data} eq $mhp->{p})# no device retry
          &&  ($mNoWait == $mNoInt || $mNoInt == ($mNoWait+1)%256)){      # noWait +1 modulo 256
        $rspWait->{data} = $mhp->{p}; # prevent timeout for device resends with mNo+2
        $rspWait->{mNo} = $mNoInt; # next message will be numbered same or one plus
        $repeat = 1;#prevent stop for messagenumber match
        CUL_HM_m_setCh($mhp,$rspWait->{forChn});
        my ($format,$data);
        ($format,$data) = ($1,$2) if ($mhp->{p} =~ m/^(..)(.*)/);
        my $list = $rspWait->{forList} ? $rspWait->{forList} : "00";#use the default
        my $peer = $rspWait->{forPeer};
        my $regLNp = "RegL_".$list.".".$peer;# pure, no expert
        my $regLN = ($mhp->{cHash}{helper}{expert}{raw}?"":".").$regLNp;
        delete $mhp->{cHash}{helper}{regCollect} if (     defined $mhp->{cHash}{helper}{regCollect} 
                                                      && !defined $mhp->{cHash}{helper}{regCollect}{$regLN});
        if    ($format eq "02"){ # list 2: format aa:dd aa:dd ...
          $data =~ s/(..)(..)/ $1:$2/g;
          foreach(split(" ",$data)){
            next if (!$_);
            my ($a,$d) = split(":",$_);
            $mhp->{cHash}{helper}{regCollect}{$regLN}{$a} = $d;
          }
        }
        elsif ($format eq "03"){ # list 3: format aa:dddd
          my $addr;
          ($addr,$data) = (hex($1),$2) if ($data =~ m/(..)(.*)/);
          if ($addr == 0){
            $mhp->{cHash}{helper}{regCollect}{$regLN}{'00'} = '00';
          }
          else{
            foreach my $d1 (unpack'(A2)*',$data){
              $mhp->{cHash}{helper}{regCollect}{$regLN}{sprintf("%02X",$addr++)} = $d1;
            }
          }
        }
        if (   defined $mhp->{cHash}{helper}{regCollect}{$regLN}{'00'}
            &&         $mhp->{cHash}{helper}{regCollect}{$regLN}{'00'} eq "00"){ # this was the last message in the block
          my $dat;
          $dat .= " $_:".$mhp->{cHash}{helper}{regCollect}{$regLN}{$_} foreach(sort(keys%{$mhp->{cHash}{helper}{regCollect}{$regLN}}));
          delete $mhp->{cHash}{helper}{regCollect}{$regLN};
          CUL_HM_UpdtReadSingle($mhp->{cHash},$regLN,$dat,0);
          if($list eq "00"){
            push @evtEt,[$mhp->{devH},0,"PairedTo:".CUL_HM_getRegFromStore($mhp->{devN},"pairCentral",0,"")];
          }
          CUL_HM_respPendRm($mhp->{devH});
          delete $mhp->{cHash}{helper}{shadowReg}{$regLNp};   #rm shadow
          # peerChannel name from/for user entry. <IDorName> <deviceID> <ioID>
          CUL_HM_updtRegDisp($mhp->{cHash},$list,CUL_HM_peerChId($peer,$mhp->{devH}{DEF}));
          Log3 $mhp->{devH},4,'reglist $regLN finished. cmds pending:'.scalar(@{$mhp->{devH}->{cmdStack}});
        }
        else{
          CUL_HM_respPendToutProlong($mhp->{devH});#wasn't last - reschedule timer
          Log3 $mhp->{devH},4,'waiting for Reglist $regLN  msgNo:'.$rspWait->{mNo}.'+, rec:'.hex($mhp->{mNo});
        }
      }
      else{
        if(   $pendType eq "RegisterRead"# frank: prevent timeout for device resends with mNo+2 or wrong destination
           && defined($rspWait->{data}) && $rspWait->{data} eq $mhp->{p}){
          Log3 $mhp->{devH},3,"device resend for $pendType => mTp:$mhp->{mTp} mStp:$mhp->{mStp} mNo:".hex($mhp->{mNo})." dst:$mhp->{dst} data:$mhp->{p}\n          "
                               .join("\n          ",map{"$_:$rspWait->{$_}"}keys %{$rspWait});
          $rspWait->{mNo} = $mNoInt; # next message will be numbered same or one plus
          $repeat = 1;#prevent stop for messagenumber match
          CUL_HM_respPendToutProlong($mhp->{devH});#wasn't last - reschedule timer
          if(   $mhp->{dst} ne CUL_HM_IoId($mhp->{devH})                     # wrong destination, frank: manage fw bug HM-CC-TC
             && $mhp->{devH}->{IODev}->{TYPE} !~ m/^(?:HMLAN|HMUARTLGW)$/s){ # only for cul io
            CUL_HM_SndCmd($mhp->{devH},"$mhp->{mNo}8002".CUL_HM_IoId($mhp->{devH})."$mhp->{src}00");
          }
        }
        else{
          Log3 $mhp->{devH},4,"waiting for: $pendType, got:RegisterRead # await msgNo:".(defined $rspWait->{mNo} ? $rspWait->{mNo} :"-no msgNo").", rec:$mNoInt";
        }
      }
      $ret = "done";
    }
    elsif($mhp->{mStp} eq "04" ||$mhp->{mStp} eq "05"){ #ParamChange============
                                        #m:1E A010 4CF663 1743BF 0500(00000000)(07)(00)  # finish
                                        #m:1E A010 4CF663 1743BF 0500(00000000)(07)(62)(2120212020EA36F643)
      my($mCh,$peerID,$list,$data) = ($1,$2,$3,$4) if($mhp->{p} =~ m/^0.(..)(........)(..)(.*)/);
      CUL_HM_m_setCh($mhp,$mCh);
      my $fch = CUL_HM_shC($mhp->{cHash},$list,$mhp->{chnHx});
      my $fHash = $modules{CUL_HM}{defptr}{$mhp->{src}.$fch};
      $fHash = $mhp->{devH} if (!$fHash);
      my $fName = $fHash->{NAME};
      my $peer = ($peerID ne "00000000") ? CUL_HM_peerChName($peerID,"000000") : "";
      
      if($data eq "00"){#update finished for mStp 05. Now update display
        CUL_HM_updtRegDisp($fHash,$list,$peerID);
      }
      else{
        my $regLNp = "RegL_".$list.".".$peer;
        $regLNp =~ s/broadcast//;
        $regLNp =~ s/ /_/g; #remove blanks
        my $regLN = ($mhp->{cHash}{helper}{expert}{raw}?"":".").$regLNp;
        my $rCur = ReadingsVal($fName,$regLN,"");
        
        if ($rCur){# if list not present we cannot update
          if ($mhp->{mStp} eq "05"){ # generate $data identical for 04 and 05
            $data = "";
            my ($addr,$data1);
            ($addr,$data1) = (hex($3),$4) if($mhp->{p} =~ m/^05..(........)(..)(..)(.*)/);
            foreach my $d1 ($data1 =~ m/.{2}/g){
              $data .= sprintf(" %02X:%s",$addr++,$d1);
            }
          }
          else{
            $data =~ s/(..)(..)/ $1:$2/g;
          }
        
          my $sdH = CUL_HM_shH($mhp->{cHash},$list,$mhp->{dst});
          my $shdwReg = $sdH->{helper}{shadowReg}{$regLNp};
          
          foreach my $entry (split(" ",$data)){
            next if (!$entry);
            my ($a,$d) = split(":",$entry);
            last if ($a eq "00");
            if ($rCur =~ m/$a:/){ $rCur =~ s/$a:../$a:$d/;}
            else               { $rCur .= " ".$entry;}
            $shdwReg =~ s/ $a:..// if ($shdwReg);# confirmed: remove from shadow
          }
          CUL_HM_UpdtReadSingle($fHash,$regLN,$rCur,0);
          if ($mhp->{mStp} eq "04"){
            CUL_HM_updtRegDisp($fHash,$list,$peerID);
          }
        }
      }
      $ret= "parsed"; # send ACK 
    }    
    elsif($mhp->{mStp} eq "06"){ #reply to status request=======================
      my $rssi = substr($mhp->{p},8,2);

      push @evtEt,[$mhp->{cHash},0,"recentStateType:info"];
      CUL_HM_storeRssi( $mhp->{devN}
                       ,$mhp->{dstN}
                       ,(-1)*(hex($rssi))
                       ,$mhp->{mNo})
            if ($rssi && $rssi ne '00' && $rssi ne'80');
      CUL_HM_unQEntity($mhp->{cName},"qReqStat");
      if ($pendType eq "StatusReq"){#it is the answer to our request
        CUL_HM_respPendRm($mhp->{devH});
        $ret = "STATresp";
      }
      else{
        if ($mhp->{chn} == 0
            || (   $mhp->{chn} == 1 
                && $devHlpr->{PONtest})){# this is power on
          CUL_HM_qStateUpdatIfEnab($mhp->{devN});
          CUL_HM_qAutoRead($mhp->{devN},2);
          $ret = "powerOn" ;# check dst eq "000000" as well?
          $devHlpr->{PONtest} = 0;
        }
      }
    }
  }
  elsif($mhp->{mTp} eq "12"){ #wakeup received - ignore############
    $ret = "done";
  }
  elsif($mhp->{mTp} =~ m/^4[01]/){ #someone is triggered##########
    CUL_HM_m_setCh($mhp,substr($mhp->{p},0,2));
    my $cnt = hex(substr($mhp->{p},2,2));
    my $long = ($mhp->{chnraw} & 0x40)?"long":"short";
    my $level = "-";
    if (length($mhp->{p})>5){
      my $l = substr($mhp->{p},4,2);
      if    ($mhp->{cHash}{helper}{lm} && $mhp->{cHash}{helper}{lm}{hex($l)}){$level = $mhp->{cHash}{helper}{lm}{hex($l)}}
      elsif ($lvlStr{md}{$mhp->{md}}     && $lvlStr{md}{$mhp->{md}}{$l}    ){$level = $lvlStr{md}{$mhp->{md}}{$l}}
      elsif ($lvlStr{st}{$mhp->{st}}     && $lvlStr{st}{$mhp->{st}}{$l}    ){$level = $lvlStr{st}{$mhp->{st}}{$l}}
      else                                                    {$level = hex($l)};
    }
    elsif($mhp->{mTp} eq "40"){
      $level = $long;
      my $state = ucfirst($long);

      if(!defined $mhp->{cHash}{helper}{BNO} || $mhp->{cHash}{helper}{BNO} ne $cnt){#cnt = event counter
        $mhp->{cHash}{helper}{BNO}    = $cnt;
        $mhp->{cHash}{helper}{BNOCNT} = 0; # message counter reset
      }
      if (($mhp->{mFlgH} & 0x24) == 0x20 && ($long eq "long")){  # release long press
        $state .=  "Release";
      }
      else{                                                     # continue long press
        $mhp->{cHash}{helper}{BNOCNT} += 1;
      }
      $state .= " $mhp->{cHash}{helper}{BNOCNT}_$cnt";

      push @evtEt,[$mhp->{cHash},1,"trigger:".(ucfirst($long))."_$cnt"];
      push @evtEt,[$mhp->{cHash},1,"state:".$state." (to $mhp->{dstN})"] if ($mhp->{devH} ne $mhp->{cHash});
      if(   $mhp->{mFlgH} & 0x20
         && $mhp->{dst} ne "000000" 
#         && $mhp->{dst} ne $mhp->{id}
         ){
        push @evtEt,[$mhp->{cHash},1,"triggerTo_$mhp->{dstN}:".(ucfirst($long))."_$cnt"];
        $devHlpr->{ack}{$mhp->{dstN}} = "$mhp->{cName}:$mhp->{mNo}";
      }
    }
    push @evtEt,[$mhp->{cHash},1,"trigger_cnt:$cnt"];

    my $peersFound = 0;
    foreach my $pName (CUL_HM_getPeers($mhp->{cName},"Name:$mhp->{dst}")){
      next if (!$pName || !$defs{$pName});
      push @evtEt,[$defs{$pName},1,"trig_$mhp->{cName}:".(ucfirst($level))."_$cnt"];
      push @evtEt,[$defs{$pName},1,"trigLast:$mhp->{cName}".(($level ne "-")?":$level":"")];

      CUL_HM_stateUpdatDly($pName,10) if ($mhp->{mTp} eq "40");#conditional request may not deliver state-req
      $peersFound = 1;
    }
    if(!$peersFound
          && ($mhp->{mFlgH} & 2) # dst can be garbage - but not if answer request
          && (  !$mhp->{dstH} 
              || $mhp->{dst} ne CUL_HM_IoId($mhp->{dstH}))
          ){
      my $pName = CUL_HM_id2Name($mhp->{dst});
      push @evtEt,[$mhp->{cHash},1,"trigDst_$pName:noConfig"];
    }
    return "";
  }
  elsif($mhp->{mTp} eq "70"){ #Time to trigger TC##################
    #send wakeup and process command stack
  }
  if (defined($rspWait->{mNo})            &&
      $rspWait->{mNo} == hex($mhp->{mNo}) &&
      !$repeat){
    #response we waited for - stop Waiting
    CUL_HM_respPendRm($mhp->{devH});
  }

  return $ret;
}
sub CUL_HM_m_setCh($$){### add channel identification to Message Hash
  my ($mhp,$chn) = @_;
  $mhp->{chnM}  = $chn;
  $mhp->{chnraw}= hex($mhp->{chnM});
  $mhp->{chn}   = $mhp->{chnraw} & 0x3f;
  $mhp->{chnHx} = sprintf("%02X",$mhp->{chn});
  $mhp->{cHash} = CUL_HM_id2Hash($mhp->{src}.$mhp->{chnHx});
  $mhp->{cHash} = $mhp->{shash} if (!$mhp->{cHash});
  $mhp->{cName} = $mhp->{cHash}{NAME};
}

sub CUL_HM_queueUpdtCfg($){
  my $name = shift;
  if ($modules{CUL_HM}{helper}{hmManualOper}){ # no update when manual operation
    delete $modules{CUL_HM}{helper}{updtCfgLst};
  }
  else{
    my @arr;
    if ($modules{CUL_HM}{helper}{updtCfgLst}){
      @arr = CUL_HM_noDup((@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name));
    }
    else{
      push @arr,$name;
    }
    $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
  }
  RemoveInternalTimer("updateConfig");
  InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
}
sub CUL_HM_parseSDteam(@){#handle SD team events
  my ($mTp,$sId,$dId,$p) = @_;
  
  my @entities;
  my $dHash = CUL_HM_id2Hash($dId);
  my $dName = CUL_HM_id2Name($dId);
  my $sHash = CUL_HM_id2Hash($sId);
  my $sName = CUL_HM_hash2Name($sHash);
  if (AttrVal($sName,"subType","") eq "virtual"){
    foreach my $cId (CUL_HM_getAssChnIds($sName)){
      my $cHash = CUL_HM_id2Hash($cId);
      next if (!$cHash->{sdTeam} || $cHash->{sdTeam} ne "sdLead");
      my $cName = CUL_HM_id2Name($cId);
      $sHash = $cHash;
      $sName = CUL_HM_id2Name($cId);
      last;
    }
  }
  return () if (!$sHash->{sdTeam} || $sHash->{sdTeam} ne "sdLead");

  if ($mTp eq "40"){ #test
    my $trgCnt = hex(substr($p,2,2));
    my $err = hex(substr($p,0,2));
    push @evtEt,[$sHash,1,"teamCall:from $dName:$trgCnt"];
    push @evtEt,[$dHash,1,"battery:"   .(($err&0x80) ? "low":"ok")] if (defined($dHash) && !$dHash->{helper}{role}{vrt});
    foreach (keys %{$sHash->{helper}{peerIDsH}}){
      my $tHash = CUL_HM_id2Hash($_);
      push @evtEt,[$tHash,1,"teamCall:from $dName:$trgCnt"];
    }
  }
  elsif ($mTp eq "41"){ #Alarm detected
    #C8: Smoke Alarm
    #C7: tone off
    #01: no alarm
    my (undef,$No,$state) = unpack 'A2A2A2',$p;
    if(($dHash) && # update source(ID reported in $dst)
       (!$dHash->{helper}{alarmNo} || $dHash->{helper}{alarmNo} ne $No)){
      $dHash->{helper}{alarmNo} = $No;
    }

    my ($sVal,$sProsa,$smokeSrc) = (hex($state),"off","none");
    if ($sVal > 1){
      $sProsa = "smoke-Alarm_".$No;
      $smokeSrc = $dName;
    }
    return if($sProsa eq ReadingsVal($sHash->{NAME},"state",""));
    
    push @evtEt,[$sHash,1,"recentAlarm:$smokeSrc"] if($sVal == 200);
    push @evtEt,[$sHash,1,"state:$sProsa"];
    push @evtEt,[$sHash,1,'level:'.$sVal];
    push @evtEt,[$sHash,1,"eventNo:".$No];
    push @evtEt,[$sHash,1,"smoke_detect:".$smokeSrc];

    foreach (keys %{$sHash->{helper}{peerIDsH}}){
      my $tHash = CUL_HM_id2Hash($_);
      push @evtEt,[$tHash,1,"state:$sProsa"];
      push @evtEt,[$tHash,1,"smoke_detect:$smokeSrc"];
    }
  }
  return @entities;
}
sub CUL_HM_parseSDteam_2(@){#handle SD team events
  my ($mTp,$sId,$dId,$p) = @_;
  
  my $dHash = CUL_HM_id2Hash($dId);
  my $dName = CUL_HM_id2Name($dId);
  my $sHash = CUL_HM_id2Hash($sId);
  my $sName = CUL_HM_hash2Name($sHash);
  
  if (AttrVal($sName,"subType","") eq "virtual"){#search for the team lead channel
    foreach my $cId (CUL_HM_getAssChnIds($sName)){
      my $cHash = CUL_HM_id2Hash($cId);
      next if (!$cHash->{sdTeam} || $cHash->{sdTeam} ne "sdLead");
      $sHash = $cHash;
      $sName = CUL_HM_hash2Name($sHash);
      last;
    }
  }
  return () if (!$sHash->{sdTeam} || $sHash->{sdTeam} ne "sdLead"
              ||!$dHash);
  my ($chn,$No,$state,$null,$aesKNo,$aesStr) = unpack 'A2A2A2A4A2A8',$p;
  if(!$dHash->{helper}{alarmNo} || $dHash->{helper}{alarmNo} ne $No){
    $dHash->{helper}{alarmNo} = $No;
  }
  else{
    return ();# duplicate alarm
  }
  my ($sVal,$sProsa,$smokeSrc) = (hex($state),"off","none");
  my @tHash = ((map{CUL_HM_id2Hash($_)} grep !/00000000/, keys %{$sHash->{helper}{peerIDsH}})
               ,$sHash);
  
  if ($sVal > 179 ||$sVal <51 ){# need to raise alarm
    if ($sVal > 179){# need to raise alarm
      #"SHORT_COND_VALUE_LO" value="50"/>
      #"SHORT_COND_VALUE_HI" value="180"/>
      $sProsa = "smoke-Alarm_".$No;
      $smokeSrc = $dName;
      push @evtEt,[$sHash,1,"recentAlarm:$smokeSrc"] if($sVal == 200);
    }
    elsif($sVal <51){#alarm inactive
      #$sProsa = "off_".$No;
      #$smokeSrc = $dName;
    }
    push @evtEt,[$sHash,1,'level:'.$sVal];
  }
  elsif($sVal == 150){#alarm teamcall
    foreach (@tHash){
      next if (!$_);
      push @evtEt,[$_,1,"teamCall:from $dName:$No"];
    }
  }
  elsif($sVal == 151){#alarm teamcall repeat
    push @evtEt,[$dHash,1,"MsgRepeated $No"];#unclear. first repeater send 97 instead of 96. What about 2nd ans third repeater?
  }
  foreach (@tHash){
    next if (!$_);
    push @evtEt,[$_,1,"state:$sProsa"];
    push @evtEt,[$_,1,"smoke_detect:$smokeSrc"];
  }
  push @evtEt,[$dHash,1,"battery:"   .((hex($chn)&0x80) ? "low":"ok")] if (!$dHash->{helper}{role}{vrt});
  push @evtEt,[$sHash,1,"eventNo:".$No];
  Log3 $sHash,5,"CUL_HM $sName sdTeam: no:$No state:$state aesNo:$aesKNo aesStr:$aesStr";
  
  return;
}
sub CUL_HM_updtSDTeam(@){#in: TeamName, optional caller name and its new state
  # update team status if virtual team lead
  # check all member state
  # prio: 1:alarm, 2: unknown, 3: off
  # sState given in input may not yet be visible in readings
  my ($name,$sName,$sState) = @_;
  return undef if (!$defs{$name} || AttrVal($name,"model","") !~ m "VIRTUAL");
  ($sName,$sState) = ("","") if (!$sName || !$sState);
  return undef if (ReadingsVal($name,"state","off") =~ m/smoke-Alarm/);
  my $dStat = "off";
  foreach my $pId(CUL_HM_getPeers($name,"IDs")){#screen teamIDs for Alarm  
    my $pNam = CUL_HM_id2Name(substr($pId,0,6));
    next if (!$pNam ||!$defs{$pNam});
    my $pStat = ($pNam eq $sName)
                  ?$sState
                  :ReadingsVal($pNam,"state",undef);
    if    (!$pStat)         {$dStat = "unknown";}
    elsif ($pStat ne "off") {$dStat = $pStat;last;}
  }
  return CUL_HM_UpdtReadSingle($defs{$name},"state",$dStat,1);
}
sub CUL_HM_pushEvnts(){########################################################
  #write events to Readings and collect touched devices
  my @ent = ();
  $evtDly = 0;# switch delay trigger off
  if (scalar(@evtEt) > 0){
    @evtEt = sort {($a->[0] cmp $b->[0])|| ($a->[1] cmp $b->[1])} @evtEt;
    my ($h,$x) = ("","");
    my @evts = ();
    foreach my $e(@evtEt){
      if(scalar(@{$e} != 3)){
        Log 2,"CUL_HM set reading invalid:".join(",",@{$e});
        next;
      }
      if ($h ne ${$e}[0] || $x ne ${$e}[1]){
        push @ent,CUL_HM_UpdtReadBulk($h,$x,@evts);
        @evts = ();
        ($h,$x) = (${$e}[0],${$e}[1]);
      }
      push @evts,${$e}[2] if (${$e}[2]);
    }
    @evtEt = ();
    push @ent,CUL_HM_UpdtReadBulk($h,$x,@evts);
  }

  return @ent;
}

sub CUL_HM_Get($@) {#+++++++++++++++++ get command+++++++++++++++++++++++++++++
  my ($hash, @a) = @_;
  return "no value specified" if(@a < 2);
  return "" if(!$hash->{NAME});

  my $name = $hash->{NAME};
#  return ""
#        if (CUL_HM_getAttrInt($name,"ignore"));

  my $devName = InternalVal($name,"device",$name);
  my $st      = defined $defs{$devName}{helper}{mId} ? $culHmModel->{$defs{$devName}{helper}{mId}}{st}   : AttrVal($devName, "subType", "");
  my $md      = CUL_HM_getAliasModel($hash);

  my $cmd   = $a[1];
  
  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;
  my $fkt   = $hash->{helper}{fkt}?$hash->{helper}{fkt}:"";

  my ($dst,$chn) = unpack 'A6A2',$hash->{DEF}.($roleC?'01':'00');

  CUL_HM_SetList($name               # refresh command options
                 ,  "$roleC"
                  .":$roleD"
                  .":$roleV"
                  .":$fkt"
                  .":$devName"
                  .":".($defs{$devName}{helper}{mId} ? $defs{$devName}{helper}{mId}:"")
                  .":$chn"
                  .":".InternalVal($name,"peerList","")
                 );# update cmds entry in case
  


  if(!defined $hash->{helper}{cmds}{rtrvLst}{$cmd}) { ### unknown - return the commandlist
    my @cmdPrep = ();
    foreach my $cmdS (keys%{$hash->{helper}{cmds}{rtrvLst}}){
      my $val = $hash->{helper}{cmds}{rtrvLst}{$cmdS};
      if($val eq "noArg"){
          $val = ":$val";
      }
      elsif($val =~ m/^(\[?)-([a-zA-Z]*?)-\]? *$/){#add relacements if available
        my ($null,$repl) = ($1,$2);
        if (defined $hash->{helper}{cmds}{lst}{$repl}){
          $null = $null ? "noArg," : ""; # if "optional" add "noArg" to optionList
          $val =~ s/\[?-$repl-\]?/:$null$hash->{helper}{cmds}{lst}{$repl}/; 
          next if ($hash->{helper}{cmds}{lst}{$repl} eq "");# no options - no command
        }
        else{
          $val = "";
        }
      }
      elsif($val =~ m/^[\(\[]*([-+a-zA-Z0-9_|\.\{\}]*)[\]\)]*$/){#(xxx|yyy) as optionlist - new
        my $v1 = $1;
        $v1 =~ s/[\{\}]//g;#remove default marking
        my @lst1;
        foreach(split('\|',$v1)){
          if ($_ =~ m/(.*)\.\.(.*)/ ){
            my @list = map { ($_.".0", $_+0.5) } (($1+0)..($2+0));
            pop @list;
            push @lst1,@list;
          }
          else{
            push @lst1,$_;
          }     
        }
        $val = ":".join(",",@lst1);
      }
      else      {
        $val = "";
      }
      push @cmdPrep,"$cmdS$val";
    }
    @cmdPrep = ("--") if (!scalar @cmdPrep);
    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @cmdPrep)." ";
    Log3 $name,(defined $modules{CUL_HM}{helper}{verbose}{allGetVerb} ? 0:5),"CUL_HM get $name $cmd";
    return $usg;
  }

  my $paraOpts = $hash->{helper}{cmds}{rtrvLst}{$cmd};
  if($paraOpts eq "noArg"){ # no argument allowed
     return "$cmd no params required" if(@a != 2);
  }
  elsif(@a == 2){# no arguments - is this ok?
    if($paraOpts !~ m/\.\.\./ && $paraOpts !~ m/^\[.*?\] *$/ ){# argument required
      return "$cmd parameter required:$paraOpts";  
    }
    else{
      push @a,"noArg";
    }
  }

  my $devHash = CUL_HM_getDeviceHash($hash);
  Log3 $name,(defined $modules{CUL_HM}{helper}{verbose}{allGet} ? 0:4),"CUL_HM get $name " . join(" ", @a[1..$#a]);
  #----------- now start processing --------------
  if   ($cmd eq "param") {  ###################################################
    my $p = $a[2];
    return $attr{$name}{$p}              if ($attr{$name}{$p});
    return $hash->{READINGS}{$p}{VAL}    if ($hash->{READINGS}{$p});
    return $hash->{READINGS}{".$p"}{VAL} if ($hash->{READINGS}{".$p"});
    return $hash->{$p}                   if ($hash->{$p});
    return $hash->{helper}{$p}           if ($hash->{helper}{$p} && ref($hash->{helper}{$p}) ne "HASH");
    
    return $attr{$devName}{$p}           if ($attr{$devName}{$p});
    return "undefined";
  }
  elsif($cmd =~ m/^(reg|regVal)$/) {  #########################################
    my (undef,undef,$regReq,$list,$peerId) = (@a,0,0);

    if (!defined $regReq or $regReq eq 'all'){
      my @regArr = CUL_HM_getRegN($st,$md,($roleD?"00":""),($roleC?$chn:""));

      my @peers; # get all peers we have a reglist
      my @listWp; # list that require peers
      foreach my $readEntry (keys %{$hash->{READINGS}}){
        if ($readEntry =~ m/^[\.]?RegL_(.*)/){ #reg Reading "RegL_<list>:peerN
          my $peer = substr($1,3);
          next if (!$peer); 
          push(@peers,$peer);
          push(@listWp,substr($1,1,1));
        }
      }
      @listWp = CUL_HM_noDup(@listWp);
      my @regValList; #storage of results
      my $regHeader = "list:peer\tregister         :value\n";
      foreach my $regName (@regArr){
        my $regL  = $culHmRegDefine->{$regName}->{l};
        my @peerExe = (grep (/$regL/,@listWp)) ? @peers : ("00000000");
        @peerExe = CUL_HM_noDup(@peerExe);
        foreach my $peer(@peerExe){
          next if($peer eq "");
          my $regVal= CUL_HM_getRegFromStore($name,$regName,0,CUL_HM_name2Id($peer,$hash));#determine
          my $peerN = CUL_HM_id2Name($peer);
          $peerN = "      " if ($peer  eq "00000000");
          push @regValList,sprintf("   %d:%s\t%-16s :%s\n",
                  $regL,$peerN,$regName,$regVal)
                if ($regVal !~ m/invalid/);
        }
      }
      my $addInfo = "";
      if    ($md =~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/ && $chn eq "02")
                                                    {$addInfo = CUL_HM_TCtempReadings($hash)}
      elsif ($md =~ m/^HM-CC-RT-DN/ && $chn eq "04"){$addInfo = CUL_HM_TCITRTtempReadings($hash,$md,7)}
      elsif ($md =~ m/^HM-TC-IT/    && $chn eq "02"){$addInfo = CUL_HM_TCITRTtempReadings($hash,$md,7,8,9)}
      elsif (ReadingsVal($name,".RegL_01.",ReadingsVal($name,"RegL_01.","")) =~ m / 36:/){#add text
                                                    $addInfo = CUL_HM_4DisText($hash)}
      elsif ($md eq "HM-SYS-SRP-PL")                {$addInfo = CUL_HM_repReadings($hash)}

      return $name." type:".$st." - \n".
             $regHeader.join("",sort(@regValList)).
             $addInfo;
    }
    else{
      my $regVal = CUL_HM_getRegFromStore($name,$regReq,$list,$peerId);
      $regVal =~ s/ .*// if ($cmd eq "regVal");
      return ($regVal =~ m/^invalid/)? "Value not captured:$name - $regReq"
                                     : $regVal;
    }
  }
  elsif($cmd eq "regTable") {  ################################################
    return 'not supported w/o HMinfo' if !defined &HMinfo_GetFn;                                                                
    return HMinfo_GetFn($hash,$name,"register","-f","\^".$name."\$");
  }
  elsif($cmd eq "regList") {  #################################################
    return CUL_HM_getRegInfo($name) ;
  }
  elsif($cmd eq "cmdList") {  #################################################
    my $long = (defined $a[2] && $a[2] eq "long" ? 1 : 0);
    
    my   @arr;

    if(!$roleV) {push @arr,"$_ $culHmGlobalGets->{$_}"    foreach (keys %{$culHmGlobalGets}   )};
    if($roleV)  {push @arr,"$_ $culHmVrtGets->{$_}"       foreach (keys %{$culHmVrtGets}      )};

    if($roleD)  {push @arr,"$_ $culHmGlobalGetsDev->{$_}" foreach (keys %{$culHmGlobalGetsDev})};

    push @arr,"$_ $culHmSubTypeGets->{$st}{$_}" foreach (keys %{$culHmSubTypeGets->{$st}});
    push @arr,"$_ $culHmModelGets->{$md}{$_}"   foreach (keys %{$culHmModelGets->{$md}});

    my $info .= " Gets ------\n";
    $info .= join("\n",sort @arr);
    $info .= "\n\n Sets ------\n";
    $hash->{helper}{cmds}{TmplTs}=gettimeofday();# force re-arrange of template commands
    $hash->{helper}{cmds}{cmdKey}=""; 

    CUL_HM_SetList($name
                   ,  "$roleC"
                    .":$roleD"
                    .":$roleV"
                    .":$fkt"
                    .":$devName"
                    .":".($defs{$devName}{helper}{mId} ? $defs{$devName}{helper}{mId}:"")
                    .":$chn"
                    .":".InternalVal($name,"peerList","")
                   );
    $info .= join("\n",map{"$_:".$hash->{helper}{cmds}{cmdLst}{$_}} sort (keys%{$hash->{helper}{cmds}{cmdLst}}));

    if ($long){
      $info .= "\n Options:";
      foreach my $opt (sort keys %{$hash->{helper}{cmds}{lst}}){
        $info .= "\n -${opt}- : ";
        my @vals = sort split (',',$hash->{helper}{cmds}{lst}{$opt});
        
        for (my $val=0; $val < scalar(@vals);$val++){
          $info .= sprintf("\t%-15s,",$vals[$val]);
          $info .= "\n         " if (($val + 1) % 5 == 0);
        }
      }
      $info = "command syntax:"
            ."\n"."[optional]         : optional = the parameter is optional"
            ."\n"."(valX|valY)        : list     = one value valX or valY must be given"
            ."\n"."[(valX|{valY})]    : default  = one value valX or valY CAN be given. If non is given it defaults to valY"
            ."\n"."-peer-             : other    = the name of a peer needs to be given"
            ."\n"."[(-peer-|{self01})]: default  = a peername can be given. If emty the command will use 'self01'"
            ."\n".""
            ."\n".""
           .$info;
    }
    return $info;
  }
  elsif($cmd eq "tplInfo"){  ##################################################
    my $info;
    my @tplCmd = split(" ",CUL_HM_TmplSetCmd($name));
    my %tplH;
    my %tplTyp = (dev  =>"device templates"
                 ,ls   =>"templates for peerings serving short OR long press"
                 ,both =>"templates for peerings serving short AND long press"
    );
    foreach my $tplSet (split(" ",CUL_HM_TmplSetCmd($name))){
      my ($tplDst,$tplOpt) = split(":",$tplSet);
      my @tplLst = sort split(",",$tplOpt);
      if ($tplDst eq "tplSet_0"){#none peer template
        @{$tplH{dev}} = @tplLst;
      }
      else{
        @{$tplH{both}} = grep!/(.*)_(short|long)/,@tplLst;
        @{$tplH{ls}}   = map{(my $foo = $_) =~ s/_(short|long)//; $foo;}
                         grep/(.*)_(short|long)/,@tplLst;
      }
    }
    foreach my $tt (sort keys %tplTyp){
      if (defined $tplH{$tt}){
        $info .= "\n$tplTyp{$tt}:";
        foreach (@{$tplH{$tt}}){
          my ($r)=split("\n",HMinfo_templateList($_));
          $info .= "\n   ".$r;
        }
      }
    }
    return $info;
  }
  elsif($cmd eq "saveConfig"){  ###############################################
    return "no filename given" if (!$a[2]);
    my $fName = $a[2];
    open(aSave, ">>$fName") || return("Can't open $fName: $!");
    my $sName;
    my @eNames;
    if ($a[3] && $a[3] eq "strict"){
      @eNames = ($name);
      $sName =  $name;
    }
    else{
      $sName = $devName;
      @eNames = CUL_HM_getAssChnNames($sName);
    }
    print aSave "\n\n#======== store device data:".$sName." === from: ".TimeNow();
    foreach my $eName (@eNames){
      print aSave "\n#---      entity:".$eName;
      foreach my $rName ("D-firmware","D-serialNr",".D-devInfo",".D-stc"){
        my $rVal = ReadingsVal($eName,$rName,undef);        
        print aSave "\nsetreading $eName $rName $rVal" if (defined $rVal);
      }
      my $pIds = AttrVal($eName, "peerIDs", "");
      my $timestamps = "\n#     timestamp of the readings for reference";
      if ($pIds){
        print aSave "\n# Peer Names:"
                    .InternalVal($eName,"peerList","");
        $timestamps .= "\n#        "
                      .InternalVal($eName,"peerList","")
                      ." :peerList";
        print aSave "\nset $eName peerBulk $pIds#"
                   .ReadingsTimestamp($eName,"peerList","1900-01-01 00:00:01");
      } 
      my $ehash = $defs{$eName};
      foreach my $read (sort grep(/^[\.]?RegL_/,keys %{$ehash->{READINGS}})){
        my $ts = ReadingsTimestamp($eName,$read,"1900-01-01 00:00:01");
        print aSave "\nset $eName regBulk $read"
                   ." ".ReadingsVal($eName,$read,"")
                   ." #$ts";
        $timestamps .= "\n#        $ts :$read";
      }
      print aSave $timestamps;
    }
    print aSave "\n======= finished ===\n";
    close(aSave);
  }
  elsif($cmd eq "listDevice"){  ###############################################
    if    ($md eq "CCU-FHEM"){
      my @dl = grep !/^$/,
               map{AttrVal($_,"IOgrp","") =~ m/^$name/ ? $_ : ""}
               keys %defs;
      my @rl;
      foreach (@dl){
        next if IsIgnored($_) || IsDummy($_);
        my(undef,$pref) = split":",$attr{$_}{IOgrp},2;
        $pref =  "---" if (!$pref);
        my $IODev = $defs{$_}{IODev}->{NAME}?$defs{$_}{IODev}->{NAME}:"---";
        push @rl, "$IODev / $pref $_ ";
      }
      return "devices using $name\ncurrent IO / preferred\n  ".join "\n  ", sort @rl;
    } 
    elsif ($md eq "ACTIONDETECTOR"){
      my $re = $a[2]?$a[2]:"all";
      if($re && $re =~ m/^(all|alive|unknown|dead|notAlive)$/){
        my @fnd = map {$_.":".$defs{$name}{READINGS}{$_}{VAL}}
                  grep /^status_/,
                  keys %{$defs{ActionDetector}{READINGS}};
        if    ($re eq "notAlive"){ @fnd = grep !/:alive$/,@fnd; }
        elsif ($re eq "all")     {;        }
        else                     { @fnd = grep /:$a[2]$/,@fnd;}
        $_ =~ s/status_(.*):.*/$1/ foreach(@fnd);
        push @fnd,"empty" if (!scalar(@fnd));
        return  join",",sort(@fnd);
      } else{
        return "please enter parameter [alive|unknown|dead|notAlive]";
      }
    }
  }
  elsif($cmd eq "status"){  ###################################################
    return CUL_HM_ActInfo();
  }
  elsif($cmd eq "deviceInfo"){  ###############################################
    my $infoTypeLong = (!defined $a[2] || $a[2] ne 'long')?0:1 ;
    my $orgMId = AttrVal($devName,".mId","");
    my $FrcMd  = AttrVal($devName,"modelForce","");
    my $actMId = $defs{$devName}{helper}{mId}; # active mId
    my $act = ReadingsVal($devName,"Activity","-");
    my $ret =   " Device name:".$devName;
    if($infoTypeLong){
      $ret   .= "\n   org ID   \t:".$orgMId                       ."  Model=".$culHmModel->{$orgMId}{name};
      $ret   .= "\n   forced   \t:".CUL_HM_getmIdFromModel($FrcMd)."  Model=".$FrcMd                        if($FrcMd  ne "");
      $ret   .= "\n   alias ID \t:".$actMId                       ."  Model=".$culHmModel->{$actMId}{alias} if($orgMId ne $devName);
    }
    else{
      $ret   .= "\n   mId      \t:".CUL_HM_getmIdFromModel($md)."  Model=$md";
    }
    
    { my $mode = $culHmModel->{$defs{$devName}{helper}{mId}}{rxt};
      $mode =~ s/\bc\b/config/;
      $mode =~ s/\bw\b/wakeup/;
      $mode =~ s/\bb\b/burst/;
      $mode =~ s/\b3\b/3Burst/;
      $mode =~ s/\bl\b/lazyConf/;
      $mode =~ s/\bf\b/burstCond/;
      $mode =~ s/:/,/g;
      $mode = "normal" if (!$mode);
      
      $ret   .= "\n   mode   \t:".$mode;
    }

    if(!$roleV){
      $ret   .= " - activity:".$act if ($act ne "-");
      $ret   .= "\n   protState\t: "     .ReadingsVal($devName,"commState"  ,"unknown");
      $ret   .= " pending: ".InternalVal($devName,"protCmdPend","none"   );
      $ret   .= "\n";
    }
    if ($infoTypeLong){
      foreach (grep(/^channel_/,sort keys %{$defs{$devName}})){
        $ret .= "\n   "     .$defs{$devName}{$_}."\t state:".InternalVal($defs{$devName}{$_},"STATE","unknown");
      }
    }

    my $cfgState = ReadingsVal($name,"cfgState","unknown");
    $ret .= "\n configuration check: $cfgState";
    if ($cfgState =~ m/(unknown|ok)/){
    }
    else{
      foreach(sort keys %{$hash->{helper}{cfgChk}}){
        my( $Fkt,$shtxt,$txt) = HMinfo_getTxt2Check($_);
        $ret .= "\n   $shtxt: $txt";
        $ret .= "\n      =>$_" foreach(split("\n",$hash->{helper}{cfgChk}{$_}));
      }
    }
    return $ret;
  }
  elsif($cmd eq "list"){  #####################################################
    my $globAttr = AttrVal("global","showInternalValues","undef");
    $attr{global}{showInternalValues} = $a[2] eq "full" ? 1 : 0;
    my $ret = CommandList(undef,$name);
    if ($globAttr eq "undef"){
      delete $attr{global}{showInternalValues};
    }
    else{
      $attr{global}{showInternalValues} = $globAttr;
    }
    return $ret;
  }
 
  Log3 $name,3,"CUL_HM get $name " . join(" ", @a[1..$#a]);

  my $rxType = CUL_HM_getRxType($hash);
  CUL_HM_ProcessCmdStack($devHash) if ($rxType & 0x03);#burst/all
  return "";
}

sub CUL_HM_TemplateModify(){
   $modules{CUL_HM}{helper}{tmplTimestamp} = time();
}
sub CUL_HM_getTemplateModify(){
   return (defined $modules{CUL_HM}{helper}{tmplTimestamp} ? $modules{CUL_HM}{helper}{tmplTimestamp} : 'no');
}
sub CUL_HM_SetList($$) {#+++++++++++++++++ get command basic list++++++++++++++
  my($name,$cmdKey)=@_;
  my $hash = $defs{$name} // return;
  
  if(!$cmdKey){
    my $devName = InternalVal($name,"device",$name);
    my (undef,$chn) = unpack 'A6A2',$hash->{DEF}.'01';#default to chn 01 for dev
    $cmdKey =        ($hash->{helper}{role}{chn}?1:0)
                .":".($hash->{helper}{role}{dev}?1:0)
                .":".($hash->{helper}{role}{vrt}?1:0)
                .":".($hash->{helper}{fkt}?$hash->{helper}{fkt}:"")
                .":".$devName
                .":".($defs{$devName}{helper}{mId} ? $defs{$devName}{helper}{mId}:"")
                .":".$chn
                .":".InternalVal($name,"peerList","")
               ;# update cmds entry in case
  }
  if( $hash->{helper}{cmds}{cmdKey} ne $cmdKey){
    my ($roleC,$roleD,$roleV,$fkt,$devName,$mId,$chn,$peerLst) = split(":", $cmdKey);
    my $st      = $mId ne "" ? $culHmModel->{$mId}{st}   : AttrVal($devName, "subType", "");
    my $md      = $mId ne "" ? $culHmModel->{$mId}{name} : AttrVal($devName, "model"  , "");
    my @arr1 = ();
    delete $hash->{helper}{cmds}{cmdLst}{$_} foreach(grep!/^tpl(Set|Para)/,keys%{$hash->{helper}{cmds}{cmdLst}});
    if (defined $hash->{helper}{regLst}){
      foreach my $rl(grep /./,split(",",$hash->{helper}{regLst})){        
        next if (!defined $culHmReglSets->{$rl});
        foreach(keys %{$culHmReglSets->{$rl}}      ){push @arr1,"$_:".$culHmReglSets->{$rl}{$_}         };
      }
    }
    
    if( !$roleV &&($roleD || $roleC)        ){push @arr1,map{"$_:".$culHmGlobalSets->{$_}            } sort keys %{$culHmGlobalSets}           };
    if(( $roleV||!$st||$st eq "no")&& $roleD){push @arr1,map{"$_:".$culHmGlobalSetsVrtDev->{$_}      } sort keys %{$culHmGlobalSetsVrtDev}     };
    if( !$roleV                    && $roleD){push @arr1,map{"$_:".${$culHmSubTypeDevSets->{$st}}{$_}} sort keys %{$culHmSubTypeDevSets->{$st}}};
    if( !$roleV                    && $roleC){push @arr1,map{"$_:".$culHmGlobalSetsChn->{$_}         } sort keys %{$culHmGlobalSetsChn}        };
    if( $culHmSubTypeSets->{$st}   && $roleC){push @arr1,map{"$_:".${$culHmSubTypeSets->{$st}}{$_}   } sort keys %{$culHmSubTypeSets->{$st}}   };
    if( $culHmModelSets->{$md})              {push @arr1,map{"$_:".${$culHmModelSets->{$md}}{$_}     } sort keys %{$culHmModelSets->{$md}}     };
    if( $culHmChanSets->{$md."00"} && $roleD){push @arr1,map{"$_:".${$culHmChanSets->{$md."00"}}{$_} } sort keys %{$culHmChanSets->{$md."00"}} };
    if( $culHmChanSets->{$md."xx"} && $roleC){push @arr1,map{"$_:".${$culHmChanSets->{$md."xx"}}{$_} } sort keys %{$culHmChanSets->{$md."xx"}} };
    if( $culHmChanSets->{$md.$chn} && $roleC){push @arr1,map{"$_:".${$culHmChanSets->{$md.$chn}}{$_} } sort keys %{$culHmChanSets->{$md.$chn}} };
    if( $culHmFunctSets->{$fkt}    && $roleC){push @arr1,map{"$_:".${$culHmFunctSets->{$fkt}}{$_}    } sort keys %{$culHmFunctSets->{$fkt}}    };

    $hash->{helper}{cmds}{lst}{peerOpt} = CUL_HM_getPeerOption($name);
    push @arr1,"peerSmart:-peerOpt-" if ($hash->{helper}{cmds}{lst}{peerOpt}); 
   
    my @cond = ();
    push @cond,map{$lvlStr{md}{$md}{$_}}         sort keys%{$lvlStr{md}{$md}}         if (defined $lvlStr{md}{$md});
    push @cond,map{$lvlStr{mdCh}{"$md$chn"}{$_}} sort keys%{$lvlStr{mdCh}{"$md$chn"}} if (defined $lvlStr{mdCh}{"$md$chn"});
    push @cond,map{$lvlStr{st}{$st}{$_}}         sort keys%{$lvlStr{st}{$st}}         if (defined $lvlStr{st}{$st});
    push @cond,"slider,0,1,255" if (!scalar @cond);
    $hash->{helper}{cmds}{lst}{condition} = join(",",sort grep /./,@cond);

    $hash->{helper}{cmds}{lst}{peer} = join",",sort (CUL_HM_getPeers($name,"Names"));
    if (grep /^press:/,@arr1){
      if ($roleV){
        push @arr1,"pressS:[(-peer-|{all})]";
        push @arr1,"pressL:[(-peer-|{all})]";
      }
      elsif ($peerLst ne ""){
        push @arr1,"pressS:[(-peer-|{self})]";
        push @arr1,"pressL:[(-peer-|{self})]";
      }
      else{#remove command
        @arr1 = grep !/(trg|)(press|event|Press|Event)[SL]\S*?/,@arr1;
      }
    }
    foreach(@arr1){
      my ($cmdS,$val) = split(":",$_,2);
      $val =~ s/\{self\}/\{self$chn\}/;
      $hash->{helper}{cmds}{cmdLst}{$cmdS} = (defined $val && $val ne "") ? $val : "noArg";
    }

    #---------------- gets ---------------
    my @gets = ();
    if(!$roleV)                              {push @gets,map{"$_:".$culHmGlobalGets->{$_}            }keys %{$culHmGlobalGets}              };
    if($roleV)                               {push @gets,map{"$_:".$culHmVrtGets->{$_}               }keys %{$culHmVrtGets}              };
    if($culHmSubTypeGets->{$st})             {push @gets,map{"$_:".${$culHmSubTypeGets->{$st}}{$_}   }keys %{$culHmSubTypeGets->{$st}}   };
    if($culHmModelGets->{$md})               {push @gets,map{"$_:".${$culHmModelGets->{$md}}{$_}     }keys %{$culHmModelGets->{$md}}     };
    if($roleD)                               {push @gets,map{"$_:".$culHmGlobalGetsDev->{$_}         }keys %{$culHmGlobalGetsDev}        };

    delete $hash->{helper}{cmds}{rtrvLst};
    foreach(@gets){
      my ($cmdS,$val) = split(":",$_,2);
      $hash->{helper}{cmds}{rtrvLst}{$cmdS} = (defined $val && $val ne "") ? $val : "noArg";
    }
    $hash->{helper}{cmds}{cmdKey}  = $cmdKey;
  }

  my $tmplStamp = CUL_HM_getTemplateModify();
  my $tmplAssTs = (defined $hash->{helper}{cmds}{TmplTs} ? $hash->{helper}{cmds}{TmplTs}:"noAssTs");# template assign timestamp
  my $peerLst = InternalVal($name,"peerList","");
  if($hash->{helper}{cmds}{TmplKey} ne $peerLst.":$tmplStamp:$tmplAssTs" ){
    my @arr1 =  map{"$_:-value-"}split(" ",CUL_HM_TmplSetParam($name));
    delete $hash->{helper}{cmds}{cmdLst}{$_} foreach(grep/^tpl(Set|Para)/,keys%{$hash->{helper}{cmds}{cmdLst}});
    
    CUL_HM_TmplSetCmd($name);
    push @arr1, "tplSet_0:-tplChan-" if(defined $hash->{helper}{cmds}{lst}{tplChan});
    if(defined $hash->{helper}{cmds}{lst}{tplPeer}){
      push @arr1, "tplSet_$_:-tplPeer-" foreach(split(",",$peerLst));
    }
    $hash->{helper}{cmds}{lst}{tplDel} = join(",",keys%{$hash->{helper}{tmpl}});

    foreach(@arr1){
      my ($cmdS,$val) = split(":",$_,2);
      $hash->{helper}{cmds}{cmdLst}{$cmdS} = (defined $val && $val ne "") ? $val : "noArg";
    }

    $hash->{helper}{cmds}{TmplKey}  = $peerLst
                                     .":$tmplStamp"
                                     .":$tmplAssTs"
                                     ;   
  }

  return;
}
sub CUL_HM_SearchCmd($$) {#+++++++++++++++++ is command supported?+++++++++++++
  my($name,$findCmd)=@_;
  CUL_HM_SetList($name,"") if ($defs{$name}{helper}{cmds}{cmdKey} eq "");
  return defined $defs{$name}{helper}{cmds}{cmdLst}{$findCmd} ? 1 : 0;
}


sub CUL_HM_Set($@) {#+++++++++++++++++ set command+++++++++++++++++++++++++++++
  my ($hash, @a) = @_;
#  my $T0 = gettimeofday();
  return "no value specified" if(@a < 2);
  return "FW update in progress - please wait" 
        if ($modules{CUL_HM}{helper}{updating});
  my $act     = join(" ", @a[1..$#a]);
  my $name    = $hash->{NAME};
  return "" if (!defined $name || CUL_HM_getAttrInt($name,"ignore"));
  my $devName = InternalVal($name,"device",$name);
  my $st      = defined $defs{$devName}{helper}{mId} ? $culHmModel->{$defs{$devName}{helper}{mId}}{st}   : AttrVal($devName, "subType", "");
  my $md      = defined $defs{$devName}{helper}{mId} ? $culHmModel->{$defs{$devName}{helper}{mId}}{name} : AttrVal($devName, "model"  , "");
  my $flag    = 'A0'; #set flag

  my ($dst,$chn) = unpack 'A6A2',$hash->{DEF}.'01';#default to chn 01 for dev
  return "" if (!defined $chn);

  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;
  my $fkt   = $hash->{helper}{fkt}?$hash->{helper}{fkt}:"";
 
  CUL_HM_SetList($name               # refresh command options
                 ,  "$roleC"
                  .":$roleD"
                  .":$roleV"
                  .":$fkt"
                  .":$devName"
                  .":".($defs{$devName}{helper}{mId} ? $defs{$devName}{helper}{mId}:"")
                  .":$chn"
                  .":".InternalVal($name,"peerList","")
                 );# update cmds entry in case

  my $cmd     = $a[1];
  if (defined($hash->{helper}{cmds}{cmdLst}{pct}) && $cmd =~ m/^\d+\.?\d*$/) {# is cmd "pct"?
    splice @a, 1, 0,"pct";#insert the actual command
    $cmd = "pct";
  }
  if(!defined $hash->{helper}{cmds}{cmdLst}{$cmd}) { ### unknown - return the commandlist
    my @cmdPrep = ();
    foreach my $cmdS (keys%{$hash->{helper}{cmds}{cmdLst}}){
      my $val = $hash->{helper}{cmds}{cmdLst}{$cmdS};

      if($cmdS =~ m/^(pct|pctSlat)$/){
        $val = ":slider,0,1,100";
      }
      elsif($val !~ m/ /){#no space - this is a single param command (or less)
        my $opt  = ($val =~ s/^\[(.*)\] *$/$1/ ? "noArg" : "");
        $val =~ s/^\((.*)\)$/$1/;
        my $dflt = ($val =~ s/\{(.*)\}// ? $1 : "");

        if   ($val eq "noArg"){
            $val = ":$val";
        }
        elsif($cmdS eq "color"){
          $val = ":colorpicker,HUE,0,0.5,100";
        }
        elsif($val eq "-tempTmpl-"){
          if(!defined $modules{CUL_HM}{tempListTmplLst}){
            $val = "";
          }
          else{
            $val = ":$modules{CUL_HM}{tempListTmplLst}";
          }
        }
        elsif($val =~ m/^-([a-zA-Z]*?)-\|?(.*)$/){#add relacements if available plus default
          my ($repl,$def) = ($1,$2);
          $def = "" if (!defined $def);
          if (defined $hash->{helper}{cmds}{lst}{$repl}){
            $repl = $hash->{helper}{cmds}{lst}{$repl};
            next if ($repl.$dflt.$opt eq "");# - options
            $val = ":".join(",",grep/./,( $dflt
                                         ,$opt
                                         ,$repl
                                         ,$def));
          }
          else{
            $val = "";
          }
        }
        elsif($val =~ m/^([a-zA-Z0-9\;_\-\|\.]*)$/){#(xxx|yyy) as optionlist - new
          my $v1 = $1;
          my @lst1;
          foreach(split('\|',$v1)){
            if ($_ =~ m/(.*)\.\.(.*)/ ){
              my ($min,$max,$step) = ($1,$2,0.5);
              if ($max =~ m/(.*);(.*)/){
                ($max,$step) = ($1,$2);
              }
              my $f = 0;
              ($f) = map{(my $foo = $_) =~ s/.*\.//;length($foo)}($step) if ($step =~ m/\./);
              my $m = ($max - $min)/$step;
              push @lst1, map{sprintf("%.${f}f",$min + $_ * $step)}(0..$m);
            }
            else{
              push @lst1,$_;
            }     
          }
          $val = ":".join(",",grep/./,($dflt,$opt,@lst1));
        }
        else    {# no shortcut
          $val = "";
        }
      }
      else      {# multi-parameter - no quick select
        $val = "";
      }
      push @cmdPrep,"$cmdS$val";
    }
    @cmdPrep = ("--") if (!scalar @cmdPrep);
    Log3 $name,(defined $modules{CUL_HM}{helper}{verbose}{allSetVerb} ? 0:5),"CUL_HM set $name $cmd";
    return "Unknown argument $cmd, choose one of ".join(" ",@cmdPrep)." ";
  }

  ###------------------- commands parameter parsing -------------------###
  if (1){
    my @parIn = grep!/noArg/,@a[2..$#a];
    my $paraOpts = $hash->{helper}{cmds}{cmdLst}{$cmd};
    $paraOpts =~ s/(\.\.\.|noArg|\'.*?\')//g;#remove comment, "..." and noArg
    my @optLst = split(" ",$paraOpts);#[...] would leave an empty list
    #my $max = $hash->{helper}{cmds}{cmdLst}{$cmd} =~ m/\.\.\./ ? 99 : scalar(@optLst);
    $paraOpts =~ s/(\[.*?\])//g; # remove optionals
    my $pCnt = 0;
    my $paraFail = "";
    foreach my $param (@optLst){ # check each parameter
      my $optional = $param =~ s/^\[(.*)\]$/$1/ ? 1:0; # is parameter optional?
      if($param =~ m/^\((.*)\)$/ ){                 # list of options?
        my @parLst = split('\|',$1);
        if(  defined $parIn[$pCnt]){                # user param provided
          my ($tmp1) = map{my$foo=$_;$foo =~ s/([\?\*\+])/\\$1/g;$foo}($parIn[$pCnt]);       
          if( $parIn[$pCnt] !~ m/[:\{\[\(]/ && grep/$tmp1/,@parLst){ # parameter not comparable or matched 
          }
          elsif($param =~ m/([\-\d\.]*)\.\.([\-\d\.]*)/ ){# we check for min/max but not for step
            my ($min,$max) = ($1,$2);
            if ($parIn[$pCnt] !~ m/^[-+]?[0-9]+\.?[0-9]*$/){
              $paraFail = "\'$parIn[$pCnt]\' not numeric";
            }
            elsif ($parIn[$pCnt] < $min || $parIn[$pCnt] > $max ){
              $paraFail = "\'$parIn[$pCnt]\' out of range min:$min max:$max";
            }
          }
          else{                                     # user param no match
            if($param =~ m/-.*-/){                  #    but not distinct
            }
            elsif($optional && $param =~ m/\{(.*?)\}/){# no match, distinct but optional with default
              my $default = $1;
              splice @parIn, $pCnt, 0,$default;#insert the default
            }
            else{                                   # no match, distinct, not optional or no default => fail
              $paraFail = "$parIn[$pCnt] does not match options";
            }
          }
        }
        else{                                       # no user param
          if($optional){                            # optional
            if($param =~ m/\{(.*)\}/){              #   defaut available, use it
              my $default = $1;
              splice @parIn, $pCnt, 0,$default;#insert the default
            }
            else{                                   # insert "noArg"
              splice @parIn, $pCnt, 0,"noArg";
            }
          }
          else{                                     # no user param, no default => fail
            $paraFail = "is not optional. No dafault identifies";
          }
        }
      }
      $paraFail = "is required but missing" if(!defined $parIn[$pCnt] && !$optional);
      if($paraFail){
        $paraFail = "param $pCnt:'$optLst[$pCnt]' => $paraFail"
                    ."\n$cmd: $hash->{helper}{cmds}{cmdLst}{$cmd}";
        Log3 $name,(defined $modules{CUL_HM}{helper}{verbose}{allSet} ? 0:3),"CUL_HM reject-set $name $cmd: $paraFail ";
        return $paraFail;
      }

      $pCnt++;
    }

    splice @parIn, $pCnt, 0,"noArg" if(scalar(@parIn) == 0);
    @a = ($a[0],$cmd,@parIn);
    
  }
  Log3 $name,(defined $modules{CUL_HM}{helper}{verbose}{allSet} ? 0:3),"CUL_HM set $name " . join(" ", @a[1..$#a]);

  my @postCmds=(); #Commands to be appended after regSet (ugly...)
  my $id; # define id of IO device for later usage
  ###------------------- commands requiring no IO action -------------------###
  my $nonIOcmd = 1;
  if(   $cmd eq "clear") { ####################################################
    my (undef,undef,$sectIn) = @a;
    my @sectL;
    if ($sectIn eq "all") {
      @sectL = ("rssi","msgEvents","readings","attack");#readings is last - it schedules a reread possible
    }
    elsif($sectIn =~ m/(rssi|trigger|msgEvents|msgErrors|readings|oldRegs|register|unknownDev|attack)/){
      @sectL = ($sectIn);
    }
    else{
      return "unknown section:$sectIn. User rssi|trigger|msgEvents|readings|oldRegs|register|unknownDev|attack";
    }
    foreach my $sect (@sectL){
      if   ($sect eq "readings"){
        my @cH = ($hash);
        push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,sort keys %{$hash});
        delete $_->{READINGS} foreach (@cH);
        delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
        CUL_HM_complConfig($_->{NAME}) foreach (@cH);
        CUL_HM_qStateUpdatIfEnab($_->{NAME}) foreach (@cH);
      }
      elsif($sect eq "unknownDev"){
        delete $hash->{READINGS}{$_} 
             foreach (grep /^unknown_/,keys %{$hash->{READINGS}});
      }
      elsif($sect eq "trigger"){
        delete $hash->{READINGS}{$_} foreach (grep /^trig/,keys %{$hash->{READINGS}});
      }
      elsif($sect eq "register"){
        my @cH = ($hash);
        push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,sort keys %{$hash});
      
        foreach my $h(@cH){
          delete $h->{READINGS}{$_}
               foreach (grep /^(\.?)(R-|RegL)/,keys %{$h->{READINGS}});
          delete $h->{helper}{shadowReg}{$_}
               foreach (grep /^(\.?)(R-|RegL)/,keys %{$h->{helper}{shadowReg}});
          delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
          CUL_HM_complConfig($h->{NAME});
        }
      }
      elsif($sect eq "oldRegs"){
        my @cN = ($name);
        push @cN,$hash->{$_} foreach(grep /^channel/,keys %{$hash});     
        foreach (@cN){
          CUL_HM_refreshRegs($_);
        }
      }
      elsif($sect eq "msgEvents"){
        CUL_HM_respPendRm($hash);
      
        $hash->{helper}{prt}{bErr}=0;
        delete $hash->{cmdStack};
        delete $hash->{helper}{prt}{rspWait};
        delete $hash->{helper}{prt}{mmcA};
        delete $hash->{helper}{prt}{mmcS};
        delete $hash->{lastMsg};
        delete ($hash->{$_}) foreach ( grep {$_ =~ m/^prot/ && $_ ne 'protCondBurst'} keys %{$hash} );
      
        if ($hash->{IODev}{NAME} &&
            $modules{CUL_HM}{$hash->{IODev}{NAME}} &&
            $modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}){
          @{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}} =
                grep !/$name/,@{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}};
        }
        CUL_HM_unQEntity($name,"qReqConf");
        CUL_HM_unQEntity($name,"qReqStat");
        CUL_HM_protState($hash,"Info_Cleared");
      }
      elsif($sect eq "msgErrors"){
        delete $hash->{protResndFail};
        delete $hash->{protResnd};
        delete $hash->{protCmdDel};
        delete $hash->{protNACK};
        delete $hash->{protIOerr};
      }
      elsif($sect eq "rssi"){
        delete $defs{$name}{helper}{rssi};
        delete ($hash->{$_}) foreach (grep(/^rssi/,keys %{$hash}))
      }
      elsif($sect eq "attack"){
        delete $defs{$name}{helper}{rssi};
        delete ($hash->{$_}) foreach (grep(/^protErrIo(Id|Attack)/,keys %{$hash}));
        delete $hash->{READINGS}{$_}
            foreach (grep /^sabotageAttack/,keys %{$hash->{READINGS}});
      }
    }

  }
  elsif($cmd eq "defIgnUnknown") { ############################################
    foreach (map {substr($_,8)} 
             grep /^unknown_......$/,
             keys %{$hash->{READINGS}}){
      if (!$modules{CUL_HM}{defptr}{$_}){
        CommandDefine(undef,"unknown_$_ CUL_HM $_") ;
        $attr{"unknown_$_"}{ignore} = 1;
      }
      delete $hash->{READINGS}{"unknown_$_"};
    }
  }
  elsif($cmd eq "deviceRename") { #############################################
    my $newName = $a[2];
    my @chLst = ("device");# entry 00 is unsed

    my $result = CommandRename(undef,$name.' '.$newName);#and the device itself
    if ($result){
      return $result;
    }
    $hash->{device} = $newName;
 
    if ($roleV){
      foreach(1..50){
        push @chLst,$newName."_Btn".$_;
      }
    }
    else{
      my $mId = CUL_HM_getMId($hash);# set helper valiable and use result
      foreach my $chantype (split(',',$culHmModel->{$mId}{chn})){
        my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
        my $chnNoTyp = 1;
        for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
          my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
          $chLst[$chnNoAbs] = $newName."_".$chnTpName.(($chnStart == $chnEnd)
                                                ? ''
                                                : '_'.sprintf("%02d",$chnNoTyp));
          $chnNoTyp++;
        }
      }
    }
    my @results;
    my @renamed;
    foreach my $cd (grep /^channel_/,sort keys %{$hash}){
      my $cName = InternalVal($newName,$cd,"");
      my $no = hex(substr($cd,8));
      $result = CommandRename(undef,$cName.' '.$chLst[$no]);
      $hash->{"channel_".sprintf "%02X",$no} = $chLst[$no];     #reference in device as well
      $defs{$chLst[$no]}->{device} = $newName;
      push @renamed, $chLst[$no];
      push @results,"rename $cName failed: $result" if ($result);
    }
    CUL_HM_setAssotiat($newName);
    for (@renamed) { CUL_HM_setAssotiat($_); }
    return "channel rename failed:\n".join("\n",@results) if (scalar @results);
  }
  elsif($cmd eq "tempListTmpl") { #############################################
    my $action = "verify";#defaults
    my ($template,$fn);
    for my $ax ($a[2],$a[3]){
      next if (!$ax);
      if ($ax =~ m/^(verify|restore)$/){
        $action = $ax;
      }
      else{
        $template = $ax;
      }
    }
    ($fn,$template) = split(":",($template?$template
                                          :AttrVal($name,"tempListTmpl",$name)));
    if (defined &HMinfo_tempListDefFn){
      if (!$template){ $template = HMinfo_tempListDefFn()   .":$fn"      ;}
      else{            $template = HMinfo_tempListDefFn($fn).":$template";}
    }
    else{
      if (!$template){ $template = "./tempList.cfg:$fn";}
      else{            $template = "$fn:$template"     ;}
    }
    my $ret = CUL_HM_tempListTmpl($name,$action,$template);
    $ret = "verifed with no faults" if (!$ret && $action eq "verify");
    return $ret;
  }
  elsif($cmd eq "tempTmplSet") { ##############################################
    return "template missing" if (!defined $a[2]);
    my $reply = CommandAttr(undef, "$name tempListTmpl $a[2]");
    
    my ($fn,$template) = split(":",AttrVal($name,"tempListTmpl",$name));
    if (defined &HMinfo_tempListDefFn){
      if (!$template){ $template = HMinfo_tempListDefFn()   .":$fn"      ;}
      else{            $template = HMinfo_tempListDefFn($fn).":$template";}
    }
    else{
      if (!$template){ $template = "./tempList.cfg:$fn";}
      else{            $template = "$fn:$template"     ;}
    }
    CUL_HM_tempListTmpl($name,"restore",$template);
  }
  elsif($cmd eq "tplDel") { ###################################################
    return "template missing" if (!defined $a[2]);
    my ($p,$t) = split(">",$a[2]);
    if (defined &HMinfo_templateDel){
      HMinfo_templateDel($name,$t,$p) if (eval "defined(&HMinfo_templateDel)");
    }
    return;
  }
  elsif($cmd eq "virtual") { ##################################################
    my (undef,undef,$maxBtnNo) = @a;
    return "please give a number between 1 and 50"
       if ($maxBtnNo < 1 ||$maxBtnNo > 50);# arbitrary - 255 should be max
    return $name." already defines as ".$attr{$name}{subType}
       if ($attr{$name}{subType} && $attr{$name}{subType} !~ m/^(virtual|no)$/);
    $attr{$name}{subType} = "virtual";
    if (!$attr{$name}{model}){
      $attr{$name}{model}   = "VIRTUAL";
      $attr{$name}{".mId"}  = CUL_HM_getmIdFromModel("VIRTUAL");
    }
    my $devId = $hash->{DEF};
    for (my $btn=1;$btn <= $maxBtnNo;$btn++){
      my $chnName = $name."_Btn".$btn;
      my $chnId = $devId.sprintf("%02X",$btn);
      CommandDefine(undef,"$chnName CUL_HM $chnId")
          if (!$modules{CUL_HM}{defptr}{$chnId});
    }
    foreach my $channel (keys %{$hash}){# remove higher numbers
      my $chNo;
      $chNo = $1 if($channel =~ m/^channel_(.*)/);
      next if (!defined($chNo));
      CommandDelete(undef,$hash->{$channel})
            if (hex($chNo) > $maxBtnNo);
    }
    CUL_HM_queueUpdtCfg($name);
    CUL_HM_UpdtCentral($name) if ($md eq "CCU_FHEM");
  }
  elsif($cmd eq "update") { ###################################################
    if ($md eq "ACTIONDETECTOR"){
      CUL_HM_ActCheck("ActionDetector");
    }
    else{
      CUL_HM_UpdtCentral($name);
    }
  }
  else{                     #command which requires IO#########################
    $id = CUL_HM_IoId($defs{$devName});
    if(length($id) != 6 && $hash->{DEF} ne "000000" ){# have to try to find an IO $devName
      CUL_HM_assignIO($defs{$devName});
      $id = CUL_HM_IoId($defs{$devName});
    }
    return "no IO device identified" if(length($id) != 6 && $st ne 'virtual');
    $nonIOcmd = 0;
  }
  return ("",1) if($nonIOcmd);# we are done already

  #convert 'old' commands to current methods like regSet and regBulk...
  # Unify the interface
  if(   $cmd eq "sign"){ ######################################################
    splice @a,1,0,"regSet";# make hash,regSet,reg,value
  }
  elsif($cmd eq "unpair"){ ####################################################
    splice @a,1,3, ("regSet","pairCentral","000000");
  }
  elsif($cmd eq "ilum") { ################################################# reg
    return "$a[2] not specified. choose 0-15 for brightness"  if ($a[2]>15);
    return "$a[3] not specified. choose 0-127 for duration"   if ($a[3]>127);
    return "unsupported for channel, use $devName"            if (!$roleD);
    splice @a,1,3, ("regBulk","RegL_00.",sprintf("04:%02X",$a[2]),sprintf("08:%02X",$a[3]*2));
  }
  elsif($cmd eq "text") { ################################################# reg
    my ($bn,$l1, $l2) = ($chn,$a[2],$a[3]); # Create CONFIG_WRITE_INDEX string
    if ($roleD){# if used on device.
      return "$a[2] is not a button number" if($a[2] !~ m/^\d*$/ || $a[2] < 1);
      return "$a[3] is not on or off" if($a[3] !~ m/^(on|off)$/);
      $bn = $a[2]*2-($a[3] eq "on" ? 0 : 1);
      ($l1, $l2) = ($a[4],$a[5]);
      $chn = sprintf("%02X",$bn)
      }
    else{
      return "to many parameter. Try set $a[0] text $a[2] $a[3]" if($a[4]);
    }
    my $s = 54;
    $l1 =~ s/\\_/ /g;
    $l1 = substr($l1."\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0, 12);
    $l1 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;

    $s = 70;
    $l2 =~ s/\\_/ /g;
    $l2 = substr($l2."\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0, 12);
    $l2 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;
    @a = ($a[0],"regBulk","RegL_01.",split(" ",$l1.$l2));
  }
  elsif($cmd =~ m/^(displayMode|displayTemp|displayTempUnit|controlMode)/) { ##
    if ($md =~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){#controlMode different for RT
      splice @a,1,3, ("regSet",$a[1],$a[2]);
      push @postCmds,"++803F$id${dst}0202".sprintf("%02X",CUL_HM_secSince2000());
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

    my ($s,$m,$h) = localtime();
    return "$eH:$eM passed at $h:$m. Please enter time in the feature" 
                                                            if ($days == 0 && ($h+($m/60))>=($eH+($eM/60)) );
    return "$eM illegal - use 00 or 30 minutes only"        if ($eM !~ m/^(00|30)$/);
    return "$eH illegal - hour must be between 0 and 23"    if ($eH < 0 || $eH > 23);
    return "$days illegal - days must be between 0 and 200" if ($days < 0 || $days > 200);
    $eH += 128 if ($eM eq "30");

    my $cHash = CUL_HM_id2Hash($dst."02");
    $cHash->{helper}{partyReg} = sprintf("61%02X62%02X0000",$eH,$days);
    $cHash->{helper}{partyReg} =~ s/(..)(..)/ $1:$2/g;
    if ($cHash->{READINGS}{"RegL_06."}){#remove old settings
      $cHash->{READINGS}{"RegL_06."}{VAL} =~ s/ 61:.*//;
      $cHash->{READINGS}{"RegL_06."}{VAL} =~ s/00:00//;
      $cHash->{READINGS}{"RegL_06."}{VAL} =~ s/ $//;
      $cHash->{READINGS}{"RegL_06."}{VAL} .= $cHash->{helper}{partyReg};
    }
    else{
      $cHash->{READINGS}{"RegL_06."}{VAL} = $cHash->{helper}{partyReg};
    }
    CUL_HM_pushConfig($hash,$id,$dst,2,"000000","00",6,
                      sprintf("61%02X62%02X",$eH,$days),$prep);
    splice @a,1,3, ("regSet","controlMode","party");
    splice @a,2,0, ($prep) if ($prep);
    push @postCmds,"++803F$id${dst}0202".sprintf("%02X",CUL_HM_secSince2000());
  }

  $cmd = $a[1];# get converted command

  #if chn cmd is executed on device but refers to a channel? 
  my $chnHash = (!$roleC && $modules{CUL_HM}{defptr}{$dst."01"})?
                 $modules{CUL_HM}{defptr}{$dst."01"}:$hash;
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);
  return "device on readonly. $cmd disabled" 
        if($activeCmds{$cmd} && CUL_HM_getAttrInt($name,"readOnly") );

  if   ($cmd eq "raw") {  #####################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
    $state = "";
    my $msg = $a[2];
    foreach my $sub (@a[3..$#a]) {
      last if ($sub !~ m/^[A-F0-9]*$/);
      $msg .= $sub;      
    }
    CUL_HM_PushCmdStack($hash, $msg);
  }
  elsif($cmd eq "reset") { ####################################################
    CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  }
  elsif($cmd eq "burstXmit") { ################################################
    $state = "";
    $hash->{helper}{prt}{brstWu}=1;# start burst wakeup
    CUL_HM_SndCmd($hash,"++B112$id$dst");
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
  elsif($cmd eq "getDevInfo") { ###############################################
    $state = "";
    my $sn = ReadingsVal($name,"D-serialNr","");
    return "serial number unknown"  if (! $sn);
    CUL_HM_PushCmdStack($hash,'++8401'.$id.'000000010A'.uc(unpack('H*', $sn)));
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
    my $set = ($a[3] && $a[3] eq "unset")?"02":"01";
    foreach my $peer (grep(!/^self/,split(',',$pL))){
      last if($peer =~ m/^#/);
      my $pID = CUL_HM_peerChId($peer,$dst);
      return "unknown peer".$peer if (length($pID) != 8);# peer only to channel
      my $pCh1 = substr($pID,6,2);
      my $pCh2 = $pCh1;
      if(($culHmSubTypeSets->{$st}   && $culHmSubTypeSets->{$st}{peerChan}  )||
         ($culHmModelSets->{$md}     && $culHmModelSets->{$md}{peerChan}    )||
         ($culHmChanSets->{$md.$chn} && $culHmChanSets->{$md.$chn}{peerChan})  ){
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
      ($list,$peerID) = split('\.',$list);
#      return "unknown list Number:".$list if(hex($list)>6);
    }
    elsif ($cmd eq "getRegRaw"){
      ($list,$peerID) = ($a[2],$a[3]);
      return "Enter valid List0-7" if (!defined $list || $list !~ m/^List([0-7])$/);
      $list ='0'.$1;
    }
    # as of now only hex value allowed check range and convert
    $peerID  = CUL_HM_peerChId(($peerID?$peerID:"00000000"),$dst);
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
          if ($list =~ m/^0[34]$/){#getPeers to see if list3 is available
            CUL_HM_PushCmdStack($hash,'##'.$flag.'01'.$id.$dst.$chnNo.'03');
            my $chnHash = CUL_HM_id2Hash($channel);
            $chnHash->{helper}{getCfgList} = $peerID.$peerChn;#list3 regs
            $chnHash->{helper}{getCfgListNo} = int($list);
          }
          else{
            CUL_HM_PushCmdStack($hash,'##'.$flag.'01'.$id.$dst.$chnNo.'04'
                                          .$peerID.$peerChn.$list);
          }
        }
      }
    }
    elsif($cmd eq "regBulk"){;
      my @adIn = @a;
      shift @adIn;shift @adIn;shift @adIn;
      my $adList;
      foreach my $ad ( @adIn){
        last if($ad =~ m/^#/);
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
    my $mdAl  = CUL_HM_getAliasModel($hash);
    my @regArr = CUL_HM_getRegN($st,$mdAl,($roleD?"00":""),($roleC?$chn:""));
    
    my ($tmp1) = map{my$foo=$_;$foo =~ s/([\+\?\*])/\\$1/g;$foo}($regName); # we need to consider spacial chars
    return "$regName failed: supported register are ".join(" ",sort @regArr)
            if (!grep /^$tmp1$/,@regArr );

    my $reg  = $culHmRegDefine->{$regName};
    my $conv = $reg->{c};
    return $st." - ".$regName            # give some help
           .($conv eq "lit"? " literal:".join(",",keys%{$reg->{lit}})." "
                               : " range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
                                 .($reg->{lit}?" special:".join(",",keys%{$reg->{lit}})." "
                                              :""
                                              )
            )
           .(($reg->{p} eq 'y')?" peer required":"")." : ".$reg->{t}."\n"
            if ($data eq "?");
    if (   $conv ne 'lit' 
        && $reg->{lit} 
        && defined $reg->{lit}{$data} ){
      $data = $reg->{lit}{$data};#conv special value past to calculation
    }     
    return "value:$data out of range $reg->{min} to $reg->{max} for Reg \""
           .$regName."\""
            if (!($conv =~ m/^(lit|hex|min2time)$/)&&
                $data !~ m/^set_/ &&
                ($data < $reg->{min} ||$data > $reg->{max})); # none number
    return"invalid value. use:". join(",",sort keys%{$reg->{lit}})
            if ($conv eq 'lit' && !defined($reg->{lit}{$data}));

    if ($conv ne 'lit' && $reg->{lit} && $reg->{lit}{$data}){
      $data = $reg->{lit}{$data}; #conv special value prior to calculation
    }
    $data *= $reg->{f} if($reg->{f});# obey factor befor possible conversion
    if (!$conv){;# do nothing
    }elsif($conv eq "fltCvT"  ){$data = CUL_HM_fltCvT($data);
    }elsif($conv eq "fltCvT60"){$data = CUL_HM_fltCvT60($data);
    }elsif($conv eq "min2time"){$data = CUL_HM_time2min($data);
    }elsif($conv eq "m10s3")   {$data = $data*10-3;
    }elsif($conv eq "hex")     {$data = hex($data);
    }elsif($conv eq "lit")     {$data = $reg->{lit}{$data};
    }else{return " conv undefined - please contact admin";
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
#    if (($list == 3) ||($list == 4)   # peer is necessary for list 3/4
    if ($reg->{p} eq 'y'              # peer is necessary 
        ||(defined $peerChnIn and $peerChnIn))   {# and if requested by user
      return "Peer not specified" if ($peerChnIn eq "");
      $peerId  = CUL_HM_peerChId($peerChnIn,$dst);
      ($peerId,$peerChn) = unpack 'A6A2',$peerId.'01';
      if (   $list == 4             # If the device is programmed as peer then "00" is the channel 
          && $defs{$peerChnIn}{helper}{role}{dev}
          && AttrVal($name,"peerIDs",0)=~ m/${peerId}(0x|00)/){
          $peerChn = "00";
      }
      return "Peer not valid" if (length ($peerId) < 6);
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
      my $cName = CUL_HM_id2Name($dst.$lChn);
      $cName =~ s/_chn-\d\d$//;
      my $curVal = CUL_HM_getRegFromStore($cName,$addr,$list,$peerId.$peerChn);
      if ($curVal !~ m/^(set_|)(\d+)$/){
        return "peer required for $regName" if ($curVal =~ m/peer/);
        return "cannot calculate value. Please issue set $name getConfig first - $curVal";
      }
      $curVal = $2; # we expect one byte in int, strap 'set_' possibly
      $data = ($curVal & (~($mask<<$bit)))|($data<<$bit);
      $addrData.=sprintf("%02X%02X",$addr,$data);
    }
    else{
      for (my $cnt = 0;$cnt<int($reg->{s}+0.99);$cnt++){
        $addrData.=sprintf("%02X",$addr+$cnt).substr($dataStr,$cnt*2,2);
      }
    }

    my $cHash = CUL_HM_id2Hash($dst.($lChn eq '00'?"":$lChn));
    $cHash = $hash if (!$cHash);
    CUL_HM_pushConfig($cHash,$id,$dst,hex($lChn),$peerId,hex($peerChn),$list
                     ,$addrData,$prep);

    CUL_HM_PushCmdStack($hash,$_) foreach(@postCmds);#ugly commands after regSet
  }

  elsif($cmd eq "level") { ####################################################
    #level        =>"<level> <relockDly> <speed>..."
    my (undef,undef,$lvl,$rLocDly,$speed) = @a;
    $rLocDly = 111600 if (!defined($rLocDly)||$rLocDly eq "ignore");# defaults
    $speed   = 30     if (!defined($speed));
    $lvl = 127.5 if ($lvl eq "lock");
    return "please enter level 0 to 100 or lock" 
                                         if (  !defined($lvl)           
                                             || $lvl !~ m/^\d*\.?\d?$/  
                                             || ($lvl > 100 && $lvl != 127.5));
    return "reloclDelay range 0..65535 or ignore"
                                         if ( $rLocDly > 111600 ||
                                             ($rLocDly < 0.1 &&  $rLocDly ne '0' ));
    return "select speed range 0 to 100" if ( $speed > 100);
    
    $rLocDly = CUL_HM_encodeTime8($rLocDly);# calculate hex value
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'81'.$chn.
                        sprintf("%02X%02s%02X",$lvl*2,$rLocDly,$speed*2));
  }
  elsif($cmd =~ m/^(on|off|toggle)$/) { #######################################
    my $lvlInv = (AttrVal($name, "param", "") =~ m/levelInverse/)?1:0;
    $hash->{helper}{dlvl} = ( $cmd eq 'off'||
                             ($cmd eq 'toggle' &&CUL_HM_getChnLvl($name) != 0)) 
                                ? ($lvlInv?'C8':'00')
                                : ($lvlInv?'00':'C8');
    my(undef,$lvlMax)=split",",AttrVal($name, "levelRange", "0,100");
    $hash->{helper}{dlvl} = sprintf("%02X",$lvlMax*2)   if ($hash->{helper}{dlvl} eq 'C8');
    if ($md eq "HM-LC-JA1PBU-FM"){ $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."80$chn$hash->{helper}{dlvl}"."CA";}
    else{                          $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn$hash->{helper}{dlvl}".'0000';}
    CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    $hash = $chnHash; # report to channel if defined
  }
  elsif($cmd eq "toggleDir") { ################################################
    if ($hash->{helper}{dir}{cur} &&  $hash->{helper}{dir}{cur} ne "err"){
      my $old = $hash->{helper}{dir}{cur};
      $hash->{helper}{dir}{cur} = $hash->{helper}{dir}{cur} eq "stop" ?(($hash->{helper}{dir}{rct} 
                                                                      && $hash->{helper}{dir}{rct} eq "up")?"down"
                                                                                                           :"up")
                                                                      :"stop";
      $hash->{helper}{dir}{rct} = $old;
    }
    else{
      $hash->{helper}{dir}{rct} = "stop";
      $hash->{helper}{dir}{cur} = "up";
    }
    if     ($hash->{helper}{dir}{cur} eq "up"  ){
      $hash->{helper}{dlvl} = "C8";
      $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn".'C80000';
      CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    }elsif ($hash->{helper}{dir}{cur} eq "down"){
      $hash->{helper}{dlvl} = "00";
      $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn".'000000';
      CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    }else                                       {
      delete $hash->{helper}{dlvl};
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
    }
  }
  elsif($cmd =~ m/^(on-for-timer|on-till)$/) { ################################
    my (undef,undef,$duration,$ramp) = @a; #date prepared extention to entdate
    if ($cmd eq "on-till"){
      # to be extended to handle end date as well
      my ($info,$eH,$eM,$eSec)  = GetTimeSpec($duration);
      return "enter time: $info" if($info && $info !~ m/Wrong/);
      
      $eSec += $eH*3600 + $eM*60;
      my @lt = localtime;
      my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
      $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
      $duration = $eSec - $ltSec;
    }
    return "please enter the duration in seconds"
          if (!defined $duration || $duration !~ m/^[+-]?\d+(\.\d+)?$/);
    my $tval = CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
    #    return "timer value to low" if ($tval eq "0000"); does it work for all if "0000"?
    $tval = "" if ($tval eq "0000");
    $ramp = ($ramp && $st eq "dimmer") ? CUL_HM_encodeTime16($ramp)
           :($tval eq ""               ? ""
                                       : "0000");
    delete $hash->{helper}{dlvl};#stop desiredLevel supervision
    $hash->{helper}{stateUpdatDly} = ($duration>120)?$duration:120;
    my(undef,$lvlMax)=split",",AttrVal($name, "levelRange", "0,100");
    $lvlMax = sprintf("%02X",$lvlMax*2);
    CUL_HM_PushCmdStack($hash,"++${flag}11$id${dst}02${chn}$lvlMax$ramp$tval");
    $hash = $chnHash; # report to channel if defined
  }
  elsif($cmd eq "alarmLevel") { ###############################################
    #level        =>"[disarmed|armExtSens|armAll|armBlocked]"
    my %lvlSet = (disarmed=>"00",armExtSens=>"32",armAll=>"C8",armBlocked=>"FF");
    my (undef,undef,$lvl,$onTime) = (@a,0);#set ontime to 0 if not given. 
    $lvl = $lvlSet{$lvl};
    
    return "please enter the onTime in seconds"
      if ($onTime !~ m/^[+-]?\d+(\.\d+)?$/);
    my $tval = CUL_HM_encodeTime16($onTime);# onTime   0.0..85825945.6, 0=forever
    $tval = "" if ($tval eq "0000");
    CUL_HM_PushCmdStack($hash,"++${flag}11$id${dst}02${chn}${lvl}0000$tval");
  }

  elsif($cmd eq "lock") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800100FF'); # LEVEL_SET
  }
  elsif($cmd eq "unlock") { ###################################################
      my $tval = (@a > 2) ? int($a[2]) : 0;
      my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";   # RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800101'.$delay);# LEVEL_SET
  }
  elsif($cmd eq "open") { #####################################################
      my $tval = (@a > 2) ? int($a[2]) : 0;
      my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";   # RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'8001C8'.$delay);# OPEN
  }
  elsif($cmd eq "inhibit") { ##################################################
    return "$a[2] is not on or off" if($a[2] !~ m/^(on|off)$/);
    my $val = ($a[2] eq "on") ? "01" : "00";
    CUL_HM_UpdtReadSingle($hash,"inhibit","set_$a[2]",1);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$val.$chn);  # SET_LOCK
  }
  elsif($cmd =~ m/^(up|down|pct|old)$/) { #####################################
    my ($lvl,$tval,$rval,$duration) = (($cmd eq "old"?"old":($a[2]?$a[2]:0))
                                        ,"","",0);
    my($lvlMin,$lvlMax) = split",",AttrVal($name, "levelRange", "0,100");
    my $lvlInv = (AttrVal($name, "param", "") =~ m/levelInverse/)?1:0;
    if ($lvl eq "old"){#keep it - it means "old value"
    }
    else{
      $lvl =~ s/(\d*\.?\d*).*/$1/;
      return "level not given" if(!defined $lvl);
      if ($cmd eq "pct"){
      }
      else{#dim [<changeValue>] ... [ontime] [ramptime]
        $lvl = 10 if (!defined $a[2]); #set default step
        $lvl = -1*$lvl if (($cmd eq "down" && !$lvlInv)|| 
                           ($cmd ne "down" && $lvlInv));
        $lvl += CUL_HM_getChnLvl($name);
      }
      $lvl = $lvlMin + $lvl*($lvlMax-$lvlMin)/100; # relativ to range
      $lvl = ($lvl > $lvlMax)?$lvlMax:(($lvl <= $lvlMin)?0:$lvl);
    }
    if ($st =~ m/^(dimmer|rgb)$/){# at least blind cannot stand ramp time...
      if (!$a[3]){
        $tval = "FFFF";
        $duration = 0;
      }
      elsif ($a[3] =~ m/(..):(..):(..)/){
        my ($eH,$eM,$eSec)  = ($1,$2,$3);
        $eSec += $eH*3600 + $eM*60;
        my @lt = localtime;
        my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
        $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
        $duration = $eSec - $ltSec;
        $tval = CUL_HM_encodeTime16($duration);
      }
      else{
        $duration = $a[3];
        $tval = CUL_HM_encodeTime16($duration);# onTime 0.05..85825945.6, 0=forever
      }
      $rval = CUL_HM_encodeTime16($a[4]);# rampTime 0.0..85825945.6, 0=immediate
      $hash->{helper}{stateUpdatDly} = ($duration>120)?$duration:120;
    }
    # store desiredLevel in and its Cmd in case we have to repeat
    my $plvl = ($lvl eq "old")?"C9"
                              :sprintf("%02X",(($lvlInv)?100-$lvl :$lvl)*2);
    if (($tval ne "FFFF") || $lvl eq "old"){
      delete $hash->{helper}{dlvl};#stop desiredLevel supervision
    }
    else{
      $hash->{helper}{dlvl} = $plvl;
    }
    if    ($md eq "HM-LC-JA1PBU-FM"){ $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."80$chn$plvl"."CA";}
    else{                             $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn$plvl$rval$tval";}
    CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    $state = "set_".$lvl;
    CUL_HM_UpdtReadSingle($hash,"level",$state,1);
  }
  elsif($cmd =~ m/^(pctSlat|pctLvlSlat)$/) { ##################################
    # pctSlat        =>"[0-100]|old|noChng"
    # pctLvlSlat     =>"-value-|old|noChng -slatValue-|old|noChng"
    my ($lvl,$slat,$plvl,$pslat);
    return "param missing " if (!defined $a[2]);
    if ($cmd eq "pctSlat"){
      $slat = $a[2];
      $lvl  = "noChng";
    }
    else{#"pctLvlSlat"
      $slat = defined $a[3] ? $a[3] : "noChng";
      $lvl  = $a[2];
    }
    
    #--- calc slat----
    if    ($slat eq "old")   {$pslat = "C9"}
    elsif ($slat eq "noChng"){$pslat = "CA"}
    else{                     $slat =~ s/(\d*\.?\d*).*/$1/;
          return "Value $a[2] not allowed for slat" if ($slat > 100);
                              $pslat = sprintf("%02X",$slat*2);
      CUL_HM_UpdtReadSingle($hash,"levelSlat","set_".$slat,1);
    }
    
    #--- calc level----
    if    ($lvl eq "old")   {$plvl = "C9"}
    elsif ($lvl eq "noChng"){$plvl = "CA"}
    else{
      my $lvlInv          = (AttrVal($name, "param", "") =~ m/levelInverse/) ? 1 : 0;
      my($lvlMin,$lvlMax) = split",",AttrVal($name, "levelRange", "0,100");
      $lvl = $lvlMin + $lvl*($lvlMax-$lvlMin)/100; # relativ to range
      $lvl = ($lvl > $lvlMax) ? $lvlMax
                              : (($lvl <= $lvlMin)?0:$lvl);
      $lvl =~ s/(\d*\.?\d*).*/$1/;
      $plvl = sprintf("%02X",(($lvlInv) ? 100-$lvl : $lvl)*2);
      CUL_HM_UpdtReadSingle($hash,"level","set_".$lvl,1);
      $state = "set_".$lvl;
    }

    #--- execute----
    CUL_HM_PushCmdStack($hash,"++$flag"."11$id$dst"."80${chn}$plvl$pslat");
  }
  
  elsif($cmd eq "stop") { #####################################################
    delete $hash->{helper}{dlvl};#stop desiredLevel supervision
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
      return " too many entries in repPeers" if (int(@rPeer) > 36);
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
           if ($roleC && $chn ne "12");
    my %symbol=(off => 0x0000,
                bulb =>0x0100,switch =>0x0200,window   =>0x0400,door=>0x0800,
                blind=>0x1000,scene  =>0x2000,phone    =>0x4000,bell=>0x8000,
                clock=>0x0001,arrowUp=>0x0002,arrowDown=>0x0004);
    my %light=(off=>0,on=>1,slow=>2,fast=>3);
    my %unit=(off =>0,Proz=>1,Watt=>2,x3=>3,C=>4,x5=>5,x6=>6,x7=>7,
              F=>8,x9=>9,x10=>10,x11=>11,x12=>12,x13=>13,x14=>14,x15=>15);

    my @symbList = split(',',$symb);
    my $symbAdd = 0;
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

    $symbAdd |= 0x0008 if ($c eq "comma");
    $symbAdd |= ($unit{$u} * 16);

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
      if ($roleD){# command called for a device, not a channel
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
    elsif($md =~ m/^HM-OU-CFM?-PL/){
      my %color = (redL =>18,greenL =>34,orangeL =>50,
                   redS =>17,greenS =>33,orangeS =>49,
                   pause=>01);
      my @itemList = split(',',$a[2]);
      my $repeat = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt = int(@itemList);
      return "no more then 10 entries please"      if ($itemCnt>10);
      return "at least one entry must be entered"  if ($itemCnt<1);
      return "repetition $repeat out of range [1..255]"
          if($repeat < 1 || $repeat > 255);
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
    elsif($md =~ m/^HM-OU-CFM?-TW/){
      my %color = (redL =>18,greenL =>34,yellowL =>50,blueL =>66, violettL => 82, cyanL => 98, whiteL =>114,
                   redS =>17,greenS =>33,yellowS =>49,blueS =>65, violettS => 81, cyanS => 97, whiteS =>113,
                   pause=>2);
      my @itemList = split(',',$a[2]);
      my $repeat   = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $duration = (defined $a[4] && $a[4] =~ m/^(\d+)$/)?$a[4]:10800;
      my $itemCnt  = int(@itemList);
      
      return "enter at least one and up to 10 items"      if ($itemCnt  < 1 || $itemCnt  > 10);
      return "repetition $repeat out of range [1..255]"   if ($repeat   < 1 || $repeat   > 255);
      return "duration $duration out of range [1..10800]" if ($duration < 1 || $duration > 10800);
      
      my $msgBytes = sprintf("01%02X",$repeat);
      foreach my $led (@itemList){        
        return "'$led' unknown. use: ".join(" ",sort keys(%color)) if (!$color{$led} );# wrong parameter;
        $msgBytes .= sprintf("%02X",$color{$led});
      }
      $msgBytes .= "01" if ($itemCnt == 1 && $repeat == 1);#add pause to term LED
      # need to fill up empty locations  for LED channel
      $msgBytes = substr($msgBytes."00000000000000000000",0,(10+2)*2);
     
      if	($duration < 10800) {
        $msgBytes .= sprintf("%02X%02X",($duration & 0x00ff), ($duration & 0xff00)>>8);
      }
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes);
    }
    else{
      return "device for command cannot be identified";
    }
  }
  elsif($cmd eq "brightCol") { ################################################
    my (undef,undef,$bright,$colVal,$duration,$ramp) = @a; #date prepared extention to entdate
    return "cmd requires brightness[0..100] step 0.5, color[0..100] step 0.5, duration, ramptime" if (!defined $ramp);
    return "please enter the duration in seconds"                                                 if (!defined $duration || $duration !~ m/^[+-]?\d+(\.\d+)?$/);
    ($bright,$colVal) = (int($bright*2),int($colVal*2));# convert percent to [0..200]
    return "obey range for brightness[0..100] color[0..100]" if (   $bright < 0 or $bright > 200 
                                                                 or $colVal < 0 or $colVal > 200);
    my $tval = CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
    $ramp = CUL_HM_encodeTime16($ramp);
    $hash->{helper}{dlvl} = $colVal;
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.
                           sprintf("%02X%02X",$bright,$colVal).$ramp.$tval);
  }
  elsif($cmd eq "color") { ####################################################
    my (undef,undef,$colVal) = @a; #date prepared extention to entdate
    return "cmd requires color[0..100] step 0.5" if (!defined $colVal 
                                                ||$colVal < 0 ||$colVal > 100);
    $colVal = int($colVal*2);# convert percent to [0..200]
    $hash->{helper}{dlvl} = $colVal;
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.
                           sprintf("%02X",$colVal)."00A0");
  }
  elsif($cmd eq "brightAuto") { ###############################################
    my (undef,undef,$bright,$colProg,$min,$max,$duration,$ramp) = @a; #date prepared extention to entdate
    return "please enter the duration in seconds"
          if (defined $duration && $duration !~ m/^[+-]?\d+(\.\d+)?$/);
    return "at least bright and colorprogramm need to be set" if (!defined $colProg);

    $bright = int($bright*2);
    my $tval;
    $tval = (!defined $duration) ? "" : CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
    $ramp = (!defined $ramp)     ? "" : CUL_HM_encodeTime16($ramp)    ;
    $min  = (!defined $min)      ? "" : sprintf("%02X",$min)          ;
    $max  = (!defined $max)      ? "" : sprintf("%02X",$max)          ;

    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'81'.$chn.
                           sprintf("%02X%02X",$bright,$colProg).$min.$max.$ramp.$tval);
  }
  elsif($cmd eq "colProgram") { ###############################################
    my (undef,undef,$colProg) = @a; #date prepared extention to entdate
    return "cmd requires a colorProgram[0..255]" if (!defined $colProg 
                                                     ||$colProg < 0 ||$colProg > 255);

    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'02'.$chn.
                           sprintf("%02X",$colProg)."00A0");
  }
  elsif($cmd eq "playTone") { #################################################
    my $msg;
    if (!defined $a[2]){
      return "please enter parameter";
    }
    elsif ($a[2] eq 'replay'){
      $msg = ReadingsVal($chnHash->{NAME},".lastTone","");
    }
    else{
      my @itemList = split(',',$a[2]);
      my $repeat   = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt  = int(@itemList);
      my $volume   = (defined $a[4] && $a[4] =~ m/^(\d+)$/)?$a[4]:10;
      my $duration = (defined $a[5] && $a[5] =~ m/^(\d+\.)?\d+$/)?$a[5]:108000;
      return "no more than 10 entries please"                if ($itemCnt  > 10);
      return "repetition $repeat out of range [1..255]"      if ($repeat   < 1   || $repeat > 255);
      return "volume $volume out of range [0..10]"           if ($volume   < 0   || $volume > 10);
      return "duration $duration out of range [0.1..108000]" if ($duration < 0.1 || $duration > 108000);
      #<volume><multiply><MP3><MP3>
      my $msgBytes = sprintf("%02X%02X",$volume*20,$repeat);

      foreach my $mp3 (@itemList){
        return "input: $mp3 is not an integer below 255"
           if (!defined $mp3 || $mp3 !~ /^[+-]?\d+$/ || $mp3 > 255);
        $msgBytes .= sprintf("%02X",$mp3);
      }
      # need to fill up empty locations  for MP3 numbers
      $msgBytes = substr($msgBytes."00000000000000000000",0,(10+2)*2);

      # add duration as a float value
      #$duration = CUL_HM_decodeTime16($duration * 10);# need to be tested
      my $exponent = 0;
      my $mantisse = $duration * 10;
      while ($mantisse >= 2048) {
        $mantisse = $mantisse >> 1;
        $exponent++;
      }
      $duration = $mantisse << 5 | $exponent;
      $msgBytes .= sprintf("%04X", $duration);
      $msg = '++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes;
      CUL_HM_UpdtReadSingle($chnHash,".lastTone",$msg,0);
    }
    CUL_HM_PushCmdStack($hash,$msg) if ($msg);
  }

  elsif($cmd eq "displayWM" ) { ###############################################
    $state = "";
    
    # textNo color icon
    my $param = (scalar(@a)-2);
    if ($a[2] eq "help"){
      my $ret = "text :\n      <text> max 2 char";
      foreach (sort keys %disBtn){
        my (undef,$ch,undef,$ln) = unpack('A3A2A1A1',$_);
        $ch = sprintf("%02X",$ch);
        $ret .= "\n      $_ ->" 
                  .ReadingsVal( InternalVal($devName,"channel_$ch","no")
                                ,"text$ln","unkown");
      }
      $ret .= "\n      nc(no change), off(no text)"
             ."\ncolor:".join(",",sort keys %disColor)
             ."\n      nc(no change), off(no color)"
             ."\nicon :".join(",",sort keys %disIcon)
             ."\n      nc(no change), noIcon(no Icon)"
             ;
      return $ret;
    }

    my $type = $a[2] eq "short"?"s":"l";

    if(!defined $hash->{helper}{dispi}{$type}{"l1"}{d}){# setup if one is missing
      $hash->{helper}{dispi}{$type}{"l$_"}{d}=1 foreach (1,2,3,4,5,6);
    }

    if($a[3] =~ m/^line(.)$/){
      my $lnNr = $1;
      return "line number wrong - use 1..6" if($lnNr !~ m/[1-6]/);
      return "please add a text " if(!$a[4]);
      my $lnRd = "disp_$a[2]_l$lnNr";# reading assotiated with this entry
      my $dh = $hash->{helper}{dispi}{$type}{"l$lnNr"};

      if($a[4] =~ m/^e:/){ # equation
        $dh->{d} = 2; # mark as equation
        $dh->{exe} = $a[4];
        $dh->{exe} =~ s/^e://;
        ($dh->{txt},$a[5],$a[6]) = eval $dh->{exe};
        return "define eval must return 3 values:" if(!defined $a[6]);
      }
      else{
        if ($a[4] eq "off"){ #no display in this line
          $dh->{d} = 0; # mark as none
          delete $dh->{txt};
        }
        elsif($a[4] ne "nc"){ # new text
          return "text too long " .$a[4]   if (length($a[4])>12);
          $dh->{d} = 1; # mark as none
          $dh->{txt}=$a[4];
        }

        if($a[5] eq "off"){ # set color off
          delete $dh->{col};
        }
        elsif($a[5] ne "nc"){ # set new color
          return "color wrong $a[5] use:".join(",",sort keys %disColor) if (!defined $disColor{$a[5]});
          $dh->{col} = $a[5];
        }
        
        if($a[6] eq "noIcon"){ # new icon
          delete $dh->{icn};
        }
        elsif($a[6] ne "nc"){ # new icon
          return "icon wrong $a[6] use:".join(",",sort keys %disIcon)  if (!defined $disIcon{$a[6]});
          $dh->{icn} = $a[6];
        }
      }
    }
    else{
      return "not enough parameter - always use txtNo, color and icon in a set"
            if(($param-1) %3);
      for (my $cnt=3;$cnt<$param;$cnt+=3){ 
        my $lnNr = int($cnt/3);
        my $dh = $hash->{helper}{dispi}{$type}{"l$lnNr"};
        return "color wrong ".$a[$cnt+1]." use:".join(",",sort keys %disColor) if (!defined $disColor{$a[$cnt+1]});
        return "icon wrong " .$a[$cnt+2]." use:".join(",",sort keys %disIcon)  if (!defined $disIcon {$a[$cnt+2]});
        return "text too long " .$a[$cnt+0]   if (length($a[$cnt+0])>12);
        if    ($a[$cnt+0] eq "nc") {} # nc = no change
        elsif ($a[$cnt+0] eq "off"){ delete $dh->{txt}      } # off =  no text display
        else                       {$dh->{txt} = $a[$cnt+0];} # nc = no change

        $dh->{col} = $a[$cnt+1];
        $dh->{icn} = $a[$cnt+2];
        delete $dh->{icn} if ($a[$cnt+2] eq "noIcon");
      }
    }

    foreach my $t (keys %{$hash->{helper}{dispi}}){ # prepare the messages
      CUL_HM_calcDisWm($hash,$devName,$t);
    }
  }
  elsif($cmd eq "displayEP" ) { ###############################################
    $state = "displayEP";
    RemoveInternalTimer($name.":reWriteDisplay");# just in case param reWriteDisplay used
    my %disp_icons = (
       off    => '80', on => '81', open => '82', closed => '83'
      ,error  => '84', ok => '85', info => '86', newmsg => '87'
      ,svcmsg => '88'
      ,none   => ''
    );
    my %disp_sounds = (
       off        => 'C0', longlong   => 'C1', longshort  => 'C2'
      ,long2short => 'C3', short      => 'C4', shortshort => 'C5'
      ,long       => 'C6'
    );
    my %disp_signals = (
       off    => 'F0', red    => 'F1', green  => 'F2', orange => 'F3'
    );
    # msg: 'text,icon;text,icon;text,icon'
    my ($msg, $sound, $rep, $pause, $sig) = @a[2..$#a];

    # set defaults
    $msg   = ''    if (!defined ($msg));
    $sound = 'off' if (!defined ($sound) || !exists ($disp_sounds{$sound}));
    $sig   = 'off' if (!defined ($sig)   || !exists ($disp_signals{$sig} ));
    $rep   =       (!defined ($rep)? 1   :
                    ($rep > 15     ? 15  :
                    ($rep == 0     ? 16  :
                                     $rep)));
    $pause =        (!defined ($pause)?10 :
                    ($pause < 1      ?1  :
                    ($pause >160     ?160:
                                      $pause)));

    if($msg eq 'help'){ # display command info
      return      "command options:"
                 ."\n  line1,icon1:line2,icon2:line3,icon3 sound repeat pause signal"
                 ."\n  "
                 ."\n  line: 12 char text to be dispalyed. No change if empty."
                 ."\n  icon: per line: ".join(", ",keys(%disp_icons))
                 ."\n  sound: ".join(", ",keys(%disp_sounds))
                 ."\n  repeat: 1..16 default = 1"
                 ."\n  pause: 1..160 default = 10"
                 ."\n  signal: ".join(", ",keys(%disp_signals))
                 ."\n "
                 ."\n  check for param reWriteDisplayxx: "
                 ."\n  translate chars: "
                 ."\n    [ => Ä"      
                 ."\n    # => Ö"      	
                 ."\n    $ => Ü"      	
                 ."\n    { => ä"      	
                 ."\n    | => ö"      	
                 ."\n    } => ü"      	
                 ."\n    _ => ß"      	
                 ."\n    ] => &"      	
                 ."\n    ' => ="      	
                 ."\n    @ => ∨"      	
                 ."\n    > => ∧"      	
                 ."\n    ; => Sandwatch"
                 ; 
    }
    my $snd = '020A';
    # Lines are separated by semicolon, empty lines are supported
    my @disp_lines = (split (':', $msg.":::"),"","");# at least 3 entries - loop will use first 3
    my $lineNr=1;
    $evtDly = 1;
    foreach my $line (@disp_lines[0..2]) {# only 3 lines
      # Split line into text and icon part separated by comma

      $snd .= '12';# start text indicator
      my ($text, $icon); # add separator in case Icon is dismissed
      if (!defined $line || $line eq '') {
        $text =  ReadingsVal($name,"line${lineNr}_text","");
        $icon = ReadingsVal($name,"line${lineNr}_icon","off");
      }
      else{
        ($text, $icon) = split (',', $line.","); # add separator in case Icon is dismissed
      }
       
      # Hex code
      if ($text =~ /^0x[0-9A-F]{2}$/) {
        $snd .= substr($text,2,2);
      }
      # Predefined text code text0-9
      elsif ($text =~ /^text([0-9])$/) {
        $snd .= sprintf ("8%1X", $1);
      }
      # Convert string to hex codes
      else {
        $text =~ s/\\_/ /g;
        foreach my $ch (split ('', substr ($text, 0, 12))) {
          $snd .= sprintf ("%02X", ord ($ch));
        }
      }
    
      $snd .= '13'.$disp_icons{$icon} if ($disp_icons{$icon});
      $snd .= '0A';
      
      CUL_HM_UpdtReadBulk($hash,0,"line${lineNr}_text:$text"
                                 ,"line${lineNr}_icon:$icon");
      $lineNr++;
    }
    
    $snd .= '14'.$disp_sounds{$sound}.'1C';         # Sound
    $snd .= sprintf ("%02X1D", 0xD0+$rep-1);        # Repeat
    $snd .= sprintf ("E%01X16", int(($pause-1)/10));# Pause
    $snd .= $disp_signals{$sig}.'03';               # Signal
    CUL_HM_UpdtReadBulk($hash,0,"signal:$sig");
    CUL_HM_pushEvnts();

    CUL_HM_PushCmdStack($hash,"++${flag}11$id${dst}80${chn}$_") foreach (unpack('(A28)*',$snd));
  }  

  elsif($cmd =~ m/^(controlMode|controlManu|controlParty)$/) { ################
    $state = "";
    my $mode = $a[2];
    if ($cmd ne "controlMode"){
      $mode = substr($cmd,7);
      $mode =~ s/^Manu$/manual/;
      $a[2] = ($a[2] eq "off")?4.5:($a[2] eq "on"?30.5:$a[2]);
    }
    $mode = lc $mode;
    return "invalid $mode:select of mode [auto|boost|day|night] or"
          ." controlManu,controlParty"
                if ($mode !~ m/^(auto|manual|party|boost|day|night)$/);
    my ($temp,$party);
    if ($mode =~ m/^(auto|boost|day|night)$/){
      return "no additional params for $mode" if ($a[3]);
    }
    if($mode eq "manual"){
      my $t = $a[2] ne "manual"?$a[2]:ReadingsVal($name,"desired-temp",18);
      if ($md =~ m/CC-TC/){$t = ($t eq "off")?4.5:(($t eq "on" )?30.5:$t);}
      else                {$t = ($t eq "off")?5  :(($t eq "on" )?30  :$t);}
      return "temperatur for manual  4.5 to 30.5 C"
                if ($t < 4.5 || $t > 30.5);
      $temp = $t*2;
    }
    elsif($mode eq "party"){
      return  "use party <temp> <from-time> <from-date> <to-time> <to-date>\n"
             ."temperatur: 5 to 30 C\n"
             ."date format: party 10 03.8.13 11:30 5.8.13 12:00"
                if (!$a[2] || $a[2] < 5 || $a[2] > 30 || !$a[6] );
      $temp = $a[2]*2;
      # party format 03.8.13 11:30 5.8.13 12:00
      my ($sd,$sm,$sy) = split('[\.-]',$a[3]);
      my ($sh,$smin)   = split(':' ,$a[4]);
      my ($ed,$em,$ey) = split('[\.-]',$a[5]);
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
    my %mCmd = (auto=>0,manual=>1,party=>2,boost=>3,day=>4,night=>5);
    my $msg = '8'.($mCmd{$mode}).$chn;
    $msg .= sprintf("%02X",$temp) if ($temp);
    $msg .= $party if ($party);
    my @teamList = ( CUL_HM_getPeers(CUL_HM_id2Name($dst."05"),"IDs") # peers of RT team 
                    ,CUL_HM_getPeers(CUL_HM_id2Name($dst."02"),"IDs") # peers RT/TC team
                    ,CUL_HM_name2Id($name)                            # myself
                    );
    foreach my $tId (@teamList){
      my $teamC = CUL_HM_id2Name($tId);
      $tId = substr($tId,0,6);
      my $teamD = CUL_HM_id2Name($tId);
      next if (!defined $defs{$teamC} );
      CUL_HM_UpdtReadSingle($defs{$teamC},"controlMode","set_".$mode,1);
      CUL_HM_PushCmdStack($defs{$teamD},'++'.$flag.'11'.$id.$tId.$msg);
      if (   $tId ne $dst 
          && CUL_HM_getRxType($defs{$teamD}) & 0x02){
        # burst device - we need to send immediately
        CUL_HM_SndCmd($defs{$teamD},"++B112$id".substr($tId,0,6));
      }
    }
  }
  elsif($cmd eq "desired-temp") { #############################################
    if ($md =~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
      my $temp = ($a[2] eq "off")?9:($a[2] eq "on"?61:$a[2]*2);
      return "invalid temp:$a[2]" if($temp <9 ||$temp > 61);
      $temp = sprintf ("%02X",$temp);
      CUL_HM_PushCmdStack($hash,'++'.$flag."11$id$dst"."8604$temp");

      my $idTch = ($md =~ m/^HM-CC-RT-DN/ ? $dst."05" : $dst."02");
      my @teamList = ( CUL_HM_name2Id($name)                                      # myself
                      );
      push @teamList,( CUL_HM_getPeers(CUL_HM_id2Name($dst."05"),"IDs") # peers of RT team
                      ,CUL_HM_getPeers(CUL_HM_id2Name($dst."02"),"IDs") # peers RT/TC team
                     ) if($md =~ m/^HM-CC-RT-DN/) ;
      foreach my $tId (grep !/00000000/,@teamList){
        $tId = substr($tId,0,6);
        my $teamD = CUL_HM_id2Name($tId);
        my $teamCh = (AttrVal($teamD,"model","") =~ m/HM-CC-RT-DN/) ? "04" #what is the controls channel of the peer?
                                                                    : "02";
        my $teamC = CUL_HM_id2Name($tId.$teamCh);
        
        next if (!defined $defs{$teamC} );       
        CUL_HM_PushCmdStack($defs{$teamD},'++'.$flag."11$id$tId"."86$teamCh$temp");
        CUL_HM_UpdtReadSingle($defs{$teamC},"state",$state,1);
        if (   $tId ne $dst 
            && CUL_HM_getRxType($defs{$teamD}) & 0x02){
          # burst device - we need to send immediately
          CUL_HM_SndCmd($defs{$teamD},"++B112$id".substr($tId,0,6));
        }
      }
    }
    else{
      my $temp = CUL_HM_convTemp($a[2]);
      return $temp if($temp =~ m/Invalid/);
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'0202'.$temp);
      my $chnHash = CUL_HM_id2Hash($dst."02");
      my $mode = ReadingsVal($chnHash->{NAME},"R-controlMode","");
      $mode =~ s/set_//;#consider set as given
      CUL_HM_UpdtReadSingle($chnHash,"desired-temp-cent",$a[2],1)
            if($mode =~ m/central/);
    }
  }
  elsif($cmd =~ m/^tempList(...)$/) { ##################################### reg
    my $wd = $1;
    $state= "";
    my ($list,$addr,$prgChn);
    if ($md =~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
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
    if (defined($a[2]) && $a[2] =~ m/^(prep|exec)$/){
      $prep = $a[2];
      splice  @a,2,1;#remove prep
    }
    if ($md =~ m/^HM-TC-IT-WM-W-EU/ && $a[2] =~ m/^p([123])$/){
      $list +=  $1 - 1;
      splice  @a,2,1;#remove list
    }
    return "To few arguments"                if(@a < 4);
    return "To many arguments, max 13 pairs" if(@a > 28 && $md =~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/);
    return "To many arguments, max 24 pairs" if(@a > 50 && $md !~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/);
    return "Bad format, use HH:MM TEMP ..."  if(@a % 2);
    return "Last time spec must be 24:00"    if($a[@a-2] ne "24:00");

    my ($data,$msg) = ("","");
    for(my $idx = 2; $idx < @a; $idx += 2) {
      return "$a[$idx] is not in HH:MM format"
                                if($a[$idx] !~ m/^([0-2]\d):([0-5]\d)/);
      my ($h, $m) = ($1, $2);
      my ($hByte,$lByte);
      my $temp = $a[$idx+1];
      if ($md =~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
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
    CUL_HM_PushCmdStack($hash,"++803F$id${dst}0202$s2000");
  }
  elsif($cmd =~ m/^(valvePos|virtTemp|virtHum)$/) { ###########################
    my $valu = $a[2];

    my %lim = (valvePos =>{min=>0  ,max=>99 ,rd =>"valvePosTC" ,u =>" %"},
               virtTemp =>{min=>-20,max=>50 ,rd =>"temperature",u =>""  },
               virtHum  =>{min=>0  ,max=>99 ,rd =>"humidity"   ,u =>""  },);
    if ($md eq "HM-CC-VD"){
      return "level between $lim{$cmd}{min} and $lim{$cmd}{max} allowed"
             if ($valu !~ m/^[+-]?\d+\.?\d+$/||
                 $valu > $lim{$cmd}{max}||$valu < $lim{$cmd}{min} );
      CUL_HM_PushCmdStack($hash,'++A258'.$id.$dst
                                ."00".sprintf("%02X",($valu * 2.56)%256));
    }
    else{
      my $u = $lim{$cmd}{u};
      if ($valu eq "off"){
        $u = "";
        if ($cmd eq "virtHum") {$hash->{helper}{vd}{vinH} = "";}
        else                   {$hash->{helper}{vd}{vin}  = "";}
        if ((!$hash->{helper}{vd}{vinH} || $hash->{helper}{vd}{vinH} eq "") && 
            (!$hash->{helper}{vd}{vin}  || $hash->{helper}{vd}{vin}  eq "") ){
          $state = "$cmd:stopped";
          RemoveInternalTimer("valvePos:$dst$chn");# remove responsePending timer
          RemoveInternalTimer("valveTmr:$dst$chn");# remove responsePending timer
          delete($hash->{helper}{virtTC});
        }
      }
      if ($hash->{helper}{virtTC} || $valu ne "off") {
        if ($valu ne "off"){
          return "level between $lim{$cmd}{min} and $lim{$cmd}{max} or 'off' allowed"
               if ($valu !~ m/^[+-]?\d+\.?\d*$/||
                   $valu > $lim{$cmd}{max}||$valu < $lim{$cmd}{min} );
          if ($cmd eq "virtHum") {$hash->{helper}{vd}{vinH} = $valu;}
          else                   {$hash->{helper}{vd}{vin}  = $valu;}
        }
        $attr{$devName}{msgRepeat} = 0;#force no repeat
        if ($cmd eq "valvePos"){
          my @pId = CUL_HM_getPeers($name,"IDs");
          return "virtual TC support one VD only. Correct number of peers"
            if (scalar @pId != 1);
          my $ph = CUL_HM_id2Hash($pId[0]);
          return "peerID $pId[0] is not assigned to a device " if (!$ph);
          $hash->{helper}{vd}{typ} = 1; #valvePos
          my $idDev = substr($pId[0],0,6);
          $hash->{helper}{vd}{nDev}  =  CUL_HM_id2Name($idDev);
          $hash->{helper}{vd}{id}    = $modules{CUL_HM}{defptr}{$pId[0]}
                                                ?$pId[0]
                                                :$idDev;
          $hash->{helper}{vd}{cmd} = "A258$dst$idDev";
          CUL_HM_UpdtReadBulk($ph,1,
                           "state:set_$valu %",
                           "ValveDesired:$valu %");
          $hash->{helper}{vd}{val} = sprintf("%02X",($valu * 2.56)%256);
          $state = "ValveAdjust:$valu %";
        }
        else{#virtTemp || virtHum
          $hash->{helper}{vd}{typ} = 2; #virtTemp
          $hash->{helper}{vd}{cmd} = "8470$dst"."000000";
          my $t = $hash->{helper}{vd}{vin}?$hash->{helper}{vd}{vin}:0;
          $t *=10;
          $t -= 0x8000 if ($t < 0);
          $hash->{helper}{vd}{val} = sprintf("%04X", $t & 0x7fff);
          $hash->{helper}{vd}{val} .= sprintf("%02X", $hash->{helper}{vd}{vinH})
               if ($hash->{helper}{vd}{vinH} && $hash->{helper}{vd}{vinH} ne "");
        }
        $hash->{helper}{vd}{idh} = hex(substr($dst,2,2))*20077;
        $hash->{helper}{vd}{idl} = hex(substr($dst,4,2))*256;
        ($hash->{helper}{vd}{msgCnt},$hash->{helper}{vd}{next}) = 
                    split(";",ReadingsVal($name,".next","0;".gettimeofday())) if(!defined $hash->{helper}{vd}{next});
        if (!$hash->{helper}{virtTC}){
          my $pn = CUL_HM_id2Name($hash->{helper}{vd}{id});
          $hash->{helper}{vd}{ackT} = ReadingsTimestamp($pn, "ValvePosition", "")
                                          if(!defined $hash->{helper}{vd}{ackT});
          $hash->{helper}{vd}{miss}   = 0 if(!defined $hash->{helper}{vd}{miss});
          $hash->{helper}{vd}{msgRed} = 0 if(!defined $hash->{helper}{vd}{msgRed});

          $hash->{helper}{virtTC}   = ($cmd eq "valvePos")?"03":"00";
          CUL_HM_UpdtReadSingle($hash,"valveCtrl","init",1)                     if ($cmd eq "valvePos");
          $hash->{helper}{vd}{next} = ReadingsVal($name,".next",gettimeofday()) if (!defined $hash->{helper}{vd}{next});
          CUL_HM_valvePosUpdt("valvePos:$dst$chn");
        }
        $hash->{helper}{virtTC} = ($cmd eq "valvePos")?"03":"00";
      }
      CUL_HM_UpdtReadSingle($hash,$lim{$cmd}{rd},$valu.$u,1);
    }
  }

  elsif($cmd eq "keydef") { ############################################### reg
    if (     $a[3] eq "tilt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B220D838B228D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "close")     {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B550D838B558D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "closed")    {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0F008F00");        #offLevel (also thru register)
    } elsif ($a[3] eq "bolt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0FFF8FFF");        #offLevel (also thru register)
    } elsif ($a[3] eq "speedclose"){CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("23%02XA3%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } elsif ($a[3] eq "speedtilt") {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("22%02XA2%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } else                         {return 'unknown argument '.$a[3];
    }
  }
  elsif($cmd =~ m/^(teamCall|teamCallBat)$/) { ################################
    $state = "";
    my $sId = $roleV ? $dst : $id;  # ID of cmd-source must not be a physical
                                    # device. It can cause trouble with 
                                    # subsequent alarming 
    $hash->{TESTNR} = (($a[2] && $a[2] ne "noArg") ? $a[2] : ($hash->{TESTNR} + 1))%255;
    if ($fkt eq "sdLead1"){# ($md eq "HM-CC-SCD")
      my $tstNo = sprintf("%02X",$hash->{TESTNR});
      my $val = ($cmd eq "teamCallBat")? "80" : "00";
      CUL_HM_PushCmdStack($hash, "++9440".$dst.$sId.$val.$tstNo);
      CUL_HM_parseSDteam("40",$dst,$sId,$val.$tstNo);
    }
    else {#($md eq "HM-SEC-SD-2"){
           # 96 switch on- others unknown
      my $msg = CUL_HM_generateCBCsignature($hash, 
                                sprintf("++1441$dst${sId}01%02X9600",$hash->{TESTNR}));
      CUL_HM_PushCmdStack($hash, $msg) foreach (1..6);
      CUL_HM_parseSDteam_2("41",$dst,$sId,substr($msg, 18));
    }
  }
  elsif($cmd =~ m/^alarm(.*)/) { ##############################################
    $state = "";
    
    my $sId = $roleV ? $dst : $id;  # ID of cmd-source must not be a physical
                                    # device. It can cause trouble with 
                                    # subsequent alarming 
    if ($fkt eq "sdLead1"){# ($md eq "HM-CC-SCD")
      my $p = (($1 eq "On")?"0BC8":"0C01");
      my $msg = "++9441".$dst.$sId."01".$p;
      CUL_HM_PushCmdStack($hash, $msg) foreach (1..3);# 3 reps fpr non-ack msg 
      CUL_HM_parseSDteam("41",$dst,$sId,"01".$p);
    }
    else{#($md eq "HM-SEC-SD-2"){
      my $p = (($1 eq "On")?"C6":"00");
      $hash->{TESTNR} = ($hash->{TESTNR} + 1)%255;
 
      my $msg = CUL_HM_generateCBCsignature($hash, 
                              sprintf("++1441$dst${sId}01%02X${p}00",$hash->{TESTNR}));
      
      CUL_HM_PushCmdStack($hash, $msg) foreach (1..6);
      CUL_HM_parseSDteam_2("41",$dst,$sId,substr($msg, 18));
   }
  }

  elsif($cmd =~ m/^(press|event)/) { #####################################
    #press          =>"[(long|{short})] [(-peer-|{all})] [(-repCount-|{0})] [(-repDelay-|{0.25})]" 
    #press          =>"[(long|{short})] [(noBurst|{Burst})] [(-peer-|{all})] [(-repCount-|{0})] [(-repDelay-|{0.25})]" 
    #press[LS]      =>"-peer-"
    #event[LS]      =>"-peer- -cond-"

    my ($trig,$type,$peer      ,$cond,$mode,$modeCode,$repCnt,$repDly,$Burst) = 
       ($1   ,"S"  ,"self".$chn,""   ,0    ,"40"     ,1      ,0.25   ,1)          ;#defaults
    
    if ($cmd =~ m/^(press|event)(L|S)/){# set short/long and remove from Params
      $type = $2;
      foreach(2,3,4,5,6){$a[$_] = "noArg" if(!defined $a[$_])}
    }
    else{
      if   ($a[2] eq "long") {$type = "L";splice @a,2,1;}
      elsif($a[2] eq "short"){$type = "S";splice @a,2,1;}
    }

    $peer = $a[2] if ($a[2] ne "noArg");
    splice @a,2,1; # remove long/short or  (no)Burst
   
    if ($roleV){ # burst (just for virtuals) could be given
      $Burst = 0 if($a[2] eq "noBurst");
      splice @a,2,1; # remove long/short or  (no)Burst
    }
    
    if ($type eq "event"){# set condition for event (blank for press)
      $modeCode = "41";
      if ($a[2] < 0 || $a[2] > 255){
        $cond = sprintf("%02X",$a[2]);
      }
      else{
        return "event requires a condition between 0 and 255";
      }
    }
    else{# type = press
      if($type eq "L"){# set timing if releated
        $mode = 64;
        if($a[2] ne "noArg"){
          return "repeat count must be numeric:$a[2] is illegal" if ($a[2] !~ m/^\d*$/);
          $repCnt = $a[2];
        }
        splice @a,2,1; # remove repeat count

        if($a[2] ne "noArg"){
          return "repeatDelay count must be numeric e.g. 0.25:$a[2] is illegal" if ($a[2] !~ m/^\d*\.?\d+$/);
          $repDly = $a[2];
        }
        splice @a,2,1; # remove repeat count
      }
    }

    $hash->{helper}{count} = (!$hash->{helper}{count} ? 1 
                                                      : $hash->{helper}{count}+1)%256;
    if ($roleV){#serve all peers of virtual button
      $peer = ".*" if ($peer eq "all");
      my @peerLchn = map{CUL_HM_name2Id($_)}
                     grep/$peer/,
                     CUL_HM_getPeers($name,"IDs");
      my @peerList = grep !/000000/,grep !/^$/
                 ,CUL_HM_noDup(map{substr($_,0,6)} @peerLchn); # peer device IDs - clean

      my $pc =  sprintf("%02X%02X",hex($chn)+$mode,$hash->{helper}{count});# msg end
      my $snd = 0;
      my @trigDest;
      foreach my $peerDev (@peerList){# send once to each device (not each channel)
        my $pHash = CUL_HM_id2Hash($peerDev);
        next if (   !$pHash 
                 || !$pHash->{helper}{role}
                 || !$pHash->{helper}{role}{prs});
        my $rxt = CUL_HM_getRxType($pHash);
        $rxt = $rxt & 0x7d if (!$Burst); # if noBurst is requested just stript this options
        my $peerFlag = ($rxt & 0x02) ? "B4" : "A4"; #burst
        CUL_HM_PushCmdStack($pHash,"++${peerFlag}$modeCode$dst$peerDev$pc");
        $snd = 1;
        foreach my $pCh(grep /$peerDev/,@peerLchn){
          my $n = CUL_HM_id2Name($pCh);
          next if (!$n);
          $n =~ s/_chn-\d\d$//;
          delete $defs{$n}{helper}{dlvl};#stop desiredLevel supervision
          CUL_HM_stateUpdatDly($n,10);
          push @trigDest,$n;
        }
        if ($rxt & 0x80){#burstConditional
          CUL_HM_SndCmd($pHash, "++B112$id".$peerDev);
        }
        else{
          CUL_HM_ProcessCmdStack($pHash);
        }
      }
      if(!$snd){# send 2 broadcast if no relevant peers 
        push @trigDest,"broadcast";
        CUL_HM_SndCmd($hash,"++8440${dst}000000$pc");
      }
      my $readVal =  ($type eq "S" ? "short":"long")
                    .($Burst       ? ""     :" :noBurst")
                    .($type eq "S" ? ""     :" count:$repCnt dly:$repDly")
                    ." cnt: $hash->{helper}{count}"
                    ;
      CUL_HM_UpdtReadBulk($hash,1,map{"${trig}_$_:$readVal"} @trigDest);
    }
    else{#serve internal channels for actor
      my ($pDev,$pCh) = unpack 'A6A2',CUL_HM_name2Id($peer,$devHash)."01";
      return "button cannot be identified" if (!$pCh);
      delete $hash->{helper}{dlvl};#stop desiredLevel supervision
      my $msg = sprintf("3E%s%s%s%s%02X%02X%s",
                                     $id,$dst,$pDev,$modeCode
                                    ,hex($pCh)+$mode
                                    ,$hash->{helper}{count}
                                    ,$cond);
      for (my $cnt = 1;$cnt < $repCnt; $cnt++ ){
        CUL_HM_SndCmd($hash, "++80$msg"); # send direct Wont work for burst!
        select(undef, undef, undef, $repDly);
      }
      CUL_HM_PushCmdStack($hash, "++${flag}$msg"); # send thru commandstack
      CUL_HM_stateUpdatDly($name,10);#check status after 10 sec latest
   }
  }
  elsif($cmd =~ m/^trg(Press|Event)(.)/) { ####################################
    $state = "";
    my ($trig,$type) = ($1,$2);
    my $peer = $a[2];
    $peer = "." if ($peer =~ m/(noArg|all)/);
    if($trig eq "Event"){
      return "no condition level defined" if (!defined $a[3]);
      return "condition $a[3] out of range. limit to 0..255" if ($a[3]<0 || $a[3]>255);
    }
    my @peers = ();
    foreach my $peerItem (grep/$peer/,CUL_HM_getPeers($name,"NamesExt")){
      if   ($defs{$peerItem}{helper}{role}{vrt}){
      }
      elsif($defs{$peerItem}{helper}{role}{chn}){
        push @peers,$peerItem;  
      }
      elsif($defs{$peerItem}{helper}{role}{dev}){
        push @peers,CUL_HM_getAssChnNames($peerItem);  
      }
    }
    my $peerCnt = 0;
    foreach my $peerSet(@peers){
      next if (!defined($peerSet) || !defined($defs{$peerSet}) );
      next if (!defined $defs{$peerSet}{helper}{cmds}{cmdLst}{press});
      if($trig eq "Event"){CUL_HM_Set($defs{$peerSet},$peerSet,"event$type",$name,$a[3]);}
      else                {CUL_HM_Set($defs{$peerSet},$peerSet,"press$type",$name);}
      $peerCnt++;
    }
    return "no target peer found" if(!$peerCnt);

  }
  elsif($cmd eq "postEvent") { ################################################
    my (undef,undef,$cond) = @a;
    my $cndNo;
    if ($cond =~ m/[+-]?\d+/){
      return "condition value:$cond above 255 illegal" if ($cond > 255);
      $cndNo = $cond;
    }
    else{
      my @keys;
      if ($chnHash->{helper}{lm}){
        foreach (keys %{$chnHash->{helper}{lm}}){
          if ($chnHash->{helper}{lm}{$_} eq $cond){
            $cndNo = $_;
            last;
          }
          push @keys,$chnHash->{helper}{lm};
        }
      }
      else{
        foreach my $tp (keys %lvlStr){
          foreach my $mk (keys %{$lvlStr{$tp}}){
            foreach (keys %{$lvlStr{$tp}{$mk}}){
              $cndNo = hex($_) if ($cond eq $lvlStr{$tp}{$mk}{$_});
              push @keys,$lvlStr{$tp}{$mk}{$_};
            }
          }
        }
      }
      return "cond:$cond not allowed. choose one of:[0..255],"
            .join(",",sort @keys)
        if (!defined $cndNo);
    }
    my $pressCnt = (!$hash->{helper}{count}?1:$hash->{helper}{count}+1)%256;
    $hash->{helper}{count}=$pressCnt;# remember for next round

    my @peerLChn = CUL_HM_getPeers($name,"IDs");
    my @peerDev;
    push (@peerDev,substr($_,0,6)) foreach (@peerLChn);
    @peerDev = CUL_HM_noDup(@peerDev);#only once per device!

    push @peerDev,'000000' if (!@peerDev);#send to broadcast if no peer
    foreach my $peer (@peerDev){
      my $pHash = CUL_HM_id2Hash($peer);
      my $rxt = CUL_HM_getRxType($pHash);
      my $peerFlag = ($rxt & 0x02)?"B4":"A4";#burst
      CUL_HM_PushCmdStack($pHash, sprintf("++%s41%s%s%02X%02X%02X"
                     ,$peerFlag,$dst,$peer
                     ,hex($chn)
                     ,$pressCnt
                     ,$cndNo));
      if ($rxt & 0x80){#burstConditional
        CUL_HM_SndCmd($pHash, "++B112$id".substr($peer,0,6));
      }
      else{
        CUL_HM_ProcessCmdStack($pHash);
      }
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
  elsif($cmd eq "fwUpdate") { #################################################
    if ($a[2] eq "onlyEnterBootLoader") {
      Log3 $name,2,"CUL_HM entering bootloader for $name";
      CUL_HM_SndCmd($hash, sprintf("%02X",$modules{CUL_HM}{helper}{updateNbr})
                                  ."3011$id${dst}CA");
      return ("",1);
    }
    return "no filename given" if (!$a[2]);
#    return "only thru CUL " if (!$hash->{IODev}->{TYPE}
#                                 ||($hash->{IODev}->{TYPE} ne "CUL"));
    # todo add version checks of CUL
    my ($fName,$pos,$enterBL) = ($a[2],0,($a[3] ? $a[3]+0 : 10));
    my @imA; # image array: image[block][msg]

    return "Illegal waitTime $enterBL - enter a value between 10 and 300" 
         if ($enterBL < 10 || $enterBL>300);    

    open(aUpdtF, $fName) || return("Can't open $fName: $!");
    while(<aUpdtF>){
      my $line = $_;
      my $fs = length($line);
      while ($fs>$pos){
        my $bs = hex(substr($line,$pos,4))*2+4;	  
        return "file corrupt. length:$fs expected:".($pos+$bs) 
              if ($fs<$pos+$bs);
        my @msg = grep !/^$/,unpack '(A60)*',substr($line,$pos,$bs);
        push @imA,\@msg; # image[block][msg]
        $pos += $bs;
      }
    }
    close(aUpdtF);
    # --- we are prepared start update---
    CUL_HM_protState($hash,"CMDs_FWupdate");
    $modules{CUL_HM}{helper}{updating} = 1;
    $modules{CUL_HM}{helper}{updatingName} = $name;
    $modules{CUL_HM}{helper}{updateData} = \@imA;
    $modules{CUL_HM}{helper}{updateStep} = 0;
    $modules{CUL_HM}{helper}{updateDst} = $dst;
    $modules{CUL_HM}{helper}{updateId} = $id;
    $modules{CUL_HM}{helper}{updateNbr} = 10;
    Log3 $name,2,"CUL_HM fwUpdate started for $name";
    CUL_HM_SndCmd($hash, sprintf("%02X",$modules{CUL_HM}{helper}{updateNbr})
                        ."3011$id${dst}CA");
                        
    $hash->{helper}{io}{newChnFwUpdate} = $hash->{helper}{io}{newChn};#temporary hide init message
    $hash->{helper}{io}{newChn} = "";

    InternalTimer(gettimeofday()+$enterBL,"CUL_HM_FWupdateEnd","fail:notInBootLoader",0);
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim",$dst."00000000",0);
  }

  elsif($cmd eq "peerIODev") { ################################################
    # peerIODev [IO] <chn> [set|unset]...
    $state = "";
    return "command requires parameter" if (!$a[2]);
    my ($ioId,$ioCh,$set) = ($id,$a[2],'set'); #set defaults
    if ($defs{$a[2]}){ #IO device given
      $ioId =  AttrVal($a[2],"hmId","");
      return "$a[2] not valid, attribut hmid not set" 
            if($ioId !~ m/^[0-9A-F]{6}$/);
      splice @a,2,1;
      $ioCh = $a[2];
    }
    $set = $a[3] if ($a[3]);
    $ioCh = sprintf("%02X",$ioCh);
    return "No:$ioCh invalid. Number must be <=50"  if (!$ioCh || $ioCh !~ m/^(\d*)$/ || $ioCh > 50);
    return "option $set unknown - use set or unset" if ($set != m/^(set|unset)$/);
    $set = ($set eq "set")?"01":"02"; 
    CUL_HM_PushCmdStack($hash,"++${flag}01$id${dst}$chn$set$ioId${ioCh}00");
  }
  elsif($cmd eq "peerChan") { ############################################# reg
    #peerChan <btnN> <device> ... [single|dual] [set|unset] [actor|remote|both]
    my ($bNo,$peerN,$single,$set,$target) = ($a[2],$a[3],($a[4]?$a[4]:"dual"),
                                                         ($a[5]?$a[5]:"set"),
                                                         ($a[6]?$a[6]:"both"));

    $state = "";
    if ($roleD){
      $bNo = 1 if ($bNo == 0 && $roleC); # role device and channel => button=1
      return "$bNo is not a button number"                        if($bNo < 1);
    }
    
    my $peerId = CUL_HM_name2Id($peerN);
    return "please enter peer"                                    if(!$peerId);
    return "peer is not a channel"                                if(!$defs{$peerN}{helper}{role}{chn});
    $peerId .= "01" if( length($peerId) == 6);

    my @pCh;
    my ($peerHash,$dSet,$cmdB);
    my $peerDst = substr($peerId,0,6);
    my $pmd     = AttrVal(CUL_HM_id2Name($peerDst), "model"  , "");

    if ($md =~ m/^HM-CC-RT-DN/ && $chn eq "05" ){# rt team peers cross from 05 to 04
      @pCh = (undef,"04","05");
      $chn = "04";
      $single = "dual";
      $dSet = 1;#Dual set - set 2 channels for "remote"
    }
    else{ # normal devices
      $pCh[1] = $pCh[2] = substr($peerId,6,2);
    }
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst.$pCh[1]}if ($modules{CUL_HM}{defptr}{$peerDst.$pCh[1]});
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst}        if (!$peerHash);
    return "$peerN not a CUL_HM device"                           if(   ($target ne "remote") 
                                                                     && (!$peerHash || $peerHash->{TYPE} ne "CUL_HM")
                                                                     &&  $defs{$devName}{IODev}->{NAME} ne $peerN);
    return "$single must be single, dual or reverse"              if($single !~ m/^(single|dual|reverse)$/);
    return "$set must be set or unset"                            if($set    !~ m/^(set|unset)$/);
    return "$target must be [actor|remote|both]"                  if($target !~ m/^(actor|remote|both)$/);
    return "use - single [set|unset] actor - for smoke detector"  if( $st eq "smokeDetector"       && ($single ne "single" || $target ne "actor"));
    return "use - single - for ".$st                              if(($st =~ m/^(threeStateSensor|motionDetector)$/) && ($single ne "single"));
    return "TC WindowRec only peers to channel 01 single"         if( $pmd =~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/ && $pCh[1] eq "03" && $chn ne "01" && $set eq "set");

    my $pSt = CUL_HM_getAttr($peerHash->{NAME},"subType","");

    
    if ($set eq "unset"){$set = 0; $cmdB ="02";}
    else                {$set = 1; $cmdB ="01";}

    my (@b,$nrCh2Pair);
    $b[1] = ($roleD) ?(($single eq "single")?$bNo : ($bNo*2 - 1))
                     : hex($chn)
                       ;
    if ($single eq "single"){
      $b[2] = $b[1];
      $b[1] = 0 if ($st eq "smokeDetector" ||$pSt eq "smokeDetector");
      $nrCh2Pair = 1;
    }
    elsif($single eq "dual"){
      $single = 0;
      $b[2] = $b[1] + 1;
      $nrCh2Pair = 2;
    }
    else{#($single eq "reverse")
      $single = 0;
      $b[2] = $b[1]++;
      $nrCh2Pair = 2;
    }

    if ( $pSt eq "smokeDetector"){
      $target = "both" if ($st eq "virtual");
    }

    # First the remote (one loop for on, one for off)
    if ($target =~ m/^(remote|both)$/){
      my $burst;
      if ($culHmRegModel->{$md}{peerNeedsBurst}|| #peerNeedsBurst supported
          $culHmRegType->{$st}{peerNeedsBurst}){
        $burst = (CUL_HM_getRxType($peerHash) & 0x82) #burst |burstConditional
                           ?"0101"  
                           :"0100";
      }
      for(my $i = 1; $i <= $nrCh2Pair; $i++) {
        if ($st eq "virtual"){
          my $btnName = $pSt eq "smokeDetector" ? $name :CUL_HM_id2Name($dst.sprintf("%02X",$b[$i]));
          next if (!defined $attr{$btnName});
          CUL_HM_ID2PeerList ($btnName,$peerDst.$pCh[$i],$set); #upd. peerlist
        }
        else{
          my $bStr = sprintf("%02X",$b[$i]);
          CUL_HM_PushCmdStack($hash,
                 "++".$flag."01${id}${dst}${bStr}$cmdB${peerDst}$pCh[$i]00");
#                       my ($hash,$src,$dst,$chn  ,$peerAddr,$peerChn     ,$list,$content,$prep) = @_;
          CUL_HM_pushConfig($hash,$id, $dst,$b[$i],$peerDst ,hex($pCh[$i]),4    ,$burst)
                   if($burst && $cmdB eq "01"); # only if set
          CUL_HM_qAutoRead($name,3);
        }
      }
      # need to send data here- this is a 2 device command... thats why. 
      my $rxType = CUL_HM_getRxType($devHash);
      if($rxType & 0x01){#allways
        CUL_HM_ProcessCmdStack($devHash);
      }
      elsif($devHash->{cmdStack}                  &&
            $devHash->{helper}{prt}{sProc} != 1    # not processing
            ){
        if($rxType & 0x02){# handle burst Access devices - add burst Bit
          my ($pre,$tp,$tail) = unpack 'A2A2A*',$devHash->{cmdStack}[0];
          $devHash->{cmdStack}[0] = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
          CUL_HM_ProcessCmdStack($devHash);
        }
        elsif (CUL_HM_getAttrInt($name,"burstAccess")){ #burstConditional - have a try
          $hash->{helper}{prt}{brstWu}=1;# start auto-burstWakeup
          CUL_HM_SndCmd($devHash,"++B112$id$dst");
        }
      }
    }
    if ($target =~ m/^(actor|both)$/ ){
      if ($modules{CUL_HM}{defptr}{$peerDst}){# is defined or ID only?
        if ($pSt eq "virtual"){
          CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b[2]),$set);
          CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b[1]),$set) 
                if ($b[1] & !$single);
        }
        else{
          my $peerFlag = 'A0';
          if ($dSet){
           CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X00",$peerFlag,$id,$peerDst,$pCh[1],$cmdB,$dst,$b[1]));
           CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X00",$peerFlag,$id,$peerDst,$pCh[2],$cmdB,$dst,$b[2] ));
          }
          else{
            CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",$peerFlag,$id,$peerDst,$pCh[1],$cmdB,$dst,$b[2],$b[1] ));
          }
          if(CUL_HM_getRxType($peerHash) & 0x80){
            my $pDevHash = CUL_HM_id2Hash($peerDst);#put on device
            CUL_HM_pushConfig($pDevHash,$id,$peerDst,0,0,0,0,"0101");#set burstRx
          }
          CUL_HM_qAutoRead($peerHash->{NAME},3);
        }
        $devHash = CUL_HM_getDeviceHash($peerHash); # Exchange the hash, as the switch is always alive.
      }
    }
    return ("",1) if ($target && $target eq "remote");#Nothing for actor
  }
  elsif($cmd eq "peerSmart") { ############################################ reg
    #peerSmart <peer>  
    $state = "";
    my $set  = $a[2] =~ s/^remove_// ? 0    : 1;
    my $cmdB = $set                  ? "01" : "02";
    my %PInfo;
    my $pCnt = 0;
    my $ret;
    return "peer not defined $a[2]"     if(!defined $defs{$a[2]});
    for my $pn ($a[2],$name){# setup peering information
      $PInfo{$pCnt}{name}     = $pn;
      $PInfo{$pCnt}{hash}     = CUL_HM_name2Hash($pn);
      $PInfo{$pCnt}{Dname}    = CUL_HM_getDeviceName($pn);
      $PInfo{$pCnt}{Dhash}    = CUL_HM_getDeviceHash($PInfo{$pCnt}{hash});
      $PInfo{$pCnt}{DId}      = substr(CUL_HM_name2Id($PInfo{$pCnt}{Dname}),0,6);
      $PInfo{$pCnt}{chn}      = substr(CUL_HM_name2Id($pn)."01",6,2);
      $PInfo{$pCnt}{mId}      = $PInfo{$pCnt}{Dhash}->{helper}{mId};      
      $PInfo{$pCnt}{md}       = $culHmModel->{$PInfo{$pCnt}{Dhash}->{helper}{mId}}{name};
      $PInfo{$pCnt}{st}       = $culHmModel->{$PInfo{$pCnt}{Dhash}->{helper}{mId}}{st};  
      $PInfo{$pCnt}{BurstReg} = (CUL_HM_getRxType($PInfo{$pCnt}{hash}) & 0x82)?"0101" :"0100";
      $PInfo{$pCnt}{haveBReg} = ($culHmRegModel->{$md}{peerNeedsBurst}||$culHmRegType->{$st}{peerNeedsBurst})? 1:0;
      return "please enter peer"       if(!defined $PInfo{$pCnt}{chn});
      return "peer is not a channel"   if(!$PInfo{$pCnt}{hash}->{helper}{role}{chn} );
      $PInfo{$pCnt}{remote} = (($culHmSubTypeSets->{$PInfo{$pCnt}{st}}   && $culHmSubTypeSets->{$PInfo{$pCnt}{st}}{peerChan}  )||
                               ($culHmModelSets->{$PInfo{$pCnt}{md}}     && $culHmModelSets->{$PInfo{$pCnt}{md}}{peerChan}    )||
                               ($culHmChanSets->{$PInfo{$pCnt}{md}.$PInfo{$pCnt}{chn}}
                                                                         && $culHmChanSets->{$PInfo{$pCnt}{md}.$PInfo{$pCnt}{chn}}{peerChan})  )
                               ?"remote":"actor";
      $ret .="\npeerCount $pCnt \n  ".join("\n  ", sort map{$_.":".$PInfo{$pCnt}{$_}} keys %{$PInfo{$pCnt}});
      $pCnt++;
    }
    foreach my $myNo (keys %PInfo){# execute peering
      my $pNo = ($myNo + 1) % 2;
      if ($PInfo{$myNo}{st} eq "virtual"){
        my $btnName = $PInfo{$pNo}{st} eq "smokeDetector" 
                          ? $PInfo{$myNo}{name} 
                          : $PInfo{$pNo}{name};
        next if (!defined $attr{$btnName});
        CUL_HM_ID2PeerList ($btnName,$PInfo{$pNo}{DId}.$PInfo{$pNo}{chn},$set); #upd. peerlist
      }
      else{
        my $pl = scalar (CUL_HM_getPeers($PInfo{$myNo}{name},"ID:".$PInfo{$pNo}{DId}.$PInfo{$pNo}{chn}));
        if(  ( $pl &&  $set)
           ||(!$pl && !$set) ){ # already peered or removed - skip
          Log3 $name,4,"peering skip - already done:$PInfo{$pNo}{name} to $PInfo{$myNo}{name}";
          next;
        }
        else{
          Log3 $name,4,"peering execute:$PInfo{$pNo}{name} to $PInfo{$myNo}{name}";
        }
        CUL_HM_PushCmdStack($PInfo{$myNo}{hash},"++".$flag."01${id}$PInfo{$myNo}{DId}"
                            .$PInfo{$myNo}{chn}
                            .$cmdB
                            .$PInfo{$pNo}{DId}
                            .($PInfo{$pNo}{st}     eq "smokeDetector" ? "01" : $PInfo{$pNo}{chn})
                            .($PInfo{$pNo}{remote} eq "remote"        
                            ||$PInfo{$pNo}{st}     eq "smokeDetector" ? "00" : $PInfo{$pNo}{chn})
                            );
        CUL_HM_pushConfig($PInfo{$myNo}{hash},$id, $PInfo{$myNo}{DId}
                                             ,$PInfo{$myNo}{chn}
                                             ,$PInfo{$pNo}{DId} 
                                             ,hex($PInfo{$pNo}{chn})
                                             ,4    
                                             ,$PInfo{$pNo}{BurstReg})
                   if($cmdB eq "01" && $PInfo{$myNo}{haveBReg}); # only if set peer
        my $rxType = CUL_HM_getRxType($PInfo{$myNo}{Dhash});
    
        if($rxType & 0x01){#allways
          CUL_HM_ProcessCmdStack($PInfo{$myNo}{Dhash});
        }
        elsif(   $PInfo{$myNo}{Dhash}->{cmdStack}                 
              && $PInfo{$myNo}{Dhash}->{helper}{prt}{sProc} != 1    # not processing
              ){
          if($rxType & 0x02){# handle burst Access devices - add burst Bit
            my ($pre,$tp,$tail) = unpack 'A2A2A*',$PInfo{$myNo}{Dhash}->{cmdStack}[0];
            $PInfo{$myNo}{Dhash}->{cmdStack}[0] = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
            CUL_HM_ProcessCmdStack($PInfo{$myNo}{Dhash});
          }
          elsif (CUL_HM_getAttrInt($PInfo{$pCnt}{name},"burstAccess")){ #burstConditional - have a try
            $PInfo{$pCnt}{hash}->{helper}{prt}{brstWu} = 1;             # start auto-burstWakeup
            CUL_HM_SndCmd($PInfo{$myNo}{Dhash},"++B112$id$dst");
          }
        }
    
        CUL_HM_qAutoRead($PInfo{$myNo}{name},3);
      }
    }    
  }
###############################################################################
  elsif($cmd  =~ m/^(pair|getVersion)$/) { ####################################
    $state = "";
    my $serial = ReadingsVal($name, "D-serialNr", AttrVal($name,'serialNr',""));
    return "serial $serial - wrong length or Reading D-serialNr not present"
          if(length($serial) != 10);
    my ($IO,undef)=split(":",AttrVal("laSwitch","IOgrp",AttrVal("laSwitch","IODev","")));
    if ($cmd eq "pair"){
      return "no IO defined - cannot issue command" if (!defined $IO || !defined $defs{$IO} );
      CUL_HM_Set($defs{$IO},$IO,"hmPairSerial",$serial);
    }
    else{# just trigger command
      CUL_HM_PushCmdStack($hash,"++A401".$id."000000010A".uc( unpack("H*",$serial)));
    }
  }
  elsif($cmd eq "hmPairForSec") { #############################################
    $state = "";
    my $arg = $a[2] ? $a[2] : "";
    $arg = 60 if( $arg !~ m/^\d+$/);
    CUL_HM_RemoveHMPair("hmPairForSec:$name:noReading");
    $defs{$_}{lastMsg}="cleared" foreach (devspec2array("TYPE=CUL_HM:FILTER=DEF=......:FILTER=lastMsg=.*t:00 s:...... d:000000.*")); #remove old config message from duplicate filter

    $hash->{hmPair} = 1;
    CUL_HM_UpdtReadSingle($devHash,"hmPair","for sec: $arg",1);
    InternalTimer(gettimeofday()+$arg, "CUL_HM_RemoveHMPair", "hmPairForSec:$name", 1);
  }
  elsif($cmd eq "hmPairSerial") { #############################################
    $state = "";
    my $serial = $a[2]?$a[2]:"";
    return "Usage: set $name hmPairSerial <10-character-serialnumber>"
        if(length($serial) != 10);
    CUL_HM_PushCmdStack($hash, "++8401${dst}000000010A".uc( unpack('H*', $serial)));
    CUL_HM_RemoveHMPair("hmPairForSec:$name:noReading");
    $hash->{hmPair} = 1;
    $hash->{hmPairSerial} = $serial;
    CUL_HM_UpdtReadSingle($devHash,"hmPair","serial:$serial",1);
    InternalTimer(gettimeofday()+30, "CUL_HM_RemoveHMPair", "hmPairForSec:$name", 1);
  }
  elsif($cmd eq "assignIO") { #################################################
    $state = "";
    my $io = $a[2];
    return "use set or unset - $a[3] not allowed"   if ($a[3] && $a[3] !~ m/^(set|unset)$/);
    return "$io not suitable for CUL_HM" if(!defined $defs{$io} || InternalVal("$io",'Clients','') !~ m/:CUL_HM:/);

    my $rmIO  = $a[3]  && $a[3] eq "unset" ? $io : "";
    my $addIO = !$a[3] || $a[3] ne "unset" ? $io : "";

    my @ios = (grep{$_ ne $rmIO} split(",",AttrVal($name,"IOList","")),$addIO);
    
    CommandAttr      (undef, "$name IOList ".join(",",@ios));
  }

  elsif($cmd eq "assignHmKey") { ##############################################
    $state = "";
    my $oldKeyIdx = ReadingsVal($name, "aesKeyNbr", "00");
    return "current key unknown" if (!defined $oldKeyIdx || $oldKeyIdx eq "");

    my ($key1,$key2);

    if (AttrVal($hash->{IODev}{NAME},"rfmode","") eq "HomeMatic" ) {
      return "$cmd needs Crypt::Rijndael for updating keys with CUL"
            if ($cryptFunc != 1);

      my ($newKeyIdx, %keys) = CUL_HM_getKeys($hash);
      my $oldKey = $keys{hex($oldKeyIdx)/2};

      return "$cmd requires VCCU with hmKeys"                     if ($newKeyIdx == 0);
      return "$cmd needs old key with index ".(hex($oldKeyIdx)/2) if (!defined($oldKey));
      return "$cmd key with index ".$newKeyIdx." allready in use by device"
          if ($newKeyIdx == (hex($oldKeyIdx)/2));

      my $newKey = $keys{$newKeyIdx};
      my $payload1 = pack("CCa8nN",1                      #changekey?
                                  ,$newKeyIdx*2           #index for first part of key
                                  ,substr($newKey, 0, 8)  #first 8 bytes of new key
                                  ,rand(0xffff)           #random
                                  ,0x7e296fa5);           #magic
      my $payload2 = pack("CCa8nN",1                      #changekey?
                                  ,($newKeyIdx*2)+1       #index for second part of key
                                  ,substr($newKey, 8, 8)  #second 8 bytes of new key
                                  ,rand(0xffff)           #random
                                  ,0x7e296fa5);           #magic

      my $cipher = Crypt::Rijndael->new($oldKey, Crypt::Rijndael::MODE_ECB());
      Log3 $name,2,"CUL_HM $name assignHmKey index ".(hex($oldKeyIdx)/2)." to ".$newKeyIdx
                                ." Key1: ".unpack("H*", $payload1)
                                ." Key2: ".unpack("H*", $payload2);
      
      $key1 = unpack("H*", $cipher->encrypt($payload1));
      $key2 = unpack("H*", $cipher->encrypt($payload2));
    } 
    else {
      $key1 = sprintf("01%02X",$oldKeyIdx);
      $key2 = sprintf("01%02X",($oldKeyIdx+1));
    }
    CUL_HM_PushCmdStack($hash,'++'.$flag.'04'.$id.$dst.$key1);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'04'.$id.$dst.$key2);

  }
  elsif($cmd =~ m/tplSet_(.*)/) { #############################################
    $state = "";
    my ($tPeer,$tpl,$tTyp) = ($1,$a[2],0);
    if ($tpl =~ m/^(.*)_(short|long)/){
      ($tpl,$tTyp)  = ($1,$2);
    }
    
    my %params;
    if ($HMConfig::culHmTpl{$tpl}{p} ne ""){# template with parameter
      my $tTypPre  = ($tTyp  eq "short" ? "sh":$tTyp  eq "long" ? "lg":"");
      my $tPeerPre = ($tPeer eq "0"     ? ""  
                                        :($defs{$tPeer} && $defs{$tPeer}{helper}{role}{dev} ? $tPeer."_chn-01" : $tPeer)
                                         ."-");
      foreach (keys%{$HMConfig::culHmTpl{$tpl}{reg}}){
        next if ($HMConfig::culHmTpl{$tpl}{reg}{$_} !~ m/^p([0-9])/);
        my ($curVal) = split(" ",ReadingsVal($name,"R-$tPeerPre$tTypPre$_",ReadingsVal($name,".R-$tPeerPre$tTypPre$_","whereAreYou")));
        return "template cannot be set - register default R-$tPeerPre$tTypPre$_  not available. Issue getConfig" 
               if($curVal eq "whereAreYou");
        $params{$1} = $curVal;
        
      }
    }
    $tTyp =   ($tPeer eq "0" ? "" 
            : ($tTyp  eq "0" ? ":both"
            :  ":".$tTyp)); 
    my ($hm) = devspec2array("TYPE=HMinfo");
    return "no HMinfo defined" if (!defined $defs{$hm});

    my @par =  map{$params{$_}} sort keys%params;
    my $ret = "not supported w/o HMinfo";
    if (defined &HMinfo_SetFn){
      $ret = HMinfo_SetFn($defs{$hm},$hm,"templateSet",$name,$tpl,"$tPeer$tTyp",@par);
    }
    return $ret;
  }
  elsif($cmd =~ m/tplPara(..)(.)_.*/) { #######################################
    $state = "";
    my ($tNo,$pNo) = ($1,$2);
    my ($hm) = devspec2array("TYPE=HMinfo");
    return "no HMinfo defined" if (!defined $defs{$hm});
    my @tCmd;
    my @t = sort keys%{$hash->{helper}{tmpl}};
    
    my @pv;
    my($p,$tn);
    if ($hash->{helper}{tmpl}{$t[$tNo]}){# we have a parameter
      ($p,$tn) = split(">",$t[$tNo]);
      @pv = split(" ",$hash->{helper}{tmpl}{$t[$tNo]});
      $pv[$pNo] = $a[2];
    }

    my $ret = "not supported w/o HMinfo";
    if (defined &HMinfo_SetFn){
      $ret = HMinfo_SetFn($defs{hm},$hm,"templateSet",$name,$tn,$p,@pv);
    }
    return $ret;
  }

  elsif (eval "defined(&CUL_HM_Set${cmd})"){###################################
    no strict "refs";
    my ($re,$stat,@msgs) = &{"CUL_HM_Set${cmd}"}($name,$cmd,@a);
    use strict "refs";
    if ($re == 1){
        return $stat;
    }
    elsif($re == 0){
      $state = $stat;

      CUL_HM_PushCmdStack($hash,"++${flag}$_") foreach (map {(my $foo = $_) =~ s/xADDRESSx/$id$dst/; $foo;}@msgs);
    }
    else{
        return "unknown reply from CUL_HM_Set${cmd}";
    }
  }

  else{
    return "$cmd not implemented - contact sysop";
  }
  CUL_HM_UpdtReadSingle($hash,"state",$state,1) if($state);

  my $rxType = CUL_HM_getRxType($devHash);
  if($rxType & 0x01){#always
    CUL_HM_ProcessCmdStack($devHash);
  }
  elsif($devHash->{cmdStack}                  &&
        $devHash->{helper}{prt}{sProc} != 1    # not processing
        ){
    if($rxType & 0x02){# handle burst Access devices - add burst Bit
      if($st eq "thermostat"){ # others do not support B112
        CUL_HM_SndCmd($devHash,"++B112$id$dst");
      }
      else{# set burst flag
        my ($pre,$tp,$tail) = unpack 'A2A2A*',$devHash->{cmdStack}[0];
        $devHash->{cmdStack}[0] = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
        CUL_HM_ProcessCmdStack($devHash);
      }
    }
    elsif (CUL_HM_getAttrInt($name,"burstAccess")                                                  # burstConditional - have a try
           &&  (   !defined($devHash->{helper}{prt}{awake})                                        # prevent A112/B112 at same time
                ||  defined($devHash->{helper}{prt}{awake}) && $devHash->{helper}{prt}{awake} != 1)# not if wuPrep is scheduled
           && !(defined($devHash->{helper}{io}{flgs}) && $devHash->{helper}{io}{flgs} & 0x02)){    # wuPrep is not active (for fhem start)
      $devHash->{helper}{prt}{brstWu}=1;# start auto-burstWakeup
      CUL_HM_SndCmd($devHash,"++B112$id$dst");
    }
    elsif (     $rxType & 0x18                                                                     # wu or lazy device 
           && !(defined($devHash->{helper}{io}{flgs}) && $devHash->{helper}{io}{flgs} & 0x02)){    # wuPrep is not active
      CUL_HM_hmInitMsgUpdt($devHash,1);
    }
  }
  return ("",1);# no not generate trigger out of command
}
sub CUL_HM_Ping($) {
  my($defN) = @_;
  return 0 if (   !$defs{$defN}                                  # used by timers, may get undefined
               || (CUL_HM_getRxType($defs{$defN}) & 0xe3 == 0)); # no ping for config devices
  return 1 if (defined $defs{$defN}{protCmdPend});               # cmds are already pending - that is ping enough
  if(CUL_HM_SearchCmd($defN,"sysTime")){
    CUL_HM_Set($defs{$defN},$defN,"sysTime"); 
    return 1; 
  }

  foreach my $chnN($defN,map{$defs{$defN}{$_}}grep(/^channel_/,keys %{$defs{$defN}})){
    next if (!CUL_HM_SearchCmd($chnN,"statusRequest"));
    my (undef, $nres) = CUL_HM_Set($defs{$chnN},$chnN,"statusRequest");
    return 1; 
  }

  if (CUL_HM_SearchCmd($defN,"getSerial")){
    CUL_HM_Set($defs{$defN},$defN,"getSerial");
    return 1;
  }

  return 0;
}

#+++++++++++++++++ set/get support subroutines+++++++++++++++++++++++++++++++++
sub CUL_HM_valvePosUpdt(@) {#update valve position periodically to please valve
  my($in ) = @_;
  my(undef,$vId) = split(':',$in);
  my $hash = CUL_HM_id2Hash($vId);
  my $hashVd = $hash->{helper}{vd}; 
  my $name = $hash->{NAME};
  my $msgCnt = $hashVd->{msgCnt};
  my ($idl,$lo,$hi,$nextTimer);
  my $tn = gettimeofday();
  my $nextF = $hashVd->{next};
# int32_t result = (((_address << 8) | messageCounter) * 1103515245 + 12345) >> 16;
#                          4e6d = 20077                        12996205 = C64E6D
# return (result & 0xFF) + 480;
  if ($tn > ($nextF + 3000)){# missed 20 periods;
    Log3 $name,3,"CUL_HM $name virtualTC timer off by:".int($tn - $nextF);
    $nextF = $tn;
  }
  while ($nextF < ($tn+0.05)) {# calculate next time from last successful
    $msgCnt = ($msgCnt +1) %256;
    $idl = $hashVd->{idl}+$msgCnt;
    $lo = int(($idl*0x4e6d +12345)/0x10000);#&0xff;
    $hi = ($hashVd->{idh}+$idl*198);        #&0xff;
    $nextTimer = (($lo+$hi)&0xff)/4 + 120;
    $nextF += $nextTimer;
  }
  my $offset = AttrVal($name, "cyclicMsgOffset", 200) / 1000.0;
  $nextTimer += $offset;
  $nextF += $offset;

  Log3  $name,5,"CUL_HM $name m:$hashVd->{msgCnt} ->$msgCnt t:$hashVd->{next}->$nextF  M:$tn :$nextTimer";
  $hashVd->{next} = $nextF;
  $hashVd->{nextM} = $tn+$nextTimer;# new adjust if we will match
  $hashVd->{msgCnt} = $msgCnt;
  if ($hashVd->{cmd}){
    if    ($hashVd->{typ} == 1){ 
      my $vc = ReadingsVal($name,"valveCtrl","init");
      if ($vc eq 'restart'){
        CUL_HM_UpdtReadSingle($hash,"valveCtrl","unknown",1);
        my $pn = CUL_HM_id2Name($hashVd->{id});
        $hashVd->{ackT} = ReadingsTimestamp($pn, "ValvePosition", "");
        $hashVd->{msgSent} = 0;
      }
      elsif(  ($vc ne "init" && $hashVd->{msgRed} <= $hashVd->{miss})
            || $hash->{helper}{virtTC} ne "00") {
        $hashVd->{msgSent} = 1;
        CUL_HM_SndCmd($defs{$hashVd->{nDev}},sprintf("%02X%s%s%s"
                                             ,$msgCnt
                                             ,$hashVd->{cmd}
                                             ,$hash->{helper}{virtTC}
                                             ,$hashVd->{val}));
      }
      InternalTimer($tn+10,"CUL_HM_valvePosTmr","valveTmr:$vId",0);
      $hashVd->{virtTC} = $hash->{helper}{virtTC};#save for repeat
      $hash->{helper}{virtTC} = "00";
    }
    elsif ($hashVd->{typ} == 2){#send to broadcast
      CUL_HM_PushCmdStack($hash,sprintf("%02X%s%s"
                                        ,$msgCnt
                                        ,$hashVd->{cmd}
                                        ,$hashVd->{val}));
      $hashVd->{next} = $hashVd->{nextM};
      InternalTimer($hashVd->{next},"CUL_HM_valvePosUpdt","valvePos:$vId",0);
    }
  }
  else{
    delete $hash->{helper}{virtTC};
    CUL_HM_UpdtReadSingle($hash,"state","stopped",1);
    return;# terminate processing
  }
  CUL_HM_ProcessCmdStack($hash);
}
sub CUL_HM_valvePosTmr(@) {#calc next vd wakeup 
  my($in ) = @_;
  my(undef,$vId) = split(':',$in);
  my $hash = CUL_HM_id2Hash($vId); 
  my $hashVd = $hash->{helper}{vd}; 
  my $name = $hash->{NAME};
  my $vc = ReadingsVal($name,"valveCtrl","init");
  my $vcn = $vc;
  if ($hashVd->{msgSent}) {
    my $pn = CUL_HM_id2Name($hashVd->{id});
    my $ackTime = ReadingsTimestamp($pn, "ValvePosition", "");
    if (!$ackTime || $ackTime eq $hashVd->{ackT} ){
      $vcn = (++$hashVd->{miss} > 5) ? "lost"
                                     :"miss_".$hashVd->{miss};
      Log3 $name,5,"CUL_HM $name virtualTC use fail-timer";
    }
    else{#successful - store sendtime and msgCnt that calculated it
      CUL_HM_UpdtReadSingle($hash,".next","$hashVd->{msgCnt};$hashVd->{nextM}",0);
      $hashVd->{next} = $hashVd->{nextM};#use adjusted value if ack
      $vcn = "ok";
      $hashVd->{miss} = 0;
    }
    $hashVd->{msgSent} = 0;
    $hashVd->{ackT} = $ackTime;
  }
  else {
    $hash->{helper}{virtTC} = $hashVd->{virtTC} if($hash->{helper}{virtTC} eq "00" && $hashVd->{virtTC});
    $hashVd->{miss}++;
  }
  CUL_HM_UpdtReadSingle($hash,"valveCtrl",$vcn,1) if($vc ne $vcn);
  InternalTimer($hashVd->{next},"CUL_HM_valvePosUpdt","valvePos:$vId",0);
}
sub CUL_HM_weather(@) {#periodically send weather data
  my($in ) = @_;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  my $dName = CUL_HM_getDeviceName($name) ;
  my $ioId = CUL_HM_IoId($defs{$dName});
  CUL_HM_SndCmd($hash,"++8470".$ioId."00000000".$hash->{helper}{weather});
  InternalTimer(gettimeofday()+150,"CUL_HM_weather","weather:$name",0);
}

sub CUL_HM_infoUpdtDevData($$$$) {#autoread config
  my($name,$hash,$p,$muf) = @_;
  my($fw1,$fw2,$mId,$serNo,$stc,$devInfo) = unpack('A1A1A4A20A2A*', $p);
  my $md = AttrVal($name, 'modelForce', $culHmModel->{$mId}{name} ? $culHmModel->{$mId}{name} : "unknown");# original model or forced model
  my $serial = pack('H*',$serNo);
  my $fw = sprintf("%d.%d", hex($fw1),hex($fw2));
  $attr{$name}{".mId"}     = $mId;
  $attr{$name}{serialNr}   = $serial;  # to be removed from attributes
  $attr{$name}{firmware}   = $fw;      # to be removed from attributes

  CUL_HM_updtDeviceModel($name, $md) if (   $muf
                                         || $md ne AttrVal($name,"model","unknown"));#model may be overwritten by modelForce
  CUL_HM_complConfigTest($name) if(ReadingsVal($name,"D-firmware","") ne $fw     # force read register
                                 ||ReadingsVal($name,"D-serialNr","") ne $serial
                                 ||ReadingsVal($name,".D-devInfo","") ne $devInfo
                                 ||ReadingsVal($name,".D-stc"    ,"") ne $stc
                                 ) ;
  CUL_HM_UpdtReadBulk($hash,1,"D-firmware:$fw",
                              "D-serialNr:$serial",
                              ".D-devInfo:$devInfo",
                              ".D-stc:$stc");
}
sub CUL_HM_updtDeviceModel($$@) {#change the model for a device - obey overwrite modelForce
  my($name,$model,$fromUpdate) = @_;
  my $hash = $defs{$name};
  $attr{$name}{model} = $model;
  delete $hash->{helper}{mId};
  delete $hash->{helper}{rxType};
  CUL_HM_getRxType($hash); #will update rxType
  my $mId = CUL_HM_getMId($hash);# set helper valiable and use result
  return if(!defined $mId or $mId eq "" or $mId eq "none");
  # autocreate undefined channels
  my %chanExist;
  %chanExist = map { $_ => 0 } CUL_HM_getAssChnIds($name);
  if ($attr{$name}{subType} eq "virtual"){# do not apply all possible channels for virtual
    foreach my $chanid (keys %chanExist) {
      my $chann = CUL_HM_id2Name($chanid);
      next if (!defined $defs{$chann}); #special for ACTIONDETECTOR. Or use "next if ($chanExist{$_} == 1);"
      $attr{$chann}{model} = $model;
      if ( $fromUpdate && AttrVal($chann,'peerIDs',undef) && !keys %{$defs{$chann}{helper}{peerIDsH}} ) {
          CUL_HM_ID2PeerList($chann,$_,1) for ('peerUnread',split q{,},AttrVal($chann,'peerIDs',''));
      } #Beta-User: Might not have been called earlier. Then subtype is unknown yet, https://forum.fhem.de/index.php/topic,123136.msg1177303.html#msg1177303;
      CUL_HM_SetList($chann,'') if ($fromUpdate || !defined $defs{$chann}{helper}{cmds}{cmdLst});
      CUL_HM_AttrAssign($chann) if ($fromUpdate); #Beta-User: add .AttrList for virtual channels
      $defs{$chann}->{'.AttrList'} =~ s{IOList |expert[\S]+ |levelRange }{}g if (defined $defs{$chann}->{'.AttrList'});
    }
  }
  else{
    CUL_HM_SetList($name,'') if ($fromUpdate || !defined $defs{$name}{helper}{cmds}{cmdLst});
    CUL_HM_AttrAssign($name) if ($fromUpdate);
    my @chanTypesList = split(',',$culHmModel->{$mId}{chn});
    foreach my $chantype (@chanTypesList){# check all regulat channels
      my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
      my $chnNoTyp = 1;
      for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
        my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
        if (!$modules{CUL_HM}{defptr}{$chnId} && !$fromUpdate){# not existing by now - create if not init phase
          my $chnName = $name."_".$chnTpName.(($chnStart == $chnEnd)?''
                                                                    :'_'.sprintf("%02d",$chnNoTyp));
                                  
          CommandDefine(undef,$chnName.' CUL_HM '.$chnId);
          Log3 $name,5,"CUL_HM_update: $name add channel ID: $chnId name: $chnName";
        }
        if(defined $modules{CUL_HM}{defptr}{$chnId}){
          $attr{CUL_HM_id2Name($chnId)}{model} = $model ;
          $chanExist{$chnId} = 1; # mark this channel as required
        }
        CUL_HM_SetList(CUL_HM_id2Name($chnId),"") if ($fromUpdate); #!defined $defs{CUL_HM_id2Name($chnId)}{helper}{cmds}{cmdLst};
        CUL_HM_AttrAssign(CUL_HM_id2Name($chnId));
        $chnNoTyp++;
      }
    }
    if (scalar @chanTypesList == 0){# we won't delete channel 01. This may be on purpose
      $chanExist{$defs{$name}{DEF}."01"} = 1;
      my $cn01 = CUL_HM_id2Name($defs{$name}{DEF}."01");
      $attr{$cn01}{model} = $model if (defined $attr{$cn01});
    }
    foreach(keys %chanExist){
      next if ($chanExist{$_} == 1);
      CommandDelete(undef,CUL_HM_id2Name($_));
      Log3 $name,5,"CUL_HM_update: $name delete channel name: $_";
    }
    my $CycTime = AttrVal($name,"actCycle", $culHmModel->{$mId}{cyc});
    CUL_HM_ActAdd($hash->{DEF},$CycTime)if ($CycTime);
    CUL_HM_queueUpdtCfg($name) if(!$fromUpdate);
  }
  CUL_HM_AttrAssign($name);
}

sub CUL_HM_getConfig($){
  my $hash = shift;
  my $flag = 'A0';
  my $id = CUL_HM_IoId($hash);
  my $dst = substr($hash->{DEF},0,6);
  my $name = $hash->{NAME};
  delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
  CUL_HM_complConfigTest($name);
  CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000')
           if ($hash->{helper}{role}{dev});
  my @chnIdList = CUL_HM_getAssChnIds($name);
  delete $hash->{READINGS}{$_}
        foreach (grep /^[\.]?(RegL_)/,keys %{$hash->{READINGS}});
  CUL_HM_UpdtReadSingle($hash,"cfgState","updating",1);
  foreach my $channel (@chnIdList){
    my $cHash = CUL_HM_id2Hash($channel);
    my $chn = substr($channel,6,2);
    delete $cHash->{READINGS}{$_}
          foreach (grep /^[\.]?(RegL_)/,keys %{$cHash->{READINGS}});
    CUL_HM_UpdtReadSingle($cHash,"cfgState","updating",1);
    my $lstAr = $culHmModel->{CUL_HM_getMId($cHash)}{lst};
    if($lstAr){ 
      my $pReq = 0; # Peer request not issued, do only once for channel
      $cHash->{helper}{getCfgListNo}= "";
      foreach my $listEntry (split(",",$lstAr)){#lists define for this channel
                                                # e.g."1, 5:2.3p ,6:2"
        my ($peerReq,$chnValid)= (0,0);
        my ($listNo,$chnLst1) = split(":",$listEntry);
        if (!$chnLst1){
          $chnValid = 1; #if no entry go for all channels
          $peerReq = 1 if($listNo eq 'p' || $listNo==3 ||$listNo==4); #default
        }
        else{
          my @chnLst = split('\.',$chnLst1);
          foreach my $lchn (@chnLst){
            no warnings;#know that lchan may be followed by 'p' causing a warning
            $chnValid = 1 if (int($lchn) == hex($chn));
            use warnings;
            $peerReq = 1 if ($chnValid && $lchn =~ m/p/);
            last if ($chnValid);
          }
        }
        if ($chnValid){# yes, we will go for a list
          if ($peerReq){# need to get the peers first
            if($listNo ne 'p'){# not if 'only peers'!
              $cHash->{helper}{getCfgList} = "all";
              $cHash->{helper}{getCfgListNo} .= ",".$listNo;
            }
            if (!$pReq){#get peers first, but only once per channel
              CUL_HM_PushCmdStack($cHash,'##'.sprintf("%s01%s%s%s03"
                                         ,$flag,$id,$dst,$chn));
              $pReq = 1;
            }
          }
          else{
            my $ln = sprintf("%02X",$listNo);
            my $mch = CUL_HM_lstCh($cHash,$ln,$chn);
            CUL_HM_PushCmdStack($cHash,"##$flag"."01$id$dst$mch"."0400000000$ln");
          }
        }
      }
    }
  }
}

sub CUL_HM_calcDisWmSet($){
  my $dh = shift; 
  my ($txt,$col,$icon) = eval $dh->{exe};
  if   ($txt eq "off")  { delete $dh->{txt};}
  elsif($txt ne "nc")   { $dh->{txt} = substr($txt,0,12);}

  if   (!$col ||$col eq "off")   { delete $dh->{col};}
  elsif($col ne "nc"){
    if (!defined $disColor{$col}){ delete $dh->{col};}
    else                         { $dh->{col}=$col; }
  }

  if   (!$icon ||$icon eq "noIcon"){delete $dh->{icn};}
  elsif($icon ne "nc"){ 
    if (!defined $disIcon {$icon}){delete $dh->{icn}}
    else                          {$dh->{icn}=$icon;}
  }
}
sub CUL_HM_calcDisWm($$$){
  my ($hash,$devName,$t)= @_; # t = s or l
  my $msg;
  my $ts = $t eq "s"?"short":"long";
  foreach my $l (sort keys %{$hash->{helper}{dispi}{$t}}){
    my $dh = $hash->{helper}{dispi}{$t}{"$l"};
    CUL_HM_calcDisWmSet($dh) if ($dh->{d} == 2);

    my ($ch,$ln);
    if($dh->{txt}){
      (undef,$ch,undef,$ln) = unpack('A3A2A1A1',$dh->{txt});
      $ch = sprintf("%02X",$ch) if ($ch =~ m/^\d+\d+$/);
      my $rd =  ($dh->{txt}?"$dh->{txt} ":"- ")
               .($dh->{col}?"$dh->{col} ":"- ") 
               .($dh->{icn}?"$dh->{icn} ":"- ")
               ;
      $rd .= "->". ReadingsVal(InternalVal($devName,"channel_$ch","no")
                                         ,"text$ln","unkown")
                      if (defined $disBtn{$dh->{txt}  });
      readingsSingleUpdate($hash,"disp_${ts}_$l"
                         ,$rd
                         ,0);
      if (defined $disBtn{$dh->{txt}  }){
        $msg .= sprintf("12%02X",$disBtn{$dh->{txt}  }+0x80);
      } 
      else{
        $msg .= "12";
        $msg .= uc( unpack("H*",$dh->{txt})) if ($dh->{txt});
      }
    }

    $msg .= sprintf("11%02X",$disColor{$dh->{col}}+0x80)if ($dh->{col});
    $msg .= sprintf("13%02X",$disIcon{$dh->{icn} }+0x80)if ($dh->{icn});
    $msg .= "0A";# end of line indicator
  }
  my $msgh = "800102";
  $msg .= "03";
  my @txtMsg2;
  foreach (unpack('(A28)*',$msg)){ 
    push @txtMsg2,$msgh.$_;
    $msgh = "8001";
  }
  $hash->{helper}{disp}{$t} = \@txtMsg2;
}

sub CUL_HM_RemoveHMPair($) {####################################################
  my($in ) = shift;
  my(undef,$name,$setReading) = split(':',$in);
  return if (!$name || !defined $defs{$name});
  my %ioN = ($name => 1);
  my $owner_CCU = InternalVal($name,"owner_CCU",$name);
  $ioN{$_} = 1 foreach (grep {defined $_ && $_ !~ m/^$/ && defined $defs{$_}} (split(",",AttrVal($owner_CCU,"IOList",$name).",$owner_CCU")));
  
  foreach my $IOname (keys %ioN){
    RemoveInternalTimer("hmPairForSec:$IOname");
    if(  ($defs{$IOname}{hmPair} || $defs{$IOname}{hmPairSerial} )
       &&(!$setReading || $setReading ne "noReading")){
      CUL_HM_UpdtReadSingle($defs{$IOname},"hmPair","timeout",1);
    }
    delete($defs{$IOname}{hmPair});
    delete($defs{$IOname}{hmPairSerial});
  }
}

#+++++++++++++++++ Protocol stack, sending, repeat+++++++++++++++++++++++++++++
sub CUL_HM_pushConfig($$$$$$$$@) {#generate messages to config data to register
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content,$prep) = @_;
  my $flag = 'A0';
  my $tl = length($content);
  $chn     = sprintf("%02X",$chn);
  $peerChn = sprintf("%02X",$peerChn);
  $list    = sprintf("%02X",$list);
  $prep    = "" if (!defined $prep);
  # --store pending changes in shadow to handle bit manipulations cululativ--
  $peerAddr = "000000" if(!$peerAddr);
  my $peerN = ($peerAddr ne "000000")?CUL_HM_peerChName($peerAddr.$peerChn,$dst):"";
  $peerN =~ s/broadcast//;
  $peerN =~ s/ /_/g;#remote blanks
  my $regLNp = "RegL_".$list.".".$peerN;
  my $regPre = ($hash->{helper}{expert}{raw}?"":".");
  my $regLN = $regPre.$regLNp;
  #--- copy data from readings to shadow
  my $chnhash = $modules{CUL_HM}{defptr}{$dst.$chn};
  $chnhash = $hash if (!$chnhash);
  my $sdH = CUL_HM_shH($chnhash,$list,$dst);
  my $rRd = ReadingsVal($chnhash->{NAME},$regLN,"");
  if (!$sdH->{helper}{shadowReg} ||
      !$sdH->{helper}{shadowReg}{$regLNp}){
    $sdH->{helper}{shadowReg}{$regLNp} = $rRd;
  }
  #--- update with ne value
  my $regs = $sdH->{helper}{shadowReg}{$regLNp};
  for(my $l = 0; $l < $tl; $l+=4) { #substitute changed bytes in shadow
    my $addr = substr($content,$l,2);
    my $data = substr($content,$l+2,2);
    if(!$regs || !($regs =~ s/$addr:../$addr:$data/)){
        $regs .= " ".$addr.":".$data;
    }
  }
  $sdH->{helper}{shadowReg}{$regLNp} = $regs;   # update shadow
  $sdH->{helper}{shadowRegChn}{$regLNp} = $chn; # save chn for later use, even with prep
  my @changeList;
  if ($prep eq "exec"){#update complete registerset
    @changeList = keys%{$sdH->{helper}{shadowReg}};
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
    foreach (sort split " ",$sdH->{helper}{shadowReg}{$nrn}){
      $change .= $_." " if ($nrRd !~ m/$_/);# filter only changes
    }
    next if (!$change);#no changes
    $change =~ s/00:00//;
    $change =~ s/(\ |:)//g;
    if ($nrRd){
      $chnhash->{READINGS}{$regPre.$nrn}{VAL} =~ s/00:00//; #mark incomplete as we go for a change;
    }
    my $pN;
    $changed = 1;# yes, we did
    ($list,$pN) = ($1,$2) if($nrn =~ m/RegL_(..)\.(.*)/);
    if ($pN){($peerAddr,$peerChn) = unpack('A6A2', CUL_HM_name2Id($pN,$hash));}
    else       {($peerAddr,$peerChn) = ('000000','00');}

    if (AttrVal($chnhash->{NAME},"peerIDs","") =~ m/${peerAddr}00/){$peerChn = "00"}# if device we are not sure about device or channel. Check peers

    CUL_HM_updtRegDisp($hash,$list,$peerAddr.$peerChn);
    ############partition
#   my @chSplit = unpack('(A28)*',$change);
    $chn = $sdH->{helper}{shadowRegChn}{$nrn};
    my @chSplit = unpack('(A1120)*',$change);# makes max 40 lines, 280 byte
    foreach my $chSpl(@chSplit){
      my $mch = CUL_HM_lstCh($chnhash,$list,$chn);
      CUL_HM_PushCmdStack($hash, "++".$flag.'01'.$src.$dst.$mch.'05'.
                                          $peerAddr.$peerChn.$list);
      $tl = length($chSpl);
      for(my $l = 0; $l < $tl; $l+=28) {
        my $ml = $tl-$l < 28 ? $tl-$l : 28;
        CUL_HM_PushCmdStack($hash, '++A001'.$src.$dst.$mch.'08'.
                                       substr($chSpl,$l,$ml));
      }
      CUL_HM_PushCmdStack($hash,"++A001".$src.$dst.$mch."06");
    }
    #########
  }
  CUL_HM_cfgStateDelay($hash->{NAME});
  if ($changed){
    CUL_HM_complConfig($hash->{NAME},1);
    CUL_HM_qAutoRead($hash->{NAME},3) ;
  }
}
sub CUL_HM_PushCmdStack($$) {
  my ($chnhash, $cmd) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);
  if(!$hash->{cmdStack}){# this is a new 'burst' of messages
    my @arr = ();
    $hash->{cmdStack} = \@arr;
    $hash->{helper}{prt}{bErr}=0 if ($hash->{helper}{prt}{sProc} != 1);# not processing
  }
  push(@{$hash->{cmdStack}}, $cmd);
  if ($hash->{helper}{prt}{sProc} != 1) {
    CUL_HM_protState($hash,"CMDs_pending");# not processing
  }
  else {
    $hash->{protCmdPend} = scalar(@{$hash->{cmdStack}})." CMDs_pending";
  }
}
sub CUL_HM_ProcessCmdStack($) {
  my ($chnhash) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);
  if (!defined $hash->{helper}{prt}{rspWait} or ! defined $hash->{helper}{prt}{rspWait}{cmd}){
    if   ($hash->{cmdStack} && scalar(@{$hash->{cmdStack}})){
      CUL_HM_SndCmd($hash, shift @{$hash->{cmdStack}});
    }
    elsif($hash->{helper}{prt}{sProc} != 0){
      CUL_HM_protState($hash,"CMDs_done");                                    
    }
  }
  return;
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
    next if (!$_);
    my ($f,$d)=split ":=",$_;
    $mHsh->{rspWait}{$f}=$d;
  }
  my $to = gettimeofday() + (($mHsh->{rspWait}{Pending})?rand(20)/10+4:
                                                         rand(40)/10+2);
  if ($mHsh->{rspWait}{cmd}) {
    my (undef,$mFlg) = unpack 'A6A2',$mHsh->{rspWait}{cmd};
    $to += 1 if($mFlg && (hex($mFlg) & 0x10)); # burst wakeup
  }
  InternalTimer($to,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
}
sub CUL_HM_responseSetup($$) {#store all we need to handle the response
  #setup repeatTimer and cmdStackControll
  my ($hash,$cmd) =  @_;
  return if($hash->{helper}{prt}{sProc} == 3);#not relevant while FW update
  my (undef,$mNo,$mFlg,$mTp,$src,$dst,$chn,$sTp,$dat) = 
        unpack 'A4A2A2A2A6A6A2A2A*',$cmd;
  $mFlg = hex($mFlg);
  if (($mFlg & 0x20) && ($dst ne '000000')){#msg wants ack
    my $rss = $hash->{helper}{prt}{wuReSent}
                       ? $hash->{helper}{prt}{wuReSent}
                       :1;#resend counter start value - may need preloaded for WU device

    if   ($mTp =~ m/^(01|3E)$/ && $sTp)        {
      if   ($sTp eq "03"){ #PeerList-----------
        #--- remember request params in device level
        CUL_HM_respWaitSu ($hash,"Pending:=PeerList"
                                ,"cmd:=$cmd" ,"forChn:=$chn"
                                ,"mNo:=".hex($mNo)
                                ,"reSent:=$rss");

        #--- remove readings in channel
        my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
        $chnhash = $hash if (!$chnhash);
        delete $chnhash->{READINGS}{peerList};#empty old list
        delete $chnhash->{peerList};#empty old list
        delete $chnhash->{helper}{peerIDsRaw};
        $attr{$chnhash->{NAME}}{peerIDs} = 'peerUnread';
        my %peerIDsH;
        $chnhash->{helper}{peerIDsH} = \%peerIDsH;
      }
      elsif($sTp eq "04"){ #RegisterRead-------
        my ($peer, $list) = unpack 'A8A2',$dat;
        $peer = ($peer ne "00000000")?CUL_HM_peerChName($peer,$dst):"";
        #--- set messaging items
        my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
        $chnhash = $hash if(!$chnhash);
        my $fch = CUL_HM_shC($chnhash,$list,$chn);
        CUL_HM_respWaitSu ($hash,"Pending:=RegisterRead"
                                ,"cmd:=$cmd" ,"forChn:=$fch"
                                ,"forList:=$list","forPeer:=$peer"
                                ,"mNo:=".hex($mNo)
                                ,"nAddr:=0"
                                ,"reSent:=$rss");
        #--- remove channel entries that will be replaced
        #empty val since reading will be cumulative
        my $rlName = ($chnhash->{helper}{expert}{raw}?"":".")."RegL_".$list.".".$peer;
        $chnhash->{READINGS}{$rlName}{VAL}="";
        delete ($chnhash->{READINGS}{$rlName}{TIME});
      }
      elsif($sTp eq "09"){ #SerialRead-------
        CUL_HM_respWaitSu ($hash,"Pending:=SerialRead"
                                ,"cmd:=$cmd" ,"reSent:=$rss");
      }
      else{
        CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=".hex($mNo),"reSent:=$rss");
      }
      $hash->{helper}{cSnd} =~ s/.*,// if($hash->{helper}{cSnd});
      $hash->{helper}{cSnd} .= ",".substr($cmd,8);
    }
    elsif($mTp eq '03')                {#AES response - keep former wait and start timer again
      # 
      if ($hash->{helper}{prt}{rspWait}){
        RemoveInternalTimer("respPend:$hash->{DEF}");
        my $mHsh = $hash->{helper}{prt};
        my $to = gettimeofday() + (($mHsh->{helper}{prt}{rspWait}{Pending})?rand(20)/10+4:
                                                               rand(40)/10+2);
        if ($mHsh->{rspWait}{cmd}) {
          my (undef,$mFlg) = unpack 'A6A2',$mHsh->{rspWait}{cmd};
          $to += 1 if($mFlg && (hex($mFlg) & 0x10)); # burst wakeup
        }
        InternalTimer($to,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
      }
      else{
        # nothing - we dont know the origonal message
      }
    }
    elsif($mTp eq '11')                {
      my $to = "";
      if ($chn eq "02"){#!!! chn is subtype!!!
        if ($dat =~ m/(..)....(....)/){#lvl ne 0 and timer on
          # store Channel in this datafield. 
          # dimmer may answer with wrong virtual channel - then dont resent!
          $hash->{helper}{tmdOn} = $sTp if ($1 ne "00" && $2 !~ m/(0000|FFFF)/);
          $to = "timedOn:=1";
        }
      }
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=".hex($mNo),"reSent:=$rss",$to);
      $hash->{helper}{cSnd} =~ s/.*,// if($hash->{helper}{cSnd});
      $hash->{helper}{cSnd} .= ",".substr($cmd,8);
    }
    elsif($mTp eq '12' && $mFlg & 0x10){#wakeup with burst
      # response setup - do not repeat, set counter to 250
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=".hex($mNo),"reSent:=$rss","brstWu:=1");
    }
    elsif($mTp !~ m/C./)              {#
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=".hex($mNo),"fromSrc:=$src","reSent:=$rss");
    }

    CUL_HM_protState($hash,"CMDs_processing...");#if($mTp ne '03');
  }
  else{# no answer expected
    if($hash->{cmdStack} && scalar @{$hash->{cmdStack}}){
      if (!$hash->{helper}{prt}{sleeping}){
        CUL_HM_protState($hash,"CMDs_processing...");
        InternalTimer(gettimeofday()+.1, "CUL_HM_ProcessCmdStack", $hash, 0);
      }
    }
    elsif(!$hash->{helper}{prt}{rspWait}{cmd}){
      CUL_HM_protState($hash,"CMDs_done");
    }
  }

  my $mmcS = $hash->{helper}{prt}{mmcS}?$hash->{helper}{prt}{mmcS}:0;
  if ($mTp eq '01'){
    my $oCmd = "++".substr($cmd,6);
    if    ($sTp eq "05"){
      my @arr = ($oCmd);
      $hash->{helper}{prt}{mmcA}=\@arr;
      $hash->{helper}{prt}{mmcS} = 1;
    }
    elsif ($sTp =~ m/^(07|08)$/ && ($mmcS == 1||$mmcS == 2)){
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
  if (   (defined $ioHash->{XmitOpen} && $ioHash->{XmitOpen} != 1)
      || ReadingsVal($io,"state","") !~ m/^(?:opened|Initialized)$/
       ){#still no send allowed
    if ( $modules{CUL_HM}{$io}{tmrStart} &&
        ($modules{CUL_HM}{$io}{tmrStart} < gettimeofday() - $modules{CUL_HM}{hmIoMaxDly})){
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
      if ($modules{CUL_HM}{$io}{pendDev} && @{$modules{CUL_HM}{$io}{pendDev}}){
        InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
                                    "sndIfOpen:$io", 0);
      }
    }
  }
  else{
    $modules{CUL_HM}{$io}{tmr} = 0;
    if ($modules{CUL_HM}{$io}{pendDev} && @{$modules{CUL_HM}{$io}{pendDev}}){
      my $name = shift(@{$modules{CUL_HM}{$io}{pendDev}});
      CUL_HM_ProcessCmdStack($defs{$name});
      if (@{$modules{CUL_HM}{$io}{pendDev}}){#tmr = 0, clearing queue slowly
        InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
                                      "sndIfOpen:$io", 0);
      }
    }
  }
}
sub CUL_HM_SndCmd($$) {
  my ($hash, $cmd) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  if(   AttrVal($hash->{NAME},"ignore",0) != 0
     || AttrVal($hash->{NAME},"dummy" ,0) != 0){
    CUL_HM_eventP($hash,"dummy");
    return;
  }
  CUL_HM_assignIO($hash) ;
  if(!defined $hash->{IODev} ||!defined $hash->{IODev}{NAME}){
    CUL_HM_eventP($hash,"IOerr");
    CUL_HM_UpdtReadSingle($hash,"state","ERR_IOdev_undefined",1);
    return;
  }
  my $io = $hash->{IODev};
  my $ioName = $io->{NAME};
  
  if (   (   (hex(substr($cmd,2,2)) & 0x20)                           # check for commands with resp-req
          && (   $modules{CUL_HM}{$ioName}{tmr}                       # queue already running
              || (defined($io->{XmitOpen}) && $io->{XmitOpen} != 1) ) # overload, dont send
         )
      || !CUL_HM_operIObyIOHash($io)                                  # we need to queue
      ){

    # push device to list
    if (!defined $modules{CUL_HM}{$ioName}{tmr}){
      # some setup work for this timer
      $modules{CUL_HM}{$ioName}{tmr} = 0;
      if (!$modules{CUL_HM}{$ioName}{pendDev}){# generate if not exist
        my @arr2 = ();
        $modules{CUL_HM}{$ioName}{pendDev} = \@arr2;
      }
    }
    
    # shall we delay commands if IO device is not present?
    # it could cause trouble if light switches on after a long period
    # repetition will be stopped after 1min forsecurity reason.
    #  so do: return cmd to queue and set state to pending again. 
    #  device will be queued @ CUL_HM. Timer will perform cyclic check for IO to return. 
    #  
    if(!$hash->{cmdStack}) {   
      my @arr = ();
      $hash->{cmdStack} = \@arr;
    }
    
    if( $hash->{helper}{prt}{rspWait} && $hash->{helper}{prt}{rspWait}{cmd}){
      (undef,$cmd) = unpack 'A4A*',$hash->{helper}{prt}{rspWait}{cmd};
    }
    unshift (@{$hash->{cmdStack}}, $cmd);#pushback cmd, wait for opportunity

    @{$modules{CUL_HM}{$ioName}{pendDev}} =
          CUL_HM_noDup(@{$modules{CUL_HM}{$ioName}{pendDev}},$hash->{NAME});
    CUL_HM_respPendRm($hash);#rm timer - we are out
    CUL_HM_protState($hash,"CMDs_pending");
    
    if ($modules{CUL_HM}{$ioName}{tmr} != 1){# need to start timer
      my $tn = gettimeofday();
         InternalTimer($tn+$IOpoll, "CUL_HM_sndIfOpen", "sndIfOpen:$ioName", 0);
      $modules{CUL_HM}{$ioName}{tmr} = 1;
      $modules{CUL_HM}{$ioName}{tmrStart} = $tn; # abort if to long
    }
    return;
  }

  my ($mn, $cmd2) =  unpack 'A2A*',$cmd;
  if   ($mn eq "++") {
    $mn = ($hash->{helper}{HM_CMDNR} + 1) & 0xff;
    $hash->{helper}{HM_CMDNR} = $mn;
  }
  elsif($mn eq '##') { #noansi: all changes with respect to https://forum.fhem.de/index.php/topic,119122.msg1149902.html#msg1149902
    $mn = ($hash->{helper}{HM_CMDNR} + 16) & 0xff; #noansi: larger change in mNo for blocks of data expected (register read, peer read),
    $hash->{helper}{HM_CMDNR} = $mn;               #        2 is minimum to overcome known problem with early zero 'end' in register data from
                                                   #        HM-LC-DIM1TPBU-FM or HM-MOD-RE-8 due to random register reported
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
  CUL_HM_statCnt($ioName,"s",hex(substr($cmd2,0,2)));
  CUL_HM_eventP($hash,"Snd");
  CUL_HM_eventP($hash,"SndB") if (hex(substr($cmd2,0,2)) & 0x10);
  CUL_HM_responseSetup($hash,$cmd);
  $cmd =~ m/^As(..)(..)(..)(..)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6,$7));
}
sub CUL_HM_statCnt(@) {# set msg statistics for (r)ecive (s)end or (u)pdate
  my ($ioName,$dir,$typ) = @_;
  my $stat = $modules{CUL_HM}{stat};
  if (!$stat->{$ioName}){
    foreach my $ud ("r","s","rb","sb"){
      $stat->{$ud}{$ioName}{h}{$_}  = 0 foreach(0..23);
      $stat->{$ud}{$ioName}{d}{$_}  = 0 foreach(0..6);
    }
    $stat->{$ioName}{last} = 0;
  }
  my @l = localtime(gettimeofday());

  if ($l[2] != $stat->{$ioName}{last}){#next field
    if ($l[2] < $stat->{$ioName}{last}){#next day
      my $recentD = ($l[6]+5)%7;
      foreach my $ud ("r","s","rb","sb"){
        $stat->{$ud}{$ioName}{d}{$recentD} = 0;
        $stat->{$ud}{$ioName}{d}{$recentD} += $stat->{$ud}{$ioName}{h}{$_}    foreach (0..23);
      }
    }
    foreach my $ud ("r","s","rb","sb"){
      $stat->{$ud}{$ioName}{h}{$l[2]}  = 0;
    }
    $stat->{$ioName}{last} = $l[2];
  }
  if ($dir ne "u"){
    $stat->{$dir}{$ioName}{h}{$l[2]}++;
    if (defined($typ) && ($typ & 0x10)){
      $stat->{$dir."b"}{$ioName}{h}{$l[2]}++;
    }
  }
}
sub CUL_HM_statCntRfresh($) {# update statistic once a day
  my ($ioName,$dir) = @_;
  foreach (keys %{$modules{CUL_HM}{stat}{r}}){
    if (!$defs{$ioName}){#IO device is deleted, clear counts
      delete $modules{CUL_HM}{stat}{$ioName};
      delete $modules{CUL_HM}{stat}{r}{$ioName};
      delete $modules{CUL_HM}{stat}{s}{$ioName};
      delete $modules{CUL_HM}{stat}{rb}{$ioName};
      delete $modules{CUL_HM}{stat}{sb}{$ioName};
      next;
    }
    CUL_HM_statCnt($_,"u") if ($_ ne "dummy");
  }
  RemoveInternalTimer("StatCntRfresh");
  InternalTimer(gettimeofday()+3600*20,"CUL_HM_statCntRfresh","StatCntRfresh",0);
}

sub CUL_HM_trigLastEvent($$$$$){#set trigLast for central setting commands
  my ($dst,$mTp,$p01,$p02,$chn) = @_;
  my $hash = CUL_HM_id2Hash($dst.$chn);
  CUL_HM_UpdtReadSingle($hash,"trigLast","fhem:".$p01,1);
}

sub CUL_HM_respPendRm($) {#del response related entries in messageing entity
  my ($hash) =  @_;

  return if (!defined($hash->{DEF}));
  $modules{CUL_HM}{prot}{rspPend}-- if($hash->{helper}{prt}{rspWait}{cmd});
  delete $hash->{helper}{prt}{wuReSent} if (  !$hash->{helper}{prt}{mmcS}                              
                                            && $hash->{helper}{prt}{rspWait}{cmd}                      
                                            && substr($hash->{helper}{prt}{rspWait}{cmd},8,2) ne '12');
  delete $hash->{helper}{prt}{rspWait};
  delete $hash->{helper}{tmdOn};
#  delete $hash->{helper}{prt}{mmcA};
#  delete $hash->{helper}{prt}{mmcS};
  RemoveInternalTimer($hash);                  # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer
  $respRemoved = 1;
}
sub CUL_HM_respPendTout($) {
  my ($HMidIn) =  @_;
  my(undef,$HMid) = split(":",$HMidIn,2);
  my $hash = $modules{CUL_HM}{defptr}{$HMid};
  my $pHash = $hash->{helper}{prt};#shortcut
  if ($hash && $hash->{DEF} ne '000000'){# we know the device
    my $name = $hash->{NAME};
    return if(!$pHash->{rspWait}{reSent});      # Double timer?
    my $rxt = CUL_HM_getRxType($hash);
    if    ($pHash->{rspWait}{brstWu}){#burst-wakeup try failed (conditionalBurst)
      CUL_HM_respPendRm($hash);# don't count problems, was just a try
      $hash->{protCondBurst} = "off" if (!$hash->{protCondBurst}||
                                          $hash->{protCondBurst} !~ m/forced/);;
      $pHash->{brstWu} = 0;# finished
      $pHash->{awake} = 1;# new mode => set to "wait for wu" (wuPrep)
      CUL_HM_protState($hash,"CMDs_pending");
      CUL_HM_hmInitMsgUpdt($hash,1);
      # commandstack will be executed when device wakes up itself
    }
    elsif ($pHash->{try}){         #send try failed - revert, wait for wakeup
      # device might still be busy with writing flash or similar
      # we have to wait for next wakeup
      unshift (@{$hash->{cmdStack}}, "++".substr($pHash->{rspWait}{cmd},6));
      delete $pHash->{try};
      CUL_HM_respPendRm($hash);# do not count problems with wakeup try, just wait
      $pHash->{awake} = 1 if (defined $pHash->{awake});                         # frank: new mode => set to "wait for wu" (wuPrep)
      CUL_HM_protState($hash,"CMDs_pending");
      CUL_HM_hmInitMsgUpdt($hash,1);
    }
    elsif (!CUL_HM_operIObyIOHash($hash->{IODev})){#IO errors
      CUL_HM_eventP($hash,"IOdly");
      CUL_HM_ProcessCmdStack($hash) if($rxt & 0x03);#burst/all
    }
    elsif ($pHash->{rspWait}{reSent} > AttrVal($name,"msgRepeat",($rxt & 0x9B)?3:0)#too many
           ){#config cannot retry
      my $pendCmd = "MISSING ACK";

      if ($pHash->{rspWait}{Pending}){
        $pendCmd = "RESPONSE TIMEOUT:".$pHash->{rspWait}{Pending};
        CUL_HM_complConfig($name,1);# check with delay
      }
      CUL_HM_eventP($hash,"ResndFail");
      CUL_HM_UpdtReadSingle($hash,"state",$pendCmd,1);
    }
    else{# manage retries
      $pHash->{rspWait}{reSent}++;
      CUL_HM_eventP($hash,"Resnd");
      Log3 $name,5,"CUL_HM_Resend: $name nr ".$pHash->{rspWait}{reSent};
      if   ($hash->{protCondBurst} && $hash->{protCondBurst} eq "on" ){
        #timeout while conditional burst was active. try re-wakeup
        #need to fill back command to queue and wait for next wakeup            # frank: change mechanism
        if ($pHash->{mmcA}){#fillback multi-message command                     
          unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});   
          delete $pHash->{mmcA};                                                
          delete $pHash->{mmcS};                                                
        }                                                                       
        else{#fillback simple command                                           
          unshift (@{$hash->{cmdStack}},"++".substr($pHash->{rspWait}{cmd},6)); 
        }                                                                       
        $pHash->{wuReSent} = $pHash->{rspWait}{reSent};                         
        delete $pHash->{rspWait};                                               
        $pHash->{awake}=4;#start re-wakeup                                      # frank: change position
        my $addr = CUL_HM_IoId($hash);
        CUL_HM_SndCmd($hash,"++B112$addr$HMid");
      }
      elsif($rxt & 0x18){# wakeup/lazy devices
        #need to fill back command to queue and wait for next wakeup
        if ($pHash->{mmcA}){#fillback multi-message command
          unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
          delete $pHash->{mmcA};
          delete $pHash->{mmcS};
        }
        else{#fillback simple command
          unshift (@{$hash->{cmdStack}},"++".substr($pHash->{rspWait}{cmd},6))
                if (substr($pHash->{rspWait}{cmd},8,2) ne '12');# not wakeup
        }
        my $wuReSent = $pHash->{rspWait}{reSent};# save 'invalid' count
        CUL_HM_respPendRm($hash);#clear
        CUL_HM_protState($hash,"CMDs_pending");
        $pHash->{wuReSent} = $wuReSent;# restore'invalid' count after general delete
        CUL_HM_hmInitMsgUpdt($hash,1);                                          # frank:
      }
      else{# normal/burst device resend
        if ($rxt & 0x02){# type = burst - need to set burst-Bit for retry
          if ($pHash->{mmcA}){#fillback multi-message command
            unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
            delete $pHash->{mmcA};
            delete $pHash->{mmcS};
            
            my $cmd = shift @{$hash->{cmdStack}};
            $cmd = sprintf("As%02X01%s", length($cmd)/2, substr($cmd,2));
            $pHash->{rspWait}{cmd} = $cmd;
            my $rss = $pHash->{rspWait}{reSent}; # rescue repeat counter (will be overwritten in responseSetup)
            CUL_HM_responseSetup($hash,$cmd);
            $pHash->{rspWait}{reSent} = $rss; # restore repeat counter
          }

          my ($pre,$tp,$tail) = unpack 'A6A2A*',$pHash->{rspWait}{cmd};
          $pHash->{rspWait}{cmd} = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
        }
        IOWrite($hash, "", $pHash->{rspWait}{cmd});
        CUL_HM_eventP($hash,"SndB")          if(hex(substr($pHash->{rspWait}{cmd},6,2)) & 0x10);
        CUL_HM_statCnt($hash->{IODev}{NAME},"s",hex(substr($pHash->{rspWait}{cmd},6,2)));
        RemoveInternalTimer("respPend:$hash->{DEF}");
        InternalTimer(gettimeofday()+rand(20)/10+4,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
      }
    }
  }
}
sub CUL_HM_respPendToutProlong($) {#used when device sends part responses
  my ($hash) =  @_;
  RemoveInternalTimer("respPend:$hash->{DEF}");
  InternalTimer(gettimeofday()+3, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}

sub CUL_HM_FWupdateSteps($){#steps for FW update
  my $mIn = shift;
  my $step = $modules{CUL_HM}{helper}{updateStep};
  my $name = $modules{CUL_HM}{helper}{updatingName};
  my $dst  = $modules{CUL_HM}{helper}{updateDst};
  my $id   = $modules{CUL_HM}{helper}{updateId};
  my $mNo  = $modules{CUL_HM}{helper}{updateNbr};
  my $hash = $defs{$name};
  my $mNoA = sprintf("%02X",$mNo);
  
  return "" if ($mIn !~ m/$mNoA..02$dst${id}00/ && $mIn !~ m/..10${dst}00000000/);
  if ($mIn =~ m/$mNoA..02$dst${id}00/){
    $modules{CUL_HM}{helper}{updateRetry} = 0;
    $modules{CUL_HM}{helper}{updateNbrPassed} = $mNo;
  }

  if ($step == 0){#check bootloader entered - now change speed
    return "" if ($mIn =~ m/$mNoA..02$dst${id}00/);
    Log3 $name,2,"CUL_HM fwUpdate $name entered mode. IO-speed: fast";
    $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
    CUL_HM_SndCmd($hash,"${mNoA}00CB$id${dst}105B11F81547");
#    CUL_HM_SndCmd($hash,"${mNoA}20CB$id${dst}105B11F815470B081A1C191D1BC71C001DB221B623EA");
    select(undef, undef, undef, (0.04));
    CUL_HM_FWupdateSpeed($name,100);
    select(undef, undef, undef, (0.04));
    $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
    $modules{CUL_HM}{helper}{updateStep} = $step = 1;
    $modules{CUL_HM}{helper}{updateNbr} = $mNo;
    RemoveInternalTimer("fail:notInBootLoader");
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim","${dst}${id}00",0);
  }

  ##16.130  CUL_Parse:  A 0A 30 0002 235EDB 255E91 00
  ##16.338  CUL_Parse:  A 0A 39 0002 235EDB 255E91 00
  ##16.716  CUL_Parse:  A 0A 42 0002 235EDB 255E91 00
  ##17.093  CUL_Parse:  A 0A 4B 0002 235EDB 255E91 00
  ##17.471  CUL_Parse:  A 0A 54 0002 235EDB 255E91 00
  ##17.848  CUL_Parse:  A 0A 5D 0002 235EDB 255E91 00
  ##...
  ##43.621 4: CUL_Parse: iocu1 A 0A 58 0002 235EDB 255E91 00
  ##44.034 4: CUL_Parse: iocu1 A 0A 61 0002 235EDB 255E91 00
  ##44.161 4: CUL_Parse: iocu1 A 1D 6A 20CA 255E91 235EDB 00121642446D1C3F45F240ED84DC5E7C1AB7554D
  ##44.180 4: CUL_Parse: iocu1 A 0A 6A 0002 235EDB 255E91 00
  ## one block = 10 messages in 200-1000ms
  my $blocks = scalar(@{$modules{CUL_HM}{helper}{updateData}});
  RemoveInternalTimer("respPend:$hash->{DEF}");
  RemoveInternalTimer("fail:Block".($step-1));
  if ($blocks < $step){#last block
    CUL_HM_FWupdateEnd("done");
    Log3 $name,2,"CUL_HM fwUpdate completed";
    return "done";
  }
  else{# programming continue
    my $bl = ${$modules{CUL_HM}{helper}{updateData}}[$step-1];
    my $no = scalar(@{$bl});
    Log3 $name,5,"CUL_HM fwUpdate write block $step of $blocks: $no messages";
    foreach my $msgP (@{$bl}){
      $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
      CUL_HM_SndCmd($hash, $mNoA.((--$no)?"00":"20")."CA$id$dst".$msgP);
      # select(undef, undef, undef, (0.01));# no wait necessary - FHEM is slow anyway
    }
    $modules{CUL_HM}{helper}{updateStep}++;
    $modules{CUL_HM}{helper}{updateNbr} = $mNo;
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim","${dst}${id}00",0);
    InternalTimer(gettimeofday()+5,"CUL_HM_FWupdateBTo","fail:Block$step",0);
    return "";
  }
}
sub CUL_HM_FWupdateBTo($){# FW update block timeout
  my $in = shift;
  $modules{CUL_HM}{helper}{updateRetry}++;
  if ($modules{CUL_HM}{helper}{updateRetry} > 5){#retry exceeded
    CUL_HM_FWupdateEnd($in);
  }
  else{# have a retry
    $modules{CUL_HM}{helper}{updateStep}--;
    $modules{CUL_HM}{helper}{updateNbr} = $modules{CUL_HM}{helper}{updateNbrPassed};
    CUL_HM_FWupdateSteps("0010".$modules{CUL_HM}{helper}{updateDst}."00000000");
  }
}
sub CUL_HM_FWupdateEnd($){#end FW update
  my $in = shift;
  my $hash = $defs{$modules{CUL_HM}{helper}{updatingName}};
  CUL_HM_UpdtReadSingle($hash,"fwUpdate",$in,1);
  CUL_HM_FWupdateSpeed($modules{CUL_HM}{helper}{updatingName},10);
  $hash->{helper}{io}{newChn} = $hash->{helper}{io}{newChnFwUpdate}
      if(defined $hash->{helper}{io}{newChnFwUpdate});#restore initMsg
  delete $hash->{helper}{io}{newChnFwUpdate};
  
  delete $defs{$modules{CUL_HM}{helper}{updatingName}}->{cmdStack};
  delete $modules{CUL_HM}{helper}{updating};
  delete $modules{CUL_HM}{helper}{updatingName};
  delete $modules{CUL_HM}{helper}{updateData};
  delete $modules{CUL_HM}{helper}{updateStep};
  delete $modules{CUL_HM}{helper}{updateDst};
  delete $modules{CUL_HM}{helper}{updateId};
  delete $modules{CUL_HM}{helper}{updateNbr};
  CUL_HM_respPendRm($hash);

  CUL_HM_protState($hash,"CMDs_done_FWupdate");
  Log3 $hash->{NAME},2,"CUL_HM fwUpdate $hash->{NAME} end. IO-speed: normal";
}
sub CUL_HM_FWupdateSpeed($$){#set IO speed
  my ($name,$speed) = @_;
  my $hash = $defs{$name};
  if (AttrVal($hash->{IODev}{NAME},"rfmode","") ne "HomeMatic"){
    my $msg = sprintf("G%02X",$speed);
    IOWrite($hash, "cmd",$msg);
  }
  else{
    IOWrite($hash, "cmd","speed".$speed);
  }
}
sub CUL_HM_FWupdateSim($){#end FW Simulation
  my $msg = shift;
  my $ioName = $defs{$modules{CUL_HM}{helper}{updatingName}}->{IODev}->{NAME};
  my $mNo = sprintf("%02X",$modules{CUL_HM}{helper}{updateNbr});
  if (0 == $modules{CUL_HM}{helper}{updateStep}){
    CUL_HM_Parse($defs{$ioName},"A00${mNo}0010$msg");
  }
  else{
    Log3 "",5,"FWupdate simulate No:$mNo";
    CUL_HM_Parse($defs{$ioName},"A00${mNo}8002$msg");
  }
}

sub CUL_HM_eventP($$) {#handle protocol events
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv
  my ($hash, $evntType) = @_;
  return if (!defined $hash);
  if ($evntType eq "Rcv"){
    my $t = TimeNow();
    $hash->{"protLastRcv"} = $t;
    $t =~ s/[\:\-\ ]//g;
    CUL_HM_UpdtReadSingle($hash,".protLastRcv",$t,0);
  }
  my $evnt = $hash->{"prot".$evntType} ? $hash->{"prot".$evntType} : "0";
  my ($evntCnt,undef) = split(' last_at:',$evnt);
  $hash->{"prot".$evntType} = ++$evntCnt." last_at:".TimeNow();

  my $pHash = $hash->{helper}{prt};                  # frank: change position
  if ($evntType =~ m/^(Nack|ResndFail|IOerr|dummy)/){# unrecoverable Error
    CUL_HM_UpdtReadSingle($hash,"state",$evntType,1);
    $pHash->{bErr}++;
    $hash->{protCmdDel} = 0 if(!$hash->{protCmdDel});
    $hash->{protCmdDel} += scalar @{$hash->{cmdStack}} + 1
            if ($hash->{cmdStack});
    CUL_HM_protState($hash,"CMDs_done");
    if ($pHash->{mmcA}){                             # frank: uncommented in CUL_HM_respPendRm
      delete $pHash->{mmcA};
      delete $pHash->{mmcS};
    }
    CUL_HM_respPendRm($hash);
  }
  elsif($evntType eq "IOdly"){ # IO problem - will see whether it recovers
    if ($pHash->{mmcA}){
      unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
      delete $pHash->{mmcA};
      delete $pHash->{mmcS};
    }
    else{
      unshift (@{$hash->{cmdStack}},"++".substr($pHash->{rspWait}{cmd},6));
#      unshift @{$hash->{cmdStack}}, $pHash->{rspWait}{cmd};#pushback
    }
    CUL_HM_respPendRm($hash);
  }
}
sub CUL_HM_protState($$){
  my ($hash,$state) = @_;
  my $name = $hash->{NAME};

  my $sProcIn = $hash->{helper}{prt}{sProc};
  $sProcIn = 0 if(!defined $sProcIn);
  if ($sProcIn == 3){#FW update processing
    # do not change state - commandstack is bypassed
    return if ( $state !~ m/(Info_Cleared|_FWupdate)/);
  }
  if   ($state =~ m/processing/) {
    $hash->{helper}{prt}{sProc} = 1;
  }
  elsif($state =~ m/^CMDs_done/) {
    $state .= ($hash->{helper}{prt}{bErr}?
                            ("_Errors:".$hash->{helper}{prt}{bErr})
                            :"");
    delete($hash->{cmdStack});
    delete($hash->{protCmdPend});
    $hash->{helper}{prt}{bErr}  = 0;
    $hash->{helper}{prt}{sProc} = 0;
    $hash->{helper}{prt}{awake} = 0 if (defined $hash->{helper}{prt}{awake});
  }
  elsif($state eq "Info_Cleared"){
    $hash->{helper}{prt}{sProc} = 0;
    $hash->{helper}{prt}{awake} = 0 if (defined $hash->{helper}{prt}{awake});
  }
  elsif($state eq "CMDs_pending"){
    $hash->{protCmdPend} = (defined($hash->{cmdStack}) ? scalar(@{$hash->{cmdStack}})
                                                       : '0')." CMDs_pending"; 
    $hash->{helper}{prt}{sProc} = 2;
  }
  elsif($state eq "CMDs_FWupdate"){
    $hash->{helper}{prt}{sProc} = 3;
  }
  $hash->{protState} = $state;
  
  if(AttrVal($name,"commStInCh","on") eq "on"){
    CUL_HM_UpdtReadSingle($defs{$_},"commState",$state,1) foreach(CUL_HM_getAssChnNames($name));#trigger for all channels required due to bad hierarchical structure of FHEM  
  }
  else{
    CUL_HM_UpdtReadSingle($defs{$name},"commState",$state,1) ;
  }

  if (!$hash->{helper}{role}{chn}){
    CUL_HM_UpdtReadSingle($hash,"state",$state,
                          ($hash->{helper}{prt}{sProc} == 1)?0:1);
  }
  Log3 $name,5,"CUL_HM $name protEvent:$state".
            ($hash->{cmdStack}?" pending:".scalar @{$hash->{cmdStack}}:"");
  CUL_HM_hmInitMsgUpdt($hash) if(   $hash->{helper}{prt}{sProc} != $sProcIn
                                 && defined $hash->{helper}{io}{flgs} && $hash->{helper}{io}{flgs} & 0x02   # wuPrep is active
                                 && !$hash->{helper}{q}{qReqConf} && !$hash->{helper}{q}{qReqStat}          # no wuQueue is scheduled 
                                 && $hash->{helper}{prt}{sProc} < 2);                                       # any changing to idle/processing
}

###################-----------helper and shortcuts--------#####################
################### Peer Handling ################
sub CUL_HM_ID2PeerList ($$$) { # {CUL_HM_ID2PeerList ("lvFrei","12345678",1)}
  my($name,$peerID,$set) = @_;
  
  my $peerHash = $defs{$name}{helper};
  my $peerIDsH = $defs{$name}{helper}{peerIDsH};
  if($peerID eq "peerUnread"){
    my %peerH;
    $peerHash->{peerIDsH} = \%peerH;
  }
  elsif (!defined($peerID) || $peerID eq '' || $peerID !~ m/^[0-9a-fA-Fx]{8}$/){ #ignore - perform status update
  }
  else{
      $peerID = "00000000" if($peerID =~ m/^000000..$/);
      if($set){
        $peerIDsH->{$peerID} = CUL_HM_peerChName($peerID,substr(CUL_HM_name2Id($name),0,6));
      }
      else {
        delete $peerIDsH->{$peerID};
      }
  }
  if   (defined $peerIDsH->{"00000000"}) {$peerHash->{peerIDsState} = "complete";}
  elsif(keys %{$peerIDsH})               {$peerHash->{peerIDsState} = "incomplete";}
  else                                   {$peerHash->{peerIDsState} = "peerUnread";}
  
  my $peerIDs   = join(",",sort(CUL_HM_getPeers($name,"IDsRaw")));
  my $peerNames = join(",",sort(CUL_HM_getPeers($name,"Names" )));
  if($defs{$name}{helper}{role}{vrt}){
      if (!$peerIDs){
        delete $attr{$name}{peerIDs};
      }
      else{
        $attr{$name}{peerIDs} = $peerIDs;
      }
  }
  else{
      $attr{$name}{peerIDs} = $peerIDs ? $peerIDs : "peerUnread";                 # make it public
  }

  my $hash  = $defs{$name};
  my $dHash = CUL_HM_getDeviceHash($hash);
  my $st    = AttrVal($dHash->{NAME},"subType","");
  my $md    = AttrVal($dHash->{NAME},"model","");
  my $chn   = InternalVal($name,"chanNo","");
  if ($peerNames && $peerNames ne " "){
    CUL_HM_UpdtReadSingle($hash,"peerList",$peerNames,0);
    $hash->{peerList} = $peerNames;
    if ($st eq "virtual"){
      #if any of the peers is an SD we are team master
      my ($tMstr,$tcSim,$thSim) = (0,0,0);
      foreach (CUL_HM_getPeers($name,"NamesExt" )){
        if(AttrVal($_,"subType","") eq "smokeDetector"){#have smoke detector
          $tMstr = AttrVal($_,"model","") eq "HM-SEC-SD-2"? 2:1;#differentiate SD and SD2
        }
        $tcSim = 1 if(AttrVal($_,"model","")   =~ m/^(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/);
        my $pch = (substr(CUL_HM_name2Id($_),6,2));
        $thSim = 1 if(AttrVal($_,"model","")   =~ m/^HM-CC-RT-DN/ && $pch eq "01");
      }
      if   ($tMstr){
        $hash->{helper}{fkt} = "sdLead".$tMstr;
        $hash->{sdTeam}      = "sdLead";
        $hash->{TESTNR}      = 1 if(!exists $hash->{TESTNR});#must be defined for all sdLead
        CUL_HM_updtSDTeam($name);
      }
      elsif($tcSim){
        $hash->{helper}{fkt}="vdCtrl";}
      elsif($thSim){
        $hash->{helper}{fkt}="virtThSens";}
      else         {
        delete $hash->{helper}{fkt};}
      
      if(!$tMstr)  {delete $hash->{sdTeam};}      
    }
    elsif ($st eq "smokeDetector"){
      foreach (grep !/broadcast/,values %{$peerIDsH}){
        my $tn = ($_ =~ m/self/) ? $name : $_;
        next if (!$defs{$tn});
        $defs{$tn}{helper}{fkt} = "sdLead".(AttrVal($name,"model","") eq "HM-SEC-SD-2"? 2:1);
        $defs{$tn}{sdTeam}      = "sdLead" ;
        $defs{$tn}{TESTNR}      = 1 if(!exists $defs{$tn}{TESTNR});#must be defined for all sdLead
      }
      if($peerNames !~ m/self/){
        delete $hash->{sdTeam};
        delete $hash->{helper}{fkt};
      }
    }
    elsif( ($md =~ m/^HM-CC-RT-DN/     && $chn =~ m/^(02|05|04)$/)
         ||($md eq "HM-TC-IT-WM-W-EU"  && $chn eq "07")){
      if ($chn eq "04"){
        #if 04 is peered we are "teamed" -> set channel 05
        my $ch05H = $modules{CUL_HM}{defptr}{$dHash->{DEF}."05"};
        CUL_HM_UpdtReadSingle($ch05H,"state","peered",0) if($ch05H);
      }
      else{
        CUL_HM_UpdtReadSingle($hash,"state","peered",0);
      }
    }
    elsif( $chn =~ m/^(03|06)$/ && $md =~ m/^(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/ ){
      if (ReadingsVal($name,"state","unpeered") eq "unpeered"){ 
        CUL_HM_UpdtReadSingle($hash,"state","unknown",0);
      }
    }
  }
  else{# no peer set - clean up: delete entries
    delete $hash->{READINGS}{peerList};
    delete $hash->{peerList};
    if (($md =~ m/^HM-CC-RT-DN/     && $chn=~ m/^(02|03|04|05|06)$/)
      ||($md eq "HM-TC-IT-WM-W-EU"  && $chn=~ m/^(03|06|07)$/)){
      if ($chn eq "04"){
        my $ch05H = $modules{CUL_HM}{defptr}{$dHash->{DEF}."05"};
        CUL_HM_UpdtReadSingle($ch05H,"state","unpeered") if($ch05H);
      }
      else{
        CUL_HM_UpdtReadSingle($hash,"state","unpeered");
      }
    }
  }
  CUL_HM_setAssotiat($name);
}
sub CUL_HM_peerChId($$) {  #in:<IDorName> <deviceID>, out:channelID
  my($pId,$dId)=@_;
  return "" if (!$pId);
  my $iId = CUL_HM_id2IoId($dId);
  my ($pSc,$pScNo) = unpack 'A4A*',$pId; #helper for shortcut spread
  return $dId.sprintf("%02X",'0'.$pScNo) if ($pSc eq 'self');
  return $iId.sprintf("%02X",'0'.$pScNo) if ($pSc eq 'fhem');
  return "all"                           if ($pId eq 'all');#used by getRegList
  my $p = CUL_HM_name2Id($pId).'01';
  return "" if (length($p)<8);
  return substr(CUL_HM_name2Id($pId).'01',0,8);# default chan is 01
}
sub CUL_HM_peerChName($$) {#in:<IDorName> <deviceID>, out:name
  my($pId,$dId)=@_;
  my $iId = CUL_HM_id2IoId($dId);
  my($pDev,$pChn) = unpack'A6A2',$pId;
  return 'self'.$pChn if ($pDev eq $dId);
  return 'fhem'.$pChn if ($pDev eq $iId && !defined $modules{CUL_HM}{defptr}{$pDev});
  $pId = $pDev if($pChn =~ m/0[0x]/); # both means device directly. This may be used by remotes and pusdbuttons
  return CUL_HM_id2Name($pId);
}
sub CUL_HM_getMId($) {     #in: hash(chn or dev) out:model key (key for %culHmModel)
 # Will store result in device helper
  my $hash = shift;
  $hash = CUL_HM_getDeviceHash($hash);
  return "none" if (!$hash->{NAME});
  if (!defined $hash->{helper}{mId} || !$hash->{helper}{mId}){# need to search
    $hash->{helper}{mId}     = CUL_HM_getmIdFromModel(AttrVal($hash->{NAME}, "model", ""));
    $hash->{helper}{mId}     = CUL_HM_getmIdFromModel($culHmModel->{$hash->{helper}{mId}}{alias})    
                               if ($hash->{helper}{mId} && defined $culHmModel->{$hash->{helper}{mId}}{alias});
    $attr{$hash->{NAME}}{subType} = $hash->{helper}{mId} ? $culHmModel->{$hash->{helper}{mId}}{st}:"no";
    #--- mId is updated - now update the reglist
    return "" if ($hash->{helper}{mId} eq "no");
    foreach(CUL_HM_getAssChnNames($hash->{NAME})){
      $defs{$_}{helper}{regLst}     = CUL_HM_getChnList($_) ;
      $defs{$_}{helper}{peerOpt}    = CUL_HM_getChnPeers($_);
      $defs{$_}{helper}{peerFriend} = CUL_HM_getChnPeerFriend($_);
      CUL_HM_calcPeerOptions();
    }
  }
  return $hash->{helper}{mId};
}
sub CUL_HM_getmIdFromModel($){ # enter model and receive the corresponding ID
  my $model = shift;
  $model = ""        if(not defined $model);
  $model = "VIRTUAL" if($model =~ m/^virtual_/);
  return (defined $culHmModel2Id->{$model}     ? $culHmModel2Id->{$model}
        :(defined $culHmModel2Id->{uc($model)} ? $culHmModel2Id->{uc($model)}
        :"no"))                                                              if ($mIdReverse);
  # old version: if user did not reboot or not updated HMconfig
  my $mId = "";
  foreach my $mIdKey(keys%{$culHmModel}){
    next if (!$culHmModel->{$mIdKey}{name} ||
              $culHmModel->{$mIdKey}{name} ne $model);
    $mId = $mIdKey;
    last;
  }
  return $mId;
}
sub CUL_HM_getAliasModel($){ # 
  my $hash = shift;
  my $dHash = CUL_HM_getDeviceHash($hash);
  return "" if(!defined $dHash || !defined $dHash->{helper}|| !defined $dHash->{helper}{mId});
  return $culHmModel->{$dHash->{helper}{mId}}{name};
}

sub CUL_HM_getRxType($) {      #in:hash(chn or dev) out:binary coded Rx type
 # Will store result in device helper
  my ($hash) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  no warnings; #convert regardless of content
  my $rxtEntity = int($hash->{helper}{rxType});
  use warnings;
  if (!$rxtEntity){ #at least one bit must be set
    delete $hash->{helper}{mId}; # force new calculation by now
    my $MId = CUL_HM_getMId($hash);
    my $rxtOfModel = ($MId && $culHmModel->{$MId}{rxt} ? $culHmModel->{$MId}{rxt} : "");
    if ($rxtOfModel){
      $rxtEntity |= ($rxtOfModel =~ m/b/)?0x02:0;#burst
      $rxtEntity |= ($rxtOfModel =~ m/3/)?0x02:0;#tripple-burst todo currently unknown how it works
      $rxtEntity |= ($rxtOfModel =~ m/c/)?0x04:0;#config
      $rxtEntity |= ($rxtOfModel =~ m/w/)?0x08:0;#wakeup
      $rxtEntity |= ($rxtOfModel =~ m/l/)?0x10:0;#lazyConfig
      $rxtEntity |= ($rxtOfModel =~ m/f/)?0x80:0;#burstConditional
    }
    $rxtEntity = 1 if (!$rxtEntity);#always
    $hash->{helper}{rxType} = $rxtEntity if ($MId);#store if ID is prooven
  }
  return $rxtEntity;
}
sub CUL_HM_getAssChnIds($) {   #in: name out:ID list of assotiated channels
  # if it is a channel only return itself
  # if device and no channel
  my ($name) = @_;
  my @chnIdList;
  if ($defs{$name}){
    my $hash = $defs{$name};
    foreach my $channel (grep /^channel_/, keys %{$hash}){
      my $chnHash = $defs{$hash->{$channel}};
      push @chnIdList,$chnHash->{DEF} if ($chnHash);
    }
    my $dId = CUL_HM_name2Id($name);
    
    push @chnIdList,$dId."01" if (length($dId) == 6 && !$hash->{channel_01});
    push @chnIdList,$dId if (length($dId) == 8);
  }
  return sort(@chnIdList);
}
sub CUL_HM_getAssChnNames($) { #in: name out:list of assotiated chan and device
  my ($name) = @_;
  my @chnN = ();
  if ($defs{$name}){
    push @chnN,$name;
    my $hash = $defs{$name};
    push @chnN,$hash->{$_} foreach (grep /^channel_/,sort keys %{$hash});
  }
  return sort(@chnN);
}
sub CUL_HM_getKeys($) {        #in: device-hash out:highest index, hash with keys
  my ($hash) = @_;
  my $highestIdx = 0;
  my %keys = ();
  $keys{0} = pack("H*", "A4E375C6B09FD185F27C4E96FC273AE4"); #index 0: eQ-3 default
      
  my $vccu = $hash->{IODev}->{owner_CCU};
  $vccu = $hash->{IODev}->{NAME} if(!defined($vccu) || !AttrVal($vccu,"hmKey",""));# if keys are not in vccu
  if (defined($vccu)) {
    foreach my $i (1..3){
      my ($kNo,$k) = split(":",AttrVal($vccu,"hmKey".($i== 1?"":$i),""));
      if (defined($kNo) && defined($k)) {
        $kNo = hex($kNo);
        $keys{$kNo} = pack("H*", $k);
        $highestIdx = $kNo if ($kNo > $highestIdx);
      }
    }
  }
  return ($highestIdx, %keys);
}

sub CUL_HM_generateCBCsignature($$) { #in: device-hash,msg out: signed message
  my ($hash,$msg) = @_;
  my $oldcounter = ReadingsVal($hash->{NAME},"aesCBCCounter","000000");
  my $counter = substr($oldcounter, 0, 4);
  my ($mNo,$mFlg,$mTg,$mSnd,$mPay) = unpack 'A2A2A2A12A*',$msg;
  my $devH = CUL_HM_getDeviceHash($hash);
  
  if ($cryptFunc != 1) {
    Log3 $hash,1,"CUL_HM $hash->{NAME} need Crypt::Rijndael to generate AES-CBC signature";
    return $msg;
  }
  my ($kNo, %keys) = CUL_HM_getKeys($devH);
  $kNo = AttrVal($devH->{NAME},"aesKey",$kNo);
  if (!defined($keys{$kNo})) {
    Log3 $hash,1,"CUL_HM $devH->{NAME} AES key ${kNo} not defined!";
    return $msg;
  }

  #generate message number
  if($mNo eq "++") {
    $mNo = ($devH->{helper}{HM_CMDNR} + 1) & 0xff;
    my $oldNo = hex(substr($oldcounter, 4, 2));
    if ($mNo <= $oldNo && (($oldNo + 1) & 0xff) > $oldNo) {
      $mNo = ($oldNo + 1) & 0xff;
    }
    $devH->{helper}{HM_CMDNR} = $mNo;
    $mNo = sprintf("%02X", $mNo);
  }

  if (hex($counter.$mNo) <= hex($oldcounter)) {
    $counter = sprintf("%04X", (hex($counter) + 1) & 0xffff);
  }

  push @evtEt,[$hash,1,"aesCBCCounter:".$counter.$mNo];
  CUL_HM_pushEvnts();

  my $cipher = Crypt::Rijndael->new($keys{$kNo}, Crypt::Rijndael::MODE_ECB());

  my $iv = "49" 
          .$mSnd                #sender receiver
          .$counter             #generation counter
          .$mNo 
          ."000000000005";

  my $ivC = $cipher->encrypt(pack("H32", $iv));
  my $d = $mNo 
         .$mFlg             #Flags
         .$mPay;            #payload

  $d .= "00" x ((32 - length($d)) / 2) if (length($d) < 32);

  my $cbc = $cipher->encrypt(pack("H32", $d) ^ $ivC);
  #2016.09.04 06:52:54.227 3: CUL_HM
  Log3 $hash,5,     "CUL_HM $hash->{NAME} CBC IV: " . $iv
            ."\n".(" "x30)."$hash->{NAME} CBC D:  " . $d
            ."\n".(" "x30)."$hash->{NAME} CBC E:  " . unpack("H*", $cbc);
  return uc(  $mNo 
            . $mFlg.$mTg.$mSnd.$mPay
            . $counter 
            . unpack("H8", substr($cbc, 12, 4)));
}

#+++++++++++++++++ Conversions names, hashes, ids++++++++++++++++++++++++++++++
#Performance opti: subroutines may consume up to 5 times the performance
#
#get Attr: $val  = $attr{$hash->{NAME}}{$attrName}?$attr{$hash->{NAME}}{$attrName}      :"";
#          $val  = $attr{$name}{$attrName}        ?$attr{$name}{$attrName}              :"";
#getRead:  $val  = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{VAL}      :"";
#          $val  = $defs{$name}{READINGS}{$rlName}?$defs{$name}{READINGS}{$rlName}{VAL} :"";
#          $time = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{time}     :"";
 
sub CUL_HM_h2IoId($) {      #in: ioHash out: ioHMid
  my ($io) = @_;
  return "000000" if (ref($io) ne 'HASH');
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_IoId($) {        #in: hash out: IO_id
  my ($hash) = @_;
  my $ioHash = CUL_HM_getDeviceHash($hash)->{IODev};
  return "" if (!defined($ioHash) || !$ioHash->{NAME});
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return AttrVal($ioHash->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_id2IoId($) {     #in: id, out:Id of assigned IO
  my ($id) = @_;
  ($id) = unpack 'A6',$id;#get device ID
  return "";
  return "" if ( !$modules{CUL_HM}{defptr}{$id} 
              || !$modules{CUL_HM}{defptr}{$id}->{IODev} 
              || !$modules{CUL_HM}{defptr}{$id}->{IODev}{NAME}
                );
  my $ioHash = $defs{$modules{CUL_HM}{defptr}{$id}->{IODev}};
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return AttrVal($ioHash->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_name2IoName($) { #in: hash out: IO_id
  my ($name) = @_;
  my $ioHash = CUL_HM_getDeviceHash($defs{$name})->{IODev};
  return (defined($ioHash) && defined($ioHash->{NAME})) ? $ioHash->{NAME} : "";
}

sub CUL_HM_hash2Id($) {  #in: id,   out:hash
  my ($hash) = @_;
  return $hash->{DEF};
}
sub CUL_HM_hash2Name($) {#in: hash, out:name
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
  return $name               if($name =~ m/^[A-F0-9]{6,8}$/i);#was already HMid
  return $defs{$1}->{DEF}.$2 if($name =~ m/(.*)_chn-(..)$/);   #<devname> chn-xx
  return "000000"            if($name eq "broadcast");        #broadcast
  return substr($idHash->{DEF},0,6).sprintf("%02X",$1)
                             if($idHash && ($name =~ m/self(.*)/));
  return CUL_HM_IoId($idHash).sprintf("%02X",$1)
                             if($idHash && ($name =~ m/fhem(.*)/));
  return AttrVal($name,"hmId",""); # could be IO device
}
sub CUL_HM_id2Name($) { #in: name or HMid out: name
  my ($p) = @_;
  $p = "" if (!defined $p);
  return $p                               if($defs{$p}||$p =~ m/_chn-\d\d$/
                                             || $p !~ m/^[A-F0-9]{6,8}$/i);
  my ($devId,$chn) = unpack 'A6A2',$p;
  return "broadcast"                      if($devId eq "000000");

  my $defPtr = $modules{CUL_HM}{defptr};
  if (length($p) == 8 && $chn ne "00"){
    return $defPtr->{$p}{NAME}            if(defined $defPtr->{$p});#channel
    return $defPtr->{$devId}{NAME}."_chn-$chn"
                                          if($defPtr->{$devId});#dev, add chn
    return $p;                               #not defined, return ID only
  }
  else{
    return $defPtr->{$devId}{NAME}        if($defPtr->{$devId});#device only
    return $devId;                           #not defined, return ID only
  }
}
sub CUL_HM_id2Hash($) { #in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if (defined $modules{CUL_HM}{defptr}{$id});
  $id = substr($id,0,6);
  return defined $modules{CUL_HM}{defptr}{$id}?($modules{CUL_HM}{defptr}{$id}):undef;
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
sub CUL_HM_shH($$$){
  my ($h,$l,$d) = @_;
  if (   $h->{helper}{shRegW} 
      && $h->{helper}{shRegW}{$l}
      && $modules{CUL_HM}{defptr}{$d.$h->{helper}{shRegW}{$l}}){
    return $modules{CUL_HM}{defptr}{$d.$h->{helper}{shRegW}{$l}};
  }
  return $h;
}
sub CUL_HM_shC($$$){
  my ($h,$l,$c) = @_;
  if (   $h->{helper}{shRegW} 
      && $h->{helper}{shRegW}{$l}){
    return $h->{helper}{shRegW}{$l};
  }
  return $c;
}
sub CUL_HM_lstCh($$$){
  my ($h,$l,$c) = @_;
  if (   $h->{helper}{shRegR} 
      && $h->{helper}{shRegR}{$l}){
    return $h->{helper}{shRegR}{$l};
  }
  return $c;
}
sub CUL_HM_setAssotiat($) {##########################
  my $name = shift;
  my @list = (CUL_HM_getAssChnNames(CUL_HM_getDeviceName($name))
             ,CUL_HM_getDeviceName($name)
             ,CUL_HM_getPeers($name,"NamesExt"));
  CUL_HM_UpdtReadSingle($defs{$name},".associatedWith"
                       ,join(",",@list)
                       ,0);
}

#+++++++++++++++++ debug ++++++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_DumpProtocol($$@) {
  my ($prefix, $iohash, $len,$cnt,$msgFlags,$mTp,$src,$dst,$p) = @_;
  my $iname = $iohash->{NAME};
  no warnings;# conv 2 number would cause a warning - which is ok
  my $hmProtocolEvents = int (AttrVal(CUL_HM_id2Name($src), "hmProtocolEvents",
                              AttrVal(InternalVal($iname,"owner_CCU",$iname), "hmProtocolEvents", 0)));
  use warnings;

  my $p01 = substr($p,0,2);
  my $p02 = substr($p,0,4);
  my $p11 = (length($p) > 2 ? substr($p,2,2) : "");
  CUL_HM_trigLastEvent($dst,$mTp,$p01,$p02,$p11) if ($mTp eq "11" && $p01 =~ m/(02|03|80|81)/ && $p11);
  return if(!$hmProtocolEvents);

  # decode message flags for printing
  my $msgFlLong   = "";
  my $msgFlagsHex = hex($msgFlags);
  for(my $i = 0; $i < @{$culHmCmdFlags}; $i++) {
    $msgFlLong .= ",".${$culHmCmdFlags}[$i] if($msgFlagsHex & (1<<$i));
  }

  my $ps;
  $ps = $culHmBits->{"$mTp;p11=$p11"} if(!$ps);
  $ps = $culHmBits->{"$mTp;p01=$p01"} if(!$ps);
  $ps = $culHmBits->{"$mTp;p02=$p02"} if(!$ps);
  $ps = $culHmBits->{"$mTp"}          if(!$ps);
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
  Log3 $iname,5,$msg;
  DoTrigger($iname, $msg) if($hmProtocolEvents > 2);
}

#+++++++++++++++++ handling register updates ++++++++++++++++++++++++++++++++++
sub CUL_HM_getRegFromStore($$$$@) {#read a register from backup data
  my($name,$regName,$list,$peerId,$regLN)=@_;
  my $hash = $defs{$name};
  my ($size,$pos,$conv,$factor,$unit,$peerRq) = (8,0,"",1,"","n"); # default
  my $addr = $regName;
  my $reg = $culHmRegDefine->{$regName};
  if ($reg) { # get the register's information
    $addr   = $reg->{a};
    $pos    = ($addr*10)%10;
    $addr   = int($addr);
    $size   = $reg->{s};
    $size   = int($size)*8 + ($size*10)%10;
    $list   = $reg->{l};
    $conv   = $reg->{c}; #unconvert formula
    $factor = $reg->{f};
    $peerRq = $reg->{p};
    $unit   = ($reg->{u} ? " ".$reg->{u} : "");
  }
  else{
    return "invalid:regname or address" if($addr < 1 ||$addr > 255);
    $peerRq = hex($peerId) != 0 ? "y":"n";
  }

  return "invalid:no peer for this register" if((hex($peerId) != 0 && $peerRq eq "n" )
                                              ||(hex($peerId) == 0 && $peerRq eq "y"));
  my $dst = substr(CUL_HM_name2Id($name),0,6);
  if(!$regLN){
    $regLN = ($hash->{helper}{expert}{raw}?"":".")
              .sprintf("RegL_%02X.",$list)
              .($peerId?CUL_HM_peerChName($peerId,
                                          $dst)
                       :"");
  }
  $regLN =~ s/broadcast//;
  my $regLNp = $regLN;
  $regLNp =~ s/^\.//; #remove leading '.' in case ..
  my $sdH = CUL_HM_shH($hash,sprintf("%02X",$list),$dst);
  my $sRL = (    $sdH->{helper}{shadowReg}          # shadowregList
              && $sdH->{helper}{shadowReg}{$regLNp})
                           ?$sdH->{helper}{shadowReg}{$regLNp}
                           :"";
  my $rRL = ($hash->{READINGS}{$regLN})              #realRegList
                           ?$hash->{READINGS}{$regLN}{VAL}
                           :"";
  my $data=0;
  my $convFlg = "";# confirmation flag - indicates data not confirmed by device
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
    my ($dReadS,$dReadR) = (undef,"");  
    $dReadS = $1 if( $sRL =~ m/$addrS:(..)/);#shadowReg
    $dReadR = $1 if( $rRL =~ m/$addrS:(..)/);#realReg
    my $dRead = $dReadR;
    if (defined $dReadS){
      $convFlg = "set_" if ($dReadR ne $dReadS);
      $dRead = $dReadS;
    }
    else{
      return "invalid:peer missing"  if (grep /$regLN../,keys %{$hash->{READINGS}} &&
                                         !$peerId);
      if (!defined($dRead) || $dRead eq ""){
        return "invalid: not supported by FW version" if ($rRL =~ m/00:00/);#reglist is complete but still address cannot be found
        return "invalid";
      }
    }

    $data = ($data<< 8)+hex($dRead);
    $addr++;
  }

  $data = ($data>>$pos) & (0xffffffff>>(32-$size));
  if (!$conv){                ;# do nothing
  } elsif($conv eq "lit"     ){$data = defined $reg->{litInv}{$data} ? $reg->{litInv}{$data} : "undef lit:$data";
  } elsif($conv eq "fltCvT"  ){$data = CUL_HM_CvTflt($data);
  } elsif($conv eq "fltCvT60"){$data = CUL_HM_CvTflt60($data);
  } elsif($conv eq "min2time"){$data = CUL_HM_min2time($data);
  } elsif($conv eq "m10s3"   ){$data = ($data+3)/10;
  } elsif($conv eq "hex"     ){$data = sprintf("0x%06X",$data);#06 only for paired to. Currently not used by others
  } else { return " conv undefined - please contact admin";
  }
  $data /= $factor if ($factor);# obey factor after possible conversion
  if ($conv ne "lit" && $reg->{litInv} && $reg->{litInv}{$data} ){
    $data = $reg->{litInv}{$data};#conv special value past to calculation
    $unit = "";
  }     
  return $convFlg.$data.$unit;
}
sub CUL_HM_TmplSetCmd($){
  my $name = shift;
  return "" if(not scalar devspec2array("TYPE=HMinfo"));
  my $devId = substr($defs{$name}{DEF},0,6);
  my %a;
  my %tpl;
  my $helper = $defs{$name}{helper};
  
  my   @peers = map{$helper->{peerIDsH}{$_}} grep !/^(00000000|$devId)/,keys %{$helper->{peerIDsH}};
  push @peers,  map{"self".substr($_,-2)}    grep /^$devId/            ,keys %{$helper->{peerIDsH}};
  foreach my $peer($peers[0],"0"){ 
    next if (!defined $peer);
    $peer = "self".substr($peer,-2) if($peer =~ m/^${name}_chn-..$/);
    $peer = "self".substr($peer,-2) if($peer =~ m/^${name}_chn-..$/);
    my $ps = $peer eq "0" ? "R-" : "R-$peer-";
    my %b = map { $_ => 1 }map {(my $foo = $_) =~ s/.?$ps//; $foo;} grep/.?$ps/,keys%{$defs{$name}{READINGS}};
    foreach my $t(reverse sort keys %HMConfig::culHmTpl){
      next if (not scalar (keys %{$HMConfig::culHmTpl{$t}{reg}}));
      my $f = 0;
      my $typShLg=0;
      foreach my $r(keys %{$HMConfig::culHmTpl{$t}{reg}}){
        if(!defined $b{$r} && !defined $b{"sh".$r}){$f = 1;last;}
        $typShLg = defined $b{"sh".$r} ? 1 : 0;
      }
      if($f == 0){
        if($typShLg){
          foreach my $pAss (@peers){
            $a{$pAss}{$t."_short"} = 1;
            $a{$pAss}{$t."_long"} = 1;
            $tpl{p}{$t."_short"}  = 1;
            $tpl{p}{$t."_long"}   = 1;
          }
        }
        else{
          if ($peer eq "0"){
            $a{$peer}{$t} = 1;
            $tpl{0}{$t} = 1;
          }
          else{
            $a{$_}{$t} = 1  foreach(map{$_ =~ m/^${name}_chn-..$/ ? "self".substr($peer,-2) : $_}@peers);
            $tpl{p}{$t} = 1;
          }
        }
      }
    }
  };
  $defs{$name}{helper}{cmds}{lst}{tplPeer} = join(",",sort keys%{$tpl{p}});
  $defs{$name}{helper}{cmds}{lst}{tplChan} = join(",",sort keys%{$tpl{0}});
  return (scalar keys %a ? " tplSet_".join(" tplSet_",map{"$_:".join(",",sort keys%{$a{$_}})} keys %a)
                         : "")#no template
         ;
}
sub CUL_HM_TmplSetParam($){
  my $name = shift;
  return "" if(not scalar devspec2array("TYPE=HMinfo"));
  my @tCmd;
  my $tCnt = 0; # template count
  foreach my $t(sort keys%{$defs{$name}{helper}{tmpl}}){
    if ($defs{$name}{helper}{tmpl}{$t}){# we have a parameter
      my($p,$tn) = split(">",$t);
      my @pv = split(" ",$defs{$name}{helper}{tmpl}{$t});
      my $pCnt = 0;     #parameter count
      $t =~ s/[:>]/_/g; # replace illegal chars for command
      next if(!defined $HMConfig::culHmTpl{$tn}||
              !defined $HMConfig::culHmTpl{$tn}{p});
      my $tnH = $HMConfig::culHmTpl{$tn};
      
      for my $pm (split(" ",$tnH->{p})){
        my ($reg1) = map{(my $foo = $_) =~ s/:.*//; $foo;}
                     grep/p$pCnt/,
                     map{$_.":".$tnH->{reg}{$_}}
                     keys%{$tnH->{reg}}
                     ;
        my $literals = "";
        my $reglH = $culHmRegDefine->{$reg1};
        if(defined $reglH->{c} && $reglH->{c} eq "lit"){
          $literals = ":".join(",",keys%{$reglH->{lit}})
        }
        push @tCmd,"tplPara".sprintf("%02d%d_",$tCnt,$pCnt++).join("_",$t,$pm).$literals;
      }
    }
    $tCnt++;
  }
  return " ".join(" ",@tCmd);
}    

sub CUL_HM_chgExpLvl($){# update visibility and set internal values for expert 
  my $tHash = shift;

  delete $tHash->{helper}{expert};
  $tHash->{helper}{expert}{def} = 0;
  $tHash->{helper}{expert}{det} = 0;
  $tHash->{helper}{expert}{raw} = 0;
  $tHash->{helper}{expert}{tpl} = 0;
  foreach my $expSet (split(",",CUL_HM_getAttr($tHash->{NAME},"expert","defReg"))){
    $tHash->{helper}{expert}{def} = 1 if($expSet eq "defReg"
                                       ||$expSet eq "allReg");#default register on
    $tHash->{helper}{expert}{det} = 1 if($expSet eq "allReg");#detail register on
    $tHash->{helper}{expert}{raw} = 1 if($expSet eq "rawReg");#raw register on
    $tHash->{helper}{expert}{tpl} = 1 if($expSet eq "templ") ;#template on
  }
  my ($det,$def,$raw) = ($tHash->{helper}{expert}{det}
                        ,$tHash->{helper}{expert}{def}
                        ,$tHash->{helper}{expert}{raw});
  foreach my $rdEntry (grep /^(\.R|R)-/   ,keys %{$tHash->{READINGS}}){
    my $rdEntryPure = $rdEntry;
    $rdEntryPure =~ s/^\.//;

    my $reg = $rdEntryPure;
    $reg =~ s/-temp$/##temp/; # rescue ugly registernames prior  to replacement
    $reg =~ s/^R.*-//;
    $reg =~ s/##temp$/-temp/; # and revert
    next if(!$culHmRegDefine->{$reg});
    
    my $nTag = (( $culHmRegDefine->{$reg}{d} && $def)
            ||  (!$culHmRegDefine->{$reg}{d} && $det))
               ? ""
               : "."
               ;
    if ($nTag.$rdEntryPure ne $rdEntry){# have to change
      $tHash->{READINGS}{$nTag.$rdEntryPure} = $tHash->{READINGS}{$rdEntry};
      delete $tHash->{READINGS}{$rdEntry};
    }
  }

  my $nTag = $raw ? "":".";

  foreach my $rdEntry (grep /^(\.R|R)egL_/   ,keys %{$tHash->{READINGS}}){
    my $reg = $rdEntry;
    $reg =~ s/^\.//;
    if ($nTag.$reg ne $rdEntry){# have to change
      $tHash->{READINGS}{$nTag.$reg} = $tHash->{READINGS}{$rdEntry};
      delete $tHash->{READINGS}{$rdEntry};
    }
  }
  CUL_HM_setTmplDisp($tHash);
}
sub CUL_HM_setTmplDisp($){ # remove register if outdated
  my $tHash = shift;
  $tHash->{helper}{cmds}{TmplTs} = gettimeofday(); #set marker to update command list
  delete $tHash->{READINGS}{$_} foreach (grep /^tmpl_/ ,keys %{$tHash->{READINGS}});
  if ($tHash->{helper}{expert}{tpl} && (%HMConfig::culHmTpl)){
    foreach (keys %{$tHash->{helper}{tmpl}}){
      my ($p,$t) = split(">",$_);
      my @param;
      if($tHash->{helper}{tmpl}{$_}){
        @param = split(" ",$HMConfig::culHmTpl{$t}{p});
        my @value = split(" ",$tHash->{helper}{tmpl}{$_});
        for (my $i = 0; $i<scalar(@value); $i++){
         $param[$i] .= ":".$value[$i];
        }
        $t .= ":".join(" ",@param);
      }
      $tHash->{READINGS}{"tmpl_".$p}{VAL} .= $t.",";#could be more than one!
      $tHash->{READINGS}{"tmpl_".$p}{TIME} .= "-";# time does not make sense
    }
  }
}
sub CUL_HM_updtRegDisp($$$) {
  my($hash,$list,$peerId)=@_;
  my $listNo += $list;
  my $name = $hash->{NAME};
  my $devId = substr(CUL_HM_name2Id($name),0,6);
  my $ioId = CUL_HM_IoId(CUL_HM_id2Hash($devId));
  my $pReg = ($peerId && $peerId ne '00000000' )
              ? CUL_HM_peerChName($peerId,$devId)."-"
              : "";
  $pReg =~ s/:/-/;
  $pReg = "R-".$pReg;
#  $pReg =~ s/_chn-..//;
  my $devName =CUL_HM_getDeviceHash($hash)->{NAME};# devName as protocol entity
  my $st = $attr{$devName}{subType} ?$attr{$devName}{subType} :"";
  my $md = CUL_HM_getAliasModel($hash);
  my $chn = $hash->{DEF};
  $chn = (length($chn) == 8)?substr($chn,6,2):"";
  my @regArr = CUL_HM_getRegN($st,$md,$chn);
  my @changedRead;
  
  
  if(  !CUL_HM_getPeers($name,"ID:$peerId") 
     && CUL_HM_getPeers($name,"ID:".substr($peerId,0,6))){
    ($peerId) = CUL_HM_getPeers($name,"ID:".substr($peerId,0,6));
  }

  my $regLN = ($hash->{helper}{expert}{raw}?"":".")
              .sprintf("RegL_%02X.",$listNo)
              .($peerId ? CUL_HM_peerChName($peerId,$devId) : "");
  if ($listNo == 0) {
    if    ($md eq "HM-MOD-RE-8") {#handle Fw bug 
      CUL_HM_ModRe8($hash,$regLN);
    }
  }
  foreach my $rgN (@regArr){
    next if ($culHmRegDefine->{$rgN}->{l} ne $listNo);
    my $rgVal = CUL_HM_getRegFromStore($name,$rgN,$list,$peerId,$regLN);
    next if (!defined $rgVal || $rgVal =~ m/invalid/);
    my $rdN = ($culHmRegDefine->{$rgN}->{d} ? ($hash->{helper}{expert}{def} ?"":".")
                                            : ($hash->{helper}{expert}{det} ?"":"."))
              .$pReg.$rgN;
    push (@changedRead,$rdN.":".$rgVal)
          if (ReadingsVal($name,$rdN,"") ne $rgVal);
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  # ---  handle specifics -  Devices with abnormal or long register
  if    ($md =~ m/^(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){#handle temperature readings
    CUL_HM_TCtempReadings($hash)  if (($list == 5 ||$list == 6) &&
                      substr($hash->{DEF},6,2) eq "02");
  }
  elsif ($md =~ m/^HM-CC-RT-DN/){#handle temperature readings
    CUL_HM_TCITRTtempReadings($hash,$md,7)  if ($list == 7 && $chn eq "04");
  }
  elsif ($md =~ m/^HM-TC-IT-WM-W-EU/){#handle temperature readings
    CUL_HM_TCITRTtempReadings($hash,$md,$list)  if ($list >= 7 && $chn eq "02");
  }
  elsif (ReadingsVal($name,".RegL_01.",ReadingsVal($name,"RegL_01.","")) =~ m / 36:/){#add text
    CUL_HM_4DisText($hash)  if ($list == 1) ;
  }
  elsif ($st eq "repeater"){
    CUL_HM_repReadings($hash) if ($list == 2);
  }
  elsif ($md eq "HM-SEC-SD-2"){
    CUL_HM_SD_2($hash) if ($list == 0);
  }
  CUL_HM_cfgStateDelay($name);#schedule check when finished
}
sub CUL_HM_cfgStateDelay($) {#update cfgState: schedule for devices
  my $name = shift;
  return if IsIgnored($name);
  CUL_HM_cfgStateUpdate("cfgStateUpdate:".CUL_HM_getDeviceName($name));
}
sub CUL_HM_cfgStateUpdate($) {#update cfgState
  my $tmrId = shift;
  my (undef,$name) = split(':',$tmrId,2);
  return if (!defined $defs{$name} );
  RemoveInternalTimer("cfgStateUpdate:$name") if($defs{$name}{helper}{cfgStateUpdt});#could be direct call or timeout
  if (   !$evtDly && $init_done && $fhem_started + 30 < time      #noansi: first Readings must be set, helps also not to disturb others
      && !$defs{$name}{helper}{prt}{sProc} #not busy with commands?
      ){
    $defs{$name}{helper}{cfgStateUpdt} = 0;
    my ($hm) = devspec2array("TYPE=HMinfo");
    HMinfo_GetFn($defs{$hm},$hm,"configCheck","-f","^(".join("|",(CUL_HM_getAssChnNames($name),$name,CUL_HM_getPeers($name,"NamesExt"))).")\$") if (defined $hm);
  }
  else {
    $defs{$name}{helper}{cfgStateUpdt} = 1;  # use to remove duplicate timer                                                                       
    InternalTimer(gettimeofday() + 60, "CUL_HM_cfgStateUpdate","cfgStateUpdate:$name", 0) if ($init_done || length(CUL_HM_name2Id($name)) == 6); # try later
  }
  return;
}

sub CUL_HM_rmOldRegs($$){ # remove register i outdated
  #will remove register for deleted peers
  my ($name,$readCont) = @_;
  my $hash = $defs{$name};
  return if (!$hash->{peerList});# so far only peer-regs are removed
  my @rpList;
  foreach(grep /^R-(.*)-/,keys %{$hash->{READINGS}}){
    push @rpList,$1 if ($_ =~ m/^R-(.*)-/);
  }
  @rpList = CUL_HM_noDup(@rpList);
  return if (!@rpList);
  foreach my $peer(@rpList){
    $peer =~ s/_chn-..$//;
    next if($hash->{peerList} =~ m/\b$peer\b/);
    delete $hash->{READINGS}{$_} foreach (grep /^R-${peer}-/,keys %{$hash->{READINGS}});
    delete $hash->{READINGS}{$_} foreach (grep /^R-${peer}_chn-..-/,keys %{$hash->{READINGS}});
  }
  if($readCont){
    CUL_HM_cfgStateDelay($name);
 }
}
sub CUL_HM_refreshRegs($){ # renew all register readings from Regl_
  my $name = shift;
  return if !defined $defs{$name};
  foreach(grep /\.?R-/,keys %{$defs{$name}{READINGS}}){
    delete $defs{$name}{READINGS}{$_};
  }
  my $peers = ReadingsVal($name,"peerList","");
  my $dH = CUL_HM_getDeviceHash($defs{$name}) // return;
  foreach(grep /\.?RegL_/,keys %{$defs{$name}{READINGS}}){
    my ($l,$p);
    ($l,$p) = ($1,$2) if($_ =~ m/RegL_(..)\.(.*)/);
    my $ps = $p;
    $ps =~ s/_chn-\d\d$// if (defined $ps);
    if (!$p || defined $ps && $peers =~ m/$ps/){
      CUL_HM_updtRegDisp($defs{$name},$l,CUL_HM_name2Id($p,$dH));
    }
    else{
      delete $defs{$name}{READINGS}{$_};# peer for This List not found
    }
  }
  CUL_HM_cfgStateDelay($name);
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
  return "0000" if($v !~ m/^[+-]?\d+(\.\d+)?$/ || $v < 0.05);

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
  return (2**$e)*$m*0.1;
}
sub CUL_HM_secSince2000() {#####################
  # Calculate the local time in seconds from 2000.
  my $t = time();

  my @l = localtime($t);
  my @g = gmtime($t);
  my $t2 = $t + 60*(($l[2]-$g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1]-$g[1])
                           # timezone and daylight saving...
        - 946684800        # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
        - 3600;            # HM Special
  return $t2;
}
sub CUL_HM_getChnLvl($){# in: name out: vit or phys level
  my $name = shift;
  my $curVal = ReadingsVal($name,"level",ReadingsVal($name,".level",0));
  $curVal =~ s/.*?(\d+\.?\d*).*/$1/;
  $curVal = 0 if ($curVal eq "" || $curVal <0 || $curVal >100 );
  return $curVal;
}

#--------------- Conversion routines for register settings---------------------
sub CUL_HM_initRegHash() { #duplicate short and long press register
  my $mp = "$attr{global}{modpath}/FHEM";
  opendir(DH, $mp) || return;
  foreach my $m (grep /^HMConfig_(.*)\.pm$/,readdir(DH)) {
    my $file = "${mp}/$m";
    no strict "refs";
      my $ret = do $file;
    use strict "refs";
    if(!$ret){ 
      Log3 undef, 1, "Error loading file: $file:\n $@";
    }
    else     { # success - now update some datafiels
      Log3 undef, 3, "additional HM config file loaded: $file";
      foreach (sort keys %{$culHmModel}){
        next if(!$_);
        $culHmModel2Id->{$culHmModel->{$_}{name}} = $_ ;
        $culHmModel->{$_}{alias} = $culHmModel->{$_}{name} if (!defined $culHmModel->{$_}{alias});
      }
    }
  }
  closedir(DH);
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

sub CUL_HM_flt6CvT($) { # float -> config time
  my ($inValue) = @_;
  my $exp = ($inValue>127)?1:0;
  return ($exp << 7)+int($inValue/($exp?60:1));
}
sub CUL_HM_CvTflt6($) { # config time -> float
  my ($inValue) = @_;
  $inValue = 129 if ($inValue == 128);
  return ($inValue & 0x7f)*(($inValue >> 7)?60:1);
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

sub CUL_HM_getRegInfo($) { # 
  my ($name) = @_;
  my $hash = $defs{$name} // return;
  my $devHash = CUL_HM_getDeviceHash($hash) // return;
  my $st  = AttrVal    ($devHash->{NAME},"subType", "" );
  my $md  = CUL_HM_getAliasModel($hash);#AttrVal    ($devHash->{NAME},"model"  , "" );
  my $roleD  = $hash->{helper}{role}{dev} ? 1 : 0;
  my $roleC  = $hash->{helper}{role}{chn} ? 1 : 0;
  my $chn = $roleD ? "00" : InternalVal($hash->{NAME}   ,"chanNo" ,"00");
  my @regArr = CUL_HM_getRegN($st,$md,$chn);

  my @rI;
  foreach my $regName (@regArr){
    my $reg  = $culHmRegDefine->{$regName};
    my $help = $reg->{t};
    my ($min,$max) = ($reg->{min},"to ".$reg->{max});
    if ($reg->{c} eq "lit"){
      $help .= " options:".join(",",keys%{$reg->{lit}});
      $min = "";
      $max = "literal";
    }
    elsif (defined($reg->{lit})){
      $help .= " special:".join(",",keys%{$reg->{lit}});
    }
    my $cp = $reg->{l}."p";
    push @rI,sprintf("%4d: %-16s | %3s %-14s | %8s | %s\n",
                      $reg->{l},$regName
                     ,$min
                     ,$max.$reg->{u}
                     ,($reg->{p} eq 'y' ? "required" : "")
                     ,$help)
          if (($roleD && $reg->{l} == 0)||
              ($roleC && $reg->{l} != 0));
  }

  my $info = sprintf("list: %16s | %-18s | %-8s | %s\n",
                   "register","range","peer","description");
  foreach(sort(@rI)){$info .= $_;}
  return $info;
}
sub CUL_HM_getRegN($$@){ # get list of register for a model
  my ($st,$md,@chn) = @_;
  my @regArr = keys %{$culHmRegGeneral};
  push @regArr, keys %{$culHmRegType->{$st}}      if($culHmRegType->{$st});
  push @regArr, keys %{$culHmRegModel->{$md}}     if($culHmRegModel->{$md});
 
  foreach (@chn){
    push @regArr, keys %{$culHmRegChan->{$md.$_}} if($culHmRegChan->{$md.$_});
  }
  return @regArr;
}
sub CUL_HM_getChnList($){ # get reglist assotiated with a channel
  my ($name) = @_;
  my $hash = $defs{$name};
  my $devHash = CUL_HM_getDeviceHash($hash);  
  my $chnN = hex(InternalVal($name,"chanNo","0"));
  $chnN = "-" if ($chnN == 0);
  return undef if (!$devHash->{helper}{mId});
  my @chRl;

  if    ($hash->{helper}{role}{vrt}){
  }
  elsif ($hash->{helper}{role}{dev}){
    push @chRl,"0";
  }
  foreach my $mLst(split(",",$culHmModel->{$devHash->{helper}{mId}}{lst})){
    my ($Lst,$cLst) = split(":",$mLst.":$chnN"); # if channel  not given in "lst" then use for all channels!
    next if ($Lst eq "p" || $cLst eq "-");# no list, just peers
    foreach my $aaa (grep /$chnN/,split('\.',$cLst)){
      $Lst .= "p" if($Lst =~ m/^[34]$/ || $aaa =~ m/p/);
      $Lst =~ s/ //g;
      push @chRl,$Lst;
    }
  }
  return join(",",sort @chRl );
}

sub CUL_HM_getPeers($$)   { #return peering information - status and lists
   my ($name,$type) = @_;
   return () if(!defined $name || !defined $defs{$name}|| !defined $defs{$name}{DEF});
   my $hashH = $defs{$name}{helper};
   my ($devId,$chn) = unpack 'A6A2',$defs{$name}{DEF};

   if    ($type eq "IDs"           ){return                             grep!/00000000/         ,keys%{$hashH->{peerIDsH}};}
   elsif ($type eq "IDsExt"        ){return                             grep!/(00000000|$devId)/,keys%{$hashH->{peerIDsH}};}#only external peers
   elsif ($type eq "IDsSelf"       ){return                             grep /$devId/           ,keys%{$hashH->{peerIDsH}};}#only own peers
   elsif ($type eq "Names"         ){return grep/./,map{(my $foo = $hashH->{peerIDsH}{$_}) =~ s/_chn-..$//;
                                                         $foo}
                                                                        grep!/00000000/         ,keys%{$hashH->{peerIDsH}};}#all peer names
   elsif ($type eq "NamesExt"      ){return grep/./,map{(my $foo = $hashH->{peerIDsH}{$_}) =~ s/_chn-..$//;
                                                         defined($defs{$foo})?$foo:""}
                                                                        grep!/(00000000|$devId)/,keys%{$hashH->{peerIDsH}};}#all external names
   elsif ($type eq "NamesSelf"     ){return map{$hashH->{peerIDsH}{$_}} grep /$devId/           ,keys%{$hashH->{peerIDsH}};}#all own names
   elsif ($type eq "IDsRaw"        ){return                                                      keys%{$hashH->{peerIDsH}};}
   elsif ($type eq "Status"        ){
       return defined $hashH->{peerIDsH}{"00000000"} ? "complete" : "incomplete";
       return "peerUnread" if(0 == scalar keys%{$hashH->{peerIDsH}});
   }
   elsif ($type eq "Config"        ){
       # return 0: no peers expected 
       #        1: peers expected, list valid 
       #        2: peers expected, list invalid 
       #        3: peers possible (virtuall actor)
       return 0 if (!$hashH->{role}{chn});#device has no channels
       return 3 if ($hashH->{role}{vrt});
       my $mId = CUL_HM_getMId($defs{$name});
       return 0 if (!$mId || !$culHmModel->{$mId});
       my $cNo = hex(substr($defs{$name}{DEF}."01",6,2))."p"; #default to channel 01
       foreach my $ls (split ",",$culHmModel->{$mId}{lst}){
         my ($l,$c) = split":",$ls;
         if (  ($l =~ m/^(p|3|4)$/ && !$c )  # 3,4,p without chanspec
             ||($c && $c =~ m/$cNo/       )){
           return (defined $hashH->{peerIDsH}{"00000000"} ? 1 : 2);
         }
       }
       return 0;
   }
   elsif ($type =~ m/^ID:(.{8})$/  ){return $hashH->{peerIDsH}{$1} if (defined $hashH->{peerIDsH}{$1});}
   elsif ($type =~ m/^ID:(.{6})$/  ){return                             grep /$1../             ,keys%{$hashH->{peerIDsH}};}#peers for a device
   elsif ($type =~ m/^Name:(.{6})$/){return grep/./,map{(my $foo = $hashH->{peerIDsH}{$_}) =~ s/_chn-..$//;
                                                         defined($defs{$foo})?$foo:""}
                                                                        grep /$1../             ,keys%{$hashH->{peerIDsH}};}#peers for a device
     ();
}
sub CUL_HM_getChnPeers($){ #which peertype am I
  my ($name) = @_;
  my $hash = $defs{$name};
  my $devHash = CUL_HM_getDeviceHash($hash);  
  return "-" if (!$devHash->{helper}{mId});
  my $chnN = hex(InternalVal($name,"chanNo","0"));
  $chnN = "-" if ($chnN == 0);
  my @chPopt;
  return "-:-" if($devHash->{helper}{mId} eq "0000");
  
  if ($hash->{helper}{role}{chn}){
    if ($hash->{helper}{role}{vrt}){
      push @chPopt,"v";# all except action detector
    }
    else{
      foreach my $mLst(split(",",$culHmModel->{$devHash->{helper}{mId}}{lst})){
        my ($Lst,$cLst) = split(":",$mLst.":-");
        push @chPopt,$Lst     if ($Lst =~ m /[p34]/ && $cLst =~m /[-$chnN]/);
        push @chPopt,$Lst."p" if ($Lst !~ m /[p34]/ && $cLst =~m /[$chnN]p/);
      }   
    }
  }
  push @chPopt,'-' if(!scalar @chPopt);
  return join(",",map{$_.":".$culHmModel->{$devHash->{helper}{mId}}{st}} sort @chPopt);
}
sub CUL_HM_getChnPeerFriend($){ #which are my peerFriends
#$defs{$_}{helper}{peerFriend} = CUL_HM_getChnPeerFriend
  my ($name)  = @_;
  my $hash    = $defs{$name};
  return "-" if(!$hash->{helper}{role}{chn});
  my $devHash = CUL_HM_getDeviceHash($hash);  
  return "-" if (!$devHash->{helper}{mId});
  my $mIdA    = $devHash->{helper}{mId};
  my $peerOpt = $hash->{helper}{peerOpt};
  my $chn     = InternalVal($name,"chanNo","");

  my @chPopt;
  
  if    ($peerOpt =~ m/4:/ )                       {push @chPopt,"peerAct","peerVirt"         ;}
  elsif ($peerOpt =~ m/3:/ )                       {push @chPopt,"peerSens","peerVirt"        ;}
  elsif ($peerOpt eq "p:display" )                 {push @chPopt,"peerAct","peerVirt"         ;}
  elsif ($peerOpt eq "p:smokeDetector" )           {push @chPopt,"peerSD"                     ;}
  elsif ($peerOpt eq "-:virtual" && $chn eq "01" ) {push @chPopt,"peerSD","peerSens","peerAct";}
  elsif ($peerOpt eq "-:virtual"         )         {push @chPopt,"peerSens","peerAct"         ;}
  elsif ($peerOpt eq "p:THPLSensor"      )         {push @chPopt,"peerRecT"                   ;}
  elsif ($mIdA eq "0095" && $chn eq "01" )         {push @chPopt,"peerSensT"                  ;}
  elsif ($mIdA eq "00AD" && $chn eq "01" )         {push @chPopt,"peerSensT"                  ;}
  elsif ($mIdA eq "0095" && $chn eq "04" )         {push @chPopt,"peerRTteam2"                ;}
  elsif ($mIdA eq "0095" && $chn eq "05" )         {push @chPopt,"peerRTteam1"                ;}
  elsif ($mIdA eq "0095" && $chn eq "02" )         {push @chPopt,"peerRtTc"                   ;}
  elsif ($mIdA eq "00AD" && $chn eq "02" )         {push @chPopt,"peerRtTc"                   ;}
  return join(",",@chPopt);
}

sub CUL_HM_getPeerOption($){ #who are my friends? Whom can I peer to, who can I unpeer
  my ($name)  = @_; 
  CUL_HM_calcPeerOptions() if(!$modules{CUL_HM}{helper}{peerOpt});

  my %curPTmp;  
  if($defs{$name}{helper}{peerFriend}){
    $curPTmp{$_} = $_              foreach(grep !/$name/,
                                       split(",",
                                       join(",",map{$modules{CUL_HM}{helper}{peerOpt}{$_}}
                                                grep!/^-$/,
                                                split(",",$defs{$name}{helper}{peerFriend}))));
  }
  if($defs{$name}{helper}{peerIDsH}){
    $curPTmp{$_} = "remove_".$_    foreach(grep !/(broadcast|self)/,values %{$defs{$name}{helper}{peerIDsH}});
  }
  my @peers = sort values %curPTmp;
  
  return join(",",(grep/remove/ ,@peers)   # offer remove first
                 ,(grep!/remove/,@peers));  
}
sub CUL_HM_calcPeerOptions(){ # calculation peering options
  my @peerAct;     # normal actor
  my @peerSens;    # normal sensor
  my @peerSD;      # smoke detector
  my @peerVirt;    # virtual
  my @peerSensT;   # Sensor Temperature
  my @peerRecT;    # receiver Temperature
  my @peerRTteam1; # RT team Clima     <-> ClimaTeam
  my @peerRTteam2; # RT team ClimaTeam <-> Clima
  my @peerRtTc;    # RT - TC
  my @peerTcRt;    # TC - RT

  foreach(devspec2array("TYPE=CUL_HM:FILTER=chanNo=..")){
    my $devHash = CUL_HM_getDeviceHash($defs{$_});  
    my $mIdA    = $devHash->{helper}{mId};
    next if (!defined $defs{$_} 
          || !defined $defs{$_}{helper} 
          || !$mIdA
          || !$defs{$_}{helper}{peerOpt});
    my $peerOpt = $defs{$_}{helper}{peerOpt};
    my $chn     = $defs{$_}{chanNo};
    
    push @peerAct    ,$_ if ($peerOpt =~ m/3:/             ); 
    push @peerSens   ,$_ if ($peerOpt =~ m/4:/             ); 
    push @peerSD     ,$_ if ($peerOpt eq "p:smokeDetector" );
    push @peerSD     ,$_ if ($peerOpt eq "-:virtual"       && $chn eq "01");# chan 01 
    push @peerVirt   ,$_ if ($peerOpt eq "-:virtual"       ); 
    push @peerSensT  ,$_ if ($peerOpt eq "p:THPLSensor"    );     
    push @peerRecT   ,$_ if ($mIdA eq "0095"         && $chn eq "01");   # HM-CC-RT-DN      Weather
    push @peerRecT   ,$_ if ($mIdA eq "00AD"         && $chn eq "01");   # HM-TC-IT-WM-W-EU Weather
    push @peerRTteam1,$_ if ($mIdA eq "0095"         && $chn eq "04");   # HM-CC-RT-DN      Clima     <-> HM-CC-RT-DN      ClimaTeam
    push @peerRTteam2,$_ if ($mIdA eq "0095"         && $chn eq "05");   # HM-CC-RT-DN      ClimaTeam <-> HM-CC-RT-DN      Clima
    push @peerRtTc   ,$_ if ($mIdA eq "0095"         && $chn eq "02");   # HM-CC-RT-DN      Climate   <-> HM-TC-IT-WM-W-EU Climate
    push @peerTcRt   ,$_ if ($mIdA eq "00AD"         && $chn eq "02");   # HM-TC-IT-WM-W-EU Climate   <-> HM-CC-RT-DN      Climate
  }
  $modules{CUL_HM}{helper}{peerOpt}{peerAct}     = join(",",@peerAct    );
  $modules{CUL_HM}{helper}{peerOpt}{peerSens}    = join(",",@peerSens   );
  $modules{CUL_HM}{helper}{peerOpt}{peerSD}      = join(",",@peerSD     );
  $modules{CUL_HM}{helper}{peerOpt}{peerVirt}    = join(",",@peerVirt   );
  $modules{CUL_HM}{helper}{peerOpt}{peerSensT}   = join(",",@peerSensT  );
  $modules{CUL_HM}{helper}{peerOpt}{peerRecT}    = join(",",@peerRecT   );
  $modules{CUL_HM}{helper}{peerOpt}{peerRTteam1} = join(",",@peerRTteam1);
  $modules{CUL_HM}{helper}{peerOpt}{peerRTteam2} = join(",",@peerRTteam2);
  $modules{CUL_HM}{helper}{peerOpt}{peerRtTc}    = join(",",@peerRtTc   );
  $modules{CUL_HM}{helper}{peerOpt}{peerTcRt}    = join(",",@peerTcRt   );
  return ;
}

sub CUL_HM_4DisText($) {      # convert text for 4dis
  #text1: start at 54 (0x36) length 12 (0x0c)
  #text2: start at 70 (0x46) length 12 (0x0c)
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ($hash->{helper}{expert}{raw}?"":".");
  my $reg1 = ReadingsVal($name,$regPre."RegL_01." ,"");
  my $pref = "";
  if ($hash->{helper}{shadowReg}{"RegL_01."}){
    $pref = "set_";
    $reg1 = $hash->{helper}{shadowReg}{"RegL_01."};
  }
  my %txt;
  foreach my $sAddr (54,70){
    my $txtHex = $reg1;  #one row
    my $sStr = sprintf("%02X:",$sAddr);
    $txtHex =~ s/.* $sStr//;       #remove reg prior to string
    $sStr = sprintf("%02X:",$sAddr+11);
    $txtHex =~ s/$sStr(..).*/,$1/; #remove reg after string
    $txtHex =~ s/ ..:/,/g;         #remove addr
    $txtHex =~ s/ //g;             #remove space
    $txtHex =~ s/,00.*//;          #remove trailing string
    $txt{$sAddr} = "";
    my @ch = split(",",$txtHex,12);
    foreach (@ch){$txt{$sAddr}.=chr(hex($_)) if (length($_)==2)};
  }
  CUL_HM_UpdtReadBulk($hash,1,"text1:".$pref.$txt{54},
                              "text2:".$pref.$txt{70});
  return "text1:".$txt{54}."\n".
         "text2:".$txt{70}."\n";
}
sub CUL_HM_TCtempReadings($) {# parse TC temperature readings
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $regPre = ($hash->{helper}{expert}{raw}?"":".");
  my $reg5   = ReadingsVal($name,$regPre."RegL_05." ,"");
  my $reg6   = ReadingsVal($name,$regPre."RegL_06." ,"");
  { #update readings in device - oldfashioned style, copy from Readings
    my @histVals;
    foreach my $var ("displayMode","displayTemp","controlMode","decalcDay","displayTempUnit","day-temp","night-temp","party-temp"){
      my $varV = ReadingsVal($name,"R-".$var,ReadingsVal($name,".R-".$var,"???"));
      
      foreach my $e( grep {${$_}[2] =~ m/$var/}# see if change is pending
                     grep {$hash eq ${$_}[0]}
                     grep {scalar(@{$_} == 3)}
                     @evtEt){
        $varV = ${$e}[2];
        $varV =~ s/^\.?R-$var:// ;
      }
      push @histVals,"$var:$varV";
    }
    if (@histVals){
      CUL_HM_UpdtReadBulk($hash,1,@histVals) ;
      CUL_HM_UpdtReadBulk(CUL_HM_getDeviceHash($hash),1,@histVals);
    }
  }
  
  if (ReadingsVal($name,"R-controlMode","") =~ m/^party/){
    if (   $reg6                # ugly handling to add vanishing party register
        && $reg6 !~ m/ 61:/
        && $hash->{helper}{partyReg}){
      $hash->{READINGS}{"RegL_06."}{VAL} =~ s/ 00:00/$hash->{helper}{partyReg}/;
    }
   }
  else{
    delete $hash->{helper}{partyReg};
  }

  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
  $reg5 =~ s/.* 0B://;     #remove register up to addr 11 from list 5
  my $tempRegs = $reg5.$reg6;  #one row
  $tempRegs =~ s/00:00//g;   #remove regline termination
  $tempRegs =~ s/ ..:/,/g;     #remove addr Info
  $tempRegs =~ s/ //g;         #blank
  my @Tregs = split(",",$tempRegs);
  my @time  = @Tregs[grep !($_ % 2), 0..$#Tregs]; # even-index =time
  my @temp  = @Tregs[grep $_ % 2, 0..$#Tregs];    # odd-index  =data

  my @changedRead;
  my $setting;
  if (scalar( @time )<168){
    push (@changedRead,"R_tempList_State:incomplete");
    $setting = "reglist incomplete\n" ;
  }
  else{
    delete $hash->{READINGS}{$_} 
            foreach (grep !/_/,grep /tempList/,keys %{$hash->{READINGS}});
    
    foreach  (@time){$_=hex($_)*10};
    foreach  (@temp){$_=hex($_)/2};
    push (@changedRead,"R_tempList_State:".
                  (($hash->{helper}{shadowReg}{"RegL_05."} ||
                    $hash->{helper}{shadowReg}{"RegL_06."} )?"set":"verified"));
    for (my $day = 0; $day < 7; $day++){
      my $tSpan  = 0;
      my $dayRead = "";
      for (my $entry = 0;$entry<24;$entry++){
        my $reg = $day *24 + $entry;
        last if ($tSpan > 1430);
        $tSpan = $time[$reg];
        my $entry = sprintf("%02d:%02d %3.01f",($tSpan/60),($tSpan%60),$temp[$reg]);
          $setting .= "Temp set: ${day}_".$days[$day]." ".$entry." C\n";
          $dayRead .= " ".$entry;
        $tSpan = $time[$reg];
      }
      push (@changedRead,"R_${day}_tempList$days[$day]:$dayRead");
    }
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  return $setting;
}
sub CUL_HM_SD_2($)           {# parse SD2
  my ($hash)=@_;
  my $rep = CUL_HM_getRegFromStore($hash->{NAME},"devRepeatCntMax",0,"","");
  if ($rep eq "1"){
    CUL_HM_UpdtReadBulk($hash,1,"sdRepeat:on");
    $hash->{sdRepeat} = "on";
  }
  elsif($rep eq "0"){
    CUL_HM_UpdtReadBulk($hash,1,"sdRepeat:off");
  }
  else{
    CUL_HM_UpdtReadBulk($hash,1,"sdRepeat:$rep");
  }
}
sub CUL_HM_TCITRTtempReadings($$@) {# parse RT - TC-IT temperature readings
  my ($hash,$md,@list)=@_;
  my $name = $hash->{NAME};
  my $regPre = ($hash->{helper}{expert}{raw}?"":".");
  my @changedRead;
  my $setting="";
  my %idxN = (7=>"P1_",8=>"P2_",9=>"P3_");
  $idxN{7} = "" if($md =~ m/CC-RT/);# not prefix for RT
  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
  delete $hash->{READINGS}{hyst2pointWrite};
  
  foreach my $lst (@list){
    my @r1;
    $lst +=0;
    # cleanup old value formats
    my $ln = length($idxN{$lst})?substr($idxN{$lst},0,2):"";
    delete $hash->{READINGS}{$_} 
          foreach (grep !/_/,grep /tempList$ln/,keys %{$hash->{READINGS}});
    my $tempRegs = ReadingsVal($name,$regPre."RegL_0$lst.","");
    if ($tempRegs !~ m/00:00/){
      # for (my $day = 0;$day<7;$day++){#leave days allone - state is incomplete should be enough
      #   push (@changedRead,"R_$idxN{$lst}${day}_tempList".$days[$day].":incomplete");
      # }
      push (@changedRead,"R_$idxN{$lst}tempList_State:incomplete");
      CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
      next;
    }

    foreach(split " ",$tempRegs){
      my ($a,$d) = split ":",$_;
      $r1[hex($a)] = $d;
    }

    if ($hash->{helper}{shadowReg}{"RegL_0$lst."}){
      my $ch = 0;
      foreach(split " ",$hash->{helper}{shadowReg}{"RegL_0$lst."}){
        my ($a,$d) = split ":",$_;
        $a = hex($a);
        $ch = 1 if ((!$r1[$a] || $r1[$a] ne $d) && $a >= 20);
        $r1[$a] = $d;
      }
      push (@changedRead,"R_$idxN{$lst}tempList_State:set") if ($ch);
    }
    else{
      push (@changedRead,"R_$idxN{$lst}tempList_State:verified");
    }
     
    $tempRegs = join("",@r1[20..scalar@r1-1]);
    for (my $day = 0;$day<7;$day++){
      my $dayRead = "";
      my @time;
      my @temp;
      if (length($tempRegs)<($day+1) *13*4) {
        push (@changedRead,"R_$idxN{$lst}${day}_tempList$days[$day]:incomplete");
        $setting .= "Temp set $idxN{$lst}: ${day}_".$days[$day]." incomplete\n";
      }
      else{
        foreach (unpack '(A4)*',substr($tempRegs,$day *13*4,13*4)){
          my $h = hex($_);
          push @temp,($h >> 9)/2;
          $h = ($h & 0x1ff) * 5;
          $h = sprintf("%02d:%02d",int($h / 60),($h%60));
          push @time,$h;
        }
        for (my $idx = 0;$idx<13;$idx++){
          my $entry = sprintf(" %s %04.01f",$time[$idx],$temp[$idx]);
            $setting .= "Temp set $idxN{$lst}: ${day}_".$days[$day].$entry." C\n";
            $dayRead .= $entry;
          last if ($time[$idx] eq "24:00");
        }
        push (@changedRead,"R_$idxN{$lst}${day}_tempList$days[$day]:$dayRead");
      }
    }
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
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
  delete $hash->{repeater} foreach(devspec2array("TYPE=CUL_HM"
                                                .":FILTER=DEF=......"
                                                .":FILTER=repeater=$hash->{NAME}"));
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
  push @readList,"repPeer_".sprintf("%02d",$_+1).":undefined" for(0..35);#set default empty
  my @retL;
  my @repAttr;
  push @repAttr," " for(0..35);
  foreach my$pId(sort keys %pCnt){
    my ($pdID,$bdcst,$no) = unpack('A6A2A2',$pId);
    my $fNo = $no-1;#shorthand field number, often used
    my $sName = CUL_HM_id2Name($pdID);
    if ($sName eq $pdID && $pD[$fNo] && $defs{$pD[$fNo]}){
      $sName = $defs{$pD[$fNo]}->{IODev}{NAME}
            if($attr{$defs{$pD[$fNo]}->{IODev}{NAME}}{hmId} eq $pdID);
    }
    my $eS = sprintf("%02d:%-15s %-15s %-3s %-4s",
               $no
              ,$sName
              ,((!$pS[$fNo] || $pS[$fNo] ne $sName)?"unknown":" dst>$pD[$fNo]")
              ,($bdcst eq "01"?"yes":"no ")
              ,($pB[$fNo] && (  ($bdcst eq "01" && $pB[$fNo] eq "y")
                              ||($bdcst eq "00" && $pB[$fNo] eq "n")) ?"ok":"fail")
              );
    $repAttr[$fNo] = "$sName:"
                .((!$pS[$fNo] || $pS[$fNo] ne $sName)?"-":$pD[$fNo])
                .":".($pB[$fNo]?$pB[$fNo]:"-");  

    my $dName = CUL_HM_getDeviceName($sName);
    $defs{$dName}{repeater} = $hash->{NAME} if ($defs{$dName});

    push @retL,$eS;
    $readList[$fNo]="repPeer_".$eS;
  }
  $attr{$hash->{NAME}}->{repPeers} = join",",@repAttr;
  CUL_HM_UpdtReadBulk($hash,0,@readList);
  return "No Source          Dest            Bcast\n". join"\n", sort @retL;
}
sub CUL_HM_ModRe8($$)     {   # repair FW bug
  #Register 18 may come with a wrong address - we will corrent that
  my ($hash,$regN)=@_;
  my $name = $hash->{NAME};
  my $rl0 = ReadingsVal($name,$regN,'');
  return if(  $rl0 !~ m/00:00/ # not if List is incomplete
            ||$rl0 =~ m/12:/ ); # reg 18 present, dont touch
  foreach my $ad (split(" ",$rl0)){
    my ($a,$d) = split(":",$ad);
    my $ah = hex($a);
    if ($ah & 0xe0 && (($ah & 0x1F) == 0x12)){
      Log3 $hash,3,"CUL_HM replace address $a to 0x12";
      $hash->{READINGS}{$regN}{VAL} =~ s/ $a:/ 12:/;
      last;
    }
  }
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
  CUL_HM_UpdtReadBulk($hash,0,"R-logicCombTxt:".$logicComb{$lComb}{txt} 
                             ,"R-logicCombCalc:".$logicComb{$lComb}{calc});
  return "";
}

#+++++++++++++++++ Action Detector ++++++++++++++++++++++++++++++++++++++++++++
# verify that devices are seen in a certain period of time
# It will generate events if no message is seen sourced by the device during
# that period.
# ActionDetector will use the fixed HMid 000000
sub CUL_HM_ActGetCreateHash() {# get ActionDetector - create if necessary
  return if (!$init_done);
  if (!$modules{CUL_HM}{defptr}{"000000"}){
    CommandDefine(undef,"ActionDetector CUL_HM 000000");
    $attr{ActionDetector}{actCycle} = 600;
    $attr{ActionDetector}{"event-on-change-reading"} = ".*";
  }
  my $actHash = $modules{CUL_HM}{defptr}{"000000"};
  my $actName = ($actHash ? $actHash->{NAME} : "");
  my $ac = AttrVal($actName,"actCycle",600);
  if (!$actHash->{helper}{actCycle} ||
      $actHash->{helper}{actCycle} != $ac){
    $actHash->{helper}{actCycle} = $ac;
    RemoveInternalTimer("ActionDetector");
    $actHash->{STATE} = "active";
    InternalTimer(gettimeofday()+$ac,"CUL_HM_ActCheck", "ActionDetector", 0);
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
  my $devName = CUL_HM_id2Name($devId);
  my $devHash = $defs{$devName};
  return "timeout format failed:$timeout" if($timeout !~ m/^\d\d\d:\d\d/);
  my ($cycleString,undef) = CUL_HM_time2sec($timeout);
  $attr{$devName}{actCycle} = $cycleString;
  $attr{$devName}{actStatus}="unset"; # force trigger
  my $actHash = CUL_HM_ActGetCreateHash();
  $actHash->{helper}{$devId}{start} = TimeNow();
  $actHash->{helper}{$devId}{start} =~ s/[\:\-\ ]//g;
  
  if(defined $devHash->{READINGS}{".protLastRcv"}){
    $devHash->{READINGS}{".protLastRcv"}{VAL} =~ s/[\:\-\ ]//g;
  }

  $actHash->{helper}{peers} = CUL_HM_noDupInString(
                       ($actHash->{helper}{peers}?$actHash->{helper}{peers}:"")
                       .",$devId");
  Log3 $actHash, 5,"Device ".$devName." added to ActionDetector with $cycleString time";
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
  Log3 $actHash,5,"Device ".$devName." removed from ActionDetector";
  RemoveInternalTimer("ActionDetector");
  CUL_HM_ActCheck("del");
  return;
}
sub CUL_HM_ActCheck($) {# perform supervision
  my ($call) = @_;
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $actName = $actHash->{NAME};
  my $peerIDs = $actHash->{helper}{peers}?$actHash->{helper}{peers}:"";
  my @event;
  my ($cntUnkn,$cntAliv,$cntDead,$cnt_Off) =(0,0,0,0);
  my $autoTry = CUL_HM_getAttrInt($actName,"actAutoTry",0);
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
    
    if(AttrVal($devName,"ignore",0)){
      delete $actHash->{READINGS}{"status_".$devName};
      next;
    }
    if(!$devName || !defined($attr{$devName}{actCycle})){
      CUL_HM_ActDel($devId);
      next;
    }
    my $state;
    my $oldState = AttrVal($devName,"actStatus","unset");
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
    if ($tSec == 0){# detection switched off
      $state = "switchedOff";
    }
    else{
      my $tLast = ReadingsVal($devName,".protLastRcv",0);
      my @t = localtime($tod - $tSec); #time since when a trigger is expected
      my $tSince = sprintf("%04d%02d%02d%02d%02d%02d",
                             $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
      if (!$tLast                  #cannot determine time
          || $tSince gt $tLast){   #no message received in window
        if ($actHash->{helper}{$devId}{start} < $tSince){  
          if($autoTry) { #try to send a statusRequest?
            my $try = $actHash->{helper}{$devId}{try} ? $actHash->{helper}{$devId}{try} : 0;
            
            $actHash->{helper}{$devId}{try} = $try + 1;
            if ($try < 3 || !($try % 4)){#try 3 times, then reduce speed
              if (CUL_HM_Ping($devName)){
                $state = $oldState;
                Log3 $actHash,4,"$devName uncertain. state:$state. Send pings $actHash->{helper}{$devId}{try}";
              }
              else{
                $actHash->{helper}{$devId}{try} = 999;
                $state = "dead";
              }
            }
            else{
              $state = "dead";
            }
          }
          else{
            $state = "dead";
          }
        }
        else{
          if(!$actHash->{helper}{$devId}{try}){# try once
            CUL_HM_Ping($devName);
            $actHash->{helper}{$devId}{try} = 901;
          }
          $state = "unknown";
        }
      }
      else{                         #message in time
        $state = "alive";
        delete $actHash->{helper}{$devId}{try};
      }
    }
    if ($oldState ne $state){
      CUL_HM_ActDepRead($devName,$state,$oldState);
      Log3 $actHash,5,"Device: $devName changed from:$oldState to-> $state";
    }
    if    ($state eq "unknown")    {$cntUnkn++;} 
    elsif ($state eq "alive")      {$cntAliv++;} 
    elsif ($state eq "dead")       {$cntDead++;}
    elsif ($state eq "switchedOff"){$cnt_Off++;}
    push @event, "status_".$devName.":".$state;
  }
  push @event, "state:"."alive:".$cntAliv
                       ." dead:".$cntDead
                       ." unkn:".$cntUnkn
                       ." off:" .$cnt_Off;

  my $allState = join " ",@event;# search and remove outdated readings
  if ($call eq "ActionDetector"){#delete only in routine call 
    foreach (keys %{$actHash->{READINGS}}){
      delete $actHash->{READINGS}{$_} if ($allState !~ m/$_:/);
    }
  }

  CUL_HM_UpdtReadBulk($actHash,1,@event);

  $actHash->{helper}{actCycle} = AttrVal($actName,"actCycle",600);
  Log3 $actHash,5,"next ActionDetector check in $actHash->{helper}{actCycle} sec";
  RemoveInternalTimer("ActionDetector");
  InternalTimer(gettimeofday()+$actHash->{helper}{actCycle},"CUL_HM_ActCheck", "ActionDetector", 0);
}
sub CUL_HM_ActInfo() {# print detailed status information
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $peerIDs = $actHash->{helper}{peers}?$actHash->{helper}{peers}:"";
  my @info;
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
    
    next if(!$devName || !defined($attr{$devName}{actCycle}));
    next if(AttrVal($devName,"ignore",0));

    my $state;
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
    if ($tSec != 0){
      my ($Y,$Mth,$D,$H,$Min,$S) =  unpack 'A4A2A2A2A2A2',ReadingsVal($devName,".protLastRcv","00000000000000");

      my @t = localtime($tod - $tSec); #time since when a trigger is expected

      my $y =  $Mth*30*24*3600 + $D*24*3600 + $H*3600 + $Min*60 +$S -
               ((  $t[4]+1)*30*24*3600
                 + $t[3]*24*3600 
                 + $t[2]*3600 
                 + $t[1]*60 
                 + $t[0]);
      my $sign = "next  ";
      if ($y < 0){
        $sign = "late -";
        $y *= -1;
        $y = 0 if($Y == 0);
      }
      my $try = (defined $actHash->{helper}{$devId}{try} ? $actHash->{helper}{$devId}{try} : 0);
      my $pingNext = "";
      if    ($try == 0 || $try == 901){$pingNext = "";}
      elsif ($try < 4 ){               $pingNext = 1;}
      else{                            $pingNext = 4 - $try % 4;}

      my @c;      
      $c[2] = int($y/(3600*24));$y -= $c[2] * 3600 * 24;
      $c[1] = int($y/3600)     ;$y -= $c[1] * 3600;
      $c[0] = int($y/60)       ;$y -= $c[0] * 60;
 
      $state .= sprintf("%-8s %6s %3d-%02d:%02d:%02d : %04d.%02d.%02d %02d:%02d:%02d  %6s %3s %4s %s"
                              ,ReadingsVal($devName,"Activity","")
                              ,$sign,$c[2],$c[1],$c[0],$y
                              ,$Y,$Mth,$D,$H,$Min,$S
                              ,AttrVal($devName,"actCycle","")
                              ,(defined $actHash->{helper}{$devId}{try} ? $actHash->{helper}{$devId}{try} : "")
                              ,$pingNext
                              ,$devName
                              );
    }
    else{
      $state = sprintf ("%-8s :%30s : "
                                      ,ReadingsVal($devName,"Activity","")
                                      ,$devName);
    }
    push @info,$state;
  }
  return sprintf ("%-8s %-6s %12s : %-19s  %-6s %3s %4s %s\n"
                                           ,"state"
                                           ,"next/","latest in "
                                           ,"last message"
                                           ,"cycle"
                                           ,"try"
                                           ,"ping"
                                           ,"dev name")
        .sprintf ("%-8s %-6s %12s : %-19s  %-6s %3s %4s %s\n"
                                           ,""
                                           ,"late","d-hh:mm:ss"
                                           ,"received"
                                           ,"set"
                                           ,"cnt"
                                           ,"next"
                                           ,"")
        .join("\n", sort @info);
}
sub CUL_HM_ActDepRead($$$){# Action detector update dependant readings
  #readings may be changed if the device is dead. This is controlled by an 
  # device dependant attribute
  my ($name,$state,$oldState) = @_;
  my $deadAction = AttrVal($name,"readingOnDead","noChange");#state|periodValues|periodString|channels
  if ($deadAction eq "noChange" || ($state !~ m/(dead)/ && $oldState ne "dead" )){#no change to dependant readings
    CUL_HM_UpdtReadSingle($defs{$name},"Activity",$state,1);
  }
  else{
    my %deadH = map{$_ =>1}split(",",$deadAction);
    $defs{$name}{READINGS}{Activity}{VAL} = $oldState if (not defined $defs{$name}{READINGS}{Activity});
    my $deadVal       = $state   eq "dead"    ? "dead"    : "notDead";
    my $deadValsearch = $deadVal eq "notDead" ? "^dead\$" : ".*";
    my @nullReads;
    push @nullReads,( "measured-temp"
                     ,"humidity"
                     ,"ValvePosition"
                     ,"temperature"
                     ,"pressure"
                     ,"current"
                     ,"power"
                     ,"frequency"
                     ,"voltage"
                     ,"luminosity"
                     ,"batteryLevel"
                     ,"brightness"
                     ,"level"
                     ,"phyLevel"
                     ,"mLevel"
                    )         if ($deadH{periodValues} && $state eq "dead" );
    my $grepNull = "^(" .join("|",@nullReads) .")\$";
    my @deadReads;
    push @deadReads,  "state" if ($deadH{state});
    push @deadReads,( "eState"
                     ,"motion"
                     ,"battery"
                    )         if ($deadH{periodString});
    push @deadReads,grep!/^(state|periodValues|periodString|channels)$/,keys %deadH;# add customer readings to be updated
    my $grepDead = "^(" .join("|",@deadReads) .")\$";

    my @entities;
    if($deadH{channels}){@entities = CUL_HM_getAssChnNames($name)}
    else                {@entities = ($name)}
    foreach my $e (@entities){
      my @readNull = map{"$_:0"}        grep/$grepNull/,keys %{$defs{$e}{READINGS}};
      my @readDead = map{"$_:$deadVal"} grep/$grepDead/,map{$defs{$e}{READINGS}{$_}{VAL} =~ m/$deadValsearch/ ? $_:"no"} keys %{$defs{$e}{READINGS}};
      push @readDead,"Activity:$state" if ($e eq $name);
      next if (!(scalar(@readNull) + scalar(@readDead)));
      CUL_HM_UpdtReadBulk($defs{$e},1,@readNull,@readDead);
    }
  }
  $attr{$name}{actStatus} = $state;
}

#+++++++++++++++++ helper +++++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_UpdtReadBulk(@) { #update a bunch of readings and trigger the events
  my ($hash,$doTrg,@readings) = @_;
  return if (!@readings  ||!defined $hash|| !defined $hash->{NAME} );
  if($evtDly && $doTrg){#delay trigger if in parser and trigger ist requested
    push @evtEt,[$hash,1,"$_"] foreach(@readings);
  }
  else{
    readingsBeginUpdate($hash);
    foreach my $rd (CUL_HM_noDup(@readings)){
      next if (!$rd);
      my ($rdName, $rdVal) = split(":",$rd, 2); 
      readingsBulkUpdate($hash,$rdName,
                               ((defined($rdVal) && $rdVal ne "")?$rdVal:"-"));
    }
    readingsEndUpdate($hash,$doTrg);
  }
  return $hash->{NAME};
}
sub CUL_HM_UpdtReadSingle(@) { #update single reading and trigger the event
  my ($hash,$rName,$val,$doTrg) = @_;
  return if (!defined $hash->{NAME});
  if($evtDly && $doTrg){#delay trigger if in parser and trigger ist requested
    push @evtEt,[$hash,1,"$rName:$val"];
  }
  else{
    readingsSingleUpdate($hash,$rName,$val,$doTrg);
  }
  return $hash->{NAME};
}
sub CUL_HM_setAttrIfCh($$$$) {
  my ($name,$att,$val,$trig) = @_;
  if(AttrVal($name,$att,"") ne $val){
    DoTrigger($name,$trig.":".$val) if($trig);
    $attr{$name}{$att} = $val;
  }
}
sub CUL_HM_noDup(@) {#return list with no duplicates
  my %all;
  return @_ if (!scalar(@_));
  $all{$_}=0 foreach (grep {defined $_ && $_ !~ m/^$/} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}
sub CUL_HM_noDupInString($) {#return string with no duplicates, comma separated
  my ($str) = @_;
  return join ",",CUL_HM_noDup(split ",",$str);
}
sub CUL_HM_storeRssi(@){
  my ($name,$peerName,$val,$mNo) = @_;
  return if (!$val || !$name|| !defined  $defs{$name});
  my $hash = $defs{$name};
  if (AttrVal($peerName,"subType","") eq "virtual"){
    my $h = InternalVal($name,"IODev",undef);#CUL_HM_name2IoName($peerName);
    return if (!$h);
    $peerName = $h->{NAME};
  }
  else{
    return if (length($peerName) < 3);
  }
  
  if ($peerName =~ m/^at_/){
    my $hhmrssi = $hash->{helper}{mRssi};
    if ($hhmrssi->{mNo} ne $mNo){# new message
      foreach my $n (keys %{$hhmrssi->{io}}) {
        pop(@{$hhmrssi->{io}{$n}}); # take one from all IOs rssi
      }
      $hhmrssi->{mNo} = $mNo;
    }
    
    my ($mVal,$mPn) = ($val,substr($peerName,3));
    if ($mPn =~ m/^rpt_(.*)/){# map repeater to io device, use max rssi
      $mPn = $1;
      $mVal = @{$hhmrssi->{io}{$mPn}}[0]
            if(   @{$hhmrssi->{io}{$mPn}}[0] 
               && @{$hhmrssi->{io}{$mPn}}[0] > $mVal);
    }
    if(CUL_HM_name2IoName($name) eq $mPn){
      if    ($mVal > -50 ) {$mVal += 8 ;}
      elsif ($mVal > -60 ) {$mVal += 6 ;}
      elsif ($mVal > -70 ) {$mVal += 4 ;}
      else                 {$mVal += 2 ;}      
    }
    @{$hhmrssi->{io}{$mPn}} = ($mVal,$mVal); # save last rssi twice
                                             # -> allow tolerance for one missed reception even with good rssi
                                             # -> reduce useless IO switching
  }
  
  $hash->{helper}{rssi}{$peerName}{lst} = $val;
  my $rssiP = $hash->{helper}{rssi}{$peerName};
  $rssiP->{min} = $val if (!$rssiP->{min} || $rssiP->{min} > $val);
  $rssiP->{max} = $val if (!$rssiP->{max} || $rssiP->{max} < $val);
  $rssiP->{cnt} ++;
  $rssiP->{cnt} = 10000 if(!$rssiP->{cnt}); # avoid division by zero on overflow!
  if ($rssiP->{cnt} == 1){
    $rssiP->{avg} = $val;
  }
  else{
    $rssiP->{avg} += ($val - $rssiP->{avg}) /$rssiP->{cnt};
  }
  my $rssi;
#  foreach (keys %{$rssiP}){
  foreach ("cnt","min","max","avg","lst"){
    my $val = $rssiP->{$_}?$rssiP->{$_}:0;
    $rssi .= $_.":".(int($val*100)/100)." ";
  }
  $hash->{"rssi_".$peerName} = $rssi;
  CUL_HM_UpdtReadSingle($hash,"rssi_".$peerName,$val,1) 
        if (AttrVal($name,"rssiLog",undef));
 return ;
}

sub CUL_HM_UpdtCentral($){
  my $name = shift;
  my $id = CUL_HM_name2Id($name);
  return if(!$init_done || length($id) != 6);
  
  delete $defs{$_}{owner_CCU} foreach (grep{InternalVal($_,"owner_CCU","-") eq $name}keys %defs); 

#  $defs{$name}{assignedIOs} = join(",",grep{AttrVal($_,"hmId","-") eq $id}keys %defs);
  $defs{$name}{assignedIOs} = join(",",devspec2array("hmId=$id"));
  
  foreach my $ioN(split",",AttrVal($name,"IOList","")){# set parameter in IO
    #next if (!$defs{$ioN});  done at attr IOList
    #CommandAttr(undef, "$ioN hmId $id") if (AttrVal($ioN,"hmId","") ne $id); done at attr IOList
    $defs{$ioN}{owner_CCU} = $name;
    CommandAttr(undef, "$ioN rfmode HomeMatic") if ( $defs{$ioN}{TYPE} =~ m/^(CUL|TSCUL|TSSTACKED|STACKABLE_CC)$/
                                                  && AttrVal($ioN,"rfmode","") ne "HomeMatic");
  }

  my $logOpt = "logIDs:"
              .join(',',"multiple,none,sys,all,broadcast"
                       ,sort map{"IO:$_"} split(",",AttrVal($name,"IOList",""))
                       ,sort devspec2array("TYPE=CUL_HM:FILTER=IOgrp=$name.*") # devices assigned to the vccu
                   )." ";
  if ( defined $defs{$name}{'.AttrList'} ) { #Beta-User: fixes "uninitialized ... in substitution" warning at startup
      $defs{$name}{'.AttrList'} =~ s/logIDs:.*? /$logOpt/;
  } else {
      $defs{$name}{'.AttrList'} = $logOpt;
  }

  # --- search for peers to CCU and potentially device this channel
  # create missing CCU channels 
  foreach my $ccuBId (CUL_HM_noDup(grep !/00$/,
                                   grep /^$id[0-9]{2}$/ ,map{split ",",AttrVal($_,"peerIDs","")}
                                   grep{AttrVal($_,"peerIDs","") =~ m/$id/} 
                                   keys %defs)){
    # now for each ccu Channel, that ist peered with someone. 
    next if ($ccuBId !~ m/^[0-9A-F]{8}$/);
    my $btn = hex(substr($ccuBId,6,2)) + 0;
    CommandDefine(undef,$name."_Btn$btn CUL_HM $ccuBId") if (!$modules{CUL_HM}{defptr}{$ccuBId});
    foreach my $pn (grep !/^$/,
                    grep{AttrVal($_,"peerIDs","") =~ m/$ccuBId/}
                    keys %defs){
      CUL_HM_ID2PeerList ($modules{CUL_HM}{defptr}{$ccuBId}{NAME},unpack('A8',CUL_HM_name2Id($pn)."01"),1); 
    }
  }

  CUL_HM_UpdtCentralState($name);
  return;
}
sub CUL_HM_UpdtCentralState($){
  my $name = shift;
  my $state = "";
  my @IOl = split",",AttrVal($name,"IOList","");
  foreach my $e (split",",$defs{$name}{assignedIOs}){
    $state .= "$e:UAS," if (!grep /$e/,@IOl);
  }
  my $xo = 0; # there is still an io(xmit) open
  my @ioState;
  foreach my $ioN (@IOl){
    next if (!defined($defs{$ioN})); # remove undefined IO devices

    (my $x = ReadingsVal($ioN,"cond"                   # covering all HMLAN/USB
            ,ReadingsVal($ioN,"state","unknown")))     # handling CUL
            =~ s/Initialized/ok/;
    push @ioState,"$ioN:$x";
    $xo++ if (InternalVal($ioN,"XmitOpen",($x eq "ok" ? 1 : 0)));# if xmitOpen is not supported use state (e.g.CUL)

    if (AttrVal($ioN,"hmId","") ne $defs{$name}{DEF}){ # update HMid of io devices
      Log 2,"CUL_HM correct hmId for assigned IO $ioN";
      CommandAttr(undef, "$ioN hmId $defs{$name}{DEF}");
    }
  };
  $state .= join(",",@ioState);
  $state = "IOs_ok" if (!$state);
  CUL_HM_UpdtReadBulk($defs{$name},1,"state:$state"
                                    ,"IOopen:$xo");
  return "$xo : $state";
}
sub CUL_HM_operIObyIOHash($){ # noansi: in iohash, return iohash if IO is operational, else undef
  return if (!defined($_[0]));
  return CUL_HM_operIObyIOName($_[0]->{NAME});
}
sub CUL_HM_operIObyIOName($){ # noansi: in ioname, return iohash if IO is operational, else undef
  return if (!$_[0]);
  my $iohash = $defs{$_[0]};
  return if (   !defined($iohash)
             || defined InternalVal($_[0],'XmitOpen',undef) && InternalVal($_[0],'XmitOpen',0) == 0 # HMLAN/HMUSB/TSCUL
             || ReadingsVal($_[0],'state','disconnected') eq 'disconnected'                         # CUL
             || IsDummy($_[0])
             || IsDisabled($_[0])                                                                                                
            );
  return $iohash;
}
sub CUL_HM_assignIO($){ #check and assign IO, returns 1 if IO changed
  # assign IO device
  # only called after init_done
  # prio:
  # 0) no change if transmission is active
  # 1) with vccu check preferred list   as long as operational
  # 2) with vccu check remaining IOs    as long as operational sort by rssi
  # 3) with vccu first preferred        if assinged - unconditional
  # 4) with vccu first any              if defined - unconditional

  # 5) no vccu -> attr IODev            as long as defined (obey user decission)
  # 6) current IO                       as long as defined
  # 7) any IO with client "CUL_HM"      as long as operational
  # 8) any IO with client "CUL_HM"      unconditional
  # no option - 
  
  my $hash = shift;
  return 0 if IsIgnored($hash->{NAME}) || IsDummy($hash->{NAME});
  my $oldIODevH = $hash->{IODev};
  my $hh = $hash->{helper};

  return 0 if (   (   defined($hh->{prt}{sProc})
                    && $hh->{prt}{sProc} == 1           #don't change while send in process
                    && $oldIODevH                 )     #with an operational IO
                || defined($hh->{aesCommRq})            #don't change while CUL aesCommReq in progress
                || $modules{CUL_HM}{helper}{updateStep} #don't change while a fwupdate is in progress, only IO for update is in 100kbit/s speed
                );
  my $newIODevH;
  
  if ($hh->{io}{vccu}){# second option - any IO from the
    my $iom;
    ($iom) = grep {CUL_HM_operIObyIOName($_)} @{$hh->{io}{prefIO}}  if(!$iom && @{$hh->{io}{prefIO}});
    ($iom) = grep {$_ eq 'none'}              @{$hh->{io}{prefIO}}  if(!$iom && @{$hh->{io}{prefIO}});
    return 0 if $iom && $iom eq 'none';
    if(!$iom){
      my @ioccu = grep{CUL_HM_operIObyIOName($_)} @{$defs{$hh->{io}{vccu}}{helper}{io}{ioList}};
      ($iom) =    ((sort {@{$hh->{mRssi}{io}{$b}}[0] <=>     # This is the best choice
                            @{$hh->{mRssi}{io}{$a}}[0] } 
                          (grep { defined @{$hh->{mRssi}{io}{$_}}[0]} @ioccu))
                         ,(grep {!defined @{$hh->{mRssi}{io}{$_}}[0]} @ioccu))      if(@ioccu);
    } 
    ($iom) = grep{defined $defs{$_}} @{$hh->{io}{prefIO}}                           if(!$iom && @{$hh->{io}{prefIO}});
    ($iom) = grep{defined $defs{$_}} @{$defs{$hh->{io}{vccu}}{helper}{io}{ioList}}  if(!$iom && @{$defs{$hh->{io}{vccu}}{helper}{io}{ioList}});
    return 0 if ($iom && $iom eq 'none');
    $newIODevH  = $defs{$iom} if($iom);
  }
  
  
  if (!defined $newIODevH) {# not assigned thru CCU - try normal
    my $dIo = AttrVal($hash->{NAME},"IODev",""); 
    if (CUL_HM_operIObyIOName($dIo)) {
      ; # assign according to reading/attribut
    }
    elsif(CUL_HM_operIObyIOHash($oldIODevH)) {
      $dIo = $oldIODevH->{NAME};
    }
    else {
      my @IOs = devspec2array('Clients=.*:CUL_HM:.*');
      ($dIo) = (grep{CUL_HM_operIObyIOName($_)} @IOs,@IOs);# tricky: use first active IO else use any IO for CUL_HM
    }
    $newIODevH  = $defs{$dIo} if($dIo);
  }

  my $result = 0; # default: IO unchanged
  if(  (defined $newIODevH && (!defined($oldIODevH) || $newIODevH ne $oldIODevH))){
    my $ID = CUL_HM_hash2Id($hash);
    IOWrite($hash, "", "remove:".$ID) if(   defined($oldIODevH) && defined $oldIODevH->{NAME} 
                                         && $oldIODevH->{TYPE}  && $oldIODevH->{TYPE} =~ m/^(HMLAN|HMUARTLGW)$/); #IODev still old
    AssignIoPort($hash,$newIODevH->{NAME}); #  send preferred
    if (defined $newIODevH->{NAME} && $newIODevH->{NAME} ne $hash->{IODev}->{NAME}) {
      Log3($hash, 2, "fhem.pl does not assign desired IODev $newIODevH->{NAME} to $hash->{NAME}!") if (!defined $hash->{IOAssignmentErrCnt});
      $hash->{IOAssignmentErrCnt}++;
    }
    $newIODevH = $hash->{IODev};
    if (   ($newIODevH->{TYPE} && $newIODevH->{TYPE} =~ m/^(HMLAN|HMUARTLGW)$/)
        || (   $newIODevH->{helper}{VTS_AES})){
      IOWrite($hash, "", "init:".$ID); # assign to new IO
    }
    else {
      if (   defined($hash->{helper}{io}{flgs})
          && $hash->{helper}{io}{flgs} & 0x02) { $hash->{helper}{io}{sendWu} = 1;     } #noansi: for CUL
      else                                     { delete($hash->{helper}{io}{sendWu}); }
    }
    $result = 1;
  }
  else{
    AssignIoPort($hash); # leave it to IO
  }

#  if (   defined($newIODevH)
#      && (   !defined($oldIODevH)
#          || ($oldIODevH != $newIODevH) ) ) {
#    my $ID = CUL_HM_hash2Id($hash);
#    if ($haveIOList) {
#      my $lastIODevH = $hash->{IODev};
#      my $lIODevH;
#      foreach my $ioLd (@ioccu) { # remove on all unassigend IOs to ensure a consistant state of assignments in IO devices!
#                                  # IO has to keep track about and really remove just if required
#        $lIODevH = $defs{$ioLd};
#        next if (   !defined($lIODevH)
#                 || ($lIODevH == $newIODevH) );
#        if (ReadingsVal($ioLd,"state","") ne "disconnected") {
#          if (   $lIODevH->{helper}{VTS_AES} #if this unselected IO is TSCUL 0.14+ we have to remove the device from IO, as it starts with "historical" assignment data
#              || (   defined($lastIODevH)
#                  && ($lIODevH == $lastIODevH) # HMLAN/HMUARTLGW always start with clean peerlist? At least it tries to.
#                  && $lIODevH->{TYPE}
#                  && $lIODevH->{TYPE} =~ m/^(HMLAN|HMUARTLGW)$/s
#                  ) #if this unselected IO is HMLAN we have to remove the device from IO
#              ) {
#            $hash->{IODev} = $lIODevH; # temporary assignment for IOWrite to work on each IO!
#            IOWrite($hash, "", "remove:".$ID);
#          }
#        }
#      }
#    }
#
#    $hash->{IODev} = $newIODevH; # finally assign IO
##    $attr{$hash->{NAME}}{IODev} = $newIODevH->{NAME}
##      if (AttrVal($hash->{NAME}, 'model', '') !~ m/^(?:VIRTUAL|CCU-FHEM)$/s);
##      $attr{$hash->{NAME}}{IODev} = $newIODevH->{NAME};
##    }
#    
#    if (   ($newIODevH->{TYPE} && $newIODevH->{TYPE} =~ m/^(HMLAN|HMUARTLGW)$/)
#        || (   $newIODevH->{helper}{VTS_AES})){
#      IOWrite($hash, "", "init:".$ID); # assign to new IO
#    }
#    else {
#      if (   defined($hash->{helper}{io}{flgs})
#          && $hash->{helper}{io}{flgs} & 0x02) { $hash->{helper}{io}{sendWu} = 1;     } #noansi: for CUL
#      else                                     { delete($hash->{helper}{io}{sendWu}); }
#    }
#    $result = 1; # IO changed
#  }
  return $result;
}

sub CUL_HM_stateUpdatDly($$){#delayed queue of status-request
  my ($name,$time) = @_;
  CUL_HM_unQEntity($name,"qReqStat");#remove requests, wait for me.
  RemoveInternalTimer("sUpdt:$name");
  InternalTimer(gettimeofday()+$time,"CUL_HM_qStateUpdatIfEnab","sUpdt:$name",0);
}
sub CUL_HM_qStateUpdatIfEnab($@){#in:name or id, queue stat-request
  my ($name,$force) = @_;
  $name = substr($name,6) if ($name =~ m/^sUpdt:/);
  $name = CUL_HM_id2Name($name) if ($name =~ m/^[A-F0-9]{6,8}$/i);
  $name =~ s/_chn-\d\d$//;
  my $ret = 0;
  foreach my $chNm(CUL_HM_getAssChnNames($name)){
    next if (  !$defs{$chNm}                  #device unknown, ignore
               || 0 == CUL_HM_SearchCmd($chNm,"statusRequest"));
    if ($force || ((CUL_HM_getAttrInt($chNm,"autoReadReg") & 0x0f) > 3)){
      CUL_HM_qEntity($chNm,"qReqStat");
      $ret = 1;
    }
  }
  return $ret;
}
sub CUL_HM_qAutoRead($$){
  my ($name,$lvl) = @_;
  CUL_HM_complConfigTest($name);
  return if (!$defs{$name}
             ||$lvl >= (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
  CUL_HM_qEntity($name,"qReqConf");
}
sub CUL_HM_unQEntity($$){# remove entity from q
  my ($name,$q) = @_;
  my $devN = CUL_HM_getDeviceName($name);
  
  return if (AttrVal($devN,'subType','') eq 'virtual') || IsIgnored($devN) || IsDummy($devN);

  my $dq = $defs{$devN}{helper}{q};
  RemoveInternalTimer("sUpdt:$name") if ($q eq "qReqStat");#remove delayed
  return if ($dq->{$q} eq "");

  if ($devN eq $name){#all channels included
    $dq->{$q}="";
  }
  else{
    my @chns = split(",",$dq->{$q});
    my $chn = substr(CUL_HM_name2Id($name),6,2);
    @chns = grep !/$chn/,@chns;
    @chns = grep !/00/,@chns;#remove device as well - just in case
    $dq->{$q} = join",",@chns;
  }
  if ($dq->{$q} eq "") {
    my $rxt = CUL_HM_getRxType($defs{$name});
    my $mQ = $modules{CUL_HM}{helper}{($rxt & 0x1C) ? $q.'Wu' : $q};
    return if(!defined($mQ) || scalar(@{$mQ}) == 0);
    @{$mQ} = grep !/^$devN$/,@{$mQ};
    if (   $rxt & 0x18 #wakeup, lazyConfig
        && !$defs{$name}->{helper}{prt}{sProc} #not busy with queue
        ) {
      CUL_HM_hmInitMsgUpdt($defs{$devN}); #remove wakeup prep
    }
  }
}
sub CUL_HM_qEntity($$){  # add to queue
  my ($name,$q) = @_;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,'subType','') eq 'virtual' || IsIgnored($devN) || IsDummy($devN));

  $name =  $devN if ($defs{$devN}{helper}{q}{$q} eq "00"); #already requesting all
  if ($devN eq $name){#config for all device
    $defs{$devN}{helper}{q}{$q}="00";
  }
  else{
    $defs{$devN}{helper}{q}{$q} = CUL_HM_noDupInString(
                                      $defs{$devN}{helper}{q}{$q}
                                      .",".substr(CUL_HM_name2Id($name),6,2));
  }
  my $rxt = CUL_HM_getRxType($defs{$devN});
  my $wu = ($rxt & 0x1C) ? 'Wu' : ''; #normal or wakeup q?
  $q .= $wu;
  my $qa = $modules{CUL_HM}{helper}{$q};
  @{$qa} = CUL_HM_noDup(@{$qa},$devN); #we only q device - channels are stored in the device

  CUL_HM_cfgStateDelay($devN)  if($q eq "qReqConf");

  if (!$wu) {
    my $wT = (@{$modules{CUL_HM}{helper}{qReqStat}})?
                                "1" :
                                $modules{CUL_HM}{hmAutoReadScan};
    RemoveInternalTimer("CUL_HM_procQs");
    InternalTimer(gettimeofday()+ $wT,"CUL_HM_procQs","CUL_HM_procQs", 0);
  }
  else {
    if(    $rxt & 0x18 #wakeup prep for wakeup, lazyConfig
       && !(CUL_HM_getAttrInt($devN,'burstAccess') && $defs{$devN}->{cmdStack})
       && !(defined($defs{$devN}->{helper}{io}{flgs}) && $defs{$devN}->{helper}{io}{flgs} & 0x02)   # wuPrep is not active
       ){
      CUL_HM_hmInitMsgUpdt($defs{$devN}, 1);
    }
  }
}

sub CUL_HM_readStateTo($){#staterequest not working
  my ($eN) = @_;
  $eN = substr($eN,6) if ($eN =~ m/^sUpdt:/);
  CUL_HM_UpdtReadSingle($defs{$eN},"state","unreachable",1);
  CUL_HM_stateUpdatDly($eN,1800 );
}
sub CUL_HM_procQs($){#process non-wakeup queues
  # --- verify send is possible

  my $mq = $modules{CUL_HM}{helper};
  my $Qexec = "none";
  foreach my $q ("qReqStat","qReqConf"){
    if   (@{$mq->{$q}}){
      my ($devN,$devH);
      foreach my $devNtmp (@{$mq->{$q}}){ # search for next possible device
        $devH = $defs{$devNtmp};
        CUL_HM_assignIO($devH); 
        if(   defined($devH->{IODev}) # noansi: IODev may be undefined
           && $devH->{IODev}->{NAME}
           && (  (   ReadingsVal($devH->{IODev}->{NAME},"cond","ok") =~ m/^(ok|Overload-released|Warning-HighLoad|init)$/
                  && $q eq "qReqStat")
               ||(   CUL_HM_autoReadReady($devH->{IODev}->{NAME})
                  && !$devH->{cmdStack}
                  && $q eq "qReqConf")
              )
            ){# got next device
          $devN = $devNtmp;
          last;
        }
      }
      next  if(!defined $devN);# no device found for this queue
  
      my $dq = $devH->{helper}{q};
      my @chns = split(",",$dq->{$q});
      my $nOpen = scalar @chns;
      if (@chns > 1){$dq->{$q} = join ",",@chns[1..$nOpen-1];}
      else{          $dq->{$q} = "";
                     @{$mq->{$q}} = grep !/^$devN$/,@{$mq->{$q}};
      }
      my $dId = CUL_HM_name2Id($devN);
      my $eN=($chns[0] && $chns[0]ne "00") ? CUL_HM_id2Name($dId.$chns[0]) : $devN;
      next if(!defined $defs{$eN});
      if ($q eq "qReqConf"){
        $mq->{autoRdActive} = $devN;
        CUL_HM_Set($defs{$eN},$eN,"getConfig");
      }
      else{
         my $ign = CUL_HM_getAttrInt($eN,'ignore') + IsDummy($eN);
         CUL_HM_Set($defs{$eN},$eN,'statusRequest') if (!$ign);
         CUL_HM_unQEntity($eN,'qReqStat') if (!$dq->{$q});
         InternalTimer(gettimeofday()+20,'CUL_HM_readStateTo','sUpdt:'.$eN,0) if (!$ign);
      }
      $Qexec = $q;
      last; # execute only one!
    }
  }
  my $delayAdd = $Qexec eq 'none' ? 10 : 0; # if no device was identified wait at least
  delete $mq->{autoRdActive}  if ($mq->{autoRdActive} &&
                                  $defs{$mq->{autoRdActive}}{helper}{prt}{sProc} != 1);
  my $next;# how long to wait for next timer
  if    (@{$mq->{qReqStat}}){$next = 1}
  elsif (@{$mq->{qReqConf}}){$next = $modules{CUL_HM}{hmAutoReadScan}}
  InternalTimer(gettimeofday()+$next+$delayAdd,"CUL_HM_procQs","CUL_HM_procQs",0) if ($next);
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
        if ($nOpen > 1){$dq->{$q} = join ",",@chns[1..$nOpen-1];}
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
  if (   !$ioName
      || ReadingsVal($ioName,"cond","ok") !~ m/^(ok|Overload-released|init)$/#default ok for CUL
      || ( defined $defs{$ioName}->{msgLoadCurrent}
          && ( $defs{$ioName}->{msgLoadCurrent}>
               (defined $defs{$ioName}{helper}{loadLvl}?$defs{$ioName}{helper}{loadLvl}{bl}:40)))){
    return 0;
  }
  return 1;
}

sub CUL_HM_readValIfTO($){# 
  my ($name,$rd,$val) = split(":",shift);#  uncertain:$name:$reading:$value
  readingsSingleUpdate($defs{$name},$rd,$val,1);
}
sub CUL_HM_motionCheck($){# 
  my ($name) = split(":",shift);#  uncertain:$name:$reading:$value 

  if (defined $defs{$name}{helper}{moStart}){
    CUL_HM_UpdtReadBulk($defs{$name},1,"state:noMotion"
                                      ,"motion:off"
                                      ,"motionDuration:".(int(gettimeofday())-int($defs{$name}{helper}{moStart})));
    delete $defs{$name}{helper}{moStart};
  }
  else{
    CUL_HM_UpdtReadBulk($defs{$name},1,"state:noMotion"
                                      ,"motion:off");
  }
}

sub CUL_HM_reWriteDisplay($){
  my ($name) = split(":",shift);#  uncertain:$name:$reading:$value 
  CUL_HM_Set($defs{$name},$name,"displayEP",":::");
}

sub CUL_HM_getAttr($$$){#return attrValue - consider device if empty
  my ($name,$attrName,$default) = @_;
  my $val;
  if($defs{$name}){
    $val = (defined $attr{$name}{$attrName})
                 ? $attr{$name}{$attrName}
                 : undef;
    if (!defined $val){
      my $devN = $defs{$name}{device}?$defs{$name}{device}:$name;
      $val = (defined $attr{$devN}{$attrName})
                 ? $attr{$devN}{$attrName}
                 : ($modules{CUL_HM}{AttrListDef} && $modules{CUL_HM}{AttrListDef}{$attrName})?$modules{CUL_HM}{AttrListDef}{$attrName}
                 :$default;
    }
  }
  return $val;
}
sub CUL_HM_getAttrInt($@){#return attrValue as integer
  my ($name,$attrName,$default) = @_;
  $default = 0 if (!defined $default);
  
  
  if($name && $defs{$name}){
    my $devN = $defs{$name}{device}?$defs{$name}{device}:$name;
    my $val = "0".AttrVal($name,$attrName
                 ,AttrVal($devN,$attrName
                 ,($modules{CUL_HM}{AttrListDef} && $modules{CUL_HM}{AttrListDef}{$attrName})?$modules{CUL_HM}{AttrListDef}{$attrName}
                 :$default));
    $val =~ s/(\d*).*/$1/;
    return int($val);
  }
  return $default;
}

#+++++++++++++++++ external use +++++++++++++++++++++++++++++++++++++++++++++++

sub CUL_HM_reglUsed($) {# provide data for HMinfo
  my $name = shift;
  return () if (!defined $name || !defined $defs{$name} || !defined $defs{$name}{DEF});
  my $hash = $defs{$name};
  my ($devId,$chn) =  unpack 'A6A2',$hash->{DEF}."01";
  return () if (AttrVal(CUL_HM_id2Name($devId),"subType","") eq "virtual");

  my @pNames;
  push @pNames,CUL_HM_peerChName($_,$devId)
             foreach (grep !/(x)/,CUL_HM_getPeers($name,"IDs"));#dont check 'x' peers

  my @lsNo;
  my $mId = CUL_HM_getMId($hash);
  return () if (!$mId || !$culHmModel->{$mId});
  if ($hash->{helper}{role}{dev}){
    push @lsNo,"0.";
  }
  if ($hash->{helper}{role}{chn}){
    foreach my $ls (split ",",$culHmModel->{$mId}{lst}){
      my ($l,$c) = split":",$ls;
      if ($l ne "p"){# ignore peer-only entries
        if ($c){
          my $chNo = hex($chn);
          if   ($c =~ m/($chNo)p/){push @lsNo,"$l.$_" foreach (@pNames);}
          elsif($c =~ m/$chNo/   ){push @lsNo,"$l.";}
        }
        else{
          if ($l == 3 || $l == 4){push @lsNo,"$l.$_" foreach (@pNames);
          }else{                  push @lsNo,"$l." ;}
        }
      }
    }
  }
  my $pre = $hash->{helper}{expert}{raw}?"":".";

  $_ = $pre."RegL_0".$_ foreach (@lsNo);
  return @lsNo;
}

sub CUL_HM_complConfigTest($){  # Q - check register consistency some time later
  my $name = shift;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  
  $modules{CUL_HM}{helper}{confCheckH}{CUL_HM_name2Id($name)} = 1;
  if (scalar keys%{$modules{CUL_HM}{helper}{confCheckH}} == 1){# this was the first
    RemoveInternalTimer("CUL_HM_complConfigTO");
    InternalTimer(gettimeofday()+ 1800,"CUL_HM_complConfigTO","CUL_HM_complConfigTO", 0);
  }
}
sub CUL_HM_complConfigTestRm($){# Q - check register consistency some time later - remove
  my $name = shift;
  delete $modules{CUL_HM}{helper}{confCheckH}{CUL_HM_name2Id($name)};
}
sub CUL_HM_complConfigTO($)  {# now perform consistency check of register
  foreach (keys %{$modules{CUL_HM}{helper}{confCheckH}}){
    CUL_HM_complConfig(CUL_HM_id2Name($_));
    delete $modules{CUL_HM}{helper}{confCheckH}{$_};
  }
}
sub CUL_HM_complConfig($;$)  {# read config if enabled and not complete
  my ($name,$dly) = @_;
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  return if ((CUL_HM_getAttrInt($name,"autoReadReg") & 0x07) < 5);
  if ($defs{$devN}{helper}{prt}{sProc} != 0){# we wait till device is idle. 
    CUL_HM_complConfigTest($name);           # requeue and wait patient
  }
  elsif (CUL_HM_getPeers($name,"Config") == 2){# 2: peer list incomplete
    CUL_HM_qAutoRead($name,0) if(!$dly);
    CUL_HM_complConfigTest($name);
    delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
    Log3 $name,5,"CUL_HM $name queue configRead, peers incomplete";
  }
  else{
    my @regList = CUL_HM_reglUsed($name);
    foreach (@regList){
      if (ReadingsVal($name,$_,"") !~ m/00:00/){
        CUL_HM_qAutoRead($name,0) if(!$dly);
        CUL_HM_complConfigTest($name);
        delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
        Log3 $name,5,"CUL_HM $name queue configRead, register incomplete";
        last;
      }
    }
    $modules{CUL_HM}{helper}{cfgCmpl}{$name} = 1;#mark config as complete
  }
}
sub CUL_HM_configUpdate($)   {# mark entities with changed data for archive
  my $name = shift;
  $modules{CUL_HM}{helper}{confUpdt}{$name} = 1;
}

sub CUL_HM_cleanShadowReg($){
  # remove shadow-regs if those are identical to readings or 
  # the reading does not exist. 
  # return dirty "1" if some shadowregs still remain active
  my $name = shift        // return 0;
  my $hash = $defs{$name} // return 0;
  my $dirty = 0;
  foreach my $rLn (keys %{$hash->{helper}{shadowReg}}){ 
    my $rLnP = ($hash->{helper}{expert}{raw} ? "" : ".").$rLn;
    if (   !$hash->{READINGS}{$rLnP}
        || !$hash->{helper}{shadowReg}{$rLn}
        ||  $hash->{helper}{shadowReg}{$rLn} eq $hash->{READINGS}{$rLnP}{VAL}){   
      delete $hash->{helper}{shadowReg}{$rLn};
    }
    else{
      $dirty = 1;
    }
  }
  return $dirty;
}

#+++++++++++++++++ templates ++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_tempListTmpl(@) { ##################################################
  # $name is comma separated list of names
  # $template is formated <file>:template - file is optional
  my ($name,$action,$template)=@_; 
  my %dl  = (Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6);
  my %dlf = (1=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0},
             2=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0},
             3=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0});
  return "unused" if ($template =~ m/^(none|0) *$/);
  my $ret = "";
  my @el = split",",$name;
  my ($fName,$tmpl) = split":",$template;
  if(!$tmpl){ # just a template - switch
    $tmpl = $fName ? $fName: $name;
    $fName = (eval "defined(&HMinfo_tempListDefFn)")
                              ? HMinfo_tempListDefFn()
                              : "./tempList.cfg";
  }
  my ($err,@RLines) = FileRead($fName);
  return "file: $fName error:$err"  if ($err);
#  return "file: $fName for $name does not exist"  if (!(-e $fName));
#  open(aSave, "$fName") || return("Can't open $fName: $!");
  my $found = 0;
  my @entryFail = ();
  my @exec = ();

  if ($template =~ m/defaultWeekplan$/){
    $found = 1;
    foreach my $eN(@el){
      if ($action eq "verify"){
        my $val = "24:00 18.0";
        foreach ( "R_0_tempListSat"
                 ,"R_1_tempListSun"
                 ,"R_2_tempListMon"
                 ,"R_3_tempListTue"
                 ,"R_4_tempListWed"
                 ,"R_5_tempListThu"
                 ,"R_6_tempListFri"){      
          my $nv = ReadingsVal($eN,$_,"empty");
          $nv = join(" ",split(" ",$nv));
          push @entryFail,$eN.": ".$_." mismatch $val ne $nv ##" if ($val ne $nv);
        }
        $dlf{1}{Sat} = 1;
        $dlf{1}{Sun} = 1;
        $dlf{1}{Mon} = 1;
        $dlf{1}{Tue} = 1;
        $dlf{1}{Wed} = 1;
        $dlf{1}{Thu} = 1;
        $dlf{1}{Fri} = 1;
     }
      elsif($action eq "restore"){
        foreach ( "tempListSat"
                 ,"tempListSun"
                 ,"tempListMon"
                 ,"tempListTue"
                 ,"tempListWed"
                 ,"tempListThu"
                 ,"tempListFri"){      
          my $x = CUL_HM_Set($defs{$eN},$eN,$_,"prep",split(" "," 24:00 18.0"));
          
          push @entryFail,$eN." :".$_." respose:$x" if ($x ne "1");
          push @exec,"$eN $_ exec 24:00 18.0";
        }
      }
    }
  }
  else{
    foreach(@RLines){
#    while(<aSave>){
      chomp;
      my $line = $_;
      $line =~ s/\r//g;
      next if($line =~ m/#/);
      if($line =~ m/^entities:/){
        last if ($found != 0);
        $line =~ s/.*://;
        foreach my $eN (split(",",$line)){
          $eN =~ s/ //g;
          $found = 1 if ($eN eq $tmpl);
        }
      }    
      elsif($found == 1 && $line =~ m/(R_)?(P[123])?(_?._)?tempList[SMFWT].*\>/){
        my ($prg,$tln,$val);
        $prg = $1 if ($line =~ m/P(.)_/);
        $prg = 1  if (!$prg);
        ($tln,$val) = ($1,$2) if ($line =~ m/(.*)>(.*)/);
        $tln =~ s/ //g;
        $tln = "R_".$tln if($tln !~ m/^R_/);
        my $dayTxt = ($tln =~ m/tempList(...)/ ? $1 : "");
        if (!defined $dl{$dayTxt}){
          push @entryFail," undefined daycode:$dayTxt";
          next;
        }
        if ($dlf{$prg}{$dayTxt}){
          push @entryFail," duplicate daycode:$dayTxt";        
          next;
        }
        $dlf{$prg}{$dayTxt} = 1;
        my $day = $dl{$dayTxt};
        $tln =~ s/tempList/${day}_tempList/ if ($tln !~ m/_[0-6]_/);
        if (AttrVal($name,"model","") =~ m/^HM-TC-IT-WM-W/){
          $tln =~ s/^R_/R_P1_/ if ($tln !~ m/^R_P/);# add P1 as default
        }
        else{
          $tln =~ s/^R_P1_/R_/ if ($tln =~ m/^R_P/);# remove P1 default
        }
        $val =~ tr/ +/ /;
        $val =~ s/^ //;
        $val =~ s/ $//;
        @exec = ();
        foreach my $eN(@el){
          if ($action eq "verify"){
            $tln =~ m/R_(P.)_.*/;
            my $prog = defined $1 ? $1."_" : "";
            if (ReadingsVal($name,"R_${prog}tempList_State","") ne "verified"){
              next;
              push @entryFail,$eN.":${prog} templist not verified";
            }
            $val = join(" ",map{(my $foo = $_) =~ s/^(.\.)/0$1/;$foo} split(" ",$val));
            my $nv = ReadingsVal($eN,$tln,"empty");
            $nv = join(" ",map{(my $foo = $_) =~ s/^(.\.)/0$1/;$foo} split(" ",$nv));
            push @entryFail,$eN.": ".$tln." mismatch $val ne $nv ##" if ($val ne $nv);
          }
          elsif($action eq "restore"){
            $val = lc($1)." ".$val if ($tln =~ m/(P.)_._tempList/);
            $tln =~ s/R_(P._)?._//;
            my $x = CUL_HM_Set($defs{$eN},$eN,$tln,"prep",split(" ",$val));
            push @entryFail,$eN." :".$tln." respose:$x" if ($x ne "1");
            push @exec,"$eN $tln exec $val";
          }
        }
      }
      $ret = "failed Entries:\n     "   .join("\n     ",CUL_HM_noDup(@entryFail)) if (scalar@entryFail);
    }
  }
  
  my $progType = "multi";
  if (!$found){
    $ret .= "$tmpl not found in file $fName";
  }
  else{
    if(CUL_HM_getAttr($name,"model","") !~ m/^HM-TC-IT-WM-W-EU/s){
      delete $dlf{2};
      delete $dlf{3};
      $progType = "single";
    }
    foreach my $p (keys %dlf){
      my @unprg = grep !/^$/,map {$dlf{$p}{$_}?"":$_} keys %{$dlf{$p}};
      my $cnt = scalar @unprg;
      if ($cnt > 0 && $cnt < 7) {$ret .= "\n $name: incomplete template for prog $p days:".join(",",@unprg);}
      elsif ($cnt == 7)         {$ret .= "\n $name: unprogrammed prog $p ";}
      else{
        my $prog = ($progType eq "multi" ?"_P$p" :"");
        if(ReadingsVal($name,"R".$prog."_tempList_State","") ne "verified"){
          $ret .= "\n     $name: tempList $p not verified";
        }
#        my $res =  join(",",map{$_=~m/^R_(P.)_.*/;(defined $1?$1:"ll")}
#                             grep {$defs{$name}{READINGS}{$_}{VAL} ne "verified"}
#                             grep /tempList_State/
#                            ,keys %{$defs{$name}{READINGS}});
      }
    }
  }
  foreach (@exec){
    my @param = split(" ",$_);
    CUL_HM_Set($defs{$param[0]},@param);
  }
#  close(aSave);
  return $ret;
}
sub CUL_HM_getIcon($) { ####################################################### {my $s = gettimeofday();;return join("\n",map{$_.":\t".CUL_HM_getIcon($_)}devspec2array("TYPE=CUL_HM"))."\ntime: ".(gettimeofday() - $s)}
  my $name = shift;
  # only for CUL_HM
  return "" if(!defined $name || !defined $defs{$name} || $defs{$name}{TYPE} ne "CUL_HM");
  
  # handle virtual - no idea so far
  return ".*:HomeMatic.svg" if(defined $defs{$name}->{helper}{role}{vrt}); 
  
  # prio 1: Device is dead. Will apply to all channels
  return ".*:dead.svg"      if("dead" eq ReadingsVal(CUL_HM_getDeviceName($name),"Activity","alive"));
  
  my ($state,$chn) = 
           (ReadingsVal     ($name,"state"   ,""  )
           ,InternalVal     ($name,"chanNo"  ,"00")
           );

  if($chn eq "00"){#execute device-only entites. Prio: 1)communication 3)battery
    my ($bat) = 
               (ReadingsVal     ($name,"battery"   ,"ok"  )
               );
    return ".*:"
            .( $state   =~ m/^CMDs_.*err/   ? "rc_RED"
              :$state   =~ m/^CMDs_(process|pending)/ ? "rc_YELLOW"
              :$bat     ne "ok"             ? "measure_battery_0"
              :$state   eq "CMDs_done"      ? "rc_GREEN"
              :                               "rc_RED"
             ).".svg";
  }

  my ($level,$subType) = 
             (ReadingsVal     ($name,"level"   ,""  )
             ,CUL_HM_getAttr  ($name,"subType" ,""  )
             );
  $level =~ s/^set_//;
  if(CUL_HM_SearchCmd($name,"on")){# devices with 'on' cmd are major light switches - but not all
    if(CUL_HM_SearchCmd($name,"color")){
      return ".*:"
              .( $level     < 5    ? "rc_RED"
                :$level     < 15   ? "rc_YELLOW"
                :$level     < 45   ? "rc_GREEN"
                :$level     < 82   ? "rc_BLUE"
                :                    "rc_RED"
               ).".svg";
    }
    if($subType eq "blindActuator"){
      my ($dir) = split(":",ReadingsVal($name,"motor"     ,""));
      return ".*:"
              .( $state    =~ m /^set_(.*)/ ? ($1 eq "off" ? "set_off" :"set_on")
                :$level    == 0             ? "shutter_open"
                :$level    >= 99            ? "shutter_closed"
                :$dir      =~ m/^(up|down)$/? "black_$1"
                :"shutter_".int($level/14.5+0.99)
               ).".png";
    }
    my ($timedOn) = 
             (ReadingsVal     ($name,"timedOn" ,""  )
             );
    if(1){#any with cmd on, not blind and not color
      my ($dir) = split(":",ReadingsVal($name,"dim"     ,""));
      return ".*:"
              .( $state    =~ m /^set_(.*)/ ? ($1 eq "off" ? "set_off" :"set_on")
                :$level    == 0             ? "off"
                :$level    == 100           ? ($timedOn eq "running" ? "on-till" : "on")
                :$dir      =~ m/^(up|down)$/? "dim$1"
                :$level    < 6              ? "dim06%"
                :"dim".int(int(($level+6)/6.25)*6.25)."%"
               ).".png";
    }
  }
  if($subType eq "smokeDetector"){
    my ($bat) = 
               (ReadingsVal     ($name,"battery"   ,"ok"  )
               );
    return ".*:"
            .( $state   ne "off"            ? "icoHEIZUNG.png"
              :$bat     ne "ok"             ? "measure_battery_0.svg"
              :                               "light_ceiling_off.svg"
             );
  }

  #sani_heating_level_0/10/.../100.svg
}



1;

__END__

=pod
=encoding utf8
=item device
=item summary    controls wireless homematic devices
=item summary_DE steuert HomeMatic devices auf Funk Basis
=begin html

  <a id="CUL_HM"></a><h3>CUL_HM</h3>
  <ul>
    Support for eQ-3 HomeMatic devices via the <a href="#CUL">CUL</a> or the <a href="#HMLAN">HMLAN</a>.<br>
    <br>
    <a id="CUL_HM-define"></a><h4>Define</h4>
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
      Usually you issue a <a href="#CUL-set">hmPairForSec</a> and press the
      corresponding button on the device to be paired, or issue a <a
      href="#CUL-set">hmPairSerial</a> set command if the device is a receiver
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
            href="#set-hmPairSerial">hmPairSerial</a> and <a
            href="#set-hmPairForSec">hmPairForSec</a> to enable pairing).</li>
        <a id="HMAES"></a>
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
              <li>AES-Encryption is useable with a HMLAN or a CUL. When using
                  a CUL, the perl-module Crypt::Rijndael needs to be installed.
                  Due to the issues above I do not recommend using Homematic
                  encryption at all.</li>
            </ul>
        </li>
      </ul>
    </ul><br>
    <a id="CUL_HM-set"></a><h4>Set</h4>
    <ul>
      Note: devices which are normally send-only (remote/sensor/etc) must be set
      into pairing/learning mode in order to receive the following commands.
      <br><br>
  
      Universal commands (available to most hm devices):
      <ul>
        <li><a id="CUL_HM-set-assignHmKey"></a><B>assignHmKey</B><br>
          Initiates a key-exchange with the device, exchanging the old AES-key of the device with the key with the highest
          index defined by the attribute hmKey* in the HMLAN or VCCU. The old key is determined by the reading aesKeyNbr,
          which specifies the index of the old key when the reading is divided by 2.
        </li>
        <li><a id="CUL_HM-set-clear"></a><B>clear &lt;[rssi|readings|register|msgEvents|attack|all]&gt;</B><br>
          A set of variables or readings can be removed.<br>
          <ul>
            readings: all readings are removed. Any new reading will be added usual. Used to eliminate old data.<br>
            register: all captured register-readings in FHEM are removed. NO impact to the device.<br>
            msgEvents:  all message event counter are removed. Also commandstack is cleared. <br>
            msgErrors:  message-error counter are removed.<br>
            rssi:  collected rssi values are cleared. <br>
            attack:  information regarding an attack are removed. <br>
            trigger:  all trigger readings are removed. <br>
            all:  all of the above. <br>
          </ul>
        </li>
        <li><a id="CUL_HM-set-getConfig"></a><B>getConfig</B><br>
          Will read configuration of the physical HM device. Executed
          on a channel it reads peerings and register information. <br>
          Executed on a device the command will retrieve configuration for ALL associated channels. 
        </li>
        <li><a id="CUL_HM-set-getRegRaw"></a><B>getRegRaw [List0|List1|List2|List3|List4|List5|List6|List7]&lt;peerChannel&gt; </B><br>
        
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
        
           Note2: for 'sender' see <a href="#CUL_HM-set-remote">remote</a> <br>
        
           Note3: the information retrieval may take a while - especially for
           devices with a lot of channels and links. It may be necessary to
           refresh the web interface manually to view the results <br>
        
           Note4: the direct buttons on a HM device are hidden by default.
           Nevertheless those are implemented as links as well. To get access to
           the 'internal links' it is necessary to issue <br>
           'set &lt;name&gt; <a href="#CUL_HM-set-regSet">regSet</a> intKeyVisib visib'<br>
           or<br>
           'set &lt;name&gt; <a href="#CUL_HM-set-regBulk">regBulk</a> RegL_0. 2:81'<br>
        
           Reset it by replacing '81' with '01'<br> example:<br>
        
           <ul><code>
             set mydimmer getRegRaw List1<br>
             set mydimmer getRegRaw List3 all <br>
           </code></ul>
         </li>
        <li><a id="CUL_HM-set-getSerial"></a><B>getSerial</B><br>
          Read serial number from device and write it to attribute serialNr.
        </li>
        <li><a id="CUL_HM-set-inhibit"></a><B>inhibit [on|off]</B><br>
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
        
        <li><a id="CUL_HM-set-pair"></a><B>pair</B><br>
          Pair the device with a known serialNumber (e.g. after a device reset)
          to FHEM Central unit. FHEM Central is usualy represented by CUL/CUNO,
          HMLAN,...
          If paired, devices will report status information to
          FHEM. If not paired, the device won't respond to some requests, and
          certain status information is also not reported.  Paring is on device
          level. Channels cannot be paired to central separate from the device.
          See also <a href="#CUL_HM-set-getpair">getPair</a>  and
          <a href="#CUL_HM-set-unpair">unpair</a>.<br>
          Don't confuse pair (to a central) with peer (channel to channel) with
          <a href="#CUL_HM-set-peerChan">peerChan</a>.<br>
        </li>
        <li><a id="CUL_HM-set-peerBulk"></a><B>peerBulk</B> &lt;peerch1,peerch2,...&gt; [set|unset]<br>
          peerBulk will add peer channels to the channel. All peers in the list will be added. <br>
          with unset option the peers in the list will be subtracted from the device's peerList.<br>
          peering sets the configuration of this link to its defaults. As peers are not
          added in pairs default will be as defined for 'single' by HM for this device. <br>
          More suffisticated funktionality is provided by
          <a href="#CUL_HM-set-peerChan">peerChan</a>.<br>
          peerBulk will not delete existing peers, just handle the given peerlist.
          Other already installed peers will not be touched.<br>
          peerBulk may be used to remove peers using <B>unset</B> option while default ist set.<br>
        
          Main purpose of this command is to re-store data to a device.
          It is recommended to restore register configuration utilising
          <a href="#CUL_HM-set-regBulk">regBulk</a> subsequent. <br>
          Example:<br>
          <ul><code>
            set myChannel peerBulk 12345601,<br>
            set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
            set myChannel peerBulk 12345601 unset # remove peer 123456 channel 01<br>
          </code></ul>
        </li>
        <li><a id="CUL_HM-set-regBulk"></a><B>regBulk  &lt;reg List&gt;.&lt;peer&gt; &lt;addr1:data1&gt; &lt;addr2:data2&gt;...</B><br>
          This command will replace the former regRaw. It allows to set register
          in raw format. Its main purpose is to restore a complete register list
          to values secured before. <br>
          Values may be read by <a href="#CUL_HM-set-getConfig">getConfig</a>. The
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
            set myChannel regBulk RegL_00. 02:01 0A:17 0B:43 0C:BF 15:FF 00:00<br>
            RegL_03.FB_Btn_07
           01:00 02:00 03:00 04:32 05:64 06:00 07:FF 08:00 09:FF 0A:01 0B:44 0C:54 0D:93 0E:00 0F:00 11:C8 12:00 13:00 14:00 15:00 16:00 17:00 18:00 19:00 1A:00 1B:00 1C:00 1D:FF 1E:93 1F:00 81:00 82:00 83:00 84:32 85:64 86:00 87:FF 88:00 89:FF 8A:21 8B:44 8C:54 8D:93 8E:00 8F:00 91:C8 92:00 93:00 94:00 95:00 96:00 97:00 98:00 99:00 9A:00 9B:00 9C:00 9D:05 9E:93 9F:00 00:00<br>
            set myblind regBulk 01 0B:10<br>
            set myblind regBulk 01 0C:00<br>
          </code></ul>
          myblind will set the max drive time up for a blind actor to 25,6sec
        </li>
        <li><a id="CUL_HM-set-regSet"></a><B>regSet [prep|exec] &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><br>
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
          href="#CUL_HM-set-getRegRaw">getRegRaw</a>  for full description<br>
          Supported register for a device can be explored using<br>
            <ul><code>set regSet ? 0 0</code></ul>
          Condensed register description will be printed
          using<br>
          <ul><code>set regSet &lt;regname&gt; ? 0</code></ul>
        </li>
        <li><a id="CUL_HM-set-reset"></a><B>reset</B><br>
          Factory reset the device. You need to pair it again to use it with
          fhem.
        </li>
        <li><a id="CUL_HM-set-sign"></a><B>sign [on|off]</B><br>
          Activate or deactivate signing (also called AES encryption, see the <a
          href="#HMAES">note</a> above). Warning: if the device is attached via
          a CUL, you need to install the perl-module Crypt::Rijndael to be
          able to switch it (or deactivate signing) from fhem.
        </li>
        <li><a id="CUL_HM-set-statusRequest"></a><B>statusRequest</B><br>
          Update device status. For multichannel devices it should be issued on
          an per channel base
        </li>
        <li><a id="CUL_HM-set-unpair"></a><B>unpair</B><br>
          "Unpair" the device, i.e. make it available to pair with other master
          devices. See <a href="#CUL_HM-set-pair">pair</a> for description.</li>
        <li><a id="CUL_HM-set-virtual"></a><B>virtual &lt;number of buttons&gt;</B><br>
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
          see also <a href="#CUL_HM-set-press">press</a>
        </li>
        <li><a id="CUL_HM-set-deviceRename"></a><B>deviceRename &lt;newName&gt;</B><br>
          rename the device and all its channels.
        </li>
        <li><a id="CUL_HM-set-fwUpdate"></a><B>fwUpdate [onlyEnterBootLoader] &lt;filename&gt; [&lt;waitTime&gt;]</B><br>
          update Fw of the device. User must provide the appropriate file.
          waitTime can be given optionally. In case the device needs to be set to
          FW update mode manually this is the time the system will wait.<br>
          "onlyEnterBootLoader" tells the device to enter the boot loader so it can be
          flashed using the eq3 firmware update tool. Mainly useful for flush-mounted devices
          in FHEM environments solely using HM-LAN adapters.
        </li>
        <li><B>assignIO &lt;IOname&gt; &lt;set|unset&gt;</B><a id="CUL_HM-set-assignIO"></a><br>
          Add or remove an IO device to the list of available IO's.
          Changes attribute <i>IOList</i> accordingly.
        </li>
      </ul>
  
      <br>
      <B>subType dependent commands:</B>
      <ul>
        <br>
        <li>switch
          <ul>
            <li><a id="CUL_HM-set-on"></a><B>on</B> - set level to 100%</li>
            <li><a id="CUL_HM-set-off"></a><B>off</B> - set level to 0%</li>
            <li><a id="CUL_HM-set-onForTimer"></a><B>on-for-timer &lt;sec&gt;</B> -
              set the switch on for the given seconds [0-85825945].<br> Note:
              off-for-timer like FS20 is not supported. It may to be programmed
              thru channel register.</li>
            <li><a id="CUL_HM-set-onTill"></a><B>on-till &lt;time&gt;</B> - set the switch on for the given end time.<br>
              <ul><code>set &lt;name&gt; on-till 20:32:10<br></code></ul>
              Currently a max of 24h is supported with endtime.<br>
            </li>
            <li><a id="CUL_HM-set-pressL"></a><B>pressL &lt;peer&gt; [&lt;repCount&gt;] [&lt;repDelay&gt;] </B><br>
                simulate a press of the local button or direct connected switch of the actor.<br>
                <B>&lt;peer&gt;</B> allows to stimulate button-press of any peer of the actor. 
                                    i.e. if the actor is peered to any remote, virtual or io (HMLAN/CUL) 
                                    press can trigger the action defined. <br>              
                <B>&lt;repCount&gt;</B> number of automatic repetitions.<br>
                <B>&lt;repDelay&gt;</B> timer between automatic repetitions. <br>
               <B>Example:</B>
                <code> 
                   set actor pressL FB_Btn01 # trigger long peer FB button 01<br>
                   set actor pressL FB_chn-8 # trigger long peer FB button 08<br>
                   set actor pressL self01 # trigger short of internal peer 01<br>
                   set actor pressL fhem02 # trigger short of FHEM channel 2<br>
                </code>
            </li>
            <li><a id="CUL_HM-set-pressS"></a><B>pressS &lt;peer&gt;</B><br>
                simulates a short press similar to long press
            </li>
            <li><a id="CUL_HM-set-eventL"></a><B>eventL &lt;peer&gt; &lt;condition&gt; [&lt;repCount&gt;] [&lt;repDelay&gt;] </B><br>
                simulate an event of an peer and stimulates the actor.<br>
                <B>&lt;peer&gt;</B> allows to stimulate button-press of any peer of the actor. 
                                    i.e. if the actor is peered to any remote, virtual or io (HMLAN/CUL) 
                                    press can trigger the action defined. <br>              
                <B>&lt;codition&gt;</B> the level of the condition <br>              
                <B>Example:</B>
                <code> 
                   set actor eventL md 30 # trigger from motion detector with level 30<br>
                </code>
            </li>
            <li><a id="CUL_HM-set-eventS"></a><B>eventS &lt;peer&gt; &lt;condition&gt; </B><br>
                simulates a short event from a peer of the actor. Typically sensor do not send long events.
            </li>
            <li><a id="CUL_HM-set-toggle"></a><B>toggle</B> - toggle the Actor. It will switch from any current
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
             <li><B><a href="#CUL_HM-set-on">on</a></B></li>
             <li><B><a href="#CUL_HM-set-off">off</a></B></li>
             <li><B><a href="#CUL_HM-set-press">press &lt;[short|long]&gt;&lt;[on|off]&gt;</a></B></li>
             <li><B><a href="#CUL_HM-set-toggle">toggle</a></B></li>
             <li><a id="CUL_HM-set-toggleDir"></a><B>toggleDir</B> - toggled drive direction between up/stop/down/stop</li>
             <li><B><a href="#CUL_HM-set-onForTimer">on-for-timer &lt;sec&gt;</a></B> - Dimmer only! <br></li>
             <li><B><a href="#CUL_HM-set-onTill">on-till &lt;time&gt;</a></B> - Dimmer only! <br></li>
             <li><B>stop</B> - stop motion (blind) or dim ramp</li>
             <li><B>old</B> - switch back to old value after a change. Dimmer only.</li>
             <li><B>pct &lt;level&gt [&lt;ontime&gt] [&lt;ramptime&gt]</B> - set actor to a desired <B>absolut level</B>.<br>
                    Optional ontime and ramptime could be given for dimmer.<br>
                    ontime may be time in seconds. It may also be entered as end-time in format hh:mm:ss
             </li>
             <li><B>up [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step</li>
             <li><B>down [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step<br>
                 changeValue is optional an gives the level to be changed up or down in percent. Granularity is 0.5%, default is 10%. <br>
                 ontime is optional an gives the duration of the level to be kept. '0' means forever and is default.<br>
                 ramptime is optional an defines the change speed to reach the new level. It is meaningful only for dimmer.
             <br></li>
           </ul>
          <br>
        </li>
        <li><a id="CUL_HM-set-remote"></a>remotes, pushButton<br>
             This class of devices does not react on requests unless they are put
             to learn mode. FHEM obeys this behavior by stacking all requests until
             learn mode is detected. Manual interaction of the user is necessary to
             activate learn mode. Whether commands are pending is reported on
             device level with parameter 'protCmdPend'.
        </li>
        <ul>
          <li><a id="CUL_HM-set-trgEventS"></a><B>trgEventS [all|&lt;peer&gt;] &lt;condition&gt;</B><br>
               Issue eventS on the peer entity. If <B>all</B> is selected each of the peers will be triggered. See also <a href="#CUL_HM-set-eventS">eventS</a><br>
               <B>&lt;condition&gt;</B>: is the condition being transmitted with the event. E.g. the brightness in case of a motion detector. 
          </li>
          <li><a id="CUL_HM-set-trgEventL"></a><B>trgEventL [all|&lt;peer&gt;] &lt;condition&gt;</B><br>
               Issue eventL on the peer entity. If <B>all</B> is selected each of the peers will be triggered. a normal device will not sent event long. See also <a href="#CUL_HM-set-eventL">eventL</a><br>
               <B>&lt;condition&gt;</B>: is the condition being transmitted with the event. E.g. the brightness in case of a motion detector. 
          </li>
          <li><a id="CUL_HM-set-trgPressS"></a><B>trgPressS [all|&lt;peer&gt;]</B><br>
               Issue pressS on the peer entity. If <B>all</B> is selected each of the peers will be triggered. See also <a href="#CUL_HM-set-pressS">pressS</a><br>
          </li>
          <li><a id="CUL_HM-set-trgPressL"></a><B>trgPressL [all|&lt;peer&gt;]</B><br>
               Issue pressL on the peer entity. If <B>all</B> is selected each of the peers will be triggered. See also <a href="#CUL_HM-set-pressL">pressL</a><br>
          </li>
          <li><a id="CUL_HM-set-peerIODev"></a><B>peerIODev [IO] &lt;btn_no&gt; [<u>set</u>|unset]</B><br>
               The command is similar to <B><a href="#CUL_HM-set-peerChan">peerChan</a></B>. 
               While peerChan
               is executed on a remote and peers any remote to any actor channel peerIODev is 
               executed on an actor channel and peer this to an channel of an FHEM IO device.<br>
               An IO device according to eQ3 supports up to 50 virtual buttons. Those
               will be peered/unpeerd to the actor. <a href="#CUL_HM-set-press">press</a> can be
               used to stimulate the related actions as defined in the actor register.
          </li>
          <li><a id="CUL_HM-set-peerSmart"></a><B>peerSmart [&lt;peer&gt;]</B><br>
               The command is similar to <B><a href="#CUL_HM-set-peerChan">peerChan</a></B> 
               with reduced options for peer and unpeer.<br>
               peerSmart peers in single mode (see peerChan) while funktionallity should be defined 
               by setting register (not much difference to peerChan). <br>
               Smart register setting could be done using hmTemplate.
          </li>
          <li><a id="CUL_HM-set-peerChan"></a><B>peerChan &lt;btn_no&gt; &lt;actChan&gt; [single|<u>dual</u>|reverse][<u>set</u>|unset] [<u>both</u>|actor|remote]</B><br>
          
               peerChan will establish a connection between a sender- <B>channel</B> and
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
          
               'reverse' identical to dual - but button order is reverse.<br>
          
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
               <ul><code>
                 set myRemote peerChan 2 mySwActChn single set       #peer second button to an actuator channel<br>
                 set myRmtBtn peerChan 0 mySwActChn single set       #myRmtBtn is a button of the remote. '0' is not processed here<br>
                 set myRemote peerChan 2 mySwActChn dual set         #peer button 3 and 4<br>
                 set myRemote peerChan 3 mySwActChn dual unset       #remove peering for button 5 and 6<br>
                 set myRemote peerChan 3 mySwActChn dual unset aktor #remove peering for button 5 and 6 in actor only<br>
                 set myRemote peerChan 3 mySwActChn dual set remote  #peer button 5 and 6 on remote only. Link settings il mySwActChn will be maintained<br>
               </code></ul>
          </li>
        </ul>
        <li><a id="CUL_HM-set-virtual"></a>virtual<br>
           <ul>
             <li><B><a href="#CUL_HM-set-peerChan">peerChan</a></B> see remote</li>
             <li><a id="CUL_HM-set-press"></a><B>press [long|short] [&lt;peer&gt;] [&lt;repCount&gt;] [&lt;repDelay&gt;]</B>
               <ul>
                 simulates button press for an actor from a peered sensor.
                 will be sent of type "long".
                 <li>[long|short] defines whether long or short press shall be simulated. Defaults to short</li>
                 <li>[&lt;peer&gt;] define which peer's trigger shall be simulated.Defaults to self(channelNo).</li>
                 <li>[&lt;repCount&gt;] Valid for long press only. How long shall the button be pressed? Number of repetition of the messages is defined. Defaults to 1</li>
                 <li>[&lt;repDelay&gt;] Valid for long press only. defines wait time between the single messages. </li>
               </ul>
             </li>
             <li><a id="CUL_HM-set-virtTemp"></a><B>virtTemp &lt;[off -10..50]&gt;</B>
               simulates a thermostat. If peered to a device it periodically sends the
               temperature until "off" is given. See also <a href="#CUL_HM-set-virtHum">virtHum</a><br>
             </li>
             <li><a id="CUL_HM-set-virtHum"></a><B>virtHum &lt;[off -10..50]&gt;</B>
               simulates the humidity part of a thermostat. If peered to a device it periodically sends 
               the temperature and humidity until both are "off". See also <a href="#CUL_HM-set-virtTemp">virtTemp</a><br>
             </li>
             <li><B>valvePos &lt;[off 0..100]&gt;<a id="CUL_HM-set-valvePos"></a></B>
               stimulates a VD<br>
             </li>
           </ul>
        </li>
        <li>smokeDetector<br>
          Note: All these commands work right now only if you have more then one
          smoekDetector, and you peered them to form a group. For issuing the
          commands you have to use the master of this group, and currently you
          have to guess which of the detectors is the master.<br>
          smokeDetector can be setup to teams using
          <a href="#CUL_HM-set-peerChan">peerChan</a>. You need to peer all
          team-members to the master. Don't forget to also peerChan the master
          itself to the team - i.e. peer it to itself! doing that you have full
          controll over the team and don't need to guess.<br>
          <ul>
            <li><B>teamCall</B> - execute a network test to all team members</li>
            <li><B>teamCallBat</B> - execute a network test simulate bat low</li>
            <li><B>alarmOn</B> - initiate an alarm</li>
            <li><B>alarmOff</B> - switch off the alarm</li>
          </ul>
        </li>
        <li>4Dis (HM-PB-4DIS-WM|HM-RC-DIS-H-X-EU|ROTO_ZEL-STG-RM-DWT-10)
          <ul>
            <li><B>text &lt;btn_no&gt; [on|off] &lt;text1&gt; &lt;text2&gt;</B><br>
              Set the text on the display of the device. To this purpose issue
              this set command first (or a number of them), and then choose from
              the teach-in menu of the 4Dis the "Central" to transmit the data.<br>
              If used on a channel btn_no and on|off must not be given but only pure text.<br>
              \_ will be replaced by blank character.<br>
              Example:
              <ul><code>
                set 4Dis text 1 on On Lamp<br>
                set 4Dis text 1 off Kitchen Off<br>
                <br>
                set 4Dis_chn4 text Kitchen Off<br>
              </code></ul>
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
            <br>
            <li><B>tempListTmpl   =>"[verify|restore] [[ &lt;file&gt; :]templateName] ...</B><br>
              The tempList for one or more devices can be stored in a file. User can compare the
              tempList in the file with the data read from the device. <br>
              Restore will write the tempList to the device.<br>
              Default opeartion is verify.<br>
              Default file is tempList.cfg.<br>
              Default templateName is the name of the actor<br>
              Default for file and templateName can be set with attribut <B>tempListTmpl</B><br>
              Example for templist file. room1 and room2 are the names of the template: <br>
              <code>entities:room1
                 tempListSat>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              entities:room2
                 tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              </code>
              Specials:<br>
              <li>none: template will be ignored</li>
              <li>defaultWeekplan: as default each day is set to 18.0 degree. 
                  useful if peered to a TC controller. Implicitely teh weekplan of TC will be used.</li>
            </li>
            <li><B>tempTmplSet   =>"[[ &lt;file&gt; :]templateName]</B><br>
              Set the attribut and apply the change to the device
            </li>
            <li><B>tplDel   =>" &lt;template&gt; </B><br>
              Delete template entry for this entity
            </li>
            <li><B>tplSet_&lt;peer&gt;   =>" &lt;template&gt; </B><br>
              Set a template for a peer of the entity. Possible parameter will be set to the current register value of the device - i.e. no  change to the register. Parameter may be changed after assigning the template by using the tplPara command.<br>
              The command is avalilable if HMinfo is defined and a tamplate fitting the combination is available. Note that the register of the device need to be available (see getConfig command).<br>
              In case of dedicated template for long and short trigger separat commands will be available.
            </li>
            <li><B>tplParaxxx_&lt;peer&gt;_&lt;tpl&gt;_&lt;param&gt;   =>" &lt;template&gt; </B><br>
              A parameter of an assigned template can be modified. A command s available for each parameter of each assigned template. 
            </li>
            <li><B>partyMode &lt;HH:MM&gt;&lt;durationDays&gt;</B><br>
              set control mode to party and device ending time. Add the time it ends
              and the <b>number of days</b> it shall last. If it shall end next day '1'
              must be entered<br></li>
            <li><B>sysTime</B><br>
                set time in climate channel to system time</li>
          </ul><br>
        </li>
        <li>Climate-Control (HM-CC-RT-DN|HM-CC-RT-DN-BOM)
          <ul>
            <li><B>controlMode &lt;auto|boost|day|night&gt;</B><br></li>
            <li><B>controlManu &lt;temp&gt;</B><br></li>
            <li><B>controlParty &lt;temp&gt;&lt;startDate&gt;&lt;startTime&gt;&lt;endDate&gt;&lt;endTime&gt;</B><br>
                set control mode to party, define temp and timeframe.<br>
                example:<br>
                <code>set controlParty 15 03-8-13 20:30 5-8-13 11:30</code></li>
            <li><B>sysTime</B><br>
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
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-CFM-PL)
          <ul>
            <li><B>led &lt;color&gt;[,&lt;color&gt;..] [&lt;repeat&gt..]</B><br>
              Possible colors are [redL|greenL|yellowL|redS|greenS|yellowS|pause]. A
              sequence of colors can be given separating the color entries by ','.
              White spaces must not be used in the list. 'S' indicates short and
              'L' long ilumination. <br>
              <b>repeat</b> defines how often the sequence shall be executed. Defaults to 1.<br>
            </li>
            <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt..] [&lt;repeat&gt;] [&lt;volume&gt;]</B><br>
              Play a series of tones. List is to be entered separated by ','. White
              spaces must not be used in the list.<br>
              <b>replay</b> can be entered to repeat the last sound played once more.<br>
              <b>repeat</b> defines how often the sequence shall be played. Defaults to 1.<br>
          <b>volume</b> is defined between 0 and 10. 0 stops any sound currently playing. Defaults to 10 (100%).<br>
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
        <li>HM-DIS-WM55
          <ul>
            <li><B>displayWM help </B><br>
              <B>displayWM [long|short] &lt;text1&gt; &lt;color1&gt; &lt;icon1&gt; ... &lt;text6&gt; &lt;color6&gt; &lt;icon6&gt;</B><br>
              <B>displayWM [long|short] &lt;lineX&gt; &lt;text&gt; &lt;color&gt; &lt;icon&gt;</B><br>
              up to 6 lines can be addressed.<br>
              <B>lineX</B> line number that shall be changed. If this is set the 3 parameter of a line can be adapted. <br>
              <B>textNo</B> is the text to be dispalyed in line No. The text is assotiated with the text defined for the buttons.
              txt&lt;BtnNo&gt;_&lt;lineNo&gt; references channel 1 to 10 and their lines 1 or 2.
              Alternaly a free text of up to 12 char can be used<br>
              <B>color</B> is one white, red, orange, yellow, green, blue<br>
              <B>icon</B> is one off, on, open, closed, error, ok, noIcon<br>
              Example:
              <ul><code>
                set disp01 displayWM short txt02_2 green noIcon txt10_1 red error txt05_2 yellow closed txt02_2 orange open <br>
                set disp01 displayWM long line3 txt02_2 green noIcon<br>
                set disp01 displayWM long line2 nc yellow noIcon<br>
                set disp01 displayWM long line6 txt02_2<br>
                set disp01 displayWM long line1 nc nc closed<br>
              </ul></code>
            </li>
          </ul><br>
        </li>
        <li>HM-DIS-EP-WM55
          <ul>
            <li><B>displayEP help </B><br>
              <B>displayEP &lt;text1,icon1:text2,icon2:text3,icon3&gt; &lt;sound&gt; &lt;repetition&gt; &lt;pause&gt; &lt;signal&gt;</B><br>
              up to 3 lines can be addressed.<br>
              If help is given a <i><B>help</B></i> on the command is given. Options for all parameter will be given.<br>
              <B>textx</B> 12 char text for the given line. 
                If empty the value as per reading will be transmittet - i.e. typically no change.
                text0-9 will display predefined text of channels 4 to 8.
                0xHH allows to display a single char in hex format.<br>
              <B>iconx</B> Icon for this line. 
                If empty the value as per reading will be transmittet - i.e. typically no change.<br>
              <B>sound</B> sound to be played<br>
              <B>repetition</B> 0..15 <br>
              <B>pause</B> 1..160<br>
              <B>signal</B> signal color to be displayed<br>
              <br>
              <B>Note: param reWriteDisplayxx</B> <br>
              <li>
                upon button press the device will overwrite the 3 middles lines. When set <br>
                attr chan param reWriteDisplayxx<br>
                the 3 lines will be rewritten to the latest value after xx seconds. xx is between 01 and 99<br>
              </li>
              
            </li>
          </ul><br>
        </li>
        <li>keyMatic<br><br>
          <ul>The Keymatic uses the AES signed communication. Control
              of the Keymatic is possible with the HM-LAN adapter and the CUL.
              To control the KeyMatic with a CUL, the perl-module Crypt::Rijndael
              needs to be installed.</ul><br>
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
          </ul>
        </li>
        <li>CCU_FHEM<br>
          <ul>
            <li>defIgnUnknown<br>
              define unknown devices which are present in the readings. 
              set attr ignore and remove the readingfrom the list. <br>
            </li>
          </ul>
        </li>
        <li>HM-SYS-SRP-PL<br><br>
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
              will rewrite the complete list to the deivce. Data will be taken from attribut repPeers. <br>
              attribut repPeers is formated:<br>
              src1:dst1:[y/n],src2:dst2:[y/n],src2:dst2:[y/n],...<br>
              <br>
              Reading repPeer is formated:<br>
              <ul>
                Number src dst broadcast verify<br>
                number: entry sequence number<br>
                src: message source device - read from repeater<br>
                dst: message destination device - assembled from attributes<br>
                broadcast: shall broadcast be repeated for this source - read from repeater<br>
                verify: do attributes and readings match?<br>
              </ul>
            </li>
          </ul>
        </li>
        <br>
        Debugging:
        <ul>
          <li><B>raw &lt;data&gt; ...</B><br>
              Only needed for experimentation.
              send a "raw" command. The length will be computed automatically, and the
              message counter will be incremented if the first two charcters are
              ++. Example (enable AES):
           <pre>
             set hm1 raw ++A001F100001234560105000000001</pre>
          </li>
        </ul>
    </ul>
    </ul>
    <br>
    <a id="CUL_HM-get"></a><h4>Get</h4><br>
    <ul>
       <li><a id="CUL_HM-get-configSave"></a><B>configSave &lt;filename&gt;</B><br>
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
       <li><a id="CUL_HM-get-reg"></a><B>reg &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
           returns the value of a register. The data is taken from the storage in FHEM and not 
           read directly outof the device. 
           If register content is not present please use getConfig, getReg in advance.<br>
  
           &lt;addr&gt; address in hex of the register. Registername can be used alternaly 
           if decoded by FHEM. "all" will return all decoded register for this entity in one list.<br>
           &lt;list&gt; list from which the register is taken. If rgistername is used list 
           is ignored and can be set to 0.<br>
           &lt;peerID&gt; identifies the registerbank in case of list3 and list4. It an be set to dummy if not used.<br>
           </li>
       <li><B>regVal &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
           returns the value of a register. It does the same as <a href="#CUL_HM-get-reg">reg</a> but strips off units<br>
           </li>
       <li><B>regList</B><br>
           returns a list of register that are decoded by FHEM for this device.<br>
           Note that there could be more register implemented for a device.<br>
           </li>
  
       <li><a id="CUL_HM-get-saveConfig"></a><B>saveConfig &lt;file&gt;</B><br>
           stores peers and register to the file.<br>
           Stored will be the data as available in fhem. It is necessary to read the information from the device prior to the save.<br>
           The command supports device-level action. I.e. if executed on a device also all related channel entities will be stored implicitely.<br>
           Storage to the file will be cumulative. 
           If an entity is stored multiple times to the same file data will be appended. 
           User can identify time of storage in the file if necessary.<br>
           Content of the file can be used to restore device configuration. 
           It will restore all peers and all register to the entity.<br>
           Constrains/Restrictions:<br>
           prior to rewrite data to an entity it is necessary to pair the device with FHEM.<br>
           restore will not delete any peered channels, it will just add peer channels.<br>
           </li>
       <li><a id="CUL_HM-get-list"></a><B>list (normal|hidden);</B><br>
           issue list command for the fiven entity normal or including the hidden parameter
           </li>       
       <li><B>listDevice</B><br>
           <ul>
                <li>when used with ccu it returns a list of Devices using the ccu service to assign an IO.<br>
                    </li>
                <li>when used with ActionDetector user will get a comma separated list of entities being assigned to the action detector<br>
                    get ActionDetector listDevice          # returns all assigned entities<br>
                    get ActionDetector listDevice notActive# returns entities which habe not status alive<br>
                    get ActionDetector listDevice alive    # returns entities with status alive<br>
                    get ActionDetector listDevice unknown  # returns entities with status unknown<br>
                    get ActionDetector listDevice dead     # returns entities with status dead<br>
                    </li> 
               </ul>
           </li>       
       <li><B>info</B><br>
           <ul>
                <li>provides information about entities using ActionDetector<br>
                    </li>
               </ul>
           </li>       
    </ul><br>

    <a id="CUL_HM-attr"></a><h4>Attributes</h4>
    <ul>
      <li><a href="#eventMap">eventMap</a></li>
      <li><a href="#do_not_notify">do_not_notify</a></li>
      <li><a href="#ignore">ignore</a></li>
      <li><a href="#dummy">dummy</a></li>
      <li><a href="#showtime">showtime</a></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li><a id="CUL_HM-attr-actAutoTry"></a>actAutoTry<br>
           actAutoTry 0_off,1_on<br>
           setting this option enables Action Detector to send a statusrequest in case of a device is going to be marked dead.
           The attribut may be useful in case a device is being checked that does not send messages regularely - e.g. an ordinary switch. 
          </li>
      <li><a id="CUL_HM-attr-actCycle"></a>actCycle &lt;[hhh:mm]|off&gt;<br>
           Supports 'alive' or better 'not alive' detection for devices. [hhh:mm] is the maximum silent time for the device. 
           Upon no message received in this period an event will be raised "&lt;device&gt; is dead". 
           If the device sends again another notification is posted "&lt;device&gt; is alive". <br>
           This actiondetect will be autocreated for each device with build in cyclic status report.<br>
           Controlling entity is a pseudo device "ActionDetector" with HMId "000000".<br>
           Due to performance considerations the report latency is set to 600sec (10min). 
           It can be controlled by the attribute "actCycle" of "ActionDetector".<br>
           Once entered to the supervision the HM device has 2 attributes:<br>
           <ul>
           actStatus: activity status of the device<br>
           actCycle:  detection period [hhh:mm]<br>
           </ul>
           The overall function can be viewed checking out the "ActionDetector" entity. The status of all entities is present in the READING section.<br>
           Note: This function can be enabled for devices with non-cyclic messages as well. It is up to the user to enter a reasonable cycletime.
          </li>
      <li><a id="CUL_HM-attr-actStatus"></a>actStatus<br>
           readonly<br>
           This attribut is set by ActionDetector. It cannot be set manually
          </li>
      <li><a id="CUL_HM-attr-aesCommReq"></a>aesCommReq<br>
           if set IO is forced to request AES signature before sending ACK to the device.<br>
           Defautls to 0<br>
          </li>
      <li><a id="CUL_HM-attr-aesKey" data-pattern="aesKey.*"></a>aesKey<br>
          specifies which aes key is to be used if aesCommReq is active<br>
          </li>
      <li><a id="CUL_HM-attr-autoReadReg"></a>autoReadReg<br>
          '0' autoReadReg will be ignored.<br>
          '1' will execute a getConfig for the device automatically after each reboot of FHEM. <br>
          '2' like '1' plus execute after power_on.<br>
          '3' includes '2' plus updates on writes to the device<br>
          '4' includes '3' plus tries to request status if it seems to be missing<br>
          '5' checks reglist and peerlist. If reading seems incomplete getConfig will be scheduled<br>
          '8_stateOnly' will only update status information but not configuration
                         data like register and peer<br>
          Execution will be delayed in order to prevent congestion at startup. Therefore the update
          of the readings and the display will be delayed depending on the size of the database.<br>
          Recommendations and constrains upon usage:<br>
          <ul>
              usage on devices which only react to 'config' mode is not recommended since executen will
              not start until config is triggered by the user<br>
              usage on devices which support wakeup-mode is usefull. But consider that execution is delayed
              until the device "wakes up".<br>
              </ul>
          </li>
      <li><a id="CUL_HM-attr-burstAccess"></a>burstAccess<br>
          can be set for the device entity if the model allowes conditionalBurst.
          The attribut will switch off burst operations (0_off) which causes less message load
          on HMLAN and therefore reduces the chance of HMLAN overload.<br>
          Setting it on (1_auto) allowes shorter reaction time of the device. User does not
          need to wait for the device to wake up. <br>
          Note that also the register burstRx needs to be set in the device.</li>
      <li><a id="CUL_HM-attr-expert"></a>expert &lt;option1[[,option2],...]&gt;<br>
          This attribut controls the visibility of the register readings. This attibute controls
          the presentation of device parameter in readings.<br>
          Options are:<br>
          <ul>
          defReg       : default register<br>
          allReg       : all register<br>
          rawReg       : raw reading<br>
          templ        : template assiciation<br>
          none         : no register<br>
          </ul>
          If expert is applied to the device it is used for assotiated channels if not overwritten by it.<br>
          </li>
      <li><a id="CUL_HM-attr-commStInCh"></a>communication status copied to channel reading<br>
          on: device communication status not visible in channel entities<br>
          off: device communication status commState is visiblein channel entities<br>
          </li>
      <li><a id="CUL_HM-attr-firmware"></a>firmware &lt;FWversion&gt;<br>
          Firmware version of the device. Should not be overwritten.
          </li>
      <li><a id="CUL_HM-attr-hmKey" data-pattern="hmKey.*"></a>hmKey &lt;key&gt;<br>
          AES key to be used
          </li>
      <li><a id="CUL_HM-attr-hmProtocolEvents"></a>hmProtocolEvents<br>
          parses and logs the device messages. This is performance consuming and may disturb the timing. Use with care.<br>
          Options:<br>
          <ul>
          0_off         : no parsing - default<br>
          1_dump        : log all messages<br>
          2_dumpFull    : log with extended parsing<br>
          3_dumpTrigger : log full and include trigger events<br>
          </ul>
          </li>
      <li><a id="CUL_HM-attr-readOnly"></a>readOnly<br>
          1: restricts commands to read od observ only.
          </li>
      <li><a id="CUL_HM-attr-readingOnDead"></a>readingOnDead<br>
          defines how readings shall be treated upon device is marked 'dead'.<br>
          The attribute is applicable for devices only. It will modify the readings upon entering dead of the device. 
          Upon leaving state 'dead' the selected readings will be set to 'notDead'. It is expected that useful values will be filled by the normally operating device.<br>
          Options are:<br>
          noChange: no readings will be changed upon entering 'dead' except Actvity. Other valvues will be ignored<br>
          state: set the entites 'state' readings to dead<br>
          periodValues: set periodic numeric readings of the device to '0'<br>
          periodString: set periodic string readings of the device to 'dead'<br>
          channels: if set the device's channels will be effected identical to the device entity<br>
          custom readings: customer may add a list of other readings that will be set to 'dead'<br>
          <br>
          Example:<br>
          <ul><code>
            attr myDevice readingOnDead noChange,state # no dead marking - noChange has priority <br>
            attr myDevice readingOnDead state,periodValues,channels # Recommended. reading state of the device and all its channels will be set to 'dead'. 
            Periodic numerical readings will be set to 0 which influences graphics<br>
            attr myDevice readingOnDead state,channels # reading state of the device and all its channels will be set to 'dead'.<br>
            attr myDevice readingOnDead periodValues,channels # numeric periodic readings of device and channels will be set to '0' <br>
            attr myDevice readingOnDead state,deviceMsg,CommandAccepted # upon entering dead state,deviceMsg and CommandAccepted of the device will be set to 'dead' if available.<br>
          </code></ul>           
          </li>
      <li><a id="CUL_HM-attr-rssiLog"></a>rssiLog<br>
          can be given to devices, denied for channels. If switched '1' each RSSI entry will be
          written to a reading. User may use this to log and generate a graph of RSSI level.<br>
          Due to amount of readings and events it is NOT RECOMMENDED to switch it on by default.
          </li>
      <li><a id="CUL_HM-attr-IOgrp"></a>IOgrp<br>
          can be given to devices and shall point to a virtual CCU. 
          Setting the attribut will remove attr IODev since it mutual exclusiv. 
          As a consequence the
          VCCU will take care of the assignment to the best suitable IO. It is necessary that a
          virtual VCCU is defined and all relevant IO devices are assigned to it. Upon sending the CCU will
          check which IO is operational and has the best RSSI performance for this device.<br>
          Optional a prefered IO - perfIO can be given. In case this IO is operational it will be selected regardless
          of rssi values. <br>
          If none is detected in the VCCU's IOList the mechanism is stopped.<br>
          Example:<br>
          <ul><code>
            attr myDevice1 IOgrp vccu<br>
            attr myDevice2 IOgrp vccu:prefIO<br>
            attr myDevice2 IOgrp vccu:prefIO1,prefIO2,prefIO3<br>
            attr myDevice2 IOgrp vccu:prefIO1,prefIO2,none<br>
          </code></ul>
          </li>
      <li><a id="CUL_HM-attr-levelRange"></a>levelRange &lt;min,max&gt;<br>
          It defines the usable dimm-range.
          Can be used for e.g. LED light starting at 10% and reach maxbrightness at 40%.
          levelRange will normalize the level to this range. I.e. set to 100% will physically set the 
          dimmer to 40%, 1% will set to 10% physically. 0% still switches physially off.<br>
          Applies to all level commands as on, up, down, toggle and pct. off and level 0 still sets to physically 0%.<br>
          LevelRage does not impact register controlled level and direct peering.<br>
          The attribut needs to be set for each virtual channel of a device.<br>
          Example:<br>
          <ul><code>
            attr myChannel levelRange 10,80<br>
          </code></ul>
          </li>
      <li><a id="CUL_HM-attr-levelMap"></a>levelMap &lt;<val1>=<key1>[:<val2>=<key2>[:...]]&gt;<br>
          the level value valX will be replaced by keyX. Multiple values can be mapped. 
          </li>
      <li><a id="CUL_HM-attr-modelForce"></a>modelForce<br>
          modelForce overwrites the model attribute. Doing that it converts the device and its channel to the new model.<br>
          Reason for this attribute is an eQ3 bug as some devices are delivered with wrong Module IDs.<br>
          ATTENTION: changing model id automatically starts reconfiguration of the device and its channels! channels may be deleted or incarnated<br>
          </li>
      <li><a id="CUL_HM-attr-model"></a>model<br>
          showes model. This is read only.
          </li>
      <li><a id="CUL_HM-attr-subType"></a>subType<br>
          showes models subType. This is read only.</li>
      <li><a id="CUL_HM-attr-serialNr"></a>serialNr<br>
          device serial number. Should not be set manually</li>
      <li><a id="CUL_HM-attr-msgRepeat"></a>msgRepeat<br>
          defines number of repetitions if a device doesn't answer in time. <br>
          Devices which donly support config mode no repeat ist allowed. <br>
          For devices with wakeup mode the device will wait for next wakeup. Lonng delay might be 
          considered in this case. <br>
          Repeat for burst devices will impact HMLAN transmission capacity.</li>
      <li><a id="CUL_HM-attr-peerIDs"></a>peerIDs<br>
          will be filled automatically by getConfig and shows the direct peerings of the channel. Should not be changed by user.</li>
      <li><a id="CUL_HM-attr-rawToReadable"></a>rawToReadable<br>
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
      <li><a id="CUL_HM-attr-tempListTmpl"></a>tempListTmpl<br>
          Sets the default template for a heating controller. If not given the detault template is taken from 
          file tempList.cfg using the enitity name as template name (e.g. ./tempLict.cfg:RT1_Clima <br> 
          To avoid template usage set this attribut to 'none' or '0'.<br> 
          Format is &lt;file&gt;:&lt;templatename&gt;. lt
          </li>
      <li><a id="CUL_HM-attr-unit"></a>unit<br>
          set the reported unit by the KFM100 if rawToReadable is active. E.g.<br>
          attr KFM100 unit Liter
          </li>
      <li><a id="CUL_HM-attr-cyclicMsgOffset"></a>cyclicMsgOffset<br>
          when calculating the timestamp for sending the next cyclic message (e.g. weather or valve data) then the value of this attribute<br>
          in milliseconds is added to the result. So adjusting this might fix problems for example when weather messages of virtual devices are not received reliably
          </li>
    </ul>  <br>
    <li>
    <a id="CUL_HM-attr-param"></a><b>param defines model specific behavior or functions. Available parameters are (model dependand):</b>
    <ul>
      <li><B>HM-SEN-RD-O</B><br>
        <B>offAtPon</B> heat channel only: force heating off after powerOn<br>
        <B>onAtRain</B> heat channel only: force heating on while status changes to 'rain' and off when it changes to 'dry'<br>
      </li>
      <li><B>virtuals</B><br>
        <B>noOnOff</B> virtual entity will not toggle state when trigger is received. If this parameter is
        not given the entity will toggle its state between On and Off with each trigger<br>
        <B>msgReduce:&lt;No&gt;</B> if channel is used for <a ref="CUL_HM-set-valvePos">valvePos</a> it skips every No message
        in order to reduce transmit load. Numbers from 0 (no skip) up to 9 can be given. 
        VD will lose connection with more then 5 skips<br>
      </li>
      <li><B>blind</B><br>
        <B>levelInverse</B> while HM considers 100% as open and 0% as closed this may not be 
        intuitive to all user. Ny default 100%  is open and will be dislayed as 'on'. Setting this param the display will be inverted - 0% will be open and 100% is closed.<br>
        NOTE: This will apply to readings and set commands. <B>It does not apply to any register. </B><br>
        <B>ponRestoreSmart</B> upon powerup of the device the Blind will drive to expected closest endposition followed by driving to the pre-PON level<br>
        <B>ponRestoreForce</B> upon powerup of the device the Blind will drive to level 0, then to level 100 followed by driving to the pre-PON level<br>
      </li>
      <li><B>switch</B><br>
        <B>levelInverse</B> siehe <i>blind</i> above.
      </li>
      
      <li><B>sensRain</B><br>
          <B>siren</B><br>
          <B>powerMeter</B><br>
          <B>switch</B><br>
          <B>dimmer</B><br>
          <B>rgb</B><br>
        <B>showTimed</B> if timmed is running -till will be added to state. 
                         This results eventually in state on-till which allowes better icon handling.<br>
      </li>
    </ul>
    </li><br>
    <a id="CUL_HM-events"></a><h4>Generated events:</h4>
    <ul>
      <li><B>general</B><br>
          recentStateType:[ack|info] # cannot be used ti trigger notifies<br>
            <ul>
              <li>ack indicates that some statusinfo is derived from an acknowledge</li>  
              <li>info indicates an autonomous message from the device</li>  
              <li><a id="CUL_HM-attr-sabotageAttackId"></a><b>sabotageAttackId</b><br>
                Alarming configuration access to the device from a unknown source<br></li>
              <li><a id="CUL_HM-attr-sabotageAttack"></a><b>sabotageAttack</b><br>
                Alarming configuration access to the device that was not issued by our system<br></li>
              <li><a id="CUL_HM-attr-trigDst"></a><b>trigDst_&lt;name&gt;: noConfig</b><br>
                A sensor triggered a Device which is not present in its peerList. Obviously the peerList is not up to date<br></li>
           </ul>
         </li>  
      <li><B>HM-CC-TC,ROTO_ZEL-STG-RM-FWT</B><br>
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
          controlMode [auto|manual|central|party]<br>
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
      <li><B>HM-CC-RT-DN and HM-CC-RT-DN-BOM</B><br>
          state:T: $actTemp desired: $setTemp valve: $vp %<br>
          motorErr: [ok|ValveTight|adjustRangeTooLarge|adjustRangeTooSmall|communicationERR|unknown|lowBat|ValveErrorPosition]
          measured-temp $actTemp<br>
          desired-temp $setTemp<br>
          ValvePosition $vp %<br>
          mode  [auto|manual|party|boost]<br>
          battery [low|ok]<br>
          batteryLevel $bat V<br>
          measured-temp $actTemp<br>
          desired-temp $setTemp<br>
          actuator $vp %<br>
          time-request<br>
          trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel.
      </li>
      <li><B>HM-CC-VD,ROTO_ZEL-STG-RM-FSA</B><br>
          $vp %<br>
          battery:[critical|low|ok]<br>
          motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
          ValvePosition:$vp %<br>
          ValveErrorPosition:$vep %<br>
          ValveOffset:$of %<br>
          ValveDesired:$vp %            # set by TC <br>
          operState:[errorTargetNotMet|onTarget|adjusting|changed]  # operational condition<br>
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
          [off|red|green|orange]        # for channel <br>
      </li>
      <li><B>HM-OU-CFM-PL</B><br>
          [on|off|$val]<br>
      </li>
      <li><B>HM-SEN-WA-OD</B><br>
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
      <li><B>HM-SEN-RD-O</B><br>
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
          cover [closed|open]        # not for HM-SEC-MDIR<br>
          sabotageError [on|off]     # only HM-SEC-MDIR<br>
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
            Btn$x Short<br>
            Btn$x Short (to $dest)<br>
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
          level &lt;val&ge;<br>
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
          teamCall:from $src<br>
      </li>
      <li><B>threeStateSensor</B><br>
          [open|tilted|closed]<br>
          [wet|damp|dry]                 #HM-SEC-WDS only<br>
          cover [open|closed]            #HM-SEC-WDS and HM-SEC-RHS<br>
          alive yes<br>
          battery [low|ok]<br>
          contact [open|tilted|closed]<br>
          contact [wet|damp|dry]         #HM-SEC-WDS only<br>
          sabotageError [on|off]         #HM-SEC-SC only<br>
      </li>
      <li><B>winMatic</B><br>
          [locked|$value]<br>
          motorErr [ok|TurnError|TiltError]<br>
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
    <a id="CUL_HM-internals"></a><h4>Internals</h4>
    <ul>
      <li><B>aesCommToDev</B><br>
        gives information about success or fail of AES communication between IO-device and HM-Device<br>
      </li>
    </ul><br>
    <br>
  </ul>
=end html
=begin html_DE

  <a id="CUL_HM"></a><h3>CUL_HM</h3>
  <ul>
    Unterst&uuml;tzung f&uuml;r eQ-3 HomeMatic Ger&auml;te via <a href="#CUL">CUL</a> oder <a href="#HMLAN">HMLAN</a>.<br>
    <br>
    <a id="CUL_HM-define"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; CUL_HM &lt;6-digit-hex-code|8-digit-hex-code&gt;</B></code>
      
      <br><br>
      Eine korrekte Ger&auml;tedefinition ist der Schl&uuml;ssel zur einfachen Handhabung der HM-Umgebung.
      <br>
      
      Hintergrund zur Definition:<br>
      HM-Ger&auml;te haben eine 3 Byte (6 stelliger HEX-Wert) lange HMid - diese ist Grundlage
      der Adressierung. Jedes Ger&auml;t besteht aus einem oder mehreren Kan&auml;len. Die HMid f&uuml;r einen
      Kanal ist die HMid des Ger&auml;tes plus die Kanalnummer (1 Byte, 2 Stellen) in
      hexadezimaler Notation.
      Kan&auml;le sollten f&uuml;r alle mehrkanaligen Ger&auml;te definiert werden. Eintr&auml;ge f&uuml;r Kan&auml;le
      k&ouml;nnen nicht angelegt werden wenn das zugeh&ouml;rige Ger&auml;t nicht existiert.<br> Hinweis: FHEM
      belegt das Ger&auml;t automatisch mit Kanal 1 falls dieser nicht explizit angegeben wird. Daher
      ist bei einkanaligen Ger&auml;ten keine Definition n&ouml;tig.<br>
      
      Hinweis: Wird ein Ger&auml;t gel&ouml;scht werden auch die zugeh&ouml;rigen Kan&auml;le entfernt. <br> Beispiel einer
      vollst&auml;ndigen Definition eines Ger&auml;tes mit 2 Kan&auml;len:<br>
      <ul><code>
        define livingRoomSwitch CUL_HM 123456<br>
        define LivingroomMainLight CUL_HM 12345601<br>
        define LivingroomBackLight CUL_HM 12345602<br><br>
      </code></ul>
      
      livingRoomSwitch bezeichnet das zur Kommunikation verwendete Ger&auml;t. Dieses wird
      vor den Kan&auml;len definiert um entsprechende Verweise einstellen zu k&ouml;nnen. <br>
      LivingroomMainLight hat Kanal 01 und behandelt den Lichtstatus, Kanal-Peers
      sowie zugeh&ouml;rige Kanalregister. Falls nicht definiert wird Kanal 01 durch die Ger&auml;teinstanz
      abgedeckt.<br> LivingRoomBackLight ist der zweite "Kanal", Kanal 02. Seine
      Definition ist verpflichtend um die Funktion ausf&uuml;hren zu k&ouml;nnen.<br><br>
      
      Sonderfall Sender: HM behandelt jeden Knopf einer Fernbedienung, Drucktaster und
      &auml;hnliches als Kanal . Es ist m&ouml;glich (nicht notwendig) einen Kanal pro Knopf zu
      definieren. Wenn alle Kan&auml;le definiert sind ist der Zugriff auf Pairing-Informationen
      sowie auf Kanalregister m&ouml;glich. Weiterhin werden Verkn&uuml;pfungen durch Namen besser
      lesbar.<br><br>
      
      define kann auch durch das <a href="#autocreate">autocreate</a>
      Modul aufgerufen werden, zusammen mit dem notwendigen subType Attribut.
      Normalerweise erstellt man <a href="#CUL-set">hmPairForSec</a> und dr&uuml;ckt dann den
      zugeh&ouml;rigen Knopf am Ger&auml;t um die Verkn&uuml;pfung herzustellen oder man verwendet <a
      href="#CUL-set">hmPairSerial</a> falls das Ger&auml;t ein Empf&auml;nger und die Seriennummer
      bekannt ist. Autocreate wird dann ein FHEM-Ger&auml;t mit allen notwendigen Attributen anlegen.
      Ohne Pairing wird das Ger&auml;t keine Befehle von FHEM akzeptieren. Selbst wenn das Pairing
      scheitert legt FHEM m&ouml;glicherweise das Ger&auml;t an. Erfolgreiches Pairen wird
      durch den Eintrag CommandAccepted in den Details zum CUL_HM Ger&auml;t angezeigt.<br><br>
      
      Falls autocreate nicht verwendet werden kann muss folgendes spezifiziert werden:<br>
      <ul>
        <li>Der &lt;6-stellige-Hex-Code&gt;oder HMid+ch &lt;8-stelliger-Hex-Code&gt;<br>
          Das ist eine einzigartige, festgelegte Ger&auml;teadresse die nicht ge&auml;ndert werden kann (nein,
          man kann sie nicht willk&uuml;rlich ausw&auml;hlen wie z.B. bei FS20 Ger&auml;ten). Man kann sie feststellen
          indem man das FHEM-Log durchsucht.</li>
        <li>Das subType Attribut<br>
          Dieses lautet: switch dimmer blindActuator remote sensor swi
          pushButton threeStateSensor motionDetector keyMatic winMatic
          smokeDetector</li>
        <li>Das model Attribut<br>
        ist entsprechend der HM Nomenklatur zu vergeben</li>
      </ul>
      Ohne diese Angaben kann FHEM nicht korrekt mit dem Ger&auml;t arbeiten.<br><br>
      
      <b>Hinweise</b>
      <ul>
        <li>Falls das Interface ein Ger&auml;t vom Typ CUL ist muss <a href="#rfmode">rfmode </a>
          des zugeh&ouml;rigen CUL/CUN Ger&auml;tes auf HomeMatic gesetzt werden.
          Achtung: Dieser Modus ist nur f&uuml;r BidCos/Homematic. Nachrichten von FS20/HMS/EM/S300
          werden durch diese Ger&auml;t <b>nicht</b> empfangen. Bereits definierte FS20/HMS
          Ger&auml;te m&uuml;ssen anderen Eing&auml;ngen zugeordnet werden (CUL/FHZ/etc).
        </li>
        <li>Nachrichten eines Ger&auml;ts werden nur richtig interpretiert wenn der Ger&auml;tetyp
          bekannt ist. FHEM erh&auml;lt den Ger&auml;tetyp aus einer"pairing request"
          Nachricht, selbst wenn es darauf keine Antwort erh&auml;lt (siehe <a
          href="#hmPairSerial">hmPairSerial</a> und <a
          href="#hmPairForSec">hmPairForSec</a> um Parinig zu erm&ouml;glichen).</li>
        <a id="HMAES"></a>
        <li>Die sogenannte "AES-Verschl&uuml;sselung" ist eigentlich eine Signaturanforderung: Ist sie
          aktiviert wird ein Aktor den erhaltenen Befehl nur ausf&uuml;hren falls er die korrekte
          Antwort auf eine zuvor durch den Aktor gestellte Anfrage erh&auml;lt. Das bedeutet:
          <ul>
            <li>Die Reaktion auf Befehle ist merklich langsamer, da 3 Nachrichten anstatt einer &uuml;bertragen
              werden bevor der Befehl vom Aktor ausgef&uuml;hrt wird.</li>
            <li>Jeder Befehl sowie seine Best&auml;tigung durch das Ger&auml;t wird in Klartext &uuml;bertragen, ein externer
              Beobachter kennt somit den Status jedes Ger&auml;ts.</li>
            <li>Die eingebaute Firmware ist fehlerhaft: Ein "toggle" Befehl wir ausgef&uuml;hrt <b>bevor</b> die
              entsprechende Antwort auf die Signaturanforderung empfangen wurde, zumindest bei einigen Schaltern
              (HM-LC-SW1-PL und HM-LC-SW2-PB-FM).</li>
            <li>Der <a href="#HMLAN">HMLAN</a> Konfigurator beantwortet Signaturanforderungen selbstst&auml;ndig,
              ist dabei die 3-Byte-Adresse einer anderen CCU eingestellt welche noch immer das Standardpasswort hat,
              kann dieser Signaturanfragen korrekt beantworten.</li>
            <li>AES-Verschl&uuml;sselung wird durch HMLAN und CUL unterst&uuml;tzt. Bei Einsatz eines CUL
              ist das Perl-Modul Crypt::Rijndael notwendig. Aufgrund dieser Einschr&auml;nkungen ist der
              Einsatz der Homematic-Verschl&uuml;sselung nicht zu empfehlen!</li>
          </ul>
        </li>
      </ul>
    </ul><br>
    <a id="CUL_HM-set"></a><b>Set</b>
    <ul>
      Hinweis: Ger&auml;te die normalerweise nur senden (Fernbedienung/Sensor/etc.) m&uuml;ssen in den
      Pairing/Lern-Modus gebracht werden um die folgenden Befehle zu empfangen.
      <br>
      <br>
      
      Allgemeine Befehle (verf&uuml;gbar f&uuml;r die meisten HM-Ger&auml;te):
      <ul>
        <li><B>clear &lt;[rssi|readings|register|msgEvents|attack|all]&gt;</B><a id="CUL_HM-set-clear"></a><br>
            Eine Reihe von Variablen kann entfernt werden.<br>
          <ul>
            readings: Alle Messwerte werden gel&ouml;scht, neue Werte werden normal hinzugef&uuml;gt. Kann benutzt werden um alte Daten zu entfernen<br>
            register: Alle in FHEM aufgezeichneten Registerwerte werden entfernt. Dies hat KEINEN Einfluss auf Werte im Ger&auml;t.<br>
            msgEvents: Alle Nachrichtenz&auml;hler werden gel&ouml;scht. Ebenso wird der Befehlsspeicher zur&uuml;ckgesetzt. <br>
            rssi: gesammelte RSSI-Werte werden gel&ouml;scht.<br>
            attack: Eintr&auml;ge bez&uuml;glich einer Attack werden gel&ouml;scht.<br>
            all: alles oben genannte.<br>
          </ul>
        </li>
        <li><B>getConfig</B><a id="CUL_HM-set-getConfig"></a><br>
          Liest die Hauptkonfiguration eines HM_Ger&auml;tes aus. Angewendet auf einen Kanal
          erh&auml;lt man Pairing-Information, List0, List1 und List3 des ersten internen Peers.
          Außerdem erh&auml;lt man die Liste der Peers f&uuml;r den gegebenen Kanal. Wenn auf ein Ger&auml;t
          angewendet so bekommt man mit diesem Befehl die vorherigen Informationen f&uuml;r alle
          zugeordneten Kan&auml;le. Ausgeschlossen davon sind Konfigurationen zus&auml;tzlicher Peers.
          <br> Der Befehl ist eine Abk&uuml;rzung f&uuml;r eine Reihe anderer Befehle.
        </li>
        <li><B>getRegRaw [List0|List1|List2|List3|List4|List5|List6|List7]&lt;peerChannel&gt; </B><a id="CUL_HM-set-getRegRaw"></a><br>
          Auslesen der Rohdaten des Registersatzes. Eine Beschreibung der Register sprengt
          den Rahmen dieses Dokuments.<br>
          
          Die Register sind in sog. Listen strukturiert welche einen Satz Register enthalten.<br>
          
          List0: Ger&auml;teeinstellungen z.B: Einstellungen f&uuml;r CUL-Pairing Temperaturlimit eines Dimmers.<br>
          
          List1: Kanaleinstellungen z.B. ben&ouml;tigte Zeit um Rollo hoch und runter zu fahren.<br>
          
          List3: "link" Einstellungen - d.h. Einstellungen f&uuml;r Peer-Kanal. Das ist eine große Datenmenge!
          Steuert Aktionen bei Empfang eines Triggers vom Peer.<br>
          
          List4: Einstellungen f&uuml;r den Kanal (Taster) einer Fernbedienung.<br><br>
          
          &lt;PeerChannel&gt; verkn&uuml;pfte HMid+ch, z.B. 4 byte (8 stellige) Zahl wie
          '12345601'. Ist verpflichtend f&uuml;r List3 und List4 und kann ausgelassen werden
          f&uuml;r List0 und 1. <br>
          
          'all' kann verwendet werden um Daten von jedem mit einem Kanal verkn&uuml;pften Link zu bekommen. <br>
          
          'selfxx' wird verwendet um interne Kan&auml;le zu adressieren (verbunden mit den eingebauten Schaltern
          falls vorhanden). xx ist die Kanalnummer in dezimaler Notation.<br>
          
          Hinweis 1: Ausf&uuml;hrung ist abh&auml;ngig vom Entity. Wenn List1 f&uuml;r ein Ger&auml;t statt einem Kanal
          abgefragt wird gibt der Befehl List1 f&uuml;r alle zugeh&ouml;rigen Kan&auml;le aus.
          List3 mit 'peerChannel = all' gibt alle Verbindungen f&uuml;r alle Kan&auml;le eines Ger&auml;tes zur&uuml;ck.<br>
          
          Hinweis 2: f&uuml;r 'Sender' siehe auch <a href="#CUL_HM-set-remote">remote</a> <br>
          
          Hinweis 3: Das Abrufen von Informationen kann dauern - besonders f&uuml;r Ger&auml;te
          mit vielen Kan&auml;len und Verkn&uuml;pfungen. Es kann n&ouml;tig sein das Webinterface manuell neu zu laden
          um die Ergebnisse angezeigt zu bekommen.<br>
          
          Hinweis 4: Direkte Schalter eines HM-Ger&auml;ts sind standardm&auml;ßig ausgeblendet.
          Dennoch sind sie genauso als Verkn&uuml;pfungen implemetiert. Um Zugriff auf 'internal links'
          zu bekommen ist es notwendig folgendes zu erstellen:<br>
          'set &lt;name&gt; <a href="#CUL_HM-set-regSet">regSet</a> intKeyVisib visib'<br>
          oder<br>
          'set &lt;name&gt; <a href="#CUL_HM-set-regBulk">regBulk</a> RegL_0. 2:81'<br>
          Zur&uuml;cksetzen l&auml;sst es sich indem '81' mit '01' ersetzt wird.<br> example:<br>
          
          <ul><code>
            set mydimmer getRegRaw List1<br>
            set mydimmer getRegRaw List3 all <br>
          </code></ul>
          </li>
        <li><B>getSerial</B><a id="CUL_HM-set-getSerial"></a><br>
          Auslesen der Seriennummer eines ger&auml;ts und speichern in Attribut serialNr.
        </li>
        <li><B>inhibit [on|off]</B><br>
          Blockieren/Zulassen aller Kanal&auml;nderungen eines Aktors, d.h. Zustand des Aktors ist
          eingefroren bis 'inhibit' wieder deaktiviert wird. 'Inhibit' kann f&uuml;r jeden Aktorkanal
          ausgef&uuml;hrt werden aber nat&uuml;rlich nicht f&uuml;r Sensoren - w&uuml;rde auch keinen Sinn machen.<br>
          Damit ist es praktischerweise m&ouml;glich Nachrichten ebenso wie verkn&uuml;pfte Kanalaktionen
          tempor&auml;r zu unterdr&uuml;cken ohne sie l&ouml;schen zu m&uuml;ssen. <br>
          Beispiele:
          <ul><code>
            # Ausf&uuml;hrung blockieren<br>
            set keymatic inhibit on <br><br>
          </ul></code>
        </li>
        
        <li><B>pair</B><a id="CUL_HM-set-pair"></a><br>
          Verbinden eines Ger&auml;ts bekannter Seriennummer (z.b. nach einem Reset)
          mit einer FHEM-Zentrale. Diese Zentrale wird normalerweise durch CUL/CUNO,
          HMLAN,... hergestellt.
          Wenn verbunden melden Ger&auml;te ihren Status and FHEM.
          Wenn nicht verbunden wird das Ger&auml;t auf bestimmte Anfragen nicht reagieren
          und auch bestimmte Statusinformationen nicht melden. Pairing geschieht auf
          Ger&auml;teebene. Kan&auml;le k&ouml;nnen nicht unabh&auml;ngig von einem Ger&auml;t mit der Zentrale
          verbunden werden.
          Siehe auch <a href="#CUL_HM-set-getpair">getPair</a> und
          <a href="#CUL_HM-set-unpair">unpair</a>.<br>
          Nicht das Verbinden (mit einer Zentrale) mit verkn&uuml;pfen (Kanal zu Kanal) oder
          <a href="#CUL_HM-set-peerChan">peerChan</a> verwechseln.<br>
        </li>
        <li><B>peerBulk</B> &lt;peerch1,peerch2,...&gt; [set|unset]<a id="CUL_HM-set-peerBulk"></a><br>
          peerBulk f&uuml;gt Peer-Kan&auml;le zu einem Kanal hinzu. Alle Peers einer Liste werden
          dabei hinzugef&uuml;gt.<br>
          Peering setzt die Einstellungen einer Verkn&uuml;pfung auf Standardwerte. Da Peers nicht in Gruppen
          hinzugef&uuml;gt werden werden sie durch HM standardm&auml;ßig als'single' f&uuml;r dieses Ger&auml;t
          angelegt. <br>
          Eine ausgekl&uuml;geltere Funktion wird gegeben durch
          <a href="#CUL_HM-set-peerChan">peerChan</a>.<br>
          peerBulk l&ouml;scht keine vorhandenen Peers sondern bearbeitet nur die Peerliste.
          Andere bereits angelegt Peers werden nicht ver&auml;ndert.<br>
          peerBulk kann verwendet werden um Peers zu l&ouml;schen indem die <B>unset</B> Option
          mit Standardeinstellungen aufgerufen wird.<br>
          
          Verwendungszweck dieses Befehls ist haupts&auml;chlich das Wiederherstellen
          von Daten eines Ger&auml;ts.
          Empfehlenswert ist das anschließende Wiederherstellen der Registereinstellung
          mit <a href="#CUL_HM-set-regBulk">regBulk</a>. <br>
          Beispiel:<br>
          <ul><code>
            set myChannel peerBulk 12345601,<br>
            set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
            set myChannel peerBulk 12345601 unset # entferne Peer 123456 Kanal 01<br>
          </code></ul>
        </li>
        <a id="CUL_HM-set-regBulk"></a>
        <li><B>regBulk &lt;reg List&gt;.&lt;peer&gt; &lt;addr1:data1&gt; &lt;addr2:data2&gt;...</B><br>
          Dieser Befehl ersetzt das bisherige regRaw. Er erlaubt Register mit Rohdaten zu
          beschreiben. Hauptzweck ist das komplette Wiederherstellen eines zuvor gesicherten
          Registers. <br>
          Werte k&ouml;nnen mit <a href="#CUL_HM-set-getConfig">getConfig</a> ausgelesen werden. Die
          zur&uuml;ckgegebenen Werte k&ouml;nnen direkt f&uuml;r diesen Befehl verwendet werden.<br>
          &lt;reg List&gt; bezeichnet die Liste in die geschrieben werden soll. M&ouml;gliches Format
          '00', 'RegL_00', '01'...<br>
          &lt;peer&gt; ist eine optionale Angabe falls die Liste ein Peer ben&ouml;tigt.
          Der Peer kann als Kanalname oder als 4-Byte (8 chars) HM-Kanal ID angegeben
          werden.<br>
          &lt;addr1:data1&gt; ist die Liste der Register im Hex-Format.<br>
          Beispiel:<br>
          <ul><code>
            set myChannel regBulk RegL_00. 02:01 0A:17 0B:43 0C:BF 15:FF 00:00<br>
            RegL_03.FB_Btn_07
            01:00 02:00 03:00 04:32 05:64 06:00 07:FF 08:00 09:FF 0A:01 0B:44 0C:54 0D:93 0E:00 0F:00 11:C8 12:00 13:00 14:00 15:00 16:00 17:00 18:00 19:00 1A:00 1B:00 1C:00 1D:FF 1E:93 1F:00 81:00 82:00 83:00 84:32 85:64 86:00 87:FF 88:00 89:FF 8A:21 8B:44 8C:54 8D:93 8E:00 8F:00 91:C8 92:00 93:00 94:00 95:00 96:00 97:00 98:00 99:00 9A:00 9B:00 9C:00 9D:05 9E:93 9F:00 00:00<br>
            set myblind regBulk 01 0B:10<br>
            set myblind regBulk 01 0C:00<br>
            </code></ul>
          myblind setzt die maximale Zeit f&uuml;r das Hochfahren der Rollos auf 25,6 Sekunden
        </li>
        <li><B>regSet [prep|exec] &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><a id="CUL_HM-set-regSet"></a><br>
          F&uuml;r einige Hauptregister gibt es eine lesbarere Version die Registernamen &lt;regName&gt;
          und Wandlung der Werte enth&auml;lt. Nur ein Teil der Register wird davon unterst&uuml;tzt.<br>
          Der optionale Parameter [prep|exec] erlaubt das Packen von Nachrichten und verbessert damit
          deutlich die Daten&uuml;bertragung.
          Benutzung durch senden der Befehle mit Parameter "prep". Daten werden dann f&uuml;r das Senden gesammelt.
          Der letzte Befehl muss den Parameter "exec" habe um die Information zu &uuml;bertragen.<br>
          &lt;value&gt; enth&auml;lt die Daten in menschenlesbarer Form die in das Register geschrieben werden.<br>
          &lt;peerChannel&gt; wird ben&ouml;tigt falls das Register 'peerChan' basiert definiert wird.
          Kann ansonsten auf '0' gesetzt werden. Siehe <a
          href="#CUL_HM-set-getRegRaw">getRegRaw</a> f&uuml;r komplette Definition.<br>
          Unterst&uuml;tzte Register eines Ger&auml;ts k&ouml;nnen wie folgt bestimmt werden:<br>
          <ul><code>set regSet ? 0 0</code></ul>
            Eine verk&uuml;rzte Beschreibung der Register wird zur&uuml;ckgegeben mit:<br>
          <ul><code>set regSet &lt;regname&gt; ? 0</code></ul>
        </li>
        <li><B>reset</B><a id="CUL_HM-set-reset"></a><br>
          R&uuml;cksetzen des Ger&auml;ts auf Werkseinstellungen. Muss danach erneut verbunden werden um es
          mit FHEM zu nutzen.
        </li>
        <li><B>sign [on|off]</B><a id="CUL_HM-set-sign"></a><br>
          Ein- oder ausschalten der Signierung (auch "AES-Verschl&uuml;sselung" genannt, siehe <a
          href="#HMAES">note</a>). Achtung: Wird das Ger&auml;t &uuml;ber einen CUL eingebunden, ist schalten (oder
          deaktivieren der Signierung) nur m&ouml;glich, wenn das Perl-Modul Crypt::Rijndael installiert ist.
        </li>
        <li><B>statusRequest</B><a id="CUL_HM-set-statusRequest"></a><br>
          Aktualisieren des Ger&auml;testatus. F&uuml;r mehrkanalige Ger&auml;te sollte dies kanalbasiert
          erfolgen.
        </li>
        <li><B>unpair</B><a id="CUL_HM-set-unpair"></a><br>
          Aufheben des "Pairings", z.B. um das verbinden mit einem anderen Master zu erm&ouml;glichen.
          Siehe <a href="#CUL_HM-set-pair">pair</a> f&uuml;r eine Beschreibung.</li>
        <li><B>virtual &lt;Anzahl an Kn&ouml;pfen&gt;</B><a id="CUL_HM-set-virtual"></a><br>
          Konfiguriert eine vorhandene Schaltung als virtuelle Fernbedienung. Die Anzahl der anlegbaren
          Kn&ouml;pfe ist 1 - 255. Wird der Befehl f&uuml;r die selbe Instanz erneut aufgerufen werden Kn&ouml;pfe
          hinzugef&uuml;gt. <br>
          Beispiel f&uuml;r die Anwendung:
          <ul><code>
            define vRemote CUL_HM 100000 # die gew&auml;hlte HMid darf nicht in Benutzung sein<br>
            set vRemote virtual 20 # definiere eine Fernbedienung mit 20 Kn&ouml;pfen<br>
            set vRemote_Btn4 peerChan 0 &lt;actorchannel&gt; # verkn&uuml;pft Knopf 4 und 5 mit dem gew&auml;hlten Kanal<br>
            set vRemote_Btn4 press<br>
            set vRemote_Btn5 press long<br>
          </code></ul>
          siehe auch <a href="#CUL_HM-set-press">press</a>
        </li>
        <li><B>deviceRename &lt;newName&gt;</B><a id="CUL_HM-set-deviceRename"></a><br>
          benennt das Device und alle seine Kan&auml;le um.
        </li>

        <li><B>fwUpdate [onlyEnterBootLoader] &lt;filename&gt; [&lt;waitTime&gt;]</B><br>
          update Fw des Device. Der User muss das passende FW file bereitstellen.
          waitTime ist optional. Es ist die Wartezeit, um das Device manuell in den FW-update-mode
          zu versetzen.<br>
          "onlyEnterBootLoader" schickt das Device in den Booloader so dass es vom eq3 Firmware Update 
          Tool geflashed werden kann. Haupts&auml;chlich f&uuml;r Unterputz-Aktoren in Verbindung mit 
          FHEM Installationen die ausschliesslich HM-LANs nutzen interessant.
        </li>
        <li><B>assignIO &lt;IOname&gt; &lt;set|unset&gt;</B><a id="CUL_HM-set-assignIO"></a><br>
          IO-Ger&auml;t zur Liste der IO's hinzuf&uuml;gen oder aus dieser L&ouml;schen.
          &Auml;ndert das Attribut <i>IOList</i> entsprechend.
        </li>

      </ul>
      <br>

      <B>subType abh&auml;ngige Befehle:</B>
      <ul>
        <br>
        <li>switch
          <ul>
            <li><B>on</B> <a id="CUL_HM-set-on"> </a> - setzt Wert auf 100%</li>
            <li><B>off</B><a id="CUL_HM-set-off"></a> - setzt Wert auf 0%</li>
            <li><B>on-for-timer &lt;sec&gt;</B><a id="CUL_HM-set-onForTimer"></a> -
              Schaltet das Ger&auml;t f&uuml;r die gew&auml;hlte Zeit in Sekunden [0-85825945] an.<br> Hinweis:
              off-for-timer wie bei FS20 wird nicht unterst&uuml;tzt. Kann aber &uuml;ber Kanalregister
              programmiert werden.</li>
            <li><B>on-till &lt;time&gt;</B><a id="CUL_HM-set-onTill"></a> - einschalten bis zum angegebenen Zeitpunkt.<br>
              <ul><code>set &lt;name&gt; on-till 20:32:10<br></code></ul>
              Das momentane Maximum f&uuml;r eine Endzeit liegt bei 24 Stunden.<br>
            </li>
            <li><B>pressL &lt;peer&gt; [&lt;repCount&gt;] [&lt;repDelay&gt;] </B><a id="CUL_HM-set-pressL"></a><br>
                simuliert einen Tastendruck eines lokalen oder anderen peers.<br>
                <B>&lt;peer&gt;</B> peer auf den der Tastendruck bezogen wird. <br>
                <B>&lt;repCount&gt;</B> automatische Wiederholungen des long press. <br>
                <B>&lt;repDelay&gt;</B> timer zwischen den Wiederholungen. <br>
                <B>Beispiel:</B>
                <code> 
                   set actor pressL FB_Btn01 # trigger long peer FB button 01<br>
                   set actor pressL FB_chn-8 # trigger long peer FB button 08<br>
                   set actor pressL self01 # trigger short des internen peers 01<br>
                   set actor pressL fhem02 # trigger short des FHEM channel 2<br>
                </code>
            </li>
            <li><B>pressS &lt;peer&gt;</B><a id="CUL_HM-set-pressS"></a><br>
                simuliert einen kurzen Tastendruck entsprechend peerL
            </li>

            <li><B>eventL &lt;peer&gt; &lt;condition&gt; [&lt;repCount&gt;] [&lt;repDelay&gt;] </B><a id="CUL_HM-set-eventL"></a><br>
                simuliert einen Event mit zus&auml;tzlichem Wert.<br>
                <B>&lt;peer&gt;</B> peer auf den der Tastendruck bezogen wird.<br>              
                <B>&lt;codition&gt;</B>wert des Events, 0..255 <br>              
                <B>Beispiel:</B>
                <code> 
                   set actor eventL md 30 # trigger vom Bewegungsmelder mit Wert 30<br>
                </code>
            </li>
            <li><B>eventS &lt;peer&gt; &lt;condition&gt; </B><a id="CUL_HM-set-eventS"></a><br>
                simuliert einen kurzen Event eines Peers des actors. Typisch senden Sensoren nur short Events.
            </li>
          <br>
          </ul>
        </li>
        <li>dimmer, blindActuator<br>
          Dimmer k&ouml;nnen virtuelle Kan&auml;le unterst&uuml;tzen. Diese werden automatisch angelegt falls vorhanden.
          Normalerweise gibt es 2 virtuelle Kan&auml;le zus&auml;tzlich zum prim&auml;ren Kanal. Virtuelle Dimmerkan&auml;le sind
          standardm&auml;ßig deaktiviert, k&ouml;nnen aber parallel zum ersten Kanal benutzt werden um das Licht zu steuern. <br>
          Die virtuellen Kan&auml;le haben Standardnamen SW&lt;channel&gt;_V&lt;nr&gt; z.B. Dimmer_SW1_V1 and Dimmer_SW1_V2.<br>
          Virtuelle Dimmerkan&auml;le unterscheiden sich komplett von virtuellen Kn&ouml;pfen und Aktoren in FHEM, sind aber
          Teil des HM-Ger&auml;ts. Dokumentation und M&ouml;glichkeiten w&uuml;rde hier aber zu weit f&uuml;hren.<br>
          <ul>
            <li><B>0 - 100 [on-time] [ramp-time]</B><br>
              Setzt den Aktor auf den gegeben Wert (In Prozent)
              mit einer Aufl&ouml;sung von 0.5.<br>
              Bei Dimmern ist optional die Angabe von "on-time" und "ramp-time" m&ouml;glich, beide in Sekunden mit 0.1s Abstufung.<br>
              "On-time" verh&auml;lt sich analog dem "on-for-timer".<br>
              "Ramp-time" betr&auml;gt standardm&auml;ßig 2.5s, 0 bedeutet umgehend.<br>
            </li>
            <li><B><a href="#CUL_HM-set-on">on</a></B></li>
            <li><B><a href="#CUL_HM-set-off">off</a></B></li>
            <li><B><a href="#CUL_HM-set-press">press &lt;[short|long]&gt;&lt;[on|off]&gt;</a></B></li>
            <li><B><a href="#CUL_HM-set-toggle">toggle</a></B></li>
            <li><B>toggleDir</B><a id="CUL_HM-set-toggleDir"></a> - toggelt die fahrtrichtung des Rollo-Aktors.
              Es wird umgeschaltet zwischen auf/stop/ab/stop</li>
            <li><B><a href="#CUL_HM-set-onForTimer">on-for-timer &lt;sec&gt;</a></B> - Nur Dimmer! <br></li>
            <li><B><a href="#CUL_HM-set-onTill">on-till &lt;time&gt;</a></B> - Nur Dimmer! <br></li>
            <li><B>stop</B> - Stopt Bewegung (Rollo) oder Dimmerrampe</li>
            <li><B>old</B> - schaltet auf den vorigen Wert zur&uuml;ck. Nur dimmer. </li>
            <li><B>pct &lt;level&gt [&lt;ontime&gt] [&lt;ramptime&gt]</B> - setzt Aktor auf gew&uuml;nschten <B>absolut Wert</B>.<br>
              Optional k&ouml;nnen f&uuml;r Dimmer "ontime" und "ramptime" angegeben werden.<br>
              "Ontime" kann dabei in Sekunden angegeben werden. Kann auch als Endzeit angegeben werden im Format hh:mm:ss
            </li>
            <li><B>up [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> Einen Schritt hochdimmen.</li>
            <li><B>down [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> Einen Schritt runterdimmen.<br>
              "changeValue" ist optional und gibt den zu &auml;ndernden Wert in Prozent an. M&ouml;gliche Abstufung dabei ist 0.5%, Standard ist 10%. <br>
              "ontime" ist optional und gibt an wielange der Wert gehalten werden soll. '0' bedeutet endlos und ist Standard.<br>
              "ramptime" ist optional und definiert die Zeit bis eine &auml;nderung den neuen Wert erreicht. Hat nur f&uuml;r Dimmer Bedeutung.
            <br></li>
          </ul>
          <br>
        </li>
        <li>remotes, pushButton<a id="CUL_HM-set-remote"></a><br>
          Diese Ger&auml;teart reagiert nicht auf Anfragen, außer sie befinden sich im Lernmodus. FHEM reagiert darauf
          indem alle Anfragen gesammelt werden bis der Lernmodus detektiert wird. Manuelles Eingreifen durch
          den Benutzer ist dazu n&ouml;tig. Ob Befehle auf Ausf&uuml;hrung warten kann auf Ger&auml;teebene mit dem Parameter
          'protCmdPend' abgefragt werden.
          <ul>
          <li><B>trgEventS [all|&lt;peer&gt;] &lt;condition&gt;</B><a id="CUL_HM-set-trgEventS"></a><br>
               Initiiert ein eventS fuer die peer entity. Wenn <B>all</B> ausgew&auml;hlt ist wird das Kommando bei jedem der Peers ausgef&uuml;hrt. Siehe auch <a href="#CUL_HM-set-eventS">eventS</a><br>
               <B>&lt;condition&gt;</B>: Ist der Wert welcher mit dem Event versendet wird. Bei einem Bewegungsmelder ist das bspw. die Helligkeit.  
          </li>
          <li><B>trgEventL [all|&lt;peer&gt;] &lt;condition&gt;</B><a id="CUL_HM-set-trgEventL"></a><br>
               Initiiert ein eventL fuer die peer entity. Wenn <B>all</B> ausgew&auml;hlt ist wird das Kommando bei jedem der Peers ausgef&uuml;hrt. Siehe auch <a href="#CUL_HM-set-eventL">eventL</a><br>
               <B>&lt;condition&gt;</B>: is the condition being transmitted with the event. E.g. the brightness in case of a motion detector. 
          </li>
          <li><B>trgPressS [all|&lt;peer&gt;] </B><a id="CUL_HM-set-trgPressS"></a><br>
               Initiiert ein pressS fuer die peer entity. Wenn <B>all</B> ausgew&auml;hlt ist wird das Kommando bei jedem der Peers ausgef&uuml;hrt. Siehe auch <a href="#CUL_HM-set-pressS">pressS</a><br>
          </li>
          <li><B>trgPressL [all|&lt;peer&gt;] </B><a id="CUL_HM-set-trgPressL"></a><br>
               Initiiert ein pressL fuer die peer entity. Wenn <B>all</B> ausgew&auml;hlt ist wird das Kommando bei jedem der Peers ausgef&uuml;hrt. Siehe auch <a href="#CUL_HM-set-pressL">pressL</a><br>
          </li>
          <li><B>peerSmart [&lt;peer&gt;] </B><a id="CUL_HM-set-peerSmart"></a><br>
               Das Kommando ist aehnlich <B><a href="#CUL_HM-set-peerChan">peerChan</a></B> mit reduzierten Optionen.<br>
               peerSmart peert immer single mode (siehe peerChan). Die Funktionalitaet &uuml;ber das  
               setzen der Register erstellt (kein grosser Unterschied zu peerChan).<br>
               Smartes Registersetzen unterst&uuml;tzt bspw hmTemplate.<br>
          </li>
          <li><B>peerChan &lt;btn_no&gt; &lt;actChan&gt; [single|<u>dual</u>|reverse]
              [<u>set</u>|unset] [<u>both</u>|actor|remote]</B><a id="CUL_HM-set-peerChan"></a><br>
              "peerChan" richtet eine Verbindung zwischen Sender-<B>Kanal</B> und
              Aktor-<B>Kanal</B> ein, bei HM "link" genannt. "Peering" darf dabei nicht
              mit "pairing" verwechselt werden.<br>
              <B>Pairing</B> bezeichnet das Zuordnen eines <B>Ger&auml;ts</B> zu einer Zentrale.<br>
              <B>Peering</B> bezeichnet das faktische Verbinden von <B>Kan&auml;len</B>.<br>
              Peering erlaubt die direkte Interaktion zwischen Sender und Aktor ohne den Einsatz einer CCU<br>
              Peering eines Senderkanals veranlaßt den Sender nach dem Senden eines Triggers auf die
              Best&auml;tigung eines - jeden - Peers zu warten. Positives Feedback (z.B. gr&uuml;ne LED)
              gibt es dabei nur wenn alle Peers den Befehl best&auml;tigt haben.<br>
              Peering eines Aktorkanals richtet dabei einen Satz von Parametern ein welche die auszuf&uuml;hrenden Aktionen
              definieren wenn ein Trigger dieses Peers empfangen wird. Dies bedeutet: <br>
              - nur Trigger von Peers werden ausgef&uuml;hrt<br>
              - die auszuf&uuml;hrende Aktion muss f&uuml;r den zugeh&ouml;rigen Trigger eines Peers definiert werden<br>
              Ein Aktorkanal richtet dabei eine Standardaktion beim Peering ein - diese h&auml;ngt vom Aktor ab.
              Sie kann ebenfalls davon abh&auml;ngen ob ein oder zwei Tasten <B>ein einem Befehl</B> gepeert werden.
              Peert man einen Schalter mit 2 Tasten kann eine Taste f&uuml;r 'on' und eine andere f&uuml;r 'off' angelegt werden.
              Wenn nur eine Taste definiert wird ist die Funktion wahrscheinlich 'toggle'.<br>
              Die Funktion kann durch programmieren des Register (vom Aktor abh&auml;ngig) ge&auml;ndert werden.<br>
              
              Auch wenn der Befehl von einer Fernbedienung oder einem Taster kommt hat er direkten Effekt auf
              den Aktor. Das Peering beider Seiten ist quasi unabh&auml;ngig und hat unterschiedlich Einfluss auf
              Sender und Empf&auml;nger.<br>
              Peering eines Aktorkanals mit mehreren Senderkan&auml;len ist ebenso m&ouml;glich wie das eines Senderkanals
              mit mehreren Empf&auml;ngerkan&auml;len.<br>
              
              &lt;actChan&gt; ist der zu verkn&uuml;pfende Aktorkanal.<br>
              
              &lt;btn_no&gt; ist der zu verkn&uuml;pfende Senderkanal (Knopf). Wird
              'single' gew&auml;hlt werden die Tasten von 1 an gez&auml;hlt. F&uuml;r 'dual' ist btn_no
              die Nummer des zu verwendenden Tasterpaares. Z.B. ist '3' iim Dualmodus das
              dritte Tasterpaar welches mit Tasten 5 und 6 im Singlemodus &uuml;bereinstimmt.<br>
              
              Wird der Befehl auf einen Kanal angewendet wird btn_no igroriert.
              Muss gesetzt sein, sollte dabei 0 sein.<br>
              
              [single|dual]: Dieser Modus bewirkt das Standardverhalten des Aktors bei Benutzung eines Tasters. Ein Dimmer
              kann z.B. an einen einzelnen oder ein Paar von Tastern angelernt werden. <br>
              Standardeinstellung ist "dual".<br>
              
              'dual' (default) Schalter verkn&uuml;pft zwei Taster mit einem Aktor. Bei einem Dimmer
              bedeutet das ein Taster f&uuml;r hoch- und einer f&uuml;r runterdimmen. <br>
              
              'reverse' identisch zu dual - nur die Reihenfolge der Buttons ist gedreht<br>
              
              'single' benutzt nur einen Taster des Senders. Ist z.B. n&uuml;tzlich f&uuml;r einen einfachen Schalter
              der nur zwischen an/aus toggled. Aber auch ein Dimmer kann an nur einen Taster angelernt werden.<br>
              
              [set|unset]: W&auml;hlt aus ob Peer hinzugef&uuml;gt oder entfernt werden soll.<br>
              Hinzuf&uuml;gen ist Standard.<br>
              'set' stellt Peers f&uuml;r einen Kanal ein.<br>
              'unset' entfernt Peer f&uuml;r einen Kanal.<br>
              
              [actor|remote|both] beschr&auml;nkt die Ausf&uuml;hrung auf Aktor oder Fernbedienung.
              Das erm&ouml;glicht dem Benutzer das entfernen des Peers vom Fernbedienungskanal ohne
              die Einstellungen am Aktor zu entfernen.<br>
              Standardm&auml;ßig gew&auml;hlt ist "both" f&uuml;r beides.<br>
              
              Example:
              <ul><code>
                set myRemote peerChan 2 mySwActChn single set #Peer zweiten Knopf mit Aktorkanal<br>
                set myRmtBtn peerChan 0 mySwActChn single set #myRmtBtn ist ein Knopf der Fernbedienung. '0' wird hier nicht verarbeitet<br>
                set myRemote peerChan 2 mySwActChn dual set #Verkn&uuml;pfe Kn&ouml;pfe 3 und 4<br>
                set myRemote peerChan 3 mySwActChn dual unset #Entferne Peering f&uuml;r Kn&ouml;pfe 5 und 6<br>
                set myRemote peerChan 3 mySwActChn dual unset aktor #Entferne Peering f&uuml;r Kn&ouml;pfe 5 und 6 nur im Aktor<br>
                set myRemote peerChan 3 mySwActChn dual set remote #Verkn&uuml;pfe Kn&ouml;pfe 5 und 6 nur mit Fernbedienung. Linkeinstellungen mySwActChn werden beibehalten.<br>
              </code></ul>
            </li>
          </ul>
        
        </li>
        <li>virtual<a id="CUL_HM-set-virtual"></a><br>
          <ul>
            <li><B><a href="#CUL_HM-set-peerChan">peerChan</a></B> siehe remote</li>
            <li><a id="CUL_HM-set-press"></a><B>press [long|short] [&lt;peer&gt;] [&lt;repCount&gt;] [&lt;repDelay&gt;]</B>
              <ul>
                  Simuliert den Tastendruck am Aktor eines gepeerted Sensors
                 <li>[long|short] soll ein langer oder kurzer Taastendrucl simuliert werden? Default ist kurz. </li>
                 <li>[&lt;peer&gt;] legt fest, wessen peer's trigger simuliert werden soll.Default ist self(channelNo).</li>
                 <li>[&lt;repCount&gt;] nur gueltig fuer long. wie viele messages sollen gesendet werden? (Laenge des Button press). Default ist 1.</li>
                 <li>[&lt;repDelay&gt;] nur gueltig fuer long. definiert die Zeit zwischen den einzelnen Messages. </li>
              </ul>  
              </li>
            <li><a id="CUL_HM-set-virtTemp"></a><B>virtTemp &lt;[off -10..50]&gt;</B>
              Simuliert ein Thermostat. Wenn mit einem Ger&auml;t gepeert wird periodisch eine Temperatur gesendet,
              solange bis "off" gew&auml;hlt wird. Siehe auch <a href="#CUL_HM-set-virtHum">virtHum</a><br>
            </li>
            <li><a id="CUL_HM-set-virtHum"></a><B>virtHum &lt;[off -10..50]&gt;</B>
              Simuliert den Feuchtigkeitswert eines Thermostats. Wenn mit einem Ger&auml;t verkn&uuml;pft werden periodisch
              Luftfeuchtigkeit undTemperatur gesendet, solange bis "off" gew&auml;hlt wird. Siehe auch <a href="#CUL_HM-set-virtTemp">virtTemp</a><br>
            </li>
            <li><B>valvePos &lt;[off 0..100]&gt;<a id="CUL_HM-set-valvePos"></a></B>
              steuert einen Ventilantrieb<br>
            </li>
          </ul>
        </li>
        <li>smokeDetector<br>
          Hinweis: All diese Befehle funktionieren momentan nur wenn mehr als ein Rauchmelder
          vorhanden ist, und diese gepeert wurden um eine Gruppe zu bilden. Um die Befehle abzusetzen
          muss der Master dieser gruppe verwendet werden, und momentan muss man raten welcher der Master ist.<br>
          smokeDetector kann folgendermaßen in Gruppen eingeteilt werden:
          <a href="#CUL_HM-set-peerChan">peerChan</a>. Alle Mitglieder m&uuml;ssen mit dem Master verkn&uuml;pft werden. Auch der
          Master muss mit peerChan zur Gruppe zugef&uuml;gt werden - z.B. mit sich selbst verkn&uuml;pft! Dadurch hat man volle
          Kontrolle &uuml;ber die Gruppe und muss nicht raten.<br>
          <ul>
            <li><B>teamCall</B> - f&uuml;hrt einen Netzwerktest unter allen Gruppenmitgliedern aus</li>
            <li><B>teamCallBat</B> - Simuliert einen low-battery alarm</li>
            <li><B>alarmOn</B> - l&ouml;st einen Alarm aus</li>
            <li><B>alarmOff</B> - schaltet den Alarm aus</li>
          </ul>
        </li>
        <li>4Dis (HM-PB-4DIS-WM|HM-PB-4DIS-WM|HM-RC-DIS-H-X-EU|ROTO_ZEL-STG-RM-DWT-10)
          <ul>
            <li><B>text &lt;btn_no&gt; [on|off] &lt;text1&gt; &lt;text2&gt;</B><br>
              Zeigt Text auf dem Display eines Ger&auml;ts an. F&uuml;r diesen Zweck muss zuerst ein set-Befehl
              (oder eine Anzahl davon) abgegeben werden, dann k&ouml;nnen im "teach-in" Men&uuml; des 4Dis mit
              "Central" Daten &uuml;bertragen werden.<br>
              Falls auf einen Kanal angewendet d&uuml;rfen btn_no und on|off nicht verwendet werden, nur
              reiner Text.<br>
              \_ wird durch ein Leerzeichen ersetzt.<br>
              Beispiel:
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
          <br>
        </li>
        <li>Climate-Control (HM-CC-TC)
          <ul>
            <li><B>desired-temp &lt;temp&gt;</B><br>
              Setzt verschiedene Temperaturen. &lt;temp&gt; muss zwischen 6°C und 30°C liegen, die Aufl&ouml;sung betr&auml;gt 0.5°C.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
              Gibt eine Liste mit Temperaturintervallen an. Bis zu 24 Intervall k&ouml;nnen pro Wochentag definiert werden, die
              Aufl&ouml;sung dabei sind 10 Minuten. Die letzte Zeitangabe muss 24:00 Uhr sein.<br>
              Beispiel: bis 6:00 soll die Temperatur 19°C sein, dann bis 23:00 Uhr 22.5°C, anschließend
              werden bis Mitternacht 19°C gew&uuml;nscht.<br>
              <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
            <li><B>partyMode &lt;HH:MM&gt;&lt;durationDays&gt;</B><br>
              setzt die Steuerung f&uuml;r die angegebene Zeit in den Partymodus. Dazu ist die Endzeit sowie <b>Anzahl an Tagen</b>
              die er dauern soll anzugeben. Falls er am n&auml;chsten Tag enden soll ist '1'
              anzugeben<br></li>
            <li><B>sysTime</B><br>
              setzt Zeit des Klimakanals auf die Systemzeit</li>
          </ul><br>
        </li>
        <li>Climate-Control (HM-CC-RT-DN|HM-CC-RT-DN-BoM)
          <ul>
            <li><B>controlMode &lt;auto|boost|day|night&gt;</B><br></li>
            <li><B>controlManu &lt;temp&gt;</B><br></li>
            <li><B>controlParty &lt;temp&gt;&lt;startDate&gt;&lt;startTime&gt;&lt;endDate&gt;&lt;endTime&gt;</B><br>
              setzt die Steuerung in den Partymodus, definiert Temperatur und Zeitrahmen.<br>
              Beispiel:<br>
              <code>set controlParty 15 03-8-13 20:30 5-8-13 11:30</code></li>
            <li><B>sysTime</B><br>
              setzt Zeit des Klimakanals auf die Systemzeit</li>
            <li><B>desired-temp &lt;temp&gt;</B><br>
              Setzt verschiedene Temperaturen. &lt;temp&gt; muss zwischen 6°C und 30°C liegen, die Aufl&ouml;sung betr&auml;gt 0.5°C.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
              Gibt eine Liste mit Temperaturintervallen an. Bis zu 24 Intervall k&ouml;nnen pro Wochentag definiert werden, die
              Aufl&ouml;sung dabei sind 10 Minuten. Die letzte Zeitangabe muss immer 24:00 Uhr sein.<br>
              Der optionale Parameter [prep|exec] erlaubt das packen der Nachrichten und verbessert damit deutlich
              die Daten&uuml;bertragung. Besonders n&uuml;tzlich wenn das Ger&auml;t im "Wakeup"-modus betrieben wird.
              Benutzung durch senden der Befehle mit Parameter "prep". Daten werden dann f&uuml;r das Senden gesammelt.
              Der letzte Befehl muss den Parameter "exec" habe um die Information zu &uuml;bertragen.<br>
              Beispiel: bis 6:00 soll die Temperatur 19°C sein, dann bis 23:00 Uhr 22.5°C, anschließend
              werden bis Mitternacht 19°C gew&uuml;nscht.<br>
              <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
              <br>
              <code> set th tempListSat prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListSun prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListMon prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListTue exec 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
            <li><B>tempListTmpl   =>"[verify|restore] [[&lt;file&gt;:]templateName] ...</B><br>
              Die Temperaturlisten f&uuml;r ein oder mehrere Devices k&ouml;nnen in einem File hinterlegt 
              werden. Es wird ein template f&uuml;r eine Woche hinterlegt. Der User kann dieses
              template in ein Device schreiben lassen (restore). Er kann auch pr&uuml;fen, ob das Device korrekt
              nach dieser Templist programmiert ist (verify). 
              Default Opeartion ist verify.<br>
              Default File ist tempList.cfg.<br>
              Default templateName ist der name der Entity<br>
              Default f&uuml;r file und templateName kann mit dem Attribut <B>tempListTmpl</B> gesetzt werden.<br>
              Beispiel f&uuml;r ein templist File. room1 und room2 sind die Namen 2er Tempaltes:<br>
              <code>entities:room1
                 tempListSat>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              entities:room2
                 tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              </code>
              Specials:<br>
              <li>none: das Template wird ignoriert</li>
              <li>defaultWeekplan: Es wird als Default jeden Tag 18.0 Grad eingestellt. 
                  Sinnvoll nutzbar wenn man einen TC als Kontroller nutzt. Der Wochenplan des TC wird dann imlizit genutzt</li>
            </li>
            <li><B>tempTmplSet   =>"[[ &lt;file&gt; :]templateName]</B><br>
              Setzt das Attribut und sendet die &Auml;nderungen an das Device.
            </li>
            <li><B>tplDel   =>" &lt;template&gt; </B><br>
              L&ouml;scht eine Template Eintrag dieser entity.
            </li>
            <li><B>tplSet_&lt;peer&gt;   =>" &lt;template&gt; </B><br>
              setzt ein Template f&uuml;r einen Peer der Entity. M&ouml;gliche Parameter des Templates werde auf den aktuellen Wert der Register gesetzt. Die Parameter k&ouml;nnen danach mit dem Kommando tplPara* geaendert werden.<br>
              Das Kommando steht nur zu Verf&uuml;gung wenn HMinfo definiert ist und ein passendes Template erstellt ist.<br>
              Sollte das Template dediziert einem langen (long) oder kurzen (short) Trigger zugeordnet werden wird je ein Kommando zu Verf&uuml;gung gestellt - siehe long oder short am Ende des Kommandos.
            </li>
            <li><B>tplParaxxx_&lt;peer&gt;_&lt;tpl&gt;_&lt;param&gt;   =>" &lt;template&gt; </B><br>
              Ein Parameter eines zugewiesenen Templates kann geaendert werden. Das Kommando bezieht sich auf genau einen Parameter eines Templates. 
            </li>

          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-LED16)
          <ul>
            <li><B>led [off|red|green|yellow]</B><br>
              schaltet die LED des Kanals auf die gew&uuml;nschte Farbe. Wird der Befehl auf ein Ger&auml;t angewandt so
              werden alle LEDs auf diese Farbe gesetzt.<br>
              Experten k&ouml;nnen die LEDs separat durch eine 8-stellige Hex-Zahl ansteuern.<br></li>
            <li><B>ilum &lt;Helligkeit&gt;&lt;Dauer&gt; </B><br>
              &lt;Helligkeit&gt; [0-15] der Beleuchtung.<br>
              &lt;Dauer&gt; [0-127] in Sekunden, 0 bedeutet dauernd an.<br></li>
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-CFM-PL)
          <ul>
            <li><B>led &lt;color&gt;[,&lt;color&gt;..] [&lt;repeat&gt..]</B><br>
              M&ouml;gliche Farben sind [redL|greenL|yellowL|redS|greenS|yellowS|pause]. Eine Folge von Farben
              kann durch trennen der Farbeintr&auml;ge mit ',' eingestellt werden.
              Leerzeichen d&uuml;rfen in der Liste nicht benutzt werden. 'S' bezeichnet kurze und
              'L' lange Beleuchtungsdauer. <br>
              <b>repeat</b> definiert wie oft die Sequenz ausgef&uuml;hrt werden soll. Standard ist 1.<br>
            </li>
             <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt;..] [&lt;repeat&gt;] [&lt;volume&gt;]</B><br>
              Spielt eine Reihe von T&ouml;nen. Die Liste muss mit ',' getrennt werden. Leerzeichen
              d&uuml;rfen in der Liste nicht benutzt werden.<br>
              <b>replay</b> kann verwendet werden um den zuletzt gespielten Klang zu wiederholen.<br>
              <b>repeat</b> definiert wie oft die Sequenz ausgef&uuml;hrt werden soll. Standard ist 1.<br>
          <b>volume</b> kann im Bereich 0..10 liegen. 0 stoppt jeden aktuell gespielten Sound. Standard ist 10 (100%.<br>
              Beispiel:
              <ul><code>
                set cfm_Mp3 playTone 3 # MP3 Titel 3 einmal<br>
                set cfm_Mp3 playTone 3 3 # MP3 Titel 3 dreimal<br>
    set cfm_Mp3 playTone 3 1 5 # MP3 Titel 3 mit halber Lautst&auml;rke<br>
                set cfm_Mp3 playTone 3,6,8,3,4 # MP3 Titelfolge 3,6,8,3,4 einmal<br>
                set cfm_Mp3 playTone 3,6,8,3,4 255# MP3 Titelfolge 3,6,8,3,4 255 mal<br>
                set cfm_Mp3 playTone replay # Wiederhole letzte Sequenz<br>
                <br>
                set cfm_Led led redL 4 # rote LED dreimal lang blinken<br>
                set cfm_Led led redS,redS,redS,redL,redL,redL,redS,redS,redS 255 # SOS 255 mal<br>
              </ul></code>
              
            </li>
          </ul><br>
        </li>
        <li>HM-RC-19xxx
          <ul>
            <li><B>alarm &lt;count&gt;</B><br>
              sendet eine Alarmnachricht an die Steuerung<br></li>
            <li><B>service &lt;count&gt;</B><br>
              sendet eine Servicenachricht an die Steuerung<br></li>
            <li><B>symbol &lt;symbol&gt; [set|unset]</B><br>
              aktiviert ein verf&uuml;gbares Symbol auf der Steuerung<br></li>
            <li><B>beep [off|1|2|3]</B><br>
              aktiviert T&ouml;ne<br></li>
            <li><B>backlight [off|on|slow|fast]</B><br>
              aktiviert Hintergrundbeleuchtung<br></li>
            <li><B>display &lt;text&gt; comma unit tone backlight &lt;symbol(s)&gt;
              </B><br>
              Steuert das Display der Steuerung<br>
              &lt;text&gt; : bis zu 5 Zeichen <br>
              comma : 'comma' aktiviert das Komma, 'no' l&auml;ßt es aus <br>
              [unit] : setzt Einheitensymbole.
              [off|Proz|Watt|x3|C|x5|x6|x7|F|x9|x10|x11|x12|x13|x14|x15]. Momentan sind
              x3..x15 nicht getestet. <br>
              tone : aktiviert einen von 3 T&ouml;nen [off|1|2|3]<br>
              backlight: l&auml;ßt die Hintergrundbeleuchtung aufblinken [off|on|slow|fast]<br>
              &lt;symbol(s)&gt; aktiviert die Anzeige von Symbolen. Mehrere Symbole
              k&ouml;nnen zu selben Zeit aktiv sein, Verkn&uuml;pfung erfolgt komma-getrennt. Dabei keine
              Leerzeichen verwenden. M&ouml;gliche Symbole:
              [bulb|switch|window|door|blind|scene|phone|bell|clock|arrowUp|arrowDown]<br><br>
              
              Beispiel:
              <ul><code>
                # "Hello" auf dem Display, Symbol bulb an, Hintergrundbeleuchtung, Ton ausgeben<br>
                set FB1 display Hello no off 1 on bulb<br>
                # "1234,5" anzeigen mit Einheit 'W'. Symbole scene,phone,bell und
                # clock sind aktiv. Hintergrundbeleuchtung blinikt schnell, Ausgabe von Ton 2<br>
                set FB1 display 12345 comma Watt 2 fast scene,phone,bell,clock
              </ul></code>
            </li>
          </ul><br>
        </li>
        <li>HM-DIS-WM55
          <ul>
            <li><B>displayWM help </B><br>
               <B>displayWM [long|short] &lt;text1&gt; &lt;color1&gt; &lt;icon1&gt; ... &lt;text6&gt; &lt;color6&gt; &lt;icon6&gt;</B><br>
               <B>displayWM [long|short] &lt;lineX&gt; &lt;text&gt; &lt;color&gt; &lt;icon&gt;</B><br>
               es k&ouml;nnen bis zu 6 Zeilen programmiert werden.<br>
               <B>lineX</B> legt die zu &auml;ndernde Zeilennummer fest. Es k&ouml;nnen die 3 Parameter der Zeile ge&auml;ndert werden.<br>
               <B>textNo</B> ist der anzuzeigende Text. Der Inhalt des Texts wird in den Buttonds definiert. 
               txt&lt;BtnNo&gt;_&lt;lineNo&gt; referenziert den Button und dessn jeweiligen Zeile. 
               Alternativ kann ein bis zu 12 Zeichen langer Freitext angegeben werden<br>
               <B>color</B> kann sein white, red, orange, yellow, green, blue<br>
               <B>icon</B> kann sein off, on, open, closed, error, ok, noIcon<br>
            
               Example:
                 <ul><code>
                 set disp01 displayWM short txt02_2 green noIcon txt10_1 red error txt05_2 yellow closed txt02_2 orange open <br>
                 set disp01 displayWM long line3 txt02_2 green noIcon<br>
                 set disp01 displayWM long line2 nc yellow noIcon<br>
                 set disp01 displayWM long line6 txt02_2<br>
                 set disp01 displayWM long line1 nc nc closed<br>
                 </ul></code>
               </li>
          </ul><br>
        </li>
        <li>HM-DIS-EP-WM55
          <ul>
            <li><B>displayEP help </B><br>
              <B>displayEP &lt;text1,icon1:text2,icon2:text3,icon3&gt; &lt;sound&gt; &lt;repetition&gt; &lt;pause&gt; &lt;signal&gt;</B><br>
              bis zu 3 Zeilen werden adressiert.<br>
              Wenn help eingegeben wird wird eine <i><B>hilfe</B></i> zum Kommando ausgegeben. Optionen der Parameter werden ausgegeben.<br>
              <B>textx</B> 12 char text f&uuml;r die Zeile. 
                Wenn leer wird der Wert gem&auml;ß Reading genutzt. Typisch bedeuted es, dass keine &Auml;nderung stattfindet.
                text0-9 zeigt den vordefinierten Wert der Kan&auml;le 4 bis 8 an.
                0xHH erlaubt die anzeige eines hex Zeichens.<br>
              <B>iconx</B> Icon der Zeile. 
                Typisch bedeuted es, dass keine &Auml;nderung stattfindet.<br>
              <B>sound</B> sound zum Abspielen.<br>
              <B>repetition</B> 0..15 <br>
              <B>pause</B> 1..160<br>
              <B>signal</B> Signalfarbe zum Anzeigen<br>
              <br>
              <B>Note: param reWriteDisplayxx</B> <br>
              <li>
                Beim Druck einer Taste ueberschreibt das Geraet diemittleren 3 Zeilen. Wenn da Attribut <br>
                attr chan param reWriteDisplayxx<br>
                gesetzt ist werden die 3 Zeilen nach xx Sekunden auf den Orginalwert zur&uuml;ck geschrieben.<br>
              </li>
              
            </li>
          </ul><br>
        </li>
        <li>keyMatic<br><br>
          <ul>Keymatic verwendet eine AES-signierte Kommunikation. Die Steuerung von KeyMatic
            ist mit HMLAN und mit CUL m&ouml;glich.
            Um die Keymatic mit einem CUL zu steuern, muss das Perl-Modul Crypt::Rijndael
            installiert sein.</ul><br>
          <ul>
            <li><B>lock</B><br>
              Schließbolzen f&auml;hrt in Zu-Position<br></li>
            <li><B>unlock [sec]</B><br>
              Schließbolzen f&auml;hrt in Auf-Position.<br>
              [sec]: Stellt die Verz&ouml;gerung ein nach der sich das Schloss automatisch wieder verschließt.<br>
              0 - 65535 Sekunden</li>
            <li><B>open [sec]</B><br>
              Entriegelt die T&uuml;r sodass diese ge&ouml;ffnet werden kann.<br>
              [sec]: Stellt die Verz&ouml;gerung ein nach der sich das Schloss automatisch wieder
              verschließt.<br>0 - 65535 Sekunden</li>
          </ul>
        </li>
        <li>winMatic <br><br>
          <ul>winMatic arbeitet mit 2 Kan&auml;len, einem f&uuml;r die Fenstersteuerung und einem f&uuml;r den Akku.</ul><br>
          <ul>
            <li><B>level &lt;level&gt; &lt;relockDelay&gt; &lt;speed&gt;</B><br>
              stellt den Wert ein. <br>
              &lt;level&gt;: Bereich ist 0% bis 100%<br>
              &lt;relockDelay&gt;: Spanne reicht von 0 bis 65535 Sekunden. 'ignore' kann verwendet werden um den Wert zu ignorieren.<br>
              &lt;speed&gt;: Bereich ist 0% bis 100%<br>
            </li>
            <li><B>stop</B><br>
              stopt die Bewegung<br>
            </li>
          </ul>
        </li>
        <li>CCU_FHEM<br>
          <ul>
          <li>defIgnUnknown<br>
            Definieren die unbekannten Devices und setze das Attribut ignore. 
            Ddann loesche die Readings. <br>
          </li>
          </ul>
        </li>
        <li>HM-SYS-SRP-PL<br>
          legt Eintr&auml;ge f&uuml;r den Repeater an. Bis zu 36 Eintr&auml;ge k&ouml;nnen angelegt werden.
          <ul>
            <li><B>setRepeat &lt;entry&gt; &lt;sender&gt; &lt;receiver&gt; &lt;broadcast&gt;</B><br>
              &lt;entry&gt; [1..36] Nummer des Eintrags in der Tabelle.<br>
              &lt;sender&gt; Name oder HMid des Senders oder der Quelle die weitergeleitet werden soll<br>
              &lt;receiver&gt; Name oder HMid des Empf&auml;ngers oder Ziels an das weitergeleitet werden soll<br>
              &lt;broadcast&gt; [yes|no] definiert ob Broadcasts von einer ID weitergeleitet werden sollen.<br>
              <br>
              Kurzanwendung: <br>
              <code>setRepeat setAll 0 0 0<br></code>
              schreibt die gesamte Liste der Ger&auml;te neu. Daten kommen vom Attribut repPeers. <br>
              Das Attribut repPeers hat folgendes Format:<br>
              src1:dst1:[y/n],src2:dst2:[y/n],src2:dst2:[y/n],...<br>
              <br>
              Formatierte Werte von repPeer:<br>
              <ul>
                Number src dst broadcast verify<br>
                number: Nummer des Eintrags in der Liste<br>
                src: Ursprungsger&auml;t der Nachricht - aus Repeater ausgelesen<br>
                dst: Zielger&auml;t der Nachricht - aus den Attributen abgeleitet<br>
                broadcast: sollen Broadcasts weitergeleitet werden - aus Repeater ausgelesen<br>
                verify: stimmen Attribute und ausgelesen Werte &uuml;berein?<br>
              </ul>
            </li>
          </ul>
        </li>
        
      </ul>
      <br>
      Debugging:
      <ul>
        <li><B>raw &lt;data&gt; ...</B><br>
          nur f&uuml;r Experimente ben&ouml;tigt.
          Sendet einen "Roh"-Befehlen. Die L&auml;nge wird automatisch
          berechnet und der Nachrichtenz&auml;hler wird erh&ouml;ht wenn die ersten beiden Zeichen ++ sind.
          
          Beispiel (AES aktivieren):
          <pre>
            set hm1 raw ++A001F100001234560105000000001</pre>
        </li>
      </ul>
    </ul>
    <br>
    <a id="CUL_HM-get"></a><h4>Get</h4><br>
    <ul>
      <li><B>configSave &lt;filename&gt;</B><a id="CUL_HM-get-configSave"></a><br>
        Sichert die Einstellungen eines Eintrags in einer Datei. Die Daten werden in
        einem von der FHEM-Befehlszeile ausf&uuml;hrbaren Format gespeichert.<br>
        Die Datei liegt im FHEM Home-Verzeichnis neben der fhem.cfg. Gespeichert wird
        kumulativ- d.h. neue Daten werden an die Datei angeh&auml;ngt. Es liegt am Benutzer das
        doppelte speichern von Eintr&auml;gen zu vermeiden.<br>
        Ziel der Daten ist NUR die Information eines HM-Ger&auml;tes welche IM Ger&auml;t gespeichert ist.
        Im Deteil sind das nur die Peer-Liste sowie die Register.
        Durch die Register wird also das Peering eingeschlossen.<br>
        Die Datei ist vom Benutzer les- und editierbar. Zus&auml;tzlich gespeicherte Zeitstempel
        helfen dem Nutzer bei der Validierung.<br>
        Einschr&auml;nkungen:<br>
        Auch wenn alle Daten eines Eintrags in eine Datei gesichert werden so sichert FHEM nur
        die zum Zeitpunkt des Speicherns verf&uuml;gbaren Daten! Der Nutzer muss also die Daten
        der HM-Hardware auslesen bevor dieser Befehl ausgef&uuml;hrt wird.
        Siehe empfohlenen Ablauf unten.<br>
        Dieser Befehl speichert keine FHEM-Attribute oder Ger&auml;tedefinitionen.
        Diese verbleiben in der fhem.cfg.<br>
        Desweiteren werden gesicherte Daten nicht automatisch zur&uuml;ck auf die HM-Hardware geladen.
        Der Benutzer muss die Wiederherstellung ausl&ouml;sen.<br><br>
        Ebenso wie ander Befehle wird 'configSave' am besten auf ein Ger&auml;t und nicht auf einen
        Kanal ausgef&uuml;hrt. Wenn auf ein Ger&auml;t angewendet werden auch die damit verbundenen Kan&auml;le
        gesichert. <br><br>
        <code>
          Empfohlene Arbeitsfolge f&uuml;r ein Ger&auml;t 'HMdev':<br>
          set HMdev clear msgEvents # alte Events l&ouml;schen um Daten besser kontrollieren zu k&ouml;nnen<br>
          set HMdev getConfig # Ger&auml;te- und Kanalinformation auslesen<br>
          # warten bis Ausf&uuml;hrung abgeschlossen ist<br>
          # "protState" sollte dann "CMDs_done" sein<br>
          # es sollten keine Warnungen zwischen "prot" und den Variablen auftauchen<br>
          get configSave myActorFile<br>
        </code>
      </li>
      <li><B>param &lt;paramName&gt;</B><br>
        Gibt den Inhalt der relevanten Parameter eines Eintrags zur&uuml;ck. <br>
        Hinweis: wird der Befehl auf einen Kanal angewandt und 'model' abgefragt so wird das Model
        des inhalteanbietenden Ger&auml;ts zur&uuml;ckgegeben.
      </li>
      <li><B>reg &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
        liefert den Wert eines Registers zur&uuml;ck. Daten werden aus dem Speicher von FHEM und nicht direkt vom Ger&auml;t geholt.
        Falls der Registerinhalt nicht verf&uuml;gbar ist muss "getConfig" sowie anschließend "getReg" verwendet werden.<br>
        
        &lt;addr&gt; Adresse des Registers in HEX. Registername kann alternativ verwendet werden falls in FHEM bekannt.
        "all" gibt alle dekodierten Register eines Eintrags in einer Liste zur&uuml;ck.<br>
        &lt;list&gt; Liste aus der das Register gew&auml;hlt wird. Wird der Registername verwendet wird "list" ignoriert und kann auf '0' gesetzt werden.<br>
        &lt;peerID&gt; identifiziert die Registerb&auml;nke f&uuml;r "list3" und "list4". Kann als Dummy gesetzt werden wenn nicht ben&ouml;tigt.<br>
      </li>
      <li><B>regList</B><br>
        gibt eine Liste der von FHEM f&uuml;r dieses Ger&auml;t dekodierten Register zur&uuml;ck.<br>
        Beachten dass noch mehr Register f&uuml;r ein Ger&auml;t implemetiert sein k&ouml;nnen.<br>
      </li>
      <li><B>saveConfig &lt;file&gt;</B><a id="CUL_HM-get-saveConfig"></a><br>
        speichert Peers und Register in einer Datei.<br>
        Gespeichert werden die Daten wie sie in FHEM verf&uuml;gbar sind. Es ist daher notwendig vor dem Speichern die Daten auszulesen.<br>
        Der Befehl unterst&uuml;tzt Aktionen auf Ger&auml;teebene. D.h. wird der Befehl auf ein Ger&auml;t angewendet werden auch alle verbundenen Kanaleintr&auml;ge gesichert.<br>
        Das Speichern der Datei erfolgt kumulativ. Wird ein Eintrag mehrfach in der selben Datei gespeichert so werden die Daten an diese angeh&auml;ngt.
        Der Nutzer kann den Zeitpunkt des Speichern bei Bedarf auslesen.<br>
        Der Inhalt der Datei kann verwendet werden um die Ger&auml;teeinstellungen wiederherzustellen. Er stellt alle Peers und Register des Eintrags wieder her.<br>
        Zw&auml;nge/Beschr&auml;nkungen:<br>
        vor dem zur&uuml;ckschreiben der Daten eines Eintrags muss das Ger&auml;t mit FHEM verbunden werden.<br>
        "restore" l&ouml;scht keine verkn&uuml;pften Kan&auml;le, es f&uuml;gt nur neue Peers hinzu.<br>
      </li>
       <li><B>list (normal|hidden);</B><a id="CUL_HM-get-list"></a><br>
           triggern des list commandos fuer die entity normal oder inclusive der verborgenen parameter
           </li>       
       <li><B>listDevice</B><br>
           <ul>
               <li>bei einer CCU gibt es eine Liste der Devices, welche den ccu service zum zuweisen der IOs zur&uuml;ck<br>
                 </li>
               <li>beim ActionDetector wird eine Komma geteilte Liste der Entities zur&uuml;ckgegeben<br>
                   get ActionDetector listDevice          # returns alle assigned entities<br>
                   get ActionDetector listDevice notActive# returns entities ohne status alive<br>
                   get ActionDetector listDevice alive    # returns entities mit status alive<br>
                   get ActionDetector listDevice unknown  # returns entities mit status unknown<br>
                   get ActionDetector listDevice dead     # returns entities mit status dead<br>
                   </li>
               </ul>
           </li>
    </ul><br>
    <a id="CUL_HM-attr"></a>
    <h4>Attribute</h4>
    <ul>
      <li><a href="#eventMap">eventMap</a></li>
      <li><a href="#do_not_notify">do_not_notify</a></li>
      <li><a href="#ignore">ignore</a></li>
      <li><a href="#dummy">dummy</a></li>
      <li><a href="#showtime">showtime</a></li> 
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li><a id="CUL_HM-attr-readingOnDead"></a>readingOnDead<br>
          definiert wie readings behandelt werden sollten wenn das Device als 'dead' mariert wird.<br>
          Das Attribut ist nur auf Devices anwendbar. Es &auml;ndert die Readings wenn das Device nach dead geht. 
          Beim Verlasen des Zustandes 'dead' werden die ausgew&auml;hlten Readings nach 'notDead' ge&auml;ndert. Es kann erwartet werden, dass sinnvolle Werte vom Device eingetragen werden.<br>
          Optionen sind:<br>
          noChange: keine Readings ausser Actvity werden ge&auml;ndert. Andere Eintr&auml;ge werden ignoriert.<br>
          state: das Reading 'state' wird auf 'dead' gesetzt.<br>
          periodValues: periodische numerische Readings des Device werden auf '0' gesetzt.<br>
          periodString: periodische string Readings des Device werden auf 'dead' gesetzt.<br>
          channels: die Readings der Kan&auml;le werden ebenso wie die des Device behandelt und auch geaendert.<br>
          custom readings: der Anwender kann weitere Readingnamen eintragen, welche ggf. auf 'dead' zu setzen sind.<br>
          <br>
          Beispiel:<br>
          <ul><code>
            attr myDevice readingOnDead noChange,state # kein dead marking - noChange hat Prioritaet <br>
            attr myDevice readingOnDead state,periodValues,channels # Empfohlen. Reading state des device und aller seiner Kan&auml;le werden auf 'dead' gesetzt.
            Periodische nummerische werden werden auf 0 gesetzt was Auswirkungen auf die Grafiken hat.<br>
            attr myDevice readingOnDead state,channels # Reading state des device und aller seiner Kan&auml;le werden auf 'dead' gesetzt.<br>
            attr myDevice readingOnDead periodValues,channels # Numerische periodische Readings des Device und der Kanaele werden auf '0' gesetzt<br>
            attr myDevice readingOnDead state,deviceMsg,CommandAccepted # beim Eintreten in dead state,deviceMsg und CommandAccepted des Device werden, wenn verfuegbar, auf 'dead' gesetzt.<br>
          </code></ul>           
          </li>
      <li><a id="CUL_HM-attr-aesCommReq"></a>aesCommReq<br>
           wenn gesetzt wird IO AES signature anfordern bevor ACK zum Device gesendet wird.<br>
      </li>
      <li><a id="CUL_HM-attr-actAutoTry">actAutoTry</a><br>
         actAutoTry 0_off,1_on<br>
         setzen erlaubt dem ActionDetector ein statusrequest zu senden falls das Device dead markiert werden soll.
         Das Attribut kann f&uuml;r Devices n&uuml;tzlich sein, welche sich nicht von selbst zyklisch melden.
      </li>
      <li><a id="CUL_HM-attr-actCycle"></a>actCycle<br>
        actCycle &lt;[hhh:mm]|off&gt;<br>
        Bietet eine 'alive' oder besser 'not alive' Erkennung f&uuml;r Ger&auml;te. [hhh:mm] ist die maximale Zeit ohne Nachricht eines Ger&auml;ts. Wenn innerhalb dieser Zeit keine Nachricht empfangen wird so wird das Event"&lt;device&gt; is dead" generiert.
        Sendet das Ger&auml;t wieder so wird die Nachricht"&lt;device&gt; is alive" ausgegeben. <br>
        Diese Erkennung wird durch 'autocreate' f&uuml;r jedes Ger&auml;t mit zyklischer Statusmeldung angelegt.<br>
        Die Kontrollinstanz ist ein Pseudo-Ger&auml;t "ActionDetector" mit der HMId "000000".<br>
        Aufgrund von Performance&uuml;berlegungen liegt die Antwortverz&ouml;gerung bei 600 Sekunden (10min). Kann &uuml;ber das Attribut "actCycle" des "ActionDetector" kontrolliert werden.<br>
        Sobald die &Uuml;berwachung aktiviert wurde hat das HM-Ger&auml;t 2 Attribute:<br>
        <ul>
          actStatus: Aktivit&auml;tsstatus des Ger&auml;ts<br>
          actCycle: Detektionsspanne [hhh:mm]<br>
        </ul>
        Die gesamte Funktion kann &uuml;ber den "ActionDetector"-Eintrag &uuml;berpr&uuml;ft werden. Der Status aller Instanzen liegt im READING-Bereich.<br>
        Hinweis: Diese Funktion kann ebenfalls f&uuml;r Ger&auml;te ohne zyklische &Uuml;bertragung aktiviert werden. Es obliegt dem Nutzer eine vern&uuml;nftige Zeitspanne festzulegen.
      </li>
      <li><a id="CUL_HM-attr-aesKey" data-pattern="aesKey.*"></a>aesKey<br>
          Spezifiziert, welcher aes key verwendet wird, falls <i>aesCommReq</i> aktiviert wird.<br>
          </li>
      <li><a id="CUL_HM-attr-autoReadReg"></a>autoReadReg<br>
        '0' autoReadReg wird ignorert.<br>
        '1' wird automatisch in getConfig ausgef&uuml;hrt f&uuml;r das Device nach jedem reboot von FHEM. <br>
        '2' wie '1' plus nach Power on.<br>
        '3' wie '2' plus update wenn auf das Device geschreiben wird.<br>
        '4' wie '3' plus fordert Status an, wenn es nicht korrekt erscheint<br>
        '5' pr&uuml;ft Registerlisten und peerlisten. Wenn diese nicht komplett sind wird ein update angefordert<br>
        '8_stateOnly' es wird nur der Status gepr&uuml;ft, updates f&uuml;r Register werden nicht gemacht.<br>
        Ausf&uuml;hrung wird verz&ouml;gert ausgef&uuml;hrt. Wenn das IO eine gewisse Last erreicht hat wird 
        das Kommando weiter verz&ouml;gert um eine &Uuml;berlast zu vermeiden.<br>
        Empfohlene Zusammenh&auml;nge bei Nutzung:<br>
        <ul>
          Benutze das Attribut f&uuml;r das Device, nicht f&uuml;r jeden einzelnen Kanal<br>
          Das Setzen auf Level 5 wird f&uuml;r alle Devices und Typen empfohlen, auch wakeup Devices.<br>
        </ul>
        </li>
      <li><a id="CUL_HM-attr-burstAccess"></a>burstAccess<br>
        kann f&uuml;r eine Ger&auml;teinstanz gesetzt werden falls das Model bedingte Bursts erlaubt.
        Das Attribut deaktiviert den Burstbetrieb (0_off) was die Nachrichtenmenge des HMLAN reduziert
        und damit die Wahrscheinlichkeit einer &Uuml;berlast von HMLAN verringert.<br>
        Einschalten (1_auto) erlaubt k&uuml;rzere Reaktionszeiten eines Ger&auml;ts. Der Nutzer muss nicht warten
        bis das Ger&auml;t wach ist. <br>
        Zu beachten ist, dass das Register "burstRx" im Ger&auml;t ebenfalls gesetzt werden muss.
        </li>
      <li><a id="CUL_HM-attr-expert"></a>expert<br>
        Dieses Attribut steuert die Sichtbarkeit der Register Readngs. Damit wird die Darstellung der Ger&auml;teparameter kontrolliert.<br>
        Es handdelt sich um einen binaer kodierten Wert mit folgenden Empfehlungen:<br>
        <ul>
          0_defReg       : default Register<br>
          1_allReg       : all Register<br>
          2_defReg+raw   : default Register und raw Register<br>
          3_allReg+raw   : alle Register und raw reading<br>
          4_off          : no Register<br>
          8_templ+default: templates und default Register<br>
          12_templOnly   : nur templates<br>
          251_anything   : alles verf&uuml;gbare<br>
        </ul>
        Wird 'expert' auf ein Ger&auml;t angewendet so gilt dies auch f&uuml;r alle verkn&uuml;pften Kan&auml;le.
        Kann &uuml;bergangen werden indem das Attribut ' expert' auch f&uuml;r den Ger&auml;tekanal gesetzt wird.<br>
        Das Attribut "showInternalValues" bei den globalen Werten muss ebenfalls &uuml;berpr&uuml;ft werden.
        "expert" macht sich diese Implementierung zu Nutze.
        Gleichwohl setzt "showInternalValues" - bei Definition - 'expert' außer Kraft .
        </li>
      <li><a id="CUL_HM-attr-readOnly">readOnly</a><br>
          beschr&auml;nkt kommandos auf Lesen und Beobachten.
          </li>
      <li><a id="CUL_HM-attr-IOgrp"></a>IOgrp<br>
        kann an Devices vergeben werden und zeigt auf eine virtuelle VCCU. 
        Das Setzen des Attributs f&uuml;hrt zum L&ouml;schen des Attributs IODev da sich diese ausschliessen. 
        Danach wird die VCCU
        beim Senden das passende IO f&uuml;r das Device ausw&auml;hlen. Es ist notwendig, dass die virtuelle VCCU
        definiert und alle erlaubten IOs eingetragen sind. Beim Senden wird die VCCU pr&uuml;fen
        welches IO operational ist und welches den besten rssi-faktor f&uuml;r das Device hat.<br>
        Optional kann ein bevorzugtes IO definiert werden. In diesem Fall wird es, wenn operational,
        genutzt - unabh&auml;ngig von den rssi Werten.<br>
        wenn kein IO aus VCCU's IOList verf&uuml;gbar ist wird der Mechanismus gestoppt und nichts gesendet.<br>
        Beispiel:<br>
        <ul><code>
          attr myDevice1 IOgrp vccu<br>
          attr myDevice2 IOgrp vccu:prefIO1,prefIO2,prefIO3<br>
          attr myDevice2 IOgrp vccu:prefIO1,prefIO2,none<br>
        </code></ul>
        </li>
      <li><a id="CUL_HM-attr-levelRange"></a>levelRange<br>
        nur f&uuml;r Dimmer! Der Dimmbereich wird eingeschr&auml;nkt. 
        Es ist gedacht um z.B. LED Lichter unterst&uuml;tzen welche mit 10% beginnen und bei 40% bereits das Maximum haben.
        levelrange normalisiert den Bereich entsprechend. D.h. set 100 wird physikalisch den Dimmer auf 40%, 
        1% auf 10% setzen. 0% schaltet physikalisch aus.<br>
        Beeinflusst werdne Kommndos on, up, down, toggle und pct. <b>Nicht</b> beeinflusst werden Kommandos
        die den Wert physikalisch setzen.<br>
        Zu beachten:<br>
        dimmer level von Peers gesetzt wird nicht beeinflusst. Dies wird durch Register konfiguriert.<br>
        Readings level k&ouml;nnte negative werden oder &uuml;ber 100%. Das kommt daher, dass physikalisch der Bereich 0-100%
        ist aber auf den logischen bereicht normiert wird.<br>
        Sind virtuelle Dimmer Kan&auml;le verf&uuml;gbar muss das Attribut f&uuml;r jeden Kanal gesetzt werden<br>
        Beispiel:<br>
        <ul><code>
          attr myChannel levelRange 0,40<br>
          attr myChannel levelRange 10,80<br>
        </code></ul>
        </li>
      <li><a id="CUL_HM-attr-tempListTmpl"></a>tempListTmpl<br>
        Setzt das Default f&uuml;r Heizungskontroller. Ist es nicht gesetzt wird der default filename genutzt und der name
        der entity als templatename. Z.B. ./tempList.cfg:RT_Clima<br> 
        Um das template nicht zu nutzen kann man es auf 'none' oder '0'setzen.<br>
        Format ist &lt;file&gt;:&lt;templatename&gt;. 
        </li>
      <li><a id="CUL_HM-attr-modelForce"></a>modelForce<br>
          modelForce &uuml;berschreibt das model attribut. Dabei wird das Device und seine Kan&auml;le reconfguriert.<br>
          Grund f&uuml;r dieses Attribut ist ein eQ3 bug bei welchen Devices mit falscher ID ausgeliefert werden. Das Attribut
          erlaubt dies zu ueberschreiben<br>
          ACHTUNG: Durch das Eintragen eines anderen model werden die Entites modifiziert, ggf. neu angelegt oder gel&ouml;scht.<br>
          </li>
      <li><a id="CUL_HM-attr-model"></a>model<br>
        wird automatisch gesetzt. </li>
      <li><a id="CUL_HM-attr-subType"></a>subType<br>
        wird automatisch gesetzt. </li>
      <li><a id="CUL_HM-attr-msgRepeat"></a>msgRepeat<br>
        Definiert die Nummer an Wiederholungen falls ein Ger&auml;t nicht rechtzeitig antwortet. <br>
        F&uuml;r Ger&auml;te die nur den "Config"-Modus unterst&uuml;tzen sind Wiederholungen nicht erlaubt. <br>
        Bei Ger&auml;te mit wakeup-Modus wartet das Ger&auml;t bis zum n&auml;chsten Aufwachen. Eine l&auml;ngere Verz&ouml;gerung
        sollte in diesem Fall angedacht werden. <br>
        Wiederholen von Bursts hat Auswirkungen auf die HMLAN &Uuml;bertragungskapazit&auml;t.</li>
      <li><a id="CUL_HM-attr-rawToReadable"></a>rawToReadable<br>
        Wird verwendet um Rohdaten von KFM100 in ein lesbares Fomrat zu bringen, basierend auf
        den gemessenen Werten. Z.B. langsames F&uuml;llen eines Tanks, w&auml;hrend die Werte mit <a href="#inform">inform</a>
        angezeigt werden. Man sieht:
        <ul>
          10 (bei 0%)<br>
          50 (bei 20%)<br>
          79 (bei 40%)<br>
          270 (bei 100%)<br>
        </ul>
        Anwenden dieser Werte: "attr KFM100 rawToReadable 10:0 50:20 79:40 270:100".
        FHEM f&uuml;r damit eine lineare Interpolation der Werte in den gegebenen Grenzen aus.
      </li>
      <li><a id="CUL_HM-attr-unit"></a>unit<br>
        setzt die gemeldete Einheit des KFM100 falls 'rawToReadable' aktiviert ist. Z.B.<br>
        attr KFM100 unit Liter
      </li>
      <li><a id="CUL_HM-attr-autoReadReg"></a>autoReadReg<br>
        '0' autoReadReg wird ignoriert.<br>
        '1' f&uuml;hrt ein "getConfig" f&uuml;r ein Ger&auml;t automatisch nach jedem Neustart von FHEM aus. <br>
        '2' verh&auml;lt sich wie '1',zus&auml;tzlich nach jedem power_on.<br>
        '3' wie '2', zus&auml;tzlich bei jedem Schreiben auf das Ger&auml;t<br>
        '4' wie '3' und versucht außerdem den Status abzufragen falls dieser nicht verf&uuml;gbar erscheint.<br>
        '5' kontrolliert 'reglist' und 'peerlist'. Falls das Auslesen unvollst&auml;ndig ist wird 'getConfig' ausgef&uuml;hrt<br>
        '8_stateOnly' aktualisiert nur Statusinformationen aber keine Konfigurationen wie Daten- oder
        Peerregister.<br>
        Ausf&uuml;hrung wird verz&ouml;gert um eine &Uuml;berlastung beim Start zu vermeiden . Daher werden Aktualisierung und Anzeige
        von Werten abh&auml;ngig von der Gr&ouml;ße der Datenbank verz&ouml;gert geschehen.<br>
        Empfehlungen und Einschr&auml;nkungen bei Benutzung:<br>
        <ul>
          Dieses Attribut nur auf ein Ger&auml;t oder Kanal 01 anwenden. Nicht auf einzelne Kan&auml;le eines mehrkanaligen
          Ger&auml;ts anwenden um eine doppelte Ausf&uuml;hrung zu vermeiden.<br>
          Verwendung bei Ger&auml;ten die nur auf den 'config'-Modus reagieren wird nicht empfohlen da die Ausf&uuml;hrung
          erst starten wird wenn der Nutzer die Konfiguration vornimmt<br>
          Anwenden auf Ger&auml;te mit 'wakeup'-Modus ist n&uuml;tzlich. Zu bedenken ist aber dass die Ausf&uuml;hrung
          bis zm "aufwachen" verz&ouml;gert wird.<br>
        </ul>
      </li>
      </ul> <br>
    <li>
    <a id="CUL_HM-attr-param"></a><b>'param'</b> definiert modelspezifische Verhalten oder Funktionen. Verf&uuml;gbare Parameter f&uuml;r "param" (Modell-abh&auml;ngig):
    <ul>
      <li><B>HM-SEN-RD-O</B><br>
        offAtPon: nur Heizkan&auml;le: erzwingt Ausschalten der Heizung nach einem powerOn<br>
        onAtRain: nur Heizkan&auml;le: erzwingt Einschalten der Heizung bei Status 'rain' und Ausschalten bei Status 'dry'<br>
      </li>
      <li><B>virtuals</B><br> 
        noOnOff: eine virtuelle Instanz wird den Status nicht &auml;ndern wenn ein Trigger empfangen wird. Ist dieser Paramter
        nicht gegeben so toggled die Instanz ihren Status mit jedem trigger zwischen An und Aus<br>
        msgReduce: falls gesetzt und der Kanal wird f&uuml;r <a ref="CUL_HM-set-valvePos">valvePos</a> genutzt wird jede Nachricht
        außer die der Ventilstellung verworfen um die Nachrichtenmenge zu reduzieren<br>
      </li>
      <li><B>blind</B><br>
        levelInverse: w&auml;hrend HM 100% als offen und 0% als geschlossen behandelt ist dies evtl. nicht 
        intuitiv f&uuml;r den Nutzer. Defaut f&uuml;r 100% ist offen und wird als 'on'angezeigt. 
        Das Setzen des Parameters invertiert die Anzeige - 0% wird also offen und 100% ist geschlossen.<br>
        ACHTUNG: Die Anpassung betrifft nur Readings und Kommandos. <B>Register sind nicht betroffen.</B><br>
        ponRestoreSmart: bei powerup des Device f&auml;hrt das Rollo in die vermeintlich n&auml;chstgelegene Endposition und anschliessend in die urspr&uuml;ngliche Position.<br>
        ponRestoreForce: bei powerup des Device f&auml;hrt das Rollo auf Level 0, dann auf Level 100 und anschliessend in die urspr&uuml;ngliche Position.<br>
      </li>
      <li><B>switch</B><br>
        levelInverse: siehe oben bei <i>blind</i>
      </li>
      <li><B>sensRain</B><br>
          <B>siren</B><br>
          <B>powerMeter</B><br>
          <B>dimmer</B><br>
          <B>rgb</B><br>
        <B>showTimed</B> wenn timedOn running ist wird -till an state geh&auml;ngt. Dies f&uuml;hrt dazu, dass ggf. on-till im State steht was das stateIcon handling verbessert.<br>
      </li>
    </ul>
    </li><br>
    <a id="CUL_HM-events"></a><b>Erzeugte Events:</b>
    <ul>
      <li><B>Allgemein</B><br>
        recentStateType:[ack|info] # kann nicht verwendet werden um Nachrichten zu triggern<br>
        <ul>
          <li>ack zeigt an das eine Statusinformation aus einer Best&auml;tigung abgeleitet wurde</li>
          <li>info zeigt eine automatische Nachricht eines Ger&auml;ts an</li>
          <li><a id="CUL_HM-events-sabotageAttackId"></a><b>sabotageAttackId</b><br>
            Alarmiert bei Konfiguration des Ger&auml;ts durch unbekannte Quelle<br></li>
          <li><a id="CUL_HM-events-sabotageAttack"></a><b>sabotageAttack</b><br>
            Alarmiert bei Konfiguration des Ger&auml;ts welche nicht durch das System ausgel&ouml;st wurde<br></li>
          <li><a id="CUL_HM-events-trigDst"></a><b>trigDst_&lt;name&gt;: noConfig</b><br>
           Ein Sensor triggert ein Device welches nicht in seiner Peerliste steht. Die Peerliste ist nicht akuell<br></li>
        </ul>
      </li>
      <li><B>HM-CC-TC,ROTO_ZEL-STG-RM-FWT</B><br>
        T: $t H: $h<br>
        battery:[low|ok]<br>
        measured-temp $t<br>
        humidity $h<br>
        actuator $vp %<br>
        desired-temp $dTemp<br>
        desired-temp-manu $dTemp #Temperatur falls im manuellen Modus<br>
        desired-temp-cent $dTemp #Temperatur falls im Zentrale-Modus<br>
        windowopen-temp-%d %.1f (sensor:%s)<br>
        tempList$wd hh:mm $t hh:mm $t ...<br>
        displayMode temp-[hum|only]<br>
        displayTemp [setpoint|actual]<br>
        displayTempUnit [fahrenheit|celsius]<br>
        controlMode [auto|manual|central|party]<br>
        tempValveMode [Auto|Closed|Open|unknown]<br>
        param-change offset=$o1, value=$v1<br>
        ValveErrorPosition_for_$dname $vep %<br>
        ValveOffset_for_$dname : $of %<br>
        ValveErrorPosition $vep %<br>
        ValveOffset $of %<br>
        time-request<br>
        trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel.
        Dieses Event h&auml;ngt vom kompletten Auslesen der Kanalkonfiguration ab, anderenfalls k&ouml;nnen Daten
        unvollst&auml;ndig oder fehlerhaft sein.<br>
        trigLast &lt;channel&gt; #letzter empfangener Trigger<br>
      </li>
      <li><B>HM-CC-RT-DN and HM-CC-RT-DN-BOM</B><br>
        state:T: $actTemp desired: $setTemp valve: $vp %<br>
        motorErr: [ok|ValveTight|adjustRangeTooLarge|adjustRangeTooSmall|communicationERR|unknown|lowBat|ValveErrorPosition]
        measured-temp $actTemp<br>
        desired-temp $setTemp<br>
        ValvePosition $vp %<br>
        mode [auto|manual|party|boost]<br>
        battery [low|ok]<br>
        batteryLevel $bat V<br>
        measured-temp $actTemp<br>
        desired-temp $setTemp<br>
        actuator $vp %<br>
        time-request<br>
        trig_&lt;src&gt; &lt;value&gt; #Kanal wurde durch &lt;src&gt; Kanal ausgel&ouml;ßt.
      </li>
      <li><B>HM-CC-VD,ROTO_ZEL-STG-RM-FSA</B><br>
        $vp %<br>
        battery:[critical|low|ok]<br>
        motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
        ValvePosition:$vp %<br>
        ValveErrorPosition:$vep %<br>
        ValveOffset:$of %<br>
        ValveDesired:$vp % # durch Temperatursteuerung gesetzt <br>
        operState:[errorTargetNotMet|onTarget|adjusting|changed] # operative Bedingung<br>
        operStateErrCnt:$cnt # Anzahl fehlgeschlagener Einstellungen<br>
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
        color $value # in Hex - nur f&uuml;r Ger&auml;t<br>
        $value # in Hex - nur f&uuml;r Ger&auml;t<br>
        color [off|red|green|orange] # f&uuml;r Kanal <br>
        [off|red|green|orange] # f&uuml;r Kanal <br>
      </li>
      <li><B>HM-OU-CFM-PL</B><br>
        [on|off|$val]<br>
      </li>
      <li><B>HM-SEN-WA-OD</B><br>
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
      <li><B>HM-SEN-RD-O</B><br>
        lastRain: timestamp # kein Trigger wird erzeugt. Anfang des vorherigen Regen-Zeitstempels
        des Messwerts ist Ende des Regens. <br>
      </li>
      <li><B>THSensor und HM-WDC7000</B><br>
        T: $t H: $h AP: $ap<br>
        temperature $t<br>
        humidity $h<br>
        airpress $ap #nur HM-WDC7000<br>
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
        cover [closed|open] # nicht bei HM-SEC-MDIR<br>
        sabotageError [on|off] # nur bei HM-SEC-MDIR<br>
        battery [low|ok]<br>
        devState_raw.$d1 $d2<br>
      </li>
      <li><B>remote/pushButton/outputUnit</B><br>
        <ul> (to $dest) wird hinzugef&uuml;gt wenn der Knopf gepeert ist und keinen Broadcast sendet<br>
          Freigabe ist nur f&uuml;r verkn&uuml;pfte Kan&auml;le verf&uuml;gbar</ul>
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
        Btn$x Short<br>
        Btn$x Short (to $dest)<br>
        battery: [low|ok]<br>
      </li>
      <li><B>switch/dimmer/blindActuator</B><br>
        $val<br>
        powerOn [on|off|$val]<br>
        [unknown|motor|dim] [up|down|stop]:$val<br>
        timedOn [running|off]<br> # "An" ist tempor&auml;r - z.B. mit dem 'on-for-timer' gestartet
      </li>
      <li><B>sensRain</B><br>
        $val<br>
        powerOn <br>
        level &lt;val&ge;<br>
        timedOn [running|off]<br> # "An" ist tempor&auml;r - z.B. mit dem 'on-for-timer' gestartet
        trigger [Long|Short]_$no trigger event from channel<br>
      </li>
      <li><B>smokeDetector</B><br>
        [off|smoke-Alarm|alive] # f&uuml;r Gruppen-Master<br>
        [off|smoke-forward|smoke-alarm] # f&uuml;r Gruppenmitglieder<br>
        [normal|added|addedStrong] #HM-CC-SCD<br>
        SDteam [add|remove]_$dname<br>
        battery [low|ok]<br>
        smoke_detect [none|&lt;src&gt;]<br>
        teamCall:from $src<br>
      </li>
      <li><B>threeStateSensor</B><br>
        [open|tilted|closed]<br>
        [wet|damp|dry] #nur HM-SEC-WDS<br>
        cover [open|closed] #HM-SEC-WDS und HM-SEC-RHS<br>
        alive yes<br>
        battery [low|ok]<br>
        contact [open|tilted|closed]<br>
        contact [wet|damp|dry] #nur HM-SEC-WDS<br>
        sabotageError [on|off] #nur HM-SEC-SC<br>
      </li>
      <li><B>winMatic</B><br>
        [locked|$value]<br>
        motorErr [ok|TurnError|TiltError]<br>
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
  <a id="CUL_HM-internals"></a><b>Internals</b>
  <ul>
    <li><B>aesCommToDev</B><br>
      Information &uuml;ber Erfolg und Fehler der AES Kommunikation zwischen IO-device und HM-Device<br>
    </li>
  </ul><br>
  <br>
  </ul>
=end html_DE

=cut
