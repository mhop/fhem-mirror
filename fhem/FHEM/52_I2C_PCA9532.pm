##############################################################################
# $Id$
# 52_I2C_PCA9532.pm
#
##############################################################################
# Modul for I2C PWM Driver PCA9532
#
# define <name> I2C_PCA9532 <I2C-Adresse>
# set <name> <port> <value>
#
# contributed by Klaus Wittstock (2014) email: klauswittstock bei gmail punkt com
#
##############################################################################
#zu tun:
#bei Set sollten Input Values nicht aktualisiert werden
#$sendpackage{data} als Array ?
#$clientmsg->{received} als Array ?

#Inhalte des Hashes:
#i2caddress				00-7F								I2C-Adresse
#direction				i2cread|i2cwrite		Richtung
#reg							00-FF|""						Registeradresse (kann weggelassen werden fuer IC's ohne Registeradressierung)
#nbyte						Zahl								Anzahl Register, die bearbeitet werden sollen (im mom 0-99)
#data							00-FF ... 					Daten die an I2C geschickt werden sollen (muessen, wenn nbyte benutzt wird immer ein Vielfaches Desselben sein)
#received					00-FF ...						Daten die vom I2C empfangen wurden, durch Leerzeichen getrennt (bleibt leer wenn Daten geschrieben werden)
#pname_SENDSTAT		Ok|error						zeigt uebertragungserfolg an

package main;
use strict;
use warnings;
use SetExtensions;
#use POSIX;
use Scalar::Util qw(looks_like_number);
#use Error qw(:try);

my $setdim = ":slider,0,1,255 ";

my %setsP = (
'off' => 0,
'on' => 1,
'PWM0' => 2,
'PWM1' => 3,
); 
###############################################################################
sub I2C_PCA9532_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = "I2C_PCA9532_Define";
  $hash->{InitFn}   = 'I2C_PCA9532_Init';
  $hash->{UndefFn}  = "I2C_PCA9532_Undefine";
  $hash->{AttrFn}   = "I2C_PCA9532_Attr";
  #$hash->{StateFn} = "I2C_PCA9532_SetState";
  $hash->{SetFn}    = "I2C_PCA9532_Set";
  $hash->{GetFn}    = "I2C_PCA9532_Get";
  $hash->{I2CRecFn} = "I2C_PCA9532_I2CRec";
  $hash->{AttrList} = "IODev do_not_notify:1,0 ignore:1,0 showtime:1,0".
											"poll_interval T0:slider,0,1,255 T1:slider,0,1,255 InputPorts ".
											"$readingFnAttributes";
}
###############################################################################
sub I2C_PCA9532_SetState($$$$) {
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  #return "Undefined value $val" if(!defined($it_c2b{$val}));
  return undef;
}
###############################################################################
sub I2C_PCA9532_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
 if ($main::init_done) {
    eval { I2C_PCA9532_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_PCA9532_Catch($@) if $@;
  }
  return undef;
}
###############################################################################
sub I2C_PCA9532_Init($$) {
	my ( $hash, $args ) = @_;
	#my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME}; 
	if (defined $args && int(@$args) != 1)	{
		return "Define: Wrong syntax. Usage:\n" .
		       "define <name> I2C_PCA9532 <i2caddress>";
	}
 #return "$name I2C Address not valid" unless ($a[0] =~ /^(0x|)([0-7]|)[0-9A-F]$/xi);
 
 if (defined (my $address = shift @$args)) {
   $hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
 } else {
   return "$name I2C Address not valid";
 }
 
 #$hash->{I2C_Address} = hex($a[0]);
 AssignIoPort($hash);
 $hash->{STATE} = 'Initialized';
 return;
}
###############################################################################
sub I2C_PCA9532_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}
###############################################################################
sub I2C_PCA9532_Undefine($$) {
  my ($hash, $arg) = @_;
  if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
    RemoveInternalTimer($hash);
  }
}
###############################################################################
sub I2C_PCA9532_Attr(@) {
 my (undef, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
 if ($attr && $attr eq 'poll_interval') {
		#my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		if (!defined($val) ) {
			RemoveInternalTimer($hash);
		} elsif ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_PCA9532_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		} 
 } elsif ($attr && $attr =~ m/^T[0-1]$/i) {
   return "wrong value: $val for \"set $name $attr\" use 0-255"
	    	unless(looks_like_number($val) && $val >= 0 && $val < 256);
   substr($attr,0,1,"");
   my $regaddr = ($attr == 0 ? 2 : 4);
   my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" );
   #$sendpackage{data} = sprintf("%.2X", $val);
   #$sendpackage{reg} = sprintf("%.2X", $regaddr);
	 $sendpackage{data} = $val;
   $sendpackage{reg} = $regaddr;
   return "$name: no IO device defined" unless ($hash->{IODev});
   my $phash = $hash->{IODev};
   my $pname = $phash->{NAME};
   CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
 } elsif ($attr && $attr eq "InputPorts") {
		my @inp = split(" ", $val);
		foreach (@inp) {
			return "wrong value: $_ for \"set $name $attr\" use space separated numbers 0-15" unless ($_ >= 0 && $_ < 16);
		}
 }
  return ($msg) ? $msg : undef; 
}
###############################################################################
sub I2C_PCA9532_Poll($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # Read values
  I2C_PCA9532_Get($hash, $name);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_PCA9532_Poll', $hash, 0);
  }
} 
###############################################################################
sub I2C_PCA9532_Set($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];
  my $cmd = $a[1];
  my $val = $a[2];
	my @inports = sort(split( " ",AttrVal($name, "InputPorts", "")));
  unless (@a == 3) {

  }
  my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" );
  if ( $cmd && $cmd =~ m/^Port((0|)[0-9]|1[0-5])$/i) {
    return "wrong value: $val for \"set $name $cmd\" use one of: " . 
			join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) )
			unless(exists($setsP{$val}));
    substr($cmd,0,4,"");
	  return "$name error: Port$cmd is defined as input" if ( $cmd ~~ @inports );		#Pruefen ob entsprechender Port Input ist
		my $LSreg = int($cmd / 4); 			#Nummer des entspechenden LS Registers
		my $regaddr = $LSreg + 6;				#Adresse fuer Controlregister berechnen (LS0 = 0x06)
		my $n = $LSreg * 4;							#Erster Port in LSx
		my $sbyte = 0;
		foreach (reverse 0..3) {				#ensprechendes Controlregister fuellen
		  my $portn = $_ + $n;
#hier noch alle inputs auf rezessiv setzen
			if (( $portn) == $cmd ) {		#->wenn aktueller Port dann neuer Wert
				$sbyte += $setsP{$val} << (2 * $_);
				next;
			}
			$sbyte += $setsP{ReadingsVal($name,'Port'.$portn,"off")} << (2 * $_);		#->sonst aus dem Reading holen
		}
		#$sendpackage{data} = sprintf("%.2X",$sbyte);	
		$sendpackage{data} = $sbyte;	
		#$sendpackage{reg} = sprintf("%.2X", $regaddr);
		$sendpackage{reg} = $regaddr;
		
  } elsif ($cmd && $cmd =~ m/^PWM[0-1]$/i) {
    return "wrong value: $val for \"set $name $cmd\" use 0-255"
			unless(looks_like_number($val) && $val >= 0 && $val < 256);
    substr($cmd,0,3,"");
		my $regaddr = ($cmd == 0 ? 3 : 5);
		#$sendpackage{data} = sprintf("%.2X", $val);
		$sendpackage{data} = $val;
		$sendpackage{reg} = sprintf("%.2X", $regaddr);
		
  } else {
	  my $list = undef;
    foreach (0..15) {
		  next if ( $_ ~~ @inports );		#Inputs ueberspringen
			#$list .= "Port" . $_ . ":" . join(',', sort keys %setsP) . " ";
			$list .= "Port" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
    }
    $list .= join($setdim, ("PWM0", "PWM1")) . $setdim;
    return "Unknown argument $a[1], choose one of " . $list;
	}
  return "$name: no IO device defined" unless ($hash->{IODev});
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
}
###############################################################################
sub I2C_PCA9532_Get($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];

	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread" );
	$sendpackage{reg} = 0; 																			#startadresse zum lesen
	$sendpackage{nbyte} = 10;
	return "$name: no IO device defined" unless ($hash->{IODev});
	my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	
}
###############################################################################
sub I2C_PCA9532_I2CRec($@) {																									# vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};  
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
    $hash->{$k} = $v if $k =~ /^$pname/ ;
  } 
	#hier noch ueberpruefen, ob Register und Daten ok
  if ($clientmsg->{direction} && defined($clientmsg->{reg}) && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) { # =~ m/^[a-f0-9]{2}$/i) {
			#my @rec = @{$clientmsg->{received}};							#bei uebergabe im hash als array
			my @rec = split(" ",$clientmsg->{received});			#bei uebergabe im als skalar
			Log3 $hash, 3, "$name: wrong amount of registers transmitted from $pname" unless (@rec == $clientmsg->{nbyte});
			foreach (reverse 0..$#rec) {																							#reverse, damit Inputs (Register 0 und 1 als letztes geschrieben werden)
				I2C_PCA9532_UpdReadings($hash, $_ + $clientmsg->{reg} , $rec[$_]);
			}
			readingsSingleUpdate($hash,"state", "Ok", 1);
		} elsif ( $clientmsg->{direction} eq "i2cwrite" && defined($clientmsg->{data}) ) { # =~ m/^[a-f0-9]{2}$/i) {#readings aktualisieren wenn uebertragung ok
			I2C_PCA9532_UpdReadings($hash, $clientmsg->{reg} , $clientmsg->{data});
			readingsSingleUpdate($hash,"state", "Ok", 1);
		
		} else {
			readingsSingleUpdate($hash,"state", "transmission error", 1);
			Log3 $hash, 3, "$name: failure in message from $pname";
			Log3 $hash, 3,(defined($clientmsg->{direction}) ? "Direction: $clientmsg->{direction} " : "Direction: undef ").
										(defined($clientmsg->{i2caddress}) ? "I2Caddress: $clientmsg->{i2caddress} " : "I2Caddress: undef ").
										(defined($clientmsg->{reg}) ? "Register: $clientmsg->{reg} " : "Register: undef ").
										(defined($clientmsg->{data}) ? "Data: $clientmsg->{data} " : "Data: undef ").
										(defined($clientmsg->{received}) ? "received: $clientmsg->{received} " : "received: undef ");
		}
  } else {
		readingsSingleUpdate($hash,"state", "transmission error", 1);
		Log3 $hash, 3, "$name: failure in message from $pname";
		Log3 $hash, 3,(defined($clientmsg->{direction}) ? "Direction: $clientmsg->{direction} " : "Direction: undef ").
									(defined($clientmsg->{i2caddress}) ? "I2Caddress: $clientmsg->{i2caddress} " : "I2Caddress: undef ").
									(defined($clientmsg->{reg}) ? "Register: $clientmsg->{reg} " : "Register: undef ").
									(defined($clientmsg->{data}) ? "Data: $clientmsg->{data} " : "Data: undef ").
									(defined($clientmsg->{received}) ? "received: $clientmsg->{received} " : "received: undef ");
		#my $cmsg = undef;
		#foreach my $av (keys %{$clientmsg}) { $cmsg .= "|" . $av . ": " . $clientmsg->{$av}; }
		#Log3 $hash, 3, $cmsg;
		}
  #undef $clientmsg;
}
###############################################################################
sub I2C_PCA9532_UpdReadings($$$) {
	my ($hash, $reg, $inh) = @_;
	my $name = $hash->{NAME};
	#$inh = hex($inh);
	Log3 $hash, 5, "$name UpdReadings Register: $reg, Inhalt: $inh";
	readingsBeginUpdate($hash);
	if ( $reg < 10 && $reg > 5) {								#Wenn PortRegister
	  my %rsetsP = reverse %setsP;
		my $LSreg = $reg - 6;								#Nummer des entspechenden LS Registers
		my $n     = $LSreg * 4;							#Erster Port in LSx
		foreach (reverse 0..3) {						#Ports aus Controlregister abarbeiten
		  my $pval = 3 & ( $inh >> ($_ * 2) );
			my $port = $_ + $n;
			readingsBulkUpdate($hash, 'Port'.$port , $rsetsP{$pval}) 
			      if (ReadingsVal($name, 'Port'.$port,"nix") ne $rsetsP{$pval});  #nur wenn Wert geaendert
		}
	} elsif ( $reg == 3) { 											#wenn PWM0 Register
		readingsBulkUpdate($hash, 'PWM0' , $inh);
	} elsif ( $reg == 5) { 											#wenn PWM1 Register
		readingsBulkUpdate($hash, 'PWM1' , $inh);
	} elsif ( $reg == 2) { 											#wenn Frequenz0 Register
		$hash->{Frequency_0} = sprintf( "%.3f", ( 152 / ($inh + 1) ) ) . " Hz";
	} elsif ( $reg == 4) { 											#wenn Frequenz0 Register
		$hash->{Frequency_1} = sprintf( "%.3f", ( 152 / ($inh + 1) ) ) . " Hz";
	} elsif ( $reg >= 0 && $reg < 2 ) {					#Input Register
	  my $j = 8 * $reg;
		Log3 $hash, 5, "Register $reg Inh: $inh";		
		my @inports = sort(split( " ",AttrVal($name, "InputPorts", "")));
		for (my $i = 0; $i < 8; $i++) {
			Log3 $hash, 5, "Register $reg Forschleife i: $i";
			if ( ($i + $j) ~~ @inports ) {					#nur als Input definierte Ports aktualisieren
				my $sval = $inh & (1 << $i);
				$sval = $sval == 0 ? "0" :"1";
				readingsBulkUpdate($hash, 'Port'.($i + $j) , $sval) if (ReadingsVal($name,'Port'.($i + $j),2) ne $sval);
				Log3 $hash, 5, "Register $reg wert: $sval";
			}
     }	
	}
	readingsEndUpdate($hash, 1);
	return;
}
###############################################################################

1;

=pod
=begin html

<a name="I2C_PCA9532"></a>
<h3>I2C_PCA9532</h3>
<ul>
	<a name="I2C_PCA9532"></a>
		Provides an interface to the PCA9532 I2C 16 channel PWM IC. 
		The PCA9532 has 2 independent PWM stages and every channel can be attached to on of these stages or directly turned on or off.
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>
	<a name="I2C_PCA9532Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9532 &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> is an 2 digit hexadecimal value<br>
	</ul>

	<a name="I2C_PCA9532Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt;</code><br><br>
			<ul>
			<li>if <code>&lt;port&gt;</code> is one of Port0 to Port15, then <code>&lt;value&gt;</code> will be one of:<br>
				<ul>
				<code>
					off<br>
					on<br>
					PWM0 (output is switched with PWM0 frequency and duty cycle)<br>
					PWM1 (output is switched with PWM1 frequency and duty cycle)<br>
				</code>
				</ul>
			</li>
			<li>
				if <code>&lt;port&gt;</code> is PWM0 or PWM1, then <code>&lt;value&gt;</code> is an value between 0 and 255 and stands for the duty cycle of the PWM stage.
			</li>
			</ul>
		<br>
		Examples:
		<ul>
			<code>set mod1 Port4 PWM1</code><br>
			<code>set mod1 PWM1 128</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCA9532Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>

	<a name="I2C_PCA9532Attr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query the GPIO's level<br>
			Default: -, valid values: decimal number<br><br>
		</li>
		<li>InputPorts<br>
			Space separated list of Portnumers that are used as Inputs<br>
			Ports in this list can't be written<br>
			Default: no, valid values: 0 1 2 .. 15<br><br>
		</li>
		<li>T0/T1<br>
			Sets PWM0/PWM1 to another Frequency. The Formula is: Fx = 152/(Tx + 1) The corresponding frequency value is shown under internals.<br>
			Default: 0 (152Hz), valid values: 0-255<br><br>
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

<a name="I2C_PCA9532"></a>
<h3>I2C_PCA9532</h3>
<ul>
	<a name="I2C_PCA9532"></a>
		Erm&ouml;glicht die Verwendung eines PCA9532 I2C 16 Kanal PWM IC. 
		Das PCA9532 hat 2 unabh&auml;ngige PWM Stufen. Jeder Kanal kanne einer der Stufen zugeordnet werden oder direkt auf off/on gesetzt werden.
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_PCA9532Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCA9532 &lt;I2C Address&gt;</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ein zweistelliger Hex-Wert<br>
	</ul>

	<a name="I2C_PCA9532Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port&gt; &lt;value&gt;</code><br><br>
			<ul>
			<li>wenn als <code>&lt;port&gt;</code> Port0 bis Port15 verwendet wird, dann ist <code>&lt;value&gt;</code> einer dieser Werte:<br>
				<ul>
				<code>
					off<br>
					on<br>
					PWM0 (Port wird auf PWM0 Frequenz- und Pulsweiteneinstellung gesetzt)<br>
					PWM1 (Port wird auf PWM1 Frequenz- und Pulsweiteneinstellung gesetzt)<br>
				</code>
				</ul>
			</li>
			<li>
				wenn als <code>&lt;port&gt;</code> PWM0 oder PWM1 verwendet wird, ist <code>&lt;value&gt;</code> ein Wert zwischen 0 und 255 ensprechend der Pulsweite der PWM Stufe.
			</li>
			</ul>
		<br>
		Beispiele:
		<ul>
			<code>set mod1 Port4 PWM1</code><br>
			<code>set mod1 PWM1 128</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCA9532Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>

	<a name="I2C_PCA9532Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
		<li>InputPorts<br>
			Durch Leerzeichen getrennte Portnummern die als Inputs genutzt werden.<br>
			Ports in dieser Liste k&ouml;nnen nicht geschrieben werden.<br>
			Standard: no, g&uuml;ltige Werte: 0 1 2 .. 15<br><br>
		</li>
		<li>T0/T1<br>
			&Auml;nderung der Frequenzwerte von PWM0/PWM1 nach der Formel: Fx = 152/(Tx + 1). Der entsprechende Frequenzwert wird unter Internals angezeigt.<br>
			Standard: 0 (152Hz), g&uuml;ltige Werte: 0-255<br><br>
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