################################################################
#
#  (c) 2014 Copyright: Wzut
#  All rights reserved
#
#  FHEM Forum : http://forum.fhem.de/index.php/topic,18517.0.html
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

# Version 1.0   - 21.02.14
# add german doc , readings & state times only on change, devStateIcon
# Version 0.95  - 17.02.14
# add command set IdleNow
# Version 0.9   - 15.02.14
# Version 0.8   - 01.02.14 , first version 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use URI::Escape;
use POSIX;
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
use IO::Socket;
use Getopt::Std;

sub AttrVal($$$);

sub MPD_html($);

my %gets = (
   "music:noArg"          => "",
   "playlists:noArg"      => "",
   "playlistinfo:noArg"   => "",
   "webrc:noArg"          => "",
   "statusRequest:noArg"  => "",
   "mpdCMD"               => "",
   "currentsong:noArg"    => "",
   "outputs:noArg"        => ""
);

my %sets = (
   "play"                  => "",
   "clear:noArg"           => "",
   "stop:noArg"            => "",
   "pause:noArg"           => "",
   "previous:noArg"        => "",
   "next:noArg"            => "",
   "random:noArg"          => "",
   "repaet:noArg"          => "",
   "volume:slider,0,1,100" => "",
   "volumeUp:noArg"        => "",
   "volumeDown:noArg"      => "",
   "playlist"              => "",
   "playfile"              => "",
   "updateDb:noArg"        => "",
   "interval"              => "",
   "mpdCMD"                => "",
   "reset:noArg"           => "",
   "IdleNow:noArg"         => ""
   
  );

my %readings = (
   "title"          => "",
   "name"           => "",
   "playlist"       => "",
   "file"           => "",
   "artist"         => "",
   "album"          => "",
   "songid"         => "",
   "nextsong"       => "",
   "nextsongid"     => "",
   "song"           => "",
   "playlistlength" => "",
   "xfade"          => "",
   "mixrampdelay"   => "",
   "mixrampdb"      => "",
   "consume"        => "",
   "elapsed"        => "",
   "time"           => "",
   "audio"	    => "",
   "bitrate"        => "",
   "pos"	    => "",
   "id"             => "",
   "date"           => "",
   "genre"          => "",
   "track"          => "",
   "state"	    => "",
   "last-modified"  => "",
   "repeat" 	    => "",
   "ramdom" 	    => "",
   "single" 	    => "",
   "volume" 	    => "",
   "error"  	    => "",
   "random"  	    => ""
);

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
  $hash->{AttrList}     = "useIdle:0,1 interval password loadMusic:0,1 loadPlaylists:0,1 volumeStep:1,2,5,10 titleSplit:1,0 lcdDevice ".$readingFnAttributes;
  $hash->{FW_summaryFn} = "MPD_summaryFn";

}

sub MPD_updateConfig($)
{
  # this routine is called 5 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes

 my ($hash) = @_;
 my $name = $hash->{NAME};
 
 $hash->{INTERVAL} = AttrVal($name, "interval", 30);

  $hash->{".htmlCode"}  = "";
  $hash->{".playlist"}  = "";
  $hash->{".music"}     = "";
  $hash->{".outputs"}   = "";
  $hash->{".lasterror"} = "";
  $hash->{".lcd"}       = AttrVal($name, "lcdDevice", undef);
  $hash->{PRESENT}      =  0;
  $hash->{VOLUME}       =  -1;
   
  ## kommen wir via reset Kommando ?
  if ($hash->{".reset"})
  {
    $hash->{".reset"} = 0;
    RemoveInternalTimer($hash);
    if(defined($hash->{helper}{RUNNING_PID}))
    {
      BlockingKill($hash->{helper}{RUNNING_PID});
      Log 3 , "$name Idle Kill PID : ".$hash->{helper}{RUNNING_PID}{pid};
      delete $hash->{helper}{RUNNING_PID};
      $hash->{IPID} = "";
      Log 3 ,"$name Reset done";
    }
  } 

  my $error  = mpd_cmd($hash, "status");

  # Playlisten und Dateien laden ?
  
  if (AttrVal($name, "loadMusic", 0) && !$error)
  { $error = mpd_cmd($hash, "i|lsinfo|music");
     Log 3 ,"$name could not load music -> $error" if ($error);
  }
  if (AttrVal($name, "loadPlaylists", 0) && !$error)
  {
   $error = mpd_cmd($hash, "i|lsinfo|playlists");
   Log 3 ,"$name could not load playlists -> $error" if ($error);
  } 
  
 if (!$error)
 {
   
    $hash->{".outputs"} = mpd_cmd($hash, "i|outputs|x");
    refresh_outputs($hash);

    readingsSingleUpdate($hash,"state","Initialized",1); 

  }
  else  { readingsSingleUpdate($hash,"state","not conected",1); }


  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MPD_GetUpdate", $hash, 0) if ($hash->{INTERVAL});
  
  readingsSingleUpdate($hash,"error",$error,1) if ($error);

return undef;
}

sub MPD_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> $name <MPD ip-address> <MPD port-nr>" if(int(@a) > 4);

  $hash->{HOST} = (defined($a[2])) ? $a[2] : "localhost";
  $hash->{PORT} = (defined($a[3])) ? $a[3] : "6600" ;
  $hash->{".reset"}  = 0;
  
  Log 3, "MPD: Device $name defined.";
  readingsSingleUpdate($hash,"state","defined",1);

  $attr{$name}{devStateIcon} = 'play:rc_PLAY:stop stop:rc_STOP:play pause:rc_PAUSE:pause' unless (exists($attr{$name}{devStateIcon}));
  $attr{$name}{icon}         = 'it_radio' unless (exists($attr{$name}{icon})); 

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "MPD_updateConfig", $hash, 0);

  return undef;
}

sub MPD_Undef ($$) {

  my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);
 if(defined($hash->{helper}{RUNNING_PID}))
 {
  BlockingKill($hash->{helper}{RUNNING_PID});
 }

  return undef;
}

sub MPD_GetUpdate($) {
 my ($hash) = @_;
 my $name = $hash->{NAME};
 my $lasterror = $hash->{".lasterror"};

 my $error  = mpd_cmd($hash, "status");

 if (!$hash->{PRESENT} && $hash->{INTERVAL} eq "0") {$hash->{INTERVAL}  = 300;} # neues Intvall falls keine Verbindung zum MPD Server 

 if (!$error && (($hash->{STATE} eq "play")  || $hash->{READINGS}{"playlistlength"}{VAL})) 
 { 
  $error = mpd_cmd($hash, "currentsong");
 }

  readingsBeginUpdate($hash);
  #readingsBulkUpdate($hash, "state", $hash->{STATE});
  readingsBulkUpdate($hash, "error", $error) if ($error);
  readingsEndUpdate($hash, 1);

 if ($error && ($error ne $lasterror))
 {
   Log 3 , "$name, $error";
   $hash->{".lasterror"} = $error;
 }

 
 InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MPD_GetUpdate", $hash, 0) if ($hash->{INTERVAL});

 my_lcd($hash) if (defined($hash->{".lcd"})); 

 # erster Start bzw neuer Versuch nach Fehler ?
 if (AttrVal($name, "useIdle", 0) && !$error)
 {
  $hash->{helper}{RUNNING_PID} = BlockingCall("MPD_IdleStart", $name."|".$hash->{HOST}."|".$hash->{PORT}, "MPD_IdleDone", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
  $hash->{IPID} = $hash->{helper}{RUNNING_PID};
  Log 4 , "$name IdleStart with PID : ".$hash->{helper}{RUNNING_PID}{pid} if($hash->{helper}{RUNNING_PID});
 }


return;

}


sub MPD_Set($@)
{
 my ($hash, @a)= @_;
 my $name= $hash->{NAME};
 my $ret ;
 
 return join(" ", sort keys %sets) if(@a < 2);

 my $cmd = $a[1];
 return join(" ", sort keys %sets) if ($cmd eq "?");
 
 if ($cmd eq "mpdCMD")  { $ret = MPD_Get($hash, @a); } # pseudo Kommando , gleich mit get mpdCMD 

 my $subcmd = (defined($a[2])) ? $a[2] : "";
 return if ($subcmd eq '---'); # erster Eintrag im select Feld ignorieren

 RemoveInternalTimer($hash);

 my $step    = int(AttrVal($name, "volumeStep", 5)); # vllt runtersetzen auf default = 2 ?

 my $vol_now = int($hash->{VOLUME});
 my $vol_new;
  
 if ($cmd eq "reset")   { $hash->{".reset"} = 1; MPD_updateConfig($hash); return undef;}
 if ($cmd eq "pause")   { $ret = mpd_cmd($hash, "pause");   }
 if ($cmd eq "stop")    { $ret = mpd_cmd($hash, "stop");  }
 if ($cmd eq "update")  { $ret = mpd_cmd($hash, "update");  }
 if ($cmd eq "previous")
 { 
    if (defined($hash->{READINGS}{"song"}{VAL}) > 0)
    {
     $hash->{READINGS}{"title"}{VAL} = "";
     $hash->{READINGS}{"artist"}{VAL} = "";
     $ret = mpd_cmd($hash, "previous"); 
     mpd_cmd($hash, "currentsong") if (!$ret);
    } else { return; }
 }
 
 if ($cmd eq "next")
 { 
  if ($hash->{READINGS}{"nextsong"}{VAL} != $hash->{READINGS}{"song"}{VAL})
   {
    $hash->{READINGS}{"title"}{VAL} = "";
    $hash->{READINGS}{"artist"}{VAL} = "";
    $ret = mpd_cmd($hash, "next");
    mpd_cmd($hash, "currentsong") if (!$ret);
   } else { return; } 
 }

 if ($cmd eq "random")  
  { 
    my $rand = ($hash->{RANDOM}) ? "0" : "1";
    $ret = mpd_cmd($hash, "random $rand");  
  }

 if ($cmd eq "repeat")  
  { 
    my $rep = ($hash->{REPEAT}) ? "0" : "1";
    $ret = mpd_cmd($hash, "repeat $rep");  
  }
 
 if ($cmd eq "clear")   
  { 
    $hash->{READINGS}{"title"}{VAL} = "";
    $hash->{READINGS}{"artist"}{VAL} = "";
    $ret = mpd_cmd($hash, "clear");
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
 if (defined($vol_new)) { $ret = mpd_cmd($hash, "setvol $vol_new"); }


 # einfaches Play bzw Play Listenplatz Nr. ?
 if ($cmd eq "play") 
  {
    $ret = mpd_cmd($hash, "play $subcmd");
    if (!$ret) { $ret =  mpd_cmd($hash, "currentsong"); }
  }


 if ($cmd eq "interval")   
  {
    return "$name: Set with short interval, must be 0 or greater" if(int($a[2]) < 0);
    # update timer
    RemoveInternalTimer($hash);
    $hash->{INTERVAL} = $a[2];
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MPD_GetUpdate", $hash, 0) if ($hash->{INTERVAL});
    return undef;
  }

 if ($cmd eq "IdleNow")   
 {
  return "$name: sorry, one Idle process is always running with pid ".$hash->{helper}{RUNNING_PID}{pid} if($hash->{helper}{RUNNING_PID});
  $hash->{helper}{RUNNING_PID} = BlockingCall("MPD_IdleStart", $name."|".$hash->{HOST}."|".$hash->{PORT}, "MPD_IdleDone", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
  if($hash->{helper}{RUNNING_PID})
        { 
          $hash->{IPID} = $hash->{helper}{RUNNING_PID}{pid};
          return "$name: idle process started with PID : ".$hash->{IPID}; }
   else { return "$name: idle process start failed !"; }
 }



  # die ersten beiden brauchen wir nicht mehr
  shift @a;
  shift @a;
   
  # den Rest als ein String
  $subcmd = join(" ",@a);

 if ($cmd eq "playlist") 
 {
   return "$name : no name !" if (!$subcmd);
   
   $hash->{READINGS}{"title"}{VAL} = "";
   $hash->{READINGS}{"artist"}{VAL} = "";

   $hash->{".music"} = "";
   $hash->{".playlist"} = $subcmd; # interne PL Verwaltung

   $ret = mpd_cmd($hash, "stop|clear|load $subcmd|play");
   # kein Fehler, dann noch die Song Infos holen
   if (!$ret) { $ret =  mpd_cmd($hash, "currentsong"); }
 }

 if ($cmd eq "playfile")
 {
   return "$name : no File !" if (!$subcmd);

   $hash->{READINGS}{"title"}{VAL} = "";
   $hash->{READINGS}{"artist"}{VAL} = "";

   $hash->{".playlist"} = "",
   $hash->{".music"} = $subcmd; # interne Song Verwaltung
   
   $ret = mpd_cmd($hash, "clear|command_list_begin\nadd \"$subcmd\"\ncommand_list_end|play");
   # kein Fehler, dann noch die Song Infos holen
   if (!$ret) { $ret =  mpd_cmd($hash, "currentsong"); }
 }

  mpd_cmd($hash, "status");
 
  # readingsSingleUpdate($hash,"error",$ret,1) if($ret); ToDo : warum ist error manchmal  = "0" ??


  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MPD_GetUpdate", $hash, 0) if ($hash->{INTERVAL});
  my_lcd($hash) if (defined($hash->{".lcd"}));
 
return $ret;
}




sub MPD_Get($@)
{
 my ($hash, @a)= @_;
 my $name= $hash->{NAME};
 my $ret;

 return "get $name needs at least one argument" if(int(@a) < 2);

 my $cmd = $a[1];

 if ($cmd eq "webrc")         { return(MPD_html($hash)); }
 
 if ($cmd eq "playlists")
  { 
    $hash->{".playlists"} = "";
    mpd_cmd($hash, "i|lsinfo|playlists"); 
    return $name." playlists:\n".$hash->{".playlists"}; }
 
 if ($cmd eq "music")         
  {
    $hash->{".music"} = "";
    mpd_cmd($hash, "i|lsinfo|music"); 
    return $name." music:\n".$hash->{".music"}; }
 
  if ($cmd eq "statusRequest") 
  {  $ret = mpd_cmd($hash, "status");
     if (!$ret && $hash->{READINGS}{"playlistlength"}{VAL}) { $ret = mpd_cmd($hash, "currentsong"); } 
    if ($ret) { return $ret; } else { return $name." statusRequest:\n".mpd_cmd($hash, "i|status|x"); } 
  }

  if ($cmd eq "currentsong") 
  {  mpd_cmd($hash, "currentsong");
     return $name." currentsong:\n".mpd_cmd($hash, "i|currentsong|x"); }

 if ($cmd eq "outputs") 
  {  $hash->{".outputs"} = mpd_cmd($hash, "i|outputs|x");
     refresh_outputs($hash);
     return $name." outsputs:\n".$hash->{".outputs"}; }


  if ($cmd eq "mpdCMD") {
      my $sub;
      shift @a;
      shift @a;

      $sub = join (" ", @a);

    return $name." ".$sub.":\n".mpd_cmd($hash, "i|$sub|x");
  }

  if ($cmd eq "playlistinfo") 
  {
    return $name." playlistinfo:\n".mpd_cmd($hash, "i|playlistinfo|x");
  }


 return "$name get with unknown argument $cmd, choose one of " . join(" ", sort keys %gets); 
}

sub my_lcd($)
{
 my ($hash)= @_;
 
 my $error  = $hash->{READINGS}{"error"}{VAL} ne ""  ? $hash->{READINGS}{"error"}{VAL}. " ".$hash->{READINGS}{"error"}{TIME}  : "";
 if (($hash->{STATE} eq "play") || ($hash->{STATE} eq "pause"))
 {
  my $artist = defined($hash->{READINGS}{"artist"}{VAL}) ? $hash->{READINGS}{"artist"}{VAL} : "";
  my $name   = defined($hash->{READINGS}{"name"}{VAL})   ? $hash->{READINGS}{"name"}{VAL}   : $hash->{".playlist"};
  my $state  = $hash->{STATE} eq "pause" ? "P" : "*";     
  my $repeat = $hash->{REPEAT} ? "R" : "-";     
  my $title  = defined($hash->{READINGS}{"title"}{VAL})  ? $hash->{READINGS}{"title"}{VAL}  : "";
  my $song   = defined($hash->{READINGS}{"song"}{VAL})   ? $hash->{READINGS}{"song"}{VAL}+1 : "--";
  my $len    = defined($hash->{READINGS}{"playlistlength"}{VAL}) ? $hash->{READINGS}{"playlistlength"}{VAL} : "--";

   fhem("set ".$hash->{".lcd"}." writeXY 0,0,20,l $artist");
   fhem("set ".$hash->{".lcd"}." writeXY 0,1,20,l $title");
   fhem("set ".$hash->{".lcd"}." writeXY 0,2,20,l $name");
   fhem("set ".$hash->{".lcd"}." writeXY 0,3,3,r ".$hash->{VOLUME});
   fhem("set ".$hash->{".lcd"}." writeXY 5,3,9,l $song/$len $state $repeat");
  }
   else
  {
   fhem("set ".$hash->{".lcd"}." text $error"); $hash->{READINGS}{"error"}{VAL}="";
  }
  
  if (($hash->{STATE} eq "play") || ($hash->{STATE} eq "pause") || $error) 
    {fhem("set ".$hash->{".lcd"}." backlight on"); } else  {fhem("set ".$hash->{".lcd"}." backlight off"); }
  # Log 4 ,"mylcd";
}


sub mpd_cmd($$)
{

 my ($hash,$a)= @_;
 my $output = "";;
 my $name      = $hash->{NAME};
 my $old_state = $hash->{STATE}; # save state


 $hash->{VERSION}  = undef;
 $hash->{PRESENT}  = 0;
 $hash->{STATE}    = "not connected";


 my $iaddr = inet_aton($hash->{HOST})    || return  "no host: ".$hash->{HOST};
 my $paddr = sockaddr_in($hash->{PORT}, $iaddr);
 my $proto = getprotobyname('tcp');

 socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || return "socket: $!";
 connect(SOCK, $paddr)                       || return "connect: $!";
 select(SOCK); $| = 1;
 while (<SOCK>)  # MPD rede mit mir , egal was ;)
 {
  last if $_ ; # end of output.
 }

 chomp $_;

 return  "not a valid mpd server, welcome string was: ".$_ if $_ !~ /^OK MPD (.+)$/;

 $hash->{PRESENT}  = 1;
 
 my ($b , $c) = split("OK " , $_);
 $hash->{VERSION} = $c;
 # ok, now we're connected - let's issue the commands.

 # old state back
 $hash->{STATE} = $old_state;

 my @commands =  split("\\|" , $a);

 if ($commands[0] ne "i")
 { # start Ausgabe nach Readings oder Internals

  foreach (@commands) 
  {
    my $cmd = $_;
    print SOCK "$cmd\r\n";
    while (<SOCK>) 
    {
     chomp $_;
     return  "mpd_Msg ACK ERROR ".$_ if $_ =~ s/^ACK //; # oops - error.
        last if $_ =~ /^OK/;    # end of output.
     ($b , $c) = split(": " , $_);
   
      $b = lc($b);

      if ($b && defined($readings{$b})) # ist das ein Internals oder Reading ?
      { 
        # if ($b eq "state")  { $hash->{STATE}  = $c; }  # Sonderfall state
        if ($b eq "volume") { $hash->{VOLUME} = $c; }  # Sonderfall volume
        if ($b eq "title")
        {
          my $sp = index($c, " - ");
         if (AttrVal($name, "titleSplit", 1) && ($sp>0)) # wer nicht mag solls eben abschaltten
          {
            readingsSingleUpdate($hash,"artist",substr($c,0,$sp),1);
            readingsSingleUpdate($hash,"title",substr($c,$sp+3),1);
          }  else { readingsSingleUpdate($hash,"title",$c,1); } # kein Titel Split
        
        }      
        elsif ($b eq "state")
              { readingsSingleUpdate($hash,"state",$c,1) if ($c ne $hash->{STATE}); }        
               else { readingsSingleUpdate($hash,$b,$c,1) if ($c ne defined($hash->{READINGS}{$b}{VAL}));}  # irgendwas aber kein Titel oder State 
      }     
       else { $hash->{uc($b)} = $c; } # Internal
      
    } # while
  } # foreach
} # end Ausgabe nach Readings oder Internals , ab jetzt Bildschirmausgabe
 else
 { # start internes cmd
  print SOCK $commands[1]."\r\n";
  while (<SOCK>) 
   {
     # chomp $_; - lassen wir das \n ersteinmal noch dran
     return  "mpd_Msg ACK ERROR ".$_ if $_ =~ s/^ACK //; # oops - error.
        last if $_ =~ /^OK/;    # end of output.
      ($b , $c) = split(": " , $_);

     if (($b eq "file" ) && ($commands[2] eq "music")) {$hash->{".music"} .= $c; } # Titelliste füllen
     elsif (($b eq "playlist" ) && ($commands[2] eq "playlists")) {$hash->{".playlists"} .= $c; } # Playliste füllen
       elsif (($b eq "directory" ) && ($commands[2] eq "dir")) {$hash->{".dir"} .= $c; } # Dir liste füllen
        elsif ($commands[2] eq "x") { $output .= $_; }
   } # while
  } # end internes cmd


 print SOCK "close\n";
 close(SOCK) || return  "socketclose: $!";

 return $output; # falls es einen gibt , wenn nicht - auch gut ;)

} # end msg



sub MPD_IdleStart($)
{
 my ($string) = @_;
 return unless(defined($string));

 my @a = split("\\|" ,$string); 

 my $output = $a[0]; # Name
 my $host = $a[1];    
 my $port = $a[2];
 my $old_event = "";

 my $iaddr = inet_aton($host)    || return  $output."|E no host: $host";
 my $paddr = sockaddr_in($port, $iaddr);
 my $proto = getprotobyname('tcp');

 socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || return $output."|E socket: $!";
 connect(SOCK, $paddr)                       || return $output."|E connect: $!";
 select(SOCK); $| = 1;
 while (<SOCK>) 
 {
  last if $_ ; 
 }

 chomp $_;

 return  $output."|E not a valid mpd server, welcome string was: ".$_ if $_ !~ /^OK MPD (.+)$/;

  print SOCK "idle\r\n";
  while (<SOCK>) 
   {
     chomp $_; 
     return  $output."|E mpd_Msg ACK ERROR ".$_ if $_ =~ s/^ACK //; # oops - error.
        last if $_ =~ /^OK/;    # es hat sich was getan.
    if ($_ ne $old_event) { $output .= "|".$_; $old_event = $_; } 
   } 

 print SOCK "close\n";
 close(SOCK);

 return $output;  

} 

sub MPD_IdleDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my ($h,$ret) = split("\\|",$string);
  my $hash = $defs{$h};
  my $name = $hash->{NAME};

  Log 4 , "$name IdleDone PID : ".$hash->{helper}{RUNNING_PID}{pid};
  delete($hash->{helper}{RUNNING_PID});
  $hash->{IPID} = "";

  return if($hash->{helper}{DISABLED});
  
  if (substr($ret,0,1) ne "E")
  {
      # ToDO , den $ret noch nach Typen aufdröseln, jetzt muss ersteinmal status und currentsong reichen
      my $error  = mpd_cmd($hash, "status");
      if (!$error && (($hash->{STATE} eq "play")  || $hash->{READINGS}{"playlistlength"}{VAL})) { $error = mpd_cmd($hash, "currentsong");}
    
      readingsBeginUpdate($hash);
      #readingsBulkUpdate($hash, "state", $hash->{STATE});
      readingsBulkUpdate($hash, "error", $error) if ($error);
      readingsBulkUpdate($hash, "mpd_event", $ret);
      readingsEndUpdate($hash, 1);
 
      # weiter auf Events warten ? oder wurden inzwischen vllt. via attr geändert ?
      if (AttrVal($name, "useIdle", 0) && !$error)
      {
       $hash->{helper}{RUNNING_PID} = BlockingCall("MPD_IdleStart", $name."|".$hash->{HOST}."|".$hash->{PORT}, "MPD_IdleDone", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
       Log 4 , "$name Idle has new PID : ".$hash->{helper}{RUNNING_PID}{pid} if (exists($hash->{helper}{RUNNING_PID}));
       $hash->{IPID} = $hash->{helper}{RUNNING_PID}{pid} if (exists($hash->{helper}{RUNNING_PID}));
      }

      Log 3 , "$name, $error" if ($error);
      my_lcd($hash) if (defined($hash->{".lcd"}));
      return;
  }
  
  readingsSingleUpdate($hash,"mpd_event",$ret,1);
  Log 3 , "$name MPD idle comes back with error : $ret , MPD Idle is now disabled use reset cmd to restart";
  my_lcd($hash) if (defined($hash->{".lcd"}));
  return;
}

###############################################

sub refresh_outputs($)
{
    my ($hash) = @_;
    my @outp = split("\n" , $hash->{".outputs"});
    my $oname;
    my $oen;

   foreach (@outp)
   {
     my @val = split(": " , $_);
     $oname  = $val[1] if ($val[0] eq "outputname");
     if ($val[0] eq "outputenabled") { $oen = ($val[1] eq "1") ? "on" : "off"};
     if ($oen && $oname) {$hash->{uc $oname} = $oen; $oname  = ""; $oen = "";} 
   } 
}


sub MPD_html($) {
 my ($hash)= @_;
 my $name         = $hash->{NAME};
 my $playlist     = $hash->{".playlist"};
 my $playlists    = $hash->{".playlists"};
 my $music        = $hash->{".music"};
 my $volume       = (defined($hash->{VOLUME})) ? $hash->{VOLUME} : "???";
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
    @list = split ("\n",$playlists);
    foreach (@list) 
    {
      $sel = ($_ eq $playlist) ? " selected" : "";
      $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
    }
    $html .= "</optgroup></select></td></tr>";
   }
 
   if ($music) { 
   $html .= "<tr><td colspan=\"5\" align=center><select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playfile ' + this.options[this.selectedIndex].value)\" style=\"font-size:11px;\">";
   $html .= "<optgroup label=\"Music\">";
   $html .= "<option>---</option>"; 
     @list = split ("\n",$music);
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
 $html .= "<td style=\"font-size:14px;\" align='center'>".$pos."</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name next')\"><img src=\"/fhem/icons/remotecontrol/black_btn_FF\" title=\"NEXT\"></a></td>";
 $html .= "<td>&nbsp;</td></tr>";

 $html .= "<tr><td>&nbsp;</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name volumeDown')\"><img src=\"/fhem/icons/remotecontrol/black_btn_VOLDOWN2\" title=\"VOL -\"></a></td>";
 $html .= "<td style=\"font-size:14px;\" align='center'>".$volume."</td>";
 $html .= "<td class=\"rc_button\"><a onClick=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name volumeUp')\"><img src=\"/fhem/icons/remotecontrol/black_btn_VOLUP2\" title=\"VOL +\"></a></td>";
 $html .= "<td>&nbsp;</td></tr>";

 if ($hash->{".outputs"})
 {
   my @outp = split("\n" , $hash->{".outputs"});
   my $oid;
   my $oname;
   my $oen;
   my $osel;
   
   foreach (@outp)
   {
     my @val = split(": " , $_);
      $oid      = $val[1] if ($val[0] eq "outputid");
      $oname  = $val[1] if ($val[0] eq "outputname");
      $oen = $val[1] if ($val[0] eq "outputenabled");
   
     if (defined($oen))
     {
      $html .= "<tr>";
      $html .="<td style='font-size:10px;' colspan='2' align='right'>$oid.$oname</td>";
      $osel = $oen ? "checked" : "";
      $html .="<td style='font-size:10px;' colspan='2'><input type='radio' name='B".$oid." value='1' $osel onclick=\"FW_cmd('/fhem?XHR=1&cmd.$name=get $name mpdCMD enableoutput $oid')\">on&nbsp;";
      $osel = !$oen ? "checked" : "";
      $html .="<input type='radio' name='B".$oid." value='0' $osel onclick=\"FW_cmd('/fhem?XHR=1&cmd.$name=get $name mpdCMD disableoutput $oid')\">off</td><td>&nbsp;</td>";
      $html .="</tr>";
      $oen=undef;
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

        my ($icon,$isHtml,$link,$html,@list,$sel);
 
        ($icon, $link, $isHtml) = FW_dev2image($name);
        $txt = ($isHtml ? $icon : FW_makeImage($icon, $state)) if ($icon);
        $link = "cmd.$name=set $name $link" if ($link);
        $txt  = "<a onClick=\"FW_cmd('/fhem?XHR=1&$link&room=$room')\">".$txt."</a>" if ($link);

        my $title  = defined($hash->{READINGS}{"title"}{VAL}) ? $hash->{READINGS}{"title"}{VAL} : "&nbsp;";
        my $artist = defined($hash->{READINGS}{"artist"}{VAL})? $hash->{READINGS}{"artist"}{VAL}."<br />" : "&nbsp;";
        my $rname  = defined($hash->{READINGS}{"name"}{VAL})  ? $hash->{READINGS}{"name"}{VAL} : "&nbsp;";

        if (!$title && !$artist) { $title = $rname; } # besser das als nix
	$html  ="<table><tr><td>$txt</td><td>";
         if ($playlists) 
         { 
          $html .= "<select  id=\"".$name."_List\" name=\"".$name."_List\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1&cmd.$name=set $name playlist ' + this.options[this.selectedIndex].value)\">";
          $html .= "<optgroup label=\"Playlists\">"; 
          $html .= "<option>---</option>";
          @list = split ("\n",$playlists);
          foreach (@list) 
          {
           $sel = ($_ eq $playlist) ? " selected" : "";
           $html .= "<option ".$sel." value=\"".uri_escape($_)."\">".$_."</option>";
          }
          $html .= "</optgroup></select></td><td>";
         }

	$html .= (($state eq "play") || ($state eq "pause")) ? $artist.$title : "&nbsp;";
	$html .= "</td></tr></table>";
	return $html;	
}



1;

=pod
=begin html

<a name="MPD"></a>
<h3>MPD</h3>
 FHEM module to control a MPD like the MPC (MPC =  Music Player Command, the command line interface to the <a href='http://en.wikipedia.org/wiki/Music_Player_Daemon'>Music Player Daemon</a> )<br>
To install a MPD on a Raspberry Pi you will find a lot of documentation at the web e.g. http://www.forum-raspberrypi.de/Thread-tutorial-music-player-daemon-mpd-und-mpc-auf-dem-raspberry-pi  in german<br>
FHEM Forum : <a href='http://forum.fhem.de/index.php/topic,18517.0.html'>Modul f&uuml;r MPD</a> ( in german )<br>
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
    repaet   => like MPC repeat, toggel on/off<br>
    updateDb => like MPC update<br>
    volume (%) => like MPC volume %, 0 - 100<br>
    volumeUp => inc volume ( + attr volumeStep size )<br>
    volumeDown => dec volume ( - attr volumeStep size )<br>
    playlist (playlist name) => set playlist on MPD Server<br>
    playfile (file) => create playlist + add file to playlist + start playing<br>
    IdleNow => send Idle command to MPD and wait for events to return<br>
    interval => set polling interval of MPD server, overwrites attr interval temp , use 0 to disable polling<br>
    reset => reset MPD Modul<br>
    mpdCMD => same as GET mpdCMD<br>
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
    mpdCMD (cmd) => send a command to MPD Server ( <a href='http://www.musicpd.org/doc/protocol/'>MPD Command Ref</a> )<br>
    currentsong => get infos from current song in playlist<br>
    outputs => get name,id,status about all MPD output devices in /etc/mpd.conf<br>
  </ul>
  <br>
  <a name="MPDattr"></a>
  <b>Attributes</b>
  <ul>
      <li>interval = polling interval at MPD server, use 0 to disable polling (default 30)</li>
      <li>password (not ready yet) if password on MPD server is set</li>
      <li>loadMusic 0|1 = load titles from MPD database at startup</li>
      <li>loadPlaylists 0|1 = load playlist names from MPD database at startup</li>
      <li>volumeStep 1|2|5|10 =  Step size for Volume +/- (default 5)</li>
      <li>useIdle 0|1 = send Idle command to MPD and wait for MPD events needs MPD Version 0.16.0 or greater</li>
      <li>titleSplit 1|0 = split title to artist and title if no artist is given in songinfo (e.g. radio-stream)</li>
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
  FHEM Modul zur Steuerung des MPD &auml;hnlich dem MPC (MPC =  Music Player Command, das Kommando Zeilen Interface f&uuml;r den 
  <a href='http://en.wikipedia.org/wiki/Music_Player_Daemon'>Music Player Daemon</a> ) (englisch)<br>
  Um den MPD auf einem Raspberry Pi zu installieren finden sich im Internet zahlreiche gute Dokumentaionen 
  z.B. <a href="http://www.forum-raspberrypi.de/Thread-tutorial-music-player-daemon-mpd-und-mpc-auf-dem-raspberry-pi">hier</a><br>
  Thread im FHEM Forum : <a href='http://forum.fhem.de/index.php/topic,18517.0.html'>Modul f&uuml;r MPD</a><br>
  <br>&nbsp;<br>
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
    play  => spielt den aktuellen Titel der geladenen Playliste<br>
    clear => l&ouml;scht die Playliste<br>
    stop  => stoppt die Wiedergabe<br>
    pause => Pause an/aus<br>
    previous => spielt den vorherigen Titel in der Playliste<br>
    next => spielt den n&aumlchsten Titel in der Playliste<br>
    random => zuf&auml;llige Wiedergabe an/aus<br>
    repaet => Wiederholung an/aus<br>
    volume (%) => &auml;ndert die Lautst&auml;rke von 0 - 100%<br>
    volumeUp => Lautst&auml;rke schrittweise erh&ouml;hen , Schrittweite = ( attr volumeStep size )<br>
    volumeDown => Lautst&auml;rke schrittweise erniedrigen , Schrittweite = ( attr volumeStep size )<br>
    playlist (playlist name) => lade Playliste <name> aus der MPD Datenbank und starte Wiedergabe mit dem ersten Titel<br>
    playfile (file) => erzeugt eine temor&auml;re Playliste mit file und spielt dieses ab<br>  
    updateDb => wie MPC update, Update der MPD Datenbank<br>
    interval => in Sekunden bis neue aktuelle Informationen vom MPD geholt werden. Überschreibt die Einstellung von attr interval Ein Wert von 0 deaktiviert diese Funktion<br>
    reset => reset des FHEM MPD Moduls<br>
    mpdCMD => gleiche Funktion wie get mpdCMD<br>
    IdleNow => sendet das Kommando idle zum MPD und wartet auf Ereignisse - siehe auch Attribut useIdle<br>
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
    mpdCMD (cmd) => sende cmd direkt zum MPD Server ( siehe auch <a href="http://www.musicpd.org/doc/protocol/">MPD Comm Ref</a> )<br>
    currentsong => zeigt Informationen zum aktuellen Titel in der Playliste<br>
    outputs => zeigt Informationen der definierten MPD Ausgabe Kan&auml;le ( aus /etc/mpd.conf )<br>
  </ul>
  <br>
  <a name="MPDattr"></a>
  <b>Attribute</b>
  <ul> 
    <li>interval 0..x => polling Interval des MPD Servers, 0 zum abschalten oder in Verbindung mit useIdle</li>
    <li>password <pwd> => (z.Z. nicht umgesetzt)</li>
    <li>loadMusic 0|1  => lade die MPD Titel beim FHEM Start</li>
    <li>loadPlaylists 0|1 => lade die MPD Playlisten beim FHEM Start</li>
    <li>volumeStep x => Schrittweite f&uuml;r Volume +/-</li>
    <li>useIdle 0|1 => sendet das Kommando idle zum MPD und wartet auf Ereignisse - ben&ouml;tigt MPD Version 0.16.0 oder h&ouml;her<br>
    Wenn useIdle benutzt wird kann das Polling auf einen hohen Wert (300-600) gesetzt werden oder gleich ganz abgeschaltet werden.<br>
    FHEM startet einen Hintergrundprozess und wartet auf &Auml;nderungen des MPD , wie z.B Titelwechsel im Stream, start/stop, etc.<br>
    So lassen sich relativ zeitnah andere Ger&auml;te an/aus schalten oder z.B. eine LCD Anzeige aktualisieren ohne erst den n&auml;chsten Polling Intervall abwarten zu m&uuml;ssen !</li>
    <li>titleSplit 1|0 = zerlegt die aktuelle Titelangabe am ersten Vorkommen von - (BlankMinusBlank) in die zwei Felder Artist und Titel,<br>
    wenn im abgespielten Titel die Artist Information nicht verf&uuml;gbar ist (sehr oft bei Radio-Streams)<br>
    Liegen keine Titelangaben vor wird die Ausgabe durch den Namen der Radiostation erstetzt</li>
   </ul>
  <br>
  <b>Readings</b>
  <ul>
    alle MPD internen Werte
  </ul>
</ul>
=end html_DE

=cut




