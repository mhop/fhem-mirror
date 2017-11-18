##############################################
# $Id$
# 
# The purpose of this module is to support serval eurochron
# weather sensors like eas8007 which use the same protocol
# Sidey79, Ralf9  2015-2017
#

package main;


use strict;
use warnings;

#use Data::Dumper;


sub
SD_WS07_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^P7#[A-Fa-f0-9]{6}F[A-Fa-f0-9]{2}(#R[A-F0-9][A-F0-9]){0,1}\$";    ## pos 7 ist aktuell immer 0xF
  $hash->{DefFn}     = "SD_WS07_Define";
  $hash->{UndefFn}   = "SD_WS07_Undef";
  $hash->{ParseFn}   = "SD_WS07_Parse";
  $hash->{AttrFn}    = "SD_WS07_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                        "$readingFnAttributes ";
  $hash->{AutoCreate} =
        { "SD_WS07.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"} };


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
  #my $rawData = substr($msg, 2);
  my $name = $iohash->{NAME};
  my (undef ,$rawData, $rssi) = split("#",$msg);
  if (defined($rssi)) {
	$rssi = hex(substr($rssi,1));
	$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
  }
  #$protocol=~ s/^P(\d+)/$1/; # extract protocol

  my $model = "SD_WS07";
  my $hlen = length($rawData);
  my $blen = $hlen * 4;
  my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 

  if (defined($rssi)) {
	Log3 $name, 4, "$name SD_WS07_Parse  $model ($msg) length: $hlen RSSI = $rssi";
  } else {
	Log3 $name, 4, "$name SD_WS07_Parse  $model ($msg) length: $hlen";
  }
  
  
  #      4    8  9    12            24    28     36
  # 0011 0110 1  010  000100000010  1111  00111000 0000  eas8007
  # 0111 0010 1  010  000010111100  1111  00000000 0000  other device from anfichtn
  #      ID  Bat CHN       TMP      ??   HUM
  
  #my $hashumidity = FALSE;
  
  ## Todo: Change decoding per model into a foreach  
   #foreach $key (keys %models) {
  #   ....
  #}
    my $bitData2 = substr($bitData,0,8) . ' ' . substr($bitData,8,1) . ' ' . substr($bitData,9,3);
       $bitData2 = $bitData2 . ' ' . substr($bitData,12,12) . ' ' . substr($bitData,24,4) . ' ' . substr($bitData,28,8);
    Log3 $iohash, 5, $model . ' converted to bits: ' . $bitData2;
    
    my $id = substr($rawData,0,2);
    my $bat = int(substr($bitData,8,1)) eq "1" ? "ok" : "low";
    my $channel = oct("0b" . substr($bitData,9,3)) + 1;
    my $temp = oct("0b" . substr($bitData,12,12));
    my $bit24bis27 = oct("0b".substr($bitData,24,4));
    my $hum = oct("0b" . substr($bitData,28,8));
    
    if ($hum==0)
    {
    	$model=$model."_T";		
    } else {
    	$model=$model."_TH";		
    	if ($hum < 10 || $hum > 99) {
    	    return '';
    	}
    }
    
    if ($temp > 700 && $temp < 3840) {
      return '';
    } elsif ($temp >= 3840) {        # negative Temperaturen, muss noch ueberprueft und optimiert werden 
      $temp -= 4095;
    }  
    $temp /= 10;
    
    Log3 $iohash, 4, "$name $model decoded protocolid: 7 sensor id=$id, channel=$channel, temp=$temp, hum=$hum, bat=$bat";

    my $deviceCode;
    
	my $longids = AttrVal($iohash->{NAME},'longids',0);
	if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
	{
		$deviceCode=$model.'_'.$id.$channel;
		Log3 $iohash,4, "$name using longid: $longids model: $model";
	} else {
		$deviceCode = $model . "_" . $channel;
	}
    
    #print Dumper($modules{SD_WS07}{defptr});
    
    my $def = $modules{SD_WS07}{defptr}{$iohash->{NAME} . "." . $deviceCode};
    $def = $modules{SD_WS07}{defptr}{$deviceCode} if(!$def);

    if(!$def) {
		Log3 $iohash, 1, "$name SD_WS07: UNDEFINED sensor $model detected, code $deviceCode";
		return "UNDEFINED $deviceCode SD_WS07 $deviceCode";
    }
        #Log3 $iohash, 3, 'SD_WS07: ' . $def->{NAME} . ' ' . $id;
	
	my $hash = $def;
	$name = $hash->{NAME};
	return "" if(IsIgnored($name));
	
	Log3 $name, 4, "$iohash->{NAME} SD_WS07: $name ($rawData)";  

	if (!defined(AttrVal($hash->{NAME},"event-min-interval",undef)))
	{
		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
			Log3 $hash, 4, "$deviceCode Dropped due to short time. minsecs=$minsecs";
		  	return "";
		}
	}

	$hash->{lastReceive} = time();
	$hash->{lastMSG} = $rawData;
	$hash->{bitMSG} = $bitData2; 

    my $state = "T: $temp". ($hum>0 ? " H: $hum":"");
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $state);
    readingsBulkUpdate($hash, "temperature", $temp)  if ($temp ne"");
    readingsBulkUpdate($hash, "humidity", $hum)  if ($hum ne "" && $hum != 0 );
    readingsBulkUpdate($hash, "battery", $bat) if ($bat ne "");
    readingsBulkUpdate($hash, "channel", $channel) if ($channel ne "");

    readingsEndUpdate($hash, 1); # Notify is done by Dispatch

    if(defined($rssi)) {
		$hash->{RSSI} = $rssi;
    }

	return $name;

}

sub SD_WS07_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return  if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($modules{SD_WS07}{defptr}{$cde});
  $modules{SD_WS07}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}


1;


=pod
=item summary    Supports weather sensors protocl 7 from SIGNALduino
=item summary_DE Unterst&uumltzt Wettersensoren mit Protokol 7 vom SIGNALduino
=begin html

<a name="SD_WS07"></a>
<h3>Weather Sensors protocol #7</h3>
<ul>
  The SD_WS07 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>Eurochon EAS800z</li>
    <li>Technoline WS6750/TX70DTH</li>
  </ul>
  <br>
  New received devices are added in FHEM with autocreate.
  <br><br>

  <a name="SD_WS07_Define"></a>
  <b>Define</b> 
  <ul>The received devices are created automatically.<br>
  The ID of the defice is the cannel or, if the longid attribute is specified, it is a combination of channel and some random generated bits at powering the sensor and the channel.<br>
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
     <li>battery: (low or ok)</li>
     <li>channel: (the channelnumberf)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

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
  Das SD_WS07 Modul verarbeitet von einem IO Geraet (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b>
  <ul>
    <li>Eurochon EAS800z</li>
    <li>Technoline WS6750/TX70DTH</li>
    <li>TFA 30320902</li>
    <li>FreeTec Aussenmodul fuer Wetterstation NC-7344</li>
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>

  <a name="SD_WS07_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelegten Sensoren ist entweder der Kanal des Sensors, oder wenn das Attribut longid gesetzt ist, dann wird die ID aus dem Kanal und einer Reihe von Bits erzeugt, welche der Sensor beim Einschalten zufaellig vergibt.<br>
  </ul>
  <br>
  <a name="SD_WS07 Events"></a>
  <b>Generierte Readings:</b>
  <ul>
     <li>state: (T: H:)</li>
     <li>temperature: (&deg;C)</li>
     <li>humidity: (Luftfeuchte (1-100)</li>
     <li>battery: (low oder ok)</li>
     <li>channel: (Der Sensor Kanal)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS071_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS07_Get"></a>
  <b>Get</b> <ul>N/A</ul><br>


</ul>

=end html_DE
=cut
