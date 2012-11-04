########################################################################################
#
# OWAD.pm
#
# WIESO UNINITIALIZED in 623FF
#
# FHEM module to commmunicate with 1-Wire A/D converters DS2450
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
# OWX  = 1-Wire bus master interface (Peter Henning)
# OWFS = 1-Wire file system (??)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.25 - October, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWAD [<model>] <ROM_ID> [interval] 
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2450 A/D converter 
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id       => FAM_ID.ROM_ID.CRC 
# get <name> present  => 1 if device present, 0 if not
# get <name> interval => query interval
# get <name> reading  => measurement for all channels
# get <name> alarm    => alarm measurement settings for all channels
# get <name> status   => alarm and i/o status for all channels
#
# set <name> interval => set period for measurement
#
# Additional attributes are defined in fhem.cfg, in some cases per channel, where <channel>=A,B,C,D
# Note: attributes are read only during initialization procedure - later changes are not used.
#
# attr <name> event on-change/on-update = when to write an event (default= on-update)
#
# attr <name> stateAL0  "<string>"     = character string for denoting low normal condition, default is empty, 
#             overwritten by attribute setting green down triangle
# attr <name> stateAH0  "<string>"     = character string for denoting high normal condition, default is empty, 
#             overwritten by attribute setting green up triangle
# attr <name> stateAL1  "<string>"     = character string for denoting low alarm condition, default is l, 
#             overwritten by attributre setting red down triangle
# attr <name> stateAH1  "<string>"     = character string for denoting high alarm condition, default is h, 
#             overwritten by attributre setting red up triangle
# attr <name> <channel>Name   <string>|<string> = name for the channel | a type description for the measured value
# attr <name> <channel>Unit   <string>|<string> = unit of measurement for this channel | its abbreviation 
# attr <name> <channel>Offset <float>  = offset added to the reading in this channel 
# attr <name> <channel>Factor <float>  = factor multiplied to (reading+offset) in this channel 
# attr <name> <channel>Alarm  <string> = alarm setting in this channel, either both, low, high or none (default) 
# attr <name> <channel>Low    <float>  = measurement value (on the scale determined by offset and factor) for low alarm 
# attr <name> <channel>High   <float>  = measurement value (on the scale determined by offset and factor) for high alarm 
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

#-- Prototypes to make komodo happy
use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

#-- value globals
my @owg_status;
my $owg_state;
#-- channel name - fixed is the first array, variable the second 
my @owg_fixed = ("A","B","C","D");
my @owg_channel;
#-- channel values - always the raw values from the device
my @owg_val;
#-- channel mode - fixed for now
my @owg_mode = ("input","input","input","input");
#-- resolution in bit - fixed for now
my @owg_resoln = (16,16,16,16);
#-- raw range in mV - fixed for now
my @owg_range = (5100,5100,5100,5100);
#-- alarm status 0 = disabled, 1 = enabled, but not alarmed, 2 = alarmed
my @owg_slow;
my @owg_shigh; 
#-- alarm values - always the raw values committed to the device
my @owg_vlow;
my @owg_vhigh;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "reading"     => "",
  "alarm"       => "",
  "status"      => "",
);

my %sets = (
  "interval"    => ""
);

my %updates = (
  "present"     => "",
  "reading"     => "",
  "alarm"       => "",
  "status"      => ""
);


########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWAD
#
########################################################################################
#
# OWAD_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWAD_Define";
  $hash->{UndefFn} = "OWAD_Undef";
  $hash->{GetFn}   = "OWAD_Get";
  $hash->{SetFn}   = "OWAD_Set";
  #Name        = channel name
  #Offset      = a v(oltage) offset added to the reading
  #Factor      = a v(oltage) factor multiplied with (reading+offset)  
  #Unit        = a unit of measure
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2450 loglevel:0,1,2,3,4,5 ".
                "stateAL0 stateAL1 stateAH0 stateAH1 event:on-update,on-change ";
 
  for( my $i=0;$i<4;$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Offset";
    $attlist .= " ".$owg_fixed[$i]."Factor";
    $attlist .= " ".$owg_fixed[$i]."Unit";
    $attlist .= " ".$owg_fixed[$i]."Alarm";
    $attlist .= " ".$owg_fixed[$i]."Low";
    $attlist .= " ".$owg_fixed[$i]."High";
  }
  $hash->{AttrList} = $attlist; 
}

#########################################################################################
#
# OWAD_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWAD_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWAD [<model>] <id> [interval]
  # e.g.: define flow OWAD 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWAD: Wrong syntax, must be define <name> OWAD [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2450";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    return "OWAD: Wrong 1-Wire device model $model"
      if( $model ne "DS2450");
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
  } else {    
    return "OWAD: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC("20.".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = "20.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = "20";
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWAD: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWAD}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWAD:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+10, "OWAD_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 0);

  return undef; 
}

########################################################################################
#
# OWAD_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
  
  #-- more colorful alarm signatures
  CommandAttr (undef,"$name stateAL1 <span style=\"color:red\">&#x25BE;</span>")
     if( !defined($attr{$name}{"stateAL1"} ));
  CommandAttr (undef,"$name stateAH1 <span style=\"color:red\">&#x25B4;</span>")
     if( !defined($attr{$name}{"stateAH1"} ));
  CommandAttr (undef,"$name stateAL0 <span style=\"color:green\">&#x25BE;</span>")
     if( !defined($attr{$name}{"stateAL0"} ));
  CommandAttr (undef,"$name stateAH0 <span style=\"color:green\">&#x25B4;</span>")
     if( !defined($attr{$name}{"stateAH0"} ));
  
  #-- Initial readings 
  @owg_val   = (0.0,0.0,0.0,0.0);
  @owg_slow  = (0,0,0,0);
  @owg_shigh = (0,0,0,0);  
   
  #-- Set channel names, channel units and alarm values
  for( my $i=0;$i<int(@owg_fixed);$i++) { 
    #-- name
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|voltage";
    my @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      Log 1, "OWAD: Incomplete channel name specification $cname. Better use $cname|<type of data>";
      push(@cnama,"unknown");
    }
 
    #-- unit
    my $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "Volt|V";
    my @unarr= split(/\|/,$unit);
    if( int(@unarr)!=2 ){
      Log 1, "OWAD: Incomplete channel unit specification $unit. Better use $unit|<abbreviation>";
      push(@unarr,"");  
    }
  
    #-- offset and scale factor 
    my $offset  = defined($attr{$name}{$owg_fixed[$i]."Offset"}) ? $attr{$name}{$owg_fixed[$i]."Offset"} : 0.0;
    my $factor  = defined($attr{$name}{$owg_fixed[$i]."Factor"}) ? $attr{$name}{$owg_fixed[$i]."Factor"} : 1.0; 
    #-- put into readings
    $owg_channel[$i] = $cnama[0]; 
    $hash->{READINGS}{"$owg_channel[$i]"}{TYPE}     = $cnama[1];  
    $hash->{READINGS}{"$owg_channel[$i]"}{UNIT}     = $unarr[0];
    $hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR} = $unarr[1];
    $hash->{READINGS}{"$owg_channel[$i]"}{OFFSET}   = $offset;  
    $hash->{READINGS}{"$owg_channel[$i]"}{FACTOR}   = $factor;  
    
    #-- alarm
    my $alarm = defined($attr{$name}{$owg_fixed[$i]."Alarm"}) ? $attr{$name}{$owg_fixed[$i]."Alarm"} : "none";
    my $vlow  = defined($attr{$name}{$owg_fixed[$i]."Low"})   ? $attr{$name}{$owg_fixed[$i]."Low"}   : 0.0;
    my $vhigh = defined($attr{$name}{$owg_fixed[$i]."High"})  ? $attr{$name}{$owg_fixed[$i]."High"}  : 5.0;
    if( $alarm eq "low" || $alarm eq "both" ){
       $owg_slow[$i]=1;
    }
    if( $alarm eq "high" || $alarm eq "both" ){
       $owg_shigh[$i]=1;
    };
    $owg_vlow[$i]  = ($vlow/$factor - $offset);
    $owg_vhigh[$i] = ($vhigh/$factor - $offset);
  }
  
  #-- set status according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- OWX interface
  if( !defined($interface) ){
    return "OWAD: Interface missing";
  } elsif( $interface eq "OWX" ){
    OWXAD_SetPage($hash,"alarm");
    OWXAD_SetPage($hash,"status");
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  }else{
    return "OWAD: InitializeDevice with wrong IODev type $interface";
  }

  #-- Initialize all the display stuff  
  OWAD_FormatValues($hash);
}

########################################################################################
#
# OWAD_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWAD_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$vval,$vlow,$vhigh);
  my ($value1,$value2,$value3)   = ("","","");
  my $galarm = 0;

  my $tn = TimeNow();
  
  #-- alarm signatures
  my $stateal1 = defined($attr{$name}{stateAL1}) ? $attr{$name}{stateAL1} : "l";
  my $stateah1 = defined($attr{$name}{stateAH1}) ? $attr{$name}{stateAH1} : "h";
  my $stateal0 = defined($attr{$name}{stateAL0}) ? $attr{$name}{stateAL0} : "";
  my $stateah0 = defined($attr{$name}{stateAH0}) ? $attr{$name}{stateAH0} : "";
  
  #-- formats for output
  for (my $i=0;$i<int(@owg_fixed);$i++){
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|voltage";
    my @cnama = split(/\|/,$cname);
    $owg_channel[$i]=$cnama[0];
    $offset = $hash->{READINGS}{"$owg_channel[$i]"}{OFFSET};  
    $factor = $hash->{READINGS}{"$owg_channel[$i]"}{FACTOR};
    #-- correct values for proper offset, factor 
    $vval    = int(($owg_val[$i] + $offset)*$factor*1000)/1000;; 
    #-- put into READINGS
    $hash->{READINGS}{"$owg_channel[$i]"}{VAL}   = $vval;
    $hash->{READINGS}{"$owg_channel[$i]"}{TIME}  = $tn;
    
    #-- correct alarm values for proper offset, factor 
    $vlow  = int(($owg_vlow[$i]  + $offset)*$factor*1000)/1000;
    $vhigh = int(($owg_vhigh[$i] + $offset)*$factor*1000)/1000;

    #-- put into READINGS
    $hash->{READINGS}{$owg_channel[$i]."Low"}{VAL}     = $vlow;
    $hash->{READINGS}{$owg_channel[$i]."Low"}{TIME}    = $tn;
    $hash->{READINGS}{$owg_channel[$i]."High"}{VAL}    = $vhigh;
    $hash->{READINGS}{$owg_channel[$i]."High"}{TIME}   = $tn;
         
    #-- string buildup for return value, STATE and alarm
    $value1 .= sprintf( "%s: %5.3f %s", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
    $value2 .= sprintf( "%s: %5.2f %s ", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
    $value3 .= sprintf( "%s: " , $owg_channel[$i]);
   
    #-- Test for alarm condition
    #-- alarm signature low
    if( $owg_slow[$i] == 0 ) {
      #$value2 .= " ";
      $value3 .= "-";
    } else {
      if( $vval > $vlow ){
        $owg_slow[$i] = 1;
        $value2 .=  $stateal0;
        $value3 .=  $stateal0; 
      } else {
        $galarm = 1;
        $owg_slow[$i] = 2;
        $value2 .=  $stateal1;
        $value3 .=  $stateal1;
      }
    }
    #-- alarm signature high
    if( $owg_shigh[$i] == 0 ) {
      #$value2 .= " ";
      $value3 .= "-";   
    } else {
      if( $vval < $vhigh ){
        $owg_shigh[$i] = 1;
        $value2 .=  $stateah0;
        $value3 .=  $stateah0;
      } else {
        $galarm = 1;
        $owg_shigh[$i] = 2;
        $value2 .=  $stateah1;
        $value3 .=  $stateah1;
      }
    }
    
    #-- insert comma
    if( $i<int(@owg_fixed)-1 ){
      $value1 .= " ";
      $value2 .= ", ";
      $value3 .= ", ";
    }
  }
  #-- STATE
  $hash->{STATE} = $value2;
  #-- alarm
  $hash->{ALARM} = $galarm;
  $hash->{READINGS}{alarms}{VAL}  = $value3;
  $hash->{READINGS}{alarms}{TIME}   = $tn;
  return $value1;
}

########################################################################################
#
# OWAD_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWAD_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my ($value,$value2,$value3)   = (undef,undef,undef);
  my $ret     = "";
  my $offset;
  my $factor;

  #-- check syntax
  return "OWAD: Get argument is missing @a"
    if(int(@a) != 2);
    
  #-- check argument
  return "OWAD: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));

  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$name.id => $value";
  } 
  
  #-- get present
  if($a[1] eq "present") {
    #-- hash of the busmaster
    my $master       = $hash->{IODev};
    $value           = OWX_Verify($master,$hash->{ROM_ID});
    $hash->{PRESENT} = $value;
    return "$name.present => $value";
  } 

  #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$name.interval => $value";
  } 
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- get reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if($a[1] eq "reading") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"reading");
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process results
    if( defined($ret)  ){
      return "OWAD: Could not get values from device $name";
    }
    $hash->{PRESENT} = 1; 
    return "OWAD: $name.$reading => ".OWAD_FormatValues($hash);
  }
  
  #-- get alarm values according to interface type
  if($a[1] eq "alarm") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"alarm");
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"alarm");
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process results
    if( defined($ret)  ){
      return "OWAD: Could not get values from device $name";
    }
    $hash->{PRESENT} = 1; 
    OWAD_FormatValues($hash);
    
    #-- output string looks differently here
    $value = "";
    for (my $i=0;$i<int(@owg_fixed);$i++){
      $value .= sprintf "%s:[%4.2f,%4.2f] ",$owg_channel[$i],
      $hash->{READINGS}{$owg_channel[$i]."Low"}{VAL},
      $hash->{READINGS}{$owg_channel[$i]."High"}{VAL}; 
    }
    return "OWAD: $name.$reading => $value";
  }
  
  #-- get status values according to interface type
  if($a[1] eq "status") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"status");
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"status");
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process results
    if( defined($ret)  ){
      return "OWAD: Could not get values from device $name";
    }
    $hash->{PRESENT} = 1; 
    OWAD_FormatValues($hash);
    return "OWAD: $name.$reading => ".$hash->{READINGS}{alarms}{VAL};
  }
}

#######################################################################################
#
# OWAD_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = "";
  my $ret     = "";
  my $offset;
  my $factor;
  
  #-- define warnings
  my $warn        = "none";
  $hash->{ALARM}  = "0";

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 1);
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- Get readings, alarms and stati according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXAD_GetPage($hash,"reading");
    $ret = OWXAD_GetPage($hash,"alarm");
    $ret = OWXAD_GetPage($hash,"status");
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetValues($hash);
  }else{
    return "OWAD: GetValues with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWAD: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  
  #-- old state, new state
  my $oldval = $hash->{STATE};
  $value=OWAD_FormatValues($hash);
  my $newval =  $hash->{STATE};
   #--logging depends on setting of the event-attribute
  Log 5, $value;
  my $ev = defined($attr{$name}{"event"})  ? $attr{$name}{"event"} : "on-update";  
  if( ($ev eq "on-update") || (($ev eq "on-change") && ($newval ne $oldval)) ){
     $hash->{CHANGED}[0] = $value;
     DoTrigger($name, undef);
  } 
  
  return undef;
}

#######################################################################################
#
# OWAD_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWAD_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", sort keys %sets);
    for( my $i=0;$i<int(@owg_fixed);$i++ ){
      $newkeys .= " ".$owg_channel[$i]."Alarm";
      $newkeys .= " ".$owg_channel[$i]."Low";
      $newkeys .= " ".$owg_channel[$i]."High";
    }
    return $newkeys ;    
  }
  
  #-- check syntax
  return "OWAD: Set needs one parameter when setting this value"
    if( int(@a)!=3 );
  
  #-- check argument
  if( !defined($sets{$a[1]}) && !($key =~ m/.*(Alarm|Low|High)/) ){
        return "OWAD: Set with unknown argument $a[1]";
  }
  
  #-- define vars
  my $ret     = undef;
  my $channel = undef;
  my $channo  = undef;
  my $factor;
  my $offset;
  my $condx;
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
 
 #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWAD: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 1);
    return undef;
  }
  
  #-- find out which channel we have
  my $tc =$key;
  if( $tc =~ s/(.*)(Alarm|Low|High)/$channel=$1/se ) {
    for (my $i=0;$i<int(@owg_fixed);$i++){
      if( $tc eq $owg_channel[$i] ){
        $channo  = $i;
        $channel = $tc;
        last;
      }
    }
  }
  return "OWAD: Cannot determine channel from parameter $a[1]"
    if( !(defined($channo)));  
    
  #-- set these values depending on interface type
  my $interface= $hash->{IODev}->{TYPE};
        
  #-- check alarm values
  if( $key =~ m/(.*)(Alarm)/ ) {
    return "OWAD: Set with wrong value $value for $key, allowed is none/low/high/both"
      if($value ne "none" &&  $value ne "low" &&  $value ne "high" &&  $value ne "both");
    if( $value eq "low" || $value eq "both" ){
       $owg_slow[$channo]=1;
    } else{
       $owg_slow[$channo]=0;
    }
    if( $value eq "high" || $value eq "both" ){
       $owg_shigh[$channo]=1;
    } else{
       $owg_shigh[$channo]=0;
    }    
   
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_SetPage($hash,"status");
      return $ret
        if(defined($ret));
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_SetValues($hash,@a);
    #  return $ret
    #    if(defined($ret));
    } else {
      return "OWAD: Set with wrong IODev type $interface";
    }
  }elsif( $key =~ m/(.*)(Low|High)/ ) {
    $offset = $attr{$name}{$owg_fixed[$channo]."Offset"};
    $factor = $attr{$name}{$owg_fixed[$channo]."Factor"};
    
    #-- find upper and lower boundaries for given offset/factor
    my $mmin = 0.0;
 
    $mmin +=  $offset if ( $offset );   
    $mmin *=  $factor if ( $factor );  

    my $mmax = $owg_range[$channo]/1000;
    $mmax += $offset if ( $offset );
    $mmax *= $factor if ( $factor ); 

    return sprintf("OWAD: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
      if($value < $mmin || $value > $mmax);
    
    $value  /= $factor if ( $factor );
    $value  -= $offset if ( $offset );
    #-- round to those numbers understood by the device
    my $value2  = int($value*255000/$owg_range[$channo])*$owg_range[$channo]/255000;
 
    #-- set alarm value in the device
    if( $key =~ m/(.*)Low/ ){
      $owg_vlow[$channo]  = $value2;
    } elsif( $key =~ m/(.*)High/ ){
      $owg_vhigh[$channo]  = $value2;
    }
  
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_SetPage($hash,"alarm");
      return $ret
        if(defined($ret));
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_SetValues($hash,@a);
    #  return $ret
    #    if(defined($ret));
    } else {
      return "OWAD: Set with wrong IODev type $interface";
    }
  }
  
  #-- process results - we have to reread the device
  $hash->{PRESENT} = 1; 
  OWAD_GetValues($hash);  
  OWAD_FormatValues($hash);  
  Log 4, "OWAD: Set $hash->{NAME} $key $value";

  return undef;
}

########################################################################################
#
# OWAD_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_Undef ($) {
  my ($hash) = @_;
  delete($modules{OWAD}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSAD
#
########################################################################################





########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXAD
#
########################################################################################
#
# OWXAD_GetPage - Get one memory page from device
#
# Parameter hash = hash of device addressed
#           page = "reading", "alarm" or "status"
#
########################################################################################

sub OWXAD_GetPage($$) {

  my ($hash,$page) = @_;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);

  #=============== get the voltage reading ===============================
  if( $page eq "reading") {
    OWX_Reset($master);
    #-- issue the match ROM command \x55 and the start conversion command
    $res= OWX_Complex($master,$owx_dev,"\x3C\x0F\x00\xFF\xFF",0);
    if( $res eq 0 ){
      return "OWXAD: Device $owx_dev not accessible for conversion";
    } 
    #-- conversion needs some 5 ms per channel
    select(undef,undef,undef,0.02);
    
    #-- issue the match ROM command \x55 and the read conversion page command
    #   \xAA\x00\x00 
    $select="\xAA\x00\x00";
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the read alarm page command 
    #   \xAA\x10\x00 
    $select="\xAA\x10\x00";
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
    #-- issue the match ROM command \x55 and the read status memory page command 
    #   \xAA\x08\x00 r
  $select="\xAA\x08\x00";
  #=============== wrong value requested ===============================
  } else {
    return "OWXAD: Wrong memory page requested";
  } 
  
  #-- reset the bus
  OWX_Reset($master);
  #-- reading 9 + 3 + 8 data bytes and 2 CRC bytes = 22 bytes
  $res=OWX_Complex($master,$owx_dev,$select,10);
  #Log 1, "OWXAD: Device $owx_dev returns data of length ".length($res);
  if( $res eq 0 ){
    return "OWXAD: Device $owx_dev not accessible in reading $page page"; 
  }
  
  #-- reset the bus
  OWX_Reset($master);
  
  #-- process results
  @data=split(//,$res);
  return "OWXAD: invalid data length, ".int(@data)." bytes"
    if (@data != 22); 
  #return "invalid data"
  #  if (ord($data[17])<=0); 
  #return "invalid CRC"
  #  if (OWX_CRC8(substr($res,10,8),$data[18])==0);  
    
  #=============== get the voltage reading ===============================
  if( $page eq "reading"){
    for( $i=0;$i<int(@owg_fixed);$i++){
      $owg_val[$i]= int((ord($data[12+2*$i])+256*ord($data[13+2*$i]))/((1<<$owg_resoln[$i])-1) * $owg_range[$i])/1000;
    }
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    for( $i=0;$i<int(@owg_fixed);$i++){
      $owg_vlow[$i]  = int(ord($data[12+2*$i])/255 * $owg_range[$i])/1000;
      $owg_vhigh[$i] = int(ord($data[13+2*$i])/255 * $owg_range[$i])/1000;
    }
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
   my ($sb1,$sb2);
   for( $i=0;$i<int(@owg_fixed);$i++){
      $sb1 = ord($data[12+2*$i]); 
      $sb2 = ord($data[12+2*$i+1]);
      
      #-- normal operation 
      if( $sb1 && 128) {
        #-- put into globals
        $owg_mode[$i]   =  "input";
        $owg_resoln[$i] =  ($sb1 & 15) + 1 ;
        $owg_range[$i]  =  ($sb2 & 1) ? 5100 : 2550;
        #-- low alarm disabled
        if( ($sb2 & 4)==0 ){  
          $owg_slow[$i] = 0;
        }else {
          #-- low alarm enabled and not set
          if ( ($sb2 & 16)==0  ){
            $owg_slow[$i] = 1;
          #-- low alarm enabled and set
          }else{
            $owg_slow[$i] = 2;
          }
        }  
        #-- high alarm disabled
        if( ($sb2 & 8)==0 ){  
          $owg_shigh[$i] = 0;
        }else {
          #-- high alarm enabled and not set
          if ( ($sb2 & 32)==0  ){
            $owg_shigh[$i] = 1;
          #-- high alarm enabled and set
          }else{
            $owg_shigh[$i] = 2;
          }
        }  
        
        #-- assemble status string
        $owg_status[$i] = $owg_mode[$i].", ";
        $owg_status[$i] .= "disabled ," 
          if ( !($sb2 && 128) );
        $owg_status[$i] .=  sprintf "raw range %3.1f V, ",$owg_range[$i]/1000;
        $owg_status[$i] .=  sprintf "resolution %d bit, ",$owg_resoln[$i];
        $owg_status[$i] .=  sprintf "low alarm disabled, "
          if( $owg_slow[$i]==0 );
        $owg_status[$i] .=  sprintf "low alarm enabled, "
          if( $owg_slow[$i]==1 );
        $owg_status[$i] .=  sprintf "alarmed low, "
          if( $owg_slow[$i]==2 );
        $owg_status[$i] .=  sprintf "high alarm disabled"
          if( $owg_shigh[$i]==0 );
        $owg_status[$i] .=  sprintf "high alarm enabled"
          if( $owg_shigh[$i]==1 );
        $owg_status[$i] .=  sprintf "alarmed high"
          if( $owg_shigh[$i]==2 );
          
      } else {
        $owg_mode[$i]   =  "output";
        #-- assemble status string
        $owg_status[$i] = $owg_mode[$i].", ";
        $owg_status[$i] .=  ($sb1 & 64 ) ? "ON" : "OFF";
      }
    }
  } 
  return undef
}

########################################################################################
#
# OWXAD_SetPage - Set one page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWXAD_SetPage($$) {

  my ($hash,$page) = @_;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);
  
  #=============== set the alarm values ===============================
  if ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the set alarm page command 
    #   \x55\x10\x00 reading 8 data bytes and 2 CRC bytes
    $select="\x55\x10\x00";
    for( $i=0;$i<4;$i++){
      $select .= sprintf "%c\xFF\xFF\xFF",int($owg_vlow[$i]*255000/$owg_range[$i]);
      $select .= sprintf "%c\xFF\xFF\xFF",int($owg_vhigh[$i]*255000/$owg_range[$i]);
    }
  #=============== set the status ===============================
  } elsif ( $page eq "status" ) {
    my ($sb1,$sb2);
    #-- issue the match ROM command \x55 and the set status memory page command 
    #   \x55\x08\x00 reading 8 data bytes and 2 CRC bytes
    $select="\x55\x08\x00";
    for( $i=0;$i<4;$i++){
      if( $owg_mode[$i] eq "input" ){
        #-- resolution (TODO: check !)
        $sb1 = $owg_resoln[$i]-1;
        #-- alarm enabled
        $sb2 =  ( $owg_slow[$i] > 0  ) ? 4 : 0;
        $sb2 += ( $owg_shigh[$i] > 0 ) ? 8 : 0;
        #-- range 
        $sb2 |= 1 
          if( $owg_range[$i] > 2550 );
      } else {
        $sb1 = 128;
        $sb2 = 0;
      }
      $select .= sprintf "%c\xFF\xFF\xFF",$sb1;
      $select .= sprintf "%c\xFF\xFF\xFF",$sb2;
    }
  #=============== wrong page write attempt  ===============================
  } else {
    return "OWXAD: Wrong memory page write attempt";
  } 
  
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  
  #-- process results
  if( $res eq 0 ){
    return "OWXAD: Device $owx_dev not accessible for writing"; 
  }
  
  return undef;
}

1;

=pod
=begin html

<a name="OWAD"></a>
<h3>OWAD</h3>
<ul>FHEM module to commmunicate with 1-Wire A/D converters<br /><br /> Note:<br /> This
    1-Wire module so far works only with the OWX interface module. Please define an <a
        href="#OWX">OWX</a> device first. <br />
    <br /><b>Example</b><br />
    <ul>
        <code>define OWX_AD OWAD 724610000000 45</code>
        <br />
        <code>attr OWX_AD DAlarm high</code>
        <br />
        <code>attr OWX_AD DFactor 31.907097</code>
        <br />
        <code>attr OWX_AD DHigh 50.0</code>
        <br />
        <code>attr OWX_AD DName relHumidity|humidity</code>
        <br />
        <code>attr OWX_AD DOffset -0.8088</code>
        <br />
        <code>attr OWX_AD DUnit percent|%</code>
        <br />
    </ul><br />
    <a name="OWADdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; OWAD [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code>
        <br /><br /> Define a 1-Wire A/D converter.<br /><br />
        <li>
            <code>[&lt;model&gt;]</code><br /> Defines the A/D converter model (and thus
            1-Wire family id), currently the following values are permitted: <ul>
                <li>model DS2450 with family id 20 (default if the model parameter is
                    omitted)</li>
            </ul>
        </li>
        <li>
            <code>&lt;id&gt;</code>
            <br />12-character unique ROM id of the converter device without family id and
            CRC code </li>
        <li>
            <code>&lt;interval&gt;</code>
            <br />Measurement interval in seconds. The default is 300 seconds. </li>
        <br />
    </ul>
    <br />
    <a name="OWADset">
        <b>Set</b></a>
    <ul>
        <li><a name="owad_interval">
                <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
            interval in seconds. The default is 300 seconds. </li>
    </ul>
    <br />
    <a name="OWADget">
        <b>Get</b></a>
    <ul>
        <li><a name="owad_id">
                <code>get &lt;name&gt; id</code></a>
            <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
        <li><a name="owad_present">
                <code>get &lt;name&gt; present</code>
            </a>
            <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
        <li><a name="owad_interval2">
                <code>get &lt;name&gt; interval</code></a><br />Returns measurement interval
            in seconds. </li>
        <li><a name="owad_reading">
                <code>get &lt;name&gt; reading</code></a><br />Obtain the measuement values. </li>
        <li><a name="owad_alarm">
                <code>get &lt;name&gt; alarm</code></a><br />Obtain the alarm values. </li>
        <li><a name="owad_status">
                <code>get &lt;name&gt; status</code></a><br />Obtain the i/o status values.
        </li>
    </ul>
    <br />
    <a name="OWADattr">
        <b>Attributes</b></a>
    <ul>
        <li><a name="owad_stateAL0"><code>attr &lt;name&gt; stateAL0
                &lt;string&gt;</code></a>
            <br />character string for denoting low normal condition, default is green down
            triangle, e.g. the code &lt;span
            style="color:green"&gt;&amp;#x25BE;&lt;/span&gt; leading to the sign <span
                style="color:green">&#x25BE;</span>
        </li>
        <li><a name="owad_stateAH0"><code>attr &lt;name&gt; stateAH0
                &lt;string&gt;</code></a>
            <br />character string for denoting high alarm condition, default is green
            upward triangle, e.g. the code &lt;span
            style="color:green"&gt;&amp;#x25B4;&lt;/span&gt; leading to the sign <span
                style="color:green">&#x25B4;</span>
        </li>
        <li><a name="owad_stateAL1"><code>attr &lt;name&gt; stateAL1
                &lt;string&gt;</code></a>
            <br />character string for denoting low alarm condition, default is red down
            triangle, e.g. the code &lt;span style="color:red"&gt;&amp;#x25BE;&lt;/span&gt;
            leading to the sign <span style="color:red">&#x25BE;</span></li>
        <li><a name="owad_stateAH1"><code>attr &lt;name&gt; stateAH1
                &lt;string&gt;</code></a>
            <br />character string for denoting high alarm condition, default is red upward
            triangle, e.g. the code &lt;span style="color:red"&gt;&amp;#x25B4;&lt;/span&gt;
            leading to the sign <span style="color:red">&#x25B4;</span>
        </li>
    </ul> For each of the following attributes, the channel identification A,B,C,D may be
    used. <ul>
        <li><a name="owad_cname"><code>attr &lt;name&gt; &lt;channel&gt;Name
                    &lt;string&gt;|&lt;string&gt;</code></a>
            <br />name for the channel | a type description for the measured value. </li>
        <li><a name="owad_cunit"><code>attr &lt;name&gt; &lt;channel&gt;Unit
                    &lt;string&gt;|&lt;string&gt;</code></a>
            <br />unit of measurement for this channel | its abbreviation. </li>
        <li><a name="owad_coffset"><code>attr &lt;name&gt; &lt;channel&gt;Offset
                    &lt;float&gt;</code></a>
            <br />offset added to the reading in this channel. </li>
        <li><a name="owad_cfactor"><code>attr &lt;name&gt; &lt;channel&gt;Factor
                    &lt;float&gt;</code></a>
            <br />factor multiplied to (reading+offset) in this channel. </li>
        <li><a name="owad_calarm"><code>attr &lt;name&gt; &lt;channel&gt;Alarm
                    &lt;string&gt;</code></a>
            <br />alarm setting in this channel, either both, low, high or none (default). </li>
        <li><a name="owad_clow"><code>attr &lt;name&gt; &lt;channel&gt;Low
                    &lt;float&gt;</code></a>
            <br />measurement value (on the scale determined by offset and factor) for low
            alarm. </li>
        <li><a name="owad_chigh"><code>attr &lt;name&gt; &lt;channel&gt;High
                    &lt;float&gt;</code></a>
            <br />measurement value (on the scale determined by offset and factor) for high
            alarm. </li>
        <li><a name="owad_event"><code>attr &lt;name&gt; event on-change|on-update
            </code></a>This attribte work similarly, but not identically to the standard event-on-update-change/event-on-update-reading attribute.
            <ul><li><code>event on-update</code> (default) will write a notify/FileLog event any time a measurement is received.</li>
                <li><code>event on-change</code> will write a notify/FileLog event only when a measurement is different from the previous one.</li>
                </ul>
        </li>
        <li>Standard attributes alias, comment, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>, <a href="#webCmd">webCmd</a></li>
    </ul>
</ul>

=end html
=cut
