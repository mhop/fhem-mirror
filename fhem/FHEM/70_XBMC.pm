##############################################
#
# A module to control XBMC and receive events from XBMC.
# Requires XBMC "Frodo" 12.0.
# To use this module you will have to enable JSON-RPC. See http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC
# Also the Perl module JSON is required.
#
# written 2013 by Dennis Bokermann <dbn at gmx.de>
#
##############################################


package main;

use strict;
use warnings;
use POSIX;
use JSON;
#use JSON::RPC::Client;
use Data::Dumper;
use DevIo;
use MIME::Base64;

sub XBMC_Initialize($$)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "XBMC_Define";
  $hash->{SetFn}    = "XBMC_Set";
  $hash->{ReadFn}   = "XBMC_Read";  
  $hash->{ReadyFn}  = "XBMC_Ready";
  $hash->{UndefFn}  = "XBMC_Undefine";
  $hash->{AttrList} = "fork:enable,disable offMode:quit,hibernate,shutdown,standby";
  
  $data{RC_makenotify}{XBMC} = "XBMC_RCmakenotify";
  $data{RC_layout}{XBMC_RClayout}  = "XBMC_RClayout";
}

sub XBMC_Define($$)
{
  my ($hash, $def) = @_;
  DevIo_CloseDev($hash);
  my @args = split("[ \t]+", $def);
  if (int(@args) < 3) {
    return "Invalid number of arguments: define <name> XBMC <ip[:port]> <http|tcp> [<username>] [<password>]";
  }
  my ($name, $type, $addr, $protocol, $username, $password) = @args;
  $hash->{Protocol} = $protocol;
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
  return undef;
}

sub XBMC_Ready($)
{
  my ($hash) = @_;
  if(AttrVal($hash->{NAME},'fork','disable') eq 'enable') {
    if($hash->{CHILDPID} && !(kill 0, $hash->{CHILDPID})) {
      $hash->{CHILDPID} = undef;
      return DevIo_OpenDev($hash, 1, "XBMC_Init");
    }
    elsif(!$hash->{CHILDPID}) {
      return if($hash->{CHILDPID} = fork);
	  my $ppid = getppid();
	  while(kill 0, $ppid) {
	    DevIo_OpenDev($hash, 1, "XBMC_ChildExit");
	    sleep(5);
	  }
	  exit(0);
    }
  } else {
    return DevIo_OpenDev($hash, 1, "XBMC_Init");
  }
  return undef;
}

sub XBMC_ChildExit($) 
{
   exit(0);
}

sub XBMC_Undefine($$) 
{
  my ($hash,$arg) = @_;
  if($hash->{Protocol} eq 'tcp') {
    DevIo_CloseDev($hash); 
  }
  return undef;
}

sub XBMC_Init($) 
{
  my ($hash) = @_;
  XBMC_Update($hash);
  return undef;
}

sub XBMC_Update($) 
{
  my ($hash) = @_;
  my $obj;
  $obj  = {
    "method" => "Application.GetProperties",
    "params" => { 
      "properties" => ["volume","muted","name","version"]
    }
  };
  XBMC_Call($hash,$obj,1);
  #$obj  = {
  #  "method" => "System.GetProperties",
  #  "params" => { 
  #    "properties" => ["canshutdown", "cansuspend", "canhibernate", "canreboot"]
  #  }
  #};
  #XBMC_Call($hash,$obj,1);
  $obj  = {
    "method" => "GUI.GetProperties",
    "params" => { 
      "properties" => ["skin","fullscreen"]
    }
  };
  XBMC_Call($hash,$obj,1);
  XBMC_PlayerUpdate($hash,0);
}

sub XBMC_PlayerUpdate($$) 
{
  my $hash = shift;
  my $playerid = shift;
  my $obj  = {
    "method" => "Player.GetProperties",
    "params" => { 
      "properties" => ["partymode", "totaltime", "repeat", "shuffled", "speed" ]
	  #"canseek", "canchangespeed", "canmove", "canzoom", "canrotate", "canshuffle", "canrepeat"
    }
  };
  if($playerid) {    
	$obj->{params}->{playerid} = $playerid;
    XBMC_Call($hash,$obj,1);
  }
  else {
    XBMC_PlayerCommand($hash,$obj,0);
  }
}

sub XBMC_Read($)
{
  my ($hash) = @_;
  my $buffer = '';
  #include previous partial message
  if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
    $buffer = $hash->{PARTIAL} . DevIo_SimpleRead($hash);
  }
  else {
    $buffer = DevIo_SimpleRead($hash);
  }
  my ($msg,$tail) = XBMC_ParseMsg($buffer);
  #processes all complete messages
  while($msg) {
    my $obj = decode_json($msg);
    Log 5, "XBMC received message:" . $msg;
	#it is a notification if a method name is present
    if(defined($obj->{method})) {
      XBMC_ProcessNotification($hash,$obj);
    }
	#otherwise it is a answer of a request
    else {
      XBMC_ProcessResponse($hash,$obj);
    }
    ($msg,$tail) = XBMC_ParseMsg($tail);
  }
  $hash->{PARTIAL} = $tail;
  Log 5, "Tail:" . $tail;
}

sub XBMC_ProcessNotification($$) 
{
  my ($hash,$obj) = @_;
  #React on volume change - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Application.OnVolumeChanged
  if($obj->{method} eq "Application.OnVolumeChanged") {
    readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,'volume',$obj->{params}->{data}->{volume});
	readingsBulkUpdate($hash,'mute',($obj->{params}->{data}->{muted} ? 'on' : 'off'));
	readingsEndUpdate($hash, 1);
  } 
  #React on play, pause and stop
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnPlay
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnPause
  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player.OnStop
  elsif($obj->{method} eq "Player.OnPropertyChanged") {
    XBMC_PlayerUpdate($hash,$obj->{params}->{data}->{player}->{playerid});
  }
  elsif($obj->{method} eq "Player.OnSeek") {
    #XBMC_PlayerUpdate($hash,$obj->{params}->{data}->{player}->{playerid});
	Log 3, "Discard Player.OnSeek event because it is irrelevant";
  }
  elsif($obj->{method} eq "Player.OnSpeedChanged") {
    #XBMC_PlayerUpdate($hash,$obj->{params}->{data}->{player}->{playerid});
	Log 3, "Discard Player.OnSpeedChanged event because it is irrelevant";
  }
  elsif($obj->{method} eq "Player.OnStop") {
    readingsSingleUpdate($hash,"playStatus",'stopped',1);
  }
  elsif($obj->{method} eq "Player.OnPause") {
    readingsSingleUpdate($hash,"playStatus",'paused',1);
  }
  elsif($obj->{method} eq "Player.OnPlay") {
    my $id = XBMC_CreateId();
    my $type = $obj->{params}->{data}->{item}->{type};
    if(!defined($obj->{params}->{data}->{item}->{id}) || $type eq "picture" || $type eq "unknown") {
	  readingsBeginUpdate($hash);
	  readingsBulkUpdate($hash,'playStatus','playing');
	  readingsBulkUpdate($hash,'type',$type);
	  if(defined($obj->{params}->{data}->{item}->{artist})) {
	    my $artist = $obj->{params}->{data}->{item}->{artist};
	    if(ref($artist) eq 'ARRAY') {
	      if(int(@$artist)) {
	        $artist = join(',',@$artist);
	      }
	    }
		readingsBulkUpdate($hash,'currentArtist', $artist);
	  }
	  readingsBulkUpdate($hash,'currentAlbum',$obj->{params}->{data}->{item}->{album}) if(defined($obj->{params}->{data}->{item}->{album}));
	  readingsBulkUpdate($hash,'currentTitle',$obj->{params}->{data}->{item}->{title}) if(defined($obj->{params}->{data}->{item}->{title}));
	  readingsBulkUpdate($hash,'currentTrack',$obj->{params}->{data}->{item}->{track}) if(defined($obj->{params}->{data}->{item}->{track}));
	  readingsBulkUpdate($hash,'currentMedia',$obj->{params}->{data}->{item}->{file}) if(defined($obj->{params}->{data}->{item}->{file}));
	  readingsEndUpdate($hash, 1);
	}	
    elsif($type eq "song") {
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
      XBMC_Call($hash, $req,1);
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
      XBMC_Call($hash, $req,1);
	}
	elsif($type eq "movie") {
      my $req = {
        "method" => "VideoLibrary.GetMovieDetails",
        "params" => { 
          "movieid" => $obj->{params}->{data}->{item}->{id},
		  #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Video.Fields.Movie
          "properties" => ["title","file","year","originaltitle"]
        },
        "id" => $id
      };
      my $event = {
        "name" => $obj->{method},
        "type" => "movie",
		"event" => 'Player.OnPlay'
      };
      $hash->{PendingEvents}{$id} = $event;
      XBMC_Call($hash, $req,1);
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
      XBMC_Call($hash, $req,1);
	}
	XBMC_PlayerUpdate($hash,$obj->{params}->{data}->{player}->{playerid});
  }
  elsif($obj->{method} =~ /(.*).On(.*)/) {
    readingsSingleUpdate($hash,lc($1),lc($2),1);
  }
  return undef;
}  

sub XBMC_ProcessResponse($$) 
{
  my ($hash,$obj) = @_;
  my $id = $obj->{id};
  #check if the id of the answer matches the id of a pending event
  if(defined($hash->{PendingEvents}{$id})) {
    my $event = $hash->{PendingEvents}{$id};
    my $name = $event->{name};
    my $type = $event->{type};
    my $value = '';          
	#include song details into the event details
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
	    if(ref($item) eq 'ARRAY') {
	      if(int(@$item)) {
	        readingsBulkUpdate($hash,$key,join(',',@$item));
	      }
	    }
	    else {
		  readingsBulkUpdate($hash,$key,$item);
	    }
	  }
	  readingsEndUpdate($hash, 1);
	} 
	$hash->{PendingEvents}{$id} = undef;
  }
  elsif(defined($hash->{PendingPlayerCMDs}{$id})) {
    my $cmd = $hash->{PendingPlayerCMDs}{$id};
	my $players = $obj->{result};
	foreach my $player (@$players) {
	  $cmd->{id} = XBMC_CreateId();
	  $cmd->{params}->{playerid} = $player->{playerid};
	  XBMC_Call($hash,$cmd,1);
	}
	$hash->{PendingPlayerCMDs}{$id} = undef;
  }  
  else {
    my $properties = $obj->{result};
	if($properties && $properties ne 'OK') {
	  readingsBeginUpdate($hash);
      foreach my $key (keys %$properties) {
	    my $value = $properties->{$key};
	    if($key eq 'version') {
	      $value = $value->{major} . '.' . $value->{minor} . '-' . $value->{revision} . ' ' . $value->{tag};
	    }
	    elsif($key eq 'skin') {
	      $value = $value->{name} . '(' . $value->{id} . ')';
	    }
		elsif($key eq 'totaltime') {
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
		}
		elsif($key =~ /(album|artist|track|title)/) {
		  $key = 'current' . ucfirst($key);
		}
	    readingsBulkUpdate($hash,$key,$value);
	  }
	  readingsEndUpdate($hash, 1);
	}
  }
  return undef;
}

#Parses a given string and returns ($msg,$tail). If the string contains a complete message 
#(equal number of curly brackets) the return value $msg will contain this message. The 
#remaining string is return in form of the $tail variable.
sub XBMC_ParseMsg($) 
{
  my ($buffer) = @_;
  my $open = 0;
  my $close = 0;
  my $msg = '';
  my $tail = '';
  if($buffer) {
    foreach my $c (split //, $buffer) {
      if($open == $close && $open > 0) {
        $tail .= $c;
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

sub XBMC_Set($@)
{
  my ($hash, $name, $cmd, @args) = @_;
  if($cmd eq "off") {
    $cmd = AttrVal($hash->{NAME},'offMode','quit');
  }
  if($cmd eq 'statusRequest') {
    return XBMC_Update($hash);
  }
  #RPC referring to the Player - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Player
  elsif($cmd eq 'playpause') {
    return XBMC_Set_PlayPause($hash,@args);
  }
  elsif($cmd eq 'play') {
    return XBMC_Set_PlayPause($hash,1, @args);
  }
  elsif($cmd eq 'pause') {
    return XBMC_Set_PlayPause($hash,0, @args);
  }
  elsif($cmd eq 'prev') {
    return XBMC_Set_Goto($hash,'previous', @args);
  }
  elsif($cmd eq 'next') {
    return XBMC_Set_Goto($hash,'next', @args);
  }
  elsif($cmd eq 'goto') {
    return XBMC_Set_Goto($hash, $args[0] - 1, $args[1]);
  }
  elsif($cmd eq 'stop') {
    return XBMC_Set_Stop($hash, @args);
  }
  elsif($cmd eq 'opendir') {
    return XBMC_Set_Open($hash, 'dir', @args);
  }
  elsif($cmd eq 'open') {
    return XBMC_Set_Open($hash, 'file', @args);
  }
  elsif($cmd eq 'shuffle') {
    return XBMC_Set_Shuffle($hash, @args);
  }
  elsif($cmd eq 'repeat') {
    return XBMC_Set_Repeat($hash, @args);
  }
  
  #RPC referring to the Input http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Input
  elsif($cmd eq 'back') {
    return XBMC_Simple_Call($hash,'Input.Back');
  }
  elsif($cmd eq 'contextmenu') {
    return XBMC_Simple_Call($hash,'Input.ContextMenu');
  }
  elsif($cmd eq 'down') {
    return XBMC_Simple_Call($hash,'Input.Down');
  }
  elsif($cmd eq 'home') {
    return XBMC_Simple_Call($hash,'Input.Home');
  }
  elsif($cmd eq 'info') {
    return XBMC_Simple_Call($hash,'Input.Info');
  }
  elsif($cmd eq 'left') {
    return XBMC_Simple_Call($hash,'Input.Left');
  }
  elsif($cmd eq 'right') {
    return XBMC_Simple_Call($hash,'Input.Right');
  }
  elsif($cmd eq 'select') {
    return XBMC_Simple_Call($hash,'Input.Select');
  }
  elsif($cmd eq 'send') {
    my $text = join(' ', @args);
    return XBMC_Call($hash,{'method' => 'Input.SendText', 'params' => { 'text' => $text}},0);
  }
  elsif($cmd eq 'exec') {
    my $action = $args[0]; #http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Input.Action
    return XBMC_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => $action}},0);
  }
  elsif($cmd eq 'showcodec') {
    return XBMC_Simple_Call($hash,'Input.ShowCodec');
  }
  elsif($cmd eq 'showosd') {
    return XBMC_Simple_Call($hash,'Input.ShowOSD');
  }
  elsif($cmd eq 'up') {
    return XBMC_Simple_Call($hash,'Input.Up');
  }
  
  #RPC referring to the GUI - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#GUI
  elsif($cmd eq 'msg') {
    return XBMC_Set_Message($hash,@args);
  }
  
  #RPC referring to the Application - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#Application
  elsif($cmd eq 'mute') {
    return XBMC_Set_Mute($hash,@args);
  }
  elsif($cmd eq 'volume') {
    return XBMC_Call($hash,{'method' => 'Application.SetVolume', 'params' => { 'volume' => int($args[0])}},0);
  }
  elsif($cmd eq 'volumeUp') {
    return XBMC_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => 'volumeup'}},0);
  }
  elsif($cmd eq 'volumeDown') {
    return XBMC_Call($hash,{'method' => 'Input.ExecuteAction', 'params' => { 'action' => 'volumedown'}},0);
  }
  elsif($cmd eq 'quit') {
    return XBMC_Simple_Call($hash,'Application.Quit');
  }
  
  #RPC referring to the System - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#System
  elsif($cmd eq 'eject') {
    return XBMC_Simple_Call($hash,'System.EjectOpticalDrive');
  }
  elsif($cmd eq 'hibernate') {
    return XBMC_Simple_Call($hash,'System.Hibernate');
  }
  elsif($cmd eq 'reboot') {
    return XBMC_Simple_Call($hash,'System.Reboot');
  }
  elsif($cmd eq 'shutdown') {
    return XBMC_Simple_Call($hash,'System.Shutdown');
  }
  elsif($cmd eq 'suspend') {
    return XBMC_Simple_Call($hash,'System.Suspend');
  }
  
  #RPC referring to the VideoLibary - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#VideoLibrary
  elsif($cmd eq 'videolibrary') {
    my $opt = $args[0];
	if($opt eq 'clean') {
      return XBMC_Simple_Call($hash,'VideoLibrary.Clean');
	}
	elsif($opt eq 'scan') {
	  return XBMC_Simple_Call($hash,'VideoLibrary.Scan');
	}
  }
  
  #RPC referring to the AudioLibary - http://wiki.xbmc.org/index.php?title=JSON-RPC_API/v6#AudioLibrary
  elsif($cmd eq 'audiolibrary') {
    my $opt = $args[0];
	if($opt eq 'clean') {
      return XBMC_Simple_Call($hash,'AudioLibrary.Clean');
	}
	elsif($opt eq 'scan') {
	  return XBMC_Simple_Call($hash,'AudioLibrary.Scan');
	}
  }
  my $res = "Unknown argument " . $cmd . ", choose one of " . 
	  "off play:all,audio,video,picture playpause:all,audio,video,picture pause:all,audio,video,picture " . 
	  "prev:all,audio,video,picture next:all,audio,video,picture goto stop:all,audio,video,picture " . 
	  "open opendir shuffle:toggle,on,off repeat:one,all,off volumeUp:noArg volumeDown:noArg " . 
	  "back:noArg contextmenu:noArg down:noArg home:noArg info:noArg left:noArg " . 
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
	  "videolibrary:scan,clean audiolibrary:scan,clean";
  return $res ;

}

sub XBMC_Simple_Call($$) {
  my ($hash,$method) = @_;
  return XBMC_Call($hash,{'method' => $method},0);
}

sub XBMC_Set_Open($@)
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
  }
  my $obj = {
    'method' => 'Player.Open',
    'params' => $params
  };
  return XBMC_Call($hash,$obj,0);
}

sub XBMC_Set_Message($@)
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
  return XBMC_Call($hash, $obj,0);
}

sub XBMC_Set_Stop($@)
{
  my ($hash,$player) = @_;
  my $obj = {
    'method'  => 'Player.Stop',
    'params' => { 
      'playerid' => 0 #will be replaced with the active player
    }
  };
  return XBMC_PlayerCommand($hash,$obj,$player);
}

sub XBMC_Set_Goto($$$)
{
  my ($hash,$direction,$player) = @_;
  my $obj = {
    'method'  => 'Player.GoTo',
    'params' => { 
      'to' => $direction, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return XBMC_PlayerCommand($hash,$obj,$player);
}

sub XBMC_Set_Shuffle($@) 
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
  my $type = XBMC_Toggle($toggle);
  
  my $obj = {
    'method'  => 'Player.SetShuffle',
    'params' => { 
      'shuffle' => $type, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return XBMC_PlayerCommand($hash,$obj,$player);
}

sub XBMC_Set_Repeat($@) 
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
  return XBMC_PlayerCommand($hash,$obj,$player);
}

sub XBMC_Set_PlayPause($@) 
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
  my $type = XBMC_Toggle($toggle);
  
  my $obj = {
    'method'  => 'Player.PlayPause',
    'params' => { 
      'play' => $type, 
      'playerid' => -1 #will be replaced with the active player
    }
  };
  return XBMC_PlayerCommand($hash,$obj,$player);
}

sub XBMC_PlayerCommand($$$) 
{
  my ($hash,$obj,$player) = @_;
  if($player) {
    my $id = -1;
    $id = 0 if($player eq "audio");
    $id = 1 if($player eq "video");
    $id = 2 if($player eq "picture");
	if($id > 0 && $id < 3) {
	  $obj->{params}->{playerid} = $id;
	  return XBMC_Call($hash, $obj,0);
	}
  }
  my $id = XBMC_CreateId();
  $hash->{PendingPlayerCMDs}->{$id} = $obj;
  my $req = {
    'method'  => 'Player.GetActivePlayers',
	'id' => $id
  };
  return XBMC_Call($hash,$req,1);
}

#returns 'toggle' if the argument is undef
#returns JSON::true if the argument is true and not equals "off" otherwise it returns JSON::false
sub XBMC_Toggle($) 
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

sub XBMC_Set_Mute($@) 
{
  my ($hash,$toggle) = @_;
  my $type = XBMC_Toggle($toggle);
  my $obj = {
    'method'  => 'Application.SetMute',
    'params' => { 'mute' => $type}
  };
  return XBMC_Call($hash, $obj,0);
}

#Executes a JSON RPC
sub XBMC_Call($$$)
{
  my ($hash,$obj,$id) = @_;
  #add an ID otherwise XBMC will not respond
  if($id &&!defined($obj->{id})) {
    $obj->{id} = XBMC_CreateId();
  }
  $obj->{jsonrpc} = "2.0"; #JSON RPC version has to be passed
  my $json = encode_json($obj);
  if($hash->{Protocol} eq 'http') {
    return XBMC_HTTP_Call($hash,$json,$id);
  }
  else {
    return XBMC_TCP_Call($hash,$json);
  }
}

sub XBMC_CreateId() 
{
  return int(rand(1000000));
}

sub XBMC_RCmakenotify($$) {
  my ($nam, $ndev) = @_;
  my $nname="notify_$nam";
  
  fhem("define $nname notify $nam set $ndev ".'$EVENT',1);
  return "Notify created by XBMC: $nname";
}

sub XBMC_RClayout() {
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
sub XBMC_TCP_Call($$) 
{
  my ($hash,$obj) = @_;
  return DevIo_SimpleWrite($hash,$obj,'');
}

#JSON RPC over HTTP
sub XBMC_HTTP_Call($$$) 
{
  my ($hash,$obj,$id) = @_;
  my $uri = "http://" . $hash->{Host} . ":" . $hash->{Port} . "/jsonrpc";
  my $ret = XBMC_HTTP_Request(0,$uri,undef,$obj,undef,$hash->{Username},$hash->{Password});
  if($ret =~ /^error:(\d){3}$/) {
    return "HTTP Error Code " . $1;
  }
  return XBMC_ProcessResponse($hash,decode_json($ret)) if($id);
  return undef;	
}

#adapted version of the CustomGetFileFromURL subroutine from HttpUtils.pm
sub XBMC_HTTP_Request($$@)
{
  my ($quiet, $url, $timeout, $data, $noshutdown,$username,$password) = @_;
  $timeout = 4.0 if(!defined($timeout));

  my $displayurl= $quiet ? "<hidden>" : $url;
  if($url !~ /^(http|https):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log 1, "XBMC_HTTP_Request $displayurl: malformed or unsupported URL";
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
      Log 1, $@;
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  if(!$conn) {
    Log 1, "XBMC_HTTP_Request $displayurl: Can't connect to $protocol://$host:$port\n";
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
      Log 1, "XBMC_HTTP_Request $displayurl: Select timeout/error: $!";
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
  Log 4, "XBMC_HTTP_Request $displayurl: Got data, length: ".length($ret);
  if(!length($ret)) {
    Log 4, "XBMC_HTTP_Request $displayurl: Zero length data, header follows...";
    for (@header) {
        Log 4, "XBMC_HTTP_Request $displayurl: $_";
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
=begin html

<a name="XBMC"></a>
<h3>XBMC</h3>
<ul>
  <a name="XBMCdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; XBMC &lt;ip[:port]&gt; &lt;http|tcp&gt; [&lt;username&gt;] [&lt;password&gt;]</code>
    <br><br>

    This module allows you to control XBMC and receive events from XBMC.<br><br>
	
	<b>Prerequisites</b>
	<ul>
	  <li>Requires XBMC "Frodo" 12.0.</li>
	  <li>To use this module you will have to enable JSON-RPC. See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC">here</a>.</li>
	  <li>The Perl module JSON is required. <br>
	      On Debian/Raspbian: <code>apt-get install libjson-perl </code><br>
		  Via CPAN: <code>cpan install JSON</code></li>
	</ul>

    To receive events it is necessary to use TCP. The default TCP port is 9090. Username and password are optional for TCP. Be sure to enable JSON-RPC 
	for TCP. See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC>here</a>.<br><br>
	
	If you just want to control XBMC you can use the HTTP instead of tcp. The username and password are required for HTTP. Be sure to enable JSON-RPC for HTTP.
    See <a href="http://wiki.xbmc.org/index.php?title=JSON-RPC_API#Enabling_JSON-RPC">here</a>.<br><br>

    Example:<br><br>
    <ul>
	  <code>
        define htpc XBMC 192.168.0.10 tcp
        <br><br>
        define htpc XBMC 192.168.0.10:9000 tcp # With custom port
        <br><br>
        define htpc XBMC 192.168.0.10 http # Use HTTP instead of TCP - Note: to receive events use TCP!
        <br><br>
        define htpc XBMC 192.168.0.10 http xbmc passwd # Use HTTP with credentials - Note: to receive events use TCP!
      </code>
	</ul><br><br>
	
	Remote control:<br>
	There is an simple remote control layout for XBMC which contains the most basic buttons. To add the remote control to the webinterface execute the 
	following commands:<br><br>
	<ul>
	  <code>
        define &lt;rc_name&gt; remotecontrol #adds the remote control
        <br><br>
        set &lt;rc_name&gt; layout XBMC_RClayout #sets the layout for the remote control
        <br><br>
        set &lt;rc_name&gt; makenotify &lt;XBMC_device&gt; #links the buttons to the actions
	  </code>
	</ul><br><br>
	
	Known issues:<br>
    XBMC sometimes creates events twices. For example the Player.OnPlay event is created twice if play a song. Unfortunately this
    is a issue of XBMC. The fix of this bug is included in future version of XBMC (> 12.2).
   
  </ul>
  
  <a name="XBMCset"></a>
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
	  <li><b>send &lt;text&gt;</b> -  Sends &lt;text&gt; as input to XBMC</li>
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
	  <li><b>mute [&lt;0|1&gt;]</b> -  1 for mute; 0 for unmute; by default the mute status will be toggled</li>
	  <li><b>volume &lt;n&gt;</b> -  sets the volume to &lt;n&gt;. &lt;n&gt; must be a number between 0 and 100</li>
	  <li><b>volumeDown &lt;n&gt;</b> -  volume down</li>
	  <li><b>volumeUp &lt;n&gt;</b> -  volume up</li>
	  <li><b>quit</b> -  closes XBMC</li>
	  <li><b>off</b> -  depending on the value of the attribute &quot;offMode&quot; XBMC will be closed (see quit) or the system will be shut down, put into hibernation or stand by. Default is quit.</li>
	</ul>
	<br>System related commands:<br>
	<ul>
	  <li><b>eject</b> -  will eject the optical drive</li>
	  <li><b>shutdown</b> -  the XBMC host will be shut down</li>
	  <li><b>suspend</b> -  the XBMC host will be put into stand by</li>
	  <li><b>hibernate</b> -  the XBMC host will be put into hibernation</li>
	  <li><b>reboot</b> -  the XBMC host will be rebooted</li>	
    </ul>
  </ul>
  <br><br>

  <u>Messaging</u>
  <ul>
    To show messages on XBMC (little message PopUp at the bottom right egde of the screen) you can use the following commands:<br>
    <code>set &lt;XBMC_device&gt; msg &lt;title&gt; &lt;msg&gt; [&lt;duration&gt;] [&lt;icon&gt;]</code><br>
    The default duration of a message is 5000 (5 seconds). The minimum duration is 1500 (1.5 seconds). By default no icon is shown. XBMC provides three 
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
	<li><b>fullscreen</b> - indicates if XBMC runs in fullscreen mode (on/off)</li>
	<li><b>label</b> - label of the current media item</li>
	<li><b>movieid</b> - id of the movie in the video library</li>
	<li><b>musicvideoid</b> - id of the musicvideo in the video library</li>
	<li><b>mute</b> - indicates if XBMC is muted (on/off)</li>
	<li><b>name</b> - software name (e.g. XBMC)</li>
	<li><b>originaltitle</b> - original title of the movie being played</li>
	<li><b>partymode</b> - indicates if XBMC runs in party mode (on/off)</li>
	<li><b>playlist</b> - Possible values: add, clear, remove</li>
	<li><b>playStatus</b> - Indicates the player status: playing, paused, stopped</li>
	<li><b>repeat</b> - current repeat mode (one/all/off)</li>
	<li><b>season</b> - season of the current episode</li>
	<li><b>showtitle</b> - title of the show being played</li>
	<li><b>shuffle</b> - indicates if the playback is shuffled (on/off)</li>
	<li><b>skin</b> - current skin of XBMC</li>
	<li><b>songid</b> - id of the song in the music library</li>
	<li><b>system</b> - Possible values: lowbattery, quit, restart, sleep, wake</li>
	<li><b>totaltime</b> - total run time of the current media item</li>
	<li><b>type</b> - type of the media item. Possible values: episode, movie, song, musicvideo, picture, unknown</li>
	<li><b>version</b> - version of XBMC</li>
	<li><b>videolibrary</b> - Possible values: cleanfinished, cleanstarted, remove, scanfinished, scanstarted, update</li>
	<li><b>volume</b> - value between 0 and 100 stating the current volume setting</li>
	<li><b>year</b> - year of the movie being played</li>
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
  <a name="XBMCattr"></a>
  <b>Attributes</b>
  <ul>
    <li>offMode<br>
      Declares what should be down if the off command is executed. Possible values are <i>quit</i> (closes XBMC), <i>hibernate</i> (puts system into hibernation), 
	  <i>suspend</i> (puts system into stand by), and <i>shutdown</i> (shuts down the system). Default value is <i>quit</i></li>
	<li>fork<br>
      If XBMC does not run all the time it used to be the case that FHEM blocks because it cannot reach XBMC (only happened 
	  if TCP was used). If you encounter problems like FHEM not responding for a few seconds then you should set <code>attr &lt;XBMC_device&gt; fork enable</code>
	  which will move the search for XBMC into a separate process.</li>
  </ul>
</ul>

=end html
=cut
