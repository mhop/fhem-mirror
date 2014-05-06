##############################################
# $Id$

package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
#use Error qw(:try);

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
	$msg = CommandAttr(undef, $name . ' poll_interval 5');
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
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
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	if ($attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_SHT21_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'roundHumidityDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val >= 0 && $val <= 2 ;
	} elsif ($attr eq 'roundTemperatureDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val >= 0 && $val <= 2 ;
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
		I2C_SHT21_readTemperature($hash);
		I2C_SHT21_readHumidity($hash);
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
	if ($clientmsg->{direction} && $clientmsg->{type} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			Log3 $hash, 5, "empfangen: $clientmsg->{received}";
			I2C_SHT21_GetTemp  ($hash, $clientmsg->{received}) if $clientmsg->{type} eq "temp" && $clientmsg->{nbyte} == 2;
			I2C_SHT21_GetHum ($hash, $clientmsg->{received}) if $clientmsg->{type} eq "hum" && $clientmsg->{nbyte} == 2;
		}
	}
}

sub I2C_SHT21_GetTemp ($$) {
	my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
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
	#readingsBulkUpdate($hash, 'temperature', $temperature);
	readingsBulkUpdate($hash, 'humidity', $humidity);
	readingsEndUpdate($hash, 1);	
}


sub I2C_SHT21_readTemperature($) {
	my ($hash) = @_;
  my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};
	  
	# Write 0xF3 to device. This requests a temperature reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
  $i2creq->{data} = hex("F3");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(85000); #fuer 14bit

	# Read the two byte result from device
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
  $i2cread->{nbyte} = 2;
	$i2cread->{type} = "temp";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
		
	return;
}

sub I2C_SHT21_readHumidity($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};

	# Write 0xF5 to device. This requests a humidity reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
  $i2creq->{data} = hex("F5");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(39000); #fuer 12bit

	# Read the two byte result from device
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
  $i2cread->{nbyte} = 2;
	$i2cread->{type} = "hum";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
	
	return; # $retVal;
}


1;

=pod
=begin html

<a name="I2C_SHT21"></a>
<h3>I2C_SHT21</h3>
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
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
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
		<li>poll_interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundHumidityDecimal<br>
			Number of decimal places for humidity value<br>
			Default: 1, valid values: 0 1 2<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Number of decimal places for temperature value<br>
			Default: 1, valid values: 0,1,2<br><br>
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
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
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
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
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
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html_DE

=cut