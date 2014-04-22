#################################################################################
# 42_RFXMETER.pm
# Modul for FHEM to decode RFXMETER messages
#
# This code is derived from http://www.xpl-perl.org.uk/.
# Thanks a lot to Mark Hindess who wrote xPL.
#
# Special thanks to RFXCOM, http://www.rfxcom.com/, for their
# help. I own an USB-RFXCOM-Receiver (433.92MHz, USB, order code 80002)
# and highly recommend it.
#
# (c) 2010-2014 Copyright: Willi Herzig (Willi.Herzig@gmail.com)
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##################################
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id$
package main;

use strict;
use warnings;

my $time_old = 0;

sub
RFXMETER_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^30.*";
  $hash->{DefFn}     = "RFXMETER_Define";
  $hash->{UndefFn}   = "RFXMETER_Undef";
  $hash->{ParseFn}   = "RFXMETER_Parse";
  $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
RFXMETER_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  #return "wrong syntax: define <name> RFXMETER code " if(int(@a) != 3);
  return "wrong syntax: define <name> RFXMETER code [<scalefactor>] [<unitname>]" 
    if(int(@a) < 3 || int(@a) > 5);	

  my $name = $a[0];
  my $code = $a[2];

  $hash->{scalefactor} = ((int(@a) > 3) ? $a[3] : 0.001);
  $hash->{unitname} = ((int(@a) > 4) ? $a[4] : "kwh");

  $hash->{CODE} = $code;
  #$modules{RFXMETER}{defptr}{$name} = $hash;
  $modules{RFXMETER}{defptr}{$code} = $hash;
  AssignIoPort($hash);

  return undef;
}

#########################################
# From xpl-perl/lib/xPL/Util.pm:
sub RFXMETER_hi_nibble {
  ($_[0]&0xf0)>>4;
}
sub RFXMETER_lo_nibble {
  $_[0]&0xf;
}
sub RFXMETER_nibble_sum {
  my $c = $_[0];
  my $s = 0;
  foreach (0..$_[0]-1) {
    $s += RFXMETER_hi_nibble($_[1]->[$_]);
    $s += RFXMETER_lo_nibble($_[1]->[$_]);
  }
  $s += RFXMETER_hi_nibble($_[1]->[$_[0]]) if (int($_[0]) != $_[0]);
  return $s;
}
#####################################
sub
RFXMETER_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{RFXMETER}{defptr}{$name});
  return undef;
}

#my $DOT = q{.};
# Important: change it to _, because FHEM uses regexp
my $DOT = q{_};

sub parse_RFXmeter {
  my $bytes = shift;

  #($bytes->[0] == ($bytes->[1]^0xf0)) or return;
  if ( ($bytes->[0] + ($bytes->[1]^0xf)) != 0xff) {
    #Log 1, "RFXMETER: check1 failed";
    return;
  }

  #my $device = sprintf "%02x%02x", $bytes->[0], $bytes->[1];
  my $device = sprintf "%02x", $bytes->[0];
  Log 4, "RFXMETER: device=$device";

  my $type = RFXMETER_hi_nibble($bytes->[5]);
  #Log 1, "RFXMETER: type=$type";

  my $check = RFXMETER_lo_nibble($bytes->[5]);
  #Log 1, "RFXMETER: check=$check";

  my $nibble_sum = RFXMETER_nibble_sum(5.5, $bytes);
  my $parity = 0xf^($nibble_sum&0xf);
  unless ($parity == $check) {
    #warn "RFXMeter parity error $parity != $check\n";
    return "";
  }
  my $time =
    { 0x01 => '30s',
      0x02 => '1m',
      0x04 => '5m',
      0x08 => '10m',
      0x10 => '15m',
      0x20 => '30m',
      0x40 => '45m',
      0x80 => '60m',
    };
  my $type_str =
      [
       'normal data packet',
       'new interval time set',
       'calibrate value',
       'new address set',
       'counter value reset to zero',
       'set 1st digit of counter value integer part',
       'set 2nd digit of counter value integer part',
       'set 3rd digit of counter value integer part',
       'set 4th digit of counter value integer part',
       'set 5th digit of counter value integer part',
       'set 6th digit of counter value integer part',
       'counter value set',
       'set interval mode within 5 seconds',
       'calibration mode within 5 seconds',
       'set address mode within 5 seconds',
       'identification packet',
      ]->[$type];
  unless ($type == 0) {
    warn "Unsupported rfxmeter message $type_str\n";
    return "";
  }
  #my $kwh = ( ($bytes->[4]<<16) + ($bytes->[2]<<8) + ($bytes->[3]) ) / 100;
  #Log 1, "RFXMETER: kwh=$kwh";
  my $current = ($bytes->[4] << 16)  + ($bytes->[2] << 8)  + ($bytes->[3]);
  Log 4, "RFXMETER: current=$current";

  my $device_name = "RFXMeter".$DOT.$device;
  Log 4, "device_name=$device_name";

  #my $def = $modules{RFXMETER}{defptr}{"$device_name"};
  my $def = $modules{RFXMETER}{defptr}{"$device"};
  if(!$def) {
        Log 3, "RFXMETER: Unknown device $device_name, please define it";
        return "UNDEFINED $device_name RFXMETER $device";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  #Log 1, "name=$new_name";
  return "" if(IsIgnored($name));

  my $n = 0;
  my $tm = TimeNow();
  my $val = "";

  my $hash = $def;
  if (defined($hash->{scalefactor})) {
     $current = $current * $hash->{scalefactor};
     #Log 1, "scalefactor=$hash->{scalefactor}, current=$current";
  }
  my $unitname = "kwh";
  if (defined($hash->{unitname})) {
     $unitname = $hash->{unitname}; 
     #Log 1, "unitname=$hash->{unitname}, current=$current";
  }
 
  my $sensor = "meter";
  $val .= "CNT: " . $current;
  $def->{READINGS}{$sensor}{TIME} = $tm;
  $def->{READINGS}{$sensor}{VAL} = $current . " " . $unitname;
  $def->{CHANGED}[$n++] = $sensor . ": " . $current . " " . $unitname;

  $def->{STATE} = $val;
  $def->{TIME} = $tm;
  $def->{CHANGED}[$n++] = $val;

  DoTrigger($name, undef);

  return "";
}

sub
RFXMETER_Parse($$)
{
  my ($hash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "RFXMETER: decoding delay=0 hex=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFXMETER: decoding delay=$time_diff hex=$msg";
  }
  $time_old = $time;

  # convert to binary
  my $bin_msg = pack('H*', $msg);

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($bin_msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $bits = ord($bin_msg);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }
  Log 4, "RFXMETER: bits=$bits num_bytes=$num_bytes hex=$msg";

  my @res = "";
  if ($bits == 48) {
	@res = parse_RFXmeter(\@rfxcom_data_array);
	#parse_RFXmeter(\@rfxcom_data_array);
  } else {
	# this should never happen as this module parses only RFXmeter messages
  	Log 1, "RFXMETER: error unknown hex=$msg";
  }
 
  return @res;
}

1;

=pod
=begin html

<a name="RFXMETER"></a>
<h3>RFXMETER</h3>
<ul>
  The RFXMETER module interprets RFXCOM RFXMeter messages received by a RFXCOM receiver. You need to define an RFXCOM receiver first.
  See the <a href="#RFXCOM">RFXCOM</a>.

  <br><br>

  <a name="RFXMETERdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFXMETER &lt;deviceid&gt; [&lt;scalefactor&gt;] [&lt;unitname&gt;]</code> <br>
    <br>
    &lt;deviceid&gt; is the device identifier of the RFXMeter sensor and is a one byte hexstring (00-ff).
    <br>
    &lt;scalefactor&gt; is an optional scaling factor. It is multiplied to the value that is received from the RFXmeter sensor.
    <br>
    &lt;unitname&gt; is an optional string that describes the value units. It is added to the Reading generated to describe the values.
    <br><br>
      Example: <br>
    <code>define RFXWater RFXMETER 00 0.5 ltr</code>
      <br>
    <code>define RFXPower RFXMETER 01 0.001 kwh</code>
      <br>
    <code>define RFXGas RFXMETER 02 0.01 cu_m</code>
      <br>
  </ul>
  <br>

  <a name="RFXMETERset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="RFXMETERget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="RFXMETERattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
  </ul>
</ul>

=end html
=cut
