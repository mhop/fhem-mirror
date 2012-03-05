########################################################################################
#
# OWID.pm
#
# FHEM module to commmunicate with 1-Wire ID-ROMS
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 1.03 - March, 2012
#   
# Setup bus device in fhem.cfg as
# define <name> OWID [<model>] <ROM_ID>
#
# where <name> may be replaced by any name string 
#     
#       <model> is a 1-Wire device type. If omitted, we assume this to be a DS2502
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#
# Additional attributes are defined in fhem.cfg as
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

#-- declare variables
my %gets = (
  "present"     => "",
  "id"    => ""
);
my %sets    = ();
my %updates = ();
 
########################################################################################
#
# The following subroutines are independent of the bus interface
#
# Prefix = OWID
#
########################################################################################
#
# OWID_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWID_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "OWID_Define";
  $hash->{UndefFn}  = "OWID_Undef";
  $hash->{GetFn}    = "OWID_Get";
  $hash->{SetFn}    = undef;
  my $attlist       = "IODev do_not_notify:0,1 showtime:0,1 model:DS2502 loglevel:0,1,2,3,4,5 ";
  $hash->{AttrList} = $attlist; 
}

#########################################################################################
#
# OWID_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub OWID_Define ($$) {
  my ($hash, $def) = @_;
  
  # define <name> OWID [<model>] <id> 
  # e.g.: define flow OWID 525715020000
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$model,$id,$scale,$ret);
  
  #-- default
  $name          = $a[0];
  $ret           = "";

  #-- check syntax
  return "OWID: Wrong syntax, must be define <name> OWID [<model>] <id>"
       if(int(@a) < 2 || int(@a) > 4);
       
  #-- check if this is an old style definition, e.g. <model> is missing
  my $a2 = lc($a[2]);
  my $a3 = defined($a[3]) ? lc($a[3]) : "";
  if( $a2 =~ m/^[0-9|a-f]{12}$/ ) {
    $model         = "DS2502";
    $id            = $a[2];
  } elsif(  $a3 =~ m/^[0-9|a-f]{12}$/ ) {
    $model         = $a[2];
    return "OWID: Wrong 1-Wire device model $model"
      if( $model ne "DS2502");
    $id            = $a[3];
  } else {    
    return "OWID: $a[0] ID $a[2] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  #   YY must be determined from id
  my $crc = sprintf("%02x",OWX_CRC("09.".$id."00"));
  
  #-- Define device internals
  $hash->{ROM_ID}     = "09.".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = 9;
  $hash->{PRESENT}    = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWID: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
    
  $modules{OWID}{defptr}{$id} = $hash;
  
  #-- Take channel names from $owg_channel
  #my $channels;
  
  #foreach my $a (sort keys %attr) {
  #    print "attr $a $attr{$a}\n"; 
  #    foreach my $b (sort keys %{$attr{$a}}) {
  #      print "============> attr $a $b $attr{$a}{$b}\n"; 
  #  }
  #}
  #if ( $channels ){
  #  my $i=0;
  #  $channels =~ s/(\w+)/$owg_channel[$i++]=$1/gse;
  #}
  
  #print "$name channels = ".join(" ",@owg_channel)."\n";
     
  $hash->{STATE} = "Defined";
  Log 3, "OWID:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  #-- OWX interface
  #if( $interface eq "OWX" ){
  #  OWXAD_SetPage($hash,"alarm");
  #  OWXAD_SetPage($hash,"status");
  #-- OWFS interface
  #}elsif( $interface eq "OWFS" ){
  #  $ret = OWFSAD_GetPage($hash,"reading");
  #-- Unknown interface
  #}else{
  #  return "OWID: Define with wrong IODev type $interface";
  #}
 
  #-- redefine attributes according to channel names
  #my $attlist = "IODev do_not_notify:0,1 showtime:0,1 model:DS2450 loglevel:0,1,2,3,4,5 ".
  #              "channels ";
  #for( my $i=0;$i<4;$i++ ){
  #  $attlist .= " ".$owg_channel[$i]."Offset";
  #  $attlist .= " ".$owg_channel[$i]."Factor";
  #  $attlist .= " ".$owg_channel[$i]."Scale";
  #}
  #$hash->{AttrList} = $attlist; 
   
  #-- Start timer for updates
  #InternalTimer(time()+$hash->{INTERVAL}, "OWID_GetValues", $hash, 0);
  
  #-- InternalTimer blocks if init_done is not true
  #my $oid = $init_done;
  $hash->{STATE} = "Initialized";
  return undef; 
}

########################################################################################
#
# OWID_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed, a = argument array
#
########################################################################################

sub OWID_Get($@) {
  my ($hash, @a) = @_;
  
  my $reading = $a[1];
  my $name    = $hash->{NAME};
  my $model   = $hash->{OW_MODEL};
  my $value   = undef;
  my $ret     = "";
  my $offset;
  my $factor;

   #-- check syntax
  return "OWID: Get argument is missing @a"
    if(int(@a) != 2);
    
  #-- check argument
  return "OWID: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets)
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
}

########################################################################################
#
# OWID_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWID_Undef ($) {
  my ($hash) = @_;
  delete($modules{OWID}{defptr}{$hash->{OW_ID}});
  RemoveInternalTimer($hash);
  return undef;
}

1;
