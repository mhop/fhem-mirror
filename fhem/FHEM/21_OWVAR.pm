########################################################################################
#
# OWVAR.pm
#
# FHEM module to commmunicate with 1-Wire variable resistor DS2890
#
# Prof. Dr. Peter A. Henning
#
# $Id$
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

use vars qw{%attr %defs %modules $readingFnAttributes $init_done};
use strict;
use warnings;
use Time::HiRes qw( gettimeofday );

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use ProtoThreads;
no warnings 'deprecated';
sub Log3($$$);
sub AttrVal($$$);

my $owx_version="7.0";
my $owg_channel = "";

my %gets = (
  "id"          => ":noArg",
  "value"       => ":noArg",
  "version"     => ":noArg"
);

my %sets = (
  "value"    => ""
);

my %updates = (
  "value"     => ""
);

########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWVAR
#
########################################################################################
#
# OWVAR_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWVAR_Define";
  $hash->{UndefFn} = "OWVAR_Undef";
  $hash->{GetFn}   = "OWVAR_Get";
  $hash->{SetFn}   = "OWVAR_Set";
  $hash->{NotifyFn}= "OWVAR_Notify";
  $hash->{InitFn}  = "OWVAR_Init";
  $hash->{AttrFn}  = "OWVAR_Attr";
  $hash->{AttrList}= "IODev model:DS2890 ".
                     "Name Function Unit ".
                     $readingFnAttributes;                
  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}
  
########################################################################################
#
# OWVAR_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWVAR_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWVAR [<model>] <id> 
  # e.g.: define flow OWVAR 525715020000  
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$ret);
  
  #-- default
  $name          = $a[0];
  $ret           = "";

  #-- check syntax
  return "OWVAR: Wrong syntax, must be define <name> OWVAR [<model>] <id> or OWVAR <fam>.<id> "
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- different types of definition allowed
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  #-- no model, 12 characters
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2890";
    CommandAttr (undef,"$name model DS2890"); 
    $fam           = "10";
    $id            = $a[2];
  #-- no model, 2+12 characters
   } elsif(  $a2 =~ m/^[0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
    $fam           = substr($a[2],0,2);
    $id            = substr($a[2],3);
    if( $fam eq "2C" ){
      $model = "DS2890";
      CommandAttr (undef,"$name model DS2890"); 
    }else{
      return "OWVAR: Wrong 1-Wire device family $fam";
    }
  #-- model, 12 characters
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if( $model eq "DS2890" ){
      $fam = "2C";
      CommandAttr (undef,"$name model DS2890"); 
    }else{
      return "OWVAR: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWVAR: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }
  
  #-- determine CRC Code
  $crc = sprintf("%02X",OWX_CRC($fam.".".$id."00"));
  
  #-- define device internals
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{ROM_ID}     = "$fam.$id.$crc";

  #-- value globals - always the raw values from/for the device
  $hash->{owg_val}   = "";
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}) or !defined($hash->{IODev}->{NAME}) ){
    return "OWVAR: Warning, no 1-Wire I/O device found for $name.";
  } else {
    $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0; #-- false for now
  }

  $modules{OWVAR}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log3 $name, 3, "OWVAR:    Device $name defined.";

  $hash->{NOTIFYDEV} = "global";

  if ($init_done) {
    OWVAR_Init($hash);
  }
  return undef;
}

#######################################################################################
#
# OWVAR_Notify - Implements the Notify function
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWVAR_Notify ($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    OWVAR_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}


#######################################################################################
#
# OWVAR_Init - Implements the Init function
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_Init ($) {
  my ($hash)=@_;
  #-- Start timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+10, "OWVAR_GetValues", $hash, 0);
  return undef; 
}

#######################################################################################
#
# OWVAR_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWVAR_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
  	ARGUMENT_HANDLER: {
      #-- IODev
      $key eq "IODev" and do {
        AssignIoPort($hash,$value);
        if( defined($hash->{IODev}) ) {
          $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0;
          if ($init_done) {
            OWVAR_Init($hash);
          }
        }
        last;
      };
    }
  }
  return $ret;
}

########################################################################################
#
# OWVAR_ChannelNames - find the real channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_ChannelNames($) { 
  my ($hash) = @_;
  
  my $name    = $hash->{NAME};
  my $state   = $hash->{READINGS}{"state"}{VAL};
 
  my ($cname,@cnama,$unit);

  #-- name
  $cname = defined($attr{$name}{"Name"})  ? $attr{$name}{"Name"} : "value";
  @cnama = split(/\|/,$cname);
  if( int(@cnama)!=2){
    push(@cnama,$cnama[0]);
  }
  $owg_channel=$cnama[0];

  #-- unit
  $unit = defined($attr{$name}{"Unit"})  ? $attr{$name}{"Unit"} : "\%";
   
  #-- put into readings
  $hash->{READINGS}{"value"}{ABBR}     = $cnama[1];  
  $hash->{READINGS}{"value"}{UNIT}     = " ".$unit;
}  

########################################################################################
#
# OWVAR_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWVAR_FormatValues($) {
 my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my $interface = $hash->{IODev}->{TYPE};
  my ($vval,$vlow,$vhigh,$vfunc,$ufunc,$ret);
  
  #-- no change in any value if invalid reading
  #for (my $i=0;$i<int(@owg_fixed);$i++){
  #  return "" if( (!defined($hash->{owg_val})) || ($hash->{owg_val} eq "") );
  #}
  
  #-- obtain channel names
  OWVAR_ChannelNames($hash);
 
  #-- put into READINGS
  readingsBeginUpdate($hash);
  
  #-- formats for output
  if (defined($attr{$name}{"Function"})){
    ($vfunc,$ufunc) = split('\|',$attr{$name}{"Function"});
    #-- replace by proper values (V -> value)
    $vfunc =~ s/V/\$hash->{owg_val}/g; 
    $vfunc = eval($vfunc);
    if( !$vfunc ){
      $vval = 0.0;
    } elsif( $vfunc ne "" ){
      $vval = $vfunc;
    } else {
      $vval = "???";
    }
  }else{    
    $vval = $hash->{owg_val};
  }      
 
  #-- string buildup for return value, STATE and alarm
  my $svalue .= sprintf( "%s: %5.3f%s", $hash->{READINGS}{"value"}{ABBR}, $vval,$hash->{READINGS}{"value"}{UNIT});
                
  #-- put into READINGS
  $vval = sprintf( "%5.3f", $vval);
  readingsBulkUpdate($hash,$owg_channel,$vval);
  
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsEndUpdate($hash,1); 
  return $svalue;
}
  
########################################################################################
#
# OWVAR_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWVAR_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};

  my $value   = undef;
  my $ret     = "";

  #-- check syntax
  return "OWVAR: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  my $msg = "OWVAR: Get with unknown argument $a[1], choose one of ";
  $msg .= "$_$gets{$_} " foreach (keys%gets);
  return $msg
    if(!defined($gets{$a[1]}));
  
  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$name.id => $value";
  } 
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  #-- Get other values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $owx_version";
  }
  
  if( $a[1] eq "value") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      #-- not different from getting all values ..
      $ret = OWXVAR_GetValues($hash);
    }elsif( $interface eq "OWX_ASYNC" ){
      Log3 $name,1,"OWVAR: Get ASYNC interface not implemented";
      #eval {
      #  $ret = OWX_ASYNC_RunToCompletion($hash,OWXVAR_PT_GetValues($hash));
      #};
      #$ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSVAR_GetValues($hash);
    #-- Unknown interface
    }else{
      return "OWVAR: Get with wrong IODev type $interface";
    }
  }
   #-- process results
  if( $master->{ASYNCHRONOUS} ){
    #return "OWVAR: $name getting value, please wait for completion";
    return undef;
  }else{
    #-- when we have a return code, we have an error
    if( defined($ret)  ){
      return "OWVAR: Could not get values from device $name, return was $ret";
    }
  
    #-- return the special reading
    if ($reading eq "value") {
      return "OWVAR: $name.value => ".
        $hash->{READINGS}{"value"}{VAL};
    }  else {
      return undef;
    }
  }
}

#######################################################################################
#
# OWVAR_GetValues - Updates the readings from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_GetValues($@) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $value   = "";
  my $ret;
  
  #-- check if device needs to be initialized
  if( $hash->{READINGS}{"state"}{VAL} eq "defined"){
    OWVAR_InitializeDevice($hash);
    OWVAR_FormatValues($hash);
  }
  
  #-- Get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXVAR_GetValues($hash);
  }elsif( $interface eq "OWX_ASYNC" ){
    Log3 $name, 1,"OWVAR: Get ASYNC interface not implemented";
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSVAR_GetValues($hash);
  }else{
    Log3 $name, 3, "OWVAR: GetValues with wrong IODev type $interface";
    return 1;
  }

  #-- process results
  if( defined($ret)  ){
    $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
    return "OWVAR: Could not get values from device $name for ".$hash->{ERRCOUNT}." times, reason $ret";
  }

  return undef;
}

########################################################################################
#
# OWVAR_InitializeDevice - delayed setting of initial readings
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_InitializeDevice($) {
  my ($hash) = @_;

  my $name      = $hash->{NAME};
  my $interface = $hash->{IODev}->{TYPE};
    
  my $ret="";
  my ($ret1,$ret2);
  
  #-- Initial readings 
  $hash->{owg_val} = "0.0";  
  $hash->{ERRCOUNT} = 0;
  
  #-- Set state to initialized
  readingsSingleUpdate($hash,"state","initialized",1);
  
  return OWVAR_GetValues($hash);
}

#######################################################################################
#
# OWVAR_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################

sub OWVAR_Set($@) {
  my ($hash, @a) = @_;

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a == 2);
  #-- check syntax
  return "OWVAR: Set needs one parameter"
    if(int(@a) != 3);
  #-- check argument
  return "OWVAR: Set with unknown argument $a[1], choose one of ".join(",", sort keys %sets)
        if(!defined($sets{$a[1]}));
      
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  my $ret   = undef;
  my($vfunc,$ufunc);
  my $name  = $hash->{NAME};
  my $model = $hash->{OW_MODEL};
  my $interface = $hash->{IODev}->{TYPE};

  #-- formats for input
  if (defined($attr{$name}{"Function"})){
    ($vfunc,$ufunc) = split('\|',$attr{$name}{"Function"});
    #-- replace by proper values (U -> )
    $ufunc =~ s/U/\$value/g;  
    $ufunc = eval($ufunc);
    if( !$ufunc ){
      $value = 0.0;
    } elsif( $ufunc ne "" ){
      $value = $ufunc;
    } else {
      $value = "???";
    }
  }

  #-- put into device
  #-- OWX interface
  if( $interface eq "OWX" ){
    $ret = OWXVAR_SetValues($hash,$key,$value);
  }elsif( $interface eq "OWX_ASYNC" ){
    Log3 $name, 1,"OWVAR: Set ASYNC interface not implemented";
  #-- OWFS interface
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSVAR_SetValues($hash,$key,$value);
  } else {
    return "OWVAR: Set with wrong IODev type $interface";
  }
  #-- process results
  if( defined($ret)  ){
    return "OWVAR: Could not set device $name, reason: ".$ret;
  }
  
  #-- process results
  $hash->{PRESENT} = 1; 
  OWVAR_FormatValues($hash); 
  Log3 $name, 4, "OWVAR: Set $hash->{NAME} $key $value";
  
  return undef;
}

########################################################################################
#
# OWVAR_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWVAR_Undef ($) {
  my ($hash) = @_;
  
  delete($modules{OWVAR}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSVAR
#
########################################################################################
#
# OWFSVAR_GetValues - Get values from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSVAR_GetValues($) {
  my ($hash) = @_;
 
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- reset presence
  $hash->{PRESENT}  = 0;

  #-- get values - or should we rather get the uncached ones ?
  Log 1, "OWVAR: trying to read from OWserver /$owx_add/wiper";
  my $val = OWServer_Read($master,"/$owx_add/wiper");

  return "no return from OWServer"
    if( !defined($val) );
  return "empty return from OWServer"
    if( $val eq "" );
    
  $hash->{owg_val}=sprintf("%5.2f",(1.0-$val/255.0)*100);  
        
  #-- and now from raw to formatted values
  $hash->{PRESENT}  = 1;
  my $value = OWVAR_FormatValues($hash);
  return undef;
}

########################################################################################
#
# OWFSVAR_SetValues - Set values in device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSVAR_SetValues($$$) {
  my ($hash,$key,$value) = @_;
  
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- translate from 0..100 to 0..255
  return sprintf("OWFSVAR: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",0,100)
      if($value < 0 || $value > 100);
  my $pos = floor((100-$value)*2.55+0.5);
  
  Log 1,"OWVAR: trying to write to OWserver /$owx_add/wiper => $pos";
  
  OWServer_Write($master, "/$owx_add/wiper/",$pos);

  return undef
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXVAR
#
########################################################################################
#
# OWXVAR_BinValues - Process reading from one device - translate binary into raw
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

sub OWXVAR_BinValues($$$$$$$) {
  my ($hash, $context, $reset, $owx_dev, $crcpart, $numread, $res) = @_;
  
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  my $error  = 0;
  
  my ($i,$j,$k,@data);
  my $change = 0;

  my $msg;
  OWX_WDBGL($name,4,"OWXVAR_BinValues called for device $name in context $context with data ",$res);
  
  #-- process results 
  if( $context eq "setstate" )  {
    #-- we have to get rid  of the first 10 bytes
    if( length($res) == 11 ){
      $res=substr($res,10);
    }
    
    if( length($res) != 1 ) {
      $error = 1;
      $msg   = "$name: invalid data length, ".length($res)." instead of 1 bytes ";
    }elsif( $res ne $crcpart ){
      $error = 1;
      $msg   = "$name: invalid data ";
    }else{
      $msg   = "$name: no error, ";
    }
    OWX_WDBGL($name,5-4*$error,"OWXVAR_BinValues setstate:    ".$msg,$res);
    
    #-- increase error count
    if( $error ){
      $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
    }else{
      ####        master   slave  context     proc owx_dev   data     crcpart numread startread callback            delay
      OWX_Qomplex($master, $hash, "release",  18,  $owx_dev, "\x96",  0,      11,      0,       \&OWXVAR_BinValues,   0.01); 
    }
  #------------------------------------------------------------------
  }elsif( $context eq "release" )  {
    #-- we have to get rid  of the first 10 bytes
    if( length($res) == 11 ){
      $res=substr($res,10);
    }
    
    if( length($res) != 1 ) {
      $error = 1;
      $msg   = "$name: invalid data length, ".length($res)." instead of 1 bytes ";
    }elsif( $res ne "\x96" ){
      $error = 1;
      $msg   = "$name: invalid data ";
    }else{
      $msg   = "$name: no error, ";
    }
    OWX_WDBGL($name,5-4*$error,"OWXVAR_BinValues release :    ".$msg,$res);
    #-- increase error count
    if( $error ){
      $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
    }
  #------------------------------------------------------------------
  }elsif( $context eq "getstate" )  {
    #-- we have to get rid  of the first 10 bytes
    if( length($res) == 12 ){
      $res=substr($res,10);
    }
    @data=split(//,$res);
    
    #-- process results
    if (@data != 2) {
      $error = 1;
      $msg   = "$name: invalid data length, ".int(@data)." instead of 2 bytes ";
    }else{
      $msg   = "$name: no error, ";
    }
    OWX_WDBGL($name,5-4*$error,"OWXVAR_BinValues getstate:    ".$msg,$res);
   
    my $stat = ord($data[0]);
    my $val  = ord($data[1]);
      
    $hash->{owg_val}=sprintf("%5.2f",(1.0-$val/255.0)*100);  
  
    #-- and now from raw to formatted values
    $hash->{PRESENT}  = 1;
    if ( !$error ){
      my $value = OWVAR_FormatValues($hash)
    }else{
      $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
    }
  }
  return undef;
}

########################################################################################
#
# OWXVAR_GetValues - Trigger reading from one device 
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXVAR_GetValues($) {
  my ($hash) = @_;
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
 
  #-- NOW ask the specific device
  #-- issue the match ROM command \x55 and the read wiper command \xF0
  #-- reading 9 + 1 + 2 data bytes and 0 CRC byte = 12 bytes
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    my $res=OWX_Complex($master,$owx_dev,"\xF0",2);
    return "OWVAR: $name not accessible in reading"
      if( $res eq 0 );
    return "OWVAR: $name has returned invalid data"
      if( length($res)!=12);
    OWX_Reset($master);  
    return OWXVAR_BinValues($hash,"getstate",0,$owx_dev,0,2,substr($res,10,2));

  #-- NEW OWX interface
  }else{
    ####        master   slave  context     proc owx_dev   data     crcpart numread startread callback            delay
    OWX_Qomplex($master, $hash, "getstate", 0,   $owx_dev, "\xF0",  0,      12,     0,       \&OWXVAR_BinValues, undef); 
    return undef;
  }
}

#######################################################################################
#
# OWXVAR_SetValues - Implements SetFn function
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
#######################################################################################

sub OWXVAR_SetValues($$$) {
  my ($hash, $key,$value) = @_;
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};

  #-- translate from 0..100 to 0..255
  return sprintf("OWXVAR: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",0,100)
      if($value < 0 || $value > 100);
  my $pos = floor((100-$value)*2.55+0.5);
  
  #-- issue the match ROM command \x55 and the write wiper command \x0F,
  #   followed by 1 bytes of data 
  #
  my $select=sprintf("\x0F%c",$pos);
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    my $res=OWX_Complex($master,$owx_dev,$select,1);
    return "OWXVAR: $name not accessible"
      if( $res eq 0 );
    my $rv=ord(substr($res,11,1));
    return "OWXVAR: $name: Set failed with return value $rv from set value $pos"
      if($rv ne $pos);
    my $res2=OWX_Complex($master,$owx_dev,"\x96",1);
    my $rv2=ord(substr($res2,11,1));
    return "OWXVAR: $name: Set failed with return value $rv2 from release value"
      if($rv2 ne 0);
    OWX_Reset($master);
    $hash->{owg_val}=sprintf("%5.2f",(1-$pos/255.0)*100);  
  #-- NEW OWX interface
  }else{
    ####        master   slave  context     proc  owx_dev   data      crcpart numread startread callback          delay
    OWX_Qomplex($master, $hash, "setstate", 0,    $owx_dev, $select,  substr($select,1),       11,     0,        \&OWXVAR_BinValues,  0.1);   
    $hash->{owg_val}=sprintf("%5.2f",(1-$pos/255.0)*100);  
  }
  return undef;
}



1;

=pod 
=item device
=item summary to control 1-Wire variable resistor DS2890
=begin html

<a name="OWVAR"></a>
        <h3>OWVAR</h3>
        <p>FHEM module to commmunicate with 1-Wire bus digital potentiometer devices of type DS2890<br />
        <br />This 1-Wire module works with the OWX interface module, but not yet with the OWServer interface module.
          
        </p>
         <a name="OWVARexample"></a>
        <h4>Example</h4>
        <p>
            <code>define OWX_P OWVAR E8D09B030000 </code>
            <br />
            <code>attr OWX_P Function 1.02 * V + 0.58 | (U-0.58) / 1.02</code>
            <br />
        </p><br />
        <a name="OWVARdefine"></a>
        <h4>Define</h4>
        <p>
        <code>define &lt;name&gt; OWVAR &lt;id&gt;</code> or <br/>
        <code>define &lt;name&gt; OWVAR &lt;fam&gt;.&lt;id&gt; </code>
        <br /><br /> Define a 1-Wire digital potentiometer device.</p>
        <ul>
          <li>
           <code>&lt;fam&gt;</code>
                <br />2-character unique family id, must be 2C </li>
          <li>
            <code>&lt;id&gt;</code>
            <br />12-character unique ROM id of the thermometer device without family id and CRC
            code 
         </li>
        </ul>
        <a name="OWVARset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owvar_value">
                    <code>set &lt;name&gt; value &lt;float&gt;</code></a>
                <br /> The value of the potentiometer resistance against ground. Arguments may be in the 
                range of [0,100] without a Function attribute, or in the range needed for a <a href="#owvar_function">Function</a> </li>
        </ul>
        <br />
        <a name="OWVARget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owvar_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
        </ul>
        <br />
        <a name="OWVARattr"></a>
        <h4>Attributes</h4>
        <ul>    
         <li><a name="owvar_cname"><code>attr &lt;name&gt; Name
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the reading [|name used in state reading]. </li>
            <li><a name="owvar_cunit"><code>attr &lt;name&gt; Unit
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />unit of measurement used in state reading. </li>
          <li><a name="owvar_cfunction">  <code>attr &lt;name&gt; Function
                        &lt;string&gt;|&lt;string&gt;</code></a>
            <br />The first string is an arbitrary functional expression u(V) involving the variable V. V is replaced by 
                 the raw potentiometer reading (in the range of [0,100]). The second string must be the inverse
                 function v(U) involving the variable U, such that U can be replaced by the value given in the 
                 <a href="#OWVARset">Set</a> argument. Care has to taken that v(U) is in the range [0,100].
                 No check on the validity of these functions is performed, 
                 <b>singularities may crash FHEM.</b> <a href="#OWVARexample">Example see above</a>.
                 </li>
           <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        
=end html
=cut
