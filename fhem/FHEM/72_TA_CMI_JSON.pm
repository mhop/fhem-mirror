##############################################################################
#
#     72_TA_CMI_JSON.pm
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
# TA_CMI_JSON (c) Martin Gutenbrunner / https://github.com/delmar43/FHEM
#
# This module queries the CMI JSON API and allows to map values to readings.
# Supported devices are UVR1611, UVR16x2, RSM610, CAN-I/O45, CAN-EZ2, CAN-MTx2,
# and CAN-BC2 by Technische Alternative https://www.ta.co.at/
#
# Information in the Wiki: https://wiki.fhem.de/wiki/UVR16x2
#
# Discussed in FHEM Forum:
# * https://forum.fhem.de/index.php/topic,41439.0.html
# * https://forum.fhem.de/index.php/topic,13534.45.html
#
# $Id$
#
##############################################################################

package main;
use strict;
use warnings;
use HttpUtils;

sub TA_CMI_JSON_Initialize;
sub TA_CMI_JSON_Define;
sub TA_CMI_JSON_GetStatus;
sub TA_CMI_JSON_Undef;
sub TA_CMI_JSON_PerformHttpRequest;
sub TA_CMI_JSON_ParseHttpResponse;
sub TA_CMI_JSON_Get;
sub TA_CMI_JSON_extractDeviceName;
sub TA_CMI_JSON_extractVersion;
sub TA_CMI_JSON_extractReadings;

sub TA_CMI_JSON_Initialize($) {
  my ($hash) = @_;

  $hash->{GetFn}     = "TA_CMI_JSON_Get";
  $hash->{DefFn}     = "TA_CMI_JSON_Define";
  $hash->{UndefFn}   = "TA_CMI_JSON_Undef";

  $hash->{AttrList} = "username password interval readingNamesInputs readingNamesOutputs readingNamesDL-Bus " . $readingFnAttributes;

  Log3 '', 3, "TA_CMI_JSON - Initialize done ...";
}

sub TA_CMI_JSON_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
 
  my $name   = $a[0];
  my $module = $a[1];
  my $cmiUrl = $a[2];
  my $nodeId = $a[3];
  my $queryParams = $a[4];
 
  if(@a != 5) {
     my $msg = "TA_CMI_JSON ($name) - Wrong syntax: define <name> TA_CMI_JSON CMI-URL CAN-Node-ID QueryParameters";
     Log3 undef, 2, $msg;
     return $msg;
  }

  $hash->{NAME} = $name;
  $hash->{CMIURL} = $cmiUrl;
  $hash->{NODEID} = $nodeId;
  $hash->{QUERYPARAM} = $queryParams;
  $hash->{INTERVAL} = AttrVal( $name, "interval", "60" );
  
  Log3 $name, 5, "TA_CMI_JSON ($name) - Define done ... module=$module, CMI-URL=$cmiUrl, nodeId=$nodeId, queryParams=$queryParams";

  readingsSingleUpdate($hash, 'state', 'defined', 1);

  TA_CMI_JSON_GetStatus( $hash, 2 );

  return undef;
}

sub TA_CMI_JSON_GetStatus( $;$ ) {
  my ( $hash, $delay ) = @_;
  my $name = $hash->{NAME};

  TA_CMI_JSON_PerformHttpRequest($hash);
}

sub TA_CMI_JSON_Undef($$) {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  HttpUtils_Close($hash);

  return undef;
}

sub TA_CMI_JSON_PerformHttpRequest($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my $url = "http://$hash->{CMIURL}/INCLUDE/api.cgi?jsonnode=$hash->{NODEID}&jsonparam=$hash->{QUERYPARAM}";
    my $username = AttrVal($name, 'username', 'admin');
    my $password = AttrVal($name, 'password', 'admin');

    my $param = {
                    url        => "$url",
                    timeout    => 5,
                    hash       => $hash,
                    method     => "GET",
                    header     => "User-Agent: FHEM\r\nAccept: application/json",
                    user       => $username,
                    pwd        => $password,
                    callback   => \&TA_CMI_JSON_ParseHttpResponse
                };

    HttpUtils_NonblockingGet($param);
}

sub TA_CMI_JSON_ParseHttpResponse($) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $return;

  if($err ne "") {
     Log3 $name, 0, "error while requesting ".$param->{url}." - $err";                                               # Eintrag fürs Log
#     readingsSingleUpdate($hash, "fullResponse", "ERROR", 0);                                                        # Readings erzeugen
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'state', 'ERROR', 0);
      readingsBulkUpdate($hash, 'error', $err, 0);
      readingsEndUpdate($hash, 0);      
  } elsif($data ne "") {
     my $keyValues = json2nameValue($data);

     $hash->{STATE} = $keyValues->{Status};
     $hash->{CAN_DEVICE} = TA_CMI_JSON_extractDeviceName($keyValues->{Header_Device});
     $hash->{CMI_API_VERSION} = TA_CMI_JSON_extractVersion($keyValues->{Header_Version});
     CommandDeleteReading(undef, "$name error");

     readingsBeginUpdate($hash);
     readingsBulkUpdateIfChanged($hash, 'state', $keyValues->{Status});
     if ( $keyValues->{Status} eq 'OK' ) {
       my $queryParams = $hash->{QUERYPARAM};
       TA_CMI_JSON_extractReadings($hash, $keyValues, 'Inputs') if ($queryParams =~ /I/);
       TA_CMI_JSON_extractReadings($hash, $keyValues, 'Outputs') if ($queryParams =~ /O/);
       TA_CMI_JSON_extractReadings($hash, $keyValues, 'DL-Bus') if ($queryParams =~ /D/);
     }
     
     readingsEndUpdate($hash, 1);

#     Log3 $name, 3, "TA_CMI_JSON ($name) - Device: $keyValues->{Header_Device}";
  }

  my $functionName = "TA_CMI_JSON_GetStatus";
  RemoveInternalTimer($hash, $functionName);
  InternalTimer( gettimeofday() + $hash->{INTERVAL}, $functionName, $hash, 0 );

  return undef;
}

sub TA_CMI_JSON_extractDeviceName($) {
  my ($input) = @_;

  my $result;
  if ($input eq '80') {
    $result = 'UVR1611';
  } elsif ($input eq '87') {
    $result = 'UVR16x2';
  } elsif ($input eq '88') {
    $result = 'RSM610';
  } elsif ($input eq '89') {
    $result = 'CAN-I/O45';
  } elsif ($input eq '8B') {
    $result = 'CAN-EZ2';
  } elsif ($input eq '8C') {
    $result = 'CAN-MTx2';
  } elsif ($input eq '8D') {
    $result = 'CAN-BC2';
  } else {
    $result = "Unknown: $input";
  }

  return $result;
}

sub TA_CMI_JSON_extractVersion($) {
  my ($input) = @_;
  
  my $result;
  if ($input == 1) {
    $result = '1.25.2 2016-12-12';
  } elsif ($input == 2) {
    $result = '1.26.1 2017-02-24';
  } elsif ($input == 3) {
    $result = '1.28.0 2017-11-09';
  } else {
    $result = "unknown: $input";
  }
  
  return $result;
}

sub TA_CMI_JSON_extractReadings($$$) {
  my ( $hash, $keyValues, $id ) = @_;
  my $name = $hash->{NAME};

  my $readingNames = AttrVal($name, "readingNames$id", '');
  Log3 $name, 5, 'readingNames'.$id.": $readingNames";
  my @readingsArray = split(/ /, $readingNames); #1:T.Kollektor 5:T.Vorlauf

  for my $i (0 .. (@readingsArray-1)) {
    my ( $idx, $readingName ) = split(/\:/, $readingsArray[$i]);
    $readingName = makeReadingName($readingName);

    my $jsonKey = 'Data_'.$id.'_'.$idx.'_Value_Value';
    my $readingValue = $keyValues->{$jsonKey};
    Log3 $name, 5, "readingName: $readingName, key: $jsonKey, value: $readingValue";
    
    readingsBulkUpdateIfChanged($hash, $readingName, $readingValue);
  }

  return undef;
}

sub TA_CMI_JSON_Get ($@) {
  my ( $hash, $name, $opt, $args ) = @_;

  if ("update" eq $opt) {
    TA_CMI_JSON_PerformHttpRequest($hash);
    return undef;
  }

#  Log3 $name, 3, "ZoneMinder ($name) - Get done ...";
  return "Unknown argument $opt, choose one of update";

}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [device]
=item summary Reads values from the Technische Alternative CMI device
=item summary_DE Werte vom CMI der Firma Technische Alternative auslesen.

=begin html

<a name="TA_CMI_JSON"></a>
<h3>TA_CMI_JSON</h3>
<a name="TA_CMI_JSONdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TA_CMI_JSON  &lt;IP&gt; &lt;CAN-Node-Id&gt; &lt;Query-Params&gt;</code>
    <br><br>
    Defines a device that receives values from the CMI at the given IP for the CAN-device with the given CAN-Node-Id.<br/>
    Query-Param defines, which values you want to read. Allowed values are I,O,D.
    <br>
    Example:
    <ul>
      <code>defmod cmi TA_CMI_JSON 192.168.4.250 1 I,O,D</code><br>
    </ul>
    <br>
    It's mandatory to define which values should be mapped to readings.<br/>
    Only mapped values will not be written to readings. (see <a href="#TA_CMI_JSONattr">Attributes</a> for details)
  </ul>
  <br><br>
  
    <a name="TA_CMI_JSONget"></a>
  <b>Get</b>
  <ul>
    <li><code>update</code><br>Triggers querying of values from the CMI. Please note that the request rate is limited to one query per minute.
    </li>
  </ul>
  
  <br><br>
  <a name="TA_CMI_JSONattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>readingNamesDL-Bus {index:reading-name}</code><br>This maps received values from the DL-Bus to readings. eg <code>1:Flowrate_Solar 2:T.Solar_Backflow</code></li>
    <li><code>readingNamesInputs {index:reading-name}</code><br>This maps received values from the Inputs to readings. eg <code>1:Flowrate_Solar 2:T.Solar_Backflow</code></li>
    <li><code>readingNamesOutputs {index:reading-name}</code><br>This maps received values from the Outputs to readings. eg <code>1:Flowrate_Solar 2:T.Solar_Backflow</code></li>
    <li><code>interval</code><br>Query interval in seconds. Minimum query interval is 60 seconds.</li>
    <li><code>username</code><br>Username for querying the JSON-API. Needs to be either admin or user privilege.</li>
    <li><code>password</code><br>Password for querying the JSON-API.</li>
    
  </ul>
  <br><br>
  
  <a name="TA_CMI_JSONreadings"></a>
  <b>Readings</b>
  <br><br>
  Readings will appear according to the mappings defined in Attributes.
  
=end html

=begin html_DE

<a name="TA_CMI_JSON"></a>
<h3>TA_CMI_JSON</h3>
Weitere Informationen zu diesem Modul im <a href="https://wiki.fhem.de/wiki/UVR16x2">FHEM-Wiki</a>.
<a name="TA_CMI_JSONdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TA_CMI_JSON  &lt;IP&gt; &lt;CAN-Node-Id&gt; &lt;Query-Params&gt;</code>
    <br><br>
    Liest Werte vom CMI mit der angegebenen IP für das CAN-Gerät mit der angegebenen Node-Id.<br/>
    Query-Param definiert, welche Werte ausgelesen werden sollen. Erlaubt sind I,O,D.
    <br>
    Beispiel:
    <ul>
      <code>defmod cmi TA_CMI_JSON 192.168.4.250 1 I,O,D</code><br>
    </ul>
    <br>
    Daneben muss auch noch das mapping angegeben werden, welche Werte in welches Reading geschrieben werden sollen.<br/>
    Nur gemappte Werte werden in Readings geschrieben. (siehe <a href="#TA_CMI_JSONattr">Attributes</a>)
  </ul>
  <br><br>
  
    <a name="TA_CMI_JSONget"></a>
  <b>Get</b>
  <ul>
    <li><code>update</code><br>Hiermit kann sofort eine Abfrage der API ausgef&uuml;hrt werden. Das Limit von einer Anfrage pro Minute besteht trotzdem.
    </li>
  </ul>
  
  <br><br>
  <a name="TA_CMI_JSONattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>readingNamesDL-Bus {index:reading-name}</code><br>Hiermit werden erhaltene Werte vom DL-Bus einem Reading zugewiesen. zB <code>1:Durchfluss_Solar 2:T.Solar_RL</code></li>
    <li><code>readingNamesInput {index:reading-name}</code><br>Hiermit werden erhaltene Werte der Eing&auml;nge einem Reading zugewiesen. zB <code>1:Durchfluss_Solar 2:T.Solar_RL</code></li>
    <li><code>readingNamesDL-Bus {index:reading-name}</code><br>Hiermit werden erhaltene Werte der Ausg&auml;nge einem Reading zugewiesen. zB <code>1:Durchfluss_Solar 2:T.Solar_RL</code></li>
    <li><code>interval</code><br>Abfrage-Intervall in Sekunden. Muss mindestens 60 sein.</li>
    <li><code>username</code><br>Username zur Abfrage der JSON-API. Muss die Berechtigungsstufe admin oder user haben.</li>
    <li><code>password</code><br>Passwort zur Abfrage der JSON-API.</li>
    
  </ul>
  <br><br>
  
  <a name="TA_CMI_JSONreadings"></a>
  <b>Readings</b>
  <br><br>
  Readings werden entsprechend der Definition in den Attributen angelegt.
=end html

# Ende der Commandref
=cut
