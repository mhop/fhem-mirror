########################################################################################
#
# OWTHERM.pm
#
# FHEM module to commmunicate with 1-Wire temperature sensors DS1820, DS18S20, DS18B20, DS1822
#
# Prof. Dr. Peter A. Henning 
#
# $Id$
#
# Disclaimer: No code of the former OWTEMP module is contained here
#
########################################################################################
#
# define <name> OWTHERM [<model>] <ROM_ID> [interval] or <FAM_ID>.<ROM_ID> [interval]
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS1820 temperature sensor 
#              Currently allowed values are DS1820, DS18B20, DS1822
#       <FAM_ID> is a 1-Wire family id, currently allowed values are 10, 22, 28
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id          => FAM_ID.ROM_ID.CRC 
# get <name> present     => 1 if device present, 0 if not
# get <name> interval    => query interval
# get <name> temperature => temperature measurement
# get <name> alarm       => alarm temperature settings
# get <name> version     => OWX version number
#
# set <name> interval    => set period for measurement
# set <name> tempLow     => lower alarm temperature setting 
# set <name> tempHigh    => higher alarm temperature setting
#
# Additional attributes are defined in fhem.cfg
#
# attr <name> stateAL  "<string>"  = character string for denoting low alarm condition, default is down triangle
# attr <name> stateAH  "<string>"  = character string for denoting high alarm condition, default is up triangle
# attr <name> tempOffset <float>   = temperature offset in degree Celsius added to the raw temperature reading 
# attr <name> tempUnit  <string>   = unit of measurement, e.g. Celsius/Kelvin/Fahrenheit or C/K/F, default is Celsius
# attr <name> tempConv onkick|onread    =  determines, whether a temperature measurement will happen when "kicked" 
#               through the OWX backend module (all temperature sensors at the same time), or on 
#               reading the sensor (1 second waiting time). 
# attr <name> tempLow   <float>    = value for low alarm 
# attr <name> tempHigh  <float>    = value for high alarm 
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

use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

my $owx_version="3.23";
#-- temperature globals - always the raw values from/for the device
my $owg_temp     = "";
my $owg_th       = "";
my $owg_tl       = "";

#-- variables for display strings
my $stateal;
my $stateah;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "temperature" => "",
  "alarm"       => "",
  "version"     => ""
);

my %sets = (
  "interval"    => "",
  "tempHigh"    => "",
  "tempLow"     => ""
);

my %updates = (
  "present"     => "",
  "temperature" => "",
  "alarm"       => ""
);

########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWTHERM
#
########################################################################################
#
# OWTHERM_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWTHERM_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWTHERM_Define";
  $hash->{UndefFn} = "OWTHERM_Undef";
  $hash->{GetFn}   = "OWTHERM_Get";
  $hash->{SetFn}   = "OWTHERM_Set";
  $hash->{AttrFn}  = "OWTHERM_Attr";
  $hash->{AttrList}= "IODev model:DS1820,DS18B20,DS1822 loglevel:0,1,2,3,4,5 ".
                     "stateAL stateAH ".
                     "tempOffset tempUnit:C,Celsius,F,Fahrenheit,K,Kelvin ".
                     "tempConv:onkick,onread tempLow tempHigh ".
                     $readingFnAttributes;                
  }
  
########################################################################################
#
# OWTHERM_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWTHERM_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWTHERM [<model>] <id> [interval]
  # e.g.: define flow OWTHERM 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $ret           = "";

  #-- check syntax
  return "OWTHERM: Wrong syntax, must be define <name> OWTHERM [<model>] <id> [interval] or OWTHERM <fam>.<id> [interval]"
       if(int(@a) < 2 || int(@a) > 6);
       
  #-- different types of definition allowed
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  #-- no model, 12 characters
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS1820";
    $fam           = "10";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  #-- no model, 2+12 characters
   } elsif(  $a2 =~ m/^[0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
    $fam           = substr($a[2],0,2);
    $id            = substr($a[2],3);
    if(int(@a)>=4) { $interval = $a[3]; }
    if( $fam eq "10" ){
      $model = "DS1820";
      CommandAttr (undef,"$name model DS1820"); 
    }elsif( $fam eq "22" ){
      $model = "DS1822";
      CommandAttr (undef,"$name model DS1822"); 
    }elsif( $fam eq "28" ){
      $model = "DS18B20";
      CommandAttr (undef,"$name model DS18B20"); 
    }else{
      return "OWTHERM: Wrong 1-Wire device family $fam";
    }
  #-- model, 12 characters
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    if( $model eq "DS1820" ){
      $fam = "10";
      CommandAttr (undef,"$name model DS1820"); 
    }elsif( $model eq "DS1822" ){
      $fam = "22";
      CommandAttr (undef,"$name model DS1822"); 
    }elsif( $model eq "DS18B20" ){
      $fam = "28";
      CommandAttr (undef,"$name model DS1822"); 
    }else{
      return "OWTHERM: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWTHERM: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }
  
  #-- determine CRC Code
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- define device internals
  $hash->{ALARM}      = 0;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{INTERVAL}   = $interval;
  $hash->{ERRCOUNT}   = 0;
  
  #-- Couple to I/O device, exit if not possible
  AssignIoPort($hash);
  if( !defined($hash->{IODev}->{NAME}) || !defined($hash->{IODev}) ){
    return "OWTHERM: Warning, no 1-Wire I/O device found for $name.";
  }
  #if( $hash->{IODev}->{PRESENT} != 1 ){
  #  return "OWTHERM: Warning, 1-Wire I/O device ".$hash->{IODev}->{NAME}." not present for $name.";
  #}
  $modules{OWTHERM}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWTHERM: Device $name defined."; 
   
  #-- Start timer for updates
  InternalTimer(time()+10, "OWTHERM_GetValues", $hash, 0);

  return undef; 
}
 
#######################################################################################
#
# OWTHERM_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWTHERM_Attr(@) {
  my ($do,@a) = @_;
  
  my $name    = $a[0];
  my $key     = $a[1];
  my $ret;
  
  #-- only alarm settings may be modified at runtime for now
  return undef
    if( $key !~ m/(.*)(Low|High)/ );
  #-- safeguard against uninitialized devices
  return undef
    if( $main::defs{$name}->{READINGS}{"state"}{VAL} eq "defined" );
  
  if( $do eq "set")
  {
    $ret = OWTHERM_Set($main::defs{$name},@a);
  } elsif( $do eq "del"){
  }
  return $ret;
}

########################################################################################
#
# OWTHERM_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWTHERM_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my $interface = $hash->{IODev}->{TYPE};
  my ($unit,$offset,$factor,$abbr,$vval,$vlow,$vhigh,$statef);
  my $svalue = "";
  
  #-- attributes defined ?
  $stateal = defined($attr{$name}{stateAL}) ? $attr{$name}{stateAL} : "&#x25BE;";
  $stateah = defined($attr{$name}{stateAH}) ? $attr{$name}{stateAH} : "&#x25B4;";
  $unit    = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : "Celsius";
  $offset  = defined($attr{$name}{"tempOffset"}) ? $attr{$name}{"tempOffset"} : 0.0 ;
  $factor  = 1.0;
  
  if( $unit eq "Celsius" ){
    $abbr   = "&deg;C";
  } elsif ($unit eq "Kelvin" ){
    $abbr   = "K";
    $offset += "273.16"
  } elsif ($unit eq "Fahrenheit" ){
    $abbr   = "&deg;F";
    $offset = ($offset+32)/1.8;
    $factor = 1.8;
  } else {
    $abbr="?";
    Log 3, "OWTHERM_FormatValues: Unknown temperature unit $unit";
  }
  #-- these values are rather complex to obtain, therefore save them in the hash
  $hash->{READINGS}{"temperature"}{UNIT}     = $unit;
  $hash->{READINGS}{"temperature"}{UNITABBR} = $abbr;
  $hash->{tempf}{offset}                     = $offset;
  $hash->{tempf}{factor}                     = $factor;
  
  #-- no change in any value if invalid reading
  return if( $owg_temp eq "");
  
  #-- correct values for proper offset, factor 
  $vval  = ($owg_temp + $offset)*$factor;
  $vlow   = floor(($owg_tl + $offset)*$factor+0.5);
  $vhigh  = floor(($owg_th + $offset)*$factor+0.5);
  
  $main::attr{$name}{"tempLow"} = $vlow;
  $main::attr{$name}{"tempHigh"} = $vhigh;
         
  #-- formats for output
  $statef = "T: %5.2f ".$abbr;
  $svalue = sprintf($statef,$vval);
  
  #-- Test for alarm condition
  $hash->{ALARM} = 1;
  if( ($vval <= $vlow) && ( $vval >= $vhigh ) ){
    $svalue .= " ".$stateal.$stateah;
  }elsif( $vval <= $vlow ){
    $svalue .= " ".$stateal;
  }elsif( $vval >= $vhigh ){
    $svalue .= " ".$stateah;
  } else {
    $hash->{ALARM} = 0;
  }
  
  #-- put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"temperature",$vval);
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsEndUpdate($hash,1); 
  
  return $svalue;
}
  
########################################################################################
#
# OWTHERM_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWTHERM_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = undef;
  my $ret     = "";

  #-- check syntax
  return "OWTHERM: Get argument is missing @a"
    if(int(@a) != 2);
    
  #-- check argument
  return "OWTHERM: Get with unknown argument $a[1], choose one of ".join(" ", sort keys %gets)
    if(!defined($gets{$a[1]}));
  
  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$name.id => $value";
  } 
  
  #-- Get other values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- get present
  if($a[1] eq "present" ) {
    #-- OWX interface
    if( $interface eq "OWX" ){
      #-- hash of the busmaster
      my $master       = $hash->{IODev};
      $value           = OWX_Verify($master,$hash->{ROM_ID});
      $hash->{PRESENT} = $value;
      return "$name.present => $value";
    } else {
      return "OWTHERM: Verification not yet implemented for interface $interface";
    }
  } 
  
  #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$name.interval => $value";
  } 
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $owx_version";
  }
  
  #-- reset presence
  $hash->{PRESENT}  = 0;

  #-- OWX interface
  if( $interface eq "OWX" ){
    #-- not different from getting all values ..
    $ret = OWXTHERM_GetValues($hash);
  #-- OWFS interface
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSTHERM_GetValues($hash);
  #-- Unknown interface
  }else{
    return "OWTHERM: Get with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWTHERM: Could not get values from device $name, return was $ret";
  }
  $hash->{PRESENT} = 1; 
  OWTHERM_FormatValues($hash);
  
  #-- return the special reading
  if ($reading eq "temperature") {
    return "OWTHERM: $name.temperature => ".
      $hash->{READINGS}{"temperature"}{VAL};
  } elsif ($reading eq "alarm") {
    return "OWTHERM: $name.alarm => L ".$main::attr{$name}{"tempLow"}.
      " H ".$main::attr{$name}{"tempHigh"};
  }
  return undef;
}

#######################################################################################
#
# OWTHERM_GetValues - Updates the readings from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWTHERM_GetValues($@) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $value   = "";
  my $ret     = "";
  
  #-- check if device needs to be initialized
  OWTHERM_InitializeDevice($hash)
    if( $hash->{READINGS}{"state"}{VAL} eq "defined");
  
  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWTHERM_GetValues", $hash, 1);

  #-- reset presence
  $hash->{PRESENT}  = 0;

  #-- Get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    #-- max 3 tries
    for(my $try=0; $try<3; $try++){
      $ret = OWXTHERM_GetValues($hash);
      last
        if( !defined($ret) );
    } 
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSTHERM_GetValues($hash);
  }else{
    Log 3, "OWTHERM: GetValues with wrong IODev type $interface";
    return 1;
  }

  #-- process results
  if( defined($ret)  ){
    $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
    if( $hash->{ERRCOUNT} > 5 ){
      $hash->{INTERVAL} = 9999;
    }
    return "OWTHERM: Could not get values from device $name for ".$hash->{ERRCOUNT}." times, reason $ret";
  }
  $hash->{PRESENT} = 1; 

  $value=OWTHERM_FormatValues($hash);
  Log 5, $value;
  
  return undef;
}

########################################################################################
#
# OWTHERM_InitializeDevice - delayed setting of initial readings
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWTHERM_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
  my $interface = $hash->{IODev}->{TYPE};
  my @a = ($name,"",0);
  my ($unit,$offset,$factor,$abbr,$value,$ret);
  
  #-- attributes defined ?
  $stateal = defined($attr{$name}{stateAL}) ? $attr{$name}{stateAL} : "&#x25BE;";
  $stateah = defined($attr{$name}{stateAH}) ? $attr{$name}{stateAH} : "&#x25B4;";
  $unit    = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : "Celsius";
  $offset  = defined($attr{$name}{"tempOffset"}) ? $attr{$name}{"tempOffset"} : 0.0 ;
  $factor  = 1.0;
  
  if( $unit eq "Celsius" ){
    $abbr   = "&deg;C";
  } elsif ($unit eq "Kelvin" ){
    $abbr   = "K";
    $offset += "273.16"
  } elsif ($unit eq "Fahrenheit" ){
    $abbr   = "&deg;F";
    $offset = ($offset+32)/1.8;
    $factor = 1.8;
  } else {
    $abbr="?";
    Log 3, "OWTHERM_FormatValues: unknown unit $unit";
  }
  #-- these values are rather complex to obtain, therefore save them in the hash
  $hash->{READINGS}{"temperature"}{TYPE} = "temperature";
  $hash->{READINGS}{"temperature"}{UNIT}     = $unit;
  $hash->{READINGS}{"temperature"}{UNITABBR} = $abbr;
  $hash->{ERRCOUNT}                          = 0;
  $hash->{tempf}{offset}                     = $offset;
  $hash->{tempf}{factor}                     = $factor;
  
  #-- Check if temperature conversion is consistent
  if( $interface eq "OWX" ){
    if( defined($attr{$name}{tempConv}) && ( $attr{$name}{tempConv} eq "onkick") ){
      if( !(defined($attr{$hash->{IODev}->{NAME}}{dokick})) || 
           ( defined($attr{$hash->{IODev}->{NAME}}{dokick}) && ($attr{$hash->{IODev}->{NAME}}{dokick} eq "0") )){
        Log 1,"OWTHERM: Attribute tempConv=onkick changed to onread for $name because interface is not kicking";
        $attr{$name}{tempConv}="onread";
      }
    }
  }elsif( $interface eq "OWServer" ){
    if( !(defined($attr{$name}{tempConv})) ||
         (defined($attr{$name}{tempConv}) && ($attr{$name}{tempConv} eq "onread") ) ){
      Log 1,"OWTHERM: Attribute tempConv=onread changed to onkick for $name because interface is OWFS";
      $attr{$name}{tempConv}="onread";
    }
  }  
  
  #-- Set the attribute values if defined
  if(  defined($attr{$name}{"tempLow"}) ){
    $value = $attr{$name}{"tempLow"};
    $a[1] = "tempLow"; 
    $a[2] = floor($value/$factor-$offset+0.5);
    #-- put into device
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXTHERM_SetValues($hash,@a);
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSTHERM_SetValues($hash,@a);
    } 
    #-- process results
    if( defined($ret)  ){
      return "OWTHERM: Could not initialize device $name, reason: ".$ret;
    }
  }
  if( defined($attr{$name}{"tempHigh"}) ){
    $value = $attr{$name}{"tempHigh"};
    $a[1] = "tempHigh"; 
    $a[2] = floor($value/$factor-$offset+0.5);
    #-- put into device
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXTHERM_SetValues($hash,@a);
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSTHERM_SetValues($hash,@a);
    } 
    #-- process results
    if( defined($ret)  ){
      return "OWTHERM: Could not initialize device $name, reason: ".$ret;
    }
  }
  #-- Set state to initialized
  readingsSingleUpdate($hash,"state","initialized",1);
  
  return undef;
}

#######################################################################################
#
# OWTHERM_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################

sub OWTHERM_Set($@) {
  my ($hash, @a) = @_;

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a == 2);
  #-- check syntax
  return "OWTHERM: Set needs one parameter"
    if(int(@a) != 3);
  #-- check argument
  return "OWTHERM: Set with unknown argument $a[1], choose one of ".join(",", sort keys %sets)
      if(!defined($sets{$a[1]}));
      
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  my $ret   = undef;
  my $name  = $hash->{NAME};
  my $model = $hash->{OW_MODEL};

  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWTHERM: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTHERM_GetValues", $hash, 1);
    return undef;
  }

  #-- set tempLow or tempHigh
  if( (lc($key) eq "templow") || (lc($key) eq "temphigh")) {
  
    my $interface = $hash->{IODev}->{TYPE};
    my $offset    = defined($hash->{tempf}{offset}) ? $hash->{tempf}{offset} : 0.0;
    my $factor    = defined($hash->{tempf}{factor}) ? $hash->{tempf}{factor} : 1.0;
    
    #-- Only integer values are allowed 
    $value = floor($value+0.5);
    
    #-- First we have to read the current data, because alarms may not be set independently
    $owg_tl = floor($main::attr{$name}{"tempLow"}/$factor-$offset+0.5);
    $owg_th = floor($main::attr{$name}{"tempHigh"}/$factor-$offset+0.5);
    
    #-- find upper and lower boundaries for given offset/factor
    my $mmin = floor((-55+$offset)*$factor+0.5);
    my $mmax = floor((125+$offset)*$factor+0.5);
    return sprintf("OWTHERM: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
      if($value < $mmin || $value > $mmax);
    
    #-- seems to be ok, correcting for offset and factor
    $a[2]  = floor($value/$factor-$offset+0.5);
    #-- put into attribute value
    if( lc($key) eq "templow" ){
      if( $main::attr{$name}{"tempLow"} != $value ){
        $main::attr{$name}{"tempLow"} = $value;
      }
    }
    if( lc($key) eq "temphigh" ){
      if( $main::attr{$name}{"tempHigh"} != $value ){
        $main::attr{$name}{"tempHigh"} = $value;
      }
    }
    #-- put into device
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXTHERM_SetValues($hash,@a);
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSTHERM_SetValues($hash,@a);
    } else {
      return "OWTHERM: Set with wrong IODev type $interface";
    }
    #-- process results
    if( defined($ret)  ){
      return "OWTHERM: Could not set device $name, reason: ".$ret;
    }
  }
  
  #-- process results
  $hash->{PRESENT} = 1; 
  OWTHERM_FormatValues($hash); 
  Log 4, "OWTHERM: Set $hash->{NAME} $key $value";
  
  return undef;
}

########################################################################################
#
# OWTHERM_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWTHERM_Undef ($) {
  my ($hash) = @_;
  
  delete($modules{OWTHERM}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSTHERM
#
########################################################################################
#
# OWFSTHERM_GetValues - Get values from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSTHERM_GetValues($) {
  my ($hash) = @_;
 
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- get values - or should we rather get the uncached ones ?
  $owg_temp = OWServer_Read($master,"/$owx_add/temperature");
 
  my $ow_thn   = OWServer_Read($master,"/$owx_add/temphigh");
  my $ow_tln   = OWServer_Read($master,"/$owx_add/templow");
  
  return "no return from OWServer"
    if( (!defined($owg_temp)) || (!defined($ow_thn)) || (!defined($ow_tln)) );
  return "empty return from OWServer"
    if( ($owg_temp eq "") || ($ow_thn eq "") || ($ow_tln eq "") );
        
  #-- process alarm settings
  $owg_tl = $ow_tln;
  $owg_th = $ow_thn;
  
  return undef
}

########################################################################################
#
# OWFSTHERM_SetValues - Set values in device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSTHERM_SetValues($@) {
  my ($hash,@a) = @_;
  
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  return undef
    if( !defined($value));
  return undef 
    if( $value eq "");
    
  #-- $owg_tl and $owg_th are preset and may be changed here
  $owg_tl = $value if( lc($key) eq "templow" );
  $owg_th = $value if( lc($key) eq "temphigh");
  
  OWServer_Write($master, "/$owx_add/".lc($key),$value );
  
  return undef
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXTHERM
#
########################################################################################
#
# OWXTHERM_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXTHERM_GetValues($) {

  my ($hash) = @_;
  
  my ($i,$j,$k,@data,$ow_thn,$ow_tln);
  my $change = 0;
  
  #-- For default, perform the conversion now
  my $con=1;
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- check, if the conversion has been called before for all sensors
  if( defined($attr{$name}{tempConv}) && ( $attr{$name}{tempConv} eq "onkick") ){
    $con=0;
  }  

  #-- if the conversion has not been called before 
  if( $con==1 ){
    OWX_Reset($master);
    #-- issue the match ROM command \x55 and the start conversion command
    if( OWX_Complex($master,$owx_dev,"\x44",0) eq 0 ){
      return "$owx_dev not accessible";
    } 
    #-- conversion needs some 950 ms - but we may also do it in shorter time !
    select(undef,undef,undef,1.0);
  }

  #-- NOW ask the specific device 
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the read scratchpad command \xBE
  #-- reading 9 + 1 + 8 data bytes and 1 CRC byte = 19 bytes
  my $res=OWX_Complex($master,$owx_dev,"\xBE",9);
  #Log 1,"OWXTHERM: data length from reading device is ".length($res)." bytes";
  #-- process results
  if( $res eq 0 ){
    return "$owx_dev not accessible in 2nd step"; 
  }
  
  #-- process results
  @data=split(//,substr($res,9));
  return "invalid data length, ".int(@data)." instead of 10 bytes"
    if (@data != 10); 
  return "invalid data"
    if (ord($data[8])<=0); 
  return "invalid CRC"
    if (OWX_CRC8(substr($res,10,8),$data[9])==0);
  
  #-- this must be different for the different device types
  #   family = 10 => DS1820, DS18S20
  if( $hash->{OW_FAMILY} eq "10" ) {    
  
    my $count_remain = ord($data[7]);
    my $count_perc   = ord($data[8]);
    my $delta        = -0.25 + ($count_perc - $count_remain)/$count_perc;
   
    my $lsb  = ord($data[1]);
    my $msb  = 0;
    my $sign = ord($data[2]) & 255;
      
    #-- test with -25 degrees
    #$lsb   =  12*16+14;
    #$sign  = 1;
    #$delta = 0;
      
    #-- 2's complement form = signed bytes
    $owg_temp = int($lsb/2) + $delta;
    if( $sign !=0 ){
      $owg_temp = -128+$owg_temp;
    }

    $ow_thn = ord($data[3]) > 127 ? 128-ord($data[3]) : ord($data[3]);
    $ow_tln = ord($data[4]) > 127 ? 128-ord($data[4]) : ord($data[4]);

  } elsif ( ($hash->{OW_FAMILY} eq "22") || ($hash->{OW_FAMILY} eq "28") ) {
     
    my $lsb  = ord($data[1]);
    my $msb  = ord($data[2]) & 7;
    my $sign = ord($data[2]) & 248;
      
    #-- test with -55 degrees
    #$lsb   = 9*16;
    #$sign  = 1;
    #$msb   = 7;
      
    #-- 2's complement form = signed bytes
    $owg_temp = $msb*16+ $lsb/16;   
    if( $sign !=0 ){
      $owg_temp = -128+$owg_temp;
    }
    $ow_thn = ord($data[3]) > 127 ? 128-ord($data[3]) : ord($data[3]);
    $ow_tln = ord($data[4]) > 127 ? 128-ord($data[4]) : ord($data[4]);
    
  } else {
    return "OWXTHERM: Unknown device family $hash->{OW_FAMILY}\n";
  }
  
  #-- process alarm settings
  $owg_tl = $ow_tln;
  $owg_th = $ow_thn;
  
  return undef;
}

#######################################################################################
#
# OWXTHERM_SetValues - Implements SetFn function
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
########################################################################################

sub OWXTHERM_SetValues($@) {
  my ($hash, @a) = @_;
  
  my ($i,$j,$k);
  
  my $name = $hash->{NAME};
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
 
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  return undef
    if( !defined($value));
  return undef 
    if( $value eq "");
    
  #-- $owg_tl and $owg_th are preset and may be changed here
  $owg_tl = $value if( lc($key) eq "templow" );
  $owg_th = $value if( lc($key) eq "temphigh");

  #-- put into 2's complement formed (signed byte)
  my $tlp = $owg_tl < 0 ? 128 - $owg_tl : $owg_tl; 
  my $thp = $owg_th < 0 ? 128 - $owg_th : $owg_th; 

  OWX_Reset($master);
  
  #-- issue the match ROM command \x55 and the write scratchpad command \x4E,
  #   followed by the write EEPROM command \x48
  #
  #   so far writing the EEPROM does not work properly.
  #   1. \x48 directly appended to the write scratchpad command => command ok, no effect on EEPROM
  #   2. \x48 appended to match ROM => command not ok. 
  #   3. \x48 sent by WriteBytePower after match ROM => command ok, no effect on EEPROM
  
  my $select=sprintf("\x4E%c%c\x48",$thp,$tlp); 
  my $res=OWX_Complex($master,$owx_dev,$select,3);

  if( $res eq 0 ){
    return "OWXTHERM: Device $owx_dev not accessible"; 
  } 
  
  return undef;
}

1;

=pod
=begin html

<a name="OWTHERM"></a>
        <h3>OWTHERM</h3>
        <p>FHEM module to commmunicate with 1-Wire bus digital thermometer devices<br />
        <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
            (prerequisite: Add this module's name to the list of clients in OWServer).
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first. <br />
        </p>
        <h4>Example</h4>
        <p>
            <code>define OWX_T OWTHERM DS18B20 E8D09B030000 300</code>
            <br />
            <code>attr OWX_T tempUnit Kelvin</code>
            <br />
        </p><br />
        <a name="OWTHERMdefine"></a>
        <h4>Define</h4>
        <p>
        <code>define &lt;name&gt; OWTHERM [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
        <code>define &lt;name&gt; OWTHERM &lt;fam&gt;.lt;id&gt; [&lt;interval&gt;]</code>
        <br /><br /> Define a 1-Wire digital thermometer device.</p>
        <ul>
          <li>
            <code>[&lt;model&gt;]</code><br /> Defines the thermometer model (and thus 1-Wire family
            id) currently the following values are permitted: </p>
            <ul>
              <li>model DS1820 with family id 10 (default if the model parameter is omitted)</li>
              <li>model DS1822 with family id 22</li>
              <li>model DS18B20 with family id 28</li>
          </ul>
          </li>
          <li>
           <code>&lt;fam&gt;</code>
                <br />2-character unique family id, see above </li>
          <li>
            <code>&lt;id&gt;</code>
            <br />12-character unique ROM id of the thermometer device without family id and CRC
            code 
         </li>
          <li>
            <code>&lt;interval&gt;</code>
            <br /> Temperature measurement interval in seconds. The default is 300 seconds. 
         </li>
        </ul>
        <a name="OWTHERMset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owtherm_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Temperature
                readout intervall in seconds. The default is 300 seconds. <b>Attention:</b>This is the 
                readout interval. Whether an actual temperature measurement is performed, is determined by the
                tempConv attribute </li>
            <li><a name="owtherm_tempHigh">
                    <code>set &lt;name&gt; tempHigh &lt;float&gt;</code></a>
                <br /> The high alarm temperature (on the temperature scale chosen by the attribute
                value) </li>
            <li><a name="owtherm_tempLow">
                    <code>set &lt;name&gt; tempLow &lt;float&gt;</code></a>
                <br /> The low alarm temperature (on the temperature scale chosen by the attribute
                value) </li>
        </ul>
        <br />
        <a name="OWTHERMget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owtherm_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owtherm_present">
                    <code>get &lt;name&gt; present</code></a>
                <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
            <li><a name="owtherm_interval2">
                    <code>get &lt;name&gt; interval</code></a><br />Returns temperature measurement
                interval in seconds.</li>
            <li><a name="owtherm_temperature">
                    <code>get &lt;name&gt; temperature</code></a><br />Obtain the temperature. </li>
            <li><a name="owtherm_alarm">
                    <code>get &lt;name&gt; alarm</code></a><br />Obtain the alarm temperature
                values. </li>
        </ul>
        <br />
        <a name="OWTHERMattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="owtherm_stateAL"><code>attr &lt;name&gt; stateAL &lt;string&gt;</code>
                </a>
                <br />character string for denoting low alarm condition, default is down triangle,
                e.g. the code &amp;#x25BE; leading to the sign &#x25BE; </li>
            <li><a name="owtherm_stateAH"><code>attr &lt;name&gt; stateAH &lt;string&gt;</code>
                </a>
                <br />character string for denoting high alarm condition, default is upward
                triangle, e.g. the code &amp;#x25B4; leading to the sign &#x25B4; </li>
                <li><a name="owtherm_tempConv">
                    <code>attr &lt;name&gt; tempConv onkick|onread</code>
                </a>
                <br /> determines, whether a temperature measurement will happen when "kicked" 
                through the OWX backend module (all temperature sensors at the same time), or on 
                reading the sensor (1 second waiting time, default). </li>
            <li><a name="owtherm_tempOffset"><code>attr &lt;name&gt; tempOffset &lt;float&gt;</code>
                </a>
                <br />temperature offset in &deg;C added to the raw temperature reading. </li>
            <li><a name="owtherm_tempUnit"><code>attr &lt;name&gt; tempUnit
                        Celsius|Kelvin|Fahrenheit|C|K|F</code>
                </a>
                <br />unit of measurement (temperature scale), default is Celsius = &deg;C </li>
            <li><a name="owtherm_tempHigh2">
                    <code>attr &lt;name&gt; tempHigh &lt;float&gt;</code>
                </a>
                <br /> high alarm temperature (on the temperature scale chosen by the attribute
                value). </li>
            <li><a name="owtherm_tempLow2">
                    <code>attr &lt;name&gt; tempLow &lt;float&gt;</code>
                </a>
                <br /> low alarm temperature (on the temperature scale chosen by the attribute
                value). </li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut
