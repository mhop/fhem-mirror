##############################################
# $Id$
#
# The purpose of this module is to support serval
# weather sensors which use various protocol
# Sidey79 & Ralf9  2016
#

package main;


use strict;
use warnings;

#use Data::Dumper;


sub SD_WS_Initialize($)
{
	my ($hash) = @_;

	$hash->{Match}		= '^[W]\d+#.*';
	$hash->{DefFn}		= "SD_WS_Define";
	$hash->{UndefFn}	= "SD_WS_Undef";
	$hash->{ParseFn}	= "SD_WS_Parse";
	$hash->{AttrFn}		= "SD_WS_Attr";
	$hash->{AttrList}	= "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
				"$readingFnAttributes ";
	$hash->{AutoCreate} =
	{ 
		"SD_WS37_TH.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"},
		"SD_WS50_SM.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"} 
	
	};

}




#############################
sub SD_WS_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	return "wrong syntax: define <name> SD_WS <code> ".int(@a) if(int(@a) < 3 );

	$hash->{CODE} = $a[2];
	$hash->{lastMSG} =  "";
	$hash->{bitMSG} =  "";

	$modules{SD_WS}{defptr}{$a[2]} = $hash;
	$hash->{STATE} = "Defined";

	my $name= $hash->{NAME};
	return undef;
}

#####################################
sub SD_WS_Undef($$)
{
	my ($hash, $name) = @_;
	delete($modules{SD_WS}{defptr}{$hash->{CODE}})
		if(defined($hash->{CODE}) && defined($modules{SD_WS}{defptr}{$hash->{CODE}}));
	return undef;
}


###################################
sub SD_WS_Parse($$)
{
	my ($iohash, $msg) = @_;
	#my $rawData = substr($msg, 2);
	my $name = $iohash->{NAME};
	my ($protocol,$rawData) = split("#",$msg);
	$protocol=~ s/^[WP](\d+)/$1/; # extract protocol
	
	
	
	my $dummyreturnvalue= "Unknown, please report";
	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	my $bitData2;
	
	my $model;	# wenn im elsif Abschnitt definiert, dann wird der Sensor per AutoCreate angelegt
	my $SensorTyp;
	my $id;
	my $bat;
	my $channel;
	my $rawTemp;
	my $temp;
	my $hum;
	my $trend;
	
	my %decodingSubs  = (
    50    => # Protocol 50
     # FF550545FF9E
     # FF550541FF9A 
	 # AABCDDEEFFGG
 	 # A = Preamble, always FF
 	 # B = TX type, always 5
 	 # C = Address (5/6/7) > low 2 bits = 1/2/3
 	 # D = Soil moisture 05% 
 	 # E = temperature 
 	 # F = security code, always F
 	 # G = Checksum 55+05+45+FF=19E CRC value = 9E
        {   # subs to decode this
        	sensortype => 'XT300',
        	model => 'SD_WS_50_SM',
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^FF5[0-9A-F]{5}FF[0-9A-F]{2}/); }, 		# prematch
			crcok => sub {my $msg = shift; return 1 if ((hex(substr($msg,2,2))+hex(substr($msg,4,2))+hex(substr($msg,6,2))+hex(substr($msg,8,2))&0xFF) == (hex(substr($msg,10,2))) );  }, 	# crc
			id => sub {my $msg = shift; return (hex(substr($msg,2,2)) &0x03 ); },   							#id
			#temp => sub {my $msg = shift; return  (sprintf('%x',((hex(substr($msg,6,2)) <<4)/2/10)));  },		#temp
			#temphex => sub {my $msg = shift; return  sprintf("%04X",((hex(substr($msg,6,2)))<<4)/2);  },			#temp
			temp => sub {my $msg = shift; return  ((hex(substr($msg,6,2)))-40)  },								#temp
			#hum => sub {my $msg = shift; return (printf('%02x',hex(substr($msg,4,2))));  }, 					#hum
			hum => sub {my $msg = shift; return hex(substr($msg,4,2));  }, 										#hum
			channel => sub {my (undef,$bitData) = @_; return ( SD_WS_binaryToNumber($bitData,12,15)&0x03 );  }, #channel
        },	
     33 =>
   	 	 {
     		sensortype => 's014/TFA 30.3200/TCM/Conrad',
        	model =>	'SD_WS_33_TH',
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{10,11}/); }, 							# prematch
			crcok => 	sub {return SD_WS_binaryToNumber($bitData,36,39);  }, 										# crc
			id => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,9); },   				# id
	#		sendmode =>	sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,10,11) eq "1" ? "manual" : "auto";  }
			temp => 	sub {my (undef,$bitData) = @_; return (((SD_WS_binaryToNumber($bitData,22,25)*256 +  SD_WS_binaryToNumber($bitData,18,21)*16 + SD_WS_binaryToNumber($bitData,14,17)) *10 -12200) /18)/10;  },	#temp
			hum => 		sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,30,33)*16 + SD_WS_binaryToNumber($bitData,26,29));  }, 					#hum
			channel => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,12,13)+1 );  }, 		#channel
     		bat => 		sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,34) eq "1" ? "ok" : "critical");},
    # 		sync => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,35,35) eq "1" ? "true" : "false");},
   	 	 }        
        
        
    );
    
    	
	Log3 $name, 4, "SD_WS_Parse: Protocol: $protocol, rawData: $rawData";
	
	if ($protocol == "37")		# Bresser 7009994
	{
		# 0      7 8 9 10 12        22   25    31
		# 01011010 0 0 01 01100001110 10 0111101 11001010
		# ID      B? T Kan Temp       ?? Hum     Pruefsumme?
		
		# MU;P0=729;P1=-736;P2=483;P3=-251;P4=238;P5=-491;D=010101012323452323454523454545234523234545234523232345454545232345454545452323232345232340;CP=4;
		
		$model = "SD_WS37_TH";
		$SensorTyp = "Bresser 7009994";
	
		$id = 		SD_WS_binaryToNumber($bitData,0,7);
		#$bat = 	int(substr($bitData,8,1)) eq "1" ? "ok" : "low";
		$channel = 	SD_WS_binaryToNumber($bitData,10,11);
		$rawTemp = 	SD_WS_binaryToNumber($bitData,12,22);
		$hum =		SD_WS_binaryToNumber($bitData,25,31);
		
		$id = sprintf('%02X', $id);           # wandeln nach hex
		$temp = ($rawTemp - 609.93) / 9.014;
		$temp = sprintf("%.1f", $temp);
		
		if ($hum < 10 || $hum > 99 || $temp < -30 || $temp > 70) {
			return "";
		}
	
		$bitData2 = substr($bitData,0,8) . ' ' . substr($bitData,8,4) . ' ' . substr($bitData,12,11);
		$bitData2 = $bitData2 . ' ' . substr($bitData,23,2) . ' ' . substr($bitData,25,7) . ' ' . substr($bitData,32,8);
		Log3 $iohash, 4, "$name converted to bits: " . $bitData2;
		Log3 $iohash, 4, "$name decoded protocolid: $protocol ($SensorTyp) sensor id=$id, channel=$channel, rawTemp=$rawTemp, temp=$temp, hum=$hum";
	}
	elsif ($protocol != "37" && defined($decodingSubs{$protocol}))		# alles was nicht Protokoll #37 ist, durch den hash decodieren
	{
	 
	 	   	$SensorTyp=$decodingSubs{$protocol}{sensortype};
		    
		    return "" && Log3 $iohash, 4, "$name decoded protocolid: $protocol ($SensorTyp) prematch error" if (!$decodingSubs{$protocol}{prematch}->( $rawData ));
		    return "" && Log3 $iohash, 4, "$name decoded protocolid: $protocol ($SensorTyp) crc  error"  if (!$decodingSubs{$protocol}{crcok}->( $rawData ));
		    
	    	$id=$decodingSubs{$protocol}{id}->( $rawData,$bitData );
	    	#my $temphex=$decodingSubs{$protocol}{temphex}->( $rawData,$bitData );
	    	
	    	$temp=$decodingSubs{$protocol}{temp}->( $rawData,$bitData );
	    	$hum=$decodingSubs{$protocol}{hum}->( $rawData,$bitData );
	    	$channel=$decodingSubs{$protocol}{channel}->( $rawData,$bitData );
	    	$model = $decodingSubs{$protocol}{model};
	    	$bat = $decodingSubs{$protocol}{bat};

	    	Log3 $iohash, 4, "$name decoded protocolid: $protocol ($SensorTyp) sensor id=$id, channel=$channel, temp=$temp, hum=$hum";
		
	} 
	else {
		Log3 $iohash, 4, "SD_WS_Parse: unknown message, please report. converted to bits: $bitData";
		return undef;
	}


	if (!defined($model)) {
		return undef;
	}
	
	my $deviceCode;
	
	my $longids = AttrVal($iohash->{NAME},'longids',0);
	if (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
	{
		$deviceCode = $model . '_' . $id . $channel;
		Log3 $iohash,4, "$name using longid: $longids model: $model";
	} else {
		$deviceCode = $model . "_" . $channel;
	}
	
	#print Dumper($modules{SD_WS}{defptr});
	
	my $def = $modules{SD_WS}{defptr}{$iohash->{NAME} . "." . $deviceCode};
	$def = $modules{SD_WS}{defptr}{$deviceCode} if(!$def);

	if(!$def) {
		Log3 $iohash, 1, 'SD_WS: UNDEFINED sensor ' . $model . ' detected, code ' . $deviceCode;
		return "UNDEFINED $deviceCode SD_WS $deviceCode";
	}
	#Log3 $iohash, 3, 'SD_WS: ' . $def->{NAME} . ' ' . $id;
	
	my $hash = $def;
	$name = $hash->{NAME};
	Log3 $name, 4, "SD_WS: $name ($rawData)";  

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
	if (defined($bitData2)) {
		$hash->{bitMSG} = $bitData2;
	} else {
		$hash->{bitMSG} = $bitData;
	}

	my $state = "T: $temp" . ($hum > 0 ? " H: $hum":"");

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $state);
	readingsBulkUpdate($hash, "temperature", $temp)  if (defined($temp));
	readingsBulkUpdate($hash, "humidity", $hum)  if (defined($hum) && $hum > 0);
	readingsBulkUpdate($hash, "battery", $bat) if (defined($bat));
	readingsBulkUpdate($hash, "channel", $channel) if (defined($channel));
	readingsBulkUpdate($hash, "trend", $trend) if (defined($trend));
	
	readingsEndUpdate($hash, 1); # Notify is done by Dispatch
	
	return $name;

}

sub SD_WS_Attr(@)
{
	my @a = @_;
	
	# Make possible to use the same code for different logical devices when they
	# are received through different physical devices.
	return  if($a[0] ne "set" || $a[2] ne "IODev");
	my $hash = $defs{$a[1]};
	my $iohash = $defs{$a[3]};
	my $cde = $hash->{CODE};
	delete($modules{SD_WS}{defptr}{$cde});
	$modules{SD_WS}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
	return undef;
}


sub SD_WS_binaryToNumber
{
	my $binstr=shift;
	my $fbit=shift;
	my $lbit=$fbit;
	$lbit=shift if @_;
	
	return oct("0b".substr($binstr,$fbit,($lbit-$fbit)+1));
}

1;

=pod
=item summary    Supports various weather stations
=item summary_DE Unterst&uumltzt verschiedene Funk Wetterstationen
=begin html

<a name="SD_WS"></a>
<h3>Weather Sensors various protocols</h3>
<ul>
  The SD_WS module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>Bresser 7009994</li>
    <li>Opus XT300</li>
  </ul>
  <br>
  New received device are add in fhem with autocreate.
  <br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defice is the cannel or, if the longid attribute is specified, it is a combination of channel and some random generated bits at powering the sensor and the channel.<br>
  If you want to use more sensors, than channels available, you can use the longid option to differentiate them.
  </ul>
  <br>
  <a name="SD_WS Events"></a>
  <b>Generated readings:</b>
  <br>Some devices may not support all readings, so they will not be presented<br>
  <ul>
  	 <li>State (T: H:)</li>
     <li>temperature (&deg;C)</li>
     <li>humidity: (The humidity (1-100 if available)</li>
     <li>battery: (low or ok)</li>
     <li>channel: (The Channelnumber (number if)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="SD_WS_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="SD_WS"></a>
<h3>SD_WS</h3>
<ul>
  Das SD_WS Modul verarbeitet von einem IO Ger&aumlt (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b>
  <ul>
    <li>Bresser 7009994</li>
    <li>Opus XT300</li>

  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelgten Sensoren ist entweder der Kanal des Sensors, oder wenn das Attribut longid gesetzt ist, dann wird die ID aus dem Kanal und einer Reihe von Bits erzeugt, welche der Sensor beim Einschalten zuf&aumlllig vergibt.<br>
  </ul>
  <br>
  <a name="SD_WS Events"></a>
  <b>Generierte Readings:</b>
  <ul>
  	 <li>State (T: H:)</li>
     <li>temperature (&deg;C)</li>
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

  <a name="SD_WS_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut
