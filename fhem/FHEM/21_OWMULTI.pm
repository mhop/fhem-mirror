########################################################################################
#
# OWMULTI.pm
#
# FHEM module to commmunicate with 1-Wire chip DS2438Z - Smart Battery Monitor
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
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
#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

sub Log($$);

my $owx_version="7.2";
#-- flexible channel name
my ($owg_channel,$owg_schannel,$owg_sichannel);

my %gets = (
  "id"          => ":noArg",
  "reading"     => ":noArg",
  "temperature" => ":noArg",
  "VDD"         => ":noArg",
  "raw"         => ":noArg",
  "version"     => ":noArg"
);

my %sets = (
  "interval"    => "",
  "inittime"    => ":noArg",
  "offset"      => ":-3,-2,-1,0,1,2,3",
  "calibrate"   => ":noArg",
  "startdischarge" => ":noArg"
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
  $hash->{NotifyFn}= "OWMULTI_Notify";
  $hash->{InitFn}  = "OWMULTI_Init";
  $hash->{AttrFn}  = "OWMULTI_Attr";

  $hash->{AttrList}= "IODev do_not_notify:0,1 model:DS2438 verbose:0,1,2,3,4,5 ".
                     "tempOffset tempUnit:Celsius,Fahrenheit,Kelvin ".
                     "VName VUnit VFunction WName WUnit WFunction XName XUnit XFunction ".
                     "interval ".
                     $readingFnAttributes;
                     
  #-- temperature and voltage globals - always the raw values from the device
  for(my $i=0;$i<7;$i++){
    $hash->{owg_val}->[$i] = undef;
  }
               
  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}

#######################################################################################
#
# OWMULTI_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWMULTI_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      #-- interval modified at runtime
      $key eq "interval" and do {
        #-- check value
        return "OWMULTI: set $name interval must be >= 0" if(int($value) < 0);
        #-- update timer
        $hash->{INTERVAL} = int($value);
        if ($init_done) {
          RemoveInternalTimer($hash);
          InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 0);
        }
        last;
      };
      $key eq "IODev" and do {
        AssignIoPort($hash,$value);
        if( defined($hash->{IODev}) ) {
          if ($init_done) {
            OWMULTI_Init($hash);
          }
        }
        last;
      }
    }
  }
  return $ret;
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
       
  #-- different types of definition allowed
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  #-- no model, 12 characters
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2438";
    $fam           = "26";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
    CommandAttr (undef,"$name model DS2438");
  #-- no model, 2+12 characters
   } elsif(  $a2 =~ m/^[0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
    $fam           = substr($a[2],0,2);
    $id            = substr($a[2],3);
    if(int(@a)>=4) { $interval = $a[3]; }
    if( $fam eq "26" ){
      $model = "DS2438";
      CommandAttr (undef,"$name model DS2438"); 
    }elsif( $fam eq "A6" ){
      $model = "DS2438a";
      CommandAttr (undef,"$name model DS2438a"); 
    }else{
      return "OWMULTI: Wrong 1-Wire device family $fam";
    }
  #-- model, 12 characters
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    if( $model eq "DS2438" ){
      $fam = "26";
      CommandAttr (undef,"$name model DS2438"); 
    }elsif( $model eq "DS2438a" ){
      $fam = "A6";
      CommandAttr (undef,"$name model DS2438a"); 
    }else{
      return "OWMULTI: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWMULTI: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }
  
  #-- determine CRC Code - only if this is a direct interface
  $crc = sprintf("%02x",OWX_CRC($fam.".".$id."00"));
  
  #-- define device internals
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{ERRCOUNT}   = 0;
  $hash->{ROM_ID}     = "$fam.$id.$crc";
  $hash->{INTERVAL}   = $interval;

  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}) or !defined($hash->{IODev}->{NAME}) ){
    return "OWMULTI: Warning, no 1-Wire I/O device found for $name.";
  } 

  $main::modules{OWMULTI}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWMULTI:  Device $name defined."; 

  $hash->{NOTIFYDEV} = "global";

  if ($init_done) {
    OWMULTI_Init($hash);
  }
  return undef;
}

########################################################################################
#
# OWMULTI_Notify - implements the Notify Function  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_Notify ($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    OWMULTI_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

########################################################################################
#
# OWMULTI_Init - implements the Init function  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_Init ($) {
  my ($hash)=@_;
  #-- Start timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+10, "OWMULTI_GetValues", $hash, 0);
  return undef; 
}
  
########################################################################################
#
# OWMULTI_ChannelNames - find the real channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWMULTI_ChannelNames($) { 
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
  my $state  = $hash->{READINGS}{"state"}{VAL};
   
  my ($cname,@cnama,$unit);
  my ($tunit,$toffset,$tfactor,$tabbr,$vfunc,$wfunc);

  #-- Set channel name, channel unit for voltage channel
  $cname = defined($attr{$name}{"VName"})  ? $attr{$name}{"VName"} : "voltage|vad";
  @cnama = split(/\|/,$cname);
  if( int(@cnama)!=2){
    push(@cnama,$cnama[0]);
  }
 
  #-- unit
  $unit = defined($attr{$name}{"VUnit"})  ? $attr{$name}{"VUnit"} : "V";
  $unit = ""
    if($unit eq "none");
    
  #-- put into readings
  $owg_channel = $cnama[0]; 
  $hash->{READINGS}{$owg_channel}{VAL}      = " ";  
  $hash->{READINGS}{$owg_channel}{ABBR}     = $cnama[1];  
  $hash->{READINGS}{$owg_channel}{UNIT}     = " ".$unit;
  
  
  #-- Set channel name, channel unit for sense channel
  $cname = defined($attr{$name}{"WName"})  ? $attr{$name}{"WName"} : "vsense|vs";
  @cnama = split(/\|/,$cname);
  if( int(@cnama)!=2){
    push(@cnama,$cnama[0]);
  }
 
  #-- unit
  $unit = defined($attr{$name}{"WUnit"})  ? $attr{$name}{"WUnit"} : "V";
  if($unit eq "none"){
    $unit = ""
  }else{
    $unit = " ".$unit
  }  
    
  #-- put into readings
  $owg_schannel = $cnama[0]; 
  $hash->{READINGS}{$owg_schannel}{VAL}      = " ";  
  $hash->{READINGS}{$owg_schannel}{ABBR}     = $cnama[1];  
  $hash->{READINGS}{$owg_schannel}{UNIT}     = $unit;
  
  #-- Set channel name, channel unit for sense integrated channel
  $cname = defined($attr{$name}{"XName"})  ? $attr{$name}{"XName"} : "vsense.t|vs.t";
  @cnama = split(/\|/,$cname);
  if( int(@cnama)!=2){
    push(@cnama,$cnama[0]);
  }
 
  #-- unit
  $unit = defined($attr{$name}{"XUnit"})  ? $attr{$name}{"XUnit"} : "Vs";
  if($unit eq "none"){
    $unit = ""
  }else{
    $unit = " ".$unit
  }  
    
  #-- put into readings
  $owg_sichannel = $cnama[0]; 
  $hash->{READINGS}{$owg_sichannel}{VAL}      = " ";  
  $hash->{READINGS}{$owg_sichannel}{ABBR}     = $cnama[1];  
  $hash->{READINGS}{$owg_sichannel}{UNIT}     = $unit;
    
  #-- temperature scale 
  $hash->{READINGS}{"temperature"}{UNIT} = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : "Celsius";
  $tunit  = defined($attr{$name}{"tempUnit"}) ? $attr{$name}{"tempUnit"} : $hash->{READINGS}{"temperature"}{UNIT};
  $toffset = defined($attr{$name}{"tempOffset"}) ? $attr{$name}{"tempOffset"} : 0.0 ;
  $tfactor = 1.0;
  
  if( $tunit eq "none" ){
    $tabbr   = "";
  }elsif( $tunit eq "Celsius" ){
    $tabbr   = " °C";
  } elsif ($tunit eq "Kelvin" ){
    $tabbr   = " K";
    $toffset += "273.16"
  } elsif ($tunit eq "Fahrenheit" ){
    $tabbr   = " °F";
    $toffset = ($toffset+32)/1.8;
    $tfactor = 1.8;
  } else {
    $tabbr="?";
    Log 1, "OWMULTI_ChannelNames: unknown unit $tunit";
  }
  
  #-- these values are rather complex to obtain, therefore save them in the hash
  $hash->{READINGS}{"temperature"}{ABBR}     = "T";
  $hash->{READINGS}{"temperature"}{UNIT}     = $tabbr;
  $hash->{tempf}{offset}                     = $toffset;
  $hash->{tempf}{factor}                     = $tfactor;
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
  my ($toffset,$tfactor,$tval,$vfunc,$wfunc,$xfunc,$vval,$wval,$xval);
  my $svalue  = "";
  
  #-- no change in any value if invalid reading DOES NOT WORK !!
  return if( ($hash->{owg_val}->[0] eq "") || ($hash->{owg_val}->[1] eq "") || ($hash->{owg_val}->[2] eq "") || ($hash->{owg_val}->[3] eq "") || ($hash->{owg_val}->[4] eq ""));
  
  #-- obtain channel names
  OWMULTI_ChannelNames($hash);
  
  #-- correct values for proper offset, factor 
  $toffset = $hash->{tempf}{offset};
  $tfactor = $hash->{tempf}{factor};
  $tval    = int(10*($hash->{owg_val}->[0] + $toffset)*$tfactor+0.5)/10;
  
  #-- attribute V/WFunction defined ?
  $vfunc   = defined($attr{$name}{"VFunction"}) ? $attr{$name}{"VFunction"} : "V";
  $wfunc   = defined($attr{$name}{"WFunction"}) ? $attr{$name}{"WFunction"} : "W";
  $xfunc   = defined($attr{$name}{"XFunction"}) ? $attr{$name}{"XFunction"} : "X";

  #-- replace by proper values 
  $vfunc =~ s/VDD/\$hash->{owg_val}->[1]/g;
  $vfunc =~ s/V/\$hash->{owg_val}->[2]/g;
  $vfunc =~ s/T/\$tval/g;
  
  $wfunc =~ s/W/\$hash->{owg_val}->[3]/g;
 
  $xfunc =~ s/X/\$hash->{owg_val}->[4]/g;
  
  #-- determine the measured value from the function
  $vfunc = "\$hash->{owg_val}->[1] = $hash->{owg_val}->[1]; \$hash->{owg_val}->[2] = $hash->{owg_val}->[2]; \$tval = $tval; ".$vfunc;
  #Log 1, "vfunc= ".$vfunc;
  $vfunc = eval($vfunc);
  if( !$vfunc ){
    $vval = 0.0;
  } elsif( $vfunc ne "" ){
    $vval = int( $vfunc*100+0.5)/100;
  } else {
    $vval = "???"; 
  }
  
  $wfunc = "\$hash->{owg_val}->[3] = $hash->{owg_val}->[3]; ".$wfunc;
  $wfunc = eval($wfunc);
  if( !$wfunc ){
    $wval = 0.0;
  } elsif( $wfunc ne "" ){
    if( abs($wfunc) > 1 ){
      $wval = int( $wfunc*100+0.5)/100;
    }elsif( abs($wfunc) > 0.1 ){ 
      $wval = int( $wfunc*1000+0.5)/1000;
    }elsif( abs($wfunc) > 0.01 ){ 
      $wval = int( $wfunc*10000+0.5)/10000;
    }elsif( abs($wfunc) > 0.001 ){ 
      $wval = int( $wfunc*100000+0.5)/100000;    
    }else{
      $wval = $wfunc;
    }   
  } else {
    $wval = "???";
  }
  
  $xfunc = "\$hash->{owg_val}->[4] = $hash->{owg_val}->[4]; ".$xfunc;
  #Log 1, "xfunc= ".$xfunc;
  $xfunc = eval($xfunc);
  if( !$xfunc ){
    $xval = 0.0;
  } elsif( $xfunc ne "" ){
    if( abs($xfunc) > 1 ){
      $xval = int( $xfunc*100+0.5)/100;
    }elsif( abs($xfunc) > 0.1 ){ 
      $xval = int( $xfunc*1000+0.5)/1000;
    }elsif( abs($xfunc) > 0.01 ){ 
      $xval = int( $wfunc*10000+0.5)/10000;
    }elsif( abs($xfunc) > 0.001 ){ 
      $xval = int( $xfunc*100000+0.5)/100000;    
    }else{
      $xval = $xfunc;
    }   
  } else {
    $xval = "???";
  }
  
  #-- string buildup for return value, STATE 
  $svalue .= sprintf( "%s: %5.2f%s (T: %5.1f%s %s: %5.2f%s %s: %5.2f%s)", 
    $hash->{READINGS}{$owg_channel}{ABBR}, $vval,$hash->{READINGS}{$owg_channel}{UNIT},
    $tval,$hash->{READINGS}{"temperature"}{UNIT}, $hash->{READINGS}{$owg_schannel}{ABBR}, $wval,$hash->{READINGS}{$owg_schannel}{UNIT},
                                                  $hash->{READINGS}{$owg_sichannel}{ABBR}, $xval,$hash->{READINGS}{$owg_sichannel}{UNIT});
  
  $hash->{offset}=$hash->{owg_val}->[5];
  
  #-- put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,$owg_channel,$vval);
  readingsBulkUpdate($hash,$owg_schannel,$wval);
  readingsBulkUpdate($hash,$owg_sichannel,$xval);
  readingsBulkUpdate($hash,"time",$hash->{owg_val}->[6]);
  readingsBulkUpdate($hash,"VDD",sprintf("%4.2f",$hash->{owg_val}->[1]));
  readingsBulkUpdate($hash,"temperature",$tval);
  
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsEndUpdate($hash,1); 

  return $svalue;
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
  my $msg = "OWMULTI: Get with unknown argument $a[1], choose one of ";
  $msg .= "$_$gets{$_} " foreach (keys%gets);
  return $msg
    if(!defined($gets{$a[1]}));
  
  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$name.id => $value";
  } 
  
  #-- hash of the busmaster
  my $master       = $hash->{IODev};
  #-- Get other values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $owx_version";
  }
  
  #-- reset current ERRSTATE
  $hash->{ERRSTATE} = 0;
  
  #-- for the other readings we need a new reading
  #-- OWX interface
  if( $interface eq "OWX" ){
    #-- not different from getting all values ..
    $ret = OWXMULTI_GetValues($hash);
  #-- OWFS interface  
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSMULTI_GetValues($hash);
  #-- Unknown interface
  }else{
    return "OWMULTI: Get with wrong IODev type $interface";
  }
  
  #-- process result
  if( $master->{ASYNCHRONOUS} ){
    #return "OWSMULTI: $name getting readings, please wait for completion";
    return undef;
  }else{
    if( defined($ret)  ){
      return "OWMULTI: Could not get values from device $name, reason $ret";
    }
 
    #-- return the special reading
    if ($reading eq "reading") {
      return "OWMULTI: $name.reading => ".$hash->{READINGS}{"state"}{VAL};
    }

    if ($reading eq "temperature") {
      return "OWMULTI: $name.temperature => ".
        $hash->{READINGS}{"temperature"}{VAL};
    } 
    if ($reading eq "VDD") {
      return "OWMULTI: $name.VDD => ".
         $hash->{owg_val}->[1];
    } 
    if ( $reading eq "raw") {
      return "OWMULTI: $name.raw => ".
        $hash->{owg_val}->[2]." V    ".$hash->{owg_val}->[3]." V";
    }
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

sub OWMULTI_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $value   = "";
  my $ret     = "";
  
  #-- check if device needs to be initialized
  OWMULTI_InitializeDevice($hash)
    if( $hash->{READINGS}{"state"}{VAL} eq "defined");
  
  RemoveInternalTimer($hash); 
  #-- auto-update for device disabled;
  return undef
    if( $hash->{INTERVAL} == 0 );
  #-- restart timer for updates  
  InternalTimer(time()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 0);

  #-- reset current ERRSTATE
  $hash->{ERRSTATE} = 0;
  
  #-- Get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXMULTI_GetValues($hash);
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSMULTI_GetValues($hash);
  }else{
    return "OWMULTI: GetValues with wrong IODev type $interface";
  }

  #-- process results
  if( defined($ret)  ){
    return "OWMULTI: Could not get values from device $name, reason $ret";
  }

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
  
  #-- Initial readings
  for( my $i=0;$i<7;$i++){
    $hash->{owg_val}->[$i] = "";
  }
  #-- Set state to initialized
  readingsSingleUpdate($hash,"state","initialized",1);
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
  #return join(" ", sort keys %sets) if(@a == 2);
  #return join(" ", map { "$_$sets{$_}" } keys %sets) if(@a <= 2);

  #-- check syntax
  #return "OWMULTI: Set needs one parameter"
  #  if(int(@a) != 3);
  #-- check argument
  return "OWMULTI: Set with unknown argument $a[1], choose one of ".join(" ", map { "$_$sets{$_}" } keys %sets)
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
    return "OWMULTI: set $name interval must be >= 0"
      if(int($value) < 0);
    # update timer
    $hash->{INTERVAL} = int($value);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWMULTI_GetValues", $hash, 0);
    return undef;
  }

  #-- set other values depending on interface type
  my $interface = $hash->{IODev}->{TYPE};
  
  #my $offset    = $hash->{tempf}{offset};
  #my $factor    = $hash->{tempf}{factor};
    
  #-- find upper and lower boundaries for given offset/factor
  #my $mmin = (-55+$offset)*$factor;
  #my $mmax = (125+$offset)*$factor;
  #return sprintf("OWMULTI: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
  #  if($value < $mmin || $value > $mmax);
    
  #-- seems to be ok, put into the device
  #$a[2]  = int($value/$factor-$offset);

  #-- OWX interface
  if( $interface eq "OWX" ){
    $ret = OWXMULTI_SetValues($hash,@a);
  #-- OWFS interface 
  }elsif( $interface eq "OWServer" ){
    $ret = OWFSMULTI_SetValues($hash,@a);
  } else {
    return "OWMULTI: Set with wrong IODev type $interface";
  }
  #-- process results
  if( defined($ret)  ){
    return "OWMULTI: Could not set device $name, reason: ".$ret;
  }
  
  #-- process results - we have to reread the device
  OWMULTI_GetValues($hash);

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
  
  delete($main::modules{OWMULTI}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSMULTI
#
########################################################################################
#
# OWFSMULTI_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSMULTI_GetValues($) {
  my ($hash) = @_;
  
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
          
  #-- reset presence
  $hash->{PRESENT}  = 0;
            
  #-- get values - or should we rather get the uncached ones ?
  $hash->{owg_val}->[0]   = OWServer_Read($master,"/$owx_add/temperature");
  $hash->{owg_val}->[1]   = OWServer_Read($master,"/$owx_add/VDD");
  $hash->{owg_val}->[2]   = OWServer_Read($master,"/$owx_add/VAD");
  #$hash->{owg_val}->[3]   = OWServer_Read($master,"/$owx_add/vis"); 
    
  #-- page 0
  my ($value,$lsb,$msb,$sign);
  my $res = OWServer_Read($master,"/$owx_add/pages/page.0");
  my @data=split(//,$res);
  
  #-- external voltage
  #$lsb  = ord($data[3]);
  #$msb  = ord($data[4]) & 3;
  #$hash->{owg_val}->[2] = ($msb*256 + $lsb)/100.;
  
  #-- check if it really differs from supply voltage - if not, we assume an error
  if( $hash->{owg_val}->[1] == $hash->{owg_val}->[2] ){
     return "false return from OWServer, VAD not different from VDD ";
  }
  
  #-- external current
  $lsb  = ord($data[5]);
  $msb  = ord($data[6]) & 3;  
  $sign = ord($data[6]) & 128;   
  if( $sign==0 ){
    $hash->{owg_val}->[3] = ($msb*256 + $lsb)/4096.;
  }else{
    $hash->{owg_val}->[3] = -((3-$msb)*256 + (255-$lsb)+ 1)/4096.; 
  }
  
  #-- check if it really differs from supply voltage - if not, we assume an error
  if( $hash->{owg_val}->[1] == $hash->{owg_val}->[2] ){
     return "false return from OWServer, VAD not different from VDD ";
  }
  
  #-- page 1
  $res = OWServer_Read($master,"/$owx_add/pages/page.1");
  @data=split(//,$res);
  
  #-- time 
  $hash->{owg_val}->[6] = ord($data[0]) + 256*( ord($data[1]) + 256*( ord($data[2]) + 256*ord($data[3]) ) );
     
  #-- integrated current
  $lsb  = ord($data[4]);
  $hash->{owg_val}->[4] = $lsb/2048;
    
  #-- offset
  $lsb  = ord($data[5]) & 248;
  $msb  = ord($data[6]) & 15;
  $sign = ord($data[6]) & 16;
       
  if( $sign==0 ){
    $hash->{owg_val}->[5] = ($msb*256. + $lsb)/8;  
  }else{
    $hash->{owg_val}->[5] = -((15-$msb)*256. + (248-$lsb))/8; 
  } 
  
  return "no return from OWServer"
    if( (!defined($hash->{owg_val}->[0])) || (!defined($hash->{owg_val}->[1])) || (!defined($hash->{owg_val}->[2])) || (!defined($hash->{owg_val}->[3])) );
  return "empty return from OWServer"
    if( ($hash->{owg_val}->[0] eq "") || ($hash->{owg_val}->[1] eq "") || ($hash->{owg_val}->[2] eq "") || ($hash->{owg_val}->[3] eq "") );
    
  #-- and now from raw to formatted values 
  $hash->{PRESENT}  = 1;
  $value = OWMULTI_FormatValues($hash);
  return undef;
}

#######################################################################################
#
# OWFSMULTI_SetValues - Set values in device
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
########################################################################################

sub OWFSMULTI_SetValues($@) {
  my ($hash, @a) = @_;
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  my ($res0,$res1,$cmd,$offset,$offset2,$sign,$offmsb,$offlsb);
  my $nocur=0;
  
  #-- page 0
  my @data0=();
  #-- page 1
  $res1 = OWServer_Read($master,"/$owx_add/pages/page.1");
  my @data1=split(//,$res1);

  #-- zero the time register
  if( $key eq "inittime" ){
    $cmd = sprintf("\x00\x00\x00\x00%c%c%c%c",ord($data1[4]),ord($data1[5]),ord($data1[6]),ord($data1[7]));
  }elsif( $key eq "startdischarge" ){
    $cmd = sprintf("\x00\x00\x00\x00\xFF%c%c%c",ord($data1[5]),ord($data1[6]),ord($data1[7]));
  #-- write the offset register
  }elsif( $key eq "offset" ){
    $nocur=1;
    #-- page 0
    $res0 = OWServer_Read($master,"/$owx_add/pages/page.0");
    if( $value >= 0 ){
      $offlsb=8*$value;
      $offmsb=0;
    }else{
      $offlsb= 248+8*$value;
      $offmsb= 31;
    }  
    $cmd = sprintf("%c%c%c%c%c%c%c%c",$data1[0],$data1[1],$data1[2],$data1[3],$data1[4],$offlsb,$offmsb,$data1[7]);
  #-- calibrate the offset register 
  }elsif( $key eq "calibrate" ){
    $nocur=1;
    #-- page 0
    $res0 = OWServer_Read($master,"/$owx_add/pages/page.0");
    my ($lsb,$msb,$sign);
    @data0=split(//,$res0);
    #-- external current
    $lsb  = ord($data0[5]);
    $msb  = ord($data0[6]) & 3;  
    $sign = ord($data0[6]) & 128;   
    if( $sign==0 ){
      $hash->{owg_val}->[3] = ($msb*256 + $lsb)/4096.;
    }else{
      $hash->{owg_val}->[3] = -((3-$msb)*256 + (255-$lsb))/4096.; 
    }
    $offset = -$hash->{owg_val}->[3];
    #-- 2's complement form = signed bytes
    if( $offset>0 ){
      $offset2 = abs($offset)*4096*8;
      $sign    = 0;
    }else{
      $offset2 = 8*(1024+$offset*4096);
      $sign    = 16;
    }  
    $offlsb = $offset2 & 255;
    $offmsb = int($offset2/256) & 15 + $sign;
    $cmd    = sprintf("%c%c%c%c%c%c%c%c",$data1[0],$data1[1],$data1[2],$data1[3],$data1[4],$offlsb,$offmsb,$data1[7]);
  }else{
    Log 1, "OWFSMULTI_SetValues: Unknown key $key";
    return undef;
  }
  if( $nocur==1 ){
    OWServer_Write($master, "/$owx_add/pages/page.0",sprintf("\x00%c%c%c%c%c%c%c",ord($data0[1]),ord($data0[2]),ord($data0[3]),ord($data0[4]),ord($data0[5]),ord($data0[6]),ord($data0[7])));
  }
  OWServer_Write(  $master, "/$owx_add/pages/page.1",$cmd);
  if( $nocur==1 ){
    OWServer_Write($master, "/$owx_add/pages/page.0",sprintf("\x01%c%c%c%c%c%c%c",ord($data0[1]),ord($data0[2]),ord($data0[3]),ord($data0[4]),ord($data0[5]),ord($data0[6]),ord($data0[7])));
  }
  return undef
 
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
# OWXMULTI_BinValues - Process reading from one device - translate binary into raw
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

sub OWXMULTI_BinValues($$$$$$$) {
  my ($hash, $context, $proc, $owx_dev, $crcpart, $numread, $res) = @_;
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  #-- inherit previous error
  my $error  = $hash->{ERRSTATE};
  my @data   = []; 
  my ($value,$lsb,$msb,$sign);
  my $msg;
  
  OWX_WDBGL($name,4,"OWXMULTI_BinValues: called for device $name in context $context with data ",$res);
  
  #-- always check for success, unused are reset, numread
  return unless ($context =~ /^ds2438.get.*$/);

  #-- we have to get rid  of the first 11 bytes
  if( length($res) == 20 ){
      $res=substr($res,11);
  }
  @data=split(//,$res);
    
  #-- process results
  if ( ($context =~ /^ds2438.getv[ad]$/) && ((ord($data[0]) & 112)!=0) ) {
    $msg   = "$name: conversion not complete or data invalid in context $context ";
    $error = 1;
  }elsif (OWX_CRC8(substr($res,0,8),$data[8]) eq "\0x00") {
    $msg   = "$name: invalid CRC ";
    $error = 1;
  }else{
    $msg   = "$name: no error, ";
  }
  OWX_WDBGL($name,5-4*$error,"OWXMULTI_BinValues:  ".$msg,$res);

  #-- this must be different for the different device types
  #   family = 26 => DS2438
  #   family = A6 => DS2438a
  #-- transform binary rep of VDD
  if( $context eq "ds2438.getvdd") { 
    #-- possible addtional check: $data[0] must be 09
    
    #-- temperature
    $lsb  = ord($data[1]);
    $msb  = ord($data[2]) & 127;
    $sign = ord($data[2]) & 128;
         
    #-- 2's complement form = signed bytes
    $hash->{owg_val}->[0] = $msb+ $lsb/256.;   
    if( $sign !=0 ){
       $hash->{owg_val}->[0] = -128+$hash->{owg_val}->[0];
    }
      
    #-- supply voltage
    $lsb  = ord($data[3]);
    $msb  = ord($data[4]) & 3;
    $hash->{owg_val}->[1] = ($msb*256+ $lsb)/100.;
    
  #-- transform binary rep of VAD
  }elsif( $context eq "ds2438.getvad") {      
    #-- possible addtional check: $data[0] must be 01
     
    #-- external voltage
    $lsb  = ord($data[3]);
    $msb  = ord($data[4]) & 3;
    $hash->{owg_val}->[2] = ($msb*256 + $lsb)/100.;
    
    #-- check if it really differs from supply voltage - if not, we assume an error
    if( $hash->{owg_val}->[1] == $hash->{owg_val}->[2] ){
      $msg   = "$name: VAD not different from VDD ";
      $error = 1;
      OWX_WDBGL($name,5-4*$error,"OWXMULTI_BinValues:  ".$msg,undef);
    }
    
    #-- external current
    $lsb  = ord($data[5]);
    $msb  = ord($data[6]) & 3;  
    $sign = ord($data[6]) & 128;   
    if( $sign==0 ){
      $hash->{owg_val}->[3] = ($msb*256 + $lsb)/4096.;
    }else{
      $hash->{owg_val}->[3] = -((3-$msb)*256 + (255-$lsb) + 1)/4096.; 
    }
    
  }elsif( $context eq "ds2438.getiac") {      
    #-- time 
    $hash->{owg_val}->[6] = ord($data[0]) + 256*( ord($data[1]) + 256*( ord($data[2]) + 256*ord($data[3]) ) );
     
    #-- integrated current
    $lsb  = ord($data[4]);
    $hash->{owg_val}->[4] = $lsb/2048;
    
    #-- offset
    $lsb  = ord($data[5]) & 248;
    $msb  = ord($data[6]) & 15;
    $sign = ord($data[6]) & 16;
    
    if( $sign==0 ){
      $hash->{owg_val}->[5] = ($msb*256. + $lsb)/8;  
    }else{
      $hash->{owg_val}->[5] = -((15-$msb)*256. + (248-$lsb))/8; 
    }
    #-- check
    #my( $offset,$offset2,$offmsb,$offlsb);
    #  $offset = $hash->{owg_val}->[5];
    #if( $offset >= 0 ){
    #  $offmsb = int($offset/32);
    #  $offlsb = int($offset-32*$offmsb)*8;
    #}else{
    #  $offmsb = 15 - int(-$offset/32);   
    #  $offlsb = 248 - int(-$offset-32*(15-$offmsb))*8
    #  #$offmsb += 16;
    #}
    #Log 1,"======> Offset $offset from register msb=$msb lsb=$lsb vs. calculated msb=$offmsb lsb=$offlsb";
   
    #-- and now from raw to formatted values
    if( $error ){
      $hash->{ERRCOUNT}++;
      $hash->{ERRSTATE} = 1;
    }else{
      $hash->{PRESENT} = 1;
      OWMULTI_FormatValues($hash);
    }
  }
  return undef;
}

########################################################################################
#
# OWXMULTI_GetValues - Get reading from one device
#
# Parameter hash = hash of device addressed
#           final= 1 if FormatValues is to be called
#
########################################################################################

sub OWXMULTI_GetValues($) {

  my ($hash) = @_;
  
  my ($res,$ret);
   
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  #------------------------------------------------------------------------------------
  #-- switch the device to current measurement on, VDD only
  #-- issue the match ROM command \x55 and the write scratchpad command
  #-- synchronous OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\x4E\x00\x09",0) eq 0 ){
      return "$owx_dev write status failed";
    }
  
    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command 
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
      return "$owx_dev copy scratchpad failed"; 
    }
  
    #-- initiate temperature conversion
    #-- conversion needs some 12 ms !
    #-- issue the match ROM command \x55 and the start conversion command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\x44",0) eq 0 ){
      return "$owx_dev temperature conversion failed";
    } 
    select(undef,undef,undef,0.012);
  
    #-- initiate voltage conversion
    #-- conversion needs some 6 ms  !
    #-- issue the match ROM command \x55 and the start conversion command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\xB4",0.01) eq 0 ){
      return "$owx_dev voltage conversion failed";
    } 
    select(undef,undef,undef,0.006);
  
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\xB8\x00",0.02) eq 0 ){
      return "$owx_dev recall memory failed";
    } 
    select(undef,undef,undef,0.012);
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,"\xBE\x00",9);
    #Log 1,"OWXMULTI: data length from reading device is ".length($res)." bytes";
    return "$owx_dev not accessible in 2nd step"
      if( $res eq 0 );
    return "$owx_dev has returned invalid data"
      if( length($res)!=20);
    $ret = OWXMULTI_BinValues($hash,"ds2438.getvdd",undef,$owx_dev,undef,undef,substr($res,11));
    #Log 1,"==============> TEMP/VDD obtained, ret=$ret";
    return $ret if (defined $ret);
    #------------------------------------------------------------------------------------
    #-- switch the device to current measurement on, V external only
    #-- issue the match ROM command \x55 and the write scratchpad command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\x4E\x00\x01",0) eq 0 ){
      return "$owx_dev write status failed";
    } 
    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
      return "$owx_dev copy scratchpad failed"; 
    }
    #-- initiate voltage conversion
    #-- conversion needs some 6 ms  !
    #-- issue the match ROM command \x55 and the start conversion command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\xB4",0.01) eq 0 ){
      return "$owx_dev voltage conversion failed";
    } 
    select(undef,undef,undef,0.006);
 
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\xB8\x00",0.02) eq 0 ){
      return "$owx_dev recall memory failed";
    } 
    select(undef,undef,undef,0.012);
  
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,"\xBE\x00",9);
    #Log 1,"OWXMULTI: data length from reading device is ".length($res)." bytes";
    return "$owx_dev not accessible in 2nd step"
      if( $res eq 0 );
    return "$owx_dev has returned invalid data"
      if( length($res)!=20);
    $ret = OWXMULTI_BinValues($hash,"ds2438.getvad",undef,$owx_dev,undef,undef,substr($res,11));
    #Log 1,"==============> VAD obtained, ret=$ret";
    return $ret if (defined $ret);
    #------------------------------------------------------------------------------------
    #-- read second memory page  
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,"\xB8\x01",0.02) eq 0 ){
      return "$owx_dev recall memory failed";
    } 
    select(undef,undef,undef,0.012);
  
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,"\xBE\x01",9);
    
    #-- process results
    return "$owx_dev not accessible in 2nd step"
      if( $res eq 0 );
    return "$owx_dev has returned invalid data"
      if( length($res)!=20);
    $ret = OWXMULTI_BinValues($hash,"ds2438.getiac",undef,$owx_dev,undef,undef,substr($res,11));
    #Log 1,"==============> 2nd page obtained, ret=$ret";
    return $ret;
  #-- asynchronous OWX interface
  }else{
    #-- switch the device to current measurement on, VDD only
    #-- issue the match ROM command \x55 and the write scratchpad command
    ####        master   slave  context       proc  owx_dev   data            crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "write SP",   0,    $owx_dev, "\x4E\x00\x09", 0,       2,       0,        undef,  0.015); 
  
    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command
    ####        master   slave  context      proc  owx_dev   data        crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "copy SP",   0,    $owx_dev, "\x48\x00", 0,       1,       0,        undef,  0.015); 
  
    #-- initiate temperature conversion
    #-- conversion needs some 12 ms !
    #-- issue the match ROM command \x55 and the start conversion command
    ####        master   slave  context           proc  owx_dev   data    crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "T conversion",   0,    $owx_dev, "\x44", 0,       0,       0,        undef,   0.015); 
  
    #-- initiate voltage conversion
    #-- conversion needs some 6 ms  !
    #-- issue the match ROM command \x55 and the start conversion command
    ####        master   slave  context           proc  owx_dev   data    crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "V conversion",   0,    $owx_dev, "\xB4", 0,       0,       0,        undef,   0.015); 
  
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command (page 0)
    ####        master   slave  context     proc  owx_dev   data        crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "recall",   0,    $owx_dev, "\xB8\x00", 0,       2,       0,        undef,   0.015); 
    
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    ####        master   slave  context            proc  owx_dev   data            crcpart  numread  startread callback delay
    #                                              1 provides additional reset after last operation
    OWX_Qomplex($master, $hash, "ds2438.getvdd",   1,    $owx_dev, "\xBE\x00", 0,       20,       0,        \&OWXMULTI_BinValues,   0.015); 
   
    #-- switch the device to current measurement on, V external only. Wait a little bit longer !
    #-- issue the match ROM command \x55 and the write scratchpad command
    ####        master   slave  context       proc  owx_dev   data            crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "write SP",   0,    $owx_dev, "\x4E\x00\x01", 0,       1,       0,        undef,   0.025); 

    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command
    ####        master   slave  context      proc  owx_dev   data        crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "copy SP",   0,    $owx_dev, "\x48\x00", 0,       1,       0,        undef,   0.015); 
  
    #-- initiate voltage conversion
    #-- conversion needs some 6 ms  !
    #-- issue the match ROM command \x55 and the start conversion command
    ####        master   slave  context           proc  owx_dev   data    crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "V conversion",   0,    $owx_dev, "\xB4", 0,       0,       0,        undef,   0.015); 
   
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command (page 0)
    ####        master   slave  context   proc  owx_dev   data        crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "recall", 0,    $owx_dev, "\xB8\x00", 0,       1,       0,        undef,   0.015); 
    
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    ####        master   slave  context            proc  owx_dev   data        crcpart  numread  startread callback delay
    #                                              1 provides additional reset after last operation
    OWX_Qomplex($master, $hash, "ds2438.getvad",   1,    $owx_dev, "\xBE\x00", 0,      20,       0,        \&OWXMULTI_BinValues,   0.015);
    
    #-- from memory to scratchpad
    #-- copy needs some 12 ms !
    #-- issue the match ROM command \x55 and the recall memory command (page 1)
    ####        master   slave  context   proc  owx_dev   data        crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "recall", 0,    $owx_dev, "\xB8\x01", 0,       1,       0,        undef,   0.015); 
    
    #-- NOW ask the specific device 
    #-- issue the match ROM command \x55 and the read scratchpad command \xBE
    #-- reading 9 + 2 + 9 data bytes = 20 bytes
    ####        master   slave  context            proc  owx_dev   data        crcpart  numread  startread callback delay
    #                                              1 provides additional reset after last operation
    OWX_Qomplex($master, $hash, "ds2438.getiac",   1,    $owx_dev, "\xBE\x01", 0,      20,       0,        \&OWXMULTI_BinValues,   0.015);


    return undef;
  }   
}
#######################################################################################
#
# OWXMULTI_SetValues - Set values in device
# 
# Parameter hash = hash of device addressed
#           a = argument array
#
########################################################################################

sub OWXMULTI_SetValues($@) {
  my ($hash, @a) = @_;
  
  my $name = $hash->{NAME};
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  #-- hash of the busmaster
  my $master = $hash->{IODev};
 
  #-- define vars
  my $key   = $a[1];
  my $value = $a[2];
  my ($cmd1,$cmd2);
  my $nocur=0;
  
  #-- iac register from value
  my $iac    = int($hash->{owg_val}->[4]*2048);
  
  #-- offset register from value
  my( $sign,$offset,$offset2,$offmsb,$offlsb);
    $offset = $hash->{owg_val}->[5];
  if( $offset >= 0 ){
    $offmsb = int($offset/32);
    $offlsb = int($offset-32*$offmsb)*8;
  }else{
    $offmsb = 15 - int(-$offset/32);   
    $offlsb = 248 - int(-$offset-32*(15-$offmsb))*8;
    $offmsb += 16;
  }
  
  #-- time register from value
  my $timea   = $hash->{owg_val}->[6];
  my $time3  = int($timea/16777216);
  my $time2  = int(($timea - $time3*16777216)/65536);
  my $time1  = int(($timea - $time3*16777216 - $time2*65536)/256);
  my $time0  = $timea - $time3*16777216 - $time2*65536 - $time1*256;  
 
  #------------------------------------------------------------------------------------
  #-- zero the time register
  if( $key eq "inittime" ){
    $cmd1 = sprintf("\x4E\x01\x00\x00\x00\x00%c%c%c",$iac,$offlsb,$offmsb);
    $cmd2 = "\x48\x01";
  }elsif( $key eq "startdischarge" ){
    $cmd1 = sprintf("\x4E\x01\x00\x00\x00\x00\xFF%c%c",$offlsb,$offmsb);
    $cmd2 = "\x48\x01";
  #-- write the offset register
  }elsif( $key eq "offset" ){
    $nocur=1;
    if( $value >= 0 ){
      $offlsb=8*$value;
      $offmsb=0;
    }else{
      $offlsb= 248+8*$value;
      $offmsb= 31;
    }  
    #Log 1,"========> Setting offset to msb=$offmsb lsb=$offlsb";
    $cmd1 = sprintf("\x4E\x01%c%c%c%c%c%c%c",$time0,$time1,$time2,$time3,$iac,$offlsb,$offmsb);
    $cmd2 = "\x48\x01";
  #-- calibrate the offset register 
  }elsif( $key eq "calibrate" ){
    $nocur=1;
    #-- get current value now
    $offset = -$hash->{owg_val}->[3];
    #-- 2's complement form = signed bytes
    if( $offset>=0 ){
      $offset2 = abs($offset)*4096*8;
      $sign    = 0;
    }else{
      $offset2 = 8*(1024+$offset*4096)+1;
      $sign    = 16;
    }  
    $offlsb = $offset2 & 255;
    $offmsb = int($offset2/256) & 15 + $sign;
    $cmd1 = sprintf("\x4E\x01%c%c%c%c%c%c%c",$time0,$time1,$time2,$time3,$iac,$offlsb,$offmsb);
    $cmd2 = "\x48\x01";
  }else{
    Log 1, "OWXMULTI_SetValues: Unknown key $key";
    return undef;
  }
  #------------------------------------------------------------------------------------
  #-- synchronous OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    #-- switch the current measurement off
    if( $nocur==1 ){
      OWX_Reset($master);
      if( OWX_Complex($master,$owx_dev,"\x4E\x00\x09",0) eq 0 ){
        return "$owx_dev write status failed";
      }
  
      #-- copy scratchpad to register
      #-- issue the match ROM command \x55 and the copy scratchpad command 
      OWX_Reset($master);
      if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
        return "$owx_dev copy scratchpad failed"; 
      }
    }
    
    #-- issue the match ROM command \x55 and the write scratchpad command
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,$cmd1,0) eq 0 ){
      return "$owx_dev write status failed";
    }
  
    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command 
    OWX_Reset($master);
    if( OWX_Complex($master,$owx_dev,$cmd2,0) eq 0){
      return "$owx_dev copy scratchpad failed"; 
    }
    
    #-- switch the device to current measurement on, VDD only
    if( $nocur==1 ){
    #-- issue the match ROM command \x55 and the write scratchpad command
      OWX_Reset($master);
      if( OWX_Complex($master,$owx_dev,"\x4E\x00\x09",0) eq 0 ){
        return "$owx_dev write status failed";
      }
  
      #-- copy scratchpad to register
      #-- issue the match ROM command \x55 and the copy scratchpad command 
      OWX_Reset($master);
      if( OWX_Complex($master,$owx_dev,"\x48\x00",0) eq 0){
        return "$owx_dev copy scratchpad failed"; 
      }
    }
  #-- asynchronous OWX interface
  }else{
    #-- switch the current measurement off
    if( $nocur==1 ){
      #-- issue the match ROM command \x55 and the write scratchpad command
      ####        master   slave  context       proc  owx_dev   data            crcpart  numread  startread callback delay
      OWX_Qomplex($master, $hash, "write SP",   0,    $owx_dev, "\x4E\x00\x00", 0,       1,       0,        undef,   0.015); 

      #-- copy scratchpad to register
      #-- issue the match ROM command \x55 and the copy scratchpad command
      ####        master   slave  context      proc  owx_dev   data        crcpart  numread  startread callback delay
      OWX_Qomplex($master, $hash, "copy SP",   0,    $owx_dev, "\x48\x00", 0,       1,       0,        undef,   0.015); 
    }
    
    #-- issue the match ROM command \x55 and the write scratchpad command
    ####        master   slave  context       proc  owx_dev   data   crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "write SP",   0,    $owx_dev, $cmd1, 0,       2,       0,        undef,  0.015); 
  
    #-- copy scratchpad to register
    #-- issue the match ROM command \x55 and the copy scratchpad command
    ####        master   slave  context      proc  owx_dev   data   crcpart  numread  startread callback delay
    OWX_Qomplex($master, $hash, "copy SP",   0,    $owx_dev, $cmd2, 0,       1,       0,        undef,  0.015); 
    
    #-- switch the device to current measurement on, V external only
    if( $nocur==1 ){
      #-- issue the match ROM command \x55 and the write scratchpad command
      ####        master   slave  context       proc  owx_dev   data            crcpart  numread  startread callback delay
      OWX_Qomplex($master, $hash, "write SP",   0,    $owx_dev, "\x4E\x00\x01", 0,       1,       0,        undef,   0.015); 

      #-- copy scratchpad to register
      #-- issue the match ROM command \x55 and the copy scratchpad command
      ####        master   slave  context      proc  owx_dev   data        crcpart  numread  startread callback delay
      OWX_Qomplex($master, $hash, "copy SP",   0,    $owx_dev, "\x48\x00", 0,       1,       0,        undef,   0.015); 
    }
  } 
  return undef;
}

1;

=pod
=item device
=item summary to control 1-Wire chip DS2438Z - Smart Battery Monitor
=begin html

 <a name="OWMULTI"></a>
        <h3>OWMULTI</h3>
        <ul>
        <p>FHEM module to commmunicate with 1-Wire smart battery
            monitor DS2438 <br /> <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
                (prerequisite: Add this module's name to the list of clients in OWServer).
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first.</p>
       <h4>Example</h4>
        In this example, the DS2438 is used to monitor a rechargeable battery of 8.5 V and 8.8 Ah capacity. For this capacity the 
        data sheet of the DS2438 suggests a resistor of 0.015 Ohm across the Vsense+ ... Vsense- terminals.
        <p>
            <code>define USV OWMULTI 7C5034010000 30</code>
            <br />
            <code>attr USV VName battery voltage|Vbatt</code>
            <br/>
            <code>attr USV WName battery current|Ibatt</code>
            <br />
            <code>attr USV WUnit mA</code>
            <br />
            <code>attr USV WFunction 1000*W/0.015</code>
            <br/>
            <code>attr USV XName battery capacity|Cbatt</code>
            <br />
            <code>attr USV XUnit mAh</code>
            <br />
            <code>attr USV XFunction 8800-1000*(255/2048.-X)/0.015</code>
        </p>
         Notes: <ul>
         <li>The voltage at the VAD terminal must be in the range from 2.4 ... 10 V</li>
         <li>The voltage between the Vsense+ and Vsense- terminals must be in the range from -0.25 ... 0.25 V</li>
         <li>For calibration of the Vsense measurement:
           <ol><li>Execute the command <code>set &lt;name&gt; offset 0</code> to clear the offset register</li>
           <li>Force zero voltage across the Vsense+ and Vsense- terminals (=zero current)</li>
           <li>Execute the command <code>set &lt;name&gt; calibrate</code> to set the offset register</li>
           </ol></li>
         <li>Due to the limitations of the integration process, the value functions for the sense channel <code>WFunction</code> and
           for the sense integrated channel <code>XFunction</code> must be functions involving a linear and a constant term, see example above.</li>
         <li>To obtain the proper current in A, one must set <code>WFunction</code> to the value of
         (W/resistor value).</li>
         <li>The maximum value for the Vsense.t integration is 255/2048 = 0.1245117 Vh. This value is put into the register by executing the command 
         <code>set &lt;name&gt; startdischarge</code>. To obtain the proper remaining battery capacity in Ah, one must set <code>XFunction</code> to the value of
         (max. battery capacity (in Ah) - (255/2048-X)/resistor value).</li>
         <li>The time register is incremented by 1 each second, see commands below.</li>
         </ul>
        <a name="OWMULTIdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWMULTI [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
            <code>define &lt;name&gt; OWMULTI &lt;fam&gt;.&lt;id&gt; [&lt;interval&gt;]</code> 
            <br /><br /> Define a 1-Wire smart battery monitor</p>
        <ul>
            <li>
                <code>[&lt;model&gt;]</code><br /> Defines the model (and thus 1-Wire family
                id), currently the following values are permitted: <ul>
                    <li>model DS2438 with family id 26 (default if the model parameter is omitted) or DS2438a with family id A6.
                        For both, a temperature value T, an external voltage VAD (1.5V < VAD < 2 VDD), the supply
                        voltage VDD and a sense voltage Vsens (-0.25V < Vsens < 0.25V) are measured. Calculated are running time in seconds and time integrated sense voltage Vsens.t.</li>
                 
                </ul>
            </li>
             <li>
                <code>&lt;fam&gt;</code>
                <br />2-character unique family id, see above 
            </li>
            <li>
                <code>&lt;id&gt;</code>
                <br />12-character unique ROM id of the converter device without family id and CRC
                code </li>
            <li>
                <code>&lt;interval&gt;</code>
                <br />Measurement interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update. </li>
        </ul>
        <a name="OWMULTIset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owmulti_calibrate">
                    <code>set &lt;name&gt; calibrate</code></a><br /> Write the inverse value of the Vsense register into the offset register, see notes above </li>
            <li><a name="owmulti_offset">
                    <code>set &lt;name&gt; offset [-1,-2,-1,0,1,2,3] </code></a><br /> Write this value into the offset register, see notes above </li>
            <li><a name="owmulti_inittime">
                    <code>set &lt;name&gt; inittime</code></a><br /> Write a zero into the time register, see notes above </li>
            <li><a name="owmulti_startdischarge">
                    <code>set &lt;name&gt; startdischarge</code></a><br /> Write the maximum value into the time integrated sense register, see notes above </li>
            <li><a name="owmulti_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update. </li>
        </ul>
        <a name="OWMULTIget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owmulti_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owmulti_reading">
                    <code>get &lt;name&gt; reading</code></a><br />Obtain all measurement values. </li>
            <li><a name="owmulti_temperature">
                    <code>get &lt;name&gt; temperature</code></a><br />Obtain the temperature value. </li>
            <li><a name="owmulti_vdd">
                    <code>get &lt;name&gt; VDD</code></a><br />Obtain the actual supply voltage. </li>
            <li><a name="owmulti_raw">
                    <code>get &lt;name&gt; raw</code></a><br />Obtain the raw readings for VAD=V, Vsense=W and VSense.t=X.</li>
        </ul>
        <a name="OWMULTIattr"></a>
        <h4>Attributes</h4>
        <ul><li><a name="owtherm_interval2">
                    <code>attr &lt;name&gt; interval &lt;int&gt;</code></a><br /> measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update.</li>
            <li><a name="owmulti_vname"><code>attr &lt;name&gt; VName
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the voltage channel [|short name used in state reading]. </li>         
            <li><a name="owmulti_vunit"><code>attr &lt;name&gt; VUnit
                        &lt;string&gt;</code></a>
                <br />unit of measurement for the voltage channel used in state reading (default "V", set to "none" for  empty).</li>
            <li><a name="owmulti_vfunction"><code>attr &lt;name&gt; VFunction
                    &lt;string&gt;</code></a>
                <br />arbitrary functional expression involving the values VDD, V and T: <ul>
                    <li>VDD is replaced by the measured supply voltage in Volt,</li>
                    <li>V by the measured external voltage channel VAD,</li>                
                    <li>T by the measured and corrected temperature in its unit</li>
                </ul></li>
            <li><a name="owmulti_wname"><code>attr &lt;name&gt; WName
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the sense channel [|short name used in state reading] </li>
            <li><a name="owmulti_wunit"><code>attr &lt;name&gt; WUnit
                        &lt;string&gt;</code></a>
                <br />unit of measurement for the sense channel used in state reading (default "V", set to "none" for empty).</li>
            <li><a name="owmulti_wfunction"><code>attr &lt;name&gt; WFunction
                    &lt;string&gt;</code></a>
                <br />linear functional expression involving the value W which is replaced by the measured external sense channel Vsense</li>
            <li><a name="owmulti_xname"><code>attr &lt;name&gt; XName
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the time integrated sense channel [|short name used in state reading]. </li>
            <li><a name="owmulti_xunit"><code>attr &lt;name&gt; XUnit
                        &lt;string&gt;</code></a>
                <br />unit of measurement for the time integrated sense channel used in state reading (default "Vs", set to "none" for empty).</li>
            <li><a name="owmulti_xfunction"><code>attr &lt;name&gt; XFunction
                    &lt;string&gt;</code></a>
                <br />linear functional expression involving the value X which is replaced by the time integrated external sense channel Vsense.t</li>
            <li><a name="owmulti_tempOffset"><code>attr &lt;name&gt; tempOffset &lt;float&gt;</code>
                </a>
                <br />temperature offset in K added to the raw temperature reading. </li>
            <li><a name="owmulti_tempUnit"><code>attr &lt;name&gt; tempUnit
                        Celsius|Kelvin|Fahrenheit</code>
                </a>
                <br />unit of measurement (temperature scale), default is Celsius = &deg;C </li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        </ul>
=end html
=cut