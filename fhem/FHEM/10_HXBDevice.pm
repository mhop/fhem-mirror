# $Id$
##############################################################################
#
#     10_HXBDevice.pm
#     Copyright 2014 by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

# Debian: libdigest-crc-perl

package main;

use strict;
use warnings;

use Digest::CRC;

#############################


my %HXB_PTYPES= (
  	HXB_PTYPE_ERROR   => 0x00, # An error occured -- check the error code field for more information
	HXB_PTYPE_INFO    => 0x01, # Endpoint provides information
	HXB_PTYPE_QUERY   => 0x02, # Endpoint is requested to provide information
	HXB_PTYPE_WRITE   => 0x04, # Endpoint is requested to set its value
	HXB_PTYPE_EPINFO  => 0x09, # Endpoint metadata
	HXB_PTYPE_EPQUERY => 0x0A, # Request endpoint metadata
);

#print Dumper \%HXB_PTYPES;
my %HXB_PTYPES_r = reverse %HXB_PTYPES;

my %HXB_DTYPES= (
	HXB_DTYPE_UNDEFINED => 0x00, # Undefined: Nonexistent data type
	HXB_DTYPE_BOOL      => 0x01, # Boolean. Value still represented by 8 bits, but may only be HXB_TRUE or HXB_FALSE
	HXB_DTYPE_UINT8     => 0x02, # Unsigned 8 bit integer
	HXB_DTYPE_UINT32    => 0x03, # Unsigned 32 bit integer
	HXB_DTYPE_DATETIME  => 0x04, # Date and time
	HXB_DTYPE_FLOAT     => 0x05, # 32bit floating point
	HXB_DTYPE_128STRING => 0x06, # 128char fixed length string
	HXB_DTYPE_TIMESTAMP => 0x07, # timestamp - used for measuring durations, time differences and so on - uint32; seconds
	HXB_DTYPE_65BYTES   => 0x08, # raw 65 byte array, e.g. state machine data.
	HXB_DTYPE_16BYTES   => 0x09, # raw 16 byte array, e.g. state machine ID.
);
my %HXB_DTYPES_r = reverse %HXB_DTYPES;

my %HXB_FLAGS= (
	HXB_FLAG_NONE => 0x00, # No flags set
);
my %HXB_FLAGS_r = reverse %HXB_FLAGS;

my %EP= (
	EP_DEVICE_DESCRIPTOR => 0,                                                   
	EP_POWER_SWITCH => 1,                                                        
	EP_POWER_METER => 2,                                                         
	EP_TEMPERATURE => 3,                                                         
	EP_BUTTON => 4,                                                              
	EP_HUMIDITY => 5,                                                            
	EP_PRESSURE => 6,                                                            
	EP_ENERGY_METER_TOTAL => 7,                                                  
	EP_ENERGY_METER => 8,                                                        
	EP_SM_CONTROL => 9,                                                          
	EP_SM_UP_RECEIVER => 10,                                                     
	EP_SM_UP_ACKNAK => 11,                                                       
	EP_SM_RESET_ID => 12,                                                        
	EP_ANALOGREAD => 22,                                                         
	EP_SHUTTER => 23,                                                            
	EP_HEXAPUSH_PRESSED => 24,                                                   
	EP_HEXAPUSH_CLICKED => 25,                                                   
	EP_PRESENCE_DETECTOR => 26,                                                  
	EP_HEXONOFF_SET => 27,                                                       
	EP_HEXONOFF_TOGGLE => 28,                                                    
	EP_LIGHTSENSOR => 29,                                                        
	EP_IR_RECEIVER => 30,                                                        
	EP_LIVENESS => 31,                                                           
	EP_EXT_DEV_DESC_1 => 32,                                                     
	EP_GENERIC_DIAL_0 => 33,                                                     
	EP_GENERIC_DIAL_1 => 34,                                                     
	EP_GENERIC_DIAL_2 => 35,
	EP_GENERIC_DIAL_3 => 36,
	EP_GENERIC_DIAL_4 => 37,
	EP_GENERIC_DIAL_5 => 38,
	EP_GENERIC_DIAL_6 => 39,
	EP_GENERIC_DIAL_7 => 40,
	EP_PV_PRODUCTION => 41,
	EP_POWER_BALANCE => 42,
	EP_BATTERY_BALANCE => 43,
	EP_HEATER_HOT => 44,
	EP_HEATER_COLD => 45,
	EP_HEXASENSE_BUTTON_STATE => 46,
	EP_FLUKSO_L1 => 47,
	EP_FLUKSO_L2 => 48,
	EP_FLUKSO_L3 => 49,
	EP_FLUKSO_S01 => 50,
	EP_FLUKSO_S02 => 51,
	EP_GL_IMPORT_L1 => 52,
	EP_GL_IMPORT_L2 => 53,
	EP_GL_IMPORT_L3 => 54,
	EP_GL_EXPORT_POWER => 55,
	EP_GL_EXPORT_L1 => 56,
	EP_GL_EXPORT_L2 => 57,
	EP_GL_EXPORT_L3 => 58,
	EP_GL_IMPORT_ENERGY => 59,
	EP_GL_EXPORT_ENERGY => 60,
	EP_GL_FIRMWARE => 61,
	EP_GL_CURRENT_L1 => 62,
	EP_GL_CURRENT_L2 => 63,
	EP_GL_CURRENT_L3 => 65,
	EP_GL_VOLTAGE_L1 => 66,
	EP_GL_VOLTAGE_L2 => 67,
	EP_GL_VOLTAGE_L3 => 68,
	EP_GL_POWER_FACTOR_L1 => 69,
	EP_GL_POWER_FACTOR_L2 => 70,
	EP_GL_POWER_FACTOR_L3 => 71,
	EP_METERING_RMS_CURRENT => 72,
	EP_METERING_RMS_VOLTAGE => 73,
	EP_METERING_FREQUENCY => 74,
	EP_METERING_REACTIVE_POWER => 75,
	EP_METERING_POWER_FACTOR => 76,
	EP_METERING_APPARENT_POWER => 77,
	EP_METERING_FUNDAMENTAL_ACTIVE_POWER => 78,
	EP_METERING_FUNDAMENTAL_REACTIVE_POWER => 79,
	EP_DIMMER_MODE => 80,
	EP_DIMMER_BRIGHTNESS => 81,
);
my %EP_r= reverse %EP;


#############################
sub
HXBDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> HXBDevice <ipv6>"  if($#a != 2);

        my $name= $a[0];
        my $ipv6= $a[2];
        
        $hash->{fhem}{ipv6}= $ipv6;
        AssignIoPort($hash);
        
        my @devarray= ();
        my $devarrayref= $modules{$hash->{TYPE}}{defptr}{"$ipv6"};
        if(defined($devarrayref)) {
	  @devarray= @{$devarrayref};
	}
        push @devarray, $hash;
        $modules{$hash->{TYPE}}{defptr}{"$ipv6"}= \@devarray;
       
        return undef;
        
        # Todo: HXBDevice_Undefine
}

###################################
sub
HXBDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "HX0C.+"; 
  
  #$hash->{GetFn}     = "HXBDevice_Get";
  #$hash->{SetFn}     = "HXBDevice_Set";
  $hash->{DefFn}     = "HXBDevice_Define";
  $hash->{ParseFn}   = "HXBDevice_Parse";

  #$hash->{AttrFn}    = "HXBDevice_Attr";
  $hash->{AttrList}  =  $readingFnAttributes;
}

#####################################

sub
crc16Kermit($) {
  my ($raw)= @_;
  my $ctx= Digest::CRC->new(width=>16, init=>0x0000, xorout=>0x0000, 
                          refout=>1, poly=>0x1021, refin=>1, cont=>1);
  $ctx->add($raw);
  return $ctx->digest;
}

#############################
sub
HXBDevice_Parse($$)
{

  # we never come here if $msg does not match $IOhash->{MATCH} in the first place

  my ($IOhash, $data) = @_;        # IOhash points to the HXB, not to the HXBDevice

  my $socket= $IOhash->{TCPDev};
  my $ipv6= $socket->peerhost;
  
  my $hash;
  
  # array of device hash with that IPv6 address
  my @devices= ();

  # matching devices
  my @devarray= ();
  my $devarrayref= $modules{"HXBDevice"}{defptr}{"$ipv6"};
  if(defined($devarrayref)) {
    @devarray= @{$devarrayref};
  }
  return "UNDEFINED HXB_$ipv6 HXBDevice $ipv6" if($#devarray< 0);
  
  foreach $hash (@devarray) {
    
    my $n= length($data);
    return undef if($n< 8);
    
    my ($magic, $ptype, $flags, $payload, $crc)= unpack("A4CCa" . ($n-8) . "n", $data);
    my $raw= unpack("a" . ($n-2), $data);
    return undef unless($crc = crc16Kermit($raw));
    my $hxb_ptype= $HXB_PTYPES_r{$ptype};
    my $hxb_flag= $HXB_FLAGS_r{$flags};
    if($hxb_ptype eq "HXB_PTYPE_INFO") {
      my ($eid, $dtype, $value)= unpack("NCa*", $payload);
      my $ep= $EP_r{$eid};
      my $hxb_dtype= $HXB_DTYPES_r{$dtype};
      my $v= "<unknown>";
      if($hxb_dtype eq "HXB_DTYPE_BOOL") {
	  $v= unpack("b", $value);
      } elsif($hxb_dtype eq "HXB_DTYPE_UINT8") {
	  $v= unpack("C", $value);
      } elsif($hxb_dtype eq "HXB_DTYPE_UINT32") {
	  $v= unpack("N", $value);
      } elsif($hxb_dtype eq "HXB_DTYPE_DATETIME") {
	  $v= "?";
      } elsif($hxb_dtype eq "HXB_DTYPE_FLOAT") {
	  #Debug unpack "V", $value;
	  $v= unpack "f", pack "N", unpack "V", $value; #unpack("f", $value);
      } elsif($hxb_dtype eq "HXB_DTYPE_128STRING") {
	  $v= "?";
      } elsif($hxb_dtype eq "HXB_DTYPE_TIMESTAMP") {
	  $v= "?";
      } elsif($hxb_dtype eq "HXB_DTYPE_65BYTES") {
	  $v= "?";
      } elsif($hxb_dtype eq "HXB_DTYPE_16BYTES") {
	  $v= "?";
      }
      Log3 $hash,5, sprintf("%s: %s %s %s %s %s= %s", 
	$hash->{NAME}, $hxb_ptype, $hxb_flag, 
	$ep, $hxb_dtype, unpack("H*", $value), $v);
  
      my $fmtDateTime= readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "state", $fmtDateTime, 1); # we do not want an extra event for state
      readingsBulkUpdate($hash, $ep, $v, 1);
      readingsEndUpdate($hash, 1);
      
      push @devices, $hash->{NAME};
    }
     
  }
  return @devices;
  
}

#############################
1;
#############################

=pod
=item summary    receive multicast messages from a Hexabus device
=item summary_DE empfange Multicast-Nachrichten von einem Hexabus-Ger&auml;
=begin html

<a name="HXBDevice"></a>
<h3>HXBDevice</h3>
<ul>
  <br>

  <a name="HXB"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HXB &lt;IPv6Address&gt;</code><br>
    <br>
    Defines a Hexabus device at the IPv6 address &lt;IPv6Address&gt;. You need one <a href="#HXB">Hexabus</a>
    to receive multicast messages from Hexabus devices.
    Have a look at the <a href="https://github.com/mysmartgrid/hexabus/wiki">Hexabus wiki</a> for more information on Hexabus.
    <br><br>
    Example:
    <code>define myPlug fd01:1::50:c4ff:fe04:81ad</code>
  </ul>  

</ul>


=end html
