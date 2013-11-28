########################################################################################
#
# OWID.pm
#
# FHEM module to commmunicate with general 1-Wire ID-ROMS
#
# Attention: This module may communicate with the OWX module,
#            but currently not with the 1-Wire File System OWFS
#
# Prefixes for subroutines of this module:
# OW   = General 1-Wire routines  Peter Henning)
#
# Prof. Dr. Peter A. Henning, 2012
# 
# Version 2.24 - October, 2012
#   
# Setup bus device in fhem.cfg as
#
# define <name> OWID <FAM_ID> <ROM_ID>
#
# where <name> may be replaced by any name string 
#   
#       <FAM_ID> is a 2 character (1 byte) 1-Wire Family ID 
#  
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#
# get <name> id       => FAM_ID.ROM_ID.CRC 
# get <name> present  => 1 if device present, 0 if not
#
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
  "id"          => ""
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
  my $attlist       = "IODev do_not_notify:0,1 showtime:0,1 loglevel:0,1,2,3,4,5 ";
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
  
  #-- define <name> OWID <FAM_ID> <ROM_ID>
  my @a = split("[ \t][ \t]*", $def);
  
  my ($name,$fam,$id,$crc,$ret);
  
  #-- default
  $name          = $a[0];
  $ret           = "";

  #-- check syntax
  return "OWID: Wrong syntax, must be define <name> OWID <fam> <id>"
       if(int(@a) !=4 );
       
  #-- check id
  if(  $a[2] =~ m/^[0-9|a-f|A-F]{2}$/ ) {
    $fam            = $a[2];
  } else {    
    return "OWID: $a[0] family id $a[2] invalid, specify a 2 digit value";
  }
  if(  $a[3] =~ m/^[0-9|a-f|A-F]{12}$/ ) {
    $id            = $a[3];
  } else {    
    return "OWID: $a[0] ID $a[3] invalid, specify a 12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  # determine CRC Code YY - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  Log 3, "OWID: Warning, no 1-Wire I/O device found for $name."
    if(!defined($hash->{IODev}->{NAME}));
    
  $modules{OWID}{defptr}{$id} = $hash;
  
  $hash->{STATE} = "Defined";
  Log 3, "OWID:   Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
 
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

=pod
=begin html

<a name="OWID"></a>
<h3>OWID</h3>
<ul>FHEM module for 1-Wire devices that know only their unique ROM ID<br />
    <br />Note:<br /> This 1-Wire module so far works only with the OWX interface module.
    Please define an <a href="#OWX">OWX</a> device first. <br />
    <br /><b>Example</b><br />
    <ul>
        <code>define ROM1 OWX_ID OWCOUNT CE780F000000</code>
        <br />
    </ul><br />
    <a name="OWIDdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; OWID &lt;id&gt; </code>
        <br /><br /> Define a 1-Wire device.<br /><br />
        <li>
            <code>&lt;id&gt;</code>
            <br />12-character unique ROM id of the converter device without family id and
            CRC code </li>
    </ul>
    <br />
    <a name="OWIDget">
        <b>Get</b></a>
    <ul>
        <li><a name="owid_id">
                <code>get &lt;name&gt; id</code></a>
            <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
        <li><a name="owid_present">
                <code>get &lt;name&gt; present</code>
            </a>
            <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
    </ul>
    <br />
</ul>

=end html
=cut
