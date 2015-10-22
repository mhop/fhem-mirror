##############################################
# $Id: 14_Hideki.pm 12128 2015-10-12 $
# The file is taken from the SIGNALduino project
# see http://www.fhemwiki.de/wiki/SIGNALduino
# and was modified by a few additions
# to support Hideki Sensors
# S. Butzek & HJGode &Ralf9 2015
#

package main;

use strict;
use warnings;
use POSIX;

#use Data::Dumper;

#####################################
sub
Hideki_Initialize($)
{
  my ($hash) = @_;


  $hash->{Match}     = "^P12#75[A-F0-9]{17,30}";   # Länge (Anhahl nibbles nach 0x75 )noch genauer zpezifiieren
  $hash->{DefFn}     = "Hideki_Define";
  $hash->{UndefFn}   = "Hideki_Undef";
  $hash->{AttrFn}    = "Hideki_Attr";
  $hash->{ParseFn}   = "Hideki_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 "
                       ."ignore:0,1 "
                      ." $readingFnAttributes";
                      
  $hash->{AutoCreate}=
        { "Hideki.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };

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
  $hash->{STATE} = "Defined";

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

	my $name = $iohash->{NAME};
	my @a = split("", $msg);
	Log3 $iohash, 4, "Hideki_Parse $name incomming $msg";

	# decrypt bytes
	my $decodedString = decryptBytes($rawData); # decrpyt hex string to hex string

	#convert dectypted hex str back to array of bytes:
	my @decodedBytes  = map { hex($_) } ($decodedString =~ /(..)/g);

	if (!@decodedBytes)
	{
		Log3 $iohash, 4, "$name decrypt failed";
		return undef;
	}
	if (!Hideki_crc(\@decodedBytes))
	{
		Log3 $iohash, 4, "$name crc failed";
		return undef;
	}
	my $sensorTyp=getSensorType($decodedBytes[3]);
	Log3 $iohash, 4, "Hideki_Parse SensorTyp = $sensorTyp decodedString = $decodedString";
	my $id=substr($decodedString,2,2);      # get the random id from the data
	my $channel=0;
	my $temp=0;
	my $hum=0;
	my $rc;
	my $val;
	my $bat;
	my $deviceCode;
	my $model= "Hideki_$sensorTyp";

	## 1. Detect what type of sensor we have, then calll specific function to decode
	if ($sensorTyp==0x1E){
		($channel, $temp, $hum) = decodeThermoHygro(\@decodedBytes); # decodeThermoHygro($decodedString);
		$bat = ($decodedBytes[2] >> 6 == 3) ? 'ok' : 'low';			 # decode battery
		$val = "T: $temp H: $hum Bat: $bat";
	}else{
		Log3 $iohash, 4, "$name Sensor Typ $sensorTyp not supported, please report sensor information!";
		return "$name Sensor Typ $sensorTyp not supported, please report sensor information!";
	}
	my $longids = AttrVal($iohash->{NAME},'longids',0);
	if ( ($longids != 0) && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
	{
		$deviceCode = $model . "_" . $id;
		Log3 $iohash,4, "$name using longid: $longids model: $model";
	} else {
		$deviceCode = $model . "_" . $channel;
	}

	Log3 $iohash, 4, "$name decoded Hideki protocol model=$model, sensor id=$id, channel=$channel, temp=$temp, humidity=$hum, bat=$bat";
	Log3 $iohash, 5, "deviceCode: $deviceCode";

	my $def = $modules{Hideki}{defptr}{$iohash->{NAME} . "." . $deviceCode};
	$def = $modules{Hideki}{defptr}{$deviceCode} if(!$def);

	if(!$def) {
		Log3 $iohash, 1, "Hideki: UNDEFINED sensor $sensorTyp detected, code $deviceCode";
		return "UNDEFINED $deviceCode Hideki $deviceCode";
	}

	my $hash = $def;
	$name = $hash->{NAME};
	return "" if(IsIgnored($name));

	#Log3 $name, 4, "Hideki: $name ($msg)";
	
	
	if (!defined(AttrVal($hash->{NAME},"event-min-interval",undef)))
	{
		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
			Log3 $iohash, 4, "$deviceCode Dropped ($decodedString) due to short time. minsecs=$minsecs";
		  	return "";
		}
	}
	$hash->{lastReceive} = time();

	$def->{lastMSG} = $decodedString;

	#Log3 $name, 4, "Hideki update $name:". $name;

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $val);
	readingsBulkUpdate($hash, "battery", $bat)   if ($bat ne "");
	readingsBulkUpdate($hash, "humidity", $hum) if ($hum ne "");
	readingsBulkUpdate($hash, "temperature", $temp) if ($temp ne "");
	readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	return $name;
}

# check crc for incoming message
# in: hex string with encrypted, raw data, starting with 75
# out: 1 for OK, 0 for failed
# sample "75BDBA4AC2BEC855AC0A00"
sub Hideki_crc{
	#my $Hidekihex=shift;
	#my @Hidekibytes=shift;

	my @Hidekibytes = @{$_[0]};
	#push @Hidekibytes,0x75; #first byte always 75 and will not be included in decrypt/encrypt!
	#convert to array except for first hex
	#for (my $i=1; $i<(length($Hidekihex))/2; $i++){
    #	my $hex=Hideki_decryptByte(hex(substr($Hidekihex, $i*2, 2)));
	#	push (@Hidekibytes, $hex);
	#}

	my $cs1=0; #will be zero for xor over all (bytes>>1)&0x1F except first byte (always 0x75)
	#my $rawData=shift;
	#todo add the crc check here

	my $count=($Hidekibytes[2]>>1) & 0x1f;
	my $b;
	#iterate over data only, first byte is 0x75 always
	for (my $i=1; $i<$count+2 && $i<scalar @Hidekibytes; $i++) {
		$b =  $Hidekibytes[$i];
		$cs1 = $cs1 ^ $b; # calc first chksum
	}
	if($cs1==0){
		return 1;
	}
	else{
		return 0;
	}
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
sub getSensorType{
	return $_[0] & 0x1F;
}

# decrypt bytes of hex string
# in: hex string
# out: decrypted hex string
sub decryptBytes{
	my $Hidekihex=shift;
	#create array of hex string
	my @Hidekibytes  = map { Hideki_decryptByte(hex($_)) } ($Hidekihex =~ /(..)/g);

	my $result="75";  # Byte 0 is not encrypted
	for (my $i=1; $i<scalar (@Hidekibytes); $i++){
		$result.=sprintf("%02x",$Hidekibytes[$i]);
	}
	return $result;
}

sub Hideki_decryptByte{
	my $byte = shift;
	#printf("\ndecryptByte 0x%02x >>",$byte);
	my $ret2 = ($byte ^ ($byte << 1) & 0xFF); #gives possible overflow to left so c3->145 instead of 45
	#printf(" %02x\n",$ret2);
	return $ret2;
}

# decode byte array and return channel, temperature and hunidity
# input: decrypted byte array starting with 0x75, passed by reference as in mysub(\@array);
# output <return code>, <channel>, <temperature>, <humidity>
# was unable to get this working with an array ref as input, so switched to hex string input
sub decodeThermoHygro {
	my @Hidekibytes = @{$_[0]};

	#my $Hidekihex = shift;
	#my @Hidekibytes=();
	#for (my $i=0; $i<(length($Hidekihex))/2; $i++){
	#	my $hex=hex(substr($Hidekihex, $i*2, 2)); ## Mit split und map geht es auch ... $str =~ /(..?)/g;
	#	push (@Hidekibytes, $hex);
	#}
	my $channel=0;
	my $temp=0;
	my $humi=0;

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

	$humi = 10 * ($Hidekibytes[6] >> 4) + ($Hidekibytes[6] & 0x0f);

	$temp = $temp / 10;
	return ($channel, $temp, $humi);
}

sub
Hideki_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($modules{Hideki}{defptr}{$cde});
  $modules{Hideki}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}


1;

=pod
=begin html

<a name="Hideki"></a>
<h3>Hideki</h3>
<ul>
  The Hideki module is a module for decoding weather sensors, which use the hideki protocol. Known brands are Bresser, Cresta, TFA and Hama.
  <br><br>

  <a name="Hideki_define"></a>
  <b>Supported Brands</b>
  <ul>
  	<li>Hama</li>
  	<li>Bresser</li>
  	<li>TFA Dostman</li>
  	<li>Arduinos with remote Sensor lib from Randy Simons</li>
  	<li>Cresta</li>
  	<li>Hideki</li>
  	<li>all other devices, which use the Hideki protocol</li>
  </ul>
  Please note, currently temp/hum devices are implemented. Please report data for other sensortypes.

  <a name="Hideki_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Hideki &lt;code&gt; </code> <br>

    <br>
    &lt;code&gt; is the address of the sensor device and
	is build by the sensor type and the channelnumber (1 to 5) or if the attribute longid is specfied an autogenerated address build when inserting
	the battery (this adress will change every time changing the battery).<br>
	
	If autocreate is enabled, the device will be defined via autocreate. This is also the preferred mode of defining such a device.

  </ul>
  <a name="Hideki_readings"></a>
  <b>Generated readings</b>
  <ul>
  	<li>state (T:x H:y B:z)</li>
	<li>temperature (&deg;C)</li>
	<li>humidity (0-100)</li>
	<li>battery (ok or low)</li>
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
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
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
  <b>Unterstützte Hersteller</b>
  <ul>
  	<li>Hama</li>
  	<li>Bresser</li>
  	<li>TFA Dostman</li>
  	<li>Arduinos with remote Sensor lib from Randy Simons</li>
  	<li>Cresta</li>
  	<li>Hideki</li>
  	<li>Alle anderen, welche das Hideki Protokoll verwenden</li>
  </ul>
  Hinweis, Aktuell sind nur temp/feuchte Sensoren implementiert. Bitte sendet uns Daten zu anderen Sensoren.
  
  <a name="Hideki_define"></a>
  <b>Define</b>
  <ul>
  	<li><code>define &lt;name&gt; Hideki &lt;code&gt; </code></li>
	<li>
    <br>
    &lt;code&gt; besteht aus dem Sensortyp und der Kanalnummer (1..5) oder wenn das Attribut longid im IO Device gesetzt ist aus einer Zufallsadresse, die durch den Sensor beim einlegen der
	Batterie generiert wird (Die Adresse aendert sich bei jedem Batteriewechsel).<br>
    </li>
    <li>Wenn autocreate aktiv ist, dann wird der Sensor automatisch in FHEM angelegt. Das ist der empfohlene Weg, neue Sensoren hinzuzufügen.</li>
   
  </ul>
  <br>

  <a name="Hideki_readings"></a>
  <b>Erzeugte Readings</b>
  <ul>
  	<li>state (T:x H:y B:z)</li>
	<li>temperature (&deg;C)</li>
	<li>humidity (0-100)</li>
	<li>battery (ok or low)</li>
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
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
