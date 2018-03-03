##############################################
# $Id$
# 
# Support for the "FN-M16P Embedded MP3 Audio Module" aka DFPlayer Mini 
# (http://www.flyrontech.com/eproducts/84.html)
# It can be connected directly
# via serial port @ 9600 baud or via TCP/IP with a transparent serial bridge like ESPEasy
# This seems to be the real and most complete datasheet  
# http://www.flyrontech.com/edownload/6.html
# see also https://www.dfrobot.com/wiki/index.php/DFPlayer_Mini_SKU:DFR0299
# and http://forum.banggood.com/forum-topic-59997.html


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Data::Dumper qw(Dumper);
use Scalar::Util qw(looks_like_number);
use Cwd 'abs_path';
use File::Spec::Functions qw(splitpath catfile);
use File::Copy;
use Digest::MD5 qw(md5_hex);

use constant {
  DFP_INIT_WAIT          => 2,
  DFP_INIT_MAXRETRY      => 3,
  DFP_CMD_TIMEOUT        => 10,
  DFP_KEEPALIVE_TIMEOUT  => 60,
  DFP_KEEPALIVE_MAXRETRY => 3,
  DFP_MIN_WAITTIME       => 0.1, # 0.02,
};

use constant {
  DFP_Start_Byte => 0x7E,
  DFP_Version_Byte => 0xFF,
  DFP_Command_Length => 0x06,
  DFP_End_Byte => 0xEF,
  DFP_Acknowledge => 0x01,  # For each command an answer is sent back 
  DFP_NoAcknowledge => 0x00,
  DFP_FrameLength => 10,
  
  # Equalizermodes
  DFP_EQ_Normal => 0,
  DFP_EQ_Pop => 1,
  DFP_EQ_Rock => 2,
  DFP_EQ_Jazz => 3,
  DFP_EQ_Classic => 4,
  DFP_EQ_Bass => 5,
 
  # Playbacksources
  DFP_PS_USB => 0,
  DFP_PS_SD => 1,
  
  # Errorcodes
  DFP_E_Busy          => 1,
  DFP_E_Sleeping      => 2,
  DFP_E_Receive       => 3,
  DFP_E_Checksum      => 4,
  DFP_E_TrackRange    => 5,
  DFP_E_TrackNotFound => 6,
  DFP_E_Intercut      => 7,
  DFP_E_SDRead        => 8,
  DFP_E_EnteredSleep  => 0x0a,
  
  
  # Commands
  DFP_C_Next => 0x01,
  DFP_C_Previous => 0x02,
  DFP_C_TrackNum => 0x03, # 0-2999
  DFP_C_IncreaseVolume => 0x04,
  DFP_C_DecreaseVolume => 0x05,
  DFP_C_SetVolume => 0x06, # 0-30
  DFP_C_SetEqualizerMode => 0x07,
  DFP_C_SetRepeatSingle => 0x08,
  DFP_C_SetStorage => 0x09,
  DFP_C_Sleep => 0x0a, # DFP responses only with Busy and requires a power cycle
  DFP_C_Wake => 0x0b,  # only supported by FN-M22P
  DFP_C_Reset => 0x0c,
  DFP_C_Play => 0x0d,
  DFP_C_Pause => 0x0e,
  DFP_C_SetPlaybackFolder => 0x0f, # 1-99
  DFP_C_Amplification => 0x10,
  DFP_C_RepeatAllRoot => 0x11,
  DFP_C_SetPlaybackFolderMP3 => 0x12,
  DFP_C_IntercutAdvert => 0x13,
  DFP_C_SetPlaybackFolder3000 => 0x14, # 1-15
  DFP_C_StopAdvert => 0x15,
  DFP_C_Stop => 0x16,
  DFP_C_RepeatFolder => 0x17,
  DFP_C_Shuffle => 0x18,
  DFP_C_RepeatCurrent => 0x19,
  DFP_C_SetDAC => 0x1a,

  # Query Commands and responses
  DFP_C_StoragePluggedIn => 0x3a,
  DFP_C_StoragePulledOut => 0x3b,
  DFP_C_TrackFinishedUSB => 0x3c,
  DFP_C_TrackFinishedSD => 0x3d,
  DFP_C_GetStorage => 0x3f,
  DFP_C_Acknowledge => 0x41,
  DFP_C_Error => 0x40,
  DFP_C_GetStatus => 0x42,
  DFP_C_GetVolume => 0x43,
  DFP_C_GetEqualizerMode => 0x44,
  DFP_C_GetNoTracksRootUSB => 0x47,
  DFP_C_GetNoTracksRootSD => 0x48,
  DFP_C_GetCurrentTrackUSB => 0x4b,
  DFP_C_GetCurrentTrackSD => 0x4c,
  DFP_C_GetNoTracksInFolder => 0x4e,
  DFP_C_GetNoFolders => 0x4f,
};

my %errorTexts = (
  &DFP_E_Busy          => "Busy",
  &DFP_E_Sleeping      => "Sleeping",
  &DFP_E_Receive       => "Receive Error",
  &DFP_E_Checksum      => "Checksum Error",
  &DFP_E_TrackRange    => "Track out of range",
  &DFP_E_TrackNotFound => "Track not found",
  &DFP_E_Intercut      => "Intercut not possible",
  &DFP_E_SDRead        => "SD card read failed",
  &DFP_E_EnteredSleep  => "Entered sleep mode",
);

my %statusStorageTexts = (
  0 => "no storage",
  1 => "USB",
  2 => "SD",
  4 => "connected to PC",
  16 => "Sleep mode",
);
my %statusModeTexts = (
  0 => "stopped",
  1 => "playing",
  2 => "paused",
);
my %equalizerTexts = (
  &DFP_EQ_Normal => "Normal",
  &DFP_EQ_Pop => "Pop",
  &DFP_EQ_Rock => "Rock",
  &DFP_EQ_Jazz => "Jazz",
  &DFP_EQ_Classic => "Classic",
  &DFP_EQ_Bass => "Bass",
);

sub DFPlayerMini_Attr(@);
sub DFPlayerMini_HandleWriteQueue($);
sub DFPlayerMini_Parse($$);
sub DFPlayerMini_Read($);
sub DFPlayerMini_Ready($);
sub DFPlayerMini_Write($$$);
sub DFPlayerMini_SimpleWrite(@);

my %gets = (    # Name, Data to send to the DFPlayer Mini, Regexp for the answer
  "storage" => [ DFP_C_GetStorage, 'noArg' ],
  "status"  => [ DFP_C_GetStatus, 'noArg' ],
  "volume" =>  [ DFP_C_GetVolume, 'noArg' ],
  "equalizer" => [ DFP_C_GetEqualizerMode, 'noArg' ],
  "noTracksRootUsb" => [ DFP_C_GetNoTracksRootUSB, 'noArg'],
  "noTracksRootSd" => [ DFP_C_GetNoTracksRootSD, 'noArg'],
  "currentTrackUsb" => [ DFP_C_GetCurrentTrackUSB, 'noArg'],
  "currentTrackSd" => [ DFP_C_GetCurrentTrackSD, 'noArg'],
  "noTracksInFolder" => [ DFP_C_GetNoTracksInFolder, ""],
  "noFolders" => [DFP_C_GetNoFolders, 'noArg'],
);


my %sets = (
  # corresponding to DFP commands
  "next"       => 'noArg',
  "prev" => 'noArg',
  "trackNum" => "",
  "volumeUp"     => "noArg",
  "volumeDown"     => "noArg",
  "volumeStraight"     => 'slider,0,1,30',
  "equalizer" => join(",", values(%equalizerTexts)),
  "repeatSingle" => '',
  "storage" => 'USB,SD',
  "sleep" => 'noArg',
  "wake" => 'noArg',
  "reset" => "noArg",
  "play" => "",
  "pause"     => 'noArg',
  "amplification" => "slider,0,1,31",
  "repeatRoot"  => 'on,off',
  "MP3TrackNum" => "",
  "intercutAdvert" => "",
  "folderTrackNum" => "",
  "folderTrackNum3000" => "",
  "stopAdvert"     => 'noArg',
  "stop"     => 'noArg',
  "repeatFolder" => '',
  "shuffle" => 'noArg',
  "repeatCurrentTrack" => 'on,off',
  "DAC" => "on,off",
  # helper commands
  "close" => "noArg",
  "raw" => "",
  "uploadTTS" => "",
  "uploadTTScache" => "",
  "uploadNumbers" => "",
  "sayNumber" => "",
  "readFiles" => "noArg",
  "response" => "",
  "reopen" => "noArg",
  "tts" => "",
  #"playlist" => "noArg",
);

sub
DFPlayerMini_getKeyByValue($$) {
  my ($hash, $val) = $@;
  
}


sub
DFPlayerMini_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "DFPlayerMini_Read";
  $hash->{WriteFn} = "DFPlayerMini_Write";
  $hash->{ReadyFn} = "DFPlayerMini_Ready";

# Normal devices
  $hash->{DefFn}         = "DFPlayerMini_Define";
  $hash->{FingerprintFn}   = "DFPlayerMini_FingerprintFn";
  $hash->{UndefFn}        = "DFPlayerMini_Undef";
  $hash->{GetFn}         = "DFPlayerMini_Get";
  $hash->{SetFn}         = "DFPlayerMini_Set";
  $hash->{AttrFn}        = "DFPlayerMini_Attr";
  $hash->{NotifyFn}     = "DFPlayerMini_Notify";
  $hash->{AttrList}      = "requestAck:0,1 TTSDev uploadPath sendCmd keepAliveInterval"
                          . " rememberMissingTTS:0,1 do_not_notify:1,0 "
                          ." $readingFnAttributes";

  $hash->{ShutdownFn} = "DFPlayerMini_Shutdown";
  $hash->{parseParams} = 1;
  
  $hash->{PLAYQUEUE} = ();
  $hash->{TTSQUEUE} = ();

}

sub
DFPlayerMini_FingerprintFn($$)
{
  my ($name, $msg) = @_;

  return ($name, $msg);
}

#####################################
sub
DFPlayerMini_Define($$)
{
  my ($hash, $a, $h) = @_;

  if(int(@$a) != 3) {
    my $msg = "wrong syntax: define <name> DFPlayerMini {none | devicename[\@baudrate] | devicename\@directio | hostname:port}";
    Log3 undef, 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);
  my $name = @$a[0];

  
  my $dev = @$a[2];
 
 
  if ($dev ne "none" && $dev =~ m/[a-zA-Z]/ && $dev !~ m/\@/) {    # bei einer IP wird kein \@9600 angehaengt
    $dev .= "\@9600";
  }
  
  $hash->{DeviceName} = $dev;
  
  my $ret=undef;

  if($dev ne "none") {
    $ret = DevIo_OpenDev($hash, 0, "DFPlayerMini_DoInit", 'DFPlayerMini_Connect');
    
  } else {
    DFPlayerMini_DoInit($hash);
    $hash->{DevState} = 'initialized';
    readingsSingleUpdate($hash, "state", "opened", 1);
  }
  $hash->{NOTIFYDEV} = "global";

  
  $hash->{LAST_SEND_TS}=0;
  $hash->{LAST_RECV_TS}=0;
  $hash->{helper}{LAST_RESPONSE} = "";
  
  if ($init_done) {
    $attr{$name}{cmdIcon} = "volumeDown:rc_VOLMINUS volumeUp:rc_VOLPLUS prev:rc_PREVIOUS play:rc_PLAY next:rc_NEXT pause:rc_PAUSE stop:rc_STOP";
    $attr{$name}{webCmd} = "volumeStraight:volumeDown:volumeUp:prev:play:next:pause:stop";
    $attr{$name}{icon} = "audio_audio";
  }
  return $ret;
}

###############################
sub DFPlayerMini_Connect($$)
{
  my ($hash, $err) = @_;

  # damit wird die err-msg nur einmal ausgegeben
  if (!defined($hash->{disConnFlag}) && $err) {
    Log3($hash, 3, "DFPlayerMini $hash->{NAME}: ${err}");
    $hash->{disConnFlag} = 1;
  }
}

#####################################
sub
DFPlayerMini_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "$name: deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DFPlayerMini_Shutdown($hash);
  
  DevIo_CloseDev($hash); 
  RemoveInternalTimer($hash);    
  return undef;
}

#####################################
sub
DFPlayerMini_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}


#####################################
sub 
DFPlayerMini_createCmd($$;$$) 
{
  my ($hash, $cmd, $par1, $par2) = @_;
  
  $par1 = 0 if !defined $par1; 
  $par2 = 0 if !defined $par2; 
  
  my $requestAck = AttrVal($hash->{NAME}, "requestAck", 0) || $cmd == DFP_C_Acknowledge;
  
  my $checksum = -(DFP_Version_Byte+DFP_Command_Length+$cmd+$requestAck+$par1+$par2);
  return pack('CCCCCCCnC', DFP_Start_Byte,DFP_Version_Byte, DFP_Command_Length, $cmd, $requestAck, $par1, $par2, $checksum, DFP_End_Byte);
  
}


#####################################
sub
DFPlayerMini_uploadTTScache($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ttsDev = AttrVal($name, "TTSDev", "");
  my $uploadPath = AttrVal($name, "uploadPath", "");

  return "please set attribute TTSDev to a valid Text2Speech device" if $ttsDev eq "";
  return "please set attribute uploadPath to root directory of the SD card/USB stick the sound files should be uploaded to" if $uploadPath eq "";
  return "$uploadPath doesn't exist" if !-e $uploadPath;
  return "$uploadPath must be a directory" if !-d $uploadPath;
  return "$uploadPath must be writable" if !-x $uploadPath;
  
  my $TTS_CacheFileDir = AttrVal($ttsDev, "TTS_CacheFileDir", "cache");
  my $noTracks = 0;
  my $folder = 1;
  my $srcFile;
  my $destDir;
  my $destFile;
  my $md5;
  if (opendir CACHE, $TTS_CacheFileDir) {
    while ($srcFile = readdir CACHE) {
      next if $srcFile eq '.' or $srcFile eq '..';
      $noTracks++;
      if ($noTracks > 3000) {
        $noTracks = 0;
        $folder++;
      }
      last if $folder > 15; # return "too many files in $TTS_CacheFileDir, stopping after " . 15*3000
      
      $destDir = catfile($uploadPath, sprintf("%02d", $folder)); 
      if (!-e $destDir) {
        mkdir $destDir, 511 or return "failed to create directory $destDir: $!";
      }

      $destFile = catfile($destDir, sprintf("%04dMD5%s", $noTracks, $srcFile));
      $srcFile = catfile($TTS_CacheFileDir, $srcFile);
      $md5= $srcFile;
      $md5 =~ s/.mp3$//;
      delete $hash->{READINGS}{"Missing_MD5$md5"};
      Log3 $name, 4, "$name: cp $srcFile $destFile";
      copy($srcFile, $destFile);
    }
    closedir CACHE;
  }
 
  return undef;
}

#####################################
sub
DFPlayerMini_uploadNumbers($$)
{
  my ($hash, $destDir) = @_;
  my $name = $hash->{NAME};
  
  #my @terms = qw(ein zwei drei);
   my @terms = qw(null ein zwei drei vier f&uuml;nf sechs sieben acht neun zehn elf zw&ouml;lf
                  zwanzig dreissig vierzig f&uuml;nfzig sechzig siebzig achtzig neunzig hundert
                  sechzehn siebzehn und hundert tausend million millionen komma minus);
   
  my $i=1;
  foreach my $term (@terms) {
    my $filename = "${i}${term}";
    $i++;
    Log3 $name, 5, "$name: calling uploadTTS " . catfile($destDir, $filename) . " $term";
    my $ret = DFPlayerMini_uploadTTS($hash, catfile($destDir, $filename), $term);
    return $ret if $ret;
  } 
  return "";
}

#####################################
# taken from Lingua::DE::Num2Word (http://search.cpan.org/~rvasicek/Lingua-DE-Num2Word-0.03/Num2Word.pm)
sub DFPlayerMini_num2de_cardinal {
  my $positive = shift;

  my @tokens1 = qw(null ein zwei drei vier f&uuml;nf sechs sieben acht neun zehn elf zw&ouml;lf);
  my @tokens2 = qw(zwanzig dreissig vierzig f&uuml;nfzig sechzig siebzig achtzig neunzig hundert);

  return $tokens1[$positive]           if($positive >= 0 && $positive < 13); # 0 .. 12
  return 'sechzehn'                    if($positive == 16);                  # 16 exception
  return 'siebzehn'                    if($positive == 17);                  # 17 exception
  return ($tokens1[$positive-10], 'zehn') if($positive > 12 && $positive < 20); # 13 .. 19

  my @out = ();          # string for return value construction
  my $one_idx;      # index for tokens1 array
  my $remain;       # remainder

  if($positive > 19 && $positive < 101) {              # 20 .. 100
    $one_idx = int ($positive / 10);
    $remain = $positive % 10;

    push @out, ($tokens1[$remain], "und") if $remain;
    push @out, $tokens2[$one_idx-2];

  } elsif($positive > 100 && $positive < 1000) {       # 101 .. 999
    $one_idx = int ($positive / 100);
    $remain  = $positive % 100;

    push @out, ($tokens1[$one_idx], "hundert");
    push @out, $remain ? &DFPlayerMini_num2de_cardinal($remain) : '';

  } elsif($positive > 999 && $positive < 1_000_000) {  # 1000 .. 999_999
    $one_idx = int ($positive / 1000);
    $remain  = $positive % 1000;

    push @out, (&DFPlayerMini_num2de_cardinal($one_idx), 'tausend');
    push @out, $remain ? &DFPlayerMini_num2de_cardinal($remain) : '';

  } elsif($positive > 999_999 &&
    $positive < 1_000_000_000) {                 # 1_000_000 .. 999_999_999
    $one_idx = int ($positive / 1000000);
    $remain  = $positive % 1000000;
    my $one  = $one_idx == 1 ? 'e' : '';

    push @out, (&DFPlayerMini_num2de_cardinal($one_idx), $one);
    push @out, $one_idx > 1 ? "millionen" : "million";
    if ($remain) {
      push @out, &DFPlayerMini_num2de_cardinal($remain);
    }
  }

  return @out;
}

#####################################
sub
DFPlayerMini_sayNumber($$)
{
  my ($hash, $number) = @_;
  
  if ($number =~ /(^-?\d+)\.?(\d*)$/) {
    my $intpart = $1;
    my $decpart = $2;

    my @terms;
  
    if ($intpart < 0) {
      push @terms, "minus" ;
      $intpart *= -1;
    }
    push @terms, DFPlayerMini_num2de_cardinal($intpart);
    if ($decpart) {
      push @terms, "komma";
      for (my $i=0; $i<length($decpart); $i++) {
        push @terms, DFPlayerMini_num2de_cardinal(substr($decpart,$i,1));
      }
    }
    DFPlayerMini_Play($hash, @terms);
  } else {  
    return "$number is not a number";
  }
}

#####################################
sub
DFPlayerMini_tts($$)
{
  my ($hash, $ttsSay) = @_;
  my $name = $hash->{NAME};
  
  my $ttsDev = AttrVal($name, "TTSDev", "");
  return "please enter a text to be translated to speech" if $ttsSay eq "";
  return "please set attribute TTSDev to a valid Text2Speech device" if $ttsDev eq "";
  
  my $ttsCmd = "! " . $ttsSay;
  push @{$hash->{TTSQUEUE}}, $ttsCmd;
  $hash->{LAST_TTS} = $ttsSay;
  if (ReadingsVal($ttsDev, "playing", 1)) {
    # tts currently going on. As Text2Speech has no queue we create an own one
    # to avoid interrupting an ongoing tts operation
    Log3 $name, 4, "$name: tts busy, queueing $ttsCmd";
    $hash->{TTS_BUSY} = 1;
    return;
  }
  fhem "set $ttsDev tts " . $ttsSay;

}

#####################################
sub
DFPlayerMini_uploadTTS($$$)
{
  my ($hash, $destFile, $ttsSay) = @_;
  my $name = $hash->{NAME};
  my $ttsDev = AttrVal($name, "TTSDev", "");
  my $uploadPath = AttrVal($name, "uploadPath", "");
  my $maxTracks = 0;
  my $trackNum = 0;
  my $trackName = "";
 
  

  return "please enter a text to be translated to speech" if $ttsSay eq "";
  return "please set attribute TTSDev to a valid Text2Speech device" if $ttsDev eq "";
  return "please set attribute uploadPath to root directory of the SD/USB the sound files should be uploaded to" if $uploadPath eq "";
  return "$uploadPath doesn't exist" if !-e $uploadPath;
  return "$uploadPath must be a directory" if !-d $uploadPath;
  return "$uploadPath must be writable" if !-x $uploadPath;

 
  # 01/1Test
  # MP3/003Song
  my ($destvol, $dirname, $filename) = splitpath($destFile);
  
  $dirname =~ s/(\\|\/)$//; # remove trailing / or \
  $dirname = uc($dirname);
  
  if ($dirname eq "MP3") {
    $maxTracks = 65536;
  } elsif ($dirname eq "ADVERT") {
    $maxTracks = 3000;
  } elsif ($dirname =~ /^\d{1,2}$/) {
    my $folderNum = int($dirname);

    return "folder must be between 1 and 99" if $folderNum < 1;
    
    if ($folderNum <= 15) {
      $maxTracks = 3000;
    } else {
      $maxTracks = 255;
    }
    $dirname = sprintf("%02d", $folderNum);
  } elsif ($dirname eq ".") {
    $maxTracks = 99;
  } else {
    return "$dirname must be either MP3, ADVERT, . or a number between 1 and 99";
  }
  if ($filename =~ /(\d{1,5})(.*)/) {
    $trackNum = $1;
    $trackName = $2;
    if ($trackNum < 1 || $trackNum > $maxTracks) {
      return "track number $trackNum must be between 1 and $maxTracks";
    }
  } else {
    return "$destFile filename must start with digits but no more than 5";
  }
  
  my $digits = length("$maxTracks");
  my $formattedTrackNum = sprintf("%0${digits}d", $trackNum);
  $destFile = $formattedTrackNum . $trackName;
  
  my $destDir = catfile($uploadPath, $dirname);

  
  if (!-e $destDir) {
    mkdir $destDir, 511 or return "failed to create directory $destDir: $!";
  }
  
  # delete all files which start with the same number as the current track as the DFP identifies a file only by the number
  my $deletePattern = catfile($destDir, $formattedTrackNum) . '*';
  Log3 $name, 5, "$name: deleting: $deletePattern";
  unlink glob($deletePattern);
 

  $destFile = catfile($dirname,  $destFile);
  Log3 $name, 5, "$name: destFile = $destFile ttsSay = $ttsSay";
  my $ttsCmd = $destFile . " " . $ttsSay;
  push @{$hash->{TTSQUEUE}}, $ttsCmd;
  if (ReadingsVal($ttsDev, "playing", 1)) {
    # tts currently going on. As Text2Speech has no queue we create an own one
    # to avoid interrupting an ongoing tts operation
    Log3 $name, 4, "$name: tts busy, queueing $ttsCmd";
    $hash->{TTS_BUSY} = 1;
    return;
  }

  
 
  fhem "set $ttsDev tts " . $ttsSay;
  
  # when tts is done, DFPlayerMini_Notify will be called

  return undef;
}

#####################################
sub
DFPlayerMini_readFiles($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $fileNo;
  my $fileName;
  my $file;
  my @allfiles;
  
  my $path = AttrVal($hash->{NAME}, "uploadPath", "");
  return "please set attribute uploadPath" if $path eq "";
  
  my @dirs = ("MP3", "ADVERT");
  for my $count (1..99) {
    push @dirs, (sprintf("%02d",$count));
  }
  
  foreach my $dir (@dirs) {
    #Log3 $name, 4, "$name: reading $dir...";
    my $mp3dir = catfile($path, $dir);
    if (opendir MP3DIR, $mp3dir) {
      push @allfiles, map "File_$dir/$_", grep /[0-9]{3,4}.*\.(mp3|wav)/, readdir MP3DIR;
      closedir MP3DIR;
    } else {
      #Log3 $name, 4, "$name: can't open $mp3dir";
    }
  }
  readingsBeginUpdate($hash);
  foreach my $reading (grep /File_.*\/[0-9]{3,4}/, keys %{$hash->{READINGS}}) {
    #Log3 $name, 4, "$name: deleting $reading"; 
    delete($hash->{READINGS}{$reading});
  }

  foreach $file (@allfiles) {
    #Log3 $hash, 5, "$name: file $file";
    my ($fileNo, $fileName) = ($file =~ /(File_.*\/[0-9]{3,4})(.*)\.(mp3|wav)/);
    readingsBulkUpdate($hash, $fileNo, $fileName); 
  }
  readingsEndUpdate($hash,0);
  
  return undef;
  
}

#####################################
sub DFPlayerMini_Play($@)
{
  my ($hash, @args) = @_;
  my $name = $hash->{NAME};
  my $found = 0;
  my $r;
  
  foreach my $arg (@args) {
    Log3 $name, 5, "$name: playing $arg";
    if ($arg !~ /\//) {
      # not a reading name (which must contain a /), search the reading values
      
      if (ReadingsVal($name, "advertPossible", 0) == 1) {
        # first try to play as advert
       foreach $r (grep /^File_ADVERT/, keys %{$hash->{READINGS}}) {
          #Log3 $name, 5, "$name: testing $r " . $hash->{READINGS}{$r};
          if ($hash->{READINGS}{$r}{VAL} eq $arg ) {
            $arg = $r;
            $found = 1;
            last;
          }
        }
      } 
      if (!$found) {
        foreach $r (grep /^File_[^A]/, keys %{$hash->{READINGS}}) {
          #Log3 $name, 5, "$name: testing $r " . $hash->{READINGS}{$r};
          if ($hash->{READINGS}{$r}{VAL} eq $arg ) {
            $arg = $r;
            last;
          }
        }
      }
    }
    my $playArg = ReadingsVal($name, $arg, undef);
    if (!defined $playArg) {
      $playArg = ReadingsVal($name, "File_$arg", undef);
    }
    if (defined $playArg) {
      my ($fileMarker, $path) = split(/_/, $arg, 2);
      my ($folder, $track) = split(/\//, $path, 2);
      $folder = uc($folder);
      Log3 $name, 2, "$name: path $path folder $folder track $track";
      if ($folder eq "MP3") {
        DFPlayerMini_AddToPlayQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolderMP3, $track >> 8, $track & 0xff), 0);
      } elsif ($folder eq "ADVERT") {
        DFPlayerMini_AddToPlayQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_IntercutAdvert, $track >> 8, $track & 0xff), 1);
      } elsif (looks_like_number($folder) && $folder >= 1 && $folder <= 99) {
        if ($folder <=15 && $track >= 1 && $track <= 3000) {
          DFPlayerMini_AddToPlayQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolder3000, ($folder << 4) | ($track >> 8), $track & 0xff), 0);
        } else {
          DFPlayerMini_AddToPlayQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolder, $folder, $track), 0);
        } 
      } else {
        return "invalid folder $folder";
      }
    } else {
      Log3 $name, 5, "$name: track not found $arg";
      if ($arg =~ /^MD5/) {
        readingsSingleUpdate($hash, "Missing_$arg", $hash->{LAST_TTS}, 0) if AttrVal($name, "rememberMissingTTS", 0);
        return "no matching file found";
      } else {
        return "can't find track $arg";
      }
    }
  }
}

#####################################
sub
DFPlayerMini_AddToPlayQueue($$$)
{
  my ($hash, $msg, $isAdvert) = @_;
  
  if (@{$hash->{PLAYQUEUE}} == 0) {
    # queue is empty, play immediately
    DFPlayerMini_AddSendQueue($hash,$msg);
  } 
  if ($isAdvert) {
    # insert before the first non advert is there is one, else just add it at the end
    for (my $i = 0; $i < @{$hash->{PLAYQUEUE}}; $i++) {
      if (substr(@{$hash->{PLAYQUEUE}}[$i], 3, 1) != DFP_C_IntercutAdvert) {
        splice @{$hash->{PLAYQUEUE}}, $i, 0, ($msg);
        return;
      }
    }
  }
  push @{$hash->{PLAYQUEUE}}, $msg;
  
}

#####################################
sub
DFPlayerMini_Set($$$)
{
  my ($hash, $a, $h) = @_;
  
  return "\"set $hash->{NAME}\" needs at least one parameter" if(int(@$a) < 2);
  if (!defined($sets{@$a[1]})) {
    my $arguments = ' ';
    foreach my $arg (sort keys %sets) {
      $arguments.= $arg . ($sets{$arg} ? (':' . $sets{$arg}) : '') . ' ';
    }
    #Log3 $hash, 3, "$name: set arg = $arguments";
    return "Unknown argument @$a[1], choose one of " . $arguments;
  }

  my $name = shift @$a;
  my $cmd = shift @$a;
  my $arg = join(" ", @$a);
  my $ret = "";
  
  if( $cmd eq "next" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Next));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
  } elsif( $cmd eq "prev" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Previous));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
  } elsif( $cmd eq "trackNum" ) {
    return "track number must be between 1 and 3000" if (!looks_like_number($arg) || $arg < 1 || $arg > 3000);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_TrackNum, $arg >> 8, $arg & 0xff));
  } elsif( $cmd eq "volumeUp" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_IncreaseVolume));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_GetVolume));
  } elsif( $cmd eq "volumeDown" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_DecreaseVolume));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_GetVolume));
  } elsif( $cmd eq "volumeStraight" ) {
    return "volume must be between 0 and 30" if (!looks_like_number($arg) || $arg < 0 || $arg > 30);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetVolume,0,$arg));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_GetVolume));
  } elsif( $cmd eq "equalizer" ) {
    my $k; my $key;
    my $val;
    foreach $key (keys %equalizerTexts) {
      if ($equalizerTexts{$key} eq $arg) {
        $val = $equalizerTexts{$key};
        $k = $key;
        last;
      }
    }
    return "unknown input $arg" if !defined $val;
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetEqualizerMode, 0, $k));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_GetEqualizerMode));
  } elsif( $cmd eq "repeatSingle" ) {
    return "track number must be between 1 and 99" if (!looks_like_number($arg) || $arg < 1 || $arg > 99);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetRepeatSingle, $arg >> 8, $arg & 0xff));
  } elsif( $cmd eq "storage" ) {
    my $k; my $key;
    my $val;
    foreach $key (keys %statusStorageTexts) {
      if ($statusStorageTexts{$key} eq $arg) {
        $val = $statusStorageTexts{$key};
        $k = $key;
        last;
      }
    }
    return "unknown input $arg" if !defined $val;
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetStorage, 0, $k));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_GetStorage));
  } elsif( $cmd eq "sleep" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Sleep));
  } elsif( $cmd eq "wake" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Wake));
  } elsif( $cmd eq "reset" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Reset));
  } elsif( $cmd eq "play" ) {
    if ($arg eq "") {
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Play));
    } else {
      $ret = DFPlayerMini_Play($hash, @$a);
    }
    if (!$ret) {
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
    }
    return $ret;
  } elsif( $cmd eq "pause" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Pause));
    readingsSingleUpdate($hash, "advertPossible", 0, 1);
  } elsif( $cmd eq "amplification" ) {
    return "amplification must be between 0 and 31" if (!looks_like_number($arg) || $arg < 0 || $arg > 31);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Amplification, $arg > 0 ? 1 : 0, $arg));
  } elsif( $cmd eq "repeatRoot" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_RepeatAllRoot, 0, $arg eq "on" ? 1 : 0));
  } elsif( $cmd eq "MP3TrackNum" ) {
    return "track number must be between 1 and 65536" if (!looks_like_number($arg) || $arg < 1 || $arg > 65536);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolderMP3, $arg >> 8, $arg & 0xff));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
  } elsif ($cmd eq "intercutAdvert") {
    return "track number must be between 1 and 3000" if (!looks_like_number($arg) || $arg < 1 || $arg > 3000);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_IntercutAdvert, $arg >> 8, $arg & 0xff));
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
  } elsif( $cmd eq "folderTrackNum" ) {
    my ($folder, $track) = split(" ", $arg, 2);
    return "folder and track must be numeric" if (!looks_like_number($folder) || !looks_like_number($track));
    if ($folder >= 1 && $folder <= 99 && $track >= 1 && $track <= 255) {
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolder, $folder, $track));
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
    } else {
      return "track or folder number out of range";
    }
  } elsif( $cmd eq "folderTrackNum3000" ) {
    my ($folder, $track) = split(" ", $arg, 2);
    return "folder and track must be numeric" if (!looks_like_number($folder) || !looks_like_number($track));
    if ($folder >= 1 && $folder <=15 && $track >= 1 && $track <= 3000) {
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetPlaybackFolder3000, ($folder << 4) | ($track >> 8), $track & 0xff));
      DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, ReadingsVal($name,"storage","SD") eq "SD" ? DFP_C_GetCurrentTrackSD : DFP_C_GetCurrentTrackUSB));  
    } else {
      return "track or folder number out of range";
    }
  } elsif( $cmd eq "stopAdvert" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_StopAdvert));
  } elsif( $cmd eq "stop" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Stop));
    readingsSingleUpdate($hash, "advertPossible", 0, 1);
  } elsif( $cmd eq "repeatFolder" ) {
    return "folder number must be between 1 and 99" if (!looks_like_number($arg) || $arg < 1 || $arg > 99);
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_RepeatFolder, 0, $arg));
  } elsif( $cmd eq "shuffle" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_Shuffle));
  } elsif( $cmd eq "repeatCurrentTrack" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_RepeatCurrent, 0, $arg eq "on" ? 1 : 0));
  } elsif( $cmd eq "DAC" ) {
    DFPlayerMini_AddSendQueue($hash,DFPlayerMini_createCmd($hash, DFP_C_SetDAC, 0, $arg eq "on" ? 1 : 0));

  } elsif( $cmd eq "close" ) {
    $hash->{DevState} = 'closed';
    return DFPlayerMini_CloseDevice($hash);
  } elsif($cmd eq "raw") {
    Log3 $name, 4, "$name: set $name $cmd $arg";
    DFPlayerMini_AddSendQueue($hash,pack("H*", uc($arg)));
  } elsif ($cmd eq "reopen") {
    return DFPlayerMini_ResetDevice($hash);
  } elsif ($cmd eq "readFiles") {
    return DFPlayerMini_readFiles($hash);
  } elsif ($cmd eq "uploadTTS") {
    my $destFile = shift @$a;
    my $ttsSay = join(" ", @$a);
    return DFPlayerMini_uploadTTS($hash, $destFile, $ttsSay);
  } elsif ($cmd eq "uploadNumbers") {
    return DFPlayerMini_uploadNumbers($hash, $arg);
  } elsif ($cmd eq "uploadTTScache") {
    return DFPlayerMini_uploadTTScache($hash);  
  } elsif ($cmd eq "sayNumber") {
    return DFPlayerMini_sayNumber($hash, $arg);
  } elsif ($cmd eq "tts") {
    my $ttsSay = join(" ", @$a);
    return DFPlayerMini_tts($hash, $ttsSay);
  } elsif ($cmd eq "response") {
    return "response must be 10 hex bytes long" if length($arg) != 20; 
    DFPlayerMini_Parse($hash, pack("H*", substr($arg,6,8)));
  #} elsif ($cmd eq "playlist") {
  #  DFPlayerMini_SimpleWrite($hash, pack("H*", "7EFF1521010201030104010501060201030504070509EF"));
  } else {
    Log3 $name, 5, "$name/set: set $name $cmd $arg";
    #DFPlayerMini_SimpleWrite($hash, $arg);
    return "Unknown argument $cmd, choose one of ". ReadingsVal($name,'cmd',' help me');
  }

  return undef;
}

#####################################
sub
DFPlayerMini_Get($$$)
{
  my ($hash, $a, $h) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  
  Log3 $name, 5, "$name: \"get $type\" needs at least one parameter" if(@$a < 2);
  return "\"get $name\" needs at least one parameter" if(@$a < 2);
  if(!defined($gets{@$a[1]})) {
    my $arguments = ' ';
    foreach my $arg (sort keys %gets) {
      $arguments.= $arg . ($gets{$arg}[1] ? (':' . $gets{$arg}[1]) : '') . ' ';
    }
    #Log3 $hash, 5, "$name: get arg = $arguments";  
  
    return "Unknown argument @$a[1], choose one of " . $arguments;
  }
 
  my $cmd = @$a[1];
  my $arg = @$a[2];
 
  #Log3 $name, 5, "$name: command for gets: $cmd" . unpack("H*", $gets{$cmd}[0]);

  
  DFPlayerMini_AddSendQueue($hash, DFPlayerMini_createCmd($hash, $gets{$cmd}[0], undef, $arg));
  
  return undef;
}

#####################################
sub
DFPlayerMini_ResetDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $hash, 3, "$name reset"; 
  DevIo_CloseDev($hash);
  my $ret = DevIo_OpenDev($hash, 0, "DFPlayerMini_DoInit", 'DFPlayerMini_Connect');

  return $ret;
}

#####################################
sub
DFPlayerMini_CloseDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $hash, 2, "$name closed"; 
  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash);
  readingsSingleUpdate($hash, "state", "closed", 1);

  return undef;
}

#####################################
sub
DFPlayerMini_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my ($ver, $try) = ("", 0);
  #Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing
  Log3 $hash, 1, "$name/define: ".$hash->{DEF};

  delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});

  RemoveInternalTimer("HandleWriteQueue:$name");
  @{$hash->{QUEUE}} = ();
  if (($hash->{DEF} !~ m/\@DirectIO/) and ($hash->{DEF} !~ m/none/) )
  {
    Log3 $hash, 1, "$name/init: ".$hash->{DEF};
    $hash->{initretry} = 0;
    RemoveInternalTimer($hash);
    
    InternalTimer(gettimeofday() + DFP_INIT_WAIT, "DFPlayerMini_StartInit", $hash, 0);
  }
  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  @{$hash->{PLAYQUEUE}} = ();
  @{$hash->{TTSQUEUE}} = ();
  $hash->{waitForAck} = 0;

  return;
  #return undef;
}

sub DFPlayerMini_StartInit($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{storage} = undef;

  Log3 $name,3 , "$name/init: get storage, retry = " . $hash->{initretry};
  if ($hash->{initretry} >= DFP_INIT_MAXRETRY) {
    $hash->{DevState} = 'INACTIVE';
    # einmaliger reset, wenn danach immer noch 'init retry count reached', dann DFPlayerMini_CloseDevice()
    if (!defined($hash->{initResetFlag})) {
      Log3 $name,2 , "$name/init retry count reached. Reset";
      $hash->{initResetFlag} = 1;
      DFPlayerMini_ResetDevice($hash);
    } else {
      Log3 $name,2 , "$name/init retry count reached. Closed";
      DFPlayerMini_CloseDevice($hash);
    }
    return;
  }
  else {
    DFPlayerMini_SimpleWrite($hash, DFPlayerMini_createCmd($hash, DFP_C_GetStorage));
    $hash->{DevState} = 'waitInit';
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + DFP_CMD_TIMEOUT, "DFPlayerMini_CheckCmdResp", $hash, 0);
  }
}


####################
sub DFPlayerMini_CheckCmdResp($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $msg = undef;
  my $storage;

  $storage = ReadingsVal($name, "storage", "");
  if ($storage) {
    readingsSingleUpdate($hash, "state", "opened", 1);
    Log3 $name, 2, "$name: initialized";
    $hash->{DevState} = 'initialized';
    delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
    delete($hash->{initretry});
    # initialize keepalive
    $hash->{keepalive}{ok}    = 0;
    $hash->{keepalive}{retry} = 0;
    my $keepAliveInterval = AttrVal($name, "keepAliveInterval", DFP_KEEPALIVE_TIMEOUT);
    if ($keepAliveInterval > 0) {
      InternalTimer(gettimeofday() + $keepAliveInterval, "DFPlayerMini_KeepAlive", $hash, 0);
    }
  }
  else {
    $hash->{initretry} ++;
    DFPlayerMini_StartInit($hash);
  }
}



#####################################
## API to logical modules: Provide as Hash of IO Device, type of function ; command to call ; message to send
sub
DFPlayerMini_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  $fn="RAW" if $fn eq "";

  Log3 $name, 5, "$name/write: adding to queue $fn $msg";

  #DFPlayerMini_SimpleWrite($hash, $bstring);
  
  #DFPlayerMini_Set($hash,$name,$fn,$msg);
  #DFPlayerMini_AddSendQueue($hash,$bstring);
 
}


sub DFPlayerMini_AddSendQueue($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  #Log3 $hash, 3,"$name: AddSendQueue: " . $hash->{NAME} . ": $msg";
  
  if (!$hash->{waitForAck} && gettimeofday() - $hash->{LAST_SEND_TS}  > DFP_MIN_WAITTIME) {
    # minimal wait time before next command exceeded, can write immediately
    DFPlayerMini_SimpleWrite($hash, $msg);
  } else {
    # have to wait before sending the next command
    push(@{$hash->{QUEUE}}, $msg);
  
    #Log3 $hash , 5, Dumper($hash->{QUEUE});
    if ($hash->{waitForAck} == 0) {
      # if we don't have to wait for an acknowledge from dfp we have at least to wait 20ms
      InternalTimer(gettimeofday() + DFP_MIN_WAITTIME, "DFPlayerMini_HandleWriteQueue", "HandleWriteQueue:$name", 1);
    } else {
      Log3 $hash, 5, "delayed send, waiting for ack";
    }
  }
}


####################################
sub
DFPlayerMini_HandleWriteQueue($)
{
  my($param) = @_;
  my(undef,$name) = split(':', $param);
  my $hash = $defs{$name};
  
  #my @arr = @{$hash->{QUEUE}};
  
  if(@{$hash->{QUEUE}}) {
    my $msg = shift(@{$hash->{QUEUE}});

    if($msg eq "") {
      DFPlayerMini_HandleWriteQueue("x:$name");
    } else {

      DFPlayerMini_SimpleWrite($hash,$msg);
    }
  } else {
     Log3 $name, 4, "$name/HandleWriteQueue: nothing to send, stopping timer";
     RemoveInternalTimer("HandleWriteQueue:$name");
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
DFPlayerMini_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # einlesen der bereitstehenden Daten
  my $buf = DevIo_SimpleRead($hash);    
  return "" if ( !defined($buf) );
  
  # Zum debuggen in lesbarer Form
  $hash->{PARTIAL} = unpack ('H*', $buf);  

  #Log3 $name, 5, "$name: DFPlayerMini_Read ($name) - received data: " . $hash->{PARTIAL};    

  # Daten an den Puffer anhängen
  $hash->{helper}{BUFFER} .= $buf;
  #Log3 $name, 5, "$name: DFPlayerMini_Read ($name) - current buffer content: " . unpack('H*', $hash->{helper}{BUFFER});

  # prufen, ob im Buffer ein vollstä;ndiger Frame mit 10 Bytes zur Verarbeitung vorhanden ist.
  while (length($hash->{helper}{BUFFER}) >= DFP_FrameLength) 
  {
    if (unpack("C",substr($hash->{helper}{BUFFER},0,1)) == DFP_Start_Byte && unpack("C", substr($hash->{helper}{BUFFER},9,1)) == DFP_End_Byte) {
      # Checksumme pr&uuml;fen
      my $checksum = 0;
      for (my $i=1; $i<=6; $i++) {
        $checksum += unpack("C", substr($hash->{helper}{BUFFER},$i,1));
      }
      $checksum = (0xffff - ($checksum) + 1) & 0xffff;
      if ($checksum != unpack("n", substr($hash->{helper}{BUFFER},7,2))) {
        Log3 $name, 2, "$name: DFPlayerMini_Read - invalid checksum: calc $checksum, received " . unpack("n", substr($hash->{helper}{BUFFER},7,2));
      } else {
        DFPlayerMini_Parse($hash, substr($hash->{helper}{BUFFER},3,4));
      }
      # remove processed command from buffer
      $hash->{helper}{BUFFER} = substr($hash->{helper}{BUFFER},DFP_FrameLength);
    } else {
      Log3 $name, 2, "$name: DFPlayerMini_Read - no valid start/end byte";
      $hash->{helper}{BUFFER} = substr($hash->{helper}{BUFFER},1);
    }
  }
}



sub DFPlayerMini_KeepAlive($){
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if ($hash->{DevState} eq 'disconnected');

  Log3 $name,4 , "$name/KeepAliveOk: " . $hash->{keepalive}{ok};
  if (!$hash->{keepalive}{ok}) {
    if ($hash->{keepalive}{retry} >= DFP_KEEPALIVE_MAXRETRY) {
      Log3 $name,4 , "$name/keepalive retry count reached. Reset";
      $hash->{DevState} = 'INACTIVE';
      DFPlayerMini_ResetDevice($hash);
      return;
    }
    elsif (@{$hash->{QUEUE}} == 0) {
      $hash->{keepalive}{retry} ++;
      Log3 $name,4 , "$name/KeepAlive: send requestAck";
      DFPlayerMini_AddSendQueue($hash, DFPlayerMini_createCmd($hash, DFP_C_Acknowledge));
    }
  }
  Log3 $name,4 , "$name/keepalive retry = " . $hash->{keepalive}{retry};
  $hash->{keepalive}{ok} = 0;

  my $keepAliveInterval = AttrVal($name, "keepAliveInterval", DFP_KEEPALIVE_TIMEOUT);
  if ($keepAliveInterval > 0) {
    InternalTimer(gettimeofday() + $keepAliveInterval, "DFPlayerMini_KeepAlive", $hash, 1);
  }
}


### Helper Subs >>>



sub
DFPlayerMini_Parse($$)
{
  my ($hash, $rmsg) = @_;
  my $name = $hash->{NAME};
  my $error = "";
  my @storage;
  my $state = "";

  if (defined($hash->{keepalive})) {
    $hash->{keepalive}{ok}    = 1;
    $hash->{keepalive}{retry} = 0;
  }

  my $debug = AttrVal($hash->{NAME},"debug",0);


  #Debug "$name: incoming message: ($rmsg)\n" if ($debug);
  Log3 $name, 5, "$name: incoming message: (" .unpack("H*", $rmsg) . ")";

  my ($cmd, $ack, $par1, $par2) = unpack("CCCC", $rmsg);
  my $par16 = $par1 * 256 + $par2;
  if ($cmd == DFP_C_Error) {
      $error = $errorTexts{$par2};
      $error = "unknown Error" if !defined $error;
      # ToDo: Special case: DFP_C_GetNoTracksFolder will return DFP_E_TrackNotFound if the folder is empty
      readingsSingleUpdate($hash, "state", $error, 1);
  } elsif ($cmd == DFP_C_Acknowledge) {
    # send next command if one is in the queue
    $hash->{waitForAck} = 0;
    DFPlayerMini_HandleWriteQueue("x:$name");
  } elsif ($cmd == DFP_C_GetStorage) {
    if ($par2 & 0x01) {
      push @storage, "USB";
    }
    if ($par2 & 0x02) {
      push @storage, "SD";
    } 
    if ($par2 & 0x04) {
      push @storage, "PC";
    }
    readingsSingleUpdate($hash, "storage", join(",",@storage), 1);
  } elsif ($cmd == DFP_C_GetStatus) {
    $state = $statusStorageTexts{$par1} . ", " . $statusModeTexts{$par2};
    readingsSingleUpdate($hash, "state", $state, 1);
  } elsif ($cmd == DFP_C_GetNoTracksInFolder) {
    readingsSingleUpdate($hash, "tracksInFolder_".$par2, $par1, 1);
  } elsif ($cmd == DFP_C_GetNoTracksRootSD) {
    readingsSingleUpdate($hash, "tracksRootSD", $par16, 1);
  } elsif ($cmd == DFP_C_GetNoTracksRootUSB) {
    readingsSingleUpdate($hash, "tracksRootUSB", $par16, 1);
  } elsif ($cmd == DFP_C_GetNoFolders) {
    readingsSingleUpdate($hash, "noFolders", $par16, 1);
  } elsif ($cmd == DFP_C_GetVolume) {
    readingsSingleUpdate($hash, "volumeStraight", $par2, 1);
  } elsif ($cmd == DFP_C_GetEqualizerMode) {
    readingsSingleUpdate($hash, "equalizer", $equalizerTexts{$par2}, 1);
  } elsif ($cmd == DFP_C_SetPlaybackFolder3000 || $cmd == DFP_C_SetPlaybackFolder) {
    
  } elsif ($cmd == DFP_C_TrackFinishedSD || $cmd == DFP_C_TrackFinishedUSB) {
    # there is a bug in the DFP, it sends this response twice in succession!
    # and only after the second response it will accept the next play command.
    # Especially if connected via WLAN the time between the two responses can be quite high
    # -> only start the next play when the second response has been received
    if ($hash->{helper}{LAST_RESPONSE} eq $rmsg) { # || gettimeofday() - $hash->{LAST_RECV_TS} > 10*DFP_MIN_WAITTIME) {
      shift @{$hash->{PLAYQUEUE}};
      if (@{$hash->{PLAYQUEUE}} != 0) {
      
        # play the next track from queue
        DFPlayerMini_AddSendQueue($hash, ${$hash->{PLAYQUEUE}}[0]);
      }
      readingsSingleUpdate($hash, "state", "track $par16 finished", 1);
    }
  } elsif ($cmd == DFP_C_GetCurrentTrackSD || $cmd == DFP_C_GetCurrentTrackUSB) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "advertPossible", 1);
    readingsBulkUpdate($hash, "currentTrack" . ($cmd == DFP_C_GetCurrentTrackSD ? "SD" : "USB"), $par16);
    readingsBulkUpdate($hash, "state", "playing track $par16");
    readingsEndUpdate($hash, 1);
  } elsif ($cmd == DFP_C_StoragePluggedIn) {
    readingsSingleUpdate($hash, "state", "storage plugged in", 1);
  } elsif ($cmd == DFP_C_StoragePulledOut) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "advertPossible", 0);
    readingsBulkUpdate($hash, "state", "storage pulled out", 1);
    readingsEndUpdate($hash, 1);
    @{$hash->{PLAYQUEUE}} = ();
  } elsif ($cmd == DFP_C_RepeatCurrent) {
    readingsSingleUpdate($hash, "repeat", $par2 == 1 ? "current" : "off", 1);
  } elsif ($cmd == DFP_C_RepeatFolder) {
    readingsSingleUpdate($hash, "repeat", $par2 == 1 ? "folder" : "off", 1);
  } elsif ($cmd == DFP_C_RepeatAllRoot) {
    readingsSingleUpdate($hash, "repeat", $par2 == 1 ? "root" : "off", 1);
  } else {
    Log3 $hash, 1, "$name: Unknown response " . sprintf("%02x %02x %02x", $cmd, $par1, $par2);
  }
  $hash->{helper}{LAST_RESPONSE} = $rmsg;
  $hash->{LAST_RECV_TS} = gettimeofday();
}


#####################################
sub
DFPlayerMini_Ready($)
{
  my ($hash) = @_;

  if ($hash->{STATE} eq 'disconnected') {
    $hash->{DevState} = 'disconnected';
    return DevIo_OpenDev($hash, 1, "DFPlayerMini_DoInit", 'DFPlayerMini_Connect')
  }
  
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

########################
sub
DFPlayerMini_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  my $hexMsg = unpack ('H*', $msg);
  Log3 $name, 5, "$name SW: $hexMsg";
  

  my $sendCmd = AttrVal($name, "sendCmd", undef);
  if (defined $sendCmd) {
    $sendCmd =~ s/\$msg/${hexMsg}/;
    Log3 $name, 5, "$name: sendCmd: $sendCmd";
    my $errors = AnalyzeCommandChain($hash, $sendCmd);
    Log3 $name, 1, "$name: $errors" if $errors;
  } else {

    $hash->{USBDev}->write($msg)    if($hash->{USBDev});
    syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
    syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

    # Some linux installations are broken with 0.001, T01 returns no answer
    select(undef, undef, undef, 0.01);
  }

  # remember time the command was sent
  $hash->{LAST_SEND_TS} = gettimeofday();
  # evaluate requestAck byte in command 
  # if it is set an acknowledge must be received before 
  # sending the next command from the queue
  $hash->{waitForAck} = unpack('C', substr($msg,4,1));
  Log3 $name, 5, "current cmd waitForAck " . $hash->{waitForAck};
  
  
}

sub
DFPlayerMini_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $debug = AttrVal($name,"debug",0);

  if ($aName eq "TTSDev") 
  {
#     if ($init_done) {
#       my $devspec = "TYPE=Text2Speech:FILTER=NAME=$aVal";
#       my ($ttsDev) = devspec2array($devspec, $hash);
#       if (!$ttsDev || !$defs{$ttsDev}) {
#         return "$aVal does not exist or isn't of TYPE Text2Speech";
#       }    
      # we want to be notified when creating a tts file is finished
      $hash->{NOTIFYDEV} = "global,$aVal";
  }
 
  return undef;
}

sub DFPlayerMini_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events
  
  Log3 $ownName, 5, "Notify of $ownName called by event of $devName";

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  my $ttsDev = AttrVal($ownName, "TTSDev", "?");
  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));

    # Examples:
    # $event = "readingname: value" 
    # or
    # $event = "INITIALIZED" (for $devName equal "global")
    #
    # processing $event with further code
    if ($devName eq $ttsDev && defined $own_hash->{TTSQUEUE}) {
      if (@{$own_hash->{TTSQUEUE}}) {
        #event was triggered by receiving device
        if ($event eq "playing: 0") {

          my $ttsCmd = shift @{$own_hash->{TTSQUEUE}};
          my ($destFile, $ttsSay) = split(/ /, $ttsCmd, 2); 
          Log3 $ownName, 4, "$ownName: tts finished with ttsCmd = $ttsCmd, destFile = $destFile, ttsSay = $ttsSay"; 

          my $lastFilename = ReadingsVal($ttsDev, "lastFilename", "");
          if ($lastFilename) {
            if ($destFile eq "!") {
              # try to play using MD5
              my ($cachedir, $md5) = split(/\//, $lastFilename);
              $md5 =~ s/\.mp3$//;
              my $ret = DFPlayerMini_Play($own_hash, "MD5$md5");
              Log3 $ownName, 1, "$ownName: $ret" if $ret;
            } else {
              # upload file
              $destFile = catfile(AttrVal($ownName, "uploadPath", ""), $destFile) . ".mp3";
              Log3 $ownName, 5, "$ownName: copying $lastFilename to $destFile"; 
              if (copy($lastFilename, $destFile) == 0) {
                Log3 $ownName, 1, "$ownName: copying failed: $?";
              }
              if (@{$own_hash->{TTSQUEUE}} == 0) {
                Log3 $ownName, 4, "$ownName: tts, all playing done"; 
                $own_hash->{TTS_BUSY} = 0;
                DFPlayerMini_readFiles($own_hash);
              } else {
                $ttsCmd = @{$own_hash->{TTSQUEUE}}[0];
                ($destFile, $ttsSay) = split(/ /, $ttsCmd, 2); 
                Log3 $ownName, 4, "$ownName: starting next tts $destFile $ttsSay"; 
                fhem "set $ttsDev tts " . $ttsSay;
              }
            }
          } else {
            Log3 $ownName, 1, "$ownName: $ttsDev has no lastFilename Reading, 98_Text2Speech module too old?";
          }
        }
        delete $own_hash->{DESTFILE};
      }
    } elsif ($devName eq "global") {
      if ($event eq "DELETEATTR $ownName TTSDev") {
        delete $own_hash->{NOTIFYDEV};
      }
    } 

  }
  return undef;
}

1;

=pod
=item device
=item summary    supports the DFPLayer Mini FN-M16P Embedded MP3 Audio Module
=item summary_DE Unterst&uumltzt das DFPLayer Mini FN-M16P Embedded MP3 Audio Module
=begin html

<a name="DFPlayerMini"></a>
<h3>DFPlayerMini - FN-M16P Embedded MP3 Audio Module</h3>

  This module integrates the <a href="http://www.flyrontech.com/eproducts/84.html">DFPlayerMini - FN-M16P Embedded MP3 Audio Module device</a> into fhem.
  See the <a href="http://www.flyrontech.com/edownload/6.html">datasheet</a> of the module for technical details.
  <br>
  The MP3 player can be connected directly to a serial interface or via ethernet/WiFi by using a hardware with offers a transparent
  serial bridge over TCP/IP like <a href="http://www.letscontrolit.com/wiki/index.php/Ser2Net">ESPEasy Ser2Net</a>.
  <br><br>
  It is also possible to use other fhem transport devices like <a href="#MYSENSORS">MYSENSORS</a>.
  <br><br>
  The module supports all commands of the DFPlayer and offers additional convenience functions like 
  <ul>
  <li>integration of <a href="#Text2Speech">Text2Speech</a> for easy download of speech mp3 files</li>
  <li>easier control of which file to play by</li>
  <li>keeping a reference of all files the DFPlayer can play</li>
  <li>playing several files in succession (playlist)</li>
  <li>creating and playing files for speaking numbers</li> 
  </ul>
  <br>
  <a name="DFPlayerMinidefine"></a>
  <b>Define</b><br>
  <code>define &lt;name&gt; DFPlayerMini {none | devicename[\@baudrate] | devicename\@directio | hostname:port} </code>
  <br>
  <ul>
    <li>
    If directly connected &lt;devicename&gt; specifies the serial port to communicate with the DFPlayer Mini.
    The name of the serial-device depends on your distribution, under
    linux the cdc_acm kernel module is responsible, and usually a
    /dev/ttyACM0 or /dev/ttyUSB0 device will be created. 

    You can also specify a baudrate if the device name contains the @
    character, e.g.: /dev/ttyACM0@9600<br><br>This is also the default baudrate and normally shouldn't be changed
    as the DFPlayer uses a fixed baudrate of 9600.

    If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
    perl module Device::SerialPort is not needed, and fhem opens the device
    with simple file io. This might work if the operating system uses sane
    defaults for the serial parameters, e.g. some Linux distributions and
    OSX.  <br>
    </li>
    <li>
    If connected via TCP/IP &lt;hostname:port&gt; specifies the IP address and port of the device that provides the transparent serial
    bridge to the DFP, e.g. 192.168.2.28:23
    </li>
    <li>
    for other types of transport <code>none</code> can be specified as the device. In that case the attribute <code>sendCmd</code> should be specified and responses 
    from the DFP should be given to this module with <code>set response</code>.
    </li>
  </ul>
  <br>

  <a name="DFPlayerMiniattr"></a>
  <b>Attributes</b>    
  <ul>
  <li>TTSDev<br>
    The name of a Text2Speech device. This has to be defined beforehand with none as the &lt;alsadevice&gt; as a server device. It should be used for no other purposes
    than use by this module.
  </li>
  <li>requestAck<br>
    The DFPlayer can send a response to any command sent to it to acknowledge that is has received the command. As this increases the communication
    overhead it can be switched off if the communication integrity is ensured by other means. If set the next command is only sent if the last one was
    acknowledged by the DFPlayer. This ensures that no command is lost if the the DFPlayer is busy/sleeping.
  </li>
  <li>sendCmd<br>
    A fhem command that is used to send the command data generated by this module to the DFPlayer hardware. If this is set, no other way of communication with the DFP is used. 
    This can be used integrate other transport devices than those supported natively.<br>
    E. g. to communicate via a MySensors device named mys_dfp with an appropriate sketch use <br>
    <code>
    attr &lt;dfp&gt; sendCmd set mys_dfp value11 $msg
    </code><br>
    The module will then send a command to the DFP replacing $msg with the actual payload using the fhem command
    <code>
    set mys_dfp value11 &lt;payload&gt;
    </code>
    <br>
    See <code>set response</code> for a way to get the response of the DFPlayer received via a different device back into this module.
  </li>
  <li>uploadPath<br>
    The DFPlayer plays files from an SD card or USB stick connected to it. The mp3/wav files have to be copied to this storage device by the user.
    The device expects the files with specific names and in specific folders, see the datasheet for details. 
    Copying the files can also be done by this module if the storage device is accessible by the computer fhem is running on.
    It has to be mounted in a specific path with is specified with this attribute.
    <br>
    See uploadTTS, uploadTTScache and readFiles commands where this is used. 
  </li>
  <li>rememberMissingTTS<br>
    If set <code>tts</code> commands without a matching file create a special reading. See <code>set tts</code> and <code>set uploadTTScache</code>.
  </li>
  <li>keepAliveInterval<br>
    Specifies the interval in seconds for sending a keep alive message to the DFP. Can be used to check if the DFP is still working and to keep connections open.<br>
    After three missing answers the status of the devices is set to disconnected.<br>
    Set the interval to 0 to disable the keep alive feature. Default is 60 seconds.
  </li>
  </ul>
  <a name="DFPlayerMiniget"></a>
  <br>
  <b>Get</b>
  <br><br>
  All query commands supported by the DFP have a corresponding get command:
  <table>
  <tr><th>get</th><th>DFP cmd byte</th><th>parameters</th><th>comment</th></tr>
  <tr><td>storage</td><td>0x3F</td><td></td><td></td></tr>
  <tr><td>status</td><td>0x42</td><td></td><td></td></tr>
  <tr><td>volume</td><td>0x43</td><td></td><td></td></tr>
  <tr><td>equalizer</td><td>0x44</td><td></td><td></td></tr>
  <tr><td>noTracksRootUsb</td><td>0x47</td><td></td><td></td></tr>
  <tr><td>noTracksRootSd</td><td>0x48</td><td></td><td></td></tr>
  <tr><td>currentTrackUsb</td><td>0x4B</td><td></td><td></td></tr>
  <tr><td>currentTrackSd</td><td>0x4C</td><td></td><td></td></tr>
  <tr><td>noTracksInFolder</td><td>0x4E</td><td>folder number</td><td>1-99</td></tr>
  <tr><td>noFolders</td><td>0x4F</td><td></td><td></td></tr>
  </table>
  <a name="DFPlayer Miniset"></a>
  <br>
  <b>Set</b>
  <br><br>
  All commands supported by the DFP have a corresponding set command:
  <br>
  <table>
  <tr><th>set</th><th>DFP cmd byte</th><th>parameters</th><th>comment</th></tr>
  <tr><td>next</td><td>0x01</td><td>-</td><td></td></tr>
  <tr><td>prev</td><td>0x02</td><td>-</td><td></td></tr>
  <tr><td>trackNum</td><td>0x03</td><td>number of track in root directory</td><td>between 1 and 3000 (uses the order in which the files where created!)</td></tr>
  <tr><td>volumeUp</td><td>0x04</td><td>-</td><td></td></tr>
  <tr><td>volumeDown</td><td>0x05</td><td>-</td><td></td></tr>
  <tr><td>volumeStraight</td><td>0x06</td><td>volume</td><td>0-30</td></tr>
  <tr><td>equalizer</td><td>0x07</td><td>name of the equalizer mode</td><td>Normal, Pop, Rock, Jazz, Classic, Bass</td></tr>
  <tr><td>repeatSingle</td><td>0x08</td><td>-</td><td></td></tr>
  <tr><td>storage</td><td>0x09</td><td>SD or USB</td><td></td></tr>
  <tr><td>sleep</td><td>0x0A</td><td>-</td><td>not supported by DFP, DFP needs power cycle to work again</td></tr>
  <tr><td>wake</td><td>0x0B</td><td>-</td><td>not supported by DFP, but probably by FN-M22P</td></tr>
  <tr><td>reset</td><td>0x0C</td><td>-</td><td></td></tr>
  <tr><td>play</td><td>0x0D</td><td>-</td><td>plays the current track</td></tr>
  <tr><td>play</td><td>0x0F, 0x12, 0x13, 0x14</td><td>a space separated list of files to play successively</td><td>the correct DFP command is used automatically. 
                                                                                                                   Files can be specified with either their reading name, reading value or folder name/track number.
                                                                                                                   See set readFiles</td></tr>
  <tr><td>pause</td><td>0x0E</td><td>-</td><td></td></tr>
  <tr><td>amplification</td><td>0x10</td><td>level of amplification</td><td>0-31</td></tr>
  <tr><td>repeatRoot</td><td>0x11</td><td>on, off</td><td></td></tr>
  <tr><td>MP3TrackNum</td><td>0x12</td><td>tracknumber</td><td>1-3000, from folder MP3</td></tr>
  <tr><td>intercutAdvert</td><td>0x13</td><td>tracknumber</td><td>1-3000, from folder ADVERT</td></tr>
  <tr><td>folderTrackNum</td><td>0x0F</td><td>foldernumber tracknumber</td><td>folder: 1-99, track: 1-255</td></tr>
  <tr><td>folderTrackNum3000</td><td>0x14</td><td>foldernumber tracknumber</td><td>folder: 1-15, track: 1-3000</td></tr>
  <tr><td>stopAdvert</td><td>0x15</td><td>-</td><td></td></tr>
  <tr><td>stop</td><td>0x16</td><td>-</td><td></td></tr>
  <tr><td>repeatFolder</td><td>0x17</td><td>number of folder</td><td>1-99</td></tr>
  <tr><td>shuffle</td><td>0x18</td><td>-</td><td></td></tr>
  <tr><td>repeatCurrentTrack</td><td>0x19</td><td>on, off</td><td></td></tr>
  <tr><td>DAC</td><td>0x1A</td><td>on, off</td><td></td></tr>
  </table>
  <br>
  All other set commands are not sent to the DFP but offer convenience functions:
  <br>
  <ul>
  <li>
  close
  </li>
  <li>
  raw <br>sends a command encoded in hex directly to the DFP without any validation
  </li>
  <li>
  reopen
  </li>
  <li>
  readFiles <br> reads all files from the storage medium mounted at <code>uploadPath</code>. If these files are accessible by the DFP (i.e. they conform to the naming convention)
  a reading is created for the file. The reading name is File_&lt;folder&gt;/&lt;tracknumber&gt;. Folder can be ., MP3, ADVERT, 00 to 99.
  The reading value is the filename without the tracknumber and suffix.<br>
  Example:<br>
  For the file MP3/0003SongTitle.mp3 the reading File_MP3/0003 with value SongTitle is created.
  <br>
  The <code>set &lt;dfp&gt; play</code> command can make use of these readings, i.e. it is possible to use either <code>set &lt;dfp&gt; play File_MP3/0003</code>, 
  <code>set &lt;dfp&gt; play MP3/3</code> or <code>set &lt;dfp&gt; play SongTitle</code> to play the same track.
  </li>
  <li>
  uploadTTS &lt;destination path&gt; &lt;Text to translate to speech&gt;<br>
  The text specified is converted to a speech mp3 file using the Text2Speech device specified with attr <code>TTSDev</code>. The mp3 file is then copied into the given 
  destination path within uploadPath.
  <br>
  Examples:<br>
  <code>set &lt;dfp&gt; 01/0001Test Dies ist ein Test</code><br>
  <code>set &lt;dfp&gt; ADVERT/0099Hinweis Achtung</code>
  </li>
  <li>
  uploadTTScache<br>
  upload all files from the cache directory of the <code>TTSDev</code> to <code>uploadPath</code>. Uploading starts with folder 01. After 3000 files
  the next folder is used. The MD5 hash is used as the filename. When the upload is finished <code>set readFiles</code> is executed. The command <code>set tts</code> makes use of the readings created by this.
  </li>
  <li>
  tts &lt;text to translate to speech&gt;<br>
  <code>TTSDev</code> is used to calculate the MD5 hash of &lt;text to translate to speech&gt;. It then tries to play the file with this hash value.
  If no reading for such a file exists and if the attribute <code>rememberMissingTTS</code> is set, a new reading Missing_MD5&lt;md5&gt; with &lt;text to translate to speech&gt; as its
  value is created.
  <br>Prerequisites:<br>
  This only works if this text had been translated earlier and the resulting mp3 file was stored in the cache directory of TTSDev. 
  The files in the cache have to be uploaded to the storage card with <code>set uploadTTScache</code>.    
  </li>
  <li>
  uploadNumbers destinationFolder<br>
  creates mp3 files for all tokens required to speak arbitrary german numbers. <br>
  Example:<br>
  <code>set &lt;dfp&gt; uploadNumbers 99</code>
  <br>
  creates the 31 mp3 files required in folder 99.
  </li>
  <li>
  sayNumber number<br>
  translates a number into speech and plays the required tracks. Requires that uploadNumbers command was used to create the speech files. 
  <br>
  Example:
  <br>
  <code>sayNumber -34.7</code>
  <br>
  is equivalent to 
  <br>
  <code>play minus vier und dreissig komma sieben</code>
  </li>
  <li>
  response<br> 10 bytes response message from DFP encoded as hex
  </li>
  </ul>

=end html
=begin html_DE

<a name="DFPlayerMini"></a>
<h3>DFPlayerMini - FN-M16P Embedded MP3 Audio Module</h3>
  Dieses Modul integriert den <a href="http://www.flyrontech.com/eproducts/84.html">DFPlayerMini - FN-M16P Embedded MP3 Audio Modul</a> in fhem.
  Siehe auch das <a href="http://www.flyrontech.com/edownload/6.html">Datenblatt</a> des Moduls f&uuml;r technische Details.
  <br>
  Der MP3-Spieler kann direkt mit einer seriellen Schnittstelle verbunden werden oder per Ethernet/WiFi mittels einer Hardware die eine transparente
  serielle &Uuml;bertragung per TCP/IP zur Verf&uuml;gung stellt, z. B. <a href="http://www.letscontrolit.com/wiki/index.php/Ser2Net">ESPEasy Ser2Net</a>.
  <br><br>
  Es ist auch m&ouml;glich ein anderes fhem Device f&uuml;r den Datentransport zu nutzen, z. B. <a href="#MYSENSORS">MYSENSORS</a>.
  <br><br>
  Das Modul unterst&uuml;tzt alle Kommandos des DFPlayers und bietet weitere Funktionen wie
  <ul>
  <li>Integration von <a href="#Text2Speech">Text2Speech</a> um einfach Sprach-MP3-Dateien herunterzuladen</li>
  <li>einfachere Kontrolle dar&uuml;ber welche Dateien abgespielt werden sollen</li>
  <li>Verwaltung aller Dateien die der DFPlayer abspielen kann</li>
  <li>Abspielen mehrerer Dateien hintereinander (playlist)</li>
  <li>Erzeugung und Abspielen von Sprachschnipseln um beliebige Zahlen per Sprache auszugeben</li> 
  </ul>
  <br>
  <a name="DFPlayerMinidefine"></a>
  <b>Define</b><br>
  <code>define &lt;name&gt; DFPlayerMini {none | devicename[\@baudrate] | devicename\@directio | hostname:port} </code>
  <br>
  <ul>
    <li>
    Wenn der Player direkt angeschlossen ist wird per &lt;devicename&gt; der Name der seriellen Schnittstelle angegeben
    an die der DFPlayer Mini angeschlossen ist.
    Der Name der seriellen Schnittstelle h&auml;ngt von der Betriebssystemdistribution ab, unter Linux ist 
    das cdc_acm kernel Modul verantwortlich, und normalerweise wird ein
    /dev/ttyACM0 oder /dev/ttyUSB0 Device angelegt. 

    Man kann auch eine Baudrate angeben in dem dem im Devicenamen nach dem @ Zeichen die Baudrate angegeben wird, z. B.
    /dev/ttyACM0@9600<br><br>Das ist auch die standard Baudrate und sollte normalerweise nicht ge&auml;ndert werden da diese Baudrate beim
    DFPlayer fest eingestellt ist.

    Wenn als Baudrate "directio" angegeben wird (z. B.: /dev/ttyACM0@directio) dann wird das
    perl Modul Device::SerialPort nicht ben&ouml;tigt und fhem &ouml;ffnet das Device
    mit simple file io. Das kann funktionieren wenn das Betriebssystem sinnvolle  Voreinstellungen f&uuml;r die Parameter der
    seriellen Schnittstelle verwendet, z. B. einige Linux Distributionen und OSX.<br>
    </li>
    <li>
    Wenn die Verbindung &uuml;ber TCP/IP statt findet spezifiziert &lt;hostname:port&gt; die IP Adresse und den Port des Device das 
    die transparente serielle Verbindung zum DFP bereit stellt, e.g. 192.168.2.28:23
    </li>
    <li>
    F&uuml;r andere Arten des Datentransports kann <code>none</code> als Device angegeben werden.
    In diesem Fall sollte das Attribute <code>sendCmd</code> angegeben werden. Antworten vom DFPlayer sollten per <code>set response</code>
    zur&uuml;ck an dieses Module &uuml;bergeben werden.
    </li>
  </ul>
  <br>

  <a name="DFPlayerMiniattr"></a>
  <b>Attribute</b>    
  <ul>
  <li>TTSDev<br>
    Der Name eines Text2Speech Devices. Dieses muss bereits vorher mit none als &lt;alsadevice&gt; als Server Device angelegt worden sein. Es sollte ausschlie&szlig;lich
    f&uuml;r dieses Modul zur Verf&uuml;gung stehen und nicht f&uuml;r andere Zwecke verwendet werden.
  </li>
  <li>requestAck<br>
    Der DFPlayer kann f&uuml; jedes Kommando eine Best&auml;tigung senden. Da das zu erh&ouml;hter Kommunikation f&uuml;hrt kann es &uuml;ber dieses
    Attribut abgeschaltet werden. Wenn es eingeschaltet ist wird das n&auml;chste Kommando erst dann zum DFPlayer wenn das vorherige best&auml;tigt wurde.
    Das stellt sicher, dass kein Kommando verloren geht selbst wenn der DFPlayer ausgelastet oder im Schlafzustand ist. 
  </li>
  <li>sendCmd<br>
    Ein fhem Kommando das verwendet wird um ein durch diese Modul erzeugtes DFPlayer Kommando an die DFPlayer Hardware zu senden.
    Wenn dieses Attribut gesetzt ist wird kein andere Art der Kommunikation mit dem DFPlayer verwendet.
    Es kann verwendet werden um andere fhem Devices f&uuml;r den Datentransport zu nutzen.<br>
    Um z. B. mittels eines MySensor Devices mit dem Namen mys_dfp zu kommunizieren kann <br>
    <code>
    attr &lt;dfp&gt; sendCmd set mys_dfp value11 $msg
    </code><br>
    verwendet werden. Auf dem MySensors Devices muss eine passende Firmware installiert sein.<br>
    Dieses Modul wird dann ein Kommando an den DFP senden in dem $msg mit dem tats&auml;chlichen Kommando &lt;payload&gt; ersetzt wird und dann das fhem Kommando
    <code>
    set mys_dfp value11 &lt;payload&gt;
    </code>
    <br>
    ausgef&uuml;hrt wird.
    Siehe <code>set response</code> f&uuml;r einen Weg um die Antwort des DFPlayers zur&uuml;ck an dieses Modul zu senden.
  </li>
  <li>uploadPath<br>
    Der DFPlayer spielt Dateien von einer an ihn angeschlossenen SD-Karte oder USB-Stick ab. Die mp3/wav Dateien m&uuml;ssen vom Anwender auf dieses Speichermedium
    kopiert werden.
    Der Player erwartet die Dateien mit speziellen Namen und in spezifischen Verzeichnissen, im Datenblatt stehen die Einzelheiten.
    Das Kopieren der Dateien kann auch von diesem Modul durchgef&uuml;hrt werden. Dazu muss das Speichermedium mit dem Rechner verbunden sein auf dem
    fhem ausgef&uuml;hrt wird. Es muss dazu in dem Pfad gemounted sein der durch diese Attribut angegeben ist.
    <br>
    Siehe auch uploadTTS, uploadTTScache und readFiles Kommandos wo es verwendet wird. 
  </li>
  <li>rememberMissingTTS<br>
    Wenn gesetzt erzeugen <code>tts</code> Kommandos ohne eine passende Datei ein spezielles Reading. Siehe <code>set tts</code> und <code>set uploadTTScache</code>.
  </li>
  <li>keepAliveInterval<br>
    Gibt das Intervall in Sekunden zwischen KeepAlive Kommandos an den DFP an. Das kann verwendet werden um automatisch zu pr&uuml;fen, ob der DFP noch 
    funktioniert und erreichbar ist.<br>
    Nach drei fehlenden Antwortden wird der Status auf disconnected gesetzt.<br>
    Interval 0 schaltet die Funktion ab, die Voreinstellung ist 60 Sekunden.
  </li>
  </ul>
  <a name="DFPlayerMiniget"></a>
  <br>
  <b>Get</b>
  <br><br>
  Alle Abfrage Kommandos die vom DFP unterst&uuml;tzt werden haben ein zugeh&ouml;riges get Kommando:
  <table>
  <tr><th>get</th><th>DFP cmd byte</th><th>Parameter</th><th>Kommentar</th></tr>
  <tr><td>storage</td><td>0x3F</td><td></td><td></td></tr>
  <tr><td>status</td><td>0x42</td><td></td><td></td></tr>
  <tr><td>volume</td><td>0x43</td><td></td><td></td></tr>
  <tr><td>equalizer</td><td>0x44</td><td></td><td></td></tr>
  <tr><td>noTracksRootUsb</td><td>0x47</td><td></td><td></td></tr>
  <tr><td>noTracksRootSd</td><td>0x48</td><td></td><td></td></tr>
  <tr><td>currentTrackUsb</td><td>0x4B</td><td></td><td></td></tr>
  <tr><td>currentTrackSd</td><td>0x4C</td><td></td><td></td></tr>
  <tr><td>noTracksInFolder</td><td>0x4E</td><td>Verzeichnisnummer</td><td>1-99</td></tr>
  <tr><td>noFolders</td><td>0x4F</td><td></td><td></td></tr>
  </table>
  <a name="DFPlayer Miniset"></a>
  <br>
  <b>Set</b>
  <br><br>
  Alle Kommandos die vom DFP angeboten werden haben ein zugeh&ouml;riges set Kommando:
  <br>
  <table>
  <tr><th>set</th><th>DFP cmd byte</th><th>Parameter</th><th>Kommentar</th></tr>
  <tr><td>next</td><td>0x01</td><td>-</td><td></td></tr>
  <tr><td>prev</td><td>0x02</td><td>-</td><td></td></tr>
  <tr><td>trackNum</td><td>0x03</td><td>Nummer der Datei im Wurzelverzeichnis</td><td>zwischen 1 und 3000 (es wird die Reihenfolge verwendet in der die Dateien angelegt wurden!)</td></tr>
  <tr><td>volumeUp</td><td>0x04</td><td>-</td><td></td></tr>
  <tr><td>volumeDown</td><td>0x05</td><td>-</td><td></td></tr>
  <tr><td>volumeStraight</td><td>0x06</td><td>Lautst&auml;rke</td><td>0-30</td></tr>
  <tr><td>equalizer</td><td>0x07</td><td>Name des Equalizermodus</td><td>Normal, Pop, Rock, Jazz, Classic, Bass</td></tr>
  <tr><td>repeatSingle</td><td>0x08</td><td>-</td><td></td></tr>
  <tr><td>storage</td><td>0x09</td><td>SD oder USB</td><td></td></tr>
  <tr><td>sleep</td><td>0x0A</td><td>-</td><td>vom DFP nicht unterst&uuml;tzt, danach muss er stromlos gemacht werden um wieder zu funktionieren</td></tr>
  <tr><td>wake</td><td>0x0B</td><td>-</td><td>vom DFP nicht unterst&uuml;tzt, aber wahrscheinlich vom FN-M22P</td></tr>
  <tr><td>reset</td><td>0x0C</td><td>-</td><td></td></tr>
  <tr><td>play</td><td>0x0D</td><td>-</td><td>spielt die aktuelle Datei</td></tr>
  <tr><td>play</td><td>0x0F, 0x12, 0x13, 0x14</td><td>Eine durch Leerzeichen getrennte Liste von Dateien die nacheinander abgespielt werden</td><td>Das korrekte DFP Kommando wird automatisch ermittelt. 
                                                                                                                   Dateien k&ouml;nnen &uuml;ber den Namen ihres Readings, den Readingwert oder Verzeichnisname/Dateinummer angegeben werden. Siehe set readFiles</td></tr>
  <tr><td>pause</td><td>0x0E</td><td>-</td><td></td></tr>
  <tr><td>amplification</td><td>0x10</td><td>Verst&auml;rkungsstufe</td><td>0-31</td></tr>
  <tr><td>repeatRoot</td><td>0x11</td><td>on, off</td><td></td></tr>
  <tr><td>MP3TrackNum</td><td>0x12</td><td>Dateinummer</td><td>1-3000, aus dem Verzeichnis MP3</td></tr>
  <tr><td>intercutAdvert</td><td>0x13</td><td>Dateinummer</td><td>1-3000, aus dem Verzeichnis ADVERT</td></tr>
  <tr><td>folderTrackNum</td><td>0x0F</td><td>Verzeichnisnummer Dateinummer</td><td>Verzeichnis: 1-99, Datei: 1-255</td></tr>
  <tr><td>folderTrackNum3000</td><td>0x14</td><td>Verzeichnisnummer Dateinummer</td><td>Verzeichnis: 1-15, Datei: 1-3000</td></tr>
  <tr><td>stopAdvert</td><td>0x15</td><td>-</td><td></td></tr>
  <tr><td>stop</td><td>0x16</td><td>-</td><td></td></tr>
  <tr><td>repeatFolder</td><td>0x17</td><td>Verzeichnisnummer</td><td>1-99</td></tr>
  <tr><td>shuffle</td><td>0x18</td><td>-</td><td></td></tr>
  <tr><td>repeatCurrentTrack</td><td>0x19</td><td>on, off</td><td></td></tr>
  <tr><td>DAC</td><td>0x1A</td><td>on, off</td><td></td></tr>
  </table>
  <br>
  Alle anderen set Kommandos werden nicht an den DFPlayer geschickt sondern bieten Komfortfunktionen:
  <br>
  <ul>
  <li>
  close
  </li>
  <li>
  raw <br>sendet ein in Hexadezimal kodiertes Kommando direkt und ohne Pr&uuml;fung an den DFP
  </li>
  <li>
  reopen
  </li>
  <li>
  readFiles <br> 
  lie&szlig;t alle Dateien auf dem Speichermedium das in <code>uploadPath</code> gemounted ist. Wenn diese Dateien durch den DFP addressiert werden
  k&ouml;nnen (d.h. sie entprechen den Namenskonventionen) so wird ein Reading daf&uuml;r angelegt.
  Der Readingname ist File_&lt;Verzeichnis&gt;/&lt;Dateinummer&gt;.
  Das Verzeichnis kann ., MP3, ADVERT oder 00 bis 99 sein.
  Der Readingwert ist der Dateiname ohne die Dateinummer und das Suffix.<br>
  Beispiel:<br>
  F&uuml;r die Datei MP3/0003SongTitle.mp3 wird das Reading File_MP3/0003 mit dem Wert SongTitle angelegt.
  <br>
  Das <code>set &lt;dfp&gt; play</code> Kommando kann diese Readings verwenden, d.h. es ist m&ouml;glich entweder <code>set &lt;dfp&gt; play File_MP3/0003</code>, 
  <code>set &lt;dfp&gt; play MP3/3</code> oder <code>set &lt;dfp&gt; play SongTitle</code> zu verwenden, um die selbe Datei abzuspielen.
  </li>
  <li>
  uploadTTS &lt;destination path&gt; &lt;Text der in Sprache umgewandelt werden soll&gt;<br>
  Der angegebene Text wird in eine MP3 Sprachdatei umgewandelt. Daf&uuml;r wird das Text2Speech Device verwendet das mit attr <code>TTSDev</code> angegebene wurde.
  Die MP3 Datei wird dann in das angegebene Zielverzeichnis unterhalb von uploadPath kopiert. 
  <br>
  Beispiele:<br>
  <code>set &lt;dfp&gt; 01/0001Test Dies ist ein Test</code><br>
  <code>set &lt;dfp&gt; ADVERT/0099Hinweis Achtung</code>
  </li>
  <li>
  uploadTTScache<br>
  Kopiert alle Dateien aus dem cache Verzeichnis des <code>TTSDev</code> in <code>uploadPath</code>. Es wird zuerst in das Verzeichnis 01 kopiert. 
  Nach 3000 Dateien wird das n&auml;chste Verzeichnis verwendet. Der MD5 Hash wird als Dateiname verwendet. Zum Schluss wird <code>set readFiles</code> ausgef&uuml;hrt.
  Das Kommando <code>set tts</code> verwendet die dadurch angelegten Readings.
  </li>
  <li>
  tts &lt;Text der in Sprache &uuml;bersetzt werden soll&gt;<br>
  <code>TTSDev</code> wird verwendet um den MD5 Hash von &lt;Text der in Sprache &uuml;bersetzt werden soll&gt; zu berechnen. Anschlie&szlig;end wird versucht die Datei mit diesem Hash abzuspielen.
  Wenn kein Reading f&uuml;r diesen Hash existiert und das wenn das Attribute <code>rememberMissingTTS</code> gesetzt ist dann wird ein neues Reading Missing_MD5&lt;md5&gt; 
  mit dem Wert &lt;Text der in Sprache &uuml;bersetzt werden soll&gt; angelegt.
  <br>Voraussetzungen:<br>
  Das funktioniert nur, wenn vorher der zu &uuml;bersetzende Text bereits einmal &uuml;bersetzt wurde und die daraus resultierende MP3 Datei im cache Verzeichnis
  des TTSDev gespeichert wurde,
  Die Dateien aus dem Cache m&uuml;ssen auf das Speichermedium mittels <code>set uploadTTScache</code> kopiert werden
  </li>
  <li>
  uploadNumbers Zielverzeichnis<br>
  erzeugt MP3 Dateien f&uuml;r alle Sprachschnipsel die ben&ouml;tigt werden um beliebige deutsche Zahlen zu sprechen.<br>
  Beispiel:<br>
  <code>set &lt;dfp&gt; uploadNumbers 99</code>
  <br>
  erzeugt die ben&ouml;tigten 31 MP3 Dateien im Verzeichnis 99. 
  </li>
  <li>
  sayNumber Zahl<br>
  &uuml;bersetzt eine Zahl in Sprache und spielt die ben&ouml;tigten Dateien ab. Setzt voraus, dass vorher uploadNumbers verwendet wurde um die Sprachdateien zu erzeugen.
  <br>
  Beispiel:
  <br>
  <code>sayNumber -34.7</code>
  <br>
  entspricht
  <br>
  <code>play minus vier und dreissig komma sieben</code>
  </li>
  <li>
  response<br> 10 Byte Antwortnachricht vom DFP hexadezimal kodiert
  </li>
  </ul>

=end html_DE
=cut
