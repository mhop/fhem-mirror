##############################################################################
# $Id$
##############################################################################
# Modul for I2C GPIO Extender MCP23008
#
# contributed by Klaus Wittstock (2014) email: klauswittstock bei gmail
##############################################################################

package main;
use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

my %Registers = (
	'IODIRA'   => 0x00,		#1 = input; 0 = output (default 1)
	'IODIRB'   => 0x00,
	'IPOLA'    => 0x01,		#1 inverts logic (default 0)
	'IPOLB'    => 0x01,
	'GPINTENA' => 0x02,		#1 enables the pin for interrupt-on-change (default 0)
	'GPINTENB' => 0x02,
	'DEFVALA'  => 0x03,		#The default comparison value for interrupt (opposite value will caues an interrupt) (default 0)
	'DEFVALB'  => 0x03,
	'INTCONA'  => 0x04,		#If a bit is set, the corresponding I/O pin is compared against DEFVAL register. Otherwise against the previous value.
	'INTCONB'  => 0x04,
	'IOCON'    => 0x05,
	'GPPUA'    => 0x06,		#100k pull up resistor for input
	'GPPUB'    => 0x06,
	'INTFA'    => 0x07,		#shows which Pin caused the interrupt (ro)
	'INTFB'    => 0x07,
	'INTCAPA'  => 0x08,		#status from all registers at the time the interrupt occured, remain unchanged until a read of INTCAP or GPIO. (ro)
	'INTCAPB'  => 0x08,
	'GPIOA'    => 0x09,		#value on the ports (r/w)
	'GPIOB'    => 0x09,
	'OLATA'    => 0x0A,
	'OLATB'    => 0x0A,
);

my %setsP = (
'off' => 0,
'on' => 1,
); 

my %intout = (
'separate_active-low'   => 0x00,
'separate_active-high'  => 0x02,
'separate_open-drain'   => 0x04,
);
###############################################################################
sub I2C_MCP23008_Initialize($) {
	my ($hash) = @_;
	$hash->{DefFn}    = "I2C_MCP23008_Define";
	$hash->{InitFn}   = 'I2C_MCP23008_Init';
	$hash->{UndefFn}  = "I2C_MCP23008_Undefine";
	$hash->{AttrFn}   = "I2C_MCP23008_Attr";
	$hash->{StateFn}  = "I2C_MCP23008_State"; 
	$hash->{SetFn}    = "I2C_MCP23008_Set";
	$hash->{GetFn}    = "I2C_MCP23008_Get";
	$hash->{I2CRecFn} = "I2C_MCP23008_I2CRec";
	$hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
                      "poll_interval OnStartup ".
                      "OutputPorts:multiple-strict,A0,A1,A2,A3,A4,A5,A6,A7 ".
                      "Pullup:multiple-strict,A0,A1,A2,A3,A4,A5,A6,A7 ".
                      "invert_input:multiple-strict,A0,A1,A2,A3,A4,A5,A6,A7 ".
                      "Interrupt:multiple-strict,A0,A1,A2,A3,A4,A5,A6,A7 ".
                      "InterruptOut:separate_active-low,separate_active-high,separate_open-drain ".
                      "$readingFnAttributes";
}
###############################################################################
sub I2C_MCP23008_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
	if ($main::init_done) {
		eval { I2C_MCP23008_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_MCP23008_Catch($@) if $@;
	}
	return undef;
}
###############################################################################
sub I2C_MCP23008_Init($$) {																										#Geraet beim anlegen/booten/nach Neuverbindung (wieder) initialisieren
 my ( $hash, $args ) = @_;
 if (defined $args && int(@$args) != 1) {
	return "Define: Wrong syntax. Usage:\n" .
				 "define <name> I2C_MCP23008 <i2caddress>";
 }
	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
 } else {
		return "$hash->{NAME} I2C Address not valid";
 }
 AssignIoPort($hash);
 my $msg = '';
	#Output level wieder setzen
	my $sbyte = 0;
	foreach (reverse 0..7) {
		$sbyte += $setsP{ReadingsVal($hash->{NAME},"PortA".$_,"off")} << ($_);		#Werte fuer PortA aus dem Reading holen
		#$sbyte += $setsP{ReadingsVal($hash->{NAME},"PortB".$_,"off")} << (8 + $_);
	}
	$msg = I2C_MCP23008_SetRegPair($hash, $sbyte, "GPIO") if $sbyte;
	#bei Init IC neu konfigurieren
	if ( defined ( my $val = AttrVal($hash->{NAME},"invert_input",undef)) ) {
		($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, "invert_input", $val);
		$msg = I2C_MCP23008_SetRegPair($hash, $regval, "IPOL") unless $msg;
	}
	if ( defined ( my $val = AttrVal($hash->{NAME},"OutputPorts",undef)) ) {
		($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, "OutputPorts", $val);
		$msg = I2C_MCP23008_SetRegPair($hash, ~$regval, "IODIR") unless $msg;
	}
	if ( defined ( my $val = AttrVal($hash->{NAME},"Pullup",undef)) ) {
		($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, "Pullup", $val);
		$msg = I2C_MCP23008_SetRegPair($hash, $regval, "GPPU") unless $msg;
	}
	if ( defined ( my $val = AttrVal($hash->{NAME},"Interrupt",undef)) ) {
		($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, "Interrupt", $val);
		$msg = I2C_MCP23008_SetRegPair($hash, $regval, "GPINTEN") unless $msg;
	}
	if ( defined ( my $val = AttrVal($hash->{NAME},"InterruptOut",undef)) ) {
		my $regval = 0;
		$regval = $intout{$val} if defined $val;
		if (defined (my $iodev = $hash->{IODev})) {
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  => "i2cwrite",
				i2caddress => $hash->{I2C_Address},
				reg => 				$Registers{IOCON},
				data => 			$regval,
				}) if (defined $hash->{I2C_Address});
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}
		
	}
    #Output level wieder setzen die zweite
	#$sbyte = 0;
	#foreach (reverse 0..7) {
	#	$sbyte += $setsP{ReadingsVal($hash->{NAME},"PortA".$_,"off")} << ($_);		#Werte fuer PortA aus dem Reading holen
	#	$sbyte += $setsP{ReadingsVal($hash->{NAME},"PortB".$_,"off")} << (8 + $_);
	#}
	#$msg = I2C_MCP23008_SetRegPair($hash, $sbyte, "GPIO") if $sbyte;
    I2C_MCP23008_Get($hash, $hash->{NAME});
 $hash->{STATE} = 'Initialized';
 return ($msg) ? $msg : undef;
}
###############################################################################
sub I2C_MCP23008_Catch($) {																										#Fehlermeldung von eval formattieren
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}
###############################################################################
sub I2C_MCP23008_Undefine($$) {
	my ($hash, $arg) = @_;
	if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
		RemoveInternalTimer($hash);
	}
}
###############################################################################
sub I2C_MCP23008_Attr(@) {
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 if ($command && $command eq "set" && $attr && $attr eq "IODev") {
	if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
		main::AssignIoPort($hash,$val);
		my @def = split (' ',$hash->{DEF});
		I2C_MCP23008_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
 }
 if ($attr && $attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		if (!defined($val) ) {
			RemoveInternalTimer($hash);
		} elsif ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_MCP23008_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		} 
 } elsif ($attr && $attr eq "OutputPorts") {
	($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23008_SetRegPair($hash, ~$regval, "IODIR") unless $msg;
	
 } elsif ($attr && $attr eq "Pullup") {
	($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23008_SetRegPair($hash, $regval, "GPPU") unless $msg;
	
 } elsif ($attr && $attr eq "invert_input") {
	($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23008_SetRegPair($hash, $regval, "IPOL") unless $msg;
	
 } elsif ($attr && $attr eq "Interrupt") {
	($msg, my $regval) = I2C_MCP23008_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23008_SetRegPair($hash, $regval, "GPINTEN") unless $msg;
	
 } elsif ($attr && $attr eq "OnStartup") {
	if (defined $val) {
		foreach (split (/,/,$val)) {
			my @pair = split (/=/,$_);
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <port>=on|off|last where <port> = A0 - A7" 
				unless ( scalar(@pair) == 2 &&
								$pair[0] =~ m/^(A)(0|)[0-7]$/i &&
								$pair[1] =~ m/^(on|off|last)$/i);		
		}
	}
 } elsif ($attr && $attr eq "InterruptOut") {
		my $regval = 0;
		if (defined $val) {
			return "wrong value: $_ for \"attr $hash->{NAME} $attr\" use one of: " .
			join(',', (sort { $intout{ $a } <=> $intout{ $b } } keys %setsP) )
			unless(exists($intout{$val}));
			$regval = $intout{$val};
		} 
		if (defined (my $iodev = $hash->{IODev})) {
			#Log3 $hash, 1, "schreibe raus: i2cwrite|$hash->{I2C_Address}|$Registers{$regtype . $reg}|$port{$reg}|";
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  => "i2cwrite",
				i2caddress => $hash->{I2C_Address},
				reg => 				$Registers{IOCON},
				data => 			$regval,
				}) if (defined $hash->{I2C_Address});
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}
 }
 return ($msg) ? $msg : undef;
}
###############################################################################
sub I2C_MCP23008_State($$$$) {																								#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ($sname =~ m/^Port(A)(0|)[0-7]$/i) {
		my $po = substr $sname, 4, 2;			# Ax oder Bx
		Log3 $hash, 5, "$hash->{NAME}: Port = $po";
		if ( index( AttrVal($hash->{NAME}, "OutputPorts", ""), $po, 0) >= 0 ) {
			if ( ( my $pos = index(AttrVal($hash->{NAME},"OnStartup", ""), $po ,0) ) >=0 ) {
				my $val = substr AttrVal($hash->{NAME},"OnStartup",undef), $pos + 3, 2;
				if ( $val eq "on" ) {
					Log3 $hash, 5, "$hash->{NAME}: $sname soll auf on gesetzt werden";
					readingsSingleUpdate($hash,$sname, "on", 1);
				} elsif ( $val eq "of" ) {
					Log3 $hash, 5, "$hash->{NAME}: $sname soll auf off gesetzt werden";
					readingsSingleUpdate($hash,$sname, "off", 1);
				} else {
					Log3 $hash, 5, "$hash->{NAME}: $sname soll auf Altzustand: $sval gesetzt werden";
					$hash->{READINGS}{$sname}{VAL} = $sval;
					$hash->{READINGS}{$sname}{TIME} = $tim;
					}
			} else {
				Log3 $hash, 5, "$hash->{NAME}: $sname wird auf Altzustand: $sval gesetzt (kein Eintrag in on Startup)";
				$hash->{READINGS}{$sname}{VAL} = $sval;
				$hash->{READINGS}{$sname}{TIME} = $tim;
			}
		} else {
			Log3 $hash, 5, "$hash->{NAME}: $sname ist Eingang";
		}
	}
	return undef;
}
###############################################################################
sub I2C_MCP23008_CheckAttr {
	my ($hash, $attr, $val) = @_;
	my $msg = undef;
	my ($regval) = 0;
	if (defined $val) {
		foreach (split (/,/,$val)) {
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated values from A0 - A7" unless ($_ =~ m/^(A)(0|)[0-7]$/i);		
			#my $bank = ($_ =~ m/^A/) ? 0 : 8;	# A oder B
			$_ =~ tr/[a-zA-Z]//d;				#Nummer aus String extrahieren
			#$regval |= 1 << ($_ + $bank);
			$regval |= 1 << $_;
		}
	}
	return $msg, $regval;
}
###############################################################################
sub I2C_MCP23008_SetRegPair {																									#set register pair for PortA/B
	my ($hash, $regval, $regtype) = @_;
	my %port = ();
	$port{A} = $regval & 0xff;
	#$port{B} = ( $regval >> 8 ) & 0xff;

	if (defined (my $iodev = $hash->{IODev})) {
		foreach my $reg (keys %port) {
			#Log3 $hash, 1, "schreibe raus: i2cwrite|$hash->{I2C_Address}|$Registers{$regtype . $reg}|$port{$reg}|";
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  	=> "i2cwrite",
				i2caddress 	=> $hash->{I2C_Address},
				reg 		=> $Registers{$regtype . $reg},
				data 		=> $port{$reg},
				}) if (defined $hash->{I2C_Address});
		}
		I2C_MCP23008_Get($hash,$hash->{NAME}) if ( ($iodev->{TYPE} ne "RPII2C") && ($regtype eq "GPIO") );
	} else {
		return "no IODev assigned to $hash->{NAME}";
	}
}
###############################################################################
sub I2C_MCP23008_Poll($) {																										#function for refresh intervall
	my ($hash) = @_;
	my $name = $hash->{NAME};
	# Read values
	I2C_MCP23008_Get($hash, $name);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_MCP23008_Poll', $hash, 0);
	}
} 
###############################################################################
sub I2C_MCP23008_Set($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];
	#my @outports = sort(split(/,/,AttrVal($name, "OutputPorts", "")));
	unless (@a == 3) {

	}
	my $msg = undef;
	if ( $cmd && $cmd =~ m/^P(ort|)(A)((0|)[0-7])(,(P|)(ort|)(A|B)((0|)[0-7])){0,7}$/i) {
		return "wrong value: $val for \"set $name $cmd\" use one of: " . 
			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) )
			unless(exists($setsP{$val}));
		my @scmd = split(",", $cmd);
		foreach (@scmd) {
			$_ =~ tr/P(ort|)//d;			#Nummer aus String extrahieren
			#$msg .= (defined $msg ? "," : "") . "Port" . $_ unless ( ($_) ~~ @outports );		#Pruefen ob entsprechender Port Input ist
			$msg .= (defined $msg ? "," : "") . "Port" . $_ unless ( AttrVal($name, "OutputPorts", "") =~ /$_/ );		#Pruefen ob entsprechender Port Input ist
		}
		return "$name error: $msg is defined as input" if $msg;
		#Log3 $hash, 1, "$name: multitest gereinigt: @scmd";
	
		my $regval = 0;
		foreach (reverse 0..7) {
			#foreach my $po ("A","B") {
			foreach my $po ("A") {
				my $bank = ($po eq "A") ? 0 : 8;	# A oder B
				#if ( ($po.$_) ~~ @scmd ) {				#->wenn aktueller Port in Liste dann neuer Wert
				if ( $cmd =~ /$po$_/ ) {				#->wenn aktueller Port in Liste dann neuer Wert
					$regval += $setsP{$val} << ($bank + $_);
				} else {													#->sonst aus dem Reading holen
					$regval += $setsP{ReadingsVal($name,"Port".$po.$_,"off")} << ($bank + $_);		
				}
			}
		}	
		#Log3 $hash, 1, "$name: endwert: $regval";
		$msg = I2C_MCP23008_SetRegPair($hash, $regval, "GPIO") unless $msg;
	} else {
		my $list = "";
		foreach (0..7) {
			#next unless ( ("A" . $_) ~~ @outports );		#Inputs ueberspringen
			next unless ( AttrVal($name, "OutputPorts", "") =~ /A$_/ );		#Inputs ueberspringen
			$list .= "PortA" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
		}
		#foreach (0..7) {
		#	next unless ( ("B" . $_) ~~ @outports );		#Inputs ueberspringen
		#	$list .= "PortB" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
		#}
		$msg = "Unknown argument $a[1], choose one of " . $list;
	}
	return ($msg) ? $msg : undef;
}
###############################################################################
sub I2C_MCP23008_Get($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];

	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
    $sendpackage{reg} = $Registers{GPIOA}; 																			#startadresse zum lesen
	$sendpackage{nbyte} = 1;
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	
}
###############################################################################
sub I2C_MCP23008_I2CRec($@) {																									#ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	} 
	#hier noch ueberpruefen, ob Register und Daten ok
	if ($clientmsg->{direction} && defined $clientmsg->{reg} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
		if ($clientmsg->{direction} eq "i2cread" && defined $clientmsg->{received}) { # =~ m/^[a-f0-9]{2}$/i) {
			#my @rec = @{$clientmsg->{received}};							#bei uebergabe im hash als array
			my @rec = split(" ",$clientmsg->{received});			#bei uebergabe im als skalar
			Log3 $hash, 3, "$name: wrong amount of registers transmitted from $pname" unless (@rec == $clientmsg->{nbyte});
			foreach (reverse 0..$#rec) {																							#reverse, damit Inputs (Register 0 und 1 als letztes geschrieben werden)
				I2C_MCP23008_UpdReadings($hash, $_ + $clientmsg->{reg} , $rec[$_]);
			}
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} elsif ($clientmsg->{direction} eq "i2cwrite" && defined $clientmsg->{data}) { # =~ m/^[a-f0-9]{2}$/i) {#readings aktualisieren wenn uebertragung ok
			I2C_MCP23008_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{data}) if ( ($clientmsg->{reg} == $Registers{GPIOA}) || ($clientmsg->{reg} == $Registers{GPIOB}) );
			readingsSingleUpdate($hash,"state", "Ok", 1);
		
		} else {
			readingsSingleUpdate($hash,"state", "transmission error", 1);
			Log3 $hash, 3, "$name: failurei in message from $pname";
			Log3 $hash, 3,	(defined($clientmsg->{direction}) ? 	"Direction: "		.				$clientmsg->{direction} 	: "Direction: undef").
							(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) 	: " I2Caddress: undef").
							(defined($clientmsg->{reg}) ? 			" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 			: " Register: undef").
							(defined($clientmsg->{data}) ? 			" Data: " 		. sprintf("0x%.2X", $clientmsg->{data}) 		: " Data: undef").
							(defined($clientmsg->{received}) ? 		" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		}
	} else {
		readingsSingleUpdate($hash,"state", "transmission error", 1);
		Log3 $hash, 3, "$name: failure in message from $pname";
			Log3 $hash, 3,(defined($clientmsg->{direction}) ? 	"Direction: "		.										$clientmsg->{direction} 	: "Direction: undef").
										(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) : " I2Caddress: undef").
										(defined($clientmsg->{reg}) ? 				" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 				: " Register: undef").
										(defined($clientmsg->{data}) ? 				" Data: " 			. sprintf("0x%.2X", $clientmsg->{data}) 			: " Data: undef").
										(defined($clientmsg->{received}) ? 		" received: " 	. sprintf("0x%.2X", $clientmsg->{received}) 	: " received: undef");
		#my $cmsg = undef;
		#foreach my $av (keys %{$clientmsg}) { $cmsg .= "|" . $av . ": " . $clientmsg->{$av}; }
		#Log3 $hash, 3, $cmsg;
		}
}
###############################################################################
sub I2C_MCP23008_UpdReadings($$$) {																						#nach Rueckmeldung readings updaten (ueber I2CRec aufgerufen)
	my ($hash, $reg, $inh) = @_;
	my $name = $hash->{NAME};
	#$inh = hex($inh);
	#$reg = hex($reg);
	Log3 $hash, 5, "$name UpdReadings Register: $reg, Inhalt: $inh";
	readingsBeginUpdate($hash);
	if ($reg == $Registers{GPIOA}) {
		my %rsetsP = reverse %setsP;
		foreach (0..7) {
				my $pval = 1 & ( $inh >> $_ );
				readingsBulkUpdate($hash, 'PortA'.$_ , $rsetsP{$pval}) 
					if (ReadingsVal($name, 'PortA'.$_,"nix") ne $rsetsP{$pval});  #nur wenn Wert geaendert
		}
	} #elsif ($reg == $Registers{GPIOB}) {
		#my %rsetsP = reverse %setsP;
		#foreach (0..7) {
		#		my $pval = 1 & ( $inh >> $_ );
		#		readingsBulkUpdate($hash, 'PortB'.$_ , $rsetsP{$pval}) 
		#			if (ReadingsVal($name, 'PortB'.$_,"nix") ne $rsetsP{$pval});  #nur wenn Wert geaendert
		#}
	#}
	
	readingsEndUpdate($hash, 1);
	return;
}
1;

=pod
=item device
=item summary controls/reads GPIOs from an via I2C connected MCP23008 port extender
=item summary_DE steuern/lesen der GPIOs eines &uuml;ber I2C angeschlossenen MCP23008
=begin html

<a name="I2C_MCP23008"></a>
<h3>I2C_MCP23008</h3>
(en | <a href="commandref_DE.html#I2C_MCP23008">de</a>)
<ul>
	<a name="I2C_MCP23008"></a>
		Provides an interface to the MCP23008 16 channel port extender IC. On Raspberry Pi the Interrupt Pin's can be connected to an GPIO and <a href="#RPI_GPIO">RPI_GPIO</a> can be used to get the port values if an interrupt occurs.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_MCP23008Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_MCP23008 &lt;I2C Address&gt;</code><br>
		<code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
		For example 0x40 (hexadecimal) = 64 (decimal). An I2C address are 7 MSB, the LSB is the R/W bit.<br>
	</ul>

	<a name="I2C_MCP23008Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
				where <code>&lt;port&gt;</code> is one of PortA0 to PortA7 and <code>&lt;value&gt;</code> is one of:<br>
				<ul>
				<code>
					off<br>
					on<br>
				</code>
				</ul>
		<br>
		Example:
		<ul>
			<code>set mod1 PortA4 on</code><br>
			<code>set mod1 PortA4,PortA6 off</code><br>
			<code>set mod1 PortA4,A6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_MCP23008Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>

	<a name="I2C_MCP23008Attr"></a>
	<b>Attributes</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Set the polling interval in minutes to query the GPIO's level<br>
			Default: -, valid values: decimal number<br><br>
		</li>
		<li><a name="OutputPorts">OutputPorts</a><br>
			Comma separated list of ports that are used as Output<br>
			Ports not in this list can't be written<br>
			Default: no, valid values: A0-A7<br><br>
		</li>
		<li><a name="OnStartup">OnStartup</a><br>
			Comma separated list of output ports and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Default: -, valid values: &lt;port&gt;=on|off|last where &lt;port&gt; = A0-A7<br><br>
		</li>
		<li><a name="Pullup">Pullup</a><br>
			Comma separated list of input ports which switch on their internal 100k pullup<br>
			Default: -, valid values: A0-A7<br><br>
		</li>
		<li><a name="Interrupt">Interrupt</a><br>
			Comma separated list of input ports which will trigger the IntA/B pin<br>
			Default: -, valid values: A0-A7<br><br>
		</li>
		<li><a name="invert_input">invert_input</a><br>
			Comma separated list of input ports which use inverted logic<br>
			Default: -, valid values: A0-A7<br><br>
		</li>
		<li><a name="InterruptOut">InterruptOut</a><br>
			Configuration options for INT output pin<br>
			Values:<br>
			<ul>
				<li>
					active-low (INT output is active low)
				</li>
				<li>
					active-high (INT output is active high)
				</li>
				<li>
					open-drain (INTA output is open drain)
				</li><br>
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

<a name="I2C_MCP23008"></a>
<h3>I2C_MCP23008</h3>
(<a href="commandref.html#I2C_MCP23008">en</a> | de)
<ul>
	<a name="I2C_MCP23008"></a>
		Erm&ouml;glicht die Verwendung eines MCP23008 I2C 8 Bit Portexenders. 
		Auf einem Raspberry Pi kann der Interrupt Pin des MCP23008 mit einem GPIO verbunden werden und &uuml;ber die Interrupt Funktionen von <a href="#RPI_GPIO">RPI_GPIO</a> l&auml;sst sich dann ein get f&uuml;r den MCP23008 bei Pegel&auml;nderung ausl&ouml;sen.<br>
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_MCP23008Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_MCP23008 &lt;I2C Address&gt;</code><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Beispielsweise 0x40 (hexadezimal) = 64 (dezimal). Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
	</ul>

	<a name="I2C_MCP23008Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
			<code>&lt;port&gt;</code> kann PortA0 bis PortA7 annehmen und <code>&lt;value&gt;</code> folgende Werte:<br>
				<ul>
				<code>
					off<br>
					on<br>
				</code>
				</ul>
		<br>
		Beispiel:
		<ul>
			<code>set mod1 PortA4 on</code><br>
			<code>set mod1 PortA4,PortA6 off</code><br>
			<code>set mod1 PortA4,A6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_MCP23008Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>

	<a name="I2C_MCP23008Attr"></a>
	<b>Attribute</b>
	<ul>
		<li><a name="poll_interval">poll_interval</a><br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
		<li><a name="OutputPorts">OutputPorts</a><br>
			Durch Komma getrennte Ports die als Ausg&auml;nge genutzt werden sollen.<br>
			Nur Ports in dieser Liste k&ouml;nnen gesetzt werden.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7<br><br>
		</li>
		<li><a name="OnStartup">OnStartup</a><br>
			Durch Komma getrennte Output Ports und ihr gew&uuml;nschter Status nach dem Start.<br>
			Ohne dieses Attribut werden alle Ausg&auml;nge nach dem Start auf den letzten Status gesetzt.<br>
			Standard: -, g&uuml;ltige Werte: &lt;port&gt;=on|off|last wobei &lt;port&gt; = A0-A7<br><br>
		</li>
		<li><a name="Pullup">Pullup</a><br>
			Durch Komma getrennte Input Ports, bei denen der interne 100k pullup aktiviert werden soll.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7<br><br>
		</li>
		<li><a name="Interrupt">Interrupt</a><br>
			Durch Komma getrennte Input Ports, die einen Interrupt auf IntA/B ausl&ouml;sen.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7<br><br>
		</li>
		<li><a name="invert_input">invert_input</a><br>
			Durch Komma getrennte Input Ports, die reverse Logik nutzen.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7<br><br>
		</li>
		<li><a name="InterruptOut">InterruptOut</a><br>
			Einstellungen f&uuml;r den INT Pin<br>
			g&uuml;ltige Werte:<br>
			<ul>
				<li>
					active-low (INT ist active low)
				</li>
				<li>
					active-high (INT ist active high)
				</li>
				<li>
					open-drain (INT ist open drain)
				</li><br>
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
