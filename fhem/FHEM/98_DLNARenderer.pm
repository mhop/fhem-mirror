############################################################################
# Author: dominik.karall@gmail.com
# $Id$
#
# v2.0.7 - 20180108
# - FEATURE: support ignoredIPs and usedonlyIPs attribute
#
# v2.0.6 - 20171209
# - FEATURE: support acceptedUDNs for UDN whitelisting (thx@MichaelT!)
# - BUGFIX:  fix renew subscriptions errors on offline devices
# - BUGFIX:  fix renew warnings, now only on log level 5 (thx@mumpitzstuff!)
#
# v2.0.5 - 20170430
# - BUGFIX:  fix "readings not updated"
#
# v2.0.4 - 20170421
# - FEATURE: support $readingFnAttributes
# - BUGFIX:  fix some freezes
# - BUGFIX:  retry UPnP call 3 times if it fails (error 500)
#
# v2.0.3 - 20160918
# - BUGFIX: fixed SyncPlay for CaskeId players
#
# v2.0.2 - 20160913
# - BUGFIX: fixed pauseToggle (thx@MattG)
# - BUGFIX: fixed next/previous (thx@MattG)
#
# v2.0.1 - 20160725
# - FEATURE: support DIDL-Lite in channel_X attribute (thx@Weissbrotgrill)
# - FEATURE: automatically generate DIDL-Lite based on URI (thx@Weissbrotgrill)
# - CHANGE: update CommandRef perl library requirements
# - BUGFIX: fix ignoreUDNs crash when device gets removed
#
# v2.0.0 - 20160718
# - CHANGE: first official release within fhem repository
# - BUGFIX: support device events without / at the end of the xmlns (thx@MichaelT)
# - FEATURE: support defaultRoom attribute, defines the room to which new devices are assigned
#
# v2.0.0 RC5 - 20160614
# - BUGFIX: support events from devices with wrong serviceId
# - BUGFIX: fix perl warning on startup
# - BUGFIX: fix error if LastChange event is empty
#
# v2.0.0 RC4 - 20160613
# - FEATURE: support devices with wrong serviceId
# - BUGFIX: fix crash during stereo mode update for caskeid players
# - FEATURE: add stereoPairName reading
# - CHANGE: add version string to main device internals
# - BUGFIX: fix error when UPnP method is not implemented
# - FEATURE: identify stereo support (reading: stereoSupport)
#
# v2.0.0 RC3 - 20160609
# - BUGFIX: check correct number of params for all commands
# - BUGFIX: fix addUnitToSession/removeUnitFromSession for MUNET/Caskeid devices
# - BUGFIX: support devices with non-standard UUIDs
# - CHANGE: use BlockingCall for subscription renewal
# - CHANGE: remove ignoreUDNs attribute from play devices
# - CHANGE: remove multiRoomGroups attribute from main device
# - CHANGE: split stereoDevices reading into stereoLeft/stereoRight
# - FEATURE: support multiRoomVolume to change volume of all group speakers e.g.
#              set <name> multiRoomVolume +10
#              set <name> multiRoomVolume 25
# - FEATURE: support channel_01-10 attribute
#              attr <name> channel_01 http://... (save URI to channel_01)
#              set <name> channel 1 (play channel_01)
# - FEATURE: support speak functionality via Google Translate
#              set <name> speak "This is a test."
#              attr <name> ttsLanguage de
#              set <name> speak "Das ist ein Test."
# - FEATURE: automatically retrieve stereo mode from speakers and update stereoId/Left/Right readings
# - FEATURE: support mute
#              set <name> mute on/off
#
# v2.0.0 RC2 - 20160510
# - BUGFIX: fix multiroom for MUNET/Caskeid devices
#
# v2.0.0 RC1 - 20160509
# - CHANGE: change state to offline/playing/stopped/paused/online
# - CHANGE: removed on/off devstateicon on creation due to changed state values
# - CHANGE: play is NOT setting AVTransport any more
# - CHANGE: code cleanup
# - CHANGE: handle socket via fhem main loop instead of InternalTimer
# - BUGFIX: do not create new search objects every 30 minutes
# - FEATURE: support pauseToggle
# - FEATURE: support SetExtensions (on-for-timer, off-for-timer, ...)
# - FEATURE: support relative volume changes (e.g. set <device> volume +10)
#
# v2.0.0 BETA3 - 20160504
# - BUGFIX: XML parsing error "NOT_IMPLEMENTED"
# - CHANGE: change readings to lowcaseUppercase format
# - FEATURE: support pause
# - FEATURE: support seek REL_TIME
# - FEATURE: support next/prev
#
# v2.0.0 BETA2 - 20160403
# - FEATURE: support events from DLNA devices
# - FEATURE: support caskeid group definitions
#                set <name> saveGroupAs Bad
#                set <name> loadGroup Bad
# - FEATURE: support caskeid stereo mode
#                set <name> stereo MUNET1 MUNET2 MunetStereoPaar
#                set <name> standalone
# - CHANGE: use UPnP::ControlPoint from FHEM library
# - BUGFIX: fix presence status
#
# v2.0.0 BETA1 - 20160321
# - FEATURE: autodiscover and autocreate DLNA devices
#       just use "define dlnadevices DLNARenderer" and wait 2 minutes
# - FEATURE: support Caskeid (e.g. MUNET devices) with following commands
#                set <name> playEverywhere
#                set <name> stopPlayEverywhere
#                set <name> addUnit <UNIT>
#                set <name> removeUnit <UNIT>
#                set <name> enableBTCaskeid
#                set <name> disableBTCaskeid
# - FEATURE: display multiroom speakers in multiRoomUnits reading
# - FEATURE: automatically set alias for friendlyname
# - FEATURE: automatically set webCmd volume
# - FEATURE: automatically set devStateIcon audio icons
# - FEATURE: ignoreUDNs attribute in main
# - FEATURE: scanInterval attribute in main
#
# DLNA Module to play given URLs on a DLNA Renderer
# and control their volume. Just define
#    define dlnadevices DLNARenderer
# and look for devices in Unsorted section after 2 minutes.
#
#TODO
# - speak: support continue stream after speak finished
# - redesign multiroom functionality (virtual devices: represent the readings of master device
#    and send the commands only to the master device (except volume?)
#    automatically create group before playing
# - use bulk update for readings
#
############################################################################

package main;

use strict;
use warnings;

use Blocking;
use SetExtensions;

use HTML::Entities;
use XML::Simple;
use Data::Dumper;
use Data::UUID;
use LWP::UserAgent;

#get UPnP::ControlPoint loaded properly
my $gPath = '';
BEGIN {
	$gPath = substr($0, 0, rindex($0, '/'));
}
if (lc(substr($0, -7)) eq 'fhem.pl') {
	$gPath = $attr{global}{modpath}.'/FHEM';
}
use lib ($gPath.'/lib', $gPath.'/FHEM/lib', './FHEM/lib', './lib', './FHEM', './', '/usr/local/FHEM/share/fhem/FHEM/lib');

use UPnP::ControlPoint;

sub DLNARenderer_Initialize($) {
  my ($hash) = @_;

  $hash->{SetFn}     = "DLNARenderer_Set";
  $hash->{DefFn}     = "DLNARenderer_Define";
  $hash->{ReadFn}    = "DLNARenderer_Read";
  $hash->{UndefFn}   = "DLNARenderer_Undef";
  $hash->{AttrFn}    = "DLNARenderer_Attribute";
  $hash->{AttrList}  = "ignoredIPs usedonlyIPs ".$readingFnAttributes;
}

sub DLNARenderer_Attribute {
  my ($mode, $devName, $attrName, $attrValue) = @_;
  #ignoreUDNs, multiRoomGroups, channel_01-10
  
  if($mode eq "set") {
    
  } elsif($mode eq "del") {
    
  }
  
  return undef;
}

sub DLNARenderer_Define($$) {
  my ($hash, $def) = @_;
  my @param = split("[ \t][ \t]*", $def);
  
  #init caskeid clients for multiroom
  $hash->{helper}{caskeidClients} = "";
  $hash->{helper}{caskeid} = 0;
  
  if(@param < 3) {
    #main
    $hash->{UDN} = 0;
    my $VERSION = "v2.0.7";
    $hash->{VERSION} = $VERSION;
    Log3 $hash, 3, "DLNARenderer: DLNA Renderer $VERSION";
    DLNARenderer_setupControlpoint($hash);
    DLNARenderer_startDlnaRendererSearch($hash);
    readingsSingleUpdate($hash,"state","initialized",1);
    addToDevAttrList($hash->{NAME}, "ignoreUDNs");
    addToDevAttrList($hash->{NAME}, "acceptedUDNs");
    addToDevAttrList($hash->{NAME}, "defaultRoom");
    return undef;
  }
  
  #device specific
  my $name     = shift @param;
  my $type     = shift @param;
  my $udn      = shift @param;
  $hash->{UDN} = $udn;
  
  readingsSingleUpdate($hash,"presence","offline",1);
  readingsSingleUpdate($hash,"state","offline",1);
  
  addToDevAttrList($hash->{NAME}, "multiRoomGroups");
  addToDevAttrList($hash->{NAME}, "ttsLanguage");
  addToDevAttrList($hash->{NAME}, "channel_01");
  addToDevAttrList($hash->{NAME}, "channel_02");
  addToDevAttrList($hash->{NAME}, "channel_03");
  addToDevAttrList($hash->{NAME}, "channel_04");
  addToDevAttrList($hash->{NAME}, "channel_05");
  addToDevAttrList($hash->{NAME}, "channel_06");
  addToDevAttrList($hash->{NAME}, "channel_07");
  addToDevAttrList($hash->{NAME}, "channel_08");
  addToDevAttrList($hash->{NAME}, "channel_09");
  addToDevAttrList($hash->{NAME}, "channel_10");
  
  return undef;
}

sub DLNARenderer_Undef($) {
  my ($hash) = @_;
  
  RemoveInternalTimer($hash);
  return undef;
}

sub DLNARenderer_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $phash = $hash->{phash};
  my $cp = $phash->{helper}{controlpoint};
  
  eval {
    $cp->handleOnce($hash->{CD});
  };
  
  if($@) {
    Log3 $hash, 3, "DLNARenderer: handleOnce failed, $@";
  }
  
  return undef;
}

sub DLNARenderer_Set($@) {
  my ($hash, $name, @params) = @_;
  my $dev = $hash->{helper}{device};
  
  # check parameters
  return "no set value specified" if(int(@params) < 1);
  my $ctrlParam = shift(@params);
  
  # check device presence
  if ($ctrlParam ne "?" and (!defined($dev) or ReadingsVal($hash->{NAME}, "presence", "") eq "offline")) {
    return "DLNARenderer: Currently searching for device...";
  }
  
  #get quoted text from params
  my $blankParams = join(" ", @params);
  my @params2;
  while($blankParams =~ /"?((?<!")\S+(?<!")|[^"]+)"?\s*/g) {
      push(@params2, $1);
  }
  @params = @params2;
  
  my $set_method_mapping = {
    volume            => {method => \&DLNARenderer_volume, args => 1, argdef => "slider,0,1,100"},
    mute              => {method => \&DLNARenderer_mute, args => 1, argdef => "on,off"},
    pause             => {method => \&DLNARenderer_upnpPause, args => 0},
    pauseToggle       => {method => \&DLNARenderer_pauseToggle, args => 0},
    play              => {method => \&DLNARenderer_play, args => 0},
    next              => {method => \&DLNARenderer_upnpNext, args => 0},
    previous          => {method => \&DLNARenderer_upnpPrevious, args => 0},
    seek              => {method => \&DLNARenderer_seek, args => 1},
    multiRoomVolume   => {method => \&DLNARenderer_setMultiRoomVolume, args => 1, argdef => "slider,0,1,100", caskeid => 1},
    stereo            => {method => \&DLNARenderer_setStereoMode, args => 3, caskeid => 1},
    standalone        => {method => \&DLNARenderer_setStandaloneMode, args => 0, caskeid => 1},
    playEverywhere    => {method => \&DLNARenderer_playEverywhere, args => 0, caskeid => 1},
    stopPlayEverywhere => {method => \&DLNARenderer_stopPlayEverywhere, args => 0, caskeid => 1},
    addUnit           => {method => \&DLNARenderer_addUnit, args => 1, argdef => $hash->{helper}{caskeidClients}, caskeid => 1},
    removeUnit        => {method => \&DLNARenderer_removeUnit, args => 1, argdef => ReadingsVal($hash->{NAME}, "multiRoomUnits", ""), caskeid => 1},
    saveGroupAs       => {method => \&DLNARenderer_saveGroupAs, args => 1, caskeid => 1},
    enableBTCaskeid   => {method => \&DLNARenderer_enableBTCaskeid, args => 0, caskeid => 1},
    disableBTCaskeid  => {method => \&DLNARenderer_disableBTCaskeid, args => 0, caskeid => 1},
    off               => {method => \&DLNARenderer_upnpStop, args => 0},
    stop              => {method => \&DLNARenderer_upnpStop, args => 0},
    loadGroup         => {method => \&DLNARenderer_loadGroup, args => 1, caskeid => 1},
    on                => {method => \&DLNARenderer_on, args => 0},
    stream            => {method => \&DLNARenderer_stream, args => 1},
    channel           => {method => \&DLNARenderer_channel, args => 1, argdef => "1,2,3,4,5,6,7,8,9,10"},
    speak             => {method => \&DLNARenderer_speak, args => 1}
  };
  
  if($set_method_mapping->{$ctrlParam}) {
    if($set_method_mapping->{$ctrlParam}{args} != int(@params)) {
      return "DLNARenderer: $ctrlParam requires $set_method_mapping->{$ctrlParam}{args} parameter.";
    }
    #params array till args number
    my @args = @params[0 .. $set_method_mapping->{$ctrlParam}{args}];
    $set_method_mapping->{$ctrlParam}{method}->($hash, @args);
  } else {
    my $cmdList;
    foreach my $cmd (keys %$set_method_mapping) {
      next if($hash->{helper}{caskeid} == 0 && $set_method_mapping->{$cmd}{caskeid} && $set_method_mapping->{$cmd}{caskeid} == 1);
      if($set_method_mapping->{$cmd}{args} == 0) {
        $cmdList .= $cmd.":noArg ";
      } else {
        if($set_method_mapping->{$cmd}{argdef}) {
          $cmdList .= $cmd.":".$set_method_mapping->{$cmd}{argdef}." ";
        } else {
          $cmdList .= $cmd." ";
        }
      }
    }
    return SetExtensions($hash, $cmdList, $name, $ctrlParam, @params);
  }
  return undef;
}

##############################
##### SET FUNCTIONS ##########
##############################
sub DLNARenderer_speak {
  my ($hash, $ttsText) = @_;
  my $ttsLang = AttrVal($hash->{NAME}, "ttsLanguage", "en");
  return "DLNARenderer: Maximum text length is 100 characters." if(length($ttsText) > 100);
  
  DLNARenderer_stream($hash, "http://translate.google.com/translate_tts?tl=$ttsLang&client=tw-ob&q=$ttsText", "");
}

sub DLNARenderer_channel {
  my ($hash, $channelNr) = @_;
  my $stream = AttrVal($hash->{NAME}, sprintf("channel_%02d", $channelNr), "");
  if($stream eq "") {
    return "DLNARenderer: Set channel_XX attribute first.";
  }
  my $meta = "";
  if (substr($stream,0,10) eq "<DIDL-Lite") {
    eval {
      my $xml = XMLin($stream);
      $meta = $stream;
      $stream = $xml->{"item"}{"res"}{"content"};
    };

    if($@) {
      Log3 $hash, 2, "DLNARenderer: Incorrect DIDL-Lite format, $@";
    }
  }
  DLNARenderer_stream($hash, $stream, $meta);
  readingsSingleUpdate($hash, "channel", $channelNr, 1);
}

sub DLNARenderer_stream {
  my ($hash, $stream, $meta) = @_;
  if (!defined($meta)) {
    DLNARenderer_generateDidlLiteAndPlay($hash, $stream);
    return undef;
  }
  
  DLNARenderer_upnpSetAVTransportURI($hash, $stream, $meta);
  DLNARenderer_play($hash);
  readingsSingleUpdate($hash, "stream", $stream, 1);
}

sub DLNARenderer_on {
  my ($hash) = @_;
  if (defined($hash->{READINGS}{stream})) {
    my $lastStream = $hash->{READINGS}{stream}{VAL};
    if ($lastStream) {
      DLNARenderer_upnpSetAVTransportURI($hash, $lastStream);
      DLNARenderer_play($hash);
    }
  }
}

sub DLNARenderer_convertVolumeToAbsolute {
  my ($hash, $targetVolume) = @_;
  
  if(substr($targetVolume, 0, 1) eq "+" or
     substr($targetVolume, 0, 1) eq "-") {
      $targetVolume = ReadingsVal($hash->{NAME}, "volume", 0) + $targetVolume;
  }
  return $targetVolume;
}

sub DLNARenderer_volume {
  my ($hash, $targetVolume) = @_;
  
  $targetVolume = DLNARenderer_convertVolumeToAbsolute($hash, $targetVolume);
  
  DLNARenderer_upnpSetVolume($hash, $targetVolume);
}

sub DLNARenderer_mute {
  my ($hash, $muteState) = @_;
  
  if($muteState eq "on") {
    $muteState = 1;
  } else {
    $muteState = 0;
  }
  
  DLNARenderer_upnpSetMute($hash, $muteState);
}

sub DLNARenderer_removeUnit {
  my ($hash, $unitToRemove) = @_;
  DLNARenderer_removeUnitToPlay($hash, $unitToRemove);

  my $multiRoomUnitsReading = "";
  my @multiRoomUnits = split(",", ReadingsVal($hash->{NAME}, "multiRoomUnits", ""));
  
  foreach my $unit (@multiRoomUnits) {
    $multiRoomUnitsReading .= ",".$unit if($unit ne $unitToRemove);
  }
  $multiRoomUnitsReading = substr($multiRoomUnitsReading, 1) if($multiRoomUnitsReading ne "");
  readingsSingleUpdate($hash, "multiRoomUnits", $multiRoomUnitsReading, 1);
  
  return undef;
}

sub DLNARenderer_loadGroup {
  my ($hash, $groupName) = @_;
  my $groupMembers = DLNARenderer_getGroupDefinition($hash, $groupName);
  return "DLNARenderer: Group $groupName not defined." if(!defined($groupMembers));
  DLNARenderer_destroyCurrentSession($hash);

  my $leftSpeaker = "";
  my $rightSpeaker = "";
  my @groupMembersArray = split(",", $groupMembers);
  
  foreach my $member (@groupMembersArray) {
    if($member =~ /^R:([a-zA-Z0-9äöüßÄÜÖ_]+)/) {
      $rightSpeaker = $1;
    } elsif($member =~ /^L:([a-zA-Z0-9äöüßÄÜÖ_]+)/) {
      $leftSpeaker = $1;
    } else {
      DLNARenderer_addUnit($hash, $member);
    }
  }
  
  if($leftSpeaker ne "" && $rightSpeaker ne "") {
    DLNARenderer_setStereoMode($hash, $leftSpeaker, $rightSpeaker, $groupName);
  }
}

sub DLNARenderer_stopPlayEverywhere {
  my ($hash) = @_;
  DLNARenderer_destroyCurrentSession($hash);
  readingsSingleUpdate($hash, "multiRoomUnits", "", 1);
  return undef;
}

sub DLNARenderer_playEverywhere {
  my ($hash) = @_;
  my $multiRoomUnits = "";
  my @caskeidClients = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
  foreach my $client (@caskeidClients) {
    if($client->{UDN} ne $hash->{UDN}) {
      DLNARenderer_addUnitToPlay($hash, substr($client->{UDN},5));
      
      my $multiRoomUnits = ReadingsVal($hash->{NAME}, "multiRoomUnits", "");
      
      $multiRoomUnits .= "," if($multiRoomUnits ne "");
      $multiRoomUnits .= ReadingsVal($client->{NAME}, "friendlyName", "");
      readingsSingleUpdate($hash, "multiRoomUnits", $multiRoomUnits, 1);
    }
  }
  return undef;
}

sub DLNARenderer_setMultiRoomVolume {
  my ($hash, $targetVolume) = @_;
  
  #change volume of this device
  DLNARenderer_volume($hash, $targetVolume);
  
  #handle volume for all devices in the current group
  #iterate through group and change volume relative to the current volume of this device
  my $mainVolumeDiff = DLNARenderer_convertVolumeToAbsolute($hash, $targetVolume) - ReadingsVal($hash->{NAME}, "volume", 0);
  my $multiRoomUnits = ReadingsVal($hash->{NAME}, "multiRoomUnits", "");
  my @multiRoomUnitsArray = split(",", $multiRoomUnits);
  foreach my $unit (@multiRoomUnitsArray) {
    my $devHash = DLNARenderer_getHashByFriendlyName($hash, $unit);
    my $newVolume = ReadingsVal($devHash->{NAME}, "volume", 0) + $mainVolumeDiff;
    if($newVolume > 100) {
      $newVolume = 100;
    } elsif($newVolume < 0) {
      $newVolume = 0;
    }
    DLNARenderer_volume($devHash, $newVolume);
  }
  
  return undef;
}

sub DLNARenderer_pauseToggle {
  my ($hash) = @_;
  if($hash->{READINGS}{state}{VAL} eq "paused") {
      DLNARenderer_play($hash);
  } else {
      DLNARenderer_upnpPause($hash);
  }
}

sub DLNARenderer_play {
  my ($hash) = @_;
  
  #start play
  if($hash->{helper}{caskeid}) {
    if($hash->{READINGS}{sessionId}{VAL} eq "") {
      DLNARenderer_createSession($hash);
    }
    DLNARenderer_upnpSyncPlay($hash);
  } else {
    DLNARenderer_upnpPlay($hash);
  }
  
  return undef;
}

###########################
##### CASKEID #############
###########################
# BTCaskeid
sub DLNARenderer_enableBTCaskeid {
  my ($hash) = @_;
  DLNARenderer_upnpAddToGroup($hash, "4DAA44C0-8291-11E3-BAA7-0800200C9A66", "Bluetooth");
}

sub DLNARenderer_disableBTCaskeid {
  my ($hash) = @_;
  DLNARenderer_upnpRemoveFromGroup($hash, "4DAA44C0-8291-11E3-BAA7-0800200C9A66");
}

# Stereo Mode
sub DLNARenderer_setStereoMode {
  my ($hash, $leftSpeaker, $rightSpeaker, $name) = @_;
  
  DLNARenderer_destroyCurrentSession($hash);

  my @multiRoomDevices = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
  my $uuid = DLNARenderer_createUuid($hash);
  
  foreach my $device (@multiRoomDevices) {
    if(ReadingsVal($device->{NAME}, "friendlyName", "") eq $leftSpeaker) {
      DLNARenderer_setMultiChannelSpeaker($device, "left", $uuid, $leftSpeaker);
      readingsSingleUpdate($hash, "stereoLeft", $leftSpeaker, 1);
    } elsif(ReadingsVal($device->{NAME}, "friendlyName", "") eq $rightSpeaker) {
      DLNARenderer_setMultiChannelSpeaker($device, "right", $uuid, $rightSpeaker);
      readingsSingleUpdate($hash, "stereoRight", $rightSpeaker, 1);
    }
  }
}

sub DLNARenderer_updateStereoMode {
  my ($hash) = @_;
  
  if(!defined($hash->{helper}{device})) {
    InternalTimer(gettimeofday() + 10, 'DLNARenderer_updateStereoMode', $hash, 0);
    return undef;
  }
  
  if($hash->{helper}{caskeid} == 0) {
    return undef;
  }
  
  my $result = DLNARenderer_upnpGetMultiChannelSpeaker($hash);
  if($result) {
    InternalTimer(gettimeofday() + 300, 'DLNARenderer_updateStereoMode', $hash, 0);
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoSupport", 1, 1);
  } else {
    #speaker does not support multi channel
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoSupport", 0, 1);
    return undef;
  }
    
  my $mcsType = $result->getValue("CurrentMCSType");
  my $mcsId = $result->getValue("CurrentMCSID");
  my $mcsFriendlyName = $result->getValue("CurrentMCSFriendlyName");
  my $mcsSpeakerChannel = $result->getValue("CurrentSpeakerChannel");
  
  DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoPairName", $mcsFriendlyName, 1);
  DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoId", $mcsId, 1);
  
  if($mcsId eq "") {
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoLeft", "", 1);
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoRight", "", 1);
  } else {
    #THIS speaker is the left or right speaker
    DLNARenderer_setStereoSpeakerReading($hash, $hash, $mcsType, $mcsId, $mcsFriendlyName, $mcsSpeakerChannel);
    #set left/right speaker for OTHER speaker if OTHER speaker has same mcsId
    my @allHashes = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
    foreach my $hash2 (@allHashes) {
      my $result2 = DLNARenderer_upnpGetMultiChannelSpeaker($hash2);
      next if(!defined($result2));
      
      my $mcsType2 = $result2->getValue("CurrentMCSType");
      my $mcsId2 = $result2->getValue("CurrentMCSID");
      my $mcsFriendlyName2 = $result2->getValue("CurrentMCSFriendlyName");
      my $mcsSpeakerChannel2 = $result2->getValue("CurrentSpeakerChannel");
      
      if($mcsId2 eq $mcsId) {
        DLNARenderer_setStereoSpeakerReading($hash, $hash2, $mcsType2, $mcsId2, $mcsFriendlyName2, $mcsSpeakerChannel2);
      }
    }
  }
}

sub DLNARenderer_setStereoSpeakerReading {
  my ($hash, $speakerHash, $mcsType, $mcsId, $mcsFriendlyName, $mcsSpeakerChannel) = @_;
  DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoId", $mcsId, 1);
  if($mcsSpeakerChannel eq "LEFT_FRONT") {
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoLeft", ReadingsVal($speakerHash->{NAME}, "friendlyName", ""), 1);
  } elsif($mcsSpeakerChannel eq "RIGHT_FRONT") {
    DLNARenderer_readingsSingleUpdateIfChanged($hash, "stereoRight", ReadingsVal($speakerHash->{NAME}, "friendlyName", ""), 1);
  }
}

sub DLNARenderer_readingsSingleUpdateIfChanged {
  my ($hash, $reading, $value, $trigger) = @_;
  my $curVal = ReadingsVal($hash->{NAME}, $reading, "");
  
  if($curVal ne $value) {
    readingsSingleUpdate($hash, $reading, $value, $trigger);
  }
}

sub DLNARenderer_setMultiChannelSpeaker {
  my ($hash, $mode, $uuid, $name) = @_;
  my $uuidStr;
  
  if($mode eq "standalone") {
    DLNARenderer_upnpSetMultiChannelSpeaker($hash, "STANDALONE", "", "", "STANDALONE_SPEAKER");
  } elsif($mode eq "left") {
    DLNARenderer_upnpSetMultiChannelSpeaker($hash, "STEREO", $uuid, $name, "LEFT_FRONT");
  } elsif($mode eq "right") {
    DLNARenderer_upnpSetMultiChannelSpeaker($hash, "STEREO", $uuid, $name, "RIGHT_FRONT");
  }
  
  return undef;
}

sub DLNARenderer_setStandaloneMode {
  my ($hash) = @_;
  my @multiRoomDevices = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
  my $rightSpeaker = ReadingsVal($hash->{NAME}, "stereoRight", "");
  my $leftSpeaker = ReadingsVal($hash->{NAME}, "stereoLeft", "");
  
  foreach my $device (@multiRoomDevices) {
    if(ReadingsVal($device->{NAME}, "friendlyName", "") eq $leftSpeaker or
       ReadingsVal($device->{NAME}, "friendlyName", "") eq $rightSpeaker) {
      DLNARenderer_setMultiChannelSpeaker($device, "standalone", "", "");
    }
  }
  
  readingsSingleUpdate($hash, "stereoLeft", "", 1);
  readingsSingleUpdate($hash, "stereoRight", "", 1);
  readingsSingleUpdate($hash, "stereoId", "", 1);
  
  return undef;
}

sub DLNARenderer_createUuid {
  my ($hash) = @_;
  my $ug = Data::UUID->new();
  my $uuid = $ug->create();
  my $uuidStr = $ug->to_string($uuid);
  
  return $uuidStr;
}

# SessionManagement
sub DLNARenderer_createSession {
  my ($hash) = @_;
  return DLNARenderer_upnpCreateSession($hash, "FHEM_Session");
}

sub DLNARenderer_getSession {
  my ($hash) = @_;
  return DLNARenderer_upnpGetSession($hash);
}

sub DLNARenderer_destroySession {
  my ($hash, $session) = @_;
  
  return DLNARenderer_upnpDestroySession($hash, $session);
}

sub DLNARenderer_destroyCurrentSession {
  my ($hash) = @_;
  
  my $result = DLNARenderer_getSession($hash);
  if($result->getValue("SessionID") ne "") {
    DLNARenderer_destroySession($hash, $result->getValue("SessionID"));
  }
}

sub DLNARenderer_addUnitToPlay {
  my ($hash, $unit) = @_;
  
  my $session = DLNARenderer_getSession($hash)->getValue("SessionID");
  
  if($session eq "") {
    $session = DLNARenderer_createSession($hash)->getValue("SessionID");
  }
  
  DLNARenderer_addUnitToSession($hash, $unit, $session);
}

sub DLNARenderer_removeUnitToPlay {
  my ($hash, $unit) = @_;
  
  my $session = DLNARenderer_getSession($hash)->getValue("SessionID");
  
  if($session ne "") {
    DLNARenderer_removeUnitFromSession($hash, $unit, $session);
  }
}

sub DLNARenderer_addUnitToSession {
  my ($hash, $uuid, $session) = @_;
  
  return DLNARenderer_upnpAddUnitToSession($hash, $session, $uuid);
}

sub DLNARenderer_removeUnitFromSession {
  my ($hash, $uuid, $session) = @_;
  
  return DLNARenderer_upnpRemoveUnitFromSession($hash, $session, $uuid);
}

# Group Definitions
sub DLNARenderer_getGroupDefinition {
  #used for ... play Bad ...
  my ($hash, $groupName) = @_;
  my $currentGroupSettings = AttrVal($hash->{NAME}, "multiRoomGroups", "");
  
  #regex Bad[MUNET1,MUNET2],WZ[L:MUNET2,R:MUNET3],...
  while ($currentGroupSettings =~ /([a-zA-Z0-9äöüßÄÜÖ_]+)\[([a-zA-Z,0-9:äöüßÄÜÖ_]+)/g) {
    my $group = $1;
    my $groupMembers = $2;
    
    Log3 $hash, 4, "DLNARenderer: Groupdefinition $group => $groupMembers";
    
    if($group eq $groupName) {
      return $groupMembers;
    }
  }
  
  return undef;
}

sub DLNARenderer_saveGroupAs {
  my ($hash, $groupName) = @_;
  my $currentGroupSettings = AttrVal($hash->{NAME}, "multiRoomGroups", "");
  $currentGroupSettings .= "," if($currentGroupSettings ne "");
  
  #session details
  my $currentSession = ReadingsVal($hash->{NAME}, "multiRoomUnits", "");
  #stereo mode
  my $stereoLeft = ReadingsVal($hash->{NAME}, "stereoLeft", "");
  my $stereoRight = ReadingsVal($hash->{NAME}, "stereoRight", "");
  my $stereoDevices = "L:$stereoLeft,R:$stereoRight" if($stereoLeft ne "" && $stereoRight ne "");
  
  return undef if($currentSession eq "" && $stereoLeft eq "" && $stereoRight eq "");
  $stereoDevices .= "," if($currentSession ne "" && $stereoDevices ne "");
  
  my $groupDefinition = $currentGroupSettings.$groupName."[".$stereoDevices.$currentSession."]";
    
  #save current session as group
  CommandAttr(undef, "$hash->{NAME} multiRoomGroups $groupDefinition");
  
  return undef;
}

sub DLNARenderer_addUnit {
  my ($hash, $unitName) = @_;
  
  my @caskeidClients = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
  foreach my $client (@caskeidClients) {
    if(ReadingsVal($client->{NAME}, "friendlyName", "") eq $unitName) {
      my @multiRoomUnits = split(",", ReadingsVal($hash->{NAME}, "multiRoomUnits", ""));
      foreach my $unit (@multiRoomUnits) {
        #skip if unit is already part of the session
        return undef if($unit eq $unitName);
      }
      #add unit to session
      DLNARenderer_addUnitToPlay($hash, substr($client->{UDN},5));
      return undef;
    }
  }
  return "DLNARenderer: No unit $unitName found.";
}

##############################
####### UPNP FUNCTIONS #######
##############################
sub DLNARenderer_upnpPause {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Pause", 0);
}

sub DLNARenderer_upnpSetAVTransportURI {
  my ($hash, $stream, $meta) = @_;
  if (!defined($meta)) { $meta = ""; }
  return DLNARenderer_upnpCallAVTransport($hash, "SetAVTransportURI", 0, $stream, $meta);
}

sub DLNARenderer_upnpStop {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Stop", 0);
}

sub DLNARenderer_upnpSeek {
  my ($hash, $seekTime) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Seek", 0, "REL_TIME", $seekTime);
}

sub DLNARenderer_upnpNext {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Next", 0);
}

sub DLNARenderer_upnpPrevious {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Previous", 0);
}

sub DLNARenderer_upnpPlay {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "Play", 0, 1);
}

sub DLNARenderer_upnpSyncPlay {
  my ($hash) = @_;
  return DLNARenderer_upnpCallAVTransport($hash, "SyncPlay", 0, 1, "REL_TIME", "", "", "", "PUREDEVICECLOCK1");
}

sub DLNARenderer_upnpCallAVTransport {
  my ($hash, $method, @args) = @_;
  return DLNARenderer_upnpCall($hash, 'AVTransport', $method, @args);
}

sub DLNARenderer_upnpGetMultiChannelSpeaker {
  my ($hash) = @_;
  return DLNARenderer_upnpCallSpeakerManagement($hash, "GetMultiChannelSpeaker");
}

sub DLNARenderer_upnpSetMultiChannelSpeaker {
  my ($hash, @args) = @_;
  return DLNARenderer_upnpCallSpeakerManagement($hash, "SetMultiChannelSpeaker", @args);
}

sub DLNARenderer_upnpCallSpeakerManagement {
  my ($hash, $method, @args) = @_;
  return DLNARenderer_upnpCall($hash, 'SpeakerManagement', $method, @args);
}

sub DLNARenderer_upnpAddUnitToSession {
  my ($hash, $session, $uuid) = @_;
  return DLNARenderer_upnpCallSessionManagement($hash, "AddUnitToSession", $session, $uuid);
}

sub DLNARenderer_upnpRemoveUnitFromSession {
  my ($hash, $session, $uuid) = @_;
  return DLNARenderer_upnpCallSessionManagement($hash, "RemoveUnitFromSession", $session, $uuid);
}

sub DLNARenderer_upnpDestroySession {
  my ($hash, $session) = @_;
  return DLNARenderer_upnpCallSessionManagement($hash, "DestroySession", $session);
}

sub DLNARenderer_upnpCreateSession {
  my ($hash, $name) = @_;
  return DLNARenderer_upnpCallSessionManagement($hash, "CreateSession", $name);
}

sub DLNARenderer_upnpGetSession {
  my ($hash) = @_;
  return DLNARenderer_upnpCallSessionManagement($hash, "GetSession");
}

sub DLNARenderer_upnpAddToGroup {
  my ($hash, $unit, $name) = @_;
  return DLNARenderer_upnpCallSpeakerManagement($hash, "AddToGroup", $unit, $name, "");
}

sub DLNARenderer_upnpRemoveFromGroup {
  my ($hash, $unit) = @_;
  return DLNARenderer_upnpCallSpeakerManagement($hash, "RemoveFromGroup", $unit);
}

sub DLNARenderer_upnpCallSessionManagement {
  my ($hash, $method, @args) = @_;
  return DLNARenderer_upnpCall($hash, 'SessionManagement', $method, @args);
}

sub DLNARenderer_upnpSetVolume {
  my ($hash, $targetVolume) = @_;
  return DLNARenderer_upnpCallRenderingControl($hash, "SetVolume", 0, "Master", $targetVolume);
}

sub DLNARenderer_upnpSetMute {
  my ($hash, $muteState) = @_;
  return DLNARenderer_upnpCallRenderingControl($hash, "SetMute", 0, "Master", $muteState);
}

sub DLNARenderer_upnpCallRenderingControl {
  my ($hash, $method, @args) = @_;
  return DLNARenderer_upnpCall($hash, 'RenderingControl', $method, @args);
}

sub DLNARenderer_upnpCall {
  my ($hash, $service, $method, @args) = @_;
  my $upnpService = DLNARenderer_upnpGetService($hash, $service);
  my $ret = undef;
  my $i = 0;
  
  do {
    eval {
      my $upnpServiceCtrlProxy = $upnpService->controlProxy();
      my $methodExists = $upnpService->getAction($method);
      if($methodExists) {
        $ret = $upnpServiceCtrlProxy->$method(@args);
        Log3 $hash, 5, "DLNARenderer: $service, $method(".join(",",@args).") succeed.";
      } else {
        Log3 $hash, 4, "DLNARenderer: $service, $method(".join(",",@args).") does not exist.";
      }
    };

    if($@) {
      Log3 $hash, 3, "DLNARenderer: $service, $method(".join(",",@args).") failed, $@";
    }
    $i = $i+1;
  } while(!defined($ret) && $i < 3);
  
  return $ret;
}

sub DLNARenderer_upnpGetService {
  my ($hash, $service) = @_;
  my $upnpService;
  
  foreach my $srvc ($hash->{helper}{device}->services) {
    my @srvcParts = split(":", $srvc->serviceType);
    my $serviceName = $srvcParts[-2];
    if($serviceName eq $service) {
      Log3 $hash, 5, "DLNARenderer: $service: ".$srvc->serviceType." found. OK.";
      $upnpService = $srvc;
    }
  }
  
  if(!defined($upnpService)) {
    Log3 $hash, 4, "DLNARenderer: $service unknown for $hash->{NAME}.";
    return undef;
  }
  
  return $upnpService;
}
  

##############################
####### EVENT HANDLING #######
##############################
sub DLNARenderer_processEventXml {
  my ($hash, $property, $xml) = @_;

  Log3 $hash, 4, "DLNARenderer: ".Dumper($xml);
  
  if($property eq "LastChange") {
    return undef if($xml eq "");
  
    if($xml->{Event}) {
      if (index($xml->{Event}{xmlns},"urn:schemas-upnp-org:metadata-1-0/AVT")==0) {
        #process AV Transport
        my $e = $xml->{Event}{InstanceID};
        #DLNARenderer_updateReadingByEvent($hash, "NumberOfTracks", $e->{NumberOfTracks});
        DLNARenderer_updateReadingByEvent($hash, "transportState", $e->{TransportState});
        DLNARenderer_updateReadingByEvent($hash, "transportStatus", $e->{TransportStatus});
        #DLNARenderer_updateReadingByEvent($hash, "TransportPlaySpeed", $e->{TransportPlaySpeed});
        #DLNARenderer_updateReadingByEvent($hash, "PlaybackStorageMedium", $e->{PlaybackStorageMedium});
        #DLNARenderer_updateReadingByEvent($hash, "RecordStorageMedium", $e->{RecordStorageMedium});
        #DLNARenderer_updateReadingByEvent($hash, "RecordMediumWriteStatus", $e->{RecordMediumWriteStatus});
        #DLNARenderer_updateReadingByEvent($hash, "CurrentRecordQualityMode", $e->{CurrentRecordQualityMode});
        #DLNARenderer_updateReadingByEvent($hash, "PossibleRecordQualityMode", $e->{PossibleRecordQualityMode});
        DLNARenderer_updateReadingByEvent($hash, "currentTrackURI", $e->{CurrentTrackURI});
        #DLNARenderer_updateReadingByEvent($hash, "AVTransportURI", $e->{AVTransportURI});
        DLNARenderer_updateReadingByEvent($hash, "nextAVTransportURI", $e->{NextAVTransportURI});
        #DLNARenderer_updateReadingByEvent($hash, "RelativeTimePosition", $e->{RelativeTimePosition});
        #DLNARenderer_updateReadingByEvent($hash, "AbsoluteTimePosition", $e->{AbsoluteTimePosition});
        #DLNARenderer_updateReadingByEvent($hash, "RelativeCounterPosition", $e->{RelativeCounterPosition});
        #DLNARenderer_updateReadingByEvent($hash, "AbsoluteCounterPosition", $e->{AbsoluteCounterPosition});
        #DLNARenderer_updateReadingByEvent($hash, "CurrentTrack", $e->{CurrentTrack});
        #DLNARenderer_updateReadingByEvent($hash, "CurrentMediaDuration", $e->{CurrentMediaDuration});
        #DLNARenderer_updateReadingByEvent($hash, "CurrentTrackDuration", $e->{CurrentTrackDuration});
        #DLNARenderer_updateReadingByEvent($hash, "CurrentPlayMode", $e->{CurrentPlayMode});
        #handle metadata
        #DLNARenderer_updateReadingByEvent($hash, "AVTransportURIMetaData", $e->{AVTransportURIMetaData});
        #DLNARenderer_updateMetaData($hash, "current", $e->{AVTransportURIMetaData});
        #DLNARenderer_updateReadingByEvent($hash, "NextAVTransportURIMetaData", $e->{NextAVTransportURIMetaData});
        DLNARenderer_updateMetaData($hash, "next", $e->{NextAVTransportURIMetaData});
        #use only CurrentTrackMetaData instead of AVTransportURIMetaData
        #DLNARenderer_updateReadingByEvent($hash, "CurrentTrackMetaData", $e->{CurrentTrackMetaData});
        DLNARenderer_updateMetaData($hash, "current", $e->{CurrentTrackMetaData});
        
        #update state
        my $transportState = ReadingsVal($hash->{NAME}, "transportState", "");
        if(ReadingsVal($hash->{NAME}, "presence", "") ne "offline") {
          if($transportState eq "PAUSED_PLAYBACK") {
              readingsSingleUpdate($hash, "state", "paused", 1);
          } elsif($transportState eq "PLAYING") {
              readingsSingleUpdate($hash, "state", "playing", 1);
          } elsif($transportState eq "TRANSITIONING") {
              readingsSingleUpdate($hash, "state", "buffering", 1);
          } elsif($transportState eq "STOPPED") {
              readingsSingleUpdate($hash, "state", "stopped", 1);
          } elsif($transportState eq "NO_MEDIA_PRESENT") {
              readingsSingleUpdate($hash, "state", "online", 1);
          }
        }
      } elsif (index($xml->{Event}{xmlns},"urn:schemas-upnp-org:metadata-1-0/RCS")==0) {
        #process RenderingControl
        my $e = $xml->{Event}{InstanceID};
        DLNARenderer_updateVolumeByEvent($hash, "mute", $e->{Mute});
        DLNARenderer_updateVolumeByEvent($hash, "volume", $e->{Volume});
        readingsSingleUpdate($hash, "multiRoomVolume", ReadingsVal($hash->{NAME}, "volume", 0), 1);
      } elsif ($xml->{Event}{xmlns} eq "FIXME SpeakerManagement") {
        #process SpeakerManagement
      }
    }
  } elsif($property eq "Groups") {
    #handle BTCaskeid
    my $btCaskeidState = 0;
    foreach my $group (@{$xml->{groups}{group}}) {
      #"4DAA44C0-8291-11E3-BAA7-0800200C9A66", "Bluetooth"
      if($group->{id} eq "4DAA44C0-8291-11E3-BAA7-0800200C9A66") {
        $btCaskeidState = 1;
      }
    }
    #TODO update only if changed
    readingsSingleUpdate($hash, "btCaskeid", $btCaskeidState, 1);
  } elsif($property eq "SessionID") {
    #TODO search for other speakers with same sessionId and add them to multiRoomUnits
    readingsSingleUpdate($hash, "sessionId", $xml, 1);
  }
  
  return undef;
}

sub DLNARenderer_updateReadingByEvent {
  my ($hash, $readingName, $xmlEvent) = @_;
  
  my $currVal = ReadingsVal($hash->{NAME}, $readingName, "");
  
  if($xmlEvent) {
    Log3 $hash, 4, "DLNARenderer: Update reading $readingName with ".$xmlEvent->{val};
    my $val = $xmlEvent->{val};
    $val = "" if(ref $val eq ref {});
    if($val ne $currVal) {
      readingsSingleUpdate($hash, $readingName, $val, 1);
    }
  }
  
  return undef;
}

sub DLNARenderer_updateVolumeByEvent {
  my ($hash, $readingName, $volume) = @_;
  my $balance = 0;
  my $balanceSupport = 0;
  
  foreach my $vol (@{$volume}) {
    my $channel = $vol->{Channel} ? $vol->{Channel} : $vol->{channel};
    if($channel) {
      if($channel eq "Master") {
        DLNARenderer_updateReadingByEvent($hash, $readingName, $vol);
      } elsif($channel eq "LF") {
        $balance -= $vol->{val};
        $balanceSupport = 1;
      } elsif($channel eq "RF") {
        $balance += $vol->{val};
        $balanceSupport = 1;
      }
    } else {
      DLNARenderer_updateReadingByEvent($hash, $readingName, $vol);
    }
  }
  
  if($readingName eq "volume" && $balanceSupport == 1) {
    readingsSingleUpdate($hash, "balance", $balance, 1);
  }
  
  return undef;
}

sub DLNARenderer_updateMetaData {
  my ($hash, $prefix, $metaData) = @_;
  my $metaDataAvailable = 0;

  $metaDataAvailable = 1 if(defined($metaData) && $metaData->{val} && $metaData->{val} ne "");
  
  if($metaDataAvailable) {
    my $xml;
    if($metaData->{val} eq "NOT_IMPLEMENTED") {
      readingsSingleUpdate($hash, $prefix."Title", "", 1);
      readingsSingleUpdate($hash, $prefix."Artist", "", 1);
      readingsSingleUpdate($hash, $prefix."Album", "", 1);
      readingsSingleUpdate($hash, $prefix."AlbumArtist", "", 1);
      readingsSingleUpdate($hash, $prefix."AlbumArtURI", "", 1);
      readingsSingleUpdate($hash, $prefix."OriginalTrackNumber", "", 1);
      readingsSingleUpdate($hash, $prefix."Duration", "", 1);
    } else {
      eval {
        $xml = XMLin($metaData->{val}, KeepRoot => 1, ForceArray => [], KeyAttr => []);
        Log3 $hash, 4, "DLNARenderer: MetaData: ".Dumper($xml);
      };

      if(!$@) {
        DLNARenderer_updateMetaDataItemPart($hash, $prefix."Title", $xml->{"DIDL-Lite"}{item}{"dc:title"});
        DLNARenderer_updateMetaDataItemPart($hash, $prefix."Artist", $xml->{"DIDL-Lite"}{item}{"dc:creator"});
        DLNARenderer_updateMetaDataItemPart($hash, $prefix."Album", $xml->{"DIDL-Lite"}{item}{"upnp:album"});
        DLNARenderer_updateMetaDataItemPart($hash, $prefix."AlbumArtist", $xml->{"DIDL-Lite"}{item}{"r:albumArtist"});
        if($xml->{"DIDL-Lite"}{item}{"upnp:albumArtURI"}) {
          DLNARenderer_updateMetaDataItemPart($hash, $prefix."AlbumArtURI", $xml->{"DIDL-Lite"}{item}{"upnp:albumArtURI"});
        } else {
          readingsSingleUpdate($hash, $prefix."AlbumArtURI", "", 1);
        }
        DLNARenderer_updateMetaDataItemPart($hash, $prefix."OriginalTrackNumber", $xml->{"DIDL-Lite"}{item}{"upnp:originalTrackNumber"});
        if($xml->{"DIDL-Lite"}{item}{res}) {
          DLNARenderer_updateMetaDataItemPart($hash, $prefix."Duration", $xml->{"DIDL-Lite"}{item}{res}{duration});
        } else {
          readingsSingleUpdate($hash, $prefix."Duration", "", 1);
        }
      } else {
        Log3 $hash, 1, "DLNARenderer: XML parsing error: ".$@;
      }
    }
  }

  return undef;
}

sub DLNARenderer_updateMetaDataItemPart {
  my ($hash, $readingName, $item) = @_;

  my $currVal = ReadingsVal($hash->{NAME}, $readingName, "");
  if($item) {
    $item = "" if(ref $item eq ref {});
    if($currVal ne $item) {
      readingsSingleUpdate($hash, $readingName, $item, 1);
    }
  }
  
  return undef;
}

##############################
####### DISCOVERY ############
##############################
sub DLNARenderer_setupControlpoint {
  my ($hash) = @_;
  my $error;
  my $cp;
  my @usedonlyIPs = split(/,/, AttrVal($hash->{NAME}, 'usedonlyIPs', ''));
  my @ignoredIPs = split(/,/, AttrVal($hash->{NAME}, 'ignoredIPs', ''));
  
  do {
    eval {
      $cp = UPnP::ControlPoint->new(SearchPort => 0, SubscriptionPort => 0, MaxWait => 30, UsedOnlyIP => \@usedonlyIPs, IgnoreIP => \@ignoredIPs, LogLevel => AttrVal($hash->{NAME}, 'verbose', 0));
      $hash->{helper}{controlpoint} = $cp;
      
      DLNARenderer_addSocketsToMainloop($hash);
    };
    $error = $@;
  } while($error);
  
  return undef;
}

sub DLNARenderer_startDlnaRendererSearch {
  my ($hash) = @_;

  eval {
    $hash->{helper}{controlpoint}->searchByType('urn:schemas-upnp-org:device:MediaRenderer:1', sub { DLNARenderer_discoverCallback($hash, @_); });
  };
  if($@) {
    Log3 $hash, 2, "DLNARenderer: Search failed with error $@";
  }
  return undef;
}

sub DLNARenderer_discoverCallback {
  my ($hash, $search, $device, $action) = @_;
  
  Log3 $hash, 4, "DLNARenderer: $action, ".$device->friendlyName();

  if($action eq "deviceAdded") {
    DLNARenderer_addedDevice($hash, $device);
  } elsif($action eq "deviceRemoved") {
    DLNARenderer_removedDevice($hash, $device);
  }
  return undef;
}

sub DLNARenderer_subscriptionCallback {
  my ($hash, $service, %properties) = @_;
  
  Log3 $hash, 4, "DLNARenderer: Received event: ".Dumper(%properties);
  
  foreach my $property (keys %properties) {
    
    $properties{$property} = decode_entities($properties{$property});
    
    my $xml;
    eval {
      if($properties{$property} =~ /xml/) {
        $xml = XMLin($properties{$property}, KeepRoot => 1, ForceArray => [qw(Volume Mute Loudness VolumeDB group)], KeyAttr => []);
      } else {
        $xml = $properties{$property};
      }
    };
    
    if($@) {
      Log3 $hash, 2, "DLNARenderer: XML formatting error: ".$@.", ".$properties{$property};
      next;
    }
    
    DLNARenderer_processEventXml($hash, $property, $xml);
  }
  
  return undef;
}

sub DLNARenderer_renewSubscriptions {
  my ($hash) = @_;
  my $dev = $hash->{helper}{device};
  
  InternalTimer(gettimeofday() + 200, 'DLNARenderer_renewSubscriptions', $hash, 0);
  
  return undef if(!defined($dev));
  
  BlockingCall('DLNARenderer_renewSubscriptionBlocking', $hash->{NAME});
  
  return undef;
}

sub DLNARenderer_renewSubscriptionBlocking {
  my ($string) = @_;
  my ($name) = split("\\|", $string);
  my $hash = $main::defs{$name};

  $SIG{__WARN__} = sub {
    my ($called_from) = caller(0);
    my $wrn_text = shift;
    Log3 $hash, 5, "DLNARenderer: ".$called_from.", ".$wrn_text;
  };
  
  #register callbacks
  #urn:upnp-org:serviceId:AVTransport
  eval {
    if(defined($hash->{helper}{avTransportSubscription})) {
      $hash->{helper}{avTransportSubscription}->renew();
    }
  };
  
  #urn:upnp-org:serviceId:RenderingControl
  eval {
    if(defined($hash->{helper}{renderingControlSubscription})) {
      $hash->{helper}{renderingControlSubscription}->renew();
    }
  };
  
  #urn:pure-com:serviceId:SpeakerManagement
  eval {
    if(defined($hash->{helper}{speakerManagementSubscription})) {
      $hash->{helper}{speakerManagementSubscription}->renew();
    }
  };
}

sub DLNARenderer_addedDevice {
  my ($hash, $dev) = @_;
  
  my $udn = $dev->UDN();

  #TODO check for BOSE UDN

  #ignoreUDNs
  return undef if(AttrVal($hash->{NAME}, "ignoreUDNs", "") =~ /$udn/);

  #acceptedUDNs
  my $acceptedUDNs = AttrVal($hash->{NAME}, "acceptedUDNs", "");
  return undef if($acceptedUDNs ne "" && $acceptedUDNs !~ /$udn/);
    
  my $foundDevice = 0;
  my @allDLNARenderers = DLNARenderer_getAllDLNARenderers($hash);
  foreach my $DLNARendererHash (@allDLNARenderers) {
    if($DLNARendererHash->{UDN} eq $dev->UDN()) {
      $foundDevice = 1;
    }
  }

  if(!$foundDevice) {
    my $uniqueDeviceName = "DLNA_".substr($dev->UDN(),29,12);
    if(length($uniqueDeviceName) < 17) {
      $uniqueDeviceName = "DLNA_".substr($dev->UDN(),5);
      $uniqueDeviceName =~ tr/-/_/;
    }
    CommandDefine(undef, "$uniqueDeviceName DLNARenderer ".$dev->UDN());
    CommandAttr(undef,"$uniqueDeviceName alias ".$dev->friendlyName());
    CommandAttr(undef,"$uniqueDeviceName webCmd volume");
    if(AttrVal($hash->{NAME}, "defaultRoom", "") ne "") {
      CommandAttr(undef,"$uniqueDeviceName room ".AttrVal($hash->{NAME}, "defaultRoom", ""));
    }
    Log3 $hash, 3, "DLNARenderer: Created device $uniqueDeviceName for ".$dev->friendlyName();
    
    #update list
    @allDLNARenderers = DLNARenderer_getAllDLNARenderers($hash);
  }
  
  foreach my $DLNARendererHash (@allDLNARenderers) {
    if($DLNARendererHash->{UDN} eq $dev->UDN()) {
      #device found, update data
      $DLNARendererHash->{helper}{device} = $dev;
      
      #update device information (FIXME only on change)
      readingsSingleUpdate($DLNARendererHash, "friendlyName", $dev->friendlyName(), 1);
      readingsSingleUpdate($DLNARendererHash, "manufacturer", $dev->manufacturer(), 1);
      readingsSingleUpdate($DLNARendererHash, "modelDescription", $dev->modelDescription(), 1);
      readingsSingleUpdate($DLNARendererHash, "modelName", $dev->modelName(), 1);
      readingsSingleUpdate($DLNARendererHash, "modelNumber", $dev->modelNumber(), 1);
      readingsSingleUpdate($DLNARendererHash, "modelURL", $dev->modelURL(), 1);
      readingsSingleUpdate($DLNARendererHash, "manufacturerURL", $dev->manufacturerURL(), 1);
      readingsSingleUpdate($DLNARendererHash, "presentationURL", $dev->presentationURL(), 1);
      readingsSingleUpdate($DLNARendererHash, "manufacturer", $dev->manufacturer(), 1);
      
      #register callbacks
      #urn:upnp-org:serviceId:AVTransport
      if(DLNARenderer_upnpGetService($DLNARendererHash, "AVTransport")) {
        $DLNARendererHash->{helper}{avTransportSubscription} = DLNARenderer_upnpGetService($DLNARendererHash, "AVTransport")->subscribe(sub { DLNARenderer_subscriptionCallback($DLNARendererHash, @_); }, 1);
      }
      #urn:upnp-org:serviceId:RenderingControl
      if(DLNARenderer_upnpGetService($DLNARendererHash, "RenderingControl")) {
        $DLNARendererHash->{helper}{renderingControlSubscription} = DLNARenderer_upnpGetService($DLNARendererHash, "RenderingControl")->subscribe(sub { DLNARenderer_subscriptionCallback($DLNARendererHash, @_); }, 1);
      }
      #urn:pure-com:serviceId:SpeakerManagement
      if(DLNARenderer_upnpGetService($DLNARendererHash, "SpeakerManagement")) {
        $DLNARendererHash->{helper}{speakerManagementSubscription} = DLNARenderer_upnpGetService($DLNARendererHash, "SpeakerManagement")->subscribe(sub { DLNARenderer_subscriptionCallback($DLNARendererHash, @_); }, 1);
      }
      
      #set online
      readingsSingleUpdate($DLNARendererHash,"presence","online",1);
      if(ReadingsVal($DLNARendererHash->{NAME}, "state", "") eq "offline") {
        readingsSingleUpdate($DLNARendererHash,"state","online",1);
      }
      
      #check caskeid
      if(DLNARenderer_upnpGetService($DLNARendererHash, "SessionManagement")) {
        $DLNARendererHash->{helper}{caskeid} = 1;
        readingsSingleUpdate($DLNARendererHash,"multiRoomSupport","1",1);
      } else {
        readingsSingleUpdate($DLNARendererHash,"multiRoomSupport","0",1);
      }
      
      #update list of caskeid clients
      my @caskeidClients = DLNARenderer_getAllDLNARenderersWithCaskeid($hash);
      $DLNARendererHash->{helper}{caskeidClients} = "";
      foreach my $client (@caskeidClients) {
        #do not add myself
        if($client->{UDN} ne $DLNARendererHash->{UDN}) {
          $DLNARendererHash->{helper}{caskeidClients} .= ",".ReadingsVal($client->{NAME}, "friendlyName", "");
        }
      }
      $DLNARendererHash->{helper}{caskeidClients} = substr($DLNARendererHash->{helper}{caskeidClients}, 1) if($DLNARendererHash->{helper}{caskeidClients} ne "");

      InternalTimer(gettimeofday() + 200, 'DLNARenderer_renewSubscriptions', $DLNARendererHash, 0);
      InternalTimer(gettimeofday() + 60, 'DLNARenderer_updateStereoMode', $DLNARendererHash, 0);
    }
  }
  
  return undef;
}

sub DLNARenderer_removedDevice($$) {
  my ($hash, $device) = @_;
  my $deviceHash = DLNARenderer_getHashByUDN($hash, $device->UDN());
  return undef if(!defined($deviceHash));
  
  readingsSingleUpdate($deviceHash, "presence", "offline", 1);
  readingsSingleUpdate($deviceHash, "state", "offline", 1);

  RemoveInternalTimer($deviceHash, 'DLNARenderer_renewSubscriptions');
  RemoveInternalTimer($deviceHash, 'DLNARenderer_updateStereoMode');
}

###############################
##### GET PLAYER FUNCTIONS ####
###############################
sub DLNARenderer_getMainDLNARenderer($) {
  my ($hash) = @_;
    
  foreach my $fhem_dev (sort keys %main::defs) {
    return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'DLNARenderer' && $main::defs{$fhem_dev}{UDN} eq "0");
  }
		
  return undef;
}

sub DLNARenderer_getHashByUDN($$) {
  my ($hash, $udn) = @_;
  
  foreach my $fhem_dev (sort keys %main::defs) {
    return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'DLNARenderer' && $main::defs{$fhem_dev}{UDN} eq $udn);
  }
		
  return undef;
}

sub DLNARenderer_getHashByFriendlyName {
  my ($hash, $friendlyName) = @_;
  
  foreach my $fhem_dev (sort keys %main::defs) {
    my $devHash = $main::defs{$fhem_dev};
    return $devHash if($devHash->{TYPE} eq 'DLNARenderer' && ReadingsVal($devHash->{NAME}, "friendlyName", "") eq $friendlyName);
  }
		
  return undef;
}

sub DLNARenderer_getAllDLNARenderers($) {
  my ($hash) = @_;
  my @DLNARenderers = ();
    
  foreach my $fhem_dev (sort keys %main::defs) {
    push @DLNARenderers, $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'DLNARenderer' && $main::defs{$fhem_dev}{UDN} ne "0" && $main::defs{$fhem_dev}{UDN} ne "-1");
  }
		
  return @DLNARenderers;
}

sub DLNARenderer_getAllDLNARenderersWithCaskeid($) {
  my ($hash) = @_;
  my @caskeidClients = ();
  
  my @DLNARenderers = DLNARenderer_getAllDLNARenderers($hash);
  foreach my $DLNARenderer (@DLNARenderers) {
    push @caskeidClients, $DLNARenderer if($DLNARenderer->{helper}{caskeid});
  }
  
  return @caskeidClients;
}

###############################
###### UTILITY FUNCTIONS ######
###############################
sub DLNARenderer_generateDidlLiteAndPlay {
  my ($hash, $stream) = @_;
  BlockingCall('DLNARenderer_generateDidlLiteBlocking', $hash->{NAME}."|".$stream, 'DLNARenderer_generateDidlLiteBlockingFinished');
  return undef;
}

sub DLNARenderer_generateDidlLiteBlockingFinished {
  my ($string) = @_;
  
  return unless (defined($string));
  
  my ($name, $stream, $meta) = split("\\|",$string);
  my $hash = $defs{$name};
  
  DLNARenderer_upnpSetAVTransportURI($hash, $stream, $meta);
  DLNARenderer_play($hash);
  readingsSingleUpdate($hash, "stream", $stream, 1);
}

sub DLNARenderer_generateDidlLiteBlocking {
  my ($string) = @_;
  my ($name, $stream) = split("\\|", $string);
  my $hash = $main::defs{$name};
  my $ret = $name."|".$stream;
  
  if(index($stream, "http:") != 0) {
    return $ret;
  }
  
  my $ua = new LWP::UserAgent(agent => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:40.0) Gecko/20100101 Firefox/40.1');
  $ua->max_size(0);
  my $resp = $ua->get($stream);

  my $didl_header = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/" xmlns:sec="http://www.sec.co.kr/"><item id="-1" parentID="parent" restricted="1">';
  my $didl_footer = '</item></DIDL-Lite>';

  $stream = encode_entities($stream);

  my $size = "";
  my $protocolInfo = "";
  my $album = $stream;
  my $title = $stream;
  my $meta = "";

  if (defined($resp->header('content-length'))) {
    $size = ' size="'.$resp->header('content-length').'"';
  }

  my @header = split /;/, $resp->header('content-type');
  my $contenttype = $header[0];

  if (defined($resp->header('contentfeatures.dlna.org'))) {
    $protocolInfo = "http-get:*:".$contenttype.":".$resp->header('contentfeatures.dlna.org');
  } else {
    $protocolInfo = "http-get:*:".$contenttype.":DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000";
  }

  if (defined($resp->header('icy-name'))) {
    $album = encode_entities($resp->header('icy-name'));
  }

  if (defined($resp->header('icy-genre'))) {
    $title = encode_entities($resp->header('icy-genre'));
  }

  if (substr($contenttype,0,5) eq "audio" or $contenttype eq "application/ogg") {
    $meta = $didl_header.'<upnp:class>object.item.audioItem.musicTrack</upnp:class><dc:title>'.$title.'</dc:title><upnp:album>'.$album.'</upnp:album><res protocolInfo="'.$protocolInfo.'"'.$size.'>'.$stream.'</res>'.$didl_footer;
  } elsif (substr($contenttype,0,5) eq "video") {
    $meta = $didl_header.'<upnp:class>object.item.videoItem</upnp:class><dc:title>'.$title.'</dc:title><upnp:album>'.$album.'</upnp:album><res protocolInfo="'.$protocolInfo.'"'.$size.'>'.$stream.'</res>'.$didl_footer;
  } else {
    $meta = "";
  }
  $ret .= "|".$meta;

  return $ret;
}

sub DLNARenderer_newChash($$$) {
  my ($hash,$socket,$chash) = @_;

  $chash->{TYPE}  = $hash->{TYPE};
  $chash->{UDN}   = -1;

  $chash->{NR}    = $devcount++;

  $chash->{phash} = $hash;
  $chash->{PNAME} = $hash->{NAME};

  $chash->{CD}    = $socket;
  $chash->{FD}    = $socket->fileno();

  $chash->{PORT}  = $socket->sockport if( $socket->sockport );

  $chash->{TEMPORARY} = 1;
  $attr{$chash->{NAME}}{room} = 'hidden';

  $defs{$chash->{NAME}}       = $chash;
  $selectlist{$chash->{NAME}} = $chash;
}

sub DLNARenderer_closeSocket($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);

  close($hash->{CD});
  delete($hash->{CD});
  delete($selectlist{$name});
  delete($hash->{FD});
}

sub DLNARenderer_addSocketsToMainloop {
  my ($hash) = @_;
  
  my @sockets = $hash->{helper}{controlpoint}->sockets();
  
  #check if new sockets need to be added to mainloop
  foreach my $s (@sockets) {
    #create chash and add to selectlist
    my $chash = DLNARenderer_newChash($hash, $s, {NAME => "DLNASocket-".$hash->{NAME}."-".$s->fileno()});
  }
  
  return undef;
}


1;

=pod
=item device
=item summary Autodiscover and control your DLNA renderer devices easily
=item summary_DE Autodiscover und einfache Steuerung deiner DLNA Renderer Geräte
=begin html

<a name="DLNARenderer"></a>
<h3>DLNARenderer</h3>
<ul>

  DLNARenderer automatically discovers all your MediaRenderer devices in your local network and allows you to fully control them.<br>
  It also supports multiroom audio for Caskeid and Bluetooth Caskeid speakers (e.g. MUNET).<br><br>
        <b>Note:</b> The followig libraries are required for this module:
		<ul><li>SOAP::Lite</li> <li>LWP::Simple</li> <li>XML::Simple</li> <li>XML::Parser::Lite</li> <li>LWP::UserAgent</li><br>
		</ul>

  <a name="DLNARendererdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DLNARenderer</code>
    <br><br>

    Example:
    <ul>
      <code>define dlnadevices DLNARenderer</code><br>
      After about 2 minutes you can find all automatically created DLNA devices under "Unsorted".<br/>
    </ul>
  </ul>
  <br>

  <a name="DLNARendererset"></a>
  <b>Set</b>
  <ul>
    <br><code>set &lt;name&gt; stream &lt;value&gt</code><br>
    Set any URL to play.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; on</code><br>
    Starts playing the last stream (reading stream).
  </ul>
  <ul>
    <br><code>set &lt;name&gt; off</code><br>
    Sends stop command to device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; stop</code><br>
    Stop playback.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; volume 0-100</code><br>
    <code>set &lt;name&gt; volume +/-0-100</code><br>
    Set volume of the device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; channel 1-10</code><br>
    Start playing channel X which must be configured as channel_X attribute first.<br>
    You can specify your channel also in DIDL-Lite XML format if your player doesn't support plain URIs.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; mute on/off</code><br>
    Mute the device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; pause</code><br>
    Pause playback of the device. No toggle.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; pauseToggle</code><br>
    Toggle pause/play for the device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; play</code><br>
    Initiate play command. Only makes your player play if a stream was loaded (currentTrackURI is set).
  </ul>
  <ul>
    <br><code>set &lt;name&gt; next</code><br>
    Play next track.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; previous</code><br>
    Play previous track.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; seek &lt;seconds&gt;</code><br>
    Seek to position of track in seconds.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; speak "This is a test. 1 2 3."</code><br>
    Speak the text followed after speak within quotes. Works with Google Translate.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; playEverywhere</code><br>
    Only available for Caskeid players.<br>
    Play current track on all available Caskeid players in sync.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; stopPlayEverywhere</code><br>
    Only available for Caskeid players.<br>
    Stops multiroom audio.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; addUnit &lt;unitName&gt;</code><br>
    Only available for Caskeid players.<br>
    Adds unit to multiroom audio session.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; removeUnit &lt;unitName&gt;</code><br>
    Only available for Caskeid players.<br>
    Removes unit from multiroom audio session.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; multiRoomVolume 0-100</code><br>
    <code>set &lt;name&gt; multiRoomVolume +/-0-100</code><br>
    Only available for Caskeid players.<br>
    Set volume of all devices within this session.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; enableBTCaskeid</code><br>
    Only available for Caskeid players.<br>
    Activates Bluetooth Caskeid for this device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; disableBTCaskeid</code><br>
    Only available for Caskeid players.<br>
    Deactivates Bluetooth Caskeid for this device.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; stereo &lt;left&gt; &lt;right&gt; &lt;pairName&gt;</code><br>
    Only available for Caskeid players.<br>
    Sets stereo mode for left/right speaker and defines the name of the stereo pair.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; standalone</code><br>
    Only available for Caskeid players.<br>
    Puts the speaker into standalone mode if it was member of a stereo pair before.
  </ul>
  <ul>
    <br><code>set &lt;name&gt; saveGroupAs &lt;groupName&gt;</code><br>
    Only available for Caskeid players.<br>
    Saves the current group configuration (e.g. saveGroupAs LivingRoom).
  </ul>
  <ul>
    <br><code>set &lt;name&gt; loadGroup &lt;groupName&gt;</code><br>
    Only available for Caskeid players.<br>
    Loads the configuration previously saved (e.g. loadGroup LivingRoom).
  </ul>
  <br>
  
  <a name="DLNARendererattr"></a>
  <b>Attributes</b>
  <ul>
    <br><code>ignoreUDNs</code><br>
    Define list (comma or blank separated) of UDNs which should prevent automatic device creation.<br>
    It is important that uuid: is also part of the UDN and must be included.
  </ul>

</ul>

=end html
=cut
