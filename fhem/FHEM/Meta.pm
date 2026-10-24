#########################################################################################################################
# # $Id$
#########################################################################################################################
#       Meta.pm
#
#       Author:     Julian Pawlowski  julian.pawlowski@gmail.com
#       Maintainer: 2026 - 2026 Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       This copyright notice MUST APPEAR in all copies of the script!
#
#########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' Meta.pm
#  Zeilenenden auf LF umstellen: sed -i 's/\r$//' Meta.pm
#
#  Syntaxprüfung: cd /opt/fhem    
#                 perl -wc -I. -IFHEM FHEM/Meta.pm
#########################################################################################################################

package main;
use strict;
use warnings;

# stellt den gleichen Hash wie bei echten FHEM-Modulen im FHEM main-Kontext bereit
use vars qw(%packages);

# Paket definieren
package FHEM::Meta;
use strict;
use warnings;

use GPUtils qw(GP_Import);
use Encode;
use File::stat;

# Vor der Modulkompilierung ausführen
BEGIN {

  # Import aus main::
  GP_Import(
    qw(
      attr
      defs
      devspec2array
      fhemTimeGm
      FmtDateTime
      Log
      modules
      packages
      TimeNow
      )
  );
}

# Exportierte Variablen
#

our %supportForum = (
    forum            => 'FHEM Forum',
    url              => 'https://forum.fhem.de',
    uri              => '/index.php/board,%BOARDID%.0.html',
    rss              => '/index.php?action=.xml;type=rss',
    default_language => 'de',
);
our %supportForumCategories = (
    'Allgemeine Informationen' => {
        'Forum-Software' => {
            description =>
              'Regeln, Diskussionen, Fragen zu diesem FHEM-Forum selbst',
            boardId => 15,
        },
        'Wiki' => {
            description => 'Kommentare, Korrekturvorschläge, Anregungen zu Artikeln im FHEM Wiki',
            boardId => 80,
        },
        'Termine und Veranstaltungen' => {
            description => 'Interessante Termine zu Messen oder sonstigen Veranstaltungen wie z.B. "FHEM Stammtische"',
            boardId => 54,
        },
        'FHEM e.V. - Der Verein' => {
            description => 'Gesprächsthemen rund um den FHEM e.V.',
            boardId     => 90,

            'Bildungsförderung' => {
                boardId => 95,
            },
        },
    },
    'FHEM' => {
        'Ankündigungen' => {
            description => 'Ankündigungen und Hinweise zu FHEM',
            boardId     => 40,
        },
        'Anfängerfragen' => {
            description => 'Jeder fängt mal an ...',
            boardId     => 18,
        },
        'Automatisierung' => {
            description => 'Aufgaben mit FHEM automatisieren',
            boardId     => 20,

            'DOIF' => {
                boardId => 73,
            },
        },
        'Codeschnipsel' => {
            description => 'Nützliche Codeschnipsel',
            boardId     => 8,
        },
        'English Corner' => {
            language    => 'en',
            description => 'Discussions about FHEM in English',
            boardId     => 52,
        },
        'Frontends' => {
            description => 'FHEM Frontends',
            boardId     => 19,

            'FHEMWEB' => {
                boardId => 75,
            },
            'FLOORPLAN' => {
                boardId => 76,
            },
            'RSS' => {
                boardId => 77,
            },
            'TabletUI' => {
                boardId => 71,
            },
            'fronthem/smartVISU' => {
                boardId => 72,
            },
            'SVG/Plots/logProxy' => {
                boardId => 78,
            },
            'readingsGroup/readingsHistory' => {
                boardId => 79,
            },
            'Sprachsteuerung' => {
                boardId => 93,
            },
        },
        'Mobile Devices' => {
            description => 'FHEM auf mobilen Geräten',
            boardId     => 37,
        },
        'Sonstiges' => {
            description => 'Sonstiger Bezug zu FHEM',
            boardId     => 46,
        },
    },
    'FHEM - Hausautomations-Systeme' => {
        '1Wire' => {
            description => '1Wire',
            boardId     => 26,
        },
        'EnOcean' => {
            description => 'EnOcean',
            boardId     => 27,
        },
        'Home Connect' => {
            description =>
              'Geräte, API und Modulentwicklung rund um Home Connect',
            boardId => 97,
        },
        'Homematic' => {
            description => 'HomeMatic und Zubehör',
            boardId     => 22,
        },
        'InterTechno' => {
            description => 'InterTechno',
            boardId     => 24,
        },
        'KNX/EIB' => {
            description => 'KNX/EIB',
            boardId     => 51,
        },
        'MAX' => {
            description => 'MAX',
            boardId     => 23,
        },
        'MQTT' => {
            description => 'MQTT',
            boardId     => 94,
        },
        'RFXTRX' => {
            description => 'RFXTRX',
            boardId     => 25,
        },
        'SlowRF' => {
            description => 'FS20, FHT, EM, WS, HMS',
            boardId     => 21,
        },
        'Zigbee' => {
            description => 'Mesh-Netz mit Hue, Tradfri, Xiaomi, usw.',
            boardId     => 99,
        },
        'ZWave' => {
            description => 'ZWave',
            boardId     => 28,
        },
        'Sonstige Systeme' => {
            description => 'Sonstige Hausautomations-Systeme',
            boardId     => 29,
        },
        'Unterstützende Dienste' => {
            description => 'unterstützende Dienste und Module',
            boardId     => 44,

            'Kalendermodule' => {
                boardId => 85,
            },
            'Wettermodule' => {
                boardId => 86,
            },
        },
    },
    'FHEM - Hardware' => {
        'FRITZ!Box' => {
            description => 'AVM FRITZ!Box',
            boardId     => 31,
        },
        'Network Attached Storage (NAS)' => {
            description => 'NAS-Systeme (Synology, etc.)',
            boardId     => 30,
        },
        'Einplatinencomputer' => {
            description =>
              'Einplatinencomputer (z.B. Raspberry Pi, Beagle Bone, etc.)',
            boardId => 32,
        },
        'Server - Linux' => {
            description => 'Linux Server',
            boardId     => 33,
        },
        'Server - Mac' => {
            description => 'Apple macOS',
            boardId     => 63,
        },
        'Server - Windows' => {
            description => 'Microsoft Windows Server',
            boardId     => 34,
        },
    },
    'FHEM - Anwendungen' => {
        'Beleuchtung' => {
            description => 'Alles was mit Beleuchtung zu tun hat',
            boardId     => 62,
        },
        'Heizungssteuerung/Raumklima' => {
            description => 'Anwendungen rund um Heizkörper, Heizungsanlagen, Thermen, Wärme, Raumtemperatur, Belüftung, etc.',
            boardId => 60,
        },
        'Multimedia' => {
            description => 'Multimediageräte, TV, Fernbedienungen, etc.',
            boardId     => 53,
        },
        'Solaranlagen' => {
            description => 'Solaranlagen zur Wärme- oder Stromgewinnung',
            boardId     => 61,
        },
    },
    'FHEM - Entwicklung' => {
        'FHEM Development' => {
            description => 'FHEM Developers Corner',
            boardId     => 48,
        },
        'Wunschliste' => {
            description =>
              'Anregungen, Ideen, Vorschläge für FHEM Erweiterungen',
            boardId => 35,
        },
    },
    'CUL' => {
        'Ankündigungen' => {
            description => 'Ankündigungen und Hinweise zur CUL-Firmware',
            boardId     => 41,
        },
        'cul-fans' => {
            boardId => 6,
        },
        'Hard- und Firmware' => {
            description => 'CUL/CUN Hard- und Firmware',
            boardId     => 47,
        },
    },
    'CUL - Entwicklung' => {
        'CUL Development' => {
            description => 'CUL Developers Corner',
            boardId     => 49,
        },
        'Fehlerberichte' => {
            description => 'Berichte zu Fehlern in der CUL-Firmware',
            boardId     => 42,
        },
        'Wunschliste' => {
            description =>
              'Anregungen, Ideen, Vorschläge für CUL-Firmware Erweiterungen',
            boardId => 43,
        },
    },
    'Verschiedenes' => {
        'Bastelecke' => {
            description => 'Projekte für Bastler, die gerne auch mal zum Lötkolben greifen',
            boardId => 17,

            'ESP8266' => {
                boardId => 74,
            },
            '3D-Druck/Gehäuse' => {
                boardId => 92,
            },
            'MySensors' => {
                boardId => 96,
            },
        },
        'Marktplatz - Güter' => {
            description => 'Kein gewerblicher oder gewerbsmäßiger Handel',
            boardId     => 16,

            'Sammelbestellungen' => {
                boardId => 98,
            },
        },
        'Marktplatz - Dienstleistungen' => {
            boardId => 67,
        },
        'Marktplatz - Kommerzielle Güter' => {
            boardId => 101,
        },
        'Marktplatz - Kommerzielle Dienstleistungen' => {
            boardId => 100,
        },
        'Off-Topic' => {
            description => 'Allgemeine Themen',
            boardId     => 39,
        },
        'Projekte' => {
            description => 'Vorstellung von größeren Projekten die mit FHEM realisiert wurden',
            boardId => 50,
        },
        'User stellen sich vor' => {
            description => 'Das "Who is Who" von FHEM',
            boardId     => 7,
        },
    }
);

our %maintainers;           # Maintainer und was sie betreuen
our %moduleMaintainers;     # Module und wer sie betreut
our %packageMaintainers;    # Pakete und wer sie betreut
our %fileMaintainers;       # Dateien und wer sie betreut

our $coreUpdate;
our %corePackageUpdates;
our %coreFileUpdates;

our %moduleUpdates;
our %packageUpdates;
our %fileUpdates;

our %keywords;
our %keywordDescription = (
    'fhem-core' => {
        'en' => 'Belongs to the official FHEM core software',
        'de' => 'Gehört zum offiziellen Kern von FHEM',
    },
    'fhem-3rdparty' => {
        'en' =>
          'Originates from a source outside of the official FHEM core software',
        'de' =>
          'Stammt aus einer Quelle außerhalb des offiziellen Kern von FHEM',
    },
    'fhem-commercial' => {
        'en' => 'commercial relation',
        'de' => 'kommerzieller Zusammenhang',
    },
    'fhem-mod' => {
        'en' => 'FHEM module',
        'de' => 'FHEM Modul',
    },
    'fhem-pkg' => {
        'en' => 'FHEM development package that is used by FHEM modules',
        'de' => 'FHEM Entwickler Paket, welches in FHEM Modulen verwendet wird',
    },
    'fhem-mod-3rdparty' => {
        'en' => 'FHEM module that originates from a source outside of the official FHEM core software',
        'de' => 'FHEM Modul, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-pkg-3rdparty' => {
        'en' => 'FHEM development package that originates from a source outside of the official FHEM core software',
        'de' => 'FHEM Entwickler Paket, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-mod-commercial' => {
        'en' => 'commercial FHEM module that originates from a source outside of the official FHEM core software',
        'de' => 'kommerzielles FHEM Modul, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-pkg-commercial' => {
        'en' => 'commercial FHEM development package that originates from a source outside of the official FHEM core software',
        'de' => 'kommerzielles FHEM Entwickler Paket, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-mod-local' => {
        'en' => 'FHEM module that is maintained locally on the machine',
        'de' => 'FHEM Modul, welches lokal auf der Maschine verwaltet wird',
    },
    'fhem-pkg-local' => {
        'en' => 'FHEM development package that is maintained locally on the machine',
        'de' => 'FHEM Entwickler Paket, welches lokal auf der Maschine verwaltet wird',
    },
    'fhem-mod-command' => {
        'en' => 'FHEM system command w/o any FHEM device object visible',
        'de' => 'FHEM Systembefehl ohne sichtbares FHEM Geräte-Objekt.',
    },
    'fhem-mod-device' => {
        'en' => 'represents a physical device',
        'de' => 'repräsentiert ein physisches Gerät',
    },
    'fhem-mod-helper' => {
        'en' => 'logical, non-physical device',
        'de' => 'logisches, nicht physisches Gerät',
    },
);

our %dependents;

# Perl Pragmas, basierend auf https://metacpan.org/release/perl
my @perlPragmas = qw(
  attributes
  autodie
  autouse
  base
  bigint
  bignum
  bigrat
  blib
  bytes
  charnames
  constant
  diagnostics
  encoding
  feature
  fields
  filetest
  if
  integer
  less
  lib
  locale
  mro
  open
  ops
  overload
  overloading
  parent
  re
  sigtrap
  sort
  strict
  subs
  threads
  threads::shared
  utf8
  vars
  vmsish
  warnings
  warnings::register
);

# based on https://metacpan.org/release/perl
# and https://metacpan.org/pod/Win32#Alphabetical-Listing-of-Win32-Functions
my @perlCoreModules = qw(
  experimental
  I18N::LangTags
  I18N::LangTags::Detect
  I18N::LangTags::List
  IO
  IO::Dir
  IO::File
  IO::Handle
  IO::Pipe
  IO::Poll
  IO::Seekable
  IO::Select
  IO::Socket
  IO::Socket::INET
  IO::Socket::UNIX
  Amiga::ARexx
  Amiga::Exec
  B
  B::Concise
  B::Showlex
  B::Terse
  B::Xref
  O
  OptreeCheck
  Devel::Peek
  ExtUtils::Miniperl
  Fcntl
  File::DosGlob
  File::Find
  File::Glob
  FileCache
  GDBM_File
  Hash::Util::FieldHash
  Hash::Util
  I18N::Langinfo
  IPC::Open2
  IPC::Open3
  NDBM_File
  ODBM_File
  Opcode
  ops
  POSIX
  PerlIO::encoding
  PerlIO::mmap
  PerlIO::scalar
  PerlIO::via
  Pod::Html
  SDBM_File
  Sys::Hostname
  Tie::Hash::NamedCapture
  Tie::Memoize
  VMS::DCLsym
  VMS::Filespec
  VMS::Stdio
  Win32CORE
  XS::APItest
  XS::Typemap
  arybase
  ext/arybase/t/scope_0.pm
  attributes
  mro
  re
  Haiku
  AnyDBM_File
  B::Deparse
  B::Op_private
  Benchmark
  Class::Struct
  Config::Extensions
  DB
  DBM_Filter
  DBM_Filter::compress
  DBM_Filter::encode
  DBM_Filter::int32
  DBM_Filter::null
  DBM_Filter::utf8
  DirHandle
  English
  ExtUtils::Embed
  ExtUtils::XSSymSet
  File::Basename
  File::Compare
  File::Copy
  File::stat
  FileHandle
  FindBin
  Getopt::Std
  Net::hostent
  Net::netent
  Net::protoent
  Net::servent
  PerlIO
  SelectSaver
  Symbol
  Thread
  Tie::Array
  Tie::Handle
  Tie::StdHandle
  Tie::SubstrHash
  Time::gmtime
  Time::localtime
  Time::tm
  UNIVERSAL
  Unicode::UCD
  User::grent
  User::pwent
  blib
  bytes
  charnames
  deprecate
  feature
  filetest
  integer
  less
  locale
  open
  overload
  overloading
  sigtrap
  sort
  strict
  subs
  utf8
  vars
  version
  vmsish
  warnings
  warnings::register
  OS2::ExtAttr
  OS2::PrfDB
  OS2::Process
  OS2::DLL
  OS2::REXX
  Win32::BuildNumber
  Win32::CopyFile
  Win32::DomainName
  Win32::FormatMessage
  Win32::FsType
  Win32::GetCwd
  Win32::GetFullPathName
  Win32::GetLastError
  Win32::GetLongPathName
  Win32::GetNextAvailDrive
  Win32::GetOSVersion
  Win32::GetShortPathName
  Win32::GetTickCount
  Win32::IsWinNT
  Win32::IsWin95
  Win32::LoginName
  Win32::NodeName
  Win32::SetChildShowWindow
  Win32::SetCwd
  Win32::SetLastError
  Win32::Sleep
  Win32::Spawn
);

# Paket-interne Variablen
#

# Muster (werden nur einmal kompiliert)
my $reFileName     = qr/^(?:\.\/)?((.+\/)?((?:([0-9]+)_)?(.+)\.(.+)))$/;
my $reControlsLine = qr/^((\S+) ((([0-9]+)-([0-9]+)-([0-9]+))_(([0-9]+):([0-9]+):([0-9]+))) ([0-9]+) (?:\.\/)?((.+\/)?((?:([0-9]+)_)?(.+)\.(.+))))$/;
my $reVcsId        = qr/(\$Id\: ((?:([0-9]+)_)?([\w]+)\.([\w]+))\s([0-9]+)\s((([0-9]+)-([0-9]+)-([0-9]+))\s(([0-9]+):([0-9]+):([0-9]+)))(?:[\w]+?)\s([\w.-]+)\s\$)/;
my $reVersionVar   = qr/((?:(?:my|our)\s+)?\$VERSION\s+=\s+[^v0-9]*(v?(?:[0-9]{1,3}\.[0-9]{1,3}(?:\.[0-9]{1,3})?)))/i;
my $reVersionHash  = qr/(->\{VERSION\}\s+=\s+[^v0-9]*(v?(?:[0-9]{1,3}\.[0-9]{1,3}(?:\.[0-9]{1,3})?)))/i;
my $reHdrVersion   = qr/(^#\s+Version:?\s+[^v0-9]*(v?(?:[0-9]{1,3}\.[0-9]{1,3}(?:\.[0-9]{1,3})?))(?:\s+.*)?)$/i;
my $reHdrChangelog = qr/(^#\s+(?:[0-9]{1,2}\.[0-9]{1,2}\.(?:[0-9]{2}|[0-9]{4})\s+)?[^v0-9]*(v?(?:[0-9]{1,3}\.[0-9]{1,3}(?:\.[0-9]{1,3})?))(?:\s+.*)?)$/i;

# Namen, die im Kontext FHEM selbst "Core" sind
my %fhemCoreNames = map { $_ => 1 } qw(fhem.pl FHEM Global FHEM::Meta Meta);

# Schlüsselwörter, die dem FHEM Core vorbehalten sind
my %reservedKeywords = map { $_ => 1 } qw(
  fhem-core
  fhem-mod
  fhem-pkg
  fhem-3rdparty
  fhem-mod-3rdparty
  fhem-pkg-3rdparty
  fhem-mod-local
  fhem-pkg-local
  fhem-commercial
  fhem-mod-commercial
  fhem-pkg-commercial
);

my @prereqPrios = qw(requires recommends suggests);

# Caches
my $scanner;                 # Perl::PrereqScanner::NotQuiteLite-Objekt (einmal erzeugt)
my $jsonDecoder;             # decode_json-Coderef (einmal ermittelt)
my $coreListAvailable;       # undef = ungeprüft, 1 = Module::CoreList verfügbar, 0 = nicht
my %perlCoreIndex;           # Perl Core Module als Hash (lazy aus den Listen oben)
my %perlCoreCache;           # Ergebnisse von ModuleIsPerlCore
my %loading;                 # Laufende Load-Vorgänge (Schutz vor zyklischen Paketabhängigkeiten)

# Globalen Hash %packages initialisieren
__GetPackages() unless(keys %packages > 0);

#TODO das soll von InitMod() übernommen werden eigene Metadaten laden
my %META;
my $metaErr = __GetMetadata(__FILE__, \%META);
return $metaErr if($metaErr);
$packages{Meta}{META} = \%META;
use version 0.77; our $VERSION = $packages{Meta}{META}{version};

###############################################################
# Initiales Laden der Informationen damit die Meta-Analyse 
# bereit ist
###############################################################
__GetUpdatedata()     unless(defined($coreUpdate));
__GetMaintainerdata() unless(keys %moduleMaintainers > 0);

sub import {

  #TODO Eine Funktion in den main-Kontext exportieren, damit ein Device
  #  Metadaten nutzen kann, um Perl-Abhängigkeiten aus META.json zu laden.
  #  Das schafft einen zentralen Ort für Modulabhängigkeiten
  #  ohne Quellcode-Analyse.
}

# Lädt die Metadaten für ein einzelnes Modul anhand des Dateinamens
sub InitMod {
  my ($filePath, $modHash, $runInLoop) = @_;

  my $err = __PutMetadata ($filePath, $modHash, 1, $runInLoop);
  
  if ($err) {
    Log (1, __PACKAGE__."::InitMod: ERROR:\n".$err);
    $@ = $err;
    return $err;
  }

  return undef if(!defined($modHash->{META}) || !defined($modHash->{META}{x_file}));

  # Name zum Modul-Hash hinzufügen
  $modHash->{NAME} = $modHash->{META}{x_file}[4];
  $modHash->{NAME} =~ s/^.*://g;                      # evtl. vorangestellte Parent-Modulnamen entfernen

  # nur beim Neuladen eines Moduls ausführen
  my $name = $modHash->{NAME};
  if(defined($modules{$name}) && defined($modules{$name}{NAME}) && $name eq $modules{$name}{NAME}) {
    for my $devName (devspec2array('TYPE='.$name)) {
      __CopyMetaToInternals($defs{$devName}, $modHash->{META});
    }
  }

  return undef;
}

# Lädt die Metadaten für eine Liste von Modulen
sub Load {
  my ($modList, $reload) = @_;
  
  my $t        = TimeNow();
  my $lmodules = __ResolveModuleList($modList);

  if (!$lmodules) {
    $@ = __PACKAGE__."::Load: ERROR: Unknown parameter value";
    Log (1, $@);
    return "$@";
  }

  if ($reload) {
    __GetUpdatedata();
    __GetMaintainerdata();
  }

  my $generatedBy = __GeneratedBy($t);
  my $modPath     = $attr{global}{modpath};
  my @rets;

  for my $modName (@{$lmodules}) {
    $modName = 'Global' if(uc($modName) eq 'FHEM');

    my $isModule  = exists($modules{$modName});
    my $isPackage = exists($packages{$modName});
    next if(!$isModule && !$isPackage);

    next if($isModule && !$isPackage && !defined($modules{$modName}{ORDER}));           # Abbruch wenn die Moduldatei nicht von fhem.pl indiziert wurde

    # Nur fortfahren wenn META noch nicht geladen ist
    # oder explizit neu geladen werden soll
    my $modLoaded = $isModule  && __MetaLoaded($modules{$modName});
    my $pkgLoaded = $isPackage && __MetaLoaded($packages{$modName});
    next if(!$reload && (!$isModule || $modLoaded) && (!$isPackage || $pkgLoaded));

    # Pakete sind initial undef -> echten Hash anlegen, damit META abgelegt werden kann
    $packages{$modName} //= {} if($isPackage);

    delete $modules{$modName}{META}  if($isModule);
    delete $packages{$modName}{META} if($isPackage);

    for my $type ($isModule ? 'module' : (), $isPackage ? 'package' : ()) {             # Schutz vor Endlosschleife bei zyklischen Paketabhängigkeiten
      next if($loading{$type}{$modName});
      local $loading{$type}{$modName} = 1;

      my $filePath;
      if($modName eq 'Global') {
        $filePath = $modPath.'/fhem.pl';
      }
      elsif($modName eq 'configDB') {
        $filePath = $modPath.'/configDB.pm';
      }
      else {
        $filePath = $modPath.'/FHEM/'.($type eq 'module' ? $modules{$modName}{ORDER}.'_' : '').$modName.'.pm';
      }

      my $hash = $type eq 'module' ? $modules{$modName} : $packages{$modName};
      my $err  = InitMod($filePath, $hash, 1);
      push @rets, $err if($err);

      next if(!defined($hash->{META}));
      $hash->{META}{generated_by} = $generatedBy;

      if ($type eq 'module') {
        for my $devName (devspec2array('TYPE='.$modName)) {
          SetInternals($defs{$devName});
        }
      }
    }
  }

  if (@rets) {
    $@ = join("\n", @rets);
    return "$@";
  }

  return undef;
}

# Initialisiert eine Geräteinstanz eines FHEM-Moduls
sub SetInternals  {
  my ($devHash) = @_;
  $devHash = $defs{$devHash} if(defined($devHash) && !ref($devHash));

  my $modHash = __GetModuleHash($devHash);
  if(!$modHash) {
    $@ = __PACKAGE__."::SetInternals: ERROR: Module hash not found";
    return 0;
  }

  return 0 unless(defined($modHash->{LOADED}) && $modHash->{LOADED} eq '1');

  $devHash->{'.FhemMetaInternals'} = 1;
  __CopyMetaToInternals($devHash, $modHash->{META});

  return 1;
}

# Liefert ein Metadaten-Feld des Moduls zu einem Gerät
sub Get {
  my ($devHash, $field) = @_;
  $devHash = $defs{$devHash} if(defined($devHash) && !ref($devHash));

  my $modHash = __GetModuleHash($devHash);
  if(!$modHash) {
    $@ = __PACKAGE__."::Get: ERROR: Module hash not found";
    return 0;
  }

  my $modMeta = $modHash->{META};
  return $modMeta->{$field} if(ref($modMeta) && defined($modMeta->{$field}));
  return undef;
}

sub GetModuleSourceOrigin {
  my ($module) = @_;
  return 'fhem' if($fhemCoreNames{$module});

  for my $updates (\%moduleUpdates, \%packageUpdates, \%corePackageUpdates) {
    return $updates->{$module}[0] if(defined($updates->{$module}));
  }

  return '';
}

sub GetKeywordDesc {
  my ($keyword, $lang) = @_;
  $lang = 'en' unless($lang);
  return '' unless(defined($keywordDescription{$keyword}));

  # Fallback-Sprache umkehren
  my $desc = $keywordDescription{$keyword};
  $lang    = 'de' if(!defined($desc->{$lang}) && $lang eq 'en');

  return $desc->{$lang} // '';
}

sub ModuleIsCore {
  my ($module) = @_;
  return GetModuleSourceOrigin($module) eq 'fhem' ? 1 : 0;
}

sub ModuleIsInternal {
  my ($module) = @_;
  return 0 if(ModuleIsPerlCore($module));

  return 'module' if($module eq 'fhem.pl' || $module eq 'FHEM' || $module eq 'Global');

  my $fname = $module;
  $fname =~ s/^.*://g;                                # evtl. vorangestellte Parent-Modulnamen entfernen

  return 'package' if($fname eq 'Meta');

  # %packages-Einträge sind bis zum ersten Load undef -> bewusst "defined" statt "exists"
  my $isModule  = defined($modules{$fname});
  my $isPackage = defined($packages{$fname});
  return 'module+package' if($isModule && $isPackage);
  return 'module'         if($isModule);
  return 'package'        if($isPackage);

  # Hat das Modul einen relativen Pfad, wird angenommen
  #   dass es Teil von FHEM ist
  my $p = GetModuleFilepath($module);
  return $p && ($p =~ m/^(\.\/)?FHEM\/.+/ || $p =~ m/^(\.\/)?[^\/]+\.pm$/) ? 'file' : 0;
}

# Liefert den Dateipfad eines Perl-Moduls (ohne das Modul zu laden)
sub GetModuleFilepath {
  my @path;

  for my $package (@_) {
    (my $module = $package) =~ s/::/\//g;
    $module .= '.pm';

    if($package eq 'perl') {
      push @path, $^X;                                # echte Binärdatei
    }
    elsif(defined($INC{$module})) {
      push @path, $INC{$module};
    }

    # Pragmas nicht laden, Pfad ableiten
    elsif(ModuleIsPerlCore($package)) {
      my $n = $INC{'version.pm'};
      $n    =~ s/(.*\/).*/$1/;
      $n   .= $module;
      push @path, (-e $n ? $n : '');
    }
    else {
      push @path, __SearchInc($module);
    }
  }

  return @path if(wantarray);
  return join(',', @path) if(@path > 0);
}

sub ModuleIsPerlCore {
  my ($module) = @_;
  return 1 if($module =~ /^Perl$/i);
  return $perlCoreCache{$module} if(exists($perlCoreCache{$module}));

  # Index einmalig aufbauen
  %perlCoreIndex = map { $_ => 1 } (@perlPragmas, @perlCoreModules) unless(%perlCoreIndex);

  # Verfügbarkeit von Module::CoreList nur einmal prüfen
  if(!defined($coreListAvailable)) {
    local $@;
    $coreListAvailable = eval { require Module::CoreList; 1; } ? 1 : 0;
    $coreListAvailable = 0
      if(!defined(&Module::CoreList::is_core) || !defined(&Module::CoreList::first_release_by_date));
  }

  my $inList = $perlCoreIndex{$module} ? 1 : 0;
  my $result = $inList;
  if($coreListAvailable && Module::CoreList::is_core($module)) {
    $result = Module::CoreList::first_release_by_date($module);
  }

  return $perlCoreCache{$module} = $result;
}

# Metadaten aus einer FHEM-Moduldatei extrahieren, öffentliche Funktion - CoolTux
sub getMetadata {
  my $filePath = shift;
  my $modMeta  = shift;

  return __GetMetadata($filePath, $modMeta);
}

##########
# Private Funktionen
#

# Liefert die Modul-Hash-Referenz zu einem Gerät (oder undef)
sub __GetModuleHash {
  my ($devHash) = @_;
  return undef if(ref($devHash) ne 'HASH' || !defined($devHash->{TYPE}));

  my $modHash = $modules{$devHash->{TYPE}};
  return ref($modHash) eq 'HASH' ? $modHash : undef;
}

# Sind für den Modul-/Paket-Hash bereits Metadaten geladen?
sub __MetaLoaded {
  my ($hash) = @_;
  return ref($hash) eq 'HASH' && defined($hash->{META}) && ref($hash->{META}) eq 'HASH' ? 1 : 0;
}

# Wandelt den Parameter von Load() in eine Liste von Modulnamen um (undef bei falschem Parameter)
sub __ResolveModuleList {
  my ($modList) = @_;

  # Kein Parameter oder '1' -> alle geladenen (bzw. bei '1' auch ungenutzte) Module
  if(!$modList || (!ref($modList) && $modList eq '1')) {
    my $unused = ($modList && $modList eq '1') ? 1 : 0;
    return [ grep { $unused || (defined($modules{$_}{LOADED}) && $modules{$_}{LOADED} eq '1') } keys %modules ];
  }

  return [ $modList ]                if(!ref($modList));
  return [ @{$modList} ]             if(ref($modList) eq 'ARRAY');
  return [ keys %{$modList} ]        if(ref($modList) eq 'HASH');
  return undef;
}

sub __GeneratedBy {
  my ($t) = @_;
  return $packages{Meta}{META}{name}.' '.version->parse(__PACKAGE__->VERSION())->normal.', '.$t;
}

# Hängt einen Wert nur an, wenn er noch nicht in der Liste ist
sub __PushUnique {
  my ($list, $value, $ignoreCase) = @_;
  my $cmp = $ignoreCase ? lc($value) : $value;

  return 0 if(grep { ($ignoreCase ? lc($_) : $_) eq $cmp } @{$list});
  push @{$list}, $value;
  return 1;
}

# Sucht eine Moduldatei in @INC, ohne das Modul zu laden
sub __SearchInc {
  my ($file) = @_;

  for my $dir (@INC) {
    next if(ref($dir));                               # Hooks überspringen
    my $p = $dir.'/'.$file;
    return $p if(-f $p);
  }

  return '';
}

# Normalisiert eine Versionsangabe auf vX.Y.Z
sub __NormalizeVersion {
  my ($v) = @_;
  return undef unless($v);

  $v  = $v =~ m/^v/i ? lc($v) : lc('v'.$v);
  $v .= '.0' if($v !~ m/v[0-9]+\.[0-9]+\.[0-9]+/);

  return $v;
}

sub __EnsureArray {
  my ($hash, $key) = @_;
  $hash->{$key} = [ $hash->{$key} ] if(defined($hash->{$key}) && !ref($hash->{$key}));
}

sub __CopyMetaToInternals {
  return 0 unless(__PACKAGE__ eq caller(0));
  my ($devHash, $modMeta) = @_;
  return unless(ref($devHash) eq 'HASH' && defined($devHash->{'.FhemMetaInternals'}));
  return unless(defined($modMeta) && ref($modMeta) eq 'HASH');

  $devHash->{FVERSION} = $modMeta->{x_version} if(defined($modMeta->{x_version}));
}

# Initialisiert die Metadaten eines FHEM-Moduls
sub __PutMetadata {
  return 0 unless(__PACKAGE__ eq caller(0));
  my ($filePath, $modHash, $reload, $runInLoop) = @_;

  return if(!$reload && __MetaLoaded($modHash) && scalar keys %{$modHash->{META}} > 0);

  delete $modHash->{META};

  my %meta;
  my $err = __GetMetadata($filePath, \%meta, $runInLoop);
  return $err if($err);

  $modHash->{META} = \%meta;

  return undef;
}

# Ermittelt (einmalig) eine decode_json-Funktion
sub __GetJsonDecoder {
  return $jsonDecoder if(defined($jsonDecoder));
  return $jsonDecoder = __PACKAGE__->can('decode_json') if(__PACKAGE__->can('decode_json'));

  # Reihenfolge: Performance bzw. Verfügbarkeit
  for my $mod (qw(JSON::MaybeXS JSON Cpanel::JSON::XS JSON::XS JSON::PP JSON::backportPP)) {
    (my $file = $mod.'.pm') =~ s/::/\//g;

    local $@;
    my $ok = do {

      # Bevorzugte Backends für den JSON-Wrapper
      local $ENV{PERL_JSON_BACKEND} = $ENV{PERL_JSON_BACKEND} // 'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
        if($mod eq 'JSON');
      eval { require $file; 1; };
    };
    next unless($ok);

    my $code            = $mod->can('decode_json');
    return $jsonDecoder = $code if($code);
  }

  return undef;
}

# Liefert den Perl::PrereqScanner::NotQuiteLite (falls installiert)
sub __GetScanner {
  return $scanner if(defined($scanner));

  local $@;
  return undef unless(eval { require Perl::PrereqScanner::NotQuiteLite; 1; });

  return $scanner = Perl::PrereqScanner::NotQuiteLite->new(
    parsers  => [qw/:installed -UniversalVersion/],
    suggests => 1,
  );
}

# Zerlegt einen Dateipfad in die x_file-Struktur
sub __ParseFilePath {
  my ($filePath) = @_;
  my @f = $filePath =~ $reFileName or return undef;

  my @file;
  $file[0] = $f[0];                                   # komplette Übereinstimmung
  $file[1] = $f[1] ? $f[1] : '';                      # relativer Pfad, leer wenn im Verzeichnis von fhem.pl
  $file[2] = $f[2];                                   # Dateiname
  $file[3] = $f[3];                                   # Ordnungsnummer, evtl. undef
  $file[4] = $f[2] eq 'fhem.pl' ? 'Global' : $f[4];   # FHEM-Modulname
  $file[5] = $f[5];                                   # Dateiendung

  # Später ergänzt:
  #   $file[6] - Array mit Dateisystem-Infos
  #   $file[7] - Quelle der Version
  #   $file[8] - extrahierte Version, evtl. undef

  return \@file;
}

# Liest die Datei einmal durch und sammelt alles, was später gebraucht wird
sub __ScanSourceFile {
  my ($filePath) = @_;
  my %src = (json => {});

  open(my $fh, '<', $filePath) or return \%src;

  # Dateistatistik mit aufgeschlüsselten Zeiten
  if(my $st = stat($fh)) {
    my @stat = @{$st};
    
    for my $i (8, 9, 10) {
      my @t = FmtDateTime($stat[$i]) =~ m/^(((....)-(..)-(..)) ((..):(..):(..)))$/;
      $stat[$i] = [ $stat[$i], @t ] if(@t);
    }
    
    $src{stat} = \@stat;
  }

  my $skip    = 1;                                    # 0 = innerhalb eines META.json-Blocks
  my $current = '';

  while(my $l = <$fh>) {
    next if($l =~ m/^\s*$/);

    # Innerhalb des META.json-Blocks nur Inhalt sammeln
    if (!$skip) {
      if ($l =~ m/^=end\s+:application\/json\;q=META\.json/i) {
        $skip = 1;
      }
      else {
        $src{json}{$current} .= $l;
      }
      next;
    }

    # VCS-Info aus $Id: extrahieren
    if (!$src{vcs} && $l =~ $reVcsId) {
      my @vcs = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16);
      
      if ($2 eq 'fhem.pl') {
        $vcs[2] = '-1';
        $vcs[3] = 'Global';
      }

      # [0] komplette Übereinstimmung, [1] Dateiname, [2] Ordnungsnummer, [3] Modulname,
      #   [4] Dateiendung, [5] SVN-Basisrevision, [6] Commit-Zeit, [7] Commit-Datum,
      #   [8..10] Jahr/Monat/Tag, [11] Uhrzeit, [12..14] Stunde/Minute/Sekunde,
      #   [15] SVN-Benutzer (KÖNNTE der Maintainer sein, falls nicht in MAINTAINER.txt)
      # Später ergänzt: [16] Commit-Unix-Zeitstempel
      $src{vcs} = \@vcs;
    }

    # Versionsangabe direkt im Quellcode (Legacy)
    elsif(!$src{version} && $l =~ $reVersionVar) {
      $src{version}     = __NormalizeVersion($2);
      $src{versionFrom} = 'source/1' if($src{version});
    }
    elsif(!$src{version} && $l =~ $reVersionHash) {
      $src{version}     = __NormalizeVersion($2);
      $src{versionFrom} = 'source/2' if($src{version});
    }

    # Einträge aus POD (Legacy), jeweils der erste gewinnt
    elsif(!$src{modsubtype} && $l =~ m/^=item\s+(device|helper|command)\s*$/i) {
      $src{modsubtype} = lc($1);
    }
    elsif(!$src{summaryDE} && $l =~ m/^=item\s+(summary_DE)\s+(.+)$/i) {
      $src{summaryDE} = ($src{encoding} && $src{encoding} eq 'utf8') ? encode_utf8($2) : $2;
    }
    elsif(!$src{summary} && $l =~ m/^=item\s+(summary)\s+(.+)$/i) {
      $src{summary} = ($src{encoding} && $src{encoding} eq 'utf8') ? encode_utf8($2) : $2;
    }
    elsif($l =~ m/^=encoding\s+(.+)/i) {
      return { error => '=encoding pod must occur only once' } if($src{encoding});
      $src{encoding} = lc($1);
      $src{encoding} = 'utf8' if($src{encoding} eq 'utf-8');                            # gängige Schreibweise
    }

    # META.json aus POD
    elsif($l =~ m/^=for\s+:application\/json;q=META\.json\s+([^\s\.]+\.[^\s\.]+)\s*$/i) {
      $skip                = 0;
      $current             = $1;
      $src{json}{$current} = '';
    }
  }

  # Keine Version gefunden? Dann noch den Kommentarkopf der Datei prüfen
  if (!%{$src{json}} && !$src{version}) {
    seek $fh, 0, 0;

    while (my $l = <$fh>) {
      next if($l =~ m/^\s*$/);

      # Nur bis zum Codebeginn suchen
      last if($l !~ m/^#/ && $l !~ m/^=[A-Za-z]+/i);

      # via "Version:"
      if ($l =~ $reHdrVersion) {
        $src{version}     = __NormalizeVersion($2);
        $src{versionFrom} = 'comment/1' if($src{version});
      }

      # via Changelog, es wird angenommen die neueste Version steht oben;
      #   kann Fehltreffer enthalten
      elsif($l =~ $reHdrChangelog) {
        my $extr = $2;

        # Fehltreffer herausfiltern, die eigentlich Datumsangaben sind
        next if($extr =~ m/^[0-9]{2}\.[0-9]{2}\.([0-9]{2})$/ && $1 ge 13);

        $src{version}     = __NormalizeVersion($extr);
        $src{versionFrom} = 'comment/2' if($src{version});
      }

      last if($src{version});
    }
  }

  close($fh);

  $src{encoding} = 'latin1' unless($src{encoding});
  $src{opened}   = 1;

  return \%src;
}

# Übernimmt die META.json-Angaben aus dem POD in die Metadaten
sub __ApplyMetaJson {
  my ($json, $encoding, $modMeta, $metaSection) = @_;

  my $decoder = __GetJsonDecoder() or return undef;
  my $fName   = $modMeta->{x_file}[2];

  for my $name (keys %{$json}) {
    next if($metaSection ? $name ne $metaSection : lc($name) ne lc($fName));

    my $text = $json->{$name};
    
    if ($encoding eq 'utf8') {
      $text = encode_utf8($text);
    }
    elsif ($encoding ne 'latin1') {
      Log (4, __PACKAGE__."::__GetMetadata: Encoding type $encoding is not supported, META.json of $fName ignored");
      next;
    }

    local $@;
    my $decoded = eval { $decoder->($text) };
    my $err     = $@;
    
    if ($err || ref($decoded) ne 'HASH') {
      $err ||= 'JSON object expected';
      return "$name: Error while parsing META.json: $err";
    }

    $modMeta->{$_} = $decoded->{$_} for(keys %{$decoded});
  }

  return undef;
}

# Ermittelt die Abhängigkeiten per Perl::PrereqScanner::NotQuiteLite
sub __ScanPrereqs {
  my ($filePath, $modMeta) = @_;

  my $sc = __GetScanner() or return;

  my $context = $sc->scan_file($filePath);
  my %found   = (
    requires   => $context->requires,
    recommends => $context->recommends,
    suggests   => $context->suggests,                 # Abhängigkeiten in evals
  );

  $modMeta->{x_prereqs_src} = 'scanner';

  for my $prio (@prereqPrios) {
    my $req = $found{$prio}->{requirements};
    for my $pkg (keys %{$req}) {
      my $min = $req->{$pkg}{minimum};
      $modMeta->{prereqs}{runtime}{$prio}{$pkg} = (defined($min) && defined($min->{original})) ? $min->{original} : 0;
    }
  }
}

# Pflegt den Abhängigkeitsindex und übernimmt indirekte Abhängigkeiten von FHEM-Paketen.
#   Meta.pm selbst geht nicht tiefer, die manuellen Prereqs von Meta.pm müssen das abdecken.
sub __ProcessPackagePrereqs {
  my ($modName, $modMeta) = @_;
  return if(!defined($modMeta->{prereqs}) || !defined($modMeta->{prereqs}{runtime}));

  my $runtime = $modMeta->{prereqs}{runtime};

  for my $prio (@prereqPrios) {
    next unless(defined($runtime->{$prio}));

    for my $pkg (keys %{$runtime->{$prio}}) {

      # Index: Pakete -> FHEM-Module/Pakete
      __PushUnique(\@{$dependents{pkgs}{$pkg}{$prio}}, $modName);

      # Liste der Abhängigen (nur externe Module)
      my $known = grep { $_ eq $modName } @{$dependents{$prio}{$pkg} // []};
      push @{$dependents{$prio}{$pkg}}, $modName if(!$known && !ModuleIsInternal($pkg));

      # Abhängigkeit ist ein FHEM-Paket
      if(exists($packages{$pkg})) {
        Load($pkg);
        __InheritPrereqs($modMeta, $pkg);
      }
    }
  }
}

# Übernimmt die Abhängigkeiten des FHEM-Pakets $pkg in das Modul
sub __InheritPrereqs {
  my ($modMeta, $pkg) = @_;

  return unless(ref($packages{$pkg}) eq 'HASH' && defined($packages{$pkg}{META}));
  my $pkgMeta = $packages{$pkg}{META};
  return unless(defined($pkgMeta->{prereqs}) && defined($pkgMeta->{prereqs}{runtime}));

  my $runtime = $modMeta->{prereqs}{runtime};
  my $pkgRt   = $pkgMeta->{prereqs}{runtime};

  for my $prio (@prereqPrios) {
    next unless(defined($pkgRt->{$prio}));

    for my $dep (keys %{$pkgRt->{$prio}}) {
      next if(ModuleIsPerlCore($dep) && $dep ne 'perl');

      # Den Perl-Scanner nicht erben, wenn der Autor META.json bereitstellt
      next if($pkg eq 'Meta' && $dep eq 'Perl::PrereqScanner::NotQuiteLite'
        && defined($modMeta->{x_prereqs_src}) && $modMeta->{x_prereqs_src} eq 'META.json');

      my $target = $prio;                             # Zielpriorität
      my $v;                                          # übernommene Version eines bestehenden Eintrags

      # Doppelte Einträge mit anderer Priorität vermeiden
      if ($prio eq 'requires') {
        for my $lower (qw(recommends suggests)) {
          next unless(exists($runtime->{$lower}{$dep}));
          $v = $runtime->{$lower}{$dep};              # Versionsangabe behalten
          delete $runtime->{$lower}{$dep};
          last;
        }
      }
      elsif ($prio eq 'recommends') {
        if (exists($runtime->{requires}{$dep})) {
          $target = 'requires';                       # höhere Priorität
        }
        elsif (exists($runtime->{suggests}{$dep})) {
          $v = $runtime->{suggests}{$dep};
          delete $runtime->{suggests}{$dep};
        }
      }
      else {
        if (exists($runtime->{requires}{$dep})) {
          $target = 'requires';
        }
        elsif (exists($runtime->{recommends}{$dep})) {
          $target = 'recommends';
        }
      }

      if(defined($v)) {
        my $inherited = version->parse($pkgRt->{$prio}{$dep})->numify;
        $v            = version->parse($v)->numify;
        $v            = $inherited if($v < $inherited);
      }

      my $pkgVersion = $pkgRt->{$prio}{$dep};
      my $isNew      = !exists($runtime->{$target}) || !exists($runtime->{$target}{$dep});
      
      if ($isNew || (defined($pkgVersion) && $pkgVersion ne '0' && $v
          && version->parse($runtime->{$target}{$dep})->numify < $v)) {
        
        $runtime->{$target}{$dep} = ($isNew && !defined($v)) ? $pkgVersion : $v;        # Neuer Eintrag ohne bestehende Versionsangabe: Version des Pakets übernehmen    
        push @{$runtime->{x_inherited}{$dep}}, $pkg;                                    # Merken, dass von einem anderen Paket geerbt wurde
      }
    }
  }
}

# Registriert einen "acting maintainer" für Module/Pakete ohne Eintrag in MAINTAINER.txt
sub __AddActingMaintainer {
  my ($modName, $modMeta, $modType) = @_;
  my $file = $modMeta->{x_file};

  Log (4, __PACKAGE__."::__GetMetadata WARNING: Unregistered core module or package:\n  "
                    .$file->[0]." has defined VCS data but is not registered in MAINTAINER.txt.\n  "
                    ."Added acting maintainer with limited support status");

  my ($registry, $key) = $modType eq 'mod'
    ? (\%moduleMaintainers,  'modules')
    : (\%packageMaintainers, 'packages');

  $registry->{$modName} = [
    [ @{$file}[0 .. 3], $modName, $file->[5] ],
    'rudolfkoenig (acting)',
    'limited',
    __GetSupportForum('Sonstiges'),
  ];

  # Acting Maintainer und letzten Committer in den Maintainer-Index eintragen
  for my $editor ('rudolfkoenig (acting)', $modMeta->{x_vcs}[15]) {
    __PushUnique(\@{$maintainers{$editor}{$key}}, $modName, 1);
  }
}

# Extrahiert Metadaten aus einer FHEM-Moduldatei
sub __GetMetadata {
  return 0 unless(__PACKAGE__ eq caller(0));
  my ($filePath, $modMeta, $runInLoop, $metaSection) = @_;
  my $err = '';

  # Statische Meta-Informationen
  $modMeta->{dynamic_config} = 1;
  $modMeta->{'meta-spec'}    = {
    version => 2,
    url     => 'https://metacpan.org/pod/CPAN::Meta::Spec',
  };

  # Alles Mögliche aus dem Dateinamen extrahieren
  my $file = __ParseFilePath($filePath) or return "$filePath: Unable to parse file name";
  $modMeta->{x_file} = $file;

  my $modName = $file->[4];
  my $modType = ($file->[3] || $file->[2] eq 'fhem.pl') ? 'mod' : 'pkg';
  my $origin  = GetModuleSourceOrigin($modName);

  # Dateiinhalt auswerten
  my $src = __ScanSourceFile($filePath);
  return $src->{error} if($src->{error});

  $file->[6] = $src->{stat} // [];

  my $version     = $src->{version};
  my $versionFrom = $src->{versionFrom};
  my @vcs         = @{$src->{vcs} // []};

  # META.json aus dem POD
  if(%{$src->{json}}) {
    my $jsonErr = __ApplyMetaJson($src->{json}, $src->{encoding}, $modMeta, $metaSection);
    return $jsonErr if($jsonErr);
    return undef    if($metaSection);
  }

  # Für fhem.pl liegt die Meta-Information in dieser Moduldatei
  elsif($file->[2] eq 'fhem.pl') {
    my %fhempl;
    __GetMetadata(__FILE__, \%fhempl, undef, 'fhem.pl');
    delete $fhempl{x_file};
    $modMeta->{$_} = $fhempl{$_} for(keys %fhempl);
  }

  # Abhängigkeiten ermitteln, falls nicht per META.json angegeben
  if(!defined($modMeta->{prereqs})) {
    __ScanPrereqs($filePath, $modMeta) if($src->{opened});
  }
  else {
    $modMeta->{x_prereqs_src} = 'META.json';
  }

  # Abhängigkeiten zu FHEM-Paketen
  __ProcessPackagePrereqs($modName, $modMeta) if($modName ne 'Meta');

  # Weitere Informationen zu fhem.pl
  if($file->[2] eq 'fhem.pl') {
    $versionFrom = 'attr/featurelevel+vcs';
    if(($modules{Global}{AttrList} // '') =~ m/\W*featurelevel:(([0-9])\.([0-9]))/) {
      $version = version->parse($2.'.'.$3.'.'.($vcs[5] // 0))->numify;
    }
    $modMeta->{version} = $version;
  }

  ########
  # Metadaten-Aufbereitung beginnt hier
  #

  #TODO
  # - VCS-Daten gegen Update-Daten prüfen
  # - Abhängigkeiten für von FHEM-Modulen geladene Module ermitteln

  # VCS-Info unverändert übernehmen, aber nur wenn der Dateiname passt
  if (@vcs && $vcs[1] eq $file->[2]) {
    push @vcs, fhemTimeGm($vcs[14], $vcs[13], $vcs[12], $vcs[10], ($vcs[9] - 1), ($vcs[8] - 1900));
    $modMeta->{x_vcs} = \@vcs;

    # Gibt es keinen Maintainer, wird ein "acting" Maintainer eingesetzt
    if (!defined($moduleMaintainers{$modName}) && !defined($packageMaintainers{$modName})
      && $origin ne '' && $modName ne 'Meta') {
      __AddActingMaintainer($modName, $modMeta, $modType);
    }
  }

  # Version bestimmen
  if(defined($modMeta->{version})) {
    $versionFrom ||= 'META.json';                     # Autor hat die Version ins JSON geschrieben
  }
  elsif($version) {
    $modMeta->{version} = $version;                   # Version steht anderswo in der Datei
  }
  elsif(defined($modMeta->{x_vcs}) && $modMeta->{x_vcs}[5] ne '') {
    $versionFrom        = 'generated/vcs';
    $modMeta->{version} = '0.'.$modMeta->{x_vcs}[5];
  }
  else {                                              # gar keine Versionsangabe gefunden
    $versionFrom        = 'generated/blank';
    $modMeta->{version} = '0.000000001';
  }

  $file->[7] = $versionFrom;
  $file->[8] = $version;

  # Versionsnummer standardisieren
  $modMeta->{version} = version->parse($modMeta->{version})->numify;
  $err .= $file->[2].": Invalid version format '$modMeta->{version}'"
    if($modMeta->{version} !~ m/^[0-9]+\.[0-9]+(?:_[0-9]+)?$/);

  # Meta-Name
  $modMeta->{name} //= __BuildMetaName($modName, $file);

  $modMeta->{abstract} = $src->{summary}
    if($src->{summary} && !defined($modMeta->{abstract}));
  $modMeta->{x_lang}{de}{abstract} = $src->{summaryDE}
    if($src->{summaryDE} && !defined($modMeta->{x_lang}{de}{abstract}));

  # Nur wenn dieses Paket seine eigenen Metadaten liest.
  #   Bei anderen Modulen wird das aus Performancegründen anderswo ergänzt
  if($modMeta->{name} eq __PACKAGE__) {
    $modMeta->{generated_by} = $modMeta->{name}.' '.version->parse($modMeta->{version})->normal.', '.TimeNow();
  }
  elsif(!$runInLoop) {
    $modMeta->{generated_by} = __GeneratedBy(TimeNow());
  }

  # Pflichtangaben ergänzen
  $modMeta->{abstract}       //= $modType eq 'pkg'
    ? 'FHEM development package that is used by FHEM modules'
    : 'n/a';
  $modMeta->{description}    //= $modType eq 'pkg'
    ? 'This is a FHEM-included Perl package that does not show up as a '
      .'regular device in FHEM. \\n'
      .'That is because it provides additional functionality that can be used by real '
      .'FHEM modules in order to share the same code basis.'
    : 'n/a';
  $modMeta->{release_status} //= 'stable';
  $modMeta->{license}        //= ['unknown'];
  $modMeta->{author}         //= ['unknown <>'];

  # Sicherstellen, dass diese Felder Arrays sind
  __EnsureArray($modMeta, $_) for(qw(license author x_fhem_maintainer x_fhem_maintainer_github));
  __EnsureArray($modMeta->{resources}, 'license') if(defined($modMeta->{resources}));

  if($origin eq 'fhem') {
    __ApplyCoreDefaults($modName, $modMeta, $modType);
  }
  else {

    # Attribute, die exklusiv für FHEM Core sind
    delete $modMeta->{x_fhem_maintainer};
    delete $modMeta->{x_fhem_maintainer_github};
  }

  __ApplySupportStatus($modName, $modMeta);
  __BuildKeywords($modName, $modMeta, $modType, $origin, $src->{modsubtype});

  # x_version und x_release_date erzeugen
  __SetXVersion($modMeta);

  return $err ne '' ? $err : undef;
}

# Meta-Name aus Pfad und Modulname bilden
sub __BuildMetaName {
  my ($modName, $file) = @_;
  return 'FHEM' if($modName eq 'Global');

  my $name = $file->[1];
  $name    =~ s/^\.\///;
  $name    =~ s/\/$//;
  $name    =~ s/\//::/g;
  $name   .= '::' if($name);

  return $name.$modName;
}

# Splittet die Maintainer-Angabe aus MAINTAINER.txt
sub __SplitMaintainers {
  my ($maintainers) = @_;
  return split(m{[/,]}, $maintainers // '');
}

# Ergänzt Metadaten für FHEM-Core-Module aus VCS- und Maintainer-Daten
sub __ApplyCoreDefaults {
  my ($modName, $modMeta, $modType) = @_;
  my $vcs   = $modMeta->{x_vcs};
  my $file  = $modMeta->{x_file};
  my $maint = $moduleMaintainers{$modName} // $packageMaintainers{$modName};

  if(!$modMeta->{release_status} || $modMeta->{release_status} eq 'stable') {
    $modMeta->{release_status} = defined($vcs) ? 'stable' : 'unstable';
  }

  if(!$modMeta->{license} || (ref($modMeta->{license}) eq 'ARRAY' && $modMeta->{license}[0] eq 'unknown')) {
    $modMeta->{license}[0] = 'GPL_2' if(defined($vcs));
  }

  if(!$modMeta->{author} || $modMeta->{author}[0] eq 'unknown <>') {
    if($maint) {
      shift @{$modMeta->{author}} if($modMeta->{author} && $modMeta->{author}[0] eq 'unknown <>');
      push @{$modMeta->{author}}, "$_ <>" for(__SplitMaintainers($maint->[1]));

      # Letztes Update war nicht von einem der genannten Autoren
      if(defined($vcs)) {
        my $lastEditor = lc($vcs->[15].' <>');
        push @{$modMeta->{author}}, $vcs->[15].' (last release only) <>'
          unless(grep { lc($_) eq $lastEditor } @{$modMeta->{author}});
      }
    }
  }

  unless($modMeta->{x_fhem_maintainer}) {
    if($maint) {
      push @{$modMeta->{x_fhem_maintainer}}, __SplitMaintainers($maint->[1]);

      if(defined($vcs)) {
        my $lastEditor = lc($vcs->[15]);
        push @{$modMeta->{x_fhem_maintainer}}, $vcs->[15]
          unless(grep { lc($_) eq $lastEditor } @{$modMeta->{x_fhem_maintainer}});
      }
    }
  }

  # Die folgenden Angaben gibt es nur bei vorhandenen VCS-Daten
  return unless(defined($vcs));

  my $res = $modMeta->{resources} //= {};

  $res->{license} //= ['https://fhem.de/#License'];
  $res->{x_wiki}  //= { web => 'https://wiki.fhem.de/wiki/'.$modName };

  if($modType eq 'mod' && !defined($res->{x_commandref})) {
    $res->{x_commandref}{web} = 'https://commandref.fhem.de/#'.($modName eq 'Global' ? 'global' : $modName);
  }

  if(!defined($res->{x_support_community})) {
    for my $registry (\%moduleMaintainers, \%packageMaintainers) {
      my $m = $registry->{$modName};
      next unless(ref($m) eq 'ARRAY' && ref($m->[3]) eq 'HASH' && keys %{$m->[3]} > 0);

      $res->{x_support_community} = $m->[3];
      last;
    }
  }

  my $repo = $res->{repository};
  unless(ref($repo) && grep { defined($repo->{$_}) } qw(type url web x_branch x_filepath x_raw)) {
    my %repository = (
      type       => 'svn',
      url        => 'https://svn.fhem.de/fhem',
      web        => 'https://svn.fhem.de/trac/browser/trunk/fhem/'.$file->[1].$file->[2],
      x_branch   => 'trunk',
      x_filepath => 'fhem'.($file->[1] ne '' ? '/'.$file->[1] : ''),
      x_raw      => 'https://svn.fhem.de/trac/export/latest/trunk/fhem/'.$file->[1].$file->[2],
    );
    $res->{repository}{$_} = $repository{$_} for(keys %repository);
  }
}

# Support-Status aus MAINTAINER.txt-Daten oder Community-Angabe ableiten
sub __ApplySupportStatus {
  my ($modName, $modMeta) = @_;
  return if(defined($modMeta->{x_support_status}));

  for my $registry (\%moduleMaintainers, \%packageMaintainers) {
    my $m = $registry->{$modName};
    next unless(ref($m) eq 'ARRAY' && defined($m->[2]));

    $modMeta->{x_support_status} = $m->[2];
    return;
  }

  $modMeta->{x_support_status} =
    ($modMeta->{resources} && $modMeta->{resources}{x_support_community}) ? 'supported' : 'unknown';
}

# Schlüsselwörter ermitteln und im globalen Index ablegen
sub __BuildKeywords {
  my ($modName, $modMeta, $modType, $origin, $modSubType) = @_;

  # Für den FHEM Core reservierte Schlüsselwörter herausfiltern
  if(defined($modMeta->{keywords}) && @{$modMeta->{keywords}} > 0) {
    $modMeta->{keywords} = [ grep { !$reservedKeywords{$_} } map { lc($_) } @{$modMeta->{keywords}} ];
  }

  # Schlüsselwörter aus den Support-Daten erzeugen
  if(defined($modMeta->{resources}) && defined($modMeta->{resources}{x_support_community})
    && $modMeta->{x_file}[2] ne 'fhem.pl') {
    for my $keyword (__GenerateKeywordsFromSupportCommunity($modMeta->{resources}{x_support_community})) {
      __PushUnique(\@{$modMeta->{keywords}}, $keyword, 1);
    }
  }

  push @{$modMeta->{keywords}}, "fhem-$modType-commercial"
    if(defined($modMeta->{resources}) && defined($modMeta->{resources}{x_support_commercial}));

  # Legacy-POD-Info als Metadaten ergänzen
  __PushUnique(\@{$modMeta->{keywords}}, $modSubType ? "fhem-$modType-$modSubType" : "fhem-$modType", 1);

  # Schlüsselwörter zur Herkunft des Moduls
  if($origin eq 'fhem') {
    push @{$modMeta->{keywords}}, 'fhem-core';
  }
  elsif($origin ne '') {
    push @{$modMeta->{keywords}}, "fhem-$modType-3rdparty";
  }
  else {
    push @{$modMeta->{keywords}}, "fhem-$modType-local";
  }

  # Schlüsselwörter in den globalen Index aufnehmen
  my $key = $modType eq 'mod' ? 'modules' : 'packages';
  __PushUnique(\@{$keywords{$_}{$key}}, $modName, 1) for(@{$modMeta->{keywords}});
}

sub __AddKeywordDesc {
  my ($tag, $desc) = @_;
  return if($desc eq '');
  return if(ref($keywordDescription{$tag}) eq 'HASH' && defined($keywordDescription{$tag}{de}));

  $keywordDescription{$tag}{de} = $desc;
}

sub __GenerateKeywordsFromSupportCommunity {
  my ($community) = @_;
  my @keywords;
  return @keywords if(ref($community) ne 'HASH');

  my $sub     = ref($community->{subCommunity}) eq 'HASH' ? $community->{subCommunity} : {};
  my $subDesc = $sub->{description} // $community->{description} // '';

  if(defined($community->{board}) && $community->{board} ne '') {
    my $prefix = ($community->{cat} // '') =~ /^(\w+)/ ? lc($1).'-' : '';

    if(defined($sub->{board}) && $sub->{board} ne '') {
      my $parent = lc($community->{board});
      my $tag    = lc($sub->{board});

      $tag =~ s/\Q$parent\E\s+-\s+|\Q$parent\E\s+»\s+//g;
      $tag =~ s/ - |»/ /g;
      $tag =~ s/ +/-/g;

      for my $part (split '/', $tag) {
        my $t = (index($part, $prefix) == 0 ? '' : $prefix).$part;
        push @keywords, $t;
        __AddKeywordDesc($t, $subDesc);
      }
    }

    my $tag = lc($community->{board});
    $tag =~ s/ - |»/ /g;
    $tag =~ s/ +/-/g;

    for my $part (split '/', $tag) {
      my $t = (index($part, $prefix) == 0 ? '' : $prefix).$part;
      push @keywords, $t;
      __AddKeywordDesc($t, $subDesc);
    }
  }

  if(defined($community->{cat}) && $community->{cat} ne '' && $community->{cat} ne 'FHEM') {
    my $tag = lc($community->{cat});
    $tag =~ s/ - |»/ /g;
    $tag =~ s/ +/-/g;

    push @keywords, $tag;
    __AddKeywordDesc($tag, $community->{description} // '');
  }

  return @keywords;
}

# Initialisiert den globalen Hash %packages
sub __GetPackages {
  my $modPath = $attr{global}{modpath};

  for my $dir ($modPath, $modPath.'/FHEM/') {
    opendir(my $dh, $dir) or next;

    for my $fn (readdir($dh)) {
      next if($fn eq '.' || $fn eq '..' || -d $dir.'/'.$fn);

      my @f = $fn =~ $reFileName or next;
      next if($f[3] || !$f[5] || $f[5] ne 'pm');       # nur Dateien ohne Ordnungsnummer

      $packages{$f[4]} = undef unless(exists($packages{$f[4]}));
    }

    closedir($dh);
  }
}

# Liest MAINTAINER.txt ein
sub __GetMaintainerdata {
  return 0 unless(__PACKAGE__ eq caller(0));
  %moduleMaintainers  = ();
  %packageMaintainers = ();

  if (!open(my $fh, '<', $attr{global}{modpath}.'/MAINTAINER.txt')) {
    Log (1, __PACKAGE__."::__GetMaintainerdata ERROR: Unable to read MAINTAINER.txt:\n  $!");
    return 0;
  }
  else {
    my $started = 0;

    while(my $l = <$fh>) {
      if($l =~ m/^===+$/) {
        $started = 1;
        next;
      }
      next unless($started);

      my @line = map { s/^\s+//; s/\s+$//; $_ } split("[ \t][ \t]*", $l, 3);
      $line[$_] //= '' for(0 .. 2);

      my ($path, $dir, $fname, $order, $name, $ext) =
        $line[0] =~ m/^((.+\/)?((?:([0-9]+)_)?(.+?)(?:\.(.+))?))$/ or next;
      my $dirStr = $dir // '';
      my $extStr = $ext // '';

      # FHEM-Moduldatei, entweder in ./ oder ./FHEM/. Für Dateien in ./ muss die
      #   Dateiendung angegeben sein, Dateien in ./FHEM/ werden über die Ordnungsnummer erkannt.
      my $isModule = ((($dirStr eq '' || $dirStr eq './') && ($extStr eq 'pl' || $extStr eq 'pm'))
        || ($order && $dirStr eq 'FHEM/')) ? 1 : 0;

      # FHEM Perl-Paket unter ./FHEM/, das von FHEM-Modulen genutzt wird.
      #   Pakete müssen hier die Dateiendung angeben.
      my $isPackage = (!$isModule && $dirStr eq 'FHEM/' && $extStr eq 'pm') ? 1 : 0;

      # Alle anderen FHEM-Dateien (unter beliebigem Pfad) werden nicht ausgewertet
      next unless($isModule || $isPackage);

      # Hinweis: Dateien in ./ (z.B. fhem.pl) landen in %moduleMaintainers,
      #   Schlüsselwörter werden dort aber unter "packages" geführt
      my $type = $order ? 'module' : 'package';

      if (!-f $path && !-f $path.'.pm') {
        Log (4, __PACKAGE__."::__GetMaintainerdata ERROR: Orphan $type entry:\n  ".join(' ', @line));
        next;
      }

      my $modName    = $fname eq 'fhem.pl' ? 'Global' : $name;
      my $deprecated = $line[2] =~ m/\(deprecated\)/i ? 1 : 0;

      my @maintainer = (
        [ $path, $dir, $fname, $order, $modName, $ext ],
        $line[1],                                     # Maintainer-Alias
        $deprecated ? 'deprecated' : 'supported',     # Lebenszyklus-Status
      );

      $line[2] =~ s/\s*\(.*\)\s*$//;                  # alle Kommentare entfernen
      $maintainer[3] = $deprecated ? undef : __GetSupportForum($line[2]);    # Forum-Bereich

      my $registry = $isModule ? \%moduleMaintainers : \%packageMaintainers;
      if (defined($registry->{$modName})) {
        Log (1, __PACKAGE__."::__GetMaintainerdata ERROR: Duplicate $type entry:\n"
          .'  1st: '.$registry->{$modName}[0][0].' '.$registry->{$modName}[1].' '.$registry->{$modName}[2]
          ."\n  2nd: ".join(' ', @line));
        next;
      }

      # Im globalen Modul-/Paketindex registrieren
      $registry->{$modName} = \@maintainer;

      # Im globalen Maintainer-Index registrieren
      my $key = $isModule ? 'modules' : 'packages';
      __PushUnique(\@{$maintainers{$_}{$key}}, $modName) for(__SplitMaintainers($maintainer[1]));

      # Schlüsselwörter für den globalen Index erzeugen
      my $kwKey = $order ? 'modules' : 'packages';
      for my $keyword (__GenerateKeywordsFromSupportCommunity($maintainer[3])) {
        __PushUnique(\@{$keywords{$keyword}{$kwKey}}, $modName, 1);
      }
    }

    close($fh);
  }
}

# Sucht ein Forum-Board anhand des Namens (wie in MAINTAINER.txt angegeben)
sub __FindForumBoard {
  my ($req, $ret) = @_;

  for my $cat (sort keys %supportForumCategories) {
    my $boards = $supportForumCategories{$cat};

    for my $board (sort keys %{$boards}) {
      next if($board eq 'boardId' || $board eq 'description' || $board eq 'language');
      my $boardData = $boards->{$board};

      # Hauptboard gefunden
      if(lc($board) eq lc($req)) {
        next unless(defined($boardData->{boardId}));

        $ret->{cat}         = $cat;
        $ret->{board}       = $board;
        $ret->{boardId}     = $boardData->{boardId};
        $ret->{description} = $boardData->{description} if(defined($boardData->{description}));
        $ret->{language}    = $boardData->{language}    if(defined($boardData->{language}));
        last;
      }

      # Ist es ein Unterboard?
      for my $subBoard (sort keys %{$boardData}) {
        next if($subBoard eq 'boardId' || $subBoard eq 'description' || $subBoard eq 'language');

        my $reqSub = $req;
        if($reqSub =~ /^\Q$board\E\/(.+)/) {
          $reqSub = $1;
          $reqSub =~ s/ /\//g;                        # justme1968 special ;D)
        }

        next unless(lc($subBoard) eq lc($reqSub));
        next unless(defined($boardData->{$subBoard}{boardId}));

        $ret->{cat}         = $cat;
        $ret->{board}       = $board;
        $ret->{boardId}     = $boardData->{boardId};
        $ret->{description} = $boardData->{description} if(defined($boardData->{description}));
        $ret->{language}    = $boardData->{language}    if(defined($boardData->{language}));

        my $sub = $boardData->{$subBoard};
        $ret->{subCommunity}{board}       = $board.' » '.$subBoard;
        $ret->{subCommunity}{boardId}     = $sub->{boardId};
        $ret->{subCommunity}{description} = $sub->{description} if(defined($sub->{description}));
        $ret->{subCommunity}{language}    = $sub->{language}    if(defined($sub->{language}));
        last;
      }
    }

    last if(defined($ret->{boardId}));
  }
}

# Erzeugt Titel, Web- und RSS-Link für einen Forumbereich
sub __SetForumLinks {
  my ($ret, $boardId, $board) = @_;

  $ret->{title} = $supportForum{forum}.': '.$board;
  $ret->{web}   = $supportForum{url}.$supportForum{uri};
  $ret->{rss}   = $supportForum{url}.$supportForum{rss}.';board=%BOARDID%';
  $ret->{web}   =~ s/%BOARDID%/$boardId/;
  $ret->{rss}   =~ s/%BOARDID%/$boardId/;
}

sub __GetSupportForum {
  return 0 unless(__PACKAGE__ eq caller(0));
  my ($req) = @_;
  my %ret;

  if ($req =~ /^http/) {
    $ret{web}   = $req;
    $ret{title} = $1 if($req =~ m/^.+:\/\/([^\/]+).*/ && $1 !~ /fhem\.de$/);
    return \%ret;
  }

  # Umlaute, Schreibweise "ae" -> "ä" usw. (außer bei "...uerung")
  my %umlauteRev = (
    ae => 'ä', Ae => 'Ä',
    ue => 'ü', Ue => 'Ü',
    oe => 'ö', Oe => 'Ö',
  );
  my $umlautRevKeys = join('|', keys %umlauteRev);
  $req              =~ s/($umlautRevKeys)/$umlauteRev{$1}/g unless($req =~ /uerung/);

  __FindForumBoard($req, \%ret);

  $ret{forum} = $supportForum{forum};
  $ret{title} = $supportForum{forum};
  $ret{web}   = $supportForum{url};
  $ret{rss}   = $supportForum{url}.$supportForum{rss};

  if (defined($ret{boardId})) {
    $ret{language} //= $supportForum{default_language};                             # Sprache des Boards, sonst Standard
    __SetForumLinks(\%ret, $ret{boardId}, $ret{board});

    if (defined($ret{subCommunity}) && defined($ret{subCommunity}{boardId})) {
      my $sub            = $ret{subCommunity};
      $sub->{language} //= $supportForum{default_language};
      __SetForumLinks($sub, $sub->{boardId}, $sub->{board});
    }
  }
  else {
    $ret{web} .= '/';
  }

  return \%ret;
}

# Erzeugt aus einer Zeile von controls_*.txt einen Update-Eintrag (undef bei ungültigem Datum)
sub __BuildUpdateEntry {
  my ($srcRepo, $m, $file, $line) = @_;

  # [0] Quell-Repository, [1] komplette Übereinstimmung, [2] Steuerbefehl, [3] Datum und Uhrzeit,
  #   [4] Datum, [5..7] Jahr/Monat/Tag, [8] Uhrzeit, [9..11] Stunde/Minute/Sekunde,
  #   [12] Größe in Bytes, [13] relativer Dateipfad, [14] relativer Pfad, [15] Dateiname,
  #   [16] Ordnungsnummer (evtl. undef), [17] FHEM-Modulname, [18] Dateiendung
  my @update = ($srcRepo, @{$m}[0, 1], $m->[3].' '.$m->[7], @{$m}[3 .. 17]);

  unless ($update[11] >= 0 && $update[11] <= 59 && $update[10] >= 0 && $update[10] <= 59
    && $update[9] >= 0 && $update[9] <= 23 && $update[7] >= 0 && $update[7] <= 31
    && $update[6] >= 1 && $update[6] <= 12 && $update[5] > 0) {
    Log (1, __PACKAGE__."::__GetUpdatedata: ERROR: Invalid datetime range in $file:\n  ".$line);
    return undef;
  }

  # [19] Unix-Zeitstempel
  push @update, fhemTimeGm($update[11], $update[10], $update[9], $update[7], ($update[6] - 1), ($update[5] - 1900));

  return \@update;
}

# Liest die Update-Steuerdateien (controls_*.txt) ein
sub __GetUpdatedata {
  return 0 unless(__PACKAGE__ eq caller(0));
  $coreUpdate         = undef;
  %corePackageUpdates = ();
  %coreFileUpdates    = ();
  %moduleUpdates      = ();
  %packageUpdates     = ();
  %fileUpdates        = ();

  my $modPath = $attr{global}{modpath};
  my @fileList;

  # Sind Quell-Repositories von Drittanbietern beteiligt?
  if (open(my $fh, '<', $modPath.'/FHEM/controls.txt')) {
    while(my $l = <$fh>) {
      push @fileList, 'FHEM/'.$1 if($l =~ m/([^\/\s]+)$/);
    }
    
    close($fh);
  }

  # Nur die Update-Steuerdatei des FHEM Core
  else {
    push @fileList, 'controls_fhem.txt';
  }

  for my $file (@fileList) {
    open(my $fh, '<', $modPath.'/'.$file) or next;

    my ($srcRepoName) = $file =~ m/^[^_\s\.]+_([^_\s\.]+)\.[^_\s\.]+$/;
    $srcRepoName //= '';

    while (my $l = <$fh>) {
      my @m = $l =~ $reControlsLine or next;
      next unless($m[1] eq 'UPD');

      # Datei unter ./ (FHEM Core)
      if (!$m[13]) {

        # Core-Updates dürfen nur aus dem originalen FHEM-Quell-Repository stammen
        if ($srcRepoName ne 'fhem') {
          Log (1, __PACKAGE__."::__GetUpdatedata: ERROR: Core file '".$m[12]
            ."' can only be updated from FHEM original update server");
          next;
        }

        my $update = __BuildUpdateEntry($srcRepoName, \@m, $file, $l) or next;

        if ($m[14] eq 'fhem.pl') {
          $coreUpdate = $update;
        }
        elsif ($m[17] eq 'pm') {
          $corePackageUpdates{$m[16]} = $update;
        }

        # sonstige Core-Dateien: %coreFileUpdates wird nicht befüllt
      }

      # FHEM-Modul oder Perl-Paket unter ./FHEM/
      elsif ($m[13] eq 'FHEM/' && $m[17] eq 'pm') {
        my $update = __BuildUpdateEntry($srcRepoName, \@m, $file, $l) or next;

        my $store = $m[15] ? \%moduleUpdates : \%packageUpdates;
        my $name  = $m[16];

        # Update-Info wird nicht überschrieben, wenn der Name des Quell-Repositorys nicht passt
        if (ref($store->{$name}) eq 'ARRAY' && $store->{$name}[0] ne $update->[0]) {
          Log (1, __PACKAGE__."::__GetUpdatedata: ERROR: ".$update->[13]
            .' belongs to source repository "'.$store->{$name}[0]
            .'". Ignoring identical file name from source repository '.$update->[0]);
          next;
        }

        $store->{$name} = $update;
      }

      # sonstige Dateien unter beliebigem Pfad: %fileUpdates wird nicht befüllt
    }

    close($fh);
  }
}

# x_version anhand der vorhandenen Metadaten setzen
sub __SetXVersion {
  return 0 unless(__PACKAGE__ eq caller(0));
  my ($modMeta) = @_;
  my $file      = $modMeta->{x_file};
  my $vcs       = $modMeta->{x_vcs};

  delete $modMeta->{x_version};

  # Sonderbehandlung für fhem.pl
  if ($file->[2] eq 'fhem.pl') {                                                    # nur maximalen Featurelevel zeigen und Revision separat anhängen
    $modMeta->{x_version} = 'fhem.pl:'.$1.'-s'.($vcs ? $vcs->[5] : '')
      if(version->parse($modMeta->{version})->normal =~ m/^(v[0-9]+\.[0-9]+).*/);
  }
  elsif (defined($vcs)) {                                                           # Erweiterte Versionsangabe anhand der Basisrevision erzeugen
    my $fromVcs = $file->[7] eq 'generated/vcs';

    $modMeta->{x_version} = $file->[2].':'
      .($modMeta->{version} <= 0.000000001 ? '?'
        : (!$fromVcs ? version->parse($modMeta->{version})->normal : $modMeta->{version}))
      .(!$fromVcs && $vcs->[5] ne '' ? '-s'.$vcs->[5] : '');                        # es wird nur Subversion angenommen
  }
  elsif(defined($file->[7]) && $file->[7] eq 'generated/blank') {                   # Generische Version, um die Lücke zu füllen
    $modMeta->{x_version} = $file->[2].':?';
  }

  if (defined($modMeta->{x_version})) {

    # Änderungsdatum zur erweiterten Version
    if (defined($vcs) && defined($vcs->[7])) {
      $modMeta->{x_version} .= '/'.$vcs->[7];
    }
    elsif (defined($file->[6]) && defined($file->[6][9]) && defined($file->[6][9][2])) {
      $modMeta->{x_version} .= '/'.$file->[6][9][2];
    }

    # Release-Status anhängen wenn != stable
    $modMeta->{x_version} .= ' '.uc($modMeta->{release_status})
      if(defined($modMeta->{release_status}) && $modMeta->{release_status} ne 'stable');
  }

  # x_release_date
  $modMeta->{x_release_date} //= $vcs->[7] if(defined($vcs));
}

1;

=pod

=encoding utf8

=for :application/json;q=META.json Meta.pm
{
  "abstract": "FHEM development package to enable Metadata support",
  "x_lang": {
    "de": {
      "abstract": "FHEM Entwicklerpaket, um Metadaten Unterstützung zu aktivieren"
    }
  },
  "version": "v1.0.0",
  "release_status": "stable",
  "x_changelog": {
    "v0.6.0": {
      "date": "2019-04-18",
      "changes": [
        "improved JSON dependencies"
      ]
    },
    "v0.5.0": {
      "date": "2019-04-16",
      "changes": [
        "use Module::CoreList to identify Perl Core modules"
      ]
    },
    "v0.4.2": {
      "date": "2019-04-12",
      "release_notes": [
        ""
      ],
      "upgrade_notes": [
        ""
      ],
      "bugfixes": [
        ""
      ],
      "changes": [
        ""
      ],
      "new_features": [
        ""
      ]
    }
  },
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>",
    "Heiko Maaz <Heiko.Maaz@t-online.de>"  
  ],
  "x_fhem_maintainer": [
    "",
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "DS_Starter"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918623,
        "perl": 5.014,
        "GPUtils": 0,
        "File::stat": 0,
        "Encode": 0,
        "version": 0,
        "JSON::PP": 0
      },
      "recommends": {
        "JSON": "2.92",
        "Module::CoreList": 0,
        "Perl::PrereqScanner::NotQuiteLite": 0
      },
      "suggests": {
        "JSON::XS": 0,
        "Cpanel::JSON::XS": 0
      }
    }
  },
  "x_prereqs_os": {
    "runtime": {
      "requires": {
      },
      "recommends": {
        "debian|ubuntu": 0
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os_debian": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os_ubuntu": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_binary_exec": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_sudo": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_permissions_fileown": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_permissions_filemod": {
    "runtime": {
      "requires": {
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=for :application/json;q=META.json fhem.pl
{
  "abstract": "FHEM® is a Perl server for house automation",
  "description": "FHEM® (registered trademark) is a GPL'd Perl server for house automation. It is used to automate some common tasks in the household like switching lamps / shutters / heating / etc. and to log events like temperature / humidity / power consumption.\\nThe program runs as a server, you can control it via web or smartphone frontends, telnet or TCP/IP directly.\\nIn order to use FHEM you'll need a 24/7 server (NAS, RPi, PC, Mac Mini, etc.) with a Perl interpreter and some attached hardware like the CUL-, EnOcean-, Z-Wave-USB-Stick, etc. to access the actors and sensors.\\nIt is pronounced without the h, like in feminine.",
  "x_lang": {
    "de": {
      "abstract": "FHEM® ist ein Perl Server zur Hausautomatisierung",
      "description": "FHEM® (eingetragene Marke) ist ein in Perl geschriebener, GPL lizensierter Server für die Heimautomatisierung. Man kann mit FHEM häufig auftretende Aufgaben automatisieren, wie z.Bsp. Lampen / Rollladen / Heizung / usw. schalten, oder Ereignisse wie Temperatur / Feuchtigkeit / Stromverbrauch protokollieren und visualisieren.\\nDas Programm läuft als Server, man kann es über WEB, dedizierte Smartphone Apps oder telnet bedienen, TCP Schnittstellen für JSON und XML existieren ebenfalls.\\nUm es zu verwenden benötigt man einen 24/7 Rechner (NAS, RPi, PC, Mac Mini, etc.) mit einem Perl Interpreter und angeschlossene Hardware-Komponenten wie CUL-, EnOcean-, Z-Wave-USB-Stick, etc. für einen Zugang zu den Aktoren und Sensoren.\\nAusgesprochen wird es ohne h, wie bei feminin."
    }
  },
  "resources": {
    "homepage": "https://fhem.de/"
  },
  "prereqs": {
    "runtime": {
      "requires": {
        "perl": 5.006002,
        "constant": 0,
        "File::Copy": 0,
        "IO::Socket": 0,
        "IO::Socket::INET": 0,
        "lib": 0,
        "Math::Trig": 0,
        "POSIX": 0,
        "RTypes": 0,
        "Scalar::Util": 0,
        "strict": 0,
        "Time::HiRes": 0,
        "vars": 0,
        "warnings": 0
      },
      "recommends": {
        "Compress::Zlib": 0,
        "IO::Socket::INET6": 0,
        "Socket6": 0,
        "TimeSeries": 0
      }
    }
  },
  "x_prereqs_os_debian": {
    "runtime": {
      "requires": {
        "perl-base": ">= 5.6.2",
        "sqlite3": 0,
        "libcgi-pm-perl": 0,
        "libdbd-sqlite3-perl": 0,
        "libdevice-serialport-perl": ">= 1.0",
        "libio-socket-ssl-perl": ">= 1.0",
        "libjson-perl": 0,
        "libtext-diff-perl": 0,
        "libwww-perl": ">= 1.0"
      },
      "recommends": {
        "ttf-liberation": 0,
        "libarchive-extract-perl": 0,
        "libarchive-zip-perl": 0,
        "libgd-graph-perl": 0,
        "libgd-text-perl": 0,
        "libimage-info-perl": 0,
        "libimage-librsvg-perl": 0,
        "libio-socket-inet6-perl": 0,
        "liblist-moreutils-perl": 0,
        "libmail-imapclient-perl": 0,
        "libmime-base64-perl": 0,
        "libnet-server-perl": 0,
        "libsocket6-perl": 0,
        "libtext-csv-perl": 0,
        "libtimedate-perl": 0,
        "libusb-1.0-0-dev": 0,
        "libxml-simple-perl": 0
      },
      "suggests": {
      }
    }
  }
}

=end :application/json;q=META.json

=cut
