#########################################################################################################################
# $Id$
#########################################################################################################################
#
# 70_PylonLowVoltage.pm
#
# A FHEM module to read BMS values from Pylontech Low Voltage LiFePo04 batteries.
#
# This module uses the idea and informations from 70_Pylontech.pm written 2019 by Harald Schmitz.
# Further code development and extensions by Heiko Maaz (c) 2023 e-mail: Heiko dot Maaz at t-online dot de
#
# Credits to FHEM user: satprofi, Audi_Coupe_S, abc2006
#
#########################################################################################################################
# Copyright notice
#
# (c) 2019 Harald Schmitz (70_Pylontech.pm)
# (c) 2023 - 2026 Heiko Maaz
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# The GNU General Public License can be found at
# http://www.gnu.org/copyleft/gpl.html.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# This copyright notice MUST APPEAR in all copies of the script!
#
#########################################################################################################################
# Forumlinks:
# https://forum.fhem.de/index.php?topic=117466.0  (Source of module 70_Pylontech.pm)
# https://forum.fhem.de/index.php?topic=126361.0
# https://forum.fhem.de/index.php?topic=112947.0
# https://forum.fhem.de/index.php?topic=32037.0
#
# Photovoltaik Forum:
# https://www.photovoltaikforum.com/thread/130061-pylontech-us2000b-daten-protokolle-programme
#
#########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 70_PylonLowVoltage.pm
#
#########################################################################################################################
package FHEM::PylonLowVoltage;                                     ## no critic 'package'

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);                               # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday ualarm sleep usleep);
use IO::Socket::INET;
use Errno qw(ETIMEDOUT EWOULDBLOCK);
use Scalar::Util qw(looks_like_number);
use Carp qw(croak carp);
use SubProcess;

eval "use FHEM::Meta;1"                or my $modMetaAbsent = 1;                             ## no critic 'eval'                                                                                                               
eval "use Storable qw(freeze thaw);1;" or my $storabs       = 'Storable';                    ## no critic 'eval'

use FHEM::SynoModules::SMUtils qw(moduleVersion);                                            # Hilfsroutinen Modul
#use Data::Dumper;

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          AttrVal
          AttrNum
          data
          defs
          devspec2array
          fhem
          fhemTimeLocal
          FmtTime
          FmtDateTime
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3
          modules
          parseParams
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsAge
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          selectlist
          readyfnlist
        )
  );

  # Export to main context with different name
  GP_Export(
      qw(
          Initialize
        )
  );
}

# Versions History intern (Versions history by Heiko Maaz)
my %vNotesIntern = (
  "2.0.0"  => "22.08.2026 grundlegendes Architektur-Redesign: dauerhafter, gateway-bezogener SubProcess (SubProcess.pm) ".
                          "ersetzt BlockingCall und die bisherige FIFO-Warteschlange im Hauptprozess am selben Gateway (gleiches host:port). ".
                          "prioSave gesetzt, damit der Gateway-Subprozess beim FHEM-Start geforkt wird solange der ".
                          "Hauptprozess noch wenig Speicher belegt (kleiner Speicherfußabdruck des SubProcess). ".
                          "Siehe Forum: https://forum.fhem.de/index.php/topic,130588.msg1249277.html#msg1249277 ".
                          "Befehl 'get <name> listQueue' zeigt die Wartezeit je Device an ".
                          "Ursache für das schleichende Ausfallen aller Devices gefunden und behoben ".
                          "Change: default 1.0 für waitTimeBetweenRS485Cmd, Wertevorrat Slider angepasst ".
                          "state 'Commands sent - waiting for data' wird nach senden Request gesetzt ".
                          "initialen SubProzess-Start verbessert ".
                          "Reading averageCellVolt in cellVoltageAvg umbenannt -> Reading averageCellVolt löschen! ",
  "1.3.0"  => "16.08.2026 Ersatz der gegenseitigen 'Busy-Loop'- und 'Random-Retry'-Mechanismen durch eine FIFO-Warteschlange ".
                          "pro Gateway (im Bereich Host:Port), ".
                          "Sofortige Übergabe an das nächste wartende Gerät statt einer zufälligen Verzögerung; deaktivierte/gelöschte Geräte werden übersprungen ".
                          "neuer Befehl 'listQueue' zum Abrufen des aktuellen Warteschlangenstatus ".
                          "neue Readings cellVoltageMax, cellVoltageMin, cmdChainDuration ".
                          "Slider für waitTimeBetweenRS485Cmd angepasst ",
  "1.2.2"  => "14.03.2026 GW_composeAddr: bug fix addressing batteries with address 9 and above ",
  "1.2.1"  => "29.12.2024 manageUpdate: use random time delay ",
  "1.2.0"  => "05.10.2024 GW_composeAddr: bugfix of effective battaery addressing ",
  "1.1.0"  => "25.08.2024 manage time shift for active gateway connections of all defined  devices ",
  "1.0.0"  => "24.08.2024 implement pylon groups ",
  "0.4.0"  => "23.08.2024 Log output for timeout changed, automatic calculation of checksum, preparation for pylon groups ",
  "0.3.0"  => "22.08.2024 extend battery addresses up to 16 ",
  "0.2.6"  => "25.05.2024 replace Smartmatch Forum:#137776 ",
  "0.2.5"  => "02.04.2024 GW_callAnalogValue / GW_callAlarmInfo: integrate a Cell and Temperature Position counter ".
                          "add specific Alarm readings ",
  "0.2.4"  => "29.03.2024 avoid possible Illegal division by zero at line 1438 ",
  "0.2.3"  => "19.03.2024 edit commandref ",
  "0.2.2"  => "20.02.2024 correct commandref ",
  "0.2.1"  => "18.02.2024 GW_doOnError: print out faulty response, Forum:https://forum.fhem.de/index.php?msg=1303912 ",
  "0.2.0"  => "15.12.2023 extend possible number of batteries up to 14 ",
  "0.1.11" => "28.10.2023 add needed data format to commandref ",
  "0.1.10" => "18.10.2023 new function GW_pseudoHexToText in GW_callManufacturerInfo for translate battery name and Manufactorer ",
  "0.1.9"  => "25.09.2023 fix possible bat adresses ",
  "0.1.8"  => "23.09.2023 new Attr userBatterytype, change manufacturerInfo, protocolVersion command hash to LENID=0 ",
  "0.1.7"  => "20.09.2023 extend possible number of bats from 6 to 8 ",
  "0.1.6"  => "19.09.2023 rework of GW_callAnalogValue, support of more than 15 cells ",
  "0.1.5"  => "19.09.2023 internal code change ",
  "0.1.4"  => "24.08.2023 Serialize and deserialize data for update entry, usage of BlockingCall in case of long timeout ",
  "0.1.3"  => "22.08.2023 improve GW_responseCheck and others ",
  "0.1.2"  => "20.08.2023 commandref revised, analogValue -> use 'user defined items', refactoring according PBP ",
  "0.1.1"  => "16.08.2023 integrate US3000C, add print request command in HEX to Logfile, attr timeout ".
                          "change validation of received data, change DEF format, extend evaluation of chargeManagmentInfo ".
                          "add evaluate systemParameters, additional own values packImbalance, packState ",
  "0.1.0"  => "12.08.2023 initial version, switch to perl package, attributes: disable, interval, add command hashes ".
                          "get ... data command, add meta support and version management, more code changes ",
);

## Konstanten
###############
my $definterval   = 30;                                              # default Abrufintervall der Batteriewerte
my $defto         = 3;                                               # default für das Attribut "timeout" - gilt für die GESAMTE RS485-Kommandokette eines Zyklus
my $gwconnto      = 0.5;                                             # Verbindungsaufbau-Timeout (s) - RS485-Kommunikation und soll bei einem toten Gateway zügig als solches erkannt werden
my @blackl        = qw(state nextCycletime);                         # Ausnahmeliste deleteReadingspec
my $age1def       = 60;                                              # default Zyklus Abrufklasse statische Werte (s)
my $wtbRS485cmd   = 1.0;                                             # default Wartezeit zwischen RS485 Kommandos
my $pfx           = "~";                                             # KommandoPräfix
my $sfx           = "\x{0d}";                                        # Kommandosuffix
my $gwpoll        = 5;                                               # Prüfintervall (s) während des Wartens auf eine Antwort
my $gwstall       = 20;                                              # Sekunden gänzlich ohne Gateway-Aktivität, ab denen ein SubProcess als hängend gilt
my $gwmaxwait     = 120;                                             # absolute Obergrenze (s) für die Wartezeit eines einzelnen Requests (Sicherheitsnetz)

my $ChildSubprocess;                                                 # nur im Kindprozess gesetzt (getrennter Prozessspeicher nach fork!)

# Steuerhashes
###############
my %hrtnc = (                                                        # RTN Codes
  '00' => { desc => 'normal'                  },                     # normal Code
  '01' => { desc => 'VER error'               },
  '02' => { desc => 'CHKSUM error'            },
  '03' => { desc => 'LCHKSUM error'           },
  '04' => { desc => 'CID2 invalidation error' },
  '05' => { desc => 'Command format error'    },
  '06' => { desc => 'invalid data error'      },
  '90' => { desc => 'ADR error'               },
  '91' => { desc => 'Communication error between Master and Slave Pack'                                  },
  '98' => { desc => 'insufficient response length <LEN> of minimum length <MLEN> received ... discarded' },
  '99' => { desc => 'invalid data received ... discarded'                                                },
);

my %fncls = (                                                                   # Funktionsklassen
  1 => { class => 'sta', fn => \&GW_callSerialNumber        },                  #   statisch - serialNumber
  2 => { class => 'sta', fn => \&GW_callManufacturerInfo    },                  #   statisch - manufacturerInfo
  3 => { class => 'sta', fn => \&GW_callProtocolVersion     },                  #   statisch - protocolVersion
  4 => { class => 'sta', fn => \&GW_callSoftwareVersion     },                  #   statisch - softwareVersion
  5 => { class => 'sta', fn => \&GW_callSystemParameters    },                  #   statisch - systemParameters
  6 => { class => 'dyn', fn => \&GW_callAnalogValue         },                  #   dynamisch - analogValue
  7 => { class => 'dyn', fn => \&GW_callAlarmInfo           },                  #   dynamisch - alarmInfo
  8 => { class => 'dyn', fn => \&GW_callChargeManagmentInfo },                  #   dynamisch - chargeManagmentInfo
);

my %halm = (                                                                    # Codierung Alarme
  '00' => { alm => 'normal'            },
  '01' => { alm => 'below lower limit' },
  '02' => { alm => 'above higher limit'},
  'F0' => { alm => 'other error'       },
);

##################################################################################################################################################################
# The Basic data format SOI (7EH, ASCII '~') and EOI (CR -> 0DH) are explained and transferred in hexadecimal,
# the other items are explained in hexadecimal and transferred by hexadecimal-ASCII, each byte contains two
# ASCII, e.g. CID2 4BH transfer 2byte:
# 34H (the ASCII of '4') and 42H(the ASCII of 'B').
#
# HEX-ASCII converter: https://www.rapidtables.com/convert/number/ascii-hex-bin-dec-converter.html
# Modulo Rechner: https://miniwebtool.com/de/modulo-calculator/
# Pylontech Dokus: https://github.com/Interster/PylonTechBattery
#
# '--'  -> Platzhalter für Batterieadresse, wird ersetzt durch berechnete Adresse (Bat + Group in GW_composeAddr)
##################################################################################################################################################################
my %hrsnb = (
  1 => { cmd => '20--4693E002--', fnclsnr => 1, fname => 'serialNumber', mlen => 52 },
);

my %hrmfi = (
  1 => { cmd => '20--46510000', fnclsnr => 2, fname => 'manufacturerInfo', mlen => 82 },
);

my %hrprt = (
  1 => { cmd => '00--464F0000', fnclsnr => 3, fname => 'protocolVersion', mlen => 18 },
);

my %hrswv = (
  1 => { cmd => '20--4696E002--', fnclsnr => 4, fname => 'softwareVersion', mlen => 30 },
);

my %hrspm = (
  1 => { cmd => '20--4647E002--', fnclsnr => 5, fname => 'systemParameter', mlen => 68 },
);

my %hrcmn = (
  1 => { cmd => '20--4642E002--', fnclsnr => 6, fname => 'analogValue', mlen => 128 },
);

my %hralm = (
  1 => { cmd => '20--4644E002--', fnclsnr => 7, fname => 'alarmInfo', mlen => 82 },
);

my %hrcmi = (
  1 => { cmd => '20--4692E002--', fnclsnr => 8, fname => 'chargeManagmentInfo', mlen => 38 },
);


###############################################################
#                  PylonLowVoltage Initialize
###############################################################
sub Initialize {
  my $hash = shift;

  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undef;
  $hash->{GetFn}      = \&Get;
  $hash->{AttrFn}     = \&Attr;
  $hash->{ShutdownFn} = \&Shutdown;
  $hash->{AttrList}   = "disable:1,0 ".
                        "interval ".
                        "timeout ".
                        "userBatterytype ".
                        "waitTimeBetweenRS485Cmd:slider,0.1,0.1,2.05,1 ".
                        $readingFnAttributes;

  # prioSave: Definition wird beim Speichern der Konfiguration an den Anfang gestellt.
  # Laut fhem.pl: "prioSave - save the definition at the start, for a small SubProcess".
  # Dadurch wird beim FHEM-Start dieses Device (und damit ggf. der Gateway-Subprozess)
  # bevorzugt vor anderen Definitionen geladen, solange der FHEM-Hauptprozess noch
  # möglichst wenig Speicher belegt hat - der beim fork() kopierte Speicherfußabdruck
  # des Subprozesses bleibt dadurch klein.
  # Siehe auch Forum: https://forum.fhem.de/index.php/topic,130588.msg1249277.html#msg1249277
  $hash->{prioSave} = 1;

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'

return;
}

###############################################################
#                  PylonLowVoltage Define
###############################################################
sub Define {
  my ($hash, $def) = @_;
  my @args         = split m{\s+}x, $def;

  if (int(@args) < 2) {
      return "Define: too few arguments. Usage:\n" .
              "define <name> PylonLowVoltage <host>:<port> [<bataddress>]";
  }

  my $name = $hash->{NAME};

  if ($storabs) {
      my $err = "Perl module >$storabs< is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden

  my ($a,$h)                     = parseParams (join ' ', @args);
  ($hash->{HOST}, $hash->{PORT}) = split ":", $$a[2];

  if (!$hash->{HOST} || !$hash->{PORT}) {
      return "The <hostname/ip>:<port> must be specified.";
  }

  if (defined $$a[3] && $$a[3] !~ /^([1-9]{1}|1[0-6])$/xs) {
      return "The bataddress must be an integer from 1 to 16";
  }

  if (defined $h->{group} && $h->{group} !~ /^([0-7]{1})$/xs) {
      return "The group number must be an integer from 0 to 7";
  }

  $hash->{HELPER}{BATADDRESS} = $$a[3]      // 1;
  $hash->{HELPER}{GROUP}      = $h->{group} // 0;

  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 0,
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen
  
  gwAttach       ($hash); 
  gwDeferredInit ($hash);                                                          # wartet auf init_done, siehe dort

return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg,
# der ebenfalls alle Geräte löscht und danach das
# Konfigurationsfile neu einliest. Entsprechend müssen in der
# Funktion typische Aufräumarbeiten durchgeführt werden.
################################################################
sub Undef {
  my $hash = shift;
  my $name = shift;

  RemoveInternalTimer ($hash);
  gwDetach            ($hash);                                                      # Refcount runter, ggf. Subprozess beenden

return;
}

###############################################################
#                  PylonLowVoltage Shutdown
###############################################################
sub Shutdown {
  my ($hash, $args) = @_;

  RemoveInternalTimer ($hash);
  gwDetach            ($hash, 1);                                                   # Force-Bit bei Shutdown

return;
}

###############################################################
#                  PylonLowVoltage Get
###############################################################
sub Get {
  my ($hash, @a) = @_;
  return qq{"get X" needs at least an argument} if(@a < 2);
  my $name = shift @a;
  my $opt  = shift @a;

  my $getlist = "Unknown argument $opt, choose one of ".
                "data:noArg ".
                "listQueue:noArg "
                ;

  return if(IsDisabled($name));

  if ($opt eq 'data') {
      manageUpdate ($hash);
      return;
  }

  if ($opt eq 'listQueue') {
      return listQueue ($hash);
  }

return $getlist;
}

###############################################################
#  liefert eine lesbare Übersicht zum Gateway-Subprozess und
#  der aktuellen Warteschlange für "get <name> listQueue"
###############################################################
sub listQueue {
  my $hash = shift;
  my $gwk  = gwKey ($hash);
  my $gw   = $data{PylonLowVoltage}{GW}{$gwk};

  my $out = "Gateway: $gwk\n";

  if (!$gw) {
      $out .= "subprocess: not running\n";
      return $out;
  }

  my $alive = (defined $gw->{pid} && kill (0, $gw->{pid})) ? "running" : "dead";
  my @using = gwDevicesUsing ($gwk);                                                            # live aus %defs ermittelt, kein Zähler

  $out .= "subprocess PID: $gw->{pid} ($alive)\n";
  $out .= "devices sharing this gateway: ".(scalar @using)." (".join(", ", sort @using).")\n";

  my @pending = $gw->{pending} ? @{$gw->{pending}} : ();

  if (!@pending) {
      $out .= "queue: empty\n";
  }
  else {
      $out .= "queue: (".scalar(@pending)." waiting, in send order - position 1 is being processed or next in line)\n";
      my $pos = 1;
      my $now = gettimeofday();

      for my $e (@pending) {
          my $age = sprintf "%.1f", $now - ($e->{sent_at} // $now);
          $out .= sprintf "  %2d. %-20s waiting %s s%s\n", $pos, $e->{name}, $age, ($e->{name} eq $hash->{NAME} ? "   <- this device" : "");
          $pos++;
      }
  }

return $out;
}

###############################################################
#                  PylonLowVoltage Attr
###############################################################
sub Attr {
  my $cmd   = shift;
  my $name  = shift;
  my $aName = shift;
  my $aVal  = shift;
  my $hash  = $defs{$name};

  my ($do, $val);

  if ($aName eq 'disable') {
      if($cmd eq 'set') {
          $do = $aVal ? 1 : 0;
      }

      $do  = 0 if($cmd eq 'del');
      $val = ($do == 1 ? 'disabled' : 'initialized');

      readingsSingleUpdate ($hash, 'state', $val, 1);

      if ($do == 0) {
          gwDeferredInit ($hash);
          #InternalTimer(gettimeofday() + 2.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      }
      else {
          RemoveInternalTimer ($hash);                                  # entfernt u.a. manageUpdate- und gwCheckProgress-Timer
          deleteReadingspec   ($hash);
          readingsDelete      ($hash, 'nextCycletime');
          gwRemovePending     (gwKey ($hash), $name);                   # sonst bliebe ein "Geister"-Eintrag dauerhaft in der Warteschlange
      }
  }

  if ($cmd eq 'set') {
      if ($aName eq 'interval') {
          if (!looks_like_number($aVal)) {
              return qq{The value for $aName is invalid, it must be numeric!};
          }

          gwDeferredInit ($hash);
          #InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      }

      if ($aName =~ /timeout|waitTimeBetweenRS485Cmd/xs) {
          if (!looks_like_number($aVal)) {
              return qq{The value for $aName is invalid, it must be numeric!};
          }
      }
  }

  if ($aName eq 'userBatterytype') {
      delete $hash->{HELPER}{LASTSTATIC};                                                       # erzwingt einmalig den Refetch der statischen Klasse im nächsten Zyklus
      gwDeferredInit ($hash);
      #InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
  }

return;
}

###############################################################
#             Eintritt in den Update-Prozess
#             (Parent-Prozess)
###############################################################
sub manageUpdate {
  my $hash = shift;
  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash, 'FHEM::PylonLowVoltage::manageUpdate');
  
  return if(IsDisabled ($name));

  if (!$init_done) {
      InternalTimer(gettimeofday() + 2, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      return;
  }
  
  my $interval = AttrVal ($name, 'interval', $definterval);                             # 0 -> manuell gesteuert

  if (!$interval) {
      $hash->{OPMODE} = 'Manual';
      readingsSingleUpdate ($hash, 'nextCycletime', 'Manual', 0);
  }
  else {
      my $new = gettimeofday() + $interval;
      InternalTimer ($new, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);            # Wiederholungsintervall

      $hash->{OPMODE} = 'Automatic';
      readingsSingleUpdate ($hash, 'nextCycletime', FmtTime ($new), 0);
  }
  
  return if(gwIsPending ($hash));                                                       # vorheriger Request noch nicht beantwortet (live aus der Warteschlange geprüft)

  my $laststatic  = $hash->{HELPER}{LASTSTATIC} // 0;                                   # NUR bei tatsächlichem Erfolg gesetzt (siehe finishUpdate) -
                                                                                        # bewusst NICHT von ReadingsAge('serialNumber',...) abgeleitet,
                                                                                        # da deleteReadingspec (Fehlerpfad) dieses Reading sonst mitlöscht
                                                                                        # und dadurch bei JEDEM Fehlschlag einen teureren Refetch der
                                                                                        # kompletten statischen Klasse erzwingen würde - eine sich selbst
                                                                                        # verstärkende Kaskade, die genau zu dem beobachteten "nach und
                                                                                        # nach steigen alle Devices aus" führen kann.
  my $statage     = gettimeofday() - $laststatic;
  my $wantstatic  = ($statage < $age1def) ? 0 : 1;                                      # statische Klasse nur abrufen wenn "alt genug" oder noch nie erfolgreich geholt

  gwSendRequest ($hash, $wantstatic);

return;
}

###############################################################
#    Restaufgaben nach Update (Parent-Prozess)
###############################################################
sub finishUpdate {
  my ($hash, $success, $readings, $msg) = @_;
  my $name = $hash->{NAME};

  if ($success) {
      Log3 ($name, 4, "$name - got data from battery number >$hash->{HELPER}{BATADDRESS}<, group >$hash->{HELPER}{GROUP}< successfully");

      $hash->{HELPER}{LASTSTATIC} = gettimeofday() if(defined $readings->{serialNumber});   # statische Klasse wurde in diesem Zyklus tatsächlich (erfolgreich) geholt

      additionalReadings ($readings);                                                       # zusätzliche eigene Readings erstellen
      $readings->{state} = 'connected';
  }
  else {
      deleteReadingspec ($hash);
      $readings->{state} = $msg;
      Log3 ($name, 3, "$name - $msg") if($msg);
  }

  createReadings ($hash, $success, $readings);                                              # Readings erstellen

return;
}

###############################################################
#  wartet bis FHEM vollständig initialisiert ist (init_done),
#  bevor der Gateway-Subprozess angehängt und der erste
#  Update-Zyklus gestartet wird.
###############################################################
sub gwDeferredInit {
  my $hash = shift;
  my $name = $hash->{NAME};

  if (!$init_done) {
      InternalTimer (gettimeofday() + 1, "FHEM::PylonLowVoltage::gwDeferredInit", $hash, 0);
      return;
  }

  InternalTimer (gettimeofday() + 2, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);

return;
}

###############################################################
#  Device registriert sich als Nutzer eines Gateways
#  (Refcount hoch)
###############################################################
sub gwAttach {
  my $hash = shift;
  
  _gwEnsureSubprocess ($hash);
  
return;
}

###############################################################
#  sorgt dafür, dass für dieses Device ein laufender
#  Gateway-Subprozess existiert; startet ihn ggf. neu falls
#  tot oder noch nicht vorhanden (Parent-Prozess)
###############################################################
sub _gwEnsureSubprocess {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $gwk  = gwKey ($hash);

  my $gw = $data{PylonLowVoltage}{GW}{$gwk};

  if ($gw && defined $gw->{pid} && kill (0, $gw->{pid})) {
      $hash->{SBP_PID}   = $gw->{pid};
      $hash->{SBP_STATE} = 'running';
      return $gw;                                                                   # existiert bereits und lebt
  }

  if ($gw) {
      Log3 ($name, 3, "$name - Gateway subprocess for $gwk found dead, restarting");
      _gwUnregisterSelect ($gwk);

      $hash->{SBP_STATE} = 'dead (' .$gw->{pid}. ')';
      delete $hash->{SBP_PID};

      delete $data{PylonLowVoltage}{GW}{$gwk};
  }

  my $subprocess = SubProcess->new ( { onRun  => \&GW_onRun,
                                       onExit => \&GW_onExit
                                     } );

  $subprocess->{gwkey} = $gwk;

  my $pid = $subprocess->run();

  if (!defined $pid) {
      Log3 ($name, 1, "$name - ERROR - Cannot create gateway subprocess for $gwk");

      $hash->{SBP_STATE} = 'try_restart';
      delete $hash->{SBP_PID};
  
      return;
  }

  Log3 ($name, 3, "Gateway subprocess >$pid< for $gwk started [initialized by $name]");
  
  delete ($readyfnlist{"PLVGW.$gwk"});
  
  my $now = gettimeofday();
  $data{PylonLowVoltage}{GW}{$gwk} = { subprocess    => $subprocess,
                                       pid           => $pid,
                                       pending       => [],                         # {name=>..., sent_at=>...} je Device mit unbeantwortetem Request, in Sendereihenfolge
                                       last_activity => $now,                       # Zeitpunkt der letzten beobachteten Aktivität (irgendeine Antwort/Logzeile) dieses Gateways
                                     };

  $selectlist{"PLVGW.$gwk"} = { NAME         => "PLVGW.$gwk",
                                FD           => (fileno $subprocess->child()),
                                directReadFn => \&gwRead,
                                gwkey        => $gwk,
                              };
                              
  $hash->{SBP_PID}   = $pid;
  $hash->{SBP_STATE} = 'running';

return $data{PylonLowVoltage}{GW}{$gwk};
}

###############################################################
#  Device meldet sich ab (Refcount runter) - Aufruf aus
#  Undef/Shutdown. Bei Refcount 0 wird der Subprozess beendet.
###############################################################
sub gwDetach {
  my $hash  = shift;
  my $force = shift // 0;
  
  my $name = $hash->{NAME};
  my $gwk  = gwKey ($hash);

  return if(!defined $data{PylonLowVoltage}{GW}{$gwk});
  
  gwRemovePending ($gwk, $name);                                                    # kein "Geister"-Eintrag falls gerade ein Request unbeantwortet war

  my @others = gwDevicesUsing ($gwk, $name);                                        # alle AUSSER sich selbst, live aus %defs ermittelt

  return if(@others && !$force);                                                    # noch andere Devices aktiv und kein Shutdown -> Subprozess bleibt

  _gwStopSubprocess ($hash, $gwk);

return;
}

###############################################################
#  Subprocess für ein Gateway hart beenden und Strukturen
#  aufräumen
###############################################################
sub _gwStopSubprocess {
  my ($hash, $gwk) = @_;
  
  my $gw = $data{PylonLowVoltage}{GW}{$gwk};
  return if(!$gw);

  if (defined $gw->{pid}) {
      kill ('SIGKILL', $gw->{pid});
      waitpid ($gw->{pid}, 0);
  }
  
  my $name = $hash->{NAME};
  Log3 ($name, 3, "Gateway subprocess >$gw->{pid}< for $gwk stpped [killed by $name]");

  _gwUnregisterSelect ($gwk);
  
  $hash->{SBP_STATE} = 'stopped (' . $hash->{SBP_PID} . ')';
  
  delete $hash->{SBP_PID};
  delete $data{PylonLowVoltage}{GW}{$gwk};

return;
}

###############################################################
#  Select-Loop Eintrag für ein Gateway entfernen
###############################################################
sub _gwUnregisterSelect {
  my $gwk = shift;
  
  delete $selectlist{"PLVGW.$gwk"};
  
return;
}

###############################################################
#  ermittelt robust alle aktuell in %defs vorhandenen,
#  NICHT deaktivierten PylonLowVoltage-Devices,
#  die dasselbe Gateway (host:port) referenzieren. 
###############################################################
sub gwDevicesUsing {
  my $gwk     = shift;
  my $exclude = shift // '';

  my @using;

  for my $dev (devspec2array ('TYPE=PylonLowVoltage')) {
      next if($dev eq $exclude);
      next if(!defined $defs{$dev});
      next if(IsDisabled ($dev));                                                   # ein deaktiviertes Device sendet nie Requests und "nutzt" das Gateway faktisch nicht

      my $dhash = $defs{$dev};
      next if(!defined $dhash->{HOST} || !defined $dhash->{PORT});

      push @using, $dev if(gwKey ($dhash) eq $gwk);
  }

return @using;
}

###############################################################
#   Request an den Gateway-Subprozess senden (Parent-Prozess)
#   Verarbeitung in GW_onRun
###############################################################
sub gwSendRequest {
  my $hash       = shift;
  my $wantstatic = shift;

  my $name = $hash->{NAME};
  my $gwk  = gwKey ($hash);
  my $gw   = _gwEnsureSubprocess ($hash);                                           # ggf. Selbstheilung falls Subprozess tot/fehlend

  if (!$gw) {
      readingsSingleUpdate ($hash, 'state', 'ERROR - gateway subprocess not available', 1);
      return;
  }

  my $timeout = AttrVal ($name, 'timeout', $defto);
  my $wtb     = AttrVal ($name, 'waitTimeBetweenRS485Cmd', $wtbRS485cmd);

  my $req = { device          => $name,
              host            => $hash->{HOST},
              port            => $hash->{PORT},
              bataddr         => $hash->{HELPER}{BATADDRESS},
              group           => $hash->{HELPER}{GROUP},
              timeout         => $timeout,
              wtb             => $wtb,
              wantstatic      => $wantstatic,
              userbatterytype => AttrVal ($name, 'userBatterytype', ''),            # frisch je Request, kein Fork-Snapshot
              verbose         => AttrVal ($name, 'verbose', 3),                     # frisch je Request, kein Fork-Snapshot
            };

  my $serial = eval { freeze ($req) };

  if (!$serial) {
      Log3 ($name, 1, "$name - ERROR - could not serialize request for gateway subprocess");
      readingsSingleUpdate ($hash, 'state', 'ERROR - request serialization failed', 1);
      return;
  }

  $gw->{subprocess}->writeToChild ($serial);
  
  readingsSingleUpdate ($hash, 'state', 'Commands sent - waiting for data', 1);

  $gw->{pending} //= [];
  gwRemovePending ($gwk, $name);                                                    # defensiv: keine Dubletten, falls doch noch ein alter Eintrag da wäre
  
  my $now = gettimeofday();
  push @{$gw->{pending}}, { name => $name, sent_at => $now };                       # dieser Eintrag IST der "pending"-Status, kein separates Flag mehr nötig

  my $qpos = scalar @{$gw->{pending}};                                              # eigene Position in der Warteschlange (inkl. sich selbst), nur zur Anzeige

  RemoveInternalTimer ($hash, 'FHEM::PylonLowVoltage::gwCheckProgress');
  InternalTimer (gettimeofday() + $gwpoll, 'FHEM::PylonLowVoltage::gwCheckProgress', $hash, 0);

  Log3 ($name, 4, "$name - request sent to gateway subprocess >$gw->{pid}< for $hash->{HOST}:$hash->{PORT}, queue position $qpos");

return;
}

###############################################################
#  periodische Fortschrittsprüfung, während ein Request aussteht.
#  Wird alle $gwpoll Sekunden erneut aufgerufen. Solange der
#  Gateway-SubProcess IRGENDEINE Aktivität zeigt (auch für andere
#  Devices am selben Gateway - siehe last_activity in gwRead),
#  wird geduldig weitergewartet. Erst wenn seit $gwstall Sekunden
#  gar nichts mehr passiert, ODER die absolute Obergrenze
#  $gwmaxwait erreicht ist, wird eingegriffen.
###############################################################
sub gwCheckProgress {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $gwk  = gwKey ($hash);

  return if(!gwIsPending ($hash));                                                      # Antwort ist inzwischen via gwRead eingetroffen, nichts zu tun

  my $gw      = $data{PylonLowVoltage}{GW}{$gwk};
  my $sentat  = gwPendingSentAt ($gwk, $name) // gettimeofday();
  my $waited  = gettimeofday() - $sentat;
  my $idlefor = $gw ? (gettimeofday() - ($gw->{last_activity} // 0)) : $gwstall;

  if ($gw && $idlefor < $gwstall && $waited < $gwmaxwait) {
      # Gateway zeigt noch Aktivität (ggf. gerade für ein anderes Device) und die absolute
      # Obergrenze ist noch nicht erreicht -> geduldig weiterwarten, kein Eingriff nötig
      InternalTimer (gettimeofday() + $gwpoll, 'FHEM::PylonLowVoltage::gwCheckProgress', $hash, 0);
      return;
  }

  my $reason = ($waited >= $gwmaxwait) ? "exceeded maximum wait time of $gwmaxwait s"
                                       : "no gateway activity at all for $idlefor s";

  Log3 ($name, 3, "$name - no response from gateway subprocess ($reason), checking process health");

  gwRemovePending ($gwk, $name);

  # Bewusst KEIN deleteReadingspec hier: ein bloßes "keine Antwort erhalten" ist keine
  # bestätigte Fehlermeldung des SubProcess - die zuletzt bekannten (u.U. weiterhin
  # gültigen) Readings sind eine bessere Informationsbasis als deren Löschung. Ein
  # Wipe würde zudem via LASTSTATIC-Logik keinen Effekt mehr auf wantstatic haben,
  # aber unnötig alle anderen Readings (Zellspannungen etc.) verwerfen.
  readingsSingleUpdate ($hash, 'state', 'Timeout waiting for gateway subprocess response', 1);

  if (!$gw || !defined $gw->{pid} || !kill (0, $gw->{pid})) {
      Log3 ($name, 1, "$name - gateway subprocess for $gwk is dead, restarting");

      _gwStopSubprocess   ($hash, $gwk);
      _gwEnsureSubprocess ($hash);
  }

  RemoveInternalTimer ($hash, 'FHEM::PylonLowVoltage::manageUpdate');
  InternalTimer (gettimeofday() + 1, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);

return;
}

###############################################################
#  liefert den Sendezeitpunkt eines noch ausstehenden Requests
#  aus der Pending-Liste eines Gateways (für gwCheckProgress)
###############################################################
sub gwPendingSentAt {
  my $gwk  = shift;
  my $name = shift;

  my $gw = $data{PylonLowVoltage}{GW}{$gwk};
  return if(!$gw || !$gw->{pending});

  for my $e (@{$gw->{pending}}) {
      return $e->{sent_at} if($e->{name} eq $name);
  }

return;
}

###############################################################
#  Device-Name aus der Pending-Liste eines Gateways entfernen
#  (Antwort erhalten oder Watchdog abgelaufen)
###############################################################
sub gwRemovePending {
  my $gwk  = shift;
  my $name = shift;

  my $gw = $data{PylonLowVoltage}{GW}{$gwk};
  return if(!$gw || !$gw->{pending});

  $gw->{pending} = [ grep { $_->{name} ne $name } @{$gw->{pending}} ];

return;
}

###############################################################
#  prüft robust (ohne separat mitgeführten, driftbaren Zustand),
#  ob für dieses Device aktuell ein Request in der Gateway-
#  Warteschlange aussteht.
###############################################################
sub gwIsPending {
  my $hash = shift;
  my $gwk  = gwKey ($hash);
  my $name = $hash->{NAME};

  my $gw = $data{PylonLowVoltage}{GW}{$gwk};
  return 0 if(!$gw || !$gw->{pending});

  for my $e (@{$gw->{pending}}) {
      return 1 if($e->{name} eq $name);
  }

return 0;
}

################################################################################
#  wird aus der globalen Select-Schleife aufgerufen, wenn der Gateway-
#  Subprozess Daten geschrieben hat (Parent-Prozess)
################################################################################
sub gwRead {
  my $selhash = shift;
  my $gwk     = $selhash->{gwkey};
  my $gw      = $data{PylonLowVoltage}{GW}{$gwk};

  return if(!$gw);

  my $retserial = $gw->{subprocess}->readFromChild();
  return if(!defined $retserial);

  my $resp = eval { thaw ($retserial) };
  return if(!$resp || ref($resp) ne 'HASH');

  $gw->{last_activity} = gettimeofday();                                                # jegliche Nachricht vom Gateway zählt als Lebenszeichen -
                                                                                        # dient Devices mit tieferer Warteschlangenposition als Beleg,
                                                                                        # dass der SubProcess weiterarbeitet (siehe gwCheckProgress)

  ## Log3Parent - Log3() Ausgabe eines aus dem Kindprozess umgeleiteten Logeintrags
  ####################################################################################
  if ( ($resp->{type} // 'response') eq 'log3parent' ) {
      Log3 ($resp->{name}, $resp->{level}, $resp->{name}." - ".$resp->{msg});
      return;
  }

  ## regulärer Antwort-Datensatz eines Requests
  ####################################################################################
  my $devname = $resp->{device};

  gwRemovePending ($gwk, $devname);

  my $hash = $defs{$devname};
  return if(!$hash);                                                                # Device zwischenzeitlich gelöscht

  RemoveInternalTimer ($hash, 'FHEM::PylonLowVoltage::gwCheckProgress');

  return if(IsDisabled ($devname));                                                 # währenddessen deaktiviert -> Antwort verwerfen

  finishUpdate ($hash, $resp->{success}, $resp->{readings}, $resp->{msg});

return;
}

###############################################################
#  Gateway Key (Host:Port) für die globale Subprozess-
#  Verwaltung
###############################################################
sub gwKey {
  my $hash = shift;

return $hash->{HOST}.':'.$hash->{PORT};
}

#################################################################
#   Kindprozess - Hauptschleife, läuft dauerhaft bis der
#   Subprozess durch den Parent beendet wird
#################################################################
sub GW_onRun {
  my $subprocess   = shift;
  $ChildSubprocess = $subprocess;

  my $sock;                                                                         # gecachter Socket dieses Gateways, lebt für die gesamte Prozesslaufzeit
  my @queue;                                                                        # FIFO der bereits empfangenen, aber noch nicht abgearbeiteten Requests

  while (1) {
      # alle aktuell verfügbaren Requests nicht-blockierend abholen und einreihen.
      # Reihenfolge = Empfangsreihenfolge = Sendereihenfolge
      while (defined (my $serial = $subprocess->readFromParent())) {
          my $req = eval { thaw ($serial) };

          if (!$req || ref($req) ne 'HASH') {
              GW_sendToParent ($subprocess, { type => 'log3parent', device => '?', level => 1, msg => 'malformed request received in subprocess' });
          }
          else {
              push @queue, $req;
          }
      }

      # die komplette aktuell vorliegende Warteschlange abarbeiten, bevor erneut auf neue Requests geprüft wird
      while (@queue) {
          my $req = shift @queue;

          # Sicherheitsnetz: ein unerwarteter, von GW_handleRequest selbst nicht
          # abgefangener Fehler (Programmierfehler, unerwartete Exception) darf den
          # dauerhaften Kindprozess niemals zum Absturz bringen - sonst würden alle
          # noch wartenden Requests anderer Devices ebenfalls verwaist, ohne dass der
          # Parent das sofort bemerkt (siehe Testrückmeldung Punkt 4).
          my $resp = eval {
              my ($r, $s) = GW_handleRequest ($req, $sock);
              $sock = $s;
              $r;
          };

          if (!$resp) {
              my $err = $@ || 'unknown internal error';
              GW_childLog ($req->{device} // 'PylonLowVoltage', 1, "PylonLowVoltage gateway subprocess - unexpected internal error: $err");
              $resp = { type => 'response', device => ($req->{device} // '?'), success => 0, readings => {}, msg => "internal subprocess error: $err" };
          }

          GW_sendToParent ($subprocess, $resp);
      }

      usleep (50000);                                                              # 50ms Idle-Wartezeit, CPU schonen
  }

return;
}

#####################################################
#   Kindprozess wird beendet
#####################################################
sub GW_onExit {
  my $subprocess = shift;
  my $gwk        = $subprocess->{gwkey} // '?';

  Log3 (undef, 1, "PylonLowVoltage - Gateway subprocess for $gwk EXITED!");

return;
}

#################################################################
#   Kindprozess - einen einzelnen Request bearbeiten
#   $sockref - Referenz auf den gecachten Socket (persistent
#              über mehrere Requests hinweg innerhalb des
#              Kindprozesses)
#################################################################
sub GW_handleRequest {
  my $req  = shift;
  my $sock = shift;

  my $host          = $req->{host};
  my $port          = $req->{port};
  my $chaintimeout  = $req->{timeout};                                              # gilt für die GESAMTE Kommandokette dieses Requests, nicht je Einzelkommando
  my $wtb           = $req->{wtb};
  my $readings      = {};
  my $success       = 0;
  my $cmdChainStart = gettimeofday();                                               # Start Zeitmessung Befehlskette
  
  my $numcalls      = grep { !($fncls{$_}{class} eq 'sta' && !$req->{wantstatic}) } keys %fncls;
  my $to_add        = $chaintimeout + ($numcalls * $wtb);

  eval {                                                                            ## no critic 'eval'
      local $SIG{ALRM} = sub { croak 'gatewaytimeout' };
      ualarm ($gwconnto * 1_000_000);                                               # fester, von "timeout" unabhängiger Verbindungsaufbau-Timeout

      if ($sock && !$sock->connected()) {
          GW_childLog ($req->{device}, 4, "cached socket to gateway lost connection, reconnecting");
          close ($sock);
          undef $sock;
      }

      if (!$sock) {
          $sock = IO::Socket::INET->new ( Proto    => 'tcp',
                                          PeerAddr => $host,
                                          PeerPort => $port,
                                          Timeout  => $gwconnto,                    # 0.5–1.0s, mehr ist unnötig weniger riskant.
                                        )
                      or croak 'no connection to RS485 gateway established';

          $sock->autoflush();

          GW_childLog ($req->{device}, 4, "new socket connection to gateway $host:$port established");
      }

      local $SIG{ALRM}  = sub { croak 'batterytimeout' };
      my $chaindeadline = gettimeofday() + $to_add;                                 # eine Deadline für die GESAMTE Kommandokette dieses Requests

      GW_childLog ($req->{device}, 4, "Start command chain in subprocess with chain timeout=$to_add seconds");
  
      for my $idx (sort keys %fncls) {                                              # Befehlskette abarbeiten
          next if($fncls{$idx}{class} eq 'sta' && !$req->{wantstatic});             # Funktionsklasse statische Werte nur wenn vom Parent angefordert

          my $remaining = $chaindeadline - gettimeofday();

          if ($remaining <= 0) {
              croak 'batterytimeout';                                              # Gesamtbudget der Kommandokette bereits aufgebraucht
          }

          $req->{timeout} = $remaining;                                            # GW_Request()/GW_Reread()/GW_writeCommand() nutzen ab jetzt die verbleibende RESTZEIT, nicht das ursprüngliche volle Attribut - dadurch gilt "timeout" effektiv für die GESAMTE Kette

          ualarm ($remaining * 1_000_000);

          my $err = &{$fncls{$idx}{fn}} ($req, $sock, $readings);

          if ($err) {
              croak $err;
          }

          ualarm (0);
          usleep ($wtb * 1_000_000);
      }

      $req->{timeout} = $chaintimeout;                                             # ursprünglichen Attributwert wiederherstellen
      $success        = 1;
  };  # eval

  ualarm (0);
  
  $readings->{cmdChainDuration} = gettimeofday() - $cmdChainStart;

  if ($@) {
      my $errtxt = $@;

      if ($errtxt =~ /gatewaytimeout/xs) {
          $errtxt = 'Timeout while establish RS485 gateway connection';
      }
      elsif ($errtxt =~ /batterytimeout/xs) {
          $errtxt = 'Timeout reading battery';
      }
      else {
          $errtxt = (split "at ", $errtxt)[0];
      }

      if ($sock) {
          close ($sock);
          undef $sock;
      }

      return { type => 'response', device => $req->{device}, success => 0, readings => $readings, msg => $errtxt }, $sock;
  }

return { type => 'response', device => $req->{device}, success => 1, readings => $readings, msg => '' }, $sock;
}

###############################################################
#   Antwort/Log-Nachricht an Parent senden (Kindprozess)
###############################################################
sub GW_sendToParent {
  my $subprocess = shift;
  my $data       = shift;

  my $serial = eval { freeze ($data) };

  if (!$serial) {
      # WICHTIG: freeze() kann scheitern (z.B. bei UTF8/Byte-Inkonsistenzen in aus
      # Binärdaten dekodierten Strings wie batteryType/Manufacturer). Ohne diesen
      # Fallback würde HIER GAR NICHTS an den Parent gesendet - der Pending-Eintrag
      # des Device bliebe (bis zum gwCheckProgress-Watchdog) auf eine Antwort warten,
      # die nie kommt (das Device würde sich "nach und nach" nicht mehr aktualisieren,
      # siehe Testrückmeldung). Deshalb wird zwingend eine garantiert serialisierbare
      # Minimalantwort nachgeschoben.
      my $err = $@ || 'unknown freeze error';

      my $logserial = eval { freeze ({ type => 'log3parent', name => ($data->{device} // 'PylonLowVoltage'), level => 1,
                                       msg  => "ERROR - could not serialize response for parent ($err) - sending minimal fallback response" }) };
      $subprocess->writeToParent ($logserial) if($logserial);

      my $fallback = { type => 'log3parent', device => ($data->{device} // '?'), level => 1, msg => "internal error: response could not be serialized ($err)" };
      $serial = eval { freeze ($fallback) };
  }

  $subprocess->writeToParent ($serial) if($serial);

return;
}

###############################################################
#       Abruf serialNumber (Kindprozess)
###############################################################
sub GW_callSerialNumber {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrsnb{1}{cmd}),
                           cmdtxt => 'serialNumber'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrsnb{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                 
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  my $sernum                = substr ($res, 15, 32);
  $readings->{serialNumber} = pack   ("H*", $sernum);

return;
}

###############################################################
#       Abruf manufacturerInfo (Kindprozess)
###############################################################
sub GW_callManufacturerInfo {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrmfi{1}{cmd}),
                           cmdtxt => 'manufacturerInfo'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrmfi{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                 
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  my $ubtt                  = $req->{userbatterytype} // '';                                        # frisch vom Parent mitgeschickt
  my $BatteryHex            = substr  ($res, 13, 20);
  # my $softwareVersion       = 'V'.hex (substr ($res, 33, 2)).'.'.hex (substr ($res, 35, 2));      # unklare Bedeutung
  my $ManufacturerHex       = substr  ($res, 37, 40);

  $readings->{batteryType}  = $ubtt ? $ubtt.' (adapted)' : GW_pseudoHexToText ($BatteryHex);
  $readings->{Manufacturer} = GW_pseudoHexToText ($ManufacturerHex);

return;
}

###############################################################
#       Abruf protocolVersion (Kindprozess)
###############################################################
sub GW_callProtocolVersion {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrprt{1}{cmd}),
                           cmdtxt => 'protocolVersion'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrprt{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                 
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  $readings->{protocolVersion} = 'V'.hex (substr ($res, 1, 1)).'.'.hex (substr ($res, 2, 1));

return;
}

###############################################################
#       Abruf softwareVersion (Kindprozess)
###############################################################
sub GW_callSoftwareVersion {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrswv{1}{cmd}),
                           cmdtxt => 'softwareVersion'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrswv{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                 
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  $readings->{moduleSoftwareVersion_manufacture} = 'V'.hex (substr ($res, 15, 2)).'.'.hex (substr ($res, 17, 2));
  $readings->{moduleSoftwareVersion_mainline}    = 'V'.hex (substr ($res, 19, 2)).'.'.hex (substr ($res, 21, 2)).'.'.hex (substr ($res, 23, 2));

return;
}

###############################################################
#       Abruf systemParameters (Kindprozess)
###############################################################
sub GW_callSystemParameters {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrspm{1}{cmd}),
                           cmdtxt => 'systemParameters'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrspm{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                 
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  $readings->{paramCellHighVoltLimit}      = sprintf "%.3f", (hex substr  ($res, 15, 4)) / 1000;
  $readings->{paramCellLowVoltLimit}       = sprintf "%.3f", (hex substr  ($res, 19, 4)) / 1000;                   # Alarm Limit
  $readings->{paramCellUnderVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 23, 4)) / 1000;                   # Schutz Limit
  $readings->{paramChargeHighTempLimit}    = sprintf "%.1f", ((hex substr ($res, 27, 4)) - 2731) / 10;
  $readings->{paramChargeLowTempLimit}     = sprintf "%.1f", ((hex substr ($res, 31, 4)) - 2731) / 10;
  $readings->{paramChargeCurrentLimit}     = sprintf "%.3f", (hex substr  ($res, 35, 4)) * 100 / 1000;
  $readings->{paramModuleHighVoltLimit}    = sprintf "%.3f", (hex substr  ($res, 39, 4)) / 1000;
  $readings->{paramModuleLowVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 43, 4)) / 1000;                   # Alarm Limit
  $readings->{paramModuleUnderVoltLimit}   = sprintf "%.3f", (hex substr  ($res, 47, 4)) / 1000;                   # Schutz Limit
  $readings->{paramDischargeHighTempLimit} = sprintf "%.1f", ((hex substr ($res, 51, 4)) - 2731) / 10;
  $readings->{paramDischargeLowTempLimit}  = sprintf "%.1f", ((hex substr ($res, 55, 4)) - 2731) / 10;
  $readings->{paramDischargeCurrentLimit}  = sprintf "%.3f", (65535 - (hex substr ($res, 59, 4))) * 100 / 1000;    # mit Symbol (-)

return;
}

#################################################################################
#       Abruf analogValue (Kindprozess)
# Answer from US2000 = 128 Bytes, from US3000 = 140 Bytes
# Remain capacity US2000 hex(substr($res,109,4), US3000 hex(substr($res,123,6)
# Module capacity US2000 hex(substr($res,115,4), US3000 hex(substr($res,129,6)
#################################################################################
sub GW_callAnalogValue {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrcmn{1}{cmd}),
                           cmdtxt => 'analogValue'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrcmn{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                  
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  my $bpos = 17;                                                                                 # Startposition
  my $pcc  = hex (substr($res, $bpos, 2));                                                       # Anzahl Zellen (15 od. 16)
  $bpos   += 2;                                                                                  # Pos 19

  for my $z (1..$pcc) {
      my $fz                          = sprintf "%02d", $z;                                      # formatierter Zähler
      $readings->{'cellVoltage_'.$fz} = sprintf "%.3f", hex(substr($res, $bpos, 4)) / 1000;      # Pos 19 -> 75 bei 15 Zellen
      $bpos += 4;                                                                                # letzter Durchlauf: Pos 79 bei 15 Zellen, Pos 83 bei 16 Zellen
  }

  $readings->{numberTempPos}             = hex(substr($res, $bpos, 2));                          # Anzahl der jetzt folgenden Temperaturpositionen -> 5 oder mehr (US5000: 6)
  $bpos += 2;

  $readings->{bmsTemperature}            = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 81 bei 15 Zellen
  $bpos += 4;

  $readings->{cellTemperature_0104}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 85
  $bpos += 4;

  $readings->{cellTemperature_0508}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 89
  $bpos += 4;

  $readings->{cellTemperature_0912}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 93
  $bpos += 4;

  $readings->{'cellTemperature_13'.$pcc} = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 97
  $bpos += 4;

  for my $t (6..$readings->{numberTempPos}) {
      $t = 'Pos_'.sprintf "%02d", $t;
      $readings->{'cellTemperature_'.$t} = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # mehr als 5 Temperaturpositionen (z.B. US5000)
      $bpos += 4;                                                                                # Position bei 5 Temp.Angaben (bei 6 Temperaturen)
  }

  my $current                            =  hex (substr($res, $bpos, 4));                        # Pos 101 (105)
  $bpos += 4;

  $readings->{packVolt}                  = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 105 (109)
  $bpos += 4;

  my $remcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 109 (113)
  $bpos += 4;

  my $udi                                = hex substr($res, $bpos, 2);                           # Pos 113 (117)  user defined item=Entscheidungskriterium -> 2: Batterien <= 65Ah, 4: Batterien > 65Ah
  $bpos += 2;

  my $totcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 115 (119)
  $bpos += 4;

  $readings->{packCycles}                = hex substr($res, $bpos, 4);                           # Pos 119 (123)
  $bpos += 4;

  my $remcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 123 (127)
  $bpos += 6;

  my $totcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 129 (133)
  $bpos += 6;

  # kalkulierte Werte generieren
  ################################
  if ($udi == 2) {
      $readings->{packCapacityRemain} = $remcap1;
      $readings->{packCapacity}       = $totcap1;
  }
  elsif ($udi == 4) {
      $readings->{packCapacityRemain} = $remcap2;
      $readings->{packCapacity}       = $totcap2;
  }
  else {
      my $err = 'wrong value retrieve analogValue -> user defined items: '.$udi;
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => '',
                       state    => $err
                     } );
                  
      return $err;
  }

  if ($current & 0x8000) {
      $current = $current - 0x10000;
  }

  $readings->{packCellcount} = $pcc;
  $readings->{packCurrent}   = sprintf "%.3f", $current / 10;

return;
}

###############################################################
#       Abruf alarmInfo (Kindprozess)
###############################################################
sub GW_callAlarmInfo {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hralm{1}{cmd}),
                           cmdtxt => 'alarmInfo'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hralm{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                  
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  my ($alm, $aval);

  my $bpos = 17;                                                                  # Startposition
  $readings->{packCellcount} = hex (substr($res, $bpos, 2));                      # Pos. 17
  $bpos += 2;

  for my $cnt (1..$readings->{packCellcount}) {                                   # Start Pos. 19
      $cnt                                = sprintf "%02d", $cnt;
      $aval                               = substr ($res, $bpos, 2);
      $readings->{'almCellVoltage_'.$cnt} = $halm{$aval}{alm};
      $alm   = 1 if(int $aval);
      $bpos += 2;
  }

  my $ntp = hex (substr($res, $bpos, 2));                                         # Pos. 49 bei 15 Zellen (Anzahl der Temperaturpositionen)
  $bpos += 2;

  for my $nt (1..$ntp) {                                                          # Start Pos. 51 bei 15 Zellen
      $nt                                = sprintf "%02d", $nt;
      $aval                              = substr ($res, $bpos, 2);
      $readings->{'almTemperature_'.$nt} = $halm{$aval}{alm};
      $alm   = 1 if(int $aval);
      $bpos += 2;
  }

  $aval                         = substr ($res, $bpos, 2);                        # Pos. 61 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almChargeCurrent} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;

  $aval                         = substr ($res, $bpos, 2);                        # Pos. 63 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almModuleVoltage} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;

  $aval                            = substr ($res, $bpos, 2);                     # Pos. 65 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almDischargeCurrent} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;

  my $stat1alm = substr ($res, $bpos, 2);                                         # Pos. 67 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;

  my $stat2alm = substr ($res, $bpos, 2);                                         # Pos. 69 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;

  my $stat3alm = substr ($res, $bpos, 2);                                         # Pos. 71 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;

  my $stat4alm = substr ($res, $bpos, 2);                                         # Pos. 73 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;

  my $stat5alm = substr ($res, $bpos, 2);                                         # Pos. 75 b. 15 Zellen u. 5 Temp.positionen

  if (!$alm) {
      $readings->{packAlarmInfo} = "ok";
  }
  else {
      $readings->{packAlarmInfo} = "failure";
  }

  my $name = $req->{device};

  if (($req->{verbose} // 3) > 4) {                                               # verbose kommt frisch vom Parent, kein Fork-Snapshot
      GW_childLog ($name, 5, "Alarminfo - Status 1 alarm: $stat1alm");
      GW_childLog ($name, 5, "Alarminfo - Status 2 Info: $stat2alm");
      GW_childLog ($name, 5, "Alarminfo - Status 3 Info: $stat3alm");
      GW_childLog ($name, 5, "Alarminfo - Status 4 alarm: $stat4alm");
      GW_childLog ($name, 5, "Alarminfo - Status 5 alarm: $stat5alm");
  }

return;
}

###############################################################
#       Abruf chargeManagmentInfo (Kindprozess)
###############################################################
sub GW_callChargeManagmentInfo {
  my $req      = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = GW_Request ( { req    => $req,
                           socket => $socket,
                           cmd    => GW_getCmdString ($req, $hrcmi{1}{cmd}),
                           cmdtxt => 'chargeManagmentInfo'
                         } );

  my $rtnerr = GW_responseCheck ($res, $hrcmi{1}{mlen});

  if ($rtnerr) {
      GW_doOnError ( { req      => $req,
                       readings => $readings,
                       res      => $res,
                       state    => $rtnerr
                     } );
                  
      return $rtnerr;
  }

  GW_resultLog ($req, $res);

  $readings->{chargeVoltageLimit}     = sprintf "%.3f", hex (substr ($res, 15, 4)) / 1000;        # Genauigkeit 3
  $readings->{dischargeVoltageLimit}  = sprintf "%.3f", hex (substr ($res, 19, 4)) / 1000;        # Genauigkeit 3
  $readings->{chargeCurrentLimit}     = sprintf "%.1f", hex (substr ($res, 23, 4)) / 10;          # Genauigkeit 1
  $readings->{dischargeCurrentLimit}  = sprintf "%.1f", (65536 - hex substr ($res, 27, 4)) / 10;  # Genauigkeit 1, Fixed point, unsigned integer

  my $cdstat                          = sprintf "%08b", hex substr ($res, 31, 2);                 # Rohstatus
  $readings->{chargeEnable}           = substr ($cdstat, 0, 1) == 1 ? 'yes' : 'no';               # Bit 7
  $readings->{dischargeEnable}        = substr ($cdstat, 1, 1) == 1 ? 'yes' : 'no';               # Bit 6
  $readings->{chargeImmediatelySOC05} = substr ($cdstat, 2, 1) == 1 ? 'yes' : 'no';               # Bit 5 - SOC 5~9%  -> für Wechselrichter, die aktives Batteriemanagement bei gegebener DC-Spannungsfunktion haben oder Wechselrichter, der von sich aus einen niedrigen SOC/Spannungsgrenzwert hat
  $readings->{chargeImmediatelySOC09} = substr ($cdstat, 3, 1) == 1 ? 'yes' : 'no';               # Bit 4 - SOC 9~13% -> für Wechselrichter hat keine aktive Batterieabschaltung haben
  $readings->{chargeFullRequest}      = substr ($cdstat, 4, 1) == 1 ? 'yes' : 'no';               # Bit 3 - wenn SOC in 30 Tagen nie höher als 97% -> Flag = 1, wenn SOC-Wert ≥ 97% -> Flag = 0

return;
}

###############################################################
#       Fehlerausstieg (Kindprozess)
###############################################################
sub GW_doOnError {
  my $paref = shift;

  my $req      = $paref->{req};
  my $readings = $paref->{readings};     # Referenz auf das Hash der zu erstellenden Readings
  my $state    = $paref->{state};
  my $res      = $paref->{res}     // '';
  my $verbose  = $paref->{verbose} // 4;

  my $name           = $req->{device};
  $state             = (split "at ", $state)[0];
  $readings->{state} = $state;
  $verbose           = 3 if($readings->{state} =~ /error/xsi);

  GW_childLog ($name, $verbose, $readings->{state});

  if ($res) {
      GW_childLog  ($name, 5, "faulty data is printed out now: ");
      GW_resultLog ($req, $res);
  }

return;
}

###############################################################
#        Logausgabe Result (Kindprozess)
###############################################################
sub GW_resultLog {
  my $req = shift;
  my $res = shift;

  my $name = $req->{device};

  GW_childLog ($name, 5, "data returned raw: ".$res);
  GW_childLog ($name, 5, "data returned:\n"   .GW_Hexdump ($res));

return;
}

#################################################################
#   Kindprozess - Log-Ausgabe zum Parent umleiten
#   (nur im Kindprozess aktiv; außerhalb des Subprozess-Kontexts
#   wird direkt auf Log3 zurückgefallen, z.B. für Tests)
#################################################################
sub GW_childLog {
  my $name  = shift;
  my $level = shift;
  my $msg   = shift;

  if ($ChildSubprocess) {
      my $serial = eval { freeze ({ type => 'log3parent', name => $name, level => $level, msg => $msg }) };
      $ChildSubprocess->writeToParent ($serial) if($serial);
  }
  else {
      Log3 ($name, $level, $msg);
  }

return;
}

###############################################################
#                  PylonLowVoltage GW_Hexdump
###############################################################
sub GW_Hexdump {
  my $res = shift;

  my $offset = 0;
  my $result = "";

  for my $chunk (unpack "(a16)*", $res) {
      my $hex  = unpack "H*", $chunk;                                                       # hexadecimal magic
      $chunk   =~ tr/ -~/./c;                                                               # replace unprintables
      $hex     =~ s/(.{1,8})/$1 /gxs;                                                       # insert spaces
      $result .= sprintf "0x%08x (%05u)  %-*s %s\n", $offset, $offset, 36, $hex, $chunk;
      $offset += 16;
  }

return $result;
}

###############################################################
#            PylonLowVoltage Request (Kindprozess)
###############################################################
sub GW_Request {
  my $paref = shift;

  my $req    = $paref->{req};
  my $socket = $paref->{socket};
  my $cmd    = $paref->{cmd};
  my $cmdtxt = $paref->{cmdtxt} // 'unspecified data';

  my $name    = $req->{device};
  my $timeout = $req->{timeout} // 1;

  GW_childLog ($name, 4, "retrieve battery info: ".$cmdtxt);
  GW_childLog ($name, 4, "request command (ASCII): ".$cmd);
  GW_childLog ($name, 5, "request command (HEX): ".(unpack "H*", $cmd));

  GW_writeCommand ($socket, $cmd, $timeout);

return GW_Reread ($socket, $timeout);
}

###############################################################
# Kommando an das Gateway schreiben (Kindprozess)
# select()-gebunden statt eines ungeschützten "printf" - siehe
# ausführliche Begründung im Kommentar zu GW_Reread(). syswrite
# kann außerdem partiell schreiben, daher die Schleife.
###############################################################
sub GW_writeCommand {
  my $socket  = shift;
  my $cmd     = shift;
  my $timeout = shift // 1;                                         # Sekunden für das GESAMTE Kommando (nicht je Chunk!)

  my $win = '';
  vec ($win, fileno ($socket), 1) = 1;

  my $remaining = $cmd;
  my $deadline  = gettimeofday() + $timeout;                        # dieselbe Gesamt-Deadline-Logik wie in GW_Reread() - siehe dort

  while (length $remaining) {
      my $rest = $deadline - gettimeofday();

      if ($rest <= 0) {
          croak 'Timeout writing command to gateway';
      }

      my $nfound = select (undef, my $wout = $win, undef, $rest);

      if (!$nfound) {
          croak 'Timeout writing command to gateway';
      }

      my $n = $socket->syswrite ($remaining);

      if (!defined $n) {
          next if(0+$! == EWOULDBLOCK);
          croak 'Error writing command to gateway: '.$!;
      }

      $remaining = substr ($remaining, $n);
  }

return;
}

###############################################################
# RS485 Daten lesen/empfangen (Kindprozess)
# Bewusst NICHT allein auf $socket->read() (IO::Socket::Timeout)
# verlassen: select() mit explizitem Timeout ist ein einzelner,
# genuin kernelseitig begrenzter Syscall und dadurch NICHT von
# Perls "deferred/safe signals" betroffen (SIGALRM wird erst
# ausgeliefert, wenn die Kontrolle zu Perl-Bytecode zurückkehrt -
# das kann bei einem Ziel, das gar nicht mehr antwortet ("black
# hole"), innerhalb eines blockierenden C-Level-Syscalls u.U.
# NIE der Fall sein). Das ist der entscheidende Unterschied zu
# ualarm/$SIG{ALRM}, das als alleinige Absicherung in genau
# diesem Fall wirkungslos bleiben kann (siehe Testrückmeldung:
# ein einzelnes Kommando blockierte >240s trotz konfiguriertem
# "timeout"-Attribut).
###############################################################
sub GW_Reread {
    my $socket  = shift;
    my $timeout = shift // 1;                                       # Sekunden für die GESAMTE Antwort (nicht je Byte!)

    my $singlechar;
    my $res = q{};

    my $rin = '';
    vec ($rin, fileno ($socket), 1) = 1;

    my $deadline = gettimeofday() + $timeout;                       # WICHTIG: EINE Gesamt-Deadline für die komplette Antwort,
                                                                      # nicht pro Byte ein frisches volles $timeout. Ein select()
                                                                      # je Byte mit dem vollen $timeout würde eine Antwort, die nur
                                                                      # leicht stockend eintrudelt (jedes Byte für sich "rechtzeitig"),
                                                                      # bis zum Vielfachen von $timeout durchlassen - nachgewiesen mit
                                                                      # einem Testfall: 40 Byte im Abstand von je 0.3s liefen bei
                                                                      # timeout=0.5s in 12s statt der erwarteten <1s durch.

    while (1) {
        my $remaining = $deadline - gettimeofday();

        if ($remaining <= 0) {
            croak 'Timeout reading data from battery';
        }

        my $nfound = select (my $rout = $rin, undef, undef, $remaining);

        if (!$nfound) {
            croak 'Timeout reading data from battery';
        }

        my $n = $socket->sysread ($singlechar, 1);

        if (!defined $n) {
            next if(0+$! == EWOULDBLOCK || 0+$! == ETIMEDOUT);    # spurious wakeup - select meldete bereit, sysread blockte trotzdem kurz
            croak 'Error reading data from battery: '.$!;
        }

        if ($n == 0) {
            croak 'Connection closed by gateway while reading data from battery';
        }

        $res .= $singlechar if($singlechar =~ /[~A-Z0-9\r]+/xs);

        last if(ord ($singlechar) == 13);
    }

return $res;
}

###############################################################
#       Response Status ermitteln (Kindprozess)
###############################################################
sub GW_responseCheck {
  my $res  = shift;
  my $mlen = shift // 0;                # Mindestlänge Antwortstring

  my $rtnerr = $hrtnc{99}{desc};

  if(!$res || $res !~ /^[~A-Fa-f0-9]+\r$/xs || $res =~ tr/~// != 1) {
      return $rtnerr;
  }

  my $len = length($res);

  if ($len < $mlen) {
      $rtnerr = $hrtnc{98}{desc};
      $rtnerr =~ s/<LEN>/$len/xs;
      $rtnerr =~ s/<MLEN>/$mlen/xs;
      return $rtnerr;
  }

  my $rtn = q{_};
  $rtn    = substr($res,7,2) if($res && $len >= 10);

  if(defined $hrtnc{$rtn}{desc} && substr($res, 0, 1) eq '~') {
      $rtnerr = $hrtnc{$rtn}{desc};
      return if($rtnerr eq 'normal');
  }

return $rtnerr;
}

###############################################################
#  Hex-Zeichenkette in ASCII-Zeichenkette einzeln umwandeln
###############################################################
sub GW_pseudoHexToText {
   my $string = shift;

   my $charcode;
   my $text = '';

   for (my $i = 0; $i < length($string); $i += 2) {
      $charcode = hex substr ($string, $i, 2);                  # charcode = aquivalente Dezimalzahl der angegebenen Hexadezimalzahl
      next if($charcode == 45);                                 # Hyphen '-' ausblenden

      $text = $text.chr ($charcode);
   }

   # defensiv: reine Byte-Repräsentation erzwingen. chr() kann für Codepoints >127 intern
   # das UTF8-Flag setzen; eine solche Zeichenkette zusammen mit anderen (reinen Byte-)
   # Readings wie serialNumber (aus pack("H*",...)) im selben freeze()-Aufruf zu serialisieren
   # kann zu Storable-Fehlern führen ("Wide character..."), die GW_sendToParent zum Scheitern
   # bringen - mit dem Effekt, dass der Parent NIE eine Antwort erhält (siehe GW_sendToParent).
   # fail_ok=1 -> stirbt nicht, falls echte Wide-Chars vorhanden sind.
   utf8::downgrade ($text, 1);

return $text;
}

###############################################################
#          Kommandostring zusammenstellen (Kindprozess)
#          Teilstring aus Kommandohash wird übergeben
###############################################################
sub GW_getCmdString {
  my $req  = shift;
  my $cstr = shift;                        # Kommandoteilstring

  my $addr = GW_composeAddr ($req);          # effektive Batterieadresse berechnen
  $cstr    =~ s/--/$addr/xg;               # Platzhalter Adresse ersetzen

  my $cmd  = $pfx;                         # Präfix
  $cmd    .= $cstr;                        # Kommandostring
  $cmd    .= GW_doChecksum ($cstr);        # Checksumme ergänzen
  $cmd    .= $sfx;                         # Suffix

return $cmd;
}

###############################################################
#  Adresse aus Batterie und Gruppe erstellen (Kindprozess)
#
# 1) Single group battery 4:
#    n = 5; m = 0
#    ADR = 0x05 + 0x10*0 = 0x05; INFO of COMMAND = ADR = 0x05
# 2) multi group, group 3, battery 6;
#    n = 7; m = 3
#    ADR = 0x07 + 0x10*3 = 0x37; INFO of COMMAND = ADR = 0x37
###############################################################
sub GW_composeAddr {
  my $req = shift;

  my $ba_num = $req->{bataddr} + 1;               # n (Master startet mit "02")
  my $ga_num = $req->{group};                     # m

  my $adr_num = $ba_num + 0x10 * $ga_num;         # ADR = n + 0x10*m
  my $ad      = sprintf "%02X", $adr_num;

  my $name   = $req->{device};
  my $ba_hex = sprintf "%02X", $ba_num;
  my $ga_hex = sprintf "%02X", $ga_num;

  GW_childLog ($name, 5, "Addressing (HEX) - Bat: $ba_hex, Group: $ga_hex, effective Bat address: $ad");

return $ad;
}

###############################################################
#  (Kindprozess) wandelt eine Zeichenkette aus HEX-Zahlen in 
#  eine hexadecimal-ASCII Zeichenkette um und berechnet daraus 
#  die Checksumme (=Returnwert)
###############################################################
sub GW_doChecksum {
   my $hstring = shift // return;

   my $dezsum    = 0;
   my @asciivals = split //, $hstring;

   for my $v (@asciivals) {                                     # jedes einzelne Zeichen der HEX-Kette wird als ASCII Wert interpretiert
       my $hex  = unpack "H*", $v;                              # in einen HEX-Wert umgewandelt
       $dezsum += hex $hex;                                     # und die Dezimalsumme gebildet
   }

   my $bin = sprintf '%016b', $dezsum;

   $bin =~ s/1/x/g;                                             # invertieren
   $bin =~ s/0/1/g;
   $bin =~ s/x/0/g;

   $dezsum = oct("0b$bin");
   $dezsum++;
   $bin    = sprintf '%016b', $dezsum;

   my $chksum = sprintf '%X', oct("0b$bin");

return $chksum;
}

###############################################################
#    eigene zusätzliche Werte erstellen (Parent-Prozess)
###############################################################
sub additionalReadings {
    my $readings = shift;                                               # Referenz auf das Hash der zu erstellenden Readings

    my ($vmax, $vmin);

    $readings->{cellVoltageAvg}   = sprintf "%.5f", $readings->{packVolt} / $readings->{packCellcount}                  if($readings->{packCellcount});
    $readings->{packSOC}          = sprintf "%.2f", ($readings->{packCapacityRemain} / $readings->{packCapacity} * 100) if($readings->{packCapacity});
    $readings->{cmdChainDuration} = sprintf "%.3f", $readings->{cmdChainDuration}                                       if(defined $readings->{cmdChainDuration});
    $readings->{packPower}        = sprintf "%.2f", $readings->{packCurrent} * $readings->{packVolt};

    for (my $i=1; $i <= $readings->{packCellcount}; $i++) {
        $i    = sprintf "%02d", $i;
        $vmax = $readings->{'cellVoltage_'.$i} if(!$vmax || $vmax < $readings->{'cellVoltage_'.$i});
        $vmin = $readings->{'cellVoltage_'.$i} if(!$vmin || $vmin > $readings->{'cellVoltage_'.$i});
    }

    if ($vmax && $vmin) {
        my $maxdf = $vmax - $vmin;
        $readings->{packImbalance} = sprintf "%.3f", 100 * $maxdf / $readings->{cellVoltageAvg};

        $readings->{cellVoltageMax} = $vmax;
        $readings->{cellVoltageMin} = $vmin;
    }

    $readings->{packState} = $readings->{packCurrent} < 0 ? 'discharging' :
                             $readings->{packCurrent} > 0 ? 'charging'    :
                             'idle';

return;
}

###############################################################
#       Readings erstellen (Parent-Prozess)
###############################################################
sub createReadings {
    my $hash     = shift;
    my $success  = shift;
    my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

    readingsBeginUpdate ($hash);

    for my $rdg (keys %{$readings}) {
        next if(!defined $readings->{$rdg});
        readingsBulkUpdate ($hash, $rdg, $readings->{$rdg}) if($success || grep /^$rdg$/, @blackl);
    }

    readingsEndUpdate ($hash, 1);

return;
}

################################################################
#    alle Readings eines Devices oder nur Reading-Regex
#    löschen
#    Readings der Blacklist werden nicht gelöscht
#    (Parent-Prozess)
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";

  my $readingspec = '^'.$spec.'$';

  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
      next if(grep /^$reading$/, @blackl);
      readingsDelete ($hash, $reading);
  }

return;
}

1;


=pod
=item device
=item summary Integration of Pylontech low voltage batteries via RS485 ethernet gateway
=item summary_DE Integration von Pylontech Niederspannungsbatterien über RS485-Ethernet-Gateway

=begin html

 <a id="PylonLowVoltage"></a>
 <h3>PylonLowVoltage</h3>
 <br>
 Module for integration of low voltage batteries with battery management system (BMS) of the manufacturer Pylontech via
 RS485/Ethernet gateway. Communication to the RS485 gateway takes place exclusively via an Ethernet connection.<br>
 The module has been successfully used so far with Pylontech batteries of the following types: <br>

 <ul>
  <li> US2000        </li>
  <li> US2000B Plus  </li>
  <li> US2000C       </li>
  <li> US2000 Plus   </li>
  <li> US3000        </li>
  <li> US3000C       </li>
  <li> US5000        </li>
 </ul>

 The following devices have been successfully used as RS485 Ethernet gateways to date: <br>
 <ul>
  <li> USR-TCP232-304 from the manufacturer USRiot </li>
  <li> Waveshare RS485 to Ethernet Converter       </li>
 </ul>

 In principle, any other RS485/Ethernet gateway should also be compatible.
 <br><br>

 <b>Requirements</b>
 <br><br>
 This module requires the Perl modules:
 <ul>
    <li>IO::Socket::INET    (apt-get install libio-socket-multicast-perl)                          </li>
 </ul>

 The data format must be set on the RS485 gateway as follows:
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> Start Bit </td><td>- 1 Bit          </td></tr>
        <tr><td> Data Bit  </td><td>- 8 Bit          </td></tr>
        <tr><td> Stop Bit  </td><td>- 1 Bit          </td></tr>
        <tr><td> Parity    </td><td>- without Parity </td></tr>
     </table>
  </ul>
  <br>

 <b>Limitations</b>
 <br>
 The module currently supports a maximum of 16 batteries (1 master + 15 slaves) in up to 7 groups. <br>
 The number of groups and batteries that can be realized depends on the products used.
 Please refer to the manufacturer's instructions.
 <br><br>

 <a id="PylonLowVoltage-define"></a>
 <b>Definition</b>
 <ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;]</b></code><br>
  <br>

  <b>Example:</b> <br>
  define Pylone1 PylonLowVoltage 192.168.2.86:9000 1 group=0 <br>
  <br>

  <li><b>hostname/ip:</b><br>
     Host name or IP address of the RS485/Ethernet gateway
  </li>

  <li><b>port:</b><br>
     Port number of the port configured in the RS485/Ethernet gateway
  </li>

  <li><b>bataddress:</b><br>
     Device address of the Pylontech battery. Several Pylontech batteries can be connected via a Pylontech-specific
     Link connection. The permissible number can be found in the respective Pylontech documentation. <br>
     The master battery in the network (with open link port 0 or to which the RS485 connection is connected) has the
     address 1, the next battery then has address 2 and so on.
     If no device address is specified, address 1 is used.
  </li>

  <li><b>group:</b><br>
     Optional group number of the battery stack. If group=0 or is not specified, the default configuration
     "Single Group" is used. The group number can be 0 to 7.
  </li>
  <br>
 </ul>

 <b>Mode of operation and architecture</b>
 <ul>
 Depending on the setting of the "Interval" attribute, the module cyclically reads values provided by the battery
 management system via the RS485 interface. <br><br>

 In a typical installation, exactly one RS485/Ethernet gateway is connected to the RS485 port of the Pylontech master
 battery, while several PylonLowVoltage devices (one per battery address) share this single gateway. <br>
 For every distinct &lt;hostname/ip&gt;:&lt;port&gt; combination the module maintains exactly one permanent, small
 background process (implemented with FHEM's SubProcess.pm) that keeps the TCP connection to the gateway open and
 serializes all RS485 requests coming from the devices sharing this gateway. All devices referencing the same
 gateway automatically share this single background process (reference counted); it is started by whichever device
 needs it first and stopped automatically once the last device using it is deleted or FHEM shuts down. If the
 background process is found to be dead (e.g. after a crash), it is transparently restarted by the next device that
 needs it. <br>
 This keeps FHEM's main process fully responsive at all times, independent of how slow or unreliable the RS485
 gateway responds, while avoiding the memory and CPU overhead of forking a new process for every single query cycle.
 </ul>

 <a id="PylonLowVoltage-get"></a>
 <b>Get</b>
 <br>
 <ul>
  <a id="PylonLowVoltage-get-data"></a>
  <li><b>data</b><br>
    The data query of the battery management system is executed. The timer of the cyclic query is reinitialized according
    to the set value of the "interval" attribute.
    <br>
  </li>
  <br>
 
  <a id="PylonLowVoltage-get-listQueue"></a>
  <li><b>listQueue</b><br>
    Displays the status, process ID of the shared gateway background process for this device, and the
    current command queue. 
    <br>
  </li>
  <br>
  </ul>

 <a id="PylonLowVoltage-attr"></a>
 <b>Attributes</b>
 <br<br>
 <ul>
   <a id="PylonLowVoltage-attr-disable"></a>
   <li><b>disable 0|1</b><br>
     Enables/disables the device definition.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-interval"></a>
   <li><b>interval &lt;seconds&gt;</b><br>
     At the specified interval (in seconds), the command queue is checked to see if a battery data request
     is already scheduled. If no such entry exists, a new request is automatically added.
     If the interval value is 0, no automatic data request takes place. <br>
     (default: 30)
   </li>
   <br>

   <a id="PylonLowVoltage-attr-timeout"></a>
   <li><b>timeout &lt;seconds&gt;</b><br>
     Maximum time (in seconds) that the subprocess has available for the entire command chain of a request. <br>
     This value does not limit individual commands, but rather the total time budget for all function calls to be executed, 
     including wait times. <br>
     (default: 3.0)
   </li>
   <br>

   <a id="PylonLowVoltage-attr-userBatterytype"></a>
   <li><b>userBatterytype</b><br>
     The automatically determined battery type (Reading batteryType) is replaced by the specified string.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-waitTimeBetweenRS485Cmd"></a>
   <li><b>waitTimeBetweenRS485Cmd &lt;seconds&gt;</b><br>
     The wait time between the execution of consecutive RS485 commands within a polling cycle, evaluated
     within the shared background process. <br>
     According to the US3000C operating instructions, the pause between each RS485 command must be at least >= 1 s. <br>
     (default: 1.0)
   </li>
   <br>

 </ul>

 <a id="PylonLowVoltage-readings"></a>
 <b>Readings</b>
 <ul>
 <li><b>bmsTemperature</b><br>         Temperature (°C) of the battery management system                                  </li>
 <li><b>cellTemperature_0104</b><br>   Temperature (°C) of cell packs 1 to 4                                              </li>
 <li><b>cellTemperature_0508</b><br>   Temperature (°C) of cell packs 5 to 8                                              </li>
 <li><b>cellTemperature_0912</b><br>   Temperature (°C) of the cell packs 9 to 12                                         </li>
 <li><b>cellTemperature_1315</b><br>   Temperature (°C) of the cell packs 13 to 15                                        </li>
 <li><b>cellTemperature_Pos_XX</b><br> Temperature (°C) of position XX (not further specified)                            </li>
 <li><b>cellVoltage_XX</b><br>         Cell voltage (V) of the cell pack XX. In the battery module "packCellcount"
                                       cell packs are connected in series. Each cell pack consists of single cells
                                       connected in parallel.                                                             </li>
 <li><b>cellVoltageAvg</b><br>         Average cell voltage (V)                                                           </li>
 <li><b>cellVoltageMax</b><br>         highest cell voltage (V) of all cells in the current cycle                         </li>
 <li><b>cellVoltageMin</b><br>         lowest cell voltage (V) of all cells in the current cycle                          </li>
 <li><b>chargeCurrentLimit</b><br>     current limit value for the charging current (A)                                   </li>
 <li><b>chargeEnable</b><br>           current flag loading allowed                                                       </li>
 <li><b>chargeFullRequest</b><br>      current flag charge battery module fully (from the mains if necessary)             </li>
 <li><b>chargeImmediatelySOCXX</b><br> current flag charge battery module immediately
                                       (05: SOC limit 5-9%, 09: SOC limit 9-13%)                                          </li>
 <li><b>chargeVoltageLimit</b><br>     current charge voltage limit (V) of the battery module                             </li>
 <li><b>cmdChainDuration</b><br>       real processing time (s) of the last command chain (connection setup + all
                                       executed BMS commands of the cycle), measured inside the background process       </li>
 <li><b>dischargeCurrentLimit</b><br>  current limit value for the discharge current (A)                                  </li>
 <li><b>dischargeEnable</b><br>        current flag unloading allowed                                                     </li>
 <li><b>dischargeVoltageLimit</b><br>  current discharge voltage limit (V) of the battery module                          </li>

 <li><b>moduleSoftwareVersion_manufacture</b><br> Firmware version of the battery module                                  </li>

 <li><b>packAlarmInfo</b><br>          Alarm status (ok - battery module is OK, failure - there is a fault in the
                                       battery module)                                                                    </li>
 <li><b>packCapacity</b><br>           nominal capacity (Ah) of the battery module                                        </li>
 <li><b>packCapacityRemain</b><br>     current capacity (Ah) of the battery module                                        </li>
 <li><b>packCellcount</b><br>          Number of cell packs in the battery module                                         </li>
 <li><b>packCurrent</b><br>            current charge current (+) or discharge current (-) of the battery module (A)      </li>
 <li><b>packCycles</b><br>             Number of full cycles - The number of cycles is, to some extent, a measure of the
                                       wear and tear of the battery. A complete charge and discharge is counted as one
                                       cycle. If the battery is discharged and recharged 50%, it only counts as one
                                       half cycle. Pylontech specifies a lifetime of several 1000 cycles
                                       (see data sheet).                                                                  </li>
 <li><b>packImbalance</b><br>          current imbalance of voltage between the single cells of the
                                       battery module (%)                                                                 </li>
 <li><b>packPower</b><br>              current drawn (+) or delivered (-) power (W) of the battery module                 </li>
 <li><b>packSOC</b><br>                State of charge (%) of the battery module                                          </li>
 <li><b>packState</b><br>              current working status of the battery module                                       </li>
 <li><b>packVolt</b><br>               current voltage (V) of the battery module                                          </li>

 <li><b>paramCellHighVoltLimit</b><br>      System parameter upper voltage limit (V) of a cell                                 </li>
 <li><b>paramCellLowVoltLimit</b><br>       System parameter lower voltage limit (V) of a cell (alarm limit)                   </li>
 <li><b>paramCellUnderVoltLimit</b><br>     System parameter undervoltage limit (V) of a cell (protection limit)               </li>
 <li><b>paramChargeCurrentLimit</b><br>     System parameter charging current limit (A) of the battery module                  </li>
 <li><b>paramChargeHighTempLimit</b><br>    System parameter upper temperature limit (°C) up to which the battery charges      </li>
 <li><b>paramChargeLowTempLimit</b><br>     System parameter lower temperature limit (°C) up to which the battery charges      </li>
 <li><b>paramDischargeCurrentLimit</b><br>  System parameter discharge current limit (A) of the battery module                 </li>
 <li><b>paramDischargeHighTempLimit</b><br> System parameter upper temperature limit (°C) up to which the battery discharges   </li>
 <li><b>paramDischargeLowTempLimit</b><br>  System parameter lower temperature limit (°C) up to which the battery discharges   </li>
 <li><b>paramModuleHighVoltLimit</b><br>    System parameter upper voltage limit (V) of the battery module                     </li>
 <li><b>paramModuleLowVoltLimit</b><br>     System parameter lower voltage limit (V) of the battery module (alarm limit)       </li>
 <li><b>paramModuleUnderVoltLimit</b><br>   System parameter undervoltage limit (V) of the battery module (protection limit)   </li>
 <li><b>protocolVersion</b><br>             PYLON low voltage RS485 protocol version                                           </li>
 <li><b>serialNumber</b><br>                Serial number                                                                      </li>
 </ul>
 <br><br>

=end html
=begin html_DE

 <a id="PylonLowVoltage"></a>
 <h3>PylonLowVoltage</h3>
 <br>
 Modul zur Einbindung von Niedervolt-Batterien mit Batteriemanagmentsystem (BMS) des Herstellers Pylontech über RS485 via
 RS485/Ethernet-Gateway. Die Kommunikation zum RS485-Gateway erfolgt ausschließlich über eine Ethernet-Verbindung.<br>
 Das Modul wurde bisher erfolgreich mit Pylontech Batterien folgender Typen eingesetzt: <br>

 <ul>
  <li> US2000        </li>
  <li> US2000B Plus  </li>
  <li> US2000C       </li>
  <li> US2000 Plus   </li>
  <li> US3000        </li>
  <li> US3000C       </li>
  <li> US5000        </li>
 </ul>

 Als RS485-Ethernet-Gateways wurden bisher folgende Geräte erfolgreich eingesetzt: <br>
 <ul>
  <li> USR-TCP232-304 des Herstellers USRiot </li>
  <li> Waveshare RS485 to Ethernet Converter </li>
 </ul>

 Prinzipiell sollte auch jedes andere RS485/Ethernet-Gateway kompatibel sein.
 <br><br>

 <b>Voraussetzungen</b>
 <br><br>
 Dieses Modul benötigt die Perl-Module:
 <ul>
    <li>IO::Socket::INET    (apt-get install libio-socket-multicast-perl)                          </li>
 </ul>

 Das Datenformat muß auf dem RS485 Gateway wie folgt eingestellt werden:
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> Start Bit </td><td>- 1 Bit          </td></tr>
        <tr><td> Data Bit  </td><td>- 8 Bit          </td></tr>
        <tr><td> Stop Bit  </td><td>- 1 Bit          </td></tr>
        <tr><td> Parity    </td><td>- ohne Parität   </td></tr>
     </table>
  </ul>
  <br>

 <b>Einschränkungen</b>
 <br>
 Das Modul unterstützt zur Zeit maximal 16 Batterien (1 Master + 15 Slaves) in bis zu 7 Gruppen. <br>
 Die realisierbare Gruppen- und Batterieanzahl ist von den eingesetzen Produkten abhängig. Dazu bitte die Hinweise des
 Herstellers beachten.
 <br><br>

 <a id="PylonLowVoltage-define"></a>
 <b>Definition</b>
 <ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;] [group=&lt;N&gt;]</b></code><br>
  <br>

  <b>Beispiel:</b> <br>
  define Pylone1 PylonLowVoltage 192.168.2.86:9000 1 group=0 <br>
  <br>

  <li><b>hostname/ip:</b><br>
     Hostname oder IP-Adresse des RS485/Ethernet-Gateways
  </li>

  <li><b>port:</b><br>
     Port-Nummer des im RS485/Ethernet-Gateways konfigurierten Ports
  </li>

  <li><b>bataddress:</b><br>
     Optionale Geräteadresse der Pylontech Batterie. Es können mehrere Pylontech Batterien über eine Pylontech-spezifische
     Link-Verbindung verbunden werden. Die zulässige Anzahl ist der jeweiligen Pylontech Dokumentation zu entnehmen. <br>
     Die Master Batterie im Verbund (mit offenem Link Port 0 bzw. an der die RS485-Verbindung angeschlossen ist) hat die
     Adresse 1, die nächste Batterie hat dann die Adresse 2 und so weiter.
     Ist keine Geräteadresse angegeben, wird die Adresse 1 verwendet.
  </li>

  <li><b>group:</b><br>
     Optionale Gruppennummer des Batteriestacks. Ist group=0 oder nicht angegeben, wird die Standardkonfiguration
     "Single Group" verwendet. Die Gruppennummer kann 0 bis 7 sein.
  </li>
  <br>
 </ul>

 <b>Arbeitsweise und Architektur</b>
 <ul>
 Das Modul liest entsprechend der Einstellung des Attributes "interval" zyklisch Werte aus, die das
 Batteriemanagementsystem über die RS485-Schnittstelle zur Verfügung stellt. <br><br>

 In einer typischen Installation ist genau ein RS485/Ethernet-Gateway am RS485-Port der Pylontech Master-Batterie
 angeschlossen, während sich mehrere PylonLowVoltage-Devices (jeweils eines pro Batterieadresse) dieses eine Gateway
 teilen. <br>
 Für jede unterschiedliche &lt;hostname/ip&gt;:&lt;port&gt;-Kombination unterhält das Modul genau einen dauerhaften,
 kleinen Hintergrundprozess (realisiert mit FHEMs SubProcess.pm), der die TCP-Verbindung zum Gateway offen hält und
 alle RS485-Anfragen der an diesem Gateway hängenden Devices serialisiert. Alle Devices, die dasselbe Gateway
 referenzieren, teilen sich diesen einen Hintergrundprozess automatisch (Referenzzählung); er wird von dem Device
 gestartet, das ihn zuerst benötigt, und automatisch beendet, sobald das letzte ihn nutzende Device gelöscht wird
 oder FHEM heruntergefahren wird. Wird festgestellt, dass der Hintergrundprozess nicht mehr lebt (z.B. nach einem
 Absturz), wird er transparent durch das nächste Device neu gestartet, das ihn benötigt. <br>
 Dadurch bleibt der FHEM-Hauptprozess jederzeit voll antwortfähig, unabhängig davon wie langsam oder unzuverlässig
 das RS485-Gateway antwortet, ohne den Speicher- und CPU-Overhead, für jeden einzelnen Abfragezyklus einen neuen
 Prozess zu forken.
 </ul>

 <a id="PylonLowVoltage-get"></a>
 <b>Get</b>
 <br>
 <ul>
  <a id="PylonLowVoltage-get-data"></a>
  <li><b>data</b><br>
    Die Datenabfrage des Batteriemanagementsystems wird ausgeführt. Der Zeitgeber der zyklischen Abfrage wird entsprechend
    dem gesetzten Wert des Attributes "interval" neu initialisiert.
    <br>
  </li>
  <br>
 
  <a id="PylonLowVoltage-get-listQueue"></a>
  <li><b>listQueue</b><br>
    Zeigt den Status, Prozess-ID des gemeinsam genutzten Gateway-Hintergrundprozesses dieses Devices sowie die 
    aktuelle Kommando-Queue. 
    <br>
  </li>
  <br>
  </ul>

 <a id="PylonLowVoltage-attr"></a>
 <b>Attribute</b>
 <br<br>
 <ul>
   <a id="PylonLowVoltage-attr-disable"></a>
   <li><b>disable 0|1</b><br>
     Aktiviert/deaktiviert die Gerätedefinition.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-interval"></a>
   <li><b>interval &lt;Sekunden&gt;</b><br>
     In dem festgelegten Intervall (Sekunden) wird die Kommando-Queue darauf überprüft, ob bereits eine Batterie-Datenabfrage 
     geplant ist. Fehlt ein entsprechender Eintrag, wird automatisch ein neuer Request hinzugefügt.
     Bei einem interval-Wert von 0 findet keine automatische Datenabfrage statt. <br>
     (default: 30)
   </li>
   <br>

   <a id="PylonLowVoltage-attr-timeout"></a>
   <li><b>timeout &lt;Sekunden&gt;</b><br>
     Maximale Zeit (in Sekunden), die der Subprozess für die komplette Kommandokette eines Requests zur Verfügung hat. <br>
     Der Wert begrenzt nicht einzelne Befehle, sondern das Gesamtbudget aller auszuführenden Funktionsaufrufe inklusive Wartezeiten. <br>
     (default: 3.0)
   </li>
   <br>

   <a id="PylonLowVoltage-attr-userBatterytype"></a>
   <li><b>userBatterytype</b><br>
     Der automatisch ermittelte Batterietyp (Reading batteryType) wird durch die angegebene Zeichenfolge ersetzt.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-waitTimeBetweenRS485Cmd"></a>
   <li><b>waitTimeBetweenRS485Cmd &lt;Sekunden&gt;</b><br>
     Wartezeit zwischen der Ausführung aufeinanderfolgender RS485 Befehle innerhalb eines Abfragezyklus, ausgewertet
     innerhalb des gemeinsam genutzten Hintergrundprozesses. <br>
     Laut Betriebsanleitung US3000C muß die Unterbrechung jedes RS485-Befehls mindestens >= 1 s betragen. <br>
     (default: 1.0)
   </li>
   <br>

 </ul>

 <a id="PylonLowVoltage-readings"></a>
 <b>Readings</b>
 <ul>
 <li><b>bmsTemperature</b><br>         Temperatur (°C) des Batteriemanagementsystems                                      </li>
 <li><b>cellTemperature_0104</b><br>   Temperatur (°C) der Zellenpacks 1 bis 4                                            </li>
 <li><b>cellTemperature_0508</b><br>   Temperatur (°C) der Zellenpacks 5 bis 8                                            </li>
 <li><b>cellTemperature_0912</b><br>   Temperatur (°C) der Zellenpacks 9 bis 12                                           </li>
 <li><b>cellTemperature_1315</b><br>   Temperatur (°C) der Zellenpacks 13 bis 15                                          </li>
 <li><b>cellTemperature_Pos_XX</b><br> Temperatur (°C) der Position XX (nicht näher spezifiziert)                         </li>
 <li><b>cellVoltage_XX</b><br>         Zellenspannung (V) des Zellenpacks XX. In dem Batteriemodul sind "packCellcount"
                                       Zellenpacks in Serie geschaltet verbaut. Jedes Zellenpack besteht aus parallel
                                       geschalten Einzelzellen.                                                           </li>
 <li><b>cellVoltageAvg</b><br>         mittlere Zellenspannung (V)                                                        </li>
 <li><b>cellVoltageMax</b><br>         höchste Zellenspannung (V) aller Zellen des aktuellen Zyklus                       </li>
 <li><b>cellVoltageMin</b><br>         niedrigste Zellenspannung (V) aller Zellen des aktuellen Zyklus                    </li>
 <li><b>chargeCurrentLimit</b><br>     aktueller Grenzwert für den Ladestrom (A)                                          </li>
 <li><b>chargeEnable</b><br>           aktuelles Flag Laden erlaubt                                                       </li>
 <li><b>chargeFullRequest</b><br>      aktuelles Flag Batteriemodul voll laden (notfalls aus dem Netz)                    </li>
 <li><b>chargeImmediatelySOCXX</b><br> aktuelles Flag Batteriemodul sofort laden
                                       (05: SOC Grenze 5-9%, 09: SOC Grenze 9-13%)                                        </li>
 <li><b>chargeVoltageLimit</b><br>     aktuelle Ladespannungsgrenze (V) des Batteriemoduls                                </li>
 <li><b>cmdChainDuration</b><br>       reale Verarbeitungszeit (s) der letzten Befehlskette (Verbindungsaufbau + alle
                                       ausgeführten BMS-Kommandos des Zyklus), gemessen im Hintergrundprozess            </li>
 <li><b>dischargeCurrentLimit</b><br>  aktueller Grenzwert für den Entladestrom (A)                                       </li>
 <li><b>dischargeEnable</b><br>        aktuelles Flag Entladen erlaubt                                                    </li>
 <li><b>dischargeVoltageLimit</b><br>  aktuelle Entladespannungsgrenze (V) des Batteriemoduls                             </li>

 <li><b>moduleSoftwareVersion_manufacture</b><br> Firmware Version des Batteriemoduls                                     </li>

 <li><b>packAlarmInfo</b><br>          Alarmstatus (ok - Batterienmodul ist in Ordnung, failure - im Batteriemodul liegt
                                       eine Störung vor)                                                                  </li>
 <li><b>packCapacity</b><br>           nominale Kapazität (Ah) des Batteriemoduls                                         </li>
 <li><b>packCapacityRemain</b><br>     aktuelle Kapazität (Ah) des Batteriemoduls                                         </li>
 <li><b>packCellcount</b><br>          Anzahl der Zellenpacks im Batteriemodul                                            </li>
 <li><b>packCurrent</b><br>            aktueller Ladestrom (+) bzw. Entladstrom (-) des Batteriemoduls (A)                </li>
 <li><b>packCycles</b><br>             Anzahl der Vollzyklen - Die Anzahl der Zyklen ist in gewisserweise ein Maß für den
                                       Verschleiß der Batterie. Eine komplettes Laden und Entladen wird als ein Zyklus
                                       gewertet. Wird die Batterie 50% entladen und wieder aufgeladen, zählt das nur als ein
                                       halber Zyklus. Pylontech gibt eine Lebensdauer von mehreren 1000 Zyklen an
                                       (siehe Datenblatt).                                                                </li>
 <li><b>packImbalance</b><br>          aktuelles Ungleichgewicht der Spannung zwischen den Einzelzellen des
                                       Batteriemoduls (%)                                                                 </li>
 <li><b>packPower</b><br>              aktuell bezogene (+) bzw. gelieferte (-) Leistung (W) des Batteriemoduls           </li>
 <li><b>packSOC</b><br>                Ladezustand (%) des Batteriemoduls                                                 </li>
 <li><b>packState</b><br>              aktueller Arbeitsstatus des Batteriemoduls                                         </li>
 <li><b>packVolt</b><br>               aktuelle Spannung (V) des Batteriemoduls                                           </li>

 <li><b>paramCellHighVoltLimit</b><br>      Systemparameter obere Spannungsgrenze (V) einer Zelle                         </li>
 <li><b>paramCellLowVoltLimit</b><br>       Systemparameter untere Spannungsgrenze (V) einer Zelle (Alarmgrenze)          </li>
 <li><b>paramCellUnderVoltLimit</b><br>     Systemparameter Unterspannungsgrenze (V) einer Zelle (Schutzgrenze)           </li>
 <li><b>paramChargeCurrentLimit</b><br>     Systemparameter Ladestromgrenze (A) des Batteriemoduls                        </li>
 <li><b>paramChargeHighTempLimit</b><br>    Systemparameter obere Temperaturgrenze (°C) bis zu der die Batterie lädt      </li>
 <li><b>paramChargeLowTempLimit</b><br>     Systemparameter untere Temperaturgrenze (°C) bis zu der die Batterie lädt     </li>
 <li><b>paramDischargeCurrentLimit</b><br>  Systemparameter Entladestromgrenze (A) des Batteriemoduls                     </li>
 <li><b>paramDischargeHighTempLimit</b><br> Systemparameter obere Temperaturgrenze (°C) bis zu der die Batterie entlädt   </li>
 <li><b>paramDischargeLowTempLimit</b><br>  Systemparameter untere Temperaturgrenze (°C) bis zu der die Batterie entlädt  </li>
 <li><b>paramModuleHighVoltLimit</b><br>    Systemparameter obere Spannungsgrenze (V) des Batteriemoduls                  </li>
 <li><b>paramModuleLowVoltLimit</b><br>     Systemparameter untere Spannungsgrenze (V) des Batteriemoduls (Alarmgrenze)   </li>
 <li><b>paramModuleUnderVoltLimit</b><br>   Systemparameter Unterspannungsgrenze (V) des Batteriemoduls (Schutzgrenze)    </li>
 <li><b>protocolVersion</b><br>             PYLON low voltage RS485 Prokollversion                                        </li>
 <li><b>serialNumber</b><br>                Seriennummer                                                                  </li>
 </ul>
 <br><br>

=end html_DE

=for :application/json;q=META.json 70_PylonLowVoltage.pm
{
  "abstract": "Integration of pylontech LiFePo4 low voltage batteries (incl. BMS) over RS485 via ethernet gateway (ethernet interface)",
  "x_lang": {
    "de": {
      "abstract": "Integration von Pylontech Niedervolt Batterien (mit BMS) &uumlber RS485 via Ethernet-Gateway (Ethernet Interface)"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "battery",
    "Pylontech",
    "BMS",
    "ESS",
    "PV"
  ],
  "version": "v2.0.0",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "GPUtils": 0,
        "IO::Socket::INET": 0,
        "Errno": 0,
        "FHEM::SynoModules::SMUtils": 1.0220,
        "Time::HiRes": 0,
        "Carp": 0,
        "SubProcess": 0,
        "Storable": 0,
        "Scalar::Util": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "",
      "title": ""
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/70_PylonLowVoltage.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/70_PylonLowVoltage.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
