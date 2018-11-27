##############################################
# $Id$

package main;

use strict;
use warnings;

use constant {
	SHT21_I2C_ADDRESS => '0x40',
};

##################################################
# Forward declarations
#
sub I2C_SHT21_Initialize($);
sub I2C_SHT21_Define($$);
sub I2C_SHT21_Attr(@);
sub I2C_SHT21_Poll($);
sub I2C_SHT21_Set($@);
sub I2C_SHT21_Undef($$);
sub I2C_SHT21_DbLog_splitFn($);

my %sets = (
	'readValues' => 1,
);

sub I2C_SHT21_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_SHT21_Define';
	$hash->{InitFn}   = 'I2C_SHT21_Init';
	$hash->{AttrFn}   = 'I2C_SHT21_Attr';
	$hash->{SetFn}    = 'I2C_SHT21_Set';
	$hash->{UndefFn}  = 'I2C_SHT21_Undef';
  $hash->{I2CRecFn} = 'I2C_SHT21_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
						'roundHumidityDecimal:0,1,2 roundTemperatureDecimal:0,1,2 ' .
						$readingFnAttributes;
  $hash->{DbLog_splitFn} = "I2C_SHT21_DbLog_splitFn";
}

sub I2C_SHT21_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	  $hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_SHT21_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_SHT21_Catch($@) if $@;
  }
  return undef;
}

sub I2C_SHT21_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};

	 if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_SHT21 [<i2caddress>]";
 	}
	 
 	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
		return "$name I2C Address not valid" unless ($address < 128 && $address > 3);
 	} else {
		$hash->{I2C_Address} = hex(SHT21_I2C_ADDRESS);
	}


	my $msg = '';
	# create default attributes
	if (AttrVal($name, 'poll_interval', '?') eq '?') {  
    	$msg = CommandAttr(undef, $name . ' poll_interval 5');
    	if ($msg) {
      		Log3 ($hash, 1, $msg);
      		return $msg;
    	}
  }
	AssignIoPort($hash);	
	$hash->{STATE} = 'Initialized';

#	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
#	$sendpackage{reg} = hex("AA");
#	$sendpackage{nbyte} = 22;
#	return "$name: no IO device defined" unless ($hash->{IODev});
#	my $phash = $hash->{IODev};
#	my $pname = $phash->{NAME};
#	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);

	return undef;
}

sub I2C_SHT21_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_SHT21_Attr (@) {# hier noch Werteueberpruefung einfuegen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				I2C_SHT21_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
		};
		return I2C_SHT21_Catch($@) if $@;
	}
	if ($attr eq 'poll_interval') {
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 5, 'I2C_SHT21_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'roundHumidityDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val <= 0 && $val >= 2 ;
	} elsif ($attr eq 'roundTemperatureDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val <= 0 && $val >= 2 ;
	} 
	return ($msg) ? $msg : undef;
}

sub I2C_SHT21_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_SHT21_Set($hash, ($name, 'readValues'));
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_SHT21_Poll', $hash, 0);
	}
}

sub I2C_SHT21_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {
		I2C_SHT21_triggerTemperature($hash);
	}
}

sub I2C_SHT21_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_SHT21_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
    
    # Bit 1 of the two LSBs indicates the measurement type (‘0’: temperature, ‘1’ humidity)
    if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
    	if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
	    	Log3 $hash, 5, "empfangen: $clientmsg->{received}";    
        	my @raw = split(" ",$clientmsg->{received});
        	I2C_SHT21_GetTemp ($hash, $clientmsg->{received}) if !($raw[1] & 2) && $clientmsg->{nbyte} == 3;
        	I2C_SHT21_GetHum  ($hash, $clientmsg->{received}) if  ($raw[1] & 2) && $clientmsg->{nbyte} == 3;
        }
    }
}

sub I2C_SHT21_GetTemp ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	I2C_SHT21_triggerHumidity($hash);							#schnell noch Feuchtemessung anstoßen.
	if ( defined (my $crc = I2C_SHT21_CheckCrc(@raw)) ) {		#CRC Test
		Log3 $hash, 2, "CRC error temperature data(MSB LSB Chechsum): $rawdata, Checksum calculated: $crc";
		$hash->{CRCErrorTemperature}++;
		return;
	}	
	my $temperature = $raw[0] << 8 | $raw[1];
	$temperature = ( 175.72 * $temperature / 2**16 ) - 46.85;
	$temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			$temperature
		);
	readingsSingleUpdate($hash,"temperature", $temperature, 1);
}

sub I2C_SHT21_GetHum ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	if ( defined (my $crc = I2C_SHT21_CheckCrc(@raw)) ) {		#CRC Test
		Log3 $hash, 2, "CRC error humidity data(MSB LSB Chechsum): $rawdata, Checksum calculated: $crc";
		$hash->{CRCErrorHumidity}++;
		return;
	}				
	my $name = $hash->{NAME};
	my $temperature = ReadingsVal($name,"temperature","0");
	
	my $humidity = $raw[0] << 8 | $raw[1];	
	$humidity = ( 125 * $humidity / 2**16 ) - 6;
	$humidity = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundHumidityDecimal', 1) . 'f',
			$humidity
		);
	readingsBeginUpdate($hash);
	readingsBulkUpdate(
		$hash,
		'state',
		'T: ' . $temperature . ' H: ' . $humidity
	);
	readingsBulkUpdate($hash, 'humidity', $humidity);
	readingsEndUpdate($hash, 1);	
}

sub I2C_SHT21_triggerTemperature($) {
	my ($hash) = @_;
  my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};
	  
	# Write 0xF3 to device. This requests a "no hold master" temperature reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{data} = hex("F3");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + 1, 'I2C_SHT21_readValue', $hash, 0); #nach 1s Wert lesen (85ms sind fuer 14bit Wert notwendig)
	return;
}

sub I2C_SHT21_triggerHumidity($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};

	# Write 0xF5 to device. This requests a "no hold master" humidity reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{data} = hex("F5");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + 1, 'I2C_SHT21_readValue', $hash, 0);		#nach 1s Wert lesen (39ms sind fuer 12bit Wert notwendig)
	return;
}

sub I2C_SHT21_readValue($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	
	# Reset Internal Timer to Poll Sub
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_SHT21_Poll', $hash, 0) if ($pollInterval > 0);
	# Read the two byte result from device + 1byte CRC
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
	$i2cread->{nbyte} = 3;
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
	
	return;
}

sub I2C_SHT21_CheckCrc(@) {
	my @data = @_;
	my $crc = 0;
	my $poly = 0x131;	#P(x)=x^8+x^5+x^4+1 = 100110001
	for (my $n = 0; $n < (scalar(@data) - 1); ++$n) {
		$crc ^= $data[$n];
		for (my $bit = 8; $bit > 0; --$bit) {
			$crc = ($crc & 0x80 ? $poly : 0 ) ^ ($crc << 1);
		}
	}
	return ($crc = $data[2] ? undef : $crc);
}

sub I2C_SHT21_DbLog_splitFn($) {
    my ($event) = @_;
    Log3 undef, 5, "in DbLog_splitFn empfangen: $event"; 
    my ($reading, $value, $unit) = "";
    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $unit = "\xB0C" if(lc($reading) =~ m/temp/);
    $unit = "%" 	if(lc($reading) =~ m/humi/);
    return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary reads humidity and temperature from an via I2C connected SHT2x
=item summary_DE lese Feuchte und Temperatur eines &uuml;ber I2C angeschlossenen SHT2x
=begin html

<a name="I2C_SHT21"></a>
<h3>I2C_SHT21</h3>
(en | <a href="commandref_DE.html#I2C_SHT21">de</a>)
<ul>
	<a name="I2C_SHT21"></a>
		Provides an interface to the SHT21 I2C Humidity sensor from <a href="www.sensirion.com">Sensirion</a>.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_SHT21Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_SHT21 [&lt;I2C Address&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
		For example 0x40 (hexadecimal) = 64 (decimal). An I2C address are 7 MSB, the LSB is the R/W bit.<br>
	</ul>
	<a name="I2C_SHT21Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Reads the current temperature and humidity values from sensor.<br><br>
	</ul>
	<a name="I2C_SHT21Attr"></a>
	<b>Attributes</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li><a name="roundHumidityDecimal">roundHumidityDecimal</a><br>
			Number of decimal places for humidity value<br>
			Default: 1, valid values: 0 1 2<br><br>
		</li>
		<li><a name="roundTemperatureDecimal">roundTemperatureDecimal</a><br>
			Number of decimal places for temperature value<br>
			Default: 1, valid values: 0 1 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_SHT21"></a>
<h3>I2C_SHT21</h3>
(<a href="commandref.html#I2C_SHT21">en</a> | de)
<ul>
	<a name="I2C_SHT21"></a>
		Erm&ouml;glicht die Verwendung eines SHT21 I2C Feuchtesensors von <a href="www.sensirion.com">Sensirion</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_SHT21Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_SHT21 [&lt;I2C Address&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Beispielsweise 0x40 (hexadezimal) = 64 (dezimal). Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
	</ul>
	<a name="I2C_SHT21Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur und Feuchte Werte vom Sensor lesen.<br><br>
	</ul>
	<a name="I2C_SHT21Attr"></a>
	<b>Attribute</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li><a name="roundHumidityDecimal">roundHumidityDecimal</a><br>
			Anzahl Dezimalstellen f&uuml;r den Feuchtewert<br>
			Standard: 1, g&uuml;ltige Werte: 0 1 2<br><br>
		</li>
		<li><a name="roundTemperatureDecimal">roundTemperatureDecimal</a><br>
			Anzahl Dezimalstellen f&uuml;r den Temperaturwert<br>
			Standard: 1, g&uuml;ltige Werte: 0 1 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html_DE

=cut