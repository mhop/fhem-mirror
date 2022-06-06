########################################################################################
#
# DoorPi.pm
#
# FHEM module to communicate with a Raspberry Pi door station running DoorPi
# Prof. Dr. Peter A. Henning, 2016
# 
#  $Id: 70_DoorPi.pm 2016-05 - pahenning $
#
#  TODO: Link /xx weglassen beim letzten Call
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
use Test::JSON;

use vars qw{%attr %defs};

sub Log($$);

#-- globals on start
my $version = "2.0alpha10";

#-- these we may get on request
my %gets = (
  "config:noArg"    => "C",
  "history:noArg"   => "H",
  "version:noArg"   => "V"
);

#-- capabilities of doorpi instance for light and target
my ($lon,$loff,$don,$doff,$gtt,$son,$soff,$snon) = (0,0,0,0,0,0,0,0,0);

########################################################################################
#
# DoorPi_Initialize
#
# Parameter hash
#
########################################################################################

sub DoorPi_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}    = "DoorPi_Define";
  $hash->{UndefFn}  = "DoorPi_Undef";
  $hash->{AttrFn}   = "DoorPi_Attr";
  $hash->{GetFn}    = "DoorPi_Get";
  $hash->{SetFn}    = "DoorPi_Set";
  #$hash->{NotifyFn} = "DoorPi_Notify";
  $hash->{InitFn}   = "DoorPi_Init";

  $hash->{AttrList}= "verbose testjson ".
                     "language:de,en ringcmd ".
                     "doorbutton dooropencmd dooropendly doorlockcmd doorunlockcmd doorlockreading ".
                     "lightbutton lightoncmd lighttimercmd lightoffcmd ".
                     "snapshotbutton streambutton ".
                     "dashlightbutton iconpic iconaudio ".
                     "target0 target1 target2 target3 ".
                     $readingFnAttributes;
                     
  $hash->{FW_detailFn}  = "DoorPi_makeTable";
  $hash->{FW_summaryFn} = "DoorPi_makeShort";
}

########################################################################################
#
# DoorPi_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub DoorPi_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "[DoorPi] Define the IP address of DoorPi as a parameter"
    if(@a != 3);
  return "[DoorPi] Invalid IP address of DoorPi"
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
    
  @{$hash->{DATA}} = ();
  @{$hash->{HELPER}->{CMDS}} = ();
  $hash->{DELAYED} = "";
  
  $modules{DoorPi}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","initialized");
  readingsBulkUpdate($hash,"lockstate","Unknown");
  readingsBulkUpdate($hash,"door","Unknown");
  readingsEndUpdate($hash,1); 
     
  InternalTimer(gettimeofday() + 10, "DoorPi_GetConfig", $hash,1);
  InternalTimer(gettimeofday() + 15, "DoorPi_GetLockstate", $hash,1);
  InternalTimer(gettimeofday() + 20, "DoorPi_GetHistory", $hash,1);
  $init_done = $oid;
  
  return undef;
}

#######################################################################################
#
# DoorPi_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub DoorPi_Undef ($) {
  my ($hash) = @_;
  delete($modules{DoorPi}{defptr}{NAME});
  RemoveInternalTimer($hash);
  return undef;
}

#######################################################################################
#
# DoorPi_Attr - Set one attribute value
#
########################################################################################

sub DoorPi_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $main::defs{$name};
  my $ret;
  
  #if ( $do eq "set") {
  # 	ARGUMENT_HANDLER: {
  #       # TODO
  #       }
  #}
  return 
}
  
########################################################################################
#
# DoorPi_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub DoorPi_Get ($@) {
  my ($hash, @a) = @_;
  
  #-- check syntax
  return "[DoorPi_Get] needs exactly one parameter" if(@a != 2);
  my $name = $hash->{NAME};
  my $v;

  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $version";
  }  
  #-- current configuration
  if($a[1] eq "config") {
    $v = DoorPi_GetConfig($hash);
  #-- history
  }elsif($a[1] eq "history") {
    $v = DoorPi_GetHistory($hash);                                         
  } else {
    my $newkeys = join(" ", sort keys %gets);
    $newkeys    =~  s/:noArg//g
      if( $a[1] ne "?");
    return "[DoorPi_Get] with unknown argument $a[1], choose one of ".$newkeys;
  }
  
  if(defined($v)) {
     Log GetLogLevel($name,2), "[DoorPi_Get] $a[1] error $v";
     return "$a[0] $a[1] => Error $v";
  }
  return "$a[0] $a[1] => ok";
}
 
########################################################################################
#
# DoorPi_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub DoorPi_Set ($@) {
  my ($hash, @a) = @_;
  #-- if only hash as parameter, this is acting as timer callback
  if( !@a ){
    Log 5,"[DoorPi_Set] delayed action started with ".$hash->{DELAYED};
    #-- delayed switching off light
    if( $hash->{DELAYED} eq "light"){
      @a=($hash->{NAME},"light","off");
    #-- delayed door opening
    }elsif( $hash->{DELAYED} eq "door_time"){
      @a=($hash->{NAME},"door","open");
    }
    $hash->{DELAYED} = "";
  }
  my $name = shift @a;
  
  my ($newkeys,$key,$value,$v);

  #-- commands
  my $door     = AttrVal($name, "doorbutton", "door");
  my $doorsubs = "open,opened";
    $doorsubs .= ",locked"
    if(AttrVal($name, "doorlockcmd",undef));
  $doorsubs   .= ",unlocked"
    if(AttrVal($name, "doorunlockcmd",undef));
    
  my @tsubs   = ();
  for( my $i=0;$i<4;$i++ ){
    push(@tsubs,$i)
      if(AttrVal($name, "target$i",undef));
  }
  my $tsubs2  = join(',',@tsubs);
    
  my $light      = AttrVal($name, "lightbutton", "light");
  my $dashlight  = AttrVal($name, "dashlightbutton", "dashlight");
  my $snapshot   = AttrVal($name, "snapshotbutton", "snapshot");
  my $stream     = AttrVal($name, "streambutton", "stream");

  #-- for the selector: which values are possible
  if ($a[0] eq "?"){
    $newkeys = join(" ",@{ $hash->{HELPER}->{CMDS} });
    #Log3 $name, 1,"=====> newkeys before subs $newkeys";
    $newkeys =~ s/$door/$door:$doorsubs/;                 # FHEMWEB sugar
    $newkeys =~ s/,opened//;                              # FHEMWEB sugar
    $newkeys =~ s/\s$light/ $light:on,on-for-timer,off/;  # FHEMWEB sugar
    $newkeys =~ s/$dashlight/$dashlight:on,off/;          # FHEMWEB sugar
    $newkeys =~ s/$stream/$stream:on,off/;                # FHEMWEB sugar
    $newkeys =~ s/$snapshot/$snapshot:noArg/;             # FHEMWEB sugar
    $newkeys =~ s/button(\d\d?)/button$1:noArg/g;         # FHEMWEB sugar
    $newkeys =~ s/purge/purge:noArg/;                     # FHEMWEB sugar
    $newkeys =~ s/target/target:$tsubs2/;                 # FHEMWEB sugar
    #Log3 $name, 1,"=====> newkeys after subs $newkeys";
    return $newkeys;
  }
  
  $key   = shift @a;
  $value = shift @a; 
  #Log3 $name, 1,"[DoorPi_Set] called with key ".$key." and value ".$value;
  
  return "[DoorPi_Set] With unknown argument $key, choose one of " . join(" ", @{$hash->{HELPER}->{CMDS}})
    if ( !grep( /$key/, @{$hash->{HELPER}->{CMDS}} ) && ($key ne "call") && ($key ne "door") );

  #-- hidden command "call" to be used by DoorPi for communicating with this module
  if( $key eq "call" ){ 
    #Log3 $name,1,"[DoorPi] call $value received";
    #-- call init
    if( $value eq "init" ){
      DoorPi_GetConfig($hash);
      InternalTimer(gettimeofday()+10, "DoorPi_GetHistory", $hash,0);
    #-- alive
    }elsif( $value eq "alive" ){
      readingsSingleUpdate($hash,"state","alive",1);
      $hash->{DELAYED} = "";
      DoorPi_GetLockstate($hash);
    #-- sabotage
    }elsif( $value eq "sabotage" ){
    #-- wrong id
    }elsif( $value eq "wrongid" ){
    #-- movement
    }elsif( $value eq "movement" ){
    #-- call start
    }elsif( $value =~ "start.*" ){
      readingsSingleUpdate($hash,"call","started",1);
      my ($sec, $min, $hour, $day,$month,$year,$wday) = (localtime())[0,1,2,3,4,5,6]; 
      $year += 1900;
      my $monthn = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$month];
      $wday  = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")[$wday];
      my $timestamp = sprintf("%s, %2d %s %d %02d:%02d:%02d", $wday,$day,$monthn,$year,$hour, $min, $sec);
      unshift(@{ $hash->{DATA}}, ["",$timestamp,AttrVal($name, "target$value","unknown"),"active","--","xx","yy"] );
      #-- update web interface immediately
      DoorPi_inform($hash);
      #-- obtain last snapshot
      DoorPi_GetLastSnapshot($hash);       
      #--  and finally execute FHEM command
      fhem(AttrVal($name, "ringcmd",undef))
         if(AttrVal($name, "ringcmd",undef));
    #-- call end
    }elsif( $value =~ "end.*" ){
      DoorPi_GetHistory($hash);
      InternalTimer(gettimeofday()+5, "DoorPi_inform", $hash,0);
      readingsSingleUpdate($hash,"call","ended",1);
      readingsSingleUpdate($hash,"call_listed",int(@{ $hash->{DATA}}),1);
    #-- call rejected
    }elsif( $value eq "rejected" ){
      DoorPi_GetHistory($hash);
      InternalTimer(gettimeofday()+5, "DoorPi_inform", $hash,0);
      readingsSingleUpdate($hash,"call","rejected",1);
    #-- call dismissed
    }elsif( $value eq "dismissed" ){
      DoorPi_GetHistory($hash);
      InternalTimer(gettimeofday()+5, "DoorPi_inform", $hash,0);
      readingsSingleUpdate($hash,"call","dismissed",1);
    }else{
      Log3 $name, 1,"[DoorPi] unknown command set ... call $value";
    }   
  #-- target for the call
  }elsif( $key eq "target" ){
    if( $value =~ /[0123]/ ){
      if(AttrVal($name, "target$value",undef)){
        readingsSingleUpdate($hash,"call_target",AttrVal($name, "target$value",undef),1);
        DoorPi_Cmd($hash,"gettarget");
      }else{
        Log3 $name, 1,"[DoorPi_Set] Error: target$value attribute not set";
        return;
      }
    }else{
      Log3 $name, 1,"[DoorPi_Set] Error: attribute target$value does not exist";
      return;
    }
    
  #-- door commands
  }elsif( ($key eq "$door")||($key eq "door") ){
    DoorPi_Door($hash,$value,$a[0]);
    
  #-- snapshot
  }elsif( $key eq "$snapshot" ){
    $v=DoorPi_Cmd($hash,"snapshot");
    InternalTimer(gettimeofday()+3, "DoorPi_GetLastSnapshot", $hash,0);
  #-- video stream
  }elsif( $key eq "$stream" ){
    if( $value eq "on" ){
      $v=DoorPi_Cmd($hash,"streamon");
      readingsSingleUpdate($hash,$stream,"on",1);
    }elsif( $value eq "off" ){
      $v=DoorPi_Cmd($hash,"streamoff");
      readingsSingleUpdate($hash,$stream,"off",1);
    }
  #-- scene lighting
  }elsif( $key eq "$light" ){
    #my $light    = AttrVal($name, "lightbutton", "light");
    if( $value eq "on" ){
      $v=DoorPi_Cmd($hash,"lighton");
      if(AttrVal($name, "lightoncmd",undef)){
        fhem(AttrVal($name, "lightoncmd",undef));
      }
      readingsSingleUpdate($hash,$light,"on",1);
    }elsif( $value eq "off" ){
      $v=DoorPi_Cmd($hash,"lightoff");
      if(AttrVal($name, "lightoffcmd",undef)){
        fhem(AttrVal($name, "lightoffcmd",undef));
      }
      readingsSingleUpdate($hash,$light,"off",1);
    }elsif( $value eq "on-for-timer" ){
      $v=DoorPi_Cmd($hash,"lighton");
      if(AttrVal($name, "lightoncmd",undef)){
        fhem(AttrVal($name, "lightoncmd",undef));
      }
      readingsSingleUpdate($hash,$light,"on",1);
      #-- Intiate turning off light
      $hash->{DELAYED} = "light";
      InternalTimer(gettimeofday() + 60, "DoorPi_Set", $hash,1);
    }
  #-- dashboard lighting
  }elsif( $key eq "$dashlight" ){
    #my $dashlight    = AttrVal($name, "dashlightbutton", "dashlight");
    if( $value eq "on" ){
      $v=DoorPi_Cmd($hash,"dashlighton");
      readingsSingleUpdate($hash,$dashlight,"on",1);
    }elsif( $value eq "off" ){
      $v=DoorPi_Cmd($hash,"dashlightoff");
      readingsSingleUpdate($hash,$dashlight,"off",1);
    }
  }elsif( $key =~ /button(\d\d?)/){
     $v=DoorPi_Cmd($hash,$key);
  }elsif( $key eq "purge"){
     #-- command purge to Doorpi 
     DoorPi_Cmd($hash,"purge");
     #-- clearing of DB
     InternalTimer(gettimeofday()+5, "DoorPi_PurgeDB", $hash,0);
     #-- get new history
     InternalTimer(gettimeofday()+10, "DoorPi_GetHistory",$hash,0);
  }
  
  if(defined($v)) {
     Log GetLogLevel($name,2), "[DoorPi_Set] $key error $v";
     return "$key => Error $v";
  }
  return undef;
}

#######################################################################################
#
# DoorPi_Door - complicated sequence to perform locking and unlocking
#
# Parameter hash 
#
#######################################################################################

sub DoorPi_Door {

  my ($hash,$cmd,$param) = @_;
 
  my $fhemcmd;
  my $v;
  
  my $name      = $hash->{NAME};
  my $door      = AttrVal($name, "doorbutton", "door");
  my $lockstate = DoorPi_GetLockstate($hash);
  
  #-- "opened" => BRANCH 1.1: opening confirmation from DoorPi 
  if( ($cmd) && ($cmd eq "opened") ){
    Log3 $name, 1,"[DoorPi_Door 1.1] received 'door opened' confirmation from DoorPi";
    readingsSingleUpdate($hash,$door,"opened",1);
    
  #-- "open" => BRANCH 1.0: door opening from FHEM, forward to DoorPi 
  }elsif( (($cmd) && ($cmd eq "open")) || ((!$cmd) && ($hash->{DELAYED} =~ /^open.*/)) ){
    $hash->{DELAYED} = "";
    #-- doit
    $v=DoorPi_Cmd($hash,"dooropen");
    Log3 $name, 1,"[DoorPi_Door 1.0] sent 'dooropen' command to DoorPi";
    readingsSingleUpdate($hash,$door,"opened (pending)",0);
    #-- extra fhem command
    $fhemcmd = AttrVal($name, "dooropencmd",undef);
    fhem($fhemcmd)
      if($fhemcmd);
  
  #-- BRANCH 2: unlockandopen from DoorPi: door has to be unlocked if necessary
  }elsif( $cmd eq "unlockandopen" ){
    #-- unlocking the door now, delayed opening
    if( $lockstate =~ /^locked.*/ ){
      Log3 $name, 1,"[DoorPi_Door] BRANCH 2.1 cmd=$cmd lockstate=$lockstate";
      $fhemcmd=AttrVal($name, "doorunlockcmd",undef);
      #-- check for undefined doorunlockcmd
      if( !$fhemcmd ){
        Log3 $name,5,"[DoorPi_Door 2.1] 'unlockandopen' command from DoorPi, but no FHEM doorunlock command defined";
        return
      }
      #--doit
      $v=DoorPi_Cmd($hash,"doorunlocked"); 
      Log3 $name, 1,"[DoorPi_Door 2.1] sent 'doorunlocked' command to DoorPi";
      fhem($fhemcmd); 
      readingsSingleUpdate($hash,$door,"unlocked",1);
      readingsSingleUpdate($hash,"lockstate","unlocked (pending)",1);        
       
      my $dly=AttrVal($name, "dooropendly",7);
      #-- delay by fixed number of seconds. lockstate will change then !
      if( $dly =~ /\d+/ ){       
        $hash->{DELAYED} = "open_time";
        InternalTimer(gettimeofday() + $dly, "DoorPi_Door", $hash,0);
      #-- delay by event
      }else{
        $hash->{DELAYED} = "open_event";
        fhem(" define dooropendelay notify $dly set $name $door opened");   
      }
    #-- no unlocking, seems to be unlocked already
    }elsif ($lockstate =~ /^unlocked.*/){
      Log3 $name, 1,"[DoorPi_Door] BRANCH 2.2 cmd=$cmd lockstate=$lockstate";
      #-- doit
      $v=DoorPi_Cmd($hash,"dooropen");
      $v=DoorPi_Cmd($hash,"doorunlocked");
      Log3 $name, 1,"[DoorPi_Door 2.2] reset DoorPi to proper state and sent 'dooropen' command";       
      readingsSingleUpdate($hash,$door,"opened (pending)",1);
      #-- extra fhem command
      $fhemcmd = AttrVal($name, "dooropencmd",undef);
      fhem($fhemcmd)
        if($fhemcmd);      
    #-- error message 
    }else{
      Log3 $name, 1,"[DoorPi_Door 2.3] 'unlockandopen' command from DoorPi ignored, because current lockstate=$lockstate";
      return;
    }
   
  #-- BRANCH 3: softlock from DoorPi: door has to be locked if necessary
  }elsif( $cmd eq "softlock" ){  
    #-- ignoring because hardlock has been issued before
    if( $hash->{DELAYED} eq "hardlock" ){
      Log3 $name, 1,"[DoorPi_Door] BRANCH 3.2 cmd=$cmd lockstate=$lockstate";
      Log3 $name, 1,"[DoorPi_Door 3.2] 'softlock' command from DoorPi ignored, because following a hardlock";
      $hash->{DELAYED} = "";
    #-- locking the door now
    }elsif( $lockstate =~ /^unlocked.*/ ){
      Log3 $name, 1,"[DoorPi_Door] BRANCH 3.1 cmd=$cmd lockstate=$lockstate";
      $fhemcmd=AttrVal($name, "doorlockcmd",undef);
      #-- check for undefined doorlockcmd
      if( !$fhemcmd ){
        Log3 $name,5,"[DoorPi_Door 3.1] 'softlock' command from DoorPi, but no FHEM doorlock command defined";           
        return
      }
      #-- doit   
      $v=DoorPi_Cmd($hash,"doorlocked");
      Log3 $name, 1,"[DoorPi_Door 3.1] sent 'doorlocked' command to DoorPi";
      fhem($fhemcmd); 
      readingsSingleUpdate($hash,$door,"locked",1);
      readingsSingleUpdate($hash,"lockstate","locked (pending)",1);
    #-- error message 
    }else{
      Log3 $name, 1,"[DoorPi_Door 3.2] 'softlock' command from DoorPi ignored, because current lockstate=$lockstate";
      return;
    }
       
  #-- BRANCH 4.1: unlocked command from FHEM
  }elsif( $cmd eq "unlocked" ){
    Log3 $name, 1,"[DoorPi_Door] BRANCH 4.1 cmd=$cmd lockstate=$lockstate";
    #-- careful here - 
    #   a third parameter indicates that the door is already unlocked
    #   because the command has been issued by the lock itself
    $fhemcmd=AttrVal($name, "doorunlockcmd",undef);
    #-- check for undefined doorunlockcmd    
    if( !$fhemcmd ){
      Log3 $name,5,"[DoorPi_Door 4.1] 'unlocked' command from FHEM, but no FHEM doorunlock command defined";           
      return
    }
    #-- doit
    $v=DoorPi_Cmd($hash,"doorunlocked");
    Log3 $name, 1,"[DoorPi_Door 4.1] sent 'doorunlocked' command to DoorPi";
    if( !$param ){
      fhem($fhemcmd); 
    }else{
       Log3 $name, 1,"[DoorPi_Door 4.1] 'unlocked' command from FHEM ignored, because param=$param";
    }
    readingsSingleUpdate($hash,$door,"unlocked",1);
    readingsSingleUpdate($hash,"lockstate","unlocked (pending)",1)
    
  #-- BRANCH 4.2: locked command from FHEM
  }elsif( $cmd eq "locked" ){
    Log3 $name, 1,"[DoorPi_Door] BRANCH 4.2 cmd=$cmd lockstate=$lockstate";
    #-- careful here - 
    #   a third parameter indicates that the door is already unlocked
    #   because the command has been issued by the lock itself
    $fhemcmd=AttrVal($name, "doorlockcmd",undef);
    #-- check for undefined doorlockcmd    
    if( !$fhemcmd ){
      Log3 $name,5,"[DoorPi_Door 4.2] 'locked' command from FHEM, but no FHEM doorlock command defined";           
      return
    }
    #-- doit
    $v=DoorPi_Cmd($hash,"doorlocked");
    Log3 $name, 1,"[DoorPi_Door 4.2] sent 'doorlocked' command to DoorPi";
    if( !$param ){
      #--- 'softlock' will follow from DoorPi, needs to be ignored
      $hash->{DELAYED} = "hardlock";
      fhem($fhemcmd); 
    }else{
       Log3 $name, 1,"[DoorPi_Door 4.2] 'locked' command from FHEM ignored, because param=$param";
    }
    readingsSingleUpdate($hash,$door,"locked",1);
    readingsSingleUpdate($hash,"lockstate","locked (pending)",1)
  }else{
    Log3 $name, 1,"[DoorPi_Door] with invalid arguments $hash $cmd";
  }
}

#######################################################################################
#
# DoorPi_GetLockstate - determine the lockstate of the door
#
# Parameter hash 
#
#######################################################################################

sub DoorPi_GetLockstate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ret;
  
  my $dev = AttrVal($name,"doorlockreading",undef);
  if( !$dev ){
    $ret = "unknown(1)";
  }else{    
    my ($devn,$readn) = split(/:/,$dev,2);
    if( !$devn || !$readn ){
      $ret = "unknown(1)";
    }else{
      $ret = ReadingsVal($devn,$readn,"unknown(3)");
    }
  }
  if( $ret =~ /^locked.*/){
    DoorPi_Cmd($hash,"doorlocked");
  }elsif( $ret =~ /^unlocked.*/){
    DoorPi_Cmd($hash,"doorunlocked");
  } 
  readingsSingleUpdate($hash,"lockstate",$ret,1);
  return $ret;
}

#######################################################################################
#
# DoorPi_GetConfig - acts as callable program DoorPi_GetConfig($hash)
#                    and as callback program  DoorPi_GetConfig($hash,$err,$status)
#
# Parameter hash, err, status 
#
#######################################################################################

sub DoorPi_GetConfig {
  my ($hash,$err,$status) = @_;
  my $name = $hash->{NAME};
  my $url;
  
  #-- get configuration from doorpi
  if ( !$hash ){
    Log3 $name, 1,"[DoorPi_GetConfig] called without hash";
    return undef;
  }elsif ( $hash && !$err && !$status ){
    $url    = "http://".$hash->{TCPIP}."/status?module=config";
    #Log3 $name, 5,"[DoorPi_GetConfig] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback => sub($$$){ DoorPi_GetConfig($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[DoorPi_GetConfig] has error $err";
    readingsSingleUpdate($hash,"config",$err,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  #Log3 $name, 1,"[DoorPi_GetConfig] has obtained data";
 
  #-- test if this is valid JSON
  if( (AttrVal($name,"testjson",0)==1) and !is_valid_json($status) ){
    Log3 $name, 1,"[DoorPi_GetConfig] but data is invalid";
    readingsSingleUpdate($hash,"config","invalid data",0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $json  = JSON->new->utf8;
  my $jhash0 = $json->decode( $status );
  
  #-- decode config 
  my $keyboards = $jhash0->{"config"}->{"keyboards"};
  my $fskey;
  my $fscmds;

  foreach my $key (sort(keys %{$keyboards})) {
    $fskey = $key
      if( $keyboards->{$key} eq "filesystem");
  }
  
  if($fskey){
    Log3 $name, 1,"[DoorPi_GetConfig] virtual keyboard is defined as \"$fskey\"";
    $hash->{HELPER}->{vkeyboard}=$fskey;
    $fscmds = $jhash0->{"config"}->{$fskey."_InputPins"};
    
    my $door       = AttrVal($name, "doorbutton", "door");
    my $light      = AttrVal($name, "lightbutton", "light");
    my $dashlight  = AttrVal($name, "dashlightbutton", "dashlight");
    my $snapshot   = AttrVal($name, "snapshotbutton", "snapshot");
    my $stream     = AttrVal($name, "streambutton", "stream");
    
    #-- initialize command list
    @{$hash->{HELPER}->{CMDS}} = ();
      
    foreach my $key (sort(keys %{$fscmds})) {
      #-- check for door buttons
      if($key =~ /dooropen/){
        push(@{ $hash->{HELPER}->{CMDS}},"$door");
      }elsif($key =~ /doorlocked/){
        #no need to get these
      }elsif($key =~ /doorunlocked/){
        #no need to get these
      #-- check for stream buttons
      }elsif($key =~ /$stream(on)/){
        push(@{ $hash->{HELPER}->{CMDS}},"$stream");
        $son = 1;
      }elsif($key =~ /$stream(off)/){
        $soff = 1;
      
      #-- check for snapshot button
      }elsif($key =~ /$snapshot/){
        push(@{ $hash->{HELPER}->{CMDS}},"$snapshot");
        $snon = 1;

      #-- check for dashboard lighting buttons
      }elsif($key =~ /$dashlight(on)/){
        push(@{ $hash->{HELPER}->{CMDS}},"$dashlight");
        $don = 1;
      }elsif($key =~ /$dashlight(off)/){
        $doff = 1;
      
      #-- check for scene lighting buttons
      }elsif($key =~ /$light(on)/){
        push(@{ $hash->{HELPER}->{CMDS}},"$light");
        $lon = 1;
      }elsif($key =~ /$light(off)/){
        $loff = 1;
  
      #-- use target instead of gettarget
      }elsif($key =~ /gettarget/){
        if( !AttrVal($name,"target0",undef) && !AttrVal($name,"target1",undef) &&
            !AttrVal($name,"target2",undef) && !AttrVal($name,"target3",undef) ){
           Log3 $name, 1,"[DoorPi_GetConfig] Warning: No attribute named \"target[0|1|2|3]\" defined";
        } else {
          push(@{ $hash->{HELPER}->{CMDS}},"target");
          $gtt = 1;
        }
      #-- one of the possible other commands,
      }else{
        push(@{ $hash->{HELPER}->{CMDS}},$key)
      }
    }
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$stream."on\" defined"
      if( $son==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$stream."off\" defined"
      if( $soff==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$snapshot."\" defined"
      if( $snon==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$light."off\" defined"
      if( $loff==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$light."on\" defined"
      if( $lon==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$light."off\" defined"
      if( $loff==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$dashlight."on\" defined"
      if( $don==0 ); 
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No DoorPi InputPin named \"".$dashlight."off\" defined"
      if( $doff==0 ); 
    
  }else{
    Log3 $name, 1,"[DoorPi_GetConfig] Warning: No keyboard \"filesystem\" defined";
  };
  
  $hash->{HELPER}->{wwwpath} = $jhash0->{"config"}->{"DoorPiWeb"}->{"www"};
  
  #-- temporary way to reset the Arduino in the lock
  DoorPi_Cmd($hash,"doorlocked"); 
  DoorPi_Cmd($hash,"doorunlocked"); 
  $hash->{DELAYED} = "";
  
  #-- put into READINGS
  readingsSingleUpdate($hash,"state","initialized",1);
  readingsSingleUpdate($hash,"config","ok",1);
  return undef;
}

#######################################################################################
#
# DoorPi_LastSnapshot - acts as callable program DoorPi_GetLastSnapshot($hash)
#                       and as callback program  DoorPi_GetLastSnapshot($hash,$err,$status)
#
# Parameter hash, err, status 
#
#######################################################################################

sub DoorPi_GetLastSnapshot {
  my ($hash,$err,$status) = @_;
  my $name = $hash->{NAME};
  my $url;
  
  #-- get configuration from doorpi
  if ( !$hash ){
    Log3 $name, 1,"[DoorPi_GetLastSnapshot] called without hash";
    return undef;
  }elsif ( $hash && !$err && !$status ){
    $url    = "http://".$hash->{TCPIP}."/status?module=config";
    #Log3 $name, 1,"[DoorPi_GetLastSnapshot] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback => sub($$$){ DoorPi_GetLastSnapshot($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[DoorPi_GetLastSnapshot] has error $err";
    readingsSingleUpdate($hash,"snapshot",$err,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  Log3 $name, 5,"[DoorPi_GetLastSnapshot] has obtained data";
 
  #-- test if this is valid JSON
  if( (AttrVal($name,"testjson",0)==1) and !is_valid_json($status) ){
    Log3 $name, 1,"[DoorPi_GetLastSnapshot] but data is invalid";
    readingsSingleUpdate($hash,"snapshot","invalid data",0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $json  = JSON->new->utf8;
  my $jhash0 = $json->decode( $status );
  
  #-- decode config 
  my $DoorPi   = $jhash0->{"config"}->{"DoorPi"};
  my $lastsnap = $jhash0->{"config"}->{"DoorPi"}->{"last_snapshot"};
  $url = "http://".$hash->{TCPIP}."/";
  $lastsnap =~ s/\/home\/doorpi\/records\//$url/;
  
  Log3 $name, 5,"[DoorPi_GetLastSnapshot] returns $lastsnap";
   
  #-- put into READINGS
  readingsSingleUpdate($hash,"snapshot",$lastsnap,1);
  return undef;
}
 
#######################################################################################
#
# DoorPi_GetHistory - acts as callable program DoorPi_GetHistory($hash)
#                     and as callback program  DoorPi_GetHistory($hash,$err1,$status1)
#                     and as callback program  DoorPi_GetHistory($hash,$err1,$status1,$err2,$status2)
#
# Parameter hash
#
#######################################################################################

sub DoorPi_GetHistory {
  my ($hash,$err1,$status1,$err2,$status2) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state= $hash->{READINGS}{state}{VAL};
    if( ( $state ne "initialized") && ($state ne "alive") ){
    Log3 $name, 1,"[DoorPi_GetHistory] cannot be called, no connection";
    return
  }
  
  #-- obtain call history and snapshot history from doorpi
  if ( !$hash ){
    Log3 $name, 1,"[DoorPi_GetHistory] called without hash";
    return undef;
  }elsif ( $hash && !$err1 && !$status1 && !$err2 && !$status2 ){
    $url    = "http://".$hash->{TCPIP}."/status?module=history_event&name=OnCallStateChange&value=1000";
    #Log3 $name,5, "[DoorPi_GetHistory] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback => sub($$$){ DoorPi_GetHistory($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err1 && !$status1 && !$err2 && !$status2 ){
    Log3 $name, 1,"[DoorPi_GetHistory] has error $err1";
    readingsSingleUpdate($hash,"call_history",$err1,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return undef;
  }elsif ( $hash && !$err1 && $status1 && !$err2 && !$status2 ){
    $url    = "http://".$hash->{TCPIP}."/status?module=history_snapshot";
    #Log3 $name,5, "[DoorPi_GetHistory] called with hash and data from first call => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback => sub($$$){ DoorPi_GetHistory($hash,$err1,$status1,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && !$err1 && $status1 && $err2){
    Log3 $name, 1,"[DoorPi_GetHistory] has error2 $err2";
    readingsSingleUpdate($hash,"call_history",$err2,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return undef;
  }
  #Log3 $name, 1,"[DoorPi_GetHistory] has obtained data in two calls";

  #-- test if this is valid JSON
  if( AttrVal($name,"testjson",0)==1 ){
    if(!is_valid_json($status1) ){
      Log3 $name,1 ,"[DoorPi_GetHistory] but data from first call is invalid";
      readingsSingleUpdate($hash,"call_history","invalid data 1st call",0);
      readingsSingleUpdate($hash,"state","Error",1);
      return;
    }
    if( !is_valid_json($status2) ){
      Log3 $name, 1,"[DoorPi_GetHistory] but data from second call is invalid";
      readingsSingleUpdate($hash,"call_history","invalid data 2nd call",0);
      readingsSingleUpdate($hash,"state","Error",1);
      return;
    }
  }
  
  my $json  = JSON->new->utf8;
  my $jhash0 = $json->decode( $status1 );
  my $khash0 = $json->decode( $status2 );

  #-- decode call history
  if(ref($jhash0->{"history_event"}) ne 'ARRAY'){
     my $mga="Warning - has found an empty event history";
     Log3 $name,2,"[DoorPi_GetHistory] ".$mga;
     return $mga
  }
  if(ref($khash0->{"history_snapshot"}) ne 'ARRAY'){
     my $mga="Warning - has found an empty snapshot history";
     Log3 $name, 2,"[DoorPi_GetHistory] ".$mga;
     return $mga
  }
  my @history_event    = ($jhash0)?@{$jhash0->{"history_event"}}:();
  my @history_snapshot = ($khash0)?@{$khash0->{"history_snapshot"}}:();
  my $call = "";
  
  #-- clear list of calls
  @{$hash->{DATA}} = ();
  my ($event,$jhash1,$jhash2,$call_state,$call_state2,$callstart,$callend,$calletime,$calletarget,$callstime,$callstarget,$callsnap,$callrecord,$callstring);
  
  Log3 $name,3,"[DoorPi_GetHistory] found ".int(@history_event)." events";
  
  #-- going backward through the calls
  my $i=0;
  if( int(@history_event) > 0 ){
  do{ 
     $event = $history_event[$i];
     $calletime   = $event->{"start_time"};
     $status1 = $event->{"additional_infos"};
     #-- workaround for bug in DoorPi
     $status1 =~ tr/'/"/;
     $jhash1 = from_json( $status1 );
     $call_state  = $jhash1->{"call_state"};
     $calletarget    = $jhash1->{"remote_uri"};
     my @call_states = ();
     push(@call_states,$call_state);

     #-- no active call processed and state of call = 18 - or ended = 13
     if( ($call eq "")  && (($call_state == 18)||($call_state == 13)) ){
        $call        = "active";
        my $j = 1;
        #-- check previous max. 5 events
        do {
           $status2 = $history_event[$i+$j]->{"additional_infos"};
           if( $status2 ){
              #-- workaround for bug in DoorPi
              $status2 =~ tr/'/"/;
              $jhash2 = from_json( $status2 );
              $call_state2 = $jhash2->{"call_state"};
              if( $call_state2 < 18 ){
                 push( @call_states,$call_state2); 
                 $callstime   = $history_event[$i+$j]->{"start_time"};
                 $callstarget = $jhash2->{"remote_uri"};
              }
           }
           $j++;
        } until( ($j > 5) || ($call_state2 == 18) || ($i+$j >= int(@history_event))  );
        
        my $call_pattern = join("-",@call_states);
        #Log3 $name, 1,"[DoorPi_GetHistory] Pattern for call is $call_pattern, proceeding with event no. ".($i+$j); 
        
        if( $call_pattern =~ /1(3|8)\-.*\-2/ ){
          $callend = "ok(2)";
        }elsif( $call_pattern =~ /1(3|8)\-.*\-3/ ){
          $callend = "ok(3)";
        }elsif( $call_pattern =~ /1(3|8)\-.*\-5/ ){
          $callend = "nok(5)";
        }else{
          $callend = "unknown";
        }
        
        if( $calletarget ne $callstarget){
           Log3 $name, 1,"[DoorPi_GetHistory] Found error in call history of target $calletarget";
        }
        
        #-- Format values
        my $state     = "";
        my ($sec, $min, $hour, $day,$month,$year,$wday) = (localtime($callstime))[0,1,2,3,4,5,6]; 
        $year += 1900;
        my $monthn = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$month];
        $wday  = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")[$wday];
        my $timestamp = sprintf("%s, %2d %s %d %02d:%02d:%02d", $wday,$day,$monthn,$year,$hour, $min, $sec);
        my $number    = $callstarget;
        $number =~ s/sip://;
        $number =~ s/\@.*//;
        my $result    = $callend;
        my $duration  = int(($calletime - $callstime)*10+0.5)/10;
             
        #-- workaround for buggy DoorPi
        my $record    = sprintf("%d-%02d-%02d_%02d-%02d-%02d.wav", $year,($month+1),$day,$hour, $min, $sec);

        #-- this is the snapshot file if taken at the same time
        my $snapshot  = sprintf("%d-%02d-%02d_%02d-%02d-%02d.jpg", $year,($month+1),$day,$hour, $min, $sec);
        
        #-- maybe we have to look at a second later ?
        ($sec, $min, $hour, $day,$month,$year,$wday) = (localtime($callstime+1))[0,1,2,3,4,5,6]; 
        $year += 1900;
        $monthn = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$month];
        $wday  = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")[$wday];
                
        #-- this is the filename without extension if taken a second later
        my $later = sprintf("%d-%02d-%02d_%02d-%02d-%02d", $year,($month+1),$day,$hour, $min, $sec);
        
        my $found = 0;
        for( my $i=0; $i<@history_snapshot; $i++){
          if( index($history_snapshot[$i],$snapshot) > -1){
             $found = 1;
             last;
          } 
        }   
        #-- if not, look for a file made a second later
        if( $found == 0 ){
           #-- this is the snapshot file if taken a second later
           $snapshot  = sprintf("%s.jpg", $later);
           #-- check if it is present in the list of snapshots
           for( my $i=0; $i<@history_snapshot; $i++){
              if( index($history_snapshot[$i],$snapshot) > -1){
                 $found = 1;
                 last;
              }
           }
           if( $found == 0 ){
              Log3 $name, 1,"[DoorPi_GetHistory] No snapshot found with $snapshot";
           }
        }
             
        $found = 0;
        for( my $i=0; $i<@history_snapshot; $i++){
          if( index($history_snapshot[$i],$record) > -1){
             $found = 1;
             last;
          }   
        }
        #-- if not, look for a file made a second later
        if( $found == 0 ){
           #-- this is the record file if taken a second later
           $record  = sprintf("%s.wav", $later);
           #-- check if it is present in the list of snapshots
           for( my $i=0; $i<@history_snapshot; $i++){
              if( index($history_snapshot[$i],$record) > -1){
                 $found = 1;
                 last;
              }
           }
           if( $found == 0 ){
              Log3 $name, 1,"[DoorPi_GetHistory] No record found with $record";
           }
        }
                
        #Log3 $name, 1,"$snapshot $record";
        
        #-- store this
        push(@{ $hash->{DATA}}, [$state,$timestamp,$number,$result,$duration,$snapshot,$record] );
        
        $i += $j-1;
        $i--
           if( $call_state2 == 18 );
        $call = "";
     }  
     $i++;
  } until ($i >= int(@history_event));
  
  }

  #--put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"call_listed",int(@{ $hash->{DATA}}));
  readingsBulkUpdate($hash,"call_history","ok");
  readingsEndUpdate($hash,1); 
  return undef;
}

########################################################################################
#
# DoorPi_Cmd - Write command to DoorPi.
#              acts as callable program DoorPi_Cmd($hash,$cmd)
#              and as callback program  DoorPi_GetHistory($hash,$cmd,$err,$data)
# 
# Parameter hash, cmd = command 
#
########################################################################################

 sub DoorPi_Cmd {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $url;
  my $state = $hash->{READINGS}{state}{VAL};
  
  if( ($state ne "initialized") && ($state ne "alive") ){
    Log3 $name, 1,"[DoorPi_Cmd] cannot be called, no connection";
    return
  }
    
  if ( $hash && !$data){
     $url    = "http://".$hash->{TCPIP}."/control/trigger_event?".
               "event_name=OnKeyPressed_".$hash->{HELPER}->{vkeyboard}.".".
               $cmd."&event_source=doorpi.keyboard.from_filesystem";
     #Log3 $name, 5,"[DoorPi_Cmd] called with only hash => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ DoorPi_Cmd($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[DoorPi_Cmd] has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  #Log3 $name, 1,"[DoorPi_Cmd] has obtained data $data";
 
  #-- test if this is valid JSON
  if( (AttrVal($name,"testjson",0)==1) and !is_valid_json($data) ){
    Log3 $name,1,"[DoorPi_Cmd] invalid data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
    
  my $json = JSON->new->utf8;
  my $jhash = $json->decode( $data );
  my $msg   = $jhash->{'message'};
  my $suc   = $jhash->{'success'};
  if( $suc ){
    return $msg;
  }
  return undef;
}

######################################################################################
#
# DoorPi_PurgeDB - acts as callable program DoorPi_PurgeDB($hash)
#                  and as callback program  DoorPi_PurgeDB($hash,$err,$status)
#
# Parameter hash, err, status 
#
#######################################################################################

sub DoorPi_PurgeDB {
  my ($hash,$err,$status) = @_;
  my $name = $hash->{NAME};
  my $url;
  
  #-- purge doorpi database
  if ( !$hash ){
    Log3 $name, 1,"[DoorPi_PurgeDB] called without hash";
    return undef;
  }elsif ( $hash && !$err && !$status){
    $url    = "http://".$hash->{TCPIP}."/status?module=history_event&name=purge&value=1.0";
    #Log3 $name, 5,"[DoorPi_PurgeDB] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url, 
      callback => sub($$$){ DoorPi_PurgeDB($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err ){
    Log3 $name, 1,"[DoorPi_PurgeDB] has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  #Log3 $name, 1,"[DoorPi_PurgeDB] has obtained data $status";
  #-- test if this is valid JSON
  if( (AttrVal($name,"testjson",0)==1) and !is_valid_json($status) ){
    Log3 $name, 1,"[DoorPi_PurgeDB] invalid data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
    
  my $json = JSON->new->utf8;
  my $jhash = $json->decode( $status );
  my $suc   = $jhash->{'history_event'};
  if( $suc eq "0" ){
    return "OK";
  }else{
    return undef;
  }
}

#######################################################################################
#
# DoorPi_makeShort 
#   
# FW_summaryFn handler for creating the html output in FHEMWEB
#
#######################################################################################

sub DoorPi_makeShort($$$$){
    my ($FW_wname, $devname, $room, $extPage) = @_;
    my $hash = $defs{$devname};
    
    my $name = $hash->{NAME};
    my $wwwpath = $hash->{HELPER}->{wwwpath};
    my $alias = AttrVal($hash->{NAME}, "alias", $hash->{NAME});
    my ($state,$timestamp,$number,$result,$duration,$snapshot,$record,$nrecord);
    
    my $old_locale = setlocale(LC_ALL);
    
    if(AttrVal($name, "language", "en") eq "de"){
        setlocale(LC_ALL, "de_DE.utf8");
    }else{
        setlocale(LC_ALL, "en_US.utf8");
    }
    
    my $ret = "";
    
    if(AttrVal($name, "language", "en") eq "de"){
        $ret .= "<div class=\"col2\">".int(@{$hash->{DATA}})."\&nbsp;Einträge</div>";
    }else{
        $ret .= "<div class=\"col2\">".int(@{$hash->{DATA}})."\&nbsp;calls</div>";
    }
    
    setlocale(LC_ALL, $old_locale);
    
    return ($ret);
}

#######################################################################################
#
# DoorPi_makeTable 
#  
# FW_detailFn handler for creating the html output in FHEMWEB
#
#######################################################################################

sub DoorPi_makeTable($$$$){
    my ($FW_wname, $devname, $room, $extPage) = @_;
    my $hash = $defs{$devname};
        
    return DoorPi_list($hash)
}

#######################################################################################
#
# DoorPi_inform 
#  
# Inform FHEMWEB
#
#######################################################################################

sub DoorPi_inform($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $alias = AttrVal($hash->{NAME}, "alias", $hash->{NAME});
      
  Log3 $name, 5, "[DoorPi_inform] inform all FHEMWEB clients";
  my $count = 0;
        
  foreach my $line (DoorPi_list($hash,1)){
    #Log3 $name, 1,"[Doorpi_Set] - informing $name";
    FW_directNotify($name, $line, 1);
    $count++;
  }

  my $ret;
  if(AttrVal($name, "language", "en") eq "de"){
      $ret .= "</td><td><div class=\"col2\">".int(@{$hash->{DATA}})."\&nbsp;Einträge</div>";
  }else{
      $ret .= "</td><td><div class=\"col2\">".int(@{$hash->{DATA}})."\&nbsp;calls</div>";
  }
  
  FW_directNotify($name,"",$ret);

  return undef;  
}    

#######################################################################################
#
# DoorPi_list 
#  
# Do the work for makeTable
#
#######################################################################################
    
sub DoorPi_list($;$){
    my ($hash, $to_json) = @_;
    
    return undef if( !$hash );
    
    my $name = $hash->{NAME};
    my $wwwpath = $hash->{HELPER}->{wwwpath};
    my $alias = AttrVal($hash->{NAME}, "alias", $hash->{NAME});
    my ($state,$timestamp,$number,$result,$duration,$snapshot,$record,$nrecord);
    
    my $create_readings = AttrVal($hash->{NAME}, "create-readings","0");
    
    my $td_style = 'style="padding-left:6px;padding-right:6px;"';
    my @json_output = ();
    my $line;
    
    my $old_locale = setlocale(LC_ALL);
    
    if(AttrVal($name, "language", "en") eq "de"){
        setlocale(LC_ALL, "de_DE.utf8");
    }else{
        setlocale(LC_ALL, "en_US.utf8");
    }
    
    my $iconpic = AttrVal($hash->{NAME}, "iconpic", undef);
    $iconpic = FW_makeImage($iconpic)
      if($iconpic);
    my $iconaudio = AttrVal($hash->{NAME}, "iconaudio", undef);
    $iconaudio = FW_makeImage($iconaudio)
      if($iconaudio);
    
    my $ret = "<table>";
    
    if(AttrVal($name, "no-heading", "0") eq "0" and defined($FW_ME) and defined($FW_subdir))
    {
        $ret .= '<tr><td>';
        $ret .= '<div class="devType"><a href="'.$FW_ME.$FW_subdir.'?detail='.$name.'">'.$alias.'</a>'.(IsDisabled($name) ? ' (disabled)' : '').'</div>' 
          unless($FW_webArgs{"detail"});
        $ret .= '</td></tr>';
    }
    
    $ret .= "<tr><td></td><td>";
    #-- div tag to support inform updates
    $ret .= '<div class="fhemWidget" informId="'.$name.'" cmd="" arg="doorpicalllist" dev="'.$name.'">';   
    if( exists($hash->{DATA}) ){
       $ret .= '<table class="block doorpicalllist">';
       
       my @order=("state","timestamp","number","result","duration","record");
    
       if(AttrVal($name, "language", "en") eq "de"){
          $state     = "Wer";
          $timestamp = "Zeitpunkt";
          $number    = "Rufnummer";
          $result    = "Ergebnis";
          $duration  = "Dauer";
          $record    = "Aufzeichnung";
       }else{
          $state     = "Who";
          $timestamp = "Timestamp";
          $number    = "Number";
          $result    = "Result";
          $duration  = "Duration";
          $record    = "Recording";
       }
       $ret .= '<tr align="center" class="doorpicalllist odd">';
       $ret .= '<td name="state" class="doorpicalllist" '.$td_style.'>'.$state.'</td>';
       $ret .= '<td name="timestamp" class="doorpicalllist" '.$td_style.'>'.$timestamp.'</td>';
       $ret .= '<td name="number" class="doorpicalllist" '.$td_style.'>'.$number.'</td>';
       $ret .= '<td name="result" class="doorpicalllist" '.$td_style.'>'.$result.'</td>';
       $ret .= '<td name="duration" class="doorpicalllist" '.$td_style.'>'.$duration.'</td>';
       $ret .= '<td name="record" class="doorpicalllist" '.$td_style.'>'.$record.'</td>';
       $ret .= '</tr>';
       
       #-- Loop through all entries in the list
       if( int(@{$hash->{DATA}}) > 0){
          my @list = @{$hash->{DATA}};
          for(my $index=0; $index<(@list); $index++){
             my @data   = @{$list[$index]};            
             $state     = $data[0];
             $timestamp = $data[1];
             $number    = $data[2];
             $result    = $data[3];
             $duration  = $data[4];
             $snapshot  = $data[5];
             $record    = $data[6];
           
             if(AttrVal($name, "language", "en") eq "de"){
                $result =~ s/busy/besetzt/;
                $result =~ s/no\sresponse/ohne Antw./;
             }
           
             if( $record ne ""){
               my $rs = $record;
               $rs =~ s/.*$wwwpath\///;
               $record  = '<a href="http://'.$hash->{TCPIP}.'/'.$record.'">';
               $record .= ($iconaudio) ? $iconaudio : $rs;
               $record .= '</a>';
             }
             
             if( $snapshot ne ""){
               $state  = '<a href="http://'.$hash->{TCPIP}.'/'.$snapshot.'">';
               $state .= ($iconpic) ? $iconpic : '<img src="http://'.$hash->{TCPIP}.'/'.$snapshot.'" width="40" height="30">';
               $state .= '</a>';
             }
             #-- assemble line
             my $line = { 
                        index => $index,
                        line => $index+1,
                        state =>  $state,
                        timestamp => $timestamp,
                        number => $number,
                        result => $result,
                        duration => $duration,
                        snapshot => $snapshot,
                        record => $record
                    };
           
             #-- assemble HTML output
             my @htmlret = ();
             push @htmlret, '<tr align="center" number="'.$index.'" class="doorpicalllist '.($index % 2 == 1 ? "odd" : "even").'">';
             foreach my $col (@order){
               push @htmlret, '<td name="'.$col.'" class="doorpicalllist" '.$td_style.'>'.$line->{$col}.'</td>';
             }
               
             $ret .= join("",@htmlret)."</tr>";   
           
             #-- assemble JSON output
             my @jsonret = ();
             push @jsonret, '"line":"'.$line->{index}.'"';
             foreach my $col (@order){
                my $val = $line->{$col};
                $val =~ s,",\\",g;
                push @jsonret, '"'.$col.'":"'.$val.'"';
             }
             push @json_output, "{".join(",",@jsonret)."}";
           #--- end loop through the list
           }
        }else{
            if(AttrVal($name, "language", "en") eq "de"){
              $ret .= "</td><td>Rufliste leer";
            }else{
              $ret .= "</td><td>Calllist empty";
            }
        } 
        $ret .= "</table></div>";
    }

    $ret .= "</td></tr></table>";    
    setlocale(LC_ALL, $old_locale);
    
    return ($to_json ? @json_output : $ret);
}


1;

=pod
=item device
=item summary to communicate with a Raspberry Pi door station running DoorPi
=begin html

 <a name="DoorPi"></a>
        <h3>DoorPi</h3>
        <p>FHEM module to communicate with a Raspberry Pi door station running DoorPi<br />
        <br /><h4>Example</h4><br />
        <p>
            <code>define DoorStation DoorPi 192.168.0.51</code>
            <br />
        </p><br />
        <a name="DoorPi_Define"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;DoorPi-Device&gt; DoorPi &lt;IP address&gt;</code> 
            <br /><br /> Define a DoorpiPi instance.<br /><br />
        </p>
        <ul>
          
            <li>
                <code>&lt;IP address&gt;</code>
                <br /> </li>
        </ul>
        <b>Note:</b> The default configuration for the module assumes that opening the door is done by DoorPi
        because it controls the local door opener, but locking and unlocking are handled by FHEM. Perl modules JSON and Test:JSON are needed.
         <br />
        <a name="DoorPi_Set"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="doorpi_door">
                    <code>set &lt;DoorPi-Device&gt; door open[|locked|unlocked] [&lt;string&gt;]</code></a><br />
                    Instead of <i>door</i>, one must use the value of the doorbutton attribute.
                    <br/> 
                    open: Activate the door opener in DoorPi, accompanied by an optional FHEM command
                    specified in the <i>dooropencmd</i> attribute.<br/>
                    locked/unlocked: Shown only if the if the Attributes doorlockcmd and doorunlockcmd are specified.
                    These commands are then used by FHEM to lock and unlock the door, furthermore this is communicated to DoorPi.
                    <br/>
                    If the third parameter is a nonempty string, this additional command is skipped. Can be useful, if the
                    locked/unlocked command comes from the door itself. 
                    <br/>
                    DoorPi will confirm reception of the dooropen command by calling <code>set &lt;DoorPi-Device&gt; door <b>opened</b></code>
                    </li>
            <li><a name="doorpi_snapshot">
                    <code>set &lt;DoorPi-Device&gt; snapshot </code></a><br />
                    Take a single snapshot.
                    Instead of <i>snapshot</i>, one must use the value of the snapshotbutton attribute</li>
            <li><a name="doorpi_stream">
                    <code>set &lt;DoorPi-Device&gt; stream on|off </code></a><br />
                    Start or stop a video stream
                    Instead of <i>stream</i>, one must use the value of the streambutton attribute</li>
            <li><a name="doorpi_target">
                    <code>set &lt;DoorPi-Device&gt; target 0|1|2|3 </code></a><br />
                    Set the call target number for DoorPi to the corresponding attribute value (see below)</li>
            <li><a name="doorpi_dashlight">
                    <code>set &lt;DoorPi-Device&gt; dashlight on|off </code></a><br />
                    Set the dashlight (illuminating the door station) on or off.
                    Instead of <i>dashlight</i>, one must use the value of the dashlightbutton attribute</li>
            <li><a name="doorpi_light">
                    <code>set &lt;DoorPi-Device&gt; light on|on-for-timer|off </code></a><br />
                    Set the scene light (illuminating the visitor) on, on for a minute or off.
                    Instead of <i>light</i>, one must use the value of the lightbutton attribute</li>
             <li><a name="doorpi_button">
                    <code>set &lt;DoorPi-Device&gt; <i>buttonDD</i>  </code></a><br />
                    Activate one of the virtual buttons specified in DoorPi.</li>
            <li><a name="doorpi_purge">
                    <code>set &lt;DoorPi-Device&gt; purge </code></a><br />
                    Clear all recordings and snapshots which are older than a day</li>
        </ul>
        <br />
        <a name="DoorPi_Get"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="doorpi_config">
                    <code>get &lt;DoorPi-Device&gt; config</code></a>
                <br /> Returns the current configuration of DoorPi </li>
            <li><a name="doorpi_history">
                    <code>get &lt;DoorPi-Device&gt; history</code></a>
                <br /> Returns the current call history of DoorPi </li>
            <li><a name="doorpi_version">
                    <code>get &lt;DoorPi-Device&gt; version</code></a>
                <br /> Returns the version number of the FHEM DoorPi module</li>
        </ul>
        <h4>Attributes</h4>
        <h5>Basic DoorPi actions</h5>
        <ul>
            <li><a name="doorpi_target2"><code>attr &lt;DoorPi-Device&gt; target[0|1|2|3]
                        &lt;string&gt;</code></a>
                <br />Call target numbers for different redirections. If none is set, redirection will not be offered.</li>
            <li><a name="doorpi_ringcmd"><code>attr &lt;DoorPi-Device&gt; ringcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command additionally executed for ringing action (no default)</li>
            <li><a name="doorpi_doorbutton"><code>attr &lt;DoorPi-Device&gt; doorbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for door action (default: door)</li>
            <li><a name="doorpi_dooropencmd"><code>attr &lt;DoorPi-Device&gt; dooropencmd
                        &lt;string&gt;</code></a>
                <br />FHEM command additionally executed for door opening action (no default)</li>
        </ul>
        <h5>Basic FHEM actions</h5>
        Door locking and unlocking is executed by FHEM only. After an unlocking action, the following 
        opening action will be delayed either by a fixed number of seconds or by waiting for an event.
        <ul>
            <li><a name="doorpi_doorlockreading"><code>attr &lt;DoorPi-Device&gt; doorlockreading
                        &lt;string&gt;:&lt;string&gt;</code></a>
                <br />combination of FHEM &lt;devicename&gt::&lt;reading&gt; parameters 
                        to determine the state of the door lock (no default)</li>
            <li><a name="doorpi_doorlockcmd"><code>attr &lt;DoorPi-Device&gt; doorlockcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command for door locking action (no default)</li>
            <li><a name="doorpi_doorunlockcmd"><code>attr &lt;DoorPi-Device&gt; doorunlockcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command for door unlocking action (no default)</li>
            <li><a name="doorpi_dooropendly"><code>attr &lt;DoorPi-Device&gt; dooropendly
                        &lt;number&gt;|&lt;string&gt;</code></a>
                <br />If number, delay of opening action after unlocking is given by &lt;number&gt; seconds;
                otherwise the string will be interpreted as a regular expression for an event that 
                has to be registered befor sending the door opening command from FHEM to DoorPi after an 
                unlocking action.</li>
        </ul>
        <h5>Advanced DoorPi actions</h5>
        These actions will only be possible if they are defined in the virtual DoorPi keyboard
        <ul>
            <li><a name="doorpi_snapshotbutton"><code>attr &lt;DoorPi-Device&gt; snapshotbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for snapshot action (default: snapshot)</li>
            <li><a name="doorpi_streambutton"><code>attr &lt;DoorPi-Device&gt; streambutton
                        &lt;string&gt;</code></a>                    
                <br />DoorPi name for video stream action (default: stream)</li>
            <li><a name="doorpi_lightbutton"><code>attr &lt;DoorPi-Device&gt; lightbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for light action (default: light)</li>
            <li><a name="doorpi_lightoncmd"><code>attr &lt;DoorPi-Device&gt; lightoncmd
                        &lt;string&gt;</code></a>
                <br />FHEM command additionally executed for "light on" action (no default)</li>
            <li><a name="doorpi_lightoffcmd"><code>attr &lt;DoorPi-Device&gt; lightoffcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command additionally executed for "light off" action (no default)</li>
            <li><a name="doorpi_dashlightbutton"><code>attr &lt;DoorPi-Device&gt; dashlightbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for dashlight action (default: dashlight)</li>
                   </ul>
        <h5>Visual attributes</h5>
        These actions will only be possible if they are defined in the virtual DoorPi keyboard
        <ul>
            <li><a name="doorpi_iconpic"><code>attr &lt;DoorPi-Device&gt; iconpic
                        &lt;string&gt;</code></a>
                <br />Icon to be used in overview instead of a (slow !) miniature picture</li>
            <li><a name="doorpi_iconaudio"><code>attr &lt;DoorPi-Device&gt; iconaudio70_PT8005.pm
                        &lt;string&gt;</code></a>
                <br />Icon to be used in overview instead of a verbal link to the audio recording</li>
        </ul>
        <h5>Other attributes</h5>
        <ul>
            <li><a name="#doorpi_testjson"><code>attr &lt;DoorPi-Device&gt; testjson
                        0(default)|1</code></a><br />set to 1 if returned json has to be checked</li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
         <h4>Necessary ingredients of the DoorPi configuration</h4>
         The following Events need to be defined for DoorPi in order to communicate with FHEM:
         <pre>
[EVENT_BeforeSipPhoneMakeCall]
10 = url_call:&lt;URL of FHEM&gt;/fhem?XHR=1&amp;cmd.&lt;DoorPi-Device&gt;=set &lt;DoorPi-Device&gt call start
20 = take_snapshot

[EVENT_OnCallStateDisconnect]
10 = url_call:&lt;URL of FHEM&gt;/fhem?XHR=1&amp;cmd.&lt;DoorPi-Device&gt;=set &lt;DoorPi-Device&gt call end 

[EVENT_OnCallStateDismissed]
10 = url_call:&lt;URL of FHEM&gt;/fhem?XHR=1&amp;cmd.&lt;DoorPi-Device&gt;=set &lt;DoorPi-Device&gt call dismissed

[EVENT_OnCallStateReject]
10 = url_call:&lt;URL of FHEM&gt;/fhem?XHR=1&amp;cmd.&lt;DoorPi-Device&gt;=set &lt;DoorPi-Device&gt call rejected
</pre>
Note: These calls can either be done directly in doorpi.ini, or collected in a separate shell script.
<p/>
DoorPi <b>must</b> have a virtual (= filesystem) keyboard
<pre>
[keyboards]
...
&lt;virtualkeyboardname&gt; = filesystem

[&lt;virtualkeyboardname&gt;_keyboard]
base_path_input = &lt;dome directory&gt;
base_path_output = &lt;some directory&gt;

[&lt;virtualkeyboardname&gt;_InputPins]
dooropen        = &lt;doorpi action opening the door&gt; 
doorlocked      = &lt;doorpi action if the door is locked by FHEM&gt; 
doorunlocked    = &lt;doorpi action if the door is unlocked by FHEM&gt; 
streamon        = &lt;doorpi action to switch on video stream&gt;
streamoff       = &lt;doorpi action to switch off video stream&gt;
lighton         = &lt;doorpi action to switch on scene light&gt;
lightoff        = &lt;doorpi action to switch off scene light&gt;
dashlighton     = &lt;doorpi action to switch on dashlight&gt;
dashlightoff    = &lt;doorpi action to switch off dashlight&gt;
gettarget       = &lt;doorpi action to acquire call target number&gt;
purge           = &lt;doorpi action to purge files and entries older than a day&gt;
... (optional buttons)
button1         = &lt;some doorpi action&gt;
... (further button definitions)
</pre>
=end html
=cut