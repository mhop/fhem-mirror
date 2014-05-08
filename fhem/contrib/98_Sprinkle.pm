
##############################################
# $Id$
#
# 98_Sprinkle.pm
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

# SetParamName -> Anzahl Paramter
my %sets = (
  "Auto"    => "0",
  "An"      => "0",
  "Aus"     => "0",
  "Toggle"  => "0",
  "Disable" => "0"  
);

# These we may get on request
#my %gets = (
#  "alarms"  => "0"
#); 

##########################
sub Sprinkle_Initialize($)
{
  my ($hash) = @_;

  require "$main::attr{global}{modpath}/FHEM/97_SprinkleControl.pm";

  $hash->{DefFn}     = "Sprinkle_Define";
  $hash->{NotifyFn}  = "Sprinkle_Notify";
  $hash->{SetFn}     = "Sprinkle_Set";
  $hash->{UndefFn}   = "Sprinkle_Undefine";
  $hash->{AttrFn}    = "Sprinkle_Attr";
  $hash->{AttrList}  = "disable:0,1".
                       " Sprinkle_SensorThreshold". # in 0% - 100%
                       " Sprinkle_OnTimeSec". # =0: On; >0: on-for-timer x
                       " Sprinkle_DefaultCmd:Auto,An".
                       " ".$readingFnAttributes;

}


##########################
# Define <sprinkle> Sprinkle <actor> [<sensor>] [<timespec>]
##########################
sub Sprinkle_Define($$)
{
  my ($hash, $def) = @_;
  my $me = $hash->{NAME};
  my @a  = split("[ \t]+", $def);
  
  #$a[0]: Name
  #$a[1]: Type/Alias -> Sprinkle
  my $device    =  $a[2];
  
  my $deviceport;
  my $sensor;
  my $sensorport;
  my $timespec;
  
  $sensor     =  $a[3] if($a[3] && length($a[3])>0);
  $timespec   =  $a[4] if($a[4] && length($a[4])>0);
  
  if(int(@a) < 3) {
    my $msg =  "wrong syntax: define <name> Sprinkle <actor> [<sensor>] [<timespec>]";
    Log3 $hash, 2, $msg;
    return $msg;
  }
  
  my @t;
  # Check definition of device
  if($device =~ m/:/) {
    @t = split(":", $device);
    $device = $t[0];
    $deviceport = $t[1] if($t[1]);
  }
  # check definition of sensor
  if($sensor && $sensor =~ m/:/) {
    @t = split(":", $sensor);
    $sensor = $t[0];
    $sensorport = $t[1] if($t[1]);
  }

  return "Given device not exists: $device" if(!$defs{$device});
  return "Given Sensordevice not exists: $sensor" if(defined($sensor) && !$defs{$sensor});

  return "The specified reading of device not exists: $deviceport" if (defined($deviceport) && !defined(ReadingsVal($device, $deviceport, undef)));
  return "The specified reading of sensor not exists: $sensorport" if (defined($sensorport) && !defined(ReadingsVal($sensor, $sensorport, undef)));
  
  return "Wrong timespec, use \"[+]<hour>:<minute>:<second>\"" if(defined($timespec) && $timespec !~ m/^([\+]?)([\d]{2}):([\d]{2}):([\d]{2})$/); 

  #ininitial delete
  delete $hash->{Device};
  delete $hash->{DevicePort};
  delete $hash->{Sensor};
  delete $hash->{SensorPort};
  delete $hash->{TimeSpec};
  delete $hash->{NOTIFYDEV};

  $hash->{Device}     = $device;
  $hash->{DevicePort} = $deviceport if($deviceport);
  $hash->{Sensor}     = $sensor     if($sensor);
  $hash->{SensorPort} = $sensorport if($sensorport);
  $hash->{TimeSpec}   = $timespec   if($timespec);
  $hash->{NOTIFYDEV}  = $device;

  if(!$attr{$me}) {
    #Attribute vorbelegen! Nur beim Define, kein Modify
    $attr{$me}{webCmd}              = "Auto:An:Aus:Toggle:Disable";
    $attr{$me}{devStateIcon}        = "An:general_an Aus:general_aus Auto:time_automatic disabled:remotecontrol/black_btn_POWEROFF2";
    $attr{$me}{Sprinkle_OnTimeSec}  = 640;
    $attr{$me}{Sprinkle_SensorThreshold} = 50;
    $attr{$me}{Sprinkle_DefaultCmd} = "Auto";
  }

  UpdateSprinkleControlList(undef, undef);

  if(defined($timespec) && $sensor && $attr{$me}{Sprinkle_OnTimeSec} && $attr{$me}{Sprinkle_SensorThreshold}) {
    readingsSingleUpdate($hash, "state", "Auto", 1);
    Sprinkle_InternalTimerDoIt($hash);
  } else {
    readingsSingleUpdate($hash, "state", "Initialized", 1);
  }

  return undef;
}

#####################################
sub Sprinkle_Undefine($$)
{
 my ($hash, $arg) = @_;

 RemoveInternalTimer($hash);
 return undef;
}

###################################
#
###################################
sub Sprinkle_Attr(@) {
  my @a = @_;
  my $do = 0;
  my $hash = $defs{$a[1]};
  my $command = $a[0];
  my $setter  = $a[2];
  my $value   = $a[3];

  if($setter eq "Sprinkle_SensorThreshold" && $command ne "del") {
    return "SensorTreshold isn´t numeric or not in range [0..100]" if ($value !~ m/^(\d+)$/ || $value < 0 || $value > 100);
  
  } elsif($setter eq "Sprinkle_OnTimeSec" && $command ne "del") {
    return "OnTimeSec isn´t numeric or not greater than zero" if ($value !~ m/^(\d+)$/ || $value < 0);
  
  } elsif($setter eq "disable"){
    # 1=disable; 2=enable
    if($command eq "set") {
      $do = (!defined($value) || $value) ? 1 : 2;
    } 
    $do = 2 if($command eq "del");
    readingsSingleUpdate($hash, "state", ($do == 1 ? "disabled" : "Initialized"), 1);
  }

  return undef;

}

################################################
#
#
###############################################
sub Sprinkle_Set($@)
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

  # Abbruch falls Disabled
  #return undef if(IsDisabled($hash->{NAME}));

  #if($cmd ne "tts") {
  #  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 0);
  #}
  
  RemoveInternalTimer($hash);

  if($cmd eq "Disable" && !IsDisabled($me)) {
    $attr{$me}{disable}=1; 
    readingsSingleUpdate($hash, "state", "disabled", 1); # Deaktivieren
    return undef;
  } elsif($cmd eq "Disable" && IsDisabled($me)) {
    $attr{$me}{disable}=0;
    readingsSingleUpdate($hash, "state", "Aus", 1); # wieder aktivieren, Startzustand: Aus
    return undef;
  } elsif (IsDisabled($me)) { # mache nix da disabled
    return undef;
  } elsif($cmd eq "Toggle") {
      my $aktstate = lc(OldValue($me));
      if($aktstate =~ m/^aus/) {
        $cmd = "An";
      } else {
        $cmd = "Aus";
      }
  } elsif($cmd eq "Auto") {
    return "automode not possible because no sensor defined" if(!defined($hash->{Sensor}));
    return "automode not possible because no sensor threshold (Sprinkle_SensorThreshold) defined or value is 0" if(AttrVal($me, "Sprinkle_SensorThreshold", 0) == 0);
    return "automode not possible because no time definition (Sprinkle_OnTimeSec) defined or value is 0" if(AttrVal($me, "Sprinkle_OnTimeSec", 0) == 0);

    if(OldValue($me) !~ m/Auto/) {
      readingsSingleUpdate($hash, "state", "Auto", 1); # AutoMode aktivieren, Startzustand: Aus
      Sprinkle_InternalTimerDoIt($hash, 0);
      return undef;
    }
  }

  Sprinkle_DoIt($hash, $cmd);
  
  return undef;
}

################################################
#
#
###############################################
sub Sprinkle_Notify($$) {
  # Log is my entry, Dev is the entry of the changed device
  my ($hash, $dev) = @_;
  my $me = $hash->{NAME};
  my $devname = $dev->{NAME};
  return undef if(IsDisabled($me));
  return undef if($hash->{Device} ne $dev->{NAME}); 

  my $SprinkleControl = AttrVal($me, "SprinkleControl", undef);
  
  my $newState;
  $newState = "An"  if(lc(ReadingsVal($devname, "state", "")) =~ m/(an|on)/);
  $newState = "Aus" if(lc(ReadingsVal($devname, "state", "")) =~ m/(aus|off)/);

  if($newState eq "An") {
    SprinkleControl_AllocateNewThread($SprinkleControl, $me, "An") if($SprinkleControl);
  } elsif($newState eq "Aus") {
    SprinkleControl_DeallocateThread($SprinkleControl, $me) if($SprinkleControl);
  }

  if(lc(ReadingsVal($me, "state", "")) =~ m/auto/) {
    $newState = "Auto(An)" if ($newState eq "An");
    $newState = "Auto" if ($newState eq "Aus");
  }

  readingsSingleUpdate($hash, "state", $newState, 1) if($newState);

  return undef;
}

################################################
#
#
###############################################
sub Sprinkle_InternalTimerDoIt(@) {
  my ($hash, $DoIt) = @_;
  my $me = $hash->{NAME};
  
  $DoIt = 1 if(!defined($DoIt));

  if(defined($hash->{TimeSpec}) && $hash->{TimeSpec} =~ m/^([\+]?)([\d]{2}):([\d]{2}):([\d]{2})$/) {
    my ($rel, $hr, $min, $sec) = ($1, $2, $3, $4);
    my @lt = localtime(time);
    my $nt = time;
    $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0]) # Midnight for absolute time
      if($rel ne "+");
    $nt += ($hr*3600+$min*60+$sec); # Plus relative time
    
    @lt = localtime($nt);
    my $ntm = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
    $hash->{NextTime} = $ntm;
    $hash->{TriggerTime} = $nt;

    my $DefaultCmd = AttrVal($me, "Sprinkle_DefaultCmd", "Auto");
    RemoveInternalTimer($hash);
    Sprinkle_DoIt($hash, $DefaultCmd) if($DoIt == 1);
    InternalTimer($nt, "Sprinkle_InternalTimerDoIt", $hash, 0);  
  } else {
    delete $hash->{NextTime};
    delete $hash->{TriggerTime};
  }

}


##############################################
# HauptProzedur zur Bewässerungssteuerung
# 
# param1: $hash
# param2: Command, zb: An, Auto, Aus...
##############################################
sub Sprinkle_DoIt($$) {
  my ($hash, $cmd) = @_;
  my $me = $hash->{NAME};
  return undef if(IsDisabled($me));
  return undef if((lc(ReadingsVal($me, "state", undef)) =~ m/an/) &&
                  (lc($cmd) !~ m/aus/)) ; # Aufruf durch InternalTimer und manuell wurde bereits angeschaltet

  my $SensorTreshold = AttrVal($me, "Sprinkle_SensorThreshold", undef);
  my $OnTimeSec = AttrVal($me, "Sprinkle_OnTimeSec", undef);
  
  my $device      = $hash->{Device};
  my $deviceport  = $hash->{DevicePort}  if(defined($hash->{DevicePort}));
  my $sensor      = $hash->{Sensor}      if(defined($hash->{Sensor}));
  my $sensorport  = $hash->{SensorPort}  if(defined($hash->{SensorPort}));

  my $oldState;
  my $sensorvalue;

  # aktuellen Status des Device abfragen
  if(defined($deviceport)) {
    $oldState = lc(ReadingsVal($device, $deviceport,undef));
  } else {
    $oldState = lc(ReadingsVal($device, "state", undef));
  }
  return "actual state of given device not accessable, please check definition of $me" if(!$oldState);

  # Status des Sensors abfragen  
  if (defined($sensor) && defined($sensorport)) { 
    $sensorvalue = ReadingsVal($sensor, $sensorport, undef); 
  } 
  if(defined($sensor) && !defined($sensorport)) {
    $sensorvalue = ReadingsVal($sensor, "status", undef);
    $sensorvalue = ReadingsVal($sensor, "state",  undef) if (!defined($sensorvalue));
    
    #Bodenfeuchte ist kein Messwert sondern nur ein on/off Reading
    $sensorvalue = 0 if(lc($sensorvalue) =~ m/^(on)/);
    $sensorvalue = 999 if(lc($sensorvalue) =~ m/^(off)/);
  }  

  return "AutoMode not accessable. Please check your Sprinkle attributes and value of Sensor" 
    if(lc($cmd) eq "auto" && (!defined($OnTimeSec) || $OnTimeSec <= 0 || !defined($sensorvalue) || !defined($SensorTreshold)));
  
  my $newState;
  my $OnCmd;
  my $OnCmdAdd = "";
  my $doit = 0; # 0 => mache nichts; 1 => mache; 2 => warte auf Freigabe SprinkleControl

  if(defined($OnTimeSec) && $OnTimeSec > 0 ) {
    $OnCmd = "on-for-timer ".$OnTimeSec;
  } else {
    $OnCmd = "on";
  }

  my $SprinkleControl = AttrVal($me, "SprinkleControl", undef);

  if(defined($deviceport)) {
    $OnCmdAdd = "output ".$deviceport; #zb OWSwitch, ev. unterscheiden nach OWSWITCH und OWDEVICE
  }

  if(lc($cmd) eq "an") {
    $newState = $cmd;
    if($oldState ne $newState && (($SprinkleControl && SprinkleControl_AllocateNewThread($SprinkleControl, $me, $cmd)) || !$SprinkleControl)) {
      fhem "set $device $OnCmdAdd $OnCmd";
      $doit = 1;
    }  elsif($oldState ne $newState) {
      $newState = "Wait";
      $doit = 2;
    }
  
  } elsif(lc($cmd) eq "aus") {
    $newState = $cmd;
    if($oldState ne $newState && (($SprinkleControl && SprinkleControl_DeallocateThread($SprinkleControl, $me)) || !$SprinkleControl)) {
      fhem "set $device off";
      $doit = 1;
    }
  
  } elsif(lc($cmd) eq "auto") {
    if($SensorTreshold >= $sensorvalue) {
      $newState = "Auto(An)";
      if($oldState ne "on" && (($SprinkleControl && SprinkleControl_AllocateNewThread($SprinkleControl, $me, $cmd)) || !$SprinkleControl)) {
        fhem "set $device $OnCmdAdd $OnCmd";
        $doit = 1;
      }  elsif ($oldState ne $newState) {
        $newState = "Wait";
        $doit = 2;
      }
    } else {
      $newState = "Auto";
      if($oldState ne "off" && (($SprinkleControl && SprinkleControl_DeallocateThread($SprinkleControl, $me)) || !$SprinkleControl)) {
        fhem "set $device off";
        $doit = 1;
      }
    }
  }

  readingsSingleUpdate($hash, "state", $newState, 1) if($doit >= 1);

  return $newState;
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
