# $Id$
#
# v3.4.1 
# The module is inspired by the FHEMduino project and modified in serval ways for processing the incoming messages
# see http://www.fhemwiki.de/wiki/SIGNALDuino
# It was modified also to provide support for raw message handling which can be send from the SIGNALduino
# The purpos is to use it as addition to the SIGNALduino which runs on an arduno nano or arduino uno.
# It routes Messages serval Modules which are already integrated in FHEM. But there are also modules which comes with it.
# N. Butzek, S. Butzek, 2014-2015
# S.Butzek,Ralf9 2016-2019


package main;
my $missingModulSIGNALduino="";

use strict;
use warnings;
no warnings 'portable';

eval "use Data::Dumper qw(Dumper);1";
eval "use JSON;1" or $missingModulSIGNALduino .= "JSON ";

eval "use Scalar::Util qw(looks_like_number);1";
eval "use Time::HiRes qw(gettimeofday);1" ;
use lib::SD_Protocols;

#$| = 1;		#Puffern abschalten, Hilfreich fuer PEARL WARNINGS Search

#use POSIX qw( floor);  # can be removed
#use Math::Round qw();


use constant {
	SDUINO_VERSION            => "v3.4.1",
	SDUINO_INIT_WAIT_XQ       => 1.5,       # wait disable device
	SDUINO_INIT_WAIT          => 2,
	SDUINO_INIT_MAXRETRY      => 3,
	SDUINO_CMD_TIMEOUT        => 10,
	SDUINO_KEEPALIVE_TIMEOUT  => 60,
	SDUINO_KEEPALIVE_MAXRETRY => 3,
	SDUINO_WRITEQUEUE_NEXT    => 0.3,
	SDUINO_WRITEQUEUE_TIMEOUT => 2,
	
	SDUINO_DISPATCH_VERBOSE     => 5,      # default 5
	SDUINO_MC_DISPATCH_VERBOSE  => 5,      # wenn kleiner 5, z.B. 3 dann wird vor dem dispatch mit loglevel 3 die ID und rmsg ausgegeben
	SDUINO_MC_DISPATCH_LOG_ID   => '12.1', # die o.g. Ausgabe erfolgt nur wenn der Wert mit der ID uebereinstimmt
	SDUINO_PARSE_DEFAULT_LENGHT_MIN => 8
};


sub SIGNALduino_Attr(@);
#sub SIGNALduino_Clear($);           # wird nicht mehr benoetigt
sub SIGNALduino_HandleWriteQueue($);
sub SIGNALduino_Parse($$$$@);
sub SIGNALduino_Read($);
#sub SIGNALduino_ReadAnswer($$$$);  # wird nicht mehr benoetigt
sub SIGNALduino_Ready($);
sub SIGNALduino_Write($$$);
sub SIGNALduino_SimpleWrite(@);
sub SIGNALduino_LoadProtocolHash($);
sub SIGNALduino_Log3($$$);

#my $debug=0;

our %modules;
our %defs;

# Two options are possible to specify a get command 
# Option 1 will send a serial command to the uC and wait for response. For this an array needs to be specified
# Option 2 will call a anonymous sub which does some things
my %gets = (    # Name, Data to send to the SIGNALduino, Regexp for the answer
  "version"  => ["V", 'V\s.*SIGNAL(duino|ESP).*'],
  "freeram"  => ["R", '^[0-9]+'],
#  "raw"      => ["", '.*'],
  "uptime"   => ["t", '^[0-9]+' ],
  "cmds"     => ["?", '.*Use one of[ 0-9A-Za-z]+[\r\n]*$' ],
# "ITParms"  => ["ip",'.*'],
  "ping"     => ["P",'^OK$'],
  "config"   => ["CG",'^MS.*MU.*MC.*'],
#  "protocolIDs"   => ["none",'none'],
  "ccconf"   => ["C0DnF", 'C0Dn11.*'],
  "ccreg"    => ["C", '^C.* = .*'],
  "ccpatable" => ["C3E", '^C3E = .*'],
#  "ITClock"  => ["ic", '\d+'],
#  "FAParms"  => ["fp", '.*' ],
#  "TCParms"  => ["dp", '.*' ],
#  "HXParms"  => ["hp", '.*' ]
#  "availableFirmware" => ["none",'none'],
	"availableFirmware" => sub {
  		my ($hash, @a) = @_;
  		
		if ($missingModulSIGNALduino =~ m/JSON/ )
	  	{
	  		$hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[1] failed. Pleas install Perl module JSON. Example: sudo apt-get install libjson-perl");
	 		return "$a[1]: \n\nFetching from github is not possible. Please install JSON. Example:<br><code>sudo apt-get install libjson-perl</code>";
	  	} 
	  	
	  	my $channel=AttrVal($hash->{NAME},"updateChannelFW","stable");
		my $hardware=AttrVal($hash->{NAME},"hardware",undef);
		
		my ($validHw) = $modules{$hash->{TYPE}}{AttrList} =~ /.*hardware:(.*?)\s/;  	
		$hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: found availableFirmware for $validHw");
		
		if (!defined($hardware) || $validHw !~ /$hardware(?:,|$)/ )
	  	{
	  		$hash->{logMethod}->($hash->{NAME}, 1, "$hash->{NAME}: get $a[1] failed. Please set attribute hardware first");
	 		return "$a[1]: \n\n$hash->{NAME}: get $a[1] failed. Please choose one of $validHw attribute hardware";
	  	} 
	  	SIGNALduino_querygithubreleases($hash);
		return "$a[1]: \n\nFetching $channel firmware versions for $hardware from github\n";
 	},
	"raw" => sub {
		my ($hash, @a) = @_;
	 	if ($a[2] =~ /^M[CcSU];.*/)
	  	{
			$a[2]="\002$a[2]\003";  	## Add start end end marker if not already there
			$hash->{logMethod}->($hash->{NAME}, 5, "$hash->{NAME}: msg adding start and endmarker to message");
		}
		if ($a[2] =~ /\002M.;.*;\003$/)
		{
			$hash->{logMethod}->( $hash->{NAME}, 4, "$hash->{NAME}: msg get raw: $a[2]");
			return SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $a[2]);
	  	}
	},

);


my %sets = (
  "raw"       => '',
  "flash"     => '',
  "reset"     => 'noArg',
  "close"     => 'noArg',
  #"disablereceiver"     => "",
  #"ITClock"  => 'slider,100,20,700',
  "enableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "disableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "sendMsg"		=> "",
  "cc1101_freq"    => '',
  "cc1101_bWidth"  => '58,68,81,102,116,135,162,203,232,270,325,406,464,541,650,812',
  "cc1101_rAmpl"   => '24,27,30,33,36,38,40,42',
  "cc1101_sens"    => '4,8,12,16',
  "cc1101_patable_433" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
  "cc1101_patable_868" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
);

my %patable = (
  "433" =>
  {
    "-10_dBm"  => '34',
    "-5_dBm"   => '68',
    "0_dBm"    => '60',
    "5_dBm"    => '84',
    "7_dBm"    => 'C8',
    "10_dBm"   => 'C0',
  },
  "868" =>
  {
    "-10_dBm"  => '27',
    "-5_dBm"   => '67',
    "0_dBm"    => '50',
    "5_dBm"    => '81',
    "7_dBm"    => 'CB',
    "10_dBm"   => 'C2',
  },
);


my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42); # rAmpl(dB)

## Supported Clients per default
my $clientsSIGNALduino = ":IT:"
						."CUL_TCM97001:"
						."SD_RSL:"
						."OREGON:"
						."CUL_TX:"
						."SD_AS:"
						."Hideki:"
						."SD_WS07:"
						."SD_WS09:"
						." :"					# Zeilenumbruch
						."SD_WS:"
						."RFXX10REC:"
						."Dooya:"
						."SOMFY:"
						."SD_BELL:"		## bells
						."SD_UT:"			## universal - more devices with different protocols
						."SD_WS_Maverick:"
						."FLAMINGO:"
						."CUL_WS:"
						."Revolt:"
						." :"					# Zeilenumbruch
						."FS10:"
						."CUL_FHTTK:"
						."Siro:"
						."FHT:"
						."FS20:"
						."CUL_EM:"
						."Fernotron:"
						."SD_Keeloq:"
						."SIGNALduino_un:"
					; 

## default regex match List for dispatching message to logical modules, can be updated during runtime because it is referenced
my %matchListSIGNALduino = (
			"1:IT"								=> "^i......",														# Intertechno Format
			"2:CUL_TCM97001"			=> "^s[A-Fa-f0-9]+",											# Any hex string		beginning with s
			"3:SD_RSL"						=> "^P1#[A-Fa-f0-9]{8}",
			"5:CUL_TX"						=> "^TX..........",												# Need TX to avoid FHTTK
			"6:SD_AS"							=> "^P2#[A-Fa-f0-9]{7,8}",								# Arduino based Sensors, should not be default
			"4:OREGON"						=> "^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*",
			"7:Hideki"						=> "^P12#75[A-F0-9]+",
			"9:CUL_FHTTK"					=> "^T[A-F0-9]{8}",
			"10:SD_WS07"					=> "^P7#[A-Fa-f0-9]{6}[AFaf][A-Fa-f0-9]{2,3}",
			"11:SD_WS09"					=> "^P9#F[A-Fa-f0-9]+",
			"12:SD_WS"						=> '^W\d+x{0,1}#.*',
			"13:RFXX10REC"				=> '^(20|29)[A-Fa-f0-9]+',
			"14:Dooya"						=> '^P16#[A-Fa-f0-9]+',
			"15:SOMFY"						=> '^Ys[0-9A-F]+',
			"16:SD_WS_Maverick"		=> '^P47#[A-Fa-f0-9]+',
			"17:SD_UT"						=> '^P(?:14|29|30|34|46|68|69|76|81|83|86|90|91|91.1|92|93|95)#.*',	# universal - more devices with different protocols
			"18:FLAMINGO"					=> '^P13\.?1?#[A-Fa-f0-9]+',							# Flamingo Smoke
			"19:CUL_WS"						=> '^K[A-Fa-f0-9]{5,}',
			"20:Revolt"						=> '^r[A-Fa-f0-9]{22}',
			"21:FS10"							=> '^P61#[A-F0-9]+',
			"22:Siro"							=> '^P72#[A-Fa-f0-9]+',
			"23:FHT"							=> "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
			"24:FS20"							=> "^81..(04|0c)..0101a001", 
			"25:CUL_EM"						=> "^E0.................", 
			"26:Fernotron"				=> '^P82#.*',
			"27:SD_BELL"					=> '^P(?:15|32|41|42|57|79|96)#.*',
			"28:SD_Keeloq"				=> '^P(?:87|88)#.*',
			"X:SIGNALduino_un"		=> '^[u]\d+#.*',
);



my %ProtocolListSIGNALduino;

my %symbol_map = (one => 1 , zero =>0 ,sync => '', float=> 'F', 'start' => '');

#####################################
sub SIGNALduino_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  my $dev = "";
  if (index(SDUINO_VERSION, "dev") >= 0) {
     $dev = ",1";
  }

# Provider
  $hash->{ReadFn}  = "SIGNALduino_Read";
  $hash->{WriteFn} = "SIGNALduino_Write";
  $hash->{ReadyFn} = "SIGNALduino_Ready";

# Normal devices
  $hash->{DefFn}  		 	= "SIGNALduino_Define";
  $hash->{FingerprintFn} 	= "SIGNALduino_FingerprintFn";
  $hash->{UndefFn} 		 	= "SIGNALduino_Undef";
  $hash->{GetFn}   			= "SIGNALduino_Get";
  $hash->{SetFn}   			= "SIGNALduino_Set";
  $hash->{AttrFn}  			= "SIGNALduino_Attr";
  $hash->{AttrList}			= 
                       "Clients MatchList do_not_notify:1,0 dummy:1,0"
					  ." hexFile"
                      ." initCommands"
                  	  ." flashCommand"
					  ." hardware:ESP8266,ESP8266cc1101,ESP32,nano328,nanoCC1101,miniculCC1101,promini,radinoCC1101"
					  ." updateChannelFW:stable,testing"
					  ." debug:0$dev"
					  ." longids"
					  ." minsecs"
					  ." whitelist_IDs"
					  ." blacklist_IDs"
					  ." WS09_CRCAUS:0,1,2"
					  ." addvaltrigger"
					  ." rawmsgEvent:1,0"
					  ." cc1101_frequency"
					  ." doubleMsgCheck_IDs"
					  ." suppressDeviceRawmsg:1,0"
					  ." development:0$dev"
					  ." noMsgVerbose:0,1,2,3,4,5"
					  ." eventlogging:0,1"
					  ." maxMuMsgRepeat"
		              ." $readingFnAttributes";

  $hash->{ShutdownFn}		= "SIGNALduino_Shutdown";
  $hash->{FW_detailFn}		= "SIGNALduino_FW_Detail";
  $hash->{FW_deviceOverview} = 1;
  
  $hash->{msIdList} = ();
  $hash->{muIdList} = ();
  $hash->{mcIdList} = ();
  
  #our $attr;

  
  %ProtocolListSIGNALduino = SIGNALduino_LoadProtocolHash("$attr{global}{modpath}/FHEM/lib/SD_ProtocolData.pm");

  if (exists($ProtocolListSIGNALduino{error})  ) {
  	Log3 "SIGNALduino", 1, "Error loading Protocol Hash. Module is in inoperable mode error message:($ProtocolListSIGNALduino{error})";
  	delete($ProtocolListSIGNALduino{error});
  	return undef;
  }
}
#
# Predeclare Variables from other modules may be loaded later from fhem
#
our $FW_wname;
our $FW_ME;      

#
# Predeclare Variables from other modules may be loaded later from fhem
#
our $FW_CSRF;
our $FW_detail;

# Load Protocol hash from File into a hash.
# First Parameter is for filename (full or relativ path) to be loaded
#
# returns a hash with protocols if loaded without error. Returns a hash with {eror} => errormessage if there was an error

#####################################	
sub SIGNALduino_LoadProtocolHash($) {	
	my $ret= lib::SD_Protocols::LoadHash($_[0]);
	return %$ret;
}

#####################################
sub SIGNALduino_FingerprintFn($$) {
  my ($name, $msg) = @_;

  # Store only the "relevant" part, as the Signalduino won't compute the checksum
  #$msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);

  return ("", $msg);
}

#####################################
sub SIGNALduino_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "Define, wrong syntax: define <name> SIGNALduino {none | devicename[\@baudrate] | devicename\@directio | hostname:port}";
    Log3 undef, 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);
  my $name = $a[0];

  
  if (!exists &round)
  {
      Log3 $name, 1, "$name: Define, Signalduino can't be activated (sub round not found). Please update Fhem via update command";
	  return undef;
  }
  
  my $dev = $a[2];
  #Debug "dev: $dev" if ($debug);
  #my $hardware=AttrVal($name,"hardware","nano");
  #Debug "hardware: $hardware" if ($debug);
 
 
  if($dev eq "none") {
    Log3 $name, 1, "$name: Define, device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    #return undef;
  }
  

  if ($dev ne "none" && $dev =~ m/[a-zA-Z]/ && $dev !~ m/\@/) {    # bei einer IP wird kein \@57600 angehaengt
	$dev .= "\@57600";
  }	
  
  #$hash->{CMDS} = "";
  $hash->{Clients} = $clientsSIGNALduino;
  $hash->{MatchList} = \%matchListSIGNALduino;
  $hash->{DeviceName} = $dev;
  $hash->{logMethod} = \&main::Log3;	
  
  my $ret=undef;
  
  InternalTimer(gettimeofday(), 'SIGNALduino_IdList',"sduino_IdList:$name",0);       # verzoegern bis alle Attribute eingelesen sind
  
  if($dev ne "none") {
    $ret = DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
  } else {
		$hash->{DevState} = 'initialized';
  		readingsSingleUpdate($hash, "state", "opened", 1);
  }
  
  $hash->{DMSG}="nothing";
  $hash->{LASTDMSG} = "nothing";
  $hash->{LASTDMSGID} = "nothing";
  $hash->{TIME}=time();
  $hash->{versionmodul} = SDUINO_VERSION;
  $hash->{versionProtocols} = lib::SD_Protocols::getProtocolVersion();
  #notifyRegexpChanged($hash,"^$name$:^opened\$");  # Auf das Event opened der eigenen Definition reagieren
  #notifyRegexpChanged($hash,"sduino:opened");  # Auf das Event opened der eigenen Definition reagieren
  #$hash->{NOTIFYDEV}="$name";
  Log3 $name, 3, "$name: Define, Firmwareversion: ".$hash->{READINGS}{version}{VAL}  if ($hash->{READINGS}{version}{VAL});

  return $ret;
}

###############################
sub SIGNALduino_Connect($$) {
	my ($hash, $err) = @_;

	# damit wird die err-msg nur einmal ausgegeben
	if (!defined($hash->{disConnFlag}) && $err) {
		$hash->{logMethod}->($hash->{NAME}, 3, "$hash->{NAME}: Connect, ${err}");
		$hash->{disConnFlag} = 1;
	}
}

###############################
sub SIGNALduino_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        $hash->{logMethod}->($name, $lev, "$name: Undef, deleting port for $d");
        delete $defs{$d}{IODev};
      }
  }

  SIGNALduino_Shutdown($hash);
  
  DevIo_CloseDev($hash); 
  RemoveInternalTimer($hash);    
  return undef;
}

###############################
sub SIGNALduino_Shutdown($) {
  my ($hash) = @_;
  #DevIo_SimpleWrite($hash, "XQ\n",2);
  SIGNALduino_SimpleWrite($hash, "XQ");  # Switch reception off, it may hang up the SIGNALduino
  return undef;
}

###############################
sub SIGNALduino_flash($) {
	my $name = shift;
	my $hash = $defs{$name};
	
	if (defined($hash->{helper}{stty_pid}))
	{
		waitpid( $hash->{helper}{stty_pid}, 0 );
		delete ( $hash->{helper}{stty_pid});
	}
	
	readingsSingleUpdate($hash,"state","FIRMWARE UPDATE running",1);
	$hash->{helper}{avrdudelogs} .= "$name closed\n";
    my $logFile = AttrVal("global", "logdir", "./log/") . "$hash->{TYPE}-Flash.log";

    if (-e $logFile) {
	    unlink $logFile;
    }

    $hash->{helper}{avrdudecmd} =~ s/\Q[LOGFILE]\E/$logFile/g;
	local $SIG{CHLD} = 'DEFAULT';
	delete($hash->{FLASH_RESULT}) if (exists($hash->{FLASH_RESULT}));

	qx($hash->{helper}{avrdudecmd});


	if ($? != 0 )
	{
		readingsSingleUpdate($hash,"state","FIRMWARE UPDATE with error",1);    # processed in tests
		$hash->{logMethod}->($name ,3, "$name: flash, ERROR: avrdude exited with error $?");
		FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", "FW_okDialog('ERROR: avrdude exited with error, for details see last flashlog.')", "");
		$hash->{FLASH_RESULT}="ERROR: avrdude exited with error";              # processed in tests
	} else {
		$hash->{logMethod}->($name ,3, "$name: flash, Firmware update was successfull");
		readingsSingleUpdate($hash,"state","FIRMWARE UPDATE successfull",1);   # processed in tests
	}
	 
	local $/=undef;
	if (-e $logFile) {
		open FILE, $logFile;
	 	$hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
		$hash->{helper}{avrdudelogs} .= <FILE>;
	    $hash->{helper}{avrdudelogs} .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
	    close FILE;
	} else {
		$hash->{helper}{avrdudelogs} .= "WARNING: avrdude created no log file\n\n";
		readingsSingleUpdate($hash,"state","FIRMWARE UPDATE with error",1);
		$hash->{FLASH_RESULT}= "WARNING: avrdude created no log file";         # processed in tests
	}
	
	DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
	$hash->{helper}{avrdudelogs} .= "$name reopen started\n";
	return $hash->{FLASH_RESULT};
}


#$hash,$name,"sendmsg","P17;R6#".substr($arg,2)
###############################
sub SIGNALduino_Set($$@) {
  my ($hash,$name, @a) = @_;
  
  return "\"set SIGNALduino\" needs at least one parameter" if(@a < 1);

  #SIGNALduino_Log3 $hash, 3, "$name: Set, called with params @a";


  my $CC1101Frequency;
  if (exists($hash->{hasCC1101}) && InternalVal($name,"hasCC1101",0)) {
    if (!defined($hash->{cc1101_frequency})) {
       $CC1101Frequency = "433";
    } else {
       $CC1101Frequency = $hash->{cc1101_frequency};
    }
  }
  my %my_sets = %sets;
  %my_sets = ( %my_sets,  %{$hash->{additionalSets}} ) if ( defined($hash->{additionalSets}) );
  
  if (!defined($my_sets{$a[0]})) {
    my $arguments = ' ';
    foreach my $arg (sort keys %my_sets) {
      next if ($arg =~ m/cc1101/ && !InternalVal($name,"hasCC1101",0));
      if ($arg =~ m/patable/) {
        next if (substr($arg, -3) ne $CC1101Frequency);
      }
      $arguments.= $arg . ($my_sets{$arg} ? (':' . $my_sets{$arg}) : '') . ' ';
    }
    #SIGNALduino_Log3 $hash, 3, "$name: Set, arg = $arguments";
    return "Unknown argument $a[0], choose one of " . $arguments;
  }

  my $cmd = shift @a;
  my $arg = join(" ", @a);
  
  if ($cmd =~ m/cc1101/ && !InternalVal($name,"hasCC1101",0)) {
    return "This command is only available with a cc1101 receiver";
  }
  
  return "$name is not active, may firmware is not suppoted, please flash or reset" if ($cmd ne 'reset' && $cmd ne 'flash' && exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');

  if ($cmd =~ m/^cc1101_/) {
     $cmd = substr($cmd,7);
  }
  
  if($cmd eq "raw") {
    $hash->{logMethod}->($name, 4, "$name: Set, $cmd $arg");
    #SIGNALduino_SimpleWrite($hash, $arg);
    SIGNALduino_AddSendQueue($hash,$arg);
  } elsif( $cmd eq "flash" ) {
    my @args = split(' ', $arg);
    my $log = "";
    my $hexFile = "";
    my ($port,undef) = split('@', $hash->{DeviceName});
	my $hardware=AttrVal($name,"hardware","");
	my $baudrate= 57600;
    return "Please define your hardware! (attr $name hardware <model of your receiver>) " if ($hardware eq "");
	return "ERROR: argument failed! flash [hexFile|url]" if (!$args[0]);
    
	if( grep $args[0] eq $_ , split(",",$my_sets{flash}) )
	{
		$hash->{logMethod}->($hash, 3, "$name: Set, flash $args[0] try to fetch github assets for tag $args[0]");

		my $ghurl = "https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases/tags/$args[0]";

		$hash->{logMethod}->($hash, 3, "$name: Set, flash $args[0] try to fetch release $ghurl");
		
	    my $http_param = {
                    url        => $ghurl,
                    timeout    => 5,
                    hash       => $hash,                                                                                 # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                    method     => "GET",                                                                                 # Lesen von Inhalten
                    header     => "User-Agent: perl_fhem\r\nAccept: application/json",  								 # Den Header gemaess abzufragender Daten aendern
                    callback   =>  \&SIGNALduino_githubParseHttpResponse,                                                # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                    command    => "getReleaseByTag"
                    
                };
   		HttpUtils_NonblockingGet($http_param);                                                                           # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 
		return;
	} 
    elsif ($args[0] =~ m/^https?:\/\// ) {
		my $http_param = {
		                    url        => $args[0],
		                    timeout    => 5,
		                    hash       => $hash,                                  # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		                    method     => "GET",                                  # Lesen von Inhalten
		                    callback   =>  \&SIGNALduino_ParseHttpResponse,       # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
		                    command    => 'flash',
		                };
		
		HttpUtils_NonblockingGet($http_param);       
		return;  	
    } else {
      $hexFile = $args[0];
    }
	$hash->{logMethod}->($name, 3, "$name: Set, filename $hexFile provided, trying to flash");

	# Only for Arduino , not for ESP
	if ($hardware =~ m/(?:nano|mini|radino)/)
	{
		
		my $avrdudefound=0;
		my $tool_name = "avrdude"; 
		my $path_separator = ':';
		if ($^O eq 'MSWin32') {
			$tool_name .= ".exe";
			$path_separator = ';';
		}
		for my $path ( split /$path_separator/, $ENV{PATH} ) {
			if ( -f "$path/$tool_name" && -x _ ) {
				$avrdudefound=1;
				last;
			}
		}
		$hash->{logMethod}->($name, 5, "$name: Set, avrdude found = $avrdudefound");
		return "avrdude is not installed. Please provide avrdude tool example: sudo apt-get install avrdude" if($avrdudefound == 0);

		$log .= "flashing Arduino $name\n";
		$log .= "hex file: $hexFile\n";
		$log .= "port: $port\n";
	
		# prepare default Flashcommand
		my $defaultflashCommand = ($hardware eq "radinoCC1101" ? "avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]" : "avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]");
		
		# get User defined Flashcommand
		my $flashCommand = AttrVal($name,"flashCommand",$defaultflashCommand);
		
		if ($defaultflashCommand eq $flashCommand)	{
			$hash->{logMethod}->($name, 5, "$name: Set, standard flashCommand is used to flash.");
		} else {
			$hash->{logMethod}->($name, 3, "$name: Set, custom flashCommand is manual defined! $flashCommand");
		}
		
		DevIo_CloseDev($hash);
		if ($hardware eq "radinoCC1101" && $^O eq 'linux') {
			$hash->{logMethod}->($name, 3, "$name: Set, forcing special reset for $hardware on $port");
			# Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen
			use IPC::Open3;
 	
			my($chld_out, $chld_in, $chld_err);
			use Symbol 'gensym';
			$chld_err = gensym;
			my $pid;
			eval {
				$pid = open3($chld_in,$chld_out, $chld_err,  "stty -F $port ospeed 1200 ispeed 1200");
	 			close($chld_in);  # give end of file to kid, or feed him
			};
			if ($@) {
				$hash->{helper}{stty_output}=$@;
			} else {
				my @outlines = <$chld_out>;              # read till EOF
				my @errlines = <$chld_err>;              # XXX: block potential if massive
				$hash->{helper}{stty_pid}=$pid;
		  		$hash->{helper}{stty_output} = join(" ",@outlines).join(" ",@errlines);
			}
			$port =~ s/usb-Unknown_radino/usb-In-Circuit_radino/g;
			$hash->{logMethod}->($name ,3, "$name: Set, changed usb port to \"$port\" for avrdude flashcommand compatible with radino");
		}
		$hash->{helper}{avrdudecmd} = $flashCommand;
		$hash->{helper}{avrdudecmd}=~ s/\Q[PORT]\E/$port/g;
		$hash->{helper}{avrdudecmd} =~ s/\Q[HEXFILE]\E/$hexFile/g;
		if ($hardware =~ "^nano" && $^O eq 'linux') {
			$hash->{logMethod}->($name ,5, "$name: Set, try additional flash with baudrate 115200 for optiboot");
			$hash->{helper}{avrdudecmd} = $hash->{helper}{avrdudecmd}." || ". $hash->{helper}{avrdudecmd}; 
			$hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
			$baudrate=115200;
		}	
		$hash->{helper}{avrdudecmd} =~ s/\Q[BAUDRATE]\E/$baudrate/;
		$log .= "command: $hash->{helper}{avrdudecmd}\n\n";
		InternalTimer(gettimeofday() + 1,"SIGNALduino_flash",$name);
	 	$hash->{helper}{avrdudelogs} = $log;
	    return undef;
	} else {
		FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", "FW_okDialog('<u>ERROR:</u><br>Sorry, flashing your ESP is currently not supported.<br>The file is only downloaded in /opt/fhem/FHEM/firmware.')", "");
		return "Sorry, Flashing your ESP via Module is currently not supported.";    # processed in tests
	}
	
  } elsif ($cmd =~ m/reset/i) {
	delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
	return SIGNALduino_ResetDevice($hash);
  } elsif( $cmd eq "close" ) {
	$hash->{DevState} = 'closed';
	return SIGNALduino_CloseDevice($hash);
  } elsif( $cmd eq "disableMessagetype" ) {
	my $argm = 'CD' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	$hash->{logMethod}->($name, 4, "$name: Set, $cmd $arg $argm");
  } elsif( $cmd eq "enableMessagetype" ) {
	my $argm = 'CE' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	$hash->{logMethod}->($name, 4, "$name: Set, $cmd $arg $argm");
  } elsif( $cmd eq "freq" ) {
	if ($arg eq "") {
		$arg = AttrVal($name,"cc1101_frequency", 433.92);
	}
	my $f = $arg/26*65536;
	my $f2 = sprintf("%02x", $f / 65536);
	my $f1 = sprintf("%02x", int($f % 65536) / 256);
	my $f0 = sprintf("%02x", $f % 256);
	$arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
	$hash->{logMethod}->($name, 3, "$name: Set, Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz");
	SIGNALduino_AddSendQueue($hash,"W0F$f2");
	SIGNALduino_AddSendQueue($hash,"W10$f1");
	SIGNALduino_AddSendQueue($hash,"W11$f0");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "bWidth" ) {
	SIGNALduino_AddSendQueue($hash,"C10");
	$hash->{getcmd}->{cmd} = "bWidth";
	$hash->{getcmd}->{arg} = $arg;
  } elsif( $cmd eq "rAmpl" ) {
	return "a numerical value between 24 and 42 is expected" if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
	my ($v, $w);
	for($v = 0; $v < @ampllist; $v++) {
		last if($ampllist[$v] > $arg);
	}
	$v = sprintf("%02d", $v-1);
	$w = $ampllist[$v];
	$hash->{logMethod}->($name, 3, "$name: Set, Setting AGCCTRL2 (1B) to $v / $w dB");
	SIGNALduino_AddSendQueue($hash,"W1D$v");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sens" ) {
	return "a numerical value between 4 and 16 is expected" if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
	my $w = int($arg/4)*4;
	my $v = sprintf("9%d",$arg/4-1);
	$hash->{logMethod}->($name, 3, "$name: Set, Setting AGCCTRL0 (1D) to $v / $w dB");
	SIGNALduino_AddSendQueue($hash,"W1F$v");
	SIGNALduino_WriteInit($hash);
  } elsif( substr($cmd,0,7) eq "patable" ) {
	my $paFreq = substr($cmd,8);
	my $pa = "x" . $patable{$paFreq}{$arg};
	$hash->{logMethod}->($name, 3, "$name: Set, Setting patable $paFreq $arg $pa");
	SIGNALduino_AddSendQueue($hash,$pa);
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sendMsg" ) {
	$hash->{logMethod}->($name, 5, "$name: Set, sendmsg msg=$arg");
	
	# Split args in serval variables
	my ($protocol,$data,$repeats,$clock,$frequency,$datalength,$dataishex);
	my $n=0;
	foreach my $s (split "#", $arg) {
	    my $c = substr($s,0,1);
	    if ($n == 0 ) {  #  protocol
			$protocol = substr($s,1);
	    } elsif ($n == 1) { # Data
	        $data = $s;
	        if   ( substr($s,0,2) eq "0x" ) { $dataishex=1; $data=substr($data,2); }
	        else { $dataishex=0; }
	        
	    } else {
	    	    if ($c eq 'R') { $repeats = substr($s,1);  }
	    		elsif ($c eq 'C') { $clock = substr($s,1);   }
	    		elsif ($c eq 'F') { $frequency = substr($s,1);  }
	    		elsif ($c eq 'L') { $datalength = substr($s,1);   }
	    }
	    $n++;
	}
	return "$name: sendmsg, unknown protocol: $protocol" if (!exists($ProtocolListSIGNALduino{$protocol}));

	$repeats=1 if (!defined($repeats));

	if (exists($ProtocolListSIGNALduino{$protocol}{frequency}) && InternalVal($name,"hasCC1101",0) && !defined($frequency)) {
		$frequency = $ProtocolListSIGNALduino{$protocol}{frequency};
	}
	if (defined($frequency) && InternalVal($name,"hasCC1101",0)) {
		$frequency="F=$frequency;";
	} else {
		$frequency="";
	}
	
	#print ("data = $data \n");
	#print ("protocol = $protocol \n");
    #print ("repeats = $repeats \n");
    
	my %signalHash;
	my %patternHash;
	my $pattern="";
	my $cnt=0;
	
	my $sendData;
	if  (exists($ProtocolListSIGNALduino{$protocol}{format}) && $ProtocolListSIGNALduino{$protocol}{format} eq 'manchester')
	{
		#$clock = (map { $clock += $_ } @{$ProtocolListSIGNALduino{$protocol}{clockrange}}) /  2 if (!defined($clock));
		
		$clock += $_ for(@{$ProtocolListSIGNALduino{$protocol}{clockrange}});
		$clock = round($clock/2,0);
		if ($protocol == 43) {
			#$data =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
		}
		
		my $intro = "";
		my $outro = "";
		
		$intro = $ProtocolListSIGNALduino{$protocol}{msgIntro} if ($ProtocolListSIGNALduino{$protocol}{msgIntro});
		$outro = $ProtocolListSIGNALduino{$protocol}{msgOutro}.";" if ($ProtocolListSIGNALduino{$protocol}{msgOutro});

		if ($intro ne "" || $outro ne "")
		{
			$intro = "SC;R=$repeats;" . $intro;
			$repeats = 0;
		}

		$sendData = $intro . "SM;" . ($repeats > 0 ? "R=$repeats;" : "") . "C=$clock;D=$data;" . $outro . $frequency; #	SM;R=2;C=400;D=AFAFAF;
		$hash->{logMethod}->($name, 5, "$name: Set, sendmsg Preparing manchester protocol=$protocol, repeats=$repeats, clock=$clock data=$data");

	} else {
		if ($protocol == 3 || substr($data,0,2) eq "is") {
			if (substr($data,0,2) eq "is") {
				$data = substr($data,2);   # is am Anfang entfernen
			}
			$data = SIGNALduino_ITV1_tristateToBit($data);
			$hash->{logMethod}->($name, 5, "$name: Set, sendmsg IT V1 convertet tristate to bits=$data");
		}
		if (!defined($clock)) {
			$hash->{ITClock} = 250 if (!defined($hash->{ITClock}));   # Todo: Klaeren wo ITClock verwendet wird und ob wir diesen Teil nicht auf Protokoll 3,4 und 17 minimieren
			$clock=$ProtocolListSIGNALduino{$protocol}{clockabs} > 1 ?$ProtocolListSIGNALduino{$protocol}{clockabs}:$hash->{ITClock};
		}
		
		if ($dataishex == 1)	
		{
			# convert hex to bits
	        my $hlen = length($data);
	        my $blen = $hlen * 4;
	        $data = unpack("B$blen", pack("H$hlen", $data));
		}

		$hash->{logMethod}->($name, 5, "$name: Set, sendmsg Preparing rawsend command for protocol=$protocol, repeats=$repeats, clock=$clock bits=$data");
		
		foreach my $item (qw(preSync sync start one zero float pause end universal))
		{
		    #print ("item= $item \n");
		    next if (!exists($ProtocolListSIGNALduino{$protocol}{$item}));
		    
			foreach my $p (@{$ProtocolListSIGNALduino{$protocol}{$item}})
			{
			    #print (" p = $p \n");
			    
			    if (!exists($patternHash{$p}))
				{
					$patternHash{$p}=$cnt;
					$pattern.="P".$patternHash{$p}."=".$p*$clock.";";
					$cnt++;
				}
		    	$signalHash{$item}.=$patternHash{$p};
			   	#print (" signalHash{$item} = $signalHash{$item} \n");
			}
		}
		my @bits = split("", $data);
	
		my %bitconv = (1=>"one", 0=>"zero", 'D'=> "float", 'F'=> "float", 'P'=> "pause", 'U'=> "universal");
		my $SignalData="D=";
		
		$SignalData.=$signalHash{preSync} if (exists($signalHash{preSync}));
		$SignalData.=$signalHash{sync} if (exists($signalHash{sync}));
		$SignalData.=$signalHash{start} if (exists($signalHash{start}));
		foreach my $bit (@bits)
		{
			next if (!exists($bitconv{$bit}));
			#SIGNALduino_Log3 $name, 5, "$name: Set, encoding $bit";
			$SignalData.=$signalHash{$bitconv{$bit}}; ## Add the signal to our data string
		}
		$SignalData.=$signalHash{end} if (exists($signalHash{end}));
		$sendData = "SR;R=$repeats;$pattern$SignalData;$frequency";
	}

	
	#SIGNALduino_SimpleWrite($hash, $sendData);
	SIGNALduino_AddSendQueue($hash,$sendData);
	$hash->{logMethod}->($name, 4, "$name: Set, sending via SendMsg: $sendData");
  } else {
  	$hash->{logMethod}->($name, 5, "$name: Set, $cmd $arg");
	#SIGNALduino_SimpleWrite($hash, $arg);
	return "Unknown argument $cmd, choose one of ". ReadingsVal($name,'cmd',' help me');
  }

  return undef;
}

###############################
sub SIGNALduino_Get($@) {
	my ($hash, @a) = @_;
	my $type = $hash->{TYPE};
	my $name = $hash->{NAME};
	return "$name is not active, may firmware is not suppoted, please flash or reset" if (exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');	
		  
	$hash->{logMethod}->($name, 5, "$name: Get, $type\" needs at least one parameter") if(@a < 2);
	return "\"get $type\" needs at least one parameter" if(@a < 2);
	if(!defined($gets{$a[1]})) {
		Log3 ($name, 5, "Unknown argument $a[1] for $a[0]") if ($a[1] ne "?");
		my @cList = sort map { $_ =~ m/^(raw|ccreg)$/ ? $_ : "$_:noArg" } grep { (( InternalVal($a[0],"hasCC1101",0) || (!InternalVal($a[0],"hasCC1101",0) && $_ !~ /^cc/)) &&  (!IsDummy($a[0]) || IsDummy($a[0]) && $_ =~ m/^(availableFirmware|raw)/)) }   keys %gets;
		return "Unknown argument $a[1], choose one of " . join(" ", @cList);
	}
	return "no command to send, get aborted." if (ref $gets{$a[1]} eq 'ARRAY' && length($gets{$a[1]}[0]) == 0 && length($a[2]) == 0);
	  
	if (($a[1] eq "ccconf" || $a[1] eq "ccreg" || $a[1] eq "ccpatable") && !InternalVal($name,"hasCC1101",0)) {
		return "This command is only available with a cc1101 receiver";
	}
	  
	if (ref $gets{$a[1]} eq 'ARRAY') { # Option 1 
		$hash->{logMethod}->($name, 5, "$name: Get, command for gets: " . $gets{$a[1]}[0] . " " . $a[2]);
		SIGNALduino_AddSendQueue($hash, $gets{$a[1]}[0] . $a[2]); 
		$hash->{getcmd}->{cmd}=$a[1];
		$hash->{getcmd}->{asyncOut}=$hash->{CL};
		$hash->{getcmd}->{timenow}=time();
	} elsif ( ref $gets{$a[1]} eq 'CODE') { # Option 2
		return $gets{$a[1]}->($hash,@a); 
	}
	return undef; # We will exit here, and give an output only, if any output is supported. If this is not supported, only the readings are updated
}

###############################
sub SIGNALduino_parseResponse($$$) {
	my $hash = shift;
	my $cmd = shift;
	my $msg = shift;

	my $name=$hash->{NAME};
	
  	$msg =~ s/[\r\n]//g;

	if($cmd eq "cmds") 
	{       # nice it up
	    $msg =~ s/$name cmds =>//g;
   		$msg =~ s/.*Use one of//g;
 	} 
 	elsif($cmd eq "uptime") 
 	{   # decode it
   		#$msg = hex($msg);              # /125; only for col or coc
    	$msg = sprintf("%d %02d:%02d:%02d", $msg/86400, ($msg%86400)/3600, ($msg%3600)/60, $msg%60);
  	}
  	elsif($cmd eq "ccregAll")
  	{
		$msg =~ s/  /\n/g;
		$msg = "\n\n" . $msg
  	}
  	elsif($cmd eq "ccconf")
  	{
		my (undef,$str) = split('=', $msg);
		my $var;
		my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"11"=>1,"1B"=>1,"1D"=>1 );
		$msg = "";
		foreach my $a (sort keys %r) {
			$var = substr($str,(hex($a)-13)*2, 2);
			$r{$a} = hex($var);
		}
		$msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB  (DataRate:%.2fBaud)",
		26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
		26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
		$ampllist[$r{"1B"}&7],                                          #rAmpl
		4+4*($r{"1D"}&3),                                               #Sens
		((256+$r{"11"})*(2**($r{"10"} & 15 )))*26000000/(2**28)         #DataRate
		);
	}
	elsif($cmd eq "bWidth") {
		my $val = hex(substr($msg,6));
		my $arg = $hash->{getcmd}->{arg};
		my $ob = $val & 0x0f;
		
		my ($bits, $bw) = (0,0);
		OUTERLOOP:
		for (my $e = 0; $e < 4; $e++) {
			for (my $m = 0; $m < 4; $m++) {
				$bits = ($e<<6)+($m<<4);
				$bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
				last OUTERLOOP if($arg >= $bw);
			}
		}

		$ob = sprintf("%02x", $ob+$bits);
		$msg = "Setting MDMCFG4 (10) to $ob = $bw KHz";
		$hash->{logMethod}->($name, 3, "$name: parseResponse, bWidth: Setting MDMCFG4 (10) to $ob = $bw KHz");
		delete($hash->{getcmd});
		SIGNALduino_AddSendQueue($hash,"W12$ob");
		SIGNALduino_WriteInit($hash);
	}
	elsif($cmd eq "ccpatable") {
		my $CC1101Frequency = "433";
		if (defined($hash->{cc1101_frequency})) {
			$CC1101Frequency = $hash->{cc1101_frequency};
		}
		my $dBn = substr($msg,9,2);
		$hash->{logMethod}->($name, 3, "$name: parseResponse, patable: $dBn");
		foreach my $dB (keys %{ $patable{$CC1101Frequency} }) {
			if ($dBn eq $patable{$CC1101Frequency}{$dB}) {
				$hash->{logMethod}->($name, 5, "$name: parseResponse, patable: $dB");
				$msg .= " => $dB";
				last;
			}
		}
	#	$msg .=  "\n\n$CC1101Frequency MHz\n\n";
	#	foreach my $dB (keys $patable{$CC1101Frequency})
	#	{
	#		$msg .= "$patable{$CC1101Frequency}{$dB}  $dB\n";
	#	}
	}
	
  	return $msg;
}


###############################
sub SIGNALduino_ResetDevice($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	if (!defined($hash->{helper}{resetInProgress}))
	{
		my $hardware = AttrVal($name,"hardware","");
		$hash->{logMethod}->($name, 3, "$name: ResetDevice, $hardware"); 
		DevIo_CloseDev($hash);
	 	if ($hardware eq "radinoCC1101" && $^O eq 'linux') {
			# The reset is triggered when the Micro's virtual (CDC) serial / COM port is opened at 1200 baud and then closed.
			# When this happens, the processor will reset, breaking the USB connection to the computer (meaning that the virtual serial / COM port will disappear).
			# After the processor resets, the bootloader starts, remaining active for about 8 seconds.
			# The bootloader can also be initiated by pressing the reset button on the Micro.
			# Note that when the board first powers up, it will jump straight to the user sketch, if present, rather than initiating the bootloader.	
			my ($dev, $baudrate) = split("@", $hash->{DeviceName});
			$hash->{logMethod}->($name, 3, "$name: ResetDevice, forcing special reset for $hardware on $dev");
			# Mit dem Linux-Kommando 'stty' die Port-Einstellungen setzen
			system("stty -F $dev ospeed 1200 ispeed 1200");
			$hash->{helper}{resetInProgress}=1;
			InternalTimer(gettimeofday()+10,"SIGNALduino_ResetDevice",$hash);
			$hash->{logMethod}->($name, 3, "$name: ResetDevice, reopen delayed for 10 second"); 
			return;
		}
	} else {
		delete($hash->{helper}{resetInProgress});
	}
 	DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
}

###############################
sub SIGNALduino_CloseDevice($) {
	my ($hash) = @_;

	$hash->{logMethod}->($hash->{NAME}, 2, "$hash->{NAME}: CloseDevice, closed"); 
	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	readingsSingleUpdate($hash, "state", "closed", 1);
	
	return undef;
}

###############################
sub SIGNALduino_DoInit($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $err;
	my $msg = undef;

	my ($ver, $try) = ("", 0);
	#Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing
  	$hash->{logMethod}->($hash, 1, "$name: DoInit, ".$hash->{DEF});
  
	delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});
	
	RemoveInternalTimer("HandleWriteQueue:$name");
    @{$hash->{QUEUE}} = ();
    $hash->{sendworking} = 0;
    
    if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
	{
		$hash->{logMethod}->($hash, 1, "$name: DoInit, ".$hash->{DEF});
		$hash->{initretry} = 0;
		RemoveInternalTimer($hash);
		
		#SIGNALduino_SimpleWrite($hash, "XQ"); # Disable receiver
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT_XQ, "SIGNALduino_SimpleWrite_XQ", $hash, 0);
		
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT, "SIGNALduino_StartInit", $hash, 0);
	}
	# Reset the counter
	delete($hash->{XMIT_TIME});
	delete($hash->{NR_CMD_LAST_H});
	
	return;
	return undef;
}


###############################
# Disable receiver
sub SIGNALduino_SimpleWrite_XQ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{logMethod}->($hash, 3, "$name: SimpleWrite_XQ, disable receiver (XQ)");
	SIGNALduino_SimpleWrite($hash, "XQ");
	#DevIo_SimpleWrite($hash, "XQ\n",2);
}

###############################
sub SIGNALduino_StartInit($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	$hash->{version} = undef;
	
	$hash->{logMethod}->($name,3 , "$name: StartInit, get version, retry = " . $hash->{initretry});
	if ($hash->{initretry} >= SDUINO_INIT_MAXRETRY) {
		$hash->{DevState} = 'INACTIVE';
		# einmaliger reset, wenn danach immer noch 'init retry count reached', dann SIGNALduino_CloseDevice()
		if (!defined($hash->{initResetFlag})) {
			$hash->{logMethod}->($name,2 , "$name: StartInit, retry count reached. Reset");
			$hash->{initResetFlag} = 1;
			SIGNALduino_ResetDevice($hash);
		} else {
			$hash->{logMethod}->($name,2 , "$name: StartInit, init retry count reached. Closed");
			SIGNALduino_CloseDevice($hash);
		}
		return;
	}
	else {
		$hash->{getcmd}->{cmd} = "version";
		SIGNALduino_SimpleWrite($hash, "V");
		#DevIo_SimpleWrite($hash, "V\n",2);
		$hash->{DevState} = 'waitInit';
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday() + SDUINO_CMD_TIMEOUT, "SIGNALduino_CheckCmdResp", $hash, 0);
	}
}

###############################
sub SIGNALduino_CheckCmdResp($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $msg = undef;
	my $ver;
	
	if ($hash->{version}) {
		$ver = $hash->{version};
		if ($ver !~ m/SIGNAL(duino|ESP)/) {
			$msg = "$name: CheckCmdResp, Not an SIGNALduino device, setting attribute dummy=1 got for V:  $ver";
			$hash->{logMethod}->($hash, 1, $msg);
			readingsSingleUpdate($hash, "state", "no SIGNALduino found", 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
 			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		elsif($ver =~ m/^V 3\.1\./) {
			$msg = "$name: CheckCmdResp, Version of your arduino is not compatible, pleas flash new firmware. (device closed) Got for V:  $ver";
			readingsSingleUpdate($hash, "state", "unsupported firmware found", 1); #uncoverable statement because state is overwritten by SIGNALduino_CloseDevice
			$hash->{logMethod}->($hash, 1, $msg);
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		else {
			readingsSingleUpdate($hash, "state", "opened", 1);
			$hash->{logMethod}->($name, 2, "$name: CheckCmdResp, initialized " . SDUINO_VERSION);
			$hash->{DevState} = 'initialized';
			delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
			SIGNALduino_SimpleWrite($hash, "XE"); # Enable receiver
			$hash->{logMethod}->($hash, 3, "$name: CheckCmdResp, enable receiver (XE) ");
			delete($hash->{initretry});
			# initialize keepalive
			$hash->{keepalive}{ok}    = 0;
			$hash->{keepalive}{retry} = 0;
			InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash, 0);
		 	$hash->{hasCC1101} = 1  if ($ver =~ m/cc1101/);
		}
	}
	else {
		delete($hash->{getcmd});
		$hash->{initretry} ++;
		#InternalTimer(gettimeofday()+1, "SIGNALduino_StartInit", $hash, 0);
		SIGNALduino_StartInit($hash);
	}
}


###############################
# Check if the 1% limit is reached and trigger notifies
sub SIGNALduino_XmitLimitCheck($$) {
  my ($hash,$fn) = @_;
  
  return if ($fn !~ m/^(is|SR).*/);

  my $now = time();

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    $hash->{logMethod}->($name, 2, "$name: XmitLimitCheck, TRANSMIT LIMIT EXCEEDED");
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

###############################
## API to logical modules: Provide as Hash of IO Device, type of function ; command to call ; message to send
sub SIGNALduino_Write($$$) {
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  if ($fn eq "") {
    $fn="RAW" ;
  }
  elsif($fn eq "04" && substr($msg,0,6) eq "010101") {   # FS20
    $fn="sendMsg";
    $msg = substr($msg,6);
    $msg = SIGNALduino_PreparingSend_FS20_FHT(74, 6, $msg);
  }
  elsif($fn eq "04" && substr($msg,0,6) eq "020183") {   # FHT
    $fn="sendMsg";
    $msg = substr($msg,6,4) . substr($msg,10);     # was ist der Unterschied zu "$msg = substr($msg,6);" ?
    $msg = SIGNALduino_PreparingSend_FS20_FHT(73, 12, $msg);
  }
  $hash->{logMethod}->($name, 5, "$name: Write, sending via Set $fn $msg");
  
  SIGNALduino_Set($hash,$name,$fn,$msg);
}

###############################
sub SIGNALduino_AddSendQueue($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  push(@{$hash->{QUEUE}}, $msg);
  
  #SIGNALduino_Log3 $hash , 5, Dumper($hash->{QUEUE});
  
  $hash->{logMethod}->($hash, 5,"$name: AddSendQueue, " . $hash->{NAME} . ": $msg (" . @{$hash->{QUEUE}} . ")");
  InternalTimer(gettimeofday() + 0.1, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name") if (@{$hash->{QUEUE}} == 1 && $hash->{sendworking} == 0);
}

###############################
sub SIGNALduino_SendFromQueue($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  if($msg ne "") {
	SIGNALduino_XmitLimitCheck($hash,$msg);
    #DevIo_SimpleWrite($hash, $msg . "\n", 2);
    $hash->{sendworking} = 1;
    SIGNALduino_SimpleWrite($hash,$msg);
    if ($msg =~ m/^S(R|C|M);/) {
       $hash->{getcmd}->{cmd} = 'sendraw';
       $hash->{logMethod}->($name, 4, "$name: SendFromQueue, msg=$msg"); # zu testen der Queue, kann wenn es funktioniert auskommentiert werden
    } 
    elsif ($msg eq "C99") {
       $hash->{getcmd}->{cmd} = 'ccregAll';
    }
  }

  ##############
  # Write the next buffer not earlier than 0.23 seconds
  # else it will be sent too early by the SIGNALduino, resulting in a collision, or may the last command is not finished
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_TIMEOUT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  } else {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_NEXT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  }
}

###############################
sub SIGNALduino_HandleWriteQueue($) {
  my($param) = @_;
  my(undef,$name) = split(':', $param);
  my $hash = $defs{$name};
  
  #my @arr = @{$hash->{QUEUE}};
  
  $hash->{sendworking} = 0;       # es wurde gesendet
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
    $hash->{logMethod}->($name, 4, "$name: HandleWriteQueue, sendraw no answer (timeout)");
    delete($hash->{getcmd});
  }
	  
  if(exists($hash->{QUEUE}) && @{$hash->{QUEUE}}) {
    my $msg= shift(@{$hash->{QUEUE}});

    if($msg eq "") {
      SIGNALduino_HandleWriteQueue("x:$name");
    } else {
      SIGNALduino_SendFromQueue($hash, $msg);
    }
  } else {
  	 $hash->{logMethod}->($name, 4, "$name: HandleWriteQueue, nothing to send, stopping timer");
  	 RemoveInternalTimer("HandleWriteQueue:$name");
  }
}

###############################
# called from the global loop, when the select for hash->{FD} reports data
sub SIGNALduino_Read($) {
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my $debug = AttrVal($name,"debug",0);

  my $SIGNALduinodata = $hash->{PARTIAL};
  $hash->{logMethod}->($name, 5, "$name: Read, RAW: $SIGNALduinodata/$buf") if ($debug);
  $SIGNALduinodata .= $buf;

  while($SIGNALduinodata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$SIGNALduinodata) = split("\n", $SIGNALduinodata, 2);
    $rmsg =~ s/\r//;
    
    if ($rmsg =~ m/^\002(M(s|u|o);.*;)\003/) {
		$rmsg =~ s/^\002//;                # \002 am Anfang entfernen
		my @msg_parts = split(";",$rmsg);
		my $m0;
		my $mnr0;
		my $m1;
		my $mL;
		my $mH;
		my $part = "";
		my $partD;
		$hash->{logMethod}->($name, 5, "$name: Read, RAW rmsg: $rmsg");
		
		foreach my $msgPart (@msg_parts) {
			next if ($msgPart eq "");
			$m0 = substr($msgPart,0,1);
			$mnr0 = ord($m0);
			$m1 = substr($msgPart,1);
			if ($m0 eq "M") {
				$part .= "M" . uc($m1) . ";";
			}
			elsif ($mnr0 > 127) {
				$part .= "P" . sprintf("%u", ($mnr0 & 7)) . "=";
				if (length($m1) == 2) {
					$mL = ord(substr($m1,0,1)) & 127;        # Pattern low
					$mH = ord(substr($m1,1,1)) & 127;        # Pattern high
					if (($mnr0 & 0b00100000) != 0) {           # Vorzeichen  0b00100000 = 32
						$part .= "-";
					}
					if ($mnr0 & 0b00010000) {                # Bit 7 von Pattern low
						$mL += 128;
					}
					$part .= ($mH * 256) + $mL;
				}
				$part .= ";";
			}
			elsif (($m0 eq "D" || $m0 eq "d") && length($m1) > 0) {
				my @arrayD = split(//, $m1);
				$part .= "D=";
				$partD = "";
				foreach my $D (@arrayD) {
					$mH = ord($D) >> 4;
					$mL = ord($D) & 7;
					$partD .= "$mH$mL";
				}
				#SIGNALduino_Log3 $name, 3, "$name: Read, msg READredu1$m0: $partD";
				if ($m0 eq "d") {
					$partD =~ s/.$//;	   # letzte Ziffer entfernen wenn Anzahl der Ziffern ungerade
				}
				$partD =~ s/^8//;	           # 8 am Anfang entfernen
				#SIGNALduino_Log3 $name, 3, "$name: Read, msg READredu2$m0: $partD";
				$part = $part . $partD . ';';
			}
			elsif (($m0 eq "C" || $m0 eq "S") && length($m1) == 1) {
				$part .= "$m0" . "P=$m1;";
			}
			elsif ($m0 eq "o" || $m0 eq "m") {
				$part .= "$m0$m1;";
			}
			elsif ($m1 =~ m/^[0-9A-Z]{1,2}$/) {        # bei 1 oder 2 Hex Ziffern nach Dez wandeln 
				$part .= "$m0=" . hex($m1) . ";";
			}
			elsif ($m0 =~m/[0-9a-zA-Z]/) {
				$part .= "$m0";
				if ($m1 ne "") {
					$part .= "=$m1";
				}
				$part .= ";";
			}
		}
		$hash->{logMethod}->($name, 4, "$name: Read, msg READredu: $part");
		$rmsg = "\002$part\003";
	}
	else {
		$hash->{logMethod}->($name, 4, "$name: Read, msg: $rmsg");
	}

	if ( $rmsg && !SIGNALduino_Parse($hash, $hash, $name, $rmsg) && defined($hash->{getcmd}) && defined($hash->{getcmd}->{cmd}))
	{
		my $regexp;
		if ($hash->{getcmd}->{cmd} eq 'sendraw') { # todo: pruefen wieso die regexp nicht im %gets hinterlegt ist. Das könnte in paar Zeilen code sparen
			$regexp = '^S(?:R|C|M);.';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'ccregAll') {
			$regexp = '^ccreg 00:';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'bWidth') {
			$regexp = '^C.* = .*';
		}
		else {
			$regexp = $gets{$hash->{getcmd}->{cmd}}[1];
		}
		if(!defined($regexp) || $rmsg =~ m/$regexp/) {
			if (defined($hash->{keepalive})) {
				$hash->{keepalive}{ok}    = 1;
				$hash->{keepalive}{retry} = 0;
			}
			$hash->{logMethod}->($name, 5, "$name: Read, msg: regexp=$regexp cmd=$hash->{getcmd}->{cmd} msg=$rmsg");
			
			if ($hash->{getcmd}->{cmd} eq 'version') { # todo prüfen ob der code nicht in die %gets tabelle verschoben werden kann
				my $msg_start = index($rmsg, 'V 3.');
				if ($msg_start > 0) {
					$rmsg = substr($rmsg, $msg_start);
					$hash->{logMethod}->($name, 4, "$name: Read, cut chars at begin. msgstart = $msg_start msg = $rmsg");
				}
				$hash->{version} = $rmsg;
				if (defined($hash->{DevState}) && $hash->{DevState} eq 'waitInit') {
					RemoveInternalTimer($hash);
					SIGNALduino_CheckCmdResp($hash);
				}
			}
			if ($hash->{getcmd}->{cmd} eq 'sendraw') {
				# zu testen der sendeQueue, kann wenn es funktioniert auf verbose 5
				$hash->{logMethod}->($name, 4, "$name: Read, sendraw answer: $rmsg");
				delete($hash->{getcmd});
				RemoveInternalTimer("HandleWriteQueue:$name");
				SIGNALduino_HandleWriteQueue("x:$name");
			}
			else {
				$rmsg = SIGNALduino_parseResponse($hash,$hash->{getcmd}->{cmd},$rmsg);
				if (defined($hash->{getcmd}) && $hash->{getcmd}->{cmd} ne 'ccregAll') {
					readingsSingleUpdate($hash, $hash->{getcmd}->{cmd}, $rmsg, 0);
				}
				if (defined($hash->{getcmd}->{asyncOut})) {
					#SIGNALduino_Log3 $name, 4, "$name: Read, msg: asyncOutput";
					my $ao = asyncOutput( $hash->{getcmd}->{asyncOut}, $hash->{getcmd}->{cmd}.": " . $rmsg );
				}
				delete($hash->{getcmd});
			}
		} else {
			$hash->{logMethod}->($name, 4, "$name: Read, msg: Received answer ($rmsg) for ". $hash->{getcmd}->{cmd}." does not match $regexp"); 
		}
	}
  }
  $hash->{PARTIAL} = $SIGNALduinodata;
}

###############################
sub SIGNALduino_KeepAlive($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	return if ($hash->{DevState} eq 'disconnected');
	
	#SIGNALduino_Log3 $name,4 , "$name: KeepAliveOk, " . $hash->{keepalive}{ok};
	if (!$hash->{keepalive}{ok}) {
		delete($hash->{getcmd});
		if ($hash->{keepalive}{retry} >= SDUINO_KEEPALIVE_MAXRETRY) {
			$hash->{logMethod}->($name,3 , "$name: KeepAlive, not ok, retry count reached. Reset");
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_ResetDevice($hash);
			return;
		}
		else {
			my $logLevel = 3;
			$hash->{keepalive}{retry} ++;
			if ($hash->{keepalive}{retry} == 1) {
				$logLevel = 4;
			}
			$hash->{logMethod}->($name, $logLevel, "$name: KeepAlive, not ok, retry = " . $hash->{keepalive}{retry} . " -> get ping");
			$hash->{getcmd}->{cmd} = "ping";
			SIGNALduino_AddSendQueue($hash, "P");
			#SIGNALduino_SimpleWrite($hash, "P");
		}
	}
	else {
		$hash->{logMethod}->($name,4 , "$name: KeepAlive, ok, retry = " . $hash->{keepalive}{retry});
	}
	$hash->{keepalive}{ok} = 0;
	
	InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash);
}


### Helper Subs >>>

###############################
## Parses a HTTP Response for example for flash via http download
sub SIGNALduino_ParseHttpResponse {
	
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "")               											 		# wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, error while requesting ".$param->{url}." - $err");    		# Eintrag fuers Log
    }
    elsif($param->{code} eq "200" && $data ne "")                                                       		# wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
    {
    	
        $hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, url ".$param->{url}." returned: ".length($data)." bytes Data");  # Eintrag fuers Log
		    	
    	if ($param->{command} eq "flash")
    	{
	    	my $filename;
	    	
	    	if ($param->{httpheader} =~ /Content-Disposition: attachment;.?filename=\"?([-+.\w]+)?\"?/)
			{ 
				$filename = $1;
			} else {  # Filename via path if not specifyied via Content-Disposition
	    		($filename = $param->{path}) =~s/.*\///;
			}
			
	    	$hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, Downloaded $filename firmware from ".$param->{host});
	    	$hash->{logMethod}->($name, 5, "$name: ParseHttpResponse, Header = ".$param->{httpheader});
	
			
		   	$filename = "FHEM/firmware/" . $filename;
			open(my $file, ">", $filename) or die $!;
			print $file $data;
			close $file;
	
			# Den Flash Befehl mit der soebene heruntergeladenen Datei ausfuehren
			#SIGNALduino_Log3 $name, 3, "$name: ParseHttpResponse, calling set ".$param->{command}." $filename";    		# Eintrag fuers Log

			my $set_return = SIGNALduino_Set($hash,$name,$param->{command},$filename); # $hash->{SetFn}
			if (defined($set_return))
			{
				$hash->{logMethod}->($name ,3, "$name: ParseHttpResponse, Error while flashing: $set_return");
			} 
    	}
    } else {
    	$hash->{logMethod}->($name, 3, "$name: ParseHttpResponse, undefined error while requesting ".$param->{url}." - $err - code=".$param->{code});    		# Eintrag fuers Log
    }
}

###############################
sub SIGNALduino_splitMsg {
  my $txt = shift;
  my $delim = shift;
  my @msg_parts = split(/$delim/,$txt);
  
  return @msg_parts;
}

###############################
# $value  - $set <= $tolerance
sub SIGNALduino_inTol($$$) {
	#Debug "sduino abs \($_[0] - $_[1]\) <= $_[2] ";
	return (abs($_[0]-$_[1])<=$_[2]);
}


###############################
# =item SIGNALduino_FillPatternLookupTable()
#
# Retruns 1 on success or 0 if symbol was not found

sub SIGNALduino_FillPatternLookupTable {
			my ($hash,$symbol,$representation,$patternList,$rawData,$patternLookupHash,$endPatternLookupHash,$rtext) = @_;
			my $pstr=undef;
			if (($pstr=SIGNALduino_PatternExists($hash, $symbol,$patternList,$rawData)) >=0) {
				${$rtext} = $pstr;
				$patternLookupHash->{$pstr}=${$representation};		 ## Append to lookuptable
				chop $pstr;
				$endPatternLookupHash->{$pstr} = ${$representation} if (!exists($endPatternLookupHash->{$pstr})); ## Append shortened string to lookuptable
				return 1;
			} else {
				${$rtext} = "";
				return 0;
			}
}


###############################
#=item SIGNALduino_PatternExists()
# This functons, needs reference to $hash, @array of values to search and %patternList where to find the matches.
# 
# Will return -1 if pattern is not found or a string, containing the indexes which are in tolerance and have the smallest gap to what we searched
# =cut

# 01232323242423       while ($message =~ /$pstr/g) { $count++ }

sub SIGNALduino_PatternExists {
	my ($hash,$search,$patternList,$data) = @_;
	#my %patternList=$arg3;
	#Debug "plist: ".Dumper($patternList) if($debug); 
	#Debug "searchlist: ".Dumper($search) if($debug);


	my $searchpattern;
	my $valid=1;  
	my @pstr;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	my $i=0;
	
	my $maxcol=0;
	
	foreach $searchpattern (@{$search}) # z.B. [1, -4] 
	{
		#my $patt_id;
		# Calculate tolernace for search
		#my $tol=abs(abs($searchpattern)>=2 ?$searchpattern*0.3:$searchpattern*1.5);
		my $tol=abs(abs($searchpattern)>3 ? abs($searchpattern)>16 ? $searchpattern*0.18 : $searchpattern*0.3 : 1);  #tol is minimum 1 or higer, depending on our searched pulselengh
		

		Debug "tol: looking for ($searchpattern +- $tol)" if($debug);		
		
		my %pattern_gap ; #= {};
		# Find and store the gap of every pattern, which is in tolerance
		%pattern_gap = map { $_ => abs($patternList->{$_}-$searchpattern) } grep { abs($patternList->{$_}-$searchpattern) <= $tol} (keys %$patternList);
		if (scalar keys %pattern_gap > 0) 
		{
			Debug "index => gap in tol (+- $tol) of pulse ($searchpattern) : ".Dumper(\%pattern_gap) if($debug);
			# Extract fist pattern, which is nearst to our searched value
			my @closestidx = (sort {$pattern_gap{$a} <=> $pattern_gap{$b}} keys %pattern_gap);
			
			my $idxstr="";
			my $r=0;
			
			while (my ($item) = splice(@closestidx, 0, 1)) 
			{
				$pstr[$i][$r]=$item; 
				$r++;
				Debug "closest pattern has index: $item" if($debug);
			}
			$valid=1;
		} else {
			# search is not found, return -1
			return -1;
			last;	
		}
		$i++;
		#return ($valid ? $pstr : -1);  # return $pstr if $valid or -1

		
		#foreach $patt_id (keys %$patternList) {
			#Debug "$patt_id. chk ->intol $patternList->{$patt_id} $searchpattern $tol"; 
			#$valid =  SIGNALduino_inTol($patternList->{$patt_id}, $searchpattern, $tol);
			#if ( $valid) #one pulse found in tolerance, search next one
			#{
			#	$pstr="$pstr$patt_id";
			#	# provide this index for further lookup table -> {$patt_id =  $searchpattern}
			#	Debug "pulse found";
			#	last ; ## Exit foreach loop if searched pattern matches pattern in list
			#}
		#}
		#last if (!$valid);  ## Exit loop if a complete iteration has not found anything
	}
	my @results = ('');
	
	foreach my $subarray (@pstr)
	{
	    @results = map {my $res = $_; map $res.$_, @$subarray } @results;
	}
			
	foreach my $search (@results)
	{
		Debug "looking for substr $search" if($debug);
			
		return $search if (index( ${$data}, $search) >= 0);
	}
	
	return -1;
	
	#return ($valid ? @results : -1);  # return @pstr if $valid or -1
}

#SIGNALduino_MatchSignalPattern{$hash,@array, %hash, @array, $scalar}; not used >v3.1.3
sub SIGNALduino_MatchSignalPattern($\@\%\@$){

	my ( $hash, $signalpattern,  $patternList,  $data_array, $idx) = @_;
    my $name = $hash->{NAME};
	#print Dumper($patternList);		
	#print Dumper($idx);		
	#Debug Dumper($signalpattern) if ($debug);		
	my $tol="0.2";   # Tolerance factor
	my $found=0;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	foreach ( @{$signalpattern} )
	{
			#Debug " $idx check: ".$patternList->{$data_array->[$idx]}." == ".$_;		
			Debug "$name: idx: $idx check: abs(". $patternList->{$data_array->[$idx]}." - ".$_.") > ". ceil(abs($patternList->{$data_array->[$idx]}*$tol)) if ($debug);		
			  
			#print "\n";;
			#if ($patternList->{$data_array->[$idx]} ne $_ ) 
			### Nachkommastelle von ceil!!!
			if (!defined( $patternList->{$data_array->[$idx]})){
				Debug "$name: Error index ($idx) does not exist!!" if ($debug);

				return -1;
			}
			if (abs($patternList->{$data_array->[$idx]} - $_)  > ceil(abs($patternList->{$data_array->[$idx]}*$tol)))
			{
				return -1;		## Pattern does not match, return -1 = not matched
			}
			$found=1;
			$idx++;
	}
	if ($found)
	{
		return $idx;			## Return new Index Position
	}
	
}

###############################
sub SIGNALduino_b2h {
    my $num   = shift;
    my $WIDTH = 4;
    my $index = length($num) - $WIDTH;
    my $hex = '';
    do {
        my $width = $WIDTH;
        if ($index < 0) {
            $width += $index;
            $index = 0;
        }
        my $cut_string = substr($num, $index, $width);
        $hex = sprintf('%X', oct("0b$cut_string")) . $hex;
        $index -= $WIDTH;
    } while ($index > (-1 * $WIDTH));
    return $hex;
}

###############################
sub SIGNALduino_Split_Message($$) {
	my $rmsg = shift;
	my $name = shift;
	my %patternList;
	my $clockidx;
	my $syncidx;
	my $rawData;
	my $clockabs;
	my $mcbitnum;
	my $rssi;
	
	my @msg_parts = SIGNALduino_splitMsg($rmsg,';');			## Split message parts by ";"
	my %ret;
	my $debug = AttrVal($name,"debug",0);
	
	foreach (@msg_parts)
	{
		#Debug "$name: checking msg part:( $_ )" if ($debug);

		#if ($_ =~ m/^MS/ or $_ =~ m/^MC/ or $_ =~ m/^Mc/ or $_ =~ m/^MU/) 		#### Synced Message start
		if ($_ =~ m/^M./)
		{
			$ret{messagetype} = $_;
		}
		elsif ($_ =~ m/^P\d=-?\d{2,}/ or $_ =~ m/^[SL][LH]=-?\d{2,}/) 		#### Extract Pattern List from array
		{
		   $_ =~ s/^P+//;  
		   $_ =~ s/^P\d//;  
		   my @pattern = split(/=/,$_);
		   
		   $patternList{$pattern[0]} = $pattern[1];
		   Debug "$name: extracted  pattern @pattern \n" if ($debug);
		}
		elsif($_ =~ m/D=\d+/ or $_ =~ m/^D=[A-F0-9]+/) 		#### Message from array

		{
			$_ =~ s/D=//;  
			$rawData = $_ ;
			Debug "$name: extracted  data $rawData\n" if ($debug);
			$ret{rawData} = $rawData;

		}
		elsif($_ =~ m/^SP=\d{1}/) 		#### Sync Pulse Index
		{
			(undef, $syncidx) = split(/=/,$_);
			Debug "$name: extracted  syncidx $syncidx\n" if ($debug);
			#return undef if (!defined($patternList{$syncidx}));
			$ret{syncidx} = $syncidx;

		}
		elsif($_ =~ m/^CP=\d{1}/) 		#### Clock Pulse Index
		{
			(undef, $clockidx) = split(/=/,$_);
			Debug "$name: extracted  clockidx $clockidx\n" if ($debug);;
			#return undef if (!defined($patternList{$clockidx}));
			$ret{clockidx} = $clockidx;
		}
		elsif($_ =~ m/^L=\d/) 		#### MC bit length
		{
			(undef, $mcbitnum) = split(/=/,$_);
			Debug "$name: extracted  number of $mcbitnum bits\n" if ($debug);;
			$ret{mcbitnum} = $mcbitnum;
		}
		
		elsif($_ =~ m/^C=\d+/) 		#### Message from array
		{
			$_ =~ s/C=//;  
			$clockabs = $_ ;
			Debug "$name: extracted absolute clock $clockabs \n" if ($debug);
			$ret{clockabs} = $clockabs;
		}
		elsif($_ =~ m/^R=\d+/)		### RSSI ###
		{
			$_ =~ s/R=//;
			$rssi = $_ ;
			Debug "$name: extracted RSSI $rssi \n" if ($debug);
			$ret{rssi} = $rssi;
		}  else {
			Debug "$name: unknown Message part $_" if ($debug);;
		}
		#print "$_\n";
	}
	$ret{pattern} = {%patternList}; 
	return %ret;
}

###############################
# Function which dispatches a message if needed.
sub SIGNALduno_Dispatch($$$$$) {
	my ($hash, $rmsg, $dmsg, $rssi, $id) = @_;
	my $name = $hash->{NAME};
	
	if (!defined($dmsg))
	{
		$hash->{logMethod}->($name, 5, "$name: Dispatch, dmsg is undef. Skipping dispatch call");
		return;
	}
	
	#SIGNALduino_Log3 $name, 5, "$name: Dispatch, DMSG: $dmsg";
	
	my $DMSGgleich = 1;
	if ($dmsg eq $hash->{LASTDMSG}) {
		$hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test gleich");
	} else {
		if (defined($hash->{DoubleMsgIDs}{$id})) {
			$DMSGgleich = 0;
			$hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test ungleich");
		}
		else {
			$hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, test ungleich: disabled");
		}
		$hash->{LASTDMSG} = $dmsg;
		$hash->{LASTDMSGID} = $id;
	}

   if ($DMSGgleich) {
	#Dispatch if dispatchequals is provided in protocol definition or only if $dmsg is different from last $dmsg, or if 2 seconds are between transmits
	if ( (SIGNALduino_getProtoProp($id,'dispatchequals',0) eq 'true') || ($hash->{DMSG} ne $dmsg) || ($hash->{TIME}+2 < time() ) )   { 
		$hash->{MSGCNT}++;
		$hash->{TIME} = time();
		$hash->{DMSG} = $dmsg;
		#my $event = 0;
		if (substr(ucfirst($dmsg),0,1) eq 'U') { # u oder U
			#$event = 1;
			DoTrigger($name, "DMSG " . $dmsg);
			return if (substr($dmsg,0,1) eq 'U'); # Fuer $dmsg die mit U anfangen ist kein Dispatch notwendig, da es dafuer kein Modul gibt klein u wird dagegen dispatcht
		}
		#readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, $event);
		
		$hash->{RAWMSG} = $rmsg;
		my %addvals = (
			DMSG => $dmsg,
			Protocol_ID => $id
		);
		if (AttrVal($name,"suppressDeviceRawmsg",0) == 0) {
			$addvals{RAWMSG} = $rmsg
		}
		if(defined($rssi)) {
			$hash->{RSSI} = $rssi;
			$addvals{RSSI} = $rssi;
			$rssi .= " dB,"
		}
		else {
			$rssi = "";
		}
		$dmsg = lc($dmsg) if ($id eq '74' or $id eq '74.1');		# 10_FS20.pm accepted only lower case hex
		$hash->{logMethod}->($name, SDUINO_DISPATCH_VERBOSE, "$name: Dispatch, $dmsg, $rssi dispatch");
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
		
	}	else {
		$hash->{logMethod}->($name, 4, "$name: Dispatch, $dmsg, Dropped due to short time or equal msg");
	}
   }
}

###############################
# param #1 is name of definition 
# param #2 is protocol id
# param #3 is dispatched message to check against
#
# returns 1 if message matches modulematch + development attribute/whitelistIDs
# returns 0 if message does not match modulematch  
# return -1 if message is not activated via whitelistIDs but has developID=m flag
sub SIGNALduino_moduleMatch {
	my $name = shift;
	my $id = shift;
	my $dmsg = shift;
	my $debug = AttrVal($name,"debug",0);
	my $modMatchRegex=SIGNALduino_getProtoProp($id,"modulematch",undef);
	
	if (!defined($modMatchRegex) || $dmsg =~ m/$modMatchRegex/) {
		Debug "$name: modmatch passed for: $dmsg" if ($debug);
		my $developID = SIGNALduino_getProtoProp($id,"developId","");
		my $IDsNoDispatch = "," . InternalVal($name,"IDsNoDispatch","") . ",";
		if ($IDsNoDispatch ne ",," && index($IDsNoDispatch, ",$id,") >= 0) {	# kein dispatch wenn die Id im Internal IDsNoDispatch steht
			Log3 $name, 3, "$name: moduleMatch, ID=$id skipped dispatch (developId=m). To use, please add $id to the attr whitelist_IDs";

			return -1;
		}
		return 1; #   return 1 da modulematch gefunden wurde			
		}
	return 0;
}

###############################
sub SIGNALduino_Parse_MS($$$$%) {
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $syncidx=$msg_parts{syncidx};			
	my $clockidx=$msg_parts{clockidx};				
	my $rssi=$msg_parts{rssi};
	my $rawData=$msg_parts{rawData};
	my %patternList;
	my $rssiStr= "";
	
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
		$rssiStr= " RSSI = $rssi"
	}
	
	#Debug "Message splitted:";
	#Debug Dumper(\@msg_parts);

	my $debug = AttrVal($iohash->{NAME},"debug",0);

	
	if (defined($clockidx) and defined($syncidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:";
		my $clockabs= $msg_parts{pattern}{$msg_parts{clockidx}};
		return undef if ($clockabs == 0); 
		$patternList{$_} = round($msg_parts{pattern}{$_}/$clockabs,1) for keys %{$msg_parts{pattern}};
	
		
 		#Debug Dumper(\%patternList);		

		#my $syncfact = $patternList{$syncidx}/$patternList{$clockidx};
		#$syncfact=$patternList{$syncidx};
		#Debug "SF=$syncfact";
		#### Convert rawData in Message
		my $signal_length = length($rawData);        # Length of data array

		## Iterate over the data_array and find zero, one, float and sync bits with the signalpattern
		## Find matching protocols
		my $id;
		my $message_dispatched=0;
		
		IDLOOP:
		foreach $id (@{$hash->{msIdList}}) {
			
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);

			# Check Clock if is it in range
			if ($ProtocolListSIGNALduino{$id}{clockabs} > 0) {
				if (!SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},$clockabs,$clockabs*0.30)) {
					Debug "protocClock=$ProtocolListSIGNALduino{$id}{clockabs}, msgClock=$clockabs is not in tol=" . $clockabs*0.30 if ($debug);  
					next;
				} elsif ($debug) {
					Debug "protocClock=$ProtocolListSIGNALduino{$id}{clockabs}, msgClock=$clockabs is in tol=" . $clockabs*0.30;
				}
			}

			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);
			
			my %patternLookupHash=();
			my %endPatternLookupHash=();
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			my $return_text;
			my $message_start;
			foreach my $key (qw(sync one zero float) ) {
				next if (!exists($ProtocolListSIGNALduino{$id}{$key}));
				
				if (!SIGNALduino_FillPatternLookupTable($hash,\@{$ProtocolListSIGNALduino{$id}{$key}},\$symbol_map{$key},\%patternList,\$rawData,\%patternLookupHash,\%endPatternLookupHash,\$return_text))
				{
					Debug sprintf("%s pattern not found",$key) if ($debug);
					next IDLOOP if ($key ne "float") ;
				}
				
				if ($key eq "sync")
				{
					$message_start =index($rawData,$return_text)+length($return_text);
					my $bit_length = ($signal_length-$message_start) / $signal_width;
					if (exists($ProtocolListSIGNALduino{$id}{length_min}) && $ProtocolListSIGNALduino{$id}{length_min} > $bit_length) {
						Debug "bit_length=$bit_length to short" if ($debug);
						next IDLOOP;
					}
					Debug "expecting $bit_length bits in signal" if ($debug);
					%endPatternLookupHash=();
				}
				Debug sprintf("Found matched %s with indexes: (%s)",$key,$return_text) if ($debug);
			}
			next if (scalar keys %patternLookupHash == 0);  # Keine Eingträge im patternLookupHash
			

			$hash->{logMethod}->($name, 4, "$name: Parse_MS, Matched MS Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}");
			my @bit_msg;							# array to store decoded signal bits
			$hash->{logMethod}->($name, 5, "$name: Parse_MS, Starting demodulation at Position $message_start");
			for (my $i=$message_start;$i<length($rawData);$i+=$signal_width)
			{
				my $sigStr= substr($rawData,$i,$signal_width);
				#SIGNALduino_Log3 $name, 5, "$name: Parse_MS, demodulating $sigStr";
				#Debug $patternLookupHash{substr($rawData,$i,$signal_width)}; ## Get $signal_width number of chars from raw data string
				if (exists $patternLookupHash{$sigStr}) { ## Add the bits to our bit array
					push(@bit_msg,$patternLookupHash{$sigStr}) if ($patternLookupHash{$sigStr} ne '');
				} elsif (exists($ProtocolListSIGNALduino{$id}{reconstructBit})) {
					if (length($sigStr) == $signal_width) {			# ist $sigStr zu lang?
						chop($sigStr);
					}
					if (exists($endPatternLookupHash{$sigStr})) {
						push(@bit_msg,$endPatternLookupHash{$sigStr});
						$hash->{logMethod}->($name, 4, "$name: Parse_MS, last part pair=$sigStr reconstructed, last bit=$endPatternLookupHash{$sigStr}");
					}
					else {
						$hash->{logMethod}->($name, 5, "$name: Parse_MS, can't reconstruct last part pair=$sigStr");
					}
					last;
				} else {
					$hash->{logMethod}->($name, 5, "$name: Parse_MS, Found wrong signalpattern $sigStr, catched ".scalar @bit_msg." bits, aborting demodulation");
					last;
				}
			}
	
			
			Debug "$name: decoded message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);
			
			#Check converted message against lengths
			my ($rcode, $rtxt) = SIGNALduino_TestLength(undef,$id,scalar @bit_msg,undef);
			if (!$rcode)
			{
			  Debug "$name: decoded $rtxt" if ($debug);
			  next;
			}
			my $padwith = lib::SD_Protocols::checkProperty($id,'paddingbits',4);
			
			my $i=0;
			while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
			{
				push(@bit_msg,'0');
				$i++;
			}
			Debug "$name padded $i bits to bit_msg array" if ($debug);
			
			if ($i == 0) {
				$hash->{logMethod}->($name, 5, "$name: Parse_MS, dispatching bits: @bit_msg");
			} else {
				$hash->{logMethod}->($name, 5, "$name: Parse_MS, dispatching bits: @bit_msg with $i Paddingbits 0");
			}
			
			my $evalcheck = (SIGNALduino_getProtoProp($id,"developId","") =~ 'p') ? 1 : undef;
			($rcode,my @retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$evalcheck,$name,@bit_msg);
			next if ($rcode < 1 );
			#SIGNALduino_Log3 $name, 5, "$name: Parse_MS, postdemodulation value @retvalue";
			
			@bit_msg = @retvalue;
			undef(@retvalue); undef($rcode);
			
			my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
			my $postamble = $ProtocolListSIGNALduino{$id}{postamble};
			$dmsg = "$dmsg".$postamble if (defined($postamble));
			$dmsg = "$ProtocolListSIGNALduino{$id}{preamble}"."$dmsg" if (defined($ProtocolListSIGNALduino{$id}{preamble}));
			
			
			#my ($rcode,@retvalue) = SIGNALduino_callsub('preDispatchfunc',$ProtocolListSIGNALduino{$id}{preDispatchfunc},$name,$dmsg);
			#next if (!$rcode);
			#$dmsg = @retvalue;
			#undef(@retvalue); undef($rcode);
			
			if ( SIGNALduino_moduleMatch($name,$id,$dmsg) == 1)
			{
				$message_dispatched++;
				$hash->{logMethod}->($name, 4, "$name: Parse_MS, Decoded matched MS Protocol id $id dmsg $dmsg length " . scalar @bit_msg . " $rssiStr");
				SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
			} 
			
		}
		
		return 0 if (!$message_dispatched);
		
		return $message_dispatched;

	}
}

###############################
## //Todo: check list as reference
sub SIGNALduino_padbits(\@$) {
	my $i=@{$_[0]} % $_[1];
	while (@{$_[0]} % $_[1] > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
	{
		push(@{$_[0]},'0');
	}
	return " padded $i bits to bit_msg array";
}

###############################
#=item SIGNALduino_getProtoProp()
#This functons, will return a value from the Protocolist and check if the key exists and a value is defined optional you can specify a optional default value that will be reurned
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname,

sub SIGNALduino_getProtoProp {
	my ($id,$propNameLst,$default) = @_;
	
	#my $id = shift;
	#my $propNameLst = shift;
	return $ProtocolListSIGNALduino{$id}{$propNameLst} if exists($ProtocolListSIGNALduino{$id}{$propNameLst}) && defined($ProtocolListSIGNALduino{$id}{$propNameLst});
	return $default; # Will return undef if $default is not provided
	#return undef;
}

###############################
sub SIGNALduino_Parse_MU($$$$@) {
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $protocolid;
	my $clockidx=$msg_parts{clockidx};
	my $rssi=$msg_parts{rssi};
	my $rawData;
	my %patternListRaw;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	my $rssiStr= "";
	
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
		$rssiStr= " RSSI = $rssi"
	}
	
    Debug "$name: processing unsynced message\n" if ($debug);

	my $clockabs = 1;  #Clock will be fetched from Protocol if possible
	#$patternListRaw{$_} = floor($msg_parts{pattern}{$_}/$clockabs) for keys $msg_parts{pattern};
	$patternListRaw{$_} = $msg_parts{pattern}{$_} for keys %{$msg_parts{pattern}};

	
	if (defined($clockidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:"; 		#Debug Dumper(\%patternList);		

		## Find matching protocols
		my $id;
		
		IDLOOP:
		foreach $id (@{$hash->{muIdList}}) {
			
			$clockabs= $ProtocolListSIGNALduino{$id}{clockabs};
			my %patternList;
			$rawData=$msg_parts{rawData};
			if (exists($ProtocolListSIGNALduino{$id}{filterfunc}))
			{
				my $method = $ProtocolListSIGNALduino{$id}{filterfunc};
		   		if (!exists &$method)
				{
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, Error: Unknown filtermethod=$method. Please define it in file $0");
					next;
				} else {					
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, for MU Protocol id $id, applying filterfunc $method");

				    no strict "refs";
					(my $count_changes,$rawData,my %patternListRaw_tmp) = $method->($name,$id,$rawData,%patternListRaw);				
				    use strict "refs";

					%patternList = map { $_ => round($patternListRaw_tmp{$_}/$clockabs,1) } keys %patternListRaw_tmp; 
				}
			} else {
				%patternList = map { $_ => round($patternListRaw{$_}/$clockabs,1) } keys %patternListRaw; 
			}
			
					
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);
			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);

			my $startStr=""; # Default match if there is no start pattern available
			my $message_start=0 ;
			my $startLogStr="";
			
			if (exists($ProtocolListSIGNALduino{$id}{start}) && defined($ProtocolListSIGNALduino{$id}{start}) && ref($ProtocolListSIGNALduino{$id}{start}) eq 'ARRAY')	# wenn start definiert ist, dann startStr ermitteln und in rawData suchen und in der rawData alles bis zum startStr abschneiden
			{
				Debug "msgStartLst: ".Dumper(\@{$ProtocolListSIGNALduino{$id}{start}})  if ($debug);
				
				
				if ( ($startStr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{start}},\%patternList,\$rawData)) eq -1)
				{
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, start pattern for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} not found, aborting");
					next;
				}
				Debug "startStr is: $startStr" if ($debug);
				$message_start = index($rawData, $startStr);
				if ( $message_start == -1) 
				{
					Debug "startStr $startStr not found." if ($debug);
					next;
				} else {
					$rawData = substr($rawData, $message_start);
					$startLogStr = "StartStr: $startStr first found at $message_start";
					Debug "rawData = $rawData" if ($debug);
					Debug "startStr $startStr found. Message starts at $message_start" if ($debug);
					#SIGNALduino_Log3 $name, 5, "$name: Parse_MU, substr: $rawData"; # todo: entfernen
				} 
				
			}
			
			my %patternLookupHash=();
			my %endPatternLookupHash=();
			my $pstr="";
			my $zeroRegex ="";
			my $oneRegex ="";
			my $floatRegex ="";
			my $return_text="";
			my $signalRegex="(?:";
						
			foreach my $key (qw(one zero float) ) {
				next if (!exists($ProtocolListSIGNALduino{$id}{$key}));
				if (!SIGNALduino_FillPatternLookupTable($hash,\@{$ProtocolListSIGNALduino{$id}{$key}},\$symbol_map{$key},\%patternList,\$rawData,\%patternLookupHash,\%endPatternLookupHash,\$return_text))
				{
						Debug sprintf("%s pattern not found",$key) if ($debug);
						next IDLOOP if ($key ne "float");
				}
				Debug sprintf("Found matched %s with indexes: (%s)",$key,$return_text) if ($debug);
				if ($key eq "one")
				{
					 $signalRegex .= $return_text;
				}
				else {
					$signalRegex .= "|$return_text" if($return_text);
				}
			}
			$signalRegex .= ")";

			$hash->{logMethod}->($name, 4, "$name: Parse_MU, Fingerprint for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} matches, trying to demodulate");
			
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			my $length_min = $ProtocolListSIGNALduino{$id}{length_min};
			my $length_max = "";
			$length_max = $ProtocolListSIGNALduino{$id}{length_max} if (exists($ProtocolListSIGNALduino{$id}{length_max}));
			
			$signalRegex .= "{$length_min,}";
			
			if (exists($ProtocolListSIGNALduino{$id}{reconstructBit})) {
				
				$signalRegex .= "(?:" . join("|",keys %endPatternLookupHash) . ")?";
			}
			Debug "signalRegex is $signalRegex " if ($debug);

			my $nrRestart=0;
			my $nrDispatch=0;
			my $regex="(?:$startStr)($signalRegex)";
			
			while ( $rawData =~ m/$regex/g)		{
				my $length_str="";
				$nrRestart++;
				$hash->{logMethod}->($name, 5, "$name: Parse_MU, part is $1 starts at position $-[0] and ends at ". pos $rawData);				
			
				my @pairs = unpack "(a$signal_width)*", $1;
			
				if (exists($ProtocolListSIGNALduino{$id}{length_max}) && scalar @pairs > $ProtocolListSIGNALduino{$id}{length_max})	# ist die Nachricht zu lang?
				{
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, $nrRestart. skip demodulation (length ".scalar @pairs." is to long) at Pos $-[0] regex ($regex)");
					next;
				}
				
				if ($nrRestart == 1) {
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, Starting demodulation ($startLogStr " . "regex: $regex Pos $message_start) length_min_max (".$length_min."..".$length_max.") length=".scalar @pairs); 
				} else {
					$hash->{logMethod}->($name, 5, "$name: Parse_MU, $nrRestart. try demodulation$length_str at Pos $-[0]");
				}
				

				my @bit_msg=();			# array to store decoded signal bits
				
				foreach my $sigStr (@pairs)
				{
					if (exists $patternLookupHash{$sigStr}) {
						push(@bit_msg,$patternLookupHash{$sigStr})  ## Add the bits to our bit array
					}
					elsif (exists($ProtocolListSIGNALduino{$id}{reconstructBit}) && exists($endPatternLookupHash{$sigStr})) {
						my $lastbit = $endPatternLookupHash{$sigStr};
						push(@bit_msg,$lastbit);
						$hash->{logMethod}->($name, 4, "$name: Parse_MU, last part pair=$sigStr reconstructed, bit=$lastbit");
					}
				}
				
				Debug "$name: demodulated message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);

				my $evalcheck = (SIGNALduino_getProtoProp($id,"developId","") =~ 'p') ? 1 : undef;
				my ($rcode,@retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$evalcheck,$name,@bit_msg);
				
				next if ($rcode < 1 );
				@bit_msg = @retvalue;
				undef(@retvalue); undef($rcode);
	
				my $dispmode="hex"; 
				$dispmode="bin" if (SIGNALduino_getProtoProp($id,"dispatchBin",0) == 1 );
				
				my $padwith = lib::SD_Protocols::checkProperty($id,'paddingbits',4);
				while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
				{
					push(@bit_msg,'0');
					Debug "$name: padding 0 bit to bit_msg array" if ($debug);
				}		
				my $dmsg = join ("", @bit_msg);
				my $bit_length=scalar @bit_msg;
				@bit_msg=(); # clear bit_msg array

				$dmsg = SIGNALduino_b2h($dmsg) if (SIGNALduino_getProtoProp($id,"dispatchBin",0) == 0 );
				

				$dmsg =~ s/^0+//	 if (  SIGNALduino_getProtoProp($id,"remove_zero",0) );
				
				$dmsg=sprintf("%s%s%s",SIGNALduino_getProtoProp($id,"preamble",""),$dmsg,SIGNALduino_getProtoProp($id,"postamble",""));
				$hash->{logMethod}->($name, 5, "$name: Parse_MU, dispatching $dispmode: $dmsg");
				
				if ( SIGNALduino_moduleMatch($name,$id,$dmsg) == 1)
				{
					$nrDispatch++;
					$hash->{logMethod}->($name, 4, "$name: Parse_MU, Decoded matched MU Protocol id $id dmsg $dmsg length $bit_length dispatch($nrDispatch/". AttrVal($name,'maxMuMsgRepeat', 4) . ")$rssiStr");
					SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
					if ( $nrDispatch == AttrVal($name,"maxMuMsgRepeat", 4))
					{
						last;
					}
				} 


			}
			$hash->{logMethod}->($name, 5, "$name: Parse_MU, $nrRestart. try, regex ($regex) did not match") if ($nrRestart == 0);
			$message_dispatched=$message_dispatched+$nrDispatch;
		}
		return $message_dispatched;	
		
	}
}

###############################
sub SIGNALduino_Parse_MC($$$$@) {

	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;
	my $clock=$msg_parts{clockabs};	     ## absolute clock
	my $rawData=$msg_parts{rawData};
	my $rssi=$msg_parts{rssi};
	my $mcbitnum=$msg_parts{mcbitnum};
	my $messagetype=$msg_parts{messagetype};
	my $bitData;
	my $dmsg;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
	
	return undef if (!$clock);
	#my $protocol=undef;
	#my %patternListRaw = %msg_parts{patternList};
	
	Debug "$name: processing manchester messag len:".length($rawData) if ($debug);
	
	my $hlen = length($rawData);
	my $blen;
	#if (defined($mcbitnum)) {
	#	$blen = $mcbitnum;
	#} else {
		$blen = $hlen * 4;
	#}
	my $id;
	
	my $rawDataInverted;
	($rawDataInverted = $rawData) =~ tr/0123456789ABCDEF/FEDCBA9876543210/;   # Some Manchester Data is inverted
	
	foreach $id (@{$hash->{mcIdList}}) {

		#next if ($blen < $ProtocolListSIGNALduino{$id}{length_min} || $blen > $ProtocolListSIGNALduino{$id}{length_max});
		#if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1]);
		if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1] and length($rawData)*4 >= $ProtocolListSIGNALduino{$id}{length_min} )
		{
			Debug "clock and min length matched"  if ($debug);

			if (defined($rssi)) {
				$hash->{logMethod}->($name, 4, "$name: Parse_MC, Found manchester Protocol id $id clock $clock RSSI $rssi -> $ProtocolListSIGNALduino{$id}{name}");
			} else {
				$hash->{logMethod}->($name, 4, "$name: Parse_MC, Found manchester Protocol id $id clock $clock -> $ProtocolListSIGNALduino{$id}{name}");
			}
			
			my $polarityInvert = 0;
			if (exists($ProtocolListSIGNALduino{$id}{polarity}) && ($ProtocolListSIGNALduino{$id}{polarity} eq 'invert'))
			{
				$polarityInvert = 1;
			}
			if ($messagetype eq 'Mc' || (defined($hash->{version}) && substr($hash->{version},0,6) eq 'V 3.2.'))
			{
				$polarityInvert = $polarityInvert ^ 1;
			}
			if ($polarityInvert == 1)
			{
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawDataInverted)); 
		   		
			} else {
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawData)); 
			}
			Debug "$name: extracted data $bitData (bin)\n" if ($debug); ## Convert Message from hex to bits
		   	$hash->{logMethod}->($name, 5, "$name: Parse_MC, extracted data $bitData (bin)");
		   	
		   	my $method = lib::SD_Protocols::getProperty($id,"method");
		    if (!exists &$method || !defined &{ $method })
			{
				$hash->{logMethod}->($name, 5, "$name: Parse_MC, Error: Unknown function=$method. Please define it in file $0");
			} else {
				$mcbitnum = length($bitData) if ($mcbitnum > length($bitData));
				my ($rcode,$res) = $method->($name,$bitData,$id,$mcbitnum);
				if ($rcode != -1) {
					$dmsg = $res;
					$dmsg=$ProtocolListSIGNALduino{$id}{preamble}.$dmsg if (defined($ProtocolListSIGNALduino{$id}{preamble})); 
					my $modulematch;
					if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
		                $modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
					}
					if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
						if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
							my $devid = "m$id";
							my $develop = lc(AttrVal($name,"development",""));
							if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
								$hash->{logMethod}->($name, 3, "$name: Parse_MC, ID=$devid skipped dispatch (developId=m). To use, please add m$id to the attr development");
								next;
							}
						}
						if (SDUINO_MC_DISPATCH_VERBOSE < 5 && (SDUINO_MC_DISPATCH_LOG_ID eq '' || SDUINO_MC_DISPATCH_LOG_ID eq $id))
						{
							if (defined($rssi)) {
								$hash->{logMethod}->($name, SDUINO_MC_DISPATCH_VERBOSE, "$name: Parse_MC, $id, $rmsg RSSI=$rssi");
							} else
							{
								$hash->{logMethod}->($name, SDUINO_MC_DISPATCH_VERBOSE, "$name: Parse_MC, $id, $rmsg");
							}
						}
						SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
						$message_dispatched=1;
					}
				} else {
					$res="undef" if (!defined($res));
					$hash->{logMethod}->($name, 5, "$name: Parse_MC, protocol does not match return from method: ($res)") ; 

				}
			}
		}
			
	}
	return 0 if (!$message_dispatched);
	return 1;
}

###############################
sub SIGNALduino_Parse($$$$@) {
  my ($hash, $iohash, $name, $rmsg, $initstr) = @_;

	#print Dumper(\%ProtocolListSIGNALduino);
	
    	
	if (!($rmsg=~ s/^\002(M.;.*;)\003/$1/)) 			# Check if a Data Message arrived and if it's complete  (start & end control char are received)
	{							# cut off start end end character from message for further processing they are not needed
		$hash->{logMethod}->($name, AttrVal($name,"noMsgVerbose",5), "$name: Parse, noMsg: $rmsg");
		return undef;
	}

	if (defined($hash->{keepalive})) {
		$hash->{keepalive}{ok}    = 1;
		$hash->{keepalive}{retry} = 0;
	}
	
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	
	
	Debug "$name: incoming message: ($rmsg)\n" if ($debug);
	
	if (AttrVal($name, "rawmsgEvent", 0)) {
		DoTrigger($name, "RAWMSG " . $rmsg);
	}
	
	my %signal_parts=SIGNALduino_Split_Message($rmsg,$name);   ## Split message and save anything in an hash %signal_parts
	#Debug "raw data ". $signal_parts{rawData};
	
	
	my $dispatched;
	# Message Synced type   -> M#

	if (@{$hash->{msIdList}} && $rmsg=~ m/^MS;(P\d=-?\d+;){3,8}D=\d+;CP=\d;SP=\d;/) 
	{
		$dispatched= SIGNALduino_Parse_MS($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Message unsynced type   -> MU
  	elsif (@{$hash->{muIdList}} && $rmsg=~ m/^MU;(P\d=-?\d+;){3,8}((CP|R)=\d+;){0,2}D=\d+;/)
	{
		$dispatched=  SIGNALduino_Parse_MU($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Manchester encoded Data   -> MC
  	elsif (@{$hash->{mcIdList}} && $rmsg=~ m/^M[cC];.*;/) 
	{
		$dispatched=  SIGNALduino_Parse_MC($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	else {
		Debug "$name: unknown Messageformat, aborting\n" if ($debug);
		return undef;
	}
	
	if ( AttrVal($hash->{NAME},"verbose","0") > 4 && !$dispatched)
	{
   	    my $notdisplist;
   	    my @lines;
   	    if (defined($hash->{unknownmessages}))
   	    {
   	    	$notdisplist=$hash->{unknownmessages};	      				
			@lines = split ('#', $notdisplist);   # or whatever
   	    }
		push(@lines,FmtDateTime(time())."-".$rmsg);
		shift(@lines)if (scalar @lines >25);
		$notdisplist = join('#',@lines);

		$hash->{unknownmessages}=$notdisplist;
		return undef;
		#Todo  compare Sync/Clock fact and length of D= if equal, then it's the same protocol!
	}
	return $dispatched;
	
}


###############################
sub SIGNALduino_Ready($) {
  my ($hash) = @_;

  if ($hash->{STATE} eq 'disconnected') {
    $hash->{DevState} = 'disconnected';
    return DevIo_OpenDev($hash, 1, "SIGNALduino_DoInit", 'SIGNALduino_Connect')
  }
  
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

###############################
sub SIGNALduino_WriteInit($) {
  my ($hash) = @_;
  
  # todo: ist dies so ausreichend, damit die Aenderungen uebernommen werden?
  SIGNALduino_AddSendQueue($hash,"WS36");   # SIDLE, Exit RX / TX, turn off frequency synthesizer 
  SIGNALduino_AddSendQueue($hash,"WS34");   # SRX, Enable RX. Perform calibration first if coming from IDLE and MCSM0.FS_AUTOCAL=1.
}

###############################
sub SIGNALduino_SimpleWrite(@) {
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq "SIGNALduino_RFR") {
    # Prefix $msg with RRBBU and return the corresponding SIGNALduino hash.
    ($hash, $msg) = SIGNALduino_RFR_AddPrefix($hash, $msg); 
  }

  my $name = $hash->{NAME};
  $hash->{logMethod}->($name, 5, "$name: SimpleWrite, $msg");

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

###############################
sub SIGNALduino_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	my $debug = AttrVal($name,"debug",0);
	
	$aVal= "" if (!defined($aVal));
	$hash->{logMethod}->($name, 4, "$name: Attr, Calling sub with args: $cmd $aName = $aVal");
		
	if( $aName eq "Clients" ) {		## Change clientList
		$hash->{Clients} = $aVal;
		$hash->{Clients} = $clientsSIGNALduino if( !$hash->{Clients}) ;				## Set defaults
		return "Setting defaults";
	} elsif( $aName eq "MatchList" ) {	## Change matchList
		my $match_list;
		if( $cmd eq "set" ) {
			$match_list = eval $aVal;
			if( $@ ) {
				$hash->{logMethod}->($name, 2, $name .": Attr, $aVal: ". $@);
			}
		}
		
		if( ref($match_list) eq 'HASH' ) {
		  $hash->{MatchList} = $match_list;
		} else {
		  $hash->{MatchList} = \%matchListSIGNALduino;								## Set defaults
		  $hash->{logMethod}->($name, 2, $name .": Attr, $aVal: not a HASH using defaults") if( $aVal );
		}
	}
	elsif ($aName eq "verbose")
	{
		$hash->{logMethod}->($name, 3, "$name: Attr, setting Verbose to: " . $aVal);
		$hash->{unknownmessages}="" if $aVal <4;
		
	}
	elsif ($aName eq "debug")
	{
		$debug = $aVal;
		$hash->{logMethod}->($name, 3, "$name: Attr, setting debug to: " . $debug);
	}
	elsif ($aName eq "whitelist_IDs")
	{
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",$aVal);
		}
	}
	elsif ($aName eq "blacklist_IDs")
	{
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,$aVal);
		}
	}
	elsif ($aName eq "development")
	{
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,undef,$aVal);
		}
	}
	elsif ($aName eq "doubleMsgCheck_IDs")
	{
		if (defined($aVal)) {
			if (length($aVal)>0) {
				if (substr($aVal,0 ,1) eq '#') {
					$hash->{logMethod}->($name, 3, "$name: Attr, doubleMsgCheck_IDs disabled: $aVal");
					delete $hash->{DoubleMsgIDs};
				}
				else {
					$hash->{logMethod}->($name, 3, "$name: Attr, doubleMsgCheck_IDs enabled: $aVal");
					my %DoubleMsgiD = map { $_ => 1 } split(",", $aVal);
					$hash->{DoubleMsgIDs} = \%DoubleMsgiD;
					#print Dumper $hash->{DoubleMsgIDs};
				}
			}
			else {
				$hash->{logMethod}->($name, 3, "$name: Attr, delete doubleMsgCheck_IDs");
				delete $hash->{DoubleMsgIDs};
			}
		}
	}
	elsif ($aName eq "cc1101_frequency")
	{
		if ($aVal eq "" || $aVal < 800) {
			$hash->{logMethod}->($name, 3, "$name: Attr, delete cc1101_frequency");
			delete ($hash->{cc1101_frequency}) if (defined($hash->{cc1101_frequency}));
		} else {
			$hash->{logMethod}->($name, 3, "$name: Attr, setting cc1101_frequency to 868");
			$hash->{cc1101_frequency} = 868;
		}
	}

	elsif ($aName eq "hardware")	# to set flashCommand if hardware def or change
	{
		# to delete flashCommand if hardware delete
		if ($cmd eq "del") {
			if (exists $attr{$name}{flashCommand}) { delete $attr{$name}{flashCommand};}
		}
	}
	elsif ($aName eq "eventlogging")	# enable / disable eventlogging
	{
		if ($aVal == 1) {
			$hash->{logMethod} = \&::SIGNALduino_Log3;	
			Log3 $name, 3, "$name: Attr, Enable eventlogging";
		} else {
			$hash->{logMethod} = \&::Log3;	
			Log3 $name, 3, "$name: Attr, Disable eventlogging";
		}
	}
		
  	return undef;
}

###############################
sub SIGNALduino_FW_Detail($@) {
  my ($FW_wname, $name, $room, $pageHash) = @_;
  
  my $hash = $defs{$name};
    
  my @dspec=devspec2array("DEF=.*fakelog");
  my $lfn = $dspec[0];
  my $fn=$defs{$name}->{TYPE}."-Flash.log";
  
  my $ret = "<div class='makeTable wide'><span>Information menu</span>
<table class='block wide' id='SIGNALduinoInfoMenue' nm='$hash->{NAME}' class='block wide'>
<tr class='even'>";


  if (-s AttrVal("global", "logdir", "./log/") .$fn)
  { 
	  my $flashlogurl="$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn";
	  
	  $ret .= "<td>";
	  $ret .= "<a href=\"$flashlogurl\">Last Flashlog<\/a>";
	  $ret .= "</td>";
	  #return $ret;
  }

  my $protocolURL="$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn";
  
  $ret.="<td><a href='#showProtocolList' id='showProtocolList'>Display protocollist</a></td>";
  $ret .= '</tr></table></div>
  
<script>
$( "#showProtocolList" ).click(function(e) {
	e.preventDefault();
	FW_cmd(FW_root+\'?cmd={SIGNALduino_FW_getProtocolList("'.$FW_detail.'")}&XHR=1\', function(data){SD_plistWindow(data)});
	
});

function SD_plistWindow(txt)
{
  var div = $("<div id=\"SD_protocolDialog\">");
  $(div).html(txt);
  $("body").append(div);
  var oldPos = $("body").scrollTop();
  var btxtStable = "";
  var btxtBlack = "";
  if ($("#SD_protoCaption").text().substr(0,1) != "d") {
  	    btxtStable = "stable";
  }
  if ($("#SD_protoCaption").text().substr(-1) == ".") {
    btxtBlack = " except blacklist";
  }
  
  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    title: "Protocollist Overview",
    buttons: [
      {text:"select all " + btxtStable + btxtBlack, click:function(){
		  $("#SD_protocolDialog table td input:checkbox").prop(\'checked\', true);
		  
		  $("input[name=SDnotCheck]").each( function () {
			  $(this).prop(\'checked\',false);
		  });
      }},
      {text:"deselect all", click:function(e){
           $("#SD_protocolDialog table td input:checkbox").prop(\'checked\', false);
      }},
      {text:"save to whitelist and close", click:function(){
      	var allVals = [];
 		  $("#SD_protocolDialog table td input:checkbox:checked").each(function() {
	    	  allVals.push($(this).val());
		  })
          FW_cmd(FW_root+ \'?XHR=1&cmd={SIGNALduino_FW_saveWhitelist("'.$name.'","\'+String(allVals)+\'")}\');
          $(this).dialog("close");
          $(div).remove();
          location.reload();
      }},
      {text:"close", click:function(){
        $(this).dialog("close");
        $(div).remove();
        location.reload();
      }}]
  });
}


</script>';
  return $ret;
}

###############################
sub SIGNALduino_FW_saveWhitelist {
	my $name = shift;
	my $wl_attr = shift;
	
	if (!IsDevice($name)) {
		Log3 undef, 3, "$name: FW_saveWhitelist, is not a valid definition, operation aborted.";
		return;
	}
	
	if ($wl_attr eq "") {	# da ein Attribut nicht leer sein kann, kommt ein Komma rein
		$wl_attr = ',';
	}
	elsif ($wl_attr !~ /\d+(?:,\d.?\d?)*$/ ) {
		Log3 $name, 3, "$name: FW_saveWhitelist, attr whitelist_IDs can not be updated";
		return;
	}
	else {
		$wl_attr =~ s/,$//;			# Komma am Ende entfernen
	}
	$attr{$name}{whitelist_IDs} = $wl_attr;
	Log3 $name, 3, "$name: FW_saveWhitelist, $wl_attr";
	SIGNALduino_IdList("x:$name", $wl_attr);
}

sub SIGNALduino_IdList($@) {
	my ($param, $aVal, $blacklist, $develop0) = @_;
	my (undef,$name) = split(':', $param);
	my $hash = $defs{$name};

	my @msIdList = ();
	my @muIdList = ();
	my @mcIdList = ();
	my @skippedDevId = ();
	my @skippedBlackId = ();
	my @skippedWhiteId = ();
	my @devModulId = ();
	my %WhitelistIDs;
	my %BlacklistIDs;
	my $wflag = 0;		# whitelist flag, 0=disabled
	
	delete ($hash->{IDsNoDispatch}) if (defined($hash->{IDsNoDispatch}));

	if (!defined($aVal)) {
		$aVal = AttrVal($name,"whitelist_IDs","");
	}
	
	my ($develop,$devFlag) = SIGNALduino_getAttrDevelopment($name, $develop0);	# $devFlag = 1 -> alle developIDs y aktivieren
	$hash->{logMethod}->($name, 3, "$name: IdList, development version active, development attribute = $develop") if ($devFlag == 1);
	
	if ($aVal eq "" || substr($aVal,0 ,1) eq '#') {		# whitelist nicht aktiv
		if ($devFlag == 1) {
			$hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist disabled or not defined (all IDs are enabled, except blacklisted): $aVal");
		}
		else {
			$hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist disabled or not defined (all IDs are enabled, except blacklisted and instable IDs): $aVal");
		}
	}
	else {
		%WhitelistIDs = map {$_ => undef} split(",", $aVal);			# whitelist in Hash wandeln
		#my $w = join ',' => map "$_" => keys %WhitelistIDs;
		$hash->{logMethod}->($name, 3, "$name: IdList, attr whitelist: $aVal");
		$wflag = 1;
	}
	#SIGNALduino_Log3 $name, 3, "$name IdList: attr whitelistIds=$aVal" if ($aVal);
		
	if ($wflag == 0) {			# whitelist not aktive
		if (!defined($blacklist)) {
			$blacklist = AttrVal($name,"blacklist_IDs","");
		}
		if (length($blacklist) > 0) {							# Blacklist in Hash wandeln
			$hash->{logMethod}->($name, 3, "$name: IdList, attr blacklistIds=$blacklist");
			%BlacklistIDs = map { $_ => 1 } split(",", $blacklist);
			#my $w = join ', ' => map "$_" => keys %BlacklistIDs;
			#SIGNALduino_Log3 $name, 3, "$name IdList, Attr blacklist $w";
		}
	}
	
	my $id;
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		if ($wflag == 1)				# whitelist active
		{
			if (!exists($WhitelistIDs{$id}))		# Id wurde in der whitelist nicht gefunden
			{
				push (@skippedWhiteId, $id);
				next;
			}
		}
		else {						# whitelist not active
			if (exists($BlacklistIDs{$id})) {
				#SIGNALduino_Log3 $name, 3, "$name: IdList, skip Blacklist ID $id";
				push (@skippedBlackId, $id);
				next;
			}
		
			# wenn es keine developId gibt, dann die folgenden Abfragen ueberspringen
			if (exists($ProtocolListSIGNALduino{$id}{developId}))
			{
				if ($ProtocolListSIGNALduino{$id}{developId} eq "m") {
					if ($develop !~ m/m$id/) {  # ist nur zur Abwaertskompatibilitaet und kann in einer der naechsten Versionen entfernt werden
						push (@devModulId, $id);
						if ($devFlag == 0) {
							push (@skippedDevId, $id);
							next;
						}
					}
				}
				elsif ($ProtocolListSIGNALduino{$id}{developId} eq "p") {
					$hash->{logMethod}->($name, 5, "$name: IdList, ID=$id skipped (developId=p), caution, protocol can cause crashes, use only if advised to do");
					next;
				}
				elsif ($devFlag == 0 && $ProtocolListSIGNALduino{$id}{developId} eq "y" && $develop !~ m/y$id/) {
					#SIGNALduino_Log3 $name, 3, "$name: IdList, ID=$id skipped (developId=y)";
					push (@skippedDevId, $id);
					next;
				}
			}
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			push (@mcIdList, $id);
		} 
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			push (@msIdList, $id);
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			$ProtocolListSIGNALduino{$id}{length_min} = SDUINO_PARSE_DEFAULT_LENGHT_MIN if (!exists($ProtocolListSIGNALduino{$id}{length_min}));	
			push (@muIdList, $id);
		}
	}

	@msIdList = sort {$a <=> $b} @msIdList;
	@muIdList = sort {$a <=> $b} @muIdList;
	@mcIdList = sort {$a <=> $b} @mcIdList;
	@skippedDevId = sort {$a <=> $b} @skippedDevId;
	@skippedBlackId = sort {$a <=> $b} @skippedBlackId;
	@skippedWhiteId = sort {$a <=> $b} @skippedWhiteId;
	
	@devModulId = sort {$a <=> $b} @devModulId;

	$hash->{logMethod}->($name, 3, "$name: IdList, MS @msIdList");
	$hash->{logMethod}->($name, 3, "$name: IdList, MU @muIdList");
	$hash->{logMethod}->($name, 3, "$name: IdList, MC @mcIdList");
	$hash->{logMethod}->($name, 5, "$name: IdList, not whitelisted skipped = @skippedWhiteId") if (scalar @skippedWhiteId > 0);
	$hash->{logMethod}->($name, 4, "$name: IdList, blacklistId skipped = @skippedBlackId") if (scalar @skippedBlackId > 0);
	$hash->{logMethod}->($name, 4, "$name: IdList, development skipped = @skippedDevId") if (scalar @skippedDevId > 0);
	if (scalar @devModulId > 0)
	{
		$hash->{logMethod}->($name, 3, "$name: IdList, development protocol is active (to activate dispatch to not finshed logical module, enable desired protocol via whitelistIDs) = @devModulId");
		$hash->{IDsNoDispatch} = join(",", @devModulId);
	}
	
	$hash->{msIdList} = \@msIdList;
	$hash->{muIdList} = \@muIdList;
	$hash->{mcIdList} = \@mcIdList;
}

###############################
sub SIGNALduino_getAttrDevelopment {
	my $name = shift;
	my $develop = shift;
	my $devFlag = 0;
	if (index(SDUINO_VERSION, "dev") >= 0) {  	# development version
		$develop = AttrVal($name,"development", 0) if (!defined($develop));
		$devFlag = 1 if ($develop eq "1" || (substr($develop,0,1) eq "y" && $develop !~ m/^y\d/));	# Entwicklerversion, y ist nur zur Abwaertskompatibilitaet und kann in einer der naechsten Versionen entfernt werden
	}
	else {
		$develop = "0";
		Log3 $name, 3, "$name: getAttrDevelopment, IdList ### Attribute development is in this version ignored ###";
	}
	return ($develop,$devFlag);
}

###############################
sub SIGNALduino_callsub {
	my $funcname =shift;
	my $method = shift;
	my $evalFirst = shift;
	my $name = shift;
	
	my @args = @_;

	my $hash = $defs{$name};
	if ( defined $method && defined &$method )   
	{
		if (defined($evalFirst) && $evalFirst)
		{
			eval( $method->($name, @args));
			if($@) {
				$hash->{logMethod}->($name, 5, "$name: callsub, Error: $funcname, has an error and will not be executed: $@ please report at github.");
				return (0,undef);
			}
		}
		#my $subname = @{[eval {&$method}, $@ =~ /.*/]};
		$hash->{logMethod}->($hash, 5, "$name: callsub, applying $funcname, value before: @args"); # method $subname"

		#SIGNALduino_Log3 $name, 5, "$name: callsub, value bevore $funcname: @args";
		
		my ($rcode, @returnvalues) = $method->($name, @args) ;	
		
		if (@returnvalues && defined($returnvalues[0])) {
	    	$hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, modified value after $funcname: @returnvalues");
		} else {
	   		$hash->{logMethod}->($name, 5, "$name: callsub, rcode=$rcode, after calling $funcname");
	    } 
	    return ($rcode, @returnvalues);
	} elsif (defined $method ) {					
		$hash->{logMethod}->($name, 5, "$name: callsub, Error: Unknown method $funcname pease report at github");
		return (0,undef);
	}	
	return (1,@args);			
}

###############################
# calculates the hex (in bits) and adds it at the beginning of the message
# input = @list
# output = @list
sub SIGNALduino_lengtnPrefix {
	my ($name, @bit_msg) = @_;
	
	my $msg = join("",@bit_msg);	

	#$msg = unpack("B8", pack("N", length($msg))).$msg;
	$msg=sprintf('%08b', length($msg)).$msg;
	
	return (1,split("",$msg));
}

###############################
sub SIGNALduino_PreparingSend_FS20_FHT($$$) {
	my ($id, $sum, $msg) = @_;
	my $temp = 0;
	my $newmsg = "P$id#0000000000001";	  # 12 Bit Praeambel, 1 bit
	
	for (my $i=0; $i<length($msg); $i+=2) {
		$temp = hex(substr($msg, $i, 2));
		$sum += $temp;
		$newmsg .= SIGNALduino_dec2binppari($temp);
	}
	
	$newmsg .= SIGNALduino_dec2binppari($sum & 0xFF);   # Checksum		
	my $repeats = $id - 71;			# FS20(74)=3, FHT(73)=2
	$newmsg .= "0P#R" . $repeats;		# EOT, Pause, 3 Repeats    
	
	return $newmsg;
}

###############################
sub SIGNALduino_dec2binppari {      # dec to bin . parity
	my $num = shift;
	my $parity = 0;
	my $nbin = sprintf("%08b",$num);
	foreach my $c (split //, $nbin) {
		$parity ^= $c;
	}
	my $result = $nbin . $parity;		# bin(num) . paritybit
	return $result;
}

###############################
sub SIGNALduino_bit2Arctec {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);	
	# Convert 0 -> 01   1 -> 10 to be compatible with IT Module
	$msg =~ s/0/z/g;
	$msg =~ s/1/10/g;
	$msg =~ s/z/01/g;
	return (1,split("",$msg)); 
}

###############################
sub SIGNALduino_bit2itv1 {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);	

	$msg =~ s/0F/01/g;		# Convert 0F -> 01 (F) to be compatible with CUL
#	$msg =~ s/0F/11/g;		# Convert 0F -> 11 (1) float
	if (index($msg,'F') == -1) {
		return (1,split("",$msg));
	} else {
		return (0,0);
	}
}

###############################
sub SIGNALduino_ITV1_tristateToBit($) {
	my ($msg) = @_;
	# Convert 0 -> 00   1 -> 11 F => 01 to be compatible with IT Module
	$msg =~ s/0/00/g;
	$msg =~ s/1/11/g;
	$msg =~ s/F/01/g;
	$msg =~ s/D/10/g;
		
	return (1,$msg);
}

sub SIGNALduino_HE800($@) {
	my ($name, @bit_msg) = @_;
	my $protolength = scalar @bit_msg;
	
	if ($protolength < 40) {
		for (my $i=0; $i<(40-$protolength); $i++) {
			push(@bit_msg, 0);
		}
	}
	return (1,@bit_msg);
}

sub SIGNALduino_HE_EU($@) {
	my ($name, @bit_msg) = @_;
	my $protolength = scalar @bit_msg;
	
	if ($protolength < 72) {
		for (my $i=0; $i<(72-$protolength); $i++) {
			push(@bit_msg, 0);
		}
	}
	return (1,@bit_msg);
}

sub SIGNALduino_postDemo_EM($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $msg_start = index($msg, "0000000001");				# find start
	my $count;
	$msg = substr($msg,$msg_start + 10);						# delete preamble + 1 bit
	my $new_msg = "";
	my $crcbyte;
	my $msgcrc = 0;
	my $hash = $defs{$name};

	if ($msg_start > 0 && length $msg == 89) {
		for ($count = 0; $count < length ($msg) ; $count +=9) {
			$crcbyte = substr($msg,$count,8);
			if ($count < (length($msg) - 10)) {
				$new_msg.= join "", reverse @bit_msg[$msg_start + 10 + $count.. $msg_start + 17 + $count];
				$msgcrc = $msgcrc ^ oct( "0b$crcbyte" );
			}
		}
		if ($msgcrc == oct( "0b$crcbyte" )) {
			$hash->{logMethod}->($name, 4, "$name: EM Protocol - CRC OK");
			return (1,split("",$new_msg));
		} else {
			$hash->{logMethod}->($name, 3, "$name: EM Protocol - CRC ERROR");
			return 0, undef;
		}
	}
	
	$hash->{logMethod}->($name, 3, "$name: EM Protocol - Start not found or length msg (".length $msg.") not correct");
	return 0, undef;
}

sub SIGNALduino_postDemo_FS20($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 6;
	my $b = 0;
	my $i = 0;
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   my $hash = $defs{$name};
   if ($datastart == $protolength) {                                 # all bits are 0
		$hash->{logMethod}->($name, 3, "$name: FS20 - ERROR message all bit are zeros");
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   $hash->{logMethod}->($name, 5, "$name: FS20 - pos=$datastart length=$protolength");
   if ($protolength == 46 || $protolength == 55) {			# If it 1 bit too long, then it will be removed (EOT-Bit)
      pop(@bit_msg);
      $protolength--;
   }
   if ($protolength == 45 || $protolength == 54) {          ### FS20 length 45 or 54
      for(my $b = 0; $b < $protolength - 9; $b += 9) {	                  # build sum over first 4 or 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[$protolength - 9 .. $protolength - 2]));   # Checksum Byte 5 or 6
      if ((($sum + 6) & 0xFF) == $checksum) {			# Message from FHT80 roothermostat
         $hash->{logMethod}->($name, 5, "$name: FS20 - Detection aborted, checksum matches FHT code");
         return 0, undef;
      }
      if (($sum & 0xFF) == $checksum) {				            ## FH20 remote control
			for(my $b = 0; $b < $protolength; $b += 9) {	            # check parity over 5 or 6 bytes
				my $parity = 0;					                                 # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					$hash->{logMethod}->($name, 3, "$name: FS20 ERROR - Parity not even");
					return 0, undef;
				}
			}																						# parity ok
			for(my $b = $protolength - 1; $b > 0; $b -= 9) {	               # delete 5 or 6 parity bits
				splice(@bit_msg, $b, 1);
			}
         if ($protolength == 45) {                       		### FS20 length 45
            splice(@bit_msg, 32, 8);                                       # delete checksum
            splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));                    # insert Byte 3
         } else {                                              ### FS20 length 54
            splice(@bit_msg, 40, 8);                                       # delete checksum
         }
			my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
			$hash->{logMethod}->($name, 4, "$name: FS20 - remote control post demodulation $dmsg length $protolength");
			return (1, @bit_msg);											## FHT80TF ok
      }
      else {
         $hash->{logMethod}->($name, 4, "$name: FS20 ERROR - wrong checksum");
      }
   }
   else {
      $hash->{logMethod}->($name, 5, "$name: FS20 ERROR - wrong length=$protolength (must be 45 or 54)");
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
	my $protolength = scalar @bit_msg;
	my $sum = 12;
	my $b = 0;
	my $i = 0;
    my $hash=$defs{$name};
	for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
		last if $bit_msg[$datastart] eq "1";
	}
	if ($datastart == $protolength) {                                 # all bits are 0
		$hash->{logMethod}->($name, 3, "$name: FHT80 - ERROR message all bit are zeros");
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   $hash->{logMethod}->($name, 5, "$name: FHT80 - pos=$datastart length=$protolength");
   if ($protolength == 55) {						# If it 1 bit too long, then it will be removed (EOT-Bit)
      pop(@bit_msg);
      $protolength--;
   }
   if ($protolength == 54) {                       		### FHT80 fixed length
      for($b = 0; $b < 45; $b += 9) {	                             # build sum over first 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[45 .. 52]));          # Checksum Byte 6
      if ((($sum - 6) & 0xFF) == $checksum) {		## Message from FS20 remote control
         $hash->{logMethod}->($name, 5, "$name: FHT80 - Detection aborted, checksum matches FS20 code");
         return 0, undef;
      }
      if (($sum & 0xFF) == $checksum) {								## FHT80 Raumthermostat
         for($b = 0; $b < 54; $b += 9) {	                              # check parity over 6 byte
            my $parity = 0;					                              # Parity even
			            for($i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
               $parity += $bit_msg[$i];
            }
            if ($parity % 2 != 0) {
               $hash->{logMethod}->($name, 3, "$name: FHT80 ERROR - Parity not even");
               return 0, undef;
            }
         }																					# parity ok
         for($b = 53; $b > 0; $b -= 9) {	                              # delete 6 parity bits
            splice(@bit_msg, $b, 1);
         }
         if ($bit_msg[26] != 1) {                                       # Bit 5 Byte 3 must 1
            $hash->{logMethod}->($name, 3, "$name: FHT80 ERROR - byte 3 bit 5 not 1");
            return 0, undef;
         }
         splice(@bit_msg, 40, 8);                                       # delete checksum
         splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));# insert Byte 3
         my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
         $hash->{logMethod}->($name, 4, "$name: FHT80 - roomthermostat post demodulation $dmsg");
         return (1, @bit_msg);											## FHT80 ok
      }
      else {
         $hash->{logMethod}->($name, 4, "$name: FHT80 ERROR - wrong checksum");
      }
   }
   else {
      $hash->{logMethod}->($name, 5, "$name: FHT80 ERROR - wrong length=$protolength (must be 54)");
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80TF($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
	my $protolength = scalar @bit_msg;
	my $sum = 12;			
	my $b = 0;
	my $hash=$defs{$name};
	if ($protolength < 46) {                                        	# min 5 bytes + 6 bits
		$hash->{logMethod}->($name, 4, "$name: FHT80TF - ERROR lenght of message < 46");
		return 0, undef;
   }
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		$hash->{logMethod}->($name, 3, "$name: FHT80TF - ERROR message all bit are zeros");
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   if ($protolength == 45) {                       		      ### FHT80TF fixed length
      for(my $b = 0; $b < 36; $b += 9) {	                             # build sum over first 4 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[36 .. 43]));          # Checksum Byte 5
      if (($sum & 0xFF) == $checksum) {									## FHT80TF Tuer-/Fensterkontakt
			for(my $b = 0; $b < 45; $b += 9) {	                           # check parity over 5 byte
				my $parity = 0;					                              # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			               # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					$hash->{logMethod}->($name, 4, "$name: FHT80TF ERROR - Parity not even");
					return 0, undef;
				}
			}																					# parity ok
			for(my $b = 44; $b > 0; $b -= 9) {	                           # delete 5 parity bits
				splice(@bit_msg, $b, 1);
			}
         if ($bit_msg[26] != 0) {                                       # Bit 5 Byte 3 must 0
            $hash->{logMethod}->($name, 3, "$name: FHT80TF ERROR - byte 3 bit 5 not 0");
            return 0, undef;
         }
			splice(@bit_msg, 32, 8);                                       # delete checksum
				my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
				$hash->{logMethod}->($name, 4, "$name: FHT80TF - door/window switch post demodulation $dmsg");
			return (1, @bit_msg);											## FHT80TF ok
      } 
   } 
   return 0, undef;
}

sub SIGNALduino_postDemo_WS7035($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $parity = 0;					# Parity even
	my $sum = 0;						# checksum
	my $hash=$defs{$name};
	$hash->{logMethod}->($name, 4, "$name: WS7035 $msg");
	if (substr($msg,0,8) ne "10100000") {		# check ident
		$hash->{logMethod}->($name, 3, "$name: WS7035 ERROR - Ident not 1010 0000");
		return 0, undef;
	} else {
		for(my $i = 15; $i < 28; $i++) {			# Parity over bit 15 and 12 bit temperature
	      $parity += substr($msg, $i, 1);
		}
		if ($parity % 2 != 0) {
			$hash->{logMethod}->($name, 3, "$name: WS7035 ERROR - Parity not even");
			return 0, undef;
		} else {
			for(my $i = 0; $i < 39; $i += 4) {			# Sum over nibble 0 - 9
				$sum += oct("0b".substr($msg,$i,4));
			}
			if (($sum &= 0x0F) != oct("0b".substr($msg,40,4))) {
				$hash->{logMethod}->($name, 3, "$name: WS7035 ERROR - Checksum");
				return 0, undef;
			} else {
				$hash->{logMethod}->($name, 4, "$name: WS7035 " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4) ." ". substr($msg,32,4) ." ". substr($msg,36,4) ." ". substr($msg,40));
				substr($msg, 27, 4, '');			# delete nibble 8
				return (1,split("",$msg));
			}
		}
	}
}

sub SIGNALduino_postDemo_WS2000($@) {
	my ($name, @bit_msg) = @_;
	my @new_bit_msg = "";
	my $protolength = scalar @bit_msg;
	my @datalenghtws = (35,50,35,50,70,40,40,85);
	my $datastart = 0;
	my $datalength = 0;
	my $datalength1 = 0;
	my $index = 0;
	my $data = 0;
	my $dataindex = 0;
	my $check = 0;
	my $sum = 5;
	my $typ = 0;
	my $adr = 0;
	my $hash=$defs{$name};
	my @sensors = (
		"Thermo",
		"Thermo/Hygro",
		"Rain",
		"Wind",
		"Thermo/Hygro/Baro",
		"Brightness",
		"Pyrano",
		"Kombi"
		);

	for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
		last if $bit_msg[$datastart] eq "1";
	}
	if ($datastart == $protolength) {                                 # all bits are 0
		$hash->{logMethod}->($name, 4, "$name: WS2000 - ERROR message all bit are zeros");
		return 0, undef;
	}
	$datalength = $protolength - $datastart;
	$datalength1 = $datalength - ($datalength % 5);  		# modulo 5
	$hash->{logMethod}->($name, 5, "$name: WS2000 protolength: $protolength, datastart: $datastart, datalength $datalength");
	$typ = oct( "0b".(join "", reverse @bit_msg[$datastart + 1.. $datastart + 4]));		# Sensortyp
	if ($typ > 7) {
		$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ - ERROR typ to big (0-7)");
		return 0, undef;
	}
	if ($typ == 1 && ($datalength == 45 || $datalength == 46)) {$datalength1 += 5;}		# Typ 1 ohne Summe
	if ($datalenghtws[$typ] != $datalength1) {												# check lenght of message
		$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ - ERROR lenght of message $datalength1 ($datalenghtws[$typ])");
		return 0, undef;
	} elsif ($datastart > 10) {									# max 10 Bit preamble
		$hash->{logMethod}->($name, 4, "$name: WS2000 ERROR preamble > 10 ($datastart)");
		return 0, undef;
	} else {
		do {
			if ($bit_msg[$index + $datastart] != 1) {			# jedes 5. Bit muss 1 sein
				$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ - ERROR checking bit $index");
				return (0, undef);
			}
			$dataindex = $index + $datastart + 1;				 
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($index == 5) {$adr = ($data & 0x07)}			# Sensoradresse
			if ($datalength == 45 || $datalength == 46) { 	# Typ 1 ohne Summe
				if ($index <= $datalength - 5) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
				}
			} else {
				if ($index <= $datalength - 10) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
					$sum += $data;
				}
			}
			$index += 5;
		} until ($index >= $datalength -1 );
	}
	if ($check != 0) {
		$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR check XOR");
		return (0, undef);
	} else {
		if ($datalength < 45 || $datalength > 46) { 			# Summe pruefen, außer Typ 1 ohne Summe
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($data != ($sum & 0x0F)) {
				$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR sum");
				return (0, undef);
			}
		}
		$hash->{logMethod}->($name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - $sensors[$typ]");
		$datastart += 1;																							# [x] - 14_CUL_WS
		@new_bit_msg[4 .. 7] = reverse @bit_msg[$datastart .. $datastart+3];							# [2]  Sensortyp
		@new_bit_msg[0 .. 3] = reverse @bit_msg[$datastart+5 .. $datastart+8];						# [1]  Sensoradresse
		@new_bit_msg[12 .. 15] = reverse @bit_msg[$datastart+10 .. $datastart+13];				# [4]  T 0.1, R LSN, Wi 0.1, B   1, Py   1
		@new_bit_msg[8 .. 11] = reverse @bit_msg[$datastart+15 .. $datastart+18];					# [3]  T   1, R MID, Wi   1, B  10, Py  10
		if ($typ == 0 || $typ == 2) {		# Thermo (AS3), Rain (S2000R, WS7000-16)
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [5]  T  10, R MSN
		} else {
			@new_bit_msg[20 .. 23] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [6]  T  10, 			Wi  10, B 100, Py 100
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+25 .. $datastart+28];			# [5]  H 0.1, 			Wr   1, B Fak, Py Fak
			if ($typ == 1 || $typ == 3 || $typ == 4 || $typ == 7) {	# Thermo/Hygro, Wind, Thermo/Hygro/Baro, Kombi
				@new_bit_msg[28 .. 31] = reverse @bit_msg[$datastart+30 .. $datastart+33];		# [8]  H   1,			Wr  10
				@new_bit_msg[24 .. 27] = reverse @bit_msg[$datastart+35 .. $datastart+38];		# [7]  H  10,			Wr 100
				if ($typ == 4) {	# Thermo/Hygro/Baro (S2001I, S2001ID)
					@new_bit_msg[36 .. 39] = reverse @bit_msg[$datastart+40 .. $datastart+43];	# [10] P    1
					@new_bit_msg[32 .. 35] = reverse @bit_msg[$datastart+45 .. $datastart+48];	# [9]  P   10
					@new_bit_msg[44 .. 47] = reverse @bit_msg[$datastart+50 .. $datastart+53];	# [12] P  100
					@new_bit_msg[40 .. 43] = reverse @bit_msg[$datastart+55 .. $datastart+58];	# [11] P Null
				}
			}
		}
		return (1, @new_bit_msg);
	}

}


sub SIGNALduino_postDemo_WS7053($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $parity = 0;	                       # Parity even
	my $hash=$defs{$name};
	$hash->{logMethod}->($name, 4, "$name: WS7053 - MSG = $msg");
	my $msg_start = index($msg, "10100000");
	if ($msg_start > 0) {                  # start not correct
		$msg = substr($msg, $msg_start);
		$msg .= "0";
		$hash->{logMethod}->($name, 5, "$name: WS7053 - cut $msg_start char(s) at begin");
	}
	if ($msg_start < 0) {                  # start not found
		$hash->{logMethod}->($name, 3, "$name: WS7053 ERROR - Ident 10100000 not found");
		return 0, undef;
	} else {
		if (length($msg) < 32) {             # msg too short
			$hash->{logMethod}->($name, 3, "$name: WS7053 ERROR - msg too short, length " . length($msg));
		return 0, undef;
		} else {
			for(my $i = 15; $i < 28; $i++) {   # Parity over bit 15 and 12 bit temperature
				$parity += substr($msg, $i, 1);
			}
			if ($parity % 2 != 0) {
				$hash->{logMethod}->($name, 3, "$name: WS7053 ERROR - Parity not even");
				return 0, undef;
			} else {
				$hash->{logMethod}->($name, 5, "$name: WS7053 before: " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4));
				# Format from 7053:  Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28-31 Zero
				my $new_msg = substr($msg,0,28) . substr($msg,16,8) . substr($msg,28,4);
				# Format for CUL_TX: Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28 - 35 Temperature (12), Bit 36-39 Zero
				$hash->{logMethod}->($name, 5, "$name: WS7053 after:  " . substr($new_msg,0,4) ." ". substr($new_msg,4,4) ." ". substr($new_msg,8,4) ." ". substr($new_msg,12,4) ." ". substr($new_msg,16,4) ." ". substr($new_msg,20,4) ." ". substr($new_msg,24,4) ." ". substr($new_msg,28,4) ." ". substr($new_msg,32,4) ." ". substr($new_msg,36,4));
				return (1,split("",$new_msg));
			}
		}
	}
}


# manchester method

sub SIGNALduino_GROTHE() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	#my $debug = AttrVal($name,"debug",0);
	my $bitLength;
	$bitData = substr($bitData, 0, $mcbitnum);
	my $preamble = "01000111";
	my $pos = index($bitData, $preamble);
	my $hash=$defs{$name};
	
	if ($pos < 0 || $pos > 5) {
		$hash->{logMethod}->( $name, 3, "$name: GROTHE protocol-Id $id, start pattern ($preamble) not found");	
		return (-1,"Start pattern ($preamble) not found");
	} else {
		if ($pos == 1) {		# eine Null am Anfang zuviel
			$bitData =~ s/^0//;		# eine Null am Anfang entfernen
		}
		$bitLength = length($bitData);
		my ($rcode, $rtxt) = SIGNALduino_TestLength($name, $id, $bitLength, "GROTHE ID=$id");
		if (!$rcode) {
			$hash->{logMethod}->( $name, 3, "$name: GROTHE protocol-Id $id, $rtxt");	
			return (-1,"$rtxt");
		}
	}
	my $hex=SIGNALduino_b2h($bitData);
	$hash->{logMethod}->( $name, 4, "$name: GROTHE protocol-Id $id detected, $bitData ($bitLength)");	
	return (1,$hex); ## Return the bits unchanged in hex
}

sub SIGNALduino_MCTFA {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;

	#if ($bitData =~ m/^.?(1){16,24}0101/)  {  
	if ($bitData =~ m/(1{9}101)/ )
	{
		my $hash=$defs{$name};
		$preamble_pos=$+[1];
		$hash->{logMethod}->($name, 4, "$name: TFA 30.3208.0 preamble_pos = $preamble_pos");
		return return (-1," sync not found") if ($preamble_pos <=0);
		my @messages;
		
		my $i=1;
		my $retmsg = "";
		do 
		{
			$message_end = index($bitData,"1111111111101",$preamble_pos); 
			if ($message_end < $preamble_pos)
			{
				$message_end=$mcbitnum;		# length($bitData);
			} 
			$message_length = ($message_end - $preamble_pos);			
			
			my $part_str=substr($bitData,$preamble_pos,$message_length);
			#$part_str = substr($part_str,0,52) if (length($part_str)) > 52;

			$hash->{logMethod}->($name, 4, "$name: TFA message start($i)=$preamble_pos end=$message_end with length=$message_length");
			$hash->{logMethod}->($name, 5, "$name: TFA message part($i)=$part_str");
			
			my ($rcode, $rtxt) = SIGNALduino_TestLength($name, $id, $message_length, "TFA message part($i)");
			if ($rcode) {
				my $hex=SIGNALduino_b2h($part_str);
				push (@messages,$hex);
				$hash->{logMethod}->($name, 4, "$name: TFA message part($i)=$hex");
			}
			else {
				$retmsg = ", " . $rtxt;
			}
			
			$preamble_pos=index($bitData,"1101",$message_end)+4;
			$i++;
		}  while ($message_end < $mcbitnum);
		
		my %seen;
		my @dupmessages = map { 1==$seen{$_}++ ? $_ : () } @messages;
		
		return ($i,"loop error, please report this data $bitData") if ($i==10);
		if (scalar(@dupmessages) > 0 ) {
			$hash->{logMethod}->($name, 4, "$name: repeated hex ".$dupmessages[0]." found ".$seen{$dupmessages[0]}." times");
			return  (1,$dupmessages[0]);
		} else {  
			return (-1," no duplicate found$retmsg");
		}
	}
	return (-1,undef);
	
}


sub SIGNALduino_OSV2 {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;
	my $msg_start;
	my $hash=$defs{$name};

	#$bitData =~ tr/10/01/;
	if ($bitData =~ m/^.?(01){12,17}.?10011001/) 
	{  	
		# Valid OSV2 detected!	
		#$preamble_pos=index($bitData,"10011001",24);
		$preamble_pos=$+[1];
		
		$hash->{logMethod}->($name, 4, "$name: OSV2 protocol detected: preamble_pos = $preamble_pos");
		return return (-1," sync not found") if ($preamble_pos <24);
		
		$message_end=$-[1] if ($bitData =~ m/^.{44,}(01){16,17}.?10011001/); #Todo regex .{44,} 44 should be calculated from $preamble_pos+ min message lengh (44)
		if (!defined($message_end) || $message_end < $preamble_pos) {
			$message_end = length($bitData);
		} else {
			$message_end += 16;
			$hash->{logMethod}->($name, 4, "$name: OSV2 message end pattern found at pos $message_end  lengthBitData=".length($bitData));
		}
		$message_length = ($message_end - $preamble_pos)/2;

		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		my $idx=0;
		my $osv2bits="";
		my $osv2hex ="";
		
		for ($idx=$preamble_pos;$idx<$message_end;$idx=$idx+16)
		{
			if ($message_end-$idx < 8 )
			{
			  last;
			}
			my $osv2byte = "";
			$osv2byte=NULL;
			$osv2byte=substr($bitData,$idx,16);

			my $rvosv2byte="";
			
			for (my $p=0;$p<length($osv2byte);$p=$p+2)
			{
				$rvosv2byte = substr($osv2byte,$p,1).$rvosv2byte;
			}
			$rvosv2byte =~ tr/10/01/;
			
			if (length($rvosv2byte) eq 8) {
				$osv2hex=$osv2hex.sprintf('%02X', oct("0b$rvosv2byte"))  ;
			} else {
				$osv2hex=$osv2hex.sprintf('%X', oct("0b$rvosv2byte"))  ;
			}
			$osv2bits = $osv2bits.$rvosv2byte;
		}
		$osv2hex = sprintf("%02X", length($osv2hex)*4).$osv2hex;
		$hash->{logMethod}->($name, 4, "$name: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits");
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv2hex);
	}
	elsif ($bitData =~ m/1{12,24}(0101)/g) {  # min Preamble 12 x 1, Valid OSV3 detected!	
		$preamble_pos = $-[1];
		$msg_start = $preamble_pos + 4;
		if ($bitData =~ m/\G.+?(1{24})0101/) {		#  preamble + sync der zweiten Nachricht
			$message_end = $-[1];
			$hash->{logMethod}->($name, 4, "$name: OSV3 protocol with two messages detected: length of second message = " . ($mcbitnum - $message_end - 28));
		}
		else {		# es wurde keine zweite Nachricht gefunden
			$message_end = $mcbitnum;
		}
		$message_length = $message_end - $msg_start;
		#SIGNALduino_Log3 $name, 4, "$name: OSV3: bitdata=$bitData";
		$hash->{logMethod}->($name, 4, "$name: OSV3 protocol detected: msg_start = $msg_start, message_length = $message_length");
		return (-1," message with length ($message_length) is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		
		my $idx=0;
		#my $osv3bits="";
		my $osv3hex ="";
		
		for ($idx=$msg_start; $idx<$message_end; $idx=$idx+4)
		{
			if (length($bitData)-$idx  < 4 )
			{
			  last;
			}
			my $osv3nibble = "";
			$osv3nibble=NULL;
			$osv3nibble=substr($bitData,$idx,4);

			my $rvosv3nibble="";
			
			for (my $p=0;$p<length($osv3nibble);$p++)
			{
				$rvosv3nibble = substr($osv3nibble,$p,1).$rvosv3nibble;
			}
			$osv3hex=$osv3hex.sprintf('%X', oct("0b$rvosv3nibble"));
			#$osv3bits = $osv3bits.$rvosv3nibble;
		}
		$hash->{logMethod}->($name, 4, "$name: OSV3 protocol =                     $osv3hex");
		my $korr = 10;
		# Check if nibble 1 is A
		if (substr($osv3hex,1,1) ne 'A')
		{
			my $n1=substr($osv3hex,1,1);
			$korr = hex(substr($osv3hex,3,1));
			substr($osv3hex,1,1,'A');  # nibble 1 = A
			substr($osv3hex,3,1,$n1); # nibble 3 = nibble1
		}
		# Korrektur nibble
		my $insKorr = sprintf('%X', $korr);
		# Check for ending 00
		if (substr($osv3hex,-2,2) eq '00')
		{
			#substr($osv3hex,1,-2);  # remove 00 at end
			$osv3hex = substr($osv3hex, 0, length($osv3hex)-2);
		}
		my $osv3len = length($osv3hex);
		$osv3hex .= '0';
		my $turn0 = substr($osv3hex,5, $osv3len-4);
		my $turn = '';
		for ($idx=0; $idx<$osv3len-5; $idx=$idx+2) {
			$turn = $turn . substr($turn0,$idx+1,1) . substr($turn0,$idx,1);
		}
		$osv3hex = substr($osv3hex,0,5) . $insKorr . $turn;
		$osv3hex = substr($osv3hex,0,$osv3len+1);
		$osv3hex = sprintf("%02X", length($osv3hex)*4).$osv3hex;
		$hash->{logMethod}->($name, 4, "$name: OSV3 protocol converted to hex: ($osv3hex) with length (".((length($osv3hex)-2)*4).") bits");
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv3hex);
		
	}
	return (-1,undef);
}

sub SIGNALduino_OSV1() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $mcbitnum < $ProtocolListSIGNALduino{$id}{length_min} );
	return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $mcbitnum > $ProtocolListSIGNALduino{$id}{length_max} );

	if (substr($bitData,20,1) != 0) {
		$bitData =~ tr/01/10/; # invert message and check if it is possible to deocde now
	}
	my $hash=$defs{$name};
	my $calcsum = oct( "0b" . reverse substr($bitData,0,8));
	$calcsum += oct( "0b" . reverse substr($bitData,8,8));
	$calcsum += oct( "0b" . reverse substr($bitData,16,8));
	$calcsum = ($calcsum & 0xFF) + ($calcsum >> 8);
	my $checksum = oct( "0b" . reverse substr($bitData,24,8));
 
	if ($calcsum != $checksum) {	                        # Checksum
		return (-1,"OSV1 - ERROR checksum not equal: $calcsum != $checksum");
	} 
 
	$hash->{logMethod}->($name, 4, "$name: OSV1 input data: $bitData");
	my $newBitData = "00001010";                       # Byte 0:   Id1 = 0x0A
    $newBitData .= "01001101";                         # Byte 1:   Id2 = 0x4D
	my $channel = substr($bitData,6,2);						# Byte 2 h: Channel
	if ($channel == "00") {										# in 0 LSB first
		$newBitData .= "0001";									# out 1 MSB first
	} elsif ($channel == "10") {								# in 4 LSB first
		$newBitData .= "0010";									# out 2 MSB first
	} elsif ($channel == "01") {								# in 4 LSB first
		$newBitData .= "0011";									# out 3 MSB first
	} else {															# in 8 LSB first
		return (-1,"$name: OSV1 - ERROR channel not valid: $channel");
    }
    $newBitData .= "0000";                             # Byte 2 l: ????
    $newBitData .= "0000";                             # Byte 3 h: address
    $newBitData .= reverse substr($bitData,0,4);       # Byte 3 l: address (Rolling Code)
    $newBitData .= reverse substr($bitData,8,4);       # Byte 4 h: T 0,1
    $newBitData .= "0" . substr($bitData,23,1) . "00"; # Byte 4 l: Bit 2 - Batterie 0=ok, 1=low (< 2,5 Volt)
    $newBitData .= reverse substr($bitData,16,4);      # Byte 5 h: T 10
    $newBitData .= reverse substr($bitData,12,4);      # Byte 5 l: T 1
    $newBitData .= "0000";                             # Byte 6 h: immer 0000
    $newBitData .= substr($bitData,21,1) . "000";      # Byte 6 l: Bit 3 - Temperatur 0=pos | 1=neg, Rest 0
    $newBitData .= "00000000";                         # Byte 7: immer 0000 0000
    # calculate new checksum over first 16 nibbles
    $checksum = 0;       
    for (my $i = 0; $i < 64; $i = $i + 4) {
       $checksum += oct( "0b" . substr($newBitData, $i, 4));
    }
    $checksum = ($checksum - 0xa) & 0xff;
    $newBitData .= sprintf("%08b",$checksum);          # Byte 8:   new Checksum 
    $newBitData .= "00000000";                         # Byte 9:   immer 0000 0000
    my $osv1hex = "50" . SIGNALduino_b2h($newBitData); # output with length before
    $hash->{logMethod}->($name, 4, "$name: OSV1 protocol id $id translated to RFXSensor format");
    $hash->{logMethod}->($name, 4, "$name: converted to hex: $osv1hex");
    return (1,$osv1hex);
   
}

sub	SIGNALduino_AS() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	if(index($bitData,"1100",16) >= 0) # $rawData =~ m/^A{2,3}/)
	{  # Valid AS detected!	
		my $message_start = index($bitData,"1100",16);
		Debug "$name: AS protocol detected \n" if ($debug);
		
		my $message_end=index($bitData,"1100",$message_start+16);
		$message_end = length($bitData) if ($message_end == -1);
		my $message_length = $message_end - $message_start;
		
		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		
		my $msgbits =substr($bitData,$message_start);
		
		my $ashex=sprintf('%02X', oct("0b$msgbits"));
		my $hash=$defs{$name};
		$hash->{logMethod}->($name, 5, "$name: AS protocol converted to hex: ($ashex) with length ($message_length) bits \n");

		return (1,$bitData);
	}
	return (-1,undef);
}

sub	SIGNALduino_Hideki() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
    Debug "$name: search in $bitData \n" if ($debug);
	my $message_start = index($bitData,"10101110");
	my $invert = 0;
	
	if ($message_start < 0) {
	$bitData =~ tr/01/10/;									# invert message
	$message_start = index($bitData,"10101110");			# 0x75 but in reverse order
	$invert = 1;
	}
	
	my $hash=$defs{$name};
	if ($message_start >= 0 )   # 0x75 but in reverse order
	{
		Debug "$name: Hideki protocol (invert=$invert) detected \n" if ($debug);

		# Todo: Mindest Laenge fuer startpunkt vorspringen 
		# Todo: Wiederholung auch an das Modul weitergeben, damit es dort geprueft werden kann
		my $message_end = index($bitData,"10101110",$message_start+71); # pruefen auf ein zweites 0x75,  mindestens 72 bit nach 1. 0x75, da der Regensensor minimum 8 Byte besitzt je byte haben wir 9 bit
        $message_end = length($bitData) if ($message_end == -1);
        my $message_length = $message_end - $message_start;
		
		return (-1,"message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1,"message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );

		
		my $hidekihex = "";
		my $idx;
		
		for ($idx=$message_start; $idx<$message_end; $idx=$idx+9)
		{
			my $byte = "";
			$byte= substr($bitData,$idx,8); ## Ignore every 9th bit
			Debug "$name: byte in order $byte " if ($debug);
			$byte = scalar reverse $byte;
			Debug "$name: byte reversed $byte , as hex: ".sprintf('%X', oct("0b$byte"))."\n" if ($debug);

			$hidekihex=$hidekihex.sprintf('%02X', oct("0b$byte"));
		}

		if ($invert == 0) {
			$hash->{logMethod}->($name, 4, "$name: receive Hideki protocol not inverted");
		} else {
			$hash->{logMethod}->($name, 4, "$name: receive Hideki protocol inverted");
		}
		$hash->{logMethod}->($name, 4, "$name: Hideki protocol converted to hex: $hidekihex with " .$message_length ." bits, messagestart $message_start");

		return  (1,$hidekihex); ## Return only the original bits, include length
	}
	$hash->{logMethod}->($name, 4, "$name: hideki start pattern (10101110) not found");
	return (-1,"Start pattern (10101110) not found");
}


sub SIGNALduino_Maverick() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(101010101001100110010101).*/) 
	{  # Valid Maverick header detected	
		my $header_pos=$+[1];
		my $hash=$defs{$name};
	
		$hash->{logMethod}->($name, 4, "$name: Maverick protocol detected: header_pos = $header_pos");

		my $hex=SIGNALduino_b2h(substr($bitData,$header_pos,26*4));
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}

sub SIGNALduino_OSPIR() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(1{14}|0{14}).*/) 
	{  # Valid Oregon PIR detected	
		my $header_pos=$+[1];
		my $hash=$defs{$name};
		$hash->{logMethod}->($name, 4, "$name: Oregon PIR protocol detected: header_pos = $header_pos");

		my $hex=SIGNALduino_b2h($bitData);
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}


sub SIGNALduino_SomfyRTS() {
	my ($name, $bitData,$id,$mcbitnum) = @_;
	
    #(my $negBits = $bitData) =~ tr/10/01/;   # Todo: eventuell auf pack umstellen

	if (defined($mcbitnum)) {
		my $hash=$defs{$name};
		$hash->{logMethod}->($name, 4, "$name: Somfy bitdata: $bitData ($mcbitnum)");
		if ($mcbitnum == 57) {
			$bitData = substr($bitData, 1, 56);
			$hash->{logMethod}->($name, 4, "$name: Somfy bitdata: _$bitData (" . length($bitData) . "). Bit am Anfang entfernt");
		}
	}
	my $encData = SIGNALduino_b2h($bitData);

	#SIGNALduino_Log3 $name, 4, "$name: Somfy RTS protocol enc: $encData";
	return (1, $encData);
}


sub SIGNALduino_TestLength {
	my ($name, $id, $message_length, $logMsg) = @_;
	my $hash=$defs{$name} if (defined($name) && exists($defs{$name}));
	if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min}) {
		$hash->{logMethod}->($name, 4, "$name: $logMsg: message with length=$message_length is to short") if (defined($logMsg));
		return (0, "message is to short");
	}
	elsif (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max}) {
		$hash->{logMethod}->($name, 4, "$name: $logMsg: message with length=$message_length is to long") if (defined($logMsg));
		return (0, "message is to long");
	}
	return (1,"");
}

# - - - - - - - - - - - -
#=item SIGNALduino_filterMC()
#This functons, will act as a filter function. It will decode MU data via Manchester encoding
# 
# Will return  $count of ???,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterMC($$$%) {
	
	## Warema Implementierung : Todo variabel gestalten
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	my ($ht, $hasbit, $value) = 0;
	$value=1 if (!$debug);
	my @bitData;
	my @sigData = split "",$rawData;

	foreach my $pulse (@sigData)
	{
	  next if (!defined($patternListRaw{$pulse})); 
	  #SIGNALduino_Log3 $name, 4, "$name: pulese: ".$patternListRaw{$pulse};
		
	  if (SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))
	  {
		# Short	
		$hasbit=$ht;
		$ht = $ht ^ 0b00000001;
		$value='S' if($debug);
		#SIGNALduino_Log3 $name, 4, "$name: filter S ";
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs}*2,abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5)) {
	  	# Long
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
		#SIGNALduino_Log3 $name, 4, "$name: filter L ";	
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{syncabs}+(2*$ProtocolListSIGNALduino{$id}{clockabs}),abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))  {
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
	  	#SIGNALduino_Log3 $name, 4, "$name: sync L ";
	
	  } else {
	  	# No Manchester Data
	  	$ht=0;
	  	$hasbit=0;
	  	#SIGNALduino_Log3 $name, 4, "$name: filter n ";
	  }
	  
	  if ($hasbit && $value) {
	  	$value = lc($value) if($debug && $patternListRaw{$pulse} < 0);
	  	my $bit=$patternListRaw{$pulse} > 0 ? 1 : 0;
	  	#SIGNALduino_Log3 $name, 5, "$name: adding value: ".$bit;
	  	
	  	push @bitData, $bit ;
	  }
	}

	my %patternListRawFilter;
	
	$patternListRawFilter{0} = 0;
	$patternListRawFilter{1} = $ProtocolListSIGNALduino{$id}{clockabs};
	
	#SIGNALduino_Log3 $name, 5, "$name: filterbits: ".@bitData;
	$rawData = join "", @bitData;
	return (undef ,$rawData, %patternListRawFilter);
	
}

# - - - - - - - - - - - -
#=item SIGNALduino_filterSign()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterSign($$$%) {
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    %patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sign from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.25))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=abs($patternListRaw{$key});
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}


# - - - - - - - - - - - -
#=item SIGNALduino_compPattern()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_compPattern($$$%) {
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    #%patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sing from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.4))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=$patternListRaw{$key};
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}



################################################
# the new Log with integrated loglevel checking
sub SIGNALduino_Log3($$$) {
  
  my ($dev, $loglevel, $text) = @_;
  my $name =$dev;
  $name= $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
  
  DoTrigger($dev,"$name $loglevel: $text");
  
  return Log3($name,$loglevel,$text);
}


################################################
# Helper to get a reference of the protocolList Hash
sub SIGNALduino_getProtocolList() {
	return \%ProtocolListSIGNALduino
}


sub SIGNALduino_FW_getProtocolList {
	my $name = shift;
	
	my $hash = $defs{$name};
	my $id;
	my $ret;
	my $devText = "";
	my $blackTxt = "";
	my %BlacklistIDs;
	my @IdList = ();
	my $comment;
	
	my $blacklist = AttrVal($name,"blacklist_IDs","");
	if (length($blacklist) > 0) {							# Blacklist in Hash wandeln
		#SIGNALduino_Log3 $name, 5, "$name getProtocolList: attr blacklistIds=$blacklist";
		%BlacklistIDs = map { $_ => 1 } split(",", $blacklist);;
	}
	
	my $whitelist = AttrVal($name,"whitelist_IDs","#");
	if (AttrVal($name,"blacklist_IDs","") ne "") {				# wenn es eine blacklist gibt, dann "." an die Ueberschrift anhaengen
		$blackTxt = ".";
	}
	
	my ($develop,$devFlag) = SIGNALduino_getAttrDevelopment($name);	# $devFlag = 1 -> alle developIDs y aktivieren
	$devText = "development version - " if ($devFlag == 1);
	
	my %activeIdHash;
	@activeIdHash{@{$hash->{msIdList}}, @{$hash->{muIdList}}, @{$hash->{mcIdList}}} = (undef);
	#SIGNALduino_Log3 $name,4, "$name IdList: $mIdList";
	
	my %IDsNoDispatch;
	if (defined($hash->{IDsNoDispatch})) {
		%IDsNoDispatch = map { $_ => 1 } split(",", $hash->{IDsNoDispatch});
		#SIGNALduino_Log3 $name,4, "$name IdList IDsNoDispatch=" . join ', ' => map "$_" => keys %IDsNoDispatch;
	}
	
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		push (@IdList, $id);
	}
	@IdList = sort { $a <=> $b } @IdList;

	$ret = "<table class=\"block wide internals wrapcolumns\">";
	
	$ret .="<caption id=\"SD_protoCaption\">$devText";
	if (substr($whitelist,0,1) ne "#") {
		$ret .="whitelist active$blackTxt</caption>";
	}
	else {
		$ret .="whitelist not active (save activate it)$blackTxt</caption>";
	}
	$ret .= "<thead style=\"text-align:center\"><td>act.</td><td>dev</td><td>ID</td><td>Msg Type</td><td>modulname</td><td>protocolname</td> <td># comment</td></thead>";
	$ret .="<tbody>";
	my $oddeven="odd";
	my $checked;
	my $checkAll;
	
	foreach $id (@IdList)
	{
		my $msgtype = "";
		my $chkbox;
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			$msgtype = "MC";
		}
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			$msgtype = "MS";
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			$msgtype = "MU";
		}
		
		$checked="";
		
		if (substr($whitelist,0,1) ne "#") {	# whitelist aktiv, dann ermitteln welche ids bei select all nicht checked sein sollen
			$checkAll = "SDcheck";
			if (exists($BlacklistIDs{$id})) {
				$checkAll = "SDnotCheck";
			}
			elsif (exists($ProtocolListSIGNALduino{$id}{developId})) {
				if ($devFlag == 1 && $ProtocolListSIGNALduino{$id}{developId} eq "p") {
					$checkAll = "SDnotCheck";
				}
				elsif ($devFlag == 0 && $ProtocolListSIGNALduino{$id}{developId} eq "y" && $develop !~ m/y$id/) {
					$checkAll = "SDnotCheck";
				}
				elsif ($devFlag == 0 && $ProtocolListSIGNALduino{$id}{developId} eq "m") {
					$checkAll = "SDnotCheck";
				}
			}
		}
		else {
			$checkAll = "SDnotCheck";
		}
		
		if (exists($activeIdHash{$id}))
		{
			$checked="checked";
			if (substr($whitelist,0,1) eq "#") {	# whitelist nicht aktiv, dann entspricht select all dem $activeIdHash 
				$checkAll = "SDcheck";
			}
		}
		
		if ($devFlag == 0 && exists($ProtocolListSIGNALduino{$id}{developId}) && $ProtocolListSIGNALduino{$id}{developId} eq "p") {
			$chkbox="<div> </div>";
		}
		else {
			$chkbox=sprintf("<INPUT type=\"checkbox\" name=\"%s\" value=\"%s\" %s/>", $checkAll, $id, $checked);
		}
		
		$comment = SIGNALduino_getProtoProp($id,"comment","");
		if (exists($IDsNoDispatch{$id})) {
			$comment .= " (dispatch is only with a active whitelist possible)";
		}
		
		$ret .= sprintf("<tr class=\"%s\"><td>%s</td><td><div>%s</div></td><td><div>%3s</div></td><td><div>%s</div></td><td><div>%s</div></td><td><div>%s</div></td><td><div>%s</div></td></tr>",$oddeven,$chkbox,SIGNALduino_getProtoProp($id,"developId",""),$id,$msgtype,SIGNALduino_getProtoProp($id,"clientmodule",""),SIGNALduino_getProtoProp($id,"name",""),$comment);
		$oddeven= $oddeven eq "odd" ? "even" : "odd" ;
		
		$ret .= "\n";
	}
	$ret .= "</tbody></table>";
	return $ret;
}


sub SIGNALduino_querygithubreleases {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $param = {
                    url        => "https://api.github.com/repos/RFD-FHEM/SIGNALDuino/releases",
                    timeout    => 5,
                    hash       => $hash,                                                                                 # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                    method     => "GET",                                                                                 # Lesen von Inhalten
                    header     => "User-Agent: perl_fhem\r\nAccept: application/json",  								 # Den Header gemaess abzufragender Daten aendern
                    callback   =>  \&SIGNALduino_githubParseHttpResponse,                                                # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                    command    => "queryReleases"
                    
                };
	HttpUtils_NonblockingGet($param);                                                                                     # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 
}


#return -10 = hardeware attribute is not set
sub SIGNALduino_githubParseHttpResponse($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $hardware=AttrVal($name,"hardware",undef);
    
    if($err ne "")                                                                                                         # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        Log3 $name, 3, "$name: githubParseHttpResponse, error while requesting ".$param->{url}." - $err (command: $param->{command}";                                                  # Eintrag fuers Log
        #readingsSingleUpdate($hash, "fullResponse", "ERROR");                                                              # Readings erzeugen
    }
    elsif($data ne "" && defined($hardware))                                                                                                     # wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
    {
    	
    	my $json_array = decode_json($data);
    	#print  Dumper($json_array);
       	if ($param->{command} eq "queryReleases") {
	        #Log3 $name, 3, "$name: githubParseHttpResponse, url ".$param->{url}." returned: $data";                                                            # Eintrag fuers Log
			
			my $releaselist="";
			if (ref($json_array) eq "ARRAY") {
				foreach my $item( @$json_array ) { 
					next if (AttrVal($name,"updateChannelFW","stable") eq "stable" && $item->{prerelease});

					#Debug " item = ".Dumper($item);
					
					foreach my $asset (@{$item->{assets}})
					{
						next if ($asset->{name} !~ m/$hardware/i);
						$releaselist.=$item->{tag_name}."," ;		
						last;
					}
					
				}
			}
			
			$releaselist =~ s/,$//;
		  	$hash->{additionalSets}{flash} = $releaselist;
    	} elsif ($param->{command} eq "getReleaseByTag" && defined($hardware)) {
			#Debug " json response = ".Dumper($json_array);
			
			my @fwfiles;
			foreach my $asset (@{$json_array->{assets}})
			{
				my %fileinfo;
				if ( $asset->{name} =~ m/$hardware/i)  
				{
					$fileinfo{filename} = $asset->{name};
					$fileinfo{dlurl} = $asset->{browser_download_url};
					$fileinfo{create_date} = $asset->{created_at};
					#Debug " firmwarefiles = ".Dumper(@fwfiles);
					push @fwfiles, \%fileinfo;
					
					my $set_return = SIGNALduino_Set($hash,$name,"flash",$asset->{browser_download_url}); # $hash->{SetFn
					if(defined($set_return))
					{
						$hash->{logMethod}->($name, 3, "$name: githubParseHttpResponse, Error while trying to download firmware: $set_return");    	
					} 
					last;
					
				}
			}
			
    	} 
    } elsif (!defined($hardware))  {
    	$hash->{logMethod}->($name, 5, "$name: githubParseHttpResponse, hardware is not defined");    	
    }                                                                                              # wenn
    # Damit ist die Abfrage zuende.
    # Evtl. einen InternalTimer neu schedulen
    FW_directNotify("FILTER=$name", "#FHEMWEB:$FW_wname", "location.reload('true')", "");
	return 0;
}

1;

=pod
=item summary    supports the same low-cost receiver for digital signals
=item summary_DE Unterstuetzt den gleichnamigen Low-Cost Empfaenger fuer digitale Signale
=begin html

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

	<table>
	<tr><td>
	The SIGNALduino ia based on an idea from mdorenka published at <a href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>. With the opensource firmware (see this <a href="https://github.com/RFD-FHEM/SIGNALduino">link</a>) it is capable to receive and send different protocols over different medias. Currently are 433Mhz protocols implemented.<br><br>
	The following device support is currently available:<br><br>
	Wireless switches<br>
	<ul>
		<li>ITv1 & ITv3/Elro and other brands using pt2263 or arctech protocol--> uses IT.pm<br>In the ITv1 protocol is used to sent a default ITclock from 250 and it may be necessary in the IT-Modul to define the attribute ITclock</li>
    		<li>ELV FS10 -> 10_FS10</li>
    		<li>ELV FS20 -> 10_FS20</li>
	</ul>
	<br>
	Temperature / humidity sensors
	<ul>
		<li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 and many more -> 14_CUL_TCM97001 </li>
		<li>Oregon Scientific v2 and v3 Sensors  -> 41_OREGON.pm</li>
		<li>Temperatur / humidity sensors suppored -> 14_SD_WS07</li>
    		<li>technoline WS 6750 and TX70DTH -> 14_SD_WS07</li>
    		<li>Eurochon EAS 800z -> 14_SD_WS07</li>
    		<li>CTW600, WH1080	-> 14_SD_WS09 </li>
    		<li>Hama TS33C, Bresser Thermo/Hygro Sensor -> 14_Hideki</li>
    		<li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07</li>
    		<li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    		<li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
	</ul>
	<br>
	It is possible to attach more than one device in order to get better reception, fhem will filter out duplicate messages. See more at the <a href="#global">global</a> section with attribute dupTimeout<br><br>
	Note: this module require the Device::SerialPort or Win32::SerialPort module. It can currently only attatched via USB.
	</td>
	</tr>
	</table>
	<br>
	<a name="SIGNALduinodefine"></a>
	<b>Define</b>
	<ul><code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code></ul>
	USB-connected devices (SIGNALduino):<br>
	<ul>
		<li>
		&lt;device&gt; specifies the serial port to communicate with the SIGNALduino. The name of the serial-device depends on your distribution, under linux the cdc_acm kernel module is responsible, and usually a /dev/ttyACM0 or /dev/ttyUSB0 device will be created. If your distribution does not have a	cdc_acm module, you can force usbserial to handle the SIGNALduino by the following command:
		<ul>		
			<li>modprobe usbserial</li>
			<li>vendor=0x03eb</li>
			<li>product=0x204b</li>
		</ul>
		In this case the device is most probably /dev/ttyUSB0.<br><br>
		You can also specify a baudrate if the device name contains the @ character, e.g.: /dev/ttyACM0@57600<br><br>This is also the default baudrate.<br>
		It is recommended to specify the device via a name which does not change:<br>
		e.g. via by-id devicename: /dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600<br>
		If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the perl module Device::SerialPort is not needed, and fhem opens the device with simple file io. This might work if the operating system uses sane defaults for the serial parameters, e.g. some Linux distributions and OSX.<br><br>
		</li>
	</ul>
	<a name="SIGNALduinointernals"></a>
	<b>Internals</b>
	<ul>
		<li><b>IDsNoDispatch</b>: Here are protocols entryls listed by their numeric id for which not communication to a logical module is enabled. To enable, look at the menu option <a href="#SIGNALduinoDetail">Display protocollist</a>.</li>
		<li><b>LASTDMSGID</b>: This shows the last dispatched Protocol ID.</li>
		<li><b>NR_CMD_LAST_H</b>: Number of messages sent within the last hour.</li>
		<li><b>RAWMSG</b>: last received RAWMSG</li>
		<li><b>version</b>: This shows the version of the SIGNALduino microcontroller.</li>
		<li><b>versionProtocols</b>: This shows the version of SIGNALduino protocol file.</li>
		<li><b>versionmodule</b>: This shows the version of the SIGNALduino FHEM module itself.</li>
	</ul>
	
	<a name="SIGNALduinoset"></a>
	<b>Set</b>
	<ul>
		<li>freq / bWidth / patable / rAmpl / sens<br>
		Only with CC1101 receiver.<br>
		Set the sduino frequency / bandwidth / PA table / receiver-amplitude / sensitivity<br>
		
		Use it with care, it may destroy your hardware and it even may be
		illegal to do so. Note: The parameters used for RFR transmission are
		not affected.<br>
		<ul>
			<a name="cc1101_freq"></a>
			<li><code>cc1101_freq</code> sets both the reception and transmission frequency. Note: Although the CC1101 can be set to frequencies between 315 and 915 MHz, the antenna interface and the antenna is tuned for exactly one frequency. Default is 433.920 MHz (or 868.350 MHz). If not set, frequency from <code>cc1101_frequency</code> attribute will be set.</li>
			<a name="cc1101_bWidth"></a>
			<li><code>cc1101_bWidth</code> can be set to values between 58 kHz and 812 kHz. Large values are susceptible to interference, but make possible to receive inaccurately calibrated transmitters. It affects tranmission too. Default is 325 kHz.</li>
			<a name="cc1101_patable"></a>
			<li><code>cc1101_patable</code> change the PA table (power amplification for RF sending)</li>
			<a name="cc1101_rAmpl"></a>
			<li><code>cc1101_rAmpl</code> is receiver amplification, with values between 24 and 42 dB. Bigger values allow reception of weak signals. Default is 42.</li>
			<a name="cc1101_sens"></a>
			<li><code>cc1101_sens</code> is the decision boundary between the on and off values, and it is 4, 8, 12 or 16 dB.  Smaller values allow reception of less clear signals. Default is 4 dB.</li>
		</ul>
		</li><br>
		<a name="close"></a>
		<li>close<br>
		Closes the connection to the device.
		</li><br>
		<a name="disableMessagetype"></a>
		<li>disableMessagetype<br>
			Allows you to disable the message processing for 
			<ul>
				<li>messages with sync (syncedMS),</li>
				<li>messages without a sync pulse (unsyncedMU)</li> 
				<li>manchester encoded messages (manchesterMC) </li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br>
		<a name="enableMessagetype"></a>
		<li>enableMessagetype<br>
			Allows you to enable the message processing for 
			<ul>
				<li>messages with sync (syncedMS)</li>
				<li>messages without a sync pulse (unsyncedMU)</li>
				<li>manchester encoded messages (manchesterMC)</li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br>
		<a name="flash"></a>
		<li>flash [hexFile|url]<br>
		The SIGNALduino needs the right firmware to be able to receive and deliver the sensor data to fhem. In addition to the way using the arduino IDE to flash the firmware into the SIGNALduino this provides a way to flash it directly from FHEM. You can specify a file on your fhem server or specify a url from which the firmware is downloaded There are some requirements:
		<ul>
			<li>avrdude must be installed on the host<br> On a Raspberry PI this can be done with: sudo apt-get install avrdude</li>
			<li>the hardware attribute must be set if using any other hardware as an Arduino nano<br> This attribute defines the command, that gets sent to avrdude to flash the uC.</li>
			<li>If you encounter a problem, look into the logfile</li>
		</ul>
		Example:
		<ul>
			<li>flash via Version Name: Versions are provided via get availableFirmware</li>
			<li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
			<li>flash via url for Nano with CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
		</ul>
		<i><u>note model radino:</u></i>
		<ul>
			<li>Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under point "radino & Linux" is a patch!</a></li>
			<li>If the Radino is defined in this way <code>/dev/ttyACM0</code>, the flashing of the firmware should be done automatically. If this fails, the boot loader must be activated manually:</li>
			<li>To activate the bootloader of the radino there are 2 variants.
			<ul>
				<li>1) modules that contain a BSL-button:
				<ul>
					<li>apply supply voltage</li>
					<li>press & hold BSL- and RESET-Button</li>
					<li>release RESET-button, release BSL-button</li>
			 		<li>(repeat these steps if your radino doesn't enter bootloader mode right away.)</li>
				</ul>
				</li>
				<li>2) force bootloader:
				<ul>
					<li>pressing reset button twice</li>
				</ul>
				</li>
			</ul>
			In bootloader mode, the radino gets a different USB ID. This must be entered in the "flashCommand" attribute.<br>
			If the bootloader is enabled, it signals with a flashing LED. Then you have 8 seconds to flash.
			</li>
		</ul>
		</li><br>
		<a name="reset"></a>
		<li>reset<br>
		This will do a reset of the usb port and normaly causes to reset the uC connected.
		</li><br>
		<a name="raw"></a>
		<li>raw<br>
		Issue a SIGNALduino firmware command, without waiting data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected

        To send some raw data look at these examples:
		P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional)<br>
		<br>Example 1: set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030  sends the data in raw mode 3 times repeated
        <br>Example 2: set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE  sends the data manchester encoded with a clock of 250uS
        <br>Example 3: set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE  sends a combined message of raw and manchester encoded repeated 3 times
		</p>
		</li>
        <a name="sendMsg"></a>
		<li>sendMsg<br>
		This command will create the needed instructions for sending raw data via the signalduino. Insteaf of specifying the signaldata by your own you specify 
		a protocol and the bits you want to send. The command will generate the needed command, that the signalduino will send this.
		It is also supported to specify the data in hex. prepend 0x in front of the data part.
		<br><br>
		Please note, that this command will work only for MU or MS protocols. You can't transmit manchester data this way.
		<br><br>
		Input args are:
		<p>
		<ul><li>P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional) 
		<br>Example binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
		<br>Will generate the raw send command for the message 0101 with protocol 0 and instruct the arduino to send this three times and the clock is 500.
		<br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;</li></ul><br>
		<ul><li>P<protocol id>#0xhexdata#R<num of repeats>#C<optional clock>    (#C is optional) 
		<br>Example 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
		<br>Generates the raw send command with the hex message F7E with protocl id 29 . The message will be send four times.
		<br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;</li></ul><br>
		<ul><li>P<protocol id>#0xhexdata#R<num of repeats>#C<optional taktrate>#F<optional frequency>    (#C #F is optional) 
		<br>Example 0xhexdata: <code>set sduino sendMsg P36#0xF7#R6#Fxxxxxxxxxx</code> (xxxxxxxxxx = register from CC1101)
		<br>Generates the raw send command with the hex message F7 with protocl id 36 . The message will be send six times.
		<br>SR;R=6;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=012323232324232323;F= (register from CC1101);</ul>
		</p></li></ul>
		</li>

	<a name="SIGNALduinoget"></a>
	<b>Get</b>
	<ul>
        <a name="availableFirmware"></a>
        <li>availableFirmware<br>
		Retrieves available firmware versions from github and displays them in set flash command.
		</li><br>
		<a name="ccconf"></a>
        <li>ccconf<br>
		Read some CUL radio-chip (cc1101) registers (frequency, bandwidth, etc.),
		and display them in human readable form.<br>
		Only with cc1101 receiver.
		</li><br>
        <a name="ccpatable"></a>
		<li>ccpatable<br>
		read cc1101 PA table (power amplification for RF sending)<br>
		Only with cc1101 receiver.
		</li><br>
        <a name="ccreg"></a>
		<li>ccreg<br>
		read cc1101 registers (99 reads all cc1101 registers)<br>
		Only with cc1101 receiver.
		</li><br>
        <a name="cmds"></a>
		<li>cmds<br>
		Depending on the firmware installed, SIGNALduinos have a different set of
		possible commands. Please refer to the sourcecode of the firmware of your
		SIGNALduino to interpret the response of this command. See also the raw-
		command.
		</li><br>
        <a name="config"></a>
		<li>config<br>
		Displays the configuration of the SIGNALduino protocol category. | example: <code>MS=1;MU=1;MC=1;Mred=0</code>
		</li><br>
        <a name="freeram"></a>
		<li>freeram<br>
		Displays the free RAM.
		</li><br>
        <a name="ping"></a>
		<li>ping<br>
		Check the communication with the SIGNALduino.
		</li><br>
        <a name="raw"></a>
		<li>raw<br>
		Issue a SIGNALduino firmware command, and wait for one line of data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected
		</li><br>
        <a name="uptime"></a>
		<li>uptime<br>
		Displays information how long the SIGNALduino is running. A FHEM reboot resets the timer.
		</li><br>
        <a name="version"></a>
		<li>version<br>
		return the SIGNALduino firmware version
		</li><br>		
	</ul>

	
	<a name="SIGNALduinoattr"></a>
	<b>Attributes</b>
	<ul>
		<li><a href="#addvaltrigger">addvaltrigger</a><br>
        	Create triggers for additional device values. Right now these are RSSI, RAWMSG, DMSG and ID.
        	</li><br>
        	<a name="blacklist_IDs"></a>
        	<li>blacklist_IDs<br>
        	The blacklist works only if a whitelist not exist.
        	</li><br>
        	<a name="cc1101_frequency"></a>
		<li>cc1101_frequency<br>
        	Since the PA table values are frequency-dependent, at 868 MHz a value greater 800 required.
        	</li><br>
		<a name="debug"></a>
		<li>debug<br>
		This will bring the module in a very verbose debug output. Usefull to find new signals and verify if the demodulation works correctly.
		</li><br>
		<a name="development"></a>
		<li>development<br>
		The development attribute is only available in development version of this Module for backwart compatibility. Use the whitelistIDs Attribute instead. Setting this attribute to 1 will enable all protocols which are flagged with developID=Y.
		<br>
		To check which protocols are flagged, open via FHEM webinterface in the section "Information menu" the option "Display protocollist". Look at the column "dev" where the flags are noted.
		<br>
		</li>
		<li><a href="#do_not_notify">do_not_notify</a></li><br>
		<li><a href="#attrdummy">dummy</a></li><br>
    		<a name="doubleMsgCheck_IDs"></a>
		<li>doubleMsgCheck_IDs<br>
		This attribute allows it, to specify protocols which must be received two equal messages to call dispatch to the modules.<br>
		You can specify multiple IDs wih a colon : 0,3,7,12<br>
		</li><br>
    		<a name="eventlogging"></a>
		<li>eventlogging<br>
    		With this attribute you can control if every logmessage is also provided as event. This allows to generate event for every log messages.
    		Set this to 0 and logmessages are only saved to the global fhem logfile if the loglevel is higher or equal to the verbose attribute.
    		Set this to 1 and every logmessages is also dispatched as event. This allows you to log the events in a seperate logfile.
    		</li><br>
		<a name="flashCommand"></a>
		<li>flashCommand<br>
    		This is the command, that is executed to performa the firmware flash. Do not edit, if you don't know what you are doing.<br>
		If the attribute not defined, it uses the default settings. <b>If the user defines the attribute manually, the system uses the specifications!</b><br>
    		<ul>
			<li>default for nano, nanoCC1101, miniculCC1101, promini: <code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
			<li>default for radinoCC1101: <code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
		</ul>
		It contains some place-holders that automatically get filled with the according values:<br>
		<ul>
			<li>[BAUDRATE]<br>
			is the speed (e.g. 57600)</li>
			<li>[PORT]<br>
			is the port the Signalduino is connectd to (e.g. /dev/ttyUSB0) and will be used from the defenition</li>
			<li>[HEXFILE]<br>
			is the .hex file that shall get flashed. There are three options (applied in this order):<br>
			- passed in set flash as first argument<br>
			- taken from the hexFile attribute<br>
			- the default value defined in the module<br>
			</li>
			<li>[LOGFILE]<br>
			The logfile that collects information about the flash process. It gets displayed in FHEM after finishing the flash process</li>
		</ul><br>
		<u><i>note:</u></i> ! Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under the point "radino & Linux" is a patch!</a>
    		</li><br>
    		<a name="SIGNALDuino_hardware"></a>
		<li>hardware<br>
			Currently, there are serval hardware options with different receiver options available.
			The simple single wire option,  consists of a single wire connected receiver and a single wire connected transmitter which are connected over a single digital port with the microcontroller. The receiver only sends data and the transmitter receives only from the microcontroller.
			The other option consists of the cc1101 (sub 1 GHZ) chip, which can transmit and receiver. It's a transceiver which is connected via spi.		
			ESP8266 hardware type, currently doesn't support flashing out of the modu and needs at leat 1 MB of flash.
		<ul>
			<li>ESP32: ESP32</li>
			<li>ESP8266: ESP8266 simple single wire receiver</li>
			<li>ESP8266cc1101: ESP8266 with CC1101 (spi connected) receiver</li>
			<li>miniculCC1101: Arduino pro Mini with CC110x (spi connected) receiver and cables as a minicul</li>
			<li>nano: Arduino Nano 328 with simple single wired receiver</li>
			<li>nanoCC1101: Arduino Nano 328 with CC110x (spi connected) receiver</li>
			<li>promini: Arduino Pro Mini 328 with simple single receiver </li>
			<li>radinoCC1101: Arduino compatible radino with cc1101 (spi connected) receiver</li>
		</ul>
	</li><br>
	<li>maxMuMsgRepeat<br>
	MU signals can contain multiple repeats of the same message. The results are all send to a logical module. You can limit the number of scanned repetitions. Defaukt is 4, so after found 4 repeats, the demoduation is aborted. 	
	<br></li>
    <a name="minsecs"></a>
	<li>minsecs<br>
    This is a very special attribute. It is provided to other modules. minsecs should act like a threshold. All logic must be done in the logical module. 
    If specified, then supported modules will discard new messages if minsecs isn't past.
    </li><br>
    <a name="noMsgVerbose"></a>
    <li>noMsgVerbose<br>
    With this attribute you can control the logging of debug messages from the io device.
    If set to 3, this messages are logged if global verbose is set to 3 or higher.
    </li><br>
    <a name="longids"></a>
	<li>longids<br>
        Comma separated list of device-types for SIGNALduino that should be handled using long IDs. This additional ID allows it to differentiate some weather sensors, if they are sending on the same channel. Therfor a random generated id is added. If you choose to use longids, then you'll have to define a different device after battery change.<br>
		Default is to not to use long IDs for all devices.
      <br><br>
      Examples:<PRE>
# Do not use any long IDs for any devices:
attr sduino longids 0
# Use any long IDs for all devices (this is default):
attr sduino longids 1
# Use longids for BTHR918N devices.
# Will generate devices names like BTHR918N_f3.
attr sduino longids BTHR918N
</PRE></li>
<a name="rawmsgEvent"></a>
<li>rawmsgEvent<br>
When set to "1" received raw messages triggers events
</li><br>
<a name="suppressDeviceRawmsg"></a>
<li>suppressDeviceRawmsg<br>
When set to 1, the internal "RAWMSG" will not be updated with the received messages
</li><br>
	<a name="updateChannelFW"></a>
	<li>updateChannelFW<br>
		The module can search for new firmware versions (<a href="https://github.com/RFD-FHEM/SIGNALDuino/releases">SIGNALDuino</a> and <a href="https://github.com/RFD-FHEM/SIGNALESP/releases">SIGNALESP</a>). Depending on your choice, only stable versions are displayed or also prereleases are available for flash. The option testing does also provide the stable ones.
		<ul>
			<li>stable: only versions marked as stable are available. These releases are provided very infrequently</li>
			<li>testing: These versions needs some verifications and are provided in shorter intervals</li>
		</ul>
		<br>Reload the available Firmware via get availableFirmware manually.
		</li><br>
		<a name="whitelist_IDs"></a>
		<li>whitelist_IDs<br>
		This attribute allows it, to specify whichs protocos are considured from this module. Protocols which are not considured, will not generate logmessages or events. They are then completly ignored. This makes it possible to lower ressource usage and give some better clearnes in the logs. You can specify multiple whitelistIDs wih a colon : 0,3,7,12<br> With a # at the beginnging whitelistIDs can be deactivated.
		<br>
		Not using this attribute or deactivate it, will process all stable protocol entrys. Protocols which are under development, must be activated explicit via this Attribute.
		</li><br>
   		<a name="WS09_CRCAUS"></a>
   		<li>WS09_CRCAUS<br>
       		<ul>
				<li>0: CRC-Check WH1080 CRC = 0  on, default</li>
       			<li>2: CRC = 49 (x031) WH1080, set OK</li>
			</ul>
    	</li>
   	</ul>
   	<a name="SIGNALduinoDetail"></a>
	<b>Information menu</b>
	<ul>
   	    <a name="Display protocollist"></a>
		<li>Display protocollist<br> 
		Shows the current implemented protocols from the SIGNALduino and to what logical FHEM Modul data is sent.<br>
		Additional there is an checkbox symbol, which shows you if a protocol will be processed. This changes the Attribute whitlistIDs for you in the background. The attributes whitelistIDs and blacklistIDs affects this state.
		Protocols which are flagged in the row <code>dev</code>, are under development
		<ul>
			<li>If a row is flagged via 'm', then the logical module which provides you with an interface is still under development. Per default, these protocols will not send data to logcial module. To allow communication to a logical module you have to enable the protocol.</li> 
			<li>If a row is flagged via 'p', then this protocol entry is reserved or in early development state.</li>
			<li>If a row is flalged via 'y' then this protocol isn't fully tested or reviewed.</li>
		</ul>
		<br>
		If you are using blacklistIDs, then you also can not activate them via the button, delete the attribute blacklistIDs if you want to control enabled protocols via this menu.
		</li><br>
   	</ul>
							  		   
=end html
=begin html_DE

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

	<table>
	<tr><td>
	Der <a href="https://wiki.fhem.de/wiki/SIGNALduino">SIGNALduino</a> ist basierend auf einer Idee von "mdorenka" und ver&ouml;ffentlicht im <a href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.<br>

	Mit der OpenSource-Firmware (<a href="https://github.com/RFD-FHEM/SIGNALDuino/releases">SIGNALDuino</a> und <a href="https://github.com/RFD-FHEM/SIGNALESP/releases">SIGNALESP</a>) ist dieser f&auml;hig zum Empfangen und Senden verschiedener Protokolle auf 433 und 868 Mhz.
	<br><br>
	Folgende Ger&auml;te werden zur Zeit unterst&uuml;tzt:
	<br><br>
	Funk-Schalter<br>
	<ul>
		<li>ITv1 & ITv3/Elro und andere Marken mit dem pt2263-Chip oder welche das arctech Protokoll nutzen --> IT.pm<br> Das ITv1 Protokoll benutzt einen Standard ITclock von 250 und es kann vorkommen, das in dem IT-Modul das Attribut "ITclock" zu setzen ist.</li>
    		<li>ELV FS10 -> 10_FS10</li>
    		<li>ELV FS20 -> 10_FS20</li>
	</ul>
	Temperatur-, Luftfeuchtigkeits-, Luftdruck-, Helligkeits-, Regen- und Windsensoren:
	<ul>
		<li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 und viele anderen -> 14_CUL_TCM97001.pm</li>
		<li>Oregon Scientific v2 und v3 Sensoren  -> 41_OREGON.pm</li>
		<li>Temperatur / Feuchtigkeits Sensoren unterst&uuml;tzt -> 14_SD_WS07.pm</li>
    		<li>technoline WS 6750 und TX70DTH -> 14_SD_WS07.pm</li>
    		<li>Eurochon EAS 800z -> 14_SD_WS07.pm</li>
    		<li>CTW600, WH1080	-> 14_SD_WS09.pm</li>
    		<li>Hama TS33C, Bresser Thermo/Hygro Sensoren -> 14_Hideki.pm</li>
    		<li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07.pm</li>
    		<li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    		<li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
	</ul>
	<br>
	Es ist m&ouml;glich, mehr als ein Ger&auml;t anzuschließen, um beispielsweise besseren Empfang zu erhalten. FHEM wird doppelte Nachrichten herausfiltern.
	Mehr dazu im dem <a href="#global">global</a> Abschnitt unter dem Attribut dupTimeout<br><br>
	Hinweis: Dieses Modul erfordert das Device::SerialPort oder Win32::SerialPort
	Modul. Es kann derzeit nur &uuml;ber USB angeschlossen werden.
	</td>
	</tr>
	</table>
	<br>
	<a name="SIGNALduinodefine"></a>
	<b>Define</b>
	<code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code>
	USB-connected devices (SIGNALduino):<br>
	<ul><li>
		&lt;device&gt; spezifiziert den seriellen Port f&uuml;r die Kommunikation mit dem SIGNALduino.
		Der Name des seriellen Ger&auml;ts h&auml;ngt von Ihrer  Distribution ab. In Linux ist das <code>cdc_acm</code> Kernel_Modul daf&uuml;r verantwortlich und es wird ein <code>/dev/ttyACM0</code> oder <code>/dev/ttyUSB0</code> Ger&auml;t angelegt. Wenn deine Distribution kein <code>cdc_acm</code> Module besitzt, kannst du usbserial nutzen um den SIGNALduino zu betreiben mit folgenden Kommandos:
		<ul>
			<li>modprobe usbserial</li>
			<li>vendor=0x03eb</li>
			<li>product=0x204b</li>
		</ul>
		In diesem Fall ist das Ger&auml;t h&ouml;chstwahrscheinlich <code>/dev/ttyUSB0</code>.<br><br>

		Sie k&ouml;nnen auch eine Baudrate angeben, wenn der Ger&auml;tename das @ enth&auml;lt, Beispiel: <code>/dev/ttyACM0@57600</code><br>Dies ist auch die Standard-Baudrate.<br><br>
		Es wird empfohlen, das Ger&auml;t &uuml;ber einen Namen anzugeben, der sich nicht &auml;ndert. Beispiel via by-id devicename: <code>/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600</code><br>
		Wenn die Baudrate "directio" (Bsp: <code>/dev/ttyACM0@directio</code>), dann benutzt das Perl Modul nicht Device::SerialPort und FHEM &ouml;ffnet das Ger&auml;t mit einem file io. Dies kann funktionieren, wenn das Betriebssystem die Standardwerte f&uuml;r die seriellen Parameter verwendet. Bsp: einige Linux Distributionen und
		OSX.<br><br>
		</li>
	</ul>
	
	<a name="SIGNALduinointernals"></a>
	<b>Internals</b>
	<ul>
		<li><b>IDsNoDispatch</b>: Hier werden protokoll Eintr&auml;ge mit ihrer numerischen ID aufgelistet, f&uuml;r welche keine Weitergabe von Daten an logische Module aktiviert wurde. Um die Weitergabe zu aktivieren, kann die Men&uuml;option <a href="#SIGNALduinoDetail">Display protocollist</a> verwendet werden.</li>
		<li><b>LASTDMSGID</b>: Hier wird die zuletzt dispatchte Protocol ID angezeigt.</li>
		<li><b>NR_CMD_LAST_H</b>: Anzahl der gesendeten Nachrichten innerhalb der letzten Stunde.</li>
		<li><b>RAWMSG</b>: zuletzt empfangene RAWMSG</li>
		<li><b>version</b>: Hier wird die Version des SIGNALduino microcontrollers angezeigt.</li>
		<li><b>versionProtocols</b>: Hier wird die Version der SIGNALduino Protokolldatei angezeigt.</li>
		<li><b>versionmodule</b>: Hier wird die Version des SIGNALduino FHEM Modules selbst angezeigt.</li>
	</ul>


	<a name="SIGNALduinoset"></a>
	<b>SET</b>
	<ul>
		<li>cc1101_freq / cc1101_bWidth / cc1101_patable / cc1101_rAmpl / cc1101_sens<br>
		(NUR bei Verwendung eines cc110x Funk-Moduls)<br><br>
		Stellt die SIGNALduino-Frequenz / Bandbreite / PA-Tabelle / Empf&auml;nger-Amplitude / Empfindlichkeit ein.<br>
		Verwenden Sie es mit Vorsicht. Es kann Ihre Hardware zerst&ouml;ren und es kann sogar illegal sein, dies zu tun.<br>
		Hinweis: Die f&uuml;r die RFR-&Uuml;bertragung verwendeten Parameter sind nicht betroffen.<br></li>
		<ul>
		<a name="cc1101_freq"></a>
		<li><code>cc1101_freq</code> , legt sowohl die Empfangsfrequenz als auch die &Uuml;bertragungsfrequenz fest.<br>
		Hinweis: Obwohl der CC1101 auf Frequenzen zwischen 315 und 915 MHz eingestellt werden kann, ist die Antennenschnittstelle und die Antenne auf genau eine Frequenz abgestimmt. Standard ist 433.920 MHz (oder 868.350 MHz). Wenn keine Frequenz angegeben wird, dann wird die Frequenz aus dem Attribut <code>cc1101_frequency</code> geholt.</li>
		<a name="cc1101_bWidth"></a>
		<li><code>cc1101_bWidth</code> , kann auf Werte zwischen 58 kHz und 812 kHz eingestellt werden. Große Werte sind st&ouml;ranf&auml;llig, erm&ouml;glichen jedoch den Empfang von ungenau kalibrierten Sendern. Es wirkt sich auch auf die &Uuml;bertragung aus. Standard ist 325 kHz.</li>
		<a name="cc1101_patable"></a>
		<li><code>cc1101_patable</code> , &Auml;nderung der PA-Tabelle (Leistungsverst&auml;rkung f&uuml;r HF-Senden)</li>
		<a name="cc1101_rAmpl"></a>
		<li><code>cc1101_rAmpl</code> , ist die Empf&auml;ngerverst&auml;rkung mit Werten zwischen 24 und 42 dB. Gr&ouml;ßere Werte erlauben den Empfang schwacher Signale. Der Standardwert ist 42.</li>
		<a name="cc1101_sens"></a>
		<li><code>cc1101_sens</code> , ist die Entscheidungsgrenze zwischen den Ein- und Aus-Werten und betr&auml;gt 4, 8, 12 oder 16 dB. Kleinere Werte erlauben den Empfang von weniger klaren Signalen. Standard ist 4 dB.</li>
		</ul>
		<br>
		<a name="close"></a>
		<li>close<br>
		Beendet die Verbindung zum Ger&auml;t.</li><br>
		<a name="enableMessagetype"></a>
		<li>enableMessagetype<br>
			Erm&ouml;glicht die Aktivierung der Nachrichtenverarbeitung f&uuml;r
			<ul>
				<li>Nachrichten mit sync (syncedMS),</li>
				<li>Nachrichten ohne einen sync pulse (unsyncedMU)</li>
				<li>Manchester codierte Nachrichten (manchesterMC)</li>
			</ul>
			Der neue Status wird in den eeprom vom Arduino geschrieben.
		</li><br>
		<a name="disableMessagetype"></a>
		<li>disableMessagetype<br>
		Erm&ouml;glicht das Deaktivieren der Nachrichtenverarbeitung f&uuml;r
		<ul>
			<li>Nachrichten mit sync (syncedMS)</li>
			<li>Nachrichten ohne einen sync pulse (unsyncedMU)</li> 
			<li>Manchester codierte Nachrichten (manchesterMC)</li>
		</ul>
		Der neue Status wird in den eeprom vom Arduino geschrieben.
		</li><br>
		<a name="flash"></a>
		<li>flash [hexFile|url]<br>
		Der SIGNALduino ben&ouml;tigt die richtige Firmware, um die Sensordaten zu empfangen und zu liefern. Unter Verwendung der Arduino IDE zum Flashen der Firmware in den SIGNALduino bietet dies eine M&ouml;glichkeit, ihn direkt von FHEM aus zu flashen. Sie k&ouml;nnen eine Datei auf Ihrem fhem-Server angeben oder eine URL angeben, von der die Firmware heruntergeladen wird. Es gibt einige Anforderungen:
		<ul>
			<li><code>avrdude</code> muss auf dem Host installiert sein. Auf einem Raspberry PI kann dies getan werden mit: <code>sudo apt-get install avrdude</code></li>
			<li>Das Hardware-Attribut muss festgelegt werden, wenn eine andere Hardware als Arduino Nano verwendet wird. Dieses Attribut definiert den Befehl, der an avrdude gesendet wird, um den uC zu flashen.</li>
			<li>Bei Problem mit dem Flashen, k&ouml;nnen im Logfile interessante Informationen zu finden sein.</li>
		</ul>
		Beispiele:
		<ul>
			<li>flash mittels Versionsnummer: Versionen k&ouml;nnen mit get availableFirmware abgerufen werden</li>		
			<li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
			<li>flash via url f&uuml;r einen Nano mit CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
		</ul>
		<i><u>Hinweise Modell radino:</u></i>
		<ul>
			<li>Teilweise kann es beim flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a></li>
			<li>Wenn der Radino in dieser Art <code>/dev/ttyACM0</code> definiert wurde, sollte das Flashen der Firmware automatisch erfolgen. Wenn das nicht gelingt, muss der Bootloader manuell aktiviert werden:</li>
			<li>Um den Bootloader vom radino manuell zu aktivieren gibt es 2 Varianten.
			<ul>
				<li>1) Module welche einen BSL-Button besitzen:
				<ul>
					<li>Spannung anlegen</li>
					<li>druecke & halte BSL- und RESET-Button</li>
					<li>RESET-Button loslassen und danach den BSL-Button loslassen</li>
					<li>(Wiederholen Sie diese Schritte, wenn Ihr radino nicht sofort in den Bootloader-Modus wechselt.)</li>
				</ul>
				</li>
				<li>2) Bootloader erzwingen:
				<ul>
					<li>durch zweimaliges druecken der Reset-Taste</li>
				</ul>
				</li>
			</ul>
			Im Bootloader-Modus erh&auml;lt der radino eine andere USB ID. Diese muss im Attribut "flashCommand" eingetragen werden.<br>
			Wenn der Bootloader aktiviert ist, signalisiert er das mit dem Blinken einer LED. Dann hat man ca. 8 Sekunden Zeit zum flashen.
			</li>
		</ul>
		</li><br>
	<a name="raw"></a>
	<li>raw<br>
	Geben Sie einen SIGNALduino-Firmware-Befehl aus, ohne auf die vom SIGNALduino zur&uuml;ckgegebenen Daten zu warten. Ausf&uuml;hrliche Informationen zu SIGNALduino-Befehlen finden Sie im SIGNALduino-Firmware-Code. Mit dieser Linie k&ouml;nnen Sie fast jedes Signal &uuml;ber einen angeschlossenen Sender senden.<br>
	Um einige Rohdaten zu senden, schauen Sie sich diese Beispiele an: P#binarydata#R#C (#C is optional)
			<ul>
				<li>Beispiel 1: <code>set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030</code> , sendet die Daten im Raw-Modus dreimal wiederholt</li>
				<li>Beispiel 2: <code>set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE</code> , sendet die Daten Manchester codiert mit einem clock von 250&micro;S</li>
				<li>Beispiel 3: <code>set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE</code> , sendet eine kombinierte Nachricht von Raw und Manchester codiert 3 mal wiederholt</li>
			</ul><br>
		<ul>
         <u>NUR f&uuml;r DEBUG Nutzung | <small>Befehle sind abhaenging vom Firmwarestand!</small></u><br>
         <small>(Hinweis: Die falsche Benutzung kann zu Fehlfunktionen des SIGNALduino´s f&uuml;hren!)</small>
            <li>CED -> Debugausgaben ein</li>
            <li>CDD -> Debugausgaben aus</li>
            <li>CDL -> LED aus</li>
            <li>CEL -> LED ein</li>
            <li>CER -> Einschalten der Datenkomprimierung (config: Mred=1)</li>
            <li>CDR -> Abschalten der Datenkomprimierung (config: Mred=0)</li>
            <li>CSmscnt=[Wert] -> Wiederholungszaehler fuer den split von MS Nachrichten</li>
            <li>CSmuthresh=[Wert] -> Schwellwert fuer den split von MU Nachrichten (0=aus)</li>
            <li>CSmcmbl=[Wert] -> minbitlen fuer MC-Nachrichten</li>
            <li>CSfifolimit=[Wert] -> Schwellwert fuer debug Ausgabe der Pulsanzahl im FIFO Puffer</li>
         </ul><br></li>
	<a name="reset"></a>
	<li>reset<br>
	&Ouml;ffnet die Verbindung zum Ger&auml;t neu und initialisiert es.</li><br>
	<a name="sendMsg"></a>
	<li>sendMsg<br>
	Dieser Befehl erstellt die erforderlichen Anweisungen zum Senden von Rohdaten &uuml;ber den SIGNALduino. Sie k&ouml;nnen die Signaldaten wie Protokoll und die Bits angeben, die Sie senden m&ouml;chten.<br>
	Alternativ ist es auch moeglich, die zu sendenden Daten in hexadezimaler Form zu uebergeben. Dazu muss ein 0x vor den Datenteil geschrieben werden.
	<br><br>
	Bitte beachte, dieses Kommando funktioniert nur fuer MU oder MS Protokolle nach dieser Vorgehensweise:
		<br><br>
		Argumente sind:
		<p>
		<ul>
			<li>P<protocol id>#binarydata#R<anzahl der wiederholungen>#C<optional taktrate>   (#C is optional) 
			<br>Beispiel binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
			<br>Wird eine sende Kommando fuer die Bitfolge 0101 anhand der protocol id 0 erzeugen. Als Takt wird 500 verwendet.
			<br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;<br></li></ul><br>
			<ul><li>P<protocol id>#0xhexdata#R<anzahl der wiederholungen>#C<optional taktrate>    (#C is optional) 
			<br>Beispiel 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
			<br>Wird eine sende Kommando fuer die Hexfolge F7E anhand der protocol id 29 erzeugen. Die Nachricht soll 4x gesendet werden.
			<br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;</li></ul><br>
			<ul><li>P<protocol id>#0xhexdata#R<anzahl der wiederholungen>#C<optional taktrate>#F<optional Frequenz>    (#C #F is optional) 
			<br>Beispiel 0xhexdata: <code>set sduino sendMsg P36#0xF7#R6#Fxxxxxxxxxx</code> (xxxxxxxxxx = Registerwert des CC1101)
			<br>Wird eine sende Kommando fuer die Hexfolge F7 anhand der protocol id 36 erzeugen. Die Nachricht soll 6x gesendet werden mit der angegebenen Frequenz.
			<br>SR;R=6;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=012323232324232323;F= (Registerwert des CC1101);</ul>
			</p></li>
		</ul>
	</li>
	<br>

	<a name="SIGNALduinoget"></a>
	<b>Get</b>
	<ul>
    	<a name="availableFirmware"></a>
    	<li>availableFirmware<br>
	Ruft die verf&uuml;gbaren Firmware-Versionen von Github ab und macht diese im <code>set flash</code> Befehl ausw&auml;hlbar.
	</li><br>
	<a name="ccconf"></a>
	<li>ccconf<br>
   	Liest s&auml;mtliche radio-chip (cc1101) Register (Frequenz, Bandbreite, etc.) aus und zeigt die aktuelle Konfiguration an.<br>
	(NUR bei Verwendung eines cc1101 Empf&auml;nger)
   	</li><br>
	<a name="ccpatable"></a>
	<li>ccpatable<br>
   	Liest die cc1101 PA Tabelle aus (power amplification for RF sending).<br>
	(NUR bei Verwendung eines cc1101 Empf&auml;nger)
   	</li><br>
	<a name="ccreg"></a>
	<li>ccreg<br>
   	Liest das cc1101 Register aus (99 liest alle aus).<br>
	(NUR bei Verwendung eines cc1101 Empf&auml;nger)
	</li><br>
	<a name="close"></a>
	<li>close<br>
	Beendet die Verbindung zum SIGNALduino.
	</li><br>
	<a name="cmds"></a>
	<li>cmds<br>
	Abh&auml;ngig von der installierten Firmware besitzt der SIGNALduino verschiedene Befehle. Bitte beachten Sie den Quellcode der Firmware Ihres SIGNALduino, um die Antwort dieses Befehls zu interpretieren.
	</li><br>
	<a name="config"></a>
	<li>config<br>
	Zeigt Ihnen die aktuelle Konfiguration der SIGNALduino Protokollkathegorie an. | Bsp: <code>MS=1;MU=1;MC=1;Mred=0</code>
	</li><br>
	<a name="freeram"></a>
	<li>freeram<br>
   	Zeigt den freien RAM an.
	</li><br>
	<a name="ping"></a>
   	<li>ping<br>
	Pr&uuml;ft die Kommunikation mit dem SIGNALduino.
	</li><br>
	<a name="raw"></a>
	<li>raw<br>
	Abh&auml;ngig von der installierten Firmware! Somit k&ouml;nnen Sie einen SIGNALduino-Firmware-Befehl direkt ausf&uuml;hren.
	</li><br>
	<a name="uptime"></a>
	<li>uptime<br>
	Zeigt Ihnen die Information an, wie lange der SIGNALduino l&auml;uft. Ein FHEM Neustart setzt den Timer zur&uuml;ck.
	</li><br>
	<a name="version"></a>
	<li>version<br>
	Zeigt Ihnen die Information an, welche aktuell genutzte Software Sie mit dem SIGNALduino verwenden.
	</li><br>
	</ul>
	
	
	<a name="SIGNALduinoattr"></a>
	<b>Attributes</b>
	<ul>
	<a name="addvaltrigger"></a>
	<li>addvaltrigger<br>
	Generiert Trigger f&uuml;r zus&auml;tzliche Werte. Momentan werden DMSG, ID, RAWMSG und RSSI unterst&uuml;zt.
	</li><br>
	<a name="blacklist_IDs"></a>
	<li>blacklist_IDs<br>
	Dies ist eine durch Komma getrennte Liste. Die Blacklist funktioniert nur, wenn keine Whitelist existiert! Hier kann man ID´s eintragen welche man nicht ausgewertet haben m&ouml;chte.
	</li><br>
	<a name="cc1101_frequency"></a>
	<li>cc1101_frequency<br>
	Frequenzeinstellung des cc1101. | Bsp: 433.920 / 868.350
	</li><br>
	<a name="debug"></a>
	<li>debug<br>
	Dies bringt das Modul in eine sehr ausf&uuml;hrliche Debug-Ausgabe im Logfile. Somit lassen sich neue Signale finden und Signale &uuml;berpr&uuml;fen, ob die Demodulation korrekt funktioniert.
	</li><br>
	<a name="development"></a>
		<li>development<br>
		Das development Attribut ist nur in den Entwicklungsversionen des FHEM Modules aus Gr&uuml;den der Abw&auml;rtskompatibilit&auml;t vorhanden. Bei Setzen des Attributes auf "1" werden alle Protokolle aktiviert, welche mittels developID=y markiert sind. 
		<br>
		Wird das Attribut auf 1 gesetzt, so werden alle in Protokolle die mit dem developID Flag "y" markiert sind aktiviert. Die Flags (Spalte dev) k&ouml;nnen &uuml;ber das Webfrontend im Abschnitt "Information menu" mittels "Display protocollist" eingesehen werden.
		</li>
		<br>
	<li><a href="#do_not_notify">do_not_notify</a></li><br>
	<a name="doubleMsgCheck_IDs"></a>
	<li>doubleMsgCheck_IDs<br>
	Dieses Attribut erlaubt es, Protokolle anzugeben, die zwei gleiche Nachrichten enthalten m&uuml;ssen, um diese an die Module zu &uuml;bergeben. Sie k&ouml;nnen mehrere IDs mit einem Komma angeben: 0,3,7,12
	</li><br>
	<li><a href="#dummy">dummy</a></li><br>
	<a name="flashCommand"></a>
	<li>flashCommand<br>
	Dies ist der Befehl, der ausgef&uuml;hrt wird, um den Firmware-Flash auszuf&uuml;hren. Nutzen Sie dies nicht, wenn Sie nicht wissen, was Sie tun!<br>
	Wurde das Attribut nicht definiert, so verwendet es die Standardeinstellungen.<br><b>Sobald der User das Attribut manuell definiert, nutzt das System diese Vorgaben!</b><br>
	<ul>
	<li>Standard nano, nanoCC1101, miniculCC1101, promini:<br><code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
	<li>Standard radinoCC1101:<br><code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
	</ul>
	Es enth&auml;lt einige Platzhalter, die automatisch mit den entsprechenden Werten gef&uuml;llt werden:
		<ul>
			<li>[BAUDRATE]<br>
			Ist die Schrittgeschwindigkeit. (z.Bsp: 57600)</li>
			<li>[PORT]<br>
			Ist der Port, an dem der SIGNALduino angeschlossen ist (z.Bsp: /dev/ttyUSB0) und wird von der Definition verwendet.</li>
			<li>[HEXFILE]<br>
			Ist die .hex-Datei, die geflasht werden soll. Es gibt drei Optionen (angewendet in dieser Reihenfolge):<br>
			<ul>
				<li>in <code>set SIGNALduino flash</code> als erstes Argument &uuml;bergeben</li>
				<li>aus dem Hardware-Attribut genommen</li>
				<li>der im Modul definierte Standardwert</li>
			</ul>
			</li>
			<li>[LOGFILE]<br>
			Die Logdatei, die Informationen &uuml;ber den Flash-Prozess sammelt. Es wird nach Abschluss des Flash-Prozesses in FHEM angezeigt</li>
		</ul><br>
	<u><i>Hinweis:</u></i> ! Teilweise kann es beim Flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a>
	</li><br>
	<a name="SIGNALDuino_hardware"></a>
	<li>hardware<br>
		Derzeit m&ouml;gliche Hardware Varianten mit verschiedenen Empfänger Optionen.
		Die einfache Variante besteht aus einem Empf&auml;nger und einen Sender, die über je eine einzige digitale Signalleitung Datem mit dem Microcontroller austauschen. Der Empf&auml;nger sendet dabei und der Sender empf&auml;ngt dabei ausschließlich.
		Weiterhin existiert der den sogenannten cc1101 (sub 1 GHZ) Chip, welche empfangen und senden kann. Dieser wird über die SPI Verbindung angebunden.
		ESP8266 Hardware Typen, unterstützen derzeit kein flashen aus dem Modul und ben&ouml;tigen mindestens 1 MB Flash Speicher.		
		<ul>
			<li>ESP32: ESP32</li>
			<li>ESP8266: ESP8266 f&uuml;r einfachen eindraht Empf&auml;nger</li>
			<li>ESP8266cc1101: ESP8266 mit einem CC110x-Empf&auml;nger (SPI Verbindung)</li>
			<li>miniculCC1101: Arduino pro Mini mit einem CC110x-Empf&auml;nger (SPI Verbindung) entsprechend dem minicul verkabelt</li>
			<li>nano: Arduino Nano 328 f&uuml;r einfachen eindraht Empf&auml;nger</li>
			<li>nanoCC1101: Arduino Nano f&uuml;r einen CC110x-Empf&auml;nger (SPI Verbindung)</li>
			<li>promini: Arduino Pro Mini 328 f&uuml;r einfachen eindraht Empf&auml;nger</li>
			<li>radinoCC1101: Ein Arduino Kompatibler Radino mit cc1101 Empfänger (SPI Verbindung)</li>
		</ul><br>
		Notwendig f&uuml;r den Befehl <code>flash</code>. Hier sollten Sie angeben, welche Hardware Sie mit dem usbport verbunden haben. Andernfalls kann es zu Fehlfunktionen des Ger&auml;ts kommen. Wichtig ist auch das Attribut <code>updateChannelFW</code><br>
	</li><br>
	<a name="longids"></a>
	<li>longids<br>
	Durch Komma getrennte Liste von Device-Typen f&uuml;r Empfang von langen IDs mit dem SIGNALduino. Diese zus&auml;tzliche ID erlaubt es Wettersensoren, welche auf dem gleichen Kanal senden zu unterscheiden. Hierzu wird eine zuf&auml;llig generierte ID hinzugef&uuml;gt. Wenn Sie longids verwenden, dann wird in den meisten F&auml;llen nach einem Batteriewechsel ein neuer Sensor angelegt. Standardm&auml;ßig werden keine langen IDs verwendet.<br>
	Folgende Module verwenden diese Funktionalit&auml;t: 14_Hideki, 41_OREGON, 14_CUL_TCM97001, 14_SD_WS07.<br>
	Beispiele:<PRE>
    		# Keine langen IDs verwenden (Default Einstellung):
    		attr sduino longids 0
    		# Immer lange IDs verwenden:
    		attr sduino longids 1
    		# Verwende lange IDs f&uuml;r SD_WS07 Devices.
    		# Device Namen sehen z.B. so aus: SD_WS07_TH_3.
    		attr sduino longids SD_WS07
	</PRE></li><br>
	<a name="maxMuMsgRepeat"></a>
	<li>maxMuMsgRepeat<br>
	In MU Signalen k&ouml;nnen mehrere Wiederholungen stecken. Diese werden einzeln ausgewertet und an ein logisches Modul uebergeben. Mit diesem Attribut kann angepasst werden, wie viele Wiederholungen gesucht werden. Standard ist 4.
	</li><br>
	<a name="minsecs"></a>
	<li>minsecs<br>
	Es wird von anderen Modulen bereitgestellt. Minsecs sollte wie eine Schwelle wirken. Wenn angegeben, werden unterst&uuml;tzte Module neue Nachrichten verworfen, wenn minsecs nicht vergangen sind.
	</li><br>
	<a name="noMsgVerbose"></a>
	<li>noMsgVerbose<br>
	Mit diesem Attribut k&ouml;nnen Sie die Protokollierung von Debug-Nachrichten vom io-Ger&auml;t steuern. Wenn dieser Wert auf 3 festgelegt ist, werden diese Nachrichten protokolliert, wenn der globale Verbose auf 3 oder h&ouml;her eingestellt ist.
	</li><br>
	<a name="eventlogging"></a>
	<li>eventlogging<br>
    	Mit diesem Attribut k&ouml;nnen Sie steuern, ob jede Logmeldung auch als Ereignis bereitgestellt wird. Dies erm&ouml;glicht das Erzeugen eines Ereignisses fuer jede Protokollnachricht.
    	Setze dies auf 0 und Logmeldungen werden nur in der globalen Fhem-Logdatei gespeichert, wenn der Loglevel h&ouml;her oder gleich dem Verbose-Attribut ist.
    	Setze dies auf 1 und jede Logmeldung wird auch als Ereignis versendet. Dadurch k&ouml;nnen Sie die Ereignisse in einer separaten Protokolldatei protokollieren.
    	</li><br>
	<a name="rawmsgEvent"></a>
	<li>rawmsgEvent<br>
	Bei der Einstellung "1", l&ouml;sen empfangene Rohnachrichten Ereignisse aus.
	</li><br>
	<a name="suppressDeviceRawmsg"></a>
	<li>suppressDeviceRawmsg<br>
	Bei der Einstellung "1" wird das interne "RAWMSG" nicht mit den empfangenen Nachrichten aktualisiert.
	</li><br>
	<a name="updateChannelFW"></a>
	<li>updateChannelFW<br>
		Das Modul sucht nach Verf&uuml;gbaren Firmware Versionen (<a href="https://github.com/RFD-FHEM/SIGNALDuino/releases">GitHub</a>) und bietet diese via dem Befehl <code>flash</code> zum Flashen an. Mit dem Attribut kann festgelegt werden, ob nur stabile Versionen ("Latest Release") angezeigt werden oder auch Vorabversionen ("Pre-release") einer neuen Firmware.<br>
		Die Option testing inkludiert auch die stabilen Versionen.
		<ul>
			<li>stable: Als stabil getestete Versionen, erscheint nur sehr selten</li>
			<li>testing: Neue Versionen, welche noch getestet werden muss</li>
		</ul>
		<br>Die Liste der verf&uuml;gbaren Versionen muss manuell mittels <code>get availableFirmware</code> neu geladen werden.
		
	</li><br>
	Notwendig f&uuml;r den Befehl <code>flash</code>. Hier sollten Sie angeben, welche Hardware Sie mit dem USB-Port verbunden haben. Andernfalls kann es zu Fehlfunktionen des Ger&auml;ts kommen. <br><br>
	<a name="whitelist_IDs"></a>
	<li>whitelist_IDs<br>
	Dieses Attribut erlaubt es, festzulegen, welche Protokolle von diesem Modul aus verwendet werden. Protokolle, die nicht beachtet werden, erzeugen keine Logmeldungen oder Ereignisse. Sie werden dann vollst&auml;ndig ignoriert. Dies erm&ouml;glicht es, die Ressourcennutzung zu reduzieren und bessere Klarheit in den Protokollen zu erzielen. Sie k&ouml;nnen mehrere WhitelistIDs mit einem Komma angeben: 0,3,7,12. Mit einer # am Anfang k&ouml;nnen WhitelistIDs deaktiviert werden. 
	<br>
	Wird dieses Attribut nicht verwrndet oder deaktiviert, werden alle stabilen Protokolleintr&auml;ge verarbeitet. Protokolleintr&auml;ge, welche sich noch in Entwicklung befinden m&uuml;ssen explizit &uuml;ber dieses Attribut aktiviert werden.
	</li><br>
	<a name="WS09_CRCAUS"></a>
	<li>WS09_CRCAUS<br>
		<ul>
			<li>0: CRC-Check WH1080 CRC = 0 on, Standard</li>
			<li>2: CRC = 49 (x031) WH1080, set OK</li>
		</ul>
	</li><br>
  </ul>


   	<a name="SIGNALduinoDetail"></a>
	<b>Information menu</b>
	<ul>
   	    <a name="Display protocollist"></a>
		<li>Display protocollist<br> 
		Zeigt Ihnen die aktuell implementierten Protokolle des SIGNALduino an und an welches logische FHEM Modul Sie &uuml;bergeben werden.<br>
		Außerdem wird mit checkbox Symbolen angezeigt ob ein Protokoll verarbeitet wird. Durch Klick auf das Symbol, wird im Hintergrund das Attribut whitlelistIDs angepasst. Die Attribute whitelistIDs und blacklistIDs beeinflussen den dargestellten Status.
		Protokolle die in der Spalte <code>dev</code> markiert sind, befinden sich in Entwicklung. 
		<ul>
			<li>Wemm eine Zeile mit 'm' markiert ist, befindet sich das logische Modul, welches eine Schnittstelle bereitstellt in Entwicklung. Im Standard &uuml;bergeben diese Protokolle keine Daten an logische Module. Um die Kommunikation zu erm&ouml;glichenm muss der Protokolleintrag aktiviert werden.</li> 
			<li>Wemm eine Zeile mit 'p' markiert ist, wurde der Protokolleintrag reserviert oder befindet sich in einem fr&uuml;hen Entwicklungsstadium.</li>
			<li>Wemm eine Zeile mit 'y' markiert ist, wurde das Protkokoll noch nicht ausgiebig getestet und &uuml;berpr&uuml;ft.</li>
		</ul>
		<br>
		Protokolle, welche in dem blacklistIDs Attribut eingetragen sind, k&ouml;nnen nicht &uuml;ber das Men&uuml; aktiviert werden. Dazu bitte das Attribut blacklistIDs entfernen.
		</li><br>
   	</ul>
   
     
=end html_DE
=cut
