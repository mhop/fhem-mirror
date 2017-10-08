########################################################################################
#
# YAAHM.pm
#
# Yet Another Auto Home Module for FHEM
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
use vars qw($FW_inform);
use vars qw($FW_headerlines);
use vars qw($FW_id);

use Data::Dumper;
use Math::Trig;
use JSON;      # imports encode_json, decode_json, to_json and from_json.

#########################
# Global variables
my $yaahmname;
my $yaahmlinkname   = "Profile";    # link text
my $yaahmhiddenroom = "ProfileRoom"; # hidden room
my $yaahmpublicroom = "Unsorted";    # public room
my $yaahmversion    = "1.09";
my $firstcall=1;
    
my %yaahm_transtable_EN = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Not OK",
    "start"             =>  "Start",
    "status"            =>  "Status",
    "notstarted"        =>  "Not started",
    "next"              =>  "Next",
    "manual"            =>  "Manual Time",
    "active"            =>  "Active",
    "inactive"          =>  "Inactive",
    "overview"          =>  "Summary",
    "name"              =>  "Name", 
    "event"             =>  "Event", 
    "time"              =>  "Time",
    "timer"             =>  "Timer",
    "action"            =>  "Action",
    "weekly"            =>  "Weekly ",
    "day"               =>  "Day",
    "daytime"           =>  "Daytime",
    "nighttime"         =>  "Nighttime",
    "daylight"          =>  "Daylight",
    "daytype"           =>  "Day Type",
    "daily"             =>  "Daily ",
    "type"              =>  "Type",
    "description"       =>  "Description",
    "profile"           =>  "Profile",
    "profiles"          =>  "Profiles",
    #--
    "aftermidnight"     =>  "After Midnight",
    "beforesunrise"     =>  "Before Sunrise",
    "sunrise"           =>  "Sunrise",
    "aftersunrise"      =>  "After Sunrise",
    "wakeup"            =>  "WakeUp",
    "morning"           =>  "Morning",
    "noon"              =>  "Noon",
    "afternoon"         =>  "Afternoon",
    "evening"           =>  "Evening",
    "beforesunset"      =>  "Before Sunset",
    "sunset"            =>  "Sunset",
    "aftersunset"       =>  "After Sunset",
    "sleep"             =>  "Sleep",
    "night"             =>  "Night",
    "beforemidnight"    =>  "Before Midnight",
    #--
    "date"              =>  "Date",
    "today"             =>  "Today",
    "tomorrow"          =>  "Tomorrow",
    "workday"           =>  "Workday",
    "weekend"           =>  "Weekend",
    "vacation"          =>  "Vacation",
    "holiday"           =>  "Holiday",
    "weekday"           =>  "Day of Week",
    #--
    "mode"              =>  "Mode",
    "normal"            =>  "Normal",
    "party"             =>  "Party",
    "absence"           =>  "Absence",
    #--
    "state"             =>  "Security",
    "secstate"          =>  "Device states",
    "unlocked"          =>  "Unlocked",
    "locked"            =>  "Locked",
    "unsecured"         =>  "Not Secured",
    "secured"           =>  "Secured",
    "protected"         =>  "Geschützt",
    "guarded"           =>  "Guarded",
    #--
    "monday"    =>  ["Monday","Mon"],
    "tuesday"   =>  ["Tuesday","Tue"],
    "wednesday" =>  ["Wednesday","Wed"],
    "thursday"  =>  ["Thursday","Thu"],
    "friday"    =>  ["Friday","Fri"],
    "saturday"  =>  ["Saturday","Sat"],
    "sunday"    =>  ["Sunday","Sun"],
    #--
    "spring"    => "Spring",
    "summer"    => "Summer",
    "fall"      => "Fall",
    "winter"    => "Winter"
    );
    
 my %yaahm_transtable_DE = ( 
    "ok"                =>  "OK",
    "notok"             =>  "Nicht OK",
    "start"             =>  "Start",
    "status"            =>  "Status",
    "notstarted"        =>  "Nicht gestartet",
    "next"              =>  "Nächste",
    "manual"            =>  "Manuelle Zeit",
    "active"            =>  "Aktiv",
    "inactive"          =>  "Inaktiv",
    "overview"          =>  "Zusammenfassung",
    "name"              =>  "Name", 
    "event"             =>  "Event", 
    "time"              =>  "Zeit",
    "timer"             =>  "Timer",
    "action"            =>  "Aktion",
    "weekly"            =>  "Wochen-",
    "day"               =>  "Tag",
    "daytime"           =>  "Tageszeit",
    "nighttime"         =>  "Nachtzeit",
    "daylight"          =>  "Tageslicht",
    "daytype"           =>  "Tagestyp",
    "daily"             =>  "Tages-",
    "type"              =>  "Typ",
    "description"       =>  "Beschreibung",
    "profile"           =>  "Profil",
    "profiles"          =>  "Profile",
    #--
    "aftermidnight"     =>  "Nach Mitternacht",
    "beforesunrise"     =>  "Vor Sonnenaufgang",
    "sunrise"           =>  "Sonnenaufgang",
    "aftersunrise"      =>  "Nach Sonnenaufgang",
    "wakeup"            =>  "Wecken",
    "morning"           =>  "Morgen",
    "noon"              =>  "Mittag",
    "afternoon"         =>  "Nachmittag",
    "evening"           =>  "Abend",
    "beforesunset"      =>  "Vor Sonnenuntergang",
    "sunset"            =>  "Sonnenuntergang",
    "aftersunset"       =>  "Nach Sonnenuntergang",
    "sleep"             =>  "Schlafen",
    "night"             =>  "Nacht",
    "beforemidnight"    =>  "Vor Mitternacht",
    #--
    "date"              =>  "Termin",
    "today"             =>  "Heute",
    "tomorrow"          =>  "Morgen",
    "workday"           =>  "Arbeitstag",
    "weekend"           =>  "Wochenende",
    "vacation"          =>  "Ferientag",
    "holiday"           =>  "Feiertag",
    "weekday"           =>  "Wochentag",
    #--
    "mode"              =>  "Modus",
    "normal"            =>  "Normal",
    "party"             =>  "Party",
    "absence"           =>  "Abwesenheit",
    #--
    "state"             =>  "Sicherheit",
    "secstate"          =>  "Device States",
    "unlocked"          =>  "Unverschlossen",
    "locked"            =>  "Verschlossen",
    "unsecured"         =>  "Nicht Gesichert",
    "secured"           =>  "Gesichert",
    "protected"         =>  "Geschützt",
    "guarded"           =>  "Überwacht",
    #--
    "monday"    =>  ["Montag","Mo"],
    "tuesday"   =>  ["Dienstag","Di"],
    "wednesday" =>  ["Mittwoch","Mi"],
    "thursday"  =>  ["Donnerstag","Do"],
    "friday"    =>  ["Freitag","Fr"],
    "saturday"  =>  ["Samstag","Sa"],
    "sunday"    =>  ["Sonntag","So"],
        #--
    "spring"    => "Frühling",
    "summer"    => "Sommer",
    "fall"      => "Herbst",
    "winter"    => "Winter"
    );
    
my $yaahm_tt;

#-- default values, need to be overwritten from save file
# first and second parameter
#   entries in the default table with no time entry are single-timers
#   entries in the default table with only first time are single-timers
#   entries in the default table with only second time are single-timer offsets
#   entries in the default table with first an second time are two-timer periods
# third parameter
# fourth parameter

my %defaultdailytable = ( 
    "aftermidnight"     =>  [undef,"00:01",undef,undef],
    "beforesunrise"     =>  [undef,"01:00",undef,undef],
    "sunrise"           =>  [undef,undef,undef,undef],
    "aftersunrise"      =>  [undef,"01:00",undef,undef],
    "wakeup"            =>  ["06:15",undef,undef,undef],
    "morning"           =>  ["08:00",undef,undef,undef],
    "noon"              =>  ["13:00",undef,undef,undef],
    "afternoon"         =>  ["14:00",undef,undef,undef],
    "evening"           =>  ["18:30",undef,undef,undef],
    "beforesunset"      =>  [undef,"01:00",undef,undef],
    "sunset"            =>  [undef,undef,undef,undef],
    "aftersunset"       =>  [undef,"01:00",undef,undef],
    "sleep"             =>  ["22:30",undef,undef,undef],
    "night"             =>  ["22:00",undef,undef,undef],
    "beforemidnight"    =>  [undef,"00:05",undef,undef]);
    
my %dailytable = ();

sub YAAHM_dsort { 
  $dailytable{$a}[0] cmp $dailytable{$b}[0]
}
    
my @weeklytable = (
    "monday",    
    "tuesday",  
    "wednesday", 
    "thursday",
    "friday",   
    "saturday",  
    "sunday");
    
my %defaultwakeuptable = (
    "name"      =>  "",
    "action"    =>  "",
    "monday"    =>  "06:15",
    "tuesday"   =>  "06:15",
    "wednesday" =>  "06:15",
    "thursday"  =>  "06:15",
    "friday"    =>  "06:15",
    "saturday"  =>  "off",
    "sunday"    =>  "off");
    
my %defaultsleeptable = (
    "name"      =>  "",
    "action"    =>  "",
    "monday"    =>  "22:30",
    "tuesday"   =>  "22:30",
    "wednesday" =>  "22:30",
    "thursday"  =>  "22:30",
    "friday"    =>  "23:00",
    "saturday"  =>  "23:00",
    "sunday"    =>  "22:30");
    
my @daytype = (
    "workday",
    "vacation",
    "weekend",
    "holiday");
   
my %defaultdayproperties = (
    "date"      =>  "",
    "weekday"   =>  "",
    "daytype"   =>  0,
    "desc"      =>  "",
    "season"    =>  "");

my @times = (keys %defaultdailytable);
    
my @modes = (
    "normal","party","absence");
   
my @states = (
    "unsecured","secured","protected","guarded");
    

my @seasons = (
    "winter","spring","summer","fall");
 
#-- modes or day types that affect the profile
my @profmode = ("party","absence");
my @profday  = ("vacation","holiday"); 

#########################################################################################
#
# YAAHM_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub YAAHM_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "YAAHM_Define";
  $hash->{SetFn}   	   = "YAAHM_Set";  
  $hash->{GetFn}       = "YAAHM_Get";
  $hash->{UndefFn}     = "YAAHM_Undef";   
  $hash->{AttrFn}      = "YAAHM_Attr";
  my $attst            = "linkname publicroom hiddenroom lockstate:locked,unlocked simulation:0,1 ".
                         "timeHelper modeHelper modeAuto:0,1 stateDevices:textField-long stateInterval stateWarning stateHelper stateAuto:0,1 ".
                         "holidayDevices:textField-long vacationDevices:textField-long specialDevices:textField-long";
 
  $hash->{AttrList}    = $attst;
  
  if( !defined($yaahm_tt) ){
    #-- in any attribute redefinition readjust language
    my $lang = AttrVal("global","language","EN");
    if( $lang eq "DE"){
      $yaahm_tt = \%yaahm_transtable_DE;
    }else{
      $yaahm_tt = \%yaahm_transtable_EN;
    }
  }
  $yaahmlinkname = $yaahm_tt->{"profiles"};
  
  $data{FWEXT}{YAAHMx}{LINK} = "?room=".$yaahmhiddenroom;
  $data{FWEXT}{YAAHMx}{NAME} = $yaahmlinkname;		
  
  $data{FWEXT}{"/YAAHM_timewidget"}{FUNC} = "YAAHM_timewidget";
  $data{FWEXT}{"/YAAHM_timewidget"}{FORKABLE} = 0;		  
	
  return undef;
}

#########################################################################################
#
# YAAHM_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub YAAHM_Define ($$) {
  my ($hash, $def) = @_;
  my $now  = time();
  my $name = $hash->{NAME}; 
  my $TYPE = $hash->{TYPE};
 
  $hash->{VERSION} = $yaahmversion;
  $yaahmname       = $name;

  #-- readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $yaahm_tt = \%yaahm_transtable_DE;
  }else{
    $yaahm_tt = \%yaahm_transtable_EN;
  }
  #$hash->{DATA}{"TT"}=$yaahm_tt;

  # NOTIFYDEV
  my $NOTIFYDEV = "global,$name";
  unless ( defined( $hash->{NOTIFYDEV} ) && $hash->{NOTIFYDEV} eq $NOTIFYDEV )
  {
    $hash->{NOTIFYDEV} = $NOTIFYDEV;
    #$changed = 1;
  }

 readingsSingleUpdate( $hash, "state", "Initialized", 1 ); 
 
 $yaahmlinkname             = defined($attr{$name}{"linkname"})  ? $attr{$name}{"linkname"} : $yaahmlinkname; 
 $yaahmhiddenroom           = defined($attr{$name}{"hiddenroom"})  ? $attr{$name}{"hiddenroom"} : $yaahmhiddenroom;  
 $data{FWEXT}{YAAHMx}{LINK} = "?room=".$yaahmhiddenroom;
 $data{FWEXT}{YAAHMx}{NAME} = $yaahmlinkname;	
 $attr{$name}{"room"}       = $yaahmhiddenroom;
 
 #-- clone daily default profile
 $hash->{DATA}{"DT"}  = {%defaultdailytable};
 
 #-- clone weekly default profile
 $hash->{DATA}{"WT"} = ();
 push(@{$hash->{DATA}{"WT"}},{%defaultwakeuptable});
 $hash->{DATA}{"WT"}[0]{"name"} = $yaahm_tt->{"wakeup"};
  push(@{$hash->{DATA}{"WT"}},{%defaultsleeptable});
 $hash->{DATA}{"WT"}[1]{"name"} = $yaahm_tt->{"sleep"};
 
 #-- clone days for today and tomorrow
 $hash->{DATA}{"DD"}  = ();
 push(@{$hash->{DATA}{"DD"}},{%defaultdayproperties});
 push(@{$hash->{DATA}{"DD"}},{%defaultdayproperties});
 
 #-- determine Astro device
 if( !exists($modules{Astro}{defptr}) ){
   Log3 $name,1,"[YAAHM] does not find an Astro device, loading module Astro separately";
   require "95_Astro.pm";
 }else{
   my @keys = sort keys %{$modules{Astro}{defptr}};
   Log3 $name,1,"[YAAHM] finds ".int(@keys)." Astro devices, module not loaded separately";
 }
    
 #--
 $modules{YAAHM}{defptr}{$name} = $hash;
 
 RemoveInternalTimer($hash);
 InternalTimer      ($now + 5, 'YAAHM_CreateEntry', $hash, 0);

 return;
}

#########################################################################################
#
# YAAHM_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub YAAHM_Undef ($$) {
  my ($hash,$arg) = @_;
  
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  delete $data{FWEXT}{YAAHMx};
  if (defined $defs{$name."_weblink"}) {
      FW_fC("delete ".$name."_weblink");
      Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Weblink ".$name."_weblink deleted";
  }
  if (defined $defs{$name."_shortlink"}) {
      FW_fC("delete ".$name."_shortlink");
      Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Weblink ".$name."_shortlink deleted";
  }
  delete($modules{YAAHM}{defptr});
  return undef;
}

#########################################################################################
#
# YAAHM_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
#########################################################################################

sub YAAHM_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  
  my $hash = $defs{"$name"};
  
  #-- in any attribute redefinition readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $yaahm_tt = \%yaahm_transtable_DE;
  }else{
    $yaahm_tt = \%yaahm_transtable_EN;
  }
  
  #---------------------------------------
  if ( $attrName eq "timeHelper" ) {
    my $dh = (defined($attr{$name}{"timeHelper"})) ? $attr{$name}{"timeHelper"} : undef;
    #-- remove this function from all entries
    if( $cmd eq "del" ){
      foreach my $key (keys %defaultdailytable){
        my $xval = $hash->{DATA}{"DT"}{$key}[2];
        if( $xval =~ /^{$dh/){
          my @cmds = split(',',$xval);
          shift(@cmds);
          $xval = join(',',@cmds);
          $hash->{DATA}{"DT"}{$key}[2] = $xval;
        }
      }
    }
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "linkname") ) {
    
    $yaahmlinkname = $attrVal;
    $data{FWEXT}{YAAHMx}{NAME} = $yaahmlinkname;	
  
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "publicroom") ) {
    
    $yaahmpublicroom = $attrVal;
    FW_fC("attr ".$name."_shortlink room ".$yaahmpublicroom);	
    
  #---------------------------------------
  }elsif ( ($cmd eq "set") && ($attrName eq "hiddenroom") ){
    #-- remove old hiddenroom from FHEMWEB instances
    foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     $hr =~ s/$yaahmhiddenroom//;
	     $hr =~ s/,,//;
	     $hr =~ s/,$//;
		 FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr);
      }
    }
    
    #-- new value
    $yaahmhiddenroom = $attrVal;
    $data{FWEXT}{YAAHMx}{LINK} = "?room=".$yaahmhiddenroom;
    FW_fC("attr ".$name."_weblink room ".$yaahmhiddenroom);
    #-- place into FHEMWEB instances
    foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     if (index($hr,$yaahmhiddenroom) == -1){ 		
		    if ($hr eq "") {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$yaahmhiddenroom);
		    }else {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$yaahmhiddenroom);
		    }
		    Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Added hidden room '".$yaahmhiddenroom."' to ".$defs{$dn}{NAME};
	     }	
      }
   }
  #---------------------------------------  
  }elsif ( ($cmd eq "delete") && ($attrName eq "stateDevices") ) {
    fhem("deletereading $name sdev_housestate");
    fhem("deletereading $name sec_housestate");
    fhem("deletereading $name sym_housestate");
    YAAHM_RemoveInternalTimer("check",$hash);
    
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "stateInterval") ) {
    my $next = gettimeofday()+AttrVal($name,"stateInterval",60)*60;
    YAAHM_RemoveInternalTimer("check",$hash);
    YAAHM_InternalTimer("check",$next, "YAAHM_checkstate", $hash, 0);
    
  #---------------------------------------  
  }elsif ( ($cmd eq "delete") && ($attrName eq "stateInterval") ) {
    my $next = gettimeofday()+3600;
    YAAHM_RemoveInternalTimer("check",$hash);
    YAAHM_InternalTimer("check",$next, "YAAHM_checkstate", $hash, 0);
    
  #---------------------------------------    
  }elsif ( $attrName eq "holidayDevices" ) {
    return "Value for $attrName has invalid format"
      unless ( $cmd eq "del" || $attrVal =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );
  #---------------------------------------
  }elsif ( $attrName eq "vacationDevices" ) {
    return "Value for $attrName has invalid format"
      unless ( $cmd eq "del" || $attrVal =~ m/^[A-Za-z\d._]+(?:,[A-Za-z\d._]*)*$/ );
  }

  return;  
}

#########################################################################################
#
# YAAHM_CreateEntry - Puts the YAAHM entry into the FHEM menu
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_CreateEntry($) {
   my ($hash) = @_;
 
   my $name = $hash->{NAME};
   
   $yaahmlinkname   = defined($attr{$name}{"linkname"})    ? $attr{$name}{"linkname"}   : $yaahmlinkname; 
   $yaahmpublicroom = defined($attr{$name}{"publicroom"})  ? $attr{$name}{"publicroom"} : $yaahmpublicroom;  
   $yaahmhiddenroom = defined($attr{$name}{"hiddenroom"})  ? $attr{$name}{"hiddenroom"} : $yaahmhiddenroom;  
   
   #-- this is the long YAAHM entry
   FW_fC("defmod ".$name."_weblink weblink htmlCode {YAAHM_Longtable(\"".$name."\")}");
   Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Weblink ".$name."_weblink created";
   FW_fC("attr ".$name."_weblink room ".$yaahmhiddenroom)
     if(!defined($attr{$name."_weblink"}{"room"}));  
   
   #-- this is the short YAAHM entry
   FW_fC("defmod ".$name."_shortlink weblink htmlCode {YAAHM_Shorttable(\"".$name."\")}");
   Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Weblink ".$name."_shortlink created";
   FW_fC("attr ".$name."_shortlink room ".$yaahmpublicroom)
     if(!defined($attr{$name."_shortlink"}{"room"}));  
   
   foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     if (index($hr,$yaahmhiddenroom) == -1){ 		
		    if ($hr eq "") {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$yaahmhiddenroom);
		    }else {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$yaahmhiddenroom);
		    }
		    Log3 $hash, 3, "[".$name. " V".$yaahmversion."]"." Added hidden room '".$yaahmhiddenroom."' to ".$defs{$dn}{NAME};
	     }	
      }
   }
   
   #-- Start updater
   InternalTimer(gettimeofday()+ 3, "YAAHM_updater",$hash,0);
   YAAHM_InternalTimer("check",gettimeofday()+ 5, "YAAHM_checkstate", $hash, 0);

}

#########################################################################################
#
# YAAHM_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_Set($@) {
   my ( $hash, $name, $cmd, @args ) = @_;
   
   my $imax;
   my $if;
   my $msg;
   my $exec = ( defined($attr{$name}{"simulation"})&&$attr{$name}{"simulation"}==1 ) ? 0 : 1;
   
   #-----------------------------------------------------------
   if ( $cmd =~ /^manualnext.*/ ) {
     #--timer address
     if( $args[0] =~ /^\d+/ ) {
       #-- check if valid
       if( $args[0] >= int(@{$hash->{DATA}{"WT"}}) ){
         $msg = "Error, timer number ".$args[0]." does not exist, number musst be smaller than ".int( @{$hash->{DATA}{"WT"}});
         Log3 $name,1,"[YAAHM_Set] ".$msg;
         return $msg;
       }
       $cmd = "next_".$args[0];
     }else{
       my $ifound = undef;
       for( my $i=0;$i<int(@{$hash->{DATA}{"WT"}});$i++){
         $ifound = $i
           if ($hash->{DATA}{"WT"}[$i]{"name"} eq $args[0] );
       };
       #-- check if valid
       if( !defined($ifound) ){
         $msg = "Error: timer name ".$args[0]." not found";
         Log3 $name,1,"[YAAHM_Set] ".$msg;
         return $msg;
       }
       $cmd = "next_".$ifound;
     }
	 return YAAHM_nextWeeklyTime($name,$cmd,$args[1],$exec);
   
   #-----------------------------------------------------------
   }elsif ( $cmd =~ /^time.*/ ) {
	 return YAAHM_time($name,$args[0],$exec);
  
   #-----------------------------------------------------------
   }elsif ( $cmd =~ /^mode.*/ ) {
	 return YAAHM_mode($name,$args[0],$exec);
   
   #-----------------------------------------------------------
   }elsif ( $cmd =~ /^state.*/ ) {
	 return YAAHM_state($name,$args[0],$exec);
	 
   #-----------------------------------------------------------
   }elsif ( $cmd =~ /^lock(ed)?$/ ) {
	 readingsSingleUpdate( $hash, "lockstate", "locked", 0 ); 
	 return;
	 
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^unlock(ed)?$/ ) {
	 readingsSingleUpdate( $hash, "lockstate", "unlocked", 0 );
	 return;
	 
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^save/ ) {
	return YAAHM_save($hash);
	 
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^restore/ ) {
     return YAAHM_restore($hash);
   
   #-----------------------------------------------------------
   } elsif ( $cmd =~ /^initialize/ ) {
     $firstcall = 1;
     YAAHM_updater($hash);
     YAAHM_InternalTimer("check",gettimeofday()+ 5, "YAAHM_checkstate", $hash, 0);
   #-----------------------------------------------------------
   } elsif ( $cmd eq "createWeekly" ){
     return "[YAAHM] missing name for new weekly profile"
       if( !defined($args[0]) );
     #-- find index
     $imax = int(@{$hash->{DATA}{"WT"}});
     $if= undef;
     for( my $j=0;$j<$imax;$j++){
       if($hash->{DATA}{"WT"}[$j]{"name"} eq $args[0]){
         $if = $j;
         last;
       }
     }
     return "[YAAHM] name $args[0] for weekly profile to be created is already in use"
       if( defined($if) );
     #-- clone wakeuptable
     push(@{$hash->{DATA}{"WT"}},{%defaultwakeuptable});
     $hash->{DATA}{"WT"}[$imax]{"name"} = $args[0];
     #-- save everything
     YAAHM_save($hash);
     fhem("save");
     return "[YAAHM] weekly profile $args[0] created successfully";
     
   #-----------------------------------------------------------     
   } elsif ( $cmd eq "deleteWeekly" ){
     return "[YAAHM] missing name for weekly profile to be deleted"
       if( !defined($args[0]) );
     return "[YAAHM] Default weekly profile cannot be deleted"
       if( ($args[0] eq $yaahm_tt->{"wakeup"}) || ($args[0] eq $yaahm_tt->{"sleep"}) );
     #-- find index
     $imax = int(@{$hash->{DATA}{"WT"}});
     $if= undef;
     for( my $j=0;$j<$imax;$j++){
       if($hash->{DATA}{"WT"}[$j]{"name"} eq $args[0]){
         $if = $j;
         last;
       }
     }
     return "[YAAHM] name $args[0] for weekly profile to be deleted is not known"
       if( !defined($if) );
     splice(@{$hash->{DATA}{"WT"}},$if,1);
     #-- delete timer
     fhem("delete ".$name.".wtimer_".$if.".IF");
     #-- save everything
     YAAHM_save($hash);
     fhem("save");
     return "[YAAHM] weekly profile $args[0] deleted successfully";
     
   #-----------------------------------------------------------	 
   } else {
     my $str =  "";
	 return "[YAAHM] Unknown argument " . $cmd . ", choose one of".
	   " manualnext time:".join(',',@times)." mode:".join(',',@modes).
	   " state:".join(',',@states)." locked:noArg unlocked:noArg save:noArg restore:noArg initialize:noArg createWeekly deleteWeekly";
   }
}

#########################################################################################
#
# YAAHM_Set - Implements the Get function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_Get($@) {
  my ($hash, @a) = @_;
  my $res  = "";
  my $name = $a[0];
  
  my $arg = (defined($a[1]) ? $a[1] : "");
  if ($arg eq "version") {
    return "YAAHM.version => $yaahmversion";
  }elsif ($arg eq "template") {
    $res = "sub HouseTimeHelper(\@){\n".
           "  my (\$event,\$param1,\$param2) = \@_;\n\n".
           "  Log 1,\"[HouseTimeHelper] event=\$event\";\n\n".
           "  my \$time    = ReadingsVal(\"".$name."\",\"housetime\",\"\");\n".
           "  my \$phase   = ReadingsVal(\"".$name."\",\"housephase\",\"\");\n".
           "  my \$state   = ReadingsVal(\"".$name."\",\"housestate\",\"\");\n".
           "  my \$party   = (ReadingsVal(\"".$name."\",\"housemode\",\"\")) eq \"party\") ? 1 : 0;\n".
           "  my \$absence = (ReadingsVal(\"".$name."\",\"housemode\",\"\")) eq \"absence\") ? 1 : 0;\n".
           "  my \$todaytype = ReadingsVal(\"".$name."\",\"tr_todayType\",\"\");\n".
           "  my \$todaydesc = ReadingsVal(\"".$name."\",\"todayDesc\",\"\")\n".
           "  my \$tomorrowtype = ReadingsVal(\"".$name."\",\"tr_tomorrowType\",\"\");\n".
           "  my \$tomorrowdesc = ReadingsVal(\"".$name."\",\"tomorrowDesc\",\"\")\n";
    #-- iterate through table        
    foreach my $key (sort YAAHM_dsort keys %dailytable){
           $res .= "  #---------------------------------------------------------------------\n";
           my $if = ($key eq "aftermidnight") ? "if" : "}elsif";
           $res .= "  ".$if."( \$event eq \"".$key."\" ){\n\n";
    }
    $res .= "  }\n}\n";
    $res .= "sub HouseStateHelper(\@){\n".
           "  my (\$event,\$param1,\$param2) = \@_;\n\n".
           "  Log 1,\"[HouseStateHelper] event=\$event\";\n\n".
           "  my \$time    = ReadingsVal(\"".$name."\",\"housetime\",\"\");\n".
           "  my \$phase   = ReadingsVal(\"".$name."\",\"housephase\",\"\");\n".
           "  my \$state   = ReadingsVal(\"".$name."\",\"housestate\",\"\");\n".
           "  my \$party   = (ReadingsVal(\"".$name."\",\"housemode\",\"\")) eq \"party\") ? 1 : 0;\n".
           "  my \$absence = (ReadingsVal(\"".$name."\",\"housemode\",\"\")) eq \"absence\") ? 1 : 0;\n";
    #-- iterate through table        
    for( my $i=0;$i<int(@states);$i++) {
           $res .= "  #---------------------------------------------------------------------\n";
           my $if = ($i == 0) ? "if" : "}elsif";
           $res .= "  ".$if."( \$event eq \"".$states[$i]."\" ){\n\n";
    }
    $res .= "  }\n}\n";
    return $res;
  } else {
    return "Unknown argument $arg choose one of version:noArg template:noArg";
  }
}

#########################################################################################
#
# YAAHM_save
#
# Parameter hash = hash of the YAAHM device
#
#########################################################################################

sub YAAHM_save($) {
  my ($hash) = @_;
  my $json   = JSON->new->utf8;
  my $jhash0 = eval{ $json->encode( $hash->{DATA} ) };
  my $error  = FileWrite("YAAHMFILE",$jhash0);
  return;
}
	 
#########################################################################################
#
# YAAHM_restore
#
# Parameter hash = hash of the YAAHM device
#
#########################################################################################

sub YAAHM_restore($) {
  my ($hash) = @_;
  my ($error,$jhash0) = FileRead("YAAHMFILE");
  my $json  = JSON->new->utf8;
  my $jhash1 = eval{ $json->decode( $jhash0 ) };
  $hash->{DATA}  = {%{$jhash1}};
  return;
}

#########################################################################################
#
# YAAHM_setParm - Receives parameter values from the javascript FE
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_setParm($@) {
  my ($name, @a) = @_;
  my $hash = $defs{$name};
 
  my $cmd  = $a[0];
  my $key  = $a[1];
  my $msg  = "";
  my $val;
  
  #-- daily profile
  #   start, end/offset, execution, active in mode / daytype
  if ($cmd eq "dt") {
    for( my $i=1;$i<5;$i++){
       $val = $a[$i+1];
       if( ($val eq "undef")||($val eq "") ){
         $val = undef;
       }elsif( ($i<3) && ($val !~ /\d?\d:\d\d/)){
         $msg = "wrong time specification $val for key $key, must be hh:mm";
         Log 1,"[YAAHM_setParm] ".$msg;
         $val = "00:00";
       }elsif( $i<3 ){
         my ($hour,$min) = split(':',$val);
         if( $hour>23 || $min>59 ){
           $msg = "wrong time specification $val for key $key > 23:59";
           Log 1,"[YAAHM_setParm] ".$msg;
           $val = "00:00";
         }
       }
       $hash->{DATA}{"DT"}{$key}[$i-1]=$val;
       #Log 1, "=============> $key $i ".$a[$i+1];
    }
    return $msg;
  #-- weekly profile
  }elsif ($cmd eq "wt") {
    #Log 1,"=================> ".Dumper(@a);
    #-- action
    $hash->{DATA}{"WT"}[$a[1]]{"action"}    = $a[2];
    #-- next time
    $val = $a[3];
    if( ($val eq "undef")||($val eq "") ){
         $val = undef;
    }elsif( $val =~/^off/ ){
      #-- ok
    }elsif( $val =~ /\d?\d:\d\d/ ){
      #-- ok
      my ($hour,$min) = split(':',$val);
      if( $hour>23 || $min>59 ){
        $msg = "wrong time specification next=$val for weekly timer > 23:59".$a[1];
        Log 1,"[YAAHM_setParm] ".$msg;
        $val = "off";
      }
    }else{
      $msg = "wrong time specification next=$val for weekly timer ".$a[1].", must be hh:mm of 'off'";
      Log 1,"[YAAHM_setParm] ".$msg;
      $val = "off";
    }
     
    $hash->{DATA}{"WT"}[$a[1]]{"next"}      = $val;
    $hash->{DATA}{"WT"}[$a[1]]{"acti_m"}    = $a[4];
    $hash->{DATA}{"WT"}[$a[1]]{"acti_d"}    = $a[5];
    #-- weekdays
    for( my $i=0;$i<7;$i++){
      $val = $a[$i+6];
      if( ($val eq "undef")||($val eq "") ){
        $val = undef;
      }elsif( $val =~/^off/ ){
        #-- ok
      }elsif( $val =~ /\d?\d:\d\d/ ){
        #-- ok
        my ($hour,$min) = split(':',$val);
        if( $hour>23 || $min>59 ){
          $msg = "wrong time specification $val for weekly timer > 23:59 ".$a[1];
          Log 1,"[YAAHM_setParm] ".$msg;
          $val = "off";
        }
      }else{
        $msg = "wrong time specification $val for weekly timer ".$a[1].", must be hh:mm or 'off'";
        Log 1,"[YAAHM_setParm] ".$msg;
        $val = "off";
      }
      $hash->{DATA}{"WT"}[$a[1]]{$weeklytable[$i]} = $val;
    }
    return $msg;
  }
}

#########################################################################################
#
# YAAHM_time - Change the house time (aftermidnight .. beforemidnight)
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_time {
  my ($name,$targettime,$exec) = @_;
  my $hash = $defs{$name};
  
  my $prevtime   = defined($hash->{DATA}{"HSM"}{"time"})  ? $hash->{DATA}{"HSM"}{"time"}  : "";
  my $currmode   = defined($hash->{DATA}{"HSM"}{"mode"})  ? $hash->{DATA}{"HSM"}{"mode"}  : "normal";
  my $currstate  = defined($hash->{DATA}{"HSM"}{"state"}) ? $hash->{DATA}{"HSM"}{"state"}  : "unsecured";
  my $msg        = "";
  
  #-- local checks
  #-- double change
  #if( $prevtime eq $targettime ){
  #  $msg = "Transition skipped, the time event $targettime has been executed already"; 
  #}
  
  #-- don't
  if( $msg ne "" ){
    Log3 $name,1,"[YAAHM_time] ".$msg;
    return $msg;
  }
  #-- doit
  my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
  my $lval = sprintf("%02d%02d",$hour,$min);
  my $mval = $dailytable{"morning"}[0];
  my $nval = $dailytable{"night"}[0];
  my $tval = $dailytable{$targettime}[0];
  
  $mval =~ s/://;
  $nval =~ s/://;
  $tval =~ s/://;
  
  #-- targetphase always according to real time, not to command time
  my $targetphase = ( ($lval >= $mval) && ( $nval > $lval ) ) ? "daytime" : "nighttime";
  
  #-- iterate through table to find next event
  my $nexttime;
  my $sval;   
  my $oval="0000";
  foreach my $key (sort YAAHM_dsort keys %dailytable){
    $nexttime = $key;
    $sval     = $dailytable{$key}[0];
    next
      if (!defined($sval));
    $sval     =~ s/://;
    last
      if ( ($lval <= $sval) && ( $lval > $oval ) );
    $oval     = $sval;
  }
      
  #-- automatically leave party mode at morning time or when going to bed
  if( $currmode eq "party" && $targettime =~ /(morning)|(sleep)/ && defined($attr{$name}{"modeAuto"}) && $attr{$name}{"modeAuto"} == 1 ){
    $msg  = YAAHM_mode($name,"normal",$exec)."\n";
    $msg .= YAAHM_state($name,"secured",$exec)."\n"
      if( $currstate eq "unsecured" && $targettime eq "sleep" && defined($attr{$name}{"stateAuto"}) && $attr{$name}{"stateAuto"} == 1 );
  
  #-- automatically leave absence mode at wakeup time
  }elsif( $currmode eq "absence" && $targettime =~ /(wakeup)/ && defined($attr{$name}{"modeAuto"}) && $attr{$name}{"modeAuto"} == 1 ){
    $msg = YAAHM_mode($name,"normal",$exec)."\n";
    
  #-- automatically secure the house at night time or when going to bed (if not absence, and if not party)
  }elsif( $currmode eq "normal" && $currstate eq "unsecured" && $targettime =~ /(night)|(sleep)/ && defined($attr{$name}{"stateAuto"}) && $attr{$name}{"stateAuto"} == 1 ){
    $msg = YAAHM_state($name,"secured",$exec)."\n";
  }
  
  $hash->{DATA}{"HSM"}{"time"} = $targettime;
  
  YAAHM_checkMonthly($hash,'event',$targettime);
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"prev_housetime",$prevtime);
  readingsBulkUpdate($hash,"next_housetime",$nexttime);
  readingsBulkUpdate($hash,"housetime",$targettime);
  readingsBulkUpdate($hash,"tr_housetime",$yaahm_tt->{$targettime});
  readingsBulkUpdate($hash,"housephase",$targetphase);
  readingsBulkUpdate($hash,"tr_housephase",$yaahm_tt->{$targetphase});
  readingsEndUpdate($hash,1); 
  
  #-- helper function not executed, e.g. by call from external timer
  return
    if( !defined($exec) );
  
  #-- execute the helper function
  my $xval;  
  my $ival;
  my $wupn;
  
  #-- todo here: what should we do, if the timer is NOT enabled and we get up or go to bed anyhow ???
  if( $targettime eq "wakeup" ){
    $wupn = $hash->{DATA}{"WT"}[0]{"name"};
    $ival = (ReadingsVal($name.".wtimer_0.IF","mode","") ne "disabled");
    $xval = $ival ? $hash->{DATA}{"WT"}[0]{"action"} : "";
    $msg .= "Simulation ".$xval." from weekly profile ".$wupn;
    $msg .= " (disabled)"
      if !$ival;
  }elsif( $targettime eq "sleep" ){ 
    $wupn = $hash->{DATA}{"WT"}[1]{"name"};
    $ival = (ReadingsVal($name.".wtimer_1.IF","mode","") ne "disabled");
    $xval = $ival ? $hash->{DATA}{"WT"}[1]{"action"} : "";
    $msg .= "Simulation ".$xval." from weekly profile ".$wupn;
    $msg .= " (disabled)"
      if !$ival;
  }else{
    $xval  = $dailytable{$targettime}[2];
    $msg  .= "Simulation ".$xval;
  }
  if( $exec==1 ){
    fhem($xval);
  }elsif( $exec==0 ){
    Log3 $name,1,"[YAAHM_time] ".$msg;
    return $msg;
  }
}

#########################################################################################
#
# YAAHM_nextWeeklyTime - set the next weekly time
#
# Parameter name = name of device addressed
#
#########################################################################################

sub YAAHM_nextWeeklyTime {
 my ($name,$cmd,$time,$exec) = @_;
   
  my $hash = $defs{$name};
  my $msg;
  
  #--determine which timer (duplicate check when coming from set)
  $cmd  =~ /manualnext_([0-9]+)/;
  my $i = $1;
  
  if( $i >= int( @{$hash->{DATA}{"WT"}}) ){
    $msg = "Error, timer number $i does not exist, number musst be smaller than ".int( @{$hash->{DATA}{"WT"}});
    Log3 $name,1,"[YAAHM_nextWeeklyTime] ".$msg;
    return $msg;
  }
  
  #-- check value - may be empty
  if( $time ne ""){
    #-- off=ok, do nothing
    if( $time eq "off"){
    #-- time=ok, check
    }elsif( $time =~ /(\d?\d):(\d\d)(:(\d\d))?/ ){
      if( $1 >= 24 || $2 >= 60){
        $msg = "Error, time specification $time for timer ".$cmd." > 23:59 ";
        Log3 $name,1,"[YAAHM_nextWeeklyTime] ".$msg;
        return $msg;
      }
      $time = sprintf("%02d:\%02d",$1,$2);
    }else{
      $msg = "Error, time specification $time invalid for timer ".$cmd.", must be hh:mm";;
      Log3 $name,1,"[YAAHM_nextWeeklyTime] ".$msg;
      return $msg;
    }
  }
  
  #-- weekly profile times
  my $sg0;
  if( ReadingsVal($name.".wtimer_".$i.".IF","mode","") ne "disabled" ){
    $sg0 = $time;
  }else{
    $sg0 = "off";
  }       
  $hash->{DATA}{"WT"}[$i]{"next"} = $sg0; 
  YAAHM_setWeeklyTime($hash);                                                   
   
  readingsEndUpdate($hash,1);
}

#########################################################################################
#
# YAAHM_mode - Change the house mode (normal, party, absence)
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_mode {
  my ($name,$targetmode,$exec) = @_;
  my $hash = $defs{$name};
  
  my $prevmode   = defined($hash->{DATA}{"HSM"}{"mode"})  ? $hash->{DATA}{"HSM"}{"mode"}  : "normal";
  my $currstate  = defined($hash->{DATA}{"HSM"}{"state"}) ? $hash->{DATA}{"HSM"}{"state"} : "unsecured";
  my $msg        = "";
  
  #-- local checks
  #-- double change
  if( $prevmode eq $targetmode ){
    $msg = "transition skipped, we are already in $targetmode mode"; 
    
  #-- transition into party and absence is only possible from normal mode
  }elsif( $prevmode ne "normal" && $targetmode ne "normal"){
    $msg = "transition into $targetmode mode is only possible from normal mode";
    

  #-- global checks
  #-- transition into party mode only possible in unlocked state
  }elsif( $targetmode eq "party" && $currstate ne "unsecured" ){
    $msg = "transition into party mode is only possible in unsecured state"
  }
  
  #-- don't
  if( $msg ne "" ){
    Log3 $name,1,"[YAAHM_mode] ".$msg;
    return $msg;
  }
    
  $hash->{DATA}{"HSM"}{"mode"} = $targetmode;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"prev_housemode",$prevmode);
  readingsBulkUpdate($hash,"housemode",$targetmode);
  readingsBulkUpdate($hash,"tr_housemode",$yaahm_tt->{$targetmode});
  readingsEndUpdate($hash,1); 
  
  #-- doit, if not simulation
  if (defined($attr{$name}{"modeHelper"})){
    if( !defined($exec) || $exec==1 ){
      fhem("{".$attr{$name}{"modeHelper"}."('".$targetmode."')}");
    }else{
      $msg = "Simulation {".$attr{$name}{"modeHelper"}."('".$targetmode."')}";
      Log3 $name,1,"[YAAHM_mode]  ".$msg;
      return $msg;
    }
  }
}

#########################################################################################
#
# YAAHM_state - Change the house state (unscured, secured, guarded)
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_state {
  my ($name,$targetstate,$exec) = @_;
  my $hash = $defs{$name};
  
  my $prevstate = defined($hash->{DATA}{"HSM"}{"state"}) ? $hash->{DATA}{"HSM"}{"state"} : "unsecured";
  my $currmode  = defined($hash->{DATA}{"HSM"}{"mode"})  ? $hash->{DATA}{"HSM"}{"mode"}  : "normal";
  my $msg       = "";
 
  #-- local checks 
  #-- double change
  #if( $prevstate eq $targetstate ){
  #  $msg = "transition skipped, we are already in $targetstate state";

  #-- global checks
  #-- changing away from unlocked in party mode is not possible
  if( $targetstate ne "unlocked" && $currmode eq "party" ){
    $msg = "not possible in party mode";
  }
  
  #-- don't
  if( $msg ne "" ){
    Log3 $name,1,"[YAAHM_state] ".$msg;
    return $msg;
  }
 
  $hash->{DATA}{"HSM"}{"state"} = $targetstate;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"prev_housestate",$prevstate);
  readingsBulkUpdate($hash,"housestate",$targetstate);
  readingsBulkUpdate($hash,"tr_housestate",$yaahm_tt->{$targetstate});
  readingsEndUpdate($hash,1); 
  
  YAAHM_checkstate($hash);
  
  #-- doit, if not simulation
  if (defined($attr{$name}{"stateHelper"})){
    if( !defined($exec) || $exec==1 ){
      fhem("{".$attr{$name}{"stateHelper"}."('".$targetstate."')}");
    }else{
      $msg = "Simulation {".$attr{$name}{"stateHelper"}."('".$targetstate."')}";
      Log3 $name,1,"[YAAHM_state]  ".$msg;
      return $msg;
    }
  }
}

#########################################################################################
#
# YAAHM_checkstate - check state devices
#
# Parameter someHash =  either internal hash of timer 
#                       => need to dereference it for getting device hash
#                       or device hash
#
#########################################################################################

sub YAAHM_checkstate($) {
  my ($someHash) = @_;
  
  my $hash;
  if( defined($someHash->{HASH}) ){
    $hash = $someHash->{HASH};
  }else{
    $hash = $someHash;
  }
  my $name = $hash->{NAME};
  
  my $next;
  
  $next = gettimeofday()+AttrVal($name,"stateInterval",60)*60;
  
  YAAHM_RemoveInternalTimer("check",$hash);
  YAAHM_InternalTimer("check",$next, "YAAHM_checkstate", $hash, 0);
  Log3 $name, 5,"[YAAHM_checkstate] on device ".$hash->{NAME}." called";
  
  my $istate;
  my $cstate = defined($hash->{DATA}{"HSM"}{"state"}) ? $hash->{DATA}{"HSM"}{"state"} : "";
  
  return undef 
  if( !defined($attr{$name}{"stateDevices"}) );
    
  for($istate=0;$istate<int(@states);$istate++){
    last 
      if($states[$istate] eq $cstate);
  }
  
  my (@devlist,@devl);
  my ($dev,$devs,$devh,);
  my @devf = ();
  my $isf  = 0;
   
  @devlist = split(',',$attr{$name}{"stateDevices"});
  foreach my $devc (@devlist) {
    @devl = split(':',$devc);
    $dev  = $devl[0];
    $devs = $devl[$istate+1];
    if( defined($devs) && ($devs ne "") ){
      $devh = Value($dev);
      if( $devs ne $devh ){
        #Log 1,"==============> Device $dev SOLL $devs IST $devh";
        $isf = 1;
        push(@devf,"<tr><td style=\"text-align:left;padding:5px\">".$dev."</td><td style=\"text-align:left;padding:5px\"><div style=\"color:red\">".$yaahm_tt->{'notok'}.
          "</div></td><td style=\"text-align:left;padding:5px\">".$devh."</td></tr>");
        if( defined(AttrVal($name,"stateWarning",undef)) ){
          fhem("{".AttrVal($name,"stateWarning",undef)."($dev,$devs,$devh)}");
        }
      }else{
        push(@devf,"<tr><td style=\"text-align:left;padding:5px\">".$dev."</td><td style=\"text-align:left;padding:5px\"><div style=\"color:green\">".$yaahm_tt->{'ok'}."</div></td><td></td></tr>");
      }
    }
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"sdev_housestate","<html><table>".join("<br/>",@devf)."</table></html>");
  readingsBulkUpdate($hash,"sec_housestate",(($isf==0)?"secure":"insecure"));
  readingsBulkUpdate($hash,"sym_housestate",(($isf==0)?"<html><div style=\"color:green\">&#x2713;</div></html>":"<html><div style=\"color:red\">&#x274c;</div></html>"));
  readingsEndUpdate($hash,1); 
  
  return undef
}

#########################################################################################
#
# YAAHM_SM - State machine
#
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_SM($) {
  my ($hash) = @_;

}

#########################################################################################
#
# YAAHM_informer - Tell FHEMWEB to inform this page
#
# Parameter me = hash of FHEMWEB instance
#
#########################################################################################

sub YAAHM_informer($) {
  my ($me) = @_;

  $me->{inform}{type} = "status";
  $me->{inform}{filter} = "YYY";
  #$me->{inform}{since} = time()-5;
  $me->{inform}{fmt} = "JSON";

  my $filter = $me->{inform}{filter};

  my %h = map { $_ => 1 } devspec2array($filter);
  
  $h{global} = 1 if( $me->{inform}{addglobal} );
  $h{"#FHEMWEB:$FW_wname"} = 1;
  $me->{inform}{devices} = \%h;
  %FW_visibleDeviceHash = FW_visibleDevices();
  
  $me->{NTFY_ORDER} = $FW_cname;   # else notifyfn won't be called
  %ntfyHash = ();
}
  
#########################################################################################
#
# YAAHM_startDayTimer - start the daily timer function
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_startDayTimer($) {
  my ($name) = @_;
  my $hash = $defs{$name};

  my $res  = "defmod $name.dtimer.IF DOIF ";
  my $msg;
  
  #--cleanup after definition fault
  fhem("deletereading $name t_aftermidnight")
    if( ReadingsVal($name,"t_aftermidnight",undef) );
  fhem("deletereading $name t_aftersunrise")
    if( ReadingsVal($name,"t_aftersunrise",undef) );
  fhem("deletereading $name t_aftersunset")
    if( ReadingsVal($name,"t_aftersunset",undef) );
  fhem("deletereading $name t_beforemidnight")
    if( ReadingsVal($name,"t_beforemidnight",undef) );
  fhem("deletereading $name t_beforesunrise")
    if( ReadingsVal($name,"t_beforesunrise",undef) );
  fhem("deletereading $name t_beforesunset")
    if( ReadingsVal($name,"t_beforesunset",undef) );
    
  delete $hash->{DATA}{"DT"}{"daytime"};
  delete $hash->{DATA}{"DT"}{"nighttime"};
    
  #-- TODO check for plausibility
  #--aftermidnight must be >= 00:01
  my $check=$hash->{DATA}{"DT"}{"aftermidnight"}[0];
  $check =~ s/://;
  if( $check <= 0 ){
    Log3 $name,1,"[YAAHM_startDayTimer] aftermidnight is minimum 00:01, used this value";
    $hash->{DATA}{"DT"}{"aftermidnight"}[0] = "00:01";
  }
  
  #-- Internal timer for night time
  my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
  my $nval = $hash->{DATA}{"DT"}{"night"}[0];
  if( $nval !~ /\d\d:\d\d/ ){
    $msg = "Error in night time specification";
    Log3 1,$name,"[YAAHM_startDayTimer] ".$msg;
    return $msg;
  }
  my ($hourn,$minn) = split(':',$nval);
  my $deltan = ($hourn-$hour)*3600+($minn-$min)*60-$sec;
  my $delta  = $deltan;
  $delta    += 86400
    if( $delta<0 );
  YAAHM_RemoveInternalTimer    ("nighttime", $hash);
  YAAHM_InternalTimer          ("nighttime", gettimeofday()+$delta, "YAAHM_tonight", $hash, 0);
  
  #-- Internal timer for daytime
  my $mval = $hash->{DATA}{"DT"}{"morning"}[0];
  if( $mval !~ /\d\d:\d\d/ ){
    $msg = "Error in morning time specification";
    Log3 1,$name,"[YAAHM_startDayTimer] ".$msg;
    return $msg;
  }
  ($hourn,$minn) = split(':',$mval);
  my $deltam  = ($hourn-$hour)*3600+($minn-$min)*60-$sec;
  $delta      = $deltam;
  $delta     += 86400
    if( $delta<0 );
  YAAHM_RemoveInternalTimer    ("daytime", $hash);
  YAAHM_InternalTimer          ("daytime", gettimeofday()+$delta, "YAAHM_today", $hash, 0);
  
  #-- currently day or night ?
  my $currtime = (($deltam < 0) && ($deltan > 0)) ? "daytime" : "nighttime";
  
  #-- put data into readings
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"housephase",$currtime);
  readingsBulkUpdate($hash,"tr_housephase",$yaahm_tt->{$currtime});
  
  #-- compose external timer
  foreach my $key (sort YAAHM_dsort keys %defaultdailytable){
    next if( !defined($hash->{DATA}{"DT"}{$key}[2]) );
    my $f1 = defined($defaultdailytable{$key}[0]);
    my $f2 = defined($defaultdailytable{$key}[1]);
    my $f3 = defined($hash->{DATA}{"DT"}{$key}[2]) && $hash->{DATA}{"DT"}{$key}[2] ne "";

    my $xval = "{YAAHM_time('".$name."','".$key."')},".$hash->{DATA}{"DT"}{$key}[2];
    
    #-- entries in the default table with no entry are single-timers
    if( !$f1 and !$f2 ){
      $res .= "([[".$name.":s_".$key."]])\n(".$xval.")\nDOELSEIF"
        if( $f3 );
        
    #-- entries in the default table with only first time are single-timers
    }elsif( $f1 and !$f2 ){
      $res .= "([[".$name.":s_".$key."]])\n(".$xval.")\nDOELSEIF"
        if( $f3 );
        
    #-- entries in the default table with only second time are single-timer offsets
    }elsif( !$f1 and $f2 ){
      $res .= "([[".$name.":s_".$key."]])\n(".$xval.")\nDOELSEIF"
        if( $f3 );
        
    #-- entries in the default table with first and second time are two-timer periods
    }elsif( $f1 and $f2 ){
      $res .= "([[".$name.":s_".$key."]-[".$name.":t_".$key."]])\n(".$xval.")\nDOELSEIF"
        if( $f3 );
        
    #-- something wrong
    }else{
      $msg = "Daily timer $name.dtimer.IF NOT started, something wrong with entry ".$key;
      Log 1,"[YAAHM_startDayTimer] ".$msg;
      return $msg;
    }
  }
  readingsEndUpdate($hash,1);
  
  #-- take out last DOELSEIF
  $res =~ s/\nDOELSEIF$//;
  fhem($res);
  fhem("attr $name.dtimer.IF do always");
  fhem("set $name.dtimer.IF enable");
  
  #-- save everything
  YAAHM_save($hash);
  fhem("save");
  
  return "Daily timer $name.dtimer.IF started";
}

#########################################################################################
#
# YAAHM_startWeeklyTimer - start the Weekly timer function
#
# Parameter name = name of the YAAHM device
#
#########################################################################################

sub YAAHM_startWeeklyTimer($) {
  my ($name) = @_;
  my $hash = $defs{$name};

  my $res;
  my $wupn;
  
  YAAHM_setWeeklyTime($hash);
  
  #-- start timer
  for( my $i=0;$i < int( @{$hash->{DATA}{"WT"}} );$i++){
    $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
    $res = "defmod ".$name.".wtimer_".$i.".IF DOIF ([".$name.":ring_".$i."] eq \"off\")\n()\nDOELSEIF\n(([[".$name.":ring_".$i."]])";

    #-- check for activity description
    my $g4a = defined($hash->{DATA}{"WT"}[$i]{"acti_m"}) ? $hash->{DATA}{"WT"}[$i]{"acti_m"} : "";
    my $g4b = defined($hash->{DATA}{"WT"}[$i]{"acti_d"}) ? $hash->{DATA}{"WT"}[$i]{"acti_d"} : "";
    my $v4a = ($g4a ne "") ? "(normal)|(".join(')|(',split(',',$g4a)).")" : "(normal)";
    my $v4b = ($g4b ne "") ? "(workday)|(weekend)|(".join(')|(',split(',',$g4b)).")" : "(workday)|(weekend)";
    
    $res .= "\nand ([" .$name. ":housemode] =~ \"".$v4a."\")";
    $res .= "\nand ([" .$name. ":todayType] =~ \"".$v4b."\")";
    
    #-- action
    my $xval = "";
    if( $i==0 ){
      $xval  = "{YAAHM_time('".$name."','wakeup')},".$hash->{DATA}{"WT"}[$i]{"action"};
    }elsif( $i==1 ){
      $xval  = "{YAAHM_time('".$name."','sleep')},".$hash->{DATA}{"WT"}[$i]{"action"};
    }else{
      $xval  = $hash->{DATA}{"WT"}[$i]{"action"};
    }

    #-- action
    $res .= ")\n(".$xval.")";
    
    #-- doit
    fhem($res);
    fhem("attr ".$name.".wtimer_".$i.".IF do always");
    fhem("set  ".$name.".wtimer_".$i.".IF enable");
  }
  
  #-- save everything
  YAAHM_save($hash);
  fhem("save");
  
  return "Weekly timers started";
}

#########################################################################################
#
# YAAHM_setWeeklyTime - set the Weekly times into readings
#
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_setWeeklyTime($) {
 my ($hash) = @_;
   
  my $name = $hash->{NAME};
  
  readingsBeginUpdate($hash);
  
  #-- weekly profile times
  my ($sg0,$sg1,$sg2,$wt,$ng,$mt);
  
  #-- iterate over timers
  for( my $i=0;$i<int( @{$hash->{DATA}{"WT"}} );$i++){
    if( ReadingsVal($name.".wtimer_".$i.".IF","mode","") ne "disabled" ){
      $sg0 = $hash->{DATA}{"WT"}[$i]{ $weeklytable[$hash->{DATA}{"DD"}[0]{"weekday"}] } ;
      $sg1 = $hash->{DATA}{"WT"}[$i]{ $weeklytable[$hash->{DATA}{"DD"}[1]{"weekday"}] };
      $ng  = $hash->{DATA}{"WT"}[$i]{ "next" };
    }else{
      $sg0 = "off";
      $sg1 = "off";
      $ng  = "off"
    }
    #--
    $mt = $sg1;   
    
    #-- now check if next time is already past 
    my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
    my $lga  = sprintf("%02d%02d",$hour,$min);
    my $nga  = (defined $ng)?$ng:"";
    $nga  =~ s/://;
    
    #-- arbitrary today, next off
    #   set waketime off, erase next
    if( $nga eq "off"){
      $wt = "off";
      $ng = "";
      
    #-- arbitrary today, next undefined
    #   set waketime to today
    }elsif( $nga eq ""){
      $wt = $sg0;
    
    #-- arbitrary today, but next nontrivial and before current time
    #   set waketime to today, leave next as it is (=> tomorrow)
    }elsif( $nga ne "off" && $nga < $lga ){
      $wt = $sg0;
      $mt = $sg1." (".$ng.")";
      
    #-- arbitrary today, but next nontrivial and after current time
    #   replace waketime by next, erase next
    }elsif( $nga ne "off" && $nga > $lga){
      $wt = $ng;
      $ng = "";
    }
    
    readingsBulkUpdate( $hash, "ring_".$i,$wt );
    readingsBulkUpdate( $hash, "next_".$i,$ng );
    readingsBulkUpdate( $hash, "today_".$i,$sg0 );  
    readingsBulkUpdate( $hash, "tomorrow_".$i,$sg1 );     
    readingsBulkUpdate( $hash, "ring_".$i."_1",$mt );                                               
  }
   
  readingsEndUpdate($hash,1);
}

#########################################################################################
#
# YAAHM_checkMonthly - check Monthly calendar at each 
#
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_checkMonthly($$$) {
  my ($hash,$event,$param) = @_;
   
  my $name = $hash->{NAME};
  
  my ($ret,$line,$fline,$date);
  my (@lines,@chunks,@tday,@eday,@sday,@tmor,@two);
  my ($stoday,$stom,$stwom);
  my $todaylong = "";
  my $tomlong   = "";
  my $twodaylong= "";
  
  #-- hourly call
  #if( ($event eq 'hour') || ($event eq '') ){
  #  my $text;
  #  $text = fhem("get Muell text modeAlarmOrStart");
  #  $text = "--" if (!$text); 
  #  $text = "--" if ($text eq ""); 
  #  #fhem("set Termin ".$text);
  #  return $text;
    
  #-- Vorschau täglich oder wenn neu gestartet 
  if( ($event eq "test") || (($event eq 'event') && ($param eq 'aftermidnight')) ){
    
    my $specialDevs = AttrVal( $name, "specialDevices", "" );
    foreach my $specialDev ( split( /,/, $specialDevs ) ) {
      my ($todaydesc,$tomdesc,$twomdesc);
      #-- device of type holiday 
      if( IsDevice( $specialDev, "holiday" )){      
        $stoday = strftime('%2m-%2d', localtime(time));
        $stom   = strftime('%2m-%2d', localtime(time+86400));
        $stwom  = strftime('%2m-%2d', localtime(time+2*86400));
        my $tod = holiday_refresh( $specialDev, $stoday );
        if ( $tod ne "none" ) {
          $todaydesc = $tod;
          Log3 $name, 5,"[YAAHM] found today=special date \"$todaydesc\" in holiday $specialDev";
        }
        $tod = holiday_refresh( $specialDev, $stom );
        if ( $tod ne "none" ) {
          $tomdesc = $tod;
          Log3 $name, 5,"[YAAHM] found tomorrow=special date \"$tomdesc\" in holiday $specialDev";
        } 
        $tod = holiday_refresh( $specialDev, $stwom );
        if ( $tod ne "none" ) {
          $twomdesc = $tod;
          Log3 $name, 5,"[YAAHM] found twodays=special date \"$twomdesc\" in holiday $specialDev";
        } 
      #-- device of type calendar
      }elsif( IsDevice($specialDev, "Calendar" )){
        $stoday  = strftime('%2d.%2m.%2Y', localtime(time));
        $stom    = strftime('%2d.%2m.%2Y', localtime(time+86400));
        $stwom   = strftime('%2d.%2m.%2Y', localtime(time+2*86400));
        @tday  = split('\.',$stoday);
        @tmor  = split('\.',$stom);
        @two   = split('\.',$stwom);
        #-- more complicated to check here
        $fline=Calendar_Get($defs{$specialDev},"get","full","mode=alarm|start|upcoming");
        
        if($fline){
          #chomp($fline);
          @lines = split('\n',$fline);
          foreach $fline (@lines){
            chomp($fline);
            @chunks = split(' ',$fline);
            @sday   = split('\.',$chunks[4]);
            #-- today
            my $rets  = ($sday[2]-$tday[2])*365+($sday[1]-$tday[1])*31+($sday[0]-$tday[0]);
            if( $rets==0 ){
              $todaydesc = $chunks[7];
              Log3 $name, 5,"[YAAHM] found today=special date \"$todaydesc\" in calendar $specialDev";
            }    
            $rets  = ($sday[2]-$tmor[2])*365+($sday[1]-$tmor[1])*31+($sday[0]-$tmor[0]);
            if( $rets==0 ){
              $tomdesc = $chunks[7];
              Log3 $name, 5,"[YAAHM] found tomorrow=special date \"$tomdesc\" in calendar $specialDev";
            }
            $rets  = ($sday[2]-$two[2])*365+($sday[1]-$two[1])*31+($sday[0]-$two[0]);
            if( $rets==0 ){
              $twomdesc = $chunks[7];
              Log3 $name, 5,"[YAAHM] found twodays=special date \"$twomdesc\" in calendar $specialDev";
            }
          }
        }  
      }else{
        Log3 $name, 1,"[YAAHM] unknown special device $specialDev";
        
      }
      #-- accumulate descriptions
      $todaylong .= $todaydesc.','
        if($todaydesc);
      $todaylong =~ s/,$//;
      $tomlong .= $tomdesc.','
        if($tomdesc);
      $tomlong =~ s/,$//;
      $twodaylong .= $twomdesc.','
        if($twomdesc);
       $twodaylong =~ s/,$//;
      
    }
    $hash->{DATA}{"DD"}[0]{"special"} = $todaylong;                        
    $hash->{DATA}{"DD"}[1]{"special"} = $tomlong;                                                 
    #-- put into readings
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "todaySpecial",$todaylong );
    readingsBulkUpdateIfChanged( $hash, "tomorrowSpecial",$tomlong);
    readingsEndUpdate($hash,1);
  }
}  

#########################################################################################
#
# YAAHM_today - internal function to switch into daytime
#
# Parameter timerHash = internal hash of timer 
#                       => need to dereference it for getting device hash
#
#########################################################################################

sub YAAHM_today($) {
  my ($timerHash) = @_;
  my $next;
    
  my $hash = $timerHash->{HASH};
  my $name = $hash->{NAME};
  
  $next = gettimeofday()+86400;
  
  YAAHM_RemoveInternalTimer("today",$hash);
  YAAHM_InternalTimer("today",$next, "YAAHM_today", $hash, 0);
  Log 1,"[YAAHM_today] on device ".$hash->{NAME}." called for this day";
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"housephase","daytime");
  readingsBulkUpdate($hash,"tr_housephase",$yaahm_tt->{"daytime"});
  readingsEndUpdate($hash,1);
  
  return undef; 
}

#########################################################################################
#d
# YAAHM_tonight - internal function to switch into nighttime
#
# Parameter timerHash = internal hash of timer 
#                       => need to dereference it for getting device hash
#
#########################################################################################

sub YAAHM_tonight($) {
  my ($timerHash) = @_;
  my $next;
    
  my $hash = $timerHash->{HASH};
  my $name = $hash->{NAME};
  
  $next = gettimeofday()+86400;
  
  YAAHM_RemoveInternalTimer("tonight",$hash);
  YAAHM_InternalTimer("tonight",$next, "YAAHM_tonight", $hash, 0);
  Log 1,"[YAAHM_tonight] on device ".$hash->{NAME}." called for this day";
    
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"housephase","nighttime");
  readingsBulkUpdate($hash,"tr_housephase",$yaahm_tt->{"nighttime"});
  readingsEndUpdate($hash,1);
  
  return undef; 
}

#########################################################################################
#
# YAAHM_updater - internal update function 1 minute after midnight
#
# Parameter timerHash = on first call, device hash.
#                     = on later calls: internal hash of timer 
#                       => need to dereference it for getting device hash
#
#########################################################################################

sub YAAHM_updater($) {
  my ($timerHash) = @_;
  my $hash; 
  my $next;

  #-- start timer for updates - when device is reloaded
  if( defined($firstcall) && ($firstcall==1) ){
    #-- timerHash is device hash
    $hash = $timerHash;
    my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
    $next = gettimeofday()+(23-$hour)*3600+(59-$min)*60+(59-$sec)+34;
    $firstcall=0;
    
  #-- continue timer for updates
  }else{
    #-- timerHash is internal hash
    $hash = $timerHash->{HASH};
    $next = gettimeofday()+86400;
  }
  
  #-- safeguard if hash is not properly indirected
  if( defined($hash->{HASH}) ){
    #Log 1,"WARNING ! HASH indirection not ok. firstcall=$firstcall";
    $hash = $hash->{HASH};
  }
  YAAHM_RemoveInternalTimer("aftermidnight",$hash);
  YAAHM_InternalTimer("aftermidnight",$next, "YAAHM_updater", $hash, 0);
  Log 1,"[YAAHM_updater] on device ".$hash->{NAME}." called for this day";
  
  YAAHM_GetDayStatus($hash);

  return undef; 
}

#########################################################################################
#
# YAAHM_InternalTimer - start named internal timer
#
# Parameter  modifier = name suffix
#            tim      = time
#            callback = callback function 
#            
#
#########################################################################################

sub YAAHM_InternalTimer($$$$$) {
   my ($modifier, $tim, $callback, $hash, $waitIfInitNotDone) = @_;

   my $mHash;
   if ($modifier eq "") {
      $mHash = $hash;
   } else {
      my $timerName = "$hash->{NAME}_$modifier";
      if (exists  ($hash->{TIMER}{$timerName})) {
          $mHash = $hash->{TIMER}{$timerName};
      } else {
          $mHash = { HASH=>$hash, NAME=>"$hash->{NAME}_$modifier", MODIFIER=>$modifier};
          $hash->{TIMER}{$timerName} = $mHash;
      }
   }
   InternalTimer($tim, $callback, $mHash, $waitIfInitNotDone);
}

#########################################################################################
#
# YAAHM_RemoveInternalTimer - kill named internal timer
#
# Parameter 
#
#########################################################################################

sub YAAHM_RemoveInternalTimer($$) {
   my ($modifier, $hash) = @_;

   my $timerName = "$hash->{NAME}_$modifier";
   if ($modifier eq "") {
      RemoveInternalTimer($hash);
   } else {
      my $myHash = $hash->{TIMER}{$timerName};
      if (defined($myHash)) {
         delete $hash->{TIMER}{$timerName};
         RemoveInternalTimer($myHash);
      }
   }
}

#########################################################################################
#
# YAAHM_GetDayStatus
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_GetDayStatus($) {
  my ($hash) = @_;

  my $name = $hash->{NAME};
  
  #-- readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $yaahm_tt = \%yaahm_transtable_DE;
  }else{
    $yaahm_tt = \%yaahm_transtable_EN;
  }
  
  my ($ret,$line,$fline,$date);
  my (@lines,@chunks,@tday,@eday,@sday,@tmor);
  my ($todaydesc,$todaytype,$tomdesc,$tomtype);
  
  my $stoday  = strftime('%2d.%2m.%2Y', localtime(time));
  my $stom    = strftime('%2d.%2m.%2Y', localtime(time+86400));
  
  #-- workday has lowest priority
  $todaytype = "workday";
  $hash->{DATA}{"DD"}[0]{"date"}      = $stoday;
  $hash->{DATA}{"DD"}[0]{"weekday"}   = (strftime('%w', localtime(time))+6)%7;
  $hash->{DATA}{"DD"}[0]{"daytype"}   = "workday";
  $hash->{DATA}{"DD"}[0]{"desc"}      = $yaahm_tt->{"workday"};
  
  $tomtype = "workday";
  $hash->{DATA}{"DD"}[1]{"date"}      = $stom;
  $hash->{DATA}{"DD"}[1]{"weekday"}   = (strftime('%w', localtime(time+86400))+6)%7;
  $hash->{DATA}{"DD"}[1]{"daytype"}   = "workday";
  $hash->{DATA}{"DD"}[1]{"desc"}      = $yaahm_tt->{"workday"};

  #-- vacation = vacdays has higher priority
  my $vacdayDevs = AttrVal( $name, "vacationDevices", "" );
  foreach my $vacdayDev ( split( /,/, $vacdayDevs ) ) {
    #-- device of type holiday 
    if( IsDevice( $vacdayDev, "holiday" )){      
      $stoday = strftime('%2m-%2d', localtime(time));
      $stom   = strftime('%2m-%2d', localtime(time+86400));
      my $tod = holiday_refresh( $vacdayDev, $stoday );
      if ( $tod ne "none" ) {
        $todaydesc = $tod;
        $todaytype = "vacday";
        Log3 $name, 1,"[YAAHM] found today=vacation \"$todaydesc\" in holiday $vacdayDev";
      }
      $tod = holiday_refresh( $vacdayDev, $stom );
      if ( $tod ne "none" ) {
        $tomdesc = $tod;
        $tomtype = "vacday";
        Log3 $name, 1,"[YAAHM] found tomorrow=vacation \"$tomdesc\" in holiday $vacdayDev";
      } 
    #-- device of type calendar
    }elsif( IsDevice($vacdayDev, "Calendar" )){
      $stoday  = strftime('%2d.%2m.%2Y', localtime(time));
      $stom    = strftime('%2d.%2m.%2Y', localtime(time+86400));
      @tday  = split('\.',$stoday);
      @tmor  = split('\.',$stom);
      #-- more complicated to check here
      $fline=Calendar_Get($defs{$vacdayDev},"get","full","mode=alarm|start|upcoming");
      if($fline){
        #chomp($fline);
        @lines = split('\n',$fline);
        foreach $fline (@lines){
          chomp($fline);
          @chunks = split(' ',$fline);
          @sday   = split('\.',$chunks[2]);
          @eday   = split('\.',substr($chunks[3],9,10));
          #-- today
          my $rets  = ($sday[2]-$tday[2])*365+($sday[1]-$tday[1])*31+($sday[0]-$tday[0]);
          my $rete  = ($eday[2]-$tday[2])*365+($eday[1]-$tday[1])*31+($eday[0]-$tday[0]);
          if( ($rete>=0) && ($rets<=0) ){
            $todaydesc = $chunks[5];
            $todaytype = "vacation";
            Log3 $name, 1,"[YAAHM] found today=vacation \"$todaydesc\" in calendar $vacdayDev";
          }    
          $rets  = ($sday[2]-$tmor[2])*365+($sday[1]-$tmor[1])*31+($sday[0]-$tmor[0]);
          $rete  = ($eday[2]-$tmor[2])*365+($eday[1]-$tmor[1])*31+($eday[0]-$tmor[0]);
          if( ($rete>=0) && ($rets<=0) ){
            $tomdesc = $chunks[5];
            $tomtype = "vacation";
            Log3 $name, 1,"[YAAHM] found tomorrow=vacation \"$tomdesc\" in calendar $vacdayDev";
          }
        }
      }  
    }else{
      Log3 $name, 1,"[YAAHM] unknown vacation device $vacdayDev";
    }
  }
  #-- put into readings
  if( $todaytype eq "vacation" ){
    $hash->{DATA}{"DD"}[0]{"daytype"}    = "vacation";
    $hash->{DATA}{"DD"}[0]{"desc"}       = $todaydesc;
  }else{
  }
  if( $tomtype eq "vacation" ){
    $hash->{DATA}{"DD"}[1]{"daytype"}    = "vacation";
    $hash->{DATA}{"DD"}[1]{"desc"}       = $tomdesc;
  }else{
  }
  
  #-- weekend has higher priority
  if( strftime('%u', localtime(time)) > 5){
    $todaytype = "weekend";
    if( $hash->{DATA}{"DD"}[0]{"daytype"} ne "workday" ){
      $hash->{DATA}{"DD"}[0]{"desc"}       = $yaahm_tt->{"weekend"}.", ".$hash->{DATA}{"DD"}[0]{"desc"};
    }else{
      $hash->{DATA}{"DD"}[0]{"desc"}       = $yaahm_tt->{"weekend"};
    }
    $hash->{DATA}{"DD"}[0]{"daytype"}    = "weekend";
  }
  
  if( strftime('%u', localtime(time+86400)) > 5){
    $tomtype = "weekend";
    if( $hash->{DATA}{"DD"}[1]{"daytype"} ne "workday" ){
      $hash->{DATA}{"DD"}[1]{"desc"}       = $yaahm_tt->{"weekend"}.", ".$hash->{DATA}{"DD"}[1]{"desc"};
    }else{
      $hash->{DATA}{"DD"}[1]{"desc"}       = $yaahm_tt->{"weekend"};
    }
    $hash->{DATA}{"DD"}[1]{"daytype"}    = "weekend";
  }
    
  #-- holidays have the highest priority
  my $holidayDevs = AttrVal( $name, "holidayDevices", "" );
  foreach my $holidayDev ( split( /,/, $holidayDevs ) ) {
  
    #-- device of type holiday 
    if( IsDevice( $holidayDev, "holiday" )){      
      $stoday = strftime('%2m-%2d', localtime(time));
      $stom   = strftime('%2m-%2d', localtime(time+86400));
      my $tod = holiday_refresh( $holidayDev, $stoday );
      if ( $tod ne "none" ) {
        $todaydesc = $tod;
        $todaytype = "holiday";
        Log3 $name, 1,"[YAAHM] found today=holiday \"$todaydesc\" in holiday $holidayDev";
      }
      $tod = holiday_refresh( $holidayDev, $stom );
      if ( $tod ne "none" ) {
        $tomdesc = $tod;
        $tomtype = "holiday";
        Log3 $name, 1,"[YAAHM] found tomorrow=holiday \"$tomdesc\" in holiday $holidayDev";
      }
       
    #-- device of type calendar
    }elsif( IsDevice($holidayDev, "Calendar" )){
      $stoday  = strftime('%2d.%2m.%2Y', localtime(time));
      $stom    = strftime('%2d.%2m.%2Y', localtime(time+86400));
      $line=Calendar_Get($defs{$holidayDev},"get","text","mode=alarm|start|upcoming");
      if($line){
        chomp($line);
        @lines = split('\n',$line);
        foreach $line (@lines){
          chomp($line);
          $date  = substr($line,0,8);
          if( $date eq $stoday ){
            $todaydesc = substr($line,15);
            $todaytype = "holiday";
            Log3 $name, 1,"[YAAHM] found today=holiday \"$todaydesc\" in calendar $holidayDev";
          }
          if( $date eq $stom ){
            $tomdesc = substr($line,15);
            $tomtype = "holiday";
            Log3 $name, 1,"[YAAHM] found tomorrow=holiday \"$tomdesc\" in calendar $holidayDev";
          }
        }
      }
    }else{
      Log3 $name, 1,"[YAAHM] unknown holiday device $holidayDev";
    }      
  }
  
  #-- put into store
  if( $todaytype eq "holiday" ){
    if( $hash->{DATA}{"DD"}[0]{"daytype"} ne "workday" ){
      $hash->{DATA}{"DD"}[0]{"desc"}       = $todaydesc.", ".$hash->{DATA}{"DD"}[0]{"desc"};
    }else{
      $hash->{DATA}{"DD"}[0]{"desc"}       = $todaydesc;
    }
    $hash->{DATA}{"DD"}[0]{"daytype"}    = "holiday";
    }
  if( $tomtype eq "holiday" ){
    if( $hash->{DATA}{"DD"}[1]{"daytype"} ne "workday" ){
      $hash->{DATA}{"DD"}[1]{"desc"}       = $tomdesc.", ".$hash->{DATA}{"DD"}[1]{"desc"};
    }else{
      $hash->{DATA}{"DD"}[1]{"desc"}       = $tomdesc;
    }
    $hash->{DATA}{"DD"}[1]{"daytype"}    = "holiday";
  }
 
  #-- sunrise, sunset and the offsets 
  YAAHM_sun($hash);
  YAAHM_sunoffsets($hash);
 
  readingsBeginUpdate($hash);
  #-- and do not forget to put them into readings, because these are read by the timer
  foreach my $key (sort YAAHM_dsort keys %defaultdailytable){
    #Log 1,"================> setting into reading s_$key value ".$hash->{DATA}{"DT"}{$key}[0];

    my $f1 = defined($defaultdailytable{$key}[0]);
    my $f2 = defined($defaultdailytable{$key}[1]);
    #-- entries in the default table with no entry are single-timers
    if( !$f1 and !$f2 ){
      readingsBulkUpdate( $hash, "s_".$key, $hash->{DATA}{"DT"}{$key}[0] );
        
    #-- entries in the default table with only first time are single-timers
    }elsif( $f1 and !$f2 ){
      readingsBulkUpdate( $hash, "s_".$key, $hash->{DATA}{"DT"}{$key}[0] );
        
    #-- entries in the default table with only second time are single-timer offsets
    }elsif( !$f1 and $f2 ){
      readingsBulkUpdate( $hash, "s_".$key, $hash->{DATA}{"DT"}{$key}[0] );
        
    #-- entries in the default table with first and second time are two-timer periods
    }elsif( $f1 and $f2 ){
      readingsBulkUpdate( $hash, "s_".$key, $hash->{DATA}{"DT"}{$key}[0] );
      readingsBulkUpdate( $hash, "t_".$key, $hash->{DATA}{"DT"}{$key}[1] );
   
    #-- something wrong
    }else{
      my $msg = "Readings update failed, something wrong with entry ".$key;
      Log 1,"[YAAHM_GetDayStatus] ".$msg;
      return $msg;
    }
  }
  
  readingsBulkUpdateIfChanged( $hash, "todayType",$todaytype );
  readingsBulkUpdateIfChanged( $hash, "tr_todayType",$yaahm_tt->{$hash->{DATA}{"DD"}[0]{"daytype"}} );
  if( $todaytype eq "workday"){
    readingsBulkUpdateIfChanged( $hash, "todayDesc","--" )
  }elsif( $todaytype eq "vacation"){
    readingsBulkUpdateIfChanged( $hash, "todayDesc",$hash->{DATA}{"DD"}[0]{"desc"} )
  }elsif( $todaytype eq "weekend"){
    readingsBulkUpdateIfChanged( $hash, "todayDesc","--" )
  }else{
    readingsBulkUpdateIfChanged( $hash, "todayDesc",$hash->{DATA}{"DD"}[0]{"desc"} )
  }
  readingsBulkUpdateIfChanged( $hash, "tomorrowType",$tomtype );
  readingsBulkUpdateIfChanged( $hash, "tr_tomorrowType",$yaahm_tt->{$hash->{DATA}{"DD"}[1]{"daytype"}} );
  if( $tomtype eq "workday"){
    readingsBulkUpdateIfChanged( $hash, "tomorrowDesc","--" )
  }elsif( $tomtype eq "vacation"){
    readingsBulkUpdateIfChanged( $hash, "tomorrowDesc",$hash->{DATA}{"DD"}[1]{"desc"} )
  }elsif( $tomtype eq "weekend"){
    readingsBulkUpdateIfChanged( $hash, "tomorrowDesc","--" )
  }else{
    readingsBulkUpdateIfChanged( $hash, "tomorrowDesc",$hash->{DATA}{"DD"}[1]{"desc"} )
  }
  
  YAAHM_setWeeklyTime($hash);
  
  readingsEndUpdate($hash,1);
  return undef;

}

#########################################################################################
#
# YAAHM_sun - obtain time offsets for midnight etc. sunrise and sunset
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_sun($) {
  my ($hash) = @_;
  
  #-- sunrise and sunset today and tomorrow
  my ($sttoday,$sttom);
  my ($strise0,$stset0,$stseas0,$strise1,$stset1,$stseas1);
  
  $sttoday = strftime('%4Y-%2m-%2d', localtime(time));
  
  #-- for some unknown reason we need this here:
  select(undef,undef,undef,0.01);
  
  $strise0 = Astro_Get($hash,"dummy","text", "SunRise",$sttoday).":00";
  my ($hour,$min) = split(":",$strise0);
  $hash->{DATA}{"DD"}[0]{"sunrise"} = sprintf("%02d:%02d",$hour,$min);
  
  $stset0  = Astro_Get($hash,"dummy","text", "SunSet",$sttoday).":00";
  ($hour,$min) = split(":",$stset0);
  $hash->{DATA}{"DD"}[0]{"sunset"} = sprintf("%02d:%02d",$hour,$min);
  
  $stseas0 = Astro_Get($hash,"dummy","text", "ObsSeasonN",$sttoday);
  $hash->{DATA}{"DD"}[0]{"season"}    = $seasons[$stseas0];   
  
  $sttom   = strftime('%4Y-%2m-%2d', localtime(time+86400));
  
  #-- for some unknown reason we need this here:
  select(undef,undef,undef,0.01);
  
  $strise1 = Astro_Get($hash,"dummy","text", "SunRise",$sttom).":00";
  ($hour,$min) = split(":",$strise1);
  $hash->{DATA}{"DD"}[1]{"sunrise"} = sprintf("%02d:%02d",$hour,$min);
  
  $stset1  = Astro_Get($hash,"dummy","text", "SunSet",$sttom).":00";
  ($hour,$min) = split(":",$stset1);
  $hash->{DATA}{"DD"}[1]{"sunset"} = sprintf("%02d:%02d",$hour,$min);
  
  $stseas1 = Astro_Get($hash,"dummy","text", "ObsSeasonN",$sttom);
  $hash->{DATA}{"DD"}[1]{"season"}    = $seasons[$stseas1]; 
}

#########################################################################################
#
# YAAHM_sunoffsets - obtain time offsets for midnight etc. sunrise and sunset
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub YAAHM_sunoffsets($) {
  my ($hash) = @_;
  
  #-- sunrise
  my $st = $hash->{DATA}{"DD"}[0]{"sunrise"};
  
  my ($hour,$min) = split(":",$st);
  $hash->{DATA}{"DT"}{"sunrise"}[0] = sprintf("%02d:%02d",$hour,$min); 
  
  #-- before sunrise
  my ($ofh,$ofm);
  my $of =  $hash->{DATA}{"DT"}{"beforesunrise"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset before sunrise not in format hh:mm, using 00:00";
    $ofh = 0;
    $ofm = 0;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min-$ofm;
  $ofh = $hour-$ofh;
  if( $ofm < 0 ){
    $ofh--;
    $ofm +=60;
  }
  $hash->{DATA}{"DT"}{"beforesunrise"}[0] = sprintf("%02d:%02d",$ofh,$ofm);
  
  #-- after sunrise
  $of =  $hash->{DATA}{"DT"}{"aftersunrise"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset after sunrise not in format hh:mm, using 00:00";
    $ofh = 0;
    $ofm = 0;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min+$ofm;
  $ofh = $hour+$ofh;
  if( $ofm > 59 ){
    $ofh++;
    $ofm -=60;
  }
  $hash->{DATA}{"DT"}{"aftersunrise"}[0] = sprintf("%02d:%02d",$ofh,$ofm); 
  
  #-- sunset
  $st = $hash->{DATA}{"DD"}[0]{"sunset"};
  ($hour,$min) = split(":",$st);
  $hash->{DATA}{"DT"}{"sunset"}[0] = sprintf("%02d:%02d",$hour,$min);
  
  #-- before sunset
  $of =  $hash->{DATA}{"DT"}{"beforesunset"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset before sunset not in format hh:mm, using 00:00";
    $ofh = 0;
    $ofm = 0;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min-$ofm;
  $ofh = $hour-$ofh;
  if( $ofm < 0 ){
    $ofh--;
    $ofm +=60;
  }
  $hash->{DATA}{"DT"}{"beforesunset"}[0] = sprintf("%02d:%02d",$ofh,$ofm); 
  
  #-- after sunset
  $of =  $hash->{DATA}{"DT"}{"aftersunset"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset after sunset not in format hh:mm, using 00:00";
    $ofh = 0;
    $ofm = 0;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min+$ofm;
  $ofh = $hour+$ofh;
  if( $ofm > 59 ){
    $ofh++;
    $ofm -=60;
  }
  $hash->{DATA}{"DT"}{"aftersunset"}[0] = sprintf("%02d:%02d",$ofh,$ofm);
  
  #-- before midnight
  $hour = 24;
  $min  = 0;
  $of =  $hash->{DATA}{"DT"}{"beforemidnight"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset before midnight not in format hh:mm, using 00:05";
    $ofh = 0;
    $ofm = 5;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min-$ofm;
  $ofh = $hour-$ofh;
  if( $ofm < 0 ){
    $ofh--;
    $ofm +=60;
  }
  $hash->{DATA}{"DT"}{"beforemidnight"}[0] = sprintf("%02d:%02d",$ofh,$ofm); 
  
  #-- after midnight
  $hour = 0;
  $min  = 0;
  $of =  $hash->{DATA}{"DT"}{"aftermidnight"}[1];
  if( $of !~ /\d\d:\d\d/){
    Log 1,"[YAAHM] Offset after midnight not in format hh:mm, using 00:05";
    $ofh = 0;
    $ofm = 5;
  }else{
    ($ofh,$ofm) = split(":",$of);
  }
  $ofm = $min+$ofm;
  $ofh = $hour+$ofh;
  if( $min > 59 ){
    $ofh++;
    $ofm -=60;
  }
  $hash->{DATA}{"DT"}{"aftermidnight"}[0] = sprintf("%02d:%02d",$ofh,$ofm); 
}

#########################################################################################
#
# YAAHM_timewidget - returns SVG code for inclusion into any room page
#
# Parameter name = name of the YAAHM definition
#
#########################################################################################

sub YAAHM_timewidget($){
  my ($arg) = @_;
  my $name = $FW_webArgs{name};
  $name    =~ s/'//g;
  
  my @size=split('x',($FW_webArgs{size} ? $FW_webArgs{size} : '400x400'));
  #Log 1,"++++++++++++++++++++++++++++++++++++++++++++";
  #Log 1,"YAAHM_timewidget type $type (subtype $subtype) called with $arg";
  #Log 1,"YAAHM_timewidget has size ".$size[0]."x".$size[1];
  #Log 1,"++++++++++++++++++++++++++++++++++++++++++++";
  
  $FW_RETTYPE = "image/svg+xml";
  $FW_RET="";
  FW_pO '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" width="'.$size[0].'px" height="'.$size[1].'px">';
 
  my $hash = $defs{$name};
	         # Midnight = 0  200
	         # Noon     = 0 -200
	         # hh:mm    =>  a = (hh*60 + mm)/1140
	         
  my $radius    = 250;
  
  my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
  my $t_now      = sprintf("%02d:%02d",$hour,$min);
  my $a_now  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_now  = -int(sin($a_now)*$radius*100)/100;
  my $y_now  =  int(cos($a_now)*$radius*100)/100;
  
  my $t_sunrise  = defined($hash->{DATA}{"DD"}[0]{"sunrise"}) ? $hash->{DATA}{"DD"}[0]{"sunrise"} : "06:00";
  $t_sunrise     =~ s/^0//;
  ($hour,$min) = split(":",$t_sunrise);
  my $a_sunrise  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_sunrise  = -int(sin($a_sunrise)*$radius*100)/100;
  my $y_sunrise  =  int(cos($a_sunrise)*$radius*100)/100;
  
  my $t_morning  = defined($hash->{DATA}{"DT"}{"morning"}[0]) ? $hash->{DATA}{"DT"}{"morning"}[0] : "08:00";
  $t_morning     =~ s/^0//;
  ($hour,$min) = split(":",$t_morning);
  my $a_morning  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_morning  = -int(sin($a_morning)*$radius*100)/100;
  my $y_morning  =  int(cos($a_morning)*$radius*100)/100;
  
  my $t_noon  = defined($hash->{DATA}{"DT"}{"noon"}[0]) ? $hash->{DATA}{"DT"}{"noon"}[0] : "12:00";
  $t_noon     =~ s/^0//;
  ($hour,$min) = split(":",$t_noon);
  my $a_noon  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_noon  = -int(sin($a_noon)*$radius*100)/100;
  my $y_noon  =  int(cos($a_noon)*$radius*100)/100;
  
  my $t_afternoon  = defined($hash->{DATA}{"DT"}{"afternoon"}[0]) ? $hash->{DATA}{"DT"}{"afternoon"}[0] : "14:00";
  $t_afternoon     =~ s/^0//;
  ($hour,$min) = split(":",$t_afternoon);
  my $a_afternoon  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_afternoon  = -int(sin($a_afternoon)*$radius*100)/100;
  my $y_afternoon  =  int(cos($a_afternoon)*$radius*100)/100;
  
  my $t_sunset  = defined($hash->{DATA}{"DD"}[0]{"sunset"}) ? $hash->{DATA}{"DD"}[0]{"sunset"} : "18:00";
  $t_sunset     =~ s/^0//;
  ($hour,$min) = split(":",$t_sunset);
  my $a_sunset  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_sunset  = -int(sin($a_sunset)*$radius*100)/100;
  my $y_sunset  =  int(cos($a_sunset)*$radius*100)/100;
    
  my $t_evening  = defined($hash->{DATA}{"DT"}{"evening"}[0]) ? $hash->{DATA}{"DT"}{"evening"}[0] : "19:00";
  $t_evening     =~ s/^0//;
  ($hour,$min) = split(":",$t_evening);
  my $a_evening  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_evening  = -int(sin($a_evening)*$radius*100)/100;
  my $y_evening  =  int(cos($a_evening)*$radius*100)/100;
  
  my $t_night  = defined($hash->{DATA}{"DT"}{"night"}[0]) ? $hash->{DATA}{"DT"}{"night"}[0] : "22:00";
  $t_night     =~ s/^0//;
  ($hour,$min) = split(":",$t_night);
  my $a_night  = (60*$hour + $min)/1440 * 2 * pi;
  my $x_night  = -int(sin($a_night)*$radius*100)/100;
  my $y_night  =  int(cos($a_night)*$radius*100)/100;
  FW_pO  '<defs>'.
         sprintf('<linearGradient id="grad1" x1="0%%" y1="0%%" x2="%d%%" y2="%d%%">',int(-$x_noon/$radius*100),int(-$y_noon/$radius*100)).
         '<stop offset="0%" style="stop-color:rgb(255,255,0);stop-opacity:1" />'.
         '<stop offset="100%" style="stop-color:rgb(255,100,0);stop-opacity:1" />'.
         '</linearGradient>'.
           sprintf('<linearGradient id="grad2" x1="%d%%" y1="%d%%" x2="0%%" y2="0%%">',int(-$x_noon/$radius*100),int(-$y_noon/$radius*100)).
         '<stop offset="0%" style="stop-color:rgb(70,70,100);stop-opacity:1" />'.
         '<stop offset="100%" style="stop-color:rgb(255,150,0);stop-opacity:1" />'.
         '</linearGradient>'.
           sprintf('<linearGradient id="grad3" x1="%d%%" y1="%d%%" x2="0%%" y2="0%%">',int(-$x_noon/$radius*100),int(-$y_noon/$radius*100)).
         '<stop offset="0%" style="stop-color:rgb(80,80,80);stop-opacity:1" />'.
         '<stop offset="100%" style="stop-color:rgb(120,120,100);stop-opacity:1" />'.
         '</linearGradient>'.
         '</defs>';
	         
  FW_pO      '<g id="Ebene_1" transform="translate(400,400)">';
  
  #-- daytime arc
  FW_pO      ' <path d="M 0 0 '.($x_morning*1.1).' '.($y_morning*1.1). ' A '.($radius*1.1).' '.($radius*1.1).' 0 1 1 '.($x_night*1.1).' '.($y_night*1.1).' Z" fill="none" stroke="rgb(0,255,200)" stroke-width="15" />';
  
  #-- sunset to sunrise sector
  FW_pO 	 '<path d="M 0 0 '.$x_sunset. ' '.$y_sunset. ' A '.$radius.' '.$radius.' 0 0 1 '.$x_sunrise.' '.$y_sunrise.' Z" fill="rgb(70,70,100)"/>'; 
    
  #-- sunrise to morning sector
  FW_pO 	 '<path d="M 0 0 '.$x_sunrise.' '.$y_sunrise.' A '.$radius.' '.$radius.' 0 0 1 '.$x_morning.' '.$y_morning.' Z" fill="url(#grad2)"/>';
  
  #-- morning to evening sector
  FW_pO 	 '<path d="M 0 0 '.$x_morning.' '.$y_morning.' A '.$radius.' '.$radius.' 0 0 1 '.$x_evening.' '.$y_evening.' Z" fill="url(#grad1)"/>';
  
  #-- evening to sunset sector
  FW_pO 	 '<path d="M 0 0 '.$x_evening.' '.$y_evening.' A '.$radius.' '.$radius.' 0 0 1 '.$x_sunset.' '.$y_sunset.' Z" fill="url(#grad2)"/>';
  
  #-- midnight line
  FW_pO 	 '<line x1="0" y1="0" x2="0" y2="'.($radius*1.2).'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="-30" y="'.($radius*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">0:00</text>';
  
  #--sunrise line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_sunrise*1.2).'" y2="'.($y_sunrise*1.2).'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_sunrise*1.25-30).'" y="'.($y_sunrise*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_sunrise.'</text>';
  
  #--morning line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_morning*1.2).'" y2="'.($y_morning*1.2).'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_morning*1.25-30).'" y="'.($y_morning*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_morning.'</text>';
  
  #--noon line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_noon*1.2) .'" y2="'.($y_noon*1.2) .'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_noon*1.25).'" y="'.($y_noon*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_noon.'</text>';
  
  #--afternoon line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_afternoon*1.2) .'" y2="'.($y_afternoon*1.2) .'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_afternoon*1.25).'" y="'.($y_afternoon*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_afternoon.'</text>';
  
  #--sunset line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_sunset*1.2) .'" y2="'.($y_sunset*1.2) .'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_sunset*1.25).'" y="'.($y_sunset*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_sunset.'</text>';
  
  #--evening line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_evening*1.2) .'" y2="'.($y_evening*1.2) .'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_evening*1.25).'" y="'.($y_evening*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_evening.'</text>';
  
  #--night line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_night*1.2) .'" y2="'.($y_night*1.2) .'" style="stroke:rgb(75, 75, 75);stroke-width:2" />';
  FW_pO      '<text x="'.($x_night*1.25).'" y="'.($y_night*1.25).'" fill="rgb(75, 75, 75)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_night.'</text>';
  
  #--now line
  FW_pO 	 '<line x1="0" y1="0" x2="'.($x_now*1.2) .'" y2="'.($y_now*1.2) .'" style="stroke:rgb(255,0,0);stroke-width:4" />';
  FW_pO      '<text x="'.($x_now*1.25).'" y="'.($y_now*1.25).'" fill="rgb(255,0,0)" style="font-family:Helvetica;font-size:36px;font-weight:bold">'.$t_now.'</text>';
  
  
  FW_pO      '</g>';
  FW_pO      '</svg>';
  return ($FW_RETTYPE, $FW_RET);
}

#########################################################################################
#
# YAAHM_toptable - returns incomplete HTML code for inclusion into any room page
#                  (action and overview fields)
# 
# Parameter name = name of the YAAHM definition
#
#########################################################################################

sub YAAHM_toptable($){
	my ($name) = @_; 

    my $ret = "";
 
    my $hash = $defs{$name};
    
    if( !defined($yaahm_tt) ){
      #-- readjust language
      my $lang = AttrVal("global","language","EN");
      if( $lang eq "DE"){
        $yaahm_tt = \%yaahm_transtable_DE;
      }else{
        $yaahm_tt = \%yaahm_transtable_EN;
      }
    }
    
    #-- something's rotten in the state of denmark
    my $st = $hash->{DATA}{"DD"}[0]{"sunrise"};
    if( !defined($st) || $st eq "00:00" ){
      YAAHM_GetDayStatus($hash);
    }
 
    #--
    my $lockstate = ($hash->{READINGS}{lockstate}{VAL}) ? $hash->{READINGS}{lockstate}{VAL} : "unlocked";
    my $showhelper = ($lockstate eq "unlocked") ? 1 : 0; 
    
    %dailytable = %{$hash->{DATA}{"DT"}};
    my $dailyno    = scalar keys %dailytable;
    my $weeklyno   = int( @{$hash->{DATA}{"WT"}} );
    
    #--
    $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/yaahm.js\"></script><script type=\"text/javascript\">\n";
    
    $ret .= "var dailyno     = ".$dailyno.";\n";
    $ret .= "var dailykeys   = [\"".join("\",\"",(sort YAAHM_dsort keys %dailytable))."\"];\n";
    
    $ret .= "var weeklyno    = ".$weeklyno.";\n"; 
    $ret .= "var weeklykeys  = [\"".join("\",\"",@weeklytable)."\"];\n";  # Day names !!!
    $ret .= "var weeklynames = [";
    for( my $i=0;$i<$weeklyno;$i++){ 
      $ret .= ","
        if( $i!=0 );
      $ret .= "\"".$hash->{DATA}{"WT"}[$i]{"name"}."\"";
    }
    $ret .= "];\n";

    $ret .= "</script>\n";
  
    $ret .= "<table class=\"roomoverview\">\n";
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\" style=\"font-weight:bold\">".$yaahm_tt->{"action"}."</div></td></tr>\n";
    ### action ################################################################################################
    #-- determine columns 
    my $cols = max(int(@modes),int(@states),$weeklyno);
    $ret .= "<tr><td colspan=\"3\" style=\"align:left\"><table class=\"readings\">".
            "<tr class=\"odd\"><td width=\"100px\" class=\"dname\" style=\"padding:5px;\">".$yaahm_tt->{"mode"}."</td>".
            "<td width=\"120px\"><div class=\"dval\" informId=\"$name-tr_housemode\">".ReadingsVal($name,"tr_housemode",undef)."</div></td><td></td>";
            for( my $i=0; $i<$cols; $i++){
              if( $i < int(@modes)){
                $ret .= "<td width=\"120px\"><input type=\"button\" id=\"b_".$modes[$i]."\" value=\"".$yaahm_tt->{$modes[$i]}.
                        "\" style=\"height:20px; width:120px;\" onclick=\"javascript:yaahm_mode('$name','".$modes[$i]."')\"/></td>";
              }else{
                $ret .= "<td width=\"120px\"></td>";
              }
            }
    $ret .= "</tr>";
    $ret .= "<tr class=\"even\"><td class=\"dname\" style=\"padding:5px;\">".$yaahm_tt->{"state"}."</td>".
            "<td><div informId=\"$name-tr_housestate\">".ReadingsVal($name,"tr_housestate",undef).
            "</div></td><td style=\"width:20px\"><div informId=\"$name-sym_housestate\" style=\"align:center\">".ReadingsVal($name,"sym_housestate",undef)."</div></td>";
            for( my $i=0; $i<$cols; $i++){
              if( $i < int(@states)){
                $ret .= "<td width=\"120px\"><input type=\"button\" id=\"b_".$states[$i]."\" value=\"".$yaahm_tt->{$states[$i]}.
                        "\" style=\"height:20px; width:120px;\" onclick=\"javascript:yaahm_state('$name','".$states[$i]."')\"/></td>";
              }else{
                $ret .= "<td width=\"120px\"></td>";
              }
            }
            #style=\"height:20px;border-bottom: 10px solid #333333;background-image: linear-gradient(#e5e5e5,#ababab);\"
    #$ret .= "</tr><tr><td colspan=\"8\" class=\"devType\" style=\"height:5px;border-top: 1px solid #ababab;border-bottom: 1px solid #ababab;\"></td></tr>";
    $ret .= "</table><br/><table class=\"readings\">";   
    #-- repeat manual next for every weekly table  
    my $nval  = "";
    my $wupn;
    $ret .= "<tr class=\"odd\"><td class=\"col1\" style=\"padding:5px;\">".$yaahm_tt->{"manual"}."</td>";
    for (my $i=0;$i<$weeklyno;$i++){
      $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
      $nval = ( defined($hash->{DATA}{"WT"}[$i]{"next"}) ) ? $hash->{DATA}{"WT"}[$i]{"next"} : "";
      $ret .= sprintf("<td class=\"col2\" style=\"text-align:left;padding-left:10px;padding-right:10px\">$wupn<br/>".
              "<input type=\"text\" id=\"wt%d_n\" informId=\"$name-next_$i\" size=\"4\" maxlength=\"120\" value=\"$nval\" onchange=\"javascript:yaahm_setnext('$name',%d)\"/></td>",$i,$i);
    }
    $ret .= "</tr>\n";
    $ret .= "</table><br/></td></tr>";
            
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\" style=\"font-weight:bold\">".$yaahm_tt->{"overview"}."</div></td></tr>\n";   
    ### daily overview ################################################################################################
    $ret .= "<tr><td colspan=\"3\"><table>";
    #-- time widget here
    $ret .= "<tr><td rowspan=\"8\" width=\"200\" style=\"padding-right:50px\"><img src=\"/fhem/YAAHM_timewidget?name='".$name."'&amp;size='200x200'\" type=\"image/svg+xml\" ></td>";
    #-- continue table
    $ret .= "<td colspan=\"3\">"."</td><td>".$yaahm_tt->{"today"}.                                                         
                                     "</td><td>".$yaahm_tt->{"tomorrow"}.
                                     "</td><td><div class=\"dval\" informId=\"$name-tr_housestate\">".ReadingsVal($name,"tr_housestate",undef)."</div>&#x2192;".
                                     $yaahm_tt->{"secstate"}."</td></tr>\n";
    $ret .= "<tr><td colspan=\"3\"></td><td style=\"padding:5px\">".$yaahm_tt->{$weeklytable[$hash->{DATA}{"DD"}[0]{"weekday"}]}[0] .         
                                  "</td><td style=\"padding:5px\">".$yaahm_tt->{$weeklytable[$hash->{DATA}{"DD"}[1]{"weekday"}]}[0].
                                  "</td><td style=\"padding:5px;vertical-align:top;\" rowspan=\"8\"><div class=\"dval\" informId=\"$name-sdev_housestate\">".ReadingsVal($name,"sdev_housestate","")."</div></td></tr>\n";
    $ret .= "<tr><td colspan=\"3\"></td><td style=\"padding:5px\">".$hash->{DATA}{"DD"}[0]{"date"}.         
                                  "</td><td style=\"padding:5px\">".$hash->{DATA}{"DD"}[1]{"date"}."</td></tr>\n";
    $ret .= "<tr><td colspan=\"3\" class=\"dname\" style=\"padding:5px;\">".$yaahm_tt->{"daylight"}."</td><td style=\"padding:5px\">".$hash->{DATA}{"DD"}[0]{"sunrise"}."-".$hash->{DATA}{"DD"}[0]{"sunset"}.         
                                  "</td><td style=\"padding:5px\">".$hash->{DATA}{"DD"}[1]{"sunrise"}."-".$hash->{DATA}{"DD"}[1]{"sunset"}."</td></tr>\n";
    $ret .= "<tr><td colspan=\"3\" class=\"dname\" style=\"padding:5px;\">".$yaahm_tt->{"daytime"}."</td><td style=\"padding:5px\">".$hash->{DATA}{"DT"}{"morning"}[0]."-".
                                   $hash->{DATA}{"DT"}{"night"}[0]."</td><td></td></tr>\n";
    $ret .= "<tr><td colspan=\"3\" class=\"dname\" style=\"padding:5px;\">".$yaahm_tt->{"daytype"}."</td><td style=\"padding:5px\">".$yaahm_tt->{$hash->{DATA}{"DD"}[0]{"daytype"}}.         
                                                         "</td><td style=\"padding:5px\">".$yaahm_tt->{$hash->{DATA}{"DD"}[1]{"daytype"}}."</td></tr>\n";
    $ret .= "<tr><td colspan=\"3\" class=\"dname\" style=\"padding:5px\">".$yaahm_tt->{"description"}."</td><td style=\"padding:5px;width:100px\">".$hash->{DATA}{"DD"}[0]{"desc"}.                         
                                                                "</td><td style=\"padding:5px;width:100px\">".$hash->{DATA}{"DD"}[1]{"desc"}."</td></tr>\n";
    $ret .= "<tr><td colspan=\"3\" class=\"dname\" style=\"padding:5px\">".$yaahm_tt->{"date"}."</td><td style=\"padding:5px;width:100px\">".$hash->{DATA}{"DD"}[0]{"special"}.                         
                                                                "</td><td style=\"padding:5px;width:100px\">".$hash->{DATA}{"DD"}[1]{"special"}."</td></tr>\n";
                                                                
    #-- weekly timers
    my $ts;
    for( my $i=0;$i<$weeklyno;$i++ ){
      $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
      
      #-- timer status
      if( defined($defs{$name.".wtimer_".$i.".IF"})){
        if( ReadingsVal($name.".wtimer_".$i.".IF","mode","") ne "disabled" ){
          $ts = "<div style=\"color:green\">&#x2713;</div>";
        }else{
          $ts = "<div style=\"color:red\">&#x274c;</div>";
        }
      }else{
        $ts = "";
      }   

      $ret .= "<tr>";
      if( $i == 0){
        $ret .= "<td style=\"text-align:center; white-space:nowrap;max-height:20px\">".
            "<label><div class=\"dval\" informId=\"$name-tr_housetime\">".ReadingsVal($name,"tr_housetime","").
            "</div>&nbsp;<div class=\"dval\" informId=\"$name-tr_housephase\">".ReadingsVal($name,"tr_housephase","")."</div></label>".
            "</td>";
      }else{
         $ret .= "<td></td>";
      }
      $ret.="<td></td><td style=\"padding:5px\">".$wupn.
            "</td><td style=\"text-align:center;padding:5px;\">$ts</td>".
            "<td style=\"padding:5px\"><div class=\"dval\" informId=\"$name-ring_$i\">".ReadingsVal($name,"ring_$i","")."</div></td>".
            "<td style=\"padding:5px\"><div class=\"dval\" informId=\"$name-ring_".$i."_1\">".ReadingsVal($name,"ring_".$i."_1","")."</div></td></tr>\n";
    }
    $ret .= "</table></td></tr>\n";
    
    return $ret;
    
 }

#########################################################################################
#
# YAAHM_Shorttable - returns complete HTML code for inclusion into any room page
#                  (action and overview fields)
# 
# Parameter name = name of the YAAHM definition
#
#########################################################################################

sub YAAHM_Shorttable($){
    my ($name) = @_; 

    my $ret = YAAHM_toptable($name);
    
    #-- complete the code of the page
    $ret .= "</table>";
    InternalTimer(gettimeofday()+ 1, "YAAHM_informer", $defs{$FW_cname},0);
    return $ret;
}

#########################################################################################
#
# YAAHM_Longtable - returns complete HTML code for the full YAAHM page
#              (action, overview, daily and weekly profile)
# 
# Parameter name = name of the YAAHM definition
#
#########################################################################################

sub YAAHM_Longtable($){
	my ($name) = @_; 

    my $ret = "";
 
    my $hash = $defs{$name};
    my $id   = $defs{$name}{NR};
 
    #--
    my $lockstate = ($hash->{READINGS}{lockstate}{VAL}) ? $hash->{READINGS}{lockstate}{VAL} : "unlocked";
    my $showhelper = ($lockstate eq "unlocked") ? 1 : 0; 
    
    %dailytable = %{$hash->{DATA}{"DT"}};
    my $dailyno    = scalar keys %dailytable;
    my $weeklyno   = int( @{$hash->{DATA}{"WT"}} );

    #--
    $ret = YAAHM_toptable($name);
    
    ### daily profile table ################################################################################################
    my $row   = 1;
    my $event = "";
    my $sval  = "";
    my $eval  = "";
    my $xval  = "";
 
    my $dh = (defined($attr{$name}{"timeHelper"})) ? $attr{$name}{"timeHelper"} : undef;
    
    #-- global status of timer
    my ($tl,$ts);
    if( defined($defs{$name.".dtimer.IF"})){
      $tl = "<a href=\"/fhem?detail=$name.dtimer.IF\">$name.dtimer.IF</a>";
      #-- green hook
      if( ReadingsVal($name.".dtimer.IF","mode","") ne "disabled"  ){
        $ts = "<td style=\"color:green;padding-left:5px\">&#x2713;</td>\n";
      #-- red cross
      }else{
        $ts = "<td style=\"color:red;padding-left:5px\">&#x274c;</td>\n";
      }
    }else{
      $tl= $yaahm_tt->{"notstarted"};
      $ts ="<td></td>";
    }    
    
    #-- name link button status
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\" style=\"font-weight:bold; white-space:nowrap;\">".$yaahm_tt->{"daily"}.$yaahm_tt->{"profile"}."\n".
            "<table><tr><td style=\"text-align:center;vertical-align:middle;white-space:nowrap;padding-left:5px\"><div id=\"dtlink\" style=\"font-weight:normal\">$tl</div></td>$ts";
    $ret .= "<td style=\"vertical-align:middle;;padding-left:5px\"><input type=\"button\" value=\"".$yaahm_tt->{"start"}." ".$yaahm_tt->{"daily"}.$yaahm_tt->{"timer"}."\" onclick=\"javascript:yaahm_startDayTimer('$name')\"/></td>\n";
    $ret .= "</tr></table></div></td></tr>";            
    
    #-- header line             
    $ret .= "<tr><td colspan=\"3\"><table class=\"block wide\" id=\"dailytable\">\n"; 
    $ret .= "<tr style=\"font-weight:bold\"><td rowspan=\"2\" class=\"devType col1\" style=\"min-width:120px;\">".$yaahm_tt->{"event"}."</td><td class=\"devType,col2\" style=\"text-align:right;min-width:180px;white-space:nowrap;\">".
            $yaahm_tt->{"time"}." [hh:mm]&nbsp;&nbsp;&nbsp;</td>".
            "<td rowspan=\"2\" class=\"devType col3\" style=\"min-width:200px;\">".$yaahm_tt->{"action"}."</td>".
            "</tr>".
            "<tr style=\"font-weight:bold\"><td class=\"devType col2\" style=\"text-align:right\">Start/Offset&nbsp;&nbsp;&nbsp;End&nbsp;&nbsp;&nbsp;</td></tr>\n";
            
    #-- iterate through table        
    foreach my $key (sort YAAHM_dsort keys %dailytable){
      $row++;
      $event= $yaahm_tt->{$key};
      $sval = $dailytable{$key}[0];
      $eval = $dailytable{$key}[1];
      $xval = $dailytable{$key}[2];
      $xval = "" if( !defined($xval) );
      #--
      if( $dh ){
        #-- timeHelper not in command list
        if( $xval !~ /^{$dh/ ){
          if( defined($xval) && length($xval)>0 ){
            $xval ="{".$dh."('".$key."')},".$xval;
          }else{
            $xval ="{".$dh."('".$key."')}";
          }
        }
      }
      
      $ret .= sprintf("<tr class=\"%s\"><td class=\"col1\">$event</td>\n", ($row&1)?"odd":"even"); 
      #-- First field
      #-- Only reference for wakeup
      if( $key =~ /^wakeup.*/ ){
        $ret .= "<td class=\"col2\" style=\"text-align:left\">".$yaahm_tt->{"weekly"}.$yaahm_tt->{"profile"}."</td><td></td><td></td></tr>\n";
        next;
      #-- Only reference for sleep
      }elsif( $key =~ /^sleep.*/ ){
        $ret .= "<td class=\"col2\" style=\"text-align:left\">".$yaahm_tt->{"weekly"}.$yaahm_tt->{"profile"}."</td><td></td><td></td></tr>\n";
        next;
      #-- calculated value for sunrise/sunset
      }elsif( $key =~ /.*((sunrise)|(sunset)|(midnight)).*/ ){
        my $pre;
        if( $key =~ /.*sunrise.*/ ){
          $pre   = $hash->{DATA}{"DD"}[0]{"sunrise"}
        }elsif( $key =~ /.*sunset.*/ ){
          $pre   = $hash->{DATA}{"DD"}[0]{"sunset"}
        }else{
          $pre   = "00:00";
        }
        $ret    .= "<td class=\"col2\" style=\"text-align:right\">";
        if( $key =~ /.*before.*/ ){
          $ret .= "$pre - &nbsp;<input type=\"text\" id=\"dt".$key."_e\" size=\"4\" maxlength=\"120\" value=\"$eval\"/>&nbsp;=&nbsp;$sval&nbsp;&nbsp;&nbsp;&nbsp;</td>"
        }elsif( $key =~ /.*after.*/ ){
          $ret .= "$pre + &nbsp;<input type=\"text\" id=\"dt".$key."_e\" size=\"4\" maxlength=\"120\" value=\"$eval\"/>&nbsp;=&nbsp;$sval&nbsp;&nbsp;&nbsp;&nbsp;</td>"
        }else{
          $ret .= "$pre&nbsp;&nbsp;&nbsp;&nbsp;</td>"
        }
      #-- normal input of one time
      }else{
        $ret .= "<td class=\"col2\" style=\"text-align:right\"><input type=\"text\" id=\"dt".$key."_s\" size=\"4\" maxlength=\"120\" value=\"$sval\"/></td>";
      }
      #-- Second field 
      $ret .= "<td class=\"col3\"><input type=\"text\" id=\"dt".$key."_x\" size=\"28\" maxlength=\"512\" value=\"$xval\"/></td></tr>\n";
    }    
    $ret .= "</table></td></tr></tr>";
    
   ### weekly profile table ################################################################################################
    $row   = 1;
    $event = "";
    $sval  = "";
    
    my $wupn;    
    my $wt = ( $weeklyno == 1) ? $yaahm_tt->{"profile"} :$yaahm_tt->{"profiles"};
            
    $ret .= "<tr><td colspan=\"3\"><div class=\"devType\" style=\"font-weight:bold; white-space: nowrap;\">".$yaahm_tt->{"weekly"}.$wt.
            "&nbsp;&nbsp;<input type=\"button\" value=\"".$yaahm_tt->{"start"}." ".$yaahm_tt->{"weekly"}.$yaahm_tt->{"timer"}."\" onclick=\"javascript:yaahm_startWeeklyTimer('$name')\"/></div></td></tr>";  
            
    $ret .= "<tr><td><table class=\"readings\" id=\"weeklytable\">\n"; 

    #-- repeat name for every weekly table  
    $ret .= "<tr class=\"odd\"><td class=\"col1\" style=\"font-weight:bold;text-align:left;padding:5px\">".$yaahm_tt->{"name"}."</td>";      
    for (my $i=0;$i<$weeklyno;$i++){
      $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
      $ret .= "<td class=\"col2\" style=\"text-align:left;padding:5px\">$wupn</td>";
    }
    $ret .= "</tr>\n";

    #-- repeat link for every weekly table     
    $ret .= "<tr class=\"even\"><td class=\"col1\" style=\"font-weight:bold;text-align:left;padding:5px\">".$yaahm_tt->{"timer"}."</td>";  
    
    #-- array with activity status
    my @tss;
     
    for (my $i=0;$i<$weeklyno;$i++){
      $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
      #-- timer status
      if( defined($defs{$name.".wtimer_".$i.".IF"})){
        $tl = "<a href=\"/fhem?detail=".$name.".wtimer_".$i.".IF\">".$name.".wtimer_".$i.".IF</a>";
        if( ReadingsVal($name.".wtimer_".$i.".IF","mode","") ne "disabled" ){
          push(@tss,"<div style=\"color:green\">&#x2713;</div>");
        }else{
          push(@tss,"<div style=\"color:red\">&#x274c;</div>");
        }
      }else{
        $tl = $yaahm_tt->{"notstarted"};
         push(@tss,"");
      }   
      $ret .= sprintf("<td class=\"col2\" style=\"text-align:left;padding:5px\"><div id=\"wt%dlink\">%s</div></td>",$i,$tl);
    }
    $ret .= "</tr>\n";
    
    #-- repeat active status for every weekly table  
    my $asg   = "";
    my $ast   = "";
    my $ass;
    my $acc;
    #--header
    for(my $i=0;$i<int(@profmode);$i++){
      $asg .= substr($yaahm_tt->{$profmode[$i]},0,3)."&nbsp;";
      $ast .= $yaahm_tt->{$profmode[$i]}." ";
    }
    for(my $i=0;$i<int(@profday);$i++){
      $asg .= substr($yaahm_tt->{$profday[$i]},0,3)."&nbsp;";
      $ast .= $yaahm_tt->{$profday[$i]}." ";
    }
    $ret .= "<tr class=\"odd\"><td class=\"col1\" style=\"font-weight:bold;text-align:left;padding:5px\">".$yaahm_tt->{"active"}."<br/><div title=\".$ast.\" style=\"font-weight:normal\">".$asg."</div></td>";      
    for (my $i=0;$i<$weeklyno;$i++){
      $wupn = $hash->{DATA}{"WT"}[$i]{"name"};
      $ret .= "<td class=\"col2\" style=\"text-align:center;padding:5px\">".$tss[$i]."</br>";
    
      $asg = "";
      $ass =  ( defined($hash->{DATA}{"WT"}[$i]{"acti_m"}) ) ? $hash->{DATA}{"WT"}[$i]{"acti_m"} : "";
      for( my $j=0;$j<int(@profmode);$j++ ){
        $acc = $profmode[$j];
        $acc = ( $ass =~ /.*$acc.*/ ) ? " checked=\"checked\"" : "";
        $asg .= sprintf("<input type=\"checkbox\" name=\"acti_%d_m\" value=\"".$profmode[$j]."\" $acc/>&nbsp;",$i);
      }
      $ass =  ( defined($hash->{DATA}{"WT"}[$i]{"acti_d"}) ) ? $hash->{DATA}{"WT"}[$i]{"acti_d"} : "";
      for( my $j=0;$j<int(@profday);$j++ ){
        $acc = $profday[$i];
        $acc = ( $ass =~ /.*$acc.*/ ) ? " checked=\"checked\"" : "";
        $asg .= sprintf("<input type=\"checkbox\" name=\"acti_%d_d\"  value=\"".$profday[$j]."\" $acc/>&nbsp;",$i);
      }
      $ret .= "$asg</td>";
    }
    $ret .= "</tr>\n";

    #-- repeat action for every weekly table      
    $ret .= "<tr class=\"odd\"><td class=\"col1\" style=\"font-weight:bold;text-align:left;padding:5px\">".$yaahm_tt->{"action"}."</td>";
    for (my $i=0;$i<$weeklyno;$i++){
      $xval = $hash->{DATA}{"WT"}[$i]{"action"};
      #--
      if( $dh && $i<2 ){
        #-- timeHelper not in command list
        $wupn = ($i==0) ? "wakeup" : "sleep";
        if( $xval !~ /^{$dh/ ){
          if( defined($xval) && length($xval)>0 ){
            $xval ="{".$dh."('".$wupn."')},".$xval;
          }else{
            $xval ="{".$dh."('".$wupn."')}";
          }
        }
      }
      $ret .= sprintf("<td class=\"col2\" style=\"text-align:left;padding:5px\"><input class=\"expand\" type=\"text\" id=\"wt%d_x\" size=\"10\" maxlength=\"512\" value=\"$xval\"/></td>",$i);
    }
    $ret .= "</tr>\n";

    #-- repeat unit for every weekly table  
    $ret .= "<tr class=\"even\"><td></td>";
    for (my $i=0;$i<$weeklyno;$i++){
      $ret .= "<td class=\"col2\" style=\"text-align:left;padding:5px\">".$yaahm_tt->{"time"}." [hh:mm]</td>";
    }
    $ret .= "</tr>\n";
    
    #-- weekday header  
    $ret .= "<tr class=\"even\"><td class=\"col1\" style=\"font-weight:bold;text-align:left;padding:5px\">".$yaahm_tt->{"weekday"}."</td>";
    for (my $i=0;$i<$weeklyno;$i++){
      $ret .= "<td></td>";
    }
    $ret .= "</tr>\n";
            
    for (my $j=0;$j<7;$j++){
      my $key = $weeklytable[$j];
      $row++;
      $event  = $yaahm_tt->{$key}[0];

      $ret .= sprintf("<tr class=\"%s\"><td class=\"col1\" style=\"text-align:left;padding-left:5px\">$event</td>\n", ($row&1)?"odd":"even"); 
      for (my $i=0;$i<$weeklyno;$i++){
        $sval = $hash->{DATA}{"WT"}[$i]{$key};
        $ret .= sprintf("<td class=\"col2\" style=\"text-align:left;padding-left:5px\"><input type=\"text\" id=\"wt%s%d_s\" size=\"4\" maxlength=\"120\" value=\"$sval\"/></td>",$key,$i);
      }
      $ret .= "</tr>\n";
    }    
    $ret .= "</table></td></tr></tr>";
    
    #-- complete the code of the page
	$ret .= "</table>";
	#InternalTimer(gettimeofday()+ 3, "YAAHM_informer", $defs{$FW_cname},0);
 
 return $ret; 
}

1;

=pod
=item helper
=item summary admimistration of profiles for daily, weekly and monthly processes 
=item summary_DE Verwaltung von Profilen für tägliche, wöchentliche und monatliche Abläufe
=begin html

   <a name="YAAHM"></a>
        <h3>YAAHM</h3>
        <p> Yet Another Auto Home Module to set up a cyclic processing of commands (daily, weekly, monthly, yearly profile)</p>
          <a name="YAAHMusage"></a>
        <h4>Usage</h4>
        See <a href="http://www.fhemwiki.de/wiki/Modul_YAAHM">German Wiki page</a>
        <br/>
        <a name="YAAHMdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; YAAHM</code>
            <br />Defines the YAAHM system. </p>
        <a name="YAAHMset"></a>
        Notes: <ul>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
         </ul>
        <h4>Set</h4>
        <ul>
             <li><a name="yaahm_time">
                    <code>set &lt;name&gt; time &lt;timeevent&gt;</code></a><br/>
                    Set the current house time (event), i.e. one of several values:
                    <ul>
                    <li>(after|before) midnight | [before|after] sunrise | [before|after] sunset are calculated from astronomical data (&pm;offset). 
                    These values vary from day to day, only the offset can be specified in the daily profile. </li>
                    <li>morning | noon | afternoon | evening | night are fixed time events specified in the daily profile. 
                    The time phase between events morning and night is called <i>daytime</i>, the 
                    time phase between events night and morning is called <i>nighttime</i></li>
                    <li>wakeup|sleep are time events specified in the weekly default profiles <i>Wakeup</i> and <i>Sleep</i>, i.e. the value may change from day to day.</li>
                    </ul>
                    The actual changes to certain devices are made by the functions in the command field, or by an external <a href="#yaahm_timehelper">timeHelper function</a>.
                  </li>
             <li><a name="yaahm_manualnext">
                    <code>set &lt;name&gt; manualnext &lt;timernumber&gt; &lt;time&gt;</code></a><br/>
                    <code>set &lt;name&gt; manualnext &lt;timername&gt; &lt;time&gt;</code></a><br/>
                    For the weekly timer identified by its number (starting at 0) or its name, set the next ring time manually. The time specification &lt;time&gt;must be in the format hh:mm or "off"
                    If the time specification &lt;time&gt; is later than the current time, it will be used for today. If it is earlier than the current time, it will be used tomorrow.
                  </li>
             <li><a name="yaahm_mode">
                    <code>set &lt;name&gt; mode normal | party | absence</code>
                </a>
                <br />Set the current house mode, i.e. one of several values:
                <ul>
                <li>normal - normal daily and weekly time profiles apply</li>
                <li>party - can be used in the timeHelper function to suppress certain actions, like e.g. those that set the house (security) state to <i>secured</i> or the house time event to <i>night</i>.</li>
                <li>absence - can be used in the timeHelper function to suppress certain actions. Valid until manual mode change</li>
                </ul>
                House modes are valid until manual mode change. If the attribute <i>modeAuto</i> is set (see below), mode will change automatically at certain time events.
                The actual changes to certain devices are made by an external <a href="#yaahm_modehelper">modeHelper function</a>.
                </li>   
              <li><a name="yaahm_state">
                    <code>set &lt;name&gt; state unsecured | secured | protected | guarded</code>
                </a>
                <br/>Set house (security) state, i.e. one of several values:
                  <ul>
                    <li> unsecured - Example: doors etc. 
                    </li>
                    <li> secured - Example: doors etc. are locked, windows may not be open
                    </li>
                    <li> protected - Example: doors etc. are locked, windows may not be open, alarm system is armed
                    </li>
                    <li> guarded - Example: doors etc. are locked, windows may not be open, alarm is armed, a periodic house check is run and a simulation as well
                    </li>
                  </ul>
                  House (security) states are valid until manual change. If the attribute <i>stateAuto</i> is set (see below), state will change automatically at certain times.
                  The actual changes to certain devices are made by an external <a href="#yaahm_statehelper">stateHelper function</a>. If these external devices are in their proper state 
                  for a particular house (security) state can be checked automatically, see the attribute  <a href="#yaahm_statedevices">stateDevices</a>
                  </li>
                </li>      
             <li><a name="yaahm_createweekly">
                    <code>set &lt;name&gt; createWeekly &lt;string&gt;</code>
                </a>
                <br/>Create a new weekly profile &lt;string&gt;</li>
            <li><a name="yaahm_deleteweekly">
                    <code>set &lt;name&gt; deleteWeekly &lt;string&gt;</code>
                </a>
                <br/>Delete the weekly profile &lt;string&gt;</li>
            <li><a name="yaahm_initialize">
                    <code>set &lt;name&gt; initialize</code>
                </a>
                <br/>Restart the internal timers</li>
            <li><a name="yaahm_lock">
                    <code>set &lt;name&gt; locked|unlocked</code>
                </a>
                <br />Set the lockstate of the yaahm module to <i>locked</i> (i.e., yaahm setups
                may not be changed) resp. <i>unlocked</i> (i.e., yaahm setups may be changed>)</li>
        </ul>
        <a name="YAAHMget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="yaahm_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>
            <li><a name="yaahm_template"></a>
                <code>get &lt;name&gt; template</code>
                <br />Return an (empty) perl subroutine for the helper functions</li>
        </ul>
        <a name="YAAHMattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="yaahm_linkname"><code>attr &lt;name&gt; linkname
                    &lt;string&gt;</code></a>
                <br />Name for yaahm web link, default:
                Profile</li>
            <li><a name="yaahm_hiddenroom"><code>attr &lt;name&gt; hiddenroom
                    &lt;string&gt;</code></a>
                <br />Room name for hidden yaahm room (containing only the YAAHM device), default:
                ProfileRoom</li>
            <li><a name="yaahm_lockstate"><code>attr &lt;name&gt; lockstate
                    locked|unlocked</code></a>
                <br /><i>locked</i> means that yaahm setups may not be changed, <i>unlocked</i>
                means that yaahm setups may be changed</li>
            <li><a name="yaahm_simulation"><code>attr &lt;name&gt; simulation
                    0|1</code></a>
                <br />a value of 1 means that commands will not be executed, but only simulated</li>
            <li><a name="yaahm_timehelper"><code>attr &lt;name&gt; timeHelper &lt;name of perl program&gt;</code></a>
                <br />name of a perl function that is called at each time step of the daily profile and for the two default weekly profiles</li>
            <li><a name="yaahm_modehelper"><code>attr &lt;name&gt; modeHelper &lt;name of perl program&gt;</code></a>
                <br />name of a perl function that is called at every change of the house mode</li>
             <li><a name="yaahm_modeauto"><code>attr &lt;name&gt; modeAuto 0|1</code></a>
                <br />If this attribute is set to 1, the house mode changes automatically at certain time events.
                <ul>
                <li>On time (event) <i>sleep</i> or <i>morning</i>, <i>party</i> mode will be reset to <i>normal</i> mode.</li>
                <li>On time (event) <i>wakeup</i>, <i>absence</i> mode will be reset to <i>normal</i> mode.</li>
                </ul>
                </li>          
            <li><a name="yaahm_statedevices"><code>attr &lt;name&gt; stateDevices (&lt;device&gt;:&lt;state-unsecured&gt;:&lt;state-secured&gt;:&lt;state-protected&gt;:&lt;state-guarded&gt;,)*</code></a>
                <br />comma separated list of devices and their state in each of the house (security) states. Each of the listed devices will be checked in the interval given by the <i>stateInterval</i> attribute
                for its proper state, and a <i>stateWarning</i> function will be called if it is not in the proper state.</li>
            <li><a name="yaahm_stateinterval"><code>attr &lt;name&gt; stateInterval &lt;integer&gt;</code></a>
                <br />interval in minutes for checking all <i>stateDevices</i> for their proper state according of the house (security) state. Default 60 minutes.</li>
            <li><a name="yaahm_statewarning"><code>attr &lt;name&gt; stateWarning &lt;name of perl program&gt;</code></a>
                <br />name of a perl function that is called as <i>stateWarning('device','desired state','actual state')</i>if a device is not in the desired state.</li>
            <li><a name="yaahm_statehelper"><code>attr &lt;name&gt; stateHelper &lt;name of perl program&gt;</code></a>
                <br />name of a perl function that is called as <i>stateHelper('event')</i> at every change of the house (security) state</li>
            <li><a name="yaahm_stateauto"><code>attr &lt;name&gt; stateAuto 0|1</code></a>
                <br />If this attribute is set to 1, the house state changes automatically if certain modes are set or at certain time events
                <ul>
                <li>If leaving <i>party</i> mode and time event <i>sleep</i>, and currently in (security) state <i>unsecured</i>, the state will change to <i>secured</i>.</li>
                <li>If in <i>normal</i> mode and time event <i>sleep</i> or <i>night</i>, and currently in (security) state <i>unsecured</i>, the state will change to <i>secured</i>.</li>
                </ul>
                </li>
            <li><a name="yaahm_holidaydevices"><code>attr &lt;name&gt; &lt;comma-separated list of devices&gt; </code></a>
                <br />list of devices that provide holiday information. The devices may be 
                <a href="#holiday">holiday devices</a> or <a href="#Calendar">Calendar devices</a></li>
            <li><a name="yaahm_vacationdevices"><code>attr &lt;comma-separated list of devices&gt; </code></a>
                <br />list of devices that provide vacation information. The devices may be 
                <a href="#holiday">holiday devices</a> or <a href="#Calendar">Calendar devices</a></li>
            <li><a name="yaahm_specialdevices"><code>attr &lt;comma-separated list of devices&gt; </code></a>
                <br />list of devices that provide special date information (like e.g. garbage collection). The devices may be 
                <a href="#holiday">holiday devices</a> or <a href="#Calendar">Calendar devices</a></li>
        </ul>
=end html
=begin html_DE

<a name="YAAHM"></a>
<h3>YAAHM</h3>
<a href="https://wiki.fhem.de/wiki/Modul_YAAHM">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/commandref.html#YAAHM">YAAHM</a> 
=end html_DE
=cut
