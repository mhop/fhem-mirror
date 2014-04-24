################################################################################
# 10_Itach_IR
# $Id$
#
################################################################################
#
#  Copyright notice
#
#  (c) 2014 Copyright: Ulrich Maass
#
#  This file is part of fhem.
# 
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
# 
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#  Disclaimer: The Author takes no responsibility whatsoever 
#  for damages potentially done by this program.
#
################################################################################
#
# This module serves as communication layer for 88_Itach_IRDevice
#
################################################################################

package main;
use strict;
use warnings;
use IO::Socket::INET;

#########################
# Forward declaration
sub IIR_Define();
sub IIR_Send($$);
sub IIR_Write($@);


#####################################
# Initialize module
sub
Itach_IR_Initialize($)
{
  my ($hash) = @_;
  # provider
#  $hash->{ReadFn}   = "IIR_Write";
  $hash->{WriteFn}  = "IIR_Write";
  $hash->{Clients}  = ":Itach_IRDevice:";
  #consumer
  $hash->{DefFn}    = "IIR_Define";
  $hash->{AttrList} = "verbose:0,1,2,3,4,5,6 timeout";
}


#####################################
# Initialize every new instance
sub
IIR_Define() 
{
  my ($hash, $def) = @_;
  my @args = split("[ \t]+", $def);
  return "Usage: define <name> Itach_IR <host>"  if($#args != 2);
  
  my ($name, $type, $host) = @args;
  $hash->{STATE}       = "Initialized";
  $hash->{IPADR}       = $host if ($host);  #format-check required
  my $cmdret= CommandAttr(undef,"$name room ItachIR") if (!AttrVal($name,'room',undef));
  return undef;
}


#####################################
# Execute IOWrite-calls from clients
sub IIR_Write($@) {
  my ($hash,$name,$cmd,$IRcode)= @_;
  Log3 $name, 5, "IIR_Write called with $name,$cmd";
  my $newstate = $name.':'.$cmd;
  readingsSingleUpdate($hash,"lastcommand",$newstate,0);
  my $ret=IIR_Send($hash,$IRcode);
  return undef;
}

#####################################
# Send IR-code
sub
IIR_Send($$){
  my ($hash,$IR)=@_;
  if (!$IR) {
	Log3 $hash->{NAME}, 2, "Called without IR-code to send.";
	return;
  }
  my $socket = new IO::Socket::INET (
     PeerHost => $hash->{IPADR},
     PeerPort => '4998',
     Proto    => 'tcp',
     Timeout  => AttrVal($hash->{NAME},'timeout','2.0'),
  );
  # send Itach command
  if ($socket) {
    my @codes = split(';',$IR);
	foreach my $IRcode (@codes) {
      my $data = $IRcode."\r\n";
      $socket->send($data);
      select(undef, undef, undef, 0.3); #pause 0.3 seconds
	  Log3 $hash->{NAME}, 5, 'Sent to '.$hash->{IPADR}.' : '.$IRcode;
	}
	$socket->close();
	readingsSingleUpdate($hash,"state",'Initialized',0) if ($hash->{STATE} ne 'Initialized');
  } else {
	Log3 $hash->{NAME}, 1, 'Could not open socket with '.$hash->{IPADR}.' : '.$@;
	readingsSingleUpdate($hash,"state",$@,0);
  }
  return undef;
}

1;


=pod
=begin html

<a name="Itach_IR"></a>
<h3>Itach_IR</h3>
<ul>
  Defines a device representing a physical Itach IR. Serves as communication layer for <a href="#Itach_IRDevice">Itach_IRDevice</a>.<br>
  For more information, check the <a href="http://www.fhemwiki.de/wiki/ITach">Wiki page</a>.<br>
  
  <a name="Itach_IRdefine"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Itach_IR &lt;IP-address&gt;</code><br>
	Example:<br>
    <code>define Itach Itach_IR 192.168.1.2</code>
  </ul>

  <a name="Itach_IRset"></a><br>
  <b>Set</b><br><ul>N/A</ul><br>

  <a name="Itach_IRDeviceget"></a><br>
  <b>Get</b><br><ul>N/A</ul><br>

  <a name="Itach_IRDeviceattr"></a><br>
  <b>Attributes</b>
  <ul>
    <li><a href="#verbose">verbose</a></li>
	<li>timeout<br>
	Can be used to change the timeout-value for tcp-communication. Default is 2.0.</li>
  </ul>
</ul>

=end html
=cut


