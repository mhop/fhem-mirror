##############################################################################
# $Id$
#
#  37_Spotify.pm
#
#  2017 Oskar Neumann
#  oskar.neumann@me.com
#
##############################################################################

package main;

use strict;
use warnings;

use JSON;

use MIME::Base64;
use List::Util qw/shuffle/;

sub Spotify_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = 'Spotify_Define';
    $hash->{NotifyFn} = 'Spotify_Notify';
    $hash->{UndefFn}  = 'Spotify_Undefine';
    $hash->{SetFn}    = 'Spotify_Set';
    $hash->{GetFn}    = 'Spotify_Get';
  #$hash->{AttrFn}   = "Spotify_Attr";
    $hash->{AttrList} = 'defaultPlaybackDeviceID alwaysStartOnDefaultDevice:0,1 updateInterval updateIntervalWhilePlaying disable:0,1 volumeStep ';
    $hash->{AttrList} .= $readingFnAttributes;
    $hash->{NOTIFYDEV} = "global";
}

sub Spotify_Define($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @a = split("[ \t][ \t]*", $def);
    my $hintGetVaildPair = "get a valid pair by creating a Spotify app".
    " here: https://developer.spotify.com/my-applications/#!/applications/create
    (recommendation is to use https://oskar.pw/ as redirect_uri because it displays the temporary access code - ".
    "this is safe because the code is useless without your client credentials and expires after a few minutes)";

    return 'wrong syntax: define <name> Spotify <client_id> <client_secret> [ <redirect_uri> ]
    - '. $hintGetVaildPair
        if( @a < 4 );


    my $client_id = $a[2];
    my $client_secret = $a[3];

    return 'invalid client_id / client_secret - '. $hintGetVaildPair
        if(length $client_id != 32 || length $client_secret != 32);

    $hash->{CLIENT_ID} = $client_id;
    $hash->{CLIENT_SECRET} = $client_secret;
    $hash->{REDIRECT_URI} = @a > 4 ? $a[4] : 'https://oskar.pw/';
    $hash->{helper}{custom_redirect} = @a > 4;

	Spotify_loadInternals($hash) if($init_done);

    return undef;
}

sub Spotify_Undefine($$) {                     
	my ($hash, $name) = @_;               
	RemoveInternalTimer($hash);    
	return undef;                  
}

sub Spotify_Notify($$) {
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash
 
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
		Spotify_loadInternals($own_hash);
	}
}

sub Spotify_Set($$@) {
  my ($hash, $name, $cmd, @args) = @_;

  return "\"set $name\" needs at least one argument" unless(defined($cmd));

  my $list = '';

  if(!defined $hash->{helper}{refresh_token}) {
  	$list .= ' code';
  } else {
  	$list .= ' playTrackByURI playContextByURI pause:noArg resume:noArg volume:slider,0,1,100 update:noArg';
  	$list .= ' skipToNext:noArg skipToPrevious:noArg seekToPosition repeat:one,all,off shuffle:on,off transferPlayback volumeFade:slider,0,1,100 playTrackByName playPlaylistByName togglePlayback';
  	$list .= ' playSavedTracks playRandomTrackFromPlaylistByURI randomPlayPlaylistByURI findTrackByName findArtistByName playArtistByName volumeUp volumeDown';
  }

  if($cmd eq 'code') {
  	return "please enter the code obtained from the URL after calling \"get $name authorizationURL\""
  	  if( @args < 1 );

  	return Spotify_getToken($hash, $args[0]);
  }

  return Spotify_update($hash, 1) if($cmd eq 'update');
  return Spotify_pausePlayback($hash) if($cmd eq 'pause');
  return Spotify_resumePlayback($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'resume');
  return Spotify_setVolume($hash, 1, $args[0], defined $args[1] ? join(' ', @args[1..$#args]) : undef) if ($cmd eq 'volume');
  return Spotify_skipToNext($hash) if ($cmd eq 'skipToNext' || $cmd eq 'skip' || $cmd eq 'next');
  return Spotify_skipToPrevious($hash) if ($cmd eq 'skipToPrevious' || $cmd eq 'previous' || $cmd eq 'prev');
  return Spotify_seekToPosition($hash, $args[0]) if($cmd eq 'seekToPosition');
  return Spotify_setRepeat($hash, $args[0]) if($cmd eq 'repeat');
  return Spotify_setShuffle($hash, $args[0]) if($cmd eq 'shuffle');
  return Spotify_transferPlayback($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'transferPlayback');
  return Spotify_playTrackByURI($hash, \@args, undef) if($cmd eq 'playTrackByURI');
  return Spotify_playTrackByName($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'playTrackByName');
  return Spotify_playPlaylistByName($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'playPlaylistByName');
  return Spotify_playContextByURI($hash, $args[0], $args[1], defined $args[2] ? join(' ', @args[2..$#args]) : undef) if($cmd eq 'playContextByURI');
  return Spotify_volumeFade($hash, $args[0], $args[1], $args[2], defined $args[3] ? join(' ', @args[3..$#args]) : undef) if($cmd eq 'volumeFade');
  return Spotify_volumeFadeStep($hash) if($cmd eq 'volumeFadeStep');
  return Spotify_togglePlayback($hash) if($cmd eq 'toggle' || $cmd eq 'togglePlayback');
  return Spotify_playSavedTracks($hash, $args[0], defined $args[1] ? join(' ', @args[1..$#args]) : undef) if($cmd eq 'playSavedTracks');
  return Spotify_playRandomTrackFromPlaylistByURI($hash, $args[0], $args[1], defined $args[2] ? join(' ', @args[2..$#args]) : undef) if($cmd eq 'playRandomTrackFromPlaylistByURI');
  return Spotify_randomPlayPlaylistByURI($hash, $args[0], $args[1], defined $args[2] ? join(' ', @args[2..$#args]) : undef) if($cmd eq 'randomPlayPlaylistByURI');
  return Spotify_findTrackByName($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'findTrackByName');
  return Spotify_findArtistByName($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'findArtistByName');
  return Spotify_playArtistByName($hash, @args > 0 ? join(' ', @args) : undef) if($cmd eq 'playArtistByName');
  return Spotify_volumeStep($hash, $cmd eq 'volumeDown' ? -1 : 1, $args[0], defined $args[1] ? join(' ', @args[1..$#args]) : undef) if($cmd eq 'volumeUp' || $cmd eq 'volumeDown');

  return "Unknown argument $cmd, choose one of $list";
}

sub Spotify_Get($$@) {
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  if(!defined $hash->{helper}{refresh_token}) {
  	$list .= ' authorizationURL:noArg';
  } else {
  	#$list .= ' me:noArg';
  }

  if($cmd eq "authorizationURL") {
  	return $hash->{AUTHORIZATION_URL};
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub Spotify_loadInternals($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{helper}{authorization_url} = "https://accounts.spotify.com/authorize/?client_id=$hash->{CLIENT_ID}&response_type=code&scope=playlist-read-private%20playlist-read-collaborative%20streaming%20user-library-read%20user-read-private%20user-read-playback-state&redirect_uri=" . urlEncode($hash->{REDIRECT_URI});
	$hash->{helper}{refresh_token} = ReadingsVal($name, '.refresh_token', undef);
	$hash->{helper}{access_token} = ReadingsVal($name, '.access_token', undef);
	$hash->{helper}{expires} = ReadingsVal($name, '.expires', undef);

	RemoveInternalTimer($hash);
	if(!defined(ReadingsVal($name, '.refresh_token', undef))) {
		$hash->{STATE} = 'authorization pending (see instructions)';
    	$hash->{AUTHORIZATION_URL} = $hash->{helper}{authorization_url}; 
    	$hash->{A1_INSTRUCTIONS} = 'Open AUTHORIZATION_URL in your browser and set the code afterwards. Make sure to specify REDIRECT_URI as a redirect_uri in your API application.';
    	$hash->{A1_INSTRUCTIONS} .= ' It is safe to rely on https://oskar.pw/ as redirect_uri because your code is worthless without the client secret and only valid for a few minutes. 
    	However, feel free to specify any other redirect_uri in the definition and extract the code after being redirected yourself.' if(!$hash->{helper}{custom_redirect});
	} else {
		$hash->{STATE} = 'connected';
		my $pollInterval = $attr{$name}{pollInterval};
		$attr{$name}{webCmd} = 'toggle:next:prev:volumeUp:volumeDown' if(!defined $attr{$name}{webCmd});
    	
    	Spotify_poll($hash) if(defined $hash->{helper}{refresh_token} && !Spotify_isDisabled($hash));
	}
}

sub Spotify_getToken($$) { # exchanging code for token
	my ($hash, $code) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 4, "$name: checking access code";
	my ($err,$data) = HttpUtils_BlockingGet({
    	url => "https://accounts.spotify.com/api/token",
    	method => "POST",
    	timeout => 5,
    	noshutdown => 1,
    	data => {client_id => $hash->{CLIENT_ID}, client_secret => $hash->{CLIENT_SECRET}, grant_type => 'authorization_code', redirect_uri => $hash->{REDIRECT_URI}, 'code' => $code}
  	});

  	my $json = eval { JSON->new->utf8(0)->decode($data) };
  	if(defined $json->{error}) {
  		my $msg = 'Failed to get access token: ';

  		if($json->{error_description} =~ /redirect/) {
  			$msg = $msg . 'Please add '. $hash->{REDIRECT_URI} . ' as a redirect_uri at https://developer.spotify.com/my-applications/#!/applications/';
  		} else {
  			$msg = $msg . $json->{error_description};
  		}

  		Log3 $name, 3, "$name: $json->{error} - $msg";
  		return $msg;
  	}

  	return "failed to get access token"
  	  if(!defined $json->{refresh_token});


  	$hash->{helper}{refresh_token} = $json->{refresh_token};
  	$hash->{helper}{access_token} = $json->{access_token};
  	$hash->{helper}{expires} = gettimeofday() + $json->{expires_in};
  	$hash->{helper}{scope} = $json->{scope};
  	delete $hash->{AUTHORIZATION_URL};
  	delete $hash->{A1_INSTRUCTIONS};
  	$hash->{STATE} = "connected";

  	Spotify_writeTokens($hash);
  	RemoveInternalTimer($hash);
  	Spotify_updateMe($hash, 0);
	Spotify_poll($hash);

	return undef;
}

sub Spotify_writeTokens($) { # save gathered tokens
	my ($hash) = @_;

	readingsBeginUpdate($hash);
  	readingsBulkUpdate($hash, '.refresh_token', $hash->{helper}{refresh_token});
  	readingsBulkUpdateIfChanged($hash, '.access_token', $hash->{helper}{access_token});
  	readingsBulkUpdate($hash, '.expires', $hash->{helper}{expires});
  	readingsEndUpdate($hash, 1);
}

sub Spotify_refreshToken($) { # refresh the access token once it is expired
	my ($hash) = @_;
	my $name = $hash->{NAME};

	return 'Failed to refresh access token: refresh token missing' if(!defined $hash->{helper}{refresh_token});

	Log3 $name, 4, "$name: refreshing access code";
	my ($err,$data) = HttpUtils_BlockingGet({
	  	url => "https://accounts.spotify.com/api/token",
	  	method => "POST",
	  	timeout => 5,
	  	noshutdown => 1,
	  	data => {client_id => $hash->{CLIENT_ID}, client_secret => $hash->{CLIENT_SECRET}, grant_type => 'refresh_token', refresh_token => $hash->{helper}{refresh_token}}
	});

	my $json = eval { JSON->new->utf8(0)->decode($data) };
	if(defined $json->{error}) {
		if($json->{error} eq 'invalid_grant') {
	  		$hash->{helper}{refresh_token} = undef;
	  		$hash->{STATE} = 'invalid refresh token';
	  		$hash->{AUTHORIZATION_URL} = $hash->{helper}{authorization_url};
	  		CommandDeleteReading(undef, "$name .*");
		}

		my $msg = 'Failed to refresh access token: $json->{error_description}';
		Log3 $name, 3, "$name: $json->{error} - $msg";
		return $msg;
	}

	return "failed to refresh access token" if(!defined $json->{access_token});

	$hash->{helper}{access_token} = $json->{access_token};
	$hash->{helper}{expires} = gettimeofday() + $json->{expires_in};
	$hash->{helper}{scope} = $json->{scope} if(defined $json->{scope});

	Spotify_writeTokens($hash);

	Spotify_updateMe($hash, 0);
	Spotify_updateDevices($hash, 0);
}

sub Spotify_apiRequest($$$$$) { # any kind of api request
	my ($hash, $path, $args, $method, $blocking) = @_;
	my $name = $hash->{NAME};

	Spotify_refreshToken($hash) if(gettimeofday() >= $hash->{helper}{expires});
	if(!defined $hash->{helper}{refresh_token}) {
		Log3 $name, 3, "$name: could not execute API request (not authorized)";
		return 'You need to be authorized to perform this action.';
	}

	if(!defined $blocking || !$blocking) {
		HttpUtils_NonblockingGet({
			url => "https://api.spotify.com/v1/$path",
	    	method => $method,
	    	hash => $hash,
	    	apiPath => $path,
	    	timeout => 5,
	    	noshutdown => 1,
	    	data => $method eq 'PUT' && defined $args ? encode_json $args : $args,
	    	header => "Authorization: Bearer ". $hash->{helper}{access_token},
	    	callback => \&Spotify_dispatch
	    });
	} else {
		my ($err,$data) = HttpUtils_BlockingGet({
	    	url => "https://api.spotify.com/v1/$path",
	    	method => $method,
	    	hash => $hash,
	    	apiPath => $path,
	    	timeout => 5,
	    	noshutdown => 1,
	    	data => $method eq 'PUT' && defined $args ? encode_json $args : $args,
	    	header => "Authorization: Bearer ". $hash->{helper}{access_token}
	  	});
	  	return Spotify_dispatch({hash => $hash, apiPath => $path, method => $method}, $err, $data);
	}
}

sub Spotify_updateMe($$) { # update user infos
	my ($hash, $blocking) = @_;
	Spotify_apiRequest($hash, 'me/', undef, 'GET', $blocking);
	return undef;
}

sub Spotify_updateDevices($$) { # update devices
	my ($hash, $blocking) = @_;
	Spotify_apiRequest($hash, 'me/player/devices', undef, 'GET', $blocking);
	return undef;
}

sub Spotify_pausePlayback($) { # pause playback
	my ($hash) = @_;
	my $name = $hash->{NAME};
	$hash->{helper}{is_playing} = 0;
	readingsSingleUpdate($hash, 'is_playing', 0, 1);
	Spotify_apiRequest($hash, 'me/player/pause', undef, 'PUT', 0);
	Log3 $name, 4, "$name: pause";
	return undef;
}

sub Spotify_resumePlayback($$) { # resume playback
	my ($hash, $device_id) = @_;
	my $name = $hash->{NAME};
	$device_id = Spotify_getTargetDeviceID($hash, $device_id, 0); # resolve target device id
	$hash->{helper}{is_playing} = 1;
	readingsSingleUpdate($hash, 'is_playing', 1, 1);
	Spotify_apiRequest($hash, 'me/player/play' . (defined $device_id ? "?device_id=$device_id" : ''), undef, 'PUT', 0);
	Log3 $name, 4, "$name: resume";
	return undef;
}

sub Spotify_updatePlaybackStatus($$) { # update the playback status
	my ($hash, $blocking) = @_;
	Spotify_apiRequest($hash, 'me/player', undef, 'GET', $blocking);
	return undef;
}

sub Spotify_setVolume($$$$) { # set the volume
	my ($hash, $blocking, $volume, $device_id) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> volume <percent> [ <device_id / device_name> ]' if(!defined $volume);

	delete $hash->{helper}{fading} if($blocking && defined $hash->{helper}{fading}); # stop volumeFade if currently active (override)

	$device_id = Spotify_getTargetDeviceID($hash, $device_id, 0); # resolve target device id
	Spotify_apiRequest($hash, "me/player/volume?volume_percent=$volume". (defined $device_id ? "&device_id=$device_id" : ''), undef, 'PUT', $blocking);
	Log3 $name, 4, "$name: volume $volume" if(!defined $hash->{helper}{fading});
	return undef;
}

sub Spotify_skipToNext($) { # skip to next track
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Spotify_apiRequest($hash, 'me/player/next', undef, 'POST', 0);
	Log3 $name, 4, "$name: skipToNext";
	return undef;
}

sub Spotify_skipToPrevious($) { # skip to previous track
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Spotify_apiRequest($hash, 'me/player/previous', undef, 'POST', 0);
	Log3 $name, 4, "$name: skipToPrevious";
	return undef;
}

sub Spotify_seekToPosition($$) { # seek to position in track
	my ($hash, $position) = @_;
	my $name = $hash->{NAME};
	my (undef, $minutes, $seconds) = $position =~ m/(([0-9]+):)?([0-9]+)/;
	return 'wrong syntax: set <name> seekToPosition <position_in_s>' if(!defined $minutes && !defined $seconds);
	$position = ($minutes * 60 + $seconds) * 1000;
	Spotify_apiRequest($hash, "me/player/seek?position_ms=$position", undef, 'PUT', 0);
	return undef;
}

sub Spotify_setRepeat($$) { # set the repeat mode
	my ($hash, $mode) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> repeat <one,all,off>' if(!defined $mode || ($mode ne 'one' && $mode ne 'all' && $mode ne 'off'));
	$mode = 'track' if($mode eq 'one');
	$mode = 'context' if($mode eq 'all');
	my $device_id = Spotify_getTargetDeviceID($hash, undef, 0);
	Spotify_apiRequest($hash, "me/player/repeat?state=$mode". (defined $device_id ? "&device_id=$device_id" : ""), undef, 'PUT', 0);
	Log3 $name, 4, "$name: repeat $mode";
	return undef;
}

sub Spotify_setShuffle($$) { # set the shuffle mode
	my ($hash, $mode) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> shuffle <off,on>' if(!defined $mode || ($mode ne 'on' && $mode ne 'off'));
	$mode = $mode eq 'on' ? 'true' : 'false';
	my $device_id = Spotify_getTargetDeviceID($hash, undef, 0);
	Spotify_apiRequest($hash, "me/player/shuffle?state=$mode". (defined $device_id ? "&device_id=$device_id" : ""), undef, 'PUT', 0);
	Log3 $name, 4, "$name: shuffle $mode";
	return undef;
}

sub Spotify_transferPlayback($$) { # transfer the current playback to another device
	my ($hash, $device_id) = @_;
	$device_id = Spotify_getTransferTargetDeviceID($hash, $device_id);
	return 'device not found' if(!defined $device_id);
	my @device_ids = ($device_id);
	Spotify_apiRequest($hash, 'me/player', {device_ids => \@device_ids}, 'PUT', 0);
	return undef;
}

sub Spotify_playContextByURI($$$$) { # play a context (playlist, album or artist) using its uri
    my ($hash, $uri, $position, $device_id) = @_;
    my $name = $hash->{NAME};
    return 'wrong syntax: set <name> playContextByURI <album_uri / playlist_uri> [ <nr_of_first_track> ] [ <device_id> ]' if(!defined $uri);
    $device_id = $position . (defined $device_id ? " ". $device_id : "") if(defined $position && $position !~ /^[0-9]+$/);
    $position = 1 if(!defined $position || $position !~ /^[0-9]+$/);

    return Spotify_play($hash, undef, $uri, $position, $device_id);
}

sub Spotify_playTrackByURI($$$) { # play a track by its uri
    my ($hash, $uris, $device_id) = @_;
    my $name = $hash->{NAME};
    return 'wrong syntax: set <name> playTrackByURI <track_uri> ... [ <device_id> ]' if(@{$uris} < 1);
    Log3 $name, 4, "$name: track". (@{$uris} > 1 ? "s" : "")." ". join(" ", @{$uris}) if(!defined $hash->{helper}{skipTrackLog});
    delete $hash->{helper}{skipTrackLog} if(defined $hash->{helper}{skipTrackLog});
    return Spotify_play($hash, $uris, undef, undef, $device_id);
}

sub Spotify_playTrackByName($$) { # play a track by its name using search
	my ($hash, $trackname) = @_;
	return 'wrong syntax: set <name> playTrackByName <track_name> [ <device_id> ]' if(!defined $trackname);

	my @parts = split(" ", $trackname);
	my $device_id = Spotify_getTargetDeviceID($hash, $parts[-1], 0) if(@parts > 1); # resolve device id (may be last part of the command)
	$trackname = substr($trackname, 0, -length($parts[-1])-1) if(@parts > 1 && defined $device_id); # if last part was indeed the device id, remove it from the track name

	Spotify_findTrackByName($hash, $trackname);
	my $result = $hash->{helper}{searchResult};
	return 'could not find track' if(!defined $result);

	my @uris = ($result->{uri});
	Spotify_playTrackByURI($hash, \@uris, $device_id);
	return undef;
}

sub Spotify_findTrackByName($$) { # finds a track by its name and returns the result in the readings
	my ($hash, $trackname, $saveTrack) = @_;
	return 'wrong syntax: set <name> findTrackByName <track_name> [ <device_id> ]' if(!defined $trackname);

	delete $hash->{helper}{searchResult};
	Spotify_apiRequest($hash, 'search?limit=1&type=track&q='. urlEncode($trackname), undef, 'GET', 1);
	my $result = $hash->{helper}{dispatch}{json}{tracks}{items}[0];
	return 'could not find track' if(!defined $result);

	$hash->{helper}{searchResult} = $result;
	Spotify_saveTrack($hash, $result, 'search_track', 1);

	return undef;
}

sub Spotify_findArtistByName($$) { # finds an artist by its name and returns the result in the readings
	my ($hash, $artistname, $saveTrack) = @_;
	return 'wrong syntax: set <name> findArtistByName <track_name>' if(!defined $artistname);

	delete $hash->{helper}{searchResult};
	Spotify_apiRequest($hash, 'search?limit=1&type=artist&q='. urlEncode($artistname), undef, 'GET', 1);
	my $result = $hash->{helper}{dispatch}{json}{artists}{items}[0];
	return 'could not find artist' if(!defined $result);

	$hash->{helper}{searchResult} = $result;
	Spotify_saveArtist($hash, $result, 'search_artist', 1);

	return undef;
}

sub Spotify_playArtistByName($$) { # play an artist by its name using search
	my ($hash, $artistname) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> playArtistByName <artist_name> [ <device_id> ]' if(!defined $artistname);

	my @parts = split(" ", $artistname);
	my $device_id = Spotify_getTargetDeviceID($hash, $parts[-1], 0) if(@parts > 1); # resolve device id (may be last part of the command)
	$artistname = substr($artistname, 0, -length($parts[-1])-1) if(@parts > 1 && defined $device_id); # if last part was indeed the device id, remove it from the track name

	Spotify_findArtistByName($hash, $artistname);
	my $result = $hash->{helper}{searchResult};
	return 'could not find artist' if(!defined $result);

	Spotify_playContextByURI($hash, $result->{uri}, undef, $device_id);
	Log3 $name, 4, "$name: artist $result->{uri} ($result->{name})";
	return undef;
}

sub Spotify_playPlaylistByName($$) { # play a playlist by its name
	my ($hash, $playlistname) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> playPlaylistByName <playlist_name>' if(!defined $playlistname);

	my @parts = split(" ", $playlistname);
	my $device_id = Spotify_getTargetDeviceID($hash, $parts[-1], 0) if(@parts > 1); # resolve device id (may be last part of the command)
	$playlistname = substr($playlistname, 0, -length($parts[-1])-1) if(@parts > 1 && defined $device_id); # if last part was indeed the device id, remove it from the track name

	Spotify_apiRequest($hash, 'search?limit=1&type=playlist&q='. urlEncode($playlistname), undef, 'GET', 1);
	my $result = $hash->{helper}{dispatch}{json}{playlists}{items}[0];
	return 'could not find playlist' if(!defined $result);

	Spotify_playContextByURI($hash, $result->{uri}, undef, $device_id);
	Log3 $name, 4, "$name: $result->{uri} ($result->{name})";
	return undef;
}

sub Spotify_playSavedTracks($$$) { # play users saved tracks
	my ($hash, $first, $device_id) = @_;
	my $name = $hash->{NAME};

	$device_id = $first . (defined $device_id ? " " . $device_id : "") if(defined $first && $first !~ /^[0-9]+$/);
	$first = 1 if(!defined $first || $first !~ /^[0-9]+$/);

	Spotify_apiRequest($hash, 'me/tracks?limit=50'. ($first > 50 ? '&offset='. int($first/50)-1 : ''), undef, 'GET', 1); # getting saved tracks
	my $result = $hash->{helper}{dispatch}{json}{items};
	return 'could not get saved tracks' if(!defined $result);

	my @uris = map { $_->{track}{uri} } @{$result};
	shift @uris for 1..($first%50-1); # removing first elements users wants to skip
	Spotify_playTrackByURI($hash, \@uris, $device_id); # play them

	Log3 $name, 4, "$name: saved tracks";

	return undef;
}

sub Spotify_playRandomTrackFromPlaylistByURI($$$$) { # select a random track from a given playlist and play it (use case: e.g. alarm clocks)
	my ($hash, $uri, $limit, $device_id) = @_;
	my $name = $hash->{NAME};
	return 'wrong syntax: set <name> playRandomTrackFromPlaylistByURI <playlist_uri> [ <limit> ] [ <device_id> ]' if(!defined $uri);

	my ($user_id, $playlist_id) = $uri =~ m/user:(.*):playlist:(.*)/;
	return 'invalid playlist_uri' if(!defined $user_id || !defined $playlist_id);

	$device_id = $limit . (defined $device_id ? " " . $device_id : "") if(defined $limit && $limit !~ /^[0-9]+$/);
	$limit = undef if($limit !~ /^[0-9]+$/);

	Spotify_apiRequest($hash, "users/$user_id/playlists/$playlist_id/tracks?fields=items(track(name,uri))". (defined $limit ? "&limit=$limit" : ""), undef, 'GET', 1);
	my $result = $hash->{helper}{dispatch}{json}{items};
	return 'could not find playlist' if(!defined $result);

	my @alltracks = map { $_->{track} } @{$result};
	my $selectedTrack = $alltracks[rand @alltracks];
	my @uris = ($selectedTrack->{uri});
	$hash->{helper}{skipTrackLog} = 1;
	Spotify_playTrackByURI($hash, \@uris, $device_id);
	Log3 $name, 4, "$name: random track $selectedTrack->{uri} ($selectedTrack->{name}) from $uri";
	return undef;
}

sub Spotify_randomPlayPlaylistByURI($$$$) { # play the playlist in random order
    my ($hash, $uri, $limit, $device_id) = @_;
    my $name = $hash->{NAME};
    return 'wrong syntax: set <name> randomPlayPlaylistByURI <playlist_uri> [ <limit> ] [ <device_id> ]' if(!defined $uri);

    my ($user_id, $playlist_id) = $uri =~ m/user:(.*):playlist:(.*)/;
    return 'invalid playlist_uri' if(!defined $user_id || !defined $playlist_id);

    $device_id = $limit . (defined $device_id ? " " . $device_id : "") if(defined $limit && $limit !~ /^[0-9]+$/);
    $limit = undef if($limit !~ /^[0-9]+$/);

    Spotify_apiRequest($hash, "users/$user_id/playlists/$playlist_id/tracks?fields=items(track(name,uri))". (defined $limit ? "&limit=$limit" : ""), undef, 'GET', 1);
    my $result = $hash->{helper}{dispatch}{json}{items};
    return 'could not find playlist' if(!defined $result);

    my @uris = map { $_->{track}{uri} } @{$result};
    @uris = shuffle(@uris);
    $hash->{helper}{skipTrackLog} = 1;
    Spotify_playTrackByURI($hash, \@uris, $device_id);
    Log3 $name, 4, "$name: playing $uri in random order";
    return undef;
}

sub Spotify_play($$$$$) { # any play command (colleciton or track)
    my ($hash, $uris, $context_uri, $position, $device_id) = @_;
    my $name = $hash->{NAME};

    my $data = undef;
    if(defined $uris) {
        if(@{$uris} > 1 && @{$uris}[-1] !~ /spotify:/) {
        	$device_id = pop @{$uris};
        }

        $data = {uris => $uris};
    } else {
        $data = {context_uri => $context_uri};
        $data->{offset} = {position => $position-1} if($position > 1);
    }

    $device_id = Spotify_getTargetDeviceID($hash, $device_id, 1);

    Spotify_apiRequest($hash, 'me/player/play'. (defined $device_id ? '?device_id='. $device_id : ''), $data, 'PUT', 1);
    Spotify_updatePlaybackStatus($hash, 1);
    return undef;
}

sub Spotify_volumeFade($$$$$) { # fade the volume of a device
	my ($hash, $targetVolume, $duration, $step, $device_id) = @_;
	return 'wrong syntax: set <name> volumeFade <target_volume> [ <duration_s> <percent_per_step> ] [ <device_id> ]' if(!defined $targetVolume);

	Spotify_updateDevices($hash, 1); # make sure devices are up to date (a valid start volume is required)
	$device_id = $duration . (defined $device_id ? " " . $device_id : "") if(defined $duration && $duration !~ /^[0-9]+$/);
	my $startVolume = $hash->{helper}{device_active}{volume_percent};
	return 'could not get start volume of active device' if(!defined $startVolume);
	$step = 5 if(!defined $step); # fall back to default step if not specified
	$duration = 5 if(!defined $duration || $duration !~ /^[0-9]+$/); # fallback to default value if duration is not specified or valid
	my $delta = abs($targetVolume - $startVolume);
	my $requiredSteps = int($delta/$step);
	return Spotify_setVolume($hash, 0, $targetVolume, $device_id) if($requiredSteps == 0); # no steps required, set volume and exit

	#Log3 "spotify", 3, "fading volume start $startVolume target $targetVolume duration $duration step $step steps $requiredSteps";

	$hash->{helper}{fading}{step} = $step;
	$hash->{helper}{fading}{startVolume} = $startVolume;
	$hash->{helper}{fading}{targetVolume} = $targetVolume;
	$hash->{helper}{fading}{requiredSteps} = $requiredSteps;
	$hash->{helper}{fading}{iteration} = 0;
	$hash->{helper}{fading}{duration} = $duration;
	$hash->{helper}{fading}{device_id} = $device_id;

	Spotify_volumeFadeStep($hash);

	return undef;
}

sub Spotify_togglePlayback($) { # toggle playback (pause if active, resume otherwise)
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "$name: togglePlayback";

	if($hash->{helper}{is_playing}) {
		Spotify_pausePlayback($hash);
	} else {
		Spotify_resumePlayback($hash, undef);
	}

	return undef;
}

sub Spotify_volumeStep($$$$) {
	my ($hash, $direction, $step, $device_id) = @_; 
	my $name = $hash->{NAME};

	$device_id = $step . (defined $device_id ? " ". $device_id : "") if(defined $step && $step !~ /^[0-9]+$/);
	$step = $attr{$name}{volumeStep} if(!defined $step || $step !~ /^[0-9]+$/);
	$step = 5 if(!defined $step);

	my $nextVolume = undef;
	if(defined $device_id) {
		my @devices = @{$hash->{helper}{devices}};
		foreach my $device (@devices) {
			if(defined $device->{id} && $device->{id} eq $device_id) {
				$nextVolume = min(100, max(0, $device->{volume_percent} + $step * $direction));
				$device->{volume_percent} = $nextVolume;
			}
		}
	} else {
		$nextVolume = min(100, max(0, $hash->{helper}{device_active}{volume_percent} + $step * $direction));
		$hash->{helper}{device_active}{volume_percent} = $nextVolume;
	}

	return "could not find device" if(!defined $nextVolume);

	Spotify_setVolume($hash, 0, $nextVolume, $device_id);

	return undef;
}


sub Spotify_getTargetDeviceID { # resolve target device settings
	my ($hash, $device_id, $newPlayback) = @_;
	my $name = $hash->{NAME};
	
	if(defined $device_id) { # use device id given by user
		foreach my $device (@{$hash->{helper}{devices}}) {
			return $device->{id} if((defined $device->{id} && $device->{id} eq $device_id) || (defined $device->{name} && lc($device->{name}) eq lc($device_id))); # resolve name to / verify device_id
		}

		# if not verified, continue to look for target device
	}

	# no specific device given by user for this command
	return Spotify_getTargetDeviceID($hash, $attr{$name}{defaultPlaybackDeviceID}, $newPlayback) if(defined $attr{$name}{defaultPlaybackDeviceID} # use default device or active device
		&& (
			(
			defined $attr{$name}{alwaysStartOnDefaultDevice}
			&& (!$hash->{helper}{is_playing} || $newPlayback)
			&& $attr{$name}{alwaysStartOnDefaultDevice}
			)
			|| !defined $hash->{helper}{device_active}{id}
			)
		&& (!defined $device_id || $attr{$name}{defaultPlaybackDeviceID} ne $device_id)
		);

	# no default or active device available
	return $hash->{helper}{devices}[0]{id} if($newPlayback && !defined $hash->{helper}{device_active}{id}); # use first device available device on new playback
	# if no new playback, trust the user anyway (maybe the device list is outdated)
	return undef;
}

sub Spotify_getTransferTargetDeviceID($$) { # get target device id for transfer
	my ($hash, $targetdevice_id) = @_;
	my $device_id = Spotify_getTargetDeviceID($hash, $targetdevice_id, 1); # resolve to user settings
	return $device_id if(defined $targetdevice_id || (defined $device_id && $device_id ne $hash->{helper}{device_active}{id})); # only return if device was specified in command or default device is not active

	# target device not found, no (inactive) default device available
	Spotify_updateDevices($hash, 1); # make sure devices are up to date

	# choose any device that is not active
	foreach my $device (@{$hash->{helper}{devices}}) {
		return $device->{id} if(!$device->{is_active});
	}

	return undef;
}

sub Spotify_volumeFadeStep { # do a single fading stemp
	my ($hash) = @_;
	return if(!defined $hash->{helper}{fading});
	my $name = $hash->{NAME};
	my $iteration = $hash->{helper}{fading}{iteration};
	my $requiredSteps = $hash->{helper}{fading}{requiredSteps};
	my $startVolume = $hash->{helper}{fading}{startVolume};
	my $targetVolume = $hash->{helper}{fading}{targetVolume};
	my $step = $hash->{helper}{fading}{step};
	my $isLastStep = $iteration+1 >= $requiredSteps;
	my $nextVolume = int($isLastStep ? $targetVolume : $startVolume + ($iteration+1)*$step*($targetVolume < $startVolume ? -1 : 1));
	my $deltaBetweenSteps = ($hash->{helper}{fading}{duration}/$requiredSteps); # time in s between each step

	#Log3 "spotify", 3, "fading volume step start $startVolume target $targetVolume steps $requiredSteps step $step nextVolume $nextVolume iteration $iteration delta $deltaBetweenSteps";

	return if($nextVolume < 0 || $nextVolume > 100);

	$hash->{helper}{fading}{iteration}++;
	Spotify_setVolume($hash, 0, $nextVolume, $hash->{helper}{fading}{device_id});

	if(!$isLastStep) {
		InternalTimer(gettimeofday()+$deltaBetweenSteps*($iteration+1), 'Spotify_volumeFadeStep', $hash);
	}
	
	delete $hash->{helper}{fading} if($isLastStep);
	return undef;
}

sub Spotify_dispatch($$$) {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
  	my $name = $hash->{NAME};
  	my ($path) = split('\?', $param->{apiPath}, 2);
  	my ($pathpt0, $pathpt1, $pathpt2) = split('/', $path, 3);
  	my $method = $param->{method};
  	delete $hash->{helper}{dispatch};

  	if(!defined($param->{hash})){
    	Log3 "Spotify", 2, 'Spotify: dispatch fail (hash missing)';
    	return undef;
  	}

  	my $json = eval { JSON->new->utf8(0)->decode($data) };
  	$hash->{helper}{dispatch}{json} = $json;
  	#Log3 $name, 3, $name . ' : ' . $hash . $data;

  	if(defined $json->{error}) {
  		Log3 $name, 3, "$name: request failed: $json->{error}{message}";
  		return Spotify_refreshToken($hash) if($json->{error}{message} =~ /expired/);
  		readingsBeginUpdate($hash);
  		readingsBulkUpdate($hash, 'error_code', $json->{error}{status}, 1);
		readingsBulkUpdate($hash, 'error_description', $json->{error}{message}, 1);
		readingsEndUpdate($hash, 1);
  		return "request failed: $json->{error}{message}";
  	}

  	Log3 $name, 4, "$name: dispatch successful $path";
  	
  	if($path eq 'me/') {
  		return 'could not get user data' if(!defined $json->{id});

  		$hash->{helper}{user_id} = $json->{id};
  		$hash->{helper}{subscription} = $json->{product};
  		$hash->{helper}{uri} = $json->{uri};

  		readingsBeginUpdate($hash);
		readingsBulkUpdateIfChanged($hash, 'user_id', $json->{id}, 1);
		readingsBulkUpdateIfChanged($hash, 'user_country', $json->{country}, 1);
		readingsBulkUpdateIfChanged($hash, 'user_subscription', $json->{subscription}, 1);
		readingsBulkUpdateIfChanged($hash, 'user_display_name', $json->{display_name}, 1);
		readingsBulkUpdateIfChanged($hash, 'user_profile_pic_url', $json->{images}[0]{url}, 1) if(defined $json->{images} && $json->{images} > 0);
		readingsBulkUpdateIfChanged($hash, 'user_follower_cnt', $json->{followers}{total}, 1);
		readingsEndUpdate($hash, 1);
  	}

  	if($path eq 'me/player/devices') {
  		return 'could not update devices' if(!defined $json->{devices});

  		delete $hash->{helper}{device_active};

  		# delete any devices that are out of bounds
  		if(defined $hash->{helper}{devices}) {
  			my $index = 1;
			foreach my $device (@{$hash->{helper}{devices}}) {
				if($index > @{$json->{devices}}) {
					CommandDeleteReading(undef, "$name device_". $index ."_.*");
				}
				$index++;
			}
  		} else {
  			CommandDeleteReading(undef, "$name device_.*");
  		}

  		$hash->{helper}{devices} = $json->{devices};
  		readingsBeginUpdate($hash);

  		my $index = 1;
  		foreach my $device (@{$hash->{helper}{devices}}) {
  			Spotify_saveDevice($hash, $device, "device_". $index, 0);

  			if($device->{is_active}) {
  				Spotify_saveDevice($hash, $device, "device_active", 0);
  				readingsBulkUpdateIfChanged($hash, 'volume', $device->{volume_percent});
  				$hash->{helper}{device_active} = $device; # found active device
  			}
  			
  			$hash->{helper}{device_default} = $device if(defined $attr{$name}{defaultPlaybackDeviceID} && $device->{id} eq $attr{$name}{defaultPlaybackDeviceID}); # found users default device
  			$index++;
  		}
  		readingsBulkUpdateIfChanged($hash, 'devices_cnt', $index-1, 1);
  		$hash->{helper}{is_active} = defined $hash->{helper}{device_active};
  		if(!$hash->{helper}{is_active}) {
  			Spotify_saveDevice($hash, {id => "none", "name" => "none", "volume_percent" => -1, "type" => "none"}, 'device_active', 0);
  			$hash->{STATE} = "connected";
  			readingsBulkUpdateIfChanged($hash, 'is_playing', 0, 1);	
  		}
  		readingsEndUpdate($hash, 1);
  	}

  	if($path eq 'me/player') {
  		if(!defined $json->{is_playing}) {
  			$hash->{STATE} = 'connected';
  			$hash->{helper}{is_playing} = 0;
  			readingsSingleUpdate($hash, 'is_playing', 0, 1);
  			return undef;
  		}

  		$hash->{helper}{is_active} = defined $json->{device} && $json->{device}{is_active};
  		$hash->{helper}{is_playing} = $json->{is_playing} && $hash->{helper}{is_active};
  		$hash->{helper}{repeat} = $json->{repeat_state} eq 'track' ? 'one' : ($json->{repeat_state} eq 'context' ? 'all' : 'off');
  		$hash->{helper}{shuffle} = $json->{shuffle_state};
  		$hash->{helper}{progress_ms} = $json->{progress_ms};
  		$hash->{STATE} = $json->{is_playing} ? 'playing' : 'paused';

		readingsBeginUpdate($hash);
		readingsBulkUpdateIfChanged($hash, 'is_playing', $hash->{helper}{is_playing} ? 1 : 0, 1);
		readingsBulkUpdateIfChanged($hash, 'shuffle', $json->{shuffle_state} ? 'on' : 'off', 1);
		readingsBulkUpdateIfChanged($hash, 'repeat', $hash->{helper}{repeat}, 1);
		readingsBulkUpdateIfChanged($hash, 'progress_ms', $json->{progress_ms}, 1);
        readingsBulkUpdateIfChanged($hash, "progress", h2hms_fmt($json->{progress_ms} / 1000 / 60 / 60), 1);

		if(defined $json->{item}) {
			my $item = $json->{item};
			$hash->{helper}{track} = $item;
			Spotify_saveTrack($hash, $item, 'track', 0);
		} else {
			CommandDeleteReading(undef, "$name track_.*");
		}

		if($hash->{helper}{is_active}) {
			my $device = $json->{device};
			$hash->{helper}{device_active} = $device;
			readingsBulkUpdateIfChanged($hash, 'volume', $device->{volume_percent});
			Spotify_saveDevice($hash, $device, "device_active", 0);
		} else {
			delete $hash->{helper}{device_active};
			Spotify_saveDevice($hash, {id => "none", "name" => "none", "volume_percent" => -1, "type" => "none"}, 'device_active', 0);
			$hash->{STATE} = 'connected' if(!defined $json->{device});
		}

		if($hash->{helper}{is_playing}) {
			if(!defined $hash->{helper}{updatePlaybackTimer_next} || $hash->{helper}{updatePlaybackTimer_next} <= gettimeofday()) { # start refresh timer if not already started
				my $updateIntervalWhilePlaying = $attr{updateIntervalWhilePlaying};
				$updateIntervalWhilePlaying = 10 if(!defined $updateIntervalWhilePlaying);
				$hash->{helper}{updatePlaybackTimer_next} = gettimeofday()+$updateIntervalWhilePlaying; # refresh playback status every 15 seconds if currently playing
				InternalTimer($hash->{helper}{updatePlaybackTimer_next}, 'Spotify_updatePlaybackStatus', $hash);
			}

			if(defined $json->{item} && (!defined $hash->{helper}{nextSongTimer} || $hash->{helper}{nextSongTimer} <= gettimeofday())) { # refresh on finish of the song
				$hash->{helper}{nextSongTimer} = gettimeofday() + int(($json->{item}{duration_ms} - $json->{progress_ms}) / 1000) + 1;
				InternalTimer($hash->{helper}{nextSongTimer}, "Spotify_updatePlaybackStatus", $hash);
			}
		}

		readingsEndUpdate($hash, 1);

		return undef;
  	}

  
  	if($path eq 'me/player/volume') {
  		Spotify_updateDevices($hash, 0) if(!defined $hash->{helper}{fading});
  		return undef; # do not fall through
  	} 

  	if(defined $pathpt1 && $pathpt1 eq 'player' && $method ne 'GET') { # on every modification on the player, update playback status
  		Spotify_updatePlaybackStatus($hash, 1);
  		InternalTimer(gettimeofday()+2, 'Spotify_updatePlaybackStatus', $hash); # make sure the api is already up to date and lists the changes
  	}

  	return undef;
}

sub Spotify_poll($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return if(Spotify_isDisabled($hash));

	my $pollInterval = $attr{$name}{updateInterval};
    InternalTimer(gettimeofday()+(defined $pollInterval ? $pollInterval : 5*60), "Spotify_poll", $hash);
	Spotify_update($hash, 0);
}

sub Spotify_update($$) {
	my ($hash, $full) = @_;
	Spotify_updateMe($hash, 0) if($full);
	Spotify_updateDevices($hash, 0);
  	Spotify_updatePlaybackStatus($hash, 0);
}

sub Spotify_saveTrack($$$$) { # save a track object to the readings
	my ($hash, $track, $prefix, $beginUpdate) = @_;
	readingsBeginUpdate($hash) if($beginUpdate);
	readingsBulkUpdateIfChanged($hash, $prefix."_name", $track->{name}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_uri", $track->{uri}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_popularity", $track->{popularity}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_duration_ms", $track->{duration_ms}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_artist_name", $track->{artists}[0]{name}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_artist_uri", $track->{artists}[0]{uri}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_album_name", $track->{album}{name}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix."_album_uri", $track->{album}{uri}, 1);
    readingsBulkUpdateIfChanged($hash, $prefix."_duration", h2hms_fmt($track->{duration_ms} / 1000 / 60 / 60), 1);

	my @sizes = ("large", "medium", "small");
	my $index = 0;
	foreach my $image(@{$track->{album}{images}}) {
		readingsBulkUpdateIfChanged($hash, $prefix."_album_cover_". $sizes[$index], $image->{url}, 1);
		$index++;
		last if($index >= 3);
	}
	
	readingsEndUpdate($hash, 1) if($beginUpdate);
}

sub Spotify_saveArtist($$$$) { # save an artist object to the readings
	my ($hash, $artist, $prefix, $beginUpdate) = @_;
	readingsBeginUpdate($hash) if($beginUpdate);
	readingsBulkUpdate($hash, $prefix."_name", $artist->{name}, 1);
	readingsBulkUpdate($hash, $prefix."_uri", $artist->{uri}, 1);
	readingsBulkUpdate($hash, $prefix."_popularity", $artist->{popularity}, 1);
	readingsBulkUpdate($hash, $prefix."_follower_cnt", $artist->{followers}{total}, 1);
	readingsBulkUpdate($hash, $prefix."_profile_pic_url", $artist->{images}[0]{url}, 1);
	readingsEndUpdate($hash, 1) if($beginUpdate);
}

sub Spotify_saveDevice($$$$) {
	my ($hash, $device, $prefix, $beginUpdate) = @_;
	readingsBeginUpdate($hash) if($beginUpdate);
	readingsBulkUpdateIfChanged($hash, $prefix . '_id', $device->{id}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix . '_name', $device->{name}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix . '_type', $device->{type}, 1);
	readingsBulkUpdateIfChanged($hash, $prefix . '_volume', $device->{volume_percent}, 1) if(defined $device->{volume_percent});
	readingsEndUpdate($hash, 1) if($beginUpdate);
}

sub Spotify_isDisabled($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return defined $attr{$name}{disable};
}

1;

=pod
=item device
=item summary    control your Spotify (Connect) playback
=item summary_DE Steuerung von Spotify (Connect)
=begin html

<a name="Spotify"></a>
<h3>Spotify</h3>
<ul>
  The <i>Spotify</i> module enables you to control your Spotify (Connect) playback.<br>
  To be able to control your music, you need to authorize with the Spotify WEB API. To do that, a <a target="_blank" rel="nofollow" href="https://developer.spotify.com/my-applications/#!/applications/create">Spotify API application</a> is required.<br>
  While creating the app, enter any <i>redirect_uri</i>. By default the module will use <a href="https://oskar.pw/" target="_blank">https://oskar.pw/</a> as <i>redirect_uri</i> since the site outputs your temporary authentification code.<br>
  It is safe to rely on this site because the code is useless without your client secret and only valid for a few minutes (important: you have to press the <b>add</b> and <b>save</b> button while adding the url).<br>
  If you want to use it, make sure to add it as <i>redirect_uri</i> to your app - however, you are free to use any other url and extract the code after signing in yourself.<br>
  <br>
  <a name="Spotify_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Spotify &lt;client_id&gt; &lt;client_secret&gt; [ &lt;redirect_url&gt; ]</code><br>
  </ul>
  <br>
  <ul>
   Example: <code>define Spotify Spotify f88e5f5c2911152d914391592e717738 301b6d1a245e4fe01c2f8b4efd250756</code><br>
  </ul>
  <br>
  Once defined, open up your browser and call the URL displayed in <i>AUTHORIZATION_URL</i>, sign in with spotify and extract the code after being redirected.<br>
  If you get a <b>redirect_uri mismatch</b> make sure to either add <a href="https://oskar.pw/" target="_blank">https://oskar.pw/</a> as redirect url or that your url <b>matches exactly</b> with the one defined.<br>
  As soon as you obtained the code call <code>set &lt;name&gt; code &lt;code&gt;</code> - your state should change to connected and you are ready to go.<br>

  <br>
  <a name="Spotify_set"></a>
  <p><b>set &lt;required&gt; [ &lt;optional&gt; ]</b></p>
  Without a target device given, the active device (or default device if <i>alwaysStartOnDefaultDevice</i> is enabled) will be used.<br>
  You can also use the name of the target device instead of the id if it does not contain spaces - where it states <i>&lt;device_id / device_name&gt;</i> spaces are allowed.<br>
  If no default device is defined and none is active, it will use the first available device.<br>
  You can get a spotify uri by pressing the share button in the spotify (desktop) app on a track/playlist/album.<br><br>
  <ul>
  	<li>
      <i>findArtistByName</i><br>
      finds an artist using its name and returns the result to the readings
    </li>
  	<li>
      <i>findTrackByName</i><br>
      finds a track using its name and returns the result to the readings
    </li>
    <li>
      <i>pause</i><br>
      pause the current playback
    </li>
    <li>
      <i>playArtistByName &lt;artist_name&gt; [ &lt;device_id&gt; ]</i><br>
      plays an artist using its name (uses search)
    </li>
    <li>
      <i>playContextByURI &lt;context_uri&gt; [ &lt;nr_of_start_track&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      plays a context (playlist, album or artist) using a Spotify URI
    </li>
    <li>
      <i>playPlaylistByName &lt;playlist_name&gt; [ &lt;device_id&gt; ]</i><br>
      plays any playlist by providing a name (uses search)
    </li>
    <li>
      <i>playRandomTrackFromPlaylistByURI &lt;playlist_uri&gt; [ &lt;limit&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      plays a random track from a playlist (only considering the first <i>&lt;limit&gt;</i> songs)
    </li>
    <li>
      <i>playSavedTracks [ &lt;nr_of_start_track&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      plays the saved tracks (beginning with track <i>&lt;nr_of_start_track&gt;</i>)
    </li>
    <li>
      <i>playTrackByName &lt;track_name&gt; [ &lt;device_id&gt; ]</i><br>
      finds a song by its name and plays it
    </li>
    <li>
      <i>playTrackByURI &lt;track_uri&gt; [ &lt;device_id / device_name&gt; ]</i><br>
      plays a track using a track uri
    </li>
    <li>
      <i>repeat &lt;track,context,off&gt;</i><br>
      sets the repeat mode: either <i>one</i>, <i>all</i> (meaning playlist or album) or <i>off</i>
    </li>
    <li>
      <i>resume [ &lt;device_id / device_name&gt; ]</i><br>
      resumes playback (on a device)
    </li>
    <li>
      <i>seekToPosition &lt;position&gt;</i><br>
      seeks to the position <i>&lt;position&gt;</i> (in seconds, supported formats: 01:20, 80, 00:20, 20)
    </li>
    <li>
      <i>shuffle &lt;off,on&gt;</i><br>
      sets the shuffle mode: either <i>on</i> or <i>off</i>
    </li>
    <li>
      <i>skipToNext</i><br>
      skips to the next track
    </li>
    <li>
      <i>skipToPrevious</i><br>
      skips to the previous track
    </li>
    <li>
      <i>togglePlayback</i><br>
      toggles the playback (resumes if paused, pauses if playing)
    </li>
    <li>
      <i>transferPlayback [ &lt;device_id&gt; ]</i><br>
      transfers the current playback to the specified device (or the next inactive device if not specified)
    </li>
    <li>
      <i>update</i><br>
      updates playback and devices
    </li>
    <li>
      <i>volume &lt;volume&gt; [ &lt;device_id&gt; ]</i><br>
      sets the volume
    </li>
    <li>
      <i>volumeDown [ &lt;step&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      decreases the volume by <i>step</i> (if not set it uses <i>volumeStep</i>)
    </li>
    <li>
      <i>volumeFade &lt;volume&gt; [ &lt;duration&gt; &lt;step&gt; ] [ &lt;device_id&gt; ]</i><br>
      fades the volume
    </li>
    <li>
      <i>volumeDown [ &lt;step&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      increases the volume by <i>step</i> (if not set it uses <i>volumeStep</i>)
    </li>
  </ul>  
  <br>
  <a name="Spotify_get"></a>
  <p><b>Get</b></p>
  <ul>
  	N/A
  </ul>
  <br>
  <a name="Spotify_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>alwaysStartOnDefaultDevice</i><br>
      always start new playback on the default device<br>
      default: 0
    </li>
    <li>
      <i>defaultPlaybackDeviceID</i><br>
      the prefered device by its id or device name<br>
    </li>
    <li>
      <i>disable</i><br>
      disables the device<br>
      default: 0
    </li>
    <li>
      <i>updateInterval</i><br>
      the interval to update your playback status while no music is running (in seconds)<br>
      default: 300
    </li>
    <li>
      <i>updateIntervalWhilePlaying</i><br>
      the interval to update your playback status while music is running (in seconds)<br>
      default: 10
    </li>
    <li>
      <i>volumeStep</i><br>
      the value by which the volume is in-/decreased by default (in percent)<br>
      default: 5
    </li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="Spotify"></a>
<h3>Spotify</h3>
<ul>
  Das <i>Spotify</i> Modul ermöglicht die Steuerung von Spotify (Connect).<br>
  Um die Wiedergabe zu steuern, wird die Spotify WEB API verwendet. Dafür wird eine eigene <a target="_blank" rel="nofollow" href="https://developer.spotify.com/my-applications/#!/applications/create">Spotify API application</a> benötigt.<br>
  Während der Erstellung muss eine <i>redirect_uri</i> angegeben - standardmäßig wird vom Modul <a href="https://oskar.pw/" target="_blank">https://oskar.pw/</a> verwendet, da diese Seite nach der Anmeldung den Code in leserlicher Form ausgibt.<br>
  Die Seite kann bedenkenlos verwendet werden, da der Code ohne <i>client_secret</i> nutzlos und nur wenige Minuten gültig ist.<br>
  Wenn du diese verwenden willst, stelle sicher, diese bei der Erstellung anzugeben (wichtig: das Hinzufügen der URL muss mit <b>add</b> und <b>save</b> bestätigt werden), ansonsten kann jede beliebige andere Seite verwendet werden und der Code aus der URL extrahiert werden.<br>
  <br>
  <a name="Spotify_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Spotify &lt;client_id&gt; &lt;client_secret&gt; [ &lt;redirect_url&gt; ]</code><br>
  </ul>
  <br>
  <ul>
   Beispiel: <code>define Spotify Spotify f88e5f5c2911152d914391592e717738 301b6d1a245e4fe01c2f8b4efd250756</code><br>
  </ul>
  <br>
  Sobald das Gerät angelegt wurde, muss die <i>AUTHORIZATION_URL</i> im Browser geöffnet werden und die Anmeldung mit Spotify erfolgen.<br>
  Sollte der Fehler <b>redirect_uri mismatch</b> auftauchen, stelle sicher, dass <a href="https://oskar.pw/" target="_blank">https://oskar.pw/</a> als <i>redirect_uri</i> hinzugefügt wurde oder die verwendete URL <b>exakt übereinstimmt</b>.<br>
  Sobald der Anmeldecode ermittelt wurde, führe folgenden Befehl aus: <code>set &lt;name&gt; code &lt;code&gt;</code> - der Status sollte nun auf connected wechseln und das Gerät ist einsatzbereit.<br>

  <br>
  <a name="Spotify_set"></a>
  <p><b>set &lt;required&gt; [ &lt;optional&gt; ]</b></p>
  Wird kein Zielgerät angegeben, wird das aktive (oder das Standard-Gerät, wenn <i>alwaysStartOnDefaultDevice</i> aktiviert ist) verwendet.<br>
  An den Stellen, wo eine <i>&lt;device_id&gt;</i> verlangt wird, kann auch der Gerätename, sofern dieser keine Leerzeichen enthält, verwendet werden. Dort wo es <i>&lt;device_name&gt;</i> heißt, sind auch Leerzeichen im Namen zugelassen.
  Wenn kein aktives oder Standard-Gerät vorhanden ist, wird das erste verfügbare Gerät verwendet.<br>
  Die Spotify URI kann in der (Desktop) App ermittelt werden, wenn man den teilen Knopf bei einem Track/Playlist/Album drückt.<br><br>
  <ul>
  	<li>
      <i>findArtistByName</i><br>
      sucht einen Künstler und liefert das Ergebnis in den Readings
    </li>
  	<li>
      <i>findTrackByName</i><br>
      sucht einen Track und liefert das Ergebnis in den Readings
    </li>
    <li>
      <i>pause</i><br>
      pausiert die aktuelle Wiedergabe
    </li>
    <li>
      <i>playArtistByName &lt;artist_name&gt; [ &lt;device_id&gt; ]</i><br>
      sucht einen Künstler und spielt dessen Tracks ab
    </li>
    <li>
      <i>playContextByURI &lt;context_uri&gt; [ &lt;nr_of_start_track&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      spielt einen Context (Playlist, Album oder Künstler) durch Angabe der URI ab
    </li>
    <li>
      <i>playPlaylistByName &lt;playlist_name&gt; [ &lt;device_id&gt; ]</i><br>
      sucht eine Playlist und spielt diese ab
    </li>
    <li>
      <i>playRandomTrackFromPlaylistByURI &lt;playlist_uri&gt; [ &lt;limit&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      spielt einen zufälligen Track aus einer Playlist ab (berücksichtigt nur die ersten <i>&lt;limit&gt;</i> Tracks der Playlist)
    </li>
    <li>
      <i>playSavedTracks [ &lt;nr_of_start_track&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      spielt die gespeicherten Tracks ab (beginnend mit Track Nummer <i>&lt;nr_of_start_track&gt;</i>)
    </li>
    <li>
      <i>playTrackByName &lt;track_name&gt; [ &lt;device_id&gt; ]</i><br>
      sucht den Song und spielt ihn ab
    </li>
    <li>
      <i>playTrackByURI &lt;track_uri&gt; [ &lt;device_id / device_name&gt; ]</i><br>
      spielt einen Song durch Angabe der URI ab
    </li>
    <li>
      <i>repeat &lt;track,context,off&gt;</i><br>
      setzt den Wiederholungsmodus: entweder <i>one</i>, <i>all</i> (Playlist, Album, Künstler) oder <i>off</i>
    </li>
    <li>
      <i>resume [ &lt;device_id / device_name&gt; ]</i><br>
      fährt mit der Wiedergabe (auf einem Gerät) fort
    </li>
    <li>
      <i>seekToPosition &lt;position&gt;</i><br>
      spult an die Position <i>&lt;position&gt;</i> (in Sekunden, erlaubte Formate: 01:20, 80, 00:20, 20)
    </li>
    <li>
      <i>shuffle &lt;off,on&gt;</i><br>
      setzt den Shuffle-Modus: entweder <i>on</i> oder <i>off</i>
    </li>
    <li>
      <i>skipToNext</i><br>
      weiter zum nächsten Track
    </li>
    <li>
      <i>skipToPrevious</i><br>
      zurück zum vorherigen Track
    </li>
    <li>
      <i>togglePlayback</i><br>
      toggelt die Wiedergabe (hält an, wenn sie aktiv ist, ansonsten fortsetzen)
    </li>
    <li>
      <i>transferPlayback [ &lt;device_id&gt; ]</i><br>
      überträgt die aktuelle Wiedergabe auf ein anderes Gerät (wenn kein Gerät angegeben wird, wird das nächste inaktive verwendet)
    </li>
    <li>
      <i>update</i><br>
      lädt den aktuellen Zustand neu
    </li>
    <li>
      <i>volume &lt;volume&gt; [ &lt;device_id&gt; ]</i><br>
      setzt die Lautstärke
    </li>
    <li>
      <i>volumeDown [ &lt;step&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      verringert die Lautstärke um <i>step</i> (falls nicht gesetzt, um <i>volumeStep</i>)
    </li>
    <li>
      <i>volumeFade &lt;volume&gt; [ &lt;duration&gt; &lt;step&gt; ] [ &lt;device_id&gt; ]</i><br>
      setzt die Lautstärke schrittweise
    </li>
    <li>
      <i>volumeUp [ &lt;step&gt; ] [ &lt;device_id / device_name&gt; ]</i><br>
      erhöht die Lautstärke um <i>step</i> (falls nicht gesetzt, um <i>volumeStep</i>)
    </li>
  </ul>  
  <br>
  <a name="Spotify_get"></a>
  <p><b>Get</b></p>
  <ul>
  	N/A
  </ul>
  <br>
  <a name="Spotify_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>alwaysStartOnDefaultDevice</i><br>
      startet neue Wiedergabe immer auf dem Standard-Gerät<br>
      default: 0
    </li>
    <li>
      <i>defaultPlaybackDeviceID</i><br>
      das Standard-Gerät durch Angabe der Geräte-ID oder des Geräte-Namens<br>
    </li>
    <li>
      <i>disable</i><br>
      deaktiviert das Gerät<br>
      default: 0
    </li>
    <li>
      <i>updateInterval</i><br>
      Intervall in Sekunden, in dem der Status aktualisiert wird, wenn keine Musik läuft<br>
      default: 300
    </li>
    <li>
      <i>updateIntervalWhilePlaying</i><br>
      Intervall in Sekunden, in dem der Status aktualisiert wird, wenn Musik läuft<br>
      default: 10
    </li>
    <li>
      <i>volumeStep</i><br>
      der Wert, um den die Lautstärke bei volumeUp/volumeDown standardmäßig verändert wird (in Prozent)<br>
      default: 5
    </li>
  </ul>
</ul>

=end html_DE
=cut