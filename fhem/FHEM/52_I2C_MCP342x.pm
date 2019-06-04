##############################################
# $Id$

package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
#use Error qw(:try);

use constant {
	MCP3422_I2C_ADDRESS => '0x68',
};

##################################################
# Forward declarations
#
sub I2C_MCP342x_Initialize($);
sub I2C_MCP342x_Define($$);
sub I2C_MCP342x_Attr(@);
sub I2C_MCP342x_Poll($);
sub I2C_MCP342x_Set($@);
sub I2C_MCP342x_Undef($$);


my %resols = (
'12'  => {
			code  => 0b00000000,
			delay => 5690,
			lsb   => 1000,
			},
'14'  => {
			code  => 0b00000100,
			delay => 22730,
			lsb   => 250,
			},
'16'  => {
			code  => 0b00001000,
			delay => 90910,
			lsb   => 62.5,
			},
'18'  => {
			code  => 0b00001100,
			delay => 363640,
			lsb   => 15.625,
			},
);

my %gains = (
'1'  => 0b00000000,
'2'  => 0b00000001,
'4'  => 0b00000010,
'8'  => 0b00000011,
);

sub I2C_MCP342x_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_MCP342x_Define';
	$hash->{InitFn}   = 'I2C_MCP342x_Init';
	$hash->{AttrFn}   = 'I2C_MCP342x_Attr';
	$hash->{GetFn}    = 'I2C_MCP342x_Get';
	$hash->{UndefFn}  = 'I2C_MCP342x_Undef';
  $hash->{I2CRecFn} = 'I2C_MCP342x_I2CRec';

	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
				'ch1roundDecimal:0,1,2,3 ch1gain:1,2,4,8 ch1resolution:12,14,16,18 ch1factor '.
				'ch2roundDecimal:0,1,2,3 ch2gain:1,2,4,8 ch2resolution:12,14,16,18 ch2factor '.
				'ch3roundDecimal:0,1,2,3 ch3gain:1,2,4,8 ch3resolution:12,14,16,18 ch3factor '.
				'ch4roundDecimal:0,1,2,3 ch4gain:1,2,4,8 ch4resolution:12,14,16,18 ch4factor '.
				$readingFnAttributes;
}

sub I2C_MCP342x_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	
	  $hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_MCP342x_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_MCP342x_Catch($@) if $@;
  }
  return undef;
}

sub I2C_MCP342x_Init($$) {
	my ( $hash, $args ) = @_;
	
	my $name = $hash->{NAME};
	Log3 $hash, 5, "$hash->{NAME}: Init Argumente1: $args";
	 if (defined $args && int(@$args) < 1)
 	{
  	Log3 $hash, 0, "Define: Wrong syntax. Usage:\n" .
         	"define <name> MCP342x [<i2caddress>] [<type>]";
 	}
	 
 	if (defined (my $address = shift @$args)) {
   	$hash->{I2C_Address} = $address =~ /^0x.*$/ ? oct($address) : $address;
   	Log3 $hash, 0, "$name: I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
 	} else {
		$hash->{I2C_Address} = hex(MCP3422_I2C_ADDRESS);
	}
	
	if (defined (my $channels = shift @$args)) {
		$hash->{channels} = ($channels == 4 ? 4 : 2);
	} else {
		$hash->{channels} = 2;
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

sub I2C_MCP342x_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_MCP342x_Attr (@) {# hier noch Werteueberpruefung einfuegen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_MCP342x_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
	if ($attr && $attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		if (!defined($val) ) {
			RemoveInternalTimer($hash);
		} elsif ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_MCP342x_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		} 
 } elsif ($attr eq 'roundDecimal') {
		$msg = 'Wrong $attr defined. Use one of 0, 1, 2' if defined($val) && $val <= 0 && $val >= 3 ;
	} elsif ($attr eq 'gain') {
			foreach (split (/,/,$val)) {
			my @pair = split (/=/,$_);
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <channel>=1|2|4|8 where <channel> = 1-$hash->{channels}" 
				unless ( ( scalar(@pair) == 2 &&
								$pair[0] =~ m/^[1-4]$/i && $pair[0] <= $hash->{channels} &&
								$pair[1] =~ m/^(1|2|4|8)$/i ) ||
								$val =~ m/^(1|2|4|8)$/i);		
		}
	} elsif ($attr eq 'resolution') {
			foreach (split (/,/,$val)) {
			my @pair = split (/=/,$_);
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <channel>=12|14|16|18 where <channel> = 1-$hash->{channels}" 
				unless ( ( scalar(@pair) == 2 &&
								$pair[0] =~ m/^[1-4]$/i &&
								$pair[1] =~ m/^1(2|4|6|8)$/i ) &&
								$val =~ m/^1(2|4|6|8)$/i );		
		}
	}
	
	return ($msg) ? $msg : undef;
}

sub I2C_MCP342x_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_MCP342x_Get($hash, $name);
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_MCP342x_Poll', $hash, 0);
	}
}

sub I2C_MCP342x_Get($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];
    
	my $rex = "^[1-" . $hash->{channels} . "]\$";
	if (defined $cmd && $cmd =~ m/$rex/i) {
    	my $resol   = defined $a[2] ? $a[2] : AttrVal($hash->{NAME},("ch" . $cmd . "resolution"),"12");
		return "Wrong resolution, use 12, 14, 16 or 18" unless $resol =~ m/^1(2|4|6|8)$/i;
		my $gain    = defined $a[3] ? $a[3] : AttrVal($hash->{NAME},("ch" . $cmd . "gain"),"1");
		return "Wrong gain, use 1, 2, 4 or 8" unless $gain =~ m/^(1|2|4|8)$/i;
        my $ts = ReadingsTimestamp($hash->{NAME},("Channel".$cmd),0);
		I2C_MCP342x_readvoltage($hash,$cmd,$resol,$gain);
        foreach (1..400) {   #max 2s warten
            usleep 5000;
            return ReadingsVal($hash->{NAME},("Channel".$cmd),undef) if $ts ne ReadingsTimestamp($hash->{NAME},("Channel".$cmd),0);
        } 
    } else {
    	foreach (1..$hash->{channels}) {
			my $resol   = defined $a[3] ? $a[3] : AttrVal($hash->{NAME},("ch" . $_ . "resolution"),"12");
			return "Wrong resolution, use 12, 14, 16 or 18" unless $resol =~ m/^1(2|4|6|8)$/i;
			my $gain    = defined $a[4] ? $a[4] : AttrVal($hash->{NAME},("ch" . $_ . "gain"),"1");
			return "Wrong gain, use 1, 2, 4 or 8" unless $gain =~ m/^(1|2|4|8)$/i;
			I2C_MCP342x_readvoltage($hash,$_,$resol,$gain); 
        }
    	my @gets = ('1', '2');
      push(@gets,('3', '4')) if $hash->{channels} == 4; 
		  return 'Unknown argument' . (defined $cmd ? (" " . $cmd) : "" ) . ', choose one of ' . join(' ', @gets)
	}
}

sub I2C_MCP342x_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_MCP342x_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};  
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
    $hash->{$k} = $v if $k =~ /^$pname/ ;
  } 
	#my $ankommen = "$hash->{NAME}: vom physical empfangen";
	#	foreach my $av (keys %{$clientmsg}) { $ankommen .= "|" . $av . ": " . $clientmsg->{$av}; }
	#Log3 $hash, 1, $ankommen;
	if ($clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		readingsSingleUpdate($hash,"state", "Ok", 1);
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {###hier noch normal read rein,wenn alles wieder ok
			#Log3 $hash, 1, "empfangen: $clientmsg->{received}";
			I2C_MCP342x_GetVoltage  ($hash, $clientmsg->{received}); # if $clientmsg->{type} eq "temp" && $clientmsg->{nbyte} == 2;
		}
	} else {
		readingsSingleUpdate($hash,"state", "transmission error", 1);
		Log3 $hash, 3, "$name: failurei in message from $pname";
		Log3 $hash, 3,(defined($clientmsg->{direction}) ? 	"Direction: "		.										$clientmsg->{direction} 	: "Direction: undef").
									(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) : " I2Caddress: undef").
									(defined($clientmsg->{reg}) ? 				" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 				: " Register: undef").
									(defined($clientmsg->{data}) ? 				" Data: " 			. sprintf("0x%.2X", $clientmsg->{data}) 			: " Data: undef").
									(defined($clientmsg->{received}) ? 		" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
	}
}

sub I2C_MCP342x_GetVoltage ($$) {
	my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
	if ( defined($raw[4]) ) {
		if ( ($raw[4] & 0b10000000) == 0 ) {
			my $channel  =  1 + (($raw[4] & 0b01100000) >> 5 );
			my $resol    =  2 * (($raw[4] & 0b00001100) >> 2 ) + 12;
			my $gain     =  2 ** ($raw[4] & 0b00000011);
			my $rawvolt;
			if ($resol == 18) {
				$rawvolt  = ($raw[0] & 0b00000011) << 16 | $raw[1] << 8 | $raw[2];
			} elsif ($resol == 14) {
				$rawvolt = ($raw[0] & 0b00111111) << 8 | $raw[1];
			} elsif ($resol == 12) {
				$rawvolt = ($raw[0] & 0b00001111) << 8 | $raw[1];
			} else {
				$rawvolt = $raw[0] << 8 | $raw[1];
			}
			Log3 $hash, 4, "Kanal: $channel, rawvolt: $rawvolt, Aufloesung: $resol, Gain: $gain, LSB: $resols{$resol}{lsb}";
			$rawvolt -= (1 << $resol) if $rawvolt >= (1 << ($resol - 1));
			Log3 $hash, 4, "Kanal: $channel, Signedrawvolt: $rawvolt";
			
			my $voltage = ( $rawvolt * $resols{$resol}{lsb} ) / $gain ;
			$voltage /= 1000000;														# LSB Werte in µV
			$voltage *= AttrVal($hash->{NAME},("ch" . $channel . "factor"),"1");
			$voltage = sprintf(
				'%.' . AttrVal($hash->{NAME}, ('ch' . $channel . 'roundDecimal'), 3) . 'f',
				$voltage
			);
			$voltage .= " overflow" if ( $rawvolt == ( (1<<($resol-1)) - 1) || $rawvolt == (1<<($resol-1)) );
			readingsSingleUpdate($hash,"Channel$channel", $voltage, 1);
		} else {
			Log3  $hash, 3, $hash->{NAME} . " error, output conversion not finished";
		}
	}
}

sub I2C_MCP342x_readvoltage($@) {
	my ($hash, $channel, $resol, $gain) = @_;
	my $name = $hash->{NAME};
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
																		#0b10010000
	my $confreg = 1 << 7;							#  1|| ||||	Initiate a new conversion		
	$confreg |= ($channel - 1) << 5;	#  	11 ||||	Channel Selection Bits
	$confreg |= $resols{$resol}{code};			#      11||	Sample Rate Selection Bit
	$confreg |= $gains{$gain};				#        11	PGA Gain Selection Bits
	#Log3  $hash, 1, "confinhalt: " . sprintf ('0b%08b', $confreg);
	
	# Write CONFIGURATION REGISTER to device. This requests a conversion process
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
  $i2creq->{data} = $confreg;
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep($resols{$resol}{delay}); #Verzoegerung

	# Read the result from device
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
  $i2cread->{nbyte} = 5;
	#$i2cread->{type} = "temp";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);
		
	return;
}


1;

=pod
=item device
=item summary reads the analog inputs from an via I2C connected MCP342x
=item summary_DE lesen der Analogeing&aumlnge eines &uuml;ber I2C angeschlossenen MCP342x
=begin html

<a name="I2C_MCP342x"></a>
<h3>I2C_MCP342x</h3>
<ul>
	<a name="I2C_MCP342x"></a>
		Provides an interface to the MCP3422/3/4 A/D converter.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_MCP342xDefine"></a><br>
	<b>Define</b>
	<ul>
    	<code>define &lt;name&gt; I2C_MCP342x [[&lt;I2C Address&gt;] &lt;n channels&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
		For example 0x40 (hexadecimal) = 64 (decimal). An I2C address are 7 MSB, the LSB is the R/W bit.<br>
		<code>&lt;n channels&gt;</code> is the number of A/D channels<br><br>
	</ul>
	<a name="I2C_MCP342xSet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt; [[[&lt;channel&gt;] &lt;resolution&gt; ] &lt;gain&gt;]</code><br>
		Returns the  level on specific &lt;channel&gt;. &lt;resolution&gt; and &lt;gain&gt; will override attibutes for actual operation.
		Without attributes only the readings will be refreshed.<br><br>
	</ul>
	<a name="I2C_MCP342xAttr"></a>
	<b>Attributes</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Set the polling interval in minutes to query data from sensor<br>
			Default: 5, valid values: 1,2,5,10,20,30<br><br>
		</li>
		Following attributes are separate for all channels.<br><br>
		<li><a name="ch1resolution">ch1resolution</a><br>
			resolution settings<br>
			the bigger the resolution the longer the conversion time.<br>
			Default: 12, valid values: 12,14,16,18<br><br>
		</li>
		<li><a name="ch1gain">ch1gain</a><br>
			gain setting<br>
			Important: the gain setting will reduce the measurement range an may produce an overflow. In this case "overflow" will be added to reading<br>
			Default: 1, valid values: 1,2,4,8<br><br>
		</li>
		<li><a name="ch1factor">ch1factor</a><br>
			correction factor (will be mutiplied to channel value)<br>
			Default: 1, valid values: number<br><br>
		</li>
		<li><a name="ch1roundDecimal">ch1roundDecimal</a><br>
			Number of decimal places for value<br>
			Default: 3, valid values: 0,1,2,3<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_MCP342x"></a>
<h3>I2C_MCP342x</h3>
<ul>
	<a name="I2C_MCP342x"></a>
		Erm&ouml;glicht die Verwendung eines MCP3422/3/4 I2C A/D Wandler.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_MCP342xDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_MCP342x [[&lt;I2C Address&gt;] &lt;n channels&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Beispielsweise 0x40 (hexadezimal) = 64 (dezimal). Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
		<code>&lt;n channels&gt;</code> ist die Anzahl der A/D Kanäle.<br>
	</ul>
	<a name="I2C_MCP342xGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt; [[[&lt;channel&gt;] &lt;resolution&gt; ] &lt;gain&gt;]</code><br>
		Aktuelle Werte vom entstrechenden &lt;channel&gt; lesen. &lt;resolution&gt; und &lt;gain&gt; &uuml;berschreiben die entsprechenden Attribute für diesen Lesevorgang<br><br>
	</ul>
	<a name="I2C_MCP342xAttr"></a>
	<b>Attribute</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
		</li>
		Folgende Attribute existieren separat f&uuml;r alle Kan&auml;le.<br><br>
		<li><a name="ch1resolution">ch1resolution</a><br>
			Aufl&ouml;sung des Kanals<br>
			Je gr&ouml;&szlig;er die Aufl&ouml;sung desto l&auml;nger die Lesezeit.<br>
			Standard: 12, g&uuml;ltige Werte: 12,14,16,18<br><br>
		</li>
		<li><a name="ch1gain">ch1gain</a><br>
			Verst&auml;rkungsfaktor<br>
			Wichtig: Der Verst&auml;rkungsfaktor verringert den Messbereich entsprechend und kann zu einem &Uuml;berlauf f&uuml;hren. In diesem Fall wird "overflow" an das reading angeh&auml;ngt.<br>
			Standard: 1, g&uuml;ltige Werte: 1,2,4,8<br><br>
		</li>
		<li><a name="ch1factor">ch1factor</a><br>
			Korrekturfaktor (Wird zum Kanalwert multipliziert.)<br>
			Standard: 1, g&uuml;ltige Werte: Zahl<br><br>
		</li>
		<li><a name="ch1roundDecimal">ch1roundDecimal</a><br>
			Anzahl Dezimalstellen f&uuml;r den Messwert<br>
			Standard: 3, g&uuml;ltige Werte: 0,1,2,3<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html_DE

=cut