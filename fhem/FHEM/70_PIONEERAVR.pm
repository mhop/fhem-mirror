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
# suppress the "on" command if networkStandby = "off"
#

package main;

use strict;
use warnings;
use SetExtensions;
use Time::HiRes qw(gettimeofday);
# use DevIo;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

#########################
# Forward declaration
sub PIONEERAVR_Set($@);
sub PIONEERAVR_Get($$$);
sub PIONEERAVR_Define($$);
sub PIONEERAVR_Undef($$);
sub PIONEERAVR_Read($);
sub PIONEERAVR_Write($$);
sub PIONEERAVR_Parse($$$);
sub RC_layout_PioneerAVR();
sub PIONEERAVR_RCmakenotify($$);

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

sub PIONEERAVR_Initialize($) {
    my ( $hash) = @_;

    Log3 $hash, 5, "PIONEERAVR_Initialize: Entering";

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    # Provider
    $hash->{ReadFn}      = "PIONEERAVR_Read";
    $hash->{WriteFn}     = "PIONEERAVR_Write";
    $hash->{ReadyFn}     = "PIONEERAVR_Ready";
    $hash->{Clients}     = ":PIONEERAVRZONE:";
    $hash->{ClearFn}     = "PIONEERAVR_Clear";
    $hash->{NotifyFn}    = "PIONEERAVR_Notify";

    # Normal devices
    $hash->{DefFn}   = "PIONEERAVR_Define";
    $hash->{UndefFn} = "PIONEERAVR_Undef";
    $hash->{GetFn}   = "PIONEERAVR_Get";
    $hash->{SetFn}   = "PIONEERAVR_Set";
    $hash->{AttrFn}  = "PIONEERAVR_Attr";
    $hash->{parseParams} = 1;

    no warnings 'qw';
    my @attrList = qw(
      logTraffic:0,1,2,3,4,5
      statusUpdateReconnect:enable,disable
      statusUpdateStart:enable,disable
      volumeLimitStraight
      disable:0,1
      connectionCheck:off,30,45,60,75,90,105,120
      timeout:1,2,3,4,5,7,10,15
    );
    use warnings 'qw';
    $hash->{AttrList} = join( " ", @attrList ) . " " . $readingFnAttributes;


    # remotecontrol
    $data{RC_layout}{pioneerAvr} = "RC_layout_PioneerAVR";

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        model => {
            'VSX-923' => {
                rname_E => 'energy',
                rname_P => 'consumption',
                map     => {
                    stateAV => {
                        absent => 0,
                        off    => 0,
                        muted  => 85,
                        '*'    => 140,
                    },
                },
            },
        },
    };
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

sub PIONEERAVR_Define($$) {
    my ( $hash, $a, $h ) = @_;
    my $name  = $hash->{NAME};

    Log3 $name, 5, "PIONEERAVR $name: called function PIONEERAVR_Define()";

    my $protocol = @$a[2];

    Log3 $name, 5, "PIONEERAVR $name: called function PIONEERAVR_Define()";

    if( int(@$a) != 4 || (($protocol ne "telnet") && ($protocol ne "serial"))) {
        my $msg = "Wrong syntax: define <name> PIONEERAVR telnet <ipaddress[:port]> or define <name> PIONEERAVR serial <devicename[\@baudrate]>";
        Log3 $name, 3, "PIONEERAVR $name: " . $msg;
        return $msg;
    }

    RemoveInternalTimer( $hash);
    DevIo_CloseDev( $hash);
    delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );

    # set default attributes
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        fhem 'attr ' . $name . ' stateFormat stateAV';
        fhem 'attr ' . $name
          . ' cmdIcon muteT:rc_MUTE previous:rc_PREVIOUS next:rc_NEXT play:rc_PLAY pause:rc_PAUSE stop:rc_STOP shuffleT:rc_SHUFFLE repeatT:rc_REPEAT';
        fhem 'attr ' . $name . ' webCmd volume:mute:input';
        fhem 'attr ' . $name
          . ' devStateIcon on:rc_GREEN@green:off off:rc_STOP:on absent:rc_RED:reopen playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play muted:rc_MUTE@green:muteT fast-rewind:rc_REW@green:play fast-forward:rc_FF@green:play interrupted:rc_PAUSE@yellow:play';
    }

    # $hash->{DeviceName} is needed for DevIo_OpenDev()
    $hash->{Protocol}= $protocol;
    my $devicename= @$a[3];
    $hash->{DeviceName} = $devicename;

    # connect using serial connection (old blocking style)
    if ( $hash->{Protocol} eq "serial" )
    {
        my $ret = DevIo_OpenDev( $hash, 0, undef);
        return $ret;
    }

    # connect using TCP connection (non-blocking style)
    else {
        # add missing port if required
        $hash->{DeviceName} = $hash->{DeviceName} . ":8102"
          if ( $hash->{DeviceName} !~ m/^(.+):([0-9]+)$/ );

        DevIo_OpenDev(
            $hash, 0,
            "PIONEERAVR_DevInit",
            sub() {
              my ( $hash, $err ) = @_;
              Log3 $name, 4, "PIONEERAVR $name: devName: $devicename HashDevName $hash->{DeviceName}";
            }
        );
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
    # InputNr with player functions (play,pause,...) ("13","17","18","26","27","33","38","41","44","45","48","53");       
    # Input number for usbDac, ipodUsb, xmRadio, homeMediaGallery, sirius, adapterPort, internetRadio, pandora, mediaServer, Favorites, mhl, spotify
    # Additionally this module tries to get information from the Pioneer AVR
    #  - about the input level adjust
    #  - to which connector each input is connected.
    #    There are 3 groups of connectors:
    #     - Audio connectors (possible values are: ANALOG, COAX 1...3, OPT 1...3)
    #     - Component connectors (anaolog video, possible values: COMPONENT 1...3)
    #     - HDMI connectors (possible values are hdmi 1 ... hdmi 8)
    $hash->{helper}{INPUTNAMES} = {
        "00" => {"name" => "phono",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0", "audioTerminal" => "No Assign", "componentTerminal" => "No Assign", "hdmiTerminal" => "No Assign", "inputLevelAdjust" => 1},
        "01" => {"name" => "cd",                "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "02" => {"name" => "tuner",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "03" => {"name" => "cdrTape",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "04" => {"name" => "dvd",               "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "05" => {"name" => "tvSat",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "06" => {"name" => "cblSat",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "10" => {"name" => "video1",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "12" => {"name" => "multiChIn",         "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "13" => {"name" => "usbDac",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "14" => {"name" => "video2",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "15" => {"name" => "dvrBdr",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "17" => {"name" => "iPodUsb",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "18" => {"name" => "xmRadio",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "19" => {"name" => "hdmi1",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "20" => {"name" => "hdmi2",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "21" => {"name" => "hdmi3",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "22" => {"name" => "hdmi4",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "23" => {"name" => "hdmi5",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "24" => {"name" => "hdmi6",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "25" => {"name" => "bd",                "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "26" => {"name" => "homeMediaGallery",  "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "27" => {"name" => "sirius",            "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "31" => {"name" => "hdmiCyclic",        "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "33" => {"name" => "adapterPort",       "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "34" => {"name" => "hdmi7",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "35" => {"name" => "hdmi8",             "aliasName" => "",  "enabled" => "1", "playerCommands" => "0"},
        "38" => {"name" => "internetRadio",     "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "41" => {"name" => "pandora",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "44" => {"name" => "mediaServer",       "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "45" => {"name" => "favorites",         "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "46" => {"name" => "airplay",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "48" => {"name" => "mhl",               "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "49" => {"name" => "game",              "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"},
        "53" => {"name" => "spotify",           "aliasName" => "",  "enabled" => "1", "playerCommands" => "1"}
    };
  # ----------------Human Readable command mapping table for "set" commands-----------------------
  $hash->{helper}{SETS} = {
    'main' => {
        'on'                     => 'PO',
        'off'                    => 'PF',
        'toggle'                 => 'PZ',
        'volumeUp'               => 'VU',
        'volumeDown'             => 'VD',
        'volume'                 => 'VL',
        'muteOn'                 => 'MO',
        'muteOff'                => 'MF',
        'muteToggle'             => 'MZ',
        'bassUp'                 => 'BI',
        'bassDown'               => 'BD',
        'trebleUp'               => 'TI',
        'trebleDown'             => 'TD',
        'input'                  => 'FN',
        'inputUp'                => 'FU',
        'inputDown'              => 'FD',
        'channelUp'              => 'TPI',
        'channelDown'            => 'TPD',
        '0Network'               => '00NW',
        '1Network'               => '01NW',
        '2Network'               => '02NW',
        '3Network'               => '03NW',
        '4Network'               => '04NW',
        '5Network'               => '05NW',
        '6Network'               => '06NW',
        '7Network'               => '07NW',
        '8Network'               => '08NW',
        '9Network'               => '09NW',
        'prevNetwork'            => '12NW',
        'nextNetwork'            => '13NW',
        'revNetwork'             => '14NW',
        'fwdNetwork'             => '15NW',
        'upNetwork'              => '26NW',
        'downNetwork'            => '27NW',
        'rightNetwork'           => '28NW',
        'leftNetwork'            => '29NW',
        'enterNetwork'           => '30NW',
        'returnNetwork'          => '31NW',
        'menuNetwork'            => '36NW',
        'playNetwork'            => '10NW',
        'pauseNetwork'           => '11NW',
        'stopNetwork'            => '20NW',
        'repeatNetwork'          => '34NW',
        'shuffleNetwork'         => '35NW',
        'updateScreenNetwork'    => '?GAH',
        'selectLine01Network'    => '01GFH',
        'selectLine02Network'    => '02GFH',
        'selectLine03Network'    => '03GFH',
        'selectLine04Network'    => '04GFH',
        'selectLine05Network'    => '05GFH',
        'selectLine06Network'    => '06GFH',
        'selectLine07Network'    => '07GFH',
        'selectLine08Network'    => '08GFH',
        'selectScreenPageNetwork'=> 'GGH',
        'playIpod'               => '00IP',
        'pauseIpod'              => '01IP',
        'stopIpod'               => '02IP',
        'repeatIpod'             => '07IP',
        'shuffleIpod'            => '08IP',
        'prevIpod'               => '03IP',
        'nextIpod'               => '04IP',
        'revIpod'                => '05IP',
        'fwdIpod'                => '06IP',
        'upIpod'                 => '13IP',
        'downIpod'               => '14IP',
        'rightIpod'              => '15IP',
        'leftIpod'               => '16IP',
        'enterIpod'              => '17IP',
        'returnIpod'             => '18IP',
        'menuIpod'               => '19IP',
        'updateScreenIpod'       => '?GAI',
        'selectLine01Ipod'       => '01GFI',
        'selectLine02Ipod'       => '02GFI',
        'selectLine03Ipod'       => '03GFI',
        'selectLine04Ipod'       => '04GFI',
        'selectLine05Ipod'       => '05GFI',
        'selectLine06Ipod'       => '06GFI',
        'selectLine07Ipod'       => '07GFI',
        'selectLine08Ipod'       => '08GFI',
        'selectScreenPageIpod'   => 'GGI',
        'playAdapterPort'        => '10BT',
        'pauseAdapterPort'       => '11BT',
        'stopAdapterPort'        => '12BT',
        'repeatAdapterPort'      => '17BT',
        'shuffleAdapterPort'     => '18BT',
        'prevAdapterPort'        => '13BT',
        'nextAdapterPort'        => '14BT',
        'revAdapterPort'         => '15BT',
        'fwdAdapterPort'         => '16BT',
        'upAdapterPort'          => '21BT',
        'downAdapterPort'        => '22BT',
        'rightAdapterPort'       => '23BT',
        'leftAdapterPort'        => '24BT',
        'enterAdapterPort'       => '25BT',
        'returnAdapterPort'      => '26BT',
        'menuAdapterPort'        => '27BT',
        'playMhl'                => '23MHL',
        'pauseMhl'               => '25MHL',
        'stopMhl'                => '24MHL',
        '0Mhl'                   => '07MHL',
        '1Mhl'                   => '08MHL',
        '2Mhl'                   => '09MHL',
        '3Mhl'                   => '10MHL',
        '4Mhl'                   => '11MHL',
        '5Mhl'                   => '12MHL',
        '6Mhl'                   => '13MHL',
        '7Mhl'                   => '14MHL',
        '8Mhl'                   => '15MHL',
        '9Mhl'                   => '16MHL',
        'prevMhl'                => '31MHL',
        'nextMhl'                => '30MHL',
        'revMhl'                 => '27MHL',
        'fwdMhl'                 => '28MHL',
        'upMhl'                  => '01MHL',
        'downMhl'                => '02MHL',
        'rightMhl'               => '04MHL',
        'leftMhl'                => '03MHL',
        'enterMhl'               => '17MHL',
        'returnMhl'              => '06MHL',
        'menuMhl'                => '05MHL'
    },
    'zone2' => {
        'on'                 => 'APO',
        'off'                => 'APF',
        'toggle'             => 'APZ',
        'volumeUp'           => 'ZU',
        'volumeDown'         => 'ZD',
        'muteOn'             => 'Z2MO',
        'muteOff'            => 'Z2MF',
        'muteToggle'         => 'Z2MZ',
        'inputUp'            => 'ZSFU',
        'inputDown'          => 'ZSFD'
    },
    'zone3' => {
        'on'                 => 'BPO',
        'off'                => 'BPF',
        'toggle'             => 'BPZ',
        'volumeUp'           => 'YU',
        'volumeDown'         => 'YD',
        'muteOn'             => 'Z3MO',
        'muteOff'            => 'Z3MF',
        'muteToggle'         => 'Z3MZ',
        'inputUp'            => 'ZTFU',
        'inputDown'          => 'ZTFD'
    },
    'hdZone' => {
        'on'                 => 'ZEO',
        'off'                => 'ZEF',
        'toggle'             => 'ZEZ',
        'inputUp'            => 'ZEC',
        'inputDown'          => 'ZEB'
    }
  };
  # ----------------Human Readable command mapping table for "get" commands-----------------------
  $hash->{helper}{GETS}  = {
    'main' => {
        'audioInfo'            => '?AST',
        'avrModel'             => '?RGD',
        'bass'                 => '?BA',
        'channel'              => '?PR',
        'currentListIpod'      => '?GAI',
        'currentListNetwork'   => '?GAH',
        'display'              => '?FL',
        'eq'                   => '?ATC',
        'hdmiOut'              => '?HO',
        'input'                => '?F',
        'listeningMode'        => '?S',
        'listeningModePlaying' => '?L',
        'macAddress'           => '?SVB',
        'mcaccMemory'          => '?MC',
        'mute'                 => '?M',
        'networkPort1'         => '?STM',
        'networkPort2'         => '?STN',
        'networkPort3'         => '?STO',
        'networkPort4'         => '?STP',
        'networkPorts'         => '?SUM',
        'networkSettings'      => '?SUL',
        'networkStandby'       => '?STJ',
        'power'                => '?P',
        'signalSelect'         => '?DSA',
        'softwareVersion'      => '?SSI',
        'speakers'             => '?SPK',
        'speakerSystem'        => '?SSF',
        'standingWave'         => '?ATD',
        'tone'                 => '?TO',
        'tunerFrequency'       => '?FR',
        'tunerChannelNames'    => '?TQ',
        'treble'               => '?TR',
        'videoInfo'            => '?VST',
        'volume'               => '?V'
    },
    'zone2' => {
        'bass'               => '?ZGB',
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
        "cursorUp"            => "CUP",
        "cursorDown"          => "CDN",
        "cursorRight"         => "CRI",
        "cursorLeft"          => "CLE",
        "cursorEnter"         => "CEN",
        "cursorReturn"        => "CRT",
        "statusDisplay"       => "STS",
        "audioParameter"      => "APA",
        "hdmiOutputParameter" => "HPA",
        "videoParameter"      => "VPA",
        "homeMenu"            => "HM"
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

  #Video Input Terminals
  $hash->{helper}{VIDEOINPUTTERMINAL} = {
    "0"=>"---",
    "1"=>"VIDEO",
    "2"=>"S-VIDEO",
    "3"=>"COMPONENT",
    "4"=>"HDMI",
    "5"=>"Self OSD/JPEG"
  };
  #Video resolutions
  $hash->{helper}{VIDEORESOLUTION} = {
    "00"=>"---",
    "01"=>"480/60i",
    "02"=>"576/50i",
    "03"=>"480/60p",
    "04"=>"576/50p",
    "05"=>"720/60p",
    "06"=>"720/50p",
    "07"=>"1080/60i",
    "08"=>"1080/50i",
    "09"=>"1080/60p",
    "10"=>"1080/50p",
    "11"=>"1080/24p",
    "12"=>"4Kx2K/24Hz",
    "13"=>"4Kx2K/25Hz",
    "14"=>"4Kx2K/30Hz",
    "15"=>"4Kx2K/24Hz(SMPTE)",
    "16"=>"4Kx2K/50Hz",
    "17"=>"4Kx2K/60Hz"
  };
  #Video aspect ratios
  $hash->{helper}{VIDEOASPECTRATIO} = {
    "0"=>"---",
    "1"=>"4:3",
    "2"=>"16:9",
    "3"=>"14:9"
  };
  #Video colour format
  $hash->{helper}{VIDEOCOLOURFORMAT} = {
    "0"=>"---",
    "1"=>"RGB Limit",
    "2"=>"RGB Full",
    "3"=>"YcbCr444",
    "4"=>"YcbCr422",
    "5"=>"YcbCr420"
  };
  #Video bit (VIDEOCOLOURDEPTH)
  $hash->{helper}{VIDEOCOLOURDEPTH} = {
    "0"=>"---",
    "1"=>"24bit (8bit*3)",
    "2"=>"30bit (10bit*3)",
    "3"=>"36bit (12bit*3)",
    "4"=>"48bit (16bit*3)"
  };
  #Video extended colour space
  $hash->{helper}{VIDEOCOLOURSPACE} = {
    "0"=>"---",
    "1"=>"Standard",
    "2"=>"xvYCC601",
    "3"=>"xvYCC709",
    "4"=>"sYCC",
    "5"=>"AdobeYCC601",
    "6"=>"AdobeRGB"
  };

  # for some inputs (e.g. internetRadio) the Pioneer AVR gives more information about the current program
  # The information is displayed on a (to the Pioneer avr) connected screen
  # This information is categorized - below are the categories ("dataTypes")
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

  # translation for chars (for the display)
  $hash->{helper}{CHARS} = {
    "00"=>" ",
    "01"=>" ",
    "02"=>" ",
    "03"=>" ",
    "04"=>" ",
    "05"=>"[)",
    "06"=>"(]",
    "07"=>"I",
    "08"=>"II",
    "09"=>"<",
    "0A"=>">",
    "0B"=>"_",
    "0C"=>".",
    "0D"=>".0",
    "0E"=>".5",
    "0F"=>"O",
    "10"=>"0",
    "11"=>"1",
    "12"=>"2",
    "13"=>"3",
    "14"=>"4",
    "15"=>"5",
    "16"=>"6",
    "17"=>"7",
    "18"=>"8",
    "19"=>"9",
    "1A"=>"A",
    "1B"=>"B",
    "1C"=>"C",
    "1D"=>"F",
    "1E"=>"M",
    "1F"=>"¯",
    "20"=>" ",
    "21"=>"!",
    "22"=>"\"",
    "23"=>"#",
    "24"=>"\$",
    "25"=>"%",
    "26"=>"&",
    "27"=>"\'",
    "28"=>"(",
    "29"=>")",
    "2A"=>"*",
    "2B"=>"+",
    "2C"=>",",
    "2D"=>"-",
    "2E"=>".",
    "2F"=>"/",
    "30"=>"0",
    "31"=>"1",
    "32"=>"2",
    "33"=>"3",
    "34"=>"4",
    "35"=>"5",
    "36"=>"6",
    "37"=>"7",
    "38"=>"8",
    "39"=>"9",
    "3A"=>":",
    "3B"=>";",
    "3C"=>"<",
    "3D"=>"=",
    "3E"=>">",
    "3F"=>"?",
    "40"=>"@",
    "41"=>"A",
    "42"=>"B",
    "43"=>"C",
    "44"=>"D",
    "45"=>"E",
    "46"=>"F",
    "47"=>"G",
    "48"=>"H",
    "49"=>"I",
    "4A"=>"J",
    "4B"=>"K",
    "4C"=>"L",
    "4D"=>"M",
    "4E"=>"N",
    "4F"=>"O",
    "50"=>"P",
    "51"=>"Q",
    "52"=>"R",
    "53"=>"S",
    "54"=>"T",
    "55"=>"U",
    "56"=>"V",
    "57"=>"W",
    "58"=>"X",
    "59"=>"Y",
    "5A"=>"Z",
    "5B"=>"[",
    "5C"=>"\\",
    "5D"=>"]",
    "5E"=>"^",
    "5F"=>"_",
    "60"=>"||",
    "61"=>"a",
    "62"=>"b",
    "63"=>"c",
    "64"=>"d",
    "65"=>"e",
    "66"=>"f",
    "67"=>"g",
    "68"=>"h",
    "69"=>"i",
    "6A"=>"j",
    "6B"=>"k",
    "6C"=>"l",
    "6D"=>"m",
    "6E"=>"n",
    "6F"=>"o",
    "70"=>"p",
    "71"=>"q",
    "72"=>"r",
    "73"=>"s",
    "74"=>"t",
    "75"=>"u",
    "76"=>"v",
    "77"=>"w",
    "78"=>"x",
    "79"=>"y",
    "7A"=>"z",
    "7B"=>"{",
    "7C"=>"|",
    "7D"=>"}",
    "7E"=>"~",
    "7F"=>" ",
    "80"=>"Œ",
    "81"=>"œ",
    "82"=>"?",
    "83"=>"?",
    "84"=>"p",
    "85"=>" ",
    "86"=>" ",
    "87"=>" ",
    "88"=>" ",
    "89"=>" ",
    "8A"=>" ",
    "8B"=>" ",
    "8C"=>"?",
    "8D"=>"?",
    "8E"=>"?",
    "8F"=>"?",
    "90"=>"+",
    "91"=>"?",
    "92"=>" ",
    "93"=>" ",
    "94"=>" ",
    "95"=>" ",
    "96"=>" ",
    "97"=>" ",
    "98"=>" ",
    "99"=>" ",
    "9A"=>" ",
    "9B"=>" ",
    "9C"=>" ",
    "9D"=>" ",
    "9E"=>" ",
    "9F"=>" ",
    "A0"=>" ",
    "A1"=>"¡",
    "A2"=>"¢",
    "A3"=>"£",
    "A4"=>"¤",
    "A5"=>"¥",
    "A6"=>"¦",
    "A7"=>"§",
    "A8"=>"¨",
    "A9"=>"©",
    "AA"=>"ª",
    "AB"=>"«",
    "AC"=>"¬",
    "AD"=>"-",
    "AE"=>"®",
    "AF"=>"¯",
    "B0"=>"°",
    "B1"=>"±",
    "B2"=>"²",
    "B3"=>"³",
    "B4"=>"´",
    "B5"=>"µ",
    "B6"=>"¶",
    "B7"=>"·",
    "B8"=>"¸",
    "B9"=>"¹",
    "BA"=>"º",
    "BB"=>"»",
    "BC"=>"¼",
    "BD"=>"½",
    "BE"=>"¾",
    "BF"=>"¿",
    "C0"=>"À",
    "C1"=>"Á",
    "C2"=>"Â",
    "C3"=>"Ã",
    "C4"=>"Ä",
    "C5"=>"Å",
    "C6"=>"Æ",
    "C7"=>"Ç",
    "C8"=>"È",
    "C9"=>"É",
    "CA"=>"Ê",
    "CB"=>"Ë",
    "CC"=>"Ì",
    "CD"=>"Í",
    "CE"=>"Î",
    "CF"=>"ï",
    "D0"=>"Ð",
    "D1"=>"Ñ",
    "D2"=>"Ò",
    "D3"=>"Ó",
    "D4"=>"Ô",
    "D5"=>"Õ",
    "D6"=>"Ö",
    "D7"=>"×",
    "D8"=>"Ø",
    "D9"=>"Ù",
    "DA"=>"Ú",
    "DB"=>"Û",
    "DC"=>"Ü",
    "DD"=>"Ý",
    "DE"=>"Þ",
    "DF"=>"ß",
    "E0"=>"à",
    "E1"=>"á",
    "E2"=>"â",
    "E3"=>"ã",
    "E4"=>"ä",
    "E5"=>"å",
    "E6"=>"æ",
    "E7"=>"ç",
    "E8"=>"è",
    "E9"=>"é",
    "EA"=>"ê",
    "EB"=>"ë",
    "EC"=>"ì",
    "ED"=>"í",
    "EE"=>"î",
    "EF"=>"ï",
    "F0"=>"ð",
    "F1"=>"ñ",
    "F2"=>"ò",
    "F3"=>"ó",
    "F4"=>"ô",
    "F5"=>"õ",
    "F6"=>"ö",
    "F7"=>"÷",
    "F8"=>"ø",
    "F9"=>"ù",
    "FA"=>"ú",
    "FB"=>"û",
    "FC"=>"ü",
    "FD"=>"ý",
    "FE"=>"þ",
    "FF"=>"ÿ"
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
    "20"=>"screenLineNumbersTotal",
    "21"=>"screenLineNumbers",
    "22"=>"screenType",
    "23"=>"screenName",
    "24"=>"screenHierarchy",
    "25"=>"screenTopMenuKey",
    "26"=>"screenToolsKey",
    "27"=>"screenReturnKey",
    "28"=>"playStatus",
    "29"=>"sourceInfo",
    "30"=>"currentAlbum",
    "31"=>"currentArtist",
    "32"=>"currentTitle",
    "33"=>"channel",
    "34"=>"channelName",
    "35"=>"channelStraight",
    "36"=>"tunerFrequency"  
    };

  ### initialize timer
  $hash->{helper}{nextConnectionCheck} = gettimeofday()+120;

  return undef;
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
  my ( $hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Undef() called";

  RemoveInternalTimer( $hash);

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
  DevIo_CloseDev( $hash);
  return undef;
}

#####################################
sub
PIONEERAVR_Ready($)
{
  my ( $hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Ready() called at state: ".$hash->{STATE}." reading state:".ReadingsVal( $name, "state", "disconnected" );

  if ( ReadingsVal( $name, "state", "disconnected" ) eq "disconnected" ) {

    DevIo_OpenDev(
        $hash, 1, undef,
        sub() {
            my ( $hash, $err ) = @_;
            Log3 $name, 4, "PIONEERAVR $name: $err" if ($err);
        }
    );

    return;
  }

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}


sub PIONEERAVR_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name         = $hash->{NAME};
    my $devName      = $dev->{NAME};
    my $definedZones = scalar keys %{ $modules{PIONEERAVR_ZONE}{defptr}{$name} };
    my $presence     = ReadingsVal( $name, "presence", "-" );

    return
      if ( !$dev->{CHANGED} );    # Some previous notify deleted the array.

    # work on global events related to us
    if ( $devName eq "global" ) {
        foreach my $change ( @{ $dev->{CHANGED} } ) {
            if (   $change !~ /^(\w+)\s(\w+)\s?(\w*)\s?(.*)$/
                || $2 ne $name )
            {
                return;
            }

            # DEFINED
            # MODIFIED
            elsif ( $1 eq "DEFINED" || $1 eq "MODIFIED" ) {
                Log3 $hash, 5,
                    "PIONEERAVR "
                  . $name
                  . ": processing my global event $1: $3 -> $4";

                if ( lc( ReadingsVal( $name, "state", "?" ) ) eq "opened" ) {
                    DoTrigger( $name, "CONNECTED" );
                }
                else {
                    DoTrigger( $name, "DISCONNECTED" );
                }   
            } 
            # unknown event
            else {
                Log3 $hash, 5,
                    "PIONEERAVR "
                  . $name
                  . ": WONT BE processing my global event $1: $3 -> $4";
            }
        }

        return;
    }

    # do nothing for any other device
    elsif ( $devName ne $name ) {
        return;
    }

    readingsBeginUpdate( $hash);

    foreach my $change ( @{ $dev->{CHANGED} } ) {

        # DISCONNECTED
        if ( $change eq "DISCONNECTED" ) {
            Log3 $hash, 5, "PIONEERAVR " . $name . ": processing change $change";

            # disable connectionCheck and wait
            # until DevIo reopened the connection
            RemoveInternalTimer( $hash);

            readingsBulkUpdate( $hash, "presence", "absent" )
              if ( $presence ne "absent" );

            readingsBulkUpdate( $hash, "power", "off" )
              if ( ReadingsVal( $name, "power", "on" ) ne "off" );

            # stateAV
            my $stateAV = PIONEERAVR_GetStateAV( $hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            # send to slaves
            if ( $definedZones > 1 ) {
                Log3 $name, 5,
                  "PIONEERAVR $name: Dispatching state change to slaves";
                Dispatch(
                    $hash,
                    {
                        "presence" => "absent",
                        "power"    => "off",
                    },
                    undef
                );
            }
        }

        # CONNECTED
        elsif ( $change eq "CONNECTED" ) {
            Log3 $hash, 5, "PIONEERAVR " . $name . ": processing change $change";

            readingsBulkUpdate( $hash, "presence", "present" )
              if ( $presence ne "present" );

            # stateAV
            my $stateAV = PIONEERAVR_GetStateAV( $hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            PIONEERAVR_Write( $hash, "?P\n\r?M\n\r?V\n\r\?F\n\r" );

            # send to slaves
            if ( $definedZones > 1 ) {
                Log3 $name, 5,
                  "PIONEERAVR $name: Dispatching state change to slaves";
                Dispatch(
                    $hash,
                    {
                        "presence" => "present",
                    },
                    undef
                );
            }

        }
    }

    readingsEndUpdate( $hash, 1 );
}



#####################################
sub
PIONEERAVR_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  Log3 $name, 5, "PIONEERAVR $name: PIONEER_DoInit() called";

  PIONEERAVR_Clear( $hash);

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
  DevIo_TimeoutRead( $hash, 0.1);
}

####################################
sub
PIONEERAVR_Set($@)
{
    my ($hash, $a, $h) = @_;
    my $name           = $hash->{NAME};
    my $cmd            = @$a[1];
    my $arg            = (@$a[2] ? @$a[2] : "");
    my $presence       = ReadingsVal( $name, "presence", "absent" );
    my @args           = @$a; shift @args; shift @args;
    my @setsPlayer     = ("play",
                          "pause",
                          "stop",
                          "repeat",
                          "shuffle",
                          "prev",
                          "next",
                          "rev",
                          "fwd",
                          "up",
                          "down",
                          "right",
                          "left",
                          "enter",
                          "return",
                          "menu",
                          "updateScreen",
                          "selectLine01",
                          "selectLine02",
                          "selectLine03",
                          "selectLine04",
                          "selectLine05",
                          "selectLine06",
                          "selectLine07",
                          "selectLine08",
                          "selectScreenPage" );        # available commands for certain inputs (@playerInputNr)
    my @playerInputNr  = ("13","17","18","26","27","33","38","41","44","45","48","53");  # Input number for usbDac, ipodUsb, xmRadio, homeMediaGallery, sirius, adapterPort, internetRadio, pandora, mediaServer, Favorites, mhl, spotify
    my @setsTuner      = ("channelUp",
                          "channelDown",
                          "channelStraight",
                          "channel");     # available commands for input tuner
    my @setsWithoutArg = ("off",
                          "toggle",
                          "volumeUp",
                          "volumeDown",
                          "muteOn",
                          "muteOff",
                          "muteToggle",
                          "inputUp",
                          "inputDown" ); # set commands without arguments
    my $playerCmd      = "";
    my $inputNr        = "";

    Log3 $name, 5, "PIONEERAVR $name: Processing PIONEERAVR_Set( $cmd )";
  
    return "Argument is missing" if ( int(@$a) < 1 );
    
    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent"
        && lc( $cmd ) ne "on"
        && lc( $cmd ) ne "?"
        && lc( $cmd ) ne "reopen"
        && lc( $cmd ) ne "help" );
  
    # get all input names (preferable the aliasName) of the enabled inputs for the drop down list of "set <device> input xxx"
    my @listInputNames = ();
    foreach my $key ( keys %{$hash->{helper}{INPUTNAMES}} ) {
        if (defined( $hash->{helper}{INPUTNAMES}->{$key}{enabled})) {
            if ( $hash->{helper}{INPUTNAMES}->{$key}{enabled} eq "1" ) {
                if ( $hash->{helper}{INPUTNAMES}{$key}{aliasName}) {
                    push(@listInputNames,$hash->{helper}{INPUTNAMES}{$key}{aliasName});
                } elsif ( $hash->{helper}{INPUTNAMES}{$key}{name}) {
                    push(@listInputNames,$hash->{helper}{INPUTNAMES}{$key}{name});
                }
            }
        }
    }
    
    my $inputsList=join(':', sort @listInputNames);
    readingsSingleUpdate( $hash, "inputsList", $inputsList, 0 );
 
    my $list = "reopen:noArg on:noArg off:noArg toggle:noArg input:"
        . join(',', sort @listInputNames)
        . " hdmiOut:"
        . join(',', sort values (%{$hash->{helper}{HDMIOUT}}))
        . " inputUp:noArg inputDown:noArg"
        . " channelUp:noArg channelDown:noArg channelStraight"
        #   . join(',', sort values ( $hash->{helper}{TUNERCHANNELNAMES}))
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

    if (defined( $hash->{helper}{main}{CURINPUTNR})) {
        $inputNr = $hash->{helper}{main}{CURINPUTNR};
    }
    #return "Can't find the current input - you might want to try 'get $name loadInputNames" if ($inputNr eq "");

    # some input have more set commands ...
    if ( $inputNr ~~ @playerInputNr ) {
        $list .= " play:noArg stop:noArg pause:noArg repeat:noArg shuffle:noArg prev:noArg next:noArg rev:noArg fwd:noArg up:noArg down:noArg";
        $list .= " right:noArg left:noArg enter:noArg return:noArg menu:noArg";
        $list .= " updateScreen:noArg selectLine01:noArg selectLine02:noArg selectLine03:noArg selectLine04:noArg selectLine05:noArg selectLine06:noArg selectLine07:noArg selectLine08:noArg selectScreenPage ";
    }
    
    $list .= " networkStandby:on,off";

    if ( $cmd eq "?" ) {
        return SetExtensions( $hash, $list, $name, $cmd, @args);

        # set <name> blink is part of the setextensions
        # but blink does not make sense for an PioneerAVR so we disable it here
    } elsif ( $cmd eq "blink" ) {
        return "blink does not make too much sense with an PIONEER AV receiver isn't it?";
    }

    # process set <name> command (without further argument(s))
    if(@$a == 2) {
        Log3 $name, 5, "PIONEERAVR $name: Set $cmd (no arguments)";
        # if the data connection between the PioneerAVR and Fhem is lost, we can try to reopen the data connection manually
        if( $cmd eq "reopen" ) {
            return PIONEERAVR_Reopen( $hash);
        ### Power on
        ### Command: PO
        ### according to "Elite & Pioneer FY14AVR IP & RS-232 7-31-13.xlsx" (notice) we need to send <cr> and
        ### wait 100ms before the first command is accepted by the Pioneer AV receiver
        } elsif ( $cmd  eq "on" ) {
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd -> 2x newline + 2x PO with 100ms break in between";
            my $setCmd= "";
            PIONEERAVR_Write( $hash, $setCmd);
            select(undef, undef, undef, 0.1);
            PIONEERAVR_Write( $hash, $setCmd);
            select(undef, undef, undef, 0.1);
            $setCmd= "\n\rPO";
            PIONEERAVR_Write( $hash, $setCmd);
            select(undef, undef, undef, 0.2);
            PIONEERAVR_Write( $hash, $setCmd);
            
            if (ReadingsVal($name,"networkStandby","") eq "off") {
                return "NetworkStandby for the Pioneer AV receiver is off. If Fhem should be able to turn the AV Receiver on from standby enable networkStandby on the Pioneer AV Receiver (e.g. set $name networkStandby on )!";
            } else {
                return undef;
            }
        #### simple set commands without attributes
        #### we just "translate" the human readable command to the PioneerAvr command
        #### lookup in $hash->{helper}{SETS} if the command exists and what to write to PioneerAvr
        } elsif ( $cmd  ~~ @setsWithoutArg ) {
            my $setCmd= $hash->{helper}{SETS}{main}{$cmd};
            my $v= PIONEERAVR_Write( $hash, $setCmd);
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd (setsWithoutArg): ". $cmd ." -> $setCmd";
            return undef;

        # statusRequest: execute all "get" commands to update the readings
        } elsif ( $cmd eq "statusRequest") {
            Log3 $name, 5, "PIONEERAVR $name: Set $cmd ";
            PIONEERAVR_statusUpdate( $hash);
            return undef;
            
        #### play, pause, stop, random, repeat,prev,next,rev,fwd,up,down,right,left,enter,return,menu
        #### Only available if the input is one of:
        ####    ipod, internetRadio, mediaServer, favorites, adapterPort, mhl
        #### we need to send different commands to the Pioneer AV receiver
        ####    depending on that input
        } elsif ($cmd  ~~ @setsPlayer) {
            Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (player command)";
            if ($inputNr eq "17") {
                    $playerCmd = $cmd."Ipod";

            } elsif ( $inputNr eq "33" 
                    && ( $cmd ne "updateScreen" ) 
                    && ( $cmd ne "selectLine01" ) 
                    && ( $cmd ne "selectLine02" ) 
                    && ( $cmd ne "selectLine03" ) 
                    && ( $cmd ne "selectLine04" ) 
                    && ( $cmd ne "selectLine05" ) 
                    && ( $cmd ne "selectLine06" ) 
                    && ( $cmd ne "selectLine07" ) 
                    && ( $cmd ne "selectLine08" ) ) 
            {
                $playerCmd= $cmd."AdapterPort";
            #### homeMediaGallery, sirius, internetRadio, pandora, mediaServer, favorites, spotify
            } elsif (($inputNr eq "26") ||($inputNr eq "27") || ($inputNr eq "38") || ($inputNr eq "41") || ($inputNr eq "44") || ($inputNr eq "45") || ($inputNr eq "53")) {
                $playerCmd= $cmd."Network";

            #### 'random' and 'repeat' are not available on input mhl
            } elsif (( $inputNr eq "48" ) 
                    && ( $cmd ne "repeat") 
                    && ( $cmd ne "random")
                    && ( $cmd ne "updateScreen" ) 
                    && ( $cmd ne "selectLine01" ) 
                    && ( $cmd ne "selectLine02" ) 
                    && ( $cmd ne "selectLine03" ) 
                    && ( $cmd ne "selectLine04" ) 
                    && ( $cmd ne "selectLine05" ) 
                    && ( $cmd ne "selectLine06" ) 
                    && ( $cmd ne "selectLine07" ) 
                    && ( $cmd ne "selectLine08" ) ) {
                $playerCmd= $cmd."Mhl";
            } else {
                my $err= "PIONEERAVR $name: The command $cmd for input nr. $inputNr is not possible!";
                Log3 $name, 3, $err;
                return $err;
            }
            my $setCmd= $hash->{helper}{SETS}{main}{$playerCmd};
            PIONEERAVR_Write( $hash, $setCmd);
            return undef;
        #### channelUp, channelDown
        #### Only available if the input is 02 (tuner)
        } elsif ($cmd  ~~ @setsTuner) {
            Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (tuner command)";
            if ($inputNr eq "02") {
                my $setCmd= $hash->{helper}{SETS}{main}{$cmd};
                PIONEERAVR_Write( $hash, $setCmd);
            } else {
                my $err= "PIONEERAVR $name: The tuner command $cmd for input nr. $inputNr is not possible!";
                Log3 $name, 3, $err;
                return $err;
            }
            return undef;
        }
      #### commands with argument(s)
      } elsif(@$a > 2) {
        ####Raw
        #### sends $arg to the PioneerAVR
        if($cmd eq "raw") {
            my $allArgs= join " ", @args;
            Log3 $name, 5, "PIONEERAVR $name: sending raw command ".dq($allArgs);
            PIONEERAVR_Write( $hash, $allArgs);
            return undef;

        ####Input (all available Inputs of the Pioneer AV receiver -> see 'get $name loadInputNames')
        #### according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        #### first try the aliasName (only if this fails try the default input name)
        } elsif ( $cmd eq "input" ) {
        Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
        foreach my $key ( keys %{$hash->{helper}{INPUTNAMES}} ) {
            if ( $hash->{helper}{INPUTNAMES}->{$key}{aliasName} eq $arg ) {
                PIONEERAVR_Write( $hash, sprintf "%02dFN", $key );
            } elsif ( $hash->{helper}{INPUTNAMES}->{$key}{name} eq $arg ) {
                PIONEERAVR_Write( $hash, sprintf "%02dFN", $key );
            }
        }
        return undef;

        ####hdmiOut
        } elsif ( $cmd eq "hdmiOut" ) {
        Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
        foreach my $key ( keys %{$hash->{helper}{HDMIOUT}} ) {
            if ( $hash->{helper}{LISTENINGMODES}->{$key} eq $arg ) {
                Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg)." -> found nr: ".$key." for HDMIOut ".dq($arg);
                PIONEERAVR_Write( $hash, sprintf "%dHO", $key);
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
                PIONEERAVR_Write( $hash, sprintf "%04dSR", $key);
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
          PIONEERAVR_Write( $hash, sprintf "%03dVL", $pioneerVol);
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
          PIONEERAVR_Write( $hash, sprintf "%03dVL", $pioneerVol);
          return undef;
        ####tone (on|bypass)
        } elsif ( $cmd eq "tone" ) {
        if ($arg eq "on") {
            PIONEERAVR_Write( $hash, "1TO");
        }
        elsif ($arg eq "bypass") {
            PIONEERAVR_Write( $hash, "0TO");
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
        PIONEERAVR_Write( $hash, sprintf "%02dBA", $zahl);
        return undef;
        ####treble (-6 - 6) in dB
        } elsif ( $cmd eq "treble" ) {
        Log3 $name, 5, "PIONEERAVR $name: set $cmd ".dq($arg);
        my $zahl = sprintf "%d", ($arg * (-1)) + 6;
        PIONEERAVR_Write( $hash, sprintf "%02dTR", $zahl);
        return undef;
        ####Mute (on|off|toggle)
        ####according to http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
        } elsif ( $cmd eq "mute" ) {
        if ($arg eq "on") {
            PIONEERAVR_Write( $hash, "MO");
            readingsSingleUpdate( $hash, "mute", "on", 1 );
        }
        elsif ($arg eq "off") {
            PIONEERAVR_Write( $hash, "MF");
            readingsSingleUpdate( $hash, "mute", "off", 1 );
        }
        elsif ($arg eq "toggle") {
            PIONEERAVR_Write( $hash, "MZ");
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
            PIONEERAVR_Write( $hash,$setCmd);
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
            PIONEERAVR_Write( $hash,$setCmd);
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
                PIONEERAVR_Write( $hash, "0SPK");
            } elsif ($arg eq "A") {
                PIONEERAVR_Write( $hash, "1SPK");
            } elsif ($arg eq "B") {
                PIONEERAVR_Write( $hash, "2SPK");
            } elsif ($arg eq "A+B") {
                PIONEERAVR_Write( $hash, "3SPK");
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
                PIONEERAVR_Write( $hash, "0SDA");
            } elsif ($arg eq "analog") {
                PIONEERAVR_Write( $hash, "1SDA");
            } elsif ($arg eq "digital") {
                PIONEERAVR_Write( $hash, "2SDA");
            } elsif ($arg eq "hdmi") {
                PIONEERAVR_Write( $hash, "3SDA");
            } elsif ($arg eq "cycle") {
                PIONEERAVR_Write( $hash, "9SDA");
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
              PIONEERAVR_Write( $hash, $setCmd);
              return undef;
            } else {
            my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... mcaccMemory!";
                Log3 $name, 5, $err;
                return $err;
            }

        # eq on/off/toggle
        } elsif ( $cmd eq "eq" ) {
            if ($arg eq "on") {
                PIONEERAVR_Write( $hash, "1ATC");
            }
            elsif ($arg eq "off") {
                PIONEERAVR_Write( $hash, "0ATC");
            } else {
                my $err= "PIONEERAVR $name: Error: unknown set ... eq argument: $arg !";
                Log3 $name, 3, $err;
                return $err;
            }

        # standingWave on/off/toggle
        } elsif ( $cmd eq "standingWave" ) {
            if ( $arg eq "on" ) {
                PIONEERAVR_Write( $hash, "1ATD" );
            } elsif ( $arg eq "off" ) {
                PIONEERAVR_Write( $hash, "0ATD" );
            } else {
                my $err= "PIONEERAVR $name: Error: unknown set ... standingWave argument: $arg !";
                Log3 $name, 3, $err;
                return $err;
            }

        # Network standby (on|off)
        # needs to be "on" to turn on the Pioneer AVR via this module
        } elsif ( $cmd eq "networkStandby" ) {
            if ( $arg eq "on" ) {
                PIONEERAVR_Write( $hash, "1STJ");
            }
            elsif ( $arg eq "off" ) {
                PIONEERAVR_Write( $hash, "0STJ" );
            } else {
                my $err= "PIONEERAVR $name: Error: unknown set ... networkStandby argument: $arg !";
                Log3 $name, 3, $err;
                return $err;
            }
            return undef;

        # selectScreenPage (player command) 
        } elsif ($cmd  eq "selectScreenPage") {
            Log3 $name, 5, "PIONEERAVR $name: set $cmd for inputNr: $inputNr (player command) argument: $arg !";
            if ($inputNr eq "17") {
                    my $setCmd    = sprintf "%05dGGI", $arg;
                    PIONEERAVR_Write( $hash, $setCmd);
                    return undef;                   

            #### homeMediaGallery, sirius, internetRadio, pandora, mediaServer, favorites, spotify
            } elsif ( ( $inputNr eq "26")  
                    || ( $inputNr eq "27" )
                    || ( $inputNr eq "38" )
                    || ( $inputNr eq "41" )
                    || ( $inputNr eq "44" )
                    || ( $inputNr eq "45" )
                    || ( $inputNr eq "53" ) ) 
            {
                my $setCmd = sprintf "%05dGGH", $arg;
                PIONEERAVR_Write( $hash, $setCmd);
                return undef;                   
            }
            
        ####remoteControl
        } elsif ( $cmd eq "remoteControl" ) {
            Log3 $name, 5, "PIONEERAVR $name: set $cmd $arg";
            if (exists $hash->{helper}{REMOTECONTROL}{$arg}) {
                my $setCmd= $hash->{helper}{REMOTECONTROL}{$arg};
                my $v= PIONEERAVR_Write( $hash, $setCmd);
            } else {
                my $err= "PIONEERAVR $name: Error: unknown argument $arg in set ... remoteControl!";
                Log3 $name, 5, $err;
                return $err;
            }
            return undef;
        } else {
            return SetExtensions( $hash, $list, $name, $cmd, @args);
        }
    } else {
        return SetExtensions( $hash, $list, $name, $cmd, @args);
    }
}
#####################################
sub PIONEERAVR_Get($$$) {
    my ( $hash, $a, $h )  = @_;
    my $name             = $hash->{NAME};
    my $cmd              = @$a[1];
    my $presence         = ReadingsVal( $name, "presence", "absent" );

    Log3 $name, 5, "PIONEERAVR $name: called function PIONEERAVR_AVR_Get()";

    return "get $name needs at least one parameter" if ( int(@$a) < 1 );
      
    # readings
    return $hash->{READINGS}{ @$a[1] }{VAL}
      if ( defined( $hash->{READINGS}{ @$a[1] } ) );

    return "Device is offline and cannot be controlled at that stage."
      if ( $presence eq "absent" );

    ####loadInputNames
    if ( $cmd eq "loadInputNames" ) {
        Log3 $name, 5, "PIONEERAVR $name: processing get loadInputNames";
        PIONEERAVR_askForInputNames( $hash, 5);
        return "updating input names - this may take up to one minute.";

    } elsif ( !defined( $hash->{helper}{GETS}{main}{$cmd})) {
        my $gets= "";
        foreach my $key ( keys %{$hash->{helper}{GETS}{main}} ) {
            $gets.= $key.":noArg ";
            }
        return "$name error: unknown argument $cmd, choose one of loadInputNames:noArg " . $gets;
        ####get commands for the main zone without arguments
        #### Fhem commands are translated to PioneerAVR commands as defined in PIONEERAVR_Define -> {helper}{GETS}{main}
    } elsif ( defined( $hash->{helper}{GETS}{main}{$cmd} ) ) {
        my $pioneerCmd = $hash->{helper}{GETS}{main}{$cmd};
        my $v          = PIONEERAVR_Write( $hash, $pioneerCmd);
        return "updating $cmd .";
    }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
# PIONEERAVR_Read() makes sure, that a message is complete and correct,
# and calls the global Dispatch() with one message if this message is not for the main zone
# as the main zone is handled here
sub PIONEERAVR_Read($)
{
    my ( $hash)     = @_;
    my $name       = $hash->{NAME};
    my $state      = '';
    my $msgForZone = "";
    my $buf        = '';

    #include previous partial message
    if ( defined( $hash->{PARTIAL} ) && $hash->{PARTIAL} ) {
        $buf = $hash->{PARTIAL} . DevIo_SimpleRead( $hash);
    } else {
        $buf = DevIo_SimpleRead( $hash);
    }
    return if(!defined($buf));
  
    my $logMsg = "Spontaneously received " . dq($buf);
    PIONEERAVR_Log( $hash, undef, $logMsg);

    # Connection still up!
    # We received something from the Pioneer AV receiver (otherwise we would not be here)
    # So we can assume that the connection is up.
    # We delete the current "inactivity timer" and set a new timer
    #   to check if the connection to the Pioneer AV receiver is still working in 120s

    # reset connectionCheck timer
    my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
    RemoveInternalTimer( $hash, "PIONEERAVR_connectionCheck" );
    if ( $checkInterval ne "off" ) {
        my $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextConnectionCheck} = $next;
        InternalTimer( $next, "PIONEERAVR_connectionCheck", $hash, 0 );
        Log3 $hash, 5, "PIONEERAVR $name: Connection is up --- Check again in $checkInterval s --> Internal timer set";
    } else {
        Log3 $hash, 5, "PIONEERAVR $name: Connection is up --- checkConnection is disabled";
    }
  
  # $buf can contain more than one line of information
  # the lines are separated by "\r\n"
  # if the information in the line is not for the main zone it is dispatched to
  #    all listening modules otherwise we process it here
  readingsBeginUpdate( $hash);
  
    while($buf =~ m/^(.*?)\r\n(.*)\Z/s ) {
        my $line = $1;
        $buf = $2;
        Log3 $name, 5, "PIONEERAVR $name: processing ". dq( $line ) ." received from PIONEERAVR";
        Log3 $name, 5, "PIONEERAVR $name: line to do soon: " . dq($buf) unless ($buf eq "");
        if ( ( $line eq "R" ) || ( $line eq "" ) ) {
            Log3 $hash, 5, "PIONEERAVR $name: Supressing received " . dq( $line );

        # Main zone volume
        } elsif ( substr($line,0,3) eq "VOL" ) {
            my $volume    = substr( $line,3,3 );
            my $volume_st = $volume/2 - 80.5;
            my $volume_vl = $volume/1.85;
            readingsBulkUpdate( $hash, "volumeStraight", $volume_st);
            readingsBulkUpdate( $hash, "volume", sprintf "%d", $volume_vl);
            Log3 $name, 5, "PIONEERAVR $name: ". dq( $line ) ." interpreted as: Main Zone - New volume = ".$volume . " (raw volume data).";
        # correct volume if it is over the limit
            if ( AttrVal( $name, "volumeLimitStraight", 12 ) < $volume_st or AttrVal( $name, "volumeLimit", 100 ) < $volume_vl ) {
                my $limit_st  = AttrVal( $name, "volumeLimitStraight", 12 );
                my $limit_vl  = AttrVal( $name, "volumeLimit", 100 );
                $limit_st      = $limit_vl*0.92-80 if ($limit_vl*0.92-80 < $limit_st);
                my $pioneerVol = ( 80.5 + $limit_st )*2;
                PIONEERAVR_Write( $hash, sprintf "%03dVL", $pioneerVol);
            }
        # Main zone tone (0 = bypass, 1 = on)
        } elsif ( $line =~ m/^TO([0|1])$/) {
            if ($1 == "1") {
                readingsBulkUpdate( $hash, "tone", "on" );
                Log3 $name, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Main Zone - tone on ";
            }
            else {
                readingsBulkUpdate( $hash, "tone", "bypass" );
                Log3 $name, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Main Zone - tone bypass ";
            }
        # Main zone bass (-6 to +6 dB)
        # works only if tone=on
        } elsif ( $line =~ m/^BA(\d\d)$/ ) {
            readingsBulkUpdate( $hash, "bass", ( $1 *(-1) ) + 6 );
            Log3 $name, 5, "PIONEERAVR $name: ". dq( $line ) ." interpreted as: Main Zone - New bass = ".$1 . " (raw bass data).";

        # Main zone treble (-6 to +6 dB)
        # works only if tone=on
        } elsif ( $line =~ m/^TR(\d\d)$/ ) {
            readingsBulkUpdate( $hash, "treble", ( $1 *(-1) ) + 6 );
            Log3 $name, 5, "PIONEERAVR $name: ". dq( $line ) ." interpreted as: Main Zone - New treble = ".$1 . " (raw treble data).";

        # Main zone Mute
        } elsif ( substr( $line,0,3 ) eq "MUT" ) {
            my $mute = substr( $line, 3, 1 );
            if ($mute == "1") {
                readingsBulkUpdate( $hash, "mute", "off" );
                Log3 $name, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Main Zone - Mute off ";
            }
            else {
                readingsBulkUpdate( $hash, "mute", "on" );
                Log3 $name, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Main Zone - Mute on ";
            }

        } elsif ( $line =~ m/^AST(\d{2})(\d{2})(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d*)$/ ) {
            # Audio information parameters
            #  data1-data2:Audio Input Signal
            #  data3-data4:Audio Input Frequency
            #  data5-data20 (for some models data5-data25):Audio Input Channel Format
            if ( defined ( $hash->{helper}{AUDIOINPUTSIGNAL}->{$1} ) ) {
                readingsBulkUpdate( $hash, "audioInputSignal", $hash->{helper}{AUDIOINPUTSIGNAL}->{$1} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: audio input signal: ". dq( $1 );
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown audio input signal: ". dq( $1 );
            }
            if ( defined ( $hash->{helper}{AUDIOINPUTFREQUENCY}->{$2}) ) {
                readingsBulkUpdate( $hash, "audioInputFrequency", $hash->{helper}{AUDIOINPUTFREQUENCY}->{$2} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: audio input frequency: ". dq( $2 );
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown audio input frequency: ". dq( $2 );
            }
            readingsBulkUpdate( $hash, "audioInputFormatL", $3 );
            readingsBulkUpdate( $hash, "audioInputFormatC", $4 );
            readingsBulkUpdate( $hash, "audioInputFormatR", $5 );
            readingsBulkUpdate( $hash, "audioInputFormatSL", $6 );
            readingsBulkUpdate( $hash, "audioInputFormatSR", $7 );
            readingsBulkUpdate( $hash, "audioInputFormatSLB", $8 );
            readingsBulkUpdate( $hash, "audioInputFormatS", $9 );
            readingsBulkUpdate( $hash, "audioInputFormatSBR", $10 );
            readingsBulkUpdate( $hash, "audioInputFormatLFE", $11 );
            readingsBulkUpdate( $hash, "audioInputFormatFHL", $12 );
            readingsBulkUpdate( $hash, "audioInputFormatFHR", $13 );
            readingsBulkUpdate( $hash, "audioInputFormatFWL", $14 );
            readingsBulkUpdate( $hash, "audioInputFormatFWR", $15 );
            readingsBulkUpdate( $hash, "audioInputFormatXL", $16 );
            readingsBulkUpdate( $hash, "audioInputFormatXC", $17 );
            readingsBulkUpdate( $hash, "audioInputFormatXR", $18 );
            if ( $19=~ m/^(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d)(\d{2})(\d{2})(\d{4})(\d)(\d{2})(\d)$/ ) {
            #  Some Pioneer AVR models (e.g. VSX-921) return less then 55 data bytes - the first 20 bytes can still be used
            #  here are the bytes 21-55 processed ... e.g. for VSX-923
            #  data26-data43:Audio Output Channel
            #  data44-data45:Audio Output Frequency
            #  data46-data47:Audio Output bit
            #  data48-data51:Reserved
            #  data52:Working PQLS
            #  data53-data54:Working Auto Phase Control Plus (in ms)(ignored)
            #  data55:Working Auto Phase Control Plus (Reverse Phase) (0... no revers phase, 1...reverse phase)
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." AST with 55 data bytes ";

                #readingsBulkUpdate( $hash, "audioInputFormatReserved1", $1);
                #readingsBulkUpdate( $hash, "audioInputFormatReserved2", $2);
                #readingsBulkUpdate( $hash, "audioInputFormatReserved3", $3);
                #readingsBulkUpdate( $hash, "audioInputFormatReserved4", $4);
                #readingsBulkUpdate( $hash, "audioInputFormatReserved5", $5);
                readingsBulkUpdate( $hash, "audioOutputFormatL", $6 );
                readingsBulkUpdate( $hash, "audioOutputFormatC", $7 );
                readingsBulkUpdate( $hash, "audioOutputFormatR", $8 );
                readingsBulkUpdate( $hash, "audioOutputFormatSL", $9 );
                readingsBulkUpdate( $hash, "audioOutputFormatSR", $10 );
                readingsBulkUpdate( $hash, "audioOutputFormatSBL", $11 );
                readingsBulkUpdate( $hash, "audioOutputFormatSB", $12 );
                readingsBulkUpdate( $hash, "audioOutputFormatSBR", $13 );
                readingsBulkUpdate( $hash, "audioOutputFormatSW", $14 );
                readingsBulkUpdate( $hash, "audioOutputFormatFHL", $15);
                readingsBulkUpdate( $hash, "audioOutputFormatFHR", $16 );
                readingsBulkUpdate( $hash, "audioOutputFormatFWL", $17 );
                readingsBulkUpdate( $hash, "audioOutputFormatFWR", $18 );
        #       readingsBulkUpdate( $hash, "audioOutputFormatReserved1", $19);
        #       readingsBulkUpdate( $hash, "audioOutputFormatReserved2", $20);
        #       readingsBulkUpdate( $hash, "audioOutputFormatReserved3", $21);
        #       readingsBulkUpdate( $hash, "audioOutputFormatReserved4", $22);
        #       readingsBulkUpdate( $hash, "audioOutputFormatReserved5", $23);

                if ( defined ( $hash->{helper}{AUDIOOUTPUTFREQUENCY}->{$24}) ) {
                    readingsBulkUpdate( $hash, "audioOutputFrequency", $hash->{helper}{AUDIOOUTPUTFREQUENCY}->{$24} );
                    Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: audio output frequency: ". dq( $24 );
                } else {
                    Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown audio output frequency: ". dq( $24 );
                }
                readingsBulkUpdate( $hash, "audioOutputBit", $25 );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: audio input bit: ". dq( $25 );
                if ( defined ( $hash->{helper}{PQLSWORKING}->{$27} ) ) {
                    readingsBulkUpdate( $hash, "pqlsWorking", $hash->{helper}{PQLSWORKING}->{$27} );
                    Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: working PQLS: ". dq( $27 );
                } else {
                    Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown working PQLS: ". dq( $27 );
                }
                readingsBulkUpdate( $hash, "audioAutoPhaseControlMS", $28 );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: working audio auto phase control plus (in ms): ". dq( $28 );
                readingsBulkUpdate( $hash, "audioAutoPhaseControlRevPhase", $29);
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: working audio auto phase control plus reverse phase: ". dq( $29 );
            } else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." AST with NOT 55 data bytes ... some audio parameters like audioOutputFormatXXX could not be set";
            }
            # Main zone Input
        } elsif ( $line =~ m/^FN(\d\d)$/ ) {
            my $inputNr = $1;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Main Zone - Input is set to inputNr: $inputNr ";
            if ( $hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} ) {
                readingsBulkUpdate( $hash, "input", $hash->{helper}{INPUTNAMES}{$inputNr}{aliasName} );
                Log3 $hash, 5, "PIONEERAVR $name: Main Input aliasName for input $inputNr is " . $hash->{helper}{INPUTNAMES}{$inputNr}{aliasName};
            } elsif ( defined ( $hash->{helper}{INPUTNAMES}{$inputNr}{name}) ) {
                readingsBulkUpdate( $hash, "input", $hash->{helper}{INPUTNAMES}{$inputNr}{name} );
                Log3 $hash, 5, "PIONEERAVR $name: Main Input Name for input $inputNr is " . $hash->{helper}{INPUTNAMES}{$inputNr}{name};
            } else {
                readingsBulkUpdate( $hash, "input", $line );
                Log3 $hash, 3, "PIONEERAVR $name: Main InputName: can't find Name for input $inputNr";
            }
            $hash->{helper}{main}{CURINPUTNR} = $inputNr;

    #       if($inputNr != "17" and $inputNr != "44" and $inputNr != "45"){
            # clear screen information on input change...
            foreach my $key ( keys %{$hash->{helper}{CLEARONINPUTCHANGE}} ) {
                readingsBulkUpdate( $hash, $hash->{helper}{CLEARONINPUTCHANGE}->{$key} , "" );
                Log3 $hash, 5, "PIONEERAVR $name: Main Input change ... clear screen... reading:" . $hash->{helper}{CLEARONINPUTCHANGE}->{$key};
            }
            foreach my $key ( keys %{$hash->{helper}{CLEARONINPUTCHANGE}} ) {
                readingsBulkUpdate( $hash, $hash->{helper}{CLEARONINPUTCHANGE}->{$key} , "" );
                Log3 $hash, 5, "PIONEERAVR $name: Main Input change ... clear screen... reading:" . $hash->{helper}{CLEARONINPUTCHANGE}->{$key};
            }

            # input names
            # RGBXXY(14char)
            # XX -> input number
            # Y -> 1: aliasName; 0: Standard (predefined) name
            # 14char -> name of the input
        } elsif ( $line=~ m/^RGB(\d\d)(\d)(.*)/ ) {
            my $inputNr = $1;
            my $isAlias = $2; #1: aliasName; 0: Standard (predefined) name
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Name for InputNr: $inputNr is ".dq( $3 );
            # remove non alnum
            $line =~ s/[^a-zA-Z 0-9]/ /g;
            # uc first
            $line =~ s/([\w']+)/\u\L$1/g;
            # remove whitespace
            $line =~ s/\s//g;
            # lc first
            if ( $isAlias ) {
                $hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} = lcfirst( substr( $line,6 ) );
            } else {
                $hash->{helper}{INPUTNAMES}->{$inputNr}{name} = lcfirst( substr( $line,6 ) );
            }
            
            $hash->{helper}{INPUTNAMES}->{$inputNr}{enabled} = 1 
                if ( !defined( $hash->{helper}{INPUTNAMES}->{$inputNr}{enabled} ) );
            
            $hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName} = "" 
                if ( !defined( $hash->{helper}{INPUTNAMES}->{$inputNr}{aliasName}));
            Log3 $hash, 5, "$name: Input name for input $inputNr is " . lcfirst( substr( $line,6 ) );

        # audio input terminal
        } elsif ( $line=~ m/^SSC(\d{2})00(\d{2})$/ ) {

            # check for audio input terminal information
            # format: ?SSC<2 digit input function nr>00
            # response: SSC<2 digit input function nr>00
            #    00:No Assign
            #    01:COAX 1
            #    02:COAX 2
            #    03:COAX 3
            #    04:OPT 1
            #    05:OPT 2
            #    06:OPT 3
            #    10:ANALOG"
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
            #    0:No Assign
            #    1:hdmi 1
            #    2:hdmi 2
            #    3:hdmi 3
            #    4:hdmi 4
            #    5:hdmi 5
            #    6:hdmi 6
            #    7:hdmi 7
            #    8:hdmi 8
            # response: E06: inappropriate parameter (input function nr not available on that device)
            # we can not trust "E06" as it is not sure that it is the reply for the current input nr

            if ( $2 == 0 ) {
                $hash->{helper}{INPUTNAMES}->{$1}{hdmiTerminal} = "No Assign ";
            } else {
                $hash->{helper}{INPUTNAMES}->{$1}{hdmiTerminal} = "hdmi ".$2;
            }
        # component video input terminal
        } elsif ( $line=~ m/^SSC(\d{2})020(\d)$/ ) {

            # check for component video input terminal information
            # format: ?SSC<2 digit input function nr>020
            # response: SSC<2 digit input function nr>020
            #    00:No Assign
            #    01:Component 1
            #    02:Component 2
            #    03:Component 3
            # response: E06: inappropriate parameter (input function nr not available on that device)
            # we can not trust "E06" as it is not sure that it is the reply for the current input nr

            if ( $2 == 0 ) {
                $hash->{helper}{INPUTNAMES}->{$1}{componentTerminal} = "No Assign ";
            } else {
                $hash->{helper}{INPUTNAMES}->{$1}{componentTerminal} = "component ".$2;
            }

        # input enabled
        } elsif ( $line=~ m/^SSC(\d\d)030(1|0)$/ ) {

            #       select(undef, undef, undef, 0.001);
            # check for input skip information
            # format: ?SSC<2 digit input function nr>03
            # response: SSC<2 digit input function nr>0300: use
            # response: SSC<2 digit input function nr>0301: skip
            # response: E06: inappropriate parameter (input function nr not available on that device)
            # we can not trust "E06" as it is not sure that it is the reply for the current input nr

            if ( $2 == 1 ) {
                $hash->{helper}{INPUTNAMES}->{$1}{enabled} = 0;
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: InputNr: $1 is disabled";
            } elsif ( $2 == 0) {
                $hash->{helper}{INPUTNAMES}->{$1}{enabled} = 1;
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: InputNr: $1 is enabled";
            }

        # input level adjust
        } elsif ( $line=~ m/^ILA(\d{2})(\d{2})$/ ) {
            # 74:+12dB
            # 50: 0dB
            # 26: -12dB
            my $inputLevelAdjust = $2/2 - 25;
            $hash->{helper}{INPUTNAMES}->{$1}{inputLevelAdjust} = $inputLevelAdjust;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: InputLevelAdjust of InputNr: $1 is $inputLevelAdjust ";

        # Signal Select
        } elsif ( substr( $line, 0, 3 ) eq "SDA" ) {
            my $signalSelect = substr( $line,3,1 );
            if ( $signalSelect == "0" ) {
                readingsBulkUpdate( $hash, "signalSelect", "auto" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: auto";
            } elsif ( $signalSelect == "1" ) {
                readingsBulkUpdate( $hash, "signalSelect", "analog" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: analog";
            } elsif ( $signalSelect == "2" ) {
                readingsBulkUpdate( $hash, "signalSelect", "digital" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: digital";
            } elsif ( $signalSelect == "3" ) {
                readingsBulkUpdate( $hash, "signalSelect", "hdmi" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: hdmi";
            } elsif ( $signalSelect == "9" ) {
                readingsBulkUpdate( $hash, "signalSelect", "cyclic" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: cycle";
            } else {
                readingsBulkUpdate( $hash, "signalSelect", $signalSelect );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: signalSelect: ". dq( $signalSelect );
            }
        # HDMI output
        # 0:HDMI OUT 1+2 ON
        # 1:HDMI OUT 1 ON
        # 2:HDMI OUT 2 ON
        # 3:HDMI OUT 1/2 OFF
            # Listening Mode
        } elsif ( $line =~ m/^(HO)(\d)$/ ) {
            if ( defined ( $hash->{helper}{HDMIOUT}->{$2} ) ) {
                readingsBulkUpdate( $hash, "hdmiOut", $hash->{helper}{HDMIOUT}->{$2} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: HDMI Out: ". dq( $2 );
            } else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown hdmiOut: ". dq( $2 );
            }

        } elsif ( $line=~ m/^VST(\d)(\d{2})(\d)(\d)(\d)(\d)(\d{2})(\d)(\d)(\d)(\d)(\d{2})(\d)(\d)(\d{2})(\d)(\d)(\d*)$/ ) {
            # Video information parameters
            #  data1:Video Input Signal
            #  data2-data3:Video Input Resolution
            #  data4:Video Input aspect ratio
            #  data5:Video input colour format (HDMI only)
            #  data6:Video input bit rate (HDMI only) VIDEOCOLOURDEPTH
            #  data7:Input extend color space(HDMI only)
            #  data8-9:Output Resolution
            #  data10:Output aspect
            #  data11:Output color format(HDMI only)
            #  data12:Output bit(HDMI only)
            #  data13:Output extend color space(HDMI only)
            #  data14-15:HDMI 1 Monitor Recommend Resolution Information
            #  data16:HDMI 1 Monitor DeepColor
            #  data17-21:HDMI 1 Monitor Extend Color Space
            #  data22-23:HDMI 2 Monitor Recommend Resolution Information
            #  data24:HDMI 2 Monitor DeepColor
            #  data25-29:HDMI 2 Monitor Extend Color Space
            #  data30-49: HDMI3 & HDMI4 (not used)
            if ( defined ( $hash->{helper}{VIDEOINPUTTERMINAL}->{$1}) ) {
                readingsBulkUpdate( $hash, "videoInputTerminal", $hash->{helper}{VIDEOINPUTTERMINAL}->{$1} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input terminal: ". dq($1);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown video input terminal: ". dq($1);
            }
            
            if ( defined ( $hash->{helper}{VIDEORESOLUTION}->{$2}) ) {
                readingsBulkUpdate( $hash, "videoInputResolution", $hash->{helper}{VIDEORESOLUTION}->{$2} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input resolution: ". dq($2);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input resolution: ". dq($2);
            }
            
            if ( defined ( $hash->{helper}{VIDEOASPECTRATIO}->{$3}) ) {
                readingsBulkUpdate( $hash, "videoInputAspectRatio", $hash->{helper}{VIDEOASPECTRATIO}->{$3} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input aspect ratio: ". dq($3);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input aspect ratio: ". dq($3);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURFORMAT}->{$4}) ) {
                readingsBulkUpdate( $hash, "videoInputColourFormat", $hash->{helper}{VIDEOCOLOURFORMAT}->{$4} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour format: ". dq($4);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour format: ". dq($4);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURDEPTH}->{$5}) ) {
                readingsBulkUpdate( $hash, "videoInputColourDepth", $hash->{helper}{VIDEOCOLOURDEPTH}->{$5} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour depth: ". dq($5);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour depth: ". dq($5);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURSPACE}->{$6}) ) {
                readingsBulkUpdate( $hash, "videoInputColourSpace", $hash->{helper}{VIDEOCOLOURSPACE}->{$6} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour space: ". dq($6);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video input colour space: ". dq($6);
            }
            
            if ( defined ( $hash->{helper}{VIDEORESOLUTION}->{$7}) ) {
                readingsBulkUpdate( $hash, "videoOutputResolution", $hash->{helper}{VIDEORESOLUTION}->{$7} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output resolution: ". dq($7);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output resolution: ". dq($7);
            }
            
            if ( defined ( $hash->{helper}{VIDEOASPECTRATIO}->{$8}) ) {
                readingsBulkUpdate( $hash, "videoOutputAspectRatio", $hash->{helper}{VIDEOASPECTRATIO}->{$8} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output aspect ratio: ". dq($8);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output aspect ratio: ". dq($8);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURFORMAT}->{$9}) ) {
                readingsBulkUpdate( $hash, "videoOutputColourFormat", $hash->{helper}{VIDEOCOLOURFORMAT}->{$9} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour format: ". dq($9);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour format: ". dq($9);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURDEPTH}->{$10}) ) {
                readingsBulkUpdate( $hash, "videoOutputColourDepth", $hash->{helper}{VIDEOCOLOURDEPTH}->{$10} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour depth: ". dq($10);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour depth: ". dq($10);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURSPACE}->{$11}) ) {
                readingsBulkUpdate( $hash, "videoOutputColourSpace", $hash->{helper}{VIDEOCOLOURSPACE}->{$11} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour space: ". dq($11);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: video output colour space: ". dq($11);
            }
            
            if ( defined ( $hash->{helper}{VIDEORESOLUTION}->{$12}) ) {
                readingsBulkUpdate( $hash, "hdmi1RecommendedResolution", $hash->{helper}{VIDEORESOLUTION}->{$12} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: HDMI 1 Monitor Recommend Resolution Information: ". dq($12);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: HDMI 1 Monitor Recommend Resolution Information: ". dq($12);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURDEPTH}->{$13}) ) {
                readingsBulkUpdate( $hash, "hdmi1ColourDepth", $hash->{helper}{VIDEOCOLOURDEPTH}->{$13} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi1 colour depth: ". dq($13);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi1 output colour depth: ". dq($13);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURSPACE}->{$14}) ) {
                readingsBulkUpdate( $hash, "hdmi1ColourSpace", $hash->{helper}{VIDEOCOLOURSPACE}->{$14} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi1 colour space: ". dq($14);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi1 output colour space: ". dq($14);
            }
            
            if ( defined ( $hash->{helper}{VIDEORESOLUTION}->{$15}) ) {
                readingsBulkUpdate( $hash, "hdmi2RecommendedResolution", $hash->{helper}{VIDEORESOLUTION}->{$15} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: HDMI2 Monitor Recommend Resolution Information: ". dq($15);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: HDMI2 Monitor Recommend Resolution Information: ". dq($15);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURDEPTH}->{$16}) ) {
                readingsBulkUpdate( $hash, "hdmi2ColourDepth", $hash->{helper}{VIDEOCOLOURDEPTH}->{$16} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi2 colour depth: ". dq($16);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi2 output colour depth: ". dq($16);
            }
            
            if ( defined ( $hash->{helper}{VIDEOCOLOURSPACE}->{$17}) ) {
                readingsBulkUpdate( $hash, "hdmi2ColourSpace", $hash->{helper}{VIDEOCOLOURSPACE}->{$17} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi2 colour space: ". dq($17);
            }
            else {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: hdmi2 output colour space: ". dq($17);
            }

        # Speaker
        } elsif ( substr($line,0,3) eq "SPK" ) {
            my $speakers = substr($line,3,1);
            
            if ( $speakers == "0" ) {
                readingsBulkUpdate( $hash, "speakers", "off" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: speakers: off";
            } elsif ( $speakers == "1" ) {
                readingsBulkUpdate( $hash, "speakers", "A" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: speakers: A";
            } elsif ($speakers == "2") {
                readingsBulkUpdate( $hash, "speakers", "B" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: speakers: B";
            } elsif ($speakers == "3") {
                readingsBulkUpdate( $hash, "speakers", "A+B" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: speakers: A+B";
            } else {
                readingsBulkUpdate( $hash, "speakers", $speakers );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: speakers: ". dq( $speakers );
            }
            
        # Speaker System
        # do we have Zone 2 speakers?
        } elsif ( substr( $line,0,3 ) eq "SSF" ) {
            if ( defined ( $hash->{helper}{SPEAKERSYSTEMS}->{substr( $line, 3, 2)} ) ) {
                readingsBulkUpdate( $hash, "speakerSystem", $hash->{helper}{SPEAKERSYSTEMS}->{substr( $line, 3, 2)} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: SpeakerSystem: ". dq( substr( $line, 3, 2) );
            } else {
                readingsBulkUpdate( $hash, "speakerSystem", $line );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Unknown SpeakerSystem " . dq( substr( $line, 3, 2 ) );
            }
        # Listening Mode
        } elsif ( substr($line,0,2) eq "SR" ) {
            if ( defined ( $hash->{helper}{LISTENINGMODES}->{substr($line,2)}) ) {
                readingsBulkUpdate( $hash, "listeningMode", $hash->{helper}{LISTENINGMODES}->{substr($line,2)} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: listeningMode: ". dq(substr($line,2));
            } else {
                readingsBulkUpdate( $hash, "listeningMode", $line );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown listeningMode: ". dq(substr( $line, 2 ) );
            }
        # Listening Mode Playing (for Display)
        } elsif ( substr( $line, 0, 2 ) eq "LM" ) {
            if ( defined ( $hash->{helper}{LISTENINGMODESPLAYING}->{substr( $line, 2, 4)} ) ) {
                readingsBulkUpdate( $hash, "listeningModePlaying", $hash->{helper}{LISTENINGMODESPLAYING}->{substr( $line, 2, 4 )} );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: listeningModePlaying: ". dq( substr( $line, 2, 4 ) );
            } else {
                readingsBulkUpdate( $hash, "listeningModePlaying", $line );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: unknown listeningModePlaying: ". dq( substr( $line, 2, 4 ) );
            }
        # Main zone Power
        } elsif ( substr( $line, 0, 3 ) eq "PWR" ) {
            my $power = substr( $line, 3, 1);
            if ( $power == "0" ) {
                readingsBulkUpdate( $hash, "power", "on" )
                    if ( ReadingsVal( $name, "power", "-" ) ne "on" );

                $state = "on";
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Power: on";
            } else {
                readingsBulkUpdate( $hash, "power", "off" )
                    if ( ReadingsVal( $name, "power", "-" ) ne "off" );

                $state = "off";
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Power: off";
            }
            # Set STATE
            # devIO.pm sets hash->STATE accordingly to the connection state (opened, CONNECTED, DISCONNECTED)
            # we want that hash->STATE represents the state of the device (absent, off, on)
            
            # stateAV
            my $stateAV = PIONEERAVR_GetStateAV($hash);
            readingsBulkUpdate( $hash, "stateAV", $stateAV )
              if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );
            
        # MCACC memory
        } elsif ( $line =~ m/^(MC)(\d)$/ ) {
            readingsBulkUpdate( $hash, "mcaccMemory", $2 );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: MCACC memory: selected memory is: $2";

        # Display updates
        # uses a translation table for each letter (char) to display the letters properly
        } elsif ( substr( $line, 0, 2 ) eq "FL" ) {
            my $hex = substr( $line, 4, 28);
            my @a = map $hash->{helper}{CHARS}->{$_}, $hex =~ /(..)/g;
            my $display = join('',@a);
            readingsBulkUpdate( $hash, "displayPrevious", ReadingsVal( $name, "display","" ) );
            readingsBulkUpdate( $hash, "display", $display );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Display update to: $display";

        # eq
        } elsif ( $line =~ m/^ATC([0|1])/ ) {
            if ( $1 == "1" ) {
                readingsBulkUpdate( $hash, "eq", "on" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: eq is on";
            }
            else {
                readingsBulkUpdate( $hash, "eq", "off" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: eq is off";
            }

        # standing wave
        } elsif ( $line =~ m/^ATD([0|1])/ ) {
            if ( $1 == "1" ) {
                readingsBulkUpdate( $hash, "standingWave", "on" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: standingWave is on";
            }
            else {
                readingsBulkUpdate( $hash, "standingWave", "off" );
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: standingWave is off";
            }

        # key received
        } elsif ( $line =~ m/^NXA$/ ) {
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Network player: Key pressed";

        # screen type and screen name
        } elsif ( $line =~ m/^(GCH|GCI)(\d{2})(\d)(\d)(\d)(\d)(\d)\"(.*)\"$/ ) {
            # Format:
            #   $2: screen type
            #     00:Message
            #     01:List
            #     02:Playing(Play)
            #     03:Playing(Pause)
            #     04:Playing(Fwd)
            #     05:Playing(Rev)
            #     06:Playing(Stop)
            #     99:Drawing invalid

            #   $3: 0:Same hierarchy 1:Updated hierarchy (Next or Previous list)
            #   $4: Top menu key flag
            #     0:Invalidity
            #     1:Effectiveness
            #   $5: Tools (menu, edit,iPod Control) Key Information
            #     0:Invalidity
            #     1:Effectiveness
            #   $6: Return Key Information
            #     0:Invalidity
            #     1:Effectiveness
            #   $7: always 0

            #   $8: Screen name (UTF8) max. 128 byte
            my $screenType = $hash->{helper}{SCREENTYPES}{$2};

            readingsBulkUpdate( $hash, "screenType", $screenType );
            readingsBulkUpdate( $hash, "screenName", $8 );
            readingsBulkUpdate( $hash, "screenHierarchy", $3 );
            readingsBulkUpdate( $hash, "screenTopMenuKey", $4 );
            readingsBulkUpdate( $hash, "screenToolsKey", $5 );
            readingsBulkUpdate( $hash, "screenReturnKey", $6 );

            # to update the OSD/screen while playing from iPad/network a command has to be sent regulary
            if ($2 eq "02" ) {
				RemoveInternalTimer( $hash, "PIONEERAVR_screenUpdate" );
                # reset screenUpdate timer -> again in 5s
                my $checkInterval = 5;
                my $next = gettimeofday() + $checkInterval;
                $hash->{helper}{nextScreenUpdate} = $next;
                InternalTimer( $next, "PIONEERAVR_screenUpdate", $hash, 0 );
                readingsBulkUpdate( $hash, "playStatus", "playing" );
            } elsif ( $2 eq "03" ) {
                readingsBulkUpdate( $hash, "playStatus", "paused" );            
            } elsif ( $2 eq "04" ) {
                readingsBulkUpdate( $hash, "playStatus", "fast-forward" );          
            } elsif ( $2 eq "05" ) {
                readingsBulkUpdate( $hash, "playStatus", "fast-rewind" );           
            } elsif ( $2 eq "06" ) {
                readingsBulkUpdate( $hash, "playStatus", "stopped" );           
            }
            
            # stateAV
            if ( $2 eq "02" || $2 eq "03" || $2 eq "04" || $2 eq "05" || $2 eq "06" ) {
            
                my $stateAV = PIONEERAVR_GetStateAV($hash);
                readingsBulkUpdate( $hash, "stateAV", $stateAV )
                    if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );
            }
        # screen type and screen name for XC-HM72 (XC-HM72 has screen name in $9 and no screen update command)
        } elsif ( $line =~ m/^(GCP)(\d{2})(\d)(\d)(\d)(\d)(\d)(.*)\"(.*)\"$/ ) {
            # Format:
            #   $2: screen type
            #     00:Message
            #     01:List
            #     02:Playing(Play)
            #     03:Playing(Pause)
            #     04:Playing(Fwd)
            #     05:Playing(Rev)
            #     06:Playing(Stop)
            #     99:Drawing invalid

            #   $3: 0:Same hierarchy 1:Updated hierarchy (Next or Previous list)
            #   $4: Top menu key flag
            #     0:Invalidity
            #     1:Effectiveness
            #   $5: Tools (menu, edit,iPod Control) Key Information
            #     0:Invalidity
            #     1:Effectiveness
            #   $6: Return Key Information
            #     0:Invalidity
            #     1:Effectiveness
            #   $7: always 0
            #   $8: 10 digits (XC-HM72) or nothing
            #   $9: Screen name (UTF8) max. 128 byte
            my $screenType = $hash->{helper}{SCREENTYPES}{$2};

            readingsBulkUpdate( $hash, "screenType", $screenType );
            readingsBulkUpdate( $hash, "screenName", $9 );
            readingsBulkUpdate( $hash, "screenHierarchy", $3 );
            readingsBulkUpdate( $hash, "screenTopMenuKey", $4 );
            readingsBulkUpdate( $hash, "screenToolsKey", $5 );
            readingsBulkUpdate( $hash, "screenReturnKey", $6 );

            # to update the OSD/screen while playing from iPad/network a command has to be sent regulary
            if ($2 eq "02" ) {
                RemoveInternalTimer( $hash, "PIONEERAVR_screenUpdate" );
                # It seems that XC-HM72 does not support the screen update command
                ## reset screenUpdate timer -> again in 5s
                #my $checkInterval = 5;
                #my $next = gettimeofday() + $checkInterval;
                #$hash->{helper}{nextScreenUpdate} = $next;
                #InternalTimer( $next, "PIONEERAVR_screenUpdate", $hash, 0 );
                #readingsBulkUpdate( $hash, "playStatus", "playing" );
            } elsif ( $2 eq "03" ) {
                readingsBulkUpdate( $hash, "playStatus", "paused" );            
            } elsif ( $2 eq "04" ) {
                readingsBulkUpdate( $hash, "playStatus", "fast-forward" );          
            } elsif ( $2 eq "05" ) {
                readingsBulkUpdate( $hash, "playStatus", "fast-rewind" );           
            } elsif ( $2 eq "06" ) {
                readingsBulkUpdate( $hash, "playStatus", "stopped" );           
            }
            
            # stateAV
            if ( $2 eq "02" || $2 eq "03" || $2 eq "04" || $2 eq "05" || $2 eq "06" ) {
            
                my $stateAV = PIONEERAVR_GetStateAV($hash);
                readingsBulkUpdate( $hash, "stateAV", $stateAV )
                    if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );
            }
        # Source information
        } elsif ( $line =~ m/^(GHP|GHH)(\d{2})$/ ) {
            my $sourceInfo = $hash->{helper}{SOURCEINFO}{$2};
            readingsBulkUpdate( $hash, "sourceInfo", $sourceInfo );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Screen source information: $2 $sourceInfo";

        # total screen lines
        } elsif ( $line =~ m/^(GDP|GDH)(\d{5})(\d{5})(\d{5})$/ ) {
            readingsBulkUpdate( $hash, "screenLineNumberFirst", $2 + 0 );
            readingsBulkUpdate( $hash, "screenLineNumberLast", $3 + 0 );
            readingsBulkUpdate( $hash, "screenLineNumbersTotal", $4 + 0 );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Screen Item number of line 1(5byte): $2, Item number of last line(5byte): $3, Total number of items List(5byte): $4 ";

        # Screen line numbers
        } elsif ( $line =~ m/^(GBP|GBH|GBI)(\d{2})$/ ) {
            readingsBulkUpdate( $hash, "screenLineNumbers", $2 + 0 );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Screen line numbers = $2";

        # screenInformation
        } elsif ( $line =~ m/^(GEP|GEH|GEI)(\d{2})(\d)(\d{2})\"(.*)\"$/ ) {
            # Format:
            #   $2: Line number
            #   $3: Focus (yes(1)/no(0)/greyed out(9)
            #   $4: Line data type:
            #     00:Normal(no mark type)
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
            my $screenLine     = "screenLine".$2;
            my $screenLineType = "screenLineType".$2;
            readingsBulkUpdate( $hash, $screenLine, $5 );
            readingsBulkUpdate( $hash, $screenLineType, $lineDataType );
            if ( $3 == 1 ) {
              readingsBulkUpdate( $hash, "screenLineHasFocus", $2 );
            }
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: screen line $2 ($screenLine) type: $lineDataType: " . dq( $5 );

            # for being coherent with http://www.fhemwiki.de/wiki/DevelopmentGuidelinesAV
            if ( $4 eq "20" or $4 eq "21" or $4 eq "22" ) {
              readingsBulkUpdate( $hash, $lineDataType, $5);
              Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: reading update for displayDataType $lineDataType: " . dq( $5 );
            }

        # Tuner channel names
        } elsif ( $line =~ m/^TQ(\w\d)\"(.{8})\"$/ ) {
            $hash->{helper}{TUNERCHANNELNAMES}{$1} = $2;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: tunerChannel: $1 has the name: " .dq($2);
        # Tuner channel
        } elsif ( $line =~ m/^PR(\w)0(\d)$/ ) {
            readingsBulkUpdate( $hash, "channelStraight", $1.$2 );
            readingsBulkUpdate( $hash, "channelName", $hash->{helper}{TUNERCHANNELNAMES}{$1.$2} );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Current tunerChannel: " . $1.$2;
            if ( $1 eq "A" ) {
                readingsBulkUpdate( $hash, "channel", $2 );
            } else {
                readingsBulkUpdate( $hash, "channel", "-" );
            }
        # Tuner frequency
        # FRFXXXYY -> XXX.YY Mhz
        } elsif ( $line =~ m/^FRF([0|1])([0-9]{2})([0-9]{2})$/ ) {
                my $tunerFrequency = $2.".".$3;
                if ( $1 == 1 ) {
                    $tunerFrequency = $1.$tunerFrequency;
                }
                readingsBulkUpdate( $hash, "tunerFrequency", $tunerFrequency );
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: tunerFrequency: " . $tunerFrequency;

        # all network settings
        } elsif ( $line =~ m/^SUL(\d)(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d{3})(\d)(\".*\")(\d{5})$/ ) {
            #readingsBulkUpdate( $hash, "macAddress", $1.":".$2.":".$3.":".$4.":".$5.":".$6);
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: Network settings is " . $1;
            if ( $1 == 0 ) {
                $hash->{dhcp}= "off";
            } else {
                $hash->{dhcp}= "on";
            }
            $hash->{ipAddress}      = sprintf( "%d.%d.%d.%d",$2 ,$3 ,$4 ,$5 );
            $hash->{netmask}        = sprintf( "%d.%d.%d.%d",$6,$7,$8,$9 );
            $hash->{defaultGateway} = sprintf( "%d.%d.%d.%d",$10,$11,$12,$13 );
            $hash->{dns1}           = sprintf( "%d.%d.%d.%d",$14,$15,$16,$17 );
            $hash->{dns2}           = sprintf( "%d.%d.%d.%d",$18,$19,$20,$21 );
            if ( $22 == 0 ) {
                $hash->{proxy}     = "off";
            } else {
                $hash->{proxy}     = "on";
                $hash->{proxyName} = $23;
                $hash->{proxyPort} = 0 + $24;
            }
        # network ports 1-4
        } elsif ( $line =~ m/^SUM(\d{5})(\d{5})(\d{5})(\d{5})$/ ) {
        # network port1
            if ( $1 == 99999 ) {
                $hash->{networkPort1} = "disabled";
            } else {
                $hash->{networkPort1} = 0 + $1;
            }
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: NetworkPort1 is " . $1;
        # network port2
            if ( $2 == 99999 ) {
                $hash->{networkPort2} = "disabled";
            } else {
                $hash->{networkPort2} = 0 + $2;
            }
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: NetworkPort2 is " . $2;
        # network port3
            if ( $3 == 99999 ) {
                $hash->{networkPort3} = "disabled";
            } else {
                $hash->{networkPort3} = 0 + $3;
            }
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: NetworkPort3 is " . $3;
        # network port4
            if ( $4 == 99999 ) {
                $hash->{networkPort4} = "disabled";
            } else {
                $hash->{networkPort4} = 0 + $4;
            }
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: NetworkPort4 is " . $4;

        # MAC address
        } elsif ( $line =~ m/^SVB(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})$/ ) {
            $hash->{macAddress} = $1.":".$2.":".$3.":".$4.":".$5.":".$6;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: NetworkPort1 is " . $1;

        # avrModel
        } elsif ( $line =~ m/^RGD<\d{3}><(.*)\/(.*)>$/ ) {
            $hash->{avrModel} = $1;
            $hash->{avrSoftwareType} = $2;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: avrModel is " . $1;

        # Software version
        } elsif ( $line =~ m/^SSI\"(.*)\"$/ ) {
            $hash->{softwareVersion} = $1;
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: softwareVersion is " . $1;

        # ERROR MESSAGES
        #   E02<CR+LF>  NOT AVAILABLE NOW   Detected the Command line which could not work now.
        #   E03<CR+LF>  INVALID COMMAND Detected an invalid Command with this model.
        #   E04<CR+LF>  COMMAND ERROR   "Detected inappropriate Command line.
        #               Detected IP-only Commands on RS232C (GIA,GIC,FCA,FCB,GIH and GII)."
        #   E06<CR+LF>  PARAMETER ERROR Detected inappropriate Parameter.
        #   B00<CR+LF>  BUSY    Now AV Receiver is Busy. Please wait few seconds.

        } elsif ( $line =~ m/^E0(\d)$/ ) {
            my $errorMessage ="PIONEERAVR $name: Received Error code from PioneerAVR: $line";
            if ( $1 == 2 ) {
                $errorMessage .= " (NOT AVAILABLE NOW - Detected the Command line which could not work now.)";
            } elsif ( $1 == 3 ) {
                $errorMessage .= " (INVALID COMMAND - Detected an invalid Command with this model.)";
            } elsif ( $1 == 4 ) {
                $errorMessage .= " (COMMAND ERROR - Detected inappropriate Command line.)";
            } elsif ( $1 == 6 ) {
                $errorMessage .= " (PARAMETER ERROR - Detected inappropriate Parameter.)";
            }
            Log3 $hash, 5, $errorMessage;
        } elsif ( $line =~ m/^B00$/ ) {
            Log3 $hash, 5,"PIONEERAVR $name: Error nr $line received (BUSY  Now AV Receiver is Busy. Please wait few seconds.)";
        # network standby
        # STJ1 -> on  -> Pioneer AV receiver can be switched on from standby
        # STJ0 -> off -> Pioneer AV receiver cannot be switched on from standby
        } elsif ( $line =~ m/^STJ([0|1])/) {
            if ( $1 == "1" ) {
                $hash->{networkStandby} = "on";
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: networkStandby is on";
            } else {
                $hash->{networkStandby} = "off";
                Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: networkStandby is off";
            }
        # commands for other zones (Volume, mute, power)
        # Zone 2 command
        } elsif ( $line =~ m/^ZV(\d\d)$|^Z2MUT(\d)$|^Z2F(\d\d)$|^APR(0|1)$/ ) {
            $msgForZone = "zone2";
            Log3 $hash, 5, "PIONEERAVR $name: received $line - message for zone2!";
        # Zone 3 command
        } elsif ( $line =~ m/^YV(\d\d)$|^Z3MUT(\d)$|^Z3F(\d\d)$|^BPR(0|1)$/ ) {
            $msgForZone = "zone3";
            Log3 $hash, 5, "PIONEERAVR $name: received $line - message for zone3!";
        # hdZone command
        } elsif ( $line =~ m/^ZEA(\d\d)$|^ZEP(0|1)$/ ) {
            $msgForZone = "hdZone";
            Log3 $hash, 5, "PIONEERAVR $name: received $line - message for hdZone!";
        } else { 
            Log3 $hash, 5, "PIONEERAVR $name: received $line - don't know what this means - help me!";
        }

        # if PIONEERAVRZONE device exists for that zone, dispatch the command
        # otherwise try to autocreate the device
        unless( $msgForZone eq "" ) {
            my $hashZone = $modules{PIONEERAVRZONE}{defptr}{$msgForZone};
            Log3 $hash, 5, "PIONEERAVR $name: received message for Zone: ".$msgForZone;
            if( !$hashZone ) {
                my $ret = "UNDEFINED PIONEERAVRZONE_$msgForZone PIONEERAVRZONE $msgForZone";
                Log3 $name, 3, "PIONEERAVR $name: $ret, please define it";
                DoTrigger( "global", $ret );
            }
            # dispatch "zone" - commands to other zones
            Dispatch( $hash, $line, undef );  # dispatch result to PIONEERAVRZONEs
            Log3 $hash, 5, "PIONEERAVR $name: ".dq( $line ) ." interpreted as: not for the Main zone -> dispatch to PIONEERAVRZONEs zone: $msgForZone";
            $msgForZone = "";
        }
    }

    readingsEndUpdate( $hash, 1);

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
    my ( $s )= @_;
    $s = "<nothing>" unless( defined( $s ) );
    return "\"" . escapeLogLine( $s ) . "\"";
}
#####################################
#PIONEERAVR_Log() is used to show the data sent and received from/to PIONEERAVR if attr logTraffic is set
sub PIONEERAVR_Log($$$) {
  my ( $hash, $loglevel, $logmsg ) = @_;
  my $name                         = $hash->{NAME};
  
  $loglevel = AttrVal( $name, "logTraffic", undef ) unless( defined( $loglevel ) );
  return unless( defined( $loglevel ) );
  Log3 $hash, $loglevel , "PIONEERAVR $name (loglevel: $loglevel) logTraffic: $logmsg";
}

#####################################
sub PIONEERAVR_DevInit($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if ( lc( ReadingsVal( $name, "state", "?" ) ) eq "opened" ) {
        DoTrigger( $name, "CONNECTED" );
    }
    else {
        DoTrigger( $name, "DISCONNECTED" );
    }
}

#####################################
sub PIONEERAVR_Reopen($) {
    my ( $hash ) = @_;
    my $name     = $hash->{NAME};

    Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Reopen()";

    DevIo_CloseDev( $hash );
    my $ret = DevIo_OpenDev( $hash, 1, undef );

    if ( $hash->{STATE} eq "opened" ) {
        Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_Reopen() -> now opened";

        if ( AttrVal( $name, "statusUpdateReconnect", "enable" ) eq "enable" ) {
            PIONEERAVR_statusUpdate( $hash );
        } else {
            # update state by requesting power on/off status from the Pioneer AVR
            PIONEERAVR_Write( $hash, "?P" );
        }
    }
    return $ret;
}
#####################################
# writing to the Pioneer AV receiver
# connection check 3s (or attr timout seconds) after writing
sub PIONEERAVR_Write($$) {
  my ( $hash, $msg ) = @_;
  my $name           = $hash->{NAME};
  
  $msg = $msg."\r\n";
  my $logMsg = "SimpleWrite " . dq( $msg );
  PIONEERAVR_Log( $hash, undef, $logMsg );

  DevIo_SimpleWrite( $hash, $msg, 0 );

    # do connection check latest after TIMEOUT
    my $next = gettimeofday() + AttrVal( $name, "timeout", "5" );
    if ( !defined( $hash->{helper}{nextConnectionCheck} )
        || $hash->{helper}{nextConnectionCheck} > $next )
    {
        $hash->{helper}{nextConnectionCheck} = $next;
        RemoveInternalTimer($hash, "PIONEERAVR_connectionCheck");
        InternalTimer( $next, "PIONEERAVR_connectionCheck", $hash, 0 );
    }
}

######################################################################################
# PIONEERAVR_connectionCheck is called if PIONEERAVR received no data for 120s
#   we send a "new line" and expect (if the connection is up) to receive "R"
#   DevIo_Expect() is used for this
#   DevIO_Expect() sends a command (just a "new line") and waits up to 5s for a reply
#   if there is a reply DevIO_Expect() returns the reply
#   if there is no reply
#   - DevIO_Expect() tries to close and reopen the connection
#   - sends the command again
#   - waits again up to 5 seconds for a reply
#   - if there is a reply the state is set to "opened"
#   - if there is no reply the state is set to "disconnected"
#

sub PIONEERAVR_connectionCheck ($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $verbose = AttrVal( $name, "verbose", "" );

    RemoveInternalTimer( $hash, "PIONEERAVR_connectionCheck" );

    $hash->{STATE} = "opened";    # assume we have an open connection
    $attr{$name}{verbose} = 0 if ( $verbose eq "" || $verbose < 4 );

    my $connState =
      DevIo_Expect( $hash,
        "\r\n",
        AttrVal( $name, "timeout", "5" ) );

    # successful connection
    if ( defined($connState) ) {

        # reset connectionCheck timer
        my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
        if ( $checkInterval ne "off" ) {
            my $next = gettimeofday() + $checkInterval;
            $hash->{helper}{nextConnectionCheck} = $next;
            InternalTimer( $next, "PIONEERAVR_connectionCheck", $hash, 0 );
        }

        if ($connState =~ m/^R\r?\n?$/) {
            Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_connectionCheck() --- connstate=R -> do nothing: ".dq($connState)." PARTIAL: ".dq( $hash->{PARTIAL});
        } else {
            $hash->{PARTIAL} .= $connState;
            Log3 $name, 5, "PIONEERAVR $name: PIONEERAVR_connectionCheck() --- connstate<>R -> do nothing: ".dq($connState)." PARTIAL: ".dq( $hash->{PARTIAL});
        }
    }     
    $attr{$name}{verbose} = $verbose if ( $verbose ne "" );
    delete $attr{$name}{verbose} if ( $verbose eq "" );
}

sub PIONEERAVR_screenUpdate($) {
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $cmd       = "updateScreen";
    my $playerCmd = "";
    
    Log3 $name, 3, "PIONEERAVR $name: PIONEERAVR_screenUpdate()";

    if ( defined( $hash->{helper}{main}{CURINPUTNR} ) ) {
        my $inputNr = $hash->{helper}{main}{CURINPUTNR};

        if ($inputNr eq "17") {
            $playerCmd = $cmd."Ipod";
        #### homeMediaGallery, sirius, internetRadio, pandora, mediaServer, favorites, spotify
        } elsif (($inputNr eq "26") ||($inputNr eq "27") || ($inputNr eq "38") || ($inputNr eq "41") || ($inputNr eq "44") || ($inputNr eq "45") || ($inputNr eq "53")) {
            $playerCmd = $cmd."Network";
        } else {
            my $err = "PIONEERAVR $name: The command $cmd for input nr. $inputNr is not possible!";
            Log3 $name, 3, $err;
            return $err;
        }
        my $setCmd = $hash->{helper}{SETS}{main}{$playerCmd};
        PIONEERAVR_Write( $hash, $setCmd);
    } else {
        Log3 $name, 3, "PIONEERAVR $name: PIONEERAVR_screenUpdate(): can't find the inputNr";
    }
}

#########################################################
sub PIONEERAVR_statusUpdate($) {
    my ($hash) = @_;
    my $name    = $hash->{NAME};

    Log3 $name, 3, "PIONEERAVR $name: PIONEERAVR_statusUpdate()";

    foreach my $zone ( keys %{$hash->{helper}{GETS}} ) {
        foreach my $key ( keys %{$hash->{helper}{GETS}{$zone}} ) {
            PIONEERAVR_Write( $hash, $hash->{helper}{GETS}->{$zone}->{$key});
            select(undef, undef, undef, 0.1);
        }
    }
    PIONEERAVR_askForInputNames( $hash,5);
}
#########################################################
sub PIONEERAVR_askForInputNames($$) {
    my ($hash, $loglevel) = @_;
    my $name              = $hash->{NAME};
    my $comstr            = '';
    my $now120            = gettimeofday()+120;
    my $delay             = 0.1;

    RemoveInternalTimer( $hash, "PIONEERAVR_connectionCheck" );
    InternalTimer( $now120, "PIONEERAVR_connectionCheck", $hash, 0 );

    # we ask for the inputs 1 to 59 if an input name exists (command: ?RGB00 ... ?RGB59)
    #   and if the input is disabled (command: ?SSC0003 ... ?SSC5903)
    # at least the model VSX-923 needs a break of 0.1s between each command, otherwise it closes the tcp port 
    for ( my $i=0; $i<60; $i++ ) {
        #select( undef, undef, undef, 0.1 );
        $comstr = sprintf '?RGB%02d', $i;
        PIONEERAVR_Write( $hash,$comstr );
        select( undef, undef, undef, $delay );

        #digital(audio) input terminal (coax, optical, analog)
        $comstr = sprintf '?SSC%02d00',$i;
        PIONEERAVR_Write( $hash,$comstr );
        select( undef, undef, undef, $delay );

        #hdmi input terminal?
        $comstr = sprintf '?SSC%02d01',$i;
        PIONEERAVR_Write( $hash,$comstr );
        select( undef, undef, undef, $delay );
        
        #component video input terminal ?
        $comstr = sprintf '?SSC%02d02',$i;
        PIONEERAVR_Write( $hash,$comstr );
        select( undef, undef, undef, $delay );
        
        #input enabled/disabled?
        $comstr = sprintf '?SSC%02d03',$i;
        PIONEERAVR_Write( $hash,$comstr );
        select( undef, undef, undef, $delay  );
        
        #inputLevelAdjust (-12dB ... +12dB)
        $comstr = sprintf '?ILA%02d',$i;
        PIONEERAVR_Write( $hash,$comstr );
    }
}

sub PIONEERAVR_GetStateAV($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    } elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    } elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
        
    } elsif (defined( $hash->{helper}{main}{CURINPUTNR})) {
        my $iNr = $hash->{helper}{main}{CURINPUTNR};
        if ( $hash->{helper}{INPUTNAMES}->{$iNr}{playerCommands} eq "1")
        {
            if ( ReadingsVal( $name, "playStatus", "" ) ne "" )
            {
                return ReadingsVal( $name, "playStatus", "stopped" );
            } else {
                return ReadingsVal( $name, "power", "off" );
            } 
        } else {
            return ReadingsVal( $name, "power", "off" );
        }
    } else {
        return ReadingsVal( $name, "power", "off" );
    }
}

#####################################
# Callback from 95_remotecontrol for command makenotify.
sub PIONEERAVR_RCmakenotify($$) {
    my ($nam, $ndev) = @_;
    my $nname        = "notify_$nam";

    fhem( "define $nname notify $nam set $ndev remoteControl ".'$EVENT',1);
    Log3 undef, 2, "PIONEERAVR [remotecontrol:PIONEERAVR] Notify created: $nname";
    return "Notify created by PIONEERAVR: $nname";
}

#####################################
# Default-remote control layout for PIONEERAVR
sub RC_layout_PioneerAVR() {
    my $ret;
    my @row;
    $row[0] = "toggle:POWEROFF";
    $row[1] = "volumeUp:UP,mute toggle:MUTE,inputUp:CHUP";
    $row[2] = ":VOL,:blank,:PROG";
    $row[3] = "volumeDown:DOWN,:blank,inputDown:CHDOWN";
    $row[4] = "remoteControl audioParameter:AUDIO,remoteControl cursorUp:UP,remoteControl videoParameter:VIDEO";
    $row[5] = "remoteControl cursorLeft:LEFT,remoteControl cursorEnter:ENTER,remoteControl cursorRight:RIGHT";
    $row[6] = "remoteControl homeMenu:HOMEsym,remoteControl cursorDown:DOWN,remoteControl cursorReturn:RETURN";
    $row[7] = "attr rc_iconpath icons/remotecontrol";
    $row[8] = "attr rc_iconprefix black_btn_";

    # unused available commands
    return @row;
}
#####################################

1;

=pod
=item device
=item summary control for PIONEER AV receivers via network or serial connection
=item summary_DE Steuerung von PIONEER AV Receiver per Netzwerk oder seriell
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
    <li><b>networkStandby <on|off></b> - Turns Network standby on or off. To turn on a Pioneer AV Receiver with this module from standby, Network Standby must be "on". <code>set &lt;name&gt; networkStandby on</code> should do this</li>
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

  does not return any value but asks the Pioneer AVR for the current status (e.g. of the volume). As soon as the Pioneer AVR replies (the time, till the Pioneer AVR replies is unpredictable), the readings or internals of this pioneerAVR modul are updated.
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
    <li><b>networkSettings</b> - get the IP network settings (ip, netmask, gateway,dhcp, dns1, dns2, proxy) of the Pioneer AV Receiver. The values are stored as INTERNALS not as READINGS </li>
    <li><b>networkStandby</b> - get the current setting of networkStandby -> the value of networkStandby (on|off) is stored as an INTERNAL not as a READING</li>
    <li><b>power</b> - get the Power state of the Pioneer AV receiver </li>
    <li><b>signalSelect</b> -  </li>
    <li><b>softwareVersion</b> - get the software version of the software currently running in the Pioneer AV receiver. The value is stored as INTERNAL</li>
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
    <li>
       <b>connectionCheck</b> &nbsp;&nbsp;1..120,off&nbsp;&nbsp; Pings the Pioneer AVR every X seconds to verify connection status. Defaults to 60 seconds.
    </li>
    <li>
        <b>timeout</b> &nbsp;&nbsp;1,2,3,4,5,7,10,15&nbsp;&nbsp; Max time in seconds till the Pioneer AVR replies to a ping. Defaults to 3 seconds.
    </li>
    <li><b>checkStatusStart &lt;enable|disable&gt;</b> - Enables/disables the status update (read all values from the Pioneer AV receiver, can take up to one minute) when the module is loaded.(Default: enable)</li>
    <li><b>checkStatusReconnect &lt;enable|disable&gt;</b> - Enables/disables the status update (read all values from the Pioneer AV receiver, can take up to one minute) when the connection to the Pioneer AV receiver is reestablished.(Default: enable)</li>
    <li><b>logTraffic &lt;loglevel&gt;</b> - Enables logging of sent and received datagrams with the given loglevel.
    Control characters in the logged datagrams are escaped, i.e. a double backslash is shown for a single backslash,
    \n is shown for a line feed character,...</li>
    <li><b><a href="#verbose">verbose</a></b> - 0: log es less as possible, 5: log as much as possible</li>
    <li><b>volumeLimit &lt;0 ... 100&gt;</b> - limits the volume to the given value</li>
    <li><b>volumeLimitStraight &lt;-80 ... 12&gt;</b> - limits the volume to the given value</li>
  </ul>
  <br><br>
  <b>Generated Readings/Events:</b>
    <br/><br/>
    <ul>
        <li><b>audioAutoPhaseControlMS</b> - currently configured Auto Phase Control in ms</li>
        <li><b>audioAutoPhaseControlRevPhase</b> - acurrently configured Auto Phase Control reverse Phase -> 1 means: reverse phase</li>
        <li><b>audioInputFormat<XXX></b> - Shows if the channel XXX is available in the audio input signal (1 means: is available)</li>
        <li><b>audioInputFrequency</b> - Frequency of the input signal</li>
        <li><b>audioInputSignal</b> - Type of the input signal (z.B. ANALOG, PCM, DTS,...)</li>
        <li><b>audioOutputFormat<XXX></b> - Shows if the channel XXX is available in the audio output sgnal (1 means: is available)</li>
        <li><b>audioOutputFrequency</b> - Frequency of the audio output signal</li>
        <li><b>bass</b> - currently set bass</li>
        <li><b>channel</b> - Tuner Preset (1...9)</li>
        <li><b>channelStraight</b> - Tuner Preset as diplayed in the display of the Pioneer AV Receiver, e.g. A2</li>
        <li><b>display</b> - Currently dispayed text in the display of the Pioneer AV Receiver</li>
        <li><b>displayPrevious</b> - Previous displayed text</li>
        <li><b>eq</b> - Equalizer status of the Pioneer AV Receiver (on|off)</li>
        <li><b>hdmiOut</b> - Shows the currently selected HDMI-output(s)?</li>
        <li><b>input</b> - shows the currently selected input</li>
        <li><b>inputsList</b> - ":" separated list of all activated inputs</li>
        <li><b>listeningMode</b> - Currently set Listening Mode</li>
        <li><b>listeningModePlaying</b> - Currently used Listening Mode</li>
        <li><b>mcaccMemory</b> - MCACC Setting</li>
        <li><b>mute</b> - Mute (on|off)</li>
        <li><b>power</b> - Main Zone on or standby?</li>
        <li><b>pqlsWorking</b> - currently set PQLS</li>
        <li><b>presence</b> - Is the Pioneer AV Receiver reachable via ethernet?</li>
        <li><b>screenHirarchy</b> - Hirarchy of the currently shown On Screen Displays (OSD)</li>
        <li><b>screenLine01...08</b> - Content of the lines 01...08 of the OSD</li>
        <li><b>screenLineHasFocus</b> - Which line of the OSD has the focus?</li>
        <li><b>screenLineNumberFirst</b> - Long lists are shown in the OSD in smaller pages with 8 lines. This shows which elemnt of the lang list is the currently shown first line.</li>
        <li><b>screenLineNumberLast</b> - Long lists are shown in the OSD in smaller pages with 8 lines. This shows which elemnt of the lang list is the currently shown last line.</li>
        <li><b>screenLineNumbersTotal</b> - How many lines has the full list</li>
        <li><b>screenLineNumbers</b> - How many lines has the OSD</li>
        <li><b>screenLineType01...08</b> - Which type has line 01...08? E.g. "directory", "Now playing", "current Artist",...</li>
        <li><b>screenName</b> - Name of the OSD</li>
        <li><b>screenReturnKey</b> - Is the "Return-Key" in this OSD available?</li>
        <li><b>screenTopMenuKey</b> - Is the "Menu-Key" in this OSD available?</li>
        <li><b>screenToolsKey</b> - Is the "Tools-Key" (Menu, edit, ipod control) in this OSD available?</li>
        <li><b>screenType</b> - Type of the OSD, e.g. "message", "List", "playing(play)",...</li>
        <li><b>speakerSystem</b> - Shows how the rear surround speaker connectors and the B-speaker connectors are used</li>
        <li><b>speakers</b> - Which speaker output connectors are active?</li>
        <li><b>standingWave</b> - Standing wave</li>
        <li>
            <b>state</b> - Is set while connecting from fhem to the  Pioneer AV Receiver (disconnected|innitialized|off|on|opened)
        </li>
        <li>
          <b>stateAV</b> - Status from user perspective combining readings presence, power, mute and playStatus to a useful overall status (on|off|absent|stopped|playing|paused|fast-forward|fast-rewind).
        </li>
        <li><b>tone</b> - Is the tone control turned on?</li>
        <li><b>treble</b> - Current value of treble</li>
        <li><b>tunerFrequency</b> - Tuner frequency</li>
        <li><b>volume</b> - Current value of volume (0%-100%)</li>
        <li><b>volumeStraight</b> - Current value of volume os displayed in the display of the Pioneer AV Receiver</li>
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
    <li><b>networkStandby <on|off></b> -  Schaltet Network standby ein oder aus. Um einen Pioneer AV Receiver mit diesem Modul aus dem Standby einzuschalten, muss Network Standby = on sein. Mit <code>set &lt;name&gt; networkStandby on</code> sollte sich das machen lassen.</li>
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
    liefert bei diesem Modul keine Werte zurück, sondern fragt den Pioneer AVR  nach dem aktuellen Status (z.B. der Lautstärke). Sobald der Pioneer AVR antwortet (die Zeit, bis der Pioneer AVR antwortet, ist nicht vorhersehbar), aktualisiert das Modul die Readings bzw. Internals des PioneerAVR devices.
    Falls unten keine Beschreibung für das "get-Kommando" angeführt ist, siehe gleichnamiges "Set-Kommando"
    <li><b>loadInputNames</b> - liest die Namen der Eingangsquellen vom Pioneer AV Receiver und überprüft, ob sie aktiviert sind</li>
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
    <li><b>avrModel</b> - Versucht vom Pioneer AV Receiver die Modellbezeichnung (z.B. VSX923) einzulesen und im gleichnamigen INTERNAL abzuspeichern</li>
    <li><b>mute</b> - </li>
    <li><b>networkPorts</b> - Versucht vom Pioneer AV Receiver die offenen Ethernet Ports einzulesen und als INTERNAL networkPort1 ... networkPort4 abzuspeichern</li>
    <li><b>networkSettings</b> - Versucht vom Pioneer AV Receiver die Netzwerkparameter (IP, Gateway, Netmask, Proxy, DHCP, DNS1, DNS2) einzulesen und in INTERNALS abzuspeichern</li>
    <li><b>networkStandby</b> - Versucht vom Pioneer AV Receiver den Parameter networkStandby (kann on oder off sein) einzulesen und als INTERNAL abzuspeichern</li>
    <li><b>power</b> - Versucht vom Pioneer AV Receiver in Erfahrung zu bringen, ob die Main Zone eingeschaltet oder in Standby ist.</li>
    <li><b>signalSelect</b> - </li>
    <li><b>softwareVersion</b> - Fragt den Pioneer AV Receiver nach der aktuell im Receiver verwendeten Software Version und speichert diese als INTERNAL</li>
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
    <li>
        <b>connectionCheck</b> &nbsp;&nbsp;1..120,off&nbsp;&nbsp; Pingt den Pioneer AV Receiver alle X Sekunden um den Datenverbindungsstatus zu überprüfen. Standard: 60 Sekunden.
    </li>
    <li>
        <b> timeout</b> &nbsp;&nbsp;1,2,3,4,5,7,10,15&nbsp;&nbsp;Zeit in Sekunden, innerhalb der der Pioneer AV Receiver auf einen Ping antwortet. Standard: 3 Sekunden.
    </li>
    <li>
        <b>statusUpdateStart &lt;enable|disable&gt;</b> - Ein-/Ausschalten des Status Updates (lesen aller Parameter vom Pioneer AV Receiver, dauert bis zu einer Minute) beim Start des Moduls. 
           Mit "disable" lässt sich das Status Update abschalten, FHEM startet schneller, das Pioneer Modul zeigt eventuell nicht korrekte readings.
    </li>
    <li><b>statusUpdateReconnect &lt;enable|disable&gt;</b> - Ein-/Ausschalten des Status Updates (lesen aller Parameter vom Pioneer AV Receiver, dauert bis zu einer Minute) nach dem Wiederherstellen der Datenverbindung zum Pioneer AV Receiver.
    Mit "disable" lässt sich das Status Update abschalten, FHEM bleibt reaktiver beim reconnect, das Pioneer Modul zeigt eventuell nicht korrekte readings.</li>
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
        <li><b>audioInputSignal</b> - Art des Inputsignals (z.B. ANALOG, PCM, DTS,...)</li>
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
        <li><b>inputsList</b> - Mit ":" getrennte Liste der aktivierten/verfügbaren Eingänge</li>
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
        <li><b>screenLineNumberFirst</b> - Lange Listen werden im OSD zu einzelnen Seiten mit je 8 Zeilen angezeigt. Die oberste Zeile im OSD repräsentiert welche Zeile in der gesamten Liste?</li>
        <li><b>screenLineNumberLast</b> - Lange Listen werden im OSD zu einzelnen Seiten mit je 8 Zeilen angezeigt. Die unterste Zeile im OSD repräsentiert welche Zeile in der gesamten Liste?</li>
        <li><b>screenLineNumbersTotal</b> - Wie viele Zeilen hat die im OSD anzuzeigende Liste insgesamt?</li>
        <li><b>screenLineNumbers</b> - Wie viele Zeilen hat das OSD</li>
        <li><b>screenLineType01...08</b> - Welchen Typs ist die Zeile 01...08? Z.B. "directory", "Now playing", "current Artist",...</li>
        <li><b>screenName</b> - Name des OSD</li>
        <li><b>screenReturnKey</b> - Steht die "Return-Taste" in diesem OSD zur Verfügung?</li>
        <li><b>screenTopMenuKey</b> - Steht die "Menu-Taste" in diesem OSD zur Verfügung?</li>
        <li><b>screenToolsKey</b> - Steht die "Tools-Taste" (Menu, Edit, iPod control) in diesem OSD zur Verfügung?</li>
        <li><b>screenType</b> - Typ des OSD, z.B. "message", "List", "playing(play)",...</li>
        <li><b>speakerSystem</b> - Zeigt, wie die hinteren Surround-Lautsprecheranschlüsse und die B-Lautsprecheranschlüsse verwendet werden</li>
        <li><b>speakers</b> - Welche Lautsprecheranschlüsse sind aktiviert?</li>
        <li><b>standingWave</b> - Einstellung der Steuerung stark resonanter tiefer Frequenzen im Hörraum</li>
        <li>
          <b>state</b> - Wird beim Verbindungsaufbau von Fhem mit dem Pioneer AV Receiver gesetzt. Mögliche Werte sind disconnected, innitialized, off, on, opened
        </li>
        <li>
          <b>stateAV</b> - Status aus der Sicht des USers: Kombiniert die readings presence, power, mute und playStatus zu einem Status (on|off|absent|stopped|playing|paused|fast-forward|fast-rewind).
        </li>
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
