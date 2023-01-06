##############################################
# $Id$
# The file is taken from the SIGNALduino project
# see http://www.fhemwiki.de/wiki/SIGNALduino
# and was modified by a few additions
# to support Hideki Sensors
# S. Butzek, HJGode, Ralf9 2015-2017
# S. Butzek 2018-2022
#
# changed the way crc and decrypt is used hjgode 20171129

package main;
#use version 0.77; our $VERSION = version->declare('v3.4.3');

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

#use Data::Dumper;

#####################################
sub
Hideki_Initialize($)
{
  my ($hash) = @_;


  $hash->{Match}     = qr/^P12#75[A-F0-9]{14,30}/;   # Laenge (Anhahl nibbles nach 0x75 )noch genauer spezifizieren
  $hash->{DefFn}     = \&Hideki_Define;
  $hash->{UndefFn}   = \&Hideki_Undef;
  $hash->{ParseFn}   = \&Hideki_Parse;
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1"
                       ." ignore:0,1"
                       ." windDirCorr windSpeedCorr"
                      ." $readingFnAttributes";
                      
  $hash->{AutoCreate}=
        { "Hideki.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };

  return FHEM::Meta::InitMod( __FILE__, $hash );
}


#####################################
sub
Hideki_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> Hideki <code>".int(@a)
		if(int(@a) < 3);

  $hash->{CODE}    = $a[2];
  $hash->{lastMSG} =  "";

  my $name= $hash->{NAME};

  $modules{Hideki}{defptr}{$a[2]} = $hash;
  #$hash->{STATE} = "Defined";

  #AssignIoPort($hash);
  return undef;
}

#####################################
sub
Hideki_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{Hideki}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  return undef;
}


#####################################
sub
Hideki_Parse($$)
{
	my ($iohash,$msg) = @_;
	my (undef ,$rawData) = split("#",$msg);

	my $ioname = $iohash->{NAME};
	my @a = split("", $msg);
	Log3 $iohash, 4, "$ioname Hideki_Parse: incomming $msg";

	my @decodedData;
	my $crc1crc2OK = 0;
	($crc1crc2OK, @decodedData) = decryptAndCheck($iohash, $rawData); # use unencrypted rawdata
	
	if ($crc1crc2OK == 0) {
		return '';	#crc1 or crc2 failed
	}

	# decrypt and decodedBytes are now done with decryptAndCheck
	my $decodedString = join '', unpack('H*', pack('C*',@decodedData)); # get hex string
	Log3 $iohash, 4, "$ioname Hideki_Parse: raw=$rawData, decoded=$decodedString";
	 
	if (!@decodedData) {
		Log3 $iohash, 4, "$ioname Hideki_Parse: decrypt failed";
		return '';
	}
	
	Log3 $iohash, 5, "$ioname Hideki_Parse: getSensorType for ".$decodedData[3];
	my $sensorTyp=($decodedData[3] & 0x1F);
	Log3 $iohash, 4, "$ioname Hideki_Parse: SensorTyp = $sensorTyp decodedString = $decodedString";

	my $id=substr($decodedString,2,2);      # get the random id from the data
	my $channel=0;
	my $temp="";
	my $hum=0;
	my $rain=0;
	my $unknown=0;
	my $windchill=0;
	my $windspeed=0;
	my $windgust=0;
	my $winddir=0;
	my $winddirdeg=0;
	my $winddirtext;
	my $rc;
	my $val;
	my $bat;
	my $deviceCode;
	my $model= "Hideki_$sensorTyp";
	my $count=0;
	my $comfort=0;
	## 1. Detect what type of sensor we have, then call specific function to decode
	if ($sensorTyp==30){
		($channel, $temp) = decodeThermo(\@decodedData); # decodeThermoHygro($decodedString);
		$hum = 10 * ($decodedData[6] >> 4) + ($decodedData[6] & 0x0f);
		$bat = ($decodedData[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$count = $decodedData[3] >> 6;		# verifiziert, MSG_Counter
		$comfort = ($decodedData[7] >> 2 & 0x03);   # comfort level

		if ($comfort == 0) { $comfort = 'Hum. OK. Temp. uncomfortable (>24.9 or <20)' }
		elsif ($comfort == 1) { $comfort = 'Wet. More than 69% RH' }
		elsif ($comfort == 2) { $comfort = 'Dry. Less than 40% RH' }
		elsif ($comfort == 3) { $comfort = 'Temp. and Hum. comfortable' }
		$val = "T: $temp H: $hum";
		Log3 $iohash, 4, "$ioname decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, cnt=$count, bat=$bat, temp=$temp, humidity=$hum, comfort=$comfort";
	}elsif($sensorTyp==31){
		($channel, $temp) = decodeThermo(\@decodedData);
		$bat = ($decodedData[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$count = $decodedData[3] >> 6;		# verifiziert, MSG_Counter
		$val = "T: $temp";
		Log3 $iohash, 4, "$ioname decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, cnt=$count, bat=$bat, temp=$temp";
	}elsif($sensorTyp==14){
		($channel, $rain) = decodeRain(\@decodedData); # decodeThermoHygro($decodedString);
		$bat = ($decodedData[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$count = $decodedData[3] >> 6;		# UNVERIFIZIERT, MSG_Counter
		$val = "R: $rain";
		Log3 $iohash, 4, "$ioname decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, cnt=$count, bat=$bat, rain=$rain, unknown=$unknown";
	}elsif($sensorTyp==12){
		($channel, $temp) = decodeThermo(\@decodedData); # decodeThermoHygro($decodedString);
		#($windchill,$windspeed,$windgust,$winddir,$winddirdeg,$winddirtext) = wind(\@decodedData);  ## nach unten verschoben
		$bat = ($decodedData[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$count = $decodedData[3] >> 6;		# UNVERIFIZIERT, MSG_Counter
		#$val = "T: $temp  Ws: $windspeed  Wg: $windgust  Wd: $winddirtext";  ## nach unten verschoben
		Log3 $iohash, 4, "$ioname decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, cnt=$count, bat=$bat, temp=$temp";
	}elsif($sensorTyp==13){
		($channel, $temp) = decodeThermo(\@decodedData); # decodeThermoHygro($decodedString);
		$bat = ($decodedData[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$count = $decodedData[3] >> 6;		# UNVERIFIZIERT, MSG_Counter
		$val = "T: $temp";
		Log3 $iohash, 4, "$ioname decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, cnt=$count, bat=$bat, temp=$temp";
		Log3 $iohash, 4, "$ioname Sensor Typ $sensorTyp currently not full supported, please report sensor information!";
	}
	else{
		Log3 $iohash, 4, "$ioname Sensor Typ $sensorTyp not supported, please report sensor information!";
		return "";
	}
	my $longids = AttrVal($iohash->{NAME},'longids',0);
	if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
	{
		$deviceCode=$model . "_" . $id . "." . $channel;
		Log3 $iohash,4, "$ioname Hideki_Parse: using longid: $longids model: $model";
	} else {
		$deviceCode = $model . "_" . $channel;
	}

	Log3 $iohash, 5, "$ioname Hideki_Parse deviceCode: $deviceCode";

	my $def = $modules{Hideki}{defptr}{$iohash->{NAME} . "." . $deviceCode};
	$def = $modules{Hideki}{defptr}{$deviceCode} if(!$def);

	if(!$def) {
		Log3 $iohash, 1, "$ioname Hideki: UNDEFINED sensor $deviceCode detected, code $msg";
		return "UNDEFINED $deviceCode Hideki $deviceCode";
	}

	my $hash = $def;
	my $name = $hash->{NAME};
	return "" if(IsIgnored($name));

	#Log3 $name, 4, "Hideki: $name ($msg)";
	
	if ($sensorTyp == 12) {	# Wind
		($windchill,$windspeed,$windgust,$winddir,$winddirdeg,$winddirtext) = wind($name, \@decodedData);
		$val = "T: $temp  Ws: $windspeed  Wg: $windgust  Wd: $winddirtext";
		Log3 $name, 4, "$ioname $name Parse: model=12(wind), T: $temp, Wc=$windchill, Ws=$windspeed, Wg=$windgust, Wd=$winddir, WdDeg=$winddirdeg, Wdtxt=$winddirtext";
	}
	
	if (!defined(AttrVal($name,"event-min-interval",undef)))
	{
		my $minsecs = AttrVal($ioname,'minsecs',0);
		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
			Log3 $name, 4, "$name Hideki_Parse: $deviceCode Dropped ($decodedString) due to short time. minsecs=$minsecs";
		  	return "";
		}
	}
	$hash->{lastReceive} = time();

	$def->{lastMSG} = $decodedString;

	#Log3 $name, 4, "Hideki update $name:". $name;

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $val);
	readingsBulkUpdate($hash, "battery", $bat)   if ($bat ne "");
	readingsBulkUpdate($hash, "batteryState", $bat)   if ($bat ne "");
	readingsBulkUpdate($hash, "channel", $channel) if ($channel ne "");
	readingsBulkUpdate($hash, "temperature", $temp) if ($temp ne "");
	readingsBulkUpdate($hash, "package_number", $count) if ($count ne "");
	if ($sensorTyp == 30) { # temperature, humidity
		readingsBulkUpdate($hash, "humidity", $hum) if ($hum ne "");
		readingsBulkUpdate($hash, "comfort_level", $comfort) if ($comfort ne "");
	}
	elsif ($sensorTyp == 14) {  # rain
		readingsBulkUpdate($hash, "rain", $rain);
	}
	elsif ($sensorTyp == 12) {  # wind
		readingsBulkUpdate($hash, "windChill", $windchill);
		readingsBulkUpdate($hash, "windGust", $windgust);
		readingsBulkUpdate($hash, "windSpeed", $windspeed);
		readingsBulkUpdate($hash, "windDirection", $winddir);
		readingsBulkUpdate($hash, "windDirectionDegree", $winddirdeg);
		readingsBulkUpdate($hash, "windDirectionText", $winddirtext);
	}

	readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	return $name;
}

# decryptAndCheck
# input is raw data (array of bytes)
# output is true if check1 and check2 OK
# data will then hold the decrypted data
sub decryptAndCheck {
	my $iohash = shift;
	my $rawData = shift;
	my $name = $iohash->{NAME};
	my $cs1=0; #will be zero for xor over all (bytes[2]>>1)&0x1F except first byte (always 0x75)
	my $cs2=0;
	my $i; 
	my @data;
	@data=map { hex($_) } ($rawData =~ /(..)/g); #byte array from raw hex data string
	
	#/* Decrypt raw received data byte */ BYTE DecryptByte(BYTE b) { return b ^ (b << 1); }
	my $count=( ($data[2] ^ ($data[2]<<1)) >>1 ) & 0x1f;
	my $L = scalar @data;
	if ($L <= $count+2) {
		Log3 $iohash, 4, "$name Hideki_crc: rawdata=$rawData to short, count=$count data length=$L";
		return (0,@data);
	}
	
	if($data[0] != 0x75) {
		Log3 $iohash, 4, "$name Hideki_Parse: rawData=$rawData is no Hideki";
		return (0,@data);
	}
	
	#iterate over data only, first byte is 0x75 always
	# read bytes 1 to n-2 , just before checksum
	for ($i=1; $i<($count+2); $i++) {
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

# /* The second checksum. Input is OldChecksum^NewByte */
sub Hideki_SecondCheck{
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


# return decoded sensor type
# in: one byte
# out: one byte
# Der Typ eines Sensors steckt in Byte 3:
# Byte3 & 0x1F  Device
# 0x0C	      Anemometer
# 0x0D	      UV sensor
# 0x0E	      Rain level meter
# 0x1E	      Thermo/hygro-sensor
# 0x1F	      Thermo sensor
sub getSensorType{
	return ($_[0] & 0x1F);
}


# decode byte array and return channel, temperature
# input: decrypted byte array starting with 0x75, passed by reference as in mysub(\@array);
# output <return code>, <channel>, <temperature>
# was unable to get this working with an array ref as input, so switched to hex string input
sub decodeThermo {
	my @Hidekibytes = @{$_[0]};

	#my $Hidekihex = shift;
	#my @Hidekibytes=();
	#for (my $i=0; $i<(length($Hidekihex))/2; $i++){
	#	my $hex=hex(substr($Hidekihex, $i*2, 2)); ## Mit split und map geht es auch ... $str =~ /(..?)/g;
	#	push (@Hidekibytes, $hex);
	#}
	my $channel=0;
	my $temp=0;

	$channel = $Hidekibytes[1] >> 5;
	# //Internally channel 4 is used for the other sensor types (rain, uv, anemo).
	# //Therefore, if channel is decoded 5 or 6, the real value set on the device itself is 4 resp 5.
	if ($channel >= 5) {
		$channel--;
	}
	my $sensorId = $Hidekibytes[1] & 0x1f;  		# Extract random id from sensor
	#my $devicetype = $Hidekibytes[3]&0x1f;
	$temp = 100 * ($Hidekibytes[5] & 0x0f) + 10 * ($Hidekibytes[4] >> 4) + ($Hidekibytes[4] & 0x0f);
	## // temp is negative?
	if (!($Hidekibytes[5] & 0x80)) {
		$temp = -$temp;
	}

	$temp = $temp / 10;
	return ($channel, $temp);
}


# decode byte array and return channel and total rain in mm
# input: decrypted byte array starting with 0x75, passed by reference as in mysub(\@array);
# output <return code>, <channel>, <totalrain>
# was unable to get this working with an array ref as input, so switched to hex string input
sub decodeRain {
	my @Hidekibytes = @{$_[0]};

	#my $Hidekihex = shift;
	#my @Hidekibytes=();
	#for (my $i=0; $i<(length($Hidekihex))/2; $i++){
	#	my $hex=hex(substr($Hidekihex, $i*2, 2)); ## Mit split und map geht es auch ... $str =~ /(..?)/g;
	#	push (@Hidekibytes, $hex);
	#}
	my $channel=0;
	my $rain=0;
	my $unknown;

	#my $tests=0;
	#additional checks?
	#if($Hidekibytes[2]==0xCC){
	#  $tests+=1;
	#}
	#if($Hidekibytes[6]==0x66){
	#  $tests+=1;
	#}
	# possibly test if $tests==2 for sanity check
	#printf("SANITY CHECK tests=%i\n", $tests);
	
	$unknown = $Hidekibytes[6];
	$channel = $Hidekibytes[1] >> 5;
	# //Internally channel 4 is used for the other sensor types (rain, uv, anemo).
	# //Therefore, if channel is decoded 5 or 6, the real value set on the device itself is 4 resp 5.
	if ($channel >= 5) {
		$channel--;
	}
	my $sensorId = $Hidekibytes[1] & 0x1f;  		# Extract random id from sensor
	
	$rain = ($Hidekibytes[4] + $Hidekibytes[5]*0xff)*0.7;

	return ($channel, $rain, $unknown);
}

# P12#758BB244074007400F00001C6E7A01
sub wind {
	my $name = shift;
	my @Hidekibytes = @{$_[0]};
	my @wd=(0, 15, 13, 14, 9, 10, 12, 11, 1, 2, 4, 3, 8, 7, 5, 6);
	my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");
	my $windspeed;
	my $windchill;
	my $windgust;
	my $winddir;
	my $winddirdeg;
	my $winddirtext;
	
	$windchill = 100 * ($Hidekibytes[7] & 0x0f) + 10 * ($Hidekibytes[6] >> 4) + ($Hidekibytes[6] & 0x0f);
	## windchill is negative?
	if (!($Hidekibytes[7] & 0x80)) {
		$windchill = -$windchill;
	}
	$windchill = $windchill / 10;
	$windspeed = ($Hidekibytes[9] & 0x0f ) * 100 + ($Hidekibytes[8] >> 4) * 10 + ($Hidekibytes[8] & 0x0f);
	$windgust = ($Hidekibytes[10] >> 4) * 100 + ($Hidekibytes[10] & 0x0f) * 10 + ($Hidekibytes[9] >> 4);
	my $windSpeedCorr = AttrVal($name,'windSpeedCorr',1); ### -> hierher verschoben
	if ($windSpeedCorr > 0) {
		$windspeed = sprintf("%.2f", $windspeed * $windSpeedCorr);
		$windgust  = sprintf("%.2f", $windgust * $windSpeedCorr);
		Log3 $name, 5, "$name Hideki_Parse: WindSpeedCorr factor=$windSpeedCorr";
	}
	$winddir = $wd[$Hidekibytes[11] >> 4];
	my $windDirCorr = AttrVal($name,'windDirCorr',0);
	if ($windDirCorr > 0) {
		$winddir += $windDirCorr;
		$winddir &= 15;
		Log3 $name, 5, "$name Hideki_Parse: windDirCorr=$windDirCorr";
	}
	$winddirtext = $winddir_name[$winddir]; 
	$winddirdeg = $winddir * 22.5;
  	
	return ($windchill,$windspeed,$windgust,$winddir,$winddirdeg,$winddirtext);
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
        "POSIX": "0"
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
