########################################################################################
#
# OWAD.pm  
#
# FHEM module to commmunicate with 1-Wire A/D converters DS2450
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
use GPUtils qw(:all);
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

my $owx_version="7.01";
#-- fixed raw channel name, flexible channel name
my @owg_fixed   = ("A","B","C","D");
my @owg_channel = ("A","B","C","D");
#-- channel mode - fixed for now, see initialization
my @owg_mode;
#-- resolution in bit - fixed for now, see initialization
my @owg_resoln;
#-- raw range in mV - fixed for now, see initialization
my @owg_range;

my %gets = (
  "id"          => ":noArg",
  "reading"     => ":noArg",
  "alarm"       => ":noArg",
  "status"      => ":noArg",
  "version"     => ":noArg"
);

my %sets = (
  "initialize"  => "",
  "interval"    => "",
  "AAlarm"      => "",
  "ALow"        => "",
  "AHigh"       => "",
  "BAlarm"      => "",
  "BLow"        => "",
  "BHigh"       => "",
  "CAlarm"      => "",
  "CLow"        => "",
  "CHigh"       => "",
  "DAlarm"      => "",
  "DLow"        => "",
  "DHigh"       => ""
);

my %updates = (
  "present"     => "",
  "reading"     => "",
  "alarm"       => "",
  "status"      => ""
);


########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWAD
#
########################################################################################
#
# OWAD_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWAD_Define";
  $hash->{UndefFn} = "OWAD_Undef";
  $hash->{GetFn}   = "OWAD_Get";
  $hash->{SetFn}   = "OWAD_Set";
  $hash->{NotifyFn}= "OWAD_Notify";
  $hash->{InitFn}  = "OWAD_Init";
  $hash->{AttrFn}  = "OWAD_Attr";
 
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2450 ".
                "stateAL0 stateAL1 stateAH0 stateAH1 ".
                "interval ".
                $readingFnAttributes;
 
  for( my $i=0;$i<int(@owg_fixed);$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Function";
    $attlist .= " ".$owg_fixed[$i]."Unit";
    $attlist .= " ".$owg_fixed[$i]."Alarm:none,low,high,both";
    $attlist .= " ".$owg_fixed[$i]."Low";
    $attlist .= " ".$owg_fixed[$i]."High";
  }
  $hash->{AttrList} = $attlist; 
  
  #-- value globals
  $hash->{owg_status} = [];
  #$hash->{owg_state} = undef;
  #-- channel values - always the raw values from the device
  $hash->{owg_val} = ["","","",""];
  #-- alarm status 0 = disabled, 1 = enabled, but not alarmed, 2 = alarmed
  $hash->{owg_slow}=[0,0,0,0];
  $hash->{owg_shigh}=[0,0,0,0];
  #-- alarm values - always the raw values committed to the device
  $hash->{owg_vlow} = [];
  $hash->{owg_vhigh} = [];
  
  #-- make sure OWX is loaded so OWX_CRC is available if running with OWServer
  main::LoadModule("OWX");	
}

#########################################################################################
#
# OWAD_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWAD_Define ($$) {
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWAD: Wrong syntax, must be define <name> OWAD [<model>] <id> [interval] or OWAD <fam>.<id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
          
  #-- different types of definition allowed
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  #-- no model, 12 characters
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2450";
    $fam           = "20";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  #-- no model, 2+12 characters
   } elsif(  $a2 =~ m/^[0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
    $fam           = substr($a[2],0,2);
    $id            = substr($a[2],3);
    if(int(@a)>=4) { $interval = $a[3]; }
    if( $fam eq "20" ){
      $model = "DS2450";
      CommandAttr (undef,"$name model DS2450"); 
    }else{
      return "OWAD: Wrong 1-Wire device family $fam";
    }
  #-- model, 12 characters
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
    if( $model eq "DS2450" ){
      $fam = "20";
      CommandAttr (undef,"$name model DS2450"); 
    }else{
      return "OWAD: Wrong 1-Wire device model $model";
    }
  } else {    
    return "OWAD: $a[0] ID $a[2] invalid, specify a 12 or 2.12 digit value";
  }
  
  #--   determine CRC Code 
  $crc = sprintf("%02x",OWX_CRC($fam.".".$id."00"));
 
  #-- Define device internals
  $hash->{ROM_ID}     = "$fam.$id.$crc";
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  $hash->{ERRCOUNT}   = 0;
  $hash->{ERRSTATE}   = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}) or !defined($hash->{IODev}->{NAME}) ){
    return "OWAD: Warning, no 1-Wire I/O device found for $name.";
  } else {
    $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0; #-- false for now
  }

  $main::modules{OWAD}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","defined",1);
  Log 3, "OWAD:     Device $name defined."; 

  $hash->{NOTIFYDEV} = "global";
  
  if ($init_done) {
    OWAD_Init($hash);
  }
  return undef; 
}

######################################################################################
#
# OWAD_Notify Function -
#  Parameter hash = hash of device addressed
#            dev  = device
#
######################################################################################

sub OWAD_Notify ($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    OWAD_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

#####################################################################################
#
# OWAD_Init Function -
#  Parameter hash = hash of device addressed
#          
#
######################################################################################

sub OWAD_Init ($) {
  my ($hash)=@_;
  #-- Start timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+10, "OWAD_InitializeDevice", $hash, 0);
  return undef; 
}
  
#######################################################################################
#
# OWAD_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWAD_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      #-- interval modified at runtime
      $key eq "interval" and do {
        #-- check value
        return "OWAD: set $name interval, must be >= 0" if(int($value) < 0);
       #-- update timer
        $hash->{INTERVAL} = int($value);
        if ($init_done) {
          RemoveInternalTimer($hash);
          InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 0);
        }
        last;
      };
      #-- alarm settings modified at runtime
      $key =~ m/(.*)(Alarm|Low|High)/ and do {
        #-- safeguard against uninitialized devices
        return undef
          if( $hash->{READINGS}{"state"}{VAL} eq "defined" );
        $ret = OWAD_Set($hash,($name,$key,$value));
        last;
      };
      $key eq "IODev" and do {
        AssignIoPort($hash,$value);
        if( defined($hash->{IODev}) ) {
          $hash->{ASYNC} = $hash->{IODev}->{TYPE} eq "OWX_ASYNC" ? 1 : 0;
          if ($init_done) {
            OWAD_Init($hash);
          }
        }
        last;
      };
    }
  } elsif ( $do eq "del" ) {
    ARGUMENT_HANDLER: {
      #-- should remove alarm setting, but does nothing so far
      $key =~ m/(.*)(Alarm)/ and do {
        last;
      }
    }
  }
  return $ret;
}

########################################################################################
#
# OWAD_ChannelNames - find the real channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_ChannelNames($) { 
  my ($hash) = @_;
  
  my $name    = $hash->{NAME};
  my $state   = $hash->{READINGS}{"state"}{VAL};
 
  my ($cname,@cnama,$unit);

  for (my $i=0;$i<int(@owg_fixed);$i++){
    #-- name
    $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : "$owg_fixed[$i]";
    @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      push(@cnama,$cnama[0]);
    }
    $owg_channel[$i]=$cnama[0];
 
    #-- unit
    $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "V";
    if($unit eq "none"){
      $unit = "";
    }else{
      $unit = " ".$unit;
    }
   
    #-- put into readings
    $hash->{READINGS}{$owg_channel[$i]}{ABBR}     = $cnama[1];  
    $hash->{READINGS}{$owg_channel[$i]}{UNIT}     = $unit;
  }
}  

########################################################################################
#
# OWAD_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWAD_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my $interface = $hash->{IODev}->{TYPE};
  my ($vval,$vlow,$vhigh,$vfunc,$ret);
  my $vfuncall = "";
  my $svalue = "";
  
  #-- insert initial values 
  for( my $k=0;$k<int(@owg_fixed);$k++ ){
  #-- TODO $hash->{owg_val}->[..] might be undefined here?
    $vfuncall .= "\$hash->{owg_val}->[$k]=$hash->{owg_val}->[$k];"; 
  }
  my $alarm;
  my $galarm     = 0;
  my $achange    = 0;
  my $schange    = 0;
  
  #-- alarm signatures
  my $stateal1 = defined($attr{$name}{stateAL1}) ? $attr{$name}{stateAL1} : "↓";
  my $stateah1 = defined($attr{$name}{stateAH1}) ? $attr{$name}{stateAH1} : "↑";
  my $stateal0 = defined($attr{$name}{stateAL0}) ? $attr{$name}{stateAL0} : "";
  my $stateah0 = defined($attr{$name}{stateAH0}) ? $attr{$name}{stateAH0} : "";
  
  #-- no change in any value if invalid reading
  for (my $i=0;$i<int(@owg_fixed);$i++){
    return "" if( (!defined($hash->{owg_val}->[$i])) || ($hash->{owg_val}->[$i] eq "") );
  }
  
  #-- obtain channel names
  OWAD_ChannelNames($hash);
 
  #-- put into READINGS
  readingsBeginUpdate($hash);
  
  #-- formats for output
  for (my $i=0;$i<int(@owg_fixed);$i++){
    if (defined($attr{$name}{$owg_fixed[$i]."Function"})){
      $vfunc = $attr{$name}{$owg_fixed[$i]."Function"};
    } else {
      $vfunc = "V$owg_fixed[$i]";
    }
    $hash->{tempf}{$owg_fixed[$i]}{function}   = $vfunc;  
        
    #-- replace by proper values (VA -> $hash->{owg_val}->[0] etc.)
    #   careful: how to prevent {VAL} from being replaced ?
    for( my $k=0;$k<int(@owg_fixed);$k++ ){
      my $sstr = "V$owg_fixed[$k]";
      $vfunc =~ s/VAL/WERT/g;
      $vfunc =~ s/$sstr/\$hash->{owg_val}->[$k]/g;
      $vfunc =~ s/WERT/VAL/g;
    }
      
    #-- determine the measured value from the function
    $vfunc = $vfuncall.$vfunc;
    $vfunc = eval($vfunc);
    if( !$vfunc ){
      $vval = 0.0;
    } elsif( $vfunc ne "" ){
      $vval = $vfunc;
    } else {
      $vval = "???";
    }
        
    #-- low alarm value
    $vlow =$hash->{owg_vlow}->[$i];
    $main::attr{$name}{$owg_fixed[$i]."Low"}=$vlow;
    #-- high alarm value
    $vhigh=$hash->{owg_vhigh}->[$i];
    $main::attr{$name}{$owg_fixed[$i]."High"}=$vhigh;            
        
    #-- string buildup for return value, STATE and alarm
    $svalue .= sprintf( "%s: %5.3f%s", $hash->{READINGS}{$owg_channel[$i]}{ABBR}, $vval,$hash->{READINGS}{$owg_channel[$i]}{UNIT});
             
    #-- Test for alarm condition
    $alarm = "none";
    #-- alarm signature low
    #-- TODO may be undefined here?
    if( $hash->{owg_slow}->[$i] == 0 ) { 
    } else {
      $alarm="low";
      if( $vval > $vlow ){
        $hash->{owg_slow}->[$i] = 1;
        $svalue .=  $stateal0;
      } else {
        $galarm = 1;
        $hash->{owg_slow}->[$i] = 2;
        $svalue .=  $stateal1;
      }
    }
    #-- alarm signature high
    #-- TODO may be undefined here?
    if( $hash->{owg_shigh}->[$i] == 0 ) { 
    } else {
      if( $alarm eq "low") {
        $alarm="both";
      }else{
        $alarm="high";
      }
      if( $vval < $vhigh ){
        $hash->{owg_shigh}->[$i] = 1;
        $svalue .=  $stateah0;
      } else {
        $galarm = 1;
        $hash->{owg_shigh}->[$i] = 2;
        $svalue .=  $stateah1;
      }
    }
      
    #-- put into READINGS
    $vval = sprintf( "%5.3f", $vval);
    readingsBulkUpdate($hash,"$owg_channel[$i]",$vval);
    #-- insert space
    if( $i<int(@owg_fixed)-1 ){
      $svalue .= " ";
    }
  }
  
  #-- STATE
  readingsBulkUpdate($hash,"state",$svalue);
  readingsEndUpdate($hash,1); 
  if( $galarm != $hash->{ALARM} ){
    $hash->{ALARM} = $galarm;
    main::OWX_Alarms($hash->{IODev});
  } 
  return $svalue;
}

########################################################################################
#
# OWAD_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWAD_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev}; 
  my $interface= $hash->{IODev}->{TYPE};
  my ($value,$value2,$value3)   = (undef,undef,undef);
  my $ret     = "";

  #-- check syntax
  return "OWAD: Get argument is missing @a"
    if(int(@a) != 2);
    
  #-- check argument
  my $msg = "OWAD: Get with unknown argument $a[1], choose one of ";
  $msg .= "$_$gets{$_} " foreach (keys%gets);
  return $msg
    if(!defined($gets{$a[1]}));

  #-- get id
  if($a[1] eq "id") {
    $value = $owx_dev;
     return "$name.id => $value";
  } 
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $owx_version";
  }
  
  #-- reset current ERRSTATE
  $hash->{ERRSTATE} = 0;
  
  #-- get reading according to interface type
  if($a[1] eq "reading") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"reading",1);
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXAD_PT_GetPage($hash,"reading",1));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSAD_GetPage($hash,"reading",1);
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process result
    if( $master->{ASYNCHRONOUS} ){
      return undef;
    }else{
      if( defined($ret) ){
        $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
        return "OWAD: Could not get reading from device $name for ".$hash->{ERRCOUNT}." times, reason $ret";
      }
      return "OWAD: $name.reading => ".$hash->{READINGS}{"state"}{VAL};
    }
  }
  
  #-- get alarm values according to interface type
  if($a[1] eq "alarm") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"alarm",1);
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXAD_PT_GetPage($hash,"alarm",1));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSAD_GetPage($hash,"alarm",1);
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process result
    if( $master->{ASYNCHRONOUS} ){
      return undef;
    }else{
      if( defined($ret) ){
        $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
        return "OWAD: Could not get alarm values from device $name for ".$hash->{ERRCOUNT}." times, reason $ret";
      }
    
      #-- assemble ouput string
      $value = "";
      for (my $i=0;$i<int(@owg_fixed);$i++){
        $value .= sprintf "%s:[%4.2f,%4.2f] ",$owg_channel[$i],
        $main::attr{$name}{$owg_channel[$i]."Low"},
        $main::attr{$name}{$owg_channel[$i]."High"}; 
      }
      return "OWAD: $name.alarm => $value";
    }
  }
  
   #-- get status values according to interface type
  if($a[1] eq "status") {
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_GetPage($hash,"status",1);
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        $ret = OWX_ASYNC_RunToCompletion($hash,OWXAD_PT_GetPage($hash,"status",1));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSAD_GetPage($hash,"status",1);
    #-- Unknown interface
    }else{
      return "OWAD: Get with wrong IODev type $interface";
    }
  
    #-- process result
    if( $master->{ASYNCHRONOUS} ){
      #return "OWAD: $name getting status, please wait for completion";
      return undef;
    }else{
      if( defined($ret) ){
        $hash->{ERRCOUNT}=$hash->{ERRCOUNT}+1;
        return "OWAD: Could not get values from device $name for ".$hash->{ERRCOUNT}." times, reason $ret";
      } 
    
      #-- assemble output string
      $value = "\n";
      for (my $i=0;$i<int(@owg_fixed);$i++){
        $value  .= $owg_channel[$i].": ".$owg_mode[$i].", ";
        #$value .= "disabled ," 
        #  if ( !($sb2 && 128) );
        $value .=  sprintf "raw range %3.2f V, ",$owg_range[$i]/1000;
        $value .=  sprintf "resolution %d bit, ",$owg_resoln[$i];
        if (!defined $hash->{owg_slow}->[$i]) {
          $value .= "low alarm undefined, ";
        } elsif( $hash->{owg_slow}->[$i]==0 ) { 
          $value .= "low alarm disabled, ";
        } elsif( $hash->{owg_slow}->[$i]==1 ) {
          $value .= "low alarm enabled, ";
        } elsif( $hash->{owg_slow}->[$i]==2 ) {
          $value .= "alarmed low, ";
        }
        if (!defined $hash->{owg_shigh}) {
          $value .= "high alarm undefined";
        } elsif( $hash->{owg_shigh}->[$i]==0 ) {
          $value .= "high alarm disabled";
        } elsif( $hash->{owg_shigh}->[$i]==1 ) {
          $value .= "high alarm enabled";
        } elsif( $hash->{owg_shigh}->[$i]==2 ) {
          $value .= "alarmed high";
        }
        #-- insert space
        if( $i<int(@owg_fixed)-1 ){
          $value .= "\n";
        }
      }
      return "OWAD: $name.status => ".$value;
    }
  }
}

#######################################################################################
#
# OWAD_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $interface= $hash->{IODev}->{TYPE};
  my $value   = "";
  my $ret     = "";
  my ($ret1,$ret2,$ret3);

  #-- define warnings
  my $warn        = "none";
  $hash->{ALARM}  = "0";

  RemoveInternalTimer($hash); 
  #-- auto-update for device disabled;
  return undef
    if( $hash->{INTERVAL} == 0 );
  #-- restart timer for updates  
  InternalTimer(time()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 0);

  #-- reset current ERRSTATE
  $hash->{ERRSTATE} = 0;
   
  #-- Get readings, alarms and status according to interface type
  if( $interface eq "OWX" ){
    $ret1 = OWXAD_GetPage($hash,"reading",0);
    $ret2 = OWXAD_GetPage($hash,"alarm",0);
    $ret3 = OWXAD_GetPage($hash,"status",1);
  }elsif( $interface eq "OWX_ASYNC" ){
    eval {
      OWX_ASYNC_Schedule( $hash, OWXAD_PT_GetPage($hash,"reading",0));
      OWX_ASYNC_Schedule( $hash, OWXAD_PT_GetPage($hash,"alarm",0));
      OWX_ASYNC_Schedule( $hash, OWXAD_PT_GetPage($hash,"status",1));
    };
    $ret .= GP_Catch($@) if $@;
  }elsif( $interface eq "OWServer" ){
    $ret1 = OWFSAD_GetPage($hash,"reading",0);
    $ret2 = OWFSAD_GetPage($hash,"alarm",0);
    $ret3 = OWFSAD_GetPage($hash,"status",1);
  }else{
    return "OWAD: GetValues with wrong IODev type $interface";
  }
  
  #-- process results
  $ret .= $ret1
    if( defined($ret1) );
  $ret .= $ret2
    if( defined($ret2) );
  $ret .= $ret3
    if( defined($ret3) );
  if( $ret ne "" ){
    return "OWAD: Could not get reading, alarm and status values from device $name, reason $ret";
  }
  
  return undef;
}

########################################################################################
#
# OWAD_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_InitializeDevice($) {
  my ($hash) = @_;

  my $name      = $hash->{NAME};
  my $interface = $hash->{IODev}->{TYPE};
    
  my $ret="";
  my ($ret1,$ret2);
  
  #-- Initial readings 
  $hash->{owg_val} = ["","","",""];
   
  #-- Initial alarm values
  for( my $i=0;$i<int(@owg_fixed);$i++) { 
    $hash->{ERRCOUNT}      = 0;

    #-- alarm enabling
    if( AttrVal($name,$owg_fixed[$i]."Alarm",undef) ){
      my $alarm = AttrVal($name,$owg_fixed[$i]."Alarm",undef);
      if( $alarm eq "none" ){
        $hash->{owg_slow}->[$i]=0;
        $hash->{owg_shigh}->[$i]=0;
      }elsif( $alarm eq "low" ){
        $hash->{owg_slow}->[$i]=1;
        $hash->{owg_shigh}->[$i]=0;
      }elsif( $alarm eq "high" ){
        $hash->{owg_slow}->[$i]=0;
        $hash->{owg_shigh}->[$i]=1;
      }elsif( $alarm eq "both" ){
        $hash->{owg_slow}->[$i]=1;
        $hash->{owg_shigh}->[$i]=1;
      }
    } else {
      $hash->{owg_slow}->[$i]=0;
      $hash->{owg_shigh}->[$i]=0;    
    }    
    #-- low alarm value - no checking for correct parameters
    if( AttrVal($name,$owg_fixed[$i]."Low",undef) ){
      $hash->{owg_vlow}->[$i] = $main::attr{$name}{$owg_fixed[$i]."Low"};
    } else {
      $hash->{owg_vlow}->[$i] = 0;
    }
    #-- high alarm value
    if( AttrVal($name,$owg_fixed[$i]."High",undef) ){
      $hash->{owg_vhigh}->[$i] = $main::attr{$name}{$owg_fixed[$i]."High"};
    }  else {
      $hash->{owg_vhigh}->[$i] = 0;
    }     
  }
  #-- resolution in bit - fixed for now
  @owg_resoln = (16,16,16,16);
  #-- raw range in mV - fixed for now
  @owg_range = (5120,5120,5120,5120);
  #-- mode - fixed for now
  @owg_mode  = ("input","input","input","input");
  #-- OWX interface
  if( $interface eq "OWX" ){
    $ret1 = OWXAD_SetPage($hash,"status");
    $ret2 = OWXAD_SetPage($hash,"alarm");
  }elsif( $interface eq "OWX_ASYNC" ){
    eval {
      OWX_ASYNC_Schedule( $hash, OWXAD_PT_SetPage($hash,"status"));
      OWX_ASYNC_Schedule( $hash, OWXAD_PT_SetPage($hash,"alarm"));
    };
    $ret .= GP_Catch($@) if $@;
  #-- OWFS interface
  }elsif( $interface eq "OWServer" ){
    $ret1 = OWFSAD_SetPage($hash,"status");
    $ret2 = OWFSAD_SetPage($hash,"alarm");
  }
  #-- process results
  $ret .= $ret1
    if( defined($ret1) );
  $ret .= $ret2
    if( defined($ret2) );
  if( $ret ne ""  ){
    return "OWAD: Could not initialize device $name, reason: ".$ret;
  }
    
  #-- Set state to initialized
  readingsSingleUpdate($hash,"state","initialized",1);
  
  return OWAD_GetValues($hash);
}

#######################################################################################
#
# OWAD_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWAD_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
 #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a == 2);
  
  #-- check syntax
  return "OWAD: Set needs one parameter when setting this value"
    if( int(@a)!=3 );
  
  #-- check argument
  if( !defined($sets{$a[1]}) && !($key =~ m/.*(Alarm|Low|High)/) ){
        return "OWAD: Set with unknown argument $a[1]";
  }
  
  #-- define vars
  my $ret     = undef;
  my $channon = undef;
  my $channo  = undef;
  my $condx;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
 
 #-- re-intialize
 if($key eq "initialize") {
    OWAD_InitializeDevice($hash);
    return undef;
  }
  
  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWAD: set $name interval must be >= 0"
      if(int($value) < 0);
    # update timer
    $hash->{INTERVAL} = int($value);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWAD_GetValues", $hash, 0);
    return undef;
  }
  
  #-- find out which channel we have
  my $tc =$key;
  if( $tc =~ s/(.*)(Alarm|Low|High)/$channon=$1/se ) {
    for (my $i=0;$i<int(@owg_fixed);$i++){
      if( $tc eq $owg_fixed[$i] ){
        $channo  = $i;
        $channon = $tc;
        last;
      }
    }
  }
  return "OWAD: Cannot determine channel from parameter $a[1]"
    if( !(defined($channo)));  
    
  #-- set these values depending on interface type
  my $interface= $hash->{IODev}->{TYPE};
        
  #-- set status values (alarm on or off)
  if( $key =~ m/(.*)(Alarm)/ ) {
    return "OWAD: Set with wrong value $value for $key, allowed is none/low/high/both"
      if($value ne "none" &&  $value ne "low" &&  $value ne "high" &&  $value ne "both");
    #-- put into attribute value
    if( $main::attr{$name}{$owg_fixed[$channo]."Alarm"} ne $value ){
      #Log 1,"OWAD: Correcting attribute value ".$owg_fixed[$channo]."Alarm";
      $main::attr{$name}{$owg_fixed[$channo]."Alarm"} = $value 
    }
    #-- put into device
    if( $value eq "low" || $value eq "both" ){
       $hash->{owg_slow}->[$channo]=1;
    } else{
       $hash->{owg_slow}->[$channo]=0;
    }
    if( $value eq "high" || $value eq "both" ){
       $hash->{owg_shigh}->[$channo]=1;
    } else{
       $hash->{owg_shigh}->[$channo]=0;
    }    
   
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_SetPage($hash,"status");
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXAD_PT_SetPage($hash,"status"));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSAD_SetPage($hash,"status");
    } else {
      return "OWAD: Set with wrong IODev type $interface";
    }
    #-- process results
    if( defined($ret)  ){
      return "OWAD: Could not set device $name, reason: ".$ret;
    }
    
  #-- set alarm values (alarm voltages)
  }elsif( $key =~ m/(.*)(Low|High)/ ) {
    
    #-- find upper and lower boundaries 
    my $mmin = 0.0;
    my $mmax = $owg_range[$channo]/1000;

    return sprintf("OWAD: Set with wrong value $value for $key, range is  [%3.1f,%3.1f]",$mmin,$mmax)
      if($value < $mmin || $value > $mmax);
    
    #-- round to those numbers understood by the device
    my $value2  = int($value*256000/$owg_range[$channo]+0.5)*$owg_range[$channo]/256000;
 
    if( $key =~ m/(.*)Low/ ){
      #-- put into attribute value
      if( $main::attr{$name}{$owg_fixed[$channo]."Low"} != $value2 ){
        Log 1,"OWAD: Correcting attribute value ".$owg_fixed[$channo]."Low";
        $main::attr{$name}{$owg_fixed[$channo]."Low"} = $value2 
      }
      #-- put into device
      $hash->{owg_vlow}->[$channo]  = $value2;
      
    } elsif( $key =~ m/(.*)High/ ){  
      #-- put into attribute value
      if( $main::attr{$name}{$owg_fixed[$channo]."High"} != $value2 ){
        Log 1,"OWAD: Correcting attribute value ".$owg_fixed[$channo]."High";
        $main::attr{$name}{$owg_fixed[$channo]."High"} = $value2
      }
      #-- put into device
      $hash->{owg_vhigh}->[$channo]  = $value2;
    }
  
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXAD_SetPage($hash,"alarm");
    }elsif( $interface eq "OWX_ASYNC" ){
      eval {
        OWX_ASYNC_Schedule( $hash, OWXAD_PT_SetPage($hash,"status"));
      };
      $ret = GP_Catch($@) if $@;
    #-- OWFS interface
    }elsif( $interface eq "OWServer" ){
      $ret = OWFSAD_SetPage($hash,"alarm");
    } else {
      return "OWAD: Set with wrong IODev type $interface";
    }
    #-- process results
    if( defined($ret)  ){
      return "OWAD: Could not set device $name, reason: ".$ret;
    }
  }
  
  #-- process results - we have to reread the device 
  OWAD_GetValues($hash);  
  Log 4, "OWAD: Set $hash->{NAME} $key $value";

  return undef;
}

########################################################################################
#
# OWAD_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWAD_Undef ($) {
  my ($hash) = @_;
  delete($main::modules{OWAD}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSAD
#
########################################################################################
#
# OWFSAD_GetPage - Get one memory page from device
#
# Parameter hash = hash of device addressed
#           page = "reading", "alarm" or "status"
#           final= 1 if FormatValues is to be called
#
########################################################################################

sub OWFSAD_GetPage($$$) {

  my ($hash,$page,$final) = @_;
  
  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
          
  my ($rel,$rel2,@ral,@ral2,$i,$an,$vn);
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #=============== get the voltage reading ===============================
  if( $page eq "reading"){
    #-- get values - or should we rather use the uncached ones ?
    $rel = OWServer_Read($master,"/$owx_add/volt.ALL");

    return "no return from OWServer"
      if( !defined($rel) );     
    return "empty return from OWServer"
      if( $rel eq "" );
        
    @ral = split(/,/,$rel);
  
    return "wrong data length from OWServer"
      if( int(@ral) != 4);
    for( $i=0;$i<int(@owg_fixed);$i++){
      $hash->{owg_val}->[$i]= int($ral[$i]*1000)/1000;
    }
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    #-- get values - or should we rather use the uncached ones ?
    $rel  = OWServer_Read($master,"/$owx_add/set_alarm/voltlow.ALL");
    $rel2 = OWServer_Read($master,"/$owx_add/set_alarm/volthigh.ALL");
  
  
    return "no return from OWServer"
      if( (!defined($rel)) || (!defined($rel2)) );     
    return "empty return from OWServer"
      if( ($rel eq "") || ($rel2 eq "") );
        
    @ral = split(/,/,$rel);
    @ral2= split(/,/,$rel2);
  
    return "wrong data length from OWServer"
      if( (int(@ral) != 4) || (int(@ral2) != 4) );
      
    for( $i=0;$i<int(@owg_fixed);$i++){
      $hash->{owg_vlow}->[$i] = int($ral[$i]*1000+0.5)/1000;
      $hash->{owg_vhigh}->[$i] = int($ral2[$i]*1000+0.5)/1000;
    }
    
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
    
    #-- so far not clear, how to find out which type of operation we have. 
    #   We therefore ASSUME normal operation 
    
    #-- normal operation 
    #-- put into globals
    for( $i=0;$i<int(@owg_fixed);$i++){
      $owg_mode[$i]   =  "input";
      $owg_resoln[$i] =  16;
      $owg_range[$i]  =  5120;
    }
    
    #-- get values - or should we rather use the uncached ones ?
    $rel  = OWServer_Read($master,"/$owx_add/alarm/low.ALL");
    $rel2 = OWServer_Read($master,"/$owx_add/set_alarm/low.ALL");
    
    return "no return from OWServer"
      if( (!defined($rel)) || (!defined($rel2)) );     
    return "empty return from OWServer"
      if( ($rel eq "") || ($rel2 eq "") );
        
    @ral = split(/,/,$rel);
    @ral2= split(/,/,$rel2);
  
    return "wrong data length from OWServer"
      if( (int(@ral) != 4) || (int(@ral2) != 4) );
    for( $i=0;$i<int(@owg_fixed);$i++){
      #-- low alarm disabled
      if( $ral2[$i]==0 ){  
        $an = 0;
      }else {
        #-- low alarm enabled and not set
        if ( $ral[$i]==0  ){
          $an = 1;
        #-- low alarm enabled and set
        }else{
          $an = 2;
        }
      } 
      $hash->{owg_slow}->[$i] = $an;
    }
    #-- get values - or should we rather use the uncached ones ?
    $rel  = OWServer_Read($master,"/$owx_add/alarm/high.ALL");
    $rel2 = OWServer_Read($master,"/$owx_add/set_alarm/high.ALL");
    
    return "no return from OWServer"
      if( (!defined($rel)) || (!defined($rel2)) );     
    return "empty return from OWServer"
      if( ($rel eq "") || ($rel2 eq "") );
        
    @ral = split(/,/,$rel);
    @ral2= split(/,/,$rel2);
  
    return "wrong data length from OWServer"
      if( (int(@ral) != 4) || (int(@ral2) != 4) );
    for( $i=0;$i<int(@owg_fixed);$i++){
      #-- low alarm disabled
      if( $ral2[$i]==0 ){  
        $an = 0;
      }else {
        #-- low alarm enabled and not set
        if ( $ral[$i]==0  ){
          $an = 1;
        #-- low alarm enabled and set
        }else{
          $an = 2;
        }
      } 
      $hash->{owg_shigh}->[$i] = $an;
    }
  }
  #-- and now from raw to formatted values
  $hash->{PRESENT}  = 1;
  if( $final==1 ){
    my $value = OWAD_FormatValues($hash);
    Log 5, $value;
  }
  return undef
}

########################################################################################
#
# OWFSAD_SetPage - Set one page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWFSAD_SetPage($$) {
  my ($hash,$page) = @_;

  #-- ID of the device
  my $owx_add = substr($hash->{ROM_ID},0,15);
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  
  my $i;
  my @ral =(0,0,0,0);
  my @ral2=(0,0,0,0);
  
  #=============== set the alarm values ===============================
  if ( $page eq "alarm" ) {
    OWServer_Write($master, "/$owx_add/set_alarm/voltlow.ALL",join(',',@{$hash->{owg_vlow}}));
    OWServer_Write($master, "/$owx_add/set_alarm/volthigh.ALL",join(',',@{$hash->{owg_vhigh}}));
  #=============== set the status ===============================
  } elsif ( $page eq "status" ) {
    for( $i=0;$i<int(@owg_fixed);$i++){
      if( $owg_mode[$i] eq "input" ){
        #-- resolution (TODO: check !)
        #
        #-- alarm enabled        
        if( defined($hash->{owg_slow}->[$i]) ){
         $ral[$i]=1
           if($hash->{owg_slow}->[$i]>0);
        }
        if( defined($hash->{owg_shigh}->[$i]) ){
          $ral2[$i]=1
           if($hash->{owg_shigh}->[$i]>0);
        }
      }
    }
    OWServer_Write($master, "/$owx_add/set_alarm/low.ALL",join(',',@ral));
    OWServer_Write($master, "/$owx_add/set_alarm/high.ALL",join(',',@ral2));
  #=============== wrong page write attempt  ===============================
  } else {
    return "wrong memory page write attempt";
  } 
  return undef;
}


########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXAD
#
########################################################################################
#
# OWXAD_BinValues - Process reading from one device - translate binary into raw
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

sub OWXAD_BinValues($$$$$$$) {
  my ($hash, $context, $proc, $owx_dev, $crcpart, $numread, $res) = @_;
  
  #-- hash of the busmaster
  my $master = $hash->{IODev};
  my $name   = $hash->{NAME};
  #-- inherit previous error
  my $error  = $hash->{ERRSTATE};
  my @data   = []; 
  my $value;
  my $msg;
  
  OWX_WDBGL($name,4,"OWXAD_BinValues: called for device $name in context $context with data ",$res);

  my $final = ($context =~ /\.final$/ );  
  my ($ow_thn,$ow_tln);
  
  #-- we have to get rid  of the first 12 bytes
  if( length($res) == 22 ){
    $res=substr($res,12);
  }
  @data=split(//,$res);
  $crcpart = $crcpart.substr($res,0,8);

  #-- process results
  if (int(@data) != 10){
     $msg   = "$name: invalid data length, ".int(@data)." instead of 10 bytes ";
     $error = 1;
  }elsif (OWX_CRC16($crcpart,$data[8],$data[9])==0){
     $msg   ="$name: invalid CRC ";
     $error = 1;
  }else{
     $msg   = "$name: no local error, inheritance = $error ";
  }
  OWX_WDBGL($name,5-4*$error,"OWXAD_BinValues: context $context    ".$msg,$res);
  if( $error ){
    $hash->{ERRCOUNT}++;
    $hash->{ERRSTATE} = 1;
  };
  
        
  #=============== get the voltage reading ===============================
  if( $context =~ /^ds2450.getreading/ ){
    for( my $i=0;$i<int(@owg_fixed);$i++){
      $hash->{owg_val}->[$i]= (ord($data[2*$i])+256*ord($data[1+2*$i]) )/(1<<$owg_resoln[$i]) * $owg_range[$i]/1000;
    }
  #=============== get the alarm reading ===============================
  } elsif ( $context =~ /^ds2450.getalarm/ ){
    for( my $i=0;$i<int(@owg_fixed);$i++){
      $hash->{owg_vlow}->[$i]  = int(ord($data[2*$i])/256 * $owg_range[$i]+0.5)/1000;
      $hash->{owg_vhigh}->[$i] = int(ord($data[1+2*$i])/256 * $owg_range[$i]+0.5)/1000;
    }
  #=============== get the status reading ===============================
  } elsif ( $context =~ /^ds2450.getstatus/ ) {  
    my ($sb1,$sb2);
    for( my $i=0;$i<int(@owg_fixed);$i++){
      $sb1 = ord($data[2*$i]); 
      $sb2 = ord($data[1+2*$i]);
      
      #Log 1,"VOR TEST sb1=$sb1 sb2=$sb2 UND mit 128 ist ".($sb1 && 128);
      
      #-- normal operation 
      if( ($sb1 && 128)==0) {
        #-- put into globals
        $owg_mode[$i]   =  "input";
        $owg_resoln[$i] =  ($sb1 & 15);
        $owg_resoln[$i] = 16 
          if ($owg_resoln[$i] == 0);
        $owg_range[$i]  =  ($sb2 & 1) ? 5120 : 2560;
        
        my $an;
        #-- low alarm disabled
        if( ($sb2 & 4)==0 ){  
          $an = 0;
        }else {
          #-- low alarm enabled and not set
          if ( ($sb2 & 16)==0  ){
            $an = 1;
          #-- low alarm enabled and set
          }else{
            $an = 2;
          }
        } 
        $hash->{owg_slow}->[$i]= $an;
   
        #-- high alarm disabled
        if( ($sb2 & 8)==0 ){  
          $an = 0;
        }else {
          #-- high alarm enabled and not set
          if ( ($sb2 & 32)==0  ){
            $an = 1;
          #-- high alarm enabled and set
          }else{
            $an = 2;
          }
        }   
        $hash->{owg_shigh}->[$i]= $an;
      #-- output operation     
      } else {
        $owg_mode[$i]   =  "output";
        #-- assemble status string
        $hash->{owg_status}->[$i] = $owg_mode[$i].", ";
        $hash->{owg_status}->[$i] .=  ($sb1 & 64 ) ? "ON" : "OFF";
      }
    }
  } 
  #-- and now from raw to formatted values
  $hash->{PRESENT}  = 1;
  if( ($final) && (!$error) ){
    my $value = OWAD_FormatValues($hash);
  }
  return undef
}

########################################################################################
#
# OWXAD_GetPage - Get one memory page from device
#
# Parameter hash = hash of device addressed
#           page = "reading", "alarm" or "status"
#           final= 1 if FormatValues is to be called
#
########################################################################################

sub OWXAD_GetPage($$$@) {

  my ($hash,$page,$final,$sync) = @_;
  
  my ($select, $res, $res2, $res3, @data, $an, $vn);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);

  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #=============== get the voltage reading ===============================
  if( $page eq "reading") {
    #-- issue the match ROM command \x55 and the start conversion command
    #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){
      OWX_Reset($master);
      $res= OWX_Complex($master,$owx_dev,"\x3C\x0F\x00\xFF\xFF",0);
      if( $res eq 0 ){
        return "not accessible for conversion";
      } 
      #-- conversion needs some 5 ms per channel
      select(undef,undef,undef,0.02);
    #-- NEW OWX interface
    }else{
      ####        master   slave  context   proc  owx_dev   data                     crcpart  numread  startread callback   delay
      #                                     1 additional reset after last action
      OWX_Qomplex($master, $hash, "convert", 4,    $owx_dev, "\x3C\x0F\x00\xFF\xFF", 0,       0,       undef,    undef,     0.02); 
    }   
    #-- issue the match ROM command \x55 and the read conversion page command
    #   \xAA\x00\x00 
    $select="\xAA\x00\x00";
  #=============== get the alarm reading ===============================
  } elsif ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the read alarm page command 
    #   \xAA\x10\x00 
    $select="\xAA\x10\x00";
  #=============== get the status reading ===============================
  } elsif ( $page eq "status" ) {
    #-- issue the match ROM command \x55 and the read status memory page command 
    #   \xAA\x08\x00 r
    $select="\xAA\x08\x00";
  #=============== wrong value requested ===============================
  } else {
    return "wrong memory page requested from $owx_dev";
  }
  my $context = "ds2450.get".$page.($final ? ".final" : "");
  my $proc = ($final ? 1 : 0);
  #-- OLD OWX interface
  if( !$master->{ASYNCHRONOUS} ){
    #-- reset the bus
    OWX_Reset($master);
    #-- reading 9 + 3 + 8 data bytes and 2 CRC bytes = 22 bytes
    $res=OWX_Complex($master,$owx_dev,$select,10);
    return "$owx_dev not accessible in reading page $page"
      if( $res eq 0 );
    return "$owx_dev has returned invalid data"
      if( length($res)!=22);
    #-- for processing we also need the 3 command bytes
    return OWXAD_BinValues($hash,$context,$proc,$owx_dev,$select,10,substr($res,12,10));
    
  #-- NEW OWX interface
  }else{
    ####        master   slave  context   proc  owx_dev   data     crcpart  numread  startread callback               delay
    #                                     1 additional reset after last action
    OWX_Qomplex($master, $hash, $context, 0,    $owx_dev, $select, $select, 22,      0,        \&OWXAD_BinValues,     0.01); 
    return undef;
  }   
}

########################################################################################
#
# OWXAD_SetPage - Set one page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWXAD_SetPage($$) {

  my ($hash,$page) = @_;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);
  
  #=============== set the alarm values ===============================
  if ( $page eq "alarm" ) {
    #-- issue the match ROM command \x55 and the set alarm page command 
    #   \x55\x10\x00 reading 8 data bytes and 2 CRC bytes
    $select="\x55\x10\x00";
    for( $i=0;$i<int(@owg_fixed);$i++){
      $select .= sprintf "%c\xFF\xFF\xFF",int($hash->{owg_vlow}->[$i]*256000/$owg_range[$i]); 
      $select .= sprintf "%c\xFF\xFF\xFF",int($hash->{owg_vhigh}->[$i]*256000/$owg_range[$i]);
    }
     
  #=============== set the status ===============================
  } elsif ( $page eq "status" ) {
    my ($sb1,$sb2)=(0,0);
    #-- issue the match ROM command \x55 and the set status memory page command 
    #   \x55\x08\x00 reading 8 data bytes and 2 CRC bytes
    $select="\x55\x08\x00";
    for( $i=0;$i<int(@owg_fixed);$i++){
      #if( $owg_mode[$i] eq "input" ){
      if( 1 > 0){
        #-- resolution (TODO: check !)
        $sb1 = $owg_resoln[$i] & 15;
        #-- alarm enabled        
        if( defined($hash->{owg_slow}->[$i]) ){
          $sb2   =  ( $hash->{owg_slow}->[$i] ne 0  ) ? 4 : 0;
        }
        if( defined($hash->{owg_shigh}->[$i]) ){
          $sb2  += ( $hash->{owg_shigh}->[$i] ne 0 ) ? 8 : 0;
        }
        #-- range 
        $sb2 |= 1 
          if( $owg_range[$i] > 2560 );
      } else {
        $sb1 = 128;
        $sb2 = 0;
      }
      $select .= sprintf "%c\xFF\xFF\xFF",$sb1;
      $select .= sprintf "%c\xFF\xFF\xFF",$sb2;
    }
  #=============== wrong page write attempt  ===============================
  } else {
    return "wrong memory page write attempt";
  } 
  #-- OLD OWX interface
    if( !$master->{ASYNCHRONOUS} ){
    OWX_Reset($master);
    $res=OWX_Complex($master,$owx_dev,$select,0);
    if( $res eq 0 ){
      return "device $owx_dev not accessible for writing"; 
    }
  #-- NEW OWX interface
  }else{
    ####        master   slave  context        proc  owx_dev   data     crcpart numread  startread callback delay
    OWX_Qomplex($master, $hash, "ds2450.set",  0,    $owx_dev, $select, 0,      0,       0,        undef,   undef); 
  }   
  return undef;
}

########################################################################################
#
# OWXAD_PT_GetPage - Get one memory page from device
#
# Parameter hash = hash of device addressed
#           page = "reading", "alarm" or "status"
#           final= 1 if FormatValues is to be called
#
########################################################################################

sub OWXAD_PT_GetPage($$$) {

  my ($hash,$page,$final) = @_;
  
  return PT_THREAD(sub {

    my ($thread) = @_;

    my ($res, $res2, $res3, @data, $an, $vn);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    my ($i,$j,$k);

    PT_BEGIN($thread);

    #=============== get the voltage reading ===============================
    if( $page eq "reading") {
      #-- issue the match ROM command \x55 and the start conversion command

      $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev, "\x3C\x0F\x00\xFF\xFF", 0 );
      $thread->{ExecuteTime} = gettimeofday() + 0.07; # was 0.02
      PT_WAIT_THREAD($thread->{pt_execute});
      die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);

      PT_YIELD_UNTIL(gettimeofday() >= $thread->{ExecuteTime});
      delete $thread->{ExecuteTime};

      #-- issue the match ROM command \x55 and the read conversion page command
      #   \xAA\x00\x00 
      $thread->{'select'}="\xAA\x00\x00";
    #=============== get the alarm reading ===============================
    } elsif ( $page eq "alarm" ) {
      #-- issue the match ROM command \x55 and the read alarm page command 
      #   \xAA\x10\x00 
      $thread->{'select'}="\xAA\x10\x00";
    #=============== get the status reading ===============================
    } elsif ( $page eq "status" ) {
      #-- issue the match ROM command \x55 and the read status memory page command 
      #   \xAA\x08\x00 r
      $thread->{'select'}="\xAA\x08\x00";
    #=============== wrong value requested ===============================
    } else {
      die "wrong memory page requested from $owx_dev";
    }
    #-- reading 9 + 3 + 8 data bytes and 2 CRC bytes = 22 bytes

    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev, $thread->{'select'}, 10 );
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    my $response = $thread->{pt_execute}->PT_RETVAL();
    my $res = OWXAD_BinValues($hash,"ds2450.get".$page.($final ? ".final" : ""),1,$owx_dev,$thread->{'select'},10,$response);
    if ($res) {
      die $res;
    }
    PT_END;
  });
}

########################################################################################
#
# OWXAD_PT_SetPage - Set one page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWXAD_PT_SetPage($$) {

  my ($hash,$page) = @_;

  return PT_THREAD(sub {

    my ($thread) = @_;
    my ($select, $res, $res2, $res3, @data);

    #-- ID of the device, hash of the busmaster
    my $owx_dev = $hash->{ROM_ID};
    my $master  = $hash->{IODev};

    my ($i,$j,$k);

    PT_BEGIN($thread);

    #=============== set the alarm values ===============================
    if ( $page eq "alarm" ) {
      #-- issue the match ROM command \x55 and the set alarm page command 
      #   \x55\x10\x00 reading 8 data bytes and 2 CRC bytes
      $select="\x55\x10\x00";
      for( $i=0;$i<int(@owg_fixed);$i++){
        $select .= sprintf "%c\xFF\xFF\xFF",int($hash->{owg_vlow}->[$i]*256000/$owg_range[$i]); 
        $select .= sprintf "%c\xFF\xFF\xFF",int($hash->{owg_vhigh}->[$i]*256000/$owg_range[$i]);
      }

    #++Use of uninitialized value within @owg_vlow in multiplication  at 
    #++/usr/share/fhem/FHEM/21_OWAD.pm line 1362.
    #=============== set the status ===============================
    } elsif ( $page eq "status" ) {
      my ($sb1,$sb2)=(0,0);
      #-- issue the match ROM command \x55 and the set status memory page command 
      #   \x55\x08\x00 reading 8 data bytes and 2 CRC bytes
      $select="\x55\x08\x00";
      for( $i=0;$i<int(@owg_fixed);$i++){
        #if( $owg_mode[$i] eq "input" ){
        if( 1 > 0){
          #-- resolution (TODO: check !)
          $sb1 = $owg_resoln[$i] & 15;
          #-- alarm enabled        
          if( defined($hash->{owg_slow}->[$i]) ){
            $sb2   =  ( $hash->{owg_slow}->[$i] ne 0  ) ? 4 : 0;
          }
          if( defined($hash->{owg_shigh}->[$i]) ){
            $sb2  += ( $hash->{owg_shigh}->[$i] ne 0 ) ? 8 : 0;
          }
          #-- range 
          $sb2 |= 1 
            if( $owg_range[$i] > 2560 );
        } else {
          $sb1 = 128;
          $sb2 = 0;
        }
        $select .= sprintf "%c\xFF\xFF\xFF",$sb1;
        $select .= sprintf "%c\xFF\xFF\xFF",$sb2;
      }
    #=============== wrong page write attempt  ===============================
    } else {
      PT_EXIT("wrong memory page write attempt");
    }
    #"setpage"
    $thread->{pt_execute} = OWX_ASYNC_PT_Execute($master,1,$owx_dev, $select, 0 );
    PT_WAIT_THREAD($thread->{pt_execute});
    die $thread->{pt_execute}->PT_CAUSE() if ($thread->{pt_execute}->PT_STATE() == PT_ERROR);
    PT_END;
  });
}

1;

=pod
=item device
=item summary to control 1-Wire  A/D converters DS2450
=begin html

<a name="OWAD"></a>
        <h3>OWAD</h3>
        <p>FHEM module to commmunicate with 1-Wire A/D converters<br /><br />   
        <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
         (prerequisite: Add this module's name to the list of clients in OWServer).
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first. <br/></p>
        <br /><h4>Example</h4>
        <p>
            <code>define OWX_AD OWAD 724610000000 45</code>
            <br />
            <code>attr OWX_AD DAlarm high</code>
            <br />
            <code>attr OWX_AD DName humidity</code>
            <br />
            <code>attr OWX_AD DUnit %</code>
            <br />
            <code>attr OWX_AD DFunction VD*31.907097-0.8088</code>
            <br />
            <code>attr OWX_AD DHigh 50.0</code>
            <br />
        </p><br />
        <a name="OWADdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWAD [&lt;model&gt;] &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
            <code>define &lt;name&gt; OWAD &lt;fam&gt;.&lt;id&gt; [&lt;interval&gt;]</code> 
            <br /><br /> Define a 1-Wire A/D converter.<br /><br /></p>
        <ul>
            <li>
                <code>[&lt;model&gt;]</code><br /> Defines the A/D converter model (and thus 1-Wire
                family id), currently the following values are permitted: <ul>
                    <li>model DS2450 with family id 20 (default if the model parameter is
                        omitted)</li>
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
        <br />
        <a name="OWADset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owad_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update.</li>
        </ul>
        <br />
        <a name="OWADget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owad_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owad_reading">
                    <code>get &lt;name&gt; reading</code></a><br />Obtain the measuement values. </li>
            <li><a name="owad_alarm">
                    <code>get &lt;name&gt; alarm</code></a><br />Obtain the alarm values. </li>
            <li><a name="owad_status">
                    <code>get &lt;name&gt; status</code></a><br />Obtain the i/o status values.
            </li>
        </ul>
        <br />
        <a name="OWADattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="owad_stateAL0"><code>attr &lt;name&gt; stateAL0 &lt;string&gt;</code></a>
                <br />character string for denoting low normal condition, default is empty </li>
            <li><a name="owad_stateAH0"><code>attr &lt;name&gt; stateAH0 &lt;string&gt;</code></a>
                <br />character string for denoting high normal condition, default is empty </li>
            <li><a name="owad_stateAL1"><code>attr &lt;name&gt; stateAL1 &lt;string&gt;</code></a>
                <br />character string for denoting low alarm condition, default is ↓</li>
            <li><a name="owad_stateAH1"><code>attr &lt;name&gt; stateAH1 &lt;string&gt;</code></a>
                <br />character string for denoting high alarm condition, default is ↑</li>
            <li><a name="owad_interval2">
                    <code>attr &lt;name&gt; interval &lt;int&gt;</code></a><br /> Measurement
                interval in seconds. The default is 300 seconds, a value of 0 disables the automatic update.</li>
        </ul> For each of the following attributes, the channel identification A,B,C,D may be used. <ul>
            <li><a name="owad_cname"><code>attr &lt;name&gt; &lt;channel&gt;Name
                        &lt;string&gt;[|&lt;string&gt;]</code></a>
                <br />name for the channel [|short name used in state reading]. </li>
            <li><a name="owad_cunit"><code>attr &lt;name&gt; &lt;channel&gt;Unit
                        &lt;string&gt;</code></a>
                <br />unit of measurement for this channel used in state reading (default "V", set to "none" for empty). </li>
            <li><a name="owad_cfunction">  <code>attr &lt;name&gt; &lt;channel&gt;Function
                        &lt;string&gt;</code></a>
            <br />arbitrary functional expression involving the variables VA,VB,VC,VD. VA is replaced by 
                 the (raw) measured voltage in channel A, etc. This attribute allows linearization of measurement 
                 curves as well as the mixing of various channels. </li>
            <li><a name="owad_calarm"><code>attr &lt;name&gt; &lt;channel&gt;Alarm
                        &lt;string&gt;</code></a>
                <br />alarm setting in this channel, either both, low, high or none (default). </li>
            <li><a name="owad_clow"><code>attr &lt;name&gt; &lt;channel&gt;Low
                    &lt;float&gt;</code></a>
                <br />measurement value for low alarm. </li>
            <li><a name="owad_chigh"><code>attr &lt;name&gt; &lt;channel&gt;High
                        &lt;float&gt;</code></a>
                <br />measurement value for highalarm. </li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        
=end html
=cut
