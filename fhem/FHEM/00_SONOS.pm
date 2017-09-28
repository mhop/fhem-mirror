########################################################################################
#
# SONOS.pm (c) by Reiner Leins, July 2017
# rleins at lmsoft dot de
#
# $Id$
#
# FHEM module to commmunicate with a Sonos-System via UPnP
#
########################################################################################
# !ATTENTION!
# This Module needs additional Perl-Libraries.
# Install:
#  * LWP::Simple
#  * LWP::UserAgent
#  * HTTP::Request
#  * SOAP::Lite
# 
# e.g. as Debian-Packages (via "sudo apt-get install <packagename>")
#  * LWP::Simple-Packagename (incl. LWP::UserAgent and HTTP::Request): libwww-perl
#  * SOAP::Lite-Packagename: libsoap-lite-perl
#
# e.g. as Windows ActivePerl (via Perl-Packagemanager)
#  * Install Package LWP (incl. LWP::UserAgent and HTTP::Request)
#  * Install Package SOAP::Lite
#  * SOAP::Lite-Special for Versions after 5.18:
#    * Add another Packagesource from suggestions or manual: Bribes de Perl (http://www.bribes.org/perl/ppm)
#      * Install Package: SOAP::Lite
#
# Windows ActivePerl 5.20 does currently not work due to missing SOAP::Lite
#
########################################################################################
# Configuration:
# define <name> SONOS [<host:port> [interval [waittime [delaytime]]]]
#
# where <name> may be replaced by any fhem-devicename string 
# <host:port> is the connection identifier to the internal server. Normally "localhost" with a locally free port e.g. "localhost:4711".
# interval is the interval in s, for checking the existence of a ZonePlayer
# waittime is the time to wait for the subprocess. defaults to 8.
# delaytime is the time for delaying the network- and subprocess-part of this module. If the port is longer than neccessary blocked on the subprocess-side, it may be useful.
#
##############################################
# Example:
# Simplest way to define:
# define Sonos SONOS
#
# Example with control over the used port and the isalive-checker-interval:
# define Sonos SONOS localhost:4711 45
#
########################################################################################
# Changelog (last 4 entries only, see Wiki for complete changelog)
#
# SVN-History:
# 28.09.2017
#	Provider-Icons werden wieder korrekt ermittelt
#	Das Verarbeiten der Arbeitsschlange im SubProcess wurde optimiert
#	Die Fehlermeldung mit den redundanten Argumenten bei sprintf wurde umgestellt.
# 14.07.2017
#	Änderung in der ControlPoint.pm: Es wurden zuviele Suchantworten berücksichtigt.
#	Bei einem Modify wird von Fhem nur die DefFn aufgerufen (und nicht vorher UndefFn). Dadurch blieben Reste, die aber vor einer Definition aufgeräumt werden müssen. Resultat war eine 100%-CPU-Last.
# 09.07.2017
#	BulkUpdate: Beginn und Ende sind nun sicher davor einen vom SubProzess gestarteten BulkUpdate vorzeitig zu beenden.
# 05.07.2017
#	Neue Variante für das Ermitteln der laufenden Favoriten, Radios oder Playlists.
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################
# Use-Declarations
########################################################################################
package main;

use strict;
use warnings;

use Cwd qw(realpath);
use LWP::Simple;
use LWP::UserAgent;
use URI::Escape;
use HTML::Entities;
use Net::Ping;
use Socket;
use IO::Select;
use IO::Socket::INET;
use HTTP::Request::Common;
use File::Path;
use File::stat;
use Time::HiRes qw(usleep gettimeofday);
use Scalar::Util qw(reftype looks_like_number);
use PerlIO::encoding;
use Encode;
use feature 'unicode_strings';
use Digest::MD5 qw(md5_hex);
use File::Temp;
use File::Copy;
# use Encode::Guess;

use Data::Dumper;
$Data::Dumper::Terse = 1;

use threads;
use Thread::Queue;
use threads::shared;

use feature 'state';

# SmartMatch-Fehlermeldung unterdrücken...
no if $] >= 5.017011, warnings => 'experimental::smartmatch';


########################################################
# IP-Adressen, die vom UPnP-Modul ignoriert werden sollen.
# Diese können über ein Attribut gesetzt werden.
########################################################
my %ignoredIPs = ();
my %usedonlyIPs = ();
my $reusePort = 0;


########################################################
# Standards aus FHEM einbinden
########################################################
use vars qw{%attr %modules %defs %intAt %data};


########################################################
# Prozeduren für den Betrieb des Standalone-Parts
########################################################
sub Log($$);
sub Log3($$$);

sub SONOS_Log($$$);
sub SONOS_StartClientProcessIfNeccessary($);
sub SONOS_Client_Notifier($);
sub SONOS_Client_ConsumeMessage($$);
sub SONOS_RecursiveStructure($$$$);

sub SONOS_RCLayout();

sub SONOS_URI_Escape($);

########################################################
# Verrenkungen um in allen Situationen das benötigte 
# Modul sauber geladen zu bekommen..
########################################################
my $gPath = '';
BEGIN {
	$gPath = substr($0, 0, rindex($0, '/'));
}
if (lc(substr($0, -7)) eq 'fhem.pl') { 
	$gPath = $attr{global}{modpath}.'/FHEM'; 
}
use lib ($gPath.'/lib', $gPath.'/FHEM/lib', './FHEM/lib', './lib', './FHEM', './', '/usr/local/FHEM/share/fhem/FHEM/lib');
# print 'Current: "'.$0.'", gPath: "'.$gPath."\"\n";

if (lc(substr($0, -7)) eq 'fhem.pl') {
	require 'DevIo.pm';
} else {
	use UPnP::ControlPoint;
	
	########################################################
	# Change all carp-calls in the UPnP-Module to croak-calls
	# This will ensure you can "catch" carp with an enclosing
	# "eval{}"-Block
	########################################################
	#*UPnP::ControlPoint::carp = \&UPnP::ControlPoint::croak;
}


########################################################################################
# Variable Definitions
########################################################################################
my %gets = (
	'Groups' => ''
);

my %sets = (
	'Groups' => 'groupdefinitions',
	'StopAll' => '',
	'Stop' => '',
	'PauseAll' => '',
	'Pause' => '',
	'Mute' => 'state',
	'MuteOn' => '',
	'MuteOff' => '',
	'RescanNetwork' => '',
	'RefreshShareIndex' => '',
	'LoadBookmarks' => '[Groupname]',
	'SaveBookmarks' => '[GroupName]',
	'DisableBookmark' => 'groupname',
	'EnableBookmark' => 'groupname'
);

my @SONOS_PossibleDefinitions = qw(NAME INTERVAL);
my @SONOS_PossibleAttributes = qw(targetSpeakFileHashCache targetSpeakFileTimestamp targetSpeakDir targetSpeakURL targetSpeakMP3FileDir targetSpeakMP3FileConverter SpeakGoogleURL Speak0 Speak1 Speak2 Speak3 Speak4 SpeakCover Speak1Cover Speak2Cover Speak3Cover Speak4Cover minVolume maxVolume minVolumeHeadphone maxVolumeHeadphone getAlarms disable generateVolumeEvent buttonEvents generateProxyAlbumArtURLs proxyCacheTime bookmarkSaveDir bookmarkTitleDefinition bookmarkPlaylistDefinition coverLoadTimeout getListsDirectlyToReadings getFavouritesListAtNewVersion getPlaylistsListAtNewVersion getRadiosListAtNewVersion getQueueListAtNewVersion getTitleInfoFromMaster stopSleeptimerInAction saveSleeptimerInAction webname SubProcessLogfileName);
my @SONOS_PossibleReadings = qw(AlarmList AlarmListIDs UserID_Spotify UserID_Napster location SleepTimerVersion Mute OutputFixed HeadphoneConnected Balance Volume Loudness Bass Treble TruePlay SurroundEnable SurroundLevel SubEnable SubGain SubPolarity AudioDelay AudioDelayLeftRear AudioDelayRightRear NightMode DialogLevel AlarmListVersion ZonePlayerUUIDsInGroup ZoneGroupState ZoneGroupID fieldType IsBonded ZoneGroupName roomName roomNameAlias roomIcon currentTransportState transportState TransportState LineInConnected presence currentAlbum currentArtist currentTitle currentStreamAudio GroupVolume GroupMute FavouritesVersion RadiosVersion PlaylistsVersion QueueVersion QueueHash GroupMasterPlayer ShareIndexInProgress DirectControlClientID DirectControlIsSuspended DirectControlAccountID IsMaster MasterPlayer SlavePlayer ButtonState ButtonLockState AllPlayer LineInName LineInIcon MusicServicesListVersion MusicServicesList);

# Communication between the two "levels" of threads
my $SONOS_ComObjectTransportQueue = Thread::Queue->new();

my %SONOS_PlayerRestoreRunningUDN :shared = ();
my $SONOS_PlayerRestoreQueue = Thread::Queue->new();

# For triggering the Main-Thread over Telnet-Session
my $SONOS_Thread :shared = -1;
my $SONOS_Thread_IsAlive :shared = -1;
my $SONOS_Thread_PlayerRestore :shared = -1;

my %SONOS_Thread_IsAlive_Counter;
my $SONOS_Thread_IsAlive_Counter_MaxMerci = 2;

# Runtime Variables on Module-Level
my %SONOS_Module_BulkUpdateFromSubProcessInWork;

# Some Constants
my @SONOS_PINGTYPELIST = qw(none tcp udp icmp syn);
my $SONOS_DEFAULTPINGTYPE = 'syn';
my $SONOS_SUBSCRIPTIONSRENEWAL = 1800;
my $SONOS_USERAGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, likeGecko) Chrome/23.0.1271.64 Safari/537.11';
#my $SONOS_USERAGENT = 'Linux UPnP/1.0 Sonos/35.3-39010 (WDCR:Microsoft Windows NT 6.1.7601 Service Pack 1)';
my $SONOS_DIDLHeader = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">';
my $SONOS_DIDLFooter = '</DIDL-Lite>';
my $SONOS_GOOGLETRANSLATOR_URL = 'http://translate.google.com/translate_tts?tl=%1$s&client=tw-ob&q=%2$s'; # 1->Sprache, 2->Text
my $SONOS_GOOGLETRANSLATOR_CHUNKSIZE = 95;
my $SONOS_DEFAULTCOVERLOADTIMEOUT = 5;
my $SONOS_LISTELEMMASK = '[ \(\)\/\+\?\|\*\{\}\$\^\[\]\#]';

# Basis UPnP-Object und Search-Referenzen
my $SONOS_RestartControlPoint = 0;
my $SONOS_Controlpoint;
my $SONOS_Search;

# Devices merken
my %SONOS_UPnPDevice;

# ControlProxies für spätere Aufrufe für jeden ZonePlayer extra sichern
my %SONOS_AVTransportControlProxy;
my %SONOS_RenderingControlProxy;
my %SONOS_GroupRenderingControlProxy;
my %SONOS_ContentDirectoryControlProxy;
my %SONOS_AlarmClockControlProxy;
my %SONOS_AudioInProxy;
my %SONOS_DevicePropertiesProxy;
my %SONOS_GroupManagementProxy;
my %SONOS_MusicServicesProxy;
my %SONOS_ZoneGroupTopologyProxy;

# Subscriptions müssen für die spätere Erneuerung aufbewahrt werden
my %SONOS_TransportSubscriptions;
my %SONOS_RenderingSubscriptions;
my %SONOS_GroupRenderingSubscriptions;
my %SONOS_ContentDirectorySubscriptions;
my %SONOS_AlarmSubscriptions; 
my %SONOS_ZoneGroupTopologySubscriptions;
my %SONOS_DevicePropertiesSubscriptions;
my %SONOS_AudioInSubscriptions;
my %SONOS_MusicServicesSubscriptions;

# Bookmark-Daten
my %SONOS_BookmarkQueueHash;
my %SONOS_BookmarkTitleHash;
my %SONOS_BookmarkQueueDefinition;
my %SONOS_BookmarkTitleDefinition;

my %SONOS_BookmarkSpeicher;
$SONOS_BookmarkSpeicher{OldTracks} = ();
$SONOS_BookmarkSpeicher{NumTracks} = ();
$SONOS_BookmarkSpeicher{OldTrackURIs} = ();
$SONOS_BookmarkSpeicher{OldTitles} = ();
$SONOS_BookmarkSpeicher{OldTrackPositions} = ();
$SONOS_BookmarkSpeicher{OldTrackDurations} = ();
$SONOS_BookmarkSpeicher{OldTransportstate} = ();

# Locations -> UDN der einzelnen Player merken, damit die Event-Verarbeitung schneller geht
my %SONOS_Locations;

# Wenn der Prozess/das Modul nicht von fhem aus gestartet wurde, dann versuchen, den ersten Parameter zu ermitteln
# Für diese Funktionalität werden einige Variablen benötigt
my $SONOS_ListenPort = $ARGV[0] if (lc(substr($0, -7)) ne 'fhem.pl');
my $SONOS_Client_LogLevel :shared = -1;
if ($ARGV[1]) {
	$SONOS_Client_LogLevel = $ARGV[1];
}
my $SONOS_mseclog = 0;
if ($ARGV[2]) {
	$SONOS_mseclog = $ARGV[2];
}
my $SONOS_Client_LogfileName :shared = '-';
my $SONOS_StartedOwnUPnPServer = 0;
my $SONOS_Client_Selector;
my %SONOS_Client_Data :shared = ();
my $SONOS_Client_SendQueue = Thread::Queue->new();
my $SONOS_Client_SendQueue_Suspend :shared = 0;

my %SONOS_ButtonPressQueue;

########################################################################################
#
# SONOS_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################
sub SONOS_Initialize ($) {
	my ($hash) = @_;
	# Provider
	$hash->{Clients} = ':SONOSPLAYER:';
	
	# Normal Defines
	$hash->{DefFn} = 'SONOS_Define';
	$hash->{UndefFn} = 'SONOS_Undef';
	$hash->{DeleteFn} = 'SONOS_Delete';
	$hash->{ShutdownFn} = 'SONOS_Shutdown';
	$hash->{ReadFn} = "SONOS_Read";
	$hash->{ReadyFn} = "SONOS_Ready";
	$hash->{GetFn} = 'SONOS_Get';
	$hash->{SetFn} = 'SONOS_Set';
	$hash->{AttrFn} = 'SONOS_Attribute';
	$hash->{NotifyFn} = 'SONOS_Notify';
	
	# CGI
	my $name = "sonos";
	my $fhem_url = "/" . $name ;
	$data{FWEXT}{$fhem_url}{FUNC} = "SONOS_FhemWebCallback";
	$data{FWEXT}{$fhem_url}{LINK} = $name;
	$data{FWEXT}{$fhem_url}{NAME} = undef;
	
	eval {
		no strict;
		no warnings;
		$hash->{AttrList}= 'disable:1,0 pingType:'.join(',', @SONOS_PINGTYPELIST).' usedonlyIPs ignoredIPs targetSpeakDir targetSpeakURL targetSpeakFileTimestamp:1,0 targetSpeakFileHashCache:1,0 targetSpeakMP3FileDir targetSpeakMP3FileConverter SpeakGoogleURL Speak1 Speak2 Speak3 Speak4 SpeakCover Speak1Cover Speak2Cover Speak3Cover Speak4Cover generateProxyAlbumArtURLs:1,0 proxyCacheTime proxyCacheDir bookmarkSaveDir bookmarkTitleDefinition bookmarkPlaylistDefinition coverLoadTimeout:1,2,3,4,5,6,7,8,9,10,15,20,25,30 getListsDirectlyToReadings:1,0 getFavouritesListAtNewVersion:1,0 getPlaylistsListAtNewVersion:1,0 getRadiosListAtNewVersion:1,0 getQueueListAtNewVersion:1,0 deviceRoomView:Both,DeviceLineOnly reusePort:1,0 webname SubProcessLogfileName getLocalCoverArt '.$readingFnAttributes;
		use strict;
		use warnings;
	};
	
	$data{RC_layout}{Sonos} = "SONOS_RCLayout";
	$data{RC_layout}{SonosSVG_Buttons} = "SONOS_RCLayoutSVG1";
	$data{RC_layout}{SonosSVG_Icons} = "SONOS_RCLayoutSVG2";
	
	return undef;
}

########################################################################################
#
# SONOS_RCLayout - Returns the Standard-Layout-Definition for a RemoteControl-Device
#
########################################################################################
sub SONOS_RCLayout() {
	my @rows = ();
	
	push @rows, "Play:PLAY,Pause:PAUSE,Previous:REWIND,Next:FF,:blank,VolumeD:VOLDOWN,VolumeU:VOLUP,:blank,MuteT:MUTE,ShuffleT:SHUFFLE,RepeatT:REPEAT";
	push @rows, "attr rc_iconpath icons/remotecontrol";
	push @rows, "attr rc_iconprefix black_btn_";
	
	return @rows;
}

########################################################################################
#
# SONOS_RCLayoutSVG1 - Returns the Standard-Layout-Definition for a RemoteControl-Device
#
########################################################################################
sub SONOS_RCLayoutSVG1() {
	my @rows = ();
	
	push @rows, "Play:rc_PLAY.svg,Pause:rc_PAUSE.svg,Previous:rc_PREVIOUS.svg,Next:rc_NEXT.svg,:blank,VolumeD:rc_VOLDOWN.svg,VolumeU:rc_VOLUP.svg,:blank,MuteT:rc_MUTE.svg,ShuffleT:rc_SHUFFLE.svg,RepeatT:rc_REPEAT.svg";
	push @rows, "attr rc_iconpath icons/remotecontrol";
	push @rows, "attr rc_iconprefix black_btn_";
	
	return @rows;
}

########################################################################################
#
# SONOS_RCLayoutSVG2 - Returns the Standard-Layout-Definition for a RemoteControl-Device
#
########################################################################################
sub SONOS_RCLayoutSVG2() {
	my @rows = ();
	
	push @rows, "Play:audio_play.svg,Pause:audio_pause.svg,Previous:audio_rew.svg,Next:audio_ff.svg,:blank,VolumeD:audio_volume_low.svg,VolumeU:audio_volume_high.svg,:blank,MuteT:audio_volume_mute.svg,ShuffleT:audio_shuffle.svg,RepeatT:audio_repeat.svg";
	push @rows, "attr rc_iconpath icons/remotecontrol";
	push @rows, "attr rc_iconprefix black_btn_";
	
	return @rows;
}

########################################################################################
#
# SONOS_LoadExportedSonosBibliothek - Sets the internal Value with the given Name in the given fhem-device with the loaded file given with filename
#
########################################################################################
sub SONOS_LoadExportedSonosBibliothek($$$) {
	my ($fileName, $deviceName, $internalName) = @_;
	
	my $fileInhalt = '';
	
	open FILE, '<'.$fileName;
	binmode(FILE, ':encoding(utf-8)');
	while (<FILE>) {
		$fileInhalt .= $_;
	}
	close FILE;
	
	$defs{$deviceName}->{$internalName} = eval($fileInhalt);
}

########################################################################################
#
# SONOS_getCoverTitleRG - Returns the Cover- and Title-Readings for use in a ReadingsGroup
#
########################################################################################
sub SONOS_getCoverTitleRG($;$$) { 
	my ($device, $width, $space) = @_;
	$width = 500 if (!defined($width));
	
	my $transportState = ReadingsVal($device, 'transportState', '');
	my $presence = ReadingsVal($device, 'presence', 'disappeared');
	$presence = 'disappeared' if ($presence =~ m/~~NotLoadedMarker~~/i);
	
	my $currentRuntime = 1;
	my $currentStarttime = 0;
	my $currentPosition = 0;
	my $normalAudio = ReadingsVal($device, 'currentNormalAudio', 0);
	if ($normalAudio) {
		$currentRuntime = SONOS_GetTimeSeconds(ReadingsVal($device, 'currentTrackDuration', '0:00:01'));
		$currentRuntime = 1 if (!$currentRuntime || $currentRuntime == 0);
		
		$currentPosition = SONOS_GetTimeSeconds(ReadingsVal($device, 'currentTrackPosition', '0:00:00'));
		
		$currentStarttime = SONOS_GetTimeFromString(ReadingsTimestamp($device, 'currentTrackPosition', SONOS_TimeNow())) - $currentPosition;
	}
	
	my $playing = 0;
	if ($transportState eq 'PLAYING') {
		$playing = 1;
		$transportState = FW_makeImage('audio_play', 'Playing', 'SONOS_Transportstate');
	}
	$transportState = FW_makeImage('audio_pause', 'Paused', 'SONOS_Transportstate') if ($transportState eq 'PAUSED_PLAYBACK');
	$transportState = FW_makeImage('audio_stop', 'Stopped', 'SONOS_Transportstate') if ($transportState eq 'STOPPED');
	
	my $fullscreenDiv = '<style type="text/css">.SONOS_Transportstate { height: 0.8em; margin-top: -6px; margin-left: 2px; }</style><div id="cover_current'.$device.'" style="position: fixed; top: 0px; left: 0px; width: 100%; height: 100%; z-index: 10000; background-color: rgb(20,20,20);" onclick="document.getElementById(\'cover_current'.$device.'\').style.display = \'none\'; document.getElementById(\'global_fulldiv_'.$device.'\').innerHTML = \'\';"><div style="position: absolute; top: 10px; left: 5px; display: inline-block; height: 35px; width: 35px; background-image: url('.ReadingsVal($device, 'currentTrackProviderIconRoundURL', '').'); background-repeat: no-repeat; background-size: contain; background-position: center center;"></div><div style="width: 100%; top 5px; text-align: center; font-weight: bold; color: lightgray; font-size: 200%;">'.ReadingsVal($device, 'roomName', $device).$transportState.'</div><div style="position: relative; top: 8px; height: 86%; max-width: 100%; text-align: center;"><div style="display: inline-block; height: calc(100% - 70px); width: 100%; background-image: url('.((lc($presence) eq 'disappeared') ? '/'.AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'webname', 'fhem').'/sonos/cover/empty.jpg' : ReadingsVal($device, 'currentAlbumArtURL', '')).'); background-repeat: no-repeat; background-size: contain; background-position: center center;"/></div><div style="position: absolute; width: 100%; bottom: 8px; padding: 5px; text-align: center; font-weight: bold; color: lightgray; background-color: rgb(20,20,20); font-size: 120%;">'.((lc($presence) eq 'disappeared') ? 'Player disappeared' : ReadingsVal($device, 'infoSummarize1', '')).'</div><div id="hash_'.$device.'" style="display: none; color: white;">'.md5_hex(ReadingsVal($device, 'roomName', $device).ReadingsVal($device, 'infoSummarize2', '').ReadingsVal($device, 'currentTrackPosition', '').ReadingsVal($device, 'currentAlbumArtURL', '')).'</div>'.(($normalAudio) ? '<div id="prog_runtime_'.$device.'" style="display: none; color: white;">'.$currentRuntime.'</div><div id="prog_starttime_'.$device.'" style="display: none; color: white;">'.$currentStarttime.'</div><div id="prog_playing_'.$device.'" style="display: none; color: white;">'.$playing.'</div><div id="progress'.$device.'" style="position: absolute; bottom: 0px; width: 100%; height: 2px; border: 1px solid #000; overflow: hidden;"><div id="progressbar'.$device.'" style="width: '.(($currentPosition * 100) / $currentRuntime).'%; height: 2px; border-right: 1px solid #000000; background: #d65946;"></div></div>' : '').'</div>';
	
	my $javascriptTimer = 'function refreshTime'.$device.'() {
		var playing = document.getElementById("prog_playing_'.$device.'");
		if (!playing || (playing && (playing.innerHTML == "0"))) {
			return;
		}
		
		var runtime = document.getElementById("prog_runtime_'.$device.'");
		var starttime = document.getElementById("prog_starttime_'.$device.'");
		if (runtime && starttime) {
			var now = new Date().getTime();
			var percent = (Math.round(now / 10.0) -  Math.round(starttime.innerHTML * 100.0)) / runtime.innerHTML;
			document.getElementById("progressbar'.$device.'").style.width = percent + "%";
			
			setTimeout(refreshTime'.$device.', 100);
		}
	}';
	
	my $javascriptText = '<script type="text/javascript">
		if (!document.getElementById("global_fulldiv_'.$device.'")) {
			var newDiv = document.createElement("div");
			newDiv.setAttribute("id", "global_fulldiv_'.$device.'");
			document.body.appendChild(newDiv);
			
			var newScript = document.createElement("script");
			newScript.setAttribute("type", "text/javascript");
			newScript.appendChild(document.createTextNode(\'function refreshFull'.$device.'() {
				var fullDiv = document.getElementById("element_fulldiv_'.$device.'");
				if (!fullDiv) {
					return;
				}
				var elementHTML = decodeURIComponent(fullDiv.innerHTML);
				var global = document.getElementById("global_fulldiv_'.$device.'");
				var oldGlobal = global.innerHTML;
				
				var hash = document.getElementById("hash_'.$device.'");
				var hashMatch = /<div id="hash_'.$device.'".*?>(.+?)<.div>/i;
				hashMatch.exec(elementHTML);
				
				if ((oldGlobal != "") && (!hash || (hash.innerHTML != RegExp.$1))) {
					global.innerHTML = elementHTML;
				}
				
				if (oldGlobal != "") {
					setTimeout(refreshFull'.$device.', 1000);
					var playing = document.getElementById("prog_playing_'.$device.'");
					if (playing && playing.innerHTML == "1") {
						setTimeout(refreshTime'.$device.', 100);
					}
				}
			} '.$javascriptTimer.'\'));
			
			document.body.appendChild(newScript);
		}
	</script>';
	
	$javascriptText =~ s/\n/ /g;
	return $javascriptText.'<table cellpadding="0" cellspacing="0" style="padding: 0px; margin: 0px;"><tr><td valign="top" style="padding: 0px; margin: 0px;"><div style="" onclick="document.getElementById(\'global_fulldiv_'.$device.'\').innerHTML = \'&nbsp;\'; refreshFull'.$device.'(); '.($playing ? 'refreshTime'.$device.'();' : '').'">'.SONOS_getCoverRG($device).'</div><div style="display: none;" id="element_fulldiv_'.$device.'">'.SONOS_URI_Escape($fullscreenDiv).'</div></td><td valign="top" style="padding: 0px; margin: 0px;"><div style="margin-left: 0px; min-width: '.$width.'px;">'.SONOS_getTitleRG($device, $space).'</div></td></tr></table>';
}

########################################################################################
#
# SONOS_getCoverRG - Returns the Cover-Readings for use in a ReadingsGroup
#
########################################################################################
sub SONOS_getCoverRG($;$) {
	my ($device, $height) = @_;
	$height = '10.75em' if (!defined($height));
	
	my $presence = ReadingsVal($device, 'presence', 'disappeared');
	$presence = 'disappeared' if ($presence =~ m/~~NotLoadedMarker~~/i);
	
	return '<div informid="'.$device.'-display_coverrg"><div style="display: inline-block; margin-right: 5px; border: 1px solid lightgray; height: '.$height.'; width: '.$height.'; background-image: url('.((lc($presence) eq 'disappeared') ? '/'.AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'webname', 'fhem').'/sonos/cover/empty.jpg' : ReadingsVal($device, 'currentAlbumArtURL', '')).'); background-repeat: no-repeat; background-size: contain; background-position: center center;"><div style="position: relative; top: 0px; left: 2px; display: inline-block; height: 15px; width: 15px; background-image: url('.ReadingsVal($device, 'currentTrackProviderIconRoundURL', '').'); background-repeat: no-repeat; background-size: contain; background-position: center center;"></div></div></div>';
}

########################################################################################
#
# SONOS_getTitleRG - Returns the Title-Readings for use in a ReadingsGroup
#
########################################################################################
sub SONOS_getTitleRG($;$) {
	my ($device, $space) = @_;
	$space = '2.35em' if (!defined($space));
	$space .= 'px' if (looks_like_number($space));
	
	# Wenn der Player weg ist, nur eine Kurzinfo dazu anzeigen
	my $presence = ReadingsVal($device, 'presence', 'disappeared');
	$presence = 'disappeared' if ($presence =~ m/~~NotLoadedMarker~~/i);
	if (lc($presence) eq 'disappeared') {
		return '<div style="margin-left: 0px;">Player disappeared</div>';
	}
	
	my $infoString = '';
	
	my $transportState = ReadingsVal($device, 'transportState', '');
	$transportState = 'Spiele' if ($transportState eq 'PLAYING');
	$transportState = 'Pausiere' if ($transportState eq 'PAUSED_PLAYBACK');
	$transportState = 'Stop bei' if ($transportState eq 'STOPPED');
	
	my $source = ReadingsVal($device, 'currentSource', '');
	
	# Läuft Radio oder ein "normaler" Titel
	my $currentNormalAudio = ReadingsVal($device, 'currentNormalAudio', 1);
	$currentNormalAudio = 0 if (SONOS_Trim($currentNormalAudio) eq '');
	if ($currentNormalAudio == 1) {
		my $showNext = ReadingsVal($device, 'nextTitle', '') || ReadingsVal($device, 'nextArtist', '') || ReadingsVal($device, 'nextAlbum', '');
		$infoString = sprintf('<div style="display: inline-block; margin-left: 0px; vertical-align: top;">%1$s Titel %2$s von %3$s'.(($source) ? ' ~ <b>'.$source.'</b>' : '').'<br />Titel: <b>%4$s</b><br />Interpret: <b>%5$s</b><br />Album: <b>%6$s</b>'.($showNext ? '<div style="display: block; height: %7$s; display: table-cell; vertical-align: bottom;">Nächste Wiedergabe:</div><table cellpadding="0px" cellspacing="0px" style="padding: 0px; margin: 0px;"><tr><td valign="top" style="padding: 0px; margin: 0px;"><div style="display: inline-block; margin-left: 0px; margin-right: 5px; border: 1px solid lightgray; height: 3.5em; width: 3.5em; background-image: url(%8$s); background-repeat: no-repeat; background-size: contain; background-position: center center;"><div style="position: relative; top: -5px; left: 2px; display: inline-block; height: 10px; width: 10px; background-image: url(%9$s); background-repeat: no-repeat; background-size: contain; background-position: center center;"></div></div></td><td valign="top" style="padding: 0px; margin: 0px;"><div style="">Titel: %10$s<br />Interpret: %11$s<br />Album: %12$s</div></td></tr></table>' : '').'</div>',
				$transportState, 
				ReadingsVal($device, 'currentTrack', ''), 
				ReadingsVal($device, 'numberOfTracks', ''),
				ReadingsVal($device, 'currentTitle', ''),
				ReadingsVal($device, 'currentArtist', ''),
				ReadingsVal($device, 'currentAlbum', ''),
				$space,
				ReadingsVal($device, 'nextAlbumArtURL', ''),
				ReadingsVal($device, 'nextTrackProviderIconRoundURL', ''),
				ReadingsVal($device, 'nextTitle', ''),
				ReadingsVal($device, 'nextArtist', ''),
				ReadingsVal($device, 'nextAlbum', ''));
	} else {
		$infoString = sprintf('<div style="display: inline-block; margin-left: 0px;">%s Radiostream<br />Sender: <b>%s</b><br />Info: <b>%s</b><br />Läuft: <b>%s</b></div>',
				$transportState,
				ReadingsVal($device, 'currentSender', ''),
				ReadingsVal($device, 'currentSenderInfo', ''),
				ReadingsVal($device, 'currentSenderCurrent', ''));
	}
	
	return $infoString;
}

########################################################################################
#
# SONOS_getListRG - Returns the approbriate list-Reading for use in a ReadingsGroup
#
########################################################################################
sub SONOS_getListRG($$;$) {
	my ($device, $reading, $ul) = @_;
	$ul = 0 if (!defined($ul));
	
	my $resultString = '';
	
	# Manchmal ist es etwas komplizierter mit den Zeichensätzen...
	#my %elems = %{eval(decode('CP1252', ReadingsVal($device, $reading, '{}')))};
	my %elems = %{eval(ReadingsVal($device, $reading, '{}'))};
	
	for my $key (sort keys %elems) {
		my $command = '';
		if ($reading eq 'Favourites') {
			$command = 'cmd.'.$device.SONOS_URI_Escape('=set '.$device.' StartFavourite '.SONOS_URI_Escape($elems{$key}->{Title}));
		} elsif ($reading eq 'Playlists') {
			$command = 'cmd.'.$device.SONOS_URI_Escape('=set '.$device.' StartPlaylist '.SONOS_URI_Escape($elems{$key}->{Title}));
		} elsif ($reading eq 'Radios') {
			$command = 'cmd.'.$device.SONOS_URI_Escape('=set '.$device.' StartRadio '.SONOS_URI_Escape($elems{$key}->{Title}));
		} elsif ($reading eq 'Queue') {
			next if (($key eq 'Duration') || ($key eq 'DurationSec'));
			$command = 'cmd.'.$device.SONOS_URI_Escape('=set '.$device.' Track '.$elems{$key}->{Position});
		}
		$command = "FW_cmd('/fhem?XHR=1&$command')";
		
		if ($ul) {
			$resultString .= '<li style="list-style-type: none; display: inline;"><div style="display: inline-block; border: solid 1px lightgray; margin: 3px; width: 70px; height: 70px; background-image: url('.$elems{$key}->{Cover}.'); background-repeat: no-repeat; background-size: contain; background-position: center center;" onclick="'.$command.'"/></li>';
		} else {
			$resultString .= '<tr><td><div style="list-style-type: none; display: inline;"><div style="border: solid 1px lightgray; margin: 3px; width: 70px; height: 70px; background-image: url('.$elems{$key}->{Cover}.'); background-repeat: no-repeat; background-size: contain; background-position: center center;" /></td><td><a onclick="'.$command.'">'.(($reading eq 'Queue') ? $elems{$key}->{ShowTitle} : $elems{$key}->{Title})."</a></td></tr>\n";
		}
	}
	
	if ($ul) {
		return '<ul style="margin-left: 0px; padding-left: 0px; list-style-type: none; display: inline;">'.$resultString.'</ul>';
	} else {
		return '<table>'.$resultString.'</table>';
	}
}

########################################################################################
#
# SONOS_getGroupsRG -  Returns a simple group-constellation-list for use in a ReadingsGroup
#
########################################################################################
sub SONOS_getGroupsRG() {
	my $groups = CommandGet(undef, SONOS_getSonosPlayerByName()->{NAME}.' Groups');
	
	my $result = '<ul>';
	my $i = 0;
	while ($groups =~ m/\[(.*?)\]/ig) {
		my @member = split(/, /, $1);
		
		@member = map { my $elem = $_; $elem = FW_makeImage('icoSONOSPLAYER_icon-'.ReadingsVal($elem, 'playerType', '').'.png', '', '').ReadingsVal($elem, 'roomNameAlias', $elem); $elem; } @member;
		
		$result .= '<li>'.++$i.'. Gruppe:<ul style="list-style-type: none; padding-left: 0px;"><li>'.join('</li><li>', @member).'</li></ul></li>';
	}
	return $result.'</ul>';
}

########################################################################################
#
# SONOS_FhemWebCallback -  Implements a Webcallback e.g. a small proxy for Cover-images.
#
########################################################################################
sub SONOS_FhemWebCallback($) {
	my ($URL) = @_;
	
	SONOS_Log undef, 5, 'FhemWebCallback: '.$URL;
	
	# Einfache Grundprüfungen
	return ("text/html; charset=UTF8", 'Forbidden call: '.$URL) if ($URL !~ m/^\/sonos\//i);
	$URL =~ s/^\/sonos//i;
	
	# Proxy-Features...
	if ($URL =~ m/^\/proxy\//i) {
		return ("text/html; charset=UTF8", 'No Proxy configured: '.$URL) if (!AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'generateProxyAlbumArtURLs', 0));
		
		my $proxyCacheTime = AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'proxyCacheTime', 0);
		my $proxyCacheDir = AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'proxyCacheDir', '/tmp');
		$proxyCacheDir =~ s/\\/\//g;
		
		# Zurückzugebende Adresse ermitteln...
		my $albumurl = uri_unescape($1) if ($URL =~ m/^\/proxy\/aa\?url=(.*)/i);
		$albumurl =~ s/&apos;/'/ig;
		
		# Nur für Sonos-Player den Proxy spielen (und für Spotify-Links)
		my $ip = '';
		$ip = $1 if ($albumurl =~ m/^http:\/\/(.*?)[:\/]/i);
		for my $player (SONOS_getAllSonosplayerDevices()) {
			if (ReadingsVal($player->{NAME}, 'location', '') =~ m/^http:\/\/$ip:/i) {
				undef($ip);
				last;
			}
		}
		return ("text/html; charset=UTF8", 'Call for Non-Sonos-Player: '.$URL) 
			if (defined($ip) 
			&& $albumurl !~ /\.cloudfront.net\//i 
			&& $albumurl !~ /\.scdn.co\//i 
			&& $albumurl !~ /sonos-logo\.ws\.sonos\.com\//i 
			&& $albumurl !~ /\.tunein\.com/i 
			&& $albumurl !~ /\/music\/image\?/i);
		
		# Generierter Dateiname für die Cache-Funktionalitaet
		my $albumHash;
		
		# Schauen, ob die Datei aus dem Cache bedient werden kann...
		if ($proxyCacheTime) {
			eval {
				require Digest::SHA1;
				import Digest::SHA1 qw(sha1_hex);
				$albumHash = $proxyCacheDir.'/SonosProxyCache_'.sha1_hex(lc($albumurl)).'.image';
			};
			if ($@ =~ /Can't locate Digest\/SHA1.pm in/i) {
				# FallBack auf Digest::SHA durchführen...
				eval {
					require Digest::SHA;
					import Digest::SHA qw(sha1_hex);
					$albumHash = $proxyCacheDir.'/SonosProxyCache_'.sha1_hex(lc($albumurl)).'.image';
				};
			}
			if ($@ =~ /Wide character in subroutine entry/i) {
				eval {
					require Digest::SHA1;
					import Digest::SHA1 qw(sha1_hex);
					$albumHash = $proxyCacheDir.'/SonosProxyCache_'.sha1_hex(lc(encode("iso-8859-1", $albumurl, 0))).'.image';
				};
				
				if ($@ =~ /Can't locate Digest\/SHA1.pm in/i) {
					eval {
						require Digest::SHA;
						import Digest::SHA qw(sha1_hex);
						$albumHash = $proxyCacheDir.'/SonosProxyCache_'.sha1_hex(lc(encode("iso-8859-1", $albumurl, 0))).'.image';
					};
				}
			}
			if ($@) {
				SONOS_Log undef, 1, 'Problem while generating Hashvalue: '.$@;
				return(undef, undef);
			}
			
			if ((-e $albumHash) && ((stat($albumHash)->mtime) + $proxyCacheTime > gettimeofday())) {
				SONOS_Log undef, 5, 'Cover wird aus Cache bedient: '.$albumHash.' ('.$albumurl.')';
				
				$albumHash =~ m/(.*)\/(.*)\.(.*)/;
				FW_serveSpecial($2, $3, $1, 1);
				
				return(undef, undef);
			}
		}
		
		# Bild vom Player holen...
		my $ua = LWP::UserAgent->new(agent => $SONOS_USERAGENT);
		my $response = $ua->get($albumurl);
		if ($response->is_success) {
			SONOS_Log undef, 5, 'Cover wurde neu geladen: '.$albumurl;
			
			my $tempFile;
			if ($proxyCacheTime) {
				unlink $albumHash if (-e $albumHash);
				SONOS_Log undef, 5, 'Cover wird im Cache abgelegt: '.$albumHash.' ('.$albumurl.')';
			} else {
				# Da wir die Standard-Prozedur 'FW_serveSpecial' aus 'FHEMWEB' verwenden moechten, brauchen wir eine lokale Datei
				$tempFile = File::Temp->new(SUFFIX => '.image');
				$albumHash = $tempFile->filename;
				$albumHash =~ s/\\/\//g;
				SONOS_Log undef, 5, 'TempFilename: '.$albumHash;
			}
			
			# Either Tempfile or Cachefile...
			SONOS_WriteFile($albumHash, $response->content);
			
			$albumHash =~ m/(.*)\/(.*)\.(.*)/;
			FW_serveSpecial($2, $3, $1, 1);
			
			return (undef, undef);
		} else {
			SONOS_Log undef, 1, 'Cover couldn\'t be loaded "'.$albumurl.'": '.$response->status_line,;
			
			FW_serveSpecial('sonos_empty', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
	}
	
	# Cover-Features...
	if ($URL =~ m/^\/cover\//i) {
		$URL =~ s/^\/cover//i;
		
		SONOS_Log undef, 5, 'Cover: '.$URL;
		
		if ($URL =~ m/^\/leer.gif/i) {
			FW_serveSpecial('sonos_leer', 'gif', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/tunein_quadratic.jpg/i) {
			FW_serveSpecial('sonos_tunein_quadratic', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		if ($URL =~ m/^\/tunein_round.png/i) {
			FW_serveSpecial('sonos_tunein_round', 'png', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/bibliothek_quadratic.jpg/i) {
			FW_serveSpecial('sonos_bibliothek_quadratic', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		if ($URL =~ m/^\/bibliothek_round.png/i) {
			FW_serveSpecial('sonos_bibliothek_round', 'png', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/linein_quadratic.jpg/i) {
			FW_serveSpecial('sonos_linein_quadratic', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		if ($URL =~ m/^\/linein_round.png/i) {
			FW_serveSpecial('sonos_linein_round', 'png', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/dock_quadratic.jpg/i) {
			FW_serveSpecial('sonos_dock_quadratic', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		if ($URL =~ m/^\/dock_round.png/i) {
			FW_serveSpecial('sonos_dock_round', 'png', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/playbar_quadratic.jpg/i) {
			FW_serveSpecial('sonos_playbar_quadratic', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		if ($URL =~ m/^\/playbar_round.png/i) {
			FW_serveSpecial('sonos_playbar_round', 'png', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}

		
		if ($URL =~ m/^\/empty.jpg/i) {
			FW_serveSpecial('sonos_empty', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/playlist.jpg/i) {
			FW_serveSpecial('sonos_playlist', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/input_default.jpg/i) {
			FW_serveSpecial('sonos_input_default', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/input_tv.jpg/i) {
			FW_serveSpecial('sonos_input_tv', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
		
		if ($URL =~ m/^\/input_dock.jpg/i) {
			FW_serveSpecial('sonos_input_dock', 'jpg', $attr{global}{modpath}.'/FHEM/lib/UPnP', 1);
			return (undef, undef);
		}
	}
	
	# Wenn wir hier ankommen, dann konnte nichts verarbeitet werden...
	return ("text/html; charset=UTF8", 'Call failure: '.$URL);
}

########################################################################################
#
# SONOS_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed
#						def = definition string
#
########################################################################################
sub SONOS_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t]+", $def);
	
	# Check if we just want a modify...
	if ($hash->{NAME}) {
		SONOS_Log undef, 1, 'Modify Device: '.$hash->{NAME};
		
		# Alle Timer entfernen...
		RemoveInternalTimer($hash);
		
		# SubProzess beenden, und Verbindung kappen...
		SONOS_StopSubProcess($hash);
	}
	
	# check syntax
	return 'Usage: define <name> SONOS [[[[upnplistener] interval] waittime] delaytime]' if($#a < 1 || $#a > 5);
	my $name = $a[0];
	
	my $upnplistener;
	if ($a[2] && !looks_like_number($a[2])) {
		$upnplistener = $a[2];
	} else {
		$upnplistener = 'localhost:4711';
	}
	
	my $interval;
	if (looks_like_number($a[3])) {
		$interval = $a[3];
		if ($interval < 10) {
			SONOS_Log undef, 0, 'Interval has to be a minimum of 10 sec. and not: '.$interval;
			$interval = 10;
		}
	} else {
		$interval = 30;
	}
	
	my $waittime;
	if (looks_like_number($a[4])) {
		$waittime = $a[4];
	} else {
		$waittime = 8;
	}
	
	my $delaytime;
	if (looks_like_number($a[5])) {
		$delaytime = $a[5];
	} else {
		$delaytime = 0;
	}
	
	# Wir brauchen momentan nur die Notifies für global und jeden Sonosplayer...
	$hash->{NOTIFYDEV} = 'global';
	
	$hash->{NAME} = $name;
	$hash->{DeviceName} = $upnplistener;
	
	$hash->{INTERVAL} = $interval;
	$hash->{WAITTIME} = $waittime;
	$hash->{DELAYTIME} = $delaytime;
	$hash->{STATE} = 'waiting for subprocess...';
	
	if (AttrVal($hash->{NAME}, 'disable', 0) == 0) {
		if ($hash->{DELAYTIME}) {
			InternalTimer(gettimeofday() + $hash->{DELAYTIME}, 'SONOS_DelayStart', $hash, 0);
		} else {
			InternalTimer(gettimeofday() + 1, 'SONOS_DelayStart', $hash, 0);
		}
	}
	
	return undef;
}

########################################################################################
#
#  SONOS_DelayStart - Starts the SubProcess with a Delay. Can solute problems with blocked Ports
#
########################################################################################
sub SONOS_DelayStart($) {
	my ($hash) = @_;
	
	return undef if (AttrVal($hash->{NAME}, 'disable', 0));
	
	# Prüfen, ob ein Server erreichbar wäre, und wenn nicht, einen Server starten
	SONOS_StartClientProcessIfNeccessary($hash->{DeviceName});
	
	InternalTimer(gettimeofday() + $hash->{WAITTIME}, 'SONOS_DelayOpenDev', $hash, 0);
}

########################################################################################
#
#  SONOS_DelayOpenDev - Starts the IO-Connection with a Delay.
#
########################################################################################
sub SONOS_DelayOpenDev($) {
	my ($hash) = @_;
	
	# Die Datenverbindung zu dem gemachten Server hier starten und initialisieren
	DevIo_OpenDev($hash, 0, "SONOS_InitClientProcessLater");
}

########################################################################################
#
#  SONOS_Attribute - Implements AttrFn function 
#
########################################################################################
sub SONOS_Attribute($$$@) {
	my ($mode, $devName, $attrName, $attrValue) = @_;
	
	my $disableChange = 0;
	my @attrListToSubProcess = qw(getListsDirectlyToReadings);
	
	if ($mode eq 'set') {
		if ($attrName eq 'verbose') {
			SONOS_DoWork('undef', 'setVerbose', $attrValue);
		} elsif ($attrName eq 'SubProcessLogfileName') {
			SONOS_DoWork('undef', 'setLogfileName', $attrValue);
		} elsif (SONOS_isInList($attrName, @attrListToSubProcess)) {
			SONOS_DoWork('undef', 'setAttribute', $attrName, $attrValue);
		} elsif ($attrName eq 'disable') {
			if ($attrValue && AttrVal($devName, $attrName, 0) != 1) {
				SONOS_Log(undef, 5, 'Neu-Disabled');
				$disableChange = 1;
			}
			
			if (!$attrValue && AttrVal($devName, $attrName, 0) != 0) {
				SONOS_Log(undef, 5, 'Neu-Enabled');
				$disableChange = 1;
			}
		} elsif ($attrName eq 'deviceRoomView') {
			$modules{SONOSPLAYER}->{FW_addDetailToSummary} = ($attrValue =~ m/(Both)/i) if (defined($modules{SONOSPLAYER}));
		}
	} elsif ($mode eq 'del') {
		if ($attrName eq 'disable') {
			if (AttrVal($devName, $attrName, 0) != 0) {
				SONOS_Log(undef, 5, 'Deleted-Disabled');
				$disableChange = 1;
				$attrValue = 0;
			}
		} elsif ($attrName eq 'deviceRoomView') {
			$modules{SONOSPLAYER}->{FW_addDetailToSummary} = 1 if (defined($modules{SONOSPLAYER}));
		}
	}
	
	if ($disableChange) {
		my $hash = SONOS_getSonosPlayerByName();
		
		# Wenn der Prozess beendet werden muss...
		if ($attrValue) {
			SONOS_Log undef, 5, 'Call AttributeFn: Stop SubProcess...';
			
			InternalTimer(gettimeofday() + 1, 'SONOS_StopSubProcess', $hash, 0);
		}
		
		# Wenn der Prozess gestartet werden muss...
		if (!$attrValue) {
			SONOS_Log undef, 5, 'Call AttributeFn: Start SubProcess...';
			
			InternalTimer(gettimeofday() + 1, 'SONOS_DelayStart', $hash, 0);
		}
	}
	
	return undef;
}

########################################################################################
#
#  SONOS_StopSubProcess - Tries to stop the subprocess
#
########################################################################################
sub SONOS_StopSubProcess($) {
	my ($hash) = @_;
	
	# Den SubProzess beenden, wenn wir ihn selber gestartet haben
	if ($SONOS_StartedOwnUPnPServer) {
		# DevIo_OpenDev($hash, 1, undef);
		DevIo_SimpleWrite($hash, "shutdown\n", 2);
		DevIo_CloseDev($hash);
		setReadingsVal($hash, "state", 'disabled', TimeNow());
		$hash->{STATE} = 'disabled';
		
		# Alle SonosPlayer-Devices disappearen
		for my $player (SONOS_getAllSonosplayerDevices()) {
			SONOS_readingsBeginUpdate($player);
			SONOS_readingsBulkUpdateIfChanged($player, 'presence', 'disappeared');
			SONOS_readingsBulkUpdateIfChanged($player, 'state', 'disappeared');
			SONOS_readingsBulkUpdateIfChanged($player, 'transportState', 'STOPPED');
			SONOS_readingsEndUpdate($player, 1);
			
			if (AttrVal($player->{NAME}, 'stateVariable', '') eq 'Presence') {
				$player->{STATE} = 'disappeared';
			}
		}
	}
}

########################################################################################
#
#  SONOS_Notify - Implements NotifyFn function 
#
########################################################################################
sub SONOS_Notify() {
	my ($hash, $notifyhash) = @_;
	
	return if (AttrVal($hash->{NAME}, 'disable', 0));
	
	my $events = deviceEvents($notifyhash, 1);
	return if(!$events);
	
	foreach my $event (@{$events}) {
		next if(!defined($event));
		
		#SONOS_Log $hash->{UDN}, 0, 'Event: '.$notifyhash->{NAME}.'~'.$event;
		
		# Wenn der Benutzer das Kommando 'Save' ausgeführt hat, dann auch die Bookmarks sichern...
		if (($notifyhash->{NAME} eq 'global') && ($event eq 'SAVE')) {
			SONOS_DoWork('SONOS', 'SaveBookmarks', '');
		}
	}
	
	return undef;
}

########################################################################################
#
# SONOS_Ready - Implements ReadyFn function
# 
# Parameter hash = hash of device addressed
#
########################################################################################
sub SONOS_Ready($) {
	my ($hash) = @_;
	
	return DevIo_OpenDev($hash, 1, "SONOS_InitClientProcessLater");
}

########################################################################################
#
# SONOS_Read - Implements ReadFn function
# 
# Parameter hash = hash of device addressed
#
########################################################################################
sub SONOS_Read($) {
	my ($hash) = @_;
	
	# Checker erstmal deaktivieren...
	RemoveInternalTimer($hash, 'SONOS_IsSubprocessAliveChecker');
	
	return undef if AttrVal($hash->{NAME}, 'disable', 0);
	
	# Bis zum letzten (damit der Puffer leer ist) Zeilenumbruch einlesen, da SimpleRead immer nur kleine Päckchen einliest.
	my $buf = DevIo_SimpleRead($hash);
	
	# Wenn hier gar nichts gekommen ist, dann diesen Aufruf beenden...
	if (!defined($buf) || ($buf eq '')) {
		# Checker aktivieren...
		InternalTimer(gettimeofday() + $hash->{INTERVAL}, 'SONOS_IsSubprocessAliveChecker', $hash, 0);
		
		select(undef, undef, undef, 0.001);
		return undef;
	}
	
	# Wenn noch nicht alles gekommen ist, dann hier auf den Rest warten...
	while ($buf !~ m/\n$/) {
		my $newRead = DevIo_SimpleRead($hash);
		
		# Wenn hier gar nichts gekommen ist, dann diesen Aufruf beenden...
		if (!defined($newRead) || ($newRead eq '')) {
			# Checker aktivieren...
			InternalTimer(gettimeofday() + $hash->{INTERVAL}, 'SONOS_IsSubprocessAliveChecker', $hash, 0);
			
			return undef;
		}
		
		# Wenn es neue Daten gibt, dann anhängen...
		$buf .= $newRead;
	}
	
	# Die aktuellen Abspielinformationen werden Schritt für Schritt übertragen, gesammelt und dann in einem Rutsch ausgewertet.
	# Dafür eignet sich eine Sub-Statische Variable am Besten.
	state %current;
	
	# Hier könnte jetzt eine ganze Liste von Anweisungen enthalten sein, die jedoch einzeln verarbeitet werden müssen
	# Dabei kann der Trenner ein Zeilenumbruch sein, oder ein Tab-Zeichen.
	foreach my $line (split(/[\n\a]/, SONOS_Trim($buf))) {
		# Abschließende Zeilenumbrüche abschnippeln
		$line =~ s/[\r\n]*$//;
		
		SONOS_Log undef, 5, "Received from UPnP-Server: '$line'";
		
		# Hier empfangene Werte verarbeiten
		if ($line =~ m/^ReadingsSingleUpdateIfChanged:(.*?):(.*?):(.*)/) {
			if (lc($1) eq 'undef') {
				SONOS_readingsSingleUpdateIfChanged(SONOS_getSonosPlayerByName(), $2, $3, 1);
			} else {
				my $hash = SONOS_getSonosPlayerByUDN($1);
			
				if ($hash) {
					SONOS_readingsSingleUpdateIfChanged($hash, $2, $3, 1);
				} else {
					SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsSingleUpdateIfChanged: $1:$2:$3";
				}
			}
		} elsif ($line =~ m/^ReadingsSingleUpdateIfChangedNoTrigger:(.*?):(.*?):(.*)/) {
			if (lc($1) eq 'undef') {
				SONOS_readingsSingleUpdateIfChanged(SONOS_getSonosPlayerByName(), $2, $3, 0);
			} else {
				my $hash = SONOS_getSonosPlayerByUDN($1);
			
				if ($hash) {
					SONOS_readingsSingleUpdateIfChanged($hash, $2, $3, 0);
				} else {
					SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsSingleUpdateIfChangedNoTrigger: $1:$2:$3";
				}
			}
		} elsif ($line =~ m/^ReadingsSingleUpdate:(.*?):(.*?):(.*)/) {
			if (lc($1) eq 'undef') {
				SONOS_readingsSingleUpdate(SONOS_getSonosPlayerByName(), $2, $3, 1);
			} else {
				my $hash = SONOS_getSonosPlayerByUDN($1);
			
				if ($hash) {
					SONOS_readingsSingleUpdate($hash, $2, $3, 1);
				} else {
					SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsSingleUpdate: $1:$2:$3";
				}
			}
		} elsif ($line =~ m/^ReadingsBulkUpdate:(.*?):(.*?):(.*)/) {
			my $hash = undef;
			if (lc($1) eq 'undef') {
				$hash = SONOS_getSonosPlayerByName();
			} else {
				$hash = SONOS_getSonosPlayerByUDN($1);
			}
			
			if ($hash) {
				readingsBulkUpdate($hash, $2, $3);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsBulkUpdate: $1:$2:$3";
			}
		} elsif ($line =~ m/^ReadingsBulkUpdateIfChanged:(.*?):(.*?):(.*)/) {
			my $hash = undef;
			if (lc($1) eq 'undef') {
				$hash = SONOS_getSonosPlayerByName();
			} else {
				$hash = SONOS_getSonosPlayerByUDN($1);
			}
			
			if ($hash) {
				SONOS_readingsBulkUpdateIfChanged($hash, $2, $3);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsBulkUpdateIfChanged: $1:$2:$3";
			}
		} elsif ($line =~ m/ReadingsBeginUpdate:(.*)/) {
			my $hash = undef;
			if (lc($1) eq 'undef') {
				$hash = SONOS_getSonosPlayerByName();
			} else {
				$hash = SONOS_getSonosPlayerByUDN($1);
			}
			
			if ($hash) {
				SONOS_readingsBeginUpdate($hash, 1);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsBeginUpdate: $1";
			}
		} elsif ($line =~ m/ReadingsEndUpdate:(.*)/) {
			my $hash = undef;
			if (lc($1) eq 'undef') {
				$hash = SONOS_getSonosPlayerByName();
			} else {
				$hash = SONOS_getSonosPlayerByUDN($1);
			}
			
			if ($hash) {
				SONOS_readingsEndUpdate($hash, 1, 1);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von ReadingsEndUpdate: $1";
			}
		} elsif ($line =~ m/CommandDefine:(.*)/) {
			CommandDefine(undef, $1);
		} elsif ($line =~ m/CommandAttr:(.*)/) {
			CommandAttr(undef, $1);
		} elsif ($line =~ m/CommandAttrWithUDN:(.*?):(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			
			CommandAttr(undef, $hash->{NAME}.' '.$2);
		} elsif ($line =~ m/CommandDeleteAttr:(.*)/) {
			CommandDeleteAttr(undef, $1);
		} elsif ($line =~ m/deleteCurrentNextTitleInformationAndDisappear:(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			
			# Start the updating...
			SONOS_readingsBeginUpdate($hash);
			
			# Updating...
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTrack", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackURI", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackHandle", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentEnqueuedTransportURI", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentEnqueuedTransportHandle", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackDuration", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackDurationSec", '');
			readingsBulkUpdate($hash, "currentTrackPosition", '');
			readingsBulkUpdate($hash, "currentTrackPositionSec", 0);
			SONOS_readingsBulkUpdateIfChanged($hash, "currentTitle", 'Disappeared');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentArtist", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentSource", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbum", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentOriginalTrackNumber", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbumArtist", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbumArtURL", '/'.AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'webname', 'fhem').'/sonos/cover/empty.jpg');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentSender", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentSenderCurrent", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentSenderInfo", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "currentStreamAudio", 0);
			SONOS_readingsBulkUpdateIfChanged($hash, "currentNormalAudio", 1);
			SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackDuration", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackDurationSec", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackURI", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackHandle", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextTitle", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextArtist", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbum", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbumArtist", '');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbumArtURL", '/'.AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'webname', 'fhem').'/sonos/cover/empty.jpg');
			SONOS_readingsBulkUpdateIfChanged($hash, "nextOriginalTrackNumber", '');
			
			# End the Bulk-Update, and trigger events...
			SONOS_readingsEndUpdate($hash, 1);
		} elsif ($line =~ m/GetReadingsToCurrentHash:(.*?):(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			
			if ($hash) {
				%current = SONOS_GetReadingsToCurrentHash($hash->{NAME}, $2);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von GetReadingsToCurrentHash: $1:$2";
			}
		} elsif ($line =~ m/SetCurrent:(.*?):(.*)/) {
			$current{$1} = $2;
		} elsif ($line =~ m/CurrentBulkUpdate:(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			
			if ($hash) {
				SONOS_readingsBeginUpdate($hash);
				my $oldTransportState = ReadingsVal($hash->{NAME}, 'transportState', 0);
				my $oldTrackHandle = ReadingsVal($hash->{NAME}, 'currentTrackHandle', '');
				my $oldTrack = ReadingsVal($hash->{NAME}, 'currentTrack', '');
				my $oldTrackPosition = ReadingsVal($hash->{NAME}, 'currentTrackPosition', '');
				
				# Wurden für das Device bereits Favoriten geladen? Dann raussuchen, ob gerade ein solcher abgespielt wird...
				$current{FavouriteName} = '';
				eval {
					my $readingsValue = ReadingsVal($hash->{NAME}, 'Favourites', '');
					if ($readingsValue ne '') {
						my %favourites = %{eval($readingsValue)};
						while (my ($key, $value) = each (%favourites)) {
							if (defined($current{EnqueuedTransportURI}) && defined($value->{Ressource})) {
								if ($value->{Ressource} eq $current{EnqueuedTransportURI}) {
									$current{FavouriteName} = $value->{Title};
								}
							}
						}
					}
				};
				if ($@) {
					SONOS_Log $hash->{UDN}, 1, "Error during retreiving of FavouriteName: $@";
				}
				
				# Wurden für das Device bereits Playlisten geladen? Dann raussuchen, ob gerade eine solche abgespielt wird...
				$current{PlaylistName} = '';
				eval {
					my $readingsValue = ReadingsVal($hash->{NAME}, 'Playlists', '');
					if ($readingsValue ne '') {
						my %playlists = %{eval($readingsValue)};
						while (my ($key, $value) = each (%playlists)) {
							if (defined($current{EnqueuedTransportURI}) && defined($value->{Ressource})) {
								if ($value->{Ressource} eq $current{EnqueuedTransportURI}) {
									$current{PlaylistName} = $value->{Title};
								}
							}
						}
					}
				};
				if ($@) {
					SONOS_Log $hash->{UDN}, 1, "Error during retreiving of PlaylistName: $@";
				}
				
				# Wurden für das Device bereits Radios geladen? Dann raussuchen, ob gerade ein solches abgespielt wird...
				$current{RadioName} = '';
				eval {
					my $readingsValue = ReadingsVal($hash->{NAME}, 'Radios', '');
					if ($readingsValue ne '') {
						my %radios = %{eval($readingsValue)};
						while (my ($key, $value) = each (%radios)) {
							if (defined($current{EnqueuedTransportURI}) && defined($value->{Ressource})) {
								if ($value->{Ressource} eq $current{EnqueuedTransportURI}) {
									$current{RadioName} = $value->{Title};
								}
							}
						}
					}
				};
				if ($@) {
					SONOS_Log $hash->{UDN}, 1, "Error during retreiving of RadioName: $@";
				}
				
				# Dekodierung durchführen
				$current{Title} = decode_entities($current{Title});
				$current{Artist} = decode_entities($current{Artist});
				$current{Album} = decode_entities($current{Album});
				$current{AlbumArtist} = decode_entities($current{AlbumArtist});
				
				$current{Sender} = decode_entities($current{Sender});
				$current{SenderCurrent} = decode_entities($current{SenderCurrent});
				$current{SenderInfo} = decode_entities($current{SenderInfo});
				
				$current{nextTitle} = decode_entities($current{nextTitle});
				$current{nextArtist} = decode_entities($current{nextArtist});
				$current{nextAlbum} = decode_entities($current{nextAlbum});
				$current{nextAlbumArtist} = decode_entities($current{nextAlbumArtist});
			
				SONOS_readingsBulkUpdateIfChanged($hash, "transportState", $current{TransportState});
				SONOS_readingsBulkUpdateIfChanged($hash, "Shuffle", $current{Shuffle});
				SONOS_readingsBulkUpdateIfChanged($hash, "Repeat", $current{Repeat});
				SONOS_readingsBulkUpdateIfChanged($hash, "RepeatOne", $current{RepeatOne});
				SONOS_readingsBulkUpdateIfChanged($hash, "CrossfadeMode", $current{CrossfadeMode});
				SONOS_readingsBulkUpdateIfChanged($hash, "SleepTimer", $current{SleepTimer});
				SONOS_readingsBulkUpdateIfChanged($hash, "AlarmRunning", $current{AlarmRunning});
				SONOS_readingsBulkUpdateIfChanged($hash, "AlarmRunningID", $current{AlarmRunningID});
				SONOS_readingsBulkUpdateIfChanged($hash, "DirectControlClientID", $current{DirectControlClientID});
				SONOS_readingsBulkUpdateIfChanged($hash, "DirectControlIsSuspended", $current{DirectControlIsSuspended});
				SONOS_readingsBulkUpdateIfChanged($hash, "DirectControlAccountID", $current{DirectControlAccountID});
				SONOS_readingsBulkUpdateIfChanged($hash, "numberOfTracks", $current{NumberOfTracks});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrack", $current{Track});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackURI", $current{TrackURI});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackHandle", $current{TrackHandle});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentEnqueuedTransportURI", $current{EnqueuedTransportURI});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentEnqueuedTransportHandle", $current{EnqueuedTransportHandle});
				
				SONOS_readingsBulkUpdateIfChanged($hash, "currentFavouriteName", $current{FavouriteName});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentPlaylistName", $current{PlaylistName});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentRadioName", $current{RadioName});
				
				if (AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'getListsDirectlyToReadings', 0)) {
					my $val = $current{FavouriteName};
					$val =~ s/[ \(\)]/\./g;
					SONOS_readingsBulkUpdateIfChanged($hash, "currentFavouriteNameMasked", $val);
					
					$val = $current{PlaylistName};
					$val =~ s/[ \(\)]/\./g;
					SONOS_readingsBulkUpdateIfChanged($hash, "currentPlaylistNameMasked", $val);
					
					$val = $current{RadioName};
					$val =~ s/[ \(\)]/\./g;
					SONOS_readingsBulkUpdateIfChanged($hash, "currentRadioNameMasked", $val);
				}
				
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackDuration", $current{TrackDuration});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackDurationSec", $current{TrackDurationSec});
				
				if ($current{StreamAudio} && ($oldTransportState eq $current{TransportState})) {
					SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackPosition", '0:00:00');
					SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackPositionSec", '0');
				} else {
					readingsBulkUpdate($hash, "currentTrackPosition", $current{TrackPosition});
					readingsBulkUpdate($hash, "currentTrackPositionSec", $current{TrackPositionSec});
				}
				
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackProvider", $current{TrackProvider});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackProviderIconQuadraticURL", $current{TrackProviderIconQuadraticURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTrackProviderIconRoundURL", $current{TrackProviderIconRoundURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentTitle", $current{Title});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentArtist", $current{Artist});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentSource", $current{Source});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbum", $current{Album});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentOriginalTrackNumber", $current{OriginalTrackNumber});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbumArtist", $current{AlbumArtist});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentAlbumArtURL", $current{AlbumArtURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentSender", $current{Sender});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentSenderCurrent", $current{SenderCurrent});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentSenderInfo", $current{SenderInfo});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentStreamAudio", $current{StreamAudio});
				SONOS_readingsBulkUpdateIfChanged($hash, "currentNormalAudio", $current{NormalAudio});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackDuration", $current{nextTrackDuration});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackDurationSec", $current{nextTrackDurationSec});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackURI", $current{nextTrackURI});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackHandle", $current{nextTrackHandle});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackProvider", $current{nextTrackProvider});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackProviderIconQuadraticURL", $current{nextTrackProviderIconQuadraticURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTrackProviderIconRoundURL", $current{nextTrackProviderIconRoundURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextTitle", $current{nextTitle});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextArtist", $current{nextArtist});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbum", $current{nextAlbum});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbumArtist", $current{nextAlbumArtist});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextAlbumArtURL", $current{nextAlbumArtURL});
				SONOS_readingsBulkUpdateIfChanged($hash, "nextOriginalTrackNumber", $current{nextOriginalTrackNumber});
				SONOS_readingsBulkUpdateIfChanged($hash, "Volume", $current{Volume});
				SONOS_readingsBulkUpdateIfChanged($hash, "Mute", $current{Mute});
				SONOS_readingsBulkUpdateIfChanged($hash, "Balance", $current{Balance});
				SONOS_readingsBulkUpdateIfChanged($hash, "HeadphoneConnected", $current{HeadphoneConnected});
				
				my $name = $hash->{NAME};
				
				# If the SomethingChanged-Event should be triggered, do so. It's useful if one would be triggered if even some changes are made, and it's unimportant to exactly know what
				if (AttrVal($name, 'generateSomethingChangedEvent', 0) == 1) {
					readingsBulkUpdate($hash, "somethingChanged", 1);
				}
				
				# If the Info-Summarize is configured to be triggered. Here one can define a single information-line with all the neccessary informations according to the type of Audio
				SONOS_ProcessInfoSummarize($hash, \%current, 'InfoSummarize1', 1);
				SONOS_ProcessInfoSummarize($hash, \%current, 'InfoSummarize2', 1);
				SONOS_ProcessInfoSummarize($hash, \%current, 'InfoSummarize3', 1);
				SONOS_ProcessInfoSummarize($hash, \%current, 'InfoSummarize4', 1);
				
				# Zusätzlich noch den STATE und das Reading State mit dem vom Anwender gewünschten Wert aktualisieren, Dabei müssen aber doppelte Anführungszeichen vorher maskiert werden...
				SONOS_readingsBulkUpdateIfChanged($hash, 'state', $current{AttrVal($name, 'stateVariable', 'TransportState')});
			  
				# End the Bulk-Update, and trigger events
				SONOS_readingsEndUpdate($hash, 1);
				
				# Wenn es ein Dock ist, dann noch jeden abspielenden Player mit aktualisieren
				if (ReadingsVal($hash->{NAME}, 'playerType', '') eq 'WD100') {
					my $shortUDN = $1 if ($hash->{UDN} =~ m/(.*)_MR/);
					for my $elem (SONOS_getAllSonosplayerDevices()) {
						# Wenn es ein Player ist, der gerade das Dock wiedergibt, dann diesen Befüllen...
						if (ReadingsVal($elem->{NAME}, 'currentTrackURI', '') eq 'x-sonos-dock:'.$shortUDN) {
							# Alte Werte holen, muss komplett sein, um infoSummarize füllen zu können
							my %currentElem = SONOS_GetReadingsToCurrentHash($elem->{NAME}, 0);
							$currentElem{Title} = $current{Title};
							$currentElem{Artist} = $current{Artist};
							$currentElem{Album} = $current{Album};
							$currentElem{AlbumArtist} = $current{AlbumArtist};
							$currentElem{Track} = $current{Track};
							$currentElem{NumberOfTracks} = $current{NumberOfTracks};
							$currentElem{TrackDuration} = $current{TrackDuration};
							$currentElem{TrackDurationSec} = $current{TrackDurationSec};
							$currentElem{TrackPosition} = $current{TrackPosition};
							$currentElem{TrackProvider} = $current{TrackProvider};
							$currentElem{TrackProviderIconQuadraticURL} = $current{TrackProviderIconQuadraticURL};
							$currentElem{TrackProviderIconRoundURL} = $current{TrackProviderIconRoundURL};
							
							# Loslegen
							SONOS_readingsBeginUpdate($elem);
							
							# Neue Werte setzen
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTitle", $currentElem{Title});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentArtist", $currentElem{Artist});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentAlbum", $currentElem{Album});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentAlbumArtist", $currentElem{AlbumArtist});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrack", $currentElem{Track});
							SONOS_readingsBulkUpdateIfChanged($elem, "numberOfTracks", $currentElem{NumberOfTracks});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrackDuration", $currentElem{TrackDuration});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrackDurationSec", $currentElem{TrackDurationSec});
							readingsBulkUpdate($elem, "currentTrackPosition", $currentElem{TrackPosition});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrackProvider", $currentElem{TrackProvider});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrackProviderIconQuadraticURL", $currentElem{TrackProviderIconQuadraticURL});
							SONOS_readingsBulkUpdateIfChanged($elem, "currentTrackProviderIconRoundURL", $currentElem{TrackProviderIconRoundURL});
							
							if (AttrVal($elem->{NAME}, 'generateSomethingChangedEvent', 0) == 1) {
								readingsBulkUpdate($elem, "somethingChanged", 1);
							}
							
							# InfoSummarize befüllen
							SONOS_ProcessInfoSummarize($elem, \%currentElem, 'InfoSummarize1', 1);
							SONOS_ProcessInfoSummarize($elem, \%currentElem, 'InfoSummarize2', 1);
							SONOS_ProcessInfoSummarize($elem, \%currentElem, 'InfoSummarize3', 1);
							SONOS_ProcessInfoSummarize($elem, \%currentElem, 'InfoSummarize4', 1);
							
							# State-Reading befüllen
							SONOS_readingsBulkUpdateIfChanged($elem, 'state', $currentElem{AttrVal($elem->{NAME}, 'stateVariable', 'TransportState')});
							
							# Alles verarbeiten lassen
							SONOS_readingsEndUpdate($elem, 1);
						}
					}
				}
				
				# SimulatedValues aktualisieren, wenn ein Wechsel des Titels stattgefunden hat, und gerade keine Wiedergabe erfolgt...
				if (($current{TransportState} ne 'PLAYING')
					&& (($oldTrackHandle ne $current{TrackHandle})
						|| ($oldTrack != $current{Track})
						|| ($oldTrackPosition ne $current{TrackPosition}))) {
					SONOSPLAYER_SimulateCurrentTrackPosition($hash);
				}
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von CurrentBulkUpdate: $1";
			}
		} elsif ($line =~ m/PropagateTitleInformationsToSlaves:(.*)/) {
			my $hash = SONOS_getSonosPlayerByName($1);
			
			SONOS_PropagateTitleInformationsToSlaves($hash);
		} elsif ($line =~ m/PropagateTitleInformationsToSlave:(.*?):(.*)/) {
			my $hash = SONOS_getSonosPlayerByName($1);
			
			SONOS_PropagateTitleInformationsToSlave($hash, $2);
		} elsif ($line =~ m/ProcessCover:(.*?):(.*?):(.*?):(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			if ($hash) {
				my $name = $hash->{NAME};
				
				my $nextReading = 'current';
				my $nextName = '';
				if ($2) {
					$nextReading = 'next';
					$nextName = 'Next';
				}
					
				my $tempURI = $3;
				my $groundURL = $4;
				my $currentValue;
			
				my $srcURI = '';
				my $getLocalCoverArt = AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'getLocalCoverArt', 0);
				if (defined($tempURI) && $tempURI ne '') {
					if ($tempURI =~ m/getaa.*?x-sonos-spotify%3aspotify%3atrack%3a(.*)%3f/i) {
						my $infos = SONOS_getSpotifyCoverURL($1);
						if ($infos ne '') {
							$srcURI = $infos;
							
							if ($getLocalCoverArt) {
								$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.jpg';
								SONOS_Log undef, 4, "Transport-Event: Spotify-Bilder-Download: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
							}
						} else {
							$srcURI = $groundURL.$tempURI;
							
							if ($getLocalCoverArt) {
								$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.'.SONOS_ImageDownloadTypeExtension($groundURL.$tempURI);
								SONOS_Log undef, 4, "Transport-Event: Spotify-Bilder-Download failed. Use normal thumbnail: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
							}
						}
					} elsif ($tempURI =~ m/getaa.*?x-sonosapi-stream%3a(.+?)%3f/i) {
						$srcURI = SONOS_GetRadioMediaMetadata($hash->{UDN}, $1);
						eval {
							my $result = SONOS_ReadURL($srcURI);
							if (!defined($result) || ($result =~ m/<Error>.*<\/Error>/i)) {
								$srcURI = $groundURL.$tempURI;
							}
						};
						
						if ($getLocalCoverArt) {
							$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.png';
							SONOS_Log undef, 4, "Transport-Event: Radiocover-Download: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
						}
					} elsif ($tempURI =~ m/^\/fhem\/sonos\/cover\/(.*)/i) {
						$srcURI = $attr{global}{modpath}.'/FHEM/lib/UPnP/sonos_'.$1;
						
						if ($getLocalCoverArt) {
							$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.jpg';
							SONOS_Log undef, 4, "Transport-Event: Cover-Copy: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
						}
					} else {
						$srcURI = $groundURL.$tempURI;
						
						if ($getLocalCoverArt) {
							$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.'.SONOS_ImageDownloadTypeExtension($groundURL.$tempURI);
							SONOS_Log undef, 4, "Transport-Event: Bilder-Download: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
						}
					}
				} else {
					$srcURI = $attr{global}{modpath}.'/FHEM/lib/UPnP/sonos_empty.jpg';
					
					if ($getLocalCoverArt) {
						$currentValue = $attr{global}{modpath}.'/www/images/default/SONOSPLAYER/'.$name.'_'.$nextName.'AlbumArt.png';
						SONOS_Log undef, 4, "Transport-Event: CoverArt konnte nicht gefunden werden. Verwende FHEM-Logo. Bilder-Download: SONOS_DownloadReplaceIfChanged('$srcURI', '".$currentValue."');";
					}
				}
				
				my $filechanged = 0;
				if ($getLocalCoverArt) {
					mkpath($attr{global}{modpath}.'/www/images/default/SONOSPLAYER/');
					$filechanged = SONOS_DownloadReplaceIfChanged($srcURI, $currentValue);
					# Icons neu einlesen lassen, falls die Datei neu ist
					SONOS_RefreshIconsInFHEMWEB('/www/images/default/SONOSPLAYER/') if ($filechanged);
					SONOS_Log undef, 4, 'Transport-Event: CoverArt wurde geladen...';
				} else {
					SONOS_Log undef, 4, 'Transport-Event: CoverArt wurde nicht geladen, weil das Attribut "getLocalCoverArt" nicht gesetzt ist...';
				}
				
				# Die URL noch beim aktuellen Titel mitspeichern
				my $URL = $srcURI;
				if ($URL =~ m/\/lib\/UPnP\/sonos_(.*)/i) {
					$URL = '/'.AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'webname', 'fhem').'/sonos/cover/'.$1;
				} else {
					my $sonosName = SONOS_getSonosPlayerByName()->{NAME};
					$URL = '/'.AttrVal($sonosName, 'webname', 'fhem').'/sonos/proxy/aa?url='.SONOS_URI_Escape($URL) if (AttrVal($sonosName, 'generateProxyAlbumArtURLs', 0));
				}
				
				if ($nextReading eq 'next') {
					$current{nextAlbumArtURL} = $URL;
				} else {
					$current{AlbumArtURL} = $URL;
				}
				
				# This URI change rarely, but the File itself change nearly with every song, so trigger it everytime the content was different to the old one
				if ($getLocalCoverArt) {
					if ($filechanged) {
						SONOS_readingsSingleUpdate($hash, $nextReading.'AlbumArtURI', $currentValue, 1);
					} else {
						SONOS_readingsSingleUpdateIfChanged($hash, $nextReading.'AlbumArtURI', $currentValue, 1);
					}
				}
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von ProcessCover: $1:$2:$3:$4";
			}
		} elsif ($line =~ m/^SetAlarm:(.*?):(.*?);(.*?):(.*)/) {
			my $hash = SONOS_getSonosPlayerByUDN($1);
			
			my @alarmIDs = split(/,/, $3);
			
			if ($4) {
				SONOS_readingsSingleUpdate($hash, 'AlarmList', $4, 0);
			} else {
				SONOS_readingsSingleUpdate($hash, 'AlarmList', '{}', 0);
			}
			SONOS_readingsSingleUpdateIfChanged($hash, 'AlarmListIDs', join(',', sort {$a <=> $b} @alarmIDs), 0);
			SONOS_readingsSingleUpdateIfChanged($hash, 'AlarmListVersion', $2, 1);
		} elsif ($line =~ m/DoWorkAnswer:(.*?):(.*?):(.*)/) {
			my $chash;
			if (lc($1) eq 'undef') {
				$chash = SONOS_getSonosPlayerByName();
			} else {
				$chash = SONOS_getSonosPlayerByUDN($1);
			}
			
			if ($chash) {
				SONOS_Log undef, 4, "DoWorkAnswer arrived for ".$chash->{NAME}."->$2: '$3'";
				SONOS_readingsSingleUpdate($chash, $2, $3, 1);
			} else {
				SONOS_Log undef, 0, "Fehlerhafter Aufruf von DoWorkAnswer: $1:$2:$3";
			}
		} elsif ($line =~ m/rePing:/) {
			# Zunächst mal nichts weiter tun, hier geht es nur um die Aktualisierung der letzten Prozessantwort...
		} else {
			SONOS_DoTriggerInternal('Main', $line);
		}
	}
	
	# LastAnswer aktualisieren...
	SONOS_readingsSingleUpdate(SONOS_getSonosPlayerByName(), 'LastProcessAnswer', SONOS_TimeNow(), 1);
	
	# Checker aktivieren...
	InternalTimer(gettimeofday() + $hash->{INTERVAL}, 'SONOS_IsSubprocessAliveChecker', $hash, 0);
}

########################################################################################
#
# SONOS_PropagateTitleInformationsToSlaves - Propagates the Titleinformations to all Slaveplayers
#
# Parameter hash = Hash of the MasterPlayer
#
########################################################################################
sub SONOS_PropagateTitleInformationsToSlaves($) {
	my ($hash) = @_;
	
	SONOS_Log $hash->{UDN}, 5, 'Player: '.$hash->{NAME}.' ~ Slaves: '.ReadingsVal($hash->{NAME}, 'SlavePlayer', '[]');
	
	eval {
		foreach my $slavePlayer (@{eval(ReadingsVal($hash->{NAME}, 'SlavePlayer', '[]'))}) {
			SONOS_PropagateTitleInformationsToSlave($hash, $slavePlayer);
		}
	};
	
	return undef;
}

########################################################################################
#
# SONOS_PropagateTitleInformationsToSlave - Propagates the Titleinformations to one (given) Slaveplayer
#
# Parameter hash = Hash of the MasterPlayer
#
########################################################################################
sub SONOS_PropagateTitleInformationsToSlave($$) {
	my ($hash, $slavePlayer) = @_;
	my $slaveHash = SONOS_getSonosPlayerByName($slavePlayer);
	
	return if (!defined($hash) || !defined($slaveHash));
	
	SONOS_Log $hash->{UDN}, 5, 'PropagateTitleInformationsToSlave('.$hash->{NAME}.' => '.$slaveHash->{NAME}.')';
	
	if (AttrVal($slaveHash->{NAME}, 'getTitleInfoFromMaster', 0)) {
		SONOS_readingsBeginUpdate($slaveHash);
		
		foreach my $reading (keys %{$defs{$hash->{NAME}}->{READINGS}}) {
			if ($reading =~ /^(current|next).*/) {
				SONOS_readingsBulkUpdateIfChanged($slaveHash, $reading, ReadingsVal($hash->{NAME}, $reading, ''));
			}
		}
		
		foreach my $reading (qw(transportState GroupMute GroupVolume Repeat RepeatOne Shuffle infoSummarize1 infoSummarize2 infoSummarize3 infoSummarize4 numberOfTracks)) {
			SONOS_readingsBulkUpdateIfChanged($slaveHash, $reading, ReadingsVal($hash->{NAME}, $reading, ''));
		}
		
		SONOS_readingsEndUpdate($slaveHash, 1);
	}
	
	return undef;
}

########################################################################################
#
# SONOS_StartClientProcess - Starts the client-process (in a forked-subprocess), which handles all UPnP-Messages
#
# Parameter port = Portnumber to what the client have to listen for
#
########################################################################################
sub SONOS_StartClientProcessIfNeccessary($) {
	my ($upnplistener) = @_;
	my ($host, $port) = split(/:/, $upnplistener);
	
	my $socket = new IO::Socket::INET(PeerAddr => $upnplistener, Proto => 'tcp');
	if (!$socket) {
		# Sonos-Device ermitteln...
		my $hash = SONOS_getSonosPlayerByName();
		
		SONOS_Log undef, 1, 'Kein UPnP-Server gefunden... Starte selber einen und warte '.$hash->{WAITTIME}.' Sekunde(n) darauf...';
		$SONOS_StartedOwnUPnPServer = 1;
		
		if (fork() == 0) {
			# Zuständigen Verbose-Level ermitteln...
			# Allerdings sind die Attribute (momentan) zu diesem Zeitpunkt noch nicht gesetzt, sodass nur das globale Attribut verwendet werden kann...
			my $verboselevel = AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'verbose', $attr{global}{verbose});
			
			# Prozess anstarten...
			exec("$^X $attr{global}{modpath}/FHEM/00_SONOS.pm $port $verboselevel ".(($attr{global}{mseclog}) ? '1' : '0'));
			exit(0);
		}
	} else {
		$socket->sockopt(SO_LINGER, pack("ii", 1, 0));
		
		# Antwort vom Client weglesen...
		my $answer;
		$socket->recv($answer, 5000);
		$socket->send("Test\r\n", 0);
		
		# Hiermit wird eine etwaig bestehende Thread-Struktur beendet und diese Verbindung selbst geschlossen...
		eval{
			$socket->shutdown(2);
			$socket->close();
		};
	}
	
	return undef;
}

########################################################################################
#
# SONOS_InitClientProcessLater - Initializes the client-process at a later time
#
# Parameter hash = The device-hash
#
########################################################################################
sub SONOS_InitClientProcessLater($) {
	my ($hash) = @_;
	
	# Begrüßung weglesen...
	my $answer = DevIo_SimpleRead($hash);
	DevIo_SimpleWrite($hash, "Establish connection\r\n", 2);
	
	# Verbindung aufbauen...
	InternalTimer(gettimeofday() + 1, 'SONOS_InitClientProcess', $hash, 0);
	
	return undef;
}

########################################################################################
#
# SONOS_InitClientProcess - Initializes the client-process
#
# Parameter hash = The device-hash
#
########################################################################################
sub SONOS_InitClientProcess($) {
	my ($hash) = @_;
	
	my @playerudn = ();
	my @playername = ();
	foreach my $fhem_dev (sort keys %main::defs) { 
		next if($main::defs{$fhem_dev}{TYPE} ne 'SONOSPLAYER');
		
		push @playerudn, $main::defs{$fhem_dev}{UDN};
		push @playername, $main::defs{$fhem_dev}{NAME};
	}
	
	# Grundsätzliche Informationen bzgl. der konfigurierten Player übertragen...
	my $setDataString = 'SetData:'.$hash->{NAME}.':'.AttrVal($hash->{NAME}, 'verbose', '3').':'.AttrVal($hash->{NAME}, 'SubProcessLogfileName', '-').':'.AttrVal($hash->{NAME}, 'pingType', $SONOS_DEFAULTPINGTYPE).':'.AttrVal($hash->{NAME}, 'usedonlyIPs', '').':'.AttrVal($hash->{NAME}, 'ignoredIPs', '').':'.AttrVal($hash->{NAME}, 'reusePort', 0).':'.join(',', @playername).':'.join(',', @playerudn);
	SONOS_Log undef, 5, $setDataString;
	DevIo_SimpleWrite($hash, $setDataString."\n", 2);
	
	# Gemeldete Attribute, Definitionen und Readings übertragen...
	foreach my $fhem_dev (sort keys %main::defs) { 
		if (($main::defs{$fhem_dev}{TYPE} eq 'SONOSPLAYER') || ($main::defs{$fhem_dev}{TYPE} eq 'SONOS')) {
			# Den Namen des Devices ermitteln (normalerweise die UDN, bis auf das zentrale Sonos-Device)
			my $dataName;
			if ($main::defs{$fhem_dev}{TYPE} eq 'SONOS') {
				$dataName = 'SONOS';
			} else {
				$dataName = $main::defs{$fhem_dev}{UDN};
			}
			
			# Variable für die gesammelten Informationen, die übertragen werden sollen...
			my %valueList = ();
			
			# Attribute
			foreach my $key (keys %{$main::attr{$fhem_dev}}) {
				if (SONOS_posInList($key, @SONOS_PossibleAttributes) != -1) {
					$valueList{$key} = $main::attr{$fhem_dev}{$key};
				}
			}
			
			# Definitionen
			foreach my $key (keys %{$main::defs{$fhem_dev}}) {
				if (SONOS_posInList($key, @SONOS_PossibleDefinitions) != -1) {
					$valueList{$key} = $main::defs{$fhem_dev}{$key};
				}
			}
			
			# Readings
			foreach my $key (keys %{$main::defs{$fhem_dev}{READINGS}}) {
				if (SONOS_posInList($key, @SONOS_PossibleReadings) != -1) {
					$valueList{$key} = $main::defs{$fhem_dev}{READINGS}{$key}{VAL};
				}
			}
			
			# Werte in Text-Array umwandeln und dabei prüfen, ob überhaupt ein Wert gesetzt werden soll...
			my @values = ();
			foreach my $key (keys %valueList) {
				if (defined($key) && defined($valueList{$key})) {
					push @values, $key.'='.SONOS_URI_Escape($valueList{$key});
				}
			}
			
			# Übertragen...
			SONOS_Log undef, 5, 'SetValues:'.$dataName.':'.join('|', @values);
			DevIo_SimpleWrite($hash, 'SetValues:'.$dataName.':'.join('|', @values)."\n", 2);
		}
	}
	
	# Alle Informationen sind drüben, dann Threads dort drüben starten
	DevIo_SimpleWrite($hash, "StartThread\n", 2);
	
	# Interner Timer für die Überprüfung der Verbindung zum Client (nicht verwechseln mit dem IsAlive-Timer, der die Existenz eines Sonosplayers überprüft)
	SONOS_readingsSingleUpdate($hash, 'LastProcessAnswer', '2100-01-01 00:00:00', 0);
	InternalTimer(gettimeofday() + ($hash->{INTERVAL} * 2), 'SONOS_IsSubprocessAliveChecker', $hash, 0);
	
	return undef;
}

########################################################################################
#
# SONOS_IsSubprocessAliveChecker - Internal checking routine for isAlive of the subprocess
# 
########################################################################################
sub SONOS_IsSubprocessAliveChecker() {
	my ($hash) = @_;
	
	return undef if (AttrVal($hash->{NAME}, 'disable', 0));
	
	my $lastProcessAnswer = SONOS_GetTimeFromString(ReadingsVal(SONOS_getSonosPlayerByName()->{NAME}, 'LastProcessAnswer', '2100-01-01 00:00:00'));
	
	# Wenn länger nichts passiert ist, dann eine Aktualisierung anfordern...
	SONOS_DoWork('undef', 'refreshProcessAnswer') if ($lastProcessAnswer < gettimeofday() - $hash->{INTERVAL});
	
	# Wenn die letzte Antwort zu lange her ist, dann den SubProzess neustarten...
	if ($lastProcessAnswer < gettimeofday() - (4 * $hash->{INTERVAL})) {
		# Verbindung beenden, damit der SubProzess die Chance hat neu initialisiert zu werden...
		SONOS_Log $hash->{UDN}, 2, 'LastProcessAnswer way too old (Lastanswer: '.SONOS_GetTimeString($lastProcessAnswer).')... try to restart the process and connection...';
		
		# Letzten Zeitpunkt und Anzahl der Neustarts merken...
		my $sHash = SONOS_getSonosPlayerByName();
		SONOS_readingsBeginUpdate($sHash);
		readingsBulkUpdate($sHash, 'LastProcessRestart', SONOS_TimeNow(), 1);
		my $restarts = ReadingsVal($sHash->{NAME}, 'LastProcessRestartCount', 0);
		$restarts = 0 if (!looks_like_number($restarts));
		readingsBulkUpdate($sHash, 'LastProcessRestartCount', $restarts + 1, 1);
		SONOS_readingsEndUpdate($sHash, 1);
		
		# Stoppen...
		InternalTimer(gettimeofday() + 1, 'SONOS_StopSubProcess', $hash, 0);
		
		# Starten...
		InternalTimer(gettimeofday() + 30, 'SONOS_DelayStart', $hash, 0);
	} else {
		RemoveInternalTimer($hash, 'SONOS_IsSubprocessAliveChecker');
		InternalTimer(gettimeofday() + $hash->{INTERVAL}, 'SONOS_IsSubprocessAliveChecker', $hash, 0);
	}
	
	#my $answer;
	## Neue Verbindung parallel zur bestehenden Kommunikationsleitung.
	## Nur zum Prüfen, ob der SubProzess noch lebt und antworten kann.
	#my $socket = new IO::Socket::INET(PeerAddr => $hash->{DeviceName}, Proto => 'tcp');
	#if ($socket) {
	#	$socket->sockopt(SO_LINGER, pack("ii", 1, 0));
	#	
	#	$socket->recv($answer, 500);
	#	$socket->send("Test\r\n", 0);
	#	
	#	$socket->shutdown(2);
	#	$socket->close();
	#}
	## Ab hier keine Parallelverbindung mehr offen...
	#
	#if (defined($answer)) {
	#	$answer =~ s/[\r\n]//g;
	#}
	#
	#if (!defined($answer) || ($answer !~ m/^This is UPnP-Server listening for commands/)) {
	#	SONOS_Log undef, 0, 'No (or incorrect) answer from Subprocess. Restart Sonos-Subprocess...';
	#	
	#	# Verbindung beenden, damit der SubProzess die Chance hat neu initialisiert zu werden...
	#	RemoveInternalTimer($hash);
	#	DevIo_SimpleWrite($hash, "disconnect\n", 2);
	#	DevIo_CloseDev($hash);
	#	
	#	# Neu anstarten...
	#	SONOS_StartClientProcessIfNeccessary($hash->{DeviceName}) if ($SONOS_StartedOwnUPnPServer);
	#	InternalTimer(gettimeofday() + $hash->{WAITTIME}, 'SONOS_DelayOpenDev', $hash, 0);
	#} elsif (defined($answer) && ($answer =~ m/^This is UPnP-Server listening for commands/)) {
	#	SONOS_Log undef, 4, 'Got correct answer from Subprocess...';
	#	RemoveInternalTimer($hash, 'SONOS_IsSubprocessAliveChecker');
	#	InternalTimer(gettimeofday() + $hash->{INTERVAL}, 'SONOS_IsSubprocessAliveChecker', $hash, 0);
	#}
}

########################################################################################
#
# SONOS_DoTriggerInternal - Internal working routine for DoTrigger and PeekTriggerQueueInLocalThread 
# 
########################################################################################
sub SONOS_DoTriggerInternal($$) {
	my ($triggerType, @lines) = @_;

	# Eval Kommandos ausführen
	my %doTriggerHashParam;
	my @doTriggerArrayParam;
	my $doTriggerScalarParam;
	foreach my $line (@lines) {
		my $reftype = reftype $line;
		
		if (!defined $reftype) {
			SONOS_Log undef, 5, $triggerType.'Trigger()-Line: '.$line; 

			eval $line;
			if ($@) {
				SONOS_Log undef, 2, 'Error during '.$triggerType.'Trigger: '.$@.' - Trying to execute \''.$line.'\'';
			}
			
			undef(%doTriggerHashParam);
			undef(@doTriggerArrayParam);
			undef($doTriggerScalarParam);
		} elsif($reftype eq 'HASH') {
			%doTriggerHashParam = %{$line};
			SONOS_Log undef, 5, $triggerType.'Trigger()-doTriggerHashParam: '.SONOS_Stringify(\%doTriggerHashParam);
		} elsif($reftype eq 'ARRAY') {
			@doTriggerArrayParam = @{$line};
			SONOS_Log undef, 5, $triggerType.'Trigger()-doTriggerArrayParam: '.SONOS_Stringify(\@doTriggerArrayParam);
		} elsif($reftype eq 'SCALAR') {
			$doTriggerScalarParam = ${$line};
			SONOS_Log undef, 5, $triggerType.'Trigger()-doTriggerScalarParam: '.SONOS_Stringify(\$doTriggerScalarParam);
		}
	}
}

########################################################################################
#
#  SONOS_Get - Implements GetFn function 
#
#  Parameter hash = hash of the master 
#						 a = argument array
#
########################################################################################
sub SONOS_Get($@) {
	my ($hash, @a) = @_;
	
	my $reading = $a[1];
	my $name = $hash->{NAME};
	
	# for the ?-selector: which values are possible
	if($a[1] eq '?') {
		my @newGets = ();
		for my $elem (sort keys %gets) {
			push @newGets, $elem.(($gets{$elem} eq '') ? ':noArg' : '');
		}
		return "Unknown argument, choose one of ".join(" ", @newGets);
	}
	
	# check argument
	my $found = 0;
	for my $elem (keys %gets) {
		if (lc($reading) eq lc($elem)) {
			$reading = $elem; # Korrekte Schreibweise behalten
			$found = 1;
			last;
		}
	}
	return "SONOS: Get with unknown argument $a[1], choose one of ".join(",", sort keys %gets) if(!$found);
	
	# some argument needs parameter(s), some not
	return "SONOS: $a[1] needs parameter(s): ".$gets{$a[1]} if (SONOS_CountRequiredParameters($gets{$a[1]}) > scalar(@a) - 2);
	
	# getter
	if (lc($reading) eq 'groups') {
		return SONOS_ConvertZoneGroupStateToString(SONOS_ConvertZoneGroupState(ReadingsVal($name, 'ZoneGroupState', '')));
	}
	
	return undef;
}

########################################################################################
#
#  SONOS_ConvertZoneGroupState - Retrieves the Groupstate in an array (Elements are UDNs)
#
########################################################################################
sub SONOS_ConvertZoneGroupState($) {
	my ($zoneGroupState) = @_;
	
	my @groups = ();
	while ($zoneGroupState =~ m/<ZoneGroup.*?Coordinator="(.*?)".*?>(.*?)<\/ZoneGroup>/gi) {
		my @group = ($1.'_MR');
		my $groupMember = $2;

		while ($groupMember =~ m/<ZoneGroupMember.*?UUID="(.*?)"(.*?)\/>/gi) {
			my $udn = $1;
			my $string = $2;
			push @group, $udn.'_MR' if (!($string =~ m/IsZoneBridge="."/) && !SONOS_isInList($udn.'_MR', @group));
			
			# Etwaig von vorher enthaltene Bridges wieder entfernen (wenn sie bereits als Koordinator eingesetzt wurde)
			if ($string =~ m/IsZoneBridge="."/) {
				for(my $i = 0; $i <= $#group; $i++) {
					delete $group[$i] if ($group[$i] eq $udn.'_MR');
				}
			}
		}
		
		# Die Abspielgruppe hinzufügen, wenn sie nicht leer ist (kann bei Bridges passieren)
		if ($#group >= 0) {
			# Playernamen einsetzen...
			@group = map { SONOS_getSonosPlayerByUDN($_)->{NAME} } @group;
			
			# Die einzelne Gruppe sortieren, dabei den Masterplayer vorne lassen...
			my @newgroup = ($group[0]);
			push @newgroup, sort @group[1..$#group];
			
			# Zur großen Liste hinzufügen...
			push @groups, \@newgroup;
		}
	}
	
	# Nach den Masterplayernamen sortieren
	@groups = sort {
		@{$a}[0] cmp @{$b}[0];
	} @groups;
	
	return @groups;
}

########################################################################################
#
#  SONOS_ConvertZoneGroupStateToString - Converts the GroupState into a String
#
########################################################################################
sub SONOS_ConvertZoneGroupStateToString($) {
	my (@groups) = @_;
	
	# UDNs durch Devicenamen ersetzen und dabei gleich das Ergebnis zusammenbauen
	my $result = '';
	foreach my $gelem (@groups) {
		#$result .= '[';
		#foreach my $elem (@{$gelem}) {
		#	$elem = SONOS_getSonosPlayerByUDN($elem)->{NAME};
		#}
		$result .= '['.join(', ', @{$gelem}).'], ';
	}

	return substr($result, 0, -2);
}

########################################################################################
#
#  SONOS_Set - Implements SetFn function
# 
#  Parameter hash
#						 a = argument array
#
########################################################################################
sub SONOS_Set($@) {
	my ($hash, @a) = @_;
  
	# %setCopy enthält eine Kopie von %sets, da für eine ?-Anfrage u.U. ein Slider zurückgegeben werden muss...
	my %setcopy;
	if (AttrVal($hash, 'generateVolumeSlider', 1) == 1) {
		foreach my $key (keys %sets) {
			my $oldkey = $key;
			$key = $key.':slider,0,1,100' if (lc($key) eq 'volume');
			$key = $key.':slider,-100,1,100' if (lc($key) eq 'balance');
			
			$key = $key.':0,1' if ($key =~ m/^mute(all|)$/i);
			
			$setcopy{$key} = $sets{$oldkey};
		}
	} else {
		%setcopy = %sets;
	}
	
	# for the ?-selector: which values are possible
	if($a[1] eq '?') {
		my @newSets = ();
		for my $elem (sort keys %setcopy) {
			push @newSets, $elem.(($setcopy{$elem} eq '') ? ':noArg' : '');
		}
		return "Unknown argument, choose one of ".join(" ", @newSets);
	}
	
	# check argument
	my $found = 0;
	for my $elem (keys %sets) {
		if (lc($a[1]) eq lc($elem)) {
			$a[1] = $elem; # Korrekte Schreibweise behalten
			$found = 1;
			last;
		}
	}
	return "SONOS: Set with unknown argument $a[1], choose one of ".join(",", sort keys %sets) if(!$found);
  
	# some argument needs parameter(s), some not
	return "SONOS: $a[1] needs parameter(s): ".$sets{$a[1]} if (SONOS_CountRequiredParameters($sets{$a[1]}) > scalar(@a) - 2);
      
	# define vars
	my $key = $a[1];
	my $value = $a[2];
	my $value2 = $a[3];
	my $name = $hash->{NAME};
	
	# setter
	if (lc($key) eq 'groups') {
		my $text = '';
		for(my $i = 2; $i < @a; $i++) {
			$text .= ' '.$a[$i];
		}
		$text =~ s/ //g;
		
		# Aktuellen Zustand holen
		my @current;
		my $current = SONOS_Get($hash, qw($hash->{NAME} Groups));
		$current =~ s/ //g;
		while ($current =~ m/(\[.*?\])/ig) {
			my @tmp = split(/,/, substr($1, 1, -1));
			push @current, \@tmp;
		}
		
		if (lc($text) eq 'reset') {
			my $tmpcurrent = $current;
			$tmpcurrent =~ s/[\[\],]/ /g;
			my @list = split(/ /, $tmpcurrent);
			
			# Alle Player als Standalone-Group festlegen
			for(my $i = 0; $i <= $#list; $i++) {
				next if (!$list[$i]); # Wenn hier ein Leerstring aus dem Split kam, dann überspringen...
				
				my $elemHash = SONOS_getSonosPlayerByName($list[$i]);
				
				SONOS_DoWork($elemHash->{UDN}, 'makeStandaloneGroup');
				usleep(250_000);
			}
			
			return undef;
		}
		
		# Gewünschten Zustand holen
		my @desiredList;
		my @desiredCrowd;
		while ($text =~ m/([\[\{].*?[\}\]])/ig) {
			my @tmp = split(/,/, substr($1, 1, -1));
			if (substr($1, 0, 1) eq '{') {
				push @desiredCrowd, \@tmp;
			} else {
				push @desiredList, \@tmp;
			}
		}
		# SONOS_Log undef, 5, "Desired-Crowd: ".Dumper(\@desiredCrowd);
		SONOS_Log undef, 5, "Desired-List: ".Dumper(\@desiredList);
		
		# Erstmal die Listen sicherstellen
		foreach my $dElem (@desiredList) {
			my @list = @{$dElem};
			for(my $i = 0; $i <= $#list; $i++) { # Die jeweilige Desired-List
				my $elem = $list[$i];
				my $elemHash = SONOS_getSonosPlayerByName($elem);
				my $reftype  = reftype $elemHash;
				if (!defined($reftype) || $reftype ne 'HASH') {
					SONOS_Log undef, 2, "Hash not found for Device '$elem'. Is it gone away or not known?";
					return undef;
				}
				
				# Das Element soll ein Gruppenkoordinator sein
				if ($i == 0) {
					my $cPos = -1;
					foreach my $cElem (@current) {
						$cPos = SONOS_posInList($elem, @{$cElem});
						last if ($cPos != -1);
					}
					
					# Ist es aber nicht... also erstmal dazu machen
					if ($cPos != 0) {
						SONOS_DoWork($elemHash->{UDN}, 'makeStandaloneGroup');
						usleep(250_000);
					}
				} else {
					# Alle weiteren dazufügen
					my $cHash = SONOS_getSonosPlayerByName($list[0]);
					SONOS_DoWork($cHash->{UDN}, 'addMember', $elemHash->{UDN});
					usleep(250_000);
				}
			}
		}
		
		# Jetzt noch die Mengen sicherstellen
		# Dazu aktuellen Zustand nochmal holen
		#@current = ();
		#$current = SONOS_Get($hash, qw($hash->{NAME} Groups));
		#$current =~ s/ //g;
		#while ($current =~ m/(\[.*?\])/ig) {
		#	my @tmp = split(/,/, substr($1, 1, -1));
		#	push @current, \@tmp;
		#}
		#SONOS_Log undef, 5, "Current after List: ".Dumper(\@current);
		
	} elsif (lc($key) =~ m/^(Stop|Pause|Mute|MuteOn|MuteOff)(All|)$/i) {
		my $commandType = lc($1);
		my $commandValue = $value;
		
		$commandValue = 0 if ($commandType ne 'mute');
		$commandValue = 1 if ($commandType eq 'muteon');
		$commandValue = 0 if ($commandType eq 'muteoff');
		
		$commandType = 'setGroupMute' if (($commandType eq 'mute') || ($commandType eq 'muteon') || ($commandType eq 'muteoff'));
		
		# Alle Gruppenkoordinatoren zum Stoppen/Pausieren/Muten aufrufen
		foreach my $cElem (@{eval(ReadingsVal($hash->{NAME}, 'MasterPlayer', '[]'))}) {
			SONOS_DoWork(SONOS_getSonosPlayerByName($cElem)->{UDN}, $commandType, $commandValue);
		}
	} elsif (lc($key) eq 'rescannetwork') {
		SONOS_DoWork('SONOS', 'rescanNetwork');
	} elsif (lc($key) eq 'refreshshareindex') {
		foreach my $cElem (@{eval(ReadingsVal($hash->{NAME}, 'MasterPlayer', '[]'))}) {
			SONOS_DoWork(SONOS_getSonosPlayerByName($cElem)->{UDN}, 'refreshShareIndex');
			
			last;
		}
	} elsif (lc($key) eq 'savebookmarks') {
		SONOS_DoWork('SONOS', 'SaveBookmarks', $value);
	} elsif (lc($key) eq 'loadbookmarks') {
		SONOS_DoWork('SONOS', 'LoadBookmarks', $value);
	} elsif (lc($key) eq 'disablebookmark') {
		SONOS_DoWork('SONOS', 'DisableBookmark', $value);
	} elsif (lc($key) eq 'enablebookmark') {
		SONOS_DoWork('SONOS', 'EnableBookmark', $value);
	} else {
		return 'Not implemented yet!';
	}
	
	return (undef, 1);
}

########################################################################################
#
#  SONOS_CountRequiredParameters - Counta all required parameters in the given string
#
########################################################################################
sub SONOS_CountRequiredParameters($) {
	my ($params) = @_;
	
	my $result = 0;
	for my $elem (split(' ', $params)) {
		$result++ if ($elem !~ m/\[.*\]/);
	}
	
	return $result;
}

########################################################################################
#
#  SONOS_DoWork - Communicates with the forked Part via Telnet and over there via ComObjectTransportQueue
#
# Parameter deviceName = Devicename of the SonosPlayer
#			method = Name der "Methode" die im Thread-Context ausgeführt werden soll
#			params = Parameter for the method
#
########################################################################################
sub SONOS_DoWork($$;@) {
	my ($udn, $method, @params) = @_;
	
	if (!@params) {
		@params = ();
	}
	
	if (!defined($udn)) {
		SONOS_Log undef, 0, "ERROR in DoWork: '$method' -> UDN is undefined - ".Dumper(\@params);
		return;
	}
	
	# Etwaige optionale Parameter, die sonst undefined wären, löschen
	for(my $i = 0; $i <= $#params; $i++) {
		if (!defined($params[$i])) {
			delete($params[$i]);
		}
	}
	
	eval {
		my $hash = SONOS_getSonosPlayerByName();
		if (defined($hash->{TCPDev}) && ($hash->{TCPDev}->connected())) {
			DevIo_SimpleWrite($hash, 'DoWork:'.$udn.':'.$method.':'.encode_utf8(join('--#--', @params))."\r\n", 2);
		}
	};
	if ($@) {
		SONOS_Log undef, 0, 'ERROR in DoWork: '.$@;
	}
		
	return undef;
}

########################################################################################
#
#  SONOS_Discover - Discover SonosPlayer, 
#                   indirectly autocreate devices if not already present (via callback)
#
########################################################################################
sub SONOS_Discover() {
	SONOS_Log undef, 3, 'UPnP-Thread gestartet.';
	
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'CHLD'} = 'IGNORE';
  
	# Thread 'cancellation' signal handler
	$SIG{'INT'} = sub { 
		# Sendeliste leeren
		while ($SONOS_Client_SendQueue->pending()) {
			$SONOS_Client_SendQueue->dequeue();
		}
		
		# Empfängerliste leeren
		while ($SONOS_ComObjectTransportQueue->pending()) {
			$SONOS_ComObjectTransportQueue->dequeue();
		}
		
		# UPnP-Listener beenden
		SONOS_StopControlPoint();
		
		SONOS_Log undef, 3, 'Controlpoint-Listener wurde beendet.';
		return 1;
	};
	
	SONOS_LoadBookmarkValues();
	
	my $error;
	do {
		$SONOS_RestartControlPoint = 0;
		
		eval {
			$SONOS_Controlpoint = UPnP::ControlPoint->new(SearchPort => 0, SubscriptionPort => 0, SubscriptionURL => '/fhemmodule', MaxWait => 30, UsedOnlyIP => \%usedonlyIPs, IgnoreIP => \%ignoredIPs, ReusePort => $reusePort);
			$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
			
			#$SONOS_Controlpoint->handle;
			my @mysockets = $SONOS_Controlpoint->sockets();
			my $select = IO::Select->new(@mysockets);
			
			while (!$SONOS_RestartControlPoint) {
				# UPnP-Sockets abfragen...
				my @sockets = $select->can_read(0.01);
				for my $sock (@sockets) {
					$SONOS_Controlpoint->handleOnce($sock);
				}
				
				# Befehlsqueue abfragen...
				while ($SONOS_ComObjectTransportQueue->pending()) {
					SONOS_Discover_DoQueue($SONOS_ComObjectTransportQueue->dequeue());
				}
			}
		};
		$error = $@;
		
		# Nur wenn es der Fehler mit der XML-Struktur ist, dann den UPnP-Handler nochmal anstarten...  
		if (($error =~ m/multiple roots, wrong element '.*?'/si) || ($error =~ m/junk '.*?' after XML element/si) || ($error =~ m/mismatched tag '.*?'/si) || ($error =~ m/no element found/si) || ($error =~ m/500 Can't connect to/si) || ($error =~ m/not properly closed tag '.*?'/si) || ($error =~ m/Bad arg length for Socket::unpack_sockaddr_in/si)) {
			SONOS_Log undef, 2, "Error during UPnP-Handling, restarting handling: $error";
			SONOS_StopControlPoint();
		} else {
			SONOS_Log undef, 2, "Error during UPnP-Handling: $error";
			SONOS_StopControlPoint();
			
			undef($error);
		}
	} while ($error || $SONOS_RestartControlPoint);
	
	SONOS_SaveBookmarkValues();
	
	SONOS_Log undef, 3, 'UPnP-Thread wurde beendet.';
	$SONOS_Thread = -1;
	
	return 1;
}

########################################################################################
#
#  SONOS_Discover_DoQueue - Do the working job (command from Fhem -> Sonosplayer)
#
########################################################################################
sub SONOS_Discover_DoQueue($) {
	my ($data) = @_;
	
	my $workType = $data->{WorkType};
	return if (!defined($workType));
	
	my $udn = $data->{UDN};
	my @params = ();
	@params = @{$data->{Params}} if (defined($data->{Params}));
	
	eval {
		if ($workType eq 'setVerbose') {
			$SONOS_Client_LogLevel = $params[0];
			SONOS_Log undef, $SONOS_Client_LogLevel, "Setting LogLevel to new value: $SONOS_Client_LogLevel";
		} elsif ($workType eq 'setLogfileName') {
			$SONOS_Client_LogfileName = $params[0]
		} elsif ($workType eq 'refreshProcessAnswer') {
			SONOS_Client_Notifier('rePing:undef::');
		} elsif ($workType eq 'setAttribute') {
			SONOS_Client_Data_Refresh('', $udn, $params[0], $params[1]);
		} elsif ($workType eq 'deleteAttribute') {
			SONOS_Client_Data_Refresh('', $udn, $params[0], undef);
		} elsif ($workType eq 'rescanNetwork') {
			$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
		} elsif ($workType eq 'refreshShareIndex') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $albumArtistDisplayOption = $SONOS_ContentDirectoryControlProxy{$udn}->GetAlbumArtistDisplayOption()->getValue('AlbumArtistDisplayOption');
				
				SONOS_MakeSigHandlerReturnValue('undef', 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_ContentDirectoryControlProxy{$udn}->RefreshShareIndex($albumArtistDisplayOption)));
			}
		} elsif ($workType eq 'setMinMaxVolumes') {
			$SONOS_Client_Data{Buffer}->{$udn}{$params[0]} = $params[1];
			
			# Ensures the defined volume-borders
			SONOS_EnsureMinMaxVolumes($udn);
			
			SONOS_Log undef, 3, "Setting MinMaxVolumes of device '$udn' to a new value ~ $params[0] = $params[1]";
		} elsif ($workType eq 'JumpToBookmark') {
			if ($SONOS_BookmarkTitleDefinition{$params[0]}) {
				
			}
		} elsif ($workType eq 'LoadBookmarks') {
			SONOS_LoadBookmarkValues($params[0]);
		} elsif ($workType eq 'SaveBookmarks') {
			SONOS_SaveBookmarkValues($params[0]);
		} elsif ($workType eq 'DisableBookmark') {
			$SONOS_BookmarkTitleDefinition{$params[0]}{Disabled} = 1 if ($SONOS_BookmarkTitleDefinition{$params[0]});
			$SONOS_BookmarkQueueDefinition{$params[0]}{Disabled} = 1 if ($SONOS_BookmarkQueueDefinition{$params[0]});
		} elsif ($workType eq 'EnableBookmark') {
			delete($SONOS_BookmarkTitleDefinition{$params[0]}{Disabled}) if ($SONOS_BookmarkTitleDefinition{$params[0]});
			delete($SONOS_BookmarkQueueDefinition{$params[0]}{Disabled}) if ($SONOS_BookmarkQueueDefinition{$params[0]});
		} elsif ($workType eq 'setEQ') {
			my $command = $params[0];
			my $value = $params[1];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).' ('.$command.'): '.SONOS_UPnPAnswerMessage($SONOS_RenderingControlProxy{$udn}->SetEQ(0, $command, $value)));
			}
		} elsif ($workType eq 'setTruePlay') {
			my $value = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_RenderingControlProxy{$udn}->SetSonarStatus(0, $value)));
			}
		} elsif ($workType eq 'setName') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_DevicePropertiesProxy{$udn}->SetZoneAttributes($value1, '', '')));
			}
		} elsif ($workType eq 'setIcon') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_DevicePropertiesProxy{$udn}->SetZoneAttributes('', 'x-rincon-roomicon:'.$value1, '')));
			}
		} elsif ($workType eq 'getCurrentTrackPosition') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
					my $position = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('RelTime');
					
					SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
					my $modus = 'ReadingsBulkUpdate'.((SONOS_Client_Data_Retreive($udn, 'reading', 'currentStreamAudio', 0)) ? 'IfChanged' : '');
					SONOS_Client_Data_Refresh($modus, $udn, 'currentTrackPosition', $position);
					SONOS_Client_Data_Refresh($modus, $udn, 'currentTrackPositionSec', SONOS_GetTimeSeconds($position));
					SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('RelTime'));
				}
			}
		} elsif ($workType eq 'setCurrentTrackPosition') {
			my $value1 = $params[0];
			
			# Wenn eine Sekundenangabe gemacht wurde, dann in einen Zeitstring umwandeln, damit der Rest so bleiben kann
			$value1 = $1.SONOS_ConvertSecondsToTime($2).$3 if ($value1 =~ m/^([+-]{0,1})(\d+)(\%{0,1})$/);
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				if ($value1 =~ m/([+-])(\d+:\d+:\d+|\d+:\d+|\d+)(\%{0,1})/) {
					# Relative-(Prozent)-Angabe
					my $value1Sec = SONOS_GetTimeSeconds(SONOS_ExpandTimeString($2));
					
					# Positionswerte abfragen...
					my $result = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0);
					my $pos = SONOS_GetTimeSeconds($result->getValue('RelTime'));
					my $duration = SONOS_GetTimeSeconds($result->getValue('TrackDuration'));
					
					# Neue Position berechnen...
					my $newPos = 0;
					if ($3 eq '') {
						$newPos = ($pos + $value1Sec) if ($1 eq '+');
						$newPos = ($pos - $value1Sec) if ($1 eq '-');
					} else {
						$newPos = ($pos + ($value1Sec * $duration / 100)) if ($1 eq '+');
						$newPos = ($pos - ($value1Sec * $duration / 100)) if ($1 eq '-');
					}
					
					# Sicherstellen, dass wir im Bereich des Titels bleiben...
					$newPos = 0 if ($newPos < 0);
					$newPos = $duration if ($newPos > $duration);
					
					# Neue Position setzen
					$SONOS_AVTransportControlProxy{$udn}->Seek(0, 'REL_TIME', SONOS_ConvertSecondsToTime($newPos));
				} else {
					$SONOS_AVTransportControlProxy{$udn}->Seek(0, 'REL_TIME', $value1);
				}
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('RelTime'));
			}
		} elsif ($workType eq 'reportUnresponsiveDevice') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_ZoneGroupTopologyProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_ZoneGroupTopologyProxy{$udn}->ReportUnresponsiveDevice($value1, 'VerifyThenRemoveSystemwide')));
			}
		} elsif ($workType eq 'setGroupVolume') {
			my $value1 = $params[0];
			my $value2 = $params[1];
			
			# Wenn ein fixer Wert für alle Gruppenmitglieder gleich gesetzt werden soll...
			if (defined($value2) && lc($value2) eq 'fixed') {
				
			} else {
				if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
					$SONOS_GroupRenderingControlProxy{$udn}->SetGroupVolume(0, $value1);
				
					# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_GroupRenderingControlProxy{$udn}->GetGroupVolume(0)->getValue('CurrentVolume'));
				}
			}
		} elsif ($workType eq 'setSnapshotGroupVolume') {
			if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_GroupRenderingControlProxy{$udn}->SnapshotGroupVolume(0)));
			}
		} elsif ($workType eq 'setVolume') {
			my $value1 = $params[0];
			my $ramptype = $params[1];
						
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				if (defined($ramptype)) {
					if ($ramptype == 1) {
						$ramptype = 'SLEEP_TIMER_RAMP_TYPE';
					} elsif ($ramptype == 2) {
						$ramptype = 'AUTOPLAY_RAMP_TYPE';
					} elsif ($ramptype == 3) {
						$ramptype = 'ALARM_RAMP_TYPE';
					}
					my $ramptime = $SONOS_RenderingControlProxy{$udn}->RampToVolume(0, 'Master', $ramptype, $value1, 0, '')->getValue('RampTime');
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Ramp to '.$value1.' with Type '.$params[1].' started');
				} else {
					$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'Master', $value1);
				
					# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume'));
				}
			}
		} elsif ($workType eq 'setRelativeGroupVolume') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_GroupRenderingControlProxy{$udn}->SetRelativeGroupVolume(0, $value1)->getValue('NewVolume'));
			}
		} elsif ($workType eq 'setRelativeVolume') {
			my $value1 = $params[0];
			my $ramptype = $params[1];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				if (defined($ramptype)) {
					if ($ramptype == 1) {
						$ramptype = 'SLEEP_TIMER_RAMP_TYPE';
					} elsif ($ramptype == 2) {
						$ramptype = 'AUTOPLAY_RAMP_TYPE';
					} elsif ($ramptype == 3) {
						$ramptype = 'ALARM_RAMP_TYPE';
					}
					
					# Wenn eine Prozentangabe übergeben wurde, dann die wirkliche Ziellautstärke ermitteln/berechnen
					if ($value1 =~ m/([+-])(\d+)\%/) {
						my $currentValue = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume');
						$value1 = $currentValue + eval{ $1.($currentValue * ($2 / 100)) };
					} else {
						# Hier aus der Relativangabe eine Absolutangabe für den Aufruf von RampToVolume machen
						$value1 = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume') + $value1;
					}
					$SONOS_RenderingControlProxy{$udn}->RampToVolume(0, 'Master', $ramptype, $value1, 0, '');
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Ramp to '.$value1.' with Type '.$params[1].' started');
				} else {
					# Wenn eine Prozentangabe übergeben wurde, dann die wirkliche Ziellautstärke ermitteln/berechnen
					if ($value1 =~ m/([+-])(\d+)\%/) {
						my $currentValue = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume');
						$value1 = $currentValue + eval{ $1.($currentValue * ($2 / 100)) };
						
						$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'Master', $value1);
					
						# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume'));
					} else {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_RenderingControlProxy{$udn}->SetRelativeVolume(0, 'Master', $value1)->getValue('NewVolume'));
					}
				}
			}
		} elsif ($workType eq 'setBalance') {
			my $value1 = $params[0];
			
			# Balancewert auf die beiden Lautstärkeseiten aufteilen...
			my $volumeLeft = 100;
			my $volumeRight = 100;
			if ($value1 < 0) {
				$volumeRight = 100 + $value1;
			} else {
				$volumeLeft = 100 - $value1;
			}
						
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'LF', $volumeLeft);
				$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'RF', $volumeRight);
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				$volumeLeft = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'LF')->getValue('CurrentVolume');
				$volumeRight = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'RF')->getValue('CurrentVolume');
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.((-$volumeLeft) + $volumeRight));
			}
		} elsif ($workType eq 'setLoudness') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetLoudness(0, 'Master', SONOS_ConvertWordToNum($value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_RenderingControlProxy{$udn}->GetLoudness(0, 'Master')->getValue('CurrentLoudness')));
			}
		} elsif ($workType eq 'setBass') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetBass(0, $value1);
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_RenderingControlProxy{$udn}->GetBass(0)->getValue('CurrentBass'));
			}
		} elsif ($workType eq 'setTreble') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetTreble(0, $value1);
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_RenderingControlProxy{$udn}->GetTreble(0)->getValue('CurrentTreble'));
			}
		} elsif ($workType eq 'setMute') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetMute(0, 'Master', SONOS_ConvertWordToNum($value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_RenderingControlProxy{$udn}->GetMute(0, 'Master')->getValue('CurrentMute')));
			}
		} elsif ($workType eq 'setOutputFixed') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				$SONOS_RenderingControlProxy{$udn}->SetOutputFixed(0, SONOS_ConvertWordToNum($value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_RenderingControlProxy{$udn}->GetOutputFixed(0)->getValue('CurrentFixed')));
			}
		} elsif ($workType eq 'setButtonLockState') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				$SONOS_DevicePropertiesProxy{$udn}->SetButtonLockState(0, lcfirst(SONOS_ConvertNumToWord($value1)));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertWordToNum(lc($SONOS_DevicePropertiesProxy{$udn}->GetButtonLockState(0)->getValue('CurrentButtonLockState'))));
			}
		} elsif ($workType eq 'setResetAttributesToDefault') {
			my $sonosDeviceName = $params[0];
			my $deviceName = $params[1];
			my $value1 = 0;
			$value1 = $params[2] if ($params[2]);
			
			my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
			
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				# Sollen alle Attribute vorher entfernt werden?
				if (SONOS_ConvertWordToNum($value1)) {
					SONOS_Client_Notifier('CommandDeleteAttr:'.$deviceName);
				}
				
				# Notwendige Daten vom Player ermitteln...
				my ($isZoneBridge, $topoType, $fieldType, $master, $masterPlayerName, $aliasSuffix, $zoneGroupState) = SONOS_AnalyzeZoneGroupTopology($udn, $udnShort);
				
				my $roomName = $SONOS_DevicePropertiesProxy{$udn}->GetZoneAttributes()->getValue('CurrentZoneName');
				
				my $groupName = decode('UTF-8', $roomName);
				eval {
					use utf8;
					$groupName =~ s/([äöüÄÖÜß])/SONOS_UmlautConvert($1)/eg; # Hier erstmal Umlaute 'schön' machen, damit dafür nicht '_' verwendet werden...
				};
				$groupName =~ s/[^a-zA-Z0-9]/_/g;
				
				my $iconPath = decode_entities($1) if ($SONOS_UPnPDevice{$udn}->descriptionDocument() =~ m/<iconList>.*?<icon>.*?<id>0<\/id>.*?<url>(.*?)<\/url>.*?<\/icon>.*?<\/iconList>/sim);
				$iconPath =~ s/.*\/(.*)/icoSONOSPLAYER_$1/i;
				
				# Standard-Attribute am Player setzen
				for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER_Attributes', $sonosDeviceName, undef, $master, $deviceName, $roomName, $aliasSuffix, $groupName, $iconPath, $isZoneBridge)) {
					SONOS_Client_Notifier($elem);
				}
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Successfully done...');
			}
		} elsif ($workType eq 'setMuteT') {
			my $value1 = 'off';
			if (SONOS_CheckProxyObject($udn, $SONOS_RenderingControlProxy{$udn})) {
				if ($SONOS_RenderingControlProxy{$udn}->GetMute(0, 'Master')->getValue('CurrentMute') == 0) {
					$value1 = 'on';
				} else {
					$value1 = 'off';
				}
				
				$SONOS_RenderingControlProxy{$udn}->SetMute(0, 'Master', SONOS_ConvertWordToNum($value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_RenderingControlProxy{$udn}->GetMute(0, 'Master')->getValue('CurrentMute')));
			}
		} elsif ($workType eq 'setGroupMute') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
				$SONOS_GroupRenderingControlProxy{$udn}->SetGroupMute(0, SONOS_ConvertWordToNum($value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_GroupRenderingControlProxy{$udn}->GetGroupMute(0)->getValue('CurrentMute')));
			}
		} elsif ($workType eq 'setShuffle') {
			my $value1 =  undef;
			
			if ($params[0] ne '~~') {
				$value1 = SONOS_ConvertWordToNum($params[0]);
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				my $result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				my ($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				
				$value1 = !$shuffle if (!defined($value1));
				
				$SONOS_AVTransportControlProxy{$udn}->SetPlayMode(0, SONOS_GetShuffleRepeatString($value1, $repeat, $repeatOne));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				$result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($shuffle));
			}
		} elsif ($workType eq 'setRepeat') {
			my $value1 =  undef;
			
			if ($params[0] ne '~~') {
				$value1 = SONOS_ConvertWordToNum($params[0]);
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				my $result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				my ($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				
				$value1 = !$repeat if (!defined($value1));
				
				$SONOS_AVTransportControlProxy{$udn}->SetPlayMode(0, SONOS_GetShuffleRepeatString($shuffle, $value1, $repeatOne && !$value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				$result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($repeat));
			}
		} elsif ($workType eq 'setRepeatOne') {
			my $value1 =  undef;
			
			if ($params[0] ne '~~') {
				$value1 = SONOS_ConvertWordToNum($params[0]);
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				my $result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				my ($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				
				$value1 = !$repeatOne if (!defined($value1));
				
				$SONOS_AVTransportControlProxy{$udn}->SetPlayMode(0, SONOS_GetShuffleRepeatString($shuffle, $repeat && !$value1, $value1));
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				$result = $SONOS_AVTransportControlProxy{$udn}->GetTransportSettings(0)->getValue('PlayMode');
				($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($result);
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($repeatOne));
			}
		} elsif ($workType eq 'setCrossfadeMode') {
			my $value1 = SONOS_ConvertWordToNum($params[0]);
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				$SONOS_AVTransportControlProxy{$udn}->SetCrossfadeMode(0, $value1);
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_AVTransportControlProxy{$udn}->GetCrossfadeMode(0)->getValue('CrossfadeMode')));
			}
		} elsif ($workType eq 'setLEDState') {
			my $value1 = (SONOS_ConvertWordToNum($params[0])) ? 'On' : 'Off';
			
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				$SONOS_DevicePropertiesProxy{$udn}->SetLEDState($value1);
			
				# Wert wieder abholen, um das wahre Ergebnis anzeigen zu können
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_ConvertNumToWord($SONOS_DevicePropertiesProxy{$udn}->GetLEDState()->getValue('CurrentLEDState')));
			}
		} elsif ($workType eq 'play') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Play(0, 1)));
			}
		} elsif ($workType eq 'stop') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Stop(0)));
			}
		} elsif ($workType eq 'pause') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Pause(0)));
			}
		} elsif ($workType eq 'previous') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Previous(0)));
			}
		} elsif ($workType eq 'next') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Next(0)));
			}
		} elsif ($workType eq 'setTrack') {
			my $value1 = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn}) && SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				# Abspielliste aktivieren?
				my $currentURI = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0)->getValue('CurrentURI');
				if ($currentURI !~ m/x-rincon-queue:/) {
					my $queueMetadata = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '');
					my $result = $SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $queueMetadata->getValue('Result')), '');
				}
				
				if (lc($value1) eq 'random') {
					$SONOS_AVTransportControlProxy{$udn}->Seek(0, 'TRACK_NR', int(rand($SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0)->getValue('NrTracks'))));
				} else {
					$SONOS_AVTransportControlProxy{$udn}->Seek(0, 'TRACK_NR', $value1);
				}

				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('Track'));
			}
		} elsif ($workType eq 'setCurrentPlaylist') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				# Abspielliste aktivieren?
				my $currentURI = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0)->getValue('CurrentURI');
				if ($currentURI !~ m/x-rincon-queue:/) {
					my $queueMetadata = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '');
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $queueMetadata->getValue('Result')), '')));
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Not neccessary!');
				}
			}
		} elsif ($workType eq 'getPlaylists') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('SQ:', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
			
				my %resultHash;
				while ($tmp =~ m/<container id="(SQ:\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
					$resultHash{$1} = $2;
				}
				
				if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
					SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'PlaylistsListAlias', join('|', sort values %resultHash));
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'PlaylistsList', join('|', map { $_ =~ s/$SONOS_LISTELEMMASK/\./g; $_ } sort values %resultHash));
					SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': "'.join('","', sort values %resultHash).'"');
				}
			}
		} elsif ($workType eq 'getPlaylistsWithCovers') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my %resultHash = %{SONOS_GetBrowseStructuredResult($udn, 'SQ:', 1, $workType, 1, 1)};
				
				#my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('SQ:', 'BrowseDirectChildren', '', 0, 0, '');
				#my $tmp = $result->getValue('Result');
				#
				#my %resultHash;
				#while ($tmp =~ m/<container id="(SQ:\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<\/container>/ig) {
				#	$resultHash{$1}->{Title} = $2;
				#	$resultHash{$1}->{Cover} = SONOS_MakeCoverURL($udn, $3);
				#	$resultHash{$1}->{Ressource} = decode_entities($3);
				#}
				#
				#if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				#	SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Playlists', SONOS_Dumper(\%resultHash));
				#	
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				#} else {
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash));
				#}
			}
		} elsif ($workType eq 'getFavourites') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('FV:2', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
			
				my %resultHash;
				while ($tmp =~ m/<item id="(FV:2\/\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<\/item>/ig) {
					$resultHash{$1} = $2;
				}
				
				if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
					SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'FavouritesListAlias', join('|', sort values %resultHash));
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'FavouritesList', join('|', map { $_ =~ s/$SONOS_LISTELEMMASK/\./g; $_ } sort values %resultHash));
					SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': "'.join('","', sort values %resultHash).'"');
				}
			}
		} elsif ($workType eq 'getFavouritesWithCovers') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				SONOS_GetBrowseStructuredResult($udn, 'FV:2', 1, $workType, 1);
				
				#my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('FV:2', 'BrowseDirectChildren', '', 0, 0, '');
				#my $tmp = $result->getValue('Result');
				#
				#my %resultHash;
				#while ($tmp =~ m/<item id="(FV:2\/\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<\/item>/ig) {
				#	$resultHash{$1}->{Title} = $2;
				#	$resultHash{$1}->{Cover} = SONOS_MakeCoverURL($udn, $3);
				#	$resultHash{$1}->{Ressource} = decode_entities($3);
				#}
				#
				#if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				#	SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Favourites', SONOS_Dumper(\%resultHash));
				#	
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				#} else {
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash));
				#}
			}
		} elsif ($workType eq 'getSearchlistCategories') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('A:', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
				
				SONOS_Log $udn, 5, 'getSearchlistCategories BrowseResult: '.$tmp;
			
				my %resultHash;
				while ($tmp =~ m/<container id="(A:.*?)".*?><dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
					$resultHash{$1} = $2;
				}
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': "'.join('","', sort values %resultHash).'"');
			}
		} elsif ($workType eq 'exportSonosBibliothek') {
			my $filename = $params[0];
			
			# Anfragen durchführen...
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $exports = {'Structure' => {}, 'Titles' => {}};
				
				SONOS_Log undef, 3, 'ExportSonosBibliothek-Start';
				my $startTime = gettimeofday();
				SONOS_RecursiveStructure($udn, 'A:', $exports->{Structure}, $exports->{Titles});
				SONOS_Log undef, 3, 'ExportSonosBibliothek-End. Runtime (in seconds): '.int(gettimeofday() - $startTime);
				
				my $countTitles = scalar(keys %{$exports->{Titles}});
				
				# In Datei wegschreiben
				eval {
					open FILE, '>'.$filename;
					binmode(FILE, ':encoding(utf-8)');
					print FILE SONOS_Dumper($exports);
					close FILE;
				};
				if ($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Error during filewriting: '.$@);
					return;
				}
				
				$exports = undef;
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Successfully written to file "'.$filename.'", Titles: '.$countTitles.', Duration: '.int(gettimeofday() - $startTime).'s');
			}
		} elsif ($workType eq 'loadSearchlist') {
			# Category holen
			my $regSearch = ($params[0] =~ m/^ *\/(.*)\/ *$/);
			my $searchlistName = $1 if ($regSearch);
			$searchlistName = uri_unescape($params[0]) if (!$regSearch);
			
			# RegEx prüfen...
			if ($regSearch) {
				eval { "" =~ m/$searchlistName/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad Category RegExp "'.$searchlistName.'": '.$@);
					return;
				}
			}
			
			# Element holen
			$params[1] = '' if (!$params[1]);
			my $regSearchElement = ($params[1] =~ m/^ *\/(.*)\/ *$/);
			my $searchlistElement = $1 if ($regSearchElement);
			$searchlistElement = uri_unescape($params[1]) if (!$regSearchElement);
			
			# RegEx prüfen...
			if ($regSearchElement) {
				eval { "" =~ m/$searchlistElement/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad CategoryElement RegExp "'.$searchlistElement.'": '.$@);
					return;
				}
			}
			
			# Filter angegeben?
			my $filter = '//';
			$filter = $params[2] if ($params[2]);
			$filter .= '/' while ((SONOS_CountInString('/', $filter) - SONOS_CountInString('\/', $filter)) < 2);
			my ($filterTitle, $filterAlbum, $filterArtist) = ($1, $3, $5) if ($filter =~ m/((.*?[^\\])|.{0})\/((.*?[^\\])|.{0})\/(.*)/);
			$filterTitle = '.*' if (!$filterTitle);
			$filterAlbum = '.*' if (!$filterAlbum);
			$filterArtist = '.*' if (!$filterArtist);
			SONOS_Log $udn, 4, 'getSearchlist filterTitle: '.$filterTitle;
			SONOS_Log $udn, 4, 'getSearchlist filterAlbum: '.$filterAlbum;
			SONOS_Log $udn, 4, 'getSearchlist filterArtist: '.$filterArtist;
			
			# RegEx prüfen...
			eval { "" =~ m/$filterTitle/ };
			if($@) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad FilterTitle RegExp "'.$filterTitle.'": '.$@);
				return;
			}
			
			# RegEx prüfen...
			eval { "" =~ m/$filterAlbum/ };
			if($@) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad FilterAlbum RegExp "'.$filterAlbum.'": '.$@);
				return;
			}
			
			# RegEx prüfen...
			eval { "" =~ m/$filterArtist/ };
			if($@) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad FilterArtist RegExp "'.$filterArtist.'": '.$@);
				return;
			}
			
			# Menge angegeben? Hier kann auch mit einem '*' eine zufällige Reihenfolge bestimmt werden...
			my $maxElems = '0-';
			$maxElems = $params[3] if ($params[3]);
			
			# Anfragen durchführen...
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('A:', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
				
				SONOS_Log $udn, 5, 'getSearchlistCategories BrowseResult: '.$tmp;
				
				# Category heraussuchen
				my %resultHash;
				while ($tmp =~ m/<container id="(A:.*?)".*?><dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
					next if (SONOS_Trim($2) eq ''); # Wenn kein Titel angegeben ist, dann überspringen
					
					my $name = $2;
					$resultHash{$name} = $1;
					
					# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
					if ($regSearch) {
						if ($name =~ m/$searchlistName/) {
							$searchlistName = $name;
							$regSearch = 0;
						}
					}
				}
				
				# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
				if (!$resultHash{$searchlistName} || $regSearch) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Category "'.$searchlistName.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
					return;
				}
				my $searchlistTitle = $searchlistName;
				$searchlistName = $resultHash{$searchlistName};
				
				###############################################
				# Elemente der Category heraussuchen
				###############################################
				$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchlistName, 'BrowseDirectChildren', '', 0, 0, '');
				$tmp = $result->getValue('Result');
				
				my $numberReturned = $result->getValue('NumberReturned');
				my $totalMatches = $result->getValue('TotalMatches');
				SONOS_Log $udn, 4, 'getSearchlistCategoriesElements StepInfo_0 - NumberReturned: '.$numberReturned.' - Totalmatches: '.$totalMatches;
				while ($numberReturned < $totalMatches) {
					$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchlistName, 'BrowseDirectChildren', '', $numberReturned, 0, '');
					$tmp .= $result->getValue('Result');
				
					$numberReturned += $result->getValue('NumberReturned');
					$totalMatches = $result->getValue('TotalMatches');
					
					SONOS_Log $udn, 4, 'getSearchlistCategoriesElements StepInfo - NumberReturned: '.$numberReturned.' - Totalmatches: '.$totalMatches;
				}
				
				SONOS_Log $udn, 4, 'getSearchlistCategoriesElements Totalmatches: '.$totalMatches;
				SONOS_Log $udn, 5, 'getSearchlistCategoriesElements BrowseResult: '.$tmp;
				
				# Category heraussuchen
				my $searchlistElementTitle = $searchlistElement;
				if ($tmp =~ m/<container id="(A:.*?)".*?>.*?<\/container>/ig) { # Wenn überhaupt noch was zu suchen ist...
					%resultHash = ();
					while ($tmp =~ m/<container id="(A:.*?)".*?><dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
						next if (SONOS_Trim($2) eq ''); # Wenn kein Titel angegeben ist, dann überspringen
						
						my $name = $2;
						$resultHash{$name} = $1;
						
						# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
						if ($regSearchElement) {
							if ($name =~ m/$searchlistElement/) {
								$searchlistElement = $name;
								$regSearchElement = 0;
							}
						}
					}
					
					# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
					if (!$resultHash{$searchlistElement} || $regSearchElement) {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Element "'.$searchlistElement.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
						return;
					}
					$searchlistElementTitle = $searchlistElement;
					$searchlistElement = $resultHash{$searchlistElement};
					
					
					###############################################
					# Ziel-Elemente ermitteln und filtern
					###############################################
					$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchlistElement, 'BrowseDirectChildren', '', 0, 0, '');
					$tmp = $result->getValue('Result');
					
					# Wenn hier noch eine Schicht Container enthalten ist, dann nochmal tiefer gehen...
					while ($tmp && ($tmp =~ m/<container.*?>.*?<\/container>/i)) {
						$searchlistElement .= '/';
						$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchlistElement, 'BrowseDirectChildren', '', 0, 0, '');
						$tmp = $result->getValue('Result');
					}
					
					$numberReturned = $result->getValue('NumberReturned');
					$totalMatches = $result->getValue('TotalMatches');
					SONOS_Log $udn, 4, 'getSearchlistCategoriesElementsEl StepInfo_0 - NumberReturned: '.$numberReturned.' - Totalmatches: '.$totalMatches;
					while ($numberReturned < $totalMatches) {
						$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchlistElement, 'BrowseDirectChildren', '', $numberReturned, 0, '');
						$tmp .= $result->getValue('Result');
					
						$numberReturned += $result->getValue('NumberReturned');
						$totalMatches = $result->getValue('TotalMatches');
						
						SONOS_Log $udn, 4, 'getSearchlistCategoriesElementsEl StepInfo - NumberReturned: '.$numberReturned.' - Totalmatches: '.$totalMatches;
					}
					
					SONOS_Log $udn, 4, 'getSearchlistCategoriesElementsEl Totalmatches: '.$totalMatches;
					SONOS_Log $udn, 5, 'getSearchlistCategoriesElementsEl BrowseResult: '.$tmp;
				}
				
				# Elemente heraussuchen
				%resultHash = ();
				my @URIs = ();
				my @Metas = ();
				while ($tmp =~ m/<item id="(.*?)".*?>(.*?)<\/item>/ig) {
					my $item = $2;
					
					my $uri = $1 if ($item =~ m/<res.*?>(.*?)<\/res>/i);
					$uri =~ s/&apos;/'/gi;
					
					my $title = '';
					$title = $1 if ($item =~ m/<dc:title>(.*?)<\/dc:title>/i);
					
					my $album = '';
					$album = $1 if ($item =~ m/<upnp:album>(.*?)<\/upnp:album>/i);
					
					my $interpret = '';
					$interpret = $1 if ($item =~ m/<dc:creator>(.*?)<\/dc:creator>/i);
					
					# Die Matches merken...
					if (($title =~ m/$filterTitle/) && ($album =~ m/$filterAlbum/) && ($interpret =~ m/$filterArtist/)) {
						my ($res, $meta) = SONOS_CreateURIMeta(SONOS_ExpandURIForQueueing($uri));
						
						push(@URIs, $res);
						push(@Metas, $meta);
					}
				}
				
				my $answer = 'Retrieved all titles of category "'.$searchlistTitle.'" with searchvalue "'.$searchlistElementTitle.'" and filter "'.$filterTitle.'/'.$filterAlbum.'/'.$filterArtist.'" (#'.($#URIs + 1).'). ';
				
				# Liste u.U. vermischen...
				my @matches = (0..$#URIs);
				if ($maxElems =~ m/^\*/) {
					SONOS_Fisher_Yates_Shuffle(\@matches);
					$answer .= 'Shuffled the searchlist. ';
				}
				
				# Nicht alle übernehmen?
				if ($maxElems =~ m/^\*{0,1}(\d+)[\+-]{0,1}$/) {
					splice(@matches, $1) if ($1 && ($1 <= $#matches));
					SONOS_Log $udn, 4, 'getSearchlist maxElems('.$maxElems.'): '.$1;
				}
				SONOS_Log $udn, 4, 'getSearchlist Count Matches: '.($#matches + 1);
				
				# Wenn der AVTransportProxy existiert weitermachen...
				if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
					# Playlist vorher leeren?
					if ($maxElems =~ m/-$/) {
						$SONOS_AVTransportControlProxy{$udn}->RemoveAllTracksFromQueue();
						$answer .= 'Queue successfully emptied. ';
					}
					
					# An das Ende der Playlist oder hinter dem aktuellen Titel einfügen?
					my $currentInsertPos = 0;
					if ($maxElems =~ m/\+$/) {
						$currentInsertPos = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0)->getValue('NrTracks') + 1;
					} else {
						$currentInsertPos = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('Track') + 1;
					}
					
					# Die Matches in die Playlist laden...
					my $sliceSize = 16;
					my $count = 0;
					
					SONOS_Log $udn, 4, "Start-Adding: Count ".scalar(@matches)." / $sliceSize";
					
					if (scalar(@matches)) {
						for my $i (0..int(scalar(@matches) / $sliceSize)) { # Da hier Nullbasiert vorgegangen wird, brauchen wir die letzte Runde nicht noch hinzuaddieren
							my $startIndex = $i * $sliceSize;
							my $endIndex = $startIndex + $sliceSize - 1;
							$endIndex = SONOS_Min(scalar(@matches) - 1, $endIndex);
							
							SONOS_Log $udn, 4, "Add($i) von $startIndex bis $endIndex (".($endIndex - $startIndex + 1)." Elemente)";
							
							my $uri = '';
							my $meta = '';
							for my $index (@matches[$startIndex..$endIndex]) {
								$uri .= ' '.$URIs[$index];
								$meta .= ' '.$Metas[$index];
							}
							$uri = substr($uri, 1) if (length($uri) > 0);
							$meta = substr($meta, 1) if (length($meta) > 0);
							
							$result = $SONOS_AVTransportControlProxy{$udn}->AddMultipleURIsToQueue(0, 0, $endIndex - $startIndex + 1, $uri, $meta, '', '', $currentInsertPos, 0);
							if (!$result->isSuccessful()) {
								$answer .= 'Adding-Error: '.SONOS_UPnPAnswerMessage($result).' ';
							}
							
							$currentInsertPos += $endIndex - $startIndex + 1;
							$count = $endIndex + 1;
						}
						
						if ($result->isSuccessful()) {
							$answer .= 'Added '.$count.' entries from searchlist. There are now '.$result->getValue('NewQueueLength').' entries in Queue. ';
						} else {
							$answer .= 'Adding-Error: '.SONOS_UPnPAnswerMessage($result).' ';
						}
					}
					
					# Die Liste als aktuelles Abspielstück einstellen, falls etwas anderes als die Playliste läuft...
					my $currentMediaInfo = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0);
					my $currentMediaInfoCurrentURI = $currentMediaInfo->getValue('CurrentURI');
					
					my $queueMetadata = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '');
					if ($queueMetadata->getValue('Result') !~ m/<res.*?>$currentMediaInfoCurrentURI<\/res>/) {
						my $result = $SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $queueMetadata->getValue('Result')), '');
						$answer .= 'Startlist: '.SONOS_UPnPAnswerMessage($result).'. ';
					} else {
						$answer .= 'Startlist not neccessary. ';
					}
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$answer);
				}
			}
		} elsif ($workType eq 'getRadios') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('R:0/0', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
			
				my %resultHash;
				while ($tmp =~ m/<item id="(R:0\/0\/\d+)".*?><dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<\/item>/ig) {
					$resultHash{$1} = $2;
				}
				
				if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
					SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'RadiosListAlias', join('|', sort values %resultHash));
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'RadiosList', join('|', map { $_ =~ s/$SONOS_LISTELEMMASK/\./g; $_ } sort values %resultHash));
					SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': "'.join('","', sort values %resultHash).'"');
				}
			}
		} elsif ($workType eq 'getRadiosWithCovers') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my %resultHash = %{SONOS_GetBrowseStructuredResult($udn, 'R:0/0', 1, $workType, 1)};
				
				#my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('R:0/0', 'BrowseDirectChildren', '', 0, 0, '');
				#my $tmp = $result->getValue('Result');
				#
				#my %resultHash;
				#while ($tmp =~ m/<item id="(R:0\/0\/\d+)".*?><dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<\/item>/ig) {
				#	$resultHash{$1}->{Title} = $2;
				#	$resultHash{$1}->{Cover} = SONOS_MakeCoverURL($udn, $3);
				#	$resultHash{$1}->{Ressource} = decode_entities($3);
				#}
				#
				#if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				#	SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Radios', SONOS_Dumper(\%resultHash));
				#	
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				#} else {
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash));
				#}
			}
		} elsif ($workType eq 'getQueue') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
				
				my $numberReturned = $result->getValue('NumberReturned');
				my $totalMatches = $result->getValue('TotalMatches');
				while ($numberReturned < $totalMatches) {
					$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', $numberReturned, 0, '');
					$tmp .= $result->getValue('Result');
				
					$numberReturned += $result->getValue('NumberReturned');
					$totalMatches = $result->getValue('TotalMatches');
				}
				
				my @inputArray;
				while ($tmp =~ m/(<item id="Q:0\/\d+".*?>.*?<\/item>)/ig) {
					push(@inputArray, $1);
				}
				
				my @resultArray;
				my $position = 0;
				foreach my $line (@inputArray) {
					my $id = $1 if ($line =~ m/<item id="(Q:0\/\d+)".*?>.*?<\/item>/i);
					my $duration = $1 if ($line =~ m/<item id="Q:0\/\d+".*?>.*?<res.*?duration="(.+?)".*?>.*?<\/item>/i);
					my $res = $1 if ($line =~ m/<item id="Q:0\/\d+".*?>.*?<res.*?>(.*?)<\/res>.*?<\/item>/i);
					my $title = $1 if ($line =~ m/<item id="Q:0\/\d+".*?>.*?<dc:title>(.*?)<\/dc:title>.*?<\/item>/i);
					my $artist = $1 if ($line =~ m/<item id="Q:0\/\d+".*?>.*?<dc:creator>(.*?)<\/dc:creator>.*?<\/item>/i);
					my $album = $1 if ($line =~ m/<item id="Q:0\/\d+".*?>.*?<upnp:album>(.*?)<\/upnp:album>.*?<\/item>/i);
					
					if ($duration) {
						push(@resultArray, ++$position.'. ('.$artist.') '.$title.' ['.$duration.']');
					} else {
						push(@resultArray, ++$position.'. ('.$artist.') '.$title.' [k.A.]');
					}
				}
				
				if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
					SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueListAlias', join('|', @resultArray));
					
					# Elemente um 1 verschieben...
					unshift(@resultArray, ''); @resultArray = keys @resultArray; shift(@resultArray);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueList', join('|', @resultArray));
					SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': "'.join('","', @resultArray).'"');
				}
			}
		} elsif ($workType eq 'getQueueWithCovers') {
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				SONOS_GetQueueStructuredResult($udn, 1, 'getQueueWithCovers');
				#my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '');
				#my $tmp = $result->getValue('Result');
				#
				#my $numberReturned = $result->getValue('NumberReturned');
				#my $totalMatches = $result->getValue('TotalMatches');
				#while ($numberReturned < $totalMatches) {
				#	$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', $numberReturned, 0, '');
				#	$tmp .= $result->getValue('Result');
				#	
				#	$numberReturned += $result->getValue('NumberReturned');
				#	$totalMatches = $result->getValue('TotalMatches');
				#}
				#
				#my %resultHash;
				#$resultHash{DurationSec} = 0;
				#$resultHash{Duration} = '0:00:00';
				#my $position = 0;
				#while ($tmp =~ m/<item id="(Q:0\/)(\d+)".*?>.*?<res.*?(duration="(.+?)"|).*?>(.*?)<\/res>.*?<dc:title>(.*?)<\/dc:title>.*?<dc:creator>(.*?)<\/dc:creator>.*?<upnp:album>(.*?)<\/upnp:album>.*?<\/item>/ig) {
				#	my $key = $1.sprintf("%04d", $2);
				#	$resultHash{$key}->{Position} = ++$position;
				#	$resultHash{$key}->{Title} = $6;
				#	$resultHash{$key}->{Artist} = $7;
				#	$resultHash{$key}->{Album} = $8;
				#	if (defined($4)) {
				#		$resultHash{$key}->{ShowTitle} = $position.'. ('.$7.') '.$6.' ['.$4.']';
				#		$resultHash{$key}->{Duration} = $4;
				#		$resultHash{$key}->{DurationSec} = SONOS_GetTimeSeconds($4);
				#		$resultHash{DurationSec} += SONOS_GetTimeSeconds($4);
				#	} else {
				#		$resultHash{$key}->{ShowTitle} = $position.'. ('.$7.') '.$6.' [k.A.]';
				#		$resultHash{$key}->{Duration} = '0:00:00';
				#		$resultHash{$key}->{DurationSec} = 0;
				#	}
				#	$resultHash{$key}->{Cover} = SONOS_MakeCoverURL($udn, $5);
				#	$resultHash{$key}->{Ressource} = decode_entities($5);
				#}
				#$resultHash{Duration} = SONOS_ConvertSecondsToTime($resultHash{DurationSec});
				#
				#if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				#	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
				#	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueDuration', $resultHash{Duration});
				#	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueDurationSec', $resultHash{DurationSec});
				#	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'Queue', SONOS_Dumper(\%resultHash));
				#	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
				#	
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet');
				#} else {
				#	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash));
				#}
			}
		} elsif ($workType eq 'loadRadio') {
			my $regSearch = ($params[0] =~ m/^ *\/(.*)\/ *$/);
			my $radioName = $1 if ($regSearch);
			$radioName = uri_unescape($params[0]) if (!$regSearch);
			
			# Alle übergebenen Anführungszeichen in die HTML Entity übersetzen, da es so auch von Sonos geliefert wird.
			$radioName =~ s/'/&apos;/g;
			
			# RegEx prüfen...
			if ($regSearch) {
				eval { "" =~ m/$radioName/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad RegExp "'.$radioName.'": '.$@);
					return;
				}
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('R:0/0', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
				
				SONOS_Log $udn, 5, 'LoadRadio BrowseResult: '.$tmp;
			
				my %resultHash;
				while ($tmp =~ m/(<item id="(R:0\/0\/\d+)".*?>)<dc:title>(.*?)<\/dc:title>.*?(<upnp:class>.*?<\/upnp:class>).*?<res.*?>(.*?)<\/res>.*?<\/item>/ig) {
					my $name = $3;
					$resultHash{$name}{TITLE} = $name;
					$resultHash{$name}{RES} = decode_entities($5);
					$resultHash{$name}{METADATA} = $SONOS_DIDLHeader.$1.'<dc:title>'.$name.'</dc:title>'.$4.'<desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item>'.$SONOS_DIDLFooter;
					
					# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
					if ($regSearch) {
						if ($name =~ m/$radioName/) {
							$radioName = $name;
							$regSearch = 0;
						}
					}
				}
				
				# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
				if (!$resultHash{$radioName} || $regSearch) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Radio "'.$radioName.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
					return;
				}
			
				if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
					SONOS_Log $udn, 5, 'LoadRadio SetAVTransport-Res: "'.$resultHash{$radioName}{RES}.'", -Meta: "'.$resultHash{$radioName}{METADATA}.'"';
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, $resultHash{$radioName}{RES}, $resultHash{$radioName}{METADATA})));
				}
			}
		} elsif ($workType eq 'startFavourite') {
			my $regSearch = ($params[0] =~ m/^ *\/(.*)\/ *$/);
			my $favouriteName = $1 if ($regSearch);
			$favouriteName = uri_unescape($params[0]) if (!$regSearch);
			
			# Alle übergebenen Anführungszeichen in die HTML Entity übersetzen, da es so auch von Sonos geliefert wird.
			$favouriteName =~ s/'/&apos;/g;
			
			# RegEx prüfen...
			if ($regSearch) {
				eval { "" =~ m/$favouriteName/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad RegExp "'.$favouriteName.'": '.$@);
					return;
				}
			}
			
			my $nostart = 0;
			if (defined($params[1]) && lc($params[1]) eq 'nostart') {
				$nostart = 1;
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('FV:2', 'BrowseDirectChildren', '', 0, 0, '');
				my $tmp = $result->getValue('Result');
				
				SONOS_Log $udn, 5, 'StartFavourite BrowseResult: '.$tmp;
			
				my %resultHash;
				while ($tmp =~ m/(<item id="(FV:2\/\d+)".*?>)<dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<r:resMD>(.*?)<\/r:resMD>.*?<\/item>/ig) {
					my $name = $3;
					$resultHash{$name}{TITLE} = $name;
					$resultHash{$name}{RES} = decode_entities($4);
					$resultHash{$name}{METADATA} = decode_entities($5);
					
					# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
					if ($regSearch) {
						if ($name =~ m/$favouriteName/) {
							$favouriteName = $name;
							$regSearch = 0;
						}
					}
				}
				
				# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
				if (!$resultHash{$favouriteName} || $regSearch) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Favourite "'.$favouriteName.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
					return;
				}
				
				SONOS_StartMetadata($workType, $udn, $resultHash{$favouriteName}{RES}, $resultHash{$favouriteName}{METADATA}, $nostart);
				
#						if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
#							# Entscheiden, ob eine Abspielliste geladen und gestartet werden soll, oder etwas direkt abgespielt werden kann
#							if ($resultHash{$favouriteName}{METADATA} =~ m/<upnp:class>object\.container.*?<\/upnp:class>/i) {
#								SONOS_Log $udn, 5, 'StartFavourite AddToQueue-Res: "'.$resultHash{$favouriteName}{RES}.'", -Meta: "'.$resultHash{$favouriteName}{METADATA}.'"';
#								
#								# Queue leeren
#								$SONOS_AVTransportControlProxy{$udn}->RemoveAllTracksFromQueue(0);
#								
#								# Queue wieder füllen
#								SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->AddURIToQueue(0, $resultHash{$favouriteName}{RES}, $resultHash{$favouriteName}{METADATA}, 0, 1)));
#								
#								# Queue aktivieren
#								$SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '')->getValue('Result')), '');
#							} else {
#								SONOS_Log $udn, 5, 'StartFavourite SetAVTransport-Res: "'.$resultHash{$favouriteName}{RES}.'", -Meta: "'.$resultHash{$favouriteName}{METADATA}.'"';
#								
#								# Stück aktivieren
#								SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, $resultHash{$favouriteName}{RES}, $resultHash{$favouriteName}{METADATA})));
#							}
#							
#							# Abspielen starten, wenn nicht absichtlich verhindert
#							$SONOS_AVTransportControlProxy{$udn}->Play(0, 1) if (!$nostart);
#						}
			}
		} elsif ($workType eq 'loadPlaylist') {
			my $answer = '';
			
			my $regSearch = ($params[0] =~ m/^ *\/(.*)\/ *$/);
			my $playlistName = $1 if ($regSearch);
			$playlistName = uri_unescape($params[0]) if (!$regSearch);
			
			# Alle übergebenen Anführungszeichen in die HTML Entity übersetzen, da es so auch von Sonos geliefert wird.
			$playlistName =~ s/'/&apos;/g;
			
			# RegEx prüfen...
			if ($regSearch) {
				eval { "" =~ m/$playlistName/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad RegExp "'.$playlistName.'": '.$@);
					return;
				}
			}
			
			my $overwrite = $params[1];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn}) && SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				# Queue vorher leeren?
				if ($overwrite) {
					$SONOS_AVTransportControlProxy{$udn}->RemoveAllTracksFromQueue();
					$answer .= 'Queue successfully emptied. ';
				}
				
				my $currentInsertPos = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('Track') + 1;
				
				if ($playlistName =~ /^:m3ufile:(.*)/) {
					my @URIs = ();
					my @Metas = ();
					
					# Versuche die Datei zu öffnen
					if (!open(FILE, '<'.$1)) {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Error during opening file "'.$1.'": '.$!); 
						return;
					};
					
					binmode(FILE, ':encoding(utf-8)');
					while (<FILE>) {
						if ($_ =~ m/^ *([^#].*) *\n/) {
							next if ($1 eq '');
							
							my ($res, $meta) = SONOS_CreateURIMeta(SONOS_ExpandURIForQueueing($1));
							
							push(@URIs, $res);
							push(@Metas, $meta);
						}
					}
					close FILE;
					
					# Elemente an die Queue anhängen
					$answer .= SONOS_AddMultipleURIsToQueue($udn, \@URIs, \@Metas, $currentInsertPos);
				} elsif ($playlistName =~ /^:device:(.*)/) {
					my $sourceUDN = $1;
					my @URIs = ();
					my @Metas = ();
					
					# Titel laden
					my $playlistData;
					my $startIndex = 0;
					
					do {
						$playlistData = $SONOS_ContentDirectoryControlProxy{$sourceUDN}->Browse('Q:0', 'BrowseDirectChildren', '', $startIndex, 0, '');
						my $tmp = decode('UTF-8', $playlistData->getValue('Result'));
						
						while ($tmp =~ m/<item.*?>.*?<res.*?>(.*?)<\/res>.*?<\/item>/ig) {
							my ($res, $meta) = SONOS_CreateURIMeta(decode_entities($1));
							next if (!defined($res));
							
							push(@URIs, $res);
							push(@Metas, $meta);
						}
						
						$startIndex += $playlistData->getValue('NumberReturned');
					} while ($startIndex < $playlistData->getValue('TotalMatches'));
					
					# Elemente an die Queue anhängen
					$answer .= SONOS_AddMultipleURIsToQueue($udn, \@URIs, \@Metas, $currentInsertPos);
				} else {
					my $browseResult = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('SQ:', 'BrowseDirectChildren', '', 0, 0, '');
					my $tmp = $browseResult->getValue('Result');
				
					my %resultHash;
					while ($tmp =~ m/<container id="(SQ:\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
						my $name = $2;
						$resultHash{$name} = $1;
						
						# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
						if ($regSearch) {
							if ($name =~ m/$playlistName/) {
								$playlistName = $name;
								$regSearch = 0;
							}
						}
					}
					
					# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
					if (!$resultHash{$playlistName} || $regSearch) {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Playlist "'.$playlistName.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
						return;
					}
				
					# Titel laden
					my $playlistData = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($resultHash{$playlistName}, 'BrowseMetadata', '', 0, 0, '');
					my $playlistRes = SONOS_GetTagData('res', $playlistData->getValue('Result'));
				
					# Elemente an die Queue anhängen
					my $result = $SONOS_AVTransportControlProxy{$udn}->AddURIToQueue(0, $playlistRes, '', $currentInsertPos, 0);
					$answer .= $result->getValue('NumTracksAdded').' Elems added. '.$result->getValue('NewQueueLength').' Elems in list now. ';
				}
				
				# Die Liste als aktuelles Abspielstück einstellen
				my $queueMetadata = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '');
				my $result = $SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $queueMetadata->getValue('Result')), '');
				$answer .= 'Startlist: '.SONOS_UPnPAnswerMessage($result).'. ';
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$answer);
			}
		} elsif ($workType eq 'setAlarm') {
			my $create = $params[0];
			my @idParams = split(',', $params[1]);
			
			# Die passenden IDs heraussuchen...
			my @idList = map { SONOS_Trim($_) } split(',', SONOS_Client_Data_Retreive($udn, 'reading', 'AlarmListIDs', ''));
			my @id = ();
			foreach my $elem (@idList) {
				if ((lc($idParams[0]) eq 'all') || SONOS_isInList($elem, @idParams)) {
					push @id, $elem;
				}
			}
			
			# Alle folgenden Parameter weglesen und an den letzten Parameter anhängen
			my $values = {};
			my $val = join(',', @params[2..$#params]);
			if ($val ne '') {
				$values = \%{eval($val)};
			}
			
			# Wenn keine passenden Elemente gefunden wurden...
			if (scalar(@id) == 0) {
				if ((lc($create) eq 'update') || (lc($create) eq 'delete')) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_AnswerMessage(0));
				}
			}
			
			# Hier die passenden Änderungen durchführen...
			if (SONOS_CheckProxyObject($udn, $SONOS_AlarmClockControlProxy{$udn})) {
				# Die Room-ID immer fest auf den aktuellen Player eintragen. 
				# Hiermit sollte es nicht mehr möglich sein, einen Alarm für einen anderen Player einzutragen. Das kann man auch direkt an dem anderen Player durchführen...
				$values->{RoomUUID} = $1 if ($udn =~ m/(.*?)_MR/i);
				
				if (lc($create) eq 'update') {
					my $ret = '';
					
					foreach my $id (@id) {
						my %alarm = %{eval(SONOS_Client_Data_Retreive($udn, 'reading', 'AlarmList', '{}'))->{$id}};
						
						# Replace old values with the given new ones...
						for my $key (keys %alarm) {
							if (defined($values->{$key})) {
								$alarm{$key} = $values->{$key};
							}
						}
						
						if (!SONOS_CheckAndCorrectAlarmHash(\%alarm)) {
							$ret .= '#'.$id.': '.SONOS_AnswerMessage(0).', ';
						} else {
							# Send to Zoneplayer
							$ret .= '#'.$id.': '.SONOS_UPnPAnswerMessage($SONOS_AlarmClockControlProxy{$udn}->UpdateAlarm($id, $alarm{StartTime}, $alarm{Duration}, $alarm{Recurrence}, $alarm{Enabled}, $alarm{RoomUUID}, $alarm{ProgramURI}, $alarm{ProgramMetaData}, $alarm{PlayMode}, $alarm{Volume}, $alarm{IncludeLinkedZones})).', ';
						}
					}
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$ret);
				} elsif (lc($create) eq 'create') {
					# Check if all parameters are given
					if (!SONOS_CheckAndCorrectAlarmHash($values)) {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_AnswerMessage(0));
					} else {
						# create here on Zoneplayer
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$SONOS_AlarmClockControlProxy{$udn}->CreateAlarm($values->{StartTime}, $values->{Duration}, $values->{Recurrence}, $values->{Enabled}, $values->{RoomUUID}, $values->{ProgramURI}, $values->{ProgramMetaData}, $values->{PlayMode}, $values->{Volume}, $values->{IncludeLinkedZones})->getValue('AssignedID'));
					}
				} elsif (lc($create) eq 'delete') {
					my $ret = '';
					
					foreach my $id (@id) {
						$ret .= '#'.$id.': '.SONOS_UPnPAnswerMessage($SONOS_AlarmClockControlProxy{$udn}->DestroyAlarm($id)).', ';
					}
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.$ret);
				} else {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_AnswerMessage(0));
				}
			}
		} elsif ($workType eq 'setSnoozeAlarm') {
			my $time = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SnoozeAlarm(0, $time)));
			}
		} elsif ($workType eq 'setDailyIndexRefreshTime') {
			my $time = $params[0];
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AlarmClockControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AlarmClockControlProxy{$udn}->SetDailyIndexRefreshTime($time)));
			}
		} elsif ($workType eq 'setSleepTimer') {
			my $time = $params[0];
			
			if ((lc($time) eq 'off') || ($time =~ /0+:0+:0+/)) {
				$time = '';
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->ConfigureSleepTimer(0, $time)));
			}
		} elsif ($workType eq 'addMember') {
			my $memberudn = $params[0];
			
			if (SONOS_CheckProxyObject($memberudn, $SONOS_AVTransportControlProxy{$memberudn}) && SONOS_CheckProxyObject($memberudn, $SONOS_ZoneGroupTopologyProxy{$memberudn})) {
				# Wenn der hinzuzufügende Player Koordinator einer anderen Gruppe ist,
				# dann erst mal ein anderes Gruppenmitglied zum Koordinator machen
				#my @zoneTopology = SONOS_ConvertZoneGroupState($SONOS_ZoneGroupTopologyProxy{$memberudn}->GetZoneGroupState()->getValue('ZoneGroupState'));
				
				# Hier fehlt noch die Umstellung der bestehenden Gruppe...
				
				# Sicherstellen, dass der hinzuzufügende Player kein Bestandteil einer Gruppe mehr ist.
				$SONOS_AVTransportControlProxy{$memberudn}->BecomeCoordinatorOfStandaloneGroup(0);
			
				my $coordinatorUDNShort = $1 if ($udn =~ m/(.*)_MR/);
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$memberudn}->SetAVTransportURI(0, 'x-rincon:'.$coordinatorUDNShort, '')));
			}
		} elsif ($workType eq 'removeMember') {
			my $memberudn = $params[0];
			
			if (SONOS_CheckProxyObject($memberudn, $SONOS_AVTransportControlProxy{$memberudn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$memberudn}->BecomeCoordinatorOfStandaloneGroup(0)));
			}
		} elsif ($workType eq 'makeStandaloneGroup') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->BecomeCoordinatorOfStandaloneGroup(0)));
			}
		} elsif ($workType eq 'createStereoPair') {
			my $pairString = uri_unescape($params[0]);
		
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_DevicePropertiesProxy{$udn}->CreateStereoPair($pairString)));
			}
		} elsif ($workType eq 'separateStereoPair') {
			my $pairString = uri_unescape($params[0]);
		
			if (SONOS_CheckProxyObject($udn, $SONOS_DevicePropertiesProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_DevicePropertiesProxy{$udn}->SeparateStereoPair($pairString)));
			}
		} elsif ($workType eq 'emptyPlaylist') {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->RemoveAllTracksFromQueue()));
			}
		} elsif ($workType eq 'savePlaylist') {
			my $playlistName = $params[0];
			my $playlistType = $params[1];
			
			$playlistName =~ s/ $//g;
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				if ($playlistType eq ':m3ufile:') {
					open (FILE, '>'.$playlistName);
					print FILE "#EXTM3U\n";
					
					my $startIndex = 0;
					my $result;
					my $count = 0;
					do {
						$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', $startIndex, 0, '');
						my $queueSongdata = $result->getValue('Result');
						
						while ($queueSongdata =~ m/<item.*?>(.*?)<\/item>/gi) {
							my $item = $1;
							my $res = uri_unescape(SONOS_GetURIFromQueueValue(decode_entities($1))) if ($item =~ m/<res.*?>(.*?)<\/res>/i);
							my $artist = decode_entities($1) if ($item =~ m/<dc:creator.*?>(.*?)<\/dc:creator>/i);
							my $title = decode_entities($1) if ($item =~ m/<dc:title.*?>(.*?)<\/dc:title>/i);
							my $time = 0;
							$time = SONOS_GetTimeSeconds($1) if ($item =~ m/.*?duration="(.*?)"/);
							
							# In Datei wegschreiben
							eval {
								print FILE "#EXTINF:$time,($artist) $title\n$res\n";
							};
							$count++;
						}
						
						$startIndex += $result->getValue('NumberReturned');
					} while ($startIndex < $result->getValue('TotalMatches'));
					
					
					close FILE;
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': New M3U-File "'.$playlistName.'" successfully created with '.$count.' entries!');
				} else {
					my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('SQ:', 'BrowseDirectChildren', '', 0, 0, '');
					my $tmp = $result->getValue('Result');
				
					my %resultHash;
					while ($tmp =~ m/<container id="(SQ:\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
						$resultHash{$2} = $1;
					}
					
					if ($resultHash{$playlistName}) {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Existing Playlist "'.$playlistName.'" updated: '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SaveQueue(0, $playlistName, $resultHash{$playlistName})));
					} else {
						SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': New Playlist '.$playlistName.' created: '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SaveQueue(0, $playlistName, '')));
					}
				}
			}
		} elsif ($workType eq 'deleteFromQueue') {
			$params[0] = uri_unescape($params[0]);
			
			# Simple Check...
			if ($params[0] !~ m/^[\.\,\d]*$/) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Parameter Error: '.$params[0]);
				return;
			}
			my @elemList = sort { $a <=> $b } SONOS_DeleteDoublettes(eval('('.$params[0].')'));
			SONOS_Log undef, 5, 'DeleteFromQueue: Index-Liste: '.Dumper(\@elemList);
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn}) && SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
				# Maximale Indizies bestimmen
				my $maxElems = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '')->getValue('TotalMatches');
				
				my $deleteCounter = 0;
				foreach my $elem (@elemList) {
					if (($elem > 0) && ($elem <= $maxElems)) {
						$deleteCounter++ if ($SONOS_AVTransportControlProxy{$udn}->RemoveTrackFromQueue(0, 'Q:0/'.($elem - $deleteCounter), 0)->isSuccessful());
					}
				}
				
				$maxElems = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '')->getValue('TotalMatches');
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Deleted '.$deleteCounter.' elems. In list are now '.$maxElems.' elems.');
			}
		} elsif ($workType eq 'deletePlaylist') {
			my $regSearch = ($params[0] =~ m/^ *\/(.*)\/ *$/);
			my $playlistName = $1 if ($regSearch);
			$playlistName = uri_unescape($params[0]) if (!$regSearch);
			
			# RegEx prüfen...
			if ($regSearch) {
				eval { "" =~ m/$playlistName/ };
				if($@) {
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Bad RegExp "'.$playlistName.'": '.$@);
					return;
				}
			}
			
			my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('SQ:', 'BrowseDirectChildren', '', 0, 0, '');
			my $tmp = $result->getValue('Result');
			
			my %resultHash;
			while ($tmp =~ m/<container id="(SQ:\d+)".*?<dc:title>(.*?)<\/dc:title>.*?<\/container>/ig) {
				my $name = $2;
				$resultHash{$name} = $1;
				
				# Den ersten Match ermitteln, und sich den echten Namen für die Zukunft merken...
				if ($regSearch) {
					if ($name =~ m/$playlistName/) {
						$playlistName = $name;
						$regSearch = 0;
					}
				}
			}
			
			# Wenn RegSearch gesetzt war, und nichts gefunden wurde...
			if (!$resultHash{$playlistName} || $regSearch) {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Playlist "'.$playlistName.'" not found. Choose one of: "'.join('","', sort keys %resultHash).'"');
				return;
			}
			
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Playlist "'.$playlistName.'" deleted: '.SONOS_UPnPAnswerMessage($SONOS_ContentDirectoryControlProxy{$udn}->DestroyObject($resultHash{$playlistName})));
		} elsif ($workType eq 'deleteProxyObjects') {
			# Wird vom Sonos-Device selber in IsAlive benötigt
			SONOS_DeleteProxyObjects($udn);
			
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_AnswerMessage(1));
		} elsif ($workType eq 'renewSubscription') {
			if (defined($SONOS_TransportSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_TransportSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_TransportSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'Transport-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! Transport-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_RenderingSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_RenderingSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_RenderingSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'Rendering-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! Rendering-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_GroupRenderingSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_GroupRenderingSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_GroupRenderingSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'GroupRendering-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! GroupRendering-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_ContentDirectorySubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_ContentDirectorySubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_ContentDirectorySubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'ContentDirectory-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! ContentDirectory-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_AlarmSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_AlarmSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_AlarmSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'Alarm-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! Alarm-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_ZoneGroupTopologySubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_ZoneGroupTopologySubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_ZoneGroupTopologySubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'ZoneGroupTopology-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! ZoneGroupTopology-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_DevicePropertiesSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_DevicePropertiesSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_DevicePropertiesSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'DeviceProperties-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! DeviceProperties-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_AudioInSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_AudioInSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_AudioInSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'AudioIn-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! AudioIn-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}
			
			if (defined($SONOS_MusicServicesSubscriptions{$udn}) && (Time::HiRes::time() - $SONOS_MusicServicesSubscriptions{$udn}->{_startTime} > $SONOS_SUBSCRIPTIONSRENEWAL)) {
				eval {
					$SONOS_MusicServicesSubscriptions{$udn}->renew();
					SONOS_Log $udn, 3, 'MusicServices-Subscription for ZonePlayer "'.$udn.'" has expired and is now renewed.';
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Error! MusicServices-Subscription for ZonePlayer "'.$udn.'" has expired and could not be renewed: '.$@;
					
					# Wenn der Player nicht erreichbar war, dann entsprechend entfernen...
					# Hier aber nur eine kleine Lösung, da es nur ein Notbehelf sein soll...
					if ($@ =~ m/Can.t connect to/) {
						SONOS_DeleteProxyObjects($udn);
						
						# Player-Informationen aktualisieren...
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
						SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
						
						# Discovery neu anstarten, falls der Player irgendwie doch noch erreichbar sein sollte...
						$SONOS_Search = $SONOS_Controlpoint->searchByType('urn:schemas-upnp-org:device:ZonePlayer:1', \&SONOS_Discover_Callback);
					}
				}
			}

		} elsif ($workType eq 'startHandle') {
			if ($params[0] =~ m/^(.+)\|(.+)$/) {
				my $songURI = $1;
				my $songMeta = $2;
				SONOS_Log undef, 4, 'songURI: '.$songURI;
				SONOS_Log undef, 4, 'songMeta: '.$songMeta;
				SONOS_Log undef, 4, 'nostart: '.$params[1];
				
				SONOS_StartMetadata($workType, $udn, $songURI, $songMeta, $params[1]);
			} else {
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Wrong Handle: '.$params[0]);
			}
		} elsif ($workType eq 'playURI') {
			my $songURI = SONOS_ExpandURIForQueueing($params[0]);
			SONOS_Log undef, 4, 'songURI: '.$songURI;
			
			my $volume;
			if ($#params > 0) {
				$volume = $params[1];
			}
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				my ($uri, $meta) = SONOS_CreateURIMeta($songURI);
				SONOS_Log undef, 4, 'URI: '.$uri;
				SONOS_Log undef, 4, 'Meta: '.$meta;
				$SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, $uri, $meta);
				
				if (defined($volume)) {
					if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
						$SONOS_GroupRenderingControlProxy{$udn}->SnapshotGroupVolume(0);
						if ($volume =~ m/^[+-]{1}/) {
							$SONOS_GroupRenderingControlProxy{$udn}->SetRelativeGroupVolume(0, $volume)
						} else {
							$SONOS_GroupRenderingControlProxy{$udn}->SetGroupVolume(0, $volume);
						}
					}
				}
			
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_AnswerMessage($SONOS_AVTransportControlProxy{$udn}->Play(0, 1)->isSuccessful));
			}
		} elsif ($workType eq 'playURITemp') {
			my $destURL = $params[0];
			
			my $volume;
			if ($#params > 0) {
				$volume = $params[1];
			}
			
			SONOS_PlayURITemp($udn, $destURL, $volume);
		} elsif ($workType eq 'addURIToQueue') {
			my $songURI = SONOS_ExpandURIForQueueing($params[0]);
			
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				my $track = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('Track');
				
				my ($uri, $meta) = SONOS_CreateURIMeta($songURI);
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->AddURIToQueue(0, $uri, $meta, $track + 1, 1)));
			}
		} elsif ($workType =~ m/speak\d+/i) {
			my $volume = $params[0];
			my $language = $params[1];
			
			my $text = $params[2];
			for(my $i = 3; $i < @params; $i++) {
				$text .= ','.$params[$i];
			}
			$text =~ s/^ *(.*) *$/$1/g;
			$text = SONOS_Utf8ToLatin1($text);
			
			my $digest = '';
			if (SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakFileHashCache', 0) == 1) {
				eval {
					require Digest::SHA1;
					import Digest::SHA1 qw(sha1_hex);
					$digest = '_'.sha1_hex(lc($text));
				};
				if ($@ =~ /Can't locate Digest\/SHA1.pm in/i) {
					# Unter Ubuntu gibt es die SHA1-Library nicht mehr, sodass man dort eine andere einbinden muss (SHA)
					eval {
						require Digest::SHA;
						import Digest::SHA qw(sha1_hex);
						$digest = '_'.sha1_hex(lc($text));
					};
				}
				if ($@ =~ /Wide character in subroutine entry/i) {
					eval {
						require Digest::SHA1;
						import Digest::SHA1 qw(sha1_hex);
						$digest = '_'.sha1_hex(lc(encode("iso-8859-1", $text, 0)));
					};
					
					if ($@ =~ /Can't locate Digest\/SHA1.pm in/i) {
						eval {
							require Digest::SHA;
							import Digest::SHA qw(sha1_hex);
							$digest = '_'.sha1_hex(lc(encode("iso-8859-1", $text, 0)));
						};
					}
				}
				if ($@) {
					SONOS_Log $udn, 2, 'Beim Ermitteln des Hash-Wertes ist ein Fehler aufgetreten: '.$@;
					return;
				}
			}
			
			my $timestamp = '';
			if (!$digest && SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakFileTimestamp', 0) == 1) {
				my @timearray = localtime;
				$timestamp = sprintf("_%04d%02d%02d-%02d%02d%02d", $timearray[5]+1900, $timearray[4]+1, $timearray[3], $timearray[2], $timearray[1], $timearray[0]);
			}
			
			my $fileExtension = SONOS_GetSpeakFileExtension($workType);
			my $dest = SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakDir', '.').'/'.$udn.'_Speak'.$timestamp.$digest.'.'.$fileExtension;
			my $destURL = SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakURL', '').'/'.$udn.'_Speak'.$timestamp.$digest.'.'.$fileExtension;
			
			if ($digest && (-e $dest)) {
				SONOS_Log $udn, 3, 'Hole die Durchsage aus dem Cache...';
			} else {
				if (!SONOS_GetSpeakFile($udn, $workType, $language, $text, $dest)) {
					return;
				}
				
				# MP3-Tags setzen, wenn die entsprechende Library gefunden wurde, und die Ausgabe in ein MP3-Format erfolgte
				if (lc(substr($dest, -3, 3)) eq 'mp3') {
					eval {
						my $mp3GroundPath = SONOS_GetAbsolutePath($0);
						$mp3GroundPath = substr($mp3GroundPath, 0, rindex($mp3GroundPath, '/'));
						
						require MP3::Tag;
						my $mp3 = MP3::Tag->new($dest);
						$mp3->config(write_v24 => 1);
						
						$mp3->title_set($text);
						$mp3->artist_set('FHEM ~ Sonos');
						$mp3->album_set('Sprachdurchsagen');
						my $coverPath = SONOS_Client_Data_Retreive('undef', 'attr', ucfirst(lc(($workType =~ /0$/) ? 'speak' : $workType)).'Cover', $mp3GroundPath.'/www/images/default/fhemicon.png');
						my $imgfile = SONOS_ReadFile($coverPath);
						$mp3->set_id3v2_frame('APIC', 0, (($coverPath =~ m/\.png$/) ? 'image/png' : 'image/jpeg'), chr(3), 'Cover Image', $imgfile) if ($imgfile);
						$mp3->update_tags();
					};
					if ($@) {
						SONOS_Log $udn, 2, 'Beim Setzen der MP3-Informationen (ID3TagV2) ist ein Fehler aufgetreten: '.$@;
					}
				}
			}
			
			SONOS_PlayURITemp($udn, $destURL, $volume);
		} elsif ($workType eq 'restartControlPoint') {
			SONOS_RestartControlPoint();
		} else {
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DoWork-Syntax ERROR');
		}
	};
	if ($@) {
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', 'DoWork-Exception ERROR: '.$@);
	}
}

########################################################################################
#
#  SONOS_GetBrowseStructuredResult - Browse and give the result back
#
########################################################################################
sub SONOS_GetBrowseStructuredResult($$@) {
	my ($udn, $searchValue, $withLastActionResult, $workType, $singleUpdate, $container) = @_;
	
	$withLastActionResult = 0 if (!defined($withLastActionResult));
	
	$workType = '' if (!defined($workType));
	
	$singleUpdate = 0 if (!defined($singleUpdate));
	
	if (defined($container)) {
		$container = 'container';
	} else {
		$container = 'item';
	}
	
	my %resultHash = ();
	if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
		my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($searchValue, 'BrowseDirectChildren', '', 0, 0, '');
		my $tmp = $result->getValue('Result');
		
		while ($tmp =~ m/<$container id="(.+?)".*?><dc:title>(.*?)<\/dc:title>.*?<res.*?>(.*?)<\/res>.*?<\/$container>/ig) {
			$resultHash{$1}->{Title} = $2;
			$resultHash{$1}->{Cover} = SONOS_MakeCoverURL($udn, $3);
			$resultHash{$1}->{Ressource} = decode_entities($3);
		}
	}
	
	if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
		my $type = $1 if ($workType =~ m/get(.*?)WithCovers/);
		SONOS_Client_Data_Refresh('Readings'.(($singleUpdate) ? 'Single' : 'Bulk').'UpdateIfChanged', $udn, $type, SONOS_Dumper(\%resultHash));
		
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet') if ($withLastActionResult);
	} else {
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash)) if ($withLastActionResult);
	}
	
	return \%resultHash;
}

########################################################################################
#
#  SONOS_GetQueueStructuredResult - Browse Queue and give the result back
#
########################################################################################
sub SONOS_GetQueueStructuredResult($$$) {
	my ($udn, $withLastActionResult, $workType) = @_;
	
	my %resultHash = ();
	if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
		my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '');
		my $tmp = $result->getValue('Result');
		
		my $numberReturned = $result->getValue('NumberReturned');
		my $totalMatches = $result->getValue('TotalMatches');
		while ($numberReturned < $totalMatches) {
			$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', $numberReturned, 0, '');
			$tmp .= $result->getValue('Result');
		
			$numberReturned += $result->getValue('NumberReturned');
			$totalMatches = $result->getValue('TotalMatches');
		}
		
		$resultHash{DurationSec} = 0;
		$resultHash{Duration} = '0:00:00';
		my $position = 0;
		while ($tmp =~ m/<item id="(Q:0\/)(\d+)".*?>.*?<res.*?(duration="(.+?)"|).*?>(.*?)<\/res>.*?<dc:title>(.*?)<\/dc:title>.*?<dc:creator>(.*?)<\/dc:creator>.*?<upnp:album>(.*?)<\/upnp:album>.*?<\/item>/ig) {
			my $key = $1.sprintf("%04d", $2);
			$resultHash{$key}->{Position} = ++$position;
			$resultHash{$key}->{Title} = $6;
			$resultHash{$key}->{Artist} = $7;
			$resultHash{$key}->{Album} = $8;
			if (defined($4)) {
				$resultHash{$key}->{ShowTitle} = $position.'. ('.$7.') '.$6.' ['.$4.']';
				$resultHash{$key}->{Duration} = $4;
				$resultHash{$key}->{DurationSec} = SONOS_GetTimeSeconds($4);
				$resultHash{DurationSec} += SONOS_GetTimeSeconds($4);
			} else {
				$resultHash{$key}->{ShowTitle} = $position.'. ('.$7.') '.$6.' [k.A.]';
				$resultHash{$key}->{Duration} = '0:00:00';
				$resultHash{$key}->{DurationSec} = 0;
			}
			$resultHash{$key}->{Cover} = SONOS_MakeCoverURL($udn, $5);
			$resultHash{$key}->{Ressource} = decode_entities($5);
		}
		$resultHash{Duration} = SONOS_ConvertSecondsToTime($resultHash{DurationSec});
	}
	
	if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
		SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueDuration', $resultHash{Duration});
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'QueueDurationSec', $resultHash{DurationSec});
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'Queue', SONOS_Dumper(\%resultHash));
		SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
		
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': DirectlySet') if ($withLastActionResult);
	} else {
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_Dumper(\%resultHash)) if ($withLastActionResult);
	}
	
	return \%resultHash;
}

########################################################################################
#
#  SONOS_StartMetadata - Starts any kind of Metadata
#
########################################################################################
sub SONOS_StartMetadata($$$$) {
	my ($workType, $udn, $res, $meta, $nostart) = @_;

	if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
		# Entscheiden, ob eine Abspielliste geladen und gestartet werden soll, oder etwas direkt abgespielt werden kann
		if ($meta =~ m/<upnp:class>object\.container.*?<\/upnp:class>/i) {
			SONOS_Log $udn, 5, 'StartFavourite AddToQueue-Res: "'.$res.'", -Meta: "'.$meta.'"';
			
			# Queue leeren
			$SONOS_AVTransportControlProxy{$udn}->RemoveAllTracksFromQueue(0);
			
			# Queue wieder füllen
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->AddURIToQueue(0, $res, $meta, 0, 1)));
			
			# Queue aktivieren
			$SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, SONOS_GetTagData('res', $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '')->getValue('Result')), '');
		} else {
			SONOS_Log $udn, 5, 'StartFavourite SetAVTransport-Res: "'.$res.'", -Meta: "'.$meta.'"';
			
			# Stück aktivieren
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, $res, $meta)));
		}
		
		# Abspielen starten, wenn nicht absichtlich verhindert
		$SONOS_AVTransportControlProxy{$udn}->Play(0, 1) if (!$nostart);
	}
}

########################################################################################
#
#  SONOS_RecursiveStructure - Retrieves the structure of the Sonos-Bibliothek
#
########################################################################################
sub SONOS_RecursiveStructure($$$$) {
	my ($udn, $search, $exportsStruct, $exportsTitles) = @_;
	
	my $startIndex = 0;
	my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($search, 'BrowseDirectChildren', '', $startIndex, 0, '');
	return if (!defined($result->getValue('NumberReturned')));
	$startIndex += $result->getValue('NumberReturned');
	my $tmp = decode('UTF-8', $result->getValue('Result'));
	
	# Alle Suchergebnisse vom Player abfragen...
	while ($startIndex < $result->getValue('TotalMatches')) {
		$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($search, 'BrowseDirectChildren', '', $startIndex, 0, '');
		$tmp .= decode('UTF-8', $result->getValue('Result'));
		
		$startIndex += $result->getValue('NumberReturned');
	}
	
	# Struktur verarbeiten...
	while ($tmp =~ m/<container id="(.*?)".*?>(.*?)<\/container>/ig) {
		my $id = $1;
		my $item = $2;
		
		next if (SONOS_Trim($id) eq ''); # Wenn keine ID angegeben ist, dann überspringen
		
		$exportsStruct->{$id}->{ID} = $id;
		$exportsStruct->{$id}->{Title} = $1 if ($item =~ m/<dc:title>(.*?)<\/dc:title>/i);
		$exportsStruct->{$id}->{Artist} = $1 if ($item =~ m/<dc:creator>(.*?)<\/dc:creator>/i);
		$exportsStruct->{$id}->{Cover} = SONOS_MakeCoverURL($udn, $1) if ($item =~ m/<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>/i);
		$exportsStruct->{$id}->{Type} = 'Container';
		$exportsStruct->{$id}->{Children} = {};
		
		# Wenn hier eine Titel-ID gesucht werden soll, die es bereits lokal gibt, dann nicht mehr anfragen...
		if (!$exportsTitles->{$id}) {
			SONOS_RecursiveStructure($udn, $id, $exportsStruct->{$id}->{Children}, $exportsTitles);
		}
	} 
	
	# Titel verarbeiten...
	while ($tmp =~ m/<item id="(.*?)".*?>(.*?)<\/item>/ig) {
		my $id = $1;
		my $item = $2;
		
		next if (SONOS_Trim($id) eq ''); # Wenn keine ID angegeben ist, dann überspringen
		
		# Titel merken...
		$exportsTitles->{$id}->{ID} = $id;
		$exportsTitles->{$id}->{TrackURI} = SONOS_GetURIFromQueueValue($1) if ($item =~ m/<res.*?>(.*?)<\/res>/i);
		$exportsTitles->{$id}->{Title} = $1 if ($item =~ m/<dc:title>(.*?)<\/dc:title>/i);
		$exportsTitles->{$id}->{Artist} = $1 if ($item =~ m/<dc:creator>(.*?)<\/dc:creator>/i);
		$exportsTitles->{$id}->{AlbumArtist} = $1 if ($item =~ m/<r:albumArtist>(.*?)<\/r:albumArtist>/i);
		$exportsTitles->{$id}->{Album} = $1 if ($item =~ m/<upnp:album>(.*?)<\/upnp:album>/i);
		$exportsTitles->{$id}->{Cover} = SONOS_MakeCoverURL($udn, $1) if ($item =~ m/<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>/i);
		$exportsTitles->{$id}->{OriginalTrackNumber} = $1 if ($item =~ m/<upnp:originalTrackNumber>(.*?)<\/upnp:originalTrackNumber>/i);
		
		# Verweis in der Struktur merken...
		$exportsStruct->{$id}->{ID} = $id;
		$exportsStruct->{$id}->{Type} = 'Track';
	}
}

########################################################################################
#
#  SONOS_AddMultipleURIsToQueue - Adds the given URIs to the current queue of the player
#
########################################################################################
sub SONOS_AddMultipleURIsToQueue($$$$) {
	my ($udn, $URIs, $Metas, $currentInsertPos) = @_;
	my @URIs = @{$URIs};
	my @Metas = @{$Metas};
	
	my $sliceSize = 16;
	my $result;
	my $count = 0;
	my $answer = '';
	
	SONOS_Log $udn, 5, "Start-Adding: Count ".scalar(@URIs)." / $sliceSize";
	
	for my $i (0..int(scalar(@URIs) / $sliceSize)) { # Da hier Nullbasiert vorgegangen wird, brauchen wir die letzte Runde nicht noch hinzuaddieren
		my $startIndex = $i * $sliceSize;
		my $endIndex = $startIndex + $sliceSize - 1;
		$endIndex = SONOS_Min(scalar(@URIs) - 1, $endIndex);
		
		SONOS_Log $udn, 5, "Add($i) von $startIndex bis $endIndex (".($endIndex - $startIndex + 1)." Elemente)";
		SONOS_Log $udn, 5, "Upload($currentInsertPos)-URI: ".join(' ', @URIs[$startIndex..$endIndex]);
		SONOS_Log $udn, 5, "Upload($currentInsertPos)-Meta: ".join(' ', @Metas[$startIndex..$endIndex]);
		
		$result = $SONOS_AVTransportControlProxy{$udn}->AddMultipleURIsToQueue(0, 0, $endIndex - $startIndex + 1, join(' ', @URIs[$startIndex..$endIndex]), join(' ', @Metas[$startIndex..$endIndex]), '', '', $currentInsertPos, 0);
		if (!$result->isSuccessful()) {
			$answer .= 'Adding-Error: '.SONOS_UPnPAnswerMessage($result).' ';
		}
		
		$currentInsertPos += $endIndex - $startIndex + 1;
		$count = $endIndex + 1;
	}
	
	if ($result->isSuccessful()) {
		$answer .= 'Added '.$count.' entries from file "'.$1.'". There are now '.$result->getValue('NewQueueLength').' entries in Queue. ';
	} else {
		$answer .= 'Adding: '.SONOS_UPnPAnswerMessage($result).' ';
	}
	
	return $answer;
}

########################################################################################
#
#  SONOS_Hex2String - Converts Hex-Representation into String
#
########################################################################################
sub SONOS_Hex2String($) {
	my $s = shift;
	
	return pack 'H*', $s;
}

########################################################################################
#
#  SONOS_String2Hex - Converts a normal String into the Hex-Representation
#
########################################################################################
sub SONOS_String2Hex($) {
	my $s = shift;
	
	return unpack("H*",  $s);
}

########################################################################################
#
#  SONOS_Fisher_Yates_Shuffle - Shuffles the given array
#
########################################################################################
sub SONOS_Fisher_Yates_Shuffle($) {
	my ($deck) = @_;  # $deck is a reference to an array
	my $i = @$deck;
	
	while ($i--) {
		my $j = int rand ($i+1);
		@$deck[$i,$j] = @$deck[$j,$i];
	}
}

########################################################################################
#
#  SONOS_GetShuffleRepeatStates - Retreives the information according shuffle and repeat
#
########################################################################################
sub SONOS_GetShuffleRepeatStates($) {
	my ($data) = @_;
	
	my $shuffle = $data =~ m/SHUFFLE/;
	my $repeat = $data eq 'SHUFFLE' || $data eq 'REPEAT_ALL';
	my $repeatOne = $data =~ m/REPEAT_ONE/;
	
	return ($shuffle, $repeat, $repeatOne);
}

########################################################################################
#
#  SONOS_GetShuffleRepeatString - Generates the information string according shuffle and repeat
#
########################################################################################
sub SONOS_GetShuffleRepeatString($$$) {
	my ($shuffle, $repeat, $repeatOne) = @_;
	
	my $newMode = 'NORMAL';
	$newMode = 'SHUFFLE' if ($shuffle && $repeat && $repeatOne);
	$newMode = 'SHUFFLE' if ($shuffle && $repeat && !$repeatOne);
	$newMode = 'SHUFFLE_REPEAT_ONE' if ($shuffle && !$repeat && $repeatOne);
	$newMode = 'SHUFFLE_NOREPEAT' if ($shuffle && !$repeat && !$repeatOne);
	
	$newMode = 'REPEAT_ALL' if (!$shuffle && $repeat && $repeatOne);
	$newMode = 'REPEAT_ALL' if (!$shuffle && $repeat && !$repeatOne);
	$newMode = 'REPEAT_ONE' if (!$shuffle && !$repeat && $repeatOne);
	$newMode = 'NORMAL' if (!$shuffle && !$repeat && !$repeatOne);
	
	return $newMode;
}

########################################################################################
#
#  SONOS_DeleteDoublettes - Deletes duplicate entries in the given array
#
########################################################################################
sub SONOS_DeleteDoublettes{ 
	return keys %{{ map { $_ => 1 } @_ }}; 
}

########################################################################################
#
#  SONOS_Trim - Trim the given string
#
########################################################################################
sub SONOS_Trim($) {
	my ($str) = @_;
	
	return $1 if ($str =~ m/^ *(.*?) *$/);
	return $str;
}

########################################################################################
#
#  SONOS_CountInString - Count the occurences of the first string in the second string
#
########################################################################################
sub SONOS_CountInString($$) {
	my ($search, $str) = @_;
	
	my $pos = 0;
	my $matches = 0;
	
	while (1) {
		$pos = index($str, $search, $pos);
		last if($pos < 0);
		$matches++;
		$pos++;
	}
	
	return $matches;
}

########################################################################################
#
#  SONOS_MakeCoverURL - Generates the approbriate cover-url incl. the use of a Fhem-Proxy
#
########################################################################################
sub SONOS_MakeCoverURL($$) {
	my ($udn, $resURL) = @_;
	
	SONOS_Log $udn, 5, 'MakeCoverURL-Before: '.$resURL;
	
	if ($resURL =~ m/^x-rincon-cpcontainer.*?(spotify.*?)(\?|$)/i) {
		$resURL = SONOS_getSpotifyCoverURL($1, 1);
	} elsif ($resURL =~ m/^x-sonos-spotify:spotify%3atrack%3a(.*?)(\?|$)/i) {
		$resURL = SONOS_getSpotifyCoverURL($1);
	} elsif ($resURL =~ m/^x-sonosapi-stream:(.+?)\?/i) {
		my $resURLtemp = SONOS_GetRadioMediaMetadata($udn, $1);
		eval {
			my $result = SONOS_ReadURL($resURLtemp);
			if (!defined($result) || ($result =~ m/<Error>.*<\/Error>/i)) {
				$resURLtemp = $1.'/getaa?s=1&u='.SONOS_URI_Escape($resURL) if (SONOS_Client_Data_Retreive($udn, 'reading', 'location', '') =~ m/^(http:\/\/.*?:.*?)\//i);
			}
		};
		$resURL = $resURLtemp;
	} elsif (($resURL =~ m/x-rincon-playlist:.*?#(.*)/i) || ($resURL =~ m/savedqueues.rsq(#\d+)/i)) {
		my $search = $1;
		$search = 'SQ:'.$1 if ($search =~ m/#(\d+)/i);
		
		# Default, if nothing could be retreived...
		$resURL = '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/playlist.jpg';
		
		if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
			my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($search, 'BrowseDirectChildren', '', 0, 15, '');
			if ($result) {
				my $tmp = $result->getValue('Result');
				while (defined($tmp) && $tmp =~ m/<container id="(.+?)".*?>.*?<\/container>/i) {
					$search = $1;
					$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse($search, 'BrowseDirectChildren', '', 0, 15, '');
					
					if ($result) {
						$tmp = $result->getValue('Result');
					} else {
						undef($tmp);
					}
				}
			}
			
			if ($result) {
				my $tmp = $result->getValue('Result');
				my $coverOK = 0;
				
				while (!$coverOK && defined($tmp) && $tmp =~ m/<item id=".+?".*?>.*?<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>.*?<\/item>/ig) {
					$resURL = $1;
					$resURL =~ s/%25/%/ig;
					
					# Bei Spotify-URIs, die AlbumURL korrigieren...
					if ($resURL =~ m/getaa.*?x-sonos-spotify%3aspotify%3atrack%3a(.*?)%3f/i) {
						$resURL = SONOS_getSpotifyCoverURL($1);
					} else {
						$resURL = $1.$resURL if (SONOS_Client_Data_Retreive($udn, 'reading', 'location', '') =~ m/^(http:\/\/.*?:.*?)\//i);
					}
					
					my $loadedCover = SONOS_ReadURL($resURL);
					$coverOK = (defined($loadedCover) && ($loadedCover !~ m/<Error>.*<\/Error>/i))
				}
			}
		}
	} else {
		my $stream = 0;
		$stream = 1 if (($resURL =~ /x-sonosapi-stream/) && ($resURL !~ /x-sonos-http%3aamz/));
		$stream = 1 if (!$stream && (($resURL =~ /x-sonosapi-hls-static/) || ($resURL =~ /x-sonos-http:track%3a/)));
		
		$resURL = SONOS_URI_Escape($resURL);
		SONOS_Log undef, 5, 'resURL-1: '.$resURL;
		$resURL =~ s/%26apos%3B/&apos;/ig;
		$resURL =~ s/%26amp%3B/%26/ig;
		SONOS_Log undef, 5, 'resURL-2: '.$resURL;
		$resURL = $1.'/getaa?'.($stream ? 's=1&' : '').'u='.$resURL if (SONOS_Client_Data_Retreive($udn, 'reading', 'location', '') =~ m/^(http:\/\/.*?:.*?)\//i);
		SONOS_Log undef, 5, 'resURL-3: '.$resURL;
	}
	
	# Alles über Fhem als Proxy laufen lassen?
	$resURL = '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/proxy/aa?url='.SONOS_URI_Escape($resURL) if (($resURL !~ m/^\//) && SONOS_Client_Data_Retreive('undef', 'attr', 'generateProxyAlbumArtURLs', 0));
	
	SONOS_Log $udn, 5, 'MakeCoverURL-After: '.$resURL;
	
	return $resURL;
}

########################################################################################
#
#  SONOS_getSpotifyCoverURL - Generates the approbriate cover-url for Spotify-Cover
#
########################################################################################
sub SONOS_getSpotifyCoverURL($;$) {
	my ($trackID, $oldStyle) = @_;
	$oldStyle = 0 if (!defined($oldStyle));
	
	my $infos = '';
	if ($oldStyle) {
		my $result = get('https://embed.spotify.com/oembed/?url='.$trackID);
		$infos = $1 if ($result && ($result =~ m/"thumbnail_url":"(.*?)"/i));
	} else {
		my $result = get('https://api.spotify.com/v1/tracks/'.$trackID);
		$infos = $1 if ($result && ($result =~ m/"images".*?:.*?\[.*?{.*?"height".*?:.*?\d{3},.*?"url".*?:.*?"(.*?)",.*?"width"/is));
	}
	
	$infos =~ s/\\//g;
	#$infos = $1.'original'.$3 if ($infos =~ m/(.*?\/)(cover|default)(\/.*)/i);
	
	# Falls es ein Standardcover von Spotify geben soll, lieber das Thumbnail von Sonos verwenden...
	return '' if ($infos =~ m/\/static\/img\/defaultCoverL.png/i);
	
	if ($infos ne '') {
		return $infos;
	}
	
	return '';
}

########################################################################################
#
#  SONOS_GetSpeakFileExtension - Retrieves the desired fileextension
#
########################################################################################
sub SONOS_GetSpeakFileExtension($) {
	my ($workType) = @_;
	
	if (lc($workType) eq 'speak0') {
		return 'mp3';
	} elsif ($workType =~ m/speak\d+/i) {
		$workType = ucfirst(lc($workType));
		
		my $speakDefinition = SONOS_Client_Data_Retreive('undef', 'attr', $workType, 0);
		if ($speakDefinition =~ m/(.*?):(.*)/) {
			return $1;
		}
	}
	
	return '';
}

########################################################################################
#
#  SONOS_GetSpeakFile - Generates the audiofile according to the given text, language and generator
#
########################################################################################
sub SONOS_GetSpeakFile($$$$$) {
	my ($udn, $workType, $language, $text, $destFileName) = @_;
	
	my $targetSpeakMP3FileDir = SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakMP3FileDir', '');
	
	# Parametrisieren...
	my $chunksize = $SONOS_GOOGLETRANSLATOR_CHUNKSIZE;
	my $textescaped = SONOS_URI_Escape($text);
	
	my $textutf8 = SONOS_Latin1ToUtf8($text);
	my $textutf8escaped = SONOS_URI_Escape($textutf8);
	
	# Chunks ermitteln...
	# my @textList = ($text =~ m/(?:\b(?:[^ ]+)\W*){0,$SONOS_GOOGLETRANSLATOR_CHUNKSIZE}/g);
	# pop @textList; # Letztes Element ist immer leer, deshalb abschneiden...
	my @textList = ('');
	for my $elem (split(/[ \t]/, $text)) {
		# Files beibehalten...
		if ($elem =~ m/\|(.*)\|/) {
			my $filename = $1;
			$filename = $targetSpeakMP3FileDir.'/'.$filename if ($filename !~ m/^(\/|[a-z]:)/i);
			$filename = $filename.'.mp3' if ($filename !~ m/\.mp3$/i);
			push(@textList, '|'.$filename.'|');
			push(@textList, '');
			next;
		}
		
		if (length($textList[$#textList].' '.$elem) <= $chunksize) {
			$textList[$#textList] .= ' '.$elem;
		} else {
			push(@textList, $elem);
		}
	}
	SONOS_Log $udn, 5, 'Chunks: '.SONOS_Stringify(\@textList);
	
	# Generating Speakfiles...
	if (lc($workType) eq 'speak0') {
		# Einzelne Chunks herunterladen...
		my $counter = 0;
		for my $text (@textList) {
			# Leere Einträge überspringen...
			next if ($text eq '');
			
			$counter++;
			
			# MP3Files direkt kopieren
			if ($text =~ m/\|(.*)\|/) {
				SONOS_Log $udn, 3, 'Copy MP3-File ('.$counter.'. Element) from "'.$1.'" to "'.$destFileName.$counter.'"';
				
				copy($1, $destFileName.$counter);
				
				# Etwaige ID-Tags entfernen...
				eval {
					use MP3::Info;
					remove_mp3tag($destFileName.$counter, 'ALL');
				};
				if ($@) {
					SONOS_Log $udn, 3, 'Copy MP3-File. ERROR during removing of ID3Tag: '.$@;
				}
				
				next;
			}
			
			my $url = sprintf(SONOS_Client_Data_Retreive('undef', 'attr', 'SpeakGoogleURL', $SONOS_GOOGLETRANSLATOR_URL), SONOS_URI_Escape(lc($language)), SONOS_URI_Escape($text));
		
			SONOS_Log $udn, 3, 'Load Google generated MP3 ('.$counter.'. Element) from "'.$url.'" to "'.$destFileName.$counter.'"';
			
			my $ua = LWP::UserAgent->new(agent => $SONOS_USERAGENT);
			my $response = $ua->get($url, ':content_file' => $destFileName.$counter);
			if (!$response->is_success) {
				SONOS_Log $udn, 1, 'MP3 Download-Error: '.$response->status_line;
				unlink($destFileName.$counter);
				
				SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': MP3-Creation ERROR during downloading: '.$response->status_line);
				return 0;
			}
		}
		
		# Heruntergeladene Chunks zusammenführen...
		return SONOS_CombineMP3Files($udn, $workType, $destFileName, $counter);
	} elsif ($workType =~ m/speak\d+/i) {
		$workType = ucfirst(lc($workType));
		SONOS_Log $udn, 3, 'Load '.$workType.' generated SpeakFile to "'.$destFileName.'"';
		
		my $speakDefinition = SONOS_Client_Data_Retreive('undef', 'attr', $workType, 0);
		if ($speakDefinition =~ m/(.*?):(.*)/) {
			$speakDefinition = $2;
			
			$speakDefinition =~ s/%language%/$language/gi;
			$speakDefinition =~ s/%filename%/$destFileName/gi;
			$speakDefinition =~ s/%text%/$text/gi;
			$speakDefinition =~ s/%textescaped%/$textescaped/gi;
			$speakDefinition =~ s/%textutf8%/$textutf8/gi;
			$speakDefinition =~ s/%textutf8escaped%/$textutf8escaped/gi;
			
			SONOS_Log $udn, 5, 'Execute: '.$speakDefinition;
			system($speakDefinition);
			
			return 1;
		} else {
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': No Definition found!');
			return 0;
		}
	}
	
	SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': Speaking not defined.');
	return 0;
}

########################################################################################
#
#  SONOS_CombineMP3Files - Combine the loaded mp3-files
#
########################################################################################
sub SONOS_CombineMP3Files($$$$) {
	my ($udn, $workType, $destFileName, $counter) = @_;
	
	SONOS_Log $udn, 3, 'Combine loaded chunks into "'.$destFileName.'"';
	
	# Reinladen
	my $newMP3File = '';
	for(my $i = 1; $i <= $counter; $i++) {
		$newMP3File .= SONOS_ReadFile($destFileName.$i);
		unlink($destFileName.$i);
	}
	
	# Speichern
	eval {
		open MPFILE, '>'.$destFileName;
		binmode MPFILE ;
		print MPFILE $newMP3File;
		close MPFILE;
	};
	if ($@) {
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': MP3-Creation ERROR during combining: '.$@);
		return 0;
	}
	
	# Konvertieren?
	my $targetSpeakMP3FileConverter = SONOS_Client_Data_Retreive('undef', 'attr', 'targetSpeakMP3FileConverter', '');
	if ($targetSpeakMP3FileConverter) {
		SONOS_Log $udn, 3, 'Convert combined file "'.$destFileName.'" with "'.$targetSpeakMP3FileConverter.'"';
		eval {
			my $destFileNameTMP = $destFileName;
			$destFileNameTMP =~ s/^(.*)\/(.*?)$/$1\/TMP_$2/;
			
			$targetSpeakMP3FileConverter =~ s/%infile%/$destFileName/gi;
			$targetSpeakMP3FileConverter =~ s/%outfile%/$destFileNameTMP/gi;
			
			SONOS_Log $udn, 5, 'Execute: '.$targetSpeakMP3FileConverter;
			system($targetSpeakMP3FileConverter);
			
			# "Alte" MP3-Datei entfernen, und die "neue" umbenennen...
			unlink($destFileName);
			move($destFileNameTMP, $destFileName);
		};
		if ($@) {
			SONOS_Log $udn, 2, ucfirst($workType).': MP3-Creation ERROR during converting: '.$@;
			SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', ucfirst($workType).': MP3-Creation ERROR during converting: '.$@);
			return 0;
		}
	}
	
	return 1;
}

########################################################################################
#
#  SONOS_CreateURIMeta - Creates the Meta-Information according to the Song-URI
#
#  Parameter $res = The URI to the song, for which the Metadata has to be generated
#
########################################################################################
sub SONOS_CreateURIMeta($) {
	my ($res) = @_;
	my $meta = $SONOS_DIDLHeader.'<item id="" parentID="" restricted="true"><dc:title></dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">RINCON_AssociatedZPUDN</desc></item>'.$SONOS_DIDLFooter;
	
	my $userID_Spotify = uri_unescape(SONOS_Client_Data_Retreive('undef', 'reading', 'UserID_Spotify', '-'));
	my $userID_Napster = uri_unescape(SONOS_Client_Data_Retreive('undef', 'reading', 'UserID_Napster', '-'));
	
	# Wenn es ein Spotify- oder Napster-Titel ist, dann den Benutzernamen extrahieren
	if ($res =~ m/^(x-sonos-spotify:)(.*?)(\?.*)/) {
		if ($userID_Spotify eq '-') {
			SONOS_Log undef, 1, 'There are Spotify-Titles in list, and no Spotify-Username is known. Please empty the main queue and insert a random spotify-title in it for saving this information and do this action again!';
			return;
		}
		
		$res = $1.SONOS_URI_Escape($2).$3;
		$meta = $SONOS_DIDLHeader.'<item id="00030020'.SONOS_URI_Escape($2).'" parentID="" restricted="true"><dc:title></dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">'.$userID_Spotify.'</desc></item>'.$SONOS_DIDLFooter;
	} elsif ($res =~ m/^(npsdy:)(.*?)(\.mp3)/) {
		if ($userID_Napster eq '-') {
			SONOS_Log undef, 1, 'There are Napster/Rhapsody-Titles in list, and no Napster-Username is known. Please empty the main queue and insert a random napster-title in it for saving this information and do this action again!';
			return;
		} 
	
		$res = $1.SONOS_URI_Escape($2).$3;
		$meta = $SONOS_DIDLHeader.'<item id="RDCPI:GLBTRACK:'.SONOS_URI_Escape($2).'" parentID="" restricted="true"><dc:title></dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">'.$userID_Napster.'</desc></item>'.$SONOS_DIDLFooter;
	} else {
		$res =~ s/ /%20/ig;
		$res =~ s/"/&quot;/ig;
	}
	
	return ($res, $meta);
}

########################################################################################
#
#  SONOS_CheckAlarmHash - Checks if the given hash has all neccessary Alarm-Parameters
#					Additionally it converts some parameters for direct use for Zoneplayer-Update
#
#  Parameter %old = All neccessary informations to check
#
########################################################################################
sub SONOS_CheckAndCorrectAlarmHash($) {
	my ($hash) = @_;
	
	# Checks, if a value is missing
	my @keys = keys(%$hash);
	if ((!SONOS_isInList('StartTime', @keys))
		|| (!SONOS_isInList('Duration', @keys))
		|| (!SONOS_isInList('Recurrence_Once', @keys))
		|| (!SONOS_isInList('Recurrence_Monday', @keys))
		|| (!SONOS_isInList('Recurrence_Tuesday', @keys))
		|| (!SONOS_isInList('Recurrence_Wednesday', @keys))
		|| (!SONOS_isInList('Recurrence_Thursday', @keys))
		|| (!SONOS_isInList('Recurrence_Friday', @keys))
		|| (!SONOS_isInList('Recurrence_Saturday', @keys))
		|| (!SONOS_isInList('Recurrence_Sunday', @keys))
		|| (!SONOS_isInList('Enabled', @keys))
		|| (!SONOS_isInList('RoomUUID', @keys))
		|| (!SONOS_isInList('ProgramURI', @keys))
		|| (!SONOS_isInList('ProgramMetaData', @keys))
		|| (!SONOS_isInList('Shuffle', @keys))
		|| (!SONOS_isInList('Repeat', @keys))
		|| (!SONOS_isInList('Volume', @keys))
		|| (!SONOS_isInList('IncludeLinkedZones', @keys))) {
		return 0;
	}
	
	# Convert some values
	# Playmode
	$hash->{PlayMode} = 'NORMAL';
	$hash->{PlayMode} = 'SHUFFLE' if ($hash->{Repeat} && $hash->{Shuffle});
	$hash->{PlayMode} = 'SHUFFLE_NOREPEAT' if (!$hash->{Repeat} && $hash->{Shuffle});
	$hash->{PlayMode} = 'REPEAT_ALL' if ($hash->{Repeat} && !$hash->{Shuffle});
	
	# Recurrence
	if ($hash->{Recurrence_Once}) {
		$hash->{Recurrence} = 'ONCE';
	} else {
		$hash->{Recurrence} = 'ON_';
		$hash->{Recurrence} .= '0' if ($hash->{Recurrence_Sunday});
		$hash->{Recurrence} .= '1' if ($hash->{Recurrence_Monday});
		$hash->{Recurrence} .= '2' if ($hash->{Recurrence_Tuesday});
		$hash->{Recurrence} .= '3' if ($hash->{Recurrence_Wednesday});
		$hash->{Recurrence} .= '4' if ($hash->{Recurrence_Thursday});
		$hash->{Recurrence} .= '5' if ($hash->{Recurrence_Friday});
		$hash->{Recurrence} .= '6' if ($hash->{Recurrence_Saturday});
		
		# Specials
		$hash->{Recurrence} = 'DAILY' if (($hash->{Recurrence_Monday}) && ($hash->{Recurrence_Tuesday}) && ($hash->{Recurrence_Wednesday}) && ($hash->{Recurrence_Thursday}) && ($hash->{Recurrence_Friday}) && ($hash->{Recurrence_Saturday}) && ($hash->{Recurrence_Sunday}));
		
		$hash->{Recurrence} = 'WEEKDAYS' if (($hash->{Recurrence_Monday}) && ($hash->{Recurrence_Tuesday}) && ($hash->{Recurrence_Wednesday}) && ($hash->{Recurrence_Thursday}) && ($hash->{Recurrence_Friday}) && (!$hash->{Recurrence_Saturday}) && (!$hash->{Recurrence_Sunday}));
		
		$hash->{Recurrence} = 'WEEKENDS' if ((!$hash->{Recurrence_Monday}) && (!$hash->{Recurrence_Tuesday}) && (!$hash->{Recurrence_Wednesday}) && (!$hash->{Recurrence_Thursday}) && (!$hash->{Recurrence_Friday}) && ($hash->{Recurrence_Saturday}) && ($hash->{Recurrence_Sunday}));
	}
	
	# If nothing is given, set 'ONCE'
	if ($hash->{Recurrence} eq 'ON_') {
		$hash->{Recurrence} = 'ONCE';
	}
	
	return 1;
}

########################################################################################
#
#  SONOS_RestoreOldPlaystate - Restores the old Position of a playing state
#
########################################################################################
sub SONOS_RestoreOldPlaystate() {
	SONOS_Log undef, 1, 'Restore-Thread gestartet. Warte auf Arbeit...';
	
	my $runEndlessLoop = 1;
	my $controlPoint = UPnP::ControlPoint->new(SearchPort => 0, SubscriptionPort => 0, SubscriptionURL => '/fhemmodule', MaxWait => 20, UsedOnlyIP => \%usedonlyIPs, IgnoreIP => \%ignoredIPs, ReusePort => $reusePort);
	
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'CHLD'} = 'IGNORE';
	
	$SIG{'INT'} = sub {
		$runEndlessLoop = 0;
	};
	
	while ($runEndlessLoop) {
		select(undef, undef, undef, 0.2);
		next if (!$SONOS_PlayerRestoreQueue->pending());
		
		# Es ist was auf der Queue... versuchen zu verarbeiten...
		my %old = %{$SONOS_PlayerRestoreQueue->peek()};
		next if (!defined($old{RestoreTime}));
		
		# Wenn die Zeit noch nicht reif ist, dann doch wieder übergehen...
		# Dabei die Schleife wieder von vorne beginnen lassen, da noch andere dazwischengeschoben werden könnten.
		# Eine Weile in die Zukunft, da das ermitteln der Proxies Zeit benötigt.
		next if ($old{RestoreTime} > time() + 2);
		
		# ...sonst das Ding von der Queue nehmen...
		$SONOS_PlayerRestoreQueue->dequeue();
		
		# Hier die ursprünglichen Proxies wiederherstellen/neu verbinden...
		my $device = $controlPoint->_createDevice($old{location});
		my $AVProxy;
		my $GRProxy;
		my $CCProxy;
		for my $subdevice ($device->children) {
			if ($subdevice->UDN =~ /.*_MR/i) {
				$AVProxy = $subdevice->getService('urn:schemas-upnp-org:service:AVTransport:1')->controlProxy();
				$GRProxy = $subdevice->getService('urn:schemas-upnp-org:service:GroupRenderingControl:1')->controlProxy();
			}
			
			if ($subdevice->UDN =~ /.*_MS/i) { 
				$CCProxy = $subdevice->getService('urn:schemas-upnp-org:service:ContentDirectory:1')->controlProxy();
			}
		}
		my $udn = $device->UDN.'_MR';
		$udn =~ s/.*?:(.*)/$1/;
	
		SONOS_Log $udn.'_MR', 3, 'Restorethread has found a job. Waiting for stop playing...';
		
		# Ist das Ding fertig abgespielt?
		my $result;
		do {
			select(undef, undef, undef, 0.7);
			$result = $AVProxy->GetTransportInfo(0);
		} while ($result->getValue('CurrentTransportState') ne 'STOPPED');
		
		
		SONOS_Log $udn, 3, 'Restoring playerstate...';
		SONOS_Log $udn, 5, 'StoredURI: "'.$old{CurrentURI}.'"';
		# Die Liste als aktuelles Abspielstück einstellen, oder den Stream wieder anwerfen
		if ($old{CurrentURI} =~ /^x-.*?-(.*?stream|mp3radio)/) {
			SONOS_Log $udn, 4, 'Restore Stream...';
			
			$AVProxy->SetAVTransportURI(0, $old{CurrentURI}, $old{CurrentURIMetaData});
		} else {
			SONOS_Log $udn, 4, 'Restore Track #'.$old{Track}.', RelTime: "'.$old{RelTime}.'"...';
			
			my $queueMetadata = $CCProxy->Browse('Q:0', 'BrowseMetadata', '', 0, 0, '');
			$AVProxy->SetAVTransportURI(0, SONOS_GetTagData('res', $queueMetadata->getValue('Result')), '');
			
			$AVProxy->Seek(0, 'TRACK_NR', $old{Track});
			$AVProxy->Seek(0, 'REL_TIME', $old{RelTime});
		}
		
		my $oldMute = $GRProxy->GetGroupMute(0)->getValue('CurrentMute');
		$GRProxy->SetGroupMute(0, $old{Mute}) if (defined($old{Mute}) && ($old{Mute} != $oldMute));
		
		my $oldVolume = $GRProxy->GetGroupVolume(0)->getValue('CurrentVolume');
		$GRProxy->SetGroupVolume(0, $old{Volume}) if (defined($old{Volume}) && ($old{Volume} != $oldVolume));
		
		if (($old{CurrentTransportState} eq 'PLAYING') || ($old{CurrentTransportState} eq 'TRANSITIONING')) {
			$AVProxy->Play(0, 1);
		} elsif ($old{CurrentTransportState} eq 'PAUSED_PLAYBACK') {
			$AVProxy->Pause(0); 
		}
		
		$SONOS_PlayerRestoreRunningUDN{$udn} = 0;
		SONOS_Log $udn, 3, 'Playerstate restored!';
	}
	
	undef($controlPoint);
	
	SONOS_Log undef, 1, 'Restore-Thread wurde beendet.';
	$SONOS_Thread_PlayerRestore = -1;
}

########################################################################################
#
#  SONOS_PlayURITemp - Plays an URI temporary
#
#  Parameter $udn = The udn of the SonosPlayer
#			$destURLParam = URI, that has to be played
#			$volumeParam = Volume for playing
#
########################################################################################
sub SONOS_PlayURITemp($$$) {
	my ($udn, $destURLParam, $volumeParam) = @_;
	
	my %old;
	$old{DestURIOriginal} = $destURLParam;
	my ($songURI, $meta) = SONOS_CreateURIMeta(SONOS_ExpandURIForQueueing($old{DestURIOriginal}));
	
	# Wenn auf diesem Player bereits eine temporäre Wiedergabe erfolgt, dann hier auf dessen Beendigung warten...
	if (defined($SONOS_PlayerRestoreRunningUDN{$udn}) && $SONOS_PlayerRestoreRunningUDN{$udn}) {
		SONOS_Log $udn, 3, 'Temporary playing of "'.$old{DestURIOriginal}.'" must wait, because another playing is in work...';
		
		while (defined($SONOS_PlayerRestoreRunningUDN{$udn}) && $SONOS_PlayerRestoreRunningUDN{$udn}) {
			select(undef, undef, undef, 0.2);
		}
	}
	
	$SONOS_PlayerRestoreRunningUDN{$udn} = 1;
	
	SONOS_Log $udn, 3, 'Start temporary playing of "'.$old{DestURIOriginal}.'"';
	
	my $volume = $volumeParam;
	
	if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
		$old{UDN} = $udn;
		
		my $result = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0);
		$old{Track} = $result->getValue('Track');
		$old{RelTime} = $result->getValue('RelTime');
		
		$result = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0);
		$old{CurrentURI} = $result->getValue('CurrentURI');
		$old{CurrentURIMetaData} = $result->getValue('CurrentURIMetaData');
		
		$result = $SONOS_AVTransportControlProxy{$udn}->GetTransportInfo(0);
		$old{CurrentTransportState} = $result->getValue('CurrentTransportState');
		
		$SONOS_AVTransportControlProxy{$udn}->SetAVTransportURI(0, $songURI, $meta);
		
		if (SONOS_CheckProxyObject($udn, $SONOS_GroupRenderingControlProxy{$udn})) {
			$SONOS_GroupRenderingControlProxy{$udn}->SnapshotGroupVolume(0);
			
			$old{Mute} = $SONOS_GroupRenderingControlProxy{$udn}->GetGroupMute(0)->getValue('CurrentMute');
			$SONOS_GroupRenderingControlProxy{$udn}->SetGroupMute(0, 0) if $old{Mute};
		
			$old{Volume} = $SONOS_GroupRenderingControlProxy{$udn}->GetGroupVolume(0)->getValue('CurrentVolume');
			if (defined($volume)) {
				if ($volume =~ m/^[+-]{1}/) {
					$SONOS_GroupRenderingControlProxy{$udn}->SetRelativeGroupVolume(0, $volume) if $volume;
				} else {
					$SONOS_GroupRenderingControlProxy{$udn}->SetGroupVolume(0, $volume) if ($volume != $old{Volume});
				}
			}
		}
	
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', 'PlayURITemp: '.SONOS_UPnPAnswerMessage($SONOS_AVTransportControlProxy{$udn}->Play(0, 1)));
		
		SONOS_Log $udn, 4, 'All is started successfully. Retreive Positioninfo...';
		$old{SleepTime} = 0;
		eval {
			$old{SleepTime} = SONOS_GetTimeSeconds($SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('TrackDuration'));
			
			# Wenn es keine Laufzeitangabe gibt, dann muss diese selber berechnet werden, sofern möglich. Sollte dies nicht möglich sein, ist dies vermutlich ein Stream...
			if ($old{SleepTime} == 0) {
				SONOS_Log $udn, 3, 'SleepTimer berechnet die Laufzeit des Titels selber, da keine Wartezeit uebermittelt wurde!';
				
				eval {
					use MP3::Info;
					my $tag = get_mp3info($old{DestURIOriginal});
					if ($tag) {
						$old{SleepTime} = $tag->{SECS};
					}
				};
				if ($@) {
					SONOS_Log $udn, 2, 'Bei der MP3-Längenermittlung ist ein Fehler aufgetreten: '.$@;
				}
			}
			
			$old{RestoreTime} = time() + $old{SleepTime} - 1;
			SONOS_Log $udn, 3, 'Laufzeitermittlung abgeschlossen: '.$old{SleepTime}.'s, Restore-Zeit: '.GetTimeString($old{RestoreTime});
		};
		
		# Location mitsichern, damit die Proxies neu geholt werden können
		my %revUDNs = reverse %SONOS_Locations;
		$old{location} = $revUDNs{$udn};

		# Restore-Daten an der richtigen Stelle auf die Queue legen, damit der Player-Restore-Thread sich darum kümmern kann
		# Aber nur, wenn auch ein Restore erfolgen kann, weil eine Zeit existiert
		if (defined($old{SleepTime}) && ($old{SleepTime} != 0)) {
			my $i;
			for ($i = $SONOS_PlayerRestoreQueue->pending() - 1; $i >= 0; $i--) {
				my %tmpOld = %{$SONOS_PlayerRestoreQueue->peek($i)};
				last if ($old{RestoreTime} > $tmpOld{RestoreTime});
			}
			
			$SONOS_PlayerRestoreQueue->insert($i + 1, \%old);
		} else {
			SONOS_Log $udn, 1, 'Da keine Endzeit ermittelt werden konnte, wird kein Restoring durchgeführt werden!';
			$SONOS_PlayerRestoreRunningUDN{$udn} = 0;
		}
	}
}

########################################################################################
#
#  SONOS_GetTrackProvider - Retrieves a textual representation of the Provider of the given URI
#
#  Parameter $songURI = The URI that has to be converted
#
########################################################################################
sub SONOS_GetTrackProvider($;$) {
	my ($songURI, $songTitle) = @_;
	return ('', '', '') if (!defined($songURI) || ($songURI eq ''));
	
	# Backslashe umwandeln
	$songURI =~ s/\\/\//g;
	
	# Gruppen- und LineIn-Wiedergaben bereits hier erkennen
	if ($songURI =~ m/x-rincon:(RINCON_[\dA-Z]+)/) {
		return ('Gruppenwiedergabe: '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1), '', '');
	} elsif ($songURI =~ m/x-rincon-stream:(RINCON_[\dA-Z]+)/) {
		my $elem = 'LineIn';
		$elem = $songTitle if (defined($songTitle) && $songTitle);
		return ($elem.'-Wiedergabe: '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1), '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/linein_round.png', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/linein_quadratic.jpg');
	} elsif ($songURI =~ m/x-sonos-dock:(RINCON_[\dA-Z]+)/) {
		return ('Dock-Wiedergabe: '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1), '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/dock_round.png', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/dock_quadratic.jpg');
	} elsif ($songURI =~ m/x-sonos-htastream:(RINCON_[\dA-Z]+):spdif/) {
		return ('SPDIF-Wiedergabe: '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1), '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/playbar_round.png', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/playbar_quadratic.jpg');
	} elsif (($songURI =~ m/^http:(\/\/.*)/) || ($songURI =~ m/^aac:(\/\/.*)/) || ($songURI =~ m/x-rincon-mp3radio:\/\//)) {
		return ('Radio', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/tunein_round.png', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/tunein_quadratic.jpg');
	} elsif ($songURI =~ m/^\/\//) {
		return ('Bibliothek', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/bibliothek_round.png', '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/bibliothek_quadratic.jpg');
	}
	
	my ($a, $b, $c) = eval {
		my %musicServices = %{eval(SONOS_Client_Data_Retreive('undef', 'reading', 'MusicServicesList', '()'))};
		if ($songURI =~ m/sid=(\d+)/i) {
			my $sid = $1;
			
			if (defined($musicServices{$sid})) {
				my $result = $musicServices{$sid}{Name};
				$result = '' if (!defined($result));
				SONOS_Log undef, 4, 'TrackProvider for "'.$songURI.'" ~ SID='.$sid.' ~ Name: '.$result;
				
				my $roundIcon = $musicServices{$sid}{IconRoundURL};
				$roundIcon = '' if (!defined($roundIcon));
				
				my $quadraticIcon = $musicServices{$sid}{IconQuadraticURL};
				$quadraticIcon = '' if (!defined($quadraticIcon));
				
				SONOS_Log undef, 4, 'Trackprovider-Icons for "'.$result.'": Round: '.$roundIcon.' ~ Quadratic: '.$quadraticIcon;
				
				return ($result, $roundIcon, $quadraticIcon);
			}
		}
	};
	if ($@) {
		SONOS_Log undef, 2, 'Unable to identify TrackProvider for "'.$songURI.'". Revert to empty default! Errormessage: '.$@;
		return ('', '', '');
	} else {
		return ($a, $b, $c);
	}
}

########################################################################################
#
#  SONOS_ExpandURIForQueueing - Expands and corrects a given URI
#
#  Parameter $songURI = The URI that has to be converted
#
########################################################################################
sub SONOS_ExpandURIForQueueing($) {
	my ($songURI) = @_;
	
	# Backslashe umwandeln
	$songURI =~ s/\\/\//g;
	
	# SongURI erweitern/korrigieren
	$songURI = 'x-file-cifs:'.$songURI if ($songURI =~ m/^\/\//);
	$songURI = 'x-rincon-mp3radio:'.$1 if ($songURI =~ m/^http:(\/\/.*)/);
	
	return $songURI;
}

########################################################################################
#
#  SONOS_GetURIFromQueueValue - Gets the URI from current Informations
#
#  Parameter $songURI = The URI that has to be converted
#
########################################################################################
sub SONOS_GetURIFromQueueValue($) {
	my ($songURI) = @_;
	
	# SongURI erweitern/korrigieren
	$songURI = $1 if ($songURI =~ m/^x-file-cifs:(.*)/i);
	$songURI = 'http:'.$1 if ($songURI =~ m/^x-rincon-mp3radio:(.*)/i);
	$songURI = uri_unescape($songURI) if ($songURI =~ m/^x-sonos-spotify:/i);
	
	return $songURI;
}

########################################################################################
#
#  SONOS_ExpandTimeString - Make sure, that the given TimeString is complete (like '0:04:12')
#
#  Parameter $timeStr = The timeStr that has to be proofed
#
########################################################################################
sub SONOS_ExpandTimeString($) {
	my ($timeStr) = @_;
	
	if ($timeStr !~ m/:/) {
		return '0:00:'.$timeStr;
	} elsif ($timeStr =~ m/^[^:]*:{1,1}[^:]*$/) {
		return '0:'.$timeStr;
	}
	
	return $timeStr;
}

########################################################################################
#
#  SONOS_GetTimeSeconds - Converts a Time-String like '0:04:12' to seconds (e.g. 252)
#
#  Parameter $timeStr = The timeStr that has to be converted
#
########################################################################################
sub SONOS_GetTimeSeconds($) {
	my ($timeStr) = @_;
	
	return (int($1)*3600 + int($2)*60 + int($3)) if ($timeStr =~ m/(\d+):(\d+):(\d+)/);
	return 0;
}

########################################################################################
#
#  SONOS_ConvertSecondsToTime - Converts seconds (e.g. 252) into a Time-String like '0:04:12'
#
#  Parameter $seconds = The seconds that have to be converted
#
########################################################################################
sub SONOS_ConvertSecondsToTime($) {
	my ($seconds) = @_;
	
	return sprintf('%01d:%02d:%02d', $seconds / 3600, ($seconds%3600) / 60, $seconds%60) if ($seconds > 0);
	return '0:00:00';
}

########################################################################################
#
#  SONOS_CheckProxyObject - Checks for existence of $proxyObject (=return 1) or not (=return 0). Additionally in case of error it lays an error-answer in the queue
#
#  Parameter $proxyObject = The Proxy that has to be checked
#
########################################################################################
sub SONOS_CheckProxyObject($$) {
	my ($udn, $proxyObject) = @_;
	
	if (defined($proxyObject)) {
		SONOS_Log $udn, 4, 'ProxyObject exists: '.$proxyObject;
		
		return 1;
	} else {
		SONOS_Log $udn, 3, 'ProxyObject does not exists';
		
		# Das Aufräumen der ProxyObjects und das Erzeugen des Notify wurde absichtlich nicht hier reingeschrieben, da es besser im IsAlive-Checker aufgehoben ist.
		SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', 'CheckProxyObject-ERROR: SonosPlayer disappeared?');
		return 0;
	}
}

########################################################################################
#
#  SONOS_MakeSigHandlerReturnValue - Enqueue all necessary elements on upward-queue
#
#  Parameter $returnValue = The value that has to be laid on the queue.
#
########################################################################################
sub SONOS_MakeSigHandlerReturnValue($$$) {
	my ($udn, $returnName, $returnValue) = @_;
	
	#Antwort melden
	SONOS_Client_Notifier('DoWorkAnswer:'.$udn.':'.$returnName.':'.$returnValue);
}

########################################################################################
#
#  SONOS_RestartControlPoint - Restarts the UPnP-ControlPoint
#
########################################################################################
sub SONOS_RestartControlPoint() {
	if (defined($SONOS_Controlpoint)) {
		$SONOS_RestartControlPoint = 1;
		
		$SONOS_Controlpoint->stopSearch($SONOS_Search); 
		$SONOS_Controlpoint->stopHandling();
		
		SONOS_Log undef, 4, 'ControlPoint is successfully stopped for restarting!';
	}
}

########################################################################################
#
#  SONOS_StopControlPoint - Stops all open Net-Handles and Search-Token of the UPnP Part
#
########################################################################################
sub SONOS_StopControlPoint {
	if (defined($SONOS_Controlpoint)) {
		$SONOS_Controlpoint->stopSearch($SONOS_Search); 
		$SONOS_Controlpoint->stopHandling();
		undef($SONOS_Controlpoint);
		
		SONOS_Log undef, 4, 'ControlPoint is successfully stopped!';
	} 
}

########################################################################################
#
#  SONOS_GetTagData - Return the content of the given tag in the given string
#
# Parameter $tagName = The tag to be searched for
#			$data = The string in which to search for
#
########################################################################################
sub SONOS_GetTagData($$) {
	my ($tagName, $data) = @_;
	
	return $1 if ($data =~ m/<$tagName.*?>(.*?)<\/$tagName>/i);
	return '';
}

########################################################################################
#
#  SONOS_AnswerMessage - Return 'Success' if param is true, 'Error' otherwise
#
# Parameter $var = The value to check
#
########################################################################################
sub SONOS_AnswerMessage($) {
	my ($var) = @_;
	
	if ($var) {
		return 'Success!';
	} else {
		return 'Error!';
	}
}

########################################################################################
#
#  SONOS_UPnPAnswerMessage - Return 'Success' if param is true, a complete error-message of the UPnP-answer otherwise
#
# Parameter $var = The UPnP-answer to check
#
########################################################################################
sub SONOS_UPnPAnswerMessage($) {
	my ($var) = @_;
	
	if ($var->isSuccessful) {
		return 'Success!';
	} else {
		my $faultcode = '-';
		my $faultstring = '-';
		my $faultactor = '-';
		my $faultdetail = '-';
		
		$faultcode = $var->faultcode if ($var->faultcode);
		$faultstring = $var->faultstring if ($var->faultstring);
		$faultactor = $var->faultactor if ($var->faultactor);
		$faultdetail = $var->faultdetail if ($var->faultdetail);
		
		return 'Error! UPnP-Fault-Fields: Code: "'.$faultcode.'", String: "'.$faultstring.'", Actor: "'.$faultactor.'", Detail: "'.SONOS_Stringify($faultdetail).'"';
	}
}

########################################################################################
#
#  SONOS_Dumper - Returns the 'Dumpered' Output of the given Datastructure-Reference
#
########################################################################################
sub SONOS_Dumper($) {
	my ($varRef) = @_;
	
	$Data::Dumper::Indent = 0;
	my $text = Dumper($varRef);
	$Data::Dumper::Indent = 2;
	
	return $text;
}

########################################################################################
#
#  SONOS_Stringify - Converts a given Value (Array, Hash, Scalar) to a readable string version
#
# Parameter $varRef = The value to convert to a readable version
#
########################################################################################
sub SONOS_Stringify {
	my ($varRef) = @_;
	
	return 'undef' if (!defined($varRef));
	
	my $reftype = reftype $varRef;
	if (!defined($reftype) || ($reftype eq '')) {
		if (looks_like_number($varRef)) {
			return $varRef;
		} else {
			$varRef =~ s/'/\\'/g;
			return "'".$varRef."'";
		}
	} elsif ($reftype eq 'HASH') {
		my %var = %{$varRef};
		
		my @result;
		foreach my $key (keys %var) {
			push(@result, $key.' => '.SONOS_Stringify($var{$key}));
		}
		
		return '{'.join(', ', @result).'}';
	} elsif ($reftype eq 'ARRAY') {
		my @var = @{$varRef};
	
		my @result;
		foreach my $value (@var) {
			push(@result, SONOS_Stringify($value));
		}
	
		return '['.join(', ', @result).']';
	} elsif ($reftype eq 'SCALAR') {
		if (looks_like_number(${$varRef})) {
			return ${$varRef};
		} else {
			${$varRef} =~ s/'/\\'/g;
			return "'".${$varRef}."'";
		}
	} else {
		return 'Unsupported Type ('.$reftype.') of: '.$varRef;
	}
}

########################################################################################
#
#  SONOS_UmlautConvert - Converts any umlaut (e.g. ä) to Ascii-conform writing (e.g. ae)
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_UmlautConvert($) {
	eval {
		use utf8;
		my ($var) = @_;
		
		if ($var eq 'ä') {
			return 'ae';
		} elsif ($var eq 'ö') {
			return 'oe';
		} elsif ($var eq 'ü') {
			return 'ue';
		} elsif ($var eq 'Ä') {
			return 'Ae';
		} elsif ($var eq 'Ö') {
			return 'Oe';
		} elsif ($var eq 'Ü') {
			return 'Ue';
		} elsif ($var eq 'ß') {
			return 'ss';
		} else {
			return '_';
		}
	}
}

########################################################################################
#
#  SONOS_ConvertUmlautToHtml - Converts any umlaut (e.g. ä) to Html-conform writing (e.g. &auml;)
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_ConvertUmlautToHtml($) {
	my ($var) = @_;
	
	if ($var eq 'ä') {
		return '&auml;';
	} elsif ($var eq 'ö') {
		return '&ouml;';
	} elsif ($var eq 'ü') {
		return '&uuml;';
	} elsif ($var eq 'Ä') {
		return '&Auml;';
	} elsif ($var eq 'Ö') {
		return '&Ouml;';
	} elsif ($var eq 'Ü') {
		return '&Uuml;';
	} elsif ($var eq 'ß') {
		return '&szlig;';
	} else {
		return $var;
	}
}

########################################################################################
#
#  SONOS_Latin1ToUtf8 - Converts Latin1 coding to UTF8
#
# Parameter $var = The value to convert
#
# http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
#
########################################################################################
sub SONOS_Latin1ToUtf8($) {
  my ($s)= @_;
  
  $s =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
  
  return $s;
}

########################################################################################
#
#  SONOS_Utf8ToLatin1 - Converts UTF8 coding to Latin1
#
# Parameter $var = The value to convert
#
# http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
#
########################################################################################
sub SONOS_Utf8ToLatin1($) {
  my ($s)= @_;
  
  $s =~ s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
  
  return $s;
}

########################################################################################
#
#  SONOS_ConvertNumToWord - Converts the values "0, 1" to "off, on"
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_ConvertNumToWord($) {
	my ($var) = @_;
	
	return 'off' if (!defined($var));
	
	if (!looks_like_number($var)) {
		return 'on' if (lc($var) ne 'off');
		return 'off';
	}
	
	if ($var == 0) {
		return 'off';
	} else {
		return 'on';
	}
}

########################################################################################
#
#  SONOS_ConvertWordToNum - Converts the values "off, on" to "0, 1"
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_ConvertWordToNum($) {
	my ($var) = @_;
	
	if (looks_like_number($var)) {
		return 1 if ($var != 0);
		return 0;
	}
	
	if (lc($var) eq 'off') {
		return 0;
	} else {
		return 1;
	}
}

########################################################################################
#
#  SONOS_ToggleNum - Convert the values "0, 1" to "1, 0"
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_ToggleNum($) {
	my ($var) = @_;
	
	if ($var == 0) {
		return 1;
	} else {
		return 0;
	}
}

########################################################################################
#
#  SONOS_ToggleWord - Convert the values "off, on" to "on, off"
#
# Parameter $var = The value to convert
#
########################################################################################
sub SONOS_ToggleWord($) {
	my ($var) = @_;
	
	if (lc($var) eq 'off') {
		return 'on';
	} else {
		return 'off';
	}
}

########################################################################################
#
#  SONOS_Discover_Callback - Discover-Callback, 
#                   				 autocreate devices if not already present
#
# Parameter $search = 
#			$device = 
#			$action =
#
########################################################################################
sub SONOS_Discover_Callback($$$) {
	my ($search, $device, $action) = @_;
	
	# Sicherheitsabfrage, da offensichtlich manchmal falsche Elemente durchkommen...
	if ($device->deviceType() ne 'urn:schemas-upnp-org:device:ZonePlayer:1') {
		SONOS_Log undef, 2, 'Discover-Event: Wrong deviceType "'.$device->deviceType().'" received!';
		return;
	}
	
	if ($action eq 'deviceAdded') {
		my $descriptionDocument;
		eval {
			$descriptionDocument = $device->descriptionDocument();
		};
		if ($@) {
			# Das Descriptiondocument konnte nicht abgefragt werden
			SONOS_Log undef, 2, 'Discover-Event: Wrong deviceType "'.$device->deviceType().'" received! Detected while trying to download the Description-Document from Player.';
			return;
		}
		
		# Wenn kein Description-Dokument geliefert wurde...
		if (!defined($descriptionDocument) || ($descriptionDocument eq '')) {
			SONOS_Log undef, 2, "Discover-Event: Description-Document is empty. Aborting this deviceadding-process.";
			return;
		}
		
		# Alles OK, es kann weitergehen
		SONOS_Log undef, 5, "Discover-Event: Description-Document: $descriptionDocument";
		
		$SONOS_Client_SendQueue_Suspend = 1;
		
		# Variablen initialisieren
		my $roomName = '';
		my $saveRoomName = '';
		my $modelNumber = '';
		my $displayVersion = '';
		my $serialNum = '';
		my $iconURI = '';
	
		# Um einen XML-Parser zu vermeiden, werden hier reguläre Ausdrücke für die Ermittlung der Werte eingesetzt...
		# RoomName ermitteln
		$roomName = decode_entities($1) if ($descriptionDocument =~ m/<roomName>(.*?)<\/roomName>/im);
		$saveRoomName = decode('UTF-8',  $roomName);
		eval {
			use utf8;
			$saveRoomName =~ s/([äöüÄÖÜß])/SONOS_UmlautConvert($1)/eg; # Hier erstmal Umlaute 'schön' machen, damit dafür nicht '_' verwendet werden...
		};
		$saveRoomName =~ s/[^a-zA-Z0-9_ ]//g;
		$saveRoomName = SONOS_Trim($saveRoomName);
		$saveRoomName =~ s/ /_/g;
		my $groupName = $saveRoomName;
	
		# Modelnumber ermitteln
		$modelNumber = decode_entities($1) if ($descriptionDocument =~ m/<modelNumber>(.*?)<\/modelNumber>/im);
		
		# DisplayVersion ermitteln
		$displayVersion = decode_entities($1) if ($descriptionDocument =~ m/<displayVersion>(.*?)<\/displayVersion>/im);
	
		# SerialNum ermitteln
		$serialNum = decode_entities($1) if ($descriptionDocument =~ m/<serialNum>(.*?)<\/serialNum>/im);
	
		# Icon-URI ermitteln
		$iconURI = decode_entities($1) if ($descriptionDocument =~ m/<iconList>.*?<icon>.*?<id>0<\/id>.*?<url>(.*?)<\/url>.*?<\/icon>.*?<\/iconList>/sim);
	
		# Kompletten Pfad zum Download des ZonePlayer-Bildchens zusammenbauen
		my $iconOrigPath = $device->location();
		$iconOrigPath =~ s/(http:\/\/.*?)\/.*/$1$iconURI/i;
	
		# Zieldateiname für das ZonePlayer-Bildchen zusammenbauen
		my $iconPath = $iconURI;
		$iconPath =~ s/.*\/(.*)/icoSONOSPLAYER_$1/i;
		
		my $udnShort = $device->UDN;
		$udnShort =~ s/.*?://i;
		my $udn = $udnShort.'_MR';
		
		$SONOS_Locations{$device->location()} = $udn;
		
		my $name = $SONOS_Client_Data{SonosDeviceName}."_".$saveRoomName;
		
		# Erkannte Werte ausgeben...
		SONOS_Log undef, 4, "RoomName: '$roomName', SaveRoomName: '$saveRoomName', ModelNumber: '$modelNumber', DisplayVersion: '$displayVersion', SerialNum: '$serialNum', IconURI: '$iconURI', IconOrigPath: '$iconOrigPath', IconPath: '$iconPath'";
	
		SONOS_Log undef, 2, "Discover Sonosplayer '$roomName' ($modelNumber) Software Revision $displayVersion with ID '$udn'";
		
		# Device sichern...
		$SONOS_UPnPDevice{$udn} = $device;
	
		# ServiceProxies für spätere Aufrufe merken
		my $alarmService = $device->getService('urn:schemas-upnp-org:service:AlarmClock:1');
		$SONOS_AlarmClockControlProxy{$udn} = $alarmService->controlProxy if ($alarmService);
		
		my $audioInService = $device->getService('urn:schemas-upnp-org:service:AudioIn:1');
		$SONOS_AudioInProxy{$udn} = $audioInService->controlProxy if ($audioInService);
		
		my $devicePropertiesService = $device->getService('urn:schemas-upnp-org:service:DeviceProperties:1');
		$SONOS_DevicePropertiesProxy{$udn} = $devicePropertiesService->controlProxy if ($devicePropertiesService);
		
		#$SONOS_GroupManagementProxy{$udn} = $device->getService('urn:schemas-upnp-org:service:GroupManagement:1')->controlProxy if ($device->getService('urn:schemas-upnp-org:service:GroupManagement:1'));
		
		my $musicServicesService = $device->getService('urn:schemas-upnp-org:service:MusicServices:1');
		$SONOS_MusicServicesProxy{$udn} = $musicServicesService->controlProxy if ($musicServicesService);
		
		my $zoneGroupTopologyService = $device->getService('urn:schemas-upnp-org:service:ZoneGroupTopology:1');
		$SONOS_ZoneGroupTopologyProxy{$udn} = $zoneGroupTopologyService->controlProxy if ($zoneGroupTopologyService);
		
		# Bei einem Dock gibt es AVTransport nur am Hauptdevice, deshalb mal schauen, ob wir es hier bekommen können
		my $transportService = $device->getService('urn:schemas-upnp-org:service:AVTransport:1');
		$SONOS_AVTransportControlProxy{$udn} = $transportService->controlProxy if ($transportService);
		
		my $renderingService;
		
		my $groupRenderingService;
		my $contentDirectoryService;
		
		# Hier die Subdevices durchgehen...
		for my $subdevice ($device->children) {
			SONOS_Log undef, 4, 'SubDevice found: '.$subdevice->UDN;
			
			if ($subdevice->UDN =~ /.*_MR/i) {
				# Wir haben hier das Media-Renderer Subdevice
				$transportService = $subdevice->getService('urn:schemas-upnp-org:service:AVTransport:1');
	    		$SONOS_AVTransportControlProxy{$udn} = $transportService->controlProxy if ($transportService);
	    		
	    		if ($modelNumber ne 'Sub') {
		    		$renderingService = $subdevice->getService('urn:schemas-upnp-org:service:RenderingControl:1');
		    		$SONOS_RenderingControlProxy{$udn} = $renderingService->controlProxy if ($renderingService);
		    	}
	    		
				$groupRenderingService = $subdevice->getService('urn:schemas-upnp-org:service:GroupRenderingControl:1');
	    		$SONOS_GroupRenderingControlProxy{$udn} = $groupRenderingService->controlProxy if ($groupRenderingService);
			}
			
			if ($subdevice->UDN =~ /.*_MS/i) { 
				# Wir haben hier das Media-Server Subdevice
				$contentDirectoryService = $subdevice->getService('urn:schemas-upnp-org:service:ContentDirectory:1');
				$SONOS_ContentDirectoryControlProxy{$udn} = $contentDirectoryService->controlProxy if ($contentDirectoryService);
			}
		}
		   
		SONOS_Log undef, 4, 'ControlProxies wurden gesichert';
		
		# ZoneTopology laden, um die Benennung der Fhem-Devices besser an die Realität anpassen zu können
		my ($isZoneBridge, $topoType, $fieldType, $master, $masterPlayerName, $aliasSuffix, $zoneGroupState) = SONOS_AnalyzeZoneGroupTopology($udn, $udnShort);
		my ($slavePlayerNamesRef, $notBondedSlavePlayerNamesRef) = SONOS_AnalyzeTopologyForSlavePlayer($udnShort, $zoneGroupState);
		my @slavePlayerNames = @{$slavePlayerNamesRef};
		my @slavePlayerNotBondedNames = @{$notBondedSlavePlayerNamesRef};
		
		# Wenn der aktuelle Player der Master ist, dann kein Kürzel anhängen, 
		# damit gibt es immer einen Player, der den Raumnamen trägt, und die anderen enthalten Kürzel
		if ($master) {
			$topoType = '';
		}
		
		# Raumnamen erweitern
		$name .= $topoType;
		$saveRoomName .= $topoType;
		
		# Volume laden um diese im Reading ablegen zu können
		my $currentVolume = 0;
		my $balance = 0;
		if (!$isZoneBridge) {
			if ($SONOS_RenderingControlProxy{$udn}) {
				eval {
					$currentVolume = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'Master')->getValue('CurrentVolume');
					
					# Balance ermitteln
					my $volumeLeft = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'LF')->getValue('CurrentVolume');
					my $volumeRight = $SONOS_RenderingControlProxy{$udn}->GetVolume(0, 'RF')->getValue('CurrentVolume');
					$balance = (-$volumeLeft) + $volumeRight;
					
					SONOS_Log undef, 4, 'Retrieve Current Volumelevels. Master: "'.$currentVolume.'", Balance: "'.$balance.'"';
				};
				if ($@) {
					$currentVolume = 0;
					$balance = 0;
					SONOS_Log undef, 4, 'Couldn\'t retrieve Current Volumelevels: '. $@;
				}
			} else {
				SONOS_Log undef, 4, 'Couldn\'t get any Volume Information due to missing RenderingControlProxy';
			}
		}
		
		# Load official icon from zoneplayer and copy it to local place for FHEM-use
		SONOS_Client_Notifier('getstore(\''.$iconOrigPath.'\', $attr{global}{modpath}.\'/www/images/default/'.$iconPath."');\n");
		
		# Icons neu einlesen lassen
		SONOS_Client_Notifier('SONOS_RefreshIconsInFHEMWEB(\'/www/images/default/'.$iconPath.'\');');
		
		# Transport Informations to FHEM
		# Check if this device is already defined...
		if (!SONOS_isInList($udn, @{$SONOS_Client_Data{PlayerUDNs}})) {
			push @{$SONOS_Client_Data{PlayerUDNs}}, $udn;
			
			# Wenn der Name schon mal verwendet wurde, dann solange ein Kürzel anhängen, bis ein freier Name gefunden wurde...
			while (SONOS_isInList($name, @{$SONOS_Client_Data{PlayerNames}})) {
				$name .= '_X';
				$saveRoomName .= '_X';
				
				SONOS_Log undef, 2, "New Fhem-Name neccessary for '$roomName' -> '$name', ID '$udn'";
			}
			push @{$SONOS_Client_Data{PlayerNames}}, $name;
			
			my %elemValues = ();
			$SONOS_Client_Data{Buffer}->{$udn} = shared_clone(\%elemValues);
			
			# Define SonosPlayer-Device...
			for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER', undef, $udn, undef, $name, undef, undef, undef, undef, undef)) {
				SONOS_Client_Notifier($elem);
			}
			# ...and his attributes
			for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER_Attributes', $SONOS_Client_Data{SonosDeviceName}, undef, $master, $name, $roomName, $aliasSuffix, $groupName, $iconPath, $isZoneBridge)) {
				SONOS_Client_Notifier($elem);
			}
			
			# Setting Internal-Data
			if (!$isZoneBridge) {
				SONOS_Client_Data_Refresh('', $udn, 'getAlarms', 1);
				SONOS_Client_Data_Refresh('', $udn, 'minVolume', 0);
			}
			
			# Define ReadingsGroup
			for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER_ReadingsGroup', $SONOS_Client_Data{SonosDeviceName}, undef, $master, $name, undef, undef, $groupName, undef, $isZoneBridge)) {
				SONOS_Client_Notifier($elem);
			}
			
			# Define ReadingsGroup-Listen
			for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER_ReadingsGroup_Listen', undef, undef, $master, $name, undef, undef, undef, undef, $isZoneBridge)) {
				SONOS_Client_Notifier($elem);
			}
			
			# Define RemoteControl
			for my $elem (SONOS_GetDefineStringlist('SONOSPLAYER_Remotecontrol', $SONOS_Client_Data{SonosDeviceName}, undef, $master, $name, undef, undef, $groupName, undef, $isZoneBridge)) {
				SONOS_Client_Notifier($elem);
			}
			
			# Name sichern...
			SONOS_Client_Data_Refresh('', $udn, 'NAME', $name);
			SONOS_Client_Data_Refresh('', 'udn', $name, $udn);
			
			SONOS_Log undef, 1, "Successfully autocreated SonosPlayer '$saveRoomName' ($modelNumber) as '$name' with Software Revision $displayVersion and ID '$udn'";
		} else {
			# Wenn das Device schon existiert, dann den dort verwendeten Namen holen
			$name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
			SONOS_Client_Data_Refresh('', 'udn', $name, $udn);
			
			SONOS_Log undef, 2, "SonosPlayer '$saveRoomName' ($modelNumber) with ID '$udn' is already defined (as '$name') and will only be updated";
		}
	
		# Wenn der Player noch nicht auf der "Aktiv"-Liste steht, dann draufpacken...
		push @{$SONOS_Client_Data{PlayerAlive}}, $udn if (!SONOS_isInList($udn, @{$SONOS_Client_Data{PlayerAlive}}));
		
		# Readings aktualisieren
		SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'presence', 'appeared');
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'Volume', $currentVolume);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'Balance', $balance);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomName', $roomName);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomNameAlias', $roomName.$aliasSuffix);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'saveRoomName', $saveRoomName);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'playerType', $modelNumber);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'Volume', $currentVolume);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'location', $device->location);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'softwareRevision', $displayVersion);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'serialNum', $serialNum);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'fieldType', $fieldType);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'IsBonded', (($fieldType eq '') || ($fieldType eq 'LF') || ($fieldType eq 'LF_RF')) ? '0' : '1');
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'IsMaster', $master ? '1' : '0');
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'MasterPlayer', $masterPlayerName);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayer', SONOS_Dumper(\@slavePlayerNames));
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBonded', SONOS_Dumper(\@slavePlayerNotBondedNames));
		if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBondedList', (scalar(@slavePlayerNotBondedNames) ? '-|' : '').join('|', @slavePlayerNotBondedNames));
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBondedListAlias', (scalar(@slavePlayerNotBondedNames) ? 'Auswahl|' : '').join('|', map { $_ = SONOS_Client_Data_Retreive($_, 'reading', 'roomName', $_); $_ } @slavePlayerNotBondedNames));
		}
		
		# Abspielreadings vorab ermitteln, um darauf prüfen zu können...
		if (!$isZoneBridge) {
			if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
				eval {
					my $result = $SONOS_AVTransportControlProxy{$udn}->GetTransportInfo(0);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'transportState', $result->getValue('CurrentTransportState'));
					
					$result = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0);
					my $tmp = $result->getValue('TrackURI');
					$tmp =~ s/&apos;/'/gi;
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackURI', $tmp);
					my ($trackProvider, $trackProviderRoundURL, $trackProviderQuadraticURL) = SONOS_GetTrackProvider($result->getValue('TrackURI'));
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackProvider', $trackProvider);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackProviderIconRoundURL', $trackProviderRoundURL);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackProviderIconQuadraticURL', $trackProviderQuadraticURL);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackDuration', $result->getValue('TrackDuration'));
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrackDurationSec', SONOS_GetTimeSeconds($result->getValue('TrackDuration')));
					
					my $modus = 'ReadingsBulkUpdate'.((SONOS_Client_Data_Retreive($udn, 'reading', 'currentStreamAudio', 0)) ? 'IfChanged' : '');
					SONOS_Client_Data_Refresh($modus, $udn, 'currentTrackPosition', $result->getValue('RelTime'));
					SONOS_Client_Data_Refresh($modus, $udn, 'currentTrackPositionSec', SONOS_GetTimeSeconds($result->getValue('RelTime')));
					
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentTrack', $result->getValue('Track'));
					
					$result = $SONOS_AVTransportControlProxy{$udn}->GetMediaInfo(0);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'numberOfTracks', $result->getValue('NrTracks'));
					my $stream = ($result->getValue('CurrentURI') =~ m/^x-(sonosapi|rincon)-(stream|mp3radio):.*?/);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentStreamAudio', $stream);
					SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'currentNormalAudio', !$stream);
				};
				if ($@) {
					SONOS_Log undef, 1, 'Couldn\'t retrieve Current Transportsettings during Discovery: '. $@;
				}
			}
		}
		
		SONOS_Client_Data_Refresh('', $udn, 'LastSubscriptionsRenew', SONOS_TimeNow());
		SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
		
		SONOS_Client_Notifier('CommandAttrWithUDN:'.$udn.':model Sonos_'.$modelNumber);
		
		$SONOS_Client_SendQueue_Suspend = 0;
		SONOS_Log undef, 2, "SonosPlayer '$saveRoomName' is now updated";
		
		# AVTransport-Subscription
		if (!$isZoneBridge) {
			if ($transportService) {
				$SONOS_TransportSubscriptions{$udn} = $transportService->subscribe(\&SONOS_TransportCallback);
				if (defined($SONOS_TransportSubscriptions{$udn})) {
					SONOS_Log undef, 2, 'Service-subscribing successful with SID='.$SONOS_TransportSubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'Service-subscribing NOT successful';
				}
			} else {
				undef($SONOS_TransportSubscriptions{$udn});
				SONOS_Log undef, 1, 'Service-subscribing not possible due to missing TransportService';
			}
		}
		
		# Rendering-Subscription, wenn eine untere oder obere Lautstärkegrenze angegeben wurde, und Lautstärke überhaupt geht
		if ($renderingService && (SONOS_Client_Data_Retreive($udn, 'attr', 'minVolume', -1) != -1 
								|| SONOS_Client_Data_Retreive($udn, 'attr', 'maxVolume', -1) != -1 
								|| SONOS_Client_Data_Retreive($udn, 'attr', 'minVolumeHeadphone', -1) != -1 
								|| SONOS_Client_Data_Retreive($udn, 'attr', 'maxVolumeHeadphone', -1) != -1)) {
			eval {
				$SONOS_RenderingSubscriptions{$udn} = $renderingService->subscribe(\&SONOS_RenderingCallback);
			};
			$SONOS_ButtonPressQueue{$udn} = Thread::Queue->new();
			if (defined($SONOS_RenderingSubscriptions{$udn})) {
				SONOS_Log undef, 2, 'Rendering-Service-subscribing successful with SID='.$SONOS_RenderingSubscriptions{$udn}->SID;
			} else {
				SONOS_Log undef, 1, 'Rendering-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_RenderingSubscriptions{$udn});
		}
		
		# GroupRendering-Subscription
		if ($groupRenderingService && (SONOS_Client_Data_Retreive($udn, 'attr', 'minVolume', -1) != -1 || SONOS_Client_Data_Retreive($udn, 'attr', 'maxVolume', -1) != -1 || SONOS_Client_Data_Retreive($udn, 'attr', 'minVolumeHeadphone', -1) != -1 || SONOS_Client_Data_Retreive($udn, 'attr', 'maxVolumeHeadphone', -1)  != -1 )) {
			$SONOS_GroupRenderingSubscriptions{$udn} = $groupRenderingService->subscribe(\&SONOS_GroupRenderingCallback);
			if (defined($SONOS_GroupRenderingSubscriptions{$udn})) {
				SONOS_Log undef, 2, 'GroupRendering-Service-subscribing successful with SID='.$SONOS_GroupRenderingSubscriptions{$udn}->SID;
			} else {
				SONOS_Log undef, 1, 'GroupRendering-Service-subscribing NOT successful';
			}
		} else {
			undef($SONOS_GroupRenderingSubscriptions{$udn});
		}
		
		# ContentDirectory-Subscription
		if ($contentDirectoryService) {
			eval {
				$SONOS_ContentDirectorySubscriptions{$udn} = $contentDirectoryService->subscribe(\&SONOS_ContentDirectoryCallback);
				if (defined($SONOS_ContentDirectorySubscriptions{$udn})) {
					SONOS_Log undef, 2, 'ContentDirectory-Service-subscribing successful with SID='.$SONOS_ContentDirectorySubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'ContentDirectory-Service-subscribing NOT successful';
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'ContentDirectory-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_ContentDirectorySubscriptions{$udn});
		}
		
		# Alarm-Subscription
		if ($alarmService && (SONOS_Client_Data_Retreive($udn, 'attr', 'getAlarms', 0) != 0)) {
			eval {
				$SONOS_AlarmSubscriptions{$udn} = $alarmService->subscribe(\&SONOS_AlarmCallback);
				if (defined($SONOS_AlarmSubscriptions{$udn})) {
					SONOS_Log undef, 2, 'Alarm-Service-subscribing successful with SID='.$SONOS_AlarmSubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'Alarm-Service-subscribing NOT successful';
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'Alarm-Service-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_AlarmSubscriptions{$udn});
		}
		
		# ZoneGroupTopology-Subscription
		if ($zoneGroupTopologyService) {
			eval {
				$SONOS_ZoneGroupTopologySubscriptions{$udn} = $zoneGroupTopologyService->subscribe(\&SONOS_ZoneGroupTopologyCallback);
				if (defined($SONOS_ZoneGroupTopologySubscriptions{$udn})) {
					SONOS_Log undef, 2, 'ZoneGroupTopology-Service-subscribing successful with SID='.$SONOS_ZoneGroupTopologySubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'ZoneGroupTopology-Service-subscribing NOT successful';
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'ZoneGroupTopology-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_ZoneGroupTopologySubscriptions{$udn});
		}
		
		# DeviceProperties-Subscription
		if ($devicePropertiesService) {
			eval {
				$SONOS_DevicePropertiesSubscriptions{$udn} = $devicePropertiesService->subscribe(\&SONOS_DevicePropertiesCallback);
				if (defined($SONOS_DevicePropertiesSubscriptions{$udn})) {
					SONOS_Log undef, 2, 'DeviceProperties-Service-subscribing successful with SID='.$SONOS_DevicePropertiesSubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'DeviceProperties-Service-subscribing NOT successful';
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'DeviceProperties-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_DevicePropertiesSubscriptions{$udn});
		}
		
		# AudioIn-Subscription
		if ($audioInService) {
			eval {
				$SONOS_AudioInSubscriptions{$udn} = $audioInService->subscribe(\&SONOS_AudioInCallback);
				if (defined($SONOS_AudioInSubscriptions{$udn})) {
					SONOS_Log undef, 2, 'AudioIn-Service-subscribing successful with SID='.$SONOS_AudioInSubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'AudioIn-Service-subscribing NOT successful';
					delete($SONOS_AudioInSubscriptions{$udn});
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'AudioIn-Service-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_AudioInSubscriptions{$udn});
		}
		
		# MusicServices-Subscription
		if ($musicServicesService) {
			eval {
				$SONOS_MusicServicesSubscriptions{$udn} = $musicServicesService->subscribe(\&SONOS_MusicServicesCallback);
				if (defined($SONOS_MusicServicesSubscriptions{$udn})) {
					SONOS_Log undef, 2, 'MusicServices-Service-subscribing successful with SID='.$SONOS_MusicServicesSubscriptions{$udn}->SID;
				} else {
					SONOS_Log undef, 1, 'MusicServices-Service-subscribing NOT successful';
					delete($SONOS_MusicServicesSubscriptions{$udn});
				}
			};
			if ($@) {
				SONOS_Log undef, 1, 'MusicServices-Service-Service-subscribing NOT successful: '.$@;
			}
		} else {
			undef($SONOS_MusicServicesSubscriptions{$udn});
		}

		
		SONOS_Log undef, 3, 'Discover: End of discover-event for "'.$roomName.'".';
	} elsif ($action eq 'deviceRemoved') {
		my $udn = $device->UDN;
		$udn =~ s/.*?://i;
		$udn .= '_MR';
		
		SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
		SONOS_Log undef, 2, "Device '$udn' removed. Do nothing special here, cause all is done in another way..."; 
	} 
	
	return 0;
}


########################################################################################
#
#  SONOS_GetDefineStringlist - Generates a list of define- or attr-commands acoording to the given desired-device
#
########################################################################################
sub SONOS_GetDefineStringlist($$$$$$$$$$) {
	my ($devicetype, $sonosDeviceName, $udn, $master, $name, $roomName, $aliasSuffix, $groupName, $iconPath, $isZoneBridge) = @_;
	
	my @defs = ();
	
	if (lc($devicetype) eq 'sonosplayer') {
		push(@defs, 'CommandDefine:'.$name.' SONOSPLAYER '.$udn);
	} elsif (lc($devicetype) eq 'sonosplayer_attributes') {
		push(@defs, 'CommandAttr:'.$name.' room '.$sonosDeviceName);
		push(@defs, 'CommandAttr:'.$name.' alias '.$roomName.$aliasSuffix);
		push(@defs, 'CommandAttr:'.$name.' group '.$groupName);
		push(@defs, 'CommandAttr:'.$name.' icon '.$iconPath);
		push(@defs, 'CommandAttr:'.$name.' sortby 1');
		
		if (!$isZoneBridge) {
			if (!SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				push(@defs, 'CommandAttr:'.$name.' userReadings Favourites:LastActionResult.*?GetFavouritesWithCovers.* { if (ReadingsVal($name, "LastActionResult", "") =~ m/.*?: (.*)/) { return $1; } }, Radios:LastActionResult.*?GetRadiosWithCovers.* { if (ReadingsVal($name, "LastActionResult", "") =~ m/.*?: (.*)/) { return $1; } }, Playlists:LastActionResult.*?GetPlaylistsWithCovers.* { if (ReadingsVal($name, "LastActionResult", "") =~ m/.*?: (.*)/) { return $1; } }, Queue:LastActionResult.*?GetQueueWithCovers.* { if (ReadingsVal($name, "LastActionResult", "") =~ m/.*?: (.*)/) { return $1; } }, currentTrackPosition:LastActionResult.*?GetCurrentTrackPosition.* { if (ReadingsVal($name, "LastActionResult", "") =~ m/.*?: (.*)/) { return $1; } }');
			}
			push(@defs, 'CommandAttr:'.$name.' generateInfoSummarize1 <NormalAudio><Artist prefix="(" suffix=")"/><Title prefix=" \'" suffix="\'" ifempty="[Keine Musikdatei]"/><Album prefix=" vom Album \'" suffix="\'"/></NormalAudio> <StreamAudio><Sender suffix=":"/><SenderCurrent prefix=" \'" suffix="\' -"/><SenderInfo prefix=" "/></StreamAudio>');
			push(@defs, 'CommandAttr:'.$name.' generateInfoSummarize2 <TransportState/><InfoSummarize1 prefix=" => "/>');
			push(@defs, 'CommandAttr:'.$name.' generateInfoSummarize3 <Volume prefix="Lautstärke: "/><Mute instead=" ~ Kein Ton" ifempty=" ~ Ton An" emptyval="0"/> ~ Balance: <Balance ifempty="Mitte" emptyval="0"/><HeadphoneConnected instead=" ~ Kopfhörer aktiv" ifempty=" ~ Kein Kopfhörer" emptyval="0"/>');
			push(@defs, 'CommandAttr:'.$name.' generateVolumeSlider 1');
			push(@defs, 'CommandAttr:'.$name.' getAlarms 1');
			push(@defs, 'CommandAttr:'.$name.' minVolume 0');
			#push(@defs, 'CommandAttr:'.$name.' stateVariable Presence');
			push(@defs, 'CommandAttr:'.$name.' stateFormat presence ~ currentTrackPositionSimulatedPercent% (currentTrackPositionSimulated / currentTrackDuration)');
			push(@defs, 'CommandAttr:'.$name.' getTitleInfoFromMaster 1');
			push(@defs, 'CommandAttr:'.$name.' simulateCurrentTrackPosition 1');
			
			push(@defs, 'CommandAttr:'.$name.' webCmd Volume');
			#push(@defs, 'CommandAttr:'.$name.' webCmd Play:Pause:Previous:Next:VolumeD:VolumeU:MuteT');
		} else {
			push(@defs, 'CommandAttr:'.$name.' stateFormat presence');
		}
	} elsif (lc($devicetype) eq 'sonosplayer_readingsgroup') {
		if (!$isZoneBridge) {
			if ($master) {
#				push(@defs, 'CommandDefine:'.$name.'RG readingsGroup '.$name.':<{SONOS_getCoverTitleRG($DEVICE)}@infoSummarize2>');
#				push(@defs, 'CommandAttr:'.$name.'RG room '.$sonosDeviceName);
#				push(@defs, 'CommandAttr:'.$name.'RG group '.$groupName);
#				push(@defs, 'CommandAttr:'.$name.'RG sortby 2');
#				push(@defs, 'CommandAttr:'.$name.'RG noheading 1');
#				push(@defs, 'CommandAttr:'.$name.'RG nonames 1');
				
				#push(@defs, 'CommandDefine:'.$name.'RG2 readingsGroup '.$name.':infoSummarize2@{SONOSPLAYER_GetMasterPlayerName($DEVICE)}');
				#push(@defs, 'CommandAttr:'.$name.'RG2 valueFormat {" "}');
				#push(@defs, 'CommandAttr:'.$name.'RG2 valuePrefix {SONOS_getCoverTitleRG(SONOSPLAYER_GetMasterPlayerName($DEVICE))}');
				#push(@defs, 'CommandAttr:'.$name.'RG2 room '.$SONOS_Client_Data{SonosDeviceName});
				#push(@defs, 'CommandAttr:'.$name.'RG2 group '.$groupName);
				#push(@defs, 'CommandAttr:'.$name.'RG2 sortby 4');
				#push(@defs, 'CommandAttr:'.$name.'RG2 noheading 1');
				#push(@defs, 'CommandAttr:'.$name.'RG2 nonames 1');
				#push(@defs, 'CommandAttr:'.$name.'RG2 notime 1');
			}
		}
	} elsif (lc($devicetype) eq 'sonosplayer_readingsgroup_listen') {
		if (!$isZoneBridge) {
			if ($master) {
				push(@defs, 'CommandDefine:'.$name.'RG_Favourites readingsGroup '.$name.':<{SONOS_getListRG($DEVICE,"Favourites",1)}@Favourites>');
				push(@defs, 'CommandDefine:'.$name.'RG_Radios readingsGroup '.$name.':<{SONOS_getListRG($DEVICE,"Radios",1)}@Radios>');
				push(@defs, 'CommandDefine:'.$name.'RG_Playlists readingsGroup '.$name.':<{SONOS_getListRG($DEVICE,"Playlists")}@Playlists>');
				push(@defs, 'CommandDefine:'.$name.'RG_Queue readingsGroup '.$name.':<{SONOS_getListRG($DEVICE,"Queue")}@Queue>');
			}
		}
	} elsif (lc($devicetype) eq 'sonosplayer_remotecontrol') {
		if (!$isZoneBridge) {
			if ($master) {
				#push(@defs, 'CommandDefine:'.$name.'RC remotecontrol');
				#push(@defs, 'CommandAttr:'.$name.'RC room hidden');
				#push(@defs, 'CommandAttr:'.$name.'RC group '.$sonosDeviceName);
				#push(@defs, 'CommandAttr:'.$name.'RC rc_iconpath icons/remotecontrol');
				#push(@defs, 'CommandAttr:'.$name.'RC rc_iconprefix black_btn_');
				#push(@defs, 'CommandAttr:'.$name.'RC row00 Play:rc_PLAY.svg,Pause:rc_PAUSE.svg,Previous:rc_PREVIOUS.svg,Next:rc_NEXT.svg,:blank,VolumeD:rc_VOLDOWN.svg,VolumeU:rc_VOLUP.svg,:blank,MuteT:rc_MUTE.svg,ShuffleT:rc_SHUFFLE.svg,RepeatT:rc_REPEAT.svg');
				
				#push(@defs, 'CommandDefine:'.$name.'RC_Notify notify '.$name.'RC set '.$name.' $EVENT');
				
				#push(@defs, 'CommandDefine:'.$name.'RC_Weblink weblink htmlCode {fhem("get '.$name.'RC htmlcode", 1)}');
				#push(@defs, 'CommandAttr:'.$name.'RC_Weblink room '.$sonosDeviceName);
				#push(@defs, 'CommandAttr:'.$name.'RC_Weblink group '.$groupName);
				#push(@defs, 'CommandAttr:'.$name.'RC_Weblink sortby 3');
			}
		}
	}
	
	return @defs;
}

########################################################################################
#
#  SONOS_AnalyzeZoneGroupTopology - Analyzes the current Zoneplayertopology for better naming of the components
#
########################################################################################
sub SONOS_AnalyzeZoneGroupTopology($$) {
	my ($udn, $udnShort) = @_;
	
	# ZoneTopology laden, um die Benennung der Fhem-Devices besser an die Realität anpassen zu können
	my $topoType = '';
	my $fieldType = '';
	my $master = 1;
	my $masterPlayerName;
	my $isZoneBridge = 0;
	my $zoneGroupState = '';
	if ($SONOS_ZoneGroupTopologyProxy{$udn}) {
		$zoneGroupState = $SONOS_ZoneGroupTopologyProxy{$udn}->GetZoneGroupState()->getValue('ZoneGroupState');
		SONOS_Log undef, 5, 'ZoneGroupState: '.$zoneGroupState;
		
		if ($zoneGroupState =~ m/.*(<ZoneGroup Coordinator="(RINCON_[0-9a-f]+)".*?>).*?(<(ZoneGroupMember|Satellite) UUID="$udnShort".*?(>|\/>))/is) {
			my $coordinator = $2;
			my $member = $3;
			
			$masterPlayerName = SONOS_Client_Data_Retreive($coordinator.'_MR', 'def', 'NAME', $coordinator.'_MR');
			
			# Ist dieser Player in einem ChannelMapSet (also einer Paarung) enthalten?
			if ($member =~ m/ChannelMapSet=".*?$udnShort:(.*?),(.*?)[;"]/is) {
				$topoType = '_'.$1;
			}
			
			# Ist dieser Player in einem HTSatChanMapSet (also einem Surround-System) enthalten?
			if ($member =~ m/HTSatChanMapSet=".*?$udnShort:(.*?)[;"]/is) {
				$topoType = '_'.$1;
				$topoType =~ s/,/_/g;
			}
			
			SONOS_Log undef, 4, 'Retrieved TopoType: '.$topoType;
			$fieldType = substr($topoType, 1) if ($topoType);
			
			my $invisible = 0;
			$invisible = 1 if ($member =~ m/Invisible="1"/i);
			
			$isZoneBridge = 1 if ($member =~ m/IsZoneBridge="1"/i);
			
			$master = !$invisible || $isZoneBridge;
		}
	}
	
	# Für den Aliasnamen schöne Bezeichnungen ermitteln...
	my $aliasSuffix = '';
	$aliasSuffix = ' - Hinten Links' if ($topoType eq '_LR');
	$aliasSuffix = ' - Hinten Rechts' if ($topoType eq '_RR');
	$aliasSuffix = ' - Links' if ($topoType eq '_LF');
	$aliasSuffix = ' - Rechts' if ($topoType eq '_RF');
	$aliasSuffix = ' - Subwoofer' if ($topoType eq '_SW');
	$aliasSuffix = ' - Mitte' if ($topoType eq '_LF_RF');
	
	return ($isZoneBridge, $topoType, $fieldType, $master, $masterPlayerName, $aliasSuffix, $zoneGroupState);
}

########################################################################################
#
#  SONOS_IsAlive - Checks if the given Device is alive or not and triggers the proper event if status changed
#
# Parameter $udn = UDN of the Device in short-form (e.g. RINCON_000E5828D0F401400_MR)
#
########################################################################################
sub SONOS_IsAlive($) {
	my ($udn) = @_;
	
	SONOS_Log $udn, 4, "IsAlive-Event UDN=$udn";
	my $result = 1;
	my $doDeleteProxyObjects = 0;
	
	$SONOS_Client_SendQueue_Suspend = 1;

	my $location = SONOS_Client_Data_Retreive($udn, 'reading', 'location', '');
	if ($location) {
		SONOS_Log $udn, 5, "Location: $location";
		my ($host, $port) = ($1, $2) if ($location =~ m/http:\/\/(.*?):(.*?)\//);
		
		my $pingType = $SONOS_Client_Data{pingType};
		return 1 if (lc($pingType) eq 'none');
		if (SONOS_isInList($pingType, @SONOS_PINGTYPELIST)) {
			SONOS_Log $udn, 5, "PingType: $pingType";
		} else {
			SONOS_Log $udn, 1, "Wrong pingType given for '$udn': '$pingType'. Choose one of '".join(', ', @SONOS_PINGTYPELIST)."'";
			$pingType = $SONOS_DEFAULTPINGTYPE;
		}
	
		my $ping = Net::Ping->new($pingType, 1);
		$ping->source_verify(0); # Es ist egal, von welcher Schnittstelle des Zielsystems die Antwort kommt
		$ping->port_number($port) if (lc($pingType) eq 'tcp'); # Wenn TCP verwendet werden soll, dann auf HTTP-Port des Location-Documents (Standard: 1400) des Player verbinden
		if ($ping->ping($host)) {
			# Alive
			SONOS_Log $udn, 4, "$host is alive";
			$result = 1;
			
			# IsAlive-Negativ-Counter zurücksetzen
			$SONOS_Thread_IsAlive_Counter{$host} = 0;
		} else {
			# Not Alive
			$SONOS_Thread_IsAlive_Counter{$host}++;
			
			if ($SONOS_Thread_IsAlive_Counter{$host} > $SONOS_Thread_IsAlive_Counter_MaxMerci) {
				SONOS_Log $udn, 3, "$host is REALLY NOT alive (out of merci maxlevel '".$SONOS_Thread_IsAlive_Counter_MaxMerci.'\')';
				$result = 0;
				
				SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'presence', 'disappeared');
				# Brauchen wir das wirklich? Dabei werden die lokalen Infos nicht aktualisiert...
				#SONOS_Client_Notifier('deleteCurrentNextTitleInformationAndDisappear:'.$udn);
				SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'state', 'disappeared');
				SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'transportState', 'STOPPED');
				$doDeleteProxyObjects = 1;
			} else {
				SONOS_Log $udn, 3, "$host is NOT alive, but in merci level ".$SONOS_Thread_IsAlive_Counter{$host}.'/'.$SONOS_Thread_IsAlive_Counter_MaxMerci.'.';
			}
		}
		$ping->close();
	}
	
	$SONOS_Client_SendQueue_Suspend = 0;
	
	# Jetzt, wo das Reading dazu auch gesetzt wurde, hier ausführen
	if ($doDeleteProxyObjects) {
		my %data;
		$data{WorkType} = 'deleteProxyObjects';
		$data{UDN} = $udn;
		my @params = ();
		$data{Params} = \@params;
		
		$SONOS_ComObjectTransportQueue->enqueue(\%data);
	}
	
	return $result;
}

########################################################################################
#
#  SONOS_DeleteProxyObjects - Deletes all references to the proxy objects of the given zoneplayer
#
# Parameter $name = The name of zoneplayerdevice
#
########################################################################################
sub SONOS_DeleteProxyObjects($) {
	my ($udn) = @_;
	
	SONOS_Log $udn, 4, "Delete ProxyObjects and SubscriptionObjects for '$udn'";
	
	delete $SONOS_AVTransportControlProxy{$udn};
	delete $SONOS_RenderingControlProxy{$udn};
	delete $SONOS_ContentDirectoryControlProxy{$udn};
	delete $SONOS_AlarmClockControlProxy{$udn};
	delete $SONOS_AudioInProxy{$udn};
	delete $SONOS_DevicePropertiesProxy{$udn};
	delete $SONOS_GroupManagementProxy{$udn};
	delete $SONOS_MusicServicesProxy{$udn};
	delete $SONOS_ZoneGroupTopologyProxy{$udn};
	
	delete $SONOS_TransportSubscriptions{$udn};
	delete $SONOS_RenderingSubscriptions{$udn};
	delete $SONOS_GroupRenderingSubscriptions{$udn};
	delete $SONOS_ContentDirectorySubscriptions{$udn};
	delete $SONOS_AlarmSubscriptions{$udn}; 
	delete $SONOS_ZoneGroupTopologySubscriptions{$udn};
	delete $SONOS_DevicePropertiesSubscriptions{$udn};
	delete $SONOS_AudioInSubscriptions{$udn};
	delete $SONOS_MusicServicesSubscriptions{$udn};
	
	# Am Ende noch das Device entfernen...
	delete $SONOS_UPnPDevice{$udn};
	
	SONOS_Log $udn, 4, "Delete of ProxyObjects and SubscriptionObjects DONE for '$udn'";
}

########################################################################################
#
#  SONOS_GetReadingsToCurrentHash - Get all neccessary readings from named device
#
# Parameter $name = The name of the player-device
#
########################################################################################
sub SONOS_GetReadingsToCurrentHash($$) {
	my ($name, $emptyCurrent) = @_;
	
	my %current;
	
	if ($emptyCurrent) {
		# Empty Values for Current Track Readings
		$current{TransportState} = 'ERROR';
		$current{Shuffle} = 0;
		$current{Repeat} = 0;
		$current{RepeatOne} = 0;
		$current{CrossfadeMode} = 0;
		$current{NumberOfTracks} = '';
		$current{Track} = '';
		$current{TrackURI} = '';
		$current{TrackHandle} = '';
		$current{TrackDuration} = '';
		$current{TrackDurationSec} = '';
		$current{TrackPosition} = '';
		$current{TrackProvider} = '';
		$current{TrackProviderIconQuadraticURL} = '';
		$current{TrackProviderIconRoundURL} = '';
		$current{TrackMetaData} = '';
		$current{AlbumArtURI} = '';
		$current{AlbumArtURL} = '';
		$current{Title} = '';
		$current{Artist} = '';
		$current{Album} = '';
		$current{Source} = '';
		$current{OriginalTrackNumber} = '';
		$current{AlbumArtist} = '';
		$current{Sender} = '';
		$current{SenderCurrent} = '';
		$current{SenderInfo} = '';
		$current{nextTrackDuration} = '';
		$current{nextTrackDurationSec} = '';
		$current{nextTrackURI} = '';
		$current{nextTrackHandle} = '';
		$current{nextAlbumArtURI} = '';
		$current{nextAlbumArtURL} = '';
		$current{nextTitle} = '';
		$current{nextArtist} = '';
		$current{nextAlbum} = '';
		$current{nextAlbumArtist} = '';
		$current{nextOriginalTrackNumber} = '';
		$current{InfoSummarize1} = '';
		$current{InfoSummarize2} = '';
		$current{InfoSummarize3} = '';
		$current{InfoSummarize4} = '';
		$current{StreamAudio} = 0;
		$current{NormalAudio} = 0;
	} else {
		# Insert normal Current Track Readings
		$current{TransportState} = ReadingsVal($name, 'transportState', 'ERROR');
		$current{Shuffle} = ReadingsVal($name, 'Shuffle', 0);
		$current{Repeat} = ReadingsVal($name, 'Repeat', 0);
		$current{RepeatOne} = ReadingsVal($name, 'RepeatOne', 0);
		$current{CrossfadeMode} = ReadingsVal($name, 'CrossfadeMode', 0);
		$current{NumberOfTracks} = ReadingsVal($name, 'numberOfTracks', '');
		$current{Track} = ReadingsVal($name, 'currentTrack', '');
		$current{TrackURI} = ReadingsVal($name, 'currentTrackURI', '');
		$current{TrackHandle} = ReadingsVal($name, 'currentTrackHandle', '');
		$current{EnqueuedTransportURI} = ReadingsVal($name, 'currentEnqueuedTransportURI', '');
		$current{EnqueuedTransportHandle} = ReadingsVal($name, 'currentEnqueuedTransportHandle', '');
		
		$current{TrackDuration} = ReadingsVal($name, 'currentTrackDuration', '');
		$current{TrackDurationSec} = ReadingsVal($name, 'currentTrackDurationSec', '');
		$current{TrackPosition} = ReadingsVal($name, 'currentTrackPosition', '');
		$current{TrackPosition} = ReadingsVal($name, 'currentTrackPositionSec', '');
		$current{TrackProvider} = ReadingsVal($name, 'currentTrackProvider', '');
		$current{TrackProviderIconQuadraticURL} = ReadingsVal($name, 'currentTrackProviderIconQuadraticURL', '');
		$current{TrackProviderIconRoundURL} = ReadingsVal($name, 'currentTrackProviderIconRoundURL', '');
		#$current{TrackMetaData} = '';
		$current{AlbumArtURI} = ReadingsVal($name, 'currentAlbumArtURI', '');
		$current{AlbumArtURL} = ReadingsVal($name, 'currentAlbumArtURL', '');
		$current{Title} = ReadingsVal($name, 'currentTitle', '');
		$current{Artist} = ReadingsVal($name, 'currentArtist', '');
		$current{Album} = ReadingsVal($name, 'currentAlbum', '');
		$current{Source} = ReadingsVal($name, 'currentSource', '');
		$current{OriginalTrackNumber} = ReadingsVal($name, 'currentOriginalTrackNumber', '');
		$current{AlbumArtist} = ReadingsVal($name, 'currentAlbumArtist', '');
		$current{Sender} = ReadingsVal($name, 'currentSender', '');
		$current{SenderCurrent} = ReadingsVal($name, 'currentSenderCurrent', '');
		$current{SenderInfo} = ReadingsVal($name, 'currentSenderInfo', '');
		$current{nextTrackDuration} = ReadingsVal($name, 'nextTrackDuration', '');
		$current{nextTrackDurationSec} = ReadingsVal($name, 'nextTrackDurationSec', '');
		$current{nextTrackURI} = ReadingsVal($name, 'nextTrackURI', '');
		$current{nextTrackHandle} = ReadingsVal($name, 'nextTrackHandle', '');
		$current{nextTrackProvider} = ReadingsVal($name, 'nextTrackProvider', '');
		$current{nextTrackProviderIconQuadraticURL} = ReadingsVal($name, 'nextTrackProviderIconQuadraticURL', '');
		$current{nextTrackProviderIconRoundURL} = ReadingsVal($name, 'nextTrackProviderIconRoundURL', '');
		$current{nextAlbumArtURI} = ReadingsVal($name, 'nextAlbumArtURI', '');
		$current{nextAlbumArtURL} = ReadingsVal($name, 'nextAlbumArtURL', '');
		$current{nextTitle} = ReadingsVal($name, 'nextTitle', '');
		$current{nextArtist} = ReadingsVal($name, 'nextArtist', '');
		$current{nextAlbum} = ReadingsVal($name, 'nextAlbum', '');
		$current{nextAlbumArtist} = ReadingsVal($name, 'nextAlbumArtist', '');
		$current{nextOriginalTrackNumber} = ReadingsVal($name, 'nextOriginalTrackNumber', '');
		$current{InfoSummarize1} = ReadingsVal($name, 'infoSummarize1', '');
		$current{InfoSummarize2} = ReadingsVal($name, 'infoSummarize2', '');
		$current{InfoSummarize3} = ReadingsVal($name, 'infoSummarize3', '');
		$current{InfoSummarize4} = ReadingsVal($name, 'infoSummarize4', '');
		$current{StreamAudio} = ReadingsVal($name, 'currentStreamAudio', 0);
		$current{NormalAudio} = ReadingsVal($name, 'currentNormalAudio', 0);
	}
  
	# Insert Variables scanned during Device Detection or other events (for simple Replacing-Option of InfoSummarize)
	$current{Volume} = ReadingsVal($name, 'Volume', 0);
	$current{Mute} = ReadingsVal($name, 'Mute', 0);
	$current{OutputFixed} = ReadingsVal($name, 'OutputFixed', 0);
	$current{Balance} = ReadingsVal($name, 'Balance', 0);
	$current{HeadphoneConnected} = ReadingsVal($name, 'HeadphoneConnected', 0);
	$current{SleepTimer} = ReadingsVal($name, 'SleepTimer', '');
	$current{AlarmRunning} = ReadingsVal($name, 'AlarmRunning', '');
	$current{AlarmRunningID} = ReadingsVal($name, 'AlarmRunningID', '');
	$current{DirectControlClientID} = ReadingsVal($name, 'DirectControlClientID', '');
	$current{DirectControlIsSuspended} = ReadingsVal($name, 'DirectControlIsSuspended', '');
	$current{DirectControlAccountID} = ReadingsVal($name, 'DirectControlAccountID', '');
	$current{Presence} = ReadingsVal($name, 'presence', '');
	$current{RoomName} = ReadingsVal($name, 'roomName', '');
	$current{RoomNameAlias} = ReadingsVal($name, 'roomNameAlias', '');
	$current{SaveRoomName} = ReadingsVal($name, 'saveRoomName', '');
	$current{PlayerType} = ReadingsVal($name, 'playerType', '');
	$current{Location} = ReadingsVal($name, 'location', '');
	$current{SoftwareRevision} = ReadingsVal($name, 'softwareRevision', '');
	$current{SerialNum} = ReadingsVal($name, 'serialNum', '');
	$current{ZoneGroupID} = ReadingsVal($name, 'ZoneGroupID', '');
	$current{ZoneGroupName} = ReadingsVal($name, 'ZoneGroupName', '');
	$current{ZonePlayerUUIDsInGroup} = ReadingsVal($name, 'ZonePlayerUUIDsInGroup', '');
	
	return %current;
}

########################################################################################
#
#  SONOS_TransportCallback - Transport-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_TransportCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'Transport-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 4, "Transport-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received Transport-Event for Zone "'.$name.'".';
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:AVTransport:1') {
		SONOS_Log $udn, 1, 'Transport-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	# Check if the Variable called LastChange exists
	if (not defined($properties{LastChange})) {
		SONOS_Log $udn, 1, 'Transport-Event receive error: Property \'LastChange\' does not exists!';
		return;
	}
  
	SONOS_Log $udn, 4, "Transport-Event: All correct with this service-call till now. UDN='uuid:$udn'";
	$SONOS_Client_SendQueue_Suspend = 1;
	
	my $affectSleeptimer = 0;
	
	
	# Determine the base URLs for downloading things from player
	my $groundURL = ($1) if ($service->base =~ m/(http:\/\/.*?:\d+)/i);
	SONOS_Log $udn, 4, "Transport-Event: GroundURL: $groundURL";
  
	# Variablen initialisieren
	SONOS_Client_Notifier('GetReadingsToCurrentHash:'.$udn.':1');
	
	# Die Daten wurden uns HTML-Kodiert übermittelt... diese Entities nun in Zeichen umwandeln, da sonst die regulären Ausdrücke ziemlich unleserlich werden...
	$properties{LastChangeDecoded} = decode_entities($properties{LastChange});
	$properties{LastChangeDecoded} =~ s/[\r\n]//isg; # Komischerweise können hier unmaskierte Newlines auftauchen... wegmachen

	# Verarbeitung starten	
	SONOS_Log $udn, 4, 'Transport-Event: LastChange: '.$properties{LastChangeDecoded};
	
	# Alte Bookmarks aktualisieren, gespeicherte Trackposition bei Bedarf anspringen...
	SONOS_RefreshCurrentBookmarkQueueValues($udn);
	{ # Start local area...
		my $bufferedURI = '';
		$bufferedURI = SONOS_GetURIFromQueueValue($1) if ($properties{LastChangeDecoded} =~ m/<CurrentTrackURI val="(.*?)"\/>/i);
		$bufferedURI =~ s/&apos;/'/gi;
		
		my $bufferedTrackDuration = 0;
		$bufferedTrackDuration = SONOS_GetTimeSeconds(decode_entities($1)) if ($properties{LastChangeDecoded} =~ m/<CurrentTrackDuration val="(.*?)"\/>/i);
		
		my $bufferedTrackPosition = 0;
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			$bufferedTrackPosition = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('RelTime');
			if ($bufferedTrackPosition !~ /\d+:\d+:\d+/i) { # e.g. NOT_IMPLEMENTED
				$bufferedTrackPosition = '0:00:00';
			}
			$bufferedTrackPosition = SONOS_GetTimeSeconds($bufferedTrackPosition);
		}
		
		if (($SONOS_BookmarkSpeicher{OldTrackURIs}{$udn} ne $bufferedURI) && SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			my $timestamp = scalar(gettimeofday());
			
			foreach my $gKey (SONOS_getBookmarkGroupKeys('Title', $udn)) {
				if (defined($SONOS_BookmarkTitleHash{$gKey}{$bufferedURI}) && SONOS_getBookmarkTitleIsRelevant($gKey, $timestamp, $bufferedURI, $bufferedTrackPosition, $bufferedTrackDuration)) {
					my $newTrackposition = $SONOS_BookmarkTitleHash{$gKey}{$bufferedURI}{TrackPosition};
					my $result = $SONOS_AVTransportControlProxy{$udn}->Seek(0, 'REL_TIME', SONOS_ConvertSecondsToTime($newTrackposition));
					
					SONOS_Log $udn, 3, 'Player "'.SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn).'" jumped to the bookmarked trackposition '.SONOS_ConvertSecondsToTime($newTrackposition).' (Group "'.$gKey.'") ~ Bookmarkdata: '.SONOS_Dumper($SONOS_BookmarkTitleHash{$gKey}{$bufferedURI});
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', 'JumpToTrackPosition "'.SONOS_ConvertSecondsToTime($newTrackposition).'": '.SONOS_UPnPAnswerMessage($result));
					
					last;
				}
			}
		}
	}
	
	
	# Bulkupdate hier starten...
	#SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	# Check, if this is a SleepTimer-Event
	my $sleepTimerVersion = $1 if ($properties{LastChangeDecoded} =~ m/<r:SleepTimerGeneration val="(.*?)"\/>/i);
	if (defined($sleepTimerVersion) && $sleepTimerVersion ne SONOS_Client_Data_Retreive($udn, 'reading', 'SleepTimerVersion', '')) {
		# Variablen neu initialisieren, und die Original-Werte wieder mit reinholen
		SONOS_Client_Notifier('GetReadingsToCurrentHash:'.$udn.':0');
		
		# Neuer SleepTimer da!
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			my $result = $SONOS_AVTransportControlProxy{$udn}->GetRemainingSleepTimerDuration();
			my $currentValue = $result->getValue('RemainingSleepTimerDuration');
			
			# Wenn der Timer abgelaufen ist, wird nur ein Leerstring übergeben. Diesen durch das Wort off ersetzen.
			$currentValue = 'off' if (!defined($currentValue) || ($currentValue eq ''));
			
			SONOS_Client_Notifier('SetCurrent:SleepTimer:'.$currentValue);
			
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SleepTimerVersion', ($result->getValue('CurrentSleepTimerGeneration') ? $result->getValue('CurrentSleepTimerGeneration') : ''));
		}
	}
	
	# Um einen XML-Parser zu vermeiden, werden hier einige reguläre Ausdrücke für die Ermittlung der Werte eingesetzt...
	# Transportstate ermitteln	
	if ($properties{LastChangeDecoded} =~ m/<TransportState val="(.*?)"\/>/i) {
		my $currentValue = decode_entities($1);
		# Wenn der TransportState den neuen Wert 'Transitioning' hat, dann diesen auf Playing umsetzen, da das hier ausreicht.
		$currentValue = 'PLAYING' if ($currentValue =~ m/TRANSITIONING/i);
		SONOS_Client_Notifier('SetCurrent:TransportState:'.$currentValue);
		
		$affectSleeptimer = 1 if (($currentValue ne SONOS_Client_Data_Retreive($udn, 'reading', 'currentTransportState', '')) && ($currentValue ne 'PLAYING'));
		
		$SONOS_BookmarkSpeicher{OldTransportstate}{$udn} = $currentValue;
	}
	
	#Wird hier gerade eine DirectPlay-Wiedergabe durchgeführt?
	SONOS_Client_Notifier('SetCurrent:DirectControlClientID:'.$1) if ($properties{LastChangeDecoded} =~ m/<r:DirectControlClientID val="(.*?)"\/>/i);
	SONOS_Client_Notifier('SetCurrent:DirectControlIsSuspended:'.$1) if ($properties{LastChangeDecoded} =~ m/<r:DirectControlIsSuspended val="(.*?)"\/>/i);
	SONOS_Client_Notifier('SetCurrent:DirectControlAccountID:'.$1) if ($properties{LastChangeDecoded} =~ m/<r:DirectControlAccountID val="(.*?)"\/>/i);
	
	# Wird hier gerade eine Alarm-Abspielung durchgeführt (oder beendet)?
	SONOS_Client_Notifier('SetCurrent:AlarmRunning:'.$1) if ($properties{LastChangeDecoded} =~ m/<r:AlarmRunning val="(.*?)"\/>/i);
	
	# Wenn ein Alarm läuft, dann zusätzliche Informationen besorgen, ansonsten das entsprechende Reading leeren
	if (defined($1) && $1 eq '1') {
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			my $alarmID = $SONOS_AVTransportControlProxy{$udn}->GetRunningAlarmProperties(0)->getValue('AlarmID');
			SONOS_Client_Notifier('SetCurrent:AlarmRunningID:'.$alarmID);
		}
	} elsif (defined($1) && $1 eq '0') {
		SONOS_Client_Notifier('SetCurrent:AlarmRunningID:');
	}
	
	my $isStream = 0;
	my $oldMaster = !SONOS_Client_Data_Retreive($udn, 'reading', 'IsMaster', 0);
	
	# Das nächste nur machen, wenn dieses Event die Track-Informationen auch enthält
	if ($properties{LastChangeDecoded} =~ m/<(AVTransportURI|TransportState) val=".*?"\/>/i) {
		# PlayMode ermitteln
		my $currentPlayMode = 'NORMAL';
		$currentPlayMode = $1 if ($properties{LastChangeDecoded} =~ m/<CurrentPlayMode.*?val="(.*?)".*?\/>/i);
		my ($shuffle, $repeat, $repeatOne) = SONOS_GetShuffleRepeatStates($currentPlayMode);
		SONOS_Client_Notifier('SetCurrent:Shuffle:1') if ($shuffle);
		SONOS_Client_Notifier('SetCurrent:Repeat:1') if ($repeat);
		SONOS_Client_Notifier('SetCurrent:RepeatOne:1') if ($repeatOne);
		
		# CrossfadeMode ermitteln
		SONOS_Client_Notifier('SetCurrent:CrossfadeMode:'.$1) if ($properties{LastChangeDecoded} =~ m/<CurrentCrossfadeMode.*?val="(\d+)".*?\/>/i);
		
		# Anzahl Tracknumber ermitteln
		SONOS_Client_Notifier('SetCurrent:NumberOfTracks:'.decode_entities($1)) if ($properties{LastChangeDecoded} =~ m/<NumberOfTracks val="(.*?)"\/>/i);
		
		# Current Tracknumber ermitteln
		if ($properties{LastChangeDecoded} =~ m/<CurrentTrack val="(.*?)"\/>/i) {
			SONOS_Client_Notifier('SetCurrent:Track:'.decode_entities($1));
			
			# Für die Bookmarkverwaltung ablegen
			$SONOS_BookmarkSpeicher{OldTracks}{$udn} = decode_entities($1);
		}
		
		# Current TrackURI ermitteln
		my $currentTrackURI = SONOS_GetURIFromQueueValue($1) if ($properties{LastChangeDecoded} =~ m/<CurrentTrackURI val="(.*?)"\/>/i);
		$currentTrackURI =~ s/&apos;/'/gi;
		SONOS_Client_Notifier('SetCurrent:TrackURI:'.$currentTrackURI);
		# Für die Bookmarkverwaltung ablegen
		$SONOS_BookmarkSpeicher{OldTrackURIs}{$udn} = $currentTrackURI;
		
		my $enqueuedTransportMetaData = decode_entities($1) if ($properties{LastChangeDecoded} =~ m/<r:EnqueuedTransportURIMetaData val="(.*?)"\/>/i);
		
		# Wenn es ein Spotify-Track ist, dann den Benutzernamen sichern, damit man diesen beim nächsten Export zur Verfügung hat
		if ($currentTrackURI =~ m/^x-sonos-spotify:/i) {
			SONOS_Client_Notifier('ReadingsSingleUpdateIfChangedNoTrigger:undef:UserID_Spotify:'.SONOS_URI_Escape($1)) if ($enqueuedTransportMetaData =~ m/<desc .*?>(SA_.*?)<\/desc>/i);
		}
		
		# Wenn es ein Napster/Rhapsody-Track ist, dann den Benutzernamen sichern, damit man diesen beim nächsten Export zur Verfügung hat
		if ($currentTrackURI =~ m/^npsdy:/i) {
			SONOS_Client_Notifier('ReadingsSingleUpdateIfChangedNoTrigger:undef:UserID_Napster:'.SONOS_URI_Escape($1)) if ($enqueuedTransportMetaData =~ m/<desc .*?>(SA_.*?)<\/desc>/i);
		}
		
		# (Wenn möglich) Aktuell abgespielten Favoriten ermitteln...
		my $enqueuedTransportURI = decode_entities($1) if ($properties{LastChangeDecoded} =~ m/<r:EnqueuedTransportURI val="(.*?)"\/>/i);
		$enqueuedTransportURI = "" if (!defined($enqueuedTransportURI));
		SONOS_Client_Notifier('SetCurrent:EnqueuedTransportURI:'.decode_entities($enqueuedTransportURI));
		SONOS_Client_Notifier('SetCurrent:EnqueuedTransportHandle:'.decode_entities($enqueuedTransportURI).'|'.$enqueuedTransportMetaData);
		if ($enqueuedTransportMetaData =~ m/<dc:title>(.*?)<\/dc:title>/) {
			SONOS_Log $udn, 5, 'UTF8-Decode-Title1: '.$1;
			my $text = $1;
			eval { 
				$text = Encode::decode('UTF-8', $text, Encode::FB_CROAK);
			};
			eval {
				SONOS_Log $udn, 5, 'UTF8-Decode-Title2: '.$text;
				$text = Encode::decode('UTF-8', $text, Encode::FB_CROAK);
			};
			if ($@) {
				SONOS_Log $udn, 5, 'UTF8-Decode: '.$@;
			}
			SONOS_Log $udn, 5, 'UTF8-Decode-Title3: '.$text;
			SONOS_Client_Notifier('SetCurrent:Source:'.Encode::encode('UTF-8', $text));
		}
		
		# Current Trackdauer ermitteln
		if ($properties{LastChangeDecoded} =~ m/<CurrentTrackDuration val="(.*?)"\/>/i) {
			SONOS_Client_Notifier('SetCurrent:TrackDuration:'.decode_entities($1));
			SONOS_Client_Notifier('SetCurrent:TrackDurationSec:'.SONOS_GetTimeSeconds(decode_entities($1)));
			$SONOS_BookmarkSpeicher{OldTrackDurations}{$udn} = SONOS_GetTimeSeconds(decode_entities($1));
		}
		
		# Current Track Metadaten ermitteln
		my $currentTrackMetaData = decode_entities($1) if ($properties{LastChangeDecoded} =~ m/<CurrentTrackMetaData val="(.*?)"\/>/is);
		SONOS_Log $udn, 4, 'Transport-Event: CurrentTrackMetaData: '.$currentTrackMetaData;
		SONOS_Client_Notifier('SetCurrent:TrackHandle:'.$currentTrackURI.'|'.$currentTrackMetaData);
		
		# Cover herunterladen (Infos dazu in den Track Metadaten)
		my $tempURIground = decode_entities($currentTrackMetaData);
		#$tempURIground =~ s/%25/%/ig;
		
		my $tempURI = '';
		$tempURI = ($1) if ($tempURIground =~ m/<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>/i);
		# Wenn in der URI bereits ein kompletter Pfad drinsteht, dann diese Basis verwenden (passiert bei Wiedergabe vom iPad z.B.)
		if ($tempURI =~ m/^(http:\/\/.*?\/)(.*)/) {
			$groundURL = $1;
			$tempURI = $2;
		}
		SONOS_Client_Notifier('ProcessCover:'.$udn.':0:'.$tempURI.':'.$groundURL);
		
		# Auch hier den XML-Parser verhindern, und alles per regulärem Ausdruck ermitteln...
		if ($currentTrackMetaData =~ m/<dc:title>x-(sonosapi|rincon)-(stream|mp3radio):.*?<\/dc:title>/) {
			# Wenn es ein Stream ist, dann muss da was anderes erkannt werden
			SONOS_Log $udn, 4, "Transport-Event: Stream erkannt!";
			SONOS_Client_Notifier('SetCurrent:StreamAudio:1');
			$isStream = 1;
			
			# Sender ermitteln (per SOAP-Request an den SonosPlayer)
			if ($service->controlProxy()->GetMediaInfo(0)->getValue('CurrentURIMetaData') =~ m/<dc:title>(.*?)<\/dc:title>/i) {
				SONOS_Client_Notifier('SetCurrent:Sender:'.$1);
				
				my ($trackProvider, $trackProviderRoundURL, $trackProviderQuadraticURL) = SONOS_GetTrackProvider($currentTrackURI, $1);
				SONOS_Log undef, 4, 'Trackprovider for Sender "'.$trackProvider.'" ~ RoundIcon: '.$trackProviderRoundURL.' ~ QuadraticIcon: '.$trackProviderQuadraticURL;
				SONOS_Client_Notifier('SetCurrent:TrackProvider:'.$trackProvider);
				SONOS_Client_Notifier('SetCurrent:TrackProviderIconRoundURL:'.$trackProviderRoundURL);
				SONOS_Client_Notifier('SetCurrent:TrackProviderIconQuadraticURL:'.$trackProviderQuadraticURL);
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = $1;
			}
			
			# Sender-Läuft ermitteln
			SONOS_Client_Notifier('SetCurrent:SenderCurrent:'.$1) if ($currentTrackMetaData =~ m/<r:radioShowMd>(.*?),p\d{6}<\/r:radioShowMd>/i);
		  
			# Sendungs-Informationen ermitteln
			my $currentValue = decode_entities($1) if ($currentTrackMetaData =~ m/<r:streamContent>(.*?)<\/r:streamContent>/i);
			$currentValue = '' if (!defined($currentValue));
			# Wenn hier eine Buffering- oder Connecting-Konstante zurückkommt, dann durch vernünftigen Text ersetzen
			$currentValue = 'Verbindung herstellen...' if ($currentValue eq 'ZPSTR_CONNECTING');
			$currentValue = 'Wird gestartet...' if ($currentValue eq 'ZPSTR_BUFFERING');
			# Wenn hier RTL.it seine Infos liefert, diese zurechtschnippeln...
			$currentValue = '' if ($currentValue eq '<songInfo />');
			if ($currentValue =~ m/<class>Music<\/class>.*?<mus_art_name>(.*?)<\/mus_art_name>/i) {
				$currentValue = $1;
				$currentValue =~ s/\[e\]amp\[p\]/&/ig;
			}
			SONOS_Client_Notifier('SetCurrent:SenderInfo:'.encode_entities($currentValue));
			
			$SONOS_BookmarkSpeicher{OldTrackDurations}{$udn} = 0;
		} else {
			SONOS_Log $udn, 4, "Transport-Event: Normal erkannt!";
			SONOS_Client_Notifier('SetCurrent:NormalAudio:1');
			
			my $currentArtist = '';
			my $currentTitle = '';
			if ($currentTrackURI =~ m/x-rincon:(RINCON_[\dA-Z]+)/) {
				# Gruppenwiedergabe feststellen, und dann andere Informationen anzeigen
				SONOS_Client_Notifier('SetCurrent:Album:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1));
				SONOS_Client_Notifier('SetCurrent:Title:Gruppenwiedergabe');
				SONOS_Client_Notifier('SetCurrent:Artist:');
				
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = 'Gruppenwiedergabe von '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1);
			} elsif ($currentTrackURI =~ m/x-rincon-stream:(RINCON_[\dA-Z]+)/) {
				# LineIn-Wiedergabe feststellen, und dann andere Informationen anzeigen
				SONOS_Client_Notifier('SetCurrent:Album:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1));
				
				# Fallback
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1);
				
				if ($currentTrackMetaData =~ m/<dc:title>(.*?)<\/dc:title>/i) {
					SONOS_Client_Notifier('SetCurrent:Title:'.SONOS_replaceSpecialStringCharacters(decode_entities($1)));
					$currentTitle = $1;
					
					$SONOS_BookmarkSpeicher{OldTitles}{$udn} = $1.' von '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1);
				}
				SONOS_Client_Notifier('SetCurrent:Artist:');
				
				SONOS_Client_Notifier('ProcessCover:'.$udn.':0:/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/input_default.jpg:');
			} elsif ($currentTrackURI =~ m/x-sonos-dock:(RINCON_[\dA-Z]+)/) {
				# Dock-Wiedergabe feststellen, und dann andere Informationen anzeigen
				SONOS_Client_Notifier('SetCurrent:Album:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'currentAlbum', SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1)));
				my $tmpTitle = SONOS_replaceSpecialStringCharacters(decode_entities($1)) if ($currentTrackMetaData =~ m/<dc:title>(.*?)<\/dc:title>/i);
				$tmpTitle = '' if (!defined($tmpTitle));
				SONOS_Client_Notifier('SetCurrent:Title:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'currentTitle', $tmpTitle));
				$currentTitle = $tmpTitle;
				SONOS_Client_Notifier('SetCurrent:Artist:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'currentArtist', ''));
				
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'currentTitle', $tmpTitle);
				
				SONOS_Client_Notifier('ProcessCover:'.$udn.':0:/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/input_dock.jpg:');
			} elsif ($currentTrackURI =~ m/x-sonos-htastream:(RINCON_[\dA-Z]+):spdif/) {
				# LineIn-Wiedergabe der Playbar feststellen, und dann andere Informationen anzeigen
				SONOS_Client_Notifier('SetCurrent:Album:'.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1));
				SONOS_Client_Notifier('SetCurrent:Title:SPDIF-Wiedergabe');
				SONOS_Client_Notifier('SetCurrent:Artist:');
				
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = 'SPDIF-Wiedergabe von '.SONOS_Client_Data_Retreive($1.'_MR', 'reading', 'roomName', $1);
				
				SONOS_Client_Notifier('ProcessCover:'.$udn.':0:/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/cover/input_tv.jpg:');
			} else {
				# Titel ermitteln
				if ($currentTrackMetaData =~ m/<dc:title>(.*?)<\/dc:title>/i) {
					SONOS_Client_Notifier('SetCurrent:Title:'.$1);
					$currentTitle = $1;
				}
				
				# Interpret ermitteln
				if ($currentTrackMetaData =~ m/<dc:creator>(.*?)<\/dc:creator>/i) {
					$currentArtist = decode_entities($1);
					SONOS_Client_Notifier('SetCurrent:Artist:'.encode_entities($currentArtist));
				}
				
				# Album ermitteln
				SONOS_Client_Notifier('SetCurrent:Album:'.$1) if ($currentTrackMetaData =~ m/<upnp:album>(.*?)<\/upnp:album>/i);
				
				$SONOS_BookmarkSpeicher{OldTitles}{$udn} = '('.$currentArtist.') '.$currentTitle;
			}
			
			my ($trackProvider, $trackProviderRoundURL, $trackProviderQuadraticURL) = SONOS_GetTrackProvider($currentTrackURI, $currentTitle);
			SONOS_Log undef, 4, 'Trackprovider "'.$trackProvider.'" ~ RoundIcon: '.$trackProviderRoundURL.' ~ QuadraticIcon: '.$trackProviderQuadraticURL;
			SONOS_Client_Notifier('SetCurrent:TrackProvider:'.$trackProvider);
			SONOS_Client_Notifier('SetCurrent:TrackProviderIconRoundURL:'.$trackProviderRoundURL);
			SONOS_Client_Notifier('SetCurrent:TrackProviderIconQuadraticURL:'.$trackProviderQuadraticURL);
			$SONOS_BookmarkSpeicher{OldTitles}{$udn} = $1;
			
			# Original Tracknumber ermitteln
			SONOS_Client_Notifier('SetCurrent:OriginalTrackNumber:'.decode_entities($1)) if ($currentTrackMetaData =~ m/<upnp:originalTrackNumber>(.*?)<\/upnp:originalTrackNumber>/i);
			
			# Album Artist ermitteln
			my $currentValue = decode_entities($1) if ($currentTrackMetaData =~ m/<r:albumArtist>(.*?)<\/r:albumArtist>/i);
			$currentValue = $currentArtist if (!defined($currentValue) || ($currentValue eq ''));
			SONOS_Client_Notifier('SetCurrent:AlbumArtist:'.encode_entities($currentValue));
		}
		
		# Next Track Metadaten ermitteln
		my $nextTrackMetaData = decode_entities($1) if ($properties{LastChangeDecoded} =~ m/<r:NextTrackMetaData val="(.*?)"\/>/i);
		SONOS_Log $udn, 4, 'Transport-Event: NextTrackMetaData: '.$nextTrackMetaData;
		
		SONOS_Client_Notifier('SetCurrent:nextTrackDuration:'.decode_entities($1)) if ($nextTrackMetaData =~ m/<res.*?duration="(.*?)".*?>/i);
		SONOS_Client_Notifier('SetCurrent:nextTrackDurationSec:'.SONOS_GetTimeSeconds(decode_entities($1))) if ($nextTrackMetaData =~ m/<res.*?duration="(.*?)".*?>/i);
		
		if ($properties{LastChangeDecoded} =~ m/<r:NextTrackURI val="(.*?)"\/>/i) {
			my $tmp = SONOS_GetURIFromQueueValue($1);
			$tmp =~ s/&apos;/'/gi;
			SONOS_Client_Notifier('SetCurrent:nextTrackURI:'.$tmp);
			SONOS_Client_Notifier('SetCurrent:nextTrackHandle:'.$tmp.'|'.$nextTrackMetaData);
			
			my ($trackProvider, $trackProviderRoundURL, $trackProviderQuadraticURL) = SONOS_GetTrackProvider($tmp);
			SONOS_Log undef, 4, 'NextTrackprovider "'.$trackProvider.'" ~ RoundIcon: '.$trackProviderRoundURL.' ~ QuadraticIcon: '.$trackProviderQuadraticURL;
			SONOS_Client_Notifier('SetCurrent:nextTrackProvider:'.$trackProvider);
			SONOS_Client_Notifier('SetCurrent:nextTrackProviderIconRoundURL:'.$trackProviderRoundURL);
			SONOS_Client_Notifier('SetCurrent:nextTrackProviderIconQuadraticURL:'.$trackProviderQuadraticURL);

		}
		
		$tempURIground = decode_entities($nextTrackMetaData);
		#$tempURIground =~ s/%25/%/ig;
		
		$tempURI = '';
		$tempURI = ($1) if ($tempURIground =~ m/<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>/i);
		SONOS_Client_Notifier('ProcessCover:'.$udn.':1:'.$tempURI.':'.$groundURL);
		
		SONOS_Client_Notifier('SetCurrent:nextTitle:'.$1) if ($nextTrackMetaData =~ m/<dc:title>(.*?)<\/dc:title>/i);
		
		SONOS_Client_Notifier('SetCurrent:nextArtist:'.$1) if ($nextTrackMetaData =~ m/<dc:creator>(.*?)<\/dc:creator>/i);
		
		SONOS_Client_Notifier('SetCurrent:nextAlbum:'.$1) if ($nextTrackMetaData =~ m/<upnp:album>(.*?)<\/upnp:album>/i);
		
		SONOS_Client_Notifier('SetCurrent:nextAlbumArtist:'.$1) if ($nextTrackMetaData =~ m/<r:albumArtist>(.*?)<\/r:albumArtist>/i);
		
		SONOS_Client_Notifier('SetCurrent:nextOriginalTrackNumber:'.decode_entities($1)) if ($nextTrackMetaData =~ m/<upnp:originalTrackNumber>(.*?)<\/upnp:originalTrackNumber>/i);
	} else {
		SONOS_Log undef, 4, 'No trackinformations found in data: '.$properties{LastChangeDecoded};
	}
	
	# Current Trackposition ermitteln (durch Abfrage beim Player, bzw. bei Streams statisch)
	if ($isStream) {
		SONOS_Client_Notifier('SetCurrent:TrackPosition:0:00:00');
		SONOS_Client_Notifier('SetCurrent:TrackPositionSec:0');
	} else {
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			my $trackPosition = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('RelTime');
			if ($trackPosition !~ /\d+:\d+:\d+/i) { # e.g. NOT_IMPLEMENTED
				$trackPosition = '0:00:00';
			}
			SONOS_Client_Notifier('SetCurrent:TrackPosition:'.$trackPosition);
			SONOS_Client_Notifier('SetCurrent:TrackPositionSec:'.SONOS_GetTimeSeconds($trackPosition));
			$SONOS_BookmarkSpeicher{OldTrackPositions}{$udn} = SONOS_GetTimeSeconds($trackPosition);
			$SONOS_BookmarkSpeicher{OldTimestamp}{$udn} = scalar(gettimeofday()) - SONOS_GetTimeSeconds($trackPosition);
		}
	}
	
	# Neue Bookmarks aktualisieren
	SONOS_RefreshCurrentBookmarkQueueValues($udn);
	
	# Trigger/Transfer the whole bunch and generate InfoSummarize
	SONOS_Client_Notifier('CurrentBulkUpdate:'.$udn);
	
	
	# (Etwaige) Neue ZonenTopologie ermitteln und propagieren...
	if (SONOS_CheckProxyObject($udn, $SONOS_ZoneGroupTopologyProxy{$udn})) {
		my $zoneGroupState = $SONOS_ZoneGroupTopologyProxy{$udn}->GetZoneGroupState()->getValue('ZoneGroupState');
		
		my ($masterPlayerUDN, $masterSlavePlayer) = SONOS_AnalyzeTopologyForFindingMastersSlaves($udnShort, $zoneGroupState);
		my $masterPlayer = SONOS_Client_Data_Retreive($masterPlayerUDN, 'def', 'NAME', '~~~DELETE~~~');
		
		# Wenn der MasterPlayer unbekannt ist, dann hier überspringen...
		if ($masterPlayer ne '~~~DELETE~~~') {
			SONOS_AnalyzeTopologyForMasterPlayer($zoneGroupState);
			
			SONOS_Log undef, 5, 'Player: '.$name.' ~ Master: '.$masterPlayer.' ~ Slaves: '.SONOS_Client_Data_Retreive($masterPlayerUDN, 'reading', 'SlavePlayer', '');
			
			# Wenn alle Player als Sonos-Devices vorhanden und damit bekannt sind...
			if (SONOS_Client_Data_Retreive($masterPlayerUDN, 'reading', 'SlavePlayer', '') !~ /~~~DELETE~~~/) {
				# Masterplayer zum Propagieren beauftragen, wenn es einen echten Master gibt... 
				if ($masterPlayer ne $name) {
					# Wir sind gerade der Slaveplayer, dann auch nur uns aktualisieren lassen...
					SONOS_Client_Notifier('PropagateTitleInformationsToSlave:'.$masterPlayer.':'.$name);
				} else {
					# Wir sind gerade der Masterplayer, dann alle Informationen an alle Slaveplayer weiterreichen
					SONOS_Client_Notifier('PropagateTitleInformationsToSlaves:'.$name);
				}
			}
		}
	}
	
	# Wenn der SleepTimer nach einer Aktion gelöscht werden soll...
	if ($affectSleeptimer && SONOS_Client_Data_Retreive($udn, 'attr', 'stopSleeptimerInAction', 0) && !SONOS_Client_Data_Retreive($udn, 'attr', 'saveSleeptimerInAction', 0)) {
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			$SONOS_AVTransportControlProxy{$udn}->ConfigureSleepTimer(0, '');
		}
	}
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of Transport-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "Transport-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_RenderingCallback - Rendering-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_RenderingCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'Rendering-Event receive error: SonosPlayer not found; Searching for \''.$service->eventSubURL.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "Rendering-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received Rendering-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:RenderingControl:1') {
		SONOS_Log $udn, 1, 'Rendering-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	# Check if the Variable called LastChange exists
	if (not defined($properties{LastChange})) {
		SONOS_Log $udn, 1, 'Rendering-Event receive error: Property \'LastChange\' does not exists!';
		return;
	}
  
	SONOS_Log $udn, 4, "Rendering-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	# Die Daten wurden uns HTML-Kodiert übermittelt... diese Entities nun in Zeichen umwandeln, da sonst die regulären Ausdrücke ziemlich unleserlich werden...
	$properties{LastChangeDecoded} = decode_entities($properties{LastChange});
	
	SONOS_Log $udn, 4, 'Rendering-Event: LastChange: '.$properties{LastChangeDecoded};
	my $generateVolumeEvent = SONOS_Client_Data_Retreive($udn, 'attr', 'generateVolumeEvent', 0);
	
	# Mute?
	my $mute = SONOS_Client_Data_Retreive($udn, 'reading', 'Mute', 0);
	if ($properties{LastChangeDecoded} =~ m/<Mute.*?channel="Master".*?val="(\d+)".*?\/>/i) {
		SONOS_AddToButtonQueue($udn, 'M') if ($1 ne $mute);
		$mute = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Mute', $mute);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Mute', $mute);
		}
	}
	
	# Headphone?
	my $headphoneConnected = SONOS_Client_Data_Retreive($udn, 'reading', 'HeadphoneConnected', 0);
	if ($properties{LastChangeDecoded} =~ m/<HeadphoneConnected.*?val="(\d+)".*?\/>/i) {
		SONOS_AddToButtonQueue($udn, 'H') if ($1 ne $headphoneConnected);
		$headphoneConnected = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'HeadphoneConnected', $headphoneConnected);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'HeadphoneConnected', $headphoneConnected);
		}
	}
		
	
	# Balance ermitteln
	my $balance = SONOS_Client_Data_Retreive($udn, 'reading', 'Balance', 0);
	if ($properties{LastChangeDecoded} =~ m/<Volume.*?channel="LF".*?val="(\d+)".*?\/>/i) {
		my $volumeLeft = $1;
		my $volumeRight = $1 if ($properties{LastChangeDecoded} =~ m/<Volume.*?channel="RF".*?val="(\d+)".*?\/>/i);
		$balance = (-$volumeLeft) + $volumeRight if ($volumeLeft && $volumeRight);
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Balance', $balance);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Balance', $balance);
		}
	}
	
	
	# Volume ermitteln
	my $currentVolume = SONOS_Client_Data_Retreive($udn, 'reading', 'Volume', 0);
	if ($properties{LastChangeDecoded} =~ m/<Volume.*?channel="Master".*?val="(\d+)".*?\/>/i) {
		SONOS_AddToButtonQueue($udn, 'U') if ($1 > $currentVolume);
		SONOS_AddToButtonQueue($udn, 'D') if ($1 < $currentVolume);
		$currentVolume = $1 ;
		
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Volume', $currentVolume);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Volume', $currentVolume);
		}
	}
	
	# Loudness?
	my $loudness = SONOS_Client_Data_Retreive($udn, 'reading', 'Loudness', 0);
	if ($properties{LastChangeDecoded} =~ m/<Loudness.*?channel="Master".*?val="(\d+)".*?\/>/i) {
		$loudness = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Loudness', $loudness);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Loudness', $loudness);
		}
	}
	
	# Bass?
	my $bass = SONOS_Client_Data_Retreive($udn, 'reading', 'Bass', 0);
	if ($properties{LastChangeDecoded} =~ m/<Bass.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$bass = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Bass', $bass);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Bass', $bass);
		}
	}
	
	# Treble?
	my $treble = SONOS_Client_Data_Retreive($udn, 'reading', 'Treble', 0);
	if ($properties{LastChangeDecoded} =~ m/<Treble.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$treble = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'Treble', $treble);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'Treble', $treble);
		}
	}
	
	# TruePlay?
	my $trueplay = SONOS_Client_Data_Retreive($udn, 'reading', 'TruePlay', 0);
	if ($properties{LastChangeDecoded} =~ m/<SonarEnabled.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$trueplay = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'TruePlay', $trueplay);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'TruePlay', $trueplay);
		}
	}
	
	# SurroundEnable?
	my $surroundEnable = SONOS_Client_Data_Retreive($udn, 'reading', 'SurroundEnable', 0);
	if ($properties{LastChangeDecoded} =~ m/<SurroundEnable.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$surroundEnable = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SurroundEnable', $surroundEnable);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'SurroundEnable', $surroundEnable);
		}
	}
	
	# SurroundLevel?
	my $surroundLevel = SONOS_Client_Data_Retreive($udn, 'reading', 'SurroundLevel', 0);
	if ($properties{LastChangeDecoded} =~ m/<SurroundLevel.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$surroundLevel = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SurroundLevel', $surroundLevel);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'SurroundLevel', $surroundLevel);
		}
	}
	
	# SubEnable?
	my $subEnable = SONOS_Client_Data_Retreive($udn, 'reading', 'SubEnable', 0);
	if ($properties{LastChangeDecoded} =~ m/<SubEnable.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$subEnable = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SubEnable', $subEnable);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'SubEnable', $subEnable);
		}
	}
	
	# SubGain?
	my $subGain = SONOS_Client_Data_Retreive($udn, 'reading', 'SubGain', 0);
	if ($properties{LastChangeDecoded} =~ m/<SubGain.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$subGain = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SubGain', $subGain);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'SubGain', $subGain);
		}
	}
	
	# SubPolarity?
	my $subPolarity = SONOS_Client_Data_Retreive($udn, 'reading', 'SubPolarity', 0);
	if ($properties{LastChangeDecoded} =~ m/<SubPolarity.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$subPolarity = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'SubPolarity', $subPolarity);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'SubPolarity', $subPolarity);
		}
	}
	
	# AudioDelay?
	my $audioDelay = SONOS_Client_Data_Retreive($udn, 'reading', 'AudioDelay', 0);
	if ($properties{LastChangeDecoded} =~ m/<AudioDelay.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$audioDelay = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'AudioDelay', $audioDelay);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'AudioDelay', $audioDelay);
		}
	}
	
	# AudioDelayLeftRear?
	my $audioDelayLeftRear = SONOS_Client_Data_Retreive($udn, 'reading', 'AudioDelayLeftRear', 0);
	if ($properties{LastChangeDecoded} =~ m/<AudioDelayLeftRear.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$audioDelayLeftRear = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'AudioDelayLeftRear', $audioDelayLeftRear);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'AudioDelayLeftRear', $audioDelayLeftRear);
		}
	}
	
	# AudioDelayRightRear?
	my $audioDelayRightRear = SONOS_Client_Data_Retreive($udn, 'reading', 'AudioDelayRightRear', 0);
	if ($properties{LastChangeDecoded} =~ m/<AudioDelayRightRear.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$audioDelayRightRear = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'AudioDelayRightRear', $audioDelayRightRear);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'AudioDelayRightRear', $audioDelayRightRear);
		}
	}
	
	# NightMode?
	my $nightMode = SONOS_Client_Data_Retreive($udn, 'reading', 'NightMode', 0);
	if ($properties{LastChangeDecoded} =~ m/<NightMode.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$nightMode = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'NightMode', $nightMode);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'NightMode', $nightMode);
		}
	}
	
	# DialogLevel?
	my $dialogLevel = SONOS_Client_Data_Retreive($udn, 'reading', 'DialogLevel', 0);
	if ($properties{LastChangeDecoded} =~ m/<DialogLevel.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$dialogLevel = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'DialogLevel', $dialogLevel);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'DialogLevel', $dialogLevel);
		}
	}
	
	# OutputFixed?
	my $outputFixed = SONOS_Client_Data_Retreive($udn, 'reading', 'OutputFixed', 0);
	if ($properties{LastChangeDecoded} =~ m/<OutputFixed.*?val="([-]{0,1}\d+)".*?\/>/i) {
		$outputFixed = $1;
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'OutputFixed', $outputFixed);
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'OutputFixed', $outputFixed);
		}
	}
	
	
	SONOS_Log $udn, 4, "Rendering-Event: Current Values for '$name' ~ Volume: $currentVolume, HeadphoneConnected: $headphoneConnected, Bass: $bass, Treble: $treble, Balance: $balance, Loudness: $loudness, Mute: $mute";
	
	# Ensures the defined volume-borders
	if (SONOS_EnsureMinMaxVolumes($udn)) {
		# Variablen initialisieren
		SONOS_Client_Notifier('GetReadingsToCurrentHash:'.$udn.':0');
		SONOS_Client_Notifier('CurrentBulkUpdate:'.$udn);
	}
	
	# ButtonQueue prüfen
	SONOS_CheckButtonQueue($udn);
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of Rendering-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "Rendering-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_EnsureMinMaxVolumes - Ensures the defined volume-borders
#
########################################################################################
sub SONOS_EnsureMinMaxVolumes($) {
	my ($udn) = @_;
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	my $currentVolume = SONOS_Client_Data_Retreive($udn, 'reading', 'Volume', 0);
	my $headphoneConnected = SONOS_Client_Data_Retreive($udn, 'reading', 'HeadphoneConnected', 0);
	my $mute = SONOS_Client_Data_Retreive($udn, 'reading', 'Mute', 0);
	
	# Grenzen passend zum verwendeten Tonausgang ermitteln
	# Untere Grenze ermitteln
	my $key = 'minVolume'.($headphoneConnected ? 'Headphone' : '');
	my $minVolume = SONOS_Client_Data_Retreive($udn, 'attr', $key, 0);
	
	# Obere Grenze ermitteln
	$key = 'maxVolume'.($headphoneConnected ? 'Headphone' : '');
	my $maxVolume = SONOS_Client_Data_Retreive($udn, 'attr', $key, 100);
	
	SONOS_Log $udn, 4, "Rendering-Event: Current Borders for '$name' ~ minVolume: $minVolume, maxVolume: $maxVolume";
	
	
	# Fehlerhafte Attributangaben?
	if ($minVolume > $maxVolume) {
		SONOS_Log $udn, 0, 'Min-/MaxVolume check Error: MinVolume('.$minVolume.') > MaxVolume('.$maxVolume.'), using Headphones: '.$headphoneConnected.'!';
		return;
	}
	
	# Prüfungen und Aktualisierungen durchführen
	if (!$mute && ($minVolume > $currentVolume)) {
		# Grenzen prüfen: Zu Leise
		SONOS_Log $udn, 4, 'Volume to Low. Correct it to "'.$minVolume.'"';
		
		$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'Master', $minVolume);
	} elsif (!$mute && ($currentVolume > $maxVolume)) {
		# Grenzen prüfen: Zu Laut
		SONOS_Log $udn, 4, 'Volume to High. Correct it to "'.$maxVolume.'"'; 
		
		$SONOS_RenderingControlProxy{$udn}->SetVolume(0, 'Master', $maxVolume);
	} else {
		return 0;
	}
	
	return 1;
}

########################################################################################
#
#  SONOS_GroupRenderingCallback - GroupRendering-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_GroupRenderingCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'GroupRendering-Event receive error: SonosPlayer not found; Searching for \''.$service->eventSubURL.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "GroupRendering-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received GroupRendering-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:GroupRenderingControl:1') {
		SONOS_Log $udn, 1, 'GroupRendering-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "GroupRendering-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	my $generateVolumeEvent = SONOS_Client_Data_Retreive($udn, 'attr', 'generateVolumeEvent', 0);
	
	# GroupVolume...
	my $groupVolume = SONOS_Client_Data_Retreive($udn, 'reading', 'GroupVolume', '~~');
	if (defined($properties{GroupVolume}) && ($properties{GroupVolume} ne $groupVolume)) {
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'GroupVolume', $properties{GroupVolume});
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'GroupVolume', $properties{GroupVolume});
		}
	}
	
	# GroupMute...
	my $groupMute = SONOS_Client_Data_Retreive($udn, 'reading', 'GroupMute', '~~');
	if (defined($properties{GroupMute}) && ($properties{GroupMute} ne $groupMute)) {
		if ($generateVolumeEvent) {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'GroupMute', $properties{GroupMute});
		} else {
			SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChangedNoTrigger', $udn, 'GroupMute', $properties{GroupMute});
		}
	}
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of GroupRendering-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "GroupRendering-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_ContentDirectoryCallback - ContentDirectory-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_ContentDirectoryCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'ContentDirectory-Event receive error: SonosPlayer not found; Searching for \''.$service->eventSubURL.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "ContentDirectory-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received ContentDirectory-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:ContentDirectory:1') {
		SONOS_Log $udn, 1, 'ContentDirectory-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "ContentDirectory-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	#FavoritesUpdateID...
	if (defined($properties{FavoritesUpdateID})) {
		my $containerUpdateIDs = '';
		$containerUpdateIDs = $properties{ContainerUpdateIDs} if ($properties{ContainerUpdateIDs});
		
		my $favouritesUpdateID = $1 if ($containerUpdateIDs =~ m/FV:2,\d+?/i);
		my $radiosUpdateID = $1 if ($containerUpdateIDs =~ m/R:0,\d+?/i);
		
		# Wenn beide nicht geliefert wurden, dann beide setzen...
		$containerUpdateIDs = '' if (!defined($favouritesUpdateID) && !defined($radiosUpdateID));
		
		if (defined($favouritesUpdateID) || ($containerUpdateIDs eq '')) {
			# Wenn eine neue Favoritenversion vorliegt, und eine automatische Aktualisierung gewünscht ist...
			if (($properties{FavoritesUpdateID} ne SONOS_Client_Data_Retreive($udn, 'reading', 'FavouritesVersion', '~~')) 
				&& SONOS_Client_Data_Retreive('undef', 'attr', 'getFavouritesListAtNewVersion', 0)
				&& SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				SONOS_GetBrowseStructuredResult($udn, 'FV:2', 0, 'getFavouritesWithCovers');
			}
			
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'FavouritesVersion', $properties{FavoritesUpdateID});
		}
		
		if (defined($radiosUpdateID) || ($containerUpdateIDs eq '')) {
			# Wenn eine neue Favoritenversion vorliegt, und eine automatische Aktualisierung gewünscht ist...
			if (($properties{FavoritesUpdateID} ne SONOS_Client_Data_Retreive($udn, 'reading', 'RadiosVersion', '~~')) 
				&& SONOS_Client_Data_Retreive('undef', 'attr', 'getRadiosListAtNewVersion', 0)
				&& SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				SONOS_GetBrowseStructuredResult($udn, 'R:0/0', 0, 'getRadiosWithCovers');
			}
			
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'RadiosVersion', $properties{FavoritesUpdateID});
		}
	}
	
	#SavedQueuesUpdateID...
	my $savedQueuesUpdateID = SONOS_Client_Data_Retreive($udn, 'reading', 'PlaylistsVersion', '~~');
	if (defined($properties{SavedQueuesUpdateID}) && ($properties{SavedQueuesUpdateID} ne $savedQueuesUpdateID)) {
		# Wenn eine neue Playlistversion vorliegt, und eine automatische Aktualisierung gewünscht ist...
		if (($properties{SavedQueuesUpdateID} ne SONOS_Client_Data_Retreive($udn, 'reading', 'PlaylistsVersion', '~~')) 
			&& SONOS_Client_Data_Retreive('undef', 'attr', 'getPlaylistsListAtNewVersion', 0)
			&& SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
			SONOS_GetBrowseStructuredResult($udn, 'SQ:', 0, 'getPlaylistsWithCovers', 0, 1);
		}
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'PlaylistsVersion', $properties{SavedQueuesUpdateID});
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
	
	#QueueUpdateID...
	if (defined($properties{ContainerUpdateIDs})) {
		my $oldVersion = SONOS_Client_Data_Retreive($udn, 'reading', 'QueueVersion', '~~');
		my $newVersion = '';
		$newVersion = $1 if ($properties{ContainerUpdateIDs} =~ m/Q:0,(\d+)/i);
		
		SONOS_Log $udn, 3, 'ContainerUpdateIDs: '.$properties{ContainerUpdateIDs};
		
		if ($newVersion && ($oldVersion ne $newVersion)) {
			# Wenn eine neue Queueversion vorliegt, und eine automatische Aktualisierung gewünscht ist...
			if (SONOS_Client_Data_Retreive('undef', 'attr', 'getQueueListAtNewVersion', 0)
				&& SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
				SONOS_GetQueueStructuredResult($udn, 0, 'getQueueWithCovers');
			}
			
			SONOS_Client_Data_Refresh('ReadingsSingleUpdate', $udn, 'QueueVersion', $newVersion);
			
			# Für die Queue-Bookmarkverarbeitung den Queue-Hash neu berechnen und u.U. auf anderen Titel springen...
			SONOS_CalculateQueueHash($udn);
		}
	}
	
	#ShareIndexInProgress
	my $shareIndexInProgress = SONOS_Client_Data_Retreive('undef', 'reading', 'ShareIndexInProgress', '~~');
	if (defined($properties{ShareIndexInProgress}) && ($properties{ShareIndexInProgress} ne $shareIndexInProgress)) {
		SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', 'undef', 'ShareIndexInProgress', $properties{ShareIndexInProgress});
	}
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of ContentDirectory-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "ContentDirectory-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_SaveBookmarkValues - Saves the current queue-values for Bookmarks
#
########################################################################################
sub SONOS_SaveBookmarkValues(;$$) {
	my ($gKey, $type) = @_;
	
	my $pathname = SONOS_Client_Data_Retreive('undef', 'attr', 'bookmarkSaveDir', '.');
	
	SONOS_Log undef, 4, 'Calling SONOS_SaveBookmarkValues("'.(defined($gKey) ? $gKey : 'undef').'", "'.(defined($type) ? $type : 'undef').'") ~ SaveDir: "'.$pathname.'"';
	
	my @types = ();
	if (defined($type) && ($type ne '')) {
		push(@types, $type);
	} else {
		@types = qw(Queue Title);
	}
	
	foreach my $type (@types) {
		my @groups = ();
		if (defined($gKey) && ($gKey ne '')) {
			push(@groups, $gKey);
		} else {
			my $hashList = \%SONOS_BookmarkTitleHash;
			$hashList = \%SONOS_BookmarkQueueHash if (lc($type) eq 'queue');
			
			foreach my $group (keys %{$hashList}) {
				push(@groups, $group);
			}
		}
		
		foreach my $group (@groups) {
			# ReadOnly-Gruppen niemals speichern
			next if ((lc($type) eq 'queue') && defined($SONOS_BookmarkQueueDefinition{$group}{ReadOnly}) && $SONOS_BookmarkQueueDefinition{$group}{ReadOnly});
			next if ((lc($type) ne 'queue') && defined($SONOS_BookmarkTitleDefinition{$group}{ReadOnly}) && $SONOS_BookmarkTitleDefinition{$group}{ReadOnly});
			
			my $filename;
			$filename = $pathname.'/SONOS_BookmarksPlaylists_'.$group.'.save' if (lc($type) eq 'queue');
			$filename = $pathname.'/SONOS_BookmarksTitles_'.$group.'.save' if (lc($type) ne 'queue');
			
			my $data;
			$data = $SONOS_BookmarkQueueHash{$group} if (lc($type) eq 'queue');
			$data = $SONOS_BookmarkTitleHash{$group} if (lc($type) ne 'queue');
			
			if (defined($data)) {
				eval {
					open FILE, '>'.$filename;
					binmode(FILE, ':encoding(utf-8)');
					print FILE SONOS_Dumper($data);
					close FILE;
					
					SONOS_Log undef, 3, 'Successfully saved '.$type.'-Bookmarks of group "'.$group.'" to file "'.$filename.'"!';
					SONOS_MakeSigHandlerReturnValue('undef', 'LastActionResult', 'SaveBookmarks: Success!');
				};
				if ($@) {
					SONOS_Log undef, 2, 'Error during saving '.$type.'-Bookmarks of group "'.$group.'" to file "'.$filename.'": '.$@;
					SONOS_MakeSigHandlerReturnValue('undef', 'LastActionResult', 'SaveBookmarks: Error! '.$@);
				}
			}
		}
	}
}

########################################################################################
#
#  SONOS_LoadBookmarkValues - Loads the current queue-values for Bookmarks
#
########################################################################################
sub SONOS_LoadBookmarkValues(;$$) {
	my ($gKey, $type) = @_;
	
	my $pathname = SONOS_Client_Data_Retreive('undef', 'attr', 'bookmarkSaveDir', '.');
	
	SONOS_Log undef, 4, 'Calling SONOS_LoadBookmarkValues("'.(defined($gKey) ? $gKey : 'undef').'", "'.(defined($type) ? $type : 'undef').'") ~ SaveDir: "'.$pathname.'"';
	
	my @types = ();
	if (defined($type) && ($type ne '')) {
		push(@types, $type);
	} else {
		@types = qw(Queue Title);
	}
	
	foreach my $type (@types) {
		my @groups = ();
		if (defined($gKey) && ($gKey ne '')) {
			push(@groups, $gKey);
		} else {
			my $hashList = \%SONOS_BookmarkTitleDefinition;
			$hashList = \%SONOS_BookmarkQueueDefinition if (lc($type) eq 'queue');
			
			foreach my $group (keys %{$hashList}) {
				push(@groups, $group);
			}
		}
		
		foreach my $group (@groups) {
			my $filename;
			$filename = $pathname.'/SONOS_BookmarksPlaylists_'.$group.'.save' if (lc($type) eq 'queue');
			$filename = $pathname.'/SONOS_BookmarksTitles_'.$group.'.save' if (lc($type) ne 'queue');
			
			eval {
				if (open FILE, '<'.$filename) {
					binmode(FILE, ':encoding(utf-8)');
					
					my $fileInhalt = '';
					while (<FILE>) {
						$fileInhalt .= $_;
					}
					close FILE;
					
					$SONOS_BookmarkQueueHash{$group} = eval($fileInhalt) if (lc($type) eq 'queue');
					$SONOS_BookmarkTitleHash{$group} = eval($fileInhalt) if (lc($type) ne 'queue');
					
					SONOS_Log undef, 3, 'Successfully loaded '.$type.'-Bookmarks of group "'.$group.'" from file "'.$filename.'"!';
					SONOS_MakeSigHandlerReturnValue('undef', 'LastActionResult', 'LoadBookmarks: Group "'.$group.'" Success!');
				}
			};
			if ($@) {
				SONOS_Log undef, 2, 'Error during loading '.$type.'-Bookmarks of group "'.$group.'" from file "'.$filename.'": '.$@;
				SONOS_MakeSigHandlerReturnValue('undef', 'LastActionResult', 'LoadBookmarks: Group "'.$group.'" Error! '.$@);
			}
		}
	}
}

########################################################################################
#
#  SONOS_CalculateQueueHash - Calculates the Hash over all Queue members and jumps to the saved position
#
########################################################################################
sub SONOS_CalculateQueueHash($) {
	my ($udn) = @_;
	
	SONOS_RefreshCurrentBookmarkQueueValues($udn);
	
	if (SONOS_CheckProxyObject($udn, $SONOS_ContentDirectoryControlProxy{$udn})) {
		my $result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', 0, 0, '');
		my $tmp = $result->getValue('Result');
		
		my $numberReturned = $result->getValue('NumberReturned');
		my $totalMatches = $result->getValue('TotalMatches');
		while ($numberReturned < $totalMatches) {
			$result = $SONOS_ContentDirectoryControlProxy{$udn}->Browse('Q:0', 'BrowseDirectChildren', '', $numberReturned, 0, '');
			$tmp .= $result->getValue('Result');
			
			$numberReturned += $result->getValue('NumberReturned');
			$totalMatches = $result->getValue('TotalMatches');
		}
		
		my $hashIn = $totalMatches.':';
		while ($tmp =~ m/<item id="(.*?)".*?>(.*?)<\/item>/ig) {
			my $item = $2;
			
			my $uri = $1 if ($item =~ m/<res.*?>(.*?)<\/res>/i);
			$uri =~ s/&apos;/'/gi;
			
			$hashIn .= $uri.':';
		}
		
		# Neuen Hashwert berechnen
		my $newHash = md5_hex($hashIn);
		
		# Werte aktualisieren
		SONOS_Client_Data_Refresh('ReadingsSingleUpdate', $udn, 'QueueHash', $newHash);
		
		# Aktuellen Track ermitteln...
		my $newTrack = 0;
		if (SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
			$newTrack = $SONOS_AVTransportControlProxy{$udn}->GetPositionInfo(0)->getValue('Track');
		}
		
		# Soll was getan werden?
		foreach my $gKey (SONOS_getBookmarkGroupKeys('Queue', $udn)) {
			if (defined($SONOS_BookmarkQueueHash{$gKey}{$newHash}) && SONOS_getBookmarkQueueIsRelevant($gKey, $newHash, scalar(gettimeofday()), $totalMatches)) {
				$newTrack = $SONOS_BookmarkQueueHash{$gKey}{$newHash}{Track};
				
				# Hier muss jetzt die gespeicherte Position angesprungen werden...
				if (($SONOS_BookmarkSpeicher{OldTracks}{$udn} != $newTrack) && SONOS_CheckProxyObject($udn, $SONOS_AVTransportControlProxy{$udn})) {
					my $result = $SONOS_AVTransportControlProxy{$udn}->Seek(0, 'TRACK_NR', $newTrack);
					
					SONOS_Log $udn, 3, 'Player "'.SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn).'" jumped to the bookmarked track #'.$newTrack.' (Group "'.$gKey.'") ~ Bookmarkdata: '.SONOS_Dumper($SONOS_BookmarkQueueHash{$gKey}{$newHash});
					
					SONOS_MakeSigHandlerReturnValue($udn, 'LastActionResult', 'JumpToTrack #'.$newTrack.': '.SONOS_UPnPAnswerMessage($result));
					
					last; # Nur den ersten gültigen Eintrag suchen/ausführen...
				}
			}
		}
		
		$SONOS_BookmarkSpeicher{OldTracks}{$udn} = $newTrack;
		$SONOS_BookmarkSpeicher{NumTracks}{$udn} = $totalMatches;
	}
}

########################################################################################
#
#  SONOS_RefreshCurrentBookmarkQueueValues - Saves the current queue-values for Bookmarks
#
########################################################################################
sub SONOS_RefreshCurrentBookmarkQueueValues($) {
	my ($udn) = @_;
	
	# Aktuelle Werte im Speicher sicherstellen...
	$SONOS_BookmarkSpeicher{OldTracks}{$udn} = 0 if (!defined($SONOS_BookmarkSpeicher{OldTracks}{$udn}));
	$SONOS_BookmarkSpeicher{NumTracks}{$udn} = 0 if (!defined($SONOS_BookmarkSpeicher{NumTracks}{$udn}));
	$SONOS_BookmarkSpeicher{OldTrackURIs}{$udn} = '' if (!defined($SONOS_BookmarkSpeicher{OldTrackURIs}{$udn}));
	$SONOS_BookmarkSpeicher{OldTrackPositions}{$udn} = 0 if (!defined($SONOS_BookmarkSpeicher{OldTrackPositions}{$udn}));
	$SONOS_BookmarkSpeicher{OldTrackDurations}{$udn} = 0 if (!defined($SONOS_BookmarkSpeicher{OldTrackDurations}{$udn}));
	$SONOS_BookmarkSpeicher{OldTransportstate}{$udn} = 'STOPPED' if (!defined($SONOS_BookmarkSpeicher{OldTransportstate}{$udn}));
	$SONOS_BookmarkSpeicher{OldTimestamp}{$udn} = scalar(gettimeofday()) if (!defined($SONOS_BookmarkSpeicher{OldTimestamp}{$udn}));
	$SONOS_BookmarkSpeicher{OldTitles}{$udn} = '' if (!defined($SONOS_BookmarkSpeicher{OldTitles}{$udn}));
	
	# Große Logausgabe fürs debugging...
	SONOS_Log $udn, 5, '___________________________________________________________________________';
	SONOS_Log $udn, 5, 'OldTracks: '.$SONOS_BookmarkSpeicher{OldTracks}{$udn};
	SONOS_Log $udn, 5, 'NumTracks: '.$SONOS_BookmarkSpeicher{NumTracks}{$udn};
	SONOS_Log $udn, 5, 'OldTrackURIs: '.$SONOS_BookmarkSpeicher{OldTrackURIs}{$udn};
	SONOS_Log $udn, 5, 'OldTrackPositions: '.$SONOS_BookmarkSpeicher{OldTrackPositions}{$udn};
	SONOS_Log $udn, 5, 'OldTrackDurations: '.$SONOS_BookmarkSpeicher{OldTrackDurations}{$udn};
	SONOS_Log $udn, 5, 'OldTransportstate: '.$SONOS_BookmarkSpeicher{OldTransportstate}{$udn};
	SONOS_Log $udn, 5, 'OldTimestamp: '.$SONOS_BookmarkSpeicher{OldTimestamp}{$udn};
	SONOS_Log $udn, 5, 'OldTitle: '.$SONOS_BookmarkSpeicher{OldTitles}{$udn};
	
	# Gemeinsamer Zeitstempel...
	my $timestamp = scalar(gettimeofday());
	
	# Aktuelle Werte für Title sichern...
	my $trackURI = $SONOS_BookmarkSpeicher{OldTrackURIs}{$udn};
	if ($trackURI) {
		foreach my $gKey (SONOS_getBookmarkGroupKeys('Title', $udn)) {
			next if ($SONOS_BookmarkTitleDefinition{$gKey}{Chapter});
			
			# Passt der Titel zum RegEx-Filter?
			if ($trackURI !~ m/$SONOS_BookmarkTitleDefinition{$gKey}{TrackURIRegEx}/) {
				SONOS_Log $udn, 5, 'Skipped Title because of no match to m/'.$SONOS_BookmarkTitleDefinition{$gKey}{TrackURIRegEx}.'/';
				delete($SONOS_BookmarkTitleHash{$gKey}{$trackURI});
				next;
			}
			
			# Config-Parameter ausgeben...
			SONOS_Log $udn, 5, 'Match Title! Defined group "'.$gKey.'" ~ RemainingLength: '.$SONOS_BookmarkTitleDefinition{$gKey}{RemainingLength}.' ~ MinTitleLength: '.$SONOS_BookmarkTitleDefinition{$gKey}{MinTitleLength};
			
			# U.u. eine Trackposition berechnen...
			my $trackPosition = $SONOS_BookmarkSpeicher{OldTrackPositions}{$udn};
			$trackPosition = ($timestamp - $SONOS_BookmarkSpeicher{OldTimestamp}{$udn}) if ($SONOS_BookmarkSpeicher{OldTransportstate}{$udn} eq 'PLAYING');
			SONOS_Log $udn, 5, 'Used TrackPosition: '.SONOS_ConvertSecondsToTime($trackPosition);
			
			# Wenn der Titel bereits im Bereich der RemainingTime ist oder die Mindestgröße unterschreitet, dann aus den Bookmarks löschen
			if (($SONOS_BookmarkSpeicher{OldTrackDurations}{$udn} - $trackPosition <= $SONOS_BookmarkTitleDefinition{$gKey}{RemainingLength})
			|| ($SONOS_BookmarkSpeicher{OldTrackDurations}{$udn} < $SONOS_BookmarkTitleDefinition{$gKey}{MinTitleLength})) {
				delete($SONOS_BookmarkTitleHash{$gKey}{$trackURI});
				next;
			}
			
			# Sonst die Werte aktualisieren/hinzufügen...
			$SONOS_BookmarkTitleHash{$gKey}{$trackURI}{TrackPosition} = $trackPosition;
			$SONOS_BookmarkTitleHash{$gKey}{$trackURI}{LastAccess} = $timestamp;
			$SONOS_BookmarkTitleHash{$gKey}{$trackURI}{LastPlayer} = $udn;
			$SONOS_BookmarkTitleHash{$gKey}{$trackURI}{Title} = $SONOS_BookmarkSpeicher{OldTitles}{$udn}.' - Position 1';
		}
	}
	
	# Aktuelle Werte für Queue sichern...
	my $listHash = SONOS_Client_Data_Retreive($udn, 'reading', 'QueueHash', '');
	if ($listHash) {
		foreach my $gKey (SONOS_getBookmarkGroupKeys('Queue', $udn)) {
			if (SONOS_getBookmarkQueueIsRelevant($gKey, $listHash, undef, $SONOS_BookmarkSpeicher{NumTracks}{$udn})) {
				$SONOS_BookmarkQueueHash{$gKey}{$listHash}{Track} = $SONOS_BookmarkSpeicher{OldTracks}{$udn};
				$SONOS_BookmarkQueueHash{$gKey}{$listHash}{LastAccess} = $timestamp;
				$SONOS_BookmarkQueueHash{$gKey}{$listHash}{LastPlayer} = $udn;
				$SONOS_BookmarkQueueHash{$gKey}{$trackURI}{Title} = $SONOS_BookmarkSpeicher{OldTitles}{$udn};
			}
		}
	}
	
	SONOS_Log $udn, 5, '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~';
}

########################################################################################
#
#  SONOS_getBookmarkQueueRelevant - Decide wether or not this Bookmark is relevant
#
########################################################################################
sub SONOS_getBookmarkQueueIsRelevant($$$$) {
	my ($gKey, $listHash, $timestamp, $listLength) = @_;
	
	return ((!defined($timestamp) || ($SONOS_BookmarkQueueDefinition{$gKey}{MaxAge} >= ($timestamp - $SONOS_BookmarkQueueHash{$gKey}{$listHash}{LastAccess})))
			&& ($SONOS_BookmarkQueueDefinition{$gKey}{MinListLength} <= $listLength)
			&& ($SONOS_BookmarkQueueDefinition{$gKey}{MaxListLength} >= $listLength));
}

########################################################################################
#
#  SONOS_getBookmarkTitleRelevant - Decide wether or not this Bookmark is relevant
#
########################################################################################
sub SONOS_getBookmarkTitleIsRelevant($$$$$) {
	my ($gKey, $timestamp, $trackURI, $titlePosition, $titleLength) = @_;
	
	return 0 if ($SONOS_BookmarkTitleDefinition{$gKey}{Chapter});
	
	return (($trackURI =~ m/$SONOS_BookmarkTitleDefinition{$gKey}{TrackURIRegEx}/)
			&& (!defined($timestamp) || ($SONOS_BookmarkTitleDefinition{$gKey}{MaxAge} >= ($timestamp - $SONOS_BookmarkTitleHash{$gKey}{$trackURI}{LastAccess})))
			&& ($SONOS_BookmarkTitleDefinition{$gKey}{MinTitleLength} <= $titleLength)
			&& ($SONOS_BookmarkTitleDefinition{$gKey}{RemainingLength} <= ($titleLength - $titlePosition)));
}

########################################################################################
#
#  SONOS_AddToButtonQueue - Adds the given Event-Name to the ButtonQueue
#
########################################################################################
sub SONOS_AddToButtonQueue($$) {
	my ($udn, $event) = @_;
	
	my $data = {Action => uc($event), Time => time()};
	$SONOS_ButtonPressQueue{$udn}->enqueue($data);
}

########################################################################################
#
#  SONOS_CheckButtonQueue - Checks ButtonQueue and triggers events if neccessary
#
########################################################################################
sub SONOS_CheckButtonQueue($) {
	my ($udn) = @_;
	
	my $eventDefinitions = SONOS_Client_Data_Retreive($udn, 'attr', 'buttonEvents', '');
	
	# Wenn keine Events definiert wurden, dann Queue einfach leeren und zurückkehren...
	# Das beschleunigt die Verarbeitung, da im allgemeinen keine (oder eher wenig) Events definiert werden.
	if (!$eventDefinitions) {
		$SONOS_ButtonPressQueue{$udn}->dequeue_nb(10); # Es können pro Rendering-Event im Normalfall nur 4 Elemente dazukommen...
		return;
	}

	my $maxElems = 0;
	while ($eventDefinitions =~ m/(\d+):([MHUD]+)/g) {
		$maxElems = SONOS_Max($maxElems, length($2));
		
		# Sind überhaupt ausreichend Events in der Queue, das dieses ButtonEvent ausgefüllt sein könnte?
		my $ok = $SONOS_ButtonPressQueue{$udn}->pending() >= length($2);
		
		# Prüfen, ob alle Events in der Queue der Reihenfolge des ButtonEvents entsprechen
		if ($ok) {
			for (my $i = 0; $i < length($2); $i++) {
				if ($SONOS_ButtonPressQueue{$udn}->peek($SONOS_ButtonPressQueue{$udn}->pending() - length($2) + $i)->{Action} ne substr($2, $i, 1)) {
					$ok = 0;
				}
			}
		}
		
		# Wenn die Kette stimmt, dann hier prüfen, ob die Maximalzeit eingehalten wurde, und dann u.U. das Event werfen...
		if ($ok) {
			if (time() - $SONOS_ButtonPressQueue{$udn}->peek($SONOS_ButtonPressQueue{$udn}->pending() - length($2))->{Time} <= $1) {
				# Event here...
				SONOS_Log $udn, 3, 'Generating ButtonEvent for Zone "'.$udn.'": '.$2.'.';
				SONOS_Client_Data_Refresh('ReadingsSingleUpdate', $udn, 'ButtonEvent', $2);
			}
		}
	}
	
	# Einträge, die "zu viele Elemente" her sind, wieder entfernen, da diese sowieso keine Berücksichtigung mehr finden werden
	if ($SONOS_ButtonPressQueue{$udn}->pending() > $maxElems) {
		$SONOS_ButtonPressQueue{$udn}->extract(0, $SONOS_ButtonPressQueue{$udn}->pending() - $maxElems); # Es können pro Rendering-Event im Normalfall nur 4 Elemente dazukommen...
	}
}

########################################################################################
#
#  SONOS_AlarmCallback - Alarm-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_AlarmCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'Alarm-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "Alarm-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received Alarm-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:AlarmClock:1') {
		SONOS_Log $udn, 1, 'Alarm-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	# Check if the Variable called AlarmListVersion or DailyIndexRefreshTime exists
	if (!defined($properties{AlarmListVersion}) && !defined($properties{DailyIndexRefreshTime})) {
		return;
	}
  
	SONOS_Log $udn, 4, "Alarm-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	# If a new AlarmListVersion is available
	my $alarmListVersion = SONOS_Client_Data_Retreive($udn, 'reading', 'AlarmListVersion', '~~');
	if (defined($properties{AlarmListVersion}) && ($properties{AlarmListVersion} ne $alarmListVersion)) {
		SONOS_Log $udn, 4, 'Set new Alarm-Data';
		# Retrieve new AlarmList
		my $result = $SONOS_AlarmClockControlProxy{$udn}->ListAlarms();
		
		my $currentAlarmList = $result->getValue('CurrentAlarmList');
		my %alarms = ();
		my @alarmIDs = ();
		while ($currentAlarmList =~ m/<Alarm (.*?)\/>/gi) {
			my $alarm = $1;
			
			# Nur die Alarme, die auch für diesen Raum gelten, reinholen...
			if ($alarm =~ m/RoomUUID="$udnShort"/i) {
				my $id = $1 if ($alarm =~ m/ID="(\d+)"/i);
				SONOS_Log $udn, 5, 'Alarm-Event: Alarm: '.SONOS_Stringify($alarm);
				
				push @alarmIDs, $id;
				
				$alarms{$id}{StartTime} = $1 if ($alarm =~ m/StartTime="(.*?)"/i);
				$alarms{$id}{Duration} = $1 if ($alarm =~ m/Duration="(.*?)"/i);
				$alarms{$id}{Recurrence_Once} = 0;
				$alarms{$id}{Recurrence_Monday} = 0;
				$alarms{$id}{Recurrence_Tuesday} = 0;
				$alarms{$id}{Recurrence_Wednesday} = 0;
				$alarms{$id}{Recurrence_Thursday} = 0;
				$alarms{$id}{Recurrence_Friday} = 0;
				$alarms{$id}{Recurrence_Saturday} = 0;
				$alarms{$id}{Recurrence_Sunday} = 0;
				$alarms{$id}{Enabled} = $1 if ($alarm =~ m/Enabled="(.*?)"/i);
				$alarms{$id}{RoomUUID} = $1 if ($alarm =~ m/RoomUUID="(.*?)"/i);
				$alarms{$id}{ProgramURI} = decode_entities($1) if ($alarm =~ m/ProgramURI="(.*?)"/i);
				$alarms{$id}{ProgramMetaData} = decode_entities($1) if ($alarm =~ m/ProgramMetaData="(.*?)"/i);
				$alarms{$id}{Shuffle} = 0;
				$alarms{$id}{Repeat} = 0;
				$alarms{$id}{Volume} = $1 if ($alarm =~ m/Volume="(.*?)"/i);
				$alarms{$id}{IncludeLinkedZones} = $1 if ($alarm =~ m/IncludeLinkedZones="(.*?)"/i);
				
				# PlayMode ermitteln...
				my $currentPlayMode = 'NORMAL';
				$currentPlayMode = $1 if ($alarm =~ m/PlayMode="(.*?)"/i);
				$alarms{$id}{Shuffle} = 1 if ($currentPlayMode eq 'SHUFFLE' || $currentPlayMode eq 'SHUFFLE_NOREPEAT');
				$alarms{$id}{Repeat} = 1 if ($currentPlayMode eq 'SHUFFLE' || $currentPlayMode eq 'REPEAT_ALL');
				
				# Recurrence ermitteln...
				my $currentRecurrence = $1 if ($alarm =~ m/Recurrence="(.*?)"/i);
				$alarms{$id}{Recurrence_Once} = 1 if ($currentRecurrence eq 'ONCE');
				$alarms{$id}{Recurrence_Sunday} = 1 if (($currentRecurrence =~ m/^ON_\d*?0/i) || ($currentRecurrence =~ m/^WEEKENDS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Monday} = 1 if (($currentRecurrence =~ m/^ON_\d*?1/i) || ($currentRecurrence =~ m/^WEEKDAYS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Tuesday} = 1 if (($currentRecurrence =~ m/^ON_\d*?2/i) || ($currentRecurrence =~ m/^WEEKDAYS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Wednesday} = 1 if (($currentRecurrence =~ m/^ON_\d*?3/i) || ($currentRecurrence =~ m/^WEEKDAYS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Thursday} = 1 if (($currentRecurrence =~ m/^ON_\d*?4/i) || ($currentRecurrence =~ m/^WEEKDAYS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Friday} = 1 if (($currentRecurrence =~ m/^ON_\d*?5/i) || ($currentRecurrence =~ m/^WEEKDAYS/i) || ($currentRecurrence =~ m/^DAILY/i));
				$alarms{$id}{Recurrence_Saturday} = 1 if (($currentRecurrence =~ m/^ON_\d*?6/i) || ($currentRecurrence =~ m/^WEEKENDS/i) || ($currentRecurrence =~ m/^DAILY/i));
				
				SONOS_Log $udn, 5, 'Alarm-Event: Alarm-Decoded: '.SONOS_Stringify(\%alarms);
			}
		}
		
		# Sets the approbriate Readings-Value
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AlarmList', SONOS_Dumper(\%alarms));
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AlarmListIDs', join(',', @alarmIDs));
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AlarmListVersion', $result->getValue('CurrentAlarmListVersion'));
	}
	
	if (defined($properties{DailyIndexRefreshTime})) {
		SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', $udn, 'DailyIndexRefreshTime', $properties{DailyIndexRefreshTime});
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of Alarm-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "Alarm-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_ZoneGroupTopologyCallback - ZoneGroupTopology-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_ZoneGroupTopologyCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'ZoneGroupTopology-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "ZoneGroupTopology-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received ZoneGroupTopology-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:ZoneGroupTopology:1') {
		SONOS_Log $udn, 1, 'ZoneGroupTopology-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "ZoneGroupTopology-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	# ZoneGroupState: Gesamtkonstellation
	my $zoneGroupState = '';
	if ($properties{ZoneGroupState}) {
		$zoneGroupState = decode_entities($1) if ($properties{ZoneGroupState} =~ m/(.*)/);
		SONOS_Client_Data_Refresh('ReadingsSingleUpdateIfChanged', 'undef', 'ZoneGroupState', $zoneGroupState);
	}
	
	# ZonePlayerUUIDsInGroup: Welche Player befinden sich alle in der gleichen Gruppe wie ich?
	my $zonePlayerUUIDsInGroup = SONOS_Client_Data_Retreive($udn, 'reading', 'ZonePlayerUUIDsInGroup', '');
	if ($properties{ZonePlayerUUIDsInGroup}) {
		$zonePlayerUUIDsInGroup = $properties{ZonePlayerUUIDsInGroup};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ZonePlayerUUIDsInGroup', $zonePlayerUUIDsInGroup);
	}
	
	# ZoneGroupID: Welcher Gruppe gehöre ich aktuell an, und hat sich meine Aufgabe innerhalb der Gruppe verändert?
	my $zoneGroupID = SONOS_Client_Data_Retreive($udn, 'reading', 'ZoneGroupID', '');
	my $fieldType = SONOS_Client_Data_Retreive($udn, 'reading', 'fieldType', '');
	if ($zoneGroupState =~ m/.*(<ZoneGroup Coordinator="(RINCON_[0-9a-f]+)".*?>).*?(<(ZoneGroupMember|Satellite) UUID="$udnShort".*?(>|\/>))/is) {
		$zoneGroupID = $2;
		my $member = $3;
		
		my $master = ($zoneGroupID eq $udnShort);
		my $masterPlayerName = SONOS_Client_Data_Retreive($zoneGroupID.'_MR', 'def', 'NAME', $zoneGroupID.'_MR');
		my ($slavePlayerNamesRef, $notBondedSlavePlayerNamesRef) = SONOS_AnalyzeTopologyForSlavePlayer($udnShort, $zoneGroupState);
		my @slavePlayerNames = @{$slavePlayerNamesRef};
		my @slavePlayerNotBondedNames = @{$notBondedSlavePlayerNamesRef};
		
		$zoneGroupID .= ':__' if ($zoneGroupID !~ m/:/);
		
		my $topoType = '';
		# Ist dieser Player in einem ChannelMapSet (also einer Paarung) enthalten?
		if ($member =~ m/ChannelMapSet=".*?$udnShort:(.*?),(.*?)[;"]/is) {
			$topoType = '_'.$1;
		}
		
		# Ist dieser Player in einem HTSatChanMapSet (also einem Surround-System) enthalten?
		if ($member =~ m/HTSatChanMapSet=".*?$udnShort:(.*?)[;"]/is) {
			$topoType = '_'.$1;
			$topoType =~ s/,/_/g;
		}
		
		SONOS_Log undef, 4, 'Retrieved TopoType: '.$topoType;
		if ($topoType ne '') {
			$fieldType = substr($topoType, 1);
		} else {
			$fieldType = '';
		}
		
		# Für den Aliasnamen schöne Bezeichnungen ermitteln...
		my $aliasSuffix = '';
		$aliasSuffix = ' - Hinten Links' if ($topoType eq '_LR');
		$aliasSuffix = ' - Hinten Rechts' if ($topoType eq '_RR');
		$aliasSuffix = ' - Links' if ($topoType eq '_LF');
		$aliasSuffix = ' - Rechts' if ($topoType eq '_RF');
		$aliasSuffix = ' - Subwoofer' if ($topoType eq '_SW');
		$aliasSuffix = ' - Mitte' if ($topoType eq '_LF_RF');
		
		my $roomName = SONOS_Client_Data_Retreive($udn, 'reading', 'roomName', '');
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomNameAlias', $roomName.$aliasSuffix);
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ZoneGroupID', $zoneGroupID);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'fieldType', $fieldType);
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'IsBonded', (($fieldType eq '') || ($fieldType eq 'LF') || ($fieldType eq 'LF_RF')) ? '0' : '1');
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'IsMaster', $master ? '1' : '0');
	}
	
	# ZoneGroupName: Welchen Namen hat die aktuelle Gruppe?
	my $zoneGroupName = SONOS_Client_Data_Retreive($udn, 'reading', 'ZoneGroupName', '');
	if ($properties{ZoneGroupName}) {
		$zoneGroupName = $properties{ZoneGroupName};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ZoneGroupName', $zoneGroupName);
	}
	
	SONOS_AnalyzeTopologyForMasterPlayer($zoneGroupState, $udn);
	
	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of ZoneGroupTopology-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "ZoneGroupTopology-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_AnalyzeTopologyForSlavePlayer - Topology analysieren, um die Slaveplayer zu 
#                                        einem Masterplayer zu ermitteln
#
########################################################################################
sub SONOS_AnalyzeTopologyForSlavePlayer($$) {
	my ($masterUDNShort, $zoneGroupState) = @_;
	
	my @slavePlayer = ();
	my @notBonded = ();
	while ($zoneGroupState =~ m/<ZoneGroup.*?Coordinator="(.*?)".*?>(.*?)<\/ZoneGroup>/gi) {
		next if ($1 ne $masterUDNShort);
		
		my $member = $2;
		while ($member =~ m/<ZoneGroupMember(.*?UUID="(.*?)".*?)\/>/gi) {
			next if ($2 eq $masterUDNShort); # Den Master selbst nicht in die Slaveliste reinpacken...
			
			my $memberUUID = $2;
			
			# Wenn der Player alleine ist, bzw. der Konstellationsmaster...
			if (!SONOS_Client_Data_Retreive($memberUUID.'_MR', 'reading', 'IsBonded', '')) {
				push(@notBonded, SONOS_Client_Data_Retreive($memberUUID.'_MR', 'def', 'NAME', $memberUUID.'_MR'));
			}
			
			push @slavePlayer, SONOS_Client_Data_Retreive($memberUUID.'_MR', 'def', 'NAME', $memberUUID.'_MR');
		}
	}
	
	@slavePlayer = sort @slavePlayer;
	@notBonded = sort @notBonded;
	
	return (\@slavePlayer, \@notBonded);
}

########################################################################################
#
#  SONOS_AnalyzeTopologyForFindingMaster - Topology analysieren, um den Master zu einem Player zu ermitteln
#
########################################################################################
sub SONOS_AnalyzeTopologyForFindingMaster($$) {
	my ($udnShort, $zoneGroupState) = @_;
	
	while ($zoneGroupState =~ m/<ZoneGroup.*?Coordinator="(.*?)".*?>(.*?)<\/ZoneGroup>/gi) {
		my $coordinator = $1;
		my $zoneGroup = $2;
		
		while ($zoneGroup =~ m/<ZoneGroupMember(.*?UUID="(.*?)".*?)\/>/gi) {
			return $coordinator.'_MR' if ($udnShort eq $2);
		}
	}
	
	return '';
}

########################################################################################
#
#  SONOS_AnalyzeTopologyForFindingMastersSlaves - Topology analysieren, um die Slaves des Masters zu einem Player zu ermitteln
#
########################################################################################
sub SONOS_AnalyzeTopologyForFindingMastersSlaves($$) {
	my ($udnShort, $zoneGroupState) = @_;
	
	my $masterCoordinator = SONOS_AnalyzeTopologyForFindingMaster($udnShort, $zoneGroupState);
	my @masterSlaves = ();
	
	while ($zoneGroupState =~ m/<ZoneGroup.*?Coordinator="(.*?)".*?>(.*?)<\/ZoneGroup>/gi) {
		my $coordinator = $1.'_MR';
		my $zoneGroup = $2;
		
		if ($masterCoordinator eq $coordinator) {
			while ($zoneGroup =~ m/<ZoneGroupMember(.*?UUID="(.*?)".*?)\/>/gi) {
				push(@masterSlaves, $2.'_MR') if ($masterCoordinator ne $2.'_MR');
			}
		}
	}
	
	return ($masterCoordinator, \@masterSlaves);
}

########################################################################################
#
#  SONOS_AnalyzeTopologyForMasterPlayer - Topology analysieren, um das Reading "MasterPlayer" 
#                                         sowie die Readings "MasterPlayerPlaying" und 
#                                         "MasterPlayerNotPlaying" zu setzen.
#
########################################################################################
sub SONOS_AnalyzeTopologyForMasterPlayer($;$) {
	my ($zoneGroupState, $udnCallingPlayer) = @_;
	$udnCallingPlayer = '' if (!defined($udnCallingPlayer));
	
	return if (!defined($zoneGroupState) || ($zoneGroupState eq ''));
	
	my @allplayer = ();
	my @playing = ();
	my @notplaying = ();
	my %masterPlayer;
	my %notBonded;
	my %slavePlayer;
	
	while ($zoneGroupState =~ m/<ZoneGroup.*?Coordinator="(.*?)".*?>(.*?)<\/ZoneGroup>/gi) {
		my $udn = $1.'_MR';
		my $zoneGroup = $2;
		my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', '~~~DELETE~~~');
		
		# Keine Bridge o.ä. verwenden...
		next if ($2 =~ m/IsZoneBridge="1"/i);
		
		$masterPlayer{$udn} = $udn;
		if ($name ne '~~~DELETE~~~') {
			push(@allplayer, $name) if (!SONOS_isInList($name, @allplayer));
			
			my $transportState = SONOS_Client_Data_Retreive($udn, 'reading', 'TransportState', '-');
			if ($transportState eq 'PLAYING') {
				push(@playing, $name);
			} else {
				push(@notplaying, $name);
			}
			
			while ($zoneGroup =~ m/<ZoneGroupMember(.*?UUID="(.*?)".*?)\/>/gi) {
				my $member = $1;
				my $memberUUID = $2.'_MR';
				my $memberName = SONOS_Client_Data_Retreive($memberUUID, 'def', 'NAME', '~~~DELETE~~~');
				
				push(@allplayer, $memberName) if (!SONOS_isInList($memberName, @allplayer));
				push(@{$slavePlayer{$udn}}, $memberName) if ((!SONOS_isInList($memberName, $slavePlayer{$udn})) && ($memberUUID ne $udn));
				$masterPlayer{$memberUUID} = $udn;
				
				# Wenn der Player alleine ist, bzw. der Konstellationsmaster...
				if (!SONOS_Client_Data_Retreive($memberUUID, 'reading', 'IsBonded', 0)) {
					push(@{$notBonded{$udn}}, $memberName) if ((!SONOS_isInList($memberName, $notBonded{$udn})) && ($memberUUID ne $udn));
					push(@{$notBonded{x}}, $memberName) if (!SONOS_isInList($memberName, $notBonded{x}));
				}
			}
		}
	}
	
	# Die Listen normalisieren
	@allplayer = sort @allplayer;
	@playing = sort @playing;
	@notplaying = sort @notplaying;
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:undef');
	
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'AllPlayer', SONOS_Dumper(\@allplayer));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'AllPlayerCount', scalar(@allplayer));
	
	my @list = ();
	@list = sort @{$notBonded{x}} if (defined($notBonded{x}));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'AllPlayerNotBonded', SONOS_Dumper(\@list));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'AllPlayerNotBondedCount', scalar(@list));
	
	# LineInPlayer-Listen aktualisieren...
	my @lineInPlayer = grep { SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $_, $_), 'reading', 'LineInConnected', 0) } @allplayer;
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayer', SONOS_Dumper(\@lineInPlayer));
	
	if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayerList', (scalar(@lineInPlayer) ? '-|' : '').join('|', @lineInPlayer));
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayerListAlias', (scalar(@lineInPlayer) ? 'Auswahl|' : '').join('|', map { my $udn = SONOS_Client_Data_Retreive('udn', 'udn', $_, $_); $_ = SONOS_Client_Data_Retreive($udn, 'reading', 'roomName', $udn).' ~ '.SONOS_Client_Data_Retreive($udn, 'reading', 'LineInName', $udn); $_ } @lineInPlayer));
	}
	
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayerPlaying', SONOS_Dumper(\@playing));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayerPlayingCount', scalar(@playing));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayerNotPlaying', SONOS_Dumper(\@notplaying));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayerNotPlayingCount', scalar(@notplaying));
	
	push(@playing, @notplaying);
	@playing = sort @playing;
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayer', SONOS_Dumper(\@playing));
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MasterPlayerCount', scalar(@playing));
	
	SONOS_Client_Notifier('ReadingsEndUpdate:undef');
	
	# SlavePlayerNotBonded (AvailablePlayerList) für jeden (bereits bekannten!) Sonos-Player neu ermitteln...
	foreach my $udn (@{$SONOS_Client_Data{PlayerUDNs}}) {
		my $elem = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', '');
		next if ($elem eq '');
		
		# Sicherstellen, dass immer ein Masterplayer eingetragen ist...
		$masterPlayer{$udn} = $udn if (!defined($masterPlayer{$udn}));
		
		my @notBondedPlayer = ();
		if (defined($notBonded{$udn})) {
			@notBondedPlayer = sort @{$notBonded{$udn}};
		}
		
		my @availablePlayer;
		if (defined($notBonded{x})) {
			@availablePlayer = sort @{$notBonded{x}};
		}
		
		my @slavePlayer;
		if (defined($slavePlayer{$udn})) {
			@slavePlayer = sort @{$slavePlayer{$udn}};
		}
		
		
		my $pos = SONOS_posInList($elem, @availablePlayer);
		splice(@availablePlayer, $pos, 1) if (($pos >= 0) && ($pos < scalar(@availablePlayer)));
		
		
		# Die Slaveplayer entfernen...
		foreach my $slaveElem (@slavePlayer) {
			$pos = SONOS_posInList($slaveElem, @availablePlayer);
			splice(@availablePlayer, $pos, 1) if (($pos >= 0) && ($pos < scalar(@availablePlayer)));
		}
		
		
		SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn) if (($udnCallingPlayer eq '') || ($udnCallingPlayer ne $udn));
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'MasterPlayer', SONOS_Client_Data_Retreive($masterPlayer{$udn}, 'def', 'NAME', $udn));
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AvailablePlayer', SONOS_Dumper(\@availablePlayer));
		if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AvailablePlayerList', (scalar(@availablePlayer) ? '-|' : '').join('|', @availablePlayer));
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'AvailablePlayerListAlias', (scalar(@availablePlayer) ? 'Auswahl|' : '').join('|', map { $_ = SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $_, $_), 'reading', 'roomName', $_); $_ } @availablePlayer));
		}
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayer', SONOS_Dumper(\@slavePlayer));
		if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerList', (scalar(@slavePlayer) ? '-|' : '').join('|', @slavePlayer));
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerListAlias', (scalar(@slavePlayer) ? 'Auswahl|' : '').join('|', map { $_ = SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $_, $_), 'reading', 'roomName', $_); $_ } @slavePlayer));
		}
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBonded', SONOS_Dumper(\@notBondedPlayer));
		if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBondedList', (scalar(@notBondedPlayer) ? '-|' : '').join('|', @notBondedPlayer));
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'SlavePlayerNotBondedListAlias', (scalar(@notBondedPlayer) ? 'Auswahl|' : '').join('|', map { $_ = SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $_, $_), 'reading', 'roomName', $_); $_ } @notBondedPlayer));
		}
		
		my $zoneGroupNameDetails = '';
		if ($masterPlayer{$udn} ne $udn) {
			$zoneGroupNameDetails = SONOS_Client_Data_Retreive($masterPlayer{$udn}, 'reading', 'roomName', 'k.A.');
		}
		foreach my $slave (@notBondedPlayer) {
			$zoneGroupNameDetails .= ' + '.SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $slave, $slave), 'reading', 'roomName', $slave),
		}
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ZoneGroupNameDetails', $zoneGroupNameDetails);
		
		SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn) if (($udnCallingPlayer eq '') || ($udnCallingPlayer ne $udn));
	}
}

########################################################################################
#
#  SONOS_DevicePropertiesCallback - DeviceProperties-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_DevicePropertiesCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'DeviceProperties-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "DeviceProperties-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received DeviceProperties-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:DeviceProperties:1') {
		SONOS_Log $udn, 1, 'DeviceProperties-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "DeviceProperties-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	# Raumname wurde angepasst?
	my $roomName = SONOS_Client_Data_Retreive($udn, 'reading', 'roomName', '');
	if (defined($properties{ZoneName}) && $properties{ZoneName} ne '') {
		$roomName = $properties{ZoneName};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomName', $roomName);
		
		my $saveRoomName = decode('UTF-8', $roomName);
		eval {
			use utf8;
			$saveRoomName =~ s/([äöüÄÖÜß])/SONOS_UmlautConvert($1)/eg; # Hier erstmal Umlaute 'schön' machen, damit dafür nicht '_' verwendet werden...
		};
		$saveRoomName =~ s/[^a-zA-Z0-9_ ]//g;
		$saveRoomName = SONOS_Trim($saveRoomName);
		$saveRoomName =~ s/ /_/g;
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'saveRoomName', $saveRoomName);
		
		my $topoType = '_'.SONOS_Client_Data_Retreive($udn, 'reading', 'fieldType', '');
		
		# Für den Aliasnamen schöne Bezeichnungen ermitteln...
		my $aliasSuffix = '';
		$aliasSuffix = ' - Hinten Links' if ($topoType eq '_LR');
		$aliasSuffix = ' - Hinten Rechts' if ($topoType eq '_RR');
		$aliasSuffix = ' - Links' if ($topoType eq '_LF');
		$aliasSuffix = ' - Rechts' if ($topoType eq '_RF');
		$aliasSuffix = ' - Subwoofer' if ($topoType eq '_SW');
		$aliasSuffix = ' - Mitte' if ($topoType eq '_LF_RF');
		
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomNameAlias', $roomName.$aliasSuffix);
	}
	
	# Icon wurde angepasst?
	my $roomIcon = SONOS_Client_Data_Retreive($udn, 'reading', 'roomIcon', '');
	if (defined($properties{Icon}) && $properties{Icon} ne '') {
		$properties{Icon} =~ s/.*?:(.*)/$1/i;
		
		$roomIcon = $properties{Icon};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'roomIcon', $roomIcon);
	}
	
	# ButtonState wurde angepasst?
	my $buttonState = SONOS_Client_Data_Retreive($udn, 'reading', 'ButtonState', '');
	if (defined($properties{ButtonState}) && $properties{ButtonState} ne '') {
		$buttonState = $properties{ButtonState};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ButtonState', $buttonState);
	}
	
	# ButtonLockState wurde angepasst?
	my $buttonLockState = SONOS_Client_Data_Retreive($udn, 'reading', 'ButtonLockState', '');
	if (defined($properties{ButtonLockState}) && $properties{ButtonLockState} ne '') {
		$buttonLockState = $properties{ButtonLockState};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'ButtonLockState', $buttonLockState);
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of DeviceProperties-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "DeviceProperties-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_AudioInCallback - AudioIn-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_AudioInCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'AudioIn-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "AudioIn-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received AudioIn-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:AudioIn:1') {
		SONOS_Log $udn, 1, 'AudioIn-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "AudioIn-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:'.$udn);
	
	# LineInConnected wurde angepasst?
	my $lineInConnected = SONOS_Client_Data_Retreive($udn, 'reading', 'LineInConnected', '');
	if (defined($properties{LineInConnected}) && $properties{LineInConnected} ne '') {
		$lineInConnected = $properties{LineInConnected};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'LineInConnected', $lineInConnected);
	}
	
	# LineInName wurde angepasst?
	my $lineInName = SONOS_Client_Data_Retreive($udn, 'reading', 'LineInName', '');
	if (defined($properties{AudioInputName}) && $properties{AudioInputName} ne '') {
		$lineInName = $properties{AudioInputName};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'LineInName', $lineInName);
	}
	
	# LineInIcon wurde angepasst?
	my $lineInIcon = SONOS_Client_Data_Retreive($udn, 'reading', 'LineInIcon', '');
	if (defined($properties{Icon}) && $properties{Icon} ne '') {
		$lineInIcon = $properties{Icon};
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', $udn, 'LineInIcon', $lineInIcon);
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:'.$udn);
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:undef');
	
	# LineInPlayer-Listen aktualisieren...
	my @lineInPlayer = grep { SONOS_Client_Data_Retreive(SONOS_Client_Data_Retreive('udn', 'udn', $_, $_), 'reading', 'LineInConnected', 0) } @{eval(SONOS_Client_Data_Retreive('undef', 'reading', 'AllPlayer', '[]'))};
	SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayer', SONOS_Dumper(\@lineInPlayer));
	
	if (SONOS_Client_Data_Retreive('undef', 'attr', 'getListsDirectlyToReadings', 0)) {
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayerList', (scalar(@lineInPlayer) ? '-|' : '').join('|', @lineInPlayer));
		SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'LineInPlayerListAlias', (scalar(@lineInPlayer) ? 'Auswahl|' : '').join('|', map { my $udn = SONOS_Client_Data_Retreive('udn', 'udn', $_, $_); $_ = SONOS_Client_Data_Retreive($udn, 'reading', 'roomName', $udn).' ~ '.SONOS_Client_Data_Retreive($udn, 'reading', 'LineInName', $udn); $_ } @lineInPlayer));
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:undef');
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of AudioIn-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "AudioIn-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_MusicServicesCallback - MusicServices-Callback, 
#
# Parameter $service = Service-Representing Object
#						$properties = Properties, that have been changed in this event
#
########################################################################################
sub SONOS_MusicServicesCallback($$) {
	my ($service, %properties) = @_;
	
	my $udn = $SONOS_Locations{$service->base};
	my $udnShort = $1 if ($udn =~ m/(.*?)_MR/i);
	
	if (!$udn) {
		SONOS_Log undef, 1, 'MusicServices-Event receive error: SonosPlayer not found; Searching for \''.$service->base.'\'!';
		return;
	}
	
	my $name = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	# If the Device is disabled, return here...
	if (SONOS_Client_Data_Retreive($udn, 'attr', 'disable', 0) == 1) {
		SONOS_Log $udn, 3, "MusicServices-Event: device '$name' disabled. No Events/Data will be processed!";
		return;
	}
	
	SONOS_Log $udn, 3, 'Event: Received MusicServices-Event for Zone "'.$name.'".';
	$SONOS_Client_SendQueue_Suspend = 1;
	
	# Check if the correct ServiceType
	if ($service->serviceType() ne 'urn:schemas-upnp-org:service:MusicServices:1') {
		SONOS_Log $udn, 1, 'MusicServices-Event receive error: Wrong Servicetype, was \''.$service->serviceType().'\'!';
		return;
	}
	
	SONOS_Log $udn, 4, "MusicServices-Event: All correct with this service-call till now. UDN='uuid:".$udn."'";
	
	SONOS_Client_Notifier('ReadingsBeginUpdate:undef');
	
	# ServiceListVersion wurde angepasst?
	my $serviceListVersion = SONOS_Client_Data_Retreive('undef', 'reading', 'MusicServicesListVersion', '');
	if (defined($properties{ServiceListVersion}) && $properties{ServiceListVersion} ne '') {
		if ($serviceListVersion ne $properties{ServiceListVersion}) {
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MusicServicesListVersion', $properties{ServiceListVersion});
			
			# Call MusicServiceProxy...
			my $response = $SONOS_MusicServicesProxy{$udn}->ListAvailableServices();
			
			# ServiceTypes
			my @serviceTypes = split(',', $response->getValue('AvailableServiceTypeList'));
			SONOS_Log undef, 5, 'MusicService-Types: '.join(@serviceTypes, ', ');
			my $servicepos = 0;
			
			my %musicServices = ();
			my $result = $response->getValue('AvailableServiceDescriptorList');
			SONOS_Log undef, 5, 'MusicService-Call: '.$result;
			while ($result =~ m/<Service.*?Id="(\d+)".*?Name="(.+?)"(.*?)<\/Service>/sgi) {
				my $id = $1;
				my $name = $2;
				my $content = $3;
				
				# If TuneIn, then jump over
				next if ($name eq 'TuneIn');
				
				my $serviceType = $serviceTypes[$servicepos++];
				
				if ($content =~ m/.*?SecureUri="(.+?)".*?Capabilities="(\d+)".*?>.*?(<Strings.*?Uri="(.+?)".*?\/>|).*?<PresentationMap.*?Uri="(.+?)".*?\/>.*?/si) {
					my $smapi = $1;
					my $capabilities = $2;
					my $stringsURL = $4;
					
					my $presentationMap = $5;
					
					my $promoString = '';
					if (defined($stringsURL) && ($stringsURL ne '')) {
						my $strings = encode('UTF-8', get($stringsURL));
						if (defined($strings) && ($strings ne '')) {
							$promoString = $1 if ($strings =~ m/<stringtable.*?xml:lang="de-DE">.*?<string.*?stringId="ServicePromo">(.*?)<\/string>.*?<\/stringtable>/si);
							$promoString = $1 if (($promoString eq '') && ($strings =~ m/<stringtable.*?xml:lang="en-US">.*?<string.*?stringId="ServicePromo">(.*?)<\/string>.*?<\/stringtable>/si));
						}
					}
					
					my $presentationMapData = encode('UTF-8', get($presentationMap));
					if (defined($presentationMapData)) {
						SONOS_Log undef, 5, 'PresentationMap('.$id.' ~ '.$name.' ~ ServiceType: "'.$serviceType.'"): '.$presentationMapData;
					} else {
						SONOS_Log undef, 5, 'PresentationMap('.$id.' ~ '.$name.' ~ ServiceType: "'.$serviceType.'"): undef';
					}
					
					my ($resolution, $resolutionSubst) = SONOS_ExtractMaxResolution($presentationMapData, 'ArtWorkSizeMap');
					if (!defined($resolution)) {
						($resolution, $resolutionSubst) = SONOS_ExtractMaxResolution($presentationMapData, 'BrowseIconSizeMap');
					}
					
					#SONOS_GetMediaMetadata($udn, $id, 
					
					$musicServices{$id}{Name} = $name;
					$musicServices{$id}{ServiceType} = $serviceType;
					
					$musicServices{$id}{IconQuadraticURL} = 'http://sonos-logo.ws.sonos.com/'.$musicServices{$id}{ServiceType}.'/'.$musicServices{$id}{ServiceType}.'-400x400.png';
					$musicServices{$id}{IconQuadraticURL} = '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/proxy/aa?url='.SONOS_URI_Escape($musicServices{$id}{IconQuadraticURL}) if (SONOS_Client_Data_Retreive('undef', 'attr', 'generateProxyAlbumArtURLs', 0));
					
					$musicServices{$id}{IconRoundURL} = 'http://sonos-logo.ws.sonos.com/'.$musicServices{$id}{ServiceType}.'/'.$musicServices{$id}{ServiceType}.'-72x72.png';
					$musicServices{$id}{IconRoundURL} = '/'.SONOS_Client_Data_Retreive('undef', 'attr', 'webname', 'fhem').'/sonos/proxy/aa?url='.SONOS_URI_Escape($musicServices{$id}{IconRoundURL}) if (SONOS_Client_Data_Retreive('undef', 'attr', 'generateProxyAlbumArtURLs', 0));
					
					$musicServices{$id}{SMAPI} = $smapi;
					$musicServices{$id}{Resolution} = $resolution;
					$musicServices{$id}{ResolutionSubstitution} = $resolutionSubst;
					$musicServices{$id}{Capabilities} = $capabilities;
					
					$promoString =~ s/[\r\n]/ /g;
					$musicServices{$id}{PromoText} = $promoString;
				}
			}
			
			SONOS_Log undef, 5, 'MusicService-List: '.SONOS_Dumper(\%musicServices);
			SONOS_Client_Data_Refresh('ReadingsBulkUpdateIfChanged', 'undef', 'MusicServicesList', SONOS_Dumper(\%musicServices));
		}
	}
	
	SONOS_Client_Notifier('ReadingsEndUpdate:undef');
	
	$SONOS_Client_SendQueue_Suspend = 0;
	SONOS_Log $udn, 3, 'Event: End of MusicServices-Event for Zone "'.$name.'".';
	
	# Prüfen, ob der Player auf 'disappeared' steht, und in diesem Fall den DiscoverProcess neu anstarten...
	if (SONOS_Client_Data_Retreive($udn, 'reading', 'presence', 'disappeared') eq 'disappeared') {
		SONOS_Log $udn, 1, "MusicServices-Event: device '$name' is marked as disappeared. Restarting discovery-process!";
		
		SONOS_RestartControlPoint();
	}
	
	return 0;
}

########################################################################################
#
#  SONOS_ExtractMaxResolution - Extracts the available Coversizes
#
########################################################################################
sub SONOS_ExtractMaxResolution($$) {
	my ($map, $area) = @_;
	return (undef, undef) if (!defined($map));
	
	
	my $artworkSizeMap = $1 if ($map =~ m/<PresentationMap type="$area">.*?<Match>.*?<imageSizeMap>(.*?)<\/imageSizeMap>.*?<\/Match>.*?<\/PresentationMap>/is);
	return (undef, undef) if (!defined($artworkSizeMap));
	
	my @resolutions = ();
	while ($artworkSizeMap =~ m/<sizeEntry size="(\d+)" substitution=".+?".*?\/>.*?/gis) {
		push(@resolutions, $1);
	}
	@resolutions = sort {$b <=> $a} @resolutions;
	my $resolution = $resolutions[0];
	
	my $resolutionSubst = $1 if ($artworkSizeMap =~ m/<sizeEntry.*?size="$resolution".*?substitution="(.+?)".*?\/>.*?/gis);
	
	return ($resolution, $resolutionSubst);
}

########################################################################################
#
#  SONOS_replaceSpecialStringCharacters - Replaces invalid Characters in Strings (like ") for FHEM-internal 
#
# Parameter text = The text, inside that has to be searched and replaced
#
########################################################################################
sub SONOS_replaceSpecialStringCharacters($) {
	my ($text) = @_;
	
	$text =~ s/"/'/g;
	
	return $text;
}

########################################################################################
#
#  SONOS_maskSpecialStringCharacters - Replaces invalid Characters in Strings (like ") for FHEM-internal 
#
# Parameter text = The text, inside that has to be searched and replaced
#
########################################################################################
sub SONOS_maskSpecialStringCharacters($) {
	my ($text) = @_;
	
	$text =~ s/"/\\"/g;
	
	return $text;
}

########################################################################################
#
#  SONOS_ProcessInfoSummarize - Process the InfoSummarize-Fields (XML-Alike Structure)
#  Example for Minimal neccesary structure:
#	 <NormalAudio></NormalAudio> <StreamAudio></StreamAudio>
#
#  Complex Example:
#  <NormalAudio><Artist prefix="(" suffix=")"/><Title prefix=" '" suffix="'" ifempty="[Keine Musikdatei]"/><Album prefix=" vom Album '" suffix="'"/></NormalAudio> <StreamAudio><Sender suffix=":"/><SenderCurrent prefix=" '" suffix="'"/><SenderInfo prefix=" - "/></StreamAudio>
# OR
#  <NormalAudio><TransportState/><InfoSummarize1 prefix=" => "/></NormalAudio> <StreamAudio><TransportState/><InfoSummarize1 prefix=" => "/></StreamAudio>
#
# Parameter name = The name of the SonosPlayer-Device
#						current = The Current-Values hashset
#						summarizeVariableName = The variable-name to process (e.g. "InfoSummarize1")
#
########################################################################################
sub SONOS_ProcessInfoSummarize($$$$) {
	my ($hash, $current, $summarizeVariableName, $bulkUpdate) = @_;

	if (($current->{$summarizeVariableName} = AttrVal($hash->{NAME}, 'generate'.$summarizeVariableName, '')) ne '') {
		# Only pick up the current Audio-Type-Part, if one is available...
		if ($current->{NormalAudio}) {
			$current->{$summarizeVariableName} = $1 if ($current->{$summarizeVariableName} =~ m/<NormalAudio>(.*?)<\/NormalAudio>/i);
		} else {
			$current->{$summarizeVariableName} = $1 if ($current->{$summarizeVariableName} =~ m/<StreamAudio>(.*?)<\/StreamAudio>/i);
		}
	
		# Replace placeholder with variables (list defined in 21_SONOSPLAYER ~ stateVariable)
		my $availableVariables = ($2) if (getAllAttr($hash->{NAME}) =~ m/(^|\s+)stateVariable:(.*?)(\s+|$)/);
		foreach (split(/,/, $availableVariables)) {
			$current->{$summarizeVariableName} = SONOS_ReplaceTextToken($current->{$summarizeVariableName}, $_, $current->{$_});
		}
	
		if ($bulkUpdate) {
			# Enqueue the event
			SONOS_readingsBulkUpdateIfChanged($hash, lcfirst($summarizeVariableName), $current->{$summarizeVariableName});
		} else {
			SONOS_readingsSingleUpdateIfChanged($hash, lcfirst($summarizeVariableName), $current->{$summarizeVariableName}, 1);
		}
	} else {
		if ($bulkUpdate) {
			# Enqueue the event
			SONOS_readingsBulkUpdateIfChanged($hash, lcfirst($summarizeVariableName), '');
		} else {
			SONOS_readingsSingleUpdateIfChanged($hash, lcfirst($summarizeVariableName), '', 1);
		}
	}
}

########################################################################################
#
#  SONOS_ReplaceTextToken - Search and replace any occurency of the given tokenName with the value of tokenValue
#
# Parameter text = The text, inside that has to be searched and replaced
#			tokenName = The name, that has to be searched for
#			tokenValue = The value, the has to be insert instead of tokenName
#
########################################################################################
sub SONOS_ReplaceTextToken($$$) {
	my ($text, $tokenName, $tokenValue) = @_;

	# Hier das Token mit Prefix, Suffix, Instead und IfEmpty ersetzen, wenn entsprechend vorhanden
	$text =~ s/<\s*?$tokenName(\s.*?\/|\/)>/SONOS_ReplaceTextTokenRegReplacer($tokenValue, $1)/eig;
	
	return $text;
}

########################################################################################
#
#  SONOS_ReplaceTextTokenRegReplacer - Internal procedure for replacing TagValues
#
# Parameter tokenValue = The value, the has to be insert instead of tokenName
#			$matcher = The values of the searched and found tag
#
########################################################################################
sub SONOS_ReplaceTextTokenRegReplacer($$) {
	my ($tokenValue, $matcher) = @_;
	
	my $emptyVal = SONOS_DealToken($matcher, 'emptyVal', '');

	return SONOS_ReturnIfNotEmpty($tokenValue, SONOS_DealToken($matcher, 'prefix', ''), $emptyVal).
			SONOS_ReturnIfEmpty($tokenValue, SONOS_DealToken($matcher, 'ifempty', $emptyVal), $emptyVal).
			SONOS_ReturnIfNotEmpty($tokenValue, SONOS_DealToken($matcher, 'instead', $tokenValue), $emptyVal).
			SONOS_ReturnIfNotEmpty($tokenValue, SONOS_DealToken($matcher, 'suffix', ''), $emptyVal);
}

########################################################################################
#
#  SONOS_DealToken - Extracts the content of the given tokenName if exist in checkText
#
# Parameter checkText = The text, that has to be search in
#			tokenName = The value, of which the content has to be returned
#
########################################################################################
sub SONOS_DealToken($$$) {
	my ($checkText, $tokenName, $emptyVal) = @_;
	
	my $returnText = $1 if($checkText =~ m/$tokenName\s*=\s*"(.*?)"/i);
	
	return $emptyVal if (not defined($returnText));
	return $returnText;
}

########################################################################################
#
#  SONOS_ReturnIfEmpty - Returns the second Parameter returnValue only, if the first Parameter checkText *is* empty
#
# Parameter checkText = The text, that has to be checked
#			returnValue = The value, the has to be returned
#
########################################################################################
sub SONOS_ReturnIfEmpty($$$) {
	my ($checkText, $returnValue, $emptyVal) = @_;
	
	return '' if not defined($returnValue);
	return $returnValue if ((not defined($checkText)) || $checkText eq $emptyVal);
	return '';
}

########################################################################################
#
#  SONOS_ReturnIfNotEmpty - Returns the second Parameter returnValue only, if the first Parameter checkText *is NOT* empty
#
# Parameter checkText = The text, that has to be checked
#			returnValue = The value, the has to be returned
#
########################################################################################
sub SONOS_ReturnIfNotEmpty($$$) {
	my ($checkText, $returnValue, $emptyVal) = @_;
	
	return '' if not defined($returnValue);
	return $returnValue if (defined($checkText) && $checkText ne $emptyVal);
	return '';
}

########################################################################################
#
#  SONOS_ImageDownloadTypeExtension - Gives the appropriate extension for the retrieved mimetype of the content of the given url
#
# Parameter url = The URL of the content 
#
########################################################################################
sub SONOS_ImageDownloadTypeExtension($) {
	my ($url) = @_;
	
	# Wenn Spotify, dann sendet der Zoneplayer keinen Mimetype, der ist dann immer JPG
	if ($url =~ m/x-sonos-spotify/) {
		return 'jpg';
	}
	
	# Wenn Napster, dann sendet der Zoneplayer keinen Mimetype, der ist dann immer JPG
	if ($url =~ m/npsdy/) {
		return 'jpg';
	}
	
	# Wenn Radio, dann sendet der Zoneplayer keinen Mimetype, der ist dann immer GIF
	if ($url =~ m/x-sonosapi-stream/) {
		return 'gif';
	}
	
	# Wenn Google Music oder Simfy, dann sendet der Zoneplayer keinen Mimetype, der ist dann immer JPG
	if ($url =~ m/x-sonos-http/) {
		return 'jpg';
	}
	
	# Server abfragen
	my ($content_type, $document_length, $modified_time, $expires, $server);
	eval {
		$SIG{ALRM} = sub { die "Connection Timeout\n" };
		alarm(AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'coverLoadTimeout', $SONOS_DEFAULTCOVERLOADTIMEOUT));
		($content_type, $document_length, $modified_time, $expires, $server) = head($url);
		alarm(0);
	};
	
	return 'ERROR' if (!defined($content_type) || ($content_type =~ m/<head>.*?<\/head>/));
	
	if ($content_type =~ m/png/) {
		return 'png';
	} elsif (($content_type =~ m/jpeg/) || ($content_type =~ m/jpg/)) {
		return 'jpg';
	} elsif ($content_type =~ m/gif/) {
		return 'gif';
	} else {
		$content_type =~ s/\//-/g;
		return $content_type;
	}
}

########################################################################################
#
#  SONOS_ImageDownloadMimeType - Retrieves the mimetype of the content of the given url
#
# Parameter url = The URL of the content 
#
########################################################################################
sub SONOS_ImageDownloadMimeType($) {
	my ($url) = @_;
	
	eval {
		local $SIG{ALRM} = sub { die "Connection Timeout\n" };
		alarm(AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'coverLoadTimeout', $SONOS_DEFAULTCOVERLOADTIMEOUT));
		my ($content_type, $document_length, $modified_time, $expires, $server) = head($url);
		alarm(0);
		
		return $content_type;
	};
	
	return '';
}

########################################################################################
#
#  SONOS_DownloadReplaceIfChanged - Overwrites the file only if its changed
#
# Parameter url = The URL of the new file
#						dest = The local file-uri of the old file
#
# Return 1 = New file have been written
#				 0 = nothing happened, because the filecontents are identical or an error has occurred
#
########################################################################################
sub SONOS_DownloadReplaceIfChanged($$) {
	my ($url, $dest) = @_;
	
	SONOS_Log undef, 5, 'Call of SONOS_DownloadReplaceIfChanged("'.$url.'", "'.$dest.'")';
	
	# Be sure URL is absolute
	return 0 if ($url !~ m/^http:\/\//i);
	
	# Reading new file
	my $newFile = '';
	eval {
		local $SIG{ALRM} = sub { die "Connection Timeout\n" };
		alarm(AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'coverLoadTimeout', $SONOS_DEFAULTCOVERLOADTIMEOUT));
		$newFile = get $url;
		alarm(0);
		
		if (not defined($newFile)) {
			SONOS_Log undef, 4, 'Couldn\'t retrieve file "'.$url.'" via web. Trying to copy directly...';
			
			$newFile = SONOS_ReadFile($url);
			if (not defined($newFile)) {
				SONOS_Log undef, 4, 'Couldn\'t even copy file "'.$url.'" directly... exiting...';
				return 0;
			}
		}
	};
	if ($@) {
		SONOS_Log undef, 2, 'Error during SONOS_DownloadReplaceIfChanged("'.$url.'", "'.$dest.'"): '.$@;
		return 0;
	}
	
	# Wenn keine neue Datei ermittelt wurde, dann abbrechen...
	return 0 if (!defined($newFile) || ($newFile eq ''));

	# Reading old file (if it exists)
	my $oldFile = SONOS_ReadFile($dest);
	$oldFile = '' if (!defined($oldFile));
	
	# compare those files, and overwrite old file, if it has to be changed
	if ($newFile ne $oldFile) {
		# Hier jetzt alle Dateien dieses Players entfernen, damit nichts überflüssiges rumliegt, falls sich die Endung geändert haben sollte
		if (($dest =~ m/(.*\.).*?/) && ($1 ne '')) {
			unlink(<$1*>);
		}
		
		# Hier jetzt die neue Datei herunterladen
		SONOS_Log undef, 4, "New filecontent for '$dest'!";
		if (defined(open IMGFILE, '>'.$dest)) {
			binmode IMGFILE ;
			print IMGFILE $newFile;
			close IMGFILE;
		} else {
			SONOS_Log undef, 1, "Error creating file $dest";
		}
		
		return 1;
	} else {
		SONOS_Log undef, 4, "Identical filecontent for '$dest'!";
		
		return 0;
	}
}

########################################################################################
#
#  SONOS_GetRadioMediaMetadata - Read the Radio-Metadata from the Sonos-Webservice
#
########################################################################################
sub SONOS_GetRadioMediaMetadata($$) {
	my ($udn, $id) = @_;
	my $udnKey = "$1-$2-$3-$4-$5-$6:D" if ($udn =~ m/RINCON_([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})01400(_MR|)/);
	
	return '' if (!defined($udnKey));
	
	my $ua = LWP::UserAgent->new(agent => $SONOS_USERAGENT);
	my $response = $ua->request(POST 'http://legato.radiotime.com/Radio.asmx', 'content-type' => 'text/xml; charset="utf-8"', 
		Content => "<?xml version=\"1.0\" encoding=\"utf-8\"?>
			<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">
				<s:Header>
					<credentials xmlns=\"http://www.sonos.com/Services/1.1\">
						<deviceId>$udnKey</deviceId>
						<deviceProvider>Sonos</deviceProvider>
					</credentials>
				</s:Header>
				<s:Body>
					<getMediaMetadata xmlns=\"http://www.sonos.com/Services/1.1\">
						<id>$id</id>
					</getMediaMetadata>
				</s:Body>
			</s:Envelope>");
	SONOS_Log $udn, 5, 'Radioservice-Metadata: '.$response->content;
	
	my $title = $1 if ($response->content =~ m/<title>(.*?)<\/title>/i);
	my $genreId = $1 if ($response->content =~ m/<genreId>(.*?)<\/genreId>/i);
	my $genre = $1 if ($response->content =~ m/<genre>(.*?)<\/genre>/i);
	my $bitrate = $1 if ($response->content =~ m/<bitrate>(.*?)<\/bitrate>/i);
	my $logo = $1 if ($response->content =~ m/<logo>(.*?)<\/logo>/i); $logo =~ s/(.*?)q(\..*)/$1g$2/;
	my $subtitle = $1 if ($response->content =~ m/<subtitle>(.*?)<\/subtitle>/i);
	
	return $logo;
}

########################################################################################
#
#  SONOS_GetMediaMetadata - Read the Media-Metadata from the Sonos-Webservice
#
########################################################################################
sub SONOS_GetMediaMetadata($$$) {
	my ($udn, $sid, $id) = @_;
	my $udnKey = "$1-$2-$3-$4-$5-$6:D" if ($udn =~ m/RINCON_([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})01400(_MR|)/);
	
	# Shorthand to special handling for TuneIn-Artwork
	return SONOS_GetRadioMediaMetadata($udn, $id) if ($sid == 254);
	
	# Normal Artwork...
	$udn =~ s/RINCON_(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)01400(_MR|)/$1-$2-$3-$4-$5-$6:D/;
	
	my $musicServicesList = SONOS_Client_Data_Retreive($udn, 'reading', 'MusicServicesList', '()');
	return '' if (!$musicServicesList);
	my %musicService = %{eval($musicServicesList)->{$sid}};
	
	my $url = $musicService{SMAPI};
	if ($url) {
		my $ua = LWP::UserAgent->new(agent => $SONOS_USERAGENT);
		my $response = $ua->request(POST $url, 'content-type' => 'text/xml; charset="utf-8"', 
			Content => "<?xml version=\"1.0\" encoding=\"utf-8\"?>
				<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">
					<s:Header>
						<credentials xmlns=\"http://www.sonos.com/Services/1.1\">
							<deviceId>$udnKey</deviceId>
							<deviceProvider>Sonos</deviceProvider>
						</credentials>
					</s:Header>
					<s:Body>
						<getMediaMetadata xmlns=\"http://www.sonos.com/Services/1.1\">
							<id>$id</id>
						</getMediaMetadata>
					</s:Body>
				</s:Envelope>");
		SONOS_Log $udn, 0, 'MediaMetadata: '.$response->content;
		
		my $title = $1 if ($response->content =~ m/<title>(.*?)<\/title>/i);
		my $genreId = $1 if ($response->content =~ m/<genreId>(.*?)<\/genreId>/i);
		my $genre = $1 if ($response->content =~ m/<genre>(.*?)<\/genre>/i);
		my $bitrate = $1 if ($response->content =~ m/<bitrate>(.*?)<\/bitrate>/i);
		
		my $logo = $1 if ($response->content =~ m/<logo>(.*?)<\/logo>/i);
		if ($musicService{ResolutionSubstitution}) {
			$logo =~ s//$musicService{ResolutionSubstitution}/;
		}
		
		my $subtitle = $1 if ($response->content =~ m/<subtitle>(.*?)<\/subtitle>/i);
		
		return $logo;
	} else {
		return '';
	}
}

########################################################################################
#
#  SONOS_ReadURL - Read the content of the given URL
#
# Parameter $url = The url, that has to be read
#
########################################################################################
sub SONOS_ReadURL($) {
	my ($url) = @_;
	
	my $ua = LWP::UserAgent->new(agent => $SONOS_USERAGENT);
	my $response = $ua->get($url);
	if ($response->is_success) {
		return $response->content;
	}
	
	return undef;
}

########################################################################################
#
#  SONOS_ReadFile - Read the content of the given filename
#
# Parameter $fileName = The filename, that has to be read
#
########################################################################################
sub SONOS_ReadFile($) {
	my ($fileName) = @_;

	if (-e $fileName) {
		my $fileContent = '';
		
		open IMGFILE, '<'.$fileName;
		binmode IMGFILE;
		while (<IMGFILE>){
			$fileContent .= $_;
		}
		close IMGFILE;
		
		return $fileContent;
	}
	
	return undef;
}

########################################################################################
#
#  SONOS_WriteFile - Write the content to the given filename
#
# Parameter $fileName = The filename, that has to be read
#
########################################################################################
sub SONOS_WriteFile($$) {
	my ($fileName, $data) = @_;
	
	open IMGFILE, '>'.$fileName;
	binmode IMGFILE;
	print IMGFILE $data;
	close IMGFILE;
}

########################################################################################
#
# SONOS_readingsBulkUpdateIfChanged - Wrapper for readingsBulkUpdate. Do only things if value has changed.
#
########################################################################################
sub SONOS_readingsBulkUpdateIfChanged($$$) {
	my ($hash, $readingName, $readingValue) = @_;
	
	return if (!defined($hash) || !defined($readingName) || !defined($readingValue));
	
	readingsBulkUpdate($hash, $readingName, $readingValue) if ReadingsVal($hash->{NAME}, $readingName, '~~ReAlLyNoTeQuAlSmArKeR~~') ne $readingValue;
}

########################################################################################
#
# SONOS_readingsBeginUpdate - Wrapper for readingsBeginUpdate.
#
########################################################################################
sub SONOS_readingsBeginUpdate($;$) {
	my ($hash, $fromSubProcess) = @_;
	
	readingsBeginUpdate($hash);
	
	if (defined($fromSubProcess)) {
		$SONOS_Module_BulkUpdateFromSubProcessInWork{$hash->{NAME}} = 1;
		SONOS_Log undef, 4, 'ReadingsBeginUpdate from SubProcess for "'.$hash->{NAME}.'"';
	} else {
		SONOS_Log undef, 4, 'ReadingsBeginUpdate from Module for "'.$hash->{NAME}.'"';
	}
}

########################################################################################
#
# SONOS_readingsEndUpdate - Wrapper for readingsEndUpdate.
#
########################################################################################
sub SONOS_readingsEndUpdate($$;$) {
	my ($hash, $doTrigger, $fromSubProcess) = @_;
	
	if ($SONOS_Module_BulkUpdateFromSubProcessInWork{$hash->{NAME}}) {
		if (defined($fromSubProcess)) {
			readingsEndUpdate($hash, $doTrigger);
			delete($SONOS_Module_BulkUpdateFromSubProcessInWork{$hash->{NAME}});
			SONOS_Log undef, 4, 'ReadingsEndUpdate from SubProcess for "'.$hash->{NAME}.'"';
		} else {
			SONOS_Log undef, 4, 'Supress ReadingsEndUpdate from Module due to running BulkUpdate from SubProcess for "'.$hash->{NAME}.'"';
		}
	} else {
		readingsEndUpdate($hash, $doTrigger);
		delete($SONOS_Module_BulkUpdateFromSubProcessInWork{$hash->{NAME}});
		
		if (defined($fromSubProcess)) {
			SONOS_Log undef, 4, 'ReadingsEndUpdate from SubProcess for "'.$hash->{NAME}.'"';
		} else {
			SONOS_Log undef, 4, 'ReadingsEndUpdate from Module for "'.$hash->{NAME}.'"';
		}
	}
}

########################################################################################
#
# SONOS_readingsSingleUpdate - Wrapper for readingsSingleUpdate.
#
########################################################################################
sub SONOS_readingsSingleUpdate($$$$) {
	my ($hash, $readingName, $readingValue, $doTrigger) = @_;
	
	if (defined($hash->{".updateTimestamp"})) {
		readingsBulkUpdate($hash, $readingName, $readingValue);
	} else {
		readingsSingleUpdate($hash, $readingName, $readingValue, $doTrigger);
	}
}

########################################################################################
#
# SONOS_readingsSingleUpdateIfChanged - Wrapper for readingsSingleUpdate. Do things only if value has changed.
#
########################################################################################
sub SONOS_readingsSingleUpdateIfChanged($$$$) {
	my ($hash, $readingName, $readingValue, $doTrigger) = @_;
	
	if (ReadingsVal($hash->{NAME}, $readingName, '~~ReAlLyNoTeQuAlSmArKeR~~') ne $readingValue) {
		if (defined($hash->{".updateTimestamp"})) {
			readingsBulkUpdate($hash, $readingName, $readingValue);
		} else {
			readingsSingleUpdate($hash, $readingName, $readingValue, $doTrigger);
		}
	}
}

########################################################################################
#
# SONOS_RefreshIconsInFHEMWEB - Refreshs Iconcache in all FHEMWEB-Instances
#
########################################################################################
sub SONOS_RefreshIconsInFHEMWEB($) {
	my ($dir) = @_;
	$dir = $attr{global}{modpath}.$dir;
	
	foreach my $fhem_dev (sort keys %main::defs) { 
		if ($main::defs{$fhem_dev}{TYPE} eq 'FHEMWEB') {
			eval('fhem(\'set '.$main::defs{$fhem_dev}{NAME}.' rereadicons\');');
			last; # Die Icon-Liste ist global, muss also nur einmal neu gelesen werden
		}
	}
}

########################################################################################
#
# SONOS_getAllSonosplayerDevices - Retreives all available/defined Sonosplayer-Devices
#
########################################################################################
sub SONOS_getAllSonosplayerDevices() {
	my @devices = ();
	
	foreach my $fhem_dev (sort keys %main::defs) { 
		push @devices, $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'SONOSPLAYER');
	}
	
	return @devices;
}

########################################################################################
#
# SONOS_getSonosPlayerByName - Retrieves the Def-Hash for the SONOS-Device (only one should exists, so this is OK)
#							or, if $devicename is given, the Def-Hash for the SONOSPLAYER with the given name.
#
# Parameter $devicename = SONOSPLAYER devicename to be searched for, undef if searching for SONOS instead
#
########################################################################################
sub SONOS_getSonosPlayerByName(;$) {
	my ($devicename) = @_;
	
	if (defined($devicename)) {
		foreach my $fhem_dev (keys %main::defs) {
			return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{NAME} eq $devicename);
		}
	} else {
		foreach my $fhem_dev (keys %main::defs) { 
			next if (!defined($main::defs{$fhem_dev}{TYPE}));
			return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'SONOS');
		}
	}
	
	SONOS_Log undef, 0, "The Method 'SONOS_getSonosPlayerByName' cannot find the FHEM-Device according to '".(defined($devicename) ? $devicename : 'undef')."'. This should not happen!";
	return undef;
}

########################################################################################
#
# SONOS_getSonosPlayerByUDN - Retrieves the Def-Hash for the SONOS-Device with the given UDN
#
########################################################################################
sub SONOS_getSonosPlayerByUDN(;$) {
	my ($udn) = @_;
	
	if (defined($udn)) {
		foreach my $fhem_dev (keys %main::defs) { 
			next if (!defined($main::defs{$fhem_dev}{TYPE}));
			return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'SONOSPLAYER' && $main::defs{$fhem_dev}{UDN} eq $udn);
		}
	} else {
		return SONOS_getSonosPlayerByName();
	}
	
	SONOS_Log $udn, 0, "The Method 'SONOS_getSonosPlayerByUDN' cannot find the FHEM-Device according to '".(defined($udn) ? $udn : 'undef')."'. This should not happen!";
	
	return undef;
}

########################################################################################
#
# SONOS_getSonosPlayerByRoomName - Retrieves the Def-Hash for the SONOS-Device with the given RoomName
#
########################################################################################
sub SONOS_getSonosPlayerByRoomName($) {
	my ($roomName) = @_;
	
	foreach my $fhem_dev (keys %main::defs) { 
		return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'SONOSPLAYER' && $main::defs{$fhem_dev}{READINGS}{roomName}{VAL} eq $roomName);
	}
	
	SONOS_Log undef, 0, "The Method 'SONOS_getSonosPlayerByRoomName' cannot find the FHEM-Device according to '".(defined($roomName) ? $roomName : 'undef')."'. This should not happen!";
	
	return undef;
}

########################################################################################
#
#  SONOS_Undef - Implements UndefFn function
#
#  Parameter hash = hash of the master, name
#
########################################################################################
sub SONOS_Undef($$) {
	my ($hash, $name) = @_;
	
	# Alle Timer entfernen...
	RemoveInternalTimer($hash);
	
	# SubProzess beenden, und Verbindung kappen...
	SONOS_StopSubProcess($hash);
	
	return undef;
}

########################################################################################
#
#  SONOS_Delete - Implements DeleteFn function
#
#  Parameter hash = hash of the master, name
#
########################################################################################
sub SONOS_Delete($$) {
	my ($hash, $name) = @_;
	
	# Erst alle SonosPlayer-Devices löschen
	for my $player (SONOS_getAllSonosplayerDevices()) {
		CommandDelete(undef, $player->{NAME});
	}
	
	# Etwas warten...
	select(undef, undef, undef, 1);
	
	# Das Entfernen des Sonos-Devices selbst übernimmt Fhem
	return undef;
}

########################################################################################
#
#  SONOS_Shutdown - Implements ShutdownFn function
#
#  Parameter hash = hash of the master, name
#
########################################################################################
sub SONOS_Shutdown ($$) {
	my ($hash) = @_;
  
	RemoveInternalTimer($hash);
	
	# Wenn wir einen eigenen UPnP-Server gestartet haben, diesen hier auch wieder beenden, 
	# ansonsten nur die Verbindung kappen
	if ($SONOS_StartedOwnUPnPServer) {
		DevIo_SimpleWrite($hash, "shutdown\n", 2);
	} else {
		DevIo_SimpleWrite($hash, "disconnect\n", 2);
	}
	DevIo_CloseDev($hash);
	
	select(undef, undef, undef, 2);
	
	return undef;
}

########################################################################################
#
#  SONOS_isInList - Checks, at which position the given value is in the given list
# 									Results in -1 if element not found
#
########################################################################################
sub SONOS_posInList {
	my($search, @list) = @_;
	$search = '' if (!defined($search));
	
	for (my $i = 0; $i <= $#list; $i++) {
		return $i if ($list[$i] && $search eq $list[$i]);
	}
	
	return -1;
}

########################################################################################
#
#  SONOS_isInList - Checks, if the given value is in the given list
#
########################################################################################
sub SONOS_isInList {
	my($search, @list) = @_;
	
	return 1 if SONOS_posInList($search, @list) >= 0;
	return 0;
}

########################################################################################
#
#  SONOS_Min - Retrieves the minimum of two values
#
########################################################################################
sub SONOS_Min($$) {
	$_[$_[0] > $_[1]]
}

########################################################################################
#
#  SONOS_Max - Retrieves the maximum of two values
#
########################################################################################
sub SONOS_Max($$) {
	$_[$_[0] < $_[1]]
}

########################################################################################
#
#  SONOS_URI_Escape - Escapes the given string.
#
########################################################################################
sub SONOS_URI_Escape($) {
	my ($txt) = @_;
	
	eval {
		$txt = uri_escape($txt);
	};
	if ($@) {
		$txt = uri_escape_utf8($txt);
	};
	
	return $txt;
}

########################################################################################
#
#  SONOS_GetRealPath - Retrieves the real (complete and absolute) path of the given file
#											 and converts all '\' to '/'
#
########################################################################################
sub SONOS_GetRealPath($) {
	my ($filename) = @_;
	my $realFilename = realpath($filename);
	
	$realFilename =~ s/\\/\//g;
	
	return $realFilename
}

########################################################################################
#
#  SONOS_GetAbsolutePath - Retreives the absolute path (without filename)
#
########################################################################################
sub SONOS_GetAbsolutePath($) {
	my ($filename) = @_;
	my $absFilename = SONOS_GetRealPath($filename);
	
	return substr($absFilename, 0, rindex($absFilename, '/'));
}

########################################################################################
#
#  SONOS_GetTimeFromString - Parse the given DateTime-String e.g. created by TimeNow().
#
########################################################################################
sub SONOS_GetTimeFromString($) {
	my ($timeStr) = @_;
	
	return 0 if (!defined($timeStr));
	
	eval {
		use Time::Local;
		if($timeStr =~ m/^(\d{4})-(\d{2})-(\d{2})( |_)([0-2]\d):([0-5]\d):([0-5]\d)$/) {
				return timelocal($7, $6, $5, $3, $2 - 1, $1 - 1900);
		}
	}
}

########################################################################################
#
#  SONOS_GetTimeString - Gets the String for the given time
#
########################################################################################
sub SONOS_GetTimeString($) {
	my ($time) = @_;
	
	my @t = localtime($time);
	
	return sprintf("%04d-%02d-%02d %02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

########################################################################################
#
#  SONOS_TimeNow - Same as FHEM.PL-TimeNow. Neccessary due to forked process...
#
########################################################################################
sub SONOS_TimeNow() {
	return SONOS_GetTimeString(time());
}

########################################################################################
#
#  SONOS_Log - Log to the normal Log-command with additional Infomations like Thread-ID and the prefix 'SONOS'
#
########################################################################################
sub SONOS_Log($$$) {
	my ($udn, $level, $text) = @_;
	
	if (defined($SONOS_ListenPort)) {
		if ($SONOS_Client_LogLevel >= $level) {
			my ($seconds, $microseconds) = gettimeofday();
			
			my @t = localtime($seconds);
			my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
			
			if($SONOS_mseclog) {
				$tim .= sprintf(".%03d", $microseconds / 1000);
			}
			
			if ($SONOS_Client_LogfileName eq '-') {
				print "$tim $level: SONOS".threads->tid().": $text\n";
			} else {
				open(my $fh, '>>', $SONOS_Client_LogfileName);
				print $fh "$tim $level: SONOS".threads->tid().": $text\n";
				close $fh;
			}
		}
	} else {
		my $hash = SONOS_getSonosPlayerByUDN($udn);
		
		eval {
			Log3 $hash->{NAME}, $level, 'SONOS'.threads->tid().': '.$text;
		};
		if ($@) {
			Log $level, 'SONOS'.threads->tid().': '.$text;
		}
	}
}

########################################################################################
########################################################################################
##
##  Start of Telnet-Server-Part for Sonos UPnP-Messages
##
##  If SONOS_ListenPort is defined, then we have to start a listening server
##
########################################################################################
########################################################################################
# Here starts the main-loop of the telnet-server
########################################################################################
if (defined($SONOS_ListenPort)) {
	$| = 1;
	
	my $runEndlessLoop = 1;
	my $lastRenewSubscriptionCheckTime = time();
	
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'CHLD'} = 'IGNORE';
	
	$SIG{'INT'} = sub {
		# Hauptschleife beenden
		$runEndlessLoop = 0;
		
		# Sub-Threads beenden, sofern vorhanden
		if (($SONOS_Thread != -1) && defined(threads->object($SONOS_Thread))) {
			threads->object($SONOS_Thread)->kill('INT')->detach();
		}
		if (($SONOS_Thread_IsAlive != -1) && defined(threads->object($SONOS_Thread_IsAlive))) {
			threads->object($SONOS_Thread_IsAlive)->kill('INT')->detach();
		}
		if (($SONOS_Thread_PlayerRestore != -1) && defined(threads->object($SONOS_Thread_PlayerRestore))) {
			threads->object($SONOS_Thread_PlayerRestore)->kill('INT')->detach();
		}
	};
	
	my $sock;
	my $retryCounter = 10;
	do {
		eval {
			socket($sock, AF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "Could not create socket: $!";
			bind($sock, sockaddr_in($SONOS_ListenPort, INADDR_ANY)) or die "Bind failed: $!";
			setsockopt($sock, SOL_SOCKET, SO_LINGER, pack("ii", 1, 0)) or die "Setsockopt failed: $!";
			listen($sock, 10);
		};
		if ($@) {
			SONOS_Log undef, 0, "Can't bind Port $SONOS_ListenPort: $@";
			SONOS_Log undef, 0, 'Retries left (wait 30s): '.--$retryCounter;
			
			if (!$retryCounter) {
				die 'Bind failed...';
			}
			
			select(undef, undef, undef, 30);
		}
	} while ($@);
	SONOS_Log undef, 1, "$0 is listening to Port $SONOS_ListenPort";
	
	# Accept incoming connections and talk to clients
	$SONOS_Client_Selector = IO::Select->new($sock);
	
	while ($runEndlessLoop) {
		# Nachschauen, ob Subscriptions erneuert werden müssen
		if (time() - $lastRenewSubscriptionCheckTime > 1800) {
			$lastRenewSubscriptionCheckTime = time ();
			
			foreach my $udn (@{$SONOS_Client_Data{PlayerUDNs}}) {
				my %data;
				$data{WorkType} = 'renewSubscription';
				$data{UDN} = $udn;
				my @params = ();
				$data{Params} = \@params;
				
				$SONOS_ComObjectTransportQueue->enqueue(\%data);
			}
		}
	 	
	 	# Alle Bereit-Schreibenden verarbeiten
	 	if ($SONOS_Client_SendQueue->pending() && !$SONOS_Client_SendQueue_Suspend) {
	 		my @receiver = $SONOS_Client_Selector->can_write(0);
	 		
	 		# Prüfen, ob überhaupt ein Empfänger bereit ist. Sonst würden Befehle verloren gehen...
	 		if (scalar(@receiver) > 0) {
		 		while ($SONOS_Client_SendQueue->pending()) {
					my $line = $SONOS_Client_SendQueue->dequeue();
					foreach my $so (@receiver) {
						send($so, $line, 0);
					}
				}
			}
		}
	 	
	 	# Alle Bereit-Lesenden verarbeiten
		# Das ganze blockiert eine kurze Zeit, um nicht 100% CPU-Last zu erzeugen
		# Das bedeutet aber auch, dass Sende-Vorgänge um maximal den Timeout-Wert verzögert werden
		my @ready = $SONOS_Client_Selector->can_read(0.1);
		for (my $i = 0; $i < scalar(@ready); $i++) {
			my $so = $ready[$i];
	 		if ($so == $sock) { # New Connection read
	 			my $client;
	 			
	 			my $addrinfo = accept($client, $sock);
				setsockopt($client, SOL_SOCKET, SO_LINGER, pack("ii", 1, 0));
	 			my ($port, $iaddr) = sockaddr_in($addrinfo);
	 			my $name = gethostbyaddr($iaddr, AF_INET);
	 			$name = $iaddr if (!defined($name) || $name eq '');
	 			
	 			SONOS_Log undef, 3, "Connection accepted from $name:$port";
	 			
	 			# Send Welcome-Message
	 			send($client, "This is UPnP-Server listening for commands\r\n", 0);
	 			select(undef, undef, undef, 0.5);
	 			
	 			# Antwort lesen, und nur wenn es eine dauerhaft gedachte Verbindung ist, dann auch merken...
	 			my $answer = '';
	 			recv($client, $answer, 500, 0);
	 			if ($answer eq "Establish connection\r\n") {
	 				$SONOS_Client_Selector->add($client);
	 			}
	 		} else { # Existing client calling
	 			if (!$so->opened()) {
	 				$SONOS_Client_Selector->remove($so);
	 				next;
	 			}
	 			
	 			my $inp = <$so>;
	 			
	 			if (defined($inp)) {
		 			# Abschließende Zeilenumbrüche abschnippeln
		 			$inp =~ s/[\r\n]*$//;
		 			
		 			# Consume and send evt. reply
		 			SONOS_Log undef, 5, "Received: '$inp'";
		 			SONOS_Client_ConsumeMessage($so, $inp);
		 		}
	 		}
	 	}
	}
	 
	SONOS_Log undef, 0, 'Das Lauschen auf der Schnittstelle wurde beendet. Prozess endet nun auch...';
	
	# Alle Handles entfernen und schliessen...
	for my $cl ($SONOS_Client_Selector->handles()) {
		$SONOS_Client_Selector->remove($cl);
		shutdown($cl, 2);
		close($cl);
	}
	
	# Prozess beenden...
	exit(0);
}

# Wird für den FHEM-Modulpart benötigt
1;

########################################################################################
# SONOS_Client_Thread_Notifier: Notifies all clients with the given message
########################################################################################
sub SONOS_Client_Notifier($) {
	my ($msg) = @_;
	$| = 1;
	
	state $setCurrentUDN;
	
	# Wenn hier ein SetCurrent ausgeführt werden soll, dann auch den lokalen Puffer aktualisieren
	if ($msg =~ m/SetCurrent:(.*?):(.*)/) {
		my $udnBuffer = ($setCurrentUDN eq 'undef') ? 'SONOS' : $setCurrentUDN;
		$SONOS_Client_Data{Buffer}->{$udnBuffer}->{$1} = $2;
	} elsif ($msg =~ m/GetReadingsToCurrentHash:(.*?):(.*)/) {
		$setCurrentUDN = $1;
	}
	
	SONOS_Log undef, 4, "SONOS_Client_Notifier($msg)" if ($msg !~ m/^Readings(Bulk|Single)Update/i);
	
	# Immer ein Zeilenumbruch anfügen...
	$msg .= "\n" if (substr($msg, -1, 1) ne "\n");
	
	$SONOS_Client_SendQueue->enqueue($msg);
}

########################################################################################
# SONOS_Client_Data_Retreive: Retrieves stored data.
########################################################################################
sub SONOS_Client_Data_Retreive($$$$;$) {
	my ($udn, $reading, $name, $default, $nologging) = @_;
	$udn = '' if (!defined($udn));
	$nologging = 0 if (!defined($nologging));
	
	my $udnBuffer = ($udn eq 'undef') ? 'SONOS' : $udn;
	
	return $default if (!defined($SONOS_Client_Data{Buffer}));
	
	# Prüfen, ob die Anforderung überhaupt bedient werden darf
	if ($reading eq 'attr') {
		if (SONOS_posInList($name, @SONOS_PossibleAttributes) == -1) {
			SONOS_Log undef, 0, "Ungültige Attribut-Fhem-Informationsanforderung: $udnBuffer->$name.\nStoppe Prozess!";
			exit(1);
		}
	} elsif ($reading eq 'def') {
		if (SONOS_posInList($name, @SONOS_PossibleDefinitions) == -1) {
			SONOS_Log undef, 0, "Ungültige Definitions-Fhem-Informationsanforderung: $udnBuffer->$name.\nStoppe Prozess!";
			exit(1);
		}
	} elsif ($reading eq 'udn') {
	} else {
		if (SONOS_posInList($name, @SONOS_PossibleReadings) == -1) {
			SONOS_Log undef, 0, "Ungültige Reading-Fhem-Informationsanforderung: $udnBuffer->$name.\nStoppe Prozess!";
			exit(1);
		}
	}
	
	# Anfrage zulässig, also ausliefern...
	if (defined($SONOS_Client_Data{Buffer}->{$udnBuffer}) && defined($SONOS_Client_Data{Buffer}->{$udnBuffer}->{$name})) {
		SONOS_Log undef, 4, "SONOS_Client_Data_Retreive($udnBuffer, $reading, $name, $default) -> ".$SONOS_Client_Data{Buffer}->{$udnBuffer}->{$name} if (!$nologging);
		return $SONOS_Client_Data{Buffer}->{$udnBuffer}->{$name};
	} else {
		SONOS_Log undef, 4, "SONOS_Client_Data_Retreive($udnBuffer, $reading, $name, $default) -> DEFAULT" if (!$nologging);
		return $default;
	}
}

########################################################################################
# SONOS_Client_Data_Refresh: Send data and refreshs buffer
########################################################################################
sub SONOS_Client_Data_Refresh($$$$) {
	my ($sendCommand, $udn, $name, $value) = @_;
	
	my $udnBuffer = ($udn eq 'undef') ? 'SONOS' : $udn;
	
	SONOS_Log undef, 4, "SONOS_Client_Data_Refresh(".(defined($sendCommand) ? $sendCommand : 'undef').", $udn, $name, $value)";
	
	$SONOS_Client_Data{Buffer}->{$udnBuffer}->{$name} = $value;
	if (defined($sendCommand) && ($sendCommand ne '')) {
		SONOS_Client_Notifier($sendCommand.':'.$udn.':'.$name.':'.$value);
	}
}

########################################################################################
# SONOS_Client_ConsumeMessage: Consumes the given message and give an evt. return
########################################################################################
sub SONOS_Client_ConsumeMessage($$) {
	my ($client, $msg) = @_;
	
	if (lc($msg) eq 'disconnect' || lc($msg) eq 'shutdown') {
		SONOS_Log undef, 3, "Disconnecting client and shutdown server..." if (lc($msg) eq 'shutdown');
		SONOS_Log undef, 3, "Disconnecting client..." if (lc($msg) ne 'shutdown');
		
		$SONOS_Client_Selector->remove($client);
		
		if ($SONOS_Thread != -1) {
			my $thr = threads->object($SONOS_Thread);
			
			if ($thr) {
				SONOS_Log undef, 3, 'Trying to kill Sonos_Thread...';
				$thr->kill('INT')->detach();
			} else {
				SONOS_Log undef, 3, 'Sonos_Thread is already killed!';
			}
		}
		if ($SONOS_Thread_IsAlive != -1) {
			my $thr = threads->object($SONOS_Thread_IsAlive);
			
			if ($thr) {
				SONOS_Log undef, 3, 'Trying to kill IsAlive_Thread...';
				$thr->kill('INT')->detach();
			} else {
				SONOS_Log undef, 3, 'IsAlive_Thread is already killed!';
			}
		}
		if ($SONOS_Thread_PlayerRestore != -1) {
			my $thr = threads->object($SONOS_Thread_PlayerRestore);
			
			if ($thr) {
				SONOS_Log undef, 3, 'Trying to kill PlayerRestore_Thread...';
				$thr->kill('INT')->detach();
			} else {
				SONOS_Log undef, 3, 'PlayerRestore_Thread is already killed!';
			}
		}
		
		shutdown($client, 2);
		close($client);
		
		threads->self()->kill('INT') if (lc($msg) eq 'shutdown');
	} elsif (lc($msg) eq 'hello') {
		send($client, "OK\r\n", 0);
	} elsif (lc($msg) eq 'goaway') {
		$SONOS_Client_Selector->remove($client);
		shutdown($client, 2);
		close($client);
	} elsif ($msg =~ m/SetData:(.*?):(.*?):(.*?):(.*?):(.*?):(.*?):(.*?):(.*?):(.*)/i) {
		$SONOS_Client_Data{SonosDeviceName} = $1;
		$SONOS_Client_LogLevel = $2;
		$SONOS_Client_LogfileName = $3;
		$SONOS_Client_Data{pingType} = $4;
		
		my @usedonlyIPs = split(/,/, $5);
		$SONOS_Client_Data{usedonlyIPs} = shared_clone(\@usedonlyIPs);
		for my $elem (@usedonlyIPs) {
			$usedonlyIPs{SONOS_Trim($elem)} = 1;
		}
		
		my @ignoredIPs = split(/,/, $6);
		$SONOS_Client_Data{ignoredIPs} = shared_clone(\@ignoredIPs);
		for my $elem (@ignoredIPs) {
			$ignoredIPs{SONOS_Trim($elem)} = 1;
		}
		
		$reusePort = $7;
		
		my @names = split(/,/, $8);
		$SONOS_Client_Data{PlayerNames} = shared_clone(\@names);
		
		my @udns = split(/,/, $9);
		$SONOS_Client_Data{PlayerUDNs} = shared_clone(\@udns);
		
		my @playeralive = ();
		$SONOS_Client_Data{PlayerAlive} = shared_clone(\@playeralive);
		
		my %player = ();
		$SONOS_Client_Data{Buffer} = shared_clone(\%player);
		
		my %udnValues = ();
		$SONOS_Client_Data{Buffer}->{udn} = shared_clone(\%udnValues);
		
		push @udns, 'SONOS';
		foreach my $elem (@udns) {
			my %elemValues = ();
			$SONOS_Client_Data{Buffer}->{$elem} = shared_clone(\%elemValues);
			$SONOS_Client_Data{Buffer}->{udn}->{$1} = $elem;
		}
	} elsif ($msg =~ m/SetValues:(.*?):(.*)/i) {
		my $deviceName = $1;
		my $deviceValues = $2;
		my %elemValues = ();
		
		# Werte aus der Übergabe belegen
		foreach my $elem (split(/\|/, $deviceValues)) { 
			if ($elem =~ m/(.*?)=(.*)/) {
				$elemValues{$1} = uri_unescape($2);
				
				if ($1 eq 'bookmarkPlaylistDefinition') {
					# <Gruppenname>:<PlayerDeviceRegEx>:<MinListLength>:<MaxListLength>:<MaxAge> [...]
					%SONOS_BookmarkQueueDefinition = ();
					my $def = $elemValues{$1};
					
					foreach my $elem (split(/ /, $def)) {
						# Sicherstellen, das alle Stellen vorhanden sind...
						$elem .= ':' while (SONOS_CountInString(':', $elem) < 5);
						
						# Zerlegen
						if ($elem =~ m/(.*?):(.*?):(\d*):(\d*):(.*?):(.*)/) {
							my $key = $1;
							$SONOS_BookmarkQueueDefinition{$key}{PlayerDeviceRegEx} = ($2 ne '') ? $2 : '.*';
							$SONOS_BookmarkQueueDefinition{$key}{MinListLength} = ($3 ne '') ? $3 : 0;
							$SONOS_BookmarkQueueDefinition{$key}{MaxListLength} = ($4 ne '') ? $4 : 99999;
							$SONOS_BookmarkQueueDefinition{$key}{MaxAge} = ($5 ne '') ? $5 : '28*24*60*60';
							$SONOS_BookmarkQueueDefinition{$key}{ReadOnly} = ($6 ne '') ? $6 : 0;
							
							# RegEx prüfen
							eval { "" =~ m/$SONOS_BookmarkQueueDefinition{$key}{PlayerDeviceRegEx}/ };
							if($@) {
								SONOS_Log undef, 0, 'SetData - bookmarkPlaylistDefinition: Bad PlayerDeviceRegExp "'.$SONOS_BookmarkQueueDefinition{$key}{PlayerDeviceRegEx}.'": '.$@;
								delete($SONOS_BookmarkQueueDefinition{$key});
								next;
							}
							
							# MaxAge berechnen...
							eval { $SONOS_BookmarkQueueDefinition{$key}{MaxAge} = eval($SONOS_BookmarkQueueDefinition{$key}{MaxAge}); };
							if($@) {
								SONOS_Log undef, 0, 'SetData - bookmarkPlaylistDefinition: Bad MaxAge "'.$SONOS_BookmarkQueueDefinition{$key}{MaxAge}.'": '.$@;
								delete($SONOS_BookmarkQueueDefinition{$key});
								next;
							}
						}
					}
					
					SONOS_Log undef, 4, 'BookmarkPlaylistDefinition: '.Dumper(\%SONOS_BookmarkQueueDefinition);
				}
				
				if ($1 eq 'bookmarkTitleDefinition') {
					# <Gruppenname>:<PlayerdeviceRegEx>:<TrackURIRegEx>:<MinTitleLength>:<RemainingLength>:<MaxAge>:<ReadOnly> [...]
					%SONOS_BookmarkTitleDefinition = ();
					my $def = $elemValues{$1};
					
					foreach my $elem (split(/ /, $def)) {
						# Sicherstellen, das alle Stellen vorhanden sind...
						$elem .= ':' while (SONOS_CountInString(':', $elem) < 6);
						
						# Zerlegen
						if ($elem =~ m/(.*?):(.*?):(.*?):(\d*):(\d*):(.*?):(.*)/) {
							my $key = $1;
							$SONOS_BookmarkTitleDefinition{$key}{PlayerDeviceRegEx} = ($2 ne '') ? $2 : '.*';
							$SONOS_BookmarkTitleDefinition{$key}{TrackURIRegEx} = ($3 ne '') ? $3 : '.*';
							$SONOS_BookmarkTitleDefinition{$key}{MinTitleLength} = ($4 ne '') ? $4 : 60;
							$SONOS_BookmarkTitleDefinition{$key}{RemainingLength} = ($5 ne '') ? $5 : 10;
							$SONOS_BookmarkTitleDefinition{$key}{MaxAge} = ($6 ne '') ? $6 : '28*24*60*60';
							$SONOS_BookmarkTitleDefinition{$key}{ReadOnly} = 0;
							$SONOS_BookmarkTitleDefinition{$key}{ReadOnly} = 1 if (lc($7) eq 'readonly');
							$SONOS_BookmarkTitleDefinition{$key}{Chapter} = 0;
							$SONOS_BookmarkTitleDefinition{$key}{Chapter} = 1 if (lc($7) eq 'chapter');
							
							# RegEx prüfen...
							eval { "" =~ m/$SONOS_BookmarkTitleDefinition{$key}{PlayerDeviceRegEx}/ };
							if($@) {
								SONOS_Log undef, 0, 'SetData - bookmarkTitleDefinition: Bad PlayerDeviceRegExp "'.$SONOS_BookmarkTitleDefinition{$key}{PlayerDeviceRegEx}.'": '.$@;
								delete($SONOS_BookmarkTitleDefinition{$key});
								next;
							}
							
							# RegEx prüfen...
							eval { "" =~ m/$SONOS_BookmarkTitleDefinition{$key}{TrackURIRegEx}/ };
							if($@) {
								SONOS_Log undef, 0, 'SetData - bookmarkTitleDefinition: Bad TrackURIRegEx "'.$SONOS_BookmarkTitleDefinition{$key}{TrackURIRegEx}.'": '.$@;
								delete($SONOS_BookmarkTitleDefinition{$key});
								next;
							}
							
							# MaxAge berechnen...
							eval { $SONOS_BookmarkTitleDefinition{$key}{MaxAge} = eval($SONOS_BookmarkTitleDefinition{$key}{MaxAge}); };
							if($@) {
								SONOS_Log undef, 0, 'SetData - bookmarkTitleDefinition: Bad MaxAge "'.$SONOS_BookmarkTitleDefinition{$key}{MaxAge}.'": '.$@;
								delete($SONOS_BookmarkTitleDefinition{$key});
								next;
							}
						}
					}
					
					SONOS_Log undef, 4, 'BookmarkTitleDefinition: '.Dumper(\%SONOS_BookmarkTitleDefinition);
				}
			}
		}
		 
		$SONOS_Client_Data{Buffer}->{$deviceName} = shared_clone(\%elemValues);
	} elsif ($msg =~ m/DoWork:(.*?):(.*?):(.*)/i) {
		my %data;
		$data{WorkType} = $2;
		$data{UDN} = $1;
		
		if (defined($3)) {
			my @params = split(/--#--/, decode_utf8($3));
			$data{Params} = \@params;
		} else {
			my @params = ();
			$data{Params} = \@params;
		}
		
		# Auf die Queue legen wenn Thread läuft und Signalhandler aufrufen, wenn er nicht sowieso noch läuft...
		if ($SONOS_Thread != -1) {
			$SONOS_ComObjectTransportQueue->enqueue(\%data);
			#threads->object($SONOS_Thread)->kill('HUP') if ($SONOS_ComObjectTransportQueue->pending() == 1);
		}
	} elsif (lc($msg) eq 'startthread') {
		# Discover-Thread
		$SONOS_Thread = threads->create(\&SONOS_Discover)->tid();
		
		# IsAlive-Checker-Thread
		if (lc($SONOS_Client_Data{pingType}) ne 'none') {
			$SONOS_Thread_IsAlive = threads->create(\&SONOS_Client_IsAlive)->tid();
		}
		
		# Playerrestore-Thread
		$SONOS_Thread_PlayerRestore = threads->create(\&SONOS_RestoreOldPlaystate)->tid();
	} else {
		SONOS_Log undef, 2, "ConsumMessage: Sorry. I don't understand you - '$msg'.";
		send($client, "Sorry. I don't understand you - '$msg'.\r\n", 0);
	}
}

########################################################################################
# SONOS_getBookmarkGroupKeys: Retrieves the approbriate GroupKeys to the given UDN
########################################################################################
sub SONOS_getBookmarkGroupKeys($$;$) {
	my ($type, $udn, $disabled) = @_;
	$disabled = 0 if (!defined($disabled));
	
	my $deviceName = SONOS_Client_Data_Retreive($udn, 'def', 'NAME', $udn);
	
	my @result = ();
	my $hashList = \%SONOS_BookmarkTitleDefinition;
	$hashList = \%SONOS_BookmarkQueueDefinition if (lc($type) eq 'queue');
	
	foreach my $key (keys %{$hashList}) {
		if ($deviceName =~ m/$hashList->{$key}{PlayerDeviceRegEx}/) {
			push(@result, $key) if (!$disabled && (!defined($hashList->{$key}{Disabled}) || !$hashList->{$key}{Disabled}));
			push(@result, $key) if ($disabled && defined($hashList->{$key}{Disabled}) && $hashList->{$key}{Disabled});
		}
	}
	
	return @result;
}

########################################################################################
# SONOS_Client_IsAlive: Checks of the clients are already available
########################################################################################
sub SONOS_Client_IsAlive() {
	my $interval = SONOS_Max(10, SONOS_Client_Data_Retreive('undef', 'def', 'INTERVAL', 0));
	my $stepInterval = 0.5;
	
	SONOS_Log undef, 1, 'IsAlive-Thread gestartet. Warte 120 Sekunden und pruefe dann alle '.$interval.' Sekunden...';
	
	my $runEndlessLoop = 1;
	
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'CHLD'} = 'IGNORE';
	
	$SIG{'INT'} = sub {
		$runEndlessLoop = 0;
	};
	
	# Erst nach einer Weile wartens anfangen zu arbeiten. Bis dahin sollten alle Player im Netz erkannt, und deren Konfigurationen bekannt sein.
	my $counter = 0;
	do {
		select(undef, undef, undef, 0.5);
	} while (($counter++ < 240) && $runEndlessLoop);
	
	my $stepCounter = 0;
	while($runEndlessLoop) {
		select(undef, undef, undef, $stepInterval);
		
		next if (($stepCounter += $stepInterval) < $interval);
		$stepCounter = 0;
		
		# Alle bekannten Player durchgehen, wenn der Thread nicht beendet werden soll
		if ($runEndlessLoop) {
			my @list = @{$SONOS_Client_Data{PlayerAlive}};
			my @toAnnounce = ();
			for(my $i = 0; $i <= $#list; $i++) {
				next if (!$list[$i]);
				
				if (!SONOS_IsAlive($list[$i])) {
					# Auf die Entfernen-Meldeliste setzen
					push @toAnnounce, $list[$i];
					
					# Wenn er nicht mehr am Leben ist, dann auch aus der Aktiven-Liste entfernen
					delete @{$SONOS_Client_Data{PlayerAlive}}[$i];
				}
			}
			
			# Wenn ein Player gerade verschwunden ist, dann dem (verbleibenden) Sonos-System das mitteilen
			foreach my $toDeleteElem (@toAnnounce) {
				if ($toDeleteElem =~ m/(^.*)_/) {
					$toDeleteElem = $1;
					SONOS_Log undef, 3, 'ReportUnresponsiveDevice: '.$toDeleteElem;
					foreach my $udn (@{$SONOS_Client_Data{PlayerAlive}}) {
						next if (!$udn);
						
						my %data;
						$data{WorkType} = 'reportUnresponsiveDevice';
						$data{UDN} = $udn;
						my @params = ();
						push @params, $toDeleteElem;
						$data{Params} = \@params;
						
						$SONOS_ComObjectTransportQueue->enqueue(\%data);
						
						# Da ich das nur an den ersten verfügbaren Player senden muss, kann hier die Schleife direkt beendet werden
						last;
					}
				}
			}
		}
	}
	
	SONOS_Log undef, 1, 'IsAlive-Thread wurde beendet.';
	$SONOS_Thread_IsAlive = -1;
}
########################################################################################
########################################################################################
##
##  End of Telnet-Server-Part for Sonos UPnP-Messages
##
########################################################################################
########################################################################################


=pod
=item summary    Module to commmunicate with a Sonos-System via UPnP
=item summary_DE Modul für die Kommunikation mit einem Sonos-System mittels UPnP
=begin html

<a name="SONOS"></a>
<h3>SONOS</h3>
<p>FHEM-Module to communicate with the Sonos-System via UPnP</p>
<p>For more informations have also a closer look at the wiki at <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a></p>
<p>For correct functioning of this module it is neccessary to have some Perl-Modules installed, which are eventually installed already manually:<ul>
<li><code>LWP::Simple</code></li>
<li><code>LWP::UserAgent</code></li>
<li><code>SOAP::Lite</code></li>
<li><code>HTTP::Request</code></li></ul>
Installation e.g. as Debian-Packages (via "sudo apt-get install &lt;packagename&gt;"):<ul>
<li>LWP::Simple-Packagename (incl. LWP::UserAgent and HTTP::Request): libwww-perl</li>
<li>SOAP::Lite-Packagename: libsoap-lite-perl</li></ul>
<br />Installation e.g. as Windows ActivePerl (via Perl-Packagemanager)<ul>
<li>Install Package LWP (incl. LWP::UserAgent and HTTP::Request)</li>
<li>Install Package SOAP::Lite</li>
<li>SOAP::Lite-Special for Versions after 5.18:<ul>
  <li>Add another Packagesource from suggestions or manual: Bribes de Perl (http://www.bribes.org/perl/ppm)</li>
  <li>Install Package: SOAP::Lite</li></ul></li></ul>
<b>Windows ActivePerl 5.20 does currently not work due to missing SOAP::Lite</b></p>
<p><b>Attention!</b><br />This Module will not work on any platform, because of the use of Threads and the neccessary Perl-modules.</p>
<p>More information is given in a (german) Wiki-article: <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a></p>
<p>The system consists of two different components:<br />
1. A UPnP-Client which runs as a standalone process in the background and takes the communications to the sonos-components.<br />
2. The FHEM-module itself which connects to the UPnP-client to make fhem able to work with sonos.<br /><br />
The client will be started by the module itself if not done in another way.<br />
You can start this client on your own (to let it run instantly and independent from FHEM):<br />
<code>perl 00_SONOS.pm 4711</code>: Starts a UPnP-Client in an independant way who listens to connections on port 4711. This process can run a long time, FHEM can connect and disconnect to it.</p>
<h4>Example</h4>
<p>
Simplest way to define:<br />
<b><code>define Sonos SONOS</code></b>
</p>
<p>
Example with control over the used port and the isalive-checker-interval:<br />
<b><code>define Sonos SONOS localhost:4711 45</code></b>
</p>
<a name="SONOSdefine"></a>
<h4>Define</h4>
<b><code>define &lt;name&gt; SONOS [upnplistener [interval [waittime [delaytime]]]]</code></b>
        <br /><br /> Define a Sonos interface to communicate with a Sonos-System.<br />
<p>
<b><code>[upnplistener]</code></b><br />The name and port of the external upnp-listener. If not given, defaults to <code>localhost:4711</code>. The port has to be a free portnumber on your system. If you don't start a server on your own, the script does itself.<br />If you start it yourself write down the correct informations to connect.</p>
<p>
<b><code>[interval]</code></b><br /> The interval is for alive-checking of Zoneplayer-device, because no message come if the host disappear :-)<br />If omitted a value of 10 seconds is the default.</p>
<p>
<b><code>[waittime]</code></b><br /> With this value you can configure the waiting time for the starting of the Subprocess.</p>
<p>
<b><code>[delaytime]</code></b><br /> With this value you can configure a delay time before starting the network-part.</p>
<a name="SONOSset"></a>
<h4>Set</h4>
<ul>
<li><b>Common Tasks</b><ul>
<li><a name="SONOS_setter_RefreshShareIndex">
<b><code>RefreshShareIndex</code></b></a>
<br />Starts the refreshing of the library.</li>
<li><a name="SONOS_setter_RescanNetwork">
<b><code>RescanNetwork</code></b></a>
<br />Restarts the player discovery.</li>
</ul></li>
<li><b>Control-Commands</b><ul>
<li><a name="SONOS_setter_Mute">
<b><code>Mute &lt;state&gt;</code></b></a>
<br />Sets the mute-state on all players.</li>
<li><a name="SONOS_setter_PauseAll">
<b><code>PauseAll</code></b></a>
<br />Pause all Zoneplayer.</li>
<li><a name="SONOS_setter_Pause">
<b><code>Pause</code></b></a>
<br />Alias for PauseAll.</li>
<li><a name="SONOS_setter_StopAll">
<b><code>StopAll</code></b></a>
<br />Stops all Zoneplayer.</li>
<li><a name="SONOS_setter_Stop">
<b><code>Stop</code></b></a>
<br />Alias for StopAll.</li>
</ul></li>
<li><b>Bookmark-Commands</b><ul>
<li><a name="SONOS_setter_DisableBookmark">
<b><code>DisableBookmark &lt;Groupname&gt;</code></b></a>
<br />Disables the group with the given name.</li>
<li><a name="SONOS_setter_EnableBookmark">
<b><code>EnableBookmark &lt;Groupname&gt;</code></b></a>
<br />Enables the group with the given name.</li>
<li><a name="SONOS_setter_LoadBookmarks">
<b><code>LoadBookmarks [Groupname]</code></b></a>
<br />Loads the given group (or all if parameter not set) from the filesystem.</li>
<li><a name="SONOS_setter_SaveBookmarks">
<b><code>SaveBookmarks [Groupname]</code></b></a>
<br />Saves the given group (or all if parameter not set) to the filesystem.</li>
</ul></li>
<li><b>Group-Commands</b><ul>
<li><a name="SONOS_setter_Groups">
<b><code>Groups &lt;GroupDefinition&gt;</code></b></a>
<br />Sets the current groups on the whole Sonos-System. The format is the same as retreived by getter 'Groups'.<br >A reserved word is <i>Reset</i>. It can be used to directly extract all players out of their groups.</li>
</ul></li>
</ul>
<a name="SONOSget"></a> 
<h4>Get</h4>
<ul>
<li><b>Group-Commands</b><ul>
<li><a name="SONOS_getter_Groups">
<b><code>Groups</code></b></a>
<br />Retreives the current group-configuration of the Sonos-System. The format is a comma-separated List of Lists with devicenames e.g. <code>[Sonos_Kueche], [Sonos_Wohnzimmer, Sonos_Schlafzimmer]</code>. In this example there are two groups: the first consists of one player and the second consists of two players.<br />
The order in the sublists are important, because the first entry defines the so-called group-coordinator (in this case <code>Sonos_Wohnzimmer</code>), from which the current playlist and the current title playing transferred to the other member(s).</li>
</ul></li>
</ul>
<a name="SONOSattr"></a>
<h4>Attributes</h4>
'''Attention'''<br />The most of the attributes can only be used after a restart of fhem, because it must be initially transfered to the subprocess.
<ul>
<li><b>Common</b><ul>
<li><a name="SONOS_attribut_coverLoadTimeout"><b><code>coverLoadTimeout &lt;value&gt;</code></b>
</a><br />One of (0..10,15,20,25,30). Defines the timeout for waiting of the Sonosplayer for Cover-Downloads. Defaults to 5.</li>
<li><a name="SONOS_attribut_deviceRoomView"><b><code>deviceRoomView &lt;Both|DeviceLineOnly&gt;</code></b>
</a><br /> Defines the style of the Device in the room overview. <code>Both</code> means "normal" Deviceline incl. Cover-/Titleview and maybe the control area, <code>DeviceLineOnly</code> means only the "normal" Deviceline-view.</li>
<li><a name="SONOS_attribut_disable"><b><code>disable &lt;value&gt;</code></b>
</a><br />One of (0,1). With this value you can disable the whole module. Works immediatly. If set to 1 the subprocess will be terminated and no message will be transmitted. If set to 0 the subprocess is again started.<br />It is useful when you install new Sonos-Components and don't want any disgusting devices during the Sonos setup.</li>
<li><a name="SONOS_attribut_getFavouritesListAtNewVersion"><b><code>getFavouritesListAtNewVersion &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute set, the module will refresh the Favourites-List automatically upon changes (if the Attribute <code>getListsDirectlyToReadings</code> is set).</li>
<li><a name="SONOS_attribut_getPlaylistsListAtNewVersion"><b><code>getPlaylistsListAtNewVersion &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute set, the module will refresh the Playlists-List automatically upon changes (if the Attribute <code>getListsDirectlyToReadings</code> is set).</li>
<li><a name="SONOS_attribut_getQueueListAtNewVersion"><b><code>getQueueListAtNewVersion &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute set, the module will refresh the current Queue-List automatically upon changes (if the Attribute <code>getListsDirectlyToReadings</code> is set).</li>
<li><a name="SONOS_attribut_getRadiosListAtNewVersion"><b><code>getRadiosListAtNewVersion &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute set, the module will refresh the Radios-List automatically upon changes (if the Attribute <code>getListsDirectlyToReadings</code> is set).</li>
<li><a name="SONOS_attribut_getListsDirectlyToReadings"><b><code>getListsDirectlyToReadings &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute you can define that the module fills the readings for the lists of Favourites, Playlists, Radios and the Queue directly without the need of userReadings.</li>
<li><a name="SONOS_attribut_getLocalCoverArt"><b><code>getLocalCoverArt &lt;value&gt;</code></b>
</a><br />One of (0,1). With this attribute the loads and saves the Coverart locally (default till now).</li>
<li><a name="SONOS_attribut_ignoredIPs"><b><code>ignoredIPs &lt;IP-Address&gt;[,IP-Address]</code></b>
</a><br />With this attribute you can define IP-addresses, which has to be ignored by the UPnP-System of this module. e.g. "192.168.0.11,192.168.0.37"</li>
<li><a name="SONOS_attribut_pingType"><b><code>pingType &lt;string&gt;</code></b>
</a><br /> One of (none,tcp,udp,icmp,syn). Defines which pingType for alive-Checking has to be used. If set to 'none' no checks will be done.</li>
<li><a name="SONOS_attribut_reusePort"><b><code>reusePort &lt;int&gt;</code></b>
</a><br /> One of (0,1). If defined the socket-Attribute 'reuseport' will be used for SSDP Discovery-Port. Can solve restart-problems. If you don't have such problems don't use this attribute.</li>
<li><a name="SONOS_attribut_SubProcessLogfileName"><b><code>SubProcessLogfileName &lt;Path&gt;</code></b>
</a><br /> If given, the subprocess logs into its own logfile. Under Windows this is a recommended way for logging, because the two Loggings (Fehm and the SubProcess) overwrite each other. If "-" is given, the logging goes to STDOUT (and therefor in the Fhem-log) as usual. The main purpose of this attribute is the short-use of separated logging. No variables are substituted. The value is used as configured.</li>
<li><a name="SONOS_attribut_usedonlyIPs"><b><code>usedonlyIPs &lt;IP-Adresse&gt;[,IP-Adresse]</code></b>
</a><br />With this attribute you can define IP-addresses, which has to be exclusively used by the UPnP-System of this module. e.g. "192.168.0.11,192.168.0.37"</li>
</ul></li>
<li><b>Bookmark Configuration</b><ul>
<li><a name="SONOS_attribut_bookmarkSaveDir"><b><code>bookmarkSaveDir &lt;path&gt;</code></b>
</a><br /> Defines a directory where the saved bookmarks can be placed. If not defined, "." will be used.</li>
<li><a name="SONOS_attribut_bookmarkTitleDefinition"><b><code>bookmarkTitleDefinition &lt;Groupname&gt;:&lt;PlayerdeviceRegEx&gt;:&lt;TrackURIRegEx&gt;:&lt;MinTitleLength&gt;:&lt;RemainingLength&gt;:&lt;MaxAge&gt;:&lt;ReadOnly&gt;</code></b>
</a><br /> Definition of Bookmarks for titles.</li>
<li><a name="SONOS_attribut_bookmarkPlaylistDefinition"><b><code>bookmarkPlaylistDefinition &lt;Groupname&gt;:&lt;PlayerdeviceRegEx&gt;:&lt;MinListLength&gt;:&lt;MaxListLength&gt;:&lt;MaxAge&gt;</code></b>
</a><br /> Definition of bookmarks for playlists.</li>
</ul></li>
<li><b>Proxy Configuration</b><ul>
<li><a name="SONOS_attribut_generateProxyAlbumArtURLs"><b><code>generateProxyAlbumArtURLs &lt;int&gt;</code></b>
</a><br />One of (0, 1). If defined, all Cover-Links (the readings "currentAlbumArtURL" and "nextAlbumArtURL") are generated as links to the internal Sonos-Module-Proxy. It can be useful if you access Fhem over an external proxy and therefore have no access to the local network (the URLs are direct URLs to the Sonosplayer instead).</li>
<li><a name="SONOS_attribut_proxyCacheDir"><b><code>proxyCacheDir &lt;Path&gt;</code></b>
</a><br />Defines a directory where the cached Coverfiles can be placed. If not defined "/tmp" will be used.</li>
<li><a name="SONOS_attribut_proxyCacheTime"><b><code>proxyCacheTime &lt;int&gt;</code></b>
</a><br />A time in seconds. With a definition other than "0" the caching mechanism of the internal Sonos-Module-Proxy will be activated. If the filetime of the chached cover is older than this time, it will be reloaded from the Sonosplayer.</li>
<li><a name="SONOS_attribut_webname"><b><code>webname &lt;String&gt;</code></b>
</a><br /> With the attribute you can define the used webname for coverlinks. Defaults to 'fhem' if not given.</li>
</ul></li>
<li><b>Speak Configuration</b><ul>
<li><a name="SONOS_attribut_targetSpeakDir"><b><code>targetSpeakDir &lt;string&gt;</code></b>
</a><br /> Defines, which Directory has to be used for the Speakfiles</li>
<li><a name="SONOS_attribut_targetSpeakMP3FileConverter"><b><code>targetSpeakMP3FileConverter &lt;string&gt;</code></b>
</a><br /> Defines an MP3-File converter, which properly converts the resulting speaking-file. With this option you can avoid timedisplay problems. Please note that the waittime before the speaking starts can increase with this option be set.</li>
<li><a name="SONOS_attribut_targetSpeakMP3FileDir"><b><code>targetSpeakMP3FileDir &lt;string&gt;</code></b>
</a><br /> The directory which should be used as a default for text-embedded MP3-Files.</li>
<li><a name="SONOS_attribut_targetSpeakURL"><b><code>targetSpeakURL &lt;string&gt;</code></b>
</a><br /> Defines, which URL has to be used for accessing former stored Speakfiles as seen from the SonosPlayer</li>
<li><a name="SONOS_attribut_targetSpeakFileTimestamp"><b><code>targetSpeakFileTimestamp &lt;int&gt;</code></b>
</a><br /> One of (0, 1). Defines, if the Speakfile should have a timestamp in his name. That makes it possible to store all historical Speakfiles.</li>
<li><a name="SONOS_attribut_targetSpeakFileHashCache"><b><code>targetSpeakFileHashCache &lt;int&gt;</code></b>
</a><br /> One of (0, 1). Defines, if the Speakfile should have a hash-value in his name. If this value is set to one an already generated file with the same hash is re-used and not newly generated.</li>
<li><a name="SONOS_attribut_Speak1"><b><code>Speak1 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />Defines a systemcall commandline for generating a speaking file out of the given text. If such an attribute is defined, an associated setter at the Sonosplayer-Device is available. The following placeholders are available:<br />'''%language%''': Will be replaced by the given language-parameter<br />'''%filename%''': Will be replaced by the complete target-filename (incl. fileextension).<br />'''%text%''': Will be replaced with the given text.<br />'''%textescaped%''': Will be replaced with the given url-encoded text.</li>
<li><a name="SONOS_attribut_Speak2"><b><code>Speak2 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />See Speak1</li>
<li><a name="SONOS_attribut_Speak3"><b><code>Speak3 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />See Speak1</li>
<li><a name="SONOS_attribut_Speak4"><b><code>Speak4 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />See Speak1</li>
<li><a name="SONOS_attribut_SpeakCover"><b><code>SpeakCover &lt;Filename&gt;</code></b>
</a><br />Defines a Cover for use by the speak generation process. If not defined the Fhem-logo will be used.</li>
<li><a name="SONOS_attribut_Speak1Cover"><b><code>Speak1Cover &lt;Filename&gt;</code></b>
</a><br />See SpeakCover</li>
<li><a name="SONOS_attribut_Speak2Cover"><b><code>Speak2Cover &lt;Filename&gt;</code></b>
</a><br />See SpeakCover</li>
<li><a name="SONOS_attribut_Speak3Cover"><b><code>Speak3Cover &lt;Filename&gt;</code></b>
</a><br />See SpeakCover</li>
<li><a name="SONOS_attribut_Speak4Cover"><b><code>Speak4Cover &lt;Filename&gt;</code></b>
</a><br />See SpeakCover</li>
<li><a name="SONOS_attribut_SpeakGoogleURL"><b><code>SpeakGoogleURL &lt;GoogleURL&gt;</code></b>
</a><br />The google-speak-url that has to be used. If empty a default will be used. You have to define placeholders for replacing the language- and text-value: %1$s -> Language, %2$s -> Text<br />The Default-URL is currently: <code>http://translate.google.com/translate_tts?tl=%1$s&client=tw-ob&q=%2$s</code></li>
</ul></li>
</ul>

=end html

=begin html_DE

<a name="SONOS"></a>
<h3>SONOS</h3>
<p>FHEM-Modul für die Anbindung des Sonos-Systems via UPnP</p>
<p>Für weitere Hinweise und Beschreibungen bitte auch im Wiki unter <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a> nachschauen.</p>
<p>Für die Verwendung sind Perlmodule notwendig, die unter Umständen noch nachinstalliert werden müssen:<ul>
<li><code>LWP::Simple</code></li>
<li><code>LWP::UserAgent</code></li>
<li><code>SOAP::Lite</code></li>
<li><code>HTTP::Request</code></li></ul>
Installation z.B. als Debian-Pakete (mittels "sudo apt-get install &lt;packagename&gt;"):<ul>
<li>LWP::Simple-Packagename (inkl. LWP::UserAgent und HTTP::Request): libwww-perl</li>
<li>SOAP::Lite-Packagename: libsoap-lite-perl</li></ul>
<br />Installation z.B. als Windows ActivePerl (mittels Perl-Packagemanager)<ul>
<li>Package LWP (incl. LWP::UserAgent and HTTP::Request)</li>
<li>Package SOAP::Lite</li>
<li>SOAP::Lite-Special für Versionen nach 5.18:<ul>
  <li>Eine andere Paketquelle von den Vorschlägen oder manuell hinzufügen: Bribes de Perl (http://www.bribes.org/perl/ppm)</li>
  <li>Package: SOAP::Lite</li></ul></li></ul>
<b>Windows ActivePerl 5.20 kann momentan nicht verwendet werden, da es das Paket SOAP::Lite dort momentan nicht gibt.</b></p>
<p><b>Achtung!</b><br />Das Modul wird nicht auf jeder Plattform lauffähig sein, da Threads und die angegebenen Perl-Module verwendet werden.</p>
<p>Mehr Informationen im (deutschen) Wiki-Artikel: <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a></p>
<p>Das System besteht aus zwei Komponenten:<br />
1. Einem UPnP-Client, der als eigener Prozess im Hintergrund ständig läuft, und die Kommunikation mit den Sonos-Geräten übernimmt.<br />
2. Dem eigentlichen FHEM-Modul, welches mit dem UPnP-Client zusammenarbeitet, um die Funktionalität in FHEM zu ermöglichen.<br /><br />
Der Client wird im Notfall automatisch von Modul selbst gestartet.<br />
Man kann den Server unabhängig von FHEM selbst starten (um ihn dauerhaft und unabh&auml;ngig von FHEM laufen zu lassen):<br />
<code>perl 00_SONOS.pm 4711</code>: Startet einen unabhängigen Server, der auf Port 4711 auf eingehende FHEM-Verbindungen lauscht. Dieser Prozess kann dauerhaft laufen, FHEM kann sich verbinden und auch wieder trennen.</p>
<h4>Beispiel</h4>
<p>
Einfachste Definition:<br />
<b><code>define Sonos SONOS</code></b>
</p>
<p>
Definition mit Kontrolle über den verwendeten Port und das Intervall der IsAlive-Prüfung:<br />
<b><code>define Sonos SONOS localhost:4711 45</code></b>
</p>
<a name="SONOSdefine"></a>
<h4>Definition</h4>
<b><code>define &lt;name&gt; SONOS [upnplistener [interval [waittime [delaytime]]]]</code></b>
        <br /><br /> Definiert das Sonos interface für die Kommunikation mit dem Sonos-System.<br />
<p>
<b><code>[upnplistener]</code></b><br />Name und Port eines externen UPnP-Client. Wenn nicht angegebenen wird <code>localhost:4711</code> festgelegt. Der Port muss eine freie Portnummer ihres Systems sein. <br />Wenn sie keinen externen Client gestartet haben, startet das Skript einen eigenen.<br />Wenn sie einen eigenen Dienst gestartet haben, dann geben sie hier die entsprechenden Informationen an.</p>
<p>
<b><code>[interval]</code></b><br /> Das Interval wird für die Überprüfung eines Zoneplayers benötigt. In diesem Interval wird nachgeschaut, ob der Player noch erreichbar ist, da sich ein Player nicht mehr abmeldet, wenn er abgeschaltet wird :-)<br />Wenn nicht angegeben, wird ein Wert von 10 Sekunden angenommen.</p>
<p>
<b><code>[waittime]</code></b><br /> Hiermit wird die Wartezeit eingestellt, die nach dem Starten des SubProzesses darauf gewartet wird.</p>
<p>
<b><code>[delaytime]</code></b><br /> Hiermit kann eine Verzögerung eingestellt werden, die vor dem Starten des Netzwerks gewartet wird.</p>
<a name="SONOSset"></a>
<h4>Set</h4>
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="SONOS_setter_RefreshShareIndex">
<b><code>RefreshShareIndex</code></b></a>
<br />Startet die Aktualisierung der Bibliothek.</li>
<li><a name="SONOS_setter_RescanNetwork">
<b><code>RescanNetwork</code></b></a>
<br />Startet die Erkennung der im Netzwerk vorhandenen Player erneut.</li>
</ul></li>
<li><b>Steuerbefehle</b><ul>
<li><a name="SONOS_setter_Mute">
<b><code>Mute &lt;state&gt;</code></b></a>
<br />Setzt den Mute-Zustand bei allen Playern.</li>
<li><a name="SONOS_setter_PauseAll">
<b><code>PauseAll</code></b></a>
<br />Pausiert die Wiedergabe in allen Zonen.</li>
<li><a name="SONOS_setter_Pause">
<b><code>Pause</code></b></a>
<br />Synonym für PauseAll.</li>
<li><a name="SONOS_setter_StopAll">
<b><code>StopAll</code></b></a>
<br />Stoppt die Wiedergabe in allen Zonen.</li>
<li><a name="SONOS_setter_Stop">
<b><code>Stop</code></b></a>
<br />Synonym für StopAll.</li>
</ul></li>
<li><b>Bookmark-Befehle</b><ul>
<li><a name="SONOS_setter_DisableBookmark">
<b><code>DisableBookmark &lt;Groupname&gt;</code></b></a>
<br />Deaktiviert die angegebene Gruppe.</li>
<li><a name="SONOS_setter_EnableBookmark">
<b><code>EnableBookmark &lt;Groupname&gt;</code></b></a>
<br />Aktiviert die angegebene Gruppe.</li>
<li><a name="SONOS_setter_LoadBookmarks">
<b><code>LoadBookmarks [Groupname]</code></b></a>
<br />Lädt die angegebene Gruppe (oder alle Gruppen, wenn nicht angegeben) aus den entsprechenden Dateien.</li>
<li><a name="SONOS_setter_SaveBookmarks">
<b><code>SaveBookmarks [Groupname]</code></b></a>
<br />Speichert die angegebene Gruppe (oder alle Gruppen, wenn nicht angegeben) in die entsprechenden Dateien.</li>
</ul></li>
<li><b>Gruppenbefehle</b><ul>
<li><a name="SONOS_setter_Groups">
<b><code>Groups &lt;GroupDefinition&gt;</code></b></a>
<br />Setzt die aktuelle Gruppierungskonfiguration der Sonos-Systemlandschaft. Das Format ist jenes, welches auch von dem Get-Befehl 'Groups' geliefert wird.<br >Hier kann als GroupDefinition das Wort <i>Reset</i> verwendet werden, um alle Player aus ihren Gruppen zu entfernen.</li>
</ul></li>
</ul>
<a name="SONOSget"></a> 
<h4>Get</h4>
<ul>
<li><b>Gruppenbefehle</b><ul>
<li><a name="SONOS_getter_Groups">
<b><code>Groups</code></b></a>
<br />Liefert die aktuelle Gruppierungskonfiguration der Sonos Systemlandschaft zurück. Das Format ist eine Kommagetrennte Liste von Listen mit Devicenamen, also z.B. <code>[Sonos_Kueche], [Sonos_Wohnzimmer, Sonos_Schlafzimmer]</code>. In diesem Beispiel sind also zwei Gruppen definiert, von denen die erste aus einem Player und die zweite aus Zwei Playern besteht.<br />
Dabei ist die Reihenfolge innerhalb der Unterlisten wichtig, da der erste Eintrag der sogenannte Gruppenkoordinator ist (in diesem Fall also <code>Sonos_Wohnzimmer</code>), von dem die aktuelle Abspielliste un der aktuelle Titel auf die anderen Gruppenmitglieder übernommen wird.</li>
</ul></li>
</ul>
<a name="SONOSattr"></a>
<h4>Attribute</h4>
'''Hinweis'''<br />Die Attribute werden erst bei einem Neustart von Fhem verwendet, da diese dem SubProzess initial zur Verfügung gestellt werden müssen.
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="SONOS_attribut_coverLoadTimeout"><b><code>coverLoadTimeout &lt;value&gt;</code></b>
</a><br />Eines von (0..10,15,20,25,30). Definiert den Timeout der für die Abfrage des Covers beim Sonosplayer verwendet wird. Wenn nicht angegeben, dann wird 5 verwendet.</li>
<li><a name="SONOS_attribut_deviceRoomView"><b><code>deviceRoomView &lt;Both|DeviceLineOnly&gt;</code></b>
</a><br /> Gibt an, was in der Raumansicht zum Sonosplayer-Device angezeigt werden soll. <code>Both</code> bedeutet "normale" Devicezeile zzgl. Cover-/Titelanzeige und u.U. Steuerbereich, <code>DeviceLineOnly</code> bedeutet nur die Anzeige der "normalen" Devicezeile.</li>
<li><a name="SONOS_attribut_disable"><b><code>disable &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Hiermit kann das Modul abgeschaltet werden. Wirkt sofort. Bei 1 wird der SubProzess beendet, und somit keine weitere Verarbeitung durchgeführt. Bei 0 wird der Prozess wieder gestartet.<br />Damit kann das Modul temporär abgeschaltet werden, um bei der Neueinrichtung von Sonos-Komponenten keine halben Zustände mitzubekommen.</li>
<li><a name="SONOS_attribut_getFavouritesListAtNewVersion"><b><code>getFavouritesListAtNewVersion &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die Favoriten (bei definiertem Attribut <code>getListsDirectlyToReadings</code>) bei Aktualisierung automatisch herunterzuladen.</li>
<li><a name="SONOS_attribut_getPlaylistsListAtNewVersion"><b><code>getPlaylistsListAtNewVersion &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die Playlisten (bei definiertem Attribut <code>getListsDirectlyToReadings</code>) bei Aktualisierung automatisch herunterzuladen.</li>
<li><a name="SONOS_attribut_getQueueListAtNewVersion"><b><code>getQueueListAtNewVersion &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die aktuelle Abspielliste (bei definiertem Attribut <code>getListsDirectlyToReadings</code>) bei Aktualisierung automatisch herunterzuladen.</li>
<li><a name="SONOS_attribut_getRadiosListAtNewVersion"><b><code>getRadiosListAtNewVersion &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die Radioliste (bei definiertem Attribut <code>getListsDirectlyToReadings</code>) bei Aktualisierung automatisch herunterzuladen.</li>
<li><a name="SONOS_attribut_getListsDirectlyToReadings"><b><code>getListsDirectlyToReadings &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die Listen für Favoriten, Playlists, Radios und Queue direkt in die entsprechenden Readings zu schreiben. Dafür sind dann keine Userreadings mehr notwendig.</li>
<li><a name="SONOS_attribut_getLocalCoverArt"><b><code>getLocalCoverArt &lt;value&gt;</code></b>
</a><br />Eines von (0,1). Mit diesem Attribut kann das Modul aufgefordert werden, die Cover lokal herunterzuladen (bisheriges Standardverhalten).</li>
<li><a name="SONOS_attribut_ignoredIPs"><b><code>ignoredIPs &lt;IP-Adresse&gt;[,IP-Adresse]</code></b>
</a><br />Mit diesem Attribut können IP-Adressen angegeben werden, die vom UPnP-System ignoriert werden sollen. Z.B.: "192.168.0.11,192.168.0.37"</li>
<li><a name="SONOS_attribut_pingType"><b><code>pingType &lt;string&gt;</code></b>
</a><br /> Eines von (none,tcp,udp,icmp,syn). Gibt an, welche Methode für die Ping-Überprüfung verwendet werden soll. Wenn 'none' angegeben wird, dann wird keine Überprüfung gestartet.</li>
<li><a name="SONOS_attribut_reusePort"><b><code>reusePort &lt;int&gt;</code></b>
</a><br /> Eines von (0,1). Gibt an, ob die Portwiederwendung für SSDP aktiviert werden soll, oder nicht. Kann Restart-Probleme lösen. Wenn man diese Probleme nicht hat, sollte man das Attribut nicht setzen.</li>
<li><a name="SONOS_attribut_SubProcessLogfileName"><b><code>SubProcessLogfileName &lt;Pfad&gt;</code></b>
</a><br /> Hiermit kann für den SubProzess eine eigene Logdatei angegeben werden. Unter Windows z.B. überschreiben sich die beiden Logausgaben (von Fhem und SubProzess) sonst gegenseitig. Wenn "-" angegeben wird, wird wie bisher auf STDOUT (und damit im Fhem-Log) geloggt. Der Hauptanwendungsfall ist die mehr oder weniger kurzfristige Fehlersuche. Es werden keinerlei Variablenwerte ersetzt, und der Wert direkt als Dateiname verwendet.</li>
<li><a name="SONOS_attribut_usedonlyIPs"><b><code>usedonlyIPs &lt;IP-Adresse&gt;[,IP-Adresse]</code></b>
</a><br />Mit diesem Attribut können IP-Adressen angegeben werden, die ausschließlich vom UPnP-System berücksichtigt werden sollen. Z.B.: "192.168.0.11,192.168.0.37"</li>
</ul></li>
<li><b>Bookmark-Einstellungen</b><ul>
<li><a name="SONOS_attribut_bookmarkSaveDir"><b><code>bookmarkSaveDir &lt;path&gt;</code></b>
</a><br /> Das Verzeichnis, in dem die Dateien für die gespeicherten Bookmarks abgelegt werden sollen. Wenn nicht festgelegt, dann wird "." verwendet.</li>
<li><a name="SONOS_attribut_bookmarkTitleDefinition"><b><code>bookmarkTitleDefinition &lt;Groupname&gt;:&lt;PlayerdeviceRegEx&gt;:&lt;TrackURIRegEx&gt;:&lt;MinTitleLength&gt;:&lt;RemainingLength&gt;:&lt;MaxAge&gt;:&lt;ReadOnly&gt; [...]</code></b>
</a><br /> Die Definition für die Verwendung von Bookmarks für Titel.</li>
<li><a name="SONOS_attribut_bookmarkPlaylistDefinition"><b><code>bookmarkPlaylistDefinition &lt;Groupname&gt;:&lt;PlayerdeviceRegEx&gt;:&lt;MinListLength&gt;:&lt;MaxListLength&gt;:&lt;MaxAge&gt; [...]</code></b>
</a><br /> Die Definition für die Verwendung von Bookmarks für aktuelle Abspiellisten/Playlisten.</li>
</ul></li>
<li><b>Proxy-Einstellungen</b><ul>
<li><a name="SONOS_attribut_generateProxyAlbumArtURLs"><b><code>generateProxyAlbumArtURLs &lt;int&gt;</code></b>
</a><br /> Aus (0, 1). Wenn aktiviert, werden alle Cober-Links als Proxy-Aufrufe an Fhem generiert. Dieser Proxy-Server wird vom Sonos-Modul bereitgestellt. In der Grundeinstellung erfolgt kein Caching der Cover, sondern nur eine Durchreichung der Cover von den Sonosplayern (Damit ist der Zugriff durch einen externen Proxyserver auf Fhem möglich).</li>
<li><a name="SONOS_attribut_proxyCacheDir"><b><code>proxyCacheDir &lt;Path&gt;</code></b>
</a><br /> Hiermit wird das Verzeichnis festgelegt, in dem die Cober zwischengespeichert werden. Wenn nicht festegelegt, so wird "/tmp" verwendet.</li>
<li><a name="SONOS_attribut_proxyCacheTime"><b><code>proxyCacheTime &lt;int&gt;</code></b>
</a><br /> Mit einer Angabe ungleich 0 wird der Caching-Mechanismus des Sonos-Modul-Proxy-Servers aktiviert. Dabei werden Cover, die im Cache älter sind als diese Zeitangabe in Sekunden, neu vom Sonosplayer geladen, alle anderen direkt ausgeliefert, ohne den Player zu fragen.</li>
<li><a name="SONOS_attribut_webname"><b><code>webname &lt;String&gt;</code></b>
</a><br /> Hiermit kann der zu verwendende Webname für die Cover-Link-Erzeugung angegeben werden. Da vom Modul Links zu Cover u.ä. erzeugt werden, ohne dass es einen FhemWeb-Aufruf dazu gibt, kann das Modul diesen Pfad nicht selber herausfinden. Wenn das Attribut nicht angegeben wird, dann wird 'fhem' angenommen.</li>
</ul></li>
<li><b>Sprachoptionen</b><ul>
<li><a name="SONOS_attribut_targetSpeakDir"><b><code>targetSpeakDir &lt;string&gt;</code></b>
</a><br /> Gibt an, welches Verzeichnis für die Ablage des MP3-Files der Textausgabe verwendet werden soll</li>
<li><a name="SONOS_attribut_targetSpeakMP3FileConverter"><b><code>targetSpeakMP3FileConverter &lt;string&gt;</code></b>
</a><br /> Hiermit kann ein MP3-Konverter angegeben werden, da am Ende der Verkettung der Speak-Ansage das resultierende MP3-File nochmal sauber durchkodiert. Damit können Restzeitanzeigeprobleme behoben werden. Dadurch vegrößert sich allerdings u.U. die Ansageverzögerung.</li>
<li><a name="SONOS_attribut_targetSpeakMP3FileDir"><b><code>targetSpeakMP3FileDir &lt;string&gt;</code></b>
</a><br /> Das Verzeichnis, welches als Standard für MP3-Fileangaben in Speak-Texten verwendet werden soll. Wird dieses Attribut definiert, können die Angaben bei Speak ohne Verzeichnis erfolgen.</li>
<li><a name="SONOS_attribut_targetSpeakURL"><b><code>targetSpeakURL &lt;string&gt;</code></b>
</a><br /> Gibt an, unter welcher Adresse der ZonePlayer das unter targetSpeakDir angegebene Verzeichnis erreichen kann.</li>
<li><a name="SONOS_attribut_targetSpeakFileTimestamp"><b><code>targetSpeakFileTimestamp &lt;int&gt;</code></b>
</a><br /> One of (0, 1). Gibt an, ob die erzeugte MP3-Sprachausgabedatei einen Zeitstempel erhalten soll (1) oder nicht (0).</li>
<li><a name="SONOS_attribut_targetSpeakFileHashCache"><b><code>targetSpeakFileHashCache &lt;int&gt;</code></b>
</a><br /> One of (0, 1). Gibt an, ob die erzeugte Sprachausgabedatei einen Hashwert erhalten soll (1) oder nicht (0). Wenn dieser Wert gesetzt wird, dann wird eine bereits bestehende Datei wiederverwendet, und nicht neu erzeugt.</li>
<li><a name="SONOS_attribut_Speak1"><b><code>Speak1 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />Hiermit kann ein Systemaufruf definiert werden, der zu Erzeugung einer Sprachausgabe verwendet werden kann. Sobald dieses Attribut definiert wurde, ist ein entsprechender Setter am Sonosplayer verfügbar.<br />Es dürfen folgende Platzhalter verwendet werden:<br />'''%language%''': Wird durch die eingegebene Sprache ersetzt<br />'''%filename%''': Wird durch den kompletten Dateinamen (inkl. Dateiendung) ersetzt.<br />'''%text%''': Wird durch den zu übersetzenden Text ersetzt.<br />'''%textescaped%''': Wird durch den URL-Enkodierten zu übersetzenden Text ersetzt.</li>
<li><a name="SONOS_attribut_Speak2"><b><code>Speak2 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />Siehe Speak1</li>
<li><a name="SONOS_attribut_Speak3"><b><code>Speak3 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />Siehe Speak1</li>
<li><a name="SONOS_attribut_Speak4"><b><code>Speak4 &lt;Fileextension&gt;:&lt;Commandline&gt;</code></b>
</a><br />Siehe Speak1</li>
<li><a name="SONOS_attribut_SpeakCover"><b><code>SpeakCover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Hiermit kann ein JPG- oder PNG-Bild als Cover für die Sprachdurchsagen definiert werden.</li>
<li><a name="SONOS_attribut_Speak1Cover"><b><code>Speak1Cover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Analog zu SpeakCover für Speak1.</li>
<li><a name="SONOS_attribut_Speak2Cover"><b><code>Speak2Cover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Analog zu SpeakCover für Speak2.</li>
<li><a name="SONOS_attribut_Speak3Cover"><b><code>Speak3Cover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Analog zu SpeakCover für Speak3.</li>
<li><a name="SONOS_attribut_Speak3Cover"><b><code>Speak3Cover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Analog zu SpeakCover für Speak3.</li>
<li><a name="SONOS_attribut_Speak4Cover"><b><code>Speak4Cover &lt;Absolute-Imagepath&gt;</code></b>
</a><br />Analog zu SpeakCover für Speak4.</li>
<li><a name="SONOS_attribut_SpeakGoogleURL"><b><code>SpeakGoogleURL &lt;GoogleURL&gt;</code></b>
</a><br />Die zu verwendende Google-URL. Wenn dieser Parameter nicht angegeben wird, dann wird ein Standard verwendet. Hier müssen Platzhalter für die Ersetzung durch das Modul eingetragen werden: %1$s -> Sprache, %2$s -> Text<br />Die Standard-URL lautet momentan: <code>http://translate.google.com/translate_tts?tl=%1$s&client=tw-ob&q=%2$s</code></li>
</ul></li>
</ul>

=end html_DE
=cut