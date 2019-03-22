# $Id$

package main;
use strict;
use warnings;

# provide the same hash as for real FHEM modules
#   in FHEM main context
use vars qw(%packages);

# define package
package FHEM::Meta;
use strict;
use warnings;

use GPUtils qw(GP_Import);
use File::stat;
use Encode;
use Data::Dumper;

# Run before module compilation
BEGIN {

    # Import from main::
    GP_Import(
        qw(
          modules
          packages
          defs
          attr
          Log
          Debug
          devspec2array
          genUUID
          TimeNow
          FmtDateTime
          fhemTimeGm
          )
    );
}

# Exported variables
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
            description =>
'Kommentare, Korrekturvorschläge, Anregungen zu Artikeln im FHEM Wiki',
            boardId => 80,
        },
        'Termine und Veranstaltungen' => {
            description =>
'Interessante Termine zu Messen oder sonstigen Veranstaltungen wie z.B. "FHEM Stammtische"',
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
        'Ankündigungen' => => {
            description => 'Ankündigungen und Hinweise zu FHEM',
            boardId     => 40,
        },
        'Anfängerfragen' => => {
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
            description =>
'Anwendungen rund um Heizkörper, Heizungsanlagen, Thermen, Wärme, Raumtemperatur, Belüftung, etc.',
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
            description =>
'Projekte für Bastler, die gerne auch mal zum Lötkolben greifen',
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
            description =>
'Vorstellung von größeren Projekten die mit FHEM realisiert wurden',
            boardId => 50,
        },
        'User stellen sich vor' => {
            description => 'Das "Who is Who" von FHEM',
            boardId     => 7,
        },
    }
);

our %maintainers;           # maintainers and what they maintain
our %moduleMaintainers;     # modules and who maintains them
our %packageMaintainers;    # packages and who maintains them
our %fileMaintainers;       # files and who maintains them

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
        'en' =>
'FHEM module that originates from a source outside of the official FHEM core software',
        'de' =>
'FHEM Modul, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-pkg-3rdparty' => {
        'en' =>
'FHEM development package that originates from a source outside of the official FHEM core software',
        'de' =>
'FHEM Entwickler Paket, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-mod-commercial' => {
        'en' =>
'commercial FHEM module that originates from a source outside of the official FHEM core software',
        'de' =>
'kommerzielles FHEM Modul, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-pkg-commercial' => {
        'en' =>
'commercial FHEM development package that originates from a source outside of the official FHEM core software',
        'de' =>
'kommerzielles FHEM Entwickler Paket, welches aus einer Quelle außerhalb des offiziellen Kern von FHEM stammt',
    },
    'fhem-mod-local' => {
        'en' => 'FHEM module that is maintained locally on the machine',
        'de' => 'FHEM Modul, welches lokal auf der Maschine verwaltet wird',
    },
    'fhem-pkg-local' => {
        'en' =>
          'FHEM development package that is maintained locally on the machine',
        'de' =>
'FHEM Entwickler Paket, welches lokal auf der Maschine verwaltet wird',
    },
    'fhem-mod-command' => {
        'en' => 'FHEM console text command w/o any FHEM device object visible',
        'de' =>
          'FHEM Konsolen Text Kommando ohne sichtbares FHEM Geräte-Objekt',
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

# Package internal variables
#

# based on https://metacpan.org/release/perl
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
#   and https://metacpan.org/pod/Win32#Alphabetical-Listing-of-Win32-Functions
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

# Initialize global hash %packages
__GetPackages() unless ( keys %packages > 0 );

#TODO this shall be handled by InitMod()
# Get our own Metadata
my %META;
my $ret = __GetMetadata( __FILE__, \%META );
return "$@" if ($@);
return $ret if ($ret);
$packages{Meta}{META} = \%META;
use version 0.77; our $VERSION = $packages{Meta}{META}{version};

# Initially load information
#   to be ready for meta analysis
__GetUpdatedata() unless ( defined($coreUpdate) );
__GetMaintainerdata() unless ( keys %moduleMaintainers > 0 );

sub import(@) {
    my $pkg = caller(0);

    #TODO Export a function to main context so that
    #  a device may use metadata to load Perl dependencies from META.json.
    #  This will provide a central place to maintain module dependencies
    #  w/o source code analysis.
    if ( $pkg eq "main" ) {
    }

    # Not sure yet what else could be done by just loading the module
    else {
    }
}

# Loads Metadata for single module, based on filename
sub InitMod($$;$) {
    my ( $filePath, $modHash, $runInLoop ) = @_;

    my $ret = __PutMetadata( $filePath, $modHash, 1, $runInLoop );

    if ($@) {
        Log 1, __PACKAGE__ . "::InitMod: ERROR: \$\@:\n" . $@;
        return "$@";
    }
    elsif ($ret) {
        Log 1, __PACKAGE__ . "::InitMod: ERROR: \$ret:\n" . $ret;
        return $ret;
    }

    if ( defined( $modHash->{META} ) && defined( $modHash->{META}{x_file} ) ) {

        # Add name to module hash
        $modHash->{NAME} = $modHash->{META}{x_file}[4];
        $modHash->{NAME} =~ s/^.*://g;    # strip away any parent module names

        # only run when module is reloaded
        if (   defined( $modules{ $modHash->{NAME} } )
            && defined( $modules{ $modHash->{NAME} }{NAME} )
            && $modHash->{NAME} eq $modules{ $modHash->{NAME} }{NAME} )
        {
            foreach my $devName ( devspec2array( 'TYPE=' . $modHash->{NAME} ) )
            {
                __CopyMetaToInternals( $defs{$devName}, $modHash->{META} );
            }
        }
    }

    return undef;
}

# Load Metadata for a list of modules
sub Load(;$$) {
    my ( $modList, $reload ) = @_;
    my $t = TimeNow();
    my $v = __PACKAGE__->VERSION();
    my @rets;

    my $unused = 0;
    my @lmodules;

    # if modList is undefined or is equal to '1'
    if ( !$modList || ( !ref($modList) && $modList eq '1' ) ) {
        $unused = 1 if ( $modList && $modList eq '1' );

        foreach ( keys %modules ) {

            # Only process loaded modules
            #   unless unused modules were
            #   explicitly requested
            push @lmodules,
              $_
              if (
                $unused
                || ( defined( $modules{$_}{LOADED} )
                    && $modules{$_}{LOADED} eq '1' )
              );
        }
    }

    # if a single module name was given
    elsif ( !ref($modList) ) {
        push @lmodules, $modList;
    }

    # if a list of module names was given
    elsif ( ref($modList) eq 'ARRAY' ) {
        foreach ( @{$modList} ) {
            push @lmodules, $_;
        }
    }

    # if a hash was given, assume every
    #   key is a module name
    elsif ( ref($modList) eq 'HASH' ) {
        foreach ( keys %{$modList} ) {
            push @lmodules, $_;
        }
    }

    # Wrong method use
    else {
        $@ = __PACKAGE__ . "::Load: ERROR: Unknown parameter value";
        Log 1, $@;
        return "$@";
    }

    if ($reload) {
        __GetUpdatedata();
        __GetMaintainerdata();
    }

    foreach my $modName (@lmodules) {
        $modName = 'Global' if ( uc($modName) eq 'FHEM' );
        my $type;

        if ( exists( $modules{$modName} ) && !exists( $packages{$modName} ) ) {
            $type = 'module';
        }
        elsif ( exists( $packages{$modName} ) && !exists( $modules{$modName} ) )
        {
            $type = 'package';
        }
        elsif ( exists( $packages{$modName} ) && exists( $modules{$modName} ) )
        {
            $type = 'module+package';
        }
        next unless ($type);

        # Abort when module file was not indexed by
        #   fhem.pl before.
        # Only continue if META was not loaded
        #   or should explicitly be reloaded.
        next
          if (
            $type eq 'module'
            && (
                !defined( $modules{$modName}{ORDER} )
                || (   !$reload
                    && defined( $modules{$modName}{META} )
                    && ref( $modules{$modName}{META} ) eq "HASH" )
            )
          );
        next
          if ( $type eq 'package'
            && !$reload
            && defined( $packages{$modName}{META} )
            && ref( $packages{$modName}{META} ) eq "HASH" );
        next
          if ( $type eq 'module+package'
            && !$reload
            && defined( $modules{$modName}{META} )
            && ref( $modules{$modName}{META} ) eq "HASH"
            && defined( $packages{$modName}{META} )
            && ref( $packages{$modName}{META} ) eq "HASH" );

        if ( ( $type eq 'module' || $type eq 'module+package' )
            && defined( $modules{$modName}{META} ) )
        {
            delete $modules{$modName}{META};

        }
        if ( ( $type eq 'package' || $type eq 'module+package' )
            && defined( $packages{$modName}{META} ) )
        {
            delete $packages{$modName}{META};
        }

        foreach my $type ( split( '\+', $type ) ) {
            my $filePath;
            if ( $modName eq 'Global' ) {
                $filePath = $attr{global}{modpath} . "/fhem.pl";
            }
            elsif ( $modName eq 'configDB' ) {
                $filePath = $attr{global}{modpath} . "/configDB.pm";
            }
            else {
                $filePath =
                    $attr{global}{modpath}
                  . "/FHEM/"
                  . ( $type eq 'module' ? $modules{$modName}{ORDER} . '_' : '' )
                  . $modName . '.pm';
            }

            my $ret = InitMod(
                $filePath,
                (
                    $type eq 'module' ? $modules{$modName} : $packages{$modName}
                ),
                1
            );
            push @rets, $@   if ( $@   && $@ ne '' );
            push @rets, $ret if ( $ret && $ret ne '' );

            if ( $type eq 'module' ) {
                $modules{$modName}{META}{generated_by} =
                  $packages{Meta}{META}{name} . ' '
                  . version->parse($v)->normal . ", $t"
                  if ( defined( $modules{$modName} )
                    && defined( $modules{$modName}{META} ) );

                foreach my $devName ( devspec2array( 'TYPE=' . $modName ) ) {
                    SetInternals( $defs{$devName} );
                }
            }
            else {
                $packages{$modName}{META}{generated_by} =
                  $packages{Meta}{META}{name} . ' '
                  . version->parse($v)->normal . ", $t"
                  if ( defined( $packages{$modName} )
                    && defined( $packages{$modName}{META} ) );
            }
        }
    }

    if (@rets) {
        $@ = join( "\n", @rets );
        return "$@";
    }

    return undef;
}

# Initializes a device instance of a FHEM module
sub SetInternals($) {
    my ($devHash) = @_;
    $devHash = $defs{$devHash} unless ( ref($devHash) );
    my $devName = $devHash->{NAME}   if ( defined( $devHash->{NAME} ) );
    my $modName = $devHash->{TYPE}   if ( defined( $devHash->{TYPE} ) );
    my $modHash = $modules{$modName} if ($modName);
    my $modMeta = $modHash->{META}   if ($modHash);

    unless ( defined($modHash) && ref($modHash) eq "HASH" ) {
        $@ = __PACKAGE__ . "::SetInternals: ERROR: Module hash not found";
        return 0;
    }

    return 0
      unless ( defined( $modHash->{LOADED} ) && $modHash->{LOADED} eq '1' );

    $devHash->{'.FhemMetaInternals'} = 1;
    __CopyMetaToInternals( $devHash, $modMeta );

    return 1;
}

# Get metadata
sub Get($$) {
    my ( $devHash, $field ) = @_;
    $devHash = $defs{$devHash} unless ( ref($devHash) );
    my $devName = $devHash->{NAME}   if ( defined( $devHash->{NAME} ) );
    my $modName = $devHash->{TYPE}   if ( defined( $devHash->{TYPE} ) );
    my $modHash = $modules{$modName} if ($modName);
    my $modMeta = $modHash->{META}   if ($modHash);

    unless ( defined($modHash) && ref($modHash) eq "HASH" ) {
        $@ = __PACKAGE__ . "::Get: ERROR: Module hash not found";
        return 0;
    }

    return $modMeta->{$field}
      if ( $modMeta && ref($modMeta) && defined( $modMeta->{$field} ) );
    return undef;
}

sub GetModuleSourceOrigin {
    my ($module) = @_;
    return 'fhem'
      if ( $module eq 'fhem.pl'
        || $module eq 'FHEM'
        || $module eq 'Global'
        || $module eq 'FHEM::Meta'
        || $module eq 'Meta' );

    return $moduleUpdates{$module}[0]
      if ( defined( $moduleUpdates{$module} ) );

    return $packageUpdates{$module}[0]
      if ( defined( $packageUpdates{$module} ) );

    return $corePackageUpdates{$module}[0]
      if ( defined( $corePackageUpdates{$module} ) );

    return '';
}

sub GetKeywordDesc {
    my ( $keyword, $lang ) = @_;
    $lang = 'en' unless ($lang);
    return '' unless ( defined( $keywordDescription{$keyword} ) );

    # turn fallback language around
    $lang = 'de'
      if ( !defined( $keywordDescription{$keyword}{$lang} )
        && $lang eq 'en' );

    return $keywordDescription{$keyword}{$lang}
      if ( defined( $keywordDescription{$keyword}{$lang} ) );

    return '';
}

sub ModuleIsCore {
    my ($module) = @_;
    return GetModuleSourceOrigin($module) eq 'fhem' ? 1 : 0;
}

sub ModuleIsInternal {
    my ($module) = @_;
    return 0 if ( ModuleIsPerlCore($module) || ModuleIsPerlPragma($module) );

    return 'module'
      if ( $module eq 'fhem.pl'
        || $module eq 'FHEM'
        || $module eq 'Global' );

    my $fname = $module;
    $fname =~ s/^.*://g;    # strip away any parent module names

    return 'package'
      if ( $fname eq 'Meta' );

    return 'module'
      if ( defined( $modules{$fname} ) && !defined( $packages{$fname} ) );
    return 'package'
      if ( defined( $packages{$fname} ) && !defined( $modules{$fname} ) );
    return 'module+package'
      if ( defined( $modules{$fname} ) && defined( $packages{$fname} ) );

    my $p = GetModuleFilepath($module);

    # if module has a relative path,
    #   assume it is part of FHEM
    return $p && ( $p =~ m/^(\.\/)?FHEM\/.+/ || $p =~ m/^(\.\/)?[^\/]+\.pm$/ )
      ? 'file'
      : 0;
}

# Get file path of a Perl module
sub GetModuleFilepath {
    my @path;

    foreach (@_) {
        my $module  = $_;
        my $package = $module;

        # From This::That to This/That.pm
        s/::/\//g, s/$/.pm/ foreach $module;

        if ( $module eq 'perl' ) {
            push @path, $^X;    # real binary

            # push @path, $ENV{_};    # symlink if any
        }
        elsif ( defined( $INC{$module} ) ) {
            push @path, $INC{$module};
        }
        else {
            eval {
                require $module;
                1;
            };

            if ( !$@ ) {
                push @path, $INC{$module};
            }
            else {
                push @path, '';
                $@ = undef;
            }
        }
    }

    if (wantarray) {
        return @path;
    }
    elsif ( @path > 0 ) {
        return join( ',', @path );
    }
}

sub ModuleIsPerlCore {
    my ($module) = @_;
    return grep ( /^$module$/, @perlCoreModules )
      ? 1
      : 0;
}

sub ModuleIsPerlPragma {
    my ($module) = @_;
    return grep ( /^$module$/, @perlPragmas )
      ? 1
      : 0;
}

##########
# Private functions
#

sub __CopyMetaToInternals {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $devHash, $modMeta ) = @_;
    return unless ( defined( $devHash->{'.FhemMetaInternals'} ) );
    return unless ( defined($modMeta) && ref($modMeta) eq "HASH" );

    $devHash->{FVERSION} = $modMeta->{x_version}
      if ( defined( $modMeta->{x_version} ) );
}

# Initializes FHEM module Metadata
sub __PutMetadata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $filePath, $modHash, $reload, $runInLoop ) = @_;

    return
      if ( !$reload
        && defined( $modHash->{META} )
        && ref( $modHash->{META} ) eq "HASH"
        && scalar keys %{ $modHash->{META} } > 0 );

    delete $modHash->{META};

    my %meta;
    my $ret = __GetMetadata( $filePath, \%meta, $runInLoop );
    return "$@" if ($@);
    return $ret if ($ret);

    $modHash->{META} = \%meta;

    return undef;
}

# Extract metadata from FHEM module file
sub __GetMetadata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ( $filePath, $modMeta, $runInLoop, $metaSection ) = @_;
    my @vcs;
    my $fh;
    my $encoding;
    my $version;
    my $versionFrom;
    my $authorName;    # not in use, see below
    my $authorMail;    # not in use, see below
    my $item_modsubtype;
    my $item_summary;
    my $item_summary_DE;
    my $modName;
    my $modType;

    # Static meta information
    $modMeta->{dynamic_config} = 1;
    $modMeta->{'meta-spec'} = {
        "version" => 2,
        "url"     => "https://metacpan.org/pod/CPAN::Meta::Spec"
    };

    # extract all info from file name
    if ( $filePath =~ m/^(?:\.\/)?((.+\/)?((?:(\d+)_)?(.+)\.(.+)))$/ ) {
        my @file;
        $file[0] = $1;    # complete match
        $file[1] =
            $2
          ? $2
          : '';           # relative file path, may be
                          #   undefined if same dir as fhem.pl
        $file[2] = $3;    # file name
        $file[3] = $4;    # order number, may be undefined
        $file[4] = $3 eq 'fhem.pl' ? 'Global' : $5;    # FHEM module name
        $file[5] = $6;                                 # file extension

        # These items are added later in the code:
        #   $file[6] - array with file system info
        #   $file[7] - source the version was extracted from
        #   $file[8] - plain extracted version number, may be undefined

        $modMeta->{x_file} = \@file;
        $modName = $file[4];
        $modType = $file[3] || $file[2] eq 'fhem.pl' ? 'mod' : 'pkg';
    }

    # grep info from file content
    if ( open( $fh, '<' . $filePath ) ) {
        my $skip = 1;
        my %json;

        # get file stats
        push @{ $modMeta->{x_file} }, [ @{ stat($fh) } ];
        foreach ( 8, 9, 10 ) {
            my $t = $modMeta->{x_file}[6][$_];
            my $s = FmtDateTime($t);
            $modMeta->{x_file}[6][$_] =
              [ $t, $1, $2, $3, $4, $5, $6, $7, $8, $9 ]
              if ( $s =~ m/^(((....)-(..)-(..)) ((..):(..):(..)))$/ );
        }

        my $searchComments = 1;    # not in use, see below
        my $currentJson    = '';
        while ( my $l = <$fh> ) {
            next if ( $l eq '' || $l =~ m/^\s+$/ );

            # # Track comments section at the beginning of the document
            # if ( $searchComments && $l !~ m/^#|\s*$/ ) {
            #     $searchComments = 0;
            # }

            # extract VCS info from $Id:
            if (   $skip
                && !@vcs
                && $l =~
m/(\$Id\: ((?:([0-9]+)_)?([\w]+)\.([\w]+))\s([0-9]+)\s((([0-9]+)-([0-9]+)-([0-9]+))\s(([0-9]+):([0-9]+):([0-9]+)))(?:[\w]+?)\s([\w.-]+)\s\$)/
              )
            {
                $vcs[0] = $1;    # complete match
                $vcs[1] = $2;    # file name
                $vcs[2] =
                  $2 eq 'fhem.pl'
                  ? '-1'
                  : $3;          # order number, may be indefined
                $vcs[3] = $2 eq 'fhem.pl' ? 'Global' : $4;   # FHEM module name
                $vcs[4] = $5;                                # file extension
                $vcs[5] = $6;                                # svn base revision
                $vcs[6]  = $7;     # commit datetime string
                $vcs[7]  = $8;     # commit date
                $vcs[8]  = $9;     # commit year
                $vcs[9]  = $10;    # commit month
                $vcs[10] = $11;    # commit day
                $vcs[11] = $12;    # commit time
                $vcs[12] = $13;    # commit hour
                $vcs[13] = $14;    # commit minute
                $vcs[14] = $15;    # commit second
                $vcs[15] = $16;    # svn username (COULD be maintainer
                                   #   if not in MAINTAINER.txt)

                # These items are added later in the code:
                #   $vcs[16] - commit unix timestamp
            }

#             # extract author name and email from comments
#             elsif ($searchComments
#                 && !$authorMail
#                 && $l =~
# m/(^#.*?([A-Za-z]+ +[A-Za-z]+?) +[<(]?\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b[>)]?)/i
#               )
#             {
#                 $searchComments = 0;
#                 $authorName     = $2 if ($2);
#                 $authorMail     = $3 if ($3);
#                 $authorName     = $authorMail
#                   if ( $authorName && $authorName =~ m/written| from| by/i );
#
#                 $authorName = '' unless ($authorName);
#             }

            ######
            # get legacy style version directly from
            #  within sourcecode if we are lucky
            #

            # via $VERSION|$version variable
            elsif ($skip
                && !$version
                && $l =~
m/((?:(?:my|our)\s+)?\$VERSION\s+=\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))/i
              )
            {
                my $extr = $2;
                $version = ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                  if ($extr);
                $version .= '.0'
                  if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                $versionFrom = 'source/1' if ($version);
            }

            # via $hash->{VERSION}|$hash->{version}
            elsif ($skip
                && !$version
                && $l =~
m/(->\{VERSION\}\s+=\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?)))/i
              )
            {
                my $extr = $2;
                $version = ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                  if ($extr);
                $version .= '.0'
                  if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                $versionFrom = 'source/2' if ($version);
            }

            #
            ######

            # read items from POD
            elsif ($skip
                && !$item_modsubtype
                && $l =~ m/^=item\s+(device|helper|command)\s*$/i )
            {
                return "=item (device|helper|command) pod must occur only once"
                  if ($item_modsubtype);
                $item_modsubtype = lc($1);
            }
            elsif ($skip
                && !$item_summary_DE
                && $l =~ m/^=item\s+(summary_DE)\s+(.+)$/i )
            {
                return "=item summary_DE pod must occur only once"
                  if ($item_summary_DE);
                $item_summary_DE =
                  ( $encoding && $encoding eq "utf8" ) ? encode_utf8($2) : $2;
            }
            elsif ($skip
                && !$item_summary
                && $l =~ m/^=item\s+(summary)\s+(.+)$/i )
            {
                return "=item summary_DE pod must occur only once"
                  if ($item_summary);
                $item_summary =
                  ( $encoding && $encoding eq "utf8" ) ? encode_utf8($2) : $2;
            }

            # read encoding from POD
            elsif ( $skip && $l =~ m/^=encoding\s+(.+)/i ) {
                return "=encoding pod must occur only once" if ($encoding);
                $encoding = lc($1);
            }

            # read META.json from POD
            elsif ($skip
                && $l =~
m/^=for\s+:application\/json;q=META\.json\s+([^\s\.]+\.[^\s\.]+)\s*$/i
              )
            {
                $skip               = 0;
                $currentJson        = $1;
                $json{$currentJson} = '';
            }
            elsif ( !$skip
                && $l =~ m/^=end\s+:application\/json\;q=META\.json/i )
            {
                $skip = 1;
            }
            elsif ( !$skip ) {
                $json{$currentJson} .= $l;
            }
        }

        # if we were unable to get version,
        #   let's also try the initial comments block
        unless ( keys %json > 0 || $version ) {
            seek $fh, 0, 0;

            while ( my $l = <$fh> ) {
                next if ( $l eq '' || $l =~ m/^\s+$/ );

                # Only seek the document until code starts
                if ( $l !~ m/^#/ && $l !~ m/^=[A-Za-z]+/i ) {
                    last;
                }

                # via Version:
                elsif ( !$version
                    && $l =~
m/(^#\s+Version:?\s+[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?))(?:\s+.*)?)$/i
                  )
                {
                    my $extr = $2;
                    $version =
                      ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                      if ($extr);
                    $version .= '.0'
                      if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                    $versionFrom = 'comment/1' if ($version);
                }

                # via changelog, assuming latest version comes first;
                #   might include false-positives
                elsif ( !$version
                    && $l =~
m/(^#\s+(?:\d{1,2}\.\d{1,2}\.(?:\d{2}|\d{4})\s+)?[^v\d]*(v?(?:\d{1,3}\.\d{1,3}(?:\.\d{1,3})?))(?:\s+.*)?)$/i
                  )
                {
                    my $extr = $2;

                    # filter false-positives that are actually dates
                    next
                      if ( $extr =~ m/^\d{2}\.\d{2}\.(\d{2})$/ && $1 ge 13 );

                    $version =
                      ( $extr =~ m/^v/i ? lc($extr) : lc( 'v' . $extr ) )
                      if ($extr);
                    $version .= '.0'
                      if ( $version && $version !~ m/v\d+\.\d+\.\d+/ );

                    $versionFrom = 'comment/2' if ($version);
                }

                last if ($version);
            }
        }

        close($fh);

        $encoding = 'latin1' unless ($encoding);

        if ( keys %json > 0 ) {
            eval {
                require JSON;
                1;
            };

            if ( !$@ ) {
                foreach ( keys %json ) {
                    next
                      if (
                        (
                            !$metaSection
                            && lc($_) ne lc( $modMeta->{x_file}[2] )
                        )
                        || ( $metaSection && $_ ne $metaSection )
                      );

                    eval {
                        my $t;
                        if ( $encoding ne 'latin1' ) {
                            if ( $encoding eq "utf8" ) {
                                $t = encode_utf8( $json{$_} );
                            }
                            elsif ( $encoding =~
                                /^(latin1|utf8|koi8-r|ShiftJIS|big5)$/ )
                            {
                                $@ = "Encoding type $encoding is not supported";
                            }
                            else {
                                $@ = "Invalid encoding type $encoding";
                            }
                        }
                        else {
                            $t = $json{$_};
                        }

                        return "$@" if ($@);

                        my $decoded = JSON::decode_json($t);
                        while ( my ( $k, $v ) = each %{$decoded} ) {
                            $modMeta->{$k} = $v;
                        }

                        1;
                    } or do {
                        $@ = "$_: Error while parsing META.json: $@";
                        return "$@";
                    };
                }
                return undef if ($metaSection);
            }
            else {
                $@ = undef;
            }
        }

        # special place for fhem.pl is this module file
        elsif ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {
            my %fhempl;
            my $ret = __GetMetadata( __FILE__, \%fhempl, undef, 'fhem.pl' );
            delete $fhempl{x_file};

            while ( my ( $k, $v ) = each %fhempl ) {
                $modMeta->{$k} = $v;
            }
        }

        # Detect prereqs if not provided via META.json
        if ( !defined( $modMeta->{prereqs} ) ) {
            eval {
                require Perl::PrereqScanner::NotQuiteLite;
                1;
            };

            if ( !$@ ) {
                my $scanner = Perl::PrereqScanner::NotQuiteLite->new(
                    parsers  => [qw/:installed -UniversalVersion/],
                    suggests => 1,
                );
                my $context      = $scanner->scan_file($filePath);
                my $requirements = $context->requires;
                my $recommends   = $context->recommends;
                my $suggestions = $context->suggests;    # requirements in evals

                $modMeta->{x_prereqs_src} = 'scanner';

                # requires
                foreach ( keys %{ $requirements->{requirements} } ) {
                    if (
                        defined( $requirements->{requirements}{$_}{minimum} )
                        && defined(
                            $requirements->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{requires}{$_} =
                          $requirements->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{requires}{$_} = 0;
                    }
                }

                # recommends
                foreach ( keys %{ $recommends->{requirements} } ) {
                    if (
                        defined( $recommends->{requirements}{$_}{minimum} )
                        && defined(
                            $recommends->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{recommends}{$_} =
                          $recommends->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{recommends}{$_} = 0;
                    }
                }

                # suggests
                foreach ( keys %{ $suggestions->{requirements} } ) {
                    if (
                        defined( $suggestions->{requirements}{$_}{minimum} )
                        && defined(
                            $suggestions->{requirements}{$_}{minimum}{original}
                        )
                      )
                    {
                        $modMeta->{prereqs}{runtime}{suggests}{$_} =
                          $suggestions->{requirements}{$_}{minimum}{original};
                    }
                    else {
                        $modMeta->{prereqs}{runtime}{suggests}{$_} = 0;
                    }
                }
            }
            else {
                $@ = undef;
            }
        }
        else {
            $modMeta->{x_prereqs_src} = 'META.json';
        }

        # Look for prereqs from FHEM packages
        #   used by this FHEM module.
        # We're not going deeper down for Meta.pm itself,
        # that means Meta.pm manual prereqs need to cover this.
        if (   $modName ne 'Meta'
            && defined( $modMeta->{prereqs} )
            && defined( $modMeta->{prereqs}{runtime} ) )
        {
            foreach my $pkgReq (qw(requires recommends suggests)) {
                next
                  unless ( defined( $modMeta->{prereqs}{runtime}{$pkgReq} ) );

                foreach
                  my $pkg ( keys %{ $modMeta->{prereqs}{runtime}{$pkgReq} } )
                {

                    # Add to dependency index:
                    #   packages to FHEM modules/packages
                    push @{ $dependents{pkgs}{$pkg}{$pkgReq} }, $modName
                      unless (
                        grep ( /^$modName$/,
                            @{ $dependents{pkgs}{$pkg}{$pkgReq} } ) );

                    #   dependents list
                    push @{ $dependents{$pkgReq}{$pkg} },
                      $modName
                      unless (
                        ModuleIsInternal($pkg)
                        || (   defined( $dependents{$pkgReq} )
                            && defined( $dependents{$pkgReq}{$pkg} )
                            && grep ( /^$modName$/,
                                @{ $dependents{$pkgReq}{$pkg} } ) )
                      );

                    # Found prereq that is a FHEM package
                    if ( exists( $packages{$pkg} ) ) {
                        Load($pkg);

                        if (   defined( $packages{$pkg}{META} )
                            && defined( $packages{$pkg}{META}{prereqs} )
                            && defined(
                                $packages{$pkg}{META}{prereqs}{runtime} ) )
                        {
                            my $pkgMeta = $packages{$pkg}{META};

                            foreach
                              my $pkgIreq (qw(requires recommends suggests))
                            {
                                next
                                  unless (
                                    defined(
                                        $pkgMeta->{prereqs}{runtime}{$pkgIreq}
                                    )
                                  );

                                # inject indirect prereq to FHEM module
                                foreach my $pkgI (
                                    keys
                                    %{ $pkgMeta->{prereqs}{runtime}{$pkgIreq} }
                                  )
                                {
                                    $modMeta->{prereqs}{runtime}{$pkgIreq}
                                      {$pkgI} =
                                      $pkgMeta->{prereqs}{runtime}{$pkgIreq}
                                      {$pkgI}
                                      if (
                                        !exists(
                                            $modMeta->{prereqs}{runtime}
                                              {$pkgIreq}{$pkgI}
                                        )
                                        || ( $pkgMeta->{prereqs}{runtime}
                                            {$pkgIreq}{$pkgI} ne '0'
                                            && $modMeta->{prereqs}{runtime}
                                            {$pkgIreq}{$pkgI} ne
                                            $pkgMeta->{prereqs}{runtime}
                                            {$pkgIreq}{$pkgI} )
                                      );
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Get some other info about fhem.pl
    if ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {
        $versionFrom = 'attr/featurelevel+vcs';
        if ( $modules{'Global'}{AttrList} =~ m/\W*featurelevel:((\d)\.(\d))/ ) {
            my $fl    = $1;
            my $major = $2;
            my $minor = $3;
            my $patch = $vcs[5];
            $version =
              version->parse( $major . '.' . $minor . '.' . $patch )->numify;
        }
        $modMeta->{version} = $version;
    }

    ########
    # Metadata refactoring starts here
    #

    #TODO
    # - check VCS data against update data
    # - get dependencies for modules loaded by FHEM modules

    # use VCS info 'as is', but only when:
    #   - file name matches
    #   - module is known in update file AND origin repo is fhem
    #   - or it is our own package of course
    if (   @vcs
        && $vcs[1] eq $modMeta->{x_file}[2] )
    {
        push @vcs,
          fhemTimeGm(
            $vcs[14], $vcs[13], $vcs[12], $vcs[10],
            ( $vcs[9] - 1 ),
            ( $vcs[8] - 1900 )
          );
        $modMeta->{x_vcs} = \@vcs;

        # if there is no maintainer, we will assign someone acting
        if (   !defined( $moduleMaintainers{$modName} )
            && !defined( $packageMaintainers{$modName} )
            && GetModuleSourceOrigin($modName) ne ''
            && $modName ne 'Meta' )
        {
            Log 4,
                __PACKAGE__
              . "::__GetMetadata WARNING: Unregistered core module or package:\n  "
              . $modMeta->{x_file}[0]
              . " has defined VCS data but is not registered in MAINTAINER.txt.\n  "
              . "Added acting maintainer with limited support status";

            # add acting maintainer
            if ( $modType eq 'mod' ) {
                $moduleMaintainers{$modName}[0][0] =
                  $modMeta->{x_file}[0];
                $moduleMaintainers{$modName}[0][1] =
                  $modMeta->{x_file}[1];
                $moduleMaintainers{$modName}[0][2] =
                  $modMeta->{x_file}[2];
                $moduleMaintainers{$modName}[0][3] =
                  $modMeta->{x_file}[3];
                $moduleMaintainers{$modName}[0][4] =
                  $modName;
                $moduleMaintainers{$modName}[0][5] =
                  $modMeta->{x_file}[5];
                $moduleMaintainers{$modName}[1] = 'rudolfkoenig (acting)';
                $moduleMaintainers{$modName}[2] = 'limited';
                $moduleMaintainers{$modName}[3] =
                  __GetSupportForum('Sonstiges');

                # add acting maintainer to maintainer hashes
                my $lastEditor = 'rudolfkoenig (acting)';
                push @{ $maintainers{$lastEditor}{modules} },
                  $modName
                  unless (
                    defined( $maintainers{$lastEditor} )
                    && grep( m/^$lastEditor$/i,
                        @{ $maintainers{$lastEditor}{modules} } )
                  );

                # add last committer to maintainer hashes
                $lastEditor = $modMeta->{x_vcs}[15];
                push @{ $maintainers{$lastEditor}{modules} },
                  $modName
                  unless (
                    defined( $maintainers{$lastEditor} )
                    && grep( m/^$lastEditor$/i,
                        @{ $maintainers{$lastEditor}{modules} } )
                  );
            }
            else {
                $packageMaintainers{$modName}[0][0] =
                  $modMeta->{x_file}[0];
                $packageMaintainers{$modName}[0][1] =
                  $modMeta->{x_file}[1];
                $packageMaintainers{$modName}[0][2] =
                  $modMeta->{x_file}[2];
                $packageMaintainers{$modName}[0][3] =
                  $modMeta->{x_file}[3];
                $packageMaintainers{$modName}[0][4] =
                  $modName;
                $packageMaintainers{$modName}[0][5] =
                  $modMeta->{x_file}[5];
                $packageMaintainers{$modName}[1] = 'rudolfkoenig (acting)';
                $packageMaintainers{$modName}[2] = 'limited';
                $packageMaintainers{$modName}[3] =
                  __GetSupportForum('Sonstiges');

                # add acting maintainer to maintainer hashes
                my $lastEditor = 'rudolfkoenig (acting)';
                push @{ $maintainers{$lastEditor}{packages} },
                  $modName
                  unless (
                    defined( $maintainers{$lastEditor} )
                    && grep( m/^$lastEditor$/i,
                        @{ $maintainers{$lastEditor}{packages} } )
                  );

                # add last committer to maintainer hashes
                $lastEditor = $modMeta->{x_vcs}[15];
                push @{ $maintainers{$lastEditor}{packages} },
                  $modName
                  unless (
                    defined( $maintainers{$lastEditor} )
                    && grep( m/^$lastEditor$/i,
                        @{ $maintainers{$lastEditor}{packages} } )
                  );
            }
        }
    }

    # author has put version into JSON
    if ( defined( $modMeta->{version} ) ) {
        $versionFrom = 'META.json' unless ($versionFrom);
    }

    # author has put version somewhere else in the file
    elsif ($version) {
        $modMeta->{version} = $version;
    }

    # seems the author didn't put any explicit
    #   version number we could find ...
    else {
        if ( defined( $modMeta->{x_vcs} )
            && $modMeta->{x_vcs}[5] ne '' )
        {
            $versionFrom = 'generated/vcs';
            $modMeta->{version} = '0.' . $modMeta->{x_vcs}[5];
        }

        # we don't know anything about this module at all
        else {
            $versionFrom = 'generated/blank';
            $modMeta->{version} = '0.000000001';
        }
    }

    push @{ $modMeta->{x_file} }, $versionFrom;
    push @{ $modMeta->{x_file} }, $version;

    # Standardize version number
    $modMeta->{version} = version->parse( $modMeta->{version} )->numify
      if ( defined( $modMeta->{version} ) );

    $@ .=
      $modMeta->{x_file}[2] . ": Invalid version format '$modMeta->{version}'"
      if ( defined( $modMeta->{version} )
        && $modMeta->{version} !~ m/^\d+\.\d+$/ );

    # meta name
    unless ( defined( $modMeta->{name} ) ) {
        if ( $modName eq 'Global' ) {
            $modMeta->{name} = 'FHEM';
        }
        else {
            $modMeta->{name} = $modMeta->{x_file}[1];
            $modMeta->{name} =~ s/^\.\///;
            $modMeta->{name} =~ s/\/$//;
            $modMeta->{name} =~ s/\//::/g;
        }
        if ( $modName ne 'Global' ) {
            $modMeta->{name} .= '::' if ( $modMeta->{name} );
            $modMeta->{name} .= $modName;
        }
    }

    $modMeta->{abstract} = $item_summary
      if ( $item_summary && !defined( $modMeta->{abstract} ) );
    $modMeta->{x_lang}{de}{abstract} = $item_summary_DE
      if ( $item_summary_DE && !defined( $modMeta->{x_lang}{de}{abstract} ) );

    # Only when this package is reading its own metadata.
    # Other modules shall get this added elsewhere for performance reasons
    if ( $modMeta->{name} eq __PACKAGE__ ) {
        $modMeta->{generated_by} =
            $modMeta->{name} . ' '
          . version->parse( $modMeta->{version} )->normal . ', '
          . TimeNow();
    }

    # If we are not running in loop, this is not time consuming for us here
    elsif ( !$runInLoop ) {
        $modMeta->{generated_by} =
            $packages{Meta}{META}{name} . ' '
          . version->parse( __PACKAGE__->VERSION() )->normal . ', '
          . TimeNow();
    }

    # Fill mandatory attributes
    unless ( defined( $modMeta->{abstract} ) ) {
        if ( $modType eq 'pkg' ) {
            $modMeta->{abstract} =
              'FHEM development package that is used by FHEM modules';
        }
        else {
            $modMeta->{abstract} = 'n/a';
        }
    }
    unless ( defined( $modMeta->{description} ) ) {
        if ( $modType eq 'pkg' ) {
            $modMeta->{description} =
              'This is a FHEM-included Perl package that does not show up as a '
              . 'regular device in FHEM. \\n'
              . 'That is because it provides additional functionality that can be used by real '
              . 'FHEM modules in order to share the same code basis.';
        }
        else {
            $modMeta->{description} = 'n/a';
        }
    }
    unless ( defined( $modMeta->{release_status} ) ) {
        $modMeta->{release_status} = 'stable';
    }
    unless ( defined( $modMeta->{license} ) ) {
        $modMeta->{license} = 'unknown';
    }
    unless ( defined( $modMeta->{author} ) ) {
        $modMeta->{author} = ['unknown <>'];
    }

    # Generate META information for FHEM core modules
    if ( GetModuleSourceOrigin($modName) eq 'fhem' ) {

        if (  !$modMeta->{release_status}
            || $modMeta->{release_status} eq 'stable' )
        {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{release_status} = 'stable';
            }
            else {
                $modMeta->{release_status} = 'unstable';
            }
        }

        if ( !$modMeta->{license} || $modMeta->{license} eq 'unknown' ) {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{license} = 'GPL_2';
            }
        }

        if ( !$modMeta->{author} || $modMeta->{author}[0] eq 'unknown <>' ) {
            if ( defined( $moduleMaintainers{$modName} ) ) {
                shift @{ $modMeta->{author} }
                  if ( $modMeta->{author}
                    && $modMeta->{author}[0] eq 'unknown <>' );

                foreach ( split( '/|,', $moduleMaintainers{$modName}[1] ) ) {
                    push @{ $modMeta->{author} }, "$_ <>";
                }

                # last update was not by one of the named authors
                if ( defined( $modMeta->{x_vcs} ) ) {
                    my $lastEditor = $modMeta->{x_vcs}[15] . ' <>';
                    push @{ $modMeta->{author} },
                      $modMeta->{x_vcs}[15] . ' (last release only) <>'
                      unless (
                        grep( m/^$lastEditor$/i, @{ $modMeta->{author} } ) );
                }
            }
            elsif ( defined( $packageMaintainers{$modName} ) ) {
                shift @{ $modMeta->{author} }
                  if ( $modMeta->{author}
                    && $modMeta->{author}[0] eq 'unknown <>' );

                foreach ( split( '/|,', $packageMaintainers{$modName}[1] ) ) {
                    push @{ $modMeta->{author} }, "$_ <>";
                }

                # last update was not by one of the named authors
                if ( defined( $modMeta->{x_vcs} ) ) {
                    my $lastEditor = $modMeta->{x_vcs}[15] . ' <>';
                    push @{ $modMeta->{author} },
                      $modMeta->{x_vcs}[15] . ' (last release only) <>'
                      unless (
                        grep( m/^$lastEditor$/i, @{ $modMeta->{author} } ) );
                }
            }
        }
        unless ( $modMeta->{x_fhem_maintainer} ) {
            if ( defined( $moduleMaintainers{$modName} ) ) {
                foreach ( split( '/|,', $moduleMaintainers{$modName}[1] ) ) {
                    push @{ $modMeta->{x_fhem_maintainer} }, $_;
                }

                # last update was not by one of the named authors
                if ( defined( $modMeta->{x_vcs} ) ) {
                    my $lastEditor = $modMeta->{x_vcs}[15];
                    push @{ $modMeta->{x_fhem_maintainer} },
                      $modMeta->{x_vcs}[15]
                      unless (
                        grep( m/^$lastEditor$/i,
                            @{ $modMeta->{x_fhem_maintainer} } )
                      );
                }
            }
            elsif ( defined( $packageMaintainers{$modName} ) ) {
                foreach ( split( '/|,', $packageMaintainers{$modName}[1] ) ) {
                    push @{ $modMeta->{x_fhem_maintainer} }, $_;
                }

                # last update was not by one of the named authors
                if ( defined( $modMeta->{x_vcs} ) ) {
                    my $lastEditor = $modMeta->{x_vcs}[15];
                    push @{ $modMeta->{x_fhem_maintainer} },
                      $modMeta->{x_vcs}[15]
                      unless (
                        grep( m/^$lastEditor$/i,
                            @{ $modMeta->{x_fhem_maintainer} } )
                      );
                }
            }
        }

        unless ( defined( $modMeta->{resources} )
            && defined( $modMeta->{resources}{license} ) )
        {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{resources}{license} =
                  ['https://fhem.de/#License'];
            }
        }

        unless ( defined( $modMeta->{resources} )
            && defined( $modMeta->{resources}{x_wiki} ) )
        {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{resources}{x_wiki}{web} = 'https://wiki.fhem.de/';
                $modMeta->{resources}{x_wiki}{modpath} = 'wiki/';
            }
        }

        unless (
            $modType ne 'mod'
            || (   defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_commandref} ) )
          )
        {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{resources}{x_commandref}{web} =
                  'https://fhem.de/commandref.html#' . $modName;
            }
        }

        unless ( defined( $modMeta->{resources} )
            && defined( $modMeta->{resources}{x_support_community} ) )
        {
            if (   defined( $modMeta->{x_vcs} )
                && defined( $moduleMaintainers{$modName} )
                && ref( $moduleMaintainers{$modName} ) eq 'ARRAY'
                && defined( $moduleMaintainers{$modName}[3] )
                && ref( $moduleMaintainers{$modName}[3] ) eq 'HASH'
                && keys %{ $moduleMaintainers{$modName}[3] } > 0 )
            {
                $modMeta->{resources}{x_support_community} =
                  $moduleMaintainers{$modName}[3];
            }
            elsif (defined( $modMeta->{x_vcs} )
                && defined( $packageMaintainers{$modName} )
                && ref( $packageMaintainers{$modName} ) eq 'ARRAY'
                && defined( $packageMaintainers{$modName}[3] )
                && ref( $packageMaintainers{$modName}[3] ) eq 'HASH'
                && keys %{ $packageMaintainers{$modName}[3] } > 0 )
            {
                $modMeta->{resources}{x_support_community} =
                  $packageMaintainers{$modName}[3];
            }
        }

        unless (
               defined( $modMeta->{resources} )
            && defined( $modMeta->{resources}{repository} )
            && (   defined( $modMeta->{resources}{repository}{type} )
                || defined( $modMeta->{resources}{repository}{url} )
                || defined( $modMeta->{resources}{repository}{web} )
                || defined( $modMeta->{resources}{repository}{x_branch} )
                || defined( $modMeta->{resources}{repository}{x_filepath} )
                || defined( $modMeta->{resources}{repository}{x_raw} ) )
          )
        {
            if ( defined( $modMeta->{x_vcs} ) ) {
                $modMeta->{resources}{repository}{type} = 'svn';
                $modMeta->{resources}{repository}{url} =
                  'https://svn.fhem.de/fhem';
                $modMeta->{resources}{repository}{web} =
                    'https://svn.fhem.de/trac/browser/trunk/fhem/'
                  . $modMeta->{x_file}[1]
                  . $modMeta->{x_file}[2];
                $modMeta->{resources}{repository}{x_branch}   = 'trunk';
                $modMeta->{resources}{repository}{x_filepath} = 'fhem'
                  . (
                    $modMeta->{x_file}[1] ne ''
                    ? '/' . $modMeta->{x_file}[1]
                    : ''
                  );
                $modMeta->{resources}{repository}{x_raw} =
                    'https://svn.fhem.de/fhem/trunk/fhem/'
                  . $modMeta->{x_file}[1]
                  . $modMeta->{x_file}[2];
            }
        }
    }

    # delete some attributes that are exclusive to FHEM core
    else {
        delete $modMeta->{x_fhem_maintainer};
        delete $modMeta->{x_fhem_maintainer_github};
    }

    unless ( defined( $modMeta->{x_support_status} ) ) {
        if (   defined( $moduleMaintainers{$modName} )
            && ref( $moduleMaintainers{$modName} ) eq 'ARRAY'
            && defined( $moduleMaintainers{$modName}[2] ) )
        {
            $modMeta->{x_support_status} =
              $moduleMaintainers{$modName}[2];
        }
        elsif (defined( $packageMaintainers{$modName} )
            && ref( $packageMaintainers{$modName} ) eq 'ARRAY'
            && defined( $packageMaintainers{$modName}[2] ) )
        {
            $modMeta->{x_support_status} =
              $packageMaintainers{$modName}[2];
        }
        elsif ( defined( $modMeta->{resources} )
            && $modMeta->{resources}{x_support_community} )
        {
            $modMeta->{x_support_status} = 'supported';
        }
        else {
            $modMeta->{x_support_status} = 'unknown';
        }
    }

    # Filter keywords that are reserved for FHEM core
    if ( defined( $modMeta->{keywords} ) && @{ $modMeta->{keywords} } > 0 ) {
        my @filtered;

        foreach my $keyword ( @{ $modMeta->{keywords} } ) {
            push @filtered, lc($keyword)
              unless ( lc($keyword) eq 'fhem-core'
                || lc($keyword) eq 'fhem-mod'
                || lc($keyword) eq 'fhem-pkg'
                || lc($keyword) eq 'fhem-3rdparty'
                || lc($keyword) eq 'fhem-mod-3rdparty'
                || lc($keyword) eq 'fhem-pkg-3rdparty'
                || lc($keyword) eq 'fhem-mod-local'
                || lc($keyword) eq 'fhem-pkg-local'
                || lc($keyword) eq 'fhem-commercial'
                || lc($keyword) eq 'fhem-mod-commercial'
                || lc($keyword) eq 'fhem-pkg-commercial' );
        }

        delete $modMeta->{keywords};
        $modMeta->{keywords} = \@filtered;
    }

    # Generate keywords, based on support data
    if (   defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{x_support_community} )
        && $modMeta->{x_file}[2] ne 'fhem.pl' )
    {
        foreach my $keyword (
            __GenerateKeywordsFromSupportCommunity(
                $modMeta->{resources}{x_support_community}
            )
          )
        {
            push @{ $modMeta->{keywords} }, $keyword
              if ( !defined( $modMeta->{keywords} )
                || !grep ( m/^$keyword$/i, @{ $modMeta->{keywords} } ) );
        }
    }

    if (   defined( $modMeta->{resources} )
        && defined( $modMeta->{resources}{x_support_commercial} ) )
    {
        push @{ $modMeta->{keywords} }, "fhem-$modType-commercial";
    }

    # add legacy POD info as Metadata
    if ($item_modsubtype) {
        $item_modsubtype = "fhem-$modType-" . $item_modsubtype;
        push @{ $modMeta->{keywords} }, $item_modsubtype
          if ( !defined( $modMeta->{keywords} )
            || !grep ( /^$item_modsubtype$/i, @{ $modMeta->{keywords} } ) );
    }
    else {
        push @{ $modMeta->{keywords} }, "fhem-$modType"
          if ( !defined( $modMeta->{keywords} )
            || !grep ( /^fhem-$modType$/i, @{ $modMeta->{keywords} } ) );
    }

    # Add some keywords about the module origin
    if ( GetModuleSourceOrigin($modName) eq 'fhem' ) {
        push @{ $modMeta->{keywords} }, 'fhem-core';
    }
    elsif ( GetModuleSourceOrigin($modName) ne '' ) {
        push @{ $modMeta->{keywords} }, "fhem-$modType-3rdparty";
    }
    else {
        push @{ $modMeta->{keywords} }, "fhem-$modType-local";
    }

    # Add keywords to global index
    if ( @{ $modMeta->{keywords} } > 0 ) {
        foreach ( @{ $modMeta->{keywords} } ) {
            if ( $modType eq 'mod' ) {
                push @{ $keywords{$_}{modules} }, $modName
                  if ( !defined( $keywords{$_}{modules} )
                    || !grep ( /^$modName$/i, @{ $keywords{$_}{modules} } ) );
            }
            else {
                push @{ $keywords{$_}{packages} }, $modName
                  if ( !defined( $keywords{$_}{packages} )
                    || !grep ( /^$modName$/i, @{ $keywords{$_}{packages} } ) );
            }
        }
    }

    # generate x_version
    __SetXVersion($modMeta);

    return "$@" if ($@);
    return undef;
}

sub __GenerateKeywordsFromSupportCommunity {
    my ($community) = @_;
    my @keywords;

    if ( defined( $community->{board} )
        && $community->{board} ne '' )
    {
        my $prefix;
        $prefix = lc($1) . '-'
          if ( $community->{cat} =~ /^(\w+)/ );

        if (   defined( $community->{subCommunity} )
            && defined( $community->{subCommunity}{board} )
            && $community->{subCommunity}{board} ne '' )
        {
            my $parent = lc( $community->{board} );
            my $tag    = lc( $community->{subCommunity}{board} );

            $tag =~ s/$parent\s+-\s+|$parent\s+»\s+//g;
            $tag =~ s/ - |»/ /g;
            $tag =~ s/ +/-/g;

            foreach ( split '/', $tag ) {
                my $t = ( $_ =~ /^$prefix/ ? '' : $prefix ) . $_;
                my $desc =
                  defined( $community->{subCommunity}{description} )
                  ? $community->{subCommunity}{description}
                  : (
                    defined( $community->{description} )
                    ? $community->{description}
                    : ''
                  );

                push @keywords, $t;
                $keywordDescription{$t}{de} = $desc
                  unless (
                    $desc eq ''
                    || (   defined( $keywordDescription{$t} )
                        && defined( $keywordDescription{$t}{de} ) )
                  );
            }
        }

        my $tag = lc( $community->{board} );
        $tag =~ s/ - |»/ /g;
        $tag =~ s/ +/-/g;

        foreach ( split '/', $tag ) {
            my $t = ( $_ =~ /^$prefix/ ? '' : $prefix ) . $_;
            my $desc =
                 defined( $community->{subCommunity} )
              && defined( $community->{subCommunity}{description} )
              ? $community->{subCommunity}{description}
              : (
                defined( $community->{description} ) ? $community->{description}
                : ''
              );

            push @keywords, $t;
            $keywordDescription{$t}{de} = $desc
              unless (
                $desc eq ''
                || (   defined( $keywordDescription{$t} )
                    && defined( $keywordDescription{$t}{de} ) )
              );
        }
    }

    if (   defined( $community->{cat} )
        && $community->{cat} ne ''
        && $community->{cat} ne 'FHEM' )
    {
        my $tag = lc( $community->{cat} );
        $tag =~ s/ - |»/ /g;
        $tag =~ s/ +/-/g;

        foreach ( split '/', $tag ) {
            my $desc =
              defined( $community->{description} )
              ? $community->{description}
              : '';

            push @keywords, $tag;
            $keywordDescription{$tag}{de} = $desc
              unless (
                $desc eq ''
                || (   defined( $keywordDescription{$tag} )
                    && defined( $keywordDescription{$tag}{de} ) )
              );
        }
    }

    return @keywords;
}

sub __GetPackages {
    my $dh;
    my $dir = $attr{global}{modpath};
    if ( opendir( $dh, $dir ) ) {
        foreach
          my $fn ( grep { $_ ne "." && $_ ne ".." && !-d $_ } readdir($dh) )
        {
            if (   $fn =~ m/^(?:\.\/)?((.+\/)?((?:(\d+)_)?(.+)\.(.+)))$/
                && !$4
                && $6
                && $6 eq 'pm' )
            {
                $packages{$5} = ();
            }
        }
        closedir($dh);
    }

    $dir = $attr{global}{modpath} . '/FHEM/';
    if ( opendir( $dh, $dir ) ) {
        foreach
          my $fn ( grep { $_ ne "." && $_ ne ".." && !-d $_ } readdir($dh) )
        {
            if (   $fn =~ m/^(?:\.\/)?((.+\/)?((?:(\d+)_)?(.+)\.(.+)))$/
                && !$4
                && $6
                && $6 eq 'pm' )
            {
                $packages{$5} = ();
            }
        }
        closedir($dh);
    }
}

sub __GetMaintainerdata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my $fh;
    %moduleMaintainers  = ();
    %packageMaintainers = ();

    if ( open( $fh, '<' . $attr{global}{modpath} . '/MAINTAINER.txt' ) ) {
        my $skip = 1;
        while ( my $l = <$fh> ) {
            if ( $l =~ m/^===+$/ ) {
                $skip = 0;
                next;
            }
            next if ($skip);

            my @line = map {
                s/^\s+//;    # strip leading spaces
                s/\s+$//;    # strip trailing spaces
                $_           # return the modified string
            } split( "[ \t][ \t]*", $l, 3 );

            if ( $line[0] =~ m/^((.+\/)?((?:(\d+)_)?(.+?)(?:\.(.+))?))$/ ) {

                my @maintainer;

                # This is a FHEM module file,
                #  either in ./ or ./FHEM/. For files in ./,
                #  file extension must be provided.
                #  Files in ./FHEM/ use file order number to identify.
                if (
                    (
                           ( !$2 || $2 eq '' || $2 eq './' )
                        && ( $6 && ( $6 eq 'pl' || $6 eq 'pm' ) )
                    )
                    || ( $4 && $2 eq 'FHEM/' )
                  )
                {
                    my $type = $4 ? 'module' : 'package';

                    if ( !-f $1 && !-f $1 . '.pm' ) {
                        Log 4,
                            __PACKAGE__
                          . "::__GetMaintainerdata ERROR: Orphan $type entry:\n  "
                          . join( ' ', @line );
                        next;
                    }

                    $maintainer[0][0] = $1;    # complete match
                    $maintainer[0][1] = $2;    # relative file path
                    $maintainer[0][2] = $3;    # file name
                    $maintainer[0][3] = $4;    # order number, may be undefined
                    $maintainer[0][4] =
                      $3 eq 'fhem.pl' ? 'Global' : $5;    # FHEM module name
                    $maintainer[0][5] = $6;       # file extension
                    $maintainer[1] = $line[1];    # Maintainer alias name
                    $maintainer[2] =
                      $line[2] =~ m/\(deprecated\)/i
                      ? 'deprecated'
                      : 'supported';              # Lifecycle status

                    my $modName = $maintainer[0][4];

                    $line[2] =~ s/\s*\(.*\)\s*$//;    # remove all comments
                    $maintainer[3] =
                      $maintainer[2] eq 'deprecated'
                      ? ()
                      : __GetSupportForum( $line[2] );   # Forum support section

                    if ( defined( $moduleMaintainers{ $maintainer[0][4] } ) ) {
                        Log 1,
                            __PACKAGE__
                          . "::__GetMaintainerdata ERROR: Duplicate $type entry:\n"
                          . '  1st: '
                          . $moduleMaintainers{ $maintainer[0][4] }[0][0]
                          . ' '
                          . $moduleMaintainers{ $maintainer[0][4] }[1] . ' '
                          . $moduleMaintainers{ $maintainer[0][4] }[2]
                          . "\n  2nd: "
                          . join( ' ', @line );
                    }
                    else {
                        # Register in global FHEM module index
                        $moduleMaintainers{ $maintainer[0][4] } =
                          \@maintainer;

                        # Register in global maintainer index
                        foreach ( split '/|,', $maintainer[1] ) {
                            push @{ $maintainers{$_}{modules} },
                              $maintainer[0][4];
                        }

                        # Generate keywords for global index
                        foreach (
                            __GenerateKeywordsFromSupportCommunity(
                                $maintainer[3]
                            )
                          )
                        {
                            if ( $type eq 'module' ) {
                                push @{ $keywords{$_}{modules} },
                                  $modName
                                  if (
                                    !defined( $keywords{$_}{modules} )
                                    || !grep ( /^$modName$/i,
                                        @{ $keywords{$_}{modules} } )
                                  );
                            }
                            else {
                                push @{ $keywords{$_}{packages} },
                                  $modName
                                  if (
                                    !defined( $keywords{$_}{packages} )
                                    || !grep ( /^$modName$/i,
                                        @{ $keywords{$_}{packages} } )
                                  );
                            }
                        }
                    }
                }

                # This is a FHEM Perl package under ./FHEM/,
                #   used by FHEM modules.
                #   Packages must provide file extension here.
                elsif ( $2 && $2 eq 'FHEM/' && $6 eq 'pm' ) {

                    my $type = 'package';

                    if ( !-f $1 && !-f $1 . '.pm' ) {
                        Log 4,
                            __PACKAGE__
                          . "::__GetMaintainerdata ERROR: Orphan $type entry:\n  "
                          . join( ' ', @line );
                        next;
                    }

                    $maintainer[0][0] = $1;    # complete match
                    $maintainer[0][1] = $2;    # relative file path
                    $maintainer[0][2] = $3;    # file name
                    $maintainer[0][3] = $4;    # order number,
                         #  empty here but we want the same structure
                    $maintainer[0][4] = $5;          # FHEM package name
                    $maintainer[0][5] = $6;          # file extension
                    $maintainer[1]    = $line[1];    # Maintainer alias name
                    $maintainer[2] =
                      $line[2] =~ m/\(deprecated\)/i
                      ? 'deprecated'
                      : 'supported';                 # Lifecycle status

                    my $modName = $maintainer[0][4];

                    $line[2] =~ s/\s*\(.*\)\s*$//;    # remove all comments
                    $maintainer[3] =
                      $maintainer[2] eq 'deprecated'
                      ? ()
                      : __GetSupportForum( $line[2] );   # Forum support section

                    if ( defined( $packageMaintainers{ $maintainer[0][4] } ) ) {
                        Log 1,
                            __PACKAGE__
                          . "::__GetMaintainerdata ERROR: Duplicate $type entry:\n"
                          . '  1st: '
                          . $packageMaintainers{ $maintainer[0][4] }[0][0]
                          . ' '
                          . $packageMaintainers{ $maintainer[0][4] }[1] . ' '
                          . $packageMaintainers{ $maintainer[0][4] }[2]
                          . "\n  2nd: "
                          . join( ' ', @line );
                    }
                    else {
                        # Register in global FHEM package index
                        $packageMaintainers{ $maintainer[0][4] } =
                          \@maintainer;

                        # Register in global maintainer index
                        foreach ( split '/|,', $maintainer[1] ) {
                            push @{ $maintainers{$_}{packages} },
                              $maintainer[0][4];
                        }

                        # Generate keywords for global index
                        foreach (
                            __GenerateKeywordsFromSupportCommunity(
                                $maintainer[3]
                            )
                          )
                        {
                            push @{ $keywords{$_}{packages} }, $modName
                              if ( !defined( $keywords{$_}{packages} )
                                || !
                                grep ( /^$modName$/i,
                                    @{ $keywords{$_}{packages} } ) );
                        }
                    }
                }

                # this is a FHEM file
                #   under any path
                else {
                    # our %fileMaintainers;
                }
            }
        }

        close($fh);
    }
    else {
        Log 1,
            __PACKAGE__
          . "::__GetMaintainerdata ERROR: Unable to read MAINTAINER.txt:\n  "
          . $@;
        return 0;
    }
}

sub __GetSupportForum {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ($req) = @_;
    my %ret;

    if ( $req =~ /^http/ ) {
        $ret{web}   = $req;
        $ret{title} = $1
          if ( $req =~ m/^.+:\/\/([^\/]+).*/ && $1 !~ /fhem\.de$/ );
        return \%ret;
    }

    my %umlaute = (
        "ä" => "ae",
        "Ä" => "Ae",
        "ü" => "ue",
        "Ü" => "Ue",
        "ö" => "oe",
        "Ö" => "Oe",
        "ß" => "ss"
    );
    my $umlautKeys = join( "|", keys(%umlaute) );
    my %umlauteRev = (
        "ae" => "ä",
        "Ae" => "Ä",
        "ue" => "ü",
        "Ue" => "Ü",
        "oe" => "ö",
        "Oe" => "Ö"
    );
    my $umlautRevKeys = join( "|", keys(%umlauteRev) );

    $req =~ s/($umlautRevKeys)/$umlauteRev{$1}/g    # yes, we know umlauts
      unless ( $req =~ /uerung/ );

    foreach my $cat ( keys %supportForumCategories ) {
        foreach my $board ( keys %{ $supportForumCategories{$cat} } ) {
            next
              if ( $board eq 'boardId'
                || $board eq 'description'
                || $board eq 'language' );

            if ( lc($board) eq lc($req) ) {

                # we found a main board
                if ( defined( $supportForumCategories{$cat}{$board}{boardId} ) )
                {
                    $ret{cat}   = $cat;
                    $ret{board} = $board;
                    $ret{boardId} =
                      $supportForumCategories{$cat}{$board}{boardId};
                    $ret{description} =
                      $supportForumCategories{$cat}{$board}{description}
                      if (
                        defined(
                            $supportForumCategories{$cat}{$board}{description}
                        )
                      );
                    $ret{language} =
                      $supportForumCategories{$cat}{$board}{language}
                      if (
                        defined(
                            $supportForumCategories{$cat}{$board}{language}
                        )
                      );
                    last;
                }
            }

            # is it a sub board?
            else {
                foreach my $subBoard (
                    keys %{ $supportForumCategories{$cat}{$board} } )
                {
                    next
                      if ( $subBoard eq 'boardId'
                        || $subBoard eq 'description'
                        || $subBoard eq 'language' );

                    my $reqSub = $req;
                    if ( $reqSub =~ /^$board\/(.+)/ ) {
                        $reqSub = $1;
                        $reqSub =~ s/ /\//g;    # justme1968 special ;D)
                    }

                    if ( lc($subBoard) eq lc($reqSub) ) {

                        # we found a sub board
                        if (
                            defined(
                                $supportForumCategories{$cat}{$board}
                                  {$subBoard}{boardId}
                            )
                          )
                        {
                            $ret{cat} = $cat;

                            $ret{board} = $board;
                            $ret{boardId} =
                              $supportForumCategories{$cat}{$board}{boardId};
                            $ret{description} =
                              $supportForumCategories{$cat}{$board}{description}
                              if (
                                defined(
                                    $supportForumCategories{$cat}{$board}
                                      {description}
                                )
                              );
                            $ret{language} =
                              $supportForumCategories{$cat}{$board}{language}
                              if (
                                defined(
                                    $supportForumCategories{$cat}{$board}
                                      {language}
                                )
                              );

                            $ret{subCommunity}{board} =
                              $board . ' » ' . $subBoard;
                            $ret{subCommunity}{boardId} =
                              $supportForumCategories{$cat}{$board}{$subBoard}
                              {boardId};
                            $ret{subCommunity}{description} =
                              $supportForumCategories{$cat}{$board}{$subBoard}
                              {description}
                              if (
                                defined(
                                    $supportForumCategories{$cat}{$board}
                                      {$subBoard}{description}
                                )
                              );
                            $ret{subCommunity}{language} =
                              $supportForumCategories{$cat}{$board}{$subBoard}
                              {language}
                              if (
                                defined(
                                    $supportForumCategories{$cat}{$board}
                                      {$subBoard}{language}
                                )
                              );
                            last;
                        }
                    }
                }
            }
        }
        last if ( defined( $ret{boardId} ) );
    }

    $ret{forum}    = $supportForum{forum};
    $ret{title}    = $supportForum{forum};
    $ret{language} = $supportForum{default_language}
      if ( defined( $ret{language} ) );
    $ret{web} = $supportForum{url};
    $ret{rss} = $supportForum{url} . $supportForum{rss};

    if ( defined( $ret{boardId} ) ) {
        $ret{title} .= ': ' . $ret{board};
        $ret{web}   .= $supportForum{uri};
        $ret{rss}   .= ';board=%BOARDID%';
        $ret{web} =~ s/%BOARDID%/$ret{boardId}/;
        $ret{rss} =~ s/%BOARDID%/$ret{boardId}/;

        if (   defined( $ret{subCommunity} )
            && defined( $ret{subCommunity}{boardId} ) )
        {
            $ret{subCommunity}{title}    = $supportForum{forum};
            $ret{subCommunity}{language} = $supportForum{default_language}
              unless ( defined( $ret{subCommunity}{language} ) );
            $ret{subCommunity}{web} = $supportForum{url};
            $ret{subCommunity}{rss} = $supportForum{url} . $supportForum{rss};

            $ret{subCommunity}{title} .= ': ' . $ret{subCommunity}{board};
            $ret{subCommunity}{web}   .= $supportForum{uri};
            $ret{subCommunity}{rss}   .= ';board=%BOARDID%';
            $ret{subCommunity}{web} =~ s/%BOARDID%/$ret{subCommunity}{boardId}/;
            $ret{subCommunity}{rss} =~ s/%BOARDID%/$ret{subCommunity}{boardId}/;
        }
    }
    else {
        $ret{web} .= '/';
    }

    return \%ret;
}

sub __GetUpdatedata {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my $fh;
    my @fileList;
    $coreUpdate         = undef;
    %corePackageUpdates = ();
    %coreFileUpdates    = ();
    %moduleUpdates      = ();
    %packageUpdates     = ();
    %fileUpdates        = ();

    # if there are 3rd party source file repositories involved
    if ( open( $fh, '<' . $attr{global}{modpath} . '/FHEM/controls.txt' ) ) {
        while ( my $l = <$fh> ) {
            push @fileList, 'FHEM/' . $1 if ( $l =~ m/([^\/\s]+)$/ );
        }
        close($fh);
    }

    # FHEM core update control file only
    else {
        push @fileList, 'controls_fhem.txt';
    }

    # loop through control files
    foreach my $file (@fileList) {
        if ( open( $fh, '<' . $attr{global}{modpath} . '/' . $file ) ) {
            my $filePrefix;
            my $srcRepoName;
            my $fileExtension;

            if ( $file =~ m/^([^_\s\.]+)_([^_\s\.]+)\.([^_\s\.]+)$/ ) {
                $filePrefix    = $1;
                $srcRepoName   = $2;
                $fileExtension = $3;
            }

            while ( my $l = <$fh> ) {
                if ( $l =~
m/^((\S+) (((....)-(..)-(..))_((..):(..):(..))) (\d+) (?:\.\/)?((.+\/)?((?:(\d+)_)?(.+)\.(.+))))$/
                  )
                {
                    # this is a FHEM core update
                    #   under path ./
                    if ( $2 eq 'UPD' && !$14 ) {

                        # core updates may only origin
                        #  from original fhem source repo
                        if ( $srcRepoName ne 'fhem' ) {
                            Log 1,
                                __PACKAGE__
                              . "::__GetUpdatedata: ERROR: Core file '"
                              . $13
                              . '\' can only be updated from FHEM original update server';
                            next;
                        }

                        my @update;
                        $update[0]  = $srcRepoName;     # source repository name
                        $update[1]  = $1;               # complete match
                        $update[2]  = $2;               # controls command
                        $update[3]  = $4 . ' ' . $8;    # date and time
                        $update[4]  = $4;               # date
                        $update[5]  = $5;               # year
                        $update[6]  = $6;               # month
                        $update[7]  = $7;               # day
                        $update[8]  = $8;               # time
                        $update[9]  = $9;               # hour
                        $update[10] = $10;              # minute
                        $update[11] = $11;              # second
                        $update[12] = $12;              # size in bytes
                        $update[13] = $13;              # relative file path
                        $update[14] = $14;              # relative path
                        $update[15] = $15;              # file name
                        $update[16] = $16;    # order number, may be undefined
                        $update[17] = $17;    # FHEM module name
                        $update[18] = $18;    # file extension

                        push @update,
                          fhemTimeGm(
                            $update[11], $update[10], $update[9], $update[7],
                            ( $update[6] - 1 ),
                            ( $update[5] - 1900 )
                          );

                        # this is a FHEM core update
                        if ( $15 eq 'fhem.pl' ) {
                            $coreUpdate = undef;
                            $coreUpdate = \@update;
                        }

                        # this is a FHEM core Perl package update
                        elsif ( $18 eq 'pm' ) {
                            delete $corePackageUpdates{$17}
                              if ( defined( $corePackageUpdates{$17} ) );
                            $corePackageUpdates{$17} = \@update;
                        }

                        # this is a FHEM core file update
                        else {
                            # our %coreFileUpdates;
                        }
                    }

                    # this is a FHEM module or Perl package update
                    #   under path ./FHEM/
                    elsif ( $2 eq 'UPD' && $14 eq 'FHEM/' && $18 eq 'pm' ) {
                        my @update;
                        $update[0]  = $srcRepoName;     # source repository name
                        $update[1]  = $1;               # complete match
                        $update[2]  = $2;               # controls command
                        $update[3]  = $4 . ' ' . $8;    # date and time
                        $update[4]  = $4;               # date
                        $update[5]  = $5;               # year
                        $update[6]  = $6;               # month
                        $update[7]  = $7;               # day
                        $update[8]  = $8;               # time
                        $update[9]  = $9;               # hour
                        $update[10] = $10;              # minute
                        $update[11] = $11;              # second
                        $update[12] = $12;              # size in bytes
                        $update[13] = $13;              # relative file path
                        $update[14] = $14;              # relative path
                        $update[15] = $15;              # file name
                        $update[16] = $16;    # order number, may be undefined
                        $update[17] = $17;    # FHEM module name
                        $update[18] = $18;    # file extension

                        push @update,
                          fhemTimeGm(
                            $update[11], $update[10], $update[9], $update[7],
                            ( $update[6] - 1 ),
                            ( $update[5] - 1900 )
                          );

                        # this is a FHEM module update
                        if ($16) {
                            if ( defined( $moduleUpdates{$17} ) ) {

                                # We're not overwriting update info
                                #  if source repo name does not match
                                if ( ref( $moduleUpdates{$17} ) eq 'ARRAY'
                                    && $moduleUpdates{$17}[0] ne $update[0] )
                                {
                                    Log 1,
                                        __PACKAGE__
                                      . "::__GetUpdatedata: ERROR: "
                                      . $update[13]
                                      . ' belongs to source repository "'
                                      . $moduleUpdates{$17}[0]
                                      . '". Ignoring identical file name from source repository '
                                      . $update[0];
                                    next;
                                }

                                else {
                                    delete $moduleUpdates{$17};
                                }
                            }

                            $moduleUpdates{$17} = \@update;
                        }

                        # this is a FHEM Perl package update
                        else {
                            if ( defined( $packageUpdates{$17} ) ) {

                                # We're not overwriting update info
                                #  if source repo name does not match
                                if ( ref( $packageUpdates{$17} ) eq 'ARRAY'
                                    && $packageUpdates{$17}[0] ne $update[0] )
                                {
                                    Log 1,
                                        __PACKAGE__
                                      . "::__GetUpdatedata: ERROR: "
                                      . $update[13]
                                      . ' belongs to source repository "'
                                      . $packageUpdates{$17}[0]
                                      . '". Ignoring identical file name from source repository '
                                      . $update[0];
                                    next;
                                }

                                else {
                                    delete $packageUpdates{$17};
                                }
                            }

                            $packageUpdates{$17} = \@update;
                        }
                    }

                    # this is a FHEM file update
                    #   under any other path
                    else {
                        # our %fileUpdates;
                    }
                }

                else {
                    Log 5,
                        __PACKAGE__
                      . "::__GetUpdatedata: $file: Ignoring line\n  "
                      . $l;
                }
            }
            close($fh);
        }
    }
}

# Set x_version based on existing metadata
sub __SetXVersion {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    my ($modMeta) = @_;
    my $modName = $modMeta->{x_file}[4];

    delete $modMeta->{x_version} if ( defined( $modMeta->{x_version} ) );

    # Special handling for fhem.pl
    if ( $modMeta->{x_file}[2] eq 'fhem.pl' ) {

        # only show maximum featurelevel
        #  and add revision separately
        $modMeta->{x_version} = 'fhem.pl:' . $1 . '-s' . $modMeta->{x_vcs}[5]
          if ( version->parse( $modMeta->{version} )->normal =~
            m/^(v\d+\.\d+).*/ );
    }

    # Generate extended version info based
    #   on base revision
    elsif ( defined( $modMeta->{x_vcs} ) ) {

        $modMeta->{x_version} =
          $modMeta->{x_file}[2] . ':'
          . (
            $modMeta->{version} <= 0.000000001 ? '?'
            : (
                $modMeta->{x_file}[7] ne 'generated/vcs'
                ? version->parse( $modMeta->{version} )->normal
                : $modMeta->{version}
            )
          )
          . (
            $modMeta->{x_file}[7] ne 'generated/vcs'
              && $modMeta->{x_vcs}[5] ne ''
            ? '-s'    # assume we only have Subversion for now
              . $modMeta->{x_vcs}[5]
            : ''
          );
    }

    # Generate generic version to fill the gap
    elsif ( $modMeta->{x_file}[7] eq 'generated/blank' ) {
        $modMeta->{x_version} = $modMeta->{x_file}[2] . ':?';
    }

    if ( defined( $modMeta->{x_version} ) ) {

        # Add modified date to extended version
        if ( defined( $modMeta->{x_vcs} ) ) {
            $modMeta->{x_version} .= '/' . $modMeta->{x_vcs}[7];

            # #FIXME can't use modified time because FHEM Update currently
            # #      does not set it based on controls_fhem.txt :-(
            # #      We need the block size from controls_fhem.txt here but
            # #      doesn't make sense to load that file here...
            # $modMeta->{x_version} .= '/' . $modMeta->{x_file}[6][9][2];
            # $modMeta->{x_version} .= '+modified'
            #   if ( defined( $modMeta->{x_vcs} )
            #     && $modMeta->{x_vcs}[16] ne $modMeta->{x_file}[6][9][0] );
        }
        else {
            $modMeta->{x_version} .= '/' . $modMeta->{x_file}[6][9][2];
        }

        # Add release status if != stable
        $modMeta->{x_version} .= ' ' . uc( $modMeta->{release_status} )
          if ( defined( $modMeta->{release_status} )
            && $modMeta->{release_status} ne 'stable' );
    }
}

1;

=pod

=encoding utf8

=for :application/json;q=META.json Meta.pm
{
  "abstract": "FHEM development package to enable Metadata support",
  "x_lang": {
    "de": {
      "abstract": "FHEM Entwickler Paket, um Metadaten Unterstützung zu aktivieren"
    }
  },
  "version": "v0.4.0",
  "release_status": "testing",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918623,
        "perl": 5.014,
        "GPUtils": 0,
        "File::stat": 0,
        "Data::Dumper": 0,
        "Encode": 0,
        "version": 0
      },
      "recommends": {
        "JSON": 0,
        "Perl::PrereqScanner::NotQuiteLite": 0,
        "Time::Local": 0
      },
      "suggests": {
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
