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
sub HMinfo_peerCheck(@);
sub HMinfo_getEntities(@);
sub HMinfo_SetFn($@);
sub HMinfo_SetFnDly($);

use Blocking;
use HMConfig;

sub HMinfo_Initialize($$) {####################################################
  my ($hash) = @_;

  $hash->{DefFn}     = "HMinfo_Define";
  $hash->{SetFn}     = "HMinfo_SetFn";
  $hash->{AttrFn}    = "HMinfo_Attr";
  $hash->{AttrList}  =  "loglevel:0,1,2,3,4,5,6 "
                       ."sumStatus sumERROR "
                       ."autoUpdate "
                       ."hmAutoReadScan hmIoMaxDly "
                       ."hmManualOper:0_auto,1_manual "
                       .$readingFnAttributes;

}
sub HMinfo_Define($$){#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
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
                            .",motorError:no"
                            .",error:none"
                            .",uncertain:yes"
                            .",smoke_detect:none"
                            .",cover:closed"
                            ;
  $hash->{nb}{cnt} = 0;
  return;
}
sub HMinfo_Attr(@) {#################################
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
        CUL_HM_queueAutoRead(""); #will restart timer
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
  return;
}
sub HMinfo_autoUpdate($){#in:name, send status-request
  my $name = shift;
  (undef,$name)=split":",$name,2;
  HMinfo_SetFn($defs{$name},$name,"update") if ($name);
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
    push @paramList,sprintf("%-15s",($para eq "undefined"?" -":$para));
    $found = 1 if ($para ne "undefined") ;
  }
  return $found,sprintf("%-20s\t: %s",$eName,join "\t|",@paramList);
}
sub HMinfo_regCheck(@) { ######################################################
  my @entities = @_;
  my @regIncompl;
  my @regMissing;
  my @regChPend;

  foreach my $eName (@entities){
    my $ehash = $defs{$eName};

    my @lsNo = CUL_HM_reglUsed($eName);
    my @mReg = ();
    my @iReg = ();

    foreach my $rNm (@lsNo){# check non-peer lists
      next if (!$rNm || $rNm eq "");
      
      if (   !$ehash->{READINGS}{$rNm}
          || !$ehash->{READINGS}{$rNm}{VAL})            {push @mReg, $rNm;}
      elsif ( $ehash->{READINGS}{$rNm}{VAL} !~ m/00:00/){push @iReg, $rNm;}
    }
    push @regChPend,$eName                        if ($ehash->{helper}{shadowReg} && 
                                                      keys %{$ehash->{helper}{shadowReg}});
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
  my @peerIDsEmpty;
  my @peerIDnotDef;
  my @peerIDsNoPeer;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn});#device has no channels
    next if (!CUL_HM_peerUsed($eName));

    my $id = $defs{$eName}{DEF};
    my $devId = substr($id,0,6);
    my $st = AttrVal(CUL_HM_id2Name($devId),"subType","");# from Master
    my $md = AttrVal(CUL_HM_id2Name($devId),"model","");
    my $peerIDs = AttrVal($eName,"peerIDs",undef);
    
    if (!$peerIDs){                # no peers - is this correct?
      push @peerIDsEmpty,"empty: ".$eName;
    }
    elsif($peerIDs !~ m/00000000/){#peerList incomplete
      push @peerIDsFail,"incomplete: ".$eName.":".$peerIDs;
    }
    else{# work on a valid list:
      next if ($st eq "repeater");
      foreach (split",",$peerIDs){
        next if ($_ eq "00000000" ||$_ =~m /$devId/);
        my $cId = $id;
        if ($md eq "HM-CC-RT-DN" && $id =~ m/05$/){ # special RT climate
          $_ =~ s/04$/05/;  # have to compare with clima_team, not clima
          $cId =~ s/05$/04/;# will find 04 in peerlist, not 05
        }
        my $pDiD = substr($_,0,6) if (substr($_,6,2) eq "01");
        if (!$modules{CUL_HM}{defptr}{$_} && 
            ($pDiD && !$modules{CUL_HM}{defptr}{$pDiD})){
          push @peerIDnotDef,$eName." id:".$_;
        }
        else{
          my $pName = CUL_HM_id2Name($_);
          $pName =~s/_chn:01//;           #channel 01 could be covered by device
          my $pPlist = AttrVal($pName,"peerIDs","");
          push @peerIDsNoPeer,$eName." p:".$pName if (!$pPlist || $pPlist !~ m/$cId/);
        }
      }
    }
  }
  my $ret = "";
  $ret .="\n\n peer list not read"  ."\n    ".(join "\n    ",sort @peerIDsEmpty) if(@peerIDsEmpty);
  $ret .="\n\n peer list incomplete"."\n    ".(join "\n    ",sort @peerIDsFail)  if(@peerIDsFail);
  $ret .="\n\n peer not defined"    ."\n    ".(join "\n    ",sort @peerIDnotDef) if(@peerIDnotDef);
  $ret .="\n\n peer not verified"   ."\n    ".(join "\n    ",sort @peerIDsNoPeer)if(@peerIDsNoPeer);
  return  $ret;
}
sub HMinfo_burstCheck(@) { ####################################################
  my @entities = @_;
  my @needBurstMiss;
  my @needBurstFail;
  my @peerIDsCond;
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{chn});#device has no channels
    next if (!CUL_HM_peerUsed($eName));
    next if (CUL_HM_Get($defs{$eName},$eName,"regList") !~ m/peerNeedsBurst/);

    my $peerIDs = AttrVal($eName,"peerIDs",undef);    
    next if(!$peerIDs);                # no peers - noting to check 

    my $devId = substr($defs{$eName}{DEF},0,6);
    foreach (split",",$peerIDs){
      next if ($_ eq "00000000" ||$_ =~m /$devId/);
      my $pn = CUL_HM_id2Name($_);
      $pn =~ s/_chn:/_chn-/; 
      my $prxt = CUL_HM_getRxType($defs{$pn});
      
      next if (!($prxt & 0x82)); # not a burst peer
      my $pnb = ReadingsVal($eName,"R-$pn-peerNeedsBurst",undef);
      if (!$pnb)           {push @needBurstMiss, $eName;}
      elsif($pnb !~ m /on/){push @needBurstFail, $eName;}

      if ($prxt & 0x80){# conditional burst - is it on?
        my $pDevN = CUL_HM_getDeviceName($pn);
        push @peerIDsCond," $pDevN for remote $eName" if (ReadingsVal($pDevN,"R-burstRx","") !~ m /on/);
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
  foreach my $eName (@entities){
    next if (!$defs{$eName}{helper}{role}{dev});
    my $ehash = $defs{$eName};
    my $pairId =  CUL_HM_Get($ehash,$eName,"param","PairedTo");
    my $IoDev =  $ehash->{IODev} if ($ehash->{IODev});
    my $ioHmId = AttrVal($IoDev->{NAME},"hmId","-");
    if (!$IoDev)                  { push @noIoDev,$eName;}
    elsif ($pairId eq "undefined"){ push @noID,$eName;}
    elsif ($pairId !~ m /$ioHmId/){ push @idMismatch,"$eName paired:$pairId IO attr: $ioHmId";}
  }

  my $ret = "";
  $ret .="\n\n no IO device assigned"      ."\n    ".(join "\n    ",sort @noIoDev)    if (@noIoDev);
  $ret .="\n\n PairedTo missing/unknown"   ."\n    ".(join "\n    ",sort @noID)       if (@noID);
  $ret .="\n\n PairedTo missmatch to IODev"."\n    ".(join "\n    ",sort @idMismatch) if (@idMismatch);
 return  $ret;
}
sub HMinfo_tempList(@) { ######################################################
  my ($filter,$action,$fName)=@_;
  $filter = "." if (!$filter);
  $fName = "tempList.cfg" if (!$fName);
  $action = "" if (!$action);
  my $ret;
  if ($action eq "save"){
    open(aSave, ">$fName") || return("Can't open $fName: $!");
    my @incmpl;
    foreach my $eN(HMinfo_getEntities("d")){#search for devices and select correct channel
      my $md = AttrVal($eN,"model","");
      my $chN; #tempList channel name
      if ($md =~ m/(HM-CC-RT-DN-BoM|HM-CC-RT-DN)/){
        $chN = $defs{$eN}{channel_04};
      }
      elsif ($md =~ m/(ROTO_ZEL-STG-RM-FWT|HM-CC-TC)/){
        $chN = $defs{$eN}{channel_02};
      }
      next if (!$chN || !$defs{$chN} || $chN !~ m/$filter/);
      print aSave "\nentities:$chN";
      my @tl = sort grep /tempList[SMFWT]/,keys %{$defs{$chN}{READINGS}};
      if (scalar@tl != 7){
        print aSave "\nincomplete:$chN only data for ".join(",",@tl);
        push @incmpl,$chN;
        next;
      }
      foreach my $rd (@tl){
        print aSave "\n$rd>$defs{$chN}{READINGS}{$rd}{VAL}";
      }
    }
    print aSave "\n======= finished ===\n";
    close(aSave);
    $ret = "incomplete data for ".join("\n     ",@incmpl) if (scalar@incmpl);
  }
  elsif ($action eq "verify"){
    open(aSave, "$fName") || return("Can't open $fName: $!");
    my @el = ();
    my @elAll = ();
    my @entryFail = ();
    my @entryNF = ();
    while(<aSave>){
      chomp;
      if($_ =~ m/^entities:/){
        my $line = $_;
        $line =~s/.*://;
        @el = ();
        foreach (split(",",$line)){
          if ($defs{$_}){
            push @el,$_ if ($defs{$_} && $_ =~ m/$filter/);
          }
          else{
            push @entryNF,$_;
          }
        }
        push @elAll,@el;
      }
      elsif(@el && $_ =~ m/tempList[SMFWT].*\>/){
        my ($tln,$val) = ($1,$2)if($_ =~ m/(.*)>(.*)/);
        $tln =~ s/ //g;
        $val =~ s/ //g;
        foreach my $eN(@el){
          my $valR = ReadingsVal($eN,$tln,"");
          $valR =~ s/ //g;
          push @entryFail,$eN." :".$tln if ($valR ne  $val);
        }
      }
    }
    $ret .= "\nentries tested:\n     "   .join("\n     ",@elAll)     if (scalar@elAll);
    $ret .= "\nfailed verify:\n     "    .join("\n     ",@entryFail) if (scalar@entryFail);
    $ret .= "\nentries not found:\n     ".join("\n     ",@entryNF)   if (scalar@entryNF);
  }
  elsif ($action eq "restore"){
    open(aSave, "$fName") || return("Can't open $fName: $!");
    my @el = ();
    my @elAll = ();
    my @entryFail = ();
    my @entryNF = ();
    my @exec = ();
    while(<aSave>){
      chomp;
      if($_ =~ m/^entities:/){
        my $line = $_;
        $line =~s/.*://;
        @el = ();
        foreach (split(",",$line)){
          if ($defs{$_}){
            push @el,$_ if ($defs{$_} && $_ =~ m/$filter/);
          }
          else{
            push @entryNF,$_;
          }
        }
        foreach (@exec){
          my @param = split(" ",$_);
          CUL_HM_Set($defs{$param[0]},@param);
        }
        push @elAll,@el;
      }
      elsif(@el && $_ =~ m/tempList[SMFWT].*\>/){
        my ($tln,$val) = ($1,$2)if($_ =~ m/(.*)>(.*)/);
        $tln =~ s/ //g;
        $val =~ tr/ +/ /;
        $val =~ s/^ //;
        $val =~ s/ $//;
        @exec = ();
        foreach my $eN(@el){
          my $x = CUL_HM_Set($defs{$eN},$eN,$tln,"prep",split(" ",$val));
          push @entryFail,$eN." :".$tln." respose:$x" if ($x != 1);
          push @exec,$eN." ".$tln." exec ".$val;
        }
      }
    }
    foreach (@exec){
      my @param = split(" ",$_);
      CUL_HM_Set($defs{$param[0]},@param);
    }

    $ret = "failed Entries:\n     "   .join("\n     ",@entryFail) if (scalar@entryFail);
    $ret = "Entries not found:\n     ".join("\n     ",@entryNF)   if (scalar@entryNF);
  }
  else{
    $ret = "$action unknown option - please use save, verify or restore";
  }
  return $ret;
}

sub HMinfo_getEntities(@) { ###################################################
  my ($filter,$re) = @_;
  my @names;
  my ($doDev,$doChn,$doIgn,$noVrt,$noPhy,$noAct,$noSen,$doEmp);
  $doDev=$doChn=$doEmp= 1;
  $doIgn=$noVrt=$noPhy=$noAct=$noSen = 0;
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
    }
  }
  # generate entity list
  foreach my $id (sort(keys%{$modules{CUL_HM}{defptr}})){
    next if ($id eq "000000");
    my $eHash = $modules{CUL_HM}{defptr}{$id};
    my $eName = $eHash->{NAME};
    my $isChn = (length($id) != 6 || CUL_HM_Get($eHash,$eName,"param","channel_01") eq "undefined")?1:0;
    my $eMd   = CUL_HM_Get($eHash,$eName,"param","model");
    my $eIg   = CUL_HM_Get($eHash,$eName,"param","ignore");
    $eIg = "" if ($eIg eq "undefined");
    next if (!(($doDev && length($id) == 6) ||
               ($doChn && $isChn)));
    next if (!$doIgn && $eIg);
    next if ( $noVrt && $eMd =~ m/^virtual/);
    next if ( $noPhy && $eMd !~ m/^virtual/);
    my $eSt = CUL_HM_Get($eHash,$eName,"param","subType");

    next if ( $noSen && $eSt =~ m/^(THSensor|remote|pushButton|threeStateSensor|sensor|motionDetector|swi)$/);
    next if ( $noAct && $eSt =~ m/^(switch|blindActuator|dimmer|thermostat|smokeDetector|KFM100|outputUnit)$/);
    next if ( $eName !~ m/$re/);
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
  $dr .=  sprintf("|%4s",$_) foreach ("Mon","Tue","Wed","Thu","Fri","Sat","Sun","# tdy");
  $ds .=  sprintf("|%4s",$_) foreach ("Mon","Tue","Wed","Thu","Fri","Sat","Sun","# tdy");
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
sub HMinfo_SetFn($@) {#########################################################
  my ($hash,$name,$cmd,@a) = @_;
  my ($opt,$optEmpty,$filter) = ("",1,"");
  my $ret;

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
  if   ($cmd eq "clear" )     {##actionImmediate: clear parameter--------------
    my ($type) = @a;
    if ($type eq "msgStat"){
      foreach (keys %{$modules{CUL_HM}{stat}{r}}){
        next if ($_ ne "dummy");
        delete $modules{CUL_HM}{stat}{$_};
        delete $modules{CUL_HM}{stat}{r}{$_};
        delete $modules{CUL_HM}{stat}{s}{$_};
      }
      return;
    }
    else{
      return "unknown parameter - use Protocol, readings, msgStat, register or rssi"
            if ($type !~ m/^(Protocol|readings|register|rssi)$/);
      $opt .= "d" if ($type !~ m/(readings|register)/);# readings apply to all, others device only
      my @entities;
      $type = "msgEvents" if ($type eq "Protocol");# translate parameter
      foreach my $dName (HMinfo_getEntities($opt,$filter)){
        push @entities,$dName;
        CUL_HM_Set($defs{$dName},$dName,"clear",$type);
      }
      return $cmd.$type." done:" ."\n cleared"  ."\n    ".(join "\n    ",sort @entities)
                           ;
    }
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
  elsif($cmd eq "protoEvents"){##print protocol-events-------------------------
    my ($type) = @a;
    $type = "long" if(!$type);
    my @paramList;
    my @IOlist;
    my @plSum; push @plSum,0 for (0..9);#prefill
    foreach my $dName (HMinfo_getEntities($opt."d",$filter)){
      my $id = $defs{$dName}{DEF};
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
      if ($type eq "short"){
        push @paramList, sprintf("%-20s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                      @pl[0..3],@pl[5..9]);
      }
      else{
        push @paramList, sprintf("%-20s%-17s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s",
                      @pl[0..9]);
      }
      push @IOlist,$defs{$pl[0]}{IODev}->{NAME};
    }

    my $hdr = sprintf("%-20s:%-16s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s",
                             ,"name"
                             ,"State","CmdPend"
                             ,"Snd","LastRcv","Resnd"
                             ,"CmdDel","ResndFail","Nack","IOerr");
    $hdr = sprintf("%-20s:%-16s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s",
                             ,"name"
                             ,"State","CmdPend"
                             ,"Snd","Resnd"
                             ,"CmdDel","ResndFail","Nack","IOerr") if ($type eq "short");
    $ret = $cmd." done:" ."\n    ".$hdr  ."\n    ".(join "\n    ",sort @paramList);
    $ret .= "\n======================================================="
           ."=========================================================";
    if ($type eq "short"){
      $ret .= "\n    ".sprintf("%-20s%-17s|%-10s|%-10s|%-10s#%-10s|%-10s|%-10s|%-10s","sum",@plSum[1..3],@plSum[5..9]);
    }
    else{
      $ret .= "\n    ".sprintf("%-20s%-17s|%-18s|%-18s|%-14s|%-18s#%-18s|%-18s|%-18s|%-18s","sum",@plSum[1..9]);
    }

    $ret .= "\n\n    CUL_HM queue length:$modules{CUL_HM}{prot}{rspPend}";
    
    $ret .= "\n";
    $ret .= "\n    requests pending";
    $ret .= "\n    ----------------";
    $ret .= "\n    autoReadReg          :".join(", ",@{$modules{CUL_HM}{helper}{qReqConf}});
    $ret .= "\n        recent           :".($modules{CUL_HM}{helper}{autoRdActive}?$modules{CUL_HM}{helper}{autoRdActive}:"none");
    $ret .= "\n    status request       :".join(", ",@{$modules{CUL_HM}{helper}{qReqStat}}) ;
    $ret .= "\n    autoReadReg wakeup   :".join(", ",@{$modules{CUL_HM}{helper}{qReqConfWu}});
    $ret .= "\n    status request wakeup:".join(", ",@{$modules{CUL_HM}{helper}{qReqStatWu}});
    $ret .= "\n    autoReadTest         :".join(", ",@{$modules{CUL_HM}{helper}{confCheckArr}});
    $ret .= "\n";
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
  elsif($cmd eq "rssi")       {##print RSSI protocol-events--------------------
    my @rssiList;
    foreach my $dName (HMinfo_getEntities($opt."d",$filter)){
      foreach my $dest (keys %{$defs{$dName}{helper}{rssi}}){
        my $dispName = $dName;
        my $dispDest = $dest;
        if ($dest =~ m/^at_(.*)/){
          $dispName = $1;
          $dispDest = (($dest =~ m/^to_rpt_/)?"rep_":"").$dName;
        }
        push @rssiList,sprintf("%-15s:%-15s %-15s %6.1f %6.1f %6.1f<%6.1f %5s"
                               ,$dName,$dispName,$dispDest
                               ,$defs{$dName}{helper}{rssi}{$dest}{lst}
                               ,$defs{$dName}{helper}{rssi}{$dest}{avg}
                               ,$defs{$dName}{helper}{rssi}{$dest}{min}
                               ,$defs{$dName}{helper}{rssi}{$dest}{max}
                               ,$defs{$dName}{helper}{rssi}{$dest}{cnt}
                               );
      }
    }
    $ret = $cmd." done:"."\n    "."Device         :receive         from             last   avg      min<max    count"
                        ."\n    ".(join "\n    ",sort @rssiList)
                         ;
  }
  elsif($cmd eq "register")   {##print register--------------------------------
    # devicenameFilter
    my $RegReply = "";
    my @noReg;
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      my $regs = CUL_HM_Get(CUL_HM_name2Hash($dName),$dName,"reg","all");
      if ($regs !~ m/[0-6]:/){
          push @noReg,$dName;
          next;
      }
      my ($peerOld,$ptOld,$ptLine,$peerLine) = ("","","                  ","                  ");
      foreach my $reg (split("\n",$regs)){
        my ($peer,$h1) = split ("\t",$reg);
        $peer =~s/ //g;
        if ($peer !~ m/3:/){
          $RegReply .= $reg."\n";
          next;
        }
        $peer =~s/3://;
        next if (!$h1);
        my ($regN,$h2) = split (":",$h1);
        my ($val,$unit) = split (" ",$h2);
        $unit = $unit?("[".$unit."]"):"   ";
        my ($pt,$rN) = ($1,$2) if ($regN =~m/(..)(.*)/);
        $rN .= $unit;
        $hash->{helper}{r}{$rN} = "" if (!defined($hash->{helper}{r}{$rN}));
        $hash->{helper}{r}{$rN} .= sprintf("%16s",$val);
        if ($pt ne $ptOld){
          $ptLine .= sprintf("%16s",$pt);
            $ptOld = $pt;
        }
        if ($peer ne $peerOld){
          $peerLine .= sprintf("%32s",$peer);
            $peerOld = $peer;
        }
      }
      $RegReply .= $peerLine."\n".$ptLine."\n";
      foreach my $rN (sort keys %{$hash->{helper}{r}}){
        $RegReply .= $rN.$hash->{helper}{r}{$rN}."\n";
      }
      delete $hash->{helper}{r};
    }
    $ret = "No regs found for:".join(",",sort @noReg)."\n\n"
           .$RegReply;
  }
  elsif($cmd eq "param")      {##print param ----------------------------------
    my @paramList;
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      my $id = $defs{$dName}{DEF};
      my ($found,$para) = HMinfo_getParam($id,@a);
      push @paramList,$para if($found || $optEmpty);
    }
    my $prtHdr = "entity              \t: ";
    $prtHdr .= sprintf("%-20s \t|",$_)foreach (@a);
    $ret = $cmd." done:"
               ."\n param list"  ."\n    "
               .$prtHdr          ."\n    "
               .(join "\n    ",sort @paramList)
           ;
  }
  elsif($cmd eq "regCheck")   {##check register--------------------------------
    my @entities = HMinfo_getEntities($opt."v",$filter);
    $ret = $cmd." done:" .HMinfo_regCheck(@entities);
  }
  elsif($cmd eq "peerCheck")  {##check peers-----------------------------------
    my @entities = HMinfo_getEntities($opt."v",$filter);
    $ret = $cmd." done:" .HMinfo_peerCheck(@entities);
  }
  elsif($cmd eq "configCheck"){##check peers and register----------------------
    my @entities = HMinfo_getEntities($opt."v",$filter);
    $ret = $cmd." done:" .HMinfo_regCheck(@entities)
                         .HMinfo_peerCheck(@entities)
                         .HMinfo_burstCheck(@entities)
                         .HMinfo_paramCheck(@entities);
  }
  elsif($cmd eq "peerXref")   {##print cross-references------------------------
    my @peerPairs;
    foreach my $dName (HMinfo_getEntities($opt,$filter)){
      my $peerIDs = AttrVal($dName,"peerIDs",undef);
      foreach (split",",$peerIDs){
        next if ($_ eq "00000000");
        my $pName = CUL_HM_id2Name($_);
        my $pPlist = AttrVal($pName,"peerIDs","");
        $pName =~ s/$dName\_chn:/self/;
        push @peerPairs,$dName." =>".$pName;
      }
    }
    $ret = $cmd." done:" ."\n x-ref list"  ."\n    ".(join "\n    ",sort @peerPairs)
                         ;
  }
  elsif($cmd eq "models")     {##print capability, models----------------------
    my $th = \%HMConfig::culHmModel;
    my @model;
    foreach (keys %{$th}){
      my $mode = $th->{$_}{rxt};
      $mode =~ s/c/config/;
      $mode =~ s/w/wakeup/;
      $mode =~ s/b/burst/;
      $mode =~ s/l/lazyConf/;
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
            .join"\n  ",grep(/$filter/,sort @model);
  }
  elsif($cmd eq "templateSet"){##template: set of register --------------------
    return HMinfo_templateSet(@a);
  }
  elsif($cmd eq "templateChk"){##template: see if it applies ------------------
    my $repl;
    foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
      unshift @a, $dName;
      $repl .= HMinfo_templateChk(@a);
      shift @a;
    }
    return $repl;
  }
  elsif($cmd eq "templateList"){##template: list templates --------------------
    return HMinfo_templateList($a[0]);
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
  elsif($cmd eq "tempList")   {##handle thermostat templist from file ---------
    $ret = HMinfo_tempList($filter,@a);
  }
  elsif($cmd eq "help")       {
    $ret = " Unknown argument $cmd, choose one of "
           ."\n ---checks---"
           ."\n configCheck [<typeFilter>]                     # perform regCheck and regCheck"
           ."\n regCheck [<typeFilter>]                        # find incomplete or inconsistant register readings"
           ."\n peerCheck [<typeFilter>]                       # find incomplete or inconsistant peer lists"
           ."\n ---actions---"
           ."\n saveConfig [<typeFilter>] <file>               # stores peers and register with saveConfig"
           ."\n loadConfig [<typeFilter>] <file>               # restores register and peer readings if missing"
           ."\n autoReadReg [<typeFilter>]                     # trigger update readings if attr autoReadReg is set"
           ."\n tempList [<typeFilter>][save|restore|verify][<filename>]# handle tempList of thermostat devices"
           ."\n ---infos---"
           ."\n update                                         # update HMindfo counts"
           ."\n register [<typeFilter>]                        # devicefilter parse devicename. Partial strings supported"
           ."\n peerXref [<typeFilter>]                        # peer cross-reference"
           ."\n models [<typeFilter>]                          # list of models incl native parameter"
           ."\n protoEvents [<typeFilter>] [short|long]        # protocol status - names can be filtered"
           ."\n msgStat                                        # view message statistic"
           ."\n param [<typeFilter>] [<param1>] [<param2>] ... # displays params for all entities as table"
           ."\n rssi [<typeFilter>]                            # displays receive level of the HM devices"
           ."\n       last: most recent"
           ."\n       avg:  average overall"
           ."\n       range: min to max value"
           ."\n       count: number of events in calculation"
           ."\n ---clear status---"
           ."\n clear [<typeFilter>] [Protocol|readings|msgStat|register|rssi]"
           ."\n       Protocol     # delete all protocol-events"
           ."\n       readings     # delete all readings"
           ."\n       register     # delete all register-readings"
           ."\n       rssi         # delete all rssi data"
           ."\n       msgStat      # delete message statistics"
           ."\n ---help---"
           ."\n help                            #"
           ."\n ***footnote***"
           ."\n [<nameFilter>]   : only matiching names are processed - partial names are possible"
           ."\n [<modelsFilter>] : any match in the output are searched. "
           ."\n"
           ."\n cpRegs <src:peer> <dst:peer>"
           ."\n        copy register for a channel or behavior of channel/peer"
           ."\n templateChk [<typeFilter>] <templateName> <peer:[long|short]> [<param1> ...] "
           ."\n        compare whether register match the template values"
           ."\n templateDef <entity> <templateName> <param1[:<param2>...] <description> <reg1>:<val1> [<reg2>:<val2>] ... "
           ."\n        define a template"
           ."\n templateList [<templateName>]         # gives a list of templates or a description of the named template"
           ."\n        list all currently defined templates or the structure of a given template"
           ."\n templateSet <entity> <templateName> <peer:[long|short]> [<param1> ...] "
           ."\n        write register according to a given template"
           ."\n ======= typeFilter options: supress class of devices  ===="
           ."\n set <name> <cmd> [-dcasev] [-f <filter>] [params]"
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
  elsif($cmd eq "loadConfig") {##action: saveConfig----------------------------
    $ret = HMinfo_loadConfig($filter,@a); 
  }
  elsif($cmd eq "saveConfig") {##action: saveConfig----------------------------
    my $id = ++$hash->{nb}{cnt};
    my $bl = BlockingCall("HMinfo_saveConfig", join(",",("$name:$id",$a[0],$opt,$filter)), 
                          "HMinfo_bpPost", 30, 
                          "HMinfo_bpAbort", "$name:$id");
    $hash->{nb}{$id}{$_} = $bl->{$_} foreach (keys %{$bl});
    $ret = $cmd." done:" ."\n saved";
  }
  else{
    my @cmdLst =     
           ( "autoReadReg","clear"  #"clear:msgStat,Protocol,readings,register,rssi"
            ,"configCheck","param","peerCheck","peerXref"
            ,"protoEvents","msgStat:view,clear","rssi"
            ,"models"
            ,"regCheck","register","saveConfig","loadConfig","update"
            ,"cpRegs"
            ,"tempList"
            ,"templateChk","templateDef","templateList","templateSet");
    $ret = join (" ",sort @cmdLst); 
  }
  return $ret;
}

sub HMinfo_loadConfig($@) {#####################################################
  my ($filter,$fName)=@_;
  $filter = "." if (!$filter);
  $fName = "regSave.cfg" if (!$fName);
  my $ret;

  open(aSave, "$fName") || return("Can't open $fName: $!");
  my @el = ();
  my @elAll = ();
  my @elincmpl = ();
  my @entryNF = ();
  while(<aSave>){
    chomp;
    my $line = $_;
    next if ($line !~ m/set (.*) (peerBulk|regBulk) (.*)/);
    my ($eN,$cmd,$param) = ($1,$2,$3);
    $eN =~ s/ //g;
    next if ($eN !~ m/$filter/);
    if (!$eN || !$defs{$eN}){
      push @entryNF,$eN;
      next;
    }
    if ($cmd eq "peerBulk"){
      next if(!$param);
      $param =~ s/ //g;
      if ($param !~ m/00000000/){
        push @elincmpl,"$eN peerList";
        next;
      }
      if (!AttrVal($eN,"peerIDs","")){
        CUL_HM_ID2PeerList($eN,$_,1) foreach (grep /[0-9A-F]{8}/,split(",",$param));
        push @el,"$eN peerIDs";
      }
    }
    elsif($cmd eq "regBulk"){
      my $exp = CUL_HM_getAttrInt($eN,"expert");
      $param =~ s/\.RegL/RegL/;
      $param =~ s/RegL/\.RegL/ if ($exp != 2);
      my ($reg,$data) = split(" ",$param,2);
      if ($data !~ m/00:00/){
        push @elincmpl,"$eN reg list:$reg";
        next;
      }
      if (!$defs{$eN}{READINGS}{$reg}){
        my ($list,$pN) = ($1,$2) if ($reg =~ m/RegL_(..):(.*)/);
        my $pId = CUL_HM_peerChId($pN,substr($defs{$eN}{DEF},0,6),"00000000");
        $defs{$eN}{READINGS}{$reg}{VAL} = $data;
        $defs{$eN}{READINGS}{$reg}{TIME} = "from file";
#        $defs{$eN}{READINGS}{$reg}{TIME} = "0000-00-00 00:00:00";
        CUL_HM_updtRegDisp($defs{$eN},$list,$pId);
        push @el,"$eN reg list:$reg";
      }
    }
  }
  $ret .= "\nadded data:\n     "          .join("\n     ",@el)       if (scalar@el);
  $ret .= "\nfile data incomplete:\n     ".join("\n     ",@elincmpl) if (scalar@elincmpl);
  $ret .= "\nentries not defind:\n     "  .join("\n     ",@entryNF)  if (scalar@entryNF);

  return $ret
}
sub HMinfo_saveConfig($) {#####################################################
  my ($param) = @_;
  my ($id,$file,$opt,$filter) = split ",",$param;
  my @entities;
  $file = "regSave.cfg" if (!$file);
  foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
    CUL_HM_Get($defs{$dName},$dName,"saveConfig",$file);
    push @entities,$dName;
    foreach my $chnId (CUL_HM_getAssChnIds($dName)){
      my $dName = CUL_HM_id2Name($chnId);
      push @entities, $dName if($dName !~ m/_chn:/);
    }
  }
  return $id;
}
sub HMinfo_bpPost($) {#bp finished#############################################
  my ($rep) = @_;
  my ($name,$id) = split(":",$rep);
  delete $defs{$name}{nb}{$id};
  return;
}
sub HMinfo_bpAbort($) {#bp timeout ############################################
  my ($rep) = @_;
  my ($name,$id) = split(":",$rep);
  delete $defs{$name}{nb}{$id};
  return;
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
  my %errFlt;
  my %err;
  my @errNames;
  foreach (@erro){    #prepare reading filter for error counts
    my ($p,@a) = split ":",$_;
    $errFlt{$p}{x}=1; # add at least one reading
    $errFlt{$p}{$_}=1 foreach (@a);
  }
  #--- used for IO, protocol  and communication (e.g. rssi)
  my @IOdev;

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
    push @shdwNames,$eName if (keys %{$ehash->{helper}{shadowReg}});
    foreach my $read (grep {$ehash->{READINGS}{$_}} @info){       #---- count critical readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      $sum{$read}{$val} =0 if (!$sum{$read}{$val});
      $sum{$read}{$val}++;
    }
    foreach my $read (grep {$ehash->{READINGS}{$_}} keys %errFlt){#---- count error readings
      my $val = $ehash->{READINGS}{$read}{VAL};
      next if (grep (/$val/,(keys%{$errFlt{$read}})));# filter non-Error
      $err{$read}{$val} =0 if (!$err{$read}{$val});
      $err{$read}{$val}++;
      push @errNames,$eName;
    }
    if ($ehash->{helper}{role}{dev}){#---restrict to devices
      $nbrD++;
      push @IOdev,$ehash->{IODev}{NAME} if($ehash->{IODev} && $ehash->{IODev}{NAME});
      push @Anames,$eName if ($attr{$eName}{actStatus} && $attr{$eName}{actStatus} ne "alive");

      foreach (grep /ErrIoId_/, keys %{$ehash}){# detect addtional critical entries
        my $k = $_;
        $k =~ s/^prot//;
        $protC{$k} = 0 if(!defined $protC{$_});
      }
      foreach (grep {$ehash->{"prot".$_}} keys %protC){#protocol critical alarms
        $protC{$_}++;
        push @protNamesC,$eName;
      }
      foreach (grep {$ehash->{"prot".$_}} keys %protE){#protocol errors
        $protE{$_}++;
        push @protNamesE,$eName;
      }
      foreach (grep {$ehash->{"prot".$_}} keys %protW){#protocol events reported
        $protW{$_}++;
        push @protNamesW,$eName;
      }
      $rssiMin{$eName} = 0;
      foreach (keys %{$ehash->{helper}{rssi}}){
        $rssiMin{$eName} = $ehash->{helper}{rssi}{$_}{min}
          if ($rssiMin{$eName} > $ehash->{helper}{rssi}{$_}{min});
      }
    }
  }
  #====== collection finished - start data preparation======
  delete $hash->{$_} foreach (grep(/^(ERR|W_|I_|C_)/,keys%{$hash}));# remove old
  my @updates;
  foreach my $read(grep {defined $sum{$_}} @info){       #--- disp crt count
    my $d;
    $d .= "$_:$sum{$read}{$_};"foreach(keys %{$sum{$read}});
    push @updates,"I_sum_$read:".$d;
  }
  foreach my $read(grep {defined $err{$_}} keys %errFlt){#--- disp err count
    my $d;
    $d .= "$_:$err{$read}{$_};"foreach(keys %{$err{$read}});
    push @updates,"ERR_$read:".$d;
  }

  @errNames = grep !/^$/,HMinfo_noDup(@errNames);
  $hash->{ERR_names} = join",",@errNames if(@errNames);# and name entities

  push @updates,"C_sumDefined:"."entities:$nbrE device:$nbrD channel:$nbrC virtual:$nbrV";
  # ------- display status of action detector ------
  push @updates,"I_actTotal:".$modules{CUL_HM}{defptr}{"000000"}{STATE};
  $hash->{ERRactNames} = join",",@Anames if (@Anames);

  # ------- what about IO devices??? ------
  my %tmp; # remove duplicates
  $tmp{$_}=0 for @IOdev;
  delete $tmp{""}; #remove empties if present
  @IOdev = sort keys %tmp;
  foreach (grep {$defs{$_}{READINGS}{cond}} @IOdev){
    $_ .= " :".$defs{$_}{READINGS}{cond}{VAL};
  }
  $hash->{I_HM_IOdevices}= join",",@IOdev;

  # ------- what about protocol events ------
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv
  my @tpc;
  push @tpc,"$_:$protC{$_}" foreach (grep {$protC{$_}} keys(%protC));
  if(@tpc){push @updates,"CRIT__protocol:".join",",@tpc;} else{delete $hash->{READINGS}{CRIT__protocol} };
  my @tpe;
  push @tpe,"$_:$protE{$_}" foreach (grep {$protE{$_}} keys(%protE));
  if(@tpe){push @updates,"ERR__protocol:".join",",@tpe;} else{ delete $hash->{READINGS}{ERR__protocol} };
  my @tpw;
  push @tpw,"$_:$protW{$_}" foreach (grep {$protW{$_}} keys(%protW));
  if(@tpw){push @updates,"W__protocol:".join",",@tpw  ;} else{ delete $hash->{READINGS}{W__protocol} };

  @protNamesC = grep !/^$/,HMinfo_noDup(@protNamesC);
  $hash->{CRI__protoNames} = join",",@protNamesC if(@protNamesC);
  @protNamesE = grep !/^$/,HMinfo_noDup(@protNamesE);
  $hash->{ERR__protoNames} = join",",@protNamesE if(@protNamesE);
  @protNamesW = grep !/^$/,HMinfo_noDup(@protNamesW);
  $hash->{W__protoNames} = join",",@protNamesW if(@protNamesW);

  if (defined $modules{CUL_HM}{helper}{qReqConf} &&
      @{$modules{CUL_HM}{helper}{qReqConf}}>0){
    $hash->{I_autoReadPend} = join ",",@{$modules{CUL_HM}{helper}{qReqConf}};
    push @updates,"I_autoReadPend:". scalar @{$modules{CUL_HM}{helper}{qReqConf}};
  }
#  else{
#    delete $hash->{I_autoReadPend};
#  }

  # ------- what about rssi low readings ------
  foreach (grep {$rssiMin{$_} != 0}keys %rssiMin){
    if    ($rssiMin{$_}> -60) {$rssiMinCnt{"59<"}++;}
    elsif ($rssiMin{$_}> -80) {$rssiMinCnt{"60>"}++;}
    elsif ($rssiMin{$_}< -99) {$rssiMinCnt{"99>"}++;
                               push @rssiNames,$_  ;}
    else                      {$rssiMinCnt{"80>"}++;}
  }

  my $d ="";
  $d .= "$_:$rssiMinCnt{$_} " foreach (sort keys %rssiMinCnt);
  push @updates,"I_rssiMinLevel:".$d;
  $hash->{ERR___rssiCrit} = join(",",@rssiNames) if (@rssiNames);
  # ------- what about others ------
  $hash->{W_unConfRegs} = join(",",@shdwNames) if (@shdwNames > 0);
  # ------- update own status ------
  $hash->{STATE} = "updated:".TimeNow();
  my $updt = join",",@updates;
  foreach (grep /^(W_|I_|ERR)/,keys%{$hash->{READINGS}}){
    delete $hash->{READINGS}{$_} if ($updt !~ m /$_/);
  }
  readingsBeginUpdate($hash);
  foreach my $rd (@updates){
    next if (!$rd);
    my ($rdName, $rdVal) = split(":",$rd, 2);
    next if (defined $hash->{READINGS}{$rdName} &&
             $hash->{READINGS}{$rdName}{VAL} eq $rdVal);
    readingsBulkUpdate($hash,$rdName,
                             ((defined($rdVal) && $rdVal ne "")?$rdVal:"-"));
  }
  readingsEndUpdate($hash,1);
  return;
}

my %tpl = (
   autoOff           => {p=>"time"             ,t=>"staircase - auto off after <time>, extend time with each trigger"
                    ,reg=>{ OnTime          =>"p0"
                           ,OffTime         =>111600
                     }}
  ,motionOnDim       => {p=>"ontime brightness",t=>"Dimmer:on for time if MDIR-brightness below level"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p1"
                           ,CtRampOn        =>"ltLo"
                           ,CtRampOff       =>"ltLo"
                           ,OffTime         =>111600
                           ,OnTime          =>"p0"

                           ,ActionTypeDim   =>"jmpToTarget"
                           ,DimJtOn         =>"on"
                           ,DimJtOff        =>"dlyOn"
                           ,DimJtDlyOn      =>"rampOn"
                           ,DimJtDlyOff     =>"dlyOn"
                           ,DimJtRampOn     =>"on"
                           ,DimJtRampOff    =>"dlyOn"
                     }}
  ,motionOnSw        => {p=>"ontime brightness",t=>"Switch:on for time if MDIR-brightness below level"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p1"
                           ,OffTime         =>111600
                           ,OnTime          =>"p0"

                           ,ActionType      =>"jmpToTarget"
                           ,SwJtOn          =>"on"
                           ,SwJtOff         =>"dlyOn"
                           ,SwJtDlyOn       =>"on"
                           ,SwJtDlyOff      =>"dlyOn"
                    }}
  ,SwCondAbove       => {p=>"condition"        ,t=>"Switch:execute only if condition level is above limit"
                    ,reg=>{ CtDlyOn         =>"geLo"
                           ,CtDlyOff        =>"geLo"
                           ,CtOn            =>"geLo"
                           ,CtOff           =>"geLo"
                           ,CtValLo         =>"p0"
                     }}
  ,SwCondBelow       => {p=>"condition"        ,t=>"Switch:execute only if condition level is below limit"
                    ,reg=>{ CtDlyOn         =>"ltLo"
                           ,CtDlyOff        =>"ltLo"
                           ,CtOn            =>"ltLo"
                           ,CtOff           =>"ltLo"
                           ,CtValLo         =>"p0"
                     }}
  ,SwOnCond          => {p=>"level cond"       ,t=>"switch:execute only if condition [geLo|ltLo] level is below limit"
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
);

sub HMinfo_templateDef(@){#####################################################
  my ($name,$param,$desc,@regs) = @_;
  return "insufficient parameter" if(!defined $param);
  if ($param eq "del"){
    delete $tpl{$name};
    return;
  }
  # get description if marked wir ""
  if ($desc =~ m/^"/){
    my $cnt = 0;
    foreach (@regs){
      $desc .= " ".$_;
      $cnt++;
      last if ($desc =~ m/"$/);
    }
    $desc =~ s/"//g;
    splice @regs,0,$cnt;
  }

  return "$name already defined, delete it first" if($tpl{$name});
  return "insufficient parameter" if(@regs < 1);
  $tpl{$name}{p} = "";
  $tpl{$name}{p} = join(" ",split(":",$param)) if($param ne "0");
  $tpl{$name}{t} = $desc;
  my $paramNo = split(":",$param);
  foreach (@regs){
    my ($r,$v)=split":",$_;
    if (!defined $v){
      delete $tpl{$name};
      return " empty reg value for $r";
    }
    elsif($v =~ m/^p(.)/){
      return ($1+1)." params are necessary, only $paramNo aregiven"
            if (($1+1)>$paramNo);
    }
    $tpl{$name}{reg}{$r} = $v;
  }
}
sub HMinfo_templateSet(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  $pSet = ":" if (!$pSet || $pSet eq "none");
  my ($pName,$pTyp) = split(":",$pSet);
  return "template undefined $tmpl"                       if(!$tpl{$tmpl});
  return "aktor $aName unknown"                           if(!$defs{$aName});
  return "exec set $aName getConfig first"                if(!(grep /RegL_/,keys%{$defs{$aName}{READINGS}}));
  return "give <peer>:[short|long] with peer, not $pSet"  if($pName && $pTyp !~ m/(short|long)/);
  $pSet = $pTyp ? ($pTyp eq "long"?"lg":"sh"):"";
  my $aHash = $defs{$aName};

  my @regCh;
  foreach (keys%{$tpl{$tmpl}{reg}}){
    my $regN = $pSet.$_;
    my $regV = $tpl{$tmpl}{reg}{$_};
    if ($regV =~m /^p(.)$/) {#replace with User parameter
      return "insufficient values - at least ".$tpl{p}." are $1 necessary" if (@p < ($1+1));
      $regV = $p[$1];
    }
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet",$regN,"?",$pName);
    return "Device doesn't support $regN - template $tmpl not applicable" if ($ret =~ m/failed:/);
    return "peer necessary for template"                                  if ($ret =~ m/peer required/ && !$pName);
    return "Device doesn't support literal $regV for reg $regN"           if ($ret =~ m/literal:/ && $ret !~ m/\b$regV\b/);
    my ($min,$max) = ($1,$2) if ($ret =~ m/range:(.*) to (.*) :/);
    $max = 0 if (!$max);
    $max =~ s/([0-9\.]+).*/$1/;
    return "$regV out of range:  $min to $max"                            if ($min && ($regV < $min || ($max && $regV > $max)));
    push @regCh,"$regN,$regV";
  }
  foreach (@regCh){#Finally write to shadow register.
    my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","prep",split(",",$_),$pName);
    return $ret if ($ret);
  }
  my ($ret,undef) = CUL_HM_Set($aHash,$aName,"regSet","exec",split(",",$regCh[0]),$pName);
  return $ret;
}
sub HMinfo_templateChk(@){#####################################################
  my ($aName,$tmpl,$pSet,@p) = @_;
  $pSet = "" if (!$pSet || $pSet eq "none");
  my ($pName,$pTyp) = split(":",$pSet);
  return "template undefined $tmpl\n"                     if(!$tpl{$tmpl});
  return "aktor $aName unknown\n"                         if(!$defs{$aName});
  return "give <peer>:[short|long|all] wrong:$pTyp\n"     if($pTyp && $pTyp !~ m/(short|long|all)/);

  my @pNames;
  if ($pName eq "all"){
    my $dId = substr(CUL_HM_name2Id($aName),0,6);
    foreach (grep !/00000000/,split(",",AttrVal($aName,"peerIDs",""))){
      push @pNames,CUL_HM_peerChName($_,$dId,"").":long"  if (!$pTyp || $pTyp ne "short");
      push @pNames,CUL_HM_peerChName($_,$dId,"").":short" if (!$pTyp || $pTyp ne "long");
    }
  }
  elsif(($pName && !$pTyp) || $pTyp eq "all"){
    push @pNames,$pName.":long";
    push @pNames,$pName.":short";
  }
  else{
    push @pNames,$pSet;
  }

  my $repl = "";
  foreach my $pS (@pNames){
    ($pName,$pTyp) = split(":",$pS);
    my $replPeer="";
    if($pName && (grep !/$pName/,ReadingsVal($aName,"peerList" ,undef))){
      $replPeer="  no peer:$pName\n";
    }
    else{
      my $pRnm = $pName?($pName."-".($pTyp eq "long"?"lg":"sh")):"";
      foreach my $rn (keys%{$tpl{$tmpl}{reg}}){
        my $regV = ReadingsVal($aName,"R-$pRnm$rn" ,undef);
        $regV    = ReadingsVal($aName,".R-$pRnm$rn",undef) if (!defined $regV);
        $regV    = ReadingsVal($aName,"R-".$rn     ,undef) if (!defined $regV);
        $regV    = ReadingsVal($aName,".R-".$rn    ,undef) if (!defined $regV);
        if (defined $regV){
          $regV =~s/ .*//;#strip unit
          my $tplV = $tpl{$tmpl}{reg}{$rn};
          if ($tplV =~m /^p(.)$/) {#replace with User parameter
            return "insufficient data - at least ".$tpl{p}." are $1 necessary"
                                                           if (@p < ($1+1));
            $tplV = $p[$1];
          }
          $replPeer .= "  $rn :$regV should $tplV \n" if ($regV ne $tplV);
        }
        else{
          $replPeer .= "  reg not found: $rn\n";
        }
      }
    }
    $repl .= "$aName $pS-> ".($replPeer?"failed\n$replPeer":"match\n");
  }
  return ($repl?$repl:"template $tmpl match actor:$aName peer:$pSet");
}
sub HMinfo_templateList($){####################################################
  my $templ = shift;
  my $reply = "";
#  if(!$templ || !(grep /$templ/,keys%tpl)){# list all templates
  if(!($templ && (grep /$templ/,keys%tpl))){# list all templates
    foreach (sort keys%tpl){
      $reply .= sprintf("%-16s params:%-24s Info:%s\n"
                             ,$_
                               ,$tpl{$_}{p}
                               ,$tpl{$_}{t}
                       );
    }
  }
  else{#details about one template
    $reply = sprintf("%-16s params:%-24s Info:%s\n",$templ,$tpl{$templ}{p},$tpl{$templ}{t});
    foreach (sort keys %{$tpl{$templ}{reg}}){
      my $val = $tpl{$templ}{reg}{$_};
      if ($val =~m /^p(.)$/){
        my @a = split(" ",$tpl{$templ}{p});
        $val = $a[$1];
      }
      $reply .= sprintf("  %-16s :%s\n",$_,$val);
    }
  }
  return $reply;
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
    if   ($srcP =~ m/self(.*)/)      {$srcPid = $defs{$srcCh}{DEF}.sprintf("%02X",$1)}
    elsif($srcP =~ m/^[A-F0-9]{8}$/i){$srcPid = $srcP;}
    elsif($srcP =~ m/(.*)_chn:(..)/) {$srcPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$srcP})              {$srcPid = $defs{$srcP}{DEF}.$2;}

    if   ($dstP =~ m/self(.*)/)      {$dstPid = $defs{$dstCh}{DEF}.sprintf("%02X",$1)}
    elsif($dstP =~ m/^[A-F0-9]{8}$/i){$dstPid = $dstP;}
    elsif($dstP =~ m/(.*)_chn:(..)/) {$dstPid = $defs{$1}->{DEF}.$2;}
    elsif($defs{$dstP})              {$dstPid = $defs{$dstP}{DEF}.$2;}

    return "invalid peers src:$srcP dst:$dstP" if(!$srcPid || !$dstPid);
    return "sourcepeer not in peerlist"        if ($attr{$srcCh}{peerIDs} !~ m/$srcPid/);
    return "destination peer not in peerlist"  if ($attr{$dstCh}{peerIDs} !~ m/$dstPid/);

    if   ($defs{$srcCh}{READINGS}{"RegL_03:".$srcP})  {$srcRegLn =  "RegL_03:".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_03:".$srcP}) {$srcRegLn = ".RegL_03:".$srcP}
    elsif($defs{$srcCh}{READINGS}{"RegL_04:".$srcP})  {$srcRegLn =  "RegL_04:".$srcP}
    elsif($defs{$srcCh}{READINGS}{".RegL_04:".$srcP}) {$srcRegLn = ".RegL_04:".$srcP}
    $dstRegLn = $srcRegLn;
    $dstRegLn =~ s/:.*/:/;
    $dstRegLn .= $dstP;
  }
  else{
    if   ($defs{$srcCh}{READINGS}{"RegL_01:"})  {$srcRegLn = "RegL_01:"}
    elsif($defs{$srcCh}{READINGS}{".RegL_01:"}) {$srcRegLn = ".RegL_01:"}
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
sub HMinfo_noDup(@) {#return list with no duplicates
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep {defined($_)} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}

1;
=pod
=begin html

<a name="HMinfo"></a>
<h3>HMinfo</h3>
<ul>
  <tr><td>
  HMinfo is a module to support getting an overview  of
  eQ-3 HomeMatic devices as defines in <a href="#CUL_HM">CUL_HM</a>. <br><br>
  <B>Status information and counter</B><br>
  HMinfo gives an overview on the CUL_HM installed base including current conditions.
  Readings and counter will not be updated automatically  due to performance issues. <br>
  Command <a href="#HMinfoupdate">update</a> must be used to refresh the values. 
  <ul><code><br>
           set hm update<br>
  </code></ul><br>
  Webview of HMinfo will provide details, basically counter about how
  many CUL_HM entities experience exceptional conditions. Areas provided are
  <ul>
      <li>Action Detector status</li>
      <li>CUL_HM related IO devices and condition</li>
      <li>Device protocol events which are related to communication errors</li>
      <li>count of certain readings (e.g. batterie) and conditions - <a href="#HMinfoattr">attribut controlled</a></li>
      <li>count of error condition in readings (e.g. overheat, motorError) - <a href="#HMinfoattr">attribut controlled</a></li>
  </ul>
  <br>

  It also allows some HM wide commands such
  as store all collected register settings.<br><br>

  Commands will be executed on all HM entities of the installation.
  If applicable and evident execution is restricted to related entities.
  In fact, rssi is executed on devices only because channels do not support rssi values.<br><br>
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
        </ul>
        and/or a filter for <b>names</b>:<br>
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

  <a name="HMinfoset"><b>Set</b></a>
  <ul>
  even though the commands are more a get funktion they are implemented
  as set to allow simple web interface usage<br>
    <ul>
      <li><a name="#HMinfoupdate">update</a><br>
          updates HM status counter.
      </li>
      <li><a name="#HMinfomodels">models</a><br>
          list all HM models that are supported in FHEM
      </li>
      <li><a name="#HMinfoparam">param</a> <a href="#HMinfoFilter">[filter]</a> &lt;name&gt; &lt;name&gt;...<br>
          returns a table parameter values (attribute, readings,...)
          for all entities as a table
      </li>
      <li><a name="#HMinfopeerXref">peerXref</a> <a href="#HMinfoFilter">[filter]</a><br>
          provides a cross-reference on peerings, a kind of who-with-who summary over HM
      </li>
      <li><a name="#HMinforegister">register</a> <a href="#HMinfoFilter">[filter]</a><br>
          provides a tableview of register of an entity
      </li>

      <li><a name="#HMinfoconfigCheck">configCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check of HM settings. It includes regCheck and peerCheck
      </li>
      <li><a name="#HMinfopeerCheck">peerCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check on peers. If a peer is set in one channel
          this funktion will search wether the peer also exist on the opposit side.
      </li>
      <li><a name="#HMinforegCheck">regCheck</a> <a href="#HMinfoFilter">[filter]</a><br>
          performs a consistency check on register readings for completeness
      </li>

      <li><a name="#HMinfoautoReadReg">autoReadReg</a> <a href="#HMinfoFilter">[filter]</a><br>
          schedules a read of the configuration for the CUL_HM devices with attribut autoReadReg set to 1 or higher.
      </li>
      <li><a name="#HMinfoclear">clear [Protocol|readings|msgStat|register|rssi]</a> <a href="#HMinfoFilter">[filter]</a><br>
          executes a set clear ...  on all HM entities<br>
          <ul>
          <li>Protocol relates to set clear msgEvents</li>
          <li>readings relates to set clear readings</li>
          <li>rssi clears all rssi counters </li>
          <li>msgStat clear HM general message statistics</li>
          <li>register clears all register-entries in readings</li>
          </ul>
      </li>
      <li><a name="#HMinfosaveConfig">saveConfig</a> <a href="#HMinfoFilter">[filter] [&lt;file&gt;]</a><br>
          performs a save for all HM register setting and peers. See <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>.
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
         <br>
      <li><a name="#HMinfotempList">tempList</a> <a href="#HMinfoFilter">[filter]</a>[save|restore|verify] [&lt;file&gt;]</a><br>
          this function supports handling of tempList for thermstates.
          It allows templists to be saved in a separate file, verify settings against the file
          and write the templist of the file to the devices. <br>
          <li><B>save</B> saves tempList readings of the system to the file. <br>
              Note that templist as available in FHEM is put to the file. It is up to the user to make
              sure the data is actual<br>
              Storage is not cumulative - former content of the file will be removed</li>
          <li><B>restore</B> available templist as defined in the file are written directly 
              to the device</li>
          <li><B>verify</B> file data is compared to readings as present in FHEM. It does not
              verify data in the device - user needs to ensure actuallity of present readings</li>
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
                       and coule be an onTime or brightnesslevel. a list of parameter needs to be separated with colon<br>
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
        </code></ul>
      </li>
      <li><a name="#HMinfotemplateList">templateList [&lt;name&gt;]</a><br>
          list defined templates. If no name is given all templates will be listed<br>
      </li>
      <li><a name="#HMinfotemplateChk">templateChk <a href="#HMinfoFilter">[filter] &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]</a><br>
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
        </code></ul>
      </li>
      <li><a name="#HMinfotemplateSet">templateSet &lt;entity&gt; &lt;template&gt; &lt;peer:[long|short]&gt; [&lt;param1&gt; ...]</a><br>
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
    </ul>
  </ul>
  <br>

  <a name="HMinfoget"></a>
  <b>Get</b>
  <ul> N/A </ul>
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
    <li><a name="#HMhmAutoReadScan">hmAutoReadScan</a>
        defines the time in seconds CUL_HM tries to schedule the next autoRead
        from the queue. Despide this timer FHEM will take care that only one device from the queue will be
        handled at one point in time. With this timer user can stretch timing even further - to up to 300sec
        min delay between execution. <br>
        Setting to 1 still obeys the "only one at a time" prinzip.<br>
        Note that compressing will increase message load while stretch will extent waiting time.
        data. <br>
    </li>
    <li><a name="#HMhmIoMaxDly">hmIoMaxDly</a>
        max time in seconds CUL_HM stacks messages if the IO device is not ready to send.
        If the IO device will not reappear in time all command will be deleted and IOErr will be reported.<br>
        Note: commands will be executed after the IO device reappears - which could lead to unexpected
        activity long after command issue.<br>
        default is 60sec. max value is 3600sec<br>
    </li>
    <li><a name="#HMhmManualOper">hmManualOper</a>
        set to 1 will prevent any automatic operation, update or default settings
        in CUL_HM.<br>
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
=cut
