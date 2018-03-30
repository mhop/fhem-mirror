##############################################
# $Id$
package main;
use strict;
use warnings;

sub HMinfo_Initialize($$);
sub HMinfo_Define($$);
sub HMinfo_getParam(@);
sub HMinfo_regCheck(@);
sub HMinfo_peerCheck(@);
sub HMinfo_getEntities(@);
sub HMinfo_SetFn($@);
sub HMinfo_SetFnDly($);
sub HMinfo_noDup(@);
sub HMinfo_register ($);

use Blocking;
use HMConfig;
my $doAli = 0;#display alias names as well (filter option 2)
my $tmplDefChange = 0;
my $tmplUsgChange = 0;

sub HMinfo_Initialize($$) {####################################################
  my ($hash) = @_;

  $hash->{DefFn}     = "HMinfo_Define";
  $hash->{UndefFn}   = "HMinfo_Undef";
  $hash->{SetFn}     = "HMinfo_SetFn";
  $hash->{GetFn}     = "HMinfo_GetFn";
  $hash->{AttrFn}    = "HMinfo_Attr";
  $hash->{NotifyFn}  = "HMinfo_Notify";
  $hash->{AttrList}  =  "loglevel:0,1,2,3,4,5,6 "
                       ."sumStatus sumERROR "
                       ."autoUpdate autoArchive "
                       ."autoLoadArchive:0_no,1_load "
#                       ."autoLoadArchive:0_no,1_template,2_register,3_templ+reg "
                       ."hmAutoReadScan hmIoMaxDly "
                       ."hmManualOper:0_auto,1_manual "
                       ."configDir configFilename configTempFile "
                       ."hmDefaults "
                       .$readingFnAttributes;
  $hash->{NOTIFYDEV} = "global";
}
sub HMinfo_Define($$){#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($n) = devspec2array("TYPE=HMinfo");
  return "only one instance of HMInfo allowed, $n already instantiated"
        if ($n && $hash->{NAME} ne $n);
  my $name = $hash->{NAME};
  $hash->{Version} = "01";
  $attr{$name}{webCmd} = "update:protoEvents short:rssi:peerXref:configCheck:models";
  $attr{$name}{sumStatus} =  "battery"
                            .",sabotageError"
                            .",powerError"
                            .",motor";
  $attr{$name}{sumERROR}  =  "battery:ok"
                            .",sabotageError:off"
                            .",powerError:ok"
                            .",overload:off"
                            .",overheat:off"
                            .",reduced:off"
                            .",motorErr:ok"
                            .",error:none"
                            .",uncertain:[no|yes]"
                            .",smoke_detect:none"
                            .",cover:closed"
                            ;
  $hash->{nb}{cnt} = 0;
  return;
}
sub HMinfo_Undef($$){##########################################################
  my ($hash, $name) = @_;
  return undef;
}
sub HMinfo_Attr(@) {###########################################################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  my @hashL;
  my $hash = $defs{$name};

  if   ($attrName eq "autoUpdate"){# 00:00 hh:mm
    delete $hash->{helper}{autoUpdate};
    return if ($cmd eq "del");
    my ($h,$m) = split":",$attrVal;
    return "please enter time [hh:mm]" if (!defined $h||!defined $m);
    my $sec = $h*3600+$m*60;
    return "give at least one minute" if ($sec < 60);
    $hash->{helper}{autoUpdate} = $sec;
    InternalTimer(gettimeofday()+$sec,"HMinfo_autoUpdate","sUpdt:".$name,0);
  }
  elsif($attrName eq "hmAutoReadScan"){# 00:00 hh:mm
    if ($cmd eq "del"){
      $modules{CUL_HM}{hmAutoReadScan} = 4;# return to default
    }
    else{
      return "please add plain integer between 1 and 300"
          if (  $attrVal !~ m/^(\d+)$/
              ||$attrVal<0
              ||$attrVal >300 );
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{hmAutoReadScan}=$attrVal;
      CUL_HM_procQs("");
    }
  }
  elsif($attrName eq "hmIoMaxDly"){#
    if ($cmd eq "del"){
      $modules{CUL_HM}{hmIoMaxDly} = 60;# return to default
    }
    else{
      return "please add plain integer between 0 and 3600"
          if (  $attrVal !~ m/^(\d+)$/
              ||$attrVal<0
              ||$attrVal >3600 );
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{hmIoMaxDly}=$attrVal;
    }
  }
  elsif($attrName eq "hmManualOper"){# 00:00 hh:mm
    if ($cmd eq "del"){
      $modules{CUL_HM}{helper}{hmManualOper} = 0;# default automode
    }
    else{
      return "please set 0 or 1"  if ($attrVal !~ m/^(0|1)/);
      ## implement new timer to CUL_HM
      $modules{CUL_HM}{helper}{hmManualOper} = substr($attrVal,0,1);
    }
  }
  elsif($attrName eq "sumERROR"){
    if ($cmd eq "set"){
      foreach (split ",",$attrVal){    #prepare reading filter for error counts
        my ($p,@a) = split ":",$_;
        return "parameter illegal - " 
              if(!$p || !$a[0]);
      }
    }
  }
  elsif($attrName eq "configDir"){
    if ($cmd eq "set"){
      $attr{$name}{configDir}=$attrVal;
    }
    else{
      delete $attr{$name}{configDir};
    }
    HMinfo_listOfTempTemplates();
  }
  elsif($attrName eq "configTempFile"){
    if ($cmd eq "set"){
      $attr{$name}{configTempFile}=$attrVal;
    }
    else{
      delete $attr{$name}{configTempFile};
    }
    HMinfo_listOfTempTemplates();
  }
  elsif($attrName eq "hmDefaults"){
    if ($cmd eq "set"){
      delete $modules{CUL_HM}{AttrListDef};
      my @defpara = ( "hmProtocolEvents"
                     ,"rssiLog"         
                     ,"autoReadReg"
                     ,"msgRepeat"
                     ,"expert"
                     ,"actAutoTry"
                     );
      my %culAH;
      foreach (split" ",$modules{CUL_HM}{AttrList}){
        my ($p,$v) = split(":",$_);
        $culAH{$p} = $v?",$v,":"";
      }
      
      foreach (split(",",$attrVal)){
        my ($para,$val) = split(":",$_,2);
        return "no value defined for $para" if (!defined "val");
        return "param $para not allowed" if (!grep /$para/,@defpara);
        return "param $para :$val not allowed, use $culAH{$para}" if ($culAH{$para} && $culAH{$para} !~ m/,$val,/);
        $modules{CUL_HM}{AttrListDef}{$para} = $val;
      } 
    }
    else{
      delete $modules{CUL_HM}{AttrListDef};
    }
  }
  elsif($attrName eq "autoLoadArchive"){
    if ($cmd eq "set"){
    }
  }
  return;
}

sub HMinfo_Notify(@){##########################################################
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  return "" if ($dev->{NAME} ne "global");

  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return undef if(!$events); # Some previous notify deleted the array.

  #we need to init the templist if HMInfo is in use
  my $cfgFn  = AttrVal($name,"configTempFile","tempList.cfg");
  HMinfo_listOfTempTemplates() if (grep /(FILEWRITE.*$cfgFn|INITIALIZED)/,@{$events});

  if (grep /(SAVE|SHUTDOWN)/,@{$events}){# also save configuration
    HMinfo_archConfig($hash,$name,"","") if(AttrVal($name,"autoArchive",undef));
  }
  if (grep /INITIALIZED/,@{$events}){
    HMinfo_SetFn($hash,$name,"loadConfig") 
         if (  grep (/INITIALIZED/,@{$events})
             && (substr(AttrVal($name, "autoLoadArchive", 0),0,1) ne 0));
    
  }
  return undef;
}
sub HMinfo_status($){##########################################################
  # - count defined HM entities, selected readings, errors on filtered readings
  # - display Assigned IO devices
  # - show ActionDetector status
  # - prot events if error
  # - rssi - eval minimum values
  my $hash = shift;
  my $name = $hash->{NAME};
  my ($nbrE,$nbrD,$nbrC,$nbrV) = (0,0,0,0);# count entities and types
  #--- used for status
  my @info = split ",",$attr{$name}{sumStatus};#prepare event
  my %sum;
  #--- used for error counts
  my @erro = split ",",$attr{$name}{sumERROR};
  
  # clearout internals prior to update
  delete $hash->{$_} foreach (grep(/^(ERR|W_|I_|C_|CRI_)/,keys%{$hash}));

  my %errFlt;
  my %errFltN;
  my %err;

  foreach (@erro){    #prepare reading filter for error counts
    my ($p,@a) = split ":",$_;
    $errFlt{$p}{x}=1; # add at least one reading
    $errFlt{$p}{$_}=1 foreach (@a);
    my @b;
    $errFltN{$p} = \@b;# will need an array to collect the relevant names
  }
  #--- used for IO, protocol  and communication (e.g. rssi)
  my @IOdev;
  my %IOccu;

  my %protC = (ErrIoId_ =>0,ErrIoAttack =>0);
  my %protE = (NACK =>0,IOerr =>0,ResndFail =>0,CmdDel =>0);
  my %protW = (Resnd =>0,CmdPend =>0);
  my @protNamesC;    # devices with current protocol Critical
  my @protNamesE;    # devices with current protocol Errors
  my @protNamesW;    # devices with current protocol Warnings
  my @Anames;        # devices with ActionDetector events
  my %rssiMin;
  my %rssiMinCnt = ("99>"=>0,"80>"=>0,"60>"=>0,"59<"=>0);
  my @rssiNames; #entities with ciritcal RSSI
  my @shdwNames; #entites with shadowRegs, i.e. unconfirmed register ->W_unconfRegs

  foreach my $id (keys%{$modules{CUL_HM}{defptr}}){#search/count for parameter
    my $ehash = $modules{CUL_HM}{defptr}{$id};
    my $eName = $ehash->{NAME};
    $nbrE++;
    $nbrC++ if ($ehash->{helper}{role}{chn});
    $nbrV++ if ($ehash->{helper}{role}{vrt});
    push @shdwNames,$eName if (CUL_HM_cleanShadowReg($eName)); # are shadowRegs active?
    
    
    foreach my $read (grep {$ehash->{READINGS}{$_}} @info){       #---- count critical readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      $sum{$read}{$val} =0 if (!$sum{$read}{$val});
      $sum{$read}{$val}++;
    }
    foreach my $read (grep {$ehash->{READINGS}{$_}} keys %errFlt){#---- count error readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      next if (grep (/$val/,(keys%{$errFlt{$read}})));# filter non-Error
      push @{$errFltN{$read}},$eName;
      $err{$read}{$val} = 0 if (!$err{$read}{$val});
      $err{$read}{$val}++;
    }
    if ($ehash->{helper}{role}{dev}){#---restrict to devices
      $nbrD++;
      push @IOdev,$ehash->{IODev}{NAME} if($ehash->{IODev} && $ehash->{IODev}{NAME});
      $IOccu{(split ":",AttrVal($eName,"IOgrp","no"))[0]}=1;
      push @Anames,$eName if ($attr{$eName}{actStatus} && $attr{$eName}{actStatus} eq "dead");

      foreach (grep /ErrIoId_/, keys %{$ehash}){# detect addtional critical entries
        my $k = $_;
        $k =~ s/^prot//;
        $protC{$k} = 0 if(!defined $protC{$_});
      }
      foreach (grep {$ehash->{"prot".$_}} keys %protC){ $protC{$_}++; push @protNamesC,$eName;}#protocol critical alarms
      foreach (grep {$ehash->{"prot".$_}} keys %protE){ $protE{$_}++; push @protNamesE,$eName;}#protocol errors
      foreach (grep {$ehash->{"prot".$_}} keys %protW){ $protW{$_}++; push @protNamesW,$eName;}#protocol events reported
      $rssiMin{$eName} = 0;
      foreach (keys %{$ehash->{helper}{rssi}}){
        next if($_ !~ m /at_.*$ehash->{IODev}->{NAME}/ );#ignore unused IODev
        $rssiMin{$eName} = $ehash->{helper}{rssi}{$_}{min}
          if ($rssiMin{$eName} > $ehash->{helper}{rssi}{$_}{min});
      }
    }
  }
  #====== collection finished - start data preparation======
  my @updates;
  foreach my $read(grep {defined $sum{$_}} @info){       #--- disp crt count
    my $d;
    $d .= "$_:$sum{$read}{$_},"foreach(sort keys %{$sum{$read}});
    push @updates,"I_sum_$read:".$d;
  }
  foreach my $read(keys %errFlt) {
    if (defined $err{$read}) {
      my $d;
      $d .= "$_:$err{$read}{$_}," foreach(keys %{$err{$read}});
      push @updates,"ERR_$read:".$d;
    } 
    elsif (defined $hash->{READINGS}{"ERR_$read"}) {
      if ($hash->{READINGS}{"ERR_$read"}{VAL} ne '-') {
        # Error condition has been resolved, push empty update
        push @updates,"ERR_$read:";
      } 
      else {
        # Delete reading again if it was already empty
        delete $hash->{READINGS}{"ERR_$read"};	
      }
    }
  }
  foreach(keys %errFltN){
    next if (!@{$errFltN{$_}});
    $hash->{"ERR_".$_} = join(",",sort @{$errFltN{$_}});
  }

  push @updates,"C_sumDefined:"."entities:$nbrE,device:$nbrD,channel:$nbrC,virtual:$nbrV";
  # ------- display status of action detector ------
  push @updates,"I_actTotal:".join",",(split" ",$modules{CUL_HM}{defptr}{"000000"}{STATE});
  
  # ------- what about IO devices??? ------
  push @IOdev,split ",",AttrVal($_,"IOList","")foreach (keys %IOccu);

  my %tmp; # remove duplicates
  $hash->{I_HM_IOdevices} = "";
  $tmp{ReadingsVal($_,"cond",
       InternalVal($_,"STATE","unknown"))}{$_} = 1 foreach( @IOdev);
  foreach my $IOstat (sort keys %tmp){
    $hash->{I_HM_IOdevices} .= "$IOstat: ".join(",",sort keys %{$tmp{$IOstat}}).";";
  }

  # ------- what about protocol events ------
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv

  push @updates,"CRI__protocol:"  .join(",",map {"$_:$protC{$_}"} grep {$protC{$_}} sort keys(%protC));
  push @updates,"ERR__protocol:"  .join(",",map {"$_:$protE{$_}"} grep {$protE{$_}} sort keys(%protE));
  push @updates,"W__protocol:"    .join(",",map {"$_:$protW{$_}"} grep {$protW{$_}} sort keys(%protW));

  my @tpu = devspec2array("TYPE=CUL_HM:FILTER=state=unreachable");
  push @updates,"ERR__unreachable:".scalar(@tpu);
  push @updates,"I_autoReadPend:". scalar @{$modules{CUL_HM}{helper}{qReqConf}};
  # ------- what about rssi low readings ------
  foreach (grep {$rssiMin{$_} != 0}keys %rssiMin){
    if    ($rssiMin{$_}> -60) {$rssiMinCnt{"59<"}++;}
    elsif ($rssiMin{$_}> -80) {$rssiMinCnt{"60>"}++;}
    elsif ($rssiMin{$_}< -99) {$rssiMinCnt{"99>"}++;
                               push @rssiNames,$_  ;}
    else                      {$rssiMinCnt{"80>"}++;}
  }

  my @ta;
                                              if(@tpu)      {$hash->{W__unreachNames} = join(",",@tpu)      };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesC); if(@ta)       {$hash->{CRI__protocol}   = join(",",@ta)       };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesE); if(@ta)       {$hash->{ERR__protocol}   = join(",",@ta)       };
  @ta = grep !/^$/,HMinfo_noDup(@protNamesW); if(@ta)       {$hash->{W__protoNames}   = join(",",@ta)       };
  @ta = @{$modules{CUL_HM}{helper}{qReqConf}};if(@ta)       {$hash->{I_autoReadPend}  = join(",",@ta)       };
                                              if(@shdwNames){$hash->{W_unConfRegs}    = join(",",@shdwNames)};
                                              if(@rssiNames){$hash->{ERR___rssiCrit}  = join(",",@rssiNames)};
                                              if(@Anames)   {$hash->{ERR__actDead}    = join(",",@Anames)   };
 
  push @updates,"I_rssiMinLevel:".join(" ",map {"$_:$rssiMinCnt{$_}"} sort keys %rssiMinCnt);
  
  # ------- update own status ------
  $hash->{STATE} = "updated:".TimeNow();
    
  # ------- update own status ------
  my %curRead;
  $curRead{$_}++ for(grep /^(ERR|W_|I_|C_|CRI_)/,keys%{$hash->{READINGS}});

  readingsBeginUpdate($hash);
  foreach my $rd (@updates){
    next if (!$rd);
    my ($rdName, $rdVal) = split(":",$rd, 2);
    delete $curRead{$rdName};
    next if (defined $hash->{READINGS}{$rdName} &&
             $hash->{READINGS}{$rdName}{VAL} eq $rdVal);
    readingsBulkUpdate($hash,$rdName,
                             ((defined($rdVal) && $rdVal ne "")?$rdVal:"-"));
  }
  readingsEndUpdate($hash,1);

  delete $hash->{READINGS}{$_} foreach(keys %curRead);
  
  return;
}
sub HMinfo_autoUpdate($){#in:name, send status-request#########################
  my $name = shift;
  (undef,$name)=split":",$name,2;
  HMinfo_SetFn($defs{$name},$name,"update") if ($name);
  if (AttrVal($name,"autoArchive",undef) && 
      scalar(@{$modules{CUL_HM}{helper}{confUpdt}})){
    my $fn = HMinfo_getConfigFile($name,"configFilename",undef);
    HMinfo_archConfig($defs{$name},$name,"",$fn);
  }
  InternalTimer(gettimeofday()+$defs{$name}{helper}{autoUpdate},
                "HMinfo_autoUpdate","sUpdt:".$name,0)
        if (defined $defs{$name}{helper}{autoUpdate});
}

sub HMinfo_getParam(@) { ######################################################
  my ($id,@param) = @_;
  my @paramList;
  my $ehash = $modules{CUL_HM}{defptr}{$id};
  my $eName = $ehash->{NAME};
  my $found = 0;
  foreach (@param){
    my $para = CUL_HM_Get($ehash,$eName,"param",$_);
    $para =~ s/,/ ,/g;
    push @paramList,sprintf("%-15s",($para eq "undefined"?" -":$para));
    $found = 1 if ($para ne "undefined") ;
  }
  return $found,sprintf("%-20s\t: %s",$eName,join "\t| ",@paramList);
}
sub HMinfo_regCheck(@) { ######################################################
  my @entities = @_;
  my @regIncompl;
  my @regMissing;
  my @regChPend;

  foreach my $eName (@entities){
    my $ehash = $defs{$eName};
    next if (!$ehash);

    my @lsNo = CUL_HM_reglUsed($eName);
    my @mReg = ();
    my @iReg = ();

    foreach my $rNm (@lsNo){# check non-peer lists
      next if (!$rNm || $rNm eq "");
      if (   !$ehash->{READINGS}{$rNm}
          || !$ehash->{READINGS}{$rNm}{VAL})            {push @mReg, $rNm;}
      elsif ( $ehash->{READINGS}{$rNm}{VAL} !~ m/00:00/){push @iReg, $rNm;}
    }
    if ($ehash->{helper}{shadowReg} && ref($ehash->{helper}{shadowReg}) eq 'HASH'){
      foreach my $rl (keys %{$ehash->{helper}{shadowReg}}){
        my $pre =  (CUL_HM_getAttrInt($eName,"expert") & 0x02)?"":".";#raw register on

        delete $ehash->{helper}{shadowReg}{$rl} 
              if (   ( !$ehash->{helper}{shadowReg}{$rl}) # content is missing
                  ||(   $ehash->{READINGS}{$pre.$rl} 
                     && $ehash->{READINGS}{$pre.$rl}{VAL} eq $ehash->{helper}{shadowReg}{$rl}
                     )                                  # content is already displayed
                   );
      }
      push @regChPend,$eName if (keys %{$ehash->{helper}{shadowReg}});
    }      
                                                      
    push @regMissing,$eName.":\t".join(",",@mReg) if (scalar @mReg);
    push @regIncompl,$eName.":\t".join(",",@iReg) if (scalar @iReg);
  }
  my $ret = "";
  $ret .="\n\n missing register list\n    "   .(join "\n    ",sort @regMissing) if(@regMissing);
  $ret .="\n\n incomplete register list\n    ".(join "\n    ",sort @regIncompl) if(@regIncompl);
  $ret .="\n\n Register changes pending\n    ".(join "\n    ",sort @regChPend)  if(@regChPend);
  return  $ret;
}
sub HMinfo_peerCheck(@) { #####################################################
  my @entities = @_;
  my @peerIDsFail;
  my @peerIDnotDef;
  my @peerIDsNoPeer;
  my @peerIDsTrigUnp;
  my @peerIDsTrigUnd;
  my @peerIDsTeamRT;
  my @peeringStrange; # devices likely should not be peered 
  my @peerIDsAES;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn});#device has no channels
    my $peersUsed = CUL_HM_peerUsed($eName);#
    next if ($peersUsed == 0);# no peers expected
        
    my $peerIDs = AttrVal($eName,"peerIDs","");
    $peerIDs =~ s/00000000,//;
    foreach (grep /^......$/, HMinfo_noDup(map {CUL_HM_name2Id(substr($_,8))} 
                                           grep /^trigDst_/,
                                           keys %{$defs{$eName}{READINGS}})){
      push @peerIDsTrigUnp,"triggerUnpeered: ".$eName.":".$_ 
            if(  ($peerIDs &&  $peerIDs !~ m/$_/)
               &&("CCU-FHEM" ne AttrVal(CUL_HM_id2Name($_),"model","")));
      push @peerIDsTrigUnd,"triggerUndefined: ".$eName.":".$_ 
            if(!$modules{CUL_HM}{defptr}{$_});
    }
    
    if($peersUsed == 2){#peerList incomplete
      push @peerIDsFail,"incomplete: ".$eName.":".$peerIDs;
    }
    else{# work on a valid list
      my $id = $defs{$eName}{DEF};
      my ($devId,$chn) = unpack 'A6A2',$id;
      my $devN = CUL_HM_id2Name($devId);
      my $st = AttrVal($devN,"subType","");# from Device
      my $md = AttrVal($devN,"model","");
      next if ($st eq "repeater");
      if ($st eq 'smokeDetector'){
        push @peeringStrange,$eName." not peered!! add SD to any team !!"
              if(!$peerIDs);
      }
      foreach my $pId (split",",$peerIDs){
        next if ($pId =~m /$devId/);
        if (length($pId) != 8){
          push @peerIDnotDef,$eName." id:$pId  invalid format";
          next;
        }
        my ($pDid,$pChn) = unpack'A6A2',$pId;
        if (!$modules{CUL_HM}{defptr}{$pId} && 
            (!$pDid || !$modules{CUL_HM}{defptr}{$pDid})){
          next if($pDid && CUL_HM_id2IoId($id) eq $pDid);
          push @peerIDnotDef,"$eName id:$pId";
          next;
        }
        my $pName = CUL_HM_id2Name($pId);
        $pName =~s/_chn-0[10]//;           #chan 01 could be covered by device
        my $pPlist = AttrVal($pName,"peerIDs","");
        my $pDName = CUL_HM_id2Name($pDid);
        my $pSt = AttrVal($pDName,"subType","");
        my $pMd = AttrVal($pDName,"model","");
        my $idc = $id;
        if($st =~ m/(pushButton|remote)/){ # type of primary device
          $idc = $devId;
          if($pChn eq "00"){
            foreach (CUL_HM_getAssChnNames($pDName)){
              $pPlist .= AttrVal($_,"peerIDs","");
            }
          }
        }
        push @peerIDsNoPeer,"$eName p:$pName"
              if (  (!$pPlist || $pPlist !~ m/$devId/) 
                  && $st ne 'smokeDetector'
                  && $pChn !~ m/0[x0]/
                  );
        if ($pSt eq "virtual"){
          if (AttrVal($devN,"aesCommReq",0) != 0){
            push @peerIDsAES,$eName." p:".$pName     
                  if ($pMd ne "CCU-FHEM");
          }
        }
        elsif ($md eq "HM-CC-RT-DN"){
          if ($chn =~ m/(0[45])$/){ # special RT climate
            my $c = $1 eq "04"?"05":"04";
            push @peerIDsNoPeer,$eName." pID:".$pId if ($pId !~ m/$c$/);
            if ($pMd !~ m/HM-CC-RT-DN/ ||$pChn !~ m/(0[45])$/ ){
              push @peeringStrange,$eName." pID: Model $pMd should be HM-CC-RT-DN ClimatTeam Channel";
            }
            elsif($chn eq "04"){
              # compare templist template are identical and boost is same
              my $rtCn = CUL_HM_id2Name(substr($pId,0,6)."04");
              my $ob = CUL_HM_Get($defs{$eName},$eName,"regVal","boostPeriod");
              my $pb = CUL_HM_Get($defs{$rtCn} ,$rtCn ,"regVal","boostPeriod");
              my $ot = AttrVal($eName,"tempListTmpl","--");
              my $pt = AttrVal($rtCn ,"tempListTmpl","--");
              push @peerIDsTeamRT,$eName." team:$rtCn  boost differ  $ob / $pb"        if ($ob ne $pb);
              push @peerIDsTeamRT,$eName." team:$rtCn  tempListTmpl differ  $ot / $pt" if ($ot ne $pt);
            }
          }
          elsif($chn eq "02"){
            if($pChn ne "02" ||$pMd ne "HM-TC-IT-WM-W-EU" ){
              push @peeringStrange,$eName." pID: Model $pMd should be HM-TC-IT-WM-W-EU Climate Channel";
            }
          }
        }
        elsif ($md eq "HM-TC-IT-WM-W-EU"){
          if($chn eq "02"){
            if($pChn ne "02" ||$pMd ne "HM-CC-RT-DN" ){
              push @peeringStrange,$eName." pID: Model $pMd should be HM-TC-IT-WM-W-EU Climate Channel";
            }
            else{
              # compare templist template are identical and boost is same
              my $rtCn = CUL_HM_id2Name(substr($pId,0,6)."04");
              my $ob = CUL_HM_Get($defs{$eName},$eName,"regVal","boostPeriod");
              my $pb = CUL_HM_Get($defs{$rtCn} ,$rtCn ,"regVal","boostPeriod");
              my $ot = AttrVal($eName,"tempListTmpl","--");
              my $pt = AttrVal($rtCn ,"tempListTmpl","--");
              push @peerIDsTeamRT,$eName." team:$rtCn  boost differ $ob / $pb" if ($ob ne $pb);
              # if templates differ AND RT template is not static then notify a difference
              push @peerIDsTeamRT,$eName." team:$rtCn  tempListTmpl differ $ot / $pt" if ($ot ne $pt && $pt ne "defaultWeekplan");
            }
          }
        }
      }
    }
  }
  my $ret = "";
  $ret .="\n\n peer list incomplete. Use getConfig to read it."        ."\n    ".(join "\n    ",sort @peerIDsFail   )if(@peerIDsFail);
  $ret .="\n\n peer not defined"                                       ."\n    ".(join "\n    ",sort @peerIDnotDef  )if(@peerIDnotDef);
  $ret .="\n\n peer not verified. Check that peer is set on both sides"."\n    ".(join "\n    ",sort @peerIDsNoPeer )if(@peerIDsNoPeer);
  $ret .="\n\n peering strange - likely not suitable"                  ."\n    ".(join "\n    ",sort @peeringStrange)if(@peeringStrange);
  $ret .="\n\n trigger sent to unpeered device"                        ."\n    ".(join "\n    ",sort @peerIDsTrigUnp)if(@peerIDsTrigUnp);
  $ret .="\n\n trigger sent to undefined device"                       ."\n    ".(join "\n    ",sort @peerIDsTrigUnd)if(@peerIDsTrigUnd);
  $ret .="\n\n aesComReq set but virtual peer is not vccu - won't work"."\n    ".(join "\n    ",sort @peerIDsAES    )if(@peerIDsAES);
  $ret .="\n\n boost or template differ in team"                       ."\n    ".(join "\n    ",sort @peerIDsTeamRT )if(@peerIDsTeamRT);
  
  return  $ret;
}
sub HMinfo_burstCheck(@) { ####################################################
  my @entities = @_;
  my @needBurstMiss;
  my @needBurstFail;
  my @peerIDsCond;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn}         #entity has no channels
          || CUL_HM_peerUsed($eName) != 1              #entity not peered or list incomplete
          || CUL_HM_Get($defs{$eName},$eName,"regList")#option not supported
             !~ m/peerNeedsBurst/);

    my $peerIDs = AttrVal($eName,"peerIDs",undef);    
    next if(!$peerIDs);                                # no peers assigned

    my $devId = substr($defs{$eName}{DEF},0,6);
    foreach (split",",$peerIDs){
      next if ($_ eq "00000000" ||$_ =~m /$devId/);
      my $pn = CUL_HM_id2Name($_);
      $pn =~ s/_chn:/_chn-/; 
      my $prxt = CUL_HM_getRxType($defs{$pn});
      
      next if (!($prxt & 0x82)); # not a burst peer
      my $pnb = ReadingsVal($eName,"R-$pn-peerNeedsBurst",ReadingsVal($eName,".R-$pn-peerNeedsBurst",undef));
      if (!$pnb)           {push @needBurstMiss, "$eName:$pn";}
      elsif($pnb !~ m /on/){push @needBurstFail, "$eName:$pn";}

      if ($prxt & 0x80){# conditional burst - is it on?
        my $pDevN = CUL_HM_getDeviceName($pn);
        push @peerIDsCond," $pDevN for remote $eName" if (ReadingsVal($pDevN,"R-burstRx",ReadingsVal($pDevN,".R-burstRx","")) !~ m /on/);
      }
    }
  }
  my $ret = "";
  $ret .="\n\n peerNeedsBurst cannot be determined"  ."\n    ".(join "\n    ",sort @needBurstMiss) if(@needBurstMiss);
  $ret .="\n\n peerNeedsBurst not set"               ."\n    ".(join "\n    ",sort @needBurstFail) if(@needBurstFail);
  $ret .="\n\n conditionalBurst not set"             ."\n    ".(join "\n    ",sort @peerIDsCond)   if(@peerIDsCond);
  return  $ret;
}
sub HMinfo_paramCheck(@) { ####################################################
  my @entities = @_;
  my @noIoDev;
  my @noID;
  my @idMismatch;
  my @ccuUndef;
  my @perfIoUndef;
  foreach my $eName (@entities){
    if ($defs{$eName}{helper}{role}{dev}){
      my $ehash = $defs{$eName};
      my $pairId =  ReadingsVal($eName,"R-pairCentral", ReadingsVal($eName,".R-pairCentral","undefined"));
      my $IoDev =  $ehash->{IODev} if ($ehash->{IODev});
      my $ioHmId = AttrVal($IoDev->{NAME},"hmId","-");
      my ($ioCCU,$prefIO) = split":",AttrVal($eName,"IOgrp","");
      if ($ioCCU){
        if(   !$defs{$ioCCU}
           || AttrVal($ioCCU,"model","") ne "CCU-FHEM"
           || !$defs{$ioCCU}{helper}{role}{dev}){
          push @ccuUndef,"$eName ->$ioCCU";
        }
        else{
          $ioHmId = $defs{$ioCCU}{DEF};
          if ($prefIO){
            my @pIOa = split(",",$prefIO);
            push @perfIoUndef,"$eName ->$_"  foreach ( grep {!$defs{$_}} @pIOa);
          }            
        }
      }
      if (!$IoDev)                  { push @noIoDev,$eName;}
                                    
      if (   !$defs{$eName}{helper}{role}{vrt} 
          && AttrVal($eName,"model","") ne "CCU-FHEM"){
        if ($pairId eq "undefined") { push @noID,$eName;}
        elsif ($pairId !~ m /$ioHmId/
             && $IoDev )            { push @idMismatch,"$eName paired:$pairId IO attr: ${ioHmId}.";}
      }
    }
  }

  my $ret = "";
  $ret .="\n\n no IO device assigned"             ."\n    ".(join "\n    ",sort @noIoDev)    if (@noIoDev);
  $ret .="\n\n PairedTo missing/unknown"          ."\n    ".(join "\n    ",sort @noID)       if (@noID);
  $ret .="\n\n PairedTo mismatch to IODev"        ."\n    ".(join "\n    ",sort @idMismatch) if (@idMismatch);
  $ret .="\n\n IOgrp: CCU not found"              ."\n    ".(join "\n    ",sort @ccuUndef)   if (@ccuUndef);
  $ret .="\n\n IOgrp: prefered IO undefined"      ."\n    ".(join "\n    ",sort @perfIoUndef)if (@perfIoUndef);
 return  $ret;
}

sub HMinfo_tempList(@) { ######################################################
  my ($hiN,$filter,$action,$fName)=@_;
  $filter = "." if (!$filter);
  $action = "" if (!$action);
  my %dl =("Sat"=>0,"Sun"=>1,"Mon"=>2,"Tue"=>3,"Wed"=>4,"Thu"=>5,"Fri"=>6);
  my $ret;
  
  if    ($action eq "save"){
#    foreach my $eN(HMinfo_getEntities("d")){#search and select channel
#      my $md = AttrVal($eN,"model","");
#      my $chN; #tempList channel name
#      if ($md =~ m/(HM-CC-RT-DN-BoM|HM-CC-RT-DN)/){
#        $chN = $defs{$eN}{channel_04};
#      }
#      elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|HM-CC-TC|HM-TC-IT-WM-W-EU)/){
#        $chN = $defs{$eN}{channel_02};
#      }
#      next if (!$chN || !$defs{$chN} || $chN !~ m/$filter/);
#      print aSave "\nentities:$chN";
#      my @tl = sort grep /tempList(P[123])?[SMFWT]/,keys %{$defs{$chN}{READINGS}};
#      if (scalar @tl != 7 && scalar @tl != 21){
#        print aSave "\nincomplete:$chN only data for ".join(",",@tl);
#        push @incmpl,$chN;
#        next;
#      }
#      foreach my $rd (@tl){
#        print aSave "\n$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
#      }
#    }
    my @chList;
    my @storeList;
    my @incmpl;
    foreach my $eN(HMinfo_getEntities("d")){#search and select channel
      my $md = AttrVal($eN,"model","");
      my $chN; #tempList channel name
      if ($md =~ m/(HM-CC-RT-DN-BoM|HM-CC-RT-DN)/){
        $chN = $defs{$eN}{channel_04};
      }
      elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|HM-CC-TC|HM-TC-IT-WM-W-EU)/){
        $chN = $defs{$eN}{channel_02};
      }
      if ($chN && $defs{$chN} && $chN =~ m/$filter/){
        my @tl = sort grep /tempList(P[123])?[SMFWT]/,keys %{$defs{$chN}{READINGS}};
        if (scalar @tl != 7 && scalar @tl != 21){
          push @incmpl,$chN;
          next;
        }
        else{
          push @chList,$chN;
          push @storeList,"entities:$chN";
          foreach my $rd (@tl){
            #print aSave "\n$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
            push @storeList,"$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
          }
        }
      }
    }
    my  @oldList;
    
    my ($err,@RLines) = FileRead($fName);
    push (@RLines, "#init")  if ($err);
    my $skip = 0;
    foreach(@RLines){
      chomp;
      my $line = $_;
      $line =~ s/\r//g;
      if ($line =~ m/entities:(.*)/){
        my $eFound = $1;
        if (grep /\b$eFound\b/,@chList){
          # renew this entry
          $skip = 1;
        }
        else{
          $skip = 0;
        }
      }
      push @oldList,$line if (!$skip);
    }
    my @WLines = grep !/^$/,(@oldList,@storeList);
    $err = FileWrite($fName,@WLines);
    return "file: $fName error write:$err"  if ($err);

    $ret = "incomplete data for ".join("\n     ",@incmpl) if (scalar@incmpl);
    HMinfo_listOfTempTemplates(); # refresh - maybe there are new entries in the files. 
  }
  elsif ($action =~ m/(verify|restore)/){
    $ret = HMinfo_tempListTmpl($hiN,$filter,"",$action,$fName);
  }
  else{
    $ret = "$action unknown option - please use save, verify or restore";
  }
  return $ret;
}
sub HMinfo_tempListTmpl(@) { ##################################################
  my ($hiN,$filter,$tmpl,$action,$fName)=@_;
  Log 1,"General ----- $action:$fName";
  $filter = "." if (!$filter);
  my %dl =("Sat"=>0,"Sun"=>1,"Mon"=>2,"Tue"=>3,"Wed"=>4,"Thu"=>5,"Fri"=>6);
  my $ret = "";
  my @el ;
  foreach my $eN(HMinfo_getEntities("d")){#search for devices and select correct channel
    next if (!$eN);
    my $md = AttrVal($eN,"model","");
    my $chN; #tempList channel name
    if    ($md =~ m/(HM-CC-RT-DN-BoM|HM-CC-RT-DN)/){$chN = $defs{$eN}{channel_04};}
    elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|-TC)/)    {$chN = $defs{$eN}{channel_02};}
    next if (!$chN || !$defs{$chN} || $chN !~ m/$filter/);
    push @el,$chN;
  }
  return "no entities selected" if (!scalar @el);

  $fName = HMinfo_tempListDefFn($fName);
  $tmpl =  $fName.":".$tmpl if($tmpl);
  my @rs;
  foreach my $name (@el){
   my $tmplDev = $tmpl ? $tmpl
                        : AttrVal($name,"tempListTmpl",$fName.":$name");
    $tmplDev = $fName.":$tmplDev" if ($tmplDev !~ m/:/);
  
    my $r = CUL_HM_tempListTmpl($name,$action,$tmplDev);
    HMinfo_regCheck($name);#clean helper data (shadowReg) after restore
    if($action eq "restore"){
      push @rs,  (keys %{$defs{$name}{helper}{shadowReg}}? "restore: $tmplDev for $name"
                                                         : "passed : $tmplDev for $name")
                                                         ."\n";
    }
    else{
      push @rs,  ($r ? "fail  : $tmplDev for $name: $r"
                     : "passed: $tmplDev for $name")
                 ."\n";
    }
  }

  $ret .= join "",sort @rs;
  return $ret;
}
sub HMinfo_tempListTmplView() { ###############################################
  my %tlEntitys;
  $tlEntitys{$_}{v} = 1 foreach ((devspec2array("TYPE=CUL_HM:FILTER=model=HM-CC-RT.*:FILTER=chanNo=04")
                                 ,devspec2array("TYPE=CUL_HM:FILTER=model=.*-TC.*:FILTER=chanNo=02")));
  my ($n) = devspec2array("TYPE=HMinfo");
  my $defFn = HMinfo_tempListDefFns();
  my @tlFiles = split(";",$defFn);
  $defFn = $defs{$n}{helper}{weekplanListDef};
  
  my @dWoTmpl;    # Device not using templates
  foreach my $d (keys %tlEntitys){
    my ($tf,$tn) = split(":",AttrVal($d,"tempListTmpl","empty"));
    ($tf,$tn) = ($defFn,$tf) if (!defined $tn); # no file given, switch parameter
    if($tn =~ m/^(none|0) *$/){
      push @dWoTmpl,$d;
      delete $tlEntitys{$d};
    }
    else{
      push @tlFiles,$tf;
      $tlEntitys{$d}{t} = ("$tf:".($tn eq "empty"?$d:$tn));
      
      $tlEntitys{$d}{c} = CUL_HM_tempListTmpl($d,"verify",$tlEntitys{$d}{t});
      if ($tlEntitys{$d}{c}){
        $tlEntitys{$d}{c} =~ s/\n//g;
      }
      else{
        $tlEntitys{$d}{c} = "ok" if !($tlEntitys{$d}{c});
      }
    }
  }
  @tlFiles = HMinfo_noDup(@tlFiles);

  my @tlFileMiss;
  foreach my $fName (@tlFiles){#################################
    my ($err,@RLines) = FileRead($fName);
    if ($err){
      push @tlFileMiss,"$fName - $err";
      next;
    }
  }

  my @tNfound;    # templates found in files
  if ($defs{$n}{helper}{weekplanList}){
    push @tNfound, (map{(($_ =~ m/:/) ? $_ : " defaultFile: $_" )}  @{$defs{hm}{helper}{weekplanList}});
  }
  

  ####################################################
  my $ret = "";
  $ret .= "\ndefault templatefile: $defFn\n   ";
  $ret .= "\nfiles referenced but not found:\n   " .join("\n      =>  ",sort @tlFileMiss) if (@tlFileMiss);
  $ret .= "\navailable templates\n   "             .join("\n   "       ,sort @tNfound)    if (@tNfound);
  
  $ret .= "\n\n ---------components-----------\n  template : device : state\n";
  $ret .= "\n     "        .join("\n     "        ,(sort map{s/$defFn:/ defaultFile: /;$_}
                                                         map{"$tlEntitys{$_}{t} : $_ : $tlEntitys{$_}{c}" } 
                                                         keys %tlEntitys));
  $ret .= "\ndevices not using tempList templates:\n      =>  "   .join("\n      =>  ",@dWoTmpl) if (@dWoTmpl);
  return $ret;
}
sub HMinfo_tempListDefFns(@) { #################################################
  my ($fn) = shift;
  $fn = "" if (!defined $fn);
  
  my ($n) = devspec2array("TYPE=HMinfo");
  return HMinfo_getConfigFile($n,"configTempFile",$fn);
}
sub HMinfo_tempListDefFn(@) { #################################################
  my $fn = HMinfo_tempListDefFns(@_);
  $fn =~ s/;.*//; # only use first file - this is default
  return $fn;
}
sub HMinfo_listOfTempTemplates() { ############################################
  # search all entries in tempListFile
  # provide helper: weekplanList & weekplanListDef
  my ($n) =devspec2array("TYPE=HMinfo");
  my $dir = AttrVal($n,"configDir","$attr{global}{modpath}/")."/"; #no dir?  add defDir
  $dir = "./".$dir if ($dir !~ m/^(\.|\/)/);
  my @tFiles = split(";",AttrVal($n,"configTempFile","tempList.cfg"));
  my $tDefault = $dir.$tFiles[0].":";
  my @tmpl;
  
  foreach my $fName (map{$dir.$_}@tFiles){
    my ($err,@RLines) = FileRead($fName);
    next if ($err);
    
    foreach(@RLines){
      chomp;
      my $line = $_;
      $line =~ s/\r//g;
      if($line =~ m/^entities:(.*)/){
        my $l =$1;
        $l =~s/.*://;
        push @tmpl,map{"$fName:$_"}split(",",$l);
      }  
    }
  }
  @tmpl = map{s/$tDefault//;$_} @tmpl;
  $defs{$n}{helper}{weekplanListDef}  = $tDefault;
  $defs{$n}{helper}{weekplanListDef}  =~ s/://;
  $defs{$n}{helper}{weekplanList}     = \@tmpl;

  if ($modules{CUL_HM}{AttrList}){
    my $l = "none,defaultWeekplan,".join(",",@tmpl);
    $modules{CUL_HM}{AttrList} =~ s/ tempListTmpl(.*? )/ tempListTmpl:$l /;
  }
  return ;
}

sub HMinfo_tempListTmplGenLog($$) { ###########################################
  my ($hiN,$fName) = @_;
  $fName = HMinfo_tempListDefFn($fName);

  my @eNl = ();
  my %wdl = ( tempListSun =>"02"
             ,tempListMon =>"03"
             ,tempListTue =>"04"
             ,tempListWed =>"05"
             ,tempListThu =>"06"
             ,tempListFri =>"07"
             ,tempListSat =>"08");
  my @plotL;
  
  my ($err,@RLines) = FileRead($fName);
  return "file: $fName error:$err"  if ($err);

  foreach(@RLines){
    chomp;
    my $line = $_;

    next if($line =~ m/#/);
    if($line =~ m/^entities:/){
      @eNl = ();
      my $eN = $line;
      $line =~s/.*://;
      foreach my $eN (split(",",$line)){
        $eN =~ s/ //g;
        push @eNl,$eN;
      }
    }
    elsif($line =~ m/(R_)?(P[123])?(_?._)?(tempList[SMFWT]..)(.*)\>/){
      my ($p,$wd,$lst) = ($2,$4,$line);
      $lst =~s/.*>//;
      $lst =~ tr/ +/ /;
      $lst =~ s/^ //;
      $lst =~ s/ $//;
      my @tLst = split(" ","00:00 00.0 ".$lst);
      $p = "" if (!defined $p);
      for (my $cnt = 0;$cnt < scalar(@tLst);$cnt+=2){
        last if ($tLst[$cnt] eq "24:00");
        foreach my $e (@eNl){
          push @plotL,"2000-01-$wdl{$wd}_$tLst[$cnt]:00 $e$p $tLst[$cnt+3]";
        }        
      }
    }
  }
  
  my @WLines;
  my %eNh;
  foreach (sort @plotL){
    push @WLines,$_;
    my (undef,$eN) = split " ",$_;
    $eNh{$eN} = 1;
  }
  $err = FileWrite($fName,@WLines);
  return "file: $fName error write:$err"  if ($err);
  HMinfo_tempListTmplGenGplot($fName,keys %eNh);
}
sub HMinfo_tempListTmplGenGplot(@) { ##########################################
  my ($fName,@eN) = @_;
  my $fNfull = $fName;
  $fName =~ s/.cfg$//; # remove extention
  $fName =~ s/.*\///; # remove directory
      #define weekLogF FileLog ./setup/tempList.cfg.log none
      #define wp SVG weekLogF:tempList:CURRENT
      #attr wp fixedrange week
      #attr wp startDate 2000-01-02
  if (!defined($defs{"${fName}_Log"})){
    CommandDefine(undef,"${fName}_Log FileLog ${fNfull}.log none");
  }
  if (!defined($defs{"${fName}_SVG"})){
    CommandDefine(undef,"${fName}_SVG SVG ${fName}_Log:${fName}:CURRENT");
    CommandAttr(undef, "${fName}_SVG fixedrange week");
    CommandAttr(undef, "${fName}_SVG startDate 2000-01-02");
  }

  $fName = "./www/gplot/$fName.gplot";
  my @WLines;
  push @WLines,"# Created by FHEM/98_HMInfo.pm, ";
  push @WLines,"set terminal png transparent size <SIZE> crop";
  push @WLines,"set output '<OUT>.png'";
  push @WLines,"set xdata time";
  push @WLines,"set timefmt \"%Y-%m-%d_%H:%M:%S\"";
  push @WLines,"set xlabel \" \"";
  push @WLines,"set title 'weekplan'";
  push @WLines,"set ytics ";
  push @WLines,"set grid ytics";
  push @WLines,"set ylabel \"Temperature\"";
  push @WLines,"set y2tics ";
  push @WLines,"set y2label \"invisib\"";
  push @WLines,"set y2range [99:99]";
  push @WLines," ";

  my $cnt = 0;
  my ($func,$plot) = ("","\n\nplot");
  foreach my $e (sort @eN){
    $func .= "\n#FileLog 3:$e\.\*::";
    if ($cnt++ < 8){
      $plot .= (($cnt ==0)?"":",")
               ."\\\n     \"<IN>\" using 1:2 axes x1y1 title '$e' ls l$cnt lw 0.5 with steps";
    }
  }
  
  push @WLines,$func.$plot;
  my $err = FileWrite($fName,@WLines);
  return "file: $fName error write:$err"  if ($err);
}

sub HMinfo_getEntities(@) { ###################################################
  my ($filter,$re) = @_;
  my @names;
  my ($doDev,$doChn,$doEmp)= (1,1,1,1,1,1,1,1);
  my ($doIgn,$noVrt,$noPhy,$noAct,$noSen) = (0,0,0,0,0,0,0,0,0,0);
  $filter .= "dc" if ($filter !~ m/d/ && $filter !~ m/c/); # add default
  $re = '.' if (!$re);
  if ($filter){# options provided
    $doDev=$doChn=$doEmp= 0;#change default
    no warnings;
    my @pl = split undef,$filter;
    use warnings;
    foreach (@pl){
      $doDev = 1 if($_ eq 'd');
      $doChn = 1 if($_ eq 'c');
      $doIgn = 1 if($_ eq 'i');
      $noVrt = 1 if($_ eq 'v');
      $noPhy = 1 if($_ eq 'p');
      $noAct = 1 if($_ eq 'a');
      $noSen = 1 if($_ eq 's');
      $doEmp = 1 if($_ eq 'e');
      $doAli = 1 if($_ eq '2');
    }
  }
  # generate entity list
  foreach my $id (sort(keys%{$modules{CUL_HM}{defptr}})){
    next if ($id eq "000000");
    my $eHash = $modules{CUL_HM}{defptr}{$id};
    my $eName = $eHash->{NAME};
    next if ( !$eName || $eName !~ m/$re/);
    my $eIg   = CUL_HM_Get($eHash,$eName,"param","ignore");
    $eIg = "" if ($eIg eq "undefined");
    next if (!$doIgn && $eIg);
    next if (!(($doDev && $eHash->{helper}{role}{dev}) ||
               ($doChn && $eHash->{helper}{role}{chn})));
    next if ( $noVrt && $eHash->{helper}{role}{vrt});
    next if ( $noPhy && !$eHash->{helper}{role}{vrt});
    my $eSt = CUL_HM_Get($eHash,$eName,"param","subType");

    next if ( $noSen && $eSt =~ m/^(THSensor|remote|pushButton|threeStateSensor|sensor|motionDetector|swi)$/);
    next if ( $noAct && $eSt =~ m/^(switch|blindActuator|dimmer|thermostat|smokeDetector|KFM100|outputUnit)$/);
    push @names,$eName;
  }
  return sort(@names);
}
sub HMinfo_getMsgStat() { #####################################################
  my ($hr,$dr,$hs,$ds);
  $hr  =  sprintf("\n  %-14s:","receive hour");
  $hs  =  sprintf("\n  %-14s:","send    hour");
  $dr  =  sprintf("\n  %-14s:","receive day");
  $ds  =  sprintf("\n  %-14s:","send    day");
  $hr .=  sprintf("| %02d",$_) foreach (0..23);
  $hs .=  sprintf("| %02d",$_) foreach (0..23);
  $dr .=  sprintf("|%4s",$_) foreach ("Mon","Tue","Wed","Thu","Fri","Sat","Sun","# 24h");
  $ds .=  sprintf("|%4s",$_) foreach ("Mon","Tue","Wed","Thu","Fri","Sat","Sun","# 24h");
  foreach my $ioD(keys %{$modules{CUL_HM}{stat}{r}}){
    next if ($ioD eq "dummy");
    $hr .=  sprintf("\n      %-10s:",$ioD);
    $hs .=  sprintf("\n      %-10s:",$ioD);
    $dr .=  sprintf("\n      %-10s:",$ioD);
    $ds .=  sprintf("\n      %-10s:",$ioD);
    $hr .=  sprintf("|%3d",$modules{CUL_HM}{stat}{r}{$ioD}{h}{$_}) foreach (0..23);
    $hs .=  sprintf("|%3d",$modules{CUL_HM}{stat}{s}{$ioD}{h}{$_}) foreach (0..23);
    $dr .=  sprintf("|%4d",$modules{CUL_HM}{stat}{r}{$ioD}{d}{$_}) foreach (0..6);
    $ds .=  sprintf("|%4d",$modules{CUL_HM}{stat}{s}{$ioD}{d}{$_}) foreach (0..6);
  
    my ($tdr,$tds);
    $tdr += $modules{CUL_HM}{stat}{r}{$ioD}{h}{$_} foreach (0..23);
    $tds += $modules{CUL_HM}{stat}{s}{$ioD}{h}{$_} foreach (0..23);
    $dr .=  sprintf("|#%4d",$tdr);
    $ds .=  sprintf("|#%4d",$tds);
  }
  my @l = localtime(gettimeofday());
  my $tsts = "\n                 |";
  $tsts .=  "----" foreach (1..$l[2]);
  $tsts .=  ">*" ;
  return  "msg statistics\n"
           .$tsts
           .$hr.$hs
           .$tsts
           .$dr.$ds
           ;
}

sub HMinfo_GetFn($@) {#########################################################
  my ($hash,$name,$cmd,@a) = @_;
  my ($opt,$optEmpty,$filter) = ("",1,"");
  my $ret;
  $doAli = 0;#set default
  
  if (@a && ($a[0] =~ m/^-/) && ($a[0] !~ m/^-f$/)){# options provided
    $opt = $a[0];
    $optEmpty = ($opt =~ m/e/)?1:0;
    shift @a; #remove
  }
  if (@a && $a[0] =~ m/^-f$/){# options provided
    shift @a; #remove
    $filter = shift @a;
  }

  $cmd = "?" if(!$cmd);# by default print options
  #------------ statistics ---------------
  if   ($cmd eq "protoEvents"){##print protocol-events-------------------------
    my ($type) = @a;
    $type = "short" if(!$type);
    my @paramList2;
    my @IOlist;
    my @plSum; push @plSum,0 for (0..9);#prefill
    my $maxNlen = 3;
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      my $id = $defs{$dName}{DEF};
      my $nl = length($dName); 
      $maxNlen = $nl if($nl > $maxNlen);
      my ($found,$para) = HMinfo_getParam($id,
                             ,"protState","protCmdPend"
                             ,"protSnd","protLastRcv","protResnd"
                             ,"protCmdDel","protResndFail","protNack","protIOerr");
      $para =~ s/( last_at|20..-|\|)//g;
      my @pl = split "\t",$para;
      foreach (@pl){
        $_ =~ s/\s+$|//g ;
        $_ =~ s/CMDs_//;
        $_ =~ s/..-.. ..:..:..//g if ($type eq "short");
        $_ =~ s/CMDs // if ($type eq "short");
      }

      for (1..9){
        my ($x) =  $pl[$_] =~ /(\d+)/;
        $plSum[$_] += $x if ($x);
      }
      push @paramList2,[@pl];
      push @IOlist,$defs{$pl[0]}{IODev}->{NAME};
    }
    $maxNlen ++;
    my ($hdr,$ftr);
    my @paramList;
    if ($type eq "short"){
      push @paramList, sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                    @{$_}[0..3],@{$_}[5..9]) foreach(@paramList2);
      $hdr = sprintf("%-${maxNlen}s:%-16s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                               ,"name"
                               ,"State","CmdPend"
                               ,"Snd","Resnd"
                               ,"CmdDel","ResndFail","Nack","IOerr");
      $ftr = sprintf("%-${maxNlen}s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s","sum",@plSum[1..3],@plSum[5..9]);
    }
    else{
      push @paramList, sprintf("%-${maxNlen}s%-17s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s",
                    @{$_}[0..9]) foreach(@paramList2);
      $hdr = sprintf("%-${maxNlen}s:%-16s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s",
                               ,"name"
                               ,"State","CmdPend"
                               ,"Snd","LastRcv","Resnd"
                               ,"CmdDel","ResndFail","Nack","IOerr");
      $ftr = sprintf("%-${maxNlen}20s%-17s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s","sum",@plSum[1..9]);
   }
    
    $ret = $cmd." done:" 
           ."\n    ".$hdr  
           ."\n    ".(join "\n    ",sort @paramList)
           ."\n================================================================================================================"
           ."\n    ".$ftr 
           ."\n"
           ."\n    CUL_HM queue length:$modules{CUL_HM}{prot}{rspPend}"
           ."\n"
           ."\n    requests pending"
           ."\n    ----------------"
           ."\n    autoReadReg          : ".join(" ",@{$modules{CUL_HM}{helper}{qReqConf}})
           ."\n        recent           : ".($modules{CUL_HM}{helper}{autoRdActive}?$modules{CUL_HM}{helper}{autoRdActive}:"none")
           ."\n    status request       : ".join(" ",@{$modules{CUL_HM}{helper}{qReqStat}}) 
           ."\n    autoReadReg wakeup   : ".join(" ",@{$modules{CUL_HM}{helper}{qReqConfWu}})
           ."\n    status request wakeup: ".join(" ",@{$modules{CUL_HM}{helper}{qReqStatWu}})
           ."\n    autoReadTest         : ".join(" ",@{$modules{CUL_HM}{helper}{confCheckArr}})
           ."\n"
           ;
    @IOlist = HMinfo_noDup(@IOlist);
    foreach(@IOlist){
      $_ .= ":".$defs{$_}{STATE}
            .(defined $defs{$_}{helper}{q}
                     ? " pending=".$defs{$_}{helper}{q}{answerPend}
                     : ""
             )
            ." condition:".ReadingsVal($_,"cond","-")
            .(defined $defs{$_}{msgLoadEst}
                     ? "\n            msgLoadEst: ".$defs{$_}{msgLoadEst}
                     : ""
             )
            ;
    }
    $ret .= "\n    IODevs:".(join"\n           ",HMinfo_noDup(@IOlist));
  }  
  elsif($cmd eq "msgStat")    {##print message statistics----------------------
    $ret = HMinfo_getMsgStat();
  }
  elsif($cmd =~ m/^(rssi|rssiG)$/){##print RSSI protocol-events----------------
    my ($type) = (@a,"full");# ugly way to set "full" as default
    my @rssiList = ();
    my %rssiH;
    my @io;
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      foreach my $dest (keys %{$defs{$dName}{helper}{rssi}}){
        my $dispName = $dName;
        my $dispDest = $dest;
        if ($dest =~ m/^at_(.*)/){
          $dispName = $1;
          $dispDest = (($dest =~ m/^to_rpt_/)?"rep_":"").$dName;
        }
        if (AttrVal($dName,"subType","") eq "virtual"){
          my $h = InternalVal($dName,"IODev","");
          $dispDest .= "/$h->{NAME}";
        }
        if ($type eq "full"){
          push @rssiList,sprintf("%-15s ",$dName)
                        .($doAli ? sprintf("%-15s  ",AttrVal($dName,"alias","-")):"")
                        .sprintf("%-15s %-15s %6.1f %6.1f %6.1f<%6.1f %5s"
                                ,$dispName,$dispDest
                                ,$defs{$dName}{helper}{rssi}{$dest}{lst}
                                ,$defs{$dName}{helper}{rssi}{$dest}{avg}
                                ,$defs{$dName}{helper}{rssi}{$dest}{min}
                                ,$defs{$dName}{helper}{rssi}{$dest}{max}
                                ,$defs{$dName}{helper}{rssi}{$dest}{cnt}
                                );
        }
        else{
          my $dir = ($dName eq $dispName)?$dispDest." >":$dispName." <";
          push @io,$dir;
          $rssiH{$dName}{$dir}{min} = $defs{$dName}{helper}{rssi}{$dest}{min};
          $rssiH{$dName}{$dir}{avg} = $defs{$dName}{helper}{rssi}{$dest}{avg};
          $rssiH{$dName}{$dir}{max} = $defs{$dName}{helper}{rssi}{$dest}{max};
        }
      }
    }
    if   ($type eq "reduced"){
      @io = HMinfo_noDup(@io);
      my $s = sprintf("    %15s "," ");
      $s .= sprintf(" %12s",$_)foreach (@io);
      push @rssiList, $s;
      
      foreach my $d(keys %rssiH){
        my $str = sprintf("%-15s  ",$d);
        $str .= sprintf("%-15s  ",AttrVal($d,"alias","-"))if ($doAli);
        foreach my $i(@io){
          $str .= sprintf(" %12.1f"
                  #        ,($rssiH{$d}{$i}{min} ? $rssiH{$d}{$i}{min} : 0)
                           ,($rssiH{$d}{$i}{avg} ? $rssiH{$d}{$i}{avg} : 0)
                  #        ,($rssiH{$d}{$i}{max} ? $rssiH{$d}{$i}{max} : 0)
                           );
        }
        push @rssiList, $str;
      }
      $ret = "\n rssi average \n"
             .(join "\n   ",sort @rssiList);
    }
    elsif($type eq "full"){
      $ret = $cmd." done:"."\n    "."Device          ".($doAli?"Alias            ":"")."receive         from             last   avg      min_max    count"
                        ."\n    ".(join "\n    ",sort @rssiList)
                         ;
    }
  }
  #------------ checks ---------------
  elsif($cmd eq "regCheck")   {##check register--------------------------------
    my @entities = HMinfo_getEntities($opt."v",$filter);
    $ret = $cmd." done:" .HMinfo_regCheck(@entities);
  }
  elsif($cmd eq "peerCheck")  {##check peers-----------------------------------
    my @entities = HMinfo_getEntities($opt,$filter);
    $ret = $cmd." done:" .HMinfo_peerCheck(@entities);
  }
  elsif($cmd eq "configCheck"){##check peers and register----------------------
    if ($hash->{CL}){
      $defs{$name}{helper}{cfgChkResult} = "";
      my $id = ++$hash->{nb}{cnt};
      my $bl = BlockingCall("HMinfo_configCheck", join(",",("$name;$id;$hash->{CL}{NAME}",$opt,$filter)), 
                            "HMinfo_bpPost", 30, 
                            "HMinfo_bpAbort", "$name:0");
      $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
      $ret = "";
    }
    else{
      (undef,undef,undef,$ret) = split(";",HMinfo_configCheck (join(",",("$name;;",$opt,$filter))),4);
      $ret =~s/-ret-/\n/g;
    }
  }
  elsif($cmd eq "configChkResult"){##check peers and register----------------------
    return $defs{$name}{helper}{cfgChkResult} ? $defs{$name}{helper}{cfgChkResult} :"no results available";
  }
  elsif($cmd eq "templateChk"){##template: see if it applies ------------------
    my $id = ++$hash->{nb}{cnt};
    my $bl = BlockingCall("HMinfo_templateChk_Get", join(",",("$name;$id;$hash->{CL}{NAME}",$opt,$filter,@a)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:0");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = "";
  }
  elsif($cmd =~ m/^templateUs(g|gG)$/){##template: see if it applies ------------------
    return HMinfo_templateUsg($opt,$filter,@a);
  }
  #------------ print tables ---------------
  elsif($cmd eq "peerXref")   {##print cross-references------------------------
    my @peerPairs;
    my @peerFhem;
    my @peerUndef;
    my @fheml = ();
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      # search for irregular trigger
      my $peerIDs = AttrVal($dName,"peerIDs","");
      $peerIDs =~ s/00000000,//;
      foreach (grep /^......$/, HMinfo_noDup(map {CUL_HM_name2Id(substr($_,8))} 
                                              grep /^trigDst_/,
                                              keys %{$defs{$dName}{READINGS}})){
        push @peerUndef,"$dName triggers $_"
            if(  ($peerIDs && $peerIDs !~ m/$_/)
               &&("CCU-FHEM" ne AttrVal(CUL_HM_id2Name($_),"model","")));
      }

      #--- check regular references
      next if(!$peerIDs);
      my $dId = unpack 'A6',CUL_HM_name2Id($dName);
      my @pl = ();
      foreach (split",",$peerIDs){
        my $pn = CUL_HM_peerChName($_,$dId);
        $pn =~ s/_chn-01//;
        push @pl,$pn;
        push @fheml,"$_$dName" if ($pn =~ m/^fhem..$/);
      }
      push @peerPairs,$dName." => ".join(" ",(sort @pl)) if (@pl);
    }
    #--- calculate peerings to Central ---
    my %fChn;
    foreach (@fheml){
      my ($fhId,$fhCh,$p)= unpack 'A6A2A*',$_;
      my $fhemCh = "fhem_io_${fhId}_$fhCh";
      $fChn{$fhemCh} = ($fChn{$fhemCh}?$fChn{$fhemCh}.", ":"").$p;
    }
    push @peerFhem,map {"$_ => $fChn{$_}"} keys %fChn;
    $ret = $cmd." done:" ."\n x-ref list"."\n    ".(join "\n    ",sort @peerPairs)
                                         ."\n    ".(join "\n    ",sort @peerFhem)
                         ;
    $ret .=               "\n warning: sensor triggers but no config found"
                                         ."\n    ".(join "\n    ",sort @peerUndef)
            if(@peerUndef)
                         ;
  }
  elsif($cmd eq "templateList"){##template: list templates --------------------
    return HMinfo_templateList($a[0]);
  }
  elsif($cmd eq "register")   {##print register--------------------------------
    my $id = ++$hash->{nb}{cnt};
    my $bl = BlockingCall("HMinfo_register", join(",",("$name;$id;$hash->{CL}{NAME}",$name,$opt,$filter)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:0");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = "";
  }
  elsif($cmd eq "param")      {##print param ----------------------------------
    my @paramList;
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      my $id = $defs{$dName}{DEF};
      my ($found,$para) = HMinfo_getParam($id,@a);
      push @paramList,$para if($found || $optEmpty);
    }
    my $prtHdr = "entity              \t: ";
    $prtHdr .= sprintf("%-20s \t| ",$_)foreach (@a);
    $ret = $cmd." done:"
               ."\n param list"  ."\n    "
               .$prtHdr          ."\n    "
               .(join "\n    ",sort @paramList)
           ;
  }

  elsif($cmd eq "models")     {##print capability, models----------------------
    my $th = \%HMConfig::culHmModel;
    my @model;
    foreach (keys %{$th}){
      my $mode = $th->{$_}{rxt};
      $mode =~ s/\bc\b/config/;
      $mode =~ s/\bw\b/wakeup/;
      $mode =~ s/\bb\b/burst/;
      $mode =~ s/\b3\b/3Burst/;
      $mode =~ s/\bl\b/lazyConf/;
      $mode =~ s/\bf\b/burstCond/;
      $mode =~ s/:/,/g;
      $mode = "normal" if (!$mode);
      my $list = $th->{$_}{lst};
      $list =~ s/.://g;
      $list =~ s/p//;
      my $chan = "";
      foreach (split",",$th->{$_}{chn}){
        my ($n,$s,$e) = split(":",$_);
        $chan .= $s.(($s eq $e)?"":("-".$e))." ".$n.", ";
      }
      push @model,sprintf("%-16s %-24s %4s %-24s %-5s %-5s %s"
                          ,$th->{$_}{st}
                          ,$th->{$_}{name}
                          ,$_
                          ,$mode
                          ,$th->{$_}{cyc}
                          ,$list
                          ,$chan
                          );
    }
    @model = grep /$filter/,sort @model if($filter);
    $ret = $cmd.($filter?" filtered":"").":$filter\n  "
           .sprintf("%-16s %-24s %4s %-24s %-5s %-5s %s\n  "
                          ,"subType"
                          ,"name"
                          ,"ID"
                          ,"supportedMode"
                          ,"Info"
                          ,"List"
                          ,"channels"
                          )
            .join"\n  ", @model;
  }
#  elsif($cmd eq "overview")       { 
#    my @entities = HMinfo_getEntities($opt."d",$filter);
#    return HMI_overview(\@entities,\@a);
#  }                                
  
  elsif($cmd eq "help")       {
    $ret = HMInfo_help();
  }

  else{
    my @cmdLst =     
           ( "help:noArg"
            ,"configCheck"
            ,"configChkResult:noArg"
            ,"param"
            ,"peerCheck"
            ,"peerXref"
            ,"protoEvents"
            ,"msgStat"
            ,"rssi rssiG:full,reduced"
            ,"models"
#            ,"overview"
            ,"regCheck"
            ,"register"
            ,"templateList:".join(",",("all",sort keys%HMConfig::culHmTpl))
            ,"templateChk"
            ,"templateUsg"
            ,"templateUsgG:sortTemplate,sortPeer,noTmpl,all"
            );
            
    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  return $ret;
}
sub HMinfo_SetFn($@) {#########################################################
  my ($hash,$name,$cmd,@a) = @_;
  my @in = @a;
  my ($opt,$optEmpty,$filter) = ("",1,"");
  my $ret;
  $doAli = 0;#set default

  if (@a && ($a[0] =~ m/^-/) && ($a[0] !~ m/^-f$/)){# options provided
    $opt = $a[0];
    $optEmpty = ($opt =~ m/e/)?1:0;
    shift @a; #remove
  }
  if (@a && $a[0] =~ m/^-f$/){# options provided
    shift @a; #remove
    $filter = shift @a;
  }

  $cmd = "?" if(!$cmd);# by default print options
  if   ($cmd =~ m/^clear[G]?/ )     {##actionImmediate: clear parameter--------
    my ($type) = @a;                               
    return "please enter what to clear" if (! $type);
    if ($type eq "msgStat" || $type eq "all" ){
      foreach (keys %{$modules{CUL_HM}{stat}{r}}){
        next if ($_ eq "dummy");
        delete $modules{CUL_HM}{stat}{$_};
        delete $modules{CUL_HM}{stat}{r}{$_};
        delete $modules{CUL_HM}{stat}{s}{$_};
      }
    }
    if ($type eq "msgErrors"){#clear message events for all devices which has problems
      my @devL = split(",",InternalVal($hash->{NAME},"W__protoNames",""));
      push @devL,split(",",InternalVal($hash->{NAME},"CRI__protoNames",""));
      push @devL,split(",",InternalVal($hash->{NAME},"ERR__protoNames",""));
    
      foreach my $dName (HMinfo_noDup(@devL)){
        CUL_HM_Set($defs{$dName},$dName,"clear","msgEvents");
      }
    }
    elsif ($type ne "msgStat"){
      return "unknown parameter - use msgEvents, msgErrors, msgStat, readings, register, rssi, attack or all"
            if ($type !~ m/^(msgEvents|msgErrors|readings|register|oldRegs|rssi|all|attack|trigger)$/);
      $opt .= "d" if ($type =~ m/(msgE|rssi)/);# readings apply to all, others device only
      my @entities;
      foreach my $dName (HMinfo_getEntities($opt,$filter)){
        push @entities,$dName;
        CUL_HM_Set($defs{$dName},$dName,"clear",$type);
      }
      $ret = $cmd.$type." done:" 
	                   ."\n cleared"  
					   ."\n    ".(join "\n    ",sort @entities)
             if($filter);#  no return if no filter 
    }
	HMinfo_status($hash);
  }
  elsif($cmd eq "autoReadReg"){##actionImmediate: re-issue register Read-------
    my @entities;
    foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      next if (!substr(AttrVal($dName,"autoReadReg","0"),0,1));
      CUL_HM_qAutoRead($dName,1);
      push @entities,$dName;
    }
    return $cmd." done:" ."\n triggered:"  ."\n    ".(join "\n    ",sort @entities)
                         ;
  }

  elsif($cmd eq "templateSet"){##template: set of register --------------------
    return HMinfo_templateSet(@a);
  }
  elsif($cmd eq "templateDel"){##template: set of register --------------------
    return HMinfo_templateDel(@a);
  }
  elsif($cmd eq "templateDef"){##template: define one -------------------------
    return HMinfo_templateDef(@a);
  }
  elsif($cmd eq "cpRegs")     {##copy register             --------------------
    return HMinfo_cpRegs(@a);
  }
  elsif($cmd eq "update")     {##update hm counts -----------------------------
    $ret = HMinfo_status($hash);
  }
  elsif($cmd =~ m/tempList[G]?/){##handle thermostat templist from file -------
    my $action = $a[0]?$a[0]:"";
    HMinfo_listOfTempTemplates(); # refresh - maybe there are new entries in the files. 
    if ( $action eq "genPlot"){#generatelog and gplot file 
      $ret = HMinfo_tempListTmplGenLog($name,$a[1]);
    }
    elsif ($action eq "status"){
      $ret = HMinfo_tempListTmplView();
    }
    else{
      my $fn = HMinfo_tempListDefFn($a[1]);
      $ret = HMinfo_tempList($name,$filter,$action,$fn);
    }
  }
  elsif($cmd eq "templateExe"){##template: see if it applies ------------------
    return HMinfo_templateExe($opt,$filter,@a);
  }
  elsif($cmd eq "loadConfig") {##action: loadConfig----------------------------
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);
    $ret = HMinfo_loadConfig($filter,$fn); 
  }
  elsif($cmd eq "verifyConfig"){##action: verifyConfig-------------------------
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);

    if ($hash->{CL}){
      my $id = ++$hash->{nb}{cnt};
      my $bl = BlockingCall("HMinfo_verifyConfig", join(",",("$name;$id;$hash->{CL}{NAME}",$fn)), 
                            "HMinfo_bpPost", 30, 
                            "HMinfo_bpAbort", "$name:$id");
      $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
      $ret = "";
    }
    else{
      $ret = HMinfo_verifyConfig("$name;0;none,$fn"); 
    }
  }
  elsif($cmd eq "purgeConfig"){##action: purgeConfig---------------------------
    my $id = ++$hash->{nb}{cnt};
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);

    my $bl = BlockingCall("HMinfo_purgeConfig", join(",",("$name;$id;none",$fn)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:$id");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = ""; 
  }
  elsif($cmd eq "saveConfig") {##action: saveConfig----------------------------
    my $id = ++$hash->{nb}{cnt};
    my $fn = HMinfo_getConfigFile($name,"configFilename",$a[0]);
    my $bl = BlockingCall("HMinfo_saveConfig", join(",",("$name;$id;none",$fn,$opt,$filter)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:$id");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = $cmd." done:" ."\n saved";
  }
  elsif($cmd eq "archConfig") {##action: archiveConfig-------------------------
    # save config only if register are complete
    $ret = HMinfo_archConfig($hash,$name,$opt,($a[0]?$a[0]:""));
  }
  elsif($cmd eq "x-deviceReplace") {##action: deviceReplace--------------------
    # replace a device with a new one
    $ret = HMinfo_deviceReplace($name,$a[0],$a[1]);
  }
  
  
  ### redirect set commands to get - thus the command also work in webCmd
  elsif($cmd ne '?' && HMinfo_GetFn($hash,$name,"?") =~ m/\b$cmd\b/){##----------------
    unshift @a,"-f",$filter if ($filter);
    unshift @a,"-".$opt if ($opt);
    $ret = HMinfo_GetFn($hash,$name,$cmd,@a);
 }

  else{
    my @cmdLst =     
           ( "autoReadReg"
            ,"clear"    #:msgStat,msgEvents,all,rssi,register,trigger,readings"  
            ,"clearG:msgEvents,msgErrors,msgStat,readings,register,oldRegs,rssi,trigger,attack,all"
            ,"archConfig:-0,-a","saveConfig","verifyConfig","loadConfig","purgeConfig"
            ,"update:noArg"
            ,"cpRegs"
            ,"tempList"
            ,"x-deviceReplace"
            ,"tempListG:verify,status,save,restore,genPlot"
            ,"templateDef","templateSet","templateDel","templateExe"
            );
    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  return $ret;
}

sub HMInfo_help(){ ############################################################
  return    " Unknown argument choose one of "
           ."\n ---checks---"
           ."\n get configCheck [-typeFilter-]                     # perform regCheck and regCheck"
           ."\n get regCheck [-typeFilter-]                        # find incomplete or inconsistant register readings"
           ."\n get peerCheck [-typeFilter-]                       # find incomplete or inconsistant peer lists"
           ."\n ---actions---"
           ."\n set saveConfig [-typeFilter-] [-file-]             # stores peers and register with saveConfig"
           ."\n set archConfig [-a] [-file-]                       # as saveConfig but only if data of entity is complete"
           ."\n set purgeConfig [-file-]                           # purge content of saved configfile "
           ."\n set loadConfig [-typeFilter-] -file-               # restores register and peer readings if missing"
           ."\n set verifyConfig [-typeFilter-] -file-             # compare curent date with configfile,report differences"
           ."\n set autoReadReg [-typeFilter-]                     # trigger update readings if attr autoReadReg is set"
           ."\n set tempList [-typeFilter-][save|restore|verify|status|genPlot][-filename-]# handle tempList of thermostat devices"
           ."\n set x-deviceReplace <old device> <new device>      # WARNING:replace a device with another"
           ."\n  ---infos---"
           ."\n set update                                         # update HMindfo counts"
           ."\n get register [-typeFilter-]                        # devicefilter parse devicename. Partial strings supported"
           ."\n get peerXref [-typeFilter-]                        # peer cross-reference"
           ."\n get models [-typeFilter-]                          # list of models incl native parameter"
           ."\n get protoEvents [-typeFilter-] [short|long]        # protocol status - names can be filtered"
           ."\n get msgStat                                        # view message statistic"
           ."\n get param [-typeFilter-] [-param1-] [-param2-] ... # displays params for all entities as table"
           ."\n get rssi [-typeFilter-]                            # displays receive level of the HM devices"
           ."\n          last: most recent"
           ."\n          avg:  average overall"
           ."\n          range: min to max value"
           ."\n          count: number of events in calculation"
           ."\n  ---clear status---"
           ."\n set clear[G] [-typeFilter-] [msgEvents|readings|msgStat|register|rssi]"
           ."\n                       # delete readings selective"
           ."\n          msgEvents    # delete all protocol-events , msg events"
           ."\n          msgErrors    # delete protoevents for all devices which had errors"
           ."\n          readings     # all readings"
           ."\n          register     # all register-readings"
           ."\n          oldRegs      # outdated register (cleanup) "
           ."\n          rssi         # all rssi data "
           ."\n          msgStat      # message statistics"
           ."\n          trigger      # trigger readings"
           ."\n          attack       # attack related readings"
           ."\n          all          # all of the above"
           ."\n ---help---"
           ."\n get help                            #"
           ."\n ***footnote***"
           ."\n [-nameFilter-]   : only matiching names are processed - partial names are possible"
           ."\n [-modelsFilter-] : any match in the output are searched. "
           ."\n"
           ."\n set cpRegs -src:peer- -dst:peer-"
           ."\n            copy register for a channel or behavior of channel/peer"
           ."\n set templateDef -templateName- -param1[:-param2-...] -description- -reg1-:-val1- [-reg2-:-val2-] ... "
           ."\n                 define a template"
           ."\n set templateSet -entity- -templateName- -peer:[long|short]- [-param1- ...] "
           ."\n                 write register according to a given template"
           ."\n set templateDel -entity- -templateName- -peer:[long|short]-  "
           ."\n                 remove a template set"
           ."\n set templateExe -templateName-"
           ."\n                 write all assigned templates to the file"
           ."\n get templateUsg -templateName-[sortPeer|sortTemplate]"
           ."\n                 show template usage"
           ."\n get templateChk [-typeFilter-] -templateName- -peer:[long|short]- [-param1- ...] "
           ."\n                 compare whether register match the template values"
           ."\n get templateList [-templateName-]         # gives a list of templates or a description of the named template"
           ."\n                  list all currently defined templates or the structure of a given template"
           ."\n ======= typeFilter options: supress class of devices  ===="
           ."\n set -name- -cmd- [-dcasev] [-f -filter-] [params]"
           ."\n      entities according to list will be processed"
           ."\n      d - device   :include devices"
           ."\n      c - channels :include channels"
           ."\n      i - ignore   :include devices marked as ignore"
           ."\n      v - virtual  :supress fhem virtual"
           ."\n      p - physical :supress physical"
           ."\n      a - aktor    :supress actor"
           ."\n      s - sensor   :supress sensor"
           ."\n      e - empty    :include results even if requested fields are empty"
           ."\n "
           ."\n     -f - filter   :regexp to filter entity names "
           ."\n "
           ;
}

sub HMinfo_verifyConfig($) {###################################################
  my ($param) = @_;
  my ($id,$fName) = split ",",$param;
  HMinfo_purgeConfig($param);
  open(aSave, "$fName") || return("$id;Can't open $fName: $!");
  my @elPeer = ();
  my @elReg = ();
  my @entryNF = ();
  my @elOk = ();
  my %nh;
  while(<aSave>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    next if (   $line !~ m/set .* (peerBulk|regBulk) .*/);
    $line =~ s/#.*//;
    my ($cmd1,$eN,$cmd,$param) = split(" ",$line,4);
    if (!$eN || !$defs{$eN}){
      push @entryNF,"$eN deleted";
      next;
    }
    $nh{$eN} = 1 if (!defined $nh{$eN});#
    if($cmd eq "peerBulk"){
      my $ePeer = AttrVal($eN,"peerIDs","");
      if ($param ne $ePeer){
        my @fPeers = grep !/00000000/,split(",",$param);#filepeers
        my @ePeers = grep !/00000000/,split(",",$ePeer);#entitypeers
        my %fp = map {$_=>1} @ePeers;
        my @onlyFile = grep { !$fp{$_} } @fPeers; 
        my %ep = map {$_=>1} @fPeers;
        my @onlyEnt  = grep { !$ep{$_} } @ePeers; 
        push @elPeer,"$eN peer deleted: $_" foreach(@onlyFile);
        push @elPeer,"$eN peer added  : $_" foreach(@onlyEnt);
        $nh{$eN} = 0 if(scalar@onlyFile || scalar @onlyEnt);
      }
    }
    elsif($cmd eq "regBulk"){
      next if($param !~ m/RegL_0[0-9][:\.]/);#allow . and : for the time to convert to . only
      $param =~ s/\.RegL/RegL/;
      my ($reg,$data) = split(" ",$param,2);
      my $eReg = ReadingsVal($eN,($defs{$eN}{helper}{expert}{raw}?"":".").$reg,"");
      my ($ensp,$dnsp) = ($eReg,$data);
      $ensp =~ s/ //g;
      $dnsp =~ s/ //g;
      if ($ensp ne $dnsp){

        my %r; # generate struct with changes addresses
        foreach my $rg(grep /..:../, split(" ",$eReg)){
          my ($a,$d) = split(":",$rg);
          $r{$a}{c} = $d;
        }
        foreach my $rg(grep !/00:00/,grep /..:../, split(" ",$data)){
          my ($a,$d) = split(":",$rg);
          next if (!$a || $a eq "00");
          if   (!defined $r{$a}){$r{$a}{f} = $d;$r{$a}{c} = "";}
          elsif($r{$a}{c} ne $d){$r{$a}{f} = $d;}
          else                  {delete $r{$a};}
        }
        $r{$_}{f} = "" foreach (grep {!defined $r{$_}{f}} grep !/00/,keys %r);
        my @aCh = map {hex($_)} keys %r;#list of changed addresses
        
        # search register valid for thie entity
        my $dN = CUL_HM_getDeviceName($eN);
        my $chn = CUL_HM_name2Id($eN);
        my (undef,$listNo,undef,$peer) = unpack('A6A1A1A*',$reg);
        $chn = (length($chn) == 8)?substr($chn,6,2):"";
        my $culHmRegDefine        =\%HMConfig::culHmRegDefine;
        my @regArr = grep{$culHmRegDefine->{$_}->{l} eq $listNo} 
                     CUL_HM_getRegN(AttrVal($dN,"subType","")
                                   ,AttrVal($dN,"model","")
                                   ,$chn);
        # now identify which register belongs to suspect address. 
        foreach my $rgN (@regArr){
          next if ($culHmRegDefine->{$rgN}{l} ne $listNo);
          my $a = $culHmRegDefine->{$rgN}{a};
          next if (!grep {$a == int($_)} @aCh);
          $a = sprintf("%02X",$a);
          push @elReg,"$eN "
                      .($peer?": peer:$peer ":"")
                      ."addr:$a changed from $r{$a}{f} to $r{$a}{c} - effected RegName:$rgN";
          $nh{$eN} = 0;
        }
        
      }
    }
  }
  close(aSave);
  @elReg = HMinfo_noDup(@elReg);
  foreach (sort keys(%nh)){
    push @elOk,"$_" if($nh{$_});
  }
  my $ret;
  $ret .= "\npeer mismatch:\n   "   .join("\n   ",sort(@elPeer))  if (scalar @elPeer);
  $ret .= "\nreg mismatch:\n   "    .join("\n   ",sort(@elReg ))  if (scalar @elReg);
  $ret .= "\nmissing devices:\n   " .join("\n   ",sort(@entryNF)) if (scalar @entryNF);
#  $ret .= "\nverified:\n   "        .join("\n   ",sort(@elOk))    if (scalar @elOk);
  $ret =~ s/\n/-ret-/g;
  return "$id;$ret";
}
sub HMinfo_loadConfig($@) {####################################################
  my ($filter,$fName)=@_;
  $filter = "." if (!$filter);
  my $ret;
  open(rFile, "$fName") || return("Can't open $fName: $!");
  my @el = ();
  my @elincmpl = ();
  my @entryNF = ();
  my %changes;
  my @rUpdate;
  my @tmplList = (); #collect templates
  while(<rFile>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    next if (   $line !~ m/set .* (peerBulk|regBulk) .*/
             && $line !~ m/(setreading|template.e.) .*/);
    my ($command,$timeStamp) = split("#",$line,2);
    $timeStamp = "1900-01-01 00:00:01" if (!$timeStamp || $timeStamp !~ m /^20..-..-.. /);
    my ($cmd1,$eN,$cmd,$param) = split(" ",$command,4);
    next if ($eN !~ m/$filter/);
    if   ($cmd1 !~ m /^template(Def|Set)$/ && (!$eN || !$defs{$eN})){
      push @entryNF,$eN;
      next;
    }
    if   ($cmd1 eq "setreading"){
      if (!$defs{$eN}{READINGS}{$cmd}){
        $changes{$eN}{$cmd}{d}=$param ;
        $changes{$eN}{$cmd}{t}=$timeStamp ;
      }
      $defs{$eN}{READINGS}{$cmd}{VAL} = $param;
      $defs{$eN}{READINGS}{$cmd}{TIME} = "from archivexx";
    }
    elsif($cmd1 eq "templateDef"){
      if ($eN eq "templateStart"){#if new block we remove all old templates
        @tmplList = ();
      }
      push @tmplList,$line;
    }
    elsif($cmd1 eq "templateSet"){
      my (undef,$eNt,$tpl,$param) = split("=>",$line);
      if (defined($defs{$eNt})){
        if($tpl eq "start"){
          delete $defs{$eNt}{helper}{tmpl};
        }
        else{
          $defs{$eNt}{helper}{tmpl}{$tpl} = $param;
        }
      }
    }
    elsif($cmd eq "peerBulk"){
      next if(!$param);
      $param =~ s/ //g;
      if ($param !~ m/00000000/){
        push @elincmpl,"$eN peerList";
        next;
      }
      if (   $timeStamp 
          && $timeStamp gt ReadingsTimestamp($eN,".peerListRDate","1900-01-01 00:00:01")){
        CUL_HM_ID2PeerList($eN,$_,1) foreach (grep /[0-9A-F]{8}/,split(",",$param));
        push @el,"$eN peerIDs";
        $defs{$eN}{READINGS}{".peerListRDate"}{VAL} = $defs{$eN}{READINGS}{".peerListRDate"}{TIME} = $timeStamp;
      }
    }
    elsif($cmd eq "regBulk"){
      next if($param !~ m/RegL_0[0-9][:\.]/);#allow . and : for the time to convert to . only
      $param =~ s/\.RegL/RegL/;
      $param = ".".$param if (!$defs{$eN}{helper}{expert}{raw});
      my ($reg,$data) = split(" ",$param,2);
      my @rla = CUL_HM_reglUsed($eN);
      next if (!$rla[0]);
      my $rl = join",",@rla;
      $reg =~ s/(RegL_0.):/$1\./;# conversion - : not allowed anymore. Update old versions
      $reg =~ s/_chn-00//; # special: 
      my $r2 = $reg;
      $r2 =~ s/^\.//;
      next if ($rl !~ m/$r2/);
      if ($data !~ m/00:00/){
        push @elincmpl,"$eN reg list:$reg";
        next;
      }
      my $ts = ReadingsTimestamp($eN,$reg,"1900-01-01 00:00:01");
      $ts = "1900-01-01 00:00:00" if ($ts !~ m /^20..-..-.. /);
      if (  !$defs{$eN}{READINGS}{$reg} 
          || $defs{$eN}{READINGS}{$reg}{VAL} !~ m/00:00/
          || (   (  $timeStamp gt $ts
                  ||(   $changes{$eN}
                     && $changes{$eN}{$reg}
                     && $timeStamp gt $changes{$eN}{$reg}{t})
              ))){
        $data =~ s/  //g;
        $changes{$eN}{$reg}{d}=$data;
        $changes{$eN}{$reg}{t}=$timeStamp;
      }
    }
  }

  close(rFile);
  foreach my $eN (keys %changes){
    foreach my $reg (keys %{$changes{$eN}}){
      $defs{$eN}{READINGS}{$reg}{VAL}  = $changes{$eN}{$reg}{d};
      $defs{$eN}{READINGS}{$reg}{TIME} = $changes{$eN}{$reg}{t};
      my ($list,$pN) = ($1,$2) if ($reg =~ m/RegL_(..)\.(.*)/);
      next if (!$list);
      my $pId = CUL_HM_name2Id($pN);# allow devices also as peer. Regfile is korrekt
      # my $pId = CUL_HM_peerChId($pN,substr($defs{$eN}{DEF},0,6));#old - removed
      CUL_HM_updtRegDisp($defs{$eN},$list,$pId);
      push @el,"$eN reg list:$reg";    
    }
  }
  $ret .= "\nadded data:\n     "          .join("\n     ",@el)       if (scalar@el);
  $ret .= "\nfile data incomplete:\n     ".join("\n     ",@elincmpl) if (scalar@elincmpl);
  $ret .= "\nentries not defind:\n     "  .join("\n     ",@entryNF)  if (scalar@entryNF);
  foreach ( @tmplList){
    my @tmplCmd = split("=>",$_);
    next if (!defined $tmplCmd[4]);
    delete $HMConfig::culHmTpl{$tmplCmd[1]};
    my $r = HMinfo_templateDef($tmplCmd[1],$tmplCmd[2],$tmplCmd[3],split(" ",$tmplCmd[4]));
  }
  $tmplDefChange = 0;# all changes are obsolete
  $tmplUsgChange = 0;# all changes are obsolete
  foreach my $tmpN(devspec2array("TYPE=CUL_HM")){
    $defs{$tmpN}{helper}{tmplChg} = 0 if(!$defs{$tmpN}{helper}{role}{vrt});
    CUL_HM_setTmplDisp($defs{$tmpN});#set readings if desired    
  }
  return $ret;
}
sub HMinfo_purgeConfig($) {####################################################
  my ($param) = @_;
  my ($id,$fName) = split ",",$param;
  $fName = "regSave.cfg" if (!$fName);

  open(aSave, "$fName") || return("$id;Can't open $fName: $!");
  my %purgeH;
  while(<aSave>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    if($line =~ m/entity:/){#remove an old entry. Last entry is the final.
      my $name = $line;
      $name =~ s/.*entity://;
      $name =~ s/ .*//;
      delete  $purgeH{$name};
    }
    next if (   $line !~ m/set (.*) (peerBulk|regBulk) (.*)/
             && $line !~ m/(setreading) .*/);
    my ($command,$timeStamp) = split("#",$line,2);
    my ($cmd,$eN,$typ,$p1,$p2) = split(" ",$command,5);
    if ($cmd eq "set" && $typ eq "regBulk"){
      $p1 =~ s/\.RegL_/RegL_/;
      $p1 =~ s/(RegL_0.):/$1\./;#replace old : with .
      $typ .= " $p1";
      $p1 = $p2;
    }
    elsif ($cmd eq "set" && $typ eq "peerBulk"){
      delete $purgeH{$eN}{$cmd}{regBulk};# regBulk needs to be rewritten
    }
    $purgeH{$eN}{$cmd}{$typ} = $p1.($timeStamp?"#$timeStamp":"");
  }
  close(aSave);
  open(aSave, ">$fName") || return("$id;Can't open $fName: $!");
  print aSave "\n\n#============data purged: ".TimeNow();
  foreach my $eN(sort keys %purgeH){
    next if (!defined $defs{$eN}); # remove deleted devices
    print aSave "\n\n#-------------- entity:".$eN." ------------";
    foreach my $cmd (sort keys %{$purgeH{$eN}}){
      my @peers = ();
      foreach my $typ (sort keys %{$purgeH{$eN}{$cmd}}){

        if ($typ eq "peerBulk"){# need peers to identify valid register
          @peers =  map {CUL_HM_id2Name($_)}
                    grep !/(00000000|peerBulk)/,
                    split",",$purgeH{$eN}{$cmd}{$typ};
        }
        elsif($typ =~ m/^regBulk/){#
          if ($typ !~ m/regBulk RegL_..\.(self..)?$/){# only if peer is mentioned
            my $found = 0;
            foreach my $p (@peers){
              if ($typ =~ m/regBulk RegL_..\.$p/){
                $found = 1;
                last;
              }
            }
            next if (!$found);
          }
        }
        print aSave "\n$cmd $eN $typ ".$purgeH{$eN}{$cmd}{$typ};
      }
    }
  }
  print aSave "\n\n";
  print aSave "\n======= finished ===\n";
  close(aSave);
  
  HMinfo_templateWriteDef($fName);
  foreach my $eNt(devspec2array("TYPE=CUL_HM")){
    $defs{$eNt}{helper}{tmplChg} = 1 if(!$defs{$eNt}{helper}{role}{vrt});
  }
  HMinfo_templateWriteUsg($fName);
  
  return "$id;";
}
sub HMinfo_saveConfig($) {#####################################################
  my ($param) = @_;
  my ($id,$fN,$opt,$filter,$strict) = split ",",$param;
  $strict = "" if (!defined $strict);
  foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
    CUL_HM_Get($defs{$dName},$dName,"saveConfig",$fN,$strict);
  }
  HMinfo_templateWrite($fN); 
  HMinfo_purgeConfig($param) if (-e $fN && 1000000 < -s $fN);# auto purge if file to big
  return $id;
}

sub HMinfo_archConfig($$$$) {##################################################
  # save config only if register are complete
  my ($hash,$name,$opt,$fN) = @_;
  my $fn = HMinfo_getConfigFile($name,"configFilename",$fN);
  my $id = ++$hash->{nb}{cnt};
  my $bl = BlockingCall("HMinfo_archConfigExec", join(",",("$name;$id;none"
                                                       ,$fn
                                                       ,$opt)), 
                        "HMinfo_archConfigPost", 30, 
                        "HMinfo_bpAbort", "$name:$id");
  $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
  @{$modules{CUL_HM}{helper}{confUpdt}} = ();
  return ;
}
sub HMinfo_archConfigExec($)  {################################################
  # save config only if register are complete
  my ($id,$fN,$opt) = split ",",shift;
  my @eN;
  if ($opt eq "-a"){@eN = HMinfo_getEntities("d","");}
  else             {@eN = @{$modules{CUL_HM}{helper}{confUpdt}}}
  my @names;
  push @names,(CUL_HM_getAssChnNames($_),$_) foreach(@eN);
  @{$modules{CUL_HM}{helper}{confUpdt}} = ();
  my @archs;
  @eN = ();
  foreach(HMinfo_noDup(@names)){
    if (CUL_HM_peerUsed($_) ==2 ||HMinfo_regCheck($_)){
      push @eN,$_;
    }
    else{
      push @archs,$_;
    }
  }
  HMinfo_saveConfig(join(",",( $id
                              ,$fN
                              ,"c"
                              ,"\^(".join("|",@archs).")\$")
                              ,"strict"));
  return "$id,".(@eN ? join(",",@eN) : "");
}
sub HMinfo_archConfigPost($)  {################################################
  my @arr = split(",",shift);
  my ($name,$id,$cl) = split(";",$arr[0]);
  shift @arr;
  push @{$modules{CUL_HM}{helper}{confUpdt}},@arr;
  delete $defs{$name}{nb}{$id};
  return ;
}

sub HMinfo_getConfigFile($$$) {################################################
  my ($name,$configFile,$fnIn) = @_;#HmInfoName, ConfigFiletype
  my %defaultFN = ( configFilename => "regSave.cfg"
                   ,configTempFile => "tempList.cfg"
                  );
  my $fn = $fnIn ? $fnIn
                 : AttrVal($name,$configFile,$defaultFN{$configFile});
  my @fns;# my file names - coud be more
  foreach my $fnt (split(";",$fn)){
    $fnt = AttrVal($name,"configDir",".") ."\/".$fnt  if ($fnt !~ m/\//); 
    $fnt = AttrVal("global","modpath",".")."\/".$fnt  if ($fnt !~ m/^\//);
    push @fns,$fnt;
  }
  return join(";",@fns);
}

sub HMinfo_deviceReplace($$$){
  my ($hmName,$oldDev,$newDev) = @_;
  my $logH = $defs{$hmName};
  
  my $preReply = $defs{$hmName}{helper}{devRepl}?$defs{$hmName}{helper}{devRepl}:"empty";
  $defs{$hmName}{helper}{devRepl} = "empty";# remove task. 
  
  return "only valid for CUL_HM devices" if(  !$defs{$oldDev}{helper}{role}{dev} 
                                            ||!$defs{$newDev}{helper}{role}{dev} );
  return "use 2 different devices" if ($oldDev eq $newDev);
  
  my $execMode     = 0;# replace will be 2 stage: execMode 0 will not execute any action
  my $prepComplete = 0; # if preparation is aboard (prepComplete =0) the attempt will be ignored
  my $ret = "deviceRepleace - actions";
  if ( $preReply eq $oldDev."-".$newDev){
    $execMode = 1;
    $ret .= "\n        ==>EXECUTING: set $hmName x-deviceReplace $oldDev $newDev";
  }
  else{
    $ret .= "\n       --- CAUTION: this command will reprogramm fhem AND the devices incl peers";
    $ret .= "\n           $oldDev will be replaced by $newDev  ";
    $ret .= "\n           $oldDev can be removed after execution.";
    $ret .= "\n           Peers of the device will also be reprogrammed ";
    $ret .= "\n           command execution may be pending in cmdQueue depending on the device types ";
    $ret .= "\n           thoroughly check the protocoll events";
    $ret .= "\n           NOTE: The command is not revertable!";
    $ret .= "\n                 The command can only be executed once!";
    $ret .= "\n        ==>TO EXECUTE THE COMMAND ISSUE AGAIN: set $hmName x-deviceReplace $oldDev $newDev";
    $ret .= "\n";
  }
  
  #create hash to map old and new device
  my %rnHash;
  $rnHash{old}{dev}=$oldDev;
  $rnHash{new}{dev}=$newDev;
  
  my $oldID = $defs{$oldDev}{DEF}; # device ID old
  my $newID = $defs{$newDev}{DEF}; # device ID new
  foreach my $i(grep /channel_../,keys %{$defs{$oldDev}}){
    # each channel of old device needs a pendant in new
    return "channels incompatible for $oldDev: $i" if (!$defs{$oldDev}{$i} || ! defined $defs{$defs{$oldDev}{$i}});
    $rnHash{old}{$i}=$defs{$oldDev}{$i};

    if ($defs{$newDev}{$i} && defined $defs{$defs{$newDev}{$i}}){
      $rnHash{new}{$i}=$defs{$newDev}{$i};
      return "new channel $i already has peers" if(defined $attr{$rnHash{$_}{new}}{peerIDs} 
                                                   &&      $attr{$rnHash{$_}{new}}{peerIDs} ne "0000000");
    }
    else{
      return "channel list incompatible for $newDev: $i";
    }
  }
  # each old channel has a pendant in new channel
  # lets begin
  #1  --- foreach entity  => rename old>"old-".<name> and new><name>
  #2  --- foreach channel => copy peers (peerBulk)
  #3  --- foreach channel => copy registerlist (regBulk)
  #4  --- foreach channel => copy templates 
  #5  --- foreach peer (search)
  #5a                           => add new peering
  #5b                           => apply reglist for new peer
  #5c                           => remove old peering
  #5d                           => update peer templates
  
  
  my @rename = ();# logging only
  {#1  --- foreach entity  => rename old=>"old-".<name> and new=><name>
    push @rename,"1) rename";
    foreach my $i(sort keys %{$rnHash{old}}){
      my $old = $rnHash{old}{$i};
      if ($execMode){
        AnalyzeCommand("","rename $old old-$old");
        AnalyzeCommand("","rename $rnHash{new}{$i} $old");
      }
      push @rename,"1)- $oldDev - $i: rename $old old-$old";
      push @rename,"1)- $newDev - $i: $rnHash{new}{$i} $old";
    }
    if ($execMode){
      foreach my $name(keys %{$rnHash{old}}){# correct hash internal for further processing
        $rnHash{new}{$name} = $rnHash{old}{$name};
        $rnHash{old}{$name} = "old-".$rnHash{old}{$name};
      }
    }
  }
  {#2  --- foreach channel => copy peers (peerBulk) from old to new
    push @rename,"2) copy peers from old to new";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      next if(!defined $attr{$nameO}{peerIDs});
      my $peerList = join(",",grep !/(00000000|$oldID..)/, split(",",$attr{$nameO}{peerIDs}));
      if ($execMode){
        CUL_HM_Set($defs{$nameN},$nameN,"peerBulk",$peerList,"set") if($peerList);
      }
      push @rename,"2)-      $ch: set $nameN peerBulk $peerList" if($peerList);
    }
  }
  {#3  --- foreach channel => copy registerlist (regBulk)
    push @rename,"3) copy registerlist from old to new";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      foreach my $regL(sort  grep /RegL_..\./,keys %{$defs{$nameO}{READINGS}}){
        my $regLp = $regL; 
        $regLp =~ s/^\.//;#remove leading '.' 
        if ($execMode){
          CUL_HM_Set($defs{$nameN},$nameN,"regBulk",$regLp,$defs{$nameO}{READINGS}{$regL}{VAL});
        }
        push @rename,"3)-      $ch: set $nameN regBulk $regLp ...";
      }
    }
  }
  {#4  --- foreach channel => copy templates 
    push @rename,"4) copy templates from old to new";
    if (eval "defined(&HMinfo_templateDel)"){# check templates
      foreach my $ch(sort keys %{$rnHash{old}}){
        my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
        if($defs{$nameO}{helper}{tmpl}){
          foreach(sort keys %{$defs{$nameO}{helper}{tmpl}}){
            my ($pSet,$tmplID) = split(">",$_);
            my @p = split(" ",$defs{$nameO}{helper}{tmpl}{$_});
            if ($execMode){
              HMinfo_templateSet($nameN,$tmplID,$pSet,@p);
            }
            push @rename,"4)-      $ch: templateSet $nameN,$tmplID,$pSet ".join(",",@p);
          }
        }
      }
    }
  }
  {#5  --- foreach peer (search) - remove peers old peer and set new
    push @rename,"5) for peer devices: remove ols peers";
    foreach my $ch(sort keys %{$rnHash{old}}){
      my ($nameO,$nameN) = ($rnHash{old}{$ch},$rnHash{new}{$ch});
      next if (!$attr{$nameO}{peerIDs});
      foreach my $pId(grep !/(00000000|$oldID..)/, split(",",$attr{$nameO}{peerIDs})){
        my ($oChId,$nChId) = (substr($defs{$nameO}{DEF}."01",0,8)
                             ,substr($defs{$nameN}{DEF}."01",0,8));# obey that device may be channel 01
        my $peerName = CUL_HM_id2Name($pId);

        { #5a) add new peering
          if ($execMode){
            CUL_HM_Set($defs{$peerName},$peerName,"peerBulk",$nChId,"set");  #set new in peer
          }
          push @rename,"5)-5a)-  $ch: set $peerName peerBulk $nChId set";
        }
        { #5b) apply reglist for new peer
          foreach my $regL( grep /RegL_..\.$nameO/,keys %{$defs{$peerName}{READINGS}}){
            my $regLp = $regL; 
            $regLp =~ s/^\.//;#remove leading '.' 
            if ($execMode){
              CUL_HM_Set($defs{$peerName},$peerName,"regBulk",$regLp,$defs{$peerName}{READINGS}{$regL}{VAL});
            }
            push @rename,"5)-5b)-  $ch: set $peerName regBulk $regLp ...";
          }
        }
        { #5c) remove old peering
          if ($execMode){
            CUL_HM_Set($defs{$peerName},$peerName,"peerBulk",$oChId,"unset");#remove old from peer          
          }
          push @rename,"5)-5c)-  $ch: set $peerName peerBulk $oChId unset";
        }
        { #5d) update peer templates
          if (eval "defined(&HMinfo_templateDel)"){# check templates
            if($defs{$peerName}{helper}{tmpl}){
              foreach(keys %{$defs{$peerName}{helper}{tmpl}}){
                my ($pSet,$tmplID) = split(">",$_);
                $pSet =~ s/$nameO/$nameN/;
                my @p = split(" ",$defs{$peerName}{helper}{tmpl}{$_});
                if ($execMode){
                  HMinfo_templateSet($peerName,$tmplID,$pSet,@p);
                }
                push @rename,"5)-5d)-  $ch: templateSet $peerName,$tmplID,$pSet ".join(",",@p);
              }
            }
          }
        }
      }
    }
  }
  push @rename,"5)-5a) add new peering";
  push @rename,"5)-5b) apply reglist for new peer";
  push @rename,"5)-5c) remove old peering";
  push @rename,"5)-5d) update peer templates";
  foreach my $prt(sort @rename){# logging
    $prt =~ s/.\)\-/   /;
    $prt =~ s/   ..\)\-/       /;
    if ($execMode){ Log3 ($logH,3,"Rename: $prt");}
    else          { $ret .= "\n    $prt";         }      
  }
  if (!$execMode){# we passed preparation mode. Remember to execute it next time
    $defs{$hmName}{helper}{devRepl} = $oldDev."-".$newDev;
  }

  return $ret;
}

sub HMinfo_configCheck ($){ ###################################################
  my ($param) = shift;
  my ($id,$opt,$filter) = split ",",$param;
  
  my @entities = HMinfo_getEntities($opt,$filter);
  my $ret = "configCheck done:" .HMinfo_regCheck  (@entities)
                                .HMinfo_peerCheck (@entities)
                                .HMinfo_burstCheck(@entities)
                                .HMinfo_paramCheck(@entities);

  my @td = (devspec2array("model=HM-CC-RT-DN.*:FILTER=chanNo=04"),
            devspec2array("model=HM.*-TC.*:FILTER=chanNo=02"));
  my @tlr;
  foreach my $e (@td){
    next if(!grep /$e/,@entities );
    my $tr = CUL_HM_tempListTmpl($e,"verify",AttrVal($e,"tempListTmpl"
                                                       ,HMinfo_tempListDefFn().":$e"));
                                                       
    next if ($tr eq "unused");
    push @tlr,"$e: $tr" if($tr);
  }
  $ret .= "\n\n templist mismatch \n    ".join("\n    ",sort @tlr) if (@tlr);

  @tlr = ();
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    next if (!defined $defs{$dName}{helper}{tmpl});
    foreach (keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t)=split(">",$_);
      $p = 0 if ($p eq "none");
      my $tck = HMinfo_templateChk($dName,$t,$p,split(" ",$defs{$dName}{helper}{tmpl}{$_}));
      push @tlr,$tck if ($tck);
    }
  }
  $ret .= "\n\n template mismatch \n    ".join("\n    ",sort @tlr) if (@tlr);

  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct
  return "$id;$ret";
}
sub HMinfo_register ($){ ######################################################
  my ($param) = shift;
  my ($id,$name,$opt,$filter) = split ",",$param;
  my $hash = $defs{$name};
  my $RegReply = "";
  my @noReg;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    my $regs = CUL_HM_Get(CUL_HM_name2Hash($dName),$dName,"reg","all");
    if ($regs !~ m/[0-6]:/){
        push @noReg,$dName;
        next;
    }
    my ($peerOld,$ptOld,$ptLine,$peerLine) = ("","",pack('A23',""),pack('A23',""));
    foreach my $reg (split("\n",$regs)){
      my ($peer,$h1) = split ("\t",$reg);
      $peer =~s/ //g;
      if ($peer !~ m/3:/){
        $RegReply .= $reg."\n";
        next;
      }
      next if (!$h1);
      $peer =~s/3://;
      my ($regN,$h2) = split (":",$h1);
      my ($pt,$rN) = unpack 'A2A*',$regN;
      if (!defined($hash->{helper}{r}{$rN})){
        $hash->{helper}{r}{$rN}{v} = "";
        $hash->{helper}{r}{$rN}{u} = pack('A5',"");
      }
      my ($val,$unit) = split (" ",$h2);
      $hash->{helper}{r}{$rN}{v} .= pack('A16',$val);
      $hash->{helper}{r}{$rN}{u} =  pack('A5',"[".$unit."]") if ($unit);
      if ($pt ne $ptOld){
        $ptLine .= pack('A16',$pt);
        $ptOld = $pt;
      }
      if ($peer ne $peerOld){
        $peerLine .= pack('A32',$peer);
        $peerOld = $peer;
      }
    }
    $RegReply .= $peerLine."\n".$ptLine."\n";
    foreach my $rN (sort keys %{$hash->{helper}{r}}){
      $hash->{helper}{r}{$rN} =~ s/(     o..)/$1                /g
            if($rN =~ m/^MultiExec /); #shift thhis reading since it does not appear for short
      $RegReply .=  pack ('A18',$rN)
                   .$hash->{helper}{r}{$rN}{u}
                   .$hash->{helper}{r}{$rN}{v}
                   ."\n";
    }
    delete $hash->{helper}{r};
  }
  my $ret = "No regs found for:".join(",",sort @noReg)."\n\n".$RegReply;
  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct
  return "$id;$ret";
}

sub HMinfo_bpPost($) {#bp finished ############################################
  my ($rep) = @_;
  my ($name,$id,$cl,$ret) = split(";",$rep,4);
  if ($rep =~ m/Can't open/){
    asyncOutput($defs{$cl},$ret);
  }
  else{
    if ($ret && defined $defs{$cl}){
      $ret =~s/-ret-/\n/g; # re-insert new-line
      asyncOutput($defs{$cl},$ret);
    }
  }
  delete $defs{$name}{nb}{$id};
  $defs{$name}{helper}{cfgChkResult} = $ret;
  return;
}
sub HMinfo_bpAbort($) {#bp timeout ############################################
  my ($rep) = @_;
  my ($name,$id) = split(":",$rep);
  delete $defs{$name}{nb}{$id};
  return;
}

sub HMinfo_templateChk_Get($){ ################################################
  my ($param) = shift;
  my ($id,$opt,$filter,@a) = split ",",$param;
  $opt = "" if(!defined $opt);
  my $ret;
  if(@a){
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      unshift @a, $dName;
      $ret .= HMinfo_templateChk(@a);
      shift @a;
    }
  }
  else{
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      next if (!defined $defs{$dName}{helper}{tmpl} || ! $defs{$dName}{helper}{tmpl});
      #$ret .= HMinfo_templateChk(@a);
      foreach my $tmpl(keys %{$defs{$dName}{helper}{tmpl}}){
        my ($p,$t)=split(">",$tmpl);
        $ret .= HMinfo_templateChk($dName,$t,($p eq "none"?0:$p),split(" ",$defs{$dName}{helper}{tmpl}{$tmpl}));
      }
    }
  }    
  $ret = $ret ? $ret
               :"templateChk: passed";
  $ret =~ s/\n/-ret-/g; # replace return with a placeholder - we cannot transfere direct
  return "$id;$ret";
}
sub HMinfo_templateDef(@){#####################################################
  my ($name,$param,$desc,@regs) = @_;
  return "insufficient parameter, no param" if(!defined $param);
  $tmplDefChange = 1;# signal we have a change!
  if ($param eq "del"){
    return "template in use, cannot be deleted" if(HMinfo_templateUsg("","",$name));
    delete $HMConfig::culHmTpl{$name};
    return;
  }
  return "$name already defined, delete it first" if($HMConfig::culHmTpl{$name});
  if ($param eq "fromMaster"){#set hm templateDef <tmplName> fromMaster <master> <(peer:long|0)> <descr>
    my ($master,$pl) = ($desc,@regs);
    return "master $master not defined" if(!$defs{$master});
    @regs = ();
    if ($pl eq "0"){
      foreach my $rdN (grep !/^\.?R-.*-(sh|lg)/,grep /^\.?R-/,keys %{$defs{$master}{READINGS}}){
        my $rdP = $rdN;
        $rdP =~ s/^\.?R-//;
        my ($val) = map{s/ .*//;$_;}$defs{$master}{READINGS}{$rdN}{VAL};
        push @regs,"$rdP:$val";
      }
    }
    else{
      my ($peer,$shlg) = split(":",$pl,2);
      return "peersegment not allowed. use <peer>:(both|short|long)" if($shlg != m/(short|long|both)/);
      $shlg = ($shlg eq "short"?"sh"
             :($shlg eq "long" ?"lg"
             :""));
      foreach my $rdN (grep /^\.?R-$peer-$shlg/,keys %{$defs{$master}{READINGS}}){
        my $rdP = $rdN;
        $rdP =~ s/^\.?R-$peer-$shlg//;
        my ($val) = map{s/ .*//;$_;}$defs{$master}{READINGS}{$rdN}{VAL};
        push @regs,"$rdP:$val";
      }
    }
    $param = "0";
    $desc = "from Master $name > $pl";
  }
  # get description if marked wir ""
  if ($desc =~ m/^"/ && $desc !~ m/^".*"/ ){ # parse "" - search for close and remove regs inbetween
    my $cnt = 0;
    foreach (@regs){
      $desc .= " ".$_;
      $cnt++;
      last if ($desc =~ m/"$/);
    }
    splice @regs,0,$cnt;
  }
  $desc =~ s/"//g;#reduce " to a single pair
#  $desc = "\"".$desc."\"";

  return "insufficient parameter, regs missing" if(@regs < 1);
 
  my $paramNo;
  if($param ne "0"){
    my @p = split(":",$param);
    $HMConfig::culHmTpl{$name}{p} = join(" ",@p) ;
    $paramNo = scalar (@p);
  }
  else{ 
    $HMConfig::culHmTpl{$name}{p} = "";
    $paramNo = 0;
  }
  
  $HMConfig::culHmTpl{$name}{t} = $desc;
  
  foreach (@regs){
    my ($r,$v)=split(":",$_,2);
    if (!defined $v){
      delete $HMConfig::culHmTpl{$name};
      return " empty reg value for $r";
    }
    elsif($v =~ m/^p(\d)/){
      if (($1+1)>$paramNo){
        delete $HMConfig::culHmTpl{$name};
        return ($1+1)." params are necessary, only $paramNo given";
      }
    } 
    $HMConfig::culHmTpl{$name}{reg}{$r} = $v;
  }
}
sub HMinfo_templateSet(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  return "aktor $aName unknown"                           if(!$defs{$aName});
  return "template undefined $tmpl"                       if(!$HMConfig::culHmTpl{$tmpl});
  return "exec set $aName getConfig first"                if(!(grep /RegL_/,keys%{$defs{$aName}{READINGS}}));

  my $tmplID = "$pSet>$tmpl";
  $pSet = ":" if (!$pSet || $pSet eq "none");
  my ($pName,$pTyp) = split(":",$pSet);
  return "give <peer>:[short|long|both] with peer, not $pSet $pName,$pTyp"  if($pName && $pTyp !~ m/(short|long|both)/);
  $pSet = $pTyp ? ($pTyp eq "long" ?"lg"
                 :($pTyp eq "short"?"sh"
                 :""))                  # could be "both"
                 :"";
  my $aHash = $defs{$aName};
#blindActuator - confBtnTime range:1 to 255min special:permanent : 255=permanent 
#blindActuator - intKeyVisib literal:visib,invisib : visibility of internal channel 
  my @regCh;
  foreach (keys%{$HMConfig::culHmTpl{$tmpl}{reg}}){
    my $regN = $pSet.$_;
    my $regV = $HMConfig::culHmTpl{$tmpl}{reg}{$_};
    if ($regV =~m /^p(.)$/) {#replace with User parameter
      return "insufficient values - at least ".$HMConfig::culHmTpl{p}." are $1 necessary" if (@p < ($1+1));
      $regV = $p[$1];
    }
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet",$regN,"?",$pName);
    return "Device doesn't support $regN - template $tmpl not applicable" if ($ret =~ m/failed:/);
    return "peer necessary for template"                                  if ($ret =~ m/peer required/ && !$pName);
    return "Device doesn't support literal $regV for reg $regN"           if ($ret =~ m/literal:/ && $ret !~ m/\b$regV\b/);
    
    if ($ret =~ m/special:/ && $ret !~ m/\b$regV\b/){# if covered by "special" we are good
      my ($min,$max) = ($1,$2) if ($ret =~ m/range:(.*) to (.*) :/);
      $max = 0 if (!$max);
      $max =~ s/([0-9\.]+).*/$1/;
      return "$regV out of range: $min to $max"                           if ($min && ($regV < $min || ($max && $regV > $max)));
    }
    push @regCh,"$regN,$regV";
  }
  foreach (@regCh){#Finally write to shadow register.
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","prep",split(",",$_),$pName);
    return $ret if ($ret);
  }
  my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","exec",split(",",$regCh[0]),$pName);
  HMinfo_templateMark($aHash,$tmplID,@p);
  return $ret;
}
sub HMinfo_templateMark(@){####################################################
  my ($aHash,$tmplID,@p) = @_;
  $aHash->{helper}{tmpl}{$tmplID} = join(" ",@p);
  $tmplUsgChange = 1; # mark change
  $aHash->{helper}{tmplChg} = 1;
  CUL_HM_setTmplDisp($aHash);#set readings if desired
  return;
}
sub HMinfo_templateDel(@){#####################################################
  my ($aName,$tmpl,$pSet) = @_;
  return if (!defined $defs{$aName});
  delete $defs{$aName}{helper}{tmpl}{"$pSet>$tmpl"};
  $tmplUsgChange = 1; # mark change

  $defs{$aName}{helper}{tmplChg} = 1;
  CUL_HM_setTmplDisp($defs{$aName});#set readings if desired
  return;
}
sub HMinfo_templateExe(@){#####################################################
  my ($opt,$filter,$tFilter) = @_;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    next if(!defined $defs{$dName}{helper}{tmpl});
    foreach my $tid(keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t) = split(">",$tid);
      next if($tFilter && $tFilter ne $t);
      HMinfo_templateSet($dName,$t,$p,split(" ",$defs{$dName}{helper}{tmpl}{$tid}));
    }
  }
  return;
}
sub HMinfo_templateUsg(@){#####################################################
  my ($opt,$filter,$tFilter) = @_;
  $tFilter = "all" if (!$tFilter);
  my @ul;# usageList
  my @nul;# NonUsageList
  my %h;
  foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
    my @regLists = map {(my $foo = $_)=~s/^\.//;$foo}CUL_HM_reglUsed($dName);
    foreach my $rl (@regLists){
      if    ($rl =~ m/^RegL_.*\.$/)    {$h{$dName}{general}     = 1;} # no peer register
      elsif ($rl =~ m/^RegL_03\.(.*)$/){$h{$dName}{$1.":short"} = 1;
                                        $h{$dName}{$1.":long"}  = 1;} # peer short and long register
      elsif ($rl =~ m/^RegL_0.\.(.*)$/){$h{$dName}{$1}          = 1;} # peer register
    }
   #.RegL_00.
   #.RegL_01.
   #.RegL_03.FB2_1
   #.RegL_03.FB2_2
   #.RegL_03.dis_01
   #.RegL_03.dis_02
   #.RegL_03.self01
   #.RegL_03.self02

    foreach my $tid(keys %{$defs{$dName}{helper}{tmpl}}){
      my ($p,$t) = split(">",$tid);             #split Peer > Template
      my ($pn,$ls) = split(":",$p);             #split PeerName : list
      
      if   ($tFilter =~ m/^sort.*/){
        if($tFilter eq "sortTemplate"){
          push @ul,sprintf("%-20s|%-15s|%s|%s",$t,$dName,$p,$defs{$dName}{helper}{tmpl}{$tid});
        }
        elsif($tFilter eq "sortPeer"){
          push @ul,sprintf("%-20s|%-15s|%5s:%-20s|%s",$pn,$t,$ls,$dName,$defs{$dName}{helper}{tmpl}{$tid});
        }
      }
      elsif($tFilter eq $t || $tFilter eq "all"){
        my @param;
        my $para = "";
        if($defs{$dName}{helper}{tmpl}{$tid}){
          @param = split(" ",$HMConfig::culHmTpl{$t}{p});
          my @value = split(" ",$defs{$dName}{helper}{tmpl}{$tid});
          for (my $i = 0; $i<scalar(@value); $i++){
           $param[$i] .= ":".$value[$i];
          }
          $para = join(" ",@param);
        }
        push @ul,sprintf("%-20s|%-15s|%s|%s",$dName,$p,$t,$para);
      }
      elsif($tFilter eq "noTmpl"){
        if    ($p eq "none")         {$h{$dName}{general}      = 0;}
        elsif ($ls && $ls eq "short"){$h{$dName}{$pn.":short"} = 0;}
        elsif ($ls && $ls eq "long") {$h{$dName}{$pn.":long"}  = 0;}
        elsif ($ls && $ls eq "both") {$h{$dName}{$pn.":short"} = 0;
                                      $h{$dName}{$pn.":long"}  = 0;}
        elsif ($pn )                 {$h{$dName}{$pn}          = 0;}
      }
    }
    if ($tFilter eq "noTmpl"){
      foreach my $item (keys %{$h{$dName}}){
        push @nul,sprintf("%-20s|%-15s ",$dName,$item) if($h{$dName}{$item});
      }
    }
  }
  if ($tFilter eq "noTmpl"){return  "\n no template for:\n"
                                   .join("\n",sort(@nul)); }
  else{                     return  join("\n",sort(@ul));  }
}

sub HMinfo_templateChk(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  # pset: 0                = template w/o peers
  #       peer / peer:both = template for peer, not extending Long/short
  #       peer:short|long  = template for peerlong or short

  return "aktor $aName - $tmpl:template undefined\n"                       if(!$HMConfig::culHmTpl{$tmpl});
  return "aktor $aName unknown\n"                                          if(!$defs{$aName});
  return "aktor $aName - $tmpl:give <peer>:[short|long|both] wrong:$pSet\n"if($pSet && $pSet !~ m/:(short|long|both)$/);
  $pSet = "0:0" if (!$pSet);
  
  my $repl = "";
  my($pName,$pTyp) = split(":",$pSet);
  if($pName && (grep !/$pName/,ReadingsVal($aName,"peerList" ,""))){
    $repl = "  no peer:$pName\n";
  }
  else{
    my $pRnm = $pName ? $pName."-" : "";
    if ($pName){
      $pRnm = $pName.(($defs{$pName}{helper}{role}{dev})?"_chn-01-":"-");
    }
    my $pRnmLS = $pTyp eq "long"?"lg":($pTyp eq "short"?"sh":"");
    foreach my $rn (keys%{$HMConfig::culHmTpl{$tmpl}{reg}}){
      my $regV;
      my $pRnmChk = $pRnm.($rn !~ m/^(lg|sh)/ ? $pRnmLS :"");
      if ($pRnm){
        $regV    = ReadingsVal($aName,"R-$pRnmChk$rn" ,ReadingsVal($aName,".R-$pRnmChk$rn",undef));
      }
      $regV    = ReadingsVal($aName,"R-".$rn     ,ReadingsVal($aName,".R-".$rn    ,undef)) if (!defined $regV);
      if (defined $regV){
        $regV =~s/ .*//;#strip unit
        my $tplV = $HMConfig::culHmTpl{$tmpl}{reg}{$rn};
        if ($tplV =~m /^p(.)$/) {#replace with User parameter
          return "insufficient data - at least ".$HMConfig::culHmTpl{p}." are $1 necessary"
                                                         if (@p < ($1+1));
          $tplV = $p[$1];
        }
        $repl .= "  $rn :$regV should $tplV \n" if ($regV ne $tplV);
      }
      else{
        $repl .= "  reg not found: $rn :$pRnm\n";
      }
    }
  }
  $repl = "$aName $pSet-> failed\n$repl" if($repl);

  return $repl;
}
sub HMinfo_templateList($){####################################################
  my $templ = shift;
  my $reply = "defined tempates:\n";
  if(!$templ || $templ eq "all"){# list all templates
    foreach (sort keys%HMConfig::culHmTpl){
      next if ($_ =~ m/^tmpl...Change$/); #ignore control
      $reply .= sprintf("%-16s params:%-24s Info:%s\n"
                             ,$_
                             ,$HMConfig::culHmTpl{$_}{p}
                             ,$HMConfig::culHmTpl{$_}{t}
                       );
    }
  }
  elsif( grep /$templ/,keys%HMConfig::culHmTpl ){#details about one template
    $reply = sprintf("%-16s params:%-24s Info:%s\n",$templ,$HMConfig::culHmTpl{$templ}{p},$HMConfig::culHmTpl{$templ}{t});
    foreach (sort keys %{$HMConfig::culHmTpl{$templ}{reg}}){
      my $val = $HMConfig::culHmTpl{$templ}{reg}{$_};
      if ($val =~m /^p(.)$/){
        my @a = split(" ",$HMConfig::culHmTpl{$templ}{p});
        $val = $a[$1];
      }
      $reply .= sprintf("  %-16s :%s\n",$_,$val);
    }
  }
  return $reply;
}
sub HMinfo_templateWrite($){###################################################
  my $fName = shift;
  HMinfo_templateWriteDef($fName) if ($tmplDefChange);
  HMinfo_templateWriteUsg($fName) if ($tmplUsgChange);
  return;
}
sub HMinfo_templateWriteDef($){################################################
  my $fName = shift;
  $tmplDefChange = 0; # reset changed bits
  my @tmpl =();
  #set templateDef <templateName> <param1[:<param2>...] <description> <reg1>:<val1> [<reg2>:<val2>] ... 
  foreach my $tpl(sort keys%HMConfig::culHmTpl){
    next if ($tpl =~ m/^tmpl...Change$/  ||!defined$HMConfig::culHmTpl{$tpl}{reg}); 
    my @reg =();
    foreach (keys%{$HMConfig::culHmTpl{$tpl}{reg}}){
      push @reg,$_.":".$HMConfig::culHmTpl{$tpl}{reg}{$_};
    }
    push @tmpl,sprintf("templateDef =>%s=>%s=>\"%s\"=>%s"
                           ,$tpl
                           ,($HMConfig::culHmTpl{$tpl}{p}?join(":",split(" ",$HMConfig::culHmTpl{$tpl}{p})):"0")
                           ,$HMConfig::culHmTpl{$tpl}{t}
                           ,join(" ",@reg)
                     );
  }

  open(aSave, ">>$fName") || return("Can't open $fName: $!");
  #important - this is the header - prior entires in the file will be ignored
  print aSave "\n\ntemplateDef templateStart Block stored:".TimeNow()."*******************\n\n";
  print aSave "\n".$_ foreach(sort @tmpl);
  print aSave "\n======= finished templates ===\n";
  close(aSave);

  return;
}
sub HMinfo_templateWriteUsg($){################################################
  my $fName = shift;
  $tmplUsgChange = 0; # reset changed bits
  my @tmpl =();
  foreach my $eN(sort (devspec2array("TYPE=CUL_HM"))){
    next if($defs{$eN}{helper}{role}{vrt} || !$defs{$eN}{helper}{tmplChg});
    push @tmpl,sprintf("templateSet =>%s=>start",$eN);# indicates: all entries before are obsolete
    $defs{$eN}{helper}{tmplChg} = 0;
    if (defined $defs{$eN}{helper}{tmpl}){
      foreach my $tid(keys %{$defs{$eN}{helper}{tmpl}}){
        my ($p,$t) = split(">",$tid);
        next if (!defined$HMConfig::culHmTpl{$t});
        push @tmpl,sprintf("templateSet =>%s=>%s=>%s"
                             ,$eN
                             ,$tid
                             ,$defs{$eN}{helper}{tmpl}{$tid}
                       );
      }
    }
  }
  if (@tmpl){
    open(aSave, ">>$fName") || return("Can't open $fName: $!");
    #important - this is the header - prior entires in the file will be ignored
    print aSave "\n".$_ foreach(@tmpl);
    print aSave "\n======= finished templates ===\n";
    close(aSave);
  }
  return;
}

sub HMinfo_cpRegs(@){##########################################################
  my ($srcCh,$dstCh) = @_;
  my ($srcP,$dstP,$srcPid,$dstPid,$srcRegLn,$dstRegLn);
  ($srcCh,$srcP) = split(":",$srcCh,2);
  ($dstCh,$dstP) = split(":",$dstCh,2);
  return "source channel $srcCh undefined"      if (!$defs{$srcCh});
  return "destination channel $srcCh undefined" if (!$defs{$dstCh});
  #compare source and destination attributes
#  return "model  not compatible" if (CUL_HM_Get($ehash,$eName,"param","model") ne
#                                     CUL_HM_Get($ehash,$eName,"param","model"));

  if ($srcP){# will be peer related copy
    if   ($srcP =~ m/self(.*)/)      {$srcPid = substr($defs{$srcCh}{DEF},0,6).sprintf("%02X",$1)}
    elsif($srcP =~ m/^[A-F0-9]{8}$/i){$srcPid = $srcP;}
    elsif($srcP =~ m/(.*)_chn-(..)/) {$srcPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$srcP})              {$srcPid = $defs{$srcP}{DEF}.$2;}

    if   ($dstP =~ m/self(.*)/)      {$dstPid = substr($defs{$dstCh}{DEF},0,6).sprintf("%02X",$1)}
    elsif($dstP =~ m/^[A-F0-9]{8}$/i){$dstPid = $dstP;}
    elsif($dstP =~ m/(.*)_chn-(..)/) {$dstPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$dstP})              {$dstPid = $defs{$dstP}{DEF}.$2;}

    return "invalid peers src:$srcP dst:$dstP" if(!$srcPid || !$dstPid);
    return "source peer not in peerlist"       if ($attr{$srcCh}{peerIDs} !~ m/$srcPid/);
    return "destination peer not in peerlist"  if ($attr{$dstCh}{peerIDs} !~ m/$dstPid/);

    if   ($defs{$srcCh}{READINGS}{"RegL_03.".$srcP})  {$srcRegLn =  "RegL_03.".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_03.".$srcP}) {$srcRegLn = ".RegL_03.".$srcP}
    elsif($defs{$srcCh}{READINGS}{"RegL_04.".$srcP})  {$srcRegLn =  "RegL_04.".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_04.".$srcP}) {$srcRegLn = ".RegL_04.".$srcP}
    $dstRegLn = $srcRegLn;
    $dstRegLn =~ s/:.*/:/;
    $dstRegLn .= $dstP;
  }
  else{
    if   ($defs{$srcCh}{READINGS}{"RegL_01."})  {$srcRegLn = "RegL_01."}
    elsif($defs{$srcCh}{READINGS}{".RegL_01."}) {$srcRegLn = ".RegL_01."}
    $dstRegLn = $srcRegLn;
  }
  return "source register not available"     if (!$srcRegLn);
  return "regList incomplete"                if ($defs{$srcCh}{READINGS}{$srcRegLn}{VAL} !~ m/00:00/);

  # we habe a reglist with termination, source and destination peer is checked. Go copy
  my $srcData = $defs{$srcCh}{READINGS}{$srcRegLn}{VAL};
  $srcData =~ s/00:00//; # remove termination
  my ($ret,undef) = CUL_HM_Set($defs{$dstCh},$dstCh,"regBulk",$srcRegLn,split(" ",$srcData));
  return $ret;
}
sub HMinfo_noDup(@) {#return list with no duplicates###########################
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep {defined($_)} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}


1;
=pod
=item command
=item summary    support and control instance for wireless homematic devices and IOs
=item summary_DE Unterstützung und Ueberwachung von Homematic funk devices und IOs 

=begin html


<a name="HMinfo"></a>
<h3>HMinfo</h3>
<ul>

  HMinfo is a module to support getting an overview  of
  eQ-3 HomeMatic devices as defines in <a href="#CUL_HM">CUL_HM</a>. <br><br>
  <B>Status information and counter</B><br>
  HMinfo gives an overview on the CUL_HM installed base including current conditions.
  Readings and counter will not be updated automatically  due to performance issues. <br>
  Command <a href="#HMinfoupdate">update</a> must be used to refresh the values. 
  <ul><code><br>
           set hm update<br>
  </code></ul><br>
  Webview of HMinfo providee details, basically counter about how
  many CUL_HM entities experience exceptional conditions. It contains
  <ul>
      <li>Action Detector status</li>
      <li>CUL_HM related IO devices and condition</li>
      <li>Device protocol events which are related to communication errors</li>
      <li>count of certain readings (e.g. batterie) and conditions - <a href="#HMinfoattr">attribut controlled</a></li>
      <li>count of error condition in readings (e.g. overheat, motorErr) - <a href="#HMinfoattr">attribut controlled</a></li>
  </ul>
  <br>

  It also allows some HM wide commands such
  as store all collected register settings.<br><br>

  Commands are executed on all HM entities.
  If applicable and evident execution is restricted to related entities.
  e.g. rssi is executed on devices only since channels do not support rssi values.<br><br>
  <a name="HMinfoFilter"><b>Filter</b></a>
  <ul>  can be applied as following:<br><br>
        <code>set &lt;name&gt; &lt;cmd&gt; &lt;filter&gt; [&lt;param&gt;]</code><br>
        whereby filter has two segments, typefilter and name filter<br>
        [-dcasev] [-f &lt;filter&gt;]<br><br>
        filter for <b>types</b> <br>
        <ul>
            <li>d - device   :include devices</li>
            <li>c - channels :include channels</li>
            <li>v - virtual  :supress fhem virtual</li>
            <li>p - physical :supress physical</li>
            <li>a - aktor    :supress actor</li>
            <li>s - sensor   :supress sensor</li>
            <li>e - empty    :include results even if requested fields are empty</li>
            <li>2 - alias    :display second name alias</li>
        </ul>
        and/or filter for <b>names</b>:<br>
        <ul>
            <li>-f &lt;filter&gt;  :regexp to filter entity names </li>
        </ul>
        Example:<br>
        <ul><code>
           set hm param -d -f dim state # display param 'state' for all devices whos name contains dim<br>
           set hm param -c -f ^dimUG$ peerList # display param 'peerList' for all channels whos name is dimUG<br>
           set hm param -dcv expert # get attribut expert for all channels,devices or virtuals<br>
        </code></ul>
  </ul>
  <br>
  <a name="HMinfodefine"><b>Define</b></a>
  <ul>
    <code>define &lt;name&gt; HMinfo</code><br>
    Just one entity needs to be defined without any parameter.<br>
  </ul>
  <br>
  <a name="HMinfoget"><b>Get</b></a>
  <ul>
      <li><a name="#HMinfomodels">models</a><br>
          list all HM models that are supported in FHEM
      </li>
      <li><a name="#HMinfoparam">param</a> <a href="#HMinfoFilter">[filter]</a> &lt;name&gt; &lt;name&gt;...<br>
          returns a table of parameter values (attribute, readings,...)
          for all entities as a table
      </li>
      <li><a name="#HMinforegister">register</a> <a href="#HMinfoFilter">[filter]</a><br>
          provides a tableview of register of an entity
      </li>
      <li><a name="#HMinforegCheck">regCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check on register readings for completeness
      </li>
      <li><a name="#HMinfopeerCheck">peerCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check on peers. If a peer is set in a channel
          it will check wether the peer also exist on the opposit side.
      </li>
      <li><a name="#HMinfopeerXref">peerXref</a> <a href="#HMinfoFilter">[filter]</a><br>
          provides a cross-reference on peerings, a kind of who-with-who summary over HM
      </li>
      <li><a name="#HMinfoconfigCheck">configCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check of HM settings. It includes regCheck and peerCheck
      </li>
      <li><a name="#HMinfoconfigChkResult">configChkResult</a><br>
          returns the results of a previous executed configCheck
      </li>
      <li><a name="#HMinfotemplateList">templateList [&lt;name&gt;]</a><br>
          list defined templates. If no name is given all templates will be listed<br>
      </li>
      <li><a name="#HMinfotemplateUsg">templateUsg</a> &lt;template&gt; [sortPeer|sortTemplate]<br>
          templare usage<br>
          template filters the output
      </li>
      <li><a name="#HMinfomsgStat">msgStat</a> <a href="#HMinfoFilter">[filter]</a><br>
          statistic about message transferes over a week<br>
      </li>
      <li><a name="#HMinfoprotoEvents">protoEvents </a><a href="#HMinfoFilter">[filter]</a> <br>
          <B>important view</B> about pending commands and failed executions for all devices in a single table.<br>
          Consider to clear this statistic use <a name="#HMinfoclear">clear msgEvents</a>.<br>
      </li>
      <li><a name="#HMinforssi">rssi </a><a href="#HMinfoFilter">[filter]</a><br>
          statistic over rssi data for HM entities.<br>
      </li>

      <li><a name="#HMinfotemplateChk">templateChk</a> <a href="#HMinfoFilter">[filter]</a> &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         verifies if the register-readings comply to the template <br>
         Parameter are identical to <a href="#HMinfotemplateSet">templateSet</a><br>
         The procedure will check if the register values match the ones provided by the template<br>
         If no peer is necessary use <b>none</b> to skip this entry<br>
        Example to verify settings<br>
        <ul><code>
         set hm templateChk -f RolloNord BlStopUpLg none         1 2 # RolloNord, no peer, parameter 1 and 2 given<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:long    # RolloNord peerName, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName         # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:all     # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg all:long         # RolloNord any peer, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg all              # RolloNord any peer,long and short<br>
         set hm templateChk -f Rollo.*   BlStopUpLg all              # each Rollo* any peer,long and short<br>
         set hm templateChk BlStopUpLg                               # each entities<br>
         set hm templateChk                                          # all assigned templates<br>
         set hm templateChk sortTemplate                             # all assigned templates sortiert nach Template<br>
         set hm templateChk sortPeer                                 # all assigned templates sortiert nach Peer<br>
        </code></ul>
      </li>
  </ul>
  <a name="HMinfoset"><b>Set</b></a>
  <ul>
    Even though the commands are a get funktion they are implemented
    as set to allow simple web interface usage<br>
      <li><a name="#HMinfoupdate">update</a><br>
          updates HM status counter.
      </li>

      <li><a name="#HMinfoautoReadReg">autoReadReg</a> <a href="#HMinfoFilter">[filter]</a><br>
          schedules a read of the configuration for the CUL_HM devices with attribut autoReadReg set to 1 or higher.
      </li>
      <li><a name="#HMinfoclear">clear</a> <a href="#HMinfoFilter">[filter]</a> [msgEvents|readings|msgStat|register|rssi]<br>
          executes a set clear ...  on all HM entities<br>
          <ul>
          <li>protocol relates to set clear msgEvents</li>
          <li>set clear msgEvents for all device with protocol errors</li>
          <li>readings relates to set clear readings</li>
          <li>rssi clears all rssi counters </li>
          <li>msgStat clear HM general message statistics</li>
          <li>register clears all register-entries in readings</li>
          </ul>
      </li>
      <li><a name="#HMinfosaveConfig">saveConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          performs a save for all HM register setting and peers. See <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>.<br>
          <a ref="#HMinfopurgeConfig">purgeConfig</a> will be executed automatically if the stored filesize exceeds 1MByte.<br>
      </li>
      <li><a name="#HMinfoarchConfig">archConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          performs <a href="#HMinfosaveConfig">saveConfig</a> for entities that appeare to have achanged configuration.
          It is more conservative that saveConfig since incomplete sets are not stored.<br>
          Option -a force an archieve for all devices that have a complete set of data<br>
      </li>
      <li><a name="#HMinfoloadConfig">loadConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          loads register and peers from a file saved by <a href="#HMinfosaveConfig">saveConfig</a>.<br>
          It should be used carefully since it will add data to FHEM which cannot be verified. No readings will be replaced, only 
          missing readings will be added. The command is mainly meant to be fill in readings and register that are 
          hard to get. Those from devices which only react to config may not easily be read. <br>
          Therefore it is strictly up to the user to fill valid data. User should consider using autoReadReg for devices 
          that can be read.<br>
          The command will update FHEM readings and attributes. It will <B>not</B> reprogramm any device.
      </li>
      <li><a name="#HMinfopurgeConfig">purgeConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          purge (reduce) the saved config file. Due to the cumulative storage of the register setting
          purge will use the latest stored readings and remove older one. 
          See <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>.
      </li>
      <li><a name="#HMinfoverifyConfig">verifyConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          Compare date in config file to the currentactive data and report differences. 
          Possibly usable with a known-good configuration that was saved before. 
          It may make sense to purge the config file before.
          See <a href="#CUL_HMpurgeConfig">CUL_HM purgeConfig</a>.
      </li>

      
         <br>
      <li><a name="#HMinfotempList">tempList</a> <a href="#HMinfoFilter">[filter] [save|restore|verify|status|genPlot] [&lt;file&gt;]</a><br>
          this function supports handling of tempList for thermstates.
          It allows templists to be saved in a separate file, verify settings against the file
          and write the templist of the file to the devices. <br>
          <ul>
          <li><B>save</B> saves tempList readings of the system to the file. <br>
              Note that templist as available in FHEM is put to the file. It is up to the user to make
              sure the data is actual<br>
              Storage is not cumulative - former content of the file will be removed</li>
          <li><B>restore</B> available templist as defined in the file are written directly 
              to the device</li>
          <li><B>verify</B> file data is compared to readings as present in FHEM. It does not
              verify data in the device - user needs to ensure actuallity of present readings</li>
          <li><B>status</B> gives an overview of templates being used by any CUL_HM thermostat. It alls showes 
            templates being defined in the relevant files.
            <br></li>
          <li><B>genPlot</B> generates a set of records to display templates graphicaly.<br>
            Out of the given template-file it generates a .log extended file which contains log-formated template data. timestamps are 
            set to begin Year 2000.<br>
            A prepared .gplot file will be added to gplot directory.<br>
            Logfile-entity <file>_Log will be added if not already present. It is necessary for plotting.<br>
            SVG-entity <file>_SVG will be generated if not already present. It will display the graph.<br>
            <br></li>
          <li><B>file</B> name of the file to be used. Default: <B>tempList.cfg</B></li>
          <br>
          <li><B>filename</B> is the name of the file to be used. Default ist <B>tempList.cfg</B></li>
          File example<br>
          <ul><code>
               entities:HK1_Climate,HK2_Clima<br>
               tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0<br>
               tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               entities:hk3_Climate<br>
               tempListFri>06:00 17.0 12:00 21.0 23:00 20.0 24:00 19.5<br>
               tempListMon>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSat>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSun>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListThu>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListTue>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListWed>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
         </code></ul>
         File keywords<br>
         <li><B>entities</B> comma separated list of entities which refers to the temp lists following.
           The actual entity holding the templist must be given - which is channel 04 for RTs or channel 02 for TCs</li>
         <li><B>tempList...</B> time and temp couples as used in the set tempList commands</li>
         </ul>
         <br>
     </li>
         <br>
      <li><a name="#HMinfocpRegs">cpRegs &lt;src:peer&gt; &lt;dst:peer&gt; </a><br>
          allows to copy register, setting and behavior of a channel to
          another or for peers from the same or different channels. Copy therefore is allowed
          intra/inter device and intra/inter channel. <br>
         <b>src:peer</b> is the source entity. Peer needs to be given if a peer behabior beeds to be copied <br>
         <b>dst:peer</b> is the destination entity.<br>
         Example<br>
         <ul><code>
          set hm cpRegs blindR blindL  # will copy all general register (list 1)for this channel from the blindR to the blindL entity.
          This includes items like drive times. It does not include peers related register (list 3/4) <br>
          set hm cpRegs blindR:Btn1 blindL:Btn2  # copy behavior of Btn1/blindR relation to Btn2/blindL<br>
          set hm cpRegs blindR:Btn1 blindR:Btn2  # copy behavior of Btn1/blindR relation to Btn2/blindR, i.e. inside the same Actor<br>
         </code></ul>
         <br>
         Restrictions:<br>
         <ul>
           cpRegs will <u>not add any peers</u> or read from the devices. It is up to the user to read register in advance<br>
           cpRegs is only allowed between <u>identical models</u><br>
           cpRegs expets that all <u>readings are up-to-date</u>. It is up to the user to ensure data consistency.<br>
         </ul>
      </li>
      <li><a name="#HMinfotemplateDef">templateDef &lt;name&gt; &lt;param&gt; &lt;desc&gt; &lt;reg1:val1&gt; [&lt;reg2:val2&gt;] ...</a><br>
        define a template.<br>
        <b>param</b> gives the names of parameter necesary to execute the template. It is template dependant
                     and may be onTime or brightnesslevel. A list of parameter needs to be separated with colon<br>
                     param1:param2:param3<br>
                     if del is given as parameter the template is removed<br>
        <b>desc</b> shall give a description of the template<br>
        <b>reg:val</b> is the registername to be written and the value it needs to be set to.<br>
        In case the register is from link set and can destinguist between long and short it is necessary to leave the
        leading sh or lg off. <br>
        if parameter are used it is necessary to enter p. as value with p0 first, p1 second parameter
        <br>
        Example<br>
        <ul><code>
          set hm templateDef SwOnCond level:cond "my description" CtValLo:p0 CtDlyOn:p1 CtOn:geLo<br>
          set hm templateDef SwOnCond del # delete a template<br>
          set hm templateDef SwOnCond fromMaster &lt;masterChannel&gt; &lt;peer:[long|short]&gt;# define a template with register as of the example<br>
          set hm templateDef SwOnCond fromMaster myChannel peerChannel:long  # <br>
        </code></ul>
      </li>
      <li><a name="#HMinfotemplateSet">templateSet</a> &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         sets a bunch of register accroding to a given template. Parameter may be added depending on
         the template setup. <br>
         templateSet will collect and accumulate all changes. Finally the results are written streamlined.<br>
        <b>entity:</b> peer is the source entity. Peer needs to be given if a peer behabior beeds to be copied <br>
        <b>template:</b> one of the programmed template<br>
        <b>peer:</b> [long|short]:if necessary a peer needs to be given. If no peer is used enter '0'.
                 with a peer it should be given whether it is for long or short keypress<br>
        <b>param:</b> number and meaning of parameter depends on the given template<br>
        Example could be (templates not provided, just theoretical)<br>
        <ul><code>
          set hm templateSet Licht1 staircase FB1:short 20  <br>
          set hm templateSet Licht1 staircase FB1:long 100  <br>
        </code></ul>
        Restrictions:<br>
        <ul>
          User must ensure to read configuration prior to execution.<br>
          templateSet may not setup a complete register block but only a part if it. This is up to template design.<br>
          <br>

        </ul>
      </li>
      <li><a name="#HMinfotemplateDel">templateDel</a> &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; ]<br>
         remove a template installed by templateSet
          <br>

      </li>
      <li><a name="#HMinfotemplateExe">templateExe</a> &lt;template&gt; <br>
          executes the register write once again if necessary (e.g. a device had a reset)<br>
      </li>
      <li><a name="#HMinfodeviceReplace">x-deviceReplace</a> &lt;oldDevice&gt; &lt;newDevice&gt; <br>
          replacement of an old or broken device with a replacement. The replacement needs to be compatible - FHEM will check this partly. It is up to the user to use it carefully. <br>
          The command needs to be executed twice for safety reasons. The first call will return with CAUTION remark. Once issued a second time the old device will be renamed, the new one will be named as the old one. Then all peerings, register and templates are corrected as best as posible. <br>
          NOTE: once the command is executed devices will be reconfigured. This cannot be reverted automatically.  <br>
          Replay of teh old confg-files will NOT restore the former configurations since also registers changed! Exception: proper and complete usage of templates!<br>
          In case the device is configured using templates with respect to registers a verification of the procedure is very much secure. Otherwise it is up to the user to supervice message flow for transmission failures. <br>
      </li>
  </ul>
  <br>

  <br><br>
  <a name="HMinfoattr"><b>Attributes</b></a>
   <ul>
     <li><a name="#HMinfosumStatus">sumStatus</a><br>
       Warnings: list of readings that shall be screend and counted based on current presence.
       I.e. counter is the number of entities with this reading and the same value.
       Readings to be searched are separated by comma. <br>
       Example:<br>
       <ul><code>
         attr hm sumStatus battery,sabotageError<br>
       </code></ul>
       will cause a reading like<br>
       W_sum_batterie ok:5 low:3<br>
       W_sum_sabotageError on:1<br>
       <br>
       Note: counter with '0' value will not be reported. HMinfo will find all present values autonomously<br>
       Setting is meant to give user a fast overview of parameter that are expected to be system critical<br>
     </li>
     <li><a name="#HMinfosumERROR">sumERROR</a>
       Similar to sumStatus but with a focus on error conditions in the system.
       Here user can add reading<b>values</b> that are <b>not displayed</b>. I.e. the value is the
       good-condition that will not be counted.<br>
       This way user must not know all error values but it is sufficient to supress known non-ciritical ones.
       <br>
       Example:<br>
       <ul><code>
         attr hm sumERROR battery:ok,sabotageError:off,overheat:off,Activity:alive:unknown<br>
       </code></ul>
       will cause a reading like<br>
       <ul><code>
         ERR_batterie low:3<br>
         ERR_sabotageError on:1<br>
         ERR_overheat on:3<br>
         ERR_Activity dead:5<br>
       </code></ul>
     </li>
     <li><a name="#HMinfoautoUpdate">autoUpdate</a>
       retriggers the command update periodically.<br>
       Example:<br>
       <ul><code>
         attr hm autoUpdate 00:10<br>
       </code></ul>
       will trigger the update every 10 min<br>
     </li>
     <li><a name="#HMinfoautoArchive">autoArchive</a>
       if set fhem will update the configFile each time the new data is available.
       The update will happen with <a ref="#HMinfoautoUpdate">autoUpdate</a>. It will not 
       work it autoUpdate is not used.<br>
       see also <a ref="#HMinfoarchConfig">archConfig</a>
       <br>
     </li>
     <li><a name="#HMinfohmAutoReadScan">hmAutoReadScan</a>
       defines the time in seconds CUL_HM tries to schedule the next autoRead
       from the queue. Despite this timer FHEM will take care that only one device from the queue will be
       handled at one point in time. With this timer user can stretch timing even further - to up to 300sec
       min delay between execution. <br>
       Setting to 1 still obeys the "only one at a time" prinzip.<br>
       Note that compressing will increase message load while stretch will extent waiting time.<br>
     </li>
     <li><a name="#HMinfohmIoMaxDly">hmIoMaxDly</a>
       max time in seconds CUL_HM stacks messages if the IO device is not ready to send.
       If the IO device will not reappear in time all command will be deleted and IOErr will be reported.<br>
       Note: commands will be executed after the IO device reappears - which could lead to unexpected
       activity long after command issue.<br>
       default is 60sec. max value is 3600sec<br>
     </li>
     <li><a name="#HMinfoconfigDir">configDir</a>
       default directory where to store and load configuration files from.
       This path is used as long as the path is not given in a filename of 
       a given command.<br>
       It is used by commands like <a ref="#HMinfotempList">tempList</a> or <a ref="#HMinfosaveConfig">saveConfig</a><br>
     </li>
     <li><a name="#HMinfoconfigFilename">configFilename</a>
       default filename used by 
       <a ref="#HMinfosaveConfig">saveConfig</a>, 
       <a ref="#HMinfopurgeConfig">purgeConfig</a>, 
       <a ref="#HMinfoloadConfig">loadConfig</a><br>
       <a ref="#HMinfoverifyConfig">verifyConfig</a><br>
     </li>
     <li><a name="#HMinfoconfigTempFile">configTempFile&lt;,configTempFile2&gt;&lt;,configTempFile2&gt; </a>
        Liste of Templfiles (weekplan) which are considered in HMInfo and CUL_HM<br>
        Files are comma separated. The first file is default. Its name may be skipped when setting a tempalte.<br>
     </li>
     <li><a name="#HMinfohmManualOper">hmManualOper</a>
       set to 1 will prevent any automatic operation, update or default settings
       in CUL_HM.<br>
     </li>
     <li><a name="#HMinfohmDefaults">hmDefaults</a>
       set default params for HM devices. Multiple attributes are possible, comma separated.<br>
       example:<br>
       attr hm hmDefaults hmProtocolEvents:0_off,rssiLog:0<br>
     </li>
     <li><a name="#HMinfoautoLoadArchive">autoLoadArchive</a>
       if set the register config will be loaded after reboot automatically. See <a ref="#HMinfoloadConfig">loadConfig</a> for details<br>
     </li>
     

   </ul>
   <br>
  <a name="HMinfovariables"><b>Variables</b></a>
   <ul>
     <li><b>I_autoReadPend:</b> Info:list of entities which are queued to retrieve config and status.
                             This is typically scheduled thru autoReadReg</li>
     <li><b>ERR___rssiCrit:</b> Error:list of devices with RSSI reading n min level </li>
     <li><b>W_unConfRegs:</b> Warning:list of entities with unconfirmed register changes. Execute getConfig to clear this.</li>
     <li><b>I_rssiMinLevel:</b> Info:counts of rssi min readings per device, clustered in blocks</li>
     

     <li><b>ERR__protocol:</b> Error:count of non-recoverable protocol events per device.
         Those events are NACK, IOerr, ResendFail, CmdDel, CmdPend.<br>
         Counted are the number of device with those events, not the number of events!</li>
     <li><b>ERR__protoNames:</b> Error:name-list of devices with non-recoverable protocol events</li>
     <li><b>I_HM_IOdevices:</b> Info:list of IO devices used by CUL_HM entities</li>
     <li><b>I_actTotal:</b> Info:action detector state, count of devices with ceratin states</li>
     <li><b>ERRactNames:</b> Error:names of devices that are not alive according to ActionDetector</li>
     <li><b>C_sumDefined:</b> Count:defined entities in CUL_HM. Entites might be count as
         device AND channel if channel funtion is covered by the device itself. Similar to virtual</li>
     <li><b>ERR_&lt;reading&gt;:</b> Error:count of readings as defined in attribut
         <a href="#HMinfosumERROR">sumERROR</a>
         that do not match the good-content. </li>
     <li><b>ERR_names:</b> Error:name-list of entities that are counted in any ERR_&lt;reading&gt;
         W_sum_&lt;reading&gt;: count of readings as defined in attribut
         <a href="#HMinfosumStatus">sumStatus</a>. </li>
     Example:<br>

     <ul><code>
       ERR___rssiCrit LightKittchen,WindowDoor,Remote12<br>
       ERR__protocol NACK:2 ResendFail:5 CmdDel:2 CmdPend:1<br>
       ERR__protoNames LightKittchen,WindowDoor,Remote12,Ligth1,Light5<br>
       ERR_battery: low:2;<br>
       ERR_names: remote1,buttonClara,<br>
       I_rssiMinLevel 99&gt;:3 80&lt;:0 60&lt;:7 59&lt;:4<br>
       W_sum_battery: ok:5;low:2;<br>
       W_sum_overheat: off:7;<br>
       C_sumDefined: entities:23 device:11 channel:16 virtual:5;<br>
     </code></ul>
   </ul>
</ul>
=end html


=begin html_DE

<a name="HMinfo"></a>
<h3>HMinfo</h3>
<ul>

  Das Modul HMinfo erm&ouml;glicht einen &Uuml;berblick &uuml;ber eQ-3 HomeMatic Ger&auml;te, die mittels <a href="#CUL_HM">CUL_HM</a> definiert sind.<br><br>
  <B>Status Informationen und Z&auml;hler</B><br>
  HMinfo gibt einen &Uuml;berlick &uuml;ber CUL_HM Installationen einschliesslich aktueller Zust&auml;nde.
  Readings und Z&auml;hler werden aus Performance Gr&uuml;nden nicht automatisch aktualisiert. <br>
  Mit dem Kommando <a href="#HMinfoupdate">update</a> k&ouml;nnen die Werte aktualisiert werden.
  <ul><code><br>
           set hm update<br>
  </code></ul><br>
  Die Webansicht von HMinfo stellt Details &uuml;ber CUL_HM Instanzen mit ungew&ouml;hnlichen Zust&auml;nden zur Verf&uuml;gung. Dazu geh&ouml;ren:
  <ul>
      <li>Action Detector Status</li>
      <li>CUL_HM Ger&auml;te und Zust&auml;nde</li>
      <li>Ereignisse im Zusammenhang mit Kommunikationsproblemen</li>
      <li>Z&auml;hler f&uuml;r bestimmte Readings und Zust&auml;nde (z.B. battery) - <a href="#HMinfoattr">attribut controlled</a></li>
      <li>Z&auml;hler f&uuml;r Readings, die auf Fehler hindeuten (z.B. overheat, motorErr) - <a href="#HMinfoattr">attribut controlled</a></li>
  </ul>
  <br>

  Weiterhin stehen HM Kommandos zur Verf&uuml;gung, z.B. f&uuml;r das Speichern aller gesammelten Registerwerte.<br><br>

  Ein Kommando wird f&uuml;r alle HM Instanzen der kompletten Installation ausgef&uuml;hrt.
  Die Ausf&uuml;hrung ist jedoch auf die dazugeh&ouml;rigen Instanzen beschr&auml;nkt.
  So wird rssi nur auf Ger&auml;te angewendet, da Kan&auml;le RSSI Werte nicht unterst&uuml;tzen.<br><br>
  <a name="HMinfoFilter"><b>Filter</b></a>
  <ul> werden wie folgt angewendet:<br><br>
        <code>set &lt;name&gt; &lt;cmd&gt; &lt;filter&gt; [&lt;param&gt;]</code><br>
        wobei sich filter aus Typ und Name zusammensetzt<br>
        [-dcasev] [-f &lt;filter&gt;]<br><br>
        <b>Typ</b> <br>
        <ul>
            <li>d - device   :verwende Ger&auml;t</li>
            <li>c - channels :verwende Kanal</li>
            <li>v - virtual  :unterdr&uuml;cke virtuelle Instanz</li>
            <li>p - physical :unterdr&uuml;cke physikalische Instanz</li>
            <li>a - aktor    :unterdr&uuml;cke Aktor</li>
            <li>s - sensor   :unterdr&uuml;cke Sensor</li>
            <li>e - empty    :verwendet das Resultat auch wenn die Felder leer sind</li>
            <li>2 - alias    :2ter name alias anzeigen</li>
        </ul>
        und/oder <b>Name</b>:<br>
        <ul>
            <li>-f &lt;filter&gt;  :Regul&auml;rer Ausdruck (regexp), um die Instanznamen zu filtern</li>
        </ul>
        Beispiel:<br>
        <ul><code>
           set hm param -d -f dim state # Zeige den Parameter 'state' von allen Ger&auml;ten, die "dim" im Namen enthalten<br>
           set hm param -c -f ^dimUG$ peerList # Zeige den Parameter 'peerList' f&uuml;r alle Kan&auml;le mit dem Namen "dimUG"<br>
           set hm param -dcv expert # Ermittle das Attribut expert f&uuml;r alle Ger&auml;te, Kan&auml;le und virtuelle Instanzen<br>
        </code></ul>
  </ul>
  <br>
  <a name="HMinfodefine"><b>Define</b></a>
  <ul>
    <code>define &lt;name&gt; HMinfo</code><br>
    Es muss nur eine Instanz ohne jegliche Parameter definiert werden.<br>
  </ul>
  <br>
  <a name="HMinfoget"><b>Get</b></a>
  <ul>
      <li><a name="#HMinfomodels">models</a><br>
          zeige alle HM Modelle an, die von FHEM unterst&uuml;tzt werden
      </li>
      <li><a name="#HMinfoparam">param</a> <a href="#HMinfoFilter">[filter]</a> &lt;name&gt; &lt;name&gt;...<br>
          zeigt Parameterwerte (Attribute, Readings, ...) f&uuml;r alle Instanzen in Tabellenform an 
      </li>
      <li><a name="#HMinforegister">register</a> <a href="#HMinfoFilter">[filter]</a><br>
          zeigt eine Tabelle mit Registern einer Instanz an
      </li>
      <li><a name="#HMinforegCheck">regCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          validiert Registerwerte
      </li>
      <li><a name="#HMinfopeerCheck">peerCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          validiert die Einstellungen der Paarungen (Peers). Hat ein Kanal einen Peer gesetzt, muss dieser auch auf
          der Gegenseite gesetzt sein.
      </li>
      <li><a name="#HMinfopeerXref">peerXref</a> <a href="#HMinfoFilter">[filter]</a><br>
          erzeugt eine komplette Querverweisliste aller Paarungen (Peerings)
      </li>
      <li><a name="#HMinfoconfigCheck">configCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          Plausibilit&auml;tstest aller HM Einstellungen inklusive regCheck und peerCheck
      </li>
      <li><a name="#HMinfoconfigChkResult">configChkResult</a><br>
          gibt das Ergebnis eines vorher ausgeführten configCheck zurück
      </li>
      <li><a name="#HMinfotemplateList">templateList [&lt;name&gt;]</a><br>
          zeigt eine Liste von Vorlagen. Ist kein Name angegeben, werden alle Vorlagen angezeigt<br>
      </li>
      <li><a name="#HMinfotemplateUsg">templateUsg</a> &lt;template&gt; [sortPeer|sortTemplate]<br>
          Liste der genutzten templates.<br>
          template filtert die Einträge nach diesem template
      </li>
      <li><a name="#HMinfomsgStat">msgStat</a> <a href="#HMinfoFilter">[filter]</a><br>
          zeigt eine Statistik aller Meldungen der letzen Woche<br>
      </li>
      <li><a name="#HMinfoprotoEvents">protoEvents</a> <a href="#HMinfoFilter">[filter]</a> <br>
          vermutlich die <B>wichtigste Auflistung</B> f&uuml;r Meldungsprobleme.
          Informationen &uuml;ber ausstehende Kommandos und fehlgeschlagene Sendevorg&auml;nge
          f&uuml;r alle Ger&auml;te in Tabellenform.<br>
          Mit <a name="#HMinfoclear">clear msgEvents</a> kann die Statistik gel&ouml;scht werden.<br>
      </li>
      <li><a name="#HMinforssi">rssi </a><a href="#HMinfoFilter">[filter]</a><br>
          Statistik &uuml;ber die RSSI Werte aller HM Instanzen.<br>
      </li>

      <li><a name="#HMinfotemplateChk">templateChk</a> <a href="#HMinfoFilter">[filter]</a> &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
         Verifiziert, ob die Registerwerte mit der Vorlage in Einklang stehen.<br>
         Die Parameter sind identisch mit denen aus <a href="#HMinfotemplateSet">templateSet</a>.<br>
         Wenn kein Peer ben&ouml;tigt wird, stattdessen none verwenden.
         Beispiele f&uuml;r die &Uuml;berpr&uuml;fung von Einstellungen<br>
        <ul><code>
         set hm templateChk -f RolloNord BlStopUpLg none         1 2 # RolloNord, no peer, parameter 1 and 2 given<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:long    # RolloNord peerName, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName         # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg peerName:all     # RolloNord peerName, long and short<br>
         set hm templateChk -f RolloNord BlStopUpLg all:long         # RolloNord any peer, long only<br>
         set hm templateChk -f RolloNord BlStopUpLg all              # RolloNord any peer,long and short<br>
         set hm templateChk -f Rollo.*   BlStopUpLg all              # each Rollo* any peer,long and short<br>
         set hm templateChk BlStopUpLg                               # each entities<br>
         set hm templateChk                                          # all assigned templates<br>
         set hm templateChk sortTemplate                             # all assigned templates, sort by template<br>
         set hm templateChk sortPeer                                 # all assigned templates, sort by peer<br>
        </code></ul>
      </li>
  </ul>
  <a name="HMinfoset"><b>Set</b></a>
  <ul>
  Obwohl die Kommandos Einstellungen abrufen (get function), werden sie mittels set ausgef&uuml;hrt, um die 
  Benutzung mittels Web Interface zu erleichtern.<br>
    <ul>
      <li><a name="#HMinfoupdate">update</a><br>
          Aktualisiert HM Status Z&auml;hler.
      </li>
      <li><a name="#HMinfoautoReadReg">autoReadReg</a> <a href="#HMinfoFilter">[filter]</a><br>
          Aktiviert das automatische Lesen der Konfiguration f&uuml;r ein CUL_HM Ger&auml;t, wenn das Attribut autoReadReg auf 1 oder h&ouml;her steht.
      </li>
      <li><a name="#HMinfoclear">clear</a> <a href="#HMinfoFilter">[filter]</a> [msgEvents|msgErrors|readings|msgStat|register|rssi]<br>
          F&uuml;hrt ein set clear ... f&uuml;r alle HM Instanzen aus<br>
          <ul>
          <li>Protocol bezieht sich auf set clear msgEvents</li>
          <li>Protocol set clear msgEvents fuer alle devices mit protokoll Fehlern</li>
          <li>readings bezieht sich auf set clear readings</li>
          <li>rssi l&ouml;scht alle rssi Z&auml;hler</li>
          <li>msgStat l&ouml;scht die HM Meldungsstatistik</li>
          <li>register l&ouml;scht alle Eintr&auml;ge in den Readings</li>
          </ul>
      </li>
      <li><a name="#HMinfosaveConfig">saveConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          Sichert alle HM Registerwerte und Peers. Siehe <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>.<br>
          <a ref="#HMinfopurgeConfig">purgeConfig</a> wird automatisch ausgef&uuml;hrt, wenn die Datenmenge 1 MByte &uuml;bersteigt.<br>
      </li>
      <li><a name="#HMinfoarchConfig">archConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          F&uuml;hrt <a href="#HMinfosaveConfig">saveConfig</a> f&uuml;r alle Instanzen aus, sobald sich deren Konfiguration &auml;ndert.
          Es schont gegen&uuml;ber saveConfig die Resourcen, da es nur vollst&auml;ndige Konfigurationen sichert.<br>
          Die Option -a erzwingt das sofortige Archivieren f&uuml;r alle Ger&auml;te, die eine vollst&auml;ndige Konfiguration aufweisen.<br>
      </li>
      <li><a name="#HMinfoloadConfig">loadConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          L&auml;dt Register und Peers aus einer zuvor mit <a href="#HMinfosaveConfig">saveConfig</a> gesicherten Datei.<br>
          Es sollte mit Vorsicht verwendet werden, da es Daten zu FHEM hinzuf&uuml;gt, die nicht verifiziert sind.
          Readings werden nicht ersetzt, nur fehlende Readings werden hinzugef&uuml;gt. Der Befehl ist dazu geignet, um Readings
          zu erstellen, die schwer zu erhalten sind. Readings von Ger&auml;ten, die nicht dauerhaft empfangen sondern nur auf Tastendruck
          aufwachen (z.B. T&uuml;rsensoren), k&ouml;nnen nicht ohne Weiteres gelesen werden.<br>
          Daher liegt es in der Verantwortung des Benutzers g&uuml;ltige Werte zu verwenden. Es sollte autoReadReg f&uuml;r Ger&auml;te verwendet werden,
          die einfach ausgelesen werden k&ouml;nnen.<br>
          Der Befehl aktualisiert lediglich FHEM Readings und Attribute. Die Programmierung des Ger&auml;tes wird <B>nicht</B> ver&auml;ndert.
      </li>
      <li><a name="#HMinfopurgeConfig">purgeConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          Bereinigt die gespeicherte Konfigurationsdatei. Durch die kumulative Speicherung der Registerwerte bleiben die
          zuletzt gespeicherten Werte erhalten und alle &auml;lteren werden gel&ouml;scht.
          Siehe <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>.
      </li>
      <li><a name="#HMinfoverifyConfig">verifyConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          vergleicht die aktuellen Daten mit dem configFile und zeigt unterschiede auf. 
          Es ist hilfreich wenn man eine bekannt gute Konfiguration gespeichert hat und gegen diese vergleiche will.
          Ein purge vorher macht sinn. 
          Siehe <a href="#CUL_HMpurgeConfig">CUL_HM purgeConfig</a>.
      </li>
      <br>
      
      <li><a name="#HMinfotempList">tempList</a> <a href="#HMinfoFilter">[filter]</a>[save|restore|verify] [&lt;file&gt;]</a><br>
          Diese Funktion erm&ouml;glicht die Verarbeitung von tempor&auml;ren Temperaturlisten f&uuml;r Thermostate.
          Die Listen k&ouml;nnen in Dateien abgelegt, mit den aktuellen Werten verglichen und an das Ger&auml;t gesendet werden.<br>
          <li><B>save</B> speichert die aktuellen tempList Werte des Systems in eine Datei. <br>
              Zu beachten ist, dass die aktuell in FHEM vorhandenen Werte benutzt werden. Der Benutzer muss selbst sicher stellen,
              dass diese mit den Werten im Ger&auml;t &uuml;berein stimmen.<br>
              Der Befehl arbeitet nicht kummulativ. Alle evtl. vorher in der Datei vorhandenen Werte werden &uuml;berschrieben.</li>
          <li><B>restore</B> in der Datei gespeicherte Termperaturliste wird direkt an das Ger&auml;t gesendet.</li>
          <li><B>verify</B> vergleicht die Temperaturliste in der Datei mit den aktuellen Werten in FHEM. Der Benutzer muss 
              selbst sicher stellen, dass diese mit den Werten im Ger&auml;t &uuml;berein stimmen.</li>
          <li><B>status</B> gibt einen Ueberblick aller genutzten template files. Ferner werden vorhandene templates in den files gelistst.
            <br></li>
          <li><B>genPlot</B> erzeugt einen Satz Daten um temp-templates graphisch darzustellen<br>
            Aus den gegebenen template-file wird ein .log erweitertes file erzeugt welches log-formatierte daten beinhaltet. 
            Zeitmarken sind auf Beginn 2000 terminiert.<br>
            Ein .gplot file wird in der gplt directory erzeugt.<br>
            Eine Logfile-entity <file>_Log, falls nicht vorhanden, wird erzeugt.<br>
            Eine SVG-entity <file>_SVG, falls nicht vorhanden, wird erzeugt.<br>
            </li>
          <br>
          <li><B>filename</B> Name der Datei. Vorgabe ist <B>tempList.cfg</B></li>
          Beispiel f&uuml;r einen Dateiinhalt:<br>
          <ul><code>
               entities:HK1_Climate,HK2_Clima<br>
               tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0<br>
               tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0<br>
               tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0<br>
               entities:hk3_Climate<br>
               tempListFri>06:00 17.0 12:00 21.0 23:00 20.0 24:00 19.5<br>
               tempListMon>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSat>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListSun>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListThu>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListTue>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
               tempListWed>06:00 17.0 12:00 21.0 23:00 20.0 24:00 17.0<br>
         </code></ul>
         Datei Schl&uuml;sselw&ouml;rter<br>
         <li><B>entities</B> mittels Komma getrennte Liste der Instanzen f&uuml;r die die nachfolgende Liste bestimmt ist.
         Es muss die tats&auml;chlich f&uuml;r die Temperaturliste zust&auml;ndige Instanz angegeben werden. Bei RTs ist das der Kanal 04,
         bei TCs der Kanal 02.</li>
         <li><B>tempList...</B> Zeiten und Temperaturen sind genau wie im Befehl "set tempList" anzugeben</li>
         <br>
     </li>
         <br>
      <li><a name="#HMinfocpRegs">cpRegs &lt;src:peer&gt; &lt;dst:peer&gt; </a><br>
          erm&ouml;glicht das Kopieren von Registern, Einstellungen und Verhalten zwischen gleichen Kan&auml;len, bei einem Peer auch
          zwischen unterschiedlichen Kan&auml;len. Das Kopieren kann daher sowohl von Ger&auml;t zu Ger&auml;t, als auch innerhalb eines
          Ger&auml;tes stattfinden.<br>
         <b>src:peer</b> ist die Quell-Instanz. Der Peer muss angegeben werden, wenn dessen Verhalten kopiert werden soll.<br>
         <b>dst:peer</b> ist die Ziel-Instanz.<br>
         Beispiel:<br>
         <ul><code>
          set hm cpRegs blindR blindL  # kopiert alle Register (list 1) des Kanals von blindR nach blindL einschliesslich z.B. der
          Rolladen Fahrzeiten. Register, die den Peer betreffen (list 3/4), werden nicht kopiert.<br>
          set hm cpRegs blindR:Btn1 blindL:Btn2  # kopiert das Verhalten der Beziehung Btn1/blindR nach Btn2/blindL<br>
          set hm cpRegs blindR:Btn1 blindR:Btn2  # kopiert das Verhalten der Beziehung Btn1/blindR nach Btn2/blindR, hier
          innerhalb des Aktors<br>
         </code></ul>
         <br>
         Einschr&auml;nkungen:<br>
         <ul>
         cpRegs <u>ver&auml;ndert keine Peerings</u> oder liest direkt aus den Ger&auml;ten. Die Readings m&uuml;ssen daher aktuell sein.<br>
         cpRegs kann nur auf <u>identische Ger&auml;temodelle</u> angewendet werden<br>
         cpRegs erwartet <u>aktuelle Readings</u>. Dies muss der Benutzer sicher stellen.<br>
         </ul>
      </li>
      <li><a name="#HMinfotemplateDef">templateDef &lt;name&gt; &lt;param&gt; &lt;desc&gt; &lt;reg1:val1&gt; [&lt;reg2:val2&gt;] ...</a><br>
          definiert eine Vorlage.<br>
          <b>param</b> definiert die Namen der Parameters, die erforderlich sind, um die Vorlage auszuf&uuml;hren.
                       Diese sind abh&auml;ngig von der Vorlage und k&ouml;nnen onTime oder brightnesslevel sein.
                       Bei einer Liste mehrerer Parameter m&uuml;ssen diese mittels Kommata separiert werden.<br>
                       param1:param2:param3<br>
                       Der Parameter del f&uuml;hrt zur L&ouml;schung der Vorlage.<br>
          <b>desc</b> eine Beschreibung f&uuml;r die Vorlage<br>
          <b>reg:val</b> der Name des Registers und der dazugeh&ouml;rige Zielwert.<br>
          Wenn das Register zwischen long und short unterscheidet, muss das f&uuml;hrende sh oder lg weggelassen werden.<br>
          Parameter m&uuml;ssen mit p angegeben werden, p0 f&uuml;r den ersten, p1 f&uuml;r den zweiten usw.
        <br>
        Beispiel<br>
        <ul><code>
          set hm templateDef SwOnCond level:cond "my description" CtValLo:p0 CtDlyOn:p1 CtOn:geLo<br>
          set hm templateDef SwOnCond del # lösche template SwOnCond<br>
          set hm templateDef SwOnCond fromMaster &lt;masterChannel&gt; &lt;peer:[long|short]&gt;# masterKanal mit peer wird als Vorlage genommen<br>
          set hm templateDef SwOnCond fromMaster myChannel peerChannel:long  <br>
        </code></ul>
      </li>
      <li><a name="#HMinfotemplateSet">templateSet</a> &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]<br>
          setzt mehrere Register entsprechend der angegebenen Vorlage. Die Parameter m&uuml;ssen entsprechend der Vorlage angegeben werden.<br>
          templateSet akkumuliert alle &Auml;nderungen und schreibt das Ergebnis gesammelt.<br>
         <b>entity:</b> ist die Quell-Instanz. Der Peer muss angegeben werden, wenn dessen Verhalten kopiert werden soll.<br>
         <b>template:</b> eine der vorhandenen Vorlagen<br>
         <b>peer:</b> [long|short]:falls erforderlich muss der Peer angegeben werden. Wird kein Peer ben&ouml;tigt, '0' verwenden.
                  Bei einem Peer muss f&uuml;r den Tastendruck long oder short angegeben werden.<br>
         <b>param:</b> Nummer und Bedeutung des Parameters h&auml;ngt von der Vorlage ab.<br>
         Ein Beispiel k&ouml;nnte sein (theoretisch, ohne die Vorlage anzugeben)<br>
        <ul><code>
         set hm templateSet Licht1 staircase FB1:short 20  <br>
         set hm templateSet Licht1 staircase FB1:long 100  <br>
        </code></ul>
        Einschr&auml;nkungen:<br>
        <ul>
         Der Benutzer muss aktuelle Register/Konfigurationen sicher stellen.<br>
         templateSet konfiguriert ggf. nur einzelne Register und keinen vollst&auml;ndigen Satz. Dies h&auml;ngt vom Design der Vorlage ab.<br>
         <br>
        </ul>
      </li>
      <li><a name="#HMinfotemplateDel">templateDel</a> &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt;<br>
          entfernt ein Template das mit templateSet eingetragen wurde
      </li>
      <li><a name="#HMinfotemplateExe">templateExe</a> &lt;template&gt; <br>
          führt das templateSet erneut aus. Die Register werden nochmals geschrieben, falls sie nicht zum template passen. <br>
      </li>
      <li><a name="#HMinfodeviceReplace">x-deviceReplace</a> &lt;oldDevice&gt; &lt;newDevice&gt; <br>
          Ersetzen eines alten oder defekten Device. Das neue Ersatzdevice muss kompatibel zum Alten sein - FHEM prüft das nur rudimentär. Der Anwender sollt es sorgsam prüfen.<br>
          Das Kommando muss aus Sicherheitsgründen 2-fach ausgeführt werden. Der erste Aufruf wird mit einem CAUTION quittiert. Nach Auslösen den Kommandos ein 2. mal werden die Devices umbenannt und umkonfiguriert. Er werden alle peerings, Register und Templates im neuen Device UND allen peers umgestellt.<br>
          ACHTUNG: Nach dem Auslösen kann die Änderung nicht mehr automatisch rückgängig gemacht werden. Manuell ist das natürlich möglich.<br> 
          Auch ein ückspring auf eine ältere Konfiguration erlaubt KEIN Rückgängigmachen!!!<br>          
          Sollte das Device und seine Kanäle über Templates definiert sein  - also die Registerlisten - kann im Falle von Problemen in der Übertragung - problemlos wieder hergestellt werden. <br>
      </li>

    </ul>
  </ul>
  <br>


  <a name="HMinfoattr"><b>Attribute</b></a>
   <ul>
    <li><a name="#HMinfosumStatus">sumStatus</a><br>
        erzeugt eine Liste von Warnungen. Die zu untersuchenden Readings werden mittels Komma separiert angegeben.
        Die Readings werden, so vorhanden, von allen Instanzen ausgewertet, gez&auml;hlt und getrennt nach Readings mit
        gleichem Inhalt ausgegeben.<br>
        Beispiel:<br>
        <ul><code>
           attr hm sumStatus battery,sabotageError<br>
        </code></ul>
        k&ouml;nnte nachfolgende Ausgaben erzeugen<br>
        W_sum_batterie ok:5 low:3<br>
        W_sum_sabotageError on:1<br>
        <br>
        Anmerkung: Z&auml;hler mit Werten von '0' werden nicht angezeigt. HMinfo findet alle vorhanden Werte selbstst&auml;ndig.<br>
        Das Setzen des Attributes erm&ouml;glicht einen schnellen &Uuml;berblick &uuml;ber systemkritische Werte.<br>
    </li>
    <li><a name="#HMinfosumERROR">sumERROR</a>
        &Auml;hnlich sumStatus, jedoch mit dem Fokus auf signifikante Fehler.
        Hier k&ouml;nnen Reading <b>Werte</b> angegeben werden, die dazu f&uuml;hren, dass diese <b>nicht angezeigt</b> werden.
        Damit kann beispielsweise verhindert werden, dass der zu erwartende Normalwert oder ein anderer nicht
        kritischer Wert angezeigt wird.<br>
        Beispiel:<br>
        <ul><code>
           attr hm sumERROR battery:ok,sabotageError:off,overheat:off,Activity:alive:unknown<br>
        </code></ul>
        erzeugt folgende Ausgabe:<br>
        <ul><code>
        ERR_batterie low:3<br>
        ERR_sabotageError on:1<br>
        ERR_overheat on:3<br>
        ERR_Activity dead:5<br>
        </code></ul>
    </li>
    <li><a name="#HMinfoautoUpdate">autoUpdate</a>
        f&uuml;hrt den Befehl periodisch aus.<br>
        Beispiel:<br>
        <ul><code>
           attr hm autoUpdate 00:10<br>
        </code></ul>
        f&uuml;hrt den Befehl alle 10 Minuten aus<br>
    </li>
    <li><a name="#HMinfoautoArchive">autoArchive</a>
        Sobald neue Daten verf&uuml;gbar sind, wird das configFile aktualisiert.
        F&uuml;r die Aktualisierung ist <a ref="#HMinfoautoUpdate">autoUpdate</a> zwingend erforderlich.<br>
        siehe auch <a ref="#HMinfoarchConfig">archConfig</a>
        <br>
    </li>
    <li><a name="#HMinfohmAutoReadScan">hmAutoReadScan</a>
        definiert die Zeit in Sekunden bis zum n&auml;chsten autoRead durch CUL_HM. Trotz dieses Zeitwertes stellt
        FHEM sicher, dass zu einem Zeitpunkt immer nur ein Ger&auml;t gelesen wird, auch wenn der Minimalwert von 1
        Sekunde eingestellt ist. Mit dem Timer kann der Zeitabstand
        ausgeweitet werden - bis zu 300 Sekunden zwischen zwei Ausf&uuml;hrungen.<br>
        Das Herabsetzen erh&ouml;ht die Funkbelastung, Heraufsetzen erh&ouml;ht die Wartzezeit.<br>
    </li>
    <li><a name="#HMinfohmIoMaxDly">hmIoMaxDly</a>
        maximale Zeit in Sekunden f&uuml;r die CUL_HM Meldungen puffert, wenn das Ger&auml;t nicht sendebereit ist.
        Ist das Ger&auml;t nicht wieder rechtzeitig sendebereit, werden die gepufferten Meldungen verworfen und
        IOErr ausgel&ouml;st.<br>
        Hinweis: Durch die Pufferung kann es vorkommen, dass Aktivit&auml;t lange nach dem Absetzen des Befehls stattfindet.<br>
        Standard ist 60 Sekunden, maximaler Wert ist 3600 Sekunden.<br>
    </li>
    <li><a name="#HMinfoconfigDir">configDir</a>
        Verzeichnis f&uuml;r das Speichern und Lesen der Konfigurationsdateien, sofern in einem Befehl nur ein Dateiname ohne
        Pfad angegen wurde.<br>
        Verwendung beispielsweise bei <a ref="#HMinfotempList">tempList</a> oder <a ref="#HMinfosaveConfig">saveConfig</a><br>
    </li>
    <li><a name="#HMinfoconfigFilename">configFilename</a>
        Standard Dateiname zur Verwendung von 
        <a ref="#HMinfosaveConfig">saveConfig</a>, 
        <a ref="#HMinfopurgeConfig">purgeConfig</a>, 
        <a ref="#HMinfoloadConfig">loadConfig</a><br>
    </li>
    <li><a name="#HMinfoconfigTempFile">configTempFile&lt;,configTempFile2&gt;&lt;,configTempFile3&gt; </a>
        Liste der Templfiles (weekplan) welche in HM berücksichtigt werden<br>
        Die Files werden kommasepariert eingegeben. Das erste File ist der Default. Dessen Name muss beim Template nicht eingegeben werden.<br>
    </li>
    <li><a name="#HMinfohmManualOper">hmManualOper</a>
        auf 1 gesetzt, verhindert dieses Attribut jede automatische Aktion oder Aktualisierung seitens CUL_HM.<br>
    </li>
    <li><a name="#HMinfohmDefaults">hmDefaults</a>
       setzt default Atribute fuer HM devices. Mehrere Attribute sind moeglich, Komma separiert.<br>
       Beispiel:<br>
       attr hm hmDefaults hmProtocolEvents:0_off,rssiLog:0<br>
    </li>
     <li><a name="#HMinfoautoLoadArchive">autoLoadArchive</a>
       das Register Archive sowie Templates werden nach reboot automatischgeladen.
       Siehe <a ref="#HMinfoloadConfig">loadConfig</a> fuer details<br>
     </li>

   </ul>
   <br>
  <a name="HMinfovariables"><b>Variablen</b></a>
   <ul>
    <li><b>I_autoReadPend:</b> Info: Liste der Instanzen, f&uuml;r die das Lesen von Konfiguration und Status ansteht,
                                     &uuml;blicherweise ausgel&ouml;st durch autoReadReg.</li>
    <li><b>ERR___rssiCrit:</b> Fehler: Liste der Ger&auml;te mit kritischem RSSI Wert </li>
    <li><b>W_unConfRegs:</b> Warnung: Liste von Instanzen mit unbest&auml;tigten &Auml;nderungen von Registern.
                                      Die Ausf&uuml;hrung von getConfig ist f&uuml;r diese Instanzen erforderlich.</li>
    <li><b>I_rssiMinLevel:</b> Info: Anzahl der niedrigen RSSI Werte je Ger&auml;t, in Bl&ouml;cken angeordnet.</li>

    <li><b>ERR__protocol:</b> Fehler: Anzahl nicht behebbarer Protokollfehler je Ger&auml;t.
        Protokollfehler sind NACK, IOerr, ResendFail, CmdDel, CmdPend.<br>
        Gez&auml;hlt wird die Anzahl der Ger&auml;te mit Fehlern, nicht die Anzahl der Fehler!</li>
    <li><b>ERR__protoNames:</b> Fehler: Liste der Namen der Ger&auml;te mit nicht behebbaren Protokollfehlern</li>
    <li><b>I_HM_IOdevices:</b> Info: Liste der IO Ger&auml;te, die von CUL_HM Instanzen verwendet werden</li>
    <li><b>I_actTotal:</b> Info: Status des Actiondetectors, Z&auml;hler f&uuml;r Ger&auml;te mit bestimmten Status</li>
    <li><b>ERRactNames:</b> Fehler: Namen von Ger&auml;ten, die der Actiondetector als ausgefallen meldet</li>
    <li><b>C_sumDefined:</b> Count: In CUL_HM definierte Instanzen. Instanzen k&ouml;nnen als Ger&auml;t UND
                                    als Kanal gez&auml;hlt werden, falls die Funktion des Kanals durch das Ger&auml;t
                                    selbst abgedeckt ist. &Auml;hnlich virtual</li>
    <li><b>ERR_&lt;reading&gt;:</b> Fehler: Anzahl mittels Attribut <a href="#HMinfosumERROR">sumERROR</a>
                                           definierter Readings, die nicht den Normalwert beinhalten. </li>
    <li><b>ERR_names:</b> Fehler: Namen von Instanzen, die in einem ERR_&lt;reading&gt; enthalten sind.</li>
    <li><b>W_sum_&lt;reading&gt;</b> Warnung: Anzahl der mit Attribut <a href="#HMinfosumStatus">sumStatus</a> definierten Readings.</li>
    Beispiele:<br>
    <ul>
    <code>
      ERR___rssiCrit LightKittchen,WindowDoor,Remote12<br>
      ERR__protocol NACK:2 ResendFail:5 CmdDel:2 CmdPend:1<br>
      ERR__protoNames LightKittchen,WindowDoor,Remote12,Ligth1,Light5<br>
      ERR_battery: low:2;<br>
      ERR_names: remote1,buttonClara,<br>
      I_rssiMinLevel 99&gt;:3 80&lt;:0 60&lt;:7 59&lt;:4<br>
      W_sum_battery: ok:5;low:2;<br>
      W_sum_overheat: off:7;<br>
      C_sumDefined: entities:23 device:11 channel:16 virtual:5;<br>
    </code>
    </ul>
   </ul>
</ul>
=end html_DE
=cut
