###############################################################################
#
#   This module is an MQTT bridge, which simultaneously collects data 
#   from several FHEM devices and passes their readings via MQTT 
#   or set readings or attributes from the incoming MQTT messages or 
#   executes them as a 'set' command on the configured FHEM device.
#
#  Copyright (C) 2017 Alexander Schulz
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
###############################################################################

###############################################################################
# 
# CHANGE LOG
#
# 25.03.2021 1.4.1
#  bugfix    : no publish with no global map
#
# 04.03.2021 1.4.0
# change     : perl critic fixes by Beta-User
#
# 16.02.2021 1.3.3
# fix:       : fix cref by Beta-User
#
# 01.02.2021 1.3.2
# buxfix     : Rückname Änderung "retain bei MQTT2 ohne Funktion" wg. Irrtum
#
# 31.01.2021 1.3.1
# cleanup    : Bereinigung der Konstruktionen wie my $... if / unless ...
#              (patch von Beta-User)
# bugfix     : retain bei MQTT2 ohne Funktion (patch von Beta-User)
# added      : Initialisierung beim Start für AttrTemplate (patch von Beta-User)
# added      : Unterstützung für Attribut forceNEXT (patch von Beta-User)
# cleanup    : Dokumentation (patch von Beta-User)
#
# 19.01.2021 1.3.0 
# feature    : supports attrTemplate (thanks to Beta-User)
#
# 19.01.2021 1.2.9
# improvement: increment 'incoming-count' only if at least one device is affected
# bugfix     : fix parse loop over MGB instances for the same IODev (MQTT2-IO only)
# change     : check IOType (MQTT, MQTT2x) slightly improved
#
# 19.01.2021 1.2.9
# change     : ParseFn gibt jetzt immer [NEXT] zurueck
#              Verbessertes Zusammenspiel mit MQTT2-IO
#
# 13.01.2021 1.2.8
# bugfix     : fix perl regex warning - Geschw. Klammern maskieren
#              (forum https://forum.fhem.de/index.php/topic,117659.msg1121004.html#msg1121004)
#
# 12.01.2021 1.2.7
# improvement: Anhaengigkeit zu 00_MQTT.pm dynamisch umgebaut
#              Damit wird kein MQTT.pm mehr gebraucht (und damit kein Module::Pluggable), 
#              falls als IODev  MQTT2_SERVER/CLIENT verwendet wird.
#              Danke fuer den Patch an @rudolfkoenig !
# 
# 25.06.2019 1.2.6
# bugfix     : globalPublish ohne funktion
#
# 06.06.2019 1.2.5
# bugfix     : Korrekte Trennung von Events mit mehrzeiligen Werten 
#              (regex Schalter /sm)
#
# 05.06.2019 1.2.4
# change     : Sonderlocke fuer 'state' in einigen Faellen: 
#              z.B. bei ReadingsProxy kommt in CHANGEDWITHSTATE nichts an, 
#              und in CHANGE, wie gehabt, z.B. 'off'
#
# 02.06.2019 1.2.3
# improvement: fuer mqttPublish Definitionen mit '*' koennen jetzt auch 
#              Mehrfachdefinitionen (mit '!suffix') verwendet werden
#
# 01.06.2019 1.2.2
# bugfix     : mqttPublish Definitionen mit '*' werden nicht verarbeitet
# 
# 27.05.2019 1.2.1
# bugfix     : fixed *:retain in mqttPublish ohne Funktion (auch qos)
#              jetzt werden *:xxx Angaben aus mqttPublish und auch 
#              mqttDefaultPublis (in der GenericBridge) ausgewertet
#
# 26.05.2019 1.2.0
# improvement: Unterstuetzung fuer Variable $uid in expression-Anweisungen
#              (mqttPublish)
#
# 24.05.2019 1.1.9
# improvement: Aufnahme Methoden in Import: toJSON, TimeNow 
# bugfix     : Ersetzen von (Pseudo)Variablen in _evalValue2 ohne Auswirkung
#              (falsche Variable verwendet)
#
# 23.05.2019 1.1.8
# feature    : Unterstuetzung von mehrfachen Topics fuer eine und dieselbe
#              reading (mqttPublish). 
#              Die Definitionen muessen einen durch '!' getrennten 
#              einmaligen Postfix erhalten: reading!postfix:topic=test/test
# 
# 21.05.2019 1.1.7
# cleanup    : Unnoetige 'stopic'-code bei 'publish' 
#              ('stopic' ist nur was fuer subscribe)
#
# 07.03.2019 1.1.7
# fix        : Anpassung fuer MQTT2* 
#              (https://forum.fhem.de/index.php?topic=98249.new#new)
#
# 09.02.2019 1.1.6
# bugfix     : Unterstuetzung von Variablen ($device, $reading, $name, $topic)
#              in publish-expression
#
# 07.02.2019 1.1.5
# feature    : get refreshUserAttr implementiert 
#              (erstellt notwendige user-attr Attribute an den Geraeten neu,
#               nuetzlich nach dem Hinzufügen neuer Geraete bei angegebenen
#               devspec)
#
# 30.01.2019 1.1.4
# change     : Umstellung der Zeichentrenner bei 'Parse' von ':' auf '\0'
#              wg. Problemen mit ':' in Topics (MQTT2*)
#              https://forum.fhem.de/index.php?topic=96608
#
# 29.01.2019 1.1.3
# bugfix     : Parse liefert [NEXT] nur, wenn onmessage wirklich ein array
#              geliefert hat, sonst ""
#
# 19.01.2019 1.1.2
# change     : in 'Parse' wird als erstes Element '[NEXT]' zurueckgegeben,
#              damit ggf. weitere Geraete-Module aufgerufen werden
#              (falls sich diese dafuer interessieren)
#
# 16.01.2019 1.1.1
# improvement: per mqtt erhaltene readingswerte nicht weiterleiten, wenn 
# fix          dadurch der selbe Wert gesendet waere (Endloskreise verhindern)
#
# 14.01.2019 1.1.0
# change/fix : eval jetzt rekursiv, damit mehrere {}-Bloecke moeglich sind
# 
# 12.01.2019 1.0.9
# change     : Doku angepasst, Log-Ausgaben-Format
# fix        : stack trace in log bei subscribe mit undefinierten Variablen
#
# 28.12.2018 1.0.8
# change     : fuer MQTT2_CLIENT (IOWrite): func. name change "subscribe" -> "subscriptions"
#              kein Befehl "subscribtions" an eine MQTT2_SERVER-Instanz senden
#
# 27.12.2018 1.0.7
# implement  : alias bei subscribe
# 
# 27.12.2018 1.0.6
# bugfix     : inkorrekte Verarbeitung von 'mqttDefaults' mit 
#              Prefixen 'pub:'/'sub:'.
# improvement: Sonderlocken fuer $base, $name, $reading, $device, 
#              damit auch xxx:topic={$base} geht (sonst koente nur {"$base"} verwendet werden)
#
# 16.12.2018 1.0.5
#  bugfix    : $name im Unterschied zu $reading in mqttSubscribe funktioniert
#              nicht. Nach dieser Korrektur wird es erstmal als $reading 
#              behandelt, soll jedoch noch ueber mqttAlias redefiniert
#              werden können.
#
# 06.12.2018 1.0.4
#  bugfix    : Variable $base bei publish leer annehmen falls nicht definiert
# 
# 25.11.2018 1.0.3
#  bugfix    : Param name for IOWrite (subscribe)
#
# 21.11.018  1.0.2
#  change    : techn. func. name changed subscribe => subscriptions
#
# 20.11.2018 1.0.2
#  feature   : set subscriptions list to mqtt2-IO
# 
# 19.11.2018 1.0.1
#  bugfix    : fix update multiple readings for the same topic
# 
# 17.11.2018 1.0.0
#  change    : IOWrite Parameter angepasst.
#
# 15.11.2018 1.0.0
#  fix       : Pruefung im Parse auf das richtige IODev gefixt (mqtt2).
#  fix       : Trigger-Event bei Aenderung der Attribute (mqtt2).
#  feature   : Beim publish (global publish related) pruefen, ob das Geraet
#              dem devspec im DEF entspricht (falls vorhanden)
#  feature   : Unterstuetzung fuer MQTT2 -> publish (IOWrite)
#              retain-Flag sollte funktionieren, qos nicht,
#              wie qos uebermittelt werden soll ist noch unklar
#
# 14.11.2018 0.9.9.9
#  feature   : Unterstuetzung fuer MQTT2 -> subscribe (Parse)
#              ! Erfordert Aenderung in MQTT2_CLIENT und MQTT2_SERVER !
#              ! in   $hash->{Clients} = ":MQTT2_DEVICE:MQTT_GENERIC_BRIDGE:";
#              ! und  $hash->{MatchList}= { "1:MQTT2_DEVICE"  => "^.*", 
#                                           "2:MQTT_GENERIC_BRIDGE"=>"^.*" },
#
# 11.11.2018 0.9.9.8
#   change   : import fuer json2nameValue aus main.
#              Damit geht JSON-Unterstuetzung ohne Prefix 'main::'
#              Beispiel: 
#              json:topic=/XTEST/json json:expression={json2nameValue($value)}
#
# 04.11.2018 0.9.9.7
#   bugfix   : Bei Mehrfachdefinitionen wie 'a|b|c:topic=some/$reading/thing'
#              wurden beim Treffer alle genannten Readings aktualisiert 
#              anstatt nur der einer passenden. 
#   change   : forward blockieren nur fuer Readings (mode 'R').
# 
# 18.10.2018 0.9.9.6
#   bugfix   : qos/retain/expression aus 'mqttDefaults' in Device wurden nicht
#              verwendet (Fehler bei der Suche (Namen))
#
# 14.10.2018 0.9.9.5
#   change   : 'mqttForward' dokumentiert
#   improved : Laden von MQTT-Modul in BEGIN-Block verlagert. 
#              Es gab Meldungen ueber Probleme (undefined subroutine) wenn
#              MQTT-Modul in fhem.cfg nach dem Bridge-Modul stand.
#
# 11.10.2018 0.9.9.4
#   change   : 'self-trigger-topic' wieder ausgebaut.
#   feature  : 'mqttForward' Attribute fuer ueberwachte Geraete implmentiert.
#              Moegliche Werte derzeit: 'all' und 'none'. 
#              Bei 'none' werden per MQTT angekommene Nachrichten nicht 
#              aus dem selben Device per MQTT weiter gepublisht.
#              'all' bewirkt das Gegenteil.
#              Fehlt der Attribut, dann wird standartmaeßig für alle 
#              Geraetetypen außer 'Dummy' 'all' angenommen und entsprechend
#              'none' für Dummies. 
#              Deise Einstellung ist notwendig, damit Aktoren ihren zustand 
#              zurueckmelden koennen, jedoch Dummies beim Einsatz als 
#              FHEM-UI-Schalter keine Endlosschleifen verursachen.
#
# 30.09.2018 0.9.9.3
#   feature finished: globalTypeExclude und globalDeviceExclude incl. Commandref
#   bugfix   : initialization
#
# 29.09.2018 0.9.9.2
#   quick fix: received messages forward exclude for 'dummy'
# 
# 27.09.2018 0.9.9.1
#   imroved  : auch bei stopic-Empfang wird nicht weiter gepublisht (s.u.)
#              (kein self-trigger-stopic implementiert, ggf. bei Bedarf)
#   bugfix   : beim Aendern von devspec (ueberwachte Geraete) werden die
#              userattr jetzt korrekt gesetzt bzw. bereinigt und die 
#              Steuerattribute nicht mehr geloescht.
#
# 26.09.2018 0.9.9
#   change   : no-trigger-topic hat wie gewuenscht funktioniert 
#              (mit Nebeneffekten) daher wieder ausgebaut.
#   feature  : fuer 'gewoehliche' readings-topic wird nach dem Empfang beim 
#              Triggern ein Flag gesetzt, das weiteres Publish dieser 
#              Nachricht verhindert. Damit kann selbe Reading fuer Empfang und 
#              Senden verwendet wqerden, ohne dass es zu Loops kommt.
#              Zusaetzlich gibt es jetzt fuer den Subscribe ein 
#              'self-trigger-topic' (auch 'sttopic'), wo trotzdem weiter
#              gepublisht wird. Achtung! Gefahr von Loops und wohl eher
#              ein Sonderfall, wird daher wird nicht in Commandref aufgenommen.
#  
# 25.09.2018 0.9.8.2
#   feature  : no-trigger-topic - wie readings-topic, es wird jedoch 
#              beim Update kein Trigger gesendet.
# 
# 23.09.2018 0.9.8.1
#   change   : Meldung (Reading: transmission-state) ueber inkompatibles IODev
#   bugfix   : beim Aendern von mqttXXX und globalXXX mit Zeilenumbruechen 
#              werden interne Tabellen nicht aktualisiert
#              Problem mit Regex beim Erkennen von Zeilenumbruechen
#   improved : logging
#   change   : Zeitpunkt des letzten Versandes (publish) in dev-rec speichern
#              (Vorbereitung fuer resend interval)
# 
# 22.09.2018 0.9.8
#   improved : Topics-Ausgabe (devinfo, subscribe) alphabetisch sortiert
#   improved : Trennung der zu ueberwachenden Geraete ist jetzt mit Kommas, 
#              Leezeichen, Kommas mit Leerzeichen 
#              oder einer Mischung davon moeglich
#   feature  : Unterstuetzung (fast) beliebiger variablen
#              in defaults / global defaults (subscribe).
#              Verwendung wie bei $base. 
#              z.B. hugo wird zum $hugo in Topics/Expression 
#              Variablen in Dev koennen Variablen aus global verwenden
#   feature  : Neue Einstellung: resendOnConnect fuer mgttPublish
#              Bewirkt, dass wenn keine mqtt-Connection besteht,
#              die zu sendende Nachrichten in einer Warteschlange gespeichet
#              werden. Wird die Verbindung aufgebaut, 
#              werden die Nachrichten verschickt.
#              Moegliche Optionen: none - alle verwerfen,
#              last - immer nur die letzte Nachricht speichern,
#              first - immer nur die erste Nachricht speichern, 
#              danach folgende verwerfen, all - alle speichern, 
#              allerdings existiert eine Obergrenze von 100, wird es mehr,
#              werden aelteste ueberzaelige Nachrichten verworfen.
#              (Beispiel: *:resendOnConnect=last)
#
# 21.09.2019 0.9.7.2
#   fix      : Anlegen / Loeschen von userAttr
#   change   : Vorbereitungen fuer resendOnConnect
# 
# 16.09.2018 0.9.7.1
#   fix      : defaults in globalPublish nicht verfuegbar
#   fix      : atopic in devinfo korrekt anzeigen
#   improved : Anzeige devinfo
#   change   : Umstellung auf delFromDevAttrList (zum Entfernen von UserArrt)
#   change   : Methoden-Doku
#
# 15.09.2018 0.9.7 
#   fix      : Unterstuetzung Variablen (base, name, message in expression)
#   feature  : $base in device-mqttDefault kann auf $base aus
#              globalDefault aus der Bridge zugreifen.
#   improved : wenn fuer publish Expression definiert ist,
#              muss nicht mehr zwingend topic definiert werden
#              (dafuer muss dann ggf. Expression sorgen) 
#   improved : Formatierung Ausgabe devinfo
#   feature  : Unterstuetzung (fast) beliebiger variablen
#              in defaults / global defaults (publish).
#              Verwendung wie bei $base. 
#              z.B. hugo wird zum $hugo in Topics/Expression 
#              Variablen in Dev koennen Variablen aus global verwenden
#   minor fixes                  
#
# xx.08.2018 0.9.6 
#   feature  : Unterstuetzung 'atopic'/sub (Attribute empfangen und setzen)
#   feature  : atopic kann jetzt auch als attr-topic und 
#              stopic als set-topic geschrieben werden.
#
# xx.08.2018 0.9.5 
#   feature  : Unterstuetzung 'atopic'/pub (Attribute senden)
# ...
# ...
# ...
# xx.12.2017 0.0.1 initial
#
###############################################################################

# TODO: globalForwardTypeExclude (default: dummy) Leer/Komma separiert?
# TODO: Pruefung, ob mqtt2-io connected:
# rudolfkoenig (https://forum.fhem.de/index.php/topic,95446.msg890607.html#msg890607):
# [quote]Ich habe nur kurz mit MQTT2_GENERIC_BRIDGE getestet, aber es faellt mir auf, 
# das MQTT_GENERIC_BRIDGE schafft subscribe abzusetzen _bevor_ die Verbindung zum MQTT Server steht. 
# Da ich keine Lust habe die Verantwortung fuer die Zwischenspeicherung (vulgo queuen) zu uebernehmen, 
# liefert in diesem Fall IOWrite einen Fehler zurueck: bitte pruefen.[/quote]

# Ideen:
#
# [done]
#  - global base (sollte in $base verwendet werden koennen)
#  - Support for MQTT2_SERVER
#
# [i like it]
#  - resend / interval, Warteschlange
#    done - resendOnConnect (no, first, last, all)
#    -- autoResendInterval (no/0, x min)
#
# [maybe]
#  - QOS for subscribe (fertig?), defaults(qos, fertig?), alias mapping
#  - global subscribe
#  - global excludes
#  - commands per mqtt fuer die Bridge: Liste der Geraete, Infos dazu etc.
#  - mqttOptions (zuschaltbare optionen im Form eines Perl-Routine) (json, ttl)
#  - template for Publish/Subscribe: in device: reading:template=templateTemperature (template definitions in bridge-device)
#
# [I don't like it]
#  - templates (e.g. 'define template' in der Bridge, 'mqttUseTemplate' in Devices)
#  - autocreate
#  - a reading for last send / receive mesages
#
# [just no]
# 
# 

#
# Bugs:
#
# [done]
#   - Zeilenumbruch wird nicht als Trenner zw. topic-Definitionen erkannt, nur mit einem zusaetzlichen Leerzeichen
#   - Keys enthalten Zeilenumbrueche (topic, expression) => Namen der Readings etc. trimmen bzw. Parser anpassen
#   - Variablen in Expression funktionieren nicht, wenn Topic kein perl-Expression ist
#   - atopic wird in devInfo nicht dargestellt
#   - beim Aendern von mqttXXX und globalXXX mit Zeilenumbruechen werden interne Tabellen nicht aktualisiert
#   - qos/retain ueber mqttDefaults funktionieren nicht (in publish als *:retaind=1 dagegen schon)
#
# [testing]
# 
# [works for me] 
#   - von mehreren sich gleichzeitig aendernden Readings wird nur eine gepostet
#
# [open]
#

package MQTT::GENERIC_BRIDGE;

use strict;
use warnings;
use AttrTemplate;
use Carp qw(carp);
##no critic qw(constant Package)

use GPUtils qw(:all);

#if ($DEBUG) {
  use Data::Dumper;
##   $gets{"debugInfo"}="noArg";
##   $gets{"debugReinit"}="noArg";
#}

#my $DEBUG = 1;
my $cvsid = '$Id$';
my $VERSION = "version 1.4.1 by hexenmeister\n$cvsid";

my %sets = (
);

my %gets = (
  "version"   => "noArg",
  "devlist"   => "",
  "devinfo"   => "",
  "refreshUserAttr" => "noArg"
  #"report"=>"noArg",
);

use constant {
  CTRL_ATTR_NAME_DEFAULTS            => "Defaults",
  CTRL_ATTR_NAME_ALIAS               => "Alias",
  CTRL_ATTR_NAME_PUBLISH             => "Publish",
  CTRL_ATTR_NAME_SUBSCRIBE           => "Subscribe",
  CTRL_ATTR_NAME_IGNORE              => "Disable",
  CTRL_ATTR_NAME_FORWARD             => "Forward",
  CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE => "globalTypeExclude",
  CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE  => "globalDeviceExclude",
  CTRL_ATTR_NAME_GLOBAL_PREFIX       => "global"
};


#if ($DEBUG) {
BEGIN {

  GP_Import(qw(
    CommandAttr
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    Log3
    DoSet
    fhem
    defs
    attr
    readingFnAttributes
    init_done
    AttrVal
    ReadingsVal
    ReadingsTimestamp
    ReadingsAge
    deviceEvents
    AssignIoPort
    addToDevAttrList
    delFromDevAttrList
    devspec2array
    gettimeofday
    InternalTimer
    RemoveInternalTimer
    json2nameValue
    toJSON
    TimeNow
    IOWrite
    AttrTemplate_Set
  ))

};

sub ::MQTT_GENERIC_BRIDGE_Initialize { goto &MQTT_GENERIC_BRIDGE_Initialize }

use constant {
  HELPER                      => ".helper",
  IO_DEV_TYPE                 => "IO_DEV_TYPE",

  HS_TAB_NAME_DEVICES         => "devices",
  HS_TAB_NAME_SUBSCRIBE       => "subscribeTab", # subscribed topics 
  
  HS_FLAG_INITIALIZED         => ".initialized",
  HS_PROP_NAME_INTERVAL       => ".interval",
  HS_PROP_NAME_PREFIX_OLD     => ".prefix_old",
  HS_PROP_NAME_DEVICE_CNT     => ".cnt_devices",
  HS_PROP_NAME_INCOMING_CNT   => ".cnt_incoming",
  HS_PROP_NAME_OUTGOING_CNT   => ".cnt_outgoing",
  HS_PROP_NAME_UPDATE_R_CNT   => ".cnt_update_r",
  HS_PROP_NAME_UPDATE_S_CNT   => ".cnt_update_s",
  
  HS_PROP_NAME_PREFIX         => "prefix",
  HS_PROP_NAME_DEVSPEC        => "devspec",

  HS_PROP_NAME_PUB_OFFLINE_QUEUE       => ".pub_queue", 
  HS_PROP_NAME_PUB_OFFLINE_QUEUE_MAX_CNT_PROTOPIC => ".pub_queue_max_cnt_pro_topic",

  HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE    => "globalTypeExcludes",
  HS_PROP_NAME_GLOBAL_EXCLUDES_READING => "globalReadingExcludes",
  HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES => "globalDeviceExcludes",
  DEFAULT_GLOBAL_TYPE_EXCLUDES     => "MQTT:transmission-state MQTT_DEVICE:transmission-state MQTT_BRIDGE:transmission-state MQTT_GENERIC_BRIDGE "
                                      ."Global telnet FHEMWEB ",
                                      #."CUL HMLAN HMUARTLGW TCM MYSENSORS MilightBridge JeeLink ZWDongle TUL SIGNALDuino *:transmission-state ",
  DEFAULT_GLOBAL_DEV_EXCLUDES     => ""
};


sub MQTT_GENERIC_BRIDGE_Initialize {
  my $hash = shift // return;

  # Consumer
  $hash->{DefFn}    = "MQTT::GENERIC_BRIDGE::Define";
  $hash->{UndefFn}  = "MQTT::GENERIC_BRIDGE::Undefine";
  $hash->{SetFn}    = "MQTT::GENERIC_BRIDGE::Set";
  $hash->{GetFn}    = "MQTT::GENERIC_BRIDGE::Get";
  $hash->{NotifyFn} = "MQTT::GENERIC_BRIDGE::Notify";
  $hash->{AttrFn}   = "MQTT::GENERIC_BRIDGE::Attr";
  $hash->{OnMessageFn} = "MQTT::GENERIC_BRIDGE::onmessage";
  #$hash->{RenameFn} = "MQTT::GENERIC_BRIDGE::Rename";

  $hash->{Match}    = ".*";
  $hash->{ParseFn}  = "MQTT::GENERIC_BRIDGE::Parse";

  $hash->{OnClientConnectFn}           = "MQTT::GENERIC_BRIDGE::ioDevConnect";  
  $hash->{OnClientDisconnectFn}        = "MQTT::GENERIC_BRIDGE::ioDevDisconnect";  
  $hash->{OnClientConnectionTimeoutFn} = "MQTT::GENERIC_BRIDGE::ioDevDisconnect";  
  
  $hash->{AttrList} =
    "IODev ".
    CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS.":textField-long ".
    CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS.":textField-long ".
    CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH.":textField-long ".
    #CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_SUBSCRIBE.":textField-long ".
    CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE.":textField-long ".
    CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE.":textField-long ".
    "disable:1,0 ".
    "debug:0,1 ".
    "forceNEXT:0,1 ".
    $readingFnAttributes;

    #main::LoadModule("MQTT");

    # Beim ModulReload Deviceliste loeschen (eig. nur fuer bei der Entwicklung nuetzich)
    #if($DEBUG) {
    #if($hash->{'.debug'}) {
      for my $d (keys %defs) {
        if(defined($defs{$d}{TYPE})) {
          if($defs{$d}{TYPE} eq "MQTT_GENERIC_BRIDGE") {
            $defs{$d}{".initialized"} = 0;
          }
        }
      }
    #}

    $hash->{'.debug'} = '0';
    return;       
}

###############################################################################
# prueft, ob debug Attribute auf 1 gesetzt ist (Debugmode)
sub isDebug {
  my $hash = shift // return;
  return AttrVal($hash->{NAME},'debug',0);  
}

# Entfernt Leerzeichen vom string vorne und hinten
sub  trim { my $s = shift; $s =~ s{\A\s+|\s+\z}{}gx; return $s }

# prueft, ob der erste gegebene String mit dem zweiten anfaengt
sub startsWith {
  my $str = shift;
  my $subStr = shift // return 0;
  return substr($str, 0, length($subStr)) eq $subStr;
}

###############################################################################
# Device define
sub Define {
  my $hash = shift;
  my $def  = shift // return;
  # Definition :=> defmod mqttGeneric MQTT_GENERIC_BRIDGE [prefix] [devspec,[devspec]]
  my($name, $type, $prefix, @devspeca) = split("[ \t][ \t]*", $def);
  # restlichen Parameter nach Leerzeichen trennen
  # aus dem Array einen kommagetrennten String erstellen
  my $devspec = join(",", @devspeca);
  # Doppelte Kommas entfernen.
  $devspec =~s{,+}{,}gx;
  # damit ist jetzt Trennung der zu ueberwachenden Geraete mit Kommas, Leezeichen, Kommas mit Leerzeichen und Mischung davon moeglich
  my $oldprefix = $hash->{+HS_PROP_NAME_PREFIX};
  my $olddevspec = $hash->{+HS_PROP_NAME_DEVSPEC};
  #removeOldUserAttr($hash) if defined $hash->{+HS_PROP_NAME_PREFIX};

  $prefix="mqtt" unless defined $prefix; # default prefix is 'mqtt'
  
  $hash->{+HELPER} = {} unless defined $hash->{+HELPER};

  $hash->{+HELPER}->{+HS_PROP_NAME_PREFIX_OLD}=$hash->{+HS_PROP_NAME_PREFIX};
  $hash->{+HS_PROP_NAME_PREFIX}=$prefix; # store in device hash
  # wenn Leer oder nicht definiert => devspec auf '.*' setzen
  $devspec = undef if $devspec eq '';
  $hash->{+HS_PROP_NAME_DEVSPEC} = defined($devspec)?$devspec:".*";

  Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Define: params: $name, $type, $hash->{+HS_PROP_NAME_PREFIX}, $hash->{+HS_PROP_NAME_DEVSPEC}");

  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING} = {};
  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE}    = {};
  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES} = {};


  $hash->{+HELPER}->{+HS_PROP_NAME_DEVICE_CNT}   = 0;
  $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT} = 0 if !defined $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT} = 0 if !defined $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT} = 0 if !defined $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT} = 0 if !defined $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT};

  #TODO: aktivieren, wenn gebraucht wird
  $hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL} = 60; # Sekunden

  # Max messages count pro topic for offline queue
  $hash->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE_MAX_CNT_PROTOPIC} = 100;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"incoming-count",$hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT});
  readingsBulkUpdate($hash,"outgoing-count",$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT});
  readingsBulkUpdate($hash,"updated-reading-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT});
  readingsBulkUpdate($hash,"updated-set-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT});
  readingsEndUpdate($hash,0);

  my $newdevspec = initUserAttr($hash);
  # damit ist jetzt Trennung der zu ueberwachenden Geraete mit Kommas, Leezeichen, Kommas mit Leerzeichen und Mischung davon moeglich
  removeOldUserAttr($hash,$oldprefix,$olddevspec,$newdevspec) if (defined ($olddevspec));

  # unless ($main::init_done) {
  #   $hash->{subscribe} = [];
  #   $hash->{subscribeQos} = {};
  #   $hash->{subscribeExpr} = [];
  # }
  
  ::AttrTemplate_Initialize() if $init_done;
  # noetig hier beim Anlegen im laufendem Betrieb
  InternalTimer(1, \&firstInit, $hash);

  return;
}

# Device undefine
sub Undefine {
  my $hash = shift // return;
  RemoveInternalTimer($hash);
  MQTT::client_stop($hash) if isIODevMQTT($hash); 
  return removeOldUserAttr($hash);
}

# erstellt / loescht die notwendigen userattr-Werte (die Bridge-Steuerattribute an den Geraeten laut devspec)
sub refreshUserAttr {
  my $hash = shift // return;
  my $oldprefix = $hash->{+HS_PROP_NAME_PREFIX};
  my $olddevspec = $hash->{+HS_PROP_NAME_DEVSPEC};
  my $newdevspec = initUserAttr($hash);
  removeOldUserAttr($hash,$oldprefix,$olddevspec,$newdevspec) if (defined ($olddevspec));
  return;       
}

# liefert TYPE des IODev, wenn definiert (MQTT; MQTT2,..)
sub retrieveIODevName {
  my $hash = shift // return;
  my $iodn = AttrVal($hash->{NAME}, "IODev", undef);
  return $iodn;
}

# liefert TYPE des IODev, wenn definiert (MQTT; MQTT2,..)
sub retrieveIODevType {
  my $hash = shift // return;
  
  return $hash->{+HELPER}->{+IO_DEV_TYPE} if defined $hash->{+HELPER}->{+IO_DEV_TYPE};

  my $iodn = AttrVal($hash->{NAME}, "IODev", undef);
  my $iodt = undef;
  if(defined($iodn) and defined($defs{$iodn})) {
    $iodt = $defs{$iodn}{TYPE};
  }
  $hash->{+HELPER}->{+IO_DEV_TYPE} =  $iodt;
  return $iodt;
}

# prueft, ob IODev MQTT-Instanz ist
sub isIODevMQTT {
  my $hash = shift // return 0;
  my $iodt = retrieveIODevType($hash);
  return 0 unless defined $iodt;
  return 0 unless $iodt eq 'MQTT';
  return 1;
}

sub checkIODevMQTT2 {
                  
  my $iodt = shift // return 0;
  return 1 if $iodt eq 'MQTT2_SERVER';
  return 1 if $iodt eq 'MQTT2_CLIENT';
  return 0;
}

sub checkIODevMQTT2_CLIENT {
                  
  my $iodt = shift // return 0;
  return 1 if $iodt eq 'MQTT2_CLIENT';
  return 0;
}

# prueft, ob IODev MQTT2-Instanz ist
sub isIODevMQTT2 {
  my $hash = shift // return 0;
  my $iodt = retrieveIODevType($hash);
  return checkIODevMQTT2($iodt);
}

# prueft, ob IODev MQTT2_CLIENT-Instanz ist
sub isIODevMQTT2_CLIENT {
  my $hash = shift // return 0;
  my $iodt = retrieveIODevType($hash);
  return checkIODevMQTT2_CLIENT($iodt);
}

# Fuegt notwendige UserAttr hinzu
sub initUserAttr {
  my $hash = shift // return;
  # wenn bereits ein prefix bestand, die userAttr entfernen : HS_PROP_NAME_PREFIX_OLD != HS_PROP_NAME_PREFIX
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  my $devspec = $hash->{+HS_PROP_NAME_DEVSPEC};
  $devspec = 'global' if ($devspec eq '.*'); # use global, if all devices observed
  my $prefix_old = $hash->{+HELPER}->{+HS_PROP_NAME_PREFIX_OLD};
  if(defined($prefix_old) and ($prefix ne $prefix_old)) {
    #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] initUserAttr: oldprefix: $prefix_old");
    removeOldUserAttr($hash, $prefix_old, $devspec);
  }
  my @devices = devspec2array($devspec);
  #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] initUserAttr: new list: ".Dumper(@devices));
  #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] initUserAttr: addToDevAttrList: $prefix");
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] initUserAttr> devspec: '$devspec', array: ".Dumper(@devices));
  for my $dev (@devices) {
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_DEFAULTS.":textField-long");
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_ALIAS.":textField-long");
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_PUBLISH.":textField-long");
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_SUBSCRIBE.":textField-long");
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_IGNORE.":both,incoming,outgoing");
    addToDevAttrList($dev, $prefix.CTRL_ATTR_NAME_FORWARD.":all,none");
  }
  return \@devices;
}

# Erstinitialization. 
# Variablen werden im HASH abgelegt, userattr der betroffenen Geraete wird erweitert, MQTT-Initialisierungen.
sub firstInit {
  my $hash = shift // return;
  
  # IO    
  AssignIoPort($hash);

  if(isIODevMQTT($hash)) {
    require Net::MQTT::Constants;
    ::LoadModule("MQTT");
    MQTT->import(qw(:all));
  }

  if ($init_done) {
    $hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 0;

    return if !defined(AttrVal($hash->{NAME},'IODev',undef));

    # Default-Excludes
    defineDefaultGlobalExclude($hash);

    # ggf. bestehenden subscriptions kuendigen
    RemoveAllSubscripton($hash);
    #$hash->{subscribe} = [];
    #$hash->{subscribeQos} = {};
    #$hash->{subscribeExpr} = [];

    # tabelle aufbauen, Start (subscriptions erstellen, anpassen, loeschen)
    InitializeDevices($hash);
  
    RemoveInternalTimer($hash);
    if(defined($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}) && ($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL} ne '0')) {
      InternalTimer(gettimeofday()+$hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}, "MQTT::GENERIC_BRIDGE::timerProc", $hash, 0);
    }

    if (isIODevMQTT($hash)) {
      MQTT::client_start($hash); #if defined $hash->{+HELPER}->{+IO_DEV_TYPE} and $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT';
      readingsSingleUpdate($hash,"transmission-state","IO device initialized (mqtt)",1);
    } elsif (isIODevMQTT2($hash)) {
      readingsSingleUpdate($hash,"transmission-state","IO device initialized (mqtt2)",1);
    } else {
      readingsSingleUpdate($hash,"transmission-state","unknown IO device",1);
    }

    $hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 1;

    # senden attr changes at start:
    # im firstinit schleife ueber alle devices im map und bei mode 'A' senden
    # publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, $val);
    # ggf. vorkehrungen treffen, falls nicht connected
    return;
  }
}

# Vom Timer periodisch aufzurufende Methode
sub timerProc {
  my $hash = shift // return;
  my $name = $hash->{NAME};

  # TODO: Resend
  # timerProc=> wenn autoresend an dev-map, dann dev-map nach lasttime durchsuchen

  RemoveInternalTimer($hash);
  if(defined($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}) && ($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL} ne '0')) {
    InternalTimer(gettimeofday()+$hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}, "MQTT::GENERIC_BRIDGE::timerProc", $hash, 0);
  }
  return;
}

# prueft, ob Verbindung zum MQTT-Broker besteht.
# Parameter: Bridge-Hash
sub isConnected {
  my $hash = shift // return 0;
  return MQTT::isConnected($hash->{IODev}) if isIODevMQTT($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT';

  return 1 if isIODevMQTT2($hash); # TODO: check connected #Beta-User: might need review, see https://forum.fhem.de/index.php/topic,115279.msg1130603.html#msg1130603
  # ich weiß nicht, ob das eine gute Idee ist, zu prüfen, evtl. wird FHEM-Standard-writeBuffef für das Senden nach dem Connect selbst sorgen
  # in diesem Fall koenne wir annehmen, dass immer connected ist und keine eigene Warteschlangen verwenden
  # my $iodt = retrieveIODevType($hash);
  # return 0 unless defined $iodt;
  # return 1 if $iodt eq 'MQTT2_SERVER'; # immer 'verbunden'
  # if($iodt eq 'MQTT2_CLIENT') { # Status pruefen
  #   my $iodn = retrieveIODevName($hash);
  #   return 1 if (ReadingsVal($iodn, "state", "") eq "opened");
  #   return 0;
  # }

  return 0;
}

# Berechnet Anzahl der ueberwachten Geraete neu
sub updateDevCount {
  my $hash = shift // return;
  # device count
  my $size = 0;
  for my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
    if($dname ne ":global") {
      $size++;
    }
  }
  $hash->{+HELPER}->{+HS_PROP_NAME_DEVICE_CNT} = $size;
  return readingsSingleUpdate($hash,"device-count",$size,1);
}

# loescht angelegte userattr aus den jeweiligen Devices (oder aus dem global-Device)
# Parameter: 
#   $hash:    Bridge-hash
#   $prefix:  Attribute (publish, subscribe, defaults und alis) mit diesem Prefix werden entfernt
#   $devspec: definiert Geraete, deren userattr bereinigt werden
# Die letzten zwei Parameter sind optinal, fehlen sie, werden werte aus dem Hash genommen.
sub removeOldUserAttr { 
  #my ($hash, $prefix, $devspec, $newDevices) = @_;
  my $hash       = shift // return;
  my $prefix     = shift // $hash->{+HS_PROP_NAME_PREFIX};
  my $devspec    = shift // $hash->{+HS_PROP_NAME_DEVSPEC};
  my $newDevices = shift; #Einleitung passt irgendwie nicht...

  #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] newDevices: ".Dumper($newDevices));

  # Pruefen, on ein weiteres Device (MQTT_GENERIC_BRIDGE) mit dem selben Prefix existiert (waere zwar Quatsch, aber dennoch)
  my @bridges = devspec2array("TYPE=MQTT_GENERIC_BRIDGE");
  my $name = $hash->{NAME};
  for my $dev (@bridges) {
    if($dev ne $name) {
      my $aPrefix = $defs{$dev}->{+HS_PROP_NAME_PREFIX};
      return if ($aPrefix eq $prefix);
    }
  }
  $devspec = 'global' if ($devspec eq '.*');
  # kann spaeter auch delFromDevAttrList Methode genutzt werden
  my @devices = devspec2array($devspec);

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] removeOldUserAttr> devspec: $devspec, array: ".Dumper(@devices));
  for my $dev (@devices) {
    next if grep {$_ eq $dev} @{$newDevices};
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] removeOldUserAttr> delete: from $dev ".$prefix.CTRL_ATTR_NAME_DEFAULTS);
    # O> subs aus fhem.pl nicht nutzen, da diese auch die Steuerungsattribute mit loescht. Vor allem bei global ist das ein Problem
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_DEFAULTS.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_ALIAS.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_PUBLISH.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_SUBSCRIBE.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_IGNORE.":both,incoming,outgoing");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_FORWARD.":all,none");
    # => stattdessen selbst loeschen (nur die 'userattr')
    my $ua = $attr{$dev}{userattr};
    if (defined $ua) {
      my %h = map { ($_ => 1) } split(" ", "$ua");
      #delete $h{$prefix.CTRL_ATTR_NAME_DEFAULTS};
      delete $h{$prefix.CTRL_ATTR_NAME_DEFAULTS.":textField-long"};
      #delete $h{$prefix.CTRL_ATTR_NAME_ALIAS};
      delete $h{$prefix.CTRL_ATTR_NAME_ALIAS.":textField-long"};
      #delete $h{$prefix.CTRL_ATTR_NAME_PUBLISH};
      delete $h{$prefix.CTRL_ATTR_NAME_PUBLISH.":textField-long"};
      #delete $h{$prefix.CTRL_ATTR_NAME_SUBSCRIBE};
      delete $h{$prefix.CTRL_ATTR_NAME_SUBSCRIBE.":textField-long"};
      #delete $h{$prefix.CTRL_ATTR_NAME_IGNORE};
      delete $h{$prefix.CTRL_ATTR_NAME_IGNORE.":both,incoming,outgoing"};
      #delete $h{$prefix.CTRL_ATTR_NAME_FORWARD};
      delete $h{$prefix.CTRL_ATTR_NAME_FORWARD.":all,none"};
      if(!keys %h && defined($attr{$dev}{userattr})) {
        # ganz loeschen, wenn nichts mehr drin
        delete $attr{$dev}{userattr};
      } else {
        $attr{$dev}{userattr} = join(" ", sort keys %h);
      }
    }
  }
  return;                                                      
}

# Prueft, ob der gegebene Zeichenkette einem der zu ueberwachenden Device-Attributennamen entspricht.
sub IsObservedAttribute {
  my $hash  = shift;
  my $aname = shift // return;
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};

  if($aname eq $prefix.CTRL_ATTR_NAME_DEFAULTS) {
    return 1;
  }
  if($aname eq $prefix.CTRL_ATTR_NAME_ALIAS) {
    return 1;
  }
  if($aname eq $prefix.CTRL_ATTR_NAME_PUBLISH) {
    return 1;
  }
  if($aname eq $prefix.CTRL_ATTR_NAME_SUBSCRIBE) {
    return 1;
  }
  if($aname eq $prefix.CTRL_ATTR_NAME_IGNORE) {
    return 1;
  }
  if($aname eq $prefix.CTRL_ATTR_NAME_FORWARD) {
    return 1;
  }

  return;
}

# Internal. Legt Defaultwerte im Map ab. Je nach Schluessel werden die Werte fuer 'pub:', 'sub:' oder beides abgelegt.
# Parameter:
#   $map:     Werte-Map (Ziel)
#   $dev:     Devicename
#   $valMap:  Map mit den Werten (Quelle)
#   $key:     Schluessel. Unter Inhalt aus dem Quellmap unter diesem Schluessel wird in Zielmap kopiert.
sub _takeDefaults { #($$$$) {
  my $map    = shift;
  my $dev    = shift;
  my $valMap = shift;
  my $key    = shift // return;
  my $pr = q{};
  $pr = substr($key, 0, 4) if (length($key)>4);
  if(($pr eq 'sub:') or ($pr eq 'pub:')) {
  #if (defined($valMap->{$key})) {
    # ggf. nicht ueberschreiben (damit nicht undefiniertes VErhalten entsteht,
    # wenn mit und ohne Prefx gleichzeitig angegeben wird. So wird die Definition mit Prefix immer gewinnen)
    $map->{$dev}->{':defaults'}->{$key}=$valMap->{$key} if !defined $map->{$dev}->{':defaults'}->{$key};
    $map->{$dev}->{':defaults'}->{$key}=$valMap->{$key} if !defined $map->{$dev}->{':defaults'}->{$key};
  } else {
    $map->{$dev}->{':defaults'}->{'pub:'.$key}=$valMap->{$key};
    $map->{$dev}->{':defaults'}->{'sub:'.$key}=$valMap->{$key};
  }
  return;
}

# Erstellt Strukturen fuer 'Defaults' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrDefaults { #($$$$) {
  #my($hash, $dev, $map, $attrVal) = @_;
  my $hash    = shift // return;
  my $dev     = shift // carp q[No device name provided!] && return;
  my $map     = shift // carp q[No devMapName provided!]  && return;
  my $attrVal = shift; 
  
  # collect defaults
  delete ($map->{$dev}->{':defaults'});
  return if !defined $attrVal;
  # format: [pub:|sub:]base=ha/wz/ [pub:|sub:]qos=0 [pub:|sub:]retain=0
  my($unnamed, $named) = main::parseParams($attrVal,'\s',' ','='); 
  for my $param (keys %{$named}) {
    # my $pr = substr($param, 0, 4);
    # if($pr eq 'sub:' or $pr eq 'pub:') {
    #   $param = substr($param, 4);
    # }
    _takeDefaults($map, $dev, $named, $param);
  }
  # _takeDefaults($map, $dev, $named, 'base');
  # _takeDefaults($map, $dev, $named, 'qos');
  # _takeDefaults($map, $dev, $named, 'retain');
  # _takeDefaults($map, $dev, $named, 'expression');
  return defined($map->{$dev}->{':defaults'});
}

# Erstellt Strukturen fuer 'Alias' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrAlias { #($$$$) {
  #my($hash, $dev, $map, $attrVal) = @_;
  my $hash    = shift // return;
  my $dev     = shift // carp q[No device name provided!] && return;
  my $map     = shift // carp q[No devMapName provided!]  && return;
  my $attrVal = shift; 
  
  delete ($map->{$dev}->{':alias'});
  return if !defined $attrVal;
  # format [pub:|sub:]<reading>[=<newName>] ...
  my($unnamed, $named) = main::parseParams($attrVal,'\s',' ','='); #main::parseParams($attrVal);
  if(defined($named)){
    for my $param (keys %{$named}) {
      my $val = $named->{$param};
      my($pref,$name) = split(":",$param);
      if(defined($name)) {
        if($pref eq 'pub' or $pref eq 'sub') {
          $map->{$dev}->{':alias'}->{$pref.":".$name}=$val;
        }
      } else {
        $name = $pref;
        # ggf. nicht ueberschreiben (damit nicht undefiniertes Verhalten entsteht, 
        # wenn mit und ohne Prefx gleichzeitig angegeben wird. So wird die Definition mit Prefix immer gewinnen)
        $map->{$dev}->{':alias'}->{"pub:".$name}=$val if !defined $map->{$dev}->{':alias'}->{"pub:".$name};
        $map->{$dev}->{':alias'}->{"sub:".$name}=$val if !defined $map->{$dev}->{':alias'}->{"sub:".$name};
      }
    }
    return defined($map->{$dev}->{':alias'});
  }
  return;
}

# Erstellt Strukturen fuer 'Publish' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
# NB: stopic gibt es beim 'publish' nicht
# ?: internal-topic? - keine Verwendung bis jetzt
sub CreateSingleDeviceTableAttrPublish { #($$$$) {
  #my($hash, $dev, $map, $attrVal) = @_;
  my $hash    = shift // return;
  my $dev     = shift // carp q[No device name provided!] && return;
  my $map     = shift // carp q[No devMapName provided!]  && return;
  my $attrVal = shift; 
  
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrPublish: $dev, $attrVal, ".Dumper($map));
  # collect publish topics
  delete ($map->{$dev}->{':publish'});
  
  return if !defined $attrVal; 
    # format: 
    #   <reading|alias>:topic=<"static topic"|{evaluated (first time only) topic 
    #     (avialable vars: $base, $reading (oringinal name), $name ($reading oder alias))}>
    #   <reading>:qos=0 <reading>:retain=0 ... 
    #  wildcards:
    #   *:qos=0 *:retain=0 ...
    #   *:topic=<{}> wird jedesmal ausgewertet und ggf. ein passendes Eintrag im Map erzeugt
    #   *:topic=# same as *:topic={"$base/$reading"}
    my($unnamed, $named) = main::parseParams($attrVal,'\s',' ','=');
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrPublish: parseParams: ".Dumper($named));
                                                                               return if !defined($named);
      my $autoResend = {};
      for my $param (keys %{$named}) {
        my $val = $named->{$param};
        my($name,$ident) = split(":",$param);
        if(!defined($ident) || !defined($name)) { next; }
        if($ident =~ m{\Atopic|(readings-|a|attr-)topic|qos|retain|expression|resendOnConnect|autoResendInterval\z}x) {

          #($ident eq 'stopic') or ($ident eq 'set-topic') or # stopic nur bei subscribe
          my @nameParts = split m{\|}xms, $name;
          while (@nameParts) {
            my $namePart = shift @nameParts;
            next if $namePart eq '';
            $map->{$dev}->{':publish'}->{$namePart}->{$ident}=$val;

            $map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'R' if $ident eq 'topic' || $ident eq 'readings-topic';
            #$map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'S' if (($ident eq 'stopic') or ($ident eq 'set-topic'));
            $map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'A' if $ident eq 'atopic' || $ident eq 'attr-topic';

            $autoResend->{$namePart} = $val if $ident eq 'autoResendInterval';
          }
        }
      }
      my $size = keys %{$autoResend};
      if($size > 0) {
        $map->{$dev}->{':autoResend'}=$autoResend;
      } else {
        delete $map->{$dev}->{':autoResend'};
      }

  return;
}

# Sucht nach device/reading in der Dev-Map und speichert aktuellen dort den Zeitstempel
sub updatePubTime {
  #my ($hash,$device,$reading) = @_;
  my $hash    = shift // return;
  my $device  = shift // carp q[No device name provided!] && return;
  my $reading = shift // carp q[No reading provided!] && return;
  
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined ($map)) {
    my $dmap = $map->{$device};
    if(defined($dmap)) {
      my $omap = $dmap->{':publish'};
      if(defined($omap)) {
        my $rec = $omap->{$reading};
        if(defined($rec)) {
          $rec->{'last'} = gettimeofday();
        }
      }
    }
  }
  return;
}

# sucht zu den gegebenen device und reading die publish-Eintraege (topic, qos, retain)
# liefert Liste der passenden dev-hashes
# verwendet device-record und beruecksichtigt defaults und globals
# parameter: $hash, device-name, reading-name
sub getDevicePublishRec {
  #my($hash, $dev, $reading) = @_;
  my $hash       = shift // return;
  my $dev        = shift // carp q[No device name provided!] && return;
  my $reading    = shift // carp q[No reading provided!] && return;
  my $ret = [];
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  return $ret unless defined $map;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec: $dev, $reading, ".Dumper($map));
  
  my $globalMap = $map->{':global'} // {};
  my $devMap = $map->{$dev};

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> devmap: ".Dumper($devMap));
  
  for my $key (keys %{$devMap->{':publish'}} ) {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> dev: $key");
    my($keyRName,$keyPostfix) = split("!",$key);
    if($keyRName eq $reading) {
      my $devRec = getDevicePublishRecIntern($hash, $devMap, $globalMap, $dev, $key, $reading, $keyPostfix);
      #$devRec->{'postfix'}=defined($keyPostfix)?$keyPostfix:'';
      push(@$ret, $devRec);
    }
  }
  # wenn keine explizite Readings gefunden wurden, dann noch einmal fragen, damit evtl. vorhandenen '*'-Definitionen zur Geltung kommen
  if(!@$ret) {
    #push(@$ret, getDevicePublishRecIntern($hash, $devMap, $globalMap, $dev, $reading, $reading, undef));
    for my $key (keys %{$devMap->{':publish'}} ) {
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> dev: $key");
      my($keyRName,$keyPostfix) = split("!",$key);
      if($keyRName eq '*') {
        my $devRec = getDevicePublishRecIntern($hash, $devMap, $globalMap, $dev, $key, $reading, $keyPostfix);
        #$devRec->{'postfix'}=defined($keyPostfix)?$keyPostfix:'';
        push(@$ret, $devRec);
      }
    }
  }

  # wenn immer noch keine explizite Readings gefunden wurden, dann noch einmal in globalPublishMap suchen
  if(!@$ret) {
    my $devRec = getDevicePublishRecIntern($hash, $devMap, $globalMap, $dev, $reading, $reading, '');
    #$devRec->{'postfix'}=defined($keyPostfix)?$keyPostfix:'';
    push(@$ret, $devRec) if defined $devRec;
  }

  return $ret;
}

# sucht zu den gegebenen device und reading die publish-Eintraege (topic, qos, retain) 
# in den uebergebenen Maps
# verwendet device-record und beruecksichtigt defaults und globals
# parameter: $hash, map, globalMap, device-name, reading-name
sub getDevicePublishRecIntern {
  my $hash       = shift // return;
  my $devMap     = shift // carp q[No device map provided!] && return;
  my $globalMap  = shift; # optional
  my $dev        = shift // carp q[No device name provided!] && return;
  my $readingKey = shift; #seems to be optional
  my $reading    = shift // carp q[No reading provided!] && return;
  my $postFix    = shift; # may be undef
  
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> hash: ".$hash);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> devmap: ".Dumper($devMap));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> globalmap: ".Dumper($globalMap));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> dev: ".Dumper($dev));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> readingKey: ".Dumper($readingKey));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> reading: ".Dumper($reading));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> params> postFix: ".Dumper($postFix));

  # publish map
  my $publishMap = $devMap->{':publish'};
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> publishMap ".Dumper($publishMap));
  #return undef unless defined $publishMap;
  my $globalPublishMap = $globalMap->{':publish'};

  # reading map
  my $readingMap = $publishMap->{$readingKey} // {};
  my $wildcardReadingMap = $publishMap->{'*'} // {};
  #my $defaultReadingMap = $devMap->{':defaults'} if defined $devMap;
  
  # global reading map
  my $globalReadingMap = undef;
  if (defined $globalPublishMap) {
    $globalReadingMap = $globalPublishMap->{$readingKey} // $globalPublishMap->{$reading};
  }
  my $globalWildcardReadingsMap = $globalPublishMap->{'*'} // {};

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> readingMap ".Dumper($readingMap));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> wildcardReadingMap ".Dumper($wildcardReadingMap));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> global readingMap ".Dumper($globalReadingMap));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] getDevicePublishRec> global wildcardReadingMap ".Dumper($globalWildcardReadingsMap));
  # topic
  my $topic   = $readingMap->{'topic'}                 //
                $wildcardReadingMap->{'topic'}         //
                $globalReadingMap->{'topic'}           //
                $globalWildcardReadingsMap->{'topic'}  // undef;

  # attr-topic
  my $atopic  = $readingMap->{'atopic'}                //
                $wildcardReadingMap->{'atopic'}        //
                $globalReadingMap->{'atopic'}          //
                $globalWildcardReadingsMap->{'atopic'} // undef;

  # qos & retain & expression
  #my($qos, $retain, $expression) = retrieveQosRetainExpression($globalWildcardReadingsMap, $globalReadingMap, $wildcardReadingMap, $readingMap);
  my($qos, $retain, $expression) = retrieveQosRetainExpression($globalMap->{':defaults'}, $globalReadingMap, $globalWildcardReadingsMap, $wildcardReadingMap, $devMap->{':defaults'}, $readingMap);
  
  # wenn kein topic und keine expression definiert sind, kann auch nicht gesendet werden, es muss nichts mehr ausgewertet werden
  return if !defined($topic) && !defined($atopic) && !defined($expression);

  # resendOnConnect Option
  my $resendOnConnect = $readingMap->{'resendOnConnect'}                //
                        $wildcardReadingMap->{'resendOnConnect'}        // 
                        $globalReadingMap->{'resendOnConnect'}          //
                        $globalWildcardReadingsMap->{'resendOnConnect'} // undef;

  # map name
  my $name = $devMap->{':alias'}->{'pub:'.$readingKey}      //
             $devMap->{':alias'}->{'pub:'.$reading}         //
             $globalMap->{':alias'}->{'pub:'.$readingKey}   //
             $globalMap->{':alias'}->{'pub:'.$reading}      //
             $reading;

  # get mode
  my $mode = $readingMap->{'mode'};

  # compute defaults
  my $combined = computeDefaults($hash, 'pub:', $globalMap, $devMap, {'device'=>$dev,'reading'=>$reading,'name'=>$name,'mode'=>$mode,'postfix'=>$postFix});
  # $topic evaluieren (avialable vars: $device (device name), $reading (oringinal name), $name ($reading oder alias, if defined), defaults)
  $combined->{'base'} = '' unless defined $combined->{'base'}; # base leer anlegen wenn nicht definiert

  if(defined($topic) && $topic =~ m{\A\{.*\}\z}x) {
    $topic = _evalValue2($hash->{NAME},$topic,{'topic'=>$topic,'device'=>$dev,'reading'=>$reading,'name'=>$name,'postfix'=>$postFix,%$combined}) if defined $topic;
  }
  if(defined($atopic) && $atopic =~ m{\A\{.*\}\z}x) {
    $atopic = _evalValue2($hash->{NAME},$atopic,{'topic'=>$atopic,'device'=>$dev,'reading'=>$reading,'name'=>$name,'postfix'=>$postFix,%$combined}) if defined $atopic;
  }

  return {'topic'=>$topic,'atopic'=>$atopic,'qos'=>$qos,'retain'=>$retain,
          'expression'=>$expression,'name'=>$name,'mode'=>$mode, 'postfix'=>$postFix,
          'resendOnConnect'=>$resendOnConnect,'.defaultMap'=>$combined};
}

# sucht Qos, Retain, Expression Werte unter Beruecksichtigung von Defaults und Globals
sub retrieveQosRetainExpression { 
  my $globalDefaultReadingMap   = shift;
  my $globalReadingMap          = shift;
  my $wildcardDefaultReadingMap = shift;
  my $wildcardReadingMap        = shift;
  my $defaultReadingMap         = shift;
  my $readingMap                = shift; 
  
  my $qos        = $readingMap->{'qos'}                         //
                   $wildcardReadingMap->{'qos'}                 //
                   $defaultReadingMap->{'pub:qos'}              //
                   $defaultReadingMap->{'qos'}                  //
                   $globalReadingMap->{'qos'}                   //
                   $wildcardDefaultReadingMap->{'qos'}          //
                   $globalDefaultReadingMap->{'pub:qos'}        //
                   $globalDefaultReadingMap->{'qos'}            // 0;
  
  my $retain     = $readingMap->{'retain'}                      //
                   $wildcardReadingMap->{'retain'}              //
                   $defaultReadingMap->{'pub:retain'}           //
                   $defaultReadingMap->{'retain'}               //
                   $globalReadingMap->{'retain'}                //
                   $wildcardDefaultReadingMap->{'retain'}       //
                   $globalDefaultReadingMap->{'pub:retain'}     //
                   $globalDefaultReadingMap->{'retain'}         // 0;

  my $expression = $readingMap->{'expression'}                  //
                   $wildcardReadingMap->{'expression'}          //
                   $defaultReadingMap->{'pub:expression'}       //
                   $defaultReadingMap->{'expression'}           //
                   $globalReadingMap->{'expression'}            //
                   $wildcardDefaultReadingMap->{'expression'}   //
                   $globalDefaultReadingMap->{'pub:expression'} //
                   $globalDefaultReadingMap->{'expression'}     // undef;

  return ($qos, $retain, $expression);
}

# Evaluiert Werte in Default, wenn diese Variable / Perl-Expressions enthalten
sub computeDefaults { 
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] computeDefaults> infoMap: ".Dumper($infoMap));
  my $hash      = shift // return;
  my $modifier  = shift // carp q[No modifier provided!] && return;;
  my $globalMap = shift; #seems not to be mandatory
  my $devMap    = shift; #seems not to be mandatory
  my $infoMap   = shift // {};
  my $mdLng = length($modifier);
  my $defaultCombined={};
  #$infoMap = {} unless defined $infoMap;
  if (defined($globalMap) and defined($globalMap->{':defaults'})) {
    for my $param (keys %{$globalMap->{':defaults'}} ) {
      if(startsWith($param,$modifier)) {
        my $key = substr($param,$mdLng);
        my $val = $globalMap->{':defaults'}->{$param};
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] computeDefaults> global eval: key: $key, val: $val");
        $val = _evalValue2($hash->{NAME},$val,$infoMap);
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] computeDefaults> global eval done: val: $val");
        $defaultCombined->{$key}=$val;
      }
    }
  }
  my $devCombined={};
  if (defined($devMap) and defined($devMap->{':defaults'})) {
    for my $param (keys %{$devMap->{':defaults'}} ) {
      if(startsWith($param,$modifier)) {
        my $key = substr($param,$mdLng);
        my $val = $devMap->{':defaults'}->{$param};
        #$val = _evalValue2($hash->{NAME},$val,$defaultCombined);
        $devCombined->{$key}=$val;
      }
    }
  }
  for my $param (keys %{$devCombined} ) {
    my $val = $devCombined->{$param};
    $devCombined->{$param} = _evalValue2($hash->{NAME},$val,{%$defaultCombined, %$infoMap});
  }
  my $combined = {%$defaultCombined, %$devCombined};
  return $combined;
}

# Ersetzt im $str alle Variable $xxx durch entsprechende Werte aus dem Map {xxx=>wert, xxy=>wert2}
# Ersetzt wird jedoch nur dann, wenn $str mit '{' anfaengt und mit '}' endet.
# Nach dem Ersetzen wird (je $noEval-Wert) Perl-eval durchgefuehrt
sub _evalValue2 {
  my $mod   = shift // return;
  my $str    = shift // carp q[No string to analyze!] && return;
  my $map    = shift;
  my $noEval = shift // 0;
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2: str: $str; map: ".Dumper($map));
  my$ret = $str;
  # TODO : umbauen $str =~ m/^(.*)({.*})(.*)$/;; $1.$2.$3 - ok
  # TODO : Maskierte Klammern unterstuetzen? $str =~ m/^(.*)(\\{.*\\})(.*)({.*})(.*)$/;; $1.$2.$3.$4.$5 - irgendwie so
  #if($str =~ m/^{.*}$/) {
  #if($str =~ m/^(.*)({.*})(.*)$/) {
  if($str =~ m{\A(.*)(\{.*\})(.*)\z}x) { # forum https://forum.fhem.de/index.php/topic,117659.msg1121004.html#msg1121004
    my $s1 = $1 // q{}; #$s1='' unless defined $s1;
    my $s2 = $2 // q{}; #$s2='' unless defined $s2;
    my $s3 = $3 // q{}; #$s3='' unless defined $s3;
    no strict "refs";
    local $@ = undef;
    my $base = q{};
    my $device = q{};
    my $reading = q{};
    my $name = q{};
    #my $room = '';
    if(defined($map)) {
      for my $param (keys %{$map}) {
        
        my $pname = '$'.$param;
        my $val = $map->{$param} // $pname;
        #$val=$pname if !defined $val;
        # Sonderlocken fuer $base, $name, $reading, $device, damit auch xxx:topic={$base} geht (sonst koente nur {"$base"} verwendet werden)
        if($pname eq '$base') {
          $base = $val;
        } elsif ($pname eq '$reading') {
          $reading = $val;
        } elsif ($pname eq '$device') {
          $device = $val;
        } elsif ($pname eq '$name') {
          $name = $val;
        # } elsif ($pname eq '$room') {
        #   $room = $val;
        } else {
          #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> replace2: $ret : $pname => $val");
          #$ret =~ s/\Q$pname\E/$val/g;
          $s2 =~ s{\Q$pname\E}{$val}gx;
          #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> replace2 done: $s2");
      }
    }
    }
    #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2 expr: $s2");
    #$ret = eval($ret) unless $noEval;
    $s2 = eval($s2) if !$noEval; ##no critic qw(eval) 
    #we expressively want user code to be executed! This is added after compile time...
    #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2 done: $s2");
    if ($@) {
      Log3($mod,2,"MQTT_GENERIC_BRIDGE: evalValue: user value ('".$str."'') eval error: ".$@);
      $ret=$s1.''.$s3;
    } else {
      $ret = $s1.$s2.$s3;
    }
    $ret = _evalValue2($mod, $ret, $map, $noEval) if !$noEval;
  }
  return $ret;
}



# sucht zu dem gegebenen (ankommenden) topic das entsprechende device und reading
# Params: $hash, $topic (empfangene topic)
# return: map (device1->{reading}=>reading1, device1->{expression}=>{...}, deviceN->{reading}=>readingM)
sub searchDeviceForTopic {
  #my($hash, $topic) = @_;
  my $hash  = shift // return;
  my $topic = shift // carp q[No topic provided!] && return;
  my $ret = {};
  my $map = $hash->{+HS_TAB_NAME_DEVICES} // return;
  my $globalMap = $map->{':global'};
    for my $dname (keys %{$map}) {
      my $dmap = $map->{$dname}->{':subscribe'};
      for my $rmap (@{$dmap}) {
        my $topicExp = $rmap->{'topicExp'};
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] searchDeviceForTopic: $dname => expr: ".Dumper($topicExp));
        if (defined($topicExp) and $topic =~ $topicExp) {
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] searchDeviceForTopic: match topic: $topic, reading: ".$rmap->{'reading'});
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] searchDeviceForTopic: >>>: \$+{name}: ".$+{name}.", \$+{reading}: ".$+{reading});
          # Check named groups: $+{reading},..
          my $reading = undef;
          my $oReading = $rmap->{'reading'};
          my $fname = $+{name};
          my $nReading; 
          
          if(defined($fname)) {
            if (defined($map->{$dname}->{':alias'})) {
              $nReading = $map->{$dname}->{':alias'}->{'sub:'.$fname};
            }
            if (!defined($nReading) && defined($globalMap) && defined($globalMap->{':alias'})) {
              $nReading = $globalMap->{':alias'}->{'sub:'.$fname};
            }
            $nReading = $fname if !defined $nReading;
          }
          $nReading = $+{reading} if !defined $nReading;
          
          if( !defined($nReading) || $oReading eq $nReading ) {
            $reading = $oReading;
          }
          if($rmap->{'wildcardTarget'}) {
            # $reading = $+{name} unless defined $reading;
            # # Remap name
            # $reading = $+{reading} unless defined $reading;
            $reading = $nReading;
          }
          #$reading = $rmap->{'reading'} unless defined $reading;
          next if !defined $reading;
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] searchDeviceForTopic: match topic: $topic, reading: $reading, nREading: $nReading, oReading: $oReading");
          my $tn = $dname.':'.$reading;
          $ret->{$tn}->{'mode'}=$rmap->{'mode'};
          $ret->{$tn}->{'reading'}=$reading;
          my $device = $+{device} // $dname; # TODO: Pruefen, ob Device zu verwenden ist => wie?
          #$device = $dname unless defined $device;
          $ret->{$tn}->{'device'}=$device;
          $ret->{$tn}->{'expression'}=$rmap->{'expression'};
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] searchDeviceForTopic: deliver: ".Dumper($ret));
        }
      }
    }

  return $ret;
}

# Erstellt RexExp-Definitionen zum Erkennen der ankommenden Topics
# Platzhalter werden entsprechend verarbeitet
sub createRegexpForTopic {
  my $t = shift // return;
  $t =~ s|#$|.\*|x;
  # Zugriff auf benannte captures: $+{reading}
  $t =~ s|(\$reading)|(\?\<reading\>+)|gx;
  $t =~ s|(\$name)|(\?\<name\>+)|gx;
  $t =~ s|(\$device)|(\?\<device\>+)|gx;
  $t =~ s|\$|\\\$|gx;
  $t =~ s|\/\.\*$|.\*|x;
  $t =~ s|\/|\\\/|gx;
  #$t =~ s|(\+)([^+]*$)|(+)$2|;
  $t =~ s|\+|[^\/]+|gx;
  return "^$t\$";
}

# Erstellt Strukturen fuer 'Subscribe' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrSubscribe { #($$$$) {
  #my($hash, $dev, $map, $attrVal) = @_;
  my $hash    = shift // return;
  my $dev     = shift // carp q[No device name provided!] && return;
  my $map     = shift // carp q[No map arg provided!]     && return;
  my $attrVal = shift; 

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: $dev, $attrVal, ".Dumper($map));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: ".Dumper($map));
  # collect subscribe topics
  my $devMap = $map->{$dev};
  my $globalMap = $map->{':global'};
  delete ($devMap->{':subscribe'});
  return if !defined $attrVal;
    # format: 
    #   <reading|alias>:topic="asd/asd"
    #   <set-cmd or * for 'state'>:stopic="asd/asd"
    #   <reading>:topic={"$base/$reading"}
    #   <reading>:qos=0
    #   <reading|alias|set-cmd>:expression={...} (vars: $dev, $reading (oringinal name), $name ($reading oder alias), $value (received value), $topic)
    #  wildcards:
    #   *:qos=0 
    #   *:expression={...}
    #   *:topic={"$base/$reading/xyz"} => topic = "$base/+/xyz"
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: attrVal: ".Dumper($attrVal));
    my($unnamed, $named) = main::parseParams($attrVal,'\s',' ','='); #MQTT::parseParams($attrVal, undef, undef, '=', undef);
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: parseParams: named ".Dumper($named));
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: parseParams: unnamed ".Dumper($unnamed));
    if(defined($named)){
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateSingleDeviceTableAttrSubscribe: ".Dumper($map));
      my $dmap = {};
      for my $param (keys %{$named}) {
        my $val = $named->{$param};
        my($name,$ident) = split m{:}xms, $param;
        if(!defined($ident) || !defined($name)) { next; }

        $ident = 'topic' if $ident eq 'readings-topic';
        #$ident = 'sttopic' if $ident eq 'self-trigger-topic';
        $ident = 'stopic' if $ident eq 'set-topic';
        $ident = 'atopic' if $ident eq 'attr-topic';

        if(($ident eq 'topic') or 
         #($ident eq 'sttopic') or 
          ($ident eq 'stopic') or ($ident eq 'atopic') or 
          ($ident eq 'qos') or ($ident eq 'retain') or 
          ($ident eq 'expression')) {
          my @nameParts = split m{\|}xms, $name;
          for my $namePart (@nameParts) {
            next if($namePart eq '');
            my $rmap = $dmap->{$namePart} // {};
            $rmap->{'reading'}=$namePart;
            $rmap->{'wildcardTarget'} = $namePart =~ m{\A\*}x;
            #$rmap->{'evalTarget'} = $namePart =~ /^{.+}.*$/;
            $rmap->{'dev'}=$dev;
            $rmap->{$ident}=$val;
            if( $ident eq 'topic' || 
             #($ident eq 'sttopic') or
              $ident eq 'stopic' || $ident eq 'atopic') { # -> topic

              $rmap->{'mode'} = 'R';
              #$rmap->{'mode'} = 'T' if $ident eq 'sttopic';
              $rmap->{'mode'} = 'S' if $ident eq 'stopic';
              $rmap->{'mode'} = 'A' if $ident eq 'atopic';

              # my $base=undef;
              # if (defined($devMap->{':defaults'})) {
              #   $base = $devMap->{':defaults'}->{'sub:base'};
              # }
              # if (defined($globalMap) and defined($globalMap->{':defaults'}) and !defined($base)) {
              #   $base = $globalMap->{':defaults'}->{'sub:base'};
              # }
              # $base='' unless defined $base;

              # $base = _evalValue($hash->{NAME},$base,$base,$dev,'$reading','$name');
              
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] sub: old base: $base");

              # $base verwenden => eval
              #my $topic = _evalValue($hash->{NAME},$val,$base,$dev,'$reading','$name');

              my $combined = computeDefaults($hash, 'sub:', $globalMap, $devMap, {'device'=>$dev,'reading'=>'#reading','name'=>'#name','mode'=>$rmap->{'mode'}});
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] sub: Defaults: ".Dumper($combined));
              my $topic;
              $topic = _evalValue2($hash->{NAME},$val,{'device'=>$dev,'reading'=>'#reading','name'=>'#name',%$combined}) if defined $val;
              if(!defined($topic)) {
                Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] subscribe: error while interpret topic: $val");
                
              } else {
              my $old = '#reading';
              my $new = '$reading';
              #$topic =~ s/\Q$old\E/$new/g;
              $topic =~ s{\Q$old\E}{$new}gx;
              $old = '#name';
              $new = '$name';
              #$topic =~ s/\Q$old\E/$new/g;
              $topic =~ s{\Q$old\E}{$new}gx;
                #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] sub: Topic old: $topic");
                #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] sub: Topic new: $topic");

              $rmap->{'topicOrig'} = $val;
              $rmap->{'topicExp'}=createRegexpForTopic($topic);

              $topic =~ s{\$reading}{+}gx;
              $topic =~ s{\$name}{+}gx;
              $topic =~ s{\$device}{+}gx;
              }
              $rmap->{'topic'} = $topic;
            } # <- topic
            $dmap->{$namePart} = $rmap;
          }
        } 
      }
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] >>> CreateSingleDeviceTableAttrSubscribe ".Dumper($dmap));
      my @vals = values %{$dmap};
      $devMap->{':subscribe'}= \@vals;
    }
    $map->{$dev} = $devMap;
  return;
}

# Prueft, ob Geraete keine Definitionen mehr enthalten und entfernt diese ggf. aus der Tabelle
sub deleteEmptyDevices { #($$$) {
  #my ($hash, $map, $devMapName) = @_;
  my $hash       = shift // return;
  my $map        = shift // carp q[No map arg provided!]     && return;
  my $devMapName = shift // carp q[No devMapName provided!]  && return;
  
  return if !defined $map->{$devMapName};

  # Wenn keine Eintraege => Device loeschen
  if(keys %{$map->{$devMapName}} == 0) {
    delete($map->{$devMapName});
  }
  return;
}

# Erstellt alle Strukturen fuer fuer ein bestimmtes Geraet (Default, Alias, Publish, Subscribe).
# Params: Bridge-Hash, Dev-Name , Dev-Map-Name (meist = DevName, kann aber auch ein Pseudegeraet wie ':global' sein),
#         Attr-prefix (idR 'mqtt')
#         Internes Map mit allen Definitionen fuer alle Gerate,
sub CreateSingleDeviceTable { #($$$$$) {
  # my ($hash, $dev, $devMapName, $prefix, $map) = @_;
  my $hash       = shift // return;
  my $dev        = shift // carp q[No device name provided!] && return;
  my $devMapName = shift // carp q[No devMapName provided!]  && return;
  my $prefix     = shift // carp q[No prefix provided!]      && return;
  my $map        = shift // carp q[No map arg provided!]     && return;
  # Divece-Attribute fuer ein bestimmtes Device aus Device-Attributen auslesen
  CreateSingleDeviceTableAttrDefaults($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_DEFAULTS, undef));
  CreateSingleDeviceTableAttrAlias($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_ALIAS, undef)); 
  CreateSingleDeviceTableAttrPublish($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_PUBLISH, undef));
  CreateSingleDeviceTableAttrSubscribe($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_SUBSCRIBE, undef));
  return deleteEmptyDevices($hash, $map, $devMapName);
}

# Geraet-Infos neu einlesen
sub _RefreshDeviceTable { 
  my $hash       = shift // return;
  my $dev        = shift // carp q[No device name provided!] && return;
  my $devMapName = shift // carp q[No devMapName provided!]  && return;
  my $prefix     = shift // carp q[No prefix provided!]      && return;
  my $attrName   = shift; 
  my $attrVal    = shift; 
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] _RefreshDeviceTable: $dev, $devMapName, $prefix, $attrName, $attrVal");
  # Attribute zu dem angegeben Geraet neu erfassen
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined($attrName)) {
    # ... entweder fuer bestimmte Attribute ...
    CreateSingleDeviceTableAttrDefaults($hash, $devMapName, $map, $attrVal) if($attrName eq $prefix.CTRL_ATTR_NAME_DEFAULTS);
    CreateSingleDeviceTableAttrAlias($hash, $devMapName, $map, $attrVal) if($attrName eq $prefix.CTRL_ATTR_NAME_ALIAS); 
    CreateSingleDeviceTableAttrPublish($hash, $devMapName, $map, $attrVal) if($attrName eq $prefix.CTRL_ATTR_NAME_PUBLISH);
    CreateSingleDeviceTableAttrSubscribe($hash, $devMapName, $map, $attrVal) if($attrName eq $prefix.CTRL_ATTR_NAME_SUBSCRIBE);
  } else {
    # ... oder gleich fuer alle (dann aus Device Attributes gelesen)
    CreateSingleDeviceTable($hash, $dev, $devMapName, $prefix, $map);
  }
  deleteEmptyDevices($hash, $map, $devMapName) unless defined $attrVal;

  return UpdateSubscriptionsSingleDevice($hash, $dev);
}

# Geraet-Infos neu einlesen
sub RefreshDeviceTable { 
  my $hash     = shift // return;
  my $dev      = shift // carp q[No device name provided!] && return;
  my $attrName = shift;
  my $attrVal  = shift;
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  return _RefreshDeviceTable($hash, $dev, $dev, $prefix, $attrName, $attrVal);
}

sub RefreshGlobalTableAll {
  my $hash = shift // return;
  my $name = $hash->{NAME};
  RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS, undef));
  RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS, undef));
  return RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH, undef));
  #RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_SUBSCRIBE, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_SUBSCRIBE, undef));
}

# GlobalTable-Infos neu einlesen fuer einen bestimmten Attribut
sub RefreshGlobalTable {
  my $hash     = shift // return;
  my $attrName = shift // carp q[No attribute name];
  my $attrVal  = shift // carp q[No attribute value]  && return;
  
  my $prefix = CTRL_ATTR_NAME_GLOBAL_PREFIX;
  return _RefreshDeviceTable($hash, $hash->{NAME}, ':global', $prefix, $attrName, $attrVal);
}

# Geraet umbenennen, wird aufgerufen, wenn ein Geraet in FHEM umbenannt wird
sub RenameDeviceInTable {
  my $hash   = shift // return;
  my $dev    = shift // carp q[No device name provided!] && return;
  my $devNew = shift // carp q[No new device name provided!] && return;
  
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  
  return if !defined($map->{$dev});
  
    delete($map->{$dev});
    my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
    CreateSingleDeviceTable($hash, $devNew, $devNew, $prefix, $map);
  return UpdateSubscriptionsSingleDevice($hash, $devNew);
   
}

# Geraet loeschen (geloescht in FHEM)
sub DeleteDeviceInTable {
  my $hash = shift // return;
  my $dev  = shift // carp q[No device name provided!] && return;
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  
  return if !defined($map->{$dev});
    delete($map->{$dev});
  return UpdateSubscriptions($hash);
}

# alle zu ueberwachende Geraete durchsuchen und relevanter Informationen einlesen
sub CreateDevicesTable {
  my $hash = shift // return;
  # alle zu ueberwachende Geraete durchgehen und Attribute erfassen
  my $map={};
  $hash->{+HS_TAB_NAME_DEVICES} = $map;
  RefreshGlobalTableAll($hash);
  $map = $hash->{+HS_TAB_NAME_DEVICES};

  my @devices = devspec2array($hash->{+HS_PROP_NAME_DEVSPEC});
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateDevicesTable: ".Dumper(@devices));
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  for my $dev (@devices) {
    if($dev ne $hash->{NAME}) {
      Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] CreateDevicesTable for ".$dev);
      CreateSingleDeviceTable($hash, $dev, $dev, $prefix, $map); 
    }
  }

  # crerate global defaults table
  CreateSingleDeviceTable($hash, $hash->{NAME}, ":global", CTRL_ATTR_NAME_GLOBAL_PREFIX, $map);

  $hash->{+HS_TAB_NAME_DEVICES} = $map;
  return UpdateSubscriptions($hash);
  #$hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 1;
}

# Ueberbleibsel eines Optimierungsversuchs
sub UpdateSubscriptionsSingleDevice {
  my $hash = shift // return;
  # Liste der Geraete mit der Liste der Subscriptions abgleichen
  # neue Subscriptions bei Bedarf anlegen und/oder ueberfluessige loeschen
  # fuer Einzeldevices vermutlich eher schwer, erstmal komplet updaten
  return UpdateSubscriptions($hash);
}

# Alle MQTT-Subscriptions erneuern
sub UpdateSubscriptions {
  my $hash = shift // return;

  updateDevCount($hash);

  #return unless isIODevMQTT($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';
  # TODO: MQTT2 subscriptions

  my $topicMap = {};
  my $gmap = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined($gmap)) {
    for my $dname (keys %{$gmap}) {
      my $smap = $gmap->{$dname}->{':subscribe'};
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: smap = ".Dumper($gmap->{$dname}));
      if(defined($smap)) {
        for my $rmap (@{$smap}) {
          my $topic = $rmap->{'topic'};
          $topicMap->{$topic}->{'qos'}=$rmap->{'qos'} if defined $topic;
        }
      }
    }
  }

  unless (%{$topicMap}) {
    RemoveAllSubscripton($hash);
    return;
  }

  my @topics = keys %{$topicMap};
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: topics = ".Dumper(@topics));
  my @new=();
  my @remove=();
  for my $topic (@topics) {
    next if ($topic eq "");
    push @new,$topic unless grep {$_ eq $topic} @{$hash->{subscribe}};
  }
  for my $topic (@{$hash->{subscribe}}) {
    next if ($topic eq "");
    push @remove,$topic unless grep {$_ eq $topic} @topics;
  }

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: remove = ".Dumper(@remove));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: new = ".Dumper(@new));

  if(isIODevMQTT($hash)) {
    for my $topic (@remove) {
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: unsubscribe: topic = ".Dumper($topic));
      client_unsubscribe_topic($hash,$topic);
    }
    for my $topic (@new) {
      my $qos = $topicMap->{$topic}->{'qos'};    # TODO: Default lesen
      $qos = 0 unless defined $qos;
      my $retain = 0; # not supported
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] UpdateSubscriptions: subscribe: topic = ".Dumper($topic).", qos = ".Dumper($qos).", retain = ".Dumper($retain));
      client_subscribe_topic($hash,$topic,$qos,$retain) ;
    }
  }

  #if(isIODevMQTT2($hash)) {
  if(isIODevMQTT2_CLIENT($hash)) {
    # MQTT2 Subscriptions
    IOWrite($hash, "subscriptions", join(" ", @new));
  }
  return;
}

# Alle MQTT-Subscription erntfernen
sub RemoveAllSubscripton {
  my $hash = shift // return;

  #if(isIODevMQTT($hash)) {
  if(isIODevMQTT2_CLIENT($hash)) {
    # MQTT2 Subscriptions => per default alles
    IOWrite($hash, "subscriptions", "#");
  }

  if(isIODevMQTT($hash)) {
    # alle Subscription kuendigen (beim undefine)  
    if (defined($hash->{subscribe}) and (@{$hash->{subscribe}})) {
      my $msgid = send_unsubscribe($hash->{IODev},
        topics => [@{$hash->{subscribe}}],
      );
      $hash->{message_ids}->{$msgid}++;
    }
    $hash->{subscribe}=[];
    $hash->{subscribeExpr}=[];
    $hash->{subscribeQos}={};
  }
  return;
}

sub InitializeDevices {
  my $hash = shift // return;
  # alles neu aufbauen
  # Deviceliste neu aufbauen, ggf., alte subscription kuendigen, neue abonieren
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] ------------ InitializeDevices --------------");
  return CreateDevicesTable($hash);
  #UpdateSubscriptions($hash);
}

# Falls noetig, Geraete initialisieren
sub CheckInitialization {
  my $hash = shift // return;
  # Pruefen, on interne Strukturen initialisiert sind
  return if $hash->{+HELPER}->{+HS_FLAG_INITIALIZED};
  return InitializeDevices($hash);
}

# Zusaetzliche Attribute im Debug-Modus
my %getsDebug = (
  "debugInfo" => "",
  "debugReinit" => "",
  "debugShowPubRec" => ""
);

# Routine fuer FHEM Get-Commando
sub Get { 
  my $hash    = shift // return;
  my $name    = shift;
  my $command = shift // return "Need at least one parameters";
  my $args    = shift;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] get CL: ".Dumper($hash->{CL}));
  #return "Need at least one parameters" unless (defined $command);
  unless (defined($gets{$command}) or (isDebug($hash) && defined($getsDebug{$command}))) {
    my $rstr="Unknown argument $command, choose one of";
    for my $vname (keys %gets) {
      $rstr.=" $vname";
      my $vval=$gets{$vname};
      $rstr.=":$vval" if $vval;
    }
    if (isDebug($hash)) {
      $rstr.=" debugInfo:noArg debugReinit:noArg";
      $rstr.=" debugShowPubRec:";
      for my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        for my $rname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':publish'}}) {
          $rstr.= $dname.'>'.$rname.',';
        }
        $rstr.= $dname.'>unknownReading,';
      }
      $rstr.= 'unknownDevice>unknownReading';
    }
    return $rstr;
  }
  
  my $clientIsWeb = 0;
  if(defined($hash->{CL})) {
    my $clType = $hash->{CL}->{TYPE};
    $clientIsWeb = 1 if (defined($clType) and ($clType eq 'FHEMWEB'));
  }

  #COMMAND_HANDLER: {
  if ($command eq "debugInfo" and isDebug($hash)) {
      my $debugInfo = "initialized: ".$hash->{+HELPER}->{+HS_FLAG_INITIALIZED}."\n\n";
      $debugInfo.= "device data records: ".Dumper($hash->{+HS_TAB_NAME_DEVICES})."\n\n";
      $debugInfo.= "subscriptionTab: ".Dumper($hash->{+HS_TAB_NAME_SUBSCRIBE})."\n\n";
      $debugInfo.= "subscription helper array: ".Dumper($hash->{subscribe})."\n\n";

      # Exclude tables
      $debugInfo.= "exclude type map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE})."\n\n";
      $debugInfo.= "exclude reading map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING})."\n\n";
      $debugInfo.= "exclude device map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES})."\n\n";

      $debugInfo =~ s{<}{&lt;}gx;
      $debugInfo =~ s{>}{&gt;}gx;

      return $debugInfo;
    }
    
    if ($command eq "version") {
      return $VERSION;
    }
    if ($command eq "debugReinit" and isDebug($hash)) {
      InitializeDevices($hash);
      return;
    };
    if ($command eq "debugShowPubRec") {
      my($dev,$reading) = split m{>}xms, $args;
      return "PubRec: $dev:$reading = ".Dumper(getDevicePublishRec($hash, $dev, $reading));
    }
    if ($command eq "devlist") {
      my $res= q{};
      for my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        if($dname ne ":global") {
          if($args) {
            next if $dname !~ m{\A$args\z}x;
          }
          $res.= "${dname}\n";
        }
      }
      return "no devices found" if $res eq '';
      return $res;
    }
    if ($command eq "devinfo") {
      return getDevInfo($hash,$args);;
    }
    if ($command eq "refreshUserAttr") {
      return refreshUserAttr($hash);
    }

  return;
}

sub getDevInfo {
  my $hash = shift // return;
  my $args = shift;
  my $res = q{};
  for my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        if($dname ne ":global") {
          if($args) {
        next if $dname !~ m{\A$args\z}x;
          }
          $res.=$dname."\n";
          $res.="  publish:\n";
      for my $rname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':publish'}}) {
            my $pubRecList = getDevicePublishRec($hash, $dname, $rname);
            #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> getDevInfo ($hash, $dname, $rname)".Dumper($pubRecList));
        next if !defined($pubRecList);
        for my $pubRec (@$pubRecList) {
          next if !defined($pubRec);
              my $expression = $pubRec->{'expression'};
              my $mode =  $pubRec->{'mode'};
             $mode='E' if(defined($expression) && !defined($mode));
          my $topic = 'undefined';
              if($mode eq 'R') {
                $topic = $pubRec->{'topic'};
              } elsif($mode eq 'A') {
                $topic = $pubRec->{'atopic'};
              } elsif($mode eq 'E') {
                $topic = '[expression]';
              } else {
                $topic = '!unexpected mode!';
              }
              my $qos = $pubRec->{'qos'};
              my $retain = $pubRec->{'retain'};
                  my $postFix = $pubRec->{'postfix'};
                  my $dispName = $rname;
                  if(defined($postFix) and ($postFix ne '')) {$dispName.='!'.$postFix;}
                  $res.= sprintf('    %-16s => %s',  $dispName, $topic);
              $res.= " (";
              $res.= "mode: $mode";
              $res.= "; qos: $qos";
              $res.= "; retain" if ($retain ne "0");
              $res.= ")\n";
              $res.= "                     exp: $expression\n" if defined ($expression);
            }
          }
          $res.="  subscribe:\n";
          my @resa;
      for my $subRec (@{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':subscribe'}}) {
            my $qos = $subRec->{'qos'};
            my $mode = $subRec->{'mode'};
            my $expression = $subRec->{'expression'};
        my $topic = $subRec->{'topic'} // '---';
        my $rest= sprintf('    %-16s <= %s', $subRec->{'reading'}, $topic);
            $rest.= " (mode: $mode";
            $rest.= "; qos: $qos" if defined ($qos);
            $rest.= ")\n";
            $rest.= "                     exp: $expression\n" if defined ($expression);
            push (@resa, $rest);
          }
          $res.=join('', sort @resa);
        }
        $res.= "\n";
      }
  $res = "no devices found" if $res eq '';
      return $res;
}

sub Set {
  my ($hash, @args) = @_;
  return AttrTemplate_Set($hash,'',@args);
}

# Routine fuer FHEM Notify
sub Notify {
  my $hash = shift // return;
  my $dev  = shift // carp q[No device hash provided!] && return;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] notify for ".$dev->{NAME}." ".Dumper(@{$dev->{CHANGED}})) if $dev->{TYPE} ne 'MQTT_GENERIC_BRIDGE';
  if( $dev->{NAME} eq "global" ) {
    #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] notify for global ".Dumper(@{$dev->{CHANGED}}));
    if( grep { m{\A(INITIALIZED|REREADCFG)\z}x } @{$dev->{CHANGED}}  ) {
      # FHEM (re)Start
      firstInit($hash);
    }
    
    # Aenderungen der Steuerattributen in den ueberwachten Geraeten tracken
    my $max = int(@{$dev->{CHANGED}});
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = q{} if(!defined($s));
      # tab, CR, LF durch spaces ersetzen
      $s =~ s{[\r\n\t]}{ }gx;
      #$s =~ s/ [ ]+/ /g;
      if($s =~ m{\ARENAMED\s+([^ ]*)\s+([^ ]*)\z}x) {
        # Device renamed
        my ($old, $new) = ($1, $2);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Device renamed: $old => $new");
        # wenn ein ueberwachtes device, tabelle korrigieren
        RenameDeviceInTable($hash, $old, $new);
        next;
      } 
      if($s =~ m{\ADELETED\s+([^ ]*)\z}x) {
        #elsif($s =~ m/^DELETED ([^ ]*)$/) {
        # Device deleted
        my ($name) = ($1);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Device deleted: $name");
        # wenn ein ueberwachtes device, tabelle korrigieren
        DeleteDeviceInTable($hash, $name);
        next;
      } 
      if($s =~ m{\AATTR\s+([^ ]*)\s+([^ ]*)\s+(.*)\z}x) {
        #elsif($s =~ m/^ATTR ([^ ]*) ([^ ]*) (.*)$/) {
        # Attribut created or changed
        my ($sdev, $attrName, $val) = ($1, $2, $3);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr created/changed: $sdev : $attrName = $val");
        # wenn ein ueberwachtes device und attr bzw. steuer.attr, tabelle korrigieren
        if(IsObservedAttribute($hash,$attrName)) {
          #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr created/changed: observed attr: $attrName = $val");
          RefreshDeviceTable($hash, $sdev, $attrName, $val);
        } else {
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr created/changed: non observed attr = $val");
          # check/ publish atopic => val
          publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, $val);
        }
        next;
      } 
      if($s =~ m{\ADELETEATTR\s+([^ ]*)\s+([^ ]*)\z}x) {
        #elsif($s =~ m/^DELETEATTR ([^ ]*) ([^ ]*)$/) {
        # Attribut deleted
        my ($sdev, $attrName) = ($1, $2);
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr deleted: $sdev : $attrName");
        # wenn ein ueberwachtes device und attr bzw. steuer.attr, tabelle korrigieren
        if(IsObservedAttribute($hash,$attrName)) {
          Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr deleted: observed attr: $attrName");
          RefreshDeviceTable($hash, $sdev, $attrName, undef);
        } else {
          # check/ publish atopic => null
          publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, undef);
        }
        next;
      }
    }
    return;
  }

  return checkPublishDeviceReadingsUpdates($hash, $dev);
}

# Pruefen, ob in dem Device Readings-Aenderungen vorliegen, die gepublished werden sollen 
sub checkPublishDeviceReadingsUpdates {
  my $hash = shift // return;
  my $dev  = shift // carp q[No monitored device hash provided!] && return;

  # # pruefen, ob die Aenderung von der Bridge selbst getriggert wurde
  # # es ist der Readingsname drin, die Pruefung wird jedoch derzeit nicht vorgenommen, da nur ein Reading in CHANGE drin sein kann
  # # ansonsten muesste readings in CHANGE mit dem Wert vergliechen werden und nur fuer gleiche nicht weiter senden => TODO
  # my $triggeredReading = $dev->{'.mqttGenericBridge_triggeredReading'};
  # if(defined $triggeredReading) {
  #   delete $dev->{'.mqttGenericBridge_triggeredReading'};
  #   #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify [mqttGenericBridge_triggeredReading]=>".$triggeredReading);
  #   return;
  # }

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] checkPublishDeviceReadingsUpdates: ".$dev->{NAME}." : ".Dumper(@{$dev->{CHANGED}}))  if $dev->{TYPE} ne 'MQTT_GENERIC_BRIDGE';

  # nicht waehrend FHEM startet
  return if !$init_done ;

  # nicht, wenn deaktivert
  return '' if(::IsDisabled($hash->{NAME}));
  
  #are we at the end of a bulk update?
  if ($dev->{'.mqttGenericBridge_triggeredBulk'}) {
    delete $dev->{'.mqttGenericBridge_triggeredReading'};
    delete $dev->{'.mqttGenericBridge_triggeredReading_val'};  
    delete $dev->{'.mqttGenericBridge_triggeredBulk'};  
    return;  
  }

  #CheckInitialization($hash);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] checkPublishDeviceReadingsUpdates ------------------------ ");
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] checkPublishDeviceReadingsUpdates: ".$dev->{NAME}." : ".Dumper(@{$dev->{CHANGED}}))  if $dev->{TYPE} ne 'MQTT_GENERIC_BRIDGE';

  # Pruefen, ob ein ueberwachtes Geraet vorliegt 
  my $devName = $dev->{NAME}; 
  my $devDataTab = $hash->{+HS_TAB_NAME_DEVICES}; # Geraetetabelle
  return if !defined $devDataTab; # not initialized now or internal error
  my $devDataRecord = $devDataTab->{$devName}; # 
  if (!defined($devDataRecord)) {
    # Pruefen, ob ggf. Default map existiert.
    my $globalDataRecord = $devDataTab->{':global'};
    return '' if !defined $globalDataRecord;
    my $globalPublishMap = $globalDataRecord->{':publish'};
    #return '' if !defined $globalPublishMap;
    #my $size = int(keys %{$globalPublishMap});
    #return '' unless ($size>0);
    return '' if !defined $globalPublishMap || !(%{$globalPublishMap});
  }

  for my $event (@{deviceEvents($dev,1)}) {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify for $dev->{NAME} event: $event STATE: $dev->{STATE} ".Dumper($dev));
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify for $dev->{NAME} event: $event STATE: $dev->{STATE}");
    #$event =~ /^([^:]+)(:\s)?(.*)$/sm; # Schalter /sm ...
    $event =~ m{\A(?<dev>[^:]+)(?<devr>:\s)?(?<devrv>.*)\z}smx; # Schalter /sm ist wichtig! Sonst wir bei mehrzeiligen Texten Ende nicht korrekt erkannt. s. https://perldoc.perl.org/perlretut.html#Using-regular-expressions-in-Perl 
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] event: $event, '".((defined $1) ? $1 : "-undef-")."', '".((defined $3) ? $3 : "-undef-")."'") if $dev->{TYPE} ne 'MQTT_GENERIC_BRIDGE';
    #my $devreading = $1;
    #my $devval = $3;
    my $devreading = $+{dev};
    my $devval = $+{devrv};


    # Sonderlocke fuer 'state' in einigen Faellen: z.B. bei ReadingsProxy kommt in CHANGEDWITHSTATE nichts an, und in CHANGE, wie gehabt, z.B. 'off'
    if(!$+{devr}) {
      #$devval = $devreading;
      $devval = $event;
      $devreading = 'state';
    }

    if(defined($devreading) && defined($devval)) {
    #Log3($hash->{NAME},1,">MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] event: $event, '".((defined $devreading) ? $devreading : "-undef-")."', '".((defined $devval) ? $devval : "-undef-")."'");
      # wenn ueberwachtes device and reading
      # pruefen, ob die Aenderung von der Bridge selbst getriggert wurde   TODO TEST
      my $triggeredReading = $dev->{'.mqttGenericBridge_triggeredReading'};
      my $triggeredReadingVal = $dev->{'.mqttGenericBridge_triggeredReading_val'};
      #if(defined($triggeredReading)) {
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify [mqttGenericBridge_triggeredReading]=>".$triggeredReading."=".$triggeredReadingVal." changed reading: ".$devreading);
      #}
      # Auch Wert vergleichen
      if(!defined($triggeredReading) || $devreading ne $triggeredReading || $devval ne $triggeredReadingVal) {
        if(defined($triggeredReading) && $devreading eq $triggeredReading) {
          # Wenn Name passt, aber der Wert veraendert wurde, dann einmal senden und den gesendeten Wert merken
          # TODO: Besser in einer Tabelle (name=value) fuehren (fuer jedes einzelne Reading) und bei match enizeln entfernen 
          #       => damit verhindert, dass wert verloren geht, wenn eine endere REading dazwischenkommt
          $dev->{'.mqttGenericBridge_triggeredReading_val'} = $devval;
        }
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify publishDeviceUpdate: $dev, 'R', $devreading, $devval");
      publishDeviceUpdate($hash, $dev, 'R', $devreading, $devval);
      } else {
        delete $dev->{'.mqttGenericBridge_triggeredReading'};
        delete $dev->{'.mqttGenericBridge_triggeredReading_val'};
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] Notify [mqttGenericBridge_triggeredReading]=>".$triggeredReading." (ignore/delete)");
      }
    }
  }
  return;
}

# Definiert Liste der auszuschliessenden Type/Readings-Kombinationen.
#   Parameter:
#     $hash: HASH
#     $valueType: Werteliste im Textformat fuer TYPE:readings Excludes (getrennt durch Leerzeichen).
#       Ein einzelner Wert bedeutet, dass ein Geraetetyp mit diesem Namen komplett ignoriert wird (also fuer alle seine Readings und jede Richtung).
#       Durch ein Doppelpunkt getrennte Paare werden als Type:Reading interptretiert. 
#       Das Bedeutet, dass an dem gegebenen Type die genannte Reading nicht uebertragen wird.
#       Ein Stern anstatt Type oder auch Reading bedeutet, dass alle Readings eines Geretaetyps 
#       bzw. genannte Readings an jedem Geraetetyp ignoriert werden.
#       Zusaetzlich kann auch die Richtung optional angegeben werden (pub oder sub). Dann gilt die Ausnahme entsprechend nur fuers Senden oder nur fuer Empfang.
# TEST: {Dumper(MQTT::GENERIC_BRIDGE::defineGlobalTypeExclude($defs{'mqttGenericBridge'},'sub:type:reading pub:*:reading2 sub:*:* test'))}
sub defineGlobalTypeExclude { 
  my $hash = shift // return;
  my $valueType = shift // DEFAULT_GLOBAL_TYPE_EXCLUDES;
  
  $valueType.= ' '.DEFAULT_GLOBAL_TYPE_EXCLUDES if $valueType ne DEFAULT_GLOBAL_TYPE_EXCLUDES;
  
  #my ($hash, $valueType) = @_;
  #$valueType = AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE, DEFAULT_GLOBAL_TYPE_EXCLUDES) unless defined $valueType;
  #$valueType = DEFAULT_GLOBAL_TYPE_EXCLUDES unless defined $valueType;
  #$valueType.= ' '.DEFAULT_GLOBAL_TYPE_EXCLUDES if defined $valueType;
  #$main::attr{$hash->{NAME}}{+CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE} = $valueType;
  # HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE und HS_PROP_NAME_GLOBAL_EXCLUDES_READING

  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING} = {};
  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE} = {};

  # my @list = split("[ \t][ \t]*", $valueType);
  # foreach (@list) {
  #   next if($_ eq "");
  #   my($type, $reading) = split(/:/, $_);
  #   $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING}->{$reading}=1 if (defined($reading) and ($type eq '*'));
  #   $reading='*' unless defined $reading;
  #   $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE}->{$type}=$reading if($type ne '*');
  # }


  my($unnamed, $named) = main::parseParams($valueType,'\s',' ','=');
  for my $val (@$unnamed) {
    next if($val eq '');
    my($dir, $type, $reading) = split m{:}xms, $val;
    if (!defined $reading && $dir ne 'pub' && $dir ne 'sub') {
      $reading=$type;
      $type=$dir;
      $dir=undef;
    }
    next if($type eq '');
    $reading = '*' if !defined $reading;
    $reading = '*' if $reading eq '';
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] defineGlobalTypeExclude: dir, type, reading: ".Dumper(($dir, $type, $reading)));
    if (!defined $dir) {
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING}->{'pub'}->{$reading}=1 if (defined($reading) and ($type eq '*'));
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE}->{'pub'}->{$type}=$reading if($type ne '*');
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING}->{'sub'}->{$reading}=1 if (defined($reading) and ($type eq '*'));
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE}->{'sub'}->{$type}=$reading if($type ne '*');
    } elsif (($dir eq 'pub') or ($dir eq 'sub')) {
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING}->{$dir}->{$reading}=1 if (defined($reading) and ($type eq '*'));
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE}->{$dir}->{$type}=$reading if($type ne '*');
    }

  }
  return ($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING}, $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE});
}

# Definiert Liste der auszuschliessenden DeviceName/Readings-Kombinationen.
#   Parameter:
#     $hash: HASH
#     $valueName: Werteliste im Textformat fuer [pub:|sub:]DeviceName:reading Excludes (getrennt durch Leerzeichen).
#       Ein einzelner Wert bedeutet, dass ein Geraet mit diesem Namen komplett ignoriert wird (also fuer alle seine Readings und jede Richtung).
#       Durch ein Doppelpunkt getrennte Paare werden als DeviceName:Reading interptretiert. 
#       Das Bedeutet, dass an dem gegebenen Geraet die genannte Readings nicht uebertragen wird.
#       Ein Stern anstatt Reading bedeutet, dass alle Readings eines Geraets ignoriert werden.
#       Ein Stern anstatt des Geraetenamens ist nicht erlaubt (benutzen Sie in diesem Fall GlobalTypeExclude).
#       Zusaetzlich kann auch die Richtung optional angegeben werden (pub oder sub). Dann gilt die Ausnahme entsprechend nur fuers Senden oder nur fuer Empfang.
# TEST {Dumper(MQTT::GENERIC_BRIDGE::defineGlobalDevExclude($defs{'mqttGenericBridge'},'sub:dev1:reading1 dev2:reading2 dev3 pub:a: *:* test'))}
sub defineGlobalDevExclude { 
  my $hash = shift // return;
  my $valueName = shift // DEFAULT_GLOBAL_DEV_EXCLUDES;
  #$valueName = DEFAULT_GLOBAL_DEV_EXCLUDES unless defined $valueName;
  #$valueName.= ' '.DEFAULT_GLOBAL_DEV_EXCLUDES if defined $valueName;
  #Beta-User: Logikfehler? Wenn, dann müßte man die beiden vorangehenden Zeilen umdrehen, oder? Oder so:
  $valueName.= ' '.DEFAULT_GLOBAL_DEV_EXCLUDES if $valueName ne DEFAULT_GLOBAL_DEV_EXCLUDES;
  
  # HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES

  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}={};

  # my @list = split("[ \t][ \t]*", $valueName);
  # foreach (@list) {
  #   next if($_ eq "");
  #   my($dev, $reading) = split(/:/, $_);
  #   $reading='*' unless defined $reading;
  #   $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}->{$dev}=$reading if($dev ne '*');
  # }

  my($unnamed, $named) = main::parseParams($valueName,'\s',' ','=');
  for my $val (@$unnamed) {
    next if($val eq '');
    my($dir, $dev, $reading) = split m{:}xms , $val;
    if (!defined $reading && $dir ne 'pub' && $dir ne 'sub') {
      $reading=$dev;
      $dev=$dir;
      $dir=undef;
    }
    next if($dev eq '');
    $reading = '*' if !defined $reading;
    $reading = '*' if $reading eq '';
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] defineGlobalDevExclude: dir, dev, reading: ".Dumper(($dir, $dev, $reading)));
    if (!defined $dir) {
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}->{'pub'}->{$dev}=$reading  if($dev ne '*');
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}->{'sub'}->{$dev}=$reading  if($dev ne '*');
    } elsif (($dir eq 'pub') or ($dir eq 'sub')) {
      $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}->{$dir}->{$dev}=$reading if($dev ne '*');
    }

  }
  return $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES};
}

# Setzt Liste der auszuschliessenden Type/Readings-Kombinationenb auf Defaultwerte zurueck (also falls Attribut nicht definiert ist).
sub defineDefaultGlobalExclude {
  my $hash = shift // return;
  defineGlobalTypeExclude($hash, AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE, DEFAULT_GLOBAL_TYPE_EXCLUDES));
  return defineGlobalDevExclude($hash, AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE, DEFAULT_GLOBAL_DEV_EXCLUDES));
}

# Prueft, ob Type/Reading- oder Geraete/Reading-Kombination von der Uebertragung ausgeschlossen werden soll, 
# oder im Geraet Ignore-Attribut gesetzt ist.
#   Parameter:
#     $hash:    HASH
#     $type:    Geraetetyp
#     $devName: Geraetename
#     $reading: Reading
sub isTypeDevReadingExcluded { 
  my $hash      = shift // return;
  my $direction = shift // carp q[No direction provided!]   && return;
  my $type      = shift // carp q[No device type provided!] && return;
  my $devName   = shift // carp q[No device name provided!] && return;
  my $reading   = shift // carp q[No reading provided!]     && return;

  # pruefen, ob im Geraet ignore steht
  my $devDisable = $attr{$devName}{$hash->{+HS_PROP_NAME_PREFIX}.CTRL_ATTR_NAME_IGNORE};
  $devDisable = '0' unless defined $devDisable;
  return 1 if $devDisable eq 'both';
  return 1 if (($direction eq 'pub') and ($devDisable eq 'outgoing'));
  return 1 if (($direction eq 'sub') and ($devDisable eq 'incoming'));

  # Exclude tables
  my $gExcludesTypeMap = $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE};
  $gExcludesTypeMap = $gExcludesTypeMap->{$direction} if defined $gExcludesTypeMap;
  my $gExcludesReadingMap = $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING};
  $gExcludesReadingMap = $gExcludesReadingMap->{$direction} if defined $gExcludesReadingMap;
  my $gExcludesDevMap = $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES};
  $gExcludesDevMap = $gExcludesDevMap->{$direction} if defined $gExcludesDevMap;

  # readings
  return 1 if (defined($gExcludesReadingMap) and ($gExcludesReadingMap->{$reading}));

  # types
  if (defined $gExcludesTypeMap) {
    my $exType=$gExcludesTypeMap->{$type};
    if(defined $exType) {
      return 1 if ($exType eq "*");
      return 1 if ($exType eq $reading);
    }
  }

  # devices
  if (defined $gExcludesDevMap) {
    my $exDevName=$gExcludesDevMap->{$devName};
    if(defined $exDevName) {
      return 1 if ($exDevName eq "*");
      return 1 if ($exDevName eq $reading);
    }
  }
  
  return;
}

# Prueft, ob per MQTT ankommende Nachrichten ggf. per MQTT weiter geleitet werden duerfen.
#  Parameter:
#     $hash:    HASH
#     $devName: Geraetename
#     $reading: Reading (ggf. for future use)
sub isDoForward {
  my $hash    = shift // return;
  my $devName = shift // carp q[No device name provided!] && return;
  #my $reading = shift // carp q[No reading provided!] && return;

  my $doForward = $attr{$devName}{$hash->{+HS_PROP_NAME_PREFIX}.CTRL_ATTR_NAME_FORWARD};

  $doForward = 'none' if !defined($doForward) && $defs{$devName}->{TYPE} eq 'dummy'; # Hack fuer Dummy-Devices

  #$doForward = 'all' if !defined $doForward;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] isDoForward $devName => $doForward");

  return 1 if !defined $doForward || $doForward eq 'all';
  return 0;
}

# MQTT-Nachricht senden
# Params: Bridge-Hash, Topic, Nachricht, QOS- und Retain-Flags
sub doPublish { #($$$$$$$$) {
  #my ($hash,$device,$reading,$topic,$message,$qos,$retain,$resendOnConnect) = @_;
  my $hash            = shift // return;
  my $device          = shift // carp q[No device provided!]  && return;
  my $reading         = shift // carp q[No reading provided!] && return;
  my $topic           = shift // carp q[No topic provided!]   && return;
  my $message         = shift // carp q[No message provided!] && return;
  my $qos             = shift // 0;
  my $retain          = shift // 0;
  my $resendOnConnect = shift;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] doPublish: topic: $topic, msg: $message, resend mode: ".(defined($resendOnConnect)?$resendOnConnect:"no"));
  if(!isConnected($hash)) {
    # store message?
    if(defined($resendOnConnect)) {
      $resendOnConnect = lc($resendOnConnect);
      Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] offline publish: store: topic: $topic, msg: $message, mode: $resendOnConnect");
      if($resendOnConnect eq 'first' or $resendOnConnect eq 'last' or $resendOnConnect eq 'all') {
        # store msg data
        my $queue = $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};
        #my $queue = $hash->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};
        $queue = {} unless defined $queue;

        my $entry = {'topic'=>$topic, 'message'=>$message, 'qos'=>$qos, 'retain'=>$retain, 
                     'resendOnConnect'=>$resendOnConnect,'device'=>$device,'reading'=>$reading};
        my $topicQueue = $queue->{$topic};
        if (!defined($topicQueue)) {
          $topicQueue = [$entry];
        } 
        else {
          if ($resendOnConnect eq 'first') {
            #if (scalar @$topicQueue == 0) {
              $topicQueue = [$entry] if !(@$topicQueue);  
            #}
          } elsif($resendOnConnect eq 'last') {
            $topicQueue = [$entry];
          } else { # all
            push @$topicQueue, $entry;
          } 
        }
        # check max lng
        my $max = $hash->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE_MAX_CNT_PROTOPIC} // 10;
        #$max = 10 unless defined $max;
        while (scalar @$topicQueue > $max) {
          shift @$topicQueue;
        }

        $queue->{$topic} = $topicQueue;
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] offline publish: stored: ".Dumper($queue));

        $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE} = $queue;
      }
    }
    return 'stored';
  }

  Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publish: $topic => $message (qos: $qos, retain: $retain");

  if (isIODevMQTT2($hash)){ 
    # TODO: publish MQTT2
    # TODO qos / retain ? 
    $topic.=':r' if $retain;
    IOWrite($hash, "publish", $topic.' '.$message);
    
    $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT}++;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'transmission-state','outgoing publish sent');
    #readingsSingleUpdate($hash,"transmission-state","outgoing publish sent",1);
    readingsBulkUpdate($hash,'outgoing-count',$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT});
    #readingsSingleUpdate($hash,"outgoing-count",$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT},1);
    readingsEndUpdate($hash,1);
    return;
  } elsif (isIODevMQTT($hash)) { #elsif ($hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT') {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] doPublish for $device, $reading, topic: $topic, message: $message");
    my $msgid;
    if(defined($topic) and defined($message)) {
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] send_publish: topic: $topic, message: $message");
      $msgid = send_publish($hash->{IODev}, topic => $topic, message => $message, qos => $qos, retain => $retain);
      
      $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT}++;
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,'transmission-state','outgoing publish sent');
      readingsBulkUpdate($hash,'outgoing-count',$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT});
      readingsEndUpdate($hash,1);
    
      #readingsSingleUpdate($hash,"transmission-state","outgoing publish sent",1);
      #readingsSingleUpdate($hash,"outgoing-count",$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT},1);
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publish: $topic => $message");
      return;
    }
    $hash->{message_ids}->{$msgid}++ if defined $msgid;
    return 'empty topic or message';
  } else {
    my $iodt = retrieveIODevType($hash);
    $iodt = 'undef' if !defined $iodt;
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] unknown IODev: ".$iodt);
    return 'unknown IODev';
  }
}

# MQTT-Nachrichten entsprechend Geraete-Infos senden
# Params: Bridge-Hash, Device-Hash, 
#         Modus (Topics entsprechend Readings- oder Attributen-Tabelleneintraegen suchen), 
#         Name des Readings/Attributes, Wert
sub publishDeviceUpdate { #($$$$$) {
#  my ($hash, $devHash, $mode, $reading, $value) = @_;
  my $hash    = shift // return;
  my $devHash = shift // carp q[No hash for target device provided!] && return;
  my $mode    = shift // q{R};
  my $reading = shift // carp q[No reading provided!] && return;
  my $value   = shift // q{\0} ; # TODO: pruefen: oder doch ""?;

  my $devn = $devHash->{NAME};
  my $type = $devHash->{TYPE};
  #$mode = 'R' unless defined $mode;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publishDeviceUpdate for $type, $mode, $devn, $reading, $value");  
  # bestimmte bekannte types und readings ausschliessen (vor allem 'transmission-state' in der eigenen Instanz, das fuert sonst zu einem Endlosloop)
  return if($type eq "MQTT_GENERIC_BRIDGE");
  return if($type eq "MQTT");
  return if($reading eq "transmission-state");

  # nicht durch devspec abgedeckte Geraete verwerfen
  my $devspec = $hash->{+HS_PROP_NAME_DEVSPEC};
  if (defined($devspec) and ($devspec ne '') and ($devspec ne '.*')) {
    my @devices = devspec2array($devspec);
    # check device exists in the list
    return unless grep {$_ eq $devn} @devices;
  }

  # extra definierte (ansonsten gilt eine Defaultliste) Types/Readings auschliessen.
  return if(isTypeDevReadingExcluded($hash, 'pub', $type, $devn, $reading));

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publishDeviceUpdate for $devn, $reading, $value");
  my $pubRecList = getDevicePublishRec($hash, $devn, $reading);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publishDeviceUpdate pubRec: ".Dumper($pubRecList));
  
  #Beta-User: direct return?
  if(defined($pubRecList)) {
    for my $pubRec (@$pubRecList) {
  if(defined($pubRec)) {
    # my $msgid;
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] publishDeviceUpdate pubRec: ".Dumper($pubRec));
    my $defMap = $pubRec->{'.defaultMap'};

    my $topic = $pubRec->{'topic'}; # 'normale' Readings
    $topic = $pubRec->{'atopic'} if $mode eq 'A'; # Attributaenderungen
    my $qos = $pubRec->{'qos'};
    my $retain = $pubRec->{'retain'};
    my $expression = $pubRec->{'expression'};
    my $base = $pubRec->{'base'} // q{};
    my $resendOnConnect = $pubRec->{'resendOnConnect'};
    # # damit beim start die Attribute einmal uebertragen werden => geht wohl mangels event beim start nicht
    # if(!$main::init_done and !defined($resendOnConnect) and ($mode eq 'A')) {
    #   $resendOnConnect = 'last';
    #   Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] queueing Attr-Chang at start");
    # }

    #$base='' unless defined $base;

        #$value="\0" unless defined $value; # TODO: pruefen: oder doch ""?

    my $redefMap=undef;
    my $message=$value;
    if(defined $expression) {
      # Expression: Direktes aendern von Attributen ($topic, $qos, $retain, $value) moeglich
      # Rueckgabe: bei undef wird die Ausfuehrung unterbunden. Sonst wird die Rueckgabe als neue message interpretiert, 
      # es sei denn, Variable $value wurde geaendert, dann hat die Aenderung Vorrang.
      # Rueckgabewert wird ignoriert, falls dieser ein Array ist. 
      # Bei einem Hash werden Paare als Topic-Message Paare verwendet und mehrere Nachrichten gesendet
      no strict "refs";
      local $@ = undef;
      # $device, $reading, $name (und fuer alle Faelle $topic) in $defMap packen, so zur Verfügung stellen (für eval)reicht wegen _evalValue2 wohl nicht
      my $name = $reading; # TODO: Name-Mapping
      my $device = $devn;
          #if(!defined($defMap->{'room'})) {
          #  $defMap->{'room'} = AttrVal($devn,'room','');
          #}
          if(!defined($defMap->{'uid'}) && defined($defs{$devn})) {
            $defMap->{'uid'} = $defs{$devn}->{'FUUID'} // q{};
            #$defMap->{'uid'} = '' unless defined $defMap->{'uid'};
          }
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> DEBUG: >>> expression: $expression : ".Dumper($defMap));
          my $ret = _evalValue2($hash->{NAME},$expression,{'topic'=>$topic,'device'=>$devn,'reading'=>$reading,'name'=>$name,'time'=>TimeNow(),%$defMap},1);
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> DEBUG: <<< expression: ".Dumper($ret));
      $ret = eval($ret); ##no critic qw(eval) 
      # we expressively want user code to be executed! This is added after compile time...
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> DEBUG: <<< eval expression: ".Dumper($ret));
      if(ref($ret) eq 'HASH') {
        $redefMap = $ret;
      } elsif(ref($ret) eq 'ARRAY') {
        # ignore
      } elsif(!defined($ret)) {
        $message = undef;
      } elsif($value ne $message) {
        $message = $value;
      } else {
        $message = $ret;
      }
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] eval done: ".Dumper($ret));
      if ($@) {
        Log3($hash->{NAME},2,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] error while evaluating expression ('".$expression."'') eval error: ".$@);
      }
      use strict "refs";
    }

    my $updated = 0;
    if(defined($redefMap)) {
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> DEBUG: redefMap: ".Dumper($redefMap));
      for my $key (keys %{$redefMap}) {
        my $val = $redefMap->{$key};
        my $r = doPublish($hash,$devn,$reading,$key,$val,$qos,$retain,$resendOnConnect);
        $updated = 1 if !defined $r;
      }
    } elsif (defined $topic and defined $message) {
      my $r = doPublish($hash,$devn,$reading,$topic,$message,$qos,$retain,$resendOnConnect);  
      $updated = 1 unless defined $r;
    }
    if($updated) {
      updatePubTime($hash,$devn,$reading);
    }

  }
}
  }
  return;
}

# Routine fuer FHEM Attr
sub Attr {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $defs{$name} // return;
  
    # Steuerattribute
  if (   $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS
      || $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS
      || $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH) {
      if ($command eq "set") {
        RefreshGlobalTable($hash, $attribute, $value);
      } else {
        RefreshGlobalTable($hash, $attribute, undef);
      }
    return;
      }
  if ($attribute eq CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE) {
      if ($command eq "set") {
        defineGlobalTypeExclude($hash,$value);
      } else {
        defineGlobalTypeExclude($hash,undef);
      }
    return;
  }
  if ($attribute eq CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE) {
      if ($command eq "set") {
        defineGlobalDevExclude($hash,$value);
      } else {
        defineGlobalDevExclude($hash,undef);
      }
    return;
  }

    my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  if (($attribute eq $prefix.CTRL_ATTR_NAME_DEFAULTS) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_ALIAS) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_PUBLISH) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_SUBSCRIBE) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_IGNORE) or
      ($attribute eq $prefix.CTRL_ATTR_NAME_FORWARD)) {
              
      if ($command eq "set") {
        return "this attribute is not allowed here";
      }
    return;
    }
    
    # Gateway-Device
  if ($attribute eq "IODev") {
      my $ioDevType = undef;
      $ioDevType = $defs{$value}{TYPE} if defined ($value) and defined ($defs{$value});
      $hash->{+HELPER}->{+IO_DEV_TYPE} = $ioDevType;
      
      if ($command eq "set") {
      my $oldValue = $attr{$name}{IODev};
      if ($init_done) {
          unless (defined ($oldValue) and ($oldValue eq $value) ) {
            #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] attr: change IODev");
          MQTT::client_stop($hash) if defined($attr{$name}{IODev}) and ($attr{$name}{IODev} eq 'MQTT');
          $attr{$name}{IODev} = $value;
            firstInit($hash);
          }
        }
      } else {
      if ($init_done) {
          MQTT::client_stop($hash) if defined ($ioDevType) and ($ioDevType eq 'MQTT');
        }
      }
    return;
  }
  return;
}

# CallBack-Handler fuer IODev beim Connect
sub ioDevConnect {
  my $hash = shift;
  #return if isIODevMQTT2($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER'; # TODO

  # ueberraschenderweise notwendig fuer eine subscribe-Initialisierung.
  MQTT::client_start($hash) if isIODevMQTT($hash);

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] ioDevConnect");

  # resend stored msgs => doPublish (...., undef)
  my $queue = $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};

  return if !defined($queue);
  #if (defined($queue)) {
    for my $topic (keys %{$queue}) {
      my $topicQueue = $queue->{$topic};
      my $topicRec = undef;
      while ($topicRec = shift(@$topicQueue)) {
        my $message = $topicRec->{'message'};
        my $qos     = $topicRec->{'qos'};
        my $retain  = $topicRec->{'retain'};
        my $resendOnConnect = undef; #$topicRec->{'resendOnConnect'};
        my $devn    = $topicRec->{'device'};
        my $reading = $topicRec->{'reading'};
        my $r = doPublish($hash,$devn,$reading,$topic,$message,$qos,$retain,$resendOnConnect);
        updatePubTime($hash,$devn,$reading) unless defined $r;
      }
    }
  #}
  return;
}

# CallBack-Handler fuer IODev beim Disconnect
sub ioDevDisconnect {
  my $hash = shift;
  #return if isIODevMQTT2($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] ioDevDisconnect");

  # TODO ? 
  return;
}

# Per MQTT-Empfangenen Aktualisierungen an die entsprechende Geraete anwenden
# Params: Bridge-Hash, Modus (R=Readings, A=Attribute), Device, Reading/Attribute-Name, Nachricht
sub doSetUpdate { #($$$$$) {
  #my ($hash,$mode,$device,$reading,$message) = @_;
  my $hash    = shift // return;
  my $mode    = shift // q{unexpected!};
  my $device  = shift // carp q[No device provided!]  && return;
  my $reading = shift // carp q[No reading provided!] && return;
  my $message = shift; # // carp q[No message content!]  && return;
  my $isBulk  = shift // 0;

  my $dhash = $defs{$device} // carp qq[No device hash for $device registered!]  && return;
  #return unless defined $dhash;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] setUpdate enter: update: $reading = $message");
  #my $doForward = isDoForward($hash, $device,$reading); 
  my $doForward = isDoForward($hash, $device); #code seems only to support on device level!

  if($mode eq 'S') {
    my $err;
    my @args = split ("[ \t]+",$message);
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] mqttGenericBridge_triggeredReading=".Dumper($dhash->{'.mqttGenericBridge_triggeredReading'}));
    if(($reading eq '') or ($reading eq 'state')) {
      $dhash->{'.mqttGenericBridge_triggeredReading'}="state" if !$doForward;
      $dhash->{'.mqttGenericBridge_triggeredReading_val'}=$message if !$doForward;
      #$err = DoSet($device,$message);
      $err = DoSet($device,@args);
    } else {
      $dhash->{'.mqttGenericBridge_triggeredReading'}=$reading if !$doForward;
      $dhash->{'.mqttGenericBridge_triggeredReading_val'}=$message if !$doForward;
      #$err = DoSet($device,$reading,$message);
      $err = DoSet($device,$reading,@args);
    }
    if (!defined($err)) {
      $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT}++; 
      readingsSingleUpdate($hash,"updated-set-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT},1);
      return;
    }
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] setUpdate: error in set command: ".$err);
    return "error in set command: $err";
  } elsif($mode eq 'R') { # or $mode eq 'T') {
    # R - Normale Topic (beim Empfang nicht weiter publishen)
    # T - Selt-Trigger-Topic (Sonderfall, auch wenn gerade empfangen, kann weiter getriggert/gepublisht werden. Vorsicht! Gefahr von 'Loops'!)
    readingsBeginUpdate($dhash) if !$isBulk;
    if ($mode eq 'R' && !$doForward) {
      $dhash->{'.mqttGenericBridge_triggeredReading'}     = $reading;
      $dhash->{'.mqttGenericBridge_triggeredReading_val'} = $message;
      $dhash->{'.mqttGenericBridge_triggeredBulk'}        = 1 if $isBulk;
    }
    readingsBulkUpdate($dhash,$reading,$message);
    readingsEndUpdate($dhash,1) if !$isBulk;
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] setUpdate: update: $reading = $message");
    # wird in 'notify' entfernt # delete $dhash->{'.mqttGenericBridge_triggeredReading'};

    $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT}++; 
    readingsSingleUpdate($hash,"updated-reading-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT},1);
    return;
  } elsif($mode eq 'A') {
    CommandAttr(undef, "$device $reading $message");
    return;
  } else {
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] setUpdate: unexpected mode: ".$mode);
    return "unexpected mode: $mode";
  }
  return "internal error";
}

# Call von IODev-Dispatch (e.g.MQTT2)
sub Parse {
  my $iodev = shift // carp q[No IODev provided!] && return;;
  my $msg   = shift // carp q[No message to analyze!] && return;;

  my $ioname = $iodev->{NAME};
  #my $iotype = $iodev->{TYPE};
  #Log3($iodev->{NAME},1,"MQTT_GENERIC_BRIDGE: Parse: IODev: $ioname");
  #Log3("XXX",1,"MQTT_GENERIC_BRIDGE: Parse: $msg");

  # no support for autocreate
  #my $autocreate = "no";
  #if($msg =~ m{\Aautocreate=([^\0]+)\0(.*)\z}sx) {
    ##$autocreate = $1;
    #$msg = $2;
  #}
  $msg =~ s{\Aautocreate=([^\0]+)\0(.*)\z}{$2}sx;
  #my ($cid, $topic, $value) = split(":", $msg, 3);
  my ($cid, $topic, $value) = split m{\0}xms, $msg, 3;
  
  my @instances = devspec2array("TYPE=MQTT_GENERIC_BRIDGE");
  my @ret=();
  my $forceNext = 0;
  for my $dev (@instances) {
    my $hash = $defs{$dev};
    # Name mit IODev vegleichen
    my $iiodn = retrieveIODevName($hash);
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] Parse: test IODev: $iiodn vs. $ioname");
    next if $ioname ne $iiodn;
    my $iiodt = retrieveIODevType($hash);
    next if !checkIODevMQTT2($iiodt);
    #next unless isIODevMQTT2($hash);

    Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] Parse ($iiodt : '$ioname'): Msg: $topic => $value");

    #return onmessage($hash, $topic, $value);
    # my @ret = onmessage($hash, $topic, $value);
    # unshift(@ret, "[NEXT]"); # damit weitere Geraetemodule ggf. aufgerufen werden
    # return @ret;
    my $fret = onmessage($hash, $topic, $value);
    next if !defined $fret;
    if( ref($fret) eq 'ARRAY' ) {
      push (@ret, @{$fret});
      $forceNext = 1 if AttrVal($hash->{NAME},'forceNEXT',0);
      #my @ret=@{$fret};
      #unshift(@ret, "[NEXT]"); # damit weitere Geraetemodule ggf. aufgerufen werden
      #return @ret;
    } else {
      Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] Parse ($iiodt : '$ioname'): internal error:  onmessage returned an unexpected value: ".$fret);  
    }
  }
  unshift(@ret, "[NEXT]") if !(@ret) || $forceNext; # damit weitere Geraetemodule ggf. aufgerufen werden
  return @ret;
}

# Routine MQTT-Message Callback
sub onmessage {
  my $hash    = shift // return;
  my $topic   = shift // carp q[No topic provided!] && return;
  my $message = shift // q{}; #might be empty... // carp q[No message content!] && return;
  #CheckInitialization($hash);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] onmessage: $topic => $message");

  my $fMap = searchDeviceForTopic($hash, $topic);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] onmessage: $fMap : ".Dumper($fMap));

  #if (isIODevMQTT($hash) || keys %{$fMap}) {
  if (keys %{$fMap}) {
    $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT}++; 
    readingsSingleUpdate($hash,"incoming-count",$hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT},1);
  }

  my $updated = 0;
  my @updatedList;
  for my $deviceKey (keys %{$fMap}) {
        my $device = $fMap->{$deviceKey}->{'device'};
        my $reading = $fMap->{$deviceKey}->{'reading'};
        my $mode = $fMap->{$deviceKey}->{'mode'};
        my $expression = $fMap->{$deviceKey}->{'expression'};

        next if !defined $device || !defined $reading;

        my $dhash = $defs{$device};
        next if !defined $dhash || isTypeDevReadingExcluded($hash, 'sub', $dhash->{TYPE}, $device, $reading);

        my $redefMap=undef;

        if(defined $expression) {
          # Expression: Verfuegbare Variablen: $device, $reading, $message (initial gleich $value)
          # Rueckgabe: bei undef wird die Ausfuehrung unterbunden. Sonst wird die Rueckgabe als neue message interpretiert, 
          # es sei denn, Variable $value wurde geaendert, dann hat die Aenderung Vorrang.
          # Rueckgabewert wird ignoriert, falls dieser ein Array ist. 
          # Bei einem Hash werden Paare als Reading-Wert Paare gesetzt (auch set (stopic), attr (atopic))
          no strict "refs";
          local $@ = undef;
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] eval ($expression) !!!");
          my $value = $message;
          my $ret = eval($expression); ##no critic qw(eval) 
          # we expressively want user code to be executed! This is added after compile time...
          if(ref($ret) eq 'HASH') {
            $redefMap = $ret;
          } elsif(ref($ret) eq 'ARRAY') {
            # ignore
          } elsif($value ne $message) {
            $message = $value;
          #} elsif(!defined($ret)) { #Beta-User: same as next assignement..?
          #  $message = undef;
          } else {
            $message = $ret;
          }
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] eval done: ".Dumper($ret));
          if ($@) {
            Log3($hash->{NAME},2,"MQTT_GENERIC_BRIDGE: [$hash->{NAME}] onmessage: error while evaluating expression ('".$expression."'') eval error: ".$@);
          }
          #use strict "refs"; # this is automatically done in lexical scope
        }

        #next unless defined $device;
        #next unless defined $reading;

        next if !defined $message;

        if(defined($redefMap)) {
          for my $key (keys %{$redefMap}) {
            my $val = $redefMap->{$key};
            readingsBeginUpdate($defs{$device});
            my $r = doSetUpdate($hash,$mode,$device,$key,$val,1);
            unless (defined($r)) {
              $updated = 1 if !$updated;
              push(@updatedList, $device);
            }
            readingsEndUpdate($defs{$device},1);
          }
        } else {
          my $r = doSetUpdate($hash,$mode,$device,$reading,$message);
          unless (defined($r)) {
            $updated = 1;
            push(@updatedList, $device);
          }
        }

        # TODO: ggf. Update Last Received implementieren (nicht ganz einfach).
        #if($updated) {
          #updateSubTime($device,$reading);
        #}
  }
  return \@updatedList if($updated);
  return;
}
1;
__END__
=pod
=encoding utf8
=item [device]
=item summary MQTT_GENERIC_BRIDGE acts as a bridge for any fhem-devices and mqtt-topics
=begin html

<a name="MQTT_GENERIC_BRIDGE"></a>
 <h3>MQTT_GENERIC_BRIDGE</h3>
 <ul>
 <p>
        This module is a MQTT bridge, which simultaneously collects data from several FHEM devices
        and passes their readings via MQTT, sets readings from incoming MQTT messages or executes incoming messages
       as a 'set' command for the configured FHEM device.
     <br/>One for the device types could serve as IODev: <a href="#MQTT">MQTT</a>,
     <a href="#MQTT2_CLIENT">MQTT2_CLIENT</a> or <a href="#MQTT2_SERVER">MQTT2_SERVER</a>.
 </p>
 <p>The (minimal) configuration of the bridge itself is basically very simple.</p>
 <a name="MQTT_GENERIC_BRIDGEdefine"></a>
 <p><b>Definition:</b></p>
 <ul>
   <p>In the simplest case, two lines are enough:</p>
     <p><code>defmod mqttGeneric MQTT_GENERIC_BRIDGE [prefix] [devspec,[devspec]</br>
     attr mqttGeneric IODev <MQTT-Device></code></p>
   <p>All parameters in the define are optional.</p>
   <p>The first parameter is a prefix for the control attributes on which the devices to be 
       monitored (see above) are configured. Default value is 'mqtt'. 
       If this is e.g. redefined as <i>mqttGB1_</i>, the control attributes are named <i>mqttGB1_Publish</i> etc.
    </p>
   <p>The second parameter ('devspec') allows to minimize the number of devices to be monitored
      (otherwise all devices will be monitored, which may cost performance).
      Example for devspec: 'TYPE=dummy' or 'dummy1,dummy2'. Following the general rules for <a href="#devspec">devspec</a>, a comma separated list must not contain any whitespaces!</p>
 </ul>
 
 <a name="MQTT_GENERIC_BRIDGEget"></a>
 <p><b>get:</b></p>
 <ul>
   <li>
     <p>version<br/>
        Displays module version.</p>
   </li>
   <li>
     <p>devlist [&lt;name (regex)&gt;]<br/>
        Returns list of names of devices monitored by this bridge whose names correspond to the optional regular expression. 
        If no expression provided, all devices are listed.
     </p>
   </li>
   <li>
     <p>devinfo [&lt;name (regex)&gt;]<br/>
        Returns a list of monitored devices whose names correspond to the optional regular expression. 
        If no expression provided, all devices are listed. 
        In addition, the topics used in 'publish' and 'subscribe' are displayed including the corresponding read-in names.
    </p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEreadings"></a>
 <p><b>readings:</b></p>
 <ul>
   <li>
     <p>device-count<br/>
        Number of monitored devices</p>
   </li>
   <li>
     <p>incoming-count<br/>
        Number of incoming messages</p>
   </li>
   <li>
     <p>outgoing-count<br/>
        Number of outgoing messages</p>
   </li>
   <li>
     <p>updated-reading-count<br/>
        Number of updated readings</p>
   </li>
   <li>
     <p>updated-set-count<br/>
        Number of executed 'set' commands</p>
   </li>
   <li>
     <p>transmission-state<br/>
        last transmission state</p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEattr"></a>
 <p><b>Attributes:</b></p>
 <ul>
   <p><b>The MQTT_GENERIC_BRIDGE device itself</b> supports the following attributes:</p>
   <ul>
   <li><p>IODev<br/>
    This attribute is mandatory and must contain the name of a functioning MQTT-IO module instance. MQTT, MQTT2_CLIENT and MQTT2_SERVER are supported.</p>
   </li>

   <li>
     <p>disable<br/>
        Value '1' deactivates the bridge</p>
     <p>Example:<br>
       <code>attr &lt;dev&gt; disable 1</code>
     </p>
   </li>

   <li>
     <p>globalDefaults<br/>
        Defines defaults. These are used in the case where suitable values are not defined in the respective device.
        see <a href="#MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a>. 
        <p>Example:<br>
        <code>attr &lt;dev&gt; sub:base=FHEM/set pub:base=FHEM</code>
     </p>
   </li>

   <li>
    <p>globalAlias<br/>
        Defines aliases. These are used in the case where suitable values are not defined in the respective device. 
        see <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>.
     </p>
   </li>
   
   <li>
    <p>globalPublish<br/>
        Defines topics / flags for MQTT transmission. These are used if there are no suitable values in the respective device.
        see <a href="#MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a>.
     </p>
     <p>Remark:<br>
        Setting this attribute will publish any reading value from any device matching the devspec. In most cases this may not be the intented behaviour, setting accurate attributes to the subordinated devices should be preferred.
     </p>
   </li>

   <li>
    <p>globalTypeExclude<br/>
        Defines (device) types and readings that should not be considered in the transmission.
        Values can be specified separately for each direction (publish or subscribe). Use prefixes 'pub:' and 'sub:' for this purpose.
        A single value means that a device is completely ignored (for all its readings and both directions). 
        Colon separated pairs are interpreted as '[sub:|pub:]Type:Reading'. 
        This means that the given reading is not transmitted on all devices of the given type. 
        An '*' instead of type or reading means that all readings of a device type or named readings are ignored on every device type.</p>
        <p>Example:<br/>
        <code>attr &lt;dev&gt; globalTypeExclude MQTT MQTT_GENERIC_BRIDGE:* MQTT_BRIDGE:transmission-state *:baseID</code></p>
   </li>

   <li>
    <p>globalDeviceExclude<br/>
        Defines device names and readings that should not be transferred. 
        Values can be specified separately for each direction (publish or subscribe). Use prefixes 'pub:' and 'sub:' for this purpose.
        A single value means that a device with that name is completely ignored (for all its readings and both directions).
        Colon-separated pairs are interpreted as '[sub:|pub:]Device:Reading'. 
        This means that the given reading is not transmitted to the given device.</p>
        <p>Example:<br/>
            <code>attr &lt;dev&gt; globalDeviceExclude Test Bridge:transmission-state</code></p>
   </li>
   
   <li>
    <p>forceNEXT<br/>
       Only relevant for MQTT2_CLIENT or MQTT2_SERVER as IODev. If set to 1, MQTT_GENERIC_BRIDGE will forward incoming messages also to further client modules like MQTT2_DEVICE, even if the topic matches to one of the subscriptions of the controlled devices. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also <a href="#MQTT2_CLIENTclientOrder">clientOrder attribute in MQTT2 IO-type commandrefs</a>; setting this in one instance of MQTT_GENERIC _BRIDGE might affect others, too.</p>
   </li>
   </ul>
   <br>

   <p><b>For the monitored devices</b>, a list of the possible attributes is automatically extended by several further entries. 
      Their names all start with the prefix previously defined in the bridge. These attributes are used to configure the actual MQTT mapping.<br/>
      By default, the following attribute names are used: mqttDefaults, mqttAlias, mqttPublish, mqttSubscribe.
      <br/>The meaning of these attributes is explained below.
    </p>
    <ul>
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a><br/>
            Here is a list of "key = value" pairs defined. The following keys are possible:
            <ul>
             <li>'qos' <br/>defines a default value for MQTT parameter 'Quality of Service'.</li>
             <li>'retain' <br/>allows MQTT messages to be marked as 'retained'.</li>
             <li>'base' <br/>s provided as a variable ($base) when configuring concrete topics. 
                It can contain either text or a Perl expression. 
                Perl expression must be enclosed in curly brackets. 
                The following variables can be used in an expression:
                   $base = corresponding definition from the '<a href="#MQTT_GENERIC_BRIDGEglobalDefaults">globalDefaults</a>', 
                   $reading = Original reading name, $device = device name, and $name = reading alias (see <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>. 
                   If no alias is defined, than $name = $ reading).<br/>
                   Furthermore, freely named variables can be defined. These can also be used in the public / subscribe definitions. 
                   These variables are always to be used there with quotation marks.
                   </li>
            </ul>
            <br/>
            All these values can be limited by prefixes ('pub:' or 'sub') in their validity 
            to only send or receive only (as far asappropriate). 
            Values for 'qos' and 'retain' are only used if no explicit information has been given about it for a specific topic.</p>
            <p>Example:<br/>
                <code>attr &lt;dev&gt; mqttDefaults base={"TEST/$device"} pub:qos=0 sub:qos=2 retain=0</code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a><br/>
            This attribute allows readings to be mapped to MQTT topic under a different name. 
            Usually only useful if topic definitions are Perl expressions with corresponding variables or to achieve somehow standardized topic structures. 
            Again, 'pub:' and 'sub:' prefixes are supported 
            (For 'subscribe', the mapping will be reversed).
            </p>
            <p>Example:<br/>
                <code>attr &lt;dev&gt; mqttAlias pub:temperature=temp</code></p>
        </p>
    </li>
  
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a><br/>
            Specific topics can be defined and assigned to the Readings(Format: &lt;reading&gt;:topic=&lt;topic&gt;). 
            Furthermore, these can be individually provided with 'qos' and 'retain' flags.<br/>
            Topics can also be defined as Perl expression with variables ($reading, $device, $name, $base or additional variables as provided in <a href="#MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a>).<br/><br/>
            Values for several readings can also be defined together, separated with '|'.<br/>
            If a '*' is used instead of a reading name, this definition applies to all readings for which no explicit information was provided.<br/>
            Topic can also be written as a 'readings-topic'.<br/>
            Attributes can also be sent ("atopic" or "attr-topic").
            If you want to send several messages (e.g. to different topics) for an event, the respective definitions must be defined by appending
            unique suffixes (separated from the reading name by a !-sign): reading!1:topic=... reading!2:topic=.... <br/>
            It is possible to define expressions (reading: expression = ...). <br/>
            The expressions could be used to change variables ($value, $topic, $qos, $retain, $message, $uid), or return a value of != undef.<br/>
            The return value is used as a new message value, the changed variables have priority.<br/>
            If the return value is <i>undef</i>, setting / execution is suppressed. <br/>
            If the return is a hash (topic only), its key values are used as the topic, and the contents of the messages are the values from the hash.</p>
            <p>Option 'resendOnConnect' allows to save the messages,
            if the bridge is not connected to the MQTT server.
            The messages to be sent are stored in a queue.
            When the connection is established, the messages are sent in the original order.
            <ul>Possible values:
               <li> none <br/> discard all </li>
               <li> last <br/> save only the last message </li>
               <li> first <br/> save only the first message
               then discard the following</li>
               <li>all<br/>save all, but if there is an upper limit of 100, if it is more, the most supernatural messages are discarded. </li>
            </ul>
            <p>Examples:<br/>
                <code> attr &lt;dev&gt; mqttPublish temperature:topic={"$base/$name"} temperature:qos=1 temperature:retain=0 *:topic={"$base/$name"} humidity:topic=/TEST/Feuchte<br/>
                attr &lt;dev&gt; mqttPublish temperature|humidity:topic={"$base/$name"} temperature|humidity:qos=1 temperature|humidity:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} *:qos=2 *:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={$value="message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"/TEST/Topic1"=>"$message", "/TEST/Topic2"=>"message: $message"}<br/>
                attr &lt;dev&gt; mqttPublish *:resendOnConnect=last<br/>
                attr &lt;dev&gt; mqttPublish temperature:topic={"$base/temperature/01/value"} temperature!json:topic={"$base/temperature/01/json"}
                   temperature!json:expression={toJSON({value=>$value,type=>"temperature",unit=>"°C",format=>"00.0"})}<br/>
                </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a><br/>
            This attribute configures the device to receive MQTT messages and execute corresponding actions.<br/>
            The configuration is similar to that for the 'mqttPublish' attribute. 
            Topics can be defined for setting readings ('topic' or 'readings-topic') and calls to the 'set' command on the device ('stopic' or 'set-topic').<br/>
            Also attributes can be set ('atopic' or 'attr-topic').</br>
            The result can be modified before setting the reading or executing of 'set' / 'attr' on the device with additional Perl expressions ('expression').<br/>
            The following variables are available in the expression: $device, $reading, $message (initially equal to $value). 
            The expression can either change variable $value, or return a value != undef. 
            Redefinition of the variable has priority. If the return value is undef, then the set / execute is suppressed (unless $value has a new value).<br/>
            If the return is a hash (only for 'topic' and 'stopic'), 
            then its key values are used as readings or 'set' parameters, 
            the values to be set are the values from the hash.<br/>
            Furthermore the attribute 'qos' can be specified ('retain' does not make sense here).<br/>
            Topic definition can include MQTT wildcards (+ and #).<br/>
            If the reading name is defined with a '*' at the beginning, it will act as a wildcard. 
            Several definitions with '*' should also be used as: *1:topic = ... *2:topic = ...
            The actual name of the reading (and possibly of the device) is defined by variables from the topic
            ($device (only for global definition in the bridge), $reading, $name).
            In the topic these variables act as wildcards, of course only makes sense, if reading name is not defined 
            (so start with '*', or multiple names separated with '|').<br/>
            The variable $name, unlike $reading, may be affected by the aliases defined in 'mqttAlias'. Also use of $base is allowed.<br/>
            When using 'stopic', the 'set' command is executed as 'set &lt;dev&gt; &lt;reading&gt; &lt;value&gt;'.
            For something like 'set &lt;dev&gt; &lt;value&gt;'  'state' should be used as reading name.</p>
            <p>If JSON support is needed: Use the <i>json2nameValue()</i> method provided by <i>fhem.pl</i> in 'expression' with '$message' as parameter.</p>
            <p>Examples:<br/>
                <code>attr &lt;dev&gt; mqttSubscribe temperature:topic=TEST/temperature test:qos=0 *:topic={"TEST/$reading/value"} <br/>
                    attr &lt;dev&gt; mqttSubscribe desired-temperature:stopic={"TEST/temperature/set"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={...}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={$value="x"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={"R1"=>$value, "R2"=>"Val: $value", "R3"=>"x"}
                    attr &lt;dev&gt; mqttSubscribe verbose:atopic={"TEST/light/verbose"}
                    attr &lt;dev&gt; mqttSubscribe json:topic=XTEST/json json:expression={json2nameValue($message)}
                 </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttForward">mqttForward</a><br/>
            This attribute defines what happens when one and the same reading is both subscribed and posted. 
            Possible values: 'all' and 'none'.<br/>
            If 'none' is selected, than messages received via MQTT will not be published from the same device.<br/>
            The setting 'all' does the opposite, so that the forwarding is possible.<br/>
      If this attribute is missing, the default setting for all device types except 'dummy' is 'all' 
      (so that actuators can receive commands and send their changes in the same time) and for dummies 'none' is used. 
      This was chosen because dummies are often used as a kind of GUI switch element. 
      In this case, 'all' might cause an endless loop of messages.
            </p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDisable">mqttDisable</a><br/>
            If this attribute is set in a device, this device is excluded from sending or receiving the readings.</p>
        </p>
    </li>
    </ul>
</ul>
 
<p><b>Examples</b></p>

<ul>
    <li>
        <p>Bridge for any devices with the standard prefix:<br/>
                <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE<br/>
                        attr mqttGeneric IODev mqtt</code>
        </p>
        </p>
    </li>
    
    <li>
        <p>Bridge with the prefix 'mqtt' for three specific devices:<br/>
            <code> defmod mqttGeneric MQTT_GENERIC_BRIDGE mqtt sensor1,sensor2,sensor3<br/>
                    attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>

    <li>
        <p>Bridge for all devices in a certain room:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE mqtt room=Wohnzimmer<br/>
                attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>
     
    <li>
        <p>Simple configuration of a temperature sensor:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttPublish temperature:topic=haus/sensor/temperature</code></p>
        </p>
    </li>

    <li>
        <p>Send all readings of a sensor (with their names as they are) via MQTT:<br/>
            <code> defmod sensor XXX<br/>
                attr sensor mqttPublish *:topic={"sensor/$reading"}</code></p>
        </p>
    </li>
     
    <li>
        <p>Topic definition with shared part in 'base' variable:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttDefaults base={"$device/$reading"}<br/>
                attr sensor mqttPublish *:topic={"$base"}</code></p>
        </p>
    </li>

    <li>
        <p>Topic definition only for certain readings with renaming (alias):<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttAlias temperature=temp humidity=hum<br/>
                attr sensor mqttDefaults base={"$device/$name"}<br/>
                attr sensor mqttPublish temperature:topic={"$base"} humidity:topic={"$base"}<br/></code></p>
        </p>
    </li>

    <li>
        <p>Example of a central configuration in the bridge for all devices that have Reading named 'temperature':<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish temperature:topic={"haus/$device/$reading"} <br/>
         </code></p>
        </p>
    </li>

    <li>
        <p>Example of a central configuration in the bridge for all devices:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish *:topic={"haus/$device/$reading"} <br/></code></p>
        </p>
    </li>
</ul>

<p><b>Limitations:</b></p>

<ul>
      <li>If several readings subscribe to the same topic, no different QOS are possible.</li>
      <li>If QOS is not equal to 0, it should either be defined individually for all readings, or generally over defaults.<br/>
        Otherwise, the first found value is used when creating a subscription.</li>
      <li>Subscriptions are renewed only when the topic is changed, so changing the QOS flag onnly will only work after a restart of FHEM.</li>
</ul>

<!--TODO-->
<!--
<p><b>Ideen:</b></p>
<ul>
  <li>global Subscribe</li>
  <li>global excludes</li>
  <li>QOS for subscribe (fertig?), defaults(qos, fertig?), alias mapping</li>
  <li>resendOnConnect (no, first, last, all)</li>
  <li>resendInterval (no/0, x min)</li>
  <li>templates (template in der Bridge, mqttUseTemplate in Device)</li>
</ul>
-->
</ul>

=end html

=item summary_DE MQTT_GENERIC_BRIDGE acts as a bridge for any fhem-devices and mqtt-topics
=begin html_DE

 <a name="MQTT_GENERIC_BRIDGE"></a>
 <h3>MQTT_GENERIC_BRIDGE</h3>
 <ul>
 <p>
    Dieses Modul ist eine MQTT-Bridge, die gleichzeitig mehrere FHEM-Devices erfaßt und deren Readings 
    per MQTT weiter gibt bzw. aus den eintreffenden MQTT-Nachrichten befüllt oder diese als 'set'-Befehl 
    an dem konfigurierten FHEM-Gerät ausführt.
     <br/>Es wird eines der folgenden Geräte als IODev benötigt: <a href="#MQTT">MQTT</a>,  
     <a href="#MQTT2_CLIENT">MQTT2_CLIENT</a> oder <a href="#MQTT2_SERVER">MQTT2_SERVER</a>.
 </p>
 <p>Die (minimale) Konfiguration der Bridge selbst ist grundsätzlich sehr einfach.</p>
 <a name="MQTT_GENERIC_BRIDGEdefine"></a>
 <p><b>Definition:</b></p>
 <ul>
   <p>Im einfachsten Fall reichen schon zwei Zeilen:</p>
     <p><code>defmod mqttGeneric MQTT_GENERIC_BRIDGE [prefix] [devspec,[devspec]]</br>
     attr mqttGeneric IODev <MQTT-Device></code></p>
   <p>Alle Parameter im Define sind optional.</p>
   <p>Der erste ist ein Prefix für die Steuerattribute, worüber die zu überwachende Geräte (s.u.) 
   konfiguriert werden. Defaultwert ist 'mqtt'. 
   Wird dieser z.B. als 'mqttGB1_' festgelegt, heißen die Steuerungsattribute entsprechend mqttGB1_Publish etc.</p>
   <p>Der zweite Parameter ('devspec') erlaubt die Menge der zu überwachenden Geräten 
   zu begrenzen (sonst werden einfach alle überwacht, was jedoch Performance kosten kann).
   Beispiel für devspec: 'TYPE=dummy' oder 'dummy1,dummy2'. Es gelten die allgemeinen Regeln für <a href="#devspec">devspec</a>, bei kommaseparierter Liste sind also keine Leerzeichen erlaubt!</p>
   
   
 </ul>
 
 <a name="MQTT_GENERIC_BRIDGEget"></a>
 <p><b>get:</b></p>
 <ul>
   <li>
     <p>version<br/>
     Zeigt Modulversion an.</p>
   </li>
   <li>
     <p>devlist [&lt;name (regex)&gt;]<br/>
     Liefert Liste der Namen der von dieser Bridge überwachten Geräte deren Namen zu dem optionalen regulärem Ausdruck entsprechen. 
     Fehlt der Ausdruck, werden alle Geräte aufgelistet. 
     </p>
   </li>
   <li>
     <p>devinfo [&lt;name (regex)&gt;]<br/>
     Gibt eine Liste der überwachten Geräte aus, deren Namen dem optionalen regulären Ausdruck entsprechen.
     Fehlt der Ausdruck, werden alle Geräte aufgelistet. Zusätzlich werden bei 'publish' und 'subscribe' 
     verwendete Topics angezeigt incl. der entsprechenden Readingsnamen.</p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEreadings"></a>
 <p><b>readings:</b></p>
 <ul>
   <li>
     <p>device-count<br/>
     Anzahl der überwachten Geräte</p>
   </li>
   <li>
     <p>incoming-count<br/>
     Anzahl eingehender Nachrichten</p>
   </li>
   <li>
     <p>outgoing-count<br/>
     Anzahl ausgehende Nachrichten</p>
   </li>
   <li>
     <p>updated-reading-count<br/>
     Anzahl der gesetzten Readings</p>
   </li>
   <li>
     <p>updated-set-count<br/>
     Anzahl der abgesetzten 'set' Befehle</p>
   </li>
   <li>
     <p>transmission-state<br/>
     letze Übertragunsart</p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEattr"></a>
 <p><b>Attribute:</b></p>
   <p>Folgende Attribute werden unterstützt:</p>
   <li><p><b>Im MQTT_GENERIC_BRIDGE-Device selbst:</b></p>
   <ul>
   <li><p>IODev<br/>
     Dieses Attribut ist obligatorisch und muss den Namen einer funktionierenden MQTT-IO-Modulinstanz enthalten. 
     Es werden derzeit MQTT, MQTT2_CLIENT und MQTT2_SERVER unterstützt.</p>
   </li>

   <li>
     <p>disable<br/>
     Wert 1 deaktiviert die Bridge</p>
     <p>Beispiel:<br>
       <code>attr &lt;dev&gt; disable 1</code>
     </p>
   </li>

   <li>
     <p>globalDefaults<br/>
        Definiert Defaults. Diese greifen in dem Fall, wenn in dem jeweiligen Gerät definierte Werte nicht zutreffen. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a>.
      <p>Beispiel:<br>
        <code>attr &lt;dev&gt; sub:base={"FHEM/set/$device"} pub:base={"FHEM/$device"}</code>
     </p>
     </p>
   </li>

   <li>
    <p>globalAlias<br/>
        Definiert Alias. Diese greifen in dem Fall, wenn in dem jeweiligen Gerät definierte Werte nicht zutreffen. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>.
     </p>
   </li>
   
   <li>
    <p>globalPublish<br/>
        Definiert Topics/Flags für die Übertragung per MQTT. Diese werden angewendet, falls in dem jeweiligen Gerät 
        definierte Werte nicht greifen oder nicht vorhanden sind. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a>.
     </p>
   <p>Hinweis:<br>
      Dieses Attribut sollte nur gesetzt werden, wenn wirklich alle Werte aus den überwachten Geräten versendet werden sollen; dies wird eher nur im Ausnahmefall zutreffen!
   </p>
   </li>

   <li>
    <p>globalTypeExclude<br/>
        Definiert (Geräte-)Typen und Readings, die nicht bei der Übertragung berücksichtigt werden. 
        Werte können getrennt für jede Richtung (publish oder subscribe) vorangestellte Prefixe 'pub:' und 'sub:' angegeben werden.
        Ein einzelner Wert bedeutet, dass ein Gerät diesen Types komplett ignoriert wird (also für alle seine Readings und beide Richtungen).
        Durch einen Doppelpunkt getrennte Paare werden als [sub:|pub:]Type:Reading interpretiert.
        Das bedeutet, dass an dem gegebenen Type die genannte Reading nicht übertragen wird.
        Ein Stern anstatt Type oder auch Reading bedeutet, dass alle Readings eines Geretätyps
        bzw. genannte Readings an jedem Gerätetyp ignoriert werden. </p>
        <p>Beispiel:<br/>
        <code>attr &lt;dev&gt; globalTypeExclude MQTT MQTT_GENERIC_BRIDGE:* MQTT_BRIDGE:transmission-state *:baseID</code></p>
   </li>

   <li>
    <p>globalDeviceExclude<br/>
        Definiert Gerätenamen und Readings, die nicht übertragen werden.
        Werte können getrennt für jede Richtung (publish oder subscribe) vorangestellte Prefixe 'pub:' und 'sub:' angegeben werden.
        Ein einzelner Wert bedeutet, dass ein Gerät mit diesem Namen komplett ignoriert wird (also für alle seine Readings und beide Richtungen).
        Durch ein Doppelpunkt getrennte Paare werden als [sub:|pub:]Device:Reading interptretiert. 
        Das bedeutet, dass an dem gegebenen Gerät die genannte Readings nicht übertragen wird.</p>
        <p>Beispiel:<br/>
            <code>attr &lt;dev&gt; globalDeviceExclude Test Bridge:transmission-state</code></p>
   </li>

   <li>
    <p>forceNEXT<br/>
       Nur relevant, wenn MQTT2_CLIENT oder MQTT2_SERVER als IODev verwendet werden. Wird dieses Attribut auf 1 gesetzt, gibt MQTT_GENERIC_BRIDGE alle eingehenden Nachrichten an weitere Client Module (z.b. MQTT2_DEVICE) weiter, selbst wenn der betreffende Topic von einem von der MQTT_GENERIC_BRIDGE überwachten Gerät verwendet wird. Im Regelfall ist dies nicht erwünscht und daher ausgeschaltet, um unnötige <i>autocreates</i> oder Events an MQTT2_DEVICEs zu vermeiden. Siehe dazu auch das <a href="#MQTT2_CLIENTclientOrder">clientOrder Attribut</a> bei MQTT2_CLIENT bzw -SERVER; wird das Attribut in einer Instance von MQTT_GENERIC _BRIDGE gesetzt, kann das Auswirkungen auf weitere Instanzen haben.</p>
   </li>
   </li>
   </ul>
   <br>

   <li><p><b>Für die überwachten Geräte</b> wird eine Liste der möglichen Attribute automatisch um mehrere weitere Einträge ergänzt. <br>
      Sie fangen alle mit vorher mit dem in der Bridge definierten <a href="#MQTT_GENERIC_BRIDGEdefine">Prefix</a> an. <b>Über diese Attribute wird die eigentliche MQTT-Anbindung konfiguriert.</b><br>
      Als Standardwert werden folgende Attributnamen verwendet: <i>mqttDefaults</i>, <i>mqttAlias</i>, <i>mqttPublish</i>, <i>mqttSubscribe</i>.
      <br/>Die Bedeutung dieser Attribute wird im Folgenden erklärt.
    </p>
    <ul>
       <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a><br/>
            Hier wird eine Liste der "key=value"-Paare erwartet. Folgende Keys sind dabei möglich:
            <ul>
             <li>'qos' <br/>definiert ein Defaultwert für MQTT-Paramter 'Quality of Service'.</li>
             <li>'retain' <br/>erlaubt MQTT-Nachrichten als 'retained messages' zu markieren.</li>
             <li>'base' <br/>wird als Variable ($base) bei der Konfiguration von konkreten Topics zur Verfügung gestellt.
                   Sie kann entweder Text oder eine Perl-Expression enthalten. 
                   Perl-Expression muss in geschweifte Klammern eingeschlossen werden.
                   In einer Expression können folgende Variablen verwendet werden:
                   $base = entsprechende Definition aus dem '<a href="#MQTT_GENERIC_BRIDGEglobalDefaults">globalDefaults</a>', 
                   $reading = Original-Readingname, 
                   $device = Devicename und $name = Readingalias (s. <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>. 
                   Ist kein Alias definiert, ist $name=$reading).<br/>
                   Weiterhin können frei benannte Variablen definiert werden, die neben den oben genannten in den public/subscribe Definitionen 
                   verwendet werden können. Allerdings ist zu beachten, dass diese Variablen dort immer mit Anführungszeichen zu verwenden sind.
                   </li>
            </ul>
            <br/>
            Alle diese Werte können durch vorangestelle Prefixe ('pub:' oder 'sub') in ihrer Gültigkeit 
            auf nur Senden bzw. nur Empfangen begrenzt werden (soweit sinnvoll). 
            Werte für 'qos' und 'retain' werden nur verwendet, 
            wenn keine explizite Angaben darüber für ein konkretes Topic gemacht worden sind.</p>
            <p>Beispiel:<br/>
                <code>attr &lt;dev&gt; mqttDefaults base={"TEST/$device"} pub:qos=0 sub:qos=2 retain=0</code></p>
        </p>
    </li>
 

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a><br/>
            Dieses Attribut ermöglicht Readings unter einem anderen Namen auf MQTT-Topic zu mappen. 
            Dies ist dann sinnvoll, wenn entweder Topicdefinitionen Perl-Expressions mit entsprechenden Variablen sind oder der Alias dazu dient, aus MQTT-Sicht standardisierte Readingnamen zu ermöglichen.
            Auch hier werden 'pub:' und 'sub:' Prefixe unterstützt (für 'subscribe' gilt das Mapping quasi umgekehrt).
            <br/></p>
            <p>Beispiel:<br/>
                <code>attr &lt;dev&gt; mqttAlias pub:temperature=temp</code></p>
                <i>temperature</i> ist dabei der Name des Readings in FHEM.
        </p>
    </li>
  
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a><br/>
            Hier werden konkrete Topics definiert und den Readings zugeordnet (Format: &lt;reading&gt;:topic=&lt;topic&gt;). 
            Weiterhin können diese einzeln mit 'qos'- und 'retain'-Flags versehen werden. <br/>
            Topics können auch als Perl-Expression mit Variablen definiert werden ($device, $reading, $name, $base sowie ggf. über <a href="#MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a> weitere).<br/><br/>
            'topic' kann auch als 'readings-topic' geschrieben werden.<br/>
            Werte für mehrere Readings können auch gemeinsam gleichzeitig definiert werden, 
            indem sie, mittels '|' getrennt, zusammen angegeben werden.<br/>
            Wird anstatt eines Readingsnamen ein '*' verwendet, gilt diese Definition für alle Readings, 
            für die keine expliziten Angaben gemacht wurden.<br/>
            Neben Readings können auch Attributwerte gesendet werden ('atopic' oder 'attr-topic').<br/>
            Sollten für ein Event mehrere Nachrichten (sinnvollerweise an verschiedene Topics) versendet werden, müssen jeweilige Definitionen durch Anhängen von
             einmaligen Suffixen (getrennt von dem Readingnamen durch ein !-Zeichen) unterschieden werden: reading!1:topic=... reading!2:topic=....<br/>
            Weiterhin können auch Expressions (reading:expression=...) definiert werden. <br/>
            Die Expressions können sinnvollerweise entweder Variablen ($value, $topic, $qos, $retain, $message, $uid) verändern, oder einen Wert != undef zurückgeben.<br/>
            Der Rückgabewert wird als neuer Nachrichten-Value verwendet, die Änderung der Variablen hat dabei jedoch Vorrang.<br/>
            Ist der Rückgabewert <i>undef</i>, dann wird das Setzen/Ausführen unterbunden. <br/>
            Ist die Rückgabe ein Hash (nur 'topic'), werden seine Schlüsselwerte als Topic verwendet, 
            die Inhalte der Nachrichten sind entsprechend die Werte aus dem Hash.</p>
            <p>Option 'resendOnConnect' erlaubt eine Speicherung der Nachrichten, 
            wenn keine Verbindung zu dem MQTT-Server besteht.
            Die zu sendende Nachrichten werden in einer Warteschlange gespeichert. 
            Wird die Verbindung aufgebaut, werden die Nachrichten in der ursprüngichen Reihenfolge verschickt.
            <ul>Mögliche Werte: 
              <li>none<br/>alle verwerfen</li>
              <li>last<br/>immer nur die letzte Nachricht speichern</li>
              <li>first<br/>immer nur die erste Nachricht speichern, danach folgende verwerfen</li>
              <li>all<br/>alle speichern, allerdings existiert eine Obergrenze von 100, 
              wird es mehr, werden älteste überzählige Nachrichten verworfen.</li>
            </ul>
            </p>
            <p>Beispiele:<br/>
                <code> attr &lt;dev&gt; mqttPublish temperature:topic={"$base/$name"} temperature:qos=1 temperature:retain=0 *:topic={"$base/$name"} humidity:topic=TEST/Feuchte<br/>
                attr &lt;dev&gt; mqttPublish temperature|humidity:topic={"$base/$name"} temperature|humidity:qos=1 temperature|humidity:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} *:qos=2 *:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={$value="message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"TEST/Topic1"=>"$message", "TEST/Topic2"=>"message: $message"}</br>
                attr &lt;dev&gt; mqttPublish [...] *:resendOnConnect=last<br/>
                attr &lt;dev&gt; mqttPublish temperature:topic={"$base/temperature/01/value"} temperature!json:topic={"$base/temperature/01/json"}
                   temperature!json:expression={toJSON({value=>$value,type=>"temperature",unit=>"°C",format=>"00.0"})}<br/>
                </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a><br/>
            Dieses Attribut konfiguriert das Empfangen der MQTT-Nachrichten und die entsprechenden Reaktionen darauf.<br/>
            Die Konfiguration ist ähnlich der für das 'mqttPublish'-Attribut. Es können Topics für das Setzen von Readings ('topic' oder auch 'readings-topic') und
            Aufrufe von 'set'-Befehl an dem Gerät ('stopic' oder 'set-topic') definiert werden. <br/>
            Attribute können ebenfalls gesetzt werden ('atopic' oder 'attr-topic').</br>
            Mit Hilfe von zusätzlichen auszuführenden Perl-Expressions ('expression') kann das Ergebnis vor dem Setzen/Ausführen noch beeinflußt werden.<br/>
            In der Expression sind die folgenden Variablen verfügbar: $device, $reading, $message (initial gleich $value).
            Die Expression kann dabei entweder die Variable $value verändern, oder einen Wert != undef zurückgeben. Redefinition der Variable hat Vorrang.
            Ist der Rückgabewert <i>undef</i>, dann wird das Setzen/Ausführen unterbunden (es sei denn, $value hat einen neuen Wert). <br/>
            Ist die Rückgabe ein Hash (nur für 'topic' und 'stopic'), dann werden seine Schlüsselwerte als Readingsnamen bzw. 'set'-Parameter verwendet,  
            die zu setzenden Werte sind entsprechend den Werten aus dem Hash.<br/>
            Weiterhin kann das Attribut 'qos' angegeben werden ('retain' macht dagegen keinen Sinn).<br/>
            In der Topic-Definition können MQTT-Wildcards (+ und #) verwendet werden. <br/>
            Falls der Reading-Name mit einem '*'-Zeichen am Anfang definiert wird, gilt dieser als 'Platzhalter'.
            Mehrere Definitionen mit '*' sollten somit z.B. in folgender Form verwendet werden: *1:topic=... *2:topic=...
            Der tatsächliche Name des Readings (und ggf. des Gerätes) wird dabei durch Variablen aus dem Topic 
            definiert ($device (nur für globale Definition in der Bridge), $reading, $name).
            Im Topic wirken diese Variablen als Wildcards, was evtl. dann sinnvoll ist, wenn der Reading-Name nicht fest definiert ist 
            (also mit '*' anfängt, oder mehrere Namen durch '|' getrennt definiert werden).  <br/>
            Die Variable $name wird im Unterschied zu $reading ggf. über die in 'mqttAlias' definierten Aliase beeinflusst.
            Auch Verwendung von $base ist erlaubt.<br/>
            Bei Verwendung von 'stopic' wird der 'set'-Befehl als 'set &lt;dev&gt; &lt;reading&gt; &lt;value&gt;' ausgeführt.
            Um den set-Befehl direkt am Device ohne Angabe eines Readingnamens auszuführen (also 'set &lt;dev&gt; &lt;value&gt;') muss als Reading-Name 'state' verwendet werden.</p>
            <p>Um Nachrichten im JSON-Format zu empfangen, kann mit Hilfe von 'expression' direkt die in fhem.pl bereitgestellte Funktion <i>json2nameValue()</i> aufgerufen werden, als Parameter ist <i>$message</i> anzugeben.</p>
            <p>Einige Beispiele:<br/>
                <code>attr &lt;dev&gt; mqttSubscribe temperature:topic=TEST/temperature test:qos=0 *:topic={"TEST/$reading/value"} <br/>
                    attr &lt;dev&gt; mqttSubscribe desired-temperature:stopic={"TEST/temperature/set"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={...}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={$value="x"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"TEST/light/set"} state:expression={"R1"=>$value, "R2"=>"Val: $value", "R3"=>"x"}
                    attr &lt;dev&gt; mqttSubscribe verbose:atopic={"TEST/light/verbose"}
                    attr &lt;dev&gt; mqttSubscribe json:topic=XTEST/json json:expression={json2nameValue($message)}
</code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttForward">mqttForward</a><br/>
            Dieses Attribut definiert was passiert, wenn eine und dasselbe Reading sowohl aboniert als auch gepublisht wird. 
            Mögliche Werte: 'all' und 'none'. <br/>
            Bei 'none' werden per MQTT angekommene Nachrichten nicht aus dem selben Gerät per MQTT weiter gesendet.<br/>
            Die Einstellung 'all' bewirkt das Gegenteil, also damit wird das Weiterleiten ermöglicht.<br/>
            Fehlt dieser Attribut, dann wird standardmäßig für alle Gerätetypen außer 'Dummy' die Einstellung 'all' angenommen 
            (damit können Aktoren Befehle empfangen und ihre Änderungen im gleichem Zug weiter senden) 
            und für Dummies wird 'none' verwendet. Das wurde so gewählt,  da dummy von vielen Usern als eine Art GUI-Schalterelement verwendet werden. 
            'none' verhindert hier unter Umständen das Entstehen einer Endlosschleife der Nachrichten.

            </p>
        </p>
    </li>
    
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDisable">mqttDisable</a><br/>
            Wird dieses Attribut in einem Gerät gesetzt, wird dieses Gerät vom Versand  bzw. Empfang der Readingswerten ausgeschlossen.</p>
        </p>
    </li>
  </ul>
 </li>
</ul>
 
<p><b>Beispiele</b></p>

<ul>
    <li>
        <p>Bridge für alle möglichen Geräte mit dem Standardprefix:<br/>
                <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE<br/>
                        attr mqttGeneric IODev mqtt</code>
        </p>
        </p>
    </li>
    
    <li>
        <p>Bridge mit dem Prefix 'mqttSensors' für drei bestimmte Geräte:<br/>
            <code> defmod mqttGeneric MQTT_GENERIC_BRIDGE mqttSensors sensor1,sensor2,sensor3<br/>
                    attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>

    <li>
        <p>Bridge für alle Geräte in einem bestimmten Raum:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE mqtt room=Wohnzimmer<br/>
                attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>
     
    <li>
        <p>Einfachste Konfiguration eines Temperatursensors:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttPublish temperature:topic=haus/sensor/temperature</code></p>
        </p>
    </li>

    <li>
        <p>Alle Readings eines Sensors (die Namen werden unverändet übergeben) per MQTT versenden:<br/>
            <code> defmod sensor XXX<br/>
                attr sensor mqttPublish *:topic={"sensor/$reading"}</code></p>
        </p>
    </li>
     
    <li>
        <p>Topic-Definition mit Auslagerung des gemeinsamen Teilnamens in 'base'-Variable:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttDefaults base={"/$device/$reading"}<br/>
                attr sensor mqttPublish *:topic={"$base"}</code></p>
        </p>
    </li>

    <li>
        <p>Topic-Definition nur für bestimmte Readings mit deren gleichzeitigen Umbennenung (Alias):<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttAlias temperature=temp humidity=hum<br/>
                attr sensor mqttDefaults base={"/$device/$name"}<br/>
                attr sensor mqttPublish temperature:topic={"$base"} humidity:topic={"$base"}<br/></code></p>
        </p>
    </li>

    <li>
        <p>Beispiel für eine zentrale Konfiguration in der Bridge für alle Devices, die Reading 'temperature' besitzen:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish temperature:topic={"haus/$device/$reading"} <br/>
         </code></p>
        </p>
    </li>

    <li>
        <p>Beispiel für eine zentrale Konfiguration in der Bridge für alle Devices <br/>
                (wegen einer schlechten Übersicht und einer unnötig grossen Menge eher nicht zu empfehlen!):<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish *:topic={"haus/$device/$reading"} <br/></code></p>
        </p>
    </li>
</ul>

<p><b>Einschränkungen:</b></p>

<ul>
      <li>Wenn mehrere Readings das selbe Topic abonnieren, sind dabei keine unterschiedlichen QOS möglich.</li>
      <li>Wird in so einem Fall QOS ungleich 0 benötigt, sollte dieser entweder für alle Readings gleich einzeln definiert werden,
      oder allgemeingültig über Defaults. <br/>
      Ansonsten wird beim Erstellen von Abonnements der erst gefundene Wert verwendet. </li>
      <li>Abonnements werden nur erneuert, wenn sich das Topic ändert; QOS-Flag-Änderung alleine wirkt sich daher erst nach einem Neustart aus.</li>
</ul>

<!--TODO-->
<!--
<p><b>Ideen:</b></p>
<ul>
  <li>global Subscribe</li>
  <li>global excludes</li>
  <li>QOS for subscribe (fertig?), defaults(qos, fertig?), alias mapping</li>
  <li>resendOnConnect (no, first, last, all)</li>
  <li>resendInterval (no/0, x min)</li>
  <li>templates (template in der Bridge, mqttUseTemplate in Device)</li>
</ul>
-->

=end html_DE
=cut
