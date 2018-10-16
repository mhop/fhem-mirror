########################################################################################
#
#  Shelly.pm
#
#  FHEM module to communicate with Shelly switch/roller actor devices
#  Prof. Dr. Peter A. Henning, 2018
# 
#  $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################

package main;

use strict;
use warnings;

use JSON;      # imports encode_json, decode_json, to_json and from_json.

use vars qw{%attr %defs};

sub Log($$);

#-- globals on start
my $version = "1.36";

#-- these we may get on request
my %gets = (
  "status:noArg"     => "S",
  "registers:noArg"  => "R",
  "config"           => "C",
  "version:noArg"    => "V"
);

#-- these we may set
my %setssw = (
  "on"            => "O",
  "off"           => "F",
  "on-for-timer"  => "T",
  "off-for-timer" => "E",
  "config"        => "C",
);

my %setsrol = (
  "closed:noArg"  => "C",
  "open:noArg"    => "O",
  "stop:noArg"    => "S",
  "pct:slider,0,1,100"           => "P" 
); 

my %shelly_models = (
    #(relays,rollers,meters)
    "shelly1" => [1,0,0,],
    "shelly2" => [2,1,1],
    "shellyplug" => [1,0,1],
    "shelly4" => [4,0,4]
    );
    
my %shelly_regs = (
    "relay" => "reset=1\x{27f6}factory reset\ndefault_state=off|on|last|switch\x{27f6}state after power on\nbtn_type=momentary|toggle|edge\x{27f6}type of local button\nauto_on=&lt;seconds&gt;\x{27f6}timed on\nauto_off=&lt;seconds&gt;\x{27f6}timed off",
    "roller" => "reset=1\x{27f6}factory reset\ndefault_state=stop|open|close|switch\x{27f6}state after power on\nswap=true|false\x{27f6}swap open and close\ninput_mode=openclose|onebutton\x{27f6}two or one local button\n".
                  "btn_type=momentary|toggle\x{27f6}type of local button\nobstacle_mode=disabled|while_opening|while_closing|while_moving\x{27f6}when to watch\nobstacle_action=stop|reverse\x{27f6}what to do\n".
                  "obstacle_power=&lt;watt&gt;\x{27f6}power threshold for detection\nobstacle_delay=&lt;seconds&gt;\x{27f6}delay after motor start to watch\n".
                  "safety_mode=disabled|while_opening|while_closing|while_moving\x{27f6}safety mode=2nd button\nsafety_action=stop|pause|reverse\x{27f6}action when safety mode\n".
                  "safety_allowed_on_trigger=none|open|close|all\x{27f6}commands allowed in safety mode"
    );

########################################################################################
#
# Shelly_Initialize
#
# Parameter hash
#
########################################################################################

sub Shelly_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}    = "Shelly_Define";
  $hash->{UndefFn}  = "Shelly_Undef";
  $hash->{AttrFn}   = "Shelly_Attr";
  $hash->{GetFn}    = "Shelly_Get";
  $hash->{SetFn}    = "Shelly_Set";
  #$hash->{NotifyFn} = "Shelly_Notify";
  #$hash->{InitFn}   = "Shelly_Init";

  $hash->{AttrList}= "verbose model:".join(",",(keys %shelly_models))." mode:relay,roller defchannel maxtime maxpower interval pct100:open:closed ".
                     $readingFnAttributes;
}

########################################################################################
#
# Shelly_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub Shelly_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "[Shelly] Define the IP address of the Shelly device as a parameter"
    if(@a != 3);
  return "[Shelly] Invalid IP address ".$a[2]." of Shelly device"
    if( $a[2] !~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| );
  
  my $dev = $a[2];
  #-- split into parts
  my @tcp = split(':',$dev);
  #-- when the specified ip address contains a port already, use it as supplied
  if ( $tcp[1] ){
    $hash->{TCPIP} = $dev;
  }else{
    $hash->{TCPIP} = $tcp[0].":80";
  };
    
  $hash->{DURATION} = 0;
  $hash->{MOVING} = 0;
  delete $hash->{BLOCKED};
  $hash->{INTERVAL} = 60;
  
  $modules{Shelly}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsBeginUpdate($hash);
  my $err = Shelly_status($hash);
  if( !defined($err) ){
    readingsBulkUpdate($hash,"state","initialized");
    readingsBulkUpdate($hash,"network","connected");
  }else{
    readingsBulkUpdate($hash,"state",$err);
    readingsBulkUpdate($hash,"network","not connected");
  }
  readingsEndUpdate($hash,1); 
     
  $init_done = $oid;
  
  return undef;
}

#######################################################################################
#
# Shelly_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub Shelly_Undef ($) {
  my ($hash) = @_;
  delete($modules{Shelly}{defptr}{NAME});
  RemoveInternalTimer($hash);
  return undef;
}

#######################################################################################
#
# Shelly_Attr - Set one attribute value
#
########################################################################################

sub Shelly_Attr(@) {
  my ($cmd,$name,$attrName, $attrVal) = @_;
  
  my $hash = $main::defs{$name};
  my $ret;
  
  my $model =  AttrVal($name,"model","shelly2");
  my $mode  =  AttrVal($name,"mode","relay");

  #-- temporary code
  delete $hash->{BLOCKED};
  
  #---------------------------------------  
  if ( ($cmd eq "set") && ($attrName =~ /model/) ) {
    my $regex = "((".join(")|(",(keys %shelly_models))."))";
    if( $attrVal !~ /$regex/){
      Log3 $name,1,"[Shelly_Attr] wrong value of model attribute, see documentation for possible values";
      return
    } 
    #-- only one channel
    if( $shelly_models{$model}[0] == 1){      
      fhem("deletereading ".$name." relay_.*");
      fhem("deletereading ".$name." overpower_.*");  
    }else{
      fhem("deletereading ".$name." relay");
      fhem("deletereading ".$name." overpower");  
    }
    #-- no rollers
    if( $shelly_models{$model}[1] == 0){  
      fhem("deletereading ".$name." position.*");
      fhem("deletereading ".$name." stop_reason.*");
      fhem("deletereading ".$name." last_dir.*");
      fhem("deletereading ".$name." pct.*");
      delete $hash->{MOVING};
      delete $hash->{DURATION};
    }

    #-- always clear readings for meters
    #if( $shelly_models{$model}[2] <= 1){
      fhem("deletereading ".$name." power.*");
      fhem("deletereading ".$name." overpower.*");
    #}
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName =~ /mode/) ) {
    if( $model ne "shelly2" ){
      Log3 $name,1,"[Shelly_Attr] setting the mode attribute only works for model=shelly2";
      return
    }
    if( $attrVal !~ /((relay)|(roller))/){
      Log3 $name,1,"[Shelly_Attr] wrong mode value $attrVal";
      return;
    }elsif( $attrVal eq "relay"){
      fhem("deletereading ".$name." position.*");
      fhem("deletereading ".$name." stop_reason.*");
      fhem("deletereading ".$name." last_dir.*");
      fhem("deletereading ".$name." pct.*");
    }elsif( $attrVal eq "roller"){
      fhem("deletereading ".$name." relay.*");
      fhem("deletereading ".$name." overpower.*");
    }    
    Shelly_configure($hash,"settings?mode=".$attrVal);
  
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "maxtime") ) {
    if( ($model ne "shelly2") || ($mode ne "roller" ) ){
      Log3 $name,1,"[Shelly_Attr] setting the maxtime attribute only works for model=shelly2 and mode=roller";
      return
    }
    Shelly_configure($hash,"settings?maxtime=".$attrVal);
  
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "pct100") ) {
    if( ($model ne "shelly2") || ($mode ne "roller" ) ){
      Log3 $name,1,"[Shelly_Attr] setting the pct100 attribute only works for model=shelly2 and mode=roller";
      return
    }
    
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "interval") ) {
    #-- update timer
    $hash->{INTERVAL} = int($attrVal);

    if ($init_done) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 0);
    }
  }
  return 
}
  
########################################################################################
#
# Shelly_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub Shelly_Get ($@) {
  my ($hash, @a) = @_;
  
  #-- check syntax
  my $name = $hash->{NAME};
  my $v;
  
  my $model =  AttrVal($name,"model","");
  my $mode  =  AttrVal($name,"mode","");

  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $version";
    
  #-- current status
  }elsif($a[1] eq "status") {
    $v = Shelly_status($hash);
  
  #-- some help on registers
  }elsif($a[1] eq "registers") {
    my $txt = "relay";
    $txt = "roller"
      if( ($model eq "shelly2") && ($mode eq "roller") );
    return $shelly_regs{$txt}."\n\nSet/Get these registers by calling set/get $name config &lt;registername&gt; [&lt;channel&gt;] &lt;value&gt;";
  
  #-- configuration register
  }elsif($a[1] eq "config") {
    my $reg = $a[2];
    my ($chan,$val);
    if( int(@a) == 5 ){
      $chan = $a[3];
      $val = $a[4];
    }elsif( int(@a) == 4 ){
      $chan = 0;
      $val = $a[3];
    }else{
      my $msg = "Error: wrong number of parameters";
      Log3 $name,1,"[Shelly_Get] ".$msg;
      return $msg;
    }
    my $pre = "settings/";
    if( ($model eq "shelly2") && ($mode eq "roller") ){
      $pre .= "roller/$chan?";
    }else{
      $pre .= "relay/$chan?";
      $v = Shelly_configure($hash,$pre.$reg);
    }
    
  #-- else
  } else {
    my $newkeys = join(" ", sort keys %gets);
    $newkeys    =~  s/:noArg//g
      if( $a[1] ne "?");
    return "[Shelly_Get] with unknown argument $a[1], choose one of ".$newkeys;
  }
  
  if(defined($v)) {
     return "$a[0] $a[1] => $v";
  }
  return "$a[0] $a[1] => ok";
}
 
########################################################################################
#
# Shelly_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub Shelly_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  
  my ($newkeys,$cmd,$value,$v,$msg);

  $cmd      = shift @a;
  $value    = shift @a; 
  
  my $model =  AttrVal($name,"model","shelly2");
  my $mode  =  AttrVal($name,"mode","relay");
  my ($channel,$time);
  
  #-- we have a Shelly 1,4 or ShellyPlug switch type device
  #-- or we have a Shelly 2 switch type device
  if( ($model eq "shelly1") || ($model eq "shelly4") || ($model eq "shellyplug") || (($model eq "shelly2") && ($mode eq "relay")) ){ 
    
    #-- WEB asking for command list 
    if( $cmd eq "?" ) {   
      $newkeys = join(" ", sort keys %setssw);
      #$newkeys =~ s/on\s/on:0,1 /;
      #$newkeys =~ s/off\s/off:0,1 /;
      return "[Shelly_Set] Unknown argument " . $cmd . ", choose one of ".$newkeys;
    }
    
    if( $cmd =~ /^((on)|(off)).*/ ){
      $channel = $value;
      if( $cmd =~ /(.*)-for-timer/ ){
        $time = shift @a;
        if( !defined($time) ){
          $time    = $value;
          $channel = undef;
        }
      }
      if( $shelly_models{$model}[0] == 1){
       $channel = 0
      }else{  
        if( !defined($channel) || ($channel !~ /[0123]/) || $channel >= $shelly_models{$model}[0] ){
          if( !defined($channel) ){
            $channel = AttrVal($name,"defchannel",undef);
            if( !defined($channel) ){
              $msg = "Error: wrong channel $channel given and defchannel attribute not set properly";
              Log3 $name, 1,"[Shelly_Set] ".$msg;
              return $msg;
            }else{
              Log3 $name, 4,"[Shelly_Set] switching default channel $channel";
            }
          }
        }
      }
      if( $cmd =~ /(.*)-for-timer/ ){
        $cmd = $1;
        if( $time !~ /\d+/ ){
          $msg = "Error: wrong time spec $time, must be <integer>";
          Log3 $name, 1,"[Shelly_Set] ".$msg;
          return $msg;
        }
        $cmd = $cmd."&timer=$time";
      }
      Shelly_onoff($hash,$channel,"?turn=".$cmd);
    }
    
  #-- we have a Shelly 2 roller type device
  }elsif( ($model eq "shelly2") && ($mode eq "roller") ){ 
    my $channel = $value;
    my $max=AttrVal($name,"maxtime",undef);  
    #-- WEB asking for command list 
    if( $cmd eq "?" ) {   
      $newkeys = join(" ", sort keys %setsrol);
      return "[Shelly_Set] Unknown argument " . $cmd . ", choose one of ".$newkeys;
    }
    
    if( $hash->{MOVING} ){
      $msg = "Error: roller blind still moving, wait for some time";
      Log3 $name,1,"[Shelly_Set] ".$msg;
      return $msg
    }
    
    if( $cmd eq "closed" ){
      Shelly_updown($hash,"?go=close");
      $hash->{DURATION} = $max;
    }elsif( $cmd eq "open" ){
      Shelly_updown($hash,"?go=open");
      $hash->{DURATION} = $max;
    }elsif( $cmd eq "stop" ){
      Shelly_updown($hash,"?go=stop");
      $hash->{DURATION} = 0;
    }elsif( $cmd eq "pct" ){
      my $tpct = $value;
      my $pos  = ReadingsVal($name,"position","");
      my $pct  = ReadingsVal($name,"pct",undef); 
      
      if( !$max ){
        $msg = "Error: pct value can be set only if maxtime attribute is set properly";
        Log3 $name,1,"[Shelly_Set] ".$msg;
        return $msg
      }
      my $normal = (AttrVal($name,"pct100","open") eq "open");
      if( $pos eq "open" ){
        #-- 100% = open
        if($normal){
          $time = int(($max*(100-$tpct))/10)/10;
        }else{
          $time = int(($max*$pct)/10)/10;
        }
        $cmd = "?go=close&duration=".$time; 
      }elsif( $pos eq "closed" ){
        #-- 100% = open
        if($normal){
          $time = int(($max*$tpct)/10)/10;
        }else{
          $time = int(($max*(100-$tpct))/10)/10;
        }
        $cmd = "?go=open&duration=".$time; 
      }else{
        if( !defined($pct) ){
          $msg = "Error: current pct value unknown. Open or close roller blind before";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
        }
        if( $tpct > $pct ){
          $time = int(($max*($tpct-$pct))/10)/10;
          #-- 100% = open
          if($normal){
            $cmd = "?go=open&duration=".$time; 
          }else{ 
            $cmd = "?go=close&duration=".$time; 
          }  
        }else{
          $time = int(($max*($pct-$tpct))/10)/10;
          #-- 100% = open
          if($normal){
            $cmd = "?go=close&duration=".$time;       
          }else{
            $cmd = "?go=open&duration=".$time; 
          }   
        }
      }
      $hash->{MOVING} = 1;
      $hash->{DURATION} = $time;
      Shelly_updown($hash,$cmd);
    } 
  }  
  
  #-- configuration register
  if($cmd eq "config") {
    my $reg = $value;
    my ($chan,$val);
    if( int(@a) == 2 ){
      $chan = $a[0];
      $val = $a[1];
    }elsif( int(@a) == 1 ){
      $chan = 0;
      $val = $a[0];
    }else{
      my $msg = "Error: wrong number of parameters";
      Log3 $name,1,"[Shelly_Set] ".$msg;
      return $msg;
    }
    my $pre = "settings/";
    if( ($model eq "shelly2") && ($mode eq "roller") ){
      $pre .= "roller/$chan?";
    }else{
      $pre .= "relay/$chan?";
      $v = Shelly_configure($hash,$pre.$reg."=".$val);
    }
  }
  return undef;
}

########################################################################################
#
# Shelly_configure -  Configure Shelly device
#                 acts as callable program Shelly_configure($hash,$channel,$cmd)
#                 and as callback program  Shelly_configure($hash,$channel,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#
########################################################################################

 sub Shelly_configure {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( $net ne "connected" );

  my $model =  AttrVal($name,"model","");

  if ( $hash && !$err && !$data ){
     $url    = "http://".$hash->{TCPIP}."/".$cmd;
     Log3 $name, 5,"[Shelly_configure] called with only hash  => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ Shelly_configure($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    #Log3 $name, 1,"[Shelly_configure]  has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  Log3 $name, 5,"[Shelly_configure] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    Log3 $name,1,"[Shelly_configure] has invalid JSON data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  #-- isolate register name
  my $reg = substr($cmd,index($cmd,"?")+1);
  my $val = $jhash->{$reg};
  readingsSingleUpdate($hash,"config",$reg."=".$val,1);
  
  return undef;
}

########################################################################################
#
# Shelly_status - Retrieve data from device
#                 acts as callable program Shelly_status($hash)
#                 and as callback program  Shelly_status($hash,$err,$data)
# 
# Parameter hash
#
########################################################################################

 sub Shelly_status {
  my ($hash, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
    
  if ( $hash && !$err && !$data ){
     $url    = "http://".$hash->{TCPIP}."/status";
     Log3 $name, 5,"[Shelly_status] called with only hash  => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ Shelly_status($hash,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[Shelly_status]  has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    readingsSingleUpdate($hash,"network","not connected",1);
    #-- cyclic update nevertheless
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 1)
      if( $hash->{INTERVAL} ne "0" );
    return $err;
  }
 
  Log3 $name, 5,"[Shelly_status] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    Log3 $name,1,"[Shelly_status] invalid JSON data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $model =  AttrVal($name,"model","shelly2");
  my $mode  =  AttrVal($name,"mode","relay");
  
  my $channels = $shelly_models{$model}[0];
  my $rollers  = $shelly_models{$model}[1];
  my $meters   = $shelly_models{$model}[2];
  my ($subs,$ison,$overpower,$power,$rstate,$rpower,$rstopreason,$rlastdir);
  
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,"state","OK");
  readingsBulkUpdateIfChanged($hash,"network","connected",1);
  
  #-- we have a Shelly 1, Shelly 4, Shelly 2  or ShellyPlug switch type device
  if( ($model eq "shelly1") || ($model eq "shellyplug") || ($model eq "shelly4") || (($model eq "shelly2") && ($mode eq "relay")) ){
    for( my $i=0;$i<$channels;$i++){
      $subs = (($channels == 1) ? "" : "_".$i);
      $ison       = $jhash->{'relays'}[$i]{'ison'};
      $ison =~ s/0/off/;
      $ison =~ s/1/on/;
      $overpower = $jhash->{'relays'}[$i]{'overpower'};
      
      readingsBulkUpdateIfChanged($hash,"relay".$subs,$ison);
      readingsBulkUpdateIfChanged($hash,"overpower".$subs,$overpower);
    }
    for( my $i=0;$i<$meters;$i++){
      $subs = ($meters == 1) ? "" : "_".$i;
      $power       = $jhash->{'meters'}[$i]{'power'};
      readingsBulkUpdateIfChanged($hash,"power".$subs,$power);
    }
    
  #-- we have a Shelly 2 roller type device
  }elsif( ($model eq "shelly2") && ($mode eq "roller") ){ 
   #-- reset blocking due to existing movement
    $hash->{MOVING} = 0;
    $hash->{DURATION} = 0;
    for( my $i=0;$i<$rollers;$i++){
      $subs = ($rollers == 1) ? "" : "_".$i;
      $rstate       = $jhash->{'rollers'}[$i]{'state'};
      $rstate =~ s/close/closed/;
      $rpower = $jhash->{'rollers'}[$i]{'power'};
      $rstopreason = $jhash->{'rollers'}[$i]{'stop_reason'};
      $rlastdir = $jhash->{'rollers'}[$i]{'last_direction'};
      $rlastdir =~ s/close/down/;
      $rlastdir =~ s/open/up/;
      
      my $pct;
      #-- renormalize position
      my $normal = (AttrVal($name,"pct100","open") eq "open");
      if( $rstate eq "open" ){
        #-- 100% = open in case normal
        $pct = $normal?100:0;
      }elsif( $rstate eq "closed" ){
        #-- 100% = open in case normal
        $pct = $normal?0:100;
      }else{
       $pct = ReadingsVal($name,"pct",undef);
       $pct = "unknown"
         if( !defined($pct) );
      }
      
      #-- just in case we have leftover readings from relay devices
      #fhem("deletereading ".$name." channel.*");
      #fhem("deletereading ".$name." overpower.*");
      
      readingsBulkUpdateIfChanged($hash,"position".$subs,$rstate);
      readingsBulkUpdateIfChanged($hash,"power".$subs,$rpower);
      readingsBulkUpdateIfChanged($hash,"stop_reason".$subs,$rstopreason);
      readingsBulkUpdateIfChanged($hash,"last_dir".$subs,$rlastdir);
      readingsBulkUpdateIfChanged($hash,"pct".$subs,$pct);
     }
  }
  #-- common to all Shelly models
  my $hasupdate = $jhash->{'update'}{'has_update'};
  my $firmware  = $jhash->{'update'}{'old_version'};
  $firmware     =~ /.*\/(.*)\@.*/;
  $firmware     = $1; 
  if( $hasupdate ){
     my $newfw  = $jhash->{'update'}{'new_version'};
     $newfw     =~ /.*\/(.*)\@.*/;
     $newfw     = $1; 
     $firmware .= "(update needed to $newfw)";
  }
  readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
  
  my $hascloud = $jhash->{'cloud'}{'enabled'};
  if( $hascloud ){
    my $hasconn  = ($jhash->{'cloud'}{'connected'}) ? "connected" : "not connected";
    readingsBulkUpdateIfChanged($hash,"cloud","enabled($hasconn)");  
  }else{
    readingsBulkUpdateIfChanged($hash,"cloud","disabled");  
  }
  
  readingsEndUpdate($hash,1);
  
  #-- cyclic update
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 1)
    if( $hash->{INTERVAL} ne "0" );
  
  return undef;
}

########################################################################################
#
# Shelly_updown - Move rollere blind
#                 acts as callable program Shelly_updown($hash,$cmd)
#                 and as callback program  Shelly_updown($hash,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#
########################################################################################

 sub Shelly_updown {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( $net ne "connected" );
  
  my $model =  AttrVal($name,"model","");
  
  #-- empty cmd parameter
  $cmd = ""
    if( !defined($cmd) );
    
  if ( $hash && !$err && !$data ){
     $url    = "http://".$hash->{TCPIP}."/roller/0".$cmd;
     Log3 $name, 5,"[Shelly_updown] called with only hash  => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ Shelly_updown($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    #Log3 $name, 1,"[Shelly_updown]  has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  Log3 $name, 5,"[Shelly_updown] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model eq "shelly2") && ($data =~ /Device mode is not roller!/) ){
      Log3 $name,1,"[Shelly_updown] Device $name is not in roller mode";
      readingsSingleUpdate($hash,"state","Error",1);
      return
    }else{
      Log3 $name,1,"[Shelly_updown] has invalid JSON data";
      readingsSingleUpdate($hash,"state","Error",1);
      return;
    }
  }
  
  my ($rstate,$rpower,$rstopreason,$rlastdir,$pct,$normal,$pctopen,$pctclose);
  
  #-- immediately after moving blind
  if( $cmd ne ""){
    $rstate  = "moving";
    $pct     = ReadingsVal($name,"pct",undef);
    $normal  = (AttrVal($name,"pct100","open") eq "open");
    $pctopen = ($normal && ($pct == 100)) || (!$normal && ($pct == 0));
    $pctclose= ($normal && ($pct == 0)) || (!$normal && ($pct == 100));
    #-- timer command
    if( index($cmd,"&") ne "-1"){
      my $max = AttrVal($name,"maxtime",undef);  
      my $dir = substr($cmd,4,index($cmd,"&")-4);
      my $dur = substr($cmd,index($cmd,"&")+10);
      if( (!defined($pct) && ($dir eq "close")) || $pctopen ){
        #-- 100% = open
        if( $normal ){
          $pct = 100-int((100*$dur)/$max);
        }else{
          $pct = int((100*$dur)/$max);
        }
      }elsif( $dir eq "close" ){
        #-- 100% = open
        if( $normal ){
          $pct = $pct-int((100*$dur)/$max);
        }else{
          $pct = $pct+int((100*$dur)/$max);
        }     
      }elsif( (!defined($pct) && ($dir eq "open")) || $pctclose ){
        #-- 100% = open
        if( $normal ){
          $pct = int((100*$dur)/$max);
        }else{
          $pct = 100-int((100*$dur)/$max);
        }
      }elsif( $dir eq "open" ){
        #-- 100% = open
        if( $normal ){
          $pct = $pct+int((100*$dur)/$max);
        }else{         
          $pct = $pct-int((100*$dur)/$max);
        }
      }     
    }
    $pct = 0
      if( $pct < 0);
    $pct = 100
      if( $pct > 100);
      
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","OK");
    readingsBulkUpdate($hash,"position",$rstate);
    readingsBulkUpdate($hash,"pct",$pct);
    readingsEndUpdate($hash,1);
    #-- Call us in 1 second again.
    InternalTimer(gettimeofday()+ 1, "Shelly_updown", $hash,0);
  #--after 1 second
  }else{
    $rstate = "moving";
    $rpower = $jhash->{'power'};
    $rstopreason = $jhash->{'stop_reason'};
    $rlastdir = $jhash->{'last_direction'};
    $rlastdir =~ s/close/down/;
    $rlastdir =~ s/open/up/;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","OK");
    readingsBulkUpdate($hash,"position",$rstate);
    readingsBulkUpdate($hash,"power",$rpower);
    readingsBulkUpdate($hash,"stop_reason",$rstopreason);
    readingsBulkUpdate($hash,"last_dir",$rlastdir);
    readingsEndUpdate($hash,1);
    #-- Call status after movement.
    InternalTimer(gettimeofday()+int($hash->{DURATION}+0.5), "Shelly_status", $hash,0);
  }
  return undef;
}

########################################################################################
#
# Shelly_onoff -  Switch Shelly relay
#                 acts as callable program Shelly_onoff($hash,$channel,$cmd)
#                 and as callback program  Shelly_onoff($hash,$channel,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#
########################################################################################

 sub Shelly_onoff {
  my ($hash, $channel, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( $net ne "connected" );
  
  my $model =  AttrVal($name,"model","");
    
  if ( $hash && !$err && !$data ){
     $url    = "http://".$hash->{TCPIP}."/relay/".$channel.$cmd;
     Log3 $name, 1,"[Shelly_onoff] called with only hash  => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ Shelly_onoff($hash,$channel,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    #Log3 $name, 1,"[Shelly_onoff]  has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  Log3 $name, 5,"[Shelly_onoff] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model eq "shelly2") && ($data =~ /Device mode is not relay!/) ){
      Log3 $name,1,"[Shelly_onoff] Device $name is not in relay mode";
      readingsSingleUpdate($hash,"state","Error",1);
      return
    }else{
      Log3 $name,1,"[Shelly_onoff] has invalid JSON data";
      readingsSingleUpdate($hash,"state","Error",1);
      return;
    }
  }
  
  my $ison        = $jhash->{'ison'};
  my $hastimer    = $jhash->{'has_timer'};
  my $overpower   = $jhash->{'overpower'};
  
  $ison =~ s/0/off/;
  $ison =~ s/1/on/;
  $cmd  =~ s/\?turn=//;
  
  #-- timer command
  if( index($cmd,"&") ne "-1"){
    $cmd = substr($cmd,0,index($cmd,"&"));
    if( $hastimer ne "1" ){
      Log3 $name,1,"[Shelly_onoff] returns with problem, timer not set";
    }
  }
  if( $ison ne $cmd ) {
    Log3 $name,1,"[Shelly_onoff] returns without success, cmd=$cmd but ison=$ison";
  }
  if( defined($overpower) && $overpower eq "1") {
    Log3 $name,1,"[Shelly_onoff] switched off automatically because of overpower signal";
  }
  #-- 
  my $subs = ($shelly_models{$model}[0] ==1) ? "" : "_".$channel;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","OK");
  readingsBulkUpdate($hash,"relay".$subs,$ison);
  readingsBulkUpdate($hash,"overpower".$subs,$overpower)
    if( $shelly_models{$model}[2] > 0);
  readingsEndUpdate($hash,1);
  
  #InternalTimer(gettimeofday()+ 1, "Shelly_meter", $hash,0)
  #  if( $shelly_models{$model}[2] > 0);
  #-- Call status after switch.
  InternalTimer(int(gettimeofday()+1.5), "Shelly_status", $hash,0);

  return undef;
}

########################################################################################
#
# Shelly_meter - Retrieve data from meter
#                 acts as callable program Shelly_meter($hash,$channel,cmd)
#                 and as callback program  Shelly_meter0($hash,$channel,$cmd,$err,$data)
# 
# Parameter hash, channel, cmd = command 
#
########################################################################################

 sub Shelly_meter {
  my ($hash, $channel, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( $net ne "connected" );
   
  my $model =  AttrVal($name,"model","");
    
  if ( $hash && !$err && !$data ){
     $url    = "http://".$hash->{TCPIP}."/meter/".$channel;
     Log3 $name, 5,"[Shelly_meter] called with only hash  => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ Shelly_meter($hash,$channel,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[Shelly_meter has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  Log3 $name, 5,"[Shelly_meter] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    Log3 $name,1,"[Shelly_meter] invalid JSON data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $power   = $jhash->{'power'};
  
  #-- 
  my $subs = ($shelly_models{$model}[2] ==1) ? "" : "_".$channel;

  readingsSingleUpdate($hash,"power".$subs,$power,1);
  return undef;
}

1;

=pod
=item device
=item summary to communicate with a Shelly switch/roller actuator
=begin html

<a name="Shelly"></a>
<ul>
        <p> FHEM module to communicate with a Shelly switch/roller actuator</p>
        <a name="Shellydefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Shelly &lt;IP address&gt;</code>
            <br />Defines the Shelly device. </p>
        Notes: <ul>
        <li>The attribute <code>model</code> <b>must</b> be set</li>
         <li>This module needs the JSON package</li>
         </ul>
        <a name="Shellyset"></a>
        <h4>Set</h4>  
        For Shelly all Shelly devices
        <ul>
        <li><a name="shelly_sconfig"></a>
                <code>set &lt;name&gt; config <registername> [&lt;channel&gt;] &lt;value&gt;</code>
                <br />set the value of a configuration register</li>
        </ul>
        For Shelly switching devices (mode=relay for model=shelly2, standard for all other models) 
        <ul>
            <li><a name="shelly_onoff"></a>
                <code>set &lt;name&gt; on|off &lt;channel&gt; </code>
                <br />switches channel &lt;channel&gt; on or off.</li>
            <li><a name="shelly_onofftimer"></a>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;channel&gt; &lt;time&gt;</code>
                <br />switches &lt;channel&gt; on or off for &lt;time&gt; seconds.</li>           
        </ul>
        <br/>For Shelly roller blind devices (mode=roller for model=shelly2)  
        <ul>
            <li><a name="shelly_updown"></a>
                <code>set &lt;name&gt; open|closed|stop </code>
                <br />drives the roller blind open, closed or to a stop.</li>      
            <li><a name="shelly_pct"></a>
                <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code>
                <br />drives the roller blind to a partially closed position (100=open, 0=closed)</li>      
        </ul>
        <a name="Shellyget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="shelly_config"></a>
                <code>get &lt;name&gt; config &lt;registername&gt; [$lt;channel&gt;]</code>
                <br />get the value of a configuration register and writes it in reading config</li>
            <li><a name="shelly_registers"></a>
                <code>get &lt;name&gt; registers</code>
                <br />displays the names of the configuration registers for this device</li>      
            <li><a name="shelly_status"></a>
                <code>get &lt;name&gt; status</code>
                <br />returns the current devices status.</li>
            <li><a name="shelly_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />display the version of the module</li>              
        </ul>
        <a name="Shellyattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="shelly_model"><code>attr &lt;name&gt; model shelly1|shelly2|shelly4|shellyplug </code></a>
                <br />type of the Shelly device</li>
            <li><a name="shelly_mode"><code>attr &lt;name&gt; mode relay|roller (only for model=shelly2)</code></a>
                <br />type of the Shelly device</li>
             <li><a name="shelly_interval">
                <code>&lt;interval&gt;</code>
                <br />Update interval for reading in seconds. The default is 60 seconds, a value of 0 disables the automatic update. </li>
        </ul>
        <br/>For Shelly switching devices (mode=relay for model=shelly2, standard for all other models) 
        <ul>
        <li><a name="shelly_defchannel"><code>attr &lt;name&gt; defchannel <integer> (only for model=shelly2|shelly4)</code></a>
                <br />for multi-channel switches: Which channel will be switched, if a simple on|off command is received without channel number</li>
        </ul>
        <br/>For Shelly roller blind devices (mode=roller for model=shelly2)
        <ul>
            <li><a name="shelly_maxtime"><code>attr &lt;name&gt; maxtime &lt;float&gt; </code></a>
                <br />time needed for a complete drive upward or downward</li>
            <li><a name="shelly_pct100"><code>attr &lt;name&gt; pct100 open|closed (default:open) </code></a>
                <br />is pct=100 open or closed ? </li>
        </ul>
        <br/>Standard attributes   
        <ul>
            <li><a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        </ul>
=end html
=begin html_DE

<h3>Shelly</h3>
<ul>
Absichtlich keine deutsche Dokumentation vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#Shelly">Shelly</a> 
</ul>
=end html_DE

=cut