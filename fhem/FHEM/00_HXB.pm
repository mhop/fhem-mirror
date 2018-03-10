# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2014 Copyright: Dr. Boris Neubert
#  e-mail: omega at online dot de
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
################################################################################

package main;

use strict;
use warnings;

use IO::Socket::Multicast6;

#####################################
sub
HXB_Initialize($)
{
  my ($hash) = @_;
  
  my %matchlist= (
    "1:HXBDevice" => "^HX0C.+",
  );

# Provider
  #$hash->{WriteFn} = "HXB_Write";
  $hash->{ReadFn}  = "HXB_Read";
  $hash->{Clients} = ":HXBDevice:";
  $hash->{MatchList} = \%matchlist;
  #$hash->{ReadyFn} = "HXB_Ready";

# Consumer
  $hash->{DefFn}   = "HXB_Define";
  $hash->{UndefFn} = "HXB_Undef";
  #$hash->{ReadyFn} = "HXB_Ready";
  #$hash->{GetFn}   = "HXB_Get";
  #$hash->{SetFn}   = "HXB_Set";
  #$hash->{AttrFn}  = "HXB_Attr";
  #$hash->{AttrList}= "";
}

#####################################
sub
HXB_Define($$)
{
  my ($hash, $def) = @_;
  my $name= $hash->{NAME};

  Log3 $hash, 3, "$name: Opening multicast socket...";
  my $socket = IO::Socket::Multicast6->new(
    Domain    => AF_INET6,
    Proto     => 'udp',
    LocalPort => '61616',
  );
  $socket->mcast_add('FF05::205');
  
  $hash->{TCPDev}= $socket;
  $hash->{FD} = $socket->fileno();
  delete($readyfnlist{"$name"});
  $selectlist{"$name"} = $hash;

  return undef;
}


#####################################
sub
HXB_Undef($$)
{
  my ($hash, $arg) = @_;
  
  my $socket= $hash->{TCPDev};
  $socket->mcast_drop('FF05::205');
  $socket->close;

  return undef;
}

#####################################
sub
HXB_DoInit($)
{
  my $hash = shift;
 
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub HXB_Read($) 
{
  my ($hash) = @_;
  my $name= $hash->{NAME};
  my $socket= $hash->{TCPDev};
  my $data;
  return unless $socket->recv($data, 128);
  
  Log3 $hash, 5, "$name: Received " . length($data) . " bytes.";
  Dispatch($hash, $data, undef);  # dispatch result to HXBDevices
}


#############################
1;
#############################


=pod
=item summary    receive multicast messages from Hexabus devices
=item summary_DE empfange Multicast-Nachrichten von Hexabus-Ger&auml;ten
=begin html

<a name="HXB"></a>
<h3>HXB</h3>
<ul>
  <br>

  <a name="HXB"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HXB</code><br>
    <br>
    Defines a Hexabus. You need one Hexabus to receive multicast messages from <a href="#HXBDevice">Hexabus devices</a>.
    Have a look at the <a href="https://github.com/mysmartgrid/hexabus/wiki">Hexabus wiki</a> for more information on Hexabus.
    <br><br>
    You need the perl modules IO::Socket::Multicast6 and Digest::CRC. Under Debian and its derivatives they are installed with <code>apt-get install libio-socket-multicast6-perl libdigest-crc-perl</code>.
  </ul>  

</ul>


=end html
