##############################################
# $Id$
#
# 52_I2C_SHT3x.pm
#
# i2c sensor for humidity and temperature
#
# Basis for this module is "52_I2C_SHT21.pm" from klausw. I adapted the module so that it
# is suitable for the SHT3x family from Sensirion / Switzerland. At moment the SHT3x family
# consists of 3 sensors:
#   SHT30 (Low-Cost): sensor with less accuracy
#   SHT31 (Standard): sensor with good accuracy
#   SHT35 (High-End): sensor with best accuracy
#
# Via hardware pin configuration the sensor can be configured for 2 different i2c addresses.
#
#
# If you have any questions, suggestions or like to report a failure, please feel free to cantact me:
# FHEM Forum username: macs
#
##############################################

package main;

use strict;
use warnings;

use constant {
	# 0x44 (default): ADDR (pin 2) connected to VSS (supply voltage)
	# 0x45          : ADDR (pin 2) connected to VDD (ground)
	SHT3x_I2C_ADDRESS => '0x44',
};

##################################################
# Forward declarations
#
sub I2C_SHT3x_Initialize($);
sub I2C_SHT3x_Define($$);
sub I2C_SHT3x_Attr(@);
sub I2C_SHT3x_Poll($);
sub I2C_SHT3x_Set($@);
sub I2C_SHT3x_Undef($$);
sub I2C_SHT3x_DbLog_splitFn($);

my %sets = (
	'readValues' => 1,
);

sub I2C_SHT3x_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_SHT3x_Define';
	$hash->{InitFn}   = 'I2C_SHT3x_Init';
	$hash->{AttrFn}   = 'I2C_SHT3x_Attr';
	$hash->{SetFn}    = 'I2C_SHT3x_Set';
	$hash->{UndefFn}  = 'I2C_SHT3x_Undef';
	$hash->{I2CRecFn} = 'I2C_SHT3x_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
						'roundHumidityDecimal:0,1,2 roundTemperatureDecimal:0,1,2 ' .
						$readingFnAttributes;
	$hash->{DbLog_splitFn} = "I2C_SHT3x_DbLog_splitFn";
}

sub I2C_SHT3x_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	  $hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_SHT3x_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_SHT3x_Catch($@) if $@;
  }
  return undef;
}

sub I2C_SHT3x_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};

	 if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_SHT3x [<i2caddress>]";
 	}
	 
 	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
		return "$name I2C Address not valid" unless (($hash->{I2C_Address} < 128) && ($hash->{I2C_Address} > 3));
 	} else {
		$hash->{I2C_Address} = hex(SHT3x_I2C_ADDRESS);
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

	return undef;
}

sub I2C_SHT3x_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_SHT3x_Attr (@) {# hier noch Werteueberpruefung einfuegen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				I2C_SHT3x_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
		};
		return I2C_SHT3x_Catch($@) if $@;
	}
	if ($attr eq 'poll_interval') {
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 5, 'I2C_SHT3x_Poll', $hash, 0);
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

sub I2C_SHT3x_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_SHT3x_Set($hash, ($name, 'readValues'));
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_SHT3x_Poll', $hash, 0);
	}
}

sub I2C_SHT3x_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {
		I2C_SHT3x_triggerTempHum($hash);
	}
}

sub I2C_SHT3x_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_SHT3x_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { #erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
    
    # i2c data received?
    if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
    	if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
	    	Log3 $hash, 5, "empfangen: $clientmsg->{received}";    
        	my @raw = split(" ",$clientmsg->{received});
        	I2C_SHT3x_GetTempHum ($hash, $clientmsg->{received}) if $clientmsg->{nbyte} == 6;
        }
    }
}

sub I2C_SHT3x_GetTempHum ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);

	if ( defined (my $crc = I2C_SHT3x_CheckCrc(@raw[0..2])) ) { #CRC Test
		Log3 $hash, 2, "CRC error temperature data(Temp_MSB Temp_LSB Temp_Chechsum  Hum_MSB Hum_LSB Hum_Chechsum): $rawdata, Checksum calculated: $crc";
		$hash->{CRCErrorTemperature}++;

		return;
	}

	if ( defined (my $crc = I2C_SHT3x_CheckCrc(@raw[3..5])) ) { #CRC Test
		Log3 $hash, 2, "CRC error humidity data(Temp_MSB Temp_LSB Temp_Chechsum  Hum_MSB Hum_LSB Hum_Chechsum): $rawdata, Checksum calculated: $crc";
		$hash->{CRCErrorHumidity}++;

		return;
	}


	my $name = $hash->{NAME};

	my $temperature = ($raw[0] << 8) | $raw[1];
	$temperature = ( 175.0 * ($temperature / ((2**16)-1.0) )) - 45.0;
	$temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			$temperature
		);

	my $humidity = ($raw[3] << 8) | $raw[4];
	$humidity = 100.0 * ($humidity / ((2**16)-1.0) );
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
	readingsBulkUpdate($hash, 'temperature', $temperature);
	readingsBulkUpdate($hash, 'humidity', $humidity);
	readingsEndUpdate($hash, 1);	
}

sub I2C_SHT3x_triggerTempHum($) {
	my ($hash) = @_;
  	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};
	  
	# Write decimal 36 00 to device. This requests a "Repeatability = High, Clock stretching = disabled" temperature and humidity reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{data} = "36 00";
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + 1, 'I2C_SHT3x_readValue', $hash, 0); #nach 1s Wert lesen
	return;
}

sub I2C_SHT3x_readValue($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	
	# Reset Internal Timer to Poll Sub
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_SHT3x_Poll', $hash, 0) if ($pollInterval > 0);
	# Read 6 byte: Temp MSB, Temp LSB, CRC, Hum MSB, Hum LSB, CRC
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
	$i2cread->{nbyte} = 6;
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
	
	return;
}

sub I2C_SHT3x_CheckCrc(@) {
	my @data = @_;
	my $crc = 0xFF;
	my $poly = 0x131;	#P(x)=x^8+x^5+x^4+1 = 100110001
	for (my $n = 0; $n < (scalar(@data) - 1); ++$n) {
		$crc ^= $data[$n];
		for (my $bit = 8; $bit > 0; --$bit) {
			$crc = ($crc & 0x80 ? $poly : 0 ) ^ ($crc << 1);
		}
	}

	return ($crc == $data[scalar(@data)-1] ? undef : $crc);
}

sub I2C_SHT3x_DbLog_splitFn($) {
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
=begin html

<a name="I2C_SHT3x"></a>
<h3>I2C_SHT3x</h3>
(en | <a href="commandref_DE.html#I2C_SHT3x">de</a>)
<ul>
	<a name="I2C_SHT3x"></a>
		Provides an interface to the SHT30/SHT31 I2C Humidity sensor from <a href="http:\\www.sensirion.com">Sensirion</a>.
		The I2C messages are sent through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_SHT3xDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_SHT3x [&lt;I2C Address&gt;]</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value:<br>
		ADDR (pin 2) connected to VSS (supply voltage): 0x44 (default, if <code>&lt;I2C Address&gt;</code> is not set)<br>
		ADDR (pin 2) connected to VDD (ground): 0x45<br>
		For compatible sensors also other values than 0x44 or 0x45 can be set.<br>
		<br>
	</ul>
	<a name="I2C_SHT3xSet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Reads the current temperature and humidity values from sensor.<br><br>
	</ul>
	<a name="I2C_SHT3xAttr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundHumidityDecimal, roundTemperatureDecimal<br>
			Number of decimal places for humidity or temperature value<br>
			Default: 1, valid values: 0 1 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_SHT3x"></a>
<h3>I2C_SHT3x</h3>
(<a href="commandref.html#I2C_SHT3x">en</a> | de)
<ul>
	<a name="I2C_SHT3x"></a>
		Erm&ouml;glicht die Verwendung eines SHT30/SHT31 I2C Feuchtesensors von <a href="http:\\www.sensirion.com">Sensirion</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_SHT3xDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_SHT3x [&lt;I2C Address&gt;]</code><br>
		<br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert:<br>
		ADDR (Pin 2) verbunden mit VSS (Versorgungsspannung): 0x44 (Standardwert, wenn <code>&lt;I2C Address&gt;</code> nicht angegeben)<br>
		ADDR (pin 2) verbunden mit VDD (Masse): 0x45<br>
		F&uuml;r kompatible Sensoren k&ouml;nnen auch andere Werte als 0x44 oder 0x45 angegeben werden.<br>
		<br>
	</ul>
	<a name="I2C_SHT3xSet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur und Feuchte Werte vom Sensor lesen.<br><br>
	</ul>
	<a name="I2C_SHT3xAttr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundHumidityDecimal, roundTemperatureDecimal<br>
			Anzahl Dezimalstellen f&uuml;r den Feuchte- oder Temperaturwert<br>
			Standard: 1, g&uuml;ltige Werte: 0 1 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html_DE

=cut