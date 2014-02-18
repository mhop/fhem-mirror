########################################################################################
#
# OWSWITCH.pm
#
# FHEM module to commmunicate with 1-Wire adressable switches DS2413, DS206, DS2408
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id$
#
########################################################################################
#
# define <name> OWSWITCH [<model>] <ROM_ID> [interval] or OWSWITCH <fam>.<ROM_ID> [interval]
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2413. Allowed values are DS2413, DS2406 
#       <fam> is a 1-Wire family id, currently allowed values are 12, 29, 3A
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id       => FAM_ID.ROM_ID.CRC 
# get <name> present  => 1 if device present, 0 if not
# get <name> interval => query interval
# get <name> input <channel-name> => state for channel (name A, B or defined channel name)
#            note: this value reflects the measured value, not necessarily the one set as
#            output state, because the output transistors are open collector switches. A measured
#            state of 1 = OFF therefore corresponds to an output state of 1 = OFF, but a measured
#            state of 0 = ON can also be due to an external shortening of the output.
# get <name> gpio  => values for channels
# get <name> version  => OWX version number
#
# set <name> interval => set period for measurement
# set <name> output <channel-name>  on|off|on-for-timer <int>|on-for-timer <int>
#            => set value for channel (name A, B or defined channel name)
#            note: 1 = OFF, 0 = ON in normal usage. See also the note above
#            ON-for-timer/OFF-for-timer will set the desired value only for <int> seconds
#            and then will return to the opposite value.
# set <name> gpio  value => set values for channels (3 = both OFF, 1 = B ON 2 = A ON 0 = both ON)
# set <name> init yes => re-initialize device
#
# Additional attributes are defined in fhem.cfg, in some cases per channel, where <channel>=A,B
# Note: attributes are read only during initialization procedure - later changes are not used.
#
# attr <name> stateS <string> = character string denoting external shortening condition, default is (ext)
#                                        overwritten by an attribute setting "red angled arrow downwward"
#
# attr <name> <channel>Name <string>|<string> = name for the channel | a type description for the measured value
# attr <name> <channel>Unit <string>|<string> = values to display in state variable for on|off condition
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
sub Log($$);

my $owx_version="5.05";
#-- fixed raw channel name, flexible channel name
my @owg_fixed   = ("A","B","C","D","E","F","G","H");
my @owg_channel = ("A","B","C","D","E","F","G","H");

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "input"       => "",
  "gpio"        => "",
  "version"     => ""
);

my %sets = (
  "interval"    => "",
  "output"      => "",
  "gpio"        => "",
  "init"        => ""
);

my %updates = (
  "present"     => "",
  "gpio"        => ""
);

my %cnumber = (
  "DS2413" => 2,
  "DS2406" => 2,
  "DS2408" => 8
  );

########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWSWITCH
#
########################################################################################
#
# OWSWITCH_Initialize
#
# CalledBy:  FHEM
# Calling:   --
# Parameter: hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWSWITCH_Define";
  $hash->{UndefFn} = "OWSWITCH_Undef";
  $hash->{GetFn}   = "OWSWITCH_Get";
  $hash->{SetFn}   = "OWSWITCH_Set";
  $hash->{AttrFn}  = "OWSWITCH_Attr";
  
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2413,DS2406,DS2408 loglevel:0,1,2,3,4,5 ".
    "stateS interval ".
    $readingFnAttributes;
 
  #-- initial list of attributes
  for( my $i=0;$i<8;$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Unit";
  }
 
  $hash->{AttrList} = $attlist; 
  
  #-- channel values - always the raw input resp. output values from the device
  $hash->{owg_val} = [];
  $hash->{owg_vax} = [];
  
  #-- ASYNC this function is needed for asynchronous execution of the device reads 
  $hash->{AfterExecuteFn} = "OWXSWITCH_BinValues";
  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}

#########################################################################################
#
# OWSWITCH_Define - Implements DefFn function
#
# CalledBy:  FHEM
# Calling:   -- 
# Parameter: hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWSWITCH_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWSWITCH [<model>] <id> [interval]
  # e.g.: define flow OWSWITCH 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWSWITCH: Wrong syntax, must be define <name> OWSWITCH [<model>] <id> [interval] or OWSWITCH <fam>.<id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- different types of definition allowed
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  #-- no model, 12 characters
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2413";
    CommandAttr (undef,"$name model DS2413"); 
    $fam           = "3A";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  #-- no model, 2+12 characters
   } elsif(  $a2 =~ m/^[0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
    $fam           = substr($a[2],0,2);
    $id            = substr($a[2],3);
    if(int(@a)>=4) { $interval = $a[3]; }
    if( $fam eq "3A" ){
      $model = "DS2413";
      CommandAttr (undef,"$name model DS2413"); 
    }elsif( $fam eq "12" ){
      $model = "DS2406";
      CommandAttr (undef,"$name model DS2406"); 
    }elsif( $fam eq "29" ){
      $model = "DS2408";
      CommandAttr (undef,"$name model DS2408"); 
    }else{
      return "OWSWITCH: Wrong 1-Wire device family $fam";
    }
  #-- model, 12 characters
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    if( $model eq "DS2413" ){
      $fam = "3A";
      CommandAttr (undef,"$name model DS2413"); 
    }elsif( $model eq "DS2406" ){
      $fam = "12";
      CommandAttr (undef,"$name model DS2406"); 
    }elsif( $model eq "DS2408" ){
      $fam = "29";
      CommandAttr (undef,"$name model DS2408"); 
    }else{
      return "OWSWITCH: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWSWITCH: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }
 
  #--   determine CRC Code - only if this is a direct interface
  $crc = sprintf("%02x",OWX_CRC($fam.".".$id."00"));
  
  #-- Define device internals
  $hash->{ROM_ID}     = "$fam.$id.$crc";
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  $hash->{ASYNC}      = 0; #-- false for now
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}->{NAME}) || !defined($hash->{IODev}) ){
    return "OWSWITCH: Warning, no 1-Wire I/O device found for $name.";
  }

  $main::modules{OWSWITCH}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWSWITCH: Device $name defined."; 
  
  #-- Start timer for updates
  InternalTimer(time()+10, "OWSWITCH_GetValues", $hash, 0);

  return undef; 
}

#######################################################################################
#
# OWSWITCH_Attr - Set one attribute value for device
#
# CalledBy:  FHEM
# Calling:   -- 
# Parameter: hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWSWITCH_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    #-- interval modified at runtime
   $key eq "interval" and do {
      #-- check value
      return "OWSWITCH: Set with short interval, must be > 1" if(int($value) < 1);
      #-- update timer
      $hash->{INTERVAL} = $value;
      if ($init_done) {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
      }
      last;
    };
  }
  return $ret;
}

########################################################################################
#
# OWSWITCH_ChannelNames - find the real channel names  
#
# CalledBy:  OWSWITCH_FormatValues, OWSWITCH_Get, OWSWITCH_Set
# Calling:   -- 
# Parameter: hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_ChannelNames($) { 
  my ($hash) = @_;
 
  my $name    = $hash->{NAME}; 
  my $state   = $hash->{READINGS}{"state"}{VAL};
 
  my ($cname,@cnama,$unit,@unarr);

  for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    #-- name
    $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|onoff";
    @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      Log 1, "OWSWITCH: Incomplete channel name specification $cname. Better use $cname|<type of data>"
        if( $state eq "defined");
      push(@cnama,"unknown");
    }
    #-- put into readings 
    $owg_channel[$i] = $cnama[0]; 
    $hash->{READINGS}{$owg_channel[$i]}{TYPE}     = $cnama[1];  
 
    #-- unit
    my $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "ON|OFF";
    my @unarr= split(/\|/,$unit);
    if( int(@unarr)!=2 ){
      Log 1, "OWSWITCH: Wrong channel unit specification $unit, replaced by ON|OFF"
        if( $state eq "defined");
      $unit="ON|OFF";
    }

    #-- put into readings
    $hash->{READINGS}{$owg_channel[$i]}{UNIT}     = $unit;
    $hash->{READINGS}{$owg_channel[$i]}{UNITABBR} = $unit;
  }
}

########################################################################################
#
# OWSWITCH_FormatValues - put together various format strings 
#
# CalledBy:  OWSWITCH_Get, OWSWITCH_Set
# Calling:   -- 
# Parameter; hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWSWITCH_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$vval,$vvax,$vstr,@unarr,$valid);
  my $svalue  = ""; 
  
  #-- external shortening signature
  my $sname = defined($attr{$name}{"stateS"})  ? $attr{$name}{"stateS"} : "&#x2607;";  
  
  #-- obtain channel names
  OWSWITCH_ChannelNames($hash);
  
  #-- put into READINGS
  readingsBeginUpdate($hash);

  #-- formats for output
  for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    
    #-- input state is 0 = ON or 1 = OFF
    $vval    = $hash->{owg_val}->[$i];
    #-- output state is 0 = ON or 1 = OFF
    $vvax    = $hash->{owg_vax}->[$i];
 
    #-- string buildup for return value and STATE
    @unarr= split(/\|/,$hash->{READINGS}{$owg_channel[$i]}{UNIT});
    $vstr    = $unarr[$vval];
    
    #-- put into readings only when valid
    if( ($vval == 1) && ($vvax == 0) ){
      $vstr ="???"
    }else{
      $vstr.= $sname if( ($vval == 0) && ($vvax == 1) );
      readingsBulkUpdate($hash,$owg_channel[$i],$vstr);
    } 
    $svalue .= sprintf( "%s: %s" , $owg_channel[$i], $vstr);

    #-- insert space 
    if( $i<($cnumber{$attr{$name}{"model"}}-1) ){
      $svalue .= " ";
    }
  }
  
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsEndUpdate($hash,1); 
 
  return $svalue;
}

########################################################################################
#
# OWSWITCH_Get - Implements GetFn function 
#
# CalledBy:  FHEM
# Calling:   OWSWITCH_ChannelNames,OWSWITCH_FormatValues,
#            OWFSSWITCH_GetState,OWXSWITCH_GetState,
#            OWX_Verify
# Parameter: hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWSWITCH_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my ($value,$value2,$value3)   = (undef,undef,undef);
  my $ret     = "";
  my ($offset,$factor,$page,$cname,@cnama,@channel);

  #-- check syntax
  return "OWSWITCH: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  return "OWSWITCH: Get with unknown argument $a[1], choose one of ".join(" ", sort keys %gets)
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

  #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$name.interval => $value";
  } 
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $owx_version";
  }
   
  #-- get channel names
  OWSWITCH_ChannelNames($hash);
  
  #-- get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};

  #-- get single state
  if( $reading eq "input" ){
    return "OWSWITCH: Get needs parameter when reading input: <channel>"
      if( int(@a)<2 );
    my $fnd=undef;
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      if( ($a[2] eq $owg_channel[$i]) || ($a[2] eq $owg_fixed[$i]) ){
        $fnd=$i;
        last;
      }
    }
    return "OWSWITCH: Invalid input address, must be A,B,... or defined channel name"
      if( !defined($fnd) );

    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
      #ASYNC OWXSWITCH_AwaitGetState($hash);
    #-- OWFS interface
    }elsif( $interface eq "OWFS" ){
      $ret = OWFSSWITCH_GetState($hash);
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process results
    return $name.".".$a[2]." => ".$hash->{READINGS}{$owg_channel[$fnd]}{VAL};
    
  #-- get all states
  }elsif( $reading eq "gpio" ){
    return "OWSWITCH: Get needs no parameter when reading gpio"
      if( int(@a)==1 );

    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
      #ASYNC OWXSWITCH_AwaitGetState($hash);
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSSWITCH_GetState($hash);
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process results
    if( defined($ret)  ){
      return "OWSWITCH: Could not get values from device $name, reason $ret";
    }
    return "OWSWITCH: $name.$reading => ".$hash->{READINGS}{"state"}{VAL};  
  }
}

#######################################################################################
#
# OWSWITCH_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = "";
  my $ret     = "";
  
  #-- check if device needs to be initialized
  OWSWITCH_InitializeDevice($hash)
    if( $hash->{READINGS}{"state"}{VAL} eq "defined"); 

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
  
  #-- Get readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    #-- max 3 tries
    for(my $try=0; $try<3; $try++){
      $ret = OWXSWITCH_GetState($hash);
      return if( !defined($ret) );
    } 
  }elsif( $interface eq "OWServer" ){
     $ret = OWFSSWITCH_GetState($hash);
  }else{
    Log 3, "OWSWITCH: GetValues with wrong IODev type $interface";
    return 1;
  }
  
  #-- process results
  if( defined($ret)  ){
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      $hash->{owg_val}->[$i] = 1;
      $hash->{owg_vax}->[$i] = 0;
    }
    Log 3, "OWSWITCH: Could not get values from device $name, reason $ret";
    return 1;
  }
  
  return undef;
}

########################################################################################
#
# OWSWITCH_InitializeDevice - initial readings 
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_InitializeDevice($) {

  my ($hash) = @_;
  my $name   = $hash->{NAME};
  
  #-- Initial readings 
  for( my $i=0;$i<$cnumber{$attr{$name}{"model"}} ;$i++) { 
    #-- Initial readings ERR
    $hash->{owg_val}->[$i]   = 1;
    $hash->{owg_vax}->[$i]   = 0;
  }
   
  #-- Set state to initialized
  readingsSingleUpdate($hash,"state","initialized",1);
  
  return undef;
}

#######################################################################################
#
# OWSWITCH_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWSWITCH_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  
  my ($cname,@cnama,@channel);
  my $ret="";
  my ($ret1,$ret2);
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", sort keys %sets);
    return $newkeys ;    
  }
  
  #-- check argument
  if( !defined($sets{$a[1]}) ){
        return "OWSWITCH: Set with unknown argument $a[1]";
  }
  
  #-- reset the device
  if($key eq "init") {
    return "OWSWITCH: Set init needs parameter 'yes'"
      if($value ne "yes");
    OWSWITCH_InitializeDevice($hash);
    return "OWSWITCH: Re-initialized device $name";
  }
 
  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWSWITCH: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
    return undef;
  }
    
  #-- obtain channel names
  OWSWITCH_ChannelNames($hash);
   
  #-- Set readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- set single state
  if( $key eq "output" ){
    return "OWSWITCH: Set needs parameter when writing output: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    my $fnd=undef;
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      if( ($a[2] eq $owg_channel[$i]) || ($a[2] eq $owg_fixed[$i]) ){
        $fnd=$i;
        last;
      }
    }
    return "OWSWITCH: Invalid output address, must be A,B,... or defined channel name"
      if( !defined($fnd) );

    #-- prepare gpio value
    my $nval;
    my $ntim;
    my $nstr="";
    if( lc($a[3]) eq "on" ){
      $nval = 0;
    }elsif( lc($a[3]) eq "off" ){
      $nval = 1;
    }elsif( lc($a[3]) =~ m/for-timer/ ){
      if( !($a[4] =~ m/\d\d\:\d\d\:\d\d/) ){
        if( !($a[4] =~ m/\d{1,4}/ )){
          return "OWSWITCH: Wrong data value $a[4], must be time format xx:xx:zz or integer";
        } else {
          $ntim = sprintf("%02d:%02d:%02d",int($a[4]/3600),int( ($a[4] % 3600)/60 ),$a[4] %60);
        }
      } else {
        $ntim= $a[4];
      }   
      if( lc($a[3]) eq "on-for-timer" ){
        $nval = 0;
        $nstr = "$a[0] $a[1] $a[2] off";
      }elsif( lc($a[3]) eq "off-for-timer" ){  
        $nval = 1;
        $nstr = "$a[0] $a[1] $a[2] on";
      }
    }else{
      return "OWSWITCH: Wrong data value $a[3], must be on, off, on-for-timer or off-for-timer";
    }
    
    if ($nstr ne ""){
      fhem("define ".$a[0].".".$owg_fixed[$fnd]."Timer at +".$ntim." set ".$nstr);
    }
    
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret1  = OWXSWITCH_GetState($hash);
      $value = 0;
      #-- vax or val ?
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
        $value += ($hash->{owg_vax}->[$i]<<$i) 
          if( $i != $fnd );
        $value += ($nval<<$i) 
          if( $i == $fnd );  
      }
      $ret2 = OWXSWITCH_SetState($hash,$value); 
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret1  = OWFSSWITCH_GetState($hash);
      $value = 0;
      #-- vax or val ?
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
        $value += ($hash->{owg_vax}->[$i]<<$i) 
          if( $i != $fnd );
        $value += ($nval<<$i) 
          if( $i == $fnd );  
      }
      $ret2 = OWFSSWITCH_SetState($hash,$value);
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
   #-- process results
    $ret .= $ret1
      if( defined($ret1) );
    $ret .= $ret2
      if( defined($ret2) );
    if( $ret ne "" ){
      return "OWSWITCH: Could not set device $name, reason: ".$ret;
    }
 
  #-- set state
  }elsif( $key eq "gpio" ){
    #-- check value and write to device
    return "OWSWITCH: Set with wrong value for gpio port, must be 0 <= gpio <= ".((1 << $cnumber{$attr{$name}{"model"}})-1)
      if( ! ((int($value) >= 0) && (int($value) <= ((1 << $cnumber{$attr{$name}{"model"}})-1 ))) );
     
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_SetState($hash,int($value));
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSSWITCH_SetState($hash,int($value));
    }else{
      return "OWSWITCH: GetValues with wrong IODev type $interface";
    }
    #-- process results
    if( defined($ret)  ){
      return "OWSWITCH: Could not set device $name, reason: ".$ret;
    }
  }
  
  #-- process results - we have to reread the device
  OWSWITCH_GetValues($hash);  
  Log 4, "OWSWITCH: Set $hash->{NAME} $key $value";
  return undef;
}

########################################################################################
#
# OWSWITCH_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Undef ($) {
  my ($hash) = @_;
  delete($main::modules{OWSWITCH}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWServer
#
# Prefix = OWFSSWITCH
#
########################################################################################
#
# OWFSSWITCH_GetState - Get gpio ports from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSSWITCH_GetState($) {
  my ($hash) = @_;
 
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- get values - or should we rather use the uncached ones ?
  my $rel = OWServer_Read($master,"/$owx_add/sensed.ALL");
  my $rex = OWServer_Read($master,"/$owx_add/PIO.ALL");
  
  return "no return from OWServer"
    if( !defined($rel) || !defined($rex) );
  return "empty return from OWServer"
    if( ($rel eq "") || ($rex eq "") );
        
  my @ral = split(/,/,$rel);
  my @rax = split(/,/,$rex);
  
  return "wrong data length from OWServer"
    if( (int(@ral) != $cnumber{$attr{$name}{"model"}}) || (int(@rax) != $cnumber{$attr{$name}{"model"}}) );
  
  #-- All have the same code here !
  #-- family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== get gpio values ===============================
    for(my $i=0;$i<2;$i++){
      $hash->{owg_val}->[$i] = $ral[$i];
      #-- reading a zero means it is off
      $hash->{owg_vax}->[$i] = 1 - $rax[$i];
    }
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    for(my $i=0;$i<8;$i++){
      $hash->{owg_val}->[$i] = $ral[$i];
      #-- reading a zero means it is off
      $hash->{owg_vax}->[$i] = 1 - $rax[$i];
    }
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    for(my $i=0;$i<2;$i++){
      $hash->{owg_val}->[$i] = $ral[$i];
      #-- reading a zero means it is off
      $hash->{owg_vax}->[$i] = 1 - $rax[$i];
    }
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
  
  #-- and now from raw to formatted values 
  $hash->{PRESENT}  = 1;
  my $value = OWSWITCH_FormatValues($hash);
  Log 5, $value;
  return undef;
}

########################################################################################
#
# OWFSSWITCH_SetState - Set gpio ports in device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWFSSWITCH_SetState($$) {
  my ($hash,$value) = @_;
  
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  #-- family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== set gpio values ===============================
    #-- put into local buffer
    $hash->{owg_val}->[0] = $value % 2;
    $hash->{owg_vax}->[0] = $hash->{owg_val}->[0];
    $hash->{owg_val}->[1] = int($value / 2);
    $hash->{owg_vax}->[1] = $hash->{owg_val}->[1];
   
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== set gpio values ===============================
    for(my $i=0;$i<8;$i++){
      $hash->{owg_val}->[$i] = ($value>>$i) & 1;
      $hash->{owg_vax}->[$i] = $hash->{owg_val}->[$i]
    }    
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== set gpio values ===============================
    $hash->{owg_val}->[0] = $value % 2;
    $hash->{owg_vax}->[0] = $hash->{owg_val}->[0];
    $hash->{owg_val}->[1] = int($value / 2);
    $hash->{owg_vax}->[1] = $hash->{owg_val}->[1];
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
  #-- writing a zero will switch output transistor off
  my @res;
  for(my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    $res[$i]=1-$hash->{owg_val}->[$i];
  } 
  OWServer_Write($master, "/$owx_add/PIO.ALL", join(',',@res));
  return undef
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXSWITCH
#
########################################################################################
#
# OWXSWITCH_BinValues - Binary readings into clear values
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXSWITCH_BinValues($$$$$$$$) {
  my ($hash, $context, $success, $reset, $owx_dev, $command, $numread, $res) = @_;
  
  #-- always check for success, unused are reset, numread
  return unless ($success and $context);
  #Log 1,"OWXSWITCH_BinValues context = $context";

  my @data=[]; 
  my $value;
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  #-- note: value 1 corresponds to OFF, 0 to ON normally
  #         val = input value, vax = output value
  #-- Outer if - check get or set
  if ( $context =~ /.*getstate.*/ ){
    #-- family = 12 => DS2406 -------------------------------------------------------
    if( ($context eq "getstate.ds2406") or ($context eq "ds2406.getstate") ) {
      @data=split(//,$res);
      return "invalid data length, ".int(@data)." instead of 4 bytes"
        if (@data != 4); 
      return "invalid CRC"
        if ( OWX_CRC16($command.substr($res,0,2),$data[2],$data[3]) == 0);
      $hash->{owg_val}->[0] = (ord($data[0])>>2) & 1;
      $hash->{owg_vax}->[0] =  ord($data[0])     & 1;
      $hash->{owg_val}->[1] = (ord($data[0])>>3) & 1;
      $hash->{owg_vax}->[1] = (ord($data[0])>>1) & 1;
    
    #-- family = 29 => DS2408 -------------------------------------------------------
    }elsif( ($context eq "getstate.ds2408") or ($context eq "ds2408.getstate") ) {
      @data=split(//,$res);
      return "invalid data length, ".int(@data)." instead of 10 bytes"
        if (@data != 10); 
      return "invalid data"
        if (ord($data[6])!=255); 
      return "invalid CRC"
        if( OWX_CRC16($command.substr($res,0,8),$data[8],$data[9]) == 0);  
      for(my $i=0;$i<8;$i++){
        $hash->{owg_val}->[$i] = (ord($data[0])>>$i) & 1;
        $hash->{owg_vax}->[$i] = (ord($data[1])>>$i) & 1;
      };
   
    #-- family = 3A => DS2413 -------------------------------------------------------
    }elsif( ($context eq "getstate.ds2413") or ($context eq "ds2413.getstate") ){
      @data=split(//,$res);
      return "invalid data length, ".int(@data)." instead of 2 bytes"
        if (@data != 2); 
      return "invalid data"
        if ( (15- (ord($data[0])>>4)) != (ord($data[0]) & 15) );
      $hash->{owg_val}->[0] = ord($data[0])      & 1;
      $hash->{owg_vax}->[0] = (ord($data[0])>>1) & 1;
      $hash->{owg_val}->[1] = (ord($data[0])>>2) & 1;
      $hash->{owg_vax}->[1] = (ord($data[0])>>3) & 1;
    #--
    }else{
      return "unknown device family $hash->{OW_FAMILY} in OWXSWITCH_BinValues getstate\n";
    };
  #-- Now for context setstate
  }elsif ( $context =~ /.*setstate.*/){
    #-- family = 12 => DS2406 -------------------------------------------------------
    #-- first step
    if( ($context =~ /setstate\.ds2406\.1\..*/) or ($context =~ /ds2406\.setstate\.1\..*/) ) {
      $value = substr($context,-1);
      my $stat    = ord(substr($res,0,1));
      my $statneu = ( $stat & 159 ) | (($value<<5) & 96) ; 
      #-- call the second step
      #-- issue the match ROM command \x55 and the write status command
      #   \x55 at address TA1 = \x07 TA2 = \x00
      #-- reading 9 + 4 + 2 data bytes = 15 bytes
      my $select=sprintf("\x55\x07\x00%c",$statneu);   
      #-- asynchronous mode
      if( $hash->{ASYNC} ){  
        if (OWX_Execute( $master, "setstateds2406.2.".$value, 1, $owx_dev, $select, 2, undef )) {
          OWX_Reset($master);
          return undef;
    	} else {
          return "device $owx_dev not accessible in writing"; 
        }
      #-- synchronous mode
      }else{  
        OWX_Reset($master);
        $res=OWX_Complex($master,$owx_dev,$select,2);
        if( $res eq 0 ){
          return "device $owx_dev not accessible in writing"; 
        }
        OWX_Reset($master);
        return OWXSWITCH_BinValues($hash,"ds2406.setstate.2.".$value,1,undef,$owx_dev,$select,undef,substr($res,13));
      }
    #-- family = 12 => DS2406 -------------------------------------------------------
    #-- second step from above
    }elsif( ($context =~ /setstate\.ds2406\.2\..*/) or ($context =~ /ds2406\.setstate\.2\..*/) ) {
      $value = substr($context,-1);
      @data=split(//,$res);
      if( int(@data) != 2){
        return "state could not be set for device $owx_dev";
      }
      Log 1,"invalid CRC"
        if (OWX_CRC16($command,$data[0],$data[1]) == 0);
      
      #-- put into local buffer
      $hash->{owg_val}->[0] = $value % 2;
      $hash->{owg_vax}->[0] = $value % 2;
      $hash->{owg_val}->[1] = int($value / 2);
      $hash->{owg_vax}->[1] = int($value / 2);

    #-- family = 29 => DS2408 -------------------------------------------------------
    }elsif( ($context eq "setstate.ds2408") or ($context eq "ds2408.setstate") ) {
      @data=split(//,$res);
      return "invalid data length, ".int(@data)." instead of 1 bytes"
        if (@data != 1); 
      return "state could not be set for device $owx_dev"
        if( $data[0] ne "\xAA");
    #-- family = 3A => DS2413 -------------------------------------------------------
    }elsif( ($context eq "setstate.ds2413") or ($context eq "ds2413.setstate") ){
      @data=split(//,$res);
      return "invalid data length, ".int(@data)." instead of 1 bytes"
        if (@data != 1); 
      return "state could not be set for device $owx_dev"
        if( $data[0] ne "\xAA");
   #--
    }else{
      return "unknown device family $hash->{OW_FAMILY} in OWXSWITCH_BinValues setstate\n";
    };
  }else{
    return "unknown context in OWXSWITCH_BinValues";
  }
  
  #-- and now from raw to formatted values 
  $hash->{PRESENT}  = 1;
  $value = OWSWITCH_FormatValues($hash);
  Log 5, $value;
  return undef;
}

sub OWXSWITCH_AwaitGetState($) {
	my ($hash) = @_;
	
	#-- ID of the device, hash of the busmaster
	my $owx_dev = $hash->{ROM_ID};
	my $master  = $hash->{IODev};
	my $family  = $hash->{OW_FAMILY}; 
	
	if ($master and $owx_dev) {
    #-- family = 12 => DS2406
    if( $family eq "12" ) {
    	return OWX_AwaitExecuteResponse( $master, "getstateds2406", $owx_dev );
    #-- family = 29 => DS2408
    } elsif( $family eq "29" ) {
    	return OWX_AwaitExecuteResponse( $master, "getstateds2408", $owx_dev );
    #-- family = 3A => DS2413
    } elsif( $family eq "3A" ) {
    	return OWX_AwaitExecuteResponse( $master, "getstateds2413", $owx_dev );
  	}
	}
	return undef;
}

########################################################################################
#
# OWXSWITCH_GetState - Get gpio ports from device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXSWITCH_GetState($) {
  my ($hash) = @_;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  my ($i,$j,$k);
  
  #-- family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the access channel command
    #   \xF5 plus the two byte channel control and the value
    #-- reading 9 + 3 + 2 data bytes + 2 CRC bytes = 16 bytes
    $select=sprintf("\xF5\xDD\xFF"); 
    #-- asynchronous mode
    if( $hash->{ASYNC} ){  
      if (OWX_Execute( $master, "getstateds2406", 1, $owx_dev, $select, 4, undef )) {
  		OWX_Reset($master);
  		return undef;
      } else {
        return "not accessible in reading"; 
      }
     #-- synchronous mode
    }else{
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,4);
      if( $res eq 0 ){
        return "not accessible in reading"; 
      }
      OWX_Reset($master);
      OWXSWITCH_BinValues($hash,"ds2406.getstate",1,undef,$owx_dev,substr($res,9,3),undef,substr($res,12));
    }  
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read PIO rtegisters command
    #   \xF5 plus the two byte channel target address
    #-- reading 9 + 3 + 8 data bytes + 2 CRC bytes = 22 bytes
    $select=sprintf("\xF0\x88\x00");   
    #-- asynchronous mode
    if( $hash->{ASYNC} ){
      if (OWX_Execute( $master, "getstateds2408", 1, $owx_dev, $select, 10, undef )) {
  		OWX_Reset($master);
  		return undef;
  	  } else {
        return "not accessible in reading"; 
      }
    #-- synchronous mode
    }else{
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,10);
      if( $res eq 0 ){
        return "not accessible in reading"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2408.getstate",1,undef,$owx_dev,substr($res,9,3),undef,substr($res,12));
    }  
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read gpio command
    #   \xF5 plus 2 empty bytes
    #-- reading 9 + 1 + 2 data bytes = 12 bytes
    #-- asynchronous mode
    if( $hash->{ASYNC} ){
      if (OWX_Execute( $master, "getstateds2413", 1, $owx_dev, "\xF5", 2, undef )) {
   		OWX_Reset($master);
  		return undef;
      } else {
        return "not accessible in reading"; 
      }
    #-- synchronous mode
    }else{
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,"\xF5",2);
      if( $res eq 0 ){
        return "not accessible in reading"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2413.getstate",1,undef,$owx_dev,substr($res,9,1),undef,substr($res,10));
    }
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
}

########################################################################################
#
# OWXSWITCH_SetState - Set gpio ports of device
#
# Parameter hash = hash of device addressed
#           value = integer value for device outputs
#
########################################################################################

sub OWXSWITCH_SetState($$) {

  my ($hash,$value) = @_;
  
  
  my ($select, $res, $res2, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  
  my ($i,$j,$k);

  #--  family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== set gpio values ===============================
    # Writing the output state via the access channel command does
    # not work contrary to documentation. Using the write status command 
    #-- issue the match ROM command \x55 and the read status command
    #   \xAA at address TA1 = \x07 TA2 = \x00   
    #-- reading 9 + 3 + 1 data bytes + 2 CRC bytes = 15 bytes
    #-- asynchronous mode
    if( $hash->{ASYNC} ){  
      if (OWX_Execute( $master, "setstateds2406.1.".$value, 1, $owx_dev, "\xAA\x07\x00", 3, undef )) {
  		return undef;
  	  } else {
        return "not accessible in writing"; 
      }
    #-- synchronous mode
    }else{  
      OWX_Reset($master);
      $res  = OWX_Complex($master,$owx_dev,"\xAA\x07\x00",3);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2406.setstate.1.".$value,1,undef,$owx_dev,undef,undef,substr($res,12));
    }
   
  #--  family = 29 => DS2408
  } elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and  the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",$value,255-$value);  
     #-- asynchronous mode
    if( $hash->{ASYNC} ){  
      if (OWX_Execute( $master, "setstateds2408", 1, $owx_dev, $select, 1, undef )) {
      OWX_Reset($master);
  		return undef;
  	  } else {
        return "device $owx_dev not accessible in writing"; 
      }
    #-- synchronous mode
    }else{  
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,1);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2408.setstate",1,undef,$owx_dev,undef,undef,substr($res,12));
    }
  #-- family = 3A => DS2413      
  } elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",252+$value,3-$value);   
     #-- asynchronous mode
    if( $hash->{ASYNC} ){  
      if (OWX_Execute( $master, "setstateds2413", 1, $owx_dev, $select, 1, undef )) {
        OWX_Reset($master);
  		return undef;
  	  } else {
        return "device $owx_dev not accessible in writing"; 
      }
    #-- synchronous mode
    }else{  
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,1);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2413.setstate",1,undef,$owx_dev,undef,undef,substr($res,12));
    }
  }else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
}

1;

=pod
=begin html

<a name="OWSWITCH"></a>
        <h3>OWSWITCH</h3>
        <p>FHEM module to commmunicate with 1-Wire Programmable Switches <br />
         <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
             (prerequisite: Add this module's name to the list of clients in OWServer).
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first.</p>
        <h4>Example</h4>
        <p>
            <code>define OWX_S OWSWITCH DS2413 B5D502000000 60</code>
            <br />
            <code>attr OWX_S AName Lampe|light</code>
            <br />
            <code>attr OWX_S AUnit AN|AUS</code>
        </p>
        <a name="OWSWITCHdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWSWITCH [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
            <code>define &lt;name&gt; OWSWITCH &lt;fam&gt;.&lt;id&gt; [&lt;interval&gt;]</code> 
            <br /><br /> Define a 1-Wire switch.<br /><br />
        <ul>
            <li>
                <code>[&lt;model&gt;]</code><br /> Defines the switch model (and thus 1-Wire family
                id), currently the following values are permitted: <ul>
                    <li>model DS2413 with family id 3A (default if the model parameter is omitted).
                        2 Channel switch with onboard memory</li>
                    <li>model DS2406 with family id 12. 2 Channel switch </li>
                    <li>model DS2408 with family id 29. 8 Channel switch</li>
                </ul>
            </li>
            <li>
                <code>&lt;fam&gt;</code>
                <br />2-character unique family id, see above 
            </li>
            <li>
                <code>&lt;id&gt;</code>
                <br />12-character unique ROM id of the device without family id and CRC
                code </li>
            <li>
                <code>&lt;interval&gt;</code>
                <br />Measurement interval in seconds. The default is 300 seconds. </li>
        </ul>
        <a name="OWSWITCHset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owswitch_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds. </li>
            <li><a name="owswitch_output">
                    <code>set &lt;name&gt; output &lt;channel-name&gt; on | off | on-for-timer &lt;time&gt; | off-for-timer &lt;time&gt;</code>
                    </a><br />Set
                value for channel (A,B,... or defined channel name). 1 = off, 0 = on in normal
                usage. See also the note above.<br/>
             on-for-timer/off-for-timer will set the desired value only for the given time, 
             either given as hh:mm:ss or as integers seconds
             and then will return to the opposite value.</li>
            <li><a name="owswitch_gpio">
                    <code>set &lt;name&gt; gpio &lt;value&gt;</code></a><br />Set values for
                channels (For 2 channels: 3 = A and B off, 1 = B on 2 = A on 0 = both on)</li>
            <li><a name="owswitch_init">
                    <code>set &lt;name&gt; init yes</code></a><br /> Re-initialize the device</li>
        </ul>
        <a name="OWSWITCHget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owswitch_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owswitch_present">
                    <code>get &lt;name&gt; present</code>
                </a>
                <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
            <li><a name="owswitch_interval2">
                    <code>get &lt;name&gt; interval</code></a><br />Returns measurement interval in
                seconds. </li>
            <li><a name="owswitch_input">
                    <code>get &lt;name&gt; input &lt;channel-name&gt;</code></a><br /> state for
                channel (A,B, ... or defined channel name) This value reflects the measured value,
                not necessarily the one set as output state, because the output transistors are open
                collector switches. A measured state of 1 = OFF therefore corresponds to an output
                state of 1 = OFF, but a measured state of 0 = ON can also be due to an external
                shortening of the output.</li>
            <li><a name="owswitch_gpio">
                    <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all channels</li>
        </ul>
        <a name="OWSWITCHattr"></a>
        <h4>Attributes</h4> For each of the following attributes, the channel identification A,B,...
        may be used. <ul>
            <li><a name="owswitch_cname"><code>attr &lt;name&gt; &lt;channel&gt;Name
                        &lt;string&gt;|&lt;string&gt;</code></a>
                <br />name for the channel | a type description for the measured value. </li>
            <li><a name="owswitch_cunit"><code>attr &lt;name&gt; &lt;channel&gt;Unit
                        &lt;string&gt;|&lt;string&gt;</code></a>
                <br />display for on | off condition </li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut
