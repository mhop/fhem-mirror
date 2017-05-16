########################################################################################
#
# OWSWITCH.pm
#
# FHEM module to commmunicate with 1-Wire adressable switches DS2413, DS206, DS2408
#
# Prof. Dr. Peter A. Henning
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

use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

#-- channel name - fixed is the first array, variable the second 
my @owg_fixed  = ("A","B","C","D","E","F","G","H");
my @owg_channel;
#-- channel values - always the raw input resp. output values from the device
my @owg_val;
my @owg_vax;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "input"       => "",
  "gpio"        => ""
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
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWSWITCH_Define";
  $hash->{UndefFn} = "OWSWITCH_Undef";
  $hash->{GetFn}   = "OWSWITCH_Get";
  $hash->{SetFn}   = "OWSWITCH_Set";

  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2413,DS2406,DS2408 loglevel:0,1,2,3,4,5 ".
    "stateS ".
    $readingFnAttributes;
 
  #-- correct list of attributes
  for( my $i=0;$i<8;$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Unit";
  }
 
  $hash->{AttrList} = $attlist; 
}

#########################################################################################
#
# OWSWITCH_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
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
      @owg_fixed = ("A","B");
      CommandAttr (undef,"$name model DS2413"); 
    }elsif( $fam eq "12" ){
      $model = "DS2406";
      @owg_fixed = ("A","B");
      CommandAttr (undef,"$name model DS2406"); 
    }elsif( $fam eq "29" ){
      $model = "DS2408";
      @owg_fixed = ("A","B","C","D","E","F","G","H");
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
      @owg_fixed = ("A","B");
      CommandAttr (undef,"$name model DS2413"); 
    }elsif( $model eq "DS2406" ){
      $fam = "12";
      @owg_fixed = ("A","B");
      CommandAttr (undef,"$name model DS2406"); 
    }elsif( $model eq "DS2408" ){
      $fam = "29";
      @owg_fixed = ("A","B","C","D","E","F","G","H");
      CommandAttr (undef,"$name model DS2408"); 
    }else{
      return "OWSWITCH: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWSWITCH: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }

  #--   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}->{NAME}) || !defined($hash->{IODev}) ){
    return "OWSWITCH: Warning, no 1-Wire I/O device found for $name.";
  }
  #if( $hash->{IODev}->{PRESENT} != 1 ){
  #  return "OWSWITCH: Warning, 1-Wire I/O device ".$hash->{IODev}->{NAME}." not present for $name.";
  #}
  $modules{OWSWITCH}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWSWITCH: Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+10, "OWSWITCH_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+10+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);

  return undef; 
}

########################################################################################
#
# OWSWITCH_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
    
  #-- Set channel names, channel units 
  for( my $i=0;$i<$cnumber{$attr{$name}{"model"}} ;$i++) { 
    #-- Initial readings ERR
    $owg_val[$i]   = 1;
    $owg_vax[$i]   = 0;
    #-- name
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|onoff";
    my @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      Log 1, "OWSWITCH: Incomplete channel name specification $cname. Better use $cname|<type of data>";
      push(@cnama,"unknown");
    }
 
    #-- unit
    my $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "ON|OFF";
    my @unarr= split(/\|/,$unit);
    if( int(@unarr)!=2 ){
      Log 1, "OWSWITCH: Wrong channel unit specification $unit, replaced by ON|OFF";
      $unit="ON|OFF";
    }

    #-- put into readings
    $owg_channel[$i] = $cnama[0];  
    $hash->{READINGS}{"$owg_channel[$i]"}{TYPE}     = $cnama[1];  
    $hash->{READINGS}{"$owg_channel[$i]"}{UNIT}     = $unit;
    $hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR} = $unit;
  }
  
  #-- set status according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- OWX interface
  if( !defined($interface) ){
    return "OWSWITCH: Interface missing";
  } elsif( $interface eq "OWX" ){
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  }else{
    return "OWSWITCH: InitializeDevice with wrong IODev type $interface";
  }

  #-- Initialize all the display stuff  
  OWSWITCH_FormatValues($hash);
}

########################################################################################
#
# OWSWITCH_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWSWITCH_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$vval,$vvax,$vstr,$cname,$unit,@unarr,@cnama,$valid);
  my $svalue  = ""; 
  
  #-- external shortening signature
  my $sname = defined($attr{$name}{"stateS"})  ? $attr{$name}{"stateS"} : "&#x2607;";  
  
  #-- put into READINGS
  readingsBeginUpdate($hash);

  #-- formats for output
  for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i];  
    @cnama = split(/\|/,$cname);
    $owg_channel[$i]=$cnama[0];
    
    #-- input state is 0 = ON or 1 = OFF
    $vval    = $owg_val[$i];
    #-- output state is 0 = ON or 1 = OFF
    $vvax    = $owg_vax[$i];
 
    #-- string buildup for return value and STATE
    $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "ON|OFF";
    @unarr= split(/\|/,$unit);
    $vstr    = $unarr[$vval];
    
    #-- put into readings only when valid
    if( ($vval == 1) && ($vvax == 0) ){
      $vstr ="???"
    }else{
      $vstr.= $sname if( ($vval == 0) && ($vvax == 1) );
      readingsBulkUpdate($hash,"$owg_channel[$i]",$vstr);
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
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWSWITCH_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my ($value,$value2,$value3)   = (undef,undef,undef);
  my $ret     = "";
  my $offset;
  my $factor;
  my $page;

  #-- check syntax
  return "OWSWITCH: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  return "OWSWITCH: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
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
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- get values according to interface type
  my $interface= $hash->{IODev}->{TYPE};

  #-- get single state
  # TODO: WAS passiert, wenn channel name noch falsch ist ?
  if( $reading eq "input" ){
    return "OWSWITCH: get needs parameter when reading input: <channel>"
      if( int(@a)<2 );
    my $fnd=undef;
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      if( ($a[2] eq $owg_channel[$i]) || ($a[2] eq $owg_fixed[$i]) ){
        $fnd=$i;
        last;
      }
    }
    return "OWSWITCH: invalid input address, must be A,B,... or defined channel name"
      if( !defined($fnd) );

    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSSWITCH_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process results
    OWSWITCH_FormatValues($hash);  
    my @states = split(/,/,$hash->{STATE});
    
    return $a[2]." = ".$states[$fnd]; 
    
  #-- get all states
  }elsif( $reading eq "gpio" ){
    return "OWSWITCH: get needs no parameter when reading gpio"
      if( int(@a)==1 );

    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetState($hash);
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSSWITCH_GetState($hash);
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
  }
  #-- process results
  if( defined($ret)  ){
    return "OWSWITCH: Could not get values from device $name, reason $ret";
  }
  $hash->{PRESENT} = 1; 
  return "OWSWITCH: $name.$reading => ".OWSWITCH_FormatValues($hash);  
 
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
  my $offset;
  my $factor;

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 1);
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- Get readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    #-- max 3 tries
    for(my $try=0; $try<3; $try++){
      $ret = OWXSWITCH_GetState($hash);
      last
        if( !defined($ret) );
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
      $owg_val[$i] = 1;
      $owg_vax[$i] = 0;
    }
    Log 3, "OWSWITCH: Could not get values from device $name, reason $ret";
    return 1;
  }
  $hash->{PRESENT} = 1; 
  
  $value = OWSWITCH_FormatValues($hash);
  Log 5, $value;
  
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
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", sort keys %sets);
    return $newkeys ;    
  }
  
  #-- check argument
  if( !defined($sets{$a[1]}) ){
        return "OWSWITCH: Set with unknown argument $a[1]";
  }
  
  #-- define vars
  my $ret     = undef;
  my $channel = undef;
  my $channo  = undef;
  my $condx;
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  
  #-- reset the device
  if($key eq "init") {
    return "OWCOUNT: init needs parameter 'yes'"
      if($value ne "yes");
    OWSWITCH_InitializeDevice($hash);
    return "OWCOUNT: Re-initialized device";
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
   
  #-- Set readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- set single state
  # TODO: WAS passiert, wenn channel name noch falsch ist ?
  if( $key eq "output" ){
    return "OWSWITCH: get needs parameter when writing output: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    my $fnd=undef;
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      if( ($a[2] eq $owg_channel[$i]) || ($a[2] eq $owg_fixed[$i]) ){
        $fnd=$i;
        last;
      }
    }
    return "OWSWITCH: invalid output address, must be A,B,... or defined channel name"
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
      $ret   = OWXSWITCH_GetState($hash);
      $value = 0;
      #-- vax or val ?
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
        $value += ($owg_vax[$i]<<$i) 
          if( $i != $fnd );
        $value += ($nval<<$i) 
          if( $i == $fnd );  
      }
      $ret = OWXSWITCH_SetState($hash,$value);
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret   = OWFSSWITCH_GetState($hash);
      $value = 0;
      #-- vax or val ?
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
        $value += ($owg_vax[$i]<<$i) 
          if( $i != $fnd );
        $value += ($nval<<$i) 
          if( $i == $fnd );  
      }
      $ret = OWFSSWITCH_SetState($hash,$value);
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
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
  }
  
  #-- process results - we have to reread the device
  $hash->{PRESENT} = 1; 
  OWSWITCH_GetValues($hash);  
  #OWSWITCH_FormatValues($hash);  
  Log 4, "OWSWITCH: Set $hash->{NAME} $key $value";
  #$hash->{CHANGED}[0] = $value;
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
  delete($modules{OWSWITCH}{defptr}{$hash->{OW_ID}});
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
      $owg_val[$i] = $ral[$i];
      #-- reading a zero means it is off
      $owg_vax[$i] = 1 - $rax[$i];
    }
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    for(my $i=0;$i<8;$i++){
      $owg_val[$i] = $ral[$i];
      #-- reading a zero means it is off
      $owg_vax[$i] = 1 - $rax[$i];
    }
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    for(my $i=0;$i<2;$i++){
      $owg_val[$i] = $ral[$i];
      #-- reading a zero means it is off
      $owg_vax[$i] = 1 - $rax[$i];
    }
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
  return undef
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
    $owg_val[0] = $value % 2;
    $owg_vax[0] = $owg_val[0];
    $owg_val[1] = int($value / 2);
    $owg_vax[1] = $owg_val[1];
   
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== set gpio values ===============================
    for(my $i=0;$i<8;$i++){
      $owg_val[$i] = ($value>>$i) & 1;
      $owg_vax[$i] = $owg_val[$i]
    }    
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== set gpio values ===============================
    $owg_val[0] = $value % 2;
    $owg_vax[0] = $owg_val[0];
    $owg_val[1] = int($value / 2);
    $owg_vax[1] = $owg_val[1];
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
  #-- writing a zero will switch output transistor off
  my @res;
  for(my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    $res[$i]=1-$owg_val[$i];
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
  
  my ($i,$j,$k);
  
  #-- family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the access channel command
    #   \xF5 plus the two byte channel control and the value
    #-- reading 9 + 3 + 1 data bytes + 2 CRC bytes = 15 bytes
    $select=sprintf("\xF5\xDD\xFF");   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,4);
    if( $res eq 0 ){
      return "not accessible in reading"; 
    }
    
    #-- reset the bus
    OWX_Reset($master);
    
    #-- process results
    @data=split(//,substr($res,9));
    return "invalid data length, ".int(@data)." instead of 7 bytes"
      if (@data != 7); 
    return "invalid CRC"
      if ( OWX_CRC16(substr($res,9,5),$data[5],$data[6]) == 0);
       
    $owg_val[0] = (ord($data[3])>>2) & 1;
    $owg_vax[0] =  ord($data[3])     & 1;
    $owg_val[1] = (ord($data[3])>>3) & 1;
    $owg_vax[1] = (ord($data[3])>>1) & 1;

  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read PIO rtegisters command
    #   \xF5 plus the two byte channel target address
    #-- reading 9 + 3 + 8 data bytes + 2 CRC bytes = 22 bytes
    $select=sprintf("\xF0\x88\x00");   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,10);
    if( $res eq 0 ){
      return "not accessible in reading"; 
    }
    
    #-- reset the bus
    OWX_Reset($master);
  
    #-- process results
    @data=split(//,substr($res,9));
    return "invalid data length, ".int(@data)." instead of 13 bytes"
      if (@data != 13); 
    return "invalid data"
      if (ord($data[9])!=255); 
    return "invalid CRC"
      if( OWX_CRC16(substr($res,9,11),$data[11],$data[12]) == 0);  
    for(my $i=0;$i<8;$i++){
      $owg_val[$i] = (ord($data[3])>>$i) & 1;
      $owg_vax[$i] = (ord($data[4])>>$i) & 1;
    }
    
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read gpio command
    #   \xF5 plus 2 empty bytes
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,"\xF5",2);
    if( $res eq 0 ){
      return "not accessible in reading"; 
    }
    
    #-- reset the bus
    OWX_Reset($master);
    
    #-- process results
    @data=split(//,substr($res,9));
    return "invalid data length, ".int(@data)." instead of 3 bytes"
      if (@data != 3); 
    return "invalid data"
      if ( (15- (ord($data[1])>>4)) != (ord($data[1]) & 15) );
    
    #   note: value 1 corresponds to OFF, 0 to ON normally
    #   note: val = input value, vax = output value
    $owg_val[0] = ord($data[1])      & 1;
    $owg_vax[0] = (ord($data[1])>>1) & 1;
    $owg_val[1] = (ord($data[1])>>2) & 1;
    $owg_vax[1] = (ord($data[1])>>3) & 1;
  
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
  return undef
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
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res        = OWX_Complex($master,$owx_dev,"\xAA\x07\x00",3);
    my $stat    = ord(substr($res,10,1));
    my $statneu = ( $stat & 159 ) | (($value<<5) & 96) ; 
    #-- issue the match ROM command \x55 and the write status command
    #   \x55 at address TA1 = \x07 TA2 = \x00
    #
    $select=sprintf("\x55\x07\x00%c",$statneu);   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,2);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in writing"; 
    }
    #-- reset the bus
    OWX_Reset($master);
    
    #-- process results
    @data=split(//,substr($res,9));
    
    #-- very crude check - should be CRC
    if( int(@data) != 6){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    } 
    
    #-- put into local buffer
    $owg_val[0] = $value % 2;
    $owg_vax[0] = $owg_val[0];
    $owg_val[1] = int($value / 2);
    $owg_vax[1] = $owg_val[1];
    
  #--  family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and  the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",$value,255-$value);  
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,1);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in writing"; 
    }
    
    #-- process results
    @data=split(//,substr($res,10));
    
    if( $data[2] ne "\xAA"){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    }
    #-- reset the bus
    OWX_Reset($master);
    
  #-- family = 3A => DS2413      
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",252+$value,3-$value);   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,1);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in writing"; 
    }
    #-- reset the bus
    OWX_Reset($master);
    
    #-- process results
    @data=split(//,substr($res,10));
  
    if( $data[2] ne "\xAA"){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    }  
  
  }else {
    return "OWXSWITCH: Unknown device family $hash->{OW_FAMILY}\n";
  }

  return undef;

}

1;

=pod
=begin html

<a name="OWSWITCH"></a>
        <h3>OWSWITCH</h3>
        <p>FHEM module to commmunicate with 1-Wire Programmable Switches <br />
         <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
             (prerequisite: Add this module's name to the list of clients in OWServer).
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first. <br /></p>
        <br /><h4>Example</h4>
        <p>
            <code>define OWX_S OWSWITCH DS2413 B5D502000000 60</code>
            <br />
            <code>attr OWX_S AName Lampe|light</code>
            <br />
            <code>attr OWX_S AUnit AN|AUS</code>
            <br />
        </p>
        <br />
        <a name="OWSWITCHdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWSWITCH [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
            <code>define &lt;name&gt; OWSWITCH &lt;fam&gt;.&lt;id&gt; [&lt;interval&gt;]</code> 
            <br /><br /> Define a 1-Wire switch.<br /><br /></p>
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
        <br />
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
        <br />
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
