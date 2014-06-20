##############################################
# $Id$
#
#     70_PIONEERAVR.pm
#
#     This file is part of Fhem.
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
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# by hofrichter
#
# This module handles the communication with a Pioneer AVR and controls the main zone. 

# this is the physical module - it opens the device (via rs232 or TCP), and its ReadFn is called after the global select reports, 
#   that data is available.
# - on Windows select does not work for devices not connected via TCP, here is a ReadyFn function necessary, which polls the device 10 times 
#    a second, and returns true if data is available.
# - ReadFn makes sure, that a message is complete and correct, and calls the global Dispatch() with one message
# - Dispatch() searches for a matching logical module (by checking $hash->{Clients} or $hash->{MatchList} in the physical module, and 
# $hash->{Match} in all matching logical modules), and calls the ParseFn of the logical module 
# (we use this mechanism to pass informations to the PIONEERAVR_ZONE device(s) ) 
#
# See also:
#  Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx
#  

# TODO: 
# match for devices/Dispatch() ???
# random/repeat attributes
# auto create zones
# remote control layout (dynamic depending on available/current input?)
# option for not permanent data connection
# handle special chars in display
# supress the "on" command if networkStandby = "off"
# 
# changelog
# 10.6.2014:version 0007
#			unified logging texts
#			added "verbose 5" log messages for all reads (messages coming from the PioneerAVR)
#			added "verbose 5" log messages for all set (commands sent to the PioneerAVR)
#			added "verbose 5" log messages for all get (commands sent to the PioneerAVR)
#			fixed set <name> listeningMode <mode>
#			fixed get <name> raw <PIONEER_RAW_COMMAND> - this sends <PIONEER_RAW_COMMAND> to the PioneerAVR (e.g. to power off the Pioneer AVR: get mypioneerAvr raw PF )
#				get <name> raw (without further arguments) sends only a new line command -> this should wakeup the connection if the PioneerAVR is in standby
#			removed unneeded functions, RESTART OF FHEM NEEDED (reload PIONEERAVR is not enough)
#			updated set <name> on -- to be even more Pioneer documentation conform (sending now additionally \n\r immediately before PO\n\r)
# 9.6.2014: all commands end now with "\r\n"
#			The command for PowerOn (PO) is now send twice 
#			"blink" (part of setextensions) does not make much sense for a Pioneer AVR - set <name> blink returns this information ;-)  
#			Added support for module 95_remotecontrol
#			New functions: sub RC_layout_PioneerAVR(); sub PIONEERAVR_RCmakenotify($$);
#			Updated PIONEERAVR_Initialize for remotecontrol
#			added reading "networkStandby" [on|off] -> "on" indicates that the Pioneer AVR can be turned on from standby
#			added reading "tunerFrequency"
#		version 0008
#			fixed get <name> tunerFrequency

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
} else {
  require Device::SerialPort;
}
#########################
# Forward declaration
sub PIONEERAVR_Set($@);
sub PIONEERAVR_Get($@);
sub PIONEERAVR_Define($$);
sub PIONEERAVR_Undef($$);
sub PIONEERAVR_Read($);
sub PIONEERAVR_Write($$);
sub PIONEERAVR_Parse($$$);
sub RC_layout_PioneerAVR();
sub PIONEERAVR_RCmakenotify($$);

#use vars qw {%attr %defs};

#####################################
#Die Funktion wird von Fhem.pl nach dem Laden des Moduls aufgerufen
# und bekommt einen Hash für das Modul als zentrale Datenstruktur übergeben.
# Dieser Hash wird im globalen Hash %modules gespeichert - hier $modules{PIONEERAVR}
# Es handelt sich also nicht um den oben beschriebenen Hash der Geräteinstanzen sondern einen Hash,
# der je Modul Werte enthält, beispielsweise auch die Namen der Funktionen, die das Modul implementiert
# und die fhem.pl aufrufen soll. Die Initialize-Funktion setzt diese Funktionsnamen, in den Hash des Moduls
#
# Darüber hinaus sollten die vom Modul unterstützen Attribute definiert werden
# In Fhem.pl werden dann die entsprechenden Werte beim Aufruf eines attr-Befehls in die 
# globale Datenstruktur $attr{$name}, z.B. $attr{$name}{header} für das Attribut header gespeichert. 
# Falls im Modul weitere Aktionen oder Prüfungen beim Setzen eines Attributs nötig sind, dann kann 
# die Funktion X_Attr implementiert und in der Initialize-Funktion bekannt gemacht werden.
#
# Die Variable $readingFnAttributes, die an die Liste der unterstützten Attribute angefügt wird, definiert Attributnamen,
# die dann verfügbar werden, wenn das Modul zum Setzen von Readings die Funktionen 
# readingsBeginUpdate, readingsBulkUpdate, readingsEndUpdate oder readingsSingleUpdate verwendet. 
# In diesen Funktionen werden Attribute wie event-min-interval oder auch event-on-change-reading ausgewertet

sub
PIONEERAVR_Initialize($) {
	my ($hash) = @_;

#	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{ReadFn}  = "PIONEERAVR_Read";
	$hash->{WriteFn} = "PIONEERAVR_Write";
	$hash->{ReadyFn} = "PIONEERAVR_Ready";
	$hash->{Clients} = ":PIONEERAVRZONE:";
	$hash->{ClearFn}  = "PIONEERAVR_Clear";

	# Normal devices
	$hash->{DefFn}   = "PIONEERAVR_Define";
	$hash->{UndefFn} = "PIONEERAVR_Undef";
	$hash->{GetFn}   = "PIONEERAVR_Get";
	$hash->{SetFn}   = "PIONEERAVR_Set";
	$hash->{AttrFn}  = "PIONEERAVR_Attr";
	$hash->{AttrList}= "logTraffic:0,1,2,3,4,5 ".
						$readingFnAttributes;
	
	# remotecontrol
	$data{RC_layout}{pioneerAvr} = "RC_layout_PioneerAVR";
  
}

######################################
#Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Geräte ausgeführt wird 
# und das Modul bereits geladen und mit der Initialize-Funktion initialisiert ist. Sie ist typischerweise dazu da,
# die übergebenen Parameter zu prüfen und an geeigneter Stelle zu speichern sowie 
# einen Kommunikationsweg zum Pioneer Receiver zu öffnen (z.B. TCP-Verbindung, RS232-Schnittstelle)
#Als Übergabeparameter bekommt die Define-Funktion den Hash der Geräteinstanz sowie den Rest der Parameter, die im Befehl angegeben wurden. 
#
# Damit die übergebenen Werte auch anderen Funktionen zur Verfügung stehen und an die jeweilige Geräteinstanz gebunden sind, 
# werden die Werte typischerweise als Internals im Hash der Geräteinstanz gespeichert 

sub
PIONEERAVR_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t]+", $def);
    my $name = $hash->{NAME};

    Log3 $name, 5, "PIONEERAVR $name: called function PIONEERAVR_Define()";

	my $protocol = $a[2];

	if( int(@a) != 4 || (($protocol ne "telnet") && ($protocol ne "serial"))) {
		my $msg = "Wrong syntax: define <name> PIONEERAVR telnet <ipaddress[:port]> or define <name> PIONEERAVR serial <devicename[\@baudrate]>";
		Log3 $name, 4, "PIONEERAVR $name: " . $msg;
		return $msg;
	}
    $hash->{TYPE} = "PIONEERAVR";

	DevIo_CloseDev($hash);

	$hash->{Protocol}= $protocol;
	my $devicename= $a[3];
	$hash->{DeviceName} = $devicename;

	my $ret = DevIo_OpenDev($hash, 0, undef);
	
	# set default attributes
    unless ( exists( $attr{$name}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:mute:input';
    }
    unless ( exists( $attr{$name}{devStateIcon} ) ) {
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_STOP:on absent:rc_RED';
    }
    $hash->{helper}{receiver} = undef;

    unless ( exists( $hash->{helper}{AVAILABLE} )
        and ( $hash->{helper}{AVAILABLE} == 0 ))
    {
        $hash->{helper}{AVAILABLE} = 1;
        readingsSingleUpdate( $hash, "presence", "present", 1 );
    }
  
	$hash->{helper}{INPUTNAMES} = {
		"00" => {
			"name" => "phono",
			"aliasName" => "",
			"enabled" => "1"
		},
		"01" => {
			"name" => "cd",
			"aliasName" => "",
			"enabled" => "1"
		},
		"02" => {
			"name" => "tuner",
			"aliasName" => "",
			"enabled" => "1"
		},
		"03" => {
			"name" => "cdrTape",
			"aliasName" => "",
			"enabled" => "1"
		},
		"04" => {
			"name" => "dvd",
			"aliasName" => "",
			"enabled" => "1"
		},
		"05" => {
			"name" => "tvSat",
			"aliasName" => "",
			"enabled" => "1"
		},
		"06" => {
			"name" => "CblSat",
			"aliasName" => "",
			"enabled" => "1"
		},
		"10" => {
			"name" => "video1",
			"aliasName" => "",
			"enabled" => "1"
		},
		"12" => {
			"name" => "multiChIn",
			"aliasName" => "",
			"enabled" => "1"
		},
		"14" => {
			"name" => "video2",
			"aliasName" => "",
			"enabled" => "1"
		},
		"15" => {
			"name" => "dvrBdr",
			"aliasName" => "",
			"enabled" => "1"
		},
		"17" => {
			"name" => "iPodUsb",
			"aliasName" => "",
			"enabled" => "1"
		},
		"18" => {
			"name" => "xmRadio",
			"aliasName" => "",
			"enabled" => "1"
		},
		"19" => {
			"name" => "hdmi1",
			"aliasName" => "",
			"enabled" => "1"
		},
		"20" => {
			"name" => "hdmi2",
			"aliasName" => "",
			"enabled" => "1"
		},
		"21" => {
			"name" => "hdmi3",
			"aliasName" => "",
			"enabled" => "1"
		},
		"22" => {
			"name" => "hdmi4",
			"aliasName" => "",
			"enabled" => "1"
		},
		"23" => {
			"name" => "hdmi5",
			"aliasName" => "",
			"enabled" => "1"
		},
		"25" => {
			"name" => "bd",
			"aliasName" => "",
			"enabled" => "1"
		},
		"26" => {
			"name" => "homeMediaGallery",
			"aliasName" => "",
			"enabled" => "1"
		},
		"27" => {
			"name" => "sirius",
			"aliasName" => "",
			"enabled" => "1"
		},
		"31" => {
			"name" => "hdmiCyclic",
			"aliasName" => "",
			"enabled" => "1"
		},
		"33" => {
			"name" => "adapterPort",
			"aliasName" => "",
			"enabled" => "1"
		}			
	};

	PIONEERAVR_askForInputNames($hash,5);

	# ----------------Human Readable command mapping table-----------------------
	$hash->{helper}{SETS} = {
		'main' => {
			'on'                 => 'PO',
			'off'                => 'PF',
			'toggle'             => 'PZ',
			'volumeUp'           => 'VU',
			'volumeDown'         => 'VD',
			'volume'             => 'VL',
			'muteOn'			 => 'MO',
			'muteOff'			 => 'MF',
			'muteToggle'		 => 'MZ',
			'input'			     => 'FN',
			'inputUp'			 => 'FU',
			'inputDown'			 => 'FD',
			'channelUp'			 => 'TPI',
			'channelDown'		 => 'TPD',
			'playNetwork'		 => '10NW',
			'pauseNetwork'		 => '11NW',
			'stopNetwork'		 => '20NW',
			'repeatNetwork'		 => '34NW',
			'shuffleNetwork'	 => '35NW',
			'playIpod'	    	 => '00IP',
			'pauseIpod'	    	 => '01IP',
			'stopIpod'	    	 => '02IP',
			'repeatIpod'	     => '07IP',
			'shuffleIpod'	     => '08IP',
			'playAdapterPort'	 => '10BT',
			'pauseAdapterPort'	 => '11BT',
			'stopAdapterPort'	 => '12BT',
			'repeatAdapterPort'	 => '17BT',
			'shuffleAdapterPort' => '18BT',
			'playMhl'       	 => '23MHL',
			'pauseMhl'       	 => '25MHL',
			'stopMhl'       	 => '24MHL'
		},
		'zone2' => {
			'on'                 => 'APO',
			'off'                => 'APF',
			'toggle'             => 'APZ',
			'volumeUp'           => 'ZU',
			'volumeDown'         => 'ZD',
			'muteOn'			 => 'Z2MO',
			'muteOff'			 => 'Z2MF',
			'muteToggle'		 => 'Z2MZ',
			'inputUp'			 => 'ZSFU',
			'inputDown'			 => 'ZSFD'
		},
		'zone3' => {
			'on'                 => 'BPO',
			'off'                => 'BPF',
			'toggle'             => 'BPZ',
			'volumeUp'           => 'YU',
			'volumeDown'         => 'YD',
			'muteOn'			 => 'Z3MO',
			'muteOff'			 => 'Z3MF',
			'muteToggle'		 => 'Z3MZ',
			'inputUp'			 => 'ZTFU',
			'inputDown'			 => 'ZTFD'
		},
		'hdZone' => {
			'on'                 => 'ZEO',
			'off'                => 'ZEF',
			'toggle'             => 'ZEZ',
			'inputUp'			 => 'ZEC',
			'inputDown'			 => 'ZEB'
		}
	};
	# ----------------Human Readable command mapping table-----------------------
	$hash->{helper}{GETS}  = {
		'main' => {
			'power'                => '?P',
			'volume'               => '?V',
			'mute'                 => '?M',
			'input'                => '?F',
			'display'              => '?FL',
			'listeningMode'        => '?S',
			'listeningModePlaying' => '?L',
			'speakers'             => '?SPK',
			'speakerSystem'        => '?SSF',
			'channel'              => '?PR',
			'tunerFrequency'       => '?FR',
			'tunerChannelNames'    => '?TQ',
			'model'                => '?RGD',
			'networkStandby'	   => '?STJ',
			'softwareVersion'      => '?SSI'
		},
		'zone2' => {
			'power'              => '?AP',
			'volume'             => '?ZV',
			'mute'               => '?Z2M',
			'input'              => '?ZS'
		},
		'zone3' => {
			'power'              => '?BP',
			'volume'             => '?YV',
			'mute'               => '?Z3M',
			'input'              => '?ZT'
		},
		'hdZone' => {
			'power'              => '?ZEP',
			'input'              => '?ZEA'
		}
	};
	# ----------------Human Readable command mapping table-----------------------
    $hash->{helper}{SPEAKERSYSTEMS} = {
		"10"=>"9.1ch FH/FW",
		"00"=>"Normal(SB/FH)",
		"01"=>"Normal(sb/FW)",
		"02"=>"Speaker B",
		"03"=>"Front Bi-Amp",
		"04"=>"ZONE 2",
		"11"=>"7.1ch + Speaker B",
		"12"=>"7.1ch Front Bi-Amp",
		"13"=>"7.1ch + ZONE2",
		"14"=>"7.1ch FH/FW + ZONE2",
		"15"=>"5.1ch Bi-Amp + ZONE2",
		"16"=>"5.1ch + ZONE 2+3",
		"17"=>"5.1ch + SP-B Bi-Amp",
		"18"=>"5.1ch F+Surr Bi-Amp",
		"19"=>"5.1ch F+C Bi-Amp",
		"20"=>"5.1ch C+Surr Bi-Amp"
	};
	
	$hash->{helper}{TUNERCHANNELNAMES} = {
		"A1"=>""
	};
	
	$hash->{helper}{LISTENINGMODES} = {
		"0001"=>"stereoCyclic",
		"0010"=>"standard",
		"0009"=>"stereoDirectSet",
		"0011"=>"2chSource",
		"0013"=>"proLogic2movie",
		"0018"=>"proLogic2xMovie",
		"0014"=>"proLogic2music",
		"0019"=>"proLogic2xMusic",
		"0015"=>"proLogic2game",
		"0020"=>"proLogic2xGame",
		"0031"=>"proLogic2zHeight",
		"0032"=>"wideSurroundMovie",
		"0033"=>"wideSurroundMusic",
		"0012"=>"proLogic",
		"0016"=>"neo6cinema",
		"0017"=>"neo6music",
		"0028"=>"xmHdSurround",
		"0029"=>"neuralSurround",
		"0037"=>"neoXcinema",
		"0038"=>"neoXmusic",
		"0039"=>"neoXgame",
		"0040"=>"neuralSurroundNeoXcinema",
		"0041"=>"neuralSurroundNeoXmusic",
		"0042"=>"neuralSurroundNeoXgame",
		"0021"=>"multiChSource",
		"0022"=>"multiChSourceDolbyEx",
		"0023"=>"multiChSourceProLogic2xMovie",
		"0024"=>"multiChSourceProLogic2xMusic",
		"0034"=>"multiChSourceProLogic2zHeight",
		"0035"=>"multiChSourceWideSurroundMovie",
		"0036"=>"multiChSourceWideSurroundMusic",
		"0025"=>"multiChSourceDtsEsNeo6",
		"0026"=>"multiChSourceDtsEsMatrix",
		"0027"=>"multiChSourceDtsEsDiscrete",
		"0030"=>"multiChSourceDtsEs8chDiscrete",
		"0043"=>"multiChSourceNeoXcinema",
		"0044"=>"multiChSourceNeoXmusic",
		"0045"=>"multiChSourceNeoXgame",
		"0100"=>"advancedSurroundCyclic",
		"0101"=>"action",
		"0103"=>"drama",
		"0102"=>"sciFi",
		"0105"=>"monoFilm",
		"0104"=>"entertainmentShow",
		"0106"=>"expandedTheater",
		"0116"=>"tvSurround",
		"0118"=>"advancedGame",
		"0117"=>"sports",
		"0107"=>"classical",
		"0110"=>"rockPop",
		"0109"=>"unplugged",
		"0112"=>"extendedStereo",
		"0003"=>"frontStageSurroundAdvanceFocus",
		"0004"=>"frontStageSurroundAdvanceWide",
		"0153"=>"retrieverAir",
		"0113"=>"phonesSurround",
		"0050"=>"thxCyclic",
		"0051"=>"prologicThxCinema",
		"0052"=>"pl2movieThxCinema",
		"0053"=>"neo6cinemaThxCinema",
		"0054"=>"pl2xMovieThxCinema",
		"0092"=>"pl2zHeightThxCinema",
		"0055"=>"thxSelect2games",
		"0068"=>"thxCinemaFor2ch",
		"0069"=>"thxMusicFor2ch",
		"0070"=>"thxGamesFor2ch",
		"0071"=>"pl2musicThxMusic",
		"0072"=>"pl2xMusicThxMusic",
		"0093"=>"pl2zHeightThxMusic",
		"0073"=>"neo6musicThxMusic",
		"0074"=>"pl2gameThxGames",
		"0075"=>"pl2xGameThxGames",
		"0094"=>"pl2zHeightThxGames",
		"0076"=>"thxUltra2games",
		"0077"=>"prologicThxMusic",
		"0078"=>"prologicThxGames",
		"0201"=>"neoXcinemaThxCinema",
		"0202"=>"neoXmusicThxMusic",
		"0203"=>"neoXgameThxGames",
		"0056"=>"thxCinemaForMultiCh",
		"0057"=>"thxSurroundExForMultiCh",
		"0058"=>"pl2xMovieThxCinemaForMultiCh",
		"0095"=>"pl2zHeightThxCinemaForMultiCh",
		"0059"=>"esNeo6thxCinemaForMultiCh",
		"0060"=>"esMatrixThxCinemaForMultiCh",
		"0061"=>"esDiscreteThxCinemaForMultiCh",
		"0067"=>"es8chDiscreteThxCinemaForMultiCh",
		"0062"=>"thxSelect2cinemaForMultiCh",
		"0063"=>"thxSelect2musicForMultiCh",
		"0064"=>"thxSelect2gamesForMultiCh",
		"0065"=>"thxUltra2cinemaForMultiCh",
		"0066"=>"thxUltra2musicForMultiCh",
		"0079"=>"thxUltra2gamesForMultiCh",
		"0080"=>"thxMusicForMultiCh",
		"0081"=>"thxGamesForMultiCh",
		"0082"=>"pl2xMusicThxMusicForMultiCh",
		"0096"=>"pl2zHeightThxMusicForMultiCh",
		"0083"=>"exThxGamesForMultiCh",
		"0097"=>"pl2zHeightThxGamesForMultiCh",
		"0084"=>"neo6thxMusicForMultiCh",
		"0085"=>"neo6thxGamesForMultiCh",
		"0086"=>"esMatrixThxMusicForMultiCh",
		"0087"=>"esMatrixThxGamesForMultiCh",
		"0088"=>"esDiscreteThxMusicForMultiCh",
		"0089"=>"esDiscreteThxGamesForMultiCh",
		"0090"=>"es8chDiscreteThxMusicForMultiCh",
		"0091"=>"es8chDiscreteThxGamesForMultiCh",
		"0204"=>"neoXcinemaThxCinemaForMultiCh",
		"0205"=>"neoXmusicThxMusicForMultiCh",
		"0206"=>"neoXgameThxGamesForMultiCh",
		"0005"=>"autoSurrStreamDirectCyclic",
		"0006"=>"autoSurround",
		"0151"=>"autoLevelControlAlC",
		"0007"=>"direct",
		"0008"=>"pureDirect",
		"0152"=>"optimumSurround"
	};

	$hash->{helper}{LISTENINGMODESPLAYING} = {
		"0101"=>"[)(]PLIIx MOVIE",
		"0102"=>"[)(]PLII MOVIE",
		"0103"=>"[)(]PLIIx MUSIC",
		"0104"=>"[)(]PLII MUSIC",
		"0105"=>"[)(]PLIIx GAME",
		"0106"=>"[)(]PLII GAME",
		"0107"=>"[)(]PROLOGIC",
		"0108"=>"Neo:6 CINEMA",
		"0109"=>"Neo:6 MUSIC",
		"010c"=>"2ch Straight Decode",
		"010d"=>"[)(]PLIIz HEIGHT",
		"010e"=>"WIDE SURR MOVIE",
		"010f"=>"WIDE SURR MUSIC",
		"0110"=>"STEREO",
		"0111"=>"Neo:X CINEMA",
		"0112"=>"Neo:X MUSIC",
		"0113"=>"Neo:X GAME",
		"1101"=>"[)(]PLIIx MOVIE",
		"1102"=>"[)(]PLIIx MUSIC",
		"1103"=>"[)(]DIGITAL EX",
		"1104"=>"DTS Neo:6",
		"1105"=>"ES MATRIX",
		"1106"=>"ES DISCRETE",
		"1107"=>"DTS-ES 8ch ",
		"1108"=>"multi ch Straight Decode",
		"1109"=>"[)(]PLIIz HEIGHT",
		"110a"=>"WIDE SURR MOVIE",
		"110b"=>"WIDE SURR MUSIC",
		"110c"=>"Neo:X CINEMA ",
		"110d"=>"Neo:X MUSIC",
		"110e"=>"Neo:X GAME",
		"0201"=>"ACTION",
		"0202"=>"DRAMA",
		"0208"=>"ADVANCEDGAME",
		"0209"=>"SPORTS",
		"020a"=>"CLASSICAL",
		"020b"=>"ROCK/POP",
		"020d"=>"EXT.STEREO",
		"020e"=>"PHONES SURR.",
		"020f"=>"FRONT STAGE SURROUND ADVANCE",
		"0211"=>"SOUND RETRIEVER AIR",
		"0212"=>"ECO MODE 1",
		"0213"=>"ECO MODE 2",
		"0301"=>"[)(]PLIIx MOVIE +THX",
		"0302"=>"[)(]PLII MOVIE +THX",
		"0303"=>"[)(]PL +THX CINEMA",
		"0305"=>"THX CINEMA",
		"0306"=>"[)(]PLIIx MUSIC +THX",
		"0307"=>"[)(]PLII MUSIC +THX",
		"0308"=>"[)(]PL +THX MUSIC",
		"030a"=>"THX MUSIC",
		"030b"=>"[)(]PLIIx GAME +THX",
		"030c"=>"[)(]PLII GAME +THX",
		"030d"=>"[)(]PL +THX GAMES",
		"0310"=>"THX GAMES",
		"0311"=>"[)(]PLIIz +THX CINEMA",
		"0312"=>"[)(]PLIIz +THX MUSIC",
		"0313"=>"[)(]PLIIz +THX GAMES",
		"0314"=>"Neo:X CINEMA + THX CINEMA",
		"0315"=>"Neo:X MUSIC + THX MUSIC",
		"0316"=>"Neo:X GAMES + THX GAMES",
		"1301"=>"THX Surr EX",
		"1303"=>"ES MTRX +THX CINEMA",
		"1304"=>"ES DISC +THX CINEMA",
		"1305"=>"ES 8ch +THX CINEMA ",
		"1306"=>"[)(]PLIIx MOVIE +THX",
		"1309"=>"THX CINEMA",
		"130b"=>"ES MTRX +THX MUSIC",
		"130c"=>"ES DISC +THX MUSIC",
		"130d"=>"ES 8ch +THX MUSIC",
		"130e"=>"[)(]PLIIx MUSIC +THX",
		"1311"=>"THX MUSIC",
		"1313"=>"ES MTRX +THX GAMES",
		"1314"=>"ES DISC +THX GAMES",
		"1315"=>"ES 8ch +THX GAMES",
		"1319"=>"THX GAMES",
		"131a"=>"[)(]PLIIz +THX CINEMA",
		"131b"=>"[)(]PLIIz +THX MUSIC",
		"131c"=>"[)(]PLIIz +THX GAMES",
		"131d"=>"Neo:X CINEMA + THX CINEMA",
		"131e"=>"Neo:X MUSIC + THX MUSIC",
		"131f"=>"Neo:X GAME + THX GAMES",
		"0401"=>"STEREO",
		"0402"=>"[)(]PLII MOVIE",
		"0403"=>"[)(]PLIIx MOVIE",
		"0405"=>"AUTO SURROUND Straight Decode",
		"0406"=>"[)(]DIGITAL EX",
		"0407"=>"[)(]PLIIx MOVIE",
		"0408"=>"DTS +Neo:6",
		"0409"=>"ES MATRIX",
		"040a"=>"ES DISCRETE",
		"040b"=>"DTS-ES 8ch ",
		"040e"=>"RETRIEVER AIR",
		"040f"=>"Neo:X CINEMA",
		"0501"=>"STEREO",
		"0502"=>"[)(]PLII MOVIE",
		"0503"=>"[)(]PLIIx MOVIE",
		"0504"=>"DTS/DTS-HD",
		"0505"=>"ALC Straight Decode",
		"0506"=>"[)(]DIGITAL EX",
		"0507"=>"[)(]PLIIx MOVIE",
		"0508"=>"DTS +Neo:6",
		"0509"=>"ES MATRIX",
		"050a"=>"ES DISCRETE",
		"050b"=>"DTS-ES 8ch ",
		"050e"=>"RETRIEVER AIR",
		"050f"=>"Neo:X CINEMA",
		"0601"=>"STEREO",
		"0602"=>"[)(]PLII MOVIE",
		"0603"=>"[)(]PLIIx MOVIE",
		"0605"=>"STREAM DIRECT NORMAL Straight Decode",
		"0606"=>"[)(]DIGITAL EX",
		"0607"=>"[)(]PLIIx MOVIE",
		"0609"=>"ES MATRIX",
		"060a"=>"ES DISCRETE",
		"060b"=>"DTS-ES 8ch ",
		"060c"=>"Neo:X CINEMA",
		"0701"=>"STREAM DIRECT PURE 2ch",
		"0702"=>"[)(]PLII MOVIE",
		"0703"=>"[)(]PLIIx MOVIE",
		"0704"=>"Neo:6 CINEMA",
		"0705"=>"STREAM DIRECT PURE Straight Decode",
		"0706"=>"[)(]DIGITAL EX",
		"0707"=>"[)(]PLIIx MOVIE",
		"0708"=>"(nothing)",
		"0709"=>"ES MATRIX",
		"070a"=>"ES DISCRETE",
		"070b"=>"DTS-ES 8ch ",
		"070c"=>"Neo:X CINEMA",
		"0881"=>"OPTIMUM",
		"0e01"=>"HDMI THROUGH",
		"0f01"=>"MULTI CH IN"
	};
	#### statusRequest
	#### we execute all 'get <name> XXX'   
	foreach my $zone ( keys %{$hash->{helper}{GETS}} ) {
		foreach my $key ( keys %{$hash->{helper}{GETS}{$zone}} ) {
			PIONEERAVR_Write($hash, $hash->{helper}{GETS}->{$zone}->{$key});
			select(undef, undef, undef, 0.1);
		}
	}  
	return $ret;
}

#####################################
#Die Undef-Funktion ist das Gegenstück zur Define-Funktion und wird aufgerufen wenn ein Gerät mit delete gelöscht wird
# oder bei der Abarbeitung des Befehls rereadcfg, der ebenfalls alle Geräte löscht und danach das Konfigurationsfile neu abarbeitet.
# Entsprechend müssen in der Funktion typische Aufräumarbeiten durchgeführt werden wie das saubere Schließen von Verbindungen
# oder das Entfernen von internen Timern sofern diese im Modul zum Pollen verwendet wurden (siehe später).
#
#Zugewiesene Variablen im Hash der Geräteinstanz, Internals oder Readings müssen hier nicht gelöscht werden.
# In fhem.pl werden die entsprechenden Strukturen beim Löschen der Geräteinstanz ohnehin vollständig gelöscht.
sub
PIONEERAVR_Undef($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	# deleting port for clients
	foreach my $d (sort keys %defs) {
	if(defined($defs{$d}) &&
	   defined($defs{$d}{IODev}) &&
	   $defs{$d}{IODev} == $hash) {
		my $lev = ($reread_active ? 4 : 2);
		Log3 $hash, $lev, "PIONEERAVR $name: deleting port for $d";
		delete $defs{$d}{IODev};
	  }
	}

	DevIo_CloseDev($hash);
	return undef;
}

#####################################
sub
PIONEERAVR_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "PIONEERAVR_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

#####################################
sub
PIONEERAVR_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $msg = undef;

  PIONEERAVR_Clear($hash);
 
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

#####################################
sub
PIONEERAVR_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  DevIo_TimeoutRead($hash, 0.1);
}



#####################################
#Function to show special chars (e.g. \n\r) in logs
sub
dq($) 
{
	my ($s)= @_;
	$s= "<nothing>" unless(defined($s));
	return "\"" . escapeLogLine($s) . "\"";
}

#PIONEER_Log() is used to show the data sent end received from/to the PioneerAVR if attr logTraffic is set
sub
PIONEERAVR_Log($$$)
{
	my ($hash, $loglevel, $logmsg)= @_;
	my $name= $hash->{NAME};
	$loglevel = AttrVal($name, "logTraffic", undef) unless(defined($loglevel)); 
	return unless(defined($loglevel)); 
	Log3 $hash, $loglevel , "PIONEERAVR $name (loglevel: $loglevel): logTraffic $logmsg";
}

#####################################

sub
PIONEERAVR_Write($$) 
{
	my ($hash, $msg) = @_;
	$msg= $msg."\r\n";
	PIONEERAVR_Log $hash, undef, "SimpleWrite " . dq($msg);
	DevIo_SimpleWrite($hash, $msg, 0);
}

####################################
sub
PIONEERAVR_Set($@)
{
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd = $a[1];
	my @setsPlayer= ("play","pause","stop","repeat","shuffle"); # available commands for certain inputs (@playerInputNr)
	my @playerInputNr= ("17","33","38","44","45","48"); 		# Input number for Ipod, AdapterPort, InternetRadio, MediaServer, Favorites, Mhl
	my @setsTuner = ("channelUp","channelDown","channelStraight","channel"); # available commands for input tuner 
	my @setsWithoutArg= ("off","toggle","volumeUp","volumeDown","muteOn","muteOff","muteToggle","inputUp","inputDown"); # set commands without arguments
	my $playerCmd= "";
	my $inputNr= "";
	
	Log3 $name, 5, "PIONEERAVR $name: Processing PIONEERAVR_Set( $cmd )";
	# get all input names (preferable the aliasName) of the enabled inputs for the drop down list of "set <device> input xxx"  
	my @listInputNames = ();
	foreach my $key ( keys %{$hash->{helper}{INPUTNAMES}} ) {
		if (defined($hash->{helper}{INPUTNAMES}->{$key}{enabled})) {
			if ( $hash->{helper}{INPUTNAMES}->{$key}{enabled} eq "1" ) {
				if ($hash->{helper}{INPUTNAMES}{$key}{aliasName}) {
					push(@listInputNames,$hash->{helper}{INPUTNAMES}{$key}{aliasName});
				} elsif ($hash->{helper}{INPUTNAMES}{$key}{name}) {
					push(@listInputNames,$hash->{helper}{INPUTNAMES}{$key}{name});
				}
			}
		}
	}
	
	my $list = "reopen:noArg on:noArg off:noArg toggle:noArg input:"
	. join(',', sort @listInputNames)
	. " inputUp:noArg inputDown:noArg"
	. " channelUp:noArg channelDown:noArg channelStraight"
#	. join(',', sort values ($hash->{helper}{TUNERCHANNELNAMES}))
	. " channel:1,2,3,4,5,6,7,8,9"
	. " listeningMode:"
	. join(',', sort values (%{$hash->{helper}{LISTENINGMODES}}))
	. " volumeUp:noArg volumeDown:noArg mute:on,off,toggle statusRequest:noArg volume:slider,0,1,100"
	. " volumeStraight:slider,-80,1,12"
	. " speakers:off,A,B,A+B";
	
	my $currentInput= ReadingsVal($name,"input","");
	
	if (defined($hash->{helper}{main}{CURINPUTNR})) {
		$inputNr = $hash->{helper}{main}{CURINPUTNR};
	}
	#return "Can't find the current input - you might want to try 'get $name loadInputNames" if ($inputNr eq "");

	# some input have more set commands ...
	if ( $inputNr ~~ @playerInputNr ) {
		$list .= "play:noArg stop:noArg pause:noArg repeat:noArg shuffle:noArg";
	}  
	if ( $cmd eq "?" ) {
		return SetExtensions($hash, $list, $name, $cmd, @a);
		
	# set <name> blink is part of the setextensions
	# but blink does not make sense for an PioneerAVR so we disable it here
	} elsif ( $cmd eq "blink" ) {
		return "blink does not make too much sense with an PIONEER AVR isn't it?";
	}
	return "No Argument given" if ( !defined( $a[1] ) );

	# process set <name> command (without further argument(s))
	if(@a == 2) {
		Log3 $name, 5, "PIONEERAVR $name: Set $cmd (no arguments)";
		# if the data connection between the PioneerAVR and Fhem is lost, we can try to reopen the data connection manually
		if( $cmd eq "reopen" ) {
			return PIONEERAVR_Reopen($hash);
		### Power on
		### Command: PO
		### according to "Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx" (notice) we need to send <cr> and 
		### wait 100ms before the first command is accepted by the Pioneer AVR
		} elsif ( $cmd  eq "on" ) {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd -> 2x newline + 2x PO with 100ms break in between";
			my $setCmd= "";
			PIONEERAVR_Write($hash, $setCmd);
			select(undef, undef, undef, 0.1);
			PIONEERAVR_Write($hash, $setCmd);
			select(undef, undef, undef, 0.1);
			$setCmd= "\n\rPO";
			PIONEERAVR_Write($hash, $setCmd);	
			select(undef, undef, undef, 0.2);
			PIONEERAVR_Write($hash, $setCmd);	
			return undef;			
			
		#### simple set commands without attributes
		#### we just "translate" the human readable command to the PioneerAvr command
		#### lookup in $hash->{helper}{SETS} if the command exists and what to write to PioneerAvr 
		} elsif ( $cmd  ~~ @setsWithoutArg ) {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd (setsWithoutArg)";
			my $setCmd= $hash->{helper}{SETS}{main}{$a[1]};
			my $v= PIONEERAVR_Write($hash, $setCmd);
			return undef;
			
		# statusRequest: execute all "get" commands	to update the readings
		} elsif ( $cmd eq "statusRequest") {
			Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
			foreach my $key ( keys %{$hash->{helper}{GETS}{main}} ) {
				PIONEERAVR_Write($hash, $hash->{helper}{GETS}->{main}->{$key});
				select(undef, undef, undef, 0.1);
			}
		#### play, pause, stop, random, repeat
		#### Only available if the input is one of:
		####    ipod, internetRadio, mediaServer, favorites, adapterPort, mhl
		#### we need to send different Pioneer Avr commands
		####    depending on that input
		} elsif ($cmd  ~~ @setsPlayer) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (player command)";
			if ($inputNr eq "17") {
				$playerCmd= $cmd."Ipod";
			} elsif ($inputNr eq "33") {
				$playerCmd= $cmd."AdapterPort";
			#### internetRadio, mediaServer, favorites
			} elsif (($inputNr eq "38") || ($inputNr eq "44") || ($inputNr eq "45")) {
				$playerCmd= $cmd."Network";
			#### 'random' and 'repeat' are not available on input mhl
			} elsif (($inputNr eq "48") && (( $cmd eq "play") || ( $cmd eq "pause") ||( $cmd eq "stop"))) {
				$playerCmd= $cmd."Mhl";
			} else {
				my $err= "PIONEERAVR $name: The command $cmd for input nr. $inputNr is not possible!";
				Log3 $name, 5, $err;
				return $err;
			}
			my $setCmd= $hash->{helper}{SETS}{main}{$playerCmd};
			PIONEERAVR_Write($hash, $setCmd);
			return undef;
		#### channelUp, channelDown
		#### Only available if the input is 02 (tuner)		
		} elsif ($cmd  ~~ @setsTuner) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (tuner command)";
			if ($inputNr eq "02") {
				my $setCmd= $hash->{helper}{SETS}{main}{$cmd};
				PIONEERAVR_Write($hash, $setCmd);
			} else {
				my $err= "PIONEERAVR $name: The tuner command $cmd for input nr. $inputNr is not possible!";
				Log3 $name, 5, $err;
				return $err;
			}
			return undef;
		}
		#### commands with argument(s)
	} elsif(@a > 2) {
		my $arg = $a[2];
		####Input (all available Inputs of the Pioneer Avr -> see 'get $name loadInputNames')
		#### according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		#### first try the aliasName (only if this fails try the default input name)
		if ( $cmd eq "input" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
			foreach my $key ( keys %{$hash->{helper}{INPUTNAMES}} ) {
				if ( $hash->{helper}{INPUTNAMES}->{$key}{aliasName} eq $arg ) {
						PIONEERAVR_Write($hash, sprintf "%02dFN", $key);
				} elsif ( $hash->{helper}{INPUTNAMES}->{$key}{name} eq $arg ) {
					PIONEERAVR_Write($hash, sprintf "%02dFN", $key);
				}
			}
			return undef;
		####ListeningMode
		} elsif ( $cmd eq "listeningMode" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
			foreach my $key ( keys %{$hash->{helper}{LISTENINGMODES}} ) {
				if ( $hash->{helper}{LISTENINGMODES}->{$key} eq $arg ) {
					Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg)." -> found nr: ".$key." for listeningMode ".dq($arg);
					PIONEERAVR_Write($hash, sprintf "%04dSR", $key);
					return undef;
				} 
			}
			my $err= "PIONEERAVR $name: Error: unknown listeningMode $cmd --- $arg !";
			Log3 $name, 5, $err;
			return $err;
			
		#####VolumeStraight (-80.5 - 12) in dB
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "volumeStraight" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
			my $zahl = 80.5 + $arg;
			# Main Zone double as we have 0.5 db steps
			PIONEERAVR_Write($hash, sprintf "%03dVL", $zahl*2);
			return undef;
		####Volume (0 - 100) in %
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "volume" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
			my $zahl = sprintf "%d", $arg * 1.85;
			PIONEERAVR_Write($hash, sprintf "%03dVL", $zahl);
			return undef;
		####Mute (on|off|toggle)
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		} elsif ( $cmd eq "mute" ) {
			if ($arg eq "on") {
				PIONEERAVR_Write($hash, "MO");
				readingsSingleUpdate($hash, "mute", "on", 1 );
			}
			elsif ($arg eq "off") {
				PIONEERAVR_Write($hash, "MF");
				readingsSingleUpdate($hash, "mute", "off", 1 );
			}
			elsif ($arg eq "toggle") {
				PIONEERAVR_Write($hash, "MZ");
			} else {
				my $err= "PIONEERAVR $name: Error: unknown set ... mute argument: $arg !";
				Log3 $name, 5, $err;
				return $err;
			}
			return undef;
		#### channelStraight
		#### set tuner preset in Pioneer preset format (A1...G9)
		#### Only available if the input is 02 (tuner)
		#### X0YPR -> X = tuner preset class (A...G), Y = tuner preset number (1...9)
		} elsif ($cmd  eq "channelStraight" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr $arg (tuner command only available for 02)";
			if (($inputNr eq "02") && $arg =~ m/([A-G])([1-9])/ ) {
				my $setCmd= $1."0".$2."PR";
				PIONEERAVR_Write($hash,$setCmd);
			} else {
				my $err= "PIONEERAVR $name: Error: set ... channelStraight only available for input 02 (tuner) - not for $inputNr !";
				Log3 $name, 5, $err;
				return $err;			
			}
			return undef;
		#### channel
		####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
		#### set tuner preset numeric (1...9)
		#### Only available if the input is 02 (tuner)
		#### XTP -> X = tuner preset number (1...9)		
		} elsif ($cmd  eq "channel" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr $arg (tuner command)";
			if (($inputNr eq "02") && $arg =~ m/([1-9])/ ) {
				my $setCmd= $1."TP";
				PIONEERAVR_Write($hash,$setCmd);
			} else {
				my $err= "PIONEERAVR $name: Error: set ... channel only available for input 02 (tuner) - not for $inputNr !";
				Log3 $name, 5, $err;
				return $err;			
			}
			return undef;
			####Speakers (off|A|B|A+B)
		} elsif ( $cmd eq "speakers" ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd $arg";
			if ($arg eq "off") {
				PIONEERAVR_Write($hash, "0SPK");
			} elsif ($arg eq "A") {
				PIONEERAVR_Write($hash, "1SPK");
			} elsif ($arg eq "B") {
				PIONEERAVR_Write($hash, "2SPK");
			} elsif ($arg eq "A+B") {
				PIONEERAVR_Write($hash, "3SPK");
			} else {
				my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... speakers. Must be one of off, A, B, A+B  !";
				Log3 $name, 5, $err;
				return $err;			
			}
			return undef;
		} else {
		return SetExtensions($hash, $list, $name, $cmd, @a);
		}
	} else {
		return SetExtensions($hash, $list, $name, $cmd, @a);
	}
}
#####################################
sub
PIONEERAVR_Get($@)
{
	my ($hash, @a) = @_;

	return "get needs at least one parameter" if(@a < 2);

	my $name = $a[0];
	my $cmd= $a[1];
	my $arg = ($a[2] ? $a[2] : "");
	my @args= @a; shift @args; shift @args;
	my ($answer, $err);

	return "No get $cmd for dummies" if(IsDummy($name));
	####Raw
	#### sends $arg to the PioneerAVR
	if($cmd eq "raw") {
		my $allArgs= join " ", @args;
		Log3 $name, 5, "PIONEERAVR $name: sending raw command ".dq($allArgs);
		PIONEERAVR_Write($hash, $allArgs);
	####loadInputNames
	} elsif ( $cmd eq "loadInputNames" ) {
		Log3 $name, 5, "PIONEERAVR $name: processing get loadInputNames";
		PIONEERAVR_askForInputNames($hash, 5);
		return undef;

	} elsif(!defined($hash->{helper}{GETS}{main}{$cmd})) {
		my $gets= "";
		foreach my $key ( keys %{$hash->{helper}{GETS}{main}} ) {
			$gets.= $key.":noArg ";
		}
		return "$name error: unknown argument $cmd, choose one of raw loadInputNames:noArg " . $gets;
	####get commands for the main zone without arguments
	#### Fhem commands are translated to PioneerAVR commands as defined in PIONEERAVR_Define -> {helper}{GETS}{main}
	} elsif(defined($hash->{helper}{GETS}{main}{$cmd})) {
		Log3 $name, 5, "PIONEERAVR $name: processing get ". dq($cmd);
		my $pioneerCmd= $hash->{helper}{GETS}{main}{$cmd};
		my $v= PIONEERAVR_Write($hash, $pioneerCmd);
	}
}

#####################################
sub
PIONEERAVR_Attr($@)
{
  my @a = @_;
  my $hash= $defs{$a[1]};
  return undef;
}

#####################################
sub
PIONEERAVR_Reopen($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, undef);

  return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
# PIONEERAVR_Read() makes sure, that a message is complete and correct, and calls the global Dispatch() with one message
sub PIONEERAVR_Read($) 
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $state='';
	my $buf = '';
	#include previous partial message
	if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
		$buf = $hash->{PARTIAL} . DevIo_SimpleRead($hash);
	}
	else {
		$buf = DevIo_SimpleRead($hash);
	}
	return if($buf eq '');
	  
	PIONEERAVR_Log $hash, undef, "Spontaneously received " . dq($buf);

	Log3 $name, 5, "PIONEERAVR $name RAW: ". dq($buf);
	
	# $buf can contain more than one line of information
	# the lines are separated by "\r\n"
	# if the information in the line is not for the main zone it is dispatched to
	#    all listening modules otherwise we process it here
	readingsBeginUpdate($hash);
	while($buf =~ m/^(.*?)\r\n(.*)\Z/s ) {
		my $line = $1;
		$buf = $2;

		Log3 $name, 5, "PIONEERAVR $name: line received from PIONEERAVR: " . dq($line);
		Log3 $name, 5, "PIONEERAVR $name: line to do soon PIONEERAVR: " . dq($buf) unless ($buf eq "");
		if (( $line eq "R" ) ||( $line eq "" )) {
			Log3 $hash, 5, "PIONEERAVR $name: Supressing received " . dq($line);
			next;
		# Main zone volume
		} elsif ( substr($line,0,3) eq "VOL" ) {
			my $volume = substr($line,3,3);
			readingsBulkUpdate($hash, "volumeStraight", $volume/2 - 80 );				
			readingsBulkUpdate($hash, "volume", sprintf "%d", $volume/1.85 );
			Log3 $name, 5, "PIONEERAVR $name: ". dq($line) ." interpreted as: Main Zone - New volume = ".$volume . " (raw volume data).";
		# Main zone Mute				
		} elsif ( substr($line,0,3) eq "MUT" ) {
			my $mute = substr($line,3,1);
			if ($mute == "1") {
				readingsBulkUpdate($hash, "mute", "off" );
				Log3 $name, 5, "PIONEERAVR $name: ".dq($line) ." interpreted as: Main Zone - Mute off ";
			} 
			else {
				readingsBulkUpdate($hash, "mute", "on" );
				Log3 $name, 5, "PIONEERAVR $name: ".dq($line) ." interpreted as: Main Zone - Mute on ";
			}				
		# Main zone Input			
		} elsif ( $line =~ m/^FN(\d\d)$/) {
			my $inputNr = $1;
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Main Zone - Input is set to inputNr: $inputNr ";

			if ( $hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} ) {
				readingsBulkUpdate($hash, "input", $hash->{helper}{INPUTNAMES}{$inputNr}{aliasName} );
				Log3 $hash,5,"PIONEERAVR $name: Main Input aliasName for input $inputNr is " . $hash->{helper}{INPUTNAMES}{$inputNr}{aliasName};
			} elsif ( defined ( $hash->{helper}{INPUTNAMES}{$inputNr}{name}) ) {
				readingsBulkUpdate($hash, "input", $hash->{helper}{INPUTNAMES}{$inputNr}{name} );
				Log3 $hash,5,"PIONEERAVR $name: Main Input Name for input $inputNr is " . $hash->{helper}{INPUTNAMES}{$inputNr}{name};
			} else {
				readingsBulkUpdate($hash, "input", $line );
				Log3 $hash,5,"PIONEERAVR $name: Main InputName: can't find Name for input $inputNr";
			}
			$hash->{helper}{main}{CURINPUTNR} = $inputNr;

			# input names
			# RGBXXY(14char)
			# XX -> input number
			# Y -> 1: aliasName; 0: Standard (predefined) name
			# 14char -> name of the input
		} elsif ( $line=~ m/^RGB(\d\d)(\d)(.*)/ ) {
			my $inputNr = $1;
			my $isAlias = $2; #1: aliasName; 0: Standard (predefined) name
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Name for InputNr: $inputNr is ".dq($3);
			# remove non alnum
			$line =~ s/[^a-zA-Z 0-9]/ /g;
			# uc first
			$line =~ s/([\w']+)/\u\L$1/g;
			# remove whitespace
			$line =~ s/\s//g;
			# lc first
			if ($isAlias) {
				$hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} = lcfirst(substr($line,6));
			} else {
				$hash->{helper}{INPUTNAMES}->{$inputNr}{name} = lcfirst(substr($line,6));			
			}
			$hash->{helper}{INPUTNAMES}->{$inputNr}{enabled} = 1 if ( !defined($hash->{helper}{INPUTNAMES}->{$inputNr}{enabled}));
			$hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} = "" if ( !defined($hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName}));
			Log3 $hash,5,"$name: Input name for input $inputNr is " . lcfirst(substr($line,6));
			
		# input enabled
		} elsif ( $line=~ m/^SSC(\d\d)030(1|0)$/ ) {
		
			#		select(undef, undef, undef, 0.001);
			# check for input skip information
			# format: ?SSC<2 digit input function nr>03
			# response: SSC<2 digit input function nr>0300: use
			# response: SSC<2 digit input function nr>0301: skip
			# response: E06: inappropriate parameter (input function nr not available on that device)
			# we can not trust "E06" as it is not sure that it is the reply for the current input nr
		
			if ( $2 == 1) {
				$hash->{helper}{INPUTNAMES}->{$1}{enabled} = 0;
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: InputNr: $1 is disabled";
			} elsif ( $2 == 0) {
				$hash->{helper}{INPUTNAMES}->{$1}{enabled} = 1;
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: InputNr: $1 is enabled";
			}
			
		# Speaker			
		} elsif ( substr($line,0,3) eq "SPK" ) {
			my $speakers = substr($line,3,1);
			if ($speakers == "0") {
				readingsBulkUpdate($hash, "speakers", "off" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: speakers: off";
			} elsif ($speakers == "1") {
				readingsBulkUpdate($hash, "speakers", "A" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: speakers: A";
			} elsif ($speakers == "2") {
				readingsBulkUpdate($hash, "speakers", "B" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: speakers: B";
			} elsif ($speakers == "3") {
				readingsBulkUpdate($hash, "speakers", "A+B" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: speakers: A+B";
			} else {
				readingsBulkUpdate($hash, "speakers", $speakers );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: speakers: ". dq($speakers);
			}
		# Speaker System
		# do we have Zone 2 speakers?
		} elsif ( substr($line,0,3) eq "SSF" ) {
			if ( defined ( $hash->{helper}{SPEAKERSYSTEMS}->{substr($line,3,2)}) ) {
				readingsBulkUpdate($hash, "speakerSystem", $hash->{helper}{SPEAKERSYSTEMS}->{substr($line,3,2)} );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: SpeakerSystem: ". dq(substr($line,3,2));
			}
			else {
				readingsBulkUpdate($hash, "speakerSystem", $line );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Unknown SpeakerSystem " . dq(substr($line,3,2));
			}
		# Listening Mode
		} elsif ( substr($line,0,2) eq "SR" ) {
			if ( defined ( $hash->{helper}{LISTENINGMODES}->{substr($line,2)}) ) {
				readingsBulkUpdate($hash, "listeningMode", $hash->{helper}{LISTENINGMODES}->{substr($line,2)} );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: listeningMode: ". dq(substr($line,2));	
			}
			else {
				readingsBulkUpdate($hash, "listeningMode", $line );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown listeningMode: ". dq(substr($line,2));	
			}
		# Listening Mode Playing (for Display)
		} elsif ( substr($line,0,2) eq "LM" ) {
			if ( defined ( $hash->{helper}{LISTENINGMODESPLAYING}->{substr($line,2,4)}) ) {
				readingsBulkUpdate($hash, "listeningModePlaying", $hash->{helper}{LISTENINGMODESPLAYING}->{substr($line,2,4)} );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: listeningModePlaying: ". dq(substr($line,2,4));	
			}
			else {
				readingsBulkUpdate($hash, "listeningModePlaying", $line );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown listeningModePlaying: ". dq(substr($line,2,4));	
			}
		# Main zone Power	
		} elsif ( substr($line,0,3) eq "PWR" ) {
			my $power = substr($line,3,1);
			if ($power == "0") {
				readingsBulkUpdate($hash, "power", "on" );
				$state = "on";
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Power: on";	
			} else {
				readingsBulkUpdate($hash, "power", "off" );
				$state = "off";
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Power: off";	
			}
			# Set reading for state
			#
			if ( !defined( $hash->{READINGS}{state}{VAL} )
				|| $hash->{READINGS}{state}{VAL} ne $state )
			{
				readingsBulkUpdate( $hash, "state", $state );
			}
		# Display updates
		} elsif ( substr($line,0,2) eq "FL" ) {
			my $display = pack("H*",substr($line,4,28));
			readingsBulkUpdate($hash, "displayPrevious", ReadingsVal($name,"display","") );
			readingsBulkUpdate($hash, "display", $display );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Display update";	

			# Tuner channel names
		} elsif ( $line =~ m/^TQ(\w\d)\"(.{8})\"$/ ) {
			$hash->{helper}{TUNERCHANNELNAMES}{$1} = $2;
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: tunerChannel: $1 has the name: " .dq($2);	
		# Tuner channel
		} elsif ( $line =~ m/^PR(\w)0(\d)$/ ) {
			readingsBulkUpdate($hash, "channelStraight", $1.$2 );
			readingsBulkUpdate($hash, "channelName", $hash->{helper}{TUNERCHANNELNAMES}{$1.$2} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Current tunerChannel: " . $1.$2;	
			if ($1 eq "A") {
				readingsBulkUpdate($hash, "channel", $2);
			} else {
				readingsBulkUpdate($hash, "channel", "-");
			}
		# Tuner frequency
		# FRFXXXYY -> XXX.YY Mhz
		} elsif ( $line =~ m/^FRF([0|1])([0-9]{2})([0-9]{2})$/ ) {
				my $tunerFrequency = $2.".".$3;
				if ($1==1) {
					$tunerFrequency = $1.$tunerFrequency;
				}
				readingsBulkUpdate($hash, "tunerFrequency", $tunerFrequency);
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: tunerFrequency: " . $tunerFrequency;	
			
		# model
		} elsif ( $line =~ m/^RGD<\d{3}><(.*)\/.*>$/ ) {
			readingsBulkUpdate($hash, "model", $1);			
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Model is " . $1;	
			
		# Software version
		} elsif ( $line =~ m/^SSI\"(.*)\"$/ ) {
			readingsBulkUpdate($hash, "softwareVersion", $1);
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: softwareVersion is " . $1;	

		# ERROR MESSAGES
		#   E02<CR+LF>	NOT AVAILABLE NOW	Detected the Command line which could not work now.		
		#   E03<CR+LF>	INVALID COMMAND	Detected an invalid Command with this model.		
		#   E04<CR+LF>	COMMAND ERROR	"Detected inappropriate Command line.
		#               Detected IP-only Commands on RS232C (GIA,GIC,FCA,FCB,GIH and GII)."		
		#   E06<CR+LF>	PARAMETER ERROR	Detected inappropriate Parameter.		
		#   B00<CR+LF>	BUSY	Now AV Receiver is Busy. Please wait few seconds.		

		} elsif ( $line =~ m/^E0(\d)$/ ) {
			my $errorMessage ="PIONEERAVR $name: Received Error code from PioneerAVR: $line";
			if ($1 == 2) {
				$errorMessage .= " (NOT AVAILABLE NOW - Detected the Command line which could not work now.)";
			} elsif ($1 == 3) {
				$errorMessage .= " (INVALID COMMAND - Detected an invalid Command with this model.)";
			} elsif ($1 == 4) {
				$errorMessage .= " (COMMAND ERROR - Detected inappropriate Command line.)";
			} elsif ($1 == 6) {
				$errorMessage .= " (PARAMETER ERROR - Detected inappropriate Parameter.)";
			} 
			Log3 $hash, 5, $errorMessage;
		} elsif ( $line =~ m/^B00$/ ) {
			Log3 $hash, 5,"PIONEERAVR $name: Error nr $line received (BUSY	Now AV Receiver is Busy. Please wait few seconds.)";
		# network standby
		# STJ1 -> on  -> Pioneer AVR can be switched on from standby
		# STJ0 -> off -> Pioneer AVR cannot be switched on from standby
		} elsif ( $line =~ m/^STJ([0|1])/) {
			if ($1 == "1") {
				readingsBulkUpdate($hash, "networkStandby", "on" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: networkStandby is on";	
			} 
			else {
				readingsBulkUpdate($hash, "networkStandby", "off" );
				Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: networkStandby is off";	
			}
		# dispatch "zone" - commands to other zones
		# Volume, mute, power
		} elsif ($line =~ m/^[Y|Z]V(\d\d)$|^Z[2|3]MUT(\d)$|^Z[2|3]F(\d\d)$|^[A|B]PR(0|1)$|^ZEA(\d\d)$|^ZEP(0|1)$/) { 
			Dispatch($hash, $line, undef);  # dispatch result to PIONEERAVRZONEs
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: not for the Main zone -> dispatch to PIONEERAVRZONEs";	
		} else {
			Log3 $hash, 5, "PIONEERAVR $name: received $line - don't know what this means - help me!";
		}
	}
	readingsEndUpdate($hash, 1);
	$hash->{PARTIAL} = $buf;
}


#########################################################

sub PIONEERAVR_askForInputNames($$) {
	my ($hash, $loglevel) = @_;
	my $name = $hash->{NAME};
	my $comstr = '';
	
	# we ask for the inputs 1 to 49 if an input name exists (command: ?RGB00 ... ?RGB49)
	# we ask for the inputs 1 to 49 if the input is disabled (command: ?SSC0003 ... ?SSC4903)
	#
	for ( my $i=0; $i<50; $i++ ) {
		select(undef, undef, undef, 0.1);
		$comstr = sprintf '?RGB%02d', $i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		$comstr = sprintf '?SSC%02d03',$i;
		PIONEERAVR_Write($hash,$comstr);
	}
}
#####################################
# Callback from 95_remotecontrol for command makenotify.
sub PIONEERAVR_RCmakenotify($$) {
  my ($nam, $ndev) = @_;
  my $nname="notify_$nam";
  
  fhem("define $nname notify $nam set $ndev remoteControl ".'$EVENT',1);
  Log3 undef, 2, "PIONEERAVR [remotecontrol:PIONEERAVR] Notify created: $nname";
  return "Notify created by PIONEERAVR: $nname";
}

#####################################
# Default-remote control layout for Pioneer AVR
sub 
RC_layout_PioneerAVR() {
  my $ret;
  my @row;
  $row[0]="toggle:POWEROFF";
  $row[1]="volumeUp:UP,mute toggle:MUTE,inputUp:CHUP";
  $row[2]=":VOL,:blank,:PROG";
  $row[3]="channelDown:DOWN,:blank,channelDown:CHDOWN";
  $row[4]="attr rc_iconpath icons/remotecontrol";
  $row[5]="attr rc_iconprefix black_btn_";

  # unused available commands
  return @row;
}
#####################################


1;

=pod
=begin html

<a name="PIONEERAVR"></a>
<h3>PIONEERAVR</h3>
<ul>
  This module allows to remotely control a Pioneer AV receiver (only the MAIN-zone, other zones are controlled by the module PIONEERAVRZONE) 
  equipped with an ethernet interface or a RS232 port. 
  It enables Fhem to 
  <ul>
    <li>switch ON/OFF the receiver</li>
    <li>adjust the volume</li>
    <li>set the input source</li>
    <li>and configure some other parameters</li>
  </ul>
  <br><br>
  This module is based on the <a href="http://www.pioneerelectronics.com/StaticFiles/PUSA/Files/Home%20Custom%20Install/Elite%20&%20Pioneer%20FY14AVR%20IP%20&%20RS-232%207-31-13.zip">Pioneer documentation</a> 
  and tested with a Pioneer AVR VSX-923 from <a href="http://www.pioneer.de">Pioneer</a>.
  <br><br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the module is connected via serial Port or USB.
  <br><br>  
  This module tries to 
  <ul>
    <li>keep the data connection between Fhem and the Pioneer AV receiver open. If the connection is lost, this module tries to reconnect once</li>
    <li>forwards data to the module PIONEERAVRZONE to control the ZONEs of a Pioneer AV receiver</li>
  </ul>
  As long as Fhem is connected to the Pioneer AV receiver no other device (e.g. a smartphone) can connect to the Pioneer AV receiver on the same port.
  Some Pioneer AV receivers offer more than one port though.
  <br><br>
  <a name="PIONEERAVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVR telnet &lt;IPAddress:Port&gt;</code><br><br>
    or<br><br>
    <code>define &lt;name&gt; PIONEERAVR serial &lt;SerialDevice&gt;[&lt;@BaudRate&gt;]</code>
    <br><br>

    Defines a physical PIONEERAVR device. The keywords <code>telnet</code> or
    <code>serial</code> are fixed. Default port on Pioneer AV receivers is 23 (according to the above mentioned Pioneer documetation)<br><br>

    Examples:
    <ul>
      <code>define VSX923 PIONEERAVR telnet 192.168.0.91:23</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyS0</code><br>
      <code>define VSX923 PIONEERAVR serial /sev/ttyUSB0@9600</code><br>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of
	<li>reopen <br>Tries to reopen the data connection</li>
	<li>statusRequest<br>gets some information from the physical Pioneer AVR and updates the readings accordingly</li>
	<li>off <br>turn power off</li>
	<li>on <br>turn power on</li>
	<li>toggle <br>toggles power</li>
	<li>volume <0 ... 100><br>main volume in % of the maximum volume</li>
	<li>volumeUp<br>increases the main volume by 0.5dB</li>
	<li>volumeDown<br>decreases the main volume by 0.5dB</li>
	<li>volumeStraight<-80.5 ... 12><br>same values for volume as shown on the display of the Pioneer AV rreceiver</li>
	<li>mute <on|off|toggle></li>
	<li>input <not on the Pioneer hardware deactivated input><br>the list of possible (i.e. not deactivated)
	inputs is read in during Fhem start and with <code>get <name> statusRequest</code></li>
	<li>inputUp<br>change input to next input</li>
	<li>inputDown<br>change input to previous input</li>
	<li>listeningMode</li>
	<li>play <br>starts playback for the following inputs: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer, Mhl</li>
	<li>pause<br>pause playback for the same inputs as play</li>
	<li>stop<br>stops playback for the same inputs as play</li>
	<li>repeat<br>repeat for the following inputs: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer</li>
	<li>shuffle<br>random play for the same inputs as repeat</li>
    <br><br>
    Example:
    <ul>
      <code>set VSX923 on</code><br>
    </ul>
    <br>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Closes and reopens the device. Could be handy if the connection between Fhem and the Pioneer AV receiver is lost and cannot be
    reestablished automatically.
    <br><br>
  </ul>

  <a name="PIONEERAVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; raw &lt;command&gt;</code>
    <br><br>
    Sends the command <code>&lt;command&gt;</code> to the physical Pioneer AVR device
    <code>&lt;name&gt;</code>.
	<li><br>loadInputNames<br>reads the names of the inputs from the physical Pioneer AVR
	and checks if those inputs are enabled</li>
	<li>display<br>updates the reading 'display' and 'displayPrevious' with what is shown
	on the display of the physical Pioneer AVR</li>
  </ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>logTraffic &lt;loglevel&gt;<br>Enables logging of sent and received datagrams with the given loglevel. 
	Control characters in the logged datagrams are escaped, i.e. a double backslash is shown for a single backslash,
	\n is shown for a line feed character, etc.</li>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  
</ul>

=end html
=begin html_DE

<a name="PIONEERAVR"></a>
<h3>PIONEERAVR</h3>
<ul>
  Dieses Modul erlaubt es einen Pioneer AV Receiver via Fhem zu steuern (nur die MAIN-Zone, etwaige andere Zonen können mit dem Modul PIONEERAVRZONE gesteuert werden) wenn eine Datenverbindung via Ethernet oder RS232 hergestellt werden kann. 
  Es erlaubt Fhem 
  <ul>
    <li>Den Receiver ein/auszuschalten</li>
    <li>die Lautstärke zu ändern</li>
    <li>die Eingangsquelle auszuwählen</li>
    <li>und weitere Parameter zu kontrollieren</li>
  </ul>
  <br><br>
  Dieses Modul basiert auf der <a href="http://www.pioneerelectronics.com/StaticFiles/PUSA/Files/Home%20Custom%20Install/Elite%20&%20Pioneer%20FY14AVR%20IP%20&%20RS-232%207-31-13.zip">Pioneer documentation</a> 
  und ist mit einem Pioneer AVR VSX-923 von <a href="http://www.pioneer.de">Pioneer</a> getestet.
  <br><br>
  Achtung: Dieses Modul benötigt die Perl-Module Device::SerialPort oder Win32::SerialPort
  wenn die Datenverbindung via USB bzw. rs232 Port erfolgt.
  <br><br>  
  Dieses Modul versucht 
  <ul>
    <li>die Datenverbindung zwischen Fhem und Pioneer AV Receiver offen zu halten. Wenn die Verbindung abbricht, versucht das Modul
	einmal die Verbindung wieder herzustellen</li>
    <li>Daten vom/zum Pioneer AV Receiver dem Modul PIONEERAVRZONE (für die Kontrolle weiterer Zonen des Pioneer AV Receiver)
	zur Verfügung zu stellen.</li>
  </ul>
  Solange die Datenverbindung zwischen Fhem und dem Pioneer AV Receiver offen ist, kann kein anderes Gerät (z.B. ein Smartphone) 
  auf dem gleichen Port eine Verbindung zum Pioneer AV Receiver herstellen.
  Einige Pioneer AV Receiver bieten mehr als einen Port für die Datenverbindung an.
  <br><br>
  <a name="PIONEERAVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVR telnet &lt;IPAddress:Port&gt;</code><br><br>
    or<br><br>
    <code>define &lt;name&gt; PIONEERAVR serial &lt;SerialDevice&gt;[&lt;@BaudRate&gt;]</code>
    <br><br>

    Definiert ein physisches PIONEERAVR device. Die Schlüsselwörter <code>telnet</code> bzw.
    <code>serial</code> sind fix. Der Standard Port für die Ethernet Verbindung bei Pioneer AV Receiver ist 23 
	(laut der oben angeführten Pioneer Dokumetation)<br><br>

    Beispiele:
    <ul>
      <code>define VSX923 PIONEERAVR telnet 192.168.0.91:23</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyS0</code><br>
      <code>define VSX923 PIONEERAVR serial /sev/ttyUSB0@9600</code><br>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;was&gt; [&lt;value&gt;]</code>
    <br><br>
    "was" ist eines von
	<li>reopen <br>Versucht die Datenverbindung wieder herzustellen</li>
	<li>statusRequest<br>Fragt Information vom physischen Pioneer AV Receiver und aktualisiert die readings entsprechend</li>
	<li>off <br>Ausschalten</li>
	<li>on <br>Einschalten</li>
	<li>toggle <br>Ein/Ausschalten</li>
	<li>volume <0 ... 100><br>Lautstärke der Main-Zone in % der Maximallautstärke</li>
	<li>volumeUp<br>Lautstärke um 0.5dB erhöhen</li>
	<li>volumeDown<br>Lautstärke um 0.5dB verringern</li>
	<li>volumeStraight<-80.5 ... 12><br>Einstellen der Lautstärke mit einem Wert, wie er am Display des Pioneer AV Receiver angezeigt wird</li>
	<li>mute <on|off|toggle></li>
	<li>input <nicht am Pioneer AV Receiver deaktivierte Eingangsquelle><br> Die Liste der verfügbaren (also der nicht deaktivierten)
	Eingangsquellen wird beim Start von Fhem und auch mit <code>get <name> statusRequest</code> eingelesen</li>
	<li>inputUp<br>nächste Eingangsquelle auswählen</li>
	<li>inputDown<br>vorherige Eingangsquelle auswählen</li>
	<li>listeningMode</li>
	<li>play <br>Startet die Wiedergabe für folgende Eingangsquellen: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer, Mhl</li>
	<li>pause<br>Unterbricht die Wiedergabe für die gleichen Eingangsquellen wie "play"</li>
	<li>stop<br>Stoppt die Wiedergabe für die gleichen Eingangsquellen wie "play"</li>
	<li>repeat<br>Wiederholung für folgende Eingangsquellen: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer</li>
	<li>shuffle<br>Zufällige Wiedergabe für die gleichen Eingangsquellen wie "repeat"</li>
   <br><br>
    Beispiel:
    <ul>
      <code>set VSX923 on</code><br>
    </ul>
    <br>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Schliesst und öffnet ernaut die Datenverbindung von Fhem zum Pioneer AV Receiver. 
	Kann nützlich sein, wenn die Datenverbindung nicht automatisch wieder hergestellt werden kann.
    <br><br>
  </ul>


  <a name="PIONEERAVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; raw &lt;Befehl&gt;</code>
    <br><br>
    Sendet <code>&lt;Befehl&gt;</code> an den Pioneer AV Receiver
    <code>&lt;name&gt;</code>.
	<li><br>loadInputNames<br> liest die Namen der Eingangsquellen vom Pioneer AV Receiver
	und überprüft, ob sie aktiviert sind</li>
	<li>display<br>Aktualisiert das reading 'display' und 'displayPrevious' mit der aktuellen Anzeige des Displays Pioneer AV Receiver</li>
  </ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
    <li>logTraffic &lt;loglevel&gt;<br>Ermöglicht das loggen der Datenommunikation vom/zum Pioneer AV Receiver. 
	Steuerzeichen werden angezeigtz.B. ein doppelter Ruckwärts-Schrägstrich wird als einfacher Rückwärts-Schrägstrich angezeigt,
	\n wird für das Steuerzeichen "line feed" angezeigt, etc.</li>
    <li><a href="#verbose">verbose</a></li>
  </ul>
  <br><br>
  
</ul>
=end html_DE
=cut
