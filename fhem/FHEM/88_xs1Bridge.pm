#################################################################
# $Id$
#################################################################
# physisches Modul - Verbindung zur Hardware
#
# note / ToDo´s / Bugs:
# - Port Check ???
# 
# 
# 
#################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use HttpUtils;					# um Daten via HTTP auszutauschen https://wiki.fhem.de/wiki/HttpUtils
use strict;				
use warnings;					# Warnings
use Net::Ping;

my $missingModul		= "";
my $xs1_ConnectionTry 	= 1;	# disable Funktion sobald 10x keine Verbindung (Schutzabschaltung)
my $xs1_id;

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Net::Ping;1" or $missingModul .= "Net::Ping ";

#$| = 1;		#Puffern abschalten, Hilfreich für PEARL WARNINGS Search

sub xs1Bridge_Initialize($) {
	my ($hash) = @_;
	
	$hash->{WriteFn}    = "xs1Bridge_Write";
	$hash->{Clients}    = ":xs1Dev:";
	$hash->{MatchList}  = { "1:xs1Dev"   =>	'[x][s][1][D][e][v][#][A][k][t][o][r]#[0-6][0-9].*|[x][s][1][D][e][v][#][S][e][n][s][o][r]#[0-6][0-9].*' };	## https://regex101.com/ Testfunktion
	
	$hash->{DefFn}		=	"xs1Bridge_Define";
	$hash->{AttrFn}  	= 	"xs1Bridge_Attr";  
	$hash->{UndefFn}	=	"xs1Bridge_Undef";
	$hash->{AttrList}	=	"debug:0,1 ".
								"ignore:0,1 ".
								"update_only_difference:0,1 ".
								"view_Device_name:0,1 ".
								"view_Device_function:0,1 ".
								"xs1_blackl_aktor ".
								"xs1_blackl_sensor ".
								"xs1_control:0,1 ".
								"xs1_interval:0,30,60,180,360 ";
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

					#		0		1	 2
	return "Usage: define <NAME> $name <IP>"  if(@arg != 3);
	#return "Usage: define <NAME> $name <IP> <PORT>"  if(@arg != 4);
	return "Your IP is not valid. Please Check!" if not($arg[2] =~ /[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}/s);
	#return "Your PORT is not valid. Please Check!"  if not($arg[3] =~ /[0-9]{2,5}/s);
	return "Cannot define xs1Bridge device. Perl modul ${missingModul}is missing." if ( $missingModul );

	my $xs1check = 0;
	if(!defined $modules{xs1Bridge}) {
		my $p = Net::Ping->new("tcp", 2);
		if(!($p->ping("$arg[2]", 2))) {
			$xs1check = 1;
		}
		$p->close();
		return "Your IP is not reachable. Please Check!" if ($xs1check == 1);
	}
	
	# Parameter Define
	my $xs1_ip = $arg[2];				## Zusatzparameter 1 bei Define - ggf. nur in Sub
	$hash->{xs1_ip} = $xs1_ip;
	
	$hash->{STATE} = "Initialized";		## Der Status des Modules nach Initialisierung.
	$hash->{TIME} = time();				## Zeitstempel, derzeit vom anlegen des Moduls
	$hash->{VERSION} = "1.20";			## Version
	$hash->{BRIDGE}	= 1;
	
	# Attribut gesetzt
	$attr{$name}{xs1_interval}	= "60"	if( not defined( $attr{$name}{xs1_interval} ) );
	$attr{$name}{room}			= "xs1"	if( not defined( $attr{$name}{room} ) );
	$attr{$name}{xs1_control}	= "0"		if( not defined( $attr{$name}{xs1_control} ) );
	
	$modules{xs1Bridge}{defptr}{BRIDGE} = $hash;
	
	InternalTimer(gettimeofday()+$attr{$name}{xs1_interval}, "xs1Bridge_GetUpDate", $hash);		## set Timer

	#Log3 $name, 3, "$typ: IODev defined with xs1_ip: $xs1_ip";
	
	if(!defined($defs{'FileLog_xs1Bridge'})) {												## Logfile existent check
		Log3 $name, 4, "$typ: FileLog_xs1Bridge ist NICHT definiert";
		fhem("define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log ".$arg[0]);		## Logfile define
		fhem("attr FileLog_xs1Bridge room xs1");											## Logfile in xs1 room
	} else {
		Log3 $name, 4, "$typ: FileLog_xs1Bridge ist definiert";
	}

	return undef;
}

sub xs1Bridge_Attr(@) {
	my ($cmd,$name,$attrName,$attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $xs1_interval = 0;
	
	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
   
	#### Handling bei set .. attribute
	if ($cmd eq "set") {
		RemoveInternalTimer($hash);											## Timer löschen
		Debug " $typ: Attr | Cmd:$cmd | RemoveInternalTimer" if($debug);
		if ($attrName eq "xs1_interval" && $attrValue == 0) {				## Handling xs1_interval == 0
			RemoveInternalTimer($hash);
			readingsSingleUpdate($hash, "state", "deactive", 1);
		}elsif ($attrName eq "xs1_interval" && $attrValue >= 30) {	## Handling xs1_interval >= 30
			$xs1_ConnectionTry = 1;
			my $xs1_interval = $attrValue;
			InternalTimer(gettimeofday()+$xs1_interval, "xs1Bridge_GetUpDate", $hash);
			readingsSingleUpdate($hash, "state", "active", 1);
		### Ansicht xs1_Device_function ###
		}elsif ($attrName eq "view_Device_function") {
			if ($attrValue eq "1") {								## Handling view_Device_function 1
				Log3 $name, 3, "$typ: Attribut view_Device_function $cmd to $attrValue";
			}
			elsif ($attrValue eq "0") {								## Handling view_Device_function 0
				Log3 $name, 3, "$typ: Attribut view_Device_function $cmd to $attrValue";
			}
		### Ansicht xs1_Device_name ###
		}elsif ($attrName eq "view_Device_name") {
				if ($attrValue eq "1") {								## Handling view_Device_name 1
					Log3 $name, 3, "$typ: Attribut view_Device_name $cmd to $attrValue";
				}
				elsif ($attrValue eq "0") {								## Handling view_Device_name 0
						Log3 $name, 3, "$typ: Attribut view_Device_name $cmd to $attrValue";
						for my $i (0..64) {
						delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
						delete $hash->{READINGS}{"Sensor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
					}
				}
		### Wertaenderung nur bei Difference ###
		}elsif ($attrName eq "update_only_difference") {
			if ($attrValue eq "1") {								## Handling update_only_difference 1
				Log3 $name, 3, "$typ: Attribut update_only_difference $cmd to $attrValue";
			}
			elsif ($attrValue eq "0") {								## Handling update_only_difference 0
				Log3 $name, 3, "$typ: Attribut update_only_difference $cmd to $attrValue";
				for my $i (0..64) {
					delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_name"} if($hash->{READINGS});
				}
			}
		### xs1 - steuern ###
		}elsif ($attrName eq "xs1_control") {
			if ($attrValue eq "1") {								## Handling xs1_control 1
				if(! $modules{xs1Dev}) {							## Check Modul vorhanden
					$attr{$name}{xs1_control}	= "0";
					return "Module xs1Dev is non-existent or still under development. Please wait"
				}
			}
		### Blacklist - Aktor / Sensor ###
		}elsif ($attrName eq "xs1_blackl_aktor") {			## Handling xs1_blackl_aktor
				Log3 $name, 4, "$typ: Attribut xs1_blackl_aktor $attrValue";
		}elsif ($attrName eq "xs1_blackl_sensor") {			## Handling xs1_blackl_sensor
			Log3 $name, 4, "$typ: Attribut xs1_blackl_sensor $attrValue";
		}
	}
	
	#### Handling bei del ... attribute
	if ($cmd eq "del") {
		if ($attrName eq "xs1_interval") {					## Handling deleteattr xs1_interval
			RemoveInternalTimer($hash);
			readingsSingleUpdate($hash, "state", "deactive", 1);
			Debug " $typ: Attr | Cmd:$cmd | $attrName" if($debug);
		}
		elsif ($attrName eq "view_Device_function") {		## Handling deleteattr view_Device_function
			Log3 $name, 3, "$typ: Attribut view_Device_function delete";
			for my $i (0..64) {
				for my $i2 (1..4) {
					delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i)."_function_".$i2} if($hash->{READINGS});
				}
			}
		}
		elsif ($attrName eq "view_Device_name") {			## Handling deleteattr view_Device_name
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

	#### Handling bei state active
	if ($hash->{STATE} eq "active") {
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+$xs1_interval, "xs1Bridge_GetUpDate", $hash);
		Debug " $typ: Attr | RemoveInternalTimer + InternalTimer" if($debug);
	}
	return undef;
}

sub xs1Bridge_GetUpDate() {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	my $state = $hash->{STATE};
	my $xs1_ip = $hash->{xs1_ip};
	
	my $xs1_uptimeStart = $hash->{helper}{xs1_uptimeStart};
	my $xs1_uptimeOld = $hash->{helper}{xs1_uptimeOld};
	my $xs1_uptimeNew = $hash->{helper}{xs1_uptimeNew};
	my $def;
	
	#http://x.x.x.x/control?callback=cname&cmd=...
	#get_list_actuators        - list all actuators			i0
	#get_list_sensors          - list all sensors			i1
	#get_list_timers           - list all timers				i3
	#get_config_info           - list all device info´s	i2
	#get_protocol_info         - list protocol info´s
   
	my $cmd = "/control?callback=cname&cmd=";
	my @cmdtyp = ("get_list_actuators","get_list_sensors","get_config_info","get_list_timers","get_list_actuators");
	my @arrayname = ("actuator","sensor","info","timer","function");
	my @readingsname = ("Aktor","Sensor","","Timer","");
   
	my $debug = AttrVal($hash->{NAME},"debug",0);
	my $xs1_interval = AttrVal($name, "xs1_interval", 60);
	my $viewDeviceName = AttrVal($hash->{NAME},"view_Device_name",0);
	my $viewDeviceFunction = AttrVal($hash->{NAME},"view_Device_function",0);
	my $update_only_difference = AttrVal($hash->{NAME},"update_only_difference",0);
	my $xs1_control = AttrVal($hash->{NAME},"xs1_control",0);
	my $xs1_blackl_aktor = AttrVal($hash->{NAME},"xs1_blackl_aktor",0);
	my $xs1_blackl_sensor = AttrVal($hash->{NAME},"xs1_blackl_sensor",0);
	
	#### xs1Bridge xs1_interval >= 10 -> aktiviert zum auslesen
	if ($xs1_interval >= 10 && $xs1_ConnectionTry <= 5) {
		RemoveInternalTimer($hash);									## Timer löschen
		InternalTimer(gettimeofday()+$xs1_interval, "xs1Bridge_GetUpDate", $hash);
		Debug " -------------- ERROR CHECK - START --------------" if($debug);
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

		#### JSON Abfrage - Schleife
		for my $i (0..3) {
			#### HTTP Requests #### Start ####
			my $connection;
			my $Http_err 	= "";
			my $Http_data 	= "";
			my $param 		= 	{
									url        => "http://".$xs1_ip.$cmd.$cmdtyp[$i],
									timeout    => 3,
									method     => "GET",		# Lesen von Inhalten
								};

			HttpUtils_BlockingGet($param);
			($Http_err, $Http_data) = HttpUtils_BlockingGet($param);
			#### HTTP Requests #### END ####	
		
			my $adress = "http://".$xs1_ip.$cmd.$cmdtyp[$i];
			my $json;
			my $json_utf8;
			my $decoded;			

			Debug " $typ: GetUpDate | Adresse: $adress | xs1_ConnectionTry=$xs1_ConnectionTry" if($debug && $Http_err eq "");
			Debug " $typ: GetUpDate | HTTP request: ".$Http_err."| xs1_ConnectionTry=$xs1_ConnectionTry" if($debug && $Http_err ne "");

			#### HTTP Requests, ERROR
			if ($Http_err ne "") {
				# ERROR Message
				# http://192.168.2.5/control?callback=cname&cmd=get_list_actuators: Can't connect(1) to http://192.168.2.5:80: IO::Socket::INET: connect: No route to host
				# http://192.168.2.5/control?callback=cname&cmd=get_config_info: empty answer received
				# http://192.168.2.5/control?callback=cname&cmd=get_config_info: Select timeout/error: 
				
				#($Http_err) = $Http_err =~ /[:]\s.*/g;
				Log3 $name, 3, "$typ: GetUpDate | Try=$xs1_ConnectionTry loop=$i | Error: ".$Http_err;
				$xs1_ConnectionTry++;
				last;											## Abbruch Schleife
			}
			#### HTTP Requests, OK dann ARRAY Verarbeitung	
			elsif ($Http_data ne "") {						
				($json) = $Http_data =~ /[^(]*[}]/g;			## cut cname( + ) am Ende von Ausgabe -> ARRAY Struktur als Antwort vom xs1
				$json_utf8 = eval {encode_utf8( $json )};		## UTF-8 character Bearbeitung, da xs1 TempSensoren ERROR
				$decoded = eval {decode_json( $json_utf8 )};
				$xs1_ConnectionTry 	= 1;			

				#### xs1 Aktoren / Sensoren als Readings
				if ($i <= 1 ) {
					my $xs1_data;
					my @array;
			
					if (defined $decoded->{$arrayname[$i]}) {
						@array = @{ $decoded->{$arrayname[$i]} };
					} else {
						Log3 $name, 3, "$typ: GetUpDate | ARRAY-ERROR xs1 -> no Data in loop $i";
						last;
					}

					my $i3 = 0;		## Counter für real Werte in xs1, da sonst Verschiebungen wenn User ID´s verschiebt, NOTWENDIG!
					
					foreach my $f ( @array ) {
						$i3++;
						$xs1_id = $f->{"id"};
						
						#### Test ob Aktoren / Sensoren auf xs1_blackl
						if ($f->{"type"} ne "disabled" && is_in_array($hash,$xs1_id,$i) == 0) {
							my $xs1Dev = "xs1Dev";

							#### Aktoren spezifisch
							my $xs1_function1 = "-";
							my $xs1_function2 = "-";
							my $xs1_function3 = "-";
							my $xs1_function4 = "-";

							if ($i == 0) {
								#### xs1 Aktoren nur update bei differenten Wert
								if ($update_only_difference == 1) {
									my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $i3), "unknown");	## Readings Wert
									my $newState = sprintf("%.1f" , $f->{"value"});														## ARRAY Wert xs1 aktuell

									Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $i3)." oldState=$oldState newState=$newState" if($debug);
									
									if ($oldState ne $newState) {
										readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $i3) , $newState, 0);
									}
								}

								#### xs1 Aktoren / Funktion != disable
								my @array2 = @{ $decoded->{'actuator'}->[$i3-1]->{$arrayname[4]} };
								my $i2 = 0;		## Funktionscounter

								foreach my $f2 ( @array2 ) {
									$i2++;

									#### xs1 Option - Ansicht Funktionsname
									if ($viewDeviceFunction == 1) {
										my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $i3)."_".$arrayname[4]."_".$i2, "unknown");		## Readings Wert
										my $newState = $f2->{'type'};		## ARRAY Wert xs1 aktuell

										if ($oldState ne "unknown" && $newState eq "disabled") { 	## FunktionReading del bei disable
											Debug " $typ: "."Aktor_".sprintf("%02d", $i3)."_function_".$i2." are disabled" if($debug);
											delete $hash->{READINGS}{"Aktor_".sprintf("%02d", $i3)."_function_".$i2} if($hash->{READINGS});
										}

										if ($f2->{"type"} ne "disabled") {  ## Funktion != function -> type disable
											if ($oldState ne $newState) {
												readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $i3)."_".$arrayname[4]."_".$i2 , $f2->{"type"} , 1);
											}
										}
									}

									#### Funktion != function -> type disable
									if ($f2->{"type"} ne "disabled") {
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

							#### Value der Aktoren | Sensoren
							if ($i == 1 || $i == 0 && $update_only_difference == 0) {		# Aktoren | Sensoren im intervall - Format 0.0 bzw. 37.0 wie aus xs1
								readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $i3) , sprintf("%.1f" , $f->{"value"}), 0);
								$xs1_data = $xs1Dev."#".$readingsname[$i]."#".sprintf("%02d", $i3)."#".$f->{"type"}."#".sprintf("%.1f" , $f->{"value"})."#"."$xs1_function1"."#"."$xs1_function2"."#"."$xs1_function3"."#"."$xs1_function4"."#".$f->{"name"};
							} elsif ($i == 0 && $update_only_difference == 1){				# Aktoren | nur bei DIFF - Format 0.0 bzw. 37.0 wie aus xs1
								$xs1_data = $xs1Dev."#".$readingsname[$i]."#".sprintf("%02d", $i3)."#".$f->{"type"}."#".sprintf("%.1f" , $f->{"value"})."#"."$xs1_function1"."#"."$xs1_function2"."#"."$xs1_function3"."#"."$xs1_function4"."#".$f->{"name"};
							}

							#### Ausgaben je Typ unterschiedlich !!!
							Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $i3)." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"}." | "."F1 $xs1_function1 | F2 $xs1_function2 | F3 $xs1_function3 | F4 $xs1_function4" if($debug == 1 && $i == 0);
							Debug " $typ: ".$readingsname[$i]."_".sprintf("%02d", $i3)." | ".$f->{"type"}." | ".$f->{"name"}." | ". $f->{"value"} if($debug == 1 && $i != 0);

							### Ansicht Namen der Aktoren | Sensoren als Readings
							if ($viewDeviceName == 1) {
								my $oldState = ReadingsVal($name, $readingsname[$i]."_".sprintf("%02d", $i3)."_name", "unknown");		## Readings Wert
								my $newState = $f->{"name"};		## ARRAY Wert xs1 aktuell
								
								if ($oldState ne $newState) {		## Namen nur bei Änderung schreiben
									#Log3 $name, 3, "$typ: GetUpDate | newState=$newState ne oldState=$oldState";
									readingsSingleUpdate($hash, $readingsname[$i]."_".sprintf("%02d", $i3)."_name" , $f->{"name"} , 1);
								}
							}
							
							### Dispatch an xs1Device Modul						
							if ($xs1Dev_check eq "ok" && $xs1_control == 1) {
								Debug " $typ: GetUpDate | Dispatch: $xs1_data" if($debug);
								Dispatch($hash,$xs1_data,undef) if($xs1_data);
							}
						} else {
						#### ID bzw. Speicherplatz xs1 ist disabled | Reading are delete
							delete $hash->{READINGS}{$readingsname[$i]."_".sprintf("%02d", $i3)} if($hash->{READINGS});
							delete $hash->{READINGS}{$readingsname[$i]."_".sprintf("%02d", $i3)."_name"} if($hash->{READINGS});
							
							### Erweiterung v1.20 ### Device | Logfile | SVG löschen wenn in xs1 disable - TEST
							my $delDevice = "xs1Dev_".$readingsname[$i]."_".sprintf("%02d", $i3);
							
							if (defined($defs{"xs1Dev_".$readingsname[$i]."_".sprintf("%02d", $i3)})) {
								#Log3 $name, 3, "$typ: GetUpDate | for delete $delDevice";
								fhem("delete ".$delDevice);				## delete Device
							}
							
							if (defined($defs{"SVG_xs1Dev_".$readingsname[$i]."_".sprintf("%02d", $i3)})) {
								#Log3 $name, 3, "$typ: GetUpDate | for delete FileLog_$delDevice";
								fhem("delete SVG_".$delDevice);		## delete FileLog_Device
							}
							
							if (defined($defs{"FileLog_xs1Dev_".$readingsname[$i]."_".sprintf("%02d", $i3)})) {
								#Log3 $name, 3, "$typ: GetUpDate | for delete FileLog_$delDevice";
								fhem("delete FileLog_".$delDevice);		## delete FileLog_Device
							}
							
							### Erweiterung v1.20 ### Device | Logfile | SVG löschen wenn in xs1 disable - TEST ### ENDE ###
							
							if ($i == 0) {
								for my $count (1..4) {
									delete $hash->{READINGS}{$readingsname[$i]."_".sprintf("%02d", $i3)."_function_".$count} if($hash->{READINGS});
								}
							}
						}
					}
				} 
				#### xs1 Info´s nur bei uptime Änderung als Readings
				elsif ($i == 2) {
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
				
					#### Vergleich mit 5 Sekunden Tolleranz je Verarbeitungszeit Netzwerk | DLAN | CPU
					if (abs($oldState - $newState) > 5 || $debug == 1) {
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
				} 
				#### xs1 Timers als Readings
				elsif ($i == 3) {
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
					Debug " --------------- ERROR CHECK - SUB --------------- " if($debug);
				}
				### Schleifen Ende ###
			}
		}

		Debug " ------------- ERROR CHECK - ALL END -------------\n " if($debug);
	}
	
	if ($xs1_ConnectionTry == 6) {								## Abschaltung xs1 nach 5 Verbindungsversuchen
		$attr{$name}{xs1_interval}	= "0";
		readingsSingleUpdate($hash, "state", "deactive", 1);
		RemoveInternalTimer($hash);								## Timer löschen
		Log3 $name, 3, "$typ: GetUpDate | connection ERROR -> xs1 set to disable! Device not reachable after 5 attempts";
	}
}

sub xs1Bridge_Write($)			## Zustellen von Daten via IOWrite() vom logischen zum physischen Modul 
{
	my ($hash, $Aktor_ID, $xs1_typ, $cmd, $cmd2) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	my $xs1_ip = $hash->{xs1_ip};
   
	## Anfrage (Client -> XS1): http://192.168.1.242/control?callback=cname&cmd=set_state_actuator&number=1&value=100
	
	## Aktor Typen aus xs1: (notwendig zur Verarbeitung)
	## -------------------------------------------------
	## blind - Jalousie				|	dimmer - Dimmer				|	door - Tür			|	disabled - deaktivert
	## switch - Schalter			|	shutter - Rolladen			|	sound - Ton			|	sun-blind - Markise
	## temperature - Temperatur		|	timerswitch - Zeitschalter	|	window - Fenster

	## Sensor Typen (Auswahl) aus xs1: (nur Info)
	## ------------------------------------------
	## alarmmat - Alarmmatte		|	disabled - deaktivert
	## gas_butan - Gasmelder Butan	|	gas_peak - Gas Spitzenwert
	## mail - Briefmelder			|	motion - Bewegung
	## other - Andere				|	presence - Anwesenheit
	## pwr_consump - Energiezähler	|	pwr_peak - Energie Spitzenwert
	## soilmoisture - Bodenfeuchte	|	soiltemp -  Bodentemperatur
	## leafwetness - Blattfeuchte	|	remotecontrol - Fernbedienung
	## windowopen - Fenstermelder	...

	$Aktor_ID = substr($Aktor_ID, 1,2);

	my $xs1cmd;
	#### xs1 Typ switch || shutter || timerswitch - Anpassung Sendebefehl
	if ($xs1_typ eq "switch" || $xs1_typ eq "shutter" || $xs1_typ eq "timerswitch") {
		$xs1cmd = "http://$xs1_ip/control?callback=cname&cmd=set_state_actuator&number=$Aktor_ID&$cmd2";
	} elsif ($xs1_typ eq "dimmer") {
		if ($cmd eq "off") {
			$cmd = 0;
		}
		$xs1cmd = "http://$xs1_ip/control?callback=cname&cmd=set_state_actuator&number=$Aktor_ID&value=$cmd";
	} else {
		#### keine Verarbeitung zum senden ####
		Log3 $name, 3, "$typ: Write | $xs1_typ not control xs1. Please inform me!";
		last;
	}

	### HTTP Requests #### Start ####
	my $connection;
	my $Http_err 	= "";
	my $Http_data;
	my $param 	= 	{
						url        => "$xs1cmd",
						timeout    => 3,
						method     => "GET",		# Lesen von Inhalten
					};

	HttpUtils_BlockingGet($param);
	($Http_err, $Http_data) = HttpUtils_BlockingGet($param);
	### HTTP Requests #### END ####	
	
	if ($Http_err ne "") {
		($Http_err) = $Http_err =~ /[:]\s.*/g;
		Log3 $name, 3, "$typ: Write | no Control possible | Error".$Http_err;
		return undef;
	} elsif ($Http_data ne "") {
		Log3 $name, 4, "$typ: Write | Send to xs1 -> $xs1cmd";		## Kontrolle Sendebefehl
	}
}

sub xs1Bridge_Undef($$)
{
	my ( $hash, $name) = @_;
	my $typ = $hash->{TYPE};

	RemoveInternalTimer($hash);

	delete $modules{xs1Bridge}{defptr}{BRIDGE} if( defined($modules{xs1Bridge}{defptr}{BRIDGE}) );
	Log3 $name, 3, "$typ: deleting Device with Name $name";
	
	foreach my $d (sort keys %defs) {
		if(defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash) {
			Log3 $name, 3, "$typ: deleting IODev for $d";
			delete $defs{$d}{IODev};
		}
	}
	
	return undef;
}


##########################
# eigene Sub

sub is_in_array($$$)
{
	my ( $hash,$xs1_id,$i) = @_;
	my $name = $hash->{NAME};
	my $typ = $hash->{TYPE};
	
	my $xs1_blackl = AttrVal($hash->{NAME},"xs1_blackl_aktor",0) if ($i eq 0);
	$xs1_blackl = AttrVal($hash->{NAME},"xs1_blackl_sensor",0) if ($i eq 1);

	my @attr_array=split(/,/,$xs1_blackl);
	if ( grep( /^$xs1_id$/, @attr_array ) ) {
		#Log3 $name, 3, "$typ: is_in_array | id=$xs1_id auf xs1_blackl Aktoren" if ($i eq 0);
		#Log3 $name, 3, "$typ: is_in_array | id=$xs1_id auf xs1_blackl Sensoren" if ($i eq 1);
		return 1;
	} else {
		#Log3 $name, 3, "$typ: is_in_array | id=$xs1_id NICHT auf xs1_blackl Aktoren" if ($i eq 0);
		#Log3 $name, 3, "$typ: is_in_array | id=$xs1_id NICHT auf xs1_blackl Sensoren" if ($i eq 1);
		return 0;
	}

}

##########################

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
	Testet firmware: v4.0.0.5326 (Beta) @me | v3.0.0.4493 @ForumUser<br>
	
	<br><ul>
	<u>Currently implemented types of xs1 for processing: </u><br>
	<li>Aktor: dimmer, switch, shutter, timerswitch</li>
	<li>Sensor: barometer, counter, counterdiff, light, motion, other, rain, rain_1h, rain_24h, rainintensity, remotecontrol, uv_index, waterdetector, winddirection, windgust, windspeed, windvariance</li>
	</ul><br><br>

	<a name="xs1Bridge_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;NAME&gt; xs1Bridge &lt;IP&gt;</code>
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
		</li><br>
		<li>xs1_blackl_aktor<br>
		A comma-separated blacklist of actuators, which should not be created automatically as soon as xs1_control = 1(aktiv).<br>
		(Example: 2,40,3)<br>
		</li><br>
		<li>xs1_blackl_sensor<br>
		A comma-separated blacklist of sensors, which should not be created automatically as soon as xs1_control = 1(aktiv).<br>
		(Example: 3,37,55)<br>
		</li><br>
		<li>xs1_control (0,1)<br>
		Option to control the xs1. After activating this, the xs1Dev module creates each actuator and sensor in FHEM.<br>
		(Default, xs1_control 0)<br><br>
		<li>xs1_interval (0,30,60,180,360)<br>
		This is the interval in seconds at which readings are read from xs1<br>
		<i>For actuators, only different states are updated in the set interval.</i><br>
		<i>Sensors are always updated in intervals, regardless of the status.</i><br>
		(Default, xs1_interval 60)
		</li><br>
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
		<li>The message "<code>... Can't connect ...</code>" or "<code>ERROR: empty answer received</code>" in the system logfile says that there was no query for a short time.<br>
		(This can happen more often with DLAN.)<br><br></li>
		<li>If the device has not been connected after 5 connection attempts, the module will switch on < disable > !</li><br>
		<li>Create logfile automatically after define | scheme: <code>define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log &lt;name&gt;</code><br>
			The following values ​​are recorded in logfile: Timer | xs1-status information</li>
	</ul>
</ul>
=end html
=begin html_DE

<a name="xs1Bridge"></a>
<h3>xs1Bridge</h3>
<ul>
	Mit diesem Modul k&ouml;nnen Sie das Gerät xs1 der Firma <a href="http://www.ezcontrol.de/">EZcontrol</a> auslesen. Das Modul ruft die Daten des xs1 via der Kommunikationsschnittstelle ab. Mit einem HTTP GET Requests erh&auml;lt man die Antworten in Textform welche im Datenformat JSON (JavaScript Object Notation) ausgegeben werden. 
	Es werden Aktoren | Sensoren | Timer | Informationen vom xs1 ausgelesen und in Readings geschrieben. Bei jedem Auslesen werden nur Readings angelegt bzw. aktualisiert, welche auch im xs1 definiert und aktiv sind. Aktor | Sensor bzw. Timer Definitionen welche deaktiviert sind im xs1, werden NICHT ausgelesen.
	<br><br>

	Das Modul wurde entwickelt basierend auf dem Firmwarestand v4-Beta des xs1. Es kann aufgrund von unterschiedlichen Anpassungen innerhalb der Firmware des Herstellers zu Fehlern kommen.<br>
	Getestete Firmware: v4.0.0.5326 (Beta) @me | v3.0.0.4493 @ForumUser<br>

	<br><ul>
	<u>Derzeit implementierte Typen des xs1 zur Verarbeitung: </u><br>
	<li>Aktor: dimmer, switch, shutter, timerswitch</li>
	<li>Sensor: barometer, counter, counterdiff, light, motion, other, rain, rain_1h, rain_24h, rainintensity, remotecontrol, uv_index, waterdetector, winddirection, windgust, windspeed, windvariance</li>
	</ul><br><br>
	
	<a name="xs1Bridge_define"></a>
	<b>Define</b><br>
		<ul>
		<code>define &lt;NAME&gt; xs1Bridge &lt;IP&gt;</code>
		<br><br>

		Ein anlegen des Modules ohne Angabe der IP vom xs1 ist nicht m&ouml;glich. Sollte die IP bei der Moduldefinierung nicht erreichbar sein, so bricht der Define Vorgang ab.
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
		</li><br>
		<li>xs1_blackl_aktor<br>
		Eine kommagetrennte Blacklist der Aktoren, welche nicht automatisch angelegt werden sollen sobald xs1_control = 1(aktiv).<br>
		(Beispiel: 2,40,3)<br>
		</li><br>
		<li>xs1_blackl_sensor<br>
		Eine kommagetrennte Blacklist der Sensoren, welche nicht automatisch angelegt werden sollen sobald xs1_control = 1(aktiv).<br>
		(Beispiel: 3,37,55)<br>
		</li><br>
		<li>xs1_control (0,1)<br>
		Die Freigabe zur Steuerung des xs1. Nach Aktivierung dieser, wird durch das xs1Dev Modul jeder Aktor und Sensor in FHEM angelegt.<br>
		(Default, xs1_control 0)<br>
		</li><br>
		<li>xs1_interval (0,30,60,180,360)<br>
		Das ist der Intervall in Sekunden, in dem die Readings neu gelesen werden vom xs1.<br>
		<i>Bei Aktoren werden nur unterschiedliche Zust&auml;nde aktualisiert im eingestellten Intervall.</i><br>
		<i>Sensoren werden unabhängig vom Zustand immer im Intervall aktualisiert.</i><br>
		(Default, xs1_interval 60)
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
		<li>Die Meldung "<code>Error: Can't connect ...</code>" oder "<code>ERROR: empty answer received</code>" im System-Logfile, besagt das kurzzeitig keine Abfrage erfolgen konnte.<br>
		(Das kann h&auml;ufiger bei DLAN vorkommen.)<br><br></li>
		<li>Sollte das Ger&auml;t nach 5 Verbindungsversuchen ebenfalls keine Verbindung erhalten haben, so schaltet das Modul auf < disable > !</li><br>
		<li>Logfile Erstellung erfolgt automatisch nach dem definieren. | Schema: <code>define FileLog_xs1Bridge FileLog ./log/xs1Bridge-%Y-%m.log &lt;Name&gt;</code><br>
			Folgende Werte werden im Logfile erfasst: Timer | xs1-Statusinformationen</li><br>
		<li>Sollte das Ger&auml;t nach 5 Verbindungsversuchen ebenfalls keine Verbindung erhalten haben, so schaltet das Modul auf < disable > !</li><br>
	</ul>
</ul>
=end html_DE
=cut
