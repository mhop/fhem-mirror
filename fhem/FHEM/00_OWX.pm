########################################################################################
#
# FHEM module (Next Generation) to commmunicate with 1-Wire bus devices
# * via an active DS2480/DS9097U bus master interface attached to an USB port
# * via an active DS2480 bus master interface attached to a TCP/IP-UART device
# * via a network-attached CUNO
# * via a COC attached to a Raspberry Pi
# * via an Arduino running OneWireFirmata
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
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
use Time::HiRes qw(gettimeofday);
use Data::Dumper qw(Dumper);
use DevIo;

#-- unfortunately some things OS-dependent
my $SER_regexp;
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
  $SER_regexp= "com";
} else {
  require Device::SerialPort;
  $SER_regexp= "/dev/";
} 

sub Log3($$$);

use vars qw{%owg_family %gets %sets $owx_version $owx_debug};
# 1-Wire devices 
# http://owfs.sourceforge.net/family.html
my %owg_family = (
  "01"  => ["DS2401/DS2411/DS1990A","OWID DS2401"],
  "05"  => ["DS2405","OWID DS2405"],
  "09"  => ["DS2502","OWID DS2502"],
  "10"  => ["DS18S20/DS1920","OWTHERM DS1820"],
  "12"  => ["DS2406/DS2507","OWSWITCH DS2406"],
  "1B"  => ["DS2436","OWID 1B"],
  "1D"  => ["DS2423","OWCOUNT DS2423"],
  "20"  => ["DS2450","OWAD DS2450"],
  "22"  => ["DS1822","OWTHERM DS1822"],
  "23"  => ["DS2433","OWID 23"],
  "24"  => ["DS2415/DS1904","OWID 24"],
  "26"  => ["DS2438","OWMULTI DS2438"],
  "27"  => ["DS2417","OWID 27"],
  "28"  => ["DS18B20","OWTHERM DS18B20"],
  "29"  => ["DS2408","OWSWITCH DS2408"],
  "2C"  => ["DS2890","OWVAR DS2890"],
  "3A"  => ["DS2413","OWSWITCH DS2413"],
  "3B"  => ["DS1825","OWID 3B"],
  "7E"  => ["OW-ENV","OWID 7E"], #Environmental sensor
  "81"  => ["DS1420","OWID 81"],
  "A6"  => ["DS2438","OWMULTI DS2438a"],
  "FF"  => ["LCD","OWLCD"]
);

#-- These we may get on request
my %gets = (
   "alarms"  => "A",
   "devices" => "D",
   "version" => "V",
   "qstatus" => "P"
);

#-- These occur in a pulldown menu as settable values for the bus master 
#   (expert mode: all, standard mode: only reopen)
my %sets = (
   "close"        => "c", 
   "open"         => "O", 
   "reopen"       => "R",
   "discover"     => "C",
   "detect"       => "T",
   "disconnected" => "D",
   "process"      => "P"
);

#-- some globals needed for the 1-Wire module
$owx_version="7.21";

#-- debugging now verbosity, this is just for backward compatibility
$owx_debug=0;

########################################################################################
#
# The following subroutines are independent of the bus interface
#
########################################################################################
#
# OWX_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWX_Initialize ($) {
  my ($hash) = @_;

  $hash->{Clients} = ":OWAD:OWCOUNT:OWID:OWLCD:OWMULTI:OWSWITCH:OWTHERM:OWVAR:";
  $hash->{WriteFn} = "OWX_Write";
  $hash->{ReadFn}  = "OWX_Read";
  $hash->{ReadyFn} = "OWX_Ready";

  $hash->{DefFn}   = "OWX_Define";
  $hash->{UndefFn} = "OWX_Undef";
  $hash->{GetFn}   = "OWX_Get";
  $hash->{SetFn}   = "OWX_Set";
  $hash->{AttrFn}  = "OWX_Attr";
  $hash->{AttrList}= "asynchronous:0,1 dokick:0,1 ".
                     "interval timeout opendelay expert:0_def,1_detail ".
                     "IODev ".
                     $readingFnAttributes;    
}

########################################################################################
#
# OWX_Define - Implements Define function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWX_Define ($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  my $hwdevice;
  my $ret;
  
  #-- check syntax
  if(int(@a) < 3){
    return "OWX: Syntax error - must be define <name> OWX <serial-device>|<ip-address>[:<port>]|<i2c-bus>:<i2c-addr>|<cuno/coc-device>|<firmata-device>:<firmata-pin>"
  }

  Log3 $hash->{NAME},2,"OWX: Warning - Some parameter(s) ignored, must be define <name> OWX <serial-device>|<ip-address>[:<port>]|<i2c-bus>:<i2c-addr>|<cuno/coc-device>|<firmata-device>:<firmata-pin>"
    if( int(@a)>3 );
  my $dev = $a[2];
  
  #-- Dummy 1-Wire ROM identifier, empty device lists
  $hash->{ROM_ID}      = "FF";
  $hash->{DEVS}        = ();
  $hash->{DEVHASH}{"$a[0]"}="Busmaster"; 
  $hash->{INITDONE}    = 0;
  #XXX
  $hash->{PARTIAL} = "";
  delete $hash->{ALARMDEVS};
  delete $hash->{followAlarms};
  delete $hash->{version};

  #-- Clear from leftovers of ASYNC
  delete $hash->{ASYNC};
  
  #-- First step - different methods and parameters for setup
  #-- check if we have a serial device attached
  if ($dev =~ m|$SER_regexp|i) {  
    require "$attr{global}{modpath}/FHEM/11_OWX_SER.pm";
    $hwdevice = OWX_SER->new($hash);
    
  #-- check if we have a TCP connection
  }elsif( $dev =~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| ){
    require "$attr{global}{modpath}/FHEM/11_OWX_TCP.pm";
    #$hash->{Protocol} = "telnet"
    $hwdevice = OWX_TCP->new($hash);
    
  #-- check if we have an i2c interface attached  
  }elsif( $dev =~ m|^\d\:\d\d| ){
    require "$attr{global}{modpath}/FHEM/11_OWX_I2C.pm";
    $hwdevice = OWX_I2C->new($hash);
    
  #-- check if we have a COC/CUNO interface attached  
  }elsif( $defs{$dev} && $defs{$dev}->{VERSION}  && $defs{$dev}->{VERSION} =~ m/CSM|CUNO|CUBE|MapleCUN...(4|5|6|7|C|D|E|F)/ ){
     require "$attr{global}{modpath}/FHEM/11_OWX_CCC.pm";
     $hwdevice = OWX_CCC->new($hash);
    
  #-- check if we are connecting to Arduino (via FRM):
  } elsif ($dev =~ /.*\:\d{1,2}$/) {
  	require "$attr{global}{modpath}/FHEM/11_OWX_FRM.pm";
    $hwdevice = OWX_FRM->new($hash);
    
  } else {
    return "OWX: Define failed, unable to identify interface type $dev for bus ".$hash->{NAME};
  };
  
  #-- Second step: perform low level init of device
  #Log 1,"OWX: Performing define and low level init of bus ".$hash->{NAME};
  $ret = $hwdevice->Define($def);
  
  #-- cancel definition of OWX if failed
  return $ret if $ret;  
  $hash->{OWX} = $hwdevice;
  
  #-- Default settings
  $hash->{interval}     = 300;          # kick every 5 minutes
  $hash->{timeout}      = 2;            # timeout 2 seconds
  $hash->{ALARMED}      = 0;
  $hash->{PRESENT}      = 1;
 
  #-- Third step: perform high level init for 1-Wire Bus in minute or so
  ###
  InternalTimer(time()+60, "OWX_Init", $hash,0);
  
  return undef;
}

########################################################################################
#
# OWX_Alarms - Find devices on the 1-Wire bus, 
#              which have the alarm flag set
#
# Parameter hash = hash of bus master
#
# Return: Message or list of alarmed devices
#
########################################################################################

sub OWX_Alarms ($) {
  my ($hash) = @_;

  my @owx_alarm_names=();
  
  #-- get the interface
  my $name    = $hash->{NAME};
  my $owx     = $hash->{OWX};
  my $devhash = $hash->{DEVHASH};

  foreach my $owx_dev (sort keys %{$devhash}){
   push(@owx_alarm_names,$owx_dev)
    if $defs{$owx_dev}->{ALARM};
  }
  
  my $res = int(@owx_alarm_names);
  if( $res == 0){
    $hash->{ALARMED}=0;
    return "OWX: No alarmed 1-Wire devices found on bus $name";
  } else{  
    $hash->{ALARMED}=$res;
    return "OWX: $res alarmed 1-Wire devices found on bus $name (".join(",",@owx_alarm_names).")";
  }

  ############### THE FOLLOWING IST DEAD CODE, BECAUSE ALARM SEARCH DOES NOT WORK PROPERLY - WHY ?
  if (defined $owx) {
    $res = $owx->Alarms();
  } else {
    #-- interface error
    my $owx_interface = $hash->{INTERFACE};
    if( !(defined($owx_interface))){
      return undef;
    } else {
      return "OWX: Alarms called with unknown interface $owx_interface on bus $name";
    }
  }

  if( $res == 0){
    return "OWX: No alarmed 1-Wire devices found on bus $name";
  }

  #-- walk through all the devices to get their proper fhem names
  foreach my $fhem_dev (sort keys %main::defs) {
    #-- skip if busmaster
    next if( $name eq $main::defs{$fhem_dev}{NAME} );
    #-- all OW types start with OW
    next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW");
    foreach my $owx_dev  (@{$hash->{ALARMDEVS}}) {
      #-- two pieces of the ROM ID found on the bus
      my $owx_rnf = substr($owx_dev,3,12);
      my $owx_f   = substr($owx_dev,0,2);
      my $id_owx  = $owx_f.".".$owx_rnf;
        
      #-- skip if not in alarm list
      if( $owx_dev eq $main::defs{$fhem_dev}{ROM_ID} ){
        $main::defs{$fhem_dev}{STATE} = "Alarmed";
        push(@owx_alarm_names,$main::defs{$fhem_dev}{NAME});
      }
    }
  }
  #-- so far, so good - what do we want to do with this ?
  return "OWX: $res alarmed 1-Wire devices found on bus $name (".join(",",@owx_alarm_names).")";
}  

#######################################################################################
#
# OWX_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWX_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $main::defs{$name};
  my $queue = $hash->{QUEUE};
  my $ret;
  
  if ( $do eq "set") {
  	ARGUMENT_HANDLER: {
      $key eq "asynchronous" and do {
        $hash->{ASYNCHRONOUS} = ($value==1 ? 1 : 0);
        #-- stop queue prcoessing and delete it
        if(!$value){ 
          RemoveInternalTimer ("queue:$name");  
          delete($hash->{QUEUE});
          readingsSingleUpdate($hash,"queue",0,0);
          OWX_Reset($hash);
        }
        last;
      };
      $key eq "timeout" and do {
        $hash->{timeout} = $value;
        last;
      };
      $key eq "opendelay" and do {
        $hash->{opendelay} = $value;
        last;    
      };
      $key eq "dokick" and do {
        $hash->{dokick} = $value;
        last;
      };
      $key eq "interval" and do {
        $hash->{interval} = $value;
        if ($main::init_done) {
          OWX_Kick($hash);
        }
        last;
      }
    }
  }
  return $ret;
}

########################################################################################
#
# OWX_CRC - Check the CRC code of a device address in @owx_ROM_ID
#
# Parameter romid = if not reference to array, return the CRC8 value instead of checking it
#
########################################################################################

my @crc8_table = (
    0, 94,188,226, 97, 63,221,131,194,156,126, 32,163,253, 31, 65,
    157,195, 33,127,252,162, 64, 30, 95, 1,227,189, 62, 96,130,220,
    35,125,159,193, 66, 28,254,160,225,191, 93, 3,128,222, 60, 98,
    190,224, 2, 92,223,129, 99, 61,124, 34,192,158, 29, 67,161,255,
    70, 24,250,164, 39,121,155,197,132,218, 56,102,229,187, 89, 7,
    219,133,103, 57,186,228, 6, 88, 25, 71,165,251,120, 38,196,154,
    101, 59,217,135, 4, 90,184,230,167,249, 27, 69,198,152,122, 36,
    248,166, 68, 26,153,199, 37,123, 58,100,134,216, 91, 5,231,185,
    140,210, 48,110,237,179, 81, 15, 78, 16,242,172, 47,113,147,205,
    17, 79,173,243,112, 46,204,146,211,141,111, 49,178,236, 14, 80,
    175,241, 19, 77,206,144,114, 44,109, 51,209,143, 12, 82,176,238,
    50,108,142,208, 83, 13,239,177,240,174, 76, 18,145,207, 45,115,
    202,148,118, 40,171,245, 23, 73, 8, 86,180,234,105, 55,213,139,
    87, 9,235,181, 54,104,138,212,149,203, 41,119,244,170, 72, 22,
    233,183, 85, 11,136,214, 52,106, 43,117,151,201, 74, 20,246,168,
    116, 42,200,150, 21, 75,169,247,182,232, 10, 84,215,137,107, 53);


sub OWX_CRC ($) {
  my ($romid) = @_;
  my $crc8=0;  

  my @owx_ROM_ID;
  if( ref ($romid) eq 'ARRAY' ){
  	@owx_ROM_ID = @$romid;  
    for(my $i=0; $i<8; $i++){
      $crc8 = $crc8_table[ $crc8 ^ $owx_ROM_ID[$i] ];
    }  
    return $crc8;
  } else {
    #-- from search string to byte id
    $romid=~s/\.//g;
    for(my $i=0;$i<8;$i++){
      $owx_ROM_ID[$i]=hex(substr($romid,2*$i,2));
    }
    for(my $i=0; $i<7; $i++){
      $crc8 = $crc8_table[ $crc8 ^ $owx_ROM_ID[$i] ];
    }  
    return $crc8;
  }
}  

########################################################################################
#
# OWX_CRC8 - Check the CRC8 code of an a byte string
#
# Parameter string, crc. 
# If crc is defined, make a comparison, otherwise output crc8
#
########################################################################################

sub OWX_CRC8 ($$) {
  my ($string,$crc) = @_;
  my $crc8=0;  
  my @strhex;

  for(my $i=0; $i<length($string); $i++){
    $strhex[$i]=ord(substr($string,$i,1));
    $crc8 = $crc8_table[ $crc8 ^ $strhex[$i] ];
  }
   
  if( defined($crc) ){
    my $crcx = ord($crc);
    if ( $crcx == $crc8 ){
      return 1;
    }else{
      return 0;
    }
  }else{
    return sprintf("%#2x", $crc8);
  }
}  

########################################################################################
#
# OWX_CRC16 - Calculate the CRC16 code of a string 
#
#  TODO UNFINISHED CODE
#
# Parameter crc - previous CRC code, c next character
#
########################################################################################

my @crc16_table = (
0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040
);

sub OWX_CRC16 ($$$) {
  my ($string,$crclo,$crchi) = @_;
  my $crc16=0;  
  my @strhex;
  
  #Log3 $name, 1,"CRC16 calculated for string of length ".length($string);

  for(my $i=0; $i<length($string); $i++){
    $strhex[$i]=ord(substr($string,$i,1));
    $crc16 = $crc16_table[ ($crc16 ^ $strhex[$i]) & 0xFF ] ^ ($crc16 >> 8);
  }
   
  if( defined($crclo) & defined($crchi) ){
    my $crc = (255-ord($crclo))+256*(255-ord($crchi));
    if ($crc == $crc16 ){
      return 1;
    }else{
      return 0;
    }
  }else{
    return $crc16;
  }
}  

########################################################################################
#
# OWX_Discover - Discover devices on the 1-Wire bus, 
#                autocreate devices if not already present
#
# Parameter hash = hash of bus master
#
# Return: List of devices in table format or undef
#
########################################################################################

sub OWX_Discover ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $res;
  my $ret= "";
  my ($chip,$acstring,$acname,$exname);
  my $ow_dev;
  my $owx_rnf;
  my $owx_f;
  my $owx_crc;
  my $id_owx;
  my $match;
  
  #-- get the interface - this should be the hardware device ???
  my $owx = $hash->{OWX};
  my $owx1 = $hash->{INTERFACE};
  my $owx2 = $hash->{DeviceName};
  my $owx3  = $hash->{HWDEVICE};
 
  my @owx_names   =();
  $hash->{DEVHASH}=();
  $hash->{DEVHASH}{"$name"} = "Busmaster";

  #-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
  if (defined $owx) {
	$res = $owx->Discover();
  } else {
  	my $owx_interface = $hash->{INTERFACE};
    if( !defined($owx_interface) ) {
      return undef;
    } else {
      Log3 $name, 1,"OWX_Discover on bus $name called with unknown interface $owx_interface";
      return undef;
    } 
  }

  if (defined $res and (ref($res) eq "ARRAY")) {
  	$hash->{DEVS} = $res;
  }
  
  #-- Go through all devices found on this bus
  foreach my $owx_dev  (@{$hash->{DEVS}}) {
    #-- ignore those which do not have the proper pattern
    if( !($owx_dev =~ m/[0-9A-F]{2}\.[0-9A-F]{12}\.[0-9A-F]{2}/) ){
      Log3 $name, 3,"OWX_Discover found invalid 1-Wire device ID $owx_dev on bus $name, ignoring it";
      next;
    }
    
    #-- three pieces of the ROM ID found on the bus
    $owx_rnf = substr($owx_dev,3,12);
    $owx_f   = substr($owx_dev,0,2);
    $owx_crc = substr($owx_dev,15,3);
    $id_owx  = $owx_f.".".$owx_rnf;
      
    $match = 0;
    
    #-- Check against all existing devices  
    foreach my $fhem_dev (sort keys %main::defs) { 
      #-- skip if busmaster
      # next if( $hash->{NAME} eq $main::defs{$fhem_dev}{NAME} );
      #-- all OW types start with OW
      next if( !defined($main::defs{$fhem_dev}{TYPE}));
      next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW"); 
      my $id_fhem = substr($main::defs{$fhem_dev}{ROM_ID},0,15);
      #-- skip interface device
      next if( length($id_fhem) != 15 );
      #-- yes, family id and ROM id are the same
      if( $id_fhem eq $id_owx ) {
        $exname=$main::defs{$fhem_dev}{NAME};
        push(@owx_names,$exname);
        #-- replace the ROM ID by the proper value including CRC
        $main::defs{$fhem_dev}{ROM_ID}   = $owx_dev;
        $main::defs{$fhem_dev}{PRESENT}  = 1;    
        $main::defs{$fhem_dev}{ERRCOUNT} = 0; 
        #-- add to DEVHASH
        $hash->{DEVHASH}{"$exname"}=$owx_dev;
        $match = 1;
        last;
      #-- no, only duplicate ROMID
      }elsif( substr($id_fhem,3,12) eq substr($id_owx,3,12) ) {
        Log3 $name, 1, "OWX_Discover: Warning, $fhem_dev on bus $name is defined with duplicate ROM ID ";
      }
    }
 
    #-- Determine the device type
    if(exists $owg_family{$owx_f}) {
      $chip     = $owg_family{$owx_f}[0];
      $acstring = $owg_family{$owx_f}[1];
    }else{  
      Log3 $name, 2, "OWX_Discover: Device with unknown family code '$owx_f' found on bus $name";
      #-- All unknown families are ID only
      $chip     = "unknown";
      $acstring = "OWID $owx_f";  
    }
    #Log3 $name, 1,"###\nfor the following device match=$match, chip=$chip name=$name acstring=$acstring";
    #-- device exists
    if( $match==1 ){
      $ret .= sprintf("%s.%s      %-14s %s\n", $owx_f,$owx_rnf, $chip, $exname);
    #-- device unknown, autocreate
    }else{
    #-- example code for checking global autocreate - do we want this ?
    #foreach my $d (keys %defs) {
    #next if($defs{$d}{TYPE} ne "autocreate");
    #return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
      $acname = sprintf "OWX_%s_%s",$owx_f,$owx_rnf;
      #Log3 $name, 1, "to define $acname $acstring $owx_rnf";
      $res = CommandDefine(undef,"$acname $acstring $owx_rnf");
      if($res) {
        $ret.= "OWX_Discover: Error autocreating device with $acname $acstring $owx_rnf: $res\n";
      } else{
        select(undef,undef,undef,0.01);
        push(@owx_names,$acname);
        $main::defs{$acname}{PRESENT}=1;
        #-- THIS IODev, default room (model is set in the device module)
        CommandAttr (undef,"$acname IODev $hash->{NAME}"); 
        CommandAttr (undef,"$acname room OWX"); 
        #-- replace the ROM ID by the proper value 
        $main::defs{$acname}{ROM_ID}=$owx_dev;
        #-- add to DEVHASH
        $hash->{DEVHASH}{"$acname"}=$owx_dev;
        $ret .= sprintf("%s.%s      %-10s %s\n", $owx_f,$owx_rnf, $chip, $acname);
      } 
    }
  }

  #-- final step: Undefine all 1-Wire devices which 
  #   are autocreated and
  #   not discovered on this bus 
  #   but have this IODev
  foreach my $fhem_dev (sort keys %main::defs) {
    #-- skip if malformed device
    #next if( !defined($main::defs{$fhem_dev}{NAME}) );
    #-- all OW types start with OW, but safeguard against deletion of other devices
    #next if( !defined($main::defs{$fhem_dev}{TYPE}));
    next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWX");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWFS");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWSERVER");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWDEVICE");
    #-- restrict to autocreated devices
    next if( $main::defs{$fhem_dev}{NAME} !~ m/OWX_[0-9a-fA-F]{2}_/);
    #-- skip if the device is present.
    next if( $main::defs{$fhem_dev}{PRESENT} == 1);
    #-- skip if different IODev, but only if other IODev exists
    if ( $main::defs{$fhem_dev}{IODev} ){
      next if( $main::defs{$fhem_dev}{IODev}{NAME} ne $hash->{NAME} );
    }
    Log3 $name, 1, "OWX_Discover: Device $main::defs{$fhem_dev}{NAME} of type $main::defs{$fhem_dev}{TYPE} is unused, consider deletion !";
  }
  #-- Log the discovered devices
  Log3 $name, 1, "OWX_Discover: 1-Wire devices found on bus $name (".join(",",@owx_names).")";
  #-- tabular view as return value
  return "OWX_Discover: 1-Wire devices found on bus $name \n".$ret;
  
}   

########################################################################################
#
# OWX_Get - Implements GetFn function 
#
#  Parameter hash = hash of the bus master a = argument array
#
########################################################################################

sub OWX_Get($@) {
  my ($hash, @a) = @_;
  return "OWX: Get needs exactly one parameter" if(@a != 2);

  my $name     = $hash->{NAME};
  my $owx_dev  = $hash->{ROM_ID};

  if( $a[1] eq "alarms") {
    my $res = OWX_Alarms($hash);
    #-- process result
    return $res
    
  } elsif( $a[1] eq "devices") {
    my $res = OWX_Discover($hash);
    #-- process result
    return $res
    
  } elsif( $a[1] eq "version") {
    return $owx_version;
    
  #-- expert mode
  } elsif( $a[1] eq "qstatus") {
    my $qlen  = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    my $state =  $hash->{STATE};
    my $dev   =  $hash->{DeviceName};
    my $busy  = ($hash->{BUSY})? "BUSY" : "NOT BUSY";
    my $block = ($hash->{BLOCK})? "BLOCKED" : "NOT BLOCKED";
    $hash->{BUSY} = 1;
    my $res = "OWX: Queue $name: => dev=$dev length=$qlen, state=$state, $busy, $block\n";
    
    foreach my $diapoint (@{$hash->{QUEUE}}) {  
      $res .= "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status}."\n";
    }
    return $res;

    
  } else {
    return "OWX_Get with unknown argument $a[1], choose one of ".
    ( (AttrVal($name,"expert","") eq "1_detail") ? join(":noArg ", sort keys %gets).":noArg" : "alarms devices version"); 
  }
}

#######################################################################################
# 
# OWX_Init - High Level Init of 1-Wire Bus
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Init ($) {
  my ($hash)=@_;
  
  #-- get the interface
  my $owx = $hash->{OWX};
  my $name= $hash->{NAME};
  
  if( defined($attr{$name}{"asynchronous"}) && ($attr{$name}{"asynchronous"}==1) ){
    $hash->{ASYNCHRONOUS} = 1;
  }else{
    $hash->{ASYNCHRONOUS} = 0;
  }

  return "OWX_Init finds a disconnected interface"
    if($hash->{STATE} eq "disconnected");
   
  Log3 $name,1,"OWX_Init called for bus $name with interface state ".$hash->{STATE}.", now going for detect";
  
  if ($owx) {
  	#-- Fourth step: see, if a bus interface is detected
  	if (!($owx->Detect())) {
      $hash->{PRESENT} = 0;
      #$init_done = 1; 
      Log3 $name,4,"OWX_Init: Detection failed";
      return "OWX_Init Detection failed";
    }
  } else {
    #-- interface error
  	my $owx_interface = $hash->{INTERFACE};
	if( !(defined($owx_interface))){
      return "OWX_Init called with undefined interface";
	} else {
      return "OWX_Init called with unknown interface $owx_interface";
	}
  }
  
  #-- Fifth step: discovering devices on the bus
  OWX_Discover($hash);
  $hash->{INITDONE} = 1;
  #-- Intiate first alarm detection and eventually conversion 
  OWX_Kick($hash);

  return undef;
}

########################################################################################
#
# OWX_Kick - Initiate some processes in all devices
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : Not OK
#
########################################################################################

sub OWX_Kick($) {
  my($hash)         = @_;

  #-- Call us in n seconds again.
  InternalTimer(gettimeofday()+ $hash->{interval}, "OWX_Kick", $hash,1);
   
  #-- Only if we have the dokick attribute set to 1
  if( defined($attr{$hash->{NAME}}{dokick}) &&  ($attr{$hash->{NAME}}{dokick} eq "1") ){
    my $name          = $hash->{NAME};
    my $interface     = $hash->{TYPE};
    my $asynchronous  = $hash->{ASYNCHRONOUS};
    #-- issue the skip ROM command \xCC followed by start conversion command \x44 
    my $cmd  = "\xCC\x44"; 
    #-- OWX interface
    if( $interface eq "OWX" ){
      #-- OLD OWX interface
      if( !$asynchronous ){
        OWX_Reset($hash);
        OWX_Complex($hash,"","\xCC\x44",0);
      #-- NEW OWX interface
      }else{
        ####        master slave  context proc  owx_dev   data  crcpart  numread  startread callback   delay
        OWX_Qomplex($hash, undef, "kick", 1,    "",       $cmd, 0,       -10,       undef,        undef,     undef)
      }
    }
  }
  return 1;
} 

########################################################################################
# 
# OWX_Reset - Reset the 1-Wire bus 
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Reset ($) {
  my ($hash)=@_;
  
  #-- get the interface
  my $owx  = $hash->{OWX};
  my $name = $hash->{NAME};
  my $queue = $hash->{QUEUE};
  
  my $status = (defined( $queue->[0]->{status})) ? $queue->[0]->{status} : "completed";
  
  if (defined $owx) {
    #-- reset only when there is no queue or when the status of the current entry is completed
    if( $status eq "completed" ){
	  return $owx->Reset()
	} else {
	  #Log 1,"==================> Reset attempted on waiting interface";
      my $i = 1;
      while ( (my @call_details = (caller($i++))) ){
        Log 1,$call_details[1].":".$call_details[2]." in function ".$call_details[3];
      }
      return 0;
    }
	 
  } else {  	
    #-- interface error
    my $owx_interface = $hash->{INTERFACE};
    if( !(defined($owx_interface))){
      return 0;
    } else {
      Log3 $name, 3,"OWX: Reset called with unknown interface $owx_interface on bus $name";
      return 0;
    }
  }
}

#######################################################################################
#
# OWX_Read - Callback from FHEM main loop - read from the bus 
#
# Parameter hash = hash of bus master
#
########################################################################################

sub OWX_Read(@) {
  my ($hash) = @_;   
  #-- must not be used when acting synchronously
  return undef 
    if( !$hash->{ASYNCHRONOUS} );
  
  my ($buffer, $buffer2, $qlen, $res, $ret);
  
  #-- master data
  my $owx     = $hash->{OWX};
  my $name    = $hash->{NAME};
  my $queue   = $hash->{QUEUE};
  my $query   = $queue->[0];
  my $staexp  = $query->{startread};
  my $sldev   = $query->{hash}->{NAME};
  my $slcont  = $query->{context};
  
  my $devlevel = (defined($attr{$name}{verbose})) ? $attr{$name}{verbose} : 0;
  my $qdebug   = ( ($devlevel > 3) || ($attr{global}{verbose}>3) ) ? 1 : 0;

  #--safeguard: really called from queue ?
  #if( !defined($sldev) ){
    #Log 1,"OWX_Read: Erroneous call from somewhere in FHEM ???";
    #my $i = 1;
    #Log 1, "=============> Empty call of OWX_Read Stack Trace:";
    #while ( (my @call_details = (caller($i++))) ){
    #   Log 1,$call_details[1].":".$call_details[2]." in function ".$call_details[3];
    #}
    #return;
  #}
  
  #-- expected length
  my $numget;
  my $numexp  = $query->{numread};
  $numexp     = 0
    if( (!$numexp) || ($numexp eq "") );
  
  #-- actual read operation  
  $buffer = $owx->Read($numexp);
  #-- actual length
  $numget  = length($buffer)-10;
  
  #-- partial reception
  if( $numget < $numexp ){
    #-- empty device buffer
    if( length($hash->{PARTIAL}) == 0 ){
      $hash->{PARTIAL} = $buffer;
      return undef;
    #-- some data present already
    }else{
      $buffer = $hash->{PARTIAL}.$buffer;
      $numget = length($buffer)-10;
      #-- NOT done with this return to main loop
      if( $numget<$numexp ){
        $hash->{PARTIAL} = $buffer;
        return undef;
      }
    }
  }
  
  #-- IF WE ARE HERE, WE SHOULD HAVE ALL THE BYTES
  $hash->{PARTIAL} = "";
  $queue->[0]->{status} = "completed";
  #Log3 $name, 1, "OWX_Read:    queue $name context ".$queue->[0]->{context}." received $numget bytes, expected $numexp. status completed, processing entry";
  
  #-- if necessary perform a reset after the full read operation
  if( ($queue->[0]->{proc} & 1)==1 ){
    #select(undef,undef,undef,0.01);
    $owx->Reset()
  };
       
  #-- slave data
  my $slave    = $query->{hash};
  my $context  = $query->{context};
  my $proc     = (defined($query->{proc}))?($query->{proc}):1;
  my $owx_dev  = $query->{owx_dev};
  my $crcpart  = $query->{crcpart};  #-- needed for CRC check
     
  #-- successful completion, take off the queue
  shift(@{$queue});    
  $qlen  = @{$queue};
  #Log3 $name, 4, "OWX_Read: $name queue contains $qlen entries after removal of active entry";
  
  #-- calling callback
  if( $query->{callback} ){
    #Log3 $name, 1, "OWX_Read: $name received $numget bytes, expected $numexp. Now calling callback for context $context";
    $ret =  $query->{callback}($slave,$context, $proc, $owx_dev,  $crcpart,  $numexp,  substr($buffer,$staexp,$numexp));
  }else{
    #Log3 $name, 1, "OWX_Read: $name received $numget bytes, expected $numexp. No callback defined for context $context";
  }
    
  #-- we are done - but maybe still have to do a synchronous job
  if( $hash->{BLOCK} ){
    my $ret2 = $hash->{BLOCKCALL}->();
  };   
  #-- reset busy flag
  $hash->{BUSY} = 0;        
  
  #-- more items in queue -> schedule next process   
  #if( $name eq "OWX_TEST"){ 
  #    Log3 $name, 1,"----------------------------------------------"; 
  #    Log3 $name,1, "   queue $name contains ".scalar(@{$hash->{QUEUE}})." entries after read";
  #    foreach my $diapoint (@{$hash->{QUEUE}}) {  
  #      Log3 $name, 1, "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status};
  #    }
  #    Log3 $name, 1,"----------------------------------------------"; 
  #} 
  my $now = gettimeofday();
  if( ($qlen > 0)  ) {          
    InternalTimer($now+0.01, "OWX_PrQueue", "queue:$name", 0);
  }
  return  $ret;
}

#######################################################################################
# 
# OWX_Ready
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Ready($) {
  my ($hash)=@_;
  
  #-- relevant for Windows/USB only
  if ( $hash->{STATE} ne "disconnected" ){
	if(defined($hash->{USBDev})) {
		my $po = $hash->{USBDev};
		my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
		return ( $InBytes > 0 );
	}
	return undef;	
  }
		
  #-- get the interface
  my $owx  = $hash->{OWX};
  my $name = $hash->{NAME};
  my $time     = time();
  
  #-- skip this if delay time is not yet over
  if($hash->{NEXT_OPEN} && $time < $hash->{NEXT_OPEN}) {
    #Log3 $hash, 5, "NEXT_OPEN prevented opening $name";
  }else{
    #-- call the specific interface if delay time is over
    my $success=$owx->Ready();
    if($success) {
      delete($hash->{NEXT_OPEN});
      #-- re-init the bus
      Log3 $name,1,"OWX_Ready calling low-level init of bus";
      my $ret = OWX_Init($hash);
      
    }else{
      $hash->{NEXT_OPEN} = $time+AttrVal($name, "opendelay", 60);
    }
  }
  return undef;
}

########################################################################################
#
# OWX_Set - Implements SetFn function
# 
# Parameter hash , a = argument array
#
########################################################################################

sub OWX_Set($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $res  = 0;

  #-- for the selector: all values are possible for expert, otherwise only reopen
  return ( (AttrVal($name,"expert","") eq "1_detail") ? join(":noArg ", sort keys %sets).":noArg" : "reopen:noArg")
    if(!defined($sets{$a[0]}));
  return "OWX_Set: With unknown argument $a[0], choose one of " .
     ( (AttrVal($name,"expert","") eq "1_detail") ? join(" ", sort keys %sets) : "reopen")
    if(!defined($sets{$a[0]}));

  my $owx   = $hash->{OWX};

  #-- Set open
  if( $a[0] eq "open" ){
    $owx->Open();
    $res = 0;
  } 

  #-- Set close
  if( $a[0] eq "close" ){
    $owx->Close();
    $res = 0;
  }
  
  #-- Set reopen
  if( $a[0] eq "reopen" ){
    $owx->Reopen();
    $res = 0;
  }
  
  #-- Set discover
  if( $a[0] eq "discover" ){
    OWX_Discover($hash);
    $res = 0;
  }
  
  #-- Set detect
  if( $a[0] eq "detect" ){
    my $owx = $hash->{OWX};
    $owx->Detect();
    $res = 0;
  }

  if( $a[0] eq "process") {
    my $res = OWX_PrQueue("queue:$name");
    #-- process result
    return $res
  }

  Log3 $name, 3, "OWX_Set $name ".join(" ",@a)." => $res";  
}

########################################################################################
#
# OWX_Undef - Implements UndefFn function
#
# Parameter hash = hash of the bus master, name
#
########################################################################################

sub OWX_Undef ($$) {
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  RemoveInternalTimer ("queue:$name"); 
  
  # TODO - THIS IS WRONG. DO NOT DELETE THEM, BUT INVALIDATE THEM
  #-- invalidate clients
  #foreach my $d (sort keys %defs) {
  #  if(defined($defs{$d}) &&
  #     defined($defs{$d}{IODev}) &&
  #     $defs{$d}{IODev} == $hash) {
  #      Log3 $hash, 3, "deleting port for $d";
  #      delete $defs{$d}{IODev};
  #    }
  #}  

  DevIo_CloseDev($hash);
  return undef;
}

########################################################################################
#
# OWX_Verify - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not found
#
# Unterbinden
#
########################################################################################

sub OWX_Verify ($$$$) {
  my ($hashorname,$devname,$devid,$type) = @_;
  my $hash;
  my $i;
  
  if( $type == 1){
    $hash = $defs{$hashorname};
  }else{
    $hash = $hashorname;
  }
  
  #-- get the interface
  my $name  = $hash->{NAME};
  my $owx   = $hash->{OWX};
  my $state = $hash->{STATE};
  
  #-- Do nothing, if devices not yet discovered
  return undef
    if( !$hash->{INITDONE} );
  
  my $now = gettimeofday();
  my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
  
  #-- if called synchronously, or queue is blocked, or queue empty, do it now
  if( !($hash->{ASYNCHRONOUS}) ||
      ( $qlen == 0) || 
      ( $hash->{ASYNCHRONOUS} && $hash->{BLOCK} ) ){
    if( $state ne "opened" ) {
      Log3 $name, 3,"OWX_Verify called while interface $name not opened";
      return undef;
    }
    Log3 $name, 5,"OWX_Verify called for interface $name";
    $hash->{BLOCK} = 1;
    $hash->{BUSY} = 1;
    my $ret = $owx->Verify($devid);
    #-- remove queue block and restart queue
    $hash->{BLOCK} = 0;
    $hash->{BUSY} = 0;
    my $slave = $defs{$devname};
    
    #-- generate an event only if presence has changed
    if( $ret == 0 ){
      readingsSingleUpdate($slave,"present",0,$slave->{PRESENT}); 
    } else {
      readingsSingleUpdate($slave,"present",1,!$slave->{PRESENT}); 
    }
    $slave->{PRESENT} = $ret;
    OWX_Ready($hash);
    return $ret;
     
  #-- if called asynchronously, and queue is not blocked, issue queue block and delay.
  }elsif( $hash->{ASYNCHRONOUS} && !($hash->{BLOCK}) ){
    #-- issue queue block
    $hash->{BLOCK} = 1;
    Log3 $name, 5,"OWX_Verify issued a queue block on interface $name";
    $hash->{BLOCKCALL}=sub(){ OWX_Verify($name,$devname,$devid,1); };
    return undef;
  }
}

#######################################################################################
#
# OWX_Write - Write to the bus
#
# Parameter hash      = hash of bus master, 
#
########################################################################################

sub OWX_Write($){
  my $hash = shift;
  my $queue  = $hash->{QUEUE};
  my $data = $queue->[0]{data};
  my $proc = $queue->[0]{proc};
 
  my $name = $hash->{NAME};
  my $owx  = $hash->{OWX};
  my $buffer = "";
  
  #-- catch late calls
  return
     if( !$queue );
     
  #-- perform a send from queue
  if($hash->{STATE} ne "disconnected"){
   
    #-- empty the receive buffer
    $hash->{PARTIAL} = "";
 
    $queue->[0]{status} = "active";
    my $reset = 1-(($proc & 2) >> 1);
    $owx->Write($data, $reset);
  }
  
  #-- in this case we will never get a read operation
  if( $queue->[0]{numread} == -10){
    $hash->{PARTIAL} = "";
    $queue->[0]->{status} = "completed";
    #Log3 $name, 1, "OWX_Write:    queue $name gets status completed because donotwait is set";
    
    #-- if necessary perform a reset after this operation
    if( ($queue->[0]->{proc} & 1)==1 ){
      select(undef,undef,undef,0.01);
      $owx->Reset()
    };
      
    #-- reset busy flag
    shift(@{$queue}); 
    $hash->{BUSY} = 0;  
  }
  return
}

########################################################################################
# 
# Complex R/W operations and queue handling
#
########################################################################################
# 
# OWX_Complex - Synchronously send match ROM, data block and receive bytes as response
#
# Parameter hash    = hash of bus master, 
#           owx_dev = ROM ID of device
#           data    = string to send
#           numread = number of bytes to receive
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub OWX_Complex ($$$$) {
  my ($hash,$owx_dev,$data,$numread) =@_;
  
  #-- get the interface
  my $name  = $hash->{NAME};
  my $owx   = $hash->{OWX};
  my $state = $hash->{STATE};

  if( $state eq "disconnected" ) {
    Log3 $name, 1,"OWX_Complex called while interface $name disconnected";
    return 0;
  }
  my $ret = $owx->Complex($owx_dev,$data,$numread);
  return (!defined($ret))?0:$ret;
}

#######################################################################################
#
# OWX_Qomplex - Put into queue: 
#               asynchronously send match ROM, data block and receive bytes as response
#               but queued
#
# Parameter hash      = hash of bus master, 
#           slave     = hash of slave device
#           context   = mode for evaluating the binary data
#           proc      = processing instruction, also passed to OWX_Read.
#                       bitwise interpretation !!
#                       if 0, nothing special
#                       if 1 = bit 0, a reset will be performed also after
#                       the last operation in OWX_Read
#                       if 2 = bit 1, the initial reset of the bus will be suppressed
#                       if 4 = do not wait for a response for more than ???
#                       if 8 = bit 3, the fillup of the data with 0xff will be suppressed  
#                       if 16= bit 4, the insertion will be at the top of the queue  
#           owx_dev   = ROM ID of slave device
#           data      = string to be sent 
#           crcpart   = part of the data that needs to be part of the CRC check
#           numread   = number of bytes to receive
#           startread = start index to begin reading in the return value
#           callback  = address of callback function  
#           mindelay  = minimum time until next call to this device
#
# Return    response, if NOK (died)
#           undef if  OK
#
########################################################################################

sub OWX_Qomplex(@){
  my ( $hash, $slave, $context, $proc, $owx_dev, $data, $crcpart, $numread, $startread, $callback, $mindelay) = @_;
  #### master slave   context   proc   owx_dev   data   crcpart   numread   startread   callback   delay
  my $name = $hash->{NAME};
  
  my $data2;
  my $res  = "";
  my $res2 = "";
  
  if( !$defs{$name}) {
    return undef;
  }
  
  #-- get the interface
  my $interface = $hash->{INTERFACE};
  my $owx = $hash->{OWX};
  
  my $devlevel = (defined($attr{$name}{verbose})) ? $attr{$name}{verbose} : 0;
  my $qdebug   = ( ($devlevel > 3) || ($attr{global}{verbose}>3) ) ? 1 : 0;
  
  #-- has match ROM part, prepend the rom id
  if( $owx_dev ){
    #-- ID of the device
    my $owx_rnf = substr($owx_dev,3,12);
    my $owx_f   = substr($owx_dev,0,2);

    #-- 8 byte 1-Wire device address
    my @rom_id  =(0,0,0,0 ,0,0,0,0); 
    #-- from search string to byte id
    $owx_dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $rom_id[$i]=hex(substr($owx_dev,2*$i,2));
    }
    $data2=sprintf("\x55%c%c%c%c%c%c%c%c",@rom_id).$data; 
  #-- has no match ROM part, insert a "skip ROM" command
  } else {
    $data2="\xCC".$data;
  }
  
  #-- has receive data part, suppress fillup ?
  if( (($proc & 8)>>3) != 1) {
    if( $numread >0 ){
      #$numread += length($data);
      for( my $i=0;$i<$numread;$i++){
        $data2 .= "\xFF";
      }
    }
  }
  
  my $now = gettimeofday();
    
  my %dialog;
  $dialog{hash}          = $slave;
  $dialog{context}       = $context;
  $dialog{proc}          = $proc;
  $dialog{owx_dev}       = $owx_dev;
  $dialog{data}          = $data2;
  $dialog{crcpart}       = $crcpart;
  $dialog{numread}       = $numread;
  $dialog{startread}     = $startread;
  $dialog{callback}      = $callback;
  $dialog{delay}         = $mindelay;
  $dialog{start}         = $now;
  $dialog{status}        = "waiting";
  
  if( !$context ){
    Log3 $name,1,"OWX_Qomplex: context missing in queue $name entry for device $owx_dev";
    $dialog{context} = ""
  }
  
  my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
  readingsSingleUpdate($hash,"queue",$qlen,0);
  
  #-- single item =>  new queue, and start processing immediately
  if(!$qlen) {
    $hash->{QUEUE} = [ \%dialog ];
    Log3 $name, 4, "OWX_Qomplex: Added dev $owx_dev to queue $name context=$context";
    OWX_PrQueue("direct:".$name);
    
    #-- List queue for debugging 
    if( $qdebug ){
      Log3 $name,1, "   queue $name contains ".scalar(@{$hash->{QUEUE}})." entries after insertion";
      foreach my $diapoint (@{$hash->{QUEUE}}) {  
        Log3 $name, 1, "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status};
      }
      Log3 $name, 1,"----------------------------------------------";
      return;
    }
  #-- priority insert at top of queue, and no immediate processing
  } elsif( (($proc & 16)>>4)==1 ) {
    #if ( $hash->{BUSY}==1 ) { 
    #  my $dialogtop = shift(@{$hash->{QUEUE}});
    #  unshift( @{$hash->{QUEUE}}, \%dialog  );
    #  unshift( @{$hash->{QUEUE}}, $dialogtop);
    #  Log 1,"------------> Prio insert as second task";
    #  Log 1, "   queue $name contains ".scalar(@{$hash->{QUEUE}})." entries after insertion";
    #  foreach my $diapoint (@{$hash->{QUEUE}}) {  
    #    Log 1, "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status};
    #  }
    #  Log 1,"----------------------------------------------";
    #}else{
      unshift( @{$hash->{QUEUE}}, \%dialog  );
      #Log 1,"------------> Prio insert as first task";
      #Log 1, "   queue $name contains ".scalar(@{$hash->{QUEUE}})." entries after insertion";
      #foreach my $diapoint (@{$hash->{QUEUE}}) {  
      #  Log 1, "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status};
      #}
      #Log 1,"----------------------------------------------";
    #}
    return;
  
  #-- insert into existing queue
  } else {
    if ($qlen > AttrVal($name, "queueMax", 100)) {
      Log 1,"OWX_Qomplex: $name queue too long, dropping data"
        if( $qdebug );
    } else {
      push(@{$hash->{QUEUE}}, \%dialog);
      Log 1, "OWX_Qomplex: Added dev $owx_dev to queue $name numread=$numread"
        if( $qdebug );
    }
  }
  #-- List queue for debugging 
  if( $qdebug ){
    Log 1, "   queue $name contains ".scalar(@{$hash->{QUEUE}})." entries after insertion";
    foreach my $diapoint (@{$hash->{QUEUE}}) {  
      Log 1, "    => ".$diapoint->{owx_dev}." context ".$diapoint->{context}." expecting ".$diapoint->{numread}." bytes, ".$diapoint->{status};
    }
    Log 1,"----------------------------------------------";
  }
}

#######################################################################################
#
# OWX_PrQueue - ProcessQueue.
#               Called by internal timer as"queue:$name" 
#               or directly with $direct:$name
#
# Flags: BUSY indicates an asynchronous r/w operation
#        BLOCKED stops the asynchronous operations for synchronous r/w
#
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub OWX_PrQueue($){
  my (undef,$name) = split(':', $_[0]);
  my $hash  = $defs{$name};
  my $queue = $hash->{QUEUE};
  my $slave;
  
  #-- 1 seconds queue delay as default, 2 seconds for timeout
  my $longDelay  = 1.0;
  my $shortDelay = 0.05;
  my $maxrunning = ( defined($attr{$name}{timeout})) ? $attr{$name}{timeout} : 2;
  my $devlevel = (defined($attr{$name}{verbose})) ? $attr{$name}{verbose} : 0;
  my $qdebug   = ( ($devlevel > 3) || ($attr{global}{verbose}>3) ) ? 1 : 0;
  
  RemoveInternalTimer ("queue:$name");
  my $now = gettimeofday();
  
  #-- fhem not initialized, wait with IO || !$hash->{INITDONE}
  if ( !$main::init_done  ) {     
    Log3 $name,1, "OWX_PrQueue: init not done, delay sending from queue $name";
    InternalTimer($now+$longDelay, "OWX_PrQueue", "queue:$name", 0);
    return;
  }
  
  #-- Done with the queue
  return 
    if( !$queue);
  my $qlen  = @{$queue};
  return
    if( $qlen == 0);

  #-- remove top entry if garbage
  if( !defined($queue->[0]{data}) || ($queue->[0]{data} eq "" || $queue->[0]->{start} eq "" )) {
    my $reason = (!defined($queue->[0]{data})) ? "garbage" : (($queue->[0]{data} eq "") ? "no data" : 
      (($queue->[0]->{start} eq "") ? "no start" : "unknown"));
    Log3 $name,1, "OWX_PrQueue: removing garbage from queue $name, reason $reason ";
    shift(@{$queue});
    InternalTimer($now+$shortDelay, "OWX_PrQueue", "queue:$name", 0);
    return;
  }
     
  #-- still waiting for reply to last send
  if ( $hash->{BUSY} && $hash->{BUSY}==1 ) { 
    my $running = int(100*($now-$queue->[0]->{start}))/100;
    #-- donotwait flag is set
    if( (($queue->[0]->{proc} & 4)>>2)==1 ){
      #Log 1, "OWX_PrQueue: removing ".$queue->[0]->{owx_dev}." w. context ".$queue->[0]->{context}." from queue $name, because donotwait is set"
      #  if( $name eq "OWX_TEST");
      $hash->{BUSY}=0;
      shift(@{$queue});
      InternalTimer($now+$shortDelay, "OWX_PrQueue", "queue:$name", 0); 
      return;
    #-- timeout, so kill this entry
    }elsif( $running > $maxrunning ){
      #Log 1, "OWX_PrQueue: removing ".$queue->[0]->{owx_dev}." w. context ".$queue->[0]->{context}." from queue $name. Timeout $running > $maxrunning seconds."
      #  if( $name eq "OWX_TEST");
      $hash->{BUSY}=0;
      shift(@{$queue});
      InternalTimer($now+$shortDelay, "OWX_PrQueue", "queue:$name", 0); 
      return;
    #-- no timeout, but we have to wait for a reply
    }else{
      my $rout='';
      #my $hash2 = $selectlist{'OWX_WIFI.192.168.0.97:23'};
      #my $fd = ( defined($hash2->{FD}) ) ? $hash2->{FD} : "NO";
      #my $vc = ( defined($hash2->{FD}) ) ? vec($rout, $hash2->{FD}, 1) : "NO";
      #Log 1, "OWX_PrQueue: still waiting for reply, delay sending from queue $name"
      #  if( $name eq "OWX_TEST");
      #Log 1, "OWX_PrQueue: still waiting for reply, delay sending from queue $name."; 
      #  Log 1, "     => ".$queue->[0]->{owx_dev}." context ".$queue->[0]->{context}." expecting ".$queue->[0]->{numread}." bytes, ".$queue->[0]->{status};
      InternalTimer($now+$longDelay, "OWX_PrQueue", "queue:$name", 0); 
      return;
    }
  }
    
  #-- if something to send, check if min delay for slave is over
  if( $queue->[0]{data} ) {   
    $slave = $queue->[0]{hash}; # hash of 1-Wire device
    #-- no, it is not
    if ( defined($slave->{NEXTSEND})){
      if( $now < $slave->{NEXTSEND} ){ 
        #-- reschedule, if necessary
        if( ($qlen==1) || (($qlen > 1) && $queue->[1]{$hash} && ($queue->[1]{$hash} eq $slave)) ){
          #Log 1, "OWX_PrQueue: device ".$slave->{NAME}." mindelay not over, rescheduling."
          InternalTimer($now+$shortDelay, "OWX_PrQueue", "queue:$name", 0);
          return;
        #-- switch top positions of queue if possible
        }else{
          #Log 1, "OWX_PrQueue: exchanging top positions of queue";
          my $dialogtop    = shift(@{$queue});
          my $dialogsecond = shift(@{$queue});
          unshift( @{$queue}, $dialogtop);
          unshift( @{$queue}, $dialogsecond);
        }
      }
    }
  }   
    
  #-- something to send, check min delay of 10 ms
  if( $queue->[0]{data} ) {   
    $slave = $queue->[0]{hash};  # may be a different one than above
    #-- no, it is not, reschedule
    if ($hash->{LASTSEND} && $now < $hash->{LASTSEND} + 0.01) {
      #-- List queue for debugging 
      #Log 1, "OWX_PrQueue: queue $name mindelay not over, rescheduling.";
      #  Log 1, "     => ".$queue->[0]->{owx_dev}." context ".$queue->[0]->{context}." expecting ".$queue->[0]->{numread}." bytes, ".$queue->[0]->{status};
      InternalTimer($now+$shortDelay, "OWX_PrQueue", "queue:$name", 0);
      return;
    }   
    #-- start write operation
    $hash->{BUSY}      = 1;         # OWX queue is busy until response is received
    $hash->{LASTSEND}  = $now;      # remember when last sent on this queue
    #-- set delay for this device if necessary
    if( defined($queue->[0]{delay}) ){
      $slave->{NEXTSEND} = $now + $queue->[0]{delay};
    }else{
      delete $slave->{NEXTSEND};
    }
    #  Log 1,"OWX_PrQueue: starting send-receive cycle, queue length $qlen. Setting entry to active";
    #  Log 1, "     => ".$queue->[0]->{owx_dev}." context ".$queue->[0]->{context}." expecting ".$queue->[0]->{numread}." bytes, ".$queue->[0]->{status};
    #  Log 1,"----------------------------------------------";
    #-- REALLY do it 
    #Log 1, "OWX_PrQueue: queue $name starting OWX_Write with context ".$queue->[0]->{context}
    #  if( $name eq "OWX_TEST");
    $queue->[0]->{start} = $now;
    OWX_Write($hash);
  } 
  #-- schedule next processing
  InternalTimer($now+$longDelay, "OWX_PrQueue", "queue:$name", 0); 
  return;
}

#######################################################################################
#
# OWX_WDBG - Write a debug message unconditionally
#
# Parameter $name= device name
#           $msg = string message
#           $bin = binary message
#
########################################################################################

sub OWX_WDBG($$$) {
  my ($name,$msg,$bin) = @_;
  my ($i,$j,$k);
    if( $bin ){ 
      for($i=0;$i<length($bin);$i++){
        $j=int(ord(substr($bin,$i,1))/16);
        $k=ord(substr($bin,$i,1))%16;
        $msg.=sprintf "0x%1x%1x ",$j,$k;
      }
    }
    main::Log3($name, 1, $msg);
}

#######################################################################################
#
# OWX_WDBG - Write a debug message according to verbosity level
#
# Parameter $name= device name
#           $lvl = verbosity level
#           $msg = string message
#           $bin = binary message
#           
########################################################################################

sub OWX_WDBGL($$$$) {
  my ($name,$lvl,$msg,$bin) = @_;
     
  if(defined($name) &&
    defined($attr{$name}) &&
    defined (my $devlevel = $attr{$name}{verbose})) {
    return if($lvl > $devlevel);

  } else {
    return if($lvl > $attr{global}{verbose});
  }

  my ($i,$j,$k);
    if( $bin ){ 
      for($i=0;$i<length($bin);$i++){
        $j=int(ord(substr($bin,$i,1))/16);
        $k=ord(substr($bin,$i,1))%16;
        $msg.=sprintf "0x%1x%1x ",$j,$k;
      }
    }
    main::Log3($name, 1, $msg);
}
1;

=pod
=item device
=item summary to commmunicate with 1-Wire bus devices
=item summary_DE zur Kommunikation mit 1-Wire Geräten
=begin html

<a name="OWX"></a>
        <h3>OWX</h3>
        <ul>
        <p> Backend module to commmunicate with 1-Wire bus devices</p>
        <ul>
            <li>via an active DS2480/DS9097U bus master interface attached to an USB
                port or </li>
            <li>via an active DS2480 bus master interface attached to  a TCP/IP-UART interface </li>
            <li>via a network-attached CUNO or through a COC on the RaspBerry Pi</li>
            <li>via an Arduino running OneWireFirmata</li>
        </ul> Internally these interfaces are vastly different, read the corresponding <a
            href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire"> Wiki pages </a>. 
            The passive DS9097 interface is no longer suppoorted.
        <a name="OWXdefine"></a>
        <h4>Define</h4>
        <p>To define a 1-Wire interface to communicate with a 1-Wire bus, several possibilities exist:
        <ul>
            <li><code>define &lt;name&gt; OWX &lt;serial-device&gt;</code>, i.e. specify the serial device (e.g. USB port) to which the
                1-Wire bus is attached, for example<br/><code>define OWio1 OWX /dev/ttyUSB1</code></li>
            <li><code>define &lt;name&gt; OWX &lt;tcpip&gt;[:&lt;port&gt;]</code>, i.e. specify the IP address and port to which the 1-Wire bus is attached. Attention: no socat program needed. 
                Example:<br/><code>define OWio1 OWX 192.168.0.1:23</code></li>
            <li><code>define &lt;name&gt; OWX &lt;cuno/coc-device&gt;</code>, i.e. specify the previously defined COC/CUNO to which the 1-Wire bus
                is attached, for example<br/><code>define OWio2 OWX COC</code></li>
            <li><code>define &lt;name&gt; OWX &lt;firmata-device&gt;:&lt;firmata-pin&gt;</code>, i.e. specify the name and 1-Wire pin of the previously defined <a href="#FRM">FRM</a>
                device to which the 1-Wire bus is attached, for example<br/><code>define OWio3 OWX FIRMATA:10</code></li>
        </ul>
        <a name="OWXset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owx_reopen">
                    <code>set &lt;name&gt; reopen</code>
                </a>
                <br />re-opens the interface and re-initializes the 1-Wire bus.
            </li>
        </ul>
        <br />
        <a name="OWXget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owx_alarms"></a>
                <code>get &lt;name&gt; alarms</code>
                <br />performs an "alarm search" for devices on the 1-Wire bus and, if found,
                generates an event in the log (not with all interface types). </li>
            <li><a name="owx_devices"></a>
                <code>get &lt;name&gt; devices</code>
                <br />redicovers all devices on the 1-Wire bus. If a device found has a
                previous definition, this is automatically used. If a device is found but has no
                definition, it is autocreated. If a defined device is not on the 1-Wire bus, it is
                autodeleted. </li>
            <li><a name="owx_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />internal version number</li>
        </ul>
        <br />
        <a name="OWXattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="OWXasynchronous"><code>attr &lt;name&gt; asynchronous 0(default)|1</code></a>
            <br />if 1 the interface will run asynchronously;if 0 (default) then not</li>
            <li><a name="OWXtimeout"><code>attr &lt;name&gt; timeout &lt;number&gt;</code></a>
                <br />time in seconds waiting for response of any 1-Wire device, or 1-Wire interface,default 5 s</li>
            <li><a name="OWXopendelay"><code>attr &lt;name&gt; opendelay &lt;number&gt; </code></a>
                <br />time in seconds waiting until a reopen ist attempted, default 60 s</li>            
            <li><a name="OWXdokick"><code>attr &lt;name&gt; dokick 0|1</code></a>
                <br />if 1, the interface regularly kicks thermometers on the bus to do a temperature conversion, 
                and to make an alarm check; if 0 (default) then not</li>         
            <li><a name="OWXinterval"><code>attr &lt;name&gt; interval &lt;number&gt;</code></a>
                <br />time interval in seconds for kicking temperature sensors and checking for alarms, default 300 s</li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        </ul>
=end html
=begin html_DE

<a name="OWX"></a>
<h3>OWX</h3>
<ul>
<a href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="commandref.html#OWX">OWX</a> 
</ul>
=end html_DE
=cut
