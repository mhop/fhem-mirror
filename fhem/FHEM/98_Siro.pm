# $Id$
#
# Siro module for FHEM
# Thanks for templates/coding from SIGNALduino team and Jarnsen_darkmission_ralf9
#
# Needs SIGNALduino >= V3.3.1-dev (10.03.2017).
# Published under GNU GPL License, v2
# History:

# 0.01 2017-05-24 Smag Decoding/sniffing signals, Binary-keycode-decoding for on, off, stop, favourite and p2 (pairing).
# 0.02 2017-05-25 Smag Tests with CUL/COC and Signalduino. Successful signalrepeat to device via Signalduino.
# 0.03 2017-07-23 Smag initial template
# 0.04 2017-07-24 Smag Changed binary device-define to much more easier hex-code (28bit+channel). 
# 0.10 2017-07-30 Smag Siro-Parse implemented. First alpha-version went out for Byte09 and det
# 0.11 2017-07-30 Smag, Byte09 updated module 
# 0.12 2017-08-02 Byte Subroutine X_internaltset komplett entfernt, Zusammenlegung mit X_set
#                 Byte Variablen bereinigt
#		          		Byte Code bereinigt
#		          		Byte Einführung "readings", "lastmsg" und "aktMsg" inkl. Unixtime 
# 0.13 2017-08-03 Byte Senden eines doppelten Stoppbefehls abgefangen, keine Hardwaremittelanfahrt durch zweimaliges Stopp mehr möglich
# 0.14 2017-08-04 Byte Attr SignalLongStopRepeats eingeführt. Anzahl der Repeats für Longstop (Favourite). undef = 15
# 0.15 2017-08-05 Byte Attr "timer" eingeführt. Enthält die Zeit zwischen zwei ausgeführten Befehlen zur Positionsberechnung
# 0.16 2017-08-06 Byte Berechnung der aktuellen Position nach Stop-Kommando - Darstellung im state bzw. im Slider
# 0.17 2017-08-09 Byte Fehler bei der Positionsfahrt aus der Fav-Position behoben
# 0.18 2017-08-10 Byte Änderung des State bei Empfang von FB integriert
# 0.19 2017-08-12 Byte Attr 'position_adjust' abgeschafft
# 0.20 2017-08-12 Attr 'operation_mode' eingeführt
#		  						0 Normaler Modus : Keine 'position_adjust' - Fahrt über 0
#		  						1 Normaler Modus : Positionsanfahrt immer -> 'position_adjust' - Fahrt über 0
#		  						2 Repeater Modus : Modul empfängt die FB und leitet es an den Motor weiter. Motor empfängt die FB nicht direkt.
#								Kanalanpassung notwendig. Zuverlässigster Betrieb!
# 0.21 2017-08-13 Smag: Code-Cleanup. Spellcheck. Documentation
# 0.22 2017-08-18 Byte: Kompletten Code überarbeitet. Laufzeitoptimierung. Reaktionszeit verbessert. Unnötige Readings in die Internals verlagert. Fehler bei direktem umschalten behoben.
# 	   			  		Operation_mode 1 komplett entfernt, om 2 ist nun om 1. Operationmode 1 bis Fertigstellung deaktiviert
# 0.23 Beta		  Byte V0.22 - > V1.0 Beta
# 0.24 2017-08-20 Byte Positionsanfahrt über Alexa möglich - "schalte DEVICE XX%"
# 	   			  		Operation_mode 1 eingeführt. ( Repeatermodus )
# 0.25 2017-08-26 Byte diverse Korrekturen, Codebereinigung, Anfahrt der HW_Favorit Position über FB im Mode 1 möglich
# 0.26 2017-08-26 Byte Commandref Deutsch hinzugefügt
# 0.27 2017-08-29 Byte Define von Devices, die eine Kanal nutzen der bereits von einem Device genutzt wird (channel / send_channel_mode1) wird unterbunden 
# 	   			  		Debug_Attr (0/1) eingefügt - es werden diverse redings angelegt und kein Befehl physisch anden Rollo gesendet - nur Fehlersuche
# 0.28 2017-09-02 ByteFehler bei Stateaktualisierung in Zusammenhang mit Stop bei Favoritenanfahrt behoben
# 0.29 2017-08-29 Byte Define von Devices, die einen Kanal nutzen, der bereits von einem Device genutzt wird (channel / send_channel_mode1) wird unterbunden 
#						Debug_Attr (0/1) eingefügt - es werden diverse redings angelegt und kein Befehl physisch anden Rollo gesendet - nur Fehlersuche
#				  		Set favorite und Attr prog_fav_sequence eingeführt - programmierung derHardware_Favorite_Position
#				  		Codebereinigung
#				  		Allgemeine Fehler behoben
# 0.30 2017-09-09 Byte Betrieb in eingeschränkter Funktion ohne 'time'- Attribute möglich
# 0.31 2017-09-10 Byte Commandref ergänzt Deutsch/Englisch
# 0.32 2017-09-16 Byte Fehlerkorrekturen
# 0.34 2017-09-17 Invers Dokumentation, Byte Korrekturen Log
# 0.35 2017-09-24 Byte Fehlerkorrekturen , Einbau Device  mit Kanal 0 als Gruppendevice ( noch gesperrt ) . Attribut "channel" enfernt , Kanalwahl nur noch über das Device möglich . 
# 0.36 2017-09-24 Byte Device0 Favoritenanfahrt und Positionsanfahrt durch FHEM möglich 
# 0.37 2017-09-25 SMag Prerelease-Vorbereitungen. Codeformatierung, Fehlerkorrekturen, Textkorrekturen.
# 0.38 2017-09-27 optimierung sub Siro_Setgroup($) -> laufzeitverbesserung
# 
# 0.39 2017-10-14 Byte Log überarbeitet / Parse überarbeitet / Define überarbeitet / interne Datenstruktur geändert / Internals überarbeitet / Groupdevice ( Kanal 0 ) möglich . Fehlerkorrekturen / attribut down_for_timer und up_for_timer eingebaut
# 0.40 2017-10-15	Byte Code bereinigt
# 0.41 2017-10-17	Byte anpassung der %Sets je nach device ( groupdevice )
# 0.42 2017-10-18	Byte attr "down_auto_stop" eingefügt - beendet runterfahrt durch on/close/fb bei ATTR weiterfahrt durch nochmalige cmd . Comandref ergänzt
# 0.43 2017-10-19	Byte attr "invers_position[0/1]" eingefügt. Invertiert positionsanzeige und anfahrt 0 -> 100% = rollo geschlossen - 1 -> 0% =rollo geschlossen
# 0.44 2017-10-19	Byte bugfix -> set favorite. Unterscheidung ob "time_down_to_favorite" gesetzt oder nicht. ( interpretation :favorite programmiert oder nicht ) - entsprechende anpassung des kommandos ( erst löschen -> dann speichern )
# 0.45 2017-10-28	Byte fehler bei erneutem Kommando während Positionsanfahrten behoben
# 0.46 2017-05-11	Byte fehler bei fhem-neustart behoben
# 0.47 2017-11-11	Byte attr Disable zugefügt.
# 0.47 2017-02-12	Byte/Dr Smag  Quickfix ERB15LE
################################################################################################################
# Todo's:
# - 
# - 
###############################################################################################################


package main;


use strict;
use warnings;
my $version = "V 0.48";

my %codes = (
	"55" => "stop",			# Stop the current movement or move to custom position
	"11" => "off",			# Move "up"
	"33" => "on",			# Move "down"
	"CC" => "prog",			# Programming-Mode (Remote-control-key: P2)
);

my %sets = (
	"open" => "noArg",
	"close" => "noArg",
	"off" => "noArg",
	"stop" => "noArg",
	"on" => "noArg",
	"fav" => "noArg",
	"prog" => "noArg",
	"prog_stop" => "noArg",
	"position" => "slider,0,1,100",	    # Wird nur bei vorhandenen time_to attributen gesetzt
	"state" => "noArg" ,
	"set_favorite" => "noArg",
	"down_for_timer" => "textField",
	"up_for_timer" => "textField"	
	
);

my %sendCommands = (
	"off" => "off",
	"stop" => "stop",
	"on" => "on",
	"open" => "off",
	"close" => "on",
	"fav" => "fav",
	"prog" => "prog",
	"set_favorite" => "setfav" 
);

my %siro_c2b;         

my %models = ( 
	siroblinds => 'blinds', 
	siroshutter => 'shutter' 
); 
	
#################################################################
sub Siro_Initialize($) {
	my ($hash) = @_;

	# Map commands from web interface to codes used in Siro
	foreach my $k ( keys %codes ) {
		$siro_c2b{ $codes{$k} } = $k;
	}
	$hash->{SetFn}		= "Siro_Set";
	$hash->{NotifyFn}   = "Siro_Notify";
	$hash->{ShutdownFn}		= "Siro_Shutdown";
	#$hash->{StateFn} 	= "Siro_SetState"; #change  
	$hash->{DefFn}   	= "Siro_Define";
	$hash->{UndefFn}	= "Siro_Undef";
	$hash->{DeleteFn}	= "Siro_Delete";
	$hash->{ParseFn}  	= "Siro_Parse";
	$hash->{AttrFn}  	= "Siro_Attr";
	$hash->{Match}     	= "^P72#[A-Fa-f0-9]+";
	$hash->{AttrList} = " IODev"
	  . " disable:0,1"
	  . " SignalRepeats:1,2,3,4,5,6,7,8,9"
	  . " SignalLongStopRepeats:10,15,20,40,45,50"
	  . " channel_send_mode_1:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
	  . " $readingFnAttributes"
	  . " setList"
	  . " ignore:0,1"
	  . " dummy:1,0"
#	  . " model:siroblinds,siroshutter"
	  . " time_to_open"                  
	  . " time_to_close"	
	  . " time_down_to_favorite"         
	  . " hash"
	  . " operation_mode:0,1"
	  . " debug_mode:0,1"
	  . " down_limit_mode_1:slider,0,1,100"
	  . " down_auto_stop:slider,0,1,100"
	  . " invers_position:0,1"
	  . " prog_fav_sequence";

	
	$hash->{AutoCreate} =
	{ 
		"Siro.*" => 
		{ 
			ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", 
			FILTER => "%NAME",
			autocreateThreshold => "2:10" 
		} 
	};

	$hash->{NOTIFYDEV} = "global";
	Siro_LoadHelper($hash) if($init_done);
}

#################################################################
sub Siro_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my $u = "Wrong syntax: define <name> Siro id ";
	my $askedchannel; # Angefragter kanal

	# Fail early and display syntax help
	if ( int(@a) < 3 ) {
		return $u;
	}
	
	if ( $a[2] =~ m/^[A-Fa-f0-9]{8}$/i ){
		$hash->{ID} = uc(substr($a[2], 0, 7));
		$hash->{CHANNEL} = sprintf( "%d", hex(substr($a[2], 7, 1)) );
		$askedchannel=sprintf( "%d", hex(substr($a[2], 7, 1)) );;
	} 
	else
	{
		return "Define $a[0]: wrong address format: specify a 8 char hex value (id=7 chars, channel=1 char) . Example A23B7C51. The last hexchar identifies the channel. -> ID=A23B7C5, Channel=1. "
	}

	my $test;
	my $device;
	my $chanm1;
	my $chan;
	my @channels = ('','0','1','2','3','4','5','6','7','8','9');
	my @testchannels; # Enthält alle Kanäle die in Benutzung sind
	my @keys;
	my @values; 
	my $testname;
	
	$hash->{Version}		= $version;
	my $name  = $a[0];
	# Log3($name, 0, "Siro_define: $hash->{helper}{position} ");
	# if ($hash->{helper}{position} eq '')
	# {
		# $hash->{helper}{position}="0";
		# $hash->{helper}{aktMsg} = "stop".' '.'0'.' '.gettimeofday();
		# $hash->{helper}{lastMsg} = "stop".' '.'0'.' '.gettimeofday();
		# $hash->{helper}{lastProg} ="0";
		# $hash->{helper}{lastparse_stop} ="stop".' '.gettimeofday();
		# $hash->{helper}{lastparse} ="";
		# $hash->{helper}{parse_aborted} ="0";
	# }
	
	
	my $tn = TimeNow(); #Wird wohl nicht benötigt?!?! down_limit_mode_1
	
	if ($askedchannel ne "0")
	{	
		#Setzen der vordefinierten Attribute
		$attr{$name}{devStateIcon} ="{return '.*:fts_shutter_1w_'.(int(\x{24}state/10)*10)}" if(!defined ($attr{$name}{devStateIcon})); #TMP_Byte09 !defined
		
		$attr{$name}{webCmd} ="stop:on:off:fav:position" if (!defined ($attr{$name}{webCmd})); 
		$attr{$name}{down_limit_mode_1} ="100" if (!defined ($attr{$name}{down_limit_mode_1})); 
		$attr{$name}{prog_fav_sequence} ="prog,2,stop,2,stop" if (!defined ($attr{$name}{prog_fav_sequence}));    
		#$attr{$name}{room} ="Siro" if (!defined ($attr{$name}{genericDeviceType}));                           
		$attr{$name}{SignalLongStopRepeats} ="15" if (!defined ($attr{$name}{SignalLongStopRepeats}));             
		$attr{$name}{SignalRepeats} ="8" if (!defined ($attr{$name}{SignalRepeats}));                     
		$attr{$name}{operation_mode} ="0" if (!defined ($attr{$name}{operation_mode})); 
		$attr{$name}{down_auto_stop} ="100" if (!defined ($attr{$name}{down_auto_stop}));
		$attr{$name}{invers_position} ="0" if (!defined ($attr{$name}{invers_position}));
	}
	else
	{
		$attr{$name}{devStateIcon} ="{return '.*:fts_shutter_1w_'.(int(\x{24}state/10)*10)}" if(!defined ($attr{$name}{devStateIcon})); #TMP_Byte09 !defined
		$attr{$name}{webCmd} ="stop:on:off:fav:position" if (!defined ($attr{$name}{webCmd}));    
		#$attr{$name}{room} ="Siro" if (!defined ($attr{$name}{genericDeviceType}));                           
		$attr{$name}{SignalLongStopRepeats} ="15" if (!defined ($attr{$name}{SignalLongStopRepeats}));             
		$attr{$name}{SignalRepeats} ="8" if (!defined ($attr{$name}{SignalRepeats}));                 
		#$attr{$name}{SignalRepeats} ="2";
		$attr{$name}{down_auto_stop} ="100" if (!defined ($attr{$name}{down_auto_stop}));
		$attr{$name}{invers_position} ="0" if (!defined ($attr{$name}{invers_position}));
	}
	my $code  = uc($a[2]);
	my $ncode = 1;
	
	my $devpointer = $hash->{ID}.$hash->{CHANNEL};
	$hash->{CODE}{ $ncode++ } = $code;
	$modules{Siro}{defptr}{$devpointer} = $hash;
	
	Log3($name, 5, "Siro_define: angelegtes Device - code -> $code name -> $name hash -> $hash ");

	AssignIoPort($hash);
}

#################################################################
sub Siro_Undef($$) 
{	

	my ( $hash, $name) = @_; 
	delete( $modules{Siro}{defptr}{$hash} );
	return undef;
}

#################################################################
sub Siro_Shutdown($)
{
	my ( $hash ) = @_;
	my $name = $hash->{NAME};
	
	
	
	
	
	 readingsSingleUpdate($hash, ".aktMsg",$hash->{helper}{aktMsg}, 0);
	 readingsSingleUpdate($hash, ".lastMsg",$hash->{helper}{lastMsg}, 0);
	 readingsSingleUpdate($hash, ".lastProg",$hash->{helper}{lastProg}, 0);
	 readingsSingleUpdate($hash, ".lastparse",$hash->{helper}{lastparse}, 0);
	 readingsSingleUpdate($hash, ".lastparse_stop",$hash->{helper}{lastparse_stop}, 0);
	 readingsSingleUpdate($hash, ".parse_aborted",$hash->{helper}{parse_aborted}, 0);
	 readingsSingleUpdate($hash, ".positionsave",$hash->{helper}{position}, 0);
	 readingsSingleUpdate($hash, ".positiontimer",$hash->{helper}{positiontimer}, 0);
	 
	return;
}

#################################################################
sub Siro_LoadHelper($)
{
	my ( $hash ) = @_;
	my $name = $hash->{NAME};
	
	
	
	my $save =	ReadingsVal($name, '.aktMsg', 'undef');
	if ($save eq 'undef')
		{
			 $hash->{helper}{position}="0";
			 $hash->{helper}{aktMsg} = "stop".' '.'0'.' '.gettimeofday();
			 $hash->{helper}{lastMsg} = "stop".' '.'0'.' '.gettimeofday();
			 $hash->{helper}{lastProg} ="0";
			 $hash->{helper}{lastparse_stop} ="stop".' '.gettimeofday();
			 $hash->{helper}{lastparse} ="";
			 $hash->{helper}{parse_aborted} ="0";
		}
	
	else
		{
			 $hash->{helper}{aktMsg} = ReadingsVal($name, '.aktMsg', '');
			 $hash->{helper}{lastMsg} = ReadingsVal($name, '.lastMsg', '');
			 $hash->{helper}{lastparse} = ReadingsVal($name, '.lastparse', '');
			 $hash->{helper}{lastProg} = ReadingsVal($name, '.lastProg', '');
			 $hash->{helper}{lastparse_stop} = ReadingsVal($name, '.lastparse_stop', '');
			 $hash->{helper}{parse_aborted} = ReadingsVal($name, '.parse_aborted', '');
			 $hash->{helper}{position} = ReadingsVal($name, '.positionsave', '');
			 $hash->{helper}{positiontimer} = ReadingsVal($name, '.positiontimer', '');
		}
	Log3($name, 5, "Siro: Helper initialisiert");
	return;
}

#################################################################

sub Siro_Notify($$)
	{
		my ($own_hash, $dev_hash) = @_;
		my $ownName = $own_hash->{NAME}; # own name / hash
		
		my $devName = $dev_hash->{NAME}; # Device that created the events
		my $events = deviceEvents($dev_hash, 1);

		if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
			{
				Siro_LoadHelper($own_hash);
			}
	return;	
	}
#################################################################


sub Siro_Delete($$)    
{                     
	my ( $hash, $name ) = @_; 
	
	return undef;
}

#################################################################
sub Siro_SendCommand($@)
{
	my ($hash, @args) = @_;
	my $ret = undef;
	my $cmd = $args[0];       						# Command as text (on, off, stop, prog)
	my $message;              						# IO-Message (full)
	my $chan;                 						# Channel
	my $binChannel;           						# Binary channel
	my $SignalRepeats;								#
	my $name = $hash->{NAME};
	my $binHash;
	my $bin;                  						# Full binary IO-Message 
	my $binCommand;
	my $numberOfArgs  = int(@args);
	my $command = $siro_c2b{ $cmd };
	my $io = $hash->{IODev};						# IO-Device (SIGNALduino)
	
	my $debug = AttrVal($name,'debug_mode', '0');

	Log3($name, 5, "Siro_sendCommand: hash -> $hash - $name -> cmd :$cmd: - args -> @args");

	if ($args[2] eq "longstop")
	{
		$SignalRepeats =AttrVal($name,'SignalLongStopRepeats', '15')
	}
	else
	{
	  $SignalRepeats = AttrVal($name,'SignalRepeats', '10');
	}

	my $operationmode = AttrVal($name,'operation_mode', 'on');

	Log3($name, 5, "Siro_sendCommand: operationmode -> $operationmode");

	if ($operationmode eq '1')
	{
	$chan = AttrVal($name,'channel_send_mode_1', $hash->{CHANNEL});
	Log3($name, 5, "Siro_sendCommand: channel für OM1  -> $chan");
	}
	else
	{
		$chan = AttrVal($name,'channel', undef);
		if (!defined($chan))
		{
			$chan = $hash->{CHANNEL};
		}
	}
		
	if ($chan eq "0")
	{	
		Log3($name, 5, "Siro_sendCommand: Aborted not sent on a channel 0 request ");
		return;
	}
		
	$binChannel = sprintf("%04b",$chan);
	Log3($name, 5, "Siro set channel: $chan ($binChannel) for $io->{NAME}");
	
	my $value = $name ." ". join(" ", @args);
	
	$binHash = sprintf( "%028b", hex( $hash->{ID} ) );
	Log3 $io, 5, "Siro_sendCommand: BinHash: = $binHash";
	
	$binCommand = sprintf( "%08b", hex( $command ) );
	Log3 $io, 5, "Siro_sendCommand: BinCommand: = $binCommand";
	
	$bin = 	$binHash . $binChannel . $binCommand; # Binary code to send
	Log3 $io, 5, "Siro_sendCommand: Siro set value = $value";
	
	$message = 'P72#' . $bin . '#R' . $SignalRepeats;
	
	
	if ($debug eq "1")
	{
		readingsSingleUpdate($hash, "DEBUG_SEND","$name -> message :$message: ", 1);
	} 
	else
	{
	Log3 $io, 5, "Siro_sendCommand: Siro_sendCommand: $name -> message :$message: ";
		IOWrite($hash, 'sendMsg', $message);
	}
	
	my $devicename =$hash->{IODev};
	
	Log3($name, 5, "Siro_sendCommand: name -> $name command -> $cmd ");
	Log3($name, 3, "Siro_sendCommand: execute comand $cmd - sendMsg to $devicename channel $chan -> $message ");
	
	return $ret;
}

#################################################################
sub Siro_Parse($$) 
{
	my $debug='';
	my @args;
	my ($hash, $msg) = @_;
	my $doubelmsgtime = 2;  # zeit in sek in der doppelte nachrichten blockiert werden
	my $favcheck =$doubelmsgtime+1; # zeit in der ein zweiter stop kommen muss/darf für fav
	my $testid = substr($msg, 4, 8);
	my $testcmd = substr($msg, 12, 2);
	my $timediff;  
	
	
	my $name = $hash->{NAME};
	return "" if(IsDisabled($name));
	if(my $lh = $modules{Siro}{defptr}{$testid})
		{
			my $name = $lh->{NAME};
			Log3 $hash, 3, "Siro_Parse: Incomming msg from IODevice $testid - $name device is defined";
			if (defined ($name) && $testcmd ne "54" ) # prüfe auf doppele msg falls gerät vorhanden und cmd nicht stop
				{	
				Log3 $lh, 5, "Siro_Parse: Incomming msg $msg from IODevice name/DEF $testid - Hash -> $lh";

				my $testparsetime = gettimeofday();
				my $lastparse = $lh->{helper}{lastparse};
				my @lastparsearray =split(/ /,$lastparse);
				if (!defined($lastparsearray[1])){$lastparsearray[1] = 0};
				if (!defined($lastparsearray[0])){$lastparsearray[0] = ""};
				$timediff = $testparsetime-$lastparsearray[1];
				my $abort ="false";
							
				Log3 $lh, 5, "Siro_Parse: test doublemsg ";
				Log3 $lh, 5, "Siro_Parse: lastparsearray[0] -> $lastparsearray[0] ";
				Log3 $lh, 5, "Siro_Parse: lastparsearray[1] -> $lastparsearray[1] ";
				Log3 $lh, 5, "Siro_Parse: testparsetime -> $testparsetime ";
				Log3 $lh, 5, "Siro_Parse: timediff -> $timediff ";
						
					if ($msg eq $lastparsearray[0])
					{
							
						if ($timediff < $doubelmsgtime )
						{
								
						$abort ="true";
						}
					}
				$lh->{helper}{lastparse} = "$msg $testparsetime";
					if ($abort eq "true")
					{
					Log3 $lh, 4, "Siro_Parse: aborted , doublemsg ";
					return $name;
					}
							
				Log3 $lh, 4, "Siro_Parse: not aborted , no doublemsg ";
			}
	
			my (undef ,$rawData) = split("#",$msg);
			my $hlen = length($rawData);
			my $blen = $hlen * 4;
			my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	
			Log3 $hash, 5, "Siro_Parse: msg = $rawData length: $msg";  
			Log3 $hash, 5, "Siro_Parse: rawData = $rawData length: $hlen";
			Log3 $hash, 5, "Siro_Parse: converted to bits: $bitData";
	
			my $id = substr($rawData, 0, 7);                            # The first 7 hexcodes are the ID
			my $BitChannel = substr($bitData, 28, 4);                   # Not needed atm
			my $channel = sprintf( "%d", hex(substr($rawData, 7, 1)) ); # The last hexcode-char defines the channel
			my $channelhex = substr($rawData, 7, 1) ; # tmp
			my $cmd = sprintf( "%d", hex(substr($rawData, 8, 1)) );
			my $newstate = $codes{ $cmd . $cmd};                        # Set new state
			my $deviceCode = $id . $channelhex;       					# Tmp change channel -> channelhex. The device-code is a combination of id and channel
    
			$debug=$debug."id-".$id." ";
	
			Log3 $hash, 5, "Siro_Parse: device ID: $id";
			Log3 $hash, 5, "Siro_Parse: Channel: $channel";
			Log3 $hash, 5, "Siro_Parse: Cmd: $cmd  Newstate: $newstate";
			Log3 $hash, 5, "Siro_Parse: deviceCode: $deviceCode";
	
			if (defined ($name) && $testcmd eq "54" ) # prüfe auf doppele msg falls gerät vorhanden und cmd stop
			{	
				# Log3 $lh, 5, "Siro_Parse: prüfung auf douplestop ";
				my $testparsetime = gettimeofday();
				my $lastparsestop = $lh->{helper}{lastparse_stop};
				my $parseaborted = $lh->{helper}{parse_aborted};
				my @lastparsestoparray =split(/ /,$lastparsestop);
				my $timediff = $testparsetime-$lastparsestoparray[1];
				my $abort ="false";
				$parseaborted=0 if (!defined ($parseaborted));
				
				Log3 $lh, 5, "Siro_Parse: test doublestop ";
				Log3 $lh, 5, "Siro_Parse: lastparsearray[0] -> $lastparsestoparray[0] ";
				Log3 $lh, 5, "Siro_Parse: lastparsearray[1] -> $lastparsestoparray[1] ";
				Log3 $lh, 5, "Siro_Parse: testparsetime -> $testparsetime ";
				Log3 $lh, 5, "Siro_Parse: timediff -> $timediff ";
				Log3 $lh, 5, "Siro_Parse: parseaborted -> $parseaborted ";
					
					 if ($newstate eq $lastparsestoparray[0])
						 {
						
						 if ($timediff < 3 )
							 {
								 $abort ="true";
								 $parseaborted++;
							 }
					
						 }
					 if ($abort eq "true" && $parseaborted < 8 )
						 {
							 $lh->{helper}{parse_aborted}=$parseaborted;
							 Log3 $lh, 5, "Siro_Parse: aborted , doublestop ";
							 return $name;
						 }
						
						
					 $lh->{helper}{lastparse_stop} = "$newstate $testparsetime";
					
					 if ( $parseaborted >= 7 )
						 {
							 $parseaborted = 0;
							 $lh->{helper}{parse_aborted}=$parseaborted;
							 $testparsetime = gettimeofday();
							 $lh->{helper}{lastparse_stop} = "$newstate $testparsetime";
							 if ($newstate eq "stop")
								 {
								 Log3 $lh, 3, "Siro_Parse: double_msg signal_favoritenanfahrt erkannt ";
								 $newstate="fav";
								 $args[0]="fav";
								 }
						 }
			}
	
			if (defined ($name)) 
			{
				$args[0]=$newstate;
				my $parseaborted = 0;
				$lh->{helper}{parse_aborted}=$parseaborted;
		
				$debug=$debug.' '.$name;  
				my $operationmode = AttrVal($name,'operation_mode', '0');
				my $debugmode = AttrVal($name,'debug_mode', '0');
				my $chan;
				if ($operationmode eq '0')
					{
						$chan = AttrVal($name,'channel', undef);
						if (!defined($chan)) 
							{
							$chan = $lh->{CHANNEL};
							}
					}
					
				if ($operationmode eq '1')
					{
						$chan = AttrVal($name,'channel', undef);
						if (!defined($chan)) 
							{
							$chan = $lh->{CHANNEL};
							}
					}	
						
				my $aktMsg = $lh->{helper}{aktMsg} ;
				my @last_action_array=split(/ /,$aktMsg);
				my $lastaction = $last_action_array[0];
				my $lastaction_position = $last_action_array[1];
				my $lastaction_time = $last_action_array[2];

				readingsSingleUpdate($lh, "parsestate", $newstate, 1);
				
				Log3 $lh, 5, "Siro_Parse:  $name $newstate";
				Log3 $lh, 5, "Siro_Parse: operationmode -> $operationmode";
				
				if ($operationmode ne '1' || $chan eq "0")
					{
						Log3 $lh, 5, "Siro_Parse: set mode to physical";
						$lh->{helper}{MODE}  = "physical";
						$debug=$debug.' physical';  
					}
				else
					{
						$lh->{helper}{MODE}  = "repeater";
						$debug=$debug.' repeater'; 
					}
				
				if ($chan eq "0")
					{
				
						$args[1]="physical";
						$debug=$debug.' physical'; 
					}
				
				Log3 $lh, 2, "Siro_Parse -> Siro_Set: $lh, $name, @args";
				
				Siro_Set($lh, $name, @args) ;
				$debug=$debug.' '.$lh;
				
				if($debugmode eq "1")
					{
						readingsSingleUpdate($lh, "DEBUG_PARSE",$debug, 1);
					}
				##############################################
				# Return list of affected devices
				#my ( $hash, $name, @args ) = @_;
				##############################################
				return $name;
			}
	}
	else
	{
	
		my (undef ,$rawData) = split("#",$msg);
		my $hlen = length($rawData);
		my $blen = $hlen * 4;
		my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
		
		Log3 $hash, 5, "Siro_Parse: msg = $rawData length: $msg";  
		Log3 $hash, 5, "Siro_Parse: rawData = $rawData length: $hlen";
		Log3 $hash, 5, "Siro_Parse: converted to bits: $bitData";
		
		my $id = substr($rawData, 0, 7);                            # The first 7 hexcodes are the ID
		my $BitChannel = substr($bitData, 28, 4);                   # Not needed atm
		my $channel = sprintf( "%d", hex(substr($rawData, 7, 1)) ); # The last hexcode-char defines the channel
		my $channelhex = substr($rawData, 7, 1) ; # tmp
		my $cmd = sprintf( "%d", hex(substr($rawData, 8, 1)) );
		my $newstate = $codes{ $cmd . $cmd};                        # Set new state
		my $deviceCode = $id . $channelhex;       					# Tmp change channel -> channelhex. The device-code is a combination of id and channel
		
		$debug=$debug."id-".$id." ";
		
		Log3 $hash, 5, "Siro_Parse: device ID: $id";
		Log3 $hash, 5, "Siro_Parse: Channel: $channel";
		Log3 $hash, 5, "Siro_Parse: Cmd: $cmd  Newstate: $newstate";
		Log3 $hash, 5, "Siro_Parse: deviceCode: $deviceCode";
	
		Log3 $hash, 2, "Siro unknown device $deviceCode, please define it";
		return "UNDEFINED Siro_$deviceCode Siro $deviceCode";
	}
}

#############################################################

sub Siro_Attr(@) 
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	return "\"Siro Attr: \" $name does not exist" if (!defined($hash));
	my $channel = ($hash->{CHANNEL});
	
	if ($channel eq "0")
	{
		my @notallowed = ("prog_fav_sequence", "time_to_open", "time_to_close", "operation_mode", "channel_send_mode_1", "time_down_to_favorite");
		foreach my $test (@notallowed) 
		{
			if ($test eq $aName ){return "\"Siro Attr: \" $name is a group device, the attribute $aName $aVal is not allowed here.";}
		}
	}
	
	return undef if (!defined($name));
	return undef if (!defined($aName));
	#return undef if (!defined($aVal));

	if ($cmd eq "set") 
	{
		if ($aName eq "debug_mode" && $aVal eq "0")
		{
			Log3 $hash, 5, "debug_mode: reading deleted";
			delete ($hash->{READINGS}{DEBUG_SEND});	
			delete ($hash->{READINGS}{DEBUG_PARSE});
			delete ($hash->{READINGS}{DEBUG_SET});
		}
		
		if ($aName eq "debug_mode" && $aVal eq "1")
		{
			readingsSingleUpdate($hash, "DEBUG_SEND","aktiv", 1);
			readingsSingleUpdate($hash, "DEBUG_PARSE","aktiv", 1);
			readingsSingleUpdate($hash, "DEBUG_SET","aktiv", 1);
			Log3 $hash, 5, "debug_mode: create reading";
		}
		
		if ($aName eq "invers_position")
		{
		
			if ( $aVal eq "0" )
				{
				my $oldicon = "{return '.*:fts_shutter_1w_'.(100-(int(\$state/10)*10))}";
				Log3 $hash, 3, "Siro_Attr: change attr old -> $attr{$name}{devStateIcon} $oldicon";
				if ($attr{$name}{devStateIcon} eq $oldicon)
					{
					Log3 $hash, 3, "Siro_Attr: ersetzt";
					$attr{$name}{devStateIcon} ="{return '.*:fts_shutter_1w_'.(int(\$state/10)*10)}" ;
					}
				if (defined ($attr{$name}{down_auto_stop}))
					{
					my $autostop = AttrVal($name,'down_auto_stop', 'undef');	
					$autostop = 100 - $autostop;
					$attr{$name}{down_auto_stop} =$autostop; 
					}
					
				my $oldstate =$hash->{helper}{position};
if(!defined $oldstate){$oldstate=0}; 
				my $newState =  $oldstate;
				my $updateState;
				Log3 $hash, 3, "Siro_Attr: state old -> $oldstate new -> $newState";
				Siro_UpdateState( $hash, $newState, '', $updateState, 1 );
				
				}
		
			if ( $aVal eq "1" )
				{
				my $oldicon = "{return '.*:fts_shutter_1w_'.(int(\$state/10)*10)}";
				Log3 $hash, 3, "Siro_Attr: change attr old -> $attr{$name}{devStateIcon} $oldicon";
				if ($attr{$name}{devStateIcon} eq $oldicon)
					{
					Log3 $hash, 3, "Siro_Attr: ersetzt";
					$attr{$name}{devStateIcon} ="{return '.*:fts_shutter_1w_'.(100-(int(\$state/10)*10))}" ;
					}
				if (defined ($attr{$name}{down_auto_stop}))
					{
					my $autostop = AttrVal($name,'down_auto_stop', 'undef');	
					$autostop = 100 - $autostop;
					$attr{$name}{down_auto_stop} =$autostop; 
					}	
				my $oldstate =$hash->{helper}{position};
				my $newState = 100 - $oldstate;
				my $updateState;
				Log3 $hash, 3, "Siro_Attr: state old -> $oldstate new -> $newState";
				Siro_UpdateState( $hash, $newState, '', $updateState, 1 );	
				}
		}
	}
	
	if ($cmd eq "del") 
		{
		if ($aName eq "invers_position")
			{
			my $oldicon = "{return '.*:fts_shutter_1w_'.(100-(int(\$state/10)*10))}";
			
			Log3 $hash, 3, "Siro_Attr delete invers: change attr old -> $attr{$name}{devStateIcon} $oldicon";
			if ($attr{$name}{devStateIcon} eq $oldicon)
				{
				Log3 $hash, 3, "Siro_Attr: ersetzt";
				$attr{$name}{devStateIcon} ="{return '.*:fts_shutter_1w_'.(int(\$state/10)*10)}" ;
				}
			my $oldstate =$hash->{helper}{position};
			my $newState =  $oldstate;
			my $updateState;
			Log3 $hash, 3, "Siro_Attr: state old -> $oldstate new -> $newState";
			Siro_UpdateState( $hash, $newState, '', $updateState, 1 );	
			}
		}
	return undef;
}

#################################################################

# Call with hash, name, virtual/send, set-args
sub Siro_Set($@)
{

my $testtimestart = gettimeofday();
	my $debug;
	my ( $hash, $name, @args ) = @_;
	return "" if(IsDisabled($name));
	# Set without argument  #parseonly
	my $numberOfArgs  = int(@args);
	my $nodrive = "false";
	$args[2]="0";
	my $action ="no action";

	return "Siro_set: No set value specified" if ( $numberOfArgs < 1 );
	
	my $cmd = $args[0];	
	my $invers = AttrVal($name,'invers_position', '0');
	my $runningaction = ReadingsVal($name, 'action', 'no action');
	my $runningtime = 0;
	
	
	# teste auf hilfsvariablen
	my $save =	ReadingsVal($name, '.aktMsg', 'undef');
	if ($save eq 'undef')
		{
			$hash->{helper}{position}="0";
			$hash->{helper}{aktMsg} = "stop".' '.'0'.' '.gettimeofday();
			$hash->{helper}{lastMsg} = "stop".' '.'0'.' '.gettimeofday();
			$hash->{helper}{lastProg} ="0";
			$hash->{helper}{lastparse_stop} ="stop".' '.gettimeofday();
			$hash->{helper}{lastparse} ="";
			$hash->{helper}{parse_aborted} ="0";
			 
			readingsSingleUpdate($hash, ".aktMsg",$hash->{helper}{aktMsg}, 0);
			readingsSingleUpdate($hash, ".lastMsg",$hash->{helper}{lastMsg}, 0);
			readingsSingleUpdate($hash, ".lastProg",$hash->{helper}{lastProg}, 0);
			readingsSingleUpdate($hash, ".lastparse",$hash->{helper}{lastparse}, 0);
			readingsSingleUpdate($hash, ".lastparse_stop",$hash->{helper}{lastparse_stop}, 0);
			readingsSingleUpdate($hash, ".parse_aborted",$hash->{helper}{parse_aborted}, 0);
			readingsSingleUpdate($hash, ".positionsave",$hash->{helper}{position}, 0);
			readingsSingleUpdate($hash, ".positiontimer",$hash->{helper}{positiontimer}, 0);
		}
	######################################### für ECHO
	if ( $cmd =~ /^\d+$/) 
	{
		if ($cmd >= 0 && $cmd <= 100)
		{
			$args[0] ="position";
			$args[1] =$cmd;
			$cmd = "position";
		}
	}
	#########################################
	
	
	#diverse befehle bei laufender aktion abfangen
	if 	(($cmd eq "position" || $cmd eq 'up_for_timer' || $cmd eq 'on_for_timer') && $runningaction ne 'no action')
		{
	
			my $restartmsg = $name.' '.$args[0].' '.$args[1];
			Log3($name,3,"Siro_Set: laufende action gefunden - restart msg -> $restartmsg ");
			InternalTimer(gettimeofday()+0,"Siro_Restartcmd",$restartmsg); 
			$args[0] ="stop";
			$args[1] ='';
			$cmd = "stop";
	
		}
	
	
	
	
	
	#########################################	
	# invertiere position
	if 	($cmd eq "position" && $invers eq "1")
		{
		my $noinvers = $args[1];
		my $inversposition = 100 - $args[1];
		$args[1] = $inversposition; 
		Log3($name,3,"Siro_Set: invertiere Position - input -> $noinvers - inverted -> $inversposition ");	
		}
	#########################################
	
	#########################################
	if (!defined $args[2])
		{
		$args[2]='';
		}
	
	if (!defined $args[1])
		{
		$args[2]='0';
		$args[1]=''; 
		}

	if ($args[1] eq "physical")
		{
			$hash->{helper}{MODE}  = "physical";
		}

	if (!defined($hash)){return;}
	if (!defined($name)){return;}
	
	$debug = "$hash, $name, @args";
	
	if ($cmd ne "?")
	{
		Log3($name,5,"Siro_Set: aufgerufen -> cmd -> $cmd args -> @args ");	
	}
	#########################################
	
	# up/down for timer mappen auf on/off und timer für stop setzen 
	if ($cmd eq 'up_for_timer')
	{
		Log3($name,5,"Siro_Set: up_for_timer @args $args[1]");
		$cmd ="off";
		
		InternalTimer($testtimestart+$args[1], "Siro_Stop", $hash, 0); # State auf Stopp
		$args[0] =$cmd;
		$action = 'up for timer '.$args[1];
		readingsSingleUpdate($hash, "action",$action, 1); #tmp
	}
	
	if ($cmd eq 'down_for_timer')
	{
		Log3($name,3,"Siro_Set: down_for_timer @args $args[1]");
		$cmd ="on";
		readingsSingleUpdate($hash, "action",'down for timer '.$args[1], 1); #tmp
		InternalTimer($testtimestart+$args[1], "Siro_Stop", $hash, 0); # State auf Stopp
		$args[0] =$cmd;
		$action = 'down for timer '.$args[1];
		readingsSingleUpdate($hash, "action",$action, 1); #tmp
	}
	#########################################
	
	# diverse befehle auf bekannte befehle mappen
	if ($cmd eq 'open')
		{
			$cmd ="off";
			$args[0] =$cmd;
		}
	
	if ($cmd eq 'close')
		{
			$cmd ="on";
			$args[0] =$cmd;
		}
	#########################################
	
	$hash->{Version}		= $version;
	
	# diverse attr einlesen
	my $debugmode = AttrVal($name,'debug_mode', '0');
	my $testchannel = $hash->{CHANNEL};
	my $timetoopen = AttrVal($name,'time_to_open', 'undef'); # fahrzeit komplett runter
	my $timetoclose = AttrVal($name,'time_to_close', 'undef'); # fahrzeit komplett hoch
	my $operationmode = AttrVal($name,'operation_mode', '0'); # mode 0 normal / 1 repeater
	my $limitedmode="off";
	my $downlimit = AttrVal($name,'down_limit_mode_1', '100'); # maximale runterfahrt im mode 1
	my $autostop = AttrVal($name,'down_auto_stop', '100'); # automatischer stop bei runterfahrt
	#########################################
	
	# sets an device anpassen
	if ($testchannel ne "0")
		{
		
			 %sets = (
				"open" => "noArg",
				"close" => "noArg",
				"off" => "noArg",
				"stop" => "noArg",
				"on" => "noArg",
				"fav" => "noArg",
				"prog" => "noArg",
				"prog_stop" => "noArg",
				"position" => "slider,0,1,100",	    # Wird nur bei vorhandenen time_to attributen gesetzt
				"state" => "noArg" ,
				"set_favorite" => "noArg",
				"down_for_timer" => "textField",
				"up_for_timer" => "textField"	# Ggf. entfernen (Alexa)
				);
				
			if($timetoopen eq 'undef' || $timetoclose eq 'undef')
				{
					if ($attr{$name}{webCmd} eq "stop:on:off:fav:position")
						{
							$attr{$name}{webCmd} ="stop:on:off:fav"; 
						}
				
					$limitedmode="on";
					$hash->{INFO} = "limited function without ATTR time_to_open / time_to_close / time_down_to_favorite";
				}
			else
				{
					if ($attr{$name}{webCmd} eq "stop:on:off:fav")
					{
						$attr{$name}{webCmd} ="stop:on:off:fav:position"; 
					}
					delete($hash->{INFO});
					
				
				}
		}
	else # this block is for groupdevicec ( channel 0 )
		{
				Log3($name,5,"Siro_Set: Groupdevice erkannt ");
				
				 %sets = (
				"open" => "noArg",
				"close" => "noArg",
				"off" => "noArg",
				"stop" => "noArg",
				"on" => "noArg",
				"fav" => "noArg",
				#"prog" => "noArg",
				#"prog_stop" => "noArg",
				"position" => "slider,0,1,100",	    # Wird nur bei vorhandenen time_to attributen gesetzt
				"state" => "noArg" ,
				#"set_favorite" => "noArg",
				"down_for_timer" => "textField",
				"up_for_timer" => "textField"	
				);
				
			if ($cmd  ne "?")   #change
				{	
					my $timetoopen = "15";
					my $timetoclose = "15";
					my $testhashtmp ="";
					my $testhashtmp1 ="";
					my $namex ="";
					my $testid ="";
					my $id = $hash->{ID};
					my @grouphash;
					my @groupnames;
					
					@groupnames = Siro_Testgroup($hash,$id); 
					
					$hash->{INFO} = "This is a group Device with limited functions affected the following devices:\n @groupnames";
					my $groupcommand = $cmd.",".$args[0].",".$args[1].",".$hash;
				
					$hash->{helper}{groupcommand} = $groupcommand;
					InternalTimer(gettimeofday()+0,"Siro_Setgroup",$hash,1); 
				}
			$hash->{helper}{MODE}="physical"; 
		}
	#########################################
	
	# Check for unknown arguments
	if(!exists($sets{$cmd})) 
		{
			my @cList;
			# Overwrite %sets with setList
			my $atts = AttrVal($name,'setList',"");
			my %setlist = split("[: ][ ]*", $atts);
			foreach my $k (sort keys %sets)
				{
				my $opts = undef;
				$opts = $sets{$k};
				$opts = $setlist{$k} if(exists($setlist{$k}));
				if (defined($opts)) 
						{
						push(@cList,$k . ':' . $opts);
						}
						else
						{
						push (@cList,$k);
						}
				} # end foreach
			return "Unknown argument $cmd, choose one of " . join(" ", @cList);
		} 
    #########################################
	
	# undefinierte attr time to open/close abfangen
	if(($timetoopen eq 'undef' || $timetoclose eq 'undef') && $testchannel ne "0")
		{
			Log3($name,1,"Siro_Set:limited function without definition of time_to_close and time_to_open. Please define this attributes.");
			$nodrive ="true";
			$timetoopen=1;
			$timetoclose=1;
		}
	#########################################

	# progmodus setzen
	if ($cmd eq "prog") 
		{
			$hash->{helper}{lastProg} = gettimeofday()+180; # 3 min programmiermodus
		}
	
	if ($cmd eq "prog_stop") 
		{
			$hash->{helper}{lastProg} = gettimeofday();
			return; 
		}
	#########################################
	
	# favoritenposition speichern
	if ($cmd eq "set_favorite") 
		{
			if($debugmode eq "1")
				{
					readingsSingleUpdate($hash, "DEBUG_SET",'setze Favorite', 1);	
				}
			my $sequence;
			my $sequenceraw = AttrVal($name,'prog_fav_sequence', '');
			if (defined ($attr{$name}{time_down_to_favorite}))
				{
				
				$sequence = $sequenceraw.',2,'.$sequenceraw;
				Log3($name,0,"Siro_Set: delete and set favorit -> $sequence");
				}
			else
				{
				 $sequence = $sequenceraw ;
				 Log3($name,0,"Siro_Set: set favorit -> $sequence");
				}
			
			$hash->{sequence} = $sequence; # 3 Min Programmiermodus
			InternalTimer(gettimeofday()+1,"Siro_Sequence",$hash,0); # State auf stop setzen nach Erreichen der Fahrdauer
			Log3($name,1,"Siro_Set:setting new favorite");
			return;
		}
	#########################################
	
	# variablenberechnung für folgende funktionen
	my $check='check';
	my $bmode = $hash->{helper}{aktMsg};
	if ($bmode eq "repeater")
		{
			$check ='nocheck';
		}
	my $ondirekttime = 	$timetoclose/100; # Zeit für 1 Prozent Runterfahrt
	my $offdirekttime = $timetoopen/100;  # Zeit für 1 Prozent Hochfahrt
	#my $runningtime;
	my $timetorun;
	my $newposstate;
	if (defined ($args[1]))
		{
		 if ( $args[1]=~ /^\d+$/) 
			{
				$newposstate = $args[1];# Anzufahrende Position in Prozent   
				Log3($name,5,"Siro_Set:newposstate -> $newposstate");
				$timetorun = $timetoclose/100*$newposstate;	# Laufzeit von 0 prozent }bis zur anzufahrenden Position
			}
		}
	my $virtual; # Kontrollvariable der Positionsanfahrt
	my $newState;
	my $updateState;
	my $positiondrive;
	my $state = $hash->{STATE};
	my $aktMsg = $hash->{helper}{aktMsg} ;
	my @last_action_array=split(/ /,$aktMsg);
	my $lastaction = $last_action_array[0];
	my $lastaction_position = $last_action_array[1];
	my $lastaction_time = $last_action_array[2];
	my $befMsg = $hash->{helper}{lastMsg};
	my @before_action_array=split(/ /,$befMsg);
	my $beforeaction_position = $before_action_array[1];
	my $timebetweenmsg = $testtimestart-$last_action_array[2];# Zeit zwischen dem aktuellen und letzten Befehl
	$timebetweenmsg = (int($timebetweenmsg*10)/10);
	my $oldposition;  # Alter Stand in Prozent
	my $newposition ; # Errechnende Positionsänderung in Prozent - > bei on plus alten Stand 
	my $finalposition;# Erreichter Rollostand in Prozent für state;
	my $time_to_favorite = AttrVal($name,'time_down_to_favorite', 'undef');
	my $favorit_position;
	my $mode = $hash->{helper}{MODE};# Betriebsmodus virtual, physicalFP
	my $lastprogmode = $hash->{helper}{lastProg};
	my $testprogmode = $testtimestart;
	my $testprog = int($testprogmode) - int($lastprogmode);
	my $oldstate = ReadingsVal($name, 'state', 100);
	
	Log3($name,5,"Siro_set: test auf double stop");
	Log3($name,5,"Siro_set: testprogmode -> $testprogmode");
	Log3($name,5,"Siro_set: lastprogmode -> $lastprogmode");
	Log3($name,5,"Siro_set: lastaction -> $lastaction");
	Log3($name,5,"Siro_set: cmd -> $cmd");
	
	# verhindern eines doppelten stoppbefehls ausser progmodus 1
	if ($testprogmode > $lastprogmode)	# Doppelten Stoppbefehl verhindern, ausser progmodus aktiv
		{
			if ($lastaction eq 'stop' && $cmd eq 'stop' && $check ne 'nocheck')
			{
				Log3($name,5,"Siro_set: double stop, action aborted");
				readingsSingleUpdate($hash, "prog_mode", "inaktiv "  , 1);
				if($debugmode eq "1")
					{
						$debug = "Siro_set: double stop, action aborted";
						readingsSingleUpdate($hash, "DEBUG_SET",$debug, 1);
					}
				return;
			} 
		}
	else
		{
			$testprog = $testprog*-1;
			$virtual = "virtual";
			readingsSingleUpdate($hash, "prog_mode", "$testprog"  , 1);
		
		}
	#########################################

	# invertierung position
	if 	( $invers eq "1")
		{
		 $oldstate = 100 - $oldstate;
		 $autostop = 100 - $autostop;
		}
	#########################################
	
	Log3($name,5,"Siro_Set: teste autostop: $autostop < 100  $oldstate < $autostop - $cmd");
	
	# erkennung autostopfunktiuon
	if ($cmd eq "on" && $autostop < 100 && $oldstate < $autostop )
		{
			$cmd="position";
			$args[1]=$autostop;
			$newposstate = $args[1];		 # position autostop
			$timetorun = $timetoclose/100*$newposstate;	
			Log3($name,1,"Siro_Set: autostop gefunden mapping auf position erfolgt: $newposstate  ");
		}
	#########################################
	
	# erkennung downlimit funktion
	if ($downlimit < 100 && $operationmode eq "1")
		{
			if ($cmd eq 'position' && $downlimit < $newposstate)
				{
					$args[1]=$downlimit;
					$newposstate = $args[1];		# Anzufahrende Position in Prozent   
					$timetorun = $timetoclose/100*$newposstate;	
					Log3($name,1,"Siro_Set: drive down limit reached: $newposstate ");
				}
			if ($cmd eq 'on')
				{
					$cmd="position";
					$args[1]=$downlimit;
					$newposstate = $args[1];		# Anzufahrende Position in Prozent   
					$timetorun = $timetoclose/100*$newposstate;	
					Log3($name,1,"Siro_Set: drive down limit reached: $newposstate  ");
				}
		}
	#########################################
	
	# on/off Umschaltung ohne zwischenzeitliches Anhalten
	if ($cmd eq 'on' && $timebetweenmsg < $timetoopen && $lastaction eq 'off') # Prüfe auf direkte Umschaltung on - off
		{
			$oldposition =  $beforeaction_position; 
			$newposition = $timebetweenmsg/$offdirekttime;
			$finalposition = $oldposition-$newposition;
			if ($limitedmode eq "on")
				{
					$finalposition ="50";
				}
			$hash->{helper}{lastMsg} = $aktMsg;
			$hash->{helper}{aktMsg} = "stop".' '.int($finalposition).' '.gettimeofday();
			$hash->{helper}{positiontimer} = $timebetweenmsg;
			$hash->{helper}{position} = int($finalposition);
			
			if ($mode ne "physical")
				{
					Siro_SendCommand($hash, 'stop');
				}
			$aktMsg = $hash->{helper}{aktMsg} ;
			@last_action_array=split(/ /,$aktMsg);
			$lastaction = $last_action_array[0];
			$lastaction_position = $last_action_array[1];
			$lastaction_time = $last_action_array[2];
			$befMsg = $hash->{helper}{lastMsg};
			@before_action_array=split(/ /,$befMsg);
			$beforeaction_position = $before_action_array[1];
			$timebetweenmsg = $testtimestart-$last_action_array[2]; # Zeit zwischen dem aktuellen und letzten Befehl
			$timebetweenmsg = (int($timebetweenmsg*10)/10);								
		}
	#########################################
	
	# off/on Umschaltung ohne zwischenzeitliches Anhalten
	if ($cmd eq 'off' && $timebetweenmsg < $timetoclose && $lastaction eq 'on')
		{
			$oldposition =  $beforeaction_position; 
			$newposition = $timebetweenmsg/$ondirekttime;
			$finalposition = $oldposition+$newposition;
			if ($limitedmode eq "on")
				{
					$finalposition ="50";
				}
			$hash->{helper}{lastMsg} = $aktMsg;
			$hash->{helper}{aktMsg} = "stop".' '.int($finalposition).' '.gettimeofday();
			$hash->{helper}{positiontimer} = $timebetweenmsg;
			
			if ($mode ne "physical")
				{
					Siro_SendCommand($hash, 'stop');
				}
			$aktMsg = $hash->{helper}{aktMsg} ;
			@last_action_array=split(/ /,$aktMsg);
			$lastaction = $last_action_array[0];
			$lastaction_position = $last_action_array[1];
			$lastaction_time = $last_action_array[2];
			$befMsg = $hash->{helper}{lastMsg};
			@before_action_array=split(/ /,$befMsg);
			$beforeaction_position = $before_action_array[1];
			$timebetweenmsg = gettimeofday()-$last_action_array[2]; # Zeit zwischen dem aktuellen und letzten Befehl
			$timebetweenmsg = (int($timebetweenmsg*10)/10);		
		}	
	#########################################
	
	# Positionsberechnung bei einem Stopp-Befehl 
	if ($cmd eq 'stop')
	{
		# lösche interne timer - setze reading action auf no action
		
		readingsSingleUpdate($hash, "action",'no action', 1); 
		RemoveInternalTimer($hash);
				
		Log3($name,5,"Siro_Set: cmd stop  timebetweenmsg -> $timebetweenmsg ondirekttime -> $ondirekttime offdirekttime -> $offdirekttime ");
		
		$oldposition =  $beforeaction_position; 
		if ($ondirekttime eq "0" || $offdirekttime eq "0") # Fehler division durch 0 abfanken bei ungesetzten attributen
			{
				Log3($name,5,"Siro_Set: cmd stop -> Positionserrechnung ohne gesetzte Attribute , Finalposition wird auf 50 gesetzt ");
				$finalposition ="50";
				$args[1] = $finalposition;
			}
		else
		{
			Log3($name,5,"Siro_Set: stop - Lastaction -> $lastaction $lastaction_position $oldposition");
			if ($lastaction eq 'position')
				{
					if ( $lastaction_position > $oldposition)
						{
						$lastaction="on";
						}
					else
						{
						$lastaction="off";				
						}
						
				}
			if ($lastaction eq 'on')# Letzte Fahrt runter (on)
				{
					$newposition = $timebetweenmsg/$ondirekttime;
					$finalposition = $oldposition+$newposition;
				}   
			elsif ($lastaction eq 'off')# Letzte Fahrt hoch (off)
				{
					$newposition = $timebetweenmsg/$offdirekttime;
					$finalposition = $oldposition-$newposition;
				}
			elsif ($lastaction eq 'fav')# Letzte Fahrt unbekannt
				{
					#Fahrtrichtung ermitteln - dafür Position von lastmsg nehmen $beforeaction_position
					$favorit_position =$time_to_favorite/$ondirekttime;
					Log3($name,5,"Siro_Set: drive to position aborted (target position:$favorit_position %) : (begin possition $beforeaction_position %) ");
					
				if ($favorit_position < $beforeaction_position)# Fahrt hoch
					{
						$newposition = $timebetweenmsg/$offdirekttime;
						$finalposition = $oldposition-$newposition;
					} 
					
				if ($favorit_position > $beforeaction_position)# Fahrt runter
					{
					$newposition = $timebetweenmsg/$ondirekttime;
					$finalposition = $oldposition+$newposition;
					} 
					
					Log3($name,5,"Siro_Set position: $finalposition ");	
				}
				
			if ($finalposition < 0){$finalposition = 0;}
			if ($finalposition > 100){$finalposition = 100;}  
			if ($limitedmode eq "on"){$finalposition ="50";}
			$finalposition = int($finalposition); # abrunden
			$args[1] = $finalposition;
		}
	}
	######################################### 
	
	# Hardware-Favorit anfahren 
	if ($cmd eq 'fav')
	{
	Log3($name,5,"Siro_Set fav: $cmd ");
		if (!defined $time_to_favorite)
			{
				$time_to_favorite=5;
			} # Tmp ggf. ändern 
		
		# if ( $time_to_favorite eq "undef")
			# {
				# $time_to_favorite=5;
				# #return;
			# } 
	
		if ($ondirekttime eq "0" || $offdirekttime eq "0") # Fehler division durch 0 abfanken bei ungesetzten attributen
			{
				Log3($name,1,"Siro_Set: set cmd fav -> Favoritberechnung ohne gesetzte Attribute , aktion nicht möglich");
				return;
			}
	
		$favorit_position =$time_to_favorite/$ondirekttime;  # Errechnet nur die Position, die von oben angefahren wurde. pos
		$args[0] = $cmd;
		$args[1] = int($favorit_position);
		
		if($time_to_favorite eq 'undef')
			{
				Log3($name,1,"Siro_Set: function position limited without attr time_down_to_favorite");
				$time_to_favorite ="1";
				$args[1] ="50";
				# new
				if ($mode ne "physical")
				{
				$args[2] = 'longstop';
				$args[0] = 'stop';
				Siro_SendCommand($hash, @args);
				readingsSingleUpdate($hash, "position",'50', 1); 
				readingsSingleUpdate($hash, "state",'50', 1);
				}
				return;
			}
		
		$args[2] = 'longstop';
		$hash->{helper}{lastMsg} = $aktMsg;
		$hash->{helper}{aktMsg} = $args[0].' '.$args[1].' '.gettimeofday();
		$hash->{helper}{positiontimer} = $timebetweenmsg;
		$cmd ='stop';
		$args[0] = $cmd;
		
		if ($mode ne "physical")
			{
				Siro_SendCommand($hash, @args);
			}
		
		my $position = $hash->{helper}{position}; # Position für die Zeitberechnung speichern
		$hash->{helper}{position}=int($favorit_position);
		Siro_UpdateState( $hash, int($favorit_position), '', '', 1 );
		#Fahrtrichtung ermitteln - dafür Position von lastmsg nehmen $beforeaction_position
		$runningtime = 0;
		
		if ($favorit_position < $position)# Fahrt hoch
			{
				readingsSingleUpdate($hash, "action",'up to favorite', 1); #tmp
				my $change = $position - $favorit_position; # änderung in %
				$runningtime = $change*$offdirekttime;
			} 
		
		if ($favorit_position > $position)# Fahrt runter
			{
				readingsSingleUpdate($hash, "action",'down to favorite', 1); #tmp
				my $change = $favorit_position - $position ; # Änderung in %
				$runningtime = $change*$ondirekttime;
			}
		 
		InternalTimer($testtimestart+$runningtime,"Siro_Position_fav",$hash,0); # state auf Stopp setzen nach Erreichen der Fahrtdauer
		return;
	}
	#########################################
	
	# Teste auf Position '0' oder '100' -> Mappen auf 'on' oder 'off'
	if ($cmd eq 'on'){$args[1] = "100";}
	if ($cmd eq 'off'){$args[1] = "0";}
	#########################################
	
	#Aktualisierung des Timers (Zeit zwischen den Befehlen, lastmsg und aktmsg)
	$hash->{helper}{lastMsg} = $hash->{helper}{aktMsg};
	$hash->{helper}{aktMsg} = $args[0].' '.$args[1].' '.gettimeofday();
	$hash->{helper}{positiontimer} = $timebetweenmsg;
	#########################################
	
	if ( defined($newposstate) )
		{
			if($newposstate eq "0")
				{
					$cmd="off";
					Log3($name,5,"recognized position  0 ");
				} 
			elsif ($newposstate eq "100")
				{
					$cmd="on";
					Log3($name,5,"recognized position 100 ");
				}
		}								
			  
	# Direkte Positionsanfahrt 
	if ($cmd eq 'position')
		{
		Log3($name,5,"Siro_Set: nodrive -> $nodrive");
		if (($ondirekttime eq "0" || $offdirekttime eq "0" || $nodrive eq "true") && $testchannel ne "0" ) 		# Fehler division durch 0 abfanken bei ungesetzten attributen
			{
				Log3($name,1,"Siro_Set: Positionsanfahrt ohne gesetzte Attribute , aktion nicht möglich -> abbruch");
				return "Positionsanfahrt ohne gesetzte Attribute time_to_open und time_to_close nicht moeglich";
			}
			my $aktposition=$hash->{helper}{position};  
			# Fahrt nach oben
			if ($newposstate < $aktposition)
				{
					if ($action eq "no action")
					{
					$action = 'up to position '.$newposstate;
					readingsSingleUpdate($hash, "action",$action, 1); #tmp
					} 
					$cmd='off';
					my $percenttorun = $aktposition-$newposstate;
					$runningtime = $percenttorun*$offdirekttime;
					$timetorun=$runningtime;
					Log3($name,5,"Siro_Set: direkt positiondrive: -> timing:($runningtime = $percenttorun*$offdirekttime) -> open runningtime:$runningtime - modification in % :$percenttorun");
				}
			#Fahrt nach unten
			if ($newposstate > $aktposition)
				{
					if ($action eq "no action")
					{
					$action = 'down to position '.$newposstate;
					readingsSingleUpdate($hash, "action",$action, 1); #tmp
					} 
					$cmd='on';
					my $percenttorun = $newposstate-$aktposition;
					$runningtime = $percenttorun*$ondirekttime;
					$timetorun=$runningtime;
					Log3($name,5,"Siro_Set: direkt positiondrive: -> timing: ($runningtime = $percenttorun*$ondirekttime) -> close runningtime:$runningtime - modification in % :$percenttorun");
				} 
			$virtual = "virtual"; # keine Stateänderung
			Log3($name,5,"Siro_Set: direkt positiondrive: -> setting timer to $runningtime");
			InternalTimer($testtimestart+$runningtime,"Siro_Position_down_stop",$hash,0); 
		}
	#########################################
	
	# abarbeitung weiterer befehle 
	if($cmd eq 'on') 
		{
		if ($action eq "no action")
			{
				$action = 'down ';
				readingsSingleUpdate($hash, "action",$action, 1); #tmp
				# voraussichtliche fahrzeit berechnen bis 100%
				my $aktposition=$hash->{helper}{position}; 
				my $percenttorun = 100 - $aktposition;
				$runningtime = $percenttorun*$ondirekttime;
				$timetorun=$runningtime;
				Log3($name,4,"Siro_Set: aktposition -> $aktposition - percenttorun -> $percenttorun - ondirekttime -> $ondirekttime");
				Log3($name,4,"Siro_Set: voraussichtliche fahrdauer bis 100%: -> $runningtime");
				InternalTimer(gettimeofday()+$timetorun+1, "Siro_Stopaction", $hash, 0); # action auf Stopp
			}
		$newState = '100';
		$positiondrive = 100;
		} 
	elsif($cmd eq 'off') 
		{
		if ($action eq "no action")
			{
				$action = 'up ';
				readingsSingleUpdate($hash, "action",$action, 1); #tmp
				# voraussichtliche fahrzeit berechnen bis 0%
				my $aktposition=$hash->{helper}{position}; 
				my $percenttorun = $aktposition;
				$runningtime = $percenttorun*$offdirekttime;
				$timetorun=$runningtime;
				Log3($name,4,"Siro_Set: aktposition -> $aktposition - percenttorun -> $percenttorun - offdirekttime -> $offdirekttime");
				Log3($name,4,"Siro_Set: voraussichtliche fahrdauer bis 0%: -> $runningtime");
				InternalTimer(gettimeofday()+$timetorun+1, "Siro_Stopaction", $hash, 0); # action auf Stopp
			}
		$newState = '0';
		$positiondrive = 0;
		} 
	elsif($cmd eq 'stop') 
		{
			$newState = $finalposition;
			$positiondrive = $finalposition;
		} 
	elsif($cmd eq 'fav')
		{
		  $newState = $favorit_position;
		  $positiondrive = $favorit_position;
		}
	else 
		{
			$newState = $state;   #todo: Was mache ich mit der Positiondrive?
		}
#########################################

	if (!defined($virtual)){$virtual = "";}
	if (!defined($newposstate)){$newposstate = 0;}
	if (!defined($newposstate)){$newposstate = 0;}

	if ($virtual ne "virtual")   # Kein Stateupdate beim Anfahren einer Position 
		{
		
			if ($newposstate < 0){$newposstate = 0;}
			if ($newposstate > 100){$newposstate = 100;}
			$hash->{helper}{position}=$positiondrive;
			Log3($name,5,"Siro_Set: stateupdate erfolgt -> $positiondrive");
			
			#########################################	
			# invertiere position
			if 	( $invers eq "1")
				{
				my $noinvers = $newState;
				my $inversposition = 100 - $newState;
				$newState = $inversposition; 
				
				
				Log3($name,3,"Siro_Set: invertiere Position vor setstate - berechnet -> $noinvers - inverted -> $newState ");	
				}
			#########################################
			
			
			
			Siro_UpdateState( $hash, $newState, '', $updateState, 1 );
		} 
	else
		{
			Log3($name,5,"Siro_Set: kein stateupdate erfolgt");
			#Setze readings positiondrive und positiontime
			if ($newposstate < 0){$newposstate = 0;}
			if ($newposstate > 100){$newposstate = 100;}
			$hash->{helper}{position}=$newposstate;
		}

	$args[0] = $cmd;
	
	if (!defined($mode)){$mode ="virtual"};
	
	if($debugmode eq "1")
	{
		readingsSingleUpdate($hash, "DEBUG_SET",$debug, 1);
	}
	
	if ($mode ne "physical")
	{
		Log3($name,3,"Siro_set: handing over to Siro_Send_Command with following arguments: @args");
		Siro_SendCommand($hash, @args);
	}
	
	$hash->{helper}{MODE} = "virtual";
	$hash->{helper}{LastMODE} = $mode;
	my $testtimeend = gettimeofday();
	$runningtime =$testtimeend - $testtimestart;
	Log3($name,5,"Siro_set: runningtime -> $runningtime");
	
	return ;
} 

###########################################################################

sub Siro_UpdateState($$$$$) 
{
	my ($hash, $newState, $move, $updateState, $doTrigger) = @_;
	readingsBeginUpdate($hash);
	if ($newState < 0){$newState = 0;}
	if ($newState > 100){$newState = 100;}
	readingsBulkUpdate($hash,"state",$newState);
	readingsBulkUpdate($hash,"position",$newState);
	$hash->{state} = $newState;
	#$hash->{helper}{position} = $newState;
	readingsEndUpdate($hash, $doTrigger);
} 

#################################################################

sub Siro_Position_down_start($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	#my $timetoopen = AttrVal($name,'time_to_open', 'undef'); #tmp
	#my $timetoclose = AttrVal($name,'time_to_close', 'undef');#tmp
	my @args;
	$args[0] = 'on';
	my $virtual='virtual';
	Siro_SendCommand($hash, @args,, $virtual);
	Log3 $name, 5, "Siro_Position_down_start: completed";
	return;
}
#################################################################
sub Siro_Position_down_stop($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my @args;
	$args[0] = 'stop';
	if (!defined($args[1])){$args[1]="";}
	my $virtual='virtual';
	Siro_SendCommand($hash, @args, $virtual);
	my $positiondrive=$hash->{helper}{position};
	my $aktMsg = $hash->{helper}{aktMsg};
	$hash->{helper}{lastMsg} = $aktMsg;
	#$hash->{helper}{aktMsg} =  $args[0].' '.$args[1].' '.gettimeofday();
	$hash->{helper}{aktMsg} =  $args[0].' '.$positiondrive.' '.gettimeofday();
	
	# invertiere position
		my $invers = AttrVal($name,'invers_position', '0');

	if 	( $invers eq "1")
		{
		my $noinvers = $positiondrive;
		my $inversposition = 100 - $positiondrive;
		$positiondrive = $inversposition; 
		
		
		Log3($name,3,"Siro_Set: invertiere Position vor setstate - berechnet -> $noinvers - inverted -> $positiondrive ");	
		}
	readingsSingleUpdate($hash, "action",'no action', 1); #tmp	
	Siro_UpdateState( $hash, $positiondrive, '', '', 1 );
	Log3 $name, 5, "Siro_Position_down_stop: completed -> state:$positiondrive ";
	return;
}
#################################################################
sub Siro_Position_fav($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my @args;
	my $aktMsg = $hash->{helper}{aktMsg};
	$hash->{helper}{lastMsg} = $aktMsg;
	my @last_action_array=split(/ /,$aktMsg);
	$hash->{helper}{aktMsg} =  'stop'.' '.$last_action_array[1].' '.gettimeofday();
	readingsSingleUpdate($hash, "action",'no action', 1); #tmp
	Log3 $name, 5, "Siro_Position_fav: completed";
	return;
}

#################################################################

sub Siro_Sequence($)
{

	my $debug;               
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3($name,1,"Siro_Sequence:START");
	my @args;
	my @sequence = split(/,/,$hash->{sequence});
	my $debugmode = AttrVal($name,'debug_mode', '0');
	my $cmd = shift @sequence;
	my $timer = shift @sequence;
	$debug=$debug.' '.$cmd.' '.$timer.' '.@sequence;
	$hash->{sequence} = join(",",@sequence); # 3 min Programmiermodus
	$args[0]=$cmd;
	Siro_SendCommand($hash, @args, 'virtual');
	
	if ( defined($timer) )
	{
		InternalTimer(gettimeofday()+$timer, "Siro_Sequence", $hash, 0); 
    $debug=$debug.'- Erneute Aufrufsequenz';
	}
	else
	{
		$debug=$debug.'- Sequenz beendet, ATTR time_to _fav neu berechnet und gesetzt, progmode beendet';
		readingsSingleUpdate($hash, "prog_mode", "inaktiv "  , 1);
		delete($hash->{sequence});
		my $timetoclose = AttrVal($name,'time_to_close', '10');
		my $ondirekttime = 	$timetoclose/100; 	 		 # Zeit für 1 Prozent Runterfahrt
		my $position = $hash->{helper}{position};
		my $newfav = $ondirekttime * $position;  	 	
		$attr{$name}{time_down_to_favorite} = $newfav;
	}
	if($debugmode eq "1")
	{
		readingsSingleUpdate($hash, "DEBUG_SEQUENCE",$debug, 1);
	}
	
	Log3 $name, 5, "Siro_Sequence: completed";	
  return;
}
###############################################################

sub Siro_Setgroup($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $grouphashraw=$hash->{helper}{affected_devices_h};	
	my @grouphash=split(/,/,$grouphashraw);
	my $groupnamesraw=$hash->{helper}{affected_devices_n};
	my @groupnames=split(/,/,$groupnamesraw);
	my $groupcommandraw=$hash->{helper}{groupcommand};
	my @groupcommand=split(/,/,$groupcommandraw);
	Log3($name,5,"Siro_Setgroup : @groupnames -> $groupcommandraw  ");

	my $count =0;
	
	foreach my $senddevice(@groupnames) 
	{
		my @args;
		#Log3($name,5,"----------------------------");
		Log3($name,5,"Siro_Setgroup: count -> $count ");
		Log3($name,5,"Siro_Setgroup: senddevice -> $senddevice ");
		Log3($name,5,"Siro_Setgroup: testhash -> $grouphash[$count] ");
		Log3($name,5,"Siro_Setgroup: command -> $groupcommand[1] $groupcommand[2] ");
		#Log3($name,5,"----------------------------");
		$args[0]=$groupcommand[1];
		$args[1]=$groupcommand[2];
		Log3($name,5,"Siro_Setgroup: aufruf -> $grouphash[$count],$senddevice, @args  ");
		Log3($name,5,"Siro_Setgroup: set $senddevice $groupcommand[1] $groupcommand[2]");
		#my $cs = "set Siro_5B417081 on";
		my $cs ="set $senddevice $groupcommand[0] $groupcommand[2]";
		my $client_hash = $grouphash[$count];
		Log3($name,5,"Siro_Setgroup: command -> ".$cs);
		my $errors  = AnalyzeCommandChain(undef, $cs);;
		
		$count++;
	}
	return;
}
###############################################################

sub Siro_Stop($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my @args;
	$args[0] = "stop";
	#my ( $hash, $name, @args ) = @_;
	readingsSingleUpdate($hash, "action",'no action', 1); #tmp
	Log3($name,0,"Siro_Stop: x-for-timer stop -> @args  ");
	Siro_Set($hash, $name, @args);
	
	return;
}
###############################################################

sub Siro_Restartcmd($)
{
	my $incomming = $_[0];
	my @msgarray=split(/ /,$incomming);
	my $name = $msgarray[1];
	#my $hash = $msgarray[1];
	#my $name = $hash->{NAME};
	my $cs ="set $incomming";
	Log3($name,3,"Siro_Restartcmd: incomming -> $incomming ");
	Log3($name,3,"Siro_Restartcmd: command -> ".$cs);
		
	my $errors  = AnalyzeCommandChain(undef, $cs);
	
	return;
}
###############################################################

sub Siro_Stopaction($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3($name,5,"Siro_Stopaction: setze no action ");
	readingsSingleUpdate($hash, "action",'no action', 1); #tmp
	return;
}
###############################################################readingsSingleUpdate($hash, "action",$action, 1); #tmp
sub Siro_Testgroup($$)
{
my ( $hash, $id ) = @_;
my $name = $hash->{NAME};
my $testid;
my $testidchan;
my @groupnames;
my @grouphash;

foreach my $testdevices(keys %{$modules{Siro}{defptr}})#
		{
		 
			$testid = substr($testdevices, 0, 7);
			$testidchan = substr($testdevices, 7, 1);
			Log3($name,5,"Siro_Testgroup: groupdevice search device $testid -> test device -> $testdevices-$testidchan ");
			 if ($id eq $testid )
			 {
				my $lh = $modules{Siro}{defptr}{$testdevices}; #def	
				my $namex = $lh->{NAME}; 
				my $channelx = $lh->{CHANNEL};
				Log3($name,5,"Siro_Testgroup: device for group found -> $namex lh -$lh");
					 if ($channelx ne "0")
					 {
						Log3($name,5,"Siro_Testgroup: device for group found -> $namex hash -> $lh");
						push(@groupnames,$namex);
						push(@grouphash,$lh); # betreffendes hash zur gruppe zufügen
					 }
			 }	  
		}
		
		my $hashstring;
		foreach my $target (@grouphash)
		{
			$hashstring=$hashstring.$target.",";
		}
		chop($hashstring);
		$hash->{helper}{affected_devices_h} = "$hashstring";
		
		my $devicestring;
		foreach my $target (@groupnames)
		{
			$devicestring=$devicestring.$target.",";
		}
		
		chop($devicestring);
		$hash->{helper}{affected_devices_n} = $devicestring;
		
		return @groupnames;
	}
	
#############################################
 sub Siro_icon($)
 {
 #return 'fts_shutter_1w_'.(int($state/10)*10);
	my ($id) = @_;
	my $lh = $modules{Siro}{defptr}{$id};
	my $position =$lh->{helper}{position};
 
 
 
 
 my $xsvg ="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>
<!-- Created with Inkscape (http://www.inkscape.org/) -->

<svg
   xmlns:dc=\"http://purl.org/dc/elements/1.1/\"
   xmlns:cc=\"http://creativecommons.org/ns#\"
   xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"
   xmlns:svg=\"http://www.w3.org/2000/svg\"
   xmlns=\"http://www.w3.org/2000/svg\"
   version=\"1.0\"
   width=\"585\"
   height=\"585\"
   viewBox=\"0 0 585 585\"
   id=\"svg2\">
  <defs
     id=\"defs12\" />
  <metadata
     id=\"metadata4\">
Created by potrace 1.8, written by Peter Selinger 2001-2007
<rdf:RDF>
  <cc:Work
     rdf:about=\"\">
    <dc:format>image/svg+xml</dc:format>
    <dc:type
       rdf:resource=\"http://purl.org/dc/dcmitype/StillImage\" />
    <dc:title></dc:title>
  </cc:Work>
</rdf:RDF>
</metadata>
  <path
     d=\"m 14.173228,80.136391 442.204712,0 0,29.186439 -442.204712,0 z\"
     id=\"rect3764\"
     style=\"fill:#000000;fill-opacity:1;stroke-width:3.1960001;stroke-linecap:round;stroke-miterlimit:4\" />
</svg>
";

 return $xsvg;
 
 }
1;

=pod

=item summary    Supports rf shutters from Siro
=item summary_DE Unterst&uumltzt Siro Rollo-Funkmotoren


=begin html

<a name="Siro"></a>
<h3>Siro protocol</h3>
<ul>
   
   <br> A <a href="#SIGNALduino">SIGNALduino</a> device (must be defined first).<br>
   
   <br>
        Since the protocols of Siro and Dooya are very similar, it is currently difficult to operate these systems simultaneously via one "IODev". Sending commands works without any problems, but distinguishing between the remote control signals is hardly possible in SIGNALduino. For the operation of the Siro-Module it is therefore recommended to exclude the Dooya protocol (16) in the SIGNALduino, via the whitelist. In order to detect the remote control signals correctly, it is also necessary to deactivate the "manchesterMC" protocol (disableMessagetype manchesterMC) in the SIGNALduino. If machester-coded commands are required, it is recommended to use a second SIGNALduino.<br>
 <br>
 <br>

   
  <a name="Sirodefine"></a>
   <br>
  <b>Define</b>
   <br>
  <ul>
    <code>define&lt; name&gt; Siro &lt;id&gt;&lt;channel&gt; </code>
  <br>
 <br>
   The ID is a 7-digit hex code, which is uniquely and firmly assigned to a Siro remote control. Channel is the single-digit channel assignment of the remote control and is also hexadecimal. This results in the possible channels 0 - 15 (hexadecimal 0-F). 
A unique ID must be specified, the channel (channel) must also be specified. 
An autocreate (if enabled) automatically creates the device with the ID of the remote control and the channel.

    <br><br>

    Examples:<br><br>
    <ul>
	<code>define Siro1 Siro AB00FC1</code><br>       Creates a Siro-device called Siro1 with the ID: AB00FC and Channel: 1<br>
    </ul>
  </ul>
  <br>

  <a name="Siroset"></a>
  <b>Set </b><br>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;position&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    stop
    pos (0...100) 
    prog  
    fav
    </pre>
    
    Examples:<br><br>
    <ul>
      <code>set Siro1 on</code><br>
      <code>set Siro1 off</code><br>
      <code>set Siro1 position 50</code><br>
      <code>set Siro1 fav</code><br>
      <code>set Siro1 stop</code><br>
	    <code>set Siro1 set_favorite</code><br>
    </ul>
    <br>
     <ul>
set Siro1 on                           moves the roller blind up completely (0%)<br>
set Siro1 off                           moves the roller blind down completely (100%)<br>
set Siro1 stop                        stops the current movement of the roller blind<br>
set Siro1 position 45              moves the roller blind to the specified position (45%)<br>
set Siro1 45                           moves the roller blind to the specified position (45%)<br>
set Siro1 fav                          moves the blind to the hardware-programmed favourite middle position<br>
set Siro1 prog                       corresponds to the "P2" button on the remote control, the module is set to programming mode (3 min).<br>
set Siro1 set_favorite               programs the current roll position as hardware middle position. The attribute time_down_to_favorite is recalculated and set. <br>
</ul>
    <br>
    Notes:<br><br>
    <ul>
      <li>If the module is in programming mode, the module detects successive stop commands because they are absolutely necessary for programming. In this mode, the readings and state are not updated. The mode is automatically terminated after 3 minutes. The remaining time in programming mode is displayed in the reading "pro_mode". The remaining time in programming mode is displayed in the reading "pro_mode". The programming of the roller blind must be completed during this time, otherwise the module will no longer accept successive stop commands. The display of the position, the state, is a calculated position only, since there is no return channel to status message. Due to a possible missing remote control command, timing problem etc. it may happen that this display shows wrong values sometimes. When moving into an end position without stopping the movement (set Siro1[on/off]), the status display and real position are synchronized each time the position is reached. This is due to the hardware and unfortunately not technically possible.
      </li>
     	</ul>
  </ul>
  <br>

  <b>Get</b> 
  <ul>N/A</ul><br>

  <a name="Siroattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        The IODev must contain the physical device for sending and receiving the signals. Currently a SIGNALduino or SIGNALesp is supported.
        Without the specification of the "Transmit and receive module" "IODev", a function is not possible. 
    </li><br>

  <a name="channel"></a>
    <li>channel (since V1.09 no longer available)<br>
        contains the channel used by the module for sending and receiving. 
        This is already set when the device is created.

    </li><br>
        <a name="channel_send_mode_1 "></a>
    <li>channel_send_mode_1 <br>
        contains the channel that is used by the module in "operation_mode 1" to send.
        This attribute is not used in "operation_mode 0"
    </li><br>
        

    <a name="operation_mode"></a>
    <li>operation_mode<br>
        Mode 0<br><br>
        This is the default mode. In this mode, the module uses only the channel specified by the remote control or the "channel" attribute.  In the worst case, signals, timing problems etc. missed by FHEM can lead to wrong states and position readings. These are synchronized again when a final position is approached.
        <br><br>Mode 1<br><br>
        Extended mode. In this mode, the module uses two channels. The standard channel "channel" for receiving the remote control. This should no longer be received by the blind itself. And the "channel_send_mode_1", for sending to the roller blind motor. For this purpose, a reconfiguration of the motor is necessary. This mode is "much safer" in terms of the representation of the states, since missing a signal by FHEM does not cause the wrong positions to be displayed. The roller blind only moves when FHEM has received the signal and passes it on to the motor.<br>
        Instructions for configuring the motor will follow.
    </li><br>

    <a name="time_down_to_favorite"></a>
    <li>time_down_to_favorite<br>
        contains the movement time in seconds, which the roller blind needs from 0% position to the hardware favorite center position. This time must be measured and entered manually.
        Without this attribute, the module is not fully functional.</li><br>

    <a name="time_to_close"></a>
    <li>time_to_close<br>
        contains the movement time in seconds required by the blind from 0% position to 100% position. This time must be measured and entered manually. 
        Without this attribute, the module is not fully functional.</li><br>

       <a name="time_to_open"></a>
    <li>time_to_open<br>
        contains the movement time in seconds required by the blind from 100% position to 0% position. This time must be measured and entered manually.
        Without this attribute, the module is not fully functional.</li><br>

		 <a name="prog_fav_sequence"></a>
    <li>prog_fav_sequence<br>
        contains the command sequence for programming the hardware favorite position</li><br>
		
		<a name="debug_mode [0:1]"></a>
    <li>debug_mode [0:1]<br>
        In mode 1, additional readings are created for troubleshooting purposes, in which the output of all module elements is output. Commands are NOT physically sent.</li><br>
		
			<a name="Info"></a>
    <li>Info<br>
        The attributes webcmd and devStateIcon are set once when the device is created and are adapted to the respective mode of the device during operation. The adaptation of these contents only takes place until they have been changed by the user. After that, there is no longer any automatic adjustment.</li><br>

  </ul>
</ul>

=end html




=begin html_DE



<a name="Siro"></a>
<h3>Siro protocol</h3>
<ul>
   
   <br> Ein <a href="#SIGNALduino">SIGNALduino</a>-Geraet (dieses sollte als erstes angelegt sein).<br>
   
   <br>
        Da sich die Protokolle von Siro und Dooya sehr &auml;hneln, ist ein gleichzeitiger Betrieb dieser Systeme ueber ein "IODev" derzeit schwierig. Das Senden von Befehlen funktioniert ohne Probleme, aber das Unterscheiden der Fernbedienungssignale ist in Signalduino kaum m&ouml;glich. Zum Betrieb der Siromoduls wird daher empfohlen, das Dooyaprotokoll im SIGNALduino (16) &uuml;ber die Whitelist auszuschliessen. Zur fehlerfreien Erkennung der Fernbedienungssignale ist es weiterhin erforderlich im SIGMALduino das Protokoll "manchesterMC" zu deaktivieren (disableMessagetype manchesterMC). Wird der Empfang von machestercodierten Befehlen benoetigt, wird der Betrieb eines zweiten Signalduinos empfohlen.<br>
 <br>
 <br>

   
  <a name="Sirodefine"></a>
   <br>
  <b>Define</b>
   <br>
  <ul>
    <code>define &lt;name&gt; Siro &lt;id&gt; &lt;channel&gt;</code>
  <br>
 <br>
   Bei der <code>&lt;ID&gt;</code> handelt es sich um einen 7-stelligen Hexcode, der einer Siro Fernbedienung eindeutig und fest zugewiesen ist. <code>&lt;Channel&gt;</code> ist die einstellige Kanalzuweisung der Fernbedienung und ist ebenfalls hexadezimal. Somit ergeben sich die m&ouml;glichen Kan&auml;le 0 - 15 (hexadezimal 0-F).
Eine eindeutige ID muss angegeben werden, der Kanal (Channel) muss ebenfalls angegeben werden. <br>
Ein Autocreate (falls aktiviert), legt das Device mit der ID der Fernbedienung und dem Kanal automatisch an.

    <br><br>

    Beispiele:<br><br>
    <ul>
	<code>define Siro1 Siro AB00FC1</code><br>       erstellt ein Siro-Geraet Siro1 mit der ID: AB00FC und dem Kanal: 1<br>
    </ul>
  </ul>
  <br>

  <a name="Siroset"></a>
  <b>Set </b><br>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;position&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    stop
    pos (0..100) 
    prog  
    fav
    </pre>
    
    Beispiele:<br><br>
    <ul>
      <code>set Siro1 on</code><br>
      <code>set Siro1 off</code><br>
      <code>set Siro1 position 50</code><br>
      <code>set Siro1 fav</code><br>
      <code>set Siro1 stop</code><br>
	  <code>set Siro1 set_favorite</code><br>
	  <code>set Siro1 down_for_timer 5</code><br>
	  <code>set Siro1 up_for_timer 5</code><br>
	  <code>set Siro1 set_favorite</code><br>
    </ul>
    <br>
     <ul>
set Siro1 on                           f&auml;hrt das Rollo komplett hoch (0%)<br>
set Siro1 off                           f&auml;hrt das Rollo komplett herunter (100%)<br>
set Siro1 stop                        stoppt die aktuelle Fahrt des Rollos<br>
set Siro1 position 45              f&auml;hrt das Rollo zur angegebenen Position (45%)<br>
set Siro1 45                           f&auml;hrt das Rollo zur angegebenen Position (45%)<br>
set Siro1 fav                          f&auml;hrt das Rollo in die hardwarem&auml;ssig programmierte Mittelposition<br>
et Siro1 down_for_timer 5                          f&auml;hrt das Rollo 5 Sekunden nach unten<br>
et Siro1 uown_for_timer 5                         f&auml;hrt das Rollo 5 Sekunden nach oben<br>
set Siro1 prog                       entspricht der "P2" Taste der Fernbedienung. Das Modul wird in den Programmiermodus versetzt (3 Min.)<br>
set Siro1 set_favorite               programmiert den aktuellen Rollostand als Hardwaremittelposition, das ATTR time_down_to_favorite wird neu berechnet und gesetzt. <br>
</ul>
    <br>
    Hinweise:<br><br>
    <ul>
      <li>Befindet sich das Modul im Programmiermodus, werden aufeinanderfolgende Stoppbefehle vom Modul erkannt, da diese zur Programmierung zwingend erforderlich sind. In diesem Modus werden die Readings und das State nicht aktualisiert. Der Modus wird nach 3 Minuten automatisch beendet. Die verbleibende Zeit im Programmiermodus wird im Reading "pro_mode" dargestellt. Die Programmierung des Rollos muss in dieser Zeit abgeschlossen sein, da das Modul andernfalls keine aufeinanderfolgenden Stoppbefehle mehr akzeptiert.
Die Anzeige der Position, des States, ist eine ausschliesslich rechnerisch ermittelte Position, da es keinen R&uumlckkanal zu Statusmeldung gibt. Aufgrund eines ggf. verpassten Fernbedienungsbefehls, Timingproblems etc. kann es vorkommen, dass diese Anzeige ggf. mal falsche Werte anzeigt. Bei einer Fahrt in eine Endposition, ohne die Fahrt zu stoppen (set Siro1 [on/off]), werden Statusanzeige und echte Position bei Erreichen der Position jedes Mal synchronisiert. Diese ist der Hardware geschuldet und technisch leider nicht anders l&ouml;sbar.
      </li>
     	</ul>
  </ul>
  <br>

  <b>Get</b> 
  <ul>N/A</ul><br>

  <a name="Siroattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Das IODev muss das physische Ger&auml;t zum Senden und Empfangen der Signale enthalten. Derzeit wird ein SIGNALduino bzw. SIGNALesp unterstützt.
        Ohne der Angabe des "Sende- und Empfangsmodul" "IODev" ist keine Funktion moeglich.</li><br>

    
    <a name="channel_send_mode_1 "></a>
    <li>channel_send_mode_1 <br>
        Beinhaltet den Kanal, der vom Modul im "operation_mode 1" zum Senden genutzt wird. 
        Dieses Attribut wird in "operation_mode 0" nicht genutzt
    </li><br>
        
		   <a name="down_limit_mode_1 "></a>
    <li>down_limit_mode_1 <br>
        Bei gesetztem Attribut wird das Rollo bei einem Fahrt nach unten nur bis zur angegebenen Position gefahren, egal ob das Kommando über das Modul oder die Fernbedienung ausgloest wurde. Diese Funktion ist nur im Mode 1 aktiv.
    </li><br>
	
		<a name="down_auto_stop "></a>
    <li>down_auto_stop <br>
        Bei gesetztem Attribut fährt das Rollo bei einer Fahrt nach unten nur bis zur angegebenen Position. Eine weiterfahrt erfolgt nach nochmaligem Befehl. Diese Funktion greift nur bei dem Kommando on ( close ) . Hierbei ist es egal, ob das Kommando über das Modul oder die Fernbedienung ausgelöst wird.
    </li><br>

    <a name="operation_mode"></a>
    <li>operation_mode<br>
        Mode 0<br><br>
        Dies ist der Standardmodus. In diesem Modus nutz das Modul nur den Kanal, der von der Fernbedienung vorgegeben ist.  Hier kann es durch von FHEM verpasste Signale, Timingproblemen etc. im schlechtesten Fall zu falschen States und Positionsreadings kommen. Diese werden bei Anfahrt einer Endposition wieder synchronisiert.
        <br><br>Mode 1<br><br>
        Erweiterter Modus. In diesem Modus nutzt das Modul zwei Kan&auml;le. Den Standardkanal "channel" zum Empfangen der Fernbedienung. Dieser sollte nicht mehr durch das Rollo selbst empfangen werden. Und den "channel_send_mode_1", zum Senden an den Rollomotor. Hierzu ist eine Umkonfigurierung des Motors erforderlich. Dieser Modus ist in Bezug auf die Darstellung der States "deutlich sicherer", da ein Verpassen eines Signals durch FHEM nicht dazu f&uumlhrt, das falsche Positionen angezeigt werden. Das Rollo f&auml;hrt nur dann, wenn FHEM das Signal empfangen hat und an den Motor weiterreicht.
        Eine Anleitung zur Konfiguration des Motors folgt.
    </li><br>

    <a name="time_down_to_favorite"></a>
    <li>time_down_to_favorite<br>
        beinhaltet die Fahrtzeit in Sekunden, die das Rollo von der 0% Position bis zur Hardware-Favoriten-Mittelposition ben&ouml;tigt. Diese Zeit muss manuell gemessen werden und eingetragen werden.
        Ohne dieses Attribut ist das Modul nur eingeschr&auml;nkt funktionsf&auml;hig.</li><br>

    <a name="time_to_close"></a>
    <li>time_to_close<br>
        beinhaltet die Fahrtzeit in Sekunden, die das Rollo von der 0% Position bis zur 100% Position ben&ouml;tigt. Diese Zeit muss manuell gemessen werden und eingetragen werden.
        Ohne dieses Attribut ist das Modul nur eingeschr&auml;nkt funktionsf&auml;hig.</li><br>

       <a name="time_to_open"></a>
    <li>time_to_open<br>
        beinhaltet die Fahrtzeit in Sekunden, die das Rollo von der 100% Position bis zur 0% Position ben&ouml;tigt. Diese Zeit muss manuell gemessen werden und eingetragen werden.
        Ohne dieses Attribut ist das Modul nur eingeschr&auml;nkt funktionsf&auml;hig.</li><br>

		 <a name="prog_fav_sequence"></a>
    <li>prog_fav_sequence<br>
        beinhaltet die Kommandosequenz zum Programmieren der Harware-Favoritenposition</li><br>

		<a name="debug_mode [0:1]"></a>
    <li>debug_mode [0:1] <br>
        Im Mode 1 werden zus&auml;tzliche Readings zur Fehlerbehebung angelegt, in denen die Ausgabe aller Modulelemente ausgegeben werden. Kommandos werden NICHT physisch gesendet.</li><br>
		
		<a name="Info"></a>
    <li>Info<br>
        Die Attribute webcmd und devStateIcon werden beim Anlegen des Devices einmalig gesetzt und im auch im Betrieb an den jeweiligen Mode des Devices angepasst. Die Anpassung dieser Inhalte geschieht nur solange, bis diese durch den Nutzer ge&auml;ndert wurden. Danach erfolgt keine automatische Anpassung mehr.</li><br>

  </ul>
</ul>

=end html_DE
=cut
