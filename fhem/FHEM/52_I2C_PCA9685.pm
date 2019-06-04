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

my $setdim = ":slider,0,1,4095 ";

my %setsP = (
'off' => 0,
'on' => 1,
); 

my %confregs = (
0 => 'modereg1',
1 => 'modereg2',
2 => 'SUBADR1',
3 => 'SUBADR2',
4 => 'SUBADR3',
5 => 'ALLCALLADR',
);

my %defaultreg = (
'modereg1'	=> 32,		#32-> Bit 5 -> Autoincrement
'modereg2'	=> 0,
'SUBADR1'	=> 113,
'SUBADR2'	=> 114,
'SUBADR3'	=> 116,
'ALLCALLADR'	=> 112,
'PRESCALE' => 30,
);

my %mr1 = (
'EXTCLK'	=> 64,
'SLEEP' 	=> 16,
'SUBADR1' 		=> 8,
'SUBADR2' 		=> 4,
'SUBADR3' 		=> 2,
'ALLCALLADR' 	=> 1,
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
	#$hash->{GetFn}    = "I2C_PCA9685_Get";
	$hash->{I2CRecFn} = "I2C_PCA9685_I2CRec";
	$hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
						"prescale:slider,0,1,255 OnStartup ".
						"SUBADR1 SUBADR2 SUBADR3 ALLCALLADR ".
						"modereg1:multiple-strict,EXTCLK,SUBADR1,SUBADR2,SUBADR3,ALLCALLADR ".
						"modereg2:multiple-strict,INVRT,OCH,OUTDRV,OUTNE0,OUTNE1 ".
						"$readingFnAttributes dummy:0,1 extClock";
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
sub I2C_PCA9685_Init($$) {													# wird ausgefuehrt bei Initialisierung und Connect/Reconnect des DEVio
	my ( $hash, $args ) = @_;
	#my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME}; 
	if (defined $args && int(@$args) < 1)	{
		return "Define: Wrong syntax. Usage:\n" .
					 "define <name> I2C_PCA9685 <i2caddress>";
	}
	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0x.*$/ ? oct($address) : $address; 
		return "$name: I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
	} else {
		return "$name: no I2C Address defined" unless defined($hash->{I2C_Address});
	}
	if (defined (my $maxbuff = shift @$args)) { 
		return "$name: I2C buffer size must be a number" if $maxbuff =~ m/^d+$/;
		$hash->{I2C_Buff} = $maxbuff;
	}
	my $msg = '';
	eval {
		Log3 $hash, 4, "$hash->{NAME}: Init1 Konfigurationsregister auslesen";
		AssignIoPort($hash);
		#Config Register lesen (einzeln, da Blockweises lesen noch aktiviert werden muss)
		I2C_PCA9685_i2cread($hash, 0, 1);		# Modereg1
		I2C_PCA9685_i2cread($hash, 1, 1);		# Modereg2
		I2C_PCA9685_i2cread($hash, 2, 1);		# Subadr1
		I2C_PCA9685_i2cread($hash, 3, 1);		# Subadr2
		I2C_PCA9685_i2cread($hash, 4, 1);		# Subadr3
		I2C_PCA9685_i2cread($hash, 5, 1);		# Allcalladr
		I2C_PCA9685_i2cread($hash, 254, 1);		# Frequenz fuer Internal
		$hash->{STATE} = 'Initializing';
		InternalTimer(gettimeofday() + 10, 'I2C_PCA9685_InitError', $hash, 0);	# nach 10s Initialisierungsfehler ablegen
		};
    return I2C_BME280_Catch($@) if $@;
}
#############################################################################
sub I2C_PCA9685_Init2($) {													# wird audgefuehrt wenn Frequenzregisterinhalt empfangen wird und entsprechendes Internal noch leer ist
	my ( $hash ) = @_;
	my $name = $hash->{NAME};
	eval {
		Log3 $hash, 4, "$hash->{NAME}: Init2 Konfigurationsregister beschreiben";
		RemoveInternalTimer($hash);				# Timer fuer Initialisierungsfehler stoppen
		# Mode register wiederherstellen
		I2C_PCA9685_Attr(undef, $name, "modereg1",   AttrVal($name, "modereg1", undef));
		I2C_PCA9685_Attr(undef, $name, "modereg2",   AttrVal($name, "modereg2", undef));
		# alternative I2C Adressen wiederherstellen
		I2C_PCA9685_Attr(undef, $name, "SUBADR1",	 AttrVal($name, "SUBADR1", undef));
		I2C_PCA9685_Attr(undef, $name, "SUBADR2", 	 AttrVal($name, "SUBADR2", undef));
		I2C_PCA9685_Attr(undef, $name, "SUBADR3",	 AttrVal($name, "SUBADR3", undef));
		I2C_PCA9685_Attr(undef, $name, "ALLCALLADR", AttrVal($name, "ALLCALLADR", undef));
		# PWM Frequenz wiederherstellen
		I2C_PCA9685_Attr(undef, $name, "prescale", 	 AttrVal($name, "prescale", undef));
		#Portzustände wiederherstellen
		foreach (0..15) {
			my $port = "Port".sprintf ('%02d', $_);
			I2C_PCA9685_Set($hash, $name, $port, ReadingsVal($name,$port ,0) );
		}
		$hash->{STATE} = 'Initialized';	
		};
    return I2C_BME280_Catch($@) if $@;
}
#############################################################################
sub I2C_PCA9685_InitError($) {												# wird audgefuehrt wenn 10s nach Init immer noch keine Registerwerte empfangen wurden
	my ( $hash ) = @_;
	$hash->{STATE} = 'Error during Initialisation';
}
#############################################################################
sub I2C_PCA9685_Catch($) {													# Fehlermeldung von eval formattieren
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
	Log3 $hash, 5, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ($sname =~ m/^Port(((0|)[0-9])|(1[0-5]))$/i) {
		substr($sname,0,4,"");
		$sname = sprintf('%d', $sname);
		my %onstart = split /[,=]/, AttrVal($hash->{NAME}, "OnStartup", "");
		if ( exists($onstart{$sname}) && ( exists($setsP{$onstart{$sname}}) || ($onstart{$sname} =~ m/^\d+$/ && $onstart{$sname} < 4095) ) ) {
			Log3 $hash, 5, "$hash->{NAME}: Port" . sprintf('%02d', $sname) . " soll auf $onstart{$sname} gesetzt werden";
			readingsSingleUpdate($hash,"Port". sprintf('%02d', $sname), $onstart{$sname}, 1);
		} else {
			Log3 $hash, 4, "$hash->{NAME}: Port" . sprintf('%02d', $sname) . " soll auf Altzustand: $sval gesetzt werden";
			$hash->{READINGS}{'Port'. sprintf('%02d', $sname)}{VAL} = $sval;
			$hash->{READINGS}{'Port'. sprintf('%02d', $sname)}{TIME} = $tim;
		}
	}
	return undef;
}
#############################################################################
sub I2C_PCA9685_Undefine($$) {												# wird beim loeschen des Device ausgefuehrt
	my ($hash, $arg) = @_;
	my ($msg, $data, $reg) = I2C_PCA9685_CalcRegs($hash, 61, 'off', undef);		# Registerinhalte berechnen alle Ports aus
	$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data) unless($msg);				# Rausschicken
	RemoveInternalTimer($hash);
	return undef
}
#############################################################################
sub I2C_PCA9685_Attr(@) {													# wird beim setzen eines Attributes ausgefuehrt
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_PCA9685_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	} elsif ($attr && $attr =~ m/^prescale$/i) {					# Frequenz
		$val = $defaultreg{'PRESCALE'} unless (defined($val)); 						#beim loeschen wieder auf Standard setzen
		return "wrong value: $val for \"set $name $attr\" use 0-255"
			unless($val =~ m/^(\d+)$/ && $val >= 0 && $val < 256);
		Log3 $hash, 5, $hash->{NAME} . ": $attr alter Wert: ".(defined($hash->{confregs}{PRESCALE})?$hash->{confregs}{PRESCALE}:"empty")." neuer Wert: ".$val;
		if ($main::init_done && $val != $hash->{confregs}{PRESCALE}) {
			my $modereg1 = defined $hash->{confregs}{$confregs{0}} ? $hash->{confregs}{$confregs{0}} : $defaultreg{'modereg1'};
			my $modereg1mod = ( $modereg1 & 0x7F ) | $mr1{ "SLEEP" };
			$msg = I2C_PCA9685_i2cwrite($hash, 0, $modereg1mod);	#sleep Mode aktivieren
			$msg = I2C_PCA9685_i2cwrite($hash, 254 ,$val);			#Frequenz aktualisieren
			$msg = I2C_PCA9685_i2cwrite($hash, 0 ,$modereg1);		#sleep Mode wieder aus
			foreach (0..15) {										#Portzustände wiederherstellen
				my $port = "Port".sprintf ('%02d', $_);
				I2C_PCA9685_Set($hash, $name, $port, ReadingsVal($name,$port ,0) );
			}
		}
	} elsif ($attr && $attr =~ m/^(SUBADR[1-3])|ALLCALLADR$/i) {	# weitere I2C Adressen
		$val = $defaultreg{$attr} unless defined($val);
		substr($attr,0,6,"");
		my $regaddr = ($attr =~ m/^l/i) ? 5 : $attr + 1;
		my $SUBADR  = $val =~ /^0x.*$/ ? oct($val) : $val;
		return "I2C Address not valid" if $SUBADR > 127;
		Log3 $hash, 5, $hash->{NAME} . ": $confregs{$regaddr} alter Wert: ".$hash->{confregs}{$confregs{$regaddr}}." neuer Wert: ".($SUBADR << 1);
		$msg = I2C_PCA9685_i2cwrite($hash, $regaddr ,$SUBADR << 1) if $main::init_done && ($SUBADR << 1) != $hash->{confregs}{$confregs{$regaddr}};
	} elsif ($attr && $attr =~ m/^modereg1$/i) {						# Mode register 1
		my @inp = split(/,/, $val) if defined($val);
		my $data = 32; 											# Auto increment soll immer gesetzt sein
		foreach (@inp) {
			return "wrong value: $_ for \"attr $name $attr\" use comma separated list of " . join(',', (sort { $mr1{ $a } <=> $mr1{ $b } } keys %setsP) )
				unless(exists($mr1{$_}));
			$data |= $mr1{$_};
			if ($main::init_done && $_ eq "EXTCLK" && ($hash->{confregs}{$confregs{0}} & $mr1{"EXTCLK"}) == 0) {			#wenn externer Oszillator genutzt werden soll, zuerst den sleep mode aktivieren
				my $modereg1 = defined $hash->{confregs}{$confregs{0}} ? $hash->{confregs}{$confregs{0}} : $defaultreg{'modereg1'};
				my $modereg1mod = ( $modereg1 & 0x7F ) | $mr1{ "SLEEP" };
				Log3 $hash, 5, "$hash->{NAME}: sleep Mode aktivieren (Vorbereitung fuer EXTCLK)";
				$msg = I2C_PCA9685_i2cwrite($hash, 0 ,$modereg1mod);	#sleep Mode aktivieren
#				$data += $mr1{"SLEEP"}; #???????? muss hier nicht deaktiviert werden?????
			}
		}
		if ($main::init_done && defined $hash->{confregs}{$confregs{0}} && ($hash->{confregs}{$confregs{0}} & $mr1{"EXTCLK"}) == $mr1{"EXTCLK"} && ($data & $mr1{"EXTCLK"}) == 0 ) {  #reset wenn EXTCLK abgeschaltet wird
			$msg = I2C_PCA9685_i2cwrite($hash, 0 , $data | 0x80);
		}
		Log3 $hash, 5, $hash->{NAME} . ": $attr alter Wert: ".$hash->{confregs}{$confregs{0}}." neuer Wert: ".$data;
		if ( $main::init_done && $data != $hash->{confregs}{$confregs{0}} ) {
			I2C_PCA9685_UpdReadings($hash, 0, $data);			#schonmal in den Internals ablegen lassen (damit wärend Initialisierung mit korrekten daten gearbeitet wird... bei Frequenz z.B.)
			$msg = I2C_PCA9685_i2cwrite($hash, 0 , $data);
		}
	} elsif ($attr && $attr =~ m/^modereg2$/i) {						#Mode register 2
		my @inp = split(/,/, $val) if defined($val);
		my $data = 0;
		foreach (@inp) {
			return "wrong value: $_ for \"attr $name $attr\" use comma separated list of " . join(',', (sort { $mr2{ $a } <=> $mr2{ $b } } keys %setsP) )
				unless(exists($mr2{$_}));
			$data += $mr2{$_};
		}
		Log3 $hash, 5, $hash->{NAME} . ": $attr alter Wert: ".(defined($hash->{confregs}{$confregs{1}})?$hash->{confregs}{$confregs{1}}:"")." neuer Wert: ".$data;
		$msg = I2C_PCA9685_i2cwrite($hash, 1, $data) if $main::init_done && $data != $hash->{confregs}{$confregs{1}};
	} elsif ($attr && $attr eq "OnStartup") {
		if (defined $val) {
			foreach (split (/,/,$val)) {
				my @pair = split (/=/,$_);
				$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <port>=on|off|0..4095|last where <port> = 0 - 15 " 
					unless ( scalar(@pair) == 2 &&
									(($pair[0] =~ m/(^[0-9]|1[0-5])$/i && 
									( $pair[1] eq "last" || exists($setsP{$pair[1]}) || 
									( $pair[1] =~ m/^\d+$/ && $pair[1] < 4095 ) ) ) )
									);		
			}
		}
	} elsif ($attr && $attr eq "extClock") {
		$val = defined($val) ? $val : 25;
		return "wrong value: $val for \"set $name $attr\" use point number"
			unless($val =~ m/^[1-9][0-9]*\.?[0-9]*$/);
		I2C_PCA9685_i2cread($hash, 254, 1);		# Frequenz fuer Internal neu auslesen und berechnen
	}
	return ($msg) ? $msg : undef; 
}
#############################################################################
sub I2C_PCA9685_Set($@) {													#
	my ($hash, $name, @rest) = @_;
    
	my $dimstep = AttrVal($name, "dimstep", "1");
	my $dimcount = AttrVal($name, "dimcount", "4095");
	my $msg;
	my $str = join(' ',@rest);
	#Log3 undef, 5, "$name: empfangen: $str";
	if ($str && $str =~ m/^(P(ort|)((0|)[0-9]|1[0-5]))/i && index($str, ',') == -1) {											# Nur ein Port
		my ($port, $dim, $delay) = split(' ', $str);
		$port =~ tr/(P|p)(ort|)//d;
		#Log3 undef, 5, "$name: ein Port: $port, $dim, $delay";
		($msg, my $data, my $reg) = I2C_PCA9685_CalcRegs($hash, $port, $dim, $delay);	# Registerinhalte berechnen
		$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data) unless($msg);				# Rausschicken
	# } elsif ($str && $str =~ m/^(P(ort|)((0|)[0-9]|1[0-5]))( *, *(P(ort|)((0|)[0-9]|1[0-5]))){1,} +\d+( +\d*)?/i ) { # Format P[ort]x,P[ort]y[,P..] Dimwert[ Delay]
	} elsif ($str && $str =~ m/^(P(ort|)((0|)[0-9]|1[0-5]))( *, *(P(ort|)((0|)[0-9]|1[0-5]))){1,}/i ) { 				# Format P[ort]x,P[ort]y[,P..] Dimwert[ Delay]
		Log3 undef, 5, "mehrere ports und ein wert";
		$str =~ tr/(P|p)(ort|)//d;
		my @einzel = split(',', $str);
		my @port;
		my (undef, $dim, $delay) = split(' ', $einzel[$#einzel]);
		for my $i (0..$#einzel){
			($port[$i]) = split(' ', $einzel[$i]);
		}
		my ($data, $reg) = undef;
		my $j = 1;
		for my $i (0..$#einzel){
			($msg, my $tdata, my $treg) = I2C_PCA9685_CalcRegs($hash, $port[$i], $dim, ( defined($delay) ? $delay : undef ) );		# Registerinhalte berechnen
			return $msg if defined($msg);
			Log3 $hash, 5, "$name: Port: $port[$i], Reg: $treg, Inhalt: $tdata, Rohwerte: $einzel[$i], Dimwert: $dim, Delay: ". ( defined($delay) ? ( $delay = "" ? "leer" : $delay ) : "leer" );
			if ( defined($data) && defined($reg) ) {	# bereits Werte für Ports vorhanden
				$j += 1;
				$data .= " " . $tdata;
			} else {
				$data = $tdata;
				$reg = $treg;
			}
			unless ( $j < (int( (defined($hash->{I2C_Buff})?$hash->{I2C_Buff}:30) / 4)) && $i < $#einzel && ($port[$i] + 1) == $port[$i+1]){	#wenn der naechste Port nicht der direkt Nachfolgende ist oder mehr als 8 Ports (32Bytes)
				$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data);		# Rausschicken
				($data, $reg) = undef;
				$j = 1;
			} 
		}
	} elsif ($str && $str =~ m/^(P(ort|)((0|)[0-9]|1[0-5]))( ){1,3}\d*(( ){1,3}\d*)?(( ){0,3},( ){0,3}(P(ort|)((0|)[0-9]|1[0-5]))( ){1,3}\d*(( ){1,3}\d*)?){1,}( ){0,3}$/i ) { # Mehrere Ports auf versch. Werte setzen
		Log3 undef, 5, "mehrere ports und unterschiedliche Werte";
		$str =~ tr/(P|p)(ort|)//d;
		my @einzel = split(',', $str);
		my (@port, @dim, @delay);
		#@einzel = sort { $a <=> $b } @einzel;
		for my $i (0..$#einzel){
			($port[$i], $dim[$i], $delay[$i]) = split(' ', $einzel[$i]);
		}
		my ($data, $reg) = undef;
		my $j = 1;
		for my $i (0..$#einzel){
			($msg, my $tdata, my $treg) = I2C_PCA9685_CalcRegs($hash, $port[$i], $dim[$i], ( defined($delay[$i]) ? $delay[$i] : undef ) );		# Registerinhalte berechnen
			return $msg if defined($msg);
			Log3 $hash, 5, "$name: Port: $port[$i], Reg: $treg, Inhalt: $tdata, Rohwerte: $einzel[$i], Dimwert: $dim[$i], Delay: ". ( defined($delay[$i]) ? ( $delay[$i] =~ m/ */ ? "leer" : $delay[$i] ) : "leer" );
			if ( defined($data) && defined($reg) ) {	# bereits Werte für Ports vorhanden
				$j += 1;
				$data .= " " . $tdata;
			} else {
				$data = $tdata;
				$reg = $treg;
			}
			unless ( $j < int( (defined($hash->{I2C_Buff})?$hash->{I2C_Buff}:30) / 4) && $i < $#einzel && ($port[$i] + 1) == $port[$i+1]){	#wenn der naechste Port nicht der direkt Nachfolgende ist oder mehr als 8 Ports (32Bytes)
				$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data);		# Rausschicken
				($data, $reg) = undef;
				$j = 1;
				
			} 
		}
	} elsif ($str =~ m/(a(ll|)( ){0,3}((\d{1,4})|on|off)(( ){0,3}\d{1,4})?)( ){0,3}$/i) {									# Alle Ports gleichzeitig
		my ($port, $dim, $delay) = split(' ', $str);
		$port = 61;											# Portnummer auf 61 für All setzen (All Startreg ist 250)
		Log3 undef, 5, "$name: alle Ports: $port, $dim" . (defined $delay ? ", $delay" : "" );	
		my ($msg, $data, $reg) = I2C_PCA9685_CalcRegs($hash, $port, $dim, $delay);	# Registerinhalte berechnen
		$msg = I2C_PCA9685_i2cwrite($hash,$reg, $data) unless($msg);				# Rausschicken
	} else {
		my $list = undef;
		foreach (0..15) {
			$list .= "Port" . sprintf ('%02d', $_) . ":slider,0,$dimstep,$dimcount ";
		}
		$list .= "all:slider,0,$dimstep,$dimcount";
		$msg = "Unknown argument $str, choose one of " . $list;
	}
	return (defined($msg) ? $msg : undef);
}
#############################################################################
sub I2C_PCA9685_CalcRegs($$$$) {											# Registerinhalte berechnen
	my ($hash, $port, $dim, $del) = @_;
	my $name = $hash->{NAME};
	#$port =~ tr/P(ort|)//d;										#Nummer aus Port extrahieren
	my $dimcount = AttrVal($hash->{NAME}, "dimcount", "4095");
	my $data;
	my $msg = undef;
	if (defined($dim) && $dim eq "on") {
		$data = "0 16 0 0";
	} elsif (defined($dim) && $dim eq "off") {
		$data = "0 0 0 16";
	} elsif (defined($dim) && $dim =~ m/^\d+$/ && $dim >= 0 && $dim <= $dimcount) {
		my $delaytime = 0;
		if ($dimcount < 4095) {				#DimmWert anpassen bei anderem Faktor
			$dim = int($dim * 4095 / $dimcount);
		}
		if (defined $del) {					#Delaytime angegeben?
			$msg = "wrong delay value: \"$del\" for \"$name Port$port $dim\" use value between 0 and $dimcount"
				unless ($del  =~ m/^\d+$/ && $del >= 0 && $del <= $dimcount);
			if ($dimcount < 4095) {			#DelayWert anpassen bei anderem Faktor
				$del = int($del * 4095 / $dimcount);
			}
			$delaytime = $del
		} else {							#...wenn nicht aus Reading holen (für all kommt immer 0 raus)
			$delaytime = ReadingsVal($name,'Port_d'.sprintf ('%02d', $port),"0");
		}
		unless($msg) {			# nur berechnen wenn es keine Fehlermeldung gibt
			my $LEDx_OFF = $delaytime + $dim - (( $dim + $delaytime < 4096 ) ? 0 : 4096);
			if ($LEDx_OFF == $delaytime) { 		#beide Register dürfen nicht gleichen Inhalt haben, das entpricht "aus"
				$data = "0 0 0 16";
			} else {
				my @LEDx = unpack("C*", pack("S", $delaytime));
				push @LEDx, unpack("C*", pack("S", $LEDx_OFF));		#Array $LEDx[0] = LEDx_ON_L, $LEDx[1] = LEDx_ON_H, $LEDx[2] = LEDx_OFF_L, $LEDx[3] = LEDx_OFF_H
				# $data = sprintf "%01d " x 4, @LEDx;
				$data = sprintf "%01d %01d %01d %01d", @LEDx;
		}
			}
	} else {
		$msg = "wrong dimvalue: \"".(defined($dim)?$dim:"...")."\" for \"$name Port$port\" use one of: " . 
			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " 0..$dimcount";
	}
	my $reg = 6 + 4 * $port if defined $port;							# Nummer des entspechenden LEDx_ON_L Registers (LED0_ON_L = 0x06) jede LED hat 4 Register
	return $msg, $data, $reg;
}
#############################################################################
sub I2C_PCA9685_Get($@) {													# Portwerte bei laden der Datailseite aktualisieren
	my ($hash, @a) = @_;
	unless ($hash->{IODev}->{TYPE} eq 'RPII2C') { #fuer FRM, etc. Register zurücklesen (bei RPII2C kommt bei erfolgreicher Uebertragung die Botschaft zurueck)
		my $reg = int( (defined($hash->{I2C_Buff})?$hash->{I2C_Buff}:30) / 4) * 4;	# Anzahl moegliche 4er Registergruppen pro Lesevorgang
		my $n   = int(64 / $reg);			# Anzahl Lesevorgänge (abgerundet)
		foreach (0 .. ($n-1)) {
			I2C_PCA9685_i2cread($hash, 6 + $_  * $reg, $reg);
		}
		I2C_PCA9685_i2cread($hash, 6 + $n * $reg, $reg - ($reg * ($n+1) - 64)) if (($n+1) * $reg) > 64;

	} else {
		I2C_PCA9685_i2cread($hash, 0x6, 64);
	}
	return;
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
	my ($hash, $reg, $data) = @_;
	if (defined (my $iodev = $hash->{IODev})) {
		Log3 $hash, 5, "$hash->{NAME}: $hash->{I2C_Address} write " . $data . " to Register $reg";
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
		direction  	=> "i2cwrite",
		i2caddress 	=> $hash->{I2C_Address},
		reg 		=> $reg,
		data 		=> $data,
		});
		unless ($hash->{IODev}->{TYPE} eq 'RPII2C') { #fuer FRM, etc. Register zurücklesen (bei RPII2C kommt bei erfolgreicher Uebertragung die Botschaft zurueck)
			my $nbyte = () = $data =~ / /gi;
			unless ($reg == 250) {
				I2C_PCA9685_i2cread($hash, $reg, $nbyte + 1);
			} else {
				#I2C_PCA9685_UpdReadings($hash, $reg, $data);
				my $reg = int( (defined($hash->{I2C_Buff})?$hash->{I2C_Buff}:30) / 4) * 4;	# Anzahl moegliche 4er Registergruppen pro Lesevorgang
				my $n   = int(64 / $reg);			# Anzahl Lesevorgänge (abgerundet)
				foreach (0 .. ($n-1)) {
					I2C_PCA9685_i2cread($hash, 6 + $_  * $reg, $reg);
				}
				I2C_PCA9685_i2cread($hash, 6 + $n * $reg, $reg - ($reg * ($n+1) - 64)) if (($n+1) * $reg) > 64;
			}
		}
		return undef;
	} else {
		if (AttrVal($hash->{NAME}, "dummy", 0) == 1) {
			I2C_PCA9685_UpdReadings($hash, $reg, $data);		# Zeile zum testen (Werte werden direkt zu I2CRec umgeleitet)
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}
	}
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
		} elsif ( $clientmsg->{direction} eq "i2cwrite" && defined($clientmsg->{data}) ) { 			#readings aktualisieren wenn uebertragung ok (bei FRM kommt nix zurueck)
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
	Log3 $hash, 5, "$name Received from Register $reg: $inh";  #sprintf("0x%.2X", $reg)
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
		Log3 $hash, 5, "$name: lese einen Port - Reg: $reg, Inh: @reginh";
	
	} elsif ( $reg < 70 && $reg > 5 && @reginh > 4 ) {					#Wenn mehrere Ports abgefragt werden
		for (my $i = 0; $i < @reginh; $i++) {
			next unless ( ($reg + $i - 2) / 4  =~ m/^\d+$/ && defined($reginh[$i + 3]) );
			my @regpart = ( $reginh[$i], $reginh[$i + 1], $reginh[$i + 2], $reginh[$i + 3] );
			my $port = sprintf ('%02d', ($reg + $i - 6) / 4);
			($dimval, $delay) = I2C_PCA9685_CalcVal($dimcount, @regpart);
			readingsBulkUpdate($hash, 'Port'.$port , $dimval) if (ReadingsVal($name, 'Port'.$port, "failure") ne $dimval); #nur wenn Wert geaendert
			readingsBulkUpdate($hash, 'Port_d'.$port , $delay) if (defined $delay && ReadingsVal($name, 'Port_d'.$port, "failure") ne $delay); #nur wenn Wert geaendert
			Log3 $hash, 5, "$name: lese mehrere Ports - Reg: $reg, i: $i; Inh: @regpart";
			$i += 3;
		}
	} elsif ($reg == 254) { 											#wenn Frequenz Register
		my $clock = AttrVal($name, "extClock", 25);
		my $init = 1 unless defined($hash->{Frequency});
		$hash->{confregs}{PRESCALE} = $inh;
		$hash->{Frequency} = sprintf( "%.1f", $clock * 1000000 / (4096 * ($inh + 1)) ) . " Hz";
		I2C_PCA9685_Init2($hash) if defined($init);
	} elsif ( $reg >= 0 && $reg < 6 ) {									#Konfigurations Register
		$hash->{confregs}{$confregs{$reg}} = $inh;
	}
	readingsEndUpdate($hash, 1);
	return;
}
#############################################################################

1;

=pod
=item device
=item summary controls PWM outputs from an via I2C connected PCA9685
=item summary_DE steuern der PWM Ausg&aumlnge eines &uuml;ber I2C angeschlossenen PCA9685
=begin html

<a name="I2C_PCA9685"></a>
<h3>I2C_PCA9685</h3>
<ul>
	<a name="I2C_PCA9685"></a>
		Provides an interface to the PCA9685 I2C 16 channel PWM IC. 
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_PCA9685Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9685 &lt;I2C Address&gt; [&lt;I2C Buffer Size&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
		For example 0x40 (hexadecimal) = 64 (decimal). An I2C address are 7 MSB, the LSB is the R/W bit.<br>
		<code>&lt;I2C Buffer Size&gt;</code> sets the maximum size of the I2C-Packet. 
		Without this option the packet size is 30 Bytes (32 incl. Address and Register number). 
		For RPII2C this option has no influence, cause it can deal with arbitrary packet sizes.<br>
	</ul>

	<a name="I2C_PCA9685Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;dimvalue&gt; [&lt;delay&gt;]</code><br><br>
			<li>where <code>&lt;port&gt;</code> is one of Port0 to Port15<br>
			and <code>&lt;dimvalue&gt;</code> one of<br>
			<ul>
			<code>
				off<br>
				on<br>
				0..4095<br>
			</code>
			</ul>
			<code>&lt;delay&gt;</code> defines the switch on time inside the PWM counting loop. It does not have an influence to the duty cycle. 
			Default value is 0 and, possible values are 0..4095<br>	
			</li><br>
			<li>
			It is also possible to change more than one port at the same time. Just separate them by comma. 
			If only the last of the comma separated ports has dimvalue (and delay), all ports will set to the same values. 
			Sequently ports will set at once (useful for multi color LED's).<br>
			Also P instead of Port is Possible. 
			</li><br>
		
		<br>
		Examples:
		<ul>
			<code>set mod1 Port04 543</code><br>
			<code>set mod1 Port4 434 765</code><br>
			<code>set mod1 Port1, Port14 434 765</code><br>
			<code>set mod1 Port1 on, P14 434 765</code><br>
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
		<li>SUBADR1,SUBADR2,SUBADR3,ALLCALLADR<br>
			Alternative slave addresses, if you want to control more than one PCA9685 with one define 
			Respective flag in modereg1 must be set as well<br>
			Default: SUBADR1=113,SUBADR2=114,SUBADR3=116,ALLCALLADR=112, valid values: valid I2C Address <br><br>
		</li>
		<li><a name="OnStartup">OnStartup</a><br>
			Comma separated list of output ports/PWM registers and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Default: -, valid values: &lt;port&gt;=on|off|0..4095|last where &lt;port&gt; = 0 - 15<br><br>
		</li>
		<li><a name="prescale">prescale</a><br>
			Sets PWM Frequency. The Formula is: Fx = 25MHz/(4096 * (prescale + 1)). 
			The corresponding frequency value is shown under internals. 
			If provided, attribute extClock will be used for frequency calculation. Otherwise 25MHz<br>
			Default: 30 (200Hz for 25MHz clock), valid values: 0-255<br><br>
		</li>
		<li><a name="modereg1">modereg1</a><br>
			Comma separated list of:
			<ul>
				<li>EXTCLK<br>
					If set the an external connected clock will be used instead of the internal 25MHz oscillator.
					Use the attribute extClock to provide the external oscillater value.
				</li>
				<li>SUBADR1<br>
					If set the PCA9685 responds to I2C-bus SUBADR 1.
				</li>
				<li>SUBADR2<br>
					If set the PCA9685 responds to I2C-bus SUBADR 2.
				</li>
				<li>SUBADR3<br>
					If set the PCA9685 responds to I2C-bus SUBADR 3.
				</li>
				<li>ALLCALLADR<br>
					If set the PCA9685 responds to I2C-bus ALLCALLADR address.
				</li>
			</ul>
		</li>
		<li><a name="modereg2">modereg2</a><br>
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
<ul>
	<a name="I2C_PCA9685"></a>
		Erm&ouml;glicht die Verwendung eines PCA9685 I2C 16 Kanal PWM IC. 
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_PCA9685Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9685 &lt;I2C Address&gt; [&lt;I2C Buffer Size&gt;]</code><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Beispielsweise 0x40 (hexadezimal) = 64 (dezimal). Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
		<code>&lt;I2C Buffer Size&gt;</code> gibt die maximale Anzahl von Datenbytes pro I2C Datenpaket an. Nicht angegeben, wird der Wert 30 verwendet 
		( entspricht 32 Bytes incl. Adresse und Registernummer). RPII2C kann mit beliebig gro&szlig;en Paketl&auml;ngen umgehen, daher ist diese Option dort inaktiv.<br>
	</ul>

	<a name="I2C_PCA9685Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;dimvalue&gt; [&lt;delay&gt;]</code><br><br>
			<li>Als <code>&lt;port&gt;</code> kann Port00 bis Port15 verwendet werden<br>
			<code>&lt;dimvalue&gt;</code> kann folgende Werte annehmen:<br>
			<ul>
			<code>
				off<br>
				on<br>
				0..4095<br>
			</code>
			</ul>
			<code>&lt;delay&gt;</code> gibt den Wert innerhalb der Z&auml;hlschleife an, an dem der Ausgang eingeschaltet wird. 
			Damit lassen sich die 16 Ausg&auml;nge zu unterschiedlichen Zeiten einschalten um Stromspitzen zu minimieren.
			Dieser Wert hat keinerlei Einfluss auf die Pulsbreite. Stardartwert ist 0, m&ouml;gliche Werte sind 0..4095<br>	
			</li>
			<li>
			Um mehrer Ports mit einem Befehl zu &auml;ndern k&ouml;nnen mehrere Befehle per Komma getrennt eingegeben werden. 
			Dabei kann jeder Port auf einen separaten, oder alle Ports auf den selben Wert gesettz werden. 
			F&auml;r letzteres darf nur der letzte Befehl dimvalue (und delay) enthalten. 
			Aufeinanerfolgene Ports werden mit einem Befehl geschrieben. So k&ouml;nnen beispielsweise multicolor LED's ohne flackern geschaltet werden.<br>
			Anstelle von Port kann auch einfach ein P verwendet werden.
			</li>

		<br>
		Examples:
		<ul>
			<code>set mod1 Port04 543</code><br>
			<code>set mod1 Port4 434 765</code><br>
			<code>set mod1 Port1, Port2, Port14 434 765</code><br>
			<code>set mod1 Port1 on, P14 434 765</code><br>
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
		<li>SUBADR1,SUBADR2,SUBADR3,ALLCALLADR<br>
			Alternative slave Adressen, zum kontrollieren mehrerer PCA9685 mit einem define 
			Zus&auml;tzlich zu diesen Registern m&uuml;ssen die Passenden Bits in modereg1 gesetzt werden.<br>
			Standard: SUBADR1=113,SUBADR2=114,SUBADR3=116,ALLCALLADR=112, g&uuml;ltige Werte: I2C Adresse <br><br>
		</li>
		<li><a name="OnStartup">OnStartup</a><br>
			Kommagetrennte Liste der Ports mit den gew&uuml;nschten Startwerten.<br>
			Nicht gelistete Ports werden auf en letzte state wiederhergestellt.<br>
			Standard: last, g&uuml;ltige Werte: &lt;port&gt;=on|off|0..4095|last wobei &lt;port&gt; = 0 - 15<br><br>
		</li>
		<li><a name="prescale">prescale</a><br>
			PWM Frequenz setzen. Formel: Fx = 25MHz/(4096 * (prescale + 1)).
			Die eingestellte Frequenz wird in den Internals angezeigt.
			Wenn das Attribut extclock angegeben ist, wird dieses zur Frequenzberechnung verwendet. Andernfalls 25MHz.<br>
			Standard: 30 (200Hz f&uuml;r 25MHz clock), g&uuml;ltige Werte: 0-255<br><br>
		</li>
		<li><a name="modereg1">modereg1</a><br>
			Durch Komma getrennte Liste von:
			<ul>
				<li>EXTCLK<br>
					Anstelle des internen 25MHz Oszillators wird ein extern Angeschlossener verwendet.
					Die Frequenz des externen Oszillators kann &uuml;ber das Attribut extclock angegeben werden.
				</li>
				<li>SUBADR1<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 1.
				</li>
				<li>SUBADR2<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 2.
				</li>
				<li>SUBADR3<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus Subadresse 3.
				</li>
				<li>ALLCALLADR<br>
					Wenn gesetzt, antwortet der PCA9685 auf I2C-bus ALLCALLADR Adresse.
				</li>
			</ul>
		</li>
		<li><a name="modereg2">modereg2</a><br>
			Durch Komma getrennte Liste von:
			<ul>
				<li>INVRT<br>
					Wenn gesetzt, werden die Ausg&auml;nge invertiert.<br>
				</li>
				<li>OCH<br>
					Wenn gesetzt, werden die Ports nach jedem ACK gesetzt (also nach jedem gesendeten Byte).<br>
					Andernfalls werden sie nach einem STOP Kommando gesetzt (Bus Schreibaktion fertig, also nach einem Datenpaket)<br>
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
