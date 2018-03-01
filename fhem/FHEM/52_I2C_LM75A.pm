##############################################
# $Id$
#
# adapted from 52_I2C_SHT3x.pm by stefan@clumsy.ch
#

package main;

use strict;
use warnings;

use constant {
	LM75A_I2C_ADDRESS => '0x48',
};

##################################################
# Forward declarations
#
sub I2C_LM75A_Initialize($);
sub I2C_LM75A_Define($$);
sub I2C_LM75A_Attr(@);
sub I2C_LM75A_Poll($);
sub I2C_LM75A_Set($@);
sub I2C_LM75A_Undef($$);
sub I2C_LM75A_DbLog_splitFn($);

my %sets = (
	'readValues' => 1,
);

sub I2C_LM75A_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_LM75A_Define';
	$hash->{InitFn}   = 'I2C_LM75A_Init';
	$hash->{AttrFn}   = 'I2C_LM75A_Attr';
	$hash->{SetFn}    = 'I2C_LM75A_Set';
	$hash->{UndefFn}  = 'I2C_LM75A_Undef';
  $hash->{I2CRecFn} = 'I2C_LM75A_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
						'roundTemperatureDecimal:0,1,2 ' .
						$readingFnAttributes;
  $hash->{DbLog_splitFn} = "I2C_LM75A_DbLog_splitFn";
}

sub I2C_LM75A_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	$hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_LM75A_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_LM75A_Catch($@) if $@;
  }
  return undef;
}

sub I2C_LM75A_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};

	 if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_LM75A [<i2caddress>]";
 	}
	 
 	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0x.*$/ ? hex($address) : $address;
#		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
		return "$name I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
 	} else {
		$hash->{I2C_Address} = hex(LM75A_I2C_ADDRESS);
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

sub I2C_LM75A_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_LM75A_Attr (@) {# hier noch Werteueberpruefung einfuegen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				I2C_LM75A_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
		};
		return I2C_LM75A_Catch($@) if $@;
	}
	if ($attr eq 'poll_interval') {
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 5, 'I2C_LM75A_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'roundTemperatureDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val <= 0 && $val >= 2 ;
	} 
	return ($msg) ? $msg : undef;
}

sub I2C_LM75A_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_LM75A_Set($hash, ($name, 'readValues'));
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_LM75A_Poll', $hash, 0);
	}
}

sub I2C_LM75A_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {
		I2C_LM75A_triggerTemperature($hash);
#		I2C_LM75A_readValue($hash);
	}
}

sub I2C_LM75A_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_LM75A_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
    
    if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
    	if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
	    	Log3 $hash, 5, "empfangen: $clientmsg->{received}";    
        	my @raw = split(" ",$clientmsg->{received});
        	I2C_LM75A_GetTemp ($hash, $clientmsg->{received});
        }
    }
}

sub I2C_LM75A_GetTemp ($$) {
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);

	my $temperature = 0;
#	if(($raw[0] & 0x80) > 0) {
#		$temperature = 0xffffff00;
#	}
#	$temperature |= ($raw[0] & 0x7f) << 1;
#	$temperature |= (($raw[1] >> 7) & 1);

  	my $temperature_11_bit = ($raw[0] << 8 | $raw[1]) >> 5; # Compute 11-bit temperature output value  
	$temperature = ($temperature_11_bit) * 0.125; # Compute temperature in °C  
	if(($raw[0] & 0x80) > 0) { # check for negative value
#		$temperature *= -1;
		$temperature -= 256.000;
	}

#	$temperature = $temperature / 2;
    	Log3 $hash, 5, "temperature: $temperature";    
	$temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			$temperature
		);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"temperature", $temperature);
	readingsBulkUpdate($hash,"state", "T: $temperature");
	readingsEndUpdate($hash,1);
}

sub I2C_LM75A_triggerTemperature($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	  
	# Write 0xF3 to device. This requests a "no hold master" temperature reading
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
	$i2creq->{data} = hex("00");
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + 1, 'I2C_LM75A_readValue', $hash, 0); #nach 1s Wert lesen (85ms sind fuer 14bit Wert notwendig)
	return;
}

sub I2C_LM75A_readValue($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	
	# Reset Internal Timer to Poll Sub
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_LM75A_Poll', $hash, 0) if ($pollInterval > 0);
	# Read the two byte result from device + 1byte CRC
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
#	$i2cread->{reg} = hex("00");
	$i2cread->{nbyte} = 2;
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
	return;
}

sub I2C_LM75A_CheckCrc(@) {
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

sub I2C_LM75A_DbLog_splitFn($) {
    my ($event) = @_;
    Log3 undef, 5, "in DbLog_splitFn empfangen: $event"; 
    my ($reading, $value, $unit) = "";
    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $unit = "\xB0C" if(lc($reading) =~ m/temp/);
    return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary reads temperature from an via I2C connected LM75A
=item summary_DE lese Temperatur eines &uuml;ber I2C angeschlossenen LM75A
=begin html

<a name="I2C_LM75A"></a>
<h3>I2C_LM75A</h3>
(en | <a href="commandref_DE.html#I2C_LM75A">de</a>)
<ul>
	<a name="I2C_LM75A"></a>
		Provides an interface to the LM75A I2C Temperature sensor.</a>.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_LM75ADefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_LM75A [&lt;I2C Address&gt;]</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
	</ul>
	<a name="I2C_LM75ASet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Reads the current temperature values from sensor.<br><br>
	</ul>
	<a name="I2C_LM75AAttr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
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

<a name="I2C_LM75A"></a>
<h3>I2C_LM75A</h3>
(<a href="commandref.html#I2C_LM75A">en</a> | de)
<ul>
	<a name="I2C_LM75A"></a>
		Erm&ouml;glicht die Verwendung eines LM75A I2C Temperatursensors.</a>.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_LM75ADefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_LM75A [&lt;I2C Address&gt;]</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
	</ul>
	<a name="I2C_LM75ASet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur Werte vom Sensor lesen.<br><br>
	</ul>
	<a name="I2C_LM75AAttr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
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
