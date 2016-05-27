# Modul für  I2C Lichtsensor GY-30 mit dem AD-Wandler BH1750FVI
# Autor : Karsten Grüttner
# $Id$
# Technische Dokumention für den Sensor befindet sich  http://rohmfs.rohm.com/en/products/databook/datasheet/ic/sensor/light/bh1750fvi-e.pdf


package main;
use strict;
use warnings;
use Time::HiRes qw(usleep);





# Konfigurationsparameter Auflösung, delay nur im Continuously-Mode nach erstem Lesen, ansonsten delayInit
my %I2C_GY30_BH1750FVI_resParams =  # 
( 
	'HalfLux' =>  {delay => 120000, code =>  1, delayInit => 180000	}, 
	'1Lux' => {delay => 120000, code => 0, delayInit => 180000	 } ,
	'4Lux' => {delay => 16000, code => 3, delayInit => 24000, }  
);


# Konfigurationsparameter Betriebsmode
my %I2C_GY30_BH1750FVI_CodeMode =  
(
	'Continuously' => 0x10, 	# einmalig initialisiert, kann immer gelesen werden, geeignet für Dauerüberwachung z.B. Lichtschranke
	'One' =>  0x20 				# wacht zum einmaligen Lesen auf und legt sich wieder schlafen, geeignet z.B. die Lichtverhältnisse draußen zu messen 
);

# Konfigurationsparameter Befehle
my %I2C_GY30_BH1750FVI_CodeCmd = 
(
	'PowerDown' => 0,
	'PowerOn' => 1,
	'Reset' => 7
);


sub I2C_GY30_BH1750FVI_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'I2C_GY30_BH1750FVI_Define';
    $hash->{UndefFn}    = 'I2C_GY30_BH1750FVI_Undef';
    $hash->{SetFn}      = 'I2C_GY30_BH1750FVI_Set';
    $hash->{GetFn}      = 'I2C_GY30_BH1750FVI_Get';
    $hash->{AttrFn}     = 'I2C_GY30_BH1750FVI_Attr';
    $hash->{ReadFn}     = 'I2C_GY30_BH1750FVI_Read';
	$hash->{I2CRecFn} 	= 'I2C_GY30_BH1750FVI_I2CRec';
    $hash->{AttrList} =
          "interval ".
		  "IODev ".
		  "Resolution:HalfLux,1Lux,4Lux ". # als Dropdown
		  "OperationMode:Continuously,One ". # als Dropdown
		  "roundLightIntensityDecimal ".
         $readingFnAttributes;
	
	
}


sub I2C_GY30_BH1750FVI_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	$hash->{MODUL_STATE} = "defined";
	$hash->{RESOLUTION} = 'HalfLux';
	$hash->{OPERATION_MODE} = 'One';
	$hash->{INTERVAL} = 0;
	

  if ($main::init_done) {
    eval { I2C_GY30_BH1750FVI_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_GY30_BH1750FVI_Catch($@) if $@;
  }
  else
  {
		Log3 $hash, 5, "[$hash->{NAME}] I2C_GY30_BH1750FVI_Define main::init_done was false";
  }
  
  return undef;
}

sub I2C_GY30_BH1750FVI_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};

	
	
	if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_GY30_BH1750FVI [<i2caddress>]";
 	}
	 
 	if (defined (my $address = shift @$args)) 
	{
		$address = $address =~ /^0.*$/ ? oct($address) : $address;
		if (! ($address == 35 || $address == 92)) # nur 0x23 (ohne Jumper) oder 0x5C (mit Jumper auf Pin "Add" gegen UCC)
		{
			Log3 $hash, 5, "[$name] I2C Address not valid for GY-30 BH1750FVI";
			return "$name I2C Address not valid for GY-30 BH1750FVI";
		}
		else
		{
			$hash->{I2C_Address} = $address;
		}	
		 
 	} 
	else 
	{
		$hash->{I2C_Address} = oct('0x23');
		Log3 $name, 5, "[$name] I2C_GY30_BH1750FVI_Init default-I2C-addresse 0x23 used";
	}


	my $msg = '';

	$msg = CommandAttr(undef, $name . ' interval 5');
	if ($msg) {
		
		Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_Init interval:".$msg;
		return $msg;
	}
	
	AssignIoPort($hash);	
	
	if (defined AttrVal($hash->{NAME}, "IODev", undef))
	{
		$hash->{MODUL_STATE} = 'Initialized';
		I2C_GY30_BH1750FVI_InitDevice($hash);
		
	}
	else
	{
		$hash->{MODUL_STATE} = "Error: Missing Attr 'IODev'";
	}

	return undef;
}

sub I2C_GY30_BH1750FVI_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_GY30_BH1750FVI_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) 
	{ 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		my $upper_k = uc $k;
		$hash->{$upper_k} = $v if $k =~ /^$pname/ ;
	}
	if ($clientmsg->{direction} && $clientmsg->{type} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) 
		{
			Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_I2CRec  received: $clientmsg->{type} $clientmsg->{received}";
			I2C_GY30_BH1750FVI_GetLightIntensity  ($hash, $clientmsg->{received}) if $clientmsg->{type} eq "light" && $clientmsg->{nbyte} == 2;
			
		}
	}
}

sub I2C_GY30_BH1750FVI_GetLightIntensity ($$) 
{
	my ($hash, $rawdata) = @_;
	my $name = $hash->{NAME};
	
	my @raw = split(" ",$rawdata);
	
	
	my $LightIntensity =  ($raw[1] + $raw[0] * 256) /1.2;

	Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_I2CRec  ".$raw[1].'x'.$raw[0]." calced Light: $LightIntensity";
	
	
	$LightIntensity = sprintf( '%.' . AttrVal($hash->{NAME}, 'roundLightIntensityDecimal', 1) . 'f',	$LightIntensity );

	
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'light_intensity', $LightIntensity);

	readingsBulkUpdate(
		$hash,
		'state',
		'L: ' . $LightIntensity 
	);
	
	
	readingsEndUpdate($hash, 1);	
	
}



sub I2C_GY30_BH1750FVI_Undef($$) 
{
	my ($hash, $name) = @_;
	
	if ( defined (AttrVal($hash->{NAME}, "interval", undef)) ) 
	{
		RemoveInternalTimer($hash);
	}
	
    return undef;
}

# schickt ein Reset, PowerDown oder PowerOn zum Sensor
sub I2C_GY30_BH1750FVI_Command($$)
{
	my ($hash, $cmd) = @_;
	my $name = $hash->{NAME};

	if ($hash->{MODUL_STATE} ne 'Initialized') { return "Error MODULE_STATE in $name  is not 'Initialized' " };
  	return "$name: no IO device defined" unless ($hash->{IODev});
	
	my $iodev = $hash->{IODev};
	my $i2caddress = $hash->{I2C_Address};
	
	my $code =  $I2C_GY30_BH1750FVI_CodeCmd{$cmd};
	
	CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  => "i2cwrite",
				i2caddress => $i2caddress,
				data => $code	
				});
	Time::HiRes::usleep(5); # sollte schnell gehen, aber ob die mikrosekunde ausreicht, wird man sehen.
}

# initialisiert das Gerät
# bei One-Modus, legt er den Sensor schlafen, ansonsten wird er Anhand Auflösung-Parameter in Dauerbetrieb gesetzt

sub I2C_GY30_BH1750FVI_InitDevice($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	if ($hash->{MODUL_STATE} ne 'Initialized') { return "Error MODULE_STATE in $name  is not 'Initialized' " };
  	return "$name: no IO device defined" unless ($hash->{IODev});	
	
	
	if ($hash->{OPERATION_MODE} eq 'One')
	{
		I2C_GY30_BH1750FVI_Command($hash, 'PowerDown'); # bei One kann das Gerät ausgeschalten werden
		
	}
	elsif ($hash->{OPERATION_MODE} eq 'Continuously')
	{
	
		my $resolutionIndex = $hash->{RESOLUTION};
	
		my $codeCont = $I2C_GY30_BH1750FVI_CodeMode{'Continuously'};
		my $codeResolution = $I2C_GY30_BH1750FVI_resParams{$resolutionIndex}{code};
		my $code = $codeCont | $codeResolution;
		
		
		my $delay = $I2C_GY30_BH1750FVI_resParams{$resolutionIndex}{delayInit};
		
		my $iodev = $hash->{IODev};
		my $i2caddress = $hash->{I2C_Address};		
		
		Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_InitDevice send config with ".sprintf("0x%X", $code);
		
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
					direction  => "i2cwrite",
					i2caddress => $i2caddress,
					data => $code	
					});		
		
		Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_InitDevice wait for ".($delay/1000)." ms" ;
		Time::HiRes::usleep($delay);
	}
	
}

sub I2C_GY30_BH1750FVI_UpdateValues($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if ($hash->{MODUL_STATE} ne 'Initialized') { return "Error MODULE_STATE in $name  is not 'Initialized' " };

	my $iodev = $hash->{IODev};
	my $i2caddress = $hash->{I2C_Address};		
		
	
	my $resolutionIndex = $hash->{RESOLUTION};
	my $delay = $I2C_GY30_BH1750FVI_resParams{$resolutionIndex}{delay};
	
	if ($hash->{OPERATION_MODE} eq 'One')
	{
		
	
		my $codeCont = $I2C_GY30_BH1750FVI_CodeMode{'One'};
		my $codeResolution = $I2C_GY30_BH1750FVI_resParams{$resolutionIndex}{code};
		my $code = $codeCont | $codeResolution;
		
		
		
		Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_UpdateValues send config with ".sprintf("0x%X", $code);
		
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
					direction  => "i2cwrite",
					i2caddress => $i2caddress,
					data => $code	
					});		
		$delay = $I2C_GY30_BH1750FVI_resParams{$resolutionIndex}{delayInit};
	}
	
	Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_UpdateValues wait for ".($delay/1000)." ms" ;
	
	Time::HiRes::usleep($delay);
	
	CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {	# Leider fehlt es hier an Doku. daher hier der Hinweis bei erfolgreichem Lesen wird die Funktion in $hash->{I2CRecFn} aufgerufen	
			direction  => 	"i2cread",
			i2caddress => 	$i2caddress,
			type => 		"light",
			nbyte => 		2
			});
	
	
  	return "$name: no IO device defined" unless ($hash->{IODev});
	  


}

sub I2C_GY30_BH1750FVI_Get($@) {
	my ($hash, @param) = @_;
	
	

	
	I2C_GY30_BH1750FVI_UpdateValues($hash);
	

}

# set wenn Befehl gesetzt wurde und nicht '?' ist, 
#	dann führe Befehl aus und gib den Status zurück
# 	ansonsten gib alle Befehle und deren Optionen zurück

sub I2C_GY30_BH1750FVI_Set($@) 
{
	my ($hash, @param) = @_;
	

	
	return '"set GY30_BH1750FVI" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $cmd = shift @param;
	my $val = join("", @param);
	
	if (defined $cmd && $cmd ne '?') # falls set mit Kommand aufgerufen wurde
	{
		if (defined($I2C_GY30_BH1750FVI_CodeCmd{$cmd}))
		{
			I2C_GY30_BH1750FVI_Command($hash,$cmd);
			return undef;	
		}
		elsif ($cmd eq 'Update')
		{
			I2C_GY30_BH1750FVI_UpdateValues($hash);
			return undef;
		}
		elsif ($cmd eq 'ReConfig')
		{
			I2C_GY30_BH1750FVI_InitDevice($hash);
			return undef;
		}
		
		return "unknown command";	
	
		# Debug("Set GY30_BH1750FVI $cmd");
		
	}
	else	# Ansonsten Rückgabe was an set - Optionen möglich ist
	{
		return "Update:noArg PowerDown:noArg PowerOn:noArg Reset:noArg ReConfig:noArg";
	}
	
	
}

sub I2C_GY30_BH1750FVI_CheckState
{
	my ($hash) = @_;
	if ($hash->{MODUL_STATE} ne 'Initialized')
	{
	
		my @def = split (' ',$hash->{DEF});
		I2C_GY30_BH1750FVI_Init($hash,\@def) if (defined ($hash->{IODev}));
	}
}

sub I2C_GY30_BH1750FVI_Poll
{
	my ($hash) = @_;
	I2C_GY30_BH1750FVI_CheckState($hash);
	my $name = $hash->{NAME};
	
	 
	
	I2C_GY30_BH1750FVI_UpdateValues($hash);
	
	my $ret = I2C_GY30_BH1750FVI_Catch($@) if $@;
	
	# Debug("Update Werte");
	my $pollInterval = AttrVal($hash->{NAME}, 'interval', 0);
	if ($pollInterval > 0) 
	{
		Log3 $hash, 5, "[$name] I2C_GY30_BH1750FVI_Poll call InternalTimer with $pollInterval minutes";
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_GY30_BH1750FVI_Poll', $hash, 0);
	}
	else
	{
		Log3 $name, 5, "[$name] I2C_GY30_BH1750FVI_Poll dont call InternalTimer, not valid pollInterval";
	}
	return;
}

sub I2C_GY30_BH1750FVI_Attr(@) {
	
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
				InternalTimer(1, 'I2C_GY30_BH1750FVI_Poll', $hash, 0);
				$hash->{INTERVAL} = $val;
				Log3 $hash, 5, "[$hash->{NAME}] I2C_GY30_BH1750FVI_Poll dont call InternalTimer, not valid pollInterval";
			} else 
			{
				$msg .= "$hash->{NAME}: Wrong poll intervall defined. interval must be a number > 0";
				Log3 $hash, 5, "[$hash->{NAME}] I2C_GY30_BH1750FVI_Attr Wrong poll intervall defined. interval must be a number > 0";
				$hash->{INTERVAL} = 0;
			}
		} 
		else 
		{ #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
			RemoveInternalTimer($hash);
			$hash->{INTERVAL} = 0;
		}
	}
	
	elsif ($attr eq 'Resolution') 
	{
		if (!defined($val))
		{
			$hash->{RESOLUTION} = 'HalfLux';
			I2C_GY30_BH1750FVI_InitDevice($hash);
		}
		elsif ( defined($I2C_GY30_BH1750FVI_resParams{$val}{code}) ) 
		{	
			$hash->{RESOLUTION} = $val;
			I2C_GY30_BH1750FVI_InitDevice($hash);
		}
		else	
		{
			$msg .= "invalid value for attribute $attr";
		}
	}
	
	elsif ($attr eq 'OperationMode') 
	{
		if (!defined($val))
		{
			$hash->{OPERATION_MODE} = 'One';
			I2C_GY30_BH1750FVI_InitDevice($hash);
		}
		elsif ( defined($I2C_GY30_BH1750FVI_CodeMode{$val}) ) 
		{	
			$hash->{OPERATION_MODE} = $val;
			I2C_GY30_BH1750FVI_InitDevice($hash);
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
			I2C_GY30_BH1750FVI_Init($hash,\@def) if (defined ($hash->{IODev}));
			
		}
	}
	
	elsif ( $attr eq 'roundLightIntensityDecimal' ) 
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
=begin html

<a name="I2C_GY30_BH1750FVI"></a>
<h3>I2C_GY30_BH1750FVI</h3>
<ul>
	<a name="I2C_GY30_BH1750FVI"></a>
		Provides an interface to the I2C GY-30 with chip BH1750FVI light intensity sensor from <a href=" http://www.ti.com">Texas Instruments</a>.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_GY30_BH1750FVIDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_GY30_BH1750FVI [&lt;I2C Address&gt;]</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
	</ul>
	<a name="I2C_GY30_BH1750FVISet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; Update</code><br>
		Reads the current light intensity values from sensor.<br><br>
		<code>set &lt;name&gt; Reset</code><br>
		Resets the sensor (only when sensor is power on).<br><br>
		<code>set &lt;name&gt; ReConfig</code><br>
		Sends in Continuously mode the configuration parameter again to the sensor.<br><br>
		<code>set &lt;name&gt; PowerDown</code><br>
		turn the sensor in standby (no active state).<br><br>
		<code>set &lt;name&gt; PowerOn</code><br>
		turn on the sensor
	</ul>
	<a name="I2C_GY30_BH1750FVIAttr"></a>
	<b>Attributes</b>
	<ul>
		<li>interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>Resolution<br>
			resolution for measurement<br>
			Standard: HalfLux, valid values: HalfLux, 1Lux, 4Lux<br><br>
		</li>
		<li>OperationMode<br>
			operation mode. One: One-time measurement , then the sensor turns off. Continuously: re- measure possible without re-configuration then sensor<br>
			standard: One, valid values: Continuously,One<br><br>
		</li>		
		<li>roundLightIntensityDecimal<br>
			Number of decimal places for light intensity value<br>
			Default: 1, valid values: 0 1 2,...<br><br>
		</li>
		
		<li><a href="#IODev">IODev</a></li>

	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_GY30_BH1750FVI"></a>
<h3>I2C_GY30_BH1750FVI</h3>
<ul>
	<a name="I2C_GY30_BH1750FVI"></a>
		Erm&ouml;glicht die Verwendung eines I2C GY-30 mit Chip BH1750FVI Lichtst&auml;rke-Sensors von <a href=" http://www.ti.com">Texas Instruments</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_GY30_BH1750FVIDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_GY30_BH1750FVI [&lt;I2C Address&gt;]</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
	</ul>
	<a name="I2C_GY30_BH1750FVISet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; Update</code><br>
		Aktuelle Lichtst&auml;rke vom Sensor lesen.<br><br>
		<code>set &lt;name&gt; Reset ( nur bei eingeschalteten Sensor )</code><br>
		Setzt den Sensor zur&uuml;ck<br><br>
		<code>set &lt;name&gt; ReConfig</code><br>
		Sendet im Continuously-Mode die Konfigurationsparameter erneut zum Sensor<br><br>
		<code>set &lt;name&gt; PowerDown</code><br>
		Schaltet den Sensors in einen Ruhezustand<br><br>
		<code>set &lt;name&gt; PowerOn</code><br>
		Schaltet den Sensors an
	</ul>
	<a name="I2C_GY30_BH1750FVIAttr"></a>
	<b>Attribute</b>
	<ul>
		<li>interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li>Resolution<br>
			Genauigkeit mit der gemessen werden soll.<br>
			Standard: HalfLux, g&uuml;ltige Werte: HalfLux, 1Lux, 4Lux<br><br>
		</li>
		<li>OperationMode<br>
			Betriebsmodus. One: Einmaliges Messen, dann schaltet der Sensor sich wieder aus. Continuously: erneutes Messen ohne Neukonfiguration des Sensors m&ouml;glich<br>
			Standard: One, g&uuml;ltige Werte: Continuously,One<br><br>
		</li>
		<li>roundLightIntensityDecimal<br>
			Anzahl Dezimalstellen f&uuml;r die Lichtst&auml;rke<br>
			Standard: 1, g&uuml;ltige Werte: 0,1,2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>

	</ul><br>
</ul>

=end html

=cut