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
# Willi Herzig, 2010
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
package main;

use strict;
use warnings;
use Switch;

my $time_old = 0;

sub
RFXMETER_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^0.*";
  $hash->{DefFn}     = "RFXMETER_Define";
  $hash->{UndefFn}   = "RFXMETER_Undef";
  $hash->{ParseFn}   = "RFXMETER_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

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

  my $type = hi_nibble($bytes->[5]);
  #Log 1, "RFXMETER: type=$type";

  my $check = lo_nibble($bytes->[5]);
  #Log 1, "RFXMETER: check=$check";

  my $nibble_sum = nibble_sum(5.5, $bytes);
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
  my $current = ($bytes->[4]<<16) + ($bytes->[2]<<8) + ($bytes->[3]) ;
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
  my $hexline = unpack('H*', $msg);
  if ($time_old ==0) {
  	Log 5, "RFXMETER: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFXMETER: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $bits = ord($msg);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }
  Log 4, "RFXMETER: bits=$bits num_bytes=$num_bytes hex=$hexline";

  my @res = "";
  if ($bits == 48) {
	@res = parse_RFXmeter(\@rfxcom_data_array);
	#parse_RFXmeter(\@rfxcom_data_array);
  } else {
	# this should never happen as this module parses only RFXmeter messages
  	my $hexline = unpack('H*', $msg);
  	Log 1, "RFXMETER: error unknown hex=$hexline";
  }
 
  return @res;
}

1;
