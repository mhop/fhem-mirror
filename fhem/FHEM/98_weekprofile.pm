##############################################
# $Id$
#
# Usage
# 
# define <name> weekprofile [device]
############################################## 

package main;

use strict;
use warnings;
use JSON;     #libjson-perl

use vars qw(%defs);
use vars qw($FW_ME);
use vars qw($FW_wname);
use vars qw($FW_subdir);
use vars qw($init_done);

my @shortDays = ("Mon","Tue","Wed","Thu","Fri","Sat","Sun");

my @DEVLIST_SEND = ("MAX","CUL_HM","weekprofile","dummy");

my $CONFIG_VERSION = "1.1";

my %DEV_READINGS;
# MAX
$DEV_READINGS{"Mon"}{"MAX"} = "weekprofile-2-Mon";
$DEV_READINGS{"Tue"}{"MAX"} = "weekprofile-3-Tue";
$DEV_READINGS{"Wed"}{"MAX"} = "weekprofile-4-Wed";
$DEV_READINGS{"Thu"}{"MAX"} = "weekprofile-5-Thu";
$DEV_READINGS{"Fri"}{"MAX"} = "weekprofile-6-Fri";
$DEV_READINGS{"Sat"}{"MAX"} = "weekprofile-0-Sat";
$DEV_READINGS{"Sun"}{"MAX"} = "weekprofile-1-Sun";

# CUL_HM
$DEV_READINGS{"Mon"}{"CUL_HM"} = "2_tempListMon";
$DEV_READINGS{"Tue"}{"CUL_HM"} = "3_tempListTue";
$DEV_READINGS{"Wed"}{"CUL_HM"} = "4_tempListWed";
$DEV_READINGS{"Thu"}{"CUL_HM"} = "5_tempListThu";
$DEV_READINGS{"Fri"}{"CUL_HM"} = "6_tempListFri";
$DEV_READINGS{"Sat"}{"CUL_HM"} = "0_tempListSat";
$DEV_READINGS{"Sun"}{"CUL_HM"} = "1_tempListSun";

############################################## 
sub weekprofile_getDeviceType($;$)
{
  my ($device,$sndrcv) = @_;
  
  $sndrcv = "RCV" if (!defined($sndrcv));

  # determine device type
  my $devHash = $main::defs{$device};
  if (!defined($devHash)){
    return undef;
  }
  
  my $type = undef;

  if ($devHash->{TYPE} =~ /CUL_HM/){
    my $model = AttrVal($device,"model","");
    $type = "CUL_HM" if ($model =~ m/.*(HM-CC|HM-TC).*/);
  }
  #avoid max shutter contact
  elsif ( ($devHash->{TYPE} =~ /MAX/) && ($devHash->{type} =~ /.*Thermostat.*/) ){
    $type = "MAX";
  }
  elsif ($devHash->{TYPE} =~ /dummy/){
    $type = "MAX"     if ($device =~ m/.*MAX.*FAKE.*/);    #dummy (FAKE WT) with name MAX inside for testing
    $type = "CUL_HM"  if ($device =~ m/.*CUL_HM.*FAKE.*/); #dummy (FAKE WT) with name CUL_HM inside for testing
  }
  
  return $type if ($sndrcv eq "RCV");
  
  if ($devHash->{TYPE} =~ /weekprofile/){
    $type = "WEEKPROFILE";
  }
  
  return $type;
}

############################################## 
sub weekprofile_readDayProfile($@)
{
  my ($device,$day,$type,$me) = @_;

  my @times;
  my @temps;
  
  $type = weekprofile_getDeviceType($device) if (!defined($type));
  return if (!defined($type));

  my $reading = $DEV_READINGS{$day}{$type};
  
  #Log3 $me, 5, "$me(ReadDayProfile): $reading";
  
  if($type eq "MAX") {
    @temps = split('/',ReadingsVal($device,"$reading-temp",""));
    @times = split('/',ReadingsVal($device,"$reading-time",""));
    # only use to from interval 'from-to'
    for(my $i = 0; $i < scalar(@times); $i+=1){
      my $interval =  $times[$i];
      my @parts = split('-',$interval);      
      $times[$i] = ($parts[1] ne "00:00") ? $parts[1] : "24:00";
    }
  } elsif ($type eq "CUL_HM") {    
    # get temp list for the day
    my $prf = ReadingsVal($device,"R_$reading","");
    $prf = ReadingsVal($device,"R_P1_$reading","") if (!$prf); #HM-TC-IT-WM-W-EU
    
    # split into time temp time temp etc.
    # 06:00 17.0 22:00 21.0 24:00 17.0
    my @timeTemp = split(' ', $prf);
    
    for(my $i = 0; $i < scalar(@timeTemp); $i += 2) {
      push(@times, $timeTemp[$i]);
      push(@temps, $timeTemp[$i+1]);
    }
  }
  
  for(my $i = 0; $i < scalar(@temps); $i+=1){
    $temps[$i] =~s/[^\d.]//g; #only numbers
  }
  
  for(my $i = 0; $i < scalar(@times); $i+=1){
    $times[$i] =~ s/^\s+|\s+$//g; #trim whitespace both ends
  }  
  return (\@times, \@temps);
}
############################################## 
sub weekprofile_readDevProfile(@)
{
  my ($device,$type,$me) = @_;
  $type = weekprofile_getDeviceType($device) if (!defined($type));
  return "" if (!defined ($type));
  
  my $prf = {};
  my $logDaysWarning="";
  my $logDaysCnt=0;
  foreach my $day (@shortDays){
    my ($dayTimes, $dayTemps) = weekprofile_readDayProfile($device,$day,$type,$me);
    if (scalar(@{$dayTemps})==0) {
      push(@{$dayTimes}, "24:00");
      push(@{$dayTemps}, "18.0");
      $logDaysWarning .= "\n" if ($logDaysCnt>0);
      $logDaysWarning .= "WARNING master device $device has no day profile for $day - create default";
      $logDaysCnt++;
    }
    $prf->{$day}->{"temp"} = $dayTemps;
    $prf->{$day}->{"time"} = $dayTimes;
  }
  
  if ( ($logDaysCnt>0) && ($logDaysCnt<(@shortDays)) ) {
    Log3 $me, 3, $logDaysWarning;
  }  else {
    if ($logDaysCnt == (@shortDays)) {
      Log3 $me, 3, "WARNING master device $device has no week profile - create default";
    }
  }
  
  return $prf;
}
############################################## 
sub weekprofile_createDefaultProfile(@)
{
  my ($hash) = @_;
  my $prf = {};
  
  foreach my $day (@shortDays){
    my @times; push(@times, "24:00");
    my @temps; push(@temps, "18.0");
  
    $prf->{$day}->{"temp"} = \@temps;
    $prf->{$day}->{"time"} = \@times;  
  }
  return $prf;
}
############################################## 
sub weekprofile_sendDevProfile(@)
{
  my ($device,$prf,$me) = @_;
  my $type = weekprofile_getDeviceType($device,"SND");
  return "Error device type not supported" if (!defined ($type));

  if ($type eq "WEEKPROFILE") {
      my $json = JSON->new;
      my $json_text = $json->encode($prf->{DATA});
      return fhem("set $device profile_data $prf->{NAME} $json_text",1);
  }

  my $devPrf = weekprofile_readDevProfile($device,$type,$me);
  
  # only send changed days
  my @dayToTransfer = ();
  foreach my $day (@shortDays){
    my $tmpCnt =  scalar(@{$prf->{DATA}->{$day}->{"temp"}});
    next if ($tmpCnt <= 0);
    
    if ($tmpCnt != scalar(@{$devPrf->{$day}->{"temp"}})) {
      push @dayToTransfer , $day;
      next;
    }
    
    my $equal = 1;
    for (my $i = 0; $i < $tmpCnt; $i++) {
      if ( ($prf->{DATA}->{$day}->{"temp"}[$i] ne $devPrf->{$day}->{"temp"}[$i] ) ||
            $prf->{DATA}->{$day}->{"time"}[$i] ne $devPrf->{$day}->{"time"}[$i] ) {
        $equal = 0; 
        last;
      }
    }
    
    if ($equal == 0) {
      push @dayToTransfer , $day;
      next;
    }
  }
  
  if (scalar(@dayToTransfer) <=0) {
    Log3 $me, 4, "$me(sendDevProfile): nothing to do";
    return undef;
  }
  
  my $cmd;
  if($type eq "MAX") {
    $cmd = "set $device weekProfile ";
    foreach my $day (@dayToTransfer){
      my $tmpCnt =  scalar(@{$prf->{DATA}->{$day}->{"temp"}});
      
      $cmd.=$day.' ';
      
      for (my $i = 0; $i < $tmpCnt; $i++) {
        my $endTime = $prf->{DATA}->{$day}->{"time"}[$i];
        
        $endTime = ($endTime eq "24:00") ? ' ' : ','.$endTime.',';
        $cmd.=$prf->{DATA}->{$day}->{"temp"}[$i].$endTime;
      }
    }
  } else { #Homatic
    my $k=0;
    my $dayCnt = scalar(@dayToTransfer);
    foreach my $day (@dayToTransfer){
      $cmd .= "set $device tempList";
      $cmd .= $day;
      $cmd .= ($k < $dayCnt-1) ? " prep": " exec";
      
      my $tmpCnt =  scalar(@{$prf->{DATA}->{$day}->{"temp"}});      
      for (my $i = 0; $i < $tmpCnt; $i++) {
        $cmd .= " ".$prf->{DATA}->{$day}->{"time"}[$i]." ".$prf->{DATA}->{$day}->{"temp"}[$i];
      }
      $cmd .= ($k < $dayCnt-1) ? "; ": "";
      $k++;
    }
  }
  
  my $ret = undef;
  if ($cmd) {
    $cmd =~ s/^\s+|\s+$//g; 
    Log3 $me, 4, "$me(sendDevProfile): $cmd";
    $ret = fhem($cmd,1);
  }
  return $ret;
}

##############################################
sub weekprofile_refreshSendDevList($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  splice($hash->{SNDDEVLIST});
  
  foreach my $d (keys %defs)   
  {
    next if ($defs{$d}{NAME} eq $me);
    
    my $module   = $defs{$d}{TYPE};
    
    my %sndHash;
    @sndHash{@DEVLIST_SEND}=();
    next if (!exists $sndHash{$module});
    
    my $type = weekprofile_getDeviceType($defs{$d}{NAME},"SND");
    next if (!defined($type));
    
    my $dev = {};
    $dev->{NAME} = $defs{$d}{NAME};
    $dev->{ALIAS} = AttrVal($dev->{NAME},"alias",$dev->{NAME});
    
    push @{$hash->{SNDDEVLIST}} , $dev;
  }
  return undef;
}

############################################## 
sub weekprofile_assignDev($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  my $prf = undef;
  if (defined($hash->{MASTERDEV})) {
    
    Log3 $me, 5, "$me(assignDev): assign to device $hash->{MASTERDEV}->{NAME}";
    
    my $type     = weekprofile_getDeviceType($hash->{MASTERDEV}->{NAME});
    if (!defined($type)) {
      Log3 $me, 2, "$me(assignDev): device $hash->{MASTERDEV}->{NAME} not supported or defined";
    } else {    
      $hash->{MASTERDEV}->{TYPE} = $type;
      
      my $prfDev = weekprofile_readDevProfile($hash->{MASTERDEV}->{NAME},$type, $me);
    
      $prf = {};
      $prf->{NAME} = 'master';
      $prf->{TOPIC} = 'default';
          
      if(defined($prfDev)) {
        $prf->{DATA} = $prfDev;
      } else {
        Log3 $me, 3, "WARNING master device $hash->{MASTERDEV}->{NAME} has no week profile - create default profile";
        $prf->{DATA} = weekprofile_createDefaultProfile($hash); 
      }
      $hash->{STATE} = "assigned";
    }
  }
  
  if (!defined($prf)) {
    my $prfDev = weekprofile_createDefaultProfile($hash);  
    if(defined($prfDev)) {
      $prf = {};
      $prf->{DATA} = $prfDev;
      $prf->{NAME} = 'default';
      $prf->{TOPIC} = 'default';
    }
    $hash->{STATE} = "created";
  }
  
  if(defined($prf)) {
    push @{$hash->{PROFILES}} , $prf; 
  }
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state",$hash->{STATE});
  readingsEndUpdate($hash, 1);
}
############################################## 
sub weekprofile_updateReadings($)
{
  my ($hash) = @_;
  
  my $prfCnt = scalar(@{$hash->{PROFILES}}); 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"profile_count",$prfCnt);
  
  #readings with profile names???
  #my $idx = 1;
  #foreach my $prf (@{$hash->{PROFILES}}){
    #my $str = sprintf("profile_name_%02d",$idx);
    #readingsBulkUpdate($hash,$str,$prf->{NAME});
    #$idx++;
  #}
  readingsEndUpdate($hash, 1);
}
############################################## 
sub weekprofile_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "weekprofile_Define";
  $hash->{SetFn}    = "weekprofile_Set";
  $hash->{GetFn}    = "weekprofile_Get";
  $hash->{SetFn}    = "weekprofile_Set";
  $hash->{StateFn}  = "weekprofile_State";
  $hash->{NotifyFn} = "weekprofile_Notify";
  $hash->{AttrFn}   = "weekprofile_Attr";
  $hash->{AttrList} = "widgetWeekdays widgetEditOnNewPage:0,1 configFile ".$readingFnAttributes;
  
  $hash->{FW_summaryFn}  = "weekprofile_SummaryFn";

  $hash->{FW_atPageEnd} = 1;
}
############################################## 
sub weekprofile_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 1) {
    my $msg = "wrong syntax: define <name> weekprofile [device]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  
  my $devName = undef;
  if (@a > 1) {
    $devName = $a[2];
    $devName =~ s/(^\s+|\s+$)//g if ($devName);
  }
  $hash->{MASTERDEV}->{NAME} = $devName if (defined($devName));
  
  $hash->{STATE} = "defined";
  my @profiles = ();
  my @sendDevList = ();
   
  $hash->{PROFILES} = \@profiles;
  $hash->{SNDDEVLIST} = \@sendDevList;
  
  #$attr{$me}{verbose} = 5;
  
  if ($init_done) {
    weekprofile_refreshSendDevList($hash);
    weekprofile_assignDev($hash);
    weekprofile_updateReadings($hash);
  }

  return undef;
}
############################################## 
sub weekprofile_Get($$@)
{
  my ($hash, $name, $cmd, @params) = @_;
  
  my $list = '';
  
  my $prfCnt = scalar(@{$hash->{PROFILES}});   
  $list.= 'profile_data:' if ($prfCnt > 0);
  
  foreach my $prf (@{$hash->{PROFILES}}){
    $list.= $prf->{NAME}.",";
  }
  
  $list = substr($list, 0, -1) if ($prfCnt > 0);

  if($cmd eq "profile_data") {
    return 'usage: profile_data <name>' if(@params < 1);
    return "no profile" if ($prfCnt <= 0);
    
    my ($topic, $name) = weekprofile_splitName($params[0]);

    my ($prf,$idx) = weekprofile_findPRF($hash,$name,$topic);
    return "profile $params[0] not found" unless ($prf);

    if (defined($prf->{REF})) {
      ($topic, $name) = weekprofile_splitName($prf->{REF});
      ($prf,$idx) = weekprofile_findPRF($hash,$name,$topic);
    }
    
    my $json = JSON->new;
    my $json_text = $json->encode($prf->{DATA});
    return $json_text;
  } 
  
  $list.= ' profile_names:noArg';
  if($cmd eq "profile_names") {
    my $names = '';
    foreach my $prf (@{$hash->{PROFILES}}){
      $names .=$prf->{NAME}.",";
    }
    $names = substr($names, 0, -1);
    return $names;
  }
  
  if($cmd eq "sndDevList") {
    my $json = JSON->new;
    my $json_text = $json->encode($hash->{SNDDEVLIST});
    return $json_text;
  }
  
  $list =~ s/ $//;
  return "Unknown argument $cmd choose one of $list"; 
}
############################################## 
sub weekprofile_findPRF(@)
{
  my ($hash, $name, $topic) = @_;
  
  $topic = 'default' if (!$topic);
  
  my $found = undef;
  my $idx = 0;
    
  foreach my $prf (@{$hash->{PROFILES}}){
    if ( ($prf->{NAME} eq $name) && ($prf->{TOPIC} eq $topic) ){
      $found = $prf;
      last;
    }
    $idx++;
  }
  $idx = -1 if (!defined($found));
  
  return ($found,$idx);
}

############################################## 
sub weekprofile_splitName($)
{
  my ($in) = @_;
  
  my @parts = split(':',$in);
  
  return ($parts[0],$parts[1]) if (@parts == 2);
  return ('default',$in);
}
############################################## 
sub weekprofile_Set($$@)
{
  my ($hash, $me, $cmd, @params) = @_;

  my $prfCnt = scalar(@{$hash->{PROFILES}});
  my $list = '';
  
  $list.= "profile_data";  
  if ($cmd eq 'profile_data') {
    return 'usage: profile_data <name> <json data>' if(@params < 2);
    
    my ($topic, $name) = weekprofile_splitName($params[0]);
    my $jsonData = $params[1];

    my $json = JSON->new;
    my $data = undef;
    eval { $data = $json->decode($jsonData); };
    if ($@) {
      Log3 $me, 1, "$me(Set): Error parsing profile data.";
      return "Error parsing profile data. No valid json format";
    };
    
    my ($found,$idx) = weekprofile_findPRF($hash,$name,$topic);
    if (defined($found)) {
      $found->{DATA} = $data;
      # automatic we send master profile to master device
      if ( ($name eq "master") && defined($hash->{MASTERDEV}) ){
        weekprofile_sendDevProfile($hash->{MASTERDEV}->{NAME},$found,$me);
      } else {
        weekprofile_writeProfilesToFile($hash);
      }
      return undef;
    }

    my $prfNew = {};
    $prfNew->{NAME} = $name;
    $prfNew->{DATA} = $data;
    $prfNew->{TOPIC} = $topic;
    
    push @{$hash->{PROFILES}}, $prfNew;
    weekprofile_updateReadings($hash);
    weekprofile_writeProfilesToFile($hash);
    return undef;
  }
  #----------------------------------------------------------
  $list.= ' send_to_device' if ($prfCnt > 0);
  
  if ($cmd eq 'send_to_device') {
    return 'usage: send_to_device <name> [device(s)]' if(@params < 1);
    
    my ($topic, $name) = weekprofile_splitName($params[0]);
    
    my @devices = ();
    if (@params == 2) {
      @devices = split(',',$params[1]);
    } else {
      push @devices, $hash->{MASTERDEV}->{NAME} if (defined($hash->{MASTERDEV}));
    }
    
    return "Error no devices given and no master device" if (@devices == 0);
    
    my ($found,$idx) = weekprofile_findPRF($hash,$name,$topic);
    if (!defined($found)) {
      Log3 $me, 1, "$me(Set): Error unknown profile $params[0]";
      return "Error unknown profile $params[0]";
    }
    
    my $err = '';
    foreach my $device (@devices){
      my $ret = weekprofile_sendDevProfile($device,$found,$me);
      if ($ret) {
        Log3 $me, 1, "$me(Set): $ret" if ($ret);
        $err .= $ret . "\n";
      }
    }
    return $err;
  }
  #----------------------------------------------------------
  $list.= " copy_profile";
  if ($cmd eq 'copy_profile') {
    return 'usage: copy_profile <source> <target>' if(@params < 2);
    
    my ($srcTopic, $srcName) = weekprofile_splitName($params[0]);
    my ($destTopic, $destName) = weekprofile_splitName($params[1]);
    
    my $prfSrc = undef;
    my $prfDest = undef;
    foreach my $prf (@{$hash->{PROFILES}}){
      $prfSrc = $prf if ( ($prf->{NAME} eq $srcName) && ($prf->{TOPIC} eq $srcTopic) );
      $prfDest = $prf if ( ($prf->{NAME} eq $destName) && ($prf->{TOPIC} eq $destTopic) );
    }
    return "Error unknown profile $srcName" unless($prfSrc);
    Log3 $me, 4, "$me(Set): override profile $destName" if ($prfDest);
    
    if ($prfDest){
      $prfDest->{DATA} = $prfSrc->{DATA}
    } else {
      $prfDest = {};
      $prfDest->{NAME} = $destName;
      $prfDest->{DATA} = $prfSrc->{DATA};
      $prfDest->{TOPIC} = $destTopic;
      push @{$hash->{PROFILES}}, $prfDest;
    }
    weekprofile_writeProfilesToFile($hash);
    weekprofile_updateReadings($hash);
    return undef;
  }
  
  #----------------------------------------------------------
  $list.= " reference_profile";
  if ($cmd eq 'reference_profile') {
    return 'usage: copy_profile <source> <target>' if(@params < 2);
    
    my ($srcTopic, $srcName) = weekprofile_splitName($params[0]);
    my ($destTopic, $destName) = weekprofile_splitName($params[1]);
    
    my $prfSrc = undef;
    my $prfDest = undef;
    foreach my $prf (@{$hash->{PROFILES}}){
      $prfSrc = $prf if ( ($prf->{NAME} eq $srcName) && ($prf->{TOPIC} eq $srcTopic) );
      $prfDest = $prf if ( ($prf->{NAME} eq $destName) && ($prf->{TOPIC} eq $destTopic) );
    }
    return "Error unknown profile $srcName" unless($prfSrc);
    Log3 $me, 4, "$me(Set): override profile $destName" if ($prfDest);
    
    if ($prfDest){
      $prfDest->{DATA} = undef;
      $prfDest->{REF} = "$destTopic:$destName";
    } else {
      $prfDest = {};
      $prfDest->{NAME} = $destName;
      $prfDest->{DATA} = undef;
      $prfDest->{TOPIC} = $destTopic;
      $prfDest->{REF} = "$destTopic:$destName";
      push @{$hash->{PROFILES}}, $prfDest;
    }
    weekprofile_writeProfilesToFile($hash);
    weekprofile_updateReadings($hash);
    return undef;
  }
  
  #----------------------------------------------------------
  $list.= " remove_profile";
  if ($cmd eq 'remove_profile') {
    return 'usage: remove_profile <name>' if(@params < 1);
    return 'Error master profile can not removed' if( ($params[0] eq "master") && defined($hash->{MASTERDEV}) );
    return 'Error Remove last profile is not allowed' if(scalar(@{$hash->{PROFILES}}) == 1);
    
    my ($topic, $name) = weekprofile_splitName($params[0]);
    
    my ($delprf,$idx)  = weekprofile_findPRF($hash,$name,$topic);
    return "Error unknown profile $params[0]" unless($delprf);
    
    splice(@{$hash->{PROFILES}},$idx, 1);
    weekprofile_writeProfilesToFile($hash);
    weekprofile_updateReadings($hash);
    return undef;
  }
  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list"; 
}
############################################## 
sub weekprofile_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  #do nothing we do not restore readings from statefile
  return undef;
}
############################################## 
sub weekprofile_Notify($$)
{
  my ($own, $dev) = @_;
  my $me = $own->{NAME}; # own name / hash
  my $devName = $dev->{NAME}; # Device that created the events

  my $max = int(@{$dev->{CHANGED}}); # number of events / changes
  
  if ($devName eq "global"){
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      
      next if(!defined($s));
      my ($what,$who) = split(' ',$s);
      
      if ($what =~ m/INITIALIZED/) {
        splice($own->{PROFILES});
        weekprofile_refreshSendDevList($own);
        weekprofile_assignDev($own);
        weekprofile_readProfilesFromFile($own);
        weekprofile_updateReadings($own);
      }
      
      if ($what =~ m/DEFINED/ || $what =~ m/DELETED/) {
        weekprofile_refreshSendDevList($own);
      }
    }
  }
  
  if ($init_done && defined($own->{MASTERDEV}) && 
      ($own->{MASTERDEV}->{NAME} eq $devName) && 
      (@{$own->{PROFILES}} > 0) ) {
    
    my $readprf=0;
    
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      
      next if(!defined($s));
      my ($what,$who) = split(' ',$s);
  
      Log3 $me, 5, "$me(Notify): $devName, $what";
      
      if ($own->{MASTERDEV}->{NAME} eq 'MAX') {
        $readprf =1 if ($what=~m/weekprofile/); #reading weekprofile
      } else {
         # toDo nur auf spezielle notify bei anderen typen reagieren!!
        $readprf = 1;
      }
      
      last if ($readprf);
    }
    
    if ($readprf) {
      Log3 $me, 4, "$me(Notify): reread master profile from $devName";
      my $prfDev = weekprofile_readDevProfile($own->{MASTERDEV}->{NAME},$own->{MASTERDEV}->{TYPE}, $me);
      if(defined($prfDev)) {
        $own->{PROFILES}[0]->{DATA} = $prfDev;
        weekprofile_updateReadings($own);
      }
    }
  }
  return undef;
}
############################################## 
sub weekprofile_Attr($$$)
{
  my ($cmd, $me, $attrName, $attrVal) = @_;
  
  my $hash = $defs{$me};
  
  Log3 $me, 5, "$me(weekprofile_Attr): $cmd, $attrName, $attrVal";
  
  $attr{$me}{$attrName} = $attrVal;
  weekprofile_writeProfilesToFile($hash) if ($attrName eq 'configFile');
  return undef;
  
}
############################################## 
sub weekprofile_writeProfilesToFile(@)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  my $start = (defined($hash->{MASTERDEV})) ? 1:0;
  my $prfCnt = scalar(@{$hash->{PROFILES}});
  return if ($prfCnt <= $start);

  my $filename = "./log/weekprofile-$me.cfg";
  $filename = AttrVal($me,"configFile",$filename);

  my $ret = open(my $fh, '>', $filename);
  if (!$ret){
    Log3 $me, 1, "$me(writeProfileToFile): Could not open file '$filename' $!";
    return;
  }
  
  print $fh "__version__=".$CONFIG_VERSION."\n";  
  
  Log3 $me, 5, "$me(writeProfileToFile): write profiles to $filename";
  my $json = JSON->new;
  for (my $i = $start; $i < $prfCnt; $i++) {
    print $fh "entry=".$json->encode($hash->{PROFILES}[$i])."\n";
  }  
  close $fh;
}
############################################## 
sub weekprofile_readProfilesFromFile(@)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};

  my $filename = "./log/weekprofile-$me.cfg";
  $filename = AttrVal($me,"configFile",$filename);
  
  unless (-e $filename) {
     Log3 $me, 5, "$me(readProfilesFromFile): file do not exist '$filename'";
     return;
  }
  
  my $ret = open(my $fh, '<:encoding(UTF-8)', $filename);
  if (!$ret){
    Log3 $me, 1, "$me(readProfilesFromFile): Could not open file '$filename' $!";
    return;
  }
  
  Log3 $me, 5, "$me(readProfilesFromFile): read profiles from $filename";
  
  my $json = JSON->new;  
  my $rowCnt = 0;
  my $version = undef;
  while (my $row = <$fh>) {
    chomp $row;    
    Log3 $me, 5, "$me(readProfilesFromFile): data row $row";
    my @data = split('=',$row);
    if(@data<2){
      Log3 $me, 1, "$me(readProfilesFromFile): incorrect data row";
      next;
    }
    
    if ($rowCnt == 0 && $data[0]=~/__version__/) {
      $version=$data[1] * 1;
      Log3 $me, 5, "$me(readProfilesFromFile): detect version $version";
      next;
    }
    
    if (!$version || $version < 1.1) {
      my $prfData=undef;
      eval { $prfData = $json->decode($data[1]); };
      if ($@) {
        Log3 $me, 1, "$me(readProfilesFromFile): Error parsing profile data $data[1]";
        next;
      };
          
      my $prfNew = {};
      $prfNew->{NAME} = $data[0];
      $prfNew->{DATA} = $prfData;
      $prfNew->{TOPIC} = 'default';
      
      if (!$hash->{MASTERDEV} && $rowCnt == 0) {
        $hash->{PROFILES}[0] = $prfNew; # replace default
      } else {
        push @{$hash->{PROFILES}}, $prfNew;
      }
      $rowCnt++;
    } #----------------------------------------------------- 1.1
    elsif ($version = 1.1) {
      my $prfNew=undef;
      eval { $prfNew = $json->decode($data[1]); };
      if ($@) {
        Log3 $me, 1, "$me(readProfilesFromFile): Error parsing profile data $data[1]";
        next;
      };
      
      if (!$hash->{MASTERDEV} && $rowCnt == 0) {
        $hash->{PROFILES}[0] = $prfNew; # replace default
      } else {
        push @{$hash->{PROFILES}}, $prfNew;
      }
      $rowCnt++;
    } else {
      Log3 $me, 1, "$me(readProfilesFromFile): Error unknown version $version";
      close $fh;
      return;
    }
  }  
  close $fh;
}

############################################## 
sub weekprofile_SummaryFn()
{
  my ($FW_wname, $d, $room, $extPage) = @_;
  my $hash = $defs{$d};
  
  my $show_links = 1;
  $show_links = 0 if($FW_hiddenroom{detail});

  my $html;
  
  my $iconName = AttrVal($d, "icon", "edit_settings");
  my $editNewpage = AttrVal($d, "widgetEditOnNewPage", 0);
  
  my $editIcon = FW_iconName($iconName) ? FW_makeImage($iconName,$iconName,"icon") : "";
  $editIcon = "<a name=\"$d.edit\" onclick=\"weekprofile_DoEditWeek('$d','$editNewpage')\" href=\"javascript:void(0)\">$editIcon</a>";
  
  my $lnkDetails = AttrVal($d, "alias", $d);
  $lnkDetails = "<a name=\"$d.detail\" href=\"$FW_ME$FW_subdir?detail=$d\">$lnkDetails</a>" if($show_links);
  
  my $masterDev = defined($hash->{MASTERDEV}) ? $hash->{MASTERDEV}->{NAME} : undef; 
  
  my $args = "weekprofile,MODE:SHOW";
  $args .= ",MASTERDEV:$masterDev" if (defined($masterDev));
  
  my $curr = "";
  $curr = $hash->{PROFILES}[0]->{NAME} if (@{$hash->{PROFILES}} > 0 );
  
  $html .= "<table>";
  $html .= "<tr><td>";
  $html .= "<div class=\"devType\" id=\"weekprofile.$d.header\">";
  $html .= "<div class=\"devType\" id=\"weekprofile.menu.base\">";
  $html .= $editIcon."&nbsp;".$lnkDetails;
  $html .= "</di></div></td></tr>";
  $html .= "<tr><td>";
  $html .= "<div class=\"fhemWidget\" informId=\"$d\" cmd=\"\" arg=\"$args\" current=\"$curr\" dev=\"$d\">"; # div tag to support inform updates
  $html .= "</div>";
  $html .= "</td></tr>";
  $html .= "</table>";
  return $html;
}
############################################## 
sub weekprofile_editOnNewpage(@)
{
  my ($device, $prf,$backurl) = @_;
  my $hash = $defs{$device};
  
  $backurl="?"  if(!defined($backurl));
  my $args = "weekprofile,MODE:EDIT,BACKURL:$backurl";
  
  my $html;
  $html .= "<html>";
  $html .= "<table>";
  $html .= "<tr><td>";
  $html .= "<div class=\"devType\" id=\"weekprofile.$device.header\">";
  $html .= "<div class=\"devType\" id=\"weekprofile.menu.base\">";
  $html .= "</di></div></td></tr>";
  $html .= "<tr><td>";
  $html .= "<div class=\"fhemWidget\" informId=\"$device\" cmd=\"\" arg=\"$args\" current=\"$prf\" dev=\"$device\">"; # div tag to support inform updates
  $html .= "</div>";
  $html .= "</td></tr>";
  $html .= "</table>";
  $html .= "</html>";
  return $html;
}
############################################## 
#search device weekprofile from a assoziated master device
sub weekprofile_findPRFDev($)
{
  my ($device) = @_;
  
  foreach my $d (keys %defs)   
  {
    my $module   = $defs{$d}{TYPE};
    
    next if ("$module" ne "weekprofile");     
    
    next if (!defined($defs{$d}->{MASTERDEV}));
    my $masterDev = $defs{$d}->{MASTERDEV}->{NAME};
    next unless(defined($masterDev));
    next if ($masterDev ne $device);
    
    return $defs{$d}{NAME};
  }
  return undef;
}
##############################################
# get a web link to edit a profile from weekprofile from a assoziated master device
sub weekprofile_getEditLNK_MasterDev($$)
{
  my ($aszDev, $prf) = @_;
  
  my $device = weekprofile_findPRFDev($aszDev);
  return "" if (!defined($device));
  
  my $iconName = AttrVal($device, "icon", "edit_settings");
   
  my $editIcon = FW_iconName($iconName) ? FW_makeImage($iconName,$iconName,"icon") : "";
  my $script = '<script type="text/javascript">';
  $script.= "function jump_edit_weekprofile_$aszDev() {";
  $script.= 'var url;var pos = location.href.indexOf("?"); if (pos>=0) {url = location.href.substr(pos);}';
  $script.= "window.location.assign('$FW_ME?cmd={weekprofile_editOnNewpage(";
  $script.= "\"$device\",\"$prf\",\"'+url+'\");;}')};";
  $script.= "</script>";
  
  my $lnk = "$script<a onclick=\"jump_edit_weekprofile_$aszDev()\" href=\"javascript:void(0)\">$editIcon</a>";
  return ($lnk,0);
}
1;

=pod
=item helper

=begin html_de

<a name="weekprofile"></a>
<h3>weekprofile</h3>
<ul>
  Mit dem Modul 'weekprofile' können mehrere Wochenprofile verwaltet und an unterschiedliche Geräte 
  übertragen werden. Aktuell wird folgende Hardware unterstützt:
  <li>alle MAX Thermostate</li>
  <li>andere weekprofile Module</li>
  <li>Homatic (Kanal _Clima bzw. _Climate)</li>
  
  Im Standardfall wird das Modul mit einem Geräte = 'Master-Gerät' assoziiert,
  um das Wochenprofil vom Gerät grafisch bearbeiten zu können und andere Profile auf das Gerät zu übertragen.
  <br>
  <b>Achtung:</b> Das Übertragen von Wochenprofilen erfordet eine Menge an Credits. 
  Dies wird vom Modul nicht berücksichtigt. So kann es sein, dass nach dem 
  Setzen\Aktualisieren eines Profils das Profil im Modul nicht mit dem Profil im Gerät 
  übereinstimmt solange das komplette Profil übertragen wurde.
  <br>
  Beim Homatic HM-TC-IT-WM-W-EU wird nur das 1. Profil (R_P1_...) genommen!
  <br>
  <b>Für das Module wird libjson-perl benötigt</b>
  <br><br>
  <a name="weekprofiledefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; weekprofile [master device]</code><br>
    <br>
    Aktiviert das Modul. Bei der Angabe eines 'Master-Gerätes' wird das Profil 'master'
    entprechende dem Wochenrofil vom Gerät angelegt.
    Sonderbehandlung des 'master' Profils:
    <li>Kann nicht gelöscht werden</li>
    <li>Bei Ändern\Setzen des Proils wird es automatisch an das 'Master-Geräte' gesendet</li>
    <li>Es wird sind mit abgespeicht</li>
    <br>
    Wird kein 'Master-Geräte' angegeben, wird ein 'default' Profil angelegt.
  </ul>
  
  <a name="weekprofileset"></a>
  <b>Set</b>
  <ul>
    <li>profile_data<br>
       <code>set &lt;name&gt; profile_data &lt;profilname&gt; &lt;json data&gt; </code><br>
       Es wird das Profil 'profilname' geändert. Die Profildaten müssen im json-Format übergeben werden.
    </li>
    <li>send_to_device<br>
      <code>set &lt;name&gt; send_to_device &lt;profilname&gt; [devices] </code><br>
      Das Profil wird an ein oder mehrere Geräte übertragen. Wird kein Gerät angegeben, wird das 'Master-Gerät' verwendet.
      'Devices' ist eine kommagetrennte Auflistung von Geräten
    </li>
    <li>copy_profile<br>
      <code>set &lt;name&gt; copy_profile &lt;quelle&gt; &lt;ziel&gt; </code><br>
      Kopiert das Profil 'quelle' auf 'ziel'. 'ziel' wird überschrieben oder neu angelegt.
    </li>
    <li>remove_profile<br>
      <code>set &lt;name&gt; remove_profile &lt;profilname&gt; </code><br>
      Das Profil 'profilname' wird gelöscht.
    </li>
  </ul>
  
  <a name="weekprofileget"></a>
  <b>Get</b>
  <ul>
    <li>profile_data<br>
       <code>get &lt;name&gt; profile_data &lt;profilname&gt; </code><br>
       Liefert die Profildaten von 'profilname' im json-Format
    </li>
    <li>profile_names<br>
      <code>set &lt;name&gt; profile_names</code><br>
      Liefert alle Profilnamen getrennt durch ','
    </li>
  </ul>
  
  <a name="weekprofileattr"></a>
  <b>Attribute</b>
  <ul>
    <li>widgetWeekdays<br>
      Liste von Wochentagen getrennt durch ',' welche im Widget angzeigt werden. 
      Beginnend bei Montag. z.B.
      <code>attr name widgetWeekdays Montag,Dienstag,Mittwoch,Donnerstag,Freitag,Samstag,Sonntag</code>
    </li>
    <li>widgetEditOnNewPage<br>
      Wenn gesetzt ('1'), dann wird die Bearbeitung auf einer separaten\neuen Webseite gestartet.
    </li>
     <li>configFile<br>
      Pfad und Dateiname wo die Profile gespeichert werden sollen.
      Default: ./log/weekprofile-<name>.cfg
    </li>
    <li>icon<br>
      Änders des Icons zum Bearbeiten
      Default: edit_settings
    </li>
  </ul>
  
</ul>
=end html_de

=begin html

<a name="weekprofile"></a>
<h3>weekprofile</h3>
<ul>
  With this module you can manage and edit different weekprofiles. You can send the profiles to different devices.<br>
  Currently the following devices will by supported:<br>
  <li>MAX</li>
  <li>other weekprofile modules</li>
  <li>Homatic channel _Clima or _Climate</li>
  
  In the normal case the module is assoziated with a master device.
  So a profile 'master' will be created automatically. This profile correnspond to the current active
  profile on the master device.
  You can also use this module without a master device. In this case a default profile will be created.
  <br>
  <b>Attention:</b> 
  To transfer a profile to a device it needs a lot of Credits. 
  This is not taken into account from this module. So it could be happend that the profile in the module 
  and on the device are not equal until the whole profile is transfered completly.
  <br>
  If the maste device is Homatic HM-TC-IT-WM-W-EU then only the first profile (R_P1_...) will be used!
  <br>
  <b>For this module libjson-perl have to be installed</b>
  <br><br>
  <a name="weekprofiledefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; weekprofile [master device]</code><br>
    <br>
    Activate the module with or without an assoziated master device. The master device is an optional parameter.
    With a master device a spezial profile 'master' will be created.<br>
    Special master' profile handling:<br>
    <li>Can't be deleted</li>
    <li>Will be automatically transfered to the master device if it was modified</li>
    <li>Will not be saved</li>
    <br>
    Without a master device a 'default' profile will be created
  </ul>
  
  <a name="weekprofileset"></a>
  <b>Set</b>
  <ul>
    <li>profile_data<br>
       <code>set &lt;name&gt; profile_data &lt;profilename&gt; &lt;json data&gt; </code><br>
       The profile 'profilename' will be changed. The data have to be in json format.
    </li>
    <li>send_to_device<br>
      <code>set &lt;name&gt; send_to_device &lt;profilename&gt; [devices] </code><br>
      The profile 'profilename' will be transfered to one or more the devices. Without the parameter device the profile 
      will be transferd to the master device. 'devices' is a comma seperated list of device names
    </li>
    <li>copy_profile<br>
      <code>set &lt;name&gt; copy_profile &lt;source&gt; &lt;destination&gt; </code><br>
      Copy from source to destination. The destination will be overwritten
    </li>
    <li>remove_profile<br>
      <code>set &lt;name&gt; remove_profile &lt;profilename&gt; </code><br>
      Delete profile 'profilename'.
    </li>
  </ul>
  
  <a name="weekprofileget"></a>
  <b>Get</b>
  <ul>
    <li>profile_data<br>
       <code>get &lt;name&gt; profile_data &lt;profilename&gt; </code><br>
       Get the profile date from 'profilename' in json-Format
    </li>
    <li>profile_names<br>
      <code>set &lt;name&gt; profile_names</code><br>
      Get a comma seperated list of profile names
    </li>
  </ul>
  
  <a name="weekprofileattr"></a>
  <b>Attributes</b>
  <ul>
    <li>widgetWeekdays<br>
      Comma seperated list od week days starting at Monday
      <code>attr name widgetWeekdays Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday</code>
    </li>
    <li>widgetEditOnNewPage<br>
      Editing the profile on a new html page if it is set to '1'
    </li>
     <li>configFile<br>
      Path and filename of the configuration file where the profiles will be stored
      Default: ./log/weekprofile-<name>.cfg
    </li>
    <li>icon<br>
      icon for edit
      Default: edit_settings
    </li>
  </ul>
  
</ul>
=end html

=cut
