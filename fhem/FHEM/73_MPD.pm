################################################################
#
#  $Id$
#
#  (c) 2014 Copyright: Wzut
#  All rights reserved
#
#  FHEM Forum : http://forum.fhem.de/index.php/topic,18517.msg400328.html#msg400328
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

# Version 1.32   - 03.01.17
# Version 1.31   - 30.12.16
# Version 1.3    - 14.12.16
# Version 1.2    - 10.04.16
# Version 1.1    - 03.02.16
# Version 1.01   - 18.08.14
# add set toggle command
# Version 1.0    - 21.02.14
# add german doc , readings & state times only on change, devStateIcon
# Version 0.95   - 17.02.14
# add command set IdleNow
# Version 0.9    - 15.02.14
# Version 0.8    - 01.02.14 , first version 


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use URI::Escape;
use POSIX;
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
use IO::Socket;
use Getopt::Std;
use HttpUtils;
use XML::Simple qw(:strict);
use HTML::Entities;

sub MPD_html($);

my %gets = (
	"music:noArg"          => "",
	"playlists:noArg"      => "",
	"playlistinfo:noArg"   => "",
	"statusRequest:noArg"  => "",
	"currentsong:noArg"    => "",
	"outputs:noArg"        => "",
	);

my %sets = (
	"play"                  => "",
	"clear:noArg"           => "",
	"stop:noArg"            => "",
	"pause:noArg"           => "",
	"previous:noArg"        => "",
	"next:noArg"            => "",
	"random:noArg"          => "",
	"repeat:noArg"          => "",
	"volume:slider,0,1,100" => "",
	"volumeUp:noArg"        => "",
	"volumeDown:noArg"      => "",
	"playlist"              => "",
	"playfile"              => "",
	"updateDb:noArg"        => "",
	"mpdCMD"                => "",
	"reset:noArg"           => "",
	"single:noArg"          => "",
	"IdleNow:noArg"         => "",
	"toggle:noArg"          => "",
	"clear_readings:noArg"  => "",
	);

use constant clb => "command_list_begin\n";
use constant cle => "status\nstats\ncurrentsong\ncommand_list_end";
use constant lfm => "http://ws.audioscrobbler.com/2.0/?method=artist.getinfo&api_key=";

###################################

sub MPD_Initialize($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
  
	$hash->{GetFn}        = "MPD_Get";
	$hash->{SetFn}        = "MPD_Set";
	$hash->{DefFn}        = "MPD_Define";
	$hash->{UndefFn}      = "MPD_Undef";
	$hash->{ShutdownFn}   = "MPD_Undef";
	$hash->{AttrFn}       = "MPD_Attr";
	$hash->{AttrList}     = "disable:0,1 password loadMusic:0,1 loadPlaylists:0,1 volumeStep:1,2,5,10 titleSplit:1,0 timeout waits stateMusic:0,1 statePlaylists:0,1 lastfm_api_key image_size:-1,0,1,2,3 cache artist_summary:0,1 artist_content:0,1 player:mpd,mopidy,forked-daapd ".$readingFnAttributes;
	$hash->{FW_summaryFn} = "MPD_summaryFn";
}

sub MPD_updateConfig($)
{
	# this routine is called 5 sec after the last define of a restart
	# this gives FHEM sufficient time to fill in attributes

	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (!$init_done)
	{
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+5,"MPD_updateConfig", $hash, 0);
		return;
	}

	my $error;
	$hash->{".playlist"}     = "";
	$hash->{".playlists"}    = "";
	$hash->{".musiclist"}    = "";
	$hash->{".music"}        = "";
	$hash->{".outputs"}      = "";
	$hash->{".lasterror"}    = "";
	$hash->{PRESENCE}        = "absent";
	$hash->{".volume"}       =  -1;
        $hash->{".artist"}       = "";
    
	$hash->{".password"} = AttrVal($name, "password", "");
	$hash->{TIMEOUT}     = AttrVal($name, "timeout", 2);
	$hash->{".sMusicL"}  = AttrVal($name, "stateMusic", 1);
	$hash->{".sPlayL"}   = AttrVal($name, "statePlaylists", 1);
        $hash->{".apikey"}   = AttrVal($name, "lastfm_api_key", "f3a26c7c8b4c4306bc382557d5c04ad5");
        $hash->{".player"}   = AttrVal($name, "player", "mpd");
    
        delete($gets{"music:noArg"}) if ($hash->{".player"} eq "mopidy");
    
	## kommen wir via reset Kommando ?
	if ($hash->{".reset"})
	{
		$hash->{".reset"} = 0;
		RemoveInternalTimer($hash);
		if(defined($hash->{IPID}))
		{
		    BlockingKill($hash->{helper}{RUNNING_PID});
		    Log3 $name,4, "$name, Idle Kill PID : ".$hash->{IPID};
		    delete $hash->{helper}{RUNNING_PID};
		    delete $hash->{IPID};
		    Log3 $name,4,"$name, Reset done";
		}
	} 

	if (IsDisabled($name))
	{
		readingsSingleUpdate($hash,"state","disabled",1);
		return undef;
	}

	MPD_ClearReadings($hash); # beim Starten etwas aufräumen
        MPD_Outputs_Status($hash);

        if ((AttrVal($name, "icon_size", -1) > -1) && (AttrVal($name, "cache", "") ne ""))
        {
          my $cache = AttrVal($name, "cache", "");
          unless(-e ("./www/".$cache) or mkdir ("./www/".$cache)) 
          {
           #Verzeichnis anlegen gescheitert
           Log3 $name,3,"$name, Could not create directory: www/$cache";
          }
          #else {Log3 $name,4,"$name, lastfm cache =  www/$cache";}
        }

	if (MPD_try_idle($hash)) 
	{ 
	#   Playlisten und Musik Dir laden ?
        #   nicht bei Player mopidy, listall wird von ihm nicht unterstützt !
	    if ((AttrVal($name, "loadMusic", "1") eq "1") && !$error && ($hash->{".player"} ne "mopidy"))
	    { 
		$error = mpd_cmd($hash, "i|listall|music");
		Log3 $name,3,"$name, error loading music -> $error" if ($error);
		readingsSingleUpdate($hash,"error",$error,1) if ($error);
	    }
	    if ((AttrVal($name, "loadPlaylists", "1") eq "1") && !$error)
	    {
		$error = mpd_cmd($hash, "i|lsinfo|playlists");
		Log3 $name,3,"$name, error loading playlists -> $error" if ($error);
		readingsSingleUpdate($hash,"error",$error,1) if ($error);
	    }  
  
	}
	else { readingsSingleUpdate($hash,"state","error",1);}

	return undef;
}

sub MPD_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> $name [<MPD ip-address>] [<MPD port-nr>]" if(int(@a) > 4);

  $hash->{HOST} = (defined($a[2])) ? $a[2] : "127.0.0.1";
  $hash->{PORT} = (defined($a[3])) ? $a[3] : "6600" ;
 
  $hash->{".reset"}  = 0;
  
  Log3 $name,3,"$name, Device defined.";
  readingsSingleUpdate($hash,"state","defined",1);

  $attr{$name}{devStateIcon} = 'play:rc_PLAY:stop stop:rc_STOP:play pause:rc_PAUSE:pause error:icoBlitz' unless (exists($attr{$name}{devStateIcon}));
  $attr{$name}{icon}         = 'it_radio' unless (exists($attr{$name}{icon})); 
  $attr{$name}{titleSplit}   = '1'        unless (exists($attr{$name}{titleSplit}));
  $attr{$name}{player}       = 'mpd'      unless (exists($attr{$name}{player}));
  $attr{$name}{loadPlaylists} = '1'       unless (exists($attr{$name}{loadPlaylists}));
  #$attr{$name}{cache}        = 'lfm'      unless (exists($attr{$name}{cache}));
  #$attr{$name}{loadMusic}     = '1'  unless (exists($attr{$name}{loadMusic})) && ($attr{$name}{player} ne 'mopidy');

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "MPD_updateConfig", $hash, 0);

  return undef;
}

sub MPD_Undef ($$) 
{

 my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);
 if(defined($hash->{helper}{RUNNING_PID}))
 {
  BlockingKill($hash->{helper}{RUNNING_PID});
 }

 return undef;
}

sub MPD_Attr (@) 
{

 my ($cmd, $name, $attrName, $attrVal) = @_;
 my $hash = $defs{$name};

 if ($cmd eq "set")
 {
   if ($attrName eq "timeout")
   {
     if (int($attrVal) < 1) {$attrVal = 1;}
     $hash->{TIMEOUT}      = $attrVal;
     $attr{$name}{timeout} = $attrVal;
   }
   elsif ($attrName eq "password")
   {
       $hash->{".password"}   = $attrVal;
       $attr{$name}{password} = $attrVal;
   }
   elsif (($attrName eq "disable") && ($attrVal == 1))
   {
       readingsSingleUpdate($hash,"state","disabled",1);
       $attr{$name}{disable} = $attrVal;
   }
   elsif (($attrName eq "disable") && ($attrVal == 0))
   {
       $attr{$name}{disable} = $attrVal;
       readingsSingleUpdate($hash,"state","reset",1);
       $hash->{".reset"} = 1;
       MPD_updateConfig($hash);      
   }
   elsif ($attrName eq "statePlaylists")
   {
       $attr{$name}{statePlaylists} = $attrVal;
       $hash->{".sPlayL"}=$attrVal;
   }
   elsif ($attrName eq "stateMusic")
   {
       $attr{$name}{stateMusic} = $attrVal;
       $hash->{".sMusicL"}=$attrVal;
   }
   elsif ($attrName eq "player")
   {
       $attr{$name}{player} = $attrVal;
       $hash->{".player"}=$attrVal;
   }
   elsif ($attrName eq "cache")
   {
    unless(-e ("./www/".$attrVal) or mkdir ("./www/".$attrVal)) 
    {
     #Verzeichnis anlegen gescheitert
     return "Could not create directory: www/$attrVal";
    }
    $attr{$name}{cache} = $attrVal;
   }
 }
 elsif ($cmd eq "del")
 {
  if ($attrName eq "disable")
  {
      $attr{$name}{disable} = 0;
      readingsSingleUpdate($hash,"state","reset",1);
      $hash->{".reset"}=1;
      MPD_updateConfig($hash);      
  }
  elsif ($attrName eq "statePlaylists") { $hash->{".sPlayL"}  = 1; }
  elsif ($attrName eq "stateMusic")     { $hash->{".sMusicL"} = 1; }
  elsif ($attrName eq "player")         { $hash->{".player"}  = "mpd"; }
 }

   return undef;
}

sub MPD_ClearReadings($)
{
    my ($hash)= @_;
    readingsBeginUpdate($hash);
    if ($hash->{".player"} eq "forked-daapd")
    {
     readingsBulkUpdate($hash,"albumartistsort","");
     readingsBulkUpdate($hash,"artistsort","");
    }
    #readingsBulkUpdate($hash,"albumartist","");
    readingsBulkUpdate($hash,"Album","");
    readingsBulkUpdate($hash,"Artist","");
    readingsBulkUpdate($hash,"file","");
    readingsBulkUpdate($hash,"Genre","");
    readingsBulkUpdate($hash,"Last-Modified","");
    readingsBulkUpdate($hash,"Title","");
    readingsBulkUpdate($hash,"Name","");
    readingsBulkUpdate($hash,"Date","");
    readingsBulkUpdate($hash,"Track","");
    readingsBulkUpdate($hash,"playlistname","");
    #readingsBulkUpdate($hash,"artist_image","/fhem/icons/1px-spacer", "");
    #readingsBulkUpdate($hash,"artist_image_html","");
    readingsBulkUpdate($hash,"artist_summary","")  if (AttrVal($hash->{NAME}, "artist_summary",""));
    readingsBulkUpdate($hash,"artist_content","")  if (AttrVal($hash->{NAME}, "artist_content",""));
    readingsEndUpdate($hash, 0);
    return;
}

sub MPD_Set($@)
{
 my ($hash, @a)= @_;
 my $name= $hash->{NAME};
 my $ret ;
 
 return join(" ", sort keys %sets) if(@a < 2);
 return undef if(IsDisabled($name));

 my $cmd = $a[1];
 return join(" ", sort keys %sets) if ($cmd eq "?");

 if ($cmd eq "mpdCMD") 
 {
   my $sub;
   shift @a;
   shift @a;
   $sub = join (" ", @a);
  return $name." ".$sub.":\n".mpd_cmd($hash, "i|$sub|x");
 }

 my $subcmd = (defined($a[2])) ? $a[2] : "";
 return undef if ($subcmd eq '---'); # erster Eintrag im select Feld ignorieren

 my $step    = int(AttrVal($name, "volumeStep", 5)); # vllt runtersetzen auf default = 2 ?
 my $vol_now = int($hash->{".volume"});
 my $vol_new;
  
 if ($cmd eq "reset")   { $hash->{".reset"} = 1; MPD_updateConfig($hash); return undef;}
 if ($cmd eq "pause")   { $ret = mpd_cmd($hash, clb."pause\n".cle);  return $ret; }
 if ($cmd eq "update")  { $ret = mpd_cmd($hash, clb."update\n".cle); return $ret; }

 if ($cmd eq "stop")    
  { 
   readingsSingleUpdate($hash,"artist_image","/fhem/icons/1px-spacer",1);
   readingsSingleUpdate($hash,"artist_image_html","",1);
   $ret = mpd_cmd($hash, clb."stop\n".cle);   
   return $ret; 
  }
 

 if ($cmd eq "toggle")  
  { 
    $ret = mpd_cmd($hash, clb."play\n".cle) if (($hash->{STATE} eq "stop") || ($hash->{STATE} eq "pause")); 
    if  ($hash->{STATE} eq "play")
    { 
     readingsSingleUpdate($hash,"artist_image","/fhem/icons/1px-spacer",1);
     readingsSingleUpdate($hash,"artist_image_html","",1);
     $ret = mpd_cmd($hash, clb."stop\n".cle);
    }
  }

 if ($cmd eq "previous")
 { 
    if (defined($hash->{READINGS}{"song"}{VAL}) > 0)
    {
     MPD_ClearReadings($hash);
     $ret = mpd_cmd($hash, clb."previous\n".cle); 
    } 
    else { return undef; }
 }
 
 if ($cmd eq "next")
 { 
  if ($hash->{READINGS}{"nextsong"}{VAL} != $hash->{READINGS}{"song"}{VAL})
   {
    MPD_ClearReadings($hash);
    $ret = mpd_cmd($hash, clb."next\n".cle);
   } 
   else { return undef; } 
 }

 if ($cmd eq "random")  
  { 
    my $rand = ($hash->{READINGS}{random}{VAL}) ? "0" : "1";
    $ret = mpd_cmd($hash, clb."random $rand\n".cle);
  }

 if ($cmd eq "repeat")  
  { 
    my $rep = ($hash->{READINGS}{repeat}{VAL}) ? "0" : "1";
    $ret = mpd_cmd($hash, clb."repeat $rep\n".cle);
  }

 if ($cmd eq "single")  
  { 
    my $single = ($hash->{READINGS}{single}{VAL}) ? "0" : "1";
    $ret = mpd_cmd($hash, clb."single $single\n".cle);  
  }

 if ($cmd eq "clear")   
  { 
    MPD_ClearReadings($hash);
    $ret = mpd_cmd($hash, clb."clear\n".cle);
    $hash->{".music"} = ""; 
    $hash->{".playlist"} = ""; 
  }

 if ($cmd eq "volume")    
  { 
   if (int($subcmd) > 100) { $vol_new = "100"; }
     elsif (int($subcmd) <   0) { $vol_new =   "0"; }
       else { $vol_new = $subcmd; }
   # sollte nun zwischen 0 und 100 sein 
  }

 if ($cmd eq "volumeUp")   { $vol_new = (($vol_now + $step) <= 100) ? $vol_now+$step : "100"; }
 if ($cmd eq "volumeDown") { $vol_new = (($vol_now - $step) >=   0) ? $vol_now-$step : "  0"; }

 # muessen wir die Laustärke verändern ?
 if (defined($vol_new)) 
 { 
   $ret = mpd_cmd($hash, clb."setvol $vol_new\n".cle); 
 }

 # einfaches Play bzw Play Listenplatz Nr. ?
 if ($cmd eq "play") 
  {
    MPD_ClearReadings($hash);
    $ret = mpd_cmd($hash,clb."play $subcmd\n".cle); 
  }

 if ($cmd eq "IdleNow")   
 {
  return "$name: sorry, a Idle process is always running with pid ".$hash->{IPID} if(defined($hash->{IPID}));
  MPD_try_idle($hash);
  return undef;
 }

 if ($cmd eq "clear_readings")   
 {
  MPD_ClearReadings($hash);
  return undef;
 }

 # die ersten beiden brauchen wir nicht mehr
 shift @a;
 shift @a;
   
 # den Rest als ein String
 $subcmd = join(" ",@a);

 if ($cmd eq "playlist") 
 {
   return "$name : no name !" if (!$subcmd);

   MPD_ClearReadings($hash);
   $hash->{".music"}    = "";
   my $old_list = $hash->{".playlist"};
   $hash->{".playlist"} = $subcmd; # interne Playlisten Verwaltung
   readingsSingleUpdate($hash,"playlistname",$subcmd,1);
   $ret = mpd_cmd($hash, clb."stop\nclear\nload \"$subcmd\"\nplay\n".cle);
   if ($old_list ne $hash->{".playlist"})
   {
    MPD_NewPlaylist($hash,mpd_cmd($hash, "i|playlistinfo|x|"));
   }
 }

 if ($cmd eq "playfile")
 {
   return "$name, no File !" if (!$subcmd);

   MPD_ClearReadings($hash);

   $hash->{".playlist"} = "";
   readingsSingleUpdate($hash,"playlistname","",1);
   $hash->{".music"}    = $subcmd; # interne Song Verwaltung
   
   $ret = mpd_cmd($hash, clb."stop\nclear\nadd \"$subcmd\"\nplay\n".cle);
 }

 if ($cmd eq "updateDb")
 {
   $ret = mpd_cmd($hash, clb."rescan\n".cle);
 }

 if ($cmd eq "mpd_event") 
 {  
  if ($subcmd)
  {
   #MPD_ClearReadings($hash) if (index($subcmd,"playlist") != -1);
   readingsSingleUpdate($hash,"mpd_event",$subcmd,1);
  }
   
  mpd_cmd($hash, clb.cle);
  return undef;
 }

  if (substr($cmd,0,13) eq "outputenabled")
  {
   my $oid = substr($cmd,13,1);
   if ($subcmd eq "1")
    {
     $ret = mpd_cmd($hash, "i|enableoutput $oid|x");
     Log3  $name , 5, "enableoutput $oid | $subcmd";
    }
     else
    {
     $ret = mpd_cmd($hash, "i|disableoutput $oid|x");
     Log3  $name , 5 ,"disableoutput $oid | $subcmd";
    }
   
   MPD_Outputs_Status($hash);
  }
  return $ret;
}



sub MPD_Get($@)
{
 my ($hash, @a)= @_;
 my $name= $hash->{NAME};
 my $ret;
 my $cmd;

 return "get $name needs at least one argument" if(int(@a) < 2);

 $cmd = $a[1];

 return(MPD_html($hash)) if ($cmd eq "webrc"); 

 return "no get cmd on a disabled device !" if(IsDisabled($name));

 if ($cmd eq "playlists")
  { 
    $hash->{".playlists"} = "";
    mpd_cmd($hash, "i|lsinfo|playlists");
    return format_get_output("Playlists",$hash->{".playlists"});

  }
 
 if ($cmd eq "music")         
  {
    return "Command not supported by player mopidy !" if ($hash->{".player"} eq "mopidy");
    $hash->{".musiclist"} = "";
    mpd_cmd($hash, "i|listall|music"); 
    return format_get_output("Music",$hash->{".musiclist"});
  }

  if ($cmd eq "statusRequest") 
  {  
    mpd_cmd($hash, clb.cle);
    $ret = mpd_cmd($hash, "i|".clb.cle."|x|s");
    return format_get_output("Status Request", $ret) if($ret);
    return undef;
  }

 if ($cmd eq "outputs") 
  {  
    MPD_Outputs_Status($hash);
    return format_get_output("Outputs", $hash->{".outputs"});
  }

  return format_get_output("Current Song", mpd_cmd($hash, "i|currentsong|x")) if ($cmd eq "currentsong");
  return format_get_output("Playlist Info",mpd_cmd($hash, "i|playlistinfo|x")) if ($cmd eq "playlistinfo");
  return "$name get with unknown argument $cmd, choose one of " . join(" ", sort keys %gets); 
}


sub format_get_output($$)
{
 my ($head,$ret)= @_;
 my $width = 10;
 my @arr = split("\n",$ret);
 #my @sort = sort(@arr);
 
 foreach(@arr) { $width = length($_) if(length($_) > $width); }
 return $head."\n".("-" x $width)."\n".$ret;
}

sub MPD_Outputs_Status($)
{
 my ($hash)= @_;
 my $name = $hash->{NAME};
 $hash->{".outputs"} = mpd_cmd($hash, "i|outputs|x");
 my @outp = split("\n" , $hash->{".outputs"});
 readingsBeginUpdate($hash);
 my $outpid = "0";
 foreach (@outp)
 {
   my @val = split(": " , $_);
   Log3  $name, 4 ,"$name: MPD_Outputs_Status -> $val[0] = $val[1]";
   $outpid = ($val[0] eq "outputid") ? $val[1] : $outpid;
   readingsBulkUpdate($hash,$val[0].$outpid,$val[1]) if ($val[0] ne "outputid");
   $sets{$val[0].$outpid.":0,1"} = "" if ($val[0] eq "outputenabled");
 }
 readingsEndUpdate($hash, 1);
}

sub mpd_cmd($$)
{

 my ($hash,$a)= @_;
 my $output = "";
 my $sp;
 my $artist;
 my $name      = $hash->{NAME};
 my $playlists = $hash->{".playlists"};


 $hash->{VERSION}   = undef;
 $hash->{PRESENCE}  = "absent";


 my $sock = IO::Socket::INET->new(
    PeerHost => $hash->{HOST},
    PeerPort => $hash->{PORT},
    Proto    => 'tcp',
    Timeout  => $hash->{TIMEOUT});

 if (!$sock) 
 { 
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","error");
  readingsBulkUpdate($hash,"error",$!);
  readingsBulkUpdate($hash,"presence","absent"); # MPD ist wohl tot :(
  readingsEndUpdate($hash, 1 );
  Log3 $name, 2 , "$name, cmd error : ".$!;
  return $!; 
 }

 while (<$sock>)  # MPD rede mit mir , egal was ;)
 { last if $_ ; } # end of output.

 chomp $_;

 return  "not a valid mpd server, welcome string was: ".$_ if $_ !~ /^OK MPD (.+)$/;

 $hash->{PRESENCE}  = "present";

 my ($b , $c) = split("OK MPD " , $_);
 $hash->{VERSION} = $c;
 # ok, now we're connected - let's issue the commands.

 if ($hash->{".password"} ne "")
 {
  # lets try to authenticate with a password
  print $sock "password ".$hash->{".password"}."\r\n";
  while (<$sock>) { last if $_ ; } # end of output.
  
  chomp;

  if ($_ !~ /^OK$/)
  {
    print $sock "close\n";
    close($sock);
    readingsSingleUpdate($hash,"error",$_,1);
    return "password auth failed : ".$_ ;
  }
 }

 my @commands =  split("\\|" , $a);

 if ($commands[0] ne "i")
 { # start Ausgabe nach Readings oder Internals

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"presence","present"); # MPD lebt
  
  foreach (@commands) 
  {
    my $cmd = $_;
    print $sock "$cmd\r\n";
    Log3 $name, 5 , "$name, mpd_cmd[1] -> $cmd";
 
    while (<$sock>) 
    {
     chomp $_;
     return  "MPD_Msg ACK ERROR ".$_ if $_ =~ s/^ACK //; # oops - error.
     last if $_ =~ /^OK/;    # end of output.
     Log3 $name, 5 , "$name, rec: ".$_;

     ($b , $c) = split(": " , $_);

     if ($b && defined($c)) # ist das ein Reading ?
      { 
        #$b = lc($b);
        if ($b eq "volume") { $hash->{".volume"} = $c; }  # Sonderfall volume
    
        $artist = $c if ($b eq "Artist");

        if ($b eq "Title")
        {
         $sp = index($c, " - ");
         if (AttrVal($name, "titleSplit", 1) && ($sp>0)) # wer nicht mag solls eben abschalten
          {
            $artist = substr($c,0,$sp);
            readingsBulkUpdate($hash,"Artist",$artist);
            readingsBulkUpdate($hash,"Title",substr($c,$sp+3));
          }
          else { readingsBulkUpdate($hash,"Title",$c); } # kein Titel Split
        }
        #elsif ($b eq "time")
        #{
         # fix für doppeltes time Reading 
         # https://forum.fhem.de/index.php/topic,18517.msg539676.html#msg539676
         #if (index($c,":") == -1) {$b = "songtime";}
         #readingsBulkUpdate($hash,$b,$c);
        #}

        else { readingsBulkUpdate($hash,$b,$c); } # irgendwas aber kein Titel
      } # defined $c
    } # while
  } # foreach
  
  readingsEndUpdate($hash, 1 );

  MPD_get_artist_info($hash, urlEncode($artist)) if ((AttrVal($name, "image_size", 0) > -1) && $artist);

 } # Ende der Ausgabe Readings und Internals, ab jetzt folgt nur noch Bildschirmausgabe
 else
 { # start internes cmd
  print $sock $commands[1]."\r\n";
  Log3 $name, 5 , "$name, mpd_cmd[2] -> ".$commands[1];
  my $d;
  while (<$sock>) 
   {
     return  "mpd_Msg ACK ERROR ".$_ if $_ =~ s/^ACK //; # oops - error.
     last if $_ =~ /^OK/;    # end of output.
      $sp = index($_, ": ");
      $b = substr($_,0,$sp);
      $c = substr($_,$sp+2);

     if    (($b eq "file" )     && ($commands[2] eq "music"))     {$hash->{".musiclist"} .= $c; } # Titelliste füllen
     elsif (($b eq "playlist" ) && ($commands[2] eq "playlists")) {$hash->{".playlists"} .= $c; } # Playliste füllen

     if ($commands[2] eq "x") { $output .= $_; } 
   } # while

   if (defined($commands[3])) 
   { 
     #$output =~s/Title:/title:/g;
     #$output =~s/Id:/id:/g;
     #$output =~s/Name:/name:/g;
     #$output =~s/Pos:/pos:/g;
     #$output =~s/: / : /g;
     my @arr = split("\n",$output); 
     @arr = sort(@arr);
     $output = join("\n",@arr);
   }

  } # end internes cmd

 print $sock "close\n";
 close($sock); 

 if ($hash->{".playlists"} ne $playlists) # haben sich sich die Listen geändert ?
 {
  $hash->{".playlists"} =~ s/\n+\z//;
  my $plists = $hash->{".playlists"}; 
  $plists =~ tr/\n/\:/; # Tablet UI will diese Art der Liste
  readingsSingleUpdate($hash,"playlistcollection", $plists,1);
  Log3 $name ,5 ,"$name, ".$hash->{READINGS}{"playlistcollection"}{VAL};
 }

 return $output; # falls es einen gibt , wenn nicht - auch gut ;)

} # end mpd_msg


sub MPD_IdleStart($)
{
 my ($name) = @_;
 return unless(defined($name));

 my $hash         = $defs{$name};
 my $old_event    = "";
 my $telnetPort   = undef;
 my $output; 

 # Suche das Telnet Device ohne Passwort
 # Code geklaut aus Blocking.pm :)

 foreach my $d (sort keys %defs) 
 {  
    my $h = $defs{$d};
    next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{SNAME});
    next if($attr{$d}{SSL} || AttrVal($d, "allowfrom", "127.0.0.1") ne "127.0.0.1");
    next if($h->{DEF} !~ m/^\d+( global)?$/);
    next if($h->{DEF} =~ m/IPV6/);
    my %cDev = ( SNAME=>$d, TYPE=>$h->{TYPE}, NAME=>$d.time() );
    next if(Authenticate(\%cDev, undef) == 2);    # Needs password
    $telnetPort = $defs{$d}{"PORT"};
    last;
 }

 return $name."|no telnet port without password found" if (!$telnetPort); 

 my $sock = IO::Socket::INET->new(
            PeerHost => $hash->{HOST},
            PeerPort => $hash->{PORT},
            Proto    => 'tcp',
            Timeout  => $hash->{TIMEOUT});

 return $name."|IdleStart: $!" if (!$sock);

 while (<$sock>) { last if $_ ; }

 chomp $_;

 return  $name."|not a valid mpd server, welcome string was: ".$_ if $_ !~ /^OK MPD (.+)$/;

 if ($hash->{".password"} ne "")
 {
  # lets try to authenticate with a password
  print $sock "password ".$hash->{".password"}."\r\n";
  while (<$sock>)
  {
   last if $_ ; # end of output.
  }
  chomp;
  if ($_ !~ /^OK$/)
   { 
    print $sock "close\n";
    close($sock);
    return $name."|mpd password auth failed : ".$_;
   }
 }

 # Waits until there is a noteworthy change in one or more of MPD's subsystems. 
 # As soon as there is one, it lists all changed systems in a line in the format changed: SUBSYSTEM, 
 # where SUBSYSTEM is one of the following: 
 # - database: the song database has been modified after update. 
 # - update: a database update has started or finished. If the database was modified during the update, the database event is also emitted. 
 # - stored_playlist: a stored playlist has been modified, renamed, created or deleted 
 # +- playlist: the current playlist has been modified 
 # +- player: the player has been started, stopped or seeked 
 # +- mixer: the volume has been changed 
 # - output: an audio output has been enabled or disabled 
 # +- options: options like repeat, random, crossfade, replay gain 
 # - sticker: the sticker database has been modified. 
 # - subscription: a client has subscribed or unsubscribed to a channel 
 # - message: a message was received on a channel this client is subscribed to; this event is only emitted when the queue is empty

 my $sock2  = IO::Socket::INET->new(
              PeerHost => "127.0.0.1",
              PeerPort => $telnetPort,
              Proto    => 'tcp',
              Timeout  => 2);

 return $name."|Idle send: ".$! if (!$sock2);

 print $sock2 "get $name statusRequest\nexit\n";
 close ($sock2);
 
 print $sock "idle\n";
 while (<$sock>) 
 {
  if ($_)    # es hat sich was getan.
  {
     chomp $_; 

     if ($_ =~ s/^ACK //) # oops - error.
     {
       print $sock "close\n";
       close($sock);
       return  $name."|ACK ERROR : ".$_;
     }
   
     $_ =~s/changed: //g;

     if (($_ ne $old_event) && ($_ ne "OK"))  
     { 
      $output   .= ($old_event eq "") ? $_ : "+".$_; 
      $old_event = $_; 
     }
     else #if ($_ eq "OK")  
     {
       print $sock "idle\n"; 
     } # OK
  } # $_

  if ((($old_event eq "player")  || 
       ($old_event eq "playlist")|| 
       ($old_event eq "mixer")   || 
       ($old_event eq "options"))
     ) # muessen wir den Parentprozess informieren ?
     {
        $sock2 = IO::Socket::INET->new(
                 PeerHost => "127.0.0.1",
                 PeerPort => $telnetPort,
                 Proto    => 'tcp',
                 Timeout  => 2);

        return $name."|Idle_loop send: ".$! if (!$sock2);
    
        print $sock2 "set $name mpd_event $output\nexit\n";
        close($sock2);
        $old_event = "";
        $output    = "";
     } 
   } #while 
 
  #print $sock "close\n";
  close($sock);

  return $name."|socket error";  
} 

sub MPD_IdleDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my @r = split("\\|",$string);
  my $hash = $defs{$r[0]};
  my $ret = (defined($r[1])) ? $r[1] : "unknow error";
  my $name = $hash->{NAME};

  Log3 $name, 5,"$name, IdleDone -> $string";
  
  delete($hash->{helper}{RUNNING_PID});
  delete $hash->{IPID};

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","error");
  readingsBulkUpdate($hash,"error",$ret);
  readingsBulkUpdate($hash,"presence","absent"); 
  readingsEndUpdate($hash, 1 );

  Log3 $name, 3 , "$name, idle error -> $ret";
  return if(IsDisabled($name));
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+AttrVal($name, "waits", 60), "MPD_try_idle", $hash, 0);

  return;
}

sub MPD_try_idle($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $waits  = AttrVal($name, "waits", 60);

  $hash->{helper}{RUNNING_PID} = BlockingCall("MPD_IdleStart",$name, "MPD_IdleDone", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
  if ($hash->{helper}{RUNNING_PID})
  {
    $hash->{IPID} = $hash->{helper}{RUNNING_PID}{pid};
    Log3 $name, 4 , $name.", Idle new PID : ".$hash->{IPID};
    RemoveInternalTimer($hash);
    if ($^O !~ /Win/) # was könnte man bei Windows tun ?
    {
     InternalTimer(gettimeofday()+$waits, "MPD_watch_idle", $hash, 0); # starte die Überwachung
    }
    return 1;
  }
  else 
  {
    Log3 $name, 2 , $name.", Idle Start failed, waiting $waits seconds for next try";
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$waits, "MPD_try_idle", $hash, 0);
    return 0;
  }
}

sub MPD_watch_idle($)
{
  # Lebt denn der Idle Prozess überhaupt noch ? 
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);
  return if (IsDisabled($name));
  return if (!defined($hash->{IPID}));

  my $waits  = AttrVal($name, "waits", 60);
  my $cmd    = "ps -e | grep '".$hash->{IPID}." '";
  my $result = qx($cmd); 

  if  (index($result,"perl") == -1)
  {
   Log3 $name, 2 , $name.", cant find idle PID ".$hash->{IPID}." in process list !";
   BlockingKill($hash->{helper}{RUNNING_PID});
   delete $hash->{helper}{RUNNING_PID};
   delete $hash->{IPID};
   InternalTimer(gettimeofday()+2, "MPD_try_idle", $hash, 0);
   return;
  }
  else 
  { 
    Log3 $name, 5 , $name.", idle PID ".$hash->{IPID}." found";
    if (($hash->{READINGS}{"presence"}{VAL} eq "present") && ($hash->{STATE} eq "play")) 
    {
     # Wichtig um das Readings elapsed aktuell zu halten (TabletUI)
     mpd_cmd($hash, "status");
     readingsSingleUpdate($hash,"playlistname",$hash->{".playlist"},1) if ($hash->{READINGS}{"playlistname"}{VAL} ne $hash->{".playlist"});
    }
  }

  InternalTimer(gettimeofday()+$waits, "MPD_watch_idle", $hash, 0);
  return;
}


sub MPD_get_artist_info ($$)
{
    my ($hash, $artist) = @_;
    my $name = $hash->{NAME};
    return undef if ($hash->{'.artist'} eq $artist);
    $hash->{'.artist'} = $artist;
    my $data;
    my $cache = AttrVal($name,"cache",""); # default

    my $param = {
                 url      => lfm.$hash->{'.apikey'}."&artist=".$artist,
                 timeout  => 5,
                 hash     => $hash,     
		 header   => "User-Agent: Mozilla/5.0\r\nAccept: application/xml\r\nAccept-Charset: utf-8",
                 method   => "GET",     
                 callback =>  \&MPD_lfm_artist_info
                };

    if ((-e "www/$cache/".$hash->{'.artist'}.".xml") && ($cache ne ""))
    {
     Log3 $name ,4,"$name, artist file ".$hash->{'.artist'}.".xml already exist";
     if (!open (FILE , "www/$cache/".$hash->{'.artist'}.".xml"))
     {
      Log3 $name, 2, "$name, error reading ".$hash->{'.artist'}.".xml : $!";
      $hash->{'.xml'} = 0;
     }
     else 
     {
      while(<FILE>){ $data = $data.$_;}
      close (FILE);
      MPD_lfm_artist_info($param,"",$data,'local');
     }
    }
    else # xml von lastfm holen 
    { 
      Log3 $name ,4,"$name, new artist ".$hash->{'.artist'}." , getting file from lastfm";
      HttpUtils_NonblockingGet($param); 
    }
    return undef;
}

sub MPD_lfm_artist_info(@)
{
    my ($param, $err, $data, $local) = @_;
    my $hash  = $param->{hash};
    my $name  = $hash->{NAME};
    my $size  = AttrVal($name,"image_size",0); # default
    my $cache = AttrVal($name,"cache","");
    return if ($size < 0);
  
    if (!$data || $err)
    {
     Log3 $name ,3,"$name, error getting artist info from lastfm -> $err";
     MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot","");
     return undef;
    }

    if (!$local) {Log3 $name,4,"$name, new xml data from lastfm";}
    if ($cache ne "")
    {
     # xml lokal speichern ?
     if (-e "www/$cache/".$hash->{'.artist'}.".xml")
     {
       Log3 $name ,5,"$name, artist ".$hash->{'.artist'}." already exist";
       $hash->{XML} = 1;
     }
     else
     {
      if (!open (FILE , ">"."www/$cache/".$hash->{'.artist'}.".xml"))
       {
         Log3 $name, 2, "$name, error saving ".$hash->{'.artist'}.".xml : ".$!;
         $hash->{XML} = 0;
         #$hash->{'.artist'} = "";
         #return;
       }
        else 
        {
         print FILE $data;
         close(FILE);
         $hash->{XML} = 1;
        }
     }
    }

    my $newxml = XML::Simple->new(ForceArray => ['entry', 'link'], KeyAttr => []);
    my $xml = $newxml->XMLin($data);

    my $hw="width='32' height='32'";
    $hw="width='64' height='64'"   if ($size == 1);
    $hw="width='174' height='174'" if ($size == 2);
    $hw="width='300' height='300'" if ($size == 3);

    if ((exists $xml->{'artist'}->{'bio'}->{'summary'}) && AttrVal($name,"artist_summary",0))
    {
     readingsSingleUpdate($hash,"artist_summary",$xml->{'artist'}->{'bio'}->{'summary'},1);
    }

    if ((exists $xml->{'artist'}->{'bio'}->{'content'}) && AttrVal($name,"artist_content",0))
    {
     readingsSingleUpdate($hash,"artist_content",$xml->{'artist'}->{'bio'}->{'content'},1);
    }


      if (!$cache || !$hash->{XML}) # cache verwenden ?
      {
      if (exists $xml->{'artist'}->{'image'}[$size]->{'content'})
      {
       if (index($xml->{'artist'}->{'image'}[$size]->{'content'},"http") < 0)
       {
         MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot","");
         Log3 $name,1,"$name, falsche info  URL : ".$xml->{'artist'}->{'image'}[$size]->{'content'};
         return undef;
       }
        MPD_artist_image($hash,$xml->{'artist'}->{'image'}[$size]->{'content'},$hw);
      }
      else
      {
       MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot", "");
       Log3 $name,4,"$name, unknown artist";
      }
       return undef;
    } # kein cache verwenden

   if (exists $xml->{'artist'}->{'image'}[$size]->{'content'})
   {
    $hash->{'.suffix'} = substr($xml->{'artist'}->{'image'}[$size]->{'content'},-4);
    my $fname = $hash->{'.artist'}."_$size".$hash->{'.suffix'};


    if (-e "www/$cache/".$fname)
    {
       Log3 $name ,4,"$name, artist image ".$fname." local found";
       MPD_artist_image($hash,"/fhem/$cache/".$fname,$hw);
       return undef;
    }

    Log3 $name ,4,"$name, no local artist image ".$fname." getting from lastfm";

    $param = {
        url      => $xml->{'artist'}->{'image'}[$size]->{'content'},
        timeout  => 5,
        hash     => $hash,     
        method   => "GET",     
        callback =>  \&MPD_lfm_artist_image 
    };

    HttpUtils_NonblockingGet($param);
    MPD_artist_image($hash,"/fhem/icons/10px-kreis-gelb","");
   }
    else { 
           MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot",""); 
           Log3 $name ,4,"$name, image infos missing , delete old xml";
           unlink ("www/$cache/".$hash->{'.artist'}.".xml");
         } # keine Image Infos vorhanden !
  

  return undef;
}

sub MPD_artist_image($$$)
{
  my ($hash, $im , $hw) = @_;
  readingsSingleUpdate($hash,"artist_image_html","<img src='$im' $hw />",1);
  readingsSingleUpdate($hash,"artist_image","$im",1);
  return;
}

sub MPD_lfm_artist_image(@)
{
    my ($param, $err, $data) = @_;
    my $hash  = $param->{hash};
    my $name  = $hash->{NAME};
    my $cache = AttrVal($name,"cache","");
    my $size  = AttrVal($name,"image_size",1);

    my $hw="width='32' height='32'";
    $hw="width='64' height='64'"   if ($size == 1);
    $hw="width='174' height='174'" if ($size == 2);
    $hw="width='300' height='300'" if ($size == 3);

    my $fname = $hash->{'.artist'}."_$size".$hash->{'.suffix'};
 
    if($err ne "")          
    {
        Log3 $name, 3, "$name, error while requesting ".$param->{url}." - $err";
    }
     elsif(($data ne "") && ($data =~ /PNG/i))                                                   
    {
        Log3 $name,4,"$name, got new image from lastfm";        
    
        if (!open(FILE, "> www/$cache/$fname"))
        {
         Log3 $name, 2, "$name, error saving image $fname : ".$!;
         MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot"," ");
         return undef;
        }
        binmode(FILE);
        print FILE $data;
        close(FILE);
    
        MPD_artist_image($hash,"/fhem/$cache/".$fname,$hw);
        return undef;
    }

    Log3 $name,3,"$name, empty or invalid image from lastfm";
    unlink ("www/$cache/".$hash->{'.artist'}.".xml");
    MPD_artist_image($hash,"/fhem/icons/10px-kreis-rot","");
    return undef;
}


sub MPD_NewPlaylist($$)
{
  my ($hash, $list) = @_;
  my $name  = $hash->{NAME};
  
  Log3 $name,5,"$name, new Playlist in -> $list";

  $list =~ s/"/\\"/g;
  $list = "\n".$list;  
  my @artist   = ($list=~/\nArtist:\s(.*)\n/g);
  my @title    = ($list=~/\nTitle:\s(.*)\n/g);
  my @album    = ($list=~/\nAlbum:\s(.*)\n/g);
  my @time     = ($list=~/\nTime:\s(.*)\n/g);
  my @file     = ($list=~/\nfile:\s(.*)\n/g);
  my @track    = ($list=~/\nTrack:\s(.*)\n/g);
  my @albumUri = ($list=~/\nX-AlbumUri:\s(.*)\n/g);  # von Mopidy ?
  my $ret = '[';
  my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 1 } );
  my $lastUri = '';
  my $url;

  for my $i (0 .. $#artist)
  {
     if (defined($albumUri[$i]))
     {
     if ( $lastUri ne $albumUri[$i]) 
     {
       my $response = $ua->get("https://embed.spotify.com/oembed/?url=".$albumUri[$i]);
       my $data = '';
       if ( $response->is_success ) 
       {
         $data = $response->decoded_content;
         $url = decode_json( $data );
         $lastUri = $url->{'thumbnail_url'};
       }
     }
     } # vesuchen wir es mit Last.fm
     elsif (AttrVal($name,"image_size",-1) > -1 && (AttrVal($name,"cache","") ne ""))
     {
      my $cache = AttrVal($name,"cache","");
      my $size  = AttrVal($name,"image_size",0);
      if (-e "www/$cache/".urlEncode($artist[$i])."_".$size.".png")
            { $lastUri = "/fhem/www/".$cache."/".urlEncode($artist[$i])."_".$size.".png"; }
      else  { $lastUri = "/fhem/icons/1px-spacer"; }
     }
     else  { $lastUri = "/fhem/icons/1px-spacer"; }

     $ret .= '{"Artist":"'.$artist[$i].'",';
     $ret .= '"Title":';
     $ret .= (defined($title[$i])) ? '"'.$title[$i].'",' : '"",';
     $ret .= '"Album":';
     $ret .= (defined($album[$i])) ? '"'.$album[$i].'",' : '"",';
     $ret .= '"Time":';
     $ret .= (defined($time[$i])) ? '"'.$time[$i].'",' : '"",';
     $ret .= '"File":"'.$file[$i].'",';
     $ret .= '"Track":';
     $ret .= (defined($track[$i])) ? '"'.$track[$i].'",' : '"",';
     $ret .= '"Cover":"'.$lastUri.'"}';
     $ret .= ',' if ($i<$#artist); 
  }
  
  $ret .= ']';
  $ret =~ s/;//g;
  $ret =~ s/\\n//g;
  Log3 $name,5,"$name, new Playlist out -> $ret";
  readingsSingleUpdate($hash,"playlistinfo",$ret,1);
  return;  
}



###############################################

sub MPD_html($) {
 my ($hash)= @_;
 my $name         = $hash->{NAME};
 my $playlist     = $hash->{".playlist"};
 my $playlists    = $hash->{".playlists"};
 my $musiclist    = $hash->{".musiclist"};
 my $music        = $hash->{".music"};
 my $volume       = (defined($hash->{".volume"})) ? $hash->{".volume"} : "???";
 my $len          = (defined($hash->{READINGS}{"playlistlength"}{VAL})) ? $hash->{READINGS}{"playlistlength"}{VAL} : "--";
 my $html;
 my @list;
 my $sel = "";

 my $pos = (defined($hash->{READINGS}{"song"}{VAL}) && $len) ? $hash->{READINGS}{"song"}{VAL} : "--";
 $pos .= "/"; 
 $pos .= ($len) ? $len : "0";

 $html  = "<div class=\"remotecontrol\" id=\"$name\">";
 $html .= "<table class=\"rc_body\" border=0>";
 if ($playlists||$music) 
 {
 
  if ($playlists) { 
     $html .= "<tr><td colspan=\"5\" align=center><select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playlist ' + this.options[this.selectedIndex].value)\" style=\"font-size:11px;\">";

    $html .= "<optgroup label=\"Playlists\">"; 
    $html .= "<option>---</option>";
    @list = sort(split ("\n",$playlists));
    foreach (@list) 
    {
      $sel = ($_ eq $playlist) ? " selected" : "";
      $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
    }
    $html .= "</optgroup></select></td></tr>";
   }
 
   if ($musiclist) { 
   $html .= "<tr><td colspan=\"5\" align=center><select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playfile ' + this.options[this.selectedIndex].value)\" style=\"font-size:11px;\">";
   $html .= "<optgroup label=\"Music\">";
   $html .= "<option>---</option>"; 
     @list = sort(split ("\n",$musiclist));
      foreach (@list) 
      {
      $sel = ($_ eq $music) ? " selected" : "";
      $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
      }
    $html .= "</optgroup></select></td></tr>";
  }
 }

 $html .= "<tr><td>&nbsp;</td>";
 
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name play')\"><img src=\"/fhem/icons/remotecontrol/black_btn_PLAY\" title=\"PLAY\"></a></td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name pause')\"><img src=\"/fhem/icons/remotecontrol/black_btn_PAUSE\" title=\"PAUSE\"></a></td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name stop')\"><img src=\"/fhem/icons/remotecontrol/black_btn_STOP\" title=\"STOP\"></a></td>";
 $html .= "<td>&nbsp;</td></tr>";
 
 $html .= "<tr><td>&nbsp;</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name previous')\"><img src=\"/fhem/icons/remotecontrol/black_btn_REWIND\" title=\"PREV\"></a></td>";
 $html .= "<td style=\"font-size:14px; align:center;\">".$pos."</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name next')\"><img src=\"/fhem/icons/remotecontrol/black_btn_FF\" title=\"NEXT\"></a></td>";
 $html .= "<td>&nbsp;</td></tr>";

 $html .= "<tr><td>&nbsp;</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name volumeDown')\"><img src=\"/fhem/icons/remotecontrol/black_btn_VOLDOWN2\" title=\"VOL -\"></a></td>";
 $html .= "<td style=\"font-size:14px; align:center;\">".$volume."</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name volumeUp')\"><img src=\"/fhem/icons/remotecontrol/black_btn_VOLUP2\" title=\"VOL +\"></a></td>";
 $html .= "<td>&nbsp;</td></tr>";

 if ($hash->{".outputs"})
 {
   my @outp = split("\n" , $hash->{".outputs"});
   my $oid;
   my $oname = "";
   my $oen   = "";
   my $osel  = "";
   
   foreach (@outp)
   {
      my @val = split(": " , $_);
      $oid   = $val[1] if ($val[0] eq "outputid");
      $oname = $val[1] if ($val[0] eq "outputname");
      $oen   = $val[1] if ($val[0] eq "outputenabled");
    
     if ($oen ne "")
     {
      $html .= "<tr>";
      $html .="<td style='font-size:10px;' colspan='5' align='center'>$oid.$oname ";
      $osel = ($oen eq "1") ? "checked" : "";
      $html .="<input type='radio' name='B".$oid." value='1' $osel onclick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name mpdCMD enableoutput $oid')\">on&nbsp;";
      $osel = ($oen ne "1") ? "checked" : "";
      $html .="<input type='radio' name='B".$oid." value='0' $osel onclick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name mpdCMD disableoutput $oid')\">off</td>";
      $html .="</tr>";
      $oen = "";
     }
    }
 }

 $html .= "</table></div>";

return $html;
}

sub MPD_summaryFn($$$$) {
	my ($FW_wname, $hash, $room, $pageHash) = @_;
        $hash            = $defs{$hash};
        my $state        = $hash->{STATE};
        my $txt          = $state;
        my $name         = $hash->{NAME};
        my $playlist     = $hash->{".playlist"};
        my $playlists    = $hash->{".playlists"};
        my $music        = $hash->{".music"};
        my $musiclist    = $hash->{".musiclist"};

        my ($icon,$isHtml,$link,$html,@list,$sel);
        ($icon, $link, $isHtml) = FW_dev2image($name);
        $txt = ($isHtml ? $icon : FW_makeImage($icon, $state)) if ($icon);
        $link = "cmd.$name=set $name $link" if ($link);
        $txt  = "<a onClick=\"FW_cmd('/fhem?XHR=1&$link&room=$room')\">".$txt."</a>" if ($link);

        my $rname  = "";
        my $artist = "";
        my $title  = "";
        my $album  = "";
        my $file   = (defined($hash->{READINGS}{"file"}{VAL})) ? $hash->{READINGS}{"file"}{VAL}."&nbsp;<br />" : "";

        if (defined($hash->{READINGS}{"Title"}{VAL}))  
        { $title  = ($hash->{READINGS}{"Title"}{VAL} ne "" ) ? $hash->{READINGS}{"Title"}{VAL}."&nbsp;<br />" : "";}
        if (defined($hash->{READINGS}{"Artist"}{VAL}))
        { $artist = ($hash->{READINGS}{"Artist"}{VAL} ne "") ? $hash->{READINGS}{"Artist"}{VAL}."&nbsp;<br />": "";}

        if (defined($hash->{READINGS}{"Album"}{VAL}))
        { $album = ($hash->{READINGS}{"Album"}{VAL} ne "") ? $hash->{READINGS}{"Album"}{VAL}."&nbsp;" : "";}

        if (defined($hash->{READINGS}{"Name"}{VAL}))
        { $rname  = ($hash->{READINGS}{"Name"}{VAL} ne "")   ? $hash->{READINGS}{"Name"}{VAL}."&nbsp;<br />"  : ""; }

	$html  ="<table><tr><td>$txt</td><td>";
         if (($playlists) && $hash->{".sPlayL"})
         { 
          $html .= "<select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playlist ' + this.options[this.selectedIndex].value)\">";
          $html .= "<optgroup label=\"Playlists\">"; 
          $html .= "<option>---</option>";
          @list = sort( split ("\n",$playlists));
          foreach (@list) 
          {
           $sel = ($_ eq $playlist) ? " selected" : "";
           $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
          }
          $html .= "</optgroup></select><br/>";
         }
         
         if (($musiclist) && $hash->{".sMusicL"}) 
         { 
          $html .= "<select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playfile ' + this.options[this.selectedIndex].value)\">";
          $html .= "<optgroup label=\"Music\">"; 
          $html .= "<option>---</option>";
          @list = sort (split ("\n",$musiclist));
          foreach (@list) 
          {
           $sel = ($_ eq $music) ? " selected" : "";
           $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
          }
          $html .= "</optgroup></select>";
         }

         $html.= "</td><td>";

        if ($rname.$artist.$title.$album ne "") 
        {
	 $html .= (($state eq "play") || ($state eq "pause")) ? $rname.$artist.$title.$album : "&nbsp;";
         if (defined($hash->{READINGS}{"artist_image"}{VAL}))
         {
          my $hw = (index($hash->{READINGS}{"artist_image"}{VAL},"icon") == -1) ? " width='32' height='32'" : "";
          $html .= "</td><td><img src='".$hash->{READINGS}{"artist_image"}{VAL}."' alt='".$hash->{'.artist'}."' $hw/>";
         }
        }
        else
        {
	 $html .= (($state eq "play") || ($state eq "pause")) ? $file : "&nbsp;";
        }

        $html .= "</td></tr></table>";
	return $html;	
}


1;

=pod
=item device
=item summary  controls MPD or Mopidy music server
=item summary_DE steuert den MPD oder Mopidy Musik Server
=begin html

<a name="MPD"></a>
<h3>MPD</h3>
 FHEM module to control a MPD (or Mopidy) like the MPC (MPC =  Music Player Command, the command line interface to the <a href='http://en.wikipedia.org/wiki/Music_Player_Daemon'>Music Player Daemon</a> )<br>
To install a MPD on a Raspberry Pi you will find a lot of documentation at the web e.g. http://www.forum-raspberrypi.de/Thread-tutorial-music-player-daemon-mpd-und-mpc-auf-dem-raspberry-pi  in german<br>
FHEM Forum : <a href='http://forum.fhem.de/index.php/topic,18517.0.html'>Modul f&uuml;r MPD</a> ( in german )<br>
Modul requires XML:Simple -> sudo apt-get install libxml-simple-perl<br>
<ul>
 <a name="MPDdefine"></a>
  <b>Define</b>
  <ul>
  define &lt;name&gt; MPD &lt;IP MPD Server | default localhost&gt; &lt;Port  MPD Server | default 6600&gt;<br>
  Example:<br>
  <pre>
  define myMPD MPD 192.168.0.99 7000
  </pre>
  if FHEM and MPD a running on the same device : 
  <pre>
  define myMPD MPD
  </pre>
  </ul>
  <br>
  <a name="MPDset"></a>
  <b>Set</b><ul>
    <code>set &lt;name&gt; &lt;what&gt;</code>
    <br>&nbsp;<br>
    Currently, the following commands are defined.<br>
    &nbsp;<br>
    play     => like MPC play , start playing song in playlist<br>
    clear    => like MPC clear , delete MPD playlist<br>
    stop     => like MPC stop, stops playing <br>
    pause    => like MPC pause<br>
    previous => like MPC previous, play previous song in playlist<br>
    next     => like MPC next, play next song in playlist<br>
    random   => like MPC random, toggel on/off<br>
    repeat   => like MPC repeat, toggel on/off<br>
    toggle   => toggles from play to stop or from stop/pause to play<br>
    updateDb => like MPC update<br>
    volume (%) => like MPC volume %, 0 - 100<br>
    volumeUp => inc volume ( + attr volumeStep size )<br>
    volumeDown => dec volume ( - attr volumeStep size )<br>
    playlist (playlist name) => set playlist on MPD Server<br>
    playfile (file) => create playlist + add file to playlist + start playing<br>
    IdleNow => send Idle command to MPD and wait for events to return<br>
    reset => reset MPD Modul<br>
    mpdCMD (cmd) => send a command to MPD Server ( <a href='http://www.musicpd.org/doc/protocol/'>MPD Command Ref</a> )<br>
   </ul>
  <br>
  <a name="MPDget"></a>
  <b>Get</b><ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br>&nbsp;<br>
    Currently, the following commands are defined.<br>
    music => list all MPD music files in MPD databse<br>
    playlists => list all MPD playlist in MPD databse<br>
    playlistsinfo => show current playlist informations<br>
    webrc => HTML output for a simple Remote Control on FHEM webpage e.g :.<br>
    <pre>
       define &lt;name&gt; weblink htmlCode {fhem("get &lt;name&gt; webrc", 1)}
       attr &lt;name&gt; room MPD
    </pre>
    statusRequest => get MPD status<br>
    currentsong => get infos from current song in playlist<br>
    outputs => get name,id,status about all MPD output devices in /etc/mpd.conf<br>
  </ul>
  <br>
  <a name="MPDattr"></a>
  <b>Attributes</b>
  <ul>
      <li>password <pwd>,  if password in mpd.conf is set</li>
      <li>loadMusic 1|0 => load titles from MPD database at startup (not supported by modipy)</li>
      <li>loadPlaylists 1|0 => load playlist names from MPD database at startup</li>
      <li>volumeStep 1|2|5|10 =>  Step size for Volume +/- (default 5)</li>
      <li>titleSplit 1|0 => split title to artist and title if no artist is given in songinfo (e.g. radio-stream default 1)</li>
      <li>timeout (default 1) => timeout in seconds for TCP connection timeout</li>
      <li>waits (default 60) => if idle process ends with error, seconds to wait</li>
      <li>stateMusic 1|0 => show Music DropDown box in web frontend</li>
      <li>statePlaylists 1|0 => show Playlists DropDown box in web frontend</li>
      <li>image_size</li>
      <li>player  mpd|mopidy|forked-daapd => which player is controlled by the module</li>

  </ul>
  <br>
  <b>Readings</b>
  <ul>
    all MPD internal values
  </ul>
</ul>
=end html

=begin html_DE

<a name="MPD"></a>
<h3>MPD</h3>
<ul>
  FHEM Modul zur Steuerung des MPD (oder Mopidy) &auml;hnlich dem MPC (MPC =  Music Player Command, das Kommando Zeilen Interface f&uuml;r den 
  <a href='http://en.wikipedia.org/wiki/Music_Player_Daemon'>Music Player Daemon</a> ) (englisch)<br>
  Um den MPD auf einem Raspberry Pi zu installieren finden sich im Internet zahlreiche gute Dokumentaionen 
  z.B. <a href="http://www.forum-raspberrypi.de/Thread-tutorial-music-player-daemon-mpd-und-mpc-auf-dem-raspberry-pi"><b>hier</b></a><br>
  Thread im FHEM Forum : <a href='http://forum.fhem.de/index.php/topic,18517.0.html'>Modul f&uuml;r MPD</a><br>
  Das Modul ben&ouml;tigt zwingend XML:Simple, installation z.B. mit <i>sudo apt-get install libxml-simple-perl</i><br>
  <a name="MPDdefine"></a>
  <b>Define</b>
  <ul>
    define &lt;name&gt; MPD &lt;IP MPD Server | default localhost&gt; &lt;Port  MPD Server | default 6600&gt;<br>
    Beispiel :<br>
    <ul><pre>
    define myMPD MPD 192.168.0.99 7000
    </pre>
    wenn FHEM und der MPD auf dem gleichen PC laufen : 
    <pre>
    define myMPD MPD
    </pre>
    </ul>
  </ul>
  <br>
  <a name="MPDset"></a>
  <b>Set</b><ul>
    <code>set &lt;name&gt; &lt;was&gt;</code>
    <br>&nbsp;<br>
    z.Z. unterst&uuml;tzte Kommandos<br>
    &nbsp;<br>
    play  => spielt den aktuellen Titel der MPD internen Playliste<br>
    clear => l&ouml;scht die MPD interne Playliste<br>
    stop  => stoppt die Wiedergabe<br>
    pause => Pause an/aus<br>
    previous => spielt den vorherigen Titel in der Playliste<br>
    next => spielt den n&aumlchsten Titel in der Playliste<br>
    random => zuf&auml;llige Wiedergabe an/aus<br>
    repeat => Wiederholung an/aus<br>
    toggle => wechselt von play nach stop bzw. stop/pause nach play<br>
    volume (%) => &auml;ndert die Lautst&auml;rke von 0 - 100%<br>
    volumeUp => Lautst&auml;rke schrittweise erh&ouml;hen , Schrittweite = ( attr volumeStep size )<br>
    volumeDown => Lautst&auml;rke schrittweise erniedrigen , Schrittweite = ( attr volumeStep size )<br>
    playlist (playlist name) => lade Playliste <name> aus der MPD Datenbank und starte Wiedergabe mit dem ersten Titel<br>
    playfile (file) => erzeugt eine MPD interne Playliste mit file als Inhalt und spielt dieses ab<br>  
    updateDb => wie MPC update, Update der MPD Datenbank<br>
    reset => reset des FHEM MPD Moduls<br>
    mpdCMD (cmd) => sende cmd direkt zum MPD Server ( siehe auch <a href="http://www.musicpd.org/doc/protocol/">MPD Comm Ref</a> )<br>
    IdleNow => sendet das Kommando idle zum MPD und wartet auf Ereignisse<br>
    clear_readings => l&ouml;scht sehr viele Readings<br>
   </ul>
  <br>
  <a name="MPDget"></a>
  <b>Get</b><ul>
    <code>get &lt;name&gt; &lt;was&gt;</code>
    <br>&nbsp;<br>
    z.Z. unterst&uuml;tzte Kommandos<br>
    music => zeigt alle Dateien der MPD Datenbank<br>
    playlists => zeigt alle Playlisten der MPD Datenbank<br>
    playlistsinfo => zeigt Informationen der aktuellen Playliste<br>
    webrc => HTML Ausgabe einer einfachen Web Fernbedienung Bsp :.<br>
    <pre>
      define &lt;name&gt; weblink htmlCode {fhem("get &lt;name&gt; webrc", 1)}
      attr &lt;name&gt; room MPD
    </pre>
    statusRequest => hole aktuellen MPD Status<br>
    currentsong => zeigt Informationen zum aktuellen Titel der MPD internen Playliste<br>
    outputs => zeigt Informationen der definierten MPD Ausgabe Kan&auml;le ( aus /etc/mpd.conf )<br>
  </ul>
  <br>
  <a name="MPDattr"></a>
  <b>Attribute</b>
  <ul> 
    <li>password <pwd> => Password falls in der mpd.conf definiert</li>
    <li>loadMusic 1|0  => lade die MPD Titel beim FHEM Start :  mpd.conf - music_directory</li>
    <li>loadPlaylists 1|0 => lade die MPD Playlisten beim FHEM Start : mpd.conf - playlist_directory</li>
    <li>volumeStep x => Schrittweite f&uuml;r Volume +/-</li>
    <li>titleSplit 1|0 => zerlegt die aktuelle Titelangabe am ersten Vorkommen von - (BlankMinusBlank) in die zwei Felder Artist und Titel,<br>
    wenn im abgespielten Titel die Interpreten Information nicht verf&uuml;gbar ist (sehr oft bei Radio-Streams default 1)<br>
    Liegen keine Titelangaben vor wird die Ausgabe durch den Namen der Radiostation ersetzt</li>
    <li>timeout (default 1) => Timeoutwert in Sekunden für die Verbindung fhem-mpd</li>
    <li>waits (default 60) => &Uuml;berwachungszeit in Sekunden f&uuml;r den Idle Prozess. In Verbindung mit refresh_song der Aktualisierungs Intervall für die aktuellen Songparamter,<br>
       (z.B. um den Fortschrittsbalken bei TabletUI aktuell zu halten) </li>
    <li>stateMusic 1|0 => zeige Musikliste als DropDown im Webfrontend</li>
    <li>statePlaylists 1|0 => zeige Playlisten als DropDown im Webfrontend</li>
    <li>player  mpd|mopidy|forked-daapd (default mpd) => welcher Player wird gesteuert<br>
    <b>ACHTUNG</b> : Mopidy unterst&uuml;tzt nicht alle Kommandos des echten MPD ! (siehe <a href="https://docs.mopidy.com/en/latest/ext/mpd/">Mopidy Dokumentation</a>)</li>
    <li>Cover Art Funktionen von <a href="http://www.last.fm/"><b>last.fm</b></a> :</li>
    <li>image_size -1|0|1|2|3  (default -1 = keine Interpretenbilder und Infos von last.fm verwenden)<br>
    last.fm stellt verschiedene Bildgroessen zur Verfügung :<br>
     0 = 32x32 , 1 = 64x64 , 2 = 174x174 , 3 = 300x300</li>
   <li>artist_content 0|1 => stellt Interpreteninformation im Reading artist_content zur Verf&uuml;gung</li>
   <li>artist_summary 0|1 => stellt weitere Interpreteninformation im Reading artist_summary zur Verf&uuml;gung<br>
    Beispiel Anzeige mittels readingsGroup :<br>
    <pre>
      define rg_artist &ltMPD name&gt:artist,artist_image_html,artist_summary
      attr rg_artist room MPD
    </pre></li>
   <li>cache (default lfm => /fhem/www/lfm) Zwischenspeicher für die XML und PNG Dateien<br>
   <b>Wichtig</b> : Der User unter dem der fhem Prozess ausgef&uuml;hrt wird (default fhem) muss Lese und Schreibrechte in diesem Verzeichniss haben !<br>
   Das Verzeichnis sollte auch unterhalb von www liegen, damit der fhem Webserver direkten Zugriff auf die Bilder hat.</li>
  
   </ul>
  <br>
  <b>Readings</b>
  <ul>
    - alle MPD internen Werte<br>
    - vom Modul direkt errzeugte Readings :<br>
    playlistinfo : (TabletUI Medialist)<br>
    playlistcollection : (TabletUI)<br>
    playlistname : (TabletUI)<br> 
    artist_image : (bei Nutzung von Last.fm)<br>
    artist_image_html : (bei Nutzung von Last.fm)<br>
    artist_content : (bei Nutzung von Last.fm)<br>
    artist_summary : (bei Nutzung von Last.fm)<br>

  </ul>
</ul>
=end html_DE

=cut




