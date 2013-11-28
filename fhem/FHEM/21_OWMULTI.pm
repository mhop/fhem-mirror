########################################################################################
#
# OWMULTI.pm
#
# FHEM module to commmunicate with 1-Wire chip DS2438Z - Smart Battery Monitor
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines (Martin Fischer, Peter Henning)
# OWX  = 1-Wire bus master interface (Peter Henning)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.24 - October, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWMULTI [<model>] <ROM_ID> [interval]
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2438  
#
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id          => OW_FAMILY.ROM_ID.CRC 
# get <name> present     => 1 if device present, 0 if not
# get <name> interval    => query interval
# get <name> reading     => measurement value obtained from VFunction
# get <name> temperature => temperature measurement
# get <name> VDD         => supply voltage measurement
# get <name> V|raw       => raw external voltage measurement
#
# set <name> interval    => set period for measurement
#
# Additional attributes are defined in fhem.cfg
# Note: attributes "tempXXXX" are read during every update operation.
#
# attr <name> event on-change/on-update = when to write an event (default= on-update)
#
# attr <name> tempOffset <float>        = temperature offset in degree Celsius added to the raw temperature reading 
# attr <name> tempUnit  <string>        = unit of measurement, e.g. Celsius/Kelvin/Fahrenheit or C/K/F, default is Celsius
# attr <name> VName   <string>|<string> = name for the channel | a type description for the measured value
# attr <name> VUnit   <string>|<string> = unit of measurement for the voltage channel | its abbreviation 
# attr <name> Vfunction <string>        = arbitrary functional expression involving the values VDD, V, T 
#                                         VDD is replaced by the measured supply voltage in Volt, 
#                                         V by the measured external voltage
#                                         T by the measured and corrected temperature in its unit
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

#-- temperature and voltage globals - always the raw values from the device
my $owg_temp;
my $owg_volt;
my $owg_vdd;
my $owg_channel;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "reading"     => "",
  "temperature" => "",
  "VDD"         => "",
  "V"           => "",
  "raw"         => "",
);

my %sets = (
  "interval"    => "",
);

my %updates = (
  "present"     => "",
  "reading" => "",
);

########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWMULTI
#
########################################################################################
#
# OWMULTI_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWMULTI_Define";
  $hash->{UndefFn} = "OWMULTI_Undef";
  $hash->{GetFn}   = "OWMULTI_Get";
  $hash->{SetFn}   = "OWMULTI_Set";
  #tempOffset = a temperature offset added to the temperature reading for correction 
  #tempUnit   = a unit of measure: C/F/K
  $hash->{AttrList}= "IODev do_not_notify:0,1 showtime:0,1 loglevel:0,1,2,3,4,5 ".
                     "event:on-update,on-change ".
                     "tempOffset tempUnit:C,Celsius,F,Fahrenheit,K,Kelvin ".
                     "VName VUnit VFunction";
  }
  
########################################################################################
#
# OWMULTI_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWMULTI_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWMULTI [<model>] <id> [interval]
  # e.g.: define flow OWMULTI 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$ret);
  my $tn = TimeNow();
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $ret           = "";

  #-- check syntax
  return "OWMULTI: Wrong syntax, must be define <name> OWMULTI [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 6);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if(  ($a2 eq "none") || ($a3 eq "none")  ) {
    return "OWMULTI: ID = none is obsolete now, please redefine";
  } elsif( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2438";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
    Log 1, "OWMULTI: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 5);
  } elsif( $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    Log 1, "OWMULTI: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 6);
  } else {    
    return "OWMULTI: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }

  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   FF = family id follows from the model
  #   YY must be determined from id
  if( $model eq "DS2438" ){
    $fam = "26";
  }else{
    return "OWMULTI: Wrong 1-Wire device model $model";
  }
  # determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- define device internals
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{INTERVAL}   = $interval;

  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWMULTI: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWMULTI}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWMULTI: Device $name defined."; 
  
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+10, "OWMULTI_InitializeDevice", $hash, 0);
   
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 0);

  return undef; 
}
  
########################################################################################
#
# OWMULTI_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
  my @args;
  
  #-- unit attribute defined ?
  $hash->{READINGS}{"temperature"}{UNIT} = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : "Celsius";
  $hash->{READINGS}{"temperature"}{TYPE} = "temperature";
  
  #-- Initial readings temperature sensor
  $owg_temp = 0.0;
  $owg_volt = 0.0;
  $owg_vdd  = 5.0;  
  #-- Set channel name, channel unit for voltage channel
  my $cname = defined($attr{$name}{"VName"})  ? $attr{$name}{"VName"} : "voltage|voltage";
  my @cnama = split(/\|/,$cname);
  if( int(@cnama)!=2){
    Log 1, "OWMULTI: Incomplete channel name specification $cname. Better use $cname|<type of data>";
    push(@cnama,"unknown");
  }
 
  #-- unit
  my $unit = defined($attr{$name}{"VUnit"})  ? $attr{$name}{"VUnit"} : "Volt|V";
  my @unarr= split(/\|/,$unit);
  if( int(@unarr)!=2 ){
    Log 1, "OWMULTI: Incomplete channel unit specification $unit. Better use $unit|<abbreviation>";
    push(@unarr,"");  
  }
    
  #-- put into readings
  $owg_channel = $cnama[0]; 
  $hash->{READINGS}{"$owg_channel"}{TYPE}     = $cnama[1];  
  $hash->{READINGS}{"$owg_channel"}{UNIT}     = $unarr[0];
  $hash->{READINGS}{"$owg_channel"}{UNITABBR} = $unarr[1];
    
  #-- Initialize all the display stuff  
  OWMULTI_FormatValues($hash);
  
}

########################################################################################
#
# OWMULTI_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWMULTI_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($tunit,$toffset,$tfactor,$tabbr,$tval,$vfunc,$vval);
  my ($value1,$value2)   = ("","");

  my $tn = TimeNow();
  
  #-- attributes defined ?
  $tunit  = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : $hash->{READINGS}{"temperature"}{UNIT};
  $toffset = defined($attr{$name}{"tempOffset"}) ? $attr{$name}{"tempOffset"} : 0.0 ;
  $tfactor = 1.0;
  
  if( $tunit eq "Celsius" ){
    $tabbr   = "&deg;C";
  } elsif ($tunit eq "Kelvin" ){
    $tabbr   = "K";
    $toffset += "273.16"
  } elsif ($tunit eq "Fahrenheit" ){
    $tabbr   = "&deg;F";
    $toffset = ($toffset+32)/1.8;
    $tfactor = 1.8;
  } else {
    $tabbr="?";
    Log 1, "OWMULTI_FormatValues: unknown unit $tunit";
  }
  #-- these values are rather coplex to obtain, therefore save them in the hash
  $hash->{READINGS}{"temperature"}{UNIT}     = $tunit;
  $hash->{READINGS}{"temperature"}{UNITABBR} = $tabbr;
  $hash->{tempf}{offset}                     = $toffset;
  $hash->{tempf}{factor}                     = $tfactor;
  
  #-- correct values for proper offset, factor 
  $tval  = ($owg_temp + $toffset)*$tfactor;

  #-- put into READINGS
  $hash->{READINGS}{"temperature"}{VAL}   = $tval;
  $hash->{READINGS}{"temperature"}{TIME}  = $tn;
   
  my $cname = defined($attr{$name}{"VName"})  ? $attr{$name}{"VName"} : "voltage|voltage";
  my @cnama = split(/\|/,$cname);
  $owg_channel=$cnama[0];
  
   #-- attribute VFunction defined ?
  $vfunc   = defined($attr{$name}{"VFunction"}) ? $attr{$name}{"VFunction"} : "V";

  #-- replace by proper values 
  $vfunc =~ s/VDD/\$owg_vdd/g;
  $vfunc =~ s/V/\$owg_volt/g;
  $vfunc =~ s/T/\$tval/g;
  
  #-- determine the measured value from the function
  $vfunc = "\$owg_vdd = $owg_vdd; \$owg_volt = $owg_volt; \$tval = $tval; ".$vfunc;
  $vfunc = eval($vfunc);
  if( $vfunc ne "" ){
    $vval = int( $vfunc*1000 )/1000;
  } else {
    $vval = 0.0;
  }
  
  #-- put into READINGS
  $hash->{READINGS}{"$owg_channel"}{VAL}   = $vval;
  $hash->{READINGS}{"$owg_channel"}{TIME}  = $tn;
  $hash->{READINGS}{"VDD"}{VAL}   = $owg_vdd;
  $hash->{READINGS}{"VDD"}{TIME}  = $tn;
         
  #-- string buildup for return value, STATE 
  $value1 .= sprintf( "%s: %5.3f %s temperature %5.3f %s VDD %5.2f V", $owg_channel, $vval,$hash->{READINGS}{"$owg_channel"}{UNITABBR},$tval,$tabbr,$owg_vdd);
  $value2 .= sprintf( "%s: %5.2f %s (T: %5.2f %s)", $owg_channel, $vval,$hash->{READINGS}{"$owg_channel"}{UNITABBR},$tval,$tabbr);
   
  #-- STATE
  $hash->{STATE} = $value2;

  return $value1;
}
  
########################################################################################
#
# OWMULTI_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWMULTI_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = undef;
  my $ret     = "";

  #-- check syntax
  return "OWMULTI: Get argument is missing @a"
    if(int(@a) != 2);
    
  #-- check argument
  return "OWMULTI: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
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
      return "OWMULTI: Verification not yet implemented for interface $interface";
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
    $ret = OWXMULTI_GetValues($hash);
  #-- OWFS interface not yet implemented
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSMULTI_GetValues($hash);
  #-- Unknown interface
  }else{
    return "OWMULTI: Get with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWMULTI: Could not get values from device $name, return was $ret";
  }
  $hash->{PRESENT} = 1; 
  OWMULTI_FormatValues($hash);
  
  #-- return the special reading
  if ($reading eq "reading") {
    return "OWMULTI: $name.reading => ".
      $hash->{READINGS}{"$owg_channel"}{VAL};
  } 
  if ($reading eq "temperature") {
    return "OWMULTI: $name.temperature => ".
      $hash->{READINGS}{"temperature"}{VAL};
  } 
  if ($reading eq "VDD") {
    return "OWMULTI: $name.VDD => ".
      $hash->{READINGS}{"VDD"}{VAL};
  } 
  if ( ($reading eq "V")|($reading eq "raw")) {
    return "OWMULTI: $name.V => ".
      $owg_volt;
  } 
  return undef;
}

#######################################################################################
#
# OWMULTI_GetValues - Updates the readings from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_GetValues($@) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $value   = "";
  my $ret     = "";
  
  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 1);

  #-- reset presence
  $hash->{PRESENT}  = 0;

  #-- Get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    #-- max 3 tries
    for(my $try=0; $try<3; $try++){
      $ret = OWXMULTI_GetValues($hash);
      last
        if( !defined($ret) );
    } 
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSTHERM_GetValues($hash);
  }else{
    Log 3, "OWMULTI: GetValues with wrong IODev type $interface";
    return 1;
  }

  #-- process results
  if( defined($ret)  ){
    Log 3, "OWMULTI: Could not get values from device $name, reason $ret";
    return 1;
  }
  $hash->{PRESENT} = 1; 

  #-- old state, new state
  my $oldval = $hash->{STATE};
  $value=OWMULTI_FormatValues($hash);
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
# OWMULTI_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################

sub OWMULTI_Set($@) {
  my ($hash, @a) = @_;

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a == 2);
  #-- check syntax
  return "OWMULTI: Set needs one parameter"
    if(int(@a) != 3);
  #-- check argument
  return "OWMULTI: Set with unknown argument $a[1], choose one of ".join(",", sort keys %sets)
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
    return "OWMULTI: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 1);
    return undef;
  }

  #-- set other values depending on interface type
  my $interface = $hash->{IODev}->{TYPE};
  my $offset    = $hash->{tempf}{offset};
  my $factor    = $hash->{tempf}{factor};
    
  #-- find upper and lower boundaries for given offset/factor
  my $mmin = (-55+$offset)*$factor;
  my $mmax = (125+$offset)*$factor;
  return sprintf("OWMULTI: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
    if($value < $mmin || $value > $mmax);
    
  #-- seems to be ok, put into the device
  $a[2]  = int($value/$factor-$offset);

  #-- OWX interface
  if( $interface eq "OWX" ){
    $ret = OWXMULTI_SetValues($hash,@a);
  #-- OWFS interface not yet implemented
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSTHERM_SetValues($hash,@a);
  #  return $ret
  #    if(defined($ret));
  } else {
  return "OWMULTI: Set with wrong IODev type $interface";
  }
  
  #-- process results - we have to reread the device
  $hash->{PRESENT} = 1; 
  OWMULTI_GetValues($hash);
  OWMULTI_FormatValues($hash);
  Log 4, "OWMULTI: Set $hash->{NAME} $key $value";
  
  return undef;
}

########################################################################################
#
# OWMULTI_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_Undef ($) {
  my ($hash) = @_;
  
  delete($modules{OWMULTI}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXMULTI
#
########################################################################################
#
# OWXMULTI_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXMULTI_GetValues($) {

  my ($hash) = @_;
  
  my ($i,$j,$k,$res,$res2);
   
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  #-- switch the device to current measurement off, VDD only
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the write scratchpad command
   if( OWX_Complex($master,$owx_dev,"\x4E\x00\x08",0) eq 0 ){
    return "$owx_dev write status failed";
  } 

  #-- copy scratchpad to register
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the copy scratchpad command
  if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
    return "$owx_dev copy scratchpad failed"; 
  }
     
  #-- initiate temperature conversion
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the start conversion command
  if( OWX_Complex($master,$owx_dev,"\x44",0) eq 0 ){
    return "$owx_dev temperature conversion failed";
  } 
  #-- conversion needs some 10 ms !
  select(undef,undef,undef,0.012);
  
  #-- initiate voltage conversion
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the start conversion command
  if( OWX_Complex($master,$owx_dev,"\xB4",0) eq 0 ){
    return "$owx_dev voltage conversion failed";
  } 
  #-- conversion needs some 4 ms  !
  select(undef,undef,undef,0.006);
  
  #-- from memory to scratchpad
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the recall memory command
  if( OWX_Complex($master,$owx_dev,"\xB8\x00",0) eq 0 ){
     return "$owx_dev recall memory failed";
   } 
  #-- copy needs some 10 ms !
  select(undef,undef,undef,0.012);
  
  #-- NOW ask the specific device 
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the read scratchpad command \xBE
  #-- reading 9 + 2 + 9 data bytes = 20 bytes
  $res=OWX_Complex($master,$owx_dev,"\xBE\x00",9);
  #Log 1,"OWXMULTI: data length from reading device is ".length($res)." bytes";
  #-- process results
  if( $res eq 0 ){
    return "$owx_dev not accessible in 2nd step"; 
  }
  
  #  $res2 = "====> OWXMULTI Received ";
  #  for(my $i=0;$i<length($res);$i++){  
  #    my $j=int(ord(substr($res,$i,1))/16);
  #    my $k=ord(substr($res,$i,1))%16;
  #    $res2.=sprintf "0x%1x%1x ",$j,$k;
  #  }
  #  Log 1, $res2;
     
  #-- process results
  my  @data=split(//,$res);
  return "invalid data length, ".int(@data)." bytes"
    if (@data != 20); 
  return "conversion not complete or data invalid"
    if ((ord($data[11]) & 112)!=0); 
  #return "invalid CRC"
  #  if (OWX_CRC8(substr($res,10,8),$data[18])==0);
  
  #-- this must be different for the different device types
  #   family = 26 => DS2438
  
  #-- temperature
  my $lsb  = ord($data[12]);
  my $msb  = ord($data[13]) & 127;
  my $sign = ord($data[13]) & 128;
      
  #-- test with -55 degrees
  #$lsb   = 0;
  #$sign  = 1;
  #$msb   = 73;
      
  #-- 2's complement form = signed bytes
  $owg_temp = $msb+ $lsb/256;   
  if( $sign !=0 ){
    $owg_temp = -128+$owg_temp;
  }
  
  #-- voltage
  $lsb  = ord($data[14]);
  $msb  = ord($data[15]) & 3;
      
  #-- test with 5V
  #$lsb  = 244;
  #$msb  = 1;
      
  #-- supply voltage
  $owg_vdd = ($msb*256+ $lsb)/100;   
  
  #-- switch the device to current measurement off, V external only
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the write scratchpad command
  if( OWX_Complex($master,$owx_dev,"\x4E\x00\x00",0) eq 0 ){
    return "$owx_dev write status failed";
  } 
  
  #-- copy scratchpad to register
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the copy scratchpad command
  if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
    return "$owx_dev copy scratchpad failed"; 
  }
  
  #-- initiate voltage conversion
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the start conversion command
  if( OWX_Complex($master,$owx_dev,"\xB4",0) eq 0 ){
    return "$owx_dev voltage conversion failed";
  } 
  #-- conversion needs some 4 ms  !
  select(undef,undef,undef,0.006);
  
 #-- from memory to scratchpad
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the recall memory command
  if( OWX_Complex($master,$owx_dev,"\xB8\x00",0) eq 0 ){
     return "$owx_dev recall memory failed";
   } 
  #-- copy needs some 10 ms !
  select(undef,undef,undef,0.012);
  
  #-- NOW ask the specific device 
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the read scratchpad command \xBE
  #-- reading 9 + 2 + 9 data bytes = 20 bytes
  $res=OWX_Complex($master,$owx_dev,"\xBE\x00",9);
  #Log 1,"OWXMULTI: data length from reading device is ".length($res)." bytes";
  #-- process results
  if( $res eq 0 ){
    return "$owx_dev not accessible in 2nd step"; 
  }
  
  #  $res2 = "====> OWXMULTI Received ";
  #  for(my $i=0;$i<length($res);$i++){  
  #    my $j=int(ord(substr($res,$i,1))/16);
  #    my $k=ord(substr($res,$i,1))%16;
  #    $res2.=sprintf "0x%1x%1x ",$j,$k;
  #  }
  #  Log 1, $res2;
     
  #-- process results
  @data=split(//,$res);
  return "invalid data length, ".int(@data)." bytes"
    if (@data != 20); 
  return "conversion not complete or data invalid"
    if ((ord($data[11]) & 112)!=0); 
  #return "invalid CRC"
  #  if (OWX_CRC8(substr($res,10,8),$data[18])==0);
  
  #-- this must be different for the different device types
  #   family = 26 => DS2438
  
  #-- voltage
  $lsb  = ord($data[14]);
  $msb  = ord($data[15]) & 3;
      
  #-- test with 7.2 V
  #$lsb  = 208;
  #$msb  = 2;
      
  #-- external voltage
  $owg_volt = ($msb*256+ $lsb)/100;   
    
  return undef;
    
  #} else {
  #  return "OWXMULTI: Unknown device family $hash->{OW_FAMILY}\n";
  #}
}

#######################################################################################
#
# OWXMULTI_SetValues - Implements SetFn function
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
########################################################################################

sub OWXMULTI_SetValues($@) {
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

  OWX_Reset($master);
  
  #-- issue the match ROM command \x55 and the write scratchpad command \x4E,
  #   followed by the write EEPROM command \x48
  #
  #   so far writing the EEPROM does not work properly.
  #   1. \x48 directly appended to the write scratchpad command => command ok, no effect on EEPROM
  #   2. \x48 appended to match ROM => command not ok. 
  #   3. \x48 sent by WriteBytePower after match ROM => command ok, no effect on EEPROM
  
  my $select=sprintf("\x4E%c%c\x48",0,0); 
  my $res=OWX_Complex($master,$owx_dev,$select,0);

  if( $res eq 0 ){
    return "OWXMULTI: Device $owx_dev not accessible"; 
  } 
  
  DoTrigger($name, undef) if($init_done);
  return undef;
}



1;

=pod
=begin html

<a name="OWMULTI"></a>
<h3>OWMULTI</h3>
<ul>FHEM module to commmunicate with 1-Wire multi-sensors, currently the DS2438 smart battery monitor<br /><br /> Note:<br /> This
    1-Wire module so far works only with the OWX interface module. Please define an <a
        href="#OWX">OWX</a> device first. <br />
    <br /><b>Example</b><br />
    <ul>
        <code>define OWX_M OWMULTI 7C5034010000 45</code>
        <br />
        <code>attr OWX_M VName relHumidity|humidity</code>
        <br />
        <code>attr OWX_M VUnit percent|%</code>
        <br />
        <code>attr OWX_M VFunction (161.29 * V / VDD - 25.8065)/(1.0546 - 0.00216 * T)</code>
        <br />
    </ul><br />
    <a name="OWMULTIdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; OWMULTI [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code>
        <br /><br /> Define a 1-Wire multi-sensor<br /><br />
        <li>
            <code>[&lt;model&gt;]</code><br /> Defines the sensor model (and thus
            1-Wire family id), currently the following values are permitted: <ul>
                <li>model DS2438 with family id 26 (default if the model parameter is
                    omitted). Measured is a temperature value, an external voltage and the current supply voltage</li>
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
    <a name="OWMULTIset">
        <b>Set</b></a>
    <ul>
        <li><a name="owmulti_interval">
            <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
            interval in seconds. The default is 300 seconds. </li>
    </ul>
    <br />
    <a name="OWMULTIget">
        <b>Get</b></a>
    <ul>
        <li><a name="owmulti_id">
            <code>get &lt;name&gt; id</code></a>
            <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
        <li><a name="owmulti_present">
            <code>get &lt;name&gt; present</code>
        </a>
            <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
        <li><a name="owmulti_interval2">
            <code>get &lt;name&gt; interval</code></a><br />Returns measurement interval
            in seconds. </li>
        <li><a name="owmulti_reading">
            <code>get &lt;name&gt; reading</code></a><br />Obtain the measurement value from VFunction. </li>
        <li><a name="owmulti_temperature">
            <code>get &lt;name&gt; temperature</code></a><br />Obtain the temperature value. </li>
        <li><a name="owmulti_vdd">
            <code>get &lt;name&gt; VDD</code></a><br />Obtain the current supply voltage.
        </li>
        <li><a name="owmulti_raw">
            <code>get &lt;name&gt; V</code> or <code>get &lt;name&gt; raw</code></a><br />Obtain the raw external voltage measurement.
        </li>
    </ul>
    <br />
    <a name="OWMULTIattr">
        <b>Attributes</b></a>
    <ul>
        <li><a name="owmulti_vname"><code>attr &lt;name&gt; VName
            &lt;string&gt;|&lt;string&gt;</code></a>
            <br />name for the channel | a type description for the measured value. </li>
        <li><a name="owmulti_vunit"><code>attr &lt;name&gt; VUnit
            &lt;string&gt;|&lt;string&gt;</code></a>
            <br />unit of measurement for this channel | its abbreviation. </li>
        <li><a name="owmulti_vfunction"><code>attr &lt;name&gt; VFunction
            &lt;string&gt;</code></a>
            <br />arbitrary functional expression involving the values VDD, V, T. Example see above.
            <ul>
            <li>VDD is replaced by the measured supply voltage in Volt,</li>
            <li> V by the measured external voltage,</li>
            <li>T by the measured and corrected temperature in its unit</li>
        </ul></li>
        <li><a name="owmulti_tempOffset"><code>attr &lt;name&gt; tempOffset
            &lt;float&gt;</code>
        </a>
            <br />temperature offset in &deg;C added to the raw temperature reading. </li>
        <li><a name="owmulti_tempUnit"><code>attr &lt;name&gt; tempUnit
            Celsius|Kelvin|Fahrenheit|C|K|F</code>
        </a>
            <br />unit of measurement (temperature scale), default is Celsius = &deg;C </li>
        <li><a name="owmulti_event"><code>attr &lt;name&gt; event on-change|on-update
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
