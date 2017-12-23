########################################################################################
#
# SONOSPLAYER.pm (c) by Reiner Leins, December 2017
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
use Encode;
use Scalar::Util qw(reftype looks_like_number);

# SmartMatch-Fehlermeldung unterdrücken...
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

require 'HttpUtils.pm';
require $attr{global}{modpath}.'/FHEM/00_SONOS.pm';

sub Log($$);
sub Log3($$$);
sub SONOSPLAYER_Log($$$);


########################################################
# Standards aus FHEM einbinden
########################################################
use vars qw{%modules %defs};


########################################################################################
# Variable Definitions
########################################################################################
my @possibleRoomIcons = qw(bathroom library office foyer dining tvroom hallway garage garden guestroom den bedroom kitchen portable media family pool masterbedroom playroom patio living);

my %gets = (
	'CurrentTrackPosition' => '',
	'Playlists' => '',
	'PlaylistsWithCovers' => '',
	'Favourites' => '',
	'FavouritesWithCovers' => '',
	'Radios' => '',
	'RadiosWithCovers' => '',
	'Queue' => '',
	'QueueWithCovers' => '',
	'Alarm' => 'ID',
	'EthernetPortStatus' => 'PortNum(0..3)',
	'SupportLinks' => '',
	'PossibleRoomIcons' => '',
	'SearchlistCategories' => ''
);

my %sets = (
	'Play' => '',
	'Pause' => '',
	'Stop' => '',
	'Next' => '',
	'Previous' => '',
	'LoadPlaylist' => 'playlistname [ClearPlaylist]',
	'StartPlaylist' => 'playlistname [ClearPlaylist]',
	'SavePlaylist' => 'playlistname',
	'DeletePlaylist' => 'playlistname',
	'DeleteFromQueue' => 'PerlNumberListOfIndizies',
	'CurrentPlaylist' => '',
	'EmptyPlaylist' => '',
	'LoadFavourite' => 'favouritename',
	'StartFavourite' => 'favouritename [NoStart]',
	'LoadRadio' => 'radioname',
	'StartRadio' => 'radioname',
	'PlayURI' => 'songURI [Volume]',
	'PlayURITemp' => 'songURI [Volume]',
	'LoadHandle' => 'Handle',
	'StartHandle' => 'Handle',
	'AddURIToQueue' => 'songURI',
	'Speak' => 'volume(0..100) language text',
	'OutputFixed' => 'state',
	'Mute' => 'state',
	'Shuffle' => 'state',
	'Repeat' => 'state',
	'RepeatOne' => 'state',
	'CrossfadeMode' => 'state',
	'LEDState' => 'state',
	'MuteT' => '',
	'ShuffleT' => '',
	'RepeatT' => '',
	'RepeatOneT' => '',
	'VolumeD' => '',
	'VolumeU' => '',
	'Volume' => 'volumelevel(0..100) [RampType]',
	'VolumeSave' => 'volumelevel(0..100)',
	'VolumeRestore' => '',
	'Balance' => 'balancevalue(-100..100)',
	'Loudness' => 'state',
	'Bass' => 'basslevel(0..100)',
	'Treble' => 'treblelevel(0..100)',	
	'CurrentTrackPosition' => 'timeposition',
	'Track' => 'tracknumber|Random',
	'currentTrack' => 'tracknumber',
	'Alarm' => 'create|update|delete ID,ID|All [valueHash]',
	'SnoozeAlarm' => 'timestring|seconds',
	'DailyIndexRefreshTime' => 'timestring',
	'SleepTimer' => 'timestring|seconds',
	'AddMember' => 'member_devicename[,member_devicename]',
	'RemoveMember' => 'member_devicename',
	'MakeStandaloneGroup' => '',
	'GroupVolume' => 'volumelevel(0..100)',
	'GroupVolumeD' => '',
	'GroupVolumeU' => '',
	'SnapshotGroupVolume' => '',
	'GroupMute' => 'state',
	'CreateStereoPair' => 'RightPlayerDevice',
	'SeparateStereoPair' => '',
	'Reboot' => '',
	'Wifi' => 'state',
	'Name' => 'roomName',
	'RoomIcon' => 'iconName('.join(',', @possibleRoomIcons).')',
	# 'JumpToChapter' => 'groupname chaptername', 
	'LoadSearchlist' => 'category categoryElem [titleFilter/albumFilter/artistFilter] [maxElems]',
	'StartSearchlist' => 'category categoryElem [titleFilter/albumFilter/artistFilter] [maxElems]',
	'ResetAttributesToDefault' => 'deleteOtherAttributes',
	'ExportSonosBibliothek' => 'filename',
	'TruePlay' => 'state',
	'SurroundEnable' => 'state',
	'SurroundLevel' => 'surroundlevel(-15..15)', #-15..15
	'SubEnable' => 'state',
	'SubGain' => 'gainlevel(-15..15)', #-15..15
	'SubPolarity' => 'polarity(0..2)', #0..2
	'AudioDelay' => 'delaylevel(0..5)', #0..5
	'AudioDelayLeftRear' => 'delaylevel(0{>3m},1{>0.6m&<3m},2{<0.6m})', #0..2
	'AudioDelayRightRear' => 'delaylevel(0{>3m},1{>0.6m&<3m},2{<0.6m})', #0..2
	'NightMode' => 'state',
	'DialogLevel' => 'state',
	'ButtonLockState' => 'state'
);

########################################################################################
#
#  SONOSPLAYER_Initialize
#
#  Parameter hash = hash of device addressed
#
########################################################################################
sub SONOSPLAYER_Initialize ($) {
	my ($hash) = @_;
	
	$hash->{DefFn} = "SONOSPLAYER_Define";
	$hash->{UndefFn} = "SONOSPLAYER_Undef";
	$hash->{DeleteFn} = "SONOSPLAYER_Delete";
	$hash->{GetFn} = "SONOSPLAYER_Get";
	$hash->{SetFn} = "SONOSPLAYER_Set";
	$hash->{StateFn} = "SONOSPLAYER_State";
	$hash->{AttrFn}  = 'SONOSPLAYER_Attribute';
	$hash->{NotifyFn} = 'SONOSPLAYER_Notify';
	
	$hash->{FW_detailFn} = 'SONOSPLAYER_Detail';
	$hash->{FW_deviceOverview} = 1;
	#$hash->{FW_addDetailToSummary} = 1;
	
	$hash->{AttrList} = "disable:1,0 generateVolumeSlider:1,0 generateVolumeEvent:1,0 generateSomethingChangedEvent:1,0 generateInfoSummarize1 generateInfoSummarize2 generateInfoSummarize3 generateInfoSummarize4 stateVariable:TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,TrackProvider,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackProvider,nextTrackURI,nextAlbumArtURI,nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,OutputFixed,Shuffle,Repeat,CrossfadeMode,Balance,HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,InfoSummarize2,InfoSummarize3,InfoSummarize4 model minVolume maxVolume minVolumeHeadphone maxVolumeHeadphone VolumeStep getAlarms:1,0 buttonEvents getTitleInfoFromMaster:1,0 stopSleeptimerInAction:1,0 saveSleeptimerInAction:1,0 simulateCurrentTrackPosition:0,1,2,3,4,5,6,7,8,9,10,15,20,25,30,45,60 simulateCurrentTrackPositionPercentFormat suppressControlButtons:1,0 ".$readingFnAttributes;
	
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
	
	# Check if we just want a modify...
	if ($hash->{NAME}) {
		SONOS_Log undef, 1, 'Modify SonosPlayer-Device: '.$hash->{NAME};
		
		# Alle Timer entfernen...
		RemoveInternalTimer($hash);
	}
	  
	# define <name> SONOSPLAYER <udn>
	# e.g.: define Sonos_Wohnzimmer SONOSPLAYER RINCON_000EFEFEFEF401400
	my @a = split("[ \t]+", $def);
	 
	my ($name, $udn);
	
	# default
	$name = $a[0];
	$udn = $a[2];
	
	# check syntax
	return "SONOSPLAYER: Wrong syntax, must be define <name> SONOSPLAYER <udn>" if(int(@a) < 3);
	
	$hash->{NOTIFYDEV} = $name;
	$hash->{helper}->{simulateCurrentTrackPosition} = 0;
	
	readingsSingleUpdate($hash, "state", 'init', 1);
	readingsSingleUpdate($hash, "presence", 'disappeared', 0); # Grund-Initialisierung, falls der Player sich nicht zurückmelden sollte...
	
	# RoomDarstellung für alle Player festlegen
	$modules{$hash->{TYPE}}->{FW_addDetailToSummary} = (AttrVal(SONOS_getSonosPlayerByName()->{NAME}, 'deviceRoomView', 'Both') =~ m/(Both)/i);
	
	$hash->{UDN} = $udn;
	readingsSingleUpdate($hash, "state", 'initialized', 1);
	
	return undef; 
}

########################################################################################
#
# SONOSPLAYER_Detail - Returns the Detailview
#
########################################################################################
sub SONOSPLAYER_Detail($$$;$) {
	my ($FW_wname, $d, $room, $withRC) = @_;
	$withRC = 1 if (!defined($withRC));
	
	my $hash = $defs{$d};
	
	return '' if (!ReadingsVal($d, 'IsMaster', 0) || (ReadingsVal($d, 'playerType', '') eq 'ZB100'));
	
	# Open incl. Inform-Div
	my $html .= '<html><div informid="'.$d.'-display_covertitle">';
	
	# Cover-/TitleView
	$html .= '<div style="border: 1px solid gray; border-radius: 10px; padding: 5px;">';
	$html .= SONOS_getCoverTitleRG($d);
	$html .= '</div>';
	
	# Close Inform-Div
	$html .= '</div>';
	
	# Control-Buttons
	if (!AttrVal($d, 'suppressControlButtons', 0) && ($withRC)) {
		$html.= '<div class="rc_body" style="border: 1px solid gray; border-radius: 10px; padding: 5px;">';
		$html .= '<table style="text-align: center;"><tr>';
		$html .= '<td><a onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' Previous\')">'.FW_makeImage('rc_PREVIOUS.svg', 'Previous', 'rc-button').'</a></td> 
			<td><a style="padding-left: 10px;" onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' Play\')">'.FW_makeImage('rc_PLAY.svg', 'Play', 'rc-button').'</a></td> 
			<td><a onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' Pause\')">'.FW_makeImage('rc_PAUSE.svg', 'Pause', 'rc-button').'</a></td> 
			<td><a style="padding-left: 10px;" onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' Next\')">'.FW_makeImage('rc_NEXT.svg', 'Next', 'rc-button').'</a></td> 
			<td><a style="padding-left: 20px;" onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' VolumeD\')">'.FW_makeImage('rc_VOLDOWN.svg', 'VolDown', 'rc-button').'</a></td>
			<td><a onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' MuteT\')">'.FW_makeImage('rc_MUTE.svg', 'Mute', 'rc-button').'</a></td>
			<td><a onclick="FW_cmd(\'?XHR=1&amp;cmd.dummy=set '.$d.' VolumeU\')">'.FW_makeImage('rc_VOLUP.svg', 'VolUp', 'rc-button').'</a></td>';
		$html .= '</tr></table>';
		$html .= '</div>';
	}
	
	# Close
	$html .= '</html>';
	
	return $html;
}

########################################################################################
#
#  SONOSPLAYER_Attribute - Implements AttrFn function 
#
########################################################################################
sub SONOSPLAYER_Attribute($$$@) {
	my ($mode, $devName, $attrName, $attrValue) = @_;
	
	if ($mode eq 'set') {
		if ($attrName =~ m/^(min|max)Volume(|Headphone)$/) {
			my $hash = SONOS_getSonosPlayerByName($devName);
			
			SONOS_DoWork($hash->{UDN}, 'setMinMaxVolumes', $attrName, $attrValue);
		} elsif ($attrName =~ m/^(getTitleInfoFromMaster|stopSleeptimerInAction|saveSleeptimerInAction)$/) {
			my $hash = SONOS_getSonosPlayerByName($devName);
			
			SONOS_DoWork($hash->{UDN}, 'setAttribute', $attrName, $attrValue);
		}
	} elsif ($mode eq 'del') {
		if ($attrName =~ m/^minVolume(|Headphone)$/) {
			my $hash = SONOS_getSonosPlayerByName($devName);
			
			SONOS_DoWork($hash->{UDN}, 'setMinMaxVolumes', $attrName, 0);
		} elsif ($attrName =~ m/^maxVolume(|Headphone)$/) {
			my $hash = SONOS_getSonosPlayerByName($devName);
			
			SONOS_DoWork($hash->{UDN}, 'setMinMaxVolumes', $attrName, 100);
		} elsif ($attrName =~ m/^(getTitleInfoFromMaster|stopSleeptimerInAction|saveSleeptimerInAction)$/) {
			my $hash = SONOS_getSonosPlayerByName($devName);
			
			SONOS_DoWork($hash->{UDN}, 'deleteAttribute', $attrName);
		}
	}
}

#######################################################################################
#
#  SONOSPLAYER_State - StateFn, used for deleting unused or initialized Readings...
#
########################################################################################
sub SONOSPLAYER_State($$$$) {
	my ($hash, $time, $name, $value) = @_; 
	
	# Die folgenden Readings müssen immer neu initialisiert verwendet werden, und dürfen nicht aus dem Statefile verwendet werden
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
sub SONOSPLAYER_Notify($$) {
	my ($hash, $notifyhash) = @_;
	
	my $events = deviceEvents($notifyhash, 1);
	return if(!$events);
	
	my $triggerCoverTitle = 0;
	
	foreach my $event (@{$events}) {
		next if(!defined($event));
		
		# Wenn ein CoverTitle-Trigger gesendet werden muss...
		if ($event =~ m/^(currentAlbumArtURL|currentTrackProviderIconRoundURL|currentTrackDuration|currentTrack|numberOfTracks|currentTitle|currentArtist|currentAlbum|nextAlbumArtURL|nextTrackProviderIconRoundURL|nextTitle|nextArtist|nextAlbum|currentSender|currentSenderInfo|currentSenderCurrent|transportState):/is) {
			SONOSPLAYER_Log $hash->{NAME}, 5, 'Notify-CoverTitle: '.$event;
			$triggerCoverTitle = 1;
		}
		
		# Wenn die Positionssimulation betroffen ist...
		if ($event =~ m/transportState: (.+)/i) {
			SONOSPLAYER_Log $hash->{NAME}, 5, 'Notify-TransportState: '.$event;
			if ($1 eq 'PLAYING') {
				$hash->{helper}->{simulateCurrentTrackPosition} = AttrVal($hash->{NAME}, 'simulateCurrentTrackPosition', 0);
				
				# Wiederholungskette für die Aktualisierung sofort anstarten...
				InternalTimer(gettimeofday(), 'SONOSPLAYER_SimulateCurrentTrackPosition', $hash, 0);
			} else {
				$hash->{helper}->{simulateCurrentTrackPosition} = 0;
				
				# Einmal noch etwas später aktualisieren...
				InternalTimer(gettimeofday() + 1, 'SONOSPLAYER_SimulateCurrentTrackPosition', $hash, 0);
			}
		}
	}
	
	if ($triggerCoverTitle) {
		InternalTimer(gettimeofday(), 'SONOSPLAYER_TriggerCoverTitleLater', $notifyhash, 0);
	}
	
	return undef;
}

########################################################################################
#
# SONOSPLAYER_TriggerCoverTitleLater - Refreshs the CoverTitle-Element later via DoTrigger
# 
########################################################################################
sub SONOSPLAYER_TriggerCoverTitleLater($) {
	my ($hash) = @_;
	
	my $html = SONOSPLAYER_Detail('', $hash->{NAME}, '', 0);
	DoTrigger($hash->{NAME}, 'display_covertitle: '.$html, 1);
	
	return undef;
}

########################################################################################
#
#  SONOSPLAYER_SimulateCurrentTrackPosition - Implements the Simulation for the currentTrackPosition
#
########################################################################################
sub SONOSPLAYER_SimulateCurrentTrackPosition() {
	my ($hash) = @_;
	
	return undef if (AttrVal($hash->{NAME}, 'disable', 0));
	
	SONOS_readingsBeginUpdate($hash);
	
	my $trackDurationSec = SONOS_GetTimeSeconds(ReadingsVal($hash->{NAME}, 'currentTrackDuration', 0));
	
	my $trackPositionSec = 0;
	if (ReadingsVal($hash->{NAME}, 'transportState', 'STOPPED') eq 'PLAYING') {
		$trackPositionSec = time - SONOS_GetTimeFromString(ReadingsTimestamp($hash->{NAME}, 'currentTrackPositionSec', 0)) + ReadingsVal($hash->{NAME}, 'currentTrackPositionSec', 0);
	} else {
		$trackPositionSec = ReadingsVal($hash->{NAME}, 'currentTrackPositionSec', 0);
	}
	readingsBulkUpdate($hash, 'currentTrackPositionSimulated', SONOS_ConvertSecondsToTime($trackPositionSec));
	readingsBulkUpdate($hash, 'currentTrackPositionSimulatedSec', $trackPositionSec);
	
	if ($trackDurationSec) {
		readingsBulkUpdateIfChanged($hash, 'currentTrackPositionSimulatedPercent', sprintf(AttrVal($hash->{NAME}, 'simulateCurrentTrackPositionPercentFormat', '%.1f'), 100 * $trackPositionSec / $trackDurationSec));
	} else {
		readingsBulkUpdateIfChanged($hash, 'currentTrackPositionSimulatedPercent', sprintf(AttrVal($hash->{NAME}, 'simulateCurrentTrackPositionPercentFormat', '%.1f'), 0.0));
	}
	
	SONOS_readingsEndUpdate($hash, 1);
	
	if ($hash->{helper}->{simulateCurrentTrackPosition}) {
		InternalTimer(gettimeofday() + $hash->{helper}->{simulateCurrentTrackPosition}, 'SONOSPLAYER_SimulateCurrentTrackPosition', $hash, 0);
	}
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
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$gets{$reading} if (SONOSPLAYER_CountRequiredParameters($gets{$reading}) > scalar(@a) - 2);
	
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
	} elsif (lc($reading) eq 'queue') {
		SONOS_DoWork($udn, 'getQueue');
	} elsif (lc($reading) eq 'queuewithcovers') {
		SONOS_DoWork($udn, 'getQueueWithCovers');
	} elsif (lc($reading) eq 'searchlistcategories') {
		SONOS_DoWork($udn, 'getSearchlistCategories');
	} elsif (lc($reading) eq 'ethernetportstatus') {
		my $portNum = $a[2];
		
		SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'Portstatus properly returned', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/status\/enetports/;
		
		my $statusPage = GetFileFromURL($url);
		return (($1 == 0) ? 'Inactive' : 'Active') if ($statusPage =~ m/<Port port='$portNum'><Link>(\d+)<\/Link><Speed>.*?<\/Speed><\/Port>/i);
		return 'Inactive';
	} elsif (lc($reading) eq 'supportlinks') {
		my $playerurl = ReadingsVal($name, 'location', '');
		$playerurl =~ s/(^http:\/\/.*?)\/.*/$1/;
		
		return '<a href="'.$playerurl.'/support/review" target="_blank">Support Review</a><br /><a href="'.$playerurl.'/status" target="_blank">Status</a>';
	} elsif (lc($reading) eq 'alarm') {
		my $id = $a[2];
		
		SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'Alarm-Hash properly returned', 1);
		
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
				$key = $key.':slider,-15,1,15' if ($key eq 'SubGain');
				$key = $key.':slider,-15,1,15' if ($key eq 'SurroundLevel');
				$key = $key.':slider,1,1,'.ReadingsVal($hash->{NAME}, 'numberOfTracks', 0) if (($key eq 'currentTrack') || ($key eq 'track'));
			}
			
			$key = $key.':0,1,2' if ($key eq 'SubPolarity');
			$key = $key.':0,1,2,3,4,5' if ($key eq 'AudioDelay');
			$key = $key.':0,1,2' if ($key eq 'AudioDelayLeftRear');
			$key = $key.':0,1,2' if ($key eq 'AudioDelayRightRear');
			
			# On/Off einsetzen; Da das jeweilige Reading dazu 0,1 enthalten wird, auch mit 0,1 arbeiten, damit die Vorauswahl passt
			$key = $key.':0,1' if ((lc($key) eq 'crossfademode') 
								|| (lc($key) eq 'groupmute') 
								|| (lc($key) eq 'ledstate') 
								|| (lc($key) eq 'loudness') 
								|| (lc($key) eq 'mute') 
								|| (lc($key) eq 'trueplay') 
								|| (lc($key) eq 'dialoglevel') 
								|| (lc($key) eq 'buttonlockstate') 
								|| (lc($key) eq 'nightmode') 
								|| (lc($key) eq 'subenable') 
								|| (lc($key) eq 'surroundenable') 
								|| (lc($key) eq 'outputfixed')  
								|| (lc($key) eq 'resetattributestodefault')  
								|| (lc($key) eq 'repeat') 
								|| (lc($key) eq 'repeatone') 
								|| (lc($key) eq 'shuffle'));
			
			# Iconauswahl einsetzen
			$key = $key.':'.join(',', @possibleRoomIcons) if (lc($key) eq 'roomicon');
			
			# Playerauswahl einsetzen
			eval {
				my @playerNames = @{eval(ReadingsVal($hash->{NAME}, 'AvailablePlayer', '[]'))};
				$key = $key.':'.join(',', sort(@playerNames)) if ((lc($key) eq 'addmember') || (lc($key) eq 'createstereopair'));
			};
			
			eval {
				my @playerNames = @{eval(ReadingsVal($hash->{NAME}, 'SlavePlayerNotBonded', '[]'))};
				$key = $key.':'.join(',', sort(@playerNames)) if (lc($key) eq 'removemember');
			};
			
			# Wifi-Auswahl setzen
			$key = $key.':off,on,persist-off' if (lc($key) eq 'wifi');
			
			$setcopy{$key} = $sets{$oldkey};
		}
		
		my $sonosDev = SONOS_getSonosPlayerByName();
		$sets{Speak1} = 'volume(0..100) language text' if (AttrVal($sonosDev->{NAME}, 'Speak1', '') ne '');
		$sets{Speak2} = 'volume(0..100) language text' if (AttrVal($sonosDev->{NAME}, 'Speak2', '') ne '');
		$sets{Speak3} = 'volume(0..100) language text' if (AttrVal($sonosDev->{NAME}, 'Speak3', '') ne '');
		$sets{Speak4} = 'volume(0..100) language text' if (AttrVal($sonosDev->{NAME}, 'Speak4', '') ne '');
		
		# for the ?-selector: which values are possible
		if($a[1] eq '?') {
			my @newSets = ();
			for my $elem (sort keys %setcopy) {
				push @newSets, $elem.(($setcopy{$elem} eq '') ? ':noArg' : '');
			}
			return "Unknown argument, choose one of ".join(" ", @newSets);
		}
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
	return "SONOSPLAYER: $a[1] needs parameter(s): ".$sets{$a[1]} if (SONOSPLAYER_CountRequiredParameters($sets{$a[1]}) > scalar(@a) - 2);
	     
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
			SONOS_DoWork($udn, 'setRelativeGroupVolume',  $value);
		} else {
			SONOS_DoWork($udn, 'setGroupVolume', $value, $value2);
		}
	} elsif (lc($key) eq 'groupvolumed') {
		SONOS_DoWork($udn, 'setRelativeGroupVolume', -AttrVal($hash->{NAME}, 'VolumeStep', 7));
	} elsif (lc($key) eq 'groupvolumeu') {
		SONOS_DoWork($udn, 'setRelativeGroupVolume', AttrVal($hash->{NAME}, 'VolumeStep', 7));
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
	} elsif (lc($key) eq 'surroundenable') {
		SONOS_DoWork($udn, 'setEQ', 'SurroundEnable', SONOS_ConvertWordToNum($value));
	} elsif (lc($key) eq 'surroundlevel') {
		SONOS_DoWork($udn, 'setEQ', 'SurroundLevel', $value);
	} elsif (lc($key) eq 'trueplay') {	
		SONOS_DoWork($udn, 'setTruePlay', SONOS_ConvertWordToNum($value));
	} elsif (lc($key) eq 'subenable') {
		SONOS_DoWork($udn, 'setEQ', 'SubEnable', SONOS_ConvertWordToNum($value));
	} elsif (lc($key) eq 'subgain') {
		SONOS_DoWork($udn, 'setEQ', 'SubGain', $value);
	} elsif (lc($key) eq 'subpolarity') {
		SONOS_DoWork($udn, 'setEQ', 'SubPolarity', $value);
	} elsif (lc($key) eq 'audiodelay') {
		SONOS_DoWork($udn, 'setEQ', 'AudioDelay', $value);
	} elsif (lc($key) eq 'audiodelayleftrear') {
		SONOS_DoWork($udn, 'setEQ', 'AudioDelayLeftRear', $value);
	} elsif (lc($key) eq 'audiodelayrightrear') {
		SONOS_DoWork($udn, 'setEQ', 'AudioDelayRightRear', $value);
	} elsif (lc($key) eq 'nightmode') {
		SONOS_DoWork($udn, 'setEQ', 'NightMode', SONOS_ConvertWordToNum($value));
	} elsif (lc($key) eq 'dialoglevel') {
		SONOS_DoWork($udn, 'setEQ', 'DialogLevel', SONOS_ConvertWordToNum($value));
	} elsif (lc($key) eq 'groupmute') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		SONOS_DoWork($udn, 'setGroupMute', $value);
	} elsif (lc($key) eq 'outputfixed') {
		SONOS_DoWork($udn, 'setOutputFixed', $value);
	} elsif (lc($key) eq 'buttonlockstate') {
		SONOS_DoWork($udn, 'setButtonLockState', $value);
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
	} elsif (lc($key) eq 'repeatone') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setRepeatOne', $value);
	} elsif (lc($key) eq 'repeatonet') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'setRepeatOne', '~~');
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
	} elsif ((lc($key) eq 'track') || (lc($key) eq 'currenttrack')) {
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
	} elsif (lc($key) eq 'loadfavourite') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'startFavourite', $value, 'NoStart');
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
		} elsif (defined($defs{$value})) {
			my $dHash = SONOS_getSonosPlayerByName($value);
			SONOSPLAYER_Log undef, 3, 'Device: '.$dHash->{NAME}.' ~ '.$dHash->{UDN};
			if (defined($dHash)) {
				SONOS_DoWork($udn, 'loadPlaylist', ':device:'.$dHash->{UDN}, $value2);
			}
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
	} elsif (lc($key) eq 'deleteplaylist') {
		SONOS_DoWork($udn, 'deletePlaylist', $value);
	} elsif (lc($key) eq 'deletefromqueue') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		$value =~ s/ //g;
		
		SONOS_DoWork($udn, 'deleteFromQueue', uri_escape($value));
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
	} elsif (lc($key) eq 'exportsonosbibliothek') {
		SONOS_DoWork($udn, 'exportSonosBibliothek', $value);
	} elsif (lc($key) eq 'playuri') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		# Prüfen, ob ein Sonosplayer-Device angegeben wurde, dann diesen AV Eingang als Quelle wählen
		if (defined($defs{$value})) {
			my $dHash = SONOS_getSonosPlayerByName($value);
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
	} elsif ($key =~ m/(start|load)handle/i) {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		# Hier die komplette restliche Zeile in den Text-Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 2; $i < @a; $i++) {
			$text .= ' ' if ($i > 2);
			$text .= $a[$i];
		}
		
		SONOS_DoWork($udn, 'startHandle', $text, (lc($key) eq 'loadhandle'));
	} elsif (lc($key) eq 'adduritoqueue') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
	
		SONOS_DoWork($udn, 'addURIToQueue', $value);
	} elsif ((lc($key) eq 'speak') || ($key =~ m/speak\d+/i)) {
		my $sonosName = SONOS_getSonosPlayerByName()->{NAME};
		if ((AttrVal($sonosName, 'targetSpeakDir', '') eq '') || (AttrVal($sonosName, 'targetSpeakURL', '') eq '')) {
			return $key.' not possible. Please define valid "targetSpeakDir"- and "targetSpeakURL"-Attribute for Device "'.$sonosName.'" first.';
		} else {
			$key = 'speak0' if (lc($key) eq 'speak');
			
			$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
			$udn = $hash->{UDN};
			
			# Hier die komplette restliche Zeile in den Text-Parameter packen, da damit auch Leerzeichen möglich sind
			my $text = '';
			for(my $i = 4; $i < @a; $i++) {
				$text .= ' ' if ($i > 4);
				$text .= $a[$i];
			}
			$text = decode('utf8', $text);
		
			SONOS_DoWork($udn, lc($key), $value, $value2, $text);
		}
	} elsif (lc($key) eq 'alarm') {
		# Hier die komplette restliche Zeile in den zweiten Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 4; $i < @a; $i++) {
			$text .= ' ' if ($i > 4);
			$text .= $a[$i];
		}
		$text = decode('utf8', SONOS_Trim($text));
		
		# Optionalen Parameter für die Hashwerte ermöglichen
		if ($text eq '') {
			$text = '{}';
		}
		
		# Neue Befehle auf die Standardvorgehensweise übersetzen
		my %alarmHash = %{eval($text)};
		if (lc($value) eq 'enable') {
			$value = 'Update';
			$alarmHash{Enabled} = 1;
		} elsif (lc($value) eq 'disable') {
			$value = 'Update';
			$alarmHash{Enabled} = 0;
		}
		$text = SONOS_Dumper(\%alarmHash);
		
		SONOS_DoWork($udn, 'setAlarm', $value, $value2, $text);
	} elsif (lc($key) eq 'snoozealarm') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		$value = SONOS_ConvertSecondsToTime($value) if (looks_like_number($value));
		
		SONOS_DoWork($udn, 'setSnoozeAlarm', $value);
	} elsif (lc($key) eq 'dailyindexrefreshtime') {
		SONOS_DoWork($udn, 'setDailyIndexRefreshTime', $value);
	} elsif (lc($key) eq 'sleeptimer') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		$value = SONOS_ConvertSecondsToTime($value) if (looks_like_number($value));
		
		SONOS_DoWork($udn, 'setSleepTimer', $value);
	} elsif (lc($key) eq 'addmember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getSonosPlayerByName($value);
		if ($cHash) {
			SONOS_DoWork($udn, 'addMember', $cHash->{UDN});
		} else {
			my @sonosDevs = ();
			foreach my $dev (SONOS_getAllSonosplayerDevices()) {
				push(@sonosDevs, $dev->{NAME}) if ($dev->{NAME} ne $hash->{NAME});
			}
			SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'AddMember: Wrong Sonos-Devicename "'.$value.'". Use one of "'.join('", "', @sonosDevs).'"', 1);
			
			return undef;
		}
	} elsif (lc($key) eq 'removemember') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		my $cHash = SONOS_getSonosPlayerByName($value);
		if ($cHash) {
			SONOS_DoWork($udn, 'removeMember', $cHash->{UDN});
		} else {
			my @sonosDevs = ();
			foreach my $dev (SONOS_getAllSonosplayerDevices()) {
				push(@sonosDevs, $dev->{NAME}) if ($dev->{NAME} ne $hash->{NAME});
			}
			SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'RemoveMember: Wrong Sonos-Devicename "'.$value.'". Use one of "'.join('", "', @sonosDevs).'"', 1);
			
			return undef;
		}
	} elsif (lc($key) eq 'makestandalonegroup') {
		SONOS_DoWork($udn, 'makeStandaloneGroup');
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
		SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'Reboot properly initiated', 1);
	
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/reboot/;
		
		GetFileFromURL($url);
	} elsif (lc($key) eq 'wifi') {
		$value = lc($value);
		if ($value ne 'on' && $value ne 'off' && $value ne 'persist-off') {
			SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'Wrong parameter "'.$value.'". Use one of "off", "persist-off" or "on".', 1);
			
			return undef;
		}
		
		SONOS_readingsSingleUpdate($hash, 'LastActionResult', 'WiFi properly set to '.$value, 1);
		
		my $url = ReadingsVal($name, 'location', '');
		$url =~ s/(^http:\/\/.*?)\/.*/$1\/wifictrl?wifi=$value/;
		
		GetFileFromURL($url);
	} elsif (lc($key) eq 'name') {
		$hash = SONOSPLAYER_GetRealTargetPlayerHash($hash);
		$udn = $hash->{UDN};
		
		# Hier die komplette restliche Zeile in den Parameter packen, da damit auch Leerzeichen möglich sind
		my $text = '';
		for(my $i = 2; $i < @a; $i++) {
			$text .= ' ' if ($i > 2);
			$text .= $a[$i];
		}
		$text = decode('utf8', $text);
		
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
	} elsif (lc($key) eq 'JumpToChapter') {
		SONOS_DoWork($udn, 'JumpToChapter', $value, $value2);
	} elsif (lc($key) eq 'resetattributestodefault') {
		SONOS_DoWork($udn, 'setResetAttributesToDefault', SONOS_getSonosPlayerByName()->{NAME}, $hash->{NAME}, $value);
	} else {
		return 'Not implemented yet!';
	}
	
	return (undef, 1);
}

########################################################################################
#
#  SONOSPLAYER_CountRequiredParameters - Counta all required parameters in the given string
#
########################################################################################
sub SONOSPLAYER_CountRequiredParameters($) {
	my ($params) = @_;
	
	my $result = 0;
	for my $elem (split(' ', $params)) {
		$result++ if ($elem !~ m/\[.*\]/);
	}
	
	return $result;
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
	
	return SONOSPLAYER_GetRealTargetPlayerHash(SONOS_getSonosPlayerByName($name))->{NAME};
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
	
	my $hash = SONOS_getSonosPlayerByName($name);
	my $sonosHash = SONOS_getSonosPlayerByName();
	
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
	SONOSPLAYER_DeleteIfExists($hash->{NAME}.'RG_Queue');
	
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
=item summary    Module to work with Sonos-Zoneplayers
=item summary_DE Modul für die Steuerung von Sonos Zoneplayern
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
<b><code>Alarm (Create|Update|Delete|Enable|Disable) &lt;ID[,ID]|All&gt; &lt;Datahash&gt;</code></b></a>
<br />Can be used for working on alarms:<ul><li><b>Create:</b> Creates an alarm-entry with the given datahash.</li><li><b>Update:</b> Updates the alarm-entry with the given id(s) and datahash.</li><li><b>Delete:</b> Deletes the alarm-entry with the given id(s).</li><li><b>Enable:</b> Enables the alarm-entry with the given id(s).</li><li><b>Disable:</b> Disables the alarm-entry with the gven id(s).</li></ul>If the Word 'All' is given as ID, all alarms of this player are changed.<br /><b>The Datahash:</b><br />The Format is a perl-hash and is interpreted with the eval-function.<br />e.g.: { Repeat =&gt; 1 }<br /><br />The following entries are allowed/neccessary:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />e.g.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_AudioDelay">
<b><code>AudioDelay &lt;Level&gt;</code></b></a>
<br /> Sets the audiodelay of the player to the given value. The value can range from 0 to 5.</li>
<li><a name="SONOSPLAYER_setter_AudioDelayLeftRear">
<b><code>AudioDelayLeftRear &lt;Level&gt;</code></b></a>
<br /> Sets the audiodelayleftrear of the player to the given value. The value can range from 0 to 2. The values has the following meanings: 0: >3m, 1: >0.6m und <3m, 2: <0.6m</li>
<li><a name="SONOSPLAYER_setter_AudioDelayRightRear">
<b><code>AudioDelayRightRear &lt;Level&gt;</code></b></a>
<br /> Sets the audiodelayrightrear of the player to the given value. The value can range from 0 to 2. The values has the following meanings: 0: >3m, 1: >0.6m und <3m, 2: <0.6m</li>
<li><a name="SONOSPLAYER_setter_ButtonLockState">
<b><code>ButtonLockState &lt;int&gt;</code></b></a>
<br />One of (0, 1) Sets the current state of the ButtonLockState.</li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<b><code>DailyIndexRefreshTime &lt;Timestring&gt;</code></b></a>
<br />Sets the current DailyIndexRefreshTime for the whole bunch of Zoneplayers.</li>
<li><a name="SONOSPLAYER_setter_DialogLevel">
<b><code>DialogLevel &lt;State&gt;</code></b></a>
<br /> Sets the dialoglevel for playbar-systems.</li>
<li><a name="SONOSPLAYER_setter_ExportSonosBibliothek">
<b><code>ExportSonosBibliothek &lt;filename&gt;</code></b></a>
<br />Exports a file with a textual representation of a structure- and titlehash of the complete Sonos-Bibliothek. Warning: Will use a large amount of CPU-Time and RAM!</li>
<li><a name="SONOSPLAYER_setter_Name">
<b><code>Name &lt;Zonename&gt;</code></b></a>
<br />Sets the Name for this Zone</li>
<li><a name="SONOSPLAYER_setter_NightMode">
<b><code>NightMode &lt;State&gt;</code></b></a>
<br /> Sets the nightmode for playbar-systems.</li>
<li><a name="SONOSPLAYER_setter_OutputFixed">
<b><code>OutputFixed &lt;State&gt;</code></b></a>
<br /> Sets the outputfixed-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<b><code>Reboot</code></b></a>
<br />Initiates a reboot on the Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_ResetAttributesToDefault">
<b><code>ResetAttributesToDefault &lt;DeleteAllOtherAttributes&gt;</code></b></a>
<br />Sets the attributes to the inital state. If the parameter "DeleteAllOtherAttributes" is set to "1" or "on", all attributes will be deleted before the defaults will be newly retrieved from the player and set.</li>
<li><a name="SONOSPLAYER_setter_RoomIcon">
<b><code>RoomIcon &lt;Iconname&gt;</code></b></a>
<br />Sets the Icon for this Zone</li>
<li><a name="SONOSPLAYER_setter_SnoozeAlarm">
<b><code>SnoozeAlarm &lt;Timestring|Seconds&gt;</code></b></a>
<br />Snoozes a currently playing alarm for the given time</li>
<li><a name="SONOSPLAYER_setter_SubEnable">
<b><code>SubEnable &lt;State&gt;</code></b></a>
<br /> Sets the substate for sub-systems.</li>
<li><a name="SONOSPLAYER_setter_SubGain">
<b><code>SubGain &lt;Level&gt;</code></b></a>
<br /> Sets the sub-gain for sub-systems. The value can range from -15 to 15.</li>
<li><a name="SONOSPLAYER_setter_SubPolarity">
<b><code>SubPolarity &lt;Level&gt;</code></b></a>
<br /> Sets the sub-polarity for sub-systems. The value can range from 0 to 2.</li>
<li><a name="SONOSPLAYER_setter_SurroundEnable">
<b><code>SurroundEnable &lt;State&gt;</code></b></a>
<br /> Sets the surround-state for surround-systems (like playbars).</li>
<li><a name="SONOSPLAYER_setter_SurroundLevel">
<b><code>SurroundLevel &lt;Level&gt;</code></b></a>
<br /> Sets the surround-level for surround-systems (like playbars). The value can range from -15 to 15.</li>
<li><a name="SONOSPLAYER_setter_TruePlay">
<b><code>TruePlay &lt;State&gt;</code></b></a>
<br />Sets the TruePlay-State of the given player.</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<b><code>Wifi &lt;State&gt;</code></b></a>
<br />Sets the WiFi-State of the given Player. Can be 'off', 'persist-off' or 'on'.</li>
</ul></li>
<li><b>Playing Control-Commands</b><ul>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<b><code>CurrentTrackPosition &lt;TimePosition&gt;</code></b></a>
<br /> Sets the current timeposition inside the title to the given timevalue (e.g. 0:01:15) or seconds (e.g. 81). You can make relative jumps like '+0:00:10' or just '+10'. Additionally you can make a call with a percentage value like '+10%'. This relative value can be negative.</li>
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
<li><a name="SONOSPLAYER_setter_RepeatOne">
<b><code>RepeatOne &lt;State&gt;</code></b></a>
<br /> Sets the repeatOne-state. Retrieves the new state as the result.</li>
<li><a name="SONOSPLAYER_setter_RepeatOneT">
<b><code>RepeatOneT</code></b></a>
<br /> Toggles the repeatOne-state. Retrieves the new state as the result.</li>
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
<b><code>SleepTimer &lt;Timestring|Seconds&gt;</code></b></a>
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
<li><a name="SONOSPLAYER_setter_DeleteFromQueue">
<b><code>DeleteFromQueue <index_of_elems></code></b></a>
<br /> Deletes the elements from the current queue with the given indices. You can use the ususal perl-array-formats like "1..12,17,20..22". The indices reference to the position in the current view of the list (this usually differs between the normal playmode and the shuffleplaymode).</li>
<li><a name="SONOSPLAYER_setter_DeletePlaylist">
<b><code>DeletePlaylist</code></b></a>
<br /> Deletes the Sonos-Playlist with the given name. According to the possibilities of the playlistname have a close look at LoadPlaylist.</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<b><code>EmptyPlaylist</code></b></a>
<br /> Clears the current queue</li>
<li><a name="SONOSPLAYER_setter_LoadFavourite">
<b><code>LoadFavourite &lt;Favouritename&gt;</code></b></a>
<br /> Loads the named sonos-favorite. The parameter should be URL-encoded for proper naming of lists with special characters.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/meine.hits/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<b><code>LoadPlaylist &lt;Playlistname|Fhem-Devicename&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Loads the named playlist to the current playing queue. The parameter should be URL-encoded for proper naming of lists with special characters. The Playlistnamen can be an Fhem-Devicename, then the current playlist of this referenced player will be copied. The Playlistname can also be a filename and then must be startet with 'file:' (e.g. 'file:c:/Test.m3u')<br />If EmptyQueueBeforeImport is given and set to 1, the queue will be emptied before the import process. If not given, the parameter will be interpreted as 1.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/hits.2014/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<b><code>LoadRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Loads the named radiostation (favorite). The current queue will not be touched but deactivated. The parameter should be URL-encoded for proper naming of lists with special characters.<br />Additionally it's possible to use a regular expression as the name. The first hit will be used. The format is e.g. <code>/radio/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadSearchlist">
<b><code>LoadSearchlist &lt;Categoryname&gt; &lt;CategoryElement&gt; [[TitlefilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [[*]maxElem[+|-]]]</code></b></a>
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
<li><a name="SONOSPLAYER_setter_GroupVolumeD">
<b><code>GroupVolumeD</code></b></a>
<br /> Turns the group volume by volumeStep-ticks down.</li>
<li><a name="SONOSPLAYER_setter_GroupVolumeU">
<b><code>GroupVolumeU</code></b></a>
<br /> Turns the group volume by volumeStep-ticks up.</li>
<li><a name="SONOSPLAYER_setter_MakeStandaloneGroup">
<b><code>MakeStandaloneGroup</code></b></a>
<br />Makes this Player a standalone group.</li>
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
<li><a name="SONOSPLAYER_getter_SupportLinks">
<b><code>SupportLinks</code></b></a>
<br /> Shows a list with direct links to the player-support-sites.</li>
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
<li><a name="SONOSPLAYER_getter_Queue">
<b><code>Queue</code></b></a>
<br /> Retrieves a list with the names of all titles in the current queue. This getter retrieves the same list on all Zoneplayer. The format is a comma-separated list with quoted names of the titles. e.g. "1. Liste 1 [0:02:14]","2. Eintrag 2 [k.A.]","3. Test [0:14:00]"</li>
<li><a name="SONOSPLAYER_getter_QueueWithCovers">
<b><code>QueueWithCovers</code></b></a>
<br /> Retrieves a list with the stringrepresentation of a perl-hash which can easily be converted with "eval". It consists of the names and coverlinks of all of the titles in the current queue. e.g.: {'Q:0/22' => {'Cover' => 'urlzumcover', 'Title' => '1. Titel'}}.</li>
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
<li><a name="SONOSPLAYER_attribut_suppressControlButtons"><b><code>suppressControlButtons &lt;int&gt;</code></b>
</a><br /> One of (0,1). Enables the control-section shown under the Cover-/Titleview.</li>
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
<li><a name="SONOSPLAYER_attribut_getTitleInfoFromMaster"><b><code>getTitleInfoFromMaster &lt;int&gt;</code></b>
</a><br /> One of (0, 1). Gets the current Playing-Informations from the Masterplayer (if one is present).</li>
<li><a name="SONOSPLAYER_attribut_simulateCurrentTrackPosition"><b><code>simulateCurrentTrackPosition &lt;int&gt;</code></b>
</a><br /> One of (0,1,2,3,4,5,6,7,8,9,10,15,20,25,30,45,60). Starts an internal Timer which refreshs the current trackposition into the Readings <code>currentTrackPositionSimulated</code> and <code>currentTrackPositionSimulatedSec</code>. At the same time the Reading <code>currentTrackPositionSimulatedPercent</code> (between 0.0 and 100.0) will also be refreshed.</li>
<li><a name="SONOSPLAYER_attribut_simulateCurrentTrackPositionPercentFormat"><b><code>simulateCurrentTrackPositionPercentFormat &lt;Format&gt;</code></b>
</a><br /> Defines the format of the percentformat in the Reading <code>currentTrackPositionSimulatedPercent</code>.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><b><code>stateVariable &lt;string&gt;</code></b>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,<br />Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,<br />nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,RepeatOne,CrossfadeMode,Balance,<br />HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,<br />InfoSummarize2,InfoSummarize3,InfoSummarize4). Defines, which variable has to be copied to the content of the state-variable.</li>
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
<li><a name="SONOSPLAYER_attribut_saveSleeptimerInAction"><b><code>saveSleeptimerInAction &lt;int&gt;</code></b>
</a><br /> One of (0..1). If set, a possibly set Attribute "stopSleeptimerInAction" will be ignored.</li>
<li><a name="SONOSPLAYER_attribut_stopSleeptimerInAction"><b><code>stopSleeptimerInAction &lt;int&gt;</code></b>
</a><br /> One of (0..1). If set, a change of the current transportState to "PAUSED_PLAYBACK" or "STOPPED" will cause a stopping of an eventually running SleepTimer.</li>
</ul>
<a name="SONOSPLAYERexamples"></a>
<h4>Examples / Tips</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format of InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;|:summarizeElem:</code><br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ instead=":text:"][ ifempty=":text:"]/[ emptyVal=":text:"]&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|<br />Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|<br />nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|RepeatOne|CrossfadeMode|Balance|<br />HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|<br />InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
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
<b><code>Alarm (Create|Update|Delete|Enable|Disable) &lt;ID[,ID]|All&gt; &lt;Datahash&gt;</code></b></a>
<br />Diese Anweisung wird für die Bearbeitung der Alarme verwendet:<ul><li><b>Create:</b> Erzeugt einen neuen Alarm-Eintrag mit den übergebenen Hash-Daten.</li><li><b>Update:</b> Aktualisiert die Alarme mit den übergebenen IDs und den angegebenen Hash-Daten.</li><li><b>Delete:</b> Löscht die Alarm-Einträge mit den übergebenen IDs.</li><li><b>Enable:</b> Aktiviert die Alarm-Einträge mit den übergebenen IDs.</li><li><b>Disable:</b> Deaktiviert die Alarm-Einträge mit den übergebenen IDs.</li></ul>Bei Angabe des Wortes 'All' als ID, werden alle Alarme dieses Players bearbeitet.<br /><b>Die Hash-Daten:</b><br />Das Format ist ein Perl-Hash und wird mittels der eval-Funktion interpretiert.<br />e.g.: { Repeat =&gt; 1 }<br /><br />Die folgenden Schlüssel sind zulässig/notwendig:<ul><li>StartTime</li><li>Duration</li><li>Recurrence_Once</li><li>Recurrence_Monday</li><li>Recurrence_Tuesday</li><li>Recurrence_Wednesday</li><li>Recurrence_Thursday</li><li>Recurrence_Friday</li><li>Recurrence_Saturday</li><li>Recurrence_Sunday</li><li>Enabled</li><li>ProgramURI</li><li>ProgramMetaData</li><li>Shuffle</li><li>Repeat</li><li>Volume</li><li>IncludeLinkedZones</li></ul><br />z.B.:<ul><li>set Sonos_Wohnzimmer Alarm Create 0 { Enabled =&gt; 1, Volume =&gt; 35, StartTime =&gt; '00:00:00', Duration =&gt; '00:15:00', Repeat =&gt; 0, Shuffle =&gt; 0, ProgramURI =&gt; 'x-rincon-buzzer:0', ProgramMetaData =&gt; '', Recurrence_Once =&gt; 0, Recurrence_Monday =&gt; 1, Recurrence_Tuesday =&gt; 1, Recurrence_Wednesday =&gt; 1, Recurrence_Thursday =&gt; 1, Recurrence_Friday =&gt; 1, Recurrence_Saturday =&gt; 0, Recurrence_Sunday =&gt; 0, IncludeLinkedZones =&gt; 0 }</li><li>set Sonos_Wohnzimmer Alarm Update 17 { Shuffle =&gt; 1 }</li><li>set Sonos_Wohnzimmer Alarm Delete 17 {}</li></ul></li>
<li><a name="SONOSPLAYER_setter_AudioDelay">
<b><code>AudioDelay &lt;Level&gt;</code></b></a>
<br /> Setzt den AudioDelay der Playbar auf den angegebenen Wert. Der Wert kann zwischen 0 und 5 liegen.</li>
<li><a name="SONOSPLAYER_setter_AudioDelayLeftRear">
<b><code>AudioDelayLeftRear &lt;Level&gt;</code></b></a>
<br /> Setzt den AudioDelayLeftRear des Players auf den angegebenen Wert. Der Wert kann zwischen 0 und 2 liegen. Wobei die Werte folgende Bedeutung haben: 0: >3m, 1: >0.6m und <3m, 2: <0.6m</li>
<li><a name="SONOSPLAYER_setter_AudioDelayRightRear">
<b><code>AudioDelayRightRear &lt;Level&gt;</code></b></a>
<br /> Setzt den AudioDelayRightRear des Players auf den angegebenen Wert. Der Wert kann zwischen 0 und 2 liegen. Wobei die Werte folgende Bedeutung haben: 0: >3m, 1: >0.6m und <3m, 2: <0.6m</li>
<li><a name="SONOSPLAYER_setter_ButtonLockState">
<b><code>ButtonLockState &lt;int&gt;</code></b></a>
<br />One of (0, 1). Setzt den aktuellen Button-Sperr-Zustand.</li>
<li><a name="SONOSPLAYER_setter_DailyIndexRefreshTime">
<b><code>DailyIndexRefreshTime &lt;Timestring&gt;</code></b></a>
<br />Setzt die aktuell gültige DailyIndexRefreshTime für alle Zoneplayer.</li>
<li><a name="SONOSPLAYER_setter_DialogLevel">
<b><code>DialogLevel &lt;State&gt;</code></b></a>
<br /> Legt den Zustand der Sprachverbesserung der Playbar fest.</li>
<li><a name="SONOSPLAYER_setter_ExportSonosBibliothek">
<b><code>ExportSonosBibliothek &lt;filename&gt;</code></b></a>
<br />Exportiert eine Datei mit der textuellen Darstellung eines Struktur- und Titelhashs, das die komplette Navigationsstruktur aus der Sonos-Bibliothek abbildet. Achtung: Benötigt eine große Menge CPU-Zeit und Arbeitsspeicher für die Ausführung!</li>
<li><a name="SONOSPLAYER_setter_Name">
<b><code>Name &lt;Zonename&gt;</code></b></a>
<br />Legt den Namen der Zone fest.</li>
<li><a name="SONOSPLAYER_setter_NightMode">
<b><code>NightMode &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des Nachtsounds der Playbar fest.</li>
<li><a name="SONOSPLAYER_setter_OutputFixed">
<b><code>OutputFixed &lt;State&gt;</code></b></a>
<br /> Setzt den angegebenen OutputFixed-Zustand. Liefert den aktuell gültigen OutputFixed-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Reboot">
<b><code>Reboot</code></b></a>
<br />Führt für den Zoneplayer einen Neustart durch.</li>
<li><a name="SONOSPLAYER_setter_ResetAttributesToDefault">
<b><code>ResetAttributesToDefault &lt;DeleteAllOtherAttributes&gt;</code></b></a>
<br />Setzt die Attribute eines Players auf die Voreinstellung zurück, wie sie beim Anlegen des Players gesetzt waren. Wenn der Parameter "DeleteAllOtherAttributes" mit "1" oder "on" angegeben wurde, werden vor dem Setzen alle Attribute gelöscht.</li>
<li><a name="SONOSPLAYER_setter_RoomIcon">
<b><code>RoomIcon &lt;Iconname&gt;</code></b></a>
<br />Legt das Icon für die Zone fest</li>
<li><a name="SONOSPLAYER_setter_SnoozeAlarm">
<b><code>SnoozeAlarm &lt;Timestring|Seconds&gt;</code></b></a>
<br />Unterbricht eine laufende Alarmwiedergabe für den übergebenen Zeitraum.</li>
<li><a name="SONOSPLAYER_setter_SubEnable">
<b><code>SubEnable &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des Sub-Zustands fest.</li>
<li><a name="SONOSPLAYER_setter_SubGain">
<b><code>SubGain &lt;Level&gt;</code></b></a>
<br /> Setzt den SubGain auf den angegebenen Wert. Der Wert kann zwischen -15 und 15 liegen.</li>
<li><a name="SONOSPLAYER_setter_SubPolarity">
<b><code>SubPolarity &lt;Level&gt;</code></b></a>
<br /> Setzt den SubPolarity auf den angegebenen Wert. Der Wert kann zwischen 0 und 2 liegen.</li>
<li><a name="SONOSPLAYER_setter_SurroundEnable">
<b><code>SurroundEnable &lt;State&gt;</code></b></a>
<br />Setzt den SurroundEnable-Zustand.</li>
<li><a name="SONOSPLAYER_setter_SurroundLevel">
<b><code>SurroundLevel &lt;Level&gt;</code></b></a>
<br /> Setzt den Surroundlevel auf den angegebenen Wert. Der Wert kann zwischen -15 und 15 liegen.</li>
<li><a name="SONOSPLAYER_setter_TruePlay">
<b><code>TruePlay &lt;State&gt;</code></b></a>
<br />Setzt den TruePlay-Zustand.</li>
<li><a name="SONOSPLAYER_setter_Wifi">
<b><code>Wifi &lt;State&gt;</code></b></a>
<br />Setzt den WiFi-Zustand des Players. Kann 'off', 'persist-off' oder 'on' sein.</li>
</ul></li>
<li><b>Abspiel-Steuerbefehle</b><ul>
<li><a name="SONOSPLAYER_setter_CurrentTrackPosition">
<b><code>CurrentTrackPosition &lt;TimePosition&gt;</code></b></a>
<br /> Setzt die Abspielposition innerhalb des Liedes auf den angegebenen Zeitwert (z.B. 0:01:15) oder eine Sekundenangabe (z.B. 81). Man kann hier auch relative Angaben machen wie '+0:00:10' oder nur '+10'. Zusätzlich kann man auch Prozentwerte angeben wie z.B. '+10%'. Natürlich können diese Angaben auch negativ sein.</li>
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
<li><a name="SONOSPLAYER_setter_RepeatOne">
<b><code>RepeatOne &lt;State&gt;</code></b></a>
<br /> Legt den Zustand des RepeatOne-Zustands fest. Liefert den aktuell gültigen RepeatOne-Zustand.</li>
<li><a name="SONOSPLAYER_setter_RepeatOneT">
<b><code>RepeatOneT</code></b></a>
<br /> Schaltet den Zustand des RepeatOne-Zustands um. Liefert den aktuell gültigen RepeatOne-Zustand.</li>
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
<b><code>SleepTimer &lt;Timestring|Seconds&gt;</code></b></a>
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
<li><a name="SONOSPLAYER_setter_DeleteFromQueue">
<b><code>DeleteFromQueue <index_of_elems></code></b></a>
<br /> Löscht die angegebenen Elemente aus der aktuellen Abspielliste. Die Angabe erfolgt über die Indizies der Titel. Es können die bei Perl-Array-üblichen Formate verwendet werden: "1..12,17,20..22". Die Indizies beziehen sich auf die aktuell angezeigte Reihenfolge (diese unterscheidet sich zwischen der normalen Abspielweise und dem Shufflemodus).</li>
<li><a name="SONOSPLAYER_setter_DeletePlaylist">
<b><code>DeletePlaylist</code></b></a>
<br /> Löscht die bezeichnete Playliste. Zum möglichen Format des Playlistenamen unter LoadPlaylist nachsehen.</li>
<li><a name="SONOSPLAYER_setter_EmptyPlaylist">
<b><code>EmptyPlaylist</code></b></a>
<br /> Leert die aktuelle Abspielliste</li>
<li><a name="SONOSPLAYER_setter_LoadFavourite">
<b><code>LoadFavourite &lt;FavouriteName&gt;</code></b></a>
<br /> Lädt den angegebenen Favoriten. Der Name bezeichnet einen Eintrag in der Sonos-Favoritenliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/meine.hits/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadPlaylist">
<b><code>LoadPlaylist &lt;Playlistname|Fhem-Devicename&gt; [EmptyQueueBeforeImport]</code></b></a>
<br /> Lädt die angegebene Playlist in die aktuelle Abspielliste. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen. Der Playlistname kann ein Fhem-Sonosplayer-Devicename sein, dann wird dessen aktuelle Abpielliste kopiert. Der Playlistname kann aber auch ein Dateiname sein. Dann muss dieser mit 'file:' beginnen (z.B. 'file:c:/Test.m3u).<br />Wenn der Parameter EmptyQueueBeforeImport mit ''1'' angegeben wirde, wird die aktuelle Abspielliste vor dem Import geleert. Standardmäßig wird hier ''1'' angenommen.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/hits.2014/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadRadio">
<b><code>LoadRadio &lt;Radiostationname&gt;</code></b></a>
<br /> Startet den angegebenen Radiostream. Der Name bezeichnet einen Sender in der Radiofavoritenliste. Die aktuelle Abspielliste wird nicht verändert. Der Parameter sollte/kann URL-Encoded werden um auch Spezialzeichen zu ermöglichen.<br />Zusätzlich kann ein regulärer Ausdruck für den Namen verwendet werden. Der erste Treffer wird verwendet. Das Format ist z.B. <code>/radio/</code>.</li>
<li><a name="SONOSPLAYER_setter_LoadSearchlist">
<b><code>LoadSearchlist &lt;Kategoriename&gt; &lt;KategorieElement&gt; [[TitelfilterRegEx]/[AlbumfilterRegEx]/[ArtistfilterRegEx] [[*]maxElem[+|-]]]</code></b></a>
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
<li><a name="SONOSPLAYER_setter_GroupVolumeD">
<b><code>GroupVolumeD</code></b></a>
<br /> Verringert die aktuelle Gruppenlautstärke um volumeStep-Einheiten.</li>
<li><a name="SONOSPLAYER_setter_GroupVolumeU">
<b><code>GroupVolumeU</code></b></a>
<br /> Erhöht die aktuelle Gruppenlautstärke um volumeStep-Einheiten.</li>
<li><a name="SONOSPLAYER_setter_MakeStandaloneGroup">
<b><code>MakeStandaloneGroup</code></b></a>
<br />Macht diesen Player zu seiner eigenen Gruppe.</li>
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
<li><a name="SONOSPLAYER_getter_SupportLinks">
<b><code>SupportLinks</code></b></a>
<br /> Ausnahmefall. Diese Get-Anweisung liefert eine Liste mit passenden Links zu den Supportseiten des Player.</li>
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
<li><a name="SONOSPLAYER_getter_Queue">
<b><code>Queue</code></b></a>
<br /> Liefert eine Liste mit den Namen aller Titel in der aktuellen Abspielliste. Das Format der Liste ist eine Komma-Separierte Liste, bei der die Namen in doppelten Anführungsstrichen stehen. z.B. "1. Liste 1 [0:02:14]","2. Eintrag 2 [k.A.]","3. Test [0:14:00]"</li>
<li><a name="SONOSPLAYER_getter_QueueWithCovers">
<b><code>QueueWithCovers</code></b></a>
<br /> Liefert die Stringrepräsentation eines Hash mit den Namen und Covern aller Titel der aktuellen Abspielliste. Z.B.: {'Q:0/22' => {'Cover' => 'urlzumcover', 'Title' => '1. Titel'}}. Dieser String kann einfach mit '''eval''' in eine Perl-Datenstruktur umgewandelt werden.</li>
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
<li><a name="SONOSPLAYER_attribut_suppressControlButtons"><b><code>suppressControlButtons &lt;int&gt;</code></b>
</a><br /> One of (0,1). Gibt an, ob die Steuerbuttons unter der Cover-/Titelanzeige angezeigt werden sollen (=1) oder nicht (=0).</li>
</ul></li>
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
<li><a name="SONOSPLAYER_attribut_getTitleInfoFromMaster"><b><code>getTitleInfoFromMaster &lt;int&gt;</code></b>
</a><br /> Eins aus (0,1,2,3,4,5,6,7,8,9,10,15,20,25,30,45,60). Bringt das Device dazu, seine aktuellen Abspielinformationen vom aktuellen Gruppenmaster zu holen, wenn es einen solchen gibt.</li>
<li><a name="SONOSPLAYER_attribut_simulateCurrentTrackPosition"><b><code>simulateCurrentTrackPosition &lt;int&gt;</code></b>
</a><br /> Eins aus (0, 1). Bringt das Device dazu, seine aktuelle Abspielposition simuliert weiterlaufen zu lassen. Dazu werden die Readings <code>currentTrackPositionSimulated</code> und <code>currentTrackPositionSimulatedSec</code> gesetzt. Gleichzeitig wird auch das Reading <code>currentTrackPositionSimulatedPercent</code> (zwischen 0.0 und 100.0) gesetzt.</li>
<li><a name="SONOSPLAYER_attribut_simulateCurrentTrackPositionPercentFormat"><b><code>simulateCurrentTrackPositionPercentFormat &lt;Format&gt;</code></b>
</a><br /> Definiert das Format für die sprintf-Prozentausgabe im Reading <code>currentTrackPositionSimulatedPercent</code>.</li>
<li><a name="SONOSPLAYER_attribut_stateVariable"><b><code>stateVariable &lt;string&gt;</code></b>
</a><br /> One of (TransportState,NumberOfTracks,Track,TrackURI,TrackDuration,Title,Artist,Album,OriginalTrackNumber,AlbumArtist,<br />Sender,SenderCurrent,SenderInfo,StreamAudio,NormalAudio,AlbumArtURI,nextTrackDuration,nextTrackURI,nextAlbumArtURI,<br />nextTitle,nextArtist,nextAlbum,nextAlbumArtist,nextOriginalTrackNumber,Volume,Mute,Shuffle,Repeat,RepeatOne,CrossfadeMode,Balance,<br />HeadphoneConnected,SleepTimer,Presence,RoomName,SaveRoomName,PlayerType,Location,SoftwareRevision,SerialNum,InfoSummarize1,I<br />nfoSummarize2,InfoSummarize3,InfoSummarize4). Gibt an, welche Variable in das Reading <code>state</code> kopiert werden soll.</li>
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
<li><a name="SONOSPLAYER_attribut_saveSleeptimerInAction"><b><code>saveSleeptimerInAction &lt;int&gt;</code></b>
</a><br /> One of (0..1). Wenn gesetzt, wird ein etwaig gesetztes Attribut "stopSleeptimerInAction" ignoriert.</li>
<li><a name="SONOSPLAYER_attribut_stopSleeptimerInAction"><b><code>stopSleeptimerInAction &lt;int&gt;</code></b>
</a><br /> One of (0..1). Wenn gesetzt, wird bei einem Wechsel des transportState auf "PAUSED_PLAYBACK" oder "STOPPED" ein etwaig definierter SleepTimer deaktiviert.</li>
</ul>
<a name="SONOSPLAYERexamples"></a>
<h4>Beispiele / Hinweise</h4>
<ul>
<li><a name="SONOSPLAYER_examples_InfoSummarize">Format von InfoSummarize:</a><br />
<code>infoSummarizeX := &lt;NormalAudio&gt;:summarizeElem:&lt;/NormalAudio&gt; &lt;StreamAudio&gt;:summarizeElem:&lt;/StreamAudio&gt;|:summarizeElem:</code><br />
<code>:summarizeElem: := &lt;:variable:[ prefix=":text:"][ suffix=":text:"][ instead=":text:"][ ifempty=":text:"]/[ emptyVal=":text:"]&gt;</code><br />
<code>:variable: := TransportState|NumberOfTracks|Track|TrackURI|TrackDuration|Title|Artist|Album|OriginalTrackNumber|AlbumArtist|<br />Sender|SenderCurrent|SenderInfo|StreamAudio|NormalAudio|AlbumArtURI|nextTrackDuration|nextTrackURI|nextAlbumArtURI|<br />nextTitle|nextArtist|nextAlbum|nextAlbumArtist|nextOriginalTrackNumber|Volume|Mute|Shuffle|Repeat|RepeatOne|CrossfadeMode|Balance|<br />HeadphoneConnected|SleepTimer|Presence|RoomName|SaveRoomName|PlayerType|Location|SoftwareRevision|SerialNum|InfoSummarize1|<br />InfoSummarize2|InfoSummarize3|InfoSummarize4</code><br />
<code>:text: := [Jeder beliebige Text ohne doppelte Anführungszeichen]</code><br /></li>
</ul>

=end html_DE
=cut