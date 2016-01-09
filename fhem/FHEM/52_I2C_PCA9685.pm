##############################################################################
# $Id$
#
##############################################################################
# Modul for I2C PWM Driver PCA9685
#
# define <name> I2C_PCA9685 <I2C-Adresse>
# set <name> <port> <value>
#
# contributed by Klaus Wittstock (2015) email: klauswittstock bei gmail punkt com
#
##############################################################################

#Inhalte des Hashes:
#i2caddress				00-127(7F)				I2C-Adresse
#direction				i2cread|i2cwrite		Richtung
#reg					00-255|""				Registeradresse (kann weggelassen werden fuer IC's ohne Registeradressierung)
#nbyte					Zahl					Anzahl Register, die bearbeitet werden sollen (im mom 0-99)
#data					00-255 ... 				Daten die an I2C geschickt werden sollen (muessen, wenn nbyte benutzt wird immer ein Vielfaches Desselben sein)
#received				00-255 ...				Daten die vom I2C empfangen wurden, durch Leerzeichen getrennt (bleibt leer wenn Daten geschrieben werden)
#pname_SENDSTAT			Ok|error				zeigt uebertragungserfolg an

package main;
use strict;
use warnings;
use SetExtensions;
#use POSIX;
use Scalar::Util qw(looks_like_number);

my $setdim = ":slider,0,1,4095 ";

my %setsP = (
'off' => 0,
'on' => 1,
); 

my %defaultreg = (
'modereg1'	=> 32,		#32-> Bit 5 -> Autoincrement
'modereg2'	=> 0,
'sub1'	=> 113,
'sub2'	=> 114,
'sub3'	=> 116,
'allc'	=> 112,
'presc' => 30,
);

my %mr1 = (
'EXTCLK'	=> 64,
'SLEEP' 	=> 16,
'SUB1' 		=> 8,
'SUB2' 		=> 4,
'SUB3' 		=> 2,
'ALLCALL' 	=> 1,
);

my %mr2 = (
'INVRT'	=> 16,
'OCH'	=> 8,
'OUTDRV'=> 4,
'OUTNE1'=> 2,
'OUTNE0'=> 1,
);
#############################################################################
sub I2C_PCA9685_Initialize($) {												#
	my ($hash) = @_;
	$hash->{DefFn}    = "I2C_PCA9685_Define";
	$hash->{InitFn}   = 'I2C_PCA9685_Init';
	$hash->{UndefFn}  = "I2C_PCA9685_Undefine";
	$hash->{AttrFn}   = "I2C_PCA9685_Attr";
	$hash->{StateFn}  = "I2C_PCA9685_State";
	$hash->{SetFn}    = "I2C_PCA9685_Set";
	$hash->{GetFn}    = "I2C_PCA9685_Get";
	$hash->{I2CRecFn} = "I2C_PCA9685_I2CRec";
	$hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
						"prescale:slider,0,1,255 OnStartup ".
						"subadr1 subadr2 subadr3 allcalladr ".
						"modreg1:multiple-strict,EXTCLK,SUB1,SUB2,SUB3,ALLCALL ".
						"modreg2:multiple-strict,INVRT,OCH,OUTDRV,OUTNE0,OUTNE1 ".
						"$readingFnAttributes dummy:0,1";
}
#############################################################################
sub I2C_PCA9685_SetState($$$$) {											#-------wozu?
	my ($hash, $tim, $vt, $val) = @_;

	$val = $1 if($val =~ m/^(.*) \d+$/);
	#return "Undefined value $val" if(!defined($it_c2b{$val}));
	return undef;
}
#############################################################################
sub I2C_PCA9685_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
 if ($main::init_done) {
		eval { I2C_PCA9685_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_PCA9685_Catch($@) if $@;
	}
	return undef;
}
#############################################################################
sub I2C_PCA9685_Init($$) {													#
	my ( $hash, $args ) = @_;
	#my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME}; 
	if (defined $args && int(@$args) != 1)	{
		return "Define: Wrong syntax. Usage:\n" .
					 "define <name> I2C_PCA9685 <i2caddress>";
	}
	#return "$name I2C Address not valid" unless ($a[0] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
	my $msg = undef;
	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
	} else {
		return "$name I2C Address not valid";
	}
	AssignIoPort($hash);
	#Mode register wiederherstellen
	I2C_PCA9685_Attr(undef, $name, "modreg1", AttrVal($name, "modreg1", ""));
	I2C_PCA9685_Attr(undef, $name, "modreg2", AttrVal($name, "modreg2", ""));
	#alternative I2C Adressen wiederherstellen
	I2C_PCA9685_i2cwrite($hash,AttrVal($name, $defaultreg{'sub1'}, "subadr1")		<< 1, 2) if defined AttrVal($name, "subadr1", undef);
	I2C_PCA9685_i2cwrite($hash,AttrVal($name, $defaultreg{'sub2'}, "subadr2")		<< 1, 3) if defined AttrVal($name, "subadr2", undef);
	I2C_PCA9685_i2cwrite($hash,AttrVal($name, $defaultreg{'sub3'}, "subadr3")		<< 1, 4) if defined AttrVal($name, "subadr3", undef);
	I2C_PCA9685_i2cwrite($hash,AttrVal($name, $defaultreg{'allc'}, "allcalladr")	<< 1, 5) if defined AttrVal($name, "allcalladr", undef);
	#PWM Frequenz wiederherstellen
	I2C_PCA9685_Attr(undef, $name, "prescale", AttrVal($name, "prescale", $defaultreg{'presc'})) if defined AttrVal($name, "prescale", undef);
	#Portzustände wiederherstellen
	foreach (0..15) {
		I2C_PCA9685_Set($hash, $name,"Port".sprintf ('%02d', $_), ReadingsVal($name,"Port".$_,0) );
	}
	$hash->{STATE} = 'Initialized';
	return;
}
#############################################################################
sub I2C_PCA9685_Catch($) {													#
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}
#############################################################################
sub I2C_PCA9685_State($$$$) {												# reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ($sname =~ m/^Port(((0|)[0-9])|(1[0-5]))$/i) {
		substr($sname,0,4,"");
		$sname = sprintf('%d', $sname);
		my %onstart = split /[,=]/, AttrVal($hash->{NAME}, "OnStartup", "");
		if ( exists($onstart{$sname}) && ( exists($setsP{$onstart{$sname}}) || ($onstart{$sname} =~ m/^\d+$/ && $onstart{$sname} < 4095) ) ) {
			Log3 $hash, 5, "$hash->{NAME}: Port" . sprintf('%02d', $sname) . " soll auf $onstart{$sname} gesetzt werden";
			readingsSingleUpdate($hash,"Port". sprintf('%02d', $sname), $onstart{$sname}, 1);
		} else {
			Log3 $hash, 5, "$hash->{NAME}: Port" . sprintf('%02d', $sname) . " soll auf Altzustand: $sval gesetzt werden";
			$hash->{READINGS}{'Port'. sprintf('%02d', $sname)}{VAL} = $sval;
			$hash->{READINGS}{'Port'. sprintf('%02d', $sname)}{TIME} = $tim;
		}
	}
	return undef;
}
#############################################################################
sub I2C_PCA9685_Undefine($$) {												#
	my ($hash, $arg) = @_;
	return undef
}
#############################################################################
sub I2C_PCA9685_Attr(@) {													#
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_PCA9685_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	} elsif ($attr && $attr =~ m/^prescale$/i) {					#Frequenz
		return "wrong value: $val for \"set $name $attr\" use 0-255"
			unless(looks_like_number($val) && $val >= 0 && $val < 256);
		my $modereg1 = defined $hash->{confregs}{0} ? $hash->{confregs}{0} : $defaultreg{'modreg1'};
		my $modereg1mod = ( $modereg1 & 0x7F ) | $mr1{ "SLEEP" };
		$msg = I2C_PCA9685_i2cwrite($hash, 0, $modereg1mod);	#sleep Mode aktivieren
		$msg .= I2C_PCA9685_i2cwrite($hash, 254 ,$val);			#Frequenz aktualisieren
		$msg .= I2C_PCA9685_i2cwrite($hash, 0 ,$modereg1);		#sleep Mode wieder aus
		#Log3 $hash, 1, "testprescale: $modereg1 | $modereg1mod | $val";
	} elsif ($attr && $attr =~ m/^(subadr[1-3])|allcalladr$/i) {
		substr($attr,0,6,"");										#weitere I2C Adressen
		my $regaddr = ($attr =~ m/^l/i) ? 5 : $attr + 1;
		my $subadr  = $val =~ /^0.*$/ ? oct($val) : $val;
		return "I2C Address not valid" if $subadr > 127;
		$msg = I2C_PCA9685_i2cwrite($hash, $regaddr ,$subadr << 1);
	} elsif ($attr && $attr =~ m/^modreg1$/i) {						#Mode register 1
		my @inp = split(/,/, $val) if defined($val);
		my $data = 32; 				# Auto increment soll immer gesetzt sein
		foreach (@inp) {
			return "wrong value: $_ for \"attr $name $attr\" use comma separated list of " . join(',', (sort { $mr1{ $a } <=> $mr1{ $b } } keys %setsP) )
				unless(exists($mr1{$_}));
			$data |= $mr1{$_};
			if ($_ eq "EXTCLK") {		#wenn externer Oszillator genutzt werden soll, zuerst den sleep mode aktivieren (wenn er gelöscht wird dann noch reset machen)
				my $modereg1 = defined $hash->{confregs}{0} ? $hash->{confregs}{0} : $defaultreg{'modreg1'};
				my $modereg1mod = ( $modereg1 & 0x7F ) | $mr1{ "SLEEP" };
				Log3 $hash, 5, "$hash->{NAME}: sleep Mode aktivieren (Vorbereitung fuer EXTCLK)";
				$msg = I2C_PCA9685_i2cwrite($hash, 0 ,$modereg1mod);	#sleep Mode aktivieren
				$data += $mr1{"SLEEP"};
			}
		}
		#my $modereg1 = defined $hash->{confregs}{0} ? $hash->{confregs}{0} : $defaultreg{'modreg1'};
		#Log3 $hash, 1, "test1: " . ($hash->{confregs}{0} & $mr1{"EXTCLK"}) . "|" . $hash->{confregs}{0} ."|". $mr1{"EXTCLK"} . " test2: ". ($data & $mr1{"EXTCLK"}) ."|" . $data ."|". $mr1{"EXTCLK"};
		if ( defined $hash->{confregs}{0} && ($hash->{confregs}{0} & $mr1{"EXTCLK"}) == $mr1{"EXTCLK"} && ($data & $mr1{"EXTCLK"}) == 0 ) {  #reset wenn EXTCLK abgeschaltet wird
			$msg = I2C_PCA9685_i2cwrite($hash, 0 , $data | 0x80);
		}
		$msg = I2C_PCA9685_i2cwrite($hash, 0 , $data);
	} elsif ($attr && $attr =~ m/^modreg2$/i) {						#Mode register 2
		my @inp = split(/,/, $val) if defined($val);
		my $data = 0; 						# Auto increment soll immer gesetzt sein
		foreach (@inp) {
			return "wrong value: $_ for \"attr $name $attr\" use comma separated list of " . join(',', (sort { $mr2{ $a } <=> $mr2{ $b } } keys %setsP) )
				unless(exists($mr2{$_}));
			$data += $mr2{$_};
		}
		$msg = I2C_PCA9685_i2cwrite($hash, 1, $data);
	} elsif ($attr && $attr eq "OnStartup") {
	# Das muss noch angepasst werden !!!!!!!!!!!!!!!!!!!!
	if (defined $val) {
		foreach (split (/,/,$val)) {
			my @pair = split (/=/,$_);
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <port>=on|off|0..4095|last where <port> = 0 - 15 " 
				unless ( scalar(@pair) == 2 &&
								(($pair[0] =~ m/^[0-9]|1[0-5]$/i && ( $pair[1] eq "last" || exists($setsP{$pair[1]}) || 
								( $pair[1] =~ m/^\d+$/ && $pair[1] < 4095 ) ) ) )
								);		
		}
	}
 }
	return ($msg) ? $msg : undef; 
}
#############################################################################
sub I2C_PCA9685_Set($@) {													#
	my ($hash, $name, @a) = @_;
	my $port = $a[0];
	my $val  = $a[1];

	my $dimstep = AttrVal($name, "dimstep", "1");
	my $dimcount = AttrVal($name, "dimcount", "4095");
	my $msg;

	#my $str = join(" ",@a);
	#if ($str $$ $str =~ m/^(P(ort|)((0|)[0-9]|1[0-5])) $/i) {														# mehrere Port (unfertig)
	#	
	#	if (index($str, ',') != -1) {											# wenn mehrere Kanaele gesetzt werden sollen
	#		my @einzel = split(',', $str);
	#		my (undef, $tval, $tdval) = split(' ', $einzel[$#einzel]);			# Dimmwerte von letztem Eintrag sichern 
	#		Log3 $hash, 1, "Tempval: $tval | $tdval";
	#		foreach (reverse @einzel) {
	#			my @cmd = split(' ', $_);
	#			my ($dim, $delay);
	#			my $port = $cmd[0];
	#			$port =~ tr/P(ort|)//d;
	#			if (defined($cmd[1])) {
	#				$dim  = $cmd[1];
	#				$delay = $cmd[2];
	#			} else {
	#				$dim  = $tval;
	#				$delay = $tdval;
	#			}
	#			Log3 $hash, 1, "Werte fuer $port: $dim | $delay";
	#			#hier
	#			
	#			
	#		}
	#	}
	#}
	
	if ( $port && $port =~ m/^(P(ort|)((0|)[0-9]|1[0-5]))|(All)$/i) {			# wenn ein Port oder alle
		return "wrong value: $val for \"set $name $port\" use one of: " . 
			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) .
			" 0..$dimcount"
			unless(exists($setsP{$val}) || ($val >= 0 && $val <= $dimcount));
		($port =~ m/^All$/i) ? $port = 61 : $port =~ tr/P(ort|)//d;			# Portnummer extrahieren oder 61 für All setzen (All Startreg ist 250)
		my $reg = 6 + 4 * $port;											# Nummer des entspechenden LEDx_ON_L Registers (LED0_ON_L = 0x06) jede LED hat 4 Register
		my $data = I2C_PCA9685_CalcRegs($hash, $port, $val, $a[2]);			# Registerinhalte berechnen
		$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data);						# Rausschicken
	} else {	
		my $list = undef;
		foreach (0..15) {
			$list .= "Port" . sprintf ('%02d', $_) . ":slider,0,$dimstep,$dimcount ";
		}
		$list .= "all:slider,0,$dimstep,$dimcount";
		$msg = "Unknown argument $a[0], choose one of " . $list;
	}
	return defined $msg ? $msg : undef 
}
		#my $string = 'AA55FF0102040810204080';
		#my @hex    = ($string =~ /(..)/g);
		#my @dec    = map { hex($_) } @hex;
		#my @bytes  = map { pack('C', $_) } @dec;
		#or
		#my @bytes  = map { pack('C', hex($_)) } ($string =~ /(..)/g);
		#or
		#my $bytes = pack "H*", $hex;
		#----------------------
		#$int = 2001;
		#$bint = pack("N", $int);
		#@octets = unpack("C4", $bint);
		#sprintf "%02X " x 4 . "\n", @octets;
		# prints: 00 00 07 D1
#############################################################################
sub I2C_PCA9685_CalcRegs($$$$) {											# Registerinhalte berechnen
	my ($hash, $port, $val, $del) = @_;
	my $dimcount = AttrVal($hash->{NAME}, "dimcount", "4095");
	my $data;
	if ($val eq "on") {
		$data = "0 16 0 0";
	} elsif ($val eq "off") {
		$data = "0 0 0 16";
	} else {
		my $delaytime = 0;
		if ($dimcount < 4095) {				#DimmWert anpassen bei anderem Faktor
			$val = int($val * 4095 / $dimcount);
		}
		if (defined $del) {					#Delaytime angegeben?
			return "wrong delay value: $del for \"set $hash->{NAME} Port$port $val $del\" use value between 0 and $dimcount"
				unless ($del >= 0 && $del <= $dimcount);
			if ($dimcount < 4095) {			#DelayWert anpassen bei anderem Faktor
				$del = int($del * 4095 / $dimcount);
			}
			$delaytime = $del
		} else {							#...wenn nicht aus Reading holen (für all kommt immer 0 raus)
			$delaytime = ReadingsVal($hash->{NAME},'Port_d'.sprintf ('%02d', $port),"0");
		}
		my $LEDx_OFF = $delaytime + $val - (( $val + $delaytime < 4096 ) ? 0 : 4096);
		if ($LEDx_OFF == $delaytime) { 		#beide Register dürfen nicht gleichen Inhalt haben, das entpricht "aus"
			$data = "0 0 0 16";
		} else {
			my @LEDx = unpack("C*", pack("S", $delaytime));
			push @LEDx, unpack("C*", pack("S", $LEDx_OFF));		#Array $LEDx[0] = LEDx_ON_L, $LEDx[1] = LEDx_ON_H, $LEDx[2] = LEDx_OFF_L, $LEDx[3] = LEDx_OFF_H
			$data = sprintf "%01d " x 4, @LEDx;
		}
	}
	return $data;
}
#############################################################################
sub I2C_PCA9685_Get($@) {													# Portwerte bei laden der Datailseite aktualisieren
	my ($hash, @a) = @_;


	I2C_PCA9685_i2cread($hash, 0x6, 64);
	return;
	
	#my $name =$a[0];
	#my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
	#$sendpackage{reg} = 0x6; 						#startadresse zum lesen
	#$sendpackage{nbyte} = 64;
	#return "$name: no IO device defined" unless ($hash->{IODev});
	#my $phash = $hash->{IODev};
	#my $pname = $phash->{NAME};
	#CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	
}
#############################################################################
sub I2C_PCA9685_i2cread($$$) {												# Lesebefehl an Hardware absetzen (antwort kommt in I2C_*****_I2CRec an)
	my ($hash, $reg, $nbyte) = @_;
	if (defined (my $iodev = $hash->{IODev})) {
		Log3 $hash, 5, "$hash->{NAME}: $hash->{I2C_Address} read $nbyte Byte from Register $reg";
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
		direction 	=> "i2cread",
		i2caddress	=> $hash->{I2C_Address},
		reg 		=> $reg,
		nbyte 		=> $nbyte
		});
	} else {
		if (AttrVal($hash->{NAME}, "dummy", 0) == 1) {
			Log3 $hash, 1, "attr dummy -> kann nix lesen"; 
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}	}
}
#############################################################################
sub I2C_PCA9685_i2cwrite($$$) {												# Schreibbefehl an Hardware absetzen
	my ($hash, $reg, @data) = @_;
	if (defined (my $iodev = $hash->{IODev})) {
		Log3 $hash, 5, "$hash->{NAME}: $hash->{I2C_Address} write join (' ',@data) to Register $reg";
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
		direction  	=> "i2cwrite",
		i2caddress 	=> $hash->{I2C_Address},
		reg 		=> $reg,
		data => join (' ',@data),
		});
	} else {
		if (AttrVal($hash->{NAME}, "dummy", 0) == 1) {
			I2C_PCA9685_UpdReadings($hash, $reg, @data);		# Zeile zum testen (Werte werden direkt zu I2CRec umgeleitet)
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}	}
}
#############################################################################
sub I2C_PCA9685_I2CRec($@) {												# vom IODev aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 							#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
	if ($clientmsg->{direction} && defined($clientmsg->{reg}) && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			I2C_PCA9685_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{received});
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} elsif ( $clientmsg->{direction} eq "i2cwrite" && defined($clientmsg->{data}) ) { 			#readings aktualisieren wenn uebertragung ok
			I2C_PCA9685_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{data});
			readingsSingleUpdate($hash,"state", "Ok", 1);
		
		} else {
			readingsSingleUpdate($hash,"state", "transmission error", 1);
			Log3 $hash, 3, "$name: failure in message from $pname";
			Log3 $hash, 3,	(defined($clientmsg->{direction}) ? 	"Direction: "	. 					$clientmsg->{direction} 	: "Direction: undef").
							(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress})	: " I2Caddress: undef").
							(defined($clientmsg->{reg}) ? 			" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 			: " Register: undef").
							(defined($clientmsg->{data}) ? 			" Data: " 		. sprintf("0x%.2X", $clientmsg->{data}) 		: " Data: undef").
							(defined($clientmsg->{received}) ? 		" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		}
	} else {
		readingsSingleUpdate($hash,"state", "transmission error", 1);
		Log3 $hash, 3, "$name: failure in message from $pname";
			Log3 $hash, 3,	(defined($clientmsg->{direction}) ? 	"Direction: "	.					$clientmsg->{direction} 	: "Direction: undef").
							(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) 	: " I2Caddress: undef").
							(defined($clientmsg->{reg}) ? 			" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 			: " Register: undef").
							(defined($clientmsg->{data}) ? 			" Data: " 		. sprintf("0x%.2X", $clientmsg->{data}) 		: " Data: undef").
							(defined($clientmsg->{received}) ? 		" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		}
}
#############################################################################
sub I2C_PCA9685_CalcVal($@) {												# Readings aus Registerwerten berechnen
	my ($dimcount, @reginh) = @_;
	my $delay = undef;
	my $dimval;
	if ($reginh[1] > 15) {
		$dimval = "on";
	} elsif ($reginh[3] > 15) {
		$dimval = "off";
	} else {
		$delay  = $reginh[1] * 256 + $reginh[0];
		my $temp = $reginh[3] * 256 + $reginh[2];
		$dimval = $temp - $delay + (( $temp > $delay ) ? 0 : 4096);
		if ($dimcount < 4095) {				#Wert anpassen bei anderem Faktor
			$dimval = int($dimval * $dimcount / 4095);
			$delay = int($delay * $dimcount / 4095);
		}
	}
	return $dimval, $delay;
}
############################################################################# 
sub I2C_PCA9685_UpdReadings($$$) {											# vom IODev gesendete Werte in Readings/Internals schreiben
	my ($hash, $reg, $inh) = @_;
	my $name = $hash->{NAME};
	#Log3 $hash, 1, "$name UpdReadings Start Register: " .sprintf("0x%.2X", $reg).", Inhalt: $inh";
	my @reginh = split(" ", $inh);
	my $dimstep = AttrVal($name, "dimstep", "1");
	my $dimcount = AttrVal($name, "dimcount", "4095");
	my $delay = undef;
	my $dimval;
	readingsBeginUpdate($hash);
	if ($reg == 250 && @reginh == 4) {									# wenn All
		($dimval, $delay) = I2C_PCA9685_CalcVal($dimcount, @reginh);
		foreach (0..15) {
			readingsBulkUpdate($hash, 'Port'.sprintf('%02d', $_) , $dimval) if (ReadingsVal($name, 'Port'.sprintf('%02d', $_), "failure") ne $dimval); #nur wenn Wert geaendert
			readingsBulkUpdate($hash, 'Port_d'.sprintf('%02d', $_) , $delay) if (defined $delay && ReadingsVal($name, 'Port_d'.$hash->{confregs}, "failure") ne $delay); #nur wenn Wert geaendert
		}
	} elsif ( $reg < 70 && $reg > 5 && @reginh == 4) {					#Wenn PortRegister
		my $port = sprintf ('%02d', ($reg - 6) / 4);
		($dimval, $delay) = I2C_PCA9685_CalcVal($dimcount, @reginh);
		readingsBulkUpdate($hash, 'Port'.$port , $dimval) if (ReadingsVal($name, 'Port'.$port, "failure") ne $dimval); #nur wenn Wert geaendert
		readingsBulkUpdate($hash, 'Port_d'.$port , $delay) if (defined $delay && ReadingsVal($name, 'Port_d'.$port, "failure") ne $delay); #nur wenn Wert geaendert
		Log3 $hash, 5, "$name: lese einen Port - Reg: $reg ; Inh: @reginh";
	
	} elsif ( $reg < 70 && $reg > 5 && @reginh > 4 ) {					#Wenn alle Ports abgefragt werden
		for (my $i = 0; $i < @reginh; $i++) {
			next unless ( ($reg + $i - 2) / 4  =~ m/^\d+$/ );
			my @regpart = ( $reginh[$i], $reginh[$i + 1], $reginh[$i + 2], $reginh[$i + 3] );
			my $port = sprintf ('%02d', ($reg + $i - 6) / 4);
			($dimval, $delay) = I2C_PCA9685_CalcVal($dimcount, @regpart);
			readingsBulkUpdate($hash, 'Port'.$port , $dimval) if (ReadingsVal($name, 'Port'.$port, "failure") ne $dimval); #nur wenn Wert geaendert
			readingsBulkUpdate($hash, 'Port_d'.$port , $delay) if (defined $delay && ReadingsVal($name, 'Port_d'.$port, "failure") ne $delay); #nur wenn Wert geaendert
			Log3 $hash, 5, "$name: lese mehrere Ports - Reg: $reg ; i: $i; Inh: @regpart";
			$i += 3;
		}
	} elsif ($reg == 254) { 											#wenn Frequenz Register
		my $clock = AttrVal($name, "extClock", 25);
		$hash->{Frequency} = sprintf( "0x%.1f", $clock * 1000000 / (4096 * ($inh + 1)) ) . " Hz";
	} elsif ( $reg >= 0 && $reg < 6 ) {									#Konfigurations Register
		$hash->{confregs}{$reg} = $inh;
		#folgendes evtl noch weg
		#$hash->{CONF} = (defined $hash->{confregs}{0} ? sprintf('0x%.2X ', $hash->{confregs}{0}) : "0x__ ") . 
		#				(defined $hash->{confregs}{1} ? sprintf('0x%.2X ', $hash->{confregs}{1}) : "0x__ ") .
		#				(defined $hash->{confregs}{2} ? sprintf('0x%.2X ', $hash->{confregs}{2}) : "0x__ ") .
		#				(defined $hash->{confregs}{3} ? sprintf('0x%.2X ', $hash->{confregs}{3}) : "0x__ ") .
		#				(defined $hash->{confregs}{4} ? sprintf('0x%.2X ', $hash->{confregs}{4}) : "0x__ ") .
		#				(defined $hash->{confregs}{5} ? sprintf('0x%.2X ', $hash->{confregs}{5}) : "0x__ ");
	}
	readingsEndUpdate($hash, 1);
	return;
}
#############################################################################

1;

=pod
=begin html

<a name="I2C_PCA9685"></a>
<h3>I2C_PCA9685</h3>
(en | <a href="commandref_DE.html#I2C_PCA9685">de</a>)
<ul>
	<a name="I2C_PCA9685"></a>
		Provides an interface to the PCA9685 I2C 16 channel PWM IC. 
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_PCA9685Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9685 &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> can be written as decimal value or 0xnn<br>
	</ul>

	<a name="I2C_PCA9685Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt; [&lt;delay&gt;]</code><br><br>
			<li>where <code>&lt;port&gt;</code> is one of Port00 to Port15<br>
			and <code>&lt;value&gt;</code> one of<br>
			<ul>
			<code>
				off<br>
				on<br>
				0..4095<br>
			</code>
			</ul>
			<code>&lt;delay&gt;</code> defines the switch on time inside the PWM counting loop. It does not have an influence to the duty cycle. Default value is 0 and, possible values are 0..4095<br>	
		</li>

		<br>
		Examples:
		<ul>
			<code>set mod1 Port04 543</code><br>
			<code>set mod1 Port14 434 765</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCA9685Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>


	<a name="I2C_PCA9685Attr"></a>
	<b>Attributes</b>
	<ul>
		<li>subadr1,subadr2,subadr3,allcalladr<br>
			Alternative slave addresses, if you want to control more than one PCA9685 with one define 
			Respective flag in modreg1 must be set as well<br>
			Default: subadr1=113,subadr2=114,subadr3=116,allcalladr=112, valid values: valid I2C Address <br><br>
		</li>
		<li>OnStartup<br>
			Comma separated list of output ports/PWM registers and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Default: -, valid values: &lt;port&gt;=on|off|0..4095|last where &lt;port&gt; = 0 - 15<br><br>
		</li>
		<li>prescale<br>
			Sets PWM Frequency. The Formula is: Fx = 25MHz/(4096 * (prescale + 1)) The corresponding frequency value is shown under internals (valid for the internal 25MHz clock).<br>
			Default: 30 (200Hz), valid values: 0-255<br><br>
		</li>
		<li>modreg1<br>
			Comma separated list of:
			<ul>
				<li>EXTCLK<br>
					If set the an external connected clock will be used instead of the internal 25MHz oscillator
				</li>
				<li>SUB1<br>
					If set the PCA9685 responds to I2C-bus subaddress 1.
				</li>
				<li>SUB2<br>
					If set the PCA9685 responds to I2C-bus subaddress 2.
				</li>
				<li>SUB3<br>
					If set the PCA9685 responds to I2C-bus subaddress 3.
				</li>
				<li>ALLCALL<br>
					If set the PCA9685 responds to I2C-bus allcall address.
				</li>
			</ul>
		</li>
		<li>modreg2<br>
			Comma separated list of:
			<ul>
				<li>INVRT<br>
					If set the Output logic state is inverted.<br>
				</li>
				<li>OCH<br>
					If set the outputs changes on ACK (after every byte sent).<br>
					Otherwise the output changes on STOP command (bus write action finished)<br>
				</li>
				<li>OUTDRV<br>
					If set the outputs are configured with a totem pole structure.<br>
					Otherwise the outputs are configured with open-drain.<br>
				</li>
				Behaviour when OE = 1 (if OE = 0 the output will act according OUTDRV configuration):
				<li>OUTNE0<br>
					If set:<br>
					LEDn = 1 when OUTDRV = 1<br>
					LEDn = high-impedance when OUTDRV = 0<br>
					If not set:
					LEDn = 0.<br>
				</li>
				<li>OUTNE1<br>
					LEDn = high-impedance.<br>
					OUTNE1 overrides OUTNE0<br><br>
				</li>
			</ul>		
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

<a name="I2C_PCA9685"></a>
<h3>I2C_PCA9685</h3>
(<a href="commandref.html#I2C_PCA9685">en</a> | de)
<ul>
	<a name="I2C_PCA9685"></a>
		Erm&ouml;glicht die Verwendung eines PCA9685 I2C 16 Kanal PWM IC. 
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_PCA9685Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9685 &lt;I2C Address&gt;</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert im Format 0xnn oder eine Dezimalzahl<br>
	</ul>

	<a name="I2C_PCA9685Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt; [&lt;delay&gt;]</code><br><br>
			<li>Als <code>&lt;port&gt;</code> kann Port00 bis Port15 verwendet werden<br>
			<code>&lt;value&gt;</code> kann folgende Werte annehmen:<br>
			<ul>
			<code>
				off<br>
				on<br>
				0..4095<br>
			</code>
			</ul>
			<code>&lt;delay&gt;</code> gibt den Wert innerhalb der Z&auml;hlschleife an, an dem der Ausgang eingeschaltet wird. Damit lassen sich die 16 Ausg&auml;nge zu unterschiedlichen Zeiten einschalten um Stromspitzen zu minimieren.
			Dieser Wert hat keinerlei Einfluss auf die Pulsbreite. Stardartwert ist 0, m&ouml;gliche Werte sind 0..4095<br>	
		</li>

		<br>
		Examples:
		<ul>
			<code>set mod1 Port04 543</code><br>
			<code>set mod1 Port14 434 765</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCA9685Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>


	<a name="I2C_PCA9685Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>subadr1,subadr2,subadr3,allcalladr<br>
			Alternative slave Adressen, if you want to control more than one PCA9685 with one define 
			Zus&auml;tzlich zu diesen Registern m&uuml;ssen die Passenden Bits in modreg1 gesetzt werden.<br>
			Standard: subadr1=113,subadr2=114,subadr3=116,allcalladr=112, g&uuml;ltige Werte: I2C Adresse <br><br>
		</li>
		<li>OnStartup<br>
			Comma separated list of output ports/PWM registers and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Standard: last, g&uuml;ltige Werte: &lt;port&gt;=on|off|0..4095|last wobei &lt;port&gt; = 0 - 15<br><br>
		</li>
		<li>prescale<br>
			Sets PWM Frequency. The Formula is: Fx = 25MHz/(4096 * (prescale + 1)) The corresponding frequency value is shown under internals (valid for the internal 25MHz clock).<br>
			Standard: 30 (200Hz), g&uuml;ltige Werte: 0-255<br><br>
		</li>
		<li>modreg1<br>
			Durch Komma getrennte Liste von:
			<ul>
				<li>EXTCLK<br>
					Anstelle des internen 25MHz Oszillators wird ein extern Angeschlossener verwendet.
				</li>
				<li>SUB1<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 1.
				</li>
				<li>SUB2<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 2.
				</li>
				<li>SUB3<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 3.
				</li>
				<li>ALLCALL<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Allcall Adresse.
				</li>
			</ul>
		</li>
		<li>modreg2<br>
			Durch Komma getrennte Liste von:
			<ul>
				<li>INVRT<br>
					Wenn gesetzt, werden die Ausg&auml;nge invertiert.<br>
				</li>
				<li>OCH<br>
					If set the outputs changes on ACK (after every byte sent).<br>
					Otherwise the output changes on STOP command (bus write action finished)<br>
				</li>
				<li>OUTDRV<br>
					Wenn gesetzt, werden die Ausg&auml;nge als totem pole konfiguriert.<br>
					Andernfalls sind sie open-drain.<br>
				</li>
				Verhalten bei OE = 1 (wenn OE = 0 verhalten sich die Ausg&auml;nge wie in OUTDRV eingestellt):
				<li>OUTNE0<br>
					Wenn gesetzt:<br>
					LEDn = 1 wenn OUTDRV = 1<br>
					LEDn = hochohmig wenn OUTDRV = 0<br>
					Wenn nicht gesetzt:
					LEDn = 0.<br>
				</li>
				<li>OUTNE1<br>
					LEDn = hochohmig.<br>
					Wenn OUTNE1 gesetzt wird OUTNE0 ignoriert.<br><br>
				</li>
			</ul>		
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