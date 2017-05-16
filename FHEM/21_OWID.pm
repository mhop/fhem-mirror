########################################################################################
#
# OWID.pm
#
# FHEM module to commmunicate with general 1-Wire ID-ROMS
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
# define <name> OWID <FAM_ID> <ROM_ID> or OWID <FAM_ID>.<ROM_ID>
#
# where <name> may be replaced by any name string 
#   
#       <FAM_ID> is a 2 character (1 byte) 1-Wire Family ID 
#  
#       <ROM_ID> is a 12 character (6 byte) 1-Wire ROM ID 
#                without Family ID, e.g. A2D90D000800 
#
# set <name> interval => set query interval for checking presence
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

use vars qw{%attr %defs};
use strict;
use warnings;
sub Log($$);

#-- declare variables
my %gets = (
  "present"     => "",
  "interval"    => "",
  "id"          => ""
);
my %sets    = (
  "interval"    => ""
);
my %updates = (
 "present"    => ""
);
 
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
  $hash->{SetFn}    = "OWID_Set";
  my $attlist       = "IODev do_not_notify:0,1 showtime:0,1 model loglevel:0,1,2,3,4,5 ".
                      $readingFnAttributes;
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
  
  my ($name,$interval,$fam,$id,$crc,$ret);
  
  #-- default
  $name          = $a[0];
  $interval      = 300;
  $ret           = "";

  #-- check syntax
  return "OWID: Wrong syntax, must be define <name> OWID <fam> <id> [interval]"
       if(int(@a) !=4 );
       
  #-- check id
  if(  ($a[2] =~ m/^[0-9|a-f|A-F]{2}$/) && ($a[3] =~ m/^[0-9|a-f|A-F]{12}$/)) {
    $fam           = $a[2];
    $id            = $a[3];
    if(int(@a)>=5) { $interval = $a[4]; }
  } elsif(  $a[2] =~ m/^0-9|a-f|A-F]{2}\.[0-9|a-f|A-F]{12}$/ ) {
   $fam           = substr($a[2],0,2);
   $id            = substr($a[2],3);
   if(int(@a)>=4) { $interval = $a[3]; }
  } else {    
    return "OWID: $def is invalid, specify a 2 digit 12 digit or 2.12 digit value";
  }
  
  #-- 1-Wire ROM identifier in the form "FF.XXXXXXXXXXXX.YY"
  # determine CRC Code YY - only if this is a direct interface
  $crc = defined($hash->{IODev}->{INTERFACE}) ?  sprintf("%02x",OWX_CRC($fam.".".$id."00")) : "00";
  
  #-- Define device internals
  $hash->{ROM_ID}     = $fam.".".$id.$crc;
  $hash->{OW_ID}      = $id;
  $hash->{OW_FAMILY}  = $fam;
  $hash->{PRESENT}    = 0;
  $hash->{INTERVAL}   = $interval;
  
  #-- Couple to I/O device
  AssignIoPort($hash);
  if( !defined($hash->{IODev}->{NAME}) | !defined($hash->{IODev}) | !defined($hash->{IODev}->{PRESENT}) ){
    return "OWSWITCH: Warning, no 1-Wire I/O device found for $name.";
  }
  if( $hash->{IODev}->{PRESENT} != 1 ){
    return "OWSWITCH: Warning, 1-Wire I/O device ".$hash->{IODev}->{NAME}." not present for $name.";
  }
  $modules{OWID}{defptr}{$id} = $hash;
  #--
  readingsSingleUpdate($hash,"state","Defined",1);
  Log 3, "OWTHERM: Device $name defined."; 

  #-- Initialization reading according to interface type
  my $interface= $hash->{IODev}->{TYPE};
  
  #-- Start timer for updates
  InternalTimer(time()+5+$hash->{INTERVAL}, "OWID_GetValues", $hash, 0);
  
  #--
  readingsSingleUpdate($hash,"state","Initialized",1); 
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
  
   #-- get interval
  if($a[1] eq "interval") {
    $value = $hash->{INTERVAL};
     return "$name.interval => $value";
  } 
  
  #-- get present
  if($a[1] eq "present") {
    #-- hash of the busmaster
    my $master       = $hash->{IODev};
    $value           = OWX_Verify($master,$hash->{ROM_ID});
    $hash->{PRESENT} = $value;
    if( $value == 0 ){
      readingsSingleUpdate($hash,"state","not present",1); 
    } else {
      readingsSingleUpdate($hash,"state","present",1); 
    }
    return "$name.present => $value";
  } 
}


########################################################################################
#
# OWID_GetValues - Updates the reading from one device
#
#  Parameter hash = hash of device addressed
########################################################################################

sub OWID_GetValues($) {
  my $hash    = shift;
  
  my $name    = $hash->{NAME};
  my $value   = "";
  my $ret     = "";
  my $offset;
  my $factor;
  
  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(time()+$hash->{INTERVAL}, "OWID_GetValues", $hash, 1);
  
  #-- hash of the busmaster
  my $master       = $hash->{IODev};
  $value           = OWX_Verify($master,$hash->{ROM_ID});
  $hash->{PRESENT} = $value;
  if( $value == 0 ){
    readingsSingleUpdate($hash,"state","not present",1); 
  } else {
    readingsSingleUpdate($hash,"state","present",1); 
  }
}

#######################################################################################
#
# OWID_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWID_Set($@) {
  my ($hash, @a) = @_;
  
  my $key     = $a[1];
  my $value   = $a[2];
  
  #-- for the selector: which values are possible
  if (@a == 2){
    my $newkeys = join(" ", keys %sets);
    return $newkeys ;    
  }
  
  #-- check syntax
  return "OWID: Set needs at least one parameter"
    if( int(@a)<3 );
  #-- check argument
  if( !defined($sets{$a[1]}) ){
        return "OWID: Set with unknown argument $a[1]";
  }
  
  my $name    = $hash->{NAME};
  
  #-- set new timer interval
  if($key eq "interval") {
    # check value
    return "OWID: Set with short interval, must be > 1"
      if(int($value) < 1);
    # update timer
    $hash->{INTERVAL} = $value;
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OWID_GetValues", $hash, 1);
    return undef;
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
        <p>FHEM module for 1-Wire devices that know only their unique ROM ID<br />
            <br />This 1-Wire module works with the OWX interface module or with the OWServer interface module
            Please define an <a href="#OWX">OWX</a> device or <a href="#OWServer">OWServer</a> device first. <br /></p>
        <br /><h4>Example</h4><br />
        <p>
            <code>define ROM1 OWX_ID OWCOUNT 09.CE780F000000 10</code>
            <br />
        </p><br />
        <a name="OWIDdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWID &lt;fam&gt; &lt;id&gt; [&lt;interval&gt;]</code> or <br/>
            <code>define &lt;name&gt; OWID &lt;fam&gt;.&lt;id&gt; [&lt;interval&gt;]</code>
            <br /><br /> Define a 1-Wire device.<br /><br />
        </p>
        <ul>
            <li>
                <code>&lt;fam&gt;</code>
                <br />2-character unique family id, see above 
            </li>
            <li>
                <code>&lt;id&gt;</code>
                <br />12-character unique ROM id of the converter device without family id and CRC
                code 
            </li>
            <li>
                <code>&lt;interval&gt;</code>
                <br />Interval in seconds for checking the presence of the device. The default is 300 seconds. </li>
        </ul>
         <br />
        <a name="OWIDset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owid_interval">
                    <code>set &lt;name&gt; interval &lt;int&gt;</code></a><br />
                    Interval in seconds for checking the presence of the device. The default is 300 seconds. </li>
        </ul>
        <br />
        <a name="OWIDget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owid_id">
                    <code>get &lt;name&gt; id</code></a>
                <br /> Returns the full 1-Wire device id OW_FAMILY.ROM_ID.CRC </li>
            <li><a name="owid_present">
                    <code>get &lt;name&gt; present</code>
                </a>
                <br /> Returns 1 if this 1-Wire device is present, otherwise 0. </li>
        </ul>
        
=end html
=cut
