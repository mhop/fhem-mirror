# Modul für  I2C Temperatur- und Feuchtigkeitssensor HDC1008
# Autor : Karsten Grüttner (schlawiano) bis 2016, Änderungen ab 2018: Gernot Hillier (yoda_gh)
# $Id$
# Technische Dokumention für den Sensor befindet sich  http://www.ti.com/lit/ds/symlink/hdc1008.pdf


package main;
use strict;
use warnings;




# Konfigurationsparameter Temperatur, Lesedauer in Microsekunden und Konfigurationscode als Word (Bit 10)
my %I2C_HDC1008_tempParams = 
( 
	'11Bit' => {delay => 3650, code =>  1 << 10 },
	'14Bit' => {delay => 6350, code =>  0 }
); 


# Konfigurationsparameter Feuchtigkeit, Lesedauer in Microsekunden und Konfigurationscode als Word (Bit 9:8)
my %I2C_HDC1008_humParams =  # 
( 
	'8Bit' =>  {delay => 2500, code =>  1 << 9	},
	'11Bit' => {delay => 3850, code => 1 << 8 } ,
	'14Bit' => {delay => 6500, code => 0 }  
);


# Konfigurationsparameter Heizelement,  Konfigurationscode als Word (Bit 13 )
my %I2C_HDC1008_validsHeater =  
(
	'off' => 0, 		# 0
	'on' =>  1 << 13 	# 1
);


sub I2C_HDC1008_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'I2C_HDC1008_Define';
    $hash->{UndefFn}    = 'I2C_HDC1008_Undef';
    $hash->{SetFn}      = 'I2C_HDC1008_Set';
    
    $hash->{AttrFn}     = 'I2C_HDC1008_Attr';
    $hash->{ReadFn}     = 'I2C_HDC1008_Read';
	$hash->{I2CRecFn} 	= 'I2C_HDC1008_I2CRec';
    $hash->{AttrList} =
          "interval ".
		  "IODev ".
		  "Resolution_Temperature:11Bit,14Bit ". # als Dropdown
		  "Resolution_Humidity:8Bit,11Bit,14Bit ". # als Dropdown
		  "roundTemperatureDecimal ".
		  "roundHumidityDecimal ".
         $readingFnAttributes;
	
	
}


sub I2C_HDC1008_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	$hash->{MODUL_STATE} = "defined";
	$hash->{RESOLUTION_TEMPERATURE} = '14Bit';
	$hash->{RESOLUTION_HUMIDITY} = '14Bit';
	$hash->{HEATER} = 'off';
	$hash->{INTERVAL} = 0;
	$hash->{DEVICE_STATE} = 'UNKNOWN';
	
	
  if ($main::init_done) {
    eval { I2C_HDC1008_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_HDC1008_Catch($@) if $@;
  }
  else
  {
		Log3 $hash, 5, "[$hash->{NAME}] I2C_HDC1008_Define main::init_done was false";
  }
  
  return undef;
}

sub I2C_HDC1008_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};

	
	
	if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_HDC1008 [<i2caddress>]";
 	}
	 
 	if (defined (my $address = shift @$args)) 
	{
		$address = $address =~ /^0.*$/ ? oct($address) : $address;
		if ($address < 64 && $address > 67) # nur 0x40 bis 0x43 erlaubt
		{
			Log3 $hash, 5, "[$name] I2C Address not valid for HDC1008";
			return "$name I2C Address not valid for HDC1008";
		}
		else
		{
			$hash->{I2C_Address} = $address;
		}	
		 
 	} 
	else 
	{
		$hash->{I2C_Address} = oct('0x40');
		Log3 $name, 5, "[$name] I2C_HDC1008_Init default-I2C-addresse 0x40 used";
	}
	
	my $msg = '';

	$msg = CommandAttr(undef, $name . ' interval 5');
	if ($msg) {
		
		
		Log3 $hash, 5, "[$name] I2C_HDC1008_Init interval:".$msg;
		return $msg;
	}

	
	AssignIoPort($hash);	
	
	if (defined AttrVal($hash->{NAME}, "IODev", undef))
	{
		$hash->{MODUL_STATE} = 'Initialized';
		$hash->{DEVICE_STATE} = 'READY';
		
	}
	else
	{
		$hash->{MODUL_STATE} = "Error: Missing Attr 'IODev'";
	}

	return undef;
}

sub I2C_HDC1008_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_HDC1008_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) 
	{ 			
													#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		my $upper_k = uc $k;
		$hash->{$upper_k} = $v if $k =~ /^$pname/ ;
	}
	if ($clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"}) {
		my $sendstat = $clientmsg->{$pname . "_SENDSTAT"};
		Log3 $hash, 5, "[$name] I2C_HDC1008_I2CRec  $clientmsg->{direction} $sendstat ";
		if ( $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
			if ( $clientmsg->{direction} eq "i2cwrite" ) {
				if ($hash->{DEVICE_STATE} eq 'READY') {
					$hash->{DEVICE_STATE} = 'CONFIGURING';
				} elsif($hash->{DEVICE_STATE} eq 'CONFIGURING') {
					$hash->{DEVICE_STATE} = 'MEASURING';
				}
			}
			
			if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) 
			{
				Log3 $hash, 5, "[$name] I2C_HDC1008_I2CRec  received: $clientmsg->{type} $clientmsg->{received}";
				I2C_HDC1008_GetTemp  ($hash, $clientmsg->{received}) if $clientmsg->{nbyte} == 4;
				I2C_HDC1008_GetHum ($hash, $clientmsg->{received}) if $clientmsg->{nbyte} == 4;
			}
		}
	}
}

sub I2C_HDC1008_GetTemp ($$) 
{
	my ($hash, $rawdata) = @_;
	my $name = $hash->{NAME};
	
	my @raw = split(" ",$rawdata);
	my $tempWord  = ($raw[0] << 8 | $raw[1]);
	
	my $temperature = (($tempWord /65536.0)*165.0)-40.0;

	Log3 $hash, 5, "[$name] I2C_HDC1008_I2CRec  calced Temperatur: $temperature";
	
	
	$temperature = sprintf( '%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',	$temperature );

	readingsSingleUpdate($hash, "temperature", $temperature, 0);
}

sub I2C_HDC1008_GetHum ($$) 
{
	my ($hash, $rawdata) = @_;
	my $name = $hash->{NAME};
	
	my @raw = split(" ",$rawdata);
	my $humWord  = ($raw[0] << 8 | $raw[1]);	
	
	my $humidity  = ($humWord /65536.0)*100.0;

	Log3 $hash, 5, "[$name] I2C_HDC1008_I2CRec  calced humidity: $humidity";
	
	my $temperature = ReadingsVal($hash->{NAME} ,"temperature","0");
	$humidity = sprintf( '%.' . AttrVal($hash->{NAME}, 'roundHumidityDecimal', 1) . 'f', $humidity 	);	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'humidity', $humidity);
	readingsBulkUpdate($hash, 'temperature', $temperature);
	readingsBulkUpdate(
		$hash,
		'state',
		'T: ' . $temperature . ' H: ' . $humidity
	);
	
	
	readingsEndUpdate($hash, 1);	
	
	
}

sub I2C_HDC1008_Undef($$) 
{
	my ($hash, $name) = @_;
	
	if ( defined (AttrVal($hash->{NAME}, "interval", undef)) ) 
	{
		RemoveInternalTimer($hash);
	}
	
    return undef;
}


sub I2C_HDC1008_Reset($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if ($hash->{MODUL_STATE} ne 'Initialized') { return "Error MODULE_STATE in $name  is not 'Initialized' " };
	
  	return "$name: no IO device defined" unless ($hash->{IODev});
	
	my $Param =  1 << 15; # Bit 15 für Reset
	
	my $low_byte = $Param & 0xff;
	my $high_byte = ($Param & 0xff00) >> 8;	
	
	my $iodev = $hash->{IODev};
	my $i2caddress = $hash->{I2C_Address};
	
	CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  => "i2cwrite",
				i2caddress => $i2caddress,
				reg => 2,
				data => $high_byte. " ".$low_byte	
				});
	
	RemoveInternalTimer($hash);
	$hash->{DEVICE_STATE} ='READY';
	InternalTimer(gettimeofday() + 15.0/1000, 'I2C_HDC1008_Poll', $hash, 0);		# Sensor braucht bis 15 ms bis er bereit ist	
		
}


# Funktion holt die Werte vom Sensor via I2C
#	asynchrones Lesen, über Status-Wechsel in $hash->{DEVICE_STATE} und Rückgabe der notwendigen Dauer des aktuellen Schritts in Sekunden, 
# 	die dann an den Timer gegeben wird. Der schaut nach Ablauf der Zeit hier wieder vorbei und weiß als nächstes zu tun ist,
#   andere Prozesse werden dabei nicht mehr blockiert.

sub I2C_HDC1008_UpdateValues($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if ($hash->{MODUL_STATE} ne 'Initialized') { return "Error MODULE_STATE in $name  is not 'Initialized' " };
	
  	return "$name: no IO device defined" unless ($hash->{IODev});


	Log3 $name, 5, "[$name] I2C_HDC1008_UpdateValues starts with state: $hash->{DEVICE_STATE}";
	
	# baue Konfigurationsparameter zusammen
	
	my $modeReading = 1 << 12; # lies beides gleichzeitig
	
	my $resTempIndex = $hash->{RESOLUTION_TEMPERATURE};
	my $resHumIndex = $hash->{RESOLUTION_HUMIDITY};
	my $heaterIndex = $hash->{HEATER};
	
	my $resTempParam = $I2C_HDC1008_tempParams{$resTempIndex}{code};
	my $resHumParam = $I2C_HDC1008_humParams{$resHumIndex}{code};
	my $heaterParam = $I2C_HDC1008_validsHeater{$heaterIndex};
	
	my $iodev = $hash->{IODev};
	my $i2caddress = $hash->{I2C_Address};
		
		
	if ($hash->{DEVICE_STATE} eq 'READY')
	{
	
		my $Param = $modeReading | $resTempParam | $resHumParam | $heaterParam;
		
		
		# schicke Konfiguration zum HDC1008-Sensor 
		# --------------------------------------------------------

		my $low_byte = $Param & 0xff;
		my $high_byte = ($Param & 0xff00) >> 8;	
		
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
					direction  => "i2cwrite",
					i2caddress => $i2caddress,
					reg => 2,
					data => $high_byte. " ".$low_byte	# Leider fehlt es hier an Doku. Laut Quellcode (00_RPII2C.pm, ab Zeile 369),  werden die  dezimale Zahlen durch Leerzeichen getrennt, binär gewandelt und zum I2C-Bus geschickt
					});
		return 15.0/1000; # Sensor braucht bis 15 ms bis er bereit ist
	}
	elsif($hash->{DEVICE_STATE} eq 'CONFIGURING')
	{
		# HDC1008-Sensor soll messen
		# --------------------------------------------------------
		
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
					direction  => "i2cwrite",
					i2caddress => $i2caddress,
					data => (0)
					});				
					
		my $tempWait = $I2C_HDC1008_tempParams{$resTempIndex}{delay} + 
		               $I2C_HDC1008_humParams{$resTempIndex}{delay};  # in ns
		return $tempWait/1000000.0; 
		
	}
	elsif($hash->{DEVICE_STATE} eq 'MEASURING')
	{
	
		# Werte vom HDC1008-Sensor lesen
		# --------------------------------------------------------	
		
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {	# Leider fehlt es hier an Doku. daher hier der Hinweis bei erfolgreichem Lesen wird die Funktion in $hash->{I2CRecFn} aufgerufen	
				direction  => 	"i2cread",
				i2caddress => 	$i2caddress,
				nbyte => 		4
				});	
	
		# fertig	
		
		$hash->{DEVICE_STATE} = 'READY';
		my $pollInterval = AttrVal($hash->{NAME}, 'interval', 0); 
		return $pollInterval * 60; # Pollintervall in Minuten
	}
	else
	{
		Log3 $name, 5, "[$name] I2C_HDC1008_UpdateValues wtf... whats wrong   !!!!!!!!!!!!!!";
		
		$hash->{DEVICE_STATE} = 'READY';
		my $pollInterval = AttrVal($hash->{NAME}, 'interval', 0); 
		return $pollInterval * 60; # Pollintervall in Minuten
	}

	


}



# set wenn Befehl gesetzt wurde und nicht '?' ist, 
#	dann führe Befehl aus und gib den Status zurück
# 	ansonsten gib alle Befehle und deren Optionen zurück

sub I2C_HDC1008_Set($@) {
	my ($hash, @param) = @_;
	

	
	return '"set HDC1008" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $cmd = shift @param;
	my $val = join("", @param);
	
	if (defined $cmd && $cmd ne '?') # falls set mit Kommand aufgerufen wurde
	{
		if ($cmd eq 'Heater')
		{
			if ( defined($I2C_HDC1008_validsHeater{$val}) )
			{			
				$hash->{HEATER} = $val;
				return undef;
			}
			else
			{	
				return "Invalid value for setting 'Heater'";
			}
			
		}
		elsif ($cmd eq 'Update')
		{
			
			
			RemoveInternalTimer($hash);
			$hash->{DEVICE_STATE} ='READY';
			I2C_HDC1008_Poll($hash);
	
			return undef;
		}
		elsif ($cmd eq 'Reset')
		{
			I2C_HDC1008_Reset($hash);
			return undef;
		}		
		
	
		# Debug("Set HDC1008 $cmd");
		return -1;
	}
	else	# Ansonsten Rückgabe was an set - Optionen möglich ist
	{
		return "Update:noArg Heater:off,on Reset:noArg ";
	}
	
	
}

sub I2C_HDC1008_CheckState
{
	my ($hash) = @_;
	if ($hash->{MODUL_STATE} ne 'Initialized')
	{
	
		my @def = split (' ',$hash->{DEF});
		I2C_HDC1008_Init($hash,\@def) if (defined ($hash->{IODev}));
	}
}

sub I2C_HDC1008_Poll
{
	my ($hash) = @_;
	I2C_HDC1008_CheckState($hash);
	my $name = $hash->{NAME};
	
	 
	
	my $delay = I2C_HDC1008_UpdateValues($hash);
	
	my $ret = I2C_HDC1008_Catch($@) if $@;
	

	if ($delay > 0) 
	{
		Log3 $hash, 5, "[$name] I2C_HDC1008_Poll call InternalTimer with $delay seconds";
		InternalTimer(gettimeofday() + $delay, 'I2C_HDC1008_Poll', $hash, 0);
	}
	else
	{
		Log3 $name, 5, "[$name] I2C_HDC1008_Poll dont call InternalTimer, nothing todo";
	}
	return;
}

sub I2C_HDC1008_Attr(@) 
{
	
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = '';
 
	if ($attr eq 'interval') 
	{
		if ( defined($val) ) 
		{
			if ( looks_like_number($val) && $val > 0) 
			{
				RemoveInternalTimer($hash);
				$hash->{DEVICE_STATE} = 'READY';
				InternalTimer(1, 'I2C_HDC1008_Poll', $hash, 0);
				$hash->{INTERVAL} = $val;
				Log3 $hash, 5, "[$hash->{NAME}] I2C_HDC1008_Attr call InternalTimer with new value  $val ";
			} else 
			{
				$msg .= "$hash->{NAME}: Wrong poll intervall defined. interval must be a number > 0";
				Log3 $hash, 5, "[$hash->{NAME}] I2C_HDC1008_Attr Wrong poll intervall defined. interval must be a number > 0";
				$hash->{INTERVAL} = 0;
			}
		} 
		else 
		{ #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
			RemoveInternalTimer($hash);
			$hash->{INTERVAL} = 0;
		}
	}
	
	elsif ($attr eq 'Resolution_Temperature') 
	{
	
		if (!defined($val))
		{
			$hash->{RESOLUTION_TEMPERATURE} = '14Bit';
		}	
		elsif ( defined($I2C_HDC1008_tempParams{$val}{code}) ) 
		{	
			$hash->{RESOLUTION_TEMPERATURE} = $val;
		}
		else	
		{
			$msg .= "invalid value for attribute $attr";
		}
	}
	
	elsif ($attr eq 'Resolution_Humidity') 
	{
		if (!defined($val))
		{
			$hash->{RESOLUTION_HUMIDITY} = '14Bit';
		}			
		elsif ( defined($I2C_HDC1008_humParams{$val}{code}) ) 
		{	
			$hash->{RESOLUTION_HUMIDITY} = $val;
		}
		else	
		{
			$msg .= "invalid value for attribute $attr";
		}		
	}
	
	elsif ($command && $command eq "set" && $attr && $attr eq "IODev") 
	{
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) 
		{
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_HDC1008_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
	
	elsif ( ($attr eq 'roundTemperatureDecimal') || ($attr eq 'roundHumidityDecimal')) 
	{
		if (!defined($val))
		{
			return undef;
		}
		elsif (!(looks_like_number($val) && ($val>=0 ))) 
		{
			$msg .= "$attr must be a number >= 0"
		}
	}
	
	return ($msg) ? $msg : undef;
}

1;

=pod
=item device
=item summary read Texas Instruments HDC1008/1080 temp/humidity sensor via I2C bus
=item summary_DE Texas Instruments HDC1008/1080 Temp./Feuchte-Sensor über I2C auslesen
=begin html

<a name="I2C_HDC1008"></a>
<h3>I2C_HDC1008</h3>
<ul>
	<a name="I2C_HDC1008"></a>
		Provides an interface to the I2C_HDC1008 I2C Humidity sensor from <a href=" http://www.ti.com">Texas Instruments</a>.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_HDC1008Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_HDC1008 [&lt;I2C Address&gt;]</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
	</ul>
	<a name="I2C_HDC1008Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; Update</code><br>
		Reads the current temperature and humidity values from sensor.<br><br>
		<code>set &lt;name&gt; Reset</code><br>
		Resets the sensor
		<code>set &lt;name&gt; Heater {on|off}</code><br>
		turns the sensor heater on or off
	</ul>
	<a name="I2C_HDC1008Attr"></a>
	<b>Attributes</b>
	<ul>
		<li>interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>Resolution_Temperature<br>
			resolution for measurement temperature.<br>
			Standard: 14Bit, valid values: 11Bit, 14Bit<br><br>
		</li>
		<li>Resolution_Humidity<br>
			resolution for measurement humidity.<br>
			Standard: 14Bit, valid values: 8Bit, 11Bit, 14Bit<br><br>
		</li>		
		<li>roundHumidityDecimal<br>
			Number of decimal places for humidity value<br>
			Default: 1, valid values: 0 1 2,...<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Number of decimal places for temperature value<br>
			Default: 1, valid values: 0,1,2,...<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>

	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_HDC1008"></a>
<h3>I2C_HDC1008</h3>
<ul>
	<a name="I2C_HDC1008"></a>
		Erm&ouml;glicht die Verwendung eines I2C_HDC1008 I2C Feuchtesensors von <a href=" http://www.ti.com">Texas Instruments</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_HDC1008Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_HDC1008 [&lt;I2C Address&gt;]</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
	</ul>
	<a name="I2C_HDC1008Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; Update</code><br>
		Aktuelle Temperatur und Feuchte Werte vom Sensor lesen.<br><br>
		<code>set &lt;name&gt; Reset</code><br>
		Setzt den Sensor zur&uuml;ck
		<code>set &lt;name&gt; Heater {on|off}</code><br>
		Schaltet das Heizelement des Sensors an oder aus
	</ul>
	<a name="I2C_HDC1008Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li>Resolution_Temperature<br>
			Genauigkeit mit der die Temperatur gemessen werden soll.<br>
			Standard: 14Bit, g&uuml;ltige Werte: 11Bit, 14Bit<br><br>
		</li>
		<li>Resolution_Humidity<br>
			Genauigkeit mit der die Feuchtigkeit gemessen werden soll.<br>
			Standard: 14Bit, g&uuml;ltige Werte: 8Bit, 11Bit, 14Bit<br><br>
		</li>
		<li>roundHumidityDecimal<br>
			Anzahl Dezimalstellen f&uuml;r den Feuchtewert<br>
			Standard: 1, g&uuml;ltige Werte: 0 1 2<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Anzahl Dezimalstellen f&uuml;r den Temperaturwert<br>
			Standard: 1, g&uuml;ltige Werte: 0,1,2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>

	</ul><br>
</ul>

=end html

=cut
