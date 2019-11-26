##############################################################################
#
#     71_COE_Node.pm
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
# COE_Node (c) Martin Gutenbrunner / https://github.com/delmar43/FHEM
#
# This module is designed to work as a logical device in connection with
# 70_CanOverEthernet as a physical device.
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,96170.0.html
#
# $Id$
#
##############################################################################

package main;

use strict;
use warnings;

sub COE_Node_Initialize {
  my ($hash) = @_;

  $hash->{DefFn}       = "COE_Node_Define";
  $hash->{ParseFn}     = "COE_Node_Parse";
  $hash->{UndefFn}     = "COE_Node_Undef";
  $hash->{GetFn}       = "COE_Node_Get";
  $hash->{SetFn}       = "COE_Node_Set";

  $hash->{AttrList} = "readingsConfigAnalog readingsConfigDigital " . $readingFnAttributes;
  $hash->{Match} = "^.*";

  return undef;
}

sub COE_Node_Define {
  my ( $hash, $def ) = @_;

  my @a = split( "[ \t][ \t]*", $def );
 
  my $name   = $a[0];
  my $module = $a[1];
  my $canNodeId = $a[2];
  
  if(@a < 3 || @a > 3) {
     my $msg = "COE_Node ($name) - Wrong syntax: define <name> COE_Node <CAN Node Id>";
     Log3 $name, 1, $msg;
     return $msg;
  }

  $hash->{NAME} = $name;

  AssignIoPort($hash);
  
  my $ioDevName = $hash->{IODev}{NAME};
  my $logDevAddress = $ioDevName.'_'.$canNodeId;

  Log3 $name, 5, "COE_Node ($name) - Define: Logical device address: $logDevAddress";
  $modules{COE_Node}{defptr}{$logDevAddress} = $hash;
  
  Log3 $name, 3, "COE_Node ($name) - Define done ... module=$module, canNodeId=$canNodeId";

  $hash->{helper}{CAN_NODE_ID} = $canNodeId;
  readingsSingleUpdate($hash, 'state', 'defined', 1);

  return undef;
}

sub COE_Node_Parse {
  my ( $io_hash, $buf) = @_;
  my $ioDevName = $io_hash->{NAME};

  my ( $canNodeId, $canNodePartId ) = unpack 'C C', $buf;
  my $bytes = substr $buf, 2;
  my $logDevAddress = $ioDevName.'_'.$canNodeId;

  # wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
  if(my $hash = $modules{COE_Node}{defptr}{$logDevAddress}) {
    COE_Node_HandleData($hash, $canNodeId, $canNodePartId, $bytes);

    return $hash->{NAME}; 

  } else {

    # Keine Gerätedefinition verfügbar
    # Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
    Log3 $ioDevName, 5, "COE_Node-Parse ($ioDevName) - No definition for $logDevAddress. Suggesting autocreate for canNodeId=$canNodeId";

    my $ioName = $io_hash->{NAME};
    return "UNDEFINED COE_Node_".$ioDevName."_".$canNodeId." COE_Node $canNodeId";
  }
}

sub COE_Node_HandleData {
  my ( $hash, $canNodeId, $canNodePartId, $bytes ) = @_;
  my $name = $hash->{NAME};

  readingsBeginUpdate($hash);
  if ( $canNodePartId > 0 ) {
    COE_Node_HandleAnalogValues($hash, $canNodePartId, $bytes);
  } else {
    COE_Node_HandleDigitalValues($hash, $canNodePartId, $bytes);
  }
  readingsEndUpdate($hash, 1);

}

sub COE_Node_HandleAnalogValues {
  my ( $hash, $canNodePartId, $bytes ) = @_;

  my @valuesAndTypes = unpack 's s s s C C C C', $bytes;

  my @values = @valuesAndTypes[0..3];
  my @types = @valuesAndTypes[4..7];
  my $canNodeId = $hash->{helper}{CAN_NODE_ID};
  my $name = $hash->{NAME};

  my $readings = AttrVal($name, 'readingsConfigAnalog', undef);
  if (! defined $readings) {
    Log3 $name, 0, "COE_Node ($name) - No config found. Please set readingsConfigAnalog accordingly.";
    return undef;
  }

  Log3 $name, 4, "COE_Node ($name) - Config found: $readings";

  # incoming data: 05011700f3000000000001010000  
  # extract readings from config, so we know, how to assign each value to a reading
  # readings are separated by space
  # format: index=name
  # example
  # 1=T.Solar 2=T.Solar_RL
  my @readingsArray = split / /, $readings;
  my @readingsMapping;
  foreach my $readingsEntry (@readingsArray) {
    Log3 $name, 5, "COE_Node ($name) - $readingsEntry";
    
    my @entry = split /=/, $readingsEntry;
    $readingsMapping[$entry[0]] = makeReadingName($entry[1]);
  }

  if ($canNodeId != $hash->{helper}{CAN_NODE_ID}) {
    Log3 $name, 0, "COE_Node ($name) - defined nodeId $hash->{canNodeId} != message-nodeId $canNodeId. Skipping message.";
    return undef;
  }

  #iterate through data entries. 4 entries max per incoming UDP packet
  for (my $i=0; $i < 4; $i++) {
    my $outputId = ($i + ($canNodePartId-1) * 4 +1);
    my $entryId = $outputId;
    my $existingConfig = exists $readingsMapping[$entryId];
    my $value = $values[$i];
    my $type = $types[$i];

    if ($existingConfig) {

      if ($type == 1 || $type == 10) {
        $value = (substr $value, 0, (length $value)-1) . "." . (substr $value, -1);
      } elsif ($type == 13) {
        $value = (substr $value, 0, (length $value)-2) . "." . (substr $value, -2);
      }

      if ( COE_Node_BeginsWith($value, '.') ) {
          $value = "0$value";
      }

      my $reading = $readingsMapping[$entryId];
      readingsBulkUpdateIfChanged( $hash, $reading, $value );

      Log3 $name, 4, "COE_Node ($name) - [$canNodeId][$canNodePartId][$i][$entryId][type=$type][value=$value]  configured: $reading";
    } else {
      Log3 $name, 0, "COE_Node ($name) - [$canNodeId][$canNodePartId][$i][$entryId][type=$type][value=$value]  $entryId not configured. Skipping.";
    }
  }
}

sub COE_Node_HandleDigitalValues {
  my ( $hash, $canNodePartId, $bytes ) = @_;
  my $name = $hash->{NAME};
  my $canNodeId = $hash->{helper}{CAN_NODE_ID};

  my $values = unpack 'b*', $bytes;
  my @bits = split //, $values;

  my $readings = AttrVal($name, 'readingsConfigDigital', undef);
  if (! defined $readings) {
    Log3 $name, 0, "COE_Node ($name) - No config found. Please set readingsConfigDigital accordingly.";
    return undef;
  }

  Log3 $name, 4, "COE_Node ($name) - Config found: $readings";

  my @readingsArray = split / /, $readings;
  my @readingsMapping;
  foreach my $readingsEntry (@readingsArray) {
    Log3 $name, 5, "COE_Node ($name) - $readingsEntry";

    my @entry = split /=/, $readingsEntry;
    $readingsMapping[$entry[0]] = makeReadingName($entry[1]);
  }

  if ($canNodeId != $hash->{helper}{CAN_NODE_ID}) {
    Log3 $name, 0, "COE_Node ($name) - defined nodeId $hash->{canNodeId} != message-nodeId $canNodeId. Skipping message.";
    return undef;
  }


  for (my $i=0; $i < 32; $i++) {
    my $reading = $readingsMapping[$i+1];
    readingsBulkUpdateIfChanged( $hash, $reading, $bits[$i] );
    Log3 $name, 4, "COE_Node ($name) - [$canNodeId][$canNodePartId][".($i+1)."] = $bits[$i]";
  }
}

sub COE_Node_BeginsWith {
    return substr($_[0], 0, length($_[1])) eq $_[1];
}

sub COE_Node_Undef {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  return undef;
}

sub COE_Node_Get {
  return undef;
}

sub COE_Node_Set {
  return undef;
}

1;

=pod
=item device
=item summary Single CanOverEthernet node which is created automatically by CanOverEthernet
=item summary_DE Ein einzelner CanOverEthernet Node. Wird automatisch erstellt.

=begin html

<a name="COE_Node"></a>
<h3>COE_Node</h3>

<a name="COE_Nodedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; COE_Node &lt;CAN-Node ID&gt;</code>
    <br><br>
    Defines a CanOverEthernet node. FHEM will automatically create these.
    <br>
    Example:
    <ul>
      <code>define COE_Node_coe_2 COE_Node 2</code>
    </ul>
    Assigment of readings to incoming values is done in the attribue 'readingsConfig'.
  </ul>
  <br><br>

<a name="COE_Nodeattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><a href="#readingsConfigAnalog">readingsConfigAnalog {index=reading-name}</a><br>This maps received analog values to readings. eg <code>1=Flowrate_Solar 2=T.Solar_Backflow</code></li>
    <li><a href="#readingsConfigDigital">readingsConfigDigital {index=reading-name}</a><br>This maps received digital values to readings. eg <code>1=Pump_Solar_Power 2=Pump_Water_Power</code></li>
  </ul>

=end html

=begin html_DE

<a name="COE_Node"></a>
<h3>COE_Node</h3>

<a name="COE_Nodedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; COE_Node &lt;CAN-Node ID&gt;</code>
    <br><br>
    Repräsentiert einen einzelnen CanOverEthernet Node. Wird normalerweise automatisch erstellt.
    <br>
    Beispiel:
    <ul>
      <code>define COE_Node_coe_2 COE_Node 2</code>
    </ul>
    Die eintreffenden Werte müssen noch im Attribut 'readingsConfig' einem Reading zugewiesen werden.
  </ul>
  <br><br>

<a name="COE_Nodeattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><a href="#readingsConfigAnalog">readingsConfigAnalog {index=reading-name}</a><br>Ordnet analoge Werte einem Reading zu. zB  <code>1=Durchfluss_Solar 2=T.Solar_R&uuml;cklauf</code></li>
    <li><a href="#readingsConfigDigital">readingsConfigDigital {index=reading-name}</a><br>Ordnet digitale Werte einem Reading zu. zB  <code>1=Solarpumpe_Status 2=Wasserpumpe_Status</code></li>
  </ul>

=end html_DE

=cut
