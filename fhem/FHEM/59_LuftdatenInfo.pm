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
  use strict;
  use warnings;

  use HttpUtils;

# forward declarations ########################################################
sub LuftdatenInfo_Initialize($);

sub LuftdatenInfo_Define($$);
sub LuftdatenInfo_Undefine($$);
sub LuftdatenInfo_Set($@);
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
  $hash->{AttrFn}   = $TYPE."_Attr";

  $hash->{AttrList} = ""
    . "disable:1,0 "
    . "disabledForIntervals "
    . "interval "
    . $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub LuftdatenInfo_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, @id) = split(/[\s]+/, $def);
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

  delete($hash->{READINGS});
  delete($hash->{SENSORID1});
  delete($hash->{SENSORID2});
  delete($hash->{ADDRESS});

  if(looks_like_number($id[0])){
    return("Usage: define <name> $TYPE <SDS011sensorID> [<DHT22sensorID>]")
      if(@id != 1 && @id != 2);

    $hash->{SENSORIDS} = (@id == 2) ? "explicit" : "implicit";

    $id[1] = $id[0] + 1 unless($id[1]);

    $hash->{SENSORID1} = $id[0];
    $hash->{SENSORID2} = $id[1];
    $hash->{CONNECTION} = "remote";
  }
  else{
    return("Usage: define <name> $TYPE <ip>")
      if(@id != 1);

    $hash->{ADDRESS} = $id[0];
    $hash->{CONNECTION} = "local";
  }

  my $minInterval = 300;
  my $interval = AttrVal($SELF, "interval", $minInterval);
  $interval = $minInterval unless(looks_like_number($interval));
  $interval = $minInterval if($interval < $minInterval);
  my $minTimeout = 5;
  my $timeout = AttrVal($SELF, "timeout", $minTimeout);
  $timeout = $minTimeout unless(looks_like_number($timeout));
  $timeout = $minTimeout if($timeout < $minTimeout);

  $hash->{INTERVAL} = $interval;
  $hash->{TIMEOUT} = $timeout;

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
    my $minInterval = 300;
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
  my ($hash, $id) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $timeout = $hash->{TIMEOUT};
  my $connection = $hash->{CONNECTION};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_GetHttpResponse");

  if($connection eq "remote"){
    my $param = {
      url      => "http://api.luftdaten.info/v1/sensor/$id/",
      timeout  => $timeout,
      hash     => $hash,
      method   => "GET",
      header   => "Accept: application/json",
      callback => \&LuftdatenInfo_ParseHttpResponse,
    };

    HttpUtils_NonblockingGet($param);
  }
  elsif($connection eq "local"){
    my $param = {
      url      => "http://".$id."/data.json",
      timeout  => $timeout,
      hash     => $hash,
      method   => "GET",
      header   => "Accept: application/json",
      callback => \&LuftdatenInfo_ParseHttpResponse,
    };

    HttpUtils_NonblockingGet($param);
  }
}

sub LuftdatenInfo_ParseHttpResponse($) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $connection = $hash->{CONNECTION};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_ParseHttpResponse");

  if($err ne ""){
    Log3($SELF, 2, "$TYPE ($SELF) - error while request: $err");

    readingsSingleUpdate($hash, "state", "error", 1);
  }
  elsif($data !~ /^\[.*\]$/s){
    Log3(
      $SELF, 2, "$TYPE ($SELF) - error while request: malformed JSON string"
    );

    readingsSingleUpdate($hash, "state", "error", 1);
  }
  elsif($data eq "[]"){
    if(   index($param->{url}, $hash->{SENSORID2}) > -1
       && InternalVal($SELF, "SENSORIDS", "implicit") eq "implicit"
    ){
      delete($hash->{SENSORID2});

      Log3($SELF, 2, "$TYPE ($SELF) - no second sensor found");
    }
    else{
      Log3($SELF, 2, "$TYPE ($SELF) - no data returned");

      readingsSingleUpdate($hash, "state", "no data", 1);
    }
  }
  elsif($data ne ""){
    Log3 $SELF, 4, "$TYPE ($SELF) - returned data: $data";

    $data = encode('UTF-8', $data);
    $data = JSON->new->utf8->decode($data);

    if($param->{url} =~ m/openstreetmap/){
      my $address = $data->{address};

      readingsSingleUpdate(
          $hash, "location"
        , "$address->{postcode} "
        . ($address->{city} ? $address->{city} : $address->{town})
        , 1
      );
    }
    elsif($connection eq "remote"){
      my $sensor = @{$data}[-1];
      my $sensor_type = $sensor->{sensor}{sensor_type}{name};
      my $timestamp = $sensor->{timestamp};

      return unless($timestamp ge ReadingsVal($SELF, ".timestamp", ""));

      Log3 $SELF, 5, "$TYPE ($SELF) - returned data is newer than readings";

      if($sensor_type eq "SDS011"){
        Log3 $SELF, 5, "$TYPE ($SELF) - parsing $sensor_type data";

        my $latitude = $sensor->{location}{latitude};
        my $longitude = $sensor->{location}{longitude};

        unless(ReadingsVal($SELF, "location", undef)){
          my $param = {
            url      =>
                "http://nominatim.openstreetmap.org/reverse?"
              . "format=json&lat=$latitude&lon=$longitude"
            ,
            timeout  => $hash->{TIMEOUT},
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&LuftdatenInfo_ParseHttpResponse,
          };

          HttpUtils_NonblockingGet($param);
        }

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, ".timestamp", $timestamp);

        foreach (@{$sensor->{sensordatavalues}}){
          if($_->{value_type} eq "P1"){
            readingsBulkUpdate($hash, "PM10", $_->{value});
          }
          elsif($_->{value_type} eq "P2"){
            readingsBulkUpdate($hash, "PM2.5", $_->{value});
          }
        }

        readingsBulkUpdateIfChanged($hash, "latitude", $latitude);
        readingsBulkUpdateIfChanged($hash, "longitude", $longitude);
        readingsBulkUpdate($hash, "state", "active");
        readingsEndUpdate($hash, 1);

        my $SENSORID2 = InternalVal($SELF, "SENSORID2", undef);

        LuftdatenInfo_GetHttpResponse($hash, $SENSORID2)
          if(defined($SENSORID2));
      }
      elsif($sensor_type ne "SDS011"){
        Log3 $SELF, 5, "$TYPE ($SELF) - parsing $sensor_type data";

        if(   $sensor->{location}{latitude} ne
              ReadingsVal($SELF, "latitude", "")
           || $sensor->{location}{longitude} ne
              ReadingsVal($SELF, "longitude", "")
        ){
          delete($hash->{SENSORID2});

          Log3(
              $SELF, 2
            , "$TYPE ($SELF) - "
            . "$sensor_type position differs from SDS011 position"
          );

          return;
        }
        else{
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, ".timestamp", $timestamp);

          foreach (@{$sensor->{sensordatavalues}}){
            $_->{value} =~ m/^(\S+)(\s|$)/;

            if($_->{value_type} =~ /temperature$/){
              readingsBulkUpdate($hash, "temperature", $1);
            }
            elsif($_->{value_type} =~ /humidity$/){
              readingsBulkUpdate($hash, "humidity", $1);
            }
            elsif($_->{value_type} =~ /pressure$/){
              readingsBulkUpdate($hash, "pressure", $1);
            }
          }

          readingsBulkUpdate($hash, "state", "active");
          readingsEndUpdate($hash, 1);
        }
      }
    }
    elsif($connection eq "local"){
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged(
        $hash, "softwareVersion", $data->{software_version}
      );

      foreach (@{$data->{sensordatavalues}}){
        $_->{value} =~ m/^(\S+)(\s|$)/;

        if($_->{value_type} =~ /temperature$/){
          readingsBulkUpdate($hash, "temperature", $1);
        }
        elsif($_->{value_type} =~ /humidity$/){
          readingsBulkUpdate($hash, "humidity", $1);
        }
        elsif($_->{value_type} =~ /pressure$/){
          readingsBulkUpdate($hash, "pressure", $1);
        }
        elsif($_->{value_type} eq "SDS_P1"){
          readingsBulkUpdate($hash, "PM10", $1);
        }
        elsif($_->{value_type} eq "SDS_P2"){
          readingsBulkUpdate($hash, "PM2.5", $1);
        }
        elsif($_->{value_type} eq "signal"){
          readingsBulkUpdate($hash, "signal", $1);
        }
      }

      readingsBulkUpdate($hash, "state", "active");
      readingsEndUpdate($hash, 1);
    }
  }

  return;
}

# module Fn ###################################################################
sub LuftdatenInfo_statusRequest($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $interval = $hash->{INTERVAL};
  my $connection = $hash->{CONNECTION};

  Log3($SELF, 5, "$TYPE ($SELF) - entering LuftdatenInfo_statusRequest");

  RemoveInternalTimer($hash);

  return if(IsDisabled($SELF));

  InternalTimer(
    gettimeofday() + $interval, "LuftdatenInfo_statusRequest", $hash
  );

  if($connection eq "remote"){
    LuftdatenInfo_GetHttpResponse($hash, $hash->{SENSORID1});
  }
  elsif($connection eq "local"){
    LuftdatenInfo_GetHttpResponse($hash, $hash->{ADDRESS});
  }

  return;
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
    LuftdatenInfo is the FHEM module to read 	particulate matter, temperature
    and humidity values ​​from the self-assembly particulate matter sensors
    from <a href="http://Luftdaten.info"><u>Luftdaten.info</u></a>.<br>
    The values ​​can be queried directly from the server or locally.<br>
    A local query should only be made if the sensor is NOT sendig data to the
    server, otherwise the sensor may block and need to be restarted.<br>
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
        define &lt;name&gt; LuftdatenInfo
        (&lt;SDS011sensorID&gt;
         [&lt;DHT22sensorID&gt;|&lt;BME280sensorID&gt;]
        |&lt;ip&gt;)
      </code><br>
      To query the data from the server, the SDS011 SensorID must be
      specified.<br>
      The SensorID stands right at
      <a href="http://maps.luftdaten.info/">
        <u>http://maps.luftdaten.info/</u>
      </a>
      . The DHT22 SensorID is usually the SDS011 SensorID + 1 and does not have
      to be specified explicitly. While parsing the data the location values
      from both sensors will be compared and a message will be written into the
      log if they differ.<br>
      For a local query of the data, the IP address or hostname must be
      specified.
    </ul><br>
    <a name="LuftdatenInfoset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>statusRequest</code><br>
        Starts a status request.
      </li>
    </ul><br>
    <a name="LuftdatenInforeadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>PM10</code><br>
        Quantity of particles with a diameter of less than 10 μm in μg / m³
      </li>
      <li>
        <code>PM2.5</code><br>
        Quantity of particles with a diameter of less than 2.5 μm in μg / m³
      </li>
      <li>
        <code>temperature</code><br>
        Temperature in °C
      </li>
      <li>
        <code>humidity</code><br>
        Relative humidity in%
      </li>
      <li>
        <code>pressure</code><br>
        Pressure in hPa<br>
        Only available with BME280 sensor.
      </li>
      <li>
        <code>latitude</code><br>
        latitude<br>
        Only available with remote query.
      </li>
      <li>
        <code>location</code><br>
        location as "postcode city"<br>
        Only available with remote query.
      </li>
      <li>
        <code>longitude</code><br>
        longitude<br>
        Only available with remote query.
      </li>
      <li>
        <code>signal</code><br>
        WLAN signal strength in dBm<br>
        Only available with local query.
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
    Eine lokale Abfrage sollte nur erfolgen, wenn der Sensor NICHT an den
    Server sendet, sonst kann es passieren, dass der Sensor blockiert und
    neugestartet werden muss.<br>
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
        define &lt;name&gt; LuftdatenInfo
        (&lt;SDS011sensorID&gt;
         [&lt;DHT22sensorID&gt;|&lt;BME280sensorID&gt;]
        |&lt;ip&gt;)
      </code><br>
      F&uuml;r eine Abfrage der Daten vom Server muss die SensorID von dem
      SDS011 Sensor angegeben werden. Diese steht rechts auf der Seite
      <a href="http://maps.luftdaten.info/">
        <u>http://maps.luftdaten.info/</u>
      </a>
      . Die DHT22 SensorID entspricht normalerweise der SDS011 SensorID + 1 und
      muss nicht explizit mit angegeben werden. Bei einer Abfrage werden die
      beiden Positionsangaben verglichen und bei Abweichung eine Meldung ins
      Log geschrieben.<br>
      F&uuml;r eine lokale Abfrage der Daten muss die IP Addresse oder der
      Hostname angegeben werden.
    </ul><br>
    <a name="LuftdatenInfoset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>statusRequest</code><br>
        Startet eine Abfrage der Daten.
      </li>
    </ul><br>
    <a name="LuftdatenInforeadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>PM10</code><br>
        Menge der Partikel mit einem Durchmesser von weniger als 10 µm in µg/m³
      </li>
      <li>
        <code>PM2.5</code><br>
        Menge der Partikel mit einem Durchmesser von weniger als 2.5 µm in µg/m³
      </li>
      <li>
        <code>temperature</code><br>
        Temperatur in °C
      </li>
      <li>
        <code>humidity</code><br>
        Relative Luftfeuchtgkeit in %
      </li>
      <li>
        <code>pressure</code><br>
        Luftdruck in hPa<br>
        Nur bei einem BME280 Sensor verf&uuml;gbar.
      </li>
      <li>
        <code>latitude</code><br>
        Breitengrad<br>
        Nur bei remote Abfrage verf&uuml;gbar.
      </li>
      <li>
        <code>location</code><br>
        Standort als "Postleitzahl Ort"<br>
        Nur bei remote Abfrage verf&uuml;gbar.
      </li>
      <li>
        <code>longitude</code><br>
        L&auml;ngengrad<br>
        Nur bei remote Abfrage verf&uuml;gbar.
      </li>
      <li>
        <code>signal</code><br>
        WLAN Signalst&auml;rke in dBm<br>
        Nur bei local Abfrage verf&uuml;gbar.
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
