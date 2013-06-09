##############################################
# $Id$
package main;
use strict;
use warnings;
use POSIX;

sub CommandXmlList($$);
sub XmlEscape($);
use Blocking;

sub HMinfo_Initialize($$) {####################################################
  my ($hash) = @_;

  $hash->{DefFn}     = "HMinfo_Define";
  $hash->{SetFn}     = "HMinfo_SetFn";
}
sub HMinfo_Define($$){#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  $hash->{Version} = "01";
  $attr{$name}{webCmd} = "protoEvents:rssi:peerXref:configCheck:models";
  return;
}
sub HMinfo_getParam(@) { ######################################################
  my ($id,@param) = @_;
  my @paramList;
  my $ehash = $modules{CUL_HM}{defptr}{$id};
  my $eName = $ehash->{NAME};
  my $found = 0;
  foreach (@param){
    my $para = CUL_HM_Get($ehash,$eName,"param",$_);
    push @paramList,sprintf("%-20s",($para eq "undefined"?"-":$para));
	$found = 1 if ($para ne "undefined") ;
  }
  return $found,sprintf("%-20s: %s",$eName,join "\t|",@paramList);
  return sprintf("%-20s: %s",$eName,join "\t|",@paramList);
}
sub HMinfo_regCheck(@) { ######################################################
  my @entities = @_;
  my @regIncompl;
  my @peerRegsFail;
  foreach my $eName (@entities){
    my $ehash = $defs{$eName};
    my $devId = substr($defs{$eName}{DEF},0,6);
    my @peerIdInReg;
    foreach my $rdEntry (keys %{$ehash->{READINGS}}){
      next if ($rdEntry !~m /^[\.]?RegL_(.*)/);
	  push @regIncompl,$eName.":".$rdEntry if ($ehash->{READINGS}{$rdEntry}{VAL} !~ m/00:00/);
	  my $peer = $rdEntry;
	  $peer =~ s/.*RegL_..://;
	  $peer =~ s/^self/$devId/;
	  next if (!$peer);  
	  push @peerIdInReg,CUL_HM_name2Id($peer);
    }
	#- - - -  check whether peer is required - - - - 
	my $st = CUL_HM_Get($defs{$eName},$eName,"param","subType");
	if ($st !~ m/(thermostat|smokeDetector)/){
      my $peerLinReg = (join ",",sort @peerIdInReg);
      $peerLinReg .= "," if ($peerLinReg);
      my $peerIDs = AttrVal($eName,"peerIDs","");
      $peerIDs =~ s/00000000,//;
      push @peerRegsFail,$eName." - found:".$peerLinReg." expected:".$peerIDs 
                         if ($peerLinReg ne $peerIDs);
	}
  }
  return  "\n incomplete register set\n    " .(join "\n    ",sort @regIncompl)
         ."\n missing Peer Registerset\n    ".(join "\n    ",sort @peerRegsFail)
         ;
}
sub HMinfo_peerCheck(@) { #####################################################
  my @entities = @_;
  my @peerIDsFail;
  my @peerIDsEmpty;
  my @peerIDsNoPeer;
  my %th = CUL_HM_putHash("culHmModel");
  foreach my $eName (@entities){
	my $ehash = $defs{$eName};
	my $id = $defs{$eName}{DEF};
	my $devId = substr($id,0,6);
	my $st = AttrVal(CUL_HM_id2Name($devId),"subType","");# from Master
    my $md = AttrVal(CUL_HM_id2Name($devId),"model","");
	my $peerIDs = AttrVal($eName,"peerIDs",undef);
	if (!$peerIDs){                # no peers - is this correct?
	  next if (length($id) == 6 && $ehash->{channel_01});#device with channels - no peers on device level
	  next if ($st eq "virtual");                        # virtuals may not have peers
	  
	  my $list;
      foreach (keys %th){
        $list = $th{$_}{lst} if ($th{$_}{name} eq $md);
      }
      
	  # should not be empty for SD
	  # should not be empty for entities with List 3 or 4
	  push @peerIDsEmpty,"empty critical: "    .$eName  if ($st eq "smokeDetector");
	  push @peerIDsEmpty,"empty: "    .$eName           if($list =~ m/[34]/);        #those should have peers
	}
	elsif($peerIDs !~ m/00000000/ && $st ne "virtual"){#peerList incomplete
	  push @peerIDsFail,"incomplete: ".$eName.":".$peerIDs;
	}
	else{# work on a valid list:
	  foreach (split",",$peerIDs){
		next if ($_ eq "00000000" ||$_ =~m /$devId/);
	    my $pName = CUL_HM_id2Name($_);
		$pName =~s/_chn:01//;           #channel 01 could be covered by device
		my $pPlist = AttrVal($pName,"peerIDs","");
	    push @peerIDsNoPeer,$eName." p:".$pName if ($pPlist !~ m/$id/);
	  }
	}
  }
  return  "\n incomplete list"  ."\n    ".(join "\n    ",sort @peerIDsFail)
         ."\n empty list"       ."\n    ".(join "\n    ",sort @peerIDsEmpty)
         ."\n peer not verified"."\n    ".(join "\n    ",sort @peerIDsNoPeer)
         ;
}
sub HMinfo_getEntities(@) { ###################################################
  my ($filter,$re) = @_;
  my @names;
  my ($doDev,$doChn,$noVrt,$noPhy,$noAct,$noSen,$doEmp);
  $doDev=$doChn=$doEmp= 1;
  $noVrt=$noPhy=$noAct=$noSen = 0;
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
	next if (!(($doDev && length($id) == 6) ||
	           ($doChn && $isChn)));
	next if  ($noVrt && $eMd =~ m/^virtual/);
	next if  ($noPhy && $eMd !~ m/^virtual/);
	my $eSt = CUL_HM_Get($eHash,$eName,"param","subType");
	
    next if ($noSen && $eSt =~ m/^(THSensor|remote|pushButton|threeStateSensor|sensor|motionDetector|swi)$/);
    next if ($noAct && $eSt =~ m/^(switch|blindActuator|dimmer|thermostat|smokeDetector|KFM100|outputUnit)$/);
	next if ($eName !~ m/$re/);
	push @names,$eName;
  }
  return sort(@names);
}

sub HMinfo_SetFn($$) {#########################################################
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

  if   ($cmd eq "?" )         {##actionImmediate: clear parameter--------------
	return "autoReadReg clear configCheck param peerCheck peerXref protoEvents models regCheck register rssi saveConfig";
  }
  elsif($cmd eq "clear" )     {##actionImmediate: clear parameter--------------
    my ($type) = @a;
	$opt .= "d" if ($type ne "Readings");# readings apply to all, others device only
	my @entities;
	foreach my $dName (HMinfo_getEntities($opt."v",$filter)){
	  push @entities,$dName;
	  if ($type eq "Rssi"){
	    delete $defs{$dName}{helper}{rssi};
	    next;
	  }
	  CUL_HM_Set($defs{$dName},$dName,"clear",(($type eq "Protocol")?"msgEvents":"readings"));
	}
	return $cmd.$type." done:" ."\n cleared"  ."\n    ".(join "\n    ",sort @entities)
						 ;
  }
  elsif($cmd eq "autoReadReg"){##actionImmediate: re-issue register Read-------
	my @entities;
	foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
	  next if (!substr(AttrVal($dName,"autoReadReg","0"),0,1));
	  
      my @arr;
      if(!$modules{CUL_HM}{helper}{updtCfgLst}){
        $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
      }
	  push @{$modules{CUL_HM}{helper}{updtCfgLst}}, $dName;
	  RemoveInternalTimer("updateConfig");
      InternalTimer(gettimeofday()+5,"CUL_HM_autoReadConfig", "updateConfig", 0);
	  push @entities,$dName;
	}
	return $cmd." done:" ."\n cleared"  ."\n    ".(join "\n    ",sort @entities)
						 ;
  }
  elsif($cmd eq "protoEvents"){##print protocol-events-------------------------
	my @paramList;
	foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
	  my $id = $defs{$dName}{DEF};
      my ($found,$para) = HMinfo_getParam($id,"protState","protCmdPend","protSnd",
	                          "protLastRcv","protResndFail","protResnd","protNack");
	  $para =~ s/ last_at//g;
      push @paramList,$para;
	}
	my $hdr = sprintf("%-20s:%-23s|%-23s|%-23s|%-23s|%-23s|%-23s|%-23s",
	                  "name","protState","protCmdPend","protSnd",
	                  "protLastRcv","protResndFail","protResnd","protNack");
	$ret = $cmd." done:" ."\n    ".$hdr  ."\n    ".(join "\n    ",sort @paramList)
	       ;
  }
  elsif($cmd eq "rssi")       {##print RSSI protocol-events--------------------
	my @rssiList;
	foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
      foreach my $dest (keys %{$defs{$dName}{helper}{rssi}}){
	    my $dispName = $dName;
	    my $dispDest = $dest;
	    if ($dest =~ m/^at_(.*)/){
		  $dispName = $1;
		  $dispName =~ s/^rpt_//;
		  $dispDest = (($dest =~ m/^to_rpt_/)?"rep_":"").$dName;
		}
		push @rssiList,sprintf("%-15s %-15s %6.1f %6.1f %6.1f<%6.1f %3s"
		                       ,$dispName,$dispDest
							   ,$defs{$dName}{helper}{rssi}{$dest}{lst}
		                       ,$defs{$dName}{helper}{rssi}{$dest}{avg}
		                       ,$defs{$dName}{helper}{rssi}{$dest}{min}
		                       ,$defs{$dName}{helper}{rssi}{$dest}{max}
		                       ,$defs{$dName}{helper}{rssi}{$dest}{cnt}
							   );
	  }
	}
	$ret = $cmd." done:"."\n    "."receive         from             last   avg      min<max    count"
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
	$ret = $cmd." done:" ."\n param list"  ."\n    ".(join "\n    ",sort @paramList)
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
	                     .HMinfo_peerCheck(@entities);
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
    my %th = CUL_HM_putHash("culHmModel");
	my @model;
	foreach (keys %th){
	  my $mode = $th{$_}{rxt};
	  $mode =~ s/c/config/;
	  $mode =~ s/w/wakeup/;
	  $mode =~ s/b/burst/;
	  $mode =~ s/:/,/;
	  $mode = "normal" if (!$mode);
	  my $list = $th{$_}{lst};
	  $list =~ s/.://g;
	  $list =~ s/p//;
	  my $chan = "";
	  foreach (split",",$th{$_}{chn}){
	    my ($n,$s,$e) = split(":",$_);
	    $chan .= $s.(($s eq $e)?"":("-".$e))." ".$n.", ";
	  }
	  push @model,sprintf("%-16s %-24s %4s %-13s %-5s %-5s %s"
						  ,$th{$_}{st}
	                      ,$th{$_}{name}
	                      ,$_
						  ,$mode
						  ,$th{$_}{cyc}
						  ,$list
						  ,$chan
						  );  
	}
	$ret = $cmd.($filter?" filtered":"").":$filter\n  " 
	       .sprintf("%-16s %-24s %4s %-13s %-5s %-5s %s\n  "
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
  elsif($cmd eq "help")       {
	$ret = " Unknown argument $cmd, choose one of "
		   ."\n ---checks---"
	       ."\n configCheck [<typeFilter>]                     # perform regCheck and regCheck"
	       ."\n regCheck [<typeFilter>]                        # find incomplete or inconsistant register readings"
	       ."\n peerCheck [<typeFilter>]                       # find incomplete or inconsistant peer lists"
		   ."\n ---actions---"                                   
	       ."\n saveConfig [<typeFilter>] <file>               # stores peers and register with saveConfig"       
	       ."\n autoReadReg [<typeFilter>]                     # trigger update readings if attr autoReadReg is set"       
		   ."\n ---infos---"                                   
	       ."\n register [<typeFilter>]                        # devicefilter parse devicename. Partial strings supported"  
	       ."\n peerXref [<typeFilter>]                         peer cross-reference"
	       ."\n models [<typeFilter>]                          # list of models incl native parameter"
	       ."\n protoEvents [<typeFilter>]                     # protocol status - names can be filtered"
	       ."\n param [<typeFilter>] [<param1>] [<param2>] ... # displays params for all entities as table"   
	       ."\n rssi [<typeFilter>]                            # displays receive level of the HM devices"   
	       ."\n       last: most recent"
	       ."\n       avg:  average overall"
	       ."\n       range: min to max value"
	       ."\n       count: number of events in calculation"
		   ."\n ---clear status---"                    
	       ."\n clear [<typeFilter>] [Protocol|Readings|Rssi]"       
	       ."\n       Protocol     # delete all protocol-events"       
	       ."\n       Readings     # delete all readings"       
	       ."\n       Rssi         # delete all rssi data"       
		   ."\n ---help---"                    
	       ."\n help                            #"       
		   ."\n ***footnote***"
	       ."\n [<nameFilter>]   : only matiching names are processed - partial names are possible"       
	       ."\n [<modelsFilter>] : any match in the output are searched. "       
	       ."\n"       
	       ."\n ======= typeFilter options: supress class of devices  ===="       
	       ."\n set <name> <cmd> [-dcasev] [-f <filter>] [params]"       
	       ."\n      entities according to list will be processed"       
	       ."\n      d - device   :include devices"
	       ."\n      c - channels :include channels"
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
  else                        {## go for delayed action
    $hash->{helper}{childCnt} = 0 if (!$hash->{helper}{childCnt});
	my $chCnt = ($hash->{helper}{childCnt}+1)%1000;
    my $childName = "child_".$chCnt;
	
	
#    my $blkH = BlockingCall("HMinfo_SetFnDly", 
#	                         join( ",",($childName,$name,$cmd,$opt,$optEmpty,$filter,@a)), 
#		                     "HMinfo_post", 
#		                     10);
#    $hash->{helper}{child}{$childName} = " started:".gettimeofday();
#    $hash->{helper}{childCnt} = $chCnt;
#	 my $chPid = $blkH->{pid};
#    Log 1,"General parent started $childName PID:$chPid ".$hash->{helper}{child}{$childName};
#    return "unblock started $childName PID:$chPid ".$hash->{helper}{child}{$childName};


    return HMinfo_SetFnDly(join(",",($childName,$name,$cmd,$opt,$optEmpty,$filter,@a)));
  }
  return $ret;
}

sub HMinfo_SetFnDly($) {#######################################################
  my $in = shift;
  my ($childName,$name,$cmd,$opt,$optEmpty,$filter,@a) = split",",$in;
  my $ret;
  my $hash = $defs{$name};
  if   ($cmd eq "saveConfig") {##action: saveConfig----------------------------
    my ($file) = @a;
	my @entities;
	foreach my $dName (HMinfo_getEntities($opt."dv",$filter)){
	  CUL_HM_Get($defs{$dName},$dName,"saveConfig",$file);
	  push @entities,$dName;
	  foreach my $chnId (CUL_HM_getAssChnIds($dName)){
		  my $dName = CUL_HM_id2Name($chnId);
		  push @entities, $dName if($dName !~ m/_chn:/);
	  }
	}
	$ret = $cmd." done:" ."\n saved"  ."\n    ".(join "\n    ",sort @entities)
						 ;
  }
  else{
	$ret = " Unknown argument ";
  }
  return $ret;
}
sub HMinfo_post($) {###########################################################
  my ($name,$childName) = (split":",$_);
  foreach (keys %{$defs{$name}{helper}{child}}){
    Log 1,"General still running: $_ ".$defs{$name}{helper}{child}{$_};
  }
  delete $defs{$name}{helper}{child}{$childName};
  Log 1,"General deleted $childName now++++++++++++++";
  return "finished";
}
1;
=pod
=begin html

<a name="HMinfo"></a>
<h3>HMinfo</h3>
<ul>
  <tr><td>
  HMinfo is a module that shall support in getting an overview of 
  eQ-3 HomeMatic devices as defines in <a href="#CUL_HM">CUL_HM</a>. 
  It also allows some HM wide commands such 
  as store all collected register settings.<br><br>
  
  Commands will be executed on all HM entities of the installation. 
  If applicable and evident execution is restricted to related entities. 
  This means that rssi is executed only on devices, never channels since 
  they never have support rssi values.<br><br>
  <b>Filter</b>
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
		    <li>-f - filter   :regexp to filter entity names </li>
        </ul>
	    Example:<br>
	    <ul><code>
           set hm param -d -f dim state # display param 'state' for all devices whos name contains dim<br>
           set hm param -c -f ^dimUG$ peerList # display param 'peerList' for all channels whos name is dimUG<br>
           set hm param -dcv expert # get attribut expert for all channels,devices or virtuals<br>
        </code></ul>
  </ul>
  <br>
  <a name="HMinfodefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HMinfo</code><br> 
    Just one entity needs to be defines, no parameter are necessary.<br> 	
  </ul>
  <br>

  <a name="HMinfoset"></a>
  <b>Set</b>
  <ul>
  even though the commands are more a get funktion they are implemented 
  as set to allow simple web interface usage<br>
    <ul>
      <li><a name="#models">models</a><br>
	      list all HM models that are supported in FHEM
	  </li>
      <li><a name="#param">param &lt;name&gt; &lt;name&gt;...</a><br>
	      returns a table parameter values (attribute, readings,...) 
	  	for all entities as a table
	  </li>
      <li><a name="#regCheck">regCheck</a><br>
	      performs a consistancy check on register readings for completeness
	  </li>
      <li><a name="#peerCheck">peerCheck</a><br>
	      performs a consistancy check on peers. If a peer is set in one channel 
	  	this funktion will search wether the peer also exist on the opposit side.
	  </li>
      <li><a name="#configCheck">configCheck</a><br>
	      performs a consistancy check of HM settings. It includes regCheck and peerCheck
	  </li>
      <li><a name="#peerXref">peerXref</a><br>
	      provides a cross-reference on peerings, a kind of who-with-who summary over HM
	  </li>
      <li><a name="#saveConfig">saveConfig</a><br>
	      performs a save for all HM register setting and peers. See <a href="#CUL_HMsaveConfig">CUL_HM saveConfig</a>. 
	  </li>
      <li><a name="#clearProtocol">clearProtocol</a><br>
	      executes a set clear msgEvents on all HM devices
	  </li>
      <li><a name="#clearReadings">clearReadings</a><br>
	      executes a set clear readings on all HM devices
	  </li>
      <li><a name="#clearRssi">clearRssi</a><br>
	      executes a set clear rssi on all HM devices
	  </li>
      <li><a name="#autoReadReg">autoReadReg</a><br>
	      stimulates a read of the configuration for the CUL_HM devices with attribut autoReadReg set to 1 or higher. 
	  </li>
    </ul>  
  </ul>
  <br>

  <a name="HMinfoget"></a>
  <b>Get</b>
  <ul> N/A </ul>
  <br><br>

  <a name="HMinfoattr"></a>
  <b>Attributes</b>
  <ul>N/A</ul>
</ul>
=end html
=cut
