#############################################################
#
# GOOGLECAST.pm (c) by Dominik Karall, 2016-2017
# dominik karall at gmail dot com
# $Id$
#
# FHEM module to communicate with Google Cast devices
# e.g. Chromecast Video, Chromecast Audio, Google Home
#
# Version: 2.1.0
#
#############################################################
#
# v2.1.0 - 20180218
# - BUGFIX:   one more socket_client fix
# - BUGFIX:   offline state fix
#
# v2.0.3 - 20180217
# - CHANGE:   increase speak limit to 500 characters
#
# v2.0.2 - 20180106
# - FEATURE:  support speak command for TTS
#               set castdevice speak "Hallo"
# - BUGFIX:   fix issues with umlauts in device name
# - BUGFIX:   fix one socket issue
# - BUGFIX:   fix delay for non youtube-dl links
# - BUGFIX:   optimize delay for youtube links
#
# v2.0.1 - 20171209
# - FEATURE:  support skip/rewind
# - FEATURE:  support displaying websites on Chromecast
#
# v2.0.0 - 20170812
# - CHANGE:   renamed to 98_GOOGLECAST.pm
# - CHANGE:   removed favoriteName_X attribute, it was never used
# - BUGFIX:   updated commandref with further required packages
# - FEATURE:  state reading now represents status (online, offline,
#               playing, paused, buffering)
# - FEATURE:  new readings mediaContentId, mediaCurrentPosition,
#               mediaDuration, mediaPlayerState, mediaStreamType
# - BUGFIX:   change volume to represent integer values only
#
# v1.0.7 - 20170804
# - BUGFIX:  fix reconnection in some cases
#
# v1.0.6 - 20170705
# - BUGFIX:  speed up youtube video URL extraction with youtube_dl
# - BUGFIX:  fixed one more issue when chromecast offline
# - BUGFIX:  improved performance by adding socket to FHEM main loop
#
# v1.0.5 - 20170704
# - BUGFIX:  hopefuly fixed the annoying hangs when chromecast offline
# - FEATURE: add presence reading (online/offline)
#
# v1.0.4 - 20170101
# - FEATURE: support all services supported by youtube-dl
#            https://github.com/rg3/youtube-dl/blob/master/docs/supportedsites.md
#            playlists not yet supported!
# - BUGFIX:  support non-blocking chromecast search
#
# v1.0.3 - 20161219
# - FEATURE: support volume
# - FEATURE: add new readings and removed
#            castStatus, mediaStatus reading
# - FEATURE: add attribute favoriteURL_[1-5]
# - FEATURE: add playFavorite [1-5] set function
# - FEATURE: retry init chromecast every 10s if not found on startup
# - BUGFIX:  support special characters for device name
#
# v1.0.2 - 20161216
# - FEATURE: support play of every mime type which is supported
#            by Chromecast (see https://developers.google.com/cast/docs/media)
#            including youtube URLs
# - CHANGE:  change play* methods to play <url>
# - FEATURE: support very simple .m3u which contain only URL
# - BUGFIX:  non-blocking playYoutube
# - BUGFIX:  fix play if media player is already running
#
# v1.0.1 - 20161211
# - FEATURE: support playYoutube <youtubelink>
#
# v1.0.0 - 20161015
# - FEATURE: first public release
#
# TODO
# - check spotify integration
# - support youtube playlists
#
# NOTES
#         def play_media(self, url, content_type, title=None, thumb=None,
#                   current_time=0, autoplay=True,
#                   stream_type=STREAM_TYPE_BUFFERED,
#                   metadata=None, subtitles=None, subtitles_lang='en-US',
#                   subtitles_mime='text/vtt', subtitle_id=1):
#         """
#         Plays media on the Chromecast. Start default media receiver if not
#         already started.
#         Parameters:
#         url: str - url of the media.
#         content_type: str - mime type. Example: 'video/mp4'.
#         title: str - title of the media.
#         thumb: str - thumbnail image url.
#         current_time: float - seconds from the beginning of the media
#             to start playback.
#         autoplay: bool - whether the media will automatically play.
#         stream_type: str - describes the type of media artifact as one of the
#             following: "NONE", "BUFFERED", "LIVE".
#         subtitles: str - url of subtitle file to be shown on chromecast.
#         subtitles_lang: str - language for subtitles.
#         subtitles_mime: str - mimetype of subtitles.
#         subtitle_id: int - id of subtitle to be loaded.
#         metadata: dict - media metadata object, one of the following:
#             GenericMediaMetadata, MovieMediaMetadata, TvShowMediaMetadata,
#             MusicTrackMediaMetadata, PhotoMediaMetadata.
#         Docs:
#         https://developers.google.com/cast/docs/reference/messages#MediaData
#         """
#
#############################################################

package main;

use strict;
use warnings;

use Blocking;
use Encode;
use SetExtensions;

use URI::Escape;
use LWP::UserAgent;

sub GOOGLECAST_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = 'GOOGLECAST_Define';
    $hash->{UndefFn}  = 'GOOGLECAST_Undef';
    $hash->{GetFn}    = 'GOOGLECAST_Get';
    $hash->{SetFn}    = 'GOOGLECAST_Set';
    $hash->{ReadFn}   = 'GOOGLECAST_Read';
    $hash->{AttrFn}   = 'GOOGLECAST_Attribute';
    $hash->{AttrList} = "favoriteURL_1 favoriteURL_2 favoriteURL_3 favoriteURL_4 ".
                        "favoriteURL_5 ".$readingFnAttributes;

    Log3 $hash, 3, "GOOGLECAST: GoogleCast v2.1.0";

    return undef;
}

sub GOOGLECAST_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my $name = $a[0];

    $hash->{STATE} = "initialized";

    if (int(@a) > 3) {
        return 'GOOGLECAST: Wrong syntax, must be define <name> GOOGLECAST <device name>';
    } elsif(int(@a) == 3) {
        Log3 $hash, 3, "GOOGLECAST: $a[2] initializing...";
        $hash->{CCNAME} = $a[2];
        GOOGLECAST_updateReading($hash, "presence", "offline");
        GOOGLECAST_updateReading($hash, "state", "offline");
        GOOGLECAST_initDevice($hash);
    }

    return undef;
}

sub GOOGLECAST_findChromecasts {
    my ($string) = @_;
    my ($name) = split("\\|", $string);
    my $result = "$name";

    my @ccResult = GOOGLECAST_findChromecastsPython();
    foreach my $ref_cc (@ccResult) {
        my @cc = @$ref_cc;
        $result .= "|CCDEVICE|".$cc[0]."|".$cc[1]."|".$cc[2]."|".$cc[3]."|".Encode::encode('UTF-8', $cc[4]);
    }
    Log3 $name, 4, "GOOGLECAST: search result: $result";

    return $result;
}

sub GOOGLECAST_initDevice {
    my ($hash) = @_;
    my $devName = $hash->{CCNAME};

    BlockingCall("GOOGLECAST_findChromecasts", $hash->{NAME}, "GOOGLECAST_findChromecastsResult");

    return undef;
}

sub GOOGLECAST_findChromecastsResult {
    my ($string) = @_;
    my ($name, @ccResult) = split("\\|", $string);
    my $hash = $main::defs{$name};
    my $devName = $hash->{CCNAME};
    $hash->{helper}{ccdevice} = "";

    for my $i (0..$#ccResult) {
        if($ccResult[$i] eq "CCDEVICE" and $ccResult[$i+5] eq $devName) {
            Log3 $hash, 4, "GOOGLECAST ($hash->{NAME}): init cast device $devName";
            eval {
              $hash->{helper}{ccdevice} = GOOGLECAST_createChromecastPython($ccResult[$i+1],$ccResult[$i+2],$ccResult[$i+3],$ccResult[$i+4],$ccResult[$i+5]);
            };
            if($@) {
              $hash->{helper}{ccdevice} = "";
            }
            Log3 $hash, 4, "GOOGLECAST ($hash->{NAME}): device initialized";
        }
    }

    if($hash->{helper}{ccdevice} eq "") {
        Log3 $hash, 4, "GOOGLECAST: $devName not found, retry in 10s.";
        InternalTimer(gettimeofday()+10, "GOOGLECAST_initDevice", $hash, 0);
        return undef;
    }

    Log3 $hash, 3, "GOOGLECAST: $devName initialized successfully";

    GOOGLECAST_addSocketToMainloop($hash);
    GOOGLECAST_checkConnection($hash);

    return undef;
}

sub GOOGLECAST_Attribute($$$$) {
    my ($mode, $devName, $attrName, $attrValue) = @_;

    if($mode eq "set") {

    } elsif($mode eq "del") {

    }

    return undef;
}

sub GOOGLECAST_Set($@) {
    my ($hash, $name, @params) = @_;
    my $workType = shift(@params);
    my $list = "stop:noArg pause:noArg rewind:noArg skip:noArg quitApp:noArg play playFavorite:1,2,3,4,5 volume:slider,0,1,100 displayWebsite speak";

    #get quoted text from params
    my $blankParams = join(" ", @params);
    my @params2;
    while($blankParams =~ /"?((?<!")\S+(?<!")|[^"]+)"?\s*/g) {
        push(@params2, $1);
    }
    @params = @params2;

    # check parameters for set function
    if($workType eq "?") {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }

    if($workType eq "stop") {
        GOOGLECAST_setStop($hash);
    } elsif($workType eq "pause") {
        GOOGLECAST_setPause($hash);
    } elsif($workType eq "play") {
        GOOGLECAST_setPlay($hash, $params[0]);
    } elsif($workType eq "playFavorite") {
        GOOGLECAST_setPlayFavorite($hash, $params[0]);
    } elsif($workType eq "quitApp") {
        GOOGLECAST_setQuitApp($hash);
    } elsif($workType eq "volume") {
        GOOGLECAST_setVolume($hash, $params[0]);
    } elsif($workType eq "displayWebsite") {
        GOOGLECAST_setWebsite($hash, $params[0]);
    } elsif($workType eq "rewind") {
        GOOGLECAST_setRewind($hash);
    } elsif($workType eq "skip") {
        GOOGLECAST_setSkip($hash);
    } elsif($workType eq "speak") {
        GOOGLECAST_setSpeak($hash, $params[0]);
    } else {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }

    return undef;
}

### volume ###
sub GOOGLECAST_setVolume {
    my ($hash, $volume) = @_;
    $volume = $volume/100;

    eval {
        $hash->{helper}{ccdevice}->set_volume($volume);
    };
}

### dashcast ###
sub GOOGLECAST_setWebsite {
    my ($hash, $url) = @_;

    eval {
       GOOGLECAST_loadDashCast($hash->{helper}{ccdevice}, $url);
    };
}

### speak ###
sub GOOGLECAST_setSpeak {
    my ($hash, $ttsText) = @_;

    my $ttsLang = AttrVal($hash->{NAME}, "ttsLanguage", "de");
    return "GOOGLECAST: Maximum text length is 500 characters." if(length($ttsText) > 500);

    $ttsText = uri_escape($ttsText);
    my $ttsUrl = "http://translate.google.com/translate_tts?tl=$ttsLang&client=tw-ob&q=$ttsText";

    eval {
        $hash->{helper}{ccdevice}->{media_controller}->play_media($ttsUrl, "audio/mpeg");
    };
    return undef;
}

### playType ###
sub GOOGLECAST_setPlayType {
    my ($hash, $url, $mime) = @_;

    Log3 $hash, 4, "GOOGLECAST($hash->{NAME}): setPlayType($url, $mime)";

    if($mime =~ m/text\/html/) {
        GOOGLECAST_setPlayYtDl($hash, $url);
    } else {
        eval {
            Log3 $hash, 4, "GOOGLECAST($hash->{NAME}): start play_media";
            $hash->{helper}{ccdevice}->{media_controller}->play_media($url, $mime);
        };
    }

    return undef;
}

sub GOOGLECAST_setPlayType_String {
    my ($string) = @_;
    my ($name, $url, $mime) = split("\\|", $string);
    my $hash = $main::defs{$name};

    if($mime ne "" && $url ne "") {
        GOOGLECAST_setPlayType($hash, $url, $mime);
    }
}

### playMedia ###
sub GOOGLECAST_setPlayMedia {
    my ($hash, $url) = @_;

    BlockingCall("GOOGLECAST_setPlayMediaBlocking", $hash->{NAME}."|".$url, "GOOGLECAST_setPlayType_String");

    return undef;
}

sub GOOGLECAST_setPlayMedia_String {
    my ($string) = @_;
    my ($name, $videoUrl, $origUrl) = split("\\|", $string);
    my $hash = $main::defs{$name};

    Log3 $hash, 4, "GOOGLECAST($name): setPlayMedia_String($string)";

    if($videoUrl ne "") {
        GOOGLECAST_setPlayMedia($hash, $videoUrl);
    } else {
        GOOGLECAST_setPlayMedia($hash, $origUrl);
    }
}

sub GOOGLECAST_setPlayMediaBlocking {
    my ($string) = @_;
    my ($name, $url) = split("\\|", $string);

    #$url = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
    #$url = "http://swr-mp3-m-swr3.akacast.akamaistream.net:80/7/720/137136/v1/gnl.akacast.akamaistream.net/swr-mp3-m-swr3";

    my $ua = new LWP::UserAgent(agent => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.5) Gecko/20060719 Firefox/1.5.0.5');
    $ua->max_size(0);
    my $resp = $ua->get($url);
    my $mime = $resp->header('Content-Type');

    if($mime eq "audio/x-mpegurl") {
        $mime = "audio/mpeg";
        $url = $resp->decoded_content;
        $url =~ s/\R//g;
    }

    return $name."|".$url."|".$mime;
}

### playYoutue ###
sub GOOGLECAST_setPlayYtDl {
    my ($hash, $ytUrl) = @_;

    BlockingCall("GOOGLECAST_setPlayYtDlBlocking", $hash->{NAME}."|".$ytUrl, "GOOGLECAST_setPlayMedia_String");

    return undef;
}

sub GOOGLECAST_setPlayYtDlBlocking {
    my ($string) = @_;
    my ($name, $ytUrl) = split("\\|", $string);
    my $videoUrl = "";

    eval {
        $videoUrl = GOOGLECAST_getYTVideoURLPython($ytUrl);
    };

    return $name."|".$videoUrl."|".$ytUrl;
}

### stop ###
sub GOOGLECAST_setStop {
    my ($hash) = @_;

    eval {
        $hash->{helper}{ccdevice}->{media_controller}->stop();
    };

    return undef;
}

### playFavorite ###
sub GOOGLECAST_setPlayFavorite {
    my ($hash, $favoriteNr) = @_;
    GOOGLECAST_setPlay($hash, AttrVal($hash->{NAME}, "favoriteURL_".$favoriteNr, ""));
    return undef;
}

### play ###
sub GOOGLECAST_setPlay {
    my ($hash, $url) = @_;

    if(!defined($url)) {
        eval {
            $hash->{helper}{ccdevice}->{media_controller}->play();
        };
        return undef;
    }


    if($url =~ /^http/) {
        #support streams are listed here
        #https://github.com/rg3/youtube-dl/blob/master/docs/supportedsites.md
        GOOGLECAST_setPlayMedia($hash, $url);
    } else {
        GOOGLECAST_playYouTube($hash->{helper}{ccdevice}, $url);
    }

    return undef;
}

### pause ###
sub GOOGLECAST_setPause {
    my ($hash) = @_;

    eval {
        $hash->{helper}{ccdevice}->{media_controller}->pause();
    };

    return undef;
}

### rewind ###
sub GOOGLECAST_setRewind {
    my ($hash) = @_;

    eval {
        $hash->{helper}{ccdevice}->{media_controller}->rewind();
    };

    return undef;
}

### skip ###
sub GOOGLECAST_setSkip {
    my ($hash) = @_;

    eval {
        $hash->{helper}{ccdevice}->{media_controller}->seek($hash->{helper}{ccdevice}->{media_controller}->{status}->{duration});
    };

    return undef;
}

### quitApp ###
sub GOOGLECAST_setQuitApp {
    my ($hash) = @_;

    eval {
        $hash->{helper}{ccdevice}->quit_app();
    };

    return undef;
}

sub GOOGLECAST_Undef($) {
    my ($hash) = @_;

    #remove internal timer
    RemoveInternalTimer($hash);

    return undef;
}

sub GOOGLECAST_Get($$) {
    return undef;
}

sub GOOGLECAST_updateReading {
    my ($hash, $readingName, $value) = @_;
    my $oldValue = ReadingsVal($hash->{NAME}, $readingName, "");

    if(!defined($value)) {
        $value = "";
    }

    if($oldValue ne $value) {
        readingsSingleUpdate($hash, $readingName, $value, 1);
    }
}

sub GOOGLECAST_newChash {
    my ($hash, $socket, $chash) = @_;

    $chash->{TYPE}  = $hash->{TYPE};
    $chash->{UDN}   = -1;

    $chash->{NR}    = $devcount++;

    $chash->{phash} = $hash;
    $chash->{PNAME} = $hash->{NAME};

    $chash->{CD}    = $socket;
    $chash->{FD}    = $socket->fileno();

    #$chash->{PORT}  = $socket->sockport if( $socket->sockport );

    $chash->{TEMPORARY} = 1;
    $attr{$chash->{NAME}}{room} = 'hidden';

    $defs{$chash->{NAME}}       = $chash;
    $selectlist{$chash->{NAME}} = $chash;
}

sub GOOGLECAST_addSocketToMainloop {
    my ($hash) = @_;
    my $sock;

    eval {
        $sock = $hash->{helper}{ccdevice}->{socket_client}->get_socket();
    };

    my $chash = GOOGLECAST_newChash($hash, $sock, {NAME => "GOOGLECAST-".$hash->{NAME}});
    return undef;
}

sub GOOGLECAST_checkConnection {
    my ($hash) = @_;

    eval {
        Log3 $hash, 5, "GOOGLECAST ($hash->{NAME}): run_once";
        $hash->{helper}{ccdevice}->{socket_client}->run_once();
    };

    if($@ || !defined($selectlist{"GOOGLECAST-".$hash->{NAME}})) {
        Log3 $hash, 4, "GOOGLECAST ($hash->{NAME}): checkConnection, connection failure, reconnect...";
        delete($selectlist{"GOOGLECAST-".$hash->{NAME}});
        $hash->{helper}{ccdevice}->{socket_client}->_cleanup();
        GOOGLECAST_initDevice($hash);
        GOOGLECAST_updateReading($hash, "presence", "offline");
        GOOGLECAST_updateReading($hash, "state", "offline");
        return undef;
    }

    InternalTimer(gettimeofday()+10, "GOOGLECAST_checkConnection", $hash, 0);
    return undef;
}


sub GOOGLECAST_Read {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $hash = $hash->{phash};

    eval {
        Log3 $hash, 5, "GOOGLECAST ($hash->{NAME}): run_once";
        $hash->{helper}{ccdevice}->{socket_client}->run_once();
    };

    if($@) {
        Log3 $hash, 4, "GOOGLECAST ($hash->{NAME}): connection failure, reconnect...";
        eval {
            delete($selectlist{$name});
        };
        $hash->{helper}{ccdevice}->{socket_client}->_cleanup();
        GOOGLECAST_initDevice($hash);
        GOOGLECAST_updateReading($hash, "presence", "offline");
        GOOGLECAST_updateReading($hash, "state", "offline");
        return undef;
    }

    GOOGLECAST_updateReading($hash, "presence", "online");
    GOOGLECAST_updateReading($hash, "name", $hash->{helper}{ccdevice}->{name});
    GOOGLECAST_updateReading($hash, "model", $hash->{helper}{ccdevice}->{model_name});
    GOOGLECAST_updateReading($hash, "uuid", $hash->{helper}{ccdevice}->{uuid});
    GOOGLECAST_updateReading($hash, "castType", $hash->{helper}{ccdevice}->{cast_type});
    GOOGLECAST_updateReading($hash, "model", $hash->{helper}{ccdevice}->{model_name});
    GOOGLECAST_updateReading($hash, "appId", $hash->{helper}{ccdevice}->{app_id});
    GOOGLECAST_updateReading($hash, "appName", $hash->{helper}{ccdevice}->{app_display_name});
    GOOGLECAST_updateReading($hash, "idle", $hash->{helper}{ccdevice}->{is_idle});

    my $newStatus = $hash->{helper}{ccdevice}->{media_controller}->{status};
    if(defined($newStatus)) {
        #GOOGLECAST_updateReading($hash, "mediaStatus", $newStatus);
        GOOGLECAST_updateReading($hash, "mediaPlayerState", $newStatus->{player_state});
        GOOGLECAST_updateReading($hash, "mediaContentId", $newStatus->{content_id});
        GOOGLECAST_updateReading($hash, "mediaDuration", $newStatus->{duration});
        GOOGLECAST_updateReading($hash, "mediaCurrentPosition", $newStatus->{current_time});
        GOOGLECAST_updateReading($hash, "mediaStreamType", $newStatus->{stream_type});
        GOOGLECAST_updateReading($hash, "mediaTitle", $newStatus->{title});
        GOOGLECAST_updateReading($hash, "mediaSeriesTitle", $newStatus->{series_title});
        GOOGLECAST_updateReading($hash, "mediaSeason", $newStatus->{season});
        GOOGLECAST_updateReading($hash, "mediaEpisode", $newStatus->{episode});
        GOOGLECAST_updateReading($hash, "mediaArtist", $newStatus->{artist});
        GOOGLECAST_updateReading($hash, "mediaAlbum", $newStatus->{album_name});
        GOOGLECAST_updateReading($hash, "mediaAlbumArtist", $newStatus->{album_artist});
        GOOGLECAST_updateReading($hash, "mediaTrack", $newStatus->{track});
        if(length($newStatus->{images}) > 0) {
            GOOGLECAST_updateReading($hash, "mediaImage", $newStatus->{images}[0]->{url});
        } else {
            GOOGLECAST_updateReading($hash, "mediaImage", "");
        }
    }

    my $newCastStatus = $hash->{helper}{ccdevice}->{status};
    if(defined($newCastStatus)) {
        #GOOGLECAST_updateReading($hash, "castStatus", $newCastStatus);
        GOOGLECAST_updateReading($hash, "volume", int($newCastStatus->{volume_level}*100));
    }

    my $curStatus = ReadingsVal($hash->{NAME}, "mediaPlayerState", "UNKNOWN");
    if($curStatus eq "PLAYING") {
        GOOGLECAST_updateReading($hash, "state", "playing");
    } elsif($curStatus eq "BUFFERING") {
        GOOGLECAST_updateReading($hash, "state", "buffering");
    } elsif($curStatus eq "PAUSED") {
        GOOGLECAST_updateReading($hash, "state", "paused");
    } else {
        GOOGLECAST_updateReading($hash, "state", ReadingsVal($hash->{NAME}, "presence", "offline"));
    }

    return undef;
}

use Inline Python => <<'PYTHON_CODE_END';

from __future__ import unicode_literals
import pychromecast
import time
import logging
import youtube_dl
import pychromecast.controllers.dashcast as dashcast
import pychromecast.controllers.youtube as youtube

def GOOGLECAST_findChromecastsPython():
    logging.basicConfig(level=logging.CRITICAL)
    return pychromecast.discovery.discover_chromecasts()

def GOOGLECAST_createChromecastPython(ip, port, uuid, model_name, friendly_name):
    logging.basicConfig(level=logging.CRITICAL)
    cast = pychromecast._get_chromecast_from_host((ip, int(port), uuid, model_name, friendly_name), blocking=False, timeout=0.1, tries=1, retry_wait=0.1)
    return cast

def GOOGLECAST_getYTVideoURLPython(yt_url):
    ydl = youtube_dl.YoutubeDL({'forceurl': True, 'simulate': True, 'quiet': '1', 'no_warnings': '1', 'skip_download': True, 'format': 'best', 'youtube_include_dash_manifest': False})

    with ydl:
        result = ydl.extract_info(
            yt_url,
            download=False # We just want to extract the info
    )

    if 'entries' in result:
        # Can be a playlist or a list of videos
        video = result['entries'][0]
    else:
        # Just a video
        video = result

    video_url = video['url']
    return video_url

def GOOGLECAST_loadDashCast(cast, url):
    d = dashcast.DashCastController()
    cast.register_handler(d)
    d.load_url(url,reload_seconds=60)

def GOOGLECAST_playYouTube(cast, videoId):
    yt = youtube.YouTubeController()
    cast.register_handler(yt)
    yt.play_video(videoId)


PYTHON_CODE_END

1;


=pod
=item device
=item summary Easily control your Google Cast devices (Video, Audio, Google Home)
=item summary_DE Einfache Steuerung deiner Google Cast Geräte (Video, Audio, Google Home)
=begin html

<a name="GOOGLECAST"></a>
<h3>GOOGLECAST</h3>
<ul>
  GOOGLECAST is used to control your Google Cast device<br><br>
        <b>Note</b><br>Following packages are required:
        <ul>
          <li>sudo apt-get install libwww-perl python-enum34 python-dev libextutils-makemaker-cpanfile-perl python-pip cpanminus</li>
          <li>sudo pip install netifaces</li>
          <li>sudo pip install enum34</li>
          <li>sudo pip install pychromecast --upgrade</li>
          <li>sudo pip install youtube-dl --upgrade</li>
          <li>sudo cpanm Inline::Python</li>
        </ul>

  <br>
  <br>
  <a name="GOOGLECASTdefine" id="GOOGLECASTdefine"></a>
    <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GOOGLECAST &lt;name&gt;</code><br>
    <br>
    Example:
    <ul>
      <code>define livingroom.chromecast GOOGLECAST livingroom</code><br><br>
      Wait a few seconds till presence switches to online...<br><br>
      <code>set livingroom.chromecast play https://www.youtube.com/watch?v=YE7VzlLtp-4</code><br>
    </ul>
    <br>
    Following media types are supported:<br>
    <a href="https://developers.google.com/cast/docs/media">Supported media formats</a><br>
    Play with youtube-dl works for following URLs:<br>
    <a href="https://rg3.github.io/youtube-dl/supportedsites.html">Supported youtube-dl sites</a><br>
    <br>
  </ul>

  <br>

  <a name="GOOGLECASTset" id="GOOGLECASTset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
               The following commands are defined:<br><br>
        <ul>
          <li><code><b>play</b> URL</code> &nbsp;&nbsp;-&nbsp;&nbsp; play from URL</li>
          <li><code><b>play</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; play, like resume if paused previsously</li>
          <li><code><b>playFavorite</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; plays URL from favoriteURL_[1-5]</li>
          <li><code><b>stop</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; stop, stops current playback</li>
          <li><code><b>pause</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; pause</li>
          <li><code><b>quitApp</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; quit current application, like YouTube</li>
          <li><code><b>skip</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; skip track and play next</li>
          <li><code><b>rewind</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; rewind track and play it again</li>
          <li><code><b>displayWebsite</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; displayWebsite on Chromecast Video</li>
          </ul>
    <br>
    </ul>
    
    <a name="GOOGLECASTattr" id="GOOGLECASTattr"></a>
        <b>Attributes</b>
          <ul>
            <li><code><b>favoriteURL_[1-5]</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; save URL to play afterwards with playFavorite [1-5]</li>
         </ul>
         <br>

    <a name="GOOGLECASTget" id="GOOGLECASTget"></a>
        <b>Get</b>
          <ul>
            <code>n/a</code>
         </ul>
         <br>

</ul>

=end html
=cut

