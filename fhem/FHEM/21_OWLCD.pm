########################################################################################
#
# OWLCD.pm
#
# FHEM module to commmunicate with the 1-Wire LCD hardware
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
# define <name> OWLCD <ROM_ID> or FF.<ROM_ID>
#
# where <name> may be replaced by any name string 
#  
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#
# get <name> id       => FF.ROM_ID.CRC 
# get <name> present  => 1 if device present, 0 if not
# get <name> gpio     => current state of the gpio pins (15 = all off, 0 = all on)
# get <name> counter  => four values (16 Bit) of the gpio counter
# get <name> version  => firmware version of the LCD adapter
# get <name> memory <page> => get one of the internal memory pages 0..6
# get <name> version  => OWX version number
#
# set <name> alert red|yellow|beep|none  => set one of the alert states (gpio pins)
# set <name> icon <num> on|off|blink  => set one of the icons 0..14
# set <name> icon 15 0..6             => set icon no. 15 in one of its values
# set <name> line <line> <string(s)>  => set one of the display lines 0..3
# set <name> memory <page> <string(s) => set one of the internal memory pages 0..6
# set <name> gpio                     => state of the gpio pins 0..7 
# set <name> backlight on|off         => set backlight on or off
# set <name> lcd       on|off         => set LCD power on or off
# set <name> reset                    => reset the display
# set <name> test                     => display a test content
#
# Careful: Not ASCII ! strange Codepage
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

use vars qw{%attr %defs %modules $readingFnAttributes $init_done};
use strict;
use warnings;
sub Log($$);

my $owx_version="3.34";
#-- controller may be HD44780 or KS0073 
#   these values have to be changed for different display 
#   geometries or memory maps
my $lcdcontroller = "KS0073";
my $lcdlines      = 4;
my $lcdchars      = 20;
my @lcdpage       = (0,32,64,96);
#my @lcdpage       = (0,64,20,84);

#-- declare variables
my %gets = (
  "present"     => "",
  "id"          => "",
  "memory"      => "",
  "gpio"        => "",
  "counter"     => "",
  "version"     => ""
  #"register"    => "",
  #"data"        => ""
);
my %sets    = (
  "icon"        => "",
  "line"        => "",
  "alert"       => "",
  "memory"      => "",
  "gpio"        => "",
  "backlight"   => "",
  "lcd"         => "",
  "reset"       => "",
  "test"        => ""

);
my %updates = ();
 
########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWLCD
#
########################################################################################
#
# OWLCD_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWLCD_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "OWLCD_Define";
  $hash->{UndefFn}  = "OWLCD_Undef";
  $hash->{GetFn}    = "OWLCD_Get";
  $hash->{SetFn}    = "OWLCD_Set";
  $hash->{AttrFn}   = "OWLCD_Attr";
  my $attlist       = "IODev do_not_notify:0,1 showtime:0,1 loglevel:0,1,2,3,4,5 ".
                      "";
  $hash->{AttrList} = $attlist; 

  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}

#########################################################################################
#
# OWLCD_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWLCD_Define ($$) {
  my ($hash, $def) = @_;
  
  #-- define <name> OWLCD <ROM_ID>
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$fam,$id,$crc,$ret);
  
  #-- default
  $name          = $a[0];
  $ret           = "";

  #-- check syntax
  return "OWLCD: Wrong syntax, must be define <name> OWLCD <id>"
       if(int(@a) !=3 );
       
  #-- check id
  if(  $a[2] =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $id            = $a[2];
  } elsif(  $a[2] =~ m/^FF\.[0-9|a-f|A-F]{12}$/ ) {
    $id            = substr($a[2],3);
  } else {    
    return "OWLCD: $a[0] ID $a[2] invalid, specify a 12 digit or 2.12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC("FF.".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = "FF.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = "FF";
  $hash->{PRESENT}    = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( (!defined($hash->{IODev}->{NAME})) || (!defined($hash->{IODev})) || (!defined($hash->{IODev}->{PRESENT})) ){
    return "OWSWITCH: Warning, no 1-Wire I/O device found for $name.";
  }
  if( $hash->{IODev}->{PRESENT} != 1 ){
    return "OWSWITCH: Warning, 1-Wire I/O device ".$hash->{IODev}->{NAME}." not present for $name.";
  }
  $modules{OWLCD}{defptr}{$id} = $hash;
  
  $hash->{STATE} = "Defined";
  Log 3, "OWLCD:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  #-- OWX interface
  if( $interface eq "OWX" ){
    OWXLCD_InitializeDevice($hash);
    #-- set backlight on
    OWXLCD_SetFunction($hash,"bklon",0); 
    #-- erase all icons
    OWXLCD_SetIcon($hash,0,0);
    #-- erase alarm state
    OWXLCD_SetFunction($hash,"gpio",15);
  #-- Unknown interface
  }else{
    return "OWLCD: Wrong IODev type $interface";
  }
  $hash->{STATE} = "Initialized";
  return undef; 
}

#######################################################################################
#
# OWLCD_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWLCD_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
 # if ( $do eq "set") {
 # 	ARGUMENT_HANDLER: {
 # 	  #-- empty so far
 # 	};
 #} elsif ( $do eq "del" ) {
 # 	ARGUMENT_HANDLER: {
 # 	  #-- empty so far
 # 	}
 # }
  return $ret;
}

########################################################################################
#
# OWLCD_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWLCD_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = undef;
  my $ret     = "";
  my $offset;
  my $factor;

   #-- check syntax
  return "OWLCD: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  return "OWLCD: Get with unknown argument $a[1], choose one of ".join(" ", sort keys %gets)
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
  
  #-- get gpio states
  if($a[1] eq "gpio") {
    $value = OWXLCD_Get($hash,"gpio");
    return "$name.gpio => $value";
  } 
  
  #-- get gpio counters
  if($a[1] eq "counter") {
    $value = OWXLCD_Get($hash,"counter");
    return "$name.counter => $value";
  } 
  
  #-- get version
  if($a[1] eq "version") {
    $value = OWXLCD_Get($hash,"version");
    return "$name.version => $owx_version (LCD firmware $value)";
  }
  
  #-- get EEPROM content
  if($a[1] eq "memory") {
   my $page  = ($a[2] =~ m/\d/) ? int($a[2]) : 0;
   Log 1,"Calling GetMemory with page $page";
    $value = OWXLCD_GetMemory($hash,$page);
    return "$name $reading $page => $value";
  }  
}

#######################################################################################
#
# OWLCD_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWLCD_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  my ($line,$icon,$i);
  
  #-- for the selector: which values are possible
  return join(" ", keys %sets)
     if ( (@a == 2) && !(($key eq "reset") || ($key eq "test")) );
  
  #-- check argument
  if( !defined($sets{$a[1]}) ){
    return "OWLCD: Set with unknown argument $a[1]";
  }
  
  #-- check syntax for setting line
  if( $key eq "line" ){
    return "OWLCD: Set needs one or two parameters when setting line value: <#line> <string>"
      if( int(@a)<3 );
    $line  = ($a[2] =~ m/\d/) ? $a[2] : 0;
    $value = $a[3]; 
    if( defined($value) ){
      for( $i=4; $i< int(@a); $i++){
        $value .= " ".$a[$i];
      }
    }else{
      $value="";
    }
  #-- check syntax for setting memory
  } elsif( $key eq "memory" ){
    return "OWLCD: Set needs two parameters when setting memory page: <#page> <string>"
      if( int(@a)<4 );
    $line  = ($a[2] =~ m/\d/) ? int($a[2]) : 0;
    $value = $a[3]; 
    for( $i=4; $i< int(@a); $i++){
      $value .= " ".$a[$i];
    }
  #-- check syntax for setting alert
  } elsif( $key eq "alert" ){
    return "OWLCD: Set needs a parameter when setting alert: <type>/none/off"
      if( int(@a)<3 );
  #-- check syntax for setting icon
  } elsif ( $key eq "icon" ){
    if( ($a[2] ne "0") && ($a[2] ne "none") ){
      return "OWLCD: Set needs two parameters when setting icon value: <#icon> on/off/blink (resp. 0..5/off/blink for #16)"
        if( (int(@a)!=4) );
      $icon  = ($a[2] =~ m/\d\d?/) ? $a[2] : 0;
      $value = $a[3]; 
    } else {
      return "OWLCD: Set needs only one parameter when resetting icons"
        if( (int(@a)!=3) );
      $icon  = 0;
      $value = "OFF"; 
    }  
  #-- check syntax for reset and test
  } elsif ( ($key eq "reset") || ($key eq "test") ){
    return "OWLCD: Set needs no parameters when setting $key value"
      if( int(@a)!=2 );
  #-- other syntax
  } else {
    return "OWLCD: Set needs one parameter when setting $key value"
      if( int(@a)!=3 );
  }
 
  #-- define vars
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
 
 #-- set gpio ports from all off = to all on = 7
  if($key eq "gpio") {
    #-- check value and write to device
    return "OWLCD: Set with wrong value for gpio port, must be 0 <= gpio <= 7"
      if( ! ((int($value) >= 0) && (int($value) <= 7)) );
    OWXLCD_SetFunction($hash, "gpio", int($value));
    return undef;
  }
  
  #-- set LCD ON or OFF
  if($key eq "lcd") {
    #-- check value and write to device   
    if( uc($value) eq "ON"){
      OWXLCD_SetFunction($hash, "lcdon", 0);
    }elsif( uc($value) eq "OFF" ){
      OWXLCD_SetFunction($hash, "lcdoff", 0);
    } else {
      return "OWLCD: Set with wrong value for lcd, must be on/off"
    }
    return undef;
  }
  
  #-- set LCD Backlight ON or OFF
  if($key eq "backlight") {
    #-- check value and write to device   
    if( uc($value) eq "ON"){
      OWXLCD_SetFunction($hash, "bklon", 0);
    }elsif( uc($value) eq "OFF" ){
      OWXLCD_SetFunction($hash, "bkloff", 0);
    } else {
      return "OWLCD: Set with wrong value for backlight, must be on/off"
    }
    return undef;
  }
  
  #-- reset
  if($key eq "reset") {
    OWXLCD_SetFunction($hash,"reset",0);
    OWXLCD_SetIcon($hash,0,0);
    OWXLCD_SetFunction($hash,"gpio",15);
    return undef;
  }
  
  #-- set icon
  if($key eq "icon") {
    return "OWLCD: Wrong icon type, choose 0..16" 
      if( ( 0 > $icon ) || ($icon > 16) );
    #-- check value and write to device  
    if( $icon == 16 ){
      if( uc($value) eq "OFF" ){
        OWXLCD_SetIcon($hash, 16, 0);
      }elsif( uc($value) eq "BLINK" ){
        OWXLCD_SetIcon($hash, 16, 6);
      }elsif(  ((int($value) > 0) && (int($value) < 6)) ){
        OWXLCD_SetIcon($hash, 16, int($value));
      } else {
        return "OWLCD: Set with wrong value for icon #16, must be 0..5/off/blink"
      }  
    }else{
      if( uc($value) eq "OFF"){
        OWXLCD_SetIcon($hash, $icon, 0);
      }elsif( uc($value) eq "ON" ){
        OWXLCD_SetIcon($hash, $icon, 1);
      }elsif( uc($value) eq "BLINK" ){
        OWXLCD_SetIcon($hash, $icon, 2);
      } else {
        return "OWLCD: Set with wrong value for icon $icon, must be on/off/blink"
      }
    }
    return undef;
  }
  
  #-- set a single LCD line
  if($key eq "line") {
    $value = OWXLCD_Trans($value);
    return "OWLCD: Wrong line number, choose 0..".$lcdlines 
      if( ( 0 > $line ) || ($line > ($lcdlines-1)) );
    return "OWLCD: Wrong line length, must be <= ".$lcdchars 
      if( length($value) > $lcdchars );
    #-- check value and write to device   
     OWXLCD_SetLine($hash,$line,$value);
    return undef;
  }
  
  #-- set memory page 0..6
  if($key eq "memory") {
    return "OWLCD: Wrong page number, choose 0..6" 
      if( (0 > $line) || ($line > 6) );
    return "OWLCD: Wrong line length, must be <=16 " 
      if( length($value) > 16 );
    #-- check value and write to device   
     Log 1,"Calling SetMemory with page $line";
     OWXLCD_SetMemory($hash,$line,$value);
     return undef;
  }
  
  #-- set alert
  if($key eq "alert") {
    if(lc($value) eq "beep") {
      OWXLCD_SetFunction($hash,"gpio",14);
      return undef;
    }elsif(lc($value) eq "red") {
      OWXLCD_SetFunction($hash,"gpio",13);
      return undef;
    }elsif(lc($value) eq "yellow") {
      OWXLCD_SetFunction($hash,"gpio",11);
      return undef;
    }elsif( (lc($value) eq "off") || (lc($value) eq "none") ) {
      OWXLCD_SetFunction($hash,"gpio",15);
      return undef;
    }else{
      return "OWLCD: Set with wrong value for alert type, must be beep/red/yellow/off";
    }
  }
  
  #-- start test
  if($key eq "test") {
    OWXLCD_SetLine($hash,0,"Hallo Welt");
    OWXLCD_SetLine($hash,1,"Mary had a big lamb");
    OWXLCD_SetLine($hash,2,"Solar 4.322 kW ");
    OWXLCD_SetLine($hash,3,"\x5B\x5C\x5E\x7B\x7C\x7E\xBE");
    return undef;
  }
}

########################################################################################
#
# OWLCD_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWLCD_Undef ($) {
  my ($hash) = @_;
  delete($modules{OWLCD}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# OWXLCD_Byte - write a single byte to the LCD device
#
# Parameter hash = hash of device addressed
#           cmd = register or data
#           byte = byte
#
########################################################################################

sub OWXLCD_Byte($$$) {

  my ($hash,$cmd,$byte) = @_;

  my ($select, $select2, $res, $res2, $res3, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);
  
  #=============== write to LCD register ===============================
  if ( $cmd eq "register" ) {
    #-- issue the read LCD register command \x10
    $select = sprintf("\x10%c",$byte);
  #=============== write to LCD data ===============================
  }elsif ( $cmd eq "data" ) {
    #-- issue the read LCD data command \x12
    $select = sprintf("\x12%c",$byte);
  #=============== wrong value requested ===============================
  } else {
    return "OWXLCD: Wrong byte write attempt";
  } 
 
  #-- write to device
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for writing a byte"; 
  }
  
  return undef;
}

########################################################################################
#
# OWXLCD_Get - get values from the LCD device
#
# Parameter hash = hash of device addressed
#           cmd  = command string
#
########################################################################################

sub OWXLCD_Get($$) {

  my ($hash,$cmd,$value) = @_;

  my ($select, $select2, $len, $addr, $res, $res2, $res3, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);

  #=============== fill scratch with gpio ports ===============================
  if ( $cmd eq "gpio" ) {
    #-- issue the read GPIO command \x22 (1 byte)
    $select = "\x22";
    $len     = 1;
  #=============== fill scratch with gpio counters ===============================
  }elsif ( $cmd eq "counter" ) {
    #-- issue the read counter command \x23 (8 bytes)
    $select = "\x23";
    $len     = 8;
  #=============== fill scratch with version ===============================
  }elsif ( $cmd eq "version" ) {
    #-- issue the read version command \x41
    $select = "\x41";
    $len     = 16;
  } else {
    return "OWXLCD: Wrong get attempt";
  } 
  #-- write to device
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for reading"; 
  }
  
  #-- issue the read scratchpad command \xBE
  $select2 = "\xBE";
  #-- write to device
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select2,$len); 
  
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for reading in 2nd step"; 
  }
  
  #-- process results (10 byes or more have been sent)
  $res = substr($res,10);
    
  #=============== gpio ports ===============================
  if ( $cmd eq "gpio" ) {
     return ord($res);
  #=============== gpio counters ===============================
  }elsif ( $cmd eq "counter" ) {
    for( $i=0; $i<4; $i++){
      $data[$i] = ord(substr($res,2*$i+1,1))*256+ord(substr($res,2*$i,1));
    }
    return join(" ",@data); 
  #=============== version ===============================
  }elsif ( $cmd eq "version" ) {
    return $res;
  }
   
  return $res;
}

########################################################################################
#
# OWXLCD_GetMemory - get memory page from LCD device (EXPERIMENTAL)
#
# Parameter hash = hash of device addressed
#           page = memory page address
#
########################################################################################

sub OWXLCD_GetMemory($$) {

  my ($hash,$page) = @_;

  my ($select, $res, $res2, $res3);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);

  #-- issue the match ROM command \x55 and the copy eeprom to scratchpad command \x4E
  #Log 1," page read is ".$page;
  $select = sprintf("\4E%c\x10\x37",$page);  
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
   
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for reading"; 
  }
  
  #-- sleeping for some time
  #select(undef,undef,undef,0.5);
  
  #-- issue the match ROM command \x55 and the read scratchpad command \xBE
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,"\xBE",16); 
  
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for reading in 2nd step"; 
  }
  
  #-- process results (10 bytes or more have been sent)
  $res2 = substr($res,11,16);
   
  #Log 1," Having received ".length($res)." bytes"; 
  return $res2;
}

########################################################################################
#
# OWXLCD_InitializeDevice - initialize the display
#
# Parameter hash  = hash of device addressed
#
########################################################################################

sub OWXLCD_InitializeDevice($) {
  my ($hash) = @_;

  my ($i,$data,$select, $res);
    
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};

  #-- supposedly we do not need to do anything with a HD44780
  if( $lcdcontroller eq "HD44780"){
    return undef;
  #-- need some additional sequence for KS0073
  }elsif ( $lcdcontroller eq "KS0073"){
 
    #-- Function Set: 4 bit data size, RE => 0 = \x20
    #OWXLCD_Byte($hash,"register",32); 

    #-- Entry Mode Set: cursor auto increment = \x06
    #OWXLCD_Byte($hash,"register",6);

    #-- Function Set: 4 bit data size, RE => 1, blink Enable = \x26
    OWXLCD_Byte($hash,"register",38);
    
    #-- Ext. Function Set: 4 line mode = \x09
    OWXLCD_Byte($hash,"register",9);

    #-- Function Set: 4 bit data size, RE => 0 = \x20
    OWXLCD_Byte($hash,"register",32);

    #-- Display ON/OFF: display on, cursor off, blink off = \x0C
    OWXLCD_Byte($hash,"register",12);

    #-- Clear Display 
    OWXLCD_Byte($hash,"register",1);
    
    return undef;
  #-- or else
  } else {
    return "OWXLCD: Wrong LCD controller type";
  }
 
}  

########################################################################################
#
# OWXLCD_SetFunction - write state and values of the LCD device
#
# Parameter hash  = hash of device addressed
#           cmd   = command string
#           value = data value
#
########################################################################################

sub OWXLCD_SetFunction($$$) {

  my ($hash,$cmd,$value) = @_;

  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);
   
  #=============== set gpio ports ===============================
  if ( $cmd eq "gpio" ) {
    #-- issue the write GPIO command 
    #   \x21 followed by the data value (= integer 0 - 7)
    $select = sprintf("\x21%c",$value); 
  #=============== switch LCD on ===============================
  }elsif ( $cmd eq "lcdon" ) {
    #-- issue the lcd on cmd
    $select = "\x03";
  #=============== switch LCD off ===============================
  }elsif ( $cmd eq "lcdoff" ) {
    #-- issue the lcd off cmd
    $select = "\x05";
  #=============== switch LCD backlight on ===============================
  }elsif ( $cmd eq "bklon" ) {
    #-- issue the backlight on cmd
    $select = "\x08";
  #=============== switch LCD backlight off ===============================
  }elsif ( $cmd eq "bkloff" ) {
    #-- issue the backlight off cmd
    $select = "\x07";
  #=============== switch LCD backlight off ===============================
  }elsif ( $cmd eq "reset" ) {
    #-- issue the clear LCD command
    $select = "\x49";
  #=============== wrong write attempt ===============================
  } else {
    return "OWXLCD: Wrong function selected";
  } 
  
  #-- write to device
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  #-- process results
  if( $res eq 0 ){
    return "OWLCD: Device $owx_dev not accessible for writing"; 
  }
  
  return undef;
}

########################################################################################
#
# OWXLCD_SetIcon - set one of the icons
#
# Parameter hash  = hash of device addressed
#           icon  = address of the icon used = 0,1 .. 16 (0 = all off)
#           value = data value: 0 = off, 1 = on, 2 = blink
#                   for battery icon 16: 0 = off, 1 = empty ... 5 = full, 6 = empty blink
#
########################################################################################

sub OWXLCD_SetIcon($$$) {
  my ($hash,$icon,$value) = @_;

  my ($i,$data,$select, $res);
    
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};

  #-- only for KS0073
  if ( $lcdcontroller eq "KS0073"){
    
    #-- write 16 zeros to erase all icons
    if( $icon == 0){   
      #-- 4 bit data size, RE => 1, blink Enable = \x26     
      $select = "\x10\x26";
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);
      
      #-- SEGRAM addres to 0 = \x40,
      $select = "\x10\x40";
      #-- write 16 zeros to scratchpad
      $select .= "\x4E\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);
      
      #-- issue the copy scratchpad to LCD command \x48
      $select="\x48";  
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);
    } else {
      #-- determine data value
      if( int($icon) != 16 ){
        if( $value == 0 ){
          $data = 0;
        } elsif ( $value == 1) {
          $data = 16;
        } elsif ( $value == 2) {
          $data = 80;
        } else {
          return "OWXLCD: Wrong data value $value for icon $icon";
        }
      } else {
        if( $value == 0 ){
          $data = 0;
        } elsif ( $value == 1) {
          $data = 16;
        } elsif ( $value == 2) {
          $data = 24;
        } elsif ( $value == 3) {
          $data = 28;
        } elsif ( $value == 4) {
          $data = 30;
        } elsif ( $value == 5) {
          $data = 31;
        } elsif ( $value == 6) {
          $data = 80;
        } else {
          return "OWXLCD: Wrong data value $value for icon $icon";
        }
      }
      #-- 4 bit data size, RE => 1, blink Enable = \x26
      $select = "\x10\x26";
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);
     
      #-- SEGRAM addres to 0 = \x40 + icon address
      $select = sprintf("\x10%c",63+$icon);
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);
      
      #-- data
      $select = sprintf("\x12%c",$data);
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,0);   
    }  
    
    #-- return to normal state
    $select = "\x10\x20";
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
  #-- or else
  } else {
    return "OWXLCD: Wrong LCD controller type";
  }
}

########################################################################################
#
# OWXLCD_SetLine - set one of the display lines
#
# Parameter hash  = hash of device addressed
#           line  = line number (0..3)
#           msg   = data string to be written
#
########################################################################################

sub OWXLCD_SetLine($$$) {

  my ($hash,$line,$msg) = @_;
  
  my ($select, $res, $res2, $res3, $i, $msgA, $msgB);
  $res2 = "";
  $line = int($line);
  $msg =   defined($msg) ? $msg : "";
  
  $msg = OWXLCD_Trans($msg);
 
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  #-- split if longer than 16 bytes, fill each with blanks
  #   has already been checked to be <= $lcdchars
  if( $lcdchars > 16 ){
    if( length($msg) > 16 ) {
      $msgA = substr($msg,0,16);
      $msgB = substr($msg,16,length($msg)-16);
      for($i = 0;$i<$lcdchars-length($msg);$i++){
        $msgB .= "\x20";
      }
    } else {
      $msgA = $msg;
      for($i = 0;$i<16-length($msg);$i++){
        $msgA .= "\x20";
      }
      for($i = 0;$i<$lcdchars-16;$i++){
        $msgB .= "\x20";
      }
    }
  }else{
    $msgA = $msg;
    for($i = 0;$i<$lcdchars-length($msg);$i++){
      $msgA .= "\x20";
    }
    $msgB = undef;
  }
   
  #-- issue the match ROM command \x55 and the write scratchpad command \x4E
  #   followed by LCD page address and the text 
  $select=sprintf("\x4E%c",$lcdpage[$line]).$msgA;      
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  
  #-- issue the copy scratchpad to LCD command \x48
  $select="\x48";  
  OWX_Reset($master);
  $res3=OWX_Complex($master,$owx_dev,$select,0);
  
  #-- if second string available:
  if( defined($msgB) ) {
    #select(undef,undef,undef,0.005); 
    #-- issue the match ROM command \x55 and the write scratchpad command \x4E
    #   followed by LCD page address and the text 
    $select=sprintf("\x4E%c",$lcdpage[$line]+16).$msgB;      
    OWX_Reset($master);
    $res2=OWX_Complex($master,$owx_dev,$select,0);
   
    #-- issue the copy scratchpad to LCD command \x48
    $select="\x48";  
    OWX_Reset($master);
    $res3=OWX_Complex($master,$owx_dev,$select,0);
  }
  
  #-- process results
  if( ($res eq 0) || ($res2 eq 0) || ($res3 eq 0) ){
    return "OWLCD: Device $owx_dev not accessible for writing"; 
  }
  
  return undef;

}

########################################################################################
#
# OWXLCD_Trans - String translation helper
#
# Parameter msg   = data string to be written
#
########################################################################################

sub OWXLCD_Trans($) {

  my ($msg) = @_;
  
  #-- replace umlaut chars for special codepage
  $msg =~ s/ä/\x7B/g;
  $msg =~ s/ö/\x7C/g;
  $msg =~ s/ü/\x7E/g;
  $msg =~ s/Ä/\x5B/g;
  $msg =~ s/Ö/\x5C/g;
  $msg =~ s/Ü/\x5E/g;
  $msg =~ s/ß/\xBE/g;
  #-- replace other special chars 
  $msg =~s/_/\xC4/g;
  #--take out HTML degree sign
  if( $msg =~ m/.*\&deg\;.*/ ) {
    my @ma = split(/\&deg\;/,$msg);
    $msg = $ma[0]."\x80".$ma[1];
  }
  return $msg;
}

########################################################################################
#
# OWXLCD_SetMemory - set internal nonvolatile memory
#
# Parameter hash  = hash of device addressed
#           page  = page number (0..14)
#           msg   = data string to be written
#
########################################################################################

sub OWXLCD_SetMemory($$$) {

  my ($hash,$page,$msg) = @_;
  
  my ($select, $res, $res2, $res3, $i, $msgA);
  $page = int($page);
  $msg =   defined($msg) ? $msg : "";

  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  #-- fillup with blanks
  $msgA = $msg;
  for($i = 0;$i<16-length($msg);$i++){
    $msgA .= "\x20";
  }
   
  #-- issue the match ROM command \x55 and the write scratchpad command \x4E
  #   followed by LCD page address and the text 
  #Log 1," page written is ".$page;
  $select=sprintf("\x4E\%c",$page).$msgA;         
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,0);
  
  #-- issue the copy scratchpad to EEPROM command \x39 
  OWX_Reset($master);
  $res2=OWX_Complex($master,$owx_dev,"\x39",0);
 
  #-- process results
  if( ($res eq 0) || ($res2 eq 0) ){
    return "OWLCD: Device $owx_dev not accessible for writing"; 
  }
  
  return undef;

}

1;

=pod
=begin html

 <a name="OWLCD"></a>
        <h3>OWLCD</h3>
        <p>FHEM module to commmunicate with the <a
                href="http://www.louisswart.co.za/1-Wire_Overview.html">1-Wire LCD controller</a>
            from Louis Swart (1-Wire family id FF). See also the corresponding <a
                href="http://fhemwiki.de/wiki/1-Wire_Textdisplay">Wiki page.</a><br /><br />
            Note:<br /> This 1-Wire module so far works only with the OWX interface module. Please
            define an <a href="#OWX">OWX</a> device first. <br /></p>
        <br /><h4>Example</h4>
        <p>
            <code>define OWX_LCD OWLCD 9F0700000100</code>
            <br />
        </p>
        <br />
        <a name="OWLCDdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWLCD &lt;id&gt;</code> or <br/>
             <code>define &lt;name&gt; OWLCD FF.&lt;id&gt;</code>
            <br /><br /> Define a 1-Wire LCD device.<br /><br /></p>
        <ul>
            <li>
                <code>&lt;id&gt;</code>
                <br />12-character unique ROM id of the converter device without family id and CRC
                code </li>
        </ul>
        <br />
        <a name="OWLCDset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owlcd_icon">
                    <code>set &lt;name&gt; icon &lt;int&gt; on|off|blink</code></a><br /> Set one of
                the icons 0..14 on, off or blinking</li>
            <li><a name="owlcd_icon2">
                    <code>set &lt;name&gt; icon 15 0..6</code></a><br /> Set icon 15 to one of its
                values</li>
            <li><a name="owlcd_icon3">
                    <code>set &lt;name&gt; icon none</code></a><br /> Set all icons off</li>
            <li><a name="owlcd_line">
                    <code>set &lt;name&gt; line &lt;int&gt; &lt;string&gt;</code></a><br /> Write
                LCD line 0..3 with some content </li>
            <li><a name="owlcd_memory">
                    <code>set &lt;name&gt; memory &lt;page&gt; &lt;string&gt;</code></a><br />Write
                memory page 0..6</li>
            <li><a name="owlcd_gpio">
                    <code>set &lt;name&gt; gpio &lt;value&gt;</code></a><br />Write state for all
                three gpio pins (value = 0..7, for each bit 0=ON, 1=OFF)</li>
            <li><a name="owlcd_bl">
                    <code>set &lt;name&gt; backlight ON|OFF</code></a><br />Switch backlight on or
                off</li>
            <li><a name="owlcd_lcd">
                    <code>set &lt;name&gt; lcd ON|OFF</code></a><br />Switch LCD power on or
                off</li>
            <li><a name="owlcd_gpio">
                    <code>set &lt;name&gt; reset</code></a><br />Reset the display</li>
            <li><a name="owlcd_gpio">
                    <code>set &lt;name&gt; test</code></a><br />Test the display</li>
        </ul>
        <br />
        <a name="owlcdget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owlcd_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owlcd_present">
                    <code>get &lt;name&gt; present</code>
                </a>
                <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
            <li><a name="owlcd_memory2">
                    <code>get &lt;name&gt; memory &lt;page&gt;</code></a><br />Read memory page 0..6 </li>
            <li><a name="owlcd_gpio">
                    <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all four input
                channels (15 = all off, 0 = all on)</li>
            <li><a name="owlcd_counter">
                    <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all four input
                counters (4 x 16 Bit)</li>
            <li><a name="owlcd_version">
                    <code>get &lt;name&gt; version</code></a><br />Obtain firmware version of the
                controller</li>
        </ul>
        <br />
        <a name="owlcdattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#room">room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel"
                    >loglevel</a>, <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut