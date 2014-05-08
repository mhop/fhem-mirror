
##############################################
# $Id$
#
# 98_Text2Speech.pm
#
# written by Tobias Faust 2013-10-23
# e-mail: tobias dot faust at online dot de
#
##############################################

##############################################
# EDITOR=nano
# visudo
# ALL     ALL = NOPASSWD: /usr/bin/mplayer
##############################################

package main;
use strict;
use warnings;
use Blocking;
use IO::File;
use HttpUtils;
use Digest::MD5 qw(md5_hex);
use URI::Escape;
use Data::Dumper;

sub Text2Speech_OpenDev($);
sub Text2Speech_CloseDev($);


# SetParamName -> Anzahl Paramter
my %sets = (
  "tts"    => "1",
  "volume" => "1"
);

# path to mplayer
my $mplayer 			= 'sudo /usr/bin/mplayer';
#my $mplayerOpts 		= '-nolirc -noconsolecontrols -http-header-fields "User-Agent:Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.22 (KHTML, like Gecko) Chrome/25.0.1364.172 Safari/537.22m"';
my $mplayerOpts     = '-nolirc -noconsolecontrols';
my $mplayerNoDebug  = '-really-quiet';
my $mplayerAudioOpts 	= '-ao alsa:device=';
#my $ttsAddr 			= 'http://translate.google.com/translate_tts?tl=de&q=';
my $ttsHost         = 'translate.google.com';
my $ttsPath         = '/translate_tts?tl=de&q=';

##########################
sub Text2Speech_Initialize($)
{
  my ($hash) = @_;
  $hash->{WriteFn}   = "Text2Speech_Write";
  $hash->{ReadyFn}   = "Text2Speech_Ready"; 
  $hash->{DefFn}     = "Text2Speech_Define";
  $hash->{SetFn}     = "Text2Speech_Set";
  $hash->{UndefFn}   = "Text2Speech_Undefine";
  $hash->{AttrFn}    = "Text2Speech_Attr";
  $hash->{AttrList}  = "disable:0,1".
                       " TTS_Delemiter".
                       " TTS_Ressource:Google,ESpeak".
                       " TTS_CacheFileDir".
                       " TTS_UseMP3Wrap:0,1".
                       " TTS_MplayerCall".
                       " TTS_SentenceAppendix".
                       " TTS_FileMapping".
                       " TTS_FileTemplateDir".
		       " TTS_VolumeAdjust".
                       " ".$readingFnAttributes;
}


##########################
# Define <tts> Text2Speech <alsa-device>
# Define <tts> Text2Speech host[:port][:SSL] [portpassword]
##########################
sub Text2Speech_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  #$a[0]: Name
  #$a[1]: Type/Alias -> Text2Speech
  #$a[2]: definition
  #$a[3]: optional: portpasswd
  if(int(@a) < 3) {
    my $msg =  "wrong syntax: define <name> Text2Speech <alsa-device>\n".
    			     "see at /etc/asound.conf\n".
               "or remote syntax: define <name> Text2Speech host[:port][:SSL] [portpassword]";
    Log3 $hash, 2, $msg;
    return $msg;
  }

  my $dev = $a[2];
  if($dev =~ m/^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}).*/ ) {
    # Ein RemoteDevice ist angegeben
    # zb: 192.168.10.24:7272:SSL mypasswd

    if($dev =~ m/^(.*):SSL$/) {
      $dev = $1;
      $hash->{SSL} = 1;
    }
    if($dev !~ m/^.+:[0-9]+$/) { # host:port
      $dev = "$dev:7072";
    }
    $hash->{Host} = $dev;
    $hash->{portpassword} = $a[3] if(@a == 4); 

    $hash->{MODE} = "REMOTE";
  } else {
    # Ein Alsadevice ist angegeben
    # pruefen, ob Alsa-Device in /etc/asound.conf definiert ist
    $hash->{MODE} = "DIRECT";
    $hash->{ALSADEVICE} = $a[2];
  }

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  delete($hash->{helper}{RUNNING_PID});

  $hash->{STATE} = "Initialized";

  return undef;
}

#####################################
sub Text2Speech_Undefine($$)
{
 my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);
 BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
 Text2Speech_CloseDev($hash);

 return undef;
}

###################################
# Angabe des Delemiters: zb.: +af~ 
#   + -> erzwinge das Trennen, auch wenn Textbaustein < 100Zeichen
#   - -> Trenne nur wenn Textbaustein > 100Zeichen
#  af -> add first -> füge den Delemiter am Satzanfang wieder hinzu
#  al -> add last  -> füge den Delemiter am Satzende wieder hinzu
#  an -> add nothing -> Delemiter nicht wieder hinzufügen
#   ~ -> der Delemiter
###################################
sub Text2Speech_Attr(@) {
  my @a = @_;
  my $do = 0;
  my $hash = $defs{$a[1]};
  my $value = $a[3];

  my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");
  my $TTS_CacheFileDir = AttrVal($hash->{NAME}, "TTS_CacheFileDir", "cache");
  my $TTS_FileMapping  = AttrVal($hash->{NAME}, "TTS_FileMapping", ""); # zb, silence:silence.mp3 ring:myringtone.mp3;

  if($a[2] eq "TTS_Delemiter" && $a[0] ne "del") {
    return "wrong delemiter syntax: [+-]a[lfn]. \n".
           "  Example 1: +an~\n".
           "  Example 2: +al." if($value !~ m/^([+-]a[lfn]){0,1}(.){1}$/i);
    return "This Attribute is only available in direct mode" if($hash->{MODE} ne "DIRECT");

  } elsif ($a[2] eq "TTS_Ressource") {
    return "This Attribute is only available in direct mode" if($hash->{MODE} ne "DIRECT");
  
  } elsif ($a[2] eq "TTS_CacheFileDir") {
    return "This Attribute is only available in direct mode" if($hash->{MODE} ne "DIRECT");
 
  } elsif ($a[2] eq "TTS_UseMP3Wrap") {
    return "This Attribute is only available in direct mode" if($hash->{MODE} ne "DIRECT");
    return "Attribute TTS_UseMP3Wrap is required by Attribute TTS_SentenceAppendix! Please delete it first." 
      if(AttrVal($hash->{NAME}, "TTS_SentenceAppendix", undef));

  } elsif ($a[2] eq "TTS_SentenceAppendix") { 
    return "This Attribute is only available in direct mode" if($hash->{MODE} ne "DIRECT");
    return "Attribute TTS_UseMP3Wrap is required!" unless(AttrVal($hash->{NAME}, "TTS_UseMP3Wrap", undef));
    
    my $file = $TTS_CacheFileDir ."/". $value;
    return "File <".$file."> does not exists in CacheFileDir" if(! -e $file);
  
  } elsif ($a[2] eq "TTS_FileTemplateDir") {
    unless(-e ($TTS_CacheFileDir ."/". $value) or mkdir ($TTS_CacheFileDir ."/". $value)) {
      #Verzeichnis anlegen gescheitert
      return "Could not create directory: <$value>";
    }
  
  } elsif ($a[2] eq "TTS_FileMapping") {
    #ueberpruefen, ob mp3 Template existiert
    my @FileTpl = split(" ", $TTS_FileMapping);
    for(my $j=0; $j<(@FileTpl); $j++) {
      my @FileTplPc = split(/:/, $FileTpl[$j]);
      return "file does not exist: <".$TTS_CacheFileDir ."/". $TTS_FileTemplateDir ."/". $FileTplPc[1] .">"
        unless (-e $TTS_CacheFileDir ."/". $TTS_FileTemplateDir ."/". $FileTplPc[1]);
    }
  }

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $hash->{STATE} = ($do == 1 ? "disabled" : "Initialized");

  return undef;
}

#####################################
sub Text2Speech_Ready($)
{
my ($hash) = @_;
return Text2speech_OpenDev($hash, 1);
} 

########################
sub Text2Speech_OpenDev($) {
  my ($hash) = @_;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  Log3 $name, 4, "Text2Speech opening $name at $dev"; 

  my $conn;
  if($hash->{SSL}) {
    eval "use IO::Socket::SSL";
    Log3 $name, 1, $@ if($@);
    $conn = IO::Socket::SSL->new(PeerAddr => "$dev") if(!$@);
  } else {
    $conn = IO::Socket::INET->new(PeerAddr => $dev);
  } 

  if(!$conn) {
    Log3($name, 3, "Text2Speech: Can't connect to $dev: $!");
    $hash->{STATE} = "disconnected";
    return "";
  } else {
    $hash->{STATE} = "Initialized";
  }

  $hash->{TCPDev} = $conn;
  $hash->{FD} = $conn->fileno(); 

  Log3 $name, 4, "Text2Speech device opened ($name)";

  syswrite($hash->{TCPDev}, $hash->{portpassword} . "\n")
  if($hash->{portpassword}); 

  return undef;
}

########################
sub Text2Speech_CloseDev($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};
  return if(!$dev);
  
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close(); 
    Log3 $hash, 4, "Text2speech Device closed ($name)";
  }

  delete($hash->{TCPDev});
  delete($hash->{FD});
} 

########################
sub Text2Speech_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};

  #my $call = "set tts tts Das ist ein Test.";
  my $call = "set $name tts $msg";

  Text2Speech_OpenDev($hash) if(!$hash->{TCPDev});
  #lets try again
  Text2Speech_OpenDev($hash) if(!$hash->{TCPDev});

  if($hash->{TCPDev}) {
    Log3 $hash, 4, "Text2Speech: Write remote message to $dev: $call";
    Log3 $hash, 3, "Text2Speech: Could not write remote message ($call) at " .$hash->{Host} if(!defined(syswrite($hash->{TCPDev}, "$call\n")));
    Text2Speech_CloseDev($hash);
  }

}


###########################################################################

sub Text2Speech_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);

  my $cmd = shift(@a); # Dummy
     $cmd = shift(@a); # DevName

  if(!defined($sets{$cmd})) {
    my $r = "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets);
    return $r;
  }

  if($cmd ne "tts") {
    return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 0);
  }

  # Abbruch falls Disabled
  return undef if(AttrVal($hash->{NAME}, "disable", "0") eq "1");

  if($cmd eq "tts") {
    if($hash->{MODE} eq "DIRECT") {
      Text2Speech_PrepareSpeech($hash, join(" ", @a));
      $hash->{helper}{RUNNING_PID} = BlockingCall("Text2Speech_DoIt", $hash, "Text2Speech_Done", 60, "Text2Speech_AbortFn", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    } elsif ($hash->{MODE} eq "REMOTE") {
      Text2Speech_Write($hash, join(" ", @a));
    } else {return undef;}
  } elsif($cmd eq "volume") {
      my $vol = join(" ", @a);
      return "volume adjusting only available in direct mode" if($hash->{MODE} ne "DIRECT");
      return "volume level expects 0..100 percent" if($vol !~ m/^([0-9]{1,3})$/ or $vol > 100);
      $hash->{VOLUME} = $vol  if($vol <= 100);
      delete($hash->{VOLUME}) if($vol > 100);
  }

  return undef;
}

#####################################
# Bereitet den gesamten String vor.
# Bei Nutzung Google wird dieser in ein Array
# zerlegt mit jeweils einer maximalen
# Stringlänge von 100Chars
#
# param1: $hash
# param2: string to speech
#
#####################################
sub Text2Speech_PrepareSpeech($$) {
  my ($hash, $t) = @_;

  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $TTS_Delemiter = AttrVal($hash->{NAME}, "TTS_Delemiter", undef); 
  my $TTS_FileTpl   = AttrVal($hash->{NAME}, "TTS_FileMapping", ""); # zb, silence:silence.mp3 ring:myringtone.mp3; im Text: mein Klingelton :ring: ist laut.
  my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");

  my $TTS_ForceSplit = 0;
  my $TTS_AddDelemiter;

  if($TTS_Delemiter && $TTS_Delemiter =~ m/^[+-]a[lfn]/i) {
    $TTS_ForceSplit = 1 if(substr($TTS_Delemiter,0,1) eq "+");
    $TTS_ForceSplit = 0 if(substr($TTS_Delemiter,0,1) eq "-");
    
    $TTS_AddDelemiter = substr($TTS_Delemiter,1,2); # af, al oder an
    
    $TTS_Delemiter = substr($TTS_Delemiter,3);
    
  } elsif (!$TTS_Delemiter) { # Default wenn Attr nicht gesetzt
    $TTS_Delemiter = "(?<=[\\.!?])\\s*";
    $TTS_ForceSplit = 1;
    $TTS_AddDelemiter = "";
  }

  if($TTS_Ressource eq "Google") {
    my @text; 

    $t =~ s/ä/ae/g;
    $t =~ s/ö/oe/g;
    $t =~ s/ü/ue/g;
    $t =~ s/Ä/Ae/g;
    $t =~ s/Ö/Oe/g;
    $t =~ s/Ü/Ue/g;
    $t =~ s/ß/ss/g;

    @text = $hash->{helper}{Text2Speech} if($hash->{helper}{Text2Speech}[0]);
    push(@text, $t);

    my @FileTpl = split(" ", $TTS_FileTpl);
    my @FileTplPc;
    for(my $i=0; $i<(@FileTpl); $i++) {
      #splitte bei jedem Template auf
      @FileTplPc = split(/:/, $FileTpl[$i]);
      @text = Text2Speech_SplitString(\@text, 100, ":".$FileTplPc[0].":", 1, "as"); # splitte bei bspw: :ring:
    }

    @text = Text2Speech_SplitString(\@text, 100, $TTS_Delemiter, $TTS_ForceSplit, $TTS_AddDelemiter);
    @text = Text2Speech_SplitString(\@text, 100, "(?<=[\\.!?])\\s*", 0, "");
    @text = Text2Speech_SplitString(\@text, 100, ",", 0, "al");
    @text = Text2Speech_SplitString(\@text, 100, ";", 0, "al");
    @text = Text2Speech_SplitString(\@text, 100, "und", 0, "af");

    for(my $i=0; $i<(@text); $i++) {
      for(my $j=0; $j<(@FileTpl); $j++) {
        # entferne führende und abschließende Leerzeichen aus jedem Textbaustein
        $text[$i] =~ s/^\s+|\s+$//g; 
        # ersetze die FileTemplates
        @FileTplPc = split(/:/, $FileTpl[$j]);
        $text[$i] = $TTS_FileTemplateDir ."/". $FileTplPc[1] if($text[$i] eq ":".$FileTplPc[0].":")
      }
    }

    @{$hash->{helper}{Text2Speech}} = @text;

  } else {
    push(@{$hash->{helper}{Text2Speech}}, $t);
  }
}

#####################################
# param1: array : Text 2 Speech   
# param2: string: MaxChar
# param3: string: Delemiter
# param4: int   : 1 -> es wird am Delemiter gesplittet
#                 0 -> es wird nur gesplittet, wenn Stringlänge länger als MaxChar
# param5: string: Add Delemiter to String? [al|af|as|<empty>] (AddLast/AddFirst/AddSingle)
#
# Splittet die Texte aus $hash->{helper}->{Text2Speech} anhand des
# Delemiters, wenn die Stringlänge MaxChars übersteigt.
# Ist "AddDelemiter" angegeben, so wird der Delemiter an den 
# String wieder angefügt
#####################################
sub Text2Speech_SplitString(@$$$$){
  my @text          = @{$_[0]};
  my $MaxChar       = $_[1];
  my $Delemiter     = $_[2];
  my $ForceSplit    = $_[3];
  my $AddDelemiter  = $_[4];
  my @newText;

  for(my $i=0; $i<(@text); $i++) {
    if((length($text[$i]) <= 100) && (!$ForceSplit)) { #Google kann nur 100zeichen
      push(@newText, $text[$i]);
      next;
    }

    my @b = split(/$Delemiter/, $text[$i]); 
    for(my $j=0; $j<(@b); $j++) {
      $b[$j] = $b[$j] . $Delemiter if($AddDelemiter eq "al"); # Am Satzende wieder hinzufügen.
      $b[$j+1] = $Delemiter . $b[$j+1] if(($AddDelemiter eq "af") && ($b[$j+1])); # Am Satzanfang des nächsten Satzes wieder hinzufügen.
      push(@newText, $Delemiter) if($AddDelemiter eq "as" && $j>0); # AddSingle: füge Delemiter als EinzelSatz hinzu. Zb. bei FileTemplates
      push(@newText, $b[$j]);
    }
  }
  return @newText;
}

#####################################
# param1: hash  : Hash
# param2: string: Typ (mplayer oder mp3wrap oder ....)
# param3: string: Datei
# 
# Erstellt den Commandstring für den Systemaufruf
#####################################
sub Text2Speech_BuildMplayerCmdString($$) {
  my ($hash, $file) = @_;
  my $cmd;

  my $TTS_MplayerCall = AttrVal($hash->{NAME}, "TTS_MplayerCall", $mplayer);
  my $TTS_VolumeAdjust = AttrVal($hash->{NAME}, "TTS_VolumeAdjust", 110);
  my $verbose = AttrVal($hash->{NAME}, "verbose", 3);

  if($hash->{VOLUME}) { # per: set <name> volume <..>
    $mplayerOpts .= " -softvol -softvol-max ". $TTS_VolumeAdjust ." -volume " . $hash->{VOLUME}; 
  }

  my $AlsaDevice = $hash->{ALSADEVICE};
  if($AlsaDevice eq "none") {
    $AlsaDevice = "";
    $mplayerAudioOpts = "";
  }

  my $NoDebug = $mplayerNoDebug;
  $NoDebug = "" if($verbose >= 5);

  $cmd = $TTS_MplayerCall . " " . $mplayerAudioOpts . $AlsaDevice . " " .$NoDebug. " " . $mplayerOpts . " " . $file; 

  return $cmd;
}

#####################################
# param1: hash  : Hash
# param2: string: Dateiname
# param2: string: Text
# 
# Holt den Text aus dem Google Translator als MP3Datei
#####################################
sub Text2Speech_Download($$$) {
  my ($hash, $file, $text) = @_;

  my $HttpResponse;
  my $fh;

  Log3 $hash->{NAME}, 4, "Text2Speech: Hole URL: ". "http://" . $ttsHost . $ttsPath . uri_escape($text);
  $HttpResponse = GetHttpFile($ttsHost, $ttsPath . uri_escape($text));

  $fh = new IO::File ">$file";
  if(!defined($fh)) {
    Log3 $hash->{NAME}, 2, "Text2Speech: mp3 Datei <$file> konnte nicht angelegt werden.";
    return undef;
  }

  $fh->print($HttpResponse);
  Log3 $hash->{NAME}, 4, "Text2Speech: Schreibe mp3 in die Datei $file mit ".length($HttpResponse)." Bytes";  
  close($fh);
}

#####################################
sub Text2Speech_DoIt($) {
  my ($hash) = @_;

  my $TTS_CacheFileDir = AttrVal($hash->{NAME}, "TTS_CacheFileDir", "cache");
  my $TTS_Ressource = AttrVal($hash->{NAME}, "TTS_Ressource", "Google");
  my $verbose = AttrVal($hash->{NAME}, "verbose", 3);
  my $cmd;

  if($TTS_Ressource eq "Google") {

    my $filename;
    my $file;

    unless(-e $TTS_CacheFileDir or mkdir $TTS_CacheFileDir) {
      #Verzeichnis anlegen gescheitert
      Log3 $hash->{NAME}, 2, "Text2Speech: Angegebenes Verzeichnis $TTS_CacheFileDir konnte erstmalig nicht angelegt werden.";
      return undef;
    }

    
    if(AttrVal($hash->{NAME}, "TTS_UseMP3Wrap", 0)) {
      # benutze das Tool MP3Wrap um bereits einzelne vorhandene Sprachdateien
      # zusammenzuführen. Ziel: sauberer Sprachfluss
      my @Mp3WrapFiles;
      my @Mp3WrapText;
      my $TTS_SentenceAppendix = AttrVal($hash->{NAME}, "TTS_SentenceAppendix", undef); #muss eine mp3-Datei sein, ohne Pfadangabe
      my $TTS_FileTemplateDir = AttrVal($hash->{NAME}, "TTS_FileTemplateDir", "templates");
      
      $TTS_SentenceAppendix = $TTS_CacheFileDir ."/". $TTS_FileTemplateDir ."/". $TTS_SentenceAppendix if($TTS_SentenceAppendix);
      undef($TTS_SentenceAppendix) if($TTS_SentenceAppendix && (! -e $TTS_SentenceAppendix));

      #Abspielliste erstellen
      foreach my $t (@{$hash->{helper}{Text2Speech}}) {
        if(-e $TTS_CacheFileDir."/".$t) { $filename = $t;} else {$filename = md5_hex($t) . ".mp3";} # falls eine bestimmte mp3-Datei gespielt werden soll
        $file = $TTS_CacheFileDir."/".$filename;
        if(-e $file) {
          push(@Mp3WrapFiles, $file);
          push(@Mp3WrapText, $t);
          #Text2Speech_WriteStats($hash, 0, $file, $t);
        } else {last;}
      }

      push(@Mp3WrapFiles, $TTS_SentenceAppendix) if($TTS_SentenceAppendix);

      if(scalar(@Mp3WrapFiles) >= 2) {
        Log3 $hash->{NAME}, 4, "Text2Speech: Bearbeite per MP3Wrap jetzt den Text: ". join(" ", @Mp3WrapText);

        my $Mp3WrapPrefix = md5_hex(join("|", @Mp3WrapFiles));
        my $Mp3WrapFile = $TTS_CacheFileDir ."/". $Mp3WrapPrefix . "_MP3WRAP.mp3"; 

        if(! -e $Mp3WrapFile) {
          $cmd = "mp3wrap " .$TTS_CacheFileDir. "/" .$Mp3WrapPrefix. ".mp3 " .join(" ", @Mp3WrapFiles);
          $cmd .= " >/dev/null" if($verbose < 5);;

          Log3 $hash->{NAME}, 4, "Text2Speech: " .$cmd;
          system($cmd);
        }
        if(-e $Mp3WrapFile) {
          $cmd = Text2Speech_BuildMplayerCmdString($hash, $Mp3WrapFile);
          Log3 $hash->{NAME}, 4, "Text2Speech:" .$cmd;
          system($cmd);
          #Text2Speech_WriteStats($hash, 1, $Mp3WrapFile, join(" ", @Mp3WrapText));
        } else {
          Log3 $hash->{NAME}, 2, "Text2Speech: Mp3Wrap Datei konnte nicht angelegt werden.";
        }
        
        return $hash->{NAME} ."|". 
               ($TTS_SentenceAppendix ? scalar(@Mp3WrapFiles)-1: scalar(@Mp3WrapFiles)) ."|". 
               $Mp3WrapFile;
      }
    }

    if(-e $TTS_CacheFileDir."/".$hash->{helper}{Text2Speech}[0]) { 
      # falls eine bestimmte mp3-Datei gespielt werden soll
      $filename = $hash->{helper}{Text2Speech}[0];
    } else {
      $filename = md5_hex($hash->{helper}{Text2Speech}[0]) . ".mp3";
    } 
    $file = $TTS_CacheFileDir."/".$filename;

    Log3 $hash->{NAME}, 4, "Text2Speech: Bearbeite jetzt den Text: ". $hash->{helper}{Text2Speech}[0];

    if(! -e $file) { # Datei existiert noch nicht im Cache
      Text2Speech_Download($hash, $file, $hash->{helper}{Text2Speech}[0]);
    }

    if(-e $file) { # Datei existiert jetzt
      $cmd = Text2Speech_BuildMplayerCmdString($hash, $file);
      Log3 $hash->{NAME}, 4, "Text2Speech:" .$cmd;
      system($cmd);
    }

    return $hash->{NAME}. "|". 
           "1" ."|".
           $file;

  } elsif ($TTS_Ressource eq "ESpeak") {
    $cmd = "sudo espeak -vde+f3 -k5 -s150 \"" . $hash->{helper}{Text2Speech}[0] . "\""; 
    Log3 $hash, 4, "Text2Speech:" .$cmd;
    system($cmd);
  }

  return $hash->{NAME}. "|". 
         "1" ."|".
         "";
}

####################################################
# Rückgabe der Blockingfunktion
# param1: HashName
# param2: Anzahl der abgearbeiteten Textbausteine
# param3: Dateiname der abgespielt wurde
####################################################
sub Text2Speech_Done($) {
  my ($string) = @_;
  return unless(defined($string));

  my @a = split("\\|",$string);
  my $hash = $defs{shift(@a)};
  my $tts_done = shift(@a);
  my $filename = shift(@a);
  
  if($filename) {
    my @text;
    for(my $i=0; $i<$tts_done; $i++) { 
      push(@text, $hash->{helper}{Text2Speech}[$i]);
    }         
    Text2Speech_WriteStats($hash, 1, $filename, join(" ", @text));
  }

  delete($hash->{helper}{RUNNING_PID});
  splice(@{$hash->{helper}{Text2Speech}}, 0, $tts_done);

  # erneutes aufrufen da ev. weiterer Text in der Warteschlange steht
  if(@{$hash->{helper}{Text2Speech}} > 0) {
    $hash->{helper}{RUNNING_PID} = BlockingCall("Text2Speech_DoIt", $hash, "Text2Speech_Done", 60, "Text2Speech_AbortFn", $hash);
  }
}

#####################################
sub Text2Speech_AbortFn($)     { 
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID});
  Log3 $hash->{NAME}, 2, "Text2Speech: BlockingCall for ".$hash->{NAME}." was aborted";
}

#####################################
# Hiermit werden Statistken per DbLogModul gesammelt
# Wichitg zur Entscheidung welche Dateien aus dem Cache lange 
# nicht benutzt und somit gelöscht werden koennen.
#
# param1: hash
# param2: int:    0=indirekt (über mp3wrap); 1=direkt abgespielt
# param3: string: Datei
# param4: string: Text der als mp3 abgespielt wird
#####################################
sub Text2Speech_WriteStats($$$$){
  my($hash, $typ, $file, $text) = @_;
  my $DbLogDev;

  #suche ein DbLogDevice
  return undef unless($modules{"DbLog"} && $modules{"DbLog"}{"LOADED"});
  foreach my $key (keys(%defs)) {
    if($defs{$key}{TYPE} eq "DbLog") {
      $DbLogDev = $key;
      last;
    } 
  }
  return undef if($defs{$DbLogDev}{STATE} !~ m/(active|connected)/); # muss active sein!

  # den letzten Value von "Usage" ermitteln um dann die Staistik um 1 zu erhoehen.
  my @LastValue = DbLog_Get($defs{$DbLogDev}, "", "current", "array", "-", "-", $hash->{NAME} ."|". $file.":Usage");
  my $NewValue = 1;
  $NewValue = $LastValue[0]{value} + 1 if($LastValue[0]);

  #           DbLogHash,        DbLogTable, TIMESTAMP, DEVICE,                    TYPE,          EVENT, READING, VALUE,     UNIT
  DbLog_Push($defs{$DbLogDev}, "Current", TimeNow(), $hash->{NAME} ."|". $file, $hash->{TYPE}, $text, "Usage", $NewValue, "");
}

1;

=pod
=begin html

<a name="Text2Speech"></a>
<h3>Text2Speech</h3> 
<ul>
  <br>
  <a name="Text2Speechdefine"></a>
  <b>Define</b>
  <ul>
    <b>Local : </b><code>define &lt;name&gt; Text2Speech &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Text2Speech &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code> 
    <p>
    This module converts any text into speech with serveral possible providers. The Device can be defined as locally 
    or remote device.
    </p>
       
    <li>
      <b>Local Device</b><br>
      <ul>
        The output will be send to any connected audiodevice. For example external speakers connected per jack 
        or with bluetooth speakers - connected per bluetooth dongle. Its important to install mplayer.<br>
        <code>apt-get install mplayer</code><br>
        The given alsadevice has to be configured in <code>/etc/asound.conf</code>
        <p>
          <b>Special AlsaDevice: </b><i>none</i><br>
          The internal mplayer command will be without any audio directive if the given alsadevice is <i>none</i>.
          In this case mplayer is using the standard audiodevice.
        </p>
        <p>
          <b>Example:</b><br>
          <code>define MyTTS Text2Speech hw=0.0</code><br>
          <code>define MyTTS Text2Speech none</code>
        </p>
      </ul>
    </li>

    <li>
      <b>Remote Device</b><br>
      <ul>
        This module can configured as remote-device for client-server Environments. The Client has to be configured 
        as local device.<br>
        Notice: the Name of the locally instance has to be the same!
        <ul>
          <li>Host: setting up IP-adress</li>
          <li>PortNr: setting up TelnetPort of FHEM; default: 7072</li>
          <li>SSL: setting up if connect over SSL; default: no SSL</li>
          <li>PortPassword: setting up the configured target telnet passwort</li>
        </ul>
        <p>
          <b>Example:</b><br>
          <code>define MyTTS Text2Speech 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Text2Speech 192.168.178.10</code>
        </p>
      </ul>
    </li>

  </ul>
</ul>

<a name="Text2Speechset"></a>
<b>Set</b> 
<ul>
  <li><b>tts</b>:<br>
    Giving a text to translate into audio.
  </li>
  <li><b>volume</b>:<br>
    Setting up the volume audio response.<br>
    Notice: Only available in locally instances!
  </li>
</ul><br> 

<a name="Text2Speechget"></a>
<b>Get</b> 
<ul>N/A</ul><br> 

<a name="Text2Speechattr"></a>
<b>Attributes</b>
<ul>
  <li>TTS_Delemiter<br>
    optional: By using the google engine, its not possible to convert more than 100 characters in a single audio brick.
    With a delemiter the audio brick will be split at this character. A delemiter must be a single character.!<br>
    By default, ech audio brick will be split at sentence end. Is a single sentence longer than 100 characters, 
    the sentence will be split additionally at comma, semicolon and the word <i>and</i>.<br>
    Notice: Only available in locally instances with Google engine!
  </li> 

  <li>TTS_Ressource<br>
    optional: Selection of the Translator Engine<br>
    Notice: Only available in locally instances!
    <ul>
      <li>Google<br>
        Using the Google Engine. It´s nessessary to have internet access. This engine is the recommend engine
        because the quality is fantastic. This engine is using by default.
      </li>
      <li>ESpeak<br>
        Using the ESpeak Engine. Installation of the espeak sourcen is required.<br>
        <code>apt-get install espeak</code>
      </li>
    </ul>
  </li>

  <li>TTS_CacheFileDir<br>
    optional: The downloaded Goole audio bricks are saved in this folder for reusing. 
    No automatically implemented deleting are available.<br>
    Default: <i>cache/</i><br>
    Notice: Only available in locally instances!
  </li>

  <li>TTS_UseMP3Wrap<br>
    optional: To become a liquid audio response its recommend to use the tool mp3wrap.
    Each downloaded audio bricks are concatinated to a single audio file to play with mplayer.<br>
    Installtion of the mp3wrap source is required.<br>
    <code>apt-get install mp3wrap</code><br>
    Notice: Only available in locally instances!
  </li>

  <li>TTS_MplayerCall<br>
    optional: Setting up the Mplayer system call. The following example is default.<br>
    Example: <code>sudo /usr/bin/mplayer</code>
  </li>

  <li>TTS_SentenceAppendix<br>
    Optional: Definition of one mp3-file to append each time of audio response.<br>
    Using of Mp3Wrap is required. The audio bricks has to be downloaded before into CacheFileDir.
    Example: <code>silence.mp3</code>
  </li>

  <li>TTS_FileMapping<br>
    Definition of mp3files with a custom templatedefinition. Separated by space.
    All templatedefinitions can used in audiobricks by i>tts</i>. 
    The definition must begin and end with e colon. 
    The mp3files must saved in the given directory by <i>TTS_FIleTemplateDir</i>.<br>
    <code>attr myTTS TTS_FileMapping ring:ringtone.mp3 beep:MyBeep.mp3</code><br>
    <code>set MyTTS tts Attention: This is my ringtone :ring: Its loud?</code>
  </li>

  <li>TTS_FileTemplateDir<br>
    Directory to save all mp3-files are defined in <i>TTS_FileMapping</i> und <i>TTS_SentenceAppendix</i><br>
    Optional, Default: <code>cache/templates</code>
  </li>

  <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

  <li><a href="#disable">disable</a><br>
    If this attribute is activated, the soundoutput will be disabled.<br>
    Possible values: 0 => not disabled , 1 => disabled<br>
    Default Value is 0 (not disabled)<br><br> 
  </li>

  <li><a href="#verbose">verbose</a><br>
    <b>4:</b> each step will be logged<br>
    <b>5:</b> Additionally the individual debug informations from mplayer and mp3wrap will be logged
  </li>

</ul>

=end html
=begin html_DE

<a name="Text2Speech"></a>
<h3>Text2Speech</h3> 
<ul>
  <br>
  <a name="Text2Speechdefine"></a>
  <b>Define</b>
  <ul>
    <b>Local : </b><code>define &lt;name&gt; Text2Speech &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Text2Speech &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code> 
    <p>
    Das Modul wandelt Text mittels verschiedener Provider/Ressourcen in Sprache um. Dabei kann das Device als 
    Remote oder Lokales Device konfiguriert werden.
    </p>
       
    <li>
      <b>Local Device</b><br>
      <ul>
        Die Ausgabe erfolgt auf angeschlossenen Audiodevices, zb. Lautsprecher direkt am Ger&auml;t oder per 
        Bluetooth-Lautsprecher per Mplayer. Dazu ist Mplayer zu installieren.<br>
        <code>apt-get install mplayer</code><br>
        Das angegebene Alsadevice ist in der <code>/etc/asound.conf</code> zu konfigurieren.
        <p>
          <b>Special AlsaDevice: </b><i>none</i><br>
          Ist als Alsa-Device <i>none</i> angegeben, so wird mplayer ohne eine Audiodevice Angabe aufgerufen. 
          Dementsprechend verwendet mplayer das Standard Audio Ausgabedevice.
        </p>
        <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Text2Speech hw=0.0</code><br>
          <code>define MyTTS Text2Speech none</code>
        </p>
      </ul>
    </li>

    <li>
      <b>Remote Device</b><br>
      <ul>
        Das Modul ist Client-Server f&auml;as bedeutet, das auf der Haupt-FHEM Installation eine Text2Speech-Instanz 
        als Remote definiert wird. Auf dem Client wird Text2Speech als Local definiert. Die Sprachausgabe erfolgt auf 
        der lokalen Instanz.<br>
        Zu beachten ist, das die Text2Speech Instanz (Definition als local Device) auf dem Zieldevice identisch benannt ist.
        <ul>
          <li>Host: Angabe der IP-Adresse</li>
          <li>PortNr: Angabe des TelnetPorts von FHEM; default: 7072</li>
          <li>SSL: Angabe ob der der Zugriff per SSL erfolgen soll oder nicht; default: kein SSL</li>
          <li>PortPassword: Angabe des in der Ziel-FHEM-Installtion angegebene Telnet Portpasswort</li>
        </ul>
        <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Text2Speech 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Text2Speech 192.168.178.10</code>
        </p>
      </ul>
    </li>

  </ul>
</ul>

<a name="Text2Speechset"></a>
<b>Set</b> 
<ul>
  <li><b>tts</b>:<br>
    Setzen eines Textes zur Sprachausgabe.
  </li>
  <li><b>volume</b>:<br>
    Setzen der Ausgabe Lautst&auml;rke.<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
  </li>
</ul><br> 

<a name="Text2Speechget"></a>
<b>Get</b> 
<ul>N/A</ul><br> 

<a name="Text2Speechattr"></a>
<b>Attribute</b>
<ul>
  <li>TTS_Delemiter<br>
    Optional: Wird ein Delemiter angegeben, so wird der Sprachbaustein an dieser Stelle geteilt. 
    Als Delemiter ist nur ein einzelnes Zeichen zul&auml;ssig.
    Hintergrund ist die Tatsache, das die Google Sprachengine nur 100Zeichen zul&auml;sst.<br>
    Im Standard wird nach jedem Satzende geteilt. Ist ein einzelner Satz l&auml;nger als 100 Zeichen,
    so wird zus&auml;tzlich nach Kommata, Semikolon und dem Verbindungswort <i>und</i> geteilt.<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich und nur Nutzung der Google Sprachengine relevant!
  </li> 

  <li>TTS_Ressource<br>
    Optional: Auswahl der Sprachengine<br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
    <ul>
      <li>Google<br>
        Nutzung der GoogleSprachengine. Ein Internetzugriff ist notwendig! Aufgrund der Qualit&auml;t ist der 
        Einsatz diese Engine zu empfehlen und der Standard.
      </li>
      <li>ESpeak<br>
        Nutzung der ESpeak Offline Sprachengine. Die Qualit&auml; ist schlechter als die Google Engine.
        ESpeak ist vor der Nutzung zu installieren.<br>
        <code>apt-get install espeak</code>
      </li>
    </ul>
  </li>

  <li>TTS_CacheFileDir<br>
    Optional: Die per Google geladenen Sprachbausteine werden in diesem Verzeichnis zur Wiedeverwendung abgelegt.
    Es findet zurZEit keine automatisierte L&ouml;schung statt.<br>
    Default: <i>cache/</i><br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
  </li>

  <li>TTS_UseMP3Wrap<br>
    Optional: F&uuml;r eine fl&uuml;ssige Sprachausgabe ist es zu empfehlen, die einzelnen vorher per Google 
    geladenen Sprachbausteine zu einem einzelnen Sprachbaustein zusammenfassen zu lassen bevor dieses per 
    Mplayer ausgegeben werden. Dazu muss Mp3Wrap installiert werden.<br>
    <code>apt-get install mp3wrap</code><br>
    Achtung: Nur bei einem lokal definierter Text2Speech Instanz m&ouml;glich!
  </li>

  <li>TTS_MplayerCall<br>
    Optional: Angabe der Systemaufrufes zu Mplayer. Das folgende Beispiel ist der Standardaufruf.<br>
    Beispiel: <code>sudo /usr/bin/mplayer</code>
  </li>

  <li>TTS_SentenceAppendix<br>
    Optional: Angabe einer mp3-Datei die mit jeder Sprachausgabe am Ende ausgegeben wird.<br>
    Voraussetzung ist die Nutzung von MP3Wrap. Die Sprachbausteine müssen bereits als mp3 im 
    CacheFileDir vorliegen.
    Beispiel: <code>silence.mp3</code>
  </li>

  <li>TTS_FileMapping<br>
    Angabe von m&ouml;glichen MP3-Dateien mit deren Templatedefinition. Getrennt duch Leerzeichen.
    Die Templatedefinitionen können in den per <i>tts</i> &uuml;bergebenen Sprachbausteinen verwendet werden
    und m&uuml;ssen mit einem beginnenden und endenden Doppelpunkt angegeben werden.
    Die Dateien müssen im Verzeichnis <i>TTS_FIleTemplateDir</i> gespeichert sein.<br>
    <code>attr myTTS TTS_FileMapping ring:ringtone.mp3 beep:MyBeep.mp3</code><br>
    <code>set MyTTS tts Achtung: hier kommt mein Klingelton :ring: War der laut?</code>
  </li>

  <li>TTS_FileTemplateDir<br>
    Verzeichnis, in dem die per <i>TTS_FileMapping</i> und <i>TTS_SentenceAppendix</i> definierten
    MP3-Dateien gespeichert sind.<br>
    Optional, Default: <code>cache/templates</code>
  </li>

  <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

  <li><a href="#disable">disable</a><br>
    If this attribute is activated, the soundoutput will be disabled.<br>
    Possible values: 0 => not disabled , 1 => disabled<br>
    Default Value is 0 (not disabled)<br><br> 
  </li>

  <li><a href="#verbose">verbose</a><br>
    <b>4:</b> Alle Zwischenschritte der Verarbeitung werden ausgegeben<br>
    <b>5:</b> Zus&auml;tzlich werden auch die Meldungen von Mplayer und Mp3Wrap ausgegeben
  </li>

</ul>

=end html_DE
=cut 
