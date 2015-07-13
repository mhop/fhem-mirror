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
#
# This module handles the communication with a Pioneer AV receiver and controls the main zone. Tests are done with a Pioneer VSX923 

# this is the module for the communication interface and to control the main zone - 
#   it opens the device (via rs232 or TCP), and its ReadFn is called after the global select reports, that data is available.
# - on Windows select does not work for devices not connected via TCP, here is a ReadyFn function necessary, which polls the device 10 times 
#    a second, and returns true if data is available.
# - ReadFn makes sure, that a message is complete and correct, and calls the global Dispatch() with one message
# - Dispatch() searches for a matching logical module (by checking $hash->{Clients} or $hash->{MatchList} in this device, and 
# $hash->{Match} in all matching zone devices), and calls the ParseFn of the zone devices 
# (This mechanism is used to pass information to the PIONEERAVRZONE device(s) ) 
#
# See also:
#  Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx
#  

# TODO: 
# match for devices/Dispatch() ???
# random/repeat attributes
# remote control layout (dynamic depending on available/current input?)
# handle special chars in display
# suppress the "on" command if networkStandby = "off"
# 

package main;

use strict;
use warnings;
use SetExtensions;
use Time::HiRes qw(gettimeofday);
use DevIo;
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

	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{ReadFn}  = "PIONEERAVR_Read";
	$hash->{WriteFn} = "PIONEERAVR_Write";
#	$hash->{ReadyFn} = "PIONEERAVR_Ready";
	$hash->{Clients} = ":PIONEERAVRZONE:";
	$hash->{ClearFn} = "PIONEERAVR_Clear";

	# Normal devices
	$hash->{DefFn}   = "PIONEERAVR_Define";
	$hash->{UndefFn} = "PIONEERAVR_Undef";
	$hash->{GetFn}   = "PIONEERAVR_Get";
	$hash->{SetFn}   = "PIONEERAVR_Set";
	$hash->{AttrFn}  = "PIONEERAVR_Attr";
	$hash->{AttrList}= "logTraffic:0,1,2,3,4,5 checkConnection:enable,disable volumeLimitStraight volumeLimit ".
						$readingFnAttributes;
	
	# remotecontrol
	$data{RC_layout}{pioneerAvr} = "RC_layout_PioneerAVR";
}

######################################
#Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Geräte ausgeführt wird 
# und das Modul bereits geladen und mit der Initialize-Funktion initialisiert ist. Sie ist typischerweise dazu da,
# die übergebenen Parameter zu prüfen und an geeigneter Stelle zu speichern sowie 
# einen Kommunikationsweg zum Pioneer AV Receiver zu öffnen (TCP-Verbindung bzw. RS232-Schnittstelle)
#Als Übergabeparameter bekommt die Define-Funktion den Hash der Geräteinstanz sowie den Rest der Parameter, die im Befehl angegeben wurden. 
#
# Damit die übergebenen Werte auch anderen Funktionen zur Verfügung stehen und an die jeweilige Geräteinstanz gebunden sind, 
# werden die Werte typischerweise als Internals im Hash der Geräteinstanz gespeichert 

sub
PIONEERAVR_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $name = $hash->{NAME};
  my $protocol = $a[2];

  Log3 $name, 5, "PIONEERAVR $name: called function PIONEERAVR_Define()";

  if( int(@a) != 4 || (($protocol ne "telnet") && ($protocol ne "serial"))) {
	my $msg = "Wrong syntax: define <name> PIONEERAVR telnet <ipaddress[:port]> or define <name> PIONEERAVR serial <devicename[\@baudrate]>";
	Log3 $name, 3, "PIONEERAVR $name: " . $msg;
	return $msg;
  }
  $hash->{TYPE} = "PIONEERAVR";

  DevIo_CloseDev($hash);

  # $hash->{DeviceName} is needed for DevIo_OpenDev()
  $hash->{Protocol}= $protocol;
  my $devicename= $a[3];
  $hash->{DeviceName} = $devicename;

  my $ret = DevIo_OpenDev($hash, 0, undef);
	
  # set default attributes
  unless ( exists( $attr{$name}{webCmd} ) ) {
    $attr{$name}{webCmd} = 'volume:mute:input';
  }
  unless ( exists( $attr{$name}{devStateIcon} ) ) {
    $attr{$name}{devStateIcon} = 'on:rc_GREEN:off off:rc_STOP:on disconnected:rc_RED:reopen';
  }
  $hash->{helper}{receiver} = undef;

  unless ( exists( $hash->{helper}{AVAILABLE} ) and ( $hash->{helper}{AVAILABLE} == 0 ))
  {
    $hash->{helper}{AVAILABLE} = 1;
    readingsSingleUpdate( $hash, "presence", "present", 1 );
  }

  # $hash->{helper}{INPUTNAMES} lists the default input names and their inputNr as provided by Pioneer. 
  # This module tries to read those names and the alias names from the AVR receiver and tries to check if this input is enabled or disabled
  # So this list is just a fall back if the module can't read the names ...
  # Additionally this module tries to get information from the Pioneer AVR 
  #  - about the input level adjust
  #  - to which connector each input is connected.
  #    There are 3 groups of connectors:
  #     - Audio connectors (possible values are: ANALOG, COAX 1...3, OPT 1...3)
  #     - Component connectors (anaolog video, possible values: COMPONENT 1...3)
  #     - HDMI connectors (possible values are hdmi 1 ... hdmi 8)
  $hash->{helper}{INPUTNAMES} = {
	"00" => {"name" => "phono",				"aliasName" => "",	"enabled" => "1",	"audioTerminal" => "No Assign", "componentTerminal" => "No Assign", "hdmiTerminal" => "No Assign", "inputLevelAdjust" => 1},
	"01" => {"name" => "cd",				"aliasName" => "",	"enabled" => "1"},
	"02" => {"name" => "tuner",				"aliasName" => "",	"enabled" => "1"},
	"03" => {"name" => "cdrTape",			"aliasName" => "",	"enabled" => "1"},
	"04" => {"name" => "dvd",				"aliasName" => "",	"enabled" => "1"},
	"05" => {"name" => "tvSat",				"aliasName" => "",	"enabled" => "1"},
	"06" => {"name" => "cblSat",			"aliasName" => "",	"enabled" => "1"},
	"10" => {"name" => "video1",			"aliasName" => "",	"enabled" => "1"},
	"12" => {"name" => "multiChIn",			"aliasName" => "",	"enabled" => "1"},
	"13" => {"name" => "usbDac",			"aliasName" => "",	"enabled" => "1"},
	"14" => {"name" => "video2",			"aliasName" => "",	"enabled" => "1"},
	"15" => {"name" => "dvrBdr",			"aliasName" => "",	"enabled" => "1"},
	"17" => {"name" => "iPodUsb",			"aliasName" => "",	"enabled" => "1"},
	"18" => {"name" => "xmRadio",			"aliasName" => "",	"enabled" => "1"},
	"19" => {"name" => "hdmi1",				"aliasName" => "",	"enabled" => "1"},
	"20" => {"name" => "hdmi2",				"aliasName" => "",	"enabled" => "1"},
	"21" => {"name" => "hdmi3",				"aliasName" => "",	"enabled" => "1"},
	"22" => {"name" => "hdmi4",				"aliasName" => "",	"enabled" => "1"},
	"23" => {"name" => "hdmi5",				"aliasName" => "",	"enabled" => "1"},
	"24" => {"name" => "hdmi6",				"aliasName" => "",	"enabled" => "1"},
	"25" => {"name" => "bd",				"aliasName" => "",	"enabled" => "1"},
	"26" => {"name" => "homeMediaGallery",	"aliasName" => "",	"enabled" => "1"},
	"27" => {"name" => "sirius",			"aliasName" => "",	"enabled" => "1"},
	"31" => {"name" => "hdmiCyclic",		"aliasName" => "",	"enabled" => "1"},
	"33" => {"name" => "adapterPort",		"aliasName" => "",	"enabled" => "1"},			
	"34" => {"name" => "hdmi7",				"aliasName" => "",	"enabled" => "1"},
	"35" => {"name" => "hdmi8",				"aliasName" => "",	"enabled" => "1"},
	"38" => {"name" => "internetRadio",		"aliasName" => "",	"enabled" => "1"},			
	"41" => {"name" => "pandora",			"aliasName" => "",	"enabled" => "1"},			
	"44" => {"name" => "mediaServer",		"aliasName" => "",	"enabled" => "1"},			
	"45" => {"name" => "favorites",			"aliasName" => "",	"enabled" => "1"},			
	"48" => {"name" => "mhl",				"aliasName" => "",	"enabled" => "1"},			
	"53" => {"name" => "spotify",			"aliasName" => "",	"enabled" => "1"}
	};
  # ----------------Human Readable command mapping table for "set" commands-----------------------
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
		'bassUp'			 => 'BI',
		'bassDown'			 => 'BD',
		'trebleUp'			 => 'TI',
		'trebleDown'		 => 'TD',
		'input'			     => 'FN',
		'inputUp'			 => 'FU',
		'inputDown'			 => 'FD',
		'channelUp'			 => 'TPI',
		'channelDown'		 => 'TPD',
		'0Network'			 => '00NW',
		'1Network'			 => '01NW',
		'2Network'			 => '02NW',
		'3Network'			 => '03NW',
		'4Network'			 => '04NW',
		'5Network'			 => '05NW',
		'6Network'			 => '06NW',
		'7Network'			 => '07NW',
		'8Network'			 => '08NW',
		'9Network'			 => '09NW',
		'prevNetwork'		 => '12NW',
		'nextNetwork'		 => '13NW',
		'revNetwork'		 => '14NW',
		'fwdNetwork'		 => '15NW',
		'upNetwork'		     => '26NW',
		'downNetwork'		 => '27NW',
		'rightNetwork'		 => '28NW',
		'leftNetwork'		 => '29NW',
		'enterNetwork'		 => '30NW',
		'returnNetwork'		 => '31NW',
		'menuNetwork'		 => '36NW',
		'playNetwork'		 => '10NW',
		'pauseNetwork'		 => '11NW',
		'stopNetwork'		 => '20NW',
		'repeatNetwork'		 => '34NW',
		'shuffleNetwork'	 => '35NW',
		'selectLine01'		 => '01GFH',
		'selectLine02'		 => '02GFH',
		'selectLine03'		 => '03GFH',
		'selectLine04'		 => '04GFH',
		'selectLine05'		 => '05GFH',
		'selectLine06'		 => '06GFH',
		'selectLine07'		 => '07GFH',
		'selectLine08'		 => '08GFH',
		'playIpod'	    	 => '00IP',
		'pauseIpod'	    	 => '01IP',
		'stopIpod'	    	 => '02IP',
		'repeatIpod'	     => '07IP',
		'shuffleIpod'	     => '08IP',
		'prevIpod'	    	 => '03IP',
		'nextIpod'	    	 => '04IP',
		'revIpod'	    	 => '05IP',
		'fwdIpod'	         => '06IP',
		'upIpod'	         => '13IP',
		'downIpod'	    	 => '14IP',
		'rightIpod'	    	 => '15IP',
		'leftIpod'	    	 => '16IP',
		'enterIpod'  	     => '17IP',
		'returnIpod'	     => '18IP',
		'menuIpod'  	     => '19IP',
		'playAdapterPort'	 => '10BT',
		'pauseAdapterPort'	 => '11BT',
		'stopAdapterPort'	 => '12BT',
		'repeatAdapterPort'	 => '17BT',
		'shuffleAdapterPort' => '18BT',
		'prevAdapterPort'	 => '13BT',
		'nextAdapterPort'	 => '14BT',
		'revAdapterPort'	 => '15BT',
		'fwdAdapterPort'	 => '16BT',
		'upAdapterPort'	     => '21BT',
		'downAdapterPort'	 => '22BT',
		'rightAdapterPort'	 => '23BT',
		'leftAdapterPort'	 => '24BT',
		'enterAdapterPort'   => '25BT',
		'returnAdapterPort'	 => '26BT',
		'menuAdapterPort'  	 => '27BT',
		'playMhl'       	 => '23MHL',
		'pauseMhl'       	 => '25MHL',
		'stopMhl'       	 => '24MHL',
		'0Mhl'		    	 => '07MHL',
		'1Mhl'				 => '08MHL',
		'2Mhl'				 => '09MHL',
		'3Mhl'				 => '10MHL',
		'4Mhl'				 => '11MHL',
		'5Mhl'				 => '12MHL',
		'6Mhl'			 	 => '13MHL',
		'7Mhl'			 	 => '14MHL',
		'8Mhl'			 	 => '15MHL',
		'9Mhl'			 	 => '16MHL',
		'prevMhl'		 	 => '31MHL',
		'nextMhl'		 	 => '30MHL',
		'revMhl'		 	 => '27MHL',
		'fwdMhl'		 	 => '28MHL',
		'upMhl'		     	 => '01MHL',
		'downMhl'		 	 => '02MHL',
		'rightMhl'		  	 => '04MHL',
		'leftMhl'		 	 => '03MHL',
		'enterMhl'		 	 => '17MHL',
		'returnMhl'		 	 => '06MHL',
		'menuMhl'		 	 => '05MHL'		
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
  # ----------------Human Readable command mapping table for "get" commands-----------------------
  $hash->{helper}{GETS}  = {
	'main' => {
		'audioInfo'            => '?AST',
		'avrModel'             => '?RGD',
		'bass'            	   => '?BA',
		'channel'              => '?PR',
		'currentListIpod'      => '?GAI',
		'currentListNetwork'   => '?GAH',
		'display'              => '?FL',
		'eq'                   => '?ATC',
		'hdmiOut'              => '?HO',
		'input'                => '?F',
		'listeningMode'        => '?S',
		'listeningModePlaying' => '?L',
		'macAddress'		   => '?SVB',
		'mcaccMemory'          => '?MC',
		'mute'                 => '?M',
		'networkPorts'		   => '?SUM',
		'networkSettings'	   => '?SUL',
		'networkStandby'	   => '?STJ',
		'power'                => '?P',
		'signalSelect'         => '?DSA',
		'softwareVersion'      => '?SSI',
		'speakers'             => '?SPK',
		'speakerSystem'        => '?SSF',
		'standingWave'	       => '?ATD',
		'tone'			       => '?TO',
		'tunerFrequency'       => '?FR',
		'tunerChannelNames'    => '?TQ',
		'treble'               => '?TR',		
		'volume'               => '?V'
	},
	'zone2' => {
		'bass'            	 => '?ZGB',
		'input'              => '?ZS',
		'mute'               => '?Z2M',
		'power'              => '?AP',
		'treble'             => '?ZGC',		
		'volume'             => '?ZV'
	},
	'zone3' => {
		'input'              => '?ZT',
		'mute'               => '?Z3M',
		'power'              => '?BP',
		'volume'             => '?YV'
	},
	'hdZone' => {
		'input'              => '?ZEA',
		'power'              => '?ZEP'
	}
  };
  # ----------------Human Readable command mapping table for the remote control-----------------------
    $hash->{helper}{REMOTECONTROL} = {
		"cursorUp"       	  => "CUP",
		"cursorDown"       	  => "CDN",
		"cursorRight"		  => "CRI",
		"cursorLeft"       	  => "CLE",
		"cursorEnter"      	  => "CEN",
		"cursorReturn"     	  => "CRT",
		"statusDisplay"		  => "STS",
		"audioParameter"	  => "APA",
		"hdmiOutputParameter" => "HPA",
		"videoParameter"	  => "VPA",
		"homeMenu"			  => "HM"
  };
  
  # ----------------Human Readable command mapping table for the remote control-----------------------
  # Audio input signal type
  $hash->{helper}{AUDIOINPUTSIGNAL} = {
    "00"=>"ANALOG",
	"01"=>"ANALOG",
	"02"=>"ANALOG",
	"03"=>"PCM",
	"04"=>"PCM",
	"05"=>"DOLBY DIGITAL",
	"06"=>"DTS",
	"07"=>"DTS-ES Matrix",
	"08"=>"DTS-ES Discrete",
	"09"=>"DTS 96/24",
	"10"=>"DTS 96/24 ES Matrix",
	"11"=>"DTS 96/24 ES Discrete",
	"12"=>"MPEG-2 AAC",
	"13"=>"WMA9 Pro",
	"14"=>"DSD (HDMI or File via DSP route)",
	"15"=>"HDMI THROUGH",
	"16"=>"DOLBY DIGITAL PLUS",
	"17"=>"DOLBY TrueHD",
	"18"=>"DTS EXPRESS",
	"19"=>"DTS-HD Master Audio",
	"20"=>"DTS-HD High Resolution",
	"21"=>"DTS-HD High Resolution",
	"22"=>"DTS-HD High Resolution",
	"23"=>"DTS-HD High Resolution",
	"24"=>"DTS-HD High Resolution",
	"25"=>"DTS-HD High Resolution",
	"26"=>"DTS-HD High Resolution",
	"27"=>"DTS-HD Master Audio",
	"28"=>"DSD (HDMI or File via DSD DIRECT route)",
	"64"=>"MP3",
	"65"=>"WAV",
	"66"=>"WMA",
	"67"=>"MPEG4-AAC",
	"68"=>"FLAC",
	"69"=>"ALAC(Apple Lossless)",
	"70"=>"AIFF",
	"71"=>"DSD (USB-DAC)"
  };
 
  # Audio input frequency
  $hash->{helper}{AUDIOINPUTFREQUENCY} = {
    "00"=>"32kHz",
	"01"=>"44.1kHz",
	"02"=>"48kHz",
	"03"=>"88.2kHz",
	"04"=>"96kHz",
	"05"=>"176.4kHz",
	"06"=>"192kHz",
	"07"=>"---",
	"32"=>"2.8MHz",
	"33"=>"5.6MHz"
  };

  # Audio output frequency
  $hash->{helper}{AUDIOOUTPUTFREQUENCY} = {
    "00"=>"32kHz",
	"01"=>"44.1kHz",
	"02"=>"48kHz",
	"03"=>"88.2kHz",
	"04"=>"96kHz",
	"05"=>"176.4kHz",
	"06"=>"192kHz",
	"07"=>"---",
	"32"=>"2.8MHz",
	"33"=>"5.6MHz"
  }; 
  # working PQLS
  $hash->{helper}{PQLSWORKING} = {
    "0"=>"PQLS OFF",
	"1"=>"PQLS 2ch",
	"2"=>"PQLS Multi ch",
	"3"=>"PQLS Bitstream"
  };

  # Translation table for the possible speaker systems
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
	
  # In some Pioneer AVR models you can give tuner presets a name -> e.g. instead of "A1" it writes in the display "BBC1"
  # This modules tries to read those tuner preset names and write them into this list
  $hash->{helper}{TUNERCHANNELNAMES} = {
	"A1"=>""
  };

  # Translation table for all available ListeningModes - provided by Pioneer   
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

  # Translation table for all available playing ListeningModes - provided by Pioneer
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
  #translation for hdmiOut
  $hash->{helper}{HDMIOUT} = {
	"0"=>"1+2",
	"1"=>"1",
	"2"=>"2",
	"3"=>"OFF"
  };
  
  # for some inputs (e.g. internetRadio) the Pioneer AVR gives more information about the current program
  # The information is displayed on a (to the Pioneer avr) connected screen
  # This information is categorized - below are the categories ("dataTypes")  
  $hash->{helper}{SCREENTYPES} = {
	"00"=>"Massage",
	"01"=>"List",
	"02"=>"Playing(Play)",
	"03"=>"Playing(Pause)",
	"04"=>"Playing(Fwd)",
	"05"=>"Playing(Rev)",
	"06"=>"Playing(Stop)",
	"99"=>"Drawing invalid"
  };
  
  $hash->{helper}{LINEDATATYPES} = {
	"00"=>"normal",							
	"01"=>"directory",
	"02"=>"music",
	"03"=>"photo",
	"04"=>"video",
	"05"=>"nowPlaying",
	"20"=>"currentTitle",
	"21"=>"currentArtist",
	"22"=>"currentAlbum",
	"23"=>"time",
	"24"=>"genre",
	"25"=>"currentChapterNumber",
	"26"=>"format",
	"27"=>"bitPerSample",
	"28"=>"currentSamplingRate",
	"29"=>"currentBitrate",
	"32"=>"currentChannel",
	"31"=>"buffer",
	"33"=>"station"
  };
  $hash->{helper}{SCREENTYPES} = {
	"00"=>"Message",
	"01"=>"List",
	"02"=>"Playing(Play)",
	"03"=>"Playing(Pause)",
	"04"=>"Playing(Fwd)",
	"05"=>"Playing(Rev)",
	"06"=>"Playing(Stop)",
	"99"=>"Drawing invalid"
  };
 # indicates what the source of the screen information is 
 $hash->{helper}{SOURCEINFO} = {
	"00"=>"Internet Radio",
	"01"=>"MEDIA SERVER",
	"02"=>"iPod",
	"03"=>"USB",
	"04"=>"(Reserved)",
	"05"=>"(Reserved)",
	"06"=>"(Reserved)",
	"07"=>"PANDORA",
	"10"=>"AirPlay",
	"11"=>"Digital Media Renderer(DMR)",
	"99"=>"(Indeterminate)"
  };
  
  $hash->{helper}{CLEARONINPUTCHANGE} = {
  	"00"=>"screenLine01",
	"01"=>"screenLine02",
	"02"=>"screenLine03",
	"03"=>"screenLine04",
	"04"=>"screenLine05",
	"05"=>"screenLine06",
	"06"=>"screenLine07",
	"07"=>"screenLine08",
	"09"=>"screenLineType01",
	"10"=>"screenLineType02",
	"11"=>"screenLineType03",
	"12"=>"screenLineType04",
	"13"=>"screenLineType05",
	"14"=>"screenLineType06",
	"15"=>"screenLineType07",
	"16"=>"screenLineType08",
	"17"=>"screenLineHasFocus",
	"18"=>"screenLineNumberFirst",
	"19"=>"screenLineNumberLast",
	"20"=>"screenLineNumberTotal",
	"21"=>"screenLineNumbers",
	"22"=>"screenType",
	"23"=>"screenName",
	"24"=>"screenHierarchy",
	"25"=>"screenTopMenuKey",
	"26"=>"screenIpodKey",
	"27"=>"screenReturnKey"
	};
  
  ### initialize timer
  $hash->{helper}{nextConnectionCheck} = gettimeofday()+120;
  
  #### statusRequest
  # Update Input alias names, available and enabled Inputs
  #    This updates $hash->{helper}{INPUTNAMES}  
  #### Additionally we execute all 'get <name> XXX'   
  PIONEERAVR_statusUpdate($hash);

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
  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Undef() called";
  RemoveInternalTimer($hash);
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
  my $name = $hash->{NAME};
  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Ready() called at state: ".$hash->{STATE};
  if($hash->{STATE} eq "disconnected") {
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Ready() state: disconnected -> DevIo_OpenDev";
	return DevIo_OpenDev($hash, 1, "PIONEERAVR_DoInit");
  }
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
  Log3 $name, 5, "PIONEERAVR $name: PIONEER_DoInit() called";

  PIONEERAVR_Clear($hash);
 
  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  return undef;
}

#####################################
sub
PIONEERAVR_Clear($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Clear() called";

  # Clear the pipe
  DevIo_TimeoutRead($hash, 0.1);
}

####################################
sub
PIONEERAVR_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $a[0];
  my $cmd = $a[1];
  my $arg = ($a[2] ? $a[2] : "");
  my @args= @a; shift @args; shift @args;
  my @setsPlayer= ("play","pause","stop","repeat","shuffle","prev","next","rev","fwd","up","down","right","left","enter","return","menu"); # available commands for certain inputs (@playerInputNr)
  my @playerInputNr= ("13","17","18","26","27","33","38","41","44","45","48","53"); 		# Input number for usbDac, ipodUsb, xmRadio, homeMediaGallery, sirius, adapterPort, internetRadio, pandora, mediaServer, Favorites, mhl, spotify
  my @setsTuner = ("channelUp","channelDown","channelStraight","channel"); 					# available commands for input tuner 
  my @setsWithoutArg= ("off","toggle","volumeUp","volumeDown","muteOn","muteOff","muteToggle","inputUp","inputDown","selectLine01","selectLine02","selectLine03","selectLine04","selectLine05","selectLine06","selectLine07","selectLine08" ); # set commands without arguments
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
	. " hdmiOut:"
	. join(',', sort values (%{$hash->{helper}{HDMIOUT}}))
	. " inputUp:noArg inputDown:noArg"
	. " channelUp:noArg channelDown:noArg channelStraight"
#	. join(',', sort values ($hash->{helper}{TUNERCHANNELNAMES}))
	. " channel:1,2,3,4,5,6,7,8,9"
	. " listeningMode:"
	. join(',', sort values (%{$hash->{helper}{LISTENINGMODES}}))
	. " volumeUp:noArg volumeDown:noArg mute:on,off,toggle tone:on,bypass bass:slider,-6,1,6"
	. " treble:slider,-6,1,6 statusRequest:noArg volume:slider,0,1," . AttrVal($name, "volumeLimit", (AttrVal($name, "volumeLimitStraight", 12)+80)/0.92)
	. " volumeStraight:slider,-80,1," . AttrVal($name, "volumeLimitStraight", (AttrVal($name, "volumeLimit", 100)*0.92-80))
	. " signalSelect:auto,analog,digital,hdmi,cycle"
	. " speakers:off,A,B,A+B raw"
	. " mcaccMemory:1,2,3,4,5,6 eq:on,off standingWave:on,off"
	. " remoteControl:"
	. join(',', sort keys (%{$hash->{helper}{REMOTECONTROL}}));

  my $currentInput= ReadingsVal($name,"input","");
	
  if (defined($hash->{helper}{main}{CURINPUTNR})) {
	$inputNr = $hash->{helper}{main}{CURINPUTNR};
  }
  #return "Can't find the current input - you might want to try 'get $name loadInputNames" if ($inputNr eq "");

  # some input have more set commands ...
  if ( $inputNr ~~ @playerInputNr ) {
	$list .= " play:noArg stop:noArg pause:noArg repeat:noArg shuffle:noArg prev:noArg next:noArg rev:noArg fwd:noArg up:noArg down:noArg";
	$list .= " right:noArg left:noArg enter:noArg return:noArg menu:noArg";
	$list .= " selectLine01:noArg selectLine02:noArg selectLine03:noArg selectLine04:noArg selectLine05:noArg selectLine06:noArg selectLine07:noArg selectLine08:noArg";
  }
	$list .= " networkStandby:on,off";  
  if ( $cmd eq "?" ) {
	return SetExtensions($hash, $list, $name, $cmd, @args);
		
  # set <name> blink is part of the setextensions
  # but blink does not make sense for an PioneerAVR so we disable it here
  } elsif ( $cmd eq "blink" ) {
	return "blink does not make too much sense with an PIONEER AV receiver isn't it?";
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
	### wait 100ms before the first command is accepted by the Pioneer AV receiver
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
		if (ReadingsVal($name,"networkStandby","") eq "off") {
			return "NetworkStandby for the Pioneer AV receiver is off. If Fhem should be able to turn the AV Receiver on from standby enable networkStandby on the Pioneer AV Receiver!";
		} else {
			return undef;			
		}
	#### simple set commands without attributes
	#### we just "translate" the human readable command to the PioneerAvr command
	#### lookup in $hash->{helper}{SETS} if the command exists and what to write to PioneerAvr 
	} elsif ( $cmd  ~~ @setsWithoutArg ) {
		my $setCmd= $hash->{helper}{SETS}{main}{$a[1]};
		my $v= PIONEERAVR_Write($hash, $setCmd);
		Log3 $name, 5, "PIONEERAVR $name: Set $cmd (setsWithoutArg): ". $a[1] ." -> $setCmd";
		return undef;
		
	# statusRequest: execute all "get" commands	to update the readings
	} elsif ( $cmd eq "statusRequest") {
		Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
		PIONEERAVR_statusUpdate($hash);
		return undef;
	#### play, pause, stop, random, repeat,prev,next,rev,fwd,up,down,right,left,enter,return,menu
	#### Only available if the input is one of:
	####    ipod, internetRadio, mediaServer, favorites, adapterPort, mhl
	#### we need to send different commands to the Pioneer AV receiver
	####    depending on that input
	} elsif ($cmd  ~~ @setsPlayer) {
		Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (player command)";
		if ($inputNr eq "17") {
			$playerCmd= $cmd."Ipod";
		} elsif ($inputNr eq "33") {
			$playerCmd= $cmd."AdapterPort";
		#### homeMediaGallery, sirius, internetRadio, pandora, mediaServer, favorites, spotify
		} elsif (($inputNr eq "26") ||($inputNr eq "27") || ($inputNr eq "38") || ($inputNr eq "41") || ($inputNr eq "44") || ($inputNr eq "45") || ($inputNr eq "53")) {
			$playerCmd= $cmd."Network";
		#### 'random' and 'repeat' are not available on input mhl
		} elsif (($inputNr eq "48") && ( $cmd ne "repeat") && ( $cmd ne "random")) {
			$playerCmd= $cmd."Mhl";
		} else {
			my $err= "PIONEERAVR $name: The command $cmd for input nr. $inputNr is not possible!";
			Log3 $name, 3, $err;
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
			Log3 $name, 3, $err;
			return $err;
		}
		return undef;
	}
  #### commands with argument(s)
  } elsif(@a > 2) {
	####Raw
	#### sends $arg to the PioneerAVR
	if($cmd eq "raw") {
		my $allArgs= join " ", @args;
		Log3 $name, 5, "PIONEERAVR $name: sending raw command ".dq($allArgs);
		PIONEERAVR_Write($hash, $allArgs);
		return undef;
		
	####Input (all available Inputs of the Pioneer AV receiver -> see 'get $name loadInputNames')
	#### according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
	#### first try the aliasName (only if this fails try the default input name)
	} elsif ( $cmd eq "input" ) {
	Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	foreach my $key ( keys %{$hash->{helper}{INPUTNAMES}} ) {
		if ( $hash->{helper}{INPUTNAMES}->{$key}{aliasName} eq $arg ) {
			PIONEERAVR_Write($hash, sprintf "%02dFN", $key);
		} elsif ( $hash->{helper}{INPUTNAMES}->{$key}{name} eq $arg ) {
			PIONEERAVR_Write($hash, sprintf "%02dFN", $key);
		}
	}
	return undef;

	####hdmiOut
	} elsif ( $cmd eq "hdmiOut" ) {
	Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	foreach my $key ( keys %{$hash->{helper}{HDMIOUT}} ) {
		if ( $hash->{helper}{LISTENINGMODES}->{$key} eq $arg ) {
			Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg)." -> found nr: ".$key." for HDMIOut ".dq($arg);
			PIONEERAVR_Write($hash, sprintf "%dHO", $key);
			return undef;
		} 
	}
	my $err= "PIONEERAVR $name: Error: unknown HDMI Out $cmd --- $arg !";
	Log3 $name, 3, $err;
	return $err;
	
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
	Log3 $name, 3, $err;
	return $err;

	#####VolumeStraight (-80.5 - 12) in dB
	####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
	# PioneerAVR expects values between 000 - 185
	} elsif ( $cmd eq "volumeStraight" ) {
	  if (AttrVal($name, "volumeLimitStraight", 12) < $arg ) {
		$arg = AttrVal($name, "volumeLimitStraight", 12);
	  }
      Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	  my $pioneerVol = (80.5 + $arg)*2;
	  PIONEERAVR_Write($hash, sprintf "%03dVL", $pioneerVol);
	  return undef;
	  ####Volume (0 - 100) in %
	  ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV 
	  # PioneerAVR expects values between 000 - 185
	} elsif ( $cmd eq "volume" ) {
	  if (AttrVal($name, "volumeLimit", 100) < $arg ) {
		  $arg = AttrVal($name, "volumeLimit", 100);
	  }
	  Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	  my $pioneerVol = sprintf "%d", $arg * 1.85;
	  PIONEERAVR_Write($hash, sprintf "%03dVL", $pioneerVol);
	  return undef;
	####tone (on|bypass)
	} elsif ( $cmd eq "tone" ) {
	if ($arg eq "on") {
		PIONEERAVR_Write($hash, "1TO");
	}
	elsif ($arg eq "bypass") {
		PIONEERAVR_Write($hash, "0TO");
	} else {
		my $err= "PIONEERAVR $name: Error: unknown set ... tone argument: $arg !";
		Log3 $name, 3, $err;
		return $err;
	}
	return undef;
	####bass (-6 - 6) in dB
	} elsif ( $cmd eq "bass" ) {
	Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	my $zahl = sprintf "%d", ($arg * (-1)) + 6;
	PIONEERAVR_Write($hash, sprintf "%02dBA", $zahl);
	return undef;
	####treble (-6 - 6) in dB
	} elsif ( $cmd eq "treble" ) {
	Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
	my $zahl = sprintf "%d", ($arg * (-1)) + 6;
	PIONEERAVR_Write($hash, sprintf "%02dTR", $zahl);
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
		Log3 $name, 3, $err;
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
		Log3 $name, 3, $err;
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
		Log3 $name, 3, $err;
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
	
	####Signal select (auto|analog|digital|hdmi|cycle)
	} elsif ( $cmd eq "signalSelect" ) {
		Log3 $name, 5, "PIONEERAVR $name: set $cmd $arg";
		if ($arg eq "auto") {
			PIONEERAVR_Write($hash, "0SDA");
		} elsif ($arg eq "analog") {
			PIONEERAVR_Write($hash, "1SDA");
		} elsif ($arg eq "digital") {
			PIONEERAVR_Write($hash, "2SDA");
		} elsif ($arg eq "hdmi") {
			PIONEERAVR_Write($hash, "3SDA");
		} elsif ($arg eq "cycle") {
			PIONEERAVR_Write($hash, "9SDA");
		} else {
			my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... signalSelect. Must be one of auto|analog|digital|hdmi|cycle !";
			Log3 $name, 5, $err;
			return $err;			
		}
		return undef;	
	
	#mcacc memory
	} elsif ($cmd eq "mcaccMemory") {
		if ($arg > 0 and $arg < 7) {
		  my $setCmd = $arg."MC";
		  Log3 $name, 5, "PIONEERAVR $name: setting MCACC memory to ".dq($arg);
		  PIONEERAVR_Write($hash, $setCmd);
		  return undef;
		} else {
		my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... mcaccMemory!";
			Log3 $name, 5, $err;
			return $err;
		}
	
	# eq on/off/toggle
	} elsif ( $cmd eq "eq" ) {
		if ($arg eq "on") {
			PIONEERAVR_Write($hash, "1ATC");
#			readingsSingleUpdate($hash, "eq", "on", 1 );
		}
		elsif ($arg eq "off") {
			PIONEERAVR_Write($hash, "0ATC");
#			readingsSingleUpdate($hash, "eq", "off", 1 );
		} else {
			my $err= "PIONEERAVR $name: Error: unknown set ... eq argument: $arg !";
			Log3 $name, 3, $err;
			return $err;
		}
	# standingWave on/off/toggle
	} elsif ( $cmd eq "standingWave" ) {
	if ($arg eq "on") {
		PIONEERAVR_Write($hash, "1ATD");
	}
	elsif ($arg eq "off") {
		PIONEERAVR_Write($hash, "0ATD");
	} else {
		my $err= "PIONEERAVR $name: Error: unknown set ... standingWave argument: $arg !";
		Log3 $name, 3, $err;
		return $err;
	}

	# Network standby (on|off)
	# needs to be "on" to turn on the Pioneer AVR via this module 
	} elsif ( $cmd eq "networkStandby" ) {
	if ($arg eq "on") {
		PIONEERAVR_Write($hash, "1STJ");
	}
	elsif ($arg eq "off") {
		PIONEERAVR_Write($hash, "0STJ");
	} else {
		my $err= "PIONEERAVR $name: Error: unknown set ... networkStandby argument: $arg !";
		Log3 $name, 3, $err;
		return $err;
	}
	return undef;
	
	####remoteControl
	} elsif ( $cmd eq "remoteControl" ) {
		Log3 $name, 5, "PIONEERAVR $name: set $cmd $arg";
		if (exists $hash->{helper}{REMOTECONTROL}{$arg}) {
			my $setCmd= $hash->{helper}{REMOTECONTROL}{$arg};
			my $v= PIONEERAVR_Write($hash, $setCmd);
		} else {
			my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... remoteControl!";
			Log3 $name, 5, $err;
			return $err;			
		}
		return undef;
	} else {
		return SetExtensions($hash, $list, $name, $cmd, @args);
	}
  } else {
	return SetExtensions($hash, $list, $name, $cmd, @args);
  }
}
#####################################
sub
PIONEERAVR_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $a[0];
  my $cmd= $a[1];
  my $arg = ($a[2] ? $a[2] : "");
  my @args= @a; shift @args; shift @args;
  return "get needs at least one parameter" if(@a < 2);
  return "No get $cmd for dummies" if(IsDummy($name));

  ####loadInputNames
  if ( $cmd eq "loadInputNames" ) {
	Log3 $name, 5, "PIONEERAVR $name: processing get loadInputNames";
	PIONEERAVR_askForInputNames($hash, 5);
	return undef;

  } elsif(!defined($hash->{helper}{GETS}{main}{$cmd})) {
	my $gets= "";
	foreach my $key ( keys %{$hash->{helper}{GETS}{main}} ) {
		$gets.= $key.":noArg ";
	}
	return "$name error: unknown argument $cmd, choose one of loadInputNames:noArg " . $gets;
  ####get commands for the main zone without arguments
  #### Fhem commands are translated to PioneerAVR commands as defined in PIONEERAVR_Define -> {helper}{GETS}{main}
  } elsif(defined($hash->{helper}{GETS}{main}{$cmd})) {
	Log3 $name, 5, "PIONEERAVR $name: processing get ". dq($cmd);
	my $pioneerCmd= $hash->{helper}{GETS}{main}{$cmd};
	my $v= PIONEERAVR_Write($hash, $pioneerCmd);
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
# PIONEERAVR_Read() makes sure, that a message is complete and correct, 
# and calls the global Dispatch() with one message if this message is not for the main zone 
# as the main zone is handled here
sub PIONEERAVR_Read($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $state='';
  my $buf = '';
  my $msgForZone = "";
  #include previous partial message
  if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
	$buf = $hash->{PARTIAL} . DevIo_SimpleRead($hash);
  }	else {
	$buf = DevIo_SimpleRead($hash);
  }
  return if(!defined($buf));
  my $logMsg = "Spontaneously received " . dq($buf);
  PIONEERAVR_Log($hash, undef, $logMsg);

  # $buf can contain more than one line of information
  # the lines are separated by "\r\n"
  # if the information in the line is not for the main zone it is dispatched to
  #    all listening modules otherwise we process it here
  readingsBeginUpdate($hash);
  while($buf =~ m/^(.*?)\r\n(.*)\Z/s ) {
	my $line = $1;
	$buf = $2;
	Log3 $name, 5, "PIONEERAVR $name: processing ". dq($line) ." received from PIONEERAVR";
	#Log3 $name, 5, "PIONEERAVR $name: line to do soon: " . dq($buf) unless ($buf eq "");
	if (( $line eq "R" ) ||( $line eq "" )) {
		Log3 $hash, 5, "PIONEERAVR $name: Supressing received " . dq($line);
		# next; 
	# Main zone volume
	} elsif ( substr($line,0,3) eq "VOL" ) {
		my $volume = substr($line,3,3);
		my $volume_st = $volume/2 - 80;
		my $volume_vl = $volume/1.85;
		readingsBulkUpdate($hash, "volumeStraight", $volume_st);				
		readingsBulkUpdate($hash, "volume", sprintf "%d", $volume_vl);
		Log3 $name, 5, "PIONEERAVR $name: ". dq($line) ." interpreted as: Main Zone - New volume = ".$volume . " (raw volume data).";
	# correct volume if it is over the limit
	    if (AttrVal($name, "volumeLimitStraight", 12) < $volume_st or AttrVal($name, "volumeLimit", 100) < $volume_vl) {
			 my $limit_st = AttrVal($name, "volumeLimitStraight", 12);
			 my $limit_vl = AttrVal($name, "volumeLimit", 100);
			$limit_st = $limit_vl*0.92-80 if ($limit_vl*0.92-80 < $limit_st);
			my $pioneerVol = (80.5 + $limit_st)*2;
			PIONEERAVR_Write($hash, sprintf "%03dVL", $pioneerVol);
		}
	# Main zone tone (0 = bypass, 1 = on)
	} elsif ( $line =~ m/^TO([0|1])$/) {
		if ($1 == "1") {
			readingsBulkUpdate($hash, "tone", "on" );
			Log3 $name, 5, "PIONEERAVR $name: ".dq($line) ." interpreted as: Main Zone - tone on ";
		} 
		else {
			readingsBulkUpdate($hash, "tone", "bypass" );
			Log3 $name, 5, "PIONEERAVR $name: ".dq($line) ." interpreted as: Main Zone - tone bypass ";
		}
	# Main zone bass (-6 to +6 dB)
	# works only if tone=on
	} elsif ( $line =~ m/^BA(\d\d)$/) {
		readingsBulkUpdate($hash, "bass", ($1 *(-1)) + 6 );				
		Log3 $name, 5, "PIONEERAVR $name: ". dq($line) ." interpreted as: Main Zone - New bass = ".$1 . " (raw bass data).";

	# Main zone treble (-6 to +6 dB)
	# works only if tone=on
	} elsif ( $line =~ m/^TR(\d\d)$/) {
		readingsBulkUpdate($hash, "treble", ($1 *(-1)) + 6 );				
		Log3 $name, 5, "PIONEERAVR $name: ". dq($line) ." interpreted as: Main Zone - New treble = ".$1 . " (raw treble data).";

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

	} elsif ( $line=~ m/^AST(\d{2})(\d{2})(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d{2})(\d{2})(\d{4})(\d)(\d{2})(\d)$/ ) {
		# Audio information parameters
		#  data1-data2:Audio Input Signal
		#  data3-data4:Audio Input Frequency
		#  data5-data25:Audio Input Channel Format (ignored)
		#  data26-data43:Audio Output Channel (ignored)
		#  data44-data45:Audio Output Frequency
		#  data46-data47:Audio Output bit
		#  data48-data51:Reserved
		#  data52:Working PQLS
		#  data53-data54:Working Auto Phase Control Plus (in ms)(ignored)
		#  data55:Working Auto Phase Control Plus (Reverse Phase) (0... no revers phase, 1...reverse phase)(ignored)
		if ( defined ( $hash->{helper}{AUDIOINPUTSIGNAL}->{$1}) ) {
			readingsBulkUpdate($hash, "audioInputSignal", $hash->{helper}{AUDIOINPUTSIGNAL}->{$1} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: audio input signal: ". dq($1);	
		}
		else {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown audio input signal: ". dq($1);	
		}
		if ( defined ( $hash->{helper}{AUDIOINPUTFREQUENCY}->{$2}) ) {
			readingsBulkUpdate($hash, "audioInputFrequency", $hash->{helper}{AUDIOINPUTFREQUENCY}->{$2} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: audio input frequency: ". dq($2);	
		}
		else {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown audio input frequency: ". dq($2);	
		}
		readingsBulkUpdate($hash, "audioInputFormatL", $3);
		readingsBulkUpdate($hash, "audioInputFormatC", $4);
		readingsBulkUpdate($hash, "audioInputFormatR", $5);
		readingsBulkUpdate($hash, "audioInputFormatSL", $6);
		readingsBulkUpdate($hash, "audioInputFormatSR", $7);
		readingsBulkUpdate($hash, "audioInputFormatSLB", $8);
		readingsBulkUpdate($hash, "audioInputFormatS", $9);
		readingsBulkUpdate($hash, "audioInputFormatSBR", $10);
		readingsBulkUpdate($hash, "audioInputFormatLFE", $11);
		readingsBulkUpdate($hash, "audioInputFormatFHL", $12);
		readingsBulkUpdate($hash, "audioInputFormatFHR", $13);
		readingsBulkUpdate($hash, "audioInputFormatFWL", $14);
		readingsBulkUpdate($hash, "audioInputFormatFWR", $15);
		readingsBulkUpdate($hash, "audioInputFormatXL", $16);
		readingsBulkUpdate($hash, "audioInputFormatXC", $17);
		readingsBulkUpdate($hash, "audioInputFormatXR", $18);
#		readingsBulkUpdate($hash, "audioInputFormatReserved1", $19);
#		readingsBulkUpdate($hash, "audioInputFormatReserved2", $20);
#		readingsBulkUpdate($hash, "audioInputFormatReserved3", $21);
#		readingsBulkUpdate($hash, "audioInputFormatReserved4", $22);
#		readingsBulkUpdate($hash, "audioInputFormatReserved5", $23);
		readingsBulkUpdate($hash, "audioOutputFormatL", $24);
		readingsBulkUpdate($hash, "audioOutputFormatC", $25);
		readingsBulkUpdate($hash, "audioOutputFormatR", $26);
		readingsBulkUpdate($hash, "audioOutputFormatSL", $27);
		readingsBulkUpdate($hash, "audioOutputFormatSR", $28);
		readingsBulkUpdate($hash, "audioOutputFormatSBL", $29);
		readingsBulkUpdate($hash, "audioOutputFormatSB", $30);
		readingsBulkUpdate($hash, "audioOutputFormatSBR", $31);
		readingsBulkUpdate($hash, "audioOutputFormatSW", $32);
		readingsBulkUpdate($hash, "audioOutputFormatFHL", $33);
		readingsBulkUpdate($hash, "audioOutputFormatFHR", $34);
		readingsBulkUpdate($hash, "audioOutputFormatFWL", $35);
		readingsBulkUpdate($hash, "audioOutputFormatFWR", $36);
#		readingsBulkUpdate($hash, "audioOutputFormatReserved1", $37);
#		readingsBulkUpdate($hash, "audioOutputFormatReserved2", $38);
#		readingsBulkUpdate($hash, "audioOutputFormatReserved3", $39);
#		readingsBulkUpdate($hash, "audioOutputFormatReserved4", $40);
#		readingsBulkUpdate($hash, "audioOutputFormatReserved5", $41);
		
		if ( defined ( $hash->{helper}{AUDIOOUTPUTFREQUENCY}->{$42}) ) {
			readingsBulkUpdate($hash, "audioOutputFrequency", $hash->{helper}{AUDIOOUTPUTFREQUENCY}->{$42} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: audio output frequency: ". dq($42);	
		}
		else {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown audio output frequency: ". dq($42);	
		}
		readingsBulkUpdate($hash, "audioOutputBit", $43);
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: audio input bit: ". dq($43);	
		if ( defined ( $hash->{helper}{PQLSWORKING}->{$45}) ) {
			readingsBulkUpdate($hash, "pqlsWorking", $hash->{helper}{PQLSWORKING}->{$45} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: working PQLS: ". dq($45);	
		}
		else {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown working PQLS: ". dq($45);	
		}
		readingsBulkUpdate($hash, "audioAutoPhaseControlMS", $46);
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: working audio auto phase control plus (in ms): ". dq($46);	
		readingsBulkUpdate($hash, "audioAutoPhaseControlRevPhase", $47);
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: working audio auto phase control plus reverse phase: ". dq($47);	

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
			Log3 $hash,3,"PIONEERAVR $name: Main InputName: can't find Name for input $inputNr";
		}
		$hash->{helper}{main}{CURINPUTNR} = $inputNr;

#		if($inputNr != "17" and $inputNr != "44" and $inputNr != "45"){
		# clear screen information on input change...
		foreach my $key ( keys %{$hash->{helper}{CLEARONINPUTCHANGE}} ) {
			readingsBulkUpdate($hash, $hash->{helper}{CLEARONINPUTCHANGE}->{$key} , "");
			Log3 $hash,5,"PIONEERAVR $name: Main Input change ... clear screen... reading:" . $hash->{helper}{CLEARONINPUTCHANGE}->{$key};
		}
		foreach my $key ( keys %{$hash->{helper}{CLEARONINPUTCHANGE}} ) {
			readingsBulkUpdate($hash, $hash->{helper}{CLEARONINPUTCHANGE}->{$key} , "");
			Log3 $hash,5,"PIONEERAVR $name: Main Input change ... clear screen... reading:" . $hash->{helper}{CLEARONINPUTCHANGE}->{$key};
		}
		
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

	# audio input terminal
	} elsif ( $line=~ m/^SSC(\d{2})00(\d{2})$/ ) {
	
		# check for audio input terminal information
		# format: ?SSC<2 digit input function nr>00
		# response: SSC<2 digit input function nr>00
		#	 00:No Assign
		#	 01:COAX 1
		#	 02:COAX 2
		#	 03:COAX 3
		#	 04:OPT 1
		#	 05:OPT 2
		#	 06:OPT 3
		#	 10:ANALOG"
		# response: E06: inappropriate parameter (input function nr not available on that device)
		# we can not trust "E06" as it is not sure that it is the reply for the current input nr
	
		if ( $2 == 00) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "No Assign";
		} elsif ( $2 == 01) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "COAX 1";
		} elsif ( $2 == 02) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "COAX 2";
		} elsif ( $2 == 03) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "COAX 3";
		} elsif ( $2 == 04) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "OPT 1";
		} elsif ( $2 == 05) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "OPT 2";
		} elsif ( $2 == 06) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "OPT 3";
		} elsif ( $2 == 10) {
			$hash->{helper}{INPUTNAMES}->{$1}{audioTerminal} = "ANALOG";
		}
		
	# HDMI input terminal
	} elsif ( $line=~ m/^SSC(\d{2})010(\d)$/ ) {
	
		# check for hdmi input terminal information
		# format: ?SSC<2 digit input function nr>010
		# response: SSC<2 digit input function nr>010
		#	 0:No Assign
		#	 1:hdmi 1
		#	 2:hdmi 2
		#	 3:hdmi 3
		#	 4:hdmi 4
		#	 5:hdmi 5
		#	 6:hdmi 6
		#	 7:hdmi 7
		#	 8:hdmi 8
		# response: E06: inappropriate parameter (input function nr not available on that device)
		# we can not trust "E06" as it is not sure that it is the reply for the current input nr
	
		if ( $2 == 0) {
			$hash->{helper}{INPUTNAMES}->{$1}{hdmiTerminal} = "No Assign ";
		} else {
			$hash->{helper}{INPUTNAMES}->{$1}{hdmiTerminal} = "hdmi ".$2;
		}
	# component video input terminal
	} elsif ( $line=~ m/^SSC(\d{2})020(\d)$/ ) {
	
		# check for component video input terminal information
		# format: ?SSC<2 digit input function nr>020
		# response: SSC<2 digit input function nr>020
		#	 00:No Assign
		#	 01:Component 1
		#	 02:Component 2
		#	 03:Component 3
		# response: E06: inappropriate parameter (input function nr not available on that device)
		# we can not trust "E06" as it is not sure that it is the reply for the current input nr
	
		if ( $2 == 0) {
			$hash->{helper}{INPUTNAMES}->{$1}{componentTerminal} = "No Assign ";
		} else {
			$hash->{helper}{INPUTNAMES}->{$1}{componentTerminal} = "component ".$2;
		}
		
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
		
	# input level adjust
	} elsif ( $line=~ m/^ILA(\d{2})(\d{2})$/ ) {
		# 74:+12dB
		# 50: 0dB
		# 26: -12dB	
		my $inputLevelAdjust = $2/2 - 25;
		$hash->{helper}{INPUTNAMES}->{$1}{inputLevelAdjust} = $inputLevelAdjust;
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: InputLevelAdjust of InputNr: $1 is $inputLevelAdjust ";
		
	# Signal Select			
	} elsif ( substr($line,0,3) eq "SDA" ) {
		my $signalSelect = substr($line,3,1);
		if ($signalSelect == "0") {
			readingsBulkUpdate($hash, "signalSelect", "auto" );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: auto";
		} elsif ($signalSelect == "1") {
			readingsBulkUpdate($hash, "signalSelect", "analog" );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: analog";
		} elsif ($signalSelect == "2") {
			readingsBulkUpdate($hash, "signalSelect", "digital" );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: digital";
		} elsif ($signalSelect == "3") {
			readingsBulkUpdate($hash, "signalSelect", "hdmi" );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: hdmi";
		} elsif ($signalSelect == "9") {
			readingsBulkUpdate($hash, "signalSelect", "cyclic" );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: cycle";
		} else {
			readingsBulkUpdate($hash, "signalSelect", $signalSelect );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: signalSelect: ". dq($signalSelect);
		}	
	# HDMI output 
	# 0:HDMI OUT 1+2 ON
	# 1:HDMI OUT 1 ON
	# 2:HDMI OUT 2 ON
	# 3:HDMI OUT 1/2 OFF
		# Listening Mode
	} elsif ( $line =~ m/^(HO)(\d)$/ ) {
		if ( defined ( $hash->{helper}{HDMIOUT}->{$2}) ) {
			readingsBulkUpdate($hash, "hdmiOut", $hash->{helper}{HDMIOUT}->{$2} );
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: HDMI Out: ". dq($2);	
		}
		else {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: unknown hdmiOut: ". dq($2);	
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
		# Set STATE
		# devIO.pm sets hash->STATE accordingly to the connection state (opened, CONNECTED, DISCONNECTED)
		# we want that hash->STATE represents the state of the device (DISCONNECTED, off, on)
		if ($hash->{STATE} ne $state) {
			Log3 $hash,5,"PIONEERAVR $name: Update STATE from " . $hash->{STATE} . " to $state";	
			readingsBulkUpdate($hash, "state", $state );
#			$hash->{STATE} = $state;
		}
	# MCACC memory 
	} elsif ( $line =~ m/^(MC)(\d)$/ ) {
		readingsBulkUpdate($hash, "mcaccMemory", $2 );
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: MCACC memory: selected memory is: $2";	
		
	# Display updates
	} elsif ( substr($line,0,2) eq "FL" ) {
		my $display = pack("H*",substr($line,4,28));
		readingsBulkUpdate($hash, "displayPrevious", ReadingsVal($name,"display","") );
		readingsBulkUpdate($hash, "display", $display );
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Display update to: $display";	
	
	# eq 
	} elsif ( $line =~ m/^ATC([0|1])/) {
		if ($1 == "1") {
			readingsBulkUpdate($hash, "eq", "on");
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: eq is on";	
		} 
		else {
			readingsBulkUpdate($hash, "eq", "off");
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: eq is off";	
		}
		
	# standing wave
	} elsif ( $line =~ m/^ATD([0|1])/) {
		if ($1 == "1") {
			readingsBulkUpdate($hash, "standingWave", "on");
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: standingWave is on";	
		} 
		else {
			readingsBulkUpdate($hash, "standingWave", "off");
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: standingWave is off";	
		}

	# key received
	} elsif ( $line =~ m/^NXA$/) {
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Network player: Key pressed";	
	
	# screen type and screen name
	} elsif ( $line =~ m/^(GCH|GCI)(\d{2})(\d)(\d)(\d)(\d)(\d)\"(.*)\"$/ ) {
		# Format: 
		#   $2: screen type
		#     00:Massage
		#     01:List
		#     02:Playing(Play)
		#     03:Playing(Pause)
		#     04:Playing(Fwd)
		#     05:Playing(Rev)
		#     06：Playing(Stop)
		#     99:Drawing invalid

		#   $3: 0:Same hierarchy 1:Updated hierarchy (Next or Previous list)
		#   $4: Top menu key flag
		#     0:Invalidity
		#	  1:Effectiveness
		#   $5: iPod Control Key Information
		#     0:Invalidity
		#	  1:Effectiveness
		#   $6: Return Key Information
		#     0:Invalidity
		#	  1:Effectiveness
		#	$7: always 0
		
		#   $8: Screen name (UTF8) max. 128 byte
		my $screenType = $hash->{helper}{SCREENTYPES}{$2};
		
		readingsBulkUpdate($hash, "screenType", $screenType); 
		readingsBulkUpdate($hash, "screenName", $8);
		readingsBulkUpdate($hash, "screenHierarchy", $3);
		readingsBulkUpdate($hash, "screenTopMenuKey", $4);
		readingsBulkUpdate($hash, "screenIpodKey", $5);
		readingsBulkUpdate($hash, "screenReturnKey", $6);

	# Source information
	} elsif ( $line =~ m/^(GHH)(\d{2})$/ ) {
		my $sourceInfo = $hash->{helper}{SOURCEINFO}{$2};
		readingsBulkUpdate($hash, "sourceInfo", $sourceInfo );
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Screen source information: $2 $sourceInfo";	

	# total screen lines
	} elsif ( $line =~ m/^(GDH)(\d{5})(\d{5})(\d{5})$/ ) {
		readingsBulkUpdate($hash, "screenLineNumberFirst", $2+0 );
		readingsBulkUpdate($hash, "screenLineNumberLast", $3+0 );
		readingsBulkUpdate($hash, "screenLineNumbersTotal", $4+0 );
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Screen Item number of line 1(5byte): $2, Item number of last line(5byte): $3, Total number of items List(5byte): $4 ";	
		
	# Screen line numbers
	} elsif ( $line =~ m/^(GBH|GBI)(\d{2})$/ ) {
		readingsBulkUpdate($hash, "screenLineNumbers", $2+0 );
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Screen line numbers = $2";	

	# screenInformation
	} elsif ( $line =~ m/^(GEH|GEI)(\d{2})(\d)(\d{2})\"(.*)\"$/ ) {
		# Format: 
		#   $2: Line number
		#   $3: Focus (yes(1)/no(0)/greyed out(9)
		#   $4: Line data type:
		#     00:Normal（no mark type）
		#     01:Directory
		#     02:Music
		#     03:Photo
		#     04:Video
		#     05:Now Playing
		#     20:Track
		#     21:Artist
		#     22:Album
		#     23:Time
		#     24:Genre
		#     25:Chapter number
		#     26:Format
		#     27:Bit Per Sample
		#     28:Sampling Rate
		#     29:Bitrate
		#     31:Buffer
		#     32:Channel			
		#     33:Station
		#   $5: Display line information (UTF8)
		my $lineDataType = $hash->{helper}{LINEDATATYPES}{$4};
		
		# screen lines
		my $screenLine = "screenLine".$2;
		my $screenLineType = "screenLineType".$2;
		readingsBulkUpdate($hash, $screenLine, $5); 
		readingsBulkUpdate($hash, $screenLineType, $lineDataType);
		if ($3 == 1) {
		  readingsBulkUpdate($hash, "screenLineHasFocus", $2);
		}
   		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: screen line $2 ($screenLine) type: $lineDataType: " . dq($5);
		
		# for being coherent with http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
		if ($4 eq "20" or $4 eq "21" or $4 eq "22") {
  		  readingsBulkUpdate($hash, $lineDataType, $5);
  		  Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: reading update for displayDataType $lineDataType: " . dq($5);
		}

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

	# all network settings
	} elsif ( $line =~ m/^SUL(\d)(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d)(\".*\")(\d{5})$/ ) {
		#readingsBulkUpdate($hash, "macAddress", $1.":".$2.":".$3.":".$4.":".$5.":".$6);			
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: Network settings is " . $1;	
		if ($1 == 0) {
			$hash->{dhcp}= "off";
		} else {
			$hash->{dhcp}= "on";
		}
		$hash->{ipAddress}= sprintf("%d.%d.%d.%d",$2 ,$3 ,$4 ,$5);
		$hash->{netmask}= sprintf("%d.%d.%d.%d",$6,$7,$8,$9);
		$hash->{defaultGateway}= sprintf("%d.%d.%d.%d",$10,$11,$12,$13);
		$hash->{dns1}= sprintf("%d.%d.%d.%d",$14,$15,$16,$17);
		$hash->{dns2}= sprintf("%d.%d.%d.%d",$18,$19,$20,$21);
		if ($22 == 0) {
			$hash->{proxy}= "off";
		} else {
			$hash->{proxy}= "on";
			$hash->{proxyName}= $23;
			$hash->{proxyPort}= 0+$24;
		}
	# network ports 1-4
	} elsif ( $line =~ m/^SUM(\d{5})(\d{5})(\d{5})(\d{5})$/ ) {
	# network port1
		if ( $1 == 99999) {
			$hash->{networkPort1}= "disabled";
		} else {
			$hash->{networkPort1}= 0+$1;
		}
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: NetworkPort1 is " . $1;	
	# network port2
		if ( $2 == 99999) {
			$hash->{networkPort2}= "disabled";
		} else {
			$hash->{networkPort2}= 0+$2;
		}
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: NetworkPort2 is " . $2;	
	# network port3
		if ( $3 == 99999) {
			$hash->{networkPort3}= "disabled";
		} else {
			$hash->{networkPort3}= 0+$3;
		}
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: NetworkPort3 is " . $3;	
	# network port4
		if ( $4 == 99999) {
			$hash->{networkPort4}= "disabled";
		} else {
			$hash->{networkPort4}= 0+$4;
		}
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: NetworkPort4 is " . $4;	

	# MAC address
	} elsif ( $line =~ m/^SVB(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})$/ ) {
		$hash->{macAddress}= $1.":".$2.":".$3.":".$4.":".$5.":".$6;			
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: NetworkPort1 is " . $1;	
		
	# avrModel
	} elsif ( $line =~ m/^RGD<\d{3}><(.*)\/.*>$/ ) {
		$hash->{avrModel}= $1;			
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: avrModel is " . $1;	
		
	# Software version
	} elsif ( $line =~ m/^SSI\"(.*)\"$/ ) {
		$hash->{softwareVersion}= $1;
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
	# STJ1 -> on  -> Pioneer AV receiver can be switched on from standby
	# STJ0 -> off -> Pioneer AV receiver cannot be switched on from standby
	} elsif ( $line =~ m/^STJ([0|1])/) {
		if ($1 == "1") {
			$hash->{networkStandby}= "on";
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: networkStandby is on";	
		} 
		else {
			$hash->{networkStandby}= "off";
			Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: networkStandby is off";	
		}
	# commands for other zones (Volume, mute, power)
	# Zone 2 command
	} elsif ($line =~ m/^ZV(\d\d)$|^Z2MUT(\d)$|^Z2F(\d\d)$|^APR(0|1)$/) {
		$msgForZone="zone2";
		Log3 $hash, 5, "PIONEERAVR $name: received $line - message for zone2!";
	# Zone 3 command
	} elsif ($line =~ m/^YV(\d\d)$|^Z3MUT(\d)$|^Z3F(\d\d)$|^BPR(0|1)$/) {
		$msgForZone="zone3";
		Log3 $hash, 5, "PIONEERAVR $name: received $line - message for zone3!";
	# hdZone command
	} elsif ($line =~ m/^ZEA(\d\d)$|^ZEP(0|1)$/) {
		$msgForZone="hdZone";
		Log3 $hash, 5, "PIONEERAVR $name: received $line - message for hdZone!";
	} else {
		Log3 $hash, 5, "PIONEERAVR $name: received $line - don't know what this means - help me!";
	}
	
	# if PIONEERAVRZONE device exists for that zone, dispatch the command
	# otherwise try to autocreate the device
	unless($msgForZone eq "") {
		my $hashZone = $modules{PIONEERAVRZONE}{defptr}{$msgForZone};
		Log3 $hash, 5, "PIONEERAVR $name: received message for Zone: ".$msgForZone;
		if(!$hashZone) {
			my $ret = "UNDEFINED PIONEERAVRZONE_$msgForZone PIONEERAVRZONE $msgForZone";
			Log3 $name, 3, "PIONEERAVR $name: $ret, please define it";
			DoTrigger("global", $ret);
		}
		# dispatch "zone" - commands to other zones
		Dispatch($hash, $line, undef);  # dispatch result to PIONEERAVRZONEs
		Log3 $hash,5,"PIONEERAVR $name: ".dq($line) ." interpreted as: not for the Main zone -> dispatch to PIONEERAVRZONEs zone: $msgForZone";	
		$msgForZone = "";
	}
  }
  # Connection still up?
  # We received something from the Pioneer AV receiver (otherwise we would not be here) 
  # So we can assume that the connection is up.
  # We delete the current "inactivity timer" and set a new timer 
  #   to check if connection to the Pioneer AV receiver is still working in 120s

  if (AttrVal($name, "checkConnection", "enable") eq "enable" ) {
	  my $in120s = gettimeofday()+120;
	  $hash->{helper}{nextConnectionCheck} = $in120s;
	  RemoveInternalTimer($hash);
	  InternalTimer($in120s, "PIONEERAVR_checkConnection", $hash, 0);
	  Log3 $hash,5,"PIONEERAVR $name: Connection is up --- Check again in 120s --> Internal timer (120s) set";	
  } else {
	  Log3 $hash,5,"PIONEERAVR $name: Connection is up --- checkConnection is disabled";	 
  }

  readingsEndUpdate($hash, 1);
  $hash->{PARTIAL} = $buf;
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
# helper functions
#####################################
#Function to show special chars (e.g. \n\r) in logs
sub dq($) {
	my ($s)= @_;
	$s= "<nothing>" unless(defined($s));
	return "\"" . escapeLogLine($s) . "\"";
}
#####################################
#PIONEERAVR_Log() is used to show the data sent and received from/to PIONEERAVR if attr logTraffic is set
sub PIONEERAVR_Log($$$) {
  my ($hash, $loglevel, $logmsg)= @_;
  my $name= $hash->{NAME};
  $loglevel = AttrVal($name, "logTraffic", undef) unless(defined($loglevel)); 
  return unless(defined($loglevel)); 
  Log3 $hash, $loglevel , "PIONEERAVR $name (loglevel: $loglevel) logTraffic: $logmsg";
}

#####################################
sub PIONEERAVR_Reopen($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};
  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Reopen()";
  DevIo_CloseDev($hash);
  my $ret = DevIo_OpenDev($hash, 1, undef);
  if ($hash->{STATE} eq "opened") {
    Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Reopen() -> now opened";
	PIONEERAVR_statusUpdate($hash);
  }
  return $ret;
}
#####################################
# writing to the Pioneer AV receiver
# connection check 13s after writing
sub PIONEERAVR_Write($$) {
  my ($hash, $msg) = @_;
  my $name= $hash->{NAME};
  $msg= $msg."\r\n";
  my $logMsg = "SimpleWrite " . dq($msg);
  PIONEERAVR_Log($hash, undef, $logMsg);
  DevIo_SimpleWrite($hash, $msg, 0);

  if (AttrVal($name, "checkConnection", "enable") eq "enable" ) {
	my $now3 = gettimeofday()+13;
	if ($hash->{helper}{nextConnectionCheck} > $now3) { 
		$hash->{helper}{nextConnectionCheck} = $now3;
		RemoveInternalTimer($hash);
		InternalTimer($now3, "PIONEERAVR_checkConnection", $hash, 0);
	}
  }
}

######################################################################################
# PIONEERAVR_checkConnection is called if PIONEERAVR received no data for 120s
#   we send a "new line" and expect (if the connection is up) to receive "R"
#   we use DevIo_Expect() for this
#   DevIO_Expect() sends a command (just a "new line") and waits up to 2s for a reply
#   if there is a reply DevIO_Expect() returns the reply
#   if there is no reply 
#   - DevIO_Expect() tries to close and reopen the connection
#   - sends the command again
#   - waits again up to 2 seconds for a reply
#   - if there is a reply the state is set to "opened"
#   - if there is no reply the state is set to "disconnected"
#
sub PIONEERAVR_checkConnection ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{STATE}; #backup current state

  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- state: ".$hash->{STATE};
  # we use DevIo_Expect() to check if the connection to the Pioneer AV receiver still works
  # for DevIo_Expect to work state must be "opened"
  if ($state eq "on" || $state eq "off"){
	$hash->{STATE} = "opened";
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- change state temporary to: ".$hash->{STATE};
  }
  my $connState = DevIo_Expect($hash,"\r\n",2);
  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- state after DevIo_Expect(): ".$hash->{STATE}.", previous state: ".$state.", reply from DevIo_Expect: ".dq($connState);
  if ( !defined($connState)) {
	# not connected!
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- no reply after DevIo_Expect()-> reopen()";
	PIONEERAVR_Reopen($hash);
    Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- state after PIONEERAVR_Reopen(): ".$hash->{STATE}.", previous state: ".$state;
  } else {
    # we got a reply -> connection is good -> restore state
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- state: ".$hash->{STATE}." restored to: ".$state;
	$hash->{STATE} = $state;
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- connstate: ".dq($connState)." PARTIAL: ".dq($hash->{PARTIAL});
	if ($connState =~ m/^R\r?\n?$/) {
      Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection() --- connstate=R -> do nothing: ".dq($connState)." PARTIAL: ".dq($hash->{PARTIAL});
	} else {
	  $hash->{PARTIAL} .= $connState;
	}
  } 
  if (AttrVal($name, "checkConnection", "enable") eq "enable" ) {
	$hash->{helper}{nextConnectionCheck}  = gettimeofday()+120; 
	InternalTimer($hash->{helper}{nextConnectionCheck}, "PIONEERAVR_checkConnection", $hash, 0);
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection(): set internaltimer(120s)";
  } else {
	Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_checkConnection(): disabled";
  }
}
#########################################################
sub PIONEERAVR_statusUpdate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "PIONEERAVR $name: PIONEERAVR_statusUpdate()";

  foreach my $zone ( keys %{$hash->{helper}{GETS}} ) {
	foreach my $key ( keys %{$hash->{helper}{GETS}{$zone}} ) {
		PIONEERAVR_Write($hash, $hash->{helper}{GETS}->{$zone}->{$key});
		select(undef, undef, undef, 0.1);
	}
  }
  PIONEERAVR_askForInputNames($hash,5);
}
#########################################################
sub PIONEERAVR_askForInputNames($$) {
	my ($hash, $loglevel) = @_;
	my $name = $hash->{NAME};
	my $comstr = '';
	
	my $now120 = gettimeofday()+120;
	RemoveInternalTimer($hash);
	InternalTimer($now120, "PIONEERAVR_checkConnection", $hash, 0);
	
	# we ask for the inputs 1 to 59 if an input name exists (command: ?RGB00 ... ?RGB59)
	# 	and if the input is disabled (command: ?SSC0003 ... ?SSC5903)
	for ( my $i=0; $i<60; $i++ ) {
		select(undef, undef, undef, 0.1);
		$comstr = sprintf '?RGB%02d', $i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		#digital(audio) input terminal (coax, optical, analog)
		$comstr = sprintf '?SSC%02d00',$i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		#hdmi input terminal?
		$comstr = sprintf '?SSC%02d01',$i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		#component video input terminal ?
		$comstr = sprintf '?SSC%02d02',$i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		#input enabled/disabled?
		$comstr = sprintf '?SSC%02d03',$i;
		PIONEERAVR_Write($hash,$comstr);
		select(undef, undef, undef, 0.1);
		#inpuLevelAdjust (-12dB ... +12dB)
		$comstr = sprintf '?ILA%02d',$i;
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
# Default-remote control layout for PIONEERAVR
sub 
RC_layout_PioneerAVR() {
  my $ret;
  my @row;
  $row[0]="toggle:POWEROFF";
  $row[1]="volumeUp:UP,mute toggle:MUTE,inputUp:CHUP";
  $row[2]=":VOL,:blank,:PROG";
  $row[3]="volumeDown:DOWN,:blank,inputDown:CHDOWN";
  $row[4]="remoteControl audioParameter:AUDIO,remoteControl cursorUp:UP,remoteControl videoParameter:VIDEO";
  $row[5]="remoteControl cursorLeft:LEFT,remoteControl cursorEnter:ENTER,remoteControl cursorRight:RIGHT";
  $row[6]="remoteControl homeMenu:HOMEsym,remoteControl cursorDown:DOWN,remoteControl cursorReturn:RETURN";
  $row[7]="attr rc_iconpath icons/remotecontrol";
  $row[8]="attr rc_iconprefix black_btn_";

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
  This module allows to remotely control a Pioneer AV receiver (only the Main zone, other zones are controlled by the module PIONEERAVRZONE) 
  equipped with an Ethernet interface or a RS232 port. 
  It enables Fhem to 
  <ul>
    <li>switch ON/OFF the receiver</li>
    <li>adjust the volume</li>
    <li>set the input source</li>
    <li>and configure some other parameters</li>
  </ul>
  <br><br>
  This module is based on the <a href="http://www.pioneerelectronics.com/StaticFiles/PUSA/Files/Home%20Custom%20Install/Elite%20&%20Pioneer%20FY14AVR%20IP%20&%20RS-232%207-31-13.zip">Pioneer documentation</a> 
  and tested with a Pioneer AV receiver VSX-923 from <a href="http://www.pioneer.de">Pioneer</a>.
  <br><br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the module is connected via serial Port or USB.
  <br><br>
  This module tries to 
  <ul>
    <li>keep the data connection between Fhem and the Pioneer AV receiver open. If the connection is lost, this module tries to reconnect once</li>
    <li>forwards data to the module PIONEERAVRZONE to control the ZONEs of a Pioneer AV receiver</li>
  </ul>
  As long as Fhem is connected to the Pioneer AV receiver no other device (e.g. a smart phone) can connect to the Pioneer AV receiver on the same port.
  Some Pioneer AV receivers offer more than one port though. From Pioneer recommend port numbers:00023,49152-65535, Invalid port numbers:00000,08102
  <br><br>
  <a name="PIONEERAVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVR telnet &lt;IPAddress:Port&gt;</code><br><br>
    or<br><br>
    <code>define &lt;name&gt; PIONEERAVR serial &lt;SerialDevice&gt;[&lt;@BaudRate&gt;]</code>
    <br><br>

    Defines a Pioneer AV receiver device (communication interface and main zone control). The keywords <code>telnet</code> or
    <code>serial</code> are fixed. Default port on Pioneer AV receivers is 23 (according to the above mentioned Pioneer documetation) or 8102 (according to posts in the Fhem forum)<br>
	Note: PIONEERAVRZONE devices to control zone2, zone3 and/or HD-zone are autocreated on reception of the first message for those zones.<br><br>

    Examples:
    <ul>
      <code>define VSX923 PIONEERAVR telnet 192.168.0.91:23</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyS0</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyUSB0@9600</code><br>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; is one of
	<li><b>bass <-6 ... 6></b> - Bass from -6dB to + 6dB (is only available if tone = on and the ListeningMode supports it)</li>
    <li><b>channel <1 ... 9></b> - To change the tuner preset. Only available for input = 2 (Tuner)</li>
	<li><b>channelDown</b> - Changes to the next lower tuner preset. Only available for input = 2 (Tuner)</li>
	<li><b>channelStraight <A1...G9></b> - </li> To change the tuner preset with values as they are shown in the display of the Pioneer AV receiver eg. "A1". Only available for input = 2 (Tuner)
	<li><b>channelUp</b> - Changes to the next higher tuner preset. Only available for input = 2 (Tuner)</li>
	<li><b>down</b> - "arrow key down". Available for the same inputs as "play"</li>
	<li><b>enter</b> - "Enter key". Available for the same inputs as "play" </li>
	<li><b>eq <on|off></b> - Turns the equalizer on or off</li>
	<li><b>fwd</b> - Fast forward. Available for the same inputs as "play"</li>
	<li><b>hdmiOut <1+2|1|2|off></b> - Switches the HDMI output 1 and/or 2 of the Pioneer AV Receivers on or off.</li>
	<li><b>input <not on the Pioneer hardware deactivated input></b> The list of possible (i.e. not deactivated)
	inputs is read in during Fhem start and with <code>get <name> statusRequest</code>. Renamed inputs are shown with their new (renamed) name</li>
	<li><b>inputDown</b> - Select the next lower input for the Main Zone</li>
	<li><b>inputUp</b> - Select the next higher input for the Main Zone</li>
	<li><b>left</b> - "Arrow key left". Available for the same inputs as "play"</li>
	<li><b>listeningMode</b> - Sets a ListeningMode e.g. autoSourround, direct, action,...</li>
	<li><b>mcaccMemory <1...6></b> - Sets one of the 6 predefined MCACC settings for the Main Zone</li>
	<li><b>menu</b> - "Menu-key" of the remote control. Available for the same inputs as "play"</li>
	<li><b>mute <on|off|toggle></b> - Mute the Main Zone of the Pioneer AV Receiver. "mute = on" means: Zero volume</li>
	<li><b>networkStandby <on|off></b> - Turns Network standby on or off. To turn on a Pioneer AV Receiver with this module from standby, Network Standby must be "on"</li>
	<li><b>next</b> -  Available for the same inputs as "play"</li>
	<li><b>off</b> - Switch the Main Zone to standby</li>
	<li><b>on</b> - Switch the Main Zone on from standby. This can only work if "Network Standby" is "on" in the Pioneer AV Receiver. Refer to "networkStandby" above.</li>
	<li><b>pause</b> - Pause replay. Available for the same inputs as "play"</li>
	<li><b>play</b> - Starts replay for the following inputs: 
	<ul>
		<li>usbDac</li>
		<li>ipodUsb</li>
		<li>xmRadio</li>
		<li>homeMediaGallery</li>
		<li>sirius</li>
		<li>adapterPort</li>
		<li>internetRadio</li>
		<li>pandora</li>
		<li>mediaServer</li>
		<li>favorites</li>
		<li>mhl</li>
	</ul>
	</li>
	<li><b>prev</b> - Changes to the previous title. Available for the same inputs as "play".</li>
    <li><b>raw <PioneerKommando></b> - Sends the command <code>&lt;PioneerCommand&gt;</code> unchanged to the Pioneer AV receiver. A list of all available commands is available in the Pioneer documentation mentioned above</li>
	<li><b>remoteControl <attr></b> -  where <attr> is one of:
	<ul>
		<li>cursorDown</li>
		<li>cursorRight</li>
		<li>cursorLeft</li>
		<li>cursorEnter</li>
		<li>cursorReturn</li>
		<li>homeMenu</li>
		<li>statusDisplay</li>
		<li>audioParameter</li>
		<li>hdmiOutputParameter</li>
		<li>videoParameter</li>
		<li>homeMenu</li>
		Simulates the keys of the remote control. Warning: The cursorXX keys cannot change the inputs -> set <name> up ... can be used for this
	</ul>
	</li>
	<li><b>reopen</b> - Tries to reconnect Fhem to the Pioneer AV Receiver</li>
	<li><b>repeat</b> - Repeat for the following inputs: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer. Cycles between 
	  <ul>
	    <li>no repeat</li>
	    <li>repeat current title</li>
	    <li>repeat all titles</li>
	  </ul>
	</li>
	<li><b>return</b> - "Return key". Available for the same inputs as "play"</li>
	<li><b>rev</b> -  "rev key". Available for the same inputs as "play"</li>
	<li><b>right</b> - "Arrow key right". Available for the same inputs as "play"</li>
	<li><b>selectLine01 - selectLine08</b> - Available for the same inputs as "play". If there is an OSD you can select the lines directly</li>
	<li><b>shuffle</b> - Random replay. For the same inputs available as "repeat". Toggles between random on and off</li>
	<li><b>signalSelect <auto|analog|digital|hdmi|cycle></b> - Signal select function </li>
	<li><b>speakers <off|A|B|A+B></b> - Turns speaker A and or B on or off.</li>
	<li><b>standingWave <on|off></b> - Turns Standing Wave on or off for the Main Zone</li>
	<li><b>statusRequest</b> - Asks the Pioneer AV Receiver for information to update the modules readings</li>
	<li><b>stop</b> - Stops replay. Available for the same inputs as "play"</li>
	<li><b>toggle</b> - Toggle the Main Zone to/from Standby</li>
	<li><b>tone <on|bypass></b> - Turns tone on or in bypass</li>
	<li><b>treble <-6 ... 6></b> - Treble from -6dB to + 6dB (works only if tone = on and the ListeningMode permits it)</li>
	<li><b>up</b> - "Arrow key up". Available for the same inputs as "play"</li>
	<li><b>volume <0 ... 100></b> - Volume of the Main Zone in % of the maximum volume</li>
	<li><b>volumeDown</b> - Reduce the volume of the Main Zone by 0.5dB</li>
	<li><b>volumeUp</b> - Increase the volume of the Main Zone by 0.5dB</li>
	<li><b>volumeStraight<-80.5 ... 12></b> - Set the volume of the Main Zone with values from -80 ... 12 (As it is displayed on the Pioneer AV receiver</li>
	<li><a href="#setExtensions">set extensions</a> are supported (except <code>&lt;blink&gt;</code> )</li>
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
	<li><b>loadInputNames</b> - reads the names of the inputs from the Pioneer AV receiver and checks if those inputs are enabled</li>
	<li><b>audioInfo</b> - get the current audio parameters from the Pioneer AV receiver (e.g. audioInputSignal, audioInputFormatXX, audioOutputFrequency)</li>
	<li><b>display</b> - updates the reading 'display' and 'displayPrevious' with what is shown on the display of the Pioneer AV receiver</li>
	<li><b>bass</b> -  updates the reading 'bass'</li>
	<li><b>channel</b> -  </li>
	<li><b>currentListIpod</b> -  updates the readings currentAlbum, currentArtist, etc. </li>
	<li><b>currentListNetwork</b> -  </li>
	<li><b>display</b> -  </li>
	<li><b>input</b> -  </li>
	<li><b>listeningMode</b> -  </li>
	<li><b>listeningModePlaying</b> -  </li>
	<li><b>macAddress</b> -  </li>
	<li><b>avrModel</b> - get the model of the Pioneer AV receiver, eg. VSX923 </li>
	<li><b>mute</b> -  </li>
	<li><b>networkPorts</b> - get the open tcp/ip ports of the Pioneer AV Receiver</li>
	<li><b>networkSettings</b> - get the IP network settings (ip, netmask, gateway,dhcp, dns1, dns2, proxy) of the Pioneer AV Receiver </li>
	<li><b>networkStandby</b> -  </li>
	<li><b>power</b> - get the Power state of the Pioneer AV receiver </li>
	<li><b>signalSelect</b> -  </li>
	<li><b>softwareVersion</b> - get the software version of the software currently running in the Pioneer AV receiver</li>
	<li><b>speakers</b> -  </li>
	<li><b>speakerSystem</b> -  </li>
	<li><b>tone</b> -  </li>
	<li><b>tunerFrequency</b> - get the current frequency the tuner is set to</li>
	<li><b>tunerChannelNames</b> -  </li>
	<li><b>treble</b> -  </li>		
	<li><b>volume</b> -  </li>
	</ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><b>checkConnection &lt;enable|disable&gt;</b> - Enables/disables the check if the data connection to the Pioneer AV receiver is open.(Default: enable)</li>
    <li><b>logTraffic &lt;loglevel&gt;</b> - Enables logging of sent and received datagrams with the given loglevel. 
	Control characters in the logged datagrams are escaped, i.e. a double backslash is shown for a single backslash,
	\n is shown for a line feed character,...</li>
    <li><b><a href="#verbose">verbose</a></b> - 0: log es less as possible, 5: log as much as possible</li>
    <li><b>volumeLimit &lt;0 ... 100&gt;</b> - limits the volume to the given value</li> 
    <li><b>volumeLimitStraight &lt;-80 ... 12&gt;</b> - limits the volume to the given value</li> 
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
  und ist mit einem Pioneer AV Receiver VSX-923 von <a href="http://www.pioneer.de">Pioneer</a> getestet.
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
  Einige Pioneer AV Receiver bieten mehr als einen Port für die Datenverbindung an. Pioneer empfiehlt Port 23 sowie 49152-65535, "Invalid number:00000,08102".
  <br><br>
  <a name="PIONEERAVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PIONEERAVR telnet &lt;IPAddress:Port&gt;</code><br><br>
    or<br><br>
    <code>define &lt;name&gt; PIONEERAVR serial &lt;SerialDevice&gt;[&lt;@BaudRate&gt;]</code>
    <br><br>

    Definiert ein Fhem device für einen Pioneer AV Receiver (Kommunikationsschnittstelle und Steuerung der Main - Zone). Die Schlüsselwörter <code>telnet</code> bzw.
    <code>serial</code> sind fix. Der Standard Port für die Ethernet Verbindung bei Pioneer AV Receiver ist 23 
	(laut der oben angeführten Pioneer Dokumentation) - oder 8102 (laut Fhem-Forumsberichten).<br>
	Note: PIONEERAVRZONE-Devices zur Steuerung der Zone2, Zone3 und/oder HD-Zone werden per autocreate beim Eintreffen der ersten Nachricht für eine der Zonen erzeugt.
	<br><br>

    Beispiele:
    <ul>
      <code>define VSX923 PIONEERAVR telnet 192.168.0.91:23</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyS0</code><br>
      <code>define VSX923 PIONEERAVR serial /dev/ttyUSB0@9600</code><br>
    </ul>
    <br>
  </ul>

  <a name="PIONEERAVRset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;was&gt; [&lt;value&gt;]</code>
    <br><br>
	"was" ist eines von
	<li><b>bass <-6 ... 6></b> - Bass von -6dB bis + 6dB (funktioniert nur wenn tone = on und der ListeningMode es erlaubt)</li>
    <li><b>channel <1 ... 9></b> - Setzt den Tuner Preset ("gespeicherten Sender"). Nur verfügbar, wenn Input = 2 (Tuner), wie in http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV beschrieben</li>
	<li><b>channelDown</b> - Setzt den nächst niedrigeren Tuner Preset ("gespeicherten Sender"). Wenn vorher channel = 2, so wird nachher channel = 1. Nur verfügbar, wenn Input = 2 (Tuner).</li>
	<li><b>channelStraight <A1...G9></b> - </li> Setzt den Tuner Preset ("gespeicherten Sender") mit Werten, wie sie im Display des Pioneer AV Receiver angezeigt werden (z.B. A1). Nur verfügbar, wenn Input = 2 (Tuner).
	<li><b>channelUp</b> - Setzt den nächst höheren Tuner Preset ("gespeicherten Sender"). Nur verfügbar, wenn Input = 2 (Tuner).</li>
	<li><b>down</b> - "Pfeiltaste nach unten". Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>enter</b> - "Eingabe" - Entspricht der "Enter-Taste" der Fernbedienung. Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>eq <on|off></b> - Schalten den Equalizer ein oder aus.</li>
	<li><b>fwd</b> - Schnellvorlauf. Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>hdmiOut <1+2|1|2|off></b> - Schaltet die HDMI-Ausgänge 1 und/oder 2 des Pioneer AV Receivers ein bzw. aus.</li>
	<li><b>input <nicht am Pioneer AV Receiver deaktivierte Eingangsquelle></b> - Schaltet die Eingangsquelle (z.B. CD, HDMI 1,...) auf die Ausgänge der Main-Zone. Die Liste der verfügbaren (also der nicht deaktivierten)
	Eingangsquellen wird beim Start von Fhem und auch mit <code>get <name> statusRequest</code> eingelesen. Wurden die Eingänge am Pioneer AV Receiver umbenannt, wird der neue Name des Eingangs angezeigt.</li>
	<li><b>inputDown</b> - vorherige Eingangsquelle der Main Zone auswählen</li>
	<li><b>inputUp</b> - nächste Eingangsquelle der Main Zone auswählen</li>
	<li><b>left</b> - "Pfeiltaste nach links". Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>listeningMode</b> - Setzt einen ListeningMode, z.B. autoSourround, direct, action,...</li>
	<li><b>mcaccMemory <1...6></b> - Setzt einen der bis zu 6 gespeicherten MCACC Einstellungen der Main Zone</li>
	<li><b>menu</b> - "Menu-Taste" der Fernbedienung. Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>mute <on|off|toggle></b> - Stummschalten der Main Zone des Pioneer AV Receivers. "mute = on" bedeutet: stumm</li>
	<li><b>networkStandby <on|off></b> -  Schaltet Network standby ein oder aus. Um einen Pioneer AV Receiver mit diesem Modul aus dem Standby einzuschalten, muss Network Standby = on sein.</li>
	<li><b>next</b> -  für die gleichen Eingangsquellen wie "play"</li>
	<li><b>off</b> - Ausschalten der Main Zone in den Standby Modus.</li>
	<li><b>on</b> - Einschalten der Main Zone aus dem Standby Modus. Das funktioniert nur, wenn am Pioneer AV Receiver "Network Standby" "on" eingestellt ist. Siehe dazu auch "networkStandby" weiter unten.</li>
	<li><b>pause</b> - Unterbricht die Wiedergabe für die gleichen Eingangsquellen wie "play"</li>
	<li><b>play</b> - Startet die Wiedergabe für folgende Eingangsquellen: 
	<ul>
		<li>usbDac</li>
		<li>ipodUsb</li>
		<li>xmRadio</li>
		<li>homeMediaGallery</li>
		<li>sirius</li>
		<li>adapterPort</li>
		<li>internetRadio</li>
		<li>pandora</li>
		<li>mediaServer</li>
		<li>favorites</li>
		<li>mhl</li>
	</ul>
	</li>
	<li><b>prev</b> - Wechselt zum vorherigen Titel. Für die gleichen Eingangsquellen wie "play".</li>
    <li><b>raw <PioneerKommando></b> - Sendet den Befehl <code><PioneerKommando></code> unverändert an den Pioneer AV Receiver. Eine Liste der verfügbaren Pioneer Kommandos ist in dem Link zur Pioneer Dokumentation oben enthalten</li>
	<li><b>remoteControl <attr></b> -  wobei <attr> eines von folgenden sein kann:
	<ul>
		<li>cursorDown</li>
		<li>cursorRight</li>
		<li>cursorLeft</li>
		<li>cursorEnter</li>
		<li>cursorReturn</li>
		<li>homeMenu</li>
		<li>statusDisplay</li>
		<li>audioParameter</li>
		<li>hdmiOutputParameter</li>
		<li>videoParameter</li>
		<li>homeMenu</li>
		Simuliert die Tasten der Fernbedienung. Achtung: mit cursorXX können die Eingänge nicht beeinflusst werden -> set <name> up ... kann zur Steuerung der Inputs verwendet werden.
	</ul>
	</li>
	<li><b>reopen</b> - Versucht die Datenverbindung zwischen Fhem und dem Pioneer AV Receiver wieder herzustellen</li>
	<li><b>repeat</b> - Wiederholung für folgende Eingangsquellen: AdapterPort, Ipod, Favorites, InternetRadio, MediaServer. Wechselt zyklisch zwischen 
	  <ul>
	    <li>keine Wiederholung</li>
	    <li>Wiederholung des aktuellen Titels</li>
	    <li>Wiederholung aller Titel</li>
	  </ul>
	</li>
	<li><b>return</b> - "Zurück"... Entspricht der "Return-Taste" der Fernbedienung. Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>rev</b> -  "Rückwärtssuchlauf". Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>right</b> - "Pfeiltaste nach rechts". Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>selectLine01 - selectLine08</b> -  für die gleichen Eingangsquellen wie "play".Wird am Bildschirm ein Pioneer-Menu angezeigt, kann hiermit die gewünschte Zeile direkt angewählt werden</li>
	<li><b>shuffle</b> - Zufällige Wiedergabe für die gleichen Eingangsquellen wie "repeat". Wechselt zyklisch zwischen Zufallswiedergabe "ein" und "aus".</li>
	<li><b>signalSelect <auto|analog|digital|hdmi|cycle></b> - Setzt den zu verwendenden Eingang (bei Eingängen mit mehreren Anschlüssen) </li>
	<li><b>speakers <off|A|B|A+B></b> - Schaltet die Lautsprecherausgänge ein/aus.</li>
	<li><b>standingWave <on|off></b> - Schaltet Standing Wave der Main Zone aus/ein</li>
	<li><b>statusRequest</b> - Fragt Informationen vom Pioneer AV Receiver ab und aktualisiert die readings entsprechend</li>
	<li><b>stop</b> - Stoppt die Wiedergabe für die gleichen Eingangsquellen wie "play"</li>
	<li><b>toggle</b> - Ein/Ausschalten der Main Zone in/von Standby</li>
	<li><b>tone <on|bypass></b> - Schaltet die Klangsteuerung ein bzw. auf bypass</li>
	<li><b>treble <-6 ... 6></b> - Höhen (treble) von -6dB bis + 6dB (funktioniert nur wenn tone = on und der ListeningMode es erlaubt)</li>
	<li><b>up</b> - "Pfeiltaste nach oben". Für die gleichen Eingangsquellen wie "play"</li>
	<li><b>volume <0 ... 100></b> - Lautstärke der Main Zone in % der Maximallautstärke</li>
	<li><b>volumeDown</b> - Lautstärke der Main Zone um 0.5dB verringern</li>
	<li><b>volumeUp</b> - Lautstärke der Main Zone um 0.5dB erhöhen</li>
	<li><b>volumeStraight<-80.5 ... 12></b> - Direktes Einstellen der Lautstärke der Main Zone mit einem Wert, wie er am Display des Pioneer AV Receiver angezeigt wird</li>

	<li><a href="#setExtensions">set extensions</a> (ausser <code>&lt;blink&gt;</code> ) werden unterstützt</li>
   <br><br>
    Beispiel:
    <ul>
      <code>set VSX923 on</code><br>
    </ul>
    <br>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Schließt und öffnet erneut die Datenverbindung von Fhem zum Pioneer AV Receiver. 
	Kann nützlich sein, wenn die Datenverbindung nicht automatisch wieder hergestellt werden kann.
    <br><br>
  </ul>


  <a name="PIONEERAVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; raw &lt;Befehl&gt;</code>
    <br><br>
	Falls unten keine Beschreibung für das "get-Kommando" angeführt ist, siehe gleichnamiges "Set-Kommando"
	<li><b>loadInputNames</b> - liest die Namen der Eingangsquellen vom Pioneer AV Receiver	und überprüft, ob sie aktiviert sind</li>
	<li><b>audioInfo</b> - Holt die aktuellen Audio Parameter vom Pioneer AV receiver (z.B. audioInputSignal, audioInputFormatXX, audioOutputFrequency)</li>
	<li><b>display</b> - Aktualisiert das reading 'display' und 'displayPrevious' mit der aktuellen Anzeige des Displays Pioneer AV Receiver</li>
	<li><b>bass</b> - aktualisiert das reading 'bass'</li>
	<li><b>channel</b> - </li>
	<li><b>currentListIpod</b> - aktualisiert die readings currentAlbum, currentArtist, etc. </li>
	<li><b>currentListNetwork</b> - </li>
	<li><b>input</b> - </li>
	<li><b>listeningMode</b> - </li>
	<li><b>listeningModePlaying</b> - </li>
	<li><b>macAddress</b> - </li>
	<li><b>avrModel</b> - Versucht vom Pioneer AV Receiver die Modellbezeichnung (z.B. VSX923) einzulesen und im gleichnamigen reading abzuspeichern</li>
	<li><b>mute</b> - </li>
	<li><b>networkPorts</b> - Versucht vom Pioneer AV Receiver die offenen Ethernet Ports einzulesen und in den Readings networkPort1 ... networkPort4 abzuspeichern</li>
	<li><b>networkSettings</b> - Versucht vom Pioneer AV Receiver die Netzwerkparameter (IP, Gateway, Netmask, Proxy, DHCP, DNS1, DNS2) einzulesen und in Readings abzuspeichern</li>
	<li><b>networkStandby</b> - </li>
	<li><b>power</b> - Versucht vom Pioneer AV Receiver in Erfahrung zu bringen, ob die Main Zone eingeschaltet oder in Standby ist</li>
	<li><b>signalSelect</b> - </li>
	<li><b>softwareVersion</b> - Fragt den Pioneer AV Receiver nach der aktuell im Receiver verwendeten Software Version</li>
	<li><b>speakers</b> - </li>
	<li><b>speakerSystem</b> - Fragt die aktuell verwendete Lautsprecheranwendung vom Pioneer AV Receiver ab. Mögliche Werte sind z.B. "ZONE 2", "Normal(SB/FH)", "5.1ch C+Surr Bi-Amp",...</li>
	<li><b>tone</b> - </li>
	<li><b>tunerFrequency</b> - Fragt die aktuell eingestellte Frequenz des Tuners ab</li>
	<li><b>tunerChannelNames</b> - Sollten für die Tuner Presets Namen im Pioneer AV Receiver gespeichert sein, werden sie hiermit abgefragt</li>
	<li><b>treble</b> - </li>		
	<li><b>volume</b> - </li>
  </ul>
  <br><br>

  <a name="PIONEERAVRattr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
    <li><b>checkConnection &lt;enable|disable&gt;</b> - Ein-/Ausschalten der regelmäßigen Überprüfung, ob die Datenverbindung
	zum Pioneer AV Receiver funktioniert. Ist das Attribut nicht gesetzt, oder "enable" so wird regelmäßig die Verbindung überprüft.
	Mit "disable" lässt sich die regelmäßige Überprüfung abschalten.</li>
    <li><b>logTraffic &lt;loglevel&gt;</b> - Ermöglicht das Protokollieren ("Loggen") der Datenkommunikation vom/zum Pioneer AV Receiver. 
	Steuerzeichen werden angezeigt z.B. ein doppelter Rückwärts-Schrägstrich wird als einfacher Rückwärts-Schrägstrich angezeigt,
	\n wird für das Steuerzeichen "line feed" angezeigt, etc.</li>
    <li><b><a href="#verbose">verbose</a></b> - Beeinflusst die Menge an Informationen, die dieses Modul protokolliert. 0: möglichst wenig in die Fhem Logdatei schreiben, 5: möglichst viel in die Fhem Logdatei schreiben</li>
    <li><b>volumeLimit &lt;0 ... 100&gt;</b> -  beschränkt die maximale Lautstärke (in %). Selbst wenn manuell am Pioneer AV Receiver eine höher Lautstärke eingestellt wird, regelt Fhem die Lautstärke auf volumeLimit zurück.</li>
    <li><b>volumeLimitStraight &lt; -80 ... 12&gt;</b> -  beschränkt die maximale Lautstärke (Werte wie am Display des Pioneer AV Receiver angezeigt). Selbst wenn manuell am Pioneer AV Receiver eine höher Lautstärke eingestellt wird, regelt Fhem die Lautstärke auf volumeLimit zurück.</li>
  </ul>
  <br><br>
  <b>Generated Readings/Events:</b>
  	<br/><br/>
	<ul>
		<li><b>audioAutoPhaseControlMS</b> - aktuell konfigurierte Auto Phase Control in ms</li>
		<li><b>audioAutoPhaseControlRevPhase</b> - aktuell konfigurierte Auto Phase Control reverse Phase -> 1 bedeutet: reverse phase</li>
		<li><b>audioInputFormat<XXX></b> - Zeigt ob im Audio Eingangssignal der Kanal XXX vorhanden ist (1 bedeutet: ist vorhanden)</li>
		<li><b>audioInputFrequency</b> - Frequenz des Eingangssignals</li>
		<li><b>audioInputSignal</b> - Art des inputsignals (z.B. ANALOG, PCM, DTS,...)</li>
		<li><b>audioOutputFormat<XXX></b> - Zeigt ob im Audio Ausgangssignal der Kanal XXX vorhanden ist (1 bedeutet: ist vorhanden)</li>
		<li><b>audioOutputFrequency</b> - Frequenz des Ausgangssignals</li>
		<li><b>bass</b> - aktuell konfigurierte Bass-Einstellung</li>
		<li><b>channel</b> - Tuner Preset (1...9)</li>
		<li><b>channelStraight</b> - Tuner Preset wie am Display des Pioneer AV Receiver angezeigt, z.B. A2</li>
		<li><b>display</b> - Text, der aktuell im Display des Pioneer AV Receivers angezeigt wird</li>
		<li><b>displayPrevious</b> - Zuletzt im Display angezeigter Text</li>
		<li><b>eq</b> - Status des Equalizers des Pioneer AV Receivers (on|off)</li>
		<li><b>hdmiOut</b> - welche HDMI-Ausgänge sind aktiviert?</li>
		<li><b>input</b> - welcher Eingang ist ausgewählt</li>
		<li><b>listeningMode</b> - Welcher Hörmodus (Listening Mode) ist eingestellt</li>
		<li><b>listeningModePlaying</b> - Welcher Hörmodus (Listening Mode) wird aktuell verwendet</li>
		<li><b>mcaccMemory</b> - MCACC Voreinstellung</li>
		<li><b>mute</b> - Stummschaltung</li>
		<li><b>power</b> - Main Zone eingeschaltet oder in Standby?</li>
		<li><b>pqlsWorking</b> - aktuelle PQLS Einstellung</li>
		<li><b>presence</b> - Kann der Pioneer AV Receiver via Ethernet erreicht werden?</li>
		<li><b>screenHirarchy</b> - Hierarchie des aktuell angezeigten On Screen Displays (OSD)</li>
		<li><b>screenLine01...08</b> - Inhalt der Zeile 01...08 des OSD</li>
		<li><b>screenLineHasFocus</b> - Welche Zeile des OSD hat den Fokus?</li>
		<li><b>screenLineNumberFirst</b> - Lange Listen werden im OSD zu einzelnen Seiten mit je 8 Zeilen angezeigt. Die oberste Zeile im OSD repräsentiert weiche Zeile in der gesamten Liste?</li>
		<li><b>screenLineNumberLast</b> - Lange Listen werden im OSD zu einzelnen Seiten mit je 8 Zeilen angezeigt. Die unterste Zeile im OSD repräsentiert weiche Zeile in der gesamten Liste?</li>
		<li><b>screenLineNumberTotal</b> - Wie viele Zeilen hat die im OSD anzuzeigende Liste insgesamt?</li>
		<li><b>screenLineNumbers</b> - Wie viele Zeilen hat das OSD</li>
		<li><b>screenLineType01...08</b> - Welchen Typs ist die Zeile 01...08? Z.B. "directory", "Now playing", "current Artist",...</li>
		<li><b>screenName</b> - Name des OSD</li>
		<li><b>screenReturnKey</b> - Steht die "Return-Taste" in diesem OSD zur Verfügung?</li>
		<li><b>screenTopMenuKey</b> - Steht die "Menu-Taste" in diesem OSD zur Verfügung?</li>
		<li><b>screenType</b> - Typ des OSD, z.B. "message", "List", "playing(play)",...</li>
		<li><b>speakerSystem</b> - Zeigt, wie die hinteren Surround-Lautsprecheranschlüsse und die B-Lautsprecheranschlüsse verwendet werden</li>
		<li><b>speakers</b> - Welche LAutsprecheranschlässe sind aktiviert?</li>
		<li><b>standingWave</b> - Einstellung der Steuerung stark resonanter tiefer Frequenzen im Hörraum</li>
		<li><b>state</b> - Wird beim Verbindungsaufbau von Fhem mit dem Pioneer AV Receiver gesetzt. Mögliche Werte sind disconnected, innitialized, off, on, opened</li>
		<li><b>tone</b> - Ist die Klangsteuerung eingeschalten?</li>
		<li><b>treble</b> - Einstellung des Höhenreglers</li>
		<li><b>tunerFrequency</b> - Tunerfrequenz</li>
		<li><b>volume</b> - Eingestellte Lautstärke (0%-100%)</li>
		<li><b>volumeStraight</b> - Eingestellte Lautstärke, so wie sie auch am Display des Pioneer AV Receivers angezeigt wird</li>
	</ul>
	<br/><br/>
</ul>

=end html_DE
=cut
