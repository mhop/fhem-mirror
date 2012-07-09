########################################################################################
#
# OWSWITCH.pm
#
# FHEM module to commmunicate with 1-Wire adressable switches DS2413
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
# TODO: Kanalattribute ändern zur Laufzeit.
#
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
# OWX  = 1-Wire bus master interface (Peter Henning)
# OWFS = 1-Wire file system (??)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.11 - July, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWSWITCH [<model>] <ROM_ID> [interval] 
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2413  
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id       => FAM_ID.ROM_ID.CRC 
# get <name> present  => 1 if device present, 0 if not
# get <name> interval => query interval
# get <name> input <channel-name> => state for channel (name A, B or defined channel name)
# get <name> gpio  => values for channels
#
# set <name> interval => set period for measurement
# set <name> output <channel-name>  ON|OFF => set value for channel (name A, B or defined channel name)
# set <name> gpio  value => set values for channels (3 = both OFF, 1 = B ON 2 = A ON 0 = both ON)
#
# Additional attributes are defined in fhem.cfg, in some cases per channel, where <channel>=A,B
# Note: attributes are read only during initialization procedure - later changes are not used.
#
# attr <name> <channel>Name <string>|<string> = name for the channel | a type description for the measured value
# attr <name> <channel>Unit <string>|<string> = values to display in state variable for on|off condition
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

#-- channel name - fixed is the first array, variable the second 
my @owg_fixed = ("A","B");
my @owg_channel;
#-- channel values - always the raw values from the device
my @owg_val;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "input"       => "",
  "gpio"        => ""
);

my %sets = (
  "interval"    => "",
  "output"      => "",
  "gpio"        => ""
);

my %updates = (
  "present"     => "",
  "gpio"     => ""
);


########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWSWITCH
#
########################################################################################
#
# OWSWITCH_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWSWITCH_Define";
  $hash->{UndefFn} = "OWSWITCH_Undef";
  $hash->{GetFn}   = "OWSWITCH_Get";
  $hash->{SetFn}   = "OWSWITCH_Set";
  #Name        = channel name
  #Offset      = an offset added to the reading
  #Factor      = a factor multiplied with (reading+offset)  
  #Unit        = a unit of measure
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2413 loglevel:0,1,2,3,4,5 ";
 
  for( my $i=0;$i<int(@owg_fixed);$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Unit";
  }
  $hash->{AttrList} = $attlist; 
}

#########################################################################################
#
# OWSWITCH_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWSWITCH_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWSWITCH [<model>] <id> [interval]
  # e.g.: define flow OWSWITCH 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWSWITCH: Wrong syntax, must be define <name> OWSWITCH [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2413";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    return "OWSWITCH: Wrong 1-Wire device model $model"
      if( $model ne "DS2413");
    $id            = $a[3];
  } else {    
    return "OWSWITCH: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC("3A.".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = "3A.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = "3A";
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWSWITCH: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWSWITCH}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWSWITCH:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+1, "OWSWITCH_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);

  return undef; 
}

########################################################################################
#
# OWSWITCH_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
    
  #-- Initial readings 
  @owg_val   = (0.0,0.0,0.0,0.0);
   
  #-- Set channel names, channel units 
  for( my $i=0;$i<int(@owg_fixed);$i++) { 
    #-- name
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|onoff";
    my @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      Log 1, "OWSWITCH: Incomplete channel name specification $cname. Better use $cname|<type of data>";
      push(@cnama,"unknown");
    }
 
    #-- unit
    my $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "ON|OFF";
    my @unarr= split(/\|/,$unit);
    if( int(@unarr)!=2 ){
      Log 1, "OWSWITCH: Wrong channel unit specification $unit, replaced by ON|OFF";
      $unit="ON|OFF";
    }

    #-- put into readings
    $owg_channel[$i] = $cnama[0];  
    $hash->{READINGS}{"$owg_channel[$i]"}{TYPE}     = $cnama[1];  
    $hash->{READINGS}{"$owg_channel[$i]"}{UNIT}     = $unit;
    $hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR} = $unit;
  }
  
  #-- set status according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- OWX interface
  if( !defined($interface) ){
    return "OWSWITCH: Interface missing";
  } elsif( $interface eq "OWX" ){
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  }else{
    return "OWSWITCH: InitializeDevice with wrong IODev type $interface";
  }

  #-- Initialize all the display stuff  
  OWSWITCH_FormatValues($hash);
}

########################################################################################
#
# OWSWITCH_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWSWITCH_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$vval);
  my ($value1,$value2,$value3)   = ("","","");

  my $tn = TimeNow();
  
  #-- formats for output
  for (my $i=0;$i<int(@owg_fixed);$i++){
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i];  
    my @cnama = split(/\|/,$cname);
    $owg_channel[$i]=$cnama[0];
    
    #-- result is zero or one
    $vval    = $owg_val[$i];
  
    #-- string buildup for return value and STATE
    my @unarr=split(/\|/,$hash->{READINGS}{"$owg_channel[$i]"}{UNIT});
    $value1 .= sprintf( "%s: %s", $owg_channel[$i], $unarr[$vval]);
    $value2 .= sprintf( "%s: %s ", $owg_channel[$i], $unarr[$vval]);
    $value3 .= sprintf( "%s: " , $owg_channel[$i]);
    
    #-- put into READINGS
    $hash->{READINGS}{"$owg_channel[$i]"}{VAL}   = $unarr[$vval];
    $hash->{READINGS}{"$owg_channel[$i]"}{TIME}  = $tn;
    
    #-- insert comma
    if( $i<int(@owg_fixed)-1 ){
      $value1 .= " ";
      $value2 .= ", ";
      $value3 .= ", ";
    }
  }
  #-- STATE
  $hash->{STATE} = $value2;
 
  return $value1;
}

########################################################################################
#
# OWSWITCH_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWSWITCH_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my ($value,$value2,$value3)   = (undef,undef,undef);
  my $ret     = "";
  my $offset;
  my $factor;
  my $page;

  #-- check syntax
  return "OWSWITCH: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  return "OWSWITCH: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
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
  
  #-- get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};

  #-- get single state
  # TODO: WAS passiert, wenn channel name noch falsch ist ?
  if( $reading eq "input" ){
    return "OWSWITCH: get needs parameter when reading input: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
    }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
    } else {
      return "OWSWITCH: invalid input address, must be A, B or defined channel name"
    }

    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process results
    OWSWITCH_FormatValues($hash);  
    my @states = split(/,/,$hash->{STATE});
    
    if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
      return $a[2]." = ".$states[0]; 
    }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
      return $a[2]." = ".$states[1]; 
    } else {
      return "OWSWITCH: invalid input address, must be A, B or defined channel name"
    }
    
  #-- get all states
  }elsif( $reading eq "gpio" ){
    return "OWSWITCH: get needs no parameter when reading gpio"
      if( int(@a)==1 );

    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetValues($hash);
    }else{
      return "OWSWITCH: GetValues with wrong IODev type $interface";
    }
  }
  #-- process results
  if( defined($ret)  ){
    return "OWSWITCH: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  return "OWSWITCH: $name.$reading => ".OWSWITCH_FormatValues($hash);  
 
}

#######################################################################################
#
# OWSWITCH_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = "";
  my $ret     = "";
  my $offset;
  my $factor;

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- Get readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXSWITCH_GetState($hash);
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetValues($hash);
  }else{
    return "OWSWITCH: GetValues with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWSWITCH: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  $value=OWSWITCH_FormatValues($hash);
  #--logging
  Log 5, $value;
  $hash->{CHANGED}[0] = $value;
  
  DoTrigger($name, undef);
  
  return undef;
}

#######################################################################################
#
# OWSWITCH_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWSWITCH_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", sort keys %sets);
    return $newkeys ;    
  }
  
  #-- check argument
  if( !defined($sets{$a[1]}) ){
        return "OWSWITCH: Set with unknown argument $a[1]";
  }
  
  #-- define vars
  my $ret     = undef;
  my $channel = undef;
  my $channo  = undef;
  my $condx;
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
 
  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWSWITCH: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
    return undef;
  }
 
   
  #-- Set readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- set single state
  # TODO: WAS passiert, wenn channel name noch falsch ist ?
  if( $key eq "output" ){
    return "OWSWITCH: get needs parameter when writing output: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
    }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
    } else {
      return "OWSWITCH: invalid output address, must be A, B or defined channel name"
    }
    
    #-- prepare gpio value
    my $nval;
    if( lc($a[3]) eq "on" ){
      $nval = 0;
    }elsif( lc($a[3]) eq "off" ){
      $nval = 1;
    }else{
      return "OWSWITCH: Wrong data value $a[3]";
    }

    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
      if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
         $value = $owg_val[1]*2+$nval;
      }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
         $value = 2*$nval+$owg_val[0];
      }
      $ret = OWXSWITCH_SetState($hash,$value);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
 
  #-- set state
  }elsif( $key eq "gpio" ){
    #-- check value and write to device
    return "OWSWITCH: Set with wrong value for gpio port, must be 0 <= gpio <= 3"
      if( ! ((int($value) >= 0) && (int($value) <= 3)) );
     
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_SetState($hash,int($value));
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetValues($hash);
    }else{
      return "OWSWITCH: GetValues with wrong IODev type $interface";
    }
  }
  
  #-- process results - we have to reread the device
  $hash->{PRESENT} = 1; 
  OWSWITCH_GetValues($hash);  
  OWSWITCH_FormatValues($hash);  
  Log 4, "OWSWITCH: Set $hash->{NAME} $key $value";
  $hash->{CHANGED}[0] = $value;
  return undef;
}

########################################################################################
#
# OWSWITCH_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Undef ($) {
  my ($hash) = @_;
  delete($modules{OWSWITCH}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSSWITCH
#
########################################################################################



########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXSWITCH
#
########################################################################################
#
# OWXAD_GetState - Get gpio ports from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXSWITCH_GetState($) {
  my ($hash) = @_;
  
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

  #=============== get gpio values ===============================
  #-- issue the match ROM command \x55 and the read gpio command
  #   \xF5 plus 2 empty bytes
  #-- reset the bus
  OWX_Reset($master);
  #-- read the data
  $res=OWX_Complex($master,$owx_dev,"\xF5",2);
  if( $res eq 0 ){
    return "OWX: Device $owx_dev not accessible in reading"; 
  }

  #-- process results
  # TODO: could we put in a check if the two bytes are equal
  @data=split(//,substr($res,10));
  
  #-- reset the bus
  OWX_Reset($master);
  
  #my $ress = "OWXSWITCH_Get: three data bytes ";
  #  for($i=0;$i<3;$i++){
  #  my $j=int(ord($data[$i])/16);
  #  my $k=ord($data[$i])%16;
  #  $ress.=sprintf "0x%1x%1x ",$j,$k;
  #  }
  #Log 1, $ress;
  
  #-- This holds only for DS2413 
  $owg_val[0] = ord($data[0]) % 2;
  $owg_val[1] = (ord($data[0])>>2) % 2;
  
  #Log 1, "Values are ".ord($data[0])." $owg_val[0] and $owg_val[1]";

  return undef
}

########################################################################################
#
# OWXSWITCH_SetPage - Set gpio ports of device
#
# Parameter hash = hash of device addressed
#           value = integer value for device outputs
#
########################################################################################

sub OWXSWITCH_SetState($$) {

  my ($hash,$value) = @_;
  
  
  my ($select, $res, $res2, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);
  
  #=============== set gpio values ===============================
  #-- issue the match ROM command \x55 and the write gpio command
  #   \x5A plus the value byte and its complement
  $select=sprintf("\x5A%c%c",252+$value,3-$value);   
  #-- reset the bus
  OWX_Reset($master);
  #-- read the data
  $res=OWX_Complex($master,$owx_dev,$select,1);
  if( $res eq 0 ){
    return "OWX: Device $owx_dev not accessible in reading"; 
  }

  #-- reset the bus
  OWX_Reset($master);

  #-- process results
  @data=split(//,substr($res,10));
  
  #my $ress = "OWXSWITCH_Set: three data bytes ";
  #  for($i=0;$i<3;$i++){
  #  my $j=int(ord($data[$i])/16);
  #  my $k=ord($data[$i])%16;
  #  $ress.=sprintf "0x%1x%1x ",$j,$k;
  #  }
  #Log 1, $ress;

  if( $data[2] ne "\xAA"){
    Log 1, "OWXSWITCH: State could not be set";
    return "OWXSWITCH: State could not be set";
  } 
 
  #-- Put the new values in the system variables
  #-- This holds only for DS2413 
  
  $owg_val[0] = $value % 2;
  $owg_val[1] = int($value / 2);
  return undef
}

1;
