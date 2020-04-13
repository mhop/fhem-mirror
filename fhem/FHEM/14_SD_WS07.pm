##############################################
# $Id$
# 
# The purpose of this module is to support serval eurochron
# weather sensors like eas8007 which use the same protocol
# Sidey79, Ralf9  2015-2017
# Sidey79, elektron-bbs 2018-2019
#
#  Nexus sensor protocol with ID, temperature and optional humidity 
#  also FreeTec NC-7345 sensors for FreeTec Weatherstation NC-7344. 
#  
#  the sensor sends 36 bits 12 times, 
#  the packets are ppm modulated (distance coding) with a pulse of ~500 us 
#  followed by a short gap of ~1000 us for a 0 bit or a long ~2000 us gap for a 
#  1 bit, the sync gap is ~4000 us. 
#  
#  the data is grouped in 9 nibbles 
#  [id0] [id1] [flags] [temp0] [temp1] [temp2] [const] [humi0] [humi1] 
#  
#  The 8-bit id changes when the battery is changed in the sensor. 
#  flags are 4 bits B 0 C C, where B is the battery status: 1=OK, 0=LOW 
#  and CC is the channel: 0=CH1, 1=CH2, 2=CH3 
#  temp is 12 bit signed scaled by 10 
#  const is always 1111 (0xF) or 1010 (0xA)
#  humiditiy is 8 bits 

package main;

#use version 0.77; our $VERSION = version->declare('v3.4.3');

use strict;
use warnings;

#use Data::Dumper;


sub
SD_WS07_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = "^P7#[A-Fa-f0-9]{6}[AFaf][A-Fa-f0-9]{2,3}";    ## pos 7 ist aktuell immer 0xF oder 0xA
  $hash->{DefFn}     = "SD_WS07_Define";
  $hash->{UndefFn}   = "SD_WS07_Undef";
  $hash->{ParseFn}   = "SD_WS07_Parse";
  $hash->{AttrList}  = "do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                       "negation-batt:no,yes ".
                       "max-deviation-temp:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                       "offset-temp ".
                       "$readingFnAttributes ";
  $hash->{AutoCreate} =
        {
			"SD_WS07_TH_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"},
			"SD_WS07_T_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,",  autocreateThreshold => "2:180"}
			};
}

#############################
sub
SD_WS07_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SD_WS07 <code> ".int(@a)
        if(int(@a) < 3 );

  $hash->{CODE} = $a[2];
  $hash->{lastMSG} =  "";
  $hash->{bitMSG} =  "";

  $modules{SD_WS07}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";
  
  my $name= $hash->{NAME};
  return undef;
}

#####################################
sub
SD_WS07_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{SD_WS07}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{SD_WS07}{defptr}{$hash->{CODE}}));
  return undef;
}


###################################
sub
SD_WS07_Parse($$)
{
  my ($iohash, $msg) = @_;
  my (undef ,$rawData) = split("#",$msg);
  #$protocol=~ s/^P(\d+)/$1/; # extract protocol

  my $model = "SD_WS07";
  my $typ = $model;
  my $hlen = length($rawData);
  my $blen = $hlen * 4;
  my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 

	Log3 $iohash, 4, "$iohash->{NAME}: SD_WS07_Parse $model ($msg) length: $hlen";
  
  # 0   4    8     12            24    28       36
  # 00110110 1010  000100000010  1111  00111000 0000  eas8007
  # 01110010 1010  000010111100  1111  00000000 0000  other device from anfichtn
  # 11010010 0000  000000010001  1111  00101000       other device from elektron-bbs
  # 01100011 1000  000011101010  1111  00001010       other device from HomeAuto_User SD_WS07_TH_631
  # 11101011 1000  000010111000  1111  00000000       other device from HomeAuto_User SD_WS07_T_EB1
  # 11000100 1000  000100100010  1111  00000000       other device from HomeAuto_User SD_WS07_T_C41
  # 01100100 0000  000100001110  1111  00101010       hama TS36E from HomeAuto_User - Bat bit identified
  # Long-ID  BCCC  TEMPERATURE    ??   HUMIDITY       B=Battery, C=Channel

  # 10110001 1000  000100011010  1010  00101100       Auriol AFW 2 A1, IAN: 297514
  # Long-ID  BSCC  TEMPERATURE    ??   HUMIDITY       B=Battery, S=Sendmode, C=Channel
  
	# Modelliste
	my %models = (
		"0" => "T",
		"1" => "TH",
	);
	
    my $bitData2 = substr($bitData,0,8) . ' ' . substr($bitData,8,4) . ' ' . substr($bitData,12,12) . ' ' . substr($bitData,24,4) . ' ' . substr($bitData,28,8);
    Log3 $iohash, 4, "$iohash->{NAME}: SD_WS07_Parse $model converted to bits " . $bitData2;
    
    my $id = substr($rawData,0,2);
    my $bat = substr($bitData,8,1) eq "1" ? "ok" : "low";	# 1 = ok | 0 = low --> identified on hama TS36E
    my $sendmode;
    my $channel = oct("0b" . substr($bitData,9,3)) + 1;
    if (substr($bitData,24,4) eq "1010") {
      $sendmode = substr($bitData,9,1) eq "1" ? "manual" : "auto";	# 1 = manual | 0 = auto --> identified on Auriol AFW 2 A1
      $channel = oct("0b" . substr($bitData,10,2)) + 1;
    }
    my $temp = oct("0b" . substr($bitData,12,12));
    my $hum = oct("0b" . substr($bitData,28,8));
	my $modelkey;
    
	if ($hum == 0) {
		$modelkey = $hum;
	} elsif ($hum != 0) {
		$modelkey = 1;
	}
    
	$model = $model."_".$models{$modelkey};
    my $deviceCode;
	my $longids = AttrVal($iohash->{NAME},'longids',0);
	if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))	{
		$deviceCode = $id.$channel;
		Log3 $iohash,4, "$iohash->{NAME}: using longid $longids model $model";
	} else {
		$deviceCode = $channel;
	}
    
	### Model specific attributes
	if ($models{$modelkey} eq "TH") {
		addToDevAttrList($model."_".$deviceCode,"max-deviation-hum:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ");
		addToDevAttrList($model."_".$deviceCode,"offset-hum");
	}
    #print Dumper($modules{SD_WS07}{defptr});

	my $oldDeviceCode = $deviceCode;  # temporary statement to find wrong definitions 
	    
    $deviceCode = $model . "_" . $deviceCode;
    my $def = $modules{SD_WS07}{defptr}{$deviceCode};	# test for already defined devices use normal naming convention (model_channel or model_lonid)
	
	if (!defined($def)) # temporary statement: fix wrong definition 
	{
    	$def = $modules{SD_WS07}{defptr}{$oldDeviceCode};	# test for already defined devices use wrong naming convention (only channel or longid)
		if(defined($def)) {
			Log3 $iohash,4, "$def->{NAME}: Updating decrepated DEF of this sensor. Save config is needed to avoid further messages like this.";
   			CommandModify(undef,"$def->{NAME} $deviceCode")  
		}
	}

    if(!$def) {
		Log3 $iohash, 1, "$iohash->{NAME}: UNDEFINED Sensor $model detected, code $deviceCode";
			return "UNDEFINED $deviceCode SD_WS07 $deviceCode";
    }
        #Log3 $iohash, 3, 'SD_WS07: ' . $def->{NAME} . ' ' . $id;
	
	my $hash = $def;
	my $name = $hash->{NAME};
	return "" if(IsIgnored($name));
	
	#Log3 $name, 4, "$iohash->{NAME} SD_WS07: $name ($rawData)";  

	if (!defined(AttrVal($hash->{NAME},"event-min-interval",undef))) {
		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
			Log3 $hash, 4, "$iohash->{NAME}: $deviceCode Dropped due to short time. minsecs=$minsecs";
		  	return "";
		}
	}
	
	$hum += AttrVal($name, "offset-hum", 0);				# correction value for humidity (default 0 %)
	if ($model ne "SD_WS07_T" && $hum > 100 || $model ne "SD_WS07_T" && $hum < 0) {
		Log3 $name, 4, "$iohash->{NAME}: $name ERROR - Humidity out of range 0-100: ($hum)";
		return "";
	}
	
   if ($temp > 700 && $temp < 3840) {								# -25,6 .. 70,0 Â°C
		Log3 $name, 4, "$iohash->{NAME}: $name ERROR - Temperature out of range 700-3840 ($temp)";
		return "";
   } elsif ($temp >= 3840) {        # negative Temperaturen, ist ueberprueft worden
      $temp -= 4096;
   }  
   $temp /= 10;
	$temp += AttrVal($name, "offset-temp", 0);				# correction value for temperature (default 0 K)
   Log3 $iohash, 4, "$iohash->{NAME}: $name id=$id, channel=$channel, temp=$temp, hum=$hum, bat=$bat";

	# Sanity check temperature and humidity
   if($def) {
		my $timeSinceLastUpdate = ReadingsAge($hash->{NAME}, "state", 0);
		if ($timeSinceLastUpdate < 0) {
			$timeSinceLastUpdate = -$timeSinceLastUpdate;
		}
		if (ReadingsVal($name, "temperature", undef) && (defined(AttrVal($hash->{NAME},"max-deviation-temp",undef)))) {
			my $diffTemp = 0;
			my $oldTemp = ReadingsVal($name, "temperature", undef);
			my $maxdeviation = AttrVal($name, "max-deviation-temp", 1);				# default 1 K
			if ($temp > $oldTemp) {
				$diffTemp = ($temp - $oldTemp);
			} else {
				$diffTemp = ($oldTemp - $temp);
			}
			$diffTemp = sprintf("%.1f", $diffTemp);				
			Log3 $name, 4, "$iohash->{NAME}: $name old temp $oldTemp, age $timeSinceLastUpdate, new temp $temp, diff temp $diffTemp";
			my $maxDiffTemp = $timeSinceLastUpdate / 60 + $maxdeviation; 			# maxdeviation + 1.0 Kelvin/Minute
			$maxDiffTemp = sprintf("%.1f", $maxDiffTemp + 0.05);						# round 0.1
			Log3 $name, 4, "$iohash->{NAME}: $name max difference temperature $maxDiffTemp K";
			if ($diffTemp > $maxDiffTemp) {
				Log3 $name, 3, "$iohash->{NAME}: $name ERROR - Temp diff too large (old $oldTemp, new $temp, diff $diffTemp)";
			return "";
			}
		}
		if (defined($hash->{READINGS}{humidity}{VAL}) && defined(AttrVal($hash->{NAME},"max-deviation-hum",undef)) && $models{$modelkey} eq "TH") {
			my $diffHum = 0;
			my $oldHum = ReadingsVal($name, "humidity", undef);
			my $maxdeviation = AttrVal($name, "max-deviation-hum", 1);				# default 1 %
			if ($hum > $oldHum) {
				$diffHum = ($hum - $oldHum);
			} else {
				$diffHum = ($oldHum - $hum);
			}
			Log3 $name, 4, "$iohash->{NAME}: $name old hum $oldHum, age $timeSinceLastUpdate, new hum $hum, diff hum $diffHum";
			my $maxDiffHum = $timeSinceLastUpdate / 60 + $maxdeviation;				# maxdeviation + 1.0 %/Minute
			$maxDiffHum = sprintf("%1.f", $maxDiffHum + 0.5);							# round 1
			Log3 $name, 4, "$iohash->{NAME}: $name max difference humidity $maxDiffHum %";
			if ($diffHum > $maxDiffHum) {
				Log3 $name, 3, "$iohash->{NAME}: $name ERROR - Hum diff too large (old $oldHum, new $hum, diff $diffHum)";
				return "";
			}
		}
   }
	
	$hash->{lastReceive} = time();
	$hash->{lastMSG} = $rawData;
	$hash->{bitMSG} = $bitData2; 

	if (AttrVal($name, "negation-batt", "no") eq "yes") {	# default undef negation batt bit
		$bat = "0" eq "0" ? "ok" : "low";							# 0 = ok
	}
	
    my $state = "T: $temp". ($hum>0 ? " H: $hum":"");
    
    readingsBeginUpdate($hash);
    #readingsBulkUpdate($hash, "model", $models{$modelkey});
    readingsBulkUpdate($hash, "state", $state);
    readingsBulkUpdate($hash, "temperature", $temp)  if ($temp ne"");
    readingsBulkUpdate($hash, "humidity", $hum)  if ($models{$modelkey} eq "TH");
    readingsBulkUpdate($hash, "batteryState", $bat);
    readingsBulkUpdate($hash, "sendmode", $sendmode, 0) if (defined($sendmode));
    readingsBulkUpdate($hash, "channel", $channel) if ($channel ne "");
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch

	### ZusatzCheck | Beauty - humidity wird einmal definiert obwohl Typ T ###
	#delete $hash->{READINGS}{"humidity"} if($hash->{READINGS} && $models{$modelkey} eq "T");
	delete $hash->{READINGS}{humidity} if($hash->{READINGS}{humidity} && $models{$modelkey} eq "T");
	
	return $name;
}


1;


=pod
=item summary    Supports weather sensors protocol 7 from SIGNALduino
=item summary_DE Unterst&uumltzt Wettersensoren mit Protokol 7 vom SIGNALduino
=begin html

<a name="SD_WS07"></a>
<h3>Weather Sensors protocol #7</h3>
<ul>
  The SD_WS07 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>Auriol AFW 2 A1, IAN: 297514</li>
    <li>Eurochon EAS800z</li>
    <li>Technoline WS6750/TX70DTH</li>
  </ul>
  <br>
  New received devices are added in FHEM with autocreate.
  <br><br>
  The module writes from verbose 4 messages, if not possible values like humidity > 100% are decoded.
  <br><br>

  <a name="SD_WS07_Define"></a>
  <b>Define</b> 
  <ul>The received devices are created automatically.<br>
  The ID of the device is <model>_<channel> or, if the longid attribute is specified, it is <model> with a combination of channel and some random generated bits during powering the sensor.<br>
  If you want to use more sensors, than channels available, you can use the longid option to differentiate them.
  </ul>
  <br>
  <a name="SD_WS07 Events"></a>
  <b>Generated readings:</b>
  <br>Some devices may not support all readings, so they will not be presented<br>
  <ul>
  	 <li>state (T: H:)</li>
     <li>temperature (&deg;C)</li>
     <li>humidity: (the humidity 1-100)</li>
     <li>batteryState: (low or ok)</li>
     <li>channel: (the channelnumberf)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li>offset-temp<br>
       This offset can be used to correct the temperature. For example: 10 means, that the temperature is 10 &deg;C higher.<br>
    </li>
    <li>offset-hum<br>
       Works the same way as offset-temp.<br>
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
	<li>max-deviation-hum (Default:1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>  
		Maximum permissible deviation of the measured humidity from the previous value in percent.<br>  
		Since these sensors do not send checksums, it can easily lead to the reception of implausible values.   
		To intercept these, a maximum deviation from the last correctly received value can be set.
		Larger deviations are then ignored and lead to an error message in the log file, such as this:<br>  
		<code>SD_WS07_TH_1 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>  
		In addition to the set value, a value dependent on the difference of the reception times is added.
		This is 1.0% relative humidity per minute. This means e.g. if a difference of 8 is set and the time
		interval of receiving the messages is 3 minutes, the maximum allowed difference is 11.  
	</li>
	<li>max-deviation-temp (Default:1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>  
		Maximum permissible deviation of the measured temperature from the previous value in Kelvin.<br>  
		please refer max-deviation-hum  
	</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
  <ul>
	Instead of the attributes <code>max-deviation-hum</code> and <code>max-deviation-hum</code>, 
	the <code>doubleMsgCheck_IDs</code> attribute of the SIGNALduino can also be used if the sensor is well received.
	An update of the readings is only executed if the same values ??have been received at least twice.
  </ul>
  <br>

  <a name="SD_WS07_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS07_Get"></a>
  <b>Get</b> <ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="SD_WS07"></a>
<h3>SD_WS07</h3>
<ul>
  Das SD_WS07 Modul verarbeitet von einem IO Geraet (SIGNALDuino, Signal-ESP, etc.) empfangene Nachrichten von Temperatur-/Feuchte-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b>
  <ul>
    <li>Auriol AFW 2 A1, IAN: 297514</li>
    <li>Eurochon EAS800z</li>
    <li>Technoline WS6750/TX70DTH</li>
    <li>TFA 30320902</li>
    <li>FreeTec Aussenmodul fuer Wetterstation NC-7344</li>
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>
  Das Modul schreibt in das Logfile ab verbose 4 Meldungen, wenn die dekodierten Werte nicht plausibel sind. Z.B. Feuchtewerte über 100%.
  <br><br>
  <a name="SD_WS07_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
	Die ID der angelegten Sensoren ist <model>_<channel>, oder wenn das Attribut longid gesetzt ist, <model> und eine Kombination aus Bits, welche der Sensor beim Einschalten zufaellig vergibt und dem Kanal.<br>
  </ul>
  <br>
  <a name="SD_WS07 Events"></a>
  <b>Generierte Readings:</b>
  <ul>
     <li>state: (T: H:)</li>
     <li>temperature: (&deg;C)</li>
     <li>humidity: (Luftfeuchte (1-100)</li>
     <li>batteryState: (low oder ok)</li>
     <li>channel: (Der Sensor Kanal)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li>offset-temp<br>
       Damit kann die Temperatur korrigiert werden. z.B. mit 10 wird eine um 10 Grad h&ouml;here Temperatur angezeigt.<br>
    </li>
    <li>offset-hum<br>
       Damit kann die Luftfeuchtigkeit korrigiert werden.<br>
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li>max-deviation-hum (Default:1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
		Maximal erlaubte Abweichung der gemessenen Feuchte zum vorhergehenden Wert in Prozent.<br>
		Da diese Sensoren keine Checksummen o.&auml;. senden, kann es leicht zum Empfang von unplausiblen Werten kommen. 
		Um diese abzufangen, kann eine maximale Abweichung zum letzten korrekt empfangenen Wert festgelegt werden.
		Gr&ouml&szlig;ere Abweichungen werden dann ignoriert und f&uuml;hren zu einer Fehlermeldung im Logfile, wie z.B. dieser:<br>
		<code>SD_WS07_TH_1 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>
		Zus&auml;tzlich zum eingestellten Wert wird ein von der Differenz der Empfangszeiten abh&auml;ngiger Wert addiert.
		Dieser betr&auml;gt 1.0 % relative Feuchte pro Minute. Das bedeutet z.B. wenn eine Differenz von 8 eingestellt ist
		und der zeitliche Abstand des Empfangs der Nachrichten betr&auml;gt 3 Minuten, ist die maximal erlaubte Differenz 11.
    </li>
    <li>max-deviation-temp (Default:1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
		Maximal erlaubte Abweichung der gemessenen Temperatur zum vorhergehenden Wert in Kelvin.<br>
		siehe max-deviation-hum
    </li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
  <ul>
	Anstelle der Attribute <code>max-deviation-hum</code> und <code>max-deviation-temp</code> kann bei gutem Empfang des Sensors 
	auch das Attribut <code>doubleMsgCheck_IDs</code> des SIGNALduino verwendet werden. Dabei wird ein Update der Readings erst
	ausgef&uuml;hrt, wenn mindestens zweimal die gleichen Werte empfangen wurden.
  </ul>
  <br>

  <a name="SD_WS071_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS07_Get"></a>
  <b>Get</b> <ul>N/A</ul><br>


</ul>

=end html_DE
=cut
