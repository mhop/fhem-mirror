##############################################################################
# $Id$
# 51_RPI_GPIO.pm
#
##############################################################################
# Modul for Raspberry Pi GPIO access
#
# define <name> RPI_GPIO <Pin>
# where <Pin> is one of RPi's GPIO 
#
# contributed by Klaus Wittstock (2013) email: klauswittstock bei gmail
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
use Scalar::Util qw(looks_like_number);
use IO::File;
use SetExtensions;

sub RPI_GPIO_fileaccess($$;$);

my $gpiodir = "";		#GPIO base directory
my @gpiodirs = ("/sys/class/aml_gpio", "/sys/class/gpio" );

my $gpioprg = "";		#WiringPi GPIO utility
my @gpioprgs = ("/usr/local/bin/gpio", "/usr/bin/gpio");

sub RPI_GPIO_Initialize($) {
	my ($hash) = @_;
	foreach (@gpioprgs) {
		if(-x $_) {
			$gpioprg = $_;
			Log3 undef, 4, "RPI_GPIO: wiringpi gpio utility exists: $gpioprg";
			last;
		} elsif (-e $_) {
			Log3 undef, 3, "RPI_GPIO: Attention, WiringPi gpio utility exists: $gpioprg but is not executable";
		}
	}
	foreach (@gpiodirs) {
		if(-e $_) {
			$gpiodir = $_;
			Log3 undef, 4, "RPI_GPIO: gpio directory exists: $gpiodir";
			last;
		} 
	}
	Log3 undef, 3, "RPI_GPIO: could not find gpio base directory, please add correct path in define" unless defined $gpiodir;
	Log3 undef, 4, "RPI_GPIO: could not find/use WiringPi gpio utility base directory" unless defined $gpioprg;
	
	$hash->{DefFn}    	= "RPI_GPIO_Define";
	$hash->{GetFn}    	= "RPI_GPIO_Get";
	$hash->{SetFn}    	= "RPI_GPIO_Set";
	$hash->{StateFn}  	= "RPI_GPIO_State";
	$hash->{AttrFn}   	= "RPI_GPIO_Attr";
	$hash->{ShutdownFn} = "RPI_GPIO_Shutdown";
	$hash->{UndefFn}  	= "RPI_GPIO_Undef";
	$hash->{ExceptFn} 	= "RPI_GPIO_Except";
	$hash->{AttrList}	= "poll_interval" .
						" direction:input,output pud_resistor:off,up,down" .
						" interrupt:none,falling,rising,both" .
						" toggletostate:no,yes active_low:no,yes" .
						" debounce_in_ms restoreOnStartup:no,yes,on,off,last" .
						" dblclicklevel:0,1 dblclicktime" .
						" unexportpin:no,yes longpressinterval" .
						" $readingFnAttributes";
}

my %setsoutp = (
'on:noArg' => 0,
'off:noArg' => 0,
'toggle:noArg' => 0,
);

my %setsinpt = (
'readValue:noArg' => 0,
);

sub RPI_GPIO_Define($$) {
 my ($hash, $def) = @_;
 my @args = split("[ \t]+", $def);
 my $menge = int(@args);
 if (int(@args) < 3)
 {
	return "Define: to less arguments. Usage:\n" .
				 "define <name> RPI_GPIO <GPIO>";
 }

 #Pruefen, ob GPIO bereits verwendet
 foreach my $dev (devspec2array("TYPE=$hash->{TYPE}")) {
	if ($args[2] eq InternalVal($dev,"GPIO_Nr","") && $hash->{NAME} ne InternalVal($dev,"NAME","") ) {
		return "GPIO $args[2] already used by $dev";
  }
 }
 
	my $name = $args[0];
	$hash->{GPIO_Nr} = $args[2];
 
	if ( defined $args[3] ) {
		return "unable to find gpio basedir $args[3]" unless (-e $args[3]);
		$hash->{GPIO_Basedir} = $args[3];
	} else {
		return "unable to find gpio basedir $gpiodir" unless defined $gpiodir;
		$hash->{GPIO_Basedir} = $gpiodir;
	}
 
	if ( defined $args[4] ) {
		return "unable to find wiringpi gpio utility: $gpioprg" unless (-e $args[4]);
		$hash->{WiringPi_gpio} = $args[4];
	} else {
		return "unable to find wiringpi gpio utility: $gpioprg" unless defined $gpioprg;
		$hash->{WiringPi_gpio} = $gpioprg;
	}
 
	$hash->{dir_not_set} = 1;
 
	if(-e "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}" && 
	   -w "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value" && 
	   -w "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/direction") {			#GPIO bereits exportiert?
		Log3 $hash, 4, "$name: gpio$hash->{GPIO_Nr} already exists";
		#nix tun...ist ja schon da
	} elsif (-w "$hash->{GPIO_Basedir}/export") {																																																					#gpio export Datei mit schreibrechten?
		Log3 $hash, 4, "$name: write access to file $hash->{GPIO_Basedir}/export, use it to export GPIO";
		my $exp = IO::File->new("> $hash->{GPIO_Basedir}/export");													#gpio ueber export anlegen 
		print $exp "$hash->{GPIO_Nr}";
		$exp->close;
	} else {
		if ( defined $hash->{WiringPi_gpio} ) {																		#GPIO Utility Vorhanden?
			Log3 $hash, 4, "$name: using gpio utility to export pin";
			RPI_GPIO_exuexpin($hash, "in");
		} else {																									#Abbbruch da kein gpio utility vorhanden
			my $msg = "$name: can't export gpio$hash->{GPIO_Nr}, no write access to $hash->{GPIO_Basedir}/export and WiringPi gpio utility not (correct) installed";
			Log3 $hash, 1, $msg;
			return $msg;
		}
	}
 
 # wait for Pin export (max 5s)
 my $checkpath = qq($hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value);
 my $counter = 100;
 while( $counter ){
 	last if( -e $checkpath && -w $checkpath );
 	Time::HiRes::sleep( 0.05 );
 	$counter --;
 }
 unless( $counter ) {																												# nur wenn export fehlgeschlagen
 	# nochmal probieren wenn keine Schreibrechte auf GPIO Dateien ##########
 	if ( defined $hash->{WiringPi_gpio} ) {							# nutze GPIO Utility fuer zweiten Exportversuch
		Log3 $hash, 4, "$name: using gpio utility to export pin (first export via $hash->{GPIO_Basedir}/export failed)";
		RPI_GPIO_exuexpin($hash, "in");
	} else {														# Abbbruch da kein gpio utility vorhanden
		Log3 $hash, 1, "$name: second attempt to export gpio$hash->{GPIO_Nr} also failed: WiringPi gpio utility not (correct) installed, possibly reasons for first fail:";
 		if ( -e "$hash->{GPIO_Basedir}/export") {
  			Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/export\" exists and is " . ( ( -w "$hash->{GPIO_Basedir}/export") ? "" : "NOT " ) . "writable";
		} else {
 			Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/export\" doesnt exist";
		}
		if(-e "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}") {
			Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}\" exported but define aborted:";
			if ( -e "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value") {
				Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value\" exists and is " . ( ( -w "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value") ? "" : "NOT " ) . "writable";
			} else {
				Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/value\" doesnt exist";
			}
			if ( -e "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/direction") {
				Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/direction\" exists and is " . ( ( -w "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/direction") ? "" : "NOT " ) . "writable";
			} else {
				Log3 $hash, 1, "$name: \"$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/direction\" doesnt exist";
			}
		}
       	return "$name: failed to export pin gpio$hash->{GPIO_Nr}, see logfile";						
	}
 }

 $hash->{fhem}{interfaces} = "switch";
 return undef;
}

sub RPI_GPIO_Get($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	#my $dir = $attr{$hash->{NAME}}{direction} || "output";
	my $dir = "";
	my $zustand = undef;
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ( defined ($val) ) {
		if ( $val == 1) {
			if ($dir eq "output") {$zustand = "on";} else {$zustand = "high";}
		} elsif ( $val == 0 ) {
			if ($dir eq "output") {$zustand = "off";} else {$zustand = "low";}
		}
	} else { 
		Log3 $hash, 1, "$hash->{NAME} GetFn: readout of Pinvalue fail"; 
	}
	$hash->{READINGS}{Pinlevel}{VAL} = $zustand;
	$hash->{READINGS}{Pinlevel}{TIME} = TimeNow();
	return "Current Value for $name: $zustand";
}

sub RPI_GPIO_Set($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
	my $mt = AttrVal($name, 'direction', 'input');
	if($mt && $mt eq "output") {
		if ($cmd eq 'on') {
			RPI_GPIO_fileaccess($hash, "value", "1");
			readingsSingleUpdate($hash, 'state', $cmd, 1);
		} elsif ($cmd eq 'off') {
			RPI_GPIO_fileaccess($hash, "value", "0");
			readingsSingleUpdate($hash, 'state', $cmd, 1);
		} else {
			my $slist = join(' ', keys %setsoutp);
			Log3 $hash, 5, "wird an setextensions gesendet: @a";
			return SetExtensions($hash, $slist, @a);
		}
	} elsif ($mt && $mt eq "input") {
		if ($cmd eq 'readValue') {
			RPI_GPIO_updatevalue($hash);
		} else {
			return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %setsinpt)
		}
	}
	return undef;
}

sub RPI_GPIO_State($$$$) {	#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";

	if ( $sname ne "STATE" && AttrVal($hash->{NAME},"restoreOnStartup","last") ne "no") {
		if (AttrVal($hash->{NAME},"direction","") eq "output") {
			$hash->{READINGS}{$sname}{VAL} = $sval;
			$hash->{READINGS}{$sname}{TIME} = $tim;
			Log3 $hash, 4, "OUTPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";
			if ($sname eq "state") {
				my $rval = AttrVal($hash->{NAME},"restoreOnStartup","last");
				$rval = "last" if ( $rval ne "on" && $rval ne "off" );
				$sval = $rval eq "last" ? $sval : $rval;
				#RPI_GPIO_Set($hash,$hash->{NAME},$sname,$sval);
				RPI_GPIO_Set($hash,$hash->{NAME},$sval);
				Log3 $hash, 4, "OUTPUT $hash->{NAME}: STATE wiederhergestellt auf $sval (restoreOnStartup=$rval)";
			} 
		} elsif ( AttrVal($hash->{NAME},"direction","") eq "input") {
			if ($sname eq "Toggle") {
				#wenn restoreOnStartup "on" oder "off" und der Wert mit dem im Statefile uebereinstimmt wird der Zeitstempel aus dem Statefile gesetzt
				my $rval = AttrVal($hash->{NAME},"restoreOnStartup","last");
				$rval = "last" if ( $rval ne "on" && $rval ne "off" );
				$tim  = gettimeofday() if $rval ne "last" && $rval ne $sval;
				$sval = $rval eq "last" ? $sval : $rval;
		
				$hash->{READINGS}{$sname}{VAL} = $sval;
				$hash->{READINGS}{$sname}{TIME} = $tim;
				Log3 $hash, 4, "INPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";
				#RPI_GPIO_Set($hash,$hash->{NAME},$sval);
				if ((AttrVal($hash->{NAME},"toggletostate","") eq "yes")) {
					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, 'state', $sval);
					readingsEndUpdate($hash, 1);
					Log3 $hash, 4, "INPUT $hash->{NAME}: STATE wiederhergestellt auf $sval";
				}
			} elsif ($sname eq "Counter") {
          		$hash->{READINGS}{$sname}{VAL} = $sval;
          		$hash->{READINGS}{$sname}{TIME} = $tim;
          		Log3 $hash, 4, "INPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";	
			} elsif ( ($sname eq "state") && (AttrVal($hash->{NAME},"toggletostate","") ne "yes") ) {
          		#my $rval = AttrVal($hash->{NAME},"restoreOnStartup","");
          		#if ($rval eq "" && (AttrVal($hash->{NAME},"toggletostate","") ne "yes") ) {
           		Log3 $hash, 4, "INPUT $hash->{NAME}: alter Pinwert war: $sval";
            	my $val = RPI_GPIO_fileaccess($hash, "value");
           		$val = $val eq "1" ? "on" :"off";
           		Log3 $hash, 4, "INPUT $hash->{NAME}: aktueller Pinwert ist: $val";
           		if ($val ne $sval) {
              		Log3 $hash, 4, "INPUT $hash->{NAME}: Pinwerte ungleich...Timer gesetzt";
              		InternalTimer(gettimeofday() + (10), 'RPI_GPIO_Poll', $hash, 0);
           		} else {
              		$hash->{READINGS}{$sname}{VAL} = $sval;
              		$hash->{READINGS}{$sname}{TIME} = $tim;
           		}
      		}
		}
	}
	return;
}

sub RPI_GPIO_Attr(@) {
	my (undef, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = '';
 
	if ($attr eq 'poll_interval') {
		if ( defined($val) ) {
			if ( looks_like_number($val) && $val > 0) {
				RemoveInternalTimer($hash);
				InternalTimer(1, 'RPI_GPIO_Poll', $hash, 0);
			} else {
			$msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
			}
		} else { #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
			RemoveInternalTimer($hash);
		}
	}
	if ($attr eq 'longpressinterval') {
		if ( defined($val) ) {
			unless ( looks_like_number($val) && $val >= 0.1 && $val <= 10 ) {
				$msg = "$hash->{NAME}: Wrong longpress time defined. Value must be a number between 0.1 and 10";
			}
		} 
	}
	if ($attr eq 'direction') {
		if (!$val) { #$val nicht definiert: Einstellungen loeschen
			$msg = "$hash->{NAME}: no direction value. Use input output";
		} elsif ($val eq "input") {
			delete($hash->{dir_not_set});
			RPI_GPIO_fileaccess($hash, "direction", "in");
			#RPI_GPIO_exuexpin($hash, "in");
			Log3 $hash, 5, "$hash->{NAME}: set attr direction: input"; 
		} elsif( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
			$msg = "$hash->{NAME}: Delete attribute interrupt or set it to none for output direction"; 
		} elsif ($val eq "output") {
			unless ($hash->{dir_not_set}) {							#direction bei output noch nicht setzten (erfolgt bei erstem schreiben vom Wert um kurzes umschalten beim fhem start zu unterbinden)
				RPI_GPIO_fileaccess($hash, "direction", "out");
				#RPI_GPIO_exuexpin($hash, "out");
				Log3 $hash, 5, "$hash->{NAME}: set attr direction: output";
			} else {
				Log3 $hash, 5, "$hash->{NAME}: set attr direction: output vorerst NICHT";
			}
		} else {
			$msg = "$hash->{NAME}: Wrong $attr value. Use input output";
		}
	}
	if ($attr eq 'interrupt') {
    if ( !$val || ($val eq "none") ) {
      RPI_GPIO_fileaccess($hash, "edge", "none");
      RPI_GPIO_inthandling($hash, "stop");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: none"; 
    } elsif (( AttrVal($hash->{NAME}, "direction", "output") ) eq ( "output" )) {
      $msg = "$hash->{NAME}: Wrong direction value defined for interrupt. Use input";
    } elsif ($val eq "falling") {
      RPI_GPIO_fileaccess($hash, "edge", "falling");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: falling"; 
    } elsif ($val eq "rising") {
      RPI_GPIO_fileaccess($hash, "edge", "rising");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: rising";  
    } elsif ($val eq "both") {
      RPI_GPIO_fileaccess($hash, "edge", "both");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: both";  
    } else {
      $msg = "$hash->{NAME}: Wrong $attr value. Use none, falling, rising or both";
    }  
  }
	if ($attr eq 'toggletostate') {			# Tastfunktion: bei jedem Tastendruck wird State invertiert
		unless ( !$val || ($val eq ("yes" || "no") ) ) {
		$msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
		}
	}
	if ($attr eq 'active_low') {			# invertierte Logik 
		if ( !$val || ($val eq "no" ) ) {
		  RPI_GPIO_fileaccess($hash, "active_low", "0");
		  Log3 $hash, 5, "$hash->{NAME}: set attr active_low: no"; 
		} elsif ($val eq "yes") {
		  RPI_GPIO_fileaccess($hash, "active_low", "1");
		  Log3 $hash, 5, "$hash->{NAME}: set attr active_low: yes";
		} else {
		  $msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
		}
	}
	if ($attr eq 'debounce_in_ms') {		# Entprellzeit
		if ( $val && ( ($val > 250) || ($val < 0) ) ) {
		  $msg = "$hash->{NAME}: debounce_in_ms value to big. Use 0 to 250";
		}
	}
	if ($attr eq "pud_resistor" && $val) {	# interner pullup/down Widerstand
		if($val =~ /^(off|up|down)$/) {
			if(-w "$hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr}/pull") {
				$val =~ s/off/disable/;
				RPI_GPIO_fileaccess($hash, "pull", $val);
			} else { #nur fuer Raspberry (ueber gpio utility)
				#my $pud;
				if ( defined $hash->{WiringPi_gpio} ) {
					$val =~ s/off/tri/;
					RPI_GPIO_exuexpin($hash, $val);
				} else {
					my $ret = "$hash->{NAME}: unable to change pud resistor: WiringPi gpio utility not (correct) installed";
					Log3 $hash, 1, $ret;
					return $ret;
				}
			}
		} else {
			$msg = "$hash->{NAME}: Wrong $attr value. Use off, up or down";
		}
	}
	return ($msg) ? $msg : undef; 
}

sub RPI_GPIO_Poll($) {		#for attr poll_intervall -> readout pin value
	my ($hash) = @_;
	my $name = $hash->{NAME};
	RPI_GPIO_updatevalue($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'RPI_GPIO_Poll', $hash, 0);
	}
	return;
} 

sub RPI_GPIO_Shutdown($$) {
	my ($hash, $arg) = @_;
	if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {			# remove internal timer
		RemoveInternalTimer($hash);
	}
	if ( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {		# detach interrupt
		delete $selectlist{$hash->{NAME}};
		close($hash->{filehandle});
		Log3 $hash, 5, "$hash->{NAME}: interrupt detached";	
	}	
	# to have a chance to externaly setup the GPIOs -
	# leave GPIOs untouched if attr unexportpin is set to "no"
	# only delete inputs (otherwise outputs will flicker during restart of FHEM)
	if( AttrVal($hash->{NAME},"direction","") ne "output" and AttrVal($hash->{NAME},"unexportpin","") ne "no" ) {
		if (-w "$hash->{GPIO_Basedir}/unexport") {# unexport if write access to unexport
			my $uexp = IO::File->new("> $hash->{GPIO_Basedir}/unexport");
			print $uexp "$hash->{GPIO_Nr}";
			$uexp->close;
		} else {# else use gpio utility
			RPI_GPIO_exuexpin($hash, "unexport");
		}
		Log3 $hash, 5, "$hash->{NAME}: gpio$hash->{GPIO_Nr} removed";
	}

	return undef;	
}

sub RPI_GPIO_Undef($$) {
	my ($hash, $arg) = @_;
	if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
		RemoveInternalTimer($hash);
	}
	if ( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
		delete $selectlist{$hash->{NAME}};
		close($hash->{filehandle}) if defined $hash->{filehandle};
	}
	# to have a chance to externaly setup the GPIOs -
	# leave GPIOs untouched if attr unexportpin is set to "no"
	if(AttrVal($hash->{NAME},"unexportpin","") ne "no") {
		if (-w "$hash->{GPIO_Basedir}/unexport") {#unexport Pin alte Version
			my $uexp = IO::File->new("> $hash->{GPIO_Basedir}/unexport");
			print $uexp "$hash->{GPIO_Nr}";
			$uexp->close;
		} else {#alternative unexport Pin:
			RPI_GPIO_exuexpin($hash, "unexport");
		}
	}
	Log3 $hash, 4, "$hash->{NAME}: entfernt";
	return undef;
}

sub RPI_GPIO_Except($) {	#called from main if an interrupt occured 
	my ($hash) = @_;
	#seek($hash->{filehandle},0,0);								#an Anfang der Datei springen (ist noetig falls vorher schon etwas gelesen wurde)
	#chomp ( my $firstval = $hash->{filehandle}->getline );		#aktuelle Zeile auslesen und Endezeichen entfernen
	#my $acttime = gettimeofday();
	my $eval = RPI_GPIO_fileaccess($hash, "edge");							#Eintstellung Flankensteuerung auslesen
	my ($valst, $valalt, $valto, $valcnt, $vallp) = undef;
	my $debounce_time = AttrVal($hash->{NAME}, "debounce_in_ms", "0"); #Wartezeit zum entprellen
	if( $debounce_time ne "0" ) {
		$debounce_time /= 1000;
		Log3 $hash, 4, "Wartezeit: $debounce_time ms"; 
		select(undef, undef, undef, $debounce_time);
	}

	seek($hash->{filehandle},0,0);								#an Anfang der Datei springen (ist noetig falls vorher schon etwas gelesen wurde)
	chomp ( my $val = $hash->{filehandle}->getline );				#aktuelle Zeile auslesen und Endezeichen entfernen

	if ( ( $val == 1) && ( $eval ne ("falling") ) ) {
		$valst = "on";
		$valalt = "high";
	} elsif ( ( $val == 0 ) && ($eval ne "rising" ) ) {
		$valst = "off";
		$valalt = "low";
	}
	if ( ( ($eval eq "rising") && ( $val == 1 ) ) || ( ($eval eq "falling") && ( $val == 0 ) ) ) {	#nur bei Trigger auf steigende / fallende Flanke
		#Togglefunktion
		if (!defined($hash->{READINGS}{Toggle}{VAL})) {			#Togglewert existiert nicht -> anlegen
			Log3 $hash, 5, "Toggle war nicht def";
			$valto = "on";
		} elsif ( $hash->{READINGS}{Toggle}{VAL} eq "off" ) {		#Togglewert invertieren
			Log3 $hash, 5, "Toggle war auf $hash->{READINGS}{Toggle}{VAL}";
			$valto = "on";
		} else {
			Log3 $hash, 5, "Toggle war auf $hash->{READINGS}{Toggle}{VAL}";
			$valto = "off";
		}
		Log3 $hash, 5, "Toggle ist jetzt $valto";
		if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "yes" )) {	#wenn Attr "toggletostate" gesetzt auch die Variable fuer den STATE wert setzen
			$valst = $valto;
		}
		#Zaehlfunktion
		if (!defined($hash->{READINGS}{Counter}{VAL})) {			#Zaehler existiert nicht -> anlegen
			Log3 $hash, 5, "Zaehler war nicht def";
			$valcnt = "1";
		} else {
			$valcnt = $hash->{READINGS}{Counter}{VAL} + 1;
			Log3 $hash, 5, "Zaehler ist jetzt $valcnt";
		}
		#Doppelklick (noch im Teststatus)
		if (defined($hash->{lasttrg})) {
			my $testtt = (gettimeofday() - $hash->{lasttrg} );
			readingsSingleUpdate($hash, 'Dblclick', "on", 1) if $testtt < 2;
		}
		$hash->{lasttrg} = gettimeofday();
	#langer Testendruck
	} elsif ($eval eq "both") {
		if ( $val == 1 ) {
			my $lngpressInterval = AttrVal($hash->{NAME}, "longpressinterval", "1");
			InternalTimer(gettimeofday() + $lngpressInterval, 'RPI_GPIO_longpress', $hash, 0);
		} else {
			RemoveInternalTimer('RPI_GPIO_longpress');
			$vallp = 'off';
		}
		#Doppelklick (noch im Teststatus)
		if ( $val == AttrVal($hash->{NAME}, "dblclicklevel", "1") ) {
			if (defined $hash->{lasttrg}) {
				my $testtt = (gettimeofday() - $hash->{lasttrg} );
				readingsSingleUpdate($hash, 'Dblclick', "on", 1) if $testtt < int(AttrVal($hash->{NAME}, "dblclicktime", 2));
			}
			$hash->{lasttrg} = gettimeofday();
		} else {
			readingsSingleUpdate($hash, 'Dblclick', "off", 1);
		}
	}

	delete ($hash->{READINGS}{Toggle})    if ($eval ne ("rising" || "falling"));		#Reading Toggle loeschen wenn Edge weder "rising" noch "falling"
	delete ($hash->{READINGS}{Longpress}) if ($eval ne "both");					#Reading Longpress loeschen wenn edge nicht "both"
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'Pinlevel',  $valalt);
	readingsBulkUpdate($hash, 'state',     $valst);
	readingsBulkUpdate($hash, 'Toggle',    $valto)  if ($valto);
	readingsBulkUpdate($hash, 'Counter',   $valcnt) if ($valcnt);
	readingsBulkUpdate($hash, 'Longpress', $vallp)  if ($vallp);
	readingsEndUpdate($hash, 1);
	#Log3 $hash, 5, "RPIGPIO: Except ausgeloest: $hash->{NAME}, Wert: $val, edge: $eval,vt: $valto, $debounce_time s: $firstval";
}

sub RPI_GPIO_longpress($) {			#for reading longpress
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ($val == 1) {
		readingsSingleUpdate($hash, 'Longpress', 'on', 1);
	}
}

sub RPI_GPIO_dblclick($) {

}

sub RPI_GPIO_updatevalue($) {						#update value for Input devices
	my ($hash) = @_;
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ( defined ($val) ) {
		my ($valst, $valalt) = undef;
		if ( $val == 1) {
			$valst = "on";
			$valalt = "high";
		} elsif ( $val == 0 ) {
			$valst = "off";
			$valalt = "low";
		}
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'Pinlevel', $valalt);
		readingsBulkUpdate($hash, 'state', $valst) if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "no" ));
		readingsEndUpdate($hash, 1);
	} else {
	Log3 $hash, 1, "$hash->{NAME}: readout of Pinvalue fail";
	}
}

sub RPI_GPIO_fileaccess($$;$) {						#Fileaccess for GPIO base directory
	my ($hash, @args) = @_;
	my $fname = $args[0];
	my $pinroot = qq($hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr});
	my $file =qq($pinroot/$fname);
	Log3 $hash, 5, "$hash->{NAME}, in fileaccess: $fname " . (defined($args[1])?$args[1]:"");

	if ($hash->{dir_not_set} && $fname eq "value") {			#direction setzen (bei output direkt status mit schreiben)
		delete($hash->{dir_not_set});
		my $dir = AttrVal($hash->{NAME},"direction","input");
		$dir = $dir eq "input" ? "in" : "out";
		if ($dir eq "out" && $fname eq "value" && defined($args[1])) {
			my $al = AttrVal($hash->{NAME},"active_low","no");
			my $lev = $al eq "yes" ? 0 : 1;
			$dir = ($args[1] == $lev ? "high" : "low")
		} 
		#$dir = ($args[1] == 1 ? "high" : "low") if ($dir eq "out" && $fname eq "value" && defined($args[1]));
		RPI_GPIO_fileaccess($hash, "direction", $dir);
		Log3 $hash, 4, "$hash->{NAME}: direction gesetzt auf $dir";
	}

	if (int(@args) < 2){
		my $fh = IO::File->new("< $file");
		if (defined $fh) {
			chomp ( my $pinvalue = $fh->getline );
			$fh->close;
			return $pinvalue;
		} else {
			Log3 $hash, 1, "Can't open file: $hash->{NAME}, $fname";
		}
	} else {
		my $value = $args[1];
		if ($fname eq "direction" && (not -w $file)) {		#wenn direction und diese nicht schreibbar mit gpio utility versuchen
			Log3 $hash, 4, "$hash->{NAME}: direction ueber gpio utility einstellen";
			RPI_GPIO_exuexpin($hash, $value);
		} else {
			my $fh = IO::File->new("> $file");
			if (defined $fh) {
				print $fh "$value";
				$fh->close;
			} else {
				Log3 $hash, 1, "Can't open file: $hash->{NAME}, $fname";
			}
		}
	}
}
	
sub RPI_GPIO_exuexpin($$) {			#export, unexport, direction, pud_resistor via GPIO utility
	my ($hash, $dir) = @_;
	my $gpioutility = $hash->{WiringPi_gpio};
	if ( defined $hash->{WiringPi_gpio} ) {
		my $sw;
		if ($dir eq "unexport") {
			$sw = $dir;
			$dir = "";
		} elsif ($dir eq "up" || $dir eq "down"|| $dir eq "tri") {
			$sw = "-g mode";
		} else {
			$sw = "export";
			#$dir = "out" if ( $dir eq "high" || $dir eq "low" );		#auf out zurueck, da gpio tool dies nicht unterst?tzt
		}
		#my $exp = $gpioutility.' '.$sw.' '.$hash->{GPIO_Nr}. (defined $dir ? " " . $dir : "");
		#$exp = `$exp`;
		my $exp = "$gpioutility $sw $hash->{GPIO_Nr} $dir";
		my $exp_result = `$exp 2>&1`;

		if ($exp_result =~ /export: Invalid mode/) {
			#gpio tool in neueren versionen (>= 2.25, feb 2015) unterstützt beim export high/low argumente. 
			#das verhindert kurzes flickern beim restart von fhem.
			#fallback auf alte syntax wenn utility "Invalid mode" retourniert
			
			Log3 $hash, 2, "$hash->{NAME}: WiringPi alte version erkannt. '$exp' $exp_result";

			$exp = "$gpioutility $sw $hash->{GPIO_Nr} out"; 			#fallback auf out in alter version
			$exp_result = `$exp 2>&1`
		}
		Log3 $hash, 4, "$hash->{NAME}: WiringPi executed: '$exp' $exp_result";
	} else {
		my $ret = "WiringPi gpio utility not (correct) installed";
		Log3 $hash, 1, "$hash->{NAME}: $ret";
		return $ret;
	}
}

sub RPI_GPIO_inthandling($$) {		#start/stop Interrupthandling
	my ($hash, $arg) = @_;
	my $msg = '';
	if ( $arg eq "start") {
		#FH fuer value-datei
		my $pinroot = qq($hash->{GPIO_Basedir}/gpio$hash->{GPIO_Nr});
		my $valfile = qq($pinroot/value);
		$hash->{filehandle} = IO::File->new("< $valfile"); 
		if (!defined $hash->{filehandle}) {
			$msg = "Can't open file: $hash->{NAME}, $valfile";
		} else {
			$selectlist{$hash->{NAME}} = $hash;
			$hash->{EXCEPT_FD} = fileno($hash->{filehandle});
			my $pinvalue = $hash->{filehandle}->getline;
			Log3 $hash, 5, "Datei: $valfile, FH: $hash->{filehandle}, EXCEPT_FD: $hash->{EXCEPT_FD}, akt. Wert: $pinvalue";
		}
	} else {
		delete $selectlist{$hash->{NAME}};
		close($hash->{filehandle});
	}
}

1;

=pod
=item device
=item summary controls/reads GPIO pins accessible via sysfs on linux
=item summary_DE steuern/lesen von GPIO Pins &uuml;ber sysfs auf Linux Systemen
=begin html

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
(en | <a href="commandref_DE.html#RPI_GPIO">de</a>)
<ul>
	<a name="RPI_GPIO"></a>
		Raspberry Pi offers direct access to several GPIO via header P1 (and P5 on V2). The Pinout is shown in table under define. 
		With this module you are able to access these GPIO's directly as output or input. For input you can use either polling or interrupt mode<br>
		In addition to the Raspberry Pi, also BBB, Cubie, Banana Pi and almost every linux system which provides gpio access in userspace is supported.<br>
		<b>Warning: Never apply any external voltage to an output configured pin! GPIO's internal logic operate with 3,3V. Don't exceed this Voltage!</b><br><br>
		<b>preliminary:</b><br>
		GPIO Pins accessed by sysfs. The files are located in folder <code>/system/class/gpio</code> and belong to the gpio group (on actual Raspbian distributions since jan 2014). It will work even on an Jessie version but NOT if you perform an kerlen update<br>
		After execution of following commands, GPIO's are usable whithin PRI_GPIO:<br>
		<ul><code>
			sudo adduser fhem gpio<br>
			sudo reboot
		</code></ul><br>
		If attribute <code>pud_resistor</code> shall be used and on older Raspbian distributions, aditionally gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a>
		library must be installed to set the internal pullup/down resistor or export and change access rights of GPIO's (for the second case active_low does <b>not</b> work).<br>
		Installation WiringPi:<br>
		<ul><code>
			sudo apt-get update<br>
			sudo apt-get upgrade<br>
			sudo apt-get install git-core<br>
			git clone git://git.drogon.net/wiringPi<br>
			cd wiringPi
			./build
		</code></ul><br>
	On Linux systeme where <code>/system/class/gpio</code> can only accessed as root, GPIO's must exported and their access rights changed before FHEM starts.<br>
	This can be done in <code>/etc/rc.local</code> (Examole for GPIO22 and 23):<br>
	<ul><code>
		echo 22 > /sys/class/gpio/export<br>
		echo 23 > /sys/class/gpio/export<br>
		chown -R fhem:root /sys/devices/virtual/gpio/* (or chown -R fhem:gpio /sys/devices/platform/gpio-sunxi/gpio/* for Banana Pi)<br>
		chown -R fhem:root /sys/class/gpio/*<br>
	</code></ul><br>
	<a name="RPI_GPIODefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> RPI_GPIO &lt;GPIO number&gt;[ &lt;GPIO-Basedir&gt;[ &lt;WiringPi-gpio-utility&gt;]]</code><br><br>
		all usable <code>GPIO number</code> can be found <a href="http://www.panu.it/raspberry/">here</a><br><br>
		
    Examples:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12 poll_interval 5
	  define Pin12 RPI_GPIO 18 /sys/class/gpio /usr/somewhere/bin/gpio
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><li>for output configured GPIO
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      The <a href="#setExtensions"> set extensions</a> are also supported.<br>
      </li>
      <li>for input configured GPIO
      <ul><code>
        readval		
      </code></ul>
      readval refreshes the reading Pinlevel and, if attr toggletostate not set, the state value
    </ul>   
    </li><br>
     Examples:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    returns "high" or "low" regarding the actual status of the pin and writes this value to reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Sets the GPIO direction to input or output.<br>
      Default: input, valid values: input, output<br><br>
    </li>
    <li>active_low<br>
      Inverts logical value<br>
      Default: off, valid values: on, off<br><br>
    </li>    
    <li>interrupt<br>
      <b>can only be used with GPIO configured as input</b><br>
      enables edge detection for GPIO pin<br>
      on each interrupt event readings Pinlevel and state will be updated<br>
      Default: none, valid values: none, falling, rising, both<br>
	  For "both" the reading Longpress will be added and set to on as long as kes hold down longer than 1s<br>
	  For "falling" and "rising" the reading Toggle will be added an will be toggled at every interrupt and the reading Counter that increments at every interrupt<br><br>
    </li>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the GPIO's level<br>
      Default: -, valid values: decimal number<br><br>
    </li>
    <li>toggletostate<br>
      <b>works with interrupt set to falling or rising only</b><br>
      if yes, state will be toggled at each interrupt event<br>
      Default: no, valid values: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Sets the internal pullup/pulldown resistor<br>
	  <b>Works only with installed gpio urility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Library.</b><br>
      Default: -, valid values: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      readout of pin value x ms after an interrupt occured. Can be used for switch debouncing<br>
      Default: 0, valid values: decimal number<br><br>
    </li>
    <li>restoreOnStartup<br>
      Restore Readings and sets after reboot<br>
      Default: last, valid values: last, on, off, no<br><br>
    </li>
    <li>unexportpin<br>
      do an unexport to /sys/class/gpio/unexport if the pin definition gets cleared (e.g. by rereadcmd, delete,...)<br>
      Default: yes, valid values: yes, no<br><br>
    </li>
    <li>longpressinterval<br>
      <b>works with interrupt set to both only</b><br>
      time in seconds, a port need to be high to set reading longpress to on<br>
      Default: 1, valid values: 0.1 - 10<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html

=begin html_DE

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
(<a href="commandref.html#RPI_GPIO">en</a> | de)
<ul>
  <a name="RPI_GPIO"></a>
    Das Raspberry Pi erm&ouml;glicht direkten Zugriff zu einigen GPIO's &uuml;ber den Pfostenstecker P1 (und P5 bei V2). Die Steckerbelegung ist in den Tabellen unter Define zu finden.
    Dieses Modul erm&ouml;glicht es, die herausgef&uuml;hrten GPIO's direkt als Ein- und Ausgang zu benutzen. Die Eing&auml;nge k&ouml;nnen zyklisch abgefragt werden oder auch sofort bei Pegelwechsel gesetzt werden.<br>
		Neben dem Raspberry Pi k&ouml;nnen auch die GPIO's von BBB, Cubie, Banana Pi und jedem Linuxsystem, das diese im Userspace zug&auml;gig macht, genutzt werden.<br>
    <b>Wichtig: Niemals Spannung an einen GPIO anlegen, der als Ausgang eingestellt ist! Die interne Logik der GPIO's arbeitet mit 3,3V. Ein &uuml;berschreiten der 3,3V zerst&ouml;rt den GPIO und vielleicht auch den ganzen Prozessor!</b><br><br>
    <b>Vorbereitung:</b><br>
		Auf GPIO Pins wird im Modul &uuml;ber sysfs zugegriffen. Die Dateien befinden sich unter <code>/system/class/gpio</code> und sind in der aktuellen Raspbian Distribution (ab Jan 2014) in der Gruppe gpio. Es funktioniert auch mit der Jessie Version. Allerdings NICHT wenn ein Kernelupgrade durchgef&uuml;hrt wird<br>
		Nach dem ausf&uuml;hren folgender Befehle sind die GPIO's von PRI_GPIO aus nutzbar:<br>
		<ul><code>
			sudo adduser fhem gpio<br>
			sudo reboot
		</code></ul><br>
		Wenn das Attribut <code>pud_resistor</code> verwendet werden soll und f&uuml;r &auml;ltere Raspbian Distributionen, muss zus&auml;tzlich das gpio Tool der <a href="http://wiringpi.com/download-and-install/">WiringPi</a>
		Bibliothek installiert werden, um den internen Pullup/down Widerstand zu aktivieren, bzw. GPIO's zu exportieren und die korrekten Nutzerrechte zu setzen (f&uuml;r den zweiten Fall funktioniert das active_low Attribut <b>nicht</b>).<br>
		Installation WiringPi:<br>
		<ul><code>
			sudo apt-get update<br>
			sudo apt-get upgrade<br>
			sudo apt-get install git-core<br>
			git clone git://git.drogon.net/wiringPi<br>
			cd wiringPi
			./build
  	</code></ul><br>
		F&uuml;r Linux Systeme bei denen der Zugriff auf <code>/system/class/gpio</code> nur mit root Rechten erfolgen kann, m&uuml;ssen die GPIO's vor FHEM start exportiert und von den Rechten her angepasst werden.<br>
		Dazu in die <code>/etc/rc.local</code> folgendes einf&uuml;gen (Beispiel f&uuml;r GPIO22 und 23):<br>
		<ul><code>
			echo 22 > /sys/class/gpio/export<br>
			echo 23 > /sys/class/gpio/export<br>
			chown -R fhem:root /sys/devices/virtual/gpio/* (oder chown -R fhem:gpio /sys/devices/platform/gpio-sunxi/gpio/* f&uuml;r Banana Pi)<br>
			chown -R fhem:root /sys/class/gpio/*<br>
		</code></ul><br>
	<a name="RPI_GPIODefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RPI_GPIO &lt;GPIO number&gt;[ &lt;GPIO-Basedir&gt;[ &lt;WiringPi-gpio-utility&gt;]]</code><br><br>
    Alle verf&uuml;gbaren <code>GPIO number</code> sind z.B. <a href="http://www.panu.it/raspberry/">hier</a> zu finden<br><br>
     
    Beispiele:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12 poll_interval 5
	  define Pin12 RPI_GPIO 18 /sys/class/gpio /usr/somewhere/bin/gpio
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    <code>value</code> ist dabei einer der folgenden Werte:<br>
    <ul><li>F&uuml;r GPIO der als output konfiguriert ist
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      Die <a href="#setExtensions"> set extensions</a> werden auch unterst&uuml;tzt.<br>
      </li>
      <li>F&uuml;r GPIO der als input konfiguriert ist
      <ul><code>
        readval		
      </code></ul>
      readval aktualisiert das reading Pinlevel und, wenn attr toggletostate nicht gesetzt ist, auch state
    </ul>   
    </li><br>
     Beispiele:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    Gibt "high" oder "low" entsprechend dem aktuellen Pinstatus zur&uuml;ck und schreibt den Wert auch in das reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Setzt den GPIO auf Ein- oder Ausgang.<br>
      Standard: input, g&uuml;ltige Werte: input, output<br><br>
    </li>
    <li>active_low<br>
      Invertieren des logischen Wertes<br>
      Standard: off, g&uuml;ltige Werte: on, off<br><br>
    </li>  
    <li>interrupt<br>
      <b>kann nur gew&auml;hlt werden, wenn der GPIO als Eingang konfiguriert ist</b><br>
      Aktiviert Flankenerkennung f&uuml;r den GPIO<br>
      bei jedem interrupt Ereignis werden die readings Pinlevel und state aktualisiert<br>
      Standard: none, g&uuml;ltige Werte: none, falling, rising, both<br><br>
	  Bei "both" wird ein reading Longpress angelegt, welches auf on gesetzt wird solange der Pin l&auml;nger als 1s gedr&uuml;ckt wird<br>
	  Bei "falling" und "rising" wird ein reading Toggle angelegt, das bei jedem Interruptereignis toggelt und das Reading Counter, das bei jedem Ereignis um 1 hochz&auml;hlt<br><br>

    </li>
    <li>poll_interval<br>
      Fragt den Zustand des GPIO regelm&auml;&szlig;ig ensprechend des eingestellten Wertes in Minuten ab<br>
      Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>toggletostate<br>
      <b>Funktioniert nur bei auf falling oder rising gesetztem Attribut interrupt</b><br>
      Wenn auf "yes" gestellt wird bei jedem Triggerereignis das <b>state</b> reading invertiert<br>
      Standard: no, g&uuml;ltige Werte: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Interner Pullup/down Widerstand<br>
	  <b>Funktioniert ausslie&szlig;lich mit installiertem gpio Tool der <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Bibliothek.</b><br>
      Standard: -, g&uuml;ltige Werte: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      Wartezeit in ms bis nach ausgel&ouml;stem Interrupt der entsprechende Pin abgefragt wird. Kann zum entprellen von mechanischen Schaltern verwendet werden<br>
      Standard: 0, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>unexportpin<br>
      F&uuml;hre unexport &uuml;ber /sys/class/gpio/unexport aus wenn die Pin-Definition gel&ouml;scht wird (z.B. durch rereadcfg, delete,...)<br>
      Standard: yes, , g&uuml;ltige Werte: yes, no<br><br>
    </li>
    <li>restoreOnStartup<br>
      Wiederherstellen der Portzust&auml;nde nach Neustart<br>
      Standard: last, g&uuml;ltige Werte: last, on, off, no<br><br>
    </li>
	<li>longpressinterval<br>
	  <b>Funktioniert nur bei auf both gesetztem Attribut interrupt</b><br>
      Zeit in Sekunden, die ein GPIO auf high verweilen muss, bevor das Reading longpress auf on gesetzt wird <br>
      Standard: 1, g&uuml;ltige Werte: 0.1 - 10<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE

=cut 
