##############################################################################
#
#     70_CanOverEthernet.pm
#
#     This file is part of Fhem.
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
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#
# CanOverEthernet (c) Martin Gutenbrunner / https://github.com/delmar43/FHEM
#
# This module is designed to work as a physical device in connection with 71_COE_Node
# as a logical device.
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,96170.0.html
#
# $Id$
#
##############################################################################
package main;

use strict;
use warnings;
use IO::Socket;
use DevIo;

sub CanOverEthernet_Initialize($) {
  my ($hash) = @_;

#  require "$attr{global}{modpath}/FHEM/DevIo.pm";
   
  $hash->{GetFn}     = "CanOverEthernet_Get";
  $hash->{SetFn}     = "CanOverEthernet_Set";
  $hash->{DefFn}     = "CanOverEthernet_Define";
  $hash->{UndefFn}   = "CanOverEthernet_Undef";
  $hash->{ReadFn}    = "CanOverEthernet_Read";

  $hash->{AttrList} = $readingFnAttributes;
  $hash->{MatchList} = { "1:COE_Node" => "^.*" };
  $hash->{Clients} = "COE_Node";

  Log3 '', 3, "CanOverEthernet - Initialize done ...";
}

sub CanOverEthernet_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
 
  my $name   = $a[0];
  my $module = $a[1];
 
  if(@a < 2 || @a > 2) {
     my $msg = "CanOverEthernet ($name) - Wrong syntax: define <name> CanOverEthernet";
     Log3 undef, 1, $msg;
     return $msg;
  }

  DevIo_CloseDev($hash);

  $hash->{NAME} = $name;
  
  Log3 $name, 3, "CanOverEthernet ($name) - Define done ... module=$module";

  my $portno = 5441;
  my $conn = IO::Socket::INET->new(Proto=>"udp",LocalPort=>$portno);
 
  $hash->{FD}    = $conn->fileno();
  $hash->{CD}    = $conn;         # sysread / close won't work on fileno
  $selectlist{$name} = $hash;
 
  Log3 $name, 3, "CanOverEthernet ($name) - Awaiting UDP connections on port $portno\n";

  readingsSingleUpdate($hash, 'state', 'defined', 1);

  return undef;
}

sub CanOverEthernet_Undef($$) {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  DevIo_CloseDev($hash);

  return undef;
}

sub CanOverEthernet_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf;
  my $data;

  $hash->{STATE} = 'Last: '.gmtime();
  $hash->{CD}->recv($buf, 16);
  $data = unpack('H*', $buf);
  Log3 $name, 5, "CanOverEthernet ($name) - Client said $data";

  Dispatch($hash, $buf);

}

sub CanOverEthernet_Get ($@) {
  my ( $hash, $param ) = @_;

  my $name = $hash->{NAME};
  Log3 $name, 5, "CanOverEthernet ($name) - Get done ...";
  return undef;
}

sub CanOverEthernet_Set ($@)
{
  my ( $hash, $name, $cmd, $args ) = @_;

  if ( 'sendData' eq $cmd ) {
    CanOverEthernet_parseSendDataCommand( $hash, $name, $args );
    
  }

  Log3 $name, 5, "CanOverEthernet ($name) - Set done ...";
  return 'sendData';
}

sub CanOverEthernet_parseSendDataCommand {
  my ( $hash, $name, @args ) = @_;

  # args: Target-IP Target-Node Index=Value
  
  my $targetIp = $args[0];
  my $targetNode = $args[1];
  
  my $socket = new IO::Socket::INET (
    PeerAddr=>$targetIp,  #PeerAddr von $sock ist eingegebener Paramenter $ipaddr
    PeerPort=>5441,        #PeerPort von $sock ist eingegebener Paramenter $port
    Proto=>'udp'            #Transportprotokoll: UDP
  );
  
  if ($socket) {

    my $out = pack('CCS<S<S<S<CCCC', $targetNode,5,22.7,0,0,0,1,0,0,0);

    $socket->send($out, 16);
    $socket->close();
    Log3 $name, 4, "CanOverEthernet ($name) - sendData done.";

  } else {
    Log3 $name, 0, "CanOverEthernet ($name) - sendData failed to create network socket";
    return;

  }
  
}

1;

=pod
=item [device]
=item summary CanOverEthernet receives COE UDP broadcasts
=item summary_DE CanOverEthernet empfängt CoE UDP broadcasts

=begin html

<a name="CanOverEthernet"></a>
<h3>CanOverEthernet</h3>

<a name="CanOverEthernetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CanOverEthernet</code>
    <br><br>
    Defines a CanOverEthernet device. FHEM will start listening to UDP broadcast
    on port 5441.
    <br>
    Example:
    <ul>
      <code>define coe CanOverEthernet</code>
    </ul>
    Actual readings for the incoming data will be written to COE_Node devices, which
    are created on-the-fly.    
  </ul>

=end html

=begin html_DE

<a name="CanOverEthernet"></a>
<h3>CanOverEthernet</h3>

<a name="CanOverEthernetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CanOverEthernet</code>
    <br><br>
    Erstellt ein CanOverEthernet device. FHEM empfängt auf Port 5441 UDP broadcast.
    <br>
    Beispiel:
    <ul>
      <code>define coe CanOverEthernet</code>
    </ul>
    Die eingehenden Daten werden als readings in eigenen COE_Node devices gespeichert.
    Diese devices werden automatisch angelegt, sobald Daten dafür empfangen werden.
  </ul>

=end html_DE

=cut
