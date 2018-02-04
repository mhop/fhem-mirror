##############################################
# $Id$
package main;
use strict;
use warnings;

my $culHmRegDef        =\%HMConfig::culHmRegDefine;
my $culHmRegDefLS      =\%HMConfig::culHmRegDefShLg;
my $culHmTpl           =\%HMConfig::culHmTpl;


sub HMtemplate_Initialize($$);
sub HMtemplate_Define($$);
sub HMtemplate_SetFn($@);
sub HMtemplate_noDup(@);

use Blocking;
use HMConfig;
my %HtState =(
  s0=>{name=>"init"   ,cmd=>["select" ,"defTmpl","delete","edit"]      ,info=>[ "delete to remove a template definition"
                                                                               ,"defTmpl to greate a template"
                                                                               ,"-       use an entity as default"
                                                                               ,"edit to modify a template definition"
                                                                               ,"select to apply a template to a entity"
                                                                            ]}  
 ,s1=>{name=>"edit"   ,cmd=>["dismiss","save"   ,"saveAs","importReg"] ,info=>[ "change attr Reg_ as desired"
                                                                               ,"change attr tpl_params ':' separated"
                                                                               ,"save    if finished"
                                                                               ,"saveAs  to create a copy"
                                                                               ,"dismiss will reset HMtemplate"
                                                                            ]}  
 ,s2=>{name=>"defTmpl",cmd=>["dismiss","save","saveAs"]                ,info=>[ "1)set attr tpl_type"
                                                                               ,"2)set attr tpl_source"
                                                                               ,"3)set attr tpl_peer if peer required"
                                                                               ,"4)set attr tpl_params ':' separated"
                                                                               ,"5)set attr tpl_description for the template"
                                                                            ]} 
 ,s3=>{name=>"defTmpl",cmd=>["defTmpl","edit"   ,"delete"]             ,info=>[ "delete"
                                                                            ]}  
 ,s4=>{name=>"select" ,cmd=>["dismiss","apply"  ,"select"]             ,info=>[ "apply the selected template to an entity"
                                                                               ,"1) choose target entity"
                                                                               ,"2) select a peer if required"
                                                                               ,"3) select type if required"
                                                                               ,"4) fill all attr tpl_param_"
                                                                               ,"5) set apply to execute and write the register"
                                                                            ]}  
 ,s5=>{name=>"defTmpl",cmd=>["defTmpl","edit"   ,"delete"]             ,info=>[ "s5 info1"
                                                                               ,"s5 info2"
                                                                            ]}
);

sub HMtemplate_Initialize($$) {################################################
  my ($hash) = @_;

  $hash->{DefFn}     = "HMtemplate_Define";
  $hash->{UndefFn}   = "HMtemplate_Undef";
  $hash->{SetFn}     = "HMtemplate_SetFn";
  $hash->{GetFn}     = "HMtemplate_GetFn";
  $hash->{AttrFn}    = "HMtemplate_Attr";
  $hash->{NotifyFn}  = "HMtemplate_Notify";
  $hash->{AttrList}  = "";
  $hash->{NOTIFYDEV} = "global";
}
sub HMtemplate_Define($$){#####################################################
  my ($hash, $def) = @_;
  my ($n) = devspec2array("TYPE=HMtemplate");
  return "only one instance of HMInfo allowed, $n already instantiated"
        if ($n && $hash->{NAME} ne $n);

  $hash->{helper}{attrList}  = "tpl_params tpl_description "
                              .$readingFnAttributes;
  $hash->{helper}{cSt} = "s0";
  $modules{HMtemplate}{AttrList} = $hash->{helper}{attrList};
  return;
}
sub HMtemplate_Undef($$){######################################################
  my ($hash, $name) = @_;
  return undef;
}
sub HMtemplate_Attr(@) {#######################################################
  my ($cmd,$name,$attrName,$attrVal) = @_;
  my @hashL;
  my $hash = $defs{$name};
  #return "$attrName  not an option in this state" if($modules{HMtemplate}{AttrList}!~ m/$attrName/);
  if   ($attrName =~ m/^Reg_/){
    if (!$init_done){
      return "remove attr $attrName after restart - start again with template definition";
    }
    elsif ($cmd eq "set"){
      #burstRx  =>{min=>0,max=>255  ,c=>'lit',f=>'',t=>'device reacts on Burst'    ,lit=>{off=>0,on=>1}},
      #MaxTimeF =>{min=>0,max=>25.5 ,c=>''   ,f=>10,t=>"max time first direction." ,lit=>{unused=>25.5}},
      my $rN = substr($attrName,4);
      my $ty = (AttrVal($name,"tpl_type",InternalVal($name,"tpl_type","")) =~ m/peer-both/) ? "" : "lg"; #RegDef for long and short is identical. Just extend to any sh or lg
      my $calc = $culHmRegDef->{$ty.$rN}{c};
      if ($attr{$name}{tpl_params} && $attr{$name}{tpl_params} =~ m/\b$attrVal\b/){
        # allow any parameter in any string
      }
      elsif ($calc eq "lit"){
        return "value $attrVal not allowed for $rN"  if (!defined $culHmRegDef->{$ty.$rN}{lit}{$attrVal});
      }
      elsif ($calc eq "fltCvT"  ){ my $calcVal = CUL_HM_CvTflt  (CUL_HM_fltCvT  ($attrVal)); return "Value $attrVal not possible. Use $calcVal" if ($attrVal != $calcVal); }
      elsif ($calc eq "fltCvT60"){ my $calcVal = CUL_HM_CvTflt60(CUL_HM_fltCvT60($attrVal)); return "Value $attrVal not possible. Use $calcVal" if ($attrVal != $calcVal); }
      elsif ($calc eq "min2time"){ my $calcVal = CUL_HM_min2time(CUL_HM_time2min($attrVal)); return "Value $attrVal not possible. Use $calcVal" if ($attrVal != $calcVal); }
      else{
        return "value $attrVal not numeric for $rN"  if ($attrVal !~/^\d+?\.?\d?$/);
        return "value $attrVal out of range for $rN :"
              .$culHmRegDef->{$ty.$rN}{min} ."..."
              .$culHmRegDef->{$ty.$rN}{max}          if ($culHmRegDef->{$ty.$rN}{min} > $attrVal 
                                                      || $culHmRegDef->{$ty.$rN}{max} < $attrVal);
      }
    }
    else{# delete is ok anyhow
    }
  }
  elsif($attrName eq "tpl_params"){
    if (!$init_done){
      return "remove attr $attrName after restart - start again with template definition";
    }
    elsif ($cmd eq "set"){
      my @param = split(" ",$attrVal);
      my $paramCnt = scalar @param;
      
      foreach my $pN (grep /^p(.)/,values %{$culHmTpl->{$hash->{tpl_Name}}{reg}}){
        return "still $paramCnt in use. Remove those from template first" if($1 > ($paramCnt - 1));
      }
      foreach my $rN (keys %{$culHmTpl->{$hash->{tpl_Name}}{reg}}){#now we need to rename all readings if parameter are in use
        next if ($culHmTpl->{$hash->{tpl_Name}}{reg}{$rN} !~ m/^p(.)$/);
        my $no = $1;
        $attr{$name}{"Reg_".$rN} = $param[$no];
      }
      
      #remove old params
      if ($attr{$name}{tpl_params}){# first setting
        my @atS;
        foreach my $atS (split(" ",$modules{HMtemplate}{AttrList})){
          if ($atS !~ m/:/){# no values
            push @atS,$atS;
            next;
          }
          my ($aN,$aV) = split (":",$atS);
          my @aVaNew;
          foreach my $curAV(split(",",$aV)){
            next if (!$curAV);
            foreach my $curParam (split(",",$attr{$name}{tpl_params})){
              push @aVaNew,$_ if($curAV ne $curParam);
            }
          }
          push @atS,"$aN:".join(",",@aVaNew);
        }
        $modules{HMtemplate}{AttrList} = join(" ",sort @atS);
      }
      
      #now add new ones
      my $paramSnew = join(",",@param);
      my @at = split(" ",$modules{HMtemplate}{AttrList});
      $_ .= ",".$paramSnew foreach (grep (m/:/,@at));
      my $paramSold = join(",",split(" ",$attr{$name}{tpl_params}));
      #$modules{HMtemplate}{AttrList} =~ s/$paramSold/$paramSnew/g;
      $modules{HMtemplate}{AttrList} = join(" ",@at);
      
      $hash->{tpl_Param} = $attrVal;
    }
  }
  elsif($attrName eq "tpl_type"){
    if ($cmd eq "set"){
      my @list = HMtemplate_sourceList($attrVal);
      $modules{HMtemplate}{AttrList}  = $hash->{helper}{attrList}
                                       ." tpl_type:peer-Long,peer-Short,peer-both,basic "
                                       ." tpl_source:".join(",",@list)
                                       ." tpl_peer"
                                       ;
      $attr{$name}{tpl_source} = $attr{$name}{tpl_peer} = "";
    }
  }
  elsif($attrName eq "tpl_source"){
    if ($cmd eq "set"){
      $attr{$name}{tpl_peer} = "";
      if($attr{$name}{tpl_type} eq "basic"){# we dont need peer - import now
        HMtemplate_import($name,$attrVal,"basic");
      }
      else{# need peer
        my $peerList = InternalVal($attrVal,"peerList","");
        return "no peer present for $attrVal" if (!$peerList );
        $modules{HMtemplate}{AttrList}  =~ s/tpl_peer.*?( |$)//;
        $modules{HMtemplate}{AttrList}  .=" tpl_peer:$peerList";
      }
    }
  }
  elsif($attrName eq "tpl_peer"){
    if ($cmd eq "set"){
      HMtemplate_import($name,$attr{$name}{tpl_source},$attr{$name}{tpl_type},$attrVal);
    }
  }
  elsif($attrName eq "tpl_entity"){# used with select option
    if ($cmd eq "set"){
      return "entity:$attrVal not defined" if(!defined $defs{$attrVal});
      $attr{$name}{tpl_ePeer} = "";
      if($hash->{tpl_type} eq "basic"){# we dont need peer - import now
      }
      else{# need peer
        my $peerList = InternalVal($attrVal,"peerList","");
        return "no peer present for $attrVal" if (!$peerList );
        $modules{HMtemplate}{AttrList}  =~ s/tpl_ePeer.*?( |$)//;
        $modules{HMtemplate}{AttrList}  .=" tpl_ePeer:$peerList";
      }
      ############ set attr param from device if selected
      if(ReadingsVal($hash->{NAME},"state","") eq "select"){# do we have to set params?
        my $dh = $defs{$attrVal};
        my ($tName,$tType) = (InternalVal($name,"tpl_Name",""),InternalVal($name,"tpl_type","")); 
        if (   $tType eq "basic"){ #we have enough to prefill parameter
          my @pN = split(" ",$culHmTpl->{$tName}{p});## get param Names template
          my @pD ;
          @pD = split(" ",$dh->{helper}{tmpl}{"0>$tName"}) 
                   if(   defined $dh->{helper}{tmpl}
                      && defined $dh->{helper}{tmpl}{"0>$tName"});
          
          for (my $cnt = 0;$cnt < scalar(@pN); $cnt++){
            $attr{$name}{"tpl_param_$pN[$cnt]"} = defined $pD[$cnt] ? $pD[$cnt] : "";
          }
        }
      }
    }
    else{
      $attr{$name}{tpl_ePeer}         = "";
      $modules{HMtemplate}{AttrList}  =~ s/ tpl_ePeer.*?\ / tpl_ePeer/;
    }
  }
  elsif($attrName eq "tpl_ePeer"){# used with select option
    if ($cmd eq "set"){
    }
  }
  elsif($attrName eq "tpl_eType"){# used with select option
    if ($cmd eq "set"){
    }
  }
  elsif($attrName eq "tpl_description"){# used with select option
    if ($cmd eq "set"){
    }
  }
  return;
}

sub HMtemplate_Notify(@){######################################################
  my ($hash,$dev) = @_;
  return "" if ($dev->{NAME} ne "global");
  if (grep (m/^INITIALIZED$/,@{$dev->{CHANGED}})){
    if ($hash->{helper}{attrPend}){
      my $aVal = AttrVal($hash->{NAME},"logIDs","");
      HMLAN_Attr("set",$hash->{NAME},"logIDs",$aVal) if($aVal);
      delete $hash->{helper}{attrPend};
    }
  }
  elsif (grep (m/^SHUTDOWN$/,@{$dev->{CHANGED}})){
    HMtemplate_init($hash->{name});# clear attribut bevore safe
  }

  return undef;
}

sub HMtemplate_GetFn($@) {#####################################################
  my ($hash,$name,$cmd,@a) = @_;
  my $ret;

  $cmd = "?" if(!$cmd);# by default print options
  #------------ statistics ---------------
  if($cmd eq "defineCmd"){##print protocol-events-------------------------
    my ($tN) = @a;
    return "template not given" if(!defined $tN);
    return "template unknown $tN" if(!defined $culHmTpl->{$tN});

    return "set hm templateDef $tN "
            .join(":",split(" ",$culHmTpl->{$tN}{p}))
            ." \"$culHmTpl->{$tN}{t}\""
            ." ".join(" ",map{$_.=":".$culHmTpl->{$tN}{reg}{$_}} keys %{$culHmTpl->{$tN}{reg}})
            ;
  }  
  elsif($cmd eq "regInfo"){##print protocol-events-------------------------
    my @regArr = map { $_ =~ s/Reg_//g; $_ } 
              grep /^Reg_/,keys %{$attr{$name}};
    if (InternalVal($name,"tpl_type","") =~ m/peer-(short|long)/){
      $_ = "lg".$_ foreach (@regArr);
    }
    return CUL_HM_getRegInfo($name); # 
  }  
  else{
    my @cmdLst = ( "defineCmd"
                  ,"regInfo"
                 );

    my $tList = ":".join(",",sort keys%{$culHmTpl});
    $_ .=$tList foreach(grep/^(defineCmd)$/,@cmdLst);
    
    $_ .=":noArg" foreach(grep/^(regInfo)$/,@cmdLst);# no arguments
           
    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  return $ret;
}
sub HMtemplate_SetFn($@) {#####################################################
  my ($hash,$name,$cmd,@a) = @_;
  my $ret = "";
  my $eSt = \$hash->{helper}{cSt};# shortcut
  $cmd = "?" if(!$cmd);# by default print options
  $cmd .=" " if ($cmd ne "?" && !(grep /$cmd/,@{$HtState{${$eSt}}{cmd}}));

  HMtemplate_setUsageReading($hash);
  if    ($cmd eq "delete" )   {##actionImmediate: delete template--------------
    my ($tName) = @a;                               
    return "$tName is not defined" if (! defined $culHmTpl->{$tName});
    ${$eSt} = "s0";
    if (eval "defined(&HMinfo_templateMark)"){
      HMinfo_templateDef($tName,"del");
    }
    else{
      return "HMInfo is not defined";
    } 
    HMtemplate_init($name);
  }
  elsif ($cmd eq "dismiss" )  {##actionImmediate: clear parameter--------------
    ${$eSt}="s0";
    HMtemplate_init($name);
    
  }
  elsif ($cmd eq "defTmpl" )  {#
    my ($tName) = @a;  
    return "specify template name" if (!defined $tName); 
    return "$tName is already defined" if (defined $culHmTpl->{$tName}); 
    readingsSingleUpdate($hash,"state","define",0);
    ${$eSt}="s2";
    HMtemplate_init($name);
    $modules{HMtemplate}{AttrList} .= " tpl_type:peer-Short,peer-Long,peer-both,basic "
                                     ." tpl_source"
                                     ." tpl_peer"
                                     ;
    $hash->{tpl_Name} = $tName;
    delete $attr{$name}{$_} foreach(grep /^tpl_/,keys %{$attr{$name}});#clean the settings  
    $attr{$name}{tpl_type}        = "";
    $attr{$name}{tpl_source}      = "";
    $attr{$name}{tpl_peer}        = "";
    $attr{$name}{tpl_params}      = "";
    $attr{$name}{tpl_description} = "";
      
    $hash->{tpl_Info} = "please enter attr tpl_type tpl_source and tpl_peer";
  }
  elsif ($cmd eq "select" )   {#
    my ($templ) = @a;                               
    return "$templ is not defined" if (! defined $culHmTpl->{$templ});
    readingsSingleUpdate($hash,"state","assign",0);
    HMtemplate_init($name);
    ${$eSt}="s4";

    if ($culHmTpl->{$templ}{p}){
      foreach(split(" ",$culHmTpl->{$templ}{p})){
        $modules{HMtemplate}{AttrList}  .=" tpl_param_$_" ;
        $attr{$name}{"tpl_param_$_"}     = "";
      }
    }

    my @r = keys %{$culHmTpl->{$templ}{reg}};

    ################### maybe store type in template hash##########
    my $tType;
    foreach my $rN (@r){
      if ($culHmRegDefLS->{$rN}){# template for short/long
        $tType = "peer-Long";
      }
      elsif ($culHmRegDef->{$rN}){
        if($culHmRegDef->{$rN}{l} eq 3){$tType = "peer-both"}
        else{                           $tType = "basic"; }
      }
    }
    ###################
    #### find matching entities ##########
    my @e = HMtemplate_sourceList($tType);
    my @eOk;
    foreach my $eN(@e){
      my @eR = grep /\.?R-/,keys %{$defs{$eN}{READINGS}};
      my $match = 1;
      foreach my $rN (@r){
        if (!grep (/$rN/,@eR)){
          $match = 0;
          last;
        }
      }
      push @eOk,$eN if ($match);
    }
    ##################
    $hash->{tpl_Name} = $templ;
    $hash->{tpl_type} = $tType;
    $hash->{tpl_description} = $culHmTpl->{$templ}{t}?$culHmTpl->{$templ}{t}:"";
    $modules{HMtemplate}{AttrList}  .=" tpl_entity:".join(",",@eOk);
    $attr{$name}{"tpl_entity"}       = "";
    if ($tType ne "basic"){
      $modules{HMtemplate}{AttrList} .=" tpl_ePeer";
      $attr{$name}{"tpl_ePeer"}       = "";
      if ($tType ne "peer-both"){
        $modules{HMtemplate}{AttrList} .=" tpl_eType:long,short";
        $attr{$name}{"tpl_eType"}       = "";
      }
    }
  }
  elsif ($cmd eq "apply" )    {# 
    my @p = split(" ",$culHmTpl->{$hash->{tpl_Name}}{p});## get params in correct order
    $_ = $attr{$name}{"tpl_param_$_"} foreach (@p);
    return HMinfo_templateSet( $attr{$name}{tpl_entity}
                       ,$hash->{tpl_Name}
                       ,($hash->{tpl_type} eq "basic" ? "0"
                                                      : $attr{$name}{tpl_ePeer}.":".AttrVal($name,"tpl_eType","both"))# type either long/short/both
                       ,@p
                        );
  }
  elsif ($cmd eq "importReg" ){#
    my ($eName) = @a;

    return "please enter a device to be used "if(!$eName);
    my @fnd = grep /^$eName /, 
              map {$hash->{READINGS}{$_}{VAL}}
              grep /^usage_/,keys %{$hash->{READINGS}};
    return "template not assigned to $eName" if (scalar(@fnd) != 1);

    HMtemplate_import($name,$eName,InternalVal($name,"tpl_type",""),InternalVal($name,"tpl_peer",""));
    
    # my @fnd = map { $_ =~ s/ .*//g; $_ } 
    #           map {$hash->{READINGS}{$_}{VAL}}
    #           grep /^usage_/,keys %{$hash->{READINGS}};
    # my @reg;
    # my $first = 1;
    # foreach my $d(@fnd){
    #   my $dHash = CUL_HM_getDeviceHash($defs{$d});
    #   my $st = AttrVal($dHash->{NAME},"subType","");
    #   my $md = AttrVal($dHash->{NAME},"model","");
    #   my @dr = (CUL_HM_getRegN($st,$md,"01"));
    #   
    #   if ($first){
    #     @reg = @dr;
    #     $first = 0;
    #   }
    #   else{
    #     @reg = HMtemplate_intersection(\@reg,\@dr);
    #   }
    # }
    # return join("\n",sort @reg);
  }
  elsif ($cmd eq "edit" )     {#
    my ($templ) = @a;                               
    return "$templ is not defined" if (! defined $culHmTpl->{$templ});
    readingsSingleUpdate($hash,"state","edit",0);
    HMtemplate_init($name);
    ${$eSt}="s1";

    my $tType = "";
    $attr{$name}{tpl_params}      = $culHmTpl->{$templ}{p} ? $culHmTpl->{$templ}{p} : "";
    $attr{$name}{tpl_description} = $culHmTpl->{$templ}{t} ? $culHmTpl->{$templ}{t} : "";
    my @param = split(" ",$culHmTpl->{$templ}{p});
    my $paramS = join(",",@param);# whatchout: dont change order, may be replaced!
    
    foreach my $rN (sort keys %{$culHmTpl->{$templ}{reg}}){
      my $val = $culHmTpl->{$templ}{reg}{$rN};
      if ($val =~m /^p(.)$/){# this is a parameter!!
        $val = $param[$1];
      }
      $attr{$name}{"Reg_".$rN} = $val;
      my $lits = "";
      if ($culHmRegDefLS->{$rN}){# template for short/long
        next if($tType && $tType !~ m/peer-(Long|Short)/);
        $tType = "peer-Long";
        $lits = ":".join(",",(sort(keys %{$culHmRegDefLS->{$rN}{lit}}),$paramS)) if ($culHmRegDefLS->{$rN}{c} eq "lit");
      }
      elsif ($culHmRegDef->{$rN}){
        if($culHmRegDef->{$rN}{l} eq 3){
          next if($tType && $tType ne "peer-both");
          $tType = "peer-both";
        }
        else{
          next if($tType && $tType ne "basic");
          $tType = "basic";
        }
        $lits = ":".join(",",(sort(keys %{$culHmRegDef->{$rN}{lit}}),$paramS)) if ($culHmRegDef->{$rN}{c} eq "lit");
      }
      else{
        next;
      }
      $modules{HMtemplate}{AttrList} .= " Reg_".$rN.$lits;
    }
    
    $hash->{tpl_Name} = $templ;
    $hash->{tpl_type} = $tType;
    $hash->{tpl_Param} = $culHmTpl->{$templ}{p};
  }
  elsif ($cmd eq "save" )     {#
    my $tName = $hash->{tpl_Name};                               
    if (eval "defined(&HMinfo_templateMark)"){
      HMinfo_templateDef($tName,"del");# overwrite means: delete and write!
      return HMtemplate_save($name,$tName);
    }
    else{
      return "HMInfo is not defined";
    } 
  }
  elsif ($cmd eq "saveAs" )   {#
    my ($tName) = @a;   
    return HMtemplate_save($name,$tName);
  }
  else{
    #"select","edit","delete", "defTmpl","dismiss","save","saveAs","importReg","apply"]            
    my @cmdLst = @{$HtState{${$eSt}}{cmd}};
    my $tList = ":".join(",",sort keys%{$culHmTpl});
    $_ .=$tList foreach(grep/^(edit|delete|select)$/,@cmdLst);
    if (grep/^importReg$/,@cmdLst){
      my @fnd = map { $_ =~ s/ .*//g; $_ } 
                map {$hash->{READINGS}{$_}{VAL}}
                grep /^usage_/,keys %{$hash->{READINGS}};
      my $eList = ":".join(",",sort @fnd);
      $_ .=$eList foreach(grep/^(importReg)$/,@cmdLst);
    }
    $_ .=":noArg" foreach(grep/^(save|dismiss|apply)$/,@cmdLst);# no arguments

    $ret = "Unknown argument $cmd, choose one of ".join (" ",sort @cmdLst);
  }
  my $i = 0;
  readingsSingleUpdate($hash,"state",$HtState{${$eSt}}{name},0);
  $hash->{"tpl_Info".$i++}= $_ foreach (@{$HtState{${$eSt}}{info}});
  return $ret;
}
sub HMtemplate_intersection($$) {#
    my ($x, $y) = @_;
    my %seen;
    @seen{ @$x } = (1) x @$x;
    return grep { $seen{ $_} } @$y;
}

sub HMtemplate_import(@){####################################################
  my ($name,$eName,$tType,$tPeer) = @_;
  my @regReads;
  my ($ty,$match) = ("","");
  if    ($tType eq "basic"){
    @regReads = grep !/\-.*\-/   ,grep /\.?R-/      ,keys %{$defs{$eName}{READINGS}};
  }
  elsif ($tType =~ m/peer-(Long|Short)/){
    $ty = $1 eq "Long" ? "lg" : "sh";
    $match = ".*-";
    @regReads = grep /\-.*\-$ty/ ,grep /\.?R-$tPeer/,keys %{$defs{$eName}{READINGS}};
  }
  elsif ($tType eq "peer-both"){
    $match = ".*-";
    @regReads = grep /\-.*\-/    ,grep /\.?R-$tPeer/,keys %{$defs{$eName}{READINGS}};
  }

  foreach my $rR (@regReads){
    my $rN = $rR;
    $rN =~ s/\.?R-$match$ty//; 
    if (!$attr{$name}{"Reg_".$rN}){ #dont overwrite existing
      $attr{$name}{"Reg_".$rN} = $defs{$eName}{READINGS}{$rR}{VAL};
      $attr{$name}{"Reg_".$rN} =~ s/ .*//;# remove units which are in the readings
      my $lits = ":".join(",",(sort (keys %{$culHmRegDef->{$ty.$rN}{lit}}))) if ($culHmRegDef->{$ty.$rN}{c} eq "lit");
      $modules{HMtemplate}{AttrList} .= " Reg_".$rN.$lits;
    }
  }
}

sub HMtemplate_save($$)  {#
  my ($name,$tName) = @_;                               
  return "$tName aleady defned - please choose a different name" if (defined $culHmTpl->{$tName});
  return "enter tpl_description" if (!$attr{$name}{tpl_description});
  return "enter at least one register" if ( !(grep /^Reg_/,keys %{$attr{$name}}));

  if (eval "defined(&HMinfo_templateMark)"){
    my @regs;
    push @regs,substr($_,4).":".$attr{$name}{$_} foreach ( grep /^Reg_/,keys %{$attr{$name}});
    my @params = split(" ",AttrVal($name,"tpl_params",""));
    my $i = 0;
    foreach my $p (@params){
      $_ =~ s/(.*:)$p$/$1p$i/ foreach(@regs) ;
      $i++;
      }
    HMinfo_templateDef( $tName
                       ,join(":",@params)
                       ,AttrVal($name,"tpl_description","")
                       ,@regs);
  }
  else{
    return "HMInfo is not defined";
  } 
}
sub HMtemplate_init(@)  {#
  my $name = shift;
  return if(!defined $name || !defined $defs{$name});
  my $hash = $defs{$name};
  delete $hash->{$_}      foreach(grep /^tpl_/,keys %{$hash});
  delete $attr{$name}{$_} foreach(grep /^Reg_/,keys %{$attr{$name}});#clean the settings  
  delete $attr{$name}{$_} foreach(grep /^tpl_/,keys %{$attr{$name}});#clean the settings  
  $modules{HMtemplate}{AttrList} = $hash->{helper}{attrList};
}
sub HMtemplate_noDup(@) {#return list with no duplicates###########################
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep {defined($_)} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}

sub HMtemplate_sourceList($){
  my $type = shift;
  my $match;
  if   ($type =~ m/peer-(Long|Short|both)/){$match = "RegL_03"}
  elsif($type eq "basic"                  ){$match = "RegL_(01|00)"}
  
  my @list;
  foreach my $e (devspec2array("TYPE=CUL_HM:FILTER=subType!=virtual")){
    my @l1 = grep/$match/,CUL_HM_reglUsed($e);
    $_ = $e foreach(@l1);
    push @list,@l1;
  }
  for (@list) { s/:.*//};
  return HMtemplate_noDup(@list);
}

sub HMtemplate_setUsageReading($){
  my ($hash) = @_;  
  delete $hash->{READINGS}{$_} foreach (grep /^usage_/,keys %{$hash->{READINGS}});
  if (eval "defined(&HMinfo_templateUsg)" && $hash->{tpl_Name}){
    my $tu = HMinfo_templateUsg("","",$hash->{tpl_Name});
    $tu =~ s/\|$hash->{tpl_Name}//g;
    $tu =~ s/.\|/|/g;
    my $usgCnt = 1;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"usage_".$usgCnt++,$_) foreach(split("\n",$tu));
    readingsEndUpdate($hash,1);
  }
}


1;
=pod
=item command
=item summary    definition and modification of homematic register templates
=item summary_DE definition und modifikation von homematic register templates

=begin html

  <a name="HMtemplate"></a><h3>HMtemplate</h3>
  <ul>
    Edit templates for HM entities. Programming register of HM devices can be bundled to templates and then being assigned to the devices. The editor might be instantiated ony once. Templates will be organized, handled and loaded in HMinfo. <br>
    The editor allowes to define, edit, copy and assign and delete templates. 
    <br>
    Required: HMinfo needs to be instantiated.
    
    <a name="HMtemplate"></a><b>Set</b>
      <ul>        
        following commands are available:
        <ul>
          <li><B>defTmpl &lt;name&gt;</B><a name="HMtemplate_defTmpl"></a><br>
            Define a new template. Procedure is given in internals once the command is issued.<br>
            <li><B><a href="#HMtemplate_tpl_type">tpl_type</a></B>choose whether the template will be: 
              <ul>
                <li><B>basic</B> not peer related register only</li> 
                <li><B>peer-both</B> only peer related register, setting short and long press reaction in one template</li> 
                <li><B>peer-Short</B> only peer related register, will define one short or long press behavior</li>
                <li><B>peer-Long</B> only peer related register, will define one short or long press behavior</li> 
              </ul>            
            </li>
            <li><B><a href="#HMtemplate_tpl_source">tpl_source</a></B>select the entity which will be used as master for the template 
            </li>
            <li><B><a href="#HMtemplate_tpl_peer">tpl_peer</a></B>select the peer of the entity which will be used as master for the template. This is only necessary for types that require peers.
            </li>
            <li><B><a href="#HMtemplate_tpl_params">tpl_params</a></B>if the template shall have parameter those need to be defined next. <br>
            parameter will allow to use one template with selected registers to be defined upon appling to the entity.
            </li>
            <li><B><a href="#HMtemplate_tpl_description">tpl_description</a></B>enter a free text to describe what the entity is about
            </li>
            <li><B><a href="#HMtemplate_tpl_Reg">tpl_Reg</a></B>a list of attributes will be available after all attribtes above are set. Not edit them. Delete registers which are not used for the template, edit the values as desired.
            </li>
            <li><B><a href="#HMtemplate_save">save</a></B>save the template. After that the template is defined. saveas will allow to define the template with a different name. 
            </li>
          </li>
          <li><B>delete &lt;name&gt;</B><a name="HMtemplate_delete"></a><br>
            Delete an existing template<br>
          </li>
          <li><B>edit &lt;name&gt;</B><a name="HMtemplate_edit"></a><br>
            Edit an existing template. Change register, parameter and description by change the attributes. See also defTmpl<br>
            saveAs can be used to create a copy of the template.<br>
          </li>
          <li><B>select &lt;name&gt;</B><a name="HMtemplate_select"></a><br>
            Apply an existing template to a entity<br>
            Once the command is issued it is necessary to select the entity, peer and short/long which the entity shall be applied to.<br>
            If the template has parameter the value needs to be set. <br>
            Finally <B>apply</B> the template to teh entity.
          </li>
          <li><B>dismiss</B><a name="HMtemplate_dismiss"></a><br>
            reset HMtemplate and come back to init status
          </li>
          <li><B>save, saveAs</B><a name="HMtemplate_save"></a><br>
            save a template once it is defined
          </li>
        </ul>
      </ul>
    
    
    
  </ul>
=end html

=begin html_DE

<a name="HMtemplate"></a>
<h3>HMtemplate</h3>
<ul>

</ul>
=end html_DE
=cut
