#################################################################################
# 
# $Id$ 
#
# FHEM Modul for Viessman Vitotronic200  mit vcontrold-daemon
#
# Copyright (C) Andreas Loeffler
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
#
# This modul allows controlling a Viessmann heating system (Vitotronic and the like)
# using FHEM. It relies on the vcontrold daemon (see https://openv.wikispaces.com/). 
# vcontrold must run an a machine and 89_VCLIENT establishes a telnet connection 
# to read and write data. See more details in the commandref/below. 
#
################################################################
#
# Zum Aufbau des Commandfiles *.cfg: Er besteht aus Eintraegen der Form
#
#  getDevTemp WarmwasserTemp 					[zuerst das get-Kommando aus vcontrold, danach FHEM-Readingname]
#  getBrennerStarts Brennerstarts
#  getBrennerStarts BrennerstartsBisGestern daily [soll das Kommando nur einmal am Tag ausgefuehrt werden, muss das Wort daily am Ende stehen]
#  getTimerWWMo WarmwasserMo manually 			[bei manuellem Abruf muss das Wort manually folgen]
#  setDevTemp setBefehlName 21,22,23,24 		[zuerst das set-Kommando aus vcontrold, danach der Name 
#												des set-Befehls in FHEM und die moeglichen Werte, die
#												zu setzen sind]
# setTimerWWMo WW_1Mo_spaet 07:40-10:10|12:00-12:30|15:30-16:00|19:00-20:30
# setTimerWWMo WW_2Di_spaet 08:00-10:00|12:00-12:30|| [timer Befehle sind durch Zeitangaben darzustellen]
#
################################################################
#
#
# Version History
#
# 2019-01-28 version 0.2.11j: vcontrold-Neigung (Heizkurve) commands not rounded to full number anymore 
# 2019-01-28 version 0.2.11i: update starts now if device initiated (for example, via FHEM restart) 
# 2018-12-26 version 0.2.11h: warnings removed
# 2018-12-24 version 0.2.11g: minor bugfix, more comments with verbose 5
# 2018-12-08 version 0.2.11f: Integritaetscheck der Rueckgabewerte, Bugs entfernt, Rueckgabe Datum moeglich, offizielles FHEM-Modul
# 2018-09-14 version 0.2.10: Fehler, wenn vcontrold nicht erreichbar, behoben
# 2018-03-14 version 0.2.9: Fehler beim senden von mehreren set-Kommandos behoben
# 2017-11-08 version 0.2.8: Bei Fehlermeldungen erscheint Error im state-Reading zur Weiterverarbeitung (UpdateTimer wird ja ausgeschaltet)
# 2017-10-28 version 0.2.7: weiterer Fehler zeituebergabe fuer setTimer behoben (mehrere Befehle fuer genau ein vcontrold-set Kommando moeglich)
# 2017-10-26 version 0.2.6: Fehler zeituebergabe fuer setTimer behoben (8:00 statt 08:00)
# 2017-10-24 version 0.2.4/5: Fehler bei Umwandlung $arg fuer vcontrold behoben
# 2017-10-24 version 0.2.3: 'manually' instead of 'timer', timer format will be identified automatically
# 2017-10-21 version 0.2.2: 'daily' (once a day only) command and set command execution possible
# 2017-10-18 version: 0.2 CoolTux inspired non-blocking version
# 2017-10-16 first version: 0.1 andies 

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Blocking;
use Data::Dumper;

my $VCLIENT_version = "0.2.11j";
my $internal_update_interval  = 0.1; #internal update interval for Write (time between two different write_to_Viessmann commands)
my $daily_commands_last_day_with_execution = strftime('%d', localtime)-1; #last day when daily commands (commands with type 'daily' ) were executed; set to today

my @mode = ("WW","RED","NORM","H+WW","H+WW FS","ABSCHALT"); 	#states the Heater can be set to
my @command_queue = (); 		#queue of all commands to be executed by VCLIENT
my @reading_queue = ();			#similar queue for corresponding readings
my $last_cmd;					#last command to be executed by vcontrold
my $reading_in_progress = 0;

my %get_hash; #get commands and readings that were read from the config-file, 
			  #key=vcontrold-command, value=FHEM-reading (stores return from vcontrold-command)
my %get_daily_hash; #same as get_hash, except only for commands executed once a day
my %get_manually_hash; #same as get_hash, except only for commands executed manually 

my %set_hash; #set commands with values that should appear in FHEM-dropdown 
my %dropdown_hash; #contains the values for every set command

############################################################################
sub VCLIENT_Attr ($$$$);
sub VCLIENT_Close_Connection($);
sub VCLIENT_Define($$);
sub VCLIENT_Get($@);
sub VCLIENT_Initialize($);
sub VCLIENT_integrity_check($);
sub VCLIENT_Open_Connection($);
sub VCLIENT_ParseBuf_And_WriteReading($$);
sub VCLIENT_Read($);
sub VCLIENT_Read_Config($);
sub VCLIENT_Set($@);
sub VCLIENT_Set_New_Update_Interval($);
sub VCLIENT_Set_New_Write_Interval($);
sub VCLIENT_syntax_check_for_set_arg($);
sub VCLIENT_Timeout($);
sub VCLIENT_Undef($$);
sub VCLIENT_Update($);
sub VCLIENT_Update_Manually($);
sub VCLIENT_Write($);
############################################################################
#
# Zum Mechanismus. Update liest alle auszufuehrenden Commandos in einen array.
# Dann oeffnet Update die Telnet-Connection und ruft Write auf.
#
# Write liest den command-array. Ist er leer, wird Close_Connection aufgerufen. Ist er voll, wird das 
# naechste command abgerufen, aus dem array entfernt und zu Viessmann geschickt. Gleichzeitig 
# wird ein Timout gesetzt (das nach $timeout Sekunden die sub Timeout aufruft). Dann gibt es zwei Moeglichkeiten:
#
# 1. Moeglichkeit. Es wurde Read aufgerufen. Das geschieht (durch FHEM) nur dann, wenn ein Ergebnis empfangen wurde.
# Dies wird in das Reading geschrieben und der Timeout geloescht. Danach wird Write erneut aufgerufen.
#
# 2. Moeglichkeit. Es wurde Timeout aufgerufen. Dann wurde anscheinend kein Signal empfangen. Jetzt wird
# der Array geloescht und Connection_close aufgerufen.  
#
#                Close
#                  ^    ----> Timeout -> Close
#                  |  /
#  Update ->   Write ----> Read
#                  ^         |
#                  |         |
#                   ---------
#
# Um zu verhindern, dass sich verschiedene Leseanforderungen ueberschneiden (zB: getTempA wird aufgerufen, dann
# wird getTempWW angerufen und erst jetzt meldet sich Viessmann mit TempA - das Ergebnis wuerde dann in WW
# geschrieben und waere damit falsch!) gibt es ein Flag $reading_in_progress. Sobald ein Write aufgerufen wird,
# wird =1 gesetzt und es kann kein weiterer Write-Befehl an Viessmann gesendet werden. Nach einem Timeout oder einem
# erfolgreichen Read wird es =0 gesetzt, Write ist damit wieder moeglich.
#
############################################################################

############################################################################
# Attribute setzen, mit Syntax-check
############################################################################
sub VCLIENT_Attr ($$$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  Log3 $name, 5, "$name: VCLIENT Attr: $cmd $name ".$attrName?$attrName:''." $attrVal";

  #syntax check for attributs
  if ($cmd eq "set") {
	if ($attrName eq "timeout") {
		if (!looks_like_number($attrVal)) {
			Log3 $name, 1, "$name: Invalid number in timout ($attrVal), use only natural numbers!";
			return "Invalid timeout attribut value: $attrVal $@";
		} elsif ($attrVal <= 0){
			Log3 $name, 1, "$name: Timout ($attrVal) cannot be zero or below, choose positive number!";
			return "Negative or zero timeout attribut value not allowed: $attrVal $@";
		} else {
			Log3 $name, 5, "$name: Timeout set to $attrVal.";
			}
		}
		
	if ($attrName eq "prompt") {
		Log3 $name, 5, "$name: Prompt set to $attrVal";
		}

	if ($attrName eq "internal_update_interval") {
		Log3 $name, 5, "$name: Internal_Update_Interval set to $attrVal";
		} 
	}

  return undef;
}


############################################################################
# Verbindung schliessen
############################################################################
sub VCLIENT_Close_Connection($)
{
   my ($hash) = @_;
   
   my $name = $hash->{NAME};

   return if ( !$hash->{CD} );

   Log3 $name, 5,  "$name: Closing vcontrold connection";
   close($hash->{CD}) if ($hash->{CD});
   delete ($hash->{FD});
   delete ($hash->{CD});
   delete ($selectlist{$name});
   readingsSingleUpdate($hash, 'state', 'disconnected', 1);
   
   #set new update interval
   VCLIENT_Set_New_Update_Interval($hash);  
} 


############################################################################
# Geraet definieren, Befehlssyntax pruefen
############################################################################
sub VCLIENT_Define($$)
{
  	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	return "Usage: define <name> VCLIENT <host> <port> <config-filename> <interval>"  if($#args != 5);

	my ($name, $type, $host, $port, $filename, $interval) = @args;

	my $missingModulRemote;
	eval "use Net::Telnet;1" or $missingModulRemote .= "Net::Telnet ";
    if($missingModulRemote) {
      my $msg="ERROR: Perl modul ".$missingModulRemote." is missing on this system. Please install it before using this modul.";
      Log3 $name, 1, $msg;
      return $msg;
      }

	$hash->{IP} = $host if ($host);  #no format-check (host can be numbers, text etc.) 

	if ($port =~ /^\d+?$/) {
		$hash->{PORT} = $port 
	} else {
		return "VCLIENT: Port (usually 3002) does not seem to be a number, device $name not defined";
	}

	if (-f $filename) {
		$hash->{FILE} = $filename;  	
	} else {
		return "VCLIENT: Cannot find file $filename, device $name not defined";
	} 

	if (!looks_like_number($interval)) {
		return "VCLIENT: Interval must be a number, ".$interval." does not seem to be (zero would be possible!)";
	}	
	$hash->{INTERVAL} = $interval;
	
	VCLIENT_Read_Config($hash);
	
	if ($interval > 0) {
		VCLIENT_Set_New_Update_Interval($hash); 
	}

    $hash->{'.prompt'}  = '/vctrld>$/'; # this is the initial prompt 'vctrld>' after initializing the connection,
								# telnet->waitfor() and telnet->cmd() need the correct prompt. Is this really necessary?

	$modules{VCLIENT}{defptr}{$host} = $hash;
	readingsSingleUpdate($hash, 'state', 'Initialized', 1);
    Log3 $name, 5, $name.": VCLIENT device defined";	
	
    return undef;
}


############################################################################
# Angaben von Viesmann via Get abholen
############################################################################
sub VCLIENT_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $a[0];

  if(@a < 2) {
	my $msg = "@a: get needs at least one parameter, aborting";
	Log3 $name, 1, $name.": ".$msg;
    return $msg;
  }

  my $cmd= $a[1];

  Log3 $name, 5, "$name: execute get command @a";

  if($cmd eq "update") {
    VCLIENT_Update($hash);
	readingsSingleUpdate($hash, "state", 'Updating', 1);
    return undef;
  }

  if($cmd eq "update_manually") {
    VCLIENT_Update_Manually($hash);
	readingsSingleUpdate($hash, "state", 'Updating manually', 1);
    return undef;
  }

  return "Unknown argument $cmd, choose one of update:noArg update_manually:noArg";
}


############################################################################
# Initialisierung
############################################################################
sub VCLIENT_Initialize($)
{
  my ($hash) = @_;

  Log3 undef, 1, "VCLIENT (Version ".$VCLIENT_version.") initialized";

  $hash->{DefFn}    = "VCLIENT_Define";
  $hash->{UndefFn}  = "VCLIENT_Undef";
  $hash->{GetFn}    = "VCLIENT_Get";
  $hash->{SetFn}    = "VCLIENT_Set";
  $hash->{AttrFn}   = "VCLIENT_Attr";
  $hash->{ReadFn}   = "VCLIENT_Read";
  $hash->{WriteFn}  = "VCLIENT_Write";
  $hash->{AttrList} = "timeout prompt internal_update_interval ".$readingFnAttributes;
  
  foreach my $d(sort keys %{$modules{VCLIENT}{defprt}}) {
	  my $hash = $modules{VCLIENT}{defprt}{$d};
	  $hash->{VERSION} = $VCLIENT_version;
  }
  
  if ($hash->{INTERVAL}) {
  	VCLIENT_Set_New_Update_Interval($hash); 
  }
}


############################################################################
# Integritaet der Rueckgabe pruefen auf Wunsch von Phantom
# siehe https://forum.fhem.de/index.php/topic,78101.msg869373.html#msg869373 
############################################################################
sub VCLIENT_integrity_check($)
{
	my $value = shift;
	my $integrity = 1;
	#Temperaturen muessen unter 110 Grad Celsius sein (vorher testen ob value Zahl ist - vermeidet warnings bei 'Unkown buffer')
	if (($last_cmd =~ /(T|t)emp/) and ($value =~ /^\d+.\d*$/))
	{
		$integrity &&= ($value < 110);
	}
	#Status darf nur 0 oder 1 sein
	if (($last_cmd =~ /(S|s)tatus/) and ($value =~ /^\d$/))
	{
		$integrity &&= ($value =~ /(0|1)/);
	}
	# Unkown buffer format ist nicht korrekt
	$integrity &&= ($value !~ /Unkown buffer format/);

	return $integrity;
}


############################################################################
# Telnet-Verbindung oeffnen
############################################################################
sub VCLIENT_Open_Connection($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $host = $hash->{IP};
   my $port = $hash->{PORT};
   my $msg;
     
   my $timeout = AttrVal( $name, 'timeout', '1'); #default value is 1 second
   my $t_prompt = AttrVal($name,'prompt',$hash->{'.prompt'});
   my $telnet = new Net::Telnet ( Port => $port, Timeout=>$timeout, Errmode=>'return', Prompt=>'/'.$t_prompt.'/', Dump_Log => '/opt/fhem/log/vcontrold.log');
   
   if (!$telnet) {
      $msg = "ERROR: Cannot initiate Net::Telnet object";
      Log3 $name, 1,  $name.": ".$msg;
      return $msg;
   }

   Log3 $name, 5, "$name: Opening vcontrold connection to $host:$port";
   if (!$telnet->open($host)){
       $msg = "ERROR: Cannot open vcontrold connection, ".$telnet->errmsg.". Is vcontrold running?";
	   readingsSingleUpdate($hash, "state", 'Error', 1);
       Log3 $name, 1,  $name.": ".$msg;
	   return undef;
   }
   
   $hash->{FD} = $telnet->fileno(); #Thanks to CoolTux for providing me with this idea, more see forum
   $hash->{CD} = $telnet;
   $selectlist{$name} = $hash;
   
   readingsSingleUpdate($hash, "state", 'Initialized', 1);
   Log3 $name, 5, "$name: vcontrold opened";
   return undef;
}


############################################################################
# this sub parses the contents of buffer and returns a string that can be put into a reading
############################################################################
sub VCLIENT_ParseBuf_And_WriteReading($$){
    my ($hash, $buf) = @_;
    my $name = $hash->{NAME};
	
 	my $reading = shift @reading_queue; #Readingname, dorthin sollen Daten gespeichert werden
	my $value;                          #zu speichernder Wert

	#Ergebnis = Kommando war fehlerhaft
    	if ($buf eq "ERR: command unknown"){ 
   		$value = "ERROR, see logfile";
   		Log3 $name, 1, "$name ERROR: command  ".$last_cmd." from ".$hash->{FILE}." does not seem to be defined in vcontrol.xml";
   	} else {
		my @zeilen=split /\n/, $buf;
		# Anzahl uebergebener Zeilen
		my $zeilen = @zeilen; 
		
		# hier gibt es zwei Moeglichkeiten: Entweder enthaelt $buf nur eine Zeile, 
		# dann kommt das Ergebnis gleich am Anfang (danach steht die Masseinheit oder die Uhrzeit o.Ae.). 
		if ($zeilen == 1 ) {
			my @results = split /[ ]/, $zeilen[0]; # split around empty_space
			# ueblicherweise stehen hier numerische Angaben, ausser zB bei der Betriebsart
			if (looks_like_number($results[0])){
				#if ( $last_cmd =~ /(S|s)tatus/ || $last_cmd =~ /BetriebSpar/ || $last_cmd =~ /BetriebParty/ )
				# Wenn vcontrold-command "Temp" oder "Neigung" (Heizkurve!) enthaelt, Runden auf 1 , sonst Runden auf 0 (=Statuswert)
				if (($last_cmd !~ /(T|t)emp/) and ($last_cmd !~ /Neigung/))
				{
					$value = sprintf("%.0f", $results[0]); #rounding to integer, if status value
				} else {
					$value = sprintf("%.1f", $results[0]); #rounding to, for example, 16.6	
				}
			} else {
				$value = $zeilen[0]; #Buchstaben fuer Betriebsart u.Ae.	
			}
		} elsif ($zeilen == 4) {
			# Oder $buf enthaelt einen Timer, der dann vier Zeilen enthalten muss 
			foreach my $zeile (@zeilen)
			{
				# leere timer ignorieren
				if ($zeile !~ m/^\d:An:--     Aus:--$/)
				{
					# verbleibende Zeiten einlesen
					$zeile =~ s/^\d:An://; # Wort 'An' entfernen
					$zeile =~ s/  /-/;     # Zwischenraum durch Minus ersetzen
					$zeile =~ s/Aus://;    # Wort 'Aus' entfernen
					$value .= $zeile." | ";# addiere separation sign
				}
			}
			$value = substr($value, 0, -3);# loesche letztes separation sign | beim timer
		} else {
	   		# format der Ausgabe unbekannt
			$value = "$name: Unkown buffer format";
			Debug("$name: buf ".$buf);			
		}
		Log3 $name, 3,  $name.": Received ".$value." for ".$reading;
   	}
	if (($value eq "OK") or VCLIENT_integrity_check($value))
	{
		readingsSingleUpdate($hash, $reading, $value, 1);	
	}
    VCLIENT_Set_New_Write_Interval($hash);
}


############################################################################
# Diese sub wird automatisch aufgerufen, wenn Werte zum lesen anstehen 
# dabei muss vor allem der leere prompt vctrontrold> aussortiert werden
############################################################################
sub VCLIENT_Read($){
    my ($hash) = @_;
    my $name = $hash->{NAME};

	my $buf;
	my $line = sysread($hash->{CD}, $buf, 1024);

    if ( !defined($line) || !$line){
		$reading_in_progress = 0; #enforce finish reading
		Log3 $name, 5,  "$name: connection closed unexpectedly"; #kann hier eigentlich nicht passieren
		VCLIENT_Close_Connection($hash);
		return;
    }

	unless (defined $buf){
		Log3 $name, 5,  "$name: no data received"; #continue reading
		return;
	}

	#remove prompt (with and without newline)
	$buf =~ s/vctrld>[\r]?[\n]?//;
	
	if ($buf ne "") {
		#erst hier kommen echte Daten an, die ins Reading geschrieben werden sollen - nur diese parsen
		VCLIENT_ParseBuf_And_WriteReading($hash, $buf);
	}	
	$reading_in_progress = 0; #reading successfully finished
}


############################################################################
# Konfigurationsdatei einlesen
############################################################################

sub VCLIENT_Read_Config($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $filename = $hash->{FILE};
  my $no_lines = 0;
  
  Log3 $name, 5, "$name: opening cfg-command file $filename";
  open(CMDDATEI,"<$filename") || die "VCLIENT: problem opening $filename\n" ; #darf hier eigentlich nicht passieren
  
  %get_hash = (); 
  %set_hash = ();
  %dropdown_hash = ();
  %get_daily_hash = (); 
  %get_manually_hash = (); 
  
  while(<CMDDATEI>){
	    $no_lines++;
        my $zeile=trim($_);
        if ( length($zeile) > 0 && substr($zeile,0,1) ne "#")
        {
	       Log3 $name, 5, "$name: reading cfg-command line $zeile";
           my @cfgarray = split(" ",$zeile);
           foreach(@cfgarray) {
              $_ = trim($_);
           }    

	       my $vcontrold_command = "";
		   my $readingname = "";

		   if (scalar(@cfgarray) < 2){
 	        	Log3 $name, 1, $name.": every nonempty line in the cfg-command file (if it does not have a leading #) must at least contain two words. Line no. $no_lines does not and will be ignored"; 
		   } else {
		       $vcontrold_command = $cfgarray[0];
			   $readingname = $cfgarray[1];
		   }
		   
		   ########################################################
		   # hier werden die vcontrold-get-Kommandos ausgelesen und in einfache Hashs (drei "get_hash"s gibt es hier) geschrieben
		   # key ist das vcontrold-command, value ist das dazugehoerige FHEM-reading.
		   # Wird dann vcontrold-command ausgefuehrt, wird das Ergebnis in das FHEM-reading geschrieben 	   
		   # zu unterscheiden sind "einfache get" (Intervallbasiert abgefragt), "daily" (einmal am Tag) und "manually" (nur manuell) 
		   if (substr($vcontrold_command, 0, 3) eq "get"){
				if (scalar(@cfgarray) >= 3) {
					if ($cfgarray[2] eq "manually"){
						#timer command will receive several lines, must be handled differently			
						$get_manually_hash{$vcontrold_command}=$readingname; 
						Log3 $name, 5, $name.": manual get-command ".$vcontrold_command." with reading ".$readingname. " added";
					} elsif ($cfgarray[2] eq "daily"){
						#daily commands that will be executed only once a day			
						$get_daily_hash{$vcontrold_command}=$readingname; 
						Log3 $name, 5, $name.": daily get-command ".$vcontrold_command." with reading ".$readingname. " added";
					} else {
			 	        Log3 $name, 1, $name.": command type string ".$cfgarray[2]." in cfg-file ".$filename." not recognized. Must be either 'daily' or 'manually'. Command $vcontrold_command will be ignored."; 
					}
				} else {
					#get command will read a simple number (like 14 degree Celsius)
					$get_hash{$vcontrold_command}=$readingname; 
					Log3 $name, 5, $name.": get-command ".$vcontrold_command." with reading ".$readingname. " as '".$vcontrold_command."' added";
				}
			########################################################
	 		# jetzt kommen die vcontrold-set-Kommandos, mit denen die Heizung gesteuert werden kann,
			# hier gibt es zwei Arten, die sich stark unterscheiden:
			# einmal Befehle zum einstellen der Temperatur ("Temperatur-Befehle"), zum anderne Befehle zum Zeiteneinstellen ("timer"-Befehle) 
			# hier muessen jetzt im Gegensatz zu oben mehrere Groessen uebergeben werden:
			# 1) vcontrold-set-Befehl
			# 2) FHEM-set-Befehl
			# 3) entweder auswaehlbare Temperaturen (Temperatur-Befehle) oder Zeiten (timer-Befehle)
			#
		} elsif (substr($vcontrold_command, 0, 3) eq "set") {
				# typischer Eintrag in der cfg: setTempRaumRedSollM2 RaumsollWohnzReduz 22,21
				if (scalar(@cfgarray) < 3) {
		 	        Log3 $name, 1, $name.": command type string ".$vcontrold_command." in cfg-file ".$filename." must have three entries (<vcontrold-command> <FHEM-set command> <values>). Command $vcontrold_command will be ignored."; 
				} else {
					# Achtung: Abweichendes Handling fuer timer-Befehle noetig - dort werden spaeter die Argumente naemlich nicht
					# aus der Webmaske FHEMWEB geholt, sondern muessen bereits in der cfg-Datei stehen, bei allen anderen
					# vcontrold-set-Befehlen (also Temperatureinstellungen) wird das Argument, also die einzustellende Temperatur
					# erst in der Webmaske uebergeben.
			
					my $FHEM_set_command = $readingname;  #(nur der besseren Lesbarkeit wegen)
					my $options = $cfgarray[2];
					# Jetzt muss geprueft werden, ob der zweite Eintrag ein timer ist
					# und wenn das der Fall ist, muss dieser Eintrag bestimmte Regeln erfuellen 
					my $msg = VCLIENT_syntax_check_for_set_arg($options);

					# aufgrund der oben gewählten Variablennamen steht 
					#   vcontrold-Kommando in $vcontrold_command und der 
					#   FHEM-set-Befehl in $FHEM_set_command, 
					#   und es fehlen noch die dropdown-Einträge.
					#
					# Jetzt wird hierein HoA genommen (der "set_hash").
			 		# key ist jetzt immer abweichend von oben bei get der FHEM-set-Befehl, der vcontrold gesendet wird, 
					# value ist bei Temperaturbefehlen die auswaehlbaren Werte (wie 20,19,18) und 
					# bei Timerbefehlen die ausgewaehlten Zeiten (wie 08:10-10:00|12:00-14:00 usw). 
					#
					if ($msg eq ""){
						# %set_hash ist ein HashOfArray mit $FHEM_set_command => [$vcontrold_command,$options]
						$set_hash{$FHEM_set_command} = [$vcontrold_command, $options] ;
						Log3 $name, 5, $name.": set-command ".$vcontrold_command." with options '".$options."' as '".$FHEM_set_command."' added";
					} else {
			 	        Log3 $name, 1, $name.": command type string ".$vcontrold_command." in cfg-file ".$filename." does not contain valid format: '".$msg."' Entry will be ignored."; 
					}
				}
			} else {
	 	        Log3 $name, 1, $name.": command string ".$vcontrold_command." in cfg-file ".$filename." not recognized. Must be either 'getXXXX' or 'setXXX' with additional arg = 'timer' or 'daily'. This command string will be ignored."; 
			}
        }
  };

  close (CMDDATEI);
  Log3 $name, 5, "$name: cfg-command file '$filename' closed ($no_lines lines read)";
  return undef;
}



############################################################################
# Set-Befehl von FHEM ausfuehren
############################################################################
sub VCLIENT_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: try to execute set command @a";

  if(@a < 2) {
	my $msg = "@a: set needs at least one parameter";
    Log3 $name, 1, $name.": ".$msg;
    return  $msg;
  }

  #Hier steht jetzt der set-Befehl und, wenn es kein timer ist, das argument ($a[0] enthaelt $name)
  my $cmd = $a[1];
  
  my $arg = "";
  if (@a > 2){
  	$arg = $a[2];
  }

  #wenn nur die cfg-Datei neu geladen werden soll:
  if($cmd eq "reload_command_file") {
	if (($arg eq "") and ($hash->{FILE} ne "")){
		my $msg = $name.": filename empty, reloading the default file: ".$hash->{FILE};
		Log3 $name, 1, $msg;  	
		$arg = $hash->{FILE};
	} 	
	if (!(-f $arg)) {
		my $msg = $name.": file ".$arg." not found, aborting reloading";
		Log3 $name, 1, $msg;  	
		return $msg;
	} 
	$hash->{FILE}  = $arg;  	
	VCLIENT_Read_Config($hash);
	return undef;
  }

  #wenn kein reload, dann muss hier ein vcontrold-Kommando aus der cfg-Datei stehen:
  #set_hash ist so aufgebaut: $set_hash{$FHEM_set_command} = [$vcontrold_command, $options] ;  
  my $vcontrold = $set_hash{$cmd}[0];
  #zuerst schauen, ob $cmd in set_hash zu finden ist
  if($vcontrold) {
	  #Es gab zwei Arten von vcontrold-Kommandos. Einmal gab es ein Argument wie die
	  #Temperatur. Dort ist $arg nicht leer. Bei timern dagegen wurden aus der Webseite keine
	  #Argumente uebergeben, sondern die muessen aus dem Hash geholt werden. Das geschieht nun.
	  # Details zu den Hash siehe VCLIENT_Read_Config($)
	  if ($arg eq "") {
		  	$arg = $set_hash{$cmd}[1]; #Argument holen und fuer vcontrold umwandeln 
			while ($arg =~ m/0(\d:\d\d)/){	#Uhrzeiten vor 10:00 muessen die fuehrende Null entfernt bekommen, 
				$arg =~ s/0(\d:\d\d)/$1/; 	#(Fehler in vcontrold, habe ich durch Zufall entdeckt) 
			}
			$arg =~ s/[-\|]/ /g; 			# Zeitabstandszeichen - und senkrechten Strich | durch Leerzeichen ersetzen 
	  }
	  Log3 $name, 5, $name.": will try to send command ".$vcontrold." ".$arg." now";  	
	  #Debug ($name.": next command in queue ".$vcontrold." ".$arg);
  	  readingsSingleUpdate($hash, "last_set_command", "cmd in progress: ".$vcontrold." ".$arg." ...", 1);	

	  ##$reading_in_progress = 0; ### Ich glaube, das kann man ausblenden, denn es gibt eine Rueckmeldung naemlich ein OK ###########
	  push @command_queue, $vcontrold." ".$arg;
	  push @reading_queue, "last_set_command"; #Rueckgabe kommt in das reading 'last_set_command'

	  VCLIENT_Set_New_Write_Interval($hash);
	  return undef;
  }
  
  #Liste der set-Kommandos fuer das FHEM-Menue aufbauen
  #bei timern muss hier eine Anpassung vorgenommen werden,
  #damit die Argumente ausgeblendet werden (siehe oben)
  my $other_set_cmds = "";
  foreach $cmd (keys %set_hash){
		if ($cmd ne "?"){ #warum das hier noetig ist, verstehe ich nicht; sonst tauchen ? in der Set-liste auf
			$other_set_cmds .= $cmd.":";
		  	if ( $set_hash{$cmd}[1] !~ m/.*\|.*/ ){
				$other_set_cmds .= $set_hash{$cmd}[1]." "; #kein timer-Befehl, moegliche Argumente anhaengen	
	  	  	}  else {
				$other_set_cmds .= "noArg ";		#timer befehl, ohne Argumente in Set-Liste aufnehmen
	  	  	}
		}
	}

  return "Unknown argument $cmd, choose one of reload_command_file ".$other_set_cmds;
}


############################################################################
# Das update-Intervall wird hier gesetzt
############################################################################
sub VCLIENT_Set_New_Update_Interval($)
{
    my ($hash) = @_;

	RemoveInternalTimer($hash);
	my $interval = $hash->{INTERVAL} ;
	if ($interval>0){
	  InternalTimer(gettimeofday()+$interval, "VCLIENT_Update", $hash);
	}	
} 


############################################################################
# Das write-Intervall zum Schreiben von Befehlen an Viessmann wird hier gesetzt
############################################################################
sub VCLIENT_Set_New_Write_Interval($)
{
    my ($hash) = @_;
	my $name = $hash->{NAME} ;
	
	#remove timout
	RemoveInternalTimer($hash);

	#set up timer for writing next signal (fixed at $internal_update_interval seconds after opening connection)
	my $my_internal_timer = AttrVal( $name, 'internal_update_interval', $internal_update_interval);
	InternalTimer(gettimeofday()+ $my_internal_timer, "VCLIENT_Write", $hash); 
}


############################################################################
# Syntax check for arguments used in vcontrold-command. Currently only checks whether timer format correct
# is correct.
############################################################################
sub VCLIENT_syntax_check_for_set_arg($){
	my $timer_string = $_[0];
	my $msg ="";
	
	if ( $timer_string =~ m/.*\|.*/ )
	{
		#enthaelt offensichtlich timer, jetzt pruefen wir mal; sonst nicht
		my $anzahl = $timer_string =~ tr/\|//;
		if($anzahl != 3){
			$msg = "Timer must contain exactly three separation symbols |."
		} else {
			my @t = split /\|/, $timer_string;
			foreach my $zeiten (@t){
				if (($zeiten ne "") and ($zeiten !~ /\d\d:\d0-\d\d:\d0/)) {
						$msg = "Every timer must be either empty (use || in this case) or exactly (!) of format 'hh:m0-hh:m0'.";
				}
			}
		}
	}
	return $msg;
}


############################################################################
# If this sub has been called a timeout occured between send_signal and wait_for_result.
# Therefore, we close the connection and terminate reading from telnet.
############################################################################
sub VCLIENT_Timeout($)
{
    my ($hash) = @_;
   
    my $name = $hash->{NAME};
    my $host = $hash->{IP};
    my $port = $hash->{PORT};
    my $interval = $hash->{INTERVAL} ;
	
	Log3 $name, 5, "Timeout: Was not able to receive a signal from $host:$port. Deleting command queue.";
    @command_queue = (); 
	@reading_queue = (); 
	$reading_in_progress = 0;
    VCLIENT_Close_Connection($hash);
	
    #set new update interval
    VCLIENT_Set_New_Update_Interval($hash);  
}

############################################################################
# Geraet entfernen
############################################################################
sub VCLIENT_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: will be undefined now";

  %get_hash = {}; #empty get commands list
  @command_queue = ();  #empty cmd queue

  VCLIENT_Close_Connection($hash);
  RemoveInternalTimer($hash);
  
  BlockingKill( $hash->{helper}{READOUT_RUNNING_PID} )
      if exists $hash->{helper}{READOUT_RUNNING_PID}; 
  
  delete $modules{VCLIENT}{defptr}{$hash->{IP}};
  return undef;
}

############################################################################
# Readings werden upgedatet (daily oder/und alle)
############################################################################
sub VCLIENT_Update($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5,  "$name: will now update readings";
  
  #build command queue
  # Details zu den Hash siehe VCLIENT_Read_Config($)
  @command_queue = ();
  @reading_queue = ();  
  foreach my $vcontroldentry (keys %get_hash){
     	my $readingname = $get_hash{$vcontroldentry};	  	
			push @command_queue, $vcontroldentry;
		 	push @reading_queue, $readingname;
  	  	}   
  
  #check whether we have a new day, then the daily commands are added to the queue
  my $now_daily_commands_last_day_with_execution = strftime('%d', localtime);
  if ($now_daily_commands_last_day_with_execution ne $daily_commands_last_day_with_execution){
    	#we have a new day, change the flag and
		$daily_commands_last_day_with_execution = $now_daily_commands_last_day_with_execution;
    	#include daily commands now
	    foreach my $vcontroldentry (keys %get_daily_hash){
	       	my $readingname = $get_daily_hash{$vcontroldentry};	  	
	  			push @command_queue, $vcontroldentry;
	  		 	push @reading_queue, $readingname;
	    	  	}   
  }

  # start writing procedure by setting/updating the timer
  VCLIENT_Set_New_Write_Interval($hash);   
  return undef;
}

############################################################################
# manuelles updating der als manually gekennzeichneten readings
############################################################################
sub VCLIENT_Update_Manually($){
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5,  "$name: will now update manual readings";
  
    #build command queue
    # Details zu den Hash siehe VCLIENT_Read_Config($)
    @command_queue = (); 
	@reading_queue = (); 
    foreach my $vcontroldentry (keys %get_manually_hash){
       	my $readingname = $get_manually_hash{$vcontroldentry};	  	
  			push @command_queue, $vcontroldentry;
  		 	push @reading_queue, $readingname;
    	  	}   
  
    # start writing procedure by setting/updating the timer
    VCLIENT_Set_New_Write_Interval($hash);   
    return undef;
}


############################################################################
# This sub writes a single command to the Viessmann and sets new timeout etc 
############################################################################
sub VCLIENT_Write($)
{
	my ( $hash) = @_;
    my $name = $hash->{NAME};

    #open device if not already open
	unless ($hash->{CD}){
        VCLIENT_Open_Connection($hash);
    }

	#wenn noch keine Rueckgabe erfolgte, write nicht ausfuehren, sondern verzoegern (=erneut aufrufen)
    if ($reading_in_progress){
	    VCLIENT_Set_New_Write_Interval($hash);
    	return;
    }

    #read command queue, 
    $last_cmd = shift @command_queue;  #global variable, if this command was not recognized by vcontrold there must be an error message in VCLIENT_Read 

	if ($last_cmd){ 
		#send signal
		Log3 $name, 5,  "$name: Requesting ".$last_cmd." now";
		$last_cmd .= "\r\n";
		#flag because we need to stop sending until next timeout / successful reading, do this BEFORE syswrite
		$reading_in_progress = 1; 
		if ($hash->{CD}){
			syswrite($hash->{CD}, $last_cmd);
	    } else {
			Log3 $name, 1,  "$name: (ERROR) cannot reach hash, aborting syswrite";
	    }
				
	    #and set timer for timeout
	    RemoveInternalTimer($hash);
	    my $this_timeout = AttrVal( $name, 'timeout', '1'); #default value is 1 second
	    InternalTimer(gettimeofday()+$this_timeout, "VCLIENT_Timeout", $hash);
	} else {
		#last command already executed, set now timer for closing
	    RemoveInternalTimer($hash);
	    my $my_internal_timer = AttrVal( $name, 'internal_update_interval', $internal_update_interval);
	    InternalTimer(gettimeofday()+ $my_internal_timer, "VCLIENT_Close_Connection", $hash);
	}
}



# -----------------------------------------------------------------------------

1;

=pod
=item device
=item summary    controls Viessmann devices via daemon vcontrold
=item summary_DE kontrolliert Viessmann Heizungen ueber den Daemon vcontrold
=begin html

<!-- ================================ -->
<a name="VCLIENT"></a>
<h3>VCLIENT</h3>

<ul>This modul provides a GUI for Viessmann heatings. Whereas VCONTROL and <a href="https://forum.fhem.de/index.php?topic=67744.0">VCONTROL300</a> send and receive commands directly  VCLIENT is based on the external running daemon '<a href="https://github.com/openv/openv">vcontrold</a>. <br>

Viessmann is only controlled by vcontrold. This modul only connects to vcontrold and is more or less a  vcontrold client for FHEM. If a command does not do what it should this is caused by vcontrold not VCLIENT.<br><br>
 
    <b>Requirements</b> <br><br>
This module only works if on another (external) host <code>vcontrold</code> is running. Furthermore, an  Optolink cable (by Viessmann or DIY) must be connected to the heating and the host as well. Otherwise VCLIENT will not giv any results. For installation and running of <code>vcontrold</code> as well as Optolink cables see <a href="https://github.com/openv/openv">https://github.com/openv/openv</a><br>
(In this module the FHEM commands and vcontrold commands are called get-commands and set-commands. FHEM commands and vcontrold commands must be kept linguistically separate.)
 <br><br>


<b>Requirement</b> <br><br>
VCLIENT requires a configuration file. In this file there are entries line by line. Every line allocates a <code>vcontrold</code>-command to a reading name. 
  
If the command specified in the line is executed, the result obtained by vcontrold is written to the corresponding reading. A typical line in the configuration file looks like this:<br>
  <pre>
  ###### VCLIENT configuration file #########
  #This is a commend
  getTempA outsidetemperatur
  getTempBrennerstarts burnerstarts
  getTempBrennerstarts burnerstartsTillYesterday daily
  #up to now these were get commands, now we look at set commands
  getTimerWWMo HotWater_1Monday manually
  setTimerWWMo WW_1Mo_late 08:00-10:00|12:00-12:30|| 
  setTempWW HotWaterTemp 70,65,60,55
</pre><br>
  <b>Get commands:</b>The vcontrold command must be the first word in the line, no spaces allowed (e.g., getTempWW). The return of the vcontrold command &quot;getTempA&quot; is then written to the VCLIENT reading, in this case "outsidetemperature". Please use a separate line for each command. If a command is to be executed only once a day, the third word in the cfg file must be "daily". If a command is only to be executed manually, the third word in the cfg file must be "manually". The format of time commands (so-called timers) is recognized automatically.
<br>
<b>Set commands:</b>The vcontrold command must be the first word in the line, no spaces allowed (e.g., setTempWW). Then the name to be used in the FHEM set command is given, here HotWaterTemp (the complete FHEM command would be <code>set &lt;name&gt; HotWaterTemp 65</code>). Finally, the possible selections of a dropdown list are displayed in the line. It is indispensable that the values to be selected are comma-separated and written without spaces.

Timer commands make an exception here. Again, the vcontrold command (here setTimerWWMo) is executed first, followed by the command that triggers the FHEM entries (here <code>set &lt;name&gt; WW_1Mo_late</code>). In FHEM, however, the times of the day are not entered, but rather in the cfg file. There must be an even number of times, a maximum of eight. The times of the day must be separated by exactly <i>three</i> separators | from each other. The times, in turn, are to be written using the entries HH:MM-HH:MM. Only minutes that are multiples of 10 are permitted (something like 08:14 is not allowed); the later specifications must be to right (something like 08:00-07:00 is not allowed). The times as well as the set command must not contain any spaces. 
<br><br>
<b>Define</b>
  <ul>
    <br>
	
    <code>define &lt;name&gt; VCLIENT &lt;host&gt; &lt;port&gt; &lt;configfilename&gt; &lt;interval&gt;</code>
    <br><br>
    <code>&lt;host&gt;</code> is the host on which vcontrold is running. <br>
    <code>&lt;port&gt;</code> is the port for vcontrold (usually 3002). <br>
    <code>&lt;configfilename&gt;</code> is the configuration file, see above. <br>
    <code>&lt;interval&gt;</code> is the time difference in seconds for regular queries. The value 0 (only manual queries) is possible. <br><br>
</ul>

  <b>Set</b>
    <br><br>
   <ul>
     <b>reload_command_file</b>      
     <ul><code>set &lt;name&gt; reload_command_file &lt;configfilename&gt; 
      </code><br>
      Changes the name and/or path of the configuration file. The file must exist, otherwise an error message appears (specify full path).</ul>
   </ul>
   <ul>
     <b> &lt;vcontrold/FHEM command&gt;</b>      
     <ul><code>set &lt;name&gt; &lt;vcontrold/FHEM command&gt args
      </code><br>
The set command can also be used to execute vcontrold commands. These commands must be defined <b>before </b> in the cfg configuration file. If you look at the above example of a configuration file, a FHEM command in the form <code>set &lt;name&gt; HotWaterTemp 70</code> would send the command <code>setTempWW 70</code> internally to the heating: vcontrold would send the command <code>setTempWW 70</code> which would then set the hot water temperature to 70 degrees Celsius. An OK must appear in the reading last_set_cmd if the command was executed successfully. More complex time specifications for timers can be set analogously. Unfortunately, at the moment vcontrold returns an error message when setting timer values - although the values were transferred correctly.</ul>
   </ul>

    <b>Get</b>
    <br><br>
   <ul>
     <b>update</b>
     <ul><code>get &lt;name&gt; update 
      </code><br>
	  Executes the vcontrold commands specified in the configuration file and writes the results to the readings specified there. If these are not available, they are created.
     </ul>
     </ul>
   <ul>
     <b>update_manually</b>
     <ul><code>get &lt;name&gt; update_manually 
      </code><br>
      Executes the vcontrold commands specified in the configuration file for all manual entries and writes the results to the readings specified there. If these are not available, they are created.
     </ul>
     </ul>
<b>Attribute</b>
    <br><br>
   <ul>

     <b>timeout</b>    
     <ul><code>attr &lt;name&gt; &lt;timeout&gt; 1
	   </code><br>
	  Any access to a remote host is not blocking but must still include the possibility of an abort (if no response occurs). Timeout describes after how many seconds the query will be aborted unsuccessfully. 

	  In such a case, the entire query list is also terminated. 

	  Please note: A too short timeout is problematic, because then the module could not receive any feedback from the heating. The default setting (if no attribute is set) is 1 second.<br><br>
     </ul>
     </ul>
     <ul><b>internal_update_interval</b>
     <ul><code>attr &lt;name&gt; &lt;internal_update_interval&gt; 0.1<br>
      </code>This is an attribute that should only be used if, despite an intensive search, problems still occur when controlling the system. Normally it is not necessary to set this attribute.<br>Two different commands cannot be sent to the installation at the same time, because then with an answer it is not clear to which question the result refers. This is implemented internally by VCLIENT by using a small time span between two commands. This time span is now an exact multiple of $internal_update_interval. $internal_update_interval is internally set to 0.1 seconds; this should normally be sufficient. $internal_update_interval must be greater than zero. A larger value leads to a longer duration for all queries, a smaller value may shorten the total duration but could also lead to instabilities.<br>
  </ul>
  </ul>
</ul>
<!-- ================================ -->
=end html
=begin html_DE

<!-- ================================ -->
<a name="VCLIENT"></a>
<h3>VCLIENT</h3>

<ul>Dieses Modul stellt eine GUI für Viessmann-Heizungssteuerungen bereit. Während VCONTROL und <a href="https://forum.fhem.de/index.php?topic=67744.0">VCONTROL300</a> direkt Steuerungsbefehle versenden, basiert VCLIENT auf einem (extern) laufenden Daemon vcontrold. <br>

Die Viessmann-Heizung wird ausschließlich durch vcontrold kontrolliert. Dieses Modul verbindet sich nur mit vcontrold und stellt gewissermaßen einen vcontrold-Klienten für FHEM dar. Wenn ein Befehl nicht das tut, was er soll, liegt es an vcontrold, nicht aber an VCLIENT.<br><br>
 
    <b>Voraussetzungen</b> <br><br>
  Dieses Modul funktioniert nur, wenn auf einem (externen) Host <code>vcontrold</code>
installiert wurde und fehlerfrei läuft. Zudem muss natürlich ein Optolink-Kabel (von Viessmann oder im Eigenbau) an die Heizung angeschlossen und mit diesem Host verbunden sein. Anderenfalls wird VCLIENT  keine Ergebnisse liefern. Zur Installation und Inbetriebnahme von <code>vcontrold</code> sowie dem dazugehörigen Optolink-Kabel siehe die Webseite <a href="https://github.com/openv/openv">https://github.com/openv/openv</a><br>
(Es kommt bei diesem Modul erschwerend hinzu, dass sowohl bei FHEM als auch bei vcontrold die Kommandos get-Befehle und set-Befehle heißen. FHEM-Befehle und vcontrold-Befehle müssen sprachlich auseinander gehalten werden.)
 <br><br>

<b>Vorbereitungen</b> <br><br>
VCLIENT setzt eine Konfigurationsdatei voraus. In dieser Datei befinden sich zeilenweise Einträge. Jeder Eintrag ordnet einem <code>vcontrold</code> -Befehl einen Readingnamen zu. 
  
Wird der in der Zeile genannte  Befehl ausgeführte, so wird das durch vcontrold erhaltene Ergebnis in das entsprechende Reading geschrieben. Eine typische Zeile in der Konfigurationsdatei sieht wie folgt aus:<br>
  <pre>
  ###### VCLIENT-Konfigurationsdatei #########
  #Dies ist eine Kommentarzeile
  getTempA Aussentemperatur
  getTempBrennerstarts Brennerstarts
  getTempBrennerstarts BrennerstartsBisGestern daily
  #bisher standen get-Befehle da, nun folgen set-Befehle
  getTimerWWMo Warmwasser_1Montag manually
  setTimerWWMo WW_1Mo_spaet 08:00-10:00|12:00-12:30|| 
  setTempWW WarmwasserTemp 70,65,60,55
</pre><br>
  <b>Get-Befehle:</b>Zuerst muss der vcontrold-Befehl in der Zeile stehen, er muss das Wort get enthalten (zB getTempWW). Die Rückgabe des vcontrold-Befehls &quot;getTempA&quot; wird dann in das VCLIENT-Reading Aussentemperatur geschrieben. Bitte für jeden Befehl eine eigene Zeile verwenden. Soll ein Kommando nur einmal am Tag ausgeführt werden, muss als weiteres (drittes) Wort in der cfg-Datei "daily" stehen. Soll ein Kommando nur manuell ausgeführt werden, so muss als weiteres (drittes) Wort in der cfg-Datei "manually" stehen. Das Format von Zeitbefehlen (so genannte timer) wird automatisch erkannt. <br>
<b>Set-Befehle:</b>Zuerst muss der vcontrold-Befehl in der Zeile stehen, er muss das Wort set enthalten (zB setTempWW). Dann erfolgt der Name, der im FHEM-Set-Befehl autauchen soll, hier WarmwasserTemp (der komplette FHEM-Befehl hieße dann <code>set &lt;name&gt; WarmwasserTemp 65</code>). Zuletzt stehen die möglichen Auswahlen einer dropdown-Liste in der Zeile. Es ist unabdingbar, dass die auszuwählenden Werte kommagetrennt und ohne Leerzeichen geschrieben werden.

Timer-Befehle machen hier eine Ausnahme. Wieder erfolgt zuerst der vcontrold-Befehl (hier setTimerWWMo), danach folgt der Befehl, mit dem die Angaben in FHEM ausgelöst werden (hier wäre das <code>set &lt;name&gt; WW_1Mo_spaet</code>). In FHEM werden die Zeiten aber nicht eingegeben, dies geschieht vielmehr in der cfg-Datei. Dazu werden die Zeiten, die an die Anlage zu senden sind, in der Datei eingetragen. Es muss sich um eine gerade Anzahl von Zeitangaben, höchstens acht, handeln. Die Zeitangaben sind durch genau <i>drei</i> Trennzeichen | voneinander zu separieren. Die Zeiten wiederum sind durch Angaben HH:MM-HH:MM zu notieren. Dabei sind nur Minuten zulässig, die Vielfache von 10 sind; weiter müssen die Zeitangaben von links nach rechts wachsen und dürfen nicht fallen. Die Zeitangaben wie auch der Set-Befehl dürfen keine Leerzeichen enthalten. 
<br><br>
<b>Define</b>
  <ul>
    <br>
	
    <code>define &lt;name&gt; VCLIENT &lt;host&gt; &lt;port&gt; &lt;configfilename&gt; &lt;interval&gt;</code>
    <br><br>
    <code>&lt;host&gt;</code> ist der Host, auf dem vcontrold läuft. <br>
    <code>&lt;port&gt;</code> ist der Port, unter dem vcontrold ansprechbar ist (sehr oft 3002). <br>
    <code>&lt;configfilename&gt;</code> ist die vorbereitete Konfigurationsdatei, siehe hierzu oben. <br>
    <code>&lt;interval&gt;</code> ist die Zeitspanne in Sekunden, in denen regelmäßige Abfragen erfolgen sollen. Der Wert 0 (nur manuelle Abfragen) ist möglich. <br><br>
</ul>

  <b>Set</b>
    <br><br>
   <ul>
     <b>reload_command_file</b>      
     <ul><code>set &lt;name&gt; reload_command_file &lt;configfilename&gt; 
      </code><br>
      Ändert den Namen und/oder Pfad der Konfigurationsdatei. Die Datei muss existieren, sonst erfolgt eine Fehlermeldung (vollständigen Pfad angeben).</ul>
   </ul>
   <ul>
     <b> &lt;vcontrold/FHEM-Kommando&gt;</b>      
     <ul><code>set &lt;name&gt; &lt;vcontrold/FHEM-Kommando&gt args
      </code><br>
Es können mit dem set-Befehl auch vcontrold-Kommandos ausgeführt werden. Diese Kommandos müssen <b>vorab</b> in der cfg-Konfigurationsdatei definiert werden. Schaut man auf das obige Beispiel einer Konfigurationsdatei, so würde ein FHEM-Befehl der Form <code>set &lt;name&gt; WarmwasserTemp 70</code> intern an die Heizung bzw vcontrold den Befehl <code>setTempWW 70</code> absetzen, der dann die Warmwassertemperatur auf 70 Grad Celsius setzt. Im Reading last_set_cmd muss ein OK erscheinen, wenn der Befehl erfolgreich ausgeführt wurde. Analog können komplexere Zeitangaben für Timer gesetzt werden. Leider ist es momentan wohl so, dass beim Setzen von timer-Angaben vcontrold eine Fehlermeldung zurück gibt - obwohl die Angaben korrekt übertragen wurden.</ul>
   </ul>

    <b>Get</b>
    <br><br>
   <ul>
     <b>update</b>
     <ul><code>get &lt;name&gt; update 
      </code><br>
      Führt die in der Konfigurationsdatei genannten vcontrold-Befehle aus und schreibt die Ergebnisse in die dort angegebenen Readings. Sind diese nicht vorhanden, so werden sie angelegt.
     </ul>
     </ul>
   <ul>
     <b>update_manually</b>
     <ul><code>get &lt;name&gt; update_manually 
      </code><br>
      Führt die in der Konfigurationsdatei genannten vcontrold-Befehle für sämtliche manuellen Einträge aus und schreibt die Ergebnisse in die dort angegebenen Readings. Sind diese nicht vorhanden, so werden sie angelegt.
     </ul>
     </ul>
<b>Attribute</b>
    <br><br>
   <ul>

     <b>timeout</b>    
     <ul><code>attr &lt;name&gt; &lt;timeout&gt; 1
	   </code><br>
      Jeder	Zugriff auf einen entfernten Host ist nicht blockierend,  muss aber dennoch die Möglichkeit eines Abbruches beinhalten (falls partout keine Antwort erfolgt). Timeout beschreibt, nach wie viel Sekunden die Abfrage erfolglos abgebrochen werden soll. 
In einem solchen Fall wird auch die gesamte Abfrageliste beendet. 
Beachten Sie: Ein zu kurzer Timeout ist problematisch, weil dann uU noch keine Rückmeldung von der Heizung erfolgen konnte. Voreinstellung (wenn kein Attribut gesetzt) ist 1 Sekunde.<br><br>
     </ul>
     </ul>
     <ul><b>internal_update_interval</b>
     <ul><code>attr &lt;name&gt; &lt;internal_update_interval&gt; 0.1<br>
      </code>Hier handelt es sich um ein Attribut, das nur verwendet werden sollte, wenn trotz intensiver Suche immer noch Probleme bei der Ansteuerung der Anlage auftreten. Normalerweise ist es nicht nötig, dieses Attribut zu setzen.<br>Zwei verschiedene Kommandos können nicht gleichzeitig an die Anlage geschickt werden, weil dann bei einer Antwort nicht klar ist, auf welche Frage sich das Ergebnis bezieht. Dies wird intern so umgesetzt, indem VCLIENT darauf achtet, dass zwischen zwei Kommandos eine kleine Zeitspanne liegt. Diese Zeitspanne ist nun ein genaues Vielfaches von $internal_update_interval. $internal_update_interval ist intern auf 0.1 Sekunden eingestellt; dies sollte normalerweise genügen. $internal_update_interval muss größer als Null sein. Ein größerer Wert führt zu einer längeren Abfragedauer für alle Readings, ein kleinerer Wert verkürzt unter Umständen die gesamte Abfragedauer, könnte aber auch zu Instabilitäten führen.<br>

  </ul>
  </ul>
 </ul>

<!-- ================================ -->
=end html_DE
=cut
