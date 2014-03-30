###################LoTT Uniroll###################
# First release by D. Fuchs and rudolfkoenig
# improved by c-herrmann
# $Id: 10_UNIRoll Ver 1.3 2014-03-30 14:53:00 c-herrmann $
# 
# UNIRoll:no synchronisation, the message protocoll begins directly with datas
# group address  16 Bit like an housecode
# channel address 4 Bit up to 16 devices
# command         4 Bit up: E(1110), stop: D(1101), down: B(1011)
# end off         1 Bit, zero or one it doesnot matter
# whole length   25 Bit
#time intervall:
#Bit-digit 0     high ca. 1,6 ms        equal 100(h64) 16us steps
#                low  ca. 0,576 ms             36(h24)
#Bit-digit 1     high ca. 0,576 ms             36(h24)
#                low  ca. 1,6 ms              100(h64)
#timespace ca.   100 - 170 ms
#binary : 1010 1011 1100 1101 1110 1
#hexa:    a    b    c    d    e    (an additional one bit)
#the message is sent with the general cul-command: G
#G0031A364242464abcd6e8   :  00 synchbits 3 databytes, 1 databit, HHLLLLHH, data

package main;

use strict;
use warnings;

# Stings für Anfang und Ende des Raw-Kommandos
# Die Zeiten für die Impulslänge wurden anhand meiner 1-Kanal-FB etwas angepasst.
# Sie können durch Veränderung der letzten 4 Hex-Bytes in $rawpre geändert werden.
# siehe auch: http://culfw.de/commandref.html#cmd_G
# Seit der Entwickler-Version 1.58 vom 29.03.2014 gibt es einen UNIRoll-Send-Befehl "U".
my $rawpre_old = "G0036E368232368";  # geänderte Timings und 1 Bit am Ende
                                     # culfw bis einschl. 1.58
my $rawpre = "U";                    # Nutzt UNIRoll-Send ab FW 1.58
my $rawpost_old = "80";              # ein 1-Bit senden, culfw bis einschl. 1.58
my $rawpost = "";                    # ein 1-Bit wird mit aktueller culfw automatisch gesendt
my $rPos;
my $tm;

my %codes = (
  "e" => "up",       #1110 e
  "d" => "stop",     #1101 d
  "b" => "down",     #1011 b
  "a" => "pos",      # gezielt eine Position anfahren
);

use vars qw(%UNIRoll_c2b);   # Peter would like to access it from outside

my $UNIRoll_simple = "up stop down pos";

my %models = (
    R_23700 => 'simple',
    dummySimple => 'simple',
);

#############################
sub
UNIRoll_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $UNIRoll_c2b{$codes{$k}} = $k;   # c2b liest das allgmeine Array der Gerätegruppe
  }
# print "UNIRoll_Initialize \n";
  $hash->{Match}     = "^(G|U).*";
  $hash->{SetFn}     = "UNIRoll_Set";
  $hash->{StateFn}   = "UNIRoll_SetState";
  $hash->{DefFn}     = "UNIRoll_Define";
  $hash->{UndefFn}   = "UNIRoll_Undef";
  $hash->{ParseFn}   = "UNIRoll_Parse";
  $hash->{AttrFn}    = "UNIRoll_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ".
                        "ignore:1,0 showtime:1,0 ".
                        "rMin:slider,0,1,120 rMax:slider,0,1,120 rPos:slider,0,1,120 useRolloPos:1,0 " .
                        "sendStopBeforeCmd:1,0,2,3 " .
                        "model:".join(",", sort keys %models);
}
## Neues Attribut sendStopBeforeCmd hinzugefügt. Default ist 1 - Stop wird gesendet.
## Bei 0 wird kein Stop-Befehl vor dem auf/ab-Befehl gesendet.
## Bei 2 wird Stop nur vor "auf" und bei 3 nur vor "ab" gesendet.
## Hier ging der auf-Befehl immer zuverlässig. Ab funktionierte
## nur sporadisch, insbesondere wenn es von einem "at" gesendet wurde.

#####################################
sub
UNIRoll_SetState($$$$)   # 4 Skalare Parameter
{
  my ($hash, $tim, $vt, $val) = @_;  #@_ Array
# print "UNIRoll_SetState \n";

  $val = $1 if($val =~ m/^(.*) \d+$/);  # m match Funktion
  my $name = $hash->{NAME};
  (undef, $val) = ReplaceEventMap($name, [$name, $val], 0)
        if($attr{$name}{eventMap});
  return "setstate $name: undefined value $val" if(!defined($UNIRoll_c2b{$val}));
  return undef;
}

###################################
sub
UNIRoll_Set($@)
{
  my ($hash, @a) = @_; # Eingabewerte nach define name typ devicecode channelcode
  my $ret = undef;
  my $na = int(@a);    #na Anzahl Felder in a
 # print "UNIRoll_Set \n";
  return "no set value specified" if($na < 2 || $na > 3);
  my $c = $UNIRoll_c2b{$a[1]}; # Wert des Kommandos: up stop down pos
  my $name = $a[0];            # Gerätename
  $tm = 0 if(defined($c));     # optionaler Zeitwert
  if($na == 3) {
    $tm = $a[2];
    return "Argument for <time> must be a number" if($tm !~ m/^\d*\.?\d*$/);
  }
  my $tPos = $tm;
  if(!defined($c)) {
    # Model specific set arguments
    my $mt = AttrVal($name, "model", undef);
    return "Unknown argument $a[1], choose one of $UNIRoll_simple"
            if($mt && $mt eq "simple");
    return "Unknown argument $a[1], choose one of " .
            join(" ", sort keys %UNIRoll_c2b);
  }
# RolloPos ausführen, wenn aktiviert
  if(AttrVal($name, "useRolloPos", "0") eq "1") {
    ($c, $tPos) = UNIRoll_RolloPos($hash, $name, $c, $tPos, $a[1]);
  } else {
    return "Please set useRolloPos to 1 to use pos commands with $name." if($c eq "a");
  }
  my $v = join(" ", @a);
  Log3 $name, 3, "UNIRoll set $v";
  (undef, $v) = split(" ", $v, 2);  # Not interested in the name...

# CUL-Kommandos ermitteln und Sendestrings anpassen
  my $culcmds = $hash->{IODev}->{CMDS}; # BCFiAZEGMKURTVWXefmltux
  if($culcmds !~ m/U/) {
    $rawpre = $rawpre_old;
    $rawpost = $rawpost_old;
  }

# G0030A364242464abcd6e8   :  00 Synchbits 3 Datenbytes, 1 Datenbit, HHLLLLHH, Daten
# Damit kein Befehl einen zufälligen Betrieb stoppt 
# vorher ein gezielter Stopp Befehl
# Abschaltbar mit sendStopBeforeCmd 0, 2, 3

  my $stop = "d";
  my $sendstop = AttrVal($name, "sendStopBeforeCmd", "1");
  if($sendstop eq "1" || ($sendstop eq "2" && $c eq "e") || ($sendstop eq "3" && $c eq "b") || $c eq $stop) {
    IOWrite($hash, "",$rawpre.$hash->{XMIT}.$hash->{BTN}.$stop.$rawpost);
    sleep(0.1);
  }
  IOWrite($hash, "",$rawpre.$hash->{XMIT}.$hash->{BTN}.$c.$rawpost) if($c ne $stop); # Auf-/Ab-Befehl ausführen

# XMIT: Gerätegruppe, BTN: Kanalnummer, c: Commando

# Zeit für up/down pausieren, dann Stop-Befehl ausführen und Reading aktualisieren
  InternalTimer(gettimeofday()+$tPos,"UNIRoll_Timer",$hash,0) if($c ne $stop);
  sleep(0.3);

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT} $hash->{BTN}";
  my $tn = TimeNow();
  my $defptr = $modules{UNIRoll}{defptr};
  foreach my $n (keys %{ $defptr->{$code} }) {
    my $lh = $defptr->{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
    my $lhname = $lh->{NAME};
    if($name ne $lhname) {
      DoTrigger($lhname, undef);
    }
  }

  return $ret;
}

#############################
sub
UNIRoll_Define($$)

# Gerät anmelden hash: Hash-adresse, def: Eingabe bei define .....
# Hauscode, Kanalnummer aufbereiten prüfen
 {
  my ($hash, $def) = @_;
#  my $name = $a[0];

  my @a = split("[ \t][ \t]*", $def);
  my $u = "wrong syntax: define <name> UNIRoll device adress " .
                        "addr [fg addr] [lm addr] [gm FF]";
# print "UNIRoll_Define \n";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong device address format: specify a 4 digit hex value "
        if( ($a[2] !~ m/^[a-f0-9]{4}$/i) );

  return "Define $a[0]: wrong chanal format: specify a 1 digit hex value " 
        if( ($a[3] !~ m/^[a-f0-9]{1}$/i) );

  my $devcode = $a[2];
  my $chacode = $a[3];

  $hash->{XMIT} = lc($devcode);             # hex Kleinschreibung ?
  $hash->{BTN}  = lc($chacode);

# Gerätedaten aufbauen, 
# defptr: device pointer global

  my $code = lc("$devcode $chacode");              #lc lowercase Kleinschreibung
  my $ncode = 1;                                   #?
  my $name = $a[0];                                #Gerätename
  $hash->{CODE}{$ncode++} = $code;
  $modules{UNIRoll}{defptr}{$code}{$name}   = $hash;

# print "Test IoPort $hash def $def code $code.\n";

  AssignIoPort($hash);  # Gerät anmelden
}

#############################
sub
UNIRoll_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};
# print "UNIRoll_Undef \n";
    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{UNIRoll}{defptr}{$c} }) {
      delete($modules{UNIRoll}{defptr}{$c}{$dname})
        if($modules{UNIRoll}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

#############################
sub
UNIRoll_Parse($$)
{
 #  print "UNIRoll_Parse \n";
}

#############################
sub
UNIRoll_Attr(@)
{
  return if(!$init_done);  # AttrFn erst nach Initialisierung ausführen
  my ($cmd,$name,$aName,$aVal) = @_;
  $attr{$name}{"webCmd"} = "up:stop:down" if(!defined(AttrVal($name, "webCmd", undef)));
  if($aName eq "useRolloPos") {
    if(defined($aVal) && $aVal == 1) {
      my $st = ReadingsVal($name, "state", "");
      return "Please set $name to the topmost position before activating RolloPos!"
          if($st ne "up");
      CommandSetReading(undef, "$name oldstate $st 0");
      CommandSetReading(undef, "$name oldPos 0");
      $attr{$name}{"useRolloPos"} = "1";
      $attr{$name}{"rPos"} = 0;
      $attr{$name}{"rMin"} = 0 if(!defined(AttrVal($name, "rMin", undef)));
      $attr{$name}{"rMax"} = 0 if(!defined(AttrVal($name, "rMax", undef)));
      return "Please set time for min and max position for $name!" if($attr{$name}{"rMax"} eq "0");
    } else {
      $attr{$name}{"useRolloPos"} = "0";
      CommandDeleteReading(undef, "$name old.*");
    }
  }
  return "This attribute is read-only and must not be changed!"
        if($aName eq "rPos" && AttrVal($name,"useRolloPos","") eq "1");
}

#############################
sub
UNIRoll_Timer($)
{
  my $hash = shift;
  my $stop = "d";
  IOWrite($hash, "",$rawpre.$hash->{XMIT}.$hash->{BTN}.$stop.$rawpost) if($tm ne "0");
  readingsSingleUpdate($hash, "oldPos", $rPos, 1);
}

#############################
sub
UNIRoll_RolloPos($$$$$)
{
# RolloPos - Position Speichern und Positionsbefehle in up/down umwandeln
# Variablen einlesen
    my($hash, $name, $c, $tPos, $nstate) = @_;
    my $rMax = AttrVal($name, "rMax", "0");
    my $rMin = AttrVal($name, "rMin", "0");
    return "Please check rMin and rMax values in attributes" if ($rMax eq "0" || $rMax <= $rMin);
    $rPos = AttrVal($name, "rPos", "0");
    my $oldPos = ReadingsVal($name, "oldPos", "0");

# Zeit und Fahrtrichtung des letzten Befehls ermitteln, falls neuer Befehl vor
# Beendigung der letzten Fahrt abgesetzt wurde, nur Stop zulassen.
# rPos entsprechend anpassen!
    my $tdiff = int(gettimeofday()) - time_str2num(ReadingsTimestamp($name,"state",""));  # Zeit seit letztem Befehl in Sekunden
    my ($lastcmd, $lasttime) = split(" ", ReadingsVal($name,"oldstate",""));  # letzter Befehl z.B. down 9
    if(!defined($lastcmd)) {
      my $nst = ReadingsVal($name, "state", "0");
      $lasttime = 0;
      readingsSingleUpdate($hash, "oldstate", "$nst 0", 1 );
    }
    if($lasttime > $tdiff) {  # wenn letzter Befehl noch nicht abgeschlossen
      return undef if($c ne "d");  # wenn kein Stop -> return
      RemoveInternalTimer($hash);
      $rPos = $oldPos + $tdiff if($lastcmd eq "down");
      $rPos = $oldPos - $tdiff if($lastcmd eq "up");
      $oldPos = $rPos;
      goto DOCMD;
    }
# Befehl ohne Zeitangabe
    if($tm == "0") {
      if($c eq "b") { # ab
        $tPos = $rMax - $rPos;
        $rPos = $rMax;
      } elsif($c eq "e") { # auf
        $tPos = $rPos - $rMin;
        $rPos = $rMin;
      }
      goto DOCMD;
    }
# Befehl mit Zeitangabe
    if($c eq "b") { # ab
      return undef if($rPos >= $rMax);
      if($tm >= $rMax - $rPos) {
        $tPos = $rMax - $rPos;
        $rPos = $rMax;
        $tm = "0";
      } else {
        $rPos = $rPos + $tm;
      }
    } elsif($c eq "e") { # auf
      return undef if($rPos <= $rMin);
      if($tm > $rPos) {
        $tPos = $rPos - $rMin;
        $rPos = $rMin;
        $tm = "0";
      } else {
        $rPos = $rPos - $tm;
	  }
    } elsif($c eq "a") { # pos
      return if($rPos eq $tm);
      return "Invalid position $tm for $name. Maximum value is $rMax." if($tm > $rMax);
      if($rPos > $tm) { # neue Position kleiner
        $c = "e";
        $tPos = $rPos - $tm;
      } elsif($rPos < $tm) { # neue Position größer
        $c = "b";
        $tPos = $tm - $rPos;
      }
      $rPos = $tm;
      $tm = $tPos;
    }
DOCMD:
    $attr{$name}{"rPos"} = $rPos;
#    my $nstate = $a[1];
    $nstate = "down" if($c eq "b");
    $nstate = "up" if($c eq "e");
    $nstate = "$nstate $tPos";
### state ändern!
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $nstate, 1 );
    readingsBulkUpdate($hash, "oldPos", $oldPos, 1 );
    readingsBulkUpdate($hash, "oldstate", $nstate, 1 );
    readingsEndUpdate($hash, 1);
    return ($c, $tPos);
  }
# Ende RolloPos

1;


=pod
=begin html_DE

<a name="UNIRoll"></a>
<h3>UNIRoll</h3>
Deutsche Version der Doku nicht vorhanden. Englische Version unter 

 <a href='http://fhem.de/commandref.html#<UNIRoll>'>UNIRoll</a> &nbsp;

=end html_DE

=begin html

<a name="UNIRoll"></a>
<h3>UNIRoll</h3>
<ul>
  The protocol is used by the Lott UNIROLL R-23700 reciever. The radio
  (868.35 MHz) messages are either received through an <a href="#FHZ">FHZ</a>
  or an <a href="#CUL">CUL</a> device, so this must be defined first.
  Recieving sender messages is not integrated jet.
  The CUL has to allow working with zero synchbits at the beginning of a raw-message.
  This is possible with culfw 1.49 or higher.
  <br><br>

  <a name="UNIRolldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; UNIRoll &lt;devicegroup&gt; &lt;deviceaddress&gt; </code>
    <br><br>

   The values of devicegroup address (similar to the housecode) and device address (button)
   has to be defined as hexadecimal value.
   There is no master or group code integrated.
   <br>

   <ul>
   <li><code>&lt;devicecode&gt;</code> is a 4 digit hex number,
     corresponding to the housecode address.</li>
   <li><code>&lt;channel&gt;</code> is a 1 digit hex number,
     corresponding to a button of the transmitter.</li>
   </ul>
   <br>

    Example:
    <ul>
      <code>define roll UNIRoll 7777 0</code><br>
    </ul>
  </ul>
  <br>

  <a name="UNIRollset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    up
    stop
    down
    pos  (The attribute useRolloPos has to be set to 1 to use this.)
    [&lt;time&gt] in seconds for up, down or pos
    </pre>
    Examples:
    <ul>
      <code>set roll up</code><br>
      <code>set roll up 10</code><br>
      <code>set roll1,roll2,roll3 up</code><br>
      <code>set roll1-roll3 up</code><br>
    </ul>
    <br></ul>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="UNIRollattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is an FHZ
        or a CUL. The device will not work without this entry.</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or komma(,)
        then split not by space but by this character, enabling to embed spaces.<br><br>
        Examples:<ul><code>
        attr device eventMap up:open down:closed<br>
        set device open
        </code></ul>
        </li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="sendStopBeforeCmd"></a>
    <li>sendStopBeforeCmd &lt;value&gt;<br>
        Before any up/down-command a stop-command will be sent to stop a random
        operation. This might cause failure in some situations. This attribute
        can be used to switch off the stop-command by setting it to these values.<br><br>
        where <code>value</code> is one of:<br>
    <pre>
        1 - send always stop (default)
        0 - send no stop
        2 - send stop only before up
        3 - send stop only before down
        </pre></li>

    <a name="useRolloPos"></a>
    <li>useRolloPos &lt;value&gt;<br>
        The position of each device can be stored. By this it is possible to move from
        any position to any other position. As this feature is software-based, a
        manual operation will not be recognized. To set the device into a definite
        state, a up or down command will reset the counter for the position.<br><br>
        where <code>value</code> is one of:<br>
    <pre>
        1 - RolloPos will be used
        0 - RolloPos is not used (default)
        </pre><br>
        These attributes will be created automatical if useRolloPos is set to 1.
        They will not be deleted, if the value is set to 0 or the attribut is deleted.
    <pre>
        rMin - Time in seconds for the topmost position
        rMax - Time in seconds until the device is fully closed
        rPos - This is an internal value and must not be changed!
        </pre></li>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands.
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited. Here is a list of "official"
        devices:<br><br>

          <b>Receiver/Actor</b>: there is only one reciever: R_23700
    </li><br>

  </ul>
  <br>


</ul>
