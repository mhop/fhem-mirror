########################################################################################
#
# OWX.pm
#
# FHEM module to commmunicate with 1-Wire bus devices
# * via an active DS2480/DS2482/DS2490/DS9097U bus master interface attached to an USB port
# * via a passive DS9097 interface attached to an USB port
# * via a network-attached CUNO
# * via a COC attached to a Raspberry Pi
#
# Prof. Dr. Peter A. Henning
#
# Contributions from: Martin Fischer, Rudolf König, Boris Neubert, Joachim Herold
#
# $Id$
#
########################################################################################
#
# define <name> OWX <serial-device> for USB interfaces or
# define <name> OWX <cuno/coc-device> for a CUNO or COC interface
# define <name> OWX <arduino-pin> for a Arduino/Firmata (10_FRM.pm) interface
#    
# where <name> may be replaced by any name string 
#       <serial-device> is a serial (USB) device
#       <cuno/coc-device>   is a CUNO or COC device
#
# get <name> alarms                 => find alarmed 1-Wire devices (not with CUNO)
# get <name> devices                => find all 1-Wire devices 
#
# set <name> interval <seconds>     => set period for temperature conversion and alarm testing
# set <name> followAlarms on/off    => determine whether an alarm is followed by a search for
#                                      alarmed devices
#
# attr <name> buspower real/parasitic - whether the 1-Wire bus is really powered or 
#      the 1-Wire devices take their power from the data wire (parasitic is default !)
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

#-- unfortunately some things OS-dependent
my $owgdevregexp;
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
  $owgdevregexp= "com";
} else {
  require Device::SerialPort;
  $owgdevregexp= "/dev/";
} 

use vars qw{%attr %defs};

require "$attr{global}{modpath}/FHEM/DevIo.pm";

sub Log($$);

# Line counter 
my $cline=0;

# These we may get on request
my %gets = (
   "alarms" => "A",
   "devices" => "D"
);

# These occur in a pulldown menu as settable values for the bus master
my %sets = (
   "interval" => "T",
   "followAlarms" => "F"
);

# These are attributes
my %attrs = (
);

#-- some globals needed for the 1-Wire module
#-- baud rate serial interface
my $owx_baud=9600;
my $owx_cmdlen;
#-- Debugging 0,1,2,3
my $owx_debug=0;
#-- 8 byte 1-Wire device address
my @owx_ROM_ID  =(0,0,0,0 ,0,0,0,0); 
#-- 16 byte search string
my @owx_search=(0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
#-- search state for 1-Wire bus search
my $owx_LastDiscrepancy = 0;
my $owx_LastFamilyDiscrepancy = 0;
my $owx_LastDeviceFlag = 0;

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
  #-- Provider
  $hash->{Clients}     = ":OWAD:OWCOUNT:OWID:OWLCD:OWMULTI:OWSWITCH:OWTHERM:";

  #-- Normal Devices
  $hash->{DefFn}   = "OWX_Define";
  $hash->{UndefFn} = "OWX_Undef";
  $hash->{GetFn}   = "OWX_Get";
  $hash->{SetFn}   = "OWX_Set";
  $hash->{NotifyFn} = "OWX_Notify";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 buspower:real,parasitic IODev";

  #-- Adapt to FRM
  $hash->{InitFn}   = "FRM_OWX_Init";
}

########################################################################################
#
# OWX_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWX_Define ($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  my $owx_hwdevice;
  
  #-- check syntax
  if(int(@a) < 3){
    return "OWX: Syntax error - must be define <name> OWX"
  }
  
  #-- check syntax
  Log 1,"OWX: Warning - Some parameter(s) ignored, must be define <name> OWX <serial-device>|<cuno/coc-device>|<arduino-pin>"
     if(int(@a) > 3);
  #-- If this line contains 3 parameters, it is the bus master definition
  my $dev = $a[2];
  
  $hash->{NOTIFYDEV} = "global";
  
  #-- Dummy 1-Wire ROM identifier, empty device lists
  $hash->{ROM_ID}      = "FF";
  $hash->{DEVS}        = [];
  $hash->{ALARMDEVS}   = [];
  
  #-- First step: check if we have a directly connected serial interface or a CUNO/COC attached
  if ( $dev =~ m|$owgdevregexp|i){  
    #-- when the specified device name contains @<digits> already, use it as supplied
    if ( $dev !~ m/\@\d*/ ){
      $hash->{DeviceName} = $dev."\@9600";
    }
    #-- Second step in case of serial device: open the serial device to test it
    my $msg = "OWX: Serial device $dev";
    my $ret = DevIo_OpenDev($hash,0,undef);
    $owx_hwdevice = $hash->{USBDev};
    if(!defined($owx_hwdevice)){
      Log 1, $msg." not defined";
      return "OWX: Can't open serial device $dev: $!"
    } else {
      Log 1,$msg." defined";
    }
    $owx_hwdevice->reset_error();
    $owx_hwdevice->baudrate(9600);
    $owx_hwdevice->databits(8);
    $owx_hwdevice->parity('none');
    $owx_hwdevice->stopbits(1);
    $owx_hwdevice->handshake('none');
    $owx_hwdevice->write_settings;
    #-- store with OWX device
    $hash->{INTERFACE} = "serial";
    $hash->{HWDEVICE}   = $owx_hwdevice;
  #-- check if we are connecting to Arduino (via FRM):
  } elsif ($dev =~ /^\d{1,2}$/) {
  	$hash->{INTERFACE} = "firmata";
  	main::LoadModule("FRM");
    FRM_Client_Define($hash,$def);
  } else {
    $hash->{DeviceName} = $dev;
    #-- Second step in case of CUNO: See if we can open it
    my $msg = "OWX: COC/CUNO device $dev";
    #-- hash des COC/CUNO
    $owx_hwdevice = $main::defs{$dev};
    if($owx_hwdevice){
      Log 1,$msg." defined";
      #-- store with OWX device
      $hash->{INTERFACE} = "COC/CUNO";
      $hash->{HWDEVICE}    = $owx_hwdevice;
      #-- loop for some time until the state is "Initialized"
      for(my $i=0;$i<6;$i++){
        last if( $owx_hwdevice->{STATE} eq "Initialized");
        Log 1,"OWX: Waiting, at t=$i ".$dev." is still ".$owx_hwdevice->{STATE};
        select(undef,undef,undef,3); 
      }
      Log 1, "OWX: Can't open ".$dev if( $owx_hwdevice->{STATE} ne "Initialized");
      #-- reset the 1-Wire system in COC/CUNO
      CUL_SimpleWrite($owx_hwdevice, "Oi");
    }else{
      Log 1, $msg." not defined";
      return $msg." not defined";
    } 
  }

  if ($main::init_done) {
    return OWX_Start($hash);
  }
}
  
sub OWX_Start ($) {
  my ($hash) = @_;
  
  #-- Third step: see, if a bus interface is detected
  if (!OWX_Detect($hash)){
    $hash->{PRESENT} = 0;
    readingsSingleUpdate($hash,"state","failed",1);
    return undef;
  }
  #-- Fourth step: discovering devices on the bus
  #   in 10 seconds discover all devices on the 1-Wire bus
  InternalTimer(gettimeofday()+10, "OWX_Discover", $hash,0);
  
  #-- Default settings
  $hash->{interval}     = 300;          # kick every 5 minutes
  $hash->{followAlarms} = "off";
  $hash->{ALARMED}      = "no";
  
  $hash->{PRESENT} = 1;
  readingsSingleUpdate($hash,"state","defined",1);
  #-- Intiate first alarm detection and eventually conversion in a minute or so
  InternalTimer(gettimeofday() + $hash->{interval}, "OWX_Kick", $hash,1);
  $hash->{STATE} = "Active";
  return undef;
}

sub OWX_Notify {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
  	OWX_Start($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

########################################################################################
#
# OWX_Alarms - Find devices on the 1-Wire bus, 
#              which have the alarm flag set
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : no device present
#
########################################################################################

sub OWX_Alarms ($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my @owx_alarm_names=();

  $hash->{ALARMDEVS}=[];
  
  if ($hash->{INTERFACE} eq "firmata") {
  	FRM_OWX_Alarms($hash);
  } else { 
    #-- Discover all alarmed devices on the 1-Wire bus
    my $res = OWX_First_SER($hash,"alarm");
    while( $owx_LastDeviceFlag==0 && $res != 0){
      $res = $res & OWX_Next_SER($hash,"alarm");
    }
  }
  if( @{$hash->{ALARMDEVS}} == 0){
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
  return "OWX: Alarmed 1-Wire devices found on bus $name (".join(",",@owx_alarm_names).")";
}  

########################################################################################
# 
# OWX_Complex - Send match ROM, data block and receive bytes as response
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
  my $name   = $hash->{NAME};
    
  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- interface error
  if( !(defined($owx_interface))){
    Log 3,"OWX: Complex called with undefined interface";
    return 0;
  #-- here we treat the directly connected serial interfaces
  }elsif( ($owx_interface eq "DS2480") || ($owx_interface eq "DS9097") ){
    return OWX_Complex_SER($hash,$owx_dev,$data,$numread);
    
  #-- here we treat the CUNO/COC devices
  }elsif( ($owx_interface eq "COC") || ($owx_interface eq "CUNO")  ){
    return OWX_Complex_CCC($hash,$owx_dev,$data,$numread);

  #-- here we treat Arduino/Firmata devices 
  }elsif( $owx_interface eq "firmata" ) {
    return FRM_OWX_Complex( $hash, $owx_dev, $data, $numread );
		
  #-- interface error
  }else{
    Log 3,"OWX: Complex called with unknown interface $owx_interface on bus $name";
    return 0;
  }
}

########################################################################################
#
# OWX_CRC - Check the CRC8 code of a device address in @owx_ROM_ID
#
# Parameter romid = if not zero, return the CRC8 value instead of checking it
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

  if( $romid eq "0" ){  
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
# OWX_CRC - Check the CRC8 code of an a byte string
#
# Parameter string, crc. 
# If crc is defined, make a comparison, otherwise output crc8
#
########################################################################################

sub OWX_CRC8 ($$) {
  my ($string,$crc) = @_;
  my $crc8=0;  
  my @strhex;
  
  #Log 1,"CRC8 calculated for string of length ".length($string);

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
    #Log 1,"Returning $crc8";
    return $crc8;
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
  
  #Log 1,"CRC16 calculated for string of length ".length($string);

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
# OWX_Detect - Detect 1-Wire interface 
# TODO: HAS TO BE SPLIT INTO INTERFACE DEPENDENT AND INDEPENDENT PART
#
# Method rather crude - treated as an 2480, and see whatis returned
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Detect ($) {
  my ($hash) = @_;
  
  my ($i,$j,$k,$l,$res,$ret,$ress);
  my $name = $hash->{NAME};
  my $ress0 = "OWX: 1-Wire bus $name: interface ";
  $ress     = $ress0;

  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- here we treat the directly connected serial interfaces
  if($owx_interface eq "serial"){
    #-- timing byte for DS2480
    OWX_Query_2480($hash,"\xC1",1);
  
    #-- Max 4 tries to detect an interface
    for($l=0;$l<100;$l++) {
      #-- write 1-Wire bus (Fig. 2 of Maxim AN192)
      $res = OWX_Query_2480($hash,"\x17\x45\x5B\x0F\x91",5);
    
      #-- process 4/5-byte string for detection
      if( !defined($res)){
        $res="";
        $ret=0;
      }elsif( ($res eq "\x16\x44\x5A\x00\x90") || ($res eq "\x16\x44\x5A\x00\x93")){
        $ress .= "master DS2480 detected for the first time";
        $owx_interface="DS2480";
        $ret=1;
      } elsif( $res eq "\x17\x45\x5B\x0F\x91"){
        $ress .= "master DS2480 re-detected";
        $owx_interface="DS2480";
        $ret=1;
      } elsif( ($res eq "\x17\x0A\x5B\x0F\x02") || ($res eq "\x00\x17\x0A\x5B\x0F\x02") || ($res eq "\x30\xf8\x00") ){
        $ress .= "passive DS9097 detected";
        $owx_interface="DS9097";
        $ret=1;
      } else {
        $ret=0;
      }
      last 
        if( $ret==1 );
      $ress .= "not found, answer was ";
      for($i=0;$i<length($res);$i++){
        $j=int(ord(substr($res,$i,1))/16);
        $k=ord(substr($res,$i,1))%16;
        $ress.=sprintf "0x%1x%1x ",$j,$k;
      }
      Log 1, $ress;
      $ress = $ress0;
      #-- sleeping for some time
      select(undef,undef,undef,0.5);
    }
    if( $ret == 0 ){
      $owx_interface=undef;
      $ress .= "not detected, answer was ";
      for($i=0;$i<length($res);$i++){
        $j=int(ord(substr($res,$i,1))/16);
        $k=ord(substr($res,$i,1))%16;
        $ress.=sprintf "0x%1x%1x ",$j,$k;
      }
    }
    #-- nothing to do for Arduino (already done in FRM)
  } elsif($owx_interface eq "firmata") {
    eval {
      FRM_Client_AssignIOPort($hash);
      if (defined $hash->{IODev}) {
        $ret=1;
  	    $ress .= "Firmata detected in $hash->{IODev}->{NAME}";
      } else {
      	$ret = 0;
      	$ress .= "not associated to any FRM device";
      }
    };
    if ($@) {
      $ress .= FRM_Catch($@);
      $ret = 0;
	}
    #-- here we treat the COC/CUNO
  } else {
    select(undef,undef,undef,2);
    #-- type of interface
    CUL_SimpleWrite($owx_hwdevice, "V");
    select(undef,undef,undef,0.01);
    my ($err,$ob) = OWX_ReadAnswer_CCC($owx_hwdevice);
    #my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "V"));
    #-- process result for detection
    if( !defined($ob)){
      $ob="";
      $ret=0;
    #-- COC
    }elsif( $ob =~ m/.*CSM.*/){
      $owx_interface="COC";
      $ress .= "DS2482 / COC detected in $owx_hwdevice->{NAME} with response $ob";
      $ret=1;
    #-- CUNO
    }elsif( $ob =~ m/.*CUNO.*/){
      $owx_interface="CUNO";
      $ress .= "DS2482 / CUNO detected in $owx_hwdevice->{NAME} with response $ob";
      $ret=1;
    #-- something else
    } else {
      $ret=0;
    }
    #-- treat the failure cases
    if( $ret == 0 ){
      $owx_interface=undef;
      $ress .= "in $owx_hwdevice->{NAME} could not be addressed, return was $ob";
    }
  }
  #-- store with OWX device
  $hash->{INTERFACE} = $owx_interface;
  Log3 $hash->{NAME}, 1, $ress;
  return $ret; 
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
  my $res;
  my $ret= "";
  my $name = $hash->{NAME};
  my $exname;
  my $acname;
  
  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  my @owx_names=();

  #-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
  return undef
    if( !defined($owx_interface) );
  #-- Directly connected serial interface
  if(  ($owx_interface eq "DS2480") || ($owx_interface eq "DS9097") ){
    $res = OWX_First_SER($hash,"discover");
    while( $owx_LastDeviceFlag==0 && $res!=0 ){
      $res = $res & OWX_Next_SER($hash,"discover"); 
    }
  #-- Ask the COC/CUNO
  }elsif( ($owx_interface eq "COC" ) || ($owx_interface eq "CUNO") ){
    $res = OWX_Discover_CCC($hash);
  #-- ask the Arduino
  }elsif ( $owx_interface eq "firmata") {
    $res = FRM_OWX_Discover($hash);
  #-- Something else
  } else {
    Log 1,"OWX: Discover called with unknown interface";
    return undef;
  }
  
  #-- Go through all devices found on this bus
  foreach my $owx_dev  (@{$hash->{DEVS}}) {
    #-- ignore those which do not have the proper pattern
    if( !($owx_dev =~ m/[0-9A-F]{2}\.[0-9A-F]{12}\.[0-9A-F]{2}/) ){
      Log 3,"OWX: Invalid 1-Wire device ID $owx_dev, ignoring it";
      next;
    }
    
    #-- three pieces of the ROM ID found on the bus
    my $owx_rnf = substr($owx_dev,3,12);
    my $owx_f   = substr($owx_dev,0,2);
    my $owx_crc = substr($owx_dev,15,3);
    my $id_owx  = $owx_f.".".$owx_rnf;
      
    my $match = 0;
    
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
      #-- testing if equal to the one found here  
      #   even with improper family
      #   Log 1, " FHEM-Device = ".substr($id_fhem,3,12)." OWX discovered device ".substr($id_owx,3,12);
      if( substr($id_fhem,3,12) eq substr($id_owx,3,12) ) {
        #-- warn if improper family id
        if( substr($id_fhem,0,2) ne substr($id_owx,0,2) ){
          Log 1, "OWX: Warning, $fhem_dev is defined with improper family id ".substr($id_fhem,0,2). 
           ", must enter correct model in configuration";
           #$main::defs{$fhem_dev}{OW_FAMILY} = substr($id_owx,0,2);
        }
        $exname=$main::defs{$fhem_dev}{NAME};
        push(@owx_names,$exname);
        #-- replace the ROM ID by the proper value including CRC
        $main::defs{$fhem_dev}{ROM_ID}=$owx_dev;
        $main::defs{$fhem_dev}{PRESENT}=1;    
        $match = 1;
        last;
      }
      #
    }
 
    #-- Determine the device type. This is done manually here
    #   could be automatic as in OWServer
    my $acstring;
    my $chip;
    #-- Family 10 = Temperature sensor DS1820
    if( $owx_f eq "10" ){
      $chip     = "DS1820";
      $acstring = "OWTHERM DS1820";  
    #-- Family 12 = Switch DS2406
    }elsif( $owx_f eq "12" ){
      $chip     = "DS2406";
      $acstring = "OWSWITCH DS2406";     
    #-- Family 1D = Counter/RAM DS2423
    }elsif( $owx_f eq "1D" ){
      $chip     = "DS2423";
      $acstring = "OWCOUNT DS2423";            
    #-- Family 20 = A/D converter DS2450
    } elsif( $owx_f eq "20" ){
      $chip     = "DS2450";
      $acstring = "OWAD DS2450"; 
    #-- Family 22 = Temperature sensor DS1822
    }elsif( $owx_f eq "22" ){
      $chip     = "DS1822";
      $acstring = "OWTHERM DS1822";  
    #-- Family 26 = Multisensor DS2438
    }elsif( $owx_f eq "26" ){
      $chip     = "DS2438";
      $acstring = "OWMULTI DS2438";
    #-- Family 28 = Temperature sensor DS18B20
    }elsif( $owx_f eq "28" ){
      $chip     = "DS18B20";
      $acstring = "OWTHERM DS18B20";   
    #-- Family 29 = Switch DS2408
    }elsif( $owx_f eq "29" ){
      $chip     = "DS2408";
      $acstring = "OWSWITCH DS2408";  
    #-- Family 3A = Switch DS2413
    }elsif( $owx_f eq "3A" ){
      $chip     = "DS2413";
      $acstring = "OWSWITCH DS2413";  
    #-- Family FF = LCD display    
    }elsif( $owx_f eq "FF" ){
      $chip     = "LCD";
      $acstring = "OWLCD";        
    #-- All unknown families are ID only (ID-Chips have family id 09)
    } else {
      $chip     = "unknown";
      $acstring = "OWID $owx_f";  
    }
       
    #Log 1,"###\nfor the following device match=$match, chip=$chip name=$name acstring=$acstring";
    #-- device exists
    if( $match==1 ){
      $ret .= sprintf("%s.%s      %-10s %s\n", $owx_f,$owx_rnf, $chip, $exname);
    #-- device unknoen, autocreate
    }else{
    #-- example code for checking global autocreate - do we want this ?
    #foreach my $d (keys %defs) {
    #next if($defs{$d}{TYPE} ne "autocreate");
    #return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
      my $acname = sprintf "OWX_%s_%s",$owx_f,$owx_rnf;
      #Log 1, "to define $acname $acstring $owx_rnf";
      $res = CommandDefine(undef,"$acname $acstring $owx_rnf");
      if($res) {
        $ret.= "OWX: Error autocreating with $acname $acstring $owx_rnf: $res\n";
      } else{
        select(undef,undef,undef,0.1);
        push(@owx_names,$acname);
        $main::defs{$acname}{PRESENT}=1;
        #-- THIS IODev, default room (model is set in the device module)
        CommandAttr (undef,"$acname IODev $hash->{NAME}"); 
        CommandAttr (undef,"$acname room OWX"); 
        #-- replace the ROM ID by the proper value 
        $main::defs{$acname}{ROM_ID}=$owx_dev;
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
    Log 1, "OWX: Deleting unused 1-Wire device $main::defs{$fhem_dev}{NAME} of type $main::defs{$fhem_dev}{TYPE}";
    CommandDelete(undef,$main::defs{$fhem_dev}{NAME});
    #Log 1, "present= ".$main::defs{$fhem_dev}{PRESENT}." iodev=".$main::defs{$fhem_dev}{IODev}{NAME};
  }
  #-- Log the discovered devices
  Log 1, "OWX: 1-Wire devices found on bus $name (".join(",",@owx_names).")";
  #-- tabular view as return value
  return "OWX: 1-Wire devices found on bus $name \n".$ret;
  
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
    
  } else {
    return "OWX: Get with unknown argument $a[1], choose one of ". 
    join(" ", sort keys %gets);
  }
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
  my($hash) = @_;
  my $ret;

  #-- Call us in n seconds again.
  InternalTimer(gettimeofday()+ $hash->{interval}, "OWX_Kick", $hash,1);
  #-- During reset we see if an alarmed device is present.
  OWX_Reset($hash);
   
  #-- Only if we have real power on the bus
  if( defined($attr{$hash->{NAME}}{buspower}) &&  ($attr{$hash->{NAME}}{buspower} eq "real") ){
    #-- issue the skip ROM command \xCC followed by start conversion command \x44 
    $ret = OWX_Complex($hash,"","\xCC\x44",0);
    if( $ret eq 0 ){
      Log 3, "OWX: Failure in temperature conversion\n";
      return 0;
    }
    #-- sleeping for some time
    select(undef,undef,undef,0.5);
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
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
   #-- interface error
  if( !(defined($owx_interface))){
    Log 3,"OWX: Reset called with undefined interface";
    return 0;
  }elsif( $owx_interface eq "DS2480" ){
    return OWX_Reset_2480($hash);
  }elsif( $owx_interface eq "DS9097" ){
    return OWX_Reset_9097($hash);
  }elsif( $owx_interface eq "COC" ){
    return OWX_Reset_CCC($hash);
  }elsif( $owx_interface eq "CUNO" ){
    return OWX_Reset_CCC($hash);
  }elsif( $owx_interface eq "firmata" ) {
    return FRM_OWX_Reset($hash);
  }else{
    Log 3,"OWX: Reset called with unknown interface $owx_interface";
    return 0;
  }
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
  my $res;

  #-- First we need to find the ROM ID corresponding to the device name
  my $owx_romid =  $hash->{ROM_ID};
  Log 5, "OWX_Set request $name $owx_romid ".join(" ",@a);

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a != 2);
  return "OWX_Set: With unknown argument $a[0], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[0]}));
    
  #-- Set timer value
  if( $a[0] eq "interval" ){
    #-- only values >= 15 secs allowed
    if( $a[1] >= 15){
      $hash->{interval} = $a[1];  
  	  $res = 1;
  	} else {
  	  $res = 0;
  	}
  }
  
  #-- Set alarm behaviour
  if( $a[0] eq "followAlarms" ){
    #-- only values >= 15 secs allowed
    if( (lc($a[1]) eq "off") && ($hash->{followAlarms} eq "on") ){
      $hash->{interval} = "off";  
  	  $res = 1;
  	}elsif( (lc($a[1]) eq "on") && ($hash->{followAlarms} eq "off") ){
      $hash->{interval} = "off";  
  	  $res = 1;
  	} else {
  	  $res = 0;
  	}
    
  }
  Log GetLogLevel($name,3), "OWX_Set $name ".join(" ",@a)." => $res";  
  DoTrigger($name, undef) if($init_done);
  return "OWX_Set => $name ".join(" ",@a)." => $res";
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
########################################################################################

sub OWX_Verify ($$) {
  my ($hash,$dev) = @_;
  my $i;
  
  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  
  #-- Verify this device on the 1-Wire bus
  return 0
    if( !defined($owx_interface) );
  #-- Directly connected interface
  if(  ($owx_interface eq "DS2480") || ($owx_interface eq "DS9097") ){
    return OWX_Verify_SER($hash,$dev)
  #-- Ask the COC/CUNO
  }elsif( ($owx_interface eq "COC" ) || ($owx_interface eq "CUNO") ){
    return OWX_Verify_CCC($hash,$dev)
  }elsif( $owx_interface eq "firmata" ){
  	return FRM_OWX_Verify($hash,$dev);
  } else {
    Log 1,"OWX: Verify called with unknown interface";
    return 0;
  }
}

########################################################################################
#
# The following subroutines in alphabetical order are only for direct serial bus interface
#
########################################################################################
# 
# OWX_Complex_SER - Send match ROM, data block and receive bytes as response
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

sub OWX_Complex_SER ($$$$) {
  my ($hash,$owx_dev,$data,$numread) =@_;
  
  my $select;
  my $res  = "";
  my $res2 = "";
  my ($i,$j,$k);
  
  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- has match ROM part
  if( $owx_dev ){
    #-- ID of the device
    my $owx_rnf = substr($owx_dev,3,12);
    my $owx_f   = substr($owx_dev,0,2);

    #-- 8 byte 1-Wire device address
    my @owx_ROM_ID  =(0,0,0,0 ,0,0,0,0); 
    #-- from search string to byte id
    $owx_dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $owx_ROM_ID[$i]=hex(substr($owx_dev,2*$i,2));
    }
    $select=sprintf("\x55%c%c%c%c%c%c%c%c",@owx_ROM_ID).$data; 
  #-- has no match ROM part
  } else {
    $select=$data;
  }
  #-- has receive data part
  if( $numread >0 ){
    #$numread += length($data);
    for( my $i=0;$i<$numread;$i++){
      $select .= "\xFF";
    };
  }
  
  #-- for debugging
  if( $owx_debug > 1){
    $res2 = "OWX_Complex_SER: Sending out ";
    for($i=0;$i<length($select);$i++){  
      $j=int(ord(substr($select,$i,1))/16);
      $k=ord(substr($select,$i,1))%16;
      $res2.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res2;
  }
  if( $owx_interface eq "DS2480" ){
    $res = OWX_Block_2480($hash,$select);
  }elsif( $owx_interface eq "DS9097" ){
    $res = OWX_Block_9097($hash,$select);
  }
  
  #-- for debugging
  if( $owx_debug > 1){
    $res2 = "OWX_Complex_SER: Receiving   ";
    for($i=0;$i<length($res);$i++){  
      $j=int(ord(substr($res,$i,1))/16);
      $k=ord(substr($res,$i,1))%16;
      $res2.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res2;
  }
  
  return $res
}

########################################################################################
#
# OWX_First_SER - Find the 'first' devices on the 1-Wire bus
#
# Parameter hash = hash of bus master, mode
#
# Return 1 : device found, ROM number pushed to list
#        0 : no device present
#
########################################################################################

sub OWX_First_SER ($$) {
  my ($hash,$mode) = @_;
  
  #-- clear 16 byte of search data
  @owx_search=(0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- reset the search state
  $owx_LastDiscrepancy = 0;
  $owx_LastDeviceFlag = 0;
  $owx_LastFamilyDiscrepancy = 0;
  #-- now do the search
  return OWX_Search_SER($hash,$mode);
}

########################################################################################
#
# OWX_Next_SER - Find the 'next' devices on the 1-Wire bus
#
# Parameter hash = hash of bus master, mode
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub OWX_Next_SER ($$) {
  my ($hash,$mode) = @_;
  #-- now do the search
  return OWX_Search_SER($hash,$mode);
}

#######################################################################################
#
# OWX_Search_SER - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub OWX_Search_SER ($$) {
  my ($hash,$mode)=@_;
  
  my @owx_fams=();
  
  #-- get the interface
  my $owx_interface = $hash->{INTERFACE};
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- if the last call was the last one, no search 
  if ($owx_LastDeviceFlag==1){
    return 0;
  }
  #-- 1-Wire reset
  if (OWX_Reset($hash)==0){
    #-- reset the search
    Log 1, "OWX: Search reset failed";
    $owx_LastDiscrepancy = 0;
    $owx_LastDeviceFlag = 0;
    $owx_LastFamilyDiscrepancy = 0;
    return 0;
  }
  
  #-- Here we call the device dependent part
  if( $owx_interface eq "DS2480" ){
    OWX_Search_2480($hash,$mode);
  }elsif( $owx_interface eq "DS9097" ){
    OWX_Search_9097($hash,$mode);
  }else{
    Log 1,"OWX: Search called with unknown interface ".$owx_interface;
    return 0;
  }
  #--check if we really found a device
  if( OWX_CRC(0)!= 0){  
  #-- reset the search
    Log 1, "OWX: Search CRC failed ";
    $owx_LastDiscrepancy = 0;
    $owx_LastDeviceFlag = 0;
    $owx_LastFamilyDiscrepancy = 0;
    return 0;
  }
    
  #-- character version of device ROM_ID, first byte = family 
  my $dev=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@owx_ROM_ID);
  
  #-- for some reason this does not work - replaced by another test, see below
  #if( $owx_LastDiscrepancy==0 ){
  #    $owx_LastDeviceFlag=1;
  #}
  #--
  if( $owx_LastDiscrepancy==$owx_LastFamilyDiscrepancy ){
      $owx_LastFamilyDiscrepancy=0;    
  }
    
  #-- mode was to verify presence of a device
  if ($mode eq "verify") {
    Log 5, "OWX: Device verified $dev";
    return 1;
  #-- mode was to discover devices
  } elsif( $mode eq "discover" ){
    #-- check families
    my $famfnd=0;
    foreach (@owx_fams){
      if( substr($dev,0,2) eq $_ ){        
        #-- if present, set the fam found flag
        $famfnd=1;
        last;
      }
    }
    push(@owx_fams,substr($dev,0,2)) if( !$famfnd );
    foreach (@{$hash->{DEVS}}){
      if( $dev eq $_ ){        
        #-- if present, set the last device found flag
        $owx_LastDeviceFlag=1;
        last;
      }
    }
    if( $owx_LastDeviceFlag!=1 ){
      #-- push to list
      push(@{$hash->{DEVS}},$dev);
      Log 5, "OWX: New device found $dev";
    }  
    return 1;
    
  #-- mode was to discover alarm devices 
  } else {
    for(my $i=0;$i<@{$hash->{ALARMDEVS}};$i++){
      if( $dev eq ${$hash->{ALARMDEVS}}[$i] ){        
        #-- if present, set the last device found flag
        $owx_LastDeviceFlag=1;
        last;
      }
    }
    if( $owx_LastDeviceFlag!=1 ){
    #--push to list
      push(@{$hash->{ALARMDEVS}},$dev);
      Log 5, "OWX: New alarm device found $dev";
    }  
    return 1;
  }
}

########################################################################################
#
# OWX_Verify_SER - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not
#
########################################################################################

sub OWX_Verify_SER ($$) {
  my ($hash,$dev) = @_;
  my $i;
    
  #-- from search string to byte id
  my $devs=$dev;
  $devs=~s/\.//g;
  for($i=0;$i<8;$i++){
     $owx_ROM_ID[$i]=hex(substr($devs,2*$i,2));
  }
  #-- reset the search state
  $owx_LastDiscrepancy = 64;
  $owx_LastDeviceFlag = 0;
  #-- now do the search
  my $res=OWX_Search_SER($hash,"verify");
  my $dev2=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@owx_ROM_ID);
  #-- reset the search state
  $owx_LastDiscrepancy = 0;
  $owx_LastDeviceFlag = 0;
  #-- check result
  if ($dev eq $dev2){
    return 1;
  }else{
    return 0;
  }
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a DS2480 bus interface
#
#########################################################################################
# 
# OWX_Block_2480 - Send data block (Fig. 6 of Maxim AN192)
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub OWX_Block_2480 ($$) {
  my ($hash,$data) =@_;
  
   my $data2="";
   my $retlen = length($data);
   
  #-- if necessary, prepend E1 character for data mode
  if( substr($data,0,1) ne '\xE1') {
    $data2 = "\xE1";
  }
  #-- all E3 characters have to be duplicated
  for(my $i=0;$i<length($data);$i++){
    my $newchar = substr($data,$i,1);
    $data2=$data2.$newchar;
    if( $newchar eq '\xE3'){
      $data2=$data2.$newchar;
    }
  }
  #-- write 1-Wire bus as a single string
  my $res =OWX_Query_2480($hash,$data2,$retlen);
  return $res;
}

########################################################################################
# 
# OWX_Level_2480 - Change power level (Fig. 13 of Maxim AN192)
#
# Parameter hash = hash of bus master, newlevel = "normal" or something else
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Level_2480 ($$) {
  my ($hash,$newlevel) =@_;
  my $cmd="";
  my $retlen=0;
  #-- if necessary, prepend E3 character for command mode
  $cmd = "\xE3";
 
  #-- return to normal level
  if( $newlevel eq "normal" ){
    $cmd=$cmd."\xF1\xED\xF1";
    $retlen+=3;
    #-- write 1-Wire bus
    my $res = OWX_Query_2480($hash,$cmd,$retlen);
    #-- process result
    my $r1  = ord(substr($res,0,1)) & 236;
    my $r2  = ord(substr($res,1,1)) & 236;
    if( ($r1 eq 236) && ($r2 eq 236) ){
      Log 5, "OWX: Level change to normal OK";
      return 1;
    } else {
      Log 3, "OWX: Failed to change to normal level";
      return 0;
    }
  #-- start pulse  
  } else {    
    $cmd=$cmd."\x3F\xED";
    $retlen+=2;
    #-- write 1-Wire bus
    my $res = OWX_Query_2480($hash,$cmd,$retlen);
    #-- process result
    if( $res eq "\x3E" ){
      Log 5, "OWX: Level change OK";
      return 1;
    } else {
      Log 3, "OWX: Failed to change level";
      return 0;
    }
  }
}

########################################################################################
#
# OWX_Query_2480 - Write to and read from the 1-Wire bus
# 
# Parameter: hash = hash of bus master, cmd = string to send to the 1-Wire bus
#
# Return: string received from the 1-Wire bus
#
########################################################################################

sub OWX_Query_2480 ($$$) {

  my ($hash,$cmd,$retlen) = @_;
  my ($i,$j,$k,$l,$m,$n);
  my $string_in = "";
  my $string_part;
  
  #-- get hardware device
  my $owx_hwdevice = $hash->{HWDEVICE};
  
  $owx_hwdevice->baudrate($owx_baud);
  $owx_hwdevice->write_settings;

  if( $owx_debug > 2){
    my $res = "OWX: Sending out        ";
    for($i=0;$i<length($cmd);$i++){  
      $j=int(ord(substr($cmd,$i,1))/16);
      $k=ord(substr($cmd,$i,1))%16;
  	$res.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res;
  }
  
  my $count_out = $owx_hwdevice->write($cmd);
  
  if( !($count_out)){
    Log 3,"OWX_Query_2480: No return value after writing" if( $owx_debug > 0);
  } else {
    Log 3, "OWX_Query_2480: Write incomplete $count_out ne ".(length($cmd))."" if ( ($count_out != length($cmd)) & ($owx_debug > 0));
  }
  #-- sleeping for some time
  select(undef,undef,undef,0.04);
 
  #-- read the data - looping for slow devices suggested by Joachim Herold
  $n=0;                                                
  for($l=0;$l<$retlen;$l+=$m) {                            
    my ($count_in, $string_part) = $owx_hwdevice->read(48);  
    $string_in .= $string_part;                            
    $m = $count_in;		
  	$n++;
 	if( $owx_debug > 2){
 	  Log 3, "Schleifendurchlauf $n";
 	  }
 	if ($n > 100) {                                       
	  $m = $retlen;                                         
	}
	select(undef,undef,undef,0.02);	                      
    if( $owx_debug > 2){	
      my $res = "OWX: Receiving in loop no. $n ";
      for($i=0;$i<$count_in;$i++){ 
	    $j=int(ord(substr($string_part,$i,1))/16);
        $k=ord(substr($string_part,$i,1))%16;
        $res.=sprintf "0x%1x%1x ",$j,$k;
	  }
      Log 3, $res
        if( $count_in > 0);
	}
  }
	
  #-- sleeping for some time
  select(undef,undef,undef,0.01);
  return($string_in);
}

########################################################################################
# 
# OWX_Reset_2480 - Reset the 1-Wire bus (Fig. 4 of Maxim AN192)
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Reset_2480 ($) {

  my ($hash)=@_;
  my $cmd="";
  my $name     = $hash->{NAME};
 
  my ($res,$r1,$r2);
  #-- if necessary, prepend \xE3 character for command mode
  $cmd = "\xE3";
  
  #-- Reset command \xC5
  $cmd  = $cmd."\xC5"; 
  #-- write 1-Wire bus
  $res =OWX_Query_2480($hash,$cmd,1);

  #-- if not ok, try for max. a second time
  $r1  = ord(substr($res,0,1)) & 192;
  if( $r1 != 192){
    #Log 1, "Trying second reset";
    $res =OWX_Query_2480($hash,$cmd,1);
  }

  #-- process result
  $r1  = ord(substr($res,0,1)) & 192;
  if( $r1 != 192){
    Log 3, "OWX: Reset failure on bus $name";
    return 0;
  }
  $hash->{ALARMED} = "no";
  
  $r2 = ord(substr($res,0,1)) & 3;
  
  if( $r2 == 3 ){
    #Log 3, "OWX: No presence detected";
    return 1;
  }elsif( $r2 ==2 ){
    Log 1, "OWX: Alarm presence detected on bus $name";
    $hash->{ALARMED} = "yes";
  }
  return 1;
}

########################################################################################
#
# OWX_Search_2480 - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub OWX_Search_2480 ($$) {
  my ($hash,$mode)=@_;
  
  my ($sp1,$sp2,$response,$search_direction,$id_bit_number);
    
  #-- Response search data parsing operates bytewise
  $id_bit_number = 1;
  
  select(undef,undef,undef,0.5);
  
  #-- clear 16 byte of search data
  @owx_search=(0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- Output search data construction (Fig. 9 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  while ( $id_bit_number <= 64) {
    #-- address single bits in a 16 byte search string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;
    #-- address single bits in a 8 byte id string
    my $newcpos2 = int(($id_bit_number-1)/8);
    my $newimsk2 = ($id_bit_number-1)%8;

    if( $id_bit_number <= $owx_LastDiscrepancy){
      #-- first use the ROM ID bit to set the search direction  
      if( $id_bit_number < $owx_LastDiscrepancy ) {
        $search_direction = ($owx_ROM_ID[$newcpos2]>>$newimsk2) & 1;
        #-- at the last discrepancy search into 1 direction anyhow
      } else {
        $search_direction = 1;
      } 
      #-- fill into search data;
      $owx_search[$newcpos]+=$search_direction<<(2*$newimsk+1);
    }
    #--increment number
    $id_bit_number++;
  }
  #-- issue data mode \xE1, the normal search command \xF0 or the alarm search command \xEC 
  #   and the command mode \xE3 / start accelerator \xB5 
  if( $mode ne "alarm" ){
    $sp1 = "\xE1\xF0\xE3\xB5";
  } else {
    $sp1 = "\xE1\xEC\xE3\xB5";
  }
  #-- issue data mode \xE1, device ID, command mode \xE3 / end accelerator \xA5
  $sp2=sprintf("\xE1%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c\xE3\xA5",@owx_search); 
  $response = OWX_Query_2480($hash,$sp1,1); 
  $response = OWX_Query_2480($hash,$sp2,16);   
     
  #-- interpret the return data
  if( length($response)!=16 ) {
    Log 3, "OWX: Search 2nd return has wrong parameter with length = ".length($response)."";
    return 0;
  }
  #-- Response search data parsing (Fig. 11 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  $id_bit_number = 1;
  #-- clear 8 byte of device id for current search
  @owx_ROM_ID =(0,0,0,0 ,0,0,0,0); 

  while ( $id_bit_number <= 64) {
    #-- adress single bits in a 16 byte string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;

    #-- retrieve the new ROM_ID bit
    my $newchar = substr($response,$newcpos,1);
 
    #-- these are the new bits
    my $newibit = (( ord($newchar) >> (2*$newimsk) ) & 2) / 2;
    my $newdbit = ( ord($newchar) >> (2*$newimsk) ) & 1;

    #-- output for test purpose
    #print "id_bit_number=$id_bit_number => newcpos=$newcpos, newchar=0x".int(ord($newchar)/16).
    #      ".".int(ord($newchar)%16)." r$id_bit_number=$newibit d$id_bit_number=$newdbit\n";
    
    #-- discrepancy=1 and ROM_ID=0
    if( ($newdbit==1) and ($newibit==0) ){
        $owx_LastDiscrepancy=$id_bit_number;
        if( $id_bit_number < 9 ){
        $owx_LastFamilyDiscrepancy=$id_bit_number;
        }
    } 
    #-- fill into device data; one char per 8 bits
    $owx_ROM_ID[int(($id_bit_number-1)/8)]+=$newibit<<(($id_bit_number-1)%8);
  
    #-- increment number
    $id_bit_number++;
  }
  return 1;
}

########################################################################################
# 
# OWX_WriteBytePower_2480 - Send byte to bus with power increase (Fig. 16 of Maxim AN192)
#
# Parameter hash = hash of bus master, dbyte = byte to send
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_WriteBytePower_2480 ($$) {

  my ($hash,$dbyte) =@_;
  my $cmd="\x3F";
  my $ret="\x3E";
  #-- if necessary, prepend \xE3 character for command mode
  $cmd = "\xE3".$cmd;
  
  #-- distribute the bits of data byte over several command bytes
  for (my $i=0;$i<8;$i++){
    my $newbit   = (ord($dbyte) >> $i) & 1;
    my $newchar  = 133 | ($newbit << 4);
    my $newchar2 = 132 | ($newbit << 4) | ($newbit << 1) | $newbit;
    #-- last command byte still different
    if( $i == 7){
      $newchar = $newchar | 2;
    }
    $cmd = $cmd.chr($newchar);
    $ret = $ret.chr($newchar2);
  }
  #-- write 1-Wire bus
  my $res = OWX_Query($hash,$cmd);
  #-- process result
  if( $res eq $ret ){
    Log 5, "OWX: WriteBytePower OK";
    return 1;
  } else {
    Log 3, "OWX: WriteBytePower failure";
    return 0;
  }
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a DS9097 bus interface
#
########################################################################################
# 
# OWX_Block_9097 - Send data block (
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub OWX_Block_9097 ($$) {
  my ($hash,$data) =@_;
  
   my $data2="";
   my $res=0;
   for (my $i=0; $i<length($data);$i++){
     $res = OWX_TouchByte_9097($hash,ord(substr($data,$i,1)));
     $data2 = $data2.chr($res);
   }
   return $data2;
}

########################################################################################
#
# OWX_Query_9097 - Write to and read from the 1-Wire bus
# 
# Parameter: hash = hash of bus master, cmd = string to send to the 1-Wire bus
#
# Return: string received from the 1-Wire bus
#
########################################################################################

sub OWX_Query_9097 ($$) {

  my ($hash,$cmd) = @_;
  my ($i,$j,$k);
  #-- get hardware device 
  my $owx_hwdevice = $hash->{HWDEVICE};
  
  $owx_hwdevice->baudrate($owx_baud);
  $owx_hwdevice->write_settings;
  
  if( $owx_debug > 2){
    my $res = "OWX: Sending out ";
    for($i=0;$i<length($cmd);$i++){  
      $j=int(ord(substr($cmd,$i,1))/16);
      $k=ord(substr($cmd,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res;
  } 
	
  my $count_out = $owx_hwdevice->write($cmd);

  Log 1, "OWX: Write incomplete $count_out ne ".(length($cmd))."" if ( $count_out != length($cmd) );
  #-- sleeping for some time
  select(undef,undef,undef,0.01);
 
  #-- read the data
  my ($count_in, $string_in) = $owx_hwdevice->read(48);
    
  if( $owx_debug > 2){
    my $res = "OWX: Receiving ";
    for($i=0;$i<$count_in;$i++){  
      $j=int(ord(substr($string_in,$i,1))/16);
      $k=ord(substr($string_in,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res;
  }
	
  #-- sleeping for some time
  select(undef,undef,undef,0.01);
 
  return($string_in);
}

########################################################################################
# 
# OWX_ReadBit_9097 - Read 1 bit from 1-wire bus  (Fig. 5/6 from Maxim AN214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub OWX_ReadBit_9097 ($) {
  my ($hash) = @_;
  
  #-- set baud rate to 115200 and query!!!
  my $sp1="\xFF";
  $owx_baud=115200;
  my $res=OWX_Query_9097($hash,$sp1);
  $owx_baud=9600;
  #-- process result
  if( substr($res,0,1) eq "\xFF" ){
    return 1;
  } else {
    return 0;
  } 
}

########################################################################################
# 
# OWX_Reset_9097 - Reset the 1-Wire bus (Fig. 4 of Maxim AN192)
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Reset_9097 ($) {

  my ($hash)=@_;
  my $cmd="";
    
  #-- Reset command \xF0
  $cmd="\xF0";
  #-- write 1-Wire bus
  my $res =OWX_Query_9097($hash,$cmd);
  #-- TODO: process result
  #-- may vary between 0x10, 0x90, 0xe0
  return 1;
}

########################################################################################
#
# OWX_Search_9097 - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub OWX_Search_9097 ($$) {

  my ($hash,$mode)=@_;
  
  my ($sp1,$sp2,$response,$search_direction,$id_bit_number);
    
  #-- Response search data parsing operates bitwise
  $id_bit_number = 1;
  my $rom_byte_number = 0;
  my $rom_byte_mask = 1;
  my $last_zero = 0;
      
  #-- issue search command
  $owx_baud=115200;
  $sp2="\x00\x00\x00\x00\xFF\xFF\xFF\xFF";
  $response = OWX_Query_9097($hash,$sp2);
  $owx_baud=9600;
  #-- issue the normal search command \xF0 or the alarm search command \xEC 
  #if( $mode ne "alarm" ){
  #  $sp1 = 0xF0;
  #} else {
  #  $sp1 = 0xEC;
  #}
      
  #$response = OWX_TouchByte($hash,$sp1); 

  #-- clear 8 byte of device id for current search
  @owx_ROM_ID =(0,0,0,0 ,0,0,0,0); 

  while ( $id_bit_number <= 64) {
    #loop until through all ROM bytes 0-7  
    my $id_bit     = OWX_TouchBit_9097($hash,1);
    my $cmp_id_bit = OWX_TouchBit_9097($hash,1);
     
    #print "id_bit = $id_bit, cmp_id_bit = $cmp_id_bit\n";
     
    if( ($id_bit == 1) && ($cmp_id_bit == 1) ){
      #print "no devices present at id_bit_number=$id_bit_number \n";
      next;
    }
    if ( $id_bit != $cmp_id_bit ){
      $search_direction = $id_bit;
    } else {
      # hä ? if this discrepancy if before the Last Discrepancy
      # on a previous next then pick the same as last time
      if ( $id_bit_number < $owx_LastDiscrepancy ){
        if (($owx_ROM_ID[$rom_byte_number] & $rom_byte_mask) > 0){
          $search_direction = 1;
        } else {
          $search_direction = 0;
        }
      } else {
        # if equal to last pick 1, if not then pick 0
        if ($id_bit_number == $owx_LastDiscrepancy){
          $search_direction = 1;
        } else {
          $search_direction = 0;
        }   
      }
      # if 0 was picked then record its position in LastZero
      if ($search_direction == 0){
        $last_zero = $id_bit_number;
        # check for Last discrepancy in family
        if ($last_zero < 9) {
          $owx_LastFamilyDiscrepancy = $last_zero;
        }
      }
    }
    # print "search_direction = $search_direction, last_zero=$last_zero\n";
    # set or clear the bit in the ROM byte rom_byte_number
    # with mask rom_byte_mask
    #print "ROM byte mask = $rom_byte_mask, search_direction = $search_direction\n";
    if ( $search_direction == 1){
      $owx_ROM_ID[$rom_byte_number] |= $rom_byte_mask;
    } else {
      $owx_ROM_ID[$rom_byte_number] &= ~$rom_byte_mask;
    }
    # serial number search direction write bit
    $response = OWX_WriteBit_9097($hash,$search_direction);
    # increment the byte counter id_bit_number
    # and shift the mask rom_byte_mask
    $id_bit_number++;
    $rom_byte_mask <<= 1;
    #-- if the mask is 0 then go to new rom_byte_number and
    if ($rom_byte_mask == 256){
      $rom_byte_number++;
      $rom_byte_mask = 1;
    } 
    $owx_LastDiscrepancy = $last_zero;
  }
  return 1; 
}

########################################################################################
# 
# OWX_TouchBit_9097 - Write/Read 1 bit from 1-wire bus  (Fig. 5-8 from Maxim AN 214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub OWX_TouchBit_9097 ($$) {
  my ($hash,$bit) = @_;
  
  my $sp1;
  #-- set baud rate to 115200 and query!!!
  if( $bit == 1 ){
    $sp1="\xFF";
  } else {
    $sp1="\x00";
  }
  $owx_baud=115200;
  my $res=OWX_Query_9097($hash,$sp1);
  $owx_baud=9600;
  #-- process result
  my $sp2=substr($res,0,1);
  if( $sp1 eq $sp2 ){
    return 1;
  }else {
    return 0;
  }
}

########################################################################################
# 
# OWX_TouchByte_9097 - Write/Read 8 bit from 1-wire bus 
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub OWX_TouchByte_9097 ($$) {
  my ($hash,$byte) = @_;
  
  my $loop;
  my $result=0;
  my $bytein=$byte;
  
  for( $loop=0; $loop < 8; $loop++ ){
    #-- shift result to get ready for the next bit
    $result >>=1;
    #-- if sending a 1 then read a bit else write 0
    if( $byte & 0x01 ){
      if( OWX_ReadBit_9097($hash) ){
        $result |= 0x80;
      }
    } else {
      OWX_WriteBit_9097($hash,0);
    }
    $byte >>= 1;
  }
  return $result;
}

########################################################################################
# 
# OWX_WriteBit_9097 - Write 1 bit to 1-wire bus  (Fig. 7/8 from Maxim AN 214)
#
# Parameter hash = hash of bus master
#
# Return bit value
#
########################################################################################

sub OWX_WriteBit_9097 ($$) {
  my ($hash,$bit) = @_;
  
  my $sp1;
  #-- set baud rate to 115200 and query!!!
  if( $bit ==1 ){
    $sp1="\xFF";
  } else {
    $sp1="\x00";
  }
  $owx_baud=115200;
  my $res=OWX_Query_9097($hash,$sp1);
  $owx_baud=9600;
  #-- process result
  if( substr($res,0,1) eq $sp1 ){
    return 1;
  } else {
    return 0;
  } 
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a COC/CUNO interface
#
########################################################################################
# 
# OWX_Complex_CCC - Send match ROM, data block and receive bytes as response
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

sub OWX_Complex_CCC ($$$$) {
  my ($hash,$owx_dev,$data,$numread) =@_;
  
  my $select;
  my $res = "";
  
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- has match ROM part
  if( $owx_dev ){
    #-- ID of the device
    my $owx_rnf = substr($owx_dev,3,12);
    my $owx_f   = substr($owx_dev,0,2);

    #-- 8 byte 1-Wire device address
    my @owx_ROM_ID  =(0,0,0,0 ,0,0,0,0); 
    #-- from search string to reverse string id
    $owx_dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $owx_ROM_ID[7-$i]=substr($owx_dev,2*$i,2);
    }
    $select=sprintf("Om%s%s%s%s%s%s%s%s",@owx_ROM_ID); 
    Log 3,"OWX: Sending match ROM to COC/CUNO ".$select
       if( $owx_debug > 1);
    #--
    CUL_SimpleWrite($owx_hwdevice, $select);
    my ($err,$ob) = OWX_ReadAnswer_CCC($owx_hwdevice);
    #-- padding first 9 bytes into result string, since we have this 
    #   in the serial interfaces as well
    $res .= "000000000";
  }
  #-- has data part
  if ( $data ){
    OWX_Send_CCC($hash,$data);
    $res .= $data;
  }
  #-- has receive part
  if( $numread > 0 ){
    #$numread += length($data);
    Log 3,"COC/CUNO is expected to deliver $numread bytes"
      if( $owx_debug > 1);
    $res.=OWX_Receive_CCC($hash,$numread);
  }
  Log 3,"OWX: returned from COC/CUNO $res"
    if( $owx_debug > 1);
  return $res;
}

########################################################################################
#
# OWX_Discover_CCC - Discover devices on the 1-Wire bus via internal firmware
#
# Parameter hash = hash of bus master
#
# Return 0  : error
#        1  : OK
#
########################################################################################

sub OWX_Discover_CCC ($) {
  
  my ($hash) = @_;
  my $res;
  
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- zero the array
  @{$hash->{DEVS}}=();
  #-- reset the busmaster
  OWX_ReInit_CCC($hash,0);
  #-- get the devices
  CUL_SimpleWrite($owx_hwdevice, "Oc");
  select(undef,undef,undef,0.5);
  my ($err,$ob) = OWX_ReadAnswer_CCC($owx_hwdevice);
  if( $ob ){
    Log 3,"OWX: Answer to ".$owx_hwdevice->{NAME}." device search is ".$ob;
    foreach my $dx (split(/\n/,$ob)){
      next if ($dx !~ /^\d\d?\:[0-9a-fA-F]{16}/);
      $dx =~ s/\d+\://;
      my $ddx = substr($dx,14,2).".";
      #-- reverse data from culfw
      for( my $i=1;$i<7;$i++){
        $ddx .= substr($dx,14-2*$i,2);
      }
      $ddx .= ".".substr($dx,0,2);
      push (@{$hash->{DEVS}},$ddx);
    }
    return 1;
  } else {
    Log 1, "OWX: No answer to ".$owx_hwdevice->{NAME}." device search";
    return 0;
  }
}

########################################################################################
#
# OWX_ReadAnswer_CCC - Replacement for CUL_ReadAnswer for better control
# 
# Parameter: hash = hash of bus master 
#
# Return: string received 
#
########################################################################################

sub
OWX_ReadAnswer_CCC($)
{
  my ($hash) = @_;
  
  my $type = $hash->{TYPE};

  my $arg ="";
  my $anydata=0;
  my $regexp =undef;
   
  my ($mculdata, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
  for(;;) {
      return ("Device lost when reading answer for get $arg", undef)
        if(!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        return("OWX_ReadAnswer_CCC $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

 

    if($buf) {
      Log 5, "CUL/RAW (ReadAnswer): $buf";
      $mculdata .= $buf;
    }

    # \n\n is socat special
    if($mculdata =~ m/\r\n/ || $anydata || $mculdata =~ m/\n\n/ ) {
      if($regexp && $mculdata !~ m/$regexp/) {
        CUL_Parse($hash, $hash, $hash->{NAME}, $mculdata, $hash->{initString});
      } else {
        return (undef, $mculdata)
      }
    }
  }

}

########################################################################################
#
# OWX_Receive_CCC - Read data from the 1-Wire bus
# 
# Parameter: hash = hash of bus master, numread = number of bytes to read
#
# Return: string received 
#
########################################################################################

sub OWX_Receive_CCC ($$) {
  my ($hash,$numread) = @_;
  
  my $res="";
  my $res2="";
  
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  for( 
  my $i=0;$i<$numread;$i++){
  #Log 1, "Sending $owx_hwdevice->{NAME}: OrB";
  #my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "OrB"));
  CUL_SimpleWrite($owx_hwdevice, "OrB");
  select(undef,undef,undef,0.01);
  my ($err,$ob) = OWX_ReadAnswer_CCC($owx_hwdevice);
  #Log 1, "Answer from $owx_hwdevice->{NAME}:$ob: ";

    #-- process results  
    if( !(defined($ob)) ){
      return "";
    #-- four bytes received makes one byte of result
    }elsif( length($ob) == 4 ){
      $res  .= sprintf("%c",hex(substr($ob,0,2)));
      $res2 .= "0x".substr($ob,0,2)." ";
    #-- 11 bytes received makes one byte of result
    }elsif( length($ob) == 11 ){
      $res  .= sprintf("%c",hex(substr($ob,9,2)));
      $res2 .= "0x".substr($ob,9,2)." ";
    #-- 18 bytes received from CUNO 
    }elsif( length($ob) == 18 ){
    
    my $res = "OWX: Receiving 18 bytes from CUNO: $ob\n";
    for(my $i=0;$i<length($ob);$i++){  
      my $j=int(ord(substr($ob,$i,1))/16);
      my $k=ord(substr($ob,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    Log 3, $res;
    
    #$numread++;
    #-- 20 bytes received = leftover from match
    }elsif( length($ob) == 20 ){
      $numread++;
    }else{
      Log 1,"OWX: Received unexpected number of ".length($ob)." bytes on bus ".$owx_hwdevice->{NAME};
    } 
  }
  Log 3, "OWX: Received $numread bytes = $res2 on bus ".$owx_hwdevice->{NAME}
     if( $owx_debug > 1);
  
  return($res);
}

########################################################################################
# 
# OWX_Reset_CCC - Reset the 1-Wire bus 
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_Reset_CCC ($) { 
  my ($hash) = @_;
  
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "ORb"));
  
  if( substr($ob,9,4) eq "OK:1" ){
    return 1;
  }else{
    return 0
  }
}

########################################################################################
# 
# OWX_ReInit_CCC - Reset the 1-Wire bus master chip or subsystem
#
# Parameter hash = hash of bus master
#           typ = 0 for bus master, 1 for subsystem
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub OWX_ReInit_CCC ($$) { 
  my ($hash,$type) = @_;
  
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  if ( $type eq "0") {
    my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "ORm"));
    return 0 if( !defined($ob) );
    return 0 if( length($ob) < 13);
    if( substr($ob,9,4) eq "OK" ){
      return 1;
    }else{
      return 0
    }
  }elsif( $type eq "1" ){
   my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "Oi"));
   #Log 1, "Answer of sending Oi to ".$owx_hwdevice->{NAME}." was $ob";
   return 1;
  }
}

#########################################################################################
# 
# OWX_Send_CCC - Send data block  
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub OWX_Send_CCC ($$) {
  my ($hash,$data) =@_;
  
  my ($i,$j,$k);
  my $res  = "";
  my $res2 = "";

  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  for( $i=0;$i<length($data);$i++){
    $j=int(ord(substr($data,$i,1))/16);
    $k=ord(substr($data,$i,1))%16;
  	$res  =sprintf "OwB%1x%1x ",$j,$k;
    $res2.=sprintf "0x%1x%1x ",$j,$k;
    CUL_SimpleWrite($owx_hwdevice, $res);
  } 
  Log 3,"OWX: Send to COC/CUNO $res2"
     if( $owx_debug > 1);
}

########################################################################################
#
# OWX_Verify_CCC - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not
#
########################################################################################

sub OWX_Verify_CCC ($$) {
  my ($hash,$dev) = @_;
  
  my $i;
    
  #-- get the interface
  my $owx_hwdevice  = $hash->{HWDEVICE};
  
  #-- Ask the COC/CUNO 
  CUL_SimpleWrite($owx_hwdevice, "OCf");
  #-- sleeping for some time
  select(undef,undef,undef,3);
  CUL_SimpleWrite($owx_hwdevice, "Oc");
  select(undef,undef,undef,0.5);
  my ($err,$ob) = OWX_ReadAnswer_CCC($owx_hwdevice);
  if( $ob ){
    foreach my $dx (split(/\n/,$ob)){
      next if ($dx !~ /^\d\d?\:[0-9a-fA-F]{16}/);
      $dx =~ s/\d+\://;
      my $ddx = substr($dx,14,2).".";
      #-- reverse data from culfw
      for( my $i=1;$i<7;$i++){
        $ddx .= substr($dx,14-2*$i,2);
      }
      $ddx .= ".".substr($dx,0,2);
      return 1 if( $dev eq $ddx);
    }
  }
  return 0;
} 


1;

=pod
=begin html

<a name="OWX"></a>
        <h3>OWX</h3>
        <p> FHEM module to commmunicate with 1-Wire bus devices</p>
        <ul>
            <li>via an active DS2480/DS2482/DS2490/DS9097U bus master interface attached to an USB
                port or </li>
            <li>via a passive DS9097 interface attached to an USB port or</li>
            <li>via a network-attached CUNO or through a COC on the RaspBerry Pi</li>
            <li>via an Arduino running OneWireFirmata attached to USB</li>
        </ul> Internally these interfaces are vastly different, read the corresponding <a
            href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire"> Wiki pages </a>
        <br />
        <br />
        <h4>Example</h4><br />
        <p>
            <code>define OWio1 OWX /dev/ttyUSB1</code>
            <br />
            <code>define OWio2 OWX COC</code>
            <br />
            <code>define OWio3 OWX 10</code>
            <br />
        </p>
        <br />
        <a name="OWXdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWX &lt;serial-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX &lt;cuno/coc-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX &lt;arduino-pin&gt;</code>
            <br /><br /> Define a 1-Wire interface to communicate with a 1-Wire bus.<br />
            <br />
        </p>
        <ul>
            <li>
                <code>&lt;serial-device&gt;</code> The serial device (e.g. USB port) to which the
                1-Wire bus is attached.</li>
            <li>
                <code>&lt;cuno-device&gt;</code> The previously defined CUNO to which the 1-Wire bus
                is attached. </li>
            <li>
                <code>&lt;arduino-pin&gt;</code> The pin of the previous defined <a href="#FRM">FRM</a>
                to which the 1-Wire bus is attached. If there is more than one FRM device defined
                use <a href="#IODev">IODev</a> attribute to select which FRM device to use.</li>
        </ul>
        <br />
        <a name="OWXset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owx_interval">
                    <code>set &lt;name&gt; interval &lt;value&gt;</code>
                </a>
                <br /><br /> sets the time period in seconds for "kicking" the 1-Wire bus (default
                is 300 seconds). This means: <ul>
                    <li>With 1-Wire bus interfaces that do not supply power to the 1-Wire bus (attr
                        buspower parasitic), the 1-Wire bus is reset at these intervals. </li>
                    <li>With 1-Wire bus interfaces that supply power to the 1-Wire bus (attr
                        buspower = real), all temperature measurement devices on the bus receive the
                        command to start a temperature conversion (saves a lot of time when reading) </li>
                    <li>With 1-Wire bus interfaces that contain a busmaster chip, the response to a
                        reset pulse contains information about alarms.</li>
                </ul><br />
            </li>
            <li><a name="owx_followAlarms">
                    <code>set &lt;name&gt; followAlarms on|off</code>
                </a>
                <br /><br /> instructs the module to start an alarm search in case a reset pulse
                discovers any 1-Wire device which has the alarm flag set. </li>
        </ul>
        <br />
        <a name="OWXget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owx_alarms"></a>
                <code>get &lt;name&gt; alarms</code>
                <br /><br /> performs an "alarm search" for devices on the 1-Wire bus and, if found,
                generates an event in the log (not with CUNO). </li>
            <li><a name="owx_devices"></a>
                <code>get &lt;name&gt; devices</code>
                <br /><br /> redicovers all devices on the 1-Wire bus. If a device found has a
                previous definition, this is automatically used. If a device is found but has no
                definition, it is autocreated. If a defined device is not on the 1-Wire bus, it is
                autodeleted. </li>
        </ul>
        <br />
        <a name="OWXattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="OWXbuspower"><code>attr &lt;name&gt; buspower real|parasitic</code></a>
                <br />tells FHEM whether power is supplied to the 1-Wire bus or not.</li>
            <li><code>attr &lt;name&gt; IODev <FRM-device></code>
                <br />assignes a specific FRM-device to OWX. Required only if there is more than one FRM defined.</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>

=end html
=cut
