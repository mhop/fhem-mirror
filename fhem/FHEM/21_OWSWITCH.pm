########################################################################################
#
# OWSWITCH.pm
#
# FHEM module to commmunicate with 1-Wire adressable switches DS2413, DS206, DS2408
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
# TODO: Kanalattribute ändern zur Laufzeit.
#
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
# OWX  = 1-Wire bus master interface (Peter Henning)
# OWFS = 1-Wire file system (??)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.25 - October, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWSWITCH [<model>] <ROM_ID> [interval] 
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2413. Allowed values are DS2413, DS2406 
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
# set <name> output <channel-name>  ON|OFF => set value for channel (name A, B or defined channel name)
#            note: 1 = OFF, 0 = ON in normal usage. See also the note above
# set <name> gpio  value => set values for channels (3 = both OFF, 1 = B ON 2 = A ON 0 = both ON)
# set <name> init yes => re-initialize device
#
# Additional attributes are defined in fhem.cfg, in some cases per channel, where <channel>=A,B
# Note: attributes are read only during initialization procedure - later changes are not used.
#
# attr <name> event on-change/on-update = when to write an event (default= on-update)
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

#-- Prototypes to make komodo happy
use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

#-- channel name - fixed is the first array, variable the second 
my @owg_fixed = ("A","B","C","D","E","F","G","H");
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
    "event:on-update,on-change stateS ";
 
 #TODO: correct number of channels
 
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
  return "OWSWITCH: Wrong syntax, must be define <name> OWSWITCH [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2413";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
  } else {    
    return "OWSWITCH: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
    #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   FF = family id follows from the model
  #   YY must be determined from id
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
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWSWITCH: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWSWITCH}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWSWITCH:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+1, "OWSWITCH_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);

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
   
  #-- more colorful shortening signature
  CommandAttr (undef,"$name stateS <span style=\"color:red\">&#x2607;</span>")
   if( !defined($attr{$name}{"stateS"} ));
   
  #-- Set channel names, channel units 
  for( my $i=0;$i<$cnumber{$attr{$name}{"model"}} ;$i++) { 
    #-- Initial readings OFF
    $owg_val[$i]   = 1;
    $owg_vax[$i]   = 1;
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
  my ($offset,$factor,$vval,$vvax,$vstr,$cname,@cnama,@unarr);
  my ($value1,$value2,$value3)   = ("","","");
  
  my $tn = TimeNow();
  
  #-- external shortening signature
  my $sname = defined($attr{$name}{"stateS"})  ? $attr{$name}{"stateS"} : "(ext)";  

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
    @unarr= split(/\|/,$hash->{READINGS}{"$owg_channel[$i]"}{UNIT});
   
    $vstr    = $unarr[$vval];
    $vstr   .= $sname if( ($vval == 0) && ($vvax == 1) );
    $vstr    = "ERR"  if( ($vval == 1) && ($vvax == 0) );
    
    $value1 .= sprintf( "%s: %s", $owg_channel[$i], $vstr);
    $value2 .= sprintf( "%s: %s ", $owg_channel[$i], $vstr);
    $value3 .= sprintf( "%s: " , $owg_channel[$i]);
    
    #-- put into READINGS
    $hash->{READINGS}{"$owg_channel[$i]"}{VAL}   = $vstr;
    $hash->{READINGS}{"$owg_channel[$i]"}{TIME}  = $tn;
    
    #-- insert comma
    if( $i<$cnumber{$attr{$name}{"model"}}-1 ){
      $value1 .= " ";
      $value2 .= ", ";
      $value3 .= ", ";
    }
  }
  #-- STATE
  $hash->{STATE} = $value2;
 
  return $value1;
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
    return "OWSWITCH: invalid output address, must be A,B,... or defined channel name"
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
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetValues($hash);
    }else{
      return "OWSWITCH: GetValues with wrong IODev type $interface";
    }
  }
  #-- process results
  if( defined($ret)  ){
    return "OWSWITCH: Could not get values from device $name";
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
    $ret = OWXSWITCH_GetState($hash);
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSSWITCH_GetValues($hash);
  }else{
    return "OWSWITCH: GetValues with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWSWITCH: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  #-- old state, new state
  my $oldval = $hash->{STATE};
  $value=OWSWITCH_FormatValues($hash);
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
    if( lc($a[3]) eq "on" ){
      $nval = 0;
    }elsif( lc($a[3]) eq "off" ){
      $nval = 1;
    }else{
      return "OWSWITCH: Wrong data value $a[3], must be ON or OFF";
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
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
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
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSSWITCH_GetValues($hash);
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
# via OWFS
#
# Prefix = OWFSSWITCH
#
########################################################################################



########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXSWITCH
#
########################################################################################
#
# OWXAD_GetState - Get gpio ports from device
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
  
  #-- family = 3A => DS2413
  if( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read gpio command
    #   \xF5 plus 2 empty bytes
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,"\xF5",2);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in reading"; 
    }
  #-- family = 12 => DS2406
  }elsif( $hash->{OW_FAMILY} eq "12" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the access channel command
    #   \xF5 plus the two byte channel control and the value
    $select=sprintf("\xF5\xDC\xFF");   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,1);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in writing"; 
    }
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read PIO rtegisters command
    #   \xF5 plus the two byte channel target address
    #-- reading 9 + 3 + 10 data bytes = 22 bytes
    $select=sprintf("\xF0\x88\x00");   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res=OWX_Complex($master,$owx_dev,$select,10);
    if( $res eq 0 ){
      return "OWXSWITCH: Device $owx_dev not accessible in writing"; 
    }
  } else {
    return "OWXSWITCH: Unknown device family $hash->{OW_FAMILY}\n";
  }
  
  #-- process results
  @data=split(//,substr($res,10));
  #return "invalid data length"
  #  if (@data != 22); 
  #return "invalid data"
  #  if (ord($data[17])<=0); 
  #return "invalid CRC"
  #  if (OWX_CRC8(substr($res,10,8),$data[18])==0);  
  
  #-- reset the bus
  OWX_Reset($master);

  #   note: value 1 corresponds to OFF, 0 to ON normally
  #   note: val = input value, vax = output value
  #-- family = 3A => DS2413
  if( $hash->{OW_FAMILY} eq "3A" ) {
    $owg_val[0] = ord($data[0])      & 1;
    $owg_vax[0] = (ord($data[0])>>1) & 1;
    $owg_val[1] = (ord($data[0])>>2) & 1;
    $owg_vax[1] = (ord($data[0])>>3) & 1;
    
  #-- family = 12 => DS2406
  }elsif( $hash->{OW_FAMILY} eq "12" ) {
    $owg_val[0] = (ord($data[2])>>2) & 1;
    $owg_vax[0] =  ord($data[2])     & 1;
    $owg_val[1] = (ord($data[2])>>3) & 1;
    $owg_vax[1] = (ord($data[2])>>1) & 1;
   #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    for(my $i=0;$i<8;$i++){
      $owg_val[$i] = (ord($data[2])>>$i) & 1;
      $owg_vax[$i] = (ord($data[3])>>$i) & 1;
    }
  }
  return undef
}

########################################################################################
#
# OWXSWITCH_SetPage - Set gpio ports of device
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
  
  #-- family = 3A => DS2413
  if( $hash->{OW_FAMILY} eq "3A" ) {
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
  #--  family = 12 => DS2406
  }elsif( $hash->{OW_FAMILY} eq "12" ) {
    #=============== set gpio values ===============================
    # Writing the output state via the access channel command does
    # not work contrary to documentation. Using the write status command 
    #-- issue the match ROM command \x55 and the read status command
    #   \xAA at address TA1 = \x07 TA2 = \x00   
    #-- reset the bus
    OWX_Reset($master);
    #-- read the data
    $res        = OWX_Complex($master,$owx_dev,"\xAA\x07\x00",1);
    my $stat    = substr($res,10,1);
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
        
  } else {
    return "OWXSWITCH: Unknown device family $hash->{OW_FAMILY}\n";
  }
  #-- reset the bus
  OWX_Reset($master);

  #-- process results
  @data=split(//,substr($res,10));

  #-- family = 3A => DS2413
  if( $hash->{OW_FAMILY} eq "3A" ) {
    if( $data[2] ne "\xAA"){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    } 
  #--  family = 12 => DS2406
  }elsif( $hash->{OW_FAMILY} eq "12" ) {
    #-- very crude check - should be CRC
    if( int(@data) != 5){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    } 
  #--  family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    if( $data[2] ne "\xAA"){
      return "OWXSWITCH: State could not be set for device $owx_dev";
    }
  } 
  return undef

}

1;

=pod
=begin html

<a name="OWSWITCH"></a>
<h3>OWSWITCH</h3>
<ul>FHEM module to commmunicate with 1-Wire Programmable Switches <br /><br /> Note:<br />
    This 1-Wire module so far works only with the OWX interface module. Please define an <a
        href="#OWX">OWX</a> device first. <br />
    <br /><b>Example</b><br />
    <ul>
        <code>define OWX_S OWSWITCH DS2413 B5D502000000 60</code>
        <br />
        <code>attr OWX_S AName Lampe|light</code>
        <br />
        <code>attr OWX_S AUnit AN|AUS</code>
        <br />
    </ul>
    <br />
    <a name="OWSWITCHdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; OWSWITCH [&lt;model&gt;] &lt;id&gt;
            [&lt;interval&gt;]</code>
        <br /><br /> Define a 1-Wire switch.<br /><br />
        <li>
            <code>[&lt;model&gt;]</code><br /> Defines the switch model (and thus 1-Wire
            family id), currently the following values are permitted: <ul>
                <li>model DS2413 with family id 3A (default if the model parameter is
                    omitted). 2 Channel switch with onboard memory</li>
                <li>model DS2406 with family id 12. 2 Channel switch </li>
                <li>model DS2406 with family id 29. 8 Channel switch</li>
            </ul>
        </li>
        <li>
            <code>&lt;id&gt;</code>
            <br />12-character unique ROM id of the converter device without family id and
            CRC code </li>
        <li>
            <code>&lt;interval&gt;</code>
            <br />Measurement interval in seconds. The default is 300 seconds. </li>
    </ul>
    <br />
    <a name="OWSWITCHset">
        <b>Set</b></a>
    <ul>
        <li><a name="owswitch_interval">
                <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
            interval in seconds. The default is 300 seconds. </li>
        <li><a name="owswitch_output">
                <code>set &lt;name&gt; output &lt;channel-name&gt; ON |
                    OFF</code></a><br />Set value for channel (A,B,... or defined channel name). 1 = OFF, 0 = ON in normal usage. 
                     See also the note above</li>
        <li><a name="owswitch_gpio">
            <code>set &lt;name&gt; gpio &lt;value&gt;</code></a><br />Set values for channels (For 2 channels: 3 = A and B OFF, 1 = B ON 2 = A ON 0 = both ON)</li>
        <li><a name="owswitch_init">
            <code>set &lt;name&gt; init yes</code></a><br /> Re-initialize the device</li>
    </ul>
    <br />
    <a name="OWSWITCHget">
        <b>Get</b></a>
    <ul>
        <li><a name="owswitch_id">
                <code>get &lt;name&gt; id</code></a>
            <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
        <li><a name="owswitch_present">
                <code>get &lt;name&gt; present</code>
            </a>
            <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
        <li><a name="owswitch_interval2">
                <code>get &lt;name&gt; interval</code></a><br />Returns measurement interval
            in seconds. </li>
        <li><a name="owswitch_input">
                <code>get &lt;name&gt; input &lt;channel-name&gt;</code></a><br />
                state for channel (A,B, ... or defined channel name)
                This value reflects the measured value, not necessarily the one set as
                output state, because the output transistors are open collector switches. A measured
                state of 1 = OFF therefore corresponds to an output state of 1 = OFF, but a measured
                state of 0 = ON can also be due to an external shortening of the output.</li>
        <li><a name="owswitch_gpio">
                <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all
            channels</li>
    </ul>
    <br />
    <a name="OWSWITCHattr">
        <b>Attributes</b></a> For each of the following attributes, the channel
    identification A,B,... may be used. <ul>
        <li><a name="owswitch_cname"><code>attr &lt;name&gt; &lt;channel&gt;Name
                    &lt;string&gt;|&lt;string&gt;</code></a>
            <br />name for the channel | a type description for the measured value. </li>
        <li><a name="owswitch_cunit"><code>attr &lt;name&gt; &lt;channel&gt;Unit
                    &lt;string&gt;|&lt;string&gt;</code></a>
            <br />display for on | off condition </li>
        <li><a name="owswitch_event"><code>attr &lt;name&gt; event on-change|on-update
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
