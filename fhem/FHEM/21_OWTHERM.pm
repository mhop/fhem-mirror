########################################################################################
#
# OWTHERM.pm
#
# FHEM module to commmunicate with 1-Wire temperature sensors DS1820, DS18S20, DS18B20, DS1822
#
# Attention: This module may communicate with the OWX module,
#            and also with the 1-Wire File System OWFS
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines (Martin Fischer, Peter Henning)
# OWFS = 1-Wire file system (Martin Fischer)
# OWX  = 1-Wire bus master interface (Peter Henning)
#
# Prof. Dr. Peter A. Henning, 2012
# Martin Fischer, 2011
# 
# Version 2.24 - October, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWTHERM [<model>] <ROM_ID> [interval]
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS1820 temperature sensor 
#              Currently allowed values are DS1820, DS18B20, DS1822
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id          => OW_FAMILY.ROM_ID.CRC 
# get <name> present     => 1 if device present, 0 if not
# get <name> interval    => query interval
# get <name> temperature => temperature measurement
# get <name> alarm       => alarm temperature settings
#
# set <name> interval    => set period for measurement
# set <name> tempLow     => lower alarm temperature setting 
# set <name> tempHigh    => higher alarm temperature setting
#
# Additional attributes are defined in fhem.cfg
# Note: attributes "tempXXXX" are read during every update operation.
#
# attr <name> event on-change/on-update = when to write an event (default= on-update)
#
# attr <name> stateAL  "<string>"  = character string for denoting low alarm condition, default is (-),
#             overwritten by attribute setting red down triangle
# attr <name> stateAH  "<string>"  = character string for denoting high alarm condition, default is (+), 
#             overwritten by attribute setting red up triangle
# attr <name> tempOffset <float>   = temperature offset in degree Celsius added to the raw temperature reading 
# attr <name> tempUnit  <string>   = unit of measurement, e.g. Celsius/Kelvin/Fahrenheit or C/K/F, default is Celsius
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

#-- Prototypes to make komodo happy
use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

#-- temperature globals - always the raw values from the device
my $owg_temp     = 0;
my $owg_th       = 0;
my $owg_tl       = 0;

#-- variables for display strings
my $stateal;
my $stateah;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "temperature" => "",
  "alarm"       => ""
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
  #tempOffset = a temperature offset added to the temperature reading for correction 
  #tempUnit   = a unit of measure: C/F/K
  $hash->{AttrList}= "IODev do_not_notify:0,1 showtime:0,1 loglevel:0,1,2,3,4,5 ".
                     "event:on-update,on-change ".
                     "stateAL stateAH ".
                     "tempOffset tempUnit:C,Celsius,F,Fahrenheit,K,Kelvin ".
                     "tempLow tempHigh";
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
  my $tn = TimeNow();
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $ret           = "";

  #-- check syntax
  return "OWTHERM: Wrong syntax, must be define <name> OWTHERM [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 6);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if(  ($a2 eq "none") || ($a3 eq "none")  ) {
    return "OWTHERM: ID = none is obsolete now, please redefine";
  } elsif( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS1820";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
    Log 1, "OWTHERM: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 5);
  } elsif( $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    Log 1, "OWTHERM: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 6);
  } else {    
    return "OWTHERM: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }

  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   FF = family id follows from the model
  #   YY must be determined from id
  if( $model eq "DS1820" ){
    $fam = "10";
  }elsif( $model eq "DS1822" ){
    $fam = "22";
  }elsif( $model eq "DS18B20" ){
    $fam = "28";
  }else{
    return "OWTHERM: Wrong 1-Wire device model $model";
  }
  # determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- define device internals
  $hash->{ALARM}      = 0;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{INTERVAL}   = $interval;

  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWTHERM: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWTHERM}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWTHERM: Device $name defined."; 
  
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+10, "OWTHERM_InitializeDevice", $hash, 0);
   
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWTHERM_GetValues", $hash, 0);

  return undef; 
}
  
########################################################################################
#
# OWTHERM_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWTHERM_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
  my @args;
  
  #-- more colorful alarm signatures
  CommandAttr (undef,"$name stateAL <span style=\"color:red\">&#x25BE;</span>")
     if( !defined($attr{$name}{"stateAL"} ));
  CommandAttr (undef,"$name stateAH <span style=\"color:red\">&#x25B4;</span>")
     if( !defined($attr{$name}{"stateAH"} ));
  
  #-- unit attribute defined ?
  $hash->{READINGS}{"temperature"}{UNIT} = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : "Celsius";
  $hash->{READINGS}{"temperature"}{TYPE} = "temperature";
  
  #-- Initial readings temperature sensor
  $owg_temp  =  0.0;
  $owg_tl = defined($attr{$name}{"tempLow"})   ? $attr{$name}{"tempLow"}   : 0.0;
  $owg_th = defined($attr{$name}{"tempHigh"})  ? $attr{$name}{"tempHigh"}  : 100.0;
  #-- Initialize all the display stuff  
  OWTHERM_FormatValues($hash);
  #-- alarm
  @args   = ($name,"tempLow",$owg_tl);
  OWTHERM_Set($hash,@args);
  @args   = ($name,"tempHigh",$owg_th);
  OWTHERM_Set($hash,@args);
  
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
  my ($unit,$offset,$factor,$abbr,$vval,$vlow,$vhigh,$statef);
  my ($value1,$value2,$value3)   = ("","","");

  my $tn = TimeNow();
  
  #-- attributes defined ?
  $stateal = defined($attr{$name}{stateAL}) ? $attr{$name}{stateAL} : "(-)";
  $stateah = defined($attr{$name}{stateAH}) ? $attr{$name}{stateAH} : "(+)";
  $unit   = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : $hash->{READINGS}{"temperature"}{UNIT};
  $offset = defined($attr{$name}{"tempOffset"}) ? $attr{$name}{"tempOffset"} : 0.0 ;
  $factor = 1.0;
  
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
    Log 1, "OWTHERM_FormatValues: unknown unit $unit";
  }
  #-- these values are rather coplex to obtain, therefore save them in the hash
  $hash->{READINGS}{"temperature"}{UNIT}     = $unit;
  $hash->{READINGS}{"temperature"}{UNITABBR} = $abbr;
  $hash->{tempf}{offset}                     = $offset;
  $hash->{tempf}{factor}                     = $factor;
  
  #-- correct values for proper offset, factor 
  $vval  = ($owg_temp + $offset)*$factor;
  
  #-- put into READINGS
  $hash->{READINGS}{"temperature"}{VAL}   = $vval;
  $hash->{READINGS}{"temperature"}{TIME}  = $tn;
    
  #-- correct alarm values for proper offset, factor 
  $vlow   = ($owg_tl + $offset)*$factor;
  $vhigh  = ($owg_th + $offset)*$factor;
  
  #-- put into READINGS
  $hash->{READINGS}{"tempLow"}{VAL}     = $vlow;
  $hash->{READINGS}{"tempLow"}{TIME}    = $tn;
  $hash->{READINGS}{"tempHigh"}{VAL}    = $vhigh;
  $hash->{READINGS}{"tempHigh"}{TIME}   = $tn;   
         
  #-- formats for output
  $statef  = "%5.2f ".$abbr;
  $value1 = "temperature: ".sprintf($statef,$vval);
  $value2 = sprintf($statef,$vval);
  $hash->{ALARM} = 1;
  
  #-- Test for alarm condition
  if( ($vval <= $vlow) && ( $vval >= $vhigh ) ){
    $value2 .= " ".$stateal.$stateah;
    $value3 .= " ".$stateal.$stateah;
  }elsif( $vval <= $vlow ){
    $value2 .= " ".$stateal;
    $value3 .= " ".$stateal; 
  }elsif( $vval >= $vhigh ){
    $value2 .= " ".$stateah;
    $value3 .= " ".$stateah;
  } else {
    $hash->{ALARM} = 0;
  }
  
  #-- STATE
  $hash->{STATE} = $value2;
  #-- alarm
  #$hash->{READINGS}{alarms}{VAL}  = $value3;
  #$hash->{READINGS}{alarms}{TIME}   = $tn;
  return $value1;
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
  return "OWTHERM: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
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
  if($reading eq "interval") {
    $value = $hash->{INTERVAL};
     return "$name.interval => $value";
  } 
  
  #-- reset presence
  $hash->{PRESENT}  = 0;

  #-- OWX interface
  if( $interface eq "OWX" ){
    #-- not different from getting all values ..
    $ret = OWXTHERM_GetValues($hash);
  #-- OWFS interface
  }elsif( $interface eq "OWFS" ){
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
    return "OWTHERM: $name.alarm => L ".$hash->{READINGS}{"tempLow"}{VAL}.
      " H ".$hash->{READINGS}{"tempHigh"}{VAL};
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
  }elsif( $interface eq "OWFS" ){
    $ret = OWFSTHERM_GetValues($hash);
  }else{
    Log 3, "OWTHERM: GetValues with wrong IODev type $interface";
    return 1;
  }

  #-- process results
  if( defined($ret)  ){
    Log 3, "OWTHERM: Could not get values from device $name, reason $ret";
    return 1;
  }
  $hash->{PRESENT} = 1; 

  #-- old state, new state
  my $oldval = $hash->{STATE};
  $value=OWTHERM_FormatValues($hash);
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

  #-- set other values depending on interface type
  my $interface = $hash->{IODev}->{TYPE};
  my $offset    = $hash->{tempf}{offset};
  my $factor    = $hash->{tempf}{factor};
    
  #-- find upper and lower boundaries for given offset/factor
  my $mmin = (-55+$offset)*$factor;
  my $mmax = (125+$offset)*$factor;
  return sprintf("OWTHERM: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
    if($value < $mmin || $value > $mmax);
    
  #-- seems to be ok, put into the device
  $a[2]  = int($value/$factor-$offset);

  #-- OWX interface
  if( $interface eq "OWX" ){
    $ret = OWXTHERM_SetValues($hash,@a);
  #-- OWFS interface
  }elsif( $interface eq "OWFS" ){
    $ret = OWFSTHERM_SetValues($hash,@a);
    return $ret
      if(defined($ret));
  } else {
  return "OWTHERM: Set with wrong IODev type $interface";
  }
  
  #-- process results - we have to reread the device
  $hash->{PRESENT} = 1; 
  OWTHERM_GetValues($hash);
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
# OWFSTHERM_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSTHERM_GetValues($)
{
  my ($hash) = @_;

  my $ret = OW::get("/uncached/".$hash->{OW_FAMILY}.".".$hash->{OW_ID}."/temperature");
  if( defined($ret) ) {
    $hash->{PRESENT} = 1;
    $owg_temp = $ret;
    $owg_th   = OW::get("/uncached/".$hash->{OW_FAMILY}.".".$hash->{OW_ID}."/temphigh");
    $owg_tl   = OW::get("/uncached/".$hash->{OW_FAMILY}.".".$hash->{OW_ID}."/templow");
  } else {
    $hash->{PRESENT} = 0;
    $owg_temp = 0.0;
    $owg_th   = 0.0;
    $owg_tl   = 0.0;
  }

  return undef;
}

#######################################################################################
#
# OWFSTHERM_SetValues - Implements SetFn function
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
########################################################################################

sub OWFSTHERM_SetValues($@) {
  my ($hash, @a) = @_;
  
  #-- define vars
  my $key   = lc($a[1]);
  my $value = $a[2];
  
  return OW::put($hash->{OW_FAMILY}.".".$hash->{OW_ID}."/$key",$value);
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
  
  my ($i,$j,$k);
  
  #-- For default, perform the conversion NOT now
  my $con=1;
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  #-- check, if the conversion has been called before - only on devices with real power
  if( defined($attr{$hash->{IODev}->{NAME}}{buspower}) && ( $attr{$hash->{IODev}->{NAME}}{buspower} eq "real") ){
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
  my  @data=split(//,$res);
  return "invalid data length, ".int(@data)." bytes"
    if (@data != 19); 
  return "invalid data"
    if (ord($data[17])<=0); 
  return "invalid CRC"
    if (OWX_CRC8(substr($res,10,8),$data[18])==0);
  
  #-- this must be different for the different device types
  #   family = 10 => DS1820, DS18S20
  if( $hash->{OW_FAMILY} eq "10" ) {    
  
    my $count_remain = ord($data[16]);
    my $count_perc   = ord($data[17]);
    my $delta        = -0.25 + ($count_perc - $count_remain)/$count_perc;
   
    my $lsb  = ord($data[10]);
    my $msb  = 0;
    my $sign = ord($data[11]) & 255;
      
    #-- test with -25 degrees
    #$lsb   =  12*16+14;
    #$sign  = 1;
    #$delta = 0;
      
    #-- 2's complement form = signed bytes
    $owg_temp = int($lsb/2) + $delta;
    if( $sign !=0 ){
      $owg_temp = -128+$owg_temp;
    }

    $owg_th = ord($data[12]) > 127 ? 128-ord($data[12]) : ord($data[12]);
    $owg_tl = ord($data[13]) > 127 ? 128-ord($data[13]) : ord($data[13]);
 
    return undef;

  } elsif ( ($hash->{OW_FAMILY} eq "22") || ($hash->{OW_FAMILY} eq "28") ) {
     
    my $lsb  = ord($data[10]);
    my $msb  = ord($data[11]) & 7;
    my $sign = ord($data[11]) & 248;
      
    #-- test with -55 degrees
    #$lsb   = 9*16;
    #$sign  = 1;
    #$msb   = 7;
      
    #-- 2's complement form = signed bytes
    $owg_temp = $msb*16+ $lsb/16;   
    if( $sign !=0 ){
      $owg_temp = -128+$owg_temp;
    }
    $owg_th = ord($data[12]) > 127 ? 128-ord($data[12]) : ord($data[12]);
    $owg_tl = ord($data[13]) > 127 ? 128-ord($data[13]) : ord($data[13]);
    
    return undef;
    
  } else {
    return "OWXTHERM: Unknown device family $hash->{OW_FAMILY}\n";
  }
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
  $owg_tl = $value if( $key eq "tempLow" );
  $owg_th = $value if( $key eq "tempHigh" );

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
  my $res=OWX_Complex($master,$owx_dev,$select,0);

  if( $res eq 0 ){
    return "OWXTHERM: Device $owx_dev not accessible"; 
  } 
  
  DoTrigger($name, undef) if($init_done);
  return undef;
}



1;
