#################################################################
# $Id$
#################################################################
# physisches Modul - Verbindung zur Hardware
#
# note / ToDo´s / Bugs:
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

my $missingModul	= "";
my $xs1_security 	= 0;		# disable Funktion sobald 10x keine Verbindung (Schutzabschaltung)

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";

use Net::Ping;					# Ping Test Verbindung

#$| = 1;		#Puffern abschalten, Hilfreich für PEARL WARNINGS Search

sub xs1Bridge_Initialize($) {
	my ($hash) = @_;
	
	$hash->{WriteFn}    = "xs1Bridge_Write";
	$hash->{Clients}    = ":xs1Dev:";
	$hash->{MatchList}  = { "1:xs1Dev"   =>	'[x][s][1][D][e][v][#][A][k][t][o][r]#[0-6][0-9].*|[x][s][1][D][e][v][#][S][e][n][s][o][r]#[0-6][0-9].*' };	## https://regex101.com/ Testfunktion
	
	$hash->{DefFn}		=	"xs1Bridge_Define";
	$hash->{AttrFn}  	= 	"xs1Bridge_Attr";  
	$hash->{NotifyFn}   =	"xs1Bridge_Notify";
	$hash->{UndefFn}	=	"xs1Bridge_Undef";
	$hash->{AttrList}	=	"debug:0,1 ".
							"disable:0,1 ".
							"ignore:0,1 ".
							"interval:30,60,180,360 ".
							"update_only_difference:0,1 ".
							"view_Device_name:0,1 ".
							"view_Device_function:0,1 ";
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
	my $viewDeviceName = AttrVal($hash->{NAME},"view_Device_name",0);
	my $viewDeviceFunction = AttrVal($hash->{NAME},"view_Device_function",0);
	my $update_only_difference = AttrVal($hash->{NAME},"update_only_difference",0);
	
	return "Usage: define <name> $name <ip>"  if(@arg != 3);
	return "Cannot define xs1Bridge device. Perl modul ${missingModul}is missing." if ( $missingModul );
	
	# Parameter Define
	my $xs1_ip = $arg[2];					## Zusatzparameter 1 bei Define - ggf. nur in Sub
	$hash->{xs1_ip} = $xs1_ip;

	if (&xs1Bridge_Ping == 1) {				## IP - Check
	$hash->{STATE} = "Initialized";			## Der Status des Modules nach Initialisierung.
	$hash->{TIME} = time();					## Zeitstempel, derzeit vom anlegen des Moduls
	$hash->{VERSION} = "1.11";				## Version
	$hash->{BRIDGE}	= 1;
	
	# Attribut gesetzt
	$attr{$name}{disable}	= "0";
	$attr{$name}{interval}	= "60";
	$attr{$name}{room}		= "xs1"	if( not defined( $attr{$name}{room} ) );
	
	$modules{xs1Bridge}{defptr}{BRIDGE} = $hash;
	
	InternalTimer(gettimeofday()+$attr{$name}{interval}, "xs1Bridge_GetUpDate", $hash);		## set Timer

	Log3 $name, 3, "$typ: Modul defined with xs1_ip: $xs1_ip";
	
	fhem("define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log ".$arg[0]);			## Logfil define
	fhem("attr FileLog_xs1Bridge room xs1");												## Logfile in xs1 room
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
	my $viewDeviceName = AttrVal($hash->{NAME},"view_Device_name",0);
	my $viewDeviceFunction = AttrVal($hash->{NAME},"view_Device_function",0);
	my $update_only_difference = AttrVal($hash->{NAME},"update_only_difference",0);
	
	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
   
	if ($cmd eq "set") {											## Handling bei set .. attribute
		RemoveInternalTimer($hash);									## Timer löschen
		Debug " $typ: Attr | Cmd:$cmd | RemoveInternalTimer" if($debug);
		if ($attrName eq "interval") {								## Abfrage Attribute
			if (($attrValue !~ /^\d*$/) || ($attrValue < 10))		## Bildschirmausgabe - Hinweis Wert zu klein
			{
			return "$typ: Interval is too small. Please define new Interval | (at least: 10 seconds)";
			}
			my $interval = $attrValue;
		}
		elsif ($attrName eq "disable") {
			if ($attrValue eq "1") {								## Handling bei attribute disable 1
			readingsSingleUpdate($hash, "state", "deactive", 1);
			}
			elsif ($attrValue eq "0") {								## Handling bei attribute disable 0
			$xs1_security = 0;
			readingsSingleUpdate($hash, "state", "active", 1);
			}
		}elsif ($attrName eq "view_Device_function") {
			if ($attrValue eq "1") {								## Handling bei attribute disable 1
			Log3 $name, 3, "$typ: Attribut view_Device_function $cmd to $attrValue";
			}
			elsif ($attrValue eq "0") {								## Handling bei attribute disable 0
			Log3 $name, 3, "$typ: Attribut view_Device_function $cmd to $attrValue";
			}
		}elsif ($attrName eq "view_Device_name") {
			if ($attrValue eq "1") {								## Handling bei attribute disable 1
			Log3 $name, 3, "$typ: Attribut view_Device_name $cmd to $attrValue";
			}
			elsif ($attrValue eq "0") {								## Handling bei attribute disable 0
				Log3 $name, 3, "$typ: Attribut view_Device_name $cmd to $attrValue";
				for my $i (0..64) {
				delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
				delete $hash->{READINGS}{"Sensor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
				}
			}
		}elsif ($attrName eq "update_only_difference") {
			if ($attrValue eq "1") {								## Handling bei attribute disable 1
			Log3 $name, 3, "$typ: Attribut update_only_difference $cmd to $attrValue";
			}
			elsif ($attrValue eq "0") {								## Handling bei attribute disable 0
				Log3 $name, 3, "$typ: Attribut update_only_difference $cmd to $attrValue";
				for my $i (0..64) {
				delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
				}
			}
		}
	}
	
	if ($cmd eq "del") {											## Handling bei del ... attribute
		if ($attrName eq "disable" && !defined $attrValue) {
		readingsSingleUpdate($hash, "state", "active", 1);
		Debug " $typ: Attr | Cmd:$cmd | $attrName=$attrValue" if($debug);
		}
		elsif ($attrName eq "interval") {
		RemoveInternalTimer($hash);
		Debug " $typ: Attr | Cmd:$cmd | $attrName" if($debug);
		}
		elsif ($attrName eq "view_Device_function") {
			Log3 $name, 3, "$typ: Attribut view_Device_function delete";
			for my $i (0..64) {
				for my $i2 (1..4) {
					delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_function_".$i2} if($hash->{READINGS});
				}
			}
		}
		elsif ($attrName eq "view_Device_name") {
			Log3 $name, 3, "$typ: Attribut view_Device_name delete";
			for my $i (0..64) {
				delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
				delete $hash->{READINGS}{"Sensor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
			}
		}
		elsif ($attrName eq "update_only_difference") {
			Log3 $name, 3, "$typ: Attribut update_only_difference delete";
		}
		
	}

	if ($hash->{STATE} eq "active") {
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+$interval, "xs1Bridge_GetUpDate", $hash);
		Debug " $typ: Attr | RemoveInternalTimer + InternalTimer" if($debug);
		}
	return undef;
}

sub xs1Bridge_Delete($$) {                     
	my ( $hash, $name ) = @_;       
	RemoveInternalTimer($hash);
	return undef;
}

sub xs1Bridge_Ping() {				## Check IP before Define
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
	my $xs1_uptimeStart = $hash->{helper}{xs1_uptimeStart};
	my $xs1_uptimeOld = $hash->{helper}{xs1_uptimeOld};
	my $xs1_uptimeNew = $hash->{helper}{xs1_uptimeNew};
	my $def;
	
	#http://x.x.x.x/control?callback=cname&cmd=...
	#get_list_actuators        - list all actuators			i0
	#get_list_sensors          - list all sensors			i1
	#get_list_timers           - list all timers			i3
	#get_config_info           - list all device info´s		i2
	#get_protocol_info         - list protocol info´s
   
	my $cmd = "/control?callback=cname&cmd=";
	my @cmdtyp = ("get_list_actuators","get_list_sensors","get_config_info","get_list_timers","get_list_actuators");
	my @arrayname = ("actuator","sensor","info","timer","function");
	my @readingsname = ("Aktor","Sensor","","Timer","");
   
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $disable = AttrVal($name, "disable", 0);
	my $interval = AttrVal($name, "interval", 60);
	my $viewDeviceName = AttrVal($hash->{NAME},"view_Device_name",0);
	my $viewDeviceFunction = AttrVal($hash->{NAME},"view_Device_function",0);
	my $update_only_difference = AttrVal($hash->{NAME},"update_only_difference",0);

	if (AttrVal($hash->{NAME},"disable",0) == 0 && $xs1_security <= 10) {
		RemoveInternalTimer($hash);									## Timer löschen
		InternalTimer(gettimeofday()+$interval, "xs1Bridge_GetUpDate", $hash);
		Debug "\n ------------- ERROR CHECK - START -------------" if($debug);
		Debug " $typ: GetUpDate | RemoveInternalTimer + InternalTimer" if($debug);
		#Log3 $name, 3, "$typ: xs1Bridge_GetUpDate | RemoveInternalTimer + InternalTimer";

		if ($state eq "Initialized") {
			readingsSingleUpdate($hash, "state", "active", 1);
		}

		my $xs1Dev_check = "ERROR";

		#if($modules{xs1Dev} && $modules{xs1Dev}{LOADED}) {		## Check Modul vorhanden + geladen
		if($modules{xs1Dev}) {									## Check Modul vorhanden
			$xs1Dev_check = "ok";
			Debug " $typ: GetUpDate | Modul xs1Dev_check = $xs1Dev_check" if($debug);
		} else {
			Debug " $typ: GetUpDate ERROR | Modul xs1Dev not existent! Please check it to be available!" if($debug);
			#Log3 $name, 3, "$typ: GetUpDate | xs1Dev_check = $xs1Dev_check";
		}

		### JSON Abfrage - Schleife
		for my $i (0..3) {
			my $adress = "http://".$hash->{xs1_ip}.$cmd.$cmdtyp[$i];
			Debug " $typ: GetUpDate | Adresse: $adress" if($debug);
     
			my $ua = LWP::UserAgent->new;									## CHECK JSON Adresse -> JSON-query, sonst FHEM shutdown
			my $resp = $ua->request(HTTP::Request->new(GET => $adress));
			Debug " $typ: GetUpDate | Adresse HTTP request Code: ".$resp->code if($debug);
			if ($resp->code != "200") {										## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
				Log3 $name, 3, "$typ: GetUpDate | cmdtyp=".$cmdtyp[$i]." - HTTP GET error code ".$resp->code." -> no Data";
				$xs1_security++;
				last;		## ERROR JSON-query -> Abbruch schleife
			}
			
			my $json;
			my $json_utf8;
			my $decoded;
			
			if (defined($adress)) {
				($json) = get( $adress ) =~ /[^(]*[}]/g;		## cut cname( + ) am Ende von Ausgabe -> ARRAY Struktur als Antwort vom xs1
				$json_utf8 = eval {encode_utf8( $json )};		## UTF-8 character Bearbeitung, da xs1 TempSensoren ERROR
				$decoded = eval {decode_json( $json_utf8 )};	## auswertbares ARAAY
			} else {
				Log3 $name, 3, "$typ: Adresse:$adress undefined";
				last;
			}
			
			if ($i <= 1 ) {     ### xs1 Aktoren / Sensoren
				if ($resp->code != "200") {										## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
					Log3 $name, 3, "$typ: GetUpDate | cmdtyp=".$cmdtyp[$i]." - HTTP GET error code ".$resp->code." -> no Data";
					last;		## ERROR JSON-query -> Abbruch schleife
				}
				
				my $data;
				my @array;
				if (defined $decoded->{$arrayname[$i]}) {
					@array = @{ $decoded->{$arrayname[$i]} };
				} else {
					Log3 $name, 3, "$typ: GetUpDate | ARRAY-ERROR xs1 -> no Data in loop $i";
					last;
				}
				
				foreach my $f ( @array ) {
					if ($f->{"type"} ne "disabled") {
						my $xs1Dev = "xs1Dev";
						
						### Aktoren spezifisch
						my $xs1_function1 = "-";
						my $xs1_function2 = "-";
						my $xs1_function3 = "-";
						my $xs1_function4 = "-";

						if ($i == 0) {
							### xs1 Aktoren nur update bei differenten Wert
							if ($update_only_difference == 1) {
								my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}), "unknown");	## Readings Wert
								my $newState = sprintf("%.1f" , $f->{"value"});														## ARRAY Wert xs1 aktuell
								
								Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." oldState=$oldState newState=$newState" if($debug);
									
								if ($oldState ne $newState) {
									readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}) , $newState, 1);
								}
							}
							
							### xs1 Aktoren / Funktion != disable
							my @array2 = @{ $decoded->{'actuator'}->[($f->{"id"})-1]->{$arrayname[4]} };
							my $i2 = 0;							## Funktionscounter

							foreach my $f2 ( @array2 ) {
								$i2 = $i2+1;

								### xs1 Option - Ansicht Funktionsname
								if ($viewDeviceFunction == 1) {
									my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $f->{"id"})."_".$arrayname[4]."_".$i2, "unknown");		## Readings Wert
									my $newState = $f2->{'type'};		## ARRAY Wert xs1 aktuell

									if ($f2->{"type"} ne "disabled") {  ## Funktion != function -> type disable
										if ($oldState ne $newState) {
											readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"})."_".$arrayname[4]."_".$i2 , $f2->{"type"} , 0);
										}
									}
								} else {
									if ($f2->{"type"} ne "disabled") {  ## Funktion != function -> type disable
									
										if ($i2 == 1) {
										$xs1_function1 = $f2->{"type"};
										}elsif ($i2 == 2) {
										$xs1_function2 = $f2->{"type"};
										}elsif ($i2 == 3) {
										$xs1_function3 = $f2->{"type"};
										}elsif ($i2 == 4) {
										$xs1_function4 = $f2->{"type"};
										}
									}
								}
							}
						}
						
						### Value der Aktoren | Sensoren
						if ($i == 1 || $i == 0 && $update_only_difference == 0) {		# Aktoren | Sensoren im intervall - Format 0.0 bzw. 37.0 wie aus xs1
							readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}) , sprintf("%.1f" , $f->{"value"}), 1);
							$data = $xs1Dev."#".$readingsname[$i]."#".sprintf("%02d", $f->{"id"})."#".$f->{"type"}."#".sprintf("%.1f" , $f->{"value"})."#"."$xs1_function1"."#"."$xs1_function2"."#"."$xs1_function3"."#"."$xs1_function4"."#".$f->{"name"};
						} elsif ($i == 0 && $update_only_difference == 1){				# Aktoren | nur bei DIFF - Format 0.0 bzw. 37.0 wie aus xs1
							$data = $xs1Dev."#".$readingsname[$i]."#".sprintf("%02d", $f->{"id"})."#".$f->{"type"}."#".sprintf("%.1f" , $f->{"value"})."#"."$xs1_function1"."#"."$xs1_function2"."#"."$xs1_function3"."#"."$xs1_function4"."#".$f->{"name"};
						}
						
						### Ausgaben je Typ unterschiedlich !!!
						Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"}." | "."F1 $xs1_function1 | F2 $xs1_function2 | F3 $xs1_function3 | F4 $xs1_function4" if($debug == 1 && $i == 0);
						Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"} if($debug == 1 && $i != 0);

						### Namen der Aktoren | Sensoren
						if ($viewDeviceName == 1) {
							readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"})."_name" , $f->{"name"} , 0);
						}
							
						### Dispatch an xs1Device Modul						
						if ($xs1Dev_check eq "ok") {
							Debug " $typ: GetUpDate | Dispatch -> $data" if($debug);
							Dispatch($hash,$data,undef) if($data);
						}
					}
				}
			} elsif ($i == 2) {     ### xs1 Info´s nur bei uptime Änderung
				if ($resp->code != "200") {		## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
					Log3 $name, 3, "$typ: GetUpDate | cmdtyp=".$cmdtyp[$i]." - HTTP GET error code ".$resp->code." -> no Data";
					last;						## ERROR JSON-query -> Abbruch schleife
				}
				
				my $features;
				my $features_i=0;
				
				my @xs1_readings = ("xs1_start","xs1_devicename","xs1_bootloader","xs1_hardware","xs1_features","xs1_firmware","xs1_mac","xs1_dhcp");
				my @xs1_decoded = (FmtDateTime(time()-($decoded->{'info'}{'uptime'})) , $decoded->{'info'}{'devicename'} , $decoded->{'info'}{'bootloader'} , $decoded->{'info'}{'hardware'} , $features , $decoded->{'info'}{'firmware'} , $decoded->{'info'}{'mac'} , $decoded->{'info'}{'autoip'});
				
				my $oldState = ReadingsVal($name, $xs1_readings[0], "2000-01-01 03:33:33");	## Readings Wert
				my @oldstate = split (/[-,:,\s\/]/, $oldState); 							## Split $year, $month, $mday, $hour, $min, $sec
				$oldState = fhemTimeGm($oldstate[5], $oldstate[4], $oldstate[3], $oldstate[2], $oldstate[1]-1, $oldstate[0]-1900); 	## Verarbeitung $sec, $min, $hour, $mday, $month-1, $year-1900
				
				my $newState = FmtDateTime(time()-($decoded->{'info'}{'uptime'}));			## ARRAY uptime Wert xs1 aktuell
				my @newState = split (/[-,:,\s\/]/, $newState); 							## Split $year, $month, $mday, $hour, $min, $sec
				$newState = fhemTimeGm($newState[5], $newState[4], $newState[3], $newState[2], $newState[1]-1, $newState[0]-1900); 	## Verarbeitung $sec, $min, $hour, $mday, $month-1, $year-1900
				
				if (abs($oldState - $newState) > 5) {	## Vergleich mit 5 Sekunden Tolleranz je Verabeitungszeit Netzwerk | DLAN | CPU
					readingsBeginUpdate($hash);
					for my $i2 (0..7) {
						if ($i2 == 4) {
								while (defined $decoded->{'info'}{'features'}->[$features_i]) {
								$features.= $decoded->{'info'}{'features'}->[$features_i]." ";
								$features_i++;
							}
							$xs1_decoded[4] = $features;	## ARRAY Wert xs1_decoded wird definiert
						}
						if (defined $xs1_decoded[$i2]) {

							readingsBulkUpdate($hash, $xs1_readings[$i2] , $xs1_decoded[$i2]);
							Debug " $typ: ".$xs1_readings[$i2].": ".$xs1_decoded[$i2] if($debug);
						} else {
							Log3 $name, 3, "$typ: GetUpDate | ARRAY-ERROR xs1 -> no Data in loop $i|$i2";
							last;
						}
					}
					readingsEndUpdate($hash, 1);
				}
			} elsif ($i == 3) {			### xs1 Timers
				if ($resp->code != "200") {								## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
					Log3 $name, 3, "$typ: GetUpDate | cmdtyp=".$cmdtyp[$i]." - HTTP GET error code ".$resp->code." -> no Data";
					last;				## ERROR JSON-query -> Abbruch schleife
				}
				
				my @array = @{ $decoded->{$arrayname[$i]} };
				foreach my $f ( @array ) {
					my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}), "unknown");	## Readings Wert
					my $newState = FmtDateTime($f->{"next"});			## ARRAY Wert xs1 aktuell
					
					if ($f->{"type"} ne "disabled") {
						if ($oldState ne $newState) {					## Update Reading nur bei Wertänderung
							readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $f->{"id"}) , FmtDateTime($f->{"next"}), 1);
						}
						Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." | ".$f->{"name"}." | ".$f->{"type"}." | ". $f->{"next"} if($debug);
					} elsif ($oldState ne "unknown") {					## deaktive Timer mit Wert werden als Reading entfernt
						Log3 $name, 3, "$typ: GetUpDate | ".$readingsname[$i]."_".sprintf("%02d", $f->{"id"})." is deactive in xs1";
						delete $defs{$name}{READINGS}{$readingsname[$i]."_".sprintf("%02d", $f->{"id"})};
					}
				}
			}
	 
			if ($i < 3) {
				Debug "\n ------------- ERROR CHECK - SUB -------------" if($debug);
			}
			### Schleifen Ende ###
		}
      	
		Debug "\n ------------- ERROR CHECK - ALL END -------------\n " if($debug);
	}
	
	if ($xs1_security == 10) {									## Abschaltung xs1 nach 10 Verbindungsversuchen
		$attr{$name}{disable}	= "1";
		readingsSingleUpdate($hash, "state", "deactive", 1);
		RemoveInternalTimer($hash);								## Timer löschen
		Log3 $name, 3, "$typ: GetUpDate | connection ERROR -> xs1 set to disable! Device not reachable after 10 attempts";
	}
}

sub xs1Bridge_Write($)				## Zustellen von Daten via IOWrite() vom logischen zum physischen Modul 
{
	my ($hash, $Aktor_ID, $xs1_typ, $cmd) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	my $xs1_ip = $hash->{xs1_ip};
   
   ## Anfrage (Client -> XS1): http://192.168.1.242/control?callback=cname&cmd=set_state_actuator&number=1&value=50

	$Aktor_ID = substr($Aktor_ID, 1,2);

	if ($xs1_typ eq "switch") {
		if ($cmd eq "off") {
			$cmd = 0;
		} elsif ($cmd eq "on") {
			$cmd = 100;
		}
	}

	my $json;
	my $json_utf8;
	my $decoded;
	my $xs1cmd = "http://$xs1_ip/control?callback=cname&cmd=set_state_actuator&number=$Aktor_ID&value=$cmd";
	
	my $ua = LWP::UserAgent->new;									## CHECK JSON Adresse -> JSON-query, sonst FHEM shutdown
	my $resp = $ua->request(HTTP::Request->new(GET => $xs1cmd));
	
	if ($resp->code != "200") {										## http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Status.pm
		Log3 $name, 3, "$typ: Write | cmd=".$xs1cmd." - HTTP GET error code ".$resp->code." -> no Control possible";
		return undef;
	} else {
		Log3 $name, 3, "$typ: Write | Send to xs1 -> $xs1cmd";
		
		($json) = get( $xs1cmd ) =~ /[^(]*[}]/g;		## cut cname( + ) am Ende von Ausgabe -> ARRAY Struktur als Antwort vom xs1
		#$json_utf8 = eval {encode_utf8( $json )};		## UTF-8 character Bearbeitung, da xs1 TempSensoren ERROR
		#$decoded = eval {decode_json( $json_utf8 )};	## auswertbares ARAAY
	}
}

sub xs1Bridge_Notify($$)    
{                     

}

sub xs1Bridge_Undef($$)    
{                     
	my ( $hash, $name) = @_;
	my $typ = $hash->{TYPE};
	
	RemoveInternalTimer($hash);
	Log3 $name, 3, "$typ: Device with Name: $name delete";
	delete $modules{xs1Bridge}{defptr}{BRIDGE} if( defined($modules{xs1Bridge}{defptr}{BRIDGE}) );
	return undef;                  
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item summary    Connection of the device xs1 from EZControl
=item summary_DE Anbindung des Ger&auml;tes xs1 der Firma EZControl
=begin html

<a name="xs1Bridge"></a>
<h3>xs1Bridge</h3>
<ul>
	With this module you can read out the device xs1 from EZcontrol. There will be actors | Sensors | Timer | Information read from xs1 and written in readings. With each read only readings are created or updated, which are also defined and active in xs1. Actor | Sensor or timer definitions which are deactivated in xs1 are NOT read.
	<br><br>

	The module was developed based on the firmware version v4-Beta of the xs1. There may be errors due to different adjustments within the manufacturer's firmware.<br>
	Testet firmware: v4.0.0.5326 (Beta) <br><br>

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
		<li>interval (30,60,180,360)<br>
		This is the interval in seconds at which readings are read from xs1<br>
		<i>For actuators, only different states are updated in the set interval.</i><br>
		<i>Sensors are always updated in intervals, regardless of the status.</i><br>
		(Default, interval 60)
		</li><br>
		<li>update_only_difference (0,1)<br>
		The actuators defined in xs1 are only updated when the value changes.<br>
		(Default, update_only_difference 0)</li><br>
		<li>view_Device_name (0,1)<br>
		The actor names defined in xs1 are read as Reading.<br>
		(Default, view_Device_name 0)<br>
		</li><br>
		<li>view_Device_function (0,1)<br>
		The actuator functions defined in xs1 are read out as Reading.<br>
		(Default, view_Device_function 0)<br>
		</li><br><br>
	</ul>
	<b>explanation:</b>
	<ul>
		<li>various Readings:</li>
		<ul>
		<li>Aktor_(01-64)</li> defined actuator in the device<br>
		<li>Aktor_(01-64)_name</li> defined actor name in the device<br>
		<li>Aktor_(01-64)_function(1-4)</li> defined actuator function in the device<br>
		<li>Sensor_(01-64)</li> defined sensor in the device<br>
		<li>Sensor_(01-64)_name</li> defined sensor name in the device<br>
		<li>Timer_(01-128)</li> defined timer in the device<br>
		<li>xs1_bootloader</li> version of bootloader<br>
		<li>xs1_dhcp</li> DHCP on/off<br>
		<li>xs1_features</li> purchased feature when buying (A = send | B = receive | C = Skripte/Makros | D = Media Access)<br>
		<li>xs1_firmware</li> firmware number<br>
		<li>xs1_start</li> device start<br>
		</ul><br>
		<li>The message "<code>HTTP GET error code 500 -> no Data </code>" in the log file says that there was no query for a short time.</li>
		<li>If the device has not been connected after 10 connection attempts, the module will switch on < disable > !</li><br>
		<li>Create logfile automatically after define | scheme: <code>define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log &lt;name&gt;</code><br>
			The following values ​​are recorded in logfile: Aktor_(01-64) or Sensor_(01-64) values | Timer | xs1-status information</li>
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

	Das Modul wurde entwickelt basierend auf dem Firmwarestand v4-Beta des xs1. Es kann aufgrund von unterschiedlichen Anpassungen innerhalb der Firmware des Herstellers zu Fehlern kommen.<br>
	Getestete Firmware: v4.0.0.5326 (Beta) <br><br>

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
		<li>interval (30,60,180,360)<br>
		Das ist der Intervall in Sekunden, in dem die Readings neu gelesen werden vom xs1.<br>
		<i>Bei Aktoren werden nur unterschiedliche Zustände aktualisiert im eingestellten Intervall.</i><br>
		<i>Sensoren werden unabhängig vom Zustand immer im Intervall aktualisiert.</i><br>
		(Default, interval 60)
		</li><br>
		<li>update_only_difference (0,1)<br>
		Die Aktoren welche im xs1 definiert wurden, werden nur bei Wert&auml;nderung aktualisiert.<br>
		(Default, update_only_difference 0)</li><br>
		<li>view_Device_name (0,1)<br>
		Die Aktor Namen welche im xs1 definiert wurden, werden als Reading ausgelesen.<br>
		(Default, view_Device_name 0)<br>
		</li><br>
		<li>view_Device_function (0,1)<br>
		Die Aktor Funktionen welche im xs1 definiert wurden, werden als Reading ausgelesen.<br>
		(Default, view_Device_function 0)<br>
		</li><br><br>
	</ul>
	<b>Erl&auml;uterung:</b>
	<ul>
		<li>Auszug Readings:</li>
		<ul>
		<li>Aktor_(01-64)</li> definierter Aktor mit jeweiligem Zustand im Ger&auml;t<br>
		<li>Aktor_(01-64)_name</li> definierter Aktorname im Ger&auml;t<br>
		<li>Aktor_(01-64)_function(1-4)</li> definierte Aktorfunktion im Ger&auml;t<br>
		<li>Sensor_(01-64)</li> definierter Sensor im Ger&auml;t<br>
		<li>Sensor_(01-64)</li> definierter Sensorname im Ger&auml;t<br>
		<li>Timer_(01-128)</li> definierter Timer im Ger&auml;t<br>
		<li>xs1_bootloader</li> Firmwareversion des Bootloaders<br>
		<li>xs1_dhcp</li> DHCP an/aus<br>
		<li>xs1_features</li> erworbene Feature beim Kauf (A = SENDEN | B = EMPFANGEN | C = Skripte/Makros | D = Speicherkartenzugriff)<br>
		<li>xs1_firmware</li> Firmwareversion<br>
		<li>xs1_start</li> Ger&auml;testart<br>
		</ul><br>
		<li>Die Meldung "<code>HTTP GET error code 500 -> no Data </code>" im Logfile besagt, das kurzzeitig keine Abfrage erfolgen konnte.</li>
		<li>Sollte das Ger&auml;t nach 10 Verbindungsversuchen ebenfalls keine Verbindung erhalten haben, so schaltet das Modul auf < disable > !</li><br>
		<li>Logfile Erstellung erfolgt automatisch nach dem definieren. | Schema: <code>define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log &lt;Name&gt;</code><br>
			Folgende Werte werden im Logfile erfasst: Aktor_(01-64) bzw. Sensor_(01-64) Werte | Timer | xs1-Statusinformationen</li>
	</ul>
</ul>
=end html_DE
=cut
