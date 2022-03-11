#################################################################################################################
# $Id$
# 76_SMAEVCharger.pm author: Jürgen Allmich
#################################################################################################################
#
#  Copyright notice
#
#  Published according Creative Commons : Attribution-NonCommercial-ShareAlike 3.0 Unported (CC BY-NC-SA 3.0)
#  Details: https://creativecommons.org/licenses/by-nc-sa/3.0/
#
#  Credits:
#  - used 73_SMAInverter.pm as template
#  - 
#  - 
#  - 
#  - 
#
#  Description:
#  This is an FHEM-Module for SMA EV Chargers.
#
#################################################################################################################
#
#  	Date			Version		Description
#	22.01.2022		0.0.92		Bugfixes: insert 'use JSON'
#	12.12.2021		0.0.91		Bugfixes: check for undefined parameter in SMAEVCharger_getReadableCode($)
#	14.11.2021		0.0.9		Bugfixes: when setting an incorrect value, the set command was executed anyway. No there is no setting, if value are incorrect
#								Error on setting Laden_mit_Vorgabe while values Param_Energiemenge_Ladevorgang and Param_Dauer_Ladevorgang are set correctly
#								On logon, if there is no body or header now an error will be returned (otherwise some fhem may be killed)
#								Value "Schnellladen" on setting is not possible so it has been deleted from the options for Param_Betriebsart_Ladevorgang
#	05.07.2021		0.0.8		Bugfixing (Warnings of uninitialized values), Added Livedata "Drehschalter"
#	07.02.2021		0.0.7		'Schnellabschaltung' change detail-level to 0, Documentation for the module
#	30.01.2021		0.0.6		Attr setting-level, Setting Readings for advanced and expert, on setting Lademenge set correct end_time
#	24.01.2021		0.0.5		Bug fixing and new Readings Startzeit_Ladung, Anzahl_Ladevorgaenge, 
#								Attr detail-level for config which values the use would like to see (0: basic, 1: advanced, 2: expert)
#	14.01.2021		0.0.4		Set cmd for all charging values
#	11.01.2021		0.0.3		Read Params (not all), Set all values for charging
#	10.01.2021		0.0.2		Read Live Data
#	09.01.2021		0.0.1		Initial Modul
#
#
#################################################################################################################
#
#	Todos
#	Maybe Timesheets for automated charging (Weekplan) would be nice (actual solution with doif)
#	Integration user function for individual SOC Modules (trying first with my kia)
#	Look for better coding
#
#################################################################################################################

package main;

use strict;
use warnings;
eval "use DateTime;1"         or my $MissModulDateTime = "DateTime";
use Time::HiRes qw(gettimeofday tv_interval);
use Blocking;
use Time::Local;
use JSON;


###############################################################
#   SMAEVCharger - help functions and variables
###############################################################

# These readings are updateble
my %update_readings = (
	"Param_Betriebsart_Ladevorgang" 				=> {values => ":Optimiertes_Laden,Laden_mit_Vorgabe,Ladestopp", 	level => 0},
	"Param_Minimaler_Ladestrom" 					=> {values => ":slider,6,1,32", 												level => 0},
	"Param_Dauer_Ladevorgang" 						=> {values => ":time", 															level => 0},
	"Param_Energiemenge_Ladevorgang" 				=> {values => ":slider,1,1,100", 												level => 0},
	#"Param_Ende_Ladevorgang" => {values => "",  will be calculated with Param_Dauer_Ladevorgang but could also be set an Param_Dauer_Ladevorgang will be calculated
	
	#advanced
	"Param_Minimale_Schaltdauer_Relais"				=> {values => ":slider,0,5,600", 												level => 1},
	"Param_Trennung_nach_Vollladung" 				=> {values => ":ja,nein", 														level => 1},
	"Param_Ladebereitschaft_bis_Trennung" 			=> {values => "", 																level => 1},
	"Param_Betrieb_mit_Netzanschlusspunktzaehler" 	=> {values => ":ja,nein", 														level => 1},
	"Param_Nennstrom_Netzanschluss" 				=> {values => ":slider,0,1,100", 												level => 1},
	"Param_Nennwirkleistung_WMaxOut" 				=> {values => ":slider,1380,230,22000", 											level => 1},
	"Param_Nennwirkleistung_WMaxIn" 				=> {values => ":slider,1380,230,22000", 											level => 1},
	"Param_Maximale_Schieflast" 					=> {values => ":slider,0,230,10000", 											level => 1},
	"Param_Fallback_Wirkleistungsbegrenzung" 		=> {values => ":slider,0,230,22000", 											level => 1},
	
	#expert
	"Param_Timeout_nach_Kommunikationsverlust" 		=> {values => ":slider,200,100,60000",											level => 2},
	"Param_IGMP_Query_Intervall" 					=> {values => ":slider,11,10,31744",											level => 2},
	"Param_Auto_Update_an" 							=> {values => ":ja,nein",														level => 2},
	"Param_Geraeteneustart_ausloesen" 				=> {values => ":---,Ausführen",													level => 2},
	"Param_WLAN_suchen" 							=> {values => ":---,Scan-durchführen",											level => 2},
	"Param_WPS_aktivieren" 							=> {values => ":---,WPS-aktivieren",											level => 2},
	"Param_WLAN_eingeschaltet" 						=> {values => ":ja,nein",														level => 2},
	"Param_Verschluesselung_WLAN"  					=> {values => ":WPA2-MIXED,WPA,WPA2",											level => 2},
	"Param_WLAN-Passwort" 							=> {values => "",																level => 2},
	"Param_SSID_WLAN" 								=> {values => "",																level => 2},
	"Param_Soft_Access_Point_an" 					=> {values => ":ja,nein",														level => 2},
	);
	
	
my %reading_codes = (
	"Optimiertes_Laden" => "4719",
	"Laden_mit_Vorgabe" => "4720",
	"Schnellladen" => "4718",
	"Ladestopp" => "4721",
	"ja" => "1129",
	"nein" => "1130",
	"nicht verbunden" => "200111",
	"verbunden" => "200112",
	"Ladevorgang aktiv" => "200113",
	"Phase L1 L2 L3" => "326",
	"---" => "302",
	"Ok" => "307",
	"Ein" => "308",
	"Ausführen" => "1146",
	"Scan-durchführen" => "3342",
	"WPS-aktivieren" => "3321",
	"WPA" => "3323",
	"WPA2" => "3324",
	"WPA2-MIXED" => "3398",
	"intelligente Ladung" => "4950"
	);

###############################################################
#                  SMAEVCharger getReadableCode
###############################################################
sub SMAEVCharger_getReadableCode($)
{
	my ($code) = @_;

	if(defined($code))
	{
		foreach my $key (keys %reading_codes)
		{
			if($reading_codes{$key} eq $code)
			{
				return $key;
			}
		}
	
		return $code;
	}
	else
	{
		return '';
	}
}

###############################################################
#                  SMAEVCharger getReadingCode
###############################################################
sub SMAEVCharger_getReadingCode($)
{
	my ($readable_code) = @_;

	if(defined($reading_codes{$readable_code}))
	{
		return $reading_codes{$readable_code};
	}
	else
	{
		return $readable_code;
	};
}


###############################################################
#                  SMAEVCharger checkPossibleValue
###############################################################
sub SMAEVCharger_checkPossibleValues($$$)
{
	my ($name, $reading,$val) = @_;

	my $return = undef;
	
	Log3 $name, 4, "$name -> Check if values are in range";
	
	if ($reading eq "Param_Betriebsart_Ladevorgang" and $val == 4720 and 
		(ReadingsVal($name,"Param_Dauer_Ladevorgang", "0") == 0 
		or ReadingsVal($name,"Param_Energiemenge_Ladevorgang", "0") == 0
		or ReadingsVal($name,"Status_Ladevorgang", "nicht verbunden") eq 'nicht verbunden'))
	{
		if(ReadingsVal($name,"Status_Ladevorgang", "nicht verbunden") eq 'nicht verbunden')
		{
			$return = "Car is not connected to the charger";
		}
		else
		{
			$return = "Please first set values Param_Energiemenge_Ladevorgang and Param_Dauer_Ladevorgang";
		}
	}
	elsif ((my $min = ReadingsVal($name,".".$reading."_min", "ERR")) ne "ERR")
	{
		Log3 $name, 4, "$name -> Check for min / max:".$reading.":".$val." min=".$min;
		
		if ($val >= $min and $val <= ReadingsVal($name,".".$reading."_max", 0))
		{
			$return = undef;
		}
		else
		{
			$return = "Value not allowed! Possible Values must be between: ".$min." and ".ReadingsVal($name,".".$reading."_max", 0);
		}
	}
	elsif ((my $possibleValues = ReadingsVal($name,".".$reading."_possibleValues", "ERR")) ne "ERR")
	{
		#Log3 $name, 4, "$name -> Check for array for ".$reading.":".$val;
		$return = "Value not allowed! Possible Values: ".$possibleValues;
		#Log3 $name, 4, "$name -> Check for array possible values:".$possibleValues;
		
		my @possibleValues = split('; ',$possibleValues);
		
		foreach my $tmp (@possibleValues){
			$return = undef if ($val == $tmp);
		}
	}
	
	return $return;
}


###############################################################
#                  SMAEVCharger getCurlcmd
###############################################################
sub SMAEVCharger_getCurlcmd($$;$)
{
	# get the curlcmd infos for the api call
	my ($hash, $api, $data) = @_;
	
	# get all basic infos for the curl command
	my $baseurl = $hash->{HELPER}{BASEURL};
	my $curlcmd = "";
	my $url = "";
	my $special_header = "";
	my $cmd_call = "curl -i -s -k -X ";
	my $method = "'POST' ";
	my $header = "-H 'Host: $hash->{HOST}' -H 'Connection: close' -H 'Accept: application/json, text/plain, */*' -H 'User-Agent: okhttp/3.10.0' -H 'Sec-Fetch-Site: same-origin' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Dest: empty' -H 'Accept-Encoding: gzip, deflate' -H 'Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7' ";
	my $cookies = "-b '$hash->{HELPER}{SESSIONID}' ";
	my $token = "-H 'Authorization: Bearer $hash->{HELPER}{ACCESS_TOKEN}' " if (defined($hash->{HELPER}{ACCESS_TOKEN}));
	my $len_corr = 0; # maybe there are chars in data which should not be count for header content_len

	Log3 $hash->{NAME}, 5, "$hash->{NAME} -> SMAEVCgarger_getCurlcmd";
	
	#correct string len with count of masking char \
	if (defined ($data))
	{
		$len_corr = () = $data =~ /\\/g;
	}
	
	# check wich command we have to build
	if ($api eq "login")
	{
		$url = $baseurl."/api/v1/token";
		my $content_len = length($data) - $len_corr;
		$data = "--data-binary '$data' ";
		$special_header = "-H 'Content-Type: application/x-www-form-urlencoded;charset=UTF-8' -H 'Content-Length: $content_len' -H 'Origin: $baseurl' -H 'Referer: $baseurl/webui/login' ";
		$cookies = "";
		$token = "";
	}
	elsif ($api eq "refresh_token")
	{
		my $refresh_token = $hash->{HELPER}{REFRESH_TOKEN};
		$url = $baseurl."/api/v1/token";
		$data = "grant_type=refresh_token&refresh_token=$refresh_token ";
		my $content_len = length($data);
		$data = " --data-binary '$data' ";
		$special_header = "-H 'Content-Type: application/x-www-form-urlencoded;charset=UTF-8' -H 'Content-Length: $content_len' -H 'Origin: $baseurl' -H 'Referer: $baseurl/webui/login' ";
	}
	elsif ($api eq "livedata")
	{
		$url = $baseurl.'/api/v1/measurements/live/';
		$data = '[{"componentId":"IGULD:SELF"}]'; # cmd to get live data from wallbox
		my $content_len = length($data);
		$data = "--data-binary '$data' ";
		$special_header = "-H 'Content-Type: application/x-www-form-urlencoded;charset=UTF-8' -H 'Content-Length: $content_len' -H 'Referer: $baseurl/webui/login' ";
	}
	elsif ($api eq "read_params")
	{
		$url = $baseurl.'/api/v1/parameters/search/';
		my $content_len = length($data) - $len_corr;
		$data = "--data-binary '$data' ";
		$special_header = "-H 'Content-Type: application/json' -H 'Content-Length: $content_len' -H 'Referer: $baseurl/webui/Plant:1,IGULD:SELF/configuration/view-parameters' ";
	}
	elsif ($api eq "write_params")
	{
		$url = $baseurl.'/api/v1/parameters/IGULD:SELF';
		my $content_len = length($data);
		$data = "--data-binary '$data' ";
		$special_header = "-H 'Content-Type: application/json' -H 'Content-Length: $content_len' -H 'Referer: $baseurl/webui/Plant:1,IGULD:SELF/configuration/view-parameters' ";
		$method = "'PUT' ";
		
		#my $curlcmd = "curl -i -s -k -X 'PUT' -H 'Host: $host' -H 'Connection: close' -H 'Content-Length: $content_len' -H 'Accept: application/json, text/plain, */*' -H 'Authorization: Bearer $access_token' -H 'User-Agent: okhttp/3.10.0' -H 'Content-Type: application/json' -H 'Origin: $baseurl' -H 'Sec-Fetch-Site: same-origin' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Dest: empty' -H 'Referer: $baseurl/webui/Plant:1,IGULD:SELF/configuration/view-parameters' -H 'Accept-Encoding: gzip, deflate' -H 'Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7' -b 'JSESSIONID=$cookies' --data-binary '$data' '$baseurl/api/v1/parameters/IGULD:SELF'";
	}
	elsif ($api eq "easyget")
	{
		$url = $baseurl.'/api/v1/plants/Plant:1';
		$special_header = "-H 'Referer: $baseurl/webui/Plant:1/dashboard' ";
		$method = "'GET' ";
		$data = " ";
	}
	else
	{
		$cmd_call = "";
	}
	
	if ($cmd_call ne "")
	{
		$curlcmd = $cmd_call.$method.$header.$special_header.$token.$cookies.$data.$url;
	}
	else
	{
		$curlcmd = "";
	}
	
	return $curlcmd;
}


###############################################################
#                  SMAEVCharger Initialize
###############################################################
sub SMAEVCharger_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}     = "SMAEVCharger_Define";
	$hash->{UndefFn}   = "SMAEVCharger_Undef";
	$hash->{GetFn}     = "SMAEVCharger_Get";
	$hash->{SetFn}     = "SMAEVCharger_Set";
	$hash->{AttrList}  = "interval " .
						"disable:1,0 " .
						"detail-level:0,1,2 " .
						"setting-level:0,1,2 " .
						$readingFnAttributes; 
	$hash->{AttrFn}    = "SMAEVCharger_Attr";

	return;
}

###############################################################
#                  SMAEVCharger Define
###############################################################
sub SMAEVCharger_Define($$) 
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	return "Error: Perl module ".$MissModulDateTime." is missing.
        Install it on Debian with: sudo apt-get install libdatetime-perl" if($MissModulDateTime);

	return "Wrong syntax: use define <name> SMAEVCharger <inv-hostname/inv-ip> <inv-username> <inv-userpwd> " if ((int(@a) < 5) and (int(@a) > 6));

	my $name                       	= $hash->{NAME};
	$hash->{LASTUPDATE}            	= 0;
	$hash->{INTERVAL}              	= $hash->{HELPER}{INTERVAL} = AttrVal($name, "interval", 60);
	$hash->{HELPER}{SESSIONID} 		= "";
	$hash->{HELPER}{ACCESS_TOKEN} 	= "";
	$hash->{HELPER}{REFRESH_TOKEN} 	= "";
	$hash->{HELPER}{EXPIRE_TOKEN} 	= 0;
	
	my ($Host);
	 
	my $User = $a[3];
	my $Pass = $a[4];      #todo evtl. verschlüsseln und mit set befehl änderbar machen?

	# extract IP or Hostname from $a[4]
	if (!defined $Host) 
	{
		#if ( $a[2] =~ /^([A-Za-z0-9_.])/ ) 
		# Test if IP
		if ($a[2] =~ /^([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])$/)
		{
			 $Host = $a[2];
			 
			 # extract protocol if in definition
			 my ($protocoll, $ip) = $Host =~m/(https:\/\/)(.*)/;
			 if($protocoll){ $Host = $ip; };
			 
			 $hash->{HELPER}{BASEURL} = "https://".$Host;
		}
	} 
	 
	if (!defined $Host) 
	{
		return "Argument:{$a[2]} not accepted as Host or IP. Read device specific help file.";
	}

	$hash->{USER} = $User;
	$hash->{PASS} = $Pass;
	$hash->{HOST} = $Host;

	InternalTimer(gettimeofday()+5, "SMAEVCharger_GetData", $hash, 0);      # Start Hauptroutine

	return undef;
}

###############################################################
#                  SMAEVCharger Undefine
###############################################################
sub SMAEVCharger_Undef($$) 
{
	my ($hash, $name) = @_;
	RemoveInternalTimer($hash);
	BlockingKill($hash->{HELPER}{RUNNING_PID});
	return undef;
}

###############################################################
#                  SMAEVCharger Get
###############################################################
sub SMAEVCharger_Get($$) 
{
	my ($hash, @a) = @_;
	return "\"get X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt  = shift @a;
 
	my  $getlist = "Unknown argument $opt, choose one of ".
                "data:noArg ";

	return "module is disabled" if(IsDisabled($name));

	if ($opt eq "data") 
	{
		SMAEVCharger_GetData($hash);
	} 
	else 
	{
		return "$getlist";
	}
	return undef;
}

###############################################################
#                  SMAEVCharger Set
###############################################################

sub SMAEVCharger_Set($$@) 
{
	my ($hash, $name, $cmd, $val) = @_;
	return "\"set $name\" needs at least one argument" unless(defined($cmd));
	my $resultStr = "";
	my @cList;
	my $setting_level = AttrVal($name, "setting-level", 0);

	push(@cList, " "); 
	
	foreach my $key (keys(%update_readings))
	{
		if( $update_readings{$key}{level} <= $setting_level )
		{
			push(@cList, $key.$update_readings{$key}{values});
		}
	}
	
	my $return = "Unknown argument $cmd, choose one of " . join(" ", @cList);
   
	return $return if $cmd eq '?';
   
	if(join(" ", @cList) =~ m/$cmd/) 
	{
		Log3 $name, 5, "$name - Set command exists:".$cmd;
		
		$return = SMAEVCharger_SMAcmd($hash, $cmd, $val);
	}
		   
	return $return;	
}


###############################################################
#                  SMAEVCharger Attr
###############################################################
sub SMAEVCharger_Attr(@) 
{
	my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash = $defs{$name};
    my $do;

	if ($aName eq "disable") 
	{
        if($cmd eq "set") 
		{
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val   = ($do == 1 ?  "disabled" : "initialized");

        readingsSingleUpdate($hash, "state", $val, 1);

        if ($do == 0) 
		{
            RemoveInternalTimer($hash);
            InternalTimer(time+5, 'SMAEVCharger_GetData', $hash, 0);
        } 
		else 
		{
            RemoveInternalTimer($hash);
        }
    }
	
	if ($aName eq "detail-level") {
		if ($cmd eq "set" and AttrVal($name,"setting-level", 0) > $aVal)
		{
			
			return "ERROR: first set setting-level because detail-level must be >= setting-level";
		}
		else
		{
			delete $defs{$name}{READINGS};
			RemoveInternalTimer($hash);
            InternalTimer(time+5, 'SMAEVCharger_GetData', $hash, 0);
		}
    }
	
	if ($aName eq "setting-level") {
        
		if ($cmd eq "set" and AttrVal($name,"detail-level", 0) < $aVal)
		{
			return "ERROR: for higher setting-level attribute detail-level must have same or higher level";
		}
		else
		{
			delete $defs{$name}{READINGS};
			RemoveInternalTimer($hash);
            InternalTimer(time+5, 'SMAEVCharger_GetData', $hash, 0);
		}
    }


    if ($aName eq "interval") 
	{
        if ($cmd eq "set") 
		{
            $hash->{HELPER}{INTERVAL} = $aVal;
			$hash->{INTERVAL} = $aVal;
            Log3 $name, 3, "$name - Set $aName to $aVal";
        } else 
		{
            $hash->{INTERVAL} = $hash->{HELPER}{INTERVAL} = 60;
        }
    }

	
	return;
}

###############################################################
#                  Main Loop - Get Data from EV Charger
###############################################################
sub SMAEVCharger_GetData($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $interval = AttrVal($name, "interval", 60);
	 
	RemoveInternalTimer($hash, "SMAEVCharger_GetData");

	if ($init_done != 1) 
	{
		InternalTimer(gettimeofday()+5, "SMAEVCharger_GetData", $hash, 0);
		return;
	}

	return if(IsDisabled($name));
	 
	if (exists($hash->{HELPER}{RUNNING_PID})) 
	{
		Log3 ($name, 4, "SMAEVCharger $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
		BlockingKill($hash->{HELPER}{RUNNING_PID});
	}

	Log3 ($name, 3, "$name - ##########  SMAEVCharger get all data  ##########");

	# do operation
	InternalTimer(gettimeofday()+$interval, "SMAEVCharger_GetData", $hash, 0);

	$hash->{HELPER}{RUNNING_PID} = BlockingCall("SMAEVCharger_Run", "$name", "SMAEVCharger_Done", 60, "SMAEVCharger_Aborted", $hash);
	$hash->{HELPER}{RUNNING_PID}{loglevel} = 4;

	return;
}

###############################################################
#          non-blocking EVCharger data transfer
###############################################################
sub SMAEVCharger_Run($) 
{
	my ($name)   = @_;
	my $hash     = $defs{$name};
	my $interval = AttrVal($name, "interval", 60);
	my $response = "";
	my $code = 0;
	my $ret = 0;

	Log3 ($name, 4, "$name -> Start BlockingCall SMAEVCharger_Run");

	# login to EV Charger
	if(SMAEVCharger_SMAlogon($hash->{HOST}, $hash->{PASS},$hash->{USER}, $hash))
	{
		Log3 $name, 4, "$name - login succes / start getting live data";
		
		my $baseurl = $hash->{HELPER}{BASEURL};
		my $host = $hash->{HOST};
		my $cookies = $hash->{HELPER}{SESSIONID};
		my $access_token = $hash->{HELPER}{ACCESS_TOKEN};
		my $url = $baseurl.'/api/v1/measurements/live/';
		my $data = '\'[{"componentId":"IGULD:SELF"}]\''; # cmd to get live data from wallbox
		
		my $curlcmd = SMAEVCharger_getCurlcmd($hash, "livedata");
		Log3 $name, 5, "$name - Curl cmd livedata: ".$curlcmd;

		$response = `$curlcmd`;
		my ($head,$body) = split( m{\r?\n\r?\n}, $response,2 );
		($code) = $head =~m{\A\S+ (\d+)};
			
		if($code == 200) # all ok for live data
		{
			Log3 $name, 5, "$name - Actual Live Data: ".$body;
			$response = $body;
			$ret = 1;
			
			#if live data is ok we should also get param data
			
			$url = $baseurl.'/api/v1/parameters/search/';
			$data = '{"queryItems":[{"componentId":"IGULD:SELF"}]}'; # cmd to get params
			$access_token = $hash->{HELPER}{ACCESS_TOKEN};
			
			$curlcmd = SMAEVCharger_getCurlcmd($hash, "read_params", $data);
				
			Log3 $name, 5, "$name - Curl cmd to read param: ".$curlcmd;

			my $response_param = `$curlcmd`;
			my ($head,$body) = split( m{\r?\n\r?\n}, $response_param,2 );
			($code) = $head =~m{\A\S+ (\d+)};
			
			if($code == 200) # all ok for param data
			{
				Log3 $name, 5, "$name - Parameter: ".$body;
				$response = $response.'|'.$body;
			}
			else
			{
				Log3 $name, 3, "$name - Parameter Error: ".$code;
				$response = $response.'|[{"componentId":"ERR"}]';
				
				Log3 $name, 5, "$name Response in Error: ".$response;
			}
		}
		else
		{
			#todo err handling
			Log3 $name, 3, "$name - Actual Live Data Error: ".$code;
			$response = "Error: Get Data with code:".$code;
			$ret = 0;
		}
	}
	else 
	{
		Log3 $name, 3, "$name - Login failed";
		$response = "Error: Login with code:".$code;
		$ret = 0;
	}

	# all data received
	#SMAEVCharger_SMAlogout($hash,$hash->{HOST});
	
	# store session info for blocking call parent
	my $session_info = encode_base64($hash->{HELPER}{SESSIONID}."|".$hash->{HELPER}{ACCESS_TOKEN}."|".$hash->{HELPER}{REFRESH_TOKEN}."|".$hash->{HELPER}{EXPIRE_TOKEN},"");
	 
	$response = encode_base64($response,"");

	Log3 ($name, 4, "$name -> BlockingCall SMAEVCharger_Run finished");
	  
	return "$name|$ret|$session_info|$response";
}

###############################################################
# 	Helper to change readings into user readable names 
###############################################################
sub SMAEVCharger_handledata($$$)
{
	my ($hash, $data, $param) = @_;
	my $name = $hash->{NAME};
	
	# Get the current detail-level attribute
     my $detail_level  = AttrVal($name, "detail-level", 0);
	
	my 	$livedata->{"Measurement.ChaSess.WhIn"} = "Energie_Ladevorgang"; 							# in Wh
		$livedata->{"Measurement.Chrg.ModSw"} = "Schalterstellung_Drehschalter";
		$livedata->{"Measurement.GridMs.A.phsA"} = "Netzstrom_Phase_L1";
		$livedata->{"Measurement.GridMs.A.phsB"} = "Netzstrom_Phase_L2";
		$livedata->{"Measurement.GridMs.A.phsC"} = "Netzstrom_Phase_L3";
		$livedata->{"Measurement.GridMs.PhV.phsA"} = "Netzspannung_Phase_L1";
		$livedata->{"Measurement.GridMs.PhV.phsB"} = "Netzspannung_Phase_L2";
		$livedata->{"Measurement.GridMs.PhV.phsC"} = "Netzspannung_Phase_L3";
		$livedata->{"Measurement.Metering.GridMs.TotWIn"} = "Leistung_Bezug"; 						# in W
		$livedata->{"Measurement.Metering.GridMs.TotWIn.ChaSta"} = "Leistung_Ladestation"; 			# in W
		$livedata->{"Measurement.Metering.GridMs.TotWhIn"} = "Zaehlerstand_Bezugszaehler"; 			# in Wh 
		$livedata->{"Measurement.Metering.GridMs.TotWhIn.ChaSta"} = "Zaehlerstand_Ladestation"; 	#in Wh
		$livedata->{"Measurement.Operation.EVeh.ChaStt"} = "Status_Ladevorgang"; 					# 200111 -> nicht verbunden, 200112 -> verbunden 200113 -> wird geladen
		$livedata->{"Measurement.Operation.EVeh.Health"} = "Status_verbundenes_Fahrzeug"; 			# 307 -> "Ok"
		$livedata->{"Measurement.Operation.Evt.Msg"} = "Status_Meldung"; 							# 302 -> "ok" ?
		$livedata->{"Measurement.Operation.Health"} = "Status_Zustand"; 							# 307 -> "Ok"
		$livedata->{"Setpoint.PlantControl.Inverter.FstStop"} = "Schnellabschaltung"; 				# 1467 -> "Start"
		
	# advanced infos
	if ($detail_level > 0)
	{
		$livedata->{"Measurement.GridMs.Hz"} = "Netzfrequenz";
		$livedata->{"Measurement.GridMs.TotPF"} = "Verschiebungsfaktor";
		$livedata->{"Measurement.GridMs.TotVA"} = "Scheinleistung";
		$livedata->{"Measurement.GridMs.TotVAr"} = "Blindleistung";
		$livedata->{"Measurement.Wl.AcqStt"} = "Status_WLAN_Scan";
		$livedata->{"Measurement.Wl.ConnStt"} = "Status_WLAN_Verbindung"; 							# 1725 -> keine Verbindung
		$livedata->{"Measurement.Wl.SigPwr"} = "Signalstaerke_Netzwerk"; 
	}
	
	# expert infos
	if ($detail_level > 1)
	{
		$livedata->{"Measurement.InOut.GI1"} = "digitaler_Gruppeneingang";
		$livedata->{"Measurement.Operation.WMaxLimSrc"} = "Digitaler_Eingang"; 						# eigentlich uninteressant
		$livedata->{"Measurement.Wl.SoftAcsConnStt"} = "Status_Soft_Access_Point"; 					# 308 -> "Ein"
	}
	
	my $readings = {	"Measurement.ChaSess.WhIn" => "Energie_Ladevorgang", # in Wh
					"Measurement.GridMs.A.phsA" => "Netzstrom_Phase_L1",
					"Measurement.GridMs.A.phsB" => "Netzstrom_Phase_L2",
					"Measurement.GridMs.A.phsC" => "Netzstrom_Phase_L3",
   					"Measurement.GridMs.Hz" => "Netzfrequenz",
					"Measurement.GridMs.PhV.phsA" => "Netzspannung_Phase_L1",
					"Measurement.GridMs.PhV.phsB" => "Netzspannung_Phase_L2",
					"Measurement.GridMs.PhV.phsC" => "Netzspannung_Phase_L3",
					"Measurement.GridMs.TotPF" => "Verschiebungsfaktor",
					"Measurement.GridMs.TotVA" => "Scheinleistung",
					"Measurement.GridMs.TotVAr" => "Blindleistung",
   					"Measurement.InOut.GI1" => "digitaler_Gruppeneingang",
					"Measurement.Metering.GridMs.TotWIn" => "Leistung_Bezug", # in W
					"Measurement.Metering.GridMs.TotWIn.ChaSta" => "Leistung_Ladestation", # in W
					"Measurement.Metering.GridMs.TotWhIn" => "Zaehlerstand_Bezugszaehler", # in Wh 
					"Measurement.Metering.GridMs.TotWhIn.ChaSta" => "Zaehlerstand_Ladestation", #in Wh
					"Measurement.Operation.EVeh.ChaStt" => "Status_Ladevorgang", # 200111 -> nicht verbunden, 200112 -> verbunden 200113 -> wird geladen
					"Measurement.Operation.EVeh.Health" => "Status_verbundenes_Fahrzeug", # 307 -> "Ok"
					"Measurement.Operation.Evt.Msg" => "Status_Meldung", # 302 -> "ok" ?
					"Measurement.Operation.Health" => "Status_Zustand", # 307 -> "Ok"
					"Measurement.Operation.WMaxLimSrc" => "Digitaler_Eingang", # eigentlich uninteressant
					"Measurement.Wl.AcqStt" => "Status_WLAN_Scan",
					"Measurement.Wl.ConnStt" => "Status_WLAN_Verbindung", # 1725 -> keine Verbindung
					"Measurement.Wl.SigPwr" => "Signalstaerke_Netzwerk", 
					"Measurement.Wl.SoftAcsConnStt" => "Status_Soft_Access_Point", # 308 -> "Ein"
					"Setpoint.PlantControl.Inverter.FstStop" => "Schnellabschaltung" # 1467 -> "Start"
				};
				
	# basic params
	my 	$params->{"Parameter.Chrg.ActChaMod"} = "Param_Betriebsart_Ladevorgang";
		$params->{"Parameter.Chrg.AMinCha"} = "Param_Minimaler_Ladestrom";
		$params->{"Parameter.Chrg.Plan.DurTmm"} = "Param_Dauer_Ladevorgang";
		$params->{"Parameter.Chrg.Plan.En"} = "Param_Energiemenge_Ladevorgang";
		$params->{"Parameter.Chrg.Plan.StopTm"} = "Param_Ende_Ladevorgang";
		$params->{"Parameter.Chrg.StpWhenFl"} = "Param_Trennung_nach_Vollladung";
		$params->{"Parameter.Chrg.StpWhenFlTm"} = "Param_Ladebereitschaft_bis_Trennung";
		$params->{"Parameter.GridGuard.Cntry.VRtg"} = "Param_Netz_Nennspannung";
		$params->{"Parameter.PCC.ARtg"} = "Param_Nennstrom_Netzanschluss";
		$params->{"Parameter.PCC.FlbInv.WMax"} = "Param_Fallback_Wirkleistungsbegrenzung";
		
		

		
	# advanced params
	if ($detail_level > 0)
	{
		$params->{"Parameter.Chrg.MinSwTms"} = "Param_Minimale_Schaltdauer_Relais";
		$params->{"Parameter.Chrg.UseEnergyMeter"} = "Param_Betrieb_mit_Netzanschlusspunktzaehler";
		$params->{"Parameter.Inverter.WMax"} = "Param_Nennwirkleistung_WMaxOut";
		$params->{"Parameter.Inverter.WMaxIn"} = "Param_Nennwirkleistung_WMaxIn";
		$params->{"Parameter.Inverter.WMaxInRtg"} = "Param_Bemessungswirkleistung_WMaxInRtg";
		$params->{"Parameter.Nameplate.ARtg"} = "Param_Nennstrom_alle_Phasen";
		$params->{"Parameter.Nameplate.Location"} = "Param_Geraetename";
		$params->{"Parameter.PCC.WMaxAsym"} = "Param_Maximale_Schieflast";
		
	}
	
	# expert params
	if ($detail_level > 1)
	{
		$params->{"Parameter.Spdwr.IgmpQryTms"} = "Param_IGMP_Query_Intervall";
		$params->{"Parameter.Spdwr.IgmpQryTx"} = "Param_IGMP_Anfragen_senden";
		$params->{"Parameter.Upd.AutoUpdIsOn"} = "Param_Auto_Update_an";
		$params->{"Parameter.DevUpd.IsOn"} = "Param_Geraete_Update_ein";
		$params->{"Parameter.Inverter.OutPhs"} = "Param_Phasenzuordnung";
		$params->{"Parameter.Nameplate.ChrgCtrl.ChrgTypTxt"} = "Param_Typ_Ladecontroller";
		$params->{"Parameter.Nameplate.ChrgCtrl.SerNumTxt"} = "Param_Seriennummer_Ladecontrollers";
		$params->{"Parameter.Nameplate.ChrgCtrl.SusyId"} = "Param_SusyID_Ladecontrollers";
		$params->{"Parameter.Nameplate.ChrgCtrl.SwRevTxt"} = "Param_SWVersion_Ladecontroller";
		$params->{"Parameter.Nameplate.CmpMain.HwRev"} = "Param_HWVersion_Hauptprozessor";
		$params->{"Parameter.Nameplate.CmpMain.Rev"} = "Param_Umbaustand_Hauptprozessor";
		$params->{"Parameter.Nameplate.CmpMain.SerNum"} = "Param_Seriennummer_Hauptprozessor";
		$params->{"Parameter.Nameplate.CmpMain.SusyId"} = "Param_SUSyID_Hauptprozessor";
		$params->{"Parameter.Nameplate.CmpOS.SwRev"} = "Param_Firmware_Version_Betriebssystem";
		$params->{"Parameter.Nameplate.MacId"} = "Param_MAC-Adresse";
		$params->{"Parameter.Nameplate.MainModel"} = "Param_Geraeteklasse";
		$params->{"Parameter.Nameplate.Model"} = "Param_Geraetetyp";
		$params->{"Parameter.Nameplate.ModelStr"} = "Param_Typenbezeichnung";
		$params->{"Parameter.Nameplate.PkgRev"} = "Param_Softwarepaket";
		$params->{"Parameter.Nameplate.SerNum"} = "Param_Seriennummer";
		$params->{"Parameter.Nameplate.Vendor"} = "Param_Hersteller";
		$params->{"Parameter.Nameplate.WlMacId"} = "Param_WLAN_MAC";
		$params->{"Parameter.Operation.ComTmOut"} = "Param_Timeout_nach_Kommunikationsverlust";
		$params->{"Parameter.Spdwr.ActlDnsSrvIp"} = "Param_Akt_Speedwire_Serveradresse";
		$params->{"Parameter.Spdwr.ActlGwIp"} = "Param_Akt_Speedwire_Gateway";
		$params->{"Parameter.Spdwr.ActlIp"} = "Param_Akt_Speedwire_IP";
		$params->{"Parameter.Spdwr.ActlSnetMsk"} = "Param_Akt_Speedwire_Subnetzmaske";
		$params->{"Parameter.Spdwr.AutoCfgIsOn"} = "Automatische_Speedwire-Konfig_an";
		$params->{"Parameter.SwCmp.CmpEnnexOS.Frwk.SwRev"} = "Param_ennexOS_Framework_Version";
		$params->{"Parameter.Sys.DevRstr"} = "Param_Geraeteneustart_ausloesen";
		$params->{"Parameter.Upd.AvalChkIstl"} = "Param_Auto_Speedwire_Konfig_an";
		$params->{"Parameter.Wl.ActlDnsSrvIp"} = "Aktuelle_Speedwire-DNS-Serveradresse";
		$params->{"Parameter.Wl.ActlGwIp"} = "Param_IP_Gateway_WLAN";
		$params->{"Parameter.Wl.ActlIp"} = "Param_IP_WLAN";
		$params->{"Parameter.Wl.ActlSnetMsk"} = "Param_IP_Subnetz_WLAN";
		$params->{"Parameter.Wl.AutoCfgIsOn"} = "Param_Auto_Update_an";
		$params->{"Parameter.Wl.DoAcq"} = "Param_WLAN_suchen";
		$params->{"Parameter.Wl.DoWPS"} = "Param_WPS_aktivieren";
		$params->{"Parameter.Wl.ExsNetw[]"} = "Param_Gefundenes_WLAN";
		$params->{"Parameter.Wl.IsOn"} = "Param_WLAN_eingeschaltet";
		$params->{"Parameter.Wl.Sec.Cry"} = "Param_Verschluesselung_WLAN";
		$params->{"Parameter.Wl.Sec.Psk"} = "Param_WLAN-Passwort";
		$params->{"Parameter.Wl.Sec.Ssid"} = "Param_SSID_WLAN";
		$params->{"Parameter.Wl.SoftAcsIsOn"} = "Param_Soft_Access_Point_an";
	}
	
				
	# Update Live Data Readings
	my $json = decode_json( $data );
   
	foreach my $item ( @$json )
	{
		my $val = SMAEVCharger_getReadableCode($item->{"values"}->[0]->{"value"});
		
		#old readingsBulkUpdate($hash, $readings->{$item->{"channelId"}} , $val);
		readingsBulkUpdate($hash, $livedata->{$item->{"channelId"}} , $val);
		
		if(defined($livedata->{$item->{"channelId"}}))
		{
			Log3 $name, 5, "$name - Livedata:".$item->{"channelId"}." Reading:".$livedata->{$item->{"channelId"}}." Wert:".$val;
		}
	  
		#Log3 $name, 5, "$name - Readings Update:".$item->{"channelId"}." Reading:".$readings->{$item->{"channelId"}}." Wert:".$val;
	}
	
	Log3 $name, 4, "$name - Loop Readings update done";
   
	# Update Param Readings
	$json = decode_json( $param );
   
	# only if param is from the charger
	if ($json->[0]->{"componentId"} eq "IGULD:SELF")
	{
		$json = $json->[0]->{values};

		foreach my $item ( @$json )
		{
			if(defined($item->{"channelId"}))
			{
				#read possible values:
				if(defined($item->{"min"}))
				{
					# save as non visible reading
					Log3 $name, 4, "$name - Readings Update possible Values: min=".$item->{"min"}." max=".$item->{"max"};
					if(defined($params->{$item->{"channelId"}}))
					{
						readingsBulkUpdate($hash, ".".$params->{$item->{"channelId"}}."_min" , $item->{"min"});
						readingsBulkUpdate($hash, ".".$params->{$item->{"channelId"}}."_max" , $item->{"max"});
					}
				}
				
				if(defined($item->{"possibleValues"}))
				{
					# save as non visible reading
					
					Log3 $name, 4, "$name - Readings Update possible Values:".join("; ",@{$item->{"possibleValues"}});
					if(defined($params->{$item->{"channelId"}}))
					{
						readingsBulkUpdate($hash, ".".$params->{$item->{"channelId"}}."_possibleValues" , join("; ",@{$item->{"possibleValues"}}));
					}
				}
			
				if ($item->{"channelId"} eq "Parameter.Chrg.Plan.StopTm")
				{
					my $time = FmtDateTime($item->{"value"});
					readingsBulkUpdate($hash, $params->{$item->{"channelId"}} , $time);
				}
				else
				{
					my $val = SMAEVCharger_getReadableCode($item->{"value"});
					readingsBulkUpdate($hash, $params->{$item->{"channelId"}} , $val);
				}
				
				if(defined($params->{$item->{"channelId"}}))
				{
					Log3 $name, 5, "$name - Readings Update:".$item->{"channelId"}.' Reading:'.$params->{$item->{"channelId"}}.' Wert:'.$item->{"value"};
				}
			}
		}
		
		Log3 $name, 4, "$name - Loop Params update done";
		
		#calculate additional readings
		SMAEVCharger_CalculateReadings($hash);
	}
   
   return;
}


###############################################################
#   Calculate Specials Readings which are not in Charger
###############################################################
sub SMAEVCharger_CalculateReadings ($) 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	
	# Remember last plugin time
	if($hash->{HELPER}{Status_Ladevorgang} eq "nicht verbunden" and ReadingsVal($name, "Status_Ladevorgang", "nicht verbunden") ne "nicht verbunden")
	{
		readingsBulkUpdate($hash, "Startzeit_Verbindung" , TimeNow());
		readingsBulkUpdate($hash, "Anzahl_Ladevorgaenge" , 0);
	}	
	elsif(ReadingsVal($name, "Status_Ladevorgang", "nicht verbunden") eq "nicht verbunden")
	{
		readingsBulkUpdate($hash, "Startzeit_Verbindung" , "nicht verbunden");
	}
	
	# count charges since last plugin time, will be shown until next plugin
	if($hash->{HELPER}{Status_Ladevorgang} eq "verbunden" and ReadingsVal($name, "Status_Ladevorgang", "") eq "Ladevorgang aktiv")
	{
		readingsBulkUpdate($hash, "Anzahl_Ladevorgaenge" , ReadingsNum($name, "Anzahl_Ladevorgaenge", "") + 1);
	}
}


###############################################################
#         Auswertung non-blocking Charger Datenabruf
###############################################################
sub SMAEVCharger_Done ($) 
{
	my ($string) = @_;
	return unless defined $string; 
	
	my ($name, $success, $session_info, $data) = split("\\|", $string);
	my $hash     = $defs{$name};

	Log3 ($name, 4, "$name -> Start BlockingCall SMAEVCharger_Done");
	
	#save the actual session infos
	$session_info = decode_base64($session_info);
	($hash->{HELPER}{SESSIONID}, $hash->{HELPER}{ACCESS_TOKEN}, $hash->{HELPER}{REFRESH_TOKEN},$hash->{HELPER}{EXPIRE_TOKEN}) = split("\\|", $session_info);
	
	#remember old values for calculating extra readings
	$hash->{HELPER}{Status_Ladevorgang} = ReadingsVal($name, "Status_Ladevorgang", "nicht verbunden");
	
	
	
	readingsBeginUpdate($hash);

	if ($success == 1)
	{
		$data = decode_base64($data);
		my ($livedata, $param) = split("\\|", $data);
		
		# Get current time
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
		$hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
		
		#$livedata = decode_base64($livedata);
		Log3 ($name, 5, "$name -> livedata after decoding:".$livedata);
		
		#$param = decode_base64($param);
		Log3 ($name, 5, "$name -> param after decoding:".$param);
		
		SMAEVCharger_handledata($hash, $livedata, $param);
		readingsBulkUpdate($hash, "state", "Data retrieved");
	}
	else
	{
		readingsBulkUpdate($hash, "state", "Error retrieving data");
		Log3 ($name, 3, "$name - Error retrieving data");
	}
	 
	readingsEndUpdate( $hash, 1 );
	 
	delete($hash->{HELPER}{RUNNING_PID});
	Log3 ($name, 4, "$name -> BlockingCall SMAEVCharger_Done finished");

	return;
}

###############################################################
#           Abbruchroutine Timeout Charger Abfrage
###############################################################
sub SMAEVCharger_Aborted(@) 
{
	my ($hash,$cause) = @_;
	my $name      = $hash->{NAME};
	$cause = $cause?$cause:"Timeout: process terminated";

	Log3 ($name, 1, "SMAEVCgarger $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} $cause");
	readingsSingleUpdate($hash,"state",$cause, 1);

	delete($hash->{HELPER}{RUNNING_PID});

	return;
}

##########################################################################
#                     SMA Command Execution
##########################################################################
sub SMAEVCharger_SMAcmd($$$) {

	my ($hash, $cmd, $value) = @_;
	
	my $baseurl = $hash->{HELPER}{BASEURL};
	my $host = $hash->{HOST};
	my $cookies = $hash->{HELPER}{SESSIONID};
	my $access_token = $hash->{HELPER}{ACCESS_TOKEN};
	my $url = $baseurl.'/api/v1/measurements/live/';
	my $name = $hash->{NAME};
	my $return = undef;
	
	# Get the current setting-level attribute
     my $setting_level  = AttrVal($name, "setting-level", 0);
	
	my 	$params->{"Param_Betriebsart_Ladevorgang"} = "Parameter.Chrg.ActChaMod";
		$params->{"Param_Minimaler_Ladestrom"} = "Parameter.Chrg.AMinCha";
		$params->{"Param_Dauer_Ladevorgang"} = "Parameter.Chrg.Plan.DurTmm";
		$params->{"Param_Energiemenge_Ladevorgang"} = "Parameter.Chrg.Plan.En";
		
			
	# advanced params
	if ($setting_level > 0)
	{
		$params->{"Param_Minimale_Schaltdauer_Relais"} = "Parameter.Chrg.MinSwTms";
		$params->{"Param_Trennung_nach_Vollladung"} = "Parameter.Chrg.StpWhenFl";
		$params->{"Param_Ladebereitschaft_bis_Trennung"} = "Parameter.Chrg.StpWhenFlTm";
		$params->{"Param_Betrieb_mit_Netzanschlusspunktzaehler"} = "Parameter.Chrg.UseEnergyMeter";
		$params->{"Param_Nennstrom_Netzanschluss"} = "Parameter.PCC.ARtg";
		$params->{"Param_Nennwirkleistung_WMaxOut"} = "Parameter.Inverter.WMax";
		$params->{"Param_Nennwirkleistung_WMaxIn"} = "Parameter.Inverter.WMaxIn";
		$params->{"Param_Maximale_Schieflast"} = "Parameter.PCC.WMaxAsym";
		$params->{"Param_Fallback_Wirkleistungsbegrenzung"} = "Parameter.PCC.FlbInv.WMax";
	}
	
	# expert params
	if ($setting_level > 1)
	{
		$params->{"Param_Timeout_nach_Kommunikationsverlust"} = "Parameter.Operation.ComTmOut";
		$params->{"Param_IGMP_Query_Intervall"} = "Parameter.Spdwr.IgmpQryTms";
		$params->{"Param_Auto_Update_an"} = "Parameter.Upd.AutoUpdIsOn";
		$params->{"Param_Geraeteneustart_ausloesen"} = "Parameter.Sys.DevRstr";
		$params->{"Param_WLAN_suchen"} = "Parameter.Wl.DoAcq";
		$params->{"Param_WPS_aktivieren"} = "Parameter.Wl.DoWPS";
		$params->{"Param_WLAN_eingeschaltet"} = "Parameter.Wl.IsOn";
		$params->{"Param_Verschluesselung_WLAN"} = "Parameter.Wl.Sec.Cry";
		$params->{"Param_WLAN-Passwort"} = "Parameter.Wl.Sec.Psk";
		$params->{"Param_SSID_WLAN"} = "Parameter.Wl.Sec.Ssid";
		$params->{"Param_Soft_Access_Point_an"} = "Parameter.Wl.SoftAcsIsOn";
	}
			
	Log3 $name, 5, "$name - PUT Parameter: ".$cmd." : ".$value;
	
	if (defined($params->{$cmd}) 
		and SMAEVCharger_SMAlogon($hash->{HOST}, $hash->{PASS}, $hash->{USER}, $hash))
	{	
		my $timestamp = POSIX::strftime("%Y-%m-%dT%H:%M:%S.000Z",gmtime());
		
		if( $cmd eq "Param_Dauer_Ladevorgang" and $value =~ m/:/)
		{
			my ($hour, $min) = split(":",$value);
			$value = $hour * 60 + $min;
		}
		
		# if charging volume changes during predefined charging methode, set ending time correct
		my $add_update = "";
		if ( $cmd eq "Param_Energiemenge_Ladevorgang" and ReadingsVal($name, "Param_Betriebsart_Ladevorgang", "") eq "Laden_mit_Vorgabe")
		{
			my $charging_stop = time_str2num(ReadingsVal($name, "Param_Ende_Ladevorgang",""));
			$add_update = " ,{\"channelId\":\"Parameter.Chrg.Plan.StopTm\",\"timestamp\":\"$timestamp\",\"value\":$charging_stop}";
		}
		
		my $val = $value;
		
		if ( $reading_codes{$value} )
		{
			$val = $reading_codes{$value};
		}
		
		#check if value is in range
		if(! defined ($return = SMAEVCharger_checkPossibleValues($name, $cmd, $val)))
		{
			my $data = "{\"values\":[{\"channelId\":\"$params->{$cmd}\",\"timestamp\":\"$timestamp\",\"value\":\"$val\"}$add_update]}";
			my $content_len = length($data);
			
			Log3 $name, 4, "$name - PUT data: ".$data;
			
			
			my $curlcmd = SMAEVCharger_getCurlcmd($hash, "write_params",$data);
		
			Log3 $name, 5, "$name - PUT data: ".$curlcmd;
			
			my $response = `$curlcmd`;
			
			my ($head,$body) = split( m{\r?\n\r?\n}, $response,2 );
			my ($code) = $head =~m{\A\S+ (\d+)};
			
			Log3 $name, 4, "$name - PUT data response: ".$response;
			
			if ($code == 204)
			{
				readingsSingleUpdate($hash, $cmd, $value, 1);
				$return = undef;
			}
			else 
			{
				$return = "Error: Couldn't send Info to Charger";
			}
		}
	}
	else
	{
		$return = "Error: Couldn't send Info to Charger";
	}
	
	return $return;
}

##########################################################################
#                                Login
##########################################################################
sub SMAEVCharger_SMAlogon($$$$) 
{
	# Parameters: host - passcode
	my ($host,$pass, $user, $hash)  = @_;
	my $name                = $hash->{NAME};
	my ($cmd, $timestmp, $myID, $target_ID, $spkt_ID, $cmd_ID);

	Log3 $name, 4, "$name - Starting login or refresh token process ";

	#Login / SessionID / Token
	my $baseurl = "https://".$host;
	my $url = $baseurl."/api/v1/token";
	my $content_len=length($user.$pass)+39;
	my $data = 'grant_type=password&username='.$user.'&password='.$pass;
	
	# all things for handle the web calls
	my $curlcmd = "";
	my $response = "";
	my $head = "";
	my $body = "";
	my $code = 200;
	
	# for now using curl because in trouble to get certificate verification with httputils-calls?!
	# login call
	
	Log3 $name, 5, "$name - aktueller Token:".$hash->{HELPER}{ACCESS_TOKEN}.":" if (defined($hash->{HELPER}{ACCESS_TOKEN}));
	
	#first, look if we need to login
	if (defined($hash->{HELPER}{ACCESS_TOKEN}) and $hash->{HELPER}{ACCESS_TOKEN} ne "")
	{
		if	((time()+300) > $hash->{HELPER}{EXPIRE_TOKEN}) # token will be expired
		{
			Log3 $name, 4, "$name - check for refresh token ";
			
			$curlcmd = SMAEVCharger_getCurlcmd($hash, "refresh_token");
			
			Log3 $name, 5, "$name - Curlaufruf für refresh: ".$curlcmd;
			$response = `$curlcmd`;
			($head,$body) = split( m{\r?\n\r?\n}, $response,2 );
			($code) = $head =~m{\A\S+ (\d+)};
			
			if ($code == 200)
			{
				$hash->{HELPER}{ACCESS_TOKEN} = $body->{"access_token"};
				$hash->{HELPER}{REFRESH_TOKEN} = $body->{"refresh_token"}; 
				$hash->{HELPER}{EXPIRE_TOKEN} = time() + $body->{"expires_in"};
				
				Log3 $name, 5, "$name - new acess_token:".$hash->{HELPER}{ACCESS_TOKEN};
				Log3 $name, 5, "$name - new refresh_token:".$hash->{HELPER}{REFRESH_TOKEN};
				
				Log3 $name, 4, "$name - got new access token";
			}
		}
		else
		{
			# check if we need to login
			Log3 $name, 4, "$name - check for need of login ";
			$curlcmd = SMAEVCharger_getCurlcmd($hash, "easyget");
			
			Log3 $name, 5, "$name - Curlaufruf für get: ".$curlcmd;
			$response = `$curlcmd`;
			($head,$body) = split( m{\r?\n\r?\n}, $response,2 );
			($code) = $head =~m{\A\S+ (\d+)};
			
			Log3 $name, 5, "$name - Ergebnis easy_get: ".$response;
		}
	}
	else
	{
		$code = 401;
	}
	
	if ($code != 200) # we need to login
	{
		Log3 $name, 4, "$name - try login to $host with user $user and password $pass ";
		
		$curlcmd = SMAEVCharger_getCurlcmd($hash, "login", $data);

		Log3 $name, 5, "$name - Curlaufruf: ".$curlcmd;

		$response = `$curlcmd`;
		($head,$body) = split( m{\r?\n\r?\n}, $response,2 );
		($code) = $head =~m{\A\S+ (\d+)};
	 
		Log3 $name, 5, "$name - Curl Response Header: ".$head;
		Log3 $name, 5, "$name - Curl Response Body: ".$body;
		Log3 $name, 5, "$name - Curl Response Code: ".$code;
		
		if (defined $head && defined $body)
		{
			if ($code == 200) # login ok
			{
				my ($cookies) = $head =~m{JSESSIONID= ?(.*);};
				my ($sessionid, $othercookies) = split(/;/, $cookies,2);
				 
				Log3 $name, 5, "$name - Cookies:".$cookies;
				Log3 $name, 5, "$name - SessionID:".$sessionid;

				$body = decode_json($body);
				$hash->{HELPER}{ACCESS_TOKEN} = $body->{"access_token"};
				$hash->{HELPER}{REFRESH_TOKEN} = $body->{"refresh_token"}; 
				$hash->{HELPER}{EXPIRE_TOKEN} = time() + $body->{"expires_in"};
				 
				# remember all things for the actual session login
				$hash->{HELPER}{SESSIONID} = $sessionid;
				
				Log3 $name, 4, "$name - login success";
			}
			else
			{
				# todo err handling
				Log3 $name, 3, "$name - Curl Response Error Code:".$code.":";
				
				$hash->{HELPER}{SESSIONID} = "";
				$hash->{HELPER}{ACCESS_TOKEN} = "";
				$hash->{HELPER}{REFRESH_TOKEN} = ""; 
				$hash->{HELPER}{EXPIRE_TOKEN} = 0;
				
				return 0;
			}
		}
		else
		{
			Log3 $name, 3, "$name - Curl no header or body";
			
			$hash->{HELPER}{SESSIONID} = "";
			$hash->{HELPER}{ACCESS_TOKEN} = "";
			$hash->{HELPER}{REFRESH_TOKEN} = ""; 
			$hash->{HELPER}{EXPIRE_TOKEN} = 0;
			
			return 0;
		}
	}
	
	return 1;
}



##########################################################################
#                               Logout
##########################################################################
sub SMAEVCharger_SMAlogout($$) 
{
	# Parameters: host
	my ($hash,$host)   = @_;
	my $name           = $hash->{NAME};
 
 #todo

	return 1;
}


1;

=pod
=item summary    Integration of SMA EVChargers over it's Speedwire (=Ethernet) Interface
=item summary_DE Integration von SMA Wallboxen über Speedwire (=Ethernet) Interface

=begin html

<a name="SMAEVCharger"></a>
<h3>SMAEVCharger</h3>

Module for the integration of a SMA EVCharger over it's Speedwire (=Ethernet) Interface.<br>
Tested on SMA EV Charger 22
<br><br>

<!--
Questions and discussions about this module you can find in the FHEM-Forum link:<br>
<a href="https://forum.fhem.de/index.php/topic,116543.msg1119664.html#msg1119664">SMA EV-Charger</a>.
<br><br>
-->

<b>Requirements</b>
<br><br>
This module requires:
<ul>
    <li>Perl Module: Date::Time        (apt-get install libdatetime-perl) </li>
	<li>Perl Module: Time::HiRes</li>
	<li>Perl Module: JSON</li>
	<li>FHEM Module: Blocking.pm</li>
</ul>
<br>
<br>


<b>Definition</b>
<ul>
<code>define &lt;name&gt; SMAEVCharger &lt;hostname/ip&gt; &lt;user&gt; &lt;password&gt;  </code><br>
<br>
<li>hostname/ip: IP-Adress of the charger, should be without protocol (for now hostname not testet!).</li>
<li>Example: define myWallbox 192.168.xxx.xxx username userpassword</li>
</ul>


<b>Operation method</b>
<ul>
The module logs on to the SMA Wallbox and reads live data (monitoring measurement values) as well as available parameters (configuration parameters). <br>
All values ​​that can be changed via the web interface can also be changed with the module. To reduce readings, the values ​​to be displayed and the values ​​that can be changed<br>
 can be adjusted with the 'detail-level' and 'setting-level' attributes. 
</ul>

<b>Get</b>
<br>
<ul>

  <li><b> get &lt;name&gt; data </b>
  <br><br>
  The request of the charger will be executed directly. Otherwise all <intervall> seconds the charge will be called automated (look at attribute interval)
  <br>
  </li>

<br>
</ul>

<b>Attributes</b>
<ul>
  <a name="disable"></a>
  <li><b>disable [1|0]</b><br>
    Deactivate/activate the module.
  </li>
  <br>

  <a name="interval"></a>
  <li><b>interval </b><br>
    Request cycle in seconds. (default: 60)
  </li>
  <br>
  
  <a name="detail-level"></a>
  <li><b>detail-level</b><br>
    Set level for showing Live-Data Readings<br>
	0: Basic<br>
	1: Adanced<br>
	2: Expert
  </li>
  <br>
  
  <a name="setting-level"></a>
  <li><b>setting-level</b><br>
    Set level for changing Parameters with fhem set-command. The module checks corresponding detail-level attribute.<br>
	0: Basic<br>
	1: Adanced<br>
	2: Expert
  </li>
  <br>

</ul>

<b>Readings</b>
<ul>
Following infos will show readings (livedata, parameter) and there corresponding detail-level and setting-level.

There are additional readings which will be calculated from the values of the wallbox.

<a name="Anzahl_Ladevorgaenge"></a>
  <li><b>Anzahl_Ladevorgaenge</b><br>
    Counts the charging starts since last connecting
  </li>
  <br>
  <a name="Startzeit_Verbindung"></a>
  <li><b>Startzeit_Verbindung</b><br>
    Last connecting time
  </li>
  <br>
</ul>
<br>

To start charging there are different options:
<ul>
<a name="Param_Betriebsart_Ladevorgang"></a>
  <li><b>Param_Betriebsart_Ladevorgang</b><br>
    Optimiertes Laden: default for using planning algorithm from wallbox<br>
	Laden mit Vorgabe: predefined charging. To set this option the params 'Param_Dauer_Ladevorgang' and 'Param_Energiemenge_Ladevorgang' must be filled.<br>
	If both values are set then this param will be set automatically and charging starts.<br>
	Ladestopp: stop charging
  </li>
  <br>
  <a name="Param_Dauer_Ladevorgang"></a>
  <li><b>Param_Dauer_Ladevorgang</b><br>
    Duration of the charging process. This values sets date/time till charging should be finished (Param_Ende_Ladevorgang)
  </li>
  <br>
  <a name="Param_Energiemenge_Ladevorgang"></a>
  <li><b>Param_Energiemenge_Ladevorgang</b><br>
    Set energy for charging in kWh. Value can be changed during charging process.
  </li>
  <br>
  <a name="Param_Minimaler_Ladestrom"></a>
  <li><b>Param_Minimaler_Ladestrom</b><br>
    Set minimum power for starting charging process. Minimum is 6A. Some vehicles need more power to start, so change this value.
  </li>
  <br>
</ul>
<br>



<ul>
<li>Name in Webinterface :<b> Name in FHEM </b> : comment</li>
					<li><b>LIVEDATA</b></li>
					<li>Measurement.ChaSess.WhIn :<b>Energie_Ladevorgang : unit Wh (detail-level: 0)</b></li>
					<li>Measurement.Chrg.ModSw :<b>Schalterstellung Drehschalter : (detail-level: 0)</b></li>
					<li>Measurement.GridMs.A.phsA :<b> Netzstrom_Phase_L1</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.A.phsB :<b> Netzstrom_Phase_L2</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.A.phsC :<b> Netzstrom_Phase_L3</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsA :<b> Netzspannung_Phase_L1</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsB :<b> Netzspannung_Phase_L2</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsC :<b> Netzspannung_Phase_L3</b> : (detail-level: 0)</li>
					<li>Measurement.Metering.GridMs.TotWIn :<b> Leistung_Bezug</b> : unit: W (detail-level: 0)</li>
					<li>Measurement.Metering.GridMs.TotWIn.ChaSta :<b> Leistung_Ladestation</b> : unit W (detail-level: 0)</li> 
					<li>Measurement.Metering.GridMs.TotWhIn :<b> Zaehlerstand_Bezugszaehler</b> : unit Wh (detail-level: 0)</li>  
					<li>Measurement.Metering.GridMs.TotWhIn.ChaSta :<b> Zaehlerstand_Ladestation</b> : unit Wh (detail-level: 0)</li>
					<li>Measurement.Operation.EVeh.ChaStt :<b> Status_Ladevorgang</b>: (detail-level: 0)</li> 
					<li>Measurement.Operation.EVeh.Health :<b> Status_verbundenes_Fahrzeug</b>: (detail-level: 0)</li> 
					<li>Measurement.Operation.Evt.Msg :<b> Status_Meldung</b> : (detail-level: 0)</li> 
					<li>Measurement.Operation.Health :<b> Status_Zustand</b> : (detail-level: 0)</li> 
					<li>Setpoint.PlantControl.Inverter.FstStop : <b> Schnellabschaltung </b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.Hz :<b> Netzfrequenz</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotPF :<b> Verschiebungsfaktor</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotVA :<b> Scheinleistung</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotVAr :<b> Blindleistung</b> : (detail-level: 1)</li>
					<li>Measurement.Wl.AcqStt :<b> Status_WLAN_Scan</b> : (detail-level: 1)</li>
					<li>Measurement.Wl.ConnStt :<b> Status_WLAN_Verbindung</b> : (detail-level: 1)</li> 
					<li>Measurement.Wl.SigPwr :<b> Signalstaerke_Netzwerk</b> : (detail-level: 1)</li> 
   					<li>Measurement.InOut.GI1 :<b> digitaler_Gruppeneingang</b> : (detail-level: 2)</li>
					<li>Measurement.Operation.WMaxLimSrc :<b> Digitaler_Eingang</b> : (detail-level: 2)</li>
					<li>Measurement.Wl.SoftAcsConnStt :<b> Status_Soft_Access_Point</b> : (detail-level: 2)</li> 
					<li><b>PARAMS:</b></li>
					<li>Parameter.Chrg.ActChaMod :<b> Param_Betriebsart_Ladevorgang</b>: (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.AMinCha :<b> Param_Minimaler_Ladestrom</b>: (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.DurTmm :<b> Param_Dauer_Ladevorgang</b> : (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.En :<b> Param_Energiemenge_Ladevorgang</b> : (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.StopTm :<b> Param_Ende_Ladevorgang</b>: (detail-level: 0) </li>
					<li>Parameter.Chrg.StpWhenFl :<b> Param_Trennung_nach_Vollladung</b>: (detail-level: 0 / setting-level: 1)</li>
					<li>Parameter.Chrg.StpWhenFlTm :<b> Param_Ladebereitschaft_bis_Trennung</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.GridGuard.Cntry.VRtg :<b> Param_Netz_Nennspannung</b>: (detail-level: 0) </li>
					<li>Parameter.PCC.ARtg :<b> Param_Nennstrom_Netzanschluss</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.PCC.FlbInv.WMax :<b> Param_Fallback_Wirkleistungsbegrenzung</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.Chrg.UseEnergyMeter :<b> Param_Betrieb_mit_Netzanschlusspunktzaehler</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Chrg.MinSwTms :<b> Param_Minimale_Schaltdauer_Relais</b> : (detail-level: 1 / setting-level: 1) </li>
					<li>Parameter.Inverter.WMax :<b> Param_Nennwirkleistung_WMaxOut</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Inverter.WMaxIn :<b> Param_Nennwirkleistung_WMaxIn</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Inverter.WMaxInRtg :<b> Param_Bemessungswirkleistung_WMaxInRtg</b>: (detail-level: 1)</li>
					<li>Parameter.Nameplate.ARtg :<b> Param_Nennstrom_alle_Phasen</b>: (detail-level: 1)</li>
					<li>Parameter.Nameplate.Location : <b> Param_Geraetename </b> : (detail-level: 1)</li>
					<li>Parameter.PCC.WMaxAsym :<b> Param_Maximale_Schieflast</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Nameplate.ChrgCtrl.ChrgTypTxt :<b>Param_Typ_Ladecontroller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SerNumTxt :<b>Param_Seriennummer_Ladecontrollers </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SusyId :<b>Param_SusyID_Ladecontrollers </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SwRevTxt :<b>Param_SWVersion_Ladecontroller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.HwRev :<b>Param_HWVersion_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.Rev :<b>Param_Umbaustand_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.SerNum :<b>Param_Seriennummer_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.SusyId :<b>Param_SUSyID_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpOS.SwRev :<b>Param_Firmware_Version_Betriebssystem </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.MacId :<b>Param_MAC-Adresse </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.MainModel :<b>Param_Geraeteklasse </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.Model :<b>Param_Geraetetyp </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ModelStr :<b>Param_Typenbezeichnung </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.PkgRev :<b>Param_Softwarepaket </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.SerNum :<b>Param_Seriennummer </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.Vendor :<b>Param_Hersteller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.WlMacId :<b>Param_WLAN_MAC </b>: (detail-level: 2) </li>
					<li>Parameter.DevUpd.IsOn :<b> Param_Geraete_Update_ein</b> : (detail-level: 2)</li>
					<li>Parameter.Inverter.OutPhs :<b> Param_Phasenzuordnung</b> : (detail-level: 2)</li>
					<li>Parameter.Operation.ComTmOut :<b> Param_Timeout_nach_Kommunikationsverlust</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.IgmpQryTms :<b> Param_IGMP_Query_Intervall</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.IgmpQryTx :<b> Param_IGMP_Anfragen_senden</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlDnsSrvIp :<b>Param_Akt_Speedwire_Serveradresse </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlGwIp :<b>Param_Akt_Speedwire_Gateway </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlIp :<b>Param_Akt_Speedwire_IP </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlSnetMsk :<b>Param_Akt_Speedwire_Subnetzmaske </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.AutoCfgIsOn :<b>Automatische_Speedwire-Konfig_an </b>: (detail-level: 2) </li>
					<li>Parameter.Sys.DevRstr :<b> Param_Geraeteneustart_ausloesen</b>: (detail-level: 2) </li>
					<li>Parameter.SwCmp.CmpEnnexOS.Frwk.SwRev :<b>Param_ennexOS_Framework_Version </b>: (detail-level: 2) </li>
					<li>Parameter.Upd.AutoUpdIsOn :<b> Param_Auto_Update_an</b>: (detail-level: 2) </li>
					<li>Parameter.Upd.AvalChkIstl :<b>Param_Auto_Speedwire_Konfig_an </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlGwIp :<b>Param_IP_Gateway_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlDnsSrvIp :<b>Aktuelle_Speedwire-DNS-Serveradresse </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlIp :<b>Param_IP_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlSnetMsk :<b>Param_IP_Subnetz_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.DoAcq :<b>Param_WLAN_suchen </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.DoWPS :<b>Param_WPS_aktivieren </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ExsNetw[] :<b>Param_Gefundenes_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Cry :<b>Param_Verschluesselung_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Psk :<b>Param_WLAN-Passwort </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Ssid :<b>Param_SSID_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.AutoCfgIsOn :<b> Param_Auto_Update_an</b>: (detail-level: 2) </li>
					<li>Parameter.Wl.IsOn :<b> Param_WLAN_eingeschaltet</b>: (detail-level: 2) </li>
					<li>Parameter.Wl.SoftAcsIsOn :<b> Param_Soft_Access_Point_an</b>: (detail-level: 2) </li>
</ul>
<br><br>


=end html


=begin html_DE

<a name="SMAEVCharger"></a>
<h3>SMAEVCharger</h3>

Modul zur Integration eines SMA EVCharger über Speedwire (=Ethernet) Schnittstelle.<br>
Getestet mit SMA EV Charger 22
<br><br>

<!--
Fragen und Diskussionen sind im FHEM Forum unter folgenden Link zu finden:<br>
<a href="https://forum.fhem.de/index.php/topic,116543.msg1119664.html#msg1119664">SMA EV-Charger</a>.
<br><br>
-->

<b>Notwendige Module</b>
<br><br>
Diese Modul benötigt:
<ul>
    <li>Perl Module: Date::Time        (apt-get install libdatetime-perl) </li>
	<li>Perl Module: Time::HiRes</li>
	<li>Perl Module: JSON</li>
	<li>FHEM Module: Blocking.pm</li>
</ul>
<br>
<br>


<b>Definition</b>
<ul>
<code>define &lt;name&gt; SMAEVCharger &lt;hostname/ip&gt; &lt;user&gt; &lt;password&gt;  </code><br>
<br>
<li>hostname/ip: IP-Adress des Charger, sollte zunächst ohne Protokoll angegeben werden (mit hostname noch nicht getestet!).</li>
<li>Beispiel: define myWallbox 192.168.xxx.xxx username userpassword</li>
</ul>


<b>Operation method</b>
<ul>
Das Modul meldet sich bei der SMA Wallbox an und liest Live-Daten (Momentanwerte) sowie verfügbare Parameter (Konfigurationsparameter).<br>
Alle Werte, die über die Weboberfläche geändert werden können, können auch mit dem Modul geändert werden. Um die Readings zu reduzieren, <br>
können die anzuzeigenden Werte und die Werte, die geändert werden können, mit den Attributen "detail-level" und "setting-level" angepasst werden.
</ul>

<b>Get</b>
<br>
<ul>

  <li><b> get &lt;name&gt; data </b>
  <br><br>
  Die Daten des Chargers werden direkt abgerufen. Ansonsten findet alle <intervall> Sekunden ein automatisierter Abruf statt (siehe auch das Attribut interval)
  <br>
  </li>

<br>
</ul>

<b>Attribute</b>
<ul>
  <a name="disable"></a>
  <li><b>disable [1|0]</b><br>
    Deaktivieren/Aktivieren des Moduls.
  </li>
  <br>

  <a name="interval"></a>
  <li><b>interval </b><br>
    Abfragezyklus in Sekunden. (default: 60)
  </li>
  <br>
  
  <a name="detail-level"></a>
  <li><b>detail-level</b><br>
    Einstellung der Sichtbarkeit von Parametern.<br>
	0: Basisinformationen<br>
	1: erweiterte Informationen<br>
	2: Infos auf Expertenlevel
  </li>
  <br>
  
  <a name="setting-level"></a>
  <li><b>setting-level</b><br>
    Einstellung für die Parameter, die über den set-Befehl änderbar sind. Bei der Eingabe wird geprüft, dass diese auch mittels "detail-level" sichtbar sind<br>
	0: Basisinformationen<br>
	1: erweiterte Änderungsparameter<br>
	2: Änderung von Parametern auf Expertenlevel
  </li>
  <br>
</ul>

<b>Readings</b>

Nachfolgende Readings dienen der Darstellung zusätzlicher Werte, die aus den Werten der Wallbox ermittelt wurden.
<ul>
<a name="Anzahl_Ladevorgaenge"></a>
  <li><b>Anzahl_Ladevorgaenge</b><br>
    Zähler zur Ermittlung aller gestarteten Ladungen, seit dem der Stecker das letzte Mal eingesteckt wurde
  </li>
  <br>
  <a name="Startzeit_Verbindung"></a>
  <li><b>Startzeit_Verbindung</b><br>
    Zeitpunkt, zu dem der Stecker das letzte Mal angesteckt wurde
  </li>
  <br>
</ul>
<br>

Zum Starten des Ladeprozess gibt es verschiedene Einstellmöglichkeiten:
<ul>
<a name="Param_Betriebsart_Ladevorgang"></a>
  <li><b>Param_Betriebsart_Ladevorgang</b><br>
    Optimiertes Laden: Standardeinstellung für die Ladesteuerung der Wallbox<br>
	Laden mit Vorgabe: Laden mit vordefinierten Werten. Dieser Wert kann nur eingestellt werden, wenn die Parameter 'Param_Dauer_Ladevorgang' und 'Param_Energiemenge_Ladevorgang' gefüllt sind.<br>
	Sind beide Werte gesetzt, wird automatisch in diesen Lademodus geschaltet und die Ladung beginnt entsprechend<br>
	Ladestopp: Ladevorgang stoppen
  </li>
  <br>
  <a name="Param_Dauer_Ladevorgang"></a>
  <li><b>Param_Dauer_Ladevorgang</b><br>
    Dauer des Ladevorgangs in Minuten. Hiermit wird dann auch der Parameter 'Param_Ende_Ladevorgang' gesetzt, der Datum/Uhrzeit des geplanten Ladeende anzeigt
  </li>
  <br>
  <a name="Param_Energiemenge_Ladevorgang"></a>
  <li><b>Param_Energiemenge_Ladevorgang</b><br>
    Energiemenge in kWh, die in der angegebenen Zeit geladen werden soll
  </li>
  <br>
  <a name="Param_Minimaler_Ladestrom"></a>
  <li><b>Param_Minimaler_Ladestrom</b><br>
    Minimaler Strom, mit dem eine Ladung gestartet wird. Minimum ist 6A. Einige E-Autos benötigen einen höheren Wert, der hiermit eingestellt werden kann.
  </li>
  <br>
</ul>
<br>


Nachfolgend sind alle Readings aufgelistet:

<br>
<ul>
<li>Name im Webinterface :<b> Name in FHEM </b> : Kommentar</li>
<li><b>LIVEDATA</b></li>
					<li>Measurement.ChaSess.WhIn :<b>Energie_Ladevorgang : unit Wh (detail-level: 0)</b></li>
					<li>Measurement.Chrg.ModSw :<b>Schalterstellung Drehschalter : (detail-level: 0)</b></li>
					<li>Measurement.GridMs.A.phsA :<b> Netzstrom_Phase_L1</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.A.phsB :<b> Netzstrom_Phase_L2</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.A.phsC :<b> Netzstrom_Phase_L3</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsA :<b> Netzspannung_Phase_L1</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsB :<b> Netzspannung_Phase_L2</b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.PhV.phsC :<b> Netzspannung_Phase_L3</b> : (detail-level: 0)</li>
					<li>Measurement.Metering.GridMs.TotWIn :<b> Leistung_Bezug</b> : unit: W (detail-level: 0)</li>
					<li>Measurement.Metering.GridMs.TotWIn.ChaSta :<b> Leistung_Ladestation</b> : unit W (detail-level: 0)</li> 
					<li>Measurement.Metering.GridMs.TotWhIn :<b> Zaehlerstand_Bezugszaehler</b> : unit Wh (detail-level: 0)</li>  
					<li>Measurement.Metering.GridMs.TotWhIn.ChaSta :<b> Zaehlerstand_Ladestation</b> : unit Wh (detail-level: 0)</li>
					<li>Measurement.Operation.EVeh.ChaStt :<b> Status_Ladevorgang</b>: (detail-level: 0)</li> 
					<li>Measurement.Operation.EVeh.Health :<b> Status_verbundenes_Fahrzeug</b>: (detail-level: 0)</li> 
					<li>Measurement.Operation.Evt.Msg :<b> Status_Meldung</b> : (detail-level: 0)</li> 
					<li>Measurement.Operation.Health :<b> Status_Zustand</b> : (detail-level: 0)</li> 
					<li>Setpoint.PlantControl.Inverter.FstStop : <b> Schnellabschaltung </b> : (detail-level: 0)</li>
					<li>Measurement.GridMs.Hz :<b> Netzfrequenz</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotPF :<b> Verschiebungsfaktor</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotVA :<b> Scheinleistung</b> : (detail-level: 1)</li>
					<li>Measurement.GridMs.TotVAr :<b> Blindleistung</b> : (detail-level: 1)</li>
					<li>Measurement.Wl.AcqStt :<b> Status_WLAN_Scan</b> : (detail-level: 1)</li>
					<li>Measurement.Wl.ConnStt :<b> Status_WLAN_Verbindung</b> : (detail-level: 1)</li> 
					<li>Measurement.Wl.SigPwr :<b> Signalstaerke_Netzwerk</b> : (detail-level: 1)</li> 
   					<li>Measurement.InOut.GI1 :<b> digitaler_Gruppeneingang</b> : (detail-level: 2)</li>
					<li>Measurement.Operation.WMaxLimSrc :<b> Digitaler_Eingang</b> : (detail-level: 2)</li>
					<li>Measurement.Wl.SoftAcsConnStt :<b> Status_Soft_Access_Point</b> : (detail-level: 2)</li> 
					<li><b>PARAMS:</b></li>
					<li>Parameter.Chrg.ActChaMod :<b> Param_Betriebsart_Ladevorgang</b>: (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.AMinCha :<b> Param_Minimaler_Ladestrom</b>: (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.DurTmm :<b> Param_Dauer_Ladevorgang</b> : (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.En :<b> Param_Energiemenge_Ladevorgang</b> : (detail-level: 0 / setting-level: 0) </li>
					<li>Parameter.Chrg.Plan.StopTm :<b> Param_Ende_Ladevorgang</b>: (detail-level: 0) </li>
					<li>Parameter.Chrg.StpWhenFl :<b> Param_Trennung_nach_Vollladung</b>: (detail-level: 0 / setting-level: 1)</li>
					<li>Parameter.Chrg.StpWhenFlTm :<b> Param_Ladebereitschaft_bis_Trennung</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.GridGuard.Cntry.VRtg :<b> Param_Netz_Nennspannung</b>: (detail-level: 0) </li>
					<li>Parameter.PCC.ARtg :<b> Param_Nennstrom_Netzanschluss</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.PCC.FlbInv.WMax :<b> Param_Fallback_Wirkleistungsbegrenzung</b>: (detail-level: 0 / setting-level: 1) </li>
					<li>Parameter.Chrg.UseEnergyMeter :<b> Param_Betrieb_mit_Netzanschlusspunktzaehler</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Chrg.MinSwTms :<b> Param_Minimale_Schaltdauer_Relais</b> : (detail-level: 1 / setting-level: 1) </li>
					<li>Parameter.Inverter.WMax :<b> Param_Nennwirkleistung_WMaxOut</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Inverter.WMaxIn :<b> Param_Nennwirkleistung_WMaxIn</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Inverter.WMaxInRtg :<b> Param_Bemessungswirkleistung_WMaxInRtg</b>: (detail-level: 1)</li>
					<li>Parameter.Nameplate.ARtg :<b> Param_Nennstrom_alle_Phasen</b>: (detail-level: 1)</li>
					<li>Parameter.Nameplate.Location : <b> Param_Geraetename </b> : (detail-level: 1)</li>
					<li>Parameter.PCC.WMaxAsym :<b> Param_Maximale_Schieflast</b>: (detail-level: 1 / setting-level: 1)</li>
					<li>Parameter.Nameplate.ChrgCtrl.ChrgTypTxt :<b>Param_Typ_Ladecontroller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SerNumTxt :<b>Param_Seriennummer_Ladecontrollers </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SusyId :<b>Param_SusyID_Ladecontrollers </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ChrgCtrl.SwRevTxt :<b>Param_SWVersion_Ladecontroller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.HwRev :<b>Param_HWVersion_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.Rev :<b>Param_Umbaustand_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.SerNum :<b>Param_Seriennummer_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpMain.SusyId :<b>Param_SUSyID_Hauptprozessor </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.CmpOS.SwRev :<b>Param_Firmware_Version_Betriebssystem </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.MacId :<b>Param_MAC-Adresse </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.MainModel :<b>Param_Geraeteklasse </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.Model :<b>Param_Geraetetyp </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.ModelStr :<b>Param_Typenbezeichnung </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.PkgRev :<b>Param_Softwarepaket </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.SerNum :<b>Param_Seriennummer </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.Vendor :<b>Param_Hersteller </b>: (detail-level: 2) </li>
					<li>Parameter.Nameplate.WlMacId :<b>Param_WLAN_MAC </b>: (detail-level: 2) </li>
					<li>Parameter.DevUpd.IsOn :<b> Param_Geraete_Update_ein</b> : (detail-level: 2)</li>
					<li>Parameter.Inverter.OutPhs :<b> Param_Phasenzuordnung</b> : (detail-level: 2)</li>
					<li>Parameter.Operation.ComTmOut :<b> Param_Timeout_nach_Kommunikationsverlust</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.IgmpQryTms :<b> Param_IGMP_Query_Intervall</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.IgmpQryTx :<b> Param_IGMP_Anfragen_senden</b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlDnsSrvIp :<b>Param_Akt_Speedwire_Serveradresse </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlGwIp :<b>Param_Akt_Speedwire_Gateway </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlIp :<b>Param_Akt_Speedwire_IP </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.ActlSnetMsk :<b>Param_Akt_Speedwire_Subnetzmaske </b>: (detail-level: 2) </li>
					<li>Parameter.Spdwr.AutoCfgIsOn :<b>Automatische_Speedwire-Konfig_an </b>: (detail-level: 2) </li>
					<li>Parameter.Sys.DevRstr :<b> Param_Geraeteneustart_ausloesen</b>: (detail-level: 2) </li>
					<li>Parameter.SwCmp.CmpEnnexOS.Frwk.SwRev :<b>Param_ennexOS_Framework_Version </b>: (detail-level: 2) </li>
					<li>Parameter.Upd.AutoUpdIsOn :<b> Param_Auto_Update_an</b>: (detail-level: 2) </li>
					<li>Parameter.Upd.AvalChkIstl :<b>Param_Auto_Speedwire_Konfig_an </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlGwIp :<b>Param_IP_Gateway_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlDnsSrvIp :<b>Aktuelle_Speedwire-DNS-Serveradresse </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlIp :<b>Param_IP_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ActlSnetMsk :<b>Param_IP_Subnetz_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.DoAcq :<b>Param_WLAN_suchen </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.DoWPS :<b>Param_WPS_aktivieren </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.ExsNetw[] :<b>Param_Gefundenes_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Cry :<b>Param_Verschluesselung_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Psk :<b>Param_WLAN-Passwort </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.Sec.Ssid :<b>Param_SSID_WLAN </b>: (detail-level: 2) </li>
					<li>Parameter.Wl.AutoCfgIsOn :<b> Param_Auto_Update_an</b>: (detail-level: 2) </li>
					<li>Parameter.Wl.IsOn :<b> Param_WLAN_eingeschaltet</b>: (detail-level: 2) </li>
					<li>Parameter.Wl.SoftAcsIsOn :<b> Param_Soft_Access_Point_an</b>: (detail-level: 2) </li>
</ul>

<br><br>

=end html_DE

=cut
