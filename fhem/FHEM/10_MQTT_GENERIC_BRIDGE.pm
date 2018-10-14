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
# 14.10.2018 0.9.9
#   change   :  'mqttForward' dokumentiert
#   improved :  Laden von MQTT-Modul in BEGIN-Block verlagert. 
#               Es gab Meldungen ueber Probleme (undefined subroutine) wenn
#               MQTT-Modul in fhem.cfg nach dem Bridge-Modul stand.
#
# 11.10.2018 0.9.9
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
# 30.09.2018 0.9.9
#   feature finished: globalTypeExclude und globalDeviceExclude incl. Commandref
#   bugfix   : initialization
#
# 29.09.2018 0.9.9
#   quick fix: received messages forward exclude for 'dummy'
# 
# 27.09.2018 0.9.9
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
# 25.09.2018 0.9.8
#   feature  : no-trigger-topic - wie readings-topic, es wird jedoch 
#              beim Update kein Trigger gesendet.
# 
# 23.09.2018 0.9.8
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
# 21.09.2019 0.9.7 
#   fix      : Anlegen / Loeschen von userAttr
#   change   : Vorbereitungen fuer resendOnConnect
# 
# 16.09.2018 0.9.7 
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

# Ideen:
#
# [done]
#  - global base (sollte in $base verwendet werden koennen)
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
#  - Support for MQTT2_SERVER
#  - commands per mqtt fuer die Bridge: Liste der Geraete, Infos dazu etc.
#  - mqttOptions (zuschaltbare optionen im Form eines Perl-Routine) (json, ttl)
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
#   - Zeilenumbruch wird nicht als Trennen zw. topic-Definitionen erkannt, nur mit einem zusaetzlichen Leerzeichen
#   - Keys enthalten Zeilenumbrueche (topic, expression) => Namen der Readings etc. trimmen bzw. Parser anpassen
#   - Variablen in Expression funktionieren nicht, wenn Topic kein perl-Expression ist
#   - atopic wird in devInfo nicht dargestellt
#   - beim Aendern von mqttXXX und globalXXX mit Zeilenumbruechen werden interne Tabellen nicht aktualisiert
#
# [testing]
# 
# [works for me] 
#   - von mehreren sich gleichzeitig aendernden Readings wird nur eine gepostet
#
# [open]
#

use strict;
use warnings;

#my $DEBUG = 1;
my $cvsid = '$Id$';
my $VERSION = "version 0.9.9 by hexenmeister\n$cvsid";

my %sets = (
);

my %gets = (
  "version"   => "noArg",
  "devlist"   => "",
  "devinfo"   => ""
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

sub MQTT_GENERIC_BRIDGE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT::GENERIC_BRIDGE::Define";
  $hash->{UndefFn}  = "MQTT::GENERIC_BRIDGE::Undefine";
  $hash->{GetFn}    = "MQTT::GENERIC_BRIDGE::Get";
  $hash->{NotifyFn} = "MQTT::GENERIC_BRIDGE::Notify";
  $hash->{AttrFn}   = "MQTT::GENERIC_BRIDGE::Attr";
  $hash->{OnMessageFn} = "MQTT::GENERIC_BRIDGE::onmessage";

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
    $main::readingFnAttributes;

    #main::LoadModule("MQTT");

    # Beim ModulReload Deviceliste loeschen (eig. nur fuer bei der Entwicklung nuetzich)
    #if($DEBUG) {
    #if($hash->{'.debug'}) {
      foreach my $d (keys %defs) {
        if(defined($defs{$d}{TYPE})) {
          if($defs{$d}{TYPE} eq "MQTT_GENERIC_BRIDGE") {
            $defs{$d}{".initialized"} = 0;
          }
        }
      }
    #}

    $hash->{'.debug'} = '0';
}

package MQTT::GENERIC_BRIDGE;

use strict;
use warnings;
use GPUtils qw(:all);

use Net::MQTT::Constants;

#if ($DEBUG) {
  use Data::Dumper;
##   $gets{"debugInfo"}="noArg";
##   $gets{"debugReinit"}="noArg";
#}

BEGIN {
  main::LoadModule("MQTT");
  MQTT->import(qw(:all));

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
    CTRL_ATTR_NAME_DEFAULTS
    CTRL_ATTR_NAME_ALIAS
    CTRL_ATTR_NAME_PUBLISH
    CTRL_ATTR_NAME_SUBSCRIBE
    CTRL_ATTR_NAME_IGNORE
    CTRL_ATTR_NAME_FORWARD
    CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE
    CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE
    CTRL_ATTR_NAME_GLOBAL_PREFIX
  ))

};

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

sub publishDeviceUpdate($$$$$);
sub UpdateSubscriptionsSingleDevice($$);
sub InitializeDevices($);
sub firstInit($);
sub removeOldUserAttr($;$$$);
sub IsObservedAttribute($$);
sub defineGlobalTypeExclude($;$);
sub defineGlobalDevExclude($;$);
sub defineDefaultGlobalExclude($);
sub isTypeDevReadingExcluded($$$$$);
sub getDevicePublishRecIntern($$$$$);
sub getDevicePublishRec($$$);
sub isConnected($);
sub ioDevConnect($);
sub ioDevDisconnect($);
sub updateDevCount($);
sub retrieveIODev($);
sub isIODevMQTT2($);
sub isIODevMQTT($);
sub initUserAttr($);
sub createRegexpForTopic($);
sub isDebug($);
sub checkPublishDeviceReadingsUpdates($$);
sub RefreshGlobalTableAll($);

###############################################################################
# prueft, ob debug Attribute auf 1 gesetzt ist (Debugmode)
sub isDebug($) {
  my ($hash) = @_;
  return AttrVal($hash->{NAME},"debug",0);  
}

# Entfernt Leerzeichen vom string vorne und hinten
sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s }

# prueft, ob der erste gegebene String mit dem zweiten anfaengt
sub startsWith($$) {
  my($str, $subStr) = @_;
  return substr($str, 0, length($subStr)) eq $subStr;
}

###############################################################################
# Device define
sub Define() {
  my ($hash, $def) = @_;
  # Definition :=> defmod mqttGeneric MQTT_GENERIC_BRIDGE [prefix] [devspec,[devspec]]
  my($name, $type, $prefix, @devspeca) = split("[ \t][ \t]*", $def);
  # restlichen Parameter nach Leerzeichen trennen
  # aus dem Array einen kommagetrennten String erstellen
  my $devspec = join(",", @devspeca);
  # Doppelte Kommas entfernen.
  $devspec =~s/,+/,/g;
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
  $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT} = 0 unless defined $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT} = 0 unless defined $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT} = 0 unless defined $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT};
  $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT} = 0 unless defined $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT};

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
  
  # noetig hier beim Anlegen im laufendem Betrieb
  firstInit($hash);

  return undef;
}

# Device undefine
sub Undefine() {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  MQTT::client_stop($hash) if isIODevMQTT($hash); #if defined($hash->{+HELPER}->{+IO_DEV_TYPE}) and $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT';
  removeOldUserAttr($hash);
}

# liefert TYPE des IODev, wenn definiert (MQTT; MQTT2,..)
sub retrieveIODev($) {
  my ($hash) = @_;
  my $iodn = AttrVal($hash->{NAME}, "IODev", undef);
  my $iodt = undef;
  if(defined($iodn) and defined($defs{$iodn})) {
    $iodt = $defs{$iodn}{TYPE};
  }
  $hash->{+HELPER}->{+IO_DEV_TYPE} =  $iodt;
  return $hash->{+HELPER}->{+IO_DEV_TYPE};
}

# prueft, ob IODev MQTT-Instanz ist
sub isIODevMQTT($) {
  my ($hash) = @_;
  my $iodt = retrieveIODev($hash);
  return 0 unless defined $iodt;
  return 0 unless $iodt eq 'MQTT';
  return 1;
}

# prueft, ob IODev MQTT2-Instanz ist
sub isIODevMQTT2($) {
  my ($hash) = @_;
  my $iodt = retrieveIODev($hash);
  return 0 unless defined $iodt;
  return 0 unless $iodt eq 'MQTT2_SERVER';
  return 1;
}

# Fuegt notwendige UserAttr hinzu
sub initUserAttr($) {
  my ($hash) = @_;
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
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> initUserAttr> devspec: '$devspec', array: ".Dumper(@devices));
  foreach my $dev (@devices) {
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
sub firstInit($) {
  my ($hash) = @_;
  
  # IO    
  AssignIoPort($hash);

  if ($main::init_done) {
    $hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 0;

    return unless defined(AttrVal($hash->{NAME},"IODev",undef));

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
      readingsSingleUpdate($hash,"transmission-state","IO device initialized",1);
    } elsif (isIODevMQTT2($hash)) {
      readingsSingleUpdate($hash,"transmission-state","unsupported IO device",1);
    } else {
      readingsSingleUpdate($hash,"transmission-state","unknown IO device",1);
    }

    $hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 1;

    # senden attr changes at start:
    # im firstinit schleife ueber alle devices im map und bei mode 'A' senden
    # publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, $val);
    # ggf. vorkehrungen treffen, falls nicht connected

  }
}

# Vom Timer periodisch aufzurufende Methode
sub timerProc($) {
  my ($hash, $refresh_all) = @_;
  my $name = $hash->{NAME};

  # TODO: Resend
  # timerProc=> wenn autoresend an dev-map, dann dev-map nach lasttime durchsuchen

  RemoveInternalTimer($hash);
  if(defined($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}) && ($hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL} ne '0')) {
    InternalTimer(gettimeofday()+$hash->{+HELPER}->{+HS_PROP_NAME_INTERVAL}, "MQTT::GENERIC_BRIDGE::timerProc", $hash, 0);
  }
}

# prueft, ob Verbindung zum MQTT-Broker besteht.
# Parameter: Bridge-Hash
sub isConnected($) {
  my $hash = shift;
  return MQTT::isConnected($hash->{IODev}) if isIODevMQTT($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT';
  return 1 if isIODevMQTT2($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';
}

# Berechnet Anzahl der ueberwachten Geraete neu
sub updateDevCount($) {
  my $hash = shift;
  # device count
  my $size = 0;
  foreach my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
    if($dname ne ":global") {
      $size++;
    }
  }
  $hash->{+HELPER}->{+HS_PROP_NAME_DEVICE_CNT} = $size;
  readingsSingleUpdate($hash,"device-count",$size,1);
}

# loescht angelegte userattr aus den jeweiligen Devices (oder aus dem global-Device)
# Parameter: 
#   $hash:    Bridge-hash
#   $prefix:  Attribute (publish, subscribe, defaults und alis) mit diesem Prefix werden entfernt
#   $devspec: definiert Geraete, deren userattr bereinigt werden
# Die letzten zwei Parameter sind optinal, fehlen sie, werden werte aus dem Hash genommen.
sub removeOldUserAttr($;$$$) {
  my ($hash, $prefix, $devspec, $newDevices) = @_;
  #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> [$hash->{NAME}] newDevices: ".Dumper($newDevices));

  $prefix = $hash->{+HS_PROP_NAME_PREFIX} unless defined $prefix;
  # Pruefen, on ein weiteres Device (MQTT_GENERIC_BRIDGE) mit dem selben Prefix existiert (waere zwar Quatsch, aber dennoch)
  my @bridges = devspec2array("TYPE=MQTT_GENERIC_BRIDGE");
  my $name = $hash->{NAME};
  foreach my $dev (@bridges) {
    if($dev ne $name) {
      my $aPrefix = $defs{$dev}->{+HS_PROP_NAME_PREFIX};
      return if ($aPrefix eq $prefix);
    }
  }
  $devspec = $hash->{+HS_PROP_NAME_DEVSPEC} unless defined $devspec;
  $devspec = 'global' if ($devspec eq '.*');
  # kann spaeter auch delFromDevAttrList Methode genutzt werden
  my @devices = devspec2array($devspec);

  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> removeOldUserAttr> devspec: $devspec, array: ".Dumper(@devices));
  foreach my $dev (@devices) {
    next if grep {$_ eq $dev} @{$newDevices};
    #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> removeOldUserAttr> delete: from $dev ".$prefix.CTRL_ATTR_NAME_DEFAULTS);
    # O> subs aus fhem.pl nicht nutzen, da diese auch die Steuerungsattribute mit loescht. Vor allem bei global ist das ein Problem
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_DEFAULTS.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_ALIAS.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_PUBLISH.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_SUBSCRIBE.":textField-long");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_IGNORE.":both,incoming,outgoing");
    # delFromDevAttrList($dev,$prefix.CTRL_ATTR_NAME_FORWARD.":all,none");
    # => stattdessen selbst loeschen (nur die 'userattr')
    my $ua = $main::attr{$dev}{userattr};
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
      if(!keys %h && defined($main::attr{$dev}{userattr})) {
        # ganz loeschen, wenn nichts mehr drin
        delete $main::attr{$dev}{userattr};
      } else {
        $main::attr{$dev}{userattr} = join(" ", sort keys %h);
      }
    }
  }
}

# Prueft, ob der gegebene Zeichenkette einem der zu ueberwachenden Device-Attributennamen entspricht.
sub IsObservedAttribute($$) {
  my ($hash, $aname) = @_;
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

  return undef;
}

# Internal. Legt Defaultwerte im Map ab. Je nach Schluessel werden die Werte fuer 'pub:', 'sub:' oder beides abgelegt.
# Parameter:
#   $map:     Werte-Map (Ziel)
#   $dev:     Devicename
#   $valMap:  Map mit den Werten (Quelle)
#   $key:     Schluessel. Unter Inhalt aus dem Quellmap unter diesem Schluessel wird in Zielmap kopiert.
sub _takeDefaults($$$$) {
  my ($map, $dev, $valMap, $key) = @_;
  if (defined($valMap->{$key})) {
    # ggf. nicht ueberschreiben (damit nicht undefiniertes VErhalten entsteht,
    # wenn mit und ohne Prefx gleichzeitig angegeben wird. So wird die Definition mit Prefix immer gewinnen)
    $map->{$dev}->{':defaults'}->{'pub:'.$key}=$valMap->{$key} unless defined $map->{$dev}->{':defaults'}->{'pub:'.$key};
    $map->{$dev}->{':defaults'}->{'sub:'.$key}=$valMap->{$key} unless defined $map->{$dev}->{':defaults'}->{'sub:'.$key};
  }
  $map->{$dev}->{':defaults'}->{'pub:'.$key}=$valMap->{'pub:'.$key} if defined($valMap->{'pub:'.$key});
  $map->{$dev}->{':defaults'}->{'sub:'.$key}=$valMap->{'sub:'.$key} if defined($valMap->{'sub:'.$key});
}

# Erstellt Strukturen fuer 'Defaults' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrDefaults($$$$) {
  my($hash, $dev, $map, $attrVal) = @_;
  # collect defaults
  delete ($map->{$dev}->{':defaults'});
  if(defined $attrVal) {
    # format: [pub:|sub:]base=ha/wz/ [pub:|sub:]qos=0 [pub:|sub:]retain=0
    my($unnamed, $named) = MQTT::parseParams($attrVal,'\s',' ','='); #main::parseParams($attrVal);
    foreach my $param (keys %{$named}) {
      _takeDefaults($map, $dev, $named, $param);
    }
    # _takeDefaults($map, $dev, $named, 'base');
    # _takeDefaults($map, $dev, $named, 'qos');
    # _takeDefaults($map, $dev, $named, 'retain');
    # _takeDefaults($map, $dev, $named, 'expression');
    return defined($map->{$dev}->{':defaults'});
  } else {
    return undef;
  }
}

# Erstellt Strukturen fuer 'Alias' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrAlias($$$$) {
  my($hash, $dev, $map, $attrVal) = @_;
  delete ($map->{$dev}->{':alias'});
  if(defined $attrVal) {
    # format [pub:|sub:]<reading>[=<newName>] ...
    my($unnamed, $named) = MQTT::parseParams($attrVal,'\s',' ','='); #main::parseParams($attrVal);
    if(defined($named)){
      foreach my $param (keys %{$named}) {
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
          $map->{$dev}->{':alias'}->{"pub:".$name}=$val unless defined $map->{$dev}->{':alias'}->{"pub:".$name};
          $map->{$dev}->{':alias'}->{"sub:".$name}=$val unless defined $map->{$dev}->{':alias'}->{"sub:".$name};
        }
      }
      return defined($map->{$dev}->{':alias'});
    }
  }
  return undef;
}

# Erstellt Strukturen fuer 'Publish' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrPublish($$$$) {
  my($hash, $dev, $map, $attrVal) = @_;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrPublish: $dev, $attrVal, ".Dumper($map));
  # collect publish topics
  delete ($map->{$dev}->{':publish'});
  if(defined $attrVal) {
    # format: 
    #   <reading|alias>:topic=<"static topic"|{evaluated (first time only) topic 
    #     (avialable vars: $base, $reading (oringinal name), $name ($reading oder alias))}>
    #   <reading>:qos=0 <reading>:retain=0 ... 
    #  wildcards:
    #   *:qos=0 *:retain=0 ...
    #   *:topic=<{}> wird jedesmal ausgewertet und ggf. ein passendes Eintrag im Map erzeugt
    #   *:topic=# same as *:topic={"$base/$reading"}
    my($unnamed, $named) = MQTT::parseParams($attrVal,'\s',' ','=');
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrPublish: parseParams: ".Dumper($named));
    if(defined($named)){
      my $autoResend = {};
      foreach my $param (keys %{$named}) {
        my $val = $named->{$param};
        my($name,$ident) = split(":",$param);
        if(!defined($ident) or !defined($name)) { next; }
        if(($ident eq 'topic') or ($ident eq 'readings-topic') or 
          ($ident eq 'atopic') or ($ident eq 'attr-topic') or
          ($ident eq 'qos') or ($ident eq 'retain') or 
          ($ident eq 'expression') or
          ($ident eq 'resendOnConnect') or
          ($ident eq 'autoResendInterval')) {
          my @nameParts = split(/\|/, $name);
          while (@nameParts) {
            my $namePart = shift(@nameParts);
            next if($namePart eq "");
            $map->{$dev}->{':publish'}->{$namePart}->{$ident}=$val;

            $map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'R' if (($ident eq 'topic') or ($ident eq 'readings-topic'));
            $map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'S' if (($ident eq 'stopic') or ($ident eq 'set-topic'));
            $map->{$dev}->{':publish'}->{$namePart}->{'mode'} = 'A' if (($ident eq 'atopic') or ($ident eq 'attr-topic'));

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
    }
  }

  return undef;
}

# Sucht nach device/reading in der Dev-Map und speichert aktuellen dort den Zeitstempel
sub updatePubTime($$$) {
  my ($hash,$device,$reading) = @_;
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
}

# sucht zu den gegebenen device und reading die publish-Eintraege (topic, qos, retain)
# verwendet device-record und beruecksichtigt defaults und globals
# parameter: $hash, device-name, reading-name
sub getDevicePublishRec($$$) {
  my($hash, $dev, $reading) = @_;
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  return undef unless defined $map;
  
  my $devMap = $map->{$dev};
  my $globalMap = $map->{':global'};

  return getDevicePublishRecIntern($hash, $devMap, $globalMap, $dev, $reading);
}

# sucht zu den gegebenen device und reading die publish-Eintraege (topic, qos, retain) 
# in den uebergebenen Maps
# verwendet device-record und beruecksichtigt defaults und globals
# parameter: $hash, map, globalMap, device-name, reading-name
sub getDevicePublishRecIntern($$$$$) {
  my($hash, $devMap, $globalMap, $dev, $reading) = @_;

  # publish map
  my $publishMap = $devMap->{':publish'};
  my $globalPublishMap = $globalMap->{':publish'};
  #return undef unless defined $publishMap;

  # reading map
  my $readingMap = $publishMap->{$reading} if defined $publishMap;
  my $defaultReadingMap = $publishMap->{'*'} if defined $publishMap;
  
  # global reading map
  my $globalReadingMap = $globalPublishMap->{$reading} if defined $globalPublishMap;
  my $globalDefaultReadingMap = $globalPublishMap->{'*'} if defined $globalPublishMap;

  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> getDevicePublishRec> readingMap ".Dumper($readingMap));
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> getDevicePublishRec> defaultReadingMap ".Dumper($defaultReadingMap));
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> getDevicePublishRec> readingMap ".Dumper($globalReadingMap));
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> getDevicePublishRec> defaultReadingMap ".Dumper($globalDefaultReadingMap));
  # topic
  my $topic = undef;
  $topic = $readingMap->{'topic'} if defined $readingMap;
  $topic = $defaultReadingMap->{'topic'} if (defined($defaultReadingMap) and !defined($topic));

  # global topic
  $topic = $globalReadingMap->{'topic'} if (defined($globalReadingMap) and !defined($topic));
  $topic = $globalDefaultReadingMap->{'topic'} if (defined($globalDefaultReadingMap) and !defined($topic));

  # attr-topic
  my $atopic = undef;
  $atopic = $readingMap->{'atopic'} if defined $readingMap;
  $atopic = $defaultReadingMap->{'atopic'} if (defined($defaultReadingMap) and !defined($atopic));

  # global attr-topic
  $atopic = $globalReadingMap->{'atopic'} if (defined($globalReadingMap) and !defined($atopic));
  $atopic = $globalDefaultReadingMap->{'atopic'} if (defined($globalDefaultReadingMap) and !defined($atopic));

  # qos & retain & expression
  my($qos, $retain, $expression) = retrieveQosRetainExpression($globalDefaultReadingMap, $globalReadingMap, $defaultReadingMap, $readingMap);
  
  # wenn kein topic und keine expression definiert sind, kann auch nicht gesendet werden, es muss nichts mehr ausgewertet werden
  return unless (defined($topic) or defined($atopic) or defined( $expression));

  # resendOnConnect Option
  my $resendOnConnect = undef;
  $resendOnConnect = $readingMap->{'resendOnConnect'} if defined $readingMap;
  $resendOnConnect = $defaultReadingMap->{'resendOnConnect'} if (defined($defaultReadingMap) and !defined($resendOnConnect));  
  # global
  $resendOnConnect = $globalReadingMap->{'resendOnConnect'} if (defined($globalReadingMap) and !defined($resendOnConnect));
  $resendOnConnect = $globalDefaultReadingMap->{'resendOnConnect'} if (defined($globalDefaultReadingMap) and !defined($resendOnConnect));

  # map name
  my $name = undef;
  if (defined($devMap) and defined($devMap->{':alias'})) {
    $name = $devMap->{':alias'}->{'pub:'.$reading};
  }
  if (defined($globalMap) and defined($globalMap->{':alias'}) and !defined($name)) {
    $name = $globalMap->{':alias'}->{'pub:'.$reading};
  }
  $name = $reading unless defined $name;

  # get mode
  my $mode = $readingMap->{'mode'};

  # compute defaults
  my $combined = computeDefaults($hash, 'pub:', $globalMap, $devMap, {'device'=>$dev,'reading'=>$reading,'name'=>$name,'mode'=>$mode});
  # $topic evaluieren (avialable vars: $device (device name), $reading (oringinal name), $name ($reading oder alias, if defined), defaults)
  if(defined($topic) and ($topic =~ m/^{.*}$/)) {
    $topic = _evalValue2($hash->{NAME},$topic,{'topic'=>$topic,'device'=>$dev,'reading'=>$reading,'name'=>$name,%$combined}) if defined $topic;
  }
  if(defined($atopic) and ($atopic =~ m/^{.*}$/)) {
    $atopic = _evalValue2($hash->{NAME},$atopic,{'topic'=>$atopic,'device'=>$dev,'reading'=>$reading,'name'=>$name,%$combined}) if defined $atopic;
  }

  return {'topic'=>$topic,'atopic'=>$atopic,'qos'=>$qos,'retain'=>$retain,
          'expression'=>$expression,'name'=>$name,'mode'=>$mode,
          'resendOnConnect'=>$resendOnConnect,'.defaultMap'=>$combined};
}

# sucht Qos, Retain, Expression Werte unter Beruecksichtigung von Defaults und Globals
sub retrieveQosRetainExpression($$$$) {
  my($globalDefaultReadingMap, $globalReadingMap, $defaultReadingMap, $readingMap) = @_;
  my $qos=undef;
  my $retain = undef;
  my $expression = undef;

  if(defined $readingMap) {
    $qos =          $readingMap->{'qos'};
    $retain =       $readingMap->{'retain'};
    $expression =   $readingMap->{'expression'};
    if(defined($readingMap->{':defaults'})) {
      $qos =        $readingMap->{':defaults'}->{'pub:qos'} unless defined $qos;
      $retain =     $readingMap->{':defaults'}->{'pub:retain'} unless defined $retain;
      $expression = $readingMap->{':defaults'}->{'expression'} unless defined $expression;
    }
  }

  if(defined $defaultReadingMap) {
    $qos =          $defaultReadingMap->{'qos'} unless defined $qos;
    $retain =       $defaultReadingMap->{'retain'} unless defined $retain;
    $expression =   $defaultReadingMap->{'expression'} unless defined $expression;
    if(defined($defaultReadingMap->{':defaults'})) {
      $qos =        $defaultReadingMap->{':defaults'}->{'pub:qos'} unless defined $qos;
      $retain =     $defaultReadingMap->{':defaults'}->{'pub:retain'} unless defined $retain;
      $expression = $defaultReadingMap->{':defaults'}->{'expression'} unless defined $expression;
    }
  }

  if(defined $globalReadingMap) {
    $qos =          $globalReadingMap->{'qos'};
    $retain =       $globalReadingMap->{'retain'};
    $expression =   $globalReadingMap->{'expression'} unless defined $expression;
    if(defined($globalReadingMap->{':defaults'})) {
      $qos =        $globalReadingMap->{':defaults'}->{'pub:qos'} unless defined $qos;
      $retain =     $globalReadingMap->{':defaults'}->{'pub:retain'} unless defined $retain;
      $expression = $globalReadingMap->{':defaults'}->{'expression'} unless defined $expression;
    }
  }
  
  if(defined $globalDefaultReadingMap) {
    $qos =          $globalDefaultReadingMap->{'qos'} unless defined $qos;
    $retain =       $globalDefaultReadingMap->{'retain'} unless defined $retain;
    $expression =   $globalDefaultReadingMap->{'expression'} unless defined $expression;
    if(defined($globalDefaultReadingMap->{':defaults'})) {
      $qos =        $globalDefaultReadingMap->{':defaults'}->{'pub:qos'} unless defined $qos;
      $retain =     $globalDefaultReadingMap->{':defaults'}->{'pub:retain'} unless defined $retain;
      $expression = $globalDefaultReadingMap->{':defaults'}->{'expression'} unless defined $expression;
    }
  }

  $qos = 0 unless defined $qos;
  $retain = 0 unless defined $retain;

  return ($qos, $retain, $expression);
}

# Evaluiert Werte in Default, wenn diese Variable / Perl-Expressions enthalten
sub computeDefaults($$$$$) {
  my($hash, $modifier, $globalMap, $devMap, $infoMap) = @_;
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> computeDefaults> infoMap: ".Dumper($infoMap));
  my $mdLng = length($modifier);
  my $defaultCombined={};
  $infoMap = {} unless defined $infoMap;
  if (defined($globalMap) and defined($globalMap->{':defaults'})) {
    foreach my $param (keys %{$globalMap->{':defaults'}} ) {
      if(startsWith($param,$modifier)) {
        my $key = substr($param,$mdLng);
        my $val = $globalMap->{':defaults'}->{$param};
        #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> computeDefaults> global eval: key: $key, val: $val");
        $val = _evalValue2($hash->{NAME},$val,$infoMap);
        #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> computeDefaults> global eval done: val: $val");
        $defaultCombined->{$key}=$val;
      }
    }
  }
  my $devCombined={};
  if (defined($devMap) and defined($devMap->{':defaults'})) {
    foreach my $param (keys %{$devMap->{':defaults'}} ) {
      if(startsWith($param,$modifier)) {
        my $key = substr($param,$mdLng);
        my $val = $devMap->{':defaults'}->{$param};
        #$val = _evalValue2($hash->{NAME},$val,$defaultCombined);
        $devCombined->{$key}=$val;
      }
    }
  }
  foreach my $param (keys %{$devCombined} ) {
    my $val = $devCombined->{$param};
    $devCombined->{$param} = _evalValue2($hash->{NAME},$val,{%$defaultCombined, %$infoMap});
  }
  my $combined = {%$defaultCombined, %$devCombined};
  return $combined;
}

# Ersetzt im $str alle Variable $xxx durch entsprechende Werte aus dem Map {xxx=>wert, xxy=>wert2}
# Ersetzt wird jedoch nur dann, wenn $str mit '{' anfaengt und mit '}' endet.
# Nach dem Ersetzen wird (je $noEval-Wert) Perl-eval durchgefuehrt
sub _evalValue2($$;$$) {
  my($mod, $str, $map, $noEval) = @_;
  $noEval = 0 unless defined $noEval;
  #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2: str: $str; map: ".Dumper($map));
  my$ret = $str;
  if($str =~ m/^{.*}$/) {
    no strict "refs";
    local $@;
    if(defined($map)) {
      foreach my $param (keys %{$map}) {
        my $val = $map->{$param};
        my $pname = '$'.$param;
        $val=$pname unless defined $val;
        #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> replace2: $ret : $pname => $val");
        $ret =~ s/\Q$pname\E/$val/g;
        #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> replace2 done: $ret");
      }
    }
    #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2 !!!");
    $ret = eval($ret) unless $noEval;
    #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval2 done: $ret");
    if ($@) {
      Log3($mod,2,"MQTT_GENERIC_BRIDGE: evalValue: user value ('".$str."'') eval error: ".$@);
    }
  }
  return $ret;
}

# Alte Methode, verwendet noch fixe Variable (base, dev, reading, name), kein Map
# soll durch _evalValue2 ersetzt werden
# sub _evalValue($$;$$$$) {
#   my($mod, $str, $base, $device, $reading, $name) = @_;
#   #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval: (str, base, dev, reading, name) $str, $base, $device, $reading, $name");
#   my$ret = $str;
#   #$base="" unless defined $base;
#   if($str =~ m/^{.*}$/) {
#     no strict "refs";
#     local $@;
#     #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval !!!");
#     $ret = eval($str);
#     #Log3('xxx',1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval done: $ret");
#     if ($@) {
#       Log3($mod,2,"MQTT_GENERIC_BRIDGE: evalValue: user value ('".$str."'') eval error: ".$@);
#     }
#   }
#   return $ret;
# }

# sucht zu dem gegebenen (ankommenden) topic das entsprechende device und reading
# Params: $hash, $topic (empfangene topic)
# return: map (device1->{reading}=>reading1, device1->{expression}=>{...}, deviceN->{reading}=>readingM)
sub searchDeviceForTopic($$) {
  my($hash, $topic) = @_;
  
  my $ret = {};
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined ($map)) {
    foreach my $dname (keys %{$map}) {
      my $dmap = $map->{$dname}->{':subscribe'};
      foreach my $rmap (@{$dmap}) {
        my $topicExp = $rmap->{'topicExp'};
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> searchDeviceForTopic: expr: ".Dumper($topicExp));
        if (defined($topicExp) and $topic =~ $topicExp) {
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> searchDeviceForTopic: match topic: $topic, reading: ".$rmap->{'reading'});
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> searchDeviceForTopic: >>>: \$+{name}: ".$+{name}.", \$+{reading}: ".$+{reading});
          # Check named groups: $+{reading},..
          my $reading = undef;
          if($rmap->{'wildcardTarget'}) {
            $reading = $+{name} unless defined $reading;
            # Remap name
            $reading = $+{reading} unless defined $reading;
          }
          $reading = $rmap->{'reading'} unless defined $reading;
          my $tn = $dname.':'.$reading;
          $ret->{$tn}->{'mode'}=$rmap->{'mode'};
          $ret->{$tn}->{'reading'}=$reading;
          my $device = $+{device}; # TODO: Pruefen, ob Device zu verwenden ist => wie?
          $device = $dname unless defined $device;
          $ret->{$tn}->{'device'}=$device;
          $ret->{$tn}->{'expression'}=$rmap->{'expression'};
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> searchDeviceForTopic: deliver: ".Dumper($ret));
        }
      }
    }
  }

  return $ret;
}

# Erstellt RexExp-Definitionen zum Erkennen der ankommenden Topics
# Platzhaltern werden entsprechend verarbeitet
sub createRegexpForTopic($) {
  my $t = shift;
  $t =~ s|#$|.\*|;
  # Zugriff auf benannte captures: $+{reading}
  $t =~ s|(\$reading)|(\?\<reading\>+)|g;
  $t =~ s|(\$device)|(\?\<device\>+)|g;
  $t =~ s|\$|\\\$|g;
  $t =~ s|\/\.\*$|.\*|;
  $t =~ s|\/|\\\/|g;
  #$t =~ s|(\+)([^+]*$)|(+)$2|;
  $t =~ s|\+|[^\/]+|g;
  return "^$t\$";
}

# Erstellt Strukturen fuer 'Subscribe' fuer ein bestimmtes Geraet.
# Params: Bridge-Hash, Dev-Name (im Map, ist auch = DevName),
#         Internes Map mit allen Definitionen fuer alle Gerate,
#         Attribute-Value zum Parsen
sub CreateSingleDeviceTableAttrSubscribe($$$$) {
  my($hash, $dev, $map, $attrVal) = @_;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: $dev, $attrVal, ".Dumper($map));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: ".Dumper($map));
  # collect subscribe topics
  my $devMap = $map->{$dev};
  my $globalMap = $map->{':global'};
  delete ($devMap->{':subscribe'});
  if(defined $attrVal) {
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
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: attrVal: ".Dumper($attrVal));
    my($unnamed, $named) = MQTT::parseParams($attrVal,'\s',' ','=', undef); #MQTT::parseParams($attrVal, undef, undef, '=', undef);
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: parseParams: named ".Dumper($named));
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: parseParams: unnamed ".Dumper($unnamed));
    if(defined($named)){
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateSingleDeviceTableAttrSubscribe: ".Dumper($map));
      my $dmap = {};
      foreach my $param (keys %{$named}) {
        my $val = $named->{$param};
        my($name,$ident) = split(":",$param);
        if(!defined($ident) or !defined($name)) { next; }

        $ident = 'topic' if $ident eq 'readings-topic';
        #$ident = 'sttopic' if $ident eq 'self-trigger-topic';
        $ident = 'stopic' if $ident eq 'set-topic';
        $ident = 'atopic' if $ident eq 'attr-topic';

        if(($ident eq 'topic') or 
         #($ident eq 'sttopic') or 
          ($ident eq 'stopic') or ($ident eq 'atopic') or 
          ($ident eq 'qos') or ($ident eq 'retain') or 
          ($ident eq 'expression')) {
          my @nameParts = split(/\|/, $name);
          while (@nameParts) {
            my $namePart = shift(@nameParts);
            next if($namePart eq "");
            my $rmap = $dmap->{$namePart};
            $rmap = {} unless defined $rmap;
            $rmap->{'reading'}=$namePart;
            $rmap->{'wildcardTarget'} = $namePart =~ /^\*/;
            #$rmap->{'evalTarget'} = $namePart =~ /^{.+}.*$/;
            $rmap->{'dev'}=$dev;
            $rmap->{$ident}=$val;
            if(($ident eq 'topic') or 
             #($ident eq 'sttopic') or
              ($ident eq 'stopic') or ($ident eq 'atopic')) { # -> topic

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
              
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> sub: old base: $base");

              # $base verwenden => eval
              #my $topic = _evalValue($hash->{NAME},$val,$base,$dev,'$reading','$name');

              my $combined = computeDefaults($hash, 'sub:', $globalMap, $devMap, {'device'=>$dev,'reading'=>'#reading','name'=>'#name','mode'=>$rmap->{'mode'}});
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> sub: Defaults: ".Dumper($combined));
              my $topic = _evalValue2($hash->{NAME},$val,{'device'=>$dev,'reading'=>'#reading','name'=>'#name',%$combined}) if defined $val;
              my $old = '#reading';
              my $new = '$reading';
              $topic =~ s/\Q$old\E/$new/g;
              $old = '#name';
              $new = '$name';
              $topic =~ s/\Q$old\E/$new/g;
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> sub: Topic old: $topic");
              #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> sub: Topic new: $topic");

              $rmap->{'topicOrig'} = $val;
              $rmap->{'topicExp'}=createRegexpForTopic($topic);

              $topic =~ s/\$reading/+/g;
              $topic =~ s/\$name/+/g;
              $topic =~ s/\$device/+/g;
              $rmap->{'topic'} = $topic;
            } # <- topic
            $dmap->{$namePart} = $rmap;
          }
        } 
      }
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> >>> CreateSingleDeviceTableAttrSubscribe ".Dumper($dmap));
      my @vals = values %{$dmap};
      $devMap->{':subscribe'}= \@vals;
    }
    $map->{$dev} = $devMap;
  }
  return undef;
}

# Prueft, ob Geraete keine Definitionen mehr enthalten und entfernt diese ggf. aus der Tabelle
sub deleteEmptyDevices($$$) {
  my ($hash, $map, $devMapName) = @_;
  return unless defined $map;
  return unless defined $devMapName;
  return unless defined $map->{$devMapName};

  # Wenn keine Eintraege => Device loeschen
  if(keys %{$map->{$devMapName}} == 0) {
    delete($map->{$devMapName});
  }
}

# Erstellt alle Strukturen fuer fuer ein bestimmtes Geraet (Default, Alias, Publish, Subscribe).
# Params: Bridge-Hash, Dev-Name , Dev-Map-Name (meist = DevName, kann aber auch ein Pseudegeraet wie ':global' sein),
#         Attr-prefix (idR 'mqtt')
#         Internes Map mit allen Definitionen fuer alle Gerate,
sub CreateSingleDeviceTable($$$$$) {
  my ($hash, $dev, $devMapName, $prefix, $map) = @_;
  # Divece-Attribute fuer ein bestimmtes Device aus Device-Attributen auslesen
  CreateSingleDeviceTableAttrDefaults($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_DEFAULTS, undef));
  CreateSingleDeviceTableAttrAlias($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_ALIAS, undef)); 
  CreateSingleDeviceTableAttrPublish($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_PUBLISH, undef));
  CreateSingleDeviceTableAttrSubscribe($hash, $devMapName, $map, AttrVal($dev, $prefix.CTRL_ATTR_NAME_SUBSCRIBE, undef));
  deleteEmptyDevices($hash, $map, $devMapName);
}

# Geraet-Infos neu einlesen
sub _RefreshDeviceTable($$$$;$$) {
  my ($hash, $dev, $devMapName, $prefix, $attrName, $attrVal) = @_;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> _RefreshDeviceTable: $dev, $devMapName, $prefix, $attrName, $attrVal");
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

  UpdateSubscriptionsSingleDevice($hash, $dev);
}

# Geraet-Infos neu einlesen
sub RefreshDeviceTable($$;$$) {
  my ($hash, $dev, $attrName, $attrVal) = @_;
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  _RefreshDeviceTable($hash, $dev, $dev, $prefix, $attrName, $attrVal);
}

sub RefreshGlobalTableAll($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS, undef));
  RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS, undef));
  RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH, undef));
  #RefreshGlobalTable($hash, CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_SUBSCRIBE, AttrVal($name,CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_SUBSCRIBE, undef));
}

# GlobalTable-Infos neu einlesen fuer einen bestimmten Attribut
sub RefreshGlobalTable($;$$) {
  my ($hash, $attrName, $attrVal) = @_;
  my $prefix = CTRL_ATTR_NAME_GLOBAL_PREFIX;
  _RefreshDeviceTable($hash, $hash->{NAME}, ':global', $prefix, $attrName, $attrVal);
}

# Geraet umbenennen, wird aufgerufen, wenn ein Geraet in FHEM umbenannt wird
sub RenameDeviceInTable($$$) {
  my($hash, $dev, $devNew) = @_;
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined($map->{$dev})) {
    #$map->{$devNew}=$map->{$dev};
    delete($map->{$dev});
    my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
    CreateSingleDeviceTable($hash, $devNew, $devNew, $prefix, $map);
    UpdateSubscriptionsSingleDevice($hash, $devNew);
  }
}

# Geraet loeschen (geloescht in FHEM)
sub DeleteDeviceInTable($$) {
  my($hash, $dev) = @_;
  my $map = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined($map->{$dev})) {
    delete($map->{$dev});
    UpdateSubscriptions($hash);
  }
}

# alle zu ueberwachende Geraete durchsuchen und relevanter Informationen einlesen
sub CreateDevicesTable($) {
  my ($hash) = @_;
  # alle zu ueberwachende Geraete durchgehen und Attribute erfassen
  my $map={};
  $hash->{+HS_TAB_NAME_DEVICES} = $map;
  RefreshGlobalTableAll($hash);
  $map = $hash->{+HS_TAB_NAME_DEVICES};

  my @devices = devspec2array($hash->{+HS_PROP_NAME_DEVSPEC});
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateDevicesTable: ".Dumper(@devices));
  my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
  foreach my $dev (@devices) {
    if($dev ne $hash->{NAME}) {
      Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> CreateDevicesTable for ".$dev);
      CreateSingleDeviceTable($hash, $dev, $dev, $prefix, $map); 
    }
  }

  # crerate global defaults table
  CreateSingleDeviceTable($hash, $hash->{NAME}, ":global", CTRL_ATTR_NAME_GLOBAL_PREFIX, $map);

  $hash->{+HS_TAB_NAME_DEVICES} = $map;
  UpdateSubscriptions($hash);
  #$hash->{+HELPER}->{+HS_FLAG_INITIALIZED} = 1;
}

# Ueberbleibsel eines Optimierungsversuchs
sub UpdateSubscriptionsSingleDevice($$) {
  my ($hash, $dev) = @_;
  # Liste der Geraete mit der Liste der Subscriptions abgleichen
  # neue Subscriptions bei Bedarf anlegen und/oder ueberfluessige loeschen
  # fuer Einzeldevices vermutlich eher schwer, erstmal komplet updaten
  UpdateSubscriptions($hash);
}

# Alle MQTT-Subscriptions erneuern
sub UpdateSubscriptions($) {
  my ($hash) = @_;

  updateDevCount($hash);

  return unless isIODevMQTT($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';

  my $topicMap = {};
  my $gmap = $hash->{+HS_TAB_NAME_DEVICES};
  if(defined($gmap)) {
    foreach my $dname (keys %{$gmap}) {
      my $smap = $gmap->{$dname}->{':subscribe'};
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: smap = ".Dumper($gmap->{$dname}));
      if(defined($smap)) {
        foreach my $rmap (@{$smap}) {
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
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: topics = ".Dumper(@topics));
  my @new=();
  my @remove=();
  foreach my $topic (@topics) {
    next if ($topic eq "");
    push @new,$topic unless grep {$_ eq $topic} @{$hash->{subscribe}};
  }
  foreach my $topic (@{$hash->{subscribe}}) {
    next if ($topic eq "");
    push @remove,$topic unless grep {$_ eq $topic} @topics;
  }

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: remove = ".Dumper(@remove));
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: new = ".Dumper(@new));

  foreach my $topic (@remove) {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: unsubscribe: topic = ".Dumper($topic));
    client_unsubscribe_topic($hash,$topic);
  }
  foreach my $topic (@new) {
    my $qos = $topicMap->{$topic}->{'qos'};    # TODO: Default lesen
    $qos = 0 unless defined $qos;
    my $retain = 0; # not supported
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> UpdateSubscriptions: subscribe: topic = ".Dumper($topic).", qos = ".Dumper($qos).", retain = ".Dumper($retain));
    client_subscribe_topic($hash,$topic,$qos,$retain) ;
  }
}

# Alle MQTT-Subscription erntfernen
sub RemoveAllSubscripton($) {
  my ($hash) = @_;

  return unless isIODevMQTT($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';

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

sub InitializeDevices($) {
  my ($hash) = @_;
  # alles neu aufbauen
  # Deviceliste neu aufbauen, ggf., alte subscription kuendigen, neue abonieren
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> ------------ InitializeDevices --------------");
  CreateDevicesTable($hash);
  #UpdateSubscriptions($hash);
}

# Falls noetig, Geraete initialisieren
sub CheckInitialization($) {
  my ($hash) = @_;
  # Pruefen, on interne Strukturen initialisiert sind
  return if $hash->{+HELPER}->{+HS_FLAG_INITIALIZED};
  InitializeDevices($hash);
}

# Zusaetzliche Attribute im Debug-Modus
my %getsDebug = (
  "debugInfo" => "",
  "debugReinit" => "",
  "debugShowPubRec" => ""
);

# Routine fuer FHEM Get-Commando
sub Get($$$@) {
  my ($hash, $name, $command, $args) = @_;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> get CL: ".Dumper($hash->{CL}));
  return "Need at least one parameters" unless (defined $command);
  unless (defined($gets{$command}) or (isDebug($hash) && defined($getsDebug{$command}))) {
    my $rstr="Unknown argument $command, choose one of";
    foreach my $vname (keys %gets) {
      $rstr.=" $vname";
      my $vval=$gets{$vname};
      $rstr.=":$vval" if $vval;
    }
    if (isDebug($hash)) {
      $rstr.=" debugInfo:noArg debugReinit:noArg";
      $rstr.=" debugShowPubRec:";
      foreach my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        foreach my $rname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':publish'}}) {
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

  COMMAND_HANDLER: {
    $command eq "debugInfo" and isDebug($hash) and do {
      my $debugInfo = "initialized: ".$hash->{+HELPER}->{+HS_FLAG_INITIALIZED}."\n\n";
      $debugInfo.= "device data records: ".Dumper($hash->{+HS_TAB_NAME_DEVICES})."\n\n";
      $debugInfo.= "subscriptionTab: ".Dumper($hash->{+HS_TAB_NAME_SUBSCRIBE})."\n\n";
      $debugInfo.= "subscription helper array: ".Dumper($hash->{subscribe})."\n\n";

      # Exclude tables
      $debugInfo.= "exclude type map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_TYPE})."\n\n";
      $debugInfo.= "exclude reading map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_READING})."\n\n";
      $debugInfo.= "exclude device map: ".Dumper($hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES})."\n\n";

      $debugInfo =~ s/</&lt;/g;      
      $debugInfo =~ s/>/&gt;/g;      

      return $debugInfo;
    };
    $command eq "version" and do {
      return $VERSION;
    };
    $command eq "debugReinit" and isDebug($hash) and do {
      InitializeDevices($hash);
      last;
    };
    $command eq "debugShowPubRec" and do {
      my($dev,$reading) = split(/>/,$args);
      return "PubRec: $dev:$reading = ".Dumper(getDevicePublishRec($hash, $dev, $reading));
      #last;
    };
    $command eq "devlist" and do {
      my $res="";
      foreach my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        if($dname ne ":global") {
          if($args) {
            next unless $dname =~ /^$args$/;
          }
          $res.=$dname."\n";
        }
      }
      $res = "no devices found" unless ($res ne "");
      return $res;
    };
    $command eq "devinfo" and do {
      my $res="";
      foreach my $dname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}}) {
        if($dname ne ":global") {
          if($args) {
            next unless $dname =~ /^$args$/;
          }
          $res.=$dname."\n";
          $res.="  publish:\n";
          foreach my $rname (sort keys %{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':publish'}}) {
            my $pubRec = getDevicePublishRec($hash, $dname, $rname);
            if(defined($pubRec)) {
              my $expression = $pubRec->{'expression'};
              my $mode =  $pubRec->{'mode'};
              $mode='E' if(defined($expression) and !defined($mode));
              my $topic = undef;
              if($mode eq 'R') {
                $topic = $pubRec->{'topic'};
              } elsif($mode eq 'A') {
                $topic = $pubRec->{'atopic'};
              } elsif($mode eq 'E') {
                $topic = '[expression]';
              } else {
                $topic = '!unexpected mode!';
              }
              $topic = 'undefined' unless defined $topic;
              my $qos = $pubRec->{'qos'};
              my $retain = $pubRec->{'retain'};
              $res.= sprintf('    %-16s => %s',  $rname, $topic);
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
          foreach my $subRec (@{$hash->{+HS_TAB_NAME_DEVICES}->{$dname}->{':subscribe'}}) {
            my $qos = $subRec->{'qos'};
            my $mode = $subRec->{'mode'};
            my $expression = $subRec->{'expression'};
            my $topic = $subRec->{'topic'};
            $topic = '---' unless defined $topic;
            my $rest.= sprintf('    %-16s <= %s', $subRec->{'reading'}, $topic);
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
      # TODO : Weitere Dev Infos?
      $res = "no devices found" unless ($res ne "");
      return $res;
      #last;
    };
    # $command eq "YYY" and do {
    #   #  
    #   last;
    # };
  };
}

# Routine fuer FHEM Notify
sub Notify() {
  my ($hash,$dev) = @_;
  if( $dev->{NAME} eq "global" ) {
    #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> notify for global ".Dumper(@{$dev->{CHANGED}}));
    if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
      # FHEM (re)Start
      firstInit($hash);
    }
    
    # Aenderungen der Steuerattributen in den ueberwachten Geraeten tracken
    my $max = int(@{$dev->{CHANGED}});
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = "" if(!defined($s));
      # tab, CR, LF durch spaces ersetzen
      $s =~ s/[\r\n\t]/ /g;
      #$s =~ s/ [ ]+/ /g;
      if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
        # Device renamed
        my ($old, $new) = ($1, $2);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> Device renamed: $old => $new");
        # wenn ein ueberwachtes device, tabelle korrigieren
        RenameDeviceInTable($hash, $old, $new);
      } elsif($s =~ m/^DELETED ([^ ]*)$/) {
        # Device deleted
        my ($name) = ($1);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> Device deleted: $name");
        # wenn ein ueberwachtes device, tabelle korrigieren
        DeleteDeviceInTable($hash, $name);
      } elsif($s =~ m/^ATTR ([^ ]*) ([^ ]*) (.*)$/) {
        # Attribut created or changed
        my ($sdev, $attrName, $val) = ($1, $2, $3);
        #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> attr created/changed: $sdev : $attrName = $val");
        # wenn ein ueberwachtes device und attr bzw. steuer.attr, tabelle korrigieren
        if(IsObservedAttribute($hash,$attrName)) {
          #Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> attr created/changed: observed attr: $attrName = $val");
          RefreshDeviceTable($hash, $sdev, $attrName, $val);
        } else {
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> attr created/changed: non observed attr = $val");
          # check/ publish atopic => val
          publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, $val);
        }
      } elsif($s =~ m/^DELETEATTR ([^ ]*) ([^ ]*)$/) {
        # Attribut deleted
        my ($sdev, $attrName) = ($1, $2);
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> attr deleted: $sdev : $attrName");
        # wenn ein ueberwachtes device und attr bzw. steuer.attr, tabelle korrigieren
        if(IsObservedAttribute($hash,$attrName)) {
          Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> attr deleted: observed attr: $attrName");
          RefreshDeviceTable($hash, $sdev, $attrName, undef);
        } else {
          # check/ publish atopic => null
          publishDeviceUpdate($hash, $defs{$sdev}, 'A', $attrName, undef);
        }
      }
    }
    return undef;
  }

  checkPublishDeviceReadingsUpdates($hash, $dev);
}

# Pruefen, ob in dem Device Readings-Aenderungen vorliegen, die gepublished werden sollen 
sub checkPublishDeviceReadingsUpdates($$) {
  my ($hash, $dev) = @_;

  # pruefen, ob die Aenderung von der Bridge selbst getriggert wurde
  # es ist der Readingsname drin, die Pruefung ist jedoch derzeit nicht nietig, da nur ein Reading in CHANGE drin sein kann
  # ansonsten muesste readings in CHANGE mit dem Wert vergliechen werden und nur fuer gleiche nicht weiter senden
  my $triggeredReading = $dev->{'.mqttGenericBridge_triggeredReading'};
  if(defined $triggeredReading) {
    delete $dev->{'.mqttGenericBridge_triggeredReading'};
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> Notify [mqttGenericBridge_triggeredReading]=>".$triggeredReading);
    return;
  }

  # nicht waehrend FHEM startet
  return if( !$main::init_done );

  # nicht, wenn deaktivert
  return "" if(main::IsDisabled($hash->{NAME}));

  #CheckInitialization($hash);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> checkPublishDeviceReadingsUpdates ------------------------ ");

  # Pruefen, ob ein ueberwachtes Geraet vorliegt 
  my $devName = $dev->{NAME}; 
  my $devDataTab = $hash->{+HS_TAB_NAME_DEVICES}; # Geraetetabelle
  return unless defined $devDataTab; # not initialized now or internal error
  my $devDataRecord = $devDataTab->{$devName}; # 
  unless (defined($devDataRecord)) {
    # Pruefen, ob ggf. Default map existiert.
    my $globalDataRecord = $devDataTab->{':global'};
    return "" unless defined $globalDataRecord;
    my $globalPublishMap = $globalDataRecord->{':publish'};
    return "" unless defined $globalPublishMap;
    my $size = int(keys %{$globalPublishMap});
    return "" unless ($size>0);
  }

  foreach my $event (@{deviceEvents($dev,1)}) {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> Notify for $dev->{NAME} event: $event STATE: $dev->{STATE}");
    $event =~ /^([^:]+)(: )?(.*)$/;
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> event: $event, '".((defined $1) ? $1 : "-undef-")."', '".((defined $3) ? $3 : "-undef-")."'");
    my $devreading = $1;
    my $devval = $3;
    if(defined $devreading and defined $devval) {
      # wenn ueberwachtes device and reading
      publishDeviceUpdate($hash, $dev, 'R', $devreading, $devval);
    }
  }
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
sub defineGlobalTypeExclude($;$) {
  my ($hash, $valueType) = @_;
  #$valueType = AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE, DEFAULT_GLOBAL_TYPE_EXCLUDES) unless defined $valueType;
  $valueType = DEFAULT_GLOBAL_TYPE_EXCLUDES unless defined $valueType;
  $valueType.= ' '.DEFAULT_GLOBAL_TYPE_EXCLUDES if defined $valueType;
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


  my($unnamed, $named) = MQTT::parseParams($valueType,'\s',' ','=', undef);
  foreach my $val (@$unnamed) {
    next if($val eq '');
    my($dir, $type, $reading) = split(/:/, $val);
    if ((!defined $reading) and ($dir ne 'pub') and ($dir ne 'sub')) {
      $reading=$type;
      $type=$dir;
      $dir=undef;
    }
    next if($type eq '');
    $reading='*' unless defined $reading;
    $reading = '*' if $reading eq '';
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> defineGlobalTypeExclude: dir, type, reading: ".Dumper(($dir, $type, $reading)));
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
#       Das Bedeutet, dass an dem gegebenen Geraet die genannte Reading nicht uebertragen wird.
#       Ein Stern anstatt Reading bedeutet, dass alle Readings eines Geraets ignoriert werden.
#       Ein Stern anstatt des Geraetenamens ist nicht erlaubt (benutzen Sie in diesem Fall GlobalTypeExclude).
#       Zusaetzlich kann auch die Richtung optional angegeben werden (pub oder sub). Dann gilt die Ausnahme entsprechend nur fuers Senden oder nur fuer Empfang.
# TEST {Dumper(MQTT::GENERIC_BRIDGE::defineGlobalDevExclude($defs{'mqttGenericBridge'},'sub:dev1:reading1 dev2:reading2 dev3 pub:a: *:* test'))}
sub defineGlobalDevExclude($;$) {
  my ($hash, $valueName) = @_;
  $valueName = DEFAULT_GLOBAL_DEV_EXCLUDES unless defined $valueName;
  $valueName.= ' '.DEFAULT_GLOBAL_DEV_EXCLUDES if defined $valueName;
  # HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES

  $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}={};

  # my @list = split("[ \t][ \t]*", $valueName);
  # foreach (@list) {
  #   next if($_ eq "");
  #   my($dev, $reading) = split(/:/, $_);
  #   $reading='*' unless defined $reading;
  #   $hash->{+HS_PROP_NAME_GLOBAL_EXCLUDES_DEVICES}->{$dev}=$reading if($dev ne '*');
  # }

  my($unnamed, $named) = MQTT::parseParams($valueName,'\s',' ','=', undef);
  foreach my $val (@$unnamed) {
    next if($val eq '');
    my($dir, $dev, $reading) = split(/:/, $val);
    if ((!defined $reading) and ($dir ne 'pub') and ($dir ne 'sub')) {
      $reading=$dev;
      $dev=$dir;
      $dir=undef;
    }
    next if($dev eq '');
    $reading = '*' unless defined $reading;
    $reading = '*' if $reading eq '';
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> defineGlobalDevExclude: dir, dev, reading: ".Dumper(($dir, $dev, $reading)));
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
sub defineDefaultGlobalExclude($) {
  my ($hash) = @_;  
  defineGlobalTypeExclude($hash, AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE, DEFAULT_GLOBAL_TYPE_EXCLUDES));
  defineGlobalDevExclude($hash, AttrVal($hash->{NAME}, CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE, DEFAULT_GLOBAL_DEV_EXCLUDES));
}

# Prueft, ob Type/Reading- oder Geraete/Reading-Kombination von der Uebertragung ausgeschlossen werden soll, 
# oder im Geraet Ignore-Attribut gesetzt ist.
#   Parameter:
#     $hash:    HASH
#     $type:    Geraetetyp
#     $devName: Geraetename
#     $reading: Reading
sub isTypeDevReadingExcluded($$$$$) {
  my ($hash, $direction, $type, $devName, $reading) = @_;

  # pruefen, ob im Geraet ignore steht
  my $devDisable = $main::attr{$devName}{$hash->{+HS_PROP_NAME_PREFIX}.CTRL_ATTR_NAME_IGNORE};
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
  my $exType=$gExcludesTypeMap->{$type} if defined $gExcludesTypeMap;
  if(defined $exType) {
    return 1 if ($exType eq "*");
    return 1 if ($exType eq $reading);
  }

  # devices
  my $exDevName=$gExcludesDevMap->{$devName} if defined $gExcludesDevMap;
  if(defined $exDevName) {
    return 1 if ($exDevName eq "*");
    return 1 if ($exDevName eq $reading);
  }
  
  return undef;
}

# Prueft, ob per MQTT ankommende Nachrichten ggf. per MQTT weiter geleitet werden duerfen.
#  Parameter:
#     $hash:    HASH
#     $devName: Geraetename
#     $reading: Reading (ggf. for future use)
sub isDoForward($$$) {
  my ($hash, $devName, $reading) = @_;
  my $doForward = $main::attr{$devName}{$hash->{+HS_PROP_NAME_PREFIX}.CTRL_ATTR_NAME_FORWARD};

  $doForward = 'none' if (!defined($doForward) and ($defs{$devName}->{TYPE} eq 'dummy')); # Hack fuer Dummy-Devices

  $doForward = 'all' unless defined $doForward;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> isDoForward $devName => $doForward");

  return 1 if $doForward eq 'all';
  return 0;
}

# MQTT-Nachricht senden
# Params: Bridge-Hash, Topic, Nachricht, QOS- und Retain-Flags
sub doPublish($$$$$$$$) {
  my ($hash,$device,$reading,$topic,$message,$qos,$retain,$resendOnConnect) = @_;

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> doPublish: topic: $topic, msg: $message, resend mode: ".(defined($resendOnConnect)?$resendOnConnect:"no"));
  if(!isConnected($hash)) {
    # store message?
    if(defined($resendOnConnect)) {
      $resendOnConnect = lc($resendOnConnect);
      Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> offline publish: store: topic: $topic, msg: $message, mode: $resendOnConnect");
      if($resendOnConnect eq 'first' or $resendOnConnect eq 'last' or $resendOnConnect eq 'all') {
        # store msg data
        my $queue = $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};
        #my $queue = $hash->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};
        $queue = {} unless defined $queue;

        my $entry = {'topic'=>$topic, 'message'=>$message, 'qos'=>$qos, 'retain'=>$retain, 
                     'resendOnConnect'=>$resendOnConnect,'device'=>$device,'reading'=>$reading};
        my $topicQueue = $queue->{$topic};
        unless (defined($topicQueue)) {
          $topicQueue = [$entry];
        } 
        else {
          if ($resendOnConnect eq 'first') {
            if (scalar @$topicQueue == 0) {
              $topicQueue = [$entry];  
            }
          } elsif($resendOnConnect eq 'last') {
            $topicQueue = [$entry];
          } else { # all
            push (@$topicQueue, $entry);
          } 
        }
        # check max lng
        my $max = $hash->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE_MAX_CNT_PROTOPIC};
        $max = 10 unless defined $max;
        while (scalar @$topicQueue > $max) {
          shift @$topicQueue;
        }

        $queue->{$topic} = $topicQueue;
        #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> offline publish: stored: ".Dumper($queue));

        $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE} = $queue;
      }
    }
    return 'stored';
  }

  Log3($hash->{NAME},5,"MQTT_GENERIC_BRIDGE:DEBUG:> publish: $topic => $message (qos: $qos, retain: ".(defined($retain)?$retain:'0').")");

  if (isIODevMQTT2($hash)){ #if ($hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER') {
    # TODO: publish MQTT2

    return 'unsupported IODev';
  } elsif (isIODevMQTT($hash)) { #elsif ($hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT') {
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> doPublish for $devn, $reading, $value, topic: $topic, message: $message");
    my $msgid;
    if(defined($topic) and defined($message)) {
      $msgid = send_publish($hash->{IODev}, topic => $topic, message => $message, qos => $qos, retain => $retain);
      readingsSingleUpdate($hash,"transmission-state","outgoing publish sent",1);
      $hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT}++;
      readingsSingleUpdate($hash,"outgoing-count",$hash->{+HELPER}->{+HS_PROP_NAME_OUTGOING_CNT},1);
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> publish: $topic => $message");
      return undef;
    }
    $hash->{message_ids}->{$msgid}++ if defined $msgid;
    return 'empty topic or message';
  } else {
    my $iodt = retrieveIODev($hash);
    $iodt = 'undef' unless defined $iodt;
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: unknown IODev: ".$iodt);
    return 'unknown IODev';
  }
}

# MQTT-Nachrichten entsprechend Geraete-Infos senden
# Params: Bridge-Hash, Device-Hash, 
#         Modus (Topics entsprechend Readings- oder Attributen-Tabelleneintraegen suchen), 
#         Name des Readings/Attributes, Wert
sub publishDeviceUpdate($$$$$) {
  my ($hash, $devHash, $mode, $reading, $value) = @_;
  my $devn = $devHash->{NAME};
  my $type = $devHash->{TYPE};
  $mode = 'R' unless defined $mode;
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> publishDeviceUpdate for $type, $mode, $devn, $reading, $value");  
  # bestimmte bekannte types und readings ausschliessen (vor allem 'transmission-state' in der eigenen Instanz, das fuert sonst zu einem Endlosloop)
  return if($type eq "MQTT_GENERIC_BRIDGE");
  return if($type eq "MQTT");
  return if($reading eq "transmission-state");
  # extra definierte (ansonsten gilt eine Defaultliste) Types/Readings auschliessen.
  return if(isTypeDevReadingExcluded($hash, 'pub', $type, $devn, $reading));

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> publishDeviceUpdate for $devn, $reading, $value");
  my $pubRec = getDevicePublishRec($hash, $devn, $reading);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> publishDeviceUpdate pubRec: ".Dumper($pubRec));

  if(defined($pubRec)) {
    # my $msgid;

    my $defMap = $pubRec->{'.defaultMap'};

    my $topic = $pubRec->{'topic'}; # 'normale' Readings
    $topic = $pubRec->{'atopic'} if $mode eq 'A'; # Attributaenderungen
    my $qos = $pubRec->{'qos'};
    my $retain = $pubRec->{'retain'};
    my $expression = $pubRec->{'expression'};
    my $base = $pubRec->{'base'};
    my $resendOnConnect = $pubRec->{'resendOnConnect'};
    # # damit beim start die Attribute einmal uebertragen werden => geht wohl mangels event beim start nicht
    # if(!$main::init_done and !defined($resendOnConnect) and ($mode eq 'A')) {
    #   $resendOnConnect = 'last';
    #   Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> queueing Attr-Chang at start");
    # }

    $base='' unless defined $base;

    $value="\0" unless defined $value;

    my $redefMap=undef;
    my $message=$value;
    if(defined $expression) {
      # Expression: Direktes aendern von Attributen ($topic, $qos, $retain, $value) moeglich
      # Rueckgabe: bei undef wird die Ausfuehrung unterbunden. Sonst wird die Rueckgabe als neue message interpretiert, 
      # es sei denn, Variable $value wurde geaendert, dann hat die Aenderung Vorrang.
      # Rueckgabewert wird ignoriert, falls dieser ein Array ist. 
      # Bei einem Hash werden Paare als Topic-Message Paare verwendet und mehrere Nachrichten gesendet
      no strict "refs";
      local $@;
      my $ret = _evalValue2($hash->{NAME},$expression,$defMap,1);
      $ret = eval($ret);
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
      #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval done: ".Dumper($ret));
      if ($@) {
        Log3($hash->{NAME},2,"MQTT_GENERIC_BRIDGE: error while evaluating expression ('".$expression."'') eval error: ".$@);
      }
      use strict "refs";
    }

    my $updated = 0;
    if(defined($redefMap)) {
      foreach my $key (keys %{$redefMap}) {
        my $val = $redefMap->{$key};
        my $r = doPublish($hash,$devn,$reading,$key,$val,$qos,$retain,$resendOnConnect);
        $updated = 1 unless defined $r;
      }
    } else {
        my $r = doPublish($hash,$devn,$reading,$topic,$message,$qos,$retain,$resendOnConnect)  if defined $topic;
        $updated = 1 unless defined $r;
    }
    if($updated) {
      updatePubTime($hash,$devn,$reading);
    }

  }
}

# Routine fuer FHEM Attr
sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    # Steuerattribute
    $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_DEFAULTS and do {
      if ($command eq "set") {
        RefreshGlobalTable($hash, $attribute, $value);
      } else {
        RefreshGlobalTable($hash, $attribute, undef);
      }
      last;
    };
    $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_ALIAS and do {
      if ($command eq "set") {
        RefreshGlobalTable($hash, $attribute, $value);
      } else {
        RefreshGlobalTable($hash, $attribute, undef);
      }
      last;
    };
    $attribute eq CTRL_ATTR_NAME_GLOBAL_PREFIX.CTRL_ATTR_NAME_PUBLISH and do {
      if ($command eq "set") {
        RefreshGlobalTable($hash, $attribute, $value);
      } else {
        RefreshGlobalTable($hash, $attribute, undef);
      }
      last;
    };
    $attribute eq CTRL_ATTR_NAME_GLOBAL_TYPE_EXCLUDE and do {
      if ($command eq "set") {
        defineGlobalTypeExclude($hash,$value);
      } else {
        defineGlobalTypeExclude($hash,undef);
      }
      last;
    };
    $attribute eq CTRL_ATTR_NAME_GLOBAL_DEV_EXCLUDE and do {
      if ($command eq "set") {
        defineGlobalDevExclude($hash,$value);
      } else {
        defineGlobalDevExclude($hash,undef);
      }
      last;
    };
     # $attribute eq "XXX" and do {
    #   if ($command eq "set") {
    #     #$hash->{publishState} = $value;
    #   } else {
    #     #delete $hash->{publishState};
    #   }
    #   last;
    # };
    my $prefix = $hash->{+HS_PROP_NAME_PREFIX};
    (($attribute eq $prefix.CTRL_ATTR_NAME_DEFAULTS) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_ALIAS) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_PUBLISH) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_SUBSCRIBE) or 
      ($attribute eq $prefix.CTRL_ATTR_NAME_IGNORE) or
      ($attribute eq $prefix.CTRL_ATTR_NAME_FORWARD)
    ) and do {
      if ($command eq "set") {
        return "this attribute is not allowed here";
      }
      last;
    };
    
    # Gateway-Device
    $attribute eq "IODev" and do {
      my $ioDevType = undef;
      $ioDevType = $defs{$value}{TYPE} if defined ($value) and defined ($defs{$value});
      $hash->{+HELPER}->{+IO_DEV_TYPE} = $ioDevType;
      
      if ($command eq "set") {
        my $oldValue = $main::attr{$name}{IODev};
        if ($main::init_done) {
          unless (defined ($oldValue) and ($oldValue eq $value) ) {
            #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> attr: change IODev");
            MQTT::client_stop($hash) if defined($main::attr{$name}{IODev}) and ($main::attr{$name}{IODev} eq 'MQTT');
            $main::attr{$name}{IODev} = $value;
            firstInit($hash);
          }
        }
      } else {
        if ($main::init_done) {
          MQTT::client_stop($hash) if defined ($ioDevType) and ($ioDevType eq 'MQTT');
        }
      }
        
      last;
    };
    return undef;
  }
}

# CallBack-Handler fuer IODev beim Connect
sub ioDevConnect($) {
  my $hash = shift;
  return if isIODevMQTT2($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';

  # ueberraschenderweise notwendig fuer eine subscribe-Initialisierung.
  MQTT::client_start($hash) if isIODevMQTT($hash);

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> ioDevConnect");

  # resend stored msgs => doPublish (...., undef)
  my $queue = $hash->{+HELPER}->{+HS_PROP_NAME_PUB_OFFLINE_QUEUE};
  if (defined($queue)) {
    foreach my $topic (keys %{$queue}) {
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
  }

}

# CallBack-Handler fuer IODev beim Disconnect
sub ioDevDisconnect($) {
  my $hash = shift;
  return if isIODevMQTT2($hash); #if $hash->{+HELPER}->{+IO_DEV_TYPE} eq 'MQTT2_SERVER';

  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> ioDevDisconnect");

  # TODO
}

# Per MQTT-Empfangenen Aktualisierungen an die entsprechende Geraete anwenden
# Params: Bridge-Hash, Modus (R=Readings, A=Attribute), Reading/Attribute-Name, Nachricht
sub doSetUpdate($$$$$) {
  my ($hash,$mode,$device,$reading,$message) = @_;

  my $dhash = $defs{$device};
  return unless defined $dhash;
  
  my $doForward = isDoForward($hash, $device,$reading);

  if($mode eq 'S') {
    my $err;
    my @args = split ("[ \t]+",$message);
    #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> mqttGenericBridge_triggeredReading=".Dumper($dhash->{'.mqttGenericBridge_triggeredReading'}));
    if(($reading eq '') or ($reading eq 'state')) {
      $dhash->{'.mqttGenericBridge_triggeredReading'}="state" unless $doForward;
      #$err = DoSet($device,$message);
      $err = DoSet($device,@args);
    } else {
      $dhash->{'.mqttGenericBridge_triggeredReading'}=$reading unless $doForward;
      #$err = DoSet($device,$reading,$message);
      $err = DoSet($device,$reading,@args);
    }
    unless (defined($err)) {
      $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT}++; 
      readingsSingleUpdate($hash,"updated-set-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_S_CNT},1);
      return undef;
    }
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: setUpdate: error in set command: ".$err);
    return "error in set command: $err";
  } elsif($mode eq 'R') { # or $mode eq 'T') {
    # R - Normale Topic (beim Empfang nicht weiter publishen)
    # T - Selt-Trigger-Topic (Sonderfall, auch wenn gerade empfangen, kann weiter getriggert/gepublisht werden. Vorsicht! Gefahr von 'Loops'!)
    readingsBeginUpdate($dhash);
    #if ($mode eq 'R') {
      $dhash->{'.mqttGenericBridge_triggeredReading'}=$reading unless $doForward;
    #}
    readingsBulkUpdate($dhash,$reading,$message);
    readingsEndUpdate($dhash,1);
    # wird in 'notify' entfernt # delete $dhash->{'.mqttGenericBridge_triggeredReading'};

    $hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT}++; 
    readingsSingleUpdate($hash,"updated-reading-count",$hash->{+HELPER}->{+HS_PROP_NAME_UPDATE_R_CNT},1);
    return undef;
  } elsif($mode eq 'A') {
    CommandAttr(undef, "$device $reading $message");
    return undef;
  } else {
    Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE: setUpdate: unexpected mode: ".$mode);
    return "unexpected mode: $mode";
  }
  return "internal error";
}

# Routine MQTT-Message Callback
sub onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  #CheckInitialization($hash);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> onmessage: $topic => $message");

  $hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT}++; 
  readingsSingleUpdate($hash,"incoming-count",$hash->{+HELPER}->{+HS_PROP_NAME_INCOMING_CNT},1);

  my $fMap = searchDeviceForTopic($hash, $topic);
  #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> onmessage: $fMap : ".Dumper($fMap));
  foreach my $deviceKey (keys %{$fMap}) {
        my $device = $fMap->{$deviceKey}->{'device'};
        my $reading = $fMap->{$deviceKey}->{'reading'};
        my $mode = $fMap->{$deviceKey}->{'mode'};
        my $expression = $fMap->{$deviceKey}->{'expression'};

        next unless defined $device;
        next unless defined $reading;

        my $dhash = $defs{$device};
        next unless defined $dhash;
        next if(isTypeDevReadingExcluded($hash, 'sub', $dhash->{TYPE}, $device, $reading));

        my $redefMap=undef;

        if(defined $expression) {
          # Expression: Verfuegbare Variablen: $device, $reading, $message (initial gleich $value)
          # Rueckgabe: bei undef wird die Ausfuehrung unterbunden. Sonst wird die Rueckgabe als neue message interpretiert, 
          # es sei denn, Variable $value wurde geaendert, dann hat die Aenderung Vorrang.
          # Rueckgabewert wird ignoriert, falls dieser ein Array ist. 
          # Bei einem Hash werden Paare als Reading-Wert Paare gesetzt (auch set (stopic), attr (atopic))
          no strict "refs";
          local $@;
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval ($expression) !!!");
          my $value = $message;
          my $ret = eval($expression);
          if(ref($ret) eq 'HASH') {
            $redefMap = $ret;
          } elsif(ref($ret) eq 'ARRAY') {
            # ignore
          } elsif($value ne $message) {
            $message = $value;
          } elsif(!defined($ret)) {
            $message = undef;
          } else {
            $message = $ret;
          }
          #Log3($hash->{NAME},1,"MQTT_GENERIC_BRIDGE:DEBUG:> eval done: ".Dumper($ret));
          if ($@) {
            Log3($hash->{NAME},2,"MQTT_GENERIC_BRIDGE: onmessage: error while evaluating expression ('".$expression."'') eval error: ".$@);
          }
          use strict "refs";
        }

        #next unless defined $device;
        #next unless defined $reading;

        next unless defined $message;

        my $updated = 0;
        if(defined($redefMap)) {
          foreach my $key (keys %{$redefMap}) {
            my $val = $redefMap->{$key};
            my $r = doSetUpdate($hash,$mode,$device,$key,$val);
            $updated = 1 unless defined $r;
          }
        } else {
          my $r = doSetUpdate($hash,$mode,$device,$reading,$message);
          $updated = 1 unless defined $r;
        }

        # TODO: ggf. Update Last Received implementieren (nicht ganz einfach).
        #if($updated) {
          #updateSubTime($device,$reading);
        #}
  }

}
1;

=pod
=item [device]
=item summary MQTT_GENERIC_BRIDGE acts as a bridge for any fhem-devices and mqtt-topics
=begin html

<a name="MQTT_GENERIC_BRIDGE"></a>
 <h3>MQTT_GENERIC_BRIDGE</h3>
 <ul>
 <p>
        This module is a MQTT bridge, which simultaneously collects data from several FHEM devices
        and passes their readings via MQTT or set readings from the incoming MQTT messages or executes them
        as a 'set' command on the configured FHEM device.
    <br/>An <a href="#MQTT">MQTT</a> device is needed as IODev.
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
       If this is e.g. redefined as 'hugo', the control attributes are named hugoPublish etc.
    </p>
   <p>The second parameter ('devspec') allows to minimize the number of devices to be monitored
      (otherwise all devices will be monitored, which may cost performance).
      Example for devspec: 'TYPE=dummy' or 'dummy1,dummy2'. With comma separated list no spaces must be used!
      see <a href="https://fhem.de/commandref_DE.html#devspec">devspec</a></p>
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
   <p>the following attributes are supported:</p>
   <li><p>IODev<br/>
    This attribute is mandatory and must contain the name of a functioning MQTT module instance. MQTT2_SERVER module is not supported.</p>
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
   </li>

   <li>
    <p>globalSubscribe ! TODO - is currently not supported and may not be implemented at all!<br/>
        Defines topics / flags for MQTT transmission. These are used if there are no suitable values in the respective device.
        see <a href="#MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a>.
     </p>
   </li>

   <li>
    <p>globalTypeExclude<br/>
        Defines (device) types and readings that should not be considered in the transmission.
        Values can be specified separately for each direction (buplish or subscribe). Use prefixes 'pub:' and 'sub:' for this purpose.
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
        Values can be specified separately for each direction (buplish or subscribe). Use prefixes 'pub:' and 'sub:' for this purpose.
        A single value means that a device with that name is completely ignored (for all its readings and both directions).
        Colon-separated pairs are interpreted as '[sub:|pub:]Device:Reading'. 
        This means that the given reading is not transmitted to the given device.</p>
        <p>Example:<br/>
            <code>attr &lt;dev&gt; globalDeviceExclude Test Bridge:transmission-state</code></p>
   </li>

   <p>For the monitored devices, a list of the possible attributes is automatically extended by several further entries. 
      They all begin with a prefix previously defined in the bridge. These attributes are used to configure the actual MQTT mapping.<br/>
      By default, the following attribute names are used: mqttDefaults, mqttAlias, mqttPublish, mqttSubscribe.
      <br/>The meaning of these attributes is explained below.
    </p>

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
                   If no alias is defined, than $name = $ reading).</li>
            </ul>
            <br/>
            All these values can be limited by prefixes ('pub:' or 'sub') in their validity 
            to only send or receive only (as far asappropriate). 
            Values for 'qos' and 'retain' are only used if no explicit information has been given about it for a specific topic.</p>
            <p>Example:<br/>
                <code>attr &lt;dev&gt; mqttDefaults base={"/TEST/$device"} pub:qos=0 sub:qos=2 retain=0</code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a><br/>
            This attribute allows readings to be mapped to MQTT topic under a different name. 
            Usually only useful if topic definitions are Perl expressions with corresponding variables. 
            Again, 'pub:' and 'sub:' prefixes are supported 
            (For 'subscribe', the mapping will be reversed).
            <br/><!--TODO: -->Alias for 'subscribe' is currently not implemented!</p>
            <p>Example:<br/>
                <code>attr &lt;dev&gt; mqttAlias pub:temperature=temp</code></p>
        </p>
    </li>
  
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a><br/>
            Specific topics can be defined and assigned to the Readings(Format: &lt;reading&gt;:topic=&lt;topic&gt;). 
            Furthermore, these can be individually provided with 'qos' and 'retain' flags.<br/>
            Topics can also be defined as Perl expression with variables($reading, $device, $name, $base).<br/>
            Values for several readings can also be defined together, separated with '|'.<br/>
            If a '*' is used instead of a read name, this definition applies to all readings for which no explicit information was provided.<br/>
            Topic can also be written as a 'readings-topic'.<br/>
            Attributes can also be sent ("atopic" or "attr-topic").
            It is possible to define expressions (reading: expression = ...). <br/>
            The expressions could usefully change variables ($value, $topic, $qos, $retain, $message), or return a value of != undef.<br/>
            The return value is used as a new message value, the changed variables have priority.<br/>
            If the return value is undef, setting / execution is suppressed. <br/>
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
                attr &lt;dev&gt; mqttPublish *:resendOnConnect=last

                </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a><br/>
            This attribute configured receiving the MQTT messages and the corresponding reactions.<br/>
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
            The actual name of the reading (and possibly of the device) is defined by variables from the topic
            ($device (only for global definition in the bridge), $reading, $name).
            In the topic these variables act as wildcards, of course only makes sense, if reading-name is not defined (so start with '*').<br/>
            The variable $name, unlike $reading, may be affected by the aliases defined in 'mqttAlias'. Also use of $base is allowed.<br/>
            When using 'stopic', the 'set' command is executed as 'set &lt;dev&gt; &lt;reading&gt; &lt;value&gt;'.
            For something like 'set &lt;dev&gt; &lt;value&gt;'  'state' should be used as reading-name.</p>
            <p>Examples:<br/>
                <code>attr &lt;dev&gt; mqttSubscribe temperature:topic=/TEST/temperature test:qos=0 *:topic={"/TEST/$reading/value"} <br/>
                    attr &lt;dev&gt; mqttSubscribe desired-temperature:stopic={"/TEST/temperature/set"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={...}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={$value="x"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={"R1"=>$value, "R2"=>"Val: $value", "R3"=>"x"}
                    attr &lt;dev&gt; mqttSubscribe verbose:atopic={"/TEST/light/verbose"}
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
                attr sensor mqttPublish temperature:topic=/haus/sensor/temperature</code></p>
        </p>
    </li>

    <li>
        <p>Send all readings of a sensor (with their names as they are) via MQTT:<br/>
            <code> defmod sensor XXX<br/>
                attr sensor mqttPublish *:topic={"/sensor/$reading"}</code></p>
        </p>
    </li>
     
    <li>
        <p>Topic definition with shared part in 'base' variable:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttDefaults base={"/$device/$reading"}<br/>
                attr sensor mqttPublish *:topic={$base}</code></p>
        </p>
    </li>

    <li>
        <p>Topic definition only for certain readings with renaming (alias):<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttAlias temperature=temp humidity=hum<br/>
                attr sensor mqttDefaults base={"/$device/$name"}<br/>
                attr sensor mqttPublish temperature:topic={$base} humidity:topic={$base}<br/></code></p>
        </p>
    </li>

    <li>
        <p>Example of a central configuration in the bridge for all devices that have Reading named 'temperature':<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish temperature:topic={"/haus/$device/$reading"} <br/>
         </code></p>
        </p>
    </li>

    <li>
        <p>Example of a central configuration in the bridge for all devices:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish *:topic={"/haus/$device/$reading"} <br/></code></p>
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
    Dieses Modul ist eine MQTT-Bridge, die gleichzeitig mehrere FHEM-Devices erfasst und deren Readings 
    per MQTT weiter gibt bzw. aus den eintreffenden MQTT-Nachrichten befuellt oder diese als 'set'-Befehl 
    an dem konfigurierten FHEM-Geraet ausfuert.
    <br/>Es wird ein <a href="#MQTT">MQTT</a>-Geraet als IODev benoetigt.
 </p>
 <p>Die (minimale) Konfiguration der Bridge selbst ist grundsaetzlich sehr einfach.</p>
 <a name="MQTT_GENERIC_BRIDGEdefine"></a>
 <p><b>Definition:</b></p>
 <ul>
   <p>Im einfachsten Fall reichen schon zwei Zeilen:</p>
     <p><code>defmod mqttGeneric MQTT_GENERIC_BRIDGE [prefix] [devspec,[devspec]]</br>
     attr mqttGeneric IODev <MQTT-Device></code></p>
   <p>Alle Parameter im Define sind optional.</p>
   <p>Der erste ist ein Prefix fuer die Steuerattribute, worueber die zu ueberwachende Geraete (s.u.) 
   konfiguriert werden. Defaultwert ist 'mqtt'. 
   Wird dieser z.B. als 'hugo' redefiniert, heissen die Steuerungsattribute entsprechend hugoPublish etc.</p>
   <p>Der zweite Parameter ('devspec') erlaubt die Menge der zu ueberwachenden Geraeten 
   zu begrenzen (sonst werden einfach alle ueberwacht, was jedoch Performance kosten kann).
   Beispiel fuer devspec: 'TYPE=dummy' oder 'dummy1,dummy2'. Bei kommaseparierten Liste duerfen keine Leerzeichen verwendet werden!
   s.a. <a href="https://fhem.de/commandref_DE.html#devspec">devspec</a></p>
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
     Liefert Liste der Namen der von dieser Bridge ueberwachten Geraete deren Namen zu dem optionalen regulaerem Ausdruck entsprechen. 
     Fehlt der Ausdruck, werden alle Geraete aufgelistet. 
     </p>
   </li>
   <li>
     <p>devinfo [&lt;name (regex)&gt;]<br/>
     Gibt eine Liste der ueberwachten Geraete aus, deren Namen zu dem optionalen regulaerem Ausdruck entsprechen. 
     Fehlt der Ausdruck, werden alle Geraete aufgelistet. Zusaetzlich werden bei 'publish' und 'subscribe' 
     verwendete Topics angezeigt incl. der entsprechenden Readinsnamen.</p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEreadings"></a>
 <p><b>readings:</b></p>
 <ul>
   <li>
     <p>device-count<br/>
     Anzahl der ueberwachten Geraete</p>
   </li>
   <li>
     <p>incoming-count<br/>
     Anzahl eingehenden Nachrichten</p>
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
     letze Uebertragunsart</p>
   </li>
 </ul>

 <a name="MQTT_GENERIC_BRIDGEattr"></a>
 <p><b>Attribute:</b></p>
 <ul>
   <p>folgende Attribute werden unterstuetzt:</p>
   <li><p>IODev<br/>
     Dieses Attribut ist obligatorisch und muss den Namen einer funktionierenden MQTT-Modulinstanz enthalten. 
     Modul MQTT2_SERVER wird nicht unterstuetzt.</p>
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
        Definiert Defaults. Diese greifen in dem Fall, wenn in dem jeweiligen Geraet definierte Werte nicht zutreffen. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a>. 
     </p>
   </li>

   <li>
    <p>globalAlias<br/>
        Definiert Alias. Diese greifen in dem Fall, wenn in dem jeweiligen Geraet definierte Werte nicht zutreffen. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>.
     </p>
   </li>
   
   <li>
    <p>globalPublish<br/>
        Definiert Topics/Flags fuer die Uebertragung per MQTT. Diese werden angewendet, falls in dem jeweiligen Geraet 
        definierte Werte nicht greifen oder nicht vorhanden sind. 
        s.a. <a href="#MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a>.
     </p>
   </li>

   <li>
    <p>globalSubscribe ! TODO - wird derzeit nicht unterstuetzt und wird moeglicherweise gar nicht implementiert !<br/>
        Definiert Topics/Flags fuer die Aufnahme der Werte aus der MQTT-Uebertragung. Sie greifen, falls in dem jeweiligen Geraet 
        definierte Werte nicht greifen oder nicht vorhanden sind. s.a. <a href="#MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a>.
     </p>
   </li>

   <li>
    <p>globalTypeExclude<br/>
        Definiert (Geraete-)Typen und Readings, die nicht bei der Uebertragung beruecksichtigt werden. 
        Werte koennen getrennt fuer jede Richtung (buplish oder subscribe) vorangestellte Prefixe 'pub:' und 'sub:' angegeben werden.
        Ein einzelner Wert bedeutet, dass ein Geraet diesen Types komplett ignoriert wird (also fuer alle seine Readings und beide Richtungen).
        Durch ein Doppelpunkt getrennte Paare werden als [sub:|pub:]Type:Reading interptretiert. 
        Das Bedeutet, dass an dem gegebenen Type die genannte Reading nicht uebertragen wird.
        Ein Stern anstatt Type oder auch Reading bedeutet, dass alle Readings eines Geretaetyps
        bzw. genannte Readings an jedem Geraetetyp ignoriert werden. </p>
        <p>Beispiel:<br/>
        <code>attr &lt;dev&gt; globalTypeExclude MQTT MQTT_GENERIC_BRIDGE:* MQTT_BRIDGE:transmission-state *:baseID</code></p>
   </li>

   <li>
    <p>globalDeviceExclude<br/>
        Definiert Geraetenamen und Readings, die nicht uebertragen werden.
        Werte koennen getrennt fuer jede Richtung (buplish oder subscribe) vorangestellte Prefixe 'pub:' und 'sub:' angegeben werden.
        Ein einzelner Wert bedeutet, dass ein Geraet mit diesem Namen komplett ignoriert wird (also fuer alle seine Readings und beide Richtungen).
        Durch ein Doppelpunkt getrennte Paare werden als [sub:|pub:]Device:Reading interptretiert. 
        Das Bedeutet, dass an dem gegebenen Geraet die genannte Reading nicht uebertragen wird.</p>
        <p>Beispiel:<br/>
            <code>attr &lt;dev&gt; globalDeviceExclude Test Bridge:transmission-state</code></p>
   </li>

   <p>Fuer die ueberwachten Geraete wird eine Liste der moeglichen Attribute automatisch um mehrere weitere Eintraege ergaenzt. 
      Sie fangen alle mit vorher in der Bridge definiertem Prefix an. Ueber diese Attribute wird die eigentliche MQTT-Anbindung konfiguriert.<br/>
      Defaultmaessig werden folgende Attributnamen verwendet: mqttDefaults, mqttAlias, mqttPublish, mqttSubscribe.
      <br/>Die Bedeutung dieser Attribute wird im Folgenden erklaert.
    </p>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDefaults">mqttDefaults</a><br/>
            Hier wird eine Liste der "key=value"-Paare erwartet. Folgende Keys sind dabei moeglich:
            <ul>
             <li>'qos' <br/>definiert ein Defaultwert fuer MQTT-Paramter 'Quality of Service'.</li>
             <li>'retain' <br/>erlaubt MQTT-Nachrichten als 'retained messages' zu markieren.</li>
             <li>'base' <br/>wird als Variable ($base) bei der Konfiguration von konkreten Topics zur Verfuegung gestellt.
                   Sie kann entweder Text oder eine Perl-Expression enthalten. 
                   Perl-Expression muss in geschweifte Klammern eingeschlossen werden.
                   In einer Expression koennen folgende Variablen verwendet werden:
                   $base = entsprechende Definition aus dem '<a href="#MQTT_GENERIC_BRIDGEglobalDefaults">globalDefaults</a>', 
                   $reading = Original-Readingname, 
                   $device = Devicename und $name = Readingalias (s. <a href="#MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a>. 
                   Ist kein Alias definiert, ist $name=$reading).</li>
            </ul>
            <br/>
            Alle diese Werte koennen durch vorangestelle Prefixe ('pub:' oder 'sub') in ihrer Gueltigkeit 
            auf nur Senden bzw. nur Empfangen begrenzt werden (soweit sinnvoll). 
            Werte fuer 'qos' und 'retain' werden nur verwendet, 
            wenn keine explizite Angaben darueber fuer ein konkretes Topic gemacht worden sind.</p>
            <p>Beispiel:<br/>
                <code>attr &lt;dev&gt; mqttDefaults base={"/TEST/$device"} pub:qos=0 sub:qos=2 retain=0</code></p>
        </p>
    </li>
 

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttAlias">mqttAlias</a><br/>
            Dieses Attribut ermoeglicht Readings unter einem anderen Namen auf MQTT-Topic zu mappen. 
            Eigentlich nur sinnvoll, wenn Topicdefinitionen Perl-Expressions mit entsprechenden Variablen sind.
            Auch hier werden 'pub:' und 'sub:' Prefixe unterstuetzt (fuer 'subscribe' gilt das Mapping quasi umgekehrt).
            <br/><!--TODO: -->Alias fuer subscribe ist derzeit nicht implementiert!</p>
            <p>Beispiel:<br/>
                <code>attr &lt;dev&gt; mqttAlias pub:temperature=temp</code></p>
        </p>
    </li>
  
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttPublish">mqttPublish</a><br/>
            Hier werden konkrette Topics definiet und den Readings zugeordnet (Format: &lt;reading&gt;:topic=&lt;topic&gt;). 
            Weiterhin koennen diese einzeln mit 'qos'- und 'retain'-Flags versehen werden. <br/>
            Topics koennen auch als Perl-Expression mit Variablen definiert werden ($reading, $device, $name, $base).<br/>
            'topic' kann auch als 'readings-topic' geschrieben werden.<br/>
            Werte fuer mehrere Readings koennen auch gemeinsam gleichzeitig definiert werden, 
            indem sie, mittels '|' getrennt, zusammen angegeben werden.<br/>
            Wird anstatt eines Readingsnamen ein '*' verwendet, gilt diese Definition fuer alle Readings, 
            fuer die keine explizite Angaben gemacht wurden.<br/>
            Ebenso koennen auch Attributwerte gesendet werden ('atopic' oder 'attr-topic').
            Weiterhin koennen auch Expressions (reading:expression=...) definiert werden. <br/>
            Die Expressions koenne sinnvollerweise entweder Variablen ($value, $topic, $qos, $retain, $message) veraendern, oder einen Wert != undef zurrueckgeben.<br/>
            Der Rueckhgabe wert wird als neue Nachricht-Value verwendet, die Aenderung der Variablen hat dabei jedoch Vorrang.<br/>
            Ist der Rueckgabewert undef, dann wird das Setzen/Ausfuehren unterbunden. <br/>
            Ist die Rueckgabe ein Hash (nur 'topic'), werden seine Schluesselwerte als Topic verwendet, 
            die Inhalte der Nachrichten sind entsprechend die Werte aus dem Hash.</p>
            <p>Option 'resendOnConnect' erlaubt eine Speicherung der Nachrichten, 
            wenn keine Verbindung zu dem MQTT-Server besteht.
            Die zu sendende Nachrichten in einer Warteschlange gespeichet. 
            Wird die Verbindung aufgebaut, werden die Nachrichten in der ursprungichen Reihenfolge verschickt.
            <ul>Moegliche Werte: 
              <li>none<br/>alle verwerfen</li>
              <li>last<br/>immer nur die letzte Nachricht speichern</li>
              <li>first<br/>immer nur die erste Nachricht speichern danach folgende verwerfen</li>
              <li>all<br/>alle speichern, allerdings existiert eine Obergrenze von 100, 
              wird es mehr, werden aelteste ueberzaelige Nachrichten verworfen.</li>
            </ul>
            </p>
            <p>Beispiele:<br/>
                <code> attr &lt;dev&gt; mqttPublish temperature:topic={"$base/$name"} temperature:qos=1 temperature:retain=0 *:topic={"$base/$name"} humidity:topic=/TEST/Feuchte<br/>
                attr &lt;dev&gt; mqttPublish temperature|humidity:topic={"$base/$name"} temperature|humidity:qos=1 temperature|humidity:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} *:qos=2 *:retain=0<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={$value="message: $value"}<br/>
                attr &lt;dev&gt; mqttPublish *:topic={"$base/$name"} reading:expression={"/TEST/Topic1"=>"$message", "/TEST/Topic2"=>"message: $message"}</br>
                attr &lt;dev&gt; mqttPublish [...] *:resendOnConnect=last
                </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttSubscribe">mqttSubscribe</a><br/>
            Dieses Attribut konfiguriert das Empfangen der MQTT-Nachrichten und die entsprechenden Reaktionen darauf.<br/>
            Die Konfiguration ist aehnlich der fuer das 'mqttPublish'-Attribut. Es koennen Topics fuer das Setzen von Readings ('topic' oder auch 'readings-topic') und
            Aufrufe von 'set'-Befehl an dem Geraet ('stopic' oder 'set-topic') definiert werden. <br/>
            Ebenso koennen auch Attribute gesetzt werden ('atopic' oder 'attr-topic').</br>
            Mit Hilfe von zusaetzlichen auszufuehrenden Perl-Expressions ('expression') kann das Ergebnis vor dem Setzen/Ausfueren noch beeinflusst werden.<br/>
            In der Expression sind folgende Variablen verfuegbar: $device, $reading, $message (initial gleich $value).
            Die Expression kann dabei entweder Variable $value veraendern, oder einen Wert != undef zurueckgeben. Redefinition der Variable hat Vorrang.
            Ist der Rueckgabewert undef, dann wird das Setzen/Ausfuehren unterbunden (es sei denn, $value hat einen neuen Wert). <br/>
            Ist die Rueckgabe ein Hash (nur fuer 'topic' und 'stopic'), dann werden seine Schluesselwerte als Readingsnamen bzw. 'set'-Parameter verwendet, 
            die zu setzenden Werte sind entsprechend die Werte aus dem Hash.<br/>
            Weiterhin kann das Attribut 'qos' angegeben werden ('retain' macht dagegen keinen Sinn).<br/>
            In der Topic-Definition koennen MQTT-Wildcards (+ und #) verwendet werden. <br/>
            Falls der Reading-Name mit einem '*'-Zeichen am Anfang definiert wird, gilt dieser als 'Platzhalter'.
            Der tatsaechliche Name der Reading (und ggf. des Geraetes) wird dabei durch Variablen aus dem Topic 
            definiert ($device (nur fuer globale Definition in der Bridge), $reading, $name).
            Im Topic wirken diese Variablen als Wildcards, macht natuerlich nur Sinn, wenn Reading-Name auch nicht fest definiert ist (also faengt mit '*' an). <br/>
            Die Variable $name wird im Unterschied zu $reading ggf. ueber die in 'mqttAlias' definierten Aliases beeinflusst.
            Auch Verwendung von $base ist erlaubt.<br/>
            Bei Verwendung von 'stopic' wird das 'set'-Befehl als 'set &lt;dev&gt; &lt;reading&gt; &lt;value&gt;' ausgefuert.
            Fuer ein 'set &lt;dev&gt; &lt;value&gt;' soll als Reading-Name 'state' verwendet werden.</p>
            <p>Beispiele:<br/>
                <code>attr &lt;dev&gt; mqttSubscribe temperature:topic=/TEST/temperature test:qos=0 *:topic={"/TEST/$reading/value"} <br/>
                    attr &lt;dev&gt; mqttSubscribe desired-temperature:stopic={"/TEST/temperature/set"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={...}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={$value="x"}<br/>
                    attr &lt;dev&gt; mqttSubscribe state:stopic={"/TEST/light/set"} state:expression={"R1"=>$value, "R2"=>"Val: $value", "R3"=>"x"}
                    attr &lt;dev&gt; mqttSubscribe verbose:atopic={"/TEST/light/verbose"}
                 </code></p>
        </p>
    </li>

    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttForward">mqttForward</a><br/>
            Dieses Attribut definiert was passiert, wenn eine und dieselbe Reading sowohl aboniert als auch gepublisht wird. 
            Moegliche Werte: 'all' und 'none'. <br/>
            Bei 'none' werden per MQTT angekommene Nachrichten nicht aus dem selben Gerät per MQTT weiter gesendet.<br/>
            Die Einstellung 'all' bewirkt das Gegenteil, also damit wird das Weiterleiten ermoeglicht.<br/>
            Fehlt dieser Attribut, dann wird standartmaeßig für alle Geraetetypen außer 'Dummy' die Einstellung 'all' angenommen 
            (damit koennen Aktoren Befehle empfangen und ihre Änderungen im gleichem Zug weiter senden) 
            und fuer Dummies wird 'none' verwendet. Das wurde so gewaehlt, weil Dummies oft als eine Art GUI-Schalterelement verwendet werden. 
            In diesem Fall wuerde 'all' unter Umstaenden eine Endlosschleife der Nachrichten verursachen.
            </p>
        </p>
    </li>
    
    <li>
        <p><a name="MQTT_GENERIC_BRIDGEmqttDisable">mqttDisable</a><br/>
            Wird dieses Attribut in einem Geraet gesetzt, wird dieses Geraet vom Versand  bzw. Empfang der Readingswerten ausgeschlossen.</p>
        </p>
    </li>

</ul>
 
<p><b>Beispiele</b></p>

<ul>
    <li>
        <p>Bridge fuer alle moeglichen Geraete mit dem Standardprefix:<br/>
                <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE<br/>
                        attr mqttGeneric IODev mqtt</code>
        </p>
        </p>
    </li>
    
    <li>
        <p>Bridge mit dem Prefix 'mqtt' fuer drei bestimmte Geraete:<br/>
            <code> defmod mqttGeneric MQTT_GENERIC_BRIDGE mqtt sensor1,sensor2,sensor3<br/>
                    attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>

    <li>
        <p>Bridge fuer alle Geraete in einem bestimmten Raum:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE mqtt room=Wohnzimmer<br/>
                attr mqttGeneric IODev mqtt</code></p>
        </p>
    </li>
     
    <li>
        <p>Einfachste Konfiguration eines Temperatursensors:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttPublish temperature:topic=/haus/sensor/temperature</code></p>
        </p>
    </li>

    <li>
        <p>Alle Readings eines Sensors (mit ihren Namen wie sie sind) per MQTT versenden:<br/>
            <code> defmod sensor XXX<br/>
                attr sensor mqttPublish *:topic={"/sensor/$reading"}</code></p>
        </p>
    </li>
     
    <li>
        <p>Topicsdefinition mit Auslagerung von dem gemeinsamen Teilnamen in 'base'-Variable:<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttDefaults base={"/$device/$reading"}<br/>
                attr sensor mqttPublish *:topic={$base}</code></p>
        </p>
    </li>

    <li>
        <p>Topicsdefinition nur fuer bestimmte Readings mit deren gleichzeitigen Umbennenung (Alias):<br/>
            <code>defmod sensor XXX<br/>
                attr sensor mqttAlias temperature=temp humidity=hum<br/>
                attr sensor mqttDefaults base={"/$device/$name"}<br/>
                attr sensor mqttPublish temperature:topic={$base} humidity:topic={$base}<br/></code></p>
        </p>
    </li>

    <li>
        <p>Beispiel fuer eine zentralle Konfiguration in der Bridge fuer alle Devices, die Reading 'temperature' besitzen:<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish temperature:topic={"/haus/$device/$reading"} <br/>
         </code></p>
        </p>
    </li>

    <li>
        <p>Beispiel fuer eine zentralle Konfiguration in der Bridge fuer alle Devices <br/>
                (wegen einer schlechte uebersicht und einer unnoetig grossen Menge eher nicht zu empfehlen):<br/>
            <code>defmod mqttGeneric MQTT_GENERIC_BRIDGE <br/>
                attr mqttGeneric IODev mqtt <br/>
                attr mqttGeneric defaults sub:qos=2 pub:qos=0 retain=0 <br/>
                attr mqttGeneric publish *:topic={"/haus/$device/$reading"} <br/></code></p>
        </p>
    </li>
</ul>

<p><b>Einschraenkungen:</b></p>

<ul>
      <li>Wenn mehrere Readings das selbe Topic abonieren, sind dabei keine unterschiedlichen QOS moeglich.</li>
      <li>Wird in so einem Fall QOS ungleich 0 benoetigt, sollte dieser entweder fuer alle Readings gleich einzeln definiert werden,
      oder allgemeinguetltig ueber Defaults. <br/>
      Ansonsten wird beim Erstellen von Abonements der erst gefundene Wert verwendet. </li>
      <li>Abonements werden nur erneuert, wenn sich das Topic aendert, QOS-Flag-Aenderung alleine wirkt sich daher erst nach einem Neustart aus.</li>
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

=end html_DE
=cut
