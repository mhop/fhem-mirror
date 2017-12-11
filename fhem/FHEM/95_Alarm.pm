########################################################################################
#
# Alarm.pm
#
# FHEM module to set up a house alarm system with 8 different alarm levels
#
# Prof. Dr. Peter A. Henning
#
# $Id$
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
use vars qw(%defs);		        # FHEM device/button definitions
use vars qw(%intAt);		    # FHEM at definitions
use vars qw($FW_ME);

use JSON;      # imports encode_json, decode_json, to_json and from_json.

#########################
# Global variables
my $alarmlinkname   = "Alarms";    # link text
my $alarmhiddenroom = "AlarmRoom"; # hidden room
my $alarmpublicroom = "Alarm";     # public room
my $alarmno         = 8;
my $alarmversion    = "3.11";

my %alarm_transtable_EN = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Not OK",
    "start"             =>  "Start",
    "end"               =>  "End",
    "status"            =>  "Status",
    "notstarted"        =>  "Not started",
    "next"              =>  "Next",
    "arm"               =>  "Arm",
    "disarm"            =>  "Disarm",
    "armbutton"         =>  "Arming",
    "disarmbutton"      =>  "Disarming",
    "cancelbutton"      =>  "Canceling",
    "raise"             =>  "Raise",
    "wait"              =>  "Wait",
    "delay"             =>  "Delay",
    "cancel"            =>  "Cancel",
    "button"            =>  "Button",
    "level"             =>  "Level",
    "message"           =>  "Message",
    "messagepart"       =>  "Message Part",
    "notify"            =>  "Notify", 
    "notifyto"          =>  "Notify to", 
    "notifyby"          =>  "Notify by",
    "setby"             =>  "Set by",
    "regexp"            =>  "RegExp",
    "time"              =>  "Time",
    "description"       =>  "Description",
    "settings"          =>  "Settings",
    "sensors"           =>  "Sensors",
    "actors"            =>  "Actors",
    "action"            =>  "Action",
    "setaction"         =>  "Set Action",
    "unsetaction"       =>  "Unset Action",
    "testaction"        =>  "Test",
    "armaction"         =>  "Arm Action",
    "disarmaction"      =>  "Disarm Action",
    "waitaction"        =>  "Wait Action",
    "cancelaction"      =>  "Cancel Action",
    "canceled"          =>  "canceled by:",
    "alarm"             =>  "Alarm",
    "raised"            =>  "raised by:",
    "alarms"            =>  "Alarm System",
    "setparms"          =>  "Set Parameters",
    #--
    "state"             =>  "Security",
    "unlocked"          =>  "Unlocked",
    "locked"            =>  "Locked",
    "unsecured"         =>  "Not Secured",
    "secured"           =>  "Secured",             
    "protected"         =>  "Geschützt",
    "guarded"           =>  "Guarded"
    );
    
 my %alarm_transtable_DE = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Nicht OK",
    "start"             =>  "Start",
    "end"               =>  "Ende",
    "status"            =>  "Status",
    "notstarted"        =>  "Nicht gestartet",
    "next"              =>  "Nächste",
    "arm"               =>  "Schärfen",
    "disarm"            =>  "Entschärfen",
    "armbutton"         =>  "Schärfen",
    "disarmbutton"      =>  "Entschärfen",
    "cancelbutton"      =>  "Widerrufen",
    "raise"             =>  "Auslösen",
    "wait"              =>  "Warte",
    "delay"             =>  "Verzögerung",
    "cancel"            =>  "Widerruf",
    "button"            =>  "Button",
    "level"             =>  "Level",
    "message"           =>  "Nachricht",
    "messagepart"       =>  "Nachrichtenteil",
    "notify"            =>  "Auslösung", 
    "notifyto"          =>  "Wirkt auf", 
    "notifyby"          =>  "Auslösung durch",
    "setby"             =>  "Gesetzt durch",
    "regexp"            =>  "RegExp",
    "time"              =>  "Zeit",
    "description"       =>  "Beschreibung",
    "settings"          =>  "Einstellungen",
    "sensors"           =>  "Sensoren",
    "actors"            =>  "Aktoren",
    "action"            =>  "Wirkung",
    "setaction"         =>  "Aktion Setzen",
    "unsetaction"       =>  "Aktion Rücksetzen",
    "testaction"        =>  "Testen",
    "armaction"         =>  "Scharf-Aktion",
    "disarmaction"      =>  "Unscharf-Aktion",
    "waitaction"        =>  "Warte-Aktion",
    "cancelaction"      =>  "Widerruf-Aktion",
    "canceled"          =>  "widerrufen durch:",
    "alarm"             =>  "Alarm",
    "raised"            =>  "ausgelöst durch:",
    "alarms"            =>  "Alarmanlage",
    "setparms"          =>  "Parameter setzen",
    #--
    "state"             =>  "Sicherheit",
    "unlocked"          =>  "Unverschlossen",
    "locked"            =>  "Verschlossen",
    "unsecured"         =>  "Nicht Gesichert",
    "secured"           =>  "Gesichert",
    "protected"         =>  "Geschützt",
    "guarded"           =>  "Überwacht"
    );
    
my $alarm_tt;

#########################################################################################
#
# Alarm_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Alarm_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "Alarm_Define";
  $hash->{SetFn}   	   = "Alarm_Set";  
  $hash->{GetFn}       = "Alarm_Get";
  $hash->{UndefFn}     = "Alarm_Undef";   
  #$hash->{AttrFn}      = "Alarm_Attr";
  my $attst            = "lockstate:locked,unlocked testbutton:0,1 statedisplay:simple,color,table,none noicons iconmap disarmcolor ".
                         "armwaitcolor armcolor alarmcolor armdelay armwait armact disarmact cancelact";
  for( my $level=0;$level<$alarmno;$level++ ){
     $attst .=" level".$level."start level".$level."end level".$level."msg level".$level."xec level".$level."onact level".$level."offact ";
  }
  $hash->{AttrList}    = $attst;
  
  if( !defined($alarm_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $alarm_tt = \%alarm_transtable_DE;
    }else{
      $alarm_tt = \%alarm_transtable_EN;
    }
  }
  $alarmlinkname = $alarm_tt->{"alarms"};
  
  $data{FWEXT}{Alarmx}{LINK} = "?room=".$alarmhiddenroom;
  $data{FWEXT}{Alarmx}{NAME} = $alarmlinkname;	
  
  $data{FWEXT}{"/Alarm_widget"}{FUNC} = "Alarm_widget";
  $data{FWEXT}{"/Alarm_widget"}{FORKABLE} = 0;				  
	
  return undef;
}

#########################################################################################
#
# Alarm_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Alarm_Define ($$) {
  my ($hash, $def) = @_;
  my $now = time();
  my $name = $hash->{NAME}; 
  $hash->{VERSION} = $alarmversion;
  
  #-- readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $alarm_tt = \%alarm_transtable_DE;
  }else{
    $alarm_tt = \%alarm_transtable_EN;
  }
  
  readingsSingleUpdate( $hash, "state", "Initialized", 1 ); 
 
  $alarmhiddenroom           = defined($attr{$name}{"hiddenroom"})  ? $attr{$name}{"hiddenroom"} : $alarmhiddenroom;  
  $alarmpublicroom           = defined($attr{$name}{"publicroom"})  ? $attr{$name}{"publicroom"} : $alarmpublicroom; 
  $data{FWEXT}{Alarmx}{LINK} = "?room=".$alarmhiddenroom;
  $data{FWEXT}{Alarmx}{NAME} = $alarmlinkname;
  $attr{$name}{"room"}       = $alarmhiddenroom;
  
  #$data{FWEXT}{"/Alarm_widget"}{FUNC} = "Alarm_widget";
  #$data{FWEXT}{"/Alarm_widget"}{FORKABLE} = 0;	
  
  my $date = Alarm_restore($hash,0);
  #-- data seems to be ok, restore
  if( defined($date) ){
    Alarm_restore($hash,1);
    Log3 $name,1,"[Alarm_Define] data hash restored from save file with date $date";
  #-- intialization
  }else{
    for( my $i=0;$i<$alarmno;$i++){
      $hash->{DATA}{"armstate"}{"level".$i} = "disarmed";
    }
    Alarm_save($hash);
    Log3 $name,1,"[Alarm_Define] data hash is initialized";
  }
 
  $modules{Alarm}{defptr}{$name} = $hash;
  
  RemoveInternalTimer($hash);
  InternalTimer      ($now + 5, 'Alarm_CreateEntry', $hash, 0);

  return;
}

sub Alarm_transform($){
  my ($hash) = @_;

  Log 1,"[Alarm] transforming old data format into new one";

  my $md = 0;
  for( my $i=0;$i<$alarmno;$i++){ 
    if( defined(AttrVal($hash->{NAME},"level".$i."xec",undef)) ){
      $md = 1;
      $hash->{DATA}{"armstate"}{"level".$i} = AttrVal($hash->{NAME},"level".$i."xec","");
      fhem("deleteattr ".$hash->{NAME}." level".$i."xec");
    }
  }
  Alarm_save($hash)
    if( $md==1 );
}


#########################################################################################
#
# Alarm_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Alarm_Undef ($$) {
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  delete $data{FWEXT}{Alarmx};
  if (defined $defs{$name."_weblink"}) {
      FW_fC("delete ".$name."_weblink");
      Log3 $hash, 3, "[".$name. " V".$alarmversion."]"." Weblink ".$name."_weblink deleted";
  }
  
  return undef;
}

#########################################################################################
#
# Alarm_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
#########################################################################################

sub Alarm_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  
  my $hash = $defs{"$name"};
  
  #-- in any attribute redefinition readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $alarm_tt = \%alarm_transtable_DE;
  }else{
    $alarm_tt = \%alarm_transtable_EN;
  }
  return;  
}

#########################################################################################
#
# Alarm_CreateEntry - Puts the Alarm entry into the FHEM menu
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_CreateEntry($) {
   my ($hash) = @_;
 
   my $name = $hash->{NAME};
   if (!defined $defs{$name."_weblink"}) {
      FW_fC("define ".$name."_weblink weblink htmlCode {Alarm_Html(\"".$name."\")}");
      Log3 $hash, 3, "[".$name. " V".$alarmversion."]"." Weblink ".$name."_weblink created";
   }
   FW_fC("attr ".$name."_weblink room ".$alarmhiddenroom);

   foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     if (index($hr,$alarmhiddenroom) == -1){ 		
		    if ($hr eq "") {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$alarmhiddenroom);
		    }else {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$alarmhiddenroom);
		    }
		    Log3 $hash, 3, "[".$name. " V".$alarmversion."]"." Added hidden room '".$alarmhiddenroom."' to ".$defs{$dn}{NAME};
	     }	
      }
   }
   
   #-- recover state from stored readings
   readingsBeginUpdate($hash);
   for( my $level=0;$level<$alarmno;$level++ ){
      my $val = $hash->{DATA}{"armstate"}{"level".$level};
      readingsBulkUpdate( $hash, "level".$level, $val);
   }
   my $mga = Alarm_getstate($hash);
   readingsBulkUpdate( $hash, "state", $mga);
   readingsEndUpdate( $hash,1 );

}

#########################################################################################
#
# Alarm_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_Set($@) {
   my ( $hash, $name, $cmd, @args ) = @_;

   if ( $cmd =~ /^(cancel|arm|disarm)(ed)?$/ ) {
      return "[Alarm] Invalid argument to set $cmd, must be numeric"
         if ( $args[0] !~ /\d+/ );
      return "[Alarm] Invalid argument to set $cmd, must be 0 < arg < $alarmno"
         if ( ($args[0] >= $alarmno)||($args[0]<0) );
      if( $cmd =~ /^cancel(ed)?$/ ){     
         Alarm_Exec($name,$args[0],"web","button","cancel");
      }elsif ( $cmd =~ /^arm(ed)?$/ ) {
         Alarm_Arm($name,$args[0],"web","button","arm");
      }elsif ( $cmd =~ /^disarm(ed)?$/ ){
         Alarm_Arm($name,$args[0],"web","button","disarm");
      }else{
         return "[Alarm] Invalid argument set $cmd";
      }
	  return;
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^lock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "locked", 0 ); 
	  return;
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^unlock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "unlocked", 0 );
	  return;
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^save/ ) {
	return Alarm_save($hash);
	 
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^restore/ ) {
     return Alarm_restore($hash,1);
   
   } else {
     my $str =  join(",",(0..($alarmno-1)));
	 return "[Alarm] Unknown argument " . $cmd . ", choose one of canceled:$str armed:$str disarmed:$str locked:noArg unlocked:noArg save:noArg restore:noArg";
   }
}

#########################################################################################
#
# Alarm_Get - Implements the Get function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_Get($@) {
  my ($hash, @a) = @_;
  my $res = "";
  
  my $arg = (defined($a[1]) ? $a[1] : "");
  if ($arg eq "version") {
    return "Alarm.version => $alarmversion";
  } else {
    return "Unknown argument $arg choose one of version:noArg";
  }
}

#########################################################################################
#
# Alarm_getsettings - Helper function to assemble the alarm settings for a device
# 
# Parameter hash = hash of Alarm device
#           dev = name of device addressed
#
#########################################################################################

sub Alarm_getsettings($$$){

  my ($hash,$dev,$type) = @_;
  my $chg = 0;
  my @aval = split('\|',AttrVal($dev, "alarmSettings","|||0:00"),4);
  
  if( $type eq "Actor"){
  #-- position 0:set by, 1:set func, 2:unset func, 3:delay
    if( $aval[0] eq "" || $aval[1] eq "" ){
      Log3 $hash, 1, "[Alarm] Settings incomplete for alarmActor $dev";
    }
    #-- check delay time
    if( $aval[3] =~ /^\d+$/ ){
      if( $aval[3] > 3559 ){
        Log3 $hash, 1, "[Alarm] Delay time $aval[3] for alarmActor $dev to large as single number, maximum 3559 seconds";;
        $aval[3] = "59:59";
      }else{
        my $min = int($aval[3]/60);
        my $sec = $aval[3]%60;
        $aval[3] = sprintf("%02d:%02d",$min,$sec);
      }      
      $chg     = 1;
    }elsif( $aval[3] !~ /^(\d\d:)?\d\d:\d\d/ ){
      Log3 $hash, 1, "[Alarm] Delay time $aval[3] ill defined for alarmActor $dev";
      $aval[3] = "0:00";
      $chg     = 1;
    }
    
    if( $chg==1 ){
      CommandAttr(undef,$dev.' alarmSettings '.join('|',@aval));
    }
  }
  return @aval;
}

#########################################################################################
#
# Alarm_save
#
# Parameter hash = hash of the Alarm device
#
#########################################################################################

sub Alarm_save($) {
  my ($hash) = @_;
  $hash->{DATA}{"savedate"} = localtime(time);
  readingsSingleUpdate( $hash, "savedate", $hash->{DATA}{"savedate"}, 1 ); 
  my $json   = JSON->new->utf8;
  my $jhash0 = eval{ $json->encode( $hash->{DATA} ) };
  my $error  = FileWrite("AlarmFILE",$jhash0);
  #Log 1,"[Alarm_save] error=$error";
  return;
}
	 
#########################################################################################
#
# Alarm_restore
#
# Parameter hash = hash of the Alarm device
#
#########################################################################################

sub Alarm_restore($$) {
  my ($hash,$doit) = @_;
  my $name = $hash->{NAME};
  my ($error,$jhash0) = FileRead("AlarmFILE");
  if( defined($error) && $error ne "" ){
    Log3 $name,1,"[Alarm_restore] read error=$error";
    return undef;
  }
  my $json   = JSON->new->utf8;
  my $jhash1 = eval{ $json->decode( $jhash0 ) };
  my $date   = $jhash1->{"savedate"};
  #-- just for the first time, reading an old savefile
  $date = localtime(time)
    if( !defined($date));
  readingsSingleUpdate( $hash, "savedate", $date, 0 ); 
  if( $doit==1 ){
    $hash->{DATA}  = {%{$jhash1}}; 
    Log3 $name,5,"[Alarm_restore] Data hash restored from save file with date ".$date;
    return 1;
  }else{  
    return $date;
  }
}

#########################################################################################
#
# Alarm_Test - Test an actor
# 
# Parameter name  = name of the Alarm definition
#           cmd   =  
#
#########################################################################################

sub Alarm_Test($$){

   my ($name,$cmd) = @_;
   my $hash  = $defs{$name};
   
    $cmd =~ s/\$NAME/Gerät/g;
    $cmd =~ s/\$EVENT/Event/g;
    $cmd =~ s/\$SHORT/Kurznachricht/g;
    #for( my $i=1;$i<= int(@evtpart);$i++){
    #     $cmd =~ s/\$EVTPART$i/$evtpart[$i-1]/g;
    #}
    fhem($cmd); 
   
}

#########################################################################################
#
# Alarm_Exec - Execute the Alarm
# 
# Parameter name  = name of the Alarm definition
#           level = Alarm level 
#           dev   = name of the device calling the alarm
#           evt   = event calling the alarm
#           act   = action - "on" or "off"
#
#########################################################################################

sub Alarm_Exec($$$$$){

   my ($name,$level,$dev,$evt,$act) = @_;
   my $hash  = $defs{$name};
   my $xec   = $hash->{DATA}{"armstate"}{"level".$level}; 
   my $xac   = $hash->{READINGS}{"level".$level}{VAL};
   my $msg   = '';
   my $cmd;
   my $mga;
   my $dly;
   my @sta;
   
   #Log3 $hash,1,"[Alarm $level] Exec called with dev $dev evt $evt act $act]";
   return 
     if ($dev eq 'global');
   return 
     if (!defined($level));

   #-- raising the alarm 
   if( $act eq "on" ){
      #-- only if this level is armed and not yet active
      if( ($xec eq "armed") && ($xac eq "armed") ){ 
         #-- check for time
         my $start = AttrVal($name, "level".$level."start", 0);
         if(  index($start, '{') != -1){
           $start = eval($start);
         }
         my @st = split(':',$start);
         if( (int(@st)>3) || (int(@st)<2) || ($st[0] > 23) || ($st[0] < 0) || ($st[1] > 59) || ($st[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Cannot be executed due to wrong time spec $start for level".$level."start";
           return;
         }
         
         my $end   = AttrVal($name, "level".$level."end", 0);
         if(  index($end, '{') != -1){
           $end = eval($end);
         }
         my @et  = split(':',$end);
         if( (int(@et)>3) || (int(@et)<2) || ($et[0] > 23) || ($et[0] < 0) || ($et[1] > 59) || ($et[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Cannot be executed due to wrong time spec $end for level".$level."end";
           return;
         }
         
         my $stp = $st[0]*60+$st[1];
         my $etp = $et[0]*60+$et[1];
     
         my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime(time);
         my $ntp = $hour*60+$min;
     
         if( (($stp < $etp) && ($ntp <= $etp) && ($ntp >= $stp)) ||  (($stp > $etp) && (($ntp <= $etp) || ($ntp >= $stp))) ){  
            #-- raised by sensor (attribute values have been controlled in CreateNotifiers)
            @sta = split('\|',  AttrVal($dev, "alarmSettings", ""));
            if( $sta[2] ){
              $mga = $sta[2]." ".AttrVal($name, "level".$level."msg", 0);
              #-- replace some parts
              my @evtpart = split(" ",$evt);
              $mga =~ s/\$NAME/$dev/g;
              $mga =~ s/\$EVENT/$evt/g;
              for( my $i=1;$i<= int(@evtpart);$i++){
                 $mga =~ s/\$EVTPART$i/$evtpart[$i-1]/g;
              }
              #-- readings
              readingsSingleUpdate( $hash, "level".$level,$dev,1 );
              readingsSingleUpdate( $hash, "short", $mga, 1);
              $msg = Alarm_getstate($hash)." ".$mga;
              readingsSingleUpdate( $hash, "state", $msg, 1 );
              $msg = "[Alarm $level] raised from device $dev with event $evt";
              #-- calling actors AFTER state update
              $cmd = AttrVal($name, "level".$level."onact", 0);
              $cmd =~ s/\$NAME/$dev/g;
              $cmd =~ s/\$EVENT/$evt/g;
              $cmd =~ s/\$SHORT/$mga/g;
              for( my $i=1;$i<= int(@evtpart);$i++){
                 $cmd =~ s/\$EVTPART$i/$evtpart[$i-1]/g;
              }
              fhem($cmd); 
              Log3 $hash,3,$msg;
           }else{  
              $msg = "[Alarm $level] not raised, alarmSensor $dev has wrong settings";
              Log3 $hash,1,$msg;            
           }
         }else{
            $msg = "[Alarm $level] not raised, not in time slot";
            Log3 $hash,5,$msg;
         }
      }else{
         $msg = "[Alarm $level] not raised, not armed or already active";
         Log3 $hash,5,$msg;
      } 
   }elsif( ($act eq "off")||($act eq "cancel") ){
      #-- only if this level is active
      if( ($xac ne "armed")&&($xac ne "disarmed") ){
         #-- deleting all running ats
         $dly = sprintf("alarm%1ddly",$level);
         foreach my $d (sort keys %intAt ) {
            next if( $intAt{$d}{FN} ne "at_Exec" );
            $mga = $intAt{$d}{ARG}{NAME};
            next if( $mga !~ /$dly\d/);
            #Log3 $hash,1,"[Alarm] Killing delayed action $name";
            CommandDelete(undef,"$mga");
         }
         #-- replace some parts
         my @evtpart = split(" ",$evt);
         #-- calling actors BEFORE state update
         $cmd = AttrVal($name, "level".$level."offact", 0);
         $cmd =~ s/\$NAME/$dev/g;
         $cmd =~ s/\$EVENT/$evt/g;
         $cmd =~ s/\$SHORT/$mga/g;
         for( my $i=1;$i<= int(@evtpart);$i++){
           $cmd =~ s/\$EVTPART$i/$evtpart[$i-1]/g;
         }
         fhem($cmd);
         $cmd = AttrVal($name, "cancelact", 0);
         fhem($cmd)
           if( $cmd );
         #-- readings - arm status does not change
         readingsSingleUpdate( $hash, "level".$level,"canceled",1);
         readingsSingleUpdate( $hash, "level".$level,"armed",1);
         readingsSingleUpdate( $hash, "short", "", 0);
         $mga = Alarm_getstate($hash)." ".$alarm_tt->{"canceled"}." ".$dev;
         readingsSingleUpdate( $hash, "state", $mga, 1 );
         $msg = "[Alarm $level] canceled from device $dev";
         Log3 $hash,3,$msg;
     }
   }else{
     Log3 $hash,3,"[Alarm $level] Exec called with act=$act";
   }
   #return $msg;
}

#########################################################################################
#
# Alarm_Arm - Arm the Alarm
# 
# Parameter name  = name of the Alarm definition
#           level = Alarm level 
#           dev   = name of the device calling the alarm
#           evt   = Event of the device
#           act   = action - "armed" or "disarmed"
#
#########################################################################################

sub Alarm_Arm($$$$$){

   my ($name,$level,$dev,$evt,$act) = @_;
   my $hash  = $defs{$name};
   my $xec   = $hash->{DATA}{"armstate"}{"level".$level};
   my $xac   = $hash->{READINGS}{"level".$level}{VAL};
   my $msg   = '';
   my $mga;
   my $cmd;
         
   #-- arming the alarm
   if( ($act eq "arm") && ( $xac ne "armed")  ){
      my $xdl     = AttrVal($name, "armdelay", 0);
      my $cmdwait = AttrVal($name, "armwait", 0);
      my $cmdact  = AttrVal($name, "armact", 0);
      
      #-- immediate arming
      if( ($xdl eq '')||($xdl eq '0:00')||($xdl eq '00:00')||($evt eq "delay") ){
         #-- update state display
         $hash->{DATA}{"armstate"}{"level".$level} = "armed";
         readingsSingleUpdate( $hash, "level".$level,"armed",1 );
         readingsSingleUpdate( $hash, "state", Alarm_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 1 );
         #-- save new state
         Alarm_save($hash);      
         #--transform commands from fhem to perl level
         my @cmdactarr = split(/;/,$cmdact);
         my $cmdactf;
         if( int(@cmdactarr) == 1 ){
           fhem("$cmdact");
         }else{
             for(my $i=0;$i<int(@cmdactarr);$i++){
               fhem("$cmdactarr[$i]");
           }
         }
         $msg = "[Alarm $level] armed from alarmSensor $dev with event $evt"; 
         Log3 $hash,3,$msg; 
         
      } elsif( $xdl =~ /([0-9])?:([0-5][0-9])?/  ){
         #-- update state display
         $hash->{DATA}{"armstate"}{"level".$level} = "armed";
         readingsSingleUpdate( $hash, "level".$level,"armwait",1 );
         readingsSingleUpdate( $hash, "state", Alarm_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 1 );
         #-- save new state
         Alarm_save($hash);
         #--transform commands from fhem to perl level
         my @cmdactarr = split(/;/,$cmdact);
         my $cmdactf;
         if( int(@cmdactarr) == 1 ){
           $cmdactf   = "fhem(\"".$cmdact."\");;";
         }else{
           $cmdactf   = '';
             for(my $i=0;$i<int(@cmdactarr);$i++){
               $cmdactf.="fhem(\"".$cmdactarr[$i]."\");;";
           }
         }
         #-- compose commands TODO
         $cmd = sprintf("defmod alarm%1d.arm.dly at +00:%02d:%02d {Alarm_Arm(\"%s\",%1d,\"%s\",\"delay\",\"arm\");;%s}",
            $level,$1,$2,$name,$level,$dev,$cmdactf);
         $msg = "[Alarm $level] will be armed from alarmSensor $dev with event $evt, delay $xdl"; 
         #-- define new delayed arm
         fhem($cmd); 
         #-- execute armwait action
         fhem($cmdwait);
         Log3 $hash,1,$msg; 
      }else{
         $msg = "[Alarm $level] cannot be armed due to wrong delay timespec"; 
         Log3 $hash,1,$msg; 
      }
   #-- disarming implies canceling as well
   }elsif( ($act eq "disarm") &&  ($xec ne "disarmed")) {
      #-- delete stale delayed arm
      fhem('delete alarm'.$level.'.arm.dly' )
         if( defined $defs{'alarm'.$level.'.arm.dly'});
      $hash->{DATA}{"armstate"}{"level".$level} = "disarmed";
      Alarm_Exec($name,$level,"program","disarm","cancel");
      #-- update state display
      readingsSingleUpdate( $hash, "level".$level,"disarmed",1 );
      readingsSingleUpdate( $hash, "state", Alarm_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 1 );
      #-- save new state
      Alarm_save($hash);
      #--
      $msg = "[Alarm $level] disarmed from alarmSensor $dev with event $evt";
      $cmd = AttrVal($name, "disarmact", 0);
      fhem("define alarm".$level.".disarm.T at +00:00:03 ".$cmd)
        if( $cmd ); 
   }
   return $msg;
}

#########################################################################################
#
# Alarm_CreateNotifiers - Create the notifiers
# 
# Parameter name = name of the Alarm definition
#
#########################################################################################

sub Alarm_CreateNotifiers($){
  my ($name) = @_; 

  my $ret = "";
  my $res;
 
  my $hash = $defs{$name};
  #-- don't do anything if locked
  if( $hash->{READINGS}{"lockstate"}{VAL} ne "unlocked" ){
     Log3 $hash, 1, "[Alarm] State locked, cannot create new notifiers";
     return "State locked, cannot create new notifiers";
  }
  
  #-- temporary code: transferm from attributes to hash
  Alarm_transform($hash);
  
  for( my $level=0;$level<$alarmno;$level++ ){
  
     #-- delete old defs in any case
     fhem('delete alarm'.$level.'.on.N' )
        if( defined $defs{'alarm'.$level.'.on.N'});
     fhem('delete alarm'.$level.'.off.N' )
        if( defined $defs{'alarm'.$level.'.off.N'});
     fhem('delete alarm'.$level.'.arm.N' )
        if( defined $defs{'alarm'.$level.'.arm.N'});
     fhem('delete alarm'.$level.'.disarm.N' )
        if( defined $defs{'alarm'.$level.'.disarm.N'});
  
     my $start = AttrVal($name, "level".$level."start", 0);
     my @st;
     if( index($start,'{')!=-1 ){
        Log3 $hash,1,"[Alarm $level] perl function $start detected for level".$level."start, currently the function gives ".eval($start);
     }else{
        @st = split(':',($start ne '') ? $start :'0:00');
        if( (int(@st)!=2) || ($st[0] > 23) || ($st[0] < 0) || ($st[1] > 59) || ($st[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Will not be executed due to wrong time spec $start for level".$level."start";
           next;
        }
     }
     
     my $end   = AttrVal($name, "level".$level."end", 0);
     my @et;
     if( index($end,'{')!=-1 ){
        Log3 $hash,1,"[Alarm $level] perl function $end detected for level".$level."end, currently the function gives ".eval($end);
     }else{
        @et = split(':',($end ne '') ? $end :'23:59');
        if( (int(@et)!=2) || ($et[0] > 23) || ($et[0] < 0) || ($et[1] > 59) || ($et[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Will not be executed due to wrong time spec $end for level".$level."end";
           next;
        }
     }
    
     #-- now set up the command for cancel alarm, and contained in this loop all other notifiers as well
     my $cmd = '';
     foreach my $d (keys %defs ) {
        next if(IsIgnored($d));
        if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
           my @aval = split('\|',AttrVal($d, "alarmSettings",""));
           if( int(@aval) != 4){
              # Log3 $hash, 1, "[Alarm $level] Settings incomplete for sensor $d";
              next;
           }
           if( (index($aval[0],"alarm".$level) != -1) && ($aval[3] eq "off") ){
              $cmd .= '('.$aval[1].')|';
              #Log3 $hash,1,"[Alarm $level] Adding sensor $d to cancel notifier";
           }
        }   
     }
     if( $cmd eq '' ){
        Log3 $hash,1,"[Alarm $level] No \"Cancel\" device defined, level will be ignored";
     } else {
        $cmd  =  substr($cmd,0,length($cmd)-1);
        $cmd  = 'alarm'.$level.'.off.N notify '.$cmd;
        $cmd .= ' {main::Alarm_Exec("'.$name.'",'.$level.',"$NAME","$EVENT","off")}';
        CommandDefine(undef,$cmd);
        CommandAttr (undef,'alarm'.$level.'.off.N room '.$alarmpublicroom); 
        CommandAttr (undef,'alarm'.$level.'.off.N group alarmNotifier'); 
        Log3 $hash,5,"[Alarm $level] Created cancel notifier";    
     
        #-- now set up the command for raising alarm - only if cancel exists
        $cmd        = '';
        my $cmdarm   = "";
        my $cmddisarm = "";
        foreach my $d (sort keys %defs ) {
           next if(IsIgnored($d));
           if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
              my @aval = split('\|',AttrVal($d, "alarmSettings",""));
              if( int(@aval) != 4){
                 Log3 $hash, 5, "[Alarm $level] Settings incomplete for alarmSensor $d";
                 next;
              }
              if( index($aval[0],"alarm".$level) != -1){
                 if( $aval[3] eq "on" ){
                    $cmd .= '('.$aval[1].')|';
                    Log3 $hash,5,"[Alarm $level] Adding alarmSensor $d to raise notifier";
                 }elsif( $aval[3] eq "arm" ){
                    $cmdarm .= '('.$aval[1].')|';
                    Log3 $hash,5,"[Alarm $level] Adding alarmSensor $d to arm notifier";
                 }elsif( $aval[3] eq "disarm" ){
                    $cmddisarm .= '('.$aval[1].')|';
                    Log3 $hash,5,"[Alarm $level] Adding alarmSensor $d to disarm notifier";
                 }
              }
           }   
        }
        #-- raise notifier
        if( $cmd eq '' ){
           Log3 $hash,1,"[Alarm $level] No \"Raise\" device defined";
        } else {   
           $cmd  = substr($cmd,0,length($cmd)-1);
           $cmd  = 'alarm'.$level.'.on.N notify '.$cmd;
           $cmd .= ' {main::Alarm_Exec("'.$name.'",'.$level.',"$NAME","$EVENT","on")}';
           CommandDefine(undef,$cmd);
           CommandAttr (undef,'alarm'.$level.'.on.N room '.$alarmpublicroom); 
           CommandAttr (undef,'alarm'.$level.'.on.N group alarmNotifier'); 
           Log3 $hash,5,"[Alarm $level] Created raise notifier";
           
           #-- now set up the list of actors
           $cmd      = '';
           my $cmd2  = '';
           my $nonum = 0;
           foreach my $d (sort keys %defs ) {
              next if(IsIgnored($d));
              if( AttrVal($d, "alarmDevice","") eq "Actor" ) {
                 my @aval = Alarm_getsettings($hash,$d,"Actor");
                 if( int(@aval) != 4){
                   Log3 $hash, 5, "[Alarm $level] Settings incomplete for alarmActor $d";
                   next;
                 }
                 if( index($aval[0],"alarm".$level) != -1 ){
                    #-- activate without delay 
                    if(( $aval[3] eq "" )||($aval[3] eq "00:00")){
                       $cmd  .= $aval[1].';';
                    #-- activate with delay
                    } else {
                       $nonum++;
                       my @tarr = split(':',$aval[3]);
                       if( int(@tarr) == 2){
                         $cmd  .= sprintf('defmod alarm%1ddly%1d at +00:%02d:%02d %s;',$level,$nonum,$tarr[0],$tarr[1],$aval[1]);
                       }elsif( int(@tarr) == 3){
                         $cmd  .= sprintf('defmod alarm%1ddly%1d at +%02d:%02d:%02d %s;',$level,$nonum,$tarr[0],$tarr[1],$tarr[2],$aval[1]); 
                       }else{
                         Log3 $name,1,"[Alarm $level] Invalid delay specification for actor $d, skipped";
                         $cmd  .= $aval[1].';';  
                       }
                    }
                    $cmd2 .= $aval[2].';'
                      if( $aval[2] ne '' );
                    Log3 $hash,5,"[Alarm $level] Adding actor $d to action list";
                 }
              }   
           }
           if( $cmd ne '' ){
              CommandAttr(undef,$name.' level'.$level.'onact '.$cmd);
              CommandAttr(undef,$name.' level'.$level.'offact '.$cmd2);
              Log3 $hash,5,"[Alarm $level] Added on/off actors to $name";
           } else {
              Log3 $hash,5,"[Alarm $level] Adding on/off actors not possible";
           }
           #-- arm notifier - optional, but only in case the alarm may be raised
           if( $cmdarm ne '' ){
              $cmdarm  = substr($cmdarm,0,length($cmdarm)-1);
              $cmdarm  = 'alarm'.$level.'.arm.N notify '.$cmdarm;
              $cmdarm .= ' {main::Alarm_Arm("'.$name.'",'.$level.',"$NAME","$EVENT","arm")}';
              CommandDefine(undef,$cmdarm);
              CommandAttr (undef,'alarm'.$level.'.arm.N room '.$alarmpublicroom); 
              CommandAttr (undef,'alarm'.$level.'.arm.N group alarmNotifier'); 
              Log3 $hash,3,"[Alarm $level] Created arm notifier";
           }
           #-- disarm notifier - optional, but only in case the alarm may be raised
           if( $cmddisarm ne '' ){
              $cmddisarm  = substr($cmddisarm,0,length($cmddisarm)-1);
              $cmddisarm  = 'alarm'.$level.'.disarm.N notify '.$cmddisarm;
              $cmddisarm .= ' {main::Alarm_Arm("'.$name.'",'.$level.',"$NAME","$EVENT","disarm")}';
              CommandDefine(undef,$cmddisarm);
              CommandAttr (undef,'alarm'.$level.'.disarm.N room '.$alarmpublicroom); 
              CommandAttr (undef,'alarm'.$level.'.disarm.N group alarmNotifier'); 
              Log3 $hash,3,"[Alarm $level] Created disarm notifier";
           }
        }
     }
  }
  return "Created alarm notifiers";
}

#########################################################################################
#
# Alarm_getstate - Helper function to assemble a state display
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_getstate($) {
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  my $res = '';
  my $type = AttrVal($hash->{NAME},"statedisplay",0);
  my $val;
  #--------------------------
  if( $type eq "simple" ){
     for( my $level=0;$level<$alarmno;$level++ ){
        $val = $hash->{READINGS}{"level".$level}{VAL};
        if( $val eq "disarmed" ){
           $res .= '-';
        }elsif( $val eq "armwait" ){
           $res .= 'o';
        }elsif( $val eq "armed" ){
           $res .= 'O';
        }else{
           $res .= 'X';
        }
     }
  #--------------------------
  }else{
  
    my $dac  = AttrVal($name,"disarmcolor","lightgray");
    my $ac   = AttrVal($name,"armcolor","#53f3c7");
    my $awc  = AttrVal($name,"armwaitcolor","#ffe658"); 
    my $alc  = AttrVal($name,"alarmcolor","#fd5777"); 
 
    if( $type eq "color" ){
      $res = '<span style="color:'.$dac.'">';
      for( my $level=0;$level<$alarmno;$level++ ){
        $val = $hash->{READINGS}{"level".$level}{VAL};
        if( $val eq "disarmed" ){
           $res .= ' '.$level;
        }elsif( $val eq "armwait" ){
           $res .= ' <span style="width:1ex;font-weight:bold;color:'.$awc.'">'.$level.'</span>';
        }elsif( $val eq "armed" ){
           $res .= ' <span style="width:1ex;font-weight:bold;color:'.$ac.'">'.$level.'</span>';
        }else{
         $res .= ' <span style="width:1ex;font-weight:bold;color:'.$alc.'">'.$level.'</span>';
        }
      }
      $res.='</span>';
      #--------------------------
     }elsif( $type eq "table" ){
       $res = '<table><tr style="height:1ex">';
       for( my $level=0;$level<$alarmno;$level++ ){
         $val = $hash->{READINGS}{"level".$level}{VAL};
         if( $val eq "disarmed" ){
            $res .= '<td style="width:1ex;background-color:'.$dac.'"/>';
         }elsif( $val eq "armwait" ){
            $res .= '<td style="width:1ex;background-color:'.$awc.'"/>';
         }elsif( $val eq "armed" ){
            $res .= '<td style="width:1ex;background-color:'.$ac.'"/>';
         }else{
            $res .= '<td style="width:1ex;background-color:'.$alc.'"/>';
         }
      }
     $res.='</tr></table>';
    }
  }
  return $res;
}

#########################################################################################
#
# Alarm_widget - returns animated SVG-code for the Alarm page
# 
# Parameter name = name of the Alarm definition
#
#########################################################################################

sub Alarm_widget($){
  my ($arg) = @_;
  
  my $name   = $FW_webArgs{name};
  my $sizep  = $FW_webArgs{size};
  my $gstate  = ( $FW_webArgs{gstate} ? $FW_webArgs{gstate} : "disarmed");
  my $dstate  = ( $FW_webArgs{dstate} ? $FW_webArgs{dstate} : "--------");
  my $inline = 0;
  
  #-- no webarg, check direct parameter. TODO: order
  if( !defined($name) || $name eq "" ){
    if( $arg   =~ /^name=(\w*)&gstate=(.+)&dstate=(.+)&size=(\d+x\d+)/ ){
       $name   = $1;
       $gstate  = $2;
       $dstate  = $3;
       $sizep  = $4;
       $inline = 1;
    }
  }    
  
  Log 1,"[Alarm_widget] name=$name gstate=$gstate dstate=$dstate sizep=$sizep";
  
  $name      =~ s/'//g;
  my @size=split('x',($sizep ? $sizep : '60x80'));
  
  my ($fillcolor,$fillcolor2);
  my $dac  = AttrVal($name,"disarmcolor","lightgray");
  my $ac   = AttrVal($name,"armcolor","#53f3c7");
  my $awc  = AttrVal($name,"armwaitcolor","#ffe658"); 
  my $alc  = AttrVal($name,"alarmcolor","#fd5777"); 
  
  if($gstate eq "disarmed"){
    $fillcolor  = AttrVal($name,"disarmcolor",$dac);
    $fillcolor2 = "white";
  }elsif($gstate eq "armed"){
    $fillcolor  = AttrVal($name,"armcolor",$ac);
    $fillcolor2 = "white";
  }elsif($gstate eq "mixed"){
    $fillcolor  = AttrVal($name,"armwaitcolor",$awc); 
    $fillcolor2 = "white";
  }else{
    $fillcolor  = AttrVal($name,"alarmcolor",$alc); 
    $fillcolor2 = $fillcolor; 
  }
  
  my $hash = $defs{$name};
  my $id = $defs{$name}{NR};
  my $ret="";
  
  $ret  = "<svg viewBox=\"0 0 60 80\" preserveAspectRatio=\"xMidYMin slice\" width=\"100%\" style=\"padding-bottom: 92%; height: 1px; overflow: visible\">";
  $ret .= "<g id=\"alarmicon\" transform=\"translate(20,5) scale(1.5,1.5)\">".
          "<path class=\"alarmst_b\" id=\"alarmst_ib\" d=\"M 25 6 C 23.354545 6 22 7.3545455 22 9 L 22 10.365234 C 17.172775 11.551105 14.001117 15.612755 14.001953 21.0625 ".
          "L 14.001953 28.863281 C 14.001953 31.035281 12.718469 33.494563 11.980469 34.726562 L 10.167969 37.445312 C 9.9629687 37.751312 9.9431875 ".
          "38.147656 10.117188 38.472656 C 10.291188 38.797656 10.631 39 11 39 L 39 39 C 39.369 39 39.708813 38.797656 39.882812 38.472656 C 40.056813 ".
          "38.147656 40.037031 37.752313 39.832031 37.445312 L 38.044922 34.767578 C 36.668922 32.473578 36 30.587 36 29 L 36 21.199219 C 36 15.68167 ".
          "32.827303 11.569596 28 10.369141 L 28 9 C 28 7.3545455 26.645455 6 25 6 z M 25 8 C 25.554545 8 26 8.4454545 26 9 L 26 10.044922 C 25.671339 ".
          "10.019952 25.339787 10 25 10 C 24.660213 10 24.328661 10.020256 24 10.044922 L 24 9 C 24 8.4454545 24.445455 8 25 8 z \" fill=\"$fillcolor\" stroke=\"black\" style=\"stroke-width:1.5\"/>";
  $ret .= "<path d=\"M 20.423828 41 C 21.197828 42.763 22.955 44 25 44 C 27.045 44 28.802172 42.763 29.576172 41 L 20.423828 41 z\" fill=\"black\"/>";   
  $ret .= "<path id=\"alarmst_isb\" class=\"alarmst_sb\" d=\"M 3.4804688 9.4765625 ".
          "C 1.2493231 13.103089 -2.9605947e-16 17.418182 0 22 C 0 26.581818 1.2493231 30.896911 3.4804688 34.523438 L 5.1855469 33.476562 C 3.1506926 ".
          "30.169089 2 26.218182 2 22 C 2 17.781818 3.1506926 13.830911 5.1855469 10.523438 L 3.4804688 9.4765625 z M 46.519531 9.4765625 L 44.814453 ".
          "10.523438 C 46.849307 13.83091 48 17.781818 48 22 C 48 26.218182 46.849307 30.169089 44.814453 33.476562 L 46.519531 34.523438 C 48.750677 ".
          "30.896911 50 26.581818 50 22 C 50 17.418182 48.750677 13.103089 46.519531 9.4765625 z M 7.8164062 12.140625 C 5.9949036 15.081921 5 ".
          "18.353594 5 22 C 5 25.672173 6.1278502 29.047117 7.8085938 31.847656 L 9.5253906 30.818359 C 8.0061341 28.286898 7 25.261827 7 22 C 7 ".
          "18.712406 7.8710809 15.852063 9.5175781 13.193359 L 7.8164062 12.140625 z M  42.183594 12.140625 L 40.482422 13.193359 C 42.128919 15.852063 ".
          "43 18.712406 43 22 C 43 25.261827 41.993866 28.286898 40.474609 30.818359 L 42.191406 31.847656 C 43.87215 29.047117 45 25.672173 45 22 C 45 ".
          "18.353594 44.005097 15.081921 42.183594 12.140625 z\" fill=\"$fillcolor2\" />";
  $ret .= "<g id=\"alarmstate\" transform=\"translate(0,30) scale(0.6,0.6)\">";
  for( my $level=0;$level<$alarmno;$level++ ){
    my $val = $hash->{READINGS}{"level".$level}{VAL};
    my $col;
    if($val eq "disarmed"){
      $col = $dac;
    }elsif($val eq "armed"){
      $col = $ac;
    }elsif($val eq "armwait"){
      $col = $awc; 
    }else{
      $col = $alc; 
    }
    $ret .= "<rect class=\"arec\" width=\"10\" height=\"10\" x=\"".(5+10*$level)."\"  y=\"35\" fill=\"".$col."\" stroke=\"black\"/>";
  }
  $ret .= "</g></g></svg>";   
  
  return $ret;
  
  if( $inline ){
    return $ret;
  }else{
    $FW_RETTYPE = "image/svg+xml";
    $FW_RET="";
    FW_pO $ret;
    return ($FW_RETTYPE, $FW_RET);
  }
}

#########################################################################################
#
# Alarm_Html - returns HTML code for the Alarm page
# 
# Parameter name = name of the Alarm definition
#
#########################################################################################

sub Alarm_Html($)
{
	my ($name) = @_; 

    my $ret = "";
 
    my $hash = $defs{$name};
    my $id = $defs{$name}{NR};
    
    if( !defined($alarm_tt) ){
      #-- readjust language
      my $lang = AttrVal("global","language","EN");
      if( $lang eq "DE"){
        $alarm_tt = \%alarm_transtable_DE;
      }else{
        $alarm_tt = \%alarm_transtable_EN;
      }
    }
    
    #-- update state display
    readingsSingleUpdate( $hash, "state", Alarm_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 1 );
 
    #--
    my $lockstate = ($hash->{READINGS}{lockstate}{VAL}) ? $hash->{READINGS}{lockstate}{VAL} : "unlocked";
    my $showhelper = ($lockstate eq "unlocked") ? 1 : 0; 

    #--
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/alarm.js\"></script><script type=\"text/javascript\">\n";
    $ret .= "var alarmno = ".$alarmno.";\n";
    #-- colors
    $ret .= "var disarmcolor  = \"".AttrVal($name,"disarmcolor","lightgray")."\";\n";
    $ret .= "var armwaitcolor = \"".AttrVal($name,"armwaitcolor","#ffe658")."\";\n";
    $ret .= "var armcolor     = \"".AttrVal($name,"armcolor","#53f3c7")."\";\n";
    $ret .= "var alarmcolor   = \"".AttrVal($name,"alarmcolor","#fd5777")."\";\n";
    #-- icon map
    my $iconmap = AttrVal($name,"iconmap","");
    $ret .= "var iconmap  = '".$iconmap."';\n";
    
    #-- initial state of system
    my ($s,$ad,$aa,$al,$at,$detailstate);
    $ad = 1;
    $aa = 1;
    $al = "";
    $at = "";
    $detailstate = "";
    $ret .= "var ast = ['";
    for( my $i=0;$i<$alarmno;$i++){ 
      $s = $hash->{READINGS}{"level".$i}{VAL};
      if( index($iconmap,$i) > -1 ){
        #-- simplify by using state ??
        if( ($s eq "disarmed") || ($s eq "armwait") ){
          $detailstate .= "-";
        }elsif( $s eq "armed" ){
          $detailstate .= "O";
        }else{
          $detailstate .= "X";
        }
        $ad = $ad & ( ($s eq "disarmed")||($s eq "armwait") );
        $aa = $aa & ( $s eq "armed" );
        if( $s ne "disarmed" && $s ne "armwait" && $s ne "armed" ){
          $al .= $i.",";
          $at .= $s.",";
        }
      }
      $ret .= $s."'";
      $ret .= ",'"
        if( $i != $alarmno-1 );
    }
    $ret .= "];\n";
    $ret .="var aa = ".(($aa == 1) ? "true;\n" : "false;\n"); 
    $ret .="var ad = ".(($ad == 1) ? "true;\n" : "false;\n"); 
    $ret .="var al = '".$al."';\n";
    $ret .="var at = '".$at."';\n";
    #-- initial state of alarm icon
    my $iconstate;
    if( $al ne "" ){
      $iconstate = $al;        
      $ret .= "var blinking = 1;\n";
      $ret .= "var blinker = setInterval('blinkbell()', 250);\n";
    }else{
      if( $aa == 1 && $ad == 0 ){
        $iconstate = "armed";
      }elsif( $aa == 0 && $ad == 1 ){
        $iconstate = "disarmed";
      }else{
        $iconstate = "mixed";
      }
      $ret .= "var blinking = 0;\n";
      $ret .= "var blinker;\n";
    }
    
    $ret .= "</script>\n";
    
    $ret .= "<table class=\"roomoverview\">\n";
    #--- here we insert the icon 
    $ret .= "<tr><td style=\"width:60px;height:80px\">";
    $ret .= "<div>".Alarm_widget("name=".$name."&gstate=".$iconstate."&dstate=".$detailstate."&size=60x80")."</div>"
      if( AttrVal($name,"noicons",0)==0 );
    $ret .= "</td>";
    $ret .= "<td style=\"width:150px;vertical-align:center\"><input type=\"button\" value=\"".$alarm_tt->{"setparms"}."\" onclick=\"javascript:alarm_set('$name')\"/></td><td>".
              "<div id=\"hid_levels\">";
    for( my $k=0;$k<$alarmno;$k++ ){
      $ret .= "<div informId=\"$name-level".$k."\" class=\"hid_lx\" style=\"display:none\">".$hash->{READINGS}{"level".$k}{VAL}."</div>";
    }
    $ret .= "</div></td></tr>\n";
    
    #-- settings table
    my $row=1;
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\">".$alarm_tt->{"settings"}."</div></td></tr>";
    $ret .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"settingstable\">\n"; 
    $ret .= "<tr class=\"odd\"><td class=\"col1\" colspan=\"4\"><table id=\"armtable\" border=\"0\">\n";
    $ret .= "<tr class=\"odd\"><td class=\"col1\" style=\"text-align:right\">".$alarm_tt->{"armbutton"}."&nbsp;&#8608;</td>";
    $ret .=                    "<td class=\"col2\" style=\"text-align:right\"> ".$alarm_tt->{"waitaction"}." ";
    $ret .= sprintf("<input type=\"text\" id=\"armwait\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",(AttrVal($name, "armwait","") eq "1")?"":AttrVal($name, "armwait","")); 
    $ret .=               "</td><td class=\"col3\" rowspan=\"2\"> &#8628 ".$alarm_tt->{"delay"}."<br> &#8626;";
    $ret .= sprintf("<input type=\"text\" id=\"armdelay\" size=\"4\" maxlength=\"5\" value=\"%s\"/>",(AttrVal($name, "armdelay","0:00") eq "1")?"":AttrVal($name, "armdelay","0:00"));
    $ret .=               "</td></tr>\n"; 
    $ret .= "<tr class=\"even\"><td class=\"col1\"></td><td class=\"col2\" style=\"text-align:right\">".$alarm_tt->{"armaction"}." ";
    $ret .= sprintf("<input type=\"text\" id=\"armaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",(AttrVal($name, "armact","") eq "1")?"":AttrVal($name, "armact","")); 
    $ret .=               "</td></tr>\n";
    $ret .="<tr class=\"odd\"><td class=\"col1\" style=\"text-align:right\">".$alarm_tt->{"disarmbutton"}."&#8608</td><td class=\"col2\" style=\"text-align:right\">".$alarm_tt->{"disarmaction"}." ";
    $ret .= sprintf("<input type=\"text\" id=\"disarmaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",(AttrVal($name, "disarmact","") eq "1")?"":AttrVal($name, "disarmact","")); 
    $ret .= "</td><td></td></tr><tr class=\"odd\"><td class=\"col1\" style=\"text-align:right\">".$alarm_tt->{"cancelbutton"}."&nbsp;&#8608;</td><td class=\"col2\" style=\"text-align:right\"> ".$alarm_tt->{"cancelaction"}." ";
    $ret .= sprintf("<input type=\"text\" id=\"cancelaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",(AttrVal($name, "cancelact","") eq "1")?"":AttrVal($name, "cancelact","")); 
    $ret .= "</td><td></td></tr></table></td></tr>";
    $ret .= "<tr class=\"odd\"><td class=\"col1\">".$alarm_tt->{"level"}."</td><td class=\"col2\">".$alarm_tt->{"time"}." [hh:mm]<br/>".
             $alarm_tt->{"start"}."&nbsp;&nbsp;&nbsp;&nbsp;".$alarm_tt->{"end"}."&nbsp;</td><td class=\"col3\">".$alarm_tt->{"messagepart"}." II</td>".
            "<td class=\"col4\">".$alarm_tt->{"arm"}."/".$alarm_tt->{"cancel"}."</td></tr>\n";
    for( my $k=0;$k<$alarmno;$k++ ){
      $row++;
      my $sval = AttrVal($name, "level".$k."start", 0);
      $sval = ""
        if( $sval eq "1");
      my $eval = AttrVal($name, "level".$k."end", 0);
      $eval = ""
        if( $eval eq "1");
      my $mval = AttrVal($name, "level".$k."msg", 0);
      $mval = ""
        if( $mval eq "1");

      my $xval = AttrVal($name, "level".$k."xec", 0);
      my $xval = $hash->{DATA}{"armstate"}{"level".$k};
      $ret .= sprintf("<tr class=\"%s\"><td class=\"col1\">".$alarm_tt->{"alarm"}." $k</td>\n", ($row&1)?"odd":"even"); 
      $ret .=                          "<td class=\"col2\"><input type=\"text\" id=\"l".$k."s\" size=\"4\" maxlength=\"120\" value=\"$sval\"/>&nbsp;&nbsp;&nbsp;".
                                                          "<input type=\"text\" id=\"l".$k."e\" size=\"4\" maxlength=\"120\" value=\"$eval\"/></td>".
              "<td class=\"col3\"><input type=\"text\" id=\"l".$k."m\" size=\"25\" maxlength=\"256\" value=\"$mval\"/></td>";
      $ret .= sprintf("<td class=\"col4\"><input type=\"checkbox\" id=\"l".$k."x\" %s onclick=\"javascript:alarm_arm('$name','$k')\"/>",($xval eq "armed")?"checked=\"checked\"":"").
              "<input type=\"button\" value=\"".$alarm_tt->{"cancel"}."\" onclick=\"javascript:alarm_cancel('$name','$k')\"/></td></tr>\n";
    }    
    $ret .= "</table></td></tr>";
   
    #-- sensors table
    $row=1;
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\">".$alarm_tt->{"sensors"}."</div></td></tr>";
    $ret .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"sensorstable\">\n"; 
    $ret .= "<tr class=\"odd\" style=\"min-width:100px\"><td/><td class=\"col2\" style=\"min-width:200px\">".$alarm_tt->{"notifyto"}." ".$alarm_tt->{"alarm"}." ".$alarm_tt->{"level"}."<br/>".
             join("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;",(0..($alarmno-1)))."</td><td class=\"col3\">".
             $alarm_tt->{"notifyby"}." ".$alarm_tt->{"regexp"}."</td><td class=\"col3\">".$alarm_tt->{"messagepart"}." I</td><td class=\"col4\">".$alarm_tt->{"action"}."</td></tr>\n";
    foreach my $d (sort keys %defs ) {
       next if(IsIgnored($d));
       if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
           my @aval = split('\|',AttrVal($d, "alarmSettings",""));
           if( int(@aval) != 4){
             Log3 $hash, 1, "[Alarm] Settings incomplete for alarmSensor $d";
           }
           $row++;
           $ret .= sprintf("<tr class=\"%s\" informId=\"$d\" name=\"sensor\">", ($row&1)?"odd":"even");
           $ret .= "<td width=\"120\" class=\"col1\"><a href=\"$FW_ME?detail=$d\">$d</a></td>\n";
           $ret .= "<td id=\"$d\" class=\"col2\">\n";
           for( my $k=0;$k<$alarmno;$k++ ){
              $ret .= sprintf("<input type=\"checkbox\" name=\"alarm$k\" value=\"$k\" %s/>&nbsp;",(index($aval[0],"alarm".$k) != -1)?"checked=\"checked\"":""); 
           }
           $ret .= "</td><td class=\"col3\"><input type=\"text\" name=\"alarmnotify\" size=\"30\" maxlength=\"512\" value=\"$aval[1]\"/>";
           $ret .= "</td><td class=\"col3\"><input type=\"text\" name=\"alarmmsg\" size=\"30\" maxlength=\"512\" value=\"$aval[2]\"/></td>\n"; 
           $ret .= sprintf("<td class=\"col4\"><select name=\"%sonoff\"><option value=\"on\" %s>".$alarm_tt->{"raise"}."</option><option value=\"off\" %s>".$alarm_tt->{"cancel"}."</option>",
               $d,($aval[3] eq "on")?"selected=\"selected\"":"",($aval[3] eq "off")?"selected=\"selected\"":"");
           $ret .= sprintf("<option value=\"arm\" %s>".$alarm_tt->{"arm"}."</option><option value=\"disarm\" %s>".$alarm_tt->{"disarm"}."</option><select></td></tr>\n",
               ($aval[3] eq "arm")?"selected=\"seleced\"":"",($aval[3] eq "disarm")?"selected=\"selected\"":"");
       }
    }  
    $ret .= "</table></td></tr>";
    
    #-- actors table
    $row=1;
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\">".$alarm_tt->{"actors"}."</div></td></tr>";
    $ret .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"actorstable\">\n"; 
    $ret .= "<tr class=\"odd\" style=\"min-width:100px\"><td/><td class=\"col2\" style=\"min-width:200px\">".$alarm_tt->{"setby"}." ".$alarm_tt->{"alarm"}." ".$alarm_tt->{"level"}."<br/>".join("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;",(0..($alarmno-1))).
            "</td><td class=\"col3\">".$alarm_tt->{"setaction"};
    $ret .= "&nbsp; (".$alarm_tt->{"testaction"}.")"
             if( AttrVal($name,"testbutton",0) == 1);
    $ret .= "</td><td class=\"col3\">".$alarm_tt->{"unsetaction"};
    $ret .= "&nbsp; (".$alarm_tt->{"testaction"}.")"
             if( AttrVal($name,"testbutton",0) == 1);
    $ret .= "</td><td class=\"col4\">".$alarm_tt->{"delay"}."<br/>[hh:]mm:ss</td></tr>\n";
    foreach my $d (sort keys %defs ) {
       next if(IsIgnored($d));
       if( AttrVal($d, "alarmDevice","") eq "Actor" ) {
           my @aval = Alarm_getsettings($hash,$d,"Actor");
           $row++;
           $ret .= sprintf("<tr class=\"%s\" informId=\"$d\" name=\"actor\">", ($row&1)?"odd":"even");
           $ret .= "<td width=\"120\" class=\"col1\"><a href=\"$FW_ME?detail=$d\">$d</a></td>\n";
           $ret .= "<td id=\"$d\" class=\"col2\">\n";
           for( my $k=0;$k<$alarmno;$k++ ){
              $ret .= sprintf("<input type=\"checkbox\" name=\"alarm$k\"%s/>&nbsp;",(index($aval[0],"alarm".$k) != -1)?"checked=\"checked\"":""); 
           }
           $ret .= "</td><td class=\"col3\"><input type=\"text\" name=\"alarmon\" size=\"30\" maxlength=\"512\" value=\"$aval[1]\"/>";
           $ret .= "&nbsp;<input type=\"button\" value=\"T\" onclick=\"javascript:alarm_testaction('$name','$d','set')\"/>"
             if( AttrVal($name,"testbutton",0) == 1);
           $ret .= "</td><td class=\"col3\">"; 
           $ret .= "<input type=\"text\" name=\"alarmoff\" size=\"30\" maxlength=\"512\" value=\"$aval[2]\"/>";
           $ret .= "&nbsp;<input type=\"button\" value=\"T\" onclick=\"javascript:alarm_testaction('$name','$d','unset')\"/>"
             if( AttrVal($name,"testbutton",0) == 1);
           $ret .= "</td><td class=\"col4\"><input type=\"text\" name=\"delay\" size=\"5\" maxlength=\"8\" value=\"$aval[3]\"/></td></tr>\n";
       }
    }  
	$ret .= "</table></td></tr>\n";
	
	$ret .= "</table>";
 
 return $ret; 
}

1;

=pod
=item helper
=item summary to set up a house alarm system with 8 different alarm levels
=begin html

   <a name="Alarm"></a>
        <h3>Alarm</h3>
        <ul>
        <p> FHEM module to set up a house alarm system with 8 different alarm levels</p>
         <a name="Alarmusage"></a>
        <h4>Usage</h4>
        See <a href="http://www.fhemwiki.de/wiki/Modul_Alarm">German Wiki page</a>
        <a name="Alarmdefine"></a>
        <br/>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Alarm</code>
            <br />Defines the Alarm system. </p>
        <a name="Alarmset"></a>
        Notes: <ul>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
         <li>This module needs the JSON package.</li>
         </ul>
        <h4>Set</h4>
        <ul>
            <li><a name="alarm_cancel">
                    <code>set &lt;name&gt; canceled &lt;level&gt;</code>
                </a>
                <br />cancels an alarm of level &lt;level&gt;, where &lt;level&gt; = 0..7 </li>
            <li><a name="alarm_arm">
                    <code>set &lt;name&gt; armed &lt;level&gt;</code><br />
                    <code>set &lt;name&gt; disarmed &lt;level&gt;</code>
                </a>
                <br />sets the alarm of level &lt;level&gt; to armed (i.e., active) or disarmed
                (i.e., inactive), where &lt;level&gt; = 0..7 </li>
            <li><a name="alarm_lock">
                    <code>set &lt;name&gt; locked</code><br />
                    <code>set &lt;name&gt; unlocked</code>
                </a>
                <br />sets the lockstate of the alarm module to <i>locked</i> (i.e., alarm setups
                may not be changed) resp. <i>unlocked</i> (i.e., alarm setups may be changed>)</li>
            <li><a name="alarm_save">
                    <code>set &lt;name&gt; save|restore</code>
                </a>
                <br />Manually save/restore the arm states to/from the external file AlarmFILE (save done automatically at each state modification, restore at FHEM start)</li>
        </ul>
        <a name="Alarmget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="alarm_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>
        </ul>
        <a name="Alarmattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="alarm_hiddenroom"><code>attr &lt;name&gt; hiddenroom
                    &lt;string&gt;</code></a>
                <br />Room name for hidden alarm room (containing only the Alarm device), default:
                AlarmRoom</li>
            <li><a name="alarm_publicroom"><code>attr &lt;name&gt; publicroom
                    &lt;string&gt;</code></a>
                <br />Room name for public alarm room (containing sensor/actor devices), default:
                Alarm</li>
            <li><a name="alarm_lockstate"><code>attr &lt;name&gt; lockstate
                    locked|unlocked</code></a>
                <br /><i>locked</i> means that alarm setups may not be changed, <i>unlocked</i>
                means that alarm setups may be changed></li>
            <li><a name="alarm_testbutton"><code>attr &lt;name&gt; testbutton 0|1</code></a>
                <br /><i>1</i> means that a test button is displayed for every actor field</li>
            <li><a name="alarm_statedisplay"><code>attr &lt;name&gt; statedisplay
                        simple,color,table,none</code></a>
                <br />defines how the state of all eight alarm levels is shown. Example for the case
                when alarm no. 0 is disarmed and only alarm no. 2 is raised: <ul>
                    <li> simple = OXOOOOO</li>
                    <li> color = <span style="color:lightgray"> 0 </span><span style="font-weight:bold;color:#53f3c7">1 <span style="font-weight:bold;color:#fd5777"
                                >2</span> 3 4 5 6 7</span></li>
                    <li> table = HTML mini table with colored fields for alarms
                    </li>
                    <li> none = no state display</li>
                </ul>
            </li>
             <li><a name="alarm_noicons"><code>attr &lt;name&gt; noicons
                    0|1</code></a>
                <br />when set to 1, animated icons are suppressed</li>
            <li><a name="alarm_iconmap"><code>attr &lt;name&gt; iconmap <i>list</i></code></a>
                <br /> comma separated list of alarm levels for which the main icon/widget is set to disarmed/mixed/armed. No default=icon static</li>
            <li><a name="alarm_color"><code>attr &lt;name&gt; disarmcolor|armwaitcolor|armcolor|alarmcolor <i>color</i></code></a>
                <br />four color specifications to signal the states disarmed (default <span style="color:lightgray">lightgray</span>), 
                armwait (default <span style="color:#ffe658">#ffe658</span>), 
                armed (default <span style="color:#53f3c7">#53f3c7</span>) and alarmed (default <span style="color:#fd5777">#fd5777</span>)</li>
            <li><a name="alarm_armdelay"><code>attr &lt;name&gt; armdelay <i>mm:ss</i></code></a>
                <br />time until the arming of an alarm becomes operative (0:00 - 9:59 allowed)</li>
            <li><a name="alarm_armwait"><code>attr &lt;name&gt; armwait <i>action</i></code></a>
                <br />FHEM action to be carried out immediately after the arm event</li>
            <li><a name="alarm_armact"><code>attr &lt;name&gt; armact <i>action</i></code></a>
                <br />FHEM action to be carried out at the arme event after the delay time </li>
            <li><a name="alarm_disarmact"><code>attr &lt;name&gt; disarmact <i>action</i></code></a>
                <br />FHEM action to be carried out on the disarming of an alarm</li>
            <li><a name="alarm_cancelact"><code>attr &lt;name&gt; cancelact <i>action</i></code></a>
                <br />FHEM action to be carried out on the canceling of an alarm</li>
            <li><a name="alarm_internals"></a>For each of the 8 alarm levels, several attributes
                hold the alarm setup. They should not be changed by hand, but through the web
                interface to avoid confusion: <code>level&lt;level&gt;start, level&lt;level&gt;end,
                    level&lt;level&gt;msg, level&lt;level&gt;onact,
                    level&lt;level&gt;offact</code></li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        </ul>
=end html
=begin html_DE

<a name="Alarm"></a>
<h3>Alarm</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_Alarm">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#Alarm">Alarm</a> 
</ul>
=end html_DE
=cut
