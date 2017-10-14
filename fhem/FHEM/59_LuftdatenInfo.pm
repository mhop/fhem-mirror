# Id ##########################################################################
# $Id$

# copyright ###################################################################
#
# 59_LuftdatenInfo.pm
#
# Copyright by igami
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# FHEM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package main;
  use Encode;
  use strict;
  use warnings;

  use HttpUtils;

# forward declarations ########################################################
sub LuftdatenInfo_Initialize($);

sub LuftdatenInfo_Define($$);
sub LuftdatenInfo_Undefine($$);
sub LuftdatenInfo_Set($@);
sub LuftdatenInfo_Get($@);
sub LuftdatenInfo_Attr(@);

sub LuftdatenInfo_GetHttpResponse($$);
sub LuftdatenInfo_ParseHttpResponse($);

sub LuftdatenInfo_statusRequest($);

# initialize ##################################################################
sub LuftdatenInfo_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "LuftdatenInfo";

  $hash->{DefFn}    = $TYPE."_Define";
  $hash->{UndefFn}  = $TYPE."_Undefine";
  $hash->{SetFn}    = $TYPE."_Set";
  $hash->{GetFn}    = $TYPE."_Get";
  $hash->{AttrFn}   = $TYPE."_Attr";

  $hash->{AttrList} = ""
    . "disable:1,0 "
    . "disabledForIntervals "
    . "interval "
    . "rawReading:0,1 "
    . "timeout "
    . $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub LuftdatenInfo_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, $MODE, $DEF) = split(/[\s]+/, $def, 4);
  my $rc = eval{
    require JSON;
    JSON->import();
    1;
  };

  return(
      "Error loading JSON. Maybe this module is not installed? "
    . "\nUnder debian (based) system it can be installed using "
    . "\"apt-get install libjson-perl\""
  ) unless($rc);

  delete($hash->{SENSORIDS});
  delete($hash->{ADDRESS});
  delete($hash->{INTERVAL});
  delete($hash->{TIMEOUT});
  delete($hash->{MASTER});
  delete($hash->{SENSORS});

  my $hadTemperature = 1 if(ReadingsVal($SELF, "temperature", undef));

  delete($hash->{READINGS});

  if($MODE eq "remote"){
    return("Usage: define <name> $TYPE $MODE <SENSORID1> [<SENSORID2> ...]")
      if($DEF !~ m/^[\s\d]+$/);

    $hash->{SENSORIDS} = $DEF;
  }
  elsif($MODE eq "local"){
    return("Usage: define <name> $TYPE $MODE <IP>")
      if($DEF =~ m/\s/);

    $hash->{ADDRESS} = $DEF;
  }
  elsif($MODE eq "slave"){
    return("Usage: define <name> $TYPE $MODE <master-name> <reading regexps>")
      if($DEF !~ m/\s/);

    ($hash->{MASTER}, $hash->{SENSORS}) = split(/[\s]+/, $DEF, 2);

    delete($defs{$hash->{MASTER}}->{READINGS})
      if(IsDevice($hash->{MASTER}, $TYPE));
  }
  else{
    if(looks_like_number($MODE)){
      $hash->{SENSORIDS} = $MODE;
      $hash->{SENSORIDS} .= " ".($MODE + 1) if($hadTemperature);
      $hash->{SENSORIDS} .= " $DEF" if($DEF && looks_like_number($DEF));

      $MODE = "remote";

      $hash->{DEF} = "$MODE $hash->{SENSORIDS}";
    }
    elsif(!$DEF){
      $hash->{ADDRESS} = $MODE;

      $MODE = "local";

      $hash->{DEF} = "$MODE $hash->{ADDRESS}";
    }
    else{
      return(
          "Usage: define <name> $TYPE remote <SENSORID1> [<SENSORID2> ...]"
        . "       define <name> $TYPE local <IP>"
        . "       define <name> $TYPE slave <master-name> <sensor1 sensor2 ...>"
      );
    }
  }

  $hash->{MODE} = $MODE;

  unless($MODE eq "slave"){
    my $minInterval = $hash->{MODE} eq "local" ? 30 : 300;
    my $interval = AttrVal($SELF, "interval", $minInterval);
    $interval = $minInterval unless(looks_like_number($interval));
    $interval = $minInterval if($interval < $minInterval);
    my $minTimeout = 5;
    my $timeout = AttrVal($SELF, "timeout", $minTimeout);
    $timeout = $minTimeout unless(looks_like_number($timeout));
    $timeout = $minTimeout if($timeout < $minTimeout);

    $hash->{INTERVAL} = $interval;
    $hash->{TIMEOUT} = $timeout;
  }

  readingsSingleUpdate($hash, "state", "active", 1);

  LuftdatenInfo_statusRequest($hash);

  return;
}

sub LuftdatenInfo_Undefine($$) {
  my ($hash, $arg) = @_;

  HttpUtils_Close($hash);
  RemoveInternalTimer($hash);

  return;
}

sub LuftdatenInfo_Set($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"set $TYPE\" needs at least one argument" if(@a < 2);

  my $SELF = shift @a;
	my $argument = shift @a;
  my $value = join(" ", @a) if (@a);

  my %LuftdatenInfo_sets = (
    "statusRequest" => "statusRequest:noArg",
  );

  return(
      "Unknown argument $argument, choose one of "
    . join(" ", values %LuftdatenInfo_sets)
  ) if(!exists($LuftdatenInfo_sets{$argument}));

  if(!IsDisabled($SELF)){
    if($argument eq "statusRequest"){
      LuftdatenInfo_statusRequest($hash);
    }
  }

  return;
}

sub LuftdatenInfo_Get($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"get $TYPE\" needs at least one argument" if(@a < 2);

  my $SELF = shift @a;
	my $argument = shift @a;
  my $value = join(" ", @a) if (@a);

  my %LuftdatenInfo_gets = (
    "sensors" => "sensors:noArg",
  );

  return(
      "Unknown argument $argument, choose one of "
    . join(" ", values %LuftdatenInfo_gets)
  ) if(!exists($LuftdatenInfo_gets{$argument}));

  if($argument eq "sensors"){
    return (join("\n", split(" ", ReadingsVal(
      InternalVal($SELF, "MASTER", $SELF), ".sensors", "No sensors found."
    ))));
  }

  return;
}

sub LuftdatenInfo_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_Attr");

  if($attribute eq "disable"){
    if($value && $value == 1){
      readingsSingleUpdate($hash, "state", "disabled", 1);
    }
    elsif($cmd eq "del" || !$value){
      LuftdatenInfo_statusRequest($hash);

      readingsSingleUpdate($hash, "state", "active", 1);
    }
  }
  elsif($attribute eq "interval"){
    my $minInterval = $hash->{CONNECTION} eq "local" ? 30 : 300;
    my $interval = $cmd eq "set" ? $value : $minInterval;
    $interval = $minInterval unless(looks_like_number($interval));
    $interval = $minInterval if($interval < $minInterval);

    $hash->{INTERVAL} = $interval;
  }
  elsif($attribute eq "timeout"){
    my $minTimeout = 5;
    my $timeout = $cmd eq "set" ? $value : $minTimeout;
    $timeout = $minTimeout unless(looks_like_number($timeout));
    $timeout = $minTimeout if($timeout < $minTimeout);

    $hash->{TIMEOUT} = $timeout;
  }

  return;
}

# HttpUtils Fn ################################################################
sub LuftdatenInfo_GetHttpResponse($$) {
  my ($hash, $arg) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $MODE = $hash->{MODE};
  my $timeout = $hash->{TIMEOUT};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_GetHttpResponse");

  my $param = {
    timeout  => $timeout,
    hash     => $hash,
    method   => "GET",
    header   => "Accept: application/json",
    callback => \&LuftdatenInfo_ParseHttpResponse,
  };
  $param->{url} = "http://api.luftdaten.info/v1/sensor/$arg/"
    if($MODE eq "remote");
  $param->{url} = "http://$arg/data.json"
    if($MODE eq "local");

  HttpUtils_NonblockingGet($param);
}

sub LuftdatenInfo_ParseHttpResponse($) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_ParseHttpResponse");

  if($err ne ""){
    Log3($SELF, 2, "$TYPE ($SELF) - error while request: $err");

    readingsSingleUpdate($hash, "state", "error", 1);
  }
  elsif($data eq "[]"){
    Log3($SELF, 2, "$TYPE ($SELF) - error while request: no data returned");

    readingsSingleUpdate($hash, "state", "error", 1);
  }
  elsif($data ne ""){
    Log3 $SELF, 4, "$TYPE ($SELF) - returned data: $data";

    $data = encode('UTF-8', $data);
    $data = eval{decode_json($data)};

    if($@){
      Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");

      readingsSingleUpdate($hash, "state", "error", 1);

      return;
    }

    my $MODE = $hash->{MODE};
    my $rawReading = AttrVal($SELF, "rawReading", 0);

    if($param->{url} =~ m/openstreetmap/){
      my $address = $data->{address};

      readingsSingleUpdate(
          $hash, "location"
        , "$address->{postcode} "
        . ($address->{city} ? $address->{city} : $address->{town})
        , 1
      );
    }
    elsif($MODE eq "remote"){
      my $sensor = @{$data}[-1];
      my $sensor_type = $sensor->{sensor}{sensor_type}{name};

      Log3 $SELF, 5, "$TYPE ($SELF) - parsing $sensor_type data";

      my $latitude = $sensor->{location}{latitude};
      my $longitude = $sensor->{location}{longitude};

      if(
           $latitude ne ReadingsVal($SELF, "latitude", $latitude)
        || $longitude ne ReadingsVal($SELF, "longitude", $longitude)
      ){
        Log3(
            $SELF, 2
          , "$TYPE ($SELF) - "
          . "$sensor->{sensor}{sensor_type}{name} position differs from "
          . "other sensor position"
        );

        return;
      }

      unless(ReadingsVal($SELF, "location", undef)){
        my $param = {
          url      => "http://nominatim.openstreetmap.org/reverse?".
                      "format=json&lat=$latitude&lon=$longitude",
          timeout  => $hash->{TIMEOUT},
          hash     => $hash,
          method   => "GET",
          header   => "Accept: application/json",
          callback => \&LuftdatenInfo_ParseHttpResponse,
        };

        HttpUtils_NonblockingGet($param);
      }

      readingsBeginUpdate($hash);

      foreach (@{$sensor->{sensordatavalues}}){
        $_->{value} =~ m/^(\S+)(\s|$)/;
        $_->{value} = $1;
        my $knownReading = 1;

        if($_->{value_type} eq "P1"){
          $_->{value_type} = "PM10";
        }
        elsif($_->{value_type} eq "P2"){
          $_->{value_type} = "PM2.5";
        }
        elsif($_->{value_type} =~ /temperature$/){
          $_->{value_type} = "temperature";
        }
        elsif($_->{value_type} =~ /humidity$/){
          $_->{value_type} = "humidity";
        }
        elsif($_->{value_type} =~ /pressure$/){
          $_->{value} = ($_->{value} > 10000 ? $_->{value} / 100 : $_->{value});
          $_->{value_type} = "pressure";
        }
        else{
          $knownReading = 0;
        }

        readingsBulkUpdate($hash, $_->{value_type}, $_->{value})
          if($knownReading || $rawReading);
      }

      readingsBulkUpdateIfChanged($hash, "latitude", $latitude);
      readingsBulkUpdateIfChanged($hash, "longitude", $longitude);
      readingsBulkUpdate($hash, "state", "active");
      readingsEndUpdate($hash, 1);
    }
    elsif($MODE eq "local"){
      my @slaves = devspec2array("TYPE=$TYPE:FILTER=MASTER=$SELF");
      my @sensors;
      push(@sensors, $_->{value_type}) foreach (@{$data->{sensordatavalues}});

      readingsBeginUpdate($defs{$_}) foreach($SELF, @slaves);
      readingsBulkUpdateIfChanged(
        $hash, "softwareVersion", $data->{software_version}
      );
      readingsBulkUpdateIfChanged($hash, ".sensors", join(" ", sort(@sensors)));

      foreach (@{$data->{sensordatavalues}}){
        my $knownReading = 1;
        $_->{value} =~ m/^(\S+)(\s|$)/;
        $_->{value} = $1;

        my $device = (devspec2array(
          "MASTER=$SELF:FILTER=SENSORS=(.+ )?$_->{value_type}( .+)?"
        ))[0];
        $device = IsDevice($device, $TYPE) ? $defs{$device} : $hash;

        if($_->{value_type} =~ /P0$/){
          $_->{value_type} = "PM1";
        }
        elsif($_->{value_type} =~ /P1$/){
          $_->{value_type} = "PM10";
        }
        elsif($_->{value_type} =~ /P2$/){
          $_->{value_type} = "PM2.5";
        }
        elsif($_->{value_type} =~ /_height$/){
          $_->{value_type} = "altitude";
        }
        elsif($_->{value_type} =~ /_date$/){
          $_->{value_type} = "date";
        }
        elsif($_->{value_type} =~ /humidity$/){
          $_->{value_type} = "humidity";
        }
        elsif($_->{value_type} =~ /_Full$/){
          $_->{value_type} = "illuminanceFull";
        }
        elsif($_->{value_type} =~ /_UV$/){
          $_->{value_type} = "illuminanceUV";
        }
        elsif($_->{value_type} =~ /_IR$/){
          $_->{value_type} = "illuminanceIR";
        }
        elsif($_->{value_type} =~ /_Visible$/){
          $_->{value_type} = "illuminanceVisible";
        }
        elsif($_->{value_type} =~ /_lat$/){
          $_->{value_type} = "latitude";
        }
        elsif($_->{value_type} =~ /_lon$/){
          $_->{value_type} = "longitude";
        }
        elsif($_->{value_type} =~ /pressure$/){
          $_->{value} = ($_->{value} > 10000 ? $_->{value} / 100 : $_->{value});
          $_->{value_type} = "pressure";
        }
        elsif($_->{value_type} =~ /pressure_nn$/){
          $_->{value} = ($_->{value} > 10000 ? $_->{value} / 100 : $_->{value});
          $_->{value_type} = "pressureNN";
        }
        elsif($_->{value_type} =~ /_risk/){
          $_->{value_type} = "UVRisk";
        }
        elsif($_->{value_type} eq "signal"){
          $_->{value_type} = "signal";
        }
        elsif($_->{value_type} =~ /temperature$/){
          $_->{value_type} = "temperature";
        }
        elsif($_->{value_type} =~ /_watt/){
          $_->{value_type} = "UVIntensity";
        }
        elsif($_->{value_type} =~ /_time$/){
          $_->{value_type} = "time";
        }
        else{
          $knownReading = 0;
        }

        readingsBulkUpdate($device, $_->{value_type}, $_->{value})
          if($knownReading || $rawReading);
      }

      foreach($SELF, @slaves){
        readingsBulkUpdate($defs{$_}, "state", "active");
        readingsEndUpdate($defs{$_}, 1);
      }
    }
  }

  return;
}

# module Fn ###################################################################
sub LuftdatenInfo_statusRequest($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $MODE = $hash->{MODE};
  my $interval = InternalVal($SELF, "INTERVAL", undef);

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_statusRequest");

  if($interval){
    RemoveInternalTimer($hash);
    InternalTimer(
      gettimeofday() + $interval, "LuftdatenInfo_statusRequest", $hash
    );
  }

  return if(IsDisabled($SELF));

  if($MODE eq "remote"){
    LuftdatenInfo_GetHttpResponse($hash, $_)
      foreach(split(/[\s]+/, $hash->{SENSORIDS}));
  }
  elsif($MODE eq "local"){
    LuftdatenInfo_GetHttpResponse($hash, $hash->{ADDRESS});
  }
  elsif($MODE eq "slave"){
    if(  IsDevice($hash->{MASTER}, $TYPE)
      && InternalVal($hash->{MASTER}, "MODE", "") eq "local"
    ){
      readingsSingleUpdate($hash, "state", "active", 1);

      LuftdatenInfo_statusRequest($defs{$hash->{MASTER}});
    }
    else{
      readingsSingleUpdate($hash, "state", "master not defined", 1);
    }
  }
}

1;

# commandref ##################################################################
=pod
=item summary    provides data from Luftdaten.info
=item summary_DE stellt Daten von Luftdaten.info bereit

=begin html

<a name="LuftdatenInfo"></a>
<h3>LuftdatenInfo</h3>
(en | <a href="commandref_DE.html#LuftdatenInfo"><u>de</u></a>)
<div>
  <ul>
    LuftdatenInfo is the FHEM module to read particulate matter, temperature
    and humidity values ​​from the self-assembly particulate matter sensors
    from <a href="http://Luftdaten.info"><u>Luftdaten.info</u></a>.<br>
    The values ​​can be queried directly from the server or locally.<br>
    There is an
    <a href="https://forum.fhem.de/index.php/topic,73879">
      <u>alternative Firmware</u>
    </a>
     to support more sensors.<br>
    <br>
    <b>Prerequisites</b>
    <ul>
      The Perl module "JSON" is required.<br>
      Under Debian (based) system, this can be installed using
      <code>"apt-get install libjson-perl"</code>.
    </ul>
    <br>
    <a name="LuftdatenInfodefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; LuftdanteInfo2 remote
          &lt;SENSORID1&gt; [&lt;SENSORID2&gt; ..]<br>
        define &lt;name&gt; LuftdanteInfo2 local &lt;IP&gt;<br>
        define &lt;name&gt; LuftdanteInfo2
          slave &lt;master-name&gt; &lt;sensor1 sensor2 ...&gt;
      </code><br>
      To query the data from the server, all affected SensorIDs must be
      specified. The IDs of the SDS01 stands right at
      <a href="http://maps.luftdaten.info/">
        <u>http://maps.luftdaten.info/</u>
      </a>
      . The DHT22 SensorID is usually the SDS011 SensorID + 1. While parsing
      the data the location values from all sensors will be compared and a
      message will be written into the log if they differ.<br>
      For a local query of the data, the IP address or hostname must be
      specified.<br>
      If several similar sensors are used, the duplicate values can be written
      in another device.
    </ul><br>
    <a name="LuftdatenInfoset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>statusRequest</code><br>
        Starts a status request.
      </li>
    </ul><br>
    <a name="LuftdatenInfoget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>sensors</code><br>
        Lists all senors.
      </li>
    </ul><br>
    <a name="LuftdatenInforeadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>altitude</code>
      </li>
      <li>
        <code>humidity</code><br>
        Relative humidity in %
      </li>
      <li>
        <code>illuminanceFull</code><br>
        Illuminace of the full spectrum in lux
      </li>
      <li>
        <code>illuminanceIR</code><br>
        Iilluminace of the IR spectrum in lux
      </li>
      <li>
        <code>illuminanceUV</code><br>
        Iilluminace of the UV spectrum in lux
      </li>
      <li>
        <code>illuminanceVisible</code><br>
        Iilluminace of the visible spectrum in lux
      </li>
      <li>
        <code>latitude</code>
      </li>
      <li>
        <code>location</code><br>
        location as "postcode city"<br>
        Only available with remote query.
      </li>
      <li>
        <code>longitude</code>
      </li>
      <li>
        <code>PM1</code><br>
        Quantity of particles with a diameter of less than 1 μm in μg/m³
      </li>
      <li>
        <code>PM2.5</code><br>
        Quantity of particles with a diameter of less than 2.5 μm in μg/m³
      </li>
      <li>
        <code>PM10</code><br>
        Quantity of particles with a diameter of less than 10 μm in μg/m³
      </li>
      <li>
        <code>pressure</code><br>
        Pressure in hPa
      </li>
      <li>
        <code>pressureNN</code><br>
        Pressure at sea level in hPa<br>
        Is calculated if pressure and temperature sensor are active and the
        sensor is not at sea level.<br>
        The height, can be determined by maps or SmartPhone, needs to be
        specified at the configuration page.
      </li>
      <li>
        <code>signal</code><br>
        WLAN signal strength in dBm<br>
        Only available with local query.
      </li>
      <li>
        <code>temperature</code><br>
        Temperature in °C
      </li>
      <li>
        <code>UVIntensity</code><br>
        UV intensity in W
      </li>
      <li>
        <code>UVRisk</code><br>
        UV risk from 1 to 5
      </li>
    </ul><br>
    <a name="LuftdatenInfoattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>disable 1</code><br>
        No queries are started.
      </li>
      <li>
        <a href="#disabledForIntervals">
          <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
        </a>
      </li>
      <li>
        <code>interval &lt;seconds&gt;</code><br>
        Interval in seconds in which queries are performed.<br>
        The default and minimum value is 300 seconds.
      </li>
      <li>
        <code>timeout &lt;seconds&gt;</code><br>
        Timeout in seconds for the queries.<br>
        The default and minimum value is 5 seconds.
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a name="LuftdatenInfo"></a>
<h3>LuftdatenInfo</h3>
(<a href="commandref.html#LuftdatenInfo"><u>en</u></a> | de)
<div>
  <ul>
    LuftdatenInfo ist das FHEM Modul um Feinstaub-, Temperatur- und
    Luftfeuchtichkeitswerte von den selbstbau Feinstaub Sensoren von
    <a href="http://Luftdaten.info"><u>Luftdaten.info</u></a> auszulesen.<br>
    Dabei k&ouml;nnen die Werte direkt vom Server oder auch lokal abgefragt
    werden.<br>
    Bei einer lokalen Abfrage werden durch eine
    <a href="https://forum.fhem.de/index.php/topic,73879">
      <u>alternative Firmware</u>
    </a>
     noch weitere Sensoren unterstützt.<br>
    <br>
    <b>Vorraussetzungen</b>
    <ul>
      Das Perl-Modul "JSON" wird ben&ouml;tigt.<br>
      Unter Debian (basierten) System, kann dies mittels
      <code>"apt-get install libjson-perl"</code> installiert werden.
    </ul>
    <br>
    <a name="LuftdatenInfodefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; LuftdanteInfo2 remote
          &lt;SENSORID1&gt; [&lt;SENSORID2&gt; ..]<br>
        define &lt;name&gt; LuftdanteInfo2 local &lt;IP&gt;<br>
        define &lt;name&gt; LuftdanteInfo2
          slave &lt;master-name&gt; &lt;sensor1 sensor2 ...&gt;
      </code><br>
      F&uuml;r eine Abfrage der Daten vom Server müssem alle betroffenenen
      SensorIDs angegeben werden. Die IDs vom SDS01 stehen rechts auf der Seite
      <a href="http://maps.luftdaten.info/">
        <u>http://maps.luftdaten.info/</u>
      </a>
      . Die DHT22 SensorID entspricht normalerweise der SDS011 SensorID + 1.
      Bei einer Abfrage werden die die Positionsangaben verglichen und bei
      einer Abweichung eine Meldung ins Log geschrieben.<br>
      F&uuml;r eine lokale Abfrage der Daten muss die IP Addresse oder der
      Hostname angegeben werden.<br>
      Werden mehrere ähnliche Sensoren betrieben lassen sich die doppelten
      Werte in einem anderen Gerät geschrieben werden.
    </ul><br>
    <a name="LuftdatenInfoset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>statusRequest</code><br>
        Startet eine Abfrage der Daten.
      </li>
    </ul><br>
    <a name="LuftdatenInfoget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>sensors</code><br>
        Listet alle Sensoren auf.
      </li>
    </ul><br>
    <a name="LuftdatenInforeadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>altitude</code><br>
        Höhe über NN
      </li>
      <li>
        <code>humidity</code><br>
        Relative Luftfeuchtgkeit in %
      </li>
      <li>
        <code>illuminanceFull</code><br>
        Helligkeit des vollen Bereich in lux
      </li>
      <li>
        <code>illuminanceIR</code><br>
        Helligkeit des IR Bereich in lux
      </li>
      <li>
        <code>illuminanceUV</code><br>
        Helligkeit des UV Bereich in lux
      </li>
      <li>
        <code>illuminanceVisible</code><br>
        Helligkeit des sichtbaren Bereich in lux
      </li>
      <li>
        <code>latitude</code><br>
        Längengrad
      </li>
      <li>
        <code>location</code><br>
        Standort als "Postleitzahl Ort"<br>
        Nur bei remote Abfrage verf&uuml;gbar.
      </li>
      <li>
        <code>longitude</code><br>
        Breitengrad
      </li>
      <li>
        <code>PM1</code><br>
        Menge der Partikel mit einem Durchmesser von weniger als 1 µm in µg/m³
      </li>
      <li>
        <code>PM2.5</code><br>
        Menge der Partikel mit einem Durchmesser von weniger als 2.5 µm in µg/m³
      </li>
      <li>
        <code>PM10</code><br>
        Menge der Partikel mit einem Durchmesser von weniger als 10 µm in µg/m³
      </li>
      <li>
        <code>pressure</code><br>
        Luftdruck in hPa
      </li>
      <li>
        <code>pressureNN</code><br>
        Luftdruck für Normal Null in hPa<br>
        Wird bei aktivem Luftdruck- und Temperatursensor berechnet, sofern sich
        der Sensor nicht auf Normal Null befindet.<br>
        Hierzu ist die Höhe, kann über Kartendienste oder SmartPhone ermittelt
        werden, auf der Konfigurationsseite anzugeben.
      </li>
      <li>
        <code>signal</code><br>
        WLAN Signalst&auml;rke in dBm<br>
        Nur bei local Abfrage verf&uuml;gbar.
      </li>
      <li>
        <code>temperature</code><br>
        Temperatur in °C
      </li>
      <li>
        <code>UVIntensity</code><br>
        UV Intensität in W
      </li>
      <li>
        <code>UVRisk</code><br>
        UV Risiko von 1 bis 5
      </li>
    </ul><br>
    <a name="LuftdatenInfoattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>disable 1</code><br>
        Es werden keine Abfragen mehr gestartet.
      </li>
      <li>
        <a href="#disabledForIntervals">
          <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
        </a>
      </li>
      <li>
        <code>interval &lt;seconds&gt;</code><br>
        Intervall in Sekunden in dem Abfragen durchgef&uuml;hrt werden.<br>
        Der Vorgabe- und Mindestwert betr&auml;gt 300 Sekunden.
      </li>
      <li>
        <code>timeout &lt;seconds&gt;</code><br>
        Timeout in Sekunden für die Abfragen.<br>
        Der Vorgabe- und Mindestwert betr&auml;gt 5 Sekunden.
      </li>
    </ul>
  </ul>
</div>

=end html_DE
=cut
