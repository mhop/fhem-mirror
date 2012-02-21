########################################################################################
#
# OWTEMP.pm
#
# FHEM module to commmunicate with 1-Wire temperature sensors
#
# Attention: This module works as a replacement for the standard 21_OWTEMP.pm,
#            therefore may communicate with the 1-Wire File System OWFS,
#            but also with the newer and more direct OWX module
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines (Martin Fischer, Peter Henning)
# OWFS = 1-Wire file system (Martin Fischer)
# OWX  = 1-Wire bus master interface (Peter Henning)
#
# Martin Fischer, 2011
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 1.0 - February 21, 2012
#   
# Setup bus device in fhem.cfg as
# define <name> OWTEMP [<model>] <ROM_ID> [interval] [alarminterval]
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS1820 temperature sensor 
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#       [alarminterval] as an additional parameter is ignored so far !
#
# Additional attributes are defined in fhem.cfg as
#
# attr <name> offset <float> = a temperature offset added to the temperature reading 
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

#-- declare variables
my $ownet;
my %gets    = ();
my %sets    = ();
my %updates = ();

#-- temperature globals
my $owg_temp=0;
my $owg_th=0;
my $owg_tl=0;

# temperature scale from IODev
my $scale;

%gets = (
  #"address"     => "",
  #"alias"       => "",
  #"crc8"        => "",
  #"family"      => "10",
  #"id"          => "",
  #"locator"     => "",
  #"power"       => "",
  "present"     => "",
  "temperature" => "",
  "temphigh"    => "",
  "templow"     => ""
  #,
  #"type"        => "",
);

%sets = (
  #-- obsolete "alias"         => "",
  "temphigh"      => "",
  "templow"       => "",
  "interval"      => ""
  #-- taken out into I/O-Device parameters,
  #"alarminterval" => "",
);

%updates = (
  "present"     => "",
  "temperature" => "",
  "templow"     => "",
  "temphigh"    => "",
);

my %dummy = (
  "crc8"         => "4D",
  "alias"        => "dummy",
  "locator"      => "FFFFFFFFFFFFFFFF",
  "power"        => "0",
  "present"      => "1",
  "temphigh"     => "75",
  "templow"      => "10",
  "type"         => "DS18S20",
  "warnings"     => "none",
);

########################################################################################
#
# The following subroutines in alphabetical order are independent of the bus interface
#
# Prefix = OWTEMP
#
#########################################################################################
#
# OWTEMP_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWTEMP_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWTEMP [<model>] <id> [interval] [alarminterval]
  # e.g.: define flow OWTEMP 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$id,$interval,$alarminterval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWTEMP: Wrong syntax, must be define <name> OWTEMP [<model>] <id> [interval] [alarminterval]"
       if(int(@a) < 2 || int(@a) > 6);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = lc($a[2]);
  my $a3 = defined($a[3]) ? lc($a[3]) : "";
  if(  ($a2 eq "none") || ($a2 =~ m/^[0-9|a-f]{12}$/) ) {
    $model         = "DS1820";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
    Log 1, "OWTEMP: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 5);
  } elsif(  ($a3 eq "none") || ($a3 =~ m/^[0-9|a-f]{12}$/) ) {
    $model         = $a[2];
    return "OWTEMP: Wrong 1-Wire device model $model"
      if( $model ne "DS1820");
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    Log 1, "OWTEMP: Parameter [alarminterval] is obsolete now - must be set with I/O-Device"
      if(int(@a) == 6);
  } else {    
    return "OWTEMP: $a[0] hat missing ID or wrong ID format $a[2], specify a 12 digit value or set it to none for demo mode";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #    
  #   Careful: For now this is effectively only 14 characters = 7 byte long and 
  #   must not be passed back to the 1-Wire bus. The 8th byte is the CRC code
  #   and will be appended in the first call of GetTemperatures
  #   TODO: should be replaced by a calculation of the CRC value !
  #-- define device internals
  $hash->{ALARM}      = 0;
  $hash->{INTERVAL}   = $interval;
  $hash->{ROM_ID}     = "10.".$id."00";
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = 10;
  $hash->{PRESENT}    = 0;

  $modules{OWTEMP}{defptr}{$id} = $hash;

  AssignIoPort($hash);
  Log 3, "OWTEMP: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));

  #-- get scale from I/O device
  $scale = $attr{$hash->{IODev}->{NAME}}{"temp-scale"};
  # define scale for temperature values
  $scale = "Celsius"    if ($scale eq "C");
  $scale = "Fahrenheit" if ($scale eq "F");
  $scale = "Kelvin"     if ($scale eq "K");
  $scale = "Rankine"    if ($scale eq "R");
  $hash->{OW_SCALE} = $scale;

  #-- define dummy values for testing
  if($hash->{OW_ID} eq "none") {
    my $now   = TimeNow();
    $dummy{address}     = $hash->{OW_FAMILY}.$hash->{OW_ID}.$dummy{crc8};
    $dummy{family}      = $hash->{OW_FAMILY};
    $dummy{id}          = $hash->{OW_ID};
    $dummy{temperature} = "80.0000 (".$hash->{OW_SCALE}.")";
    foreach my $r (sort keys %gets) {
      $hash->{READINGS}{$r}{TIME} = $now;
      $hash->{READINGS}{$r}{VAL}  = $dummy{$r};
      Log 4, "OWTEMP: $hash->{NAME} $r: ".$dummy{$r};
    }
  #-- Initial readings temperature sensor
  } else {
    $hash->{READINGS}{temp}{VAL}      = 0.0;
    $hash->{READINGS}{templow}{VAL}   = 0.0;
    $hash->{READINGS}{temphigh}{VAL}  = 0.0;
    $hash->{READINGS}{temp}{TIME}     = "";
    $hash->{READINGS}{templow}{TIME}  = "";
    $hash->{READINGS}{temphigh}{TIME} = "";
    $hash->{STATE}                    = "Defined";
    Log 3, "OWTEMP: Device $name defined."; 
  }  
  # start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 0);

  # initialize device
  #$ret = OWFS_InitializeDevice($hash);
  #return "OWFS Can't initialize Device $name" if (!defined($ret));
  #$hash->{STATE} = "Initialized";
  
  #-- InternalTimer blocks if init_done is not true
  #my $oid = $init_done;
  $hash->{STATE} = "Initialized";
  return undef; 
}

#########################################################################################
#
# OWTEMP_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWTEMP_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWTEMP_Define";
  $hash->{UndefFn} = "OWTEMP_Undef";
  $hash->{GetFn}   = "OWTEMP_Get";
  $hash->{SetFn}   = "OWTEMP_Set";
    #offset = a temperature offset added to the temperature reading 
  $hash->{AttrList}= "IODev do_not_notify:0,1 showtime:0,1 model:DS18S20 loglevel:0,1,2,3,4,5 ".
                       "offset ";
  }
  
########################################################################################
#
# OWTEMP_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWTEMP_Get($@) {
  my ($hash, @a) = @_;
  my $name  = $hash->{NAME};
  my $ret;

  #-- check argument
  return "OWTEMP: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));
  #-- check syntax
  return "OWTEMP: Get argument is missing @a"
    if(int(@a) != 2);

  # define vars
  my $reading = $a[1];
  my $value = undef;

  # get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$a[0] $reading => $value";
  } 

  #-- Get other values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
   #-- OWX interface
  if( $interface eq "OWX" ){
    #-- not different from getting all values ..
    $ret = OWXTEMP_GetValues($hash);
  #-- OWFS interface
  }elsif( $interface eq "OWFS" ){
    $ret = OWFSTEMP_GetValues($hash);
  #-- Unknown interface
  }else{
    return "OWTEMP: Get with wrong IODev type $interface";
  }
  
  #-- process results
  my $tn = TimeNow();
  
  #-- correct for proper offset
  $owg_temp += $attr{$name}{offset} if ($attr{$name}{offset} );
  #-- Test for alarm condition
  if( ($owg_temp <= $owg_tl) | ($owg_temp >= $owg_th) ){
    $hash->{STATE} = "Alarmed";
  } else {
    $hash->{STATE} = "Normal";
  }
  
  #-- put into READINGS
  $hash->{READINGS}{temp}{VAL}      = $owg_temp;
  $hash->{READINGS}{temp}{TIME}     = $tn;
  $hash->{READINGS}{templow}{VAL}   = $owg_tl;
  $hash->{READINGS}{templow}{TIME}  = $tn;
  $hash->{READINGS}{temphigh}{VAL}  = $owg_th;
  $hash->{READINGS}{temphigh}{TIME} = $tn;
  
  #-- return the special reading
  if(defined($hash->{READINGS}{$reading})) {
    $value = $hash->{READINGS}{$reading}{VAL};
  }
 if(!defined($value)) {
    Log GetLogLevel($name,4), "OWTEMP: Can't get value for $name.$reading";
    return "OWTEMP: Can't get value for $name.$reading";
  }
  return "OWTEMP: $name.$reading => $value";
}

#######################################################################################
#
# OWTEMP_GetUpdate - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWTEMP_GetUpdate($@) {
  my $hash  = shift;
  
  my $name  = $hash->{NAME};
  my $model = $hash->{OW_MODEL};
  my $owx_dev  = $hash->{ROM_ID};
    my $now     = TimeNow();
  my $value   = "";
  my $temp    = "";
  my $ret     = "";
  my $count   = 0;
  
  #-- define warnings
  my $warn        = "none";
  $hash->{ALARM}  = "0";

  #-- restart timer for updates
  #if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(time()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 1);
  #}

  # set new state
  #($temp,undef) = split(" ",$hash->{READINGS}{temperature}{VAL});
  #$warn = $hash->{READINGS}{warnings}{VAL};
  #$hash->{STATE} = "T: $temp  W: $warn";

  my $interface= $hash->{IODev}->{TYPE};
  #-- real sensor
  if($hash->{OW_ID} ne "none") {
    #-- Get values according to interface type
    my $interface= $hash->{IODev}->{TYPE};
    if( $interface eq "OWX" ){
      $ret = OWXTEMP_GetValues($hash);
    }elsif( $interface eq "OWFS" ){
      $ret = OWFSTEMP_GetValues($hash);
    }else{
      return "OWTEMP: GetUpdate with wrong IODev type $interface";
    }
  #-- dummy sensor
  } else {
    $owg_temp = sprintf("%.4f",rand(85));
    $dummy{temperature} = $owg_temp;
    $dummy{present}     = "1";
    $hash->{PRESENT}    = 1;
  }
  
  #-- process results
  my $tn = TimeNow();
  
  #-- correct for proper offset
  $owg_temp += $attr{$name}{offset} if ($attr{$name}{offset} );
  #-- Test for alarm condition
  if( ($owg_temp <= $owg_tl) | ($owg_temp >= $owg_th) ){
    $hash->{STATE} = "Alarmed";
  } else {
    $hash->{STATE} = "Normal";
  }
  
  #-- put into READINGS
  $hash->{READINGS}{temp}{VAL}      = $owg_temp;
  $hash->{READINGS}{temp}{TIME}     = $tn;
  $hash->{READINGS}{templow}{VAL}   = $owg_tl;
  $hash->{READINGS}{templow}{TIME}  = $tn;
  $hash->{READINGS}{temphigh}{VAL}  = $owg_th;
  $hash->{READINGS}{temphigh}{TIME} = $tn;
  
  #--logging
  my $rv = sprintf "temp: %3.1f templow: %3.0f temphigh: %3.0f",$owg_temp,$owg_tl,$owg_th;
  Log 5, $rv;
  $hash->{CHANGED}[0] = $rv;
  DoTrigger($name, undef);
  
  return undef;
}

#######################################################################################
#
# OWTEMP_Set - Set values for one device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################

sub OWTEMP_Set($@) {
  my ($hash, @a) = @_;
  my $name  = $hash->{NAME};
  my $model = $hash->{OW_MODEL};
  my $path  = "10.".$hash->{OW_ID};

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a == 2);
  #-- check syntax
  return "OWTEMP: Set needs one parameter"
    if(int(@a) != 3);
  #-- check argument
  return "OWTEMP: Set with unknown argument $a[1], choose one of ".join(",", sort keys %sets)
      if(!defined($sets{$a[1]}));
      
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  my $ret   = undef;

  #-- set warnings
  if($key eq "templow" || $key eq "temphigh") {
    # check range
    return "OWTEMP: Set with wrong temperature value, range is  -55°C - 125°C"
      if(int($value) < -55 || int($value) > 125);
  }

 #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWTEMP: Set with too short time value, interval must be > 10"
      if(int($value) < 10);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWTEMP_GetUpdate", $hash, 1);
    return undef;
  }

  #-- set other values depending on interface type
  Log 4, "OWTEMP: Set $hash->{NAME} $key $value";
  
  my $interface= $hash->{IODev}->{TYPE};
  #-- real sensor
  if($hash->{OW_ID} ne "none") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXTEMP_SetValues($hash,@a);
      return $ret
        if(defined($ret));
    #-- OWFS interface
    }elsif( $interface eq "OWFS" ){
      $ret = OWFSTEMP_SetValues($hash,@a);
      return $ret
        if(defined($ret));
    } else {
    return "OWTEMP: Set with wrong IODev type $interface";
    }
  #-- dummy sensor
  } else {
      $dummy{$key} = $value;
  }
  
  #-- process results
  my $tn = TimeNow();
  
  #-- correct for proper offset
  $owg_temp += $attr{$name}{offset} if ($attr{$name}{offset} );
  #-- Test for alarm condition
  if( ($owg_temp <= $owg_tl) | ($owg_temp >= $owg_th) ){
    $hash->{STATE} = "Alarmed";
  } else {
    $hash->{STATE} = "Normal";
  }
  
  #-- put into READINGS
  $hash->{READINGS}{temp}{VAL}      = $owg_temp;
  $hash->{READINGS}{temp}{TIME}     = $tn;
  $hash->{READINGS}{templow}{VAL}   = $owg_tl;
  $hash->{READINGS}{templow}{TIME}  = $tn;
  $hash->{READINGS}{temphigh}{VAL}  = $owg_th;
  $hash->{READINGS}{temphigh}{TIME} = $tn;
  
  return undef;
}

########################################################################################
#
# OWTEMP_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed, name
#
########################################################################################

sub OWTEMP_Undef ($$) {
  my ($hash, $name) = @_;
  delete($modules{OWTEMP}{defptr}{$hash->{CODE}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSTEMP
#
########################################################################################
#
# OWFSTEMP_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSTEMP_GetValues($)
{
  my ($hash) = @_;

  my $ret = OW::get("/uncached/10.".$hash->{OW_ID}."/temperature");
  if( defined($ret) ) {
    $hash->{PRESENT} = 1;
    $owg_temp = $ret;
    $owg_th   = OW::get("/uncached/10.".$hash->{OW_ID}."/temphigh");
    $owg_tl   = OW::get("/uncached/10.".$hash->{OW_ID}."/templow");
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
# OWFSTEMP_SetValues - Implements SetFn function
# 
# Parameter hash = hash of the device addressed here, a = argument array
#
########################################################################################

sub OWFSTEMP_SetValues($@) {
  my ($hash, @a) = @_;
  
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  
  return OW::put("10.".$hash->{OW_ID}."/$key",$value);
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXTEMP
#
########################################################################################
#
# OWXTEMP_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXTEMP_GetValues($) {

  my ($hash) = @_;
  
  #-- For now, switch of temperature conversion command
  my $con=0;
  
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

  #-- if the conversion has not been called before 
  if( $con==1 ){
    OWX_Reset($master);
    #-- issue the match ROM command \x55 and the start conversion command
    my $select=sprintf("\x55%c%c%c%c%c%c%c%c\x44",@owx_ROM_ID); 
    if( OWX_Block($master,$select) eq 0 ){
      return "OWXTEMP: Device $owx_dev not accessible";
    } 
    #-- conversion needs some 950 ms
    sleep(1);
  }

  #-- NOW ask the specific device 
  OWX_Reset($master);
  #-- issue the match ROM command \x55 and the read scratchpad command \xBE
  my $select=sprintf("\x55%c%c%c%c%c%c%c%c\xBE\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
     @owx_ROM_ID); 
     
  my $res=OWX_Block($master,$select);
  #-- process results
  if( $res eq 0 ){
    return "OWXTEMP: Device $owx_dev not accessible in 2nd step"; 
  }
  #-- process results
  my  @data=split(//,$res);
  if (@data == 19){
    my $count_remain = ord($data[16]);
    my $count_perc   = ord($data[17]);
    my $delta        = -0.25 + ($count_perc - $count_remain)/$count_perc;
  
    #-- 2's complement form = signed bytes
    if( $data[11] eq "\x00" ){
      $owg_temp = int(ord($data[10])/2) + $delta;
    } else {
      $owg_temp = 128-(int(ord($data[10])/2) + $delta);
    }
    $owg_th = ord($data[12]) > 127 ? 128-ord($data[12]) : ord($data[12]);
    $owg_tl = ord($data[13]) > 127 ? 128-ord($data[13]) : ord($data[13]);
   
    return undef;
  } else {
    return "OWXTEMP: Device $owx_dev returns wrong number @data of bytes";
  }
}

#######################################################################################
#
# OWXTEMP_SetValues - Implements SetFn function
# 
# Parameter hash = hash of the device addressed here, a = argument array
#
########################################################################################

sub OWXTEMP_SetValues($@) {
  my ($hash, @a) = @_;
  
  my $name = $hash->{NAME};
 
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
  
  # define vars
  my $key   = $a[1];
  my $value = $a[2];
  
  #-- get the old values
  $owg_temp = $hash->{READINGS}{temp}{VAL};
  $owg_tl   = $hash->{READINGS}{templow}{VAL};
  $owg_th   = $hash->{READINGS}{temphigh}{VAL};
  
  $owg_tl = int($value) if( $key eq "templow" );
  $owg_th = int($value) if( $key eq "temphigh" );

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
  
  my $select=sprintf("\x55%c%c%c%c%c%c%c%c\x4E%c%c\x48",@owx_ROM_ID,$thp,$tlp); 
  my $res=OWX_Block($master,$select);

  if( $res eq 0 ){
    return "OWXTEMP: Device $owx_dev not accessible"; 
  } 
  
  #-- issue the match ROM command \x55 and the copy scratchpad command \x48
  #$select=sprintf("\x55%c%c%c%c%c%c%c%c",@owx_ROM_ID); 
  #$res=OWX_Block($hash,$select);
  #$res=OWX_WriteBytePower($hash,"\x48");

  #if( $res eq 0 ){
  #  Log 3, "OWXTEMP_SetTemp: Device $romid not accessible in the second step"; 
  #  return 0;
  #} 
  
  DoTrigger($name, undef) if($init_done);
  return undef;
}



1;
