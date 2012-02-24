#################################################################################
# 46_TRX_ELSE.pm
# Modul for FHEM for unkown RFXTRX messages
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
# $Id: 
package main;

use strict;
use warnings;
use Switch;

my $time_old = 0;

sub
TRX_ELSE_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^.*";
  $hash->{DefFn}     = "TRX_ELSE_Define";
  $hash->{UndefFn}   = "TRX_ELSE_Undef";
  $hash->{ParseFn}   = "TRX_ELSE_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";
Log 1, "TRX_ELSE: Initialize";

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

  $hash->{CODE} = $code;
  #$modules{TRX_ELSE}{defptr}{$name} = $hash;
  $modules{TRX_ELSE}{defptr}{$code} = $hash;
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


my $DOT = q{_};

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
  #my $hexline = unpack('H*', $bin_msg);
  #Log 1, "TRX_ELSE: 2 hex=$hexline";

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($bin_msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  Log 0, "TRX_ELSE: hex=$msg";

  return "Test";
}

1;
