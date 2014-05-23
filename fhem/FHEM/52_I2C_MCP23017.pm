##############################################################################
# $Id: 
##############################################################################
# Modul for I2C PWM Driver MCP23017
#
# define <name> I2C_MCP23017 <I2C-Adresse>
# set <name> <port> <value>
#
# contributed by Klaus Wittstock (2013) email: klauswittstock bei gmail punkt com
#
##############################################################################

package main;
use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

my %Registers = (
  'IODIRA'   => 0x00,		#1 = input; 0 = output (default 1)
  'IODIRB'   => 0x01,
  'IPOLA'    => 0x02,		#1 inverts logic (default 0)
  'IPOLB'    => 0x03,
  'GPINTENA' => 0x04,		#1 enables the pin for interrupt-on-change (default 0)
  'GPINTENB' => 0x05,
  'DEFVALA'  => 0x06,		#The default comparison value for interrupt (opposite value will caues an interrupt) (default 0)
  'DEFVALB'  => 0x07,
  'INTCONA'  => 0x08,		#If a bit is set, the corresponding I/O pin is compared against DEFVAL register. Otherwise against the previous value.
  'INTCONB'  => 0x09,
  'IOCON'    => 0x0A,
  'GPPUA'    => 0x0C,		#100k pull up resistor for input
  'GPPUB'    => 0x0D,
  'INTFA'    => 0x0E,		#shows which Pin caused the interrupt (ro)
  'INTFB'    => 0x0F,
  'INTCAPA'  => 0x10,		#status from all registers at the time the interrupt occured, remain unchanged until a read of INTCAP or GPIO. (ro)
  'INTCAPB'  => 0x11,
  'GPIOA'    => 0x12,		#value on the ports (r/w)
  'GPIOB'    => 0x13,
  'OLATA'    => 0x14,
  'OLATB'    => 0x15,
);

my %setsP = (
'off' => 0,
'on' => 1,
); 

my %intout = (
'separate_active-low'   => 0x00,
'separate_active-high'  => 0x02,
'separate_open-drain'   => 0x04,
'connected_active-low'  => 0x40,
'connected_active-high' => 0x42,
'connected_open-drain'  => 0x44,
);
###############################################################################
sub I2C_MCP23017_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = "I2C_MCP23017_Define";
  $hash->{InitFn}   = 'I2C_MCP23017_Init';
  $hash->{UndefFn}  = "I2C_MCP23017_Undefine";
  $hash->{AttrFn}   = "I2C_MCP23017_Attr";
  $hash->{StateFn}  = "I2C_MCP23017_State"; 
  $hash->{SetFn}    = "I2C_MCP23017_Set";
  $hash->{GetFn}    = "I2C_MCP23017_Get";
  $hash->{I2CRecFn} = "I2C_MCP23017_I2CRec";
  $hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0".
					  "poll_interval OutputPorts ".
                      "Pullup invert_input Interrupt OnStartup ".
											"InterruptOut:separate_active-low,separate_active-high,separate_open-drain,connected_active-low,connected_active-high,connected_open-drain ".
					  "$readingFnAttributes";
}
###############################################################################
sub I2C_MCP23017_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
  if ($main::init_done) {
    eval { I2C_MCP23017_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_MCP23017_Catch($@) if $@;
  }
  return undef;
}
###############################################################################
sub I2C_MCP23017_Init($$) {																										#Geraet beim anlegen/booten/nach Neuverbindung (wieder) initialisieren
 my ( $hash, $args ) = @_;
 if (defined $args && int(@$args) != 1) {
  return "Define: Wrong syntax. Usage:\n" .
         "define <name> I2C_MCP23017 <i2caddress>";
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
		$sbyte += $setsP{ReadingsVal($hash->{NAME},"PortB".$_,"off")} << (8 + $_);
  }
  $msg = I2C_MCP23017_SetRegPair($hash, $sbyte, "GPIO") if $sbyte;
	#bei Init IC neu konfigurieren
  if ( defined ( my $val = AttrVal($hash->{NAME},"invert_input",undef)) ) {
		($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, "invert_input", $val);
		$msg = I2C_MCP23017_SetRegPair($hash, $regval, "IPOL") unless $msg;
  }
  if ( defined ( my $val = AttrVal($hash->{NAME},"OutputPorts",undef)) ) {
		($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, "OutputPorts", $val);
		$msg = I2C_MCP23017_SetRegPair($hash, ~$regval, "IODIR") unless $msg;
  }
  if ( defined ( my $val = AttrVal($hash->{NAME},"Pullup",undef)) ) {
		($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, "Pullup", $val);
		$msg = I2C_MCP23017_SetRegPair($hash, $regval, "GPPU") unless $msg;
  }
  if ( defined ( my $val = AttrVal($hash->{NAME},"Interrupt",undef)) ) {
		($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, "Interrupt", $val);
		$msg = I2C_MCP23017_SetRegPair($hash, $regval, "GPINTEN") unless $msg;
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
 $hash->{STATE} = 'Initialized';
 return ($msg) ? $msg : undef;
}
###############################################################################
sub I2C_MCP23017_Catch($) {																										#Fehlermeldung von eval formattieren
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}
###############################################################################
sub I2C_MCP23017_Undefine($$) {
  my ($hash, $arg) = @_;
  if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
    RemoveInternalTimer($hash);
  }
}
###############################################################################
sub I2C_MCP23017_Attr(@) {
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 if ($command && $command eq "set" && $attr && $attr eq "IODev") {
	if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
    main::AssignIoPort($hash,$val);
    my @def = split (' ',$hash->{DEF});
    I2C_MCP23017_Init($hash,\@def) if (defined ($hash->{IODev}));
    }
 }
 if ($attr && $attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		if (!defined($val) ) {
			RemoveInternalTimer($hash);
		} elsif ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_MCP23017_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		} 
 } elsif ($attr && $attr eq "OutputPorts") {
	($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23017_SetRegPair($hash, ~$regval, "IODIR") unless $msg;
	
 } elsif ($attr && $attr eq "Pullup") {
	($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23017_SetRegPair($hash, $regval, "GPPU") unless $msg;
	
 } elsif ($attr && $attr eq "invert_input") {
	($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23017_SetRegPair($hash, $regval, "IPOL") unless $msg;
	
 } elsif ($attr && $attr eq "Interrupt") {
	($msg, my $regval) = I2C_MCP23017_CheckAttr($hash, $attr, $val);
	$msg = I2C_MCP23017_SetRegPair($hash, $regval, "GPINTEN") unless $msg;
	
 } elsif ($attr && $attr eq "OnStartup") {
	if (defined $val) {
		foreach (split (/,/,$val)) {
			my @pair = split (/=/,$_);
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <port>=on|off|last where <port> = A0 - A7 and/or B0 - B7" 
				unless ( scalar(@pair) == 2 &&
								$pair[0] =~ m/^(A|B)(0|)[0-7]$/i &&
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
sub I2C_MCP23017_State($$$$) {																								#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ($sname =~ m/^Port(A|B)(0|)[0-7]$/i) {
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
sub I2C_MCP23017_CheckAttr {
	my ($hash, $attr, $val) = @_;
	my $msg = undef;
	my ($regval) = 0;
 	if (defined $val) {
		foreach (split (/,/,$val)) {
			$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated values from A0 - A7 and/or B0 - B7" unless ($_ =~ m/^(A|B)(0|)[0-7]$/i);		
			my $bank = ($_ =~ m/^A/) ? 0 : 8;	# A oder B
			$_ =~ tr/[a-zA-Z]//d;				#Nummer aus String extrahieren
			$regval |= 1 << ($_ + $bank);   
		}
 	}
	return $msg, $regval;
}
###############################################################################
sub I2C_MCP23017_SetRegPair {																									#set register pair for PortA/B
	my ($hash, $regval, $regtype) = @_;
  my %port = ();
	$port{A} = $regval & 0xff;
	$port{B} = ( $regval >> 8 ) & 0xff;

    if (defined (my $iodev = $hash->{IODev})) {
    	foreach my $reg (keys %port) {
			#Log3 $hash, 1, "schreibe raus: i2cwrite|$hash->{I2C_Address}|$Registers{$regtype . $reg}|$port{$reg}|";
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
				direction  => "i2cwrite",
				i2caddress => $hash->{I2C_Address},
				reg => 				$Registers{$regtype . $reg},
				data => 			$port{$reg},
				}) if (defined $hash->{I2C_Address});
      	}
	} else {
		return "no IODev assigned to '$hash->{NAME}'";
	}
}
###############################################################################
sub I2C_MCP23017_Poll($) {																										#function for refresh intervall
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # Read values
  I2C_MCP23017_Get($hash, $name);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_MCP23017_Poll', $hash, 0);
  }
} 
###############################################################################
sub I2C_MCP23017_Set($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];
  my $cmd = $a[1];
  my $val = $a[2];
  my @outports = sort(split(/,/,AttrVal($name, "OutputPorts", "")));
  unless (@a == 3) {

  }
	my $msg = undef;
	if ( $cmd && $cmd =~ m/^P(ort|)(A|B)((0|)[0-7])(,(P|)(ort|)(A|B)((0|)[0-7])){0,7}$/i) {
    return "wrong value: $val for \"set $name $cmd\" use one of: " . 
			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) )
			unless(exists($setsP{$val}));
		my @scmd = split(",", $cmd);
		foreach (@scmd) {
			$_ =~ tr/P(ort|)//d;			#Nummer aus String extrahieren
			$msg .= (defined $msg ? "," : "") . "Port" . $_ unless ( ($_) ~~ @outports );		#Pruefen ob entsprechender Port Input ist
		}
		return "$name error: $msg is defined as input" if $msg;
		#Log3 $hash, 1, "$name: multitest gereinigt: @scmd";
	
		my $regval = 0;
		foreach (reverse 0..7) {
			foreach my $po ("A","B") {
				my $bank = ($po eq "A") ? 0 : 8;	# A oder B
				if ( ($po.$_) ~~ @scmd ) {				#->wenn aktueller Port in Liste dann neuer Wert
					$regval += $setsP{$val} << ($bank + $_);
				} else {													#->sonst aus dem Reading holen
					$regval += $setsP{ReadingsVal($name,"Port".$po.$_,"off")} << ($bank + $_);		
				}
			}
		}	
	  #Log3 $hash, 1, "$name: endwert: $regval";
		$msg = I2C_MCP23017_SetRegPair($hash, $regval, "GPIO") unless $msg;
	} else {
	  my $list = "";
    foreach (0..7) {
		  next unless ( ("A" . $_) ~~ @outports );		#Inputs überspringen
			$list .= "PortA" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
    }
		foreach (0..7) {
		  next unless ( ("B" . $_) ~~ @outports );		#Inputs überspringen
			$list .= "PortB" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
    }
    $msg = "Unknown argument $a[1], choose one of " . $list;
	}
	return ($msg) ? $msg : undef;
	
###########################################################################################################
#alte einzelportversion	
#	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" );
#	if ( $cmd && $cmd =~ m/^Port(A|B)(0|)[0-7]$/i) {
#    return "wrong value: $val for \"set $name $cmd\" use one of: " . 
#			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) )
#			unless(exists($setsP{$val}));
#		my $po = substr $cmd, 4, 1;		# A oder B
#		my $regaddr = $po eq "A" ? $Registers{GPIOA} : $Registers{GPIOB};				#Adresse für GPIO Register
#    substr($cmd,0,5,"");
#	  return "$name error: Port$po$cmd is defined as input" unless ( ($po . $cmd) ~~ @outports );		#Prüfen ob entsprechender Port Input ist
#
#		my $sbyte = 0;
#		foreach (reverse 0..7) {
#			if ( $_ == $cmd ) {		#->wenn aktueller Port dann neuer Wert
#				$sbyte += $setsP{$val} << ($_);
#				next;
#			}
#			$sbyte += $setsP{ReadingsVal($name,"Port".$po.$_,"off")} << ($_);		#->sonst aus dem Reading holen
#		}	
#
#		$sendpackage{data} = $sbyte;
#		$sendpackage{reg} = $regaddr;
#		Log3 $hash, 5, "$name set regaddr: " . sprintf("%.2X",$sendpackage{reg}) . " inhalt: " . sprintf("%.2X",$sendpackage{data});
#  } else {
#	  my $list = "";
#    foreach (0..7) {
#		  next unless ( ("A" . $_) ~~ @outports );		#Inputs überspringen
#			$list .= "PortA" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
#    }
#		foreach (0..7) {
#		  next unless ( ("B" . $_) ~~ @outports );		#Inputs überspringen
#			$list .= "PortB" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
#    }
#    return "Unknown argument $a[1], choose one of " . $list;
#	}
#  return "$name: no IO device defined" unless ($hash->{IODev});
#  my $phash = $hash->{IODev};
#  my $pname = $phash->{NAME};
#  CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);

}
###############################################################################
sub I2C_MCP23017_Get($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];

	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
	$sendpackage{reg} = 18; 																			#startadresse zum lesen
	$sendpackage{nbyte} = 2;
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	
}
###############################################################################
sub I2C_MCP23017_I2CRec($@) {																									#ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};  
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals für alle Keys in $clientmsg die mit dem physical Namen beginnen
    $hash->{$k} = $v if $k =~ /^$pname/ ;
  } 
	#hier noch überprüfen, ob Register und Daten ok
  if ($clientmsg->{direction} && defined $clientmsg->{reg} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
		if ($clientmsg->{direction} eq "i2cread" && $clientmsg->{received}) { # =~ m/^[a-f0-9]{2}$/i) {
			#my @rec = @{$clientmsg->{received}};							#bei übergabe im hash als array
			my @rec = split(" ",$clientmsg->{received});			#bei übergabe im als skalar
			Log3 $hash, 3, "$name: wrong amount of registers transmitted from $pname" unless (@rec == $clientmsg->{nbyte});
			foreach (reverse 0..$#rec) {																							#reverse, damit Inputs (Register 0 und 1 als letztes geschrieben werden)
				I2C_MCP23017_UpdReadings($hash, $_ + $clientmsg->{reg} , $rec[$_]);
			}
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} elsif ($clientmsg->{direction} eq "i2cwrite" && defined $clientmsg->{data}) { # =~ m/^[a-f0-9]{2}$/i) {#readings aktualisieren wenn Übertragung ok
			I2C_MCP23017_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{data}) if ( ($clientmsg->{reg} == $Registers{GPIOA}) || ($clientmsg->{reg} == $Registers{GPIOB}) );
			readingsSingleUpdate($hash,"state", "Ok", 1);
		
		} else {
			readingsSingleUpdate($hash,"state", "transmission error", 1);
			Log3 $hash, 3, "$name: failurei in message from $pname";
			Log3 $hash, 3,(defined($clientmsg->{direction}) ? 	"Direction: "		.										$clientmsg->{direction} 	: "Direction: undef").
										(defined($clientmsg->{i2caddress}) ? 	" I2Caddress: " . sprintf("0x%.2X", $clientmsg->{i2caddress}) : " I2Caddress: undef").
										(defined($clientmsg->{reg}) ? 				" Register: " 	. sprintf("0x%.2X", $clientmsg->{reg}) 				: " Register: undef").
										(defined($clientmsg->{data}) ? 				" Data: " 			. sprintf("0x%.2X", $clientmsg->{data}) 			: " Data: undef").
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
sub I2C_MCP23017_UpdReadings($$$) {																						#nach Rueckmeldung readings updaten (ueber I2CRec aufgerufen)
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
		      if (ReadingsVal($name, 'PortA'.$_,"nix") ne $rsetsP{$pval});  #nur wenn Wert geändert
		}
	} elsif ($reg == $Registers{GPIOB}) {
		my %rsetsP = reverse %setsP;
	  foreach (0..7) {
			  my $pval = 1 & ( $inh >> $_ );
				readingsBulkUpdate($hash, 'PortB'.$_ , $rsetsP{$pval}) 
		      if (ReadingsVal($name, 'PortB'.$_,"nix") ne $rsetsP{$pval});  #nur wenn Wert geändert
		}
	}
	
	readingsEndUpdate($hash, 1);
	return;
}
1;

=pod
=begin html

<a name="I2C_MCP23017"></a>
<h3>I2C_MCP23017</h3>
<ul>
	<a name="I2C_MCP23017"></a>
		Provides an interface to the MCP23017 16 channel port extender IC. On Raspberry Pi the Interrupt Pin's can be connected to an GPIO and <a href="#RPI_GPIO">RPI_GPIO</a> can be used to get the port values if an interrupt occurs.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>         
	<a name="I2C_MCP23017Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_MCP23017 &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> is without direction bit<br>
	</ul>

	<a name="I2C_MCP23017Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
				where <code>&lt;port&gt;</code> is one of PortA0 to PortA7 / PortAB to PortB7 and <code>&lt;value&gt;</code> is one of:<br>
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
			<code>set mod1 PortA4,PortB6 off</code><br>
			<code>set mod1 PortA4,B6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_MCP23017Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>

	<a name="I2C_MCP23017Attr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query the GPIO's level<br>
			Default: -, valid values: decimal number<br><br>
		</li>
		<li>OutputPorts<br>
			Comma separated list of ports that are used as Output<br>
			Ports not in this list can't be written<br>
			Default: no, valid values: A0-A7, B0-B7<br><br>
		</li>
		<li>OnStartup<br>
			Comma separated list of output ports and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Default: -, valid values: &lt;port&gt;=on|off|last where &lt;port&gt; = A0-A7, B0-B7<br><br>
		</li>
		<li>Pullup<br>
			Comma separated list of input ports which switch on their internal 100k pullup<br>
			Default: -, valid values: A0-A7, B0-B7<br><br>
		</li>
		<li>Interrupt<br>
			Comma separated list of input ports which will trigger the IntA/B pin<br>
			Default: -, valid values: A0-A7, B0-B7<br><br>
		</li>
		<li>invert_input<br>
			Comma separated list of input ports which use inverted logic<br>
			Default: -, valid values: A0-A7, B0-B7<br><br>
		</li>
		<li>InterruptOut<br>
			Configuration options for INTA/INTB output pins<br>
			Values:<br>
			<ul>
				<li>
					separate_active-low (INTA/INTB outputs are separate for both ports and active low)
				</li>
				<li>
					separate_active-high (INTA/INTB outputs are separate for both ports and active high)
				</li>
				<li>
					separate_open-drain (INTA/INTB outputs are separate for both ports and open drain)
				</li>
				<li>
					connected_active-low (INTA/INTB outputs are internally connected and active low)
				</li>
				<li>
					connected_active-high (INTA/INTB outputs are internally connected and active high)
				</li>
				<li>
					connected_open-drain (INTA/INTB outputs are internally connected and open drain)
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

<a name="I2C_MCP23017"></a>
<h3>I2C_MCP23017</h3>
<ul>
	<a name="I2C_MCP23017"></a>
		Erm&ouml;glicht die Verwendung eines MCP23017 I2C 16 Bit Portexenders. 
		Auf einem Raspberry Pi kann der Interrupt Pin des MCP23017 mit einem GPIO verbunden werden und &uuml;ber die Interrupt Funktionen von <a href="#RPI_GPIO">RPI_GPIO</a> l&auml;sst sich dann ein get f&uuml;r den MCP23017 bei Pegel&auml;nderung ausl&ouml;sen.<br>
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_MCP23017Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_MCP23017 &lt;I2C Address&gt;</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ohne das Richtungsbit<br>
	</ul>

	<a name="I2C_MCP23017Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
			<code>&lt;port&gt;</code> kann PortA0 bis PortA7 / PortB0 bis PortB7 annehmen und <code>&lt;value&gt;</code> folgende Werte:<br>
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
			<code>set mod1 PortA4,PortB6 off</code><br>
			<code>set mod1 PortA4,B6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_MCP23017Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>

	<a name="I2C_MCP23017Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
		<li>OutputPorts<br>
			Durch Komma getrennte Ports die als Ausg&auml;nge genutzt werden sollen.<br>
			Nur Ports in dieser Liste k&ouml;nnen gesetzt werden.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7, B0-B7<br><br>
		</li>
		<li>OnStartup<br>
			Durch Komma getrennte Output Ports und ihr gew&uuml;nschter Status nach dem Start.<br>
			Ohne dieses Attribut werden alle Ausg&auml;nge nach dem Start auf den letzten Status gesetzt.<br>
			Standard: -, g&uuml;ltige Werte: &lt;port&gt;=on|off|last wobei &lt;port&gt; = A0-A7, B0-B7<br><br>
		</li>
		<li>Pullup<br>
			Durch Komma getrennte Input Ports, bei denen der interne 100k pullup aktiviert werden soll.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7, B0-B7<br><br>
		</li>
		<li>Interrupt<br>
			Durch Komma getrennte Input Ports, die einen Interrupt auf IntA/B auslösen.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7, B0-B7<br><br>
		</li>
		<li>invert_input<br>
			Durch Komma getrennte Input Ports, die reverse Logik nutzen.<br>
			Standard: -, g&uuml;ltige Werte: A0-A7, B0-B7<br><br>
		</li>
		<li>InterruptOut<br>
			Einstellungen f&uuml;r die INTA/INTB Pins<br>
			g&uuml;ltige Werte:<br>
			<ul>
				<li>
					separate_active-low (INTA/INTB sind f&uuml;r PortA/PortB getrennt und mit active low Logik)
				</li>
				<li>
					separate_active-high (INTA/INTB sind f&uuml;r PortA/PortB getrennt und mit active high Logik)
				</li>
				<li>
					separate_open-drain (INTA/INTB sind f&uuml;r PortA/PortB getrennt und arbeiten als open drain)
				</li>
				<li>
					connected_active-low (INTA/INTB sind intern verbunden und mit active low Logik)
				</li>
				<li>
					connected_active-high (INTA/INTB sind intern verbunden und mit active high Logik)
				</li>
				<li>
					connected_open-drain (INTA/INTB sind intern verbunden und arbeiten als open drain)
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
