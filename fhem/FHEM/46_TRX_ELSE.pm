#################################################################################
# 46_TRX_ELSE.pm
#
# FHEM module unkown RFXtrx433 messages
#
# Copyright (C) 2012 Willi Herzig
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
###################################
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id$ 
package main;

use strict;
use warnings;

# Debug this module? YES = 1, NO = 0
my $TRX_ELSE_debug = 0;

my $time_old = 0;

my $DOT = q{_};

sub
TRX_ELSE_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^...*";
  $hash->{DefFn}     = "TRX_ELSE_Define";
  $hash->{UndefFn}   = "TRX_ELSE_Undef";
  $hash->{ParseFn}   = "TRX_ELSE_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

  Log 1, "TRX_ELSE: Initialize" if ($TRX_ELSE_debug == 1);
}

#####################################
sub
TRX_ELSE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> TRX_ELSE code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];

  my $device_name = "TRX_UNKNOWN".$DOT.$code;

  $hash->{TRX_LIGHT_CODE} = $code;
  $modules{TRX_ELSE}{defptr}{$device_name} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
TRX_ELSE_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{TRX_ELSE}{defptr}{$name});
  return undef;
}

sub
TRX_ELSE_Parse($$)
{
  my ($hash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "TRX_ELSE: decoding delay=0 hex=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "TRX_ELSE: decoding delay=$time_diff hex=$msg";
  }
  $time_old = $time;

  # convert to binary
  my $bin_msg = pack('H*', $msg);
  #Log 1, "TRX_ELSE: 2 hex=$hexline";

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($bin_msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $num_bytes = ord(substr($msg,0,1));

  if ($num_bytes < 3) {
    return;
  }

  my $type = $rfxcom_data_array[0];

  Log 1, "TRX_ELSE: num_bytes=$num_bytes hex=$msg type=$type" if ($TRX_ELSE_debug == 1);
  my $res = "";
  if ($type == 0x02) {
	my $subtype = $rfxcom_data_array[1];
	my $msg = $rfxcom_data_array[2];
	if (($msg != 0x00) && ($msg != 0x01)) {
  		Log 0, "TRX_ELSE: error transmit NACK=".sprintf("%02x",$msg);
	} 
  	return "";
  } 
  #Log 0, "TRX_ELSE: hex=$msg";

  my $type_hex = sprintf("%02x", $type);

  my $device_name = "TRX".$DOT."UNKNOWN".$DOT.$type_hex;

  my $def = $modules{TRX_ELSE}{defptr}{$device_name};
  if (!$def) {
	Log 1, "UNDEFINED $device_name TRX_ELSE $type_hex";
        Log 3, "TRX_ELSE: TRX_ELSE Unknown device $device_name, please define it";
       	return "UNDEFINED $device_name TRX_ELSE $type_hex";
  }

  readingsBeginUpdate($def);

  #my $sensor = "hexline";
  my $current = $msg;
  #readingsBulkUpdate($def, $sensor, $current);

  readingsBulkUpdate($def, "state", $current);


  readingsEndUpdate($def, 1);

  return "";
}

1;

=pod
=begin html

<a name="TRX_ELSE"></a>
<h3>TRX_ELSE</h3>
<ul>
  The TRX_ELSE module is invoked by TRX if a code is received by RFXCOM RFXtrx433 RF receiver that is currently not handled by a TRX_-Module. You need to define an RFXtrx433 receiver first. 
See <a href="#TRX">TRX</a>.
  <br>
  <a name="TRX_SECURITYdefine"></a>
  <br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TRX_ELSE &lt;hextype&gt;</code> <br>
    <br>
    <code>&lt;hextype&gt;</code>
    <ul>
      specifies the hexvalue (00 - ff) of the type received by the RFXtrx433 transceiver. <br>
    </ul>
    <br>
      Example: <br>
    	<code>define TRX_UNKNOWN_9A TRX_ELSE 9A</code>
      <br>
  </ul>
  <br>
</ul>

=end html
=cut
