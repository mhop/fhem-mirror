########################################################################################
#
# OWAD.pm
#
# FHEM module to commmunicate with 1-Wire A/D converters
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
# Version 1.04 - March, 2012
#   
# Setup bus device in fhem.cfg as
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
# Additional attributes are defined in fhem.cfg per channel, where <channel>=A,B,C,D
#
# attr <name> <channel>Name <string>  = a name for the channel
# attr <name> <channel>Offset <float> = an offset added to the reading in this channel 
# attr <name> <channel>Factor <float> = a factor multiplied to (reading+offset) in this channel 
# attr <name> <channel>Unit <string>  = a unit of measurement for this channel 
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

##-- value globals
my @owg_status;
#-- channel name - fixed is the first array, variable the second 
my @owg_fixed   = ("A","B","C","D");
my @owg_channel = ("A","B","C","D");
#-- channel values
my @owg_val;
#-- channel mode 
my @owg_mode = ("input","input","input","input");
#-- resolution in bit - fixed for now
my @owg_resoln = (16,16,16,16);
#-- bare range in mV - fixed for now
my @owg_range = (5100,5100,5100,5100);
#-- alarm status 0 = disabled, 1 = enabled, but not alarmed, 2 = alarmed
my @owg_alarmlow  = (0,0,0,0);
my @owg_alarmhigh = (0,0,0,0);
#-- alarm values
my @owg_low       = (0.0,0.0,0.0,0.0);
my @owg_high      = (5.0,5.0,5.0,5.0);

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
  #name        = channel name
  #offset      = a v(oltage) offset added to the reading
  #factor      = a v(oltage) factor multiplied with (reading+offset)  
  #unit        = a unit of measure
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2450 loglevel:0,1,2,3,4,5 ".
                "channels ";
  for( my $i=0;$i<4;$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Offset";
    $attlist .= " ".$owg_fixed[$i]."Factor";
    $attlist .= " ".$owg_fixed[$i]."Unit";
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
  
  my ($name,$model,$id,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWAD: Wrong syntax, must be define <name> OWAD [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = lc($a[2]);
  my $a3 = defined($a[3]) ? lc($a[3]) : "";
  if( $a2 =~ m/^[0-9|a-f]{12}$/ ) {
    $model         = "DS2450";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  } elsif(  $a3 =~ m/^[0-9|a-f]{12}$/ ) {
    $model         = $a[2];
    return "OWAD: Wrong 1-Wire device model $model"
      if( $model ne "DS2450");
    $id            = $a[3];
  } else {    
    return "OWAD: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   YY must be determined from id
  my $crc = sprintf("%02x",OWX_CRC("20.".$id."00"));
  
  #-- Define device internals
  $hash->{INTERVAL}   = $interval;
  $hash->{ROM_ID}     = "20.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = 20;
  $hash->{PRESENT}    = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWAD: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));

  $modules{OWAD}{defptr}{$id} = $hash;
  
  $hash->{STATE} = "Defined";
  Log 3, "OWAD:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  #-- OWX interface
  if( $interface eq "OWX" ){
    OWXAD_SetPage($hash,"alarm");
    OWXAD_SetPage($hash,"status");
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  }else{
    return "OWAD: Define with wrong IODev type $interface";
  }
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+1, "OWAD_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 0);
  
  #-- InternalTimer blocks if init_done is not true
  #my $oid = $init_done;
  $hash->{STATE} = "Initialized";
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
  
  my $name    = $hash->{NAME};
  #-- name attribute present ?
  for( my $i=0;$i<4;$i++) { 
    if( defined($attr{$name}{$owg_fixed[$i]."Name"}) ){
        $owg_channel[$i]= $attr{$name}{$owg_fixed[$i]."Name"};
    }
  }
  
  my $value2 = "";
  for (my $i=0;$i<4;$i++){
    #-- Initial readings values
    $hash->{READINGS}{$owg_channel[$i]}{VAL}         = 0.0;
    $hash->{READINGS}{$owg_channel[$i]}{TIME}        = "";
    #$hash->{READINGS}{$owg_channel[$i]}{UNIT}        = "volt";
    #$hash->{READINGS}{$owg_channel[$i]}{TYPE}        = "voltage";
    $hash->{READINGS}{$owg_channel[$i]."Low"}{VAL}   = 0.0;
    $hash->{READINGS}{$owg_channel[$i]."Low"}{TIME}  = "";
    $hash->{READINGS}{$owg_channel[$i]."High"}{VAL}  = 0.0;
    $hash->{READINGS}{$owg_channel[$i]."High"}{TIME} = "";
    
    $value2 .= sprintf "%s: L- H-   ",$owg_channel[$i]; 
  }
  $hash->{READINGS}{alarms}{VAL}    = $value2;
  $hash->{READINGS}{alarms}{TIME}   = "";
  
 
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
  my $value   = undef;
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
     return "$a[0] $reading => $value";
  } 
  
  #-- get present
  if($a[1] eq "present") {
    #-- hash of the busmaster
    my $master       = $hash->{IODev};
    $value           = OWX_Verify($master,$hash->{ROM_ID});
    $hash->{PRESENT} = $value;
    return "$a[0] $reading => $value";
  } 

  #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$a[0] $reading => $value";
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
    my $tn = TimeNow();
    $value = "";
    
    for (my $i=0;$i<4;$i++){
      #-- correct values for proper offset, factor 
      $offset = $attr{$name}{$owg_fixed[$i]."Offset"};
      $factor = $attr{$name}{$owg_fixed[$i]."Factor"};
      $owg_val[$i] += $offset if ($offset );
      $owg_val[$i] *= $factor if ($factor );
     
      #-- put into READINGS
      $hash->{READINGS}{$owg_channel[$i]}{VAL}           = $owg_val[$i];
      $hash->{READINGS}{$owg_channel[$i]}{TIME}          = $tn;
      $value .= sprintf "%s: %5.3f ",$owg_channel[$i],$owg_val[$i];
      }
    return "OWAD: $name.$reading => $value";
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
    my $tn = TimeNow();
    $value = "";
    
    for (my $i=0;$i<4;$i++){
      #-- correct alarm values for proper offset, factor 
      $offset = $attr{$name}{$owg_fixed[$i]."Offset"};
      $factor = $attr{$name}{$owg_fixed[$i]."Factor"};
      $owg_low[$i] += $offset if ($offset );
      $owg_low[$i] *= $factor if ($factor );
      $owg_high[$i] += $offset if ($offset );
      $owg_high[$i] *= $factor if ($factor );
  
      #-- put into READINGS
      $hash->{READINGS}{$owg_channel[$i]."Low"}{VAL}     = $owg_low[$i];
      $hash->{READINGS}{$owg_channel[$i]."Low"}{TIME}    = $tn;
      $hash->{READINGS}{$owg_channel[$i]."High"}{VAL}    = $owg_high[$i];
      $hash->{READINGS}{$owg_channel[$i]."High"}{TIME}   = $tn;
      
      $value .= sprintf "%s:[%4.2f,%4.2f] ",$owg_channel[$i],$owg_low[$i],$owg_high[$i];
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
    my $tn = TimeNow();
    $value = "";
    
    my $value2 = "";
    for (my $i=0;$i<4;$i++){
      $value  .= sprintf "%s: %s \n",$owg_channel[$i],$owg_status[$i];
      $value2 .= sprintf "%s: L",$owg_channel[$i];
      if( $owg_alarmlow[$i] == 0 ) {
        $value2 .= "- ";
      }elsif( $owg_alarmlow[$i] == 1 ) {
        $value2 .=  "+ ";
      }else{
        $value2 .=  "* ";
      }
      $value2 .= sprintf " H";
      if( $owg_alarmhigh[$i] == 0 ) {
        $value2 .= "-   ";
      }elsif( $owg_alarmhigh[$i] == 1 ) {
        $value2 .=  "+   ";
      }else{
        $value2 .=  "*   ";
      }
    }
    $hash->{READINGS}{alarms}{VAL}    = $value2;
    $hash->{READINGS}{alarms}{TIME}   = $tn;
    return "OWAD: $name.$reading => \n$value";
  }
}

#######################################################################################
#
# OWAD_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_GetValues($@) {
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
  my $tn = TimeNow();
  $value = "";
  my $value2 ="";
  
  for (my $i=0;$i<4;$i++){
    #-- correct values for proper offset, factor 
    $offset = $attr{$name}{$owg_fixed[$i]."Offset"};
    $factor = $attr{$name}{$owg_fixed[$i]."Factor"};
    $owg_val[$i] += $offset if ($offset );
    $owg_val[$i] *= $factor if ($factor );
    #-- correct alarm values for proper offset, factor 
    $owg_low[$i] += $offset if ($offset );
    $owg_low[$i] *= $factor if ($factor );
    $owg_high[$i] += $offset if ($offset );
    $owg_high[$i] *= $factor if ($factor );
  
    #-- put into READINGS
    $hash->{READINGS}{$owg_channel[$i]}{VAL}           = $owg_val[$i];
    $hash->{READINGS}{$owg_channel[$i]}{TIME}          = $tn;
    $hash->{READINGS}{$owg_channel[$i]."Low"}{VAL}     = $owg_low[$i];
    $hash->{READINGS}{$owg_channel[$i]."Low"}{TIME}    = $tn;
    $hash->{READINGS}{$owg_channel[$i]."High"}{VAL}    = $owg_high[$i];
    $hash->{READINGS}{$owg_channel[$i]."High"}{TIME}   = $tn;
    $value .= sprintf "%s: %5.3f ",$owg_channel[$i],$owg_val[$i];

    $value2 .= sprintf "%s: L",$owg_channel[$i];
    if( $owg_alarmlow[$i] == 0 ) {
      $value2 .= "- ";
    }elsif( $owg_alarmlow[$i] == 1 ) {
      $value2 .=  "+ ";
    }else{
      $value2 .=  "* ";
    }
    $value2 .= sprintf " H";
    if( $owg_alarmhigh[$i] == 0 ) {
      $value2 .= "-   ";
    }elsif( $owg_alarmhigh[$i] == 1 ) {
      $value2 .=  "+   ";
    }else{
      $value2 .=  "*   ";
    }
  }
  $hash->{READINGS}{alarms}{VAL}    = $value2;
  $hash->{READINGS}{alarms}{TIME}   = $tn;
  
  #--logging
  Log 5, $value;
  $hash->{CHANGED}[0] = $value;
  DoTrigger($name, undef);
  
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
    for( my $i=0;$i<4;$i++ ){
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
    return "OWAD: Set with short interval, must be > 10"
      if(int($value) < 10);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 1);
    return undef;
  }
  
  #-- find out which channel we have
  my $tc =$key;
  if( $tc =~ s/(.*)(Alarm|Low|High)/$channel=$1/se ) {
    for (my $i=0;$i<4;$i++){
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
       $owg_alarmlow[$channo]=1;
    } else{
       $owg_alarmlow[$channo]=0;
    }
    if( $value eq "high" || $value eq "both" ){
       $owg_alarmhigh[$channo]=1;
    } else{
       $owg_alarmhigh[$channo]=0;
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
    #-- round to those numbers understood by the device and backward into the value;
    my $value2  = int($value*255000/$owg_range[$channo])*$owg_range[$channo]/255000;
    $value  = $value2;
    $value += $offset if ( $offset );
    $value *= $factor if ( $factor ); 
 
    #-- set alarm value in the device
    if( $key =~ m/(.*)Low/ ){
      $owg_low[$channo]  = $value2;
    } elsif( $key =~ m/(.*)High/ ){
      $owg_high[$channo]  = $value2;
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
    
  #-- process results
  my $tn = TimeNow();
  #-- set alarm value in the readings
  if( $key =~ m/(.*)Low/ ){
    $hash->{READINGS}{$owg_channel[$channo]."Low"}{VAL}     = $value;
    $hash->{READINGS}{$owg_channel[$channo]."Low"}{TIME}    = $tn;
    #-- Test for alarm condition, her ewith the raw values (uncorrected)
    if ( $owg_low[$channo] > $owg_val[$channo] ){
         $owg_alarmlow[$channo] = 2 
            if($owg_alarmlow[$channo] == 1);
    } elsif ($owg_alarmlow[$channo] == 2) {
      $condx = 1; 
      $owg_alarmlow[$channo] = 1;
    }
  } elsif( $key =~ m/(.*)High/ ){
    $hash->{READINGS}{$owg_channel[$channo]."High"}{VAL}     = $value;
    $hash->{READINGS}{$owg_channel[$channo]."High"}{TIME}    = $tn;
    #-- Test for new alarm condition
    $condx  = 0;
    if( $channo && defined($owg_val[$channo]) ){
        if( $owg_high[$channo] < $owg_val[$channo] ){
            $owg_alarmhigh[$channo] = 2
                if($owg_alarmhigh[$channo] == 1);
        } elsif($owg_alarmhigh[$channo] == 2) {
          $condx = 1; 
          $owg_alarmhigh[$channo] = 1;
        }
      }
  }
  #-- set up a new alarm string for the status display
  my $value2 = "";
  for (my $i=0;$i<4;$i++){
    $value2 .= sprintf "%s: L",$owg_channel[$i];
    if( $owg_alarmlow[$i] == 0 ) {
      $value2 .= "- ";
    }elsif( $owg_alarmlow[$i] == 1 ) {
      $value2 .=  "+ ";
    }else{
      $value2 .=  "* ";
    }
    $value2 .= sprintf " H";
    if( $owg_alarmhigh[$i] == 0 ) {
      $value2 .= "-   ";
    }elsif( $owg_alarmhigh[$i] == 1 ) {
      $value2 .=  "+   ";
    }else{
      $value2 .=  "*   ";
    }
  }
  $hash->{READINGS}{alarms}{VAL}    = $value2;
  $hash->{READINGS}{alarms}{TIME}   = $tn;  
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
  
  #-- For now, switch on conversion command
  my $con=1;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);

  #-- 8 byte 1-Wire device address
  my @owx_ROM_ID  =(0,0,0,0 ,0,0,0,0); 
  #-- from search string to byte id
  my $devs=$owx_dev;
  $devs=~s/\.//g;
  for($i=0;$i<8;$i++){
     $owx_ROM_ID[$i]=hex(substr($devs,2*$i,2));
  }

  #=============== get the voltage reading ===============================
  if( $page eq "reading"){
    #-- if the conversion has not been called before 
    if( $con==1 ){
      OWX_Reset($master);
      #-- issue the match ROM command \x55 and the start conversion command
      $select = sprintf("\x55%c%c%c%c%c%c%c%c\x3C\x0F\x00\xFF\xFF",@owx_ROM_ID);  
      $res= OWX_Block($master,$select);
      if( $res eq 0 ){
        return "OWXAD: Device $owx_dev not accessible for conversion";
      } 
      #-- conversion needs some 5 ms per channel
      select(undef,undef,undef,0.02);
    }
    #-- issue the match ROM command \x55 and the read conversion page command
    #   \xAA\x00\x00 reading 8 data bytes and 2 CRC bytes
    $select=sprintf("\x55%c%c%c%c%c%c%c%c\xAA\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
      @owx_ROM_ID);   
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the read alarm page command 
    #   \xAA\x10\x00 reading 8 data bytes and 2 CRC bytes
    $select=sprintf("\x55%c%c%c%c%c%c%c%c\xAA\x10\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
      @owx_ROM_ID); 
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
    #-- issue the match ROM command \x55 and the read status memory page command 
    #   \xAA\x08\x00 reading 8 data bytes and 2 CRC bytes
  $select=sprintf("\x55%c%c%c%c%c%c%c%c\xAA\x08\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
     @owx_ROM_ID);  
  #=============== wrong value requested ===============================
  } else {
    return "OWXAD: Wrong memory page requested";
  } 
  
  #-- reset the bus
  OWX_Reset($master);
  #-- read the data
  $res=OWX_Block($master,$select);
  if( $res eq 0 ){
    return "OWXAD: Device $owx_dev not accessible in reading $page page"; 
  }
  
  #-- process results
  @data=split(//,$res);
  if ( (@data != 22) ){
   return "OWXAD: Device $owx_dev returns invalid data";
  }
  
  #=============== get the voltage reading ===============================
  if( $page eq "reading"){
    for( $i=0;$i<4;$i++){
      $owg_val[$i]= int((ord($data[12+2*$i])+256*ord($data[13+2*$i]))/((1<<$owg_resoln[$i])-1) * $owg_range[$i])/1000;
    }
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    for( $i=0;$i<4;$i++){
      $owg_low[$i]  = int(ord($data[12+2*$i])/255 * $owg_range[$i])/1000;
      $owg_high[$i] = int(ord($data[13+2*$i])/255 * $owg_range[$i])/1000;
    }
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
   my ($sb1,$sb2);
   for( $i=0;$i<4;$i++){
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
          $owg_alarmlow[$i] = 0;
        }else {
          #-- low alarm enabled and not set
          if ( ($sb2 & 16)==0  ){
            $owg_alarmlow[$i] = 1;
          #-- low alarm enabled and set
          }else{
            $owg_alarmlow[$i] = 2;
          }
        }  
        #-- high alarm disabled
        if( ($sb2 & 8)==0 ){  
          $owg_alarmhigh[$i] = 0;
        }else {
          #-- high alarm enabled and not set
          if ( ($sb2 & 32)==0  ){
            $owg_alarmhigh[$i] = 1;
          #-- high alarm enabled and set
          }else{
            $owg_alarmhigh[$i] = 2;
          }
        }  
        
        #-- assemble status string
        $owg_status[$i] = $owg_mode[$i].", ";
        $owg_status[$i] .= "disabled ," 
          if ( !($sb2 && 128) );
        $owg_status[$i] .=  sprintf "raw range %3.1f V, ",$owg_range[$i]/1000;
        $owg_status[$i] .=  sprintf "resolution %d bit, ",$owg_resoln[$i];
        $owg_status[$i] .=  sprintf "low alarm disabled, "
          if( $owg_alarmlow[$i]==0 );
        $owg_status[$i] .=  sprintf "low alarm enabled, "
          if( $owg_alarmlow[$i]==1 );
        $owg_status[$i] .=  sprintf "alarmed low, "
          if( $owg_alarmlow[$i]==2 );
        $owg_status[$i] .=  sprintf "high alarm disabled"
          if( $owg_alarmhigh[$i]==0 );
        $owg_status[$i] .=  sprintf "high alarm enabled"
          if( $owg_alarmhigh[$i]==1 );
        $owg_status[$i] .=  sprintf "alarmed high"
          if( $owg_alarmhigh[$i]==2 );
          
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
# OWXAD_SetPage - Setup one memory page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWXAD_SetPage($$) {

  my ($hash,$page) = @_;
  
  #-- For now, switch on conversion command
  my $con=1;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);

  #-- 8 byte 1-Wire device address
  my @owx_ROM_ID  =(0,0,0,0 ,0,0,0,0); 
  #-- from search string to byte id
  my $devs=$owx_dev;
  $devs=~s/\.//g;
  for($i=0;$i<8;$i++){
     $owx_ROM_ID[$i]=hex(substr($devs,2*$i,2));
  }
  
  #=============== set the alarm values ===============================
  if ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the set alarm page command 
    #   \x55\x10\x00 reading 8 data bytes and 2 CRC bytes
    $select=sprintf("\x55%c%c%c%c%c%c%c%c\x55\x10\x00",
      @owx_ROM_ID); 
    for( $i=0;$i<4;$i++){
      $select .= sprintf "%c\xFF\xFF\xFF",int($owg_low[$i]*255000/$owg_range[$i]);
      $select .= sprintf "%c\xFF\xFF\xFF",int($owg_high[$i]*255000/$owg_range[$i]);
      #print "Setting alarm values to ".int($owg_low[$i]*255000/$owg_range[$i])." ".int($owg_high[$i]*255000/$owg_range[$i])."\n";
    }
  #=============== set the status ===============================
  } elsif ( $page eq "status" ) {
    my ($sb1,$sb2);
    #-- issue the match ROM command \x55 and the set status memory page command 
    #   \x55\x08\x00 reading 8 data bytes and 2 CRC bytes
    $select=sprintf("\x55%c%c%c%c%c%c%c%c\x55\x08\x00",
       @owx_ROM_ID);  
    for( $i=0;$i<4;$i++){
      if( $owg_mode[$i] eq "input" ){
        #-- resolution (TODO: check !)
        $sb1 = $owg_resoln[$i]-1;
        #-- alarm enabled
        $sb2 =  ( $owg_alarmlow[$i] > 0  ) ? 4 : 0;
        $sb2 += ( $owg_alarmhigh[$i] > 0 ) ? 8 : 0;
        #-- range 
        $sb2 |= 1 
          if( $owg_range[$i] > 2550 );
      } else {
        $sb1 = 128;
        $sb2 = 0;
      }
      $select .= sprintf "%c\xFF\xFF\xFF",$sb1;
      $select .= sprintf "%c\xFF\xFF\xFF",$sb2;
      #print "setting status bytes $sb1 $sb2\n";
    }
  #=============== wrong value requested ===============================
  } else {
    return "OWXAD: Wrong memory page write attempt";
  } 
  
  OWX_Reset($master);
  $res=OWX_Block($master,$select);
  
  #-- process results
  if( $res eq 0 ){
    return "OWXAD: Device $owx_dev not accessible for initialization"; 
  }
  
  return undef;
}

1;
