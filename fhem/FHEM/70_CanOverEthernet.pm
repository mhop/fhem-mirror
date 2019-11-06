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

  if ( ! defined $conn ) {  
    Log3 $name, 0, "CanOverEthernet ($name) - ERROR: Unable to open port 5441 for reading. Maybe it's opened by another process already?";
    return undef;
  }
 
  $hash->{FD}    = $conn->fileno();
  $hash->{CD}    = $conn;
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
  $hash->{CD}->recv($buf, 14);
  $data = unpack('H*', $buf);
  Log3 $name, 5, "CanOverEthernet ($name) - Client said $data";

  Dispatch($hash, $buf);

}

sub CanOverEthernet_Set ($@)
{
  my ( $hash, $name, $cmd, @args ) = @_;

  if ( 'sendDataAnalog' eq $cmd ) {

    my ( $targetIp, $targetNode, $valuesRef, $typesRef ) = CanOverEthernet_parseAnalog( $hash, $name, @args );
    return CanOverEthernet_sendDataAnalog ( $hash, $targetIp, $targetNode, $valuesRef, $typesRef );

  } elsif ( 'sendDataDigital' eq $cmd ) {

    my ( $targetIp, $targetNode, @values ) = CanOverEthernet_parseDigital( $hash, $name, @args );
    return CanOverEthernet_sendDataDigital ( $hash, $targetIp, $targetNode, @values );
    
  }

  return 'sendDataAnalog sendDataDigital';
}

sub CanOverEthernet_parseDigital {
  my ( $hash, $name, @args ) = @_;

  my $targetIp = $args[0];
  my $targetNode = $args[1];
  my @values = @args[2..$#args];
  my $page;

  for ( my $i=0; $i <= $#values; $i++ ) {
    my ( $index, $value ) = split /[=]/, $values[$i];

    if ( $index < 0 || $index > 32 ) {
      Log3 $name, 0, "CanOverEthernet ($name) - parsing sendDataDigital: index $index is out of bounds [1-32]. Value will not be sent.";
      next;
    }

    $values[$index-1] = $value;
  }

  return ( $targetIp, $targetNode, @values );
}

sub CanOverEthernet_parseAnalog {
  my ( $hash, $name, @args ) = @_;

  # args: Target-IP Target-Node Index=Value;Type
  
  my $targetIp = $args[0];
  my $targetNode = $args[1];
  my @valuesAndTypes = @args[2..$#args];
  my @values;
  my @types;
  my $page;

  for ( my $i=0; $i <= $#valuesAndTypes; $i++ ) {
    my ( $index, $value, $type ) = split /[=;]/, $valuesAndTypes[$i];

    if ( $index < 1 || $index > 32 ) {
      Log3 $name, 0, "CanOverEthernet ($name) - parsing sendDataAnalog: index $index is out of bounds [1-32]. Value will not be sent.";
      next;
    }

    my $pIndex; #index inside of page (eg 18 is pIndex 2 on page 1)

    if ( $index < 5 ) {
      $page = 1;
    } elsif ( $index < 9 ) {
      $page = 2;
    } elsif ( $index < 13 ) {
      $page = 3;
    } elsif ( $index < 17 ) {
      $page = 4;
    } elsif ( $index < 21 ) {
      $page = 5;
    } elsif ( $index < 25 ) {
      $page = 6;
    } elsif ( $index < 29 ) {
      $page = 7;
    } elsif ( $index < 33 ) {
      $page = 8;
    }

    $pIndex = $index - (($page-1)*4) -1;
    $types[$page][$pIndex] = $type;
    $values[$page][$pIndex] = $value;
  }

  return ( $targetIp, $targetNode, \@values, \@types );
}

sub CanOverEthernet_sendDataAnalog {
  my ( $hash, $targetIp, $targetNode, $valuesRef, $typesRef ) = @_;
  my $name = $hash->{NAME};

  my @values = @{$valuesRef};
  my @types = @{$typesRef};

  my $socket = new IO::Socket::INET (
    PeerAddr=>$targetIp,
    PeerPort=>5441,
    Proto=>"udp"
  );
  
  if ( !$socket ) {
    Log3 $name, 0, "CanOverEthernet ($name) - sendDataAnalog failed to create network socket";

    return;
  }

  for ( my $pageIndex=1; $pageIndex <= 4; $pageIndex++ ) {
    my $nrEntries = @{$values[$pageIndex] // []};
    Log3 $name, 5, "CanOverEthernet ($name) - page $pageIndex has $nrEntries entries.";
    if ( $nrEntries == 0 ) {
      next;
    }

    my @pageVals;
    my @pageTypes;
    for ( my $valIndex=0; $valIndex < 4; $valIndex++ ) {
      my $val = $values[$pageIndex][$valIndex];
      my $type = $types[$pageIndex][$valIndex];

      if ( ! defined $val || ! defined $type ) {
        Log3 $name, 4, "CanOverEthernet ($name) - page $pageIndex value $valIndex has no type or no value set. Skipping.";
        next;
      }

      Log3 $name, 4, "CanOverEthernet ($name) - value $valIndex = $values[$pageIndex][$valIndex] type=$types[$pageIndex][$valIndex]";
      $pageVals[$valIndex] = CanOverEthernet_getValue( $name, $val );
      $pageTypes[$valIndex] = ( defined $type ? $type : 0);
    }
    my $out = pack('CCS<S<S<S<CCCC', $targetNode, $pageIndex, @pageVals, @pageTypes);

    $socket->send($out);
  }

  $socket->close();
}

sub CanOverEthernet_sendDataDigital {
  my ( $hash, $targetIp, $targetNode, @values ) = @_;
  my $name = $hash->{NAME};

  my $socket = new IO::Socket::INET (
    PeerAddr=>$targetIp,
    PeerPort=>5441,
    Proto=>"udp"
  );

  if ( !$socket ) {
    Log3 $name, 0, "CanOverEthernet ($name) - sendDataDigital failed to create network socket";

    return;
  }

  # prepare digital values (4 bytes, 32 bits for 32 values)
  my $digiVals = '';
  for (my $idx=0; $idx < 32; $idx++) {

    if(defined($values[$idx])) {
      $digiVals = $digiVals . ($values[$idx] == '1' ? "\001" : "\000");
    } else {
      $digiVals = $digiVals . "\000";
    }
  }

  # pad the rest of the 14 bytes with zeroes
  for (my $idx=32; $idx < 96; $idx++) {
    $digiVals = $digiVals."\000";
  }

  my $out = pack('CCb*', $targetNode, 0, $digiVals);
  $socket->send($out);
  $socket->close();
}

sub CanOverEthernet_getValue {
  my ( $name, $input ) = @_;
  if ( ! defined $input ) {
    return 0;
  }

  #type 1 needs to have 1 decimal place
  #type 13 needs to have 2 decimal places
  #but the value is submitted without the dot

  $input =~ s/\.//;
  return $input;
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

<a name="CanOverEthernetset"><b>Set</b></a>
  <ul>
    <li><a href="#sendDataAnalog">sendDataAnalog</a><br>Sends analog values.<br>Example:
    <code>set <name> sendDataAnalog &lt;Target-IP&gt; &lt;CAN-Channel&gt; &lt;Index&gt;=&lt;Value&gt;;&lt;Type&gt;<br>
    set coe sendDataAnalog 192.168.1.1 3 1=22.7;1 2=18.0;1
    </code>
    </li>
    <li><a href="#sendDataDigital">sendDataDigital</a><br>Sends digital values. This can be 0 or 1.<br>Example:
    <code>set <name> sendDataDigital &lt;Target-IP&gt; &lt;CAN-Channel&gt; &lt;Index&gt;=&lt;Value&gt;<br>
    set coe sendDataDigital 192.168.1.1 3 1=1 2=0
    </code>
    </li>
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
<a name="CanOverEthernetset"><b>Set</b></a>
  <ul>
    <li><a href="#sendDataAnalog">sendDataAnalog</a><br>Sendet analoge Werte.<br>Beispiel:
      <code>set <name> sendDataAnalog &lt;Target-IP&gt; &lt;CAN-Channel&gt; &lt;Index&gt;=&lt;Value&gt;;&lt;Type&gt;<br>
      set coe sendDataAnalog 192.168.1.1 3 1=22.7;1 2=18.0;1
      </code>
    </li>
    <li><a href="#sendDataDigital">sendDataDigital</a><br>Sends digitale Werte. Also nur 0 oder 1.<br>Beispiel:
      <code>set <name> sendDataDigital &lt;Target-IP&gt; &lt;CAN-Channel&gt; &lt;Index&gt;=&lt;Value&gt;<br>
      set coe sendDataDigital 192.168.1.1 3 1=1 2=0
      </code>
    </li>
  </ul>

=end html_DE

=cut
