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

sub Log($$);

my $owx_version="7.01";
#-- fixed raw channel name, flexible channel name
my @owg_fixed   = ("A","B","C","D","E","F","G","H");
my @owg_channel = ("A","B","C","D","E","F","G","H");

my %gets = (
  "id"          => ":noArg",
  "input"       => "",
  "gpio"        => ":noArg",
  "version"     => ":noArg"
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
# Parameter: hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWSWITCH_Define";
  $hash->{UndefFn} = "OWSWITCH_Undef";
  $hash->{GetFn}   = "OWSWITCH_Get";
  $hash->{SetFn}   = "OWSWITCH_Set";
  $hash->{NotifyFn}= "OWSWITCH_Notify";
  $hash->{InitFn}  = "OWSWITCH_Init";
  $hash->{AttrFn}  = "OWSWITCH_Attr";
  
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2413,DS2406,DS2408 ".
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
  
  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}

#########################################################################################
#
# OWSWITCH_Define - Implements DefFn function
#
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
    }elsif( $fam eq "85" ){
      $fam ="3A";
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
  $hash->{ERRCOUNT}   = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}) or !defined($hash->{IODev}->{NAME}) ){
    return "OWSWITCH: Warning, no 1-Wire I/O device found for $name.";
  } else {
    $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0; #-- false for now
  }

  $main::modules{OWSWITCH}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWSWITCH: Device $name defined."; 

  $hash->{NOTIFYDEV} = "global";

  if ($init_done) {
    OWSWITCH_Init($hash);
  }
  return undef;
}

########################################################################################
#
# OWSWITCH_Notify - Implements Notify function
#
# Parameter: hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWSWITCH_Notify ($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    OWSWITCH_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

########################################################################################
#
# OWSWITCH_Init - Implements Init function
#
# Parameter: hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWSWITCH_Init ($) {
  my ($hash)=@_;
  #-- Start timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+10, "OWSWITCH_GetValues", $hash, 0);
  return undef; 
}

#######################################################################################
#
# OWSWITCH_Attr - Set one attribute value for device
#
# Parameter: hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWSWITCH_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      #-- interval modified at runtime
     $key eq "interval" and do {
        #-- check value
        return "OWSWITCH: set $name  interval must be >= 0" if(int($value) < 0);
        #-- update timer
        $hash->{INTERVAL} = int($value);
        if ($init_done) {
          RemoveInternalTimer($hash);
          InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);
        }
        last;
      };
      $key eq "IODev" and do {
        AssignIoPort($hash,$value);
        if( defined($hash->{IODev}) ) {
          $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0;
          if ($init_done) {
            OWSWITCH_Init($hash);
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
# OWSWITCH_ChannelNames - find the real channel names  
#
# Parameter: hash = hash of device addressed
#
########################################################################################

sub OWSWITCH_ChannelNames($) { 
  my ($hash) = @_;
 
  my $name    = $hash->{NAME}; 
  my $state   = $hash->{READINGS}{"state"}{VAL};
 
  my ($cname,@cnama,$unit,@unarr);
  
  $gets{"input"}=":";

  for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    #-- name
    $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : "$owg_fixed[$i]";
    @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      push(@cnama,$cnama[0]);
    }
    #-- put into readings and array for display
    $owg_channel[$i] = $cnama[0]; 
    $hash->{READINGS}{$owg_channel[$i]}{ABBR}     = $cnama[1]; 
    $gets{"input"} .=  $cnama[0];
    $gets{"input"} .=  "," 
      if ($i<$cnumber{$attr{$name}{"model"}}-1);
 
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
  }
  $sets{"output"}=$gets{"input"};
  
}

########################################################################################
#
# OWSWITCH_FormatValues - put together various format strings 
#
# Parameter; hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWSWITCH_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$vval,$vvax,$vstr,@unarr,$valid);
  my $svalue  = ""; 
  
  #-- external shortening signature
  my $sname = defined($attr{$name}{"stateS"})  ? $attr{$name}{"stateS"} : "X";  
  $sname = ""
      if($sname eq "none");
  
  #-- obtain channel names
  OWSWITCH_ChannelNames($hash);
  
  #-- put into READINGS
  my $gpio  = 0;
  readingsBeginUpdate($hash);

  #-- formats for output
  for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
    
    #-- input state is 0 = ON or 1 = OFF
    $vval    = $hash->{owg_val}->[$i];
    $gpio   += $hash->{owg_val}->[$i]<<$i;
     
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
    $svalue .= sprintf( "%s: %s" , $hash->{READINGS}{$owg_channel[$i]}{ABBR}, $vstr);

    #-- insert space 
    if( $i<($cnumber{$attr{$name}{"model"}}-1) ){
      $svalue .= " ";
    }
  }
  
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsBulkUpdate($hash,"gpio",$gpio);
  readingsEndUpdate($hash,1); 
 
  return $svalue;
}

########################################################################################
#
# OWSWITCH_Get - Implements GetFn function 
#
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
  my $msg = "OWSWITCH: Get with unknown argument $a[1], choose one of ";
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
      OWXSWITCH_GetModState($hash,"final",undef);
    }elsif( $interface eq "OWX_ASYNC") {
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXSWITCH_PT_GetState($hash));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSSWITCH_GetState($hash);
    #-- Unknown interface
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process result
    if( ($master->{ASYNCHRONOUS}) && ($interface ne "OWServer") ){
      #return "OWSWITCH: $name getting input, please wait for completion";
      return undef;
    }else{
      return $name.".".$a[2]." => ".$hash->{READINGS}{$owg_channel[$fnd]}{VAL};
    } 
    
  #-- get all states
  }elsif( $reading eq "gpio" ){
    return "OWSWITCH: Get needs no parameter when reading gpio"
      if( int(@a)==1 );

    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_GetModState($hash,undef,undef);
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXSWITCH_PT_GetState($hash));
      };
      $ret = GP_Catch($@) if $@;
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSSWITCH_GetState($hash);
    }else{
      return "OWSWITCH: Get with wrong IODev type $interface";
    }
    #-- process results
    if( $master->{ASYNCHRONOUS} ){
      #return "OWSWITCH: $name getting gpio, please wait for completion";
      return undef;
    }else{
      if( defined($ret)  ){
        return "OWSWITCH: Could not get values from device $name, reason $ret";
      }
      return "OWSWITCH: $name.$reading => ".$hash->{READINGS}{"state"}{VAL};  
    }
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

  RemoveInternalTimer($hash); 
  #-- auto-update for device disabled;
  return undef
    if( $hash->{INTERVAL} == 0 );
  #-- restart timer for updates  
  InternalTimer(time()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);
  
  #-- Get readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXSWITCH_GetModState($hash,"final",undef);
    return if( !defined($ret) );
  }elsif( $interface eq "OWX_ASYNC" ){
    eval {
      OWX_ASYNC_Schedule( $hash, OWXSWITCH_PT_GetState($hash) );
    };
    return unless $@;
    $ret = GP_Catch($@);
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
#
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
  my ($ret1,$ret2,$ret3);
  
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
    return "OWSWITCH: set $name interval must be >= 0"
      if(int($value) < 0);
    # update timer
    $hash->{INTERVAL} = int($value);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWSWITCH_GetValues", $hash, 0);
    return undef;
  }
    
  #-- obtain channel names
  OWSWITCH_ChannelNames($hash);
   
  #-- Set readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- set single output state: get-set-get needed because external shorting can be discovered only after set
  if( $key eq "output" ){
    return "OWSWITCH: Set needs parameter when writing output: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    my $outfnd=undef;
    for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
      if( ($a[2] eq $owg_channel[$i]) || ($a[2] eq $owg_fixed[$i]) ){
        $outfnd=$i;
        last;
      }
    }
    return "OWSWITCH: Invalid output address, must be A,B,... or defined channel name"
      if( !defined($outfnd) );

    #-- prepare gpio value
    my $outval;
    my $ntim;
    my $nstr="";
    if( lc($a[3]) eq "on" ){
      $outval = 0;
    }elsif( lc($a[3]) eq "off" ){
      $outval = 1;
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
        $outval = 0;
        $nstr = "$a[0] $a[1] $a[2] off";
      }elsif( lc($a[3]) eq "off-for-timer" ){  
        $outval = 1;
        $nstr = "$a[0] $a[1] $a[2] on";
      }
    }else{
      return "OWSWITCH: Set has wrong data value $a[3], must be on, off, on-for-timer or off-for-timer";
    }
    #-- timer for timed on/off
    if ($nstr ne ""){
      fhem("define ".$a[0].".".$owg_fixed[$outfnd]."Timer at +".$ntim." set ".$nstr);
    }
    
    #-- combined get-set-get operation
    #-- OWX interface
    if( $interface eq "OWX" ){
      #-- all-in one needed, because return not sure
      $ret1  = OWXSWITCH_GetModState($hash,$outfnd,$outval);
    }elsif( $interface eq "OWX_ASYNC"){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXSWITCH_PT_SetOutput($hash,$outfnd,$outval) );
      };
      $ret2 = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret1  = OWFSSWITCH_GetState($hash);
      my $gpio  = 0;
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
         $gpio += ($hash->{owg_vax}->[$i]<<$i) 
      };
      if( $outval==0 ){
        $gpio &= ~(1<<$outfnd); 
      }else{
        $gpio |= (1<<$outfnd); 
      } 
      $ret2 = OWFSSWITCH_SetState($hash,$gpio);
      $ret3 = OWFSSWITCH_GetState($hash);
    #-- Unknown interface
    }else{
      return "OWSWITCH: Set with wrong IODev type $interface";
    }
   #-- process results
    $ret .= $ret1
      if( defined($ret1) );
    $ret .= $ret2
      if( defined($ret2) );
    if( $ret ne "" ){
      return "OWSWITCH: Could not set device $name, reason: ".$ret;
    }
 
  #-- set complete gpio output state: set-get needed because external shorting can be discovered only after set
  }elsif( $key eq "gpio" ){
    #-- check value and write to device
    return "OWSWITCH: Set with wrong value for gpio port, must be 0 <= gpio <= ".((1 << $cnumber{$attr{$name}{"model"}})-1)
      if( ! ((int($value) >= 0) && (int($value) <= ((1 << $cnumber{$attr{$name}{"model"}})-1 ))) );
     
    if( $interface eq "OWX" ){
      $ret = OWXSWITCH_SetState($hash,int($value));
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXSWITCH_PT_SetState($hash,int($value)) );
      };
      $ret = GP_Catch($@) if $@;
    }elsif( $interface eq "OWServer" ){
      $ret2 = OWFSSWITCH_SetState($hash,int($value));
      $ret3 = OWFSSWITCH_GetState($hash);
    }else{
      return "OWSWITCH: Set with wrong IODev type $interface";
    }
    #-- process results
    if($ret){
      return "OWSWITCH: Could not set device $name, reason: ".$ret;
    }
  }
  
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
# OWXSWITCH_BinValues - Process reading from one device - translate binary into raw
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

sub OWXSWITCH_BinValues($$$$$$$) {
  my ($hash, $context, $reset, $owx_dev, $crcpart, $numread, $res) = @_;

  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  my $error  = 0;
  my @data   = []; 
  my $value;
  my $msg;
  my $cmd;
  my $chip;
  my $outfnd;
  my $outval;
  
  OWX_WDBGL($name,4,"OWXSWITCH_BinValues: called for device $name in context $context with data ",$res);

  #-- note: value 1 corresponds to OFF, 0 to ON normally
  #         val = input value, vax = output value
  #   setstate -> only set, getstate -> only get, mod -> get-set
  #-- Outer if - check get or set
  if ( $context =~ /^(......)\.(get|mod)state\.?(final|(\d))?\.?(\d)?/){
    $cmd    = $2;
    $chip   = $1;
    $outfnd = $3;
    $outval = $5;
    #-- initial get operation
    #-- family = 12 => DS2406 -------------------------------------------------------
    if( $chip eq "ds2406" )  {
      #-- we have to get rid  of the first 12 bytes
      if( length($res) == 16 ){
        $res=substr($res,12);
      }
      @data=split(//,$res);
      $crcpart = $crcpart.substr($res,0,2);
      
      if (@data != 4){
        $error = 1;
        $msg   = "$name: invalid data length in $context, ".int(@data)." instead of 4 bytes, ";
      }elsif(OWX_CRC16($crcpart,$data[2],$data[3]) == 0){
        $error = 1;
        $msg   = "$name: invalid CRC in getstate, ";
      }else{
        $msg   = "$name: no error, ";
        $value=ord($data[0]);
        $hash->{owg_val}->[0] = ($value>>2) & 1;
        $hash->{owg_vax}->[0] =  $value     & 1;
        $hash->{owg_val}->[1] = ($value>>3) & 1;
        $hash->{owg_vax}->[1] = ($value>>1) & 1;

      }
    #-- family = 29 => DS2408 -------------------------------------------------------
    }elsif( $chip eq "ds2408" ) {
      #-- we have to get rid  of the first 12 bytes
      if( length($res) == 22 ){
        $res=substr($res,12);
      }
      @data=split(//,$res);
      $crcpart = $crcpart.substr($res,0,8);

      if (@data < 10){
        $error = 1;
        $msg   = "$name: invalid data length in $context, ".int(@data)." instead of >=10 bytes, ";
      }elsif(ord($data[6])!=255){
        $error = 1;
        $msg   = "$name: invalid data in getstate, ";
      }elsif(OWX_CRC16($crcpart,$data[8],$data[9]) == 0){
        $error = 1;
        $msg   = "$name: invalid CRC in getstate, ";
      }else{
        $msg   = "$name: no error, ";
        for(my $i=0;$i<8;$i++){
          $hash->{owg_val}->[$i] = (ord($data[0])>>$i) & 1;
          $hash->{owg_vax}->[$i] = (ord($data[1])>>$i) & 1;
        };
      }
    #-- family = 3A => DS2413 -------------------------------------------------------
    }elsif( $chip eq "ds2413" ){
      #-- we have to get rid  of the first 10 bytes
      if( length($res) == 12 ){
        $res=substr($res,10);
      }
      @data=split(//,$res);

      if (@data != 2){
        $error = 1;
        $msg   = "$name: invalid data length in $context, ".int(@data)." instead of 2 bytes, ";
      }elsif((15- (ord($data[0])>>4)) != (ord($data[0]) & 15)){
        $error = 1;
        $msg   = "$name: invalid data in getstate, ";
      }else{
        $msg    ="$name: no error, ";
        $hash->{owg_val}->[0] = ord($data[0])      & 1;
        $hash->{owg_vax}->[0] = (ord($data[0])>>1) & 1;
        $hash->{owg_val}->[1] = (ord($data[0])>>2) & 1;
        $hash->{owg_vax}->[1] = (ord($data[0])>>3) & 1;
      }
    };
    main::OWX_WDBGL($name,5-4*$error,"OWXSWITCH_BinValues $context: ".$msg,$res);
     
    $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1
      if( $error ); 
      
    #-- Formatting only after final get
    if( defined($outfnd) && ($outfnd eq "final") && !$error ){
      $hash->{PRESENT}  = 1;
      $value = OWSWITCH_FormatValues($hash);
      return undef;
    }
    
    #-- modstate -> get-set, here set operation
    #-- now only if data has to be overwritten
    if( $cmd eq "mod" ){
      my $gpio  = 0;
      for (my $i=0;$i<$cnumber{$attr{$name}{"model"}};$i++){
         $gpio += ($hash->{owg_vax}->[$i]<<$i) 
      };
      if( $outval==0 ){
        $gpio &= ~(1<<$outfnd); 
      }else{
        $gpio |= (1<<$outfnd); 
      } 
      #-- re-set the state 
      OWXSWITCH_SetState($hash,$gpio);
    }
   
  #-- Now for context setstate. Either being called after modstate, or directly from Set 
  }elsif ( $context =~ /^(......)\.setstate\.?(\d+)?\.?(\d+)?/){
    $chip  = $1;
    $value = $2;
    #-- family = 12 => DS2406 -------------------------------------------------------
    if( $chip eq "ds2406" ) {
      #-- we have to get rid  of the first 13 bytes
      if( length($res) == 15 ){
        $res=substr($res,13);
      }
      @data=split(//,$res);

      if (@data != 2){
        $error = 1;
        $msg   = "$name: invalid data length in setstate, ".int(@data)." instead of 2 bytes, ";
      }elsif(OWX_CRC16($crcpart,$data[0],$data[1]) == 0){
        $error = 1;
        $msg   = "$name: invalid CRC in setstate, ";
      }else{
        $msg   = "$name: no error, ";
        $hash->{owg_val}->[0] = ($value>>2) & 1;
        $hash->{owg_vax}->[0] =  $value     & 1;
        $hash->{owg_val}->[1] = ($value>>3) & 1;
        $hash->{owg_vax}->[1] = ($value>>1) & 1;    
      }
    #-- family = 29 => DS2408 -------------------------------------------------------
    }elsif( $chip eq "ds2408" ) {
      #-- we have to get rid  of the first 12 bytes
      if( length($res) == 13 ){
        $res=substr($res,12);
      }
      @data=split(//,$res);

      if (@data !=1 ){
        $error = 1;
        $msg   = "$name: invalid data length in setstate, ".int(@data)." instead of 1 bytes, ";
      }elsif($data[0] ne "\xAA"){
        $error = 1;
        $msg   = "$name: invalid data in setstate, ";
      }else{
        $msg   = "$name: no error, ";
        for(my $i=0;$i<8;$i++){
          $outval = ($value >>$i) & 1;
          $hash->{owg_vax}->[$i] = $outval;
          $hash->{owg_val}->[$i] = 0
            if( $outval ==0);
        };
      }
    #-- family = 3A => DS2413 -------------------------------------------------------
    }elsif( $chip eq "ds2413" ){
      #-- we have to get rid  of the first 12 bytes
      if( length($res) == 14 ){
        $res=substr($res,12);
      }
      @data=split(//,$res);

      if (@data != 2){
        $error = 1;
        $msg   = "$name: invalid data length in setstate, ".int(@data)." instead of 2 bytes, ";
      }elsif( $data[0] ne "\xAA"){
        $error = 1;
        $msg   = "$name: invalid data in setstate, ";
      }else{
        $msg   = "$name: no error, ";
        $outval = (ord($data[1])>>1) & 1;
        $hash->{owg_vax}->[0] = $outval;
        $hash->{owg_val}->[0] = 0 
          if( $outval ==0);
        $outval = (ord($data[1])>>3) & 1;
        $hash->{owg_vax}->[1] = $outval;
        $hash->{owg_val}->[1] = 0 
          if( $outval ==0);
      }
   #--
    }
    OWX_WDBGL($name,5-4*$error,"OWXSWITCH_BinValues $context: ".$msg,$res);
    $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1
      if( $error ); 
    #-- and finally after setstate follows another getstate
    OWXSWITCH_GetModState($hash,"final",undef);
  }
  return undef;
}

########################################################################################
#
# OWXSWITCH_GetModState - Get gpio ports from device and overwrite
#
# Parameter hash = hash of device addressed
#           mod  = if 1, overwrite state with new data
#
########################################################################################

sub OWXSWITCH_GetModState($$$) {
  my ($hash,$outfnd,$outval) = @_;
  
  my ($select, $res, @data);
  
  #-- ID of the device
  my $owx_dev = $hash->{ROM_ID};
  my $owx_rnf = substr($owx_dev,3,12);
  my $owx_f   = substr($owx_dev,0,2);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name = $hash->{NAME};
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- what do we have to do
  my $context;
  my $proc;
  if( !defined($outfnd) ){
    $context = "getstate";
    #-- take your time
    $proc = 1;
  }elsif( $outfnd eq "final"){
    $context = "getstate.final";
    #-- faster !
    $proc = 1;
  }else{
    $context = "modstate.$outfnd.$outval";
    #-- faster !
    $proc = 1;
  }
   
  #-- family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the access channel command
    #   \xF5 plus the two byte channel control and the value
    #-- reading 9 + 3 + 2 data bytes + 2 CRC bytes = 16 bytes
    $select=sprintf("\xF5\xDD\xFF"); 
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,4);
      return "OWSWITCH: $name not accessible in reading"
        if( $res eq 0 );
      return "OWSWITCH: $name has returned invalid data"
        if( length($res)!=16);
      #OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2406.$context",undef,$owx_dev,$select,4,substr($res,12));

    #-- NEW OWX interface
    }else{
      ####        master   slave   context           proc   owx_dev   data     crcpart  numread startread callback               delay
      #OWX_Qomplex($master, $hash, "ds2406.$context", $proc, $owx_dev, $select, $select, 4,      12,       \&OWXSWITCH_BinValues, 0.05); 
      OWX_Qomplex($master, $hash, "ds2406.$context", $proc, $owx_dev, $select, $select, 16,      0,       \&OWXSWITCH_BinValues, 0.05); 
      return undef;
    }
  #-- family = 29 => DS2408
  }elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read PIO registers command
    #   \xF5 plus the two byte channel target address
    #-- reading 9 + 3 + 8 data bytes + 2 CRC bytes = 22 bytes
    $select=sprintf("\xF0\x88\x00");  
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){ 
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,10);
      return "OWSWITCH: $name not accessible in reading"
        if( $res eq 0 );
      return "OWSWITCH: $name has returned invalid data"
        if( length($res)!=22);
      #OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2408.$context",0,$owx_dev,$select,4,substr($res,12));

    #-- NEW OWX interface
    }else{
      ####        master   slave  context            proc   owx_dev   data     crcpart numread startread callback               delay
      #OWX_Qomplex($master, $hash, "ds2408.$context", $proc, $owx_dev, $select, $select,12,     12,       \&OWXSWITCH_BinValues, 0.05); 
      OWX_Qomplex($master, $hash, "ds2408.$context", $proc, $owx_dev, $select, $select, 22,     0,       \&OWXSWITCH_BinValues, 0.05); 
      return undef;
    }
  #-- family = 3A => DS2413
  }elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== get gpio values ===============================
    #-- issue the match ROM command \x55 and the read gpio command
    #   \xF5 plus 2 empty bytes
    #-- reading 9 + 1 + 2 data bytes = 12 bytes
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){ 
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,"\xF5",2);
      return "OWSWITCH: $name not accessible in reading"
        if( $res eq 0 );
      return "OWSWITCH: $name has returned invalid data"
        if( length($res)!=12);
      #OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2413.$context",0,$owx_dev,substr($res,9,1),2,substr($res,10));

    #-- NEW OWX interface
    }else{
      ####        master   slave   context           proc   owx_dev   data     crcpart numread  startread callback               delay
      #OWX_Qomplex($master, $hash, "ds2413.$context", $proc, $owx_dev, "\xF5", "\xF5",  2,       10,       \&OWXSWITCH_BinValues, 0.05); 
      OWX_Qomplex($master, $hash, "ds2413.$context", $proc, $owx_dev, "\xF5", "\xF5",  12,       0,       \&OWXSWITCH_BinValues, 0.05); 
      return undef;
    }
  } else {
    return "OWSWITCH: $name has unknown device family $hash->{OW_FAMILY}\n";
  }
}

########################################################################################
#
# OWXSWITCH_SetState - Set and reread gpio ports of device, and rereads gpio ports 
#
# Parameter hash = hash of device addressed
#           value = integer value for device gpio output
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

  #--  family = 12 => DS2406
  if( $hash->{OW_FAMILY} eq "12" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and the write status command
    #   \x55 at address TA1 = \x07 TA2 = \x00
    #-- reading 9 + 4 + 2 data bytes = 15 bytes
    $select=sprintf("\x55\x07\x00%c",(($value<<5) & 96));
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){ 
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,2);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      #OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2406.setstate.$value",0,$owx_dev,$select,2,substr($res,13));
    #-- NEW OWX interface
    }else{
      ####        master   slave   context                  proc owx_dev     data     crcpart       numread startread callback               delay
      #                                                     16 pushes this to the top of the queue
      #OWX_Qomplex($master, $hash, "ds2406.setstate.$value", 1,  $owx_dev,   $select, $select,            2,      13,       \&OWXSWITCH_BinValues, undef); 
      OWX_Qomplex($master, $hash, "ds2406.setstate.$value", 1,  $owx_dev,   $select, $select,            15,      0,       \&OWXSWITCH_BinValues, undef); 
      return undef;
    }
  #--  family = 29 => DS2408
  } elsif( $hash->{OW_FAMILY} eq "29" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and  the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",$value,255-$value);  
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){ 
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,1);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2408.setstate.$value",0,$owx_dev,0,1,substr($res,12));
    #-- NEW OWX interface
    }else{
      ####        master   slave  context                   proc  owx_dev   data     crcpart numread startread callback               delay
      #                                                     16 pushes this to the top of the queue
      #OWX_Qomplex($master, $hash, "ds2408.setstate.$value", 1,   $owx_dev, $select, 0,      1,      12,       \&OWXSWITCH_BinValues, undef); 
      OWX_Qomplex($master, $hash, "ds2408.setstate.$value", 1,   $owx_dev, $select, 0,      13,      0,       \&OWXSWITCH_BinValues, undef); 
      return undef;
    }
  #-- family = 3A => DS2413      
  } elsif( $hash->{OW_FAMILY} eq "3A" ) {
    #=============== set gpio values ===============================
    #-- issue the match ROM command \x55 and the write gpio command
    #   \x5A plus the value byte and its complement
    $select=sprintf("\x5A%c%c",252+$value,3-$value);   
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){ 
      OWX_Reset($master);
      $res=OWX_Complex($master,$owx_dev,$select,2);
      if( $res eq 0 ){
        return "device $owx_dev not accessible in writing"; 
      }
      OWX_Reset($master);
      return OWXSWITCH_BinValues($hash,"ds2413.setstate",0,$owx_dev,0,2,substr($res,12));
    #-- NEW OWX interface
    }else{
      ####        master   slave  context            proc owx_dev   data     cmd    numread startread callback               delay
      #                                                  16 pushes this to the top of the queue
      #OWX_Qomplex($master, $hash, "ds2413.setstate", 1,   $owx_dev, $select, 0,     2,      12,       \&OWXSWITCH_BinValues, undef); 
      OWX_Qomplex($master, $hash, "ds2413.setstate", 1,   $owx_dev, $select, 0,     14,      0,       \&OWXSWITCH_BinValues, undef); 
      return undef;
    }
  } else {
    return "unknown device family $hash->{OW_FAMILY}\n";
  }
}

########################################################################################
#
# OWXSWITCH_PT_GetState - Get gpio ports from device asynchronous
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWXSWITCH_PT_GetState($) {

  my ($hash) = @_;

  return PT_THREAD( sub {

    my ($thread) = @_;
    my ($select, $ret, @data, $response);

    #-- ID of the device
    my $owx_dev = $hash->{ROM_ID};

    #-- hash of the busmaster
    my $master = $hash->{IODev};

    PT_BEGIN($thread);

    my ($i,$j,$k);

    #-- family = 12 => DS2406
    if( $hash->{OW_FAMILY} eq "12" ) {
      #=============== get gpio values ===============================
      #-- issue the match ROM command \x55 and the access channel command
      #   \xF5 plus the two byte channel control and the value
      #-- reading 9 + 3 + 2 data bytes + 2 CRC bytes = 16 bytes
      $thread->{'select'}=sprintf("\xF5\xDD\xFF");
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$thread->{'select'},4);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $response = $thread->{pt_execute}->PT_RETVAL();
      unless (length($response) == 4) { 
        PT_EXIT("$owx_dev has returned invalid data");
      }
      $ret = OWXSWITCH_BinValues($hash,"ds2406.getstate",1,$owx_dev,$thread->{'select'},4,$response);
      if (defined $ret) {
        PT_EXIT($ret);
      }
    #-- family = 29 => DS2408
    }elsif( $hash->{OW_FAMILY} eq "29" ) {
      #=============== get gpio values ===============================
      #-- issue the match ROM command \x55 and the read PIO rtegisters command
      #   \xF5 plus the two byte channel target address
      #-- reading 9 + 3 + 8 data bytes + 2 CRC bytes = 22 bytes
      $thread->{'select'}=sprintf("\xF0\x88\x00");
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$thread->{'select'},10);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $response = $thread->{pt_execute}->PT_RETVAL();
      unless (length($response) == 10) {
        PT_EXIT("$owx_dev has returned invalid data")
      };
      $ret = OWXSWITCH_BinValues($hash,"ds2408.getstate",1,$owx_dev,$thread->{'select'},10,$response);
      if (defined $ret) {
        PT_EXIT($ret);
      }
    #-- family = 3A => DS2413
    }elsif( $hash->{OW_FAMILY} eq "3A" ) {
      #=============== get gpio values ===============================
      #-- issue the match ROM command \x55 and the read gpio command
      #   \xF5 plus 2 empty bytes
      #-- reading 9 + 1 + 2 data bytes = 12 bytes
      $thread->{'select'}="\xF5";
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$thread->{'select'},2);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $response = $thread->{pt_execute}->PT_RETVAL();
      unless (length($response) == 2) {
        PT_EXIT("$owx_dev has returned invalid data");
      }
      $ret = OWXSWITCH_BinValues($hash,"ds2413.getstate",1,$owx_dev,$thread->{'select'},2,$response);
      if (defined $ret) {
        PT_EXIT($ret);
      }
    } else {
      PT_EXIT("unknown device family $hash->{OW_FAMILY}\n");
    }
    PT_END;
  });
}

########################################################################################
#
# OWXSWITCH_PT_SetState - Set gpio ports of device asynchronous
#
# Parameter hash = hash of device addressed
#           value = integer value for device outputs
#
########################################################################################

sub OWXSWITCH_PT_SetState($$) {

  my ($hash,$value) = @_;

  return PT_THREAD( sub {

    my ($thread) = @_;
    my ($select,$res,@data);

    #-- ID of the device
    my $owx_dev = $hash->{ROM_ID};

    #-- hash of the busmaster
    my $master = $hash->{IODev};

    PT_BEGIN($thread);

    #--  family = 12 => DS2406
    if( $hash->{OW_FAMILY} eq "12" ) {
      #=============== set gpio values ===============================
      # Writing the output state via the access channel command does
      # not work contrary to documentation. Using the write status command 
      #-- issue the match ROM command \x55 and the read status command
      #   \xAA at address TA1 = \x07 TA2 = \x00   
      #-- reading 9 + 3 + 1 data bytes + 2 CRC bytes = 15 bytes

      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,"\xAA\x07\x00", 3);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $res = $thread->{pt_execute}->PT_RETVAL();

      #-- first step
      my $stat    = ord(substr($res,0,1));
      my $statneu = ( $stat & 159 ) | (($value<<5) & 96) ; 
      #-- call the second step
      #-- issue the match ROM command \x55 and the write status command
      #   \x55 at address TA1 = \x07 TA2 = \x00
      #-- reading 9 + 4 + 2 data bytes = 15 bytes
      $thread->{'select'}=sprintf("\x55\x07\x00%c",$statneu);

      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$thread->{'select'}, 2);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $res = $thread->{pt_execute}->PT_RETVAL();

      my $command = $thread->{'select'};

      #-- second step from above
      @data=split(//,$res);
      if( int(@data) != 2){
        PT_EXIT("state could not be set for device $owx_dev");
      }
      if (OWX_CRC16($command,$data[0],$data[1]) == 0) {
        PT_EXIT("invalid CRC");
      }

      #-- put into local buffer
      $hash->{owg_val}->[0] = $value % 2;
      $hash->{owg_vax}->[0] = $value % 2;
      $hash->{owg_val}->[1] = int($value / 2);
      $hash->{owg_vax}->[1] = int($value / 2);

    #--  family = 29 => DS2408
    } elsif( $hash->{OW_FAMILY} eq "29" ) {
      #=============== set gpio values ===============================
      #-- issue the match ROM command \x55 and  the write gpio command
      #   \x5A plus the value byte and its complement
      $select=sprintf("\x5A%c%c",$value,255-$value);  

      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select, 1);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $res = $thread->{pt_execute}->PT_RETVAL();

      @data=split(//,$res);
      if (@data != 1) {
        PT_EXIT("invalid data length, ".int(@data)." instead of 1 bytes");
      }
      if( $data[0] ne "\xAA") {
        PT_EXIT("state could not be set for device $owx_dev");
      }

    #-- family = 3A => DS2413      
    } elsif( $hash->{OW_FAMILY} eq "3A" ) {
      #=============== set gpio values ===============================
      #-- issue the match ROM command \x55 and the write gpio command
      #   \x5A plus the value byte and its complement
      $select=sprintf("\x5A%c%c",252+$value,3-$value);   
      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev,$select, 1);
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
      $res = $thread->{pt_execute}->PT_RETVAL();

      @data=split(//,$res);
      if (@data != 1) {
        PT_EXIT("invalid data length, ".int(@data)." instead of 1 bytes");
      } 
      if( $data[0] ne "\xAA") {
        PT_EXIT("state could not be set for device $owx_dev");
      }
    } else {
      PT_EXIT("unknown device family $hash->{OW_FAMILY}\n");
    }
    PT_END;
  });
}

sub OWXSWITCH_PT_SetOutput($$$) {

  my ($hash,$fnd,$nval) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($ret,$value);

    PT_BEGIN($thread);

    $thread->{task} = OWXSWITCH_PT_GetState($hash);
    PT_WAIT_THREAD($thread->{task});
    die $thread->{task}->PT_CAUSE() if ($thread->{task}->PT_STATE() == PT_ERROR);
    $ret = $thread->{task}->PT_RETVAL();
    die $ret if $ret;
    $value = 0;
    #-- vax or val ?
    for (my $i=0;$i<$cnumber{$attr{$hash->{NAME}}{"model"}};$i++){
      $value += ($hash->{owg_vax}->[$i]<<$i) 
        if( $i != $fnd );
      $value += ($nval<<$i)
        if( $i == $fnd );  
    }
    $thread->{value} = $value;
    $thread->{task} = OWXSWITCH_PT_SetState($hash,$thread->{value});
    PT_WAIT_THREAD($thread->{task});
    die $thread->{task}->PT_CAUSE() if ($thread->{task}->PT_STATE() == PT_ERROR);
    $ret = $thread->{task}->PT_RETVAL();
    die $ret if $ret;
    PT_END;
  });
}

1;

=pod
=item device
=item summary to control 1-Wire adressable switches DS2413, DS206, DS2408
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
            <code>attr OWX_S AName light-a|la</code>
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
                <br />Measurement interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update. </li>
        </ul>
        <a name="OWSWITCHset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owswitch_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update. </li>
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
            <li><a name="owswitch_input">
                    <code>get &lt;name&gt; input &lt;channel-name&gt;</code></a><br /> state for
                channel (A,B, ... or defined channel name) This value reflects the measured value,
                not necessarily the one set as output state, because the output transistors are open
                collector switches. A measured state of 1 = OFF therefore corresponds to an output
                state of 1 = OFF, but a measured state of 0 = ON can also be due to an external
                shortening of the output, it will be signaled by appending the value of the attribute stateS to the reading.</li>
            <li><a name="owswitch_gpio">
                    <code>get &lt;name&gt; gpio</code></a><br />Obtain state of all channels</li>
        </ul>
        <a name="OWSWITCHattr"></a>  
        <h4>Attributes</h4> 
        <ul><li><a name="owswitch_interval2">
                    <code>attr &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update.</li>
        </ul>For each of the following attributes, the channel identification A,B,...
        may be used. <ul>
            <li><a name="owswitch_states"><code>&lt;name&gt; stateS &lt;string&gt;</code></a>
                <br/> character string denoting external shortening condition (default is X, set to "none" for empty).</li>
            <li><a name="owswitch_cname"><code>attr &lt;name&gt; &lt;channel&gt;Name
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the channel [|short name used in state reading] </li>
            <li><a name="owswitch_cunit"><code>attr &lt;name&gt; &lt;channel&gt;Unit
                        &lt;string&gt;|&lt;string&gt;</code></a>
                <br />display for on | off condition </li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        
=end html
=cut
