#################################################################
# $Id$
#################################################################
# physisches Modul - Verbindung zur Hardware
#
# note / ToDo´s:
# 
# 
# 
# 
#################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use HttpUtils;					# um Daten via HTTP auszutauschen https://wiki.fhem.de/wiki/HttpUtils
use strict;				
use warnings;					# Warnings
use POSIX;
use LWP::Simple;
use Time::Local;

my $missingModul = "";
eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";

use Net::Ping;					# Ping Test Verbindung

sub xs1Bridge_Initialize($) {
	my ($hash) = @_;
	
	$hash->{WriteFn}    = "xs1Bridge_Write";
	$hash->{Clients}    = ":xs1Device:";
	$hash->{MatchList}  = { "1:xs1Device"   =>	'{\X..version.:.*' };			## https://regex101.com/ Testfunktion
	
	$hash->{DefFn}		=	"xs1Bridge_Define";
	$hash->{AttrFn}  	= 	"xs1Bridge_Attr";  
	$hash->{UndefFn}	=	"xs1Bridge_Undef";
	$hash->{AttrList}	=	"debug:0,1 ".
							"disable:0,1 ".
							"ignore:0,1 ".
							"interval:10,30,60,180,360 ";							
							##$readingFnAttributes;		## die Standardattribute von FHEM
							
	foreach my $d(sort keys %{$modules{xs1Bridge}{defptr}}) {
        my $hash = $modules{xs1Bridge}{defptr}{$d};
    }							
}

sub xs1Bridge_Define($$) {
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);
	my $name = $hash->{NAME};							## Der Definitionsname, mit dem das Gerät angelegt wurde.
	my $typ = $hash->{TYPE};							## Der Modulname, mit welchem die Definition angelegt wurde.
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	return "Usage: define <name> $name <ip>"  if(@arg != 3);
	return "Cannot define xs1Bridge device. Perl modul ${missingModul}is missing." if ( $missingModul );
	
	# Parameter Define
	my $xs1_ip = $arg[2];					## Zusatzparameter 1 bei Define - ggf. nur in Sub
	$hash->{xs1_ip} = $xs1_ip;

	if (&xs1Bridge_Ping == 1) {				## IP - Check
	$hash->{STATE} = "Initialized";			## Der Status des Modules nach Initialisierung.
	$hash->{TIME} = time();					## Zeitstempel, derzeit vom anlegen des Moduls
	$hash->{VERSION} = "1.05";				## Version
	$hash->{BRIDGE}	= 1;
	
	# Attribut gesetzt
	$attr{$name}{disable}	= "0";
	$attr{$name}{interval}	= "60";
	$attr{$name}{room}		= "xs1"	if( not defined( $attr{$name}{room} ) );
	
	$modules{xs1Bridge}{defptr}{BRIDGE} = $hash;
	
	InternalTimer(gettimeofday()+$attr{$name}{interval}, "xs1Bridge_GetUpDate", $hash);		## set Timer

	Log3 $name, 3, "$typ: Modul defined with xs1_ip: $xs1_ip";
	return undef;
   }
   else
   {
   return "ERROR - Host IP $xs1_ip is not reachable. Please check!";
   }
}

sub xs1Bridge_Attr(@) {
	my ($cmd,$name,$attrName,$attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};
	my $interval = 0;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
   
	Debug " $typ: xs1_Attr | Attributes $attrName = $attrValue" if($debug);

	if ($cmd eq "set") {											## Handling bei set .. attribute
		RemoveInternalTimer($hash);									## Timer löschen
		Debug " $typ: xs1_Attr | Cmd:$cmd | RemoveInternalTimer" if($debug);

		if ($attrName eq "interval") {								## Abfrage Attribute
			if (($attrValue !~ /^\d*$/) || ($attrValue < 5))		## Bildschirmausgabe - Hinweis Wert zu klein
			{
			return "$typ: Interval is too small. Please define new Interval | (at least: 5 seconds)";
			}
			my $interval = $attrValue;
		}
		elsif ($attrName eq "disable") {
			if ($attrValue eq "1") {								## Handling bei attribute disable 1
			readingsSingleUpdate($hash, "state", "deactive", 1);
			}
			elsif ($attrValue eq "0") {								## Handling bei attribute disable 0
			readingsSingleUpdate($hash, "state", "active", 1);
			}
		}
	}
	
	if ($cmd eq "del") {											## Handling bei del ... attribute
		if ($attrName eq "disable" && !defined $attrValue) {
		readingsSingleUpdate($hash, "state", "active", 1);
		Debug " $typ: xs1_Attr | Cmd:$cmd | $attrName=$attrValue" if($debug);
		}
		if ($attrName eq "interval") {
		RemoveInternalTimer($hash);
		Debug " $typ: xs1_Attr | Cmd:$cmd | $attrName" if($debug);
		}
		
	}

	if ($hash->{STATE} eq "active") {
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+$interval, "xs1Bridge_GetUpDate", $hash);
		Debug " $typ: xs1_Attr | RemoveInternalTimer + InternalTimer" if($debug);
		}
	return undef;
}

sub xs1Bridge_Delete($$) {                     
	my ( $hash, $name ) = @_;       
	RemoveInternalTimer($hash);
	return undef;
}

sub xs1Bridge_Ping() {			## Check before Define
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	my $xs1_ip = $hash->{xs1_ip};
	
	my $timeout = "3";
  	my $connection;
	my $p = Net::Ping->new;
  	my $isAlive = $p->ping($xs1_ip , $timeout);
  	$p->close;
  	if ($isAlive) {
		$connection = 1;
		} else {
		$connection = 0;
		}
return ($connection);
}

sub xs1Bridge_GetUpDate() {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	my $state = $hash->{STATE};
	my $def;
	
	#http://xxx.xxx.xxx.xxx/control?callback=cname&cmd=...
	#get_list_actuators        - list all actuators
	#get_list_sensors          - list all sensors
	#get_list_timers           - list all timers
	#get_config_info           - list all device info´s
	#get_protocol_info         - list protocol info´s
   
	my $cmd = "/control?callback=cname&cmd=";
	my @cmdtyp = ("get_list_actuators","get_list_sensors","get_config_info","get_list_timers","get_list_actuators");
	my @arrayname = ("actuator","sensor","info","timer","function");
	my @readingsname = ("Aktor","Sensor","","Timer","");
   
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $disable = AttrVal($name, "disable", 0);
	my $interval = AttrVal($name, "interval", 60);

	if (AttrVal($hash->{NAME},"disable",0) == 0) {
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+$interval, "xs1Bridge_GetUpDate", $hash);
		Debug "\n ------------- ERROR CHECK - START -------------" if($debug);
		Debug " $typ: xs1Bridge_GetUpDate | RemoveInternalTimer + InternalTimer" if($debug);
		#Log3 $name, 3, "$typ: xs1Bridge_GetUpDate | RemoveInternalTimer + InternalTimer";

		if ($state eq "Initialized") {
			readingsSingleUpdate($hash, "state", "active", 1);
		}

		### JSON Abfrage - Schleife
		for my $i (0..4) {
			my $adress = "http://".$hash->{xs1_ip}.$cmd.$cmdtyp[$i];
			Debug " $typ: xs1Bridge_GetUpDate | Adresse: $adress" if($debug);
     
			my $ua = LWP::UserAgent->new;									## CHECK JSON Adresse -> JSON-query, sonst FHEM shutdown
			my $resp = $ua->request(HTTP::Request->new(GET => $adress));
			if ($resp->code != "200") {										## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
				Log3 $name, 3, "$typ: xs1Bridge_GetUpDate | HTTP GET error code ".$resp->code." -> no JSON-query";
				if ($i == 0 || $i == 1 || $i == 2 || $i == 3) {last};		## ERROR JSON-query -> Abbruch schleife
			}
			
			my ($json) = get( $adress ) =~ /[^(]*[}]/g;					## cut cname( + ) am Ende von Ausgabe -> ARRAY Struktur
																		## ggf https://stackoverflow.com/questions/9493304/use-of-uninitialized-value-in-pattern-match-m testen

			my $json_utf8 = eval {encode_utf8( $json )};						## UTF-8 character Bearbeitung, da xs1 TempSensoren ERROR
			my $decoded = eval {decode_json( $json_utf8 )};

			if ($i <= 1 ) {               ### xs1 Aktoren / Sensoren
				my @array = @{ $decoded->{$arrayname[$i]} };
				foreach my $f ( @array ) {
					if ($f->{"type"} ne "disabled") {
						readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}) , $f->{"value"}, 1);
						Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"} if($debug);
						#Log3 $name, 3, $f->{"id"}." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"};
					}
				}
				
				my $xs1DeviceDev = "noDispatchDevice";					## defined xs1Device search to Dispatch
				my $key;
				foreach my $key (keys(%defs)) {							## https://forum.fhem.de/index.php/topic,19195.msg128890.html#msg128890
					if($defs{$key}{TYPE} eq "xs1Device") {				## old with Warning: #if(%defs->{$key}{TYPE} eq "xs1Device") {
						$xs1DeviceDev = $key;
						last;
					}
				}
			
				if ($xs1DeviceDev ne "noDispatchDevice")
				{
				Debug " $typ: xs1Device ($xs1DeviceDev) find, ready to dispatch" if($debug);
				Log3 $name, 5, "$typ: xs1Device ($xs1DeviceDev) find, ready to dispatch";
				Dispatch($hash,$json,undef);						## Dispatch an anderes Modul, NUR KOMPLETTES JSON !!!
				}

			} elsif ($i == 2) {           ### xs1 Info´s
				my $features;
				my $features_i=0;
				while (defined $decoded->{'info'}{'features'}->[$features_i]) {
				$features.= $decoded->{'info'}{'features'}->[$features_i]." ";
				$features_i++;
				}
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "xs1_devicename" , $decoded->{'info'}{'devicename'});
				readingsBulkUpdate($hash, "xs1_bootloader" , $decoded->{'info'}{'bootloader'});
				readingsBulkUpdate($hash, "xs1_hardware" , $decoded->{'info'}{'hardware'});
				readingsBulkUpdate($hash, "xs1_features" , $features);
				readingsBulkUpdate($hash, "xs1_firmware" , $decoded->{'info'}{'firmware'});
				readingsBulkUpdate($hash, "xs1_mac" , $decoded->{'info'}{'mac'});
				readingsEndUpdate($hash, 1);
            
				Debug " $typ: xs1_devicename: ".$decoded->{'info'}{'devicename'} if($debug);
				Debug " $typ: xs1_bootloader: ".$decoded->{'info'}{'bootloader'} if($debug);
				Debug " $typ: xs1_hardware: ".$decoded->{'info'}{'hardware'} if($debug);
				Debug " $typ: xs1_features: ".$features if($debug);
				Debug " $typ: xs1_firmware: ".$decoded->{'info'}{'firmware'} if($debug);
				Debug " $typ: xs1_mac: ".$decoded->{'info'}{'mac'} if($debug);
            
			} elsif ($i == 3) {				### xs1 Timers
				my @array = @{ $decoded->{$arrayname[$i]} };
				foreach my $f ( @array ) {
					if ($f->{"type"} ne "disabled") {
						readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}) , FmtDateTime($f->{"next"}), 1);
						Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." | ".$f->{"name"}." | ".$f->{"type"}." | ". $f->{"next"} if($debug);
					}
				}
			} elsif ($i == 4) {				### xs1 Aktoren / Funktion != disable
				my @array2 = @{ $decoded->{$arrayname[0]} };
				foreach my $f2 ( @array2 ) {
            
					if ($f2->{"type"} ne "disabled") {           ## Funktion != actuator -> type disable
						my @array = @{ $decoded->{'actuator'}->[($f2->{"id"})-1]->{$arrayname[$i]} };
						my $i2 = 0;                               ## Funktionscounter

						foreach my $f3 ( @array ) {
							$i2 = $i2+1;
							if ($f3->{"type"} ne "disabled") {  ## Funktion != function -> type disable
								Debug " $typ: ".$readingsname[0]."_".sprintf("%02d", $f2->{"id"})." | ".$f2->{"type"}." | ".$arrayname[$i]."_".$i2." | ".$f3->{"type"} if($debug);
								#readingsSingleUpdate($hash, $readingsname[0]."_".sprintf("%02d", $f2->{"id"})."_".$arrayname[$i]."_".$i2 , $f3->{"type"} , 1);
							}
						}
					}
				}     
			}
		 
			if ($i < 4) {
				Debug "\n ------------- ERROR CHECK - SUB -------------" if($debug);
			}
			### Schleifen Ende ###
		}
      	
		Debug "\n ------------- ERROR CHECK - ALL END -------------\n\n " if($debug);
	}
}

sub xs1Bridge_Write($)				## Zustellen von Daten via IOWrite() vom logischen zum physischen Modul 
{
	my ($hash, $Aktor_ID, $cmd) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
   
	Log3 $name, 3, "$typ: xs1Bridge_Write | Aktor_ID=$Aktor_ID, cmd=$cmd";
}

sub xs1Bridge_Undef($$)    
{                     
	my ( $hash, $name) = @_;
	my $typ = $hash->{TYPE};
	
	RemoveInternalTimer($hash);
	Log3 $name, 3, "$typ: Device with Name: $name delete";
	return undef;                  
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item summary    Connection of the device xs1 from EZControl
=item summary_DE Anbindung des Gerates xs1 der Firma EZControl
=begin html

<a name="xs1Bridge"></a>
<h3>xs1Bridge</h3>
<ul>
	With this module you can read out the device xs1 from EZcontrol. There will be actors | Sensors | Timer | Information read from xs1 and written in readings. With each read only readings are created or updated, which are also defined and active in xs1. Actor | Sensor or timer definitions which are deactivated in xs1 are NOT read.
	<br><br>

	The module was developed based on the firmware version v4-Beta of the xs1. There may be errors due to different adjustments within the manufacturer's firmware.<br><br>

	<a name="xs1Bridge_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Bridge &lt;IP&gt; </code>
		<br><br>

		The module can not create without the IP of the xs1. If the IP can not be reached during module definition, the Define process is aborted.
			<ul>
			<li><code>&lt;IP&gt;</code> is IP address in the local network.</li>
			</ul><br>
		example:
		<ul>
		define EZcontrol_xs1 xs1Bridge 192.168.1.45
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul>N/A</ul><br>
	<b>Get</b><br>
	<ul>N/A</ul><br>
	<a name="xs1_attr"></a>
	<b>Attributes</b>
	<ul>
		<li>debug (0,1)<br>
		This brings the module into a very detailed debug output in the logfile. Program parts can be checked and errors checked.<br>
		(Default, debug 0)
		</li><br>
		<li>disable (0,1)<br>
		This function deactivates the interval. With disable 1 no readings are updated.<br>
		(Default, disable 0)
		</li><br>
		<li>interval (10,30,60,180,360)<br>
		This is the interval in seconds at which readings are read from xs1<br>
		(Default, interval 60)
		</li><br>
	</ul>
</ul>
=end html
=begin html_DE

<a name="xs1Bridge"></a>
<h3>xs1Bridge</h3>
<ul>
	Mit diesem Modul können Sie das Gerät xs1 der Firma <a href="http://www.ezcontrol.de/">EZcontrol</a> auslesen. Das Modul ruft die Daten des xs1 via der Kommunikationsschnittstelle ab. Mit einem HTTP GET Requests erhält man die Antworten in Textform welche im Datenformat JSON (JavaScript Object Notation) ausgegeben werden. 
	Es werden Aktoren | Sensoren | Timer | Informationen vom xs1 ausgelesen und in Readings geschrieben. Bei jedem Auslesen werden nur Readings angelegt bzw. aktualisiert, welche auch im xs1 definiert und aktiv sind. Aktor | Sensor bzw. Timer Definitionen welche deaktiviert sind im xs1, werden NICHT ausgelesen.
	<br><br>

	Das Modul wurde entwickelt basierend auf dem Firmwarestand v4-Beta des xs1. Es kann aufgrund von unterschiedlichen Anpassungen innerhalb der Firmware des Herstellers zu Fehlern kommen.<br><br>

	<a name="xs1Bridge_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;name&gt; xs1Bridge &lt;IP&gt; </code>
		<br><br>

		Ein anlegen des Modules ohne Angabe der IP vom xs1 ist nicht möglich. Sollte die IP bei der Moduldefinierung nicht erreichbar sein, so bricht der Define Vorgang ab.
			<ul>
			<li><code>&lt;IP&gt;</code> ist IP-Adresse im lokalen Netzwerk.</li>
			</ul><br>
		Beispiel:
		<ul>
		define EZcontrol_xs1 xs1Bridge 192.168.1.45
		</ul>	
		</ul><br>
	<b>Set</b>
	<ul>N/A</ul><br>
	<b>Get</b><br>
	<ul>N/A</ul><br>
	<a name="xs1_attr"></a>
	<b>Attribute</b>
	<ul>
		<li>debug (0,1)<br>
		Dies bringt das Modul in eine sehr ausf&uuml;hrliche Debug-Ausgabe im Logfile. Somit lassen sich Programmteile kontrollieren und Fehler &uuml;berpr&uuml;fen.<br>
		(Default, debug 0)
		</li><br>
		<li>disable (0,1)<br>
		Diese Funktion deaktiviert den Interval. Mit <code>disable 1</code> werden keine Readings aktualisiert.<br>
		(Default, disable 0)
		</li><br>
		<li>interval (10,30,60,180,360)<br>
		Das ist der Intervall in Sekunden, in dem die Readings neu gelesen werden vom xs1.<br>
		(Default, interval 60)
		</li><br>
	</ul>
</ul>
=end html_DE
=cut
