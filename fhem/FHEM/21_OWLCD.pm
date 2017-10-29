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
# attr <name> lcdgeometry => LCD geometry values are 0-32-64-96 or 0-64-20-84
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
use Time::HiRes qw(gettimeofday);
use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use GPUtils qw(:all);
use ProtoThreads;
no warnings 'deprecated';

sub Log3($$$);

my $owx_version="7.01";
#-- controller may be HD44780 or KS0073 
#   these values can be changed by attribute for different display 
#   geometries or memory maps
my $lcdcontroller = "KS0073";
my $lcdlines      = 4;
my $lcdchars      = 20;
my @lcdpage       = (0,32,64,96); 

#-- declare variables
my %gets = (
  "id"          => ":noArg",
  "memory"      => ":noArg",
  "gpio"        => ":noArg",
  "counter"     => ":noArg",
  "version"     => ":noArg"
  #"register"    => "",
  #"data"        => ""
);
my %sets    = (
  "icon"        => "",
  "line"        => "",
  "memory"      => "",
  "gpio"        => "",
  "gpiobit"     => "",
  "backlight"   => "",
  "lcd"         => "",
  "reset"       => "",
  "test"        => "",
  "initialize"  => ""

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
  $hash->{NotifyFn} = "OWLCD_Notify";
  $hash->{InitFn}   = "OWLCD_Init";
  $hash->{AttrFn}   = "OWLCD_Attr";
  my $attlist       = "IODev do_not_notify:0,1 showtime:0,1 ".
                      "lcdgeometry:0-32-64-96,0-64-20-84 lcdcontroller:KS0073,HD44780 ".
                      $readingFnAttributes;
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

  #-- check syntaxeverywhere, everytime
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
  $hash->{ERRCOUNT}   = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}) or !defined($hash->{IODev}->{NAME}) ){
    return "OWLCD: Warning, no 1-Wire I/O device found for $name.";
  } else {
    $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0; #-- false for now
  }

  $modules{OWLCD}{defptr}{$id} = $hash;
  
  $hash->{STATE} = "Defined";
  Log3 $name,3, "OWLCD:    Device $name defined.";
  
  $hash->{NOTIFYDEV} = "global";
  
  if ($main::init_done) {
    return OWLCD_Init($hash);
  }
  return undef;
}

########################################################################################
#
# OWLCD_Notify - Implements Notify function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWLCD_Notify ($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    OWLCD_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

########################################################################################
#
# OWLCD_Init - Implements Init function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWLCD_Init($) {
  my ($hash) = @_;
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
  } elsif ( $interface eq "OWX_ASYNC" ) {
    eval {
      OWXLCD_InitializeDevice($hash);
      #-- set backlight on
      OWX_ASYNC_Schedule($hash,OWXLCD_PT_SetFunction($hash,"bklon",0));
      #-- erase all icons
      OWX_ASYNC_Schedule($hash,OWXLCD_PT_SetIcon($hash,0,0));
      #-- erase alarm state
      OWX_ASYNC_Schedule($hash,OWXLCD_PT_SetFunction($hash,"gpio",15));
    };
    return GP_Catch($@) if $@;
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
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      $key eq "IODev" and do {
        AssignIoPort($hash,$value);
        if( defined($hash->{IODev}) ) {
          $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0;
          if ($main::init_done) {
            return OWLCD_Init($hash);
          }
        }
        last;
      };
      $key eq "lcdgeometry" and do {
        if( $value     eq "0-32-64-96" ){
          @lcdpage      = (0,32,64,96);
        }elsif( $value eq "0-64-20-84" ){
          @lcdpage      = (0,64,20,84);
        }
        last;
      };
      $key eq "lcdcontroller" and do {
        if( $value      eq "KS0073," ){
          $lcdcontroller = "KS0073";
        }elsif( $value  eq "HD44780" ){
          $lcdcontroller = "HD44780";
        }
        last;
      };
    };
 #} elsif ( $do eq "del" ) {
 # 	ARGUMENT_HANDLER: {
 # 	  #-- empty so far
 # 	}
  }
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
  
  my $reading   = $a[1];
  my $name      = $hash->{NAME};
  my $model     = $hash->{OW_MODEL};
  my $master    = $hash->{IODev};
  my $interface = $hash->{IODev}->{TYPE};
  my $value     = undef;
  my $ret       = "";
  my $offset;
  my $factor;

   #-- check syntax
  return "OWLCD: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  my $msg = "OWLCD: Get with unknown argument $a[1], choose one of ";
  $msg .= "$_$gets{$_} " foreach (keys%gets);
  return $msg
    if(!defined($gets{$a[1]}));

  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$name.id => $value";
  } 
  
  #-- get gpio states
  if($a[1] eq "gpio") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $value = OWXLCD_Get($hash,"gpio");
      #-- process result
      if( $master->{ASYNCHRONOUS} ){
        #return "OWLCD: $name getting gpio, please wait for completion";
        return undef;
      }else{
        return "$name.gpio => $value";
      }
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXLCD_PT_Get($hash,"gpio"));
      };
      $ret = GP_Catch($@) if $@;
      return $ret if $ret;
      return "$name.gpio => ".main::ReadingsVal($hash->{NAME},"gpio","");
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
    #-- Unknown interface
    }else{
      return "OWLCD: Get with wrong IODev type $interface";
    }
  } 
  
  #-- get counters
  if($a[1] eq "counter") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $value = OWXLCD_Get($hash,"counter");
      #-- process result
      if( $master->{ASYNCHRONOUS} ){
        #return "OWLCD: $name getting counter, please wait for completion";
        return undef;
      }else{
        return "$name.counter => $value";
      }
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXLCD_PT_Get($hash,"counter"));
      };
      $ret = GP_Catch($@) if $@;
      return $ret if $ret;
      return "$name.counter => ".main::ReadingsVal($hash->{NAME},"counter","");
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
    #-- Unknown interface
    }else{
      return "OWLCD: Get with wrong IODev type $interface";
    }
  }
  
  #-- get version
  if($a[1] eq "version") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $value = OWXLCD_Get($hash,"version");
      #-- process result
      if( $master->{ASYNCHRONOUS} ){
        #return "OWLCD: $name getting version, please wait for completion";
        return undef;
      }else{
        return "$name.version => $owx_version (LCD firmware $value)";
      }
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXLCD_PT_Get($hash,"version"));
      };
      $ret = GP_Catch($@) if $@;
      return $ret if $ret;
      return "$name.gpio => ".main::ReadingsVal($hash->{NAME},"version","");
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
    #-- Unknown interface
    }else{
      return "OWLCD: Get with wrong IODev type $interface";
    }
  }
  
  #-- get EEPROM content
  if($a[1] eq "memory") {
    my $page  = (defined $a[2] and $a[2] =~ m/\d/) ? int($a[2]) : 0;
    #-- OWX interface
    if( $interface eq "OWX" ){
      $value = OWXLCD_GetMemory($hash,$page);
      #-- process result
     if( $master->{ASYNCHRONOUS} ){
        #return "OWLCD: $name memory page $page, please wait for completion";
        return undef;
      }else{
        return "$name $reading $page => $value";
      }
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXLCD_PT_GetMemory($hash,$page));
      };
      $ret = GP_Catch($@) if $@;
      return $ret if $ret;
      return "$name $reading $page => ".main::ReadingsVal($hash->{NAME},"memory$page","");
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
    #-- Unknown interface
    }else{
      return "OWLCD: Get with wrong IODev type $interface";
    }
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
  my $interface  = $hash->{IODev}->{TYPE};
  my $key     = $a[1];
  my $value   = $a[2];
  my ($line,$icon,$i);
  
  #-- for the selector: which values are possible
  return join(" ", keys %sets)
     if ( (@a == 2) && !(($key eq "reset") || ($key eq "test") || ($key eq "initialize")) );
  
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
    return "OWLCD: Set needs two parameters when setting memory page 0/1: <#page> <string>"
      if( int(@a)<4 );
    $line  = ($a[2] =~ m/\d/) ? int($a[2]) : 0;
    $value = $a[3]; 
    for( $i=4; $i< int(@a); $i++){
      $value .= " ".$a[$i];
    }
  #-- check syntax for setting icon
  } elsif ( $key eq "icon" ){
    if( ($a[2] ne "0") && ($a[2] ne "none") ){
      return "OWLCD: Set needs two parameters when setting icon 0-16 value: <#icon> on/off/blink (resp. 0..5/off/blink for #16)"
        if( (int(@a)!=4) );
      $icon  = ($a[2] =~ m/\d\d?/) ? $a[2] : 0;
      $value = $a[3]; 
    } else {
      return "OWLCD: Set needs only one parameter when resetting icons"
        if( (int(@a)!=3) );
      $icon  = 0;
      $value = "OFF"; 
    }  
   
  #-- check syntax for setting gpiobit
  } elsif ( $key eq "gpiobit" ){
    return "OWLCD: Set needs two parameters when setting gpiobit 1-3 value: <#bit> on/off"
      if( (int(@a)!=4) );
    return "OWLCD: Set gpiobit 1-3 value: <#bit> on/off only possible for bits 1-3"
        if( $a[2]>3 || $a[2]<1 );
    
  #-- check syntax for reset and test and initialize
  } elsif ( ($key eq "reset") || ($key eq "test") || ($key eq "initialize")){
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
    return "OWLCD: Set with wrong target value for gpio port, must be 0 <= gpio <= 7"
      if( ! ((int($value) >= 0) && (int($value) <= 7)) );
    #-- OWX interface
    if( $interface eq "OWX" ){
      return OWXLCD_SetFunction($hash, "gpio", int($value));
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "gpio", int($value)) );
      };
      return GP_Catch($@) if $@;
    }
  }
  
  #-- set single gpio bit from all off = 1 on = 0
  #   contribution from ext323
  if($key eq "gpiobit") {
    my $bit   = $a[2];
    $value = lc($a[3]);
    $value =~ s/on/0/;
    $value =~ s/off/1/;
    my $vold = $value;

    #-- check value and write to device
    return "OWLCD: Set with wrong gpio bit number $bit, must be 1 <= bit <= 3"
      if( ($bit < 1) || ($bit > 3) );
    return "OWLCD: Set with wrong gpio bit value $value, must be 0=ON or 1=OFF"
      if( $value !~ /[01]/ );
    if( $value == 1 ){
      $value = 1<<($bit-1) | ReadingsVal($name,"gpio",0);
    }else{
      $value = ~(1<<($bit-1)) & ReadingsVal($name,"gpio",0);
    }
    #-- OWX interface
    if( $interface eq "OWX" ){
      OWXLCD_SetFunction($hash,"gpio",$value);
    }
  }
  
  #-- set LCD ON or OFF
  if($key eq "lcd") {
    #-- check value and write to device   
    if( uc($value) eq "ON"){
      #-- OWX interface
      if( $interface eq "OWX" ){
        return OWXLCD_SetFunction($hash, "lcdon", 0);
      }elsif( $interface eq "OWX_ASYNC" ){
        eval {
          OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "lcdon", 0) );
        };
        return GP_Catch($@) if $@;
      }
    }elsif( uc($value) eq "OFF" ){ 
      #-- OWX interface
      if( $interface eq "OWX" ){
        return OWXLCD_SetFunction($hash, "lcdoff", 0);
      }elsif( $interface eq "OWX_ASYNC" ){
        eval {
          OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "lcdoff", 0) );
        };
        return GP_Catch($@) if $@;
      }
    } else {
      return "OWLCD: Set with wrong value for lcd, must be on/off"
    }
  }
  
  #-- set LCD Backlight ON or OFF
  if($key eq "backlight") {
    #-- check value and write to device   
    if( uc($value) eq "ON"){
      #-- OWX interface
      if( $interface eq "OWX" ){
        return OWXLCD_SetFunction($hash, "bklon", 0);
      }elsif( $interface eq "OWX_ASYNC" ){
        eval {
          OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "bklon", 0) );
        };
        return GP_Catch($@) if $@;
      } 
    }elsif( uc($value) eq "OFF" ){
      #-- OWX interface
      if( $interface eq "OWX" ){
        return OWXLCD_SetFunction($hash, "bkloff", 0);
      }elsif( $interface eq "OWX_ASYNC" ){
        eval {
          OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "bkloff", 0) );
        };
        return GP_Catch($@) if $@;
      }
    } else {
      return "OWLCD: Set with wrong value for backlight, must be on/off"
    }
  }
  
  #-- reset
  if($key eq "reset") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      OWXLCD_SetFunction($hash,"reset",0);
      OWXLCD_SetIcon($hash,0,0);
      OWXLCD_SetFunction($hash,"gpio",15);
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "reset", 0) );
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, 0, 0) );
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetFunction($hash, "gpio", 15) );
      };
      return GP_Catch($@) if $@;
    }
  }
  
  #-- set icon
  if($key eq "icon") {
    return "OWLCD: Wrong icon type, choose 0..16" 
      if( ( 0 > $icon ) || ($icon > 16) );
    #-- check value and write to device  
    if( $icon == 16 ){
      if( uc($value) eq "OFF" ){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, 16, 0);
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, 16, 0) );
          };
          return GP_Catch($@) if $@;
        } 
      }elsif( uc($value) eq "BLINK" ){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, 16, 6);
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, 16, 6) );
          };
        }
      }elsif(  ((int($value) > 0) && (int($value) < 6)) ){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, 16, int($value));
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, 16, int($value)) );
          };
          return GP_Catch($@) if $@;
        }
      } else {
        return "OWLCD: Set with wrong value for icon #16, must be 0..5/off/blink"
      }  
    }else{
      if( uc($value) eq "OFF"){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, $icon, 0);
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, $icon, 0) );
          };
          return GP_Catch($@) if $@;
        }
      }elsif( uc($value) eq "ON" ){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, $icon, 1);
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetIcon($hash, $icon, 1) );
          };
          return GP_Catch($@) if $@;
        }
      }elsif( uc($value) eq "BLINK" ){
        #-- OWX interface
        if( $interface eq "OWX" ){
          return OWXLCD_SetIcon($hash, $icon, 2);
        }elsif( $interface eq "OWX_ASYNC" ){
          eval {
            OWX_ASYNC_Schedule( $hash, &OWXLCD_PT_SetIcon($hash, $icon, 2) );
          };
          return GP_Catch($@) if $@;
        } 
      } else {
        return "OWLCD: Set with wrong value for icon $icon, must be on/off/blink"
      }
    }
  }
  
  #-- set a single LCD line
  if($key eq "line") {
    $value = OWXLCD_Trans($value);
    return "OWLCD: Wrong line number, choose 0..".$lcdlines 
      if( ( 0 > $line ) || ($line > ($lcdlines-1)) );
    return "OWLCD: Wrong line length, must be <= ".$lcdchars 
      if( length($value) > $lcdchars );
    #-- check value and write to device  
    #-- OWX interface
    if( $interface eq "OWX" ){
      return OWXLCD_SetLine($hash,$line,$value);
    }elsif( $interface eq "OWX_ASYNC" ){ 
      eval {
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetLine($hash, $line, $value) );
      };
      return GP_Catch($@) if $@;
    }
  }
  
  #-- set memory page 0..6
  if($key eq "memory") {
    return "OWLCD: Wrong page number, choose 0..6" 
      if( (0 > $line) || ($line > 6) );
    return "OWLCD: Wrong line length, must be <=16 " 
      if( length($value) > 16 );
    #-- write to device   
    #-- OWX interface
    if( $interface eq "OWX" ){
      return OWXLCD_SetMemory($hash,$line,$value);
    }elsif( $interface eq "OWX_ASYNC" ){ 
      eval {
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetMemory($hash, $line, $value) );
      };
      return GP_Catch($@) if $@;
    } 
  }
  
  #-- start test
  if($key eq "test") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      OWXLCD_SetLine($hash,0,"Hallo Welt");
      OWXLCD_SetLine($hash,1,"Mary had a big lamb");
      OWXLCD_SetLine($hash,2,"Solar 4.322 kW ");
      OWXLCD_SetLine($hash,3,"\x5B\x5C\x5E\x7B\x7C\x7E\xBE");
      return undef;
    }elsif( $interface eq "OWX_ASYNC" ){ 
      eval {
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetLine($hash,0,"Hallo Welt")); 
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetLine($hash,1,"Mary had a big lamb")); 
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetLine($hash,2,"Solar 4.322 kW ")); 
        OWX_ASYNC_Schedule( $hash, OWXLCD_PT_SetLine($hash,3,"\x5B\x5C\x5E\x7B\x7C\x7E\xBE"));
      };
      return GP_Catch($@) if $@; 
    }
  }
  
  #-- start initialize
  if($key eq "initialize") {
    OWXLCD_InitializeDevice($hash);
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
# OWXLCD_InitializeDevice - initialize the display
#
# Parameter hash  = hash of device addressed
#
########################################################################################

sub OWXLCD_InitializeDevice($) {
  my ($hash) = @_;

  my $owx_dev    = $hash->{ROM_ID};
  my $master     = $hash->{IODev};
  my $interface  = $hash->{IODev}->{TYPE};
  
  my ($i,$data,$select, $res);

  #-- supposedly we do not need to do anything with a HD44780
  if( $lcdcontroller eq "HD44780"){
    return undef;
  #-- need some additional sequence for KS0073
  }elsif ( $lcdcontroller eq "KS0073"){
 
    #-- Function Set: 4 bit data size, RE => 0 = \x20
    #OWXLCD_Byte($hash,"register",32); 

    #-- Entry Mode Set: cursor auto increment = \x06
    #OWXLCD_Byte($hash,"register",6);

    if( $interface eq "OWX" ){
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
    }elsif( $interface eq "OWX_ASYNC" ){ 
      eval {
        OWX_ASYNC_Schedule($hash,OWXLCD_PT_Byte($hash,"register",38));
        OWX_ASYNC_Schedule($hash,OWXLCD_PT_Byte($hash,"register", 9));
        OWX_ASYNC_Schedule($hash,OWXLCD_PT_Byte($hash,"register",32));
        OWX_ASYNC_Schedule($hash,OWXLCD_PT_Byte($hash,"register",12));
        OWX_ASYNC_Schedule($hash,OWXLCD_PT_Byte($hash,"register", 1));
      };
      return GP_Catch($@) if $@;
    } 
  #-- or else
  } else {
    return "OWXLCD: Wrong LCD controller type";
  }
}  

########################################################################################
#
# OWXLCD_BinValues - Process reading from one device - translate binary into raw
#
# Parameter hash = hash of device addressed
#           context   = mode for evaluating the binary data
#           proc      = processing instruction, also passed to OWX_Read.
#                       bitwise interpretation !!
#                       if 0, nothing special
#                       if 1 = bit 0, a reset will be performed not only before, but also after
#                       the last operation in OWX_Read
#                       if 2 = bit 1, the initial reset of the bus will be suppressed
#                       if 8 = bit 3, the fillup of the data with 0xff will be suppressed  
#                       if 16= bit 4, the insertion will be at the top of the queue  
#           owx_dev   = ROM ID of slave device
#           crcpart   = part of the data that needs to be part of the CRC check
#           numread   = number of bytes to receive
#           res       = result string
#
#
########################################################################################

sub OWXLCD_BinValues($$$$$$$) {
  my ($hash, $context, $reset, $owx_dev, $crcpart, $numread, $res) = @_;
  
  my ($ret,@data,$select);
  my $change = 0;
 
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};

  my $msg;
  OWX_WDBGL($name,5,"OWLCD: $name: BinValues called with context $context and data ",$res);
  
  #=============== setline 2nd step ===============================
  if( $context eq "setline" )  {
    #-- issue the copy scratchpad to LCD command \x48
    ####        master   slave  context     proc owx_dev   data    crcpart numread startread callback delay
    #                                       16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset
    OWX_Qomplex($master, $hash, "sptolcd",  24,  $owx_dev, "\x48", 0,      -3,    0,        undef,   0.01); 
  #=============== seteeprom 2nd step ===============================
  }elsif( $context eq "seteeprom" )  {
    #-- issue the copy scratchpad to EEPROM command \x39
    ####        master   slave  context proc owx_dev   data    crcpart numread startread callback delay
    #                                   16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "sptoeeprom",     24,   $owx_dev,"\x39", 0,      -9,      0,        undef,   0.01); 
  #=============== eraseicon 2nd step ===============================
  }elsif( $context eq "eraseicon.1" )  {
    #-- SEGRAM addres to 0 = \x40,
    $select  = "\x10\x40";
    #-- write 16 zeros to scratchpad
    $select .= "\x4E\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    ####        master   slave  context        proc owx_dev   data     crcpart numread startread callback            delay
    #                                          16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "eraseicon.2", 24,  $owx_dev, $select, 0,      5,      0,        \&OWXLCD_BinValues, 0.01); 
  #=============== eraseicon 3rd step ===============================
  }elsif( $context eq "eraseicon.2" )  {
    #-- issue the copy scratchpad to LCD command \x48
    ####        master   slave   context   proc owx_dev   data    crcpart numread startread callback delay
    #                                      16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "endicon", 24,   $owx_dev,"\x48", 0,      0,      0,        \&OWXLCD_BinValues,   0.01); 
  #=============== seticon 2nd step ===============================
  }elsif( $context eq "seticon.1" )  {
    #-- SEGRAM addres to 0 = \x40 + icon address
    $select = substr($crcpart,0,2);
    ####        master   slave  context      proc owx_dev   data    crcpart   numread startread callback            delay
    #                                        16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "seticon.2", 24,  $owx_dev, $select,$crcpart, 1,      0,        \&OWXLCD_BinValues, 0.01); 
  #=============== seticon 2nd step ===============================
  }elsif( $context eq "seticon.2" )  {
    #-- data
    $select = substr($crcpart,2);
    ####        master   slave  context    proc owx_dev   data     crcpart numread startread  callback            delay
    #                                      16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "endicon", 24,  $owx_dev, $select, 0,      1,      0,         \&OWXLCD_BinValues, 0.01); 
  #=============== endicon ===============================
  }elsif( $context eq "endicon" )  {
    #-- issue the return to normal state command
    ####        master   slave  context    proc owx_dev   data        crcpart numread startread callback delay
    #                                      16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "normal", 24,  $owx_dev, "\x10\x20", 0,      1,      0,        undef,   0.01); 
  #=============== prepare some get values ===============================
  }elsif ( $context =~ /^get\.prep\.(\d+)/ ) {
    my $len = $1;
    #-- command hidden in crcpart, issueing read scratchpad command 
    ####        master   slave  context          proc owx_dev   data     crcpart   numread startread callback            delay
    #                                      16 ensures entry at top of queue, 8 prevents fillup, 1 for final reset 
    OWX_Qomplex($master, $hash, "get.".$crcpart, 0,   $owx_dev, "\xBE",  0,        $len+1,   10,       \&OWXLCD_BinValues, 0.01); 
  #=============== gpio ports ===============================
  }elsif ( $context eq "get.gpio" ) {
    @data= split(//,$res);
    $ret = ord($data[0]) & 7;
    readingsSingleUpdate($hash,"gpio",$ret,1);
  #=============== gpio single bit ===============================
  }elsif ( $context =~ /^get\.gpiobit\.(\d+)\.(\d+)/ ) {
    $ret = ord($res) & 7;
    my $bit = $1;
    my $val = $2;
    my $tar;
    if( $val == 0){
      $tar = $ret & (15-(1<<($bit-1)));
    }else{
      $tar = $ret | (1<<($bit-1)&15);
    }
    OWXLCD_SetFunction($hash,"gpio",$tar);
  #=============== gpio counters ===============================
  }elsif ( $context eq "get.counter" ) {
    for( my $i=0; $i<4; $i++){
      $data[$i] = ord(substr($res,2*$i+1,1))*256+ord(substr($res,2*$i,1));
    }
    $ret = join(" ",@data);
    readingsSingleUpdate($hash,"counter",$ret,1); 
  #=============== version ===============================
  }elsif ( $context eq "get.version" ) {
    #TODO format version, raw value is unreadable
    readingsSingleUpdate($hash,"version",$res,1);
  #=============== memory ===============================
  }elsif ( $context =~ /^get\.memory\.([\d]+)$/ ) {
    readingsSingleUpdate($hash,"memory$1",unpack("H*",$res),1);
  }
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
  
  my $master     = $hash->{IODev};
  my $interface  = $hash->{IODev}->{TYPE};
  my $owx_dev    = $hash->{ROM_ID};
  my $owx_rnf    = substr($owx_dev,3,12);
  my $owx_f      = substr($owx_dev,0,2);
  
  my ($select, $select2, $res, $res2, $res3, @data);
  
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
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for writing a byte"; 
    }
  }else{
    ####        master   slave  context      proc owx_dev   data    crcpart numread startread callback delay
    OWX_Qomplex($master, $hash, "writebyte", 8,   $owx_dev,$select, 0,      1,      0,        undef,   0.01); 
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

sub OWXLCD_Get(@) {

  my ($hash,$cmd) = @_;
  
  my $owx_dev    = $hash->{ROM_ID};
  my $master     = $hash->{IODev};
  my $interface  = $hash->{IODev}->{TYPE};
  
  my ($select, $select2, $len, $addr, $res, $res2);

  #=============== fill scratch with gpio ports ===============================
  if ( $cmd =~ /^gpio.*/ ) {
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
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
    OWX_WDBGL($owx_dev,4,"OWXLCD_Get called OWX_Complex 1 w. result ",$res);
    
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for reading";
    } 
  
    #-- issue the read scratchpad command \xBE
    $select2 = "\xBE";
    #-- write to device

    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select2,$len); 
    OWX_WDBGL($owx_dev,4,"OWXLCD_Get called OWX_Complex 2 w. result ",$res);
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for reading in 2nd step"; 
    }
    OWXLCD_BinValues($hash, "get.".$cmd, 1, $owx_dev, "\xBE", $len, substr($res,10));

    return main::ReadingsVal($hash->{NAME},$cmd,"");
  }else{
    ####        master   slave  context           proc owx_dev   data     crcpart   numread startread callback            delay
    OWX_Qomplex($master, $hash, "get.prep.".$len, 8,   $owx_dev, $select, $cmd,     0,      0,       \&OWXLCD_BinValues, undef); 
    return undef;
  }
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

  my $master     = $hash->{IODev};
  my $interface  = $hash->{IODev}->{TYPE};
  my $owx_dev    = $hash->{ROM_ID};
  my $owx_rnf    = substr($owx_dev,3,12);
  my $owx_f      = substr($owx_dev,0,2);
  
  my ($select, $res, $res2, $res3);

  #-- issue the match ROM command \x55 and the copy eeprom to scratchpad command \x4E
  #Log 1," page read is ".$page;
  $select = sprintf("\4E%c\x10\x37",$page);  
  #-- write to device
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
   
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for reading";
    } 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    $select = "\xBE";
    #-- write to device
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,16); 
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for reading in 2nd step"; 
    }
    OWXLCD_BinValues($hash, "get.memory.$page", 1, $owx_dev, $select, 16, substr($res,11,16));
    #-- process results (10 bytes or more have been sent)
    #$res2 = substr($res,11,16);
    #return $res2;
    return main::ReadingsVal($hash->{NAME},"memory$page","");
  #-- NEW OWX interface
  }else{
    ####        master   slave  context        proc owx_dev   data      crcpart        numread startread callback delay
    OWX_Qomplex($master, $hash, "get.prep.16", 8,   $owx_dev, $select, "memory.$page", -2,     0,       \&OWXLCD_BinValues,   0.01); 
    return undef;
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
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($select, $res, $res2, $res3, @data);
  my $context = "setfunction";
  my $len     = 0;
   
  #=============== set gpio ports ===============================
  if ( $cmd eq "gpio" ) {
    #-- issue the write GPIO command 
    #   \x21 followed by the data value (= integer 0 - 7)
    $select = sprintf("\x21%c",$value); 
    $len    = 1;
    readingsSingleUpdate($hash,"gpio",$value,1);
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
  #=============== reset ===============================
  }elsif ( $cmd eq "reset" ) {
    #-- issue the clear LCD command
    $select = "\x49";
  #=============== wrong write attempt ===============================
  } else {
    return "OWXLCD: Wrong function selected";
  } 
  
   #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    #-- write to device
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
    #-- process results
    if( $res eq 0 ){
      return "OWLCD: Device $owx_dev not accessible for writing"; 
    }
  #-- NEW OWX interface
  }else{
    ####        master   slave  context   proc owx_dev   data      crcpart numread startread callback delay
    OWX_Qomplex($master, $hash, $context, 8,   $owx_dev, $select,  0,      $len,      0,        undef,   0.01); 
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
    
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$data,$select, $res);

  #-- only for KS0073
  if ( $lcdcontroller eq "KS0073"){
    
    #-- write 16 zeros to erase all icons
    if( $icon == 0){   
      #-- 4 bit data size, RE => 1, blink Enable = \x26     
      $select = "\x10\x26";
      #-- OLD OWX interface
      if( !$master->{ASYNCHRONOUS} ){
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
        
        #-- return to normal state
        $select = "\x10\x20";
        OWX_Reset($master);
        $res=OWX_Complex($master,$owx_dev,$select,0);
      #-- NEW OWX interface  
      }else{
        ####        master   slave  context        proc owx_dev   data      crcpart numread startread callback            delay
       OWX_Qomplex($master, $hash, "eraseicon.1",  8,   $owx_dev, $select,  0,      1,      0,        \&OWXLCD_BinValues, 0.01); 
      }
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
      if( !$master->{ASYNCHRONOUS} ){
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
        
        #-- return to normal state
        $select = "\x10\x20";
        OWX_Reset($master);
        $res=OWX_Complex($master,$owx_dev,$select,0);
      }else{
        ####        master   slave  context      proc owx_dev   data      crcpart                                              numread startread callback            delay
        OWX_Qomplex($master, $hash, "seticon.1", 8,   $owx_dev, $select,  sprintf("\x10%c",63+$icon).sprintf("\x12%c",$data),  1,      0,        \&OWXLCD_BinValues, 0.01); 
      }
    }
   
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
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($select, $res, $res2, $res3, $i, $msgA, $msgB);
  
  $res2 = "";
  $line = int($line);
  $msg =   defined($msg) ? $msg : "";
  
  $msg = OWXLCD_Trans($msg);

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
  
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
  
    #-- issue the copy scratchpad to LCD command \x48 
    OWX_Reset($master);
    $res3=OWX_Complex($master,$owx_dev,"\x48",0);
  #-- NEW OWX interface
  }else{
    ####        master   slave  context    proc owx_dev   data      crcpart   numread          startread callback            delay
    #                                      8= do not fill w. ff, 1=reset after               
    OWX_Qomplex($master, $hash, "setline", 8,   $owx_dev, $select,  0,        length($msgA)+1,   11,       \&OWXLCD_BinValues, 0.01); 
  }
  #-- if second string available:
  if( defined($msgB) ) {
    #-- issue the match ROM command \x55 and the write scratchpad command \x4E
    #   followed by LCD page address and the text 
    $select=sprintf("\x4E%c",$lcdpage[$line]+16).$msgB;      
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){
      select(undef,undef,undef,0.05); 
      OWX_Reset($master);
      $res2=OWX_Complex($master,$owx_dev,$select,0);
   
      #-- issue the copy scratchpad to LCD command \x48
      $select="\x48";  
      OWX_Reset($master);
      $res3=OWX_Complex($master,$owx_dev,$select,0);
    #-- NEW OWX interface
    }else{
      ####        master   slave  context    proc owx_dev   data      crcpart numread         startread callback             delay
      #                                      8= do not fill w. ff
      OWX_Qomplex($master, $hash, "setline", 8,   $owx_dev, $select,  0,      length($msgB)+1,  11,       \&OWXLCD_BinValues,  0.05); 
    }
  }
  
  #-- process results
  if( !$master->{ASYNCHRONOUS} ){
    if( ($res eq 0) || ($res2 eq 0) || ($res3 eq 0) ){
      return "OWLCD: Device $owx_dev not accessible for writing"; 
    }
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
  
  #-- replace umlaut chars for special codepage of KS0073
  if( $lcdcontroller eq "KS0073") {
    $msg =~ s/ä/\x7B/g;
    $msg =~ s/ö/\x7C/g;
    $msg =~ s/ü/\x7E/g;
    $msg =~ s/Ä/\x5B/g;
    $msg =~ s/Ö/\x5C/g;
    $msg =~ s/Ü/\x5E/g;
    $msg =~ s/ß/\xBE/g;
    $msg =~ s/°/\x80/g;
  #-- replace umlaut chars for special codepage of HD44780
  }elsif( $lcdcontroller eq "HD44780") {
    $msg =~ s/ä/\xE1/g;
    $msg =~ s/ö/\xEF/g;
    $msg =~ s/ü/\xF5/g;
    $msg =~ s/Ü/\x03/g;
    $msg =~ s/Ö/\x02/g;
    $msg =~ s/Ä/\x01/g;
    $msg =~ s/ß/\xE2/g;
    $msg =~ s/°/\xDF/g;
  }
  
  #-- replace other special chars 
  $msg =~s/_/\xC4/g;
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
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($select, $res, $res2, $res3, $i, $msgA);
  $page = int($page);
  $msg =   defined($msg) ? $msg : "";

  #-- fillup with blanks
  $msgA = $msg;
  for($i = 0;$i<16-length($msg);$i++){
    $msgA .= "\x20";
  }
   
  #-- issue the match ROM command \x55 and the write scratchpad command \x4E
  #   followed by LCD page address and the text 
  #Log 1," page written is ".$page;
  $select=sprintf("\x4E\%c",$page).$msgA;
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
    #-- issue the copy scratchpad to EEPROM command \x39
    $select = "\x39"; 
    OWX_Reset($master);
    $res2=OWX_Complex($master,$owx_dev,$select,0);
  
    #-- process results
    if( ($res eq 0) || ($res2 eq 0) ){
      return "OWLCD: Device $owx_dev not accessible for writing"; 
    }
  #-- NEW OWX interface
  }else{
    ####        master   slave  context      proc owx_dev   data      crcpart numread startread callback delay
    OWX_Qomplex($master, $hash, "seteeprom", 8,   $owx_dev, $select,  0,      17,      0,        \&OWXLCD_BinValues,   0.01); 
  }
  return undef;
}

########################################################################################
#
# OWXLCD_PT_Byte - write a single byte to the LCD device async
#
# Parameter hash = hash of device addressed
#           cmd = register or data
#           byte = byte
#
########################################################################################

sub OWXLCD_PT_Byte($$$) {

  my ($hash,$cmd,$byte) = @_;
  
  return PT_THREAD(sub {
    my ($thread) = @_;
    my ($select);
    #-- ID of the device
    my $owx_dev = $hash->{ROM_ID};
    #-- hash of the busmaster
    my $master = $hash->{IODev};
    my ($i,$j,$k);

    PT_BEGIN($thread);

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
      die "OWXLCD: Wrong byte write attempt";
    } 

    #"byte"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    PT_END;
  });
}

########################################################################################
#
# OWXLCD_PT_Get - get values from the LCD device async
#
# Parameter hash = hash of device addressed
#           cmd  = command string
#
########################################################################################

sub OWXLCD_PT_Get($$) {

  my ($hash,$cmd) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($select);

    #-- ID of the device
    my $owx_dev = $hash->{ROM_ID};

    #-- hash of the busmaster
    my $master = $hash->{IODev};

    my ($i,$j,$k);

    PT_BEGIN($thread);
    #=============== fill scratch with gpio ports ===============================
    if ( $cmd eq "gpio" ) {
      #-- issue the read GPIO command \x22 (1 byte)
      $select = "\x22";
      $thread->{len}     = 1;
    #=============== fill scratch with gpio counters ===============================
    }elsif ( $cmd eq "counter" ) {
      #-- issue the read counter command \x23 (8 bytes)
      $select = "\x23";
      $thread->{len}     = 8;
    #=============== fill scratch with version ===============================
    }elsif ( $cmd eq "version" ) {
      #-- issue the read version command \x41
      $select = "\x41";
      $thread->{len}     = 16;
    } else {
      die("OWXLCD: Wrong get attempt");
    }
    #"get.prepare"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    #-- issue the read scratchpad command \xBE
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,"\xBE", $thread->{len});
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    OWXLCD_BinValues($hash, "get.".$cmd, 1, $owx_dev, "\xBE", $thread->{len}, $thread->{pt_execute}->PT_RETVAL());

    PT_END;
  });
}

########################################################################################
#
# OWXLCD_PT_GetMemory - get memory page from LCD device async (EXPERIMENTAL)
#
# Parameter hash = hash of device addressed
#           page = memory page address
#
########################################################################################

sub OWXLCD_PT_GetMemory($$) {

  my ($hash,$page) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($select);

    #-- ID of the device
    my $owx_dev = $hash->{ROM_ID};

    #-- hash of the busmaster
    my $master = $hash->{IODev};

    PT_BEGIN($thread);
    #-- issue the match ROM command \x55 and the copy eeprom to scratchpad command \x4E
    #Log 1," page read is ".$page;
    $select = sprintf("\4E%c\x10\x37",$page);
    #"prepare"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    #-- sleeping for some time
    $thread->{ExecuteTime} = gettimeofday()+0.5;
    PT_YIELD_UNTIL(gettimeofday() >= $thread->{ExecuteTime});
    delete $thread->{ExecuteTime};

    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    $thread->{'select'} = "\xBE";
    #"get.memory.$page"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$thread->{'select'},16);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    OWXLCD_BinValues($hash, "get.memory.$page", 1, $owx_dev, $thread->{'select'}, 16, $thread->{pt_execute}->PT_RETVAL());
    #-- process results (10 bytes or more have been sent)
    #$res2 = substr($res,11,16);
    #return $res2;
    PT_END;
  });
}

########################################################################################
#
# OWXLCD_PT_SetFunction - write state and values of the LCD device async
#
# Parameter hash  = hash of device addressed
#           cmd   = command string
#           value = data value
#
########################################################################################

sub OWXLCD_PT_SetFunction($$$) {

  my ($hash,$cmd,$value) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($select);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    my ($i,$j,$k);

    PT_BEGIN($thread);

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
      die "OWXLCD: Wrong function selected '$cmd'";
    } 
    #"set.function"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    
    PT_END;
  });
}

########################################################################################
#
# OWXLCD_PT_SetIcon - set one of the icons async
#
# Parameter hash  = hash of device addressed
#           icon  = address of the icon used = 0,1 .. 16 (0 = all off)
#           value = data value: 0 = off, 1 = on, 2 = blink
#                   for battery icon 16: 0 = off, 1 = empty ... 5 = full, 6 = empty blink
#
########################################################################################

sub OWXLCD_PT_SetIcon($$$) {
  my ($hash,$icon,$value) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($i,$data,$select, $res);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    PT_BEGIN($thread);

    #-- only for KS0073
    if ( $lcdcontroller eq "KS0073"){

      #-- write 16 zeros to erase all icons
      if( $icon == 0){
        #-- 4 bit data size, RE => 1, blink Enable = \x26     
        $select = "\x10\x26";
        #"set.icon.1"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

        #-- SEGRAM addres to 0 = \x40,
        $select = "\x10\x40";
        #-- write 16 zeros to scratchpad
        $select .= "\x4E\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
        #"set.icon.2"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

        #-- issue the copy scratchpad to LCD command \x48
        $select="\x48";  
        #"set.icon.3"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
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
            die("OWXLCD: Wrong data value $value for icon $icon");
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
            die("OWXLCD: Wrong data value $value for icon $icon");
          }
        }
        #-- 4 bit data size, RE => 1, blink Enable = \x26
        $select = "\x10\x26";
        #"set.icon.4"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

        #-- SEGRAM addres to 0 = \x40 + icon address
        $select = sprintf("\x10%c",63+$icon);
        #"set.icon.5"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

        #-- data
        $select = sprintf("\x12%c",$data);
        #"set.icon.6"
        $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
        PT_WAIT_THREAD($thread->{pt_execute});
        die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      }  

      #-- return to normal state
      $select = "\x10\x20";
      #"set.icon.7"
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    #-- or else
    } else {
      die("OWXLCD: Wrong LCD controller type");
    }
    PT_END;
  });
}

########################################################################################
#
# OWXLCD_PT_SetLine - set one of the display lines async
#
# Parameter hash  = hash of device addressed
#           line  = line number (0..3)
#           msg   = data string to be written
#
########################################################################################

sub OWXLCD_PT_SetLine($$$) {

  my ($hash,$line,$msg) = @_;
  
  return PT_THREAD(sub {
  
    my ($thread) = @_;
    my ($select, $i, $msgA, $msgB);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    $line = int($line);  

    PT_BEGIN($thread);

    $msg =   defined($msg) ? $msg : "";
    $msg = OWXLCD_Trans($msg);

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
    $thread->{msgB} = $msgB;

    #-- issue the match ROM command \x55 and the write scratchpad command \x4E
    #   followed by LCD page address and the text 
    $select=sprintf("\x4E%c",$lcdpage[$line]).$msgA;
    #"set.line.1"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    #-- issue the copy scratchpad to LCD command \x48
    $select="\x48";  
    #"set.line.2"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    #-- if second string available:
    if( defined($thread->{msgB}) ) {
      #select(undef,undef,undef,0.005); 
      #-- issue the match ROM command \x55 and the write scratchpad command \x4E
      #   followed by LCD page address and the text 
      $select=sprintf("\x4E%c",$lcdpage[$line]+16).$thread->{msgB};
      #"set.line.3"
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

      #-- issue the copy scratchpad to LCD command \x48
      $select="\x48";  
      #"set.line.4"
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    }
    PT_END;
  });
}


########################################################################################
#
# OWXLCD_PT_SetMemory - set internal nonvolatile memory async
#
# Parameter hash  = hash of device addressed
#           page  = page number (0..14)
#           msg   = data string to be written
#
########################################################################################

sub OWXLCD_PT_SetMemory($$$) {

  my ($hash,$page,$msg) = @_;

  return PT_THREAD(sub {

    my ($thread,$hash,$page,$msg) = @_;
    my ($select, $i, $msgA);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    PT_BEGIN($thread);

    $page = int($page);
    $msg =   defined($msg) ? $msg : "";

    #-- fillup with blanks
    $msgA = $msg;
    for($i = 0;$i<16-length($msg);$i++){
      $msgA .= "\x20";
    }

    #-- issue the match ROM command \x55 and the write scratchpad command \x4E
    #   followed by LCD page address and the text 
    #Log 1," page written is ".$page;
    $select=sprintf("\x4E\%c",$page).$msgA;
    #"set.memory.page"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

    #-- issue the copy scratchpad to EEPROM command \x39
    $select = "\x39"; 
    #"set.memory.copy"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select,0);
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    PT_END;
  });
}

1;

=pod
=item device
=item summary to commmunicate with the 1-Wire LCD hardware
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
            <li><a name="owlcd_gpiobit">
                    <code>set &lt;name&gt; gpiobit &lt;bit&gt; &lt;value&gt;</code></a><br />Write state for gpio pin no. 1..3,
                 possible values are 0=ON, 1=OFF</li>
            <li><a name="owlcd_bl">
                    <code>set &lt;name&gt; backlight ON|OFF</code></a><br />Switch backlight on or
                off</li>
            <li><a name="owlcd_lcd">
                    <code>set &lt;name&gt; lcd ON|OFF</code></a><br />Switch LCD power on or
                off</li>
            <li><a name="owlcd_reset">
                    <code>set &lt;name&gt; reset</code></a><br />Reset the display</li>
            <li><a name="owlcd_test">
                    <code>set &lt;name&gt; test</code></a><br />Test the display</li>
        </ul>
        <br />
        <a name="owlcdget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owlcd_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owlcd_memory2">
                    <code>get &lt;name&gt; memory &lt;page&gt;</code></a><br />Read memory page 0..6 </li>
            <li><a name="owlcd_gpio2">
                    <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all four input
                channels (15 = all off, 0 = all on)</li>
            <li><a name="owlcd_counter">
                    <code>get &lt;name&gt; counter</code></a><br />Obtain state of all four input
                counters (4 x 16 Bit)</li>
            <li><a name="owlcd_version">
                    <code>get &lt;name&gt; version</code></a><br />Obtain firmware version of the
                controller</li>
        </ul>
        <br />
        <a name="owlcdattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="owlcd_lcdgeometry">
                    <code>attr &lt;name&gt; lcdgeometry &lt;string&gt;</code></a><br />
                    LCD geometry, values are 0-32-64-96 (default) or 0-64-20-84</li>
            <li><a name="owlcd_lcdgcontroller">
                    <code>attr &lt;name&gt; lcdcontroller &lt;string&gt;</code></a><br />
                    LCD geometry, values are KS0073 (default) HD44780</li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        
=end html
=cut