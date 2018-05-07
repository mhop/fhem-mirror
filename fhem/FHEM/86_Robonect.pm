##############################################
# $Id$
# ABU 20160307 First release
# ABU 20160321 Added first parsing algos
# ABU 20160311 Migrated to JSON
# ABU 20160412 Integrated basic set-mechanism, added internals, changed callback-routine
# ABU 20160413 Renamed to robonect, added status offline
# ABU 20160414 Changed final two Automower to Robonect
# ABU 20160414 Renamed private fn "decode"
# ABU 20160415 Renamed private fn "decode" again, set eventonchangedreading, removed debug, increased interval to 90
# ABU 20160416 Added logs, removed eventonchangedreading, added debug
# ABU 20160416 Removed logs, added eventonchangedreading, removed debug, added 1=true for json data
# ABU 20160426 Fixed decode warning, added error support
# ABU 20160515 Added splitFn and doku
# BJOERNAR 20160715 added duration and wlan-signal
# ABU 20160831 Integrated API-changes for RC9, added attribute timeout for httpData
# ABU 20160831 added calculations for duration and wlan - show in hours and percent
# ABU 20160901 rounded duration and wlan
# ABU 20161120 addaed encode_utf8 at json decode, tuned 0.5b repiar-stuff, added hibernate
# ABU 20161126 added summary
# ABU 20161129 fixed hash issues which prevents the module from loading
# ABU 20170301 fixed hybernate-check in set
# ABU 20170406 fixed hybernate-check in timer
# ABU 20170422 fixed doku
# ABU 20170427 fixed numerich undefs
# ABU 20170428 do not delete private hash data in undef
# ABU 20170428 do not define defptr in define
# ABU 20170428 fixed in define section: removed me and my secret, removed IP-check for DNS-Support
# ABU 20170428 removed setting attributes in define (eventonchange and pollInterval)
# ABU 20170428 masked decode_json in eval and added error-path
# ABU 20170501 added setkey/getkey for username and password
# ABU 20170501 added eval-error-logging
# ABU 20170501 changed verbose 3 to verbose 4
# ABU 20170501 tuned documentation
# ABU 20170516 removed useless print
# ABU 20170525 bugfixed winterschlaf again
# ABU 20171006 added options for Maehauftrag
# ABU 20171006 added "umlautfilter" for test
# ABU 20171006 added "health" for test
# ABU 20171010 finished health for test, added chck for undef at each reading
# ABU 20180507 replaced "umwelt" with "climate" in readings-section (roughly line 740)

package main;

use strict;
use warnings;
use HttpUtils;
use Encode;
use JSON;

my $EOD = "feierabend";
my $HOME = "home";
my $AUTO = "auto";
my $MANUAL = "manuell";
my $JOB = "maehauftrag";
my $START = "start";
my $STOP = "stop";
my $OFFLINE = "offline";
my $HYBERNATE = "winterschlaf";
my $USER = "benutzername";
my $PW = "passwort";

#available get cmds
my %gets = (
	"status" => "noArg",
	"health" => "noArg"	
);

#available set cmds
my %sets = (
	$EOD => "noArg",
	$HOME => "noArg",
	$AUTO => "noArg",
	$MANUAL => "noArg",
	$JOB => "",
	$START => "noArg",
	$STOP => "noArg",
	$HYBERNATE => "on,off",
	$USER => "",
	$PW => ""
);

my %commands = (
	#GET_STATUS	=> "cmd=status",
	SET_MODE	=> {$HOME=>"cmd=mode&mode=home", $MANUAL=>"cmd=mode&mode=man", $JOB=>"cmd=mode&mode=job", $AUTO=>"cmd=mode&mode=auto", $EOD=>"cmd=mode&mode=eod", $STOP=>"cmd=stop", $START=>"cmd=start"}	
);

#set to 1 for debug
my $debug = 0;

#elements within group next
my %elements = (
#	"robonect" =>
#	{
		"successful" 	=> {ALIAS=>"kommunikation", "true"=>"erfolgreich", "false"=>"fehlgeschlagen", 1=>"erfolgreich", 0=>"fehlgeschlagen"}, 
		
		"status" =>
		{
			ALIAS		=> "allgemein",
			"status" 	=> {ALIAS=>"status", 0=>"schlafen", 1=>"parken", 2=>"maehen", 3=>"suche-base", 4=>"laden", 5=>"suche", 7=>"fehler", 8=>"schleife-fehlt", 16=>"abgeschaltet", 17=>"schlafen"}, 
			"mode"	 	=> {ALIAS=>"modus", 0=>"automatik", 1=>"manuell", 2=>"home", 3=>"demo"}, 
			"battery" 	=> {ALIAS=>"batteriezustand"},
			"duration" 	=> {ALIAS=>"dauer"},
			"hours"		=> {ALIAS=>"betriebsstunden"}
		},
		
		"health" =>
		{
			ALIAS		=> "erweitert",
			"alarm" =>
			{
				ALIAS				=> "alarm",
				"voltage3v3extmin"	=> {ALIAS=>"unterspannung_extern_3V3", "false"=> "bereit", "true"=>"alarm"},
				"voltage3v3extmax"	=> {ALIAS=>"ueberspannung_extern_3V3", "false"=> "bereit", "true"=>"alarm"},
				"voltage3v3intmin"	=> {ALIAS=>"unterspannung_intern_3V3", "false"=> "bereit", "true"=>"alarm"},
				"voltage3v3intmax"	=> {ALIAS=>"ueberspannung_intern_3V3", "false"=> "bereit", "true"=>"alarm"},
				"voltagebattmin"	=> {ALIAS=>"unterspannung_batterie", "false"=> "bereit", "true"=>"alarm"},
				"voltagebattmax"	=> {ALIAS=>"ueberspannung_batterie", "false"=> "bereit", "true"=>"alarm"},
				"temperatureMin"	=> {ALIAS=>"zu_kalt", "false"=> "bereit", "true"=>"alarm"},
				"temperatureMax"	=> {ALIAS=>"zu_warm", "false"=> "bereit", "true"=>"alarm"},
				"humidityMax"		=> {ALIAS=>"zu_feucht", "false"=> "bereit", "true"=>"alarm"},
			},
			"voltages" =>
			{
				ALIAS		=> "spannung",
				"ext3v3"	=> {ALIAS=>"extern"},
				"int3v3"	=> {ALIAS=>"intern"},
				"batt"		=> {ALIAS=>"batterie"},
			},
			"climate" =>
			{
				ALIAS		=> "umwelt",
				"temperature"	=> {ALIAS=>"temperatur"},
				"humidity"	=> {ALIAS=>"feuchte"},
			}			
		},		
		
		"timer" =>
		{
			ALIAS		=> "timer",
			"status"	=> {ALIAS=>"status", 0=>"deaktiviert", 1=>"aktiv", 2=>"standby"},			
			"next" =>
			{
				ALIAS		=> "timer",
				"date"		=> {ALIAS=>"startdatum"},
				"time"		=> {ALIAS=>"startzeit"},
				#"date"		=> {ALIAS=>"start-unix"},
			}
		},
		
		"wlan" =>
		{
			ALIAS			=> "wlan",
			"signal"		=> {ALIAS=>"signal"}
		},		
		
		"error" =>
		{
			ALIAS			=> "fehler",
			"error_code"	=> {ALIAS=>"code"},
			"error_message"	=> {ALIAS=>"nachricht"},
			"date"			=> {ALIAS=>"datum"},
			"time"			=> {ALIAS=>"zeit"}
		}		
#	}	
);

#this table is used to replace special chars
my %umlaute = ("ä" => "&auml;", "ü" => "&uuml;", "ö" => "&ouml;","Ä" => "&Auml;", "Ü" => "&Uuml;", "Ö" => "&Ouml;", "ß" => "&szlig;");

#Init this device
#This declares the interface to fhem
#############################
sub Robonect_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Robonect_Define';
    $hash->{UndefFn}    = 'Robonect_Undef';
    $hash->{SetFn}      = 'Robonect_Set';
    $hash->{GetFn}      = 'Robonect_Get';
    $hash->{AttrFn}     = 'Robonect_Attr';
	$hash->{ShutdownFn} = 'Robonect_Shutdown';
	$hash->{ReadyFn} 	= 'Robonect_Ready';
	$hash->{DbLog_splitFn}  = 'Robonect_DbLog_split';
	$hash->{AttrList}  		= 	"do_not_notify:1,0 " . 		#supress any notification (including log)
								"showtime:1,0 " . 			#shows time instead of received value in state
								"credentials " .			#user/password combination for authentication in mower, stored in a credentials file
								"basicAuth " .				#user/password combination for authentication in mower								
								"pollInterval " .			#interval to poll in seconds
								"timeout " .				#http-timeout
								"useHealth " .				#if true, poll for health
								"$readingFnAttributes ";	#standard attributes
}

#Define this device
#Is called at every define
#############################
sub Robonect_Define($$) 
{
    my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	#device name
	my $name = $a[0];

	#set verbose to 5, if debug enabled
	$attr{$name}{verbose} = 5 if ($debug eq 1);	

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "define $name: enter $hash, attributes: $tempStr");
	
	#too less arguments
	#return "wrong syntax - define <name> Robonect <ip-adress> [<user> <password>]" if (int(@a) < 3);
	return "wrong syntax - define <name> Robonect <ip-adress>" if (int(@a) < 3);

	#check IP
	my $ip = $a[2];
	#remove whitespaces
	$ip =~ s/^\s+|\s+$//g;
	#removed IP-check - can also be a name
	#Syntax ok
	#if ($ip =~ m/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
	#{
	#	my @octs = split (".", $ip);
	#	
	#	foreach my $octet (@octs)
	#	{
	#		return "wrong syntax - $octet has an invalid range. Allowed is 0..255" if (($octet >= 256) or ($octet <= -1));
	#	}
	#}
	#else
	#{
	#	return "wrong syntax - IP must be supplied correctly <0..254>.<0..254>.<0..254>.<0..254>";
	#}
	
	#wrong syntax for IP
	#return "wrong syntax - IP must be supplied correctly <0..254>.<0..254>.<0..254>.<000..254>" if (int(@a) < 3);
		    
	#assign name and port
    $hash->{NAME} = $name;
	$hash->{IP} = $ip;
	#backup name for a later rename
	$hash->{DEVNAME} = $name;
	
	#get first info and launch timer
	InternalTimer(gettimeofday(), "Robonect_GetUpdate", $hash, 0);	

	#finally create decice
	#defptr is needed to supress FHEM input
	#removed according Rudis recommendation
	#$modules{Robonect}{defptr}{$name} = $hash;

	#default event-on-changed-reading for all readings
	#removed according Rudis recommendation
	#$attr{$name}{"event-on-change-reading"} = ".*";
	#default poll-interval
	#removed according Rudis recommendation
	#$attr{$name}{"pollInterval"} = 90;
	
	Log3 ($name, 5, "exit define");
	return undef;	
}

#Release this device
#Is called at every delete / shutdown
#############################
sub Robonect_Undef($$) 
{
	my ($hash, $name) = @_;

	Log3 ($name, 5, "enter undef $name: hash: $hash name: $name");
	
	#kill interval timer
	RemoveInternalTimer($hash);  

	#close port
  	Robonect_Shutdown ($hash);
	
	#remove module. Refer to DevName, because module may be renamed
	delete $modules{KNX}{defptr}{$hash->{DEVNAME}};

	#removed according to Rudis recommendation
	#remove name
	#delete $hash->{NAME};
	#remove backuped name
	#delete $hash->{DEVNAME};
		
	Log3 ($name, 5, "exit undef");
	return undef;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub Robonect_Shutdown($) 
{
	my ($hash) = @_;
	
	#hash may be de-referenced already
	my $name = "robonect-not_named_any_more";	
	$name = $hash->{NAME} if (ref($hash) eq "HASH");
	
	Log3 ($name, 5, "enter shutdown $name: hash: $hash name: $name");
	Log3 ($name, 5, "exit shutdown");
	return undef;
}

#This function is called from fhem from rime to time
#############################
sub Robonect_Ready($) 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "enter ready $name: hash: $hash name: $name");
	Log3 ($name, 5, "exit ready");
	return undef;	
}

#Reads info from the mower
#############################
sub Robonect_Get($@) 
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter get $name: $name hash: $hash, attributes: $tempStr");

	#backup cmd
	my $cmd = $a[1];
	#lower cmd
	$cmd = lc($cmd);
	
	#create response, if cmd is wrong or gui asks
	my $cmdTemp = Robonect_getCmdList ($hash, $cmd, %gets);
	return $cmdTemp if (defined ($cmdTemp)); 
	
	my ($userName, $passWord) = Robonect_getCredentials ($hash);
	
	#basic url
	my $url = "http://" . $hash->{IP} . "/json?";
	#append userdata, if given
	$url = $url . "user=" . $userName . "&pass=" . $passWord . "&" if (defined ($userName) and defined ($passWord));
	#append command
	#$url = $url . $commands{GET_STATUS};
	$url = $url . "cmd=" . $cmd;
		
	my $httpData;
	$httpData->{url} = $url;
	$httpData->{loglevel} = AttrVal ($name, "verbose", 2);
	$httpData->{loglevel} = 5;
	$httpData->{hideurl} = 0;		
	$httpData->{callback} = \&Robonect_callback;
	$httpData->{hash} = $hash;
	#$httpData->{cmd} = $commands{GET_STATUS};
	$httpData->{cmd} = "cmd=" . $cmd;
	$httpData->{timeout} = AttrVal ($name, "timeout", 4);
		
	HttpUtils_NonblockingGet($httpData);
	
	Log3 ($name, 5, "exit get");
	
	my $err = $httpData->{err};
	
	if (defined ($err) and (length ($err) > 0))
	{
		return $err;
	}
	else
	{
		return "update requested";
	}
}

#Sends commands to the mower
#############################
sub Robonect_Set($@) 
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter set $name: $name hash: $hash, attributes: $tempStr");
	
	#backup cmd
	my $cmd = $a[1];
	#lower cmd
	$cmd = lc($cmd);
			
	#create response, if cmd is wrong or gui asks
	my $cmdTemp = Robonect_getCmdList ($hash, $cmd, %sets);
	return $cmdTemp if (defined ($cmdTemp)); 
	
	my ($userName, $passWord) = Robonect_getCredentials ($hash);
	my $decodedCmd = $commands{SET_MODE}{$cmd};

	#if command is hybernate, do this
	if ($cmd eq lc($HYBERNATE))
	{
		Log3 ($name, 5, "set - got hybernate for set-command");
			
		my $val = lc($a[2]);
		$val = "off" if (!defined ($val));
			
		if ($val =~ m/on/)
		{
			readingsSingleUpdate($hash, $HYBERNATE, "on", 1);
			Log3 ($name, 5, "set - activated hybernate");
		}
		elsif ($val =~ m/off/)
		{
			readingsSingleUpdate($hash, $HYBERNATE, "off", 1);
			Log3 ($name, 5, "set - deactivated hybernate");
		}
		else
		{
			return "only on or off are supported for $HYBERNATE";
		}	
	}
	#if command is user
	elsif ($cmd eq lc($USER))
	{
		setKeyValue("ROBONECT_USER_$name", $a[2]);
		Log3 ($name, 5, "set - wrote username");
	}
	#if command is password
	elsif ($cmd eq lc($PW))
	{
		setKeyValue("ROBONECT_PW_$name", $a[2]);
		Log3 ($name, 5, "set - wrote password");
	}	
	#else proceed with communication to mower
	#execute it
	elsif (defined ($decodedCmd))
	{

		my $url = "http://" . $hash->{IP} . "/json?";
		#append userdata, if given
		$url = $url . "user=" . $userName . "&pass=" . $passWord . "&" if (defined ($userName) and defined ($passWord));
		#append command
		$url = $url . $decodedCmd;

		#execute for alle "extra" arguments
		for (my $i = 2; $i < @a; $i++) 
		{
			my $cmdAttr = $a[$i];
			my ($key, $val) = split (/=/, $cmdAttr);
			
			if (defined ($key) and defined ($val) and (length ($key) > 0) and (length ($val) > 0))
			{
				$url = $url . "&" . $key . "=" . $val;
				Log3 ($name, 5, "set - found option. Key:$key Value:$val") 
			}
			else
			{	
				Log3 ($name, 1, "set - found incomplete option. Key:$key Value:$val") 
			}
		}
		
		Log3 ($name, 5, "set - complete call-string: $url"); 
		
		my $httpData;
		$httpData->{url} = $url;
		$httpData->{loglevel} = AttrVal ($name, "verbose", 2);
		$httpData->{loglevel} = 5;
		$httpData->{hideurl} = 0;		
		$httpData->{callback} = \&Robonect_callback;
		$httpData->{hash} = $hash;
		$httpData->{cmd} = $decodedCmd;
			
		HttpUtils_NonblockingGet($httpData);
			
		return $httpData->{err};
		
		#BUllshit - never gets called	
		#Robonect_GetUpdate($hash);		
    }	
	
	Log3 ($name, 5, "exit set");	
	
	return;
}

#called on every mod of the attributes
#############################
sub Robonect_Attr(@) 
{
	my ($cmd,$name,$attr_name,$attr_value) = @_;

	Log3 ($name, 5, "enter attr $name: $name, attrName: $attr_name");
	
	#if($cmd eq "set") 
	#{		
	#	if(($attr_name eq "debug") and (($attr_value eq "1") or ($attr_value eq "true")))
	#	{
	#		#todo
	#	}			
	#}
	
	Log3 ($name, 5, "exit attr");	
	
	return undef;
}

#Split reading for DBLOG
#############################
sub Robonect_DbLog_split($) {
	my ($event) = @_;
	my ($reading, $value, $unit);

	my $tempStr = join (", ", @_);
	Log (5, "splitFn - enter, attributes: $tempStr");
	
	#detect reading - real reading or state?
	my $isReading = "false"; 
	$isReading = "true" if ($event =~ m/: /);
	
	#split input-string
	my @strings = split (" ", $event);
	
	my $startIndex = undef;
	$unit = "";
	
	return undef if (not defined ($strings[0]));

	#real reading?
	if ($isReading =~ m/true/)
	{
		#first one is always reading
		$reading = $strings[0];
		$reading =~ s/:?$//;
		$startIndex = 1;
	}
	#plain state
	else
	{
		#for reading state nothing is supplied
		$reading = "state";
		$startIndex = 0;	
	}
	
	return undef if (not defined ($strings[$startIndex]));

	#per default join all single pieces
	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	
	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+$/)
	{
		$value = $strings[$startIndex];
		#single numeric value? Assume second par is unit...
		if ((defined ($strings[$startIndex + 1])) && !($strings[$startIndex+1] =~ /^[+-]?\d*[.,]?\d+/)) 
		{
			$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
		}
	}

	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	#{
	#	$value = $strings[$startIndex];
	#	$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
	#}
	#string or raw
	#else
	#{
	#	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	#}
		
	Log (5, "splitFn - READING: $reading, VALUE: $value, UNIT: $unit");
	
	return ($reading, $value, $unit);
}

#Called on the interval timer, if enabled
#############################
sub Robonect_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "enter update $name: $name");

	#evaluate reading hybernate
	my $hybernate = $hash->{READINGS}{$HYBERNATE}{VAL};
	#supress sending, if hybernate is set
	if (!defined ($hybernate) or ($hybernate =~ m/[off]|[0]/))
	{
		#get status	
		my @callAttr;
		$callAttr[0] = $name;
		$callAttr[1] = "status";
		Robonect_Get ($hash, @callAttr);
				
		#try to poll health, if desired
		my $useHealth = AttrVal($name,"useHealth",undef);		
		if (defined ($useHealth) and ($useHealth =~ m/[1]|([oO][nN])/))
		{
			$callAttr[1] = "health";
			Robonect_Get ($hash, @callAttr);
		}
	}

	my $interval = AttrVal($name,"pollInterval",90);
	#reset timer
	InternalTimer(gettimeofday() + $interval, "Robonect_GetUpdate", $hash, 1) if ($interval > 0);
	
	Log3 ($name, 5, "exit update");	
}

#Private function which handles http-responses
#############################
sub Robonect_callback ($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
 
	#wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    if($err ne "")
    {
        Log3 ($name, 4, "callback - error while requesting ".$param->{url}." - $err");
		$hash->{LAST_COMM_STATUS} = $err;
		#set reading with failure - notify only, when state has not changed
        readingsSingleUpdate($hash, "state", $OFFLINE, 1);
    }
	#wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    elsif($data ne "")
    {
        Log3 ($name, 4, "callback - url ".$param->{url}." returned: $data");
		
		#repair V5.0b
		$data =~ s/:"/,"/g;
		$data = "" if (!defined($data));
		
		#execute in eval to be safe - therefore $answer may be undef
		my $answer = undef;
		eval '$answer = decode_json (encode_utf8($data))';
		
		#try to replaye german special chars
		if (defined ($answer) and (length ($answer) > 0))
		{
			my $umlautkeys = join ("|", keys(%umlaute));
			$answer =~ s/($umlautkeys)/$umlaute{$1}/g;
		}
				
		#backup error from eval
		my $evalErr = $@;
		
		if (not defined($answer))
		{
			my $err = "callback - error while decoding content";
			$err = $err . ": " . $evalErr if (defined ($evalErr));
			Log3 ($name, 2, $err);
			readingsSingleUpdate($hash, "fehler_aktuell", "cannot decode content", 1);
			return undef;
		}
		
		Log3 ($name, 4, "callback - url ".$param->{url}." repaired: $data");
		
		my ($key, $value) = Robonect_decodeContent ($hash, $answer, "successful", undef, undef);
		
		$hash->{LAST_CMD} = $param->{cmd};
		$hash->{LAST_COMM_STATUS} = "success: " . $value;
		
		Log3 ($name, 5, "callback - communication ok");
		
		#my %tmp = %$answer;
		#print "answer: ", %tmp, "\n";
				
		#status-readings
		#answer may be undefined due to eval
		if ($answer->{successful} =~ m/(true)|(1)/)
		{
			Log3 ($name, 5, "callback - update readings");
			
			readingsBeginUpdate($hash);

			#($key, $value) = Robonect_decodeContent ($hash, $answer, "successful", undef);
			#readingsBulkUpdate($hash, $key, $value);			

			($key, $value) = Robonect_decodeContent ($hash, $answer, "status", "status", undef);
			if (defined ($value) and !($value =~ m/undef/))
			{
				readingsBulkUpdate($hash, $key, $value);
				readingsBulkUpdate($hash, "state", $value);
			}
			($key, $value) = Robonect_decodeContent ($hash, $answer, "status", "mode", undef);
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			($key, $value) = Robonect_decodeContent ($hash, $answer, "status", "battery", undef);
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			$value = 0;
			($key, $value) = Robonect_decodeContent ($hash, $answer, "status", "duration", undef);
			readingsBulkUpdate($hash, $key, sprintf ("%d", $value/3600)) if (defined($value) and ($value =~ m/(?:\d*\.)?\d+/));			
			($key, $value) = Robonect_decodeContent ($hash, $answer, "status", "hours", undef);
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));

			($key, $value) = Robonect_decodeContent ($hash, $answer, "timer", "status", undef);
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			
			($key, $value) = Robonect_decodeContent ($hash, $answer, "timer", "next", "date");
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			($key, $value) = Robonect_decodeContent ($hash, $answer, "timer", "next", "time");
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			
			$value = -95;
			($key, $value) = Robonect_decodeContent ($hash, $answer, "wlan", "signal", undef);
			readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			
			if (defined($value) and ($value =~ m/(?:\d*\.)?\d+/))
			{
				$value = sprintf ("%d", ($value + 95) / 0.6);
				readingsBulkUpdate($hash, $key . "-prozent", $value);
			}
			
			#try to decode health, if desired
			my $useHealth = AttrVal($name,"useHealth",undef);		
			if (defined ($useHealth) and ($useHealth =~ m/[1]|([oO][nN])/))
			{
				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "alarm", "voltagebattmin");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
				
				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "alarm", "voltagebattmax");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));

				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "alarm", "temperatureMin");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));

				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "alarm", "temperatureMax");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
				
				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "alarm", "humidityMax");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
				
				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "voltages", "batt");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));

				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "climate", "temperature");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));

				($key, $value) = Robonect_decodeContent ($hash, $answer, "health", "climate", "humidity");
				readingsBulkUpdate($hash, $key, $value) if (defined ($value) and !($value =~ m/undef/));
			}
			
			readingsEndUpdate($hash, 1);
		}
		
		#error?
		#answer may be undefined due to eval
		my $errorOccured = $answer->{status}->{status};
		if (defined ($errorOccured) and ($errorOccured  =~ m/7/))
		{
			readingsSingleUpdate($hash, "fehler_aktuell", $answer->{error}->{error_message}, 1);
		}
		#no error
		elsif (defined ($errorOccured))
		{
			my $hashref = $hash->{READINGS};
			my %readings = %$hashref;
			
			#delete readings
			foreach my $key (keys %readings)
			{
				#delete $readings{$key} if ($key =~ m/^fehler.*/);			
				delete $hash->{READINGS}{$key} if ($key =~ m/^fehler.*/);							
				#delete $hash->{READINGS}{$key} if ($key =~ m/^fehler-aktuell.*/);
			}
		}
    }
}

#Private function to get json-content
#############################
sub Robonect_decodeContent ($$$$$)
{
	my ($hash, $msg, $key1, $key2, $key3) = @_;
	my $name = $hash->{NAME};
	
	my $rdName = undef;
	my $rdValue = undef;
	
	my $template = undef;

	if (defined ($key2) && defined ($key3))
	{
		$template = $elements{$key1}{$key2}{$key3};
		$rdName = $elements{$key1}{$key2}{ALIAS} . "-" . $template->{ALIAS};
		$rdValue = $msg->{$key1}->{$key2}->{$key3};	
	}
	elsif (defined ($key2))
	{
		$template = $elements{$key1}{$key2};
		$rdName = $elements{$key1}{ALIAS} . "-" . $template->{ALIAS};
		$rdValue = $msg->{$key1}->{$key2};
	}
	else
	{
		$template = $elements{$key1};
		$rdValue = $msg->{$key1};
		$rdName = $template->{ALIAS};
	}
	
	$rdValue = "undef" if (not defined ($rdValue));
	$rdValue = $template->{$rdValue} if (defined ($template->{$rdValue}));
	
	Log3 ($name, 5, "decodeContent - NAME: $rdName, VALUE: $rdValue");
	
	return $rdName, $rdValue;
}

#Private function to evaluate credentials
#############################
sub Robonect_decodeAnswer ($$$)
{
	my ($hash, $getCmd, @readings) = @_;
	my $name = $hash->{NAME};
	
	my @list;
	
	foreach my $reading (@readings)
	{
		my $answer = undef;
		my $transval = undef;
		my ($header, $key, $value) = undef;
		
		$header = $reading->{header};
		$key = $reading->{key};
		$value = $reading->{value};
		
		if ($header =~ m/robonect/i)
		{
			$answer->{name} = $getCmd . "-" . $elements{$header}{$key}{ALIAS};
			$transval = $elements{$header}{$key}{$value};
		}
		else
		{
			$answer->{name} = $getCmd . "-" . $elements{"robonect"}{$header}{ALIAS} . "-" . $elements{"robonect"}{$header}{$key}{ALIAS};
			$transval = $elements{"robonect"}{$header}{$key}{$value};		
		}
		
		if (defined($transval))
		{	
			$answer->{value} = $transval;
		}
		else
		{
			$answer->{value} = $value;
		}
		
		#$answer->{name} = $getCmd . "-" . $answer->{name};
		
		Log3 ($name, 5, "decodeAnswer - NAME: $answer->{name}, VALUE: $answer->{value}");
		
		push (@list, $answer);
	}
	
	return @list;
}

#Private function to evaluate credentials
#############################
sub Robonect_getCredentials ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $userName = undef;
	my $passWord = undef;

	#use username and password previously defined with set and stored in "registry"
	my ($errUsr, $user) = getKeyValue("ROBONECT_USER_$name");
	Log3 ($name, 4, "credentials - Error while getting value USER: " . $errUsr) if (defined ($errUsr));
	my ($errPw, $password) = getKeyValue("ROBONECT_PW_$name");
	Log3 ($name, 4, "credentials - Error while getting value PASSWORD: " . $errPw) if (defined ($errPw));

	if (defined ($user) and defined ($password))
	{
		Log3 ($name, 5, "credentials - found with key-value");
		return $userName, $passWord;
	}
	
	#parse basicAuth - overrules getKeyValue
	my $basicAuth = AttrVal ($name, "basicAuth", undef);
	if (defined ($basicAuth))
	{
		#if the string does NOT contain a ":", assume base64-encoded data
		if (not ($basicAuth =~ m/:/))
		{
			$basicAuth = decode_base64 ($basicAuth);			
			Log3 ($name, 5, "credentials - found encrypted data");
		}

		#try to split 
		my @plainAuth = split (":", $basicAuth);
		
		#found plain authentication
		if (int(@plainAuth) == 2)
		{
			$userName = $plainAuth[0];
			$passWord = $plainAuth[1];
			
			Log3 ($name, 5, "credentials - found plain or decrypted data");
		}
		else
		{
			Log3 ($name, 0, "credentials - user/pw combination not correct");		
		}
	}
	
	#parse credential-File - overrules basicAuth ang getKeyValue
	my $credentials = AttrVal ($name, "credentials", undef);
	if(defined($credentials)) 
	{
		#cannot open file
		if(!open(CFG, $credentials))
		{	
			Log3 ($name, 0, "cannot open credentials file: $credentials") ;
		}
		#read it		
		else
		{
			my @cfg = <CFG>;
			close(CFG);
			my %creds;
			eval join("", @cfg);
			#extract it
			$userName =~ $creds{$name}{username};
			$passWord =~ $creds{$name}{password};
		
			Log3 ($name, 5, "credentials - found in file");		
		}
	}
	
	return $userName, $passWord;
}

#Private function to evaluate command-lists
#############################
sub Robonect_getCmdList ($$$)
{
	my ($hash, $cmd, %cmdArray) = @_;

	my $name = $hash->{NAME};

	#return, if cmd is valid
	return undef if (defined ($cmd) and defined ($cmdArray{$cmd}));
	
	#response for gui or the user, if command is invalid
	my $retVal;
	foreach my $mySet (keys %cmdArray)
	{
		#append set-command
		$retVal = $retVal . " " if (defined ($retVal));
		$retVal = $retVal . $mySet;
		#get options
		my $myOpt = $cmdArray{$mySet};
		#append option, if valid
		$retVal = $retVal . ":" . $myOpt if (defined ($myOpt) and (length ($myOpt) > 0));
		$myOpt = "" if (!defined($myOpt));
		#Logging makes me crazy...
		#Log3 ($name, 5, "parse cmd-table - Set:$mySet, Option:$myOpt, RetVal:$retVal");
	}
	
	if (!defined ($retVal))
	{
		$retVal = "error while parsing set-table" ;
	}
	else
	{
		$retVal = "Unknown argument $cmd, choose one of " . $retVal;	
	}
	
		
	return $retVal;
}

1;

=pod
=begin html

<a name="Robonect"></a> 
<h3>Robonect</h3>
<ul>
<p>Robonect is a after-market wifi-module for robomowers based on the husky G3-control. It was developed by Fabian H. and can be optained at www.robonect.de. This module gives you access to the basic commands. This module will not work without libjson-perl! Do not forget to install it first!</p>

  <p><a name="RobonectDefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Robonect &lt;ip-adress or name&gt;</code>
    
	<p>Setting Winterschlaf prevents communicating with the mower.</p>
	
	<p>The authentication can be supplied in the definition as plaine text or in a differen way - see the attributes. Per default the status is polled every 90s.</p>

    <p>Example:</p>
      <pre>
      define myMower Robonect 192.168.13.5
	  define myMower Robonect myMowersDNSName
      </pre>
  </ul>
  
  <p><a name="RobonectSet"></a> <b>Set</b></p>
  <ul>
	<b>Set</b>
	<ul>
		<li>auto<br>
			Sets the mower to automatic mode. The mower follows the internal timer, until another mode is chosen. The mower can be stopped with stop at any time. After using stop: be aware, that it continues 
			mowing only if the timer supplies an active slot AND start is executed before.
		</li>
		<li>manuell<br>
			This sets the mower to manual mode. The internal timer is ignored. Mowing starts with start and ends with stop.
		</li>
		<li>home<br>
			This sends the mower directly home. Until you switch to auto or manuell, no further mowing work is done.
		</li>	
		<li>feierabend<br>
			This sends the mower home for the rest of the actual timeslot. At the next active timeslot mowing is continued automatically.
		</li>	
		<li>start<br>
			Start mowing in manual mode or in automatic mode at active timer-slot.
		</li>	
		<li>stop<br>
			Stops mowing immediately. The mower does not drive home. It stands there, until battery is empty. Use with care!
		</li>	
		<li>maehauftrag<br>
			This command starts a single mowing-task. It can be applied as much parameters as you want. For example you can influence start-/stop-time and duration.<br>
			The parameters have to be named according the robonect-API (no doublechecking!).<br>
			<br>
			Example:<br>
			Lauch at 15:00, Duration 120 minutes, do not use a remote-start-point, do not change mode after finishing task
			<pre>
			  set myMower maehauftrag start=15:00 duration=120 remotestart=0 after=4
			</pre>			
		</li>
		<li>winterschlaf &lt;on, off&gt;<br>
			If set to on, no polling is executet. Please use this during winter.
		</li>	
		<li>user &ltuser&gt;<br>
			One alternative to store authentication: username for robonect-logon is stored in FhemUtils or database (not encrypted).<br
			If set, the attributes regarding authentication are ignored.
		</li>		
		<li>password &lt;password&gt;<br>
			One alternative to store authentication: password for robonect-logon is stored in FhemUtils or database (not encrypted).<br
			If set, the attributes regarding authentication are ignored.
		</li>
	</ul>
  </ul>

  <p><a name="RobonectGet"></a> <b>Get</b></p>
  <ul>
	<b>Get</b>
	<ul>  
		<li>status<br>
			Gets the actual state of the mower - normally not needed, because the status is polled cyclic.
		</li>
		<li>health<br>
			This one gets more detailed information - like voltages and temperatures. It is NOT SUPPORTED BY ALL MOWERS!!!<br>
			If enabled via attribute, health is polled accordingly status.
		</li>
	</ul>
  </ul>
  
  <p><a name="RobonectAttr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="RobonectCredentials"></a> <b>credentials</b></p>
  <ul> 
    If you supply a valid path to a credentials file, this combination is used to log in at robonect. This mechism overrules basicAuth.
  </ul> 

  <p><a name="RobonectBasicAuth"></a> <b>basicAuth</b></p>
  <ul> 
	You can supply username and password plain or base-64-encoded. For a base64-encoder, use google.
      <p>Example:</p>
      <pre>
      define myMower Robonect 192.168.5.1
	  attr myMower basicAuth me:mySecret
      </pre>    
	  <pre>
      define myMower Robonect 192.168.5.1
	  attr myMower basicAuth bWU6bXlTZWNyZXQ=
      </pre>    
  </ul>	

  <p><a name="RobonectPollInterval"></a> <b>pollInterval</b></p>
  <ul>
	Supplies the interval top poll the robonect in seconds. Per default 90s is set.
  </ul>
  
  <p><a name="RobonectTimeout"></a> <b>timeout</b></p>
  <ul>
	Timeout for httpData to recive data. Default is 4s.
  </ul>
  
  <p><a name="RobonectHealth"></a> <b>useHealth</b></p>
  <ul>
	If set to 1, the health-status of the mower will be polled. Be aware NOT ALL MOWERS ARE SUPPORTED!<br>
	Please refer to logfile or LAST_COMM_STATUS if the function does not seem to be working.
  </ul>

</ul>
=end html
=device
=item summary Communicates to HW-module robonect
=item summary_DE Kommuniziert mit dem HW-Modul Robonect
=begin html_DE

<a name="Robonect"></a> 
<h3>Robonect</h3>
<ul>
<p>Robonect ist ein Nachr&uml;stmodul f&uuml;r automower, die auf der Husky-G3-Steuerung basieren. Es wurde von Fabian H. entwickelt und kann unter www.robonect.de bezogen werden. Dieses Modul gibt Euch Zugriff auf die n&ouml;tigsten Kommandos. Dieses Modul ben&ouml;tigt libjson-perl. Bitte NICHT VERGESSEN zu installieren!</p>


  <p><a name="RobonectDefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Robonect &lt;IP-Adresse oder Name&gt;</code>
    
	<p>Mit gesetztem Winterschlaf wird die Kommunikation zum M&auml;her unterbunden.</p>
	
	<p>Die Zugangsinformationen k&ouml;nnen im Klartext bei der Definition angegeben werden. Wahlweise auch per Attribut. Standardm&auml;&szlig;ig wird der Status vom RObonect alle 90s aktualisiert.</p>

    <p>Beispiel:</p>
      <pre>
      define myMower Robonect 192.168.13.5
	  define myMower Robonect myMowersDNSName
      </pre>
  </ul>
  
  <p><a name="RobonectSet"></a> <b>Set</b></p>
  <ul>
	<b>Set</b>
	<ul>
		<li>auto<br>
			Dies versetzt den M&auml;her in den Automatikmodus. Der M&auml;her reagiert nur auf den internen Timer, bis eine andere Betriebsart gew&auml;hlt wird. Der M&auml;her kann mit Stop jederzeit
			angehalten werden. Es wird erst wieder begonnen zu m&auml;hen, wenn der Timer (wieder) ein aktives Fenster hat UND Start gesendet wurde.
		</li>
		<li>manuell<br>
			Dies versetzt den M&auml;her in den manuellen modus. Der interne Timer wird nicht beachtet. Der M&auml;her reagiert nur auf Start oder Stopp Befehle von FHEM. 
		</li>
		<li>home<br>
			Dies schickt den M&auml;her direkt nach hause. Weiteres m&auml;hen wird verhindert, bis auf manuell oder auto umgeschalten wird.
		</li>	
		<li>feierabend<br>
			Dies schickt den M&auml;her f&uuml;r den aktuellen Timerslot direkt nach hause. Beim n&auml;chsten aktiven Timerslot wird weitergem&auml;ht.
		</li>	
		<li>start<br>
			Startet den M&auml;hvorgang im manuellen Modus oder im Automatikmodus bei aktivem Zeitslot.
		</li>	
		<li>stop<br>
			Beendet den M&auml;hvorgang. Der M&auml;her f&auml;hrt nicht nach Hause und beginnt nicht wieder zu m&auml;hen. Er bleibt stehen, bis die Batterie leer ist. Nur mit Bedacht benutzen!
		</li>	
		<li>maehauftrag<br>
			Hiermit wird ein (einmaliger) Auftrag an den M&auml;her abgesetzt. Es können beliebig viele Parameter mitgegeben werden. So kann zum Beispiel der Modus nach dem Auftrag,
			sowie Start- oder Stoppzeit beeinflusst werden.<br>
			Die Parameter m&uuml;ssen wie in der API des Robonect beschrieben lauten. Es erfolgt keine syntaktische Prüfung!<br>
			<br>
			Beispiel:<br>
			Startzeit 15 Uhr, Dauer 120 Minuten, keinen Fernstartpunkt verwenden, keine Betriebsartenumschaltung nach Auftragsende
			<pre>
			  set myMower maehauftrag start=15:00 duration=120 remotestart=0 after=4
			</pre>			
		</li>		
		<li>winterschlaf &lt;on, off&gt;<br>
			Wenn aktiviert, wird das Pollen unterbunden. Empfiehlt sich f&uuml;r die Winterpause.
		</li>	
		<li>user &ltuser&gt;<br>
			Alternativ zur Angabe per Argument kann per Set-Befehl der Benutzername zur Anmeldung am Robonect hier einmalig eingegeben werden. Er wird im Klartext in FhemUtils oder der DB gespeichert.<br>
			Wenn angegeben, werden die Attribute zur Authentisierung ignoriert.
		</li>		
		<li>password &lt;password&gt;<br>
			Alternativ zur Angabe per Argument kann per Set-Befehl das Passwort zur Anmeldung am Robonect hier einmalig eingegeben werden. Er wird im Klartext in FhemUtils oder der DB gespeichert.<br>
			Wenn angegeben, werden die Attribute zur Authentisierung ignoriert.
		</li>
	</ul>
  </ul>

  <p><a name="RobonectGet"></a> <b>Get</b></p>
  <ul>
	<b>Get</b>
	<ul>  
		<li>status<br>
			Holt den aktuellen Status des M&auml;hers. Wird normalerweise nicht ben&ouml;tigt, da automatisch gepolled wird.
		</li>
		<li>health<br>
			Mit diesem Kommando können detailliertere Informationen vom M&auml;her gelesen werden. Beispielsweise sind einge Spannungen und Umweltbedingungen verf&uuml;gbar.<br>
			Es werden NICHT ALLE M&Auml;HER UNTERST&Uuml;TZT!!!
			Wenn das entsprechende Attribut gesetzt ist, wird health analog status gepolled.
			This one gets more detailed information - like voltages and temperatures. It is NOT SUPPORTED BY ALL MOWERS!!!<br>
			If enabled via attribute, health is polled accordingly status.
		</li>
	</ul>
  </ul>
  
  <p><a name="RobonectAttr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="RobonectCredentials"></a> <b>credentials</b></p>
  <ul> 
    Hier kann ein Link auf ein credentials-file angegeben werden. Die Zugansinformationen werden dann aus der Datei geholt. Dieser Mechanismus &uuml;berschreibt basicAuth.
  </ul> 

  <p><a name="RobonectBasicAuth"></a> <b>basicAuth</b></p>
  <ul> 
	Hier werden die Zugangsinformationen entweder im Klartext oder base-64-codiert &uuml;bergeben. Base64-encoder gibts bei google.
      <p>Example:</p>
      <pre>
      define myMower Robonect 192.168.5.1
	  attr myMower basicAuth me:mySecret
      </pre>    
	  <pre>
      define myMower Robonect 192.168.5.1
	  attr myMower basicAuth bWU6bXlTZWNyZXQ=
      </pre>    
  </ul>	

  <p><a name="RobonectPollInterval"></a> <b>pollInterval</b></p>
  <ul>
	Hier kann das polling-interval in Sekunden angegeben werden. Default sind 90s.
  </ul>
  
  <p><a name="RobonectTimeout"></a> <b>timeout</b></p>
  <ul>
	F&uuml;r das holen der Daten per Wlan kann hier ein Timeout angegeben werden. Default sind 4s.
  </ul>

  <p><a name="RobonectHealth"></a> <b>useHealth</b></p>
  <ul>
	Wenn dieses Attribut auf 1 gesetzt wird, wird der health-status analog dem normalen Status gepolled.<br>
	Bitte beachtet, dass NICHT ALLE M&Auml;HER UNTERST&Uuml;TZT WERDEN!
	Wenn die Funktion nicht gegeben zu sein scheint, bitte den LAST_COMM_STATUS und das Logfile beachten.
  </ul>  
</ul>
=end html_DE

=cut

