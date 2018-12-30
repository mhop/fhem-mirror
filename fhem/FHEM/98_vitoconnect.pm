#########################################################################
# $Id$ 
# fhem Modul für Vissmann API. Based on investigation of "thetrueavatar"
# (https://github.com/thetrueavatar/Viessmann-Api)
#   
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
# 
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#   Changelog:
#
#   2018-11-24		initial version
#	 2018-12-11		non-blocking
#                 Reading "status" in "state" umbenannt
#   2018-12-23    Neue Werte in der API werden unter ihrem JSON Name als Reading eingetragen
#                 Neue Readings:
#  					heating.boiler.sensors.temperature.commonSupply.status error
#  					heating.boiler.temperature.value	                      48.1
#  					heating.burner.modulation.value                        11
#  					heating.burner.statistics.hours                        933.336666666667
#  					heating.burner.statistics.starts                       2717
#  					heating.circuits.0.circulation.pump.status             on
#  					heating.dhw.charging.active                            0
#  					heating.dhw.pumps.circulation.schedule.active          1
#  					heating.dhw.pumps.circulation.schedule.entries         sun mode:on end:22:30 start:04:30 position:0, fri end:22:30 mode:on position:0 start:04:30,
#  					                                                       mon mode:on end:22:30 start:04:30 position:0, 
#  					                                                       wed start:04:30 position:0 end:22:30 mode:on, thu mode:on end:22:30 position:0 start:04:30, sat end:22:30 mode:on position:0 start:04:30,
#  					                                                       tue position:0 start:04:30 end:22:30 mode:on,
#  					heating.dhw.pumps.circulation.status                   on
#  					heating.dhw.pumps.primary.status                       off
#  					heating.dhw.sensors.temperature.outlet.status          error
#  					heating.dhw.temperature.main.value                     53 
#  2018-12-30     initial offical release
#                 remove special characters from readings
#                 some internal improvements suggested by CoolTux
#          
#
#   ToDo:
# 						Passwort im KeyValue speichern statt im Klartext
#                 "set"s zum Steuern der Heizung
#                 Dokumentation (auch auf Deutsch)
#                 Nicht bei jedem Lesen neu einloggen
#                 Fehlerbehandlung verbessern
#						Attribute implementieren und dokumentieren (disable, ....)
#						"sinnvolle" Readings statt 1:1 aus der API übernommene
#		  				ErrorListChanges implementieren
#                 mapping der Readings optional machen
#




package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use HttpUtils;
#use Data::Dumper;

my $client_id = '79742319e39245de5f91d15ff4cac2a8';
my $client_secret = '8ad97aceb92c5892e102b093c7c083fa';
my $authorizeURL = 'https://iam.viessmann.com/idp/v1/authorize';
my $token_url = 'https://iam.viessmann.com/idp/v1/token';
my $apiURLBase = 'https://api.viessmann-platform.io';
my $general = '/general-management/installations?expanded=true&';
my $callback_uri = "vicare://oauth-callback/everest"; 

my %RequestList = (
    "heating.boiler.serial.value" 												=> "Kessel_Seriennummer",
    "heating.boiler.temperature.value"												=> "Kesseltemperatur_exact",
    "heating.boiler.sensors.temperature.commonSupply.status"				=> "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.main.status" 						=> "Kessel_Status",
    "heating.boiler.sensors.temperature.main.value" 						=> "Kesseltemperatur",
    "heating.burner.active" 														=> "Brenner_aktiv",
    "heating.burner.automatic.status" 											=> "Brenner_Status",
    "heating.burner.automatic.errorCode" 										=> "Brenner_Fehlercode",
    "heating.burner.current.power.value"                             => "Brenner_Leistung", 
    "heating.burner.modulation.value"                                  	=> "Brenner_Modulation",
    "heating.burner.statistics.hours"                                	=> "Brenner_Beriebsstunden",
	 "heating.burner.statistics.starts" 									 		=> "Brenner_Starts",
    "heating.circuits.enabled" 													=> "Aktive_Heizkreise",
    "heating.circuits.0.active" 													=> "HK1-aktiv",
    "heating.circuits.0.circulation.pump.status"          					=> "HK1-Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active" 						=> "HK1-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries" 					=> "HK1-Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status" 							=> "HK1-Frostschutz_Status",
    "heating.circuits.0.heating.curve.shift" 								=> "HK1-Heizkurve-Niveau",
    "heating.circuits.0.heating.curve.slope" 								=> "HK1-Heizkurve-Steigung",
    "heating.circuits.0.heating.schedule.active" 							=> "HK1-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries" 							=> "HK1-Zeitsteuerung_Heizung",
    "heating.circuits.0.operating.modes.active.value" 					=> "HK1-Betriebsart",
    "heating.circuits.0.operating.modes.dhw.active" 						=> "HK1-WW_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeating.active" 			=> "HK1-WW_und_Heizen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active" 			=> "HK1-Solltemperatur_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active" 			=> "HK1-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.0.operating.modes.standby.active" 					=> "HK1-Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value" 				=> "HK1-Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active" 				=> "HK1-Solltemperatur_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.temperature" 		=> "HK1-Solltemperatur_comfort",
    "heating.circuits.0.operating.programs.eco.active" 					=> "HK1-Solltemperatur_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature" 			=> "HK1-Solltemperatur_eco",
    "heating.circuits.0.operating.programs.external.active" 			=> "HK1-External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature" 		=> "HK1-External_Temperatur",
    "heating.circuits.0.operating.programs.holiday.active" 				=> "HK1-Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start" 				=> "HK1-Urlaub_Start",
    "heating.circuits.0.operating.programs.holiday.end" 					=> "HK1-Urlaub_Ende",
    "heating.circuits.0.operating.programs.normal.active" 				=> "HK1-Solltemperatur_aktiv",
    "heating.circuits.0.operating.programs.normal.temperature" 		=> "HK1-Solltemperatur_normal",
    "heating.circuits.0.operating.programs.reduced.active"				=> "HK1-Solltemperatur_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.temperature" 		=> "HK1-Solltemperatur_reduziert",
    "heating.circuits.0.operating.programs.standby.active" 				=> "HK1-Standby_aktiv",
    "heating.circuits.0.sensors.temperature.room.status" 				=> "HK1-Raum_Status",
    "heating.circuits.0.sensors.temperature.supply.status"				=> "HK1-Vorlauftemperatur_aktiv",
    "heating.circuits.0.sensors.temperature.supply.value" 				=> "HK1-Vorlauftemperatur",
    "heating.circuits.1.active" 													=> "HK2-aktiv",
    "heating.circuits.1.circulation.pump.status"                     	=> "HK2-Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active" 						=> "HK2-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries" 					=> "HK2-Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status" 							=> "HK2-Frostschutz_Status",
    "heating.circuits.1.heating.curve.shift" 								=> "HK2-Heizkurve-Niveau",
    "heating.circuits.1.heating.curve.slope" 								=> "HK2-Heizkurve-Steigung",
    "heating.circuits.1.heating.schedule.active" 							=> "HK2-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries" 							=> "HK2-Zeitsteuerung_Heizung",
    "heating.circuits.1.operating.modes.active.value" 					=> "HK2-Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active" 						=> "HK2-WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active" 			=> "HK2-WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" 			=> "HK2-Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" 			=> "HK2-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.standby.active" 					=> "HK2-Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" 				=> "HK2-Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" 				=> "HK2-Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.temperature" 		=> "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" 					=> "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" 			=> "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" 			=> "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" 		=> "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.holiday.active" 				=> "HK2-Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" 				=> "HK2-Urlaub_Start",
    "heating.circuits.1.operating.programs.holiday.end" 					=> "HK2-Urlaub_Ende",
    "heating.circuits.1.operating.programs.normal.active" 				=> "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.temperature" 		=> "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active"				=> "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.temperature" 		=> "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.standby.active" 				=> "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" 				=> "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.supply.status"				=> "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.value" 				=> "HK2-Vorlauftemperatur",
    "heating.configuration.multiFamilyHouse.active" 						=> "Mehrfamilenhaus_aktiv",
    "heating.controller.serial.value" 											=> "Controller_Seriennummer",
    "heating.device.time.offset.value" 										=> "Device_Time_Offset",
    "heating.dhw.active" 															=> "WW-aktiv",
    "heating.dhw.charging.active"                                      => "WW-Aufladung",
    "heating.dhw.oneTimeCharge.active" 										=> "WW-onTimeCharge_aktiv",
  	 "heating.dhw.pumps.circulation.schedule.active"                    	=> "WW-Zirklationspumpe_Zeitsteuerung_aktiv",
  	 "heating.dhw.pumps.circulation.schedule.entries"                   	=> "WW-Zirkulationspumpe_Zeitplan",
  	 "heating.dhw.pumps.circulation.status"                             	=> "WW-Zirkulationspumpe_Status",
  	 "heating.dhw.pumps.primary.status"                                 	=> "WW-Zirkulationspumpe_primaer",
  	 "heating.dhw.sensors.temperature.outlet.status"                    	=> "WW-Sensoren_Auslauf_Status",
  	 "heating.dhw.temperature.main.value"                              	=> "WW-Haupttemperatur",
    "heating.dhw.sensors.temperature.hotWaterStorage.status" 			=> "WW-Temperatur_aktiv",
    "heating.dhw.sensors.temperature.hotWaterStorage.value" 			=> "WW-Isttemperatur",
    "heating.dhw.temperature.value" 											=> "WW-Solltemperatur",
    "heating.dhw.schedule.active" 												=> "WW-zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries" 												=> "WW-Zeitplan",
    "heating.errors.active.entries" 											=> "Fehlereintraege_aktive",
    "heating.errors.history.entries" 											=> "Fehlereintraege_Historie",
    "heating.gas.consumption.dhw.day" 											=> "Gasverbrauch_WW/Tag",
    "heating.gas.consumption.dhw.week" 										=> "Gasverbrauch_WW/Woche",
    "heating.gas.consumption.dhw.month" 										=> "Gasverbrauch_WW/Monat",
    "heating.gas.consumption.dhw.year" 										=> "Gasverbrauch_WW/Jahr",
    "heating.gas.consumption.heating.day" 									=> "Gasverbrauch_Heizung/Tag",
    "heating.gas.consumption.heating.week" 									=> "Gasverbrauch_Heizung/Woche",
    "heating.gas.consumption.heating.month" 									=> "Gasverbrauch_Heizung/Monat",
    "heating.gas.consumption.heating.year" 									=> "Gasverbrauch_Heizung/Jahr",
    "heating.sensors.temperature.outside.status" 							=> "Aussen_Status",
    "heating.sensors.temperature.outside.statusWired" 					=> "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" 				=> "Aussen_StatusWireless",
    "heating.sensors.temperature.outside.value" 							=> "Aussentemperatur",
    "heating.service.timeBased.serviceDue" 									=> "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" 					=> "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" 			=> "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" 									=> "Service_Letzter",
    "heating.service.burnerBased.serviceDue" 								=> "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" 			=> "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" 	=> "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" 								=> "Service_Letzter_brennerbasiert"
);


sub vitoconnect_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}      = 'vitoconnect_Define';
    $hash->{UndefFn}    = 'vitoconnect_Undef';
    $hash->{SetFn}      = 'vitoconnect_Set';
    $hash->{GetFn}      = 'vitoconnect_Get';
    $hash->{AttrFn}     = 'vitoconnect_Attr';
    $hash->{ReadFn}     = 'vitoconnect_Read';
    $hash->{AttrList} =  "disable:0,1".$readingFnAttributes;
}

sub vitoconnect_Define($$) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @param = split('[ \t]+', $def);
    
    if(int(@param) < 5) { return "too few parameters: define <name> vitoconnect <user> <passwd> <intervall>"; }
    
    $hash->{user} = $param[2];
    $hash->{passwd} = $param[3];
    $hash->{intervall} = $param[4];
    $hash->{counter} = 0;
    
	 InternalTimer(gettimeofday()+2, "$name - _GetUpdate", $hash);   
    return undef;
}

sub vitoconnect_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    return undef;
}

sub vitoconnect_Get($@) {
	my ($hash, $name, $opt, @args) = @_;
	
	return "get $name needs at least one argument" unless (defined($opt));
	return undef;
}

sub vitoconnect_Set($@) {
	my ($hash, $name, $opt, @args) = @_;
	
	return "set $name needs at least one argument" unless (defined($opt));
	if ($opt eq "update"){ vitoconnect_GetUpdate($hash); }
	return undef;
}	
sub vitoconnect_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "formal") {
			if($attr_value !~ /^yes|no$/) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
			    Log 3, "$name: ".$err;
			    return $err;
			}
		} elsif($attr_name eq "disable") {
		
		} elsif($attr_name eq "verbose") {
		
		} else {
		    # return "Unknown attr $attr_name";
		}
	}
	return undef;
}

# Subs
sub vitoconnect_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "$name: GetUpdate called ...";

	vitoconnect_getCode($hash);
	return undef;
}

sub vitoconnect_getCode($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "$authorizeURL?client_id=$client_id&scope=openid&redirect_uri=$callback_uri&response_type=code";  
	my @header = ("Content-Type: application/x-www-form-urlencoded");
	my $isiwebuserid = $hash->{user};
	my $isiwebpasswd = $hash->{passwd};	
	Log3 $name, 3, "$name - getCode went ok";
	Log3 $name, 5, "getCode: $url"; 
        
   my $param = {
		url        => $url,
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded",
		ignoreredirects => 1,
      user		  => $isiwebuserid,
      pwd		  => $isiwebpasswd,
      sslargs    => {SSL_verify_mode => 0},
      method     => "POST",
      callback   => \&vitoconnect_getCodeCallback     
      };
   
   # Log3 $name, 3, Dumper($hash);
   HttpUtils_NonblockingGet($param);
   return undef;
}

sub vitoconnect_getCodeCallback ($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {
   	Log3 $name, 3, "$name - getCodeCallback went ok";
      Log3 $name, 5, "Received response: $response_body";
      $response_body =~ /code=(.*)"/;
      $hash->{code} = $1;
      Log3 $name, 5, "code = $hash->{code}";
      if ($hash->{code}) {
      	$hash->{login} = "ok";
      } else {
      	$hash->{login} = "failure";
      }
   } else {
   	# Error code, type of error, error message
      Log3 $name, 1, "An error happened: $err";
      $hash->{login} = "failure";
   }
	if ($hash->{login} eq "ok") {
		vitoconnect_getAccessToken($hash);
	} else {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "login failure" );
		readingsEndUpdate($hash, 1);
		# neuen Timer starten in einem konfigurierten Interval.
		InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
	}
	return undef;
}

sub vitoconnect_getAccessToken($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $param = {
		url        => $token_url,
		hash       => $hash,
		header     => "Content-Type: application/x-www-form-urlencoded;charset=utf-8",
		data       => "client_id=$client_id&client_secret=$client_secret&code=$hash->{code}&redirect_uri=$callback_uri&grant_type=authorization_code",
      sslargs    => {SSL_verify_mode => 0},
      method     => "POST",      
      callback   => \&vitoconnect_getAccessTokenCallback     
      };
	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getAccessTokenCallback($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {
   	Log3 $name, 3, "$name - getAccessTokenCallback went ok";
      Log3 $name, 5, "Received response: $response_body\n";
      my $decode_json = eval{decode_json($response_body)};
      if($@) {
        Log3 $name, 1, "$name - JSON error while request: $@";
        return;
      }  
      my $access_token = $decode_json->{"access_token"};
      if ($access_token ne "") {
			$hash->{access_token} =  $access_token;          
         Log3 $name, 5, "Access Token: $access_token";
         vitoconnect_getGw($hash);
      } else {
      	Log3 $name, 1, "Access Token: undef";
      	InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
      } 
    } else {
    	Log3 $name, 1, "getAccessToken: An error happened: $err";
      InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
    }
	return undef;
}

sub vitoconnect_getGw($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $access_token = $hash->{access_token};
	my $param = {
		url        => "$apiURLBase$general",
		hash       => $hash,
		header     => "Authorization: Bearer $access_token",
		sslargs    => {SSL_verify_mode => 0},
      callback   => \&vitoconnect_getGwCallback     
      };
	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getGwCallback($) {
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	if ($err eq "") {	
   	Log3 $name, 3, "$name - getGwCallback went ok";
      Log3 $name, 5, "Received response: $response_body\n";
      my $decode_json = eval{decode_json($response_body)};
      if($@) {
        Log3 $name, 1, "$name - JSON error while request: $@";
        return;
      } 
      my $installation = $decode_json->{entities}[0]->{properties}->{id};
      Log3 $name, 5, "installation: $installation";
      $hash->{installation} = $installation;
      $decode_json = eval{decode_json($response_body)};
      if($@) {
        Log3 $name, 1, "$name - JSON error while request: $@";
        return;
      } 
      my $gw = $decode_json->{entities}[0]->{entities}[0]->{properties}->{serial};
      Log3 $name, 5, "gw: $gw";
      $hash->{gw} = $gw;
      vitoconnect_getResource($hash);
   } else {
   	Log3 $name, 1, "An error happened: $err";
      InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
   }	
	return undef;
}

sub vitoconnect_getResource($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $access_token = $hash->{access_token};
	my $installation = $hash->{installation};
	my $gw = $hash->{gw};
	my $param = {
		url        => "https://api.viessmann-platform.io/operational-data/installations/$installation/gateways/$gw/devices/0/features/",
		hash       => $hash,
		header     => "Authorization: Bearer $access_token",
		timeout    => 10,
		sslargs    => {SSL_verify_mode => 0},
      callback   => \&vitoconnect_getResourceCallback     
      };
  	HttpUtils_NonblockingGet($param);
	return undef;
}

sub vitoconnect_getResourceCallback($) { 
	my ($param, $err, $response_body) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	readingsBeginUpdate($hash);
	if ($err eq "") {	
		Log3 $name, 3, "$name - getResourceCallback went ok";
   	Log3 $name, 5, "Received response: $response_body\n";
   	my $decode_json = eval{decode_json($response_body)};
      if($@) {
        Log3 $name, 1, "$name - JSON error while request: $@";
        return;
      } 
      my $items = $decode_json;
		for my $item( @{$items->{entities}} ) {
			my $FieldName = $item->{class}[0];
			Log3 $name, 5, "FieldName $FieldName";
			my %Properties = %{$item->{properties}};
			my @Keys = keys( %Properties );
			for my $Key ( @Keys ) {
				#readingsBulkUpdate($hash, $FieldName.".".$Key, $RequestList{$FieldName.".".$Key});
				my $Reading = $RequestList{$FieldName.".".$Key};
				if ( !defined($Reading) ) { $Reading = $FieldName.".".$Key; }
				Log3 $name, 5, "Property: $FieldName $Key";
				my $Type = $Properties{$Key}{type};
				my $Value = $Properties{$Key}{value};
				if ( $Type eq "string" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "number" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "array" ) {
					my $Array = join(",", @$Value);
					readingsBulkUpdate($hash, $Reading, $Array);
					Log3 $name, 5, "$FieldName".".$Key: $Array ($Type)";
				} elsif ( $Type eq "boolean" ) {
					readingsBulkUpdate($hash, $Reading, $Value);
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				} elsif ( $Type eq "Schedule" ) {
					my %Entries = %$Value;
					my @Days = keys (%Entries);
					my $Result = "";
					for my $Day ( @Days ){
						my $Entry = $Entries{$Day};
						$Result = "$Result $Day";
						for my $Element ( @$Entry ) {
							#$Result = "$Result $Element";
							while(my($k, $v) = each %$Element)  {
								$Result = "$Result $k:$v";
							}
						$Result = "$Result, ";
						}
					}
					readingsBulkUpdate($hash, $Reading, $Result);
					Log3 $name, 5, "$FieldName".".$Key: $Result ($Type)";
				} elsif ( $Type eq "ErrorListChanges" ) {
					# not implemented yet
					readingsBulkUpdate($hash, $Reading, "ErrorListChanges");
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
 				} else {
					readingsBulkUpdate($hash, $Reading, "Unknown: $Type");
					Log3 $name, 5, "$FieldName".".$Key: $Value ($Type)";
				}	
			};
		};
		readingsBulkUpdate($hash, "counter", $hash->{counter} );
		$hash->{counter} = $hash->{counter} + 1;
		readingsBulkUpdate($hash, "state", "ok");             
   }   else {
		# Error code, type of error, error message
		readingsBulkUpdate($hash, "state", "An error happened: $err");
      Log3 $name, 1, "An error happened: $err";
   }
	readingsEndUpdate($hash, 1);
	# neuen Timer starten in einem konfigurierten Interval.
	InternalTimer(gettimeofday()+$hash->{intervall}, "vitoconnect_GetUpdate", $hash);
	return undef;
}

1;

=pod
=item device
=item summary support for Vissmann API
=item summary_DE Unterstützung für die Vissmann API
=begin html

<a name="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implements a device for Vissmann API <a href="https://www.vissmann.de/de/vissmann-apps/vitoconnect.html">Vitoconnect100</a>.
    Based on investigation of <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a>
    
	 You need the user and password from the ViCare App account.  
	 
	 For details see: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (german)</a>

    <br><br>
    <a name="vitoconnectdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code>
        <br><br>
        Example: <code>define vitoconnect vitoconnect user@mail.xx geheim 60</code>
        <br><br>
                
    </ul>
    <br>
    
    <a name="vitoconnectset"></a>
    <b>Set</b><br>
    <ul>
        nothing to set here
    </ul>
    <br>

    <a name="vitoconnectget"></a>
    <b>Get</b><br>
    <ul>
        nothing to get here 
    </ul>
    <br>
    
    <a name="vitoconnectattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command.
        <br><br>
        Attributes:
        <ul>
            <li><i>not implemented yet</i> <br>
                You can use al lot of standard attributes like verbose, userReadings, DBLogInclude ....
            </li>
        </ul>
    </ul>
    
    <a name="vitoconnectreadings"></a>
    <b>Readings</b>
    <br><br>
	 <i>vitoconnect</i> sets one reading for every value delivered by the API (depends on the type and the settings of your heater and the version of the API!).
	 Already known values will be mapped to clear names. Unknown values will added with their JSON path (e.g. "heating.burner.modulation.value").
	 Please report new readings to the module maintainer. A description of the known reading could be found <a href="https://wiki.fhem.de/wiki/Vitoconnect">here (german)</a>	    
    
</ul>

=end html

=cut
=cut
