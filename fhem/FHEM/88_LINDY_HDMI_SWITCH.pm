################################################################
#
#  Copyright notice
#
#  (c) 2013 Sacha Gloor (sacha@imp.ch)
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;

use strict;
use warnings;
use Data::Dumper;
use Net::Telnet;

sub
LINDY_HDMI_SWITCH_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "LINDY_HDMI_SWITCH_Set";
  $hash->{DefFn}     = "LINDY_HDMI_SWITCH_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
LINDY_HDMI_SWITCH_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of 11 12 13 14 21 22 23 24" if($a[1] eq "?");

  my $v = $a[1];

  my $tel=new Net::Telnet(Host => $hash->{Host}, Port => $hash->{Host_Port},Timeout => 3, Binmode => 0, Telnetmode => 0, Errmode => "return");
  if(!defined($tel))
  {
	Log 4,"Error connecting to ".$a[0].":4999";
  }
  else
  {
	my $cmd="PORT ".$v."\n";
	$tel->print($cmd);
	sleep(1);
  }

  Log GetLogLevel($a[0],2), "LINDY_HDMI_SWITCH set @a";

  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;

  DoTrigger($hash->{NAME}, undef);

  return undef;

}

sub
LINDY_HDMI_SWITCH_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $host = $a[2];
  my $host_port = $a[3];

  return "Wrong syntax: use define <name> LINDY_HDMI_SWITCH <ip-address> <port-nr>" if(int(@a) != 4);

  $hash->{Host} = $host;
  $hash->{Host_Port} = $host_port; 
 
  return undef;
}

1;
