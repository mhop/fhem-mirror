########################################################################################
#
# OWCOUNT.pm
#
# FHEM module to commmunicate with 1-Wire Counter/RAM DS2423
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
#
#  SO FAR ONLY external counter inputs A,B are available ! Neither memory content, nor internal counters are questioned. 
#
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
# OWX  = 1-Wire bus master interface (Peter Henning)
# OWFS = 1-Wire file system (??)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.03 - July, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWCOUNT [<model>] <ROM_ID> [interval] 
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be an
#              DS2423 Counter/RAM  
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#       [interval] is an optional query interval in seconds
#
# get <name> id                  => FAM_ID.ROM_ID.CRC 
# get <name> present             => 1 if device present, 0 if not
# get <name> interval            => query interval
# get <name> memory <page>       => 32 byte string from page 0..13
# get <name> midnight  <channel> => todays starting value for counter
# get <name> counter  <channel>  => value for counter
# get <name> counters            => values for both counters
#
# set <name> interval            => set query interval for measurement
# set <name> memory <page>       => 32 byte string into page 0..13
# set <name> midnight  <channel> => todays starting value for counter
#
# Additional attributes are defined in fhem.cfg, in some cases per channel, where <channel>=A,B
# Note: attributes are read only during initialization procedure - later changes are not used.
#
# attr <name> <channel>Name <string>|<string> = name for the channel | a type description for the measured value
# attr <name> <channel>Unit <string>|<string> = unit of measurement for this channel | its abbreviation 
# attr <name> <channel>Offset <float> = offset added to the reading in this channel 
# attr <name> <channel>Factor <float> = factor multiplied to (reading+offset) in this channel 
# attr <name> <channel>Mode <string>  = normal (default) or daily
#
# In normal counting mode each returned counting value will be factor*(reading+offset)
# In daily  counting mode each returned counting value will be factor*(reading+offset)-midnight
#           where midnight is stored as string in the 32 byte memory associated with the counter
#           if this midnight string 
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
my @owg_fixed = ("A","B");
my @owg_channel;
#-- channel values - always the raw values from the device
my @owg_val;
my @owg_midnight;
my $owg_str;

my %gets = (
  "id"          => "",
  "present"     => "",
  "interval"    => "",
  "memory"      => "",
  "midnight"    => "",
  "counter"     => "",
  "counters"    => ""
);

my %sets = (
  "interval"    => "",
  "memory"      => "",
  "midnight"    => ""
);

my %updates = (
  "present"     => "",
  "counter"     => ""
);


########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWCOUNT
#
########################################################################################
#
# OWCOUNT_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWCOUNT_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "OWCOUNT_Define";
  $hash->{UndefFn} = "OWCOUNT_Undef";
  $hash->{GetFn}   = "OWCOUNT_Get";
  $hash->{SetFn}   = "OWCOUNT_Set";
  #Name        = channel name
  #Offset      = an offset added to the reading
  #Factor      = a factor multiplied with (reading+offset)  
  #Unit        = a unit of measure
  my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2423 loglevel:0,1,2,3,4,5 ";
 
  for( my $i=0;$i<int(@owg_fixed);$i++ ){
    $attlist .= " ".$owg_fixed[$i]."Name";
    $attlist .= " ".$owg_fixed[$i]."Offset";
    $attlist .= " ".$owg_fixed[$i]."Factor";
    $attlist .= " ".$owg_fixed[$i]."Unit";
    $attlist .= " ".$owg_fixed[$i]."Mode:normal,daily";
  }
  $hash->{AttrList} = $attlist; 
}

#########################################################################################
#
# OWCOUNT_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWCOUNT_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWCOUNT [<model>] <id> [interval]
  # e.g.: define flow OWCOUNT 525715020000 300
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$fam,$id,$crc,$interval,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $scale         = "";
  $ret           = "";

  #-- check syntax
  return "OWCOUNT: Wrong syntax, must be define <name> OWCOUNT [<model>] <id> [interval]"
       if(int(@a) < 2 || int(@a) > 5);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = $a[2];
  my $a3 = defined($a[3]) ? $a[3] : "";
  if( $a2 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = "DS2423";
    $id            = $a[2];
    if(int(@a)>=4) { $interval = $a[3]; }
  } elsif(  $a3 =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $model         = $a[2];
    return "OWCOUNT: Wrong 1-Wire device model $model"
      if( $model ne "DS2423");
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
  } else {    
    return "OWCOUNT: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   determine CRC Code - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC("1D.".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = "1D.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = "1D";
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWCOUNT: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
  $modules{OWCOUNT}{defptr}{$id} = $hash;
  $hash->{STATE} = "Defined";
  Log 3, "OWCOUNT:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
  #-- Start timer for initialization in a few seconds
  InternalTimer(time()+1, "OWCOUNT_InitializeDevice", $hash, 0);
  
  #-- Start timer for updates
  InternalTimer(time()+$hash->{INTERVAL}, "OWCOUNT_GetValues", $hash, 0);

  return undef; 
}

########################################################################################
#
# OWCOUNT_InitializeDevice - delayed setting of initial readings and channel names  
#
#  Parameter hash = hash of device addressed
#
########################################################################################

sub OWCOUNT_InitializeDevice($) {
  my ($hash) = @_;
  
  my $name   = $hash->{NAME};
    
  #-- Set channel names, channel units and alarm values
  for( my $i=0;$i<int(@owg_fixed);$i++) { 
    #-- initial readings 
    $owg_val[$i]      = 0.0;
    $owg_midnight[$i] = 0.0; 
    #-- name
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i]."|event";
    my @cnama = split(/\|/,$cname);
    if( int(@cnama)!=2){
      Log 1, "OWCOUNT: Incomplete channel name specification $cname. Better use $cname|<type of data>";
      push(@cnama,"unknown");
    }
 
    #-- unit
    my $unit = defined($attr{$name}{$owg_fixed[$i]."Unit"})  ? $attr{$name}{$owg_fixed[$i]."Unit"} : "counts|cts";
    my @unarr= split(/\|/,$unit);
    if( int(@unarr)!=2 ){
      Log 1, "OWCOUNT: Incomplete channel unit specification $unit. Better use $unit|<abbreviation>";
      push(@unarr,"");  
    }

    #-- offset and scale factor 
    my $offset  = defined($attr{$name}{$owg_fixed[$i]."Offset"}) ? $attr{$name}{$owg_fixed[$i]."Offset"} : 0;
    my $factor  = defined($attr{$name}{$owg_fixed[$i]."Factor"}) ? $attr{$name}{$owg_fixed[$i]."Factor"} : 1; 
    my $mode    = defined($attr{$name}{$owg_fixed[$i]."Mode"}) ? $attr{$name}{$owg_fixed[$i]."Mode"} : "normal"; 
    #-- put into readings
    $owg_channel[$i] = $cnama[0];  
    $hash->{READINGS}{"$owg_channel[$i]"}{TYPE}     = $cnama[1];  
    $hash->{READINGS}{"$owg_channel[$i]"}{UNIT}     = $unarr[0];
    $hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR} = $unarr[1];
    $hash->{READINGS}{"$owg_channel[$i]"}{OFFSET}   = $offset;  
    $hash->{READINGS}{"$owg_channel[$i]"}{FACTOR}   = $factor;  
  }
  
  #-- set status according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- OWX interface
  if( !defined($interface) ){
    return "OWCOUNT: Interface missing";
  } elsif( $interface eq "OWX" ){
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  }else{
    return "OWCOUNT: InitializeDevice with wrong IODev type $interface";
  }
  #-- Initialize all the display stuff  
  OWCOUNT_FormatValues($hash);
}

########################################################################################
#
# OWCOUNT_FormatValues - put together various format strings 
#
#  Parameter hash = hash of device addressed, fs = format string
#
########################################################################################

sub OWCOUNT_FormatValues($) {
  my ($hash) = @_;
  
  my $name    = $hash->{NAME}; 
  my ($offset,$factor,$midnight,$vval);
  my ($value1,$value2,$value3)   = ("","","");
  my $galarm = 0;

  my $tn = TimeNow();
  
  #-- formats for output
  for (my $i=0;$i<int(@owg_fixed);$i++){
    my $cname = defined($attr{$name}{$owg_fixed[$i]."Name"})  ? $attr{$name}{$owg_fixed[$i]."Name"} : $owg_fixed[$i];  
    my @cnama = split(/\|/,$cname);
    $owg_channel[$i]=$cnama[0]; 
    $offset   = $hash->{READINGS}{"$owg_channel[$i]"}{OFFSET};  
    $factor   = $hash->{READINGS}{"$owg_channel[$i]"}{FACTOR};
    #-- only if attribute value Mode=daily, take the midnight value from memory
    if( defined($attr{$name}{$owg_fixed[$i]."Mode"} )){ 
      if( $attr{$name}{$owg_fixed[$i]."Mode"} eq "daily"){
         $midnight = $owg_midnight[$i];
         #-- parse float from midnight
         $midnight =~ /([\d\.]+)/;
         $midnight = 0.0 if(!(defined($midnight)));
      }
    } else { 
      $midnight = 0.0;
    }
    #Log 1, "OWCOUNT: midnight = $midnight";
    #-- correct values for proper offset, factor 
    #-- integer values + 1 decimal
    if( $factor == 1.0 ){
      $vval    = int(($owg_val[$i] + $offset - $midnight)*10)/10;
      #-- string buildup for return value and STATE
      $value1 .= sprintf( "%s: %5.1f %s", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
      $value2 .= sprintf( "%s: %5.1f %s ", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
    #-- floating point values
    } else {
      $vval    = int((($owg_val[$i] + $offset)*$factor - $midnight)*1000)/1000;
      #-- string buildup for return value and STATE
      $value1 .= sprintf( "%s: %5.3f %s", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
      $value2 .= sprintf( "%s: %5.2f %s ", $owg_channel[$i], $vval,$hash->{READINGS}{"$owg_channel[$i]"}{UNITABBR});
    }
    $value3 .= sprintf( "%s: " , $owg_channel[$i]);
    
    #-- if daily mode and midnight has passed, store the interpolated value in the midnight store
    my $oldval = $hash->{READINGS}{"$owg_channel[$i]"}{VAL};
    my $oldtim = $hash->{READINGS}{"$owg_channel[$i]"}{TIME};
    if( $oldtim ){    
      my ($yearo,$montho,$dayrest) = split(/-/,$oldtim);
      my $dayo = substr($dayrest,0,2);
      my ($houro,$mino,$seco) = split(/:/,substr($dayrest,3));
      my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
      if( $day!=$dayo ){
        my $dt = ((24-$houro)*3600 -$mino*60 - $seco)/( ($hour+24-$houro)*3600 + ($min-$mino)*60 + ($sec-$seco) );
        $midnight = $oldval*(1-$dt)+$vval*$dt;
        OWXCOUNT_SetPage($hash,14+$i,sprintf("%f",$midnight));
      }
    } 
    #-- put into READINGS
    $hash->{READINGS}{"$owg_channel[$i]"}{VAL}   = $vval;
    $hash->{READINGS}{"$owg_channel[$i]"}{TIME}  = $tn;
    
    #-- insert comma
    if( $i<int(@owg_fixed)-1 ){
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
# OWCOUNT_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWCOUNT_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = undef;
  my $ret     = "";
  my $page;
  my $channo  = undef;
  my $channel;

  #-- check syntax
  return "OWCOUNT: Get argument is missing @a"
    if(int(@a) < 2);
    
  #-- check argument
  return "OWCOUNT: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
    if(!defined($gets{$a[1]}));

  #-- get id
  if($a[1] eq "id") {
    $value = $hash->{ROM_ID};
     return "$a[0] $reading => $value";
  } 
  
  #-- get present
  if($a[1] eq "present") {
    #-- hash of the busmaster
    my $master       = $hash->{IODev};
    $value           = OWX_Verify($master,$hash->{ROM_ID});
    $hash->{PRESENT} = $value;
    return "$a[0] $reading => $value";
  } 

  #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$a[0] $reading => $value";
  } 
  
  #-- reset presence
  #-- TODO: THIS IS TOO STRONG !!!
  #$hash->{PRESENT}  = 0;
  
  #-- get memory page/counter according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- check syntax for getting memory page 0..13 or midnight A/B
  if( ($reading eq "memory") || ($reading eq "midnight") ){
    if( $reading eq "memory" ){
      return "OWCOUNT: set needs parameter when reading memory: <page>"
        if( int(@a)<2 );
      $page=int($a[2]);
      if( ($page<0) || ($page>13) ){
        return "OWXCOUNT: Wrong memory page requested";
      }
    }else{
      return "OWCOUNT: set needs parameter when reading midnight: <channel>"
        if( int(@a)<2 );
      #-- find out which channel we have
      if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
        $page=14;
      }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
        $page=15;
      } else {
        return "OWCOUNT: invalid midnight counter address, must be A, B or defined channel name"
      }
    }
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXCOUNT_GetPage($hash,$page);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWCOUNT: Get with wrong IODev type $interface";
    }
    #-- when we have a return code, we have an error
    if( $ret ){
      return $ret;
    }else{
      return "OWCOUNT: $name.$reading [$page] =>".$owg_str;
    }
  }
  
  #-- check syntax for getting counter
  # TODO: WAS passiert, wenn channel name noch falsch ist ?
  if( $reading eq "counter" ){
    return "OWCOUNT: get needs parameter when reading counter: <channel>"
      if( int(@a)<2 );
    #-- find out which channel we have
    if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
      $page=14;
    }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
      $page=15;
    } else {
      return "OWCOUNT: invalid counter address, must be A, B or defined channel name"
    }

    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXCOUNT_GetPage($hash,$page);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetPage($hash,"reading");
    #-- Unknown interface
    }else{
      return "OWCOUNT: Get with wrong IODev type $interface";
    }
  #-- check syntax for getting counters
  }elsif( $reading eq "counters" ){
    return "OWCOUNT: get needs no parameter when reading counters"
      if( int(@a)==1 );
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXCOUNT_GetPage($hash,14);
      $ret = OWXCOUNT_GetPage($hash,15);
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_GetValues($hash);
    }else{
      return "OWCOUNT: GetValues with wrong IODev type $interface";
    }
  }
  #-- process results
  if( $ret  ){
    return "OWCOUNT: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  return "OWCOUNT: $name.$reading => ".OWCOUNT_FormatValues($hash);  
 
}

#######################################################################################
#
# OWCOUNT_GetValues - Updates the reading from one device
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWCOUNT_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = "";
  my $ret     = "";
  my $offset;
  my $factor;
  
  #-- define warnings
  my $warn        = "none";
  $hash->{ALARM}  = "0";

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWCOUNT_GetValues", $hash, 1);
  
  #-- reset presence
  $hash->{PRESENT}  = 0;
  
  #-- Get readings according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  if( $interface eq "OWX" ){
    $ret = OWXCOUNT_GetPage($hash,14);
    $ret = OWXCOUNT_GetPage($hash,15);
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetValues($hash);
  }else{
    return "OWCOUNT: GetValues with wrong IODev type $interface";
  }
  
  #-- process results
  if( defined($ret)  ){
    return "OWCOUNT: Could not get values from device $name";
  }
  $hash->{PRESENT} = 1; 
  $value=OWCOUNT_FormatValues($hash);
  #--logging
  Log 5, $value;
  $hash->{CHANGED}[0] = $value;
  
  DoTrigger($name, undef);
  
  return undef;
}

#######################################################################################
#
# OWCOUNT_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWCOUNT_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", sort keys %sets);
    return $newkeys ;    
  }
  
  #-- check syntax
  return "OWCOUNT: Set needs one parameter when setting this value"
    if( int(@a)<3 );
  
  #-- check argument
  if( !defined($sets{$a[1]}) ){
        return "OWCOUNT: Set with unknown argument $a[1]";
  }
  
  #-- define vars
  my $ret     = undef;
  my $page;
  my $data;
  my $channo  = undef;
  my $channel;
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
 
  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWCOUNT: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWCOUNT_GetValues", $hash, 1);
    return undef;
  }
  
  #-- set memory page/counter according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- check syntax for setting memory page 0..13 or midnight A/B
  if( ($key eq "memory") || ($key eq "midnight") ){
    if( $key eq "memory" ){
      return "OWCOUNT: set needs parameter when writing memory: <page>"
        if( int(@a)<2 );
      $page=int($a[2]);
      if( ($page<0) || ($page>13) ){
        return "OWXCOUNT: Wrong memory page write attempted";
      }
    }else{
      return "OWCOUNT: set needs parameter when writing midnight: <channel>"
        if( int(@a)<2 );
      #-- find out which channel we have
      if( ($a[2] eq $owg_channel[0]) || ($a[2] eq "A") ){
        $page=14;
      }elsif( ($a[2] eq $owg_channel[1]) || ($a[2] eq "B") ){    
        $page=15;
      } else {
        return "OWCOUNT: invalid midnight counter address, must be A, B or defined channel name"
      }
    }
   
    $data=$a[3];
    for( my $i=4;$i<int(@a);$i++){
      $data.=" ".$a[$i];
    }
    if( length($data) > 32 ){
      Log 1,"OWXCOUNT: memory data truncated to 32 characters";
      $data=substr($data,0,32);
    }elsif( length($data) < 32 ){
      for(my $i=length($data)-1;$i<32;$i++){
        $data.=" ";
      }
    }
    
    #-- OWX interface
    if( $interface eq "OWX" ){
      $ret = OWXCOUNT_SetPage($hash,$page,$data);
    #-- OWFS interface
    #}elsif( $interface eq "OWFS" ){
    #  $ret = OWFSAD_setPage($hash,$page,$data);
    #-- Unknown interface
    }else{
      return "OWCOUNT: Set with wrong IODev type $interface";
    }
  }
}

########################################################################################
#
# OWCOUNT_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWCOUNT_Undef ($) {
  my ($hash) = @_;
  delete($modules{OWCOUNT}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# via OWFS
#
# Prefix = OWFSCOUNT
#
########################################################################################





########################################################################################
#
# The following subroutines in alphabetical order are only for a 1-Wire bus connected 
# directly to the FHEM server
#
# Prefix = OWXCOUNT
#
########################################################################################
#
# OWXAD_GetPage - Get one memory page + counter from device
#
# Parameter hash = hash of device addressed
#           page = 0..15
#
########################################################################################

sub OWXCOUNT_GetPage($$) {
  my ($hash,$page) = @_;
  
  my ($select, $res, $res2, $res3, @data);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
  my ($i,$j,$k);

  #=============== wrong value requested ===============================
  if( ($page<0) || ($page>15) ){
    return "OWXCOUNT: Wrong memory page requested";
  } 
  #=============== get memory + counter ===============================
  #-- issue the match ROM command \x55 and the read memory + counter command
  #   \xA5 TA1 TA2 reading 40 data bytes and 2 CRC bytes
  my $ta2 = ($page*32) >> 8;
  my $ta1 = ($page*32) & 255;
  #Log 1, "OWXCOUNT: getting page Nr. $ta2 $ta1";
  $select=sprintf("\xA5%c%c",$ta1,$ta2);   
  #-- reset the bus
  OWX_Reset($master);
    #-- reading 9 + 3 + 40 data bytes and 2 CRC bytes = 54 bytes
  $res=OWX_Complex($master,$owx_dev,$select,42);
  if( $res eq 0 ){
    return "OWX: Device $owx_dev not accessible in reading $page page"; 
  }
  
  #-- process results
  if( length($res) < 54 ) {
    #Log 1, "OWXCOUNT: warning, have received ".length($res)." bytes in first step";
    #-- read the data in a second step
    $res.=OWX_Complex($master,"","",0);
    #-- process results
    if( length($res) < 54 ) {
      #Log 1, "OWXCOUNT: warning, have received ".length($res)." bytes in second step";  
      #-- read the data in a third step
      $res.=OWX_Complex($master,"","",0);
    }
  }  
  #-- reset the bus
  OWX_Reset($master);

  #-- process results
  if( length($res) < 54){
    Log 1, "OWXCOUNT: warning, have received ".length($res)." bytes in three steps";
    #return "OWXCOUNT: warning, have received ".length($res)." bytes in three steps";
  }
  #Log 1, "OWXCOUNT: warning, have received ".length($res)." bytes in three steps";
  
  #-- first 12 byte are 9 ROM ID +3 command, next 32 are memory
  #-- memory part, treated as string
  $owg_str=substr($res,12,32);
  #-- counter part
  if( ($page == 14) || ($page == 15) ){
    @data=split(//,substr($res,44));
    if ( ($data[4] | $data[5] | $data[6] | $data[7]) ne "\x00" ){
      Log 1, "OWXCOUNT: Device $owx_dev returns invalid data ".ord($data[4])." ".ord($data[5])." ".ord($data[6])." ".ord($data[7]);
      return "OWXCOUNT: Device $owx_dev returns invalid data";
    }
  
    #-- first ignore memory and only use counter
    my $value = ord($data[3])*4096 + ord($data[2])*256 +ord($data[1])*16 + ord($data[0]);
   
    if( $page == 14) {
      $owg_val[0] = $value;
      $owg_midnight[0] = $owg_str;
    }elsif( $page == 15) {
      $owg_val[1] = $value;
      $owg_midnight[1] = $owg_str;
    }
  }
 
  return undef;
}

########################################################################################
#
# OWXCOUNT_SetPage - Set one memory page of device
#
# Parameter hash = hash of device addressed
#           page = "alarm" or "status"
#
########################################################################################

sub OWXCOUNT_SetPage($$$) {

  my ($hash,$page,$data) = @_;
  
  my ($select, $res, $res2, $res3);
  
  #-- ID of the device, hash of the busmaster
  my $owx_dev = $hash->{ROM_ID};
  my $master  = $hash->{IODev};
  
 #=============== wrong value requested ===============================
  if( ($page<0) || ($page>15) ){
    return "OWXCOUNT: Wrong memory page requested";
  } 
  #=============== set memory =========================================
  #-- issue the match ROM command \x55 and the write scratchpad command
  #   \x0F TA1 TA2 and the read scratchpad command reading 3 data bytes
  my $ta2 = ($page*32) >> 8;
  my $ta1 = ($page*32) & 255;
  #Log 1, "OWXCOUNT: setting page Nr. $ta2 $ta1";
  $select=sprintf("\x0F%c%c",$ta1,$ta2).$data;   
  #-- reset the bus
  OWX_Reset($master);
  #-- reading 9 + 3 + 16 bytes = 29 bytes
  $res=OWX_Complex($master,$owx_dev,$select,0);
  if( $res eq 0 ){
    return "OWX: Device $owx_dev not accessible in writing scratchpad"; 
  }
  
  #-- issue the match ROM command \x55 and the read scratchpad command
  #   \xAA 
  #-- reset the bus
  OWX_Reset($master);
  #-- reading 9 + 4 + 16 bytes = 28 bytes
  # TODO: sometimes much less than 28
  $res=OWX_Complex($master,$owx_dev,"\xAA",28);
  if( length($res) < 13 ){
    return "OWX: Device $owx_dev not accessible in reading scratchpad"; 
  }

  #-- issue the match ROM command \x55 and the copy scratchpad command
  #   \x5A followed by 3 byte authentication code
  $select="\x5A".substr($res,10,3);
  #-- reset the bus
  OWX_Reset($master);
  $res=OWX_Complex($master,$owx_dev,$select,6);
  
  #-- process results
  if( $res eq 0 ){
    return "OWXCOUNT: Device $owx_dev not accessible for writing"; 
  }
  
  return undef;
}

1;
