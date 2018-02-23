########################################################################################
#
# Babble.pm
#
# FHEM module for speech control of FHEM devices
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
my $rive = 0;
my $riveinterpreter;
#-- RiveScript missing in System 
if  (eval {require RiveScript;1;} ne 1) {
  Log 1,"[Babble] the RiveScript module is missing from your Perl installation - chatbot functionality not available";
  Log 1,"         check cpan or https://github.com/aichaos/rivescript-perl for download and installation";
} else {
  RiveScript->import();
  $rive = 1;
  Log 1,"[Babble] the RiveScript module has been imported successfully, chatbot functionality available";
}

#########################
# Global variables
my $babblelinkname   = "babbles";    # link text
my $babblehiddenroom = "babbleRoom"; # hidden room
my $babblepublicroom = "babble";     # public room
my $babbleversion    = "1.25";

my %babble_transtable_EN = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Not OK",
    "start"             =>  "Start",
    "end"               =>  "End",
    "add"               =>  "Add",
    "added"             =>  "added",
    "remove"            =>  "Remove",
    "removed"           =>  "removed",
    "modify"            =>  "Modify",
    "modified"          =>  "modified",
    "cancel"            =>  "Cancel",
    "status"            =>  "Status",
    "notstarted"        =>  "Not started",
    "next"              =>  "Next",
    "babbledev"         =>  "Babble Devices",
    "babbleplaces"      =>  "Babble Places",
    "babbleverbs"       =>  "Babble Verbs",
    "babblename"        =>  "Babble Name",
    "babbletest"        =>  "Babble Test",
    "fhemname"          =>  "FHEM Name",
    "device"            =>  "Device",
    "place"             =>  "Place",
    "places"            =>  "Places",
    "rooms"             =>  "Rooms",
    "verb"              =>  "Verb",
    "target"            =>  "Target",
    "result"            =>  "Result",
    "unknown"           =>  "unknown",
    "infinitive"        =>  "Infinitive",
    "conjugations"      =>  "Conjugations and Variations",
    "helptext"          =>  "Help Text",
    "confirm"           =>  "Confirmation",
    "speak"             =>  "Please speak",
    "followedby"        =>  "followed by",
    "placespec"         =>  "a place specification",
    "dnu"               =>  "Sorry, I did not understand this",
    "input"             =>  "Input",
    "test"              =>  "Test",
    "exec"              =>  "Execute",
    "value"             =>  "Value",
    "save"              =>  "Save",
    "action"            =>  "Action",
    "time"              =>  "Time",
    "description"       =>  "Description",
    "settings"          =>  "Settings",
    "babbles"           =>  "Babble System",
    "setparms"          =>  "Set Parameters",
    #--
    "hallo"             =>  "Hallo",
    "state"             =>  "Security",
    "unlocked"          =>  "Unlocked",
    "locked"            =>  "Locked"
    );
    
 my %babble_transtable_DE = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Nicht OK",
    "start"             =>  "Start",
    "end"               =>  "Ende",
    "add"               =>  "Hinzufügen",
    "added"             =>  "hinzugefügt",
    "remove"            =>  "Entfernen",
    "removed"           =>  "entfernt",
    "modify"            =>  "Ändern",
    "modified"          =>  "geändert",
    "cancel"            =>  "Abbruch",
    "status"            =>  "Status",
    "notstarted"        =>  "Nicht gestartet",
    "next"              =>  "Nächste",
    "babbledev"         =>  "Babble Devices",
    "babbleplaces"      =>  "Babble Orte",
    "babbleverbs"       =>  "Babble Verben",
    "babblename"        =>  "Babble Name",
    "babbletest"        =>  "Babble Test",
    "fhemname"          =>  "FHEM Name",
    "device"            =>  "Gerät",
    "place"             =>  "Ort",
    "places"            =>  "Orte",
    "rooms"             =>  "Räume",
    "verb"              =>  "Verb",
    "target"            =>  "Ziel",
    "result"            =>  "Ergebnis",
    "unknown"           =>  "unbekannt",
    "infinitive"        =>  "Infinitiv",
    "conjugations"      =>  "Konjugationen und Variationen",
    "helptext"          =>  "Hilfetext",
    "confirm"           =>  "Bestätigung",
    "speak"             =>  "Bitte sprich",
    "followedby"        =>  "gefolgt von",
    "placespec"         =>  "einer Ortsangabe",
    "dnu"               =>  "Es tut mir leid, das habe ich nicht verstanden",
    "input"             =>  "Input",
    "test"              =>  "Test",
    "exec"              =>  "Ausführung",
    "value "            =>  "Wert",
    "save"              =>  "Sichern",
    "action"            =>  "Aktion",
    "time"              =>  "Zeit",
    "description"       =>  "Beschreibung",
    "settings"          =>  "Einstellungen",
    "babbles"           =>  "Babble",
    "setparms"          =>  "Parameter setzen",
    #--
    "hallo"             =>  "Hallo",
    "state"             =>  "Sicherheit",
    "unlocked"          =>  "Unverschlossen",
    "locked"            =>  "Verschlossen"
    );
    
my $babble_tt;

#########################################################################################
#
# Babble_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Babble_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "Babble_Define";
  $hash->{SetFn}   	   = "Babble_Set";  
  $hash->{GetFn}       = "Babble_Get";
  $hash->{UndefFn}     = "Babble_Undef";   
  #$hash->{AttrFn}      = "Babble_Attr";
  my $attst            = "lockstate:locked,unlocked helpFunc confirmFunc noChatBot:0,1 testParm0 testParm1 testParm2 testParm3 ".
                         "remoteFHEM0 remoteFHEM1 remoteFHEM2 remoteFHEM3 remoteFunc0 remoteFunc1 remoteFunc2 remoteFunc3 remoteToken0 remoteToken1 remoteToken2 remoteToken3 ".
                         "babbleIds babblePreSubs babbleDevices babblePlaces babbleNotPlaces babbleVerbs babbleVerbParts babblePrepos babbleQuests babbleArticles babbleStatus babbleWrites babbleTimes";
  $hash->{AttrList}    = $attst;
  
  if( !defined($babble_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $babble_tt = \%babble_transtable_DE;
    }else{
      $babble_tt = \%babble_transtable_EN;
    }
  }
  $babblelinkname = $babble_tt->{"babbles"};
  
  $data{FWEXT}{babblex}{LINK} = "?room=".$babblehiddenroom;
  $data{FWEXT}{babblex}{NAME} = $babblelinkname;	
  
  #-- Create a new RiveScript interpreter
  Babble_createRive($hash)
    if( $rive==1 && !defined($hash->{Rive})) ;
  
  return undef;
}

#########################################################################################
#
# Babble_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Babble_Define ($$) {
  my ($hash, $def) = @_;
  my $now = time();
  my $name = $hash->{NAME}; 
  $hash->{VERSION} = $babbleversion;
  
  #-- readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $babble_tt = \%babble_transtable_DE;
  }else{
    $babble_tt = \%babble_transtable_EN;
  }
  
  readingsSingleUpdate( $hash, "state", "Initialized", 1 ); 
 
  $babblehiddenroom           = defined($attr{$name}{"hiddenroom"})  ? $attr{$name}{"hiddenroom"} : $babblehiddenroom;  
  $babblepublicroom           = defined($attr{$name}{"publicroom"})  ? $attr{$name}{"publicroom"} : $babblepublicroom; 
  $data{FWEXT}{babblex}{LINK} = "?room=".$babblehiddenroom;
  $data{FWEXT}{babblex}{NAME} = $babblelinkname;
  $attr{$name}{"room"}        = $babblehiddenroom;;	
  
  my $date = Babble_restore($hash,0);
  
  #-- data seems to be ok, restore
  if( defined($date) ){
    Babble_restore($hash,1);
    Log3 $name,1,"[Babble_Define] data hash restored from save file with date $date";
    
  #-- intialization
  }else{
    $hash->{DATA}{"devs"}=();
    $hash->{DATA}{"devcontacts"}=();
    $hash->{DATA}{"rooms"}=();
    $hash->{DATA}{"splaces"}=();
    $hash->{DATA}{"places"}=();
    $hash->{DATA}{"commands"}=();
    $hash->{DATA}{"help"}=();
    $hash->{DATA}{"status"}=();
    $hash->{DATA}{"writes"}=();
    $hash->{DATA}{"times"}=();
    Babble_checkattrs($hash);
    Log3 $name,1,"[Babble_Define] data hash is initialized";
  }
  
  #-- Create a new RiveScript interpreter
  Babble_createRive($hash)
    if( $rive==1 && !defined($hash->{Rive})) ;
 
  $modules{babble}{defptr}{$name} = $hash;
  
  RemoveInternalTimer($hash);
  InternalTimer      ($now + 5, 'Babble_CreateEntry', $hash, 0);

  return;
}

#########################################################################################
#
# Babble_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Babble_Undef ($$) {
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  delete $data{FWEXT}{babblex};
  if (defined $defs{$name."_weblink"}) {
      FW_fC("delete ".$name."_weblink");
      Log3 $hash, 3, "[".$name. " V".$babbleversion."]"." Weblink ".$name."_weblink deleted";
  }
  
  return undef;
}

#########################################################################################
#
# Babble_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
#########################################################################################

sub Babble_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  
  my $hash = $defs{"$name"};
  
  #-- in any attribute redefinition readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $babble_tt = \%babble_transtable_DE;
  }else{
    $babble_tt = \%babble_transtable_EN;
  }
  return;  
}

#########################################################################################
#
# Babble_CreateEntry - Puts the babble entry into the FHEM menu
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_CreateEntry($) {
   my ($hash) = @_;
 
   my $name = $hash->{NAME};
   if (!defined $defs{$name."_weblink"}) {
      FW_fC("define ".$name."_weblink weblink htmlCode {Babble_Html(\"".$name."\")}");
      Log3 $hash, 3, "[".$name. " V".$babbleversion."]"." Weblink ".$name."_weblink created";
   }
   FW_fC("attr ".$name."_weblink room ".$babblehiddenroom);

   foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     if (index($hr,$babblehiddenroom) == -1){ 		
		    if ($hr eq "") {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$babblehiddenroom);
		    }else {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$babblehiddenroom);
		    }
		    Log3 $hash, 3, "[".$name. " V".$babbleversion."]"." Added hidden room '".$babblehiddenroom."' to ".$defs{$dn}{NAME};
	     }	
      }
   }
   
   #-- recover state from stored readings
   readingsBeginUpdate($hash);
   #readingsBulkUpdate( $hash, "state", $mga);
   readingsEndUpdate( $hash,1 );

}

#########################################################################################
#
# Babble_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_Set($@) {
   my ( $hash, $name, $cmd, @args ) = @_;

   if ( $cmd =~ /^lock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "locked", 0 ); 
	  return;
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^unlock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "unlocked", 0 );
	  return;
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^rivereload/ ) {
    delete $hash->{Rive};
	return Babble_createRive($hash);
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^test/ ) {
	return Babble_Test($hash);
	 
  #-----------------------------------------------------------
   } elsif ( $cmd =~ /^save/ ) {
	return Babble_save($hash);
	 
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^restore/ ) {
     return Babble_restore($hash,1);
   
   } else {
     my $str = "[babble] Unknown argument " . $cmd . ", choose one of locked:noArg unlocked:noArg save:noArg restore:noArg test:noArg ";
	 $str .= "rivereload:noArg"
	   if($rive == 1 && AttrVal($name,"noChatBot",0) != 1);
	 return $str;
   }
}

#########################################################################################
#
# Babble_Get - Implements the Get function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_Get($@) {
  my ($hash, @a) = @_;
  my $res = "";
  my $ip;
  
  my $name = $hash->{NAME};
  my $arg = (defined($a[1]) ? $a[1] : "");
  if ($arg eq "version") {
    return "babble.version => $babbleversion";
  }elsif ($arg eq "tokens") {
    for( my $i=0;$i<=3;$i++ ){
      $ip = AttrVal($name,"remoteFHEM$i",undef);
      if( $ip ){
        Babble_getcsrf($name,$ip,$i);
      }
    }
  } else {
    return "Unknown argument $arg choose one of version:noArg tokens:noArg";
  }
}

#########################################################################################
#
# Babble_save
#
# Parameter hash = hash of the babble device
#
#########################################################################################

sub Babble_save($) {
  my ($hash) = @_;
  my $date = localtime(time);
  my $name = $hash->{NAME};
  $hash->{DATA}{"savedate"} = $date;
  readingsSingleUpdate( $hash, "savedate", $hash->{DATA}{"savedate"}, 1 ); 
  my $json   = JSON->new->utf8;
  my $jhash0 = eval{ $json->encode( $hash->{DATA} ) };
  if( ReadingsVal($name,"lockstate","locked") ne "locked" ){
    my $error  = FileWrite("babbleFILE",$jhash0);
    #Log3 $name, 1, "         ".Dumper($jhash0);
    
    Log3 $name,1,"[Babble_save]";
  }else{
    Log3 $name, 1, "[Babble] attempt to save data failed due to lockstate";
    Log3 $name, 5, "         ".Dumper($jhash0);
  }
  return;
}

sub Babble_savename($){
   my ($name) = @_;
   my $hash  = $defs{$name};
   Babble_save($hash);
}
	 
#########################################################################################
#
# Babble_restore
#
# Parameter hash = hash of the babble device
#
#########################################################################################

sub Babble_restore($$) {
  my ($hash,$doit) = @_;
  my $name = $hash->{NAME};
  my ($error,@lines) = FileRead("babbleFILE");
  if( defined($error) && $error ne "" ){
    Log3 $name,1,"[Babble_restore] read error=$error";
    return undef;
  }
  my $json   = JSON->new->utf8;
  my $jhash1 = eval{ $json->decode( join('',@lines) ) };
  my $date   = $jhash1->{"savedate"};
  #-- just for the first time, reading an old savefile
  $date = localtime(time)
    if( !defined($date));
  readingsSingleUpdate( $hash, "savedate", $date, 0 ); 
  if( $doit==1 ){
    $hash->{DATA}  = {%{$jhash1}}; 
    Log3 $name,1,"[Babble_restore] Data hash restored from save file with date ".$date;
    return 1;
  }else{  
    return $date;
  }
}

#########################################################################################
#
# Babble_Test - Implements a variety of tests
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_Test($) {
  my ($hash) = @_;
 
  my $name = $hash->{NAME};
  my $str = "";
  $str .= "\nA.1:".Babble_DoIt($name,"guten morgen","testit",0);
  $str .= "\nA.2:".Babble_DoIt($name,"gute nacht","testit",0);
  $str .= "\nA.3:".Babble_DoIt($name,"guten morgen jeannie","testit",0);
  $str .= "\nA.4:".Babble_DoIt($name,"gute nacht jeannie","testit",0);
  $str .= "\n";
  $str .= "\nB.1:".Babble_DoIt($name,"schalte das gerät an","testit",0);
  $str .= "\nB.2:".Babble_DoIt($name,"schalte gerät an","testit",0);
  $str .= "\nB.3:".Babble_DoIt($name,"mach das gerät an","testit",0);
  $str .= "\nB.4:".Babble_DoIt($name,"das gerät ausschalten","testit",0);
  $str .= "\nB.5:".Babble_DoIt($name,"gerät ausschalten","testit",0);
  $str .= "\nB.6:".Babble_DoIt($name,"das gerät ausmachen","testit",0);
  $str .= "\nB.7:".Babble_DoIt($name,"gerät anmachen","testit",0);
  $str .= "\nB.8:".Babble_DoIt($name,"schalte beleuchtung an","testit",0);
  $str .= "\nB.9:".Babble_DoIt($name,"licht anschalten","testit",0);
  $str .= "\n";
  $str .= "\nC.1:".Babble_DoIt($name,"wie ist der wert von gerät","testit",0);
  $str .= "\nC.2:".Babble_DoIt($name,"wie ist wert von gerät","testit",0);
  $str .= "\nC.3:".Babble_DoIt($name,"wie ist der wert gerät","testit",0);
  $str .= "\nC.4:".Babble_DoIt($name,"wie ist wert gerät","testit",0);
  $str .= "\nC.4:".Babble_DoIt($name,"sage den status von gerät","testit",0);
  $str .= "\nC.5:".Babble_DoIt($name,"sage status von gerät","testit",0);
  $str .= "\nC.6:".Babble_DoIt($name,"sage status gerät","testit",0);
  $str .= "\n";
  $str .= "\nD.1:".Babble_DoIt($name,"wie ist das wetter von morgen","testit",0);
  $str .= "\nD.2:".Babble_DoIt($name,"wie ist wetter von morgen","testit",0);
  $str .= "\nD.3:".Babble_DoIt($name,"wie ist das wetter morgen","testit",0);
  $str .= "\nD.4:".Babble_DoIt($name,"wie ist wetter morgen","testit",0);
  $str .= "\nD.5:".Babble_DoIt($name,"wie ist morgen das wetter","testit",0);
  $str .= "\nD.6:".Babble_DoIt($name,"wie ist morgen wetter","testit",0);
  $str .= "\nD.7:".Babble_DoIt($name,"wetter von morgen","testit",0);
  $str .= "\nD.8:".Babble_DoIt($name,"wetter morgen","testit",0);
  $str .= "\n";
  $str .= "\nF.1:".Babble_DoIt($name,"schalte den wecker aus","testit",0);
  $str .= "\nF.2:".Babble_DoIt($name,"schalte wecker aus","testit",0);
  $str .= "\nF.3:".Babble_DoIt($name,"den wecker ausschalten","testit",0);
  $str .= "\nF.4:".Babble_DoIt($name,"wecker ausschalten","testit",0);
  $str .= "\nF.5:".Babble_DoIt($name,"wie ist die weckzeit","testit",0);
  $str .= "\nF.6:".Babble_DoIt($name,"wie ist der status des weckers","testit",0);
  $str .= "\nF.7:".Babble_DoIt($name,"weckzeit ansagen","testit",0);
  $str .= "\nF.8:".Babble_DoIt($name,"weckzeit","testit",0);
  $str .= "\nF.9:".Babble_DoIt($name,"wecken um 4 uhr 3","testit",0);
  $str .= "\nF.10:".Babble_DoIt($name,"stelle den wecker auf 17:00","testit",0);
  $str .= "\nF.11:".Babble_DoIt($name,"wecken um 13:12 Uhr","testit",0);
  $str .= "\n";
  $str .= "\nG.1:".Babble_DoIt($name,"das haus ansagen","testit",0);
  $str .= "\nG.2:".Babble_DoIt($name,"haus ansagen","testit",0);
  $str .= "\nG.3:".Babble_DoIt($name,"haus status","testit",0);
  $str .= "\nG.4:".Babble_DoIt($name,"wie ist der status des hauses","testit",0);
  $str .= "\nG.5:".Babble_DoIt($name,"wie ist der status vom haus","testit",0);
  $str .= "\nG.6:".Babble_DoIt($name,"das haus sichern","testit",0);
  $str .= "\nG.7:".Babble_DoIt($name,"sichere das haus","testit",0);
  $str .= "\nG.8:".Babble_DoIt($name,"haus sichern","testit",0);
  $str .= "\nG.9:".Babble_DoIt($name,"das haus entsichern","testit",0);
  $str .= "\nG.10:".Babble_DoIt($name,"haus entsichern","testit",0);
  $str .= "\nG.11:".Babble_DoIt($name,"haustür öffnen","testit",0);
  $str .= "\nG.12:".Babble_DoIt($name,"die haustür öffnen","testit",0);
  $str .= "\nG.13:".Babble_DoIt($name,"öffne die haustür","testit",0);
  $str .= "\nG.14:".Babble_DoIt($name,"schließe die haustür zu","testit",0);
  $str .= "\nG.15:".Babble_DoIt($name,"schließe die haustür auf","testit",0);
  $str .= "\n";
  $str .= "\nH.1:".Babble_DoIt($name,"alarmanlage einschalten","testit",0);
  $str .= "\nH.1:".Babble_DoIt($name,"alarmanlage ein schalten","testit",0);
  $str .= "\nH.1:".Babble_DoIt($name,"die alarmanlage scharfschalten","testit",0);
  $str .= "\nH.2:".Babble_DoIt($name,"alarmanlage unscharf schalten","testit",0);
  $str .= "\nH.2:".Babble_DoIt($name,"die alarmanlage ausschalten","testit",0);
  $str .= "\nH.3:".Babble_DoIt($name,"schalte die alarmanlage scharf","testit",0);
  $str .= "\nH.4:".Babble_DoIt($name,"schalte den alarm an","testit",0);
  $str .= "\nH.5:".Babble_DoIt($name,"alarm wider rufen","testit",0);
  $str .= "\nH.6:".Babble_DoIt($name,"alarm widerrufen","testit",0);
  $str .= "\n";
  $str .= "\nI.1:".Babble_DoIt($name,"schalte beleuchtung in sitzgruppe an","testit",0);
  $str .= "\nI.2:".Babble_DoIt($name,"schalte beleuchtung in der sitzgruppe an","testit",0);
  $str .= "\nI.3:".Babble_DoIt($name,"mach die beleuchtung auf terrasse an","testit",0);
  $str .= "\nI.4:".Babble_DoIt($name,"mache außen die beleuchtung aus","testit",0);
  $str .= "\nI.5:".Babble_DoIt($name,"wie ist die temperatur im badezimmer","testit",0);
  $str .= "\nI.6:".Babble_DoIt($name,"wie ist die feuchte in dominics zimmer","testit",0);
  $str .= "\nI.7:".Babble_DoIt($name,"wie ist die feuchte in dem schlafzimmer","testit",0);
  $str .= "\nI.8:".Babble_DoIt($name,"wie ist der status der tür im schlafzimmer","testit",0);
  $str .= "\nI.9:".Babble_DoIt($name,"status tür schlafzimmer","testit",0);
  $str .= "\nI.10:".Babble_DoIt($name,"status der tür schlafzimmer","testit",0);
  $str .= "\nI.11:".Babble_DoIt($name,"status tür im schlafzimmer","testit",0);
  $str .= "\nI.12:".Babble_DoIt($name,"status der tür im schlafzimmer","testit",0);
  $str .= "\n";
  $str .= "\nJ.1:".Babble_DoIt($name,"stelle bei gerät den wert auf 8","testit",0);
  $str .= "\nJ.2:".Babble_DoIt($name,"stelle am gerät wert auf 9","testit",0);
  $str .= "\nJ.3:".Babble_DoIt($name,"stelle bei harmony den kanal auf 10","testit",0);
  $str .= "\nJ.4:".Babble_DoIt($name,"stelle am fernseher die lautstärke auf 11","testit",0);
  $str .= "\n";
  $str .= "\nK.1:".Babble_DoIt($name,"zur einkaufsliste hinzufügen bratheringe","testit",0);
  $str .= "\nK.2:".Babble_DoIt($name,"zu peters liste hinzufügen ticket münchen besorgen","testit",0);
  $str .= "\nK.3:".Babble_DoIt($name,"von dominics liste entfernen schmieröl","testit",0);
  $str .= "\nK.4:".Babble_DoIt($name,"baumarktliste löschen","testit",0);
  $str .= "\nK.5:".Babble_DoIt($name,"einkaufsliste senden","testit",0);
 
 return $str;
  
}

##############################################################################
#
#  Babble_Normalize
#
#  Parameter hash = hash of the babble device
#
##############################################################################

sub Babble_Normalize($$){
  my ($name,$sentence) = @_;
  my $hash   = $defs{$name};
  
  $sentence = lc $sentence;
  $sentence =~ s/[,.]//g;  
  
  my $cat          = 0;
  my $subcat       = 0;
  my $subsubcat    = 0;
    
  my ($device,$verb,$reading,$value,$article,$reserve,$place,$state,$prepo)=("","","","","","","","","","");
  
  #-- normalize special phrases
  my $sentmod = $sentence;
  my $pairs = AttrVal($name,"babblePreSubs",undef);
  if( $pairs ){
    my @subs=split(' ',$pairs);
    for( my $i=0; $i<int(@subs); $i++ ){
      my ($t,$r) = split( ':',$subs[$i],2 );
      $t =~ s/\\s/ /g;
      $r =~ s/\\s/ /g;
      $sentmod =~ s/$t/$r/;
    }
  }
  my @word = split(' ',$sentmod,15);
  my $len  = int(@word);
  
  ############################# POS tagging ###################
 
  #-- isolate place - take out (prepo) [arti] PLACE
  # (verb) (prepo) [arti] PLACE [arti] (device)
  # (verb) [arti] (device) (prepo) [arti] PLACE
  #  wie ist [arti] (device) (prepo) [arti] PLACE
  #  wie ist (prepo) [arti] PLACE [arti] (device)
  $place = "none";
  for( my $i=0;$i<$len;$i++){
    if( $word[$i] =~ /^$hash->{DATA}{"re_places"}/ ){
      $place = $word[$i];
      my $to = 1;
      $to++
        if( ($i-1)>=0 && $word[$i-1] =~ /^$hash->{DATA}{"re_articles"}/ );
      $to++ 
        if( ($i-$to)>=0 && $word[$i-$to] =~ /^$hash->{DATA}{"re_prepos"}/ );
      for( my $j=$i+1-$to;$j<$len;$j++){
        $word[$j]=($word[$j+$to])?$word[$j+$to]:"";
      }
      last;
    }
  }
  #-- backup without place for reserve
  my @xord = @word;
  
  #-- leer
  if( int(@word) == 0){
    return ("","","","","","","");
    
  #-- Kategorie 1: Verb zuerst ----------------------------------------------------------
  #   schalte das gerät an
  #   schalte gerät an
  #   sage den status von gerät
  #   sage status von gerät
  #   sage status gerät
  #   schalte den wecker aus ;
  #   schalte wecker aus
  }elsif( ($word[0] =~ /^$hash->{DATA}{"re_verbsc"}/) && ($word[1])){
    $cat = 1;
    #-- get infinitive
    $verb = $hash->{DATA}{"verbs"}{$word[0]};
    if( $word[1] =~ /^$hash->{DATA}{"re_articles"}/){
      $subcat  = 1;
      $article = $word[1];
      $device  = $word[2];
      $reading = $word[3];
      $reserve = $word[4];
    }elsif( $word[1] =~ /^$hash->{DATA}{"re_prepos"}/){
      $subcat  = 2;
      $article = $word[1];
      $device  = $word[2];
    }else{
      $subcat  = 3;
      $device  = $word[1];
      $reading = $word[2];
      $reserve = $word[3];
    }
    #-- device=state => verb="sage" => reading
    if( $hash->{DATA}{"re_status"} && $device =~ /^$hash->{DATA}{"re_status"}/ ){
      if( $reading =~ /^$hash->{DATA}{"re_prepos"}/ ){
        $subsubcat  = 1;  
        $reading = $device;
        $device  = $reserve;
      }else{
        $subsubcat  = 2;
        $reserve = $reading;
        $reading = $device;
        $device  = $reserve;
      }
    #-- reading of device => target
    }elsif( $subcat==2 ){
      if( $word[3] =~ /^$hash->{DATA}{"re_articles"}/ ){
        $subsubcat  = 3;
        $reading = $word[4];
        $reserve = $word[5];
      }else{
        $subsubcat  = 4;
        $reading = $word[3];
        $reserve = $word[4];
      }
    }
  #-- Kategorie 2  ----------------------------------------------------------
  #   wie ist der wert von gerät
  #   wie ist wert von gerät
  #   wie ist der wert gerät
  #   wie ist wert gerät
  #   wie ist das wetter morgen
  #   wie ist wetter morgen
  #   wie ist morgen das wetter
  #   wie ist morgen wetter
  #   wie ist die weckzeit
  #   wie ist der status des weckers
  #  (quest) ist (time) [arti1] (reading) [prepo] [arti2] ($device)
  }elsif( $word[0] =~ /^$hash->{DATA}{"re_quests"}/){
     $cat = 2;
     $verb    = "sagen";
     my $inext;
     #-- check time
     if( $word[2] =~ /^$hash->{DATA}{"re_times"}/){
       $value = $word[2];
       $inext = 3;
     }else{
       $inext = 2;
     }
     #-- take out article
     if( $word[$inext] =~ /^$hash->{DATA}{"re_articles"}/){
       $subcat=1;
       $article = $word[$inext];
       $reading = $word[$inext+1];
       #-- check time => device is reading
       if( $word[$inext+2] =~ /^$hash->{DATA}{"re_times"}/){
         $subsubcat = 1;
         $value  = $word[$inext+2];
         $device = $reading;
       #-- check time => device is reading
       }elsif( $word[$inext+2] =~ /^$hash->{DATA}{"re_prepos"}/ && $word[$inext+3] =~ /^$hash->{DATA}{"re_times"}/){
         $subsubcat = 2;
         $value  = $word[$inext+3];
         $device = $reading;
       #--take out preposition
       }elsif( $word[$inext+2] =~ /^$hash->{DATA}{"re_prepos"}/ ){
         if( $word[$inext+3] =~ /^$hash->{DATA}{"re_articles"}/){
           $subsubcat = 3;
           $article = $word[$inext+3];
           $device  = $word[$inext+4];
         }else{
           $subsubcat = 4;
           $device  = $word[$inext+3];
         }
       #-- no preposition
       }else{
         if( $word[$inext+2] =~ /^$hash->{DATA}{"re_articles"}/){
           $subsubcat = 5;
           $article = $word[$inext+2];
           $device  = $word[$inext+3];
         }else{
           $subsubcat = 6;
           $device  = $word[$inext+2];
         }
       }
     #-- no article
     }else{
       $subcat=2;
       $reading = $word[$inext];        
       #-- check time => device is reading
       if( $word[$inext+1] =~ /^$hash->{DATA}{"re_times"}/){
         $subsubcat = 1;
         $value  = $word[$inext+1];
         $device = $reading;
       #-- check time => device is reading
       }elsif( $word[$inext+1] =~ /^$hash->{DATA}{"re_prepos"}/ && $word[$inext+2] =~ /^$hash->{DATA}{"re_times"}/){
         $subsubcat = 2;
         $value  = $word[$inext+2];
         $device = $reading;
       #--take out preposition
       }elsif( $word[$inext+1] =~ /^$hash->{DATA}{"re_prepos"}/ ){
         if( $word[$inext+2] =~ /^$hash->{DATA}{"re_articles"}/){
           $subsubcat = 3;
           $article = $word[$inext+2];
           $device  = $word[$inext+3];
         }else{
           $subsubcat = 4;
           $device  = $word[$inext+2];
         }
       #-- no preposition
       }else{
         if( $word[$inext+1] =~ /^$hash->{DATA}{"re_articles"}/){
           $subsubcat = 5;
           $article = $word[$inext+1];
           $device  = $word[$inext+2];
         }else{
           $subsubcat = 6;
           $device  = $word[$inext+1];
         }
       }
     }
    if( $device eq ""){
      $subsubcat = 7;
      $device = $reading;
      $reading = "status";
    }
  #-- Kategorie 3 ----------------------------------------------------------
  #   das gerät anschalten
  #   gerät anschalten
  #   das wetter von morgen
  #   wetter von morgen
  #   das wetter morgen
  #   wetter morgen
  #   guten morgen
  #   gute nacht
  #   den wecker ausschalten
  #   wecker ausschalten
  #   wecker
  #   status
  }else{
    $cat = 3;
    my $rex = $hash->{DATA}{"re_verbparts"}." ?".$hash->{DATA}{"re_verbsi"};
    #-- guten morgen / gute nacht
    if( $word[0] =~ /^gut.*/){
      $subcat = 1;
      $device="zeit";
      $reading="status";
      $value=$word[1];
      $reserve=$word[2]
        if( $word[2] );
      $verb="schalten";
    #-- (arti) (device) something
    }elsif( $word[0] =~ /^$hash->{DATA}{"re_articles"}/){
      $subcat = 2;
      $article = $word[0];
      $device  = $word[1];
      shift(@xord);
      shift(@xord);
      #--take out preposition
      if( $word[2] =~ /^$hash->{DATA}{"re_prepos"}/ ){
        $subsubcat = 1;
        shift(@xord);
        $reserve = join(" ",@xord);
      }else{
        $subsubcat = 2;
        $reserve = join(" ",@xord);
      }
      #-- (arti) (device) [prepo] (time)
      if( $reserve =~ /^$hash->{DATA}{"re_times"}/ ){
        $subsubcat = 3;
        #$reading   = $reserve;
        $value     = $reserve;
        $verb      = "sagen";
      #-- (arti) (device) [prepo] verb
      }elsif( $reserve =~ s/^$hash->{DATA}{"re_verbsi"}\s?// ){
        $subsubcat = 4;
        $verb      = $1;
        $reading   = $reserve;
      #-- (arti) (device) [prepo] (reading) (verb) (value)
      }else{
        $subsubcat = 5;
        $reserve =~ /^$rex/;
        #-- named group
        $verb    = $+{verbsi};   
        $reading = $1;
      }
    #-- status [prepo] (device)
    }elsif( $word[0] =~ /^status/){
      $subcat = 3;
      #--take out preposition
      if( $word[1] =~ /^$hash->{DATA}{"re_prepos"}/ ){
        $subsubcat = 1;
        $device    = $word[2];
      }else{
        $subsubcat = 2;
        $device  = $word[1];
      }
      $verb    = "sagen";
      $reading = "status";
    #-- (device) something
    }elsif($word[1] ne ""){
      $subcat  = 4;
      $device  = $word[0];   
      shift(@xord);
      #--take out preposition
      if( $word[1] =~ /^$hash->{DATA}{"re_prepos"}/ ){
        $subsubcat = 1;
        shift(@xord);
        $reserve   = join(" ",@xord);
      }else{
        $subsubcat = 2;
        $reserve   = join(" ",@xord);
      }
      #-- (device) [prepo] (time)
      if( $reserve =~ /^$hash->{DATA}{"re_times"}/ ){
        $subsubcat = 3;
        $reading   = "status";
        $value     = $reserve;
        $verb      = "sagen";
      #-- (device) [prepo] status
      }elsif( $reserve =~ /^status/ ){
        $subsubcat = 4;
        $reading   = "status";
        $verb      = "sagen";
      #-- (device) (write)
      }elsif( $word[1] =~ /^$hash->{DATA}{"re_writes"}/ ){
        $subsubcat = 5;
        $verb      = $word[1];
        shift(@xord);
        $reading   = join(" ",@xord);
      #-- (arti) (device) [prepo] verb
      }elsif( $reserve =~ s/^$hash->{DATA}{"re_verbsi"}\s?// ){
        $subsubcat = 6;
        $verb      = $1;
        $reading   = $reserve;
      #-- (device) [prepo] (reading) (verb) (value)
      }else{
        $subsubcat = 7;
        $reserve   =~ /^$rex/;
        #-- named group
        $verb      = $+{verbsi};
        $reading   = $1;
      }
    #-- (device) 
    }else{
      $subcat  = 5;
      $device  = $word[0];
      $reading = "status";
      $verb    = "sagen"; 
    }
  }
  #-- normalize devices
  $device = "haus" 
    if( $device =~/hauses/);
  $device = "wecker" 
    if( $device =~/we((ck)|g).*/);
  $place = "wohnzimmer"
    if( ($device eq "licht") && ($place eq ""));
  if( $device eq "außenlicht" ){
    $place="aussen"
      if( $place eq "" );
    $device="licht";
  }
  
  #-- machen
  $verb = "schalten"
    if( $verb && $verb eq "machen");
    
  #-- sichern
  $reading = "zu"
    if(( $verb && $verb eq "sichern") && ($reading eq ""));
    
  #-- an
  $reading = "status"
    if( (( $verb && $verb eq "sagen") || ( $verb && $verb eq "zeigen")) && ($reading eq "an"));
  $reading = "an"
    if( $reading && $reading eq "ein");
    
  #-- value
  $value=substr($sentmod,index($sentmod,"auf")+4)
    if( ($reading && $reading eq "auf") || ($reserve && $reserve eq "auf") );
    
  $value=substr($sentmod,index($sentmod,"hinzufügen")+11)
    if( $reserve && $reserve =~ /hinzufügen (.*)/ );
  
  if( $verb && $verb eq "entfernen" ){
    $value = $reading;
    $reading = "ent";
  }
    
  if( $value =~ /.*uhr.*/ ){
    $value = Babble_timecorrector($value);
  }
    
  return ($device,$verb,$reading,$value,$article,$reserve,$place,"$cat.$subcat.$subsubcat");
}

#########################################################################################
#
# Babble_timecorrector - to correct for weird answers from Google
#
#########################################################################################

sub Babble_timecorrector($){
  my ($value) = @_;
  my ($h,$m1,$m2);
  #-- xx:yy uhr und zz uhr
  if( $value =~/(\d?\d):(\d\d) uhr und (\d\d)( uhr)?/ ){
    $h  = $1*1;
    $m1 = $2*1;
    $m2 = $3*1;
    return(sprintf("%2d\:%02d uhr",$h,$m1+$m2));
  #-- xx uhr zz uhr
  }elsif( $value =~/(\d?\d) uhr (\d\d)( uhr)?/ ){
    $h  = $1*1;
    $m1 = $2*1;
    return(sprintf("%2d\:%02d uhr",$h,$m1));
  #-- xx:yy - no correction
  }elsif( $value =~/(\d?\d)(:(\d\d))?( uhr)?$/ ){
    $h  = $1*1;
    $m1 = $3*1;
    if( $m1 eq "" ){
      $m1 = 0;
    }
    return(sprintf("%2d\:%02d uhr",$h,$m1));
  }else{
    return "xx";
  }
}

#########################################################################################
#
# Babble_createRive
#
#########################################################################################
   
sub Babble_createRive($){
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  my $rs = $hash->{Rive};
  if( !defined($rs) ){
    $rs = new RiveScript(utf8=>1);
    $hash->{Rive} = $rs; 
    Log3 $name, 1, "[Babble] new RiveScript interpreter generated";
  }
  #--load a directory of replies
  eval{$rs->loadDirectory ("./rivescript")};
  
  #-- sort all the loaded replies
  $rs->sortReplies;
}
  
#########################################################################################
#
# Babble_getcsrf
# 
# Parameter ip = ip address of remote FHEM
#
#########################################################################################
   
sub Babble_getcsrf($$$){
    my ($name,$ip,$i) = @_;
    my $url    = "http://".$ip."/fhem";
    HttpUtils_NonblockingGet({
      url => $url,
      callback => sub($$$){
        my ($rhash,$err,$data) = @_;
        my $res = $rhash->{httpheader};
        $res =~ /X-FHEM-csrfToken\:\s(csrf_\d+).*/;
        CommandAttr(undef,$name." remoteToken$i ".$1);
        }
      });
}

########################################################################################
#
# Babble_DoIt
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_DoIt{
  my ($name,$sentence,@parms) = @_;
  my $hash  = $defs{$name};
  
  chomp ($sentence);
  my $testit = 0;
  my $exflag = 0;
  my $confirm= 0;
  my $res    = "";
  my $str    = "";
  my $star   = "";
  my $reply  = "";
  
  #-- semantic analysis
  my ($device,$verb,$reading,$value,$article,$reserve,$place,$cat) = Babble_Normalize($name,$sentence);
  $verb = "none" 
    if( !$verb );
  $reading = "none" 
    if( !$reading );
  
  if( defined(@parms) && $parms[0]=="testit"){
    $testit = 1;
    shift @parms;
    $exflag = $parms[0];
    shift @parms;
    for( my $i=0;$i<4;$i++){
      $parms[$i] = AttrVal($name,"testParm".$i,undef)
        if( !defined($parms[$i]) && AttrVal($name,"testParm".$i,undef));
    }   
    $str="[Babble_Normalize] ".$babble_tt->{"input"}.":  $sentence\n".
          "                       ".$babble_tt->{"result"}.": Category=$cat: ".
          $babble_tt->{"device"}."=$device ".$babble_tt->{"place"}."=$place ".
          $babble_tt->{"verb"}."=$verb ".$babble_tt->{"target"}."=$reading / $value";
  }
  
  #-- find command directly
  my $cmd = $hash->{DATA}{"command"}{$device}{$place}{$verb}{$reading}; 
  
  #-- not directly - but maybe we have an alias device ?
  if( !defined($cmd) || $cmd eq "" ){
    my $alidev  = $device;
    $alidev      =~s/_\d+$//g; 
    my $numalias = (defined($hash->{DATA}{"devsalias"}{$alidev})) ? int(@{$hash->{DATA}{"devsalias"}{$alidev}}) : 0;
    for (my $i=0;$i<$numalias ;$i++){
      my $ig = $hash->{DATA}{"devsalias"}{$alidev}[$i];
      my $bdev    = $hash->{DATA}{"devs"}[$ig];
      my $lbdev   = lc($bdev);
      next
        if( $lbdev eq $device );
      $cmd = $hash->{DATA}{"command"}{$lbdev}{$place}{$verb}{$reading};
      if( defined($cmd) && $cmd ne "" ){
        $device = $lbdev;
        last;
      }
    }
  }   
  
  #-- not directly - but maybe we have a device which is an extension of an alias device
  if( (!defined($cmd) || $cmd eq "") && defined($device) ){
    my $realdev  = $device;
    foreach my $stardev (keys %{$hash->{DATA}{"devsalias"}}){
      if(index($stardev,'*')!=-1){
        my $starrexp = $stardev;
        $starrexp    =~ s/\*/\(\.\*\)/;
        if( $realdev =~ /$starrexp/ ){
          $star = $1;
          $cmd = $hash->{DATA}{"command"}{$stardev}{$place}{$verb}{$reading};
          if( defined($cmd) && $cmd ne "" ){
            $device = $stardev;
            last;
          }
        }
      }
    }
  }   
  
  #-- command found after all
  if( defined($cmd) && $cmd ne "" ){
    #-- confirmation ?
    if( index($cmd,"\$CONFIRM") != -1 ){
      $confirm=1;
      $cmd =~ s/;;\$CONFIRM$//;
    } 
    #-- substitution
    $cmd =~ s/\$DEV/$device/g;
    $cmd =~ s/\$VALUE/$value/g;
    for(my $i=0;$i<int(@parms);$i++){
      $cmd =~ s/\$PARM$i/$parms[$i]/g;
    }
    if( $testit==0 || ($testit==1 && $exflag==1 )){
      Log3 $name,1,"[Babble_DoIt] Executing from hash: $device.$place.$verb.$reading/$value  ";
      my $contact = $hash->{DATA}{"devcontacts"}{$device}[2];
      my $fhemdev = $hash->{DATA}{"devcontacts"}{$device}[1];
      if( $contact == 0 ){
        $res = fhem($cmd);
      }else{
        my $ip    = AttrVal($name,"remoteFHEM".$contact,undef);
        my $token = AttrVal($name,"remoteToken".$contact,undef);
        my $func  = AttrVal($name,"remoteFunc".$contact,undef);  
        if( $func && $func ne "" ){
          $res = eval($func."(\"".$cmd."\")")
        }else{
          $cmd =~ s/\s/\%20/g;
          my $url    = "http://".$ip."/fhem?XHR=1&amp;fwcsrf=".$token."&amp;cmd.$fhemdev=$cmd";
          HttpUtils_NonblockingGet({
            url => $url,
            callback => sub($$$){} 
          });
        }
      }
      #-- confirm execution
      my $func  = AttrVal($name,"confirmFunc",undef);  
      if( $confirm ){
        if ($func && $func ne "" ){
          #-- substitution
          $func =~ s/\$DEV/$device/g;
          $func =~ s/\$VALUE/$value/g;
          for(my $i=0;$i<int(@parms);$i++){
            $func =~ s/\$PARM$i/$parms[$i]/g;
          }
          $res = fhem($func);   
        }else{
          Log3 $name,1,"[Babble_DoIt] requesting confirmation, but no attribute confirmFunc defined";
        }
      }
    }
    #-- what to do in conclusion
    if( $testit==0 ){
      return undef;   
    }else{
      $str .= "==> $cmd";
      return $str;
    }
 
  #-- no command found, acquire alternate text
  }else{
    #-- ChatBot available
    if( $rive==1  && AttrVal($name,"noChatBot",0) != 1){
      #-- Create a new RiveScript interpreter
      Babble_createRive($hash)
        if( !defined($hash->{Rive}) );
      my $rs = $hash->{Rive};
      $reply = $rs->reply ('localuser',$sentence);
      $reply = $babble_tt->{dnu}
        if ($reply eq "ERR: No Reply Matched");
    #-- no chatbot, use help text directly
    }else{
      $reply = defined($hash->{DATA}{"help"}{$device}) ? $hash->{DATA}{"help"}{$device} : "";
    }  
    #-- get help function
   my $func  = AttrVal($name,"helpFunc",undef);  
   if( $func && $func ne "" ){
      #-- substitution
      $func =~ s/\$HELP/$reply/g;
      $func =~ s/\$DEV/$device/g;
      $func =~ s/\$VALUE/$value/g;
      for(my $i=0;$i<int(@parms);$i++){
        $func =~ s/\$PARM$i/$parms[$i]/g;
      }    
      if( $testit==0 ){
        $res = eval($func);
        return "";
      }elsif($testit==1 && $exflag==1 ){
        $res = eval($func);
        return $str." ".$reply;
      }else{
        return $str." ".$func;
      }    
    #-- no command, testing, no execution 
    }elsif( $testit==1 ){
      Log 1,"[Babble_DoIt] Command $device.$place.$verb.$reading/$value undefined, reply = $reply";
      $str = $reply;
    }else{
      $str = "";
    }
    return $str;
  } 
}

########################################################################################
#
# Babble_checkattrs
# 
# Parameter name  = name of the babble definition
#
########################################################################################

sub Babble_checkattrs($){
   my ($hash) = @_;
   my $name = $hash->{NAME};
   
   CommandAttr (undef,$name." babbleVerbs schalt,schalte:schalten")
     if( AttrVal($name,"babbleVerbs","") eq "" );
   CommandAttr (undef,$name." babbleVerbParts zu auf ent wider ein an aus ab um")
     if( AttrVal($name,"babbleVerbParts","") eq "" ); 
   CommandAttr (undef,$name." babblePrepos von vom des der in im auf bei am")
     if( AttrVal($name,"babblePrepos","") eq "" );
   CommandAttr (undef,$name." babbleQuests  wie wo wann")
     if( AttrVal($name,"babbleQuests","") eq "" );
   CommandAttr (undef,$name." babbleArticles der die das den des dem zur")
     if( AttrVal($name,"babbleArticles","") eq "" );
   CommandAttr (undef,$name." babbleStatus Status Wert Wetter Zeit")
     if( AttrVal($name,"babbleStatus","") eq "" );
   CommandAttr (undef,$name." babbleWrites setzen ändern löschen")
     if( AttrVal($name,"babbleWrites","") eq "" );
   CommandAttr (undef,$name." babbleTimes heute morgen übermorgen nacht")
     if( AttrVal($name,"babbleTimes","") eq "" );
    #}else{
    #  $hash->{DATA}{"verbsi"}[0]="switching";
    #  $hash->{DATA}{"verbsicc"}[0][0]="switch";
    #  CommandAttr (undef,$name." babbleVerbParts re un"); 
    #  CommandAttr (undef,$name." babbleQuests by of in on at");
    #  CommandAttr (undef,$name." babbleAdverb how where when");
    #  CommandAttr (undef,$name." babbleArticles the to");
    #  CommandAttr (undef,$name." babbleStatus status value weather time");
    #}
}

#########################################################################################
#
# Babble_ModPlace
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_ModPlace($$$){

   my ($name,$place,$cmd) = @_;
   my $hash  = $defs{$name};
 
   #-- remove a place (parameter is just a number)
   if( $cmd == 0){
     splice(@{$hash->{DATA}{"splaces"}},$place,1);
   #-- add a place
   }else{
     push(@{$hash->{DATA}{"splaces"}},$place);
   }  
   
   CommandAttr (undef,$name." babblePlaces ".join(" ",@{$hash->{DATA}{"splaces"}})); 
   Babble_getplaces($hash,"new",undef);
   Babble_save($hash);
}

#########################################################################################
#
# Babble_ModVerb
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_ModVerb($$$$){

   my ($name,$verbi,$verbc,$cmd) = @_;
   my $hash   = $defs{$name};
   my $verbi2 = $verbi;
   my $verbc2 = $verbc;
   
  # %{$hash->{DATA}{"verbs"}}     = hash of all verb => infinitive_verb pairs
  # @{$hash->{DATA}{"verbsi"}}    = array of all infinite verbs
  # @{$hash->{DATA}{"verbsicc"}}  = array of all arrays of conjugated verbs
  
   #-- remove a verb - verbi is only a number,verbc is empty
   if( $cmd == 0){
     $verbi2  = $hash->{DATA}{"verbsi"}[$verbi];
     $verbc2  = join(',',$hash->{DATA}{"verbsicc"}[$verbi]);
     splice(@{  $hash->{DATA}{"verbsi"}},$verbi,1);
     splice(@{  $hash->{DATA}{"verbsicc"}},$verbi,1);
   
    #-- add a verb
   }elsif( $cmd==1) {
     push(@{$hash->{DATA}{"verbsi"}},$verbi);
     my @cc=split(',',$verbc);
     push(@{$hash->{DATA}{"verbsicc"}},\@cc);
   #-- modify a verb - verbi is only a number,verbc is a list of conjugations
   }else{
     $verbi2  = $hash->{DATA}{"verbsi"}[$verbi];
     my @cc=split(',',$verbc);
     $hash->{DATA}{"verbsicc"}[$verbi]=\@cc;
   }
   
   #-- recreate attribute
   my $att = "";
   for(my $i=0;$i<int(@{ $hash->{DATA}{"verbsi"}});$i++){
     $att .= join(',',@{ $hash->{DATA}{"verbsicc"}[$i]}).":".$hash->{DATA}{"verbsi"}[$i]." ";
   }
   CommandAttr (undef,$name." babbleVerbs ".$att); 
   Babble_getverbs($hash,"new",undef);
   Babble_save($hash);
}

########################################################################################
#
# Babble_ModHlp
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_ModHlp($$$){

   my ($name,$bdev,$txt) = @_;
   my $hash   = $defs{$name};
   
   #-- lower case characters
   $bdev   = lc($bdev);
   $hash->{DATA}{"help"}{$bdev}=$txt;
}

########################################################################################
#
# Babble_ModCmd
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_ModCmd($$$$$$){

   my ($name,$bdev,$place,$verb,$target,$cmd) = @_;
   my $hash   = $defs{$name};
   
   #-- lower case characters
   $bdev   = lc($bdev);
   if( defined($target) && $target ne "" ){ 
     $target  = lc($target);
     delete($hash->{DATA}{"command"}{$bdev}{"none"}{"none"}{"none"})
   }else{
     $target="none"
   };
   if( defined($verb) && $verb ne "" ){ 
     $verb  = lc($verb);
     delete($hash->{DATA}{"command"}{$bdev}{"none"}{"none"})
   }else{
     $verb="none"
   };
   if( defined($place) && $place ne "" ){ 
     $place  = lc($place);
     delete($hash->{DATA}{"command"}{$bdev}{"none"})
   }else{
     $place="none"
   };

   #Log 1,"[Babble_ModCmd] Setting in hash: $bdev.$place.$verb.$target";
   $hash->{DATA}{"command"}{$bdev}{$place}{$verb}{$target}=$cmd;
}

########################################################################################
#
# Babble_RemCmd
# 
# Parameter name  = name of the babble definition
#
#########################################################################################

sub Babble_RemCmd($$$$$){

   my ($name,$bdev,$place,$verb,$target) = @_;
   my $hash   = $defs{$name};
   
   #-- lower case characters
   $bdev   = lc($bdev);
   $place  = lc($place);
   $verb   = lc($verb);
   $target = lc($target);
   
   $place="none"
     if( $place eq "");
   $verb="none"
     if( $verb eq "");
   $target="none"
     if( $target eq "");
     
   Log3 $name, 1,"[Babble_RemCmd] Deleting from hash: $bdev.$place.$verb.$target => ".$hash->{DATA}{"command"}{$bdev}{$place}{$verb}{$target};
   delete($hash->{DATA}{"command"}{$bdev}{$place}{$verb}{$target});
}

#########################################################################################
#
# Babble_getids - Helper function to assemble id list
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_getids($$) {
  my ($hash,$type) = @_;
  
  my $name = $hash->{NAME};
  my $res  = "";

  # @{$hash->{DATA}{"ids"}}    = array of all ids
  my @ids;
  
  #--generate a new list
  if( $type eq "new" ){
    push(@ids,$babble_tt->{"hallo"});
    #-- get ids from attribute
    push(@ids,split(' ',AttrVal($name, "babbleIds", "")));
   
    $hash->{DATA}{"re_ids"} = lc("((".join(")|(",@ids)."))"); 
    return;
  #-- just do something with the current list
  }else{
    return undef;
  }
}

#########################################################################################
#
# Babble_getdevs - Helper function to assemble devices list
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_getdevs($$) {
  my ($hash,$type) = @_;
  
  my $name = $hash->{NAME};
          
  # @{$hash->{DATA}{"devs"}}         = array of all Babble devices
  # %{$hash->{DATA}{"devcontacts"}}  = hash of all arrays of contact data (Babble Device, FHEM Device, remote type)
  my @remotes  = ();  # intermediate array of all remote groups of Babble device/FHEM device/contact data
  my @devs     = ();  # intermediate array of all Babble devices with _number appendix 
  my %devshash = ();  # intermediate hash of all Babble devices with _number appendix (for checking existence of name) 
  my %devsalias= ();  # hash of arrays of all Babble device aliases without _number appendix
  my @devcs    = ();  # intermediate array of all contact data for a certain device
 
  my ($bdev,$lbdev,$sbdev,$fhemdev,$contact);
  
  #--generate a new list
  if( $type eq "new" ){
    my $ig = 0;
    $hash->{DATA}{"devs"}=();
    $hash->{DATA}{"devcontacts"}=();
    #-- local Babble devices raw data
    foreach my $fhemdev (sort keys %defs ) {
       $bdev  = AttrVal($fhemdev, "babbleDevice",undef);
       if( defined($bdev) ) { 
         Log3 $name,5,"[Babble_getdevs] finds local FHEM device $fhemdev with babbleDevice=$bdev";
         $lbdev = lc($bdev);
         $sbdev = $lbdev;
         if(exists($devshash{$lbdev})) {
           Log3 $name,1,"[Babble_getdevs] Warning: local FHEM device $fhemdev has duplicate babbleDevice=$bdev, is ignored. You need to specifiy ".$bdev."_<number> instead.";
         }else{  
           Log3 $name,5,"[Babble_getdevs] local FHEM device $fhemdev with babbleDevice=$bdev entered into hashes with ig=$ig";
           $devs[$ig]        = $bdev;
           #-- take away trailing _<num>
           $sbdev  =~ s/_\d+$//;
           #-- put into hash
           $hash->{DATA}{"devs"}[$ig]              = $bdev;
           $hash->{DATA}{"devcontacts"}{$lbdev}[0] = $bdev;
           $hash->{DATA}{"devcontacts"}{$lbdev}[1] = $fhemdev;
           $hash->{DATA}{"devcontacts"}{$lbdev}[2] = 0;
           $devshash{$lbdev} = 1;
           if( !defined($devsalias{$sbdev}) ){
             $devsalias{$sbdev}[0]=$ig;
           }else{
             push(@{$devsalias{$sbdev}},$ig);
           }
           $ig++;
           #-- safeguard against empty device
           if( !defined($hash->{DATA}{"command"}{$lbdev})){
             Log3 $name,1,"[Babble_getdevs] No entry in command table under $lbdev for local FHEM device $fhemdev with attribute babbleDevice=$bdev";
             Babble_ModCmd($name,$sbdev,undef,undef,undef,undef)
           }  
         }
       }
    }
    #-- get devices from attribute
    push(@remotes,split(' ',AttrVal($name, "babbleDevices", "")));
    for (my $i=0;$i<int(@remotes);$i++){
      ($bdev,$fhemdev,$contact) =split(':',$remotes[$i]);
      $lbdev = lc($bdev);
      $sbdev = $lbdev;
      #-- take away trailing _<num>
      $sbdev  =~ s/_\d+$//;
      if(exists($devshash{$lbdev})) {
        Log3 $name,1,"[Babble_getdevs] Warning: remote FHEM device $fhemdev has duplicate babbleDevice=$bdev, is ignored. You need to specifiy ".$bdev."_<unique number> instead.";
      }else{
        Log3 $name,5,"[Babble_getdevs] remote FHEM device $fhemdev with babbleDevice=$bdev entered into hashes with ig=$ig";
        $hash->{DATA}{"devs"}[$ig]              = $bdev;
        $hash->{DATA}{"devcontacts"}{$lbdev}[0] = $bdev;
        $hash->{DATA}{"devcontacts"}{$lbdev}[1] = $fhemdev;
        $hash->{DATA}{"devcontacts"}{$lbdev}[2] = $contact;
        $devshash{$lbdev} = 1;
        if( !defined($devsalias{$sbdev}) ){
          $devsalias{$sbdev}[0]=$ig;
        }else{
          push(@{$devsalias{$sbdev}},$ig);
        }
        $ig++;
        #-- safeguard against empty device
        if( !defined($hash->{DATA}{"command"}{$lbdev})){
          Log 1,"[Babble_getdevs] No entry in command table under $lbdev for remote FHEM device $fhemdev (remote $contact) with attribute babbleDevice=$bdev";
          Babble_ModCmd($name,$sbdev,undef,undef,undef,undef)
        }  
      }
    }
    #-- hash of devices without _<num>
    %{$hash->{DATA}{"devsalias"}}  = %devsalias;
    
    #-- regex list for devices to check for validity 
    $hash->{DATA}{"re_devs"} = lc("((".join(")|(",@{$hash->{DATA}{"devs"}})."))")
      if( defined($hash->{DATA}{"devs"}) );
  
    #-- cleanup commands list for obsolete devices
    if( defined( $hash->{DATA}{"command"} )){
      foreach my $device (keys %{$hash->{DATA}{"command"}}){
        if( !defined($hash->{DATA}{"devcontacts"}{$device}) ){ 
          delete($hash->{DATA}{"command"}{$device});
        }
      }
    }
  }
}

#########################################################################################
#
# Babble_antistupidity - check for stupid naming of devices or rooms
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_antistupidity($) {
  my ($hash) = @_;
  
  my $name  = $hash->{NAME};
  my $regexp = $hash->{DATA}{"re_places"};
  my $devs = $hash->{DATA}{"devs"};
  return 
    if( !defined($regexp) || !defined($devs) );
  my $imax = int(@{$hash->{DATA}{"devs"}});
  for( my $i=0; $i<$imax; $i++){
    my $dev = lc($hash->{DATA}{"devs"}[$i]);
    Log 1,"[Babble] Baaaaah ! It is not a good idea to name a device $dev similar to a place in Babble"
      if( $dev =~ /$regexp/ );
  }
  return undef; 
}

#########################################################################################
#
# Babble_gethelp - Helper function  
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_gethelp($$) {
  my ($hash,$bdev) = @_;
  
  my $name  = $hash->{NAME};
  my $lbdev = lc($bdev);
   
}

#########################################################################################
#
# Babble_getplaces - Helper function to assemble places list
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_getplaces($$$) {
  my ($hash,$type,$sel) = @_;
  
  my $name = $hash->{NAME};
  
  # @{$hash->{DATA}{"rooms"}}   = array of all rooms that are not hidden
  # @{$hash->{DATA}{"splaces"}} = array of all special places for Babble
  # @{$hash->{DATA}{"places"}}  = array of all places for Babble = rooms + special
  my %rooms;    # intermediate hash of all rooms
  my @special;  # intermediate array of all special places for Babble
  my @places;   # intermediate array of rooms/all babble places
  
  my $nop = AttrVal($name,"babbleNotPlaces","");
 
  #--generate a new list
  if( $type eq "new" ){
    #-- code lifted from FHEMWEB
    %rooms = ();  # Make a room  hash
    my $hre = AttrVal($FW_wname, "hiddenroomRegexp", "");
    foreach my $d (keys %defs ) {
      #next if(IsIgnored($d));
      foreach my $r (split(",", AttrVal($d, "room", "Unsorted"))) {
        next if($hre && $r =~ m/$hre/);
        next if($r eq "Unsorted" || $r eq "hidden" || $r eq $babblehiddenroom || $r eq $babblepublicroom );
        next if (index($nop, $r) != -1);
        $rooms{$r}{$d} = 1;
      }
    }
    if(AttrVal($FW_wname, "sortRooms", "")) { # Slow!
      my @sortBy = split( " ", AttrVal( $FW_wname, "sortRooms", "" ) );
      my %sHash;                                                       
      map { $sHash{$_} = FW_roomIdx(\@sortBy,$_) } keys %rooms;
      @places = sort { $sHash{$a} cmp $sHash{$b} } keys %rooms;
    } else {
      @places = sort keys %rooms;
    }
    @{$hash->{DATA}{"rooms"}}=@places;
  
    #-- append special places from attribute
    @special = split(' ',AttrVal($name, "babblePlaces", ""));
    @{$hash->{DATA}{"splaces"}} = @special;
    push(@places, @special);
    @{$hash->{DATA}{"places"}}  = @places;
    $hash->{DATA}{"re_places"}  = lc("((".join(")|(",@places)."))");
  
    Babble_save($hash);
    return;
  #-- just do something with the current list
  }elsif( $type eq "html" ){
    @places=@{$hash->{DATA}{"places"}};
    #-- output
    if( !defined($sel) ){
      return "<option></option><option>".join("</option><option>",@places)."</option>";
    }else{
      my $ret = ($sel eq "none") ? '<option selected="selected">' : '<option>';
      $ret .= '</option>';
      for( my $i=0;$i<int(@places);$i++){
        $ret .= (lc($sel) eq lc($places[$i]) ) ? '<option selected="selected">' : '<option>';
        $ret .= $places[$i].'</option>';
      }
      return $ret;
    }
    
  }else{
    return undef;
  }
}

#########################################################################################
#
# Babble_getverbs - Helper function to assemble verbs list
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_getverbs($$$) {
  my ($hash,$type,$sel) = @_;
  
  my $name = $hash->{NAME};
  my $res  = "";

  # %{$hash->{DATA}{"verbs"}}      = hash of all verb => infinitive_verb pairs
  # @{$hash->{DATA}{"verbsi"}}    = array of all infinite verbs
  # @{$hash->{DATA}{"verbsicc"}}  = array of all arrays of conjugated verbs
  my @groups;     # intermediate array of all conjugated_verb/infinitive_verb groups
  my @verbsic;    # intermediate array of all conjugations for a certain verb
 
  #--generate a new list
  if( $type eq "new" ){
    #-- get verbs from attribute
    push(@groups,split(' ',AttrVal($name, "babbleVerbs", "")));
    for (my $i=0;$i<int(@groups);$i++){
      my ($vc,$vi) =split(':',$groups[$i]);
      $hash->{DATA}{"verbs"}{$vi} = $vi;
      $hash->{DATA}{"verbsi"}[$i] = $vi;
      @verbsic=split(',',$vc);
      for (my $j=0;$j< int(@verbsic);$j++){
        my $vcc = $verbsic[$j];
        $hash->{DATA}{"verbs"}{$vcc}      = $vi;
        $hash->{DATA}{"verbsicc"}[$i][$j] = $vcc
      } 
    }
    $hash->{DATA}{"re_verbsi"} = "(?P<verbsi>(".lc( join(")|(",@{$hash->{DATA}{"verbsi"}}))."))"; 
    $hash->{DATA}{"re_verbsc"} = lc("((".join(")|(",(keys %{$hash->{DATA}{"verbs"}}))."))");
    return;
  #-- just do something with the current list
  }elsif( $type eq "html" ){
    my @verbsi=@{$hash->{DATA}{"verbsi"}};
    my $fnd = 0;
    #-- output
    if( !defined($sel) ){
      return "<option></option><option>".join("</option><option>",@verbsi)."</option>";
    }else{
      my $ret = ($sel eq "none") ? '<option selected="selected">' : '<option>';
      $ret .= '</option>';
      for( my $i=0;$i<int(@verbsi);$i++){
        if( lc($sel) eq lc($verbsi[$i]) ) {
          $ret .=  '<option selected="selected">';
          $fnd = 1;
        }else{
          $ret .=  '<option>';
        }
        $ret .= $verbsi[$i].'</option>';
      }
      #if( $fnd==0 ){
      #  $ret .= '<option selected="selected" value="unknown">'.$babble_tt->{"unknown"}.'</option>';
      #}
      return $ret;
    }
    
  }else{
    return undef;
  }
}

#########################################################################################
#
# Babble_getwords - Helper function to assemble list of other word classes
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Babble_getwords($$$$) {
  my ($hash,$class,$type,$sel) = @_;
  
  my $name = $hash->{NAME};
  my $res  = "";
  my @words;
  
  if( $type eq "new" ){
    if(     $class eq "verbparts" || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleVerbParts", ""));
      @{$hash->{DATA}{"verbparts"}} = @words;
      $hash->{DATA}{"re_verbparts"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "prepos"    || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babblePrepos", ""));
      @{$hash->{DATA}{"prepos"}} = @words;
      $hash->{DATA}{"re_prepos"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "articles"  || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleArticles", ""));
      @{$hash->{DATA}{"articles"}} = @words;
      $hash->{DATA}{"re_articles"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "status"    || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleStatus", ""));
      @{$hash->{DATA}{"status"}} = @words;
      $hash->{DATA}{"re_status"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "times"    || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleTimes", ""));
      @{$hash->{DATA}{"times"}} = @words;
      $hash->{DATA}{"re_times"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "quests"  || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleQuests", ""));
      @{$hash->{DATA}{"quests"}} = @words;
      $hash->{DATA}{"re_quests"} = lc("((".join(")|(",@words)."))");
    }
    if( $class eq "writes"    || $class eq "all" ) {
      @words=split(' ',AttrVal($name, "babbleStatus", ""));
      @{$hash->{DATA}{"writes"}} = @words;
      $hash->{DATA}{"re_writes"} = lc("((".join(")|(",@words)."))");
    }
    delete($hash->{DATA}{"pronouns"});
    Babble_save($hash);
    return;
    
  #-- just do something with the current list
  }elsif( $class eq "targets" && $type eq "html" ){
    my @targets=@{$hash->{DATA}{"status"}};
    push(@targets,"----");
    push(@targets,@{$hash->{DATA}{"verbparts"}});
    #-- output
    if( !defined($sel) ){
      return "<option></option><option>".join("</option><option>",@targets)."</option>";
    }else{
      my $ret = ($sel eq "none") ? '<option selected="selected">' : '<option>';
      $ret .= '</option>';
      for( my $i=0;$i<int(@targets);$i++){
        $ret .= (lc($sel) eq lc($targets[$i]) ) ? '<option selected="selected">' : '<option>';
        $ret .= $targets[$i].'</option>';
      }
      return $ret;
    }
    
  }else{
    return undef;
  }
}

#########################################################################################
#
# Babble_Html - returns HTML code for the babble page
# 
# Parameter name = name of the babble definition
#
#########################################################################################

sub Babble_Html($)
{
	my ($name) = @_; 

    my $ret = "";
    my $rot = "";
 
    my $hash = $defs{$name};
    my $id   = $defs{$name}{NR};
    
    if( !defined($babble_tt) ){
      #-- readjust language
      my $lang = AttrVal("global","language","EN");
      if( $lang eq "DE"){
        $babble_tt = \%babble_transtable_DE;
      }else{
        $babble_tt = \%babble_transtable_EN;
      }
    }
    Babble_checkattrs($hash);
    Babble_getids($hash,"new");
    Babble_getdevs($hash,"new");
    
    my $pllist = Babble_getplaces($hash,"new",undef);
    Babble_antistupidity($hash);
    
    my $pmlist="";
    for(my $i=0;$i<int(@{$hash->{DATA}{"splaces"}});$i++){
      $pmlist .= "<a onclick=\"babble_modplace('$name','".$hash->{DATA}{"splaces"}[$i]."',$i)\">".$hash->{DATA}{"splaces"}[$i]."</a> ";
    }
    
    my $vblist = Babble_getverbs($hash,"new",undef);
    my $vmlist="";
    for(my $i=0;$i<int(@{$hash->{DATA}{"verbsi"}});$i++){
      my $vi      = $hash->{DATA}{"verbsi"}[$i];
      my $vmilist = join(',',@{$hash->{DATA}{"verbsicc"}[$i]});
      $vmlist .= "<a onclick=\"babble_modverb('$name','".$vi."','".$vmilist."',$i)\">".$vi."</a> ";
    }
 
    my $vpmlist = Babble_getwords($hash,"all","new",undef);
    
    #-- update state display
    #readingsSingleUpdate( $hash, "state", Babble_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 1 );
    
    #--
    my $lockstate = ($hash->{READINGS}{lockstate}{VAL}) ? $hash->{READINGS}{lockstate}{VAL} : "unlocked";
    my $showhelper = ($lockstate eq "unlocked") ? 1 : 0; 

    #--
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/babble.js\"></script><script type=\"text/javascript\">\n";
   
    $ret .= "var tt_add='".$babble_tt->{"add"}."';\n";
    $ret .= "var tt_added='".$babble_tt->{"added"}."';\n";
    $ret .= "var tt_remove='".$babble_tt->{"remove"}."';\n";
    $ret .= "var tt_removed='".$babble_tt->{"removed"}."';\n";
    $ret .= "var tt_modify='".$babble_tt->{"modify"}."';\n";
    $ret .= "var tt_modified='".$babble_tt->{"modified"}."';\n";
    $ret .= "var tt_cancel='".$babble_tt->{"cancel"}."';\n";
    $ret .= "var tt_place='".$babble_tt->{"place"}."';\n";
    $ret .= "var tt_verb='".$babble_tt->{"verb"}."';\n";
    $ret .= "var newplace = '<select name=\"d_place\">".Babble_getplaces($hash,"html","none")."</select>';\n";
    $ret .= "var newverbs = '<select name=\"d_verb\">".Babble_getverbs($hash, "html","none")."</select>';\n";
    $ret .= "var newtargs = '<select name=\"d_verbpart\">".Babble_getwords($hash,"targets","html","none")."</select>';\n";
    $ret .= "var newfield = '<input type=\"text\" name=\"d_command\" size=\"30\" maxlength=\"512\" value=\"FHEM command\">';\n";
    $ret .= "var newcheck = '<input type=\"checkbox\" name=\"d_confirm\">';\n";
 
    $rot .= "</script>\n";
    
    $rot .= "<table class=\"roomoverview\">\n";
    
    #-- test table
    $rot .= "<tr><td colspan=\"3\"><div class=\"devType\">".$babble_tt->{"babbletest"}."</div></td></tr>";
    $rot .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"testtable\">\n"; 
    $rot .= "<tr class=\"odd\" ><td class=\"col1\">".$babble_tt->{"input"}.": <input type=\"text\" id=\"d_testcommand\" size=\"60\" maxlength=\"512\"/></td>\n".
                               "<td class=\"col1\" style=\"text-align:left\"><input type=\"button\" id=\"b_testit\" onclick=\"babble_testit('".$name."')\" value=\"".$babble_tt->{"test"}."\" style=\"width:100px;\"/</td></tr>\n".
            "<tr class=\"even\"><td class=\"col1\">".$babble_tt->{"result"}.": <div id=\"d_testresult\"></div></td>\n".
                               "<td class=\"col1\" style=\"text-align:left\"><input type=\"checkbox\" id=\"b_execit\">".$babble_tt->{"exec"}."</td></tr>\n";
    $rot .= "</table></td></tr>";
    
    #-- places table
    my $tblrow=1;
    $rot .= "<tr><td colspan=\"3\"><div class=\"devType\">".$babble_tt->{"babbleplaces"}."</div></td></tr>";
    $rot .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"placestable\">\n"; 
    $rot .= "<tr class=\"odd\"><td class=\"col1\">".$babble_tt->{"rooms"}."</td><td class=\"col1\" colspan=\"2\" style=\"horizontal-align:left\">".join(" ",@{$hash->{DATA}{"rooms"}})."</td></tr>\n".
            "<tr class=\"even\"><td class=\"col1\">".$babble_tt->{"places"}."</td><td class=\"col1\" colspan=\"2\" style=\"align:left\">".$pmlist."</td></tr>\n".
            "<tr class=\"odd\"><td class=\"col1\"><input type=\"button\" id=\"b_addplace\" onclick=\"babble_addplace('".$name."')\" value=\"".$babble_tt->{"add"}."\" style=\"width:100px;\"/>".
            "<div id=\"b_chgplacediv\" style=\"width:100px\"></div></td>".
            "<td class=\"col3\" colspan=\"2\"><input type=\"text\" id=\"b_newplace\" size=\"40\" maxlength=\"120\" ></td></tr>\n";
    $rot .= "</table></td></tr>";
    
    #-- verbs table
    $tblrow=1;
    $rot .= "<tr><td colspan=\"3\"><div class=\"devType\">".$babble_tt->{"babbleverbs"}."</div></td></tr>";
    $rot .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"verbstable\">\n"; 
    $rot .= "<tr class=\"odd\"><td class=\"col1\">".$babble_tt->{"verbs"}."</td><td class=\"col1\" colspan=\"2\" style=\"align:left\">".$vmlist."</td></tr>\n".
            "<tr class=\"even\"><td class=\"col1\"></td>".
            "<td class=\"col3\">".$babble_tt->{"conjugations"}."</td><td class=\"col3\">".$babble_tt->{"infinitive"}."</td></tr>\n".
            "<tr class=\"odd\"><td class=\"col1\"><input type=\"button\" id=\"b_addverb\" onclick=\"babble_addverb('".$name."')\" value=\"".$babble_tt->{"add"}.
                        "\" style=\"width:100px;\"/><div id=\"b_chgverbdiv\" style=\"width:100px\"></div></td>".
            "<td class=\"col3\"><input type=\"text\" id=\"b_newverbc\" size=\"20\" maxlength=\"120\" ></td><td class=\"col3\"><input type=\"text\" id=\"b_newverbi\" size=\"20\" maxlength=\"120\" ></td></tr>\n";
    $rot .= "</table></td></tr>";
   
    #-- devices table
    $tblrow      = 0;
    my $ig       = 0;
    my $devcount = 0;
    my @devrows  = ();
   
    my($devrow,$ip,$ipp);
    $rot .= "<tr><td colspan=\"3\"><div class=\"devType\">".$babble_tt->{"babbledev"}."</div></td></tr>";
    $rot .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"devstable\">\n"; 
    $rot .= "<tr class=\"odd\"><td class=\"col1\" style=\"text-align:left;padding-right:10px;\">".$babble_tt->{"fhemname"}."</td><td class=\"col2\" style=\"text-align:left\">".$babble_tt->{"device"}."</td>\n".
            "<td class=\"col3\">".$babble_tt->{"place"}."</td><td class=\"col3\">".$babble_tt->{"verb"}."</td><td class=\"col3\">".$babble_tt->{"target"}."</td>\n".
            "<td class=\"col3\">".$babble_tt->{"action"}."</td><td class=\"col3\">".$babble_tt->{"confirm"}."</td><td class=\"col3\"><input type=\"button\" id=\"d_save\" onclick=\"babble_savedevs('".$name."')\" value=\"".$babble_tt->{"save"}.
                        "\" style=\"width:100px;\"/></td></tr>\n";
    #-- loop over all unique devices to get some sorting
    if( defined($hash->{DATA}{"devsalias"}) ){
      for my $alidev (sort keys %{$hash->{DATA}{"devsalias"}}) {
        #-- number of devices with this unique
        my $numalias = int(@{$hash->{DATA}{"devsalias"}{$alidev}});
        for (my $i=0;$i<$numalias ;$i++){
          $ig = $hash->{DATA}{"devsalias"}{$alidev}[$i];
          my $bdev    = $hash->{DATA}{"devs"}[$ig];
          my $lbdev   = lc($bdev);
          my $sbdev   = $bdev;
          $sbdev      =~s/_\d+$//g; 
          my $lsbdev  = $lbdev;
          $lsbdev     =~s/_\d+$//g; 
          my $hlp     = $hash->{DATA}{"help"}{$lbdev};
          if( !defined($hlp) ){
            $hlp = $babble_tt->{"speak"}.": ".$sbdev.", ".$babble_tt->{"followedby"}." ";
            #-- places ?
            if( join('_',(keys %{$hash->{DATA}{"command"}{$lbdev}})) ne "none"){;
              $hlp .= $babble_tt->{"placespec"}.", ".$babble_tt->{"followedby"}." ";
            }
          }
          my $checked;
          my $fhemdev = $hash->{DATA}{"devcontacts"}{$lbdev}[1];
          my $contact = $hash->{DATA}{"devcontacts"}{$lbdev}[2];
           
          $devcount++;  
          $tblrow++;
          $ig++;
          $devrow=1;
          #-- headline for device 
          $rot .= sprintf("<tr class=\"%s\" style=\"padding-right:25px;\">", ($tblrow&1)?"odd":"even");
          $rot .= "<td width=\"240\" class=\"col1\" style=\"text-align:left;padding-right:10px; border-top:1px solid gray\">";
          #-- local link to device
          if( $contact == 0 ){
            $rot .= "<a href=\"$FW_ME?detail=$fhemdev\">$fhemdev</a>";
          #-- remote link to device
          }else{
            $ip  = AttrVal($name,"remoteFHEM".$contact,undef);
            $ipp = $ip =~ s/:.*//sr;
            if( $ip ){
              $rot .= "<a href=\"http://".$ip."/fhem?detail=$fhemdev\">$fhemdev</a> ($ipp)";
            }else{
              $rot .= $fhemdev." (R$contact)";
            }
          }
        
          $rot .= "</td>\n<td class=\"col2\" style=\"text-align:left;  border-top:1px solid gray;padding:2px\">$bdev</td>\n";  
          $rot .= "</td>\n<td class=\"col2\" style=\"text-align:right; border-left:1px dotted gray; border-bottom: 1px dotted gray;border-top:1px solid gray;border-bottom-left-radius:10px; padding:2px\">".$babble_tt->{"helptext"}."&rarr;</td>";
          #-- helptext
          $rot .= "<td class=\"col3\" colspan=\"4\" style=\"text-align:left;border-right:1px dotted gray;border-bottom: 1px dotted gray;border-top:1px solid gray;border-bottom-right-radius:10px; padding:2px;\">";        
          $rot .= "<input type=\"text\" name=\"d_help\" size=\"51\" maxlength=\"1024\" value=\"".$hlp."\"/></td>"; 
          $rot .= "<td style=\"text-align:left;padding-right:10px; border-top:1px solid gray\">".
                  "<input type=\"button\" id=\"d_addrow\" onclick=\"babble_addrow('".$name."',$devcount,$tblrow)\" value=\"".$babble_tt->{"add"}."\" style=\"width:100px;\"/></td></tr>\n";#$tblrow-$devcount.$devrow
                  
          #my $json   = JSON->new->utf8;
          #my $jhash0 = eval{ $json->encode( $hash->{DATA}{"command"}{$lbdev} ) };
          #Log3 $name, 1, "\n\n\n\n $lbdev ========>".Dumper($jhash0);

          foreach my $place (keys %{$hash->{DATA}{"command"}{$lbdev}}){
            foreach my $verb (keys %{$hash->{DATA}{"command"}{$lbdev}{$place}}){
              foreach my $target (keys %{$hash->{DATA}{"command"}{$lbdev}{$place}{$verb}}){
                my $cmd     = $hash->{DATA}{"command"}{$lbdev}{$place}{$verb}{$target};
                if( index($cmd,"\$CONFIRM") != -1 ){
                  $checked = "checked=\"checked\" ";
                  $cmd =~ s/;;\$CONFIRM$//;
                }else{
                  $checked="";
                }
                $tblrow++;
                $devrow++;
              
                $rot .= sprintf("<tr class=\"%s\" style=\"padding-right:25px;\"><td></td><td></td>\n", ($tblrow&1)?"odd":"even");
               
                $pllist   = Babble_getplaces($hash,"html",$place);
                $vblist   = Babble_getverbs($hash, "html",$verb);
                $vpmlist  = Babble_getwords($hash,"targets","html",$target);
               
                $rot .= "<td class=\"col3\"><select name=\"d_place\">".$pllist."</select></td>".
                        "<td class=\"col3\"><select name=\"d_verb\">".$vblist."</select></td>".
                        "<td class=\"col3\"><select name=\"d_verbpart\">".$vpmlist."</select></td>\n";  
                $rot .= "<td class=\"col3\"  style=\"text-align:left;padding:2px\"><input type=\"text\" name=\"d_command\" size=\"30\" maxlength=\"512\" value=\"".$cmd."\"/></td>";
                $rot .= "<td class=\"col3\"><input type=\"checkbox\" name=\"d_confirm\"$checked</td>";
                $rot .= "<td><input type=\"button\" id=\"d_remrow\" onclick=\"babble_remrow('".$name."',$devcount,$tblrow)\" value=\"".$babble_tt->{"remove"}."\" style=\"width:100px;\"/></td></tr>\n";#$tblrow-$devcount.$devrow
              }
           }
        }
        push(@devrows,$devrow)
      }
    }
    $rot .= "</table></td></tr>";
  }
  $rot .= "</table>";

  $ret .= "var devrows=[".( (@devrows) ? join(",",@devrows) : "")."];\n";
  $ret .= "var devrowstart=devrows;\n";

  return $ret.$rot;
}

1;

=pod
=item helper
=item summary for speech control of FHEM devices 
=begin html

   <a name="Babble"></a>
        <h3>Babble</h3>
        <ul>
        <p> FHEM module for speech control of FHEM devices</p>
         <a name="babbleusage"></a>
        <h4>Usage</h4>
        See <a href="http://www.fhemwiki.de/wiki/Modul_babble">German Wiki page</a>
        <a name="babbledefine"></a>
        <br/>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; babble</code>
            <br />Defines the Babble device. </p>
        <a name="babbleset"></a>
        Notes: <ul>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
         <li>This module needs the JSON package.</li>
         <li>Only when the chatbot functionality of RiveScript is required, the RiveScript module must be installed as well, see https://github.com/aichaos/rivescript-perl</li>
         </ul>
         <h4>Usage</h4>
          To use this module, call the Perl function <code>Babble_DoIt("&lt;name&gt;","&lt;sentence&gt;"[,&lt;parm0&gt;,&lt;parm1&gt;,...])</code>. 
          &lt;name&gt; is the name of the Babble device,  &lt;parm0&gt; &lt;parm1&gt; are arbitrary parameters. 
          
          The module will analyze the sentence passed an isolate a device to be addressed, a place identifier, 
          a verb, a target and its value from the sentence passed.
          
          If a proper command has been stored with device, place, verb and target, it will be subject to substitutions and then will be executed. 
          In these substitutions, a string $VALUE will be replaced by the value for the target reading, a string $DEV will be replaced by the device name identified by Babble, 
          and strings $PARM[0|1|2...] will be replaced by the 
          corresponding parameters passed to the function <code>Babble_DoIt</code>   
          <ul>
          <li>If no stored command ist found, the sentence is passed to the local RiveScript interpreter if present</li>
          <li>To have a FHEM register itself as a Babble Device, it must get an attribute value <code>babbleDevice=&lt;name&gt;</code>. The <i>name</i> parameter must either be 
          unique to the Babble system, or it muts be of the form <code>&lt;name&gt;_&lt;digits&gt;</code></li>
          <li>Devices on remote FHEM installations are defined in the <code>babbleDevices</code> attribute, see below</li>
          </ul>
        <h4>Set</h4>
        <ul>
            <li><a name="babble_lock">
                    <code>set &lt;name&gt; locked</code><br />
                    <code>set &lt;name&gt; unlocked</code>
                </a>
                <br />sets the lockstate of the babble module to <i>locked</i> (i.e., babble setups
                may not be changed) resp. <i>unlocked</i> (i.e., babble setups may be changed>)</li>
            <li><a name="babble_save">
                    <code>set &lt;name&gt; save|restore</code>
              </a>
                <br />Manually save/restore the babble to/from the external file babbleFILE (save done automatically at each state modification, restore at FHEM start)</li>
            <li><a name="babble_rivereload">
                    <code>set &lt;name&gt; rivereload</code>
                </a>
                <br />Reload data for RiveScript Interpreter</li>
            <li><a name="babble_test">
                    <code>set &lt;name&gt; test</code>
                </a>
                <br />Run a few test cases for normalization</li>
        </ul>
        </ul>
        <a name="babbleget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="babble_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>
             <li><a name="babble_tokens"></a>
                <code>get &lt;name&gt; tokens</code>
                <br />Obtain fresh csrfToken from remote FHEM installations (needed after restart of remote FHEM)</li>
        </ul>
        <a name="babbleattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="babbleDevices"><code>attr &lt;name&gt; babbleDevices [&lt;babble devname&gt;:&lt;FHEM devname&gt;:1|2|3]* </code></a>
                <br />space separated list of <i>remote</i> FHEM devices, each as a group separated by ':' consisting of
                <ul><li>a Babble device name</li>
                <li>a FHEM Device name</li>
                <li>an integer 1..3, indication which of the <i>remoteFHEM</i> functions to be called</li>
                </ul>
                The Babble device name may contain a <b>*</b>-character. If this is the case, it will be considered a regular expression, with the star replaced by <b>(.*)</b>. 
                When using Babble with a natural language sentence whose device part matches this regular expression, the character group addressed by the star sequence is placed in the variable 
                <code>$STAR</code>, and used to replace this value in the command sequence.
                </li>
            <li><a name="helpFunc"><code>attr &lt;name&gt; helpFunc &lt;function name&rt;</code></a>
                <br/>name of a help function which is used in case no command is found for a certain device. When this function is called, the strings $DEV, $HELP, $PARM[0|1|2...]
                will be replaced by the devicename identified by Babble, the help text for this device and parameters passed to the Babble_DoIt function</li>
            <li><a name="testParm"><code>attr &lt;name&gt; testParm(0|1|2|3) &lt;string&rt;</code></a>
                <br/>if a command is not really excuted, but only tested, the values of these attributes will be used to substitute the strings $PARM[0|1|2...]
                in the tested command</li>       
            <li><a name="confirmFunc"><code>attr &lt;name&gt; confirmFunc &lt;function name&rt;</code></a>
                <br/>name of a confirmation function which is used in case a command is exceuted. When this function is called, the strings $DEV, $HELP, $PARM[0|1|2...]
                will be replaced by the devicename identified by Babble, the help text for this device and parameters passed to the Babble_DoIt function</li>     
            <li><a name="noChatBot"><code>attr &lt;name&gt; noChatBot 0|1</code></a>
                <br/>if this attribute is set to 1, a local RiveScript interpreter will be ignored even though it is present in the system</li>
            <li><a name="remoteFHEM"><code>attr &lt;name&gt; remoteFHEM(0|1|2|3) [&lt;user&gt;:&lt;password&gt;@]&lt;IP address:port&rt;</code></a>
                <br/>IP address and port for a remote FHEM installation</li>
            <li><a name="remoteFunc"><code>attr &lt;name&gt; remoteFunc(0|1|2|3) &lt;function name&rt;</code></a>
                <br/>name of a Perl function that is called for addressing a certain remote FHEM device</li>
            <li><a name="remoteToken"><code>attr &lt;name&gt; remoteToken(0|1|2|3) &lt;csrfToken&rt;</code></a>
                <br/>csrfToken for addressing a certain remote FHEM device</li>
            <li><a name="babbleIds"><code>attr &lt;name&gt; babbleIds <id_1> <id_2> ...</code></a>
                <br />space separated list of identities by which babble may be addressed</li>
            <li><a name="babblePreSubs"><code>attr &lt;name&gt; babbleSubs <regexp1>:<replacement1>,<regexp2>:<replacement2>, ...</code></a>
                <br/>space separated list of regular expressions and their replacements - this will be used on the initial sentence submitted to Babble 
                (Note: a space in the regexp must be replaced by \s). </li>
            <li><a name="babblePlaces"><code>attr &lt;name&gt; babblePlaces <place_1> <place_2> ...</code></a>
                <br />space separated list of special places to be identified in speech</li>
            <li><a name="babbleNotPlaces"><code>attr &lt;name&gt; babbleNoPlaces <place_1> <place_2> ...</code></a>
                <br />space separated list of rooms (in the local FHEM device) that should <i>not</i> appear in the list of place</li>
            <li><a name="babbleStatus"><code>attr &lt;name&gt; babbleStatus <status_1> <status_2> ...</code></a>
                <br />space separated list of status identifiers to be identified in speech. Example: <code>Status Value Weather Time</code></li>        
            <li><a name="babblePrepos"><code>attr &lt;name&gt; babblePrepos <prepo_1> <prepo_2> ...</code></a>
                <br />space separated list of prepositions to be identified in speech. Example: <code>by in at on</code></li>
            <li><a name="babbleTimes"><code>attr &lt;name&gt; babbleTimes <time_1> <time_2> ...</code></a>
                <br />space separated list of temporal adverbs. Example: <code>today tomorrow</code></li>      
            <li><a name="babbleQuests"><code>attr &lt;name&gt; babbleQuests <pron_1> <pron_2> ...</code></a>
                <br />space separated list of questioning adverbs. Example: <code>how when where</code></li>  
            <li><a name="babbleArticles"><code>attr &lt;name&gt; babbleArticles <art_1> <art_2> ...</code></a>
                <br />space separated list of articles to be identified in speech. Example: <code>the</code></li>
            <li><a name="babbleVerbs"><code>attr &lt;name&gt; babbleVerbs <form1a>,<form1b>...:<infinitive1> <form2a>,<form2b>...:<infinitive2></code></a>
                <br />space separated list of verb groups to be identified in speech. Each group consists of comma separated verb forms (conjugations as well as variations), 
                followed by a ':' and then the infinitive form of the verb. Example: <code>speak,speaks,say,says:speaking</code></li>
            <li><a name="babbleWrites"><code>attr &lt;name&gt; babbleWrites <write_1> <write_2> ...</code></a>
                <br />space separated list of write verbs to be identified in speech. Example: <code>send add remove</code></li>
            <li><a name="babbleVerbParts"><code>attr &lt;name&gt; babbleVerbParts <vp_1> <vp_2> ...</code></a>
                <br />space separated list of verb parts to be identified in speech. Example: <code>un re</code></li>
            <li><a name="babble_linkname"><code>attr &lt;name&gt; linkname
                    &lt;string&gt;</code></a>
                <br />Name for babble web link, default:
                babbles</li>
            <li><a name="babble_hiddenroom"><code>attr &lt;name&gt; hiddenroom
                    &lt;string&gt;</code></a>
                <br />Room name for hidden babble room (containing only the Babble device), default:
                babbleRoom</li>
            <li><a name="babble_publicroom"><code>attr &lt;name&gt; publicroom
                    &lt;string&gt;</code></a>
                <br />Room name for public babble room (containing sensor/actor devices), default:
                babble</li>
            <li><a name="babble_lockstate"><code>attr &lt;name&gt; lockstate
                    locked|unlocked</code></a>
                <br /><i>locked</i> means that babble setups may not be changed, <i>unlocked</i>
                means that babble setups may be changed></li>
        </ul>
        </ul>
=end html
=begin html_DE

<a name="Babble"></a>
<h3>Babble</h3>
<ul>
<a href="https://wiki.fhem.de/wiki/Modul_Babble">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#babble">babble</a> 
</ul>
=end html_DE
=cut
