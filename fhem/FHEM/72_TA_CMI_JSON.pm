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
# Information in the Wiki: https://wiki.fhem.de/wiki/TA_CMI_UVR16x2_UVR1611
#
# Discussed in FHEM Forum:
# * https://forum.fhem.de/index.php/topic,92740.0.html (official)
# * https://forum.fhem.de/index.php/topic,41439.0.html (previous discussions)
# * https://forum.fhem.de/index.php/topic,13534.45.html (previous discussions)
#
# $Id$
#
##############################################################################

package main;
use strict;
use warnings;

sub TA_CMI_JSON_Initialize {
  my ($hash) = @_;

  $hash->{SetFn}     = "TA_CMI_JSON::Set";
  $hash->{GetFn}     = "TA_CMI_JSON::Get";
  $hash->{DefFn}     = "TA_CMI_JSON::Define";
  $hash->{UndefFn}   = "TA_CMI_JSON::Undef";
  $hash->{NotifyFn}  = "TA_CMI_JSON::Notify";
#  $hash->{FW_detailFn} = "TA_CMI_JSON::DetailFn";
#  $hash->{FW_directNotify} = "TA_CMI_JSON::DirectNotify";

  $hash->{AttrList} = "username password outputStatesInterval interval readingNamesInputs readingNamesOutputs readingNamesDL-Bus readingNamesLoggingAnalog readingNamesLoggingDigital includePrettyReadings:0,1 includeUnitReadings:0,1 prettyOutputStates:0,1 " . $readingFnAttributes;

  Log3 '', 3, "TA_CMI_JSON - Initialize done ...";
}


package TA_CMI_JSON;
use strict;
use warnings;
use HttpUtils;

use GPUtils qw(:all);

my %deviceNames = (
  '80' => 'UVR1611',
  '87' => 'UVR16x2',
  '88' => 'RSM610',
  '89' => 'CAN-I/O45',
  '8B' => 'CAN-EZ2',
  '8C' => 'CAN-MTx2',
  '8D' => 'CAN-BC2',
  '8E' => 'UVR65',
  '8F' => 'CAN-EZ3',
  '91' => 'UVR610',
  '92' => 'UVR67',
  'A3' => 'BL_NET'
);

my %versions = (
  1 => '1.25.2 2016-12-12',
  2 => '1.26.1 2017-02-24',
  3 => '1.28.0 2017-11-09',
  4 => '1.34.2 2019-04-04',
  5 => '1.35.1 2019-07-02',
  6 => '1.38.1 2021-02-04'
);

my %units = (
   0 => '', 1 => '°C', 2 => 'W/m²', 3 => 'l/h', 4 => 'Sek', 5 => 'Min', 6 => 'l/Imp',
   7 => 'K', 8 => '%', 10 => 'kW', 11 => 'kWh', 12 => 'MWh', 13 => 'V', 14 => 'mA',
  15 => 'Std', 16 => 'Tage', 17 => 'Imp', 18 => 'kΩ', 19 => 'l', 20 => 'km/h',
  21 => 'Hz', 22 => 'l/min', 23 => 'bar', 24 => '', 25 => 'km', 26 => 'm', 27 => 'mm',
  28 => 'm³', 35 => 'l/d', 36 => 'm/s', 37 => 'm³/min', 38 => 'm³/h', 39 => 'm³/d',
  40 => 'mm/min', 41 => 'mm/h', 42 => 'mm/d', 43 => 'Aus/Ein', 44 => 'Nein/Ja',
  46 => '°C', 50 => '€', 51 => '$', 52 => 'g/m³', 53 => '', 54 => '°', 56 => '°',
  57 => 'Sek', 58 => '', 59 => '%', 60 => 'Uhr', 63 => 'A', 65 => 'mbar', 66 => 'Pa',
  67 => 'ppm'
);

my %rasStates = (
  0 => 'Time/auto',
  1 => 'Standard',
  2 => 'Setback',
  3 => 'Standby/frost pr.'
);

my %outputStates = (
  0 => 'n/a',
  1 => 'Auto-Off',
  3 => 'Auto-On',
  5 => 'Manual-Off',
  7 => 'Manual-On'
);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(qw(
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBulkUpdateIfChanged
        readingsBeginUpdate
        readingsEndUpdate
        readingsDelete
        Log3
        HttpUtils_Close
        HttpUtils_NonblockingGet
        RemoveInternalTimer
        InternalTimer
        makeReadingName
        AttrVal
        json2nameValue
        gettimeofday
    ))
};

sub Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
 
  my $name   = $a[0];
  my $module = $a[1];
  my $cmiUrl = $a[2];
  my $nodeId = $a[3];
  my $queryParams = $a[4];
 
  if(@a != 4 && @a != 5) {
     my $msg = "TA_CMI_JSON ($name) - Wrong syntax: define <name> TA_CMI_JSON CMI-URL CAN-Node-ID <QueryParameters>";
     Log3 $name, 0, $msg;
     return $msg;
  }

  $hash->{NAME} = $name;
  $hash->{CMIURL} = $cmiUrl;
  $hash->{NODEID} = $nodeId;
  $hash->{QUERYPARAM} = $queryParams;

  Log3 $name, 3, "TA_CMI_JSON ($name) - Define ... module=$module, CMI-URL=$cmiUrl, nodeId=$nodeId";
  readingsSingleUpdate($hash, 'state', 'defined', 1);

  SetupIntervals($hash) if ($main::init_done);

  return undef;
}

sub Notify($$) {
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash
 
  return "" if(main::IsDisabled($ownName)); # Return without any further action if the module is disabled
 
  my $devName = $dev_hash->{NAME}; # Device that created the events
  my $events = main::deviceEvents($dev_hash, 1);

  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
    SetupIntervals($own_hash);
  }

}

sub SetupIntervals($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $queryParams = $hash->{QUERYPARAM};
  if ( defined $queryParams ) {
    $hash->{INTERVAL} = AttrVal( $name, "interval", "60" );
    Log3 $name, 3, "TA_CMI_JSON ($name) - queryParam interval: ".$hash->{INTERVAL};
    Log3 $name, 3, "TA_CMI_JSON ($name) - queryParams=$queryParams";
  }
  #make initial call in any case, even if queryParams not defined. because that brings us model and number of outputs
  GetStatus( $hash );
  
  my $outputStatesInterval = AttrVal( $name, 'outputStatesInterval', undef);
  if ( defined $outputStatesInterval ) {
    Log3 $name, 3, "TA_CMI_JSON ($name) - Define::outputStatesInterval: $outputStatesInterval";
    RequestOutputStates ( $hash );
  }

}

sub GetStatus($) {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  PerformHttpRequest($hash);
}

sub Undef($$) {
  my ($hash, $arg) = @_; 
  my $name = $hash->{NAME};

  HttpUtils_Close($hash);
  RemoveInternalTimer($hash);

  return undef;
}

sub PerformHttpRequest($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    my $queryParam = $hash->{QUERYPARAM};
    $queryParam = '' unless defined $queryParam;
    my $url = "http://$hash->{CMIURL}/INCLUDE/api.cgi?jsonnode=$hash->{NODEID}&jsonparam=$queryParam"."&_=".gettimeofday();
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
                    callback   => \&ParseHttpResponse
                };

    Log3 $name, 4, "TA_CMI_JSON ($name) - PerformHttpRequest $url";
    HttpUtils_NonblockingGet($param);
}

sub ParseHttpResponse($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $return;

  if($err ne "") {
      Log3 $name, 0, "TA_CMI_JSON ($name) - error while requesting ".$param->{url}." - $err";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'state', 'ERROR', 1);
      readingsBulkUpdate($hash, 'error', $err, 1);
      readingsEndUpdate($hash, 1);      
  } elsif($data ne "") {
    my $keyValues = json2nameValue($data);

    my $canDevice = extractDeviceName($keyValues->{Header_Device});
    $hash->{CAN_DEVICE} = $canDevice;
    $hash->{model} = $canDevice;
    $hash->{CMI_API_VERSION} = extractVersion($keyValues->{Header_Version});
    readingsDelete($hash, "error");
    readingsDelete($hash, "state");

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash, 'state', $keyValues->{Status}, 1);
    if ( $keyValues->{Status} eq 'OK' ) {
      my $queryParams = $hash->{QUERYPARAM};
      $queryParams = '' unless defined $queryParams;

      extractReadings($hash, $keyValues, 'Inputs', 'Inputs') if ($queryParams =~ /I/);
      extractReadings($hash, $keyValues, 'Outputs', 'Outputs') if ($queryParams =~ /O/);

      if ($queryParams =~ /D/) {
        if ($canDevice eq 'UVR16x2' or $canDevice eq 'RSM610' ) {
          extractReadings($hash, $keyValues, 'DL-Bus', 'DL-Bus');
        } else {
          Log3 $name, 1, "TA_CMI_JSON ($name) - Reading DL-Bus input is not supported on $canDevice";
        }
      }

      if ($queryParams =~ /La/) {
        if ($canDevice eq 'UVR16x2') {
          extractReadings($hash, $keyValues, 'LoggingAnalog', 'Logging_Analog');
        } else {
          Log3 $name, 1, "TA_CMI_JSON ($name) - Reading Logging Analog data is not supported on $canDevice";
        }
      }

      if ($queryParams =~ /Ld/) {
        if ($canDevice eq 'UVR16x2') {
          extractReadings($hash, $keyValues, 'LoggingDigital', 'Logging_Digital');
        } else {
          Log3 $name, 1, "TA_CMI_JSON ($name) - Reading Logging Digital data is not supported on $canDevice";
        }
      }
    }
    
    readingsEndUpdate($hash, 1);

#     Log3 $name, 3, "TA_CMI_JSON ($name) - Device: $keyValues->{Header_Device}";
  }

  if ( defined $hash->{QUERYPARAM} ) {
    my $functionName = "TA_CMI_JSON::GetStatus";
    RemoveInternalTimer($hash, $functionName);
    InternalTimer( gettimeofday() + $hash->{INTERVAL}, $functionName, $hash, 0 );
  }

  return undef;
}

sub extractDeviceName($) {
    my ($input) = @_;
    return (defined($deviceNames{$input}) ? $deviceNames{$input} : 'unknown: ' . $input);
}

sub extractVersion($) {
    my ($input) = @_;
    return (defined($versions{$input}) ? $versions{$input} : 'unknown: ' . $input);
}

sub extractReadings($$$$) {
  my ( $hash, $keyValues, $id, $dataKey ) = @_;
  my $name = $hash->{NAME};

  my $readingNames = AttrVal($name, "readingNames$id", '');
  Log3 $name, 5, 'readingNames'.$id.": $readingNames";
  my @readingsArray = split(/ /, $readingNames); #1:T.Kollektor 5:T.Vorlauf

  my $inclUnitReadings =  AttrVal( $name, "includeUnitReadings", 0 );
  my $inclPrettyReadings = AttrVal( $name, "includePrettyReadings", 0 );

  for my $i (0 .. (@readingsArray-1)) {
    my ( $idx, $readingName ) = split(/\:/, $readingsArray[$i]);
    $readingName = makeReadingName($readingName);

    my $jsonKey = 'Data_'.$dataKey.'_'.$idx.'_Value_Value';
    my $readingValue = $keyValues->{$jsonKey};
    Log3 $name, 5, "TA_CMI_JSON ($name) - readingName: $readingName, key: $jsonKey, value: $readingValue";
    readingsBulkUpdateIfChanged($hash, $readingName, $readingValue, 1);

    $jsonKey = 'Data_'.$dataKey.'_'.$idx.'_Value_RAS';
    my $readingRas = $keyValues->{$jsonKey};
    if (defined($readingRas)) {
      readingsBulkUpdateIfChanged($hash, $readingName . '_RAS', $readingRas, 1);

      if ($inclPrettyReadings) {
        my $ras = (defined($rasStates{$readingRas}) ? $rasStates{$readingRas} : undef);
        readingsBulkUpdateIfChanged($hash, $readingName . '_RAS_Pretty', $ras, 1) if ($ras);
      }
    }

    my $unit;
    if ($inclUnitReadings || $inclPrettyReadings) {
      $jsonKey = 'Data_'.$dataKey.'_'.$idx.'_Value_Unit';
      my $readingUnit = $keyValues->{$jsonKey};
      $unit = (defined($units{$readingUnit}) ? $units{$readingUnit} : 'unknown: ' . $readingUnit);
      Log3 $name, 5, "TA_CMI_JSON ($name) - readingName: $readingName . '_Unit', key: $jsonKey, value: $readingUnit, unit: $unit";

      readingsBulkUpdateIfChanged($hash, $readingName . '_Unit', $unit, 1) if ($inclUnitReadings);
    }

    if ($inclPrettyReadings) {
      readingsBulkUpdateIfChanged($hash, $readingName . '_Pretty', $readingValue . ' ' . $unit, 1);
    }
  }

  return undef;
}

sub Set($$$@) {
  my ( $hash, $name, $opt, @arg) = @_;

  Log3 $name, 5, "TA_CMI_JSON ($name) - Set: $name $opt ".join(' ', @arg);

  if ($opt eq 'fixwertAnalog' || $opt eq 'fixwertDigital') {
    
    my $index = $arg[0];
    my $value = $arg[1];

    my $type;
    if ($opt eq 'fixwertAnalog') {
      $type = 'D1';
    } else {
      $type = '1f';
    }

    FixwertChangeRequest($hash, $index, $value, $type);

    return undef;
  }

  return 'fixwertAnalog fixwertDigital';
}

sub FixwertChangeRequest($$$$) {
    my ($hash, $index, $value, $type) = @_;
    my $name = $hash->{NAME};
    my $nodeId = $hash->{NODEID};
    my $cmiIp = $hash->{CMIURL};

    my $hexNodeId = sprintf('%1x',$nodeId);
    $hexNodeId = "0$hexNodeId" unless length($hexNodeId) == 2;

    $index--; #1 on the Web UI is index 0. 2 is 1, etc.
    my $hexIndex = sprintf('%1x',$index);
    $hexIndex = "0$hexIndex" unless length($hexIndex) == 2;
    
    my $referrer = "Referer: http://$cmiIp/menupagex.cgi?nodex2=".$hexNodeId."005800";
    my $url = "http://$cmiIp/INCLUDE/change.cgi?changeadrx2=".$hexNodeId."00".$hexIndex."4414".$type."01&changetox2=".$value."&_=".gettimeofday();
    my $username = AttrVal($name, 'username', 'admin');
    my $password = AttrVal($name, 'password', 'admin');

    my $param = {
                    url        => "$url",
                    timeout    => 5,
                    hash       => $hash,
                    method     => "GET",
                    header     => $referrer,
                    user       => $username,
                    pwd        => $password,
                    callback   => \&FixwertChangeRequest_Callback
                };

    Log3 $name, 4, "TA_CMI_JSON ($name) - FixwertChangeRequest $url";
    HttpUtils_NonblockingGet($param);
}

sub FixwertChangeRequest_Callback {
my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if($err ne "") {
    Log3 $name, 0, "TA_CMI_JSON ($name) - error while calling ".$param->{url}." - $err";

  } elsif($data ne "") {
    Log3 $name, 5, "TA_CMI_JSON ($name) - FixwertChangeRequest_Callback: $data";
  }

  return undef;
}

sub Get($$$$) {
  my ( $hash, $name, $opt, $args ) = @_;

  if ("update" eq $opt) {
    PerformHttpRequest($hash);
    return undef;
  }

  if ("readOutputStates" eq $opt) {
    RequestOutputStates($hash); #unless $hash->{CAN_DEVICE} ne 'UVR1611';
    return undef;
  }

#  Log3 $name, 3, "ZoneMinder ($name) - Get done ...";
  return "Unknown argument $opt, choose one of update readOutputStates";
}

sub RequestOutputStates($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $nodeId = $hash->{NODEID};
    my $hexNodeId = sprintf('%1x',$nodeId);
    $hexNodeId = "0$hexNodeId" unless length($hexNodeId) == 2;

    my $url = "http://$hash->{CMIURL}/INCLUDE/agx2.cgi?nodex2=$hexNodeId"."&_=".gettimeofday();
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
                    callback   => \&ParseOutputStateResponse
                };

    Log3 $name, 4, "TA_CMI_JSON ($name) - RequestOutputStates $url";
    HttpUtils_NonblockingGet($param);
}

sub ParseOutputStateResponse($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $return;

  if($err ne "") {
      Log3 $name, 0, "TA_CMI_JSON ($name) - error while requesting output data ".$param->{url}." - $err";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'state', 'ERROR', 0);
      readingsBulkUpdate($hash, 'error', $err, 0);
      readingsEndUpdate($hash, 1);      
  } elsif($data ne "") {
     readingsDelete($hash, "error");
     readingsDelete($hash, "state");

     my @values = split(';', $data);
     my $nrValues = @values -2;

     my $prettyOutputStates = AttrVal( $name, "prettyOutputStates", '0' );
     my $readingNames = AttrVal($name, "readingNamesOutputs", undef);
     if ( ! defined $readingNames ) {
       Log3 $name, 1, "TA_CMI_JSON ($name) - Unable to assign output states, please set attribute readingNamesOutputs";
       return undef;
     }
     my @readingsArray = split(/ /, $readingNames); #1:T.Kollektor 5:T.Vorlauf

     readingsBeginUpdate($hash);
     foreach (@readingsArray) {
       my ( $readingNameIndex, $readingName ) = split(/\:/, $_);
       my $i = $readingNameIndex+1;

       $readingName = makeReadingName($readingName);
       my $readingValue = $values[$i];
       readingsBulkUpdateIfChanged($hash, $readingName.'_State', $readingValue, 1);
       if ($prettyOutputStates eq '1') {
         
         my $prettyValue = (defined($outputStates{$readingValue}) ? $outputStates{$readingValue} : '?:'.$readingValue);
         readingsBulkUpdateIfChanged($hash, $readingName.'_State_Pretty', $prettyValue, 1);
       }
       Log3 $name, 5, "TA_CMI_JSON ($name) - readingName: $readingName, readingNameIndex: $readingNameIndex, valueIndex: $i, value: $readingValue";
     }
     readingsEndUpdate($hash, 1);

     Log3 $name, 5, "TA_CMI_JSON ($name) - Output Data $nrValues: $data";
  }

  my $outputStatesInterval = AttrVal($name, 'outputStatesInterval', undef);
  if ( defined $outputStatesInterval ) {
    Log3 $name, 5, "TA_CMI_JSON ($name) - outputStatesInterval $outputStatesInterval";
    my $functionName = "TA_CMI_JSON::RequestOutputStates";
    RemoveInternalTimer($hash, $functionName);
    InternalTimer( gettimeofday() + $outputStatesInterval, $functionName, $hash, 0 );
  }

  return undef;
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
      <code>defmod cmi TA_CMI_JSON 192.168.4.250 1 &lt;I,O,D&gt;</code><br>
    </ul>
    <br>
    It's mandatory to define which values should be mapped to readings.<br/>
    Only mapped values will not be written to readings. (see <a href="#TA_CMI_JSONattr">Attributes</a> for details)
  </ul>
  <br><br>
  
  <a name="TA_CMI_JSONset"></a>
  <b>Set</b>
  <ul>
    <li><code>fixwertAnalog</code><br>Set Fixwert to an analog value. Example:<br>
    <ul><code>set cmiNode fixwertAnalog &lt;index&gt; &lt;value&gt;<br>set cmiNode fixwertAnalog 3 64.0</code></ul>
    </li>
    <li><code>fixwertDigital</code><br>Set Fixwert to a digital value. Also works for impulse values. Example:<br>
    <ul><code>set cmiNode fixwertDigital &lt;index&gt; &lt;value&gt;<br>set cmiNode fixwertDigital 2 1</code></ul>
    </li>
  </ul>

  <a name="TA_CMI_JSONget"></a>
  <b>Get</b>
  <ul>
    <li><code>update</code><br>Triggers querying of values from the CMI. Please note that the request rate is limited to one query per minute.
    </li>
    <li><code>readOutputStates</code><br>Reads Output states (eg Manual-On, Auto-Off) per defined output. Can be automated by setting <code>outputStatesInterval</code>.
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
    <li><code>readingNamesLoggingAnalog {index:reading-name}</code><br>This maps received values from Analog Logging to readings. zB eg <code>1:Flowrate_Solar 2:T.Solar_Backflow</code></li>
    <li><code>readingNamesLoggingDigital {index:reading-name}</code><br>This maps received values from Digital Logging to readings. zB eg <code>1:Flowrate_Solar 2:T.Solar_Backflow</code></li>
    <li><code>includeUnitReadings [0:1]</code><br>Adds another reading per value, which just contains the according unit of that reading.</li>
    <li><code>includePrettyReadings [0:1]</code><br>Adds another reading per value, which contains value plus unit of that reading.</li>
    <li><code>interval</code><br>Query interval in seconds. Minimum query interval is 60 seconds.</li>
    <li><code>outputStatesInterval</code><br>Request interval in seconds for getting output states.</li>
    <li><code>prettyOutputStates [0:1]</code><br>If set, generates a reading _State_Pretty for output states (eg Auto-On, Manual-Off)</li>
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
      <code>defmod cmi TA_CMI_JSON 192.168.4.250 1 &lt;I,O,D&gt;</code><br>
    </ul>
    <br>
    Daneben muss auch noch das mapping angegeben werden, welche Werte in welches Reading geschrieben werden sollen.<br/>
    Nur gemappte Werte werden in Readings geschrieben. (siehe <a href="#TA_CMI_JSONattr">Attributes</a>)
  </ul>
  <br><br>
  
  <a name="TA_CMI_JSONset"></a>
  <b>Set</b>
  <ul>
    <li><code>fixwertAnalog</code><br>Setzt einen Fixwert auf einen analogen Wert. Beispiel:<br>
    <ul><code>set cmiNode fixwertAnalog &lt;index&gt; &lt;value&gt;<br>set cmiNode fixwertAnalog 3 64.0</code></ul>
    </li>
    <li><code>fixwertDigital</code><br>Setzt einen Fixwert auf einen digitalen Wert. Funktioniert auch für Impulse. Beispiel:<br>
    <ul><code>set cmiNode fixwertDigital &lt;index&gt; &lt;value&gt;<br>set cmiNode fixwertDigital 2 1</code></ul>
    </li>
  </ul>

  <a name="TA_CMI_JSONget"></a>
  <b>Get</b>
  <ul>
    <li><code>update</code><br>Hiermit kann sofort eine Abfrage der API ausgef&uuml;hrt werden. Das Limit von einer Anfrage pro Minute besteht trotzdem.
    </li>
    <li><code>readOutputStates</code><br>Liest Ausgangs-Stati, zB Auto-Ein, Hand-Aus. Kann mittels <code>outputStatesInterval</code> automatisch ausgeführt werden. Das Zeitlimit von 60 Sekunden trifft hier nicht zu.
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
    <li><code>readingNamesLoggingAnalog {index:reading-name}</code><br>Hiermit werden erhaltene Werte vom Analog Logging einem Reading zugewiesen. zB <code>1:Durchfluss_Solar 2:T.Solar_RL</code></li>
    <li><code>readingNamesLoggingDigital {index:reading-name}</code><br>Hiermit werden erhaltene Werte vom Digital Logging einem Reading zugewiesen. zB <code>1:Durchfluss_Solar 2:T.Solar_RL</code></li>
    <li><code>includeUnitReadings [0:1]</code><br>Definiert, ob zu jedem Reading ein zusätzliches Reading _Name geschrieben werden soll, welches die Einheit enth&auml;lt.</li>
    <li><code>includePrettyReadings [0:1]</code><br>Definiert, ob zu jedem Reading zusätzlich ein Reading, welches Wert und Einheit enth&auml;lt, geschrieben werden soll.</li>
    <li><code>interval</code><br>Abfrage-Intervall in Sekunden. Muss mindestens 60 sein.</li>
    <li><code>outputStatesInterval</code><br>Abfrage-Intervall für Ausgangs-Stati in Sekunden.</li>
    <li><code>prettyOutputStates [0:1]</code><br>Definiert, ob zu einem Ausgangs-Status ein zusätzliches Reading _State_Pretty geschrieben werden soll (liefert zB Auto-On, Manual-Off)</li>
    <li><code>username</code><br>Username zur Abfrage der JSON-API. Muss die Berechtigungsstufe admin oder user haben.</li>
    <li><code>password</code><br>Passwort zur Abfrage der JSON-API.</li>
  </ul>
  <br><br>
  
  <a name="TA_CMI_JSONreadings"></a>
  <b>Readings</b>
  <br><br>
  Readings werden entsprechend der Definition in den Attributen angelegt.
=end html_DE

# Ende der Commandref
=cut
