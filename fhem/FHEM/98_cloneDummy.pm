# $Id$
################################################################################
# 98_cloneDummy
# Von Joachim Herold
# FHEM Modul um aus Events von FHEM2FHEM clone-Devices zu erstellen
# cloneDummy ist "readonly"
# Grundlage ist 98_dummy.pm von Rudolf Koenig
# von betateilchen gab es viel Hilfe (eigentlich wars betateilchen)
# mit Erweiterungenen von gandy
#
# Anleitung:
# Um cloneDummy zu nutzen, einfach einen cloneDummy anlegen
# 
# Eintrag in der fhem.cfg:
# define <name> cloneDummy <quellDevice> [reading]
# attr <name> cloneIgnore <reading1,reading2,...,readingX>
# attr <name> addStateEvent 1 (0 ist Vorgabe)
#
#
################################################################################

package main;

use strict;
use warnings;

################################################################################
# Initialisierung des Moduls
################################################################################
sub cloneDummy_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = "cloneDummy_Define";
  $hash->{NotifyFn}  = "cloneDummy_Notify";
  $hash->{AttrList}  = "cloneIgnore "
                       ."addStateEvent:0,1 "
                       .$readingFnAttributes;
}

################################################################################
# Definition des Moduls
################################################################################
sub cloneDummy_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> cloneDummy <sourceDevice> [reading]"
  if((int(@a) < 3 || int(@a) > 4)) ;

  return "Error: cloneDummy and sourceDevice must not have the same name!"
  if($a[0] eq $a[2]);

  my $hn = $hash->{NAME};
  $hash->{NOTIFYDEV} = $a[2];
  $hash->{NOTIFYSTATE} = $a[3] if(defined($a[3]));
  $attr{$hn}{stateFormat} = "_state" if(defined($a[3]));
  readingsSingleUpdate($hash,'state','defined',1);
  Log3($hash,4,"cloneDummy: $a[0] defined for source $a[2]");
  return undef;
}

################################################################################
# auslesen der Daten aus der globalen Schleife und aufbereiten der Daten
################################################################################
sub cloneDummy_Notify($$) {
  my ($hash, $dev) = @_;
  my $dn      = $dev->{NAME};                                                   # Devicename
  my $hn      = $hash->{NAME};                                                  # Quellname
  my $hs      = "";                                                             # optionales reading fuer STATE
  my $events = deviceEvents($dev, AttrVal($hn, "addStateEvent", 0));            # Quellevents
  my $max = int(@{$events});							# Anzahl Quellevents
  if(defined($hash->{NOTIFYSTATE})) {
    $hs = $hash->{NOTIFYSTATE};
  }

  readingsSingleUpdate($hash,"state", "active",1);
  readingsBeginUpdate($hash);

  for(my $i=0;$i<$max;$i++){
    my $reading = $events->[$i];                                                # Quellevents in einzelne Readings ueberfuehren
    $reading = "" if(!defined($reading));
    Log3($hash,4, "cloneDummy: $hash D: $dn R: $reading");
    my ($rname,$rval) = split(/ /,$reading,2);                                  # zerlegen des Quellevents in Name und Wert
    $rname = substr($rname,0,length($rname)-1);
    my %check = map { $_ => 1 } split(/,/,AttrVal($hn,'cloneIgnore',''));       # vorbereitung cloneIgnore
    my ($isdup, $idx) = CheckDuplicate("", "$hn: $reading", undef);             # vorbereitung doppelte Readings entfernen

    if ($isdup) {                                                               # doppelte Readings filtern
      Log3 $hash, 4, "cloneDummy: drop duplicate <$dn> <$hn> <$reading> ***";
    } else {
      Log3 $hash, 4, "cloneDummy: publish unique <$dn> <$hn> <$reading>";

      if (($hs ne "") && ($rname eq $hs) ){                                     # Reading in _state einsetzen
        readingsBulkUpdate($hash,"_state", $reading);
      }
      unless (exists ($check{$rname})) {                                        # zu ignorierende Reading filtern
        readingsBulkUpdate($hash, $rname, $rval);
      }
    }
  }

  readingsEndUpdate($hash, 1);

  return;
}

1;

=pod
=begin html

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
  <ul>This module provides a cloneDummy which will receive readings from any other device sending data
      to fhem.<br>
      E.g. may be used in an FHEM2FHEM environment. Duplicate source events which may occur within the
      time given by the global attribute <a href="#dupTimeout">dupTimeout</a>, will be suppressed in order
      to avoid overhead. The value of this attribute is to be changed with great care, as it affects other
      parts of FHEM, too.<br>
      the order of precedence for STATE is following:
    <ul><li>if there is no parameter preset then state of cloneDummy (initialized,active)</li>
        <li>if addStateEvent is set then the "state" of cloned Device is set
            (no "state" from cloneDummy)</li>
        <li>if the optional reading is set in define, then value of the optional reading.
            (this will overstrike the previous two lines)</li>
        <li>if stateFormat set ass attr, it will dominate all previous lines</li>
    </ul>
  <br><a name="cloneDummydefine"></a>
  <b>Define</b>
    <ul><code>define &lt;cloneDevice&gt; cloneDummy &lt;sourceDevice&gt; [reading]</code><br>
    <br>Example:<br>
    <br>
      <ul><code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000</code>
      </ul>
    <br>Optional parameter [reading] will be written to STATE if provided.<br>
    <br>Example:<br>
    <br>
      <ul><code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000 temperature</code>
      </ul>
    <br>
  </ul>
  <a name="cloneDummyset"></a>
  <b>Set</b>
    <ul>N/A
    </ul>
  <br>
  <a name="cloneDummyget"></a>
  <b>Get</b>
    <ul>N/A
    </ul>
  <br>
  <a name="cloneDummyattr"></a>
  <b>Attributes</b>
    <ul><li>addStateEvent
    <br>When paremeter in Modul is set to 1 the originalstate of the original Device will be STATE
        (Momentarily not possible in Connection with FHEM2FHEM)</li>
    <br>
        <li>cloneIgnore
    <br>- comma separated list of readingnames that will NOT be generated.<br>
        Usefull to prevent truncated readingnames coming from state events.</li>
    <br>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    </ul>
  <br>
  <b>Important: You MUST use different names for cloneDevice and sourceDevice!</b><br>
  </ul>

=end html

=begin html_DE

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
  <ul>Definiert einen Klon eines lokalen Devices oder von FHEM2FHEM im Logmodus uebergebenen Devices
      und uebernimmt dessen Readings. Sinnvoll um entfernte FHEM-Installationen lesend einzubinden,
      zum Testen oder Programmieren. Dabei werden die von FHEM2FHEM in Form von Events weitergereichten
      entfernten Device-Readings in eigene Readings übernommen. Identische Events, die innerhalb der
      durch das globale Attribut <a href="#dupTimeout">dupTimeout</a> vorgegebenen Zeit auftreten, werden
      zusammengefasst, um überflüssige Events zu verhindern. Dieses Attribut ist mit bedacht zu ändern,
      da sich seine Auswirkungen auch auf andere Bereiche von FHEM erstreckt.<br>
      Die Rangfolge für den STATE ist:
    <ul><li>wenn keine Vorgabe gemacht wurde, dann die Meldung von cloneDummy (initialized, active)</li>
        <li>wenn addStateEvent gesetzt ist, dann der "state" vom geklonten Device (dann kein "state" mehr
            vom cloneDummy)</li>
        <li>wenn das optionale reading im define gesetzt ist, dann der Wert davon (überstimmt die beiden
            vorherigen Zeilen)</li>
        <li>wenn stateFormat als attr gesetzt ist, toppt das alles</li>
    </ul>
  <br>
  <a name="cloneDummydefine"></a>
  <b>Define</b>
    <ul><code>define &lt;name&gt; cloneDummy &lt;Quelldevice&gt; [reading]</code><br>
    <br>
        Aktiviert den cloneDummy, der dann an das Device &lt;Quelldevice&gt; gebunden ist.
        Mit dem optionalen Parameter reading wird bestimmt, welches reading im STATE angezeigt wird,
        stateFormat ist auch weiterhin möglich.<br>
    <br>
      <ul>Beispiel:<br>
      <br>
          Der cloneDummy wird lesend an den Sensor OWX_26_09FF26010000 gebunden und zeigt im
          State temperature an.<br>
      <br>
        <ul><code>define Feuchte cloneDummy OWX_26_09FF26010000 temperature</code><br>
        </ul>
      </ul>
  </ul>
  <br>
  <a name="cloneDummyset"></a>
  <b>Set</b>
    <ul>N/A
    </ul>
  <br>
  <a name="cloneDummyget"></a>
  <b>Get</b>
    <ul>N/A
    </ul>
  <br>
  <a name="cloneDummyattr"></a>
  <b>Attributes</b>
    <ul>
    <li>addStateEvent<br>
        0 ist Vorgabe im Modul, bei 1 wird der Originalstate des original Devices als STATE verwendet
        (geht z.Z. nicht in Verbindung mit FHEM2FHEM)</li>
    <br>
    <li>clonIgnore<br>
        Eine durch Kommata getrennte Liste der readings, die cloneDummy nicht in eigene readings
        umwandelt</li>
    <br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    </ul>
  <br>
  <b>Wichtig: Es müssen unterschiedliche Namen für &lt;name&gt; und &lt;Quelldevice&gt; verwendet
     werden!</b><br/>
  <br>
  </ul>

=end html_DE

=cut
