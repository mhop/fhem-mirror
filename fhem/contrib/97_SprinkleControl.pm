
##############################################
# $Id$
#
# 97_SprinkleControl.pm
#
# written by Tobias Faust 2013-10-23
# e-mail: tobias dot faust at online dot de
#
##############################################

package main;
use strict;
use warnings;
use Data::Dumper;

use vars qw(%gets %sets %defs %attr);

sub SprinkleControl_AllocateNewThread($@);
sub SprinkleControl_DeallocateThread($@);
sub UpdateSprinkleControlList($$);

# SetParamName -> Anzahl Paramter
my %sets = (
  "MaxParallel" => "1"  
);

# These we may get on request
my %gets = (
  "Threads"  => "0"
); 

##########################
sub SprinkleControl_Initialize($)
{
  my ($hash) = @_;

  require "$main::attr{global}{modpath}/FHEM/98_Sprinkle.pm";

  $hash->{DefFn}     = "SprinkleControl_Define";
  $hash->{SetFn}     = "SprinkleControl_Set";
  $hash->{UndefFn}   = "SprinkleControl_Undefine";
  $hash->{AttrFn}    = "SprinkleControl_Attr";
  $hash->{AttrList}  = "disable:0,1".
                       " SprinkleControl_MaxParallel".
                       " ".$readingFnAttributes;
}


##########################
# Define <SprinkleControl> SprinkleControl
##########################
sub SprinkleControl_Define($$)
{
  my ($hash, $def) = @_;
  my $me = $hash->{NAME};
  my @a  = split("[ \t]+", $def);
  
  #$a[0]: Name
  #$a[1]: Type/Alias -> SprinkleControl
  
  if(int(@a) > 2) {
    my $msg =  "wrong syntax: define <name> SprinkleControl";
    Log3 $hash, 2, $msg;
    return $msg;
  }
  
  if(!$attr{$me}) {
    #Attribute vorbelegen! Nur beim Define, kein Modify
    #$attr{$me}{webCmd}              = "Auto:An:Aus:Toggle:Disable";
    $attr{$me}{SprinkleControl_MaxParallel} = 2;
  }

  UpdateSprinkleControlList($hash, "add");

  $hash->{MaxParallel} = $attr{$me}{SprinkleControl_MaxParallel};
  readingsSingleUpdate($hash, "state", "0/".$attr{$me}{SprinkleControl_MaxParallel}, 1);
  readingsSingleUpdate($hash, "CountThreads", 0, 1);

  return undef;
}

#####################################
sub SprinkleControl_Undefine($$)
{
  my ($hash, $arg) = @_;

  UpdateSprinkleControlList($hash, "del");
  return undef;
}

###################################
#
###################################
sub SprinkleControl_Attr(@) {
  my @a = @_;
  my $do = 0;
  my $hash = $defs{$a[1]};
  my $command = $a[0];
  my $setter  = $a[2];
  my $value   = $a[3];

  my $threads = ReadingsVal($hash->{NAME}, "CountThreads",0);

  if($setter eq "SprinkleControl_MaxParallel" && $command ne "del") {
    return "Max Parallel Threads isn´t numeric or not > 0" if ($value !~ m/^(\d+)$/ || $value < 0);
    $hash->{MaxParallel} = $value;
    readingsSingleUpdate($hash, "state", $threads."/".$value, 1);    

  } elsif($setter eq "disable"){
    # 1=disable; 2=enable
    if($command eq "set") {
      $do = (!defined($value) || $value) ? 1 : 2;
    } 
    $do = 2 if($command eq "del");
    readingsSingleUpdate($hash, "state", ($do == 1 ? "disabled" : $threads."/".$hash->{MaxParallel}), 1);
  }

  return undef;

}

###########################################################################

sub SprinkleControl_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);

  my $cmd   = $a[1]; # DevName
  my $value = $a[2]; 

  if(!defined($sets{$cmd})) {
    my $r = "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets);
    return $r;
  }

  # Abbruch falls Disabled
  #return undef if(IsDisabled($hash->{NAME}));

#  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 0);
  my $threads = ReadingsVal($me, "CountThreads",0);  

  if($cmd eq "Disable" && !IsDisabled($me)) {
    $attr{$me}{disable}=1; 
    readingsSingleUpdate($hash, "state", "disabled", 1); # Deaktivieren
    return undef;
  } elsif($cmd eq "Disable" && IsDisabled($me)) {
    $attr{$me}{disable}=0;
    my $threads = ReadingsVal($hash->{NAME}, "CountThreads",0);
    readingsSingleUpdate($hash, "state", $threads."/".$hash->{MaxParallel}, 1);
    return undef;
  } elsif (IsDisabled($me)) { # mache nix da disabled
    return undef;
  } elsif($cmd eq "MaxParallel") {
    $hash->{MaxParallel} = $value;
    readingsSingleUpdate($hash, "state", $threads."/".$value, 1);
  }

  return undef;
}

##########################################################
# Allokiert einen neuen Thread
# param1 :  SprinkleControlDevice
# param2 :  anforderndes Device
# param3 :  Command
# param4 :  Priorität 
#           1->Ausführung sofort ->ToDo
#           2->Ausführung als nächstes, Anfang der Queue
#           3->Einreihung an das Ende der Queue
##########################################################
sub SprinkleControl_AllocateNewThread($@) {
  my ($me, $dev, $cmd, $prio) = @_;
  my $hash = $defs{$me};

  return 1 if(IsDisabled($me));

  my $threads = ReadingsVal($me, "CountThreads",0);
  my $max     = $hash->{MaxParallel};
  $prio = 3 if(!defined($prio));
  
  my $present=0;
  $present = 1 if(defined($hash->{helper}{Queue}{$dev}));
  
  if($present == 0) {
    # noch nciht in der queue vorhanden
    $hash->{helper}{Queue}{$dev}{priority}  = $prio;
    $hash->{helper}{Queue}{$dev}{command}   = $cmd;
  } 

  if($present == 0 || ($present == 1 && $hash->{helper}{Queue}{$dev}{active} == 0)) {
    # schon in der Queue vorhanden aber in Wartestellung
    if($threads < $max) {
      $threads += 1;
      $hash->{helper}{Queue}{$dev}{active} = 1;
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "CountThreads", $threads);
      readingsBulkUpdate($hash, "state", $threads."/".$max);  
      readingsEndUpdate($hash, 1);

      return $threads; # Rückgabe der Threadnummer
    
    } else {
      # abgelehnt da MAX erreicht, in queue gelegt
      $hash->{helper}{Queue}{$dev}{active} = 0;
      return undef ; 
    }
  } else {
    # Device ist bereits in der Queue vorhanden
    return undef; 
  }

}


############################################
# Gibt einen Thread frei
# param1 :  SprinkleControlDevice
# param2 :  abgebendes Device
############################################
sub SprinkleControl_DeallocateThread($@) {
  my ($me, $dev) = @_;
  my $hash = $defs{$me};

  my $threads = ReadingsVal($me, "CountThreads",0);
  my $max     = $hash->{MaxParallel};

  if(defined($hash->{helper}{Queue}{$dev})) {
    $threads -= 1;
    $threads = 0 if($threads<0);
    delete $hash->{helper}{Queue}{$dev};
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "CountThreads", $threads);
  readingsBulkUpdate($hash, "state", ($threads)."/".$max);  
  readingsEndUpdate($hash, 1);

  # den nächsten wartenden Thread aus der Queue starten
  #my %queue = %{$hash->{helper}{Queue}};
  my @queue = sort keys %{$hash->{helper}{Queue}};
#Log3 $hash, 3, "Queue: \n".Dumper(@queue);
  for(my $i=0; $i < @queue; $i++) {
    my $d = $queue[$i]; 
#Log3 $hash,3, "Device: $d";    
    if($hash->{helper}{Queue}{$d}{active} == 0) {
#Log3 $hash, 3, "DoIt: $d -> ".$hash->{helper}{Queue}{$d}{command};      
      Sprinkle_DoIt($defs{$d}, $hash->{helper}{Queue}{$d}{command});
      last;
    }
  }

  return 1;
}

############################################
# Updatet die AttrListe im SprinkleModul
############################################
sub UpdateSprinkleControlList($$) {
  my ($hash, $cmd) = @_;
  
  #List verfuegbarer SprinkleControls in den SprinkleModulen aktualisieren
  my $attrlist = $modules{Sprinkle}{AttrList};
#Log3 $hash,3,"1. AttrList: ".$attrlist;  
  #my $newlist = "SprinkleControl:";
  my @newlist;
  my $newlist1 = "";

  foreach my $d (sort keys %defs) { 
    if($defs{$d}{TYPE} eq "SprinkleControl") {
      push(@newlist, $d) unless(defined($hash) && ($d eq $hash->{NAME}) && ($cmd eq "del"))
    }
  }
  
  if(@newlist > 0) {
    $newlist1 = "SprinkleControl:" . join(",", @newlist);
  }

  #if($attrlist) {
    #$attrlist =~ s/(SprinkleControl\:[^\ ]+)/$newlist1/i;
    $attrlist =~ s/SprinkleControl\:[^\ ]+/$newlist1/i;
#Log3 $hash,3,"2. AttrList: ".$attrlist;      
    $attrlist .= " ".$newlist1 if($attrlist !~ m/SprinkleControl/);
#Log3 $hash,3,"3. AttrList: ".$attrlist;      
    $modules{Sprinkle}{AttrList} = $attrlist;
  #}

#Log3 $hash,3,"4. AttrList: ".$attrlist;  
}

1;

=pod
=begin html

<a name="Sprinkle"></a>
<h3>Sprinkle</h3> 
<ul>
  <br>
  <a name="Sprinkledefine"></a>
  <b>Define</b>
  <ul>
    <b>Local : </b><code>define &lt;name&gt; Sprinkle &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Sprinkle &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code> 
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
          <code>define MyTTS Sprinkle hw=0.0</code><br>
          <code>define MyTTS Sprinkle none</code>
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
          <code>define MyTTS Sprinkle 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Sprinkle 192.168.178.10</code>
        </p>
      </ul>
    </li>

  </ul>
</ul>

<a name="Sprinkleset"></a>
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

<a name="Sprinkleget"></a>
<b>Get</b> 
<ul>N/A</ul><br> 

<a name="Sprinkleattr"></a>
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

<a name="Sprinkle"></a>
<h3>Sprinkle</h3> 
<ul>
  <br>
  <a name="Sprinkledefine"></a>
  <b>Define</b>
  <ul>
    <b>Local : </b><code>define &lt;name&gt; Sprinkle &lt;alsadevice&gt;</code><br>
    <b>Remote: </b><code>define &lt;name&gt; Sprinkle &lt;host&gt;[:&lt;portnr&gt;][:SSL] [portpassword]</code> 
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
          <code>define MyTTS Sprinkle hw=0.0</code><br>
          <code>define MyTTS Sprinkle none</code>
        </p>
      </ul>
    </li>

    <li>
      <b>Remote Device</b><br>
      <ul>
        Das Modul ist Client-Server f&auml;as bedeutet, das auf der Haupt-FHEM Installation eine Sprinkle-Instanz 
        als Remote definiert wird. Auf dem Client wird Sprinkle als Local definiert. Die Sprachausgabe erfolgt auf 
        der lokalen Instanz.<br>
        Zu beachten ist, das die Sprinkle Instanz (Definition als local Device) auf dem Zieldevice identisch benannt ist.
        <ul>
          <li>Host: Angabe der IP-Adresse</li>
          <li>PortNr: Angabe des TelnetPorts von FHEM; default: 7072</li>
          <li>SSL: Angabe ob der der Zugriff per SSL erfolgen soll oder nicht; default: kein SSL</li>
          <li>PortPassword: Angabe des in der Ziel-FHEM-Installtion angegebene Telnet Portpasswort</li>
        </ul>
        <p>
          <b>Beispiel:</b><br>
          <code>define MyTTS Sprinkle 192.168.178.10:7072 fhempasswd</code>
          <code>define MyTTS Sprinkle 192.168.178.10</code>
        </p>
      </ul>
    </li>

  </ul>
</ul>

<a name="Sprinkleset"></a>
<b>Set</b> 
<ul>
  <li><b>tts</b>:<br>
    Setzen eines Textes zur Sprachausgabe.
  </li>
  <li><b>volume</b>:<br>
    Setzen der Ausgabe Lautst&auml;rke.<br>
    Achtung: Nur bei einem lokal definierter Sprinkle Instanz m&ouml;glich!
  </li>
</ul><br> 

<a name="Sprinkleget"></a>
<b>Get</b> 
<ul>N/A</ul><br> 

<a name="Sprinkleattr"></a>
<b>Attribute</b>
<ul>
  <li>TTS_Delemiter<br>
    Optional: Wird ein Delemiter angegeben, so wird der Sprachbaustein an dieser Stelle geteilt. 
    Als Delemiter ist nur ein einzelnes Zeichen zul&auml;ssig.
    Hintergrund ist die Tatsache, das die Google Sprachengine nur 100Zeichen zul&auml;sst.<br>
    Im Standard wird nach jedem Satzende geteilt. Ist ein einzelner Satz l&auml;nger als 100 Zeichen,
    so wird zus&auml;tzlich nach Kommata, Semikolon und dem Verbindungswort <i>und</i> geteilt.<br>
    Achtung: Nur bei einem lokal definierter Sprinkle Instanz m&ouml;glich und nur Nutzung der Google Sprachengine relevant!
  </li> 

  <li>TTS_Ressource<br>
    Optional: Auswahl der Sprachengine<br>
    Achtung: Nur bei einem lokal definierter Sprinkle Instanz m&ouml;glich!
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
    Achtung: Nur bei einem lokal definierter Sprinkle Instanz m&ouml;glich!
  </li>

  <li>TTS_UseMP3Wrap<br>
    Optional: F&uuml;r eine fl&uuml;ssige Sprachausgabe ist es zu empfehlen, die einzelnen vorher per Google 
    geladenen Sprachbausteine zu einem einzelnen Sprachbaustein zusammenfassen zu lassen bevor dieses per 
    Mplayer ausgegeben werden. Dazu muss Mp3Wrap installiert werden.<br>
    <code>apt-get install mp3wrap</code><br>
    Achtung: Nur bei einem lokal definierter Sprinkle Instanz m&ouml;glich!
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
