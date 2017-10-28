##############################################
#
# A module to control Kodi and receive events from Kodi.
# Requires XBMC "Frodo" 12.0.
# To use this module you will have to enable JSON-RPC. See http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC
# Also the Perl module JSON is required.
#
# written 2013 by Dennis Bokermann <dbn at gmx.de>
#
##############################################
# $Id$

package main;

use strict;
use warnings;
use POSIX;
use JSON;
use Data::Dumper;
use DevIo;
use IO::Socket::INET;
use MIME::Base64;

# majority of WindowNames according to http://kodi.wiki/view/Opening_Windows_and_Dialogs
our %KODI_WindowNames = (
    Settings                    => [ 'settings' ],
    # video
    VideoRoot                   => [ 'videos', 'library://video/' ],
    Movies                      => [ 'videos', 'videodb://movies/' ],
    MovieGenres                 => [ 'videos', 'videodb://movies/genres/' ],
    MovieTitles                 => [ 'videos', 'videodb://movies/titles/' ],
    MovieYears                  => [ 'videos', 'videodb://movies/years/' ],
    MovieActors                 => [ 'videos', 'videodb://movies/actors/' ],
    MovieDirectors              => [ 'videos', 'videodb://movies/directors/' ],
    MovieStudios                => [ 'videos', 'videodb://movies/studios/' ],
    MovieSets                   => [ 'videos', 'videodb://movies/sets/' ],
    MovieCountries              => [ 'videos', 'videodb://movies/countries/' ],
    MovieTags                   => [ 'videos', 'videodb://movies/tags/' ],
    RecentlyAddedMovies         => [ 'videos', 'videodb://recentlyaddedmovies/' ],
    TvShows                     => [ 'videos', 'videodb://tvshows/' ],
    TvShowGenres                => [ 'videos', 'videodb://tvshows/genres/' ],
    TvShowTitles                => [ 'videos', 'videodb://tvshows/titles/' ],
    TvShowYears                 => [ 'videos', 'videodb://tvshows/years/' ],
    TvShowActors                => [ 'videos', 'videodb://tvshows/actors/' ],
    TvShowStudios               => [ 'videos', 'videodb://tvshows/studios/' ],
    RecentlyAddedEpisodes       => [ 'videos', 'videodb://recentlyaddedepisodes/' ],
    InProgressTvShows           => [ 'videos', 'library://video/inprogressshows.xml/' ],    # !
    MusicVideos                 => [ 'videos', 'videodb://musicvideos/' ],
    MusicVideoGenres            => [ 'videos', 'videodb://musicvideos/genres/' ],
    MusicVideoTitles            => [ 'videos', 'videodb://musicvideos/titles/' ],
    MusicVideoYears             => [ 'videos', 'videodb://musicvideos/years/' ],
    MusicVideoArtists           => [ 'videos', 'videodb://musicvideos/artists/' ],
    MusicVideoAlbums            => [ 'videos', 'videodb://musicvideos/albums/' ],
    MusicVideoDirectors         => [ 'videos', 'videodb://musicvideos/directors/' ],
    MusicVideoStudios           => [ 'videos', 'videodb://musicvideos/studios/' ],
    RecentlyAddedMusicVideos    => [ 'videos', 'videodb://recentlyaddedmusicvideos/' ],
    VideoPlaylists              => [ 'videos', 'special://videoplaylists/' ],
    VideoAddons                 => [ 'videos', 'addons://sources/video/' ],
    VideoFiles                  => [ 'videos', 'sources://video/' ],
    
    # music
    MusicRoot                   => [ 'music', 'library://music/' ],
    Genres                      => [ 'music', 'musicdb://genres/' ],
    Artists                     => [ 'music', 'musicdb://artists/' ],
    Albums                      => [ 'music', 'musicdb://albums/' ],
    Song                        => [ 'music', 'musicdb://songs/' ],
    Top100                      => [ 'music', 'musicdb://top100/' ],
    Top100Songs                 => [ 'music', 'library://music/top100/top100songs.xml/' ],      # !
    Top100Albums                => [ 'music', 'library://music/top100/top100albums.xml/' ],     # !
    RecentlyAddedAlbums         => [ 'music', 'musicdb://recentlyaddedalbums/' ],
    RecentlyPlayedAlbums        => [ 'music', 'musicdb://recentlyplayedalbums/' ],
    Compilations                => [ 'music', 'musicdb://compilations/' ],
    Years                       => [ 'music', 'musicdb://years/' ],
    Singles                     => [ 'music', 'musicdb://singles/' ],
    MusicFiles                  => [ 'music', 'sources://music/' ],
    MusicPlaylists              => [ 'music', 'special://musicplaylists/' ],
    MusicAddons                 => [ 'music', 'addons://sources/audio/' ],
    
    # programs
    ProgramAddons               => [ 'programs', 'addons://sources/executable/' ],
    AndroidApps                 => [ 'programs', 'androidapp://sources/apps/' ],
    
    # addons
    Addons                      => [ 'addonbrowser' ],
    #UpdateAvailable             => [ 'addonbrowser', 'addons://outdated/' ],
    #CurrentlyDownloading        => [ 'addonbrowser', 'addons://downloading/' ],
    #RecentlyUpdated             => [ 'addonbrowser', 'addons://recently_updated/' ],
    #Repositories                => [ 'addonbrowser', 'addons://repos/' ],
    #InstallZip                  => [ 'addonbrowser', 'addons://install/' ],
    AddonSearch                 => [ 'addonbrowser', 'addons://search/' ],
    
    FileManager => [ 'filemanager' ],
    EventLog => [ 'eventlog' ],
    SubTitles => [ 'subtitlesearch' ],
    MovieInformation => [ 'movieinformation' ],
    
    # SystemInfo => [ 'settingssysteminfo' ],
    # Profile => [ 'settingsprofile' ],
    # Pictures => [ 'mypics' ],
    # Weather => [ 'myweather' ],
    # PVR => [ 'mypvrchannels' ],
);

#  genereate list of window names for the documentation
# Log 3, '<ul><li>'.join('</li><li>',sort keys(%KODI_WindowNames)).'</li></ul>';

sub KODI_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "KODI_Define";
  $hash->{SetFn}    = "KODI_Set";
  $hash->{ReadFn}   = "KODI_Read";  
  $hash->{ReadyFn}  = "KODI_Ready";
  $hash->{UndefFn}  = "KODI_Undefine";
  $hash->{AttrFn}   = "KODI_Attr";
  $hash->{AttrList} = "fork:enable,disable compatibilityMode:kodi,plex offMode:quit,hibernate,shutdown,suspend updateInterval disable:1,0 " . $readingFnAttributes;

  $data{RC_makenotify}{XBMC} = "KODI_RCmakenotify";
  $data{RC_layout}{KODI_RClayout}  = "KODI_RClayout";
}

sub KODI_Define($$)
{
  my ($hash, $def) = @_;
  DevIo_CloseDev($hash);
  my @args = split("[ \t]+", $def);
  if (int(@args) < 3) {
    return "Invalid number of arguments: define <name> KODI <ip[:port]> <http|tcp> [<username>] [<password>]";
  }
  my ($name, $type, $addr, $protocol, $username, $password) = @args;
  $hash->{Protocol} = $protocol;
  $hash->{NextID} = 1;
  $addr =~ /^(.*?)(:([0-9]+))?$/;  
  $hash->{Host} = $1;
  if(defined($3)) {
    $hash->{Port} = $3;
  }
  elsif($protocol eq 'tcp') {
    $hash->{Port} = 9090; #Default TCP Port
  }
  else {
    $hash->{Port} = 80;
  }
  $hash->{STATE} = 'Initialized';
  if($protocol eq 'tcp') {
    $hash->{DeviceName} = $hash->{Host} . ":" . $hash->{Port};
    my $dev = $hash->{DeviceName};
    $readyfnlist{"$name.$dev"} = $hash;
  }
  elsif(defined($username) && defined($password)) {    
    $hash->{Username} = $username;
    $hash->{Password} = $password;
  }
  else {
    return "Username and/or password missing.";
  }
  
  $attr{$hash->{NAME}}{"updateInterval"} = 60;
  
  return undef;
}

sub KODI_Attr($$$$)
{
  my ($cmd, $name, $attr, $value) = @_;
  my $hash = $defs{$name};
  
  if($attr eq "disable") {
    if($cmd eq "set" && ($value || !defined($value))) {
      KODI_Disconnect($hash);
      $hash->{STATE} = "Disabled";
    } else {
      if (AttrVal($hash->{NAME}, 'disable', 0)) {
        $hash->{STATE} = "Initialized";
        
        my $dev = $hash->{DeviceName};
        $readyfnlist{"$name.$dev"} = $hash;
      }
    }
  }

  return undef;
}

sub KODI_CreateId($) 
{
  my ($hash) = @_;
  my $res = $hash->{NextID};
  $hash->{NextID} = ($res >= 1000000) ? 1 : $res + 1;
  return $res;
}

# Force a connection attempt to KODI as soon as possible 
# (e.g. you know you just started it and want to connect immediately without waiting up to 60 s)
sub KODI_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  if($hash->{Protocol} ne 'tcp') {
    # we dont have a persistent connection anyway
    return undef;
  }
  
  if(AttrVal($hash->{NAME},'fork','disable') eq 'enable') {
    return undef unless $hash->{CHILDPID}; # nothing to do
    # well, the fork process does not respond to SIGTERM
    # so lets use SIGKILL to make things clear to it
    if ((kill SIGKILL, $hash->{CHILDPID}) != 1) { 
      Log3 3, $name, "KODI_Connect: ERROR: Unable to kill fork process!";
      return undef;
    }
    $hash->{CHILDPID} = undef; # undefg childpid so the Ready-func will fork again
  } else {
    $hash->{NEXT_OPEN} = 0; # force NEXT_OPEN used in DevIO
  }

  return undef;
}

# kills child process trying to connect (if existing)
sub KODI_KillConnectionChild($)
{
  my ($hash) = @_;

  return if !$hash->{CHILDPID};
    
  kill 'KILL', $hash->{CHILDPID};
  undef $hash->{CHILDPID};
}

sub KODI_Ready($)
{
  my ($hash) = @_;
  
  if (AttrVal($hash->{NAME}, 'disable', 0)) {
    return;
  }
  
  if($hash->{Protocol} eq 'tcp') {
    if(AttrVal($hash->{NAME},'fork','disable') eq 'enable') {
      if($hash->{CHILDPID} && !(kill 0, $hash->{CHILDPID})) {
        $hash->{CHILDPID} = undef;
        return DevIo_OpenDev($hash, 1, "KODI_Init");
      }
      elsif(!$hash->{CHILDPID}) {
        return if($hash->{CHILDPID} = fork);
        my $ppid = getppid();
    
        ### Copied from Blocking.pm
        foreach my $d (sort keys %defs) {   # Close all kind of FD
          my $h = $defs{$d};
          #the following line was added by vbs to not close parent's DbLog DB handle
          $h->{DBH}->{InactiveDestroy} = 1 if ($h->{TYPE} eq 'DbLog');
          TcpServer_Close($h) if($h->{SERVERSOCKET});
          if($h->{DeviceName}) {
            require "$attr{global}{modpath}/FHEM/DevIo.pm";
            DevIo_CloseDev($h,1);
          }
        }
        ### End of copied from Blocking.pm
    
        while(kill 0, $ppid) {
          DevIo_OpenDev($hash, 1, "KODI_ChildExit");
          sleep(5);
        }
        exit(0);
      }
    } else {
      return DevIo_OpenDev($hash, 1, "KODI_Init");
    }
  }
  return undef;
}

sub KODI_ChildExit($) 
{
   exit(0);
}

sub KODI_Undefine($$) 
{
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  KODI_Disconnect($hash);
  
  return undef;
}

sub KODI_Disconnect($)
{
  my ($hash) = @_;
  if($hash->{Protocol} eq 'tcp') {
    DevIo_CloseDev($hash); 
  }
  
  KODI_KillConnectionChild($hash);
}

sub KODI_Init($) 
{
  my ($hash) = @_;

  KODI_ResetPlayerReadings($hash);
        
  #since we just successfully connected to KODI I guess its safe to assume the device is awake
  readingsSingleUpdate($hash,"system","wake",1);
  $hash->{LAST_RECV} = time();
  
  KODI_Update($hash);
  
  KODI_QueueIntervalUpdate($hash);
  
  return undef;
}

sub KODI_QueueIntervalUpdate($;$) {
  my ($hash, $time) = @_;
  # AFAIK when using http this module is not using a persistent TCP connection
  
  return if(($hash->{Protocol} eq 'http') || ($hash->{STATE} eq "disconnected"));
  
  if (!defined($time)) {
    $time = AttrVal($hash->{NAME},'updateInterval',60);
  }
  RemoveInternalTimer($hash);
  InternalTimer(time() + $time, "KODI_Check", $hash, 0);
}

sub KODI_Check($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, "KODI_Check";

  return if(!KODI_CheckConnection($hash));
  
  KODI_Update($hash);
  
  #kodi seems alive if we get here. so keep bugging it
  KODI_QueueIntervalUpdate($hash);
}

sub KODI_UpdatePlayerItem($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
 
  Log3 $name, 4, "KODI_UpdatePlayerItem";
  if (($hash->{STATE} eq 'disconnected') or (ReadingsVal($name, "playStatus","") ne 'playing')) {
    Log3 $name, 4, "KODI_UpdatePlayerItem - cancelled (disconnected or not playing)";
    return;
  }
  
  KODI_PlayerGetItem($hash, -1);   
}

sub KODI_CheckConnection($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
 
  if ($hash->{STATE} eq "disconnected") {
    # we are already disconnected
    return 0;
  }

  my $lastRecvDiff = (time() - $hash->{LAST_RECV});
  my $updateInt = AttrVal($hash->{NAME},'updateInterval',60);
  
  # give it 50% tolerance. sticking hard to updateInt might fail if the fhem timer gets delayed for some seconds
  if ($lastRecvDiff > ($updateInt * 1.5)) {
    Log3 $name, 3, "KODI_CheckConnection: Connection lost! Last data from Kodi received $lastRecvDiff s ago";
    DevIo_Disconnected($hash);
    return 0;
  }
  Log3 $name, 4, "KODI_CheckConnection: Connection still alive. Last data from Kodi received $lastRecvDiff s ago";
  
  return 1;
}

sub KODI_Update($) 
{
  my ($hash) = @_;
  my $obj;
  $obj  = {
    "method" => "Application.GetProperties",
    "params" => { 
      "properties" => ["volume","muted","name","version"]
    }
  };
  KODI_Call($hash,$obj,1);

  $obj  = {
    "method" => "GUI.GetProperties",
    "params" => { 
      "properties" => ["skin","fullscreen", "stereoscopicmode"]
    }
  };
  KODI_Call($hash,$obj,1);

  # the playerId in the message is not reliable
  #   kodi is not able to assign the correct player so the playerid might be wrong
  #   http://forum.kodi.tv/showthread.php?tid=174872
  # so we ask for the acutally running players by passing -1
  KODI_PlayerUpdate($hash, -1);
  
  KODI_UpdatePlayerItem($hash);
}

sub KODI_PlayerUpdate($$) 
{
  my $hash = shift;
  my $playerid = shift;
  my $obj  = {
    "method" => "Player.GetProperties",
    "params" => { 
      "properties" => ["time","totaltime", "repeat", "shuffled", "speed" ]
    #"canseek", "canchangespeed", "canmove", "canzoom", "canrotate", "canshuffle", "canrepeat"
    }
  };
  push(@{$obj->{params}->{properties}}, 'partymode') if(AttrVal($hash->{NAME},'compatibilityMode','kodi') eq 'kodi');
  if($playerid >= 0) {    
    $obj->{params}->{playerid} = $playerid;
    KODI_Call($hash,$obj,1);
  }
  else {
    KODI_PlayerCommand($hash,$obj,0);
  }
}

sub KODI_PlayerGetItem($$) 
{
  my $hash = shift;
  my $playerid = shift;
  my $obj  = {
    "method" => "Player.GetItem",
    "params" => { 
      "properties" => ["artist", "album", "thumbnail", "file", "title",
                        "track", "year", "streamdetails", "tvshowid"]
    }
  };
  if($playerid >= 0) {    
    $obj->{params}->{playerid} = $playerid;
    KODI_Call($hash,$obj,1);
  }
  else {
    KODI_PlayerCommand($hash,$obj,0);
  }
}

sub KODI_Read($)
{
  my ($hash) = @_;
  my $buffer = DevIo_SimpleRead($hash);
  return if (not defined($buffer));
  return KODI_ProcessRead($hash, $buffer);
}

sub KODI_ProcessRead($$)
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};
  my $buffer = '';
  Log3($name, 5, "KODI_ProcessRead");

  #include previous partial message
  if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
    Log3($name, 5, "KODI_Read: PARTIAL: " . $hash->{PARTIAL});
    $buffer = $hash->{PARTIAL};
  }
  else {
    Log3($name, 5, "No PARTIAL buffer");
  }
  
  Log3($name, 5, "KODI_Read: Incoming data: " . $data);
  
  $buffer = $buffer  . $data;
  Log3($name, 5, "KODI_Read: Current processing buffer (PARTIAL + incoming data): " . $buffer);

  my ($msg,$tail) = KODI_ParseMsg($hash, $buffer);
  #processes all complete messages
  while($msg) {
    $hash->{LAST_RECV} = time();
    Log3($name, 4, "KODI_Read: Decoding JSON message. Length: " . length($msg) . " Content: " . $msg); 
    my $obj = JSON->new->utf8(0)->decode($msg);
    #it is a notification if a method name is present
    if(defined($obj->{method})) {
      KODI_ProcessNotification($hash,$obj);
    }
    elsif(defined($obj->{error})) {
        Log3($name, 3, "KODI_Read: Received error message: " . $msg);
    }
    #otherwise it is a answer of a request
    else {
        if (KODI_ProcessResponse($hash,$obj) == -1) {
            Log3($name, 2, "KODI_ProcessRead: Faulty message: $msg");
        }
    }
    ($msg,$tail) = KODI_ParseMsg($hash, $tail);
  }
  $hash->{PARTIAL} = $tail;
  Log3($name, 5, "KODI_Read: Tail: " . $tail);
  Log3($name, 5, "KODI_Read: PARTIAL: " . $hash->{PARTIAL});
  return;
}

sub KODI_ResetMediaReadings($)
{
  my ($hash) = @_;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "currentMedia", "" );
  readingsBulkUpdate($hash, "currentOriginaltitle", "" );
  readingsBulkUpdate($hash, "currentShowtitle", "" );
  readingsBulkUpdate($hash, "currentTitle", "" );
  readingsBulkUpdate($hash, "episode", "" );
  readingsBulkUpdate($hash, "episodeid", "" );
  readingsBulkUpdate($hash, "season", "" );
  readingsBulkUpdate($hash, "label", "" );
  readingsBulkUpdate($hash, "movieid", "" );
  readingsBulkUpdate($hash, "playlist", "" );
  readingsBulkUpdate($hash, "type", "" );
  readingsBulkUpdate($hash, "year", "" );
  readingsBulkUpdate($hash, "3dfile", "" );
  
  readingsBulkUpdate($hash, "currentAlbum", "" );
  readingsBulkUpdate($hash, "currentArtist", "" );
  readingsBulkUpdate($hash, "songid", "" );
  readingsBulkUpdate($hash, "currentTrack", "" );
  
  readingsEndUpdate($hash, 1);
  
  # delete streamdetails readings
  # NOTE: we actually delete the readings (unlike the other readings)
  #       because they are stream count dependent
  fhem("deletereading $hash->{NAME} sd_.*", 1);
}

sub KODI_ResetPlayerReadings($)
{
  my ($hash) = @_;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "time", "" );
  readingsBulkUpdate($hash, "totaltime", "" );
  readingsBulkUpdate($hash, "shuffle", "" );
  readingsBulkUpdate($hash, "repeat", "" );
  readingsBulkUpdate($hash, "speed", "" );
  readingsBulkUpdate($hash, "partymode", "" );
  
  readingsBulkUpdate($hash, "playStatus", "stopped" );
  readingsEndUpdate($hash, 1);
}

sub KODI_PlayerOnPlay($$)
{
  my ($hash,$obj) = @_;
  my $name = $hash->{NAME};
  my $id = KODI_CreateId($hash);
  my $type = $obj->{params}->{data}->{item}->{type};
  if(AttrVal($hash->{NAME},'compatibilityMode','kodi') eq 'plex' || !defined($obj->{params}->{data}->{item}->{id}) || $type eq "picture" || $type eq "unknown") {
    # we either got unknown or picture OR an item not in the library (id not existing)
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'playStatus','playing');
    readingsBulkUpdate($hash,'type',$type);
    if(defined($obj->{params}->{data}->{item})) {
      foreach my $key (keys %{$obj->{params}->{data}->{item}}) {
        my $value = $obj->{params}->{data}->{item}->{$key};
        KODI_CreateReading($hash,$key,$value);
      }
    }
    readingsEndUpdate($hash, 1);

    KODI_PlayerGetItem($hash, -1);
  } 
  elsif($type eq "song") {
    # 
    my $req = {
      "method" => "AudioLibrary.GetSongDetails",
      "params" => { 
        "songid" => $obj->{params}->{data}->{item}->{id},
        "properties" => ["artist","album","title","track","file"]
      },
      "id" => $id
    };
    my $event = {
      "name" => $obj->{method},
      "type" => "song",
      "event" => 'Player.OnPlay'
    };
    $hash->{PendingEvents}{$id} = $event;
    KODI_Call($hash, $req,1);
  }
  elsif($type eq "episode") {
    my $req = {
      "method" => "VideoLibrary.GetEpisodeDetails",
      "params" => { 
        "episodeid" => $obj->{params}->{data}->{item}->{id},
        #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Video.Fields.Episode
        "properties" => ["season","episode","title","showtitle","file"]
      },
      "id" => $id
    };
    my $event = {
      "name" => $obj->{method},
      "type" => "episode",
      "event" => 'Player.OnPlay'
    };
    $hash->{PendingEvents}{$id} = $event;
    KODI_Call($hash, $req,1);
  }
  elsif($type eq "movie") {
    my $req = {
      "method" => "VideoLibrary.GetMovieDetails",
      "params" => { 
        "movieid" => $obj->{params}->{data}->{item}->{id},
        #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Video.Fields.Movie
        "properties" => ["title","file","year","originaltitle","streamdetails"]
      },
      "id" => $id
    };
    my $event = {
      "name" => $obj->{method},
      "type" => "movie",
      "event" => 'Player.OnPlay'
    };
    $hash->{PendingEvents}{$id} = $event;
    KODI_Call($hash, $req,1);
  }
  elsif($type eq "musicvideo") {
    my $req = {
      "method" => "VideoLibrary.GetMusicVideoDetails",
      "params" => { 
        "musicvideoid" => $obj->{params}->{data}->{item}->{id},
        #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Video.Fields.MusicVideo
        "properties" => ["title","artist","album","file"]
      },
      "id" => $id
    };
    my $event = {
      "name" => $obj->{method},
      "type" => "musicvideo",
      "event" => 'Player.OnPlay'
    };
    $hash->{PendingEvents}{$id} = $event;
    KODI_Call($hash, $req,1);
  }
}

sub KODI_ProcessNotification($$) 
{
  my ($hash,$obj) = @_;
  my $name = $hash->{NAME};
  #React on volume change - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Application.OnVolumeChanged
  if($obj->{method} eq "Application.OnVolumeChanged") {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'volume',sprintf("%.2f", $obj->{params}->{data}->{volume}));
    readingsBulkUpdate($hash,'mute',($obj->{params}->{data}->{muted} ? 'on' : 'off'));
    readingsEndUpdate($hash, 1);
  } 
  #React on play, pause and stop
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnPlay
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnPause
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnStop
  elsif($obj->{method} eq "Player.OnPropertyChanged") {
    KODI_PlayerUpdate($hash,$obj->{params}->{data}->{player}->{playerid});
  }
  elsif($obj->{method} =~ /(Player\.OnSeek|Player\.OnSpeedChanged|Player\.OnPropertyChanged)/) {
    my $base = $obj->{params}->{data}->{player};
    readingsBeginUpdate($hash);
    foreach my $key (keys %$base) {
      my $item = $base->{$key};
      KODI_CreateReading($hash,$key,$item);
    }
    readingsEndUpdate($hash, 1);
  }
  elsif($obj->{method} eq "Player.OnStop") {
    readingsSingleUpdate($hash,"playStatus",'stopped',1);
	
	#HACK: We want to fetch GUI.Properties here to update for example stereoscopicmode.
	# When doing this here we still get the in-movie stereo mode. So we define a timer
	# to invoke the update in some (tm) seconds
    KODI_QueueIntervalUpdate($hash, 2);
  }
  elsif($obj->{method} eq "Player.OnPause") {
    readingsSingleUpdate($hash,"playStatus",'paused',1);
  }
  elsif($obj->{method} eq "Player.OnPlay") {
    KODI_ResetMediaReadings($hash);
    KODI_PlayerOnPlay($hash, $obj);
	KODI_Update($hash);
  }
  elsif($obj->{method} =~ /(Playlist|AudioLibrary|VideoLibrary|System).On(.*)/) {
    readingsSingleUpdate($hash,lc($1),lc($2),1);
    
    if (lc($1) eq "system") {
      if ((lc($2) eq "quit") or (lc($2) eq "restart") or (lc($2) eq "sleep")) {
          readingsSingleUpdate($hash, "playStatus", "stopped", 1);
      }
      
      if (lc($2) eq "sleep") {
        Log3($name, 3, "KODI notified that it is going to sleep");
        #if we immediatlely close our DevIO then fhem will instantly try to reconnect which might
        #succeed because KODI needs a moment to actually shutdown.
        #So cancel the current timer, fake that the last data has arrived ages ago
        #and force a connection check in some seconds when we think KODI actually has shut down
        $hash->{LAST_RECV} = 0;
        RemoveInternalTimer($hash);
        KODI_QueueIntervalUpdate($hash,  5);
      }
    }
  }
  return undef;
}  

sub KODI_ProcessResponse($$) 
{
  my ($hash,$obj) = @_;
  my $name = $hash->{NAME};
  my $id = $obj->{id};
  #check if the id of the answer matches the id of a pending event
  if(defined($hash->{PendingEvents}{$id})) {
    my $event = $hash->{PendingEvents}{$id};
    my $name = $event->{name};
    my $type = $event->{type};
    my $value = '';          
    my $base = '';
    $base = $obj->{result}->{songdetails} if($type eq 'song');
    $base = $obj->{result}->{episodedetails} if($type eq 'episode');
    $base = $obj->{result}->{moviedetails} if($type eq 'movie');
    $base = $obj->{result}->{musicvideodetails} if($type eq 'musicvideo');
    if($base) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,'playStatus','playing') if($event->{event} eq 'Player.OnPlay');
      readingsBulkUpdate($hash,'type',$type);
      foreach my $key (keys %$base) {
        my $item = $base->{$key};
        KODI_CreateReading($hash,$key,$item);
      }
      readingsEndUpdate($hash, 1);
    } 
    $hash->{PendingEvents}{$id} = undef;
  }
  elsif(exists($hash->{PendingPlayerCMDs}{$id})) {
    my $cmd = $hash->{PendingPlayerCMDs}{$id};
    my $players = $obj->{result};
    if (ref($players) ne "ARRAY") {
        my $keys = "";
        while ((my $k, my $v) = each %{ $hash->{PendingPlayerCMDs} } ) {
          $keys .= ",$k";
        }
        delete $hash->{PendingPlayerCMDs}{$id};
        Log3($name, 2, "KODI_ProcessResponse: Not received a player array! Pending command cancelled!");
        Log3($name, 2, "KODI_ProcessResponse: Keys in PendingPlayerCMDs: $keys");
        return -1;
    }
    foreach my $player (@$players) {
      $cmd->{id} = KODI_CreateId($hash);
      $cmd->{params}->{playerid} = $player->{playerid};
      KODI_Call($hash,$cmd,1);
    }
    delete $hash->{PendingPlayerCMDs}{$id};
  }  
  else {
    my $result = $obj->{result};
    if($result && $result ne 'OK') {
      readingsBeginUpdate($hash);
      foreach my $key (keys %$result) {
        if ($key eq 'item') {
          my $item = $obj->{result}->{item};
          foreach my $ikey (keys %$item) {
            my $value = $item->{$ikey};
            KODI_CreateReading($hash,$ikey,$value);
          }
        }
        else {
          my $value = $result->{$key};
          KODI_CreateReading($hash,$key,$value);
        }
      }
      readingsEndUpdate($hash, 1);
    }
  }
  return 0;
}

sub KODI_Is3DFile($$) {
  my ($hash, $filename) = @_;
  
  return ($filename =~ /([-. _]3d[-. _]|.*3dbd.*)/i);
}

sub KODI_CreateReading($$$);
sub KODI_CreateReading($$$) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $key = shift;
  my $value = shift;
  
  return if ($key =~ /(playerid)/);
  
  if($key eq 'version') {
    my $version = '';
    $version = $value->{major};
    $version .= '.' . $value->{minor} if(defined($value->{minor}));
    $version .= '-' . $value->{revision} if(defined($value->{revision}));
    $version .= ' ' . $value->{tag} if(defined($value->{tag}));
    $value = $version;
  }
  elsif($key eq 'skin') {
    $value = $value->{name} . '(' . $value->{id} . ')';
  }
  elsif($key =~ /(totaltime|time|seekoffset)/) {
    $value = sprintf('%02d:%02d:%02d.%03d',$value->{hours},$value->{minutes},$value->{seconds},$value->{milliseconds});
  }
  elsif($key eq 'shuffled') {
    $key = 'shuffle';
    $value = ($value ? 'on' : 'off');
  }
  elsif($key eq 'muted') {
    $key = 'mute';
    $value = ($value ? 'on' : 'off');
  }
  elsif($key eq 'speed') {
    readingsBulkUpdate($hash,'playStatus','playing') if $value != 0;
    readingsBulkUpdate($hash,'playStatus','paused') if $value == 0;
  }
  elsif($key =~ /(fullscreen|partymode)/) {
    $value = ($value ? 'on' : 'off');
  }
  elsif($key eq 'file') {
    $key = 'currentMedia';
    
    readingsBulkUpdate($hash,'3dfile', KODI_Is3DFile($hash, $value) ? "on" : "off");
  }
  elsif($key =~ /(album|artist|track|title)/) {
    $value = "" if $value eq -1;
    $key = 'current' . ucfirst($key);
  }
  elsif($key eq 'streamdetails') {
    foreach my $mediakey (keys %{$value}) {
      my $arrRef = $value->{$mediakey};
      for (my $i = 0; $i <= $#$arrRef; $i++) {
        my $propRef = $arrRef->[$i];
        foreach my $propkey (keys %{$propRef}) {
          readingsBulkUpdate($hash, "sd_" . $mediakey . $i . $propkey, $propRef->{$propkey});
        }
      }
    }
    
    # we dont want to create a "streamdetails" reading
    $key = undef; 
  }
  elsif($key eq 'stereoscopicmode') {
    $value = $value->{mode};
  }
  
  if(ref($value) eq 'ARRAY') {
    $value = join(',',@$value);
  }
  
  if (defined $key) {
    if ($key =~ /(seekoffset)/) {
      # for these readings we do only events - no readings
      DoTrigger($name, "$key: $value");
    }
    else {
      readingsBulkUpdate($hash,$key,$value) ;
    }
  }
}

#Parses a given string and returns ($msg,$tail). If the string contains a complete message 
#(equal number of curly brackets) the return value $msg will contain this message. The 
#remaining string is return in form of the $tail variable.
sub KODI_ParseMsg($$) 
{
  my ($hash, $buffer) = @_;
  my $name = $hash->{NAME};
  my $open = 0;
  my $close = 0;
  my $msg = '';
  my $tail = '';
  if($buffer) {
    foreach my $c (split //, $buffer) {
      if($open == $close && $open > 0) {
        $tail .= $c;
      }
      elsif(($open == $close) && ($c ne '{')) {
        Log3($name, 3, "KODI_ParseMsg: Garbage character before message: " . $c); 
      }
      else {
        if($c eq '{') {
          $open++;
        }
        elsif($c eq '}') {
          $close++;
        }
        $msg .= $c;
      }
    }
    if($open != $close) {
      $tail = $msg;
      $msg = '';
    }
  }
  return ($msg,$tail);
}

sub KODI_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  our %KODI_WindowNames;
  if($cmd eq "off") {
    $cmd = AttrVal($hash->{NAME},'offMode','quit');
  }
  if($cmd eq 'statusRequest') {
    return KODI_Update($hash);
  }
  #RPC referring to the Player - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player
  elsif($cmd eq 'playpause') {
    return KODI_Set_PlayPause($hash,@args);
  }
  elsif($cmd eq 'play') {
    return KODI_Set_PlayPause($hash,1, @args);
  }
  elsif($cmd eq 'pause') {
    return KODI_Set_PlayPause($hash,0, @args);
  }
  elsif($cmd eq 'prev') {
    return KODI_Set_Goto($hash,'previous', @args);
  }
  elsif($cmd eq 'next') {
    return KODI_Set_Goto($hash,'next', @args);
  }
  elsif($cmd eq 'goto') {
    return KODI_Set_Goto($hash, $args[0] - 1, $args[1]);
  }
  elsif($cmd eq 'stop') {
    return KODI_Set_Stop($hash, @args);
  }
  elsif($cmd eq 'opendir') {
    return KODI_Set_Open($hash, 'dir', @args);
  }
  elsif($cmd eq 'open') {
    return KODI_Set_Open($hash, 'file', @args);
  }
  elsif($cmd eq 'openmovieid') {
    return KODI_Set_Open($hash, 'movie', @args);
  }
  elsif($cmd eq 'openepisodeid') {
    return KODI_Set_Open($hash, 'episode', @args);
  }
  elsif($cmd eq 'openchannelid') {
    return KODI_Set_Open($hash, 'channel', @args);
  }
  elsif($cmd eq 'addon') {
    return KODI_Set_Addon($hash, @args);
  }
  elsif($cmd eq 'shuffle') {
    return KODI_Set_Shuffle($hash, @args);
  }
  elsif($cmd eq 'repeat') {
    return KODI_Set_Repeat($hash, @args);
  }
  elsif($cmd eq 'seek') {
    return KODI_Set_Seek($hash, $args[0], @args);
  }
  
  #RPC referring to the Input http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Input
  elsif($cmd eq 'back') {
    return KODI_Simple_Call($hash,'Input.Back');
  }
  elsif($cmd eq 'contextmenu') {
    return KODI_Simple_Call($hash,'Input.ContextMenu');
  }
  elsif($cmd eq 'down') {
    return KODI_Simple_Call($hash,'Input.Down');
  }
  elsif($cmd eq 'home') {
    return KODI_Simple_Call($hash,'Input.Home');
  }
  elsif($cmd eq 'info') {
    return KODI_Simple_Call($hash,'Input.Info');
  }
  elsif($cmd eq 'left') {
    return KODI_Simple_Call($hash,'Input.Left');
  }
  elsif($cmd eq 'right') {
    return KODI_Simple_Call($hash,'Input.Right');
  }
  elsif($cmd eq 'select') {
    return KODI_Simple_Call($hash,'Input.Select');
  }
  elsif($cmd eq 'send') {
    my $text = join(' ', @args);
    return KODI_Call($hash,{'method' => 'Input.SendText', 'params' => { 'text' => $text}},0);
  }
  elsif($cmd eq 'exec') {
    my $action = $args[0]; #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Input.Action
    return KODI_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => $action}},0);
  }
  elsif($cmd eq 'jsonraw') {
    my $action = join("",@args);
    return KODI_Call_raw($hash,$action,0);
  }
  elsif($cmd eq 'showcodec') {
    return KODI_Simple_Call($hash,'Input.ShowCodec');
  }
  elsif($cmd eq 'showosd') {
    return KODI_Simple_Call($hash,'Input.ShowOSD');
  }
  elsif($cmd eq 'up') {
    return KODI_Simple_Call($hash,'Input.Up');
  }
  
  #RPC referring to the GUI - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#GUI
  elsif($cmd eq 'msg') {
    return KODI_Set_Message($hash,@args);
  }
  
  #RPC referring to the Application - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Application
  elsif($cmd eq 'mute') {
    return KODI_Set_Mute($hash,@args);
  }
  elsif($cmd eq 'volume') {
    return KODI_Call($hash,{'method' => 'Application.SetVolume', 'params' => { 'volume' => int($args[0])}},0);
  }
  elsif($cmd eq 'volumeUp') {
    return KODI_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => 'volumeup'}},0);
  }
  elsif($cmd eq 'volumeDown') {
    return KODI_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => 'volumedown'}},0);
  }
  elsif($cmd eq 'quit') {
    return KODI_Simple_Call($hash,'Application.Quit');
  }
  
  #RPC referring to the System - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#System
  elsif($cmd eq 'eject') {
    return KODI_Simple_Call($hash,'System.EjectOpticalDrive');
  }
  elsif($cmd eq 'hibernate') {
    return KODI_Simple_Call($hash,'System.Hibernate');
  }
  elsif($cmd eq 'reboot') {
    return KODI_Simple_Call($hash,'System.Reboot');
  }
  elsif($cmd eq 'shutdown') {
    return KODI_Simple_Call($hash,'System.Shutdown');
  }
  elsif($cmd eq 'suspend') {
    return KODI_Simple_Call($hash,'System.Suspend');
  }
  
  #RPC referring to the VideoLibary - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#VideoLibrary
  elsif($cmd eq 'videolibrary') {
    my $opt = $args[0];
    if($opt eq 'clean') {
      return KODI_Simple_Call($hash,'VideoLibrary.Clean');
    }
    elsif($opt eq 'scan') {
      return KODI_Simple_Call($hash,'VideoLibrary.Scan');
    }
  }
  
  #RPC referring to the AudioLibary - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#AudioLibrary
  elsif($cmd eq 'audiolibrary') {
    my $opt = $args[0];
    if($opt eq 'clean') {
      return KODI_Simple_Call($hash,'AudioLibrary.Clean');
    }
    elsif($opt eq 'scan') {
        return KODI_Simple_Call($hash,'AudioLibrary.Scan');
    }
  }
  elsif($cmd eq 'connect') {
    return KODI_Connect($hash);
  }
  elsif($cmd eq 'activatewindow') {
    my $name = $args[0];

    my $window = $KODI_WindowNames{$name}[0];
    my $path = $KODI_WindowNames{$name}[1];
    my $params;
    if($path) {
      $params = {window => $window,parameters => [ $path ]};
    } else {
      $params = {window => $window};
    }
    
    return KODI_Call($hash,{ method => 'GUI.ActivateWindow', params => $params },1);
  }
  my $res = "Unknown argument " . $cmd . ", choose one of " . 
    "off play:all,audio,video,picture playpause:all,audio,video,picture pause:all,audio,video,picture " . 
    "prev:all,audio,video,picture next:all,audio,video,picture goto stop:all,audio,video,picture " . 
    "open opendir openmovieid openepisodeid openchannelid addon shuffle:toggle,on,off repeat:one,all,off volumeUp:noArg volumeDown:noArg " . 
    "seek back:noArg contextmenu:noArg down:noArg home:noArg info:noArg left:noArg " . 
    "right:noArg select:noArg send exec:left,right," . 
    "up,down,pageup,pagedown,select,highlight,parentdir,parentfolder,back," . 
    "previousmenu,info,pause,stop,skipnext,skipprevious,fullscreen,aspectratio," . 
    "stepforward,stepback,bigstepforward,bigstepback,osd,showsubtitles," . 
    "nextsubtitle,codecinfo,nextpicture,previouspicture,zoomout,zoomin," . 
    "playlist,queue,zoomnormal,zoomlevel1,zoomlevel2,zoomlevel3,zoomlevel4," . 
    "zoomlevel5,zoomlevel6,zoomlevel7,zoomlevel8,zoomlevel9,nextcalibration," . 
    "resetcalibration,analogmove,rotate,rotateccw,close,subtitledelayminus," . 
    "subtitledelay,subtitledelayplus,audiodelayminus,audiodelay,audiodelayplus," . 
    "subtitleshiftup,subtitleshiftdown,subtitlealign,audionextlanguage," . 
    "verticalshiftup,verticalshiftdown,nextresolution,audiotoggledigital," . 
    "number0,number1,number2,number3,number4,number5,number6,number7," . 
    "number8,number9,osdleft,osdright,osdup,osddown,osdselect,osdvalueplus," . 
    "osdvalueminus,smallstepback,fastforward,rewind,play,playpause,delete," . 
    "copy,move,mplayerosd,hidesubmenu,screenshot,rename,togglewatched,scanitem," . 
    "reloadkeymaps,volumeup,volumedown,mute,backspace,scrollup,scrolldown," . 
    "analogfastforward,analogrewind,moveitemup,moveitemdown,contextmenu,shift," . 
    "symbols,cursorleft,cursorright,showtime,analogseekforward,analogseekback," . 
    "showpreset,presetlist,nextpreset,previouspreset,lockpreset,randompreset," . 
    "increasevisrating,decreasevisrating,showvideomenu,enter,increaserating," . 
    "decreaserating,togglefullscreen,nextscene,previousscene,nextletter,prevletter," . 
    "jumpsms2,jumpsms3,jumpsms4,jumpsms5,jumpsms6,jumpsms7,jumpsms8,jumpsms9,filter," . 
    "filterclear,filtersms2,filtersms3,filtersms4,filtersms5,filtersms6,filtersms7," . 
    "filtersms8,filtersms9,firstpage,lastpage,guiprofile,red,green,yellow,blue," . 
    "increasepar,decreasepar,volampup,volampdown,channelup,channeldown," . 
    "previouschannelgroup,nextchannelgroup,leftclick,rightclick,middleclick," . 
    "doubleclick,wheelup,wheeldown,mousedrag,mousemove,noop showcodec:noArg showosd:noArg up:noArg " . 
    "msg " . 
    "mute:toggle,on,off volume:slider,0,1,100 quit:noArg " . 
    "eject:noArg hibernate:noArg reboot:noArg shutdown:noArg suspend:noArg " . 
    "videolibrary:scan,clean audiolibrary:scan,clean statusRequest jsonraw " .
    "connect:noArg " . 
    "activatewindow:".join(',',sort keys(%KODI_WindowNames));
  return $res ;
}

sub KODI_Simple_Call($$) {
  my ($hash,$method) = @_;
  return KODI_Call($hash,{'method' => $method},0);
}

sub KODI_Set_Open($@)
{
  my $hash = shift;
  my $opt = shift;
  my $params;
  my $path = join(' ', @_);
  $path = $1 if ($path =~ /^['"](.*)['"]$/);
  $path =~ s/\\/\\\\/g;
  if($opt eq 'file') {
    $params = { 
      'item' => {
        'file' => $path
      }
    };
  } elsif($opt eq 'dir') {
    $params = { 
      'item' => {
        'directory' => $path
      }
    };
  }  elsif($opt eq 'movie') {
    $params = { 
      'item' => {
        'movieid' => $path +0
      },
      'options' => {
        'resume' => JSON::true
      }
    };
  } elsif($opt eq 'episode') {
    $params = { 
      'item' => {
        'episodeid' => $path +0
      },
      'options' => {
        'resume' => JSON::true
       }
    };
  } elsif($opt eq 'channel') {
    $params = { 
      'item' => {
        'channelid' => $path +0
      },
    };
  }
  my $obj = {
    'method' => 'Player.Open',
    'params' => $params
  };
  return KODI_Call($hash,$obj,0);
}

sub KODI_Set_Addon($@)
{
  my $hash = shift;
  my $params;
  my $attr = join(" ", @_);
  $attr =~ /(".*?"|'.*?'|[^ ]+)[ \t]+(".*?"|'.*?'|[^ ]+)[ \t]+(".*?"|'.*?'|[^ ]+)$/;
  my $addonid = $1;
  my $paramname = $2;
  my $paramvalue = $3;
#  printf "$1 $2 $3";
  $params = { 
    'addonid' => $addonid,
    'params' => {
        $paramname => $paramvalue
      }
    };
  my $obj = {
    'method' => 'Addons.ExecuteAddon',
    'params' => $params
  };
  return KODI_Call($hash,$obj,0);
}

sub KODI_Set_Message($@)
{
  my $hash = shift;
  my $attr = join(" ", @_);
  $attr =~ /(".*?"|'.*?'|[^ ]+)[ \t]+(".*?"|'.*?'|[^ ]+)([ \t]+([0-9]+))?([ \t]+([^ ]*))?$/;
  my $title = $1;
  my $message = $2;
  my $duration = $4;
  my $image = $6;
  if($title =~ /^['"](.*)['"]$/) {
    $title = $1;
  }
  if($message =~ /^['"](.*)['"]$/) {
    $message = $1;
  }
  
  my $obj = {
    'method'  => 'GUI.ShowNotification',
    'params' => { 
      'title' => $title, 
      'message' => $message
    }
  };
  if($duration && $duration =~ /[0-9]+/ && int($duration) >= 1500) {
    $obj->{params}->{displaytime} = int($duration);
  }
  if($image) {
    $obj->{params}->{image} = $image;
  }
  return KODI_Call($hash, $obj,0);
}

sub KODI_Set_Stop($@)
{
  my ($hash,$player) = @_;
  my $obj = {
    'method'  => 'Player.Stop',
    'params' => { 
      'playerid' => 0 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_Set_Seek($@)
{
  my ($hash,$position,$player) = @_;
  my ($hours, $minutes, $seconds) = split(/:/, $position);
  my $obj = {
    'method'  => 'Player.Seek',
    'params' => { 
	  'value' => {
	  'seconds' => $seconds + 0,
	  'minutes' => $minutes + 0 ,
	  'hours' => $hours + 0
	  },
      'playerid' => 0 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_Set_Goto($$$)
{
  my ($hash,$direction,$player) = @_;
  my $obj = {
    'method'  => 'Player.GoTo',
    'params' => { 
      'to' => $direction, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_Set_Shuffle($@) 
{
  my ($hash,@args) = @_;
  my $toggle = 'toggle';
  my $player = '';
  if(int(@args) >= 2) {
    $toggle = $args[0];
    $player = $args[1];
  }
  elsif(int(@args) == 1) {
    if($args[0] =~ /(all|audio|video|picture)/) {
      $player = $args[0];
    }
    else {
      $toggle = $args[0];
    }
  }
  my $type = KODI_Toggle($toggle);
  
  my $obj = {
    'method'  => 'Player.SetShuffle',
    'params' => { 
      'shuffle' => $type, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_Set_Repeat($@) 
{
  my ($hash,$opt,@args) = @_;
  $opt = 'off' if($opt !~ /(one|all|off)/);
  my $player = '';
  if(int(@args) == 1 && $args[0] =~ /(all|audio|video|picture)/) {
      $player = $args[0];
  }
  
  my $obj = {
    'method'  => 'Player.SetRepeat',
    'params' => { 
      'repeat' => $opt, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_Set_PlayPause($@) 
{
  my ($hash,@args) = @_;
  my $toggle = 'toggle';
  my $player = '';
  if(int(@args) >= 2) {
    $toggle = $args[0];
    $player = $args[1];
  }
  elsif(int(@args) == 1) {
    if($args[0] =~ /(all|audio|video|picture)/) {
      $player = $args[0];
    }
    else {
      $toggle = $args[0];
    }
  }
  my $type = KODI_Toggle($toggle);
  
  my $obj = {
    'method'  => 'Player.PlayPause',
    'params' => { 
      'play' => $type, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return KODI_PlayerCommand($hash,$obj,$player);
}

sub KODI_PlayerCommand($$$) 
{
  my ($hash,$obj,$player) = @_;
  if($player) {
    my $id = -1;
    $id = 0 if($player eq "audio");
    $id = 1 if($player eq "video");
    $id = 2 if($player eq "picture");
    if($id > 0 && $id < 3) {
      $obj->{params}->{playerid} = $id;
      return KODI_Call($hash, $obj,0);
    }
  }
  
  #we need to find out the correct player first
  my $id = KODI_CreateId($hash);
  $hash->{PendingPlayerCMDs}->{$id} = $obj;
  my $req = {
    'method'  => 'Player.GetActivePlayers',
    'id' => $id
  };
  return KODI_Call($hash,$req,1);
}

#returns 'toggle' if the argument is undef
#returns JSON::true if the argument is true and not equals "off" otherwise it returns JSON::false
sub KODI_Toggle($) 
{
  my ($toggle) = @_;
  if(defined($toggle) && $toggle ne "toggle") {
    if($toggle && $toggle ne "off") {
      return JSON::true;
    }
    else {
      return JSON::false;
    } 
  }
  return 'toggle';
}

sub KODI_Set_Mute($@) 
{
  my ($hash,$toggle) = @_;
  my $type = KODI_Toggle($toggle);
  my $obj = {
    'method'  => 'Application.SetMute',
    'params' => { 'mute' => $type}
  };
  return KODI_Call($hash, $obj,0);
}

#Executes a JSON RPC
sub KODI_Call($$$)
{
  my ($hash,$obj,$id) = @_;
  my $name = $hash->{NAME};
  #add an ID otherwise KODI will not respond
  if($id &&!defined($obj->{id})) {
    $obj->{id} = KODI_CreateId($hash);
  }
  $obj->{jsonrpc} = "2.0"; #JSON RPC version has to be passed
  my $json = JSON->new->utf8(0)->encode($obj);
  Log3($name, 4, "KODI_Call: Sending: " . $json); 
  if($hash->{Protocol} eq 'http') {
    return KODI_HTTP_Call($hash,$json,$id);
  }
  else {
    return KODI_TCP_Call($hash,$json);
  }
}

sub KODI_Call_raw($$$)
{
  my ($hash,$obj,$id) = @_;
  my $name = $hash->{NAME};
  Log3($name, 5, "KODI_Call: Sending: " . $obj); 
  if($hash->{Protocol} eq 'http') {
    return KODI_HTTP_Call($hash,$obj,$id);
  }
  else {
    return KODI_TCP_Call($hash,$obj);
  }
}

sub KODI_RCmakenotify($$) {
  my ($nam, $ndev) = @_;
  my $nname="notify_$nam";
  
  fhem("define $nname notify $nam set $ndev ".'$EVENT',1);
  return "Notify created by KODI: $nname";
}

sub KODI_RClayout() {
  my @row;
  my $i = 0;
  $row[$i++] = "showosd:MENU,up:UP,home:HOMEsym,exec volumeup:VOLUP";
  $row[$i++] = "left:LEFT,select:OK,right:RIGHT,mute:MUTE";
  $row[$i++] = "info:INFO,down:DOWN,back:RETURN,exec volumedown:VOLDOWN";
  $row[$i++] = "exec stepback:REWIND,playpause:PLAY,stop:STOP,exec stepforward:FF";

  $row[$i++] = "attr rc_iconpath icons/remotecontrol";
  $row[$i++] = "attr rc_iconprefix black_btn_";
  return @row;
}


#JSON RPC over TCP
sub KODI_TCP_Call($$) 
{
  my ($hash,$obj) = @_;
  return DevIo_SimpleWrite($hash,$obj,'');
}

#JSON RPC over HTTP
sub KODI_HTTP_Call($$$) 
{
  my ($hash,$obj,$id) = @_;
  my $uri = "http://" . $hash->{Host} . ":" . $hash->{Port} . "/jsonrpc";
  my $ret = KODI_HTTP_Request(0,$uri,undef,$obj,undef,$hash->{Username},$hash->{Password});
  return undef if(!$ret);
  if($ret =~ /^error:(\d{3})$/) {
    return "HTTP Error Code " . $1;
  }
  return KODI_ProcessResponse($hash,JSON->new->utf8(0)->decode($ret)) if($id);
  return undef; 
}

#adapted version of the CustomGetFileFromURL subroutine from HttpUtils.pm
sub KODI_HTTP_Request($$@)
{
  my ($quiet, $url, $timeout, $data, $noshutdown,$username,$password) = @_;
  $timeout = 4.0 if(!defined($timeout));

  my $displayurl= $quiet ? "<hidden>" : $url;
  if($url !~ /^(http|https):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log(1, "KODI_HTTP_Request $displayurl: malformed or unsupported URL");
    return undef;
  }
  
  my ($protocol,$host,$port,$path)= ($1,$2,$3,$4);

  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($protocol eq "https" ? 443: 80);
  }
  $path= '/' unless defined($path);


  my $conn;
  if($protocol eq "https") {
    eval "use IO::Socket::SSL";
    if($@) {
      Log(1, $@);
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  if(!$conn) {
    Log(1, "KODI_HTTP_Request $displayurl: Can't connect to $protocol://$host:$port\n");
    undef $conn;
    return undef;
  }

  $host =~ s/:.*//;
  my $hdr = ($data ? "POST" : "GET")." $path HTTP/1.0\r\nHost: $host\r\n";
  if($username) {
    $hdr .= "Authorization: Basic ";
  if($password) {
    $hdr .= encode_base64($username . ":" . $password,"\r\n");
  }
  else {
    $hdr .= encode_base64($username,"\r\n");
  }
  }
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/json";
  }
  $hdr .= "\r\n\r\n";
  syswrite $conn, $hdr;
  syswrite $conn, $data if(defined($data));
  shutdown $conn, 1 if(!$noshutdown);

  my ($buf, $ret) = ("", "");
  $conn->timeout($timeout);
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $conn->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $timeout);
    if($nfound <= 0) {
      Log(1, "KODI_HTTP_Request $displayurl: Select timeout/error: $!");
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  my @header= split("\r\n", $1);
  my $hostpath= $quiet ? "<hidden>" : $host . $path;
  Log(4, "KODI_HTTP_Request $displayurl: Got data, length: ".length($ret));
  if(!length($ret)) {
    Log(4, "KODI_HTTP_Request $displayurl: Zero length data, header follows...");
    for (@header) {
        Log(4, "KODI_HTTP_Request $displayurl: $_");
    }
  }
  undef $conn;
  if($header[0] =~ /^[^ ]+ ([\d]{3})/ && $1 != 200) {
    return "error:" . $1;
  }
  return $ret;
}

1;

=pod
=item summary    control and receive events from Kodi
=item summary_DE Steuern und &uuml;berwachen von Kodi
=begin html

<a name="KODI"></a>
<h3>KODI</h3>
<ul>
  <a name="XBMCdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KODI &lt;ip[:port]&gt; &lt;http|tcp&gt; [&lt;username&gt;] [&lt;password&gt;]</code>
    <br><br>

    This module allows you to control Kodi and receive events from Kodi. It can also be used to control Plex (see attribute <i>compatibilityMode</i>).<br><br>
  
  <b>Prerequisites</b>
  <ul>
    <li>Requires XBMC "Frodo" 12.0.</li>
    <li>To use this module you will have to enable JSON-RPC. See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC">here</a>.</li>
    <li>The Perl module JSON is required. <br>
        On Debian/Raspbian: <code>apt-get install libjson-perl </code><br>
      Via CPAN: <code>cpan install JSON</code>
      To get it working on a Fritzbox the JSON module has to be installed manually.</li>
  </ul>

    To receive events it is necessary to use TCP. The default TCP port is 9090. Username and password are optional for TCP. Be sure to enable JSON-RPC 
  for TCP. See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC>here</a>.<br><br>
  
  If you just want to control Kodi you can use the HTTP instead of tcp. The username and password are required for HTTP. Be sure to enable JSON-RPC for HTTP.
    See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC">here</a>.<br><br>

    Example:<br><br>
    <ul>
    <code>
        define htpc KODI 192.168.0.10 tcp
        <br><br>
        define htpc KODI 192.168.0.10:9000 tcp # With custom port
        <br><br>
        define htpc KODI 192.168.0.10 http # Use HTTP instead of TCP - Note: to receive events use TCP!
        <br><br>
        define htpc KODI 192.168.0.10 http kodi passwd # Use HTTP with credentials - Note: to receive events use TCP!
      </code>
  </ul><br><br>
  
  Remote control:<br>
  There is an simple remote control layout for Kodi which contains the most basic buttons. To add the remote control to the webinterface execute the 
  following commands:<br><br>
  <ul>
    <code>
        define &lt;rc_name&gt; remotecontrol #adds the remote control
        <br><br>
        set &lt;rc_name&gt; layout KODI_RClayout #sets the layout for the remote control
        <br><br>
        set &lt;rc_name&gt; makenotify &lt;KODI_device&gt; #links the buttons to the actions
    </code>
  </ul><br><br>
  
  Known issues:<br>
    Kodi sometimes creates events twices. For example the Player.OnPlay event is created twice if play a song. Unfortunately this
    is a issue of Kodi. The fix of this bug is included in future version of Kodi (> 12.2).
   
  </ul>
  
  <a name="KODIset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    This module supports the following commands:<br>
    
  Player related commands:<br>
  <ul> 
    <li><b>play [&lt;all|audio|video|picture&gt;]</b> -  starts the playback (might only work if previously paused). The second argument defines which player should be started. By default the active players will be started</li>
    <li><b>pause [&lt;all|audio|video|picture&gt;]</b> -  pauses the playback</li>
    <li><b>playpause [&lt;all|audio|video|picture&gt;]</b> -  toggles between play and pause for the given player</li>
    <li><b>stop [&lt;all|audio|video|picture&gt;]</b> -  stop the playback</li>
    <li><b>next [&lt;all|audio|video|picture&gt;]</b> -  jump to the next track</li>
    <li><b>prev [&lt;all|audio|video|picture&gt;]</b> -  jump to the previous track or the beginning of the current track.</li>
    <li><b>goto &lt;position&gt; [&lt;audio|video|picture&gt;]</b> -  Goes to the <position> in the playlist. <position> has to be a number.</li>
    <li><b>shuffle [&lt;toggle|on|off&gt;] [&lt;audio|video|picture&gt;]</b> -  Enables/Disables shuffle mode. Without furhter parameters the shuffle mode is toggled.</li>
    <li><b>repeat &lt;one|all|off&gt; [&lt;audio|video|picture&gt;]</b> -  Sets the repeat mode.</li>
    <li><b>open &lt;URI&gt;</b> -  Plays the resource located at the URI (can be a url or a file)</li>
    <li><b>opendir &lt;path&gt;</b> -  Plays the content of the directory</li>
    <li><b>openmovieid &lt;path&gt;</b> -  Plays a movie by id</li>
    <li><b>openepisodeid &lt;path&gt;</b> -  Plays an episode by id</li>
    <li><b>openchannelid &lt;path&gt;</b> -  Switches to channel by id</li>
    <li><b>addon &lt;addonid&gt; &lt;parametername&gt; &lt;parametervalue&gt;</b> -  Executes addon with one Parameter, for example set kodi addon script.json-cec command activate</li>
    <li><b>seek &lt;hh:mm:ss&gt;</b> - seek to the specified time</li>
  </ul>
  <br>Input related commands:<br>
  <ul> 
    <li><b>back</b> -  Back-button</li>
    <li><b>down</b> -  Down-button</li>
    <li><b>up</b> -  Up-button</li>
    <li><b>left</b> -  Left-button</li>
    <li><b>right</b> -  Right-button</li>
    <li><b>home</b> -  Home-button</li>
    <li><b>select</b> -  Select-button</li>
    <li><b>info</b> -  Info-button</li>
    <li><b>showosd</b> -  Opens the OSD (On Screen Display)</li>
    <li><b>showcodec</b> -  Shows Codec information</li>
    <li><b>exec &lt;action&gt;</b> -  Execute an input action. All available actions are listed <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Input.Action">here</a></li>
    <li><b>send &lt;text&gt;</b> -  Sends &lt;text&gt; as input to Kodi</li>
    <li><b>jsonraw</b> -  Sends raw JSON data to Kodi</li>
  </ul>
  <br>Libary related commands:<br>
  <ul>
    <li><b>videolibrary clean</b> -  Removes non-existing files from the video libary</li>
    <li><b>videolibrary scan</b> -  Scan for new video files</li>
    <li><b>audiolibrary clean</b> -  Removes non-existing files from the audio libary</li>
    <li><b>audiolibrary scan</b> -  Scan for new audio files</li>
  </ul>
  <br>Application related commands:<br>
  <ul>
    <li><b>activatewindow &lt;name&gt;</b> - activates the window "name" of the following list:
        <ul><li>AddonSearch</li><li>Addons</li><li>Albums</li><li>AndroidApps</li><li>Artists</li><li>Compilations</li><li>EventLog</li><li>FileManager</li><li>Genres</li><li>InProgressTvShows</li><li>MovieActors</li><li>MovieCountries</li><li>MovieDirectors</li><li>MovieGenres</li><li>MovieInformation</li><li>MovieSets</li><li>MovieStudios</li><li>MovieTags</li><li>MovieTitles</li><li>MovieYears</li><li>Movies</li><li>MusicAddons</li><li>MusicFiles</li><li>MusicPlaylists</li><li>MusicRoot</li><li>MusicVideoAlbums</li><li>MusicVideoArtists</li><li>MusicVideoDirectors</li><li>MusicVideoGenres</li><li>MusicVideoStudios</li><li>MusicVideoTitles</li><li>MusicVideoYears</li><li>MusicVideos</li><li>ProgramAddons</li><li>RecentlyAddedAlbums</li><li>RecentlyAddedEpisodes</li><li>RecentlyAddedMovies</li><li>RecentlyAddedMusicVideos</li><li>RecentlyPlayedAlbums</li><li>Settings</li><li>Singles</li><li>Song</li><li>SubTitles</li><li>Top100</li><li>Top100Albums</li><li>Top100Songs</li><li>TvShowActors</li><li>TvShowGenres</li><li>TvShowStudios</li><li>TvShowTitles</li><li>TvShowYears</li><li>TvShows</li><li>VideoAddons</li><li>VideoFiles</li><li>VideoPlaylists</li><li>VideoRoot</li><li>Years</li></ul>
    </li>
    <li><b>mute [&lt;0|1&gt;]</b> -  1 for mute; 0 for unmute; by default the mute status will be toggled</li>
    <li><b>volume &lt;n&gt;</b> -  sets the volume to &lt;n&gt;. &lt;n&gt; must be a number between 0 and 100</li>
    <li><b>volumeDown &lt;n&gt;</b> -  volume down</li>
    <li><b>volumeUp &lt;n&gt;</b> -  volume up</li>
    <li><b>quit</b> -  closes Kodi</li>
    <li><b>off</b> -  depending on the value of the attribute &quot;offMode&quot; Kodi will be closed (see quit) or the system will be shut down, put into hibernation or stand by. Default is quit.</li>
  </ul>
  <br>System related commands:<br>
  <ul>
    <li><b>eject</b> -  will eject the optical drive</li>
    <li><b>shutdown</b> -  the Kodi host will be shut down</li>
    <li><b>suspend</b> -  the Kodi host will be put into stand by</li>
    <li><b>hibernate</b> -  the Kodi host will be put into hibernation</li>
    <li><b>reboot</b> -  the Kodi host will be rebooted</li>
    <li><b>connect</b> -  try to connect to the Kodi host immediately</li>
  </ul>
  </ul>
  <br><br>

  <u>Messaging</u>
  <ul>
    To show messages on Kodi (little message PopUp at the bottom right egde of the screen) you can use the following commands:<br>
    <code>set &lt;KODI_device&gt; msg &lt;title&gt; &lt;msg&gt; [&lt;duration&gt;] [&lt;icon&gt;]</code><br>
    The default duration of a message is 5000 (5 seconds). The minimum duration is 1500 (1.5 seconds). By default no icon is shown. Kodi provides three 
    different icon: error, info and warning. You can also use an uri to define an icon. Please enclose title and/or message into quotes (" or ') if it consists
    of multiple words.
  </ul>

  <br>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>audiolibrary</b> - Possible values: cleanfinished, cleanstarted, remove, scanfinished, scanstarted, update</li>
  <li><b>currentAlbum</b> - album of the current song/musicvideo</li>
  <li><b>currentArtist</b> - artist of the current song/musicvideo</li>
  <li><b>currentMedia</b> - file/URL of the media item being played</li>
  <li><b>currentTitle</b> - title of the current media item</li>
  <li><b>currentTrack</b> - track of the current song/musicvideo</li>
  <li><b>episode</b> - episode number</li>
  <li><b>episodeid</b> - id of the episode in the video library</li>
  <li><b>fullscreen</b> - indicates if Kodi runs in fullscreen mode (on/off)</li>
  <li><b>label</b> - label of the current media item</li>
  <li><b>movieid</b> - id of the movie in the video library</li>
  <li><b>musicvideoid</b> - id of the musicvideo in the video library</li>
  <li><b>mute</b> - indicates if Kodi is muted (on/off)</li>
  <li><b>name</b> - software name (e.g. Kodi)</li>
  <li><b>originaltitle</b> - original title of the movie being played</li>
  <li><b>partymode</b> - indicates if Kodi runs in party mode (on/off) (not available for Plex)</li>
  <li><b>playlist</b> - Possible values: add, clear, remove</li>
  <li><b>playStatus</b> - Indicates the player status: playing, paused, stopped</li>
  <li><b>repeat</b> - current repeat mode (one/all/off)</li>
  <li><b>season</b> - season of the current episode</li>
  <li><b>showtitle</b> - title of the show being played</li>
  <li><b>shuffle</b> - indicates if the playback is shuffled (on/off)</li>
  <li><b>skin</b> - current skin of Kodi</li>
  <li><b>songid</b> - id of the song in the music library</li>
  <li><b>system</b> - Possible values: lowbattery, quit, restart, sleep, wake</li>
  <li><b>time</b> - current position in the playing media item (only updated on play/pause)</li>
  <li><b>totaltime</b> - total run time of the current media item</li>
  <li><b>type</b> - type of the media item. Possible values: episode, movie, song, musicvideo, picture, unknown</li>
  <li><b>version</b> - version of Kodi</li>
  <li><b>videolibrary</b> - Possible values: cleanfinished, cleanstarted, remove, scanfinished, scanstarted, update</li>
  <li><b>volume</b> - value between 0 and 100 stating the current volume setting</li>
  <li><b>year</b> - year of the movie being played</li>
  <li><b>3dfile</b> - is a 3D movie according to filename</li>
  <li><b>sd_<type><n>_<reading></b> - stream details of the current medium. type can be video, audio or subtitle, n is the stream index (a stream can have multiple audio/video streams)</li>
  </ul>
  <br><br>
  <u>Remarks on the events</u><br><br>
  <ul>
    The event <b>playStatus = playing</b> indicates a playback of a media item. Depending on the event <b>type</b> different events are generated:
  <ul>
      <li><b>type = song</b> generated events are: <b>album, artist, file, title</b> and <b>track</b></li>  
    <li><b>type = musicvideo</b> generated events are: <b>album, artist, file</b> and <b>title</b></li> 
    <li><b>type = episode</b> generated events are: <b>episode, file, season, showtitle,</b> and <b>title</b></li>  
    <li><b>type = movie</b> generated events are: <b>originaltitle, file, title,</b> and <b>year</b></li> 
    <li><b>type = picture</b> generated events are: <b>file</b></li>  
    <li><b>type = unknown</b> generated events are: <b>file</b></li>  
  </ul> 
  </ul>
  <br><br>
  <a name="KODIattr"></a>
  <b>Attributes</b>
  <ul>
    <li>compatibilityMode<br>
      This module can also be used to control Plex, since the JSON Api is mostly the same, but there are some differences. 
    If you want to control Plex set the attribute <i>compatibilityMode</i> to <i>plex</i>.</li>
    <li>offMode<br>
      Declares what should be down if the off command is executed. Possible values are <i>quit</i> (closes Kodi), <i>hibernate</i> (puts system into hibernation), 
    <i>suspend</i> (puts system into stand by), and <i>shutdown</i> (shuts down the system). Default value is <i>quit</i></li>
  <li>fork<br>
      If Kodi does not run all the time it used to be the case that FHEM blocks because it cannot reach Kodi (only happened 
    if TCP was used). If you encounter problems like FHEM not responding for a few seconds then you should set <code>attr &lt;KODI_device&gt; fork enable</code>
    which will move the search for Kodi into a separate process.</li>
  <li>updateInterval<br>
      The interval which is used to check if Kodi is still alive (by sending a JSON ping) and also it is used to update current player item.</li>
  <li>disable<br>
      Disables the device. All connections will be closed immediately.</li>
  <li>jsonResponseReading<br>
      When enabled then every received JSON message from Kodi will be saved into the reading <i>jsonResponse</i> so the last received message is always available.
      Also an event is triggered upon each update.</li>
  </ul>
</ul>

=end html
=cut