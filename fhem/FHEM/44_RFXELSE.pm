#################################################################################
# 44_RFXELSE.pm
# Modul for FHEM for unkown RFXCOM messages
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
use Switch;

my $time_old = 0;

sub
RFXELSE_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^.*";
  $hash->{DefFn}     = "RFXELSE_Define";
  $hash->{UndefFn}   = "RFXELSE_Undef";
  $hash->{ParseFn}   = "RFXELSE_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";
Log 1, "RFXELSE: Initialize";

}

#####################################
sub
RFXELSE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> RFXELSE code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];

  $hash->{CODE} = $code;
  #$modules{RFXELSE}{defptr}{$name} = $hash;
  $modules{RFXELSE}{defptr}{$code} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
RFXELSE_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{RFXELSE}{defptr}{$name});
  return undef;
}


my $DOT = q{_};

sub
RFXELSE_Parse($$)
{
  my ($hash, $msg) = @_;

  my $time = time();
  my $hexline = unpack('H*', $msg);
  if ($time_old ==0) {
  	Log 5, "RFXELSE: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFXELSE: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $bits = ord($msg);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }
  Log 0, "RFXELSE: bits=$bits num_bytes=$num_bytes hex=$hexline";

  return "Test";
}

1;
