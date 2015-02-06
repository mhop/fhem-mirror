########################################################################################
#
# SONOSPLAYER.pm (c) by Reiner Leins, January 2015
# rleins at lmsoft dot de
#
# $Id$
#
# FHEM module to work with Sonos-Zoneplayers
#
# define <name> SONOSPLAYER <UDN>
#
# where <name> may be replaced by any name string 
#       <udn> is the Zoneplayer Identification
#
########################################################################################
# Changelog
#
# ab 2.2 Changelog nur noch in der Datei 00_SONOS
#
# 2.1:	Neuen Befehl 'CurrentPlaylist' eingeführt
#
# 2.0:	Neue Konzeptbasis eingebaut
#		Man kann Gruppen auf- und wieder abbauen
#		PlayURI kann nun einen Devicenamen entgegennehmen, und spielt dann den AV-Eingang des angegebenen Raumes ab
#		Alle Steuerbefehle werden automatisch an den jeweiligen Gruppenkoordinator gesendet, sodass die Abspielanweisungen immer korrekt durchgeführt werden
#		Es gibt neue Lautstärke- und Mute-Einstellungen für Gruppen ingesamt
#
# 1.12:	TrackURI hinzugefügt
#		Alarmbenutzung hinzugefügt
#		Schlummerzeit hinzugefügt (Reading SleepTimer)
#		DailyIndexRefreshTime hinzugefügt
#
# 1.11:	Shuffle, Repeat und CrossfadeMode können nun gesetzt und abgefragt werden
#
# 1.10:	LastAction-Readings werden nun nach eigener Konvention am Anfang groß geschrieben. Damit werden 'interne Variablen' von den Informations-Readings durch Groß/Kleinschreibung unterschieden
#		Volume, Balance und HeadphonConnected können nun auch in InfoSummarize und StateVariable verwendet werden. Damit sind dies momentan die einzigen 'interne Variablen', die dort verwendet werden können
#		Attribut 'generateVolumeEvent' eingeführt.
#		Getter und Setter 'Balance' eingeführt.
#		Reading 'HeadphoneConnected' eingeführt.
#		Reading 'Mute' eingeführt.
#		InfoSummarize-Features erweitert: 'instead' und 'emptyval' hinzugefügt
#
# 1.9:	
#
# 1.8:	minVolume und maxVolume eingeführt. Damit kann nun der Lautstärkeregelbereich der ZonePlayer festgelegt werden
#
# 1.7:	Fehlermeldung bei aktivem TempPlaying und damit Abbruch der Anforderung deutlicher geschrieben
#
# 1.6:	Speak hinzugefügt
#
# Versionsnummer zu 00_SONOS angeglichen
#
# 1.3:	Zusätzliche Befehle hinzugefügt
#
# 1.2:	Einrückungen im Code korrigiert
#
# 1.1: 	generateInfoAnswerOnSet eingeführt (siehe Doku im Wiki)
#		generateVolumeSlider eingeführt (siehe Doku im Wiki)
#
# 1.0:	Initial Release
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
# Uses Declarations
########################################################################################
package main;

use vars qw{%attr %defs};
use strict;
use warnings;
use URI::Escape;
use Thread::Queue;

require 'HttpUtils.pm';

sub Log($$);
sub Log3($$$);
sub SONOSPLAYER_Log($$$);

########################################################################################
# Variable Definitions
########################################################################################
my %gets = (
	'CurrentTrackPosition' => '',
	'Playlists' => '',
	'PlaylistsWithCovers' => '',
	'Favourites' => '',
	'FavouritesWithCovers' => '',
	'Radios' => '',
	'RadiosWithCovers' => '',
	'Alarm' => 'ID',
	'EthernetPortStatus' => 'PortNum',
	'PossibleRoomIcons' => '',
	'SearchlistCategories' => ''
);

my %sets = (
	'Play' => '',
	'Pause' => '',
	'Stop' => '',
	'Next' => '',
	'Previous' => '',
	'LoadPlaylist' => 'playlistname',
	'StartPlaylist' => 'playlistname',
	'SavePlaylist' => 'playlistname',
	'CurrentPlaylist' => '',
	'EmptyPlaylist' => '',
	'StartFavourite' => 'favouritename',
	'LoadRadio' => 'radioname',
	'StartRadio' => 'radioname',
	'PlayURI' => 'songURI',
	'PlayURITemp' => 'songURI',
	'AddURIToQueue' => 'songURI',
	'Speak' => 'volume language text',
	'OutputFixed' => 'state',
	'Mute' => 'state',
	'Shuffle' => 'state',
	'Repeat' => 'state',
	'CrossfadeMode' => 'state',
	'LEDState' => 'state',
	'MuteT' => '',
	'ShuffleT' => '',
	'RepeatT' => '',
	'VolumeD' => '',
	'VolumeU' => '',
	'Volume' => 'volumelevel',
	'VolumeSave' => 'volumelevel',
	'VolumeRestore' => '',
	'Balance' => 'balancevalue',
	'Loudness' => 'state',
	'Bass' => 'basslevel',
	'Treble' => 'treblelevel',	
	'CurrentTrackPosition' => 'timeposition',
	'Track' => 'tracknumber|Random',
	'Alarm' => 'create|update|delete ID valueHash',
	'DailyIndexRefreshTime' => 'timestamp',
	'SleepTimer' => 'time',
	'AddMember' => 'member_devicename',
	'RemoveMember' => 'member_devicename',
	'GroupVolume' => 'volumelevel',
	'SnapshotGroupVolume' => '',
	'GroupMute' => 'state',
	'CreateStereoPair' => 'RightPlayer',
	'SeparateStereoPair' => '',
	'Reboot' => '',
	'Wifi' => 'state',
	'Name' => 'roomName',
	'RoomIcon' => 'iconName',
	'LoadSearchlist' => 'category categoryElem titleFilter/albumFilter/artistFilter maxElems',
	'StartSearchlist' => 'category categoryElem titleFilter/albumFilter/artistFilter maxElems'
);

my @possibleRoomIcons = qw(bathroom library office foyer dining tvroom hallway garage garden guestroom den bedroom kitchen portable media family pool masterbedroom playroom patio living);

########################################################################################
#
#  SONOSPLAYER_Initialize
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_Initialize ($) {
	my ($hash) = @_;
	
	$hash->{DefFn}   = "SONOSPLAYER_Define";
	$hash->{UndefFn} = "SONOSPLAYER_Undef";
	$hash->{DeleteFn} = "SONOSPLAYER_Delete";
	$hash->{GetFn}   = "SONOSPLAYER_Get";
	$hash->{SetFn}   = "SONOSPLAYER_Set";
	$hash->{StateFn} = "SONOSPLAYER_State";
	$hash->{NotifyFn} = 'SONOSPLAYER_Notify';
	
	$hash->{AttrList}= "disable:1,0 generateVolumeSlider:1,0 generateVolumeEvent:1,0 generateSomethingChangedEvent:1,0 generateInfoSummarize1 generateInfoSummarize2 generateInfoSummarize3 generateInfoSummarize4 stateVariable:TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,OutputFixed,Shuffle,Repeat,CrossfadeMode,Balance,HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,InfoSummarize2,InfoSummarize3,InfoSummarize4 model minVolume maxVolume minVolumeHeadphone maxVolumeHeadphone VolumeStep getAlarms:1,0 buttonEvents ".$readingFnAttributes;
	
	return undef;
}
  
########################################################################################
#
#  SONOSPLAYER_Define - Implements DefFn function
# 
#  Parameter hash = hash of device addressed, def = definition string
#
########################################################################################
sub SONOSPLAYER_Define ($$) {
	my ($hash, $def) = @_;
  
	# define <name> SONOSPLAYER <udn>
	# e.g.: define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400
	my @a = split("[ \t]+", $def);
  
	my ($name, $udn);
  
	# default
	$name = $a[0];
	$udn = $a[2];

	# check syntax
	return "SONOSPLAYER: Wrong syntax, must be define <name> SONOSPLAYER <udn>" if(int(@a) < 3);
  
	readingsSingleUpdate($hash, "state", 'init', 1);
	readingsSingleUpdate($hash, "presence", 'disappeared', 0); # Grund-Initialisierung, falls der Player sich nicht zurückmelden sollte...
	
	$hash->{UDN} = $udn;
	readingsSingleUpdate($hash, "state", 'initialized', 1);
	
	return undef; 
}

#######################################################################################
#
#  SONOSPLAYER_State - StateFn, used for deleting unused or initialized Readings...
#
########################################################################################
sub SONOSPLAYER_State($$$$) {
	my ($hash, $time, $name, $value) = @_; 
	
	# Die folgenden Readings müssen immer neu initialisiert verwendet werden, und dürfen nicht aus dem Statefile verwendet werden
	#return 'Reading '.$hash->{NAME}."->$name must not be used out of statefile. This is not an error! This happens due to restrictions of Fhem." if ($name eq 'presence') || ($name eq 'LastActionResult') || ($name eq 'AlarmList') || ($name eq 'AlarmListIDs') || ($name eq 'AlarmListVersion');
	if (($name eq 'presence') || ($name eq 'LastActionResult') || ($name eq 'AlarmList') || ($name eq 'AlarmListIDs') || ($name eq 'AlarmListVersion')) {
		SONOSPLAYER_Log undef, 4, 'StateFn-Call. Ignore the following Reading: '.$hash->{NAME}.'->'.$name.'('.(defined($value) ? $value : '').')';
	
		setReadingsVal($hash, $name, '~~NotLoadedMarker~~', TimeNow());
	}
	
	# Die folgenden Readings werden nicht mehr benötigt, und werden hiermit entfernt...
	return 'Reading '.$hash->{NAME}."->$name is now unused and is ignored for the future for all Zoneplayer-Types." if ($name eq 'LastGetActionName') || ($name eq 'LastGetActionResult') || ($name eq 'LastSetActionName') || ($name eq 'LastSetActionResult') || ($name eq 'LastSubscriptionsRenew') || ($name eq 'LastSubscriptionsResult') || ($name eq 'SetMakeStandaloneGroup') || ($name eq 'CurrentTempPlaying') || ($name eq 'SetWRONG');
	
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_Notify - Implements NotifyFn function 
#
########################################################################################
sub SONOSPLAYER_Notify() {
	my ($hash, $notifyhash) = @_;
	
	return undef;
	
	# Das folgende habe ich erstmal wieder entfernt, da man ja öfter im laufenden Betrieb die Einstellungen speichert, und den Sonos-Komponenten dann immer wichtige Informationen für den Betrieb fehlen (nicht jedes Save wird vor dem Neustart von Fhem ausgeführt)
	#if (($notifyhash->{NAME} eq 'global') && (($notifyhash->{CHANGED}[0] eq 'SAVE') || ($notifyhash->{CHANGED}[0] eq 'SHUTDOWN'))) {
	#	SONOSPLAYER_Log undef, 3, $hash->{NAME}.' has detected a global:'.$notifyhash->{CHANGED}[0].'-Event. Clear out some readings before...';
	#	
	#	# Einige Readings niemals speichern
	#	delete($defs{$hash->{NAME}}{READINGS}{presence});
	#	delete($defs{$hash->{NAME}}{READINGS}{LastActionResult});
	#	delete($defs{$hash->{NAME}}{READINGS}{AlarmList});
	#	delete($defs{$hash->{NAME}}{READINGS}{AlarmListIDs});
	#	delete($defs{$hash->{NAME}}{READINGS}{AlarmListVersion});
	#}
	#
	#return undef;
}

########################################################################################
#
#  SONOSPLAYER_Get - Implements GetFn function 
#
#  Parameter hash = hash of device addressed
#						 a = argument array
#
########################################################################################
sub SONOSPLAYER_Get($@) {
	my ($hash, @a) = @_;
	
	my $reading = $a[1];
	my $name = $hash->{NAME};
	my $udn = $hash->{UDN};
	
	# for the ?-selector: which values are possible
	if($reading eq '?') {
		my @newGets = ();
		for my $elem (sort keys %gets) {
			my $newElem = $elem.(($gets{$elem} eq '') ? ':noArg' : '');
			
			$newElem = $elem.':0,1,2,3' if (lc($elem) eq 'ethernetportstatus');
			
			push @newGets, $newElem;
		}
		return "Unknown argument, choose one of ".join(" ", @newGets);
	}
	
	# check argument
	my $found = 0;
	for my $elem (keys %gets) {
		if (lc($reading) eq lc($elem)) {
			$a[1] = $elem; # Korrekte Schreibweise behalten
			$reading = $elem; # Korrekte Schreibweise behalten
			$found = 1;
			last;
		}
	}
	return "SONOSPLAYER: Get with unknown argument $a[1], choose one of ".join(" ", sort keys %gets) if(!$found);
	
	# some arguments needs parameter(s), some not
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$gets{$reading} if (scalar(split(',', $gets{$reading})) > scalar(@a) - 2);
	
	# getter
	if (lc($reading) eq 'currenttrackposition') {
		SONOS_DoWork($udn, 'getCurrentTrackPosition');
	} elsif (lc($reading) eq 'playlists') {
		SONOS_DoWork($udn, 'getPlaylists');
	} elsif (lc($reading) eq 'playlistswithcovers') {
		SONOS_DoWork($udn, 'getPlaylistsWithCovers');
	} elsif (lc($reading) eq 'favourites') {
		SONOS_DoWork($udn, 'getFavourites');
	} elsif (lc($reading) eq 'favouriteswithcovers') {
		SONOS_DoWork($udn, 'getFavouritesWithCovers');
	} elsif (lc($reading) eq 'radios') {
		SONOS_DoWork($udn, 'getRadios');
	} elsif (lc($reading) eq 'radioswithcovers') {
		SONOS_DoWork($udn, 'getRadiosWithCovers');
	} elsif (lc($reading) eq 'searchlistcategories') {
		SONOS_DoWork($udn, 'getSearchlistCategories');
	} elsif (lc($reading) eq 'ethernetportstatus') {
		my $portNum = $a[2];
		
		readingsSingleUpdate($hash, 'LastActionResult', 'Portstatus properly returned', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/status\/enetports/;
		
		my $statusPage = GetFileFromURL($url);
		return (($1 == 0) ? 'Inactive' : 'Active') if ($statusPage =~ m/<Port port='$portNum'><Link>(\d+)<\/Link><Speed>.*?<\/Speed><\/Port>/i);
		return 'Inactive';
	} elsif (lc($reading) eq 'alarm') {
		my $id = $a[2];
		
		readingsSingleUpdate($hash, 'LastActionResult', 'Alarm-Hash properly returned', 1);
		
		my @idList = split(',', ReadingsVal($name, 'AlarmListIDs', ''));
		if (!SONOS_isInList($id, @idList)) {
			return {};
		} else {
			return eval(ReadingsVal($name, 'AlarmList', ()))->{$id};
		}
	} elsif (lc($reading) eq 'possibleroomicons') {
		return '"'.join('", "', @possibleRoomIcons).'"';
	}
  
	return undef;
}

#######################################################################################
#
#  SONOSPLAYER_Set - Set one value for device
#
#  Parameter hash = hash of device addressed
#            a = argument string
#
########################################################################################
sub SONOSPLAYER_Set($@) {
	my ($hash, @a) = @_;
	
	# for the ?-selector: which values are possible
	if($a[1] eq '?') {
		# %setCopy enthält eine Kopie von %sets, da für eine ?-Anfrage u.U. ein Slider zurückgegeben werden muss...
		my %setcopy;
		foreach my $key (keys %sets) {
			my $oldkey = $key;
			if (AttrVal($hash, 'generateVolumeSlider', 1) == 1) {
				$key = $key.':slider,0,1,100' if ($key eq 'Volume');
				$key = $key.':slider,0,1,100' if ($key eq 'GroupVolume');
				$key = $key.':slider,0,1,100' if ($key eq 'Treble');
				$key = $key.':slider,0,1,100' if ($key eq 'Bass');
				$key = $key.':slider,-100,1,100' if ($key eq 'Balance');
			}
			
			# On/Off einsetzen; Da das jeweilige Reading dazu 0,1 enthalten wird, auch mit 0,1 arbeiten, damit die Vorauswahl passt
			$key = $key.':0,1' if ((lc($key) eq 'crossfademode') || (lc($key) eq 'groupmute') || (lc($key) eq 'ledstate') || (lc($key) eq 'loudness') || (lc($key) eq 'mute') || (lc($key) eq 'outputfixed')  || (lc($key) eq 'repeat') || (lc($key) eq 'shuffle'));
			
			# Iconauswahl einsetzen
			if (lc($key) eq 'roomicon') {
				my $icons = SONOSPLAYER_Get($hash, ($hash->{NAME}, 'PossibleRoomIcons'));
				$icons =~ s/ //g;
				$key = $key.':'.$icons;
			}
			
			# Playerauswahl einsetzen
			my @playerNames = ();
			for my $player (SONOS_getAllSonosplayerDevices()) {
				push @playerNames, $player->{NAME} if ($hash->{NAME} ne $player->{NAME});
			}
			$key = $key.':'.join(',', sort(@playerNames)) if ((lc($key) eq 'addmember') || (lc($key) eq 'createstereopair') || (lc($key) eq 'removemember'));
			
			# Wifi-Auswahl setzen
			$key = $key.':off,on,persist-off' if (lc($key) eq 'wifi');
			
			$setcopy{$key} = $sets{$oldkey};
		}
		
		my $sonosDev = SONOS_getDeviceDefHash(undef);
		$sets{Speak1} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak1', '') ne '');
		$sets{Speak2} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak2', '') ne '');
		$sets{Speak3} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak3', '') ne '');
		$sets{Speak4} = 'volume language text' if (AttrVal($sonosDev->{NAME}, 'Speak4', '') ne '');
		
		# for the ?-selector: which values are possible
		if($a[1] eq '?') {
			my @newSets = ();
			for my $elem (sort keys %setcopy) {
				push @newSets, $elem.(($setcopy{$elem} eq '') ? ':noArg' : '');
			}
			return "Unknown argument, choose one of ".join(" ", @newSets);
		}
	
		#return join(" ", sort keys %setcopy);
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
	return "SONOSPLAYER: Set with unknown argument $a[1], choose one of ".join(" ", sort keys %sets) if(!$found);
  
	# some arguments needs parameter(s), some not
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$sets{$a[1]} if (scalar(split(',', $sets{$a[1]})) > scalar(@a) - 2);
      
	# define vars
	my $key = $a[1];
	my $value = $a[2];
	my $value2 = $a[3];
	my $name = $hash->{NAME};
	my $udn = $hash->{UDN};
	
	# setter
	if (lc($key) eq 'currenttrackposition') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setCurrentTrackPosition', $value);
	} elsif (lc($key) eq 'groupvolume') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeGroupVolume',  $value, $value2);
		} else {
			SONOS_DoWork($udn, 'setGroupVolume', $value, $value2);
		}
	} elsif (lc($key) eq 'snapshotgroupvolume') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setSnapshotGroupVolume',  $value);
	} elsif (lc($key) eq 'volume') {
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeVolume',  $value, $value2);
		} else {
			SONOS_DoWork($udn, 'setVolume', $value, $value2);
		}
	} elsif (lc($key) eq 'volumesave') {
		setReadingsVal($hash, 'VolumeStore', ReadingsVal($name, 'Volume', 0), TimeNow());
		if ($value =~ m/^[+-]{1}/) {
			SONOS_DoWork($udn, 'setRelativeVolume',  $value);
		} else {
			SONOS_DoWork($udn, 'setVolume', $value);
		}
	} elsif (lc($key) eq 'volumerestore') {
		SONOS_DoWork($udn, 'setVolume', ReadingsVal($name, 'VolumeStore', 0));
	} elsif (lc($key) eq 'volumed') {
		SONOS_DoWork($udn, 'setRelativeVolume', -AttrVal($hash->{NAME}, 'VolumeStep', 7));
	} elsif (lc($key) eq 'volumeu') {
		SONOS_DoWork($udn, 'setRelativeVolume', AttrVal($hash->{NAME}, 'VolumeStep', 7));
	} elsif (lc($key) eq 'balance') {
		SONOS_DoWork($udn, 'setBalance', $value);
	} elsif (lc($key) eq 'loudness') {
		SONOS_DoWork($udn, 'setLoudness', $value);
	} elsif (lc($key) eq 'bass') {
		SONOS_DoWork($udn, 'setBass', $value);
	} elsif (lc($key) eq 'treble') {
		SONOS_DoWork($udn, 'setTreble', $value);
	} elsif (lc($key) eq 'groupmute') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setGroupMute', $value);
	} elsif (lc($key) eq 'outputfixed') {
		SONOS_DoWork($udn, 'setOutputFixed', $value);
	} elsif (lc($key) eq 'mute') {
		SONOS_DoWork($udn, 'setMute', $value);
	} elsif (lc($key) eq 'mutet') {
		SONOS_DoWork($udn, 'setMuteT', '');
	} elsif (lc($key) eq 'shuffle') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setShuffle', $value);
	} elsif (lc($key) eq 'shufflet') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setShuffle', '~~');
	} elsif (lc($key) eq 'repeat') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setRepeat', $value);
	} elsif (lc($key) eq 'repeatt') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setRepeat', '~~');
	} elsif (lc($key) eq 'crossfademode') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setCrossfadeMode', $value);
	} elsif (lc($key) eq 'ledstate') {
		SONOS_DoWork($udn, 'setLEDState', $value);
	} elsif (lc($key) eq 'play') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'play');
	} elsif (lc($key) eq 'stop') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'stop');
	} elsif (lc($key) eq 'pause') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'pause');
	} elsif (lc($key) eq 'previous') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'previous');
	} elsif (lc($key) eq 'next') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'next');
	} elsif (lc($key) eq 'track') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setTrack', $value);
	} elsif (lc($key) eq 'loadradio') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'loadRadio', $value);
	} elsif (lc($key) eq 'startradio') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'loadRadio', $value);
		SONOS_DoWork($udn, 'play');
	} elsif (lc($key) eq 'startfavourite') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'startFavourite', $value, $value2);
	} elsif (lc($key) eq 'loadplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		$value2 = 1 if (!defined($value2));
		
		if ($value =~ m/^file:(.*)/) {
			SONOS_DoWork($udn, 'loadPlaylist', ':m3ufile:'.$1, $value2);
		} else {
			SONOS_DoWork($udn, 'loadPlaylist', $value, $value2);
		}
	} elsif (lc($key) eq 'startplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		$value2 = 1 if (!defined($value2));
		
		if ($value =~ m/^file:(.*)/) {
			SONOS_DoWork($udn, 'loadPlaylist', ':m3ufile:'.$1, $value2);
		} else {
			SONOS_DoWork($udn, 'loadPlaylist', $value, $value2);
		}
		SONOS_DoWork($udn, 'play');
	} elsif (lc($key) eq 'emptyplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'emptyPlaylist');
	} elsif (lc($key) eq 'saveplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		if ($value =~ m/^file:(.*)/) {
			SONOS_DoWork($udn, 'savePlaylist', $1, ':m3ufile:');
		} else {
			SONOS_DoWork($udn, 'savePlaylist', $value, '');
		}
	} elsif (lc($key) eq 'currentplaylist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setCurrentPlaylist');
	} elsif (lc($key) eq 'loadsearchlist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'loadSearchlist', $value, $value2, $a[4], $a[5]);
	} elsif (lc($key) eq 'startsearchlist') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'loadSearchlist', $value, $value2, $a[4], $a[5]);
		SONOS_DoWork($udn, 'play');
	} elsif (lc($key) eq 'playuri') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		# Prüfen, ob ein Sonosplayer-Device angegeben wurde, dann diesen AV Eingang als Quelle wählen
		if (defined($defs{$value})) {
			my $dHash = SONOS_getDeviceDefHash($value);
			if (defined($dHash)) {
				my $udnShort = $1 if ($dHash->{UDN} =~ m/(.*)_MR/); 
				
				# Wenn dieses Quell-Device eine Playbar ist, dann den optischen Eingang als Quelle wählen...
				if (ReadingsVal($dHash->{NAME}, 'playerType', '') eq 'S9') {
					# Das ganze geht nur bei dem eigenen Eingang, ansonsten eine Gruppenwiedergabe starten
					if ($dHash->{NAME} eq $hash->{NAME}) {
						$value = 'x-sonos-htastream:'.$udnShort.':spdif';
					} else {
						# Auf dem anderen Player den TV-Eingang wählen
						SONOS_DoWork($dHash->{UDN}, 'playURI', 'x-sonos-htastream:'.$udnShort.':spdif', undef);
						
						# Gruppe bilden
						SONOS_DoWork($hash->{UDN}, 'playURI', 'x-rincon:'.$udnShort, $value2); 
						
						# Wir sind hier fertig
						return undef;
					}
				} else {
					$value = 'x-rincon-stream:'.$udnShort;
				}
			}
		}
	
		SONOS_DoWork($udn, 'playURI', $value, $value2);
	} elsif (lc($key) eq 'playuritemp') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'playURITemp', $value, $value2); 
	} elsif (lc($key) eq 'adduritoqueue') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'addURIToQueue', $value);
	} elsif ((lc($key) eq 'speak') || ($key =~ m/speak\d+/i)) {
		my $sonosName = SONOS_getDeviceDefHash(undef)->{NAME};
		if ((AttrVal($sonosName, 'targetSpeakDir', '') eq '') || (AttrVal($sonosName, 'targetSpeakURL', '') eq '')) {
			return $key.' not possible. Please define valid "targetSpeakDir"- and "targetSpeakURL"-Attribute for Device "'.$sonosName.'" first.';
		} else {
			$key = 'speak0' if (lc($key) eq 'speak');
			
			$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
			$udn = $hash->{UDN};
			
			# Hier die komplette restliche Zeile in den Text-Parameter packen, da damit auch Leerzeichen möglich sind
			my $text = '';
			for(my $i = 4; $i < @a; $i++) {
				$text .= ' '.$a[$i];
			}
		
			SONOS_DoWork($udn, lc($key), $value, $value2, $text);
		}
	} elsif (lc($key) eq 'alarm') {
		# Hier die komplette restliche Zeile in den zweiten Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 4; $i < @a; $i++) {
			$text .= ' '.$a[$i];
		}
		
		SONOS_DoWork($udn, 'setAlarm', $value, $value2, $text);
	} elsif (lc($key) eq 'dailyindexrefreshtime') {
		SONOS_DoWork($udn, 'setDailyIndexRefreshTime', $value);
	} elsif (lc($key) eq 'sleeptimer') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'setSleepTimer', $value);
	} elsif (lc($key) eq 'addmember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getDeviceDefHash($value);
		if ($cHash) {
			SONOS_DoWork($udn, 'addMember', $cHash->{UDN});
		} else {
			my @sonosDevs = ();
			foreach my $dev (SONOS_getAllSonosplayerDevices()) {
				push(@sonosDevs, $dev->{NAME}) if ($dev->{NAME} ne $hash->{NAME});
			}
			readingsSingleUpdate($hash, 'LastActionResult', 'AddMember: Wrong Sonos-Devicename "'.$value.'". Use one of "'.join('", "', @sonosDevs).'"', 1);
			
			return undef;
		}
	} elsif (lc($key) eq 'removemember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getDeviceDefHash($value);
		if ($cHash) {
			SONOS_DoWork($udn, 'removeMember', $cHash->{UDN});
		} else {
			my @sonosDevs = ();
			foreach my $dev (SONOS_getAllSonosplayerDevices()) {
				push(@sonosDevs, $dev->{NAME}) if ($dev->{NAME} ne $hash->{NAME});
			}
			readingsSingleUpdate($hash, 'LastActionResult', 'RemoveMember: Wrong Sonos-Devicename "'.$value.'". Use one of "'.join('", "', @sonosDevs).'"', 1);
			
			return undef;
		}
	} elsif (lc($key) eq 'createstereopair') {
		my $rightPlayer = InternalVal($value, 'UDN', '');
		return 'RightPlayer not found!' if (!$rightPlayer);
		
		# UDN korrigieren
		my $leftPlayerShort = $1 if ($udn =~ m/(.*)_MR/);
		my $rightPlayerShort = $1 if ($rightPlayer =~ m/(.*)_MR/);
		
		# Anweisung an den neuen linken Lautsprecher absetzen
		SONOS_DoWork($udn, 'createStereoPair', uri_escape($leftPlayerShort.':LF,LF;'.$rightPlayerShort.':RF,RF'));
	} elsif (lc($key) eq 'separatestereopair') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		# UDN korrigieren
		my $leftPlayerShort = $1 if ($udn =~ m/(.*)_MR/);
		
		# StereoPartner herausfinden
		my $rightPlayer = '';
		foreach my $dev (SONOS_getAllSonosplayerDevices()) {
			$rightPlayer = $dev->{UDN} if ((ReadingsVal($dev->{NAME}, 'ZoneGroupID', '') =~ m/^$leftPlayerShort:/) && ($dev->{UDN} !~ m/^${leftPlayerShort}_MR/));
		}
		return 'RightPlayer not found!' if (!$rightPlayer);
		
		# UDN korrigieren
		my $rightPlayerShort = $1 if ($rightPlayer =~ m/(.*)_MR/);
		
		# Anweisung an den alten linken Lautsprecher absetzen
		SONOS_DoWork($udn, 'separateStereoPair', uri_escape($leftPlayerShort.':LF,LF;'.$rightPlayerShort.':RF,RF'));
	} elsif (lc($key) eq 'reboot') {
		readingsSingleUpdate($hash, 'LastActionResult', 'Reboot properly initiated', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/reboot/;
		
		GetFileFromURL($url);
	} elsif (lc($key) eq 'wifi') {
		$value = lc($value);
		if ($value ne 'on' && $value ne 'off' && $value ne 'persist-off') {
			readingsSingleUpdate($hash, 'LastActionResult', 'Wrong parameter "'.$value.'". Use one of "off", "persist-off" or "on".', 1);
			
			return undef;
		}
		
		readingsSingleUpdate($hash, 'LastActionResult', 'WiFi properly set to '.$value, 1);
		
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/wifictrl?wifi=$value/;
		
		GetFileFromURL($url);
	} elsif (lc($key) eq 'name') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		# Hier die komplette restliche Zeile in den Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 2; $i < @a; $i++) {
			$text .= ' '.$a[$i];
		}
		
		SONOS_DoWork($udn, 'setName', $text);
	} elsif (lc($key) eq 'roomicon') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		$value = lc($value);
		
		if (SONOS_posInList($value, @possibleRoomIcons) != -1) {
			SONOS_DoWork($udn, 'setIcon', $value);
		} else {
			return 'Wrong icon name. Use one of "'.join('", "', @possibleRoomIcons).'".';
		}
	} else {
		return 'Not implemented yet!';
	}
	
	return (undef, 1);
}

########################################################################################
#
#  SONOSPLAYER_GetRealTargetPlayerHash - Retreives the Real Player Hash for Device-Commands
#			In Case of no grouping: the given hash (the normal device)
#			In Case of grouping: the hash of the groupmaster
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_GetRealTargetPlayerHash($) {
	my ($hash) = @_;
	
	my $udnShort = $1 if ($hash->{UDN} =~ m/(.*)_MR/);
	
	my $targetUDNShort = $udnShort;
	$targetUDNShort = $1 if (ReadingsVal($hash->{NAME}, 'ZoneGroupID', '') =~ m/(.*?):/);
	
	return SONOS_getSonosPlayerByUDN($targetUDNShort.'_MR') if ($udnShort ne $targetUDNShort);
	return $hash;
}

########################################################################################
#
#  SONOSPLAYER_GetMasterPlayerName - Retreives the Real Player Name for Device-Commands
#			In Case of no grouping: the given name (the normal device)
#			In Case of grouping: the name of the groupmaster
#
#  Parameter name = name of device, for which the master is searched
#
########################################################################################
sub SONOSPLAYER_GetMasterPlayerName($) {
	my ($name) = @_;
	
	return SONOSPLAYER_GetRealTargetPlayerHash(SONOS_getDeviceDefHash($name))->{NAME};
}

########################################################################################
#
#  SONOSPLAYER_GetSlavePlayerNames - Retreives all slave Players of the given player
#
#  Parameter name = name of device, for which the group is searched
#
########################################################################################
sub SONOSPLAYER_GetSlavePlayerNames($) {
	my ($name) = @_;
	
	my $hash = SONOS_getDeviceDefHash($name);
	my $sonosHash = SONOS_getDeviceDefHash(undef);	
	
	my @groups = SONOS_ConvertZoneGroupState(ReadingsVal($sonosHash->{NAME}, 'ZoneGroupState', ''));
	
	for my $group (@groups) {
		for my $elem (@{$group}) {
			if ($hash->{UDN} eq $elem) {
				# Diese Liste brauchen wir, aber ohne das erste Element (der Master)...
				shift(@{$group});
				
				# UDNs in Devicenamen umwandeln...
				foreach my $elem (@{$group}) {
					$elem = SONOS_getSonosPlayerByUDN($elem)->{NAME};
				}
				
				# Liste zurückgeben
				return sort(@{$group});
			}
		}
	}
	
	# Nix gefunden... also leere Liste liefern... Sollte nicht vorkommen...
	return ();
}

########################################################################################
#
#  SONOSPLAYER_Undef - Implements UndefFn function
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_Undef ($) {
	my ($hash) = @_;
  
	RemoveInternalTimer($hash);
  
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_Delete - Implements DeleteFn function
#
#  Parameter hash = hash of the master, name
#
########################################################################################
sub SONOSPLAYER_Delete($$) {
	my ($hash, $name) = @_;
	
	# Alle automatisch erzeugten Komponenten mit entfernen, sofern es sie noch gibt...
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RC_Notify');
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RC_Weblink');
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RC');
	
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RG');
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RG_Favourites');
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RG_Playlists');
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RG_Radios');
	
	# Das Entfernen des Sonos-Devices selbst übernimmt Fhem
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_DeleteIfExists - Deletes the Device with the given Name
#
#  Parameter hash = hash of the master, name
#
########################################################################################
sub SONOSPLAYER_DeleteIfExists($) {
	my ($name) = @_;
	
	CommandDelete(undef, $name) if ($main::defs{$name});
}

########################################################################################
#
#  SONOSPLAYER_Log - Log to the normal Log-command with additional Infomations like Thread-ID and the prefix 'SONOSPLAYER'
#
########################################################################################
sub SONOSPLAYER_Log($$$) {
	my ($devicename, $level, $text) = @_;
	  
	Log3 $devicename, $level, 'SONOSPLAYER'.threads->tid().': '.$text;
}

1;

=pod
=begin html

<a name="SONOSPLAYER"></a>
<h3>SONOSPLAYER</h3>
<p>FHEM module to work with a Sonos Zoneplayer</p>
<p>For more informations have also a closer look at the wiki at <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a></p>
<p>Normally you don't have to define a Sonosplayer-Device on your own, because the Sonos-Device will do this for you during the discovery-process.</p>
<h4>Example</h4>
<p>
<code>define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400_MR</code>
</p>
<a name="SONOSPLAYERdefine"></a>
<h4>Define</h4>
<b><code>define &lt;name&gt; SONOSPLAYER &lt;udn&gt;</code></b>
<p>
<b><code>&lt;udn&gt;</code></b><br /> MAC-Address based identifier of the zoneplayer</p>
<a name="SONOSPLAYERset"></a>
<h4>Set</h4>
<ul>
<li><b>Common Tasks</b><ul>
<li><a name="SONOSPLAYER_setter_Alarm">
<b><code>Alarm (Create|Update|Delete) &lt;ID&gt; &lt;Datahash&gt;</code></b></a>
<br />Can be used for working on alarms:<ul><li><b>Create:</b> Creates an alarm-entry with the given datahash.</li><li><b>Update:</b> Updates the alarm-entry with the given id and datahash.</li><li><b>Delete:</b> Deletes the alarm-entry with the given id.</li></ul><br /><b>The Datahash:</b><br />The Format is a perl-hash and is interpreted with the eval-function.<br />e.g.: { Repeat =&gt; 1 }<br /><br />The following entries are allowed/neccessary:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />e.g.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<b><code>DailyIndexRefreshTime &lt;time&gt;</code></b></a>
<br />Sets the current DailyIndexRefreshTime for the whole bunch of Zoneplayers.</li>
<li><a name="SONOSPLAYER_setter_Name">
<b><code>Name &lt;Zonename&gt;</code></b></a>
<br />Sets the Name for this Zone</li>
<li><a name="SONOSPLAYER_setter_OutputFixed">
<b><code>OutputFixed &lt;State&gt;</code></b></a>
<br /> Sets the outputfixed-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<b><code>Reboot</code></b></a>
<br />Initiates a reboot on the Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_RoomIcon">
<b><code>RoomIcon &lt;Iconname&gt;</code></b></a>
<br />Sets the Icon for this Zone</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<b><code>Wifi &lt;State&gt;</code></b></a>
<br />Sets the WiFi-State of the given Player. Can be 'off', 'persist-off' or 'on'.</li>
</ul></li>
<li><b>Playing Control-Commands</b><ul>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<b><code>CurrentTrackPosition &lt;TimePosition&gt;</code></b></a>
<br /> Sets the current timeposition inside the title to the given value.</li>
<li><a name="SONOSPLAYER_setter_Pause">
<b><code>Pause</code></b></a>
<br /> Pause the playing</li>
<li><a name="SONOSPLAYER_setter_Previous">
<b><code>Previous</code></b></a>
<br /> Jumps to the beginning of the previous title.</li>
<li><a name="SONOSPLAYER_setter_Play">
<b><code>Play</code></b></a>
<br /> Starts playing</li>
<li><a name="SONOSPLAYER_setter_PlayURI">
<b><code>PlayURI &lt;songURI&gt; [Volume]</code></b></a>
<br />Plays the given MP3-File with the optional given volume.</li>
<li><a name="SONOSPLAYER_setter_PlayURITemp">
<b><code>PlayURITemp &lt;songURI&gt; [Volume]</code></b></a>
<br />Plays the given MP3-File with the optional given volume as a temporary file. After playing it, the whole state is reconstructed and continues playing at the former saved position and volume and so on. If the file given is a stream (exactly: a file where the running time could not be determined), the call would be identical to <code>,PlayURI</code>, e.g. nothing is restored after playing.</li>
<li><a name="SONOSPLAYER_setter_Next">
<b><code>Next</code></b></a>
<br /> Jumps to the beginning of the next title</li>
<li><a name="SONOSPLAYER_setter_Speak">
<b><code>Speak &lt;Volume&gt; &lt;Language&gt; &lt;Text&gt;</code></b></a>
<br />Uses the Google Text-To-Speech-Engine for generating MP3-Files of the given text and plays it on the SonosPlayer. Possible languages can be obtained from Google. e.g. "de", "en", "fr", "es"...</li>
<li><a name="SONOSPLAYER_setter_StartFavourite">
<b><code>StartFavourite &lt;Favouritename&gt; [NoStart]</code></b></a>
<br /> Starts the named sonos-favorite. The parameter should be URL-encoded for proper naming of lists with special characters. If the Word 'NoStart' is given as second parameter, than the Loading will be done, but the playing-state is leaving untouched e.g. not started.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/meine.hits/</code>.</li>
<li><a name="SONOSPLAYER_setter_StartPlaylist">
<b><code>StartPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Loads the given Playlist and starts playing immediately. For all Options have a look at "LoadPlaylist".</li>
<li><a name="SONOSPLAYER_setter_StartRadio">
<b><code>StartRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Loads the named radiostation (favorite) and starts playing immediately. For all Options have a look at "LoadRadio".</li>
<li><a name="SONOSPLAYER_setter_StartSearchlist">
<b><code>StartSearchlist &lt;Categoryname&gt; &lt;CategoryElement&gt; [[TitlefilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [maxElem]]</code></b></a>
<br /> Loads the searchlist and starts playing immediately. For all Options have a look at "LoadSearchlist".</li>
<li><a name="SONOSPLAYER_setter_Stop">
<b><code>Stop</code></b></a>
<br /> Stops the playing</li>
<li><a name="SONOSPLAYER_setter_Track">
<b><code>Track &lt;TrackNumber|Random&gt;</code></b></a>
<br /> Sets the track with the given tracknumber as the current title. If the tracknumber is the word <code>Random</code> a random track will be selected.</li>
</ul></li>
<li><b>Playing Settings</b><ul>
<li><a name="SONOSPLAYER_setter_Balance">
<b><code>Balance &lt;BalanceValue&gt;</code></b></a>
<br /> Sets the balance to the given value. The value can range from -100 (full left) to 100 (full right). Retrieves the new balancevalue as the result.</li>
<li><a name="SONOSPLAYER_setter_Bass">
<b><code>Bass &lt;BassValue&gt;</code></b></a>
<br /> Sets the bass to the given value. The value can range from -10 to 10. Retrieves the new bassvalue as the result.</li>
<li><a name="SONOSPLAYER_setter_CrossfadeMode">
<b><code>CrossfadeMode &lt;State&gt;</code></b></a>
<br /> Sets the crossfade-mode. Retrieves the new mode as the result.</li>
<li><a name="SONOSPLAYER_setter_LEDState">
<b><code>LEDState &lt;State&gt;</code></b></a>
<br /> Sets the LED state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Loudness">
<b><code>Loudness &lt;State&gt;</code></b></a>
<br /> Sets the loudness-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Mute">
<b><code>Mute &lt;State&gt;</code></b></a>
<br /> Sets the mute-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_MuteT">
<b><code>MuteT</code></b></a>
<br /> Toggles the mute state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Repeat">
<b><code>Repeat &lt;State&gt;</code></b></a>
<br /> Sets the repeat-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_RepeatT">
<b><code>RepeatT</code></b></a>
<br /> Toggles the repeat-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Shuffle">
<b><code>Shuffle &lt;State&gt;</code></b></a>
<br /> Sets the shuffle-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_ShuffleT">
<b><code>ShuffleT</code></b></a>
<br /> Toggles the shuffle-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_SleepTimer">
<b><code>SleepTimer &lt;Time&gt;</code></b></a>
<br /> Sets the Sleeptimer to the given Time. It must be in the full format of "HH:MM:SS". Deactivate with "00:00:00" or "off".</li>
<li><a name="SONOSPLAYER_setter_Treble">
<b><code>Treble &lt;TrebleValue&gt;</code></b></a>
<br /> Sets the treble to the given value. The value can range from -10 to 10. Retrieves the new treblevalue as the result.</li>
<li><a name="SONOSPLAYER_setter_Volume">
<b><code>Volume &lt;VolumeLevel&gt; [RampType]</code></b></a>
<br /> Sets the volume to the given value. The value could be a relative value with + or - sign. In this case the volume will be increased or decreased according to this value. Retrieves the new volume as the result.<br />Optional can be a RampType defined  with a value between 1 and 3 which describes different templates defined by the Sonos-System.</li>
<li><a name="SONOSPLAYER_setter_VolumeD">
<b><code>VolumeD</code></b></a>
<br /> Turns the volume by volumeStep-ticks down.</li>
<li><a name="SONOSPLAYER_setter_VolumeRestore">
<b><code>VolumeRestore</code></b></a>
<br /> Restores the volume of a formerly saved volume.</li>
<li><a name="SONOSPLAYER_setter_VolumeSave">
<b><code>VolumeSave &lt;VolumeLevel&gt;</code></b></a>
<br /> Sets the volume to the given value. The value could be a relative value with + or - sign. In this case the volume will be increased or decreased according to this value. Retrieves the new volume as the result. Additionally it saves the old volume to a reading for restoreing.</li>
<li><a name="SONOSPLAYER_setter_VolumeU">
<b><code>VolumeU</code></b></a>
<br /> Turns the volume by volumeStep-ticks up.</li>
</ul></li>
<li><b>Control the current Playlist</b><ul>
<li><a name="SONOSPLAYER_setter_AddURIToQueue">
<b><code>AddURIToQueue &lt;songURI&gt;</code></b></a>
<br />Adds the given MP3-File at the current position into the queue.</li>
<li><a name="SONOSPLAYER_setter_CurrentPlaylist">
<b><code>CurrentPlaylist</code></b></a>
<br /> Sets the current playing to the current queue, but doesn't start playing (e.g. after hearing of a radiostream, where the current playlist still exists but is currently "not in use")</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<b><code>EmptyPlaylist</code></b></a>
<br /> Clears the current queue</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<b><code>LoadPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Loads the named playlist to the current playing queue. The parameter should be URL-encoded for proper naming of lists with special characters. The Playlistname can be a filename and then must be startet with 'file:' (e.g. 'file:c:/Test.m3u')<br />If EmptyQueueBeforeImport is given and set to 1, the queue will be emptied before the import process. If not given, the parameter will be interpreted as 1.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/hits.2014/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<b><code>LoadRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Loads the named radiostation (favorite). The current queue will not be touched but deactivated. The parameter should be URL-encoded for proper naming of lists with special characters.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/radio/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadSearchlist">
<b><code>LoadSearchlist &lt;Categoryname&gt; &lt;CategoryElement&gt; [[TitlefilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [maxElem]]</code></b></a>
<br /> Loads titles from the Sonos-Bibliothek into the current playlist according to the given category and filtervalues. Please consult the (german) Wiki for detailed informations.</li>
<li><a name="SONOSPLAYER_setter_SavePlaylist">
<b><code>SavePlaylist &lt;Playlistname&gt;</code></b></a>
<br /> Saves the current queue as a playlist with the given name. An existing playlist with the same name will be overwritten. The parameter should be URL-encoded for proper naming of lists with special characters. The Playlistname can be a filename and then must be startet with 'file:' (e.g. 'file:c:/Test.m3u')</li>
</ul></li>
<li><b>Groupcontrol</b><ul>
<li><a name="SONOSPLAYER_setter_AddMember">
<b><code>AddMember &lt;devicename&gt;</code></b></a>
<br />Adds the given devicename to the current device as a groupmember. The current playing of the current device goes on and will be transfered to the given device (the new member).</li>
<li><a name="SONOSPLAYER_setter_CreateStereoPair">
<b><code>CreateStereoPair &lt;rightPlayerDevicename&gt;</code></b></a>
<br />Adds the given devicename to the current device as the right speaker of a stereopair. The current playing of the current device goes on (as left-side speaker) and will be transfered to the given device (as right-side speaker).</li>
<li><a name="SONOSPLAYER_setter_GroupMute">
<b><code>GroupMute &lt;State&gt;</code></b></a>
<br />Sets the mute state of the complete group in one step. The value can be on or off.</li>
<li><a name="SONOSPLAYER_setter_GroupVolume">
<b><code>GroupVolume &lt;VolumeLevel&gt;</code></b></a>
<br />Sets the group-volume in the way the original controller does. This means, that the relative volumelevel between the different players will be saved during change.</li>
<li><a name="SONOSPLAYER_setter_RemoveMember">
<b><code>RemoveMember &lt;devicename&gt;</code></b></a>
<br />Removes the given device, so that they both are not longer a group. The current playing of the current device goes on normally. The cutted device stops his playing and has no current playlist anymore (since Sonos Version 4.2 the old playlist will be restored).</li>
<li><a name="SONOSPLAYER_setter_SeparateStereoPair">
<b><code>SeparateStereoPair</code></b></a>
<br />Divides the stereo-pair into two independant devices.</li>
<li><a name="SONOSPLAYER_setter_SnapshotGroupVolume">
<b><code>SnapshotGroupVolume</code></b></a>
<br /> Save the current volume-relation of all players of the same group. It's neccessary for the use of "GroupVolume" and is stored until the next call of "SnapshotGroupVolume".</li>
</ul></li>
</ul>
<br />
<a name="SONOSPLAYERget"></a> 
<h4>Get</h4>
<ul>
<li><b>Common</b><ul>
<li><a name="SONOSPLAYER_getter_Alarm">
<b><code>Alarm &lt;ID&gt;</code></b></a>
<br /> It's an exception to the normal getter semantics. Returns directly a Perl-Hash with the Alarm-Informations to the given id. It's just a shorthand for <code>eval(ReadingsVal(&lt;Devicename&gt;, 'Alarmlist', ()))->{&lt;ID&gt;};</code>.</li>
<li><a name="SONOSPLAYER_getter_EthernetPortStatus">
<b><code>EthernetPortStatus &lt;PortNumber&gt;</code></b></a>
<br /> Gets the Ethernet-Portstatus of the given Port. Can be 'Active' or 'Inactive'.</li>
<li><a name="SONOSPLAYER_getter_PossibleRoomIcons">
<b><code>PossibleRoomIcons</code></b></a>
<br /> Retreives a list of all possible Roomiconnames for the use with "set RoomIcon".</li>
</ul></li>
<li><b>Lists</b><ul>
<li><a name="SONOSPLAYER_getter_Favourites">
<b><code>Favourites</code></b></a>
<br /> Retrieves a list with the names of all sonos favourites. This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of favourites. e.g. "Liste 1","Entry 2","Test"</li>
<li><a name="SONOSPLAYER_getter_FavouritesWithCovers">
<b><code>FavouritesWithCovers</code></b></a>
<br /> Retrieves a list with the stringrepresentation of a perl-hash which can easily be converted with "eval". It consists of the names and coverlinks of all of the favourites stored in Sonos e.g. {'FV:2/22' => {'Cover' => 'urlzumcover', 'Title' => '1. Favorit'}}</li>
<li><a name="SONOSPLAYER_getter_Playlists">
<b><code>Playlists</code></b></a>
<br /> Retrieves a list with the names of all saved queues (aka playlists). This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of playlists. e.g. "Liste 1","Liste 2","Test"</li>
<li><a name="SONOSPLAYER_getter_PlaylistsWithCovers">
<b><code>PlaylistsWithCovers</code></b></a>
<br /> Retrieves a list with the stringrepresentation of a perl-hash which can easily be converted with "eval". It consists of the names and coverlinks of all of the playlists stored in Sonos e.g. {'SQ:14' => {'Cover' => 'urlzumcover', 'Title' => '1. Playlist'}}</li>
<li><a name="SONOSPLAYER_getter_Radios">
<b><code>Radios</code></b></a>
<br /> Retrieves a list with the names of all saved radiostations (favorites). This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of radiostations. e.g. "Sender 1","Sender 2","Test"</li>
<li><a name="SONOSPLAYER_getter_RadiosWithCovers">
<b><code>RadiosWithCovers</code></b></a>
<br /> Retrieves a list with the stringrepresentation of a perl-hash which can easily be converted with "eval". It consists of the names and coverlinks of all of the radiofavourites stored in Sonos e.g. {'R:0/0/2' => {'Cover' => 'urlzumcover', 'Title' => '1. Radiosender'}}</li>
<li><a name="SONOSPLAYER_getter_SearchlistCategories">
<b><code>SearchlistCategories</code></b></a>
<br /> Retrieves a list with the possible categories for the setter "LoadSearchlist". The Format is a comma-separated list with quoted names of categories.</li>
</ul></li>
<li><b>Informations on the current Title</b><ul>
<li><a name="SONOSPLAYER_getter_CurrentTrackPosition">
<b><code>CurrentTrackPosition</code></b></a>
<br /> Retrieves the current timeposition inside a title</li>
</ul></li>
</ul>
<br />
<a name="SONOSPLAYERattr"></a>
<h4>Attributes</h4>
'''Attention'''<br />The attributes can only be used after a restart of fhem, because it must be initially transfered to the subprocess.
<ul>
<li><b>Common</b><ul>
<li><a name="SONOSPLAYER_attribut_disable"><b><code>disable &lt;int&gt;</code></b>
</a><br /> One of (0,1). Disables the event-worker for this Sonosplayer.</li>
<li><a name="SONOSPLAYER_attribut_generateSomethingChangedEvent"><b><code>generateSomethingChangedEvent &lt;int&gt;</code></b>
</a><br /> One of (0,1). 1 if a 'SomethingChanged'-Event should be generated. This event is thrown every time an event is generated. This is useful if you wants to be notified on every change with a single event.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeEvent"><b><code>generateVolumeEvent &lt;int&gt;</code></b>
</a><br /> One of (0,1). Enables an event generated at volumechanges if minVolume or maxVolume is set.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeSlider"><b><code>generateVolumeSlider &lt;int&gt;</code></b>
</a><br /> One of (0,1). Enables a slider for volumecontrol in detail view.</li>
<li><a name="SONOSPLAYER_attribut_getAlarms"><b><code>getAlarms &lt;int&gt;</code></b>
</a><br /> One of (0..1). Initializes a callback-method for Alarms. This included the information of the DailyIndexRefreshTime.</li>
<li><a name="SONOSPLAYER_attribut_volumeStep"><b><code>volumeStep &lt;int&gt;</code></b>
</a><br /> One of (0..100). Defines the stepwidth for subsequent calls of <code>VolumeU</code> and <code>VolumeD</code>.</li>
</ul></li>
<li><b>Information Generation</b><ul>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize1"><b><code>generateInfoSummarize1 &lt;string&gt;</code></b>
</a><br /> Generates the reading 'InfoSummarize1' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize2"><b><code>generateInfoSummarize2 &lt;string&gt;</code></b>
</a><br /> Generates the reading 'InfoSummarize2' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize3"><b><code>generateInfoSummarize3 &lt;string&gt;</code></b>
</a><br /> Generates the reading 'InfoSummarize3' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize4"><b><code>generateInfoSummarize4 &lt;string&gt;</code></b>
</a><br /> Generates the reading 'InfoSummarize4' with the given format. More Information on this in the examples-section.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><b><code>stateVariable &lt;string&gt;</code></b>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,<br />Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,<br />nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,CrossfadeMode,Balance,<br />HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,<br />InfoSummarize2,InfoSummarize3,InfoSummarize4). Defines, which variable has to be copied to the content of the state-variable.</li>
</ul></li>
<li><b>Controloptions</b><ul>
<li><a name="SONOSPLAYER_attribut_maxVolume"><b><code>maxVolume &lt;int&gt;</code></b>
</a><br /> One of (0..100). Define a maximal volume for this Zoneplayer</li>
<li><a name="SONOSPLAYER_attribut_minVolume"><b><code>minVolume &lt;int&gt;</code></b>
</a><br /> One of (0..100). Define a minimal volume for this Zoneplayer</li>
<li><a name="SONOSPLAYER_attribut_maxVolumeHeadphone"><b><code>maxVolumeHeadphone &lt;int&gt;</code></b>
</a><br /> One of (0..100). Define a maximal volume for this Zoneplayer for use with headphones</li>
<li><a name="SONOSPLAYER_attribut_minVolumeHeadphone"><b><code>minVolumeHeadphone &lt;int&gt;</code></b>
</a><br /> One of (0..100). Define a minimal volume for this Zoneplayer for use with headphones</li>
<li><a name="SONOSPLAYER_attribut_buttonEvents"><b><code>buttonEvents &lt;Time:Pattern&gt;[ &lt;Time:Pattern&gt; ...]</code></b>
</a><br /> Defines that after pressing a specified sequence of buttons at the player an event has to be thrown. The definition itself is a tupel: the first part (before the colon) is the time in seconds, the second part (after the colon) is the button sequence of this event.<br />
The following button-shortcuts are possible: <ul><li><b>M</b>: The Mute-Button</li><li><b>H</b>: The Headphone-Connector</li><li><b>U</b>: Up-Button (Volume Up)</li><li><b>D</b>: Down-Button (Volume Down)</li></ul><br />
The event thrown is named <code>ButtonEvent</code>, the value is the defined button-sequence.<br />
E.G.: <code>2:MM</code><br />
Here an event is defined, where in time of 2 seconds the Mute-Button has to be pressed 2 times. The created event is named <code>ButtonEvent</code> and has the value <code>MM</code>.</li>
</ul></li>
</ul>
<a name="SONOSPLAYERexamples"></a>
<h4>Examples / Tips</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format of InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;|:summarizeElem:</code><br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ instead=":text:"][ ifempty=":text:"]/[ emptyVal=":text:"]&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|<br />Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|<br />nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|CrossfadeMode|Balance|<br />HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|<br />InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
<code>:text: := [Any text without double-quotes]</code><br /></li>
</ul>

=end html

=begin html_DE

<a name="SONOSPLAYER"></a>
<h3>SONOSPLAYER</h3>
<p>FHEM Modul für die Steuerung eines Sonos Zoneplayer</p>
<p>Für weitere Hinweise und Beschreibungen bitte auch im Wiki unter <a href="http://www.fhemwiki.de/wiki/SONOS">http://www.fhemwiki.de/wiki/SONOS</a> nachschauen.</p>
<p>Im Normalfall braucht man dieses Device nicht selber zu definieren, da es automatisch vom Discovery-Process des Sonos-Device erzeugt wird.</p>
<h4>Example</h4>
<p>
<code>define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400_MR</code>
</p>
<a name="SONOSPLAYERdefine"></a>
<h4>Definition</h4>
<b><code>define &lt;name&gt; SONOSPLAYER &lt;udn&gt;</code></b>
<p>
<b><code>&lt;udn&gt;</code></b><br /> MAC-Addressbasierter eindeutiger Bezeichner des Zoneplayer</p>
<a name="SONOSPLAYERset"></a>
<h4>Set</h4>
<ul>
<li><b>Grundsätzliche Einstellungen</b><ul>
<li><a name="SONOSPLAYER_setter_Alarm">
<b><code>Alarm (Create|Update|Delete) &lt;ID&gt; &lt;Datahash&gt;</code></b></a>
<br />Diese Anweisung wird für die Bearbeitung der Alarme verwendet:<ul><li><b>Create:</b> Erzeugt einen neuen Alarm-Eintrag mit den übergebenen Hash-Daten.</li><li><b>Update:</b> Aktualisiert den Alarm mit der übergebenen ID und den angegebenen Hash-Daten.</li><li><b>Delete:</b> Löscht den Alarm-Eintrag mit der übergebenen ID.</li></ul><br /><b>Die Hash-Daten:</b><br />Das Format ist ein Perl-Hash und wird mittels der eval-Funktion interpretiert.<br />e.g.: { Repeat =&gt; 1 }<br /><br />Die folgenden Schlüssel sind zulässig/notwendig:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />z.B.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<b><code>DailyIndexRefreshTime &lt;time&gt;</code></b></a>
<br />Setzt die aktuell gültige DailyIndexRefreshTime für alle Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_Name">
<b><code>Name &lt;Zonename&gt;</code></b></a>
<br />Legt den Namen der Zone fest.</li>
<li><a name="SONOSPLAYER_setter_OutputFixed">
<b><code>OutputFixed &lt;State&gt;</code></b></a>
<br /> Setzt den angegebenen OutputFixed-Zustand. Liefert den aktuell gültigen OutputFixed-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<b><code>Reboot</code></b></a>
<br />Führt für den Zoneplayer einen Neustart durch.</li>
<li><a name="SONOSPLAYER_setter_RoomIcon">
<b><code>RoomIcon &lt;Iconname&gt;</code></b></a>
<br />Legt das Icon für die Zone fest</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<b><code>Wifi &lt;State&gt;</code></b></a>
<br />Setzt den WiFi-Zustand des Players. Kann 'off', 'persist-off' oder 'on' sein.</li>
</ul></li>
<li><b>Abspiel-Steuerbefehle</b><ul>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<b><code>CurrentTrackPosition &lt;TimePosition&gt;</code></b></a>
<br /> Setzt die Abspielposition innerhalb des Liedes auf den angegebenen Zeitwert (z.B. 0:01:15).</li>
<li><a name="SONOSPLAYER_setter_Pause">
<b><code>Pause</code></b></a>
<br /> Pausiert die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_Previous">
<b><code>Previous</code></b></a>
<br /> Springt an den Anfang des vorherigen Titels.</li>
<li><a name="SONOSPLAYER_setter_Play">
<b><code>Play</code></b></a>
<br /> Startet die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_PlayURI">
<b><code>PlayURI &lt;songURI&gt; [Volume]</code></b></a>
<br /> Spielt die angegebene MP3-Datei ab. Dabei kann eine Lautstärke optional mit angegeben werden.</li>
<li><a name="SONOSPLAYER_setter_PlayURITemp">
<b><code>PlayURITemp &lt;songURI&gt; [Volume]</code></b></a>
<br /> Spielt die angegebene MP3-Datei mit der optionalen Lautstärke als temporäre Wiedergabe ab. Nach dem Abspielen wird der vorhergehende Zustand wiederhergestellt, und läuft an der unterbrochenen Stelle weiter. Wenn die Länge der Datei nicht ermittelt werden kann (z.B. bei Streams), läuft die Wiedergabe genauso wie bei <code>PlayURI</code> ab, es wird also nichts am Ende (wenn es eines geben sollte) wiederhergestellt.</li>
<li><a name="SONOSPLAYER_setter_Next">
<b><code>Next</code></b></a>
<br /> Springt an den Anfang des nächsten Titels</li>
<li><a name="SONOSPLAYER_setter_Speak">
<b><code>Speak &lt;Volume&gt; &lt;Language&gt; &lt;Text&gt;</code></b></a>
<br /> Verwendet die Google Text-To-Speech-Engine um den angegebenen Text in eine MP3-Datei umzuwandeln und anschließend mittels <code>PlayURITemp</code> als Durchsage abzuspielen. Mögliche Sprachen können auf der Google-Seite nachgesehen werden. Möglich sind z.B. "de", "en", "fr", "es"...</li>
<li><a name="SONOSPLAYER_setter_StartFavourite">
<b><code>StartFavourite &lt;FavouriteName&gt; [NoStart]</code></b></a>
<br /> Startet den angegebenen Favoriten. Der Name bezeichnet einen Eintrag in der Sonos-Favoritenliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Wenn das Wort 'NoStart' als zweiter Parameter angegeben wurde, dann wird der Favorit geladen und fertig vorbereitet, aber nicht explizit gestartet.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/meine.hits/</code>.</li>
<li><a name="SONOSPLAYER_setter_StartPlaylist">
<b><code>StartPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Lädt die benannte Playlist und startet sofort die Wiedergabe. Zu den Parametern und Bemerkungen bitte unter "LoadPlaylist" nachsehen.</li>
<li><a name="SONOSPLAYER_setter_StartRadio">
<b><code>StartRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Lädt den benannten Radiosender, genauer gesagt, den benannten Radiofavoriten und startet sofort die Wiedergabe. Dabei wird die bestehende Abspielliste beibehalten, aber deaktiviert. Der Parameter kann/muss URL-Encoded sein, um auch Leer- und Sonderzeichen angeben zu können.</li>
<li><a name="SONOSPLAYER_setter_StartSearchlist">
<b><code>StartSearchlist &lt;Kategoriename&gt; &lt;KategorieElement&gt; [[TitelfilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [maxElem]]</code></b></a>
<br /> Lädt die Searchlist und startet sofort die Wiedergabe. Für nähere Informationen bitte unter "LoadSearchlist" nachschlagen.</li>
<li><a name="SONOSPLAYER_setter_Stop">
<b><code>Stop</code></b></a>
<br /> Stoppt die Wiedergabe</li>
<li><a name="SONOSPLAYER_setter_Track">
<b><code>Track &lt;TrackNumber|Random&gt;</code></b></a>
<br /> Aktiviert den angebenen Titel der aktuellen Abspielliste. Wenn als Tracknummer der Wert <code>Random</code> angegeben wird, dann wird eine zufällige Trackposition ausgewählt.</li>
</ul></li>
<li><b>Einstellungen zum Abspielen</b><ul>
<li><a name="SONOSPLAYER_setter_Balance">
<b><code>Balance &lt;BalanceValue&gt;</code></b></a>
<br /> Setzt die Balance auf den angegebenen Wert. Der Wert kann zwischen -100 (voll links) bis 100 (voll rechts) sein. Gibt die wirklich eingestellte Balance als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_Bass">
<b><code>Bass &lt;BassValue&gt;</code></b></a>
<br /> Setzt den Basslevel auf den angegebenen Wert. Der Wert kann zwischen -10 bis 10 sein. Gibt den wirklich eingestellten Basslevel als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_CrossfadeMode">
<b><code>CrossfadeMode &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des Crossfade-Mode fest. Liefert den aktuell gültigen Crossfade-Mode.</li>
<li><a name="SONOSPLAYER_setter_LEDState">
<b><code>LEDState &lt;State&gt;</code></b></a>
<br /> Legt den Zustand der LED fest. Liefert den aktuell gültigen Zustand.</li>
<li><a name="SONOSPLAYER_setter_Loudness">
<b><code>Loudness &lt;State&gt;</code></b></a>
<br /> Setzt den angegebenen Loudness-Zustand. Liefert den aktuell gültigen Loudness-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Mute">
<b><code>Mute &lt;State&gt;</code></b></a>
<br /> Setzt den angegebenen Mute-Zustand. Liefert den aktuell gültigen Mute-Zustand.</li>
<li><a name="SONOSPLAYER_setter_MuteT">
<b><code>MuteT</code></b></a>
<br /> Schaltet den Zustand des Mute-Zustands um. Liefert den aktuell gültigen Mute-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Repeat">
<b><code>Repeat &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des Repeat-Zustands fest. Liefert den aktuell gültigen Repeat-Zustand.</li>
<li><a name="SONOSPLAYER_setter_RepeatT">
<b><code>RepeatT</code></b></a>
<br /> Schaltet den Zustand des Repeat-Zustands um. Liefert den aktuell gültigen Repeat-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Shuffle">
<b><code>Shuffle &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des Shuffle-Zustands fest. Liefert den aktuell gültigen Shuffle-Zustand.</li>
<li><a name="SONOSPLAYER_setter_ShuffleT">
<b><code>ShuffleT</code></b></a>
<br /> Schaltet den Zustand des Shuffle-Zustands um. Liefert den aktuell gültigen Shuffle-Zustand.</li>
<li><a name="SONOSPLAYER_setter_SleepTimer">
<b><code>SleepTimer &lt;Time&gt;</code></b></a>
<br /> Legt den aktuellen SleepTimer fest. Der Wert muss ein kompletter Zeitstempel sein (HH:MM:SS). Zum Deaktivieren darf der Zeitstempel nur Nullen enthalten oder das Wort 'off'.</li>
<li><a name="SONOSPLAYER_setter_Treble">
<b><code>Treble &lt;TrebleValue&gt;</code></b></a>
<br /> Setzt den Treblelevel auf den angegebenen Wert. Der Wert kann zwischen -10 bis 10 sein. Gibt den wirklich eingestellten Treblelevel als Ergebnis zurück.</li>
<li><a name="SONOSPLAYER_setter_Volume">
<b><code>Volume &lt;VolumeLevel&gt; [RampType]</code></b></a>
<br /> Setzt die aktuelle Lautstärke auf den angegebenen Wert. Der Wert kann ein relativer Wert mittels + oder - Zeichen sein. Liefert den aktuell gültigen Lautstärkewert zurück.<br />Optional kann ein RampType übergeben werden, der einen Wert zwischen 1 und 3 annehmen kann, und verschiedene von Sonos festgelegte Muster beschreibt.</li>
<li><a name="SONOSPLAYER_setter_VolumeD">
<b><code>VolumeD</code></b></a>
<br /> Verringert die aktuelle Lautstärke um volumeStep-Einheiten.</li>
<li><a name="SONOSPLAYER_setter_VolumeRestore">
<b><code>VolumeRestore</code></b></a>
<br /> Stellt die mittels <code>VolumeSave</code> gespeicherte Lautstärke wieder her.</li>
<li><a name="SONOSPLAYER_setter_VolumeSave">
<b><code>VolumeSave &lt;VolumeLevel&gt;</code></b></a>
<br /> Setzt die aktuelle Lautstärke auf den angegebenen Wert. Der Wert kann ein relativer Wert mittels + oder - Zeichen sein. Liefert den aktuell gültigen Lautstärkewert zurück. Zusätzlich wird der alte Lautstärkewert gespeichert und kann mittels <code>VolumeRestore</code> wiederhergestellt werden.</li>
<li><a name="SONOSPLAYER_setter_VolumeU">
<b><code>VolumeU</code></b></a>
<br /> Erhöht die aktuelle Lautstärke um volumeStep-Einheiten.</li>
</ul></li>
<li><b>Steuerung der aktuellen Abspielliste</b><ul>
<li><a name="SONOSPLAYER_setter_AddURIToQueue">
<b><code>AddURIToQueue &lt;songURI&gt;</code></b></a>
<br /> Fügt die angegebene MP3-Datei an der aktuellen Stelle in die Abspielliste ein.</li>
<li><a name="SONOSPLAYER_setter_CurrentPlaylist">
<b><code>CurrentPlaylist</code></b></a>
<br /> Setzt den Abspielmodus auf die aktuelle Abspielliste, startet aber keine Wiedergabe (z.B. nach dem Hören eines Radiostreams, wo die aktuelle Abspielliste noch existiert, aber gerade "nicht verwendet" wird)</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<b><code>EmptyPlaylist</code></b></a>
<br /> Leert die aktuelle Abspielliste</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<b><code>LoadPlaylist &lt;Playlistname&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Lädt die angegebene Playlist in die aktuelle Abspielliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Der Playlistname kann auch ein Dateiname sein. Dann muss dieser mit 'file:' beginnen (z.B. 'file:c:/Test.m3u).<br />Wenn der Parameter EmptyQueueBeforeImport mit ''1'' angegeben wirde, wird die aktuelle Abspielliste vor dem Import geleert. Standardmäßig wird hier ''1'' angenommen.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/hits.2014/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<b><code>LoadRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Startet den angegebenen Radiostream. Der Name bezeichnet einen Sender in der Radiofavoritenliste. Die aktuelle Abspielliste wird nicht verändert. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/radio/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadSearchlist">
<b><code>LoadSearchlist &lt;Kategoriename&gt; &lt;KategorieElement&gt; [[TitelfilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [maxElem]]</code></b></a>
<br /> Lädt Titel nach diversen Kriterien in die aktuelle Abspielliste. Nähere Beschreibung bitte im Wiki nachlesen.</li>
<li><a name="SONOSPLAYER_setter_SavePlaylist">
<b><code>SavePlaylist &lt;Playlistname&gt;</code></b></a>
<br /> Speichert die aktuelle Abspielliste unter dem angegebenen Namen. Eine bestehende Playlist mit diesem Namen wird überschrieben. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Der Playlistname kann auch ein Dateiname sein. Dann muss dieser mit 'file:' beginnen (z.B. 'file:c:/Test.m3u).</li>
</ul></li>
<li><b>Gruppenbefehle</b><ul>
<li><a name="SONOSPLAYER_setter_AddMember">
<b><code>AddMember &lt;devicename&gt;</code></b></a>
<br />Fügt dem Device das übergebene Device als Gruppenmitglied hinzu. Die Wiedergabe des aktuellen Devices bleibt erhalten, und wird auf das angegebene Device mit übertragen.</li>
<li><a name="SONOSPLAYER_setter_CreateStereoPair">
<b><code>CreateStereoPair &lt;rightPlayerDevicename&gt;</code></b></a>
<br />Fügt dem Device das übergebene Device als rechtes Stereopaar-Element hinzu. Die Wiedergabe des aktuellen Devices bleibt erhalten (als linker Lautsprecher), und wird auf das angegebene Device mit übertragen (als rechter Lautsprecher).</li>
<li><a name="SONOSPLAYER_setter_GroupMute">
<b><code>GroupMute &lt;State&gt;</code></b></a>
<br />Setzt den Mute-Zustand für die komplette Gruppe in einem Schritt. Der Wert kann on oder off sein.</li>
<li><a name="SONOSPLAYER_setter_GroupVolume">
<b><code>GroupVolume &lt;VolumeLevel&gt;</code></b></a>
<br />Setzt die Gruppenlautstärke in der Art des Original-Controllers. Das bedeutet, dass das Lautstärkeverhältnis der Player zueinander beim Anpassen erhalten bleibt.</li>
<li><a name="SONOSPLAYER_setter_RemoveMember">
<b><code>RemoveMember &lt;devicename&gt;</code></b></a>
<br />Entfernt dem Device das übergebene Device, sodass die beiden keine Gruppe mehr bilden. Die Wiedergabe des aktuellen Devices läuft normal weiter. Das abgetrennte Device stoppt seine Wiedergabe, und hat keine aktuelle Abspielliste mehr (seit Sonos Version 4.2 hat der Player wieder die Playliste von vorher aktiv).</li>
<li><a name="SONOSPLAYER_setter_SeparateStereoPair">
<b><code>SeparateStereoPair</code></b></a>
<br />Trennt das Stereopaar wieder auf.</li>
<li><a name="SONOSPLAYER_setter_SnapshotGroupVolume">
<b><code>SnapshotGroupVolume</code></b></a>
<br /> Legt das Lautstärkeverhältnis der aktuellen Player der Gruppe für folgende '''GroupVolume'''-Aufrufe fest. Dieses festgelegte Verhältnis wird bis zum nächsten Aufruf von '''SnapshotGroupVolume''' beibehalten.</li>
</ul></li>
</ul>
<br />
<a name="SONOSPLAYERget"></a> 
<h4>Get</h4>
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="SONOSPLAYER_getter_Alarm">
<b><code>Alarm &lt;ID&gt;</code></b></a>
<br /> Ausnahmefall. Diese Get-Anweisung liefert direkt ein Hash zurück, in welchem die Informationen des Alarms mit der gegebenen ID enthalten sind. Es ist die Kurzform für <code>eval(ReadingsVal(&lt;Devicename&gt;, 'Alarmlist', ()))->{&lt;ID&gt;};</code>, damit sich nicht jeder ausdenken muss, wie er jetzt am einfachsten an die Alarm-Informationen rankommen kann.</li>
<li><a name="SONOSPLAYER_getter_EthernetPortStatus">
<b><code>EthernetPortStatus &lt;PortNumber&gt;</code></b></a>
<br /> Liefert den Ethernet-Portstatus des gegebenen Ports. Kann 'Active' oder 'Inactive' liefern.</li>
<li><a name="SONOSPLAYER_getter_PossibleRoomIcons">
<b><code>PossibleRoomIcons</code></b></a>
<br /> Liefert eine Liste aller möglichen RoomIcon-Bezeichnungen zurück.</li>
</ul></li>
<li><b>Listen</b><ul>
<li><a name="SONOSPLAYER_getter_Favourites">
<b><code>Favourites</code></b></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Sonos-Favoriten. Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Liste 1","Eintrag 2","Test"</li>
<li><a name="SONOSPLAYER_getter_FavouritesWithCovers">
<b><code>FavouritesWithCovers</code></b></a>
<br /> Liefert die Stringrepräsentation eines Hash mit den Namen und Covern aller gespeicherten Sonos-Favoriten. Z.B.: {'FV:2/22' => {'Cover' => 'urlzumcover', 'Title' => '1. Favorit'}}. Dieser String kann einfach mit '''eval''' in eine Perl-Datenstruktur umgewandelt werden.</li>
<li><a name="SONOSPLAYER_getter_Playlists">
<b><code>Playlists</code></b></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Playlists. Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Liste 1","Liste 2","Test"</li>
<li><a name="SONOSPLAYER_getter_PlaylistsWithCovers">
<b><code>PlaylistsWithCovers</code></b></a>
<br /> Liefert die Stringrepräsentation eines Hash mit den Namen und Covern aller gespeicherten Sonos-Playlisten. Z.B.: {'SQ:14' => {'Cover' => 'urlzumcover', 'Title' => '1. Playlist'}}. Dieser String kann einfach mit '''eval''' in eine Perl-Datenstruktur umgewandelt werden.</li>
<li><a name="SONOSPLAYER_getter_Radios">
<b><code>Radios</code></b></a>
<br /> Liefert eine Liste mit den Namen aller gespeicherten Radiostationen (Favoriten). Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "Sender 1","Sender 2","Test"</li>
<li><a name="SONOSPLAYER_getter_RadiosWithCovers">
<b><code>RadiosWithCovers</code></b></a>
<br /> Liefert die Stringrepräsentation eines Hash mit den Namen und Covern aller gespeicherten Sonos-Radiofavoriten. Z.B.: {'R:0/0/2' => {'Cover' => 'urlzumcover', 'Title' => '1. Radiosender'}}. Dieser String kann einfach mit '''eval''' in eine Perl-Datenstruktur umgewandelt werden.</li>
<li><a name="SONOSPLAYER_getter_SearchlistCategories">
<b><code>SearchlistCategories</code></b></a>
<br /> Liefert eine Liste mit den Namen alle möglichen Kategorien für den Aufruf von "LoadSearchlist". Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen.</li>
</ul></li>
<li><b>Informationen zum aktuellen Titel</b><ul>
<li><a name="SONOSPLAYER_getter_CurrentTrackPosition">
<b><code>CurrentTrackPosition</code></b></a>
<br /> Liefert die aktuelle Position innerhalb des Titels.</li>
</ul></li>
</ul>
<br />
<a name="SONOSPLAYERattr"></a>
<h4>Attribute</h4>
'''Hinweis'''<br />Die Attribute werden erst bei einem Neustart von Fhem verwendet, da diese dem SubProzess initial zur Verfügung gestellt werden müssen.
<ul>
<li><b>Grundsätzliches</b><ul>
<li><a name="SONOSPLAYER_attribut_disable"><b><code>disable &lt;int&gt;</code></b>
</a><br /> One of (0,1). Deaktiviert die Event-Verarbeitung für diesen Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_generateSomethingChangedEvent"><b><code>generateSomethingChangedEvent &lt;int&gt;</code></b>
</a><br /> One of (0,1). 1 wenn ein 'SomethingChanged'-Event erzeugt werden soll. Dieses Event wird immer dann erzeugt, wenn sich irgendein Wert ändert. Dies ist nützlich, wenn man immer informiert werden möchte, egal, was sich geändert hat.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeEvent"><b><code>generateVolumeEvent &lt;int&gt;</code></b>
</a><br /> One of (0,1). Aktiviert die Generierung eines Events bei Lautstärkeänderungen, wenn minVolume oder maxVolume definiert sind.</li>
<li><a name="SONOSPLAYER_attribut_generateVolumeSlider"><b><code>generateVolumeSlider &lt;int&gt;</code></b>
</a><br /> One of (0,1). Aktiviert einen Slider für die Lautstärkekontrolle in der Detailansicht.</li>
<li><a name="SONOSPLAYER_attribut_getAlarms"><b><code>getAlarms &lt;int&gt;</code></b>
</a><br /> One of (0..1). Richtet eine Callback-Methode für Alarme ein. Damit wird auch die DailyIndexRefreshTime automatisch aktualisiert.</li>
<li><a name="SONOSPLAYER_attribut_volumeStep"><b><code>volumeStep &lt;int&gt;</code></b>
</a><br /> One of (0..100). Definiert die Schrittweite für die Aufrufe von <code>VolumeU</code> und <code>VolumeD</code>.</li>
</ul></li>
<li><b>Informationen generieren</b><ul>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize1"><b><code>generateInfoSummarize1 &lt;string&gt;</code></b>
</a><br /> Erzeugt das Reading 'InfoSummarize1' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize2"><b><code>generateInfoSummarize2 &lt;string&gt;</code></b>
</a><br /> Erzeugt das Reading 'InfoSummarize2' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize3"><b><code>generateInfoSummarize3 &lt;string&gt;</code></b>
</a><br /> Erzeugt das Reading 'InfoSummarize3' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_generateInfoSummarize4"><b><code>generateInfoSummarize4 &lt;string&gt;</code></b>
</a><br /> Erzeugt das Reading 'InfoSummarize4' mit dem angegebenen Format. Mehr Informationen dazu im Bereich Beispiele.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><b><code>stateVariable &lt;string&gt;</code></b>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,<br />Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,<br />nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,CrossfadeMode,Balance,<br />HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,I<br />nfoSummarize2,InfoSummarize3,InfoSummarize4). Gibt an, welche Variable in das Reading <code>state</code> kopiert werden soll.</li>
</ul></li>
<li><b>Steueroptionen</b><ul>
<li><a name="SONOSPLAYER_attribut_maxVolume"><b><code>maxVolume &lt;int&gt;</code></b>
</a><br /> One of (0..100). Definiert die maximale Lautstärke dieses Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_minVolume"><b><code>minVolume &lt;int&gt;</code></b>
</a><br /> One of (0..100). Definiert die minimale Lautstärke dieses Zoneplayer.</li>
<li><a name="SONOSPLAYER_attribut_maxVolumeHeadphone"><b><code>maxVolumeHeadphone &lt;int&gt;</code></b>
</a><br /> One of (0..100). Definiert die maximale Lautstärke dieses Zoneplayer im Kopfhörerbetrieb.</li>
<li><a name="SONOSPLAYER_attribut_minVolumeHeadphone"><b><code>minVolumeHeadphone &lt;int&gt;</code></b>
</a><br /> One of (0..100). Definiert die minimale Lautstärke dieses Zoneplayer im Kopfhörerbetrieb.</li>
<li><a name="SONOSPLAYER_attribut_buttonEvents"><b><code>buttonEvents &lt;Time:Pattern&gt;[ &lt;Time:Pattern&gt; ...]</code></b>
</a><br /> Definiert, dass bei einer bestimten Tastenfolge am Player ein Event erzeugt werden soll. Die Definition der Events erfolgt als Tupel: Der erste Teil vor dem Doppelpunkt ist die Zeit in Sekunden, die berücksichtigt werden soll, der zweite Teil hinter dem Doppelpunkt definiert die Abfolge der Buttons, die für dieses Event notwendig sind.<br />
Folgende Button-Kürzel sind zulässig: <ul><li><b>M</b>: Der Mute-Button</li><li><b>H</b>: Die Headphone-Buchse</li><li><b>U</b>: Up-Button (Lautstärke Hoch)</li><li><b>D</b>: Down-Button (Lautstärke Runter)</li></ul><br />
Das Event, das geworfen wird, heißt <code>ButtonEvent</code>, der Wert ist die definierte Tastenfolge<br />
Z.B.: <code>2:MM</code><br />
Hier wird definiert, dass ein Event erzeugt werden soll, wenn innerhalb von 2 Sekunden zweimal die Mute-Taste gedrückt wurde. Das damit erzeugte Event hat dann den Namen <code>ButtonEvent</code>, und den Wert <code>MM</code>.</li>
</ul></li>
</ul>
<a name="SONOSPLAYERexamples"></a>
<h4>Beispiele / Hinweise</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format von InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;|:summarizeElem:</code><br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ instead=":text:"][ ifempty=":text:"]/[ emptyVal=":text:"]&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|<br />Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|<br />nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|CrossfadeMode|Balance|<br />HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|<br />InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
<code>:text: := [Jeder beliebige Text ohne doppelte Anführungszeichen]</code><br /></li>
</ul>

=end html_DE
=cut