##############################################################################
# $Id$
##############################################################################
# Modul for I2C EEPROM
#
# contributed by Klaus Wittstock (2013) email: klauswittstock bei gmail
##############################################################################

package main;
use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

my %setsP = (
'byte' => 0,
'bit' => 1,
'word' => 2,
'dword' => 3,
'qword' => 4,
);

my $sets = "byte bit word dword qword";

###############################################################################
sub I2C_EEPROM_Initialize($) {
	my ($hash) = @_;
	$hash->{DefFn}    = "I2C_EEPROM_Define";
	$hash->{InitFn}   = 'I2C_EEPROM_Init';
	$hash->{UndefFn}  = "I2C_EEPROM_Undefine";
	$hash->{AttrFn}   = "I2C_EEPROM_Attr";
	$hash->{SetFn}    = "I2C_EEPROM_Set";
	$hash->{GetFn}    = "I2C_EEPROM_Get";
	$hash->{I2CRecFn} = "I2C_EEPROM_I2CRec";
	$hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
						"EEPROM_size:2k,128 poll_interval ".
						"$readingFnAttributes";
}
###############################################################################
sub I2C_EEPROM_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
	if ($main::init_done) {
		eval { I2C_EEPROM_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_EEPROM_Catch($@) if $@;
	}
	return undef;
}
###############################################################################
sub I2C_EEPROM_Init($$) {																										#Geraet beim anlegen/booten/nach Neuverbindung (wieder) initialisieren
 my ( $hash, $args ) = @_;
 if (defined $args && int(@$args) != 1) {
	return "Define: Wrong syntax. Usage:\n" .
				 "define <name> I2C_EEPROM <i2caddress>";
 }
 if (defined (my $address = shift @$args)) {
	$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
 } else {
	return "$hash->{NAME} I2C Address not valid";
 }
 AssignIoPort($hash);
 I2C_EEPROM_Get($hash, $hash->{NAME});
 $hash->{STATE} = 'Initialized';
 return undef;
}
###############################################################################
sub I2C_EEPROM_Catch($) {																										#Fehlermeldung von eval formattieren
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}
###############################################################################
sub I2C_EEPROM_Undefine($$) {
	my ($hash, $arg) = @_;
	if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
		RemoveInternalTimer($hash);
	}
}
###############################################################################
sub I2C_EEPROM_Attr(@) {
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 if ($command && $command eq "set" && $attr && $attr eq "IODev") {
	if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
		main::AssignIoPort($hash,$val);
		my @def = split (' ',$hash->{DEF});
		I2C_EEPROM_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
 }
 if ($attr && $attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		if (!defined($val) ) {
			RemoveInternalTimer($hash);
		} elsif ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_EEPROM_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		} 
 } 
 return ($msg) ? $msg : undef;
}
###############################################################################
sub I2C_EEPROM_Poll($) {																										#function for refresh intervall
	my ($hash) = @_;
	my $name = $hash->{NAME};
	# Read values
	I2C_EEPROM_Get($hash, $name);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_EEPROM_Poll', $hash, 0);
	}
} 
###############################################################################
sub I2C_EEPROM_Set($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
    my $val = $a[2];
	my $msg = undef;
    
    my $setList = " ";
	return "Unknown argument, choose one of $setList" if(defined($a[1]) && $a[1] eq '?');
    
    if (@a > 2) {   
    	if (@a == 4) {
    		if ($a[2] =~ m/^(B|b)(it|)((0|)[0-7])$/i) {
  	      		my $bit = $a[2];
				$bit =~ tr/(B|b)(it|)//d;			#Nummer aus String extrahieren
  	      		$bit = $bit =~ /^0.*$/ ? oct($bit) : $bit;
				my $val = hex( I2C_EEPROM_BytefromReading($hash, $cmd) );
 	       		my $mask = 1 << $bit;
 	       		if ($a[3] eq "1") {
	 		       	$val |=  $mask;    # set bit
	 	       } else {
					$val &= ~$mask;    # clear bit
	 	       }
 			} else {
        		return "Unknown argument $a[2] use \"set <register> [Bit<bitnumber>] <value>\" where <bitnumber> is 0..7 and value is 0..255 (or 0|1 if you use Bit)";
	 		}
		}
		$val = $val =~ /^0.*$/ ? oct($val) : $val;
		$cmd = $cmd =~ /^0.*$/ ? oct($cmd) : $cmd;
		if (looks_like_number($cmd)) {
			my $nbyte = ( (AttrVal($hash->{NAME}, "EEPROM_size", "128") eq "2k") ? 256 : 16 );
			if ($nbyte > $cmd ) {
				$msg = I2C_EEPROM_SetReg($hash, $cmd, $val);
			} else {
				$msg = "$name error: $cmd is outside of address range (". $nbyte - 1 .")";
			}
		}
    }
	return ($msg) ? $msg : undef;

}
###############################################################################
sub I2C_EEPROM_Get($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];

	my $nbyte = ( (AttrVal($hash->{NAME}, "EEPROM_size", "128") eq "2k") ? 256 : 16 );
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
	$sendpackage{reg} = 0;
	$sendpackage{nbyte} = $nbyte;
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	
    my $setList = " ";
	return "Unknown argument, choose one of $setList" if(defined($a[1]) && $a[1] eq '?');
    
	if ( defined $a[1]) {
	    $a[1] = $a[1] =~ /^0.*$/ ? oct($a[1]) : $a[1];
	    if (looks_like_number($a[1]) ) {
			return "$name error: $a[1] is outside of address range (". $nbyte - 1 .")" unless ($nbyte > $a[1] );
            
            my $num = (defined $a[2] && $a[2] =~ m/^(dec|bin|hex)$/i) ? $a[2] : undef;
            
            my $rbyte = I2C_EEPROM_BytefromReading($hash, $a[1], $num);
			if ( defined $a[2] && $a[2] !~ m/^(dec|bin|hex)$/i ) {
            	if ($a[2] =~ m/^b(it|)((0|)[0-7])$/i){
					$a[2] =~ tr/(B|b)(it|)//d;			#Nummer aus String extrahieren
					$rbyte = (( hex($rbyte) >> $a[2] ) & 1) == 1 ? 1 : "0 " ;
				}else {
                	return "$name error: $a[2] is outside of range (Bit0..Bit7)";
                }
			}
			return $rbyte;
		}
	} 
		
}
###############################################################################
sub I2C_EEPROM_I2CRec($@) {																		#ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 												#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
	if ($clientmsg->{direction} && defined $clientmsg->{reg} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
		if ($clientmsg->{direction} eq "i2cread" && $clientmsg->{received}) {
			my @rec = split(" ",$clientmsg->{received});
			Log3 $hash, 3, "$name: wrong amount of registers transmitted from $pname" unless (@rec == $clientmsg->{nbyte});
			foreach (reverse 0..$#rec) {
				I2C_EEPROM_UpdReadings($hash, $_ + $clientmsg->{reg} , $rec[$_]);
			}
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} elsif ($clientmsg->{direction} eq "i2cwrite" && defined $clientmsg->{data}) { #readings aktualisieren wenn uebertragung ok
			I2C_EEPROM_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{data});
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} else {
			readingsSingleUpdate($hash,"state", "transmission error", 1);
			Log3 $hash, 3, "$name: failurei in message from $pname";
			Log3 $hash, 3,(defined($clientmsg->{direction}) ? 		"Direction: "	.					 $clientmsg->{direction} 	: "Direction: undef").
							(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) 	: " I2Caddress: undef").
							(defined($clientmsg->{reg}) ? 			" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 		: " Register: undef").
							(defined($clientmsg->{data}) ? 		" Data: " 		. sprintf("0x%.2X", $clientmsg->{data}) 		: " Data: undef").
							(defined($clientmsg->{received}) ? 	" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		}
	} else {
		readingsSingleUpdate($hash,"state", "transmission error", 1);
		Log3 $hash, 3, "$name: failure in message from $pname";
		Log3 $hash, 3,(defined($clientmsg->{direction}) ? 		"Direction: "	.					 $clientmsg->{direction} 	: "Direction: undef").
						(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) 	: " I2Caddress: undef").
						(defined($clientmsg->{reg}) ? 			" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 		: " Register: undef").
						(defined($clientmsg->{data}) ? 		" Data: " 		. sprintf("0x%.2X", $clientmsg->{data}) 		: " Data: undef").
						(defined($clientmsg->{received}) ? 	" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		}
}
###############################################################################
sub I2C_EEPROM_UpdReadings($$$) {																						#nach Rueckmeldung readings updaten (ueber I2CRec aufgerufen)
	my ($hash, $reg, $inh) = @_;
	my $name = $hash->{NAME};
	Log3 $hash, 5, "$name UpdReadings Register: $reg, Inhalt: $inh";
	my $regb = $reg >> 4;
	my $regp = $reg & 15;
	my $bank = ReadingsVal($name,"0x".sprintf("%02X",$regb)."x",".. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..");
	my $nbank = $bank;
	substr($nbank,$regp * 3,2,sprintf("%02X",$inh));
	if ($nbank ne $bank) {	#bei Aenderung
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "0x".sprintf("%02X",$regb)."x" , $nbank);
		readingsEndUpdate($hash, 1);
	}
	return;
}
###############################################################################
sub I2C_EEPROM_SetReg {																									#set register
	my ($hash, $reg, $inh) = @_;
	
	if (defined (my $iodev = $hash->{IODev})) {
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			direction  => "i2cwrite",
			i2caddress => $hash->{I2C_Address},
			reg => 				$reg,
			data => 			$inh,
			}) if (defined $hash->{I2C_Address});
	} else {
		return "no IODev assigned to '$hash->{NAME}'";
	}
}
###############################################################################
sub I2C_EEPROM_BytefromReading($@) {
	my ($hash, $reg, $num) = @_;
    #$num = "hex" unless defined $num ;
    my $regb = $reg >> 4;
	my $regp = $reg & 15;
	my $bank = ReadingsVal($hash->{NAME},"0x".sprintf("%02X",$regb)."x",".. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..");
    if ($num eq 'dec') {
    	return hex(substr($bank,$regp * 3,2));
    } elsif ($num eq 'bin') {
    	return sprintf ('0b%08b', hex(substr($bank,$regp * 3,2)));
    } else {
    	return "0x" . substr($bank,$regp * 3,2);
    }
	
}
1;

=pod
=item device
=item summary reads the content from an via I2C connected EEPROM
=item summary_DE lesen des Inhals eines &uuml;ber I2C angeschlossenen EEPROM
=begin html

<a name="I2C_EEPROM"></a>
<h3>I2C_EEPROM</h3>
<ul>
	<a name="I2C_EEPROM"></a>
		Provides an interface to an I2C EEPROM.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_EEPROMDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_EEPROM &lt;I2C Address&gt;</code><br>
		<code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
		For example 0x40 (hexadecimal) = 64 (decimal). An I2C address are 7 MSB, the LSB is the R/W bit.<br>
	</ul>

	<a name="I2C_EEPROMSet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;byte address&gt; &lt;value&gt;</code><br><br>
				where <code>&lt;byte address&gt;</code> is a number (0..device specific) and <code>&lt;value&gt;</code> is a number (0..255)<br>
				both numbers can be written in decimal or hexadecimal notation.<br>
		<br>
		Example:
		<ul>
			<code>set eeprom1 0x02 0xAA</code><br>
			<code>set eeprom1 2 170</code><br>
		</ul><br>
	</ul>

	<a name="I2C_EEPROMGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>
		<ul>
		<code>get &lt;name&gt; &lt;byte address&gt; [Bit&lt;bitnumber(0..7)&gt;]</code>
		<br><br>
		returnes actual reading of stated &lt;byte address&gt; or a single bit of &lt;byte address&gt;<br>
		Values are readout from readings, NOT from device!
	</ul><br>
	

	<a name="I2C_EEPROMAttr"></a>
	<b>Attributes</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Set the polling interval in minutes to query the EEPROM content<br>
			Default: -, valid values: decimal number<br><br>
		</li>
		<li><a name="EEPROM_size">EEPROM_size</a><br>
			Sets the storage size of the EEPROM<br>
			Default: 128, valid values: 128 (128bit), 2k (2048bit)<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html

=begin html_DE

<a name="I2C_EEPROM"></a>
<h3>I2C_EEPROM</h3>
<ul>
	<a name="I2C_EEPROM"></a>
		Erm&ouml;glicht die Verwendung I2C EEPROM. 
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_EEPROMDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_EEPROM &lt;I2C Address&gt;</code><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Beispielsweise 0x40 (hexadezimal) = 64 (dezimal). Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
	</ul>

	<a name="I2C_EEPROMSet"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;byte address&gt; &lt;value&gt;</code><br><br>
				<code>&lt;byte address&gt;</code> ist die Registeradresse (0..IC abh&auml;ngig) und <code>&lt;value&gt;</code> der Registerinhalt (0..255)<br>
				Beide Zahlen k&ouml;nnen sowohl eine Dezimal- als auch eine Hexadezimalzahl sein.<br>
		<br>
		Beispiel:
		<ul>
			<code>set eeprom1 0x02 0xAA</code><br>
			<code>set eeprom1 2 170</code><br>
		</ul><br>
	</ul>

	<a name="I2C_EEPROMGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>
	<ul>
		<code>get &lt;name&gt; &lt;byte address&gt; [Bit&lt;bitnumber(0..7)&gt;]</code>
		<br><br>
		Gibt den Inhalt des in &lt;byte address&gt; angegebenen Registers zur&uuml;ck, bzw. ein einzelnes Bit davon.<br>
		Achtung mit diesem Befehl werden nur die Werte aus den Readings angezeigt und nicht der Registerinhalt selbst! 
	</ul><br>

	<a name="I2C_EEPROMAttr"></a>
	<b>Attribute</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
		<li><a name="EEPROM_size">EEPROM_size</a><br>
			Speichergröße des EEPROM<br>
			Standard: 128, g&uuml;ltige Werte: 128 (128bit), 2k (2048bit)<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html_DE

=cut