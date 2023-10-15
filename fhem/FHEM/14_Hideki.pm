##############################################
# $Id$
# The file is taken from the SIGNALduino project
# see http://www.fhemwiki.de/wiki/SIGNALduino
# and was modified by a few additions
# to support Hideki Sensors
# S. Butzek, HJGode, Ralf9 2015-2017
# S. Butzek 2018-2022
#
# It is part of the SIGNALduinos project.
# https://github.com/RFD-FHEM/RFFHEM | see http://www.fhemwiki.de/wiki/SIGNALduino
#
# The module was modified by a few additions. support Hideki Sensors
# 2015-2017   S. Butzek, hjgode, Ralf9
# 2018-       S. Butzek, elektron-bbs, HomeAutoUser, Ralf9
#
# 20171129 - hjgode, changed the way crc and decrypt is used

package main;
#use version 0.77; our $VERSION = version->declare('v3.4.3');


use strict;
use warnings;
use POSIX;
use FHEM::Meta;
use Carp;

eval {use Data::Dumper qw(Dumper);1};
#use Data::Dumper;



#####################################
sub Hideki_Initialize {
  my ($hash) = @_;
  carp "Hideki_Initialize, hash failed" if (!$hash);

  $hash->{Match}     = qr/^P12#75[A-F0-9]{14,30}/;   # Laenge (Anhahl nibbles nach 0x75 )noch genauer spezifizieren
  $hash->{DefFn}     = \&Hideki_Define;
  $hash->{UndefFn}   = \&Hideki_Undef;
  $hash->{ParseFn}   = \&Hideki_Parse;
  $hash->{AttrList}  = 'do_not_notify:0,1 showtime:0,1'
                       .' ignore:0,1'
                       .' windDirCorr windSpeedCorr'
                       ." $readingFnAttributes";
  $hash->{AutoCreate}=
        { "Hideki.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };

  return FHEM::Meta::InitMod( __FILE__, $hash );
}


my %comfortLevel = (
      0 => q[Hum. OK. Temp. uncomfortable (>24.9 or <20)],
      1 => q[Wet. More than 69% RHWet. More than 69% RH],
      2 => q[Dry. Less than 40% RH],
      3 => q[Temp. and Hum. comfortable]
);

my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");

my %allSensorTypes;
%allSensorTypes = (
  30 => {
    'temperature'      => \&getTemperature,
    'channel'          => \&getChannel,
    'battery'          => \&getBattery,
    'humidity'         => \&getHumidity,
    'comfort_level'    => \&getComfort,
    'package_number'   => \&getCount,
    '_eval'            => {
                            'batteryState'  => sub { return $_[0]->{battery} },
                            'state'         => sub { return qq/T: $_[0]->{temperature} H: $_[0]->{humidity}/ }
                          }
  },
  31 => {
    'temperature'      => \&getTemperature,
    'channel'          => \&getChannel,
    'battery'          => \&getBattery,
    'package_number'   => \&getCount,
    '_eval'            => {
                            'batteryState'     => sub { return $_[0]->{battery} },
                            'state'            => sub { return qq/T: $_[0]->{temperature}/ }
                          }
  },
  14 => {
    'rain'             => \&getRain,
    'channel'          => \&getChannel,
    'battery'          => \&getBattery,
    'package_number'   => \&getCount,
    '_eval'            => {
                            'batteryState'     => sub { return $_[0]->{battery} },
                            'state'            => sub { return qq/R: $_[0]->{rain}/ }
                          }
  },
  12 => {
    'temperature'           => \&getTemperature,
    'channel'               => \&getChannel,
    'battery'               => \&getBattery,
    'package_number'        => \&getCount,
    'windChill'             => \&getWindchill,
    'windDirection'         => \&getWinddir,
    'windDirectionDegree'   => \&getWinddirdeg,
    'windDirectionText'     => \&getWinddirtext,
    'windGust'              => \&getWindgust,
    'windSpeed'             => \&getWindspeed,
    '_eval'                 => {
                                 'batteryState'     => sub { return $_[0]->{battery} },
                                 '_corrWindSpeed'   => \&correctWindValues,
                                 'state'            => sub { return qq/T: $_[0]->{temperature}  Ws: $_[0]->{windSpeed}  Wg: $_[0]->{windGust}  Wd: $_[0]->{windDirectionText}/ }
                               },
  },
  13 => {
    'temperature'      => \&getTemperature,
    'channel'          => \&getChannel,
    'battery'          => \&getBattery,
    'package_number'   => \&getCount,
    '_eval'            => {
                            'batteryState'     => sub { return $_[0]->{battery} },
                            'state'            => sub { return qq/T: $_[0]->{temperature}/ }
                          },
    'debug'           => sub { return q[type currently not full supported, please report sensor information] }
  }
);


#####################################
sub Hideki_Define {
  my ($hash, $def) = @_;
  carp qq[Hideki_Define, too few arguments ($hash, $def)] if @_ < 2;
  (ref $hash ne 'HASH') // return q[no hash provided];

  my @a = split("[ \t][ \t]*", $def);
  return "wrong syntax: define <name> Hideki <code>".int(@a)
    if(int(@a) < 3);

  $hash->{CODE}    = $a[2];
  $hash->{lastMSG} =  '';

  my $name= $hash->{NAME};
  $modules{Hideki}{defptr}{$a[2]} = $hash;

  return;
}

#####################################
sub Hideki_Undef {
  my ($hash, $name) = @_;
  carp qq[Hideki_Undef, too few arguments ($hash, $name)] if @_ < 2;
  (ref $hash ne 'HASH') // return q[no hash provided];

  delete($modules{Hideki}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  return;
}


#####################################
sub Hideki_Parse {
  my ($iohash,$msg) = @_;
  carp qq[Hideki_Parse, too few arguments ($iohash, $msg)] if @_ < 2;
  (ref $iohash ne 'HASH') // return q[no hash provided];

  my (undef ,$rawData) = split(/#/,$msg);
  my $ioname = $iohash->{NAME};
  my @a = split(//, $msg);
  Log3 $iohash, 4, "$ioname Hideki_Parse: incomming $msg";

  my @decodedData;
  my $crc1crc2OK = 0;
  ($crc1crc2OK, @decodedData) = decryptAndCheck($iohash, $rawData); # use unencrypted rawdata

  if ($crc1crc2OK == 0) {
    return '';  #crc1 or crc2 failed
  }

  # decrypt and decodedBytes are now done with decryptAndCheck
  my $decodedString = join '', unpack('H*', pack('C*',@decodedData)); # get hex string
  Log3 $iohash, 4, "$ioname Hideki_Parse: raw=$rawData, decoded=$decodedString";

  if (!@decodedData) {
    Log3 $iohash, 4, "$ioname Hideki_Parse: decrypt failed";
    return '';
  }

  Log3 $iohash, 5, "$ioname Hideki_Parse: getSensorType for ".$decodedData[3];
  my $sensorTyp=getSensorType(\@decodedData);
  Log3 $iohash, 4, "$ioname Hideki_Parse: SensorTyp = $sensorTyp decodedString = $decodedString";

  my $id=substr($decodedString,2,2);      # get the random id from the data
  my $deviceCode;
  my $model= qq[Hideki_$sensorTyp];

  ## 1. Detect what type of sensor we have, then call specific function to decode
  if ( !exists $allSensorTypes{$sensorTyp} ) {
    Log3 $iohash, 4, qq[$ioname Sensor type $sensorTyp not supported, please report sensor information!];
    #return q[];
  };

  # Build sensordecoder based on type  
  my $sensorDecoder = $allSensorTypes{$sensorTyp};

  # Get values from decoder
  my %sensorData;
  foreach my $key ( keys %{ $sensorDecoder } )
  {
    next if (ref $sensorDecoder->{$key} ne q[CODE]);
    $sensorData{$key} = $sensorDecoder->{$key}->(\@decodedData);
  }

  # Log received values
  my $logstr = q{};
  while( my ($key, $value) =  each(%sensorData) ) {
    next if ($key =~ /^_/x );
    $logstr .= qq[, $key=$value];
  }
  Log3 $iohash, 4, qq[$ioname decoder Hideki protocol model=$model, sensor id=$id].$logstr;

  # Get devicecode
  my $longids = AttrVal($iohash->{NAME},'longids',0);
  if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/x)))
  {
    $deviceCode=$model . "_" . $id . "." . $sensorData{channel};
    Log3 $iohash,4, "$ioname Hideki_Parse: using longid: $longids model: $model";
  } else {
    $deviceCode = $model . "_" . $sensorData{channel};
  }

  Log3 $iohash, 5, "$ioname Hideki_Parse deviceCode: $deviceCode";

  # Check if device is defined
  my $def = $modules{Hideki}{defptr}{$iohash->{NAME} . "." . $deviceCode};
  $def = $modules{Hideki}{defptr}{$deviceCode} if(!$def);
  if(!$def) {
    Log3 $iohash, 1, "$ioname Hideki: UNDEFINED sensor $deviceCode detected, code $msg";
    return "UNDEFINED $deviceCode Hideki $deviceCode";
  }

  # Check if device will receive update
  my $hash = $def;
  my $name = $hash->{NAME};
  return "" if(IsIgnored($name));
  $sensorData{_NAME} = $hash->{NAME};

  if (!defined(AttrVal($name,"event-min-interval",undef)))
  {
    my $minsecs = AttrVal($ioname,'minsecs',0);
    if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
      Log3 $name, 4, "$name Hideki_Parse: $deviceCode Dropped ($decodedString) due to short time. minsecs=$minsecs";
        return '';
    }
  }
  # Update existing device
  $hash->{lastReceive} = time();
  $def->{lastMSG} = $decodedString;


  # Do some late evaluations bevore update readings
  foreach my $key (sort keys %{ $sensorDecoder->{_eval} }) {
    $sensorData{$key} = $sensorDecoder->{_eval}{$key}->(\%sensorData);
  }

  readingsBeginUpdate($hash);
  while ( my ($key, $value) =  each(%sensorData) ) {
    next if ($key =~ /^[_\.]/x );
    readingsBulkUpdate($hash,$key,$value);
  }
  readingsEndUpdate($hash, 1); # Notify is done by Dispatch

  return $name;
}

#####################################
# decryptAndCheck
# input is raw data (array of bytes)
# output is true if check1 and check2 OK
# data will then hold the decrypted data
sub decryptAndCheck {
  carp qq[decryptAndCheck, too few arguments (iohash, rawData)] if @_ < 2;

  my $iohash = shift;
  my $rawData = shift;

  my $name = $iohash->{NAME};
  my $cs1=0; #will be zero for xor over all (bytes[2]>>1)&0x1F except first byte (always 0x75)
  my $cs2=0;
  my $i;
  my @data;
  @data=map { hex($_) } ($rawData =~ /(..)/gx); #byte array from raw hex data string

  #/* Decrypt raw received data byte */ BYTE DecryptByte(BYTE b) { return b ^ (b << 1); }
  my $count=( ($data[2] ^ ($data[2]<<1)) >>1 ) & 0x1f;
  my $L = scalar @data;
  if ($L <= $count+2) {
    Log3 $iohash, 4, "$name Hideki_crc: rawdata=$rawData to short, count=$count data length=$L";
    return (0,@data);
  }

  if($data[0] != 0x75) {
    Log3 $iohash, 4, "$name Hideki_Parse: rawData=$rawData is not Hideki";
    return (0,@data);
  }

  #iterate over data only, first byte is 0x75 always
  # read bytes 1 to n-2 , just before checksum
  for my $i (1..$count+1) {
    $cs1 ^= $data[$i]; # calc first chksum
    $cs2 = Hideki_SecondCheck($data[$i] ^ $cs2);
    $data[$i] ^= (($data[$i] << 1) & 0xFF); # decrypt byte at $i without overflow
  }

  $count += 2;
  if ($cs1 != 0 || $cs2 != $data[$count]) {
    Log3 $iohash, 4, "$name Hideki crcCheck FAILED: cs1 / cs2/checksum2 $cs1 / $cs2/$data[$count], rawData=$rawData, count+2=$count, length=$L";
    return (0, @data);
  } else {
    Log3 $iohash, 4, "$name Hideki crcCheck ok: cs1/cs2 $cs1/$cs2, rawData=$rawData, count+2=$count, length=$L";
  }
  return (1, @data);
}

#####################################
# /* The second checksum. Input is OldChecksum^NewByte */
sub Hideki_SecondCheck {
    carp qq[Hideki_SecondCheck, too few arguments] if @_ < 1;
    my $b = shift;

    my $c = 0;
    if (($b & 0x80) == 0x80){
        $b^=0x95;
    }
    $c = $b^($b>>1);
    if (($b & 1) == 1){
        $c^=0x5f;
    }
    if (($c & 1) == 1){
        $b^=0x5f;
    }
    return ($b^($c>>1));
}


#####################################
# return decoded sensor type
# in: one byte
# out: one byte
# Der Typ eines Sensors steckt in Byte 3:
# Byte3 & 0x1F  Device
# 0x0C        Anemometer
# 0x0D        UV sensor
# 0x0E        Rain level meter
# 0x1E        Thermo/hygro-sensor
# 0x1F        Thermo sensor
sub getSensorType {
  my $decodedData= shift // carp q[no bytes specified];

  return $decodedData->[3] & 0x1F;  
}


#####################################
# getters for serval values from the decrypted hexdata
# input:hashref of hex value of received message
# output specific value

sub getTemperature {
  my $decodedData= shift // carp q[no bytes specified];
  my $temp = 100 * ($decodedData->[5] & 0x0f) + 10 * ($decodedData->[4] >> 4) + ($decodedData->[4] & 0x0f);
  ## // temp is negative?
  if (!($decodedData->[5] & 0x80)) {  $temp = -$temp;  }

  return $temp = $temp / 10;
}

sub getChannel {
  my $decodedData = shift // carp q[no bytes specified];
  my $channel = $decodedData->[1] >> 5;

  if ( $channel >= 5 ) { $channel--; }

  return $channel
}

sub getHumidity {
  my $decodedData = shift // carp q[no bytes specified];

  return  10 * ($decodedData->[6] >> 4) + ($decodedData->[6] & 0x0f);
}

sub getBattery {
  my $decodedData = shift // carp q[no bytes specified];

  return ($decodedData->[2] >> 6 == 3) ? 'ok' : 'low';       # decode battery
}

sub getCount {
  my $decodedData = shift // carp q[no bytes specified];

  return $decodedData->[3] >> 6;    # verifiziert, MSG_Counter
}

sub getComfort {
  my $decodedData = shift // carp q[no bytes specified];
  my $comfortVal = ($decodedData->[7] >> 2 & 0x03);   # comfort level

  if ( !exists $comfortLevel{$comfortVal} ) {  return $comfortVal; };

  return $comfortLevel{$comfortVal};
}

sub getRain {
  my $decodedData = shift // carp q[no bytes specified];

  return ($decodedData->[4] + $decodedData->[5]*0xff)*0.7;
}

sub getWindchill {
  my $decodedData = shift // carp q[no bytes specified];

  my $windchill = 100 * ($decodedData->[7] & 0x0f) + 10 * ($decodedData->[6] >> 4) + ($decodedData->[6] & 0x0f);
  ## windchill is negative?
  if (!($decodedData->[7] & 0x80)) {
    $windchill = -$windchill;
  }

  return $windchill / 10;
}

sub getWindspeed {
  my $decodedData = shift // carp q[no bytes specified];

  my $windspeed = ($decodedData->[9] & 0x0f ) * 100 + ($decodedData->[8] >> 4) * 10 + ($decodedData->[8] & 0x0f);

  return sprintf("%.2f", $windspeed);
}

sub getWindgust {
  my $decodedData = shift // carp q[no bytes specified];

  my $windgust = ($decodedData->[10] >> 4) * 100 + ($decodedData->[10] & 0x0f) * 10 + ($decodedData->[9] >> 4);

  return sprintf("%.2f", $windgust);
}


sub getWinddir {
  my $decodedData = shift // carp q[no bytes specified];
  my @wd=(0, 15, 13, 14, 9, 10, 12, 11, 1, 2, 4, 3, 8, 7, 5, 6);

  return $wd[$decodedData->[11] >> 4];
}

sub getWinddirtext {
  my $decodedData = shift // carp q[no bytes specified];

  return $winddir_name[getWinddir($decodedData)];
}


sub getWinddirdeg {
  my $decodedData = shift // carp q[no bytes specified];
  return getWinddir($decodedData) * 22.5;
}

#####################################
# correct wind values if correction attributes are set
# input: hashref with prepared values from sensors
# output undef

sub correctWindValues {
  my $sensorValues = shift // carp q[no values from sensor specified];

  if (! IsDevice($sensorValues->{_NAME}) ) { carp q[no sensorname provided]; }
  my $windSpeedCorr = AttrVal($sensorValues->{_NAME},'windSpeedCorr',1);
  my $windDirCorr = AttrVal($sensorValues->{_NAME},'windDirCorr',0);

  if ($windSpeedCorr > 0) {
    $sensorValues->{windSpeed} = sprintf q[%.2f], $sensorValues->{windSpeed} * $windSpeedCorr ;
    $sensorValues->{windGust}  = sprintf q[%.2f], $sensorValues->{windGust} * $windSpeedCorr ;
    Log3 $sensorValues->{_NAME}, 5, qq[$sensorValues->{_NAME} correctWindValues: WindSpeedCorr factor=$windSpeedCorr];
  }

  if ($windDirCorr > 0) {
    $sensorValues->{windDirection} += $windDirCorr;
    $sensorValues->{windDirection} &= 15;
    $sensorValues->{windDirectionText} = $winddir_name[$sensorValues->{windDirection}];
    $sensorValues->{windDirectionDegree} = $sensorValues->{windDirection} * 22.5;

    Log3 $sensorValues->{_NAME}, 5, qq[$sensorValues->{_NAME} correctWindValues: windDirCorr=$windDirCorr];
  }

  return;
}



1;

=pod
=item summary    Supports various rf sensors with hideki protocol
=item summary_DE Unterst&uumltzt verschiedenen Funksensoren mit hideki Protokol
=begin html

<a name="Hideki"></a>
<h3>Hideki</h3>
<ul>
  The Hideki module is a module for decoding weather sensors, which use the hideki protocol. Known brands are Bresser, Cresta, TFA and Hama.
  <br><br>

  <a name="Hideki_define"></a>
  <b>Supported Brands</b>
  <ul>
    <li>Arduinos with remote Sensor lib from Randy Simons</li>
    <li>Bresser</li>
    <li>Cresta</li>
    <li>Hama</li>
    <li>Hideki (Anemometer | UV sensor | Rain level meter | Thermo/hygro-sensor)</li>
    <li>TFA Dostman</li>
    <li>all other devices, which use the Hideki protocol</li>
  </ul>
  Please note, currently temp/hum devices are implemented. Please report data for other sensortypes.<br><br>

  <a name="Hideki_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Hideki &lt;code&gt; </code> <br>

    <br>
    <li>&lt;code&gt; is the address of the sensor device and
  is build by the sensor type and the channelnumber (1 to 5) or if the attribute longid is specfied an autogenerated address build when inserting
  the battery (this adress will change every time changing the battery).</li><br>

  <li>If autocreate is enabled, the device will be defined via autocreate. This is also the preferred mode of defining such a device.</li><br><br>

  </ul>
  <a name="Hideki_readings"></a>
  <b>Generated readings</b>
  <ul>
    <li>battery & batteryState (ok or low)</li>
    <li>channel (The Channelnumber (number if)</li>
    <li>humidity (0-100)</li>
    <li>state (T:x.xx H:y B:z)</li>
    <li>temperature (&deg;C)</li>
    <br><i>- Hideki only -</i>
    <li>comfort_level (Status: Humidity OK... , Wet. More than 69% RH, Dry. Less than 40% RH, Temperature and humidity comfortable)</li>
    <li>package_number (reflect the package number in the stream starting at 1)</li><br>
  </ul>


  <a name="Hideki_unset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="Hideki_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Hideki_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="windDirCorr"></a>windDirCorr<br>
    correction value of your displayed wind direction deztimal degree value. The correction value is added to the measured direction in dgrees.<br>
    Example value: 5<br>
    Default value: 0<br>
    </li>
    <li><a name="windSpeedCorr"></a>windSpeedCorr<br>
    correction value of your displayed wind speed as floatingpoint value. The measured speed is multiplied with the specified value. The value 0 disables the feature.<br>
    Example value: 1.25<br>
    Default value: 1<br>
    </li>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="Hideki"></a>
<h3>Hideki</h3>
<ul>
  Das Hideki module dekodiert empfangene Nachrichten von Wettersensoren, welche das Hideki Protokoll verwenden. 
  <br><br>

  <a name="Hideki_define"></a>
  <b>Unterst&uuml;tzte Hersteller</b>
  <ul>
    <li>Arduinos with remote Sensor lib from Randy Simons</li>
    <li>Bresser</li>
    <li>Cresta</li>
    <li>Hama</li>
    <li>Hideki (Anemometer | UV sensor | Rain level meter | Thermo/hygro-sensor)</li>
    <li>TFA Dostman</li>
    <li>Alle anderen, welche das Hideki Protokoll verwenden</li>
  </ul>
  Hinweis, Aktuell sind nur temp/feuchte Sensoren implementiert. Bitte sendet uns Daten zu anderen Sensoren.<br><br>

  <a name="Hideki_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Hideki &lt;code&gt; </code>
    <br><br>
    <li>
    &lt;code&gt; besteht aus dem Sensortyp und der Kanalnummer (1..5) oder wenn das Attribut longid im IO Device gesetzt ist aus einer Zufallsadresse, die durch den Sensor beim einlegen der
    Batterie generiert wird (Die Adresse &auml;ndert sich bei jedem Batteriewechsel).<br>
    </li>
    <li>Wenn autocreate aktiv ist, dann wird der Sensor automatisch in FHEM angelegt. Das ist der empfohlene Weg, neue Sensoren hinzuzuf&uumlgen.</li>

  </ul>
  <br>

  <a name="Hideki_readings"></a>
  <b>Generierte Readings</b>
  <ul>
    <li>battery & batteryState (ok oder low)</li>
    <li>channel (Der Sensor Kanal)</li>
    <li>humidity (0-100)</li>
    <li>state (T:x.xx H:y B:z)</li>
    <li>temperature (&deg;C)</li>

    <br><i>- Hideki spezifisch -</i>
    <li>comfort_level (Status: Humidity OK... , Wet gr&ouml;&szlig;er 69% RH, Dry weniger als 40% RH, Temperature and humidity comfortable)</li>
    <li>package_number (Paketnummer in der letzten Signalfolge, startet bei 1)</li><br>
  </ul>
  <a name="Hideki_unset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="Hideki_unget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Hideki_attr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a href="#showtime">showtime</a></li>
	<li><a name="windDirCorr"></a>windDirCorr<br>
	Korrekturwert Ihrer angezeigten Windrichtung in Grad. Der Korrekturwert wird zu dem gemessenen Grad Wert Addiert.<br>
	Beispielwert: 5<br>
	Standardwert: 0<br>
	</li>
	<li><a name="windSpeedCorr"></a>windSpeedCorr<br>
	Korrekturwert Ihrer angezeigten Windgeschwindigkeit als Fließkommezahk. Die gemessene Geschwindigkeit wird mit dem angegeben Wert multiplizuert. Der Wert 0 deaktiviert die Funktion.<br>
	Beispielwert: 1.25<br>
	Standardwert: 1<br>
	</li>  <br>
  </ul>
</ul>

=end html_DE
=for :application/json;q=META.json 14_Hideki.pm
{
  "abstract": "Supports various rf sensors with hideki protocol",
  "author": [
    "Sidey <>",
    "ralf9 <>"
  ],
  "x_fhem_maintainer": [
    "Sidey"
  ],
  "x_fhem_maintainer_github": [
    "Sidey79",
	"HomeAutoUser",
	"elektron-bbs"	
  ],
  "description": "The Hideki module is a module for decoding weather sensors, which use the hideki protocol. Known brands are Bresser, Cresta, TFA and Hama",
  "dynamic_config": 1,
  "keywords": [
    "fhem-sonstige-systeme",
    "fhem-hausautomations-systeme",
    "fhem-mod",
    "signalduino",
    "Hideki",
	"Hama",
	"TFA",
	"Bresser"
  ],
  "license": [
    "GPL_2"
  ],
  "meta-spec": {
    "url": "https://metacpan.org/pod/CPAN::Meta::Spec",
    "version": 2
  },
  "name": "FHEM::Hideki",
  "prereqs": {
    "runtime": {
      "requires": {
        "POSIX": "0"
      }
    },
    "develop": {
      "requires": {
        "POSIX": "0",
        "Data::Dumper": 0
      }
    }
  },
  "release_status": "stable",
  "resources": {
    "bugtracker": {
      "web": "https://github.com/RFD-FHEM/RFFHEM/issues/"
    },
    "x_testData": [
      {
        "url": "https://raw.githubusercontent.com/RFD-FHEM/RFFHEM/master/t/FHEM/14_Hideki/testData.json",
        "testname": "Testdata with Hideki protocol sensors"
      }
    ],
    "repository": {
      "x_master": {
        "type": "git",
        "url": "https://github.com/RFD-FHEM/RFFHEM.git",
        "web": "https://github.com/RFD-FHEM/RFFHEM/tree/master"
      },
      "type": "svn",
      "url": "https://svn.fhem.de/fhem",
      "web": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/14_Hideki.pm",
      "x_branch": "trunk",
      "x_filepath": "fhem/FHEM/",
      "x_raw": "https://svn.fhem.de/trac/export/latest/trunk/fhem/FHEM/14_Hideki.pm"
    },
    "x_support_community": {
      "board": "Sonstige Systeme",
      "boardId": "29",
      "cat": "FHEM - Hausautomations-Systeme",
      "description": "Sonstige Hausautomations-Systeme",
      "forum": "FHEM Forum",
      "rss": "https://forum.fhem.de/index.php?action=.xml;type=rss;board=29",
      "title": "FHEM Forum: Sonstige Systeme",
      "web": "https://forum.fhem.de/index.php/board,29.0.html"
    },
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SIGNALduino"
    }
  }
}
=end :application/json;q=META.json
=cut
