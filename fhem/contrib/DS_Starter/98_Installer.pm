#########################################################################################################################
# $Id: 98_Installer.pm 28622 2024-03-09 06:21:14Z CoolTux $
#########################################################################################################################
#       98_Installer.pm
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
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 98_Installer.pm
#  Zeilenenden auf LF umstellen: sed -i 's/\r$//' 98_Installer.pm
#
#########################################################################################################################

package main;

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

###############################################################
#                       Initialize
###############################################################
sub Installer_Initialize ($) {
  my ($modHash) = @_;

  $modHash->{SetFn}    = 'FHEM::Installer::Set';
  $modHash->{GetFn}    = 'FHEM::Installer::Get';
  $modHash->{DefFn}    = 'FHEM::Installer::Define';
  $modHash->{NotifyFn} = 'FHEM::Installer::Notify';
  $modHash->{UndefFn}  = 'FHEM::Installer::Undef';
  $modHash->{AttrFn}   = 'FHEM::Installer::Attr';

  my @attrs = (
      'disable:1,0',
      'disabledForIntervals',
      'installerMode:update,developer,install',
      'updateListReading:1,0',
      'updatePerlDualLifeModules:0,1',
      'updatePerlUsedModulesOnly:0,1',
      'installPerlReinstall:0,1',
      'installPerlNoTest:0,1',
      'installPerlEnforced:0,1',
  );

  $modHash->{AttrList} = join(' ', @attrs).' '.$readingFnAttributes;

return FHEM::Meta::InitMod(__FILE__, $modHash);
}

###############################################################
#                       Package
###############################################################
package FHEM::Installer;

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use GPUtils qw(GP_Import);
use Data::Dumper;
use Config;
use ExtUtils::Installed;
use B qw(svref_2object);

# Imports aus main:: (vor der Modul-Kompilierung)
BEGIN {
  GP_Import(qw(
      attr
      AttrVal
      cmds
      CommandAttr
      Debug
      defs
      deviceEvents
      devspec2array
      DoTrigger
      FW_webArgs
      gettimeofday
      init_done
      InternalTimer
      IsDisabled
      LoadModule
      Log
      Log3
      maxNum
      modules
      packages
      readingsBeginUpdate
      readingsBulkUpdate
      readingsBulkUpdateIfChanged
      readingsEndUpdate
      readingsSingleUpdate
      ReadingsTimestamp
      ReadingsVal
      RemoveInternalTimer
      TimeNow
      Value
  ));
}

###############################################################
# Gemeinsame Package-Spezifikation:
#   [@scope/]Name[@Version|latest]
###############################################################
my $pkgRe = qr/^(?:@([\w-]+)\/)?([\w\-\:]+)(?:@([v]?[\d\w\.=<>_-]+|latest))?$/;

# cpanm --version: Versionszeilen
my $cpanmVersionRe = qr/^cpanm (?:\([A-Za-z_:]+\) )?version (\d+\.\d+) (\([\w\/\.\-]+\)).*/i;
my $perlVersionRe  = qr/^perl version (\d+\.\d+) (\([\w\/\.\-]+\)).*/i;

# Shell-Meldungen "Programm nicht gefunden" (Paketname steht in $3)
my @notFoundRe = (qr/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?not.found$/i,
                  qr/(?:(\w+?): )?(?:(\w+? \d+): )?\w+?: [^:]*?not.found: (\S+)$/i,
                  qr/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?No.such.file.or.directory$/i,
                 );

# Wichtigkeit in META.json -> Anzeigetext
my %importance = (
    requires   => 'required',
    recommends => 'recommended',
    suggests   => 'suggested',
);

# Metadaten-Attribut -> Schlüssel in resources
my %resourceKey = (
    bugtracker         => 'bugtracker',
    homepage           => 'homepage',
    copyright          => 'x_copyright',
    privacy            => 'x_privacy',
    wiki               => 'x_wiki',
    community_support  => 'x_support_community',
    commercial_support => 'x_support_commercial',
    version_control    => 'repository',
);

## Konstanten
######################
use constant {
  HAS_METARequirementsRange => defined eval { require CPAN::Meta::Requirements::Range; },
  POLLINTERVAL              => 1,                                                               # Sekunden zwischen Abfragen des Subprozesses
  UPDATEINTERVAL            => 14400,                                                           # Sekunden zwischen zwei Update-Checks (4 Stunden)
};

###############################################################
# JSON-Modul laden
#   Reihenfolge = Präferenz (Performance / offener Code).
#   Das erste ladbare Modul gewinnt, decode_json und
#   encode_json werden in dieses Package importiert.
#
#   - JSON::MaybeXS : bevorzugter Wrapper
#   - JSON          : mit eigener Backend-Reihenfolge
#   - Cpanel::JSON::XS / JSON::XS : in seltenen Fällen
#                     installiert, obwohl JSON(::MaybeXS) fehlt
#   - JSON::PP      : Core-Modul (seit Perl 5.014)
#   - JSON::backportPP : letzter Fallback
###############################################################
my @jsonModules = qw(
    JSON::MaybeXS
    JSON
    Cpanel::JSON::XS
    JSON::XS
    JSON::PP
    JSON::backportPP
);

my $jsonModule;                                            # Name des geladenen JSON-Moduls, in Define geprüft

for my $candidate (@jsonModules) {
  my $loaded = eval {
      local $ENV{PERL_JSON_BACKEND} = 'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
        if($candidate eq 'JSON' && !defined $ENV{PERL_JSON_BACKEND});

      (my $file = $candidate.'.pm') =~ s{::}{/}g;
      require $file;
      $candidate->import(qw(decode_json encode_json));
      1;
  };

  if ($loaded) {
      $jsonModule = $candidate;
      last;
  }
}

###############################################################
# Abhängige FHEM-Module als Package laden, unabhängig davon
# ob der User auch FHEM-Devices definiert hat.
# Wir wollen deren Funktionen hier verwenden :-)
#TODO das soll Meta.pm für mich machen
###############################################################
#LoadModule('apt');
#LoadModule('pypip');
LoadModule('npmjs');

our %pkgStatus = ();

###############################################################
#                       Define
###############################################################
sub Define {
  my ($hash, $def) = @_;

  my @a = split(/[ \t]+/, $def);

  # ohne JSON-Modul ist das Device nicht funktionsfähig
  return "Installer: no JSON module available, please install JSON::PP" if(!$jsonModule);

  # Modul und Device initialisieren
  return $@ unless (FHEM::Meta::SetInternals ($hash));
  use version 0.77; our $VERSION = FHEM::Meta::Get($hash, 'version');

  my $name = $a[0];
  my $host = $a[2] ? $a[2] : 'localhost';                  # aktuell ungenutzt

  Undef($hash, undef) if($hash->{OLDDEF});                 # modify

  $hash->{NOTIFYDEV} = "global,$name";

  # nur eine Instanz erlaubt
  if (defined $modules{$hash->{TYPE}}{defptr}{localhost}) {
      return "Existing instance: ".$modules{$hash->{TYPE}}{defptr}{localhost}{NAME};
  }

  $modules{$hash->{TYPE}}{defptr}{localhost} = $hash;

  # Voreinstellungen für FHEMWEB
  if (!defined $hash->{OLDDEF}) {
      my @icons = (
          '.*updates.available:security@orange:outdatedPerl',
          'up.to.date:security@green:outdatedPerl',
          '.*outdated.*in.progress:system_fhem_reboot@orange',
          '.*in.progress:system_fhem_update@orange',
          'warning.*:message_attention@orange',
          'error\s.*Perl.*:message_attention@red',
      );



      $attr{$name}{alias}        = 'FHEM Installer Status';
      $attr{$name}{devStateIcon} = join(' ', @icons);
      $attr{$name}{group}        = 'Update';
      $attr{$name}{icon}         = 'system_fhem';
      $attr{$name}{room}         = 'System';
  }

  if (ReadingsVal ($name, 'state', 'none') ne 'none') {
      readingsSingleUpdate ($hash, 'state', 'initialized', 1);
  }

return;
}

###############################################################
#                       Undef
###############################################################
sub Undef {
  my ($hash, $arg) = @_;

  my $name = $hash->{NAME};

  if (exists $hash->{".fhem"}{subprocess}) {
      my $subprocess = $hash->{".fhem"}{subprocess};
      $subprocess->terminate();
      $subprocess->wait();
  }

  RemoveInternalTimer ($hash);

  delete $modules{$hash->{TYPE}}{defptr}{localhost};

return;
}

###############################################################
#                       Attr
###############################################################
sub Attr {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $hash = $defs{$name};

  if ($attrName eq 'disable') {
      if ($cmd eq 'set' && $attrVal eq '1') {
          RemoveInternalTimer  ($hash);
          readingsSingleUpdate ($hash, 'state', 'disabled', 1);
          Log3 ($name, 3, "Installer ($name) - disabled");
      }
      elsif ($cmd eq 'del') {
          Log3 ($name, 3, "Installer ($name) - enabled");
      }
  }
  elsif ($attrName eq 'disabledForIntervals') {
      if ($cmd eq 'set') {
          if ($attrVal !~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/) {
              return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'";
          }

          Log3 ($name, 3, "Installer ($name) - disabledForIntervals");
          readingsSingleUpdate ($hash, 'state', 'disabled', 1);
      }
      elsif ($cmd eq 'del') {
          Log3 ($name, 3, "Installer ($name) - enabled");
          readingsSingleUpdate ($hash, 'state', 'active', 1);
      }
  }

return;
}

###############################################################
#                       Notify
###############################################################
sub Notify {
  my ($hash, $dev) = @_;

  my $name = $hash->{NAME};
  return if(IsDisabled($name));

  my $devname = $dev->{NAME};
  my $devtype = $dev->{TYPE};
  my $events  = deviceEvents ($dev, 1);
  return if(!$events);

  Log3 ($name, 5, "Installer ($name) - Notify: ".Dumper $events);

  my $inst     = ($hash->{".fhem"}{installer} //= {});
  my $isGlobal = ($devname eq 'global');

  # Events, die ein (Neu-)Laden der Daten auslösen
  my $evDefine = grep { /^DEFINED.$name$/ || /^DELETEATTR.$name.disable$/ || /^ATTR.$name.disable.0$/ } @{$events};
  my $evInit   = grep { /^INITIALIZED$/   || /^REREADCFG$/   || /^MODIFIED.$name$/ }                    @{$events};

  if ($isGlobal && (($evDefine && $init_done) || $evInit)) {

      # Metadaten aller verwendeten Module laden
      FHEM::Meta::Load();

      # Perl-Paketliste aus Reading wiederherstellen
      my $pkgList = eval { decode_json(ReadingsVal($name, '.packageListPerl', '')) };
      if (!$@) {
          $inst->{cpanversions}         = $pkgList->{versions}     if(defined $pkgList->{versions});
          $inst->{listedPerlPackages}   = $pkgList->{listedPerl}   if(defined $pkgList->{listedPerl});
          $inst->{outdatedPerlPackages} = $pkgList->{outdatedPerl} if(defined $pkgList->{outdatedPerl});
      }

      # weitere Listen 1:1 aus Readings wiederherstellen
      my %restore = (
          '.installedListPerl'   => 'installedPerlPackages',
          '.uninstalledListPerl' => 'uninstalledPerlPackages',
          '.updatedListPerl'     => 'updatedPerlPackages',
      );

      for my $reading (sort keys %restore) {
          my $list = eval { decode_json(ReadingsVal($name, $reading, '')) };
          next if($@);
          $inst->{$restore{$reading}} = $list;
      }

      # Update anstoßen
      if (ReadingsVal ($name, 'cpanminusVersion', 'none') ne 'none') {
          ProcessUpdateTimer ($hash);
      }
      else {
          $inst->{cmd} = 'getCpanVersion';
          AsynchronousExecuteFhemCommand ($hash);
      }
  }

  # nach erfolgreicher Aktion die Liste veralteter Pakete neu holen
  if ($devname eq $name && grep { /^(?:installedPerl|uninstalledPerl|updatedPerl):.successful$/ } @{$events}) {
      $inst->{cmd} = 'outdatedPerl';
      AsynchronousExecuteFhemCommand ($hash);
  }

return;
}

###############################################################
#   Liste aktualisierbarer Perl-Pakete (berücksichtigt die
#   Attribute updatePerlDualLifeModules / updatePerlUsedModulesOnly)
###############################################################
sub UpdatablePerlPackages {
  my ($hash, $name) = @_;

  my $outdated = $hash->{".fhem"}{installer}{outdatedPerlPackages};
  return () unless(defined $outdated);

  my $dualLife = AttrVal ($name, 'updatePerlDualLifeModules', 0);
  my $usedOnly = AttrVal ($name, 'updatePerlUsedModulesOnly', 0);

  my @pkgs;

  for my $pkg (sort keys %{$outdated}) {
      next if(!$dualLife && FHEM::Meta::ModuleIsPerlCore($pkg));
      next if($usedOnly  && !defined $FHEM::Meta::dependents{pkgs}{$pkg});
      push @pkgs, $pkg;
  }

return @pkgs;
}

###############################################################
#                       Set
###############################################################
sub Set {
  my ($hash, $name, @aa) = @_;

  my ($cmd, @args) = @aa;
  my $opt  = lc($cmd // '');
  my $inst = ($hash->{".fhem"}{installer} //= {});
  my $ret;
  
  # nur ein Hintergrundkommando gleichzeitig
  if (exists $hash->{".fhem"}{subprocess} && $opt =~ /^(?:outdatedperl|statusrequest|updateperl|installperl|uninstallperl|zzimportperllist)$/) {
      return "Another command ('".($inst->{cmd} // '?')."') is still in progress, please wait until it has finished.";
  }

  if ($opt eq 'outdatedperl') {
      $inst->{cmd} = $cmd;
  }
  elsif ($opt eq 'statusrequest') {
      $inst->{cmd} = 'getCpanVersion';
  }
  elsif ($opt eq 'updateperl') {
      my $outdated = $inst->{outdatedPerlPackages};
      return "Please run outdatedPerl check first" unless(defined $outdated);

      # ohne Argument oder 'all': explizite Liste aller aktualisierbaren Pakete
      if (!@args || lc($args[0]) eq 'all') {
          @args = map  { $_.'@'.$outdated->{$_}{latest} }
                  grep { $_ ne 'undefined' }
                  UpdatablePerlPackages ($hash, $name);
      }

      my @update;

      for my $pkgfull (@args) {
          next unless($pkgfull =~ $pkgRe);

          my ($pkg, $ver) = ($2, $3);
          next unless(defined $outdated->{$pkg});

          push @update, $pkg.(($ver && $ver ne 'latest') ? '@'.$ver : '');
      }

      return "Everything is up-to-date already" unless(@update);

      $inst->{cmd} = 'installPerl '.join(' ', @update);
      $ret         = 'Update started in background';
  }
  elsif ($opt eq 'installperl') {
      return "usage: $cmd <package>" if(@args < 1);

      $inst->{cmd} = 'installPerl '.join(' ', @args);
      $ret         = 'Installation started in background';
  }
  elsif ($opt eq 'uninstallperl') {
      return "usage: $cmd <package>" if(@args < 1);

      return "cpanminus cannot be uninstalled from here"
        if(grep { m/^(?:@([\w-]+)\/)?(?:App::)?(cpanm(?:inus)?)(?:@([\d\.=<>]+|latest))?$/i } @args);

      return "cpan-outdated cannot be uninstalled from here"
        if(grep { m/^(?:@([\w-]+)\/)?(?:App::)?(cpan\-?outdated)(?:@([\d\.=<>]+|latest))?$/i } @args);

      $inst->{cmd} = 'uninstallPerl '.join(' ', @args);
      $ret         = 'Deinstallation started in background';
  }
  elsif ($opt eq 'zzexportperllist') {
      return "usage: $cmd <filename>" if(@args != 1);
      return ExportPerlList ($hash, $args[0]);
  }
  elsif ($opt eq 'zzimportperllist') {
      return "usage: $cmd <filename>" if(@args != 1);
      return ImportPerlList ($hash, $args[0]);
  }
  else {
      my $list;

      if (!defined $inst->{cpanversions}) {
          $list .= 'installPerl:App::cpanminus statusRequest:noArg';
      }
      elsif (!defined $inst->{cpanversions}{cpanoutdated}) {
          $list .= 'installPerl:App::cpanoutdated statusRequest:noArg';
      }
      else {
          my @update = UpdatablePerlPackages ($hash, $name);
          
          $list .= ' outdatedPerl:noArg';
          $list .= ' installPerl';
          $list .= ' uninstallPerl';
          $list .= ' zzExportPerlList:textField,/<path>/<filename>';
          $list .= ' zzImportPerlList:textField,/<path>/<filename>';         
          $list .= ' updatePerl:all,'.join(',', @update) if(@update);
      }

      return "Unknown argument $cmd, choose one of $list";
  }

  AsynchronousExecuteFhemCommand ($hash);

return $ret;
}

###############################################################
#   Exportiert die installierten Perl-Pakete in eine Datei
###############################################################
sub ExportPerlList {
  my ($hash, $filename) = @_;

  my $name      = $hash->{NAME};
  my $localList = _LocalPerlPackages ($hash);

  return 'Please run outdatedPerl check first to populate the package list' unless($localList);

  my %export  = map { $_ => { version => $localList->{$_} } } keys %{$localList};
  my $jsonStr = eval { $jsonModule->new->utf8->canonical->pretty->encode(\%export) };

  return 'JSON encoding error' if($@ || !defined $jsonStr);

  open(my $fh, '>', $filename) or return "Error opening file $filename for writing: $!";
  binmode($fh);

  my $ok = print {$fh} $jsonStr;
  $ok    = close($fh) && $ok;

  return "Error writing file $filename: $!" unless($ok);

  Log3 ($name, 3, "Installer ($name) - exported ".(scalar keys %export)." Perl packages to $filename");

return 'Export successful: '.(scalar keys %export)." Perl packages written to $filename";
}

###############################################################
#   Importiert eine Perl-Paketliste und startet die Installation
#   fehlender und älterer Pakete
###############################################################
sub ImportPerlList {
  my ($hash, $filename) = @_;

  my $name = $hash->{NAME};
  my $inst = ($hash->{".fhem"}{installer} //= {});

  my ($fileList, $error) = _ReadPerlListFile ($hash, $filename);
  return $error if($error);

  my $localList = _LocalPerlPackages ($hash);

  return 'Please run outdatedPerl check first to populate the package list' unless($localList);

  my $diff      = _ComparePerlLists ($fileList, $localList);
  my @toInstall = map { _InstallSpec ($_->[0], $_->[1]) } (@{$diff->{missing}}, @{$diff->{outdated}});

  return "All Perl packages from $filename are already installed in the required version." unless(@toInstall);

  $inst->{cmd} = 'installPerl '.join(' ', @toInstall);

  Log3 ($name, 3, "Installer ($name) - import from $filename: installing ".scalar(@toInstall)." Perl packages");

  AsynchronousExecuteFhemCommand ($hash);

return 'Installation started in background for '.scalar(@{$diff->{missing}}).' missing and '.scalar(@{$diff->{outdated}}).' outdated package(s)';
}

###############################################################
#   Lokal installierte Perl-Pakete (Name => Version)
#   aus dem letzten Ergebnis von outdatedPerl
###############################################################
sub _LocalPerlPackages {
  my $hash = shift;

  my $listed = $hash->{".fhem"}{installer}{listedPerlPackages};

  return unless(ref $listed eq 'HASH');

  my %local;

  for my $pkg (keys %{$listed}) {
      next if($pkg eq 'CPAN::outdated');

      my $version  = ref $listed->{$pkg} eq 'HASH' ? $listed->{$pkg}{version} : undef;
      $local{$pkg} = $version // 0;
  }

return \%local;
}

###############################################################
#   Exportierte Paketliste (JSON) einlesen
#   liefert (Hash-Referenz, undef) oder (undef, Fehlertext)
###############################################################
sub _ReadPerlListFile {
  my ($hash, $filename) = @_;

  my $name = $hash->{NAME};

  return (undef, "File $filename does not exist") unless(-f $filename);

  open(my $fh, '<', $filename) or return (undef, "Error opening file $filename for reading: $!");
  binmode($fh);

  my $jsonStr = do { local $/; <$fh> };

  close($fh);

  my $list = eval { decode_json ($jsonStr // '') };

  if ($@ || ref $list ne 'HASH') {
      Log3 ($name, 3, "Installer ($name) - invalid package list in $filename: ".($@ || 'not a JSON object'));

      return (undef, "Invalid package list format in $filename");
  }

return ($list, undef);
}

###############################################################
#   Versionen vergleichen (numifizierte Versionen)
#   -1: $v1 < $v2, 1: $v1 > $v2, 0: gleich oder nicht vergleichbar
###############################################################
sub _CompareVersions {
  my ($v1, $v2) = @_;

  for my $v ($v1, $v2) {
      return 0 if(!defined $v || $v eq '' || $v eq '0');
  }

  my $cmp = eval { version->parse($v1) <=> version->parse($v2) };

return $@ ? 0 : $cmp;
}

###############################################################
#   Paketliste aus Datei mit den lokalen Paketen vergleichen
#   Ergebnis: { missing, outdated, newer, extra }, jeweils eine
#   Liste von [Paket, Version in Datei, lokale Version]
###############################################################
sub _ComparePerlLists {
  my ($fileList, $localList) = @_;

  my %diff = (missing => [], outdated => [], newer => [], extra => []);

  for my $pkg (sort keys %{$fileList}) {
      next if($pkg eq 'Perl' || $pkg eq 'undefined');

      my $fileVer = ref $fileList->{$pkg} eq 'HASH' ? $fileList->{$pkg}{version} : undef;

      if (!exists $localList->{$pkg}) {
          push @{$diff{missing}}, [$pkg, $fileVer, undef];
          next;
      }

      my $cmp = _CompareVersions ($localList->{$pkg}, $fileVer);

      push @{$diff{outdated}}, [$pkg, $fileVer, $localList->{$pkg}] if($cmp < 0);
      push @{$diff{newer}},    [$pkg, $fileVer, $localList->{$pkg}] if($cmp > 0);
  }

  for my $pkg (sort keys %{$localList}) {
      next if($pkg eq 'Perl' || exists $fileList->{$pkg});
      next if($pkg eq 'App::cpanminus' || $pkg eq 'App::cpanoutdated');

      push @{$diff{extra}}, [$pkg, undef, $localList->{$pkg}];
  }

return \%diff;
}

# Paketangabe für die Installation: Name@Version, wenn die Version brauchbar ist
sub _InstallSpec {
  my ($pkg, $version) = @_;

return (defined $version && $version =~ /^\d+(?:\.\d+)*$/ && $version ne '0') ? $pkg.'@'.$version : $pkg;
}

###############################################################
#                       Get
###############################################################
sub Get {
  my ($hash, $name, @aa) = @_;

  my ($cmd, @args) = @aa;
  my $opt = lc($cmd // '');

  if ($opt eq 'showoutdatedperllist') {
      return "usage: $cmd" if(@args);
      return CreateOutdatedPerlList ($hash, $cmd);
  }
  elsif ($opt eq 'showinstalledperllist') {
      return "usage: $cmd" if(@args);
      return CreateInstalledPerlList ($hash, $cmd);
  }
  elsif ($opt eq 'checkprereqs') {
      return CreatePrereqsList ($hash, $cmd, @args);
  }
  elsif ($opt eq 'search') {
      return CreateSearchList ($hash, $cmd, @args);
  }
  elsif ($opt eq 'showmoduleinfo' || $opt eq 'showpackageinfo') {
      my $what = $opt eq 'showmoduleinfo' ? 'MODULE' : 'PACKAGE';
      return "usage: $cmd $what" if(@args != 1);
      return CreateMetadataList ($hash, $cmd, $args[0]);
  }
  elsif ($opt eq 'zzgetmodulemetajson' || $opt eq 'zzgetpackagemetajson') {
      my $what = $opt eq 'zzgetmodulemetajson' ? 'MODULE' : 'PACKAGE';
      return "usage: $cmd $what" if(@args != 1);
      return CreateRawMetaJson ($hash, $cmd, $args[0]);
  }
  elsif ($opt eq 'showerrorlist') {
      return "usage: $cmd" if(@args);
      return CreateErrorList ($hash);
  }
  elsif ($opt eq 'showdiffperllist') {
      return "usage: $cmd <filename>" if(@args != 1);
      return CreateDiffPerlList ($hash, $cmd, $args[0]);
  }

  my $list;
  my $inst          = ($hash->{".fhem"}{installer} //= {});
  my $installerMode = AttrVal ($name, 'installerMode', 'update');

  my @fhemModules = grep { $_ ne 'Global' && ($installerMode ne 'update' || defined $modules{$_}{LOADED}) }
                    sort { lc($a) cmp lc($b) } keys %modules;

  $list .= ' search showModuleInfo:FHEM,'.join(',', @fhemModules);

  if ($installerMode eq 'developer') {
      my $pkgs = join(',', sort { lc($a) cmp lc($b) } keys %packages);

      $list .= ' showPackageInfo:'.$pkgs;
      $list .= ' zzGetModuleMETAjson:FHEM,'.join(',', @fhemModules);
      $list .= ' zzGetPackageMETAjson:'.$pkgs;
  }

  $list .= ' checkPrereqs';

  if ($installerMode eq 'install') {
      my $dir = $attr{global}{modpath};
      my @cfg;

      if (opendir(my $dh, $dir)) {
          @cfg = sort grep { /\.cfg$/ && !-d "$dir/$_" } readdir($dh);
          closedir($dh);
      }

      $list .= ':'.join(',', @cfg) if(@cfg);
  }
  elsif ($installerMode eq 'update') {
      $list .= ':noArg';
  }

  $list .= ' showOutdatedPerlList:noArg' if(UpdatablePerlPackages($hash, $name));
  $list .= ' showDiffPerlList:textField,/<path>/<filename>';

  $list .= ' showInstalledPerlList:noArg'
    if(defined $inst->{listedPerlPackages} && scalar keys %{$inst->{listedPerlPackages}});

  $list .= ' showErrorList:noArg'
    if(defined $inst->{errors} && scalar @{$inst->{errors}});

return "Unknown argument $cmd, choose one of $list";
}

###############################################################
#   Differenzliste zwischen exportierter Datei und System
###############################################################
sub CreateDiffPerlList {
  my ($hash, $getCmd, $filename) = @_;

  my $t = __GetLayout ($hash);

  my ($fileList, $error) = _ReadPerlListFile ($hash, $filename);
  return $error if($error);

  my $localList = _LocalPerlPackages ($hash);

  return 'Please run outdatedPerl check first to populate the package list' unless($localList);

  my $diff  = _ComparePerlLists ($fileList, $localList);
  my $red   = $t->{colorRed};
  my $close = $t->{colorClose};
  my $ver   = sub { my $v = shift; return (defined $v && $v ne '' && $v ne '0') ? $v : '?' };
  my @rows;

  for my $e (@{$diff->{missing}}) {
      my ($pkg, $fileVer) = @{$e};
      push @rows, [$pkg, $ver->($fileVer), 'not installed', $red.'Missing'.$close,
                   __DiffActionLink ($hash, $t, 'installPerl', _InstallSpec ($pkg, $fileVer), 'Install')];
  }

  for my $e (@{$diff->{outdated}}) {
      my ($pkg, $fileVer, $localVer) = @{$e};
      push @rows, [$pkg, $ver->($fileVer), $ver->($localVer), $red.'Outdated'.$close,
                   __DiffActionLink ($hash, $t, 'installPerl', _InstallSpec ($pkg, $fileVer), 'Update')];
  }

  for my $e (@{$diff->{newer}}) {
      my ($pkg, $fileVer, $localVer) = @{$e};
      push @rows, [$pkg, $ver->($fileVer), $ver->($localVer), 'Newer locally', '-'];
  }

  for my $e (@{$diff->{extra}}) {
      my ($pkg, undef, $localVer) = @{$e};
      push @rows, [$pkg, '-', $ver->($localVer), $red.'Extra'.$close,
                   __DiffActionLink ($hash, $t, 'uninstallPerl', $pkg, 'Deinstall', "Really uninstall $pkg?")];
  }

  push @rows, ['All packages match the exported file.', '', '', '', ''] unless(@rows);

  my $title = "Perl Package Diff: $filename";

  if ($t->{html}) {
      $title =~ s/&/&amp;/g;
      $title =~ s/</&lt;/g;
  }

  my @ret = __TableHeader ($t, $title, 'Package', 'File Version', 'Local Version', 'Status', 'Action');

  my $linecount = 1;
  push @ret, __TableRow ($t, $linecount++, @{$_}) for (@rows);

  push @ret, $t->{tClose}.$t->{blockClose};

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#  Aktions-Link (FHEMWEB) bzw. Text für die Diff-Tabelle
#  mit Sicherheitsrückfrage bei Deinstall
###############################################################
sub __DiffActionLink {
  my ($hash, $t, $cmd, $arg, $label, $confirm) = @_;

  return $label unless($t->{html});

  my $href = '?cmd=set '.$hash->{NAME}.' '.$cmd.' '.$arg.' '.$t->{csrf};
  
  if ($confirm) {
      $confirm =~ s/'/\\'/g;
      
      my $js = "
        var existing = document.getElementById('fhemCustomModal');
        if(existing) existing.remove();
        var bodyBg = window.getComputedStyle(document.body).backgroundColor;
        var isDark = false;
        if (bodyBg) {
            var rgb = bodyBg.match(/\\d+/g);
            if (rgb && rgb.length >= 3) {
                var brightness = (parseInt(rgb[0]) * 299 + parseInt(rgb[1]) * 587 + parseInt(rgb[2]) * 114) / 1000;
                if (brightness < 100) isDark = true;
            }
        }
        var bgCol = isDark ? '#2a2a2a' : '#f8f8f8';
        var borderCol = isDark ? '#555' : '#4e6f3e';
        var textCol = isDark ? '#f0f0f0' : '#333';
        var cancelBg = isDark ? '#555' : '#ccc';
        var cancelText = isDark ? '#fff' : '#333';
        var overlay = document.createElement('div');
        overlay.id = 'fhemCustomModal';
        overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:99999;display:flex;align-items:center;justify-content:center;';
        var box = document.createElement('div');
        box.style.cssText = 'background:' + bgCol + ';border:2px solid ' + borderCol + ';padding:22px;border-radius:6px;box-shadow:0 8px 24px rgba(0,0,0,0.4);max-width:400px;text-align:center;font-family:sans-serif;color:' + textCol + ';';
        var text = document.createElement('div');
        text.style.cssText = 'margin-bottom:20px;font-size:14px;line-height:1.4;';
        text.innerText = '$confirm';
        var btnContainer = document.createElement('div');
        var btnOk = document.createElement('button');
        btnOk.innerText = 'OK';
        btnOk.style.cssText = 'margin-right:10px;padding:6px 18px;background:#4e6f3e;color:#fff;border:none;border-radius:4px;cursor:pointer;font-weight:bold;';
        btnOk.onclick = function() { window.location.href = '$href'; };
        var btnCancel = document.createElement('button');
        btnCancel.innerText = 'Abbrechen';
        btnCancel.style.cssText = 'padding:6px 18px;background:' + cancelBg + ';color:' + cancelText + ';border:none;border-radius:4px;cursor:pointer;';
        btnCancel.onclick = function() { overlay.remove(); };
        btnContainer.appendChild(btnOk);
        btnContainer.appendChild(btnCancel);
        box.appendChild(text);
        box.appendChild(btnContainer);
        overlay.appendChild(box);
        document.body.appendChild(overlay);
        return false;
      ";
      
      $js =~ s/\n/ /g;

      return '<div class="detLink installerAction"><a href="#" onclick="' . $js . '">' . $label . '</a></div>';
  }

return '<div class="detLink installerAction"><a href="' . $href . '">' . $label . '</a></div>';
}

###############################################################
#                       Event
###############################################################
sub Event {
  my ($hash, $event) = @_;

  my $name = $hash->{NAME};
  my $cmd  = $hash->{".fhem"}{installer}{cmd};

  return unless(defined $cmd && $cmd =~ m/^(install|uninstall|update)(?: (.+))/i);

  my ($action, $pkgs) = ($1, $2);
  my @list;

  for my $package (split / /, $pkgs) {
      next unless($package =~ $pkgRe);
      push @list, $2;
  }

  DoModuleTrigger ($hash, uc($event).uc($action)." $name ".join(' ', @list));

return;
}

###############################################################
#                       DoModuleTrigger
###############################################################
sub DoModuleTrigger {
  my ($hash, $eventString, $noreplace, $TYPE) = @_;

  $hash      = $defs{$hash}  unless(ref $hash);
  $noreplace = 1             unless(defined $noreplace);
  $TYPE      = $hash->{TYPE} unless(defined $TYPE);

  return '' unless(defined $TYPE
                   && defined $modules{$TYPE}
                   && defined $eventString
                   && $eventString =~ m/^([A-Za-z\d._]+)(?:\s+([A-Za-z\d._]+)(?:\s+(.+))?)?$/);

  my $event = $1;
  my $dev   = $2;

  return "DoModuleTrigger() can only handle module related events"
    if(($hash->{NAME} && $hash->{NAME} eq 'global') || ($dev // '') eq 'global');

  # globales Event auf Modulebene
  return DoTrigger ('global', "$TYPE:$eventString", $noreplace)
    unless($event =~ /^INITIALIZED|INITIALIZING|MODIFIED|DELETED|BEGIN(?:UPDATE|INSTALL|UNINSTALL)|END(?:UPDATE|INSTALL|UNINSTALL)$/);

  # globales Event auf Modulebene im Device-Kontext
  return "$event: missing device name" if(!defined $dev || $dev eq '');

return DoTrigger ('global', "$TYPE:$eventString", $noreplace);
}

###############################################################
#                  Update-Timer
###############################################################
sub ProcessUpdateTimer {
  my $hash = shift;

  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash);
  InternalTimer(gettimeofday() + UPDATEINTERVAL, 'FHEM::Installer::ProcessUpdateTimer', $hash, 0);

  Log3 ($name, 4, "Installer ($name) - stateRequestTimer: Call Request Timer");

  return if(IsDisabled($name));

  if (exists $hash->{".fhem"}{subprocess}) {
      Log3 ($name, 2, "Installer ($name) - update in progress, process aborted.");
      return 0;
  }

  my $state = ReadingsVal ($name, 'state', 'none');

  if ($state eq 'none' || $state eq 'initialized') {
      readingsSingleUpdate ($hash, 'state', 'ready', 1);
  }

  # Datum der letzten outdatedPerl-Prüfung
  my $lastCheck = (split(' ', ReadingsTimestamp($name, 'outdatedPerl', '1970-01-01')))[0];

  if (__ToDay() ne $lastCheck || $state eq 'disabled') {
      $hash->{".fhem"}{installer}{cmd} = 'outdatedPerl';
      AsynchronousExecuteFhemCommand ($hash);
  }

return;
}

###############################################################
#                  Subprocess aufräumen
###############################################################
sub CleanSubprocess {
  my $hash = shift;

  my $name = $hash->{NAME};

  delete $hash->{".fhem"}{subprocess};

  Log3 ($name, 4, "Installer ($name) - clean Subprocess");

return;
}

###############################################################
#     Kommando asynchron in einem Subprozess ausführen
###############################################################
sub AsynchronousExecuteFhemCommand {
  my $hash = shift;

  require "SubProcess.pm";

  my $name = $hash->{NAME};
  my $inst = ($hash->{".fhem"}{installer} //= {});

  my $subprocess           = SubProcess->new({ onRun => \&OnRun });
  $subprocess->{installer} = $inst;                                             # gleiche Referenz wie in $hash

  $inst->{debug} = AttrVal($name, 'verbose', 0) > 3 ? 1 : 0;

  # cpanm-Optionen aus den Attributen
  my %cpanmOpts = (
      installPerlReinstall => '--reinstall ',
      installPerlNoTest    => '--notest ',
      installPerlEnforced  => '--force ',
  );

  for my $attrName (sort keys %cpanmOpts) {
      $inst->{$attrName} = AttrVal ($name, $attrName, 0) ? $cpanmOpts{$attrName} : '';
  }

  my $pid = $subprocess->run();

  readingsSingleUpdate ($hash, 'state', "command '$inst->{cmd}' in progress", 1);

  if (!defined $pid) {
      Log3 ($name, 1, "Installer ($name) - Cannot execute command asynchronously");

      CleanSubprocess      ($hash);
      readingsSingleUpdate ($hash, 'state', 'Cannot execute command asynchronously', 1);

      return;
  }

  Event ($hash, 'BEGIN');
  Log3  ($name, 4, "Installer ($name) - execute command asynchronously (PID= $pid)");

  $hash->{".fhem"}{subprocess} = $subprocess;

  InternalTimer(gettimeofday() + POLLINTERVAL, 'FHEM::Installer::PollChild', $hash, 0);

  Log3 ($name, 4, "Installer ($name) - control passed back to main loop.");

return;
}

###############################################################
#           Subprozess auf Ergebnis abfragen
###############################################################
sub PollChild {
  my $hash = shift;

  my $name       = $hash->{NAME};
  my $subprocess = $hash->{".fhem"}{subprocess};

  # Subprocess-Objekt fehlt oder ist ungültig
  if (!ref $subprocess || ref $subprocess ne 'SubProcess') {
      my $error = (defined $subprocess && ref $subprocess) ? ($subprocess->{lasterror} // '') : '';
      my $emsg  = $error ne '' ? '{"error":"'.$error.'"}' : '{"error":"Child process suddenly ended"}';

      Log3 ($name, 5, "Installer ($name) - $emsg");

      CleanSubprocess ($hash);
      PreProcessing   ($hash, $emsg);

      return;
  }

  my $json = $subprocess->readFromChild();

  # noch kein Ergebnis -> erneut abfragen
  if (!defined $json) {
      Log3 ($name, 5, "Installer ($name) - still waiting (".$subprocess->{lasterror}.").");
      InternalTimer(gettimeofday() + POLLINTERVAL, 'FHEM::Installer::PollChild', $hash, 0);

      return;
  }

  Log3 ($name, 4, "Installer ($name) - got result from asynchronous parsing.");

  $subprocess->wait();

  Log3 ($name, 4, "Installer ($name) - asynchronous finished.");

  CleanSubprocess ($hash);
  PreProcessing   ($hash, $json);

return;
}

####################################################################################################
#                                       Begin Childprocess
####################################################################################################
###############################################################
#                  Subprozess: Einstieg
###############################################################
sub OnRun {
  my $subprocess = shift;

  my $response = ExecuteFhemCommand ($subprocess->{installer});

  my $json = eval { encode_json ($response) };

  if ($@) {
      Log3 ('Installer OnRun', 3, "Installer - JSON error: $@");
      $json = "{\"jsonerror\":\"$@\"}";
  }

  $subprocess->writeToParent($json);

return;
}

###############################################################
#     Kommando aufbauen und den passenden Handler starten
###############################################################
sub ExecuteFhemCommand {
  my $cmd = shift;

  my $installer = { debug => $cmd->{debug} };

  my $locale = 'LC_ALL=C';
  my $sudo   = $locale.' sudo -n ';                        # aktuell ungenutzt
  my $sudoH  = $locale.' sudo -H -n ';

  $installer->{cpanversions}  = 'echo n | TEST=$(which cpanm) || echo "sh: command not found: cpanm"; '
                              . 'which cpanm >/dev/null 2>&1 && sh -c "'.$sudoH.' $(which cpanm) --version 2>&1" 2>&1';

  $installer->{installperl}   = 'echo n | sh -c "'.$sudoH.' $(which cpanm) --quiet '
                              . $cmd->{installPerlReinstall}
                              . $cmd->{installPerlNoTest}
                              . $cmd->{installPerlEnforced}
                              . '%PACKAGES%" 2>&1';

  $installer->{uninstallperl} = 'echo n | sh -c "'.$sudoH.' $(which cpanm) -U --quiet --force %PACKAGES%" 2>&1';

  $installer->{outdatedperl}  = 'echo n | sh -c "'.$sudoH.' $(which cpanm) --version 2>&1" 2>&1 && '
                              . 'L1=$('.' cpan-outdated --verbose 2>&1) && '
                              . '[ "$L1" != "" ] && [ "$L1" != "\n" ] && echo "@Outdated:\n$L1"; ';

  my $response;

  if ($cmd->{cmd} =~ /^installperl (.+)/i) {
      my $args     = $1;
      my $versions = $cmd->{cpanversions};                                      # bereits bekannte Versionen (kein Kommando!)

      if (!defined $versions || !defined $versions->{cpanminus}) {              # cpanminus fehlt: nur die Installation von App::cpanminus ist möglich
          if ($args =~ /App::cpanminus/i) {
              $installer->{installperl} = 'sh -c "( curl -fsSL https://git.io/cpanm 2>/dev/null || wget -qO- https://git.io/cpanm 2>/dev/null ) | '
                                        . $sudoH
                                        . '$(which perl) - App::cpanminus >/dev/null 2>&1" 2>&1 '
                                        . '&& TEST=$(which cpanm) || echo "sh: command not found: cpanm"; which cpanm >/dev/null 2>&1 && sh -c "'
                                        . $sudoH
                                        . ' $(which cpanm) --quiet App::cpanoutdated" 2>&1';
          }
      }
      else {
          my $pkglist = join(' ', __ParsePackages($args, 1));
          return if($pkglist eq '');

          $installer->{installperl} =~ s/%PACKAGES%/$pkglist/gi;
      }

      __Debug ($installer, $installer->{installperl});
      $response = CpanInstall ($installer);
  }
  elsif ($cmd->{cmd} =~ /^uninstallperl (.+)/i) {
      my $pkglist = join(' ', __ParsePackages($1, 0));
      return if($pkglist eq '');

      $installer->{uninstallperl} =~ s/%PACKAGES%/$pkglist/gi;

      __Debug ($installer, $installer->{uninstallperl});
      $response = CpanUninstall ($installer);
  }
  elsif (lc($cmd->{cmd}) eq 'outdatedperl') {
      __Debug ($installer, $installer->{outdatedperl});
      $response = CpanOutdated ($installer);
  }
  elsif (lc($cmd->{cmd}) eq 'getcpanversion') {
      __Debug ($installer, $installer->{cpanversions});
      $response = GetCpanVersion ($installer);
  }

return $response;
}

###############################################################
#                  Hilfsfunktionen
###############################################################

# Debug-Ausgabe (landet im Log des Hauptprozesses)
sub __Debug {
  my ($cmd, $text) = @_;

  print "$text\n" if($cmd->{debug});

return;
}

# Paketliste "[@scope/]Name[@Version|latest] ..." -> Paketnamen
# $withVersion: Versionsangabe (außer 'latest') mit übernehmen
sub __ParsePackages {
  my ($list, $withVersion) = @_;

  my @packages;

  for my $package (split / /, $list) {
      next unless($package =~ $pkgRe);
      push @packages, $2.(($withVersion && $3 && $3 ne 'latest') ? '@'.$3 : '');
  }

return @packages;
}

# Fehler-Hash; 'detail' nur wenn als 3. Argument übergeben
sub __NewError {
  my ($code, $summary) = @_;

  my $error = { code => $code, summary => $summary };
  $error->{detail} = $_[2] if(@_ > 2);

return $error;
}

sub __NoOutputError {
  my $p = shift;

return __NewError ('E500', 'Unknown error - Missing command output', $p);
}

# "not found" in einer Zeile erkennen -> E404 oder undef
sub __MatchNotFound {
  my $line = shift;

  for my $re (@notFoundRe) {
      return __NewError ('E404', "Not Found - $3 is not installed", $line) if($line =~ $re);
  }

return;
}

# Fehler "passwordless sudo erforderlich" mit Hinweis auf die sudoers-Zeilen
# @bins: 'cpanm' und/oder 'perl' (Reihenfolge = Reihenfolge der Zeilen)
sub __SudoError {
  my ($line, @bins) = @_;

  my $user   = scalar getpwuid($<);
  my $prefix = "  $user ALL=(ALL) NOPASSWD:SETENV: ";
  my @rules;

  for my $bin (@bins) {
      my $path = `which $bin`;
      $path    =~ s/\n//g;

      push @rules, $bin eq 'cpanm' ? $prefix.$path.' *' : $prefix.$path.' - App\:\:cpanminus';
  }

  my $detail = $line
             . '<br /><br />'
             . "You may add the following lines to /etc/sudoers.d/$user:\n"
             . '<pre>'.join("\n", @rules).'</pre>';

return __NewError ('E403', 'Forbidden - passwordless sudo permissions required', $detail);
}

# cpan-outdated vorhanden?
sub __CheckCpanOutdated {
  my $h = shift;

  my $cpanoutdated             = `which cpan-outdated`;
  $h->{versions}{cpanoutdated} = 0 if($cpanoutdated =~ /^\/.+/);

return;
}

###############################################################
#                  cpanm-Version ermitteln
###############################################################
sub GetCpanVersion {
  my $cmd = shift;

  my $h            = {};
  local $ENV{PATH} = __GetExtendedEnvPath();

  my $p = `$cmd->{cpanversions}`;

  if (!$p) {
      push @{$h->{error}}, __NoOutputError($p);
  }
  else {
      my $found   = 0;
      my $section = '';                                    # Config | ENV | INC

      for my $line (split /\n/, $p) {
          __Debug ($cmd, $line);

          if ($line =~ $cpanmVersionRe) {
              $h->{versions}{cpanminus} = $1;
              $found = 1;
          }
          elsif ($line =~ $perlVersionRe) {
              $h->{versions}{perl} = $1;
          }
          elsif ($line =~ /^\s+\%Config:.*$/i) {
              $section = 'Config';
          }
          elsif ($line =~ /^\s+\%ENV:.*$/i) {
              $section = 'ENV';
          }
          elsif ($line =~ /^\s+\@INC:.*$/i) {
              $section = 'INC';
          }
          elsif ($section) {
              $line =~ s/^\s+//;

              if ($section eq 'INC') {
                  push @{$h->{versions}{INC}}, $line unless($line =~ /^.+=.+$/);
              }
              else {
                  my ($key, $value) = split(/=/, $line, 2);
                  $h->{versions}{$section}{$key} = $value;
              }
          }
          elsif (!$found) {                                # Fehler
              my $error = __MatchNotFound ($line);

              if (!$error && $line =~ m/^sudo: /i) {
                  $error = __SudoError($line, 'cpanm', 'perl');
              }

              $error //= __NewError ('E501', 'Parsing error', $p);

              push @{$h->{error}}, $error;
              last;
          }
      }
  }

  __CheckCpanOutdated ($h);

return $h;
}

###############################################################
#                  Perl-Pakete installieren
###############################################################
sub CpanInstall {
  my $cmd = shift;

  my $h = {};
  local $ENV{PATH} = __GetExtendedEnvPath();

  eval { umask 0022; 1; };

  my $p = `$cmd->{installperl}`;

  if (!$p) {
      push @{$h->{error}}, __NoOutputError ($p);

      return $h;
  }

  $h->{success} = 0;

  for my $line (split /\n/, $p) {
      __Debug ($cmd, $line);
      
      if ($line =~ /^Successfully\s+(\S+)\s+([\S]+)-(v?\d+(?:\.\d+(?:_\d+)?)?).*$/i) {
          my ($result, $module, $version) = ($1, $2, $3);
          $module =~ s/-/::/g;

          $h->{installed}{$module}{result}  = $result;
          $h->{installed}{$module}{version} = $version;
          $h->{success}++;
      }
      elsif ($line =~ /^(\S+)\s+is\s+up\s+to\s+date.*\((\d+(?:\.\d+(?:_\d+)?)?)\).*$/i) {
          $h->{installed}{$1}{result}  = 'existing';
          $h->{installed}{$1}{version} = $2;
          $h->{success}++;
      }
      elsif ($line =~ /^(\d+)\s+(\S+)\s+(\S+)$/i) {
          # Gesamtergebnis ignorieren
      }
      elsif ($line =~ /^\!\s+(.+)$/i) {
          my $summary = $1;
          my $code    = $summary =~ /^Couldn't find.*/i ? 'E404' : 'E500';

          push @{$h->{error}}, __NewError ($code, $summary);
      }
      elsif (my $error = __MatchNotFound ($line)) {
          push @{$h->{error}}, $error;
          last;
      }
      elsif ($line =~ m/^curl:.*Failed writing body.*$/i) {
          push @{$h->{error}}, __SudoError ($line, 'perl');
          last;
      }
      elsif ($line =~ m/^sudo: /i) {
          push @{$h->{error}}, __SudoError ($line, 'cpanm');
          last;
      }
      elsif ($line =~ /^(?:.*\/)?tar:\s+Ignoring unknown extended header keyword/i) {
          # Harmlose tar-Meldungen ignorieren
      }
      else {
          push @{$h->{error}}, __NewError ('E501', 'Parsing error', $line);
      }
  }

return $h;
}

###############################################################
#                  Perl-Pakete deinstallieren
###############################################################
sub CpanUninstall {
  my $cmd = shift;

  my $h = {};
  local $ENV{PATH} = __GetExtendedEnvPath();

  my $p = `$cmd->{uninstallperl}`;

  if (!$p) {
      push @{$h->{error}}, __NoOutputError ($p);

      return $h;
  }

  $h->{success} = 0;

  for my $line (split /\n/, $p) {
      __Debug ($cmd, $line);
      next if($line eq '');

      if ($line =~ /^Successfully\s+(\S+)\s+([\S]+).*$/i) {
          $h->{uninstalled}{$2}{result} = $1;
          $h->{success}++;
      }
      elsif ($line =~ /^\!\s(\S+)\s+is\s+not\s+found.*$/i) {
          $h->{uninstalled}{$1}{result} = 'not installed';
          $h->{success}++;
      }
      elsif ($line =~ /^\!\s+(.+)$/i) {
          push @{$h->{error}}, __NewError ('E500', $1);
      }
      elsif (my $error = __MatchNotFound ($line)) {
          push @{$h->{error}}, $error;
          last;
      }
      elsif ($line =~ m/^sudo: /i) {
          push @{$h->{error}}, __SudoError ($line, 'cpanm');
          last;
      }
      elsif ($line =~ m/^\s+.*$/) {
          # Zeilen mit führenden Leerzeichen ignorieren
      }
      else {
          push @{$h->{error}}, __NewError ('E501', 'Parsing error', $line);
      }
  }

return $h;
}

###############################################################
#     Veraltete Perl-Pakete und installierte Module ermitteln
###############################################################
sub CpanOutdated {
  my $cmd = shift;

  my $h = {};
  local $ENV{PATH} = __GetExtendedEnvPath();

  my $p = `$cmd->{outdatedperl}`;

  if (!$p) {
      push @{$h->{error}}, __NoOutputError ($p);
  }
  else {
      my $found   = 0;
      my $section = '';                                    # Config | ENV | INC | Outdated

      for my $line (split /\n/, $p) {
          __Debug ($cmd, $line);

          if ($line =~ $cpanmVersionRe) {
              $h->{versions}{cpanminus} = $1;
              $found = 1;
          }
          elsif ($line =~ $perlVersionRe) {
              $h->{versions}{perl} = $1;
          }
          elsif ($line =~ /^\s+\%Config:.*$/i) {
              $section = 'Config';
          }
          elsif ($line =~ /^\s+\%ENV:.*$/i) {
              $section = 'ENV';
          }
          elsif ($line =~ /^\s+\@INC:.*$/i) {
              $section = 'INC';
          }
          elsif ($line =~ /^\@Outdated:.*$/i) {
              $section = 'Outdated';
          }
          elsif ($section eq 'Outdated') {
              next if($line =~ /^\s*$/);                    # Leere Zeilen ignorieren
              if ($line =~ /^([\w\-\:]+)\s+([\d\w\.\-_]+)\s+([\d\w\.\-_]+)\s+(\S+)$/) {
                  my ($pkg, $current, $latest) = ($1, $2, $3);
                  $pkg =~ s/-/::/g;
                  $h->{outdatedPerl}{$pkg}{current} = $current;
                  $h->{outdatedPerl}{$pkg}{latest}  = $latest;
              }
              else {
                  $found = 0;
              }
          }
          
          elsif ($section) {
              $line =~ s/^\s+//;

              if ($section eq 'INC') {
                  push @{$h->{versions}{INC}}, $line;
              }
              else {
                  my ($key, $value) = split(/=/, $line, 2);
                  $h->{versions}{$section}{$key} = $value;
              }
          }

          # Fehler (wird für jede Zeile geprüft)
          if (!$found) {
              push @{$h->{error}}, (__MatchNotFound ($line) // __NewError ('E501', 'Parsing error', $p));
              last;
          }
      }
  }

  __CheckCpanOutdated ($h);

  # installierte Perl-Module auflisten
  my $ExtUtilsInstalled = ExtUtils::Installed->new();

  for my $module ($ExtUtilsInstalled->modules()) {
      next if($module eq 'CPAN::outdated');

      my ($missing) = $ExtUtilsInstalled->validate($module);
      my $version   = $ExtUtilsInstalled->version($module);

      $h->{listedPerl}{$module}{missing} = $missing if($missing);

      my $numified = eval { version->parse($version)->numify };
      $h->{listedPerl}{$module}{version} = $numified // 0;
  }

return $h;
}
####################################################################################################
#                                       End Childprocess
####################################################################################################

###############################################################
#     JSON-Ergebnis des Subprozesses verarbeiten
###############################################################
sub PreProcessing {
  my ($hash, $json) = @_;

  my $name = $hash->{NAME};

  my $decode_json = eval { decode_json($json) };

  if ($@) {
      Log3 ($name, 2, "Installer ($name) - JSON error: $@");
      return;
  }

  Log3 ($name, 4, "Installer ($name) - JSON: $json");

  my $inst = ($hash->{".fhem"}{installer} //= {});
  my $cmd  = $inst->{cmd};

  if (defined $decode_json->{versions} && defined $decode_json->{versions}{cpanminus}) {
      $inst->{cpanversions} = $decode_json->{versions};
  }

  # Ergebnis zusätzlich in verstecktem Reading ablegen, um den Modulzustand nach einem Neustart wiederherzustellen
  if ($cmd eq 'outdatedPerl') {
      delete $inst->{outdatedPerlPackages};
      delete $inst->{listedPerlPackages};

      $inst->{outdatedPerlPackages} = $decode_json->{outdatedPerl} if(defined $decode_json->{outdatedPerl});
      $inst->{listedPerlPackages}   = $decode_json->{listedPerl}   if(defined $decode_json->{listedPerl});

      readingsSingleUpdate ($hash, '.packageListPerl', $json, 0);
  }
  else {
      my @lists = (                                        # Kommando-Regex, Schlüssel, Reading
          [qr/^install/,   'installedPerlPackages',   '.installedListPerl'  ],
          [qr/^uninstall/, 'uninstalledPerlPackages', '.uninstalledListPerl'],
          [qr/^update/,    'updatedPerlPackages',     '.updatedListPerl'    ],
      );

      for my $list (@lists) {
          next unless($cmd =~ $list->[0]);

          $inst->{$list->[1]} = $decode_json;
          readingsSingleUpdate($hash, $list->[2], $json, 0);
          last;
      }
  }

  if (defined $decode_json->{warning} || defined $decode_json->{error}) {
      $inst->{warnings} = $decode_json->{warning} if(defined $decode_json->{warning});
      $inst->{errors}   = $decode_json->{error}   if(defined $decode_json->{error});
  }
  else {
      delete $inst->{warnings};
      delete $inst->{errors};
  }

  WriteReadings ($hash, $decode_json);

return;
}

###############################################################
#                  Readings schreiben
###############################################################
sub WriteReadings {
  my ($hash, $decode_json) = @_;

  my $name = $hash->{NAME};
  my $inst = $hash->{".fhem"}{installer};
  my $cmd  = $inst->{cmd};

  Log3 ($name, 4, "Installer ($name) - Write Readings");
  Log3 ($name, 5, "Installer ($name) - ".Dumper $decode_json);

  readingsBeginUpdate ($hash);

  if ($cmd eq 'outdatedPerl') {
      readingsBulkUpdate ($hash, 'outdatedPerl', defined $decode_json->{listedPerl} ? 'check completed' : 'check failed');

      $hash->{helper}{lastSync} = __ToDay();
      
      my $upp  = scalar(UpdatablePerlPackages($hash, $name));
      $upp   //= 0;

      readingsBulkUpdateIfChanged ($hash, 'updatesAvailablePerl', $upp);
  }

  if (AttrVal($name, 'updateListReading', 0)) {
      my $list = eval { encode_json($inst->{outdatedPerlPackages}) };
      readingsBulkUpdateIfChanged ($hash, 'updateListAsJSON', $list);
  }

  my $result = 'successful';
  $result    = 'error'   if(defined $inst->{errors});
  $result    = 'warning' if(defined $inst->{warnings});

  readingsBulkUpdate ($hash, 'installedPerl',   $result) if($cmd =~ /^installperl /i);
  readingsBulkUpdate ($hash, 'uninstalledPerl', $result) if($cmd =~ /^uninstallperl /i);
  readingsBulkUpdate ($hash, 'updatedPerl',     $result) if($cmd =~ /^updateperl /i);

  my $versions = $decode_json->{versions};

  if (defined $versions) {
      readingsBulkUpdateIfChanged ($hash, 'cpanminusVersion', $versions->{cpanminus}) if(defined $versions->{cpanminus});
      readingsBulkUpdateIfChanged ($hash, 'perlVersion',      $versions->{perl})      if(defined $versions->{perl});
  }

  if (defined $decode_json->{error}) {
      readingsBulkUpdate ($hash, 'state', "error '$cmd'");
  }
  elsif (defined $decode_json->{warning}) {
      readingsBulkUpdate ($hash, 'state', "warning '$cmd'");
  }
  else {
      readingsBulkUpdate ($hash, 'state', UpdatablePerlPackages($hash, $name) ? 'updates available' : 'up to date');
  }

  Event             ($hash, 'FINISH');
  readingsEndUpdate ($hash, 1);

  ProcessUpdateTimer ($hash) if($cmd eq 'getCpanVersion' && !defined $decode_json->{error});

return;
}

###############################################################
#     Layout-Bausteine für die Ausgabe (FHEMWEB-HTML oder Text)
###############################################################
sub __GetLayout {
  my $hash = shift;

  my $html = (defined $hash->{CL} && $hash->{CL}{TYPE} eq 'FHEMWEB') ? 1 : 0;

  delete $FW_webArgs{addLinks};                            # keine automatischen Links auf FHEM-Devices

  my %t = (
      html        => $html,
      header      => '',
      footer      => '',
      blockOpen   => '',
      blockClose  => '',
      tTitleOpen  => '',
      tTitleClose => '',
      tOpen       => '',
      tClose      => '',
      tCOpen      => '',
      tCClose     => '',
      tHOpen      => '',
      tHClose     => '',
      tBOpen      => '',
      tBClose     => '',
      tFOpen      => '',
      tFClose     => '',
      trOpen      => '',
      trOpenEven  => '',
      trOpenOdd   => '',
      trClose     => '',
      thOpen      => '',
      thClose     => "\t\t\t",
      tdOpen      => '',
      tdOpen1     => '',
      tdOpen2     => '',
      tdOpen3     => '',
      tdOpen4     => '',
      tdClose     => "\t\t\t",
      strongOpen  => '',
      strongClose => '',
      colorRed    => '',
      colorGreen  => '',
      colorClose  => '',
      space       => ' ',
      lb          => "\n",
  );

  if ($html) {
      %t = (%t,
          header      => '<html>',
          footer      => '</html>',
          blockOpen   => '<div class="makeTable wide internals">',
          blockClose  => '</div>',
          tTitleOpen  => '<span class="mkTitle">',
          tTitleClose => '</span>',
          tOpen       => '<table class="block wide internals wrapcolumns">',
          tClose      => '</table>',
          tCOpen      => '<caption style="text-align: left; font-size: larger;">',
          tCClose     => '</caption>',
          tHOpen      => '<thead>',
          tHClose     => '</thead>',
          tBOpen      => '<tbody>',
          tBClose     => '</tbody>',
          tFOpen      => '<tfoot style="font-size: smaller;">',
          tFClose     => '</tfoot>',
          trOpen      => '<tr class="column">',
          trOpenEven  => '<tr class="column even">',
          trOpenOdd   => '<tr class="column odd">',
          trClose     => '</tr>',
          thOpen      => '<th style="text-align: left; vertical-align: top;">',
          thClose     => '</th>',
          tdOpen      => '<td style="vertical-align: top;">',
          tdOpen1     => '<td style="vertical-align: top;" colspan="1">',
          tdOpen2     => '<td style="vertical-align: top;" colspan="2">',
          tdOpen3     => '<td style="vertical-align: top;" colspan="3">',
          tdOpen4     => '<td style="vertical-align: top;" colspan="4">',
          tdClose     => '</td>',
          strongOpen  => '<strong>',
          strongClose => '</strong>',
          colorRed    => '<span style="color: red">',
          colorGreen  => '<span style="color: green">',
          colorClose  => '</span>',
          space       => '&nbsp;',
          lb          => '<br />',
      );
  }

  $t{lang} = lc(AttrVal($hash->{NAME}, 'language', AttrVal('global', 'language', 'EN')));
  $t{csrf} = $html ? __CsrfParam ($hash) : '';

return \%t;
}

# Kopfzeilen einer Tabelle
sub __TableHeader {
  my ($t, $title, @cols) = @_;

  my @ret = ($t->{blockOpen}.$t->{tOpen}.$t->{tCOpen}.$title.$t->{tCClose}.$t->{tHOpen}.$t->{trOpen});

  push @ret, $t->{thOpen}.$_.$t->{thClose} for (@cols);
  push @ret, $t->{trClose}.$t->{tHClose};

return @ret;
}

# Tabellenzeile (gerade/ungerade abwechselnd)
sub __TableRow {
  my ($t, $linecount, @cells) = @_;

  my $row = $linecount % 2 == 0 ? $t->{trOpenEven} : $t->{trOpenOdd};

  $row .= $t->{tdOpen}.$_.$t->{tdClose} for (@cells);
  $row .= $t->{trClose};

return $row;
}

# CSRF-Parameter für Links in FHEMWEB
sub __CsrfParam {
  my $hash = shift;

  my $token = $defs{$hash->{CL}{SNAME}}{CSRFTOKEN};

return defined $token ? '&fwcsrf='.$token : '';
}

###############################################################
#                  Fehlerliste
###############################################################
sub CreateErrorList {
  my $hash = shift;

  my $t      = __GetLayout ($hash);
  my $errors = $hash->{".fhem"}{installer}{errors};
  my @ret;

  if (ref $errors eq 'ARRAY' && scalar @{$errors} > 0) {
      push @ret, __TableHeader ($t, 'Error List', 'No.', 'Error Code', 'Description');

      my $linecount = 1;

      for my $error (@{$errors}) {
          my $detail = '';

          if (defined $error->{detail} && $error->{detail} ne '') {
              $detail = $t->{lb}.$t->{lb}.$t->{strongOpen}.'Detail:'.$t->{strongClose}.$t->{lb}.$error->{detail};
          }

          push @ret, __TableRow ($t, $linecount, $linecount, $error->{code}, $error->{summary}.$detail);
          $linecount++;
      }

      push @ret, $t->{tClose}.$t->{blockClose};
  }
  else {
      push @ret, 'No errors occured during last command.';
  }

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#                  Liste installierter Perl-Pakete
###############################################################
sub CreateInstalledPerlList {
  my ($hash, $getCmd) = @_;

  my $t        = __GetLayout ($hash);
  my $packages = $hash->{".fhem"}{installer}{listedPerlPackages};
  my @ret;

  if (ref $packages eq 'HASH' && scalar keys %{$packages} > 0) {
      push @ret, __TableHeader ($t, 'Installed Perl Packages', 'Name', 'Version');

      my $linecount = 1;

      for my $package (sort { lc($a) cmp lc($b) } keys %{$packages}) {
          next if($package eq 'undefined');

          my $version = $packages->{$package}{version};

          push @ret, __TableRow ($t, $linecount, $package, $version ? $version : '?');
          $linecount++;
      }

      push @ret, $t->{tClose}.$t->{blockClose};
  }
  else {
      push @ret, 'No installed Perl packages found.';
  }

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#                  Liste veralteter Perl-Pakete
###############################################################
sub CreateOutdatedPerlList {
  my ($hash, $getCmd) = @_;

  my $t        = __GetLayout ($hash);
  my $name     = $hash->{NAME};
  my $packages = $hash->{".fhem"}{installer}{outdatedPerlPackages};
  my @ret;

  if (ref $packages eq 'HASH') {
      my @updatable = UpdatablePerlPackages ($hash, $name);

      if (@updatable) {
          my %isUpdatable = map { $_ => 1 } @updatable;

          push @ret, __TableHeader ($t, 'Outdated Perl Packages', 'Name', 'Current Version', 'Latest Version');

          my $linecount = 1;

          for my $package (sort { lc($a) cmp lc($b) } keys %{$packages}) {
              next if($package eq 'undefined');
              next unless ($isUpdatable{$package});

              my $current = $packages->{$package}{current};
              my $latest  = $packages->{$package}{latest};

              push @ret, __TableRow ($t, $linecount, $package, defined $current ? $current : '?', defined $latest ? $latest : '?');
              $linecount++;
          }
      }
      else {
          push @ret, 'No outdated Perl packages found.';
      }
  }

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#                  Voraussetzungen prüfen
###############################################################
sub CreatePrereqsList {
  my $hash    = shift;
  my $getCmd  = shift;
  my $cfgfile = shift;

  my $mode = ($cfgfile && $cfgfile eq '1') ? 'all' : ($cfgfile ? 'file' : 'live');
  $mode    = 'list' if($cfgfile && defined $modules{$cfgfile});

  my @defined;

  if ($mode eq 'live' || $mode eq 'all') {
      for my $module (keys %modules) {
          next unless($mode eq 'all' || defined $modules{$module}{LOADED});
          push @defined, $module;
      }
  }
  elsif ($mode eq 'file') {
      @defined = __GetDefinedModulesFromFile ($cfgfile);

      return "File $cfgfile does not seem to contain any FHEM device configuration" unless(@defined > 0);
  }
  elsif ($mode eq 'list') {
      @defined = ($cfgfile, @_);
  }

  my $t       = __GetLayout ($hash);
  my $html    = $t->{html};
  my $FW_CSRF = $html ? __CsrfParam($hash) : '';
  my @ret;

  # Perl-Voraussetzungen ermitteln
  LoadInstallStatusPerl(($defined[0] // '') eq '1' ? 1 : \@defined);

  my %description = (
      Required    => 'Required dependencies '.$t->{strongOpen}.'must'.$t->{strongClose}.' be installed for the listed FHEM modules to work.',
      Recommended => 'Recommended dependencies are '.$t->{strongOpen}.'strongly encouraged'.$t->{strongClose}
                     .' and should be installed for full functionality of the listed FHEM modules, except in resource constrained environments.',
      Suggested   => 'Suggested dependencies are '.$t->{strongOpen}.'optional'.$t->{strongClose}
                     .', but are suggested for enhanced operation of the listed FHEM modules.',
  );

  my $found = 0;
  my %count = (required => 0, recommended => 0, suggested => 0);

  # Voraussetzungen anzeigen
  for my $mAttr (qw(required recommended suggested)) {
      for my $area (qw(Perl Node.js Python)) {
          my $items = defined $pkgStatus{$mAttr} ? $pkgStatus{$mAttr}{$area} : undef;
          next unless(ref $items eq 'HASH' && keys %{$items});

          my $linecount  = 1;
          my $importance = ucfirst($mAttr);

          for my $item (sort { lc($a) cmp lc($b) } keys %{$items}) {
              my $info    = $items->{$item};
              my $linkmod = '';
              my $inScope = 0;

              for my $modName (sort { lc($a) cmp lc($b) } @{$info->{modules}}) {
                  # Paket nur anzeigen, wenn ein Modul im Installationsumfang es verwendet
                  $inScope = 1 if(grep { $_ eq $modName } @defined);

                  my $modLabel = $modName eq 'Global' ? 'FHEM' : $modName;

                  $linkmod .= ', ' unless($linkmod eq '');
                  $linkmod .= $html
                            ? '<a href="?cmd=get '.$hash->{NAME}.' showModuleInfo '.$modName.$FW_CSRF.'">'.$modLabel.'</a>'
                            : $modLabel;
              }

              next unless($inScope);

              $found++;
              $count{$mAttr}++;

              my $linkitem = $html ? '<a href="https://metacpan.org/pod/'.$item.'" target="_blank">'.$item.'</a>' : $item;

              my $action   = '<div class="detLink installerAction"><a href="?cmd=set '.$hash->{NAME}.' installPerl '.$item.' '.$FW_CSRF
                           . '" title="Click here to trigger installation">Install</a></div>';

              my $itemText = $linkitem.($info->{status} eq 'outdated' ? ' (wanted version: '.$info->{version}.')' : '');

              my @cells    = ($itemText, $area, $linkmod);
              push @cells, $action if($html);

              if ($linecount == 1) {
                  push @ret, $t->{trOpen}
                           . $t->{tdOpen}
                           . ($html ? '<a name="prereqResult'.$importance.'"></a>' : '')
                           . $t->{blockOpen}
                           . $t->{tOpen}
                           . $t->{tCOpen}
                           . $importance
                           . $t->{tCClose};

                  push @ret, $t->{tHOpen}.$t->{trOpen};
                  push @ret, $t->{thOpen}.'Item'.$t->{thClose};
                  push @ret, $t->{thOpen}.'Type'.$t->{thClose};
                  push @ret, $t->{thOpen}.'Used by'.$t->{thClose};
                  push @ret, $t->{thOpen}.'Action'.$t->{thClose} if($html);
                  push @ret, $t->{trClose}.$t->{tHClose}.$t->{tBOpen};
              }

              push @ret, __TableRow ($t, $linecount, @cells);
              $linecount++;
          }

          next unless ($linecount > 1);

          if ($html) {
              my $action = '<div class="detLink installerAction"><a href="?cmd=set '.$hash->{NAME}.' install'.ucfirst($area).' all-'.$mAttr.$FW_CSRF
                         . '" title="Click here to trigger installation">Install '.$mAttr.' '.ucfirst($area).'</a></div>';

              push @ret, ($linecount % 2 == 0 ? $t->{trOpenEven} : $t->{trOpenOdd})
                       . $t->{tdOpen3}
                       . $t->{tdClose}
                       . $t->{tdOpen1}
                       . $action
                       . $t->{tdClose}
                       . $t->{trClose};
          }

          push @ret, $t->{tBClose};
          push @ret, $t->{tFOpen}.($html ? $t->{tdOpen4} : $t->{tdOpen3}).$description{$importance}.$t->{tFClose};
          push @ret, $t->{tClose}.$t->{blockClose}.$t->{tdClose}.$t->{trClose};
      }
  }

  if ($found) {
      push @ret, $t->{tBClose};

      if (defined $pkgStatus{Perl}{analyzed}) {
          push @ret, $t->{tFOpen}
                   . $t->{trOpen}
                   . $t->{tdOpen}
                   . $t->{strongOpen}.'Hint:'.$t->{strongClose}
                   . ' Some of the FHEM modules in use do not provide Perl prerequisites from its metadata.'
                   . $t->{lb};

          if ($pkgStatus{Perl}{analyzed} == 1) {
              push @ret, 'This check is based on automatic source code analysis and can be incorrect.'
                       . ' Suggested Perl items may still be required if the module author had decided to implement some own dependency and/or error handling like returning an informative message instead of the original Perl error message.';
          }
          elsif ($pkgStatus{Perl}{analyzed} == 2) {
              push @ret, 'This check may be incomplete until you '
                       . ($html
                          ? '<a href="?cmd=set '.$hash->{NAME}.' installPerl Perl::PrereqScanner::NotQuiteLite'.$FW_CSRF
                            .'">click here to install Perl::PrereqScanner::NotQuiteLite</a> '
                          : 'install Perl::PrereqScanner::NotQuiteLite ')
                       . 'for automatic source code analysis.';
          }

          push @ret, $t->{tdClose}.$t->{trClose}.$t->{tFClose};
      }

      # Zusammenfassung an den Anfang stellen
      my @summary = (
          $t->{tBOpen}.$t->{trOpen}.$t->{tdOpen},
          $t->{blockOpen}.$t->{blockClose},
          $found.' total missing '.($found > 1 ? 'prerequisites:' : 'prerequisite:'),
      );

      for my $mAttr (qw(required recommended suggested)) {
          next unless($count{$mAttr});

          push @summary, $t->{lb}.$t->{space}.$t->{space}
                       . ($html ? '<a href="#prereqResult'.ucfirst($mAttr).'">' : '')
                       . $count{$mAttr}.' '.$mAttr.' '.($count{$mAttr} > 1 ? 'items' : 'item')
                       . ($html ? '</a>' : '');
      }

      push @summary, $t->{lb}.$t->{lb}.$t->{tdClose}.$t->{trClose};

      unshift @ret, @summary;
  }
  else {
      my @hooray = ('hooray', 'hurray', 'phew', 'woop woop', 'woopee', 'wow', 'yay', 'yippie');
      my $word   = $hooray[int(rand(scalar @hooray))];

      unshift @ret, $t->{tBOpen}
                  . $t->{trOpen}
                  . $t->{tdOpen}
                  . $t->{lb}
                  . ucfirst($word).'! All prerequisites are met.'
                  . ($html ? ' 🥳' : '')
                  . $t->{lb}
                  . $t->{lb}
                  . $t->{tdClose}
                  . $t->{trClose}
                  . $t->{tBClose};
  }

  push @ret, $t->{tClose}.$t->{blockClose};

  unshift @ret, $t->{blockOpen}
              . $t->{blockClose}
              . ($html ? '<a name="prereqResultTOP"></a>' : '')
              . $t->{blockOpen}
              . $t->{tTitleOpen}
              . ($mode eq 'live' ? 'Live ' : '')
              . 'System Prerequisites Check'
              . $t->{tTitleClose}
              . $t->{tOpen};

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#                  Suche
###############################################################
sub CreateSearchList {
  my $hash   = shift;
  my $getCmd = shift;
  my $search = join('\s*', @_);
  $search    = '.+' unless($search);

  my $t    = __GetLayout($hash);
  my $html = $t->{html};
  my $lb   = $t->{lb};
  my $name = $hash->{NAME};
  my @ret;
  my %found;

  # Suchfeld
  if ($html) {
      my $token     = $defs{$hash->{CL}{SNAME}}{CSRFTOKEN};
      my $csrfInput = defined $token ? '<input type="hidden" name="fwcsrf" value="'.$token.'">' : '';

      $t->{header} .= '<div class="wide">'
                    . '<form id="fhemsearch" method="get" action="?" onsubmit="cmd.value = \'get '.$name.' search \'+ q.value" style="float: left; margin-right: 2em;">'
                    . $csrfInput
                    . '<input type="hidden" name="cmd" value="">'
                    . '<label for="q" style="margin-right: 0.5em;">Search:</label>'
                    . '<input type="text" name="q" id="q" value="'.$search.'" autocorrect="off" autocapitalize="off">'
                    . '</form>'
                    . '<div class="detLink installerBack" style="float: right"><a href="?detail='.$name.'">&larr; back to FHEM Installer</a></div>'
                    . '</div>';
  }

  # passende Devices
  my @rows;

  for my $device (sort { lc($a) cmp lc($b) } keys %defs) {
      my $type = $defs{$device}{TYPE};

      next unless(defined $type && !defined $defs{$device}{TEMPORARY} && defined $modules{$type});
      next unless($device =~ /$search/i);

      FHEM::Meta::Load($type);

      my $linkDev = $html ? '<a href="?detail='.$device.$t->{csrf}.'">'.$device.'</a>' : $device;
      my $state   = defined $defs{$device}{STATE} ? $defs{$device}{STATE} : '';

      push @rows, [$linkDev, __InfoLink ($hash, $t, 'module', $type), $state];
  }

  $found{devices} = scalar @rows;
  push @ret, __SearchTable($t, 'searchResultDevices', 'Devices', ['Device Name', 'Device Type', 'Device State'], \@rows) if(@rows);

  # passende Module
  @rows = ();

  for my $module (sort { lc($a) cmp lc($b) } keys %modules) {
      next unless($module =~ /$search/i);

      FHEM::Meta::Load ($module);

      push @rows, [__InfoLink ($hash, $t, 'module', $module), __MetaAbstract($modules{$module})];
  }

  $found{modules} = scalar @rows;
  push @ret, __SearchTable ($t, 'searchResultModules', 'Modules', ['Module Name', 'Abstract'], \@rows) if(@rows);

  # passende Packages
  @rows = ();

  for my $package (sort { lc($a) cmp lc($b) } keys %packages) {
      next unless($package =~ /$search/i);

      FHEM::Meta::Load ($package);

      push @rows, [__InfoLink ($hash, $t, 'package', $package), __MetaAbstract($packages{$package})];
  }

  $found{packages} = scalar @rows;
  push @ret, __SearchTable ($t, 'searchResultPackages', 'Packages', ['Package Name', 'Abstract'], \@rows) if(@rows);

  # passende Keywords (je Keyword eine eigene Tabelle, Zeilenzähler läuft durch)
  my $linecount    = 1;
  $found{keywords} = 0;

  for my $keyword (sort { lc($a) cmp lc($b) } keys %FHEM::Meta::keywords) {
      next unless($keyword =~ /$search/i);

      push @ret, '<a name="searchResultKeywords"></a>' if($html && !$found{keywords});
      $found{keywords}++;

      my $descr = FHEM::Meta::GetKeywordDesc ($keyword, $t->{lang});

      push @ret, $t->{blockOpen}.$t->{tOpen};
      push @ret, $html
               ? '<caption style="text-align: left; font-size: larger;"'.($descr ne '' ? ' title="'.$descr.'"' : '').'># '.$keyword.$t->{tCClose}
               : '# '.$keyword;

      push @ret, $t->{tHOpen}.$t->{trOpen};
      push @ret, $t->{thOpen}.$_.$t->{thClose} for (qw(Name Type Abstract));
      push @ret, $t->{trClose}.$t->{tHClose};

      for my $mAttr (qw(modules packages)) {
          my $items = $FHEM::Meta::keywords{$keyword}{$mAttr};
          next unless(defined $items && @{$items} > 0);

          my $type = $mAttr eq 'modules' ? 'module' : 'package';

          for my $item (sort { lc($a) cmp lc($b) } @{$items}) {
              FHEM::Meta::Load ($item);

              my $entry = $type eq 'module' ? $modules{$item} : $packages{$item};

              push @ret, __TableRow ($t, $linecount++, __InfoLink($hash, $t, $type, $item), ucfirst($type), __MetaAbstract($entry));
          }
      }

      push @ret, $t->{tClose}.$t->{blockClose};
  }

  # passende Autoren & Maintainer
  @rows = ();

  for my $maintainer (sort { lc($a) cmp lc($b) } keys %FHEM::Meta::maintainers) {
      next unless($maintainer =~ /$search/i);

      my $info = $FHEM::Meta::maintainers{$maintainer};
      my @cells = ($maintainer);

      for my $type (qw(module package)) {
          my $list = $info->{$type.'s'};

          push @cells, defined $list
                     ? join($lb, map { __InfoLink ($hash, $t, $type, $_) } sort { lc($a) cmp lc($b) } @{$list})
                     : '';
      }

      push @rows, \@cells;
  }

  $found{maintainers} = scalar @rows;
  push @ret, __SearchTable ($t, 'searchResultMaintainers', 'Authors & Maintainers', ['Name', 'Modules', 'Packages'], \@rows) if(@rows);

  # passende Perl-Pakete
  @rows = ();

  for my $dependent (sort { lc($a) cmp lc($b) } keys %{$FHEM::Meta::dependents{pkgs}}) {
      next if(FHEM::Meta::ModuleIsPerlCore($dependent));
      next if(FHEM::Meta::ModuleIsInternal($dependent));
      next unless($dependent =~ /$search/i);

      my @references;

      for my $pkgReq (qw(requires recommends suggests)) {
          my $list = $FHEM::Meta::dependents{pkgs}{$dependent}{$pkgReq};
          next unless(defined $list);

          push @references, sort { lc($a) cmp lc($b) } @{$list};
      }

      push @rows, [$dependent, join($lb, map { __InfoLink($hash, $t, __ItemType($_), $_) } @references)];
  }

  $found{perl} = scalar @rows;
  push @ret, __SearchTable ($t, 'searchResultPerl', 'Perl Packages', ['Name', 'Referenced from'], \@rows) if(@rows);

  my $found = 0;
  $found   += $_ for (values %found);

  # TODO works only if fhem.pl patch was accepted: https://forum.fhem.de/index.php/topic,98937.0.html
  if (defined $hash->{CL} && defined $hash->{CL}{'.iDefCmdMethod'} && $hash->{CL}{'.iDefCmdMethod'} eq 'always') {
      my $cmdO = $hash->{CL}{'.iDefCmdOrigin'};

      if (defined $cmds{$cmdO} && defined $hash->{CL}{'.iDefCmdOverwrite'} && $hash->{CL}{'.iDefCmdOverwrite'}) {
          my $cmd = $search;
          $cmd    =~ s/^$cmdO//;
          $cmd    = $cmdO.'!'.($cmd && $cmd ne '' ? ' '.$cmd : '');

          unshift @ret, $lb.$lb.'Did you mean to <a href="?cmd='.$cmd.$t->{csrf}.'">run command '.$cmdO.'</a> instead?';
      }

      delete $hash->{CL}{'.iDefCmdOrigin'};
      delete $hash->{CL}{'.iDefCmdMethod'};
      delete $hash->{CL}{'.iDefCmdOverwrite'};
  }

  if ($found) {

      # Zusammenfassung: Gesamtzahl und je Abschnitt eine Zeile mit Sprunglink
      my @summary = ($found.' total search '.($found > 1 ? 'results:' : 'result:'));

      my @sections = (                                     # Schlüssel, Anker, Singular, Plural
          ['devices',     'searchResultDevices',     'device',       'devices'      ],
          ['modules',     'searchResultModules',     'module',       'modules'      ],
          ['packages',    'searchResultPackages',    'package',      'packages'     ],
          ['keywords',    'searchResultKeywords',    'keyword',      'keywords'     ],
          ['maintainers', 'searchResultMaintainers', 'author',       'authors'      ],
          ['perl',        'searchResultPerl',        'Perl package', 'Perl packages'],
      );

      for my $section (@sections) {
          my ($key, $anchor, $singular, $plural) = @{$section};
          next unless($found{$key});

          push @summary, $lb.$t->{space}.$t->{space}
                       . ($html ? '<a href="#'.$anchor.'">' : '')
                       . $found{$key}.' '.($found{$key} > 1 ? $plural : $singular)
                       . ($html ? '</a>' : '');
      }

      unshift @ret, @summary;
  }
  else {
      unshift @ret, $t->{tOpen}.$t->{trOpenOdd}.$t->{tdOpen}.'Nothing found'.$t->{tdClose}.$t->{trClose}.$t->{tClose}.$lb.$lb;
  }

  push @ret, $t->{tdClose}.$t->{trClose}.$t->{tClose}.$t->{blockClose};

  unshift @ret, $t->{blockOpen}
              . $t->{blockClose}
              . ($html ? '<a name="searchResultTOP"></a>' : '')
              . $t->{blockOpen}
              . $t->{tTitleOpen}
              . 'Search Result'
              . $t->{tTitleClose}
              . $t->{tOpen}
              . $t->{trOpen}
              . $t->{tdOpen}
              . $t->{blockOpen}
              . $t->{blockClose};

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#                  Hilfsfunktionen für die Ausgabe
###############################################################
# Link auf showModuleInfo / showPackageInfo ($type: module | package)
sub __InfoLink {
  my ($hash, $t, $type, $item, $label) = @_;

  $label //= $item;

  return $label unless($t->{html});

  my $cmd = $type eq 'module' ? 'showModuleInfo' : 'showPackageInfo';

return '<a href="?cmd=get '.$hash->{NAME}.' '.$cmd.' '.$item.$t->{csrf}.'">'.$label.'</a>';
}

# Link auf "get ... search <term>"
sub __SearchLink {
  my ($hash, $t, $term, $label, $title) = @_;

  my $titleAttr = (defined $title && $title ne '') ? ' title="'.$title.'"' : '';

return '<a href="?cmd=get '.$hash->{NAME}.' search '.$term.$t->{csrf}.'"'.$titleAttr.'>'.$label.'</a>';
}

# Typ eines FHEM-internen Items: module | package
sub __ItemType {
  my $item = shift;

return FHEM::Meta::ModuleIsInternal ($item) eq 'module' ? 'module' : 'package';
}

# Abstract aus den Metadaten eines Moduls/Packages ('' wenn nicht vorhanden oder 'n/a')
sub __MetaAbstract {
  my $entry = shift;

  my $abstract = (defined $entry && defined $entry->{META}) ? $entry->{META}{abstract} : undef;

return (!defined $abstract || $abstract eq 'n/a') ? '' : $abstract;
}

# Tabelle für einen Suchtreffer-Abschnitt
sub __SearchTable {
  my ($t, $anchor, $title, $cols, $rows) = @_;

  my @ret = __TableHeader ($t, $title, @{$cols});
  $ret[0] = ($t->{html} ? '<a name="'.$anchor.'"></a>' : '').$ret[0];

  my $linecount = 1;
  push @ret, __TableRow($t, $linecount++, @{$_}) for (@{$rows});

  push @ret, $t->{tClose}.$t->{blockClose};

return @ret;
}

#TODO
# - show master/slave dependencies
# - show parent/child dependencies
# - show other dependant/related modules
# - fill empty keywords
# - Get Community Support URL from MAINTAINERS.txt

###############################################################
#                  Modul- / Package-Metadaten
###############################################################
sub CreateMetadataList {
  my ($hash, $getCmd, $modName) = @_;

  $modName    = 'Global' if(uc($modName) eq 'FHEM');
  my $modType = lc($getCmd) eq 'showmoduleinfo' ? 'module' : 'package';

  my $t = __GetLayout ($hash);

  return 'Unknown module '.$modName if($modType eq 'module' && !defined $modules{$modName});

  FHEM::Meta::Load($modName);

  return 'Unknown package '.$modName if($modType eq 'package' && !defined $packages{$modName});

  my $modMeta = $modType eq 'module' ? $modules{$modName}{META} : $packages{$modName}{META};

  return "No metadata found about $modType $modName" if(!defined $modMeta || scalar keys %{$modMeta} == 0);

  my $html = $t->{html};
  my $lb   = $t->{lb};
  my $lang = $t->{lang};
  my @ret;

  $t->{header} = '<html><div class="detLink installerBack" style="float:right"><a href="?detail='.$hash->{NAME}.'">&larr; back to FHEM Installer</a></div>' if($html);

  my @metaAttrs = qw(
      name
      abstract
      keywords
      version
      release_date
      release_status
      author
      copyright
      privacy
      homepage
      wiki
      command_reference
      community_support
      commercial_support
      bugtracker
      version_control
      license
      description
  );

  push @ret, $t->{blockOpen}.$t->{tTitleOpen}.ucfirst($modType).' Information'.$t->{tTitleClose}.$t->{tOpen};

  my $linecount = 1;

  for my $mAttr (@metaAttrs) {
      next if(__MetaSkip ($modMeta, $modType, $mAttr));

      my $mAttrName = $mAttr;
      $mAttrName    =~ s/_/$t->{space}/g;
      $mAttrName    =~ s/([\w'&]+)/\u\L$1/g;

      my $value = __MetaValue ($hash, $t, $modMeta, $modName, $modType, $mAttr, $mAttrName);

      push @ret, ($linecount % 2 == 0 ? $t->{trOpenEven} : $t->{trOpenOdd})
               . $t->{thOpen}.$mAttrName.$t->{thClose}
               . $t->{tdOpen}.$value.$t->{tdClose}
               . $t->{trClose};

      $linecount++;
  }

  push @ret, $t->{tFOpen}
           . $t->{trOpen}
           . ($html ? '<td style="text-align:right;" colspan="2">' : '')
           . 'Based on data generated by '
           . $lb
           . $modMeta->{generated_by}
           . $t->{tdClose}
           . $t->{trClose}
           . $t->{tFClose};

  push @ret, $t->{tClose}.$t->{blockClose};

  # FHEM-Module, die dieses Package verwenden
  my $deps = $FHEM::Meta::dependents{pkgs}{$modName};

  $linecount = 1;

  for my $mAttr (qw(requires recommends suggests)) {
      my $list = $deps ? $deps->{$mAttr} : undef;
      next unless(ref $list eq 'ARRAY' && @{$list} > 0);

      my $dependents = join(', ', map { __InfoLink($hash, $t, __ItemType($_), $_) } sort { lc($a) cmp lc($b) } @{$list});
      next if($dependents eq '');

      if ($linecount == 1) {
          push @ret, $t->{blockOpen}.$t->{tTitleOpen}.'FHEM internal dependencies'.$t->{tTitleClose}.$t->{tOpen};
          push @ret, $t->{tHOpen}.$t->{trOpen};
          push @ret, $t->{thOpen}.'Importance'.$t->{thClose};
          push @ret, $t->{thOpen}.'Dependent Modules'.$t->{thClose};
          push @ret, $t->{trClose}.$t->{tHClose};
      }

      push @ret, __TableRow ($t, $linecount++, $importance{$mAttr}, $dependents);
  }

  if ($linecount > 1) {
      push @ret, $t->{tFOpen}
               . $t->{trOpen}
               . $t->{tdOpen2}
               . $t->{strongOpen}.'Hint:'.$t->{strongClose}
               . ' Dependents can only be shown here if they were loaded into the metadata cache before.'
               . $t->{tdClose}
               . $t->{trClose}
               . $t->{tFClose}
               . $t->{tClose}
               . $t->{blockClose};
  }

  # Devices des Moduls (nicht für Kommando-Module)
  my $isCommand = defined $modMeta->{keywords} && grep { $_ eq 'fhem-mod-command' } @{$modMeta->{keywords}};

  if ($modType eq 'module' && $modName ne 'Global' && !$isCommand) {
      push @ret, $t->{blockOpen}.$t->{tTitleOpen}.'Devices'.$t->{tTitleClose}.$t->{tOpen};

      if ($modules{$modName}{LOADED}) {
          my @instances = devspec2array('TYPE='.$modName);

          if (@instances > 0) {
              push @ret, $t->{tHOpen}.$t->{trOpen}
                       . $t->{thOpen}.'Name'.$t->{thClose}
                       . $t->{thOpen}.'State'.$t->{thClose}
                       . $t->{trClose}.$t->{tHClose}.$t->{tBOpen};

              my $devCount = 1;

              for my $instance (sort { lc($a) cmp lc($b) } @instances) {
                  next if(defined $defs{$instance}{TEMPORARY});

                  my $device = $html ? '<a href="?detail='.$instance.'">'.$instance.'</a>' : $instance;

                  push @ret, __TableRow ($t, $devCount++, $device, $defs{$instance}{STATE});
              }

              push @ret, $t->{tBClose};
          }
          else {
              push @ret, $t->{tBOpen}.$t->{trOpen}.$t->{tdOpen}
                       . 'The module was once loaded into memory, but currently there is no device defined.'
                       . $t->{tdClose}.$t->{trClose}.$t->{tBClose};
          }
      }
      else {
          push @ret, $t->{tBOpen}.$t->{trOpen}.$t->{tdOpen}.'The module is currently not in use.'.$t->{tdClose}.$t->{trClose}.$t->{tBClose};
      }

      push @ret, $t->{tClose}.$t->{blockClose};
  }

  # Systemvoraussetzungen
  LoadInstallStatusPerl($modName);

  push @ret, $t->{blockOpen}.$t->{tTitleOpen}.'System Prerequisites'.$t->{tTitleClose}.$t->{tOpen}.$t->{trOpen}.$t->{tdOpen};
  push @ret, $t->{blockOpen}.$t->{tOpen}.$t->{tCOpen}.'Perl Packages'.$t->{tCClose};

  my $runtime = defined $modMeta->{prereqs} ? $modMeta->{prereqs}{runtime} : undef;

  if (defined $runtime) {
      push @ret, $t->{tHOpen}.$t->{trOpen};
      push @ret, $t->{thOpen}.$_.$t->{thClose} for (qw(Name Importance Status));
      push @ret, $t->{thOpen}.'Action'.$t->{thClose} if($html);
      push @ret, $t->{trClose}.$t->{tHClose}.$t->{tBOpen};

      $linecount = 1;

      for my $mAttr (qw(requires recommends suggests)) {
          my $reqs = $runtime->{$mAttr};
          next unless(defined $reqs && keys %{$reqs} > 0);

          for my $prereq (sort keys %{$reqs}) {
              my $isFhem      = FHEM::Meta::ModuleIsInternal($prereq);
              my $status      = $pkgStatus{Perl}{pkgs}{$prereq}{status} // '';
              my $actionLabel = $status eq 'outdated' ? 'Update' : 'Install';
              my $installed   = $status;
              my $action      = '';
              my $inherited   = '';
              my $imp         = $importance{$mAttr};

              my $version = $reqs->{$prereq};
              $version    = '' if(!defined $version || $version eq '0');

              my $inheritedFrom = $runtime->{x_inherited};

              if (defined $inheritedFrom && defined $inheritedFrom->{$prereq}) {
                  $inherited = '[inherited]';
                  $inherited = '<span title="Inherited from '.join(', ', @{$inheritedFrom->{$prereq}}).'" style="color: grey;">'.$inherited.'</span>' if($html);
              }

              my $installLink = '<div class="detLink installerAction"><a href="?cmd=set '.$hash->{NAME}.' installPerl '.$prereq.' '.$t->{csrf}
                              . '" title="Click here to trigger installation">'.$actionLabel.'</a></div>';

              if ($mAttr ne 'requires' && ($status eq 'missing' || $status eq 'outdated')) {
                  $installed = '';
                  $action    = $installLink;
              }
              elsif ($status eq 'installed') {
                  $installed = $t->{colorGreen}.$installed.$t->{colorClose};
              }
              elsif ($status eq 'missing' || $status eq 'outdated') {
                  $installed = $t->{colorRed}.$t->{strongOpen}.uc($installed).$t->{strongClose}.$t->{colorClose};
                  $action    = $installLink;
              }

              my $item = $prereq;

              if ($html && $installed ne 'built-in' && $installed ne 'included') {
                  $item = '<a href="https://metacpan.org/pod/'.$prereq.'" target="_blank">'.$prereq.'</a>';
              }
              elsif ($html && $installed eq 'included') {
                  $item = __InfoLink($hash, $t, $isFhem eq 'module' ? 'module' : 'package', $prereq);
              }

              my @cells = (
                  $item.($inherited ne '' ? " $inherited" : '').($version ne '' ? " ($version)" : ''),
                  $imp,
                  $installed,
              );
              push @cells, $action if($html);

              push @ret, __TableRow ($t, $linecount++, @cells);
          }
      }

      push @ret, $t->{tBClose};

      if (defined $modMeta->{x_prereqs_src} && $modMeta->{x_prereqs_src} ne 'META.json') {
          push @ret, $t->{tFOpen}
                   . $t->{trOpenEven}
                   . ($html ? $t->{tdOpen4} : $t->{tdOpen3})
                   . $t->{strongOpen}.'Hint:'.$t->{strongClose}
                   . ' The module does not provide Perl prerequisites from its metadata.'
                   . $lb
                   . 'This result is based on automatic source code analysis and can be incorrect. '
                   . 'Suggested Perl items may still be required if the module author had decided to implement some own dependency and/or error handling like returning an informative message instead of the original Perl error message.'
                   . $t->{tdClose}
                   . $t->{trClose}
                   . $t->{tFClose};
      }
  }
  elsif (defined $modMeta->{x_prereqs_src}) {
      push @ret, $t->{tBOpen}.$t->{trOpenOdd}.$t->{tdOpen}.'No known prerequisites.'.$t->{tdClose}.$t->{trClose}.$t->{tBClose};
  }
  else {
      my $install = $html
                  ? '<a href="?cmd=set '.$hash->{NAME}.' installPerl Perl::PrereqScanner::NotQuiteLite'.$t->{csrf}
                    .'">Click here to install Perl::PrereqScanner::NotQuiteLite</a> for automatic source code analysis.'
                  : 'For automatic source code analysis, please install Perl::PrereqScanner::NotQuiteLite first.';

      push @ret, $t->{tBOpen}.$t->{trOpenOdd}.$t->{tdOpen}
               . "Module metadata do not contain any prerequisites.\n".$install
               . $t->{tdClose}.$t->{trClose}.$t->{tBClose};
  }

  push @ret, $t->{tClose}.$t->{blockClose};

  # Node.js und Python
  my $nodejs = defined $modMeta->{x_prereqs_nodejs} ? $modMeta->{x_prereqs_nodejs}{runtime} : undef;
  my $python = defined $modMeta->{x_prereqs_python} ? $modMeta->{x_prereqs_python}{runtime} : undef;

  push @ret, __ExtPrereqSection ($hash, $t, 'Node.js Packages', $nodejs, \&__IsInstalledNodejs, 0) if(defined $nodejs);
  push @ret, __ExtPrereqSection ($hash, $t, 'Python Packages',  $python, \&__IsInstalledPython, 1) if(defined $python);

  push @ret, $t->{tdClose}.$t->{trClose}.$t->{tClose}.$t->{blockClose};

return $t->{header}.join("\n", @ret).$t->{footer};
}

###############################################################
#     Metadaten: welche Attribute werden nicht angezeigt
###############################################################
sub __MetaSkip {
  my ($meta, $modType, $mAttr) = @_;

  if ($mAttr eq 'release_status') {
      return !defined $meta->{release_status} || $meta->{release_status} eq 'stable';
  }

  if ($mAttr eq 'abstract' || $mAttr eq 'description') {
      my $value = $meta->{$mAttr};
      return !defined $value || $value eq 'n/a' || $value eq '';
  }

  if (my $key = $resourceKey{$mAttr}) {
      return !defined $meta->{resources} || !defined $meta->{resources}{$key};
  }

  return !defined $meta->{keywords} || !@{$meta->{keywords}} if($mAttr eq 'keywords');
  return !defined $meta->{version}                           if($mAttr eq 'version');
  return !defined $meta->{x_release_date} && !defined $meta->{x_vcs} if($mAttr eq 'release_date');
  return $modType eq 'package'                               if($mAttr eq 'command_reference');

return 0;
}

###############################################################
#     Metadaten: Attribute, die in META.json anders heißen
#     (liefert undef, wenn nichts darzustellen ist)
###############################################################
sub __MetaDerived {
  my ($hash, $t, $meta, $modName, $mAttr) = @_;

  my $html = $t->{html};
  my $res  = $meta->{resources};

  if ($mAttr eq 'release_date') {
      return $meta->{x_release_date} if(defined $meta->{x_release_date});
      return $meta->{x_vcs}[7]       if(defined $meta->{x_vcs});
      return '';
  }

  if ($mAttr eq 'copyright') {
      my $copy = $res->{x_copyright};
      my $text = '© ';
      $text   .= $meta->{x_vcs}[8].' ' if(defined $meta->{x_vcs});
      $text   .= $copy->{title};

      return '<a href="'.$copy->{web}.'" target="_blank">'.$text.'</a>'  if($html && $copy->{web});
      return '<a href="mailto:'.$copy->{mailto}.'">'.$text.'</a>'        if($html && $copy->{mailto});
      return $text;
  }

  if ($mAttr eq 'privacy') {
      my $privacy = $res->{x_privacy};
      my $title   = defined $privacy->{title} ? $privacy->{title} : $privacy->{web};

      return '<a href="'.$privacy->{web}.'" target="_blank">'.$title.'</a>';
  }

  if ($mAttr eq 'homepage') {
      return unless(defined $res && defined $res->{homepage});

      my $web   = $res->{homepage};
      my $title = defined $res->{x_homepage_title} ? $res->{x_homepage_title}
                : $web =~ m/^.+:\/\/([^\/]+).*/    ? $1
                :                                    $web;

      return '<a href="'.$web.'" target="_blank">'.$title.'</a>';
  }

  if ($mAttr eq 'command_reference') {
      my $ret     = '';
      my $webname = $html ? AttrVal($hash->{CL}{SNAME}, 'webname', 'fhem') : 'fhem';

      if ($html) {
          $ret .= '<a href="/'.$webname.'/docs/commandref.html#'.($modName eq 'Global' ? 'global' : $modName).'" target="_blank">Offline version</a>';
      }

      if (defined $res && defined $res->{x_commandref} && defined $res->{x_commandref}{web}) {
          my $title = defined $res->{x_commandref}{title} ? $res->{x_commandref}{title} : 'Online version';

          $ret .= ($webname ? ' | ' : '').'<a href="'.$res->{x_commandref}{web}.'" target="_blank">'.$title.'</a>';
      }

      return $ret;
  }

  if ($mAttr eq 'wiki') {
      return unless(defined $res && defined $res->{x_wiki} && defined $res->{x_wiki}{web});

      my $web    = $res->{x_wiki}{web};
      my $isFhem = $web =~ m/^(?:https?:\/\/)?wiki\.fhem\.de/i;
      my $title  = defined $res->{x_wiki}{title} ? $res->{x_wiki}{title} : ($isFhem ? 'FHEM Wiki' : '');

      $title = 'FHEM Wiki: '.$title if($title ne '' && $title !~ m/^FHEM Wiki/i && $isFhem);

      return '<a href="'.$web.'" target="_blank">'.$title.'</a>';
  }

  if ($mAttr eq 'community_support') {
      return unless(defined $res && defined $res->{x_support_community} && defined $res->{x_support_community}{web});

      my $community = $res->{x_support_community};
      my $board     = defined $community->{subCommunity} ? $community->{subCommunity} : $community;
      my $isFhem    = $board->{web} =~ m/^(?:https?:\/\/)?forum\.fhem\.de/i;
      my $title     = defined $board->{title} ? $board->{title} : ($isFhem ? 'FHEM Forum' : '');

      $title = 'FHEM Forum: '.$title if($title ne '' && $title !~ m/^FHEM Forum/i && $isFhem);

      my $descr = defined $board->{description}     ? $board->{description}
                : defined $community->{description} ? $community->{description}
                :                                     undef;

      my $ret = (defined $meta->{x_support_status} && $meta->{x_support_status} eq 'limited') ? 'Limited - ' : '';

      return $ret.'<a href="'.$board->{web}.'" target="_blank"'.(defined $descr ? ' title="'.$descr.'"' : '').'>'.$title.'</a>';
  }

  if ($mAttr eq 'commercial_support') {
      return unless(defined $res && defined $res->{x_support_commercial} && defined $res->{x_support_commercial}{web});

      my $commercial = $res->{x_support_commercial};
      my $title      = defined $commercial->{title} ? $commercial->{title} : $commercial->{web};
      my $ret        = (defined $meta->{x_support_status} && $meta->{x_support_status} eq 'limited') ? 'Limited - ' : '';

      return $ret.'<a href="'.$commercial->{web}.'" target="_blank">'.$title.'</a>';
  }

  if ($mAttr eq 'bugtracker') {
      return unless(defined $res && defined $res->{bugtracker} && defined $res->{bugtracker}{web});

      my $web      = $res->{bugtracker}{web};
      my $isForum  = $web =~ m/^(?:https?:\/\/)?forum\.fhem\.de/i;
      my $isGithub = $web =~ m/^(?:https?:\/\/)?github\.com\/fhem/i;

      my $title = defined $res->{bugtracker}{x_web_title} ? $res->{bugtracker}{x_web_title}
                : $isForum                                ? 'FHEM Forum'
                : $isGithub                               ? 'Github Issues: '.$meta->{name}
                :                                           $web;

      # Präfix ergänzen, wenn der Titel vom Autor vorgegeben wurde
      $title = 'FHEM Forum: '.$title    if($title ne '' && $title !~ m/^FHEM Forum/i    && $isForum);
      $title = 'Github Issues: '.$title if($title ne '' && $title !~ m/^Github issues/i && $isGithub);

      return '<a href="'.$web.'" target="_blank">'.$title.'</a>';
  }

  if ($mAttr eq 'version_control') {
      return __MetaVersionControl ($t, $meta);
  }

return;
}

###############################################################
#     Metadaten: Versionsverwaltung (Links, Branches, Raw-Dateien)
###############################################################
sub __MetaVersionControl {
  my ($t, $meta) = @_;

  my $lb   = $t->{lb};
  my $res  = $meta->{resources};
  my $repo = $res->{repository};

  return unless(defined $repo && defined $repo->{type} && defined $repo->{url});

  my $dev      = $repo->{x_dev};
  my $hasDev   = defined $repo->{x_branch} && defined $dev && defined $dev->{x_branch};
  my $fileName = $meta->{x_file}[2];
  my $ret      = '';

  # Web-Links
  if (defined $repo->{web}) {
      if ($hasDev) {
          my $same     = $repo->{x_branch} eq $dev->{x_branch};
          my $mainName = $same ? 'production'  : $repo->{x_branch};
          my $devName  = $same ? 'development' : $dev->{x_branch};

          $ret .= 'View online source code: <a href="'.$repo->{web}.'" target="_blank">'.$mainName.'</a>';
          $ret .= ' | <a href="'.$dev->{web}.'" target="_blank">'.$devName.'</a>';

          if (defined $repo->{x_raw}) {
              $ret .= $lb.'Download raw file: <a href="'.$repo->{x_raw}.'" target="_blank" download="'.$fileName.'">'.$mainName.'</a>';
              $ret .= ' | <a href="'.$dev->{x_raw}.'" target="_blank" download="'.$fileName.'">'.$devName.'</a>' if(defined $dev->{x_raw});
          }
      }
      else {
          $ret .= '<a href="'.$repo->{web}.'" target="_blank">View online source code</a>';
          $ret .= $lb.'<a href="'.$repo->{x_raw}.'" target="_blank" download="'.$fileName.'">Download raw file</a>' if(defined $repo->{x_raw});
      }

      $ret .= $lb;
  }

  # VCS-Link
  my $type      = $repo->{type};
  my $urlPrefix = $repo->{url} =~ /^$type/i ? '' : lc($type).'+';

  $ret .= uc($type).' repository: <a href="'.$urlPrefix.$repo->{url}.'" target="_blank">'.$urlPrefix.$repo->{url}.'</a>';

  if (defined $repo->{x_branch}) {
      if (lc($type) eq 'svn') {
          my $path = $repo->{x_branch} eq 'trunk' ? 'trunk' : 'branches/'.$repo->{x_branch};
          $ret    .= $lb.'Main branch: <a href="'.$urlPrefix.$repo->{url}.'/'.$path.'" target="_blank">'.$repo->{x_branch}.'</a>';
      }
      else {
          $ret .= $lb.'Main branch: '.$repo->{x_branch};
      }
  }

  if ($hasDev && $repo->{x_branch} ne $dev->{x_branch}) {
      if (lc($dev->{type}) eq 'svn') {
          my $path = $dev->{x_branch} eq 'trunk' ? 'trunk' : 'branches/'.$dev->{x_branch};
          $ret    .= $lb.'Dev branch: <a href="'.$urlPrefix.$repo->{url}.'/'.$path.'" target="_blank">'.$dev->{x_branch}.'</a>';
      }
      else {
          $ret .= $lb.'Dev branch: '.$dev->{x_branch};
      }
  }

return $ret;
}

###############################################################
#     Metadaten: Wert eines Attributs für die Anzeige
###############################################################
sub __MetaValue {
  my ($hash, $t, $meta, $modName, $modType, $mAttr, $mAttrName) = @_;

  my $html  = $t->{html};
  my $lb    = $t->{lb};
  my $lang  = $t->{lang};
  my $value = $meta->{$mAttr};

  # Attribute, die in META.json nicht unter diesem Namen vorkommen
  if (!defined $value) {
      my $derived = __MetaDerived ($hash, $t, $meta, $modName, $mAttr);

      return defined $derived ? $derived : '-';
  }

  # einfacher Text
  if (!ref $value) {
      my $text = (defined $meta->{x_lang} && defined $meta->{x_lang}{$lang} && defined $meta->{x_lang}{$lang}{$mAttr})
               ? $meta->{x_lang}{$lang}{$mAttr}
               : $value;

      $text =~ s/\\n/$lb/g;

      if ($mAttr eq 'version') {
          if ($text eq '0.000000001') {
              $text = '-';
          }
          elsif ($meta->{x_file}[7] ne 'generated/vcs') {
              $text = version->parse($text)->normal;

              # bei fhem.pl nur das maximale Featurelevel zeigen
              $text = $1 if($modName eq 'Global' && $text =~ m/^(v\d+\.\d+).*/);

              # Commit-Revision nur anhängen, wenn sie nicht schon Teil der Version ist
              $text .= '-s'.$meta->{x_vcs}[5] if(defined $meta->{x_vcs} && $meta->{x_vcs}[5] ne '');
          }
      }

      # Dateiname hinter den Modulnamen
      $text .= ' ('.$meta->{x_file}[2].')' if($modType eq 'module' && $mAttr eq 'name' && $modName ne 'Global');

      return $text;
  }

  # Arrays
  if (ref $value eq 'ARRAY' && @{$value} > 0 && $value->[0] ne '') {

      if ($mAttr eq 'license') {
          my $res  = $meta->{resources};
          my $link = (defined $res && ref $res->{license} eq 'ARRAY' && @{$res->{license}} > 0 && $res->{license}[0] ne '')
                   ? $res->{license}[0]
                   : undef;

          return defined $link ? '<a href="'.$link.'" target="_blank">'.$value->[0].'</a>' : $value->[0];
      }

      if ($mAttr eq 'author') {
          my $aliases = ref $meta->{x_fhem_maintainer} eq 'ARRAY' ? $meta->{x_fhem_maintainer} : [];
          my $ret     = '';
          my $counter = 0;

          for my $author (@{$value}) {
              next if($author eq '');

              my ($authorName, $editorOnly);

              if ($author =~ m/^([^<>\n\r]+?)(?:\s+(\(last release only\)))?(?:\s+(?:<(.*)>))?$/) {
                  $authorName = $1;
                  $editorOnly = $2 ? ' '.$2 : '';
              }

              my $display = $authorName;
              my $alias   = $aliases->[$counter];

              # Alias zeigen, falls abweichend
              if (defined $alias && $alias ne '') {
                  if ($alias eq $authorName) {
                      $display = __SearchLink ($hash, $t, $alias, $authorName).$editorOnly if($html);
                  }
                  elsif ($html) {
                      $display = $authorName.', alias '.__SearchLink ($hash, $t, $alias, $alias).$editorOnly;
                  }
                  else {
                      $display = $authorName.$editorOnly.', alias '.$alias;
                  }
              }

              $ret .= $lb if($counter);
              $ret .= $lb.'Co-'.$mAttrName.':'.$lb if($counter == 1);
              $ret .= $display ? $display : $authorName.$editorOnly;

              $counter++;
          }

          return $ret;
      }

      if ($mAttr eq 'keywords') {
          return join(', ', map {
              $html ? __SearchLink ($hash, $t, $_, $_, FHEM::Meta::GetKeywordDesc($_, $lang)) : $_
          } @{$value});
      }

      return join(', ', @{$value});
  }

return '?';
}

###############################################################
#     Node.js / Python: Installationsstatus eines Pakets
###############################################################
sub __ExtInstalledState {
  my ($t, $check, $version, $importance) = @_;

  my $installed = '';

  if ($check) {
      if ($check =~ m/^\d+\./) {
          my $nverReq = $version ne '' ? $version : 0;

          #TODO support for version range:
          #https://metacpan.org/pod/CPAN::Meta::Spec#Version-Range
          $installed = ($nverReq > 0 && $check < $nverReq)
                     ? $t->{colorRed}.'OUTDATED'.$t->{colorClose}." ($check)"
                     : 'installed';
      }
      else {
          $installed = 'installed';
      }
  }
  elsif ($importance eq 'required') {
      $installed = $t->{colorRed}.'MISSING'.$t->{colorClose};
  }

return $installed;
}

###############################################################
#     Node.js / Python: Tabelle der Voraussetzungen
###############################################################
sub __ExtPrereqSection {
  my ($hash, $t, $title, $runtime, $checkFn, $python) = @_;

  my $html = $t->{html};
  my @ret  = ($t->{blockOpen}.$t->{tOpen}.$t->{tCOpen}.$title.$t->{tCClose});

  push @ret, $t->{tHOpen}.$t->{trOpen};
  push @ret, $t->{thOpen}.$_.$t->{thClose} for (qw(Name Importance Status));
  push @ret, $t->{trClose}.$t->{tHClose}.$t->{tBOpen};

  my $linecount = 1;

  for my $mAttr (qw(requires recommends suggests)) {
      my $reqs = $runtime->{$mAttr};
      next unless(defined $reqs && keys %{$reqs} > 0);

      for my $prereq (sort keys %{$reqs}) {
          my $version = $reqs->{$prereq};
          $version    = '' if(!defined $version || $version eq '0');

          my $imp       = $importance{$mAttr};
          my $installed = __ExtInstalledState ($t, $checkFn->($prereq), $version, $imp);
          my $item      = $prereq;

          if ($python) {
              my $isPerlCore = FHEM::Meta::ModuleIsPerlCore ($prereq);
              my $isFhem     = $isPerlCore ? 0 : FHEM::Meta::ModuleIsInternal ($prereq);

              if ($isPerlCore || $prereq eq 'perl') {
                  $installed = $installed ne 'installed' ? "$installed (Perl built-in)" : 'built-in';
              }
              elsif ($isFhem) {
                  $installed = $installed ne 'installed' ? "$installed (FHEM included)" : 'included';
              }
              elsif ($installed eq 'installed') {
                  $installed = $t->{colorGreen}.$installed.$t->{colorClose};
              }

              $item = '<a href="https://metacpan.org/pod/'.$prereq.'" target="_blank">'.$prereq.'</a>'
                if($html && !$isFhem && !$isPerlCore && $prereq ne 'perl');
          }
          else {
              $installed = $t->{colorGreen}.$installed.$t->{colorClose};
              $item      = '<a href="https://www.npmjs.com/package/'.$prereq.'" target="_blank">'.$prereq.'</a>' if($html);
          }

          push @ret, __TableRow ($t, $linecount++, $item.($version ne '' ? " ($version)" : ''), $imp, $installed);
      }
  }

  push @ret, $t->{tBClose}.$t->{tClose}.$t->{blockClose};

return @ret;
}

###############################################################
#                  Rohe META.json ausgeben
###############################################################
sub CreateRawMetaJson {
  my ($hash, $getCmd, $modName) = @_;

  $modName    = 'Global' if(uc($modName) eq 'FHEM');
  my $modType = lc($getCmd) eq 'zzgetmodulemetajson' ? 'module' : 'package';

  FHEM::Meta::Load ($modName);

  my $meta = $modType eq 'module' ? $modules{$modName}{META} : $packages{$modName}{META};

  return '{}' unless(defined $meta && scalar keys %{$meta} > 0);

  my $j = $jsonModule->new->allow_nonref->canonical->pretty;

return $j->encode($meta);
}

###############################################################
#     Module aus einer FHEM-Konfigurationsdatei ermitteln
###############################################################
sub __GetDefinedModulesFromFile {
  my ($filePath) = @_;

  my @modules;
  my %seen;

  if (open(my $fh, '<', $filePath)) {
      while (my $line = <$fh>) {
          next unless($line =~ /^define\s+\S+\s+(\S+).*/);

          my $modName = $1;
          push @modules, $modName unless($seen{$modName}++);
      }

      close($fh);
  }

  return @modules if(wantarray);
  return join(',', @modules) if(@modules > 0);

return;
}

###############################################################
#     Installationsstatus der Perl-Voraussetzungen ermitteln
###############################################################
sub LoadInstallStatusPerl {
  my ($modList) = @_;

  my $t        = TimeNow();
  my $lmodules = __ResolveModuleList ($modList);

  if (!defined $lmodules) {
      $@ = __PACKAGE__.'::LoadInstallStatusPerl: ERROR: Unknown parameter value';
      Log 1, $@;

      return "$@";
  }

  for my $name (@{$lmodules}) {
      my $modName = uc($name) eq 'FHEM' ? 'Global' : $name;

      # ein Name kann gleichzeitig Modul und Package sein
      my @types;
      push @types, 'module'  if(exists $modules{$modName});
      push @types, 'package' if(exists $packages{$modName});

      for my $type (@types) {
          FHEM::Meta::Load($modName);

          my $modMeta = $type eq 'module' ? $modules{$modName}{META} : $packages{$modName}{META};
          next unless(defined $modMeta);

          $pkgStatus{Perl}{analyzed} = 2 unless(defined $modMeta->{x_prereqs_src});

          __AnalyzePerlPrereqs ($modName, $type, $modMeta, $t);

          #TODO
          # nodejs
          # python
      }
  }

  __BuildInstallHash();

return;
}

###############################################################
#     Liste der zu prüfenden Module bestimmen
#     (liefert eine Array-Referenz, bei ungültigem Parameter undef)
###############################################################
sub __ResolveModuleList {
  my $modList = shift;

  # keine Angabe oder '1': alle geladenen Module, bei '1' auch ungenutzte
  if (!$modList || (!ref $modList && $modList eq '1')) {
      my $unused = $modList ? 1 : 0;

      return [grep { $unused || (defined $modules{$_}{LOADED} && $modules{$_}{LOADED} eq '1') } keys %modules];
  }

  return [$modList]          if(!ref $modList);             # einzelner Modulname
  return [@{$modList}]       if(ref $modList eq 'ARRAY');   # Liste von Modulnamen
  return [keys %{$modList}]  if(ref $modList eq 'HASH');    # jeder Schlüssel ist ein Modulname

return;
}

# Elemente nur hinzufügen, wenn noch nicht vorhanden
sub __PushUnique {
  my ($list, @items) = @_;

  for my $item (@items) {
      push @{$list}, $item unless(grep { $_ eq $item } @{$list});
  }

return;
}

###############################################################
#     Perl-Voraussetzungen eines Moduls/Packages prüfen
###############################################################
sub __AnalyzePerlPrereqs {
  my ($modName, $type, $modMeta, $t) = @_;

  my $runtime = defined $modMeta->{prereqs} ? $modMeta->{prereqs}{runtime} : undef;
  return unless(defined $runtime);

  for my $mAttr (qw(requires recommends suggests)) {
      next unless(defined $runtime->{$mAttr} && keys %{$runtime->{$mAttr}} > 0);

      for my $pkg (keys %{$runtime->{$mAttr}}) {
          __PushUnique(\@{$pkgStatus{Perl}{pkgs}{$pkg}{$type.'s'}{$mAttr}}, $modName);

          # Status bereits ermittelt
          next if(defined $pkgStatus{Perl}{pkgs}{$pkg}{status});

          __DetectPerlPackage ($pkg, $modName, $type, $mAttr, $modMeta);

          next unless(__CheckPerlOutdated ($pkg, $mAttr, $modMeta));

          $pkgStatus{Perl}{pkgs}{$pkg}{timestamp} = $t;
      }
  }

return;
}

###############################################################
#     Status und installierte Version eines Perl-Pakets
###############################################################
sub __DetectPerlPackage {
  my ($pkg, $modName, $type, $mAttr, $modMeta) = @_;

  my $info = $pkgStatus{Perl}{pkgs}{$pkg};
  my $inst = ($pkgStatus{Perl}{installed} //= {});

  (my $fname = $pkg) =~ s/^.*://g;                                                      # übergeordnete Modulnamen entfernen

  my $isPerlCore = FHEM::Meta::ModuleIsPerlCore($pkg);
  my $isFhem     = $isPerlCore ? 0 : FHEM::Meta::ModuleIsInternal($pkg);

  if ($pkg eq 'perl') {
      $info->{status} = 'built-in';
      $inst->{$pkg}   = version->parse($])->numify;
  }
  elsif ($pkg eq 'FHEM') {
      $info->{status} = 'included';
      $inst->{$pkg}   = $modules{'Global'}{META}{version};
  }
  elsif ($pkg eq 'FHEM::Meta' || $pkg eq 'Meta') {
      $info->{status} = 'included';
      $inst->{$pkg}   = FHEM::Meta->VERSION();
  }
  elsif ($isPerlCore) {
      $info->{status} = 'built-in';
      $inst->{$pkg}   = 0;
  }
  elsif ($isFhem && $isFhem eq 'package') {                                             # FHEM-Package
      my $meta        = defined $packages{$fname} ? $packages{$fname}{META} : undef;
      $info->{status} = 'included';
      $inst->{$pkg}   = defined $meta ? $meta->{version} : 0;
  }
  elsif ($isFhem && $isFhem eq 'module') {                                              # FHEM-Modul, das als Package geladen wird
      my $meta        = defined $modules{$fname} ? $modules{$fname}{META} : undef;
      $info->{status} = 'included';
      $inst->{$pkg}   = defined $meta ? $meta->{version} : 0;
  }
  elsif ($pkg =~ /^Win32::/ && $^O !~ /Win/) {
      $info->{status} = 'n/a';
  }
  else {
      __DetectByRequire ($pkg, $modName, $type, $mAttr, $modMeta);
  }

return;
}

###############################################################
#     Paket durch Laden (require) prüfen
###############################################################
sub __DetectByRequire {
  my ($pkg, $modName, $type, $mAttr, $modMeta) = @_;

  my $runtime = $modMeta->{prereqs}{runtime};
  my $info    = $pkgStatus{Perl}{pkgs}{$pkg};
  my $inst    = $pkgStatus{Perl}{installed};

  my $error = __RequirePackage ($pkg);

  # Paket fehlt, oder es fehlt ein anderes Paket, das dieses lädt
  if ($error =~ m/^Can't locate (\S+)\.pm/i) {
      my $missing = $1;
      $missing    =~ s/\//::/g;

      $pkgStatus{Perl}{pkgs}{$missing}{status} = 'missing';
      push @{$pkgStatus{Perl}{missing}{$missing}}, defined $runtime->{$mAttr}{$missing} ? $runtime->{$mAttr}{$missing} : 0;

      $pkgStatus{Perl}{analyzed} = 1 if(($modMeta->{x_prereqs_src} // '') ne 'META.json' && !$pkgStatus{Perl}{analyzed});

      # Enthält die Fehlermeldung einen anderen Paketnamen, ist das eigentliche
      #   Paket installiert und es fehlt ein weiteres Paket, das es selbst benötigt
      if ($missing ne $pkg) {
          my $version     = eval { $pkg->VERSION() };
          $info->{status} = 'installed';
          $inst->{$pkg}   = $version ? $version : 0;

          __PushUnique(\@{$pkgStatus{Perl}{pkgs}{$missing}{$type.'s'}{$mAttr}}, $modName);

          # Metadaten des Moduls ebenfalls ergänzen
          $runtime->{$mAttr}{$missing} = 0;
          push @{$runtime->{x_inherited}{$missing}}, $pkg;
      }
  }
  else {
      my $version     = eval { $pkg->VERSION() };
      $info->{status} = 'installed';
      $inst->{$pkg}   = $version ? $version : 0;
  }

return;
}

# Paket laden und Fehlermeldung zurückgeben ('' bei Erfolg)
sub __RequirePackage {
  my $pkg = shift;

  # frühere fehlgeschlagene Ladeversuche entfernen, um die Original-Fehlermeldung zu erhalten
  for my $inc (keys %INC) {
      delete $INC{$inc} if(!$INC{$inc});
  }

  (my $file = $pkg.'.pm') =~ s/::/\//g;

  # Log-Ausgaben und Warnungen während des Ladens unterdrücken
  my $hadVerbose = exists $attr{global}{verbose};
  my $verbose    = $attr{global}{verbose};
  my $error      = '';

  $attr{global}{verbose} = 0;

  {
      local $SIG{__WARN__} = sub { };
      eval { require $file; 1 } or $error = $@;
  }

  if ($hadVerbose) {
      $attr{global}{verbose} = $verbose;
  }
  else {
      delete $attr{global}{verbose};
  }

return $error;
}

###############################################################
#     Veraltete Version erkennen
#     (liefert 0, wenn kein Zeitstempel gesetzt werden soll)
###############################################################
sub __CheckPerlOutdated {
  my ($pkg, $mAttr, $modMeta) = @_;

  my $info = $pkgStatus{Perl}{pkgs}{$pkg};

  return 1 unless($info->{status} eq 'installed' || $pkg eq 'perl');

  my $reqV  = $modMeta->{prereqs}{runtime}{$mAttr}{$pkg};
  my $instV = $pkgStatus{Perl}{installed}{$pkg};

  return 1 unless(defined $reqV  && $reqV  ne '' && $reqV  ne '0'
               && defined $instV && $instV ne '' && $instV ne '0');

  if (!HAS_METARequirementsRange) {
      $info->{status} = 'unknown';

      return 0;
  }

  my $vRange = CPAN::Meta::Requirements::Range->with_string_requirement ($reqV);

  if (!defined $vRange->accepts($instV)) {
      $info->{status} = 'outdated';
      push @{$pkgStatus{Perl}{outdated}{$pkg}}, $reqV;

      $pkgStatus{Perl}{analyzed} = 1 if(($modMeta->{x_prereqs_src} // '') ne 'META.json' && !$pkgStatus{Perl}{analyzed});
  }

return 1;
}

###############################################################
#     Zähler für fehlende/veraltete Pakete
###############################################################
sub __CountMissing {
  my ($area, $t, $imp) = @_;

  $pkgStatus{counter}{total}++;
  $pkgStatus{counter}{$t}++;
  $pkgStatus{counter}{$imp}{total}++;
  $pkgStatus{counter}{$imp}{$t}++;
  $pkgStatus{counter}{$imp}{$area}{total}++;
  $pkgStatus{counter}{$imp}{$area}{$t}++;
  $pkgStatus{counter}{$area}{total}++;
  $pkgStatus{counter}{$area}{$t}++;
  $pkgStatus{counter}{$area}{$imp}{total}++;
  $pkgStatus{counter}{$area}{$imp}{$t}++;

return;
}

###############################################################
#     Installations-Hash aufbauen
#     (fehlende/veraltete Pakete nach Wichtigkeit gruppieren)
###############################################################
sub __BuildInstallHash {
  my @levels = (                                           # Wichtigkeit, Schlüssel in modules
      ['required',    'requires'  ],
      ['recommended', 'recommends'],
      ['suggested',   'suggests'  ],
  );

  for my $area (keys %pkgStatus) {
      for my $t (qw(missing outdated)) {
          my $list = $pkgStatus{$area}{$t};

          if (ref $list eq 'HASH' && scalar keys %{$list} > 0) {
              for my $pkg (keys %{$list}) {
                  next unless(ref $list->{$pkg} eq 'ARRAY');

                  # minimal erforderliche Version
                  my $v = maxNum(0, @{$list->{$pkg}});
                  $list->{$pkg} = $v;

                  my $mods = $pkgStatus{$area}{pkgs}{$pkg}{modules};

                  # die höchste vorhandene Wichtigkeit bestimmt die Gruppe
                  for my $i (0 .. $#levels) {
                      my ($imp, $key) = @{$levels[$i]};

                      my $modList = $mods ? $mods->{$key} : undef;
                      next unless(defined $modList && @{$modList} > 0);

                      __CountMissing($area, $t, $imp);

                      my $entry = $pkgStatus{$imp}{$area}{$pkg} //= {};
                      $entry->{status}  = $t;
                      $entry->{version} = $v;
                      $entry->{modules} = $modList;

                      # Module mit geringerer Wichtigkeit ergänzen
                      for my $lower (@levels[$i + 1 .. $#levels]) {
                          my $other = $mods->{$lower->[1]};
                          next unless(defined $other && @{$other} > 0);

                          __PushUnique($entry->{modules}, @{$other});
                      }

                      last;
                  }
              }
          }
          else {
              $pkgStatus{counter}{$t} = 0;
              $pkgStatus{counter}{$area}{$t} = 0;

              for my $imp (qw(required recommended suggested)) {
                  $pkgStatus{counter}{$imp}{$t}               = 0;
                  $pkgStatus{counter}{$imp}{$area}{$t}        = 0;
                  $pkgStatus{counter}{$area}{$imp}{$t}        = 0;
              }
          }
      }
  }

return;
}

###############################################################
#     Hilfsfunktionen
###############################################################

#TODO
# Prüft, ob ein NodeJS-Paket im System installiert ist
sub __IsInstalledNodejs {
  return 0 unless(__PACKAGE__ eq caller(0));
  return 0 unless(@_);

  my ($pkg) = @_;

return 0;
}

#TODO
# Prüft, ob ein Python-Paket im System installiert ist
sub __IsInstalledPython {
  return 0 unless(__PACKAGE__ eq caller(0));
  return 0 unless(@_);

  my ($pkg) = @_;

return 0;
}

# PATH um die Perl-Installationsverzeichnisse erweitern
sub __GetExtendedEnvPath {
  return 0 unless(__PACKAGE__ eq caller(0));

  my @binpath = map { $Config::Config{$_} } qw(
      installsitebin
      installsitescript
      sitebin
      sitescript
      installscript
      installvendorbin
      installvendorscript
      initialinstalllocation
      bin
  );

  my @path = split(/:/, $ENV{PATH});

  for my $p (reverse @binpath) {
      next unless($p && $p ne '');

      $p =~ s/\\/\\\\/g if($^O =~ m/Win/);

      unshift @path, $p unless(grep { $_ eq $p } @path);
  }

return join(':', @path);
}

# heutiges Datum als YYYY-MM-DD
sub __ToDay () {
  my ($mday, $month, $year) = (localtime(gettimeofday()))[3, 4, 5];

return sprintf('%04d-%02d-%02d', $year + 1900, $month + 1, $mday);
}

# doppelte Elemente entfernen (Reihenfolge bleibt)
sub __aUniq {
  my %seen;

return grep { !$seen{$_}++ } @_;
}

# gehört die Funktion zum angegebenen Package?
sub __in_package {
  return 0 unless(__PACKAGE__ eq caller(0));

  my ($coderef, $package) = @_;

  my $cv = svref_2object ($coderef);

  return if(!$cv->isa('B::CV') || $cv->GV->isa('B::SPECIAL'));

return $cv->GV->STASH->NAME eq $package;
}

# Funktionen eines Packages auflisten
sub __list_module {
  return 0 unless(__PACKAGE__ eq caller(0));

  my ($module, $inPackage) = @_;

  no strict 'refs';

return grep { defined &{"${module}::$_"} && ($inPackage ? __in_package(\&{"${module}::$_"}, $module) : 1) }
              keys %{"${module}::"};
}

1;

=pod
=encoding utf8
=item helper
=item summary       Module to help with FHEM installations
=item summary_DE    Modul zur Unterstuetzung bei FHEM Installationen

=begin html

<a id="Installer"></a>
<h3>Installer</h3>
<ul>
  <b>Note: This module is designed for Linux/Unix systems because it uses <code>sh</code>, <code>sudo</code> and <code>cpanm</code>.</b><br><br>
  Helps to manage the system prerequisites of FHEM: The module determines which Perl packages are required by the FHEM modules in use and whether they are
  installed or outdated, and installs, updates or removes Perl packages using <code>cpanm</code>.
  It also shows metadata about FHEM modules and packages (authors, support, repository, dependencies) and provides a search across devices, modules, packages, keywords, authors and Perl packages. <br>
  Currently, Perl packages are supported. The module is closely linked to the module FHEM::Meta.pm. <br>
  For more information, see the accompanying Wiki articles (German) on <a href="https://wiki.fhem.de/wiki/Meta">Meta</a> and <a href="https://wiki.fhem.de/wiki/CPAN">CPAN</a>.
  <br><br>

  <b>Prerequisites</b>
  <ul>
    <li>A JSON module: <code>JSON::PP</code> (part of Perl), preferably <code>JSON</code>, <code>JSON::XS</code> or <code>Cpanel::JSON::XS</code>. Without a JSON module no device can be defined.</li>
    <li><code>cpanm</code> (<code>App::cpanminus</code>) for installing and <code>cpan-outdated</code> (<code>App::cpanoutdated</code>) for detecting outdated packages.
        Both can be installed with <code>set &lt;name&gt; installPerl App::cpanminus</code> or <code>set &lt;name&gt; installPerl App::cpanoutdated</code>, which requires <code>curl</code> or <code>wget</code>.</li>
    <li>Passwordless <code>sudo</code> for the FHEM user. Installations are executed via <code>sudo -n</code> or <code>sudo -H -n</code>.
        If the permission is missing, the module reports the error and shows the required lines for <code>/etc/sudoers.d/&lt;user&gt;</code> in <code>get &lt;name&gt; showErrorList</code>. Example (check the paths with <code>which cpanm</code> and <code>which perl</code>):<br>
        <code>fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/cpanm *</code><br>
        <code>fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/perl - App\:\:cpanminus</code></li>
  </ul>
  <br>

  <a id="Installer-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Installer</code><br><br>
    The module has no parameters. Only one instance can be defined.<br>
    Example: <code>define fhemInstaller Installer</code><br><br>
    When the device is created for the first time, the module sets presets for FHEMWEB (<code>alias</code>, <code>devStateIcon</code>, <code>group</code>, <code>icon</code> and <code>room</code>).
    After FHEM has started, it loads the metadata of the modules in use and requests the versions of Perl and <code>cpanm</code>.
    The list of outdated Perl packages is then updated automatically once a day (every 4 hours it is checked whether the date has changed since the last update).
  </ul>
  <br>

  <a id="Installer-set"></a>
  <b>Set</b>
  <ul>
    All actions run in the background in a separate process, FHEM is not blocked. While an action is running, <b>state</b> shows
    <code>command '&lt;command&gt;' in progress</code>. After a successful installation, update or removal, the list of outdated packages is determined again automatically.<br>
    Which set commands are offered depends on the progress of the detection: As long as <code>cpanm</code> has not been detected, only <b>statusRequest</b> and <b>installPerl App::cpanminus</b> are available,
    afterwards (until <code>cpan-outdated</code> has been detected) <b>installPerl App::cpanoutdated</b>, and then all commands.
    <br><br>

    <a id="Installer-set-installPerl"></a>
    <li><b>installPerl &lt;package&gt; [package ...]</b><br>
        Installs one or more Perl packages using <code>cpanm</code>. Optionally a version can be given (<code>package@version</code>).
        The behavior can be controlled with the attributes <a href="#Installer-attr-installPerlReinstall">installPerlReinstall</a>, <a href="#Installer-attr-installPerlNoTest">installPerlNoTest</a>
        and <a href="#Installer-attr-installPerlEnforced">installPerlEnforced</a>.<br>
        Example: <code>set fhemInstaller installPerl JSON::XS Net::MQTT::Simple@1.29</code>
    </li>
    <br>

    <a id="Installer-set-outdatedPerl"></a>
    <li><b>outdatedPerl</b><br>
        Determines which installed Perl packages are outdated and updates the list of installed Perl packages.
        The result is stored in the readings <b>outdatedPerl</b> and <b>updatesAvailablePerl</b> and can be displayed with <code>'get &lt;name&gt; showOutdatedPerlList'</code>.
    </li>
    <br>

    <a id="Installer-set-statusRequest"></a>
    <li><b>statusRequest</b><br>
        Requests the versions of Perl and <code>cpanm</code> and checks whether <code>cpan-outdated</code> is installed.
    </li>
    <br>

    <a id="Installer-set-updatePerl"></a>
    <li><b>updatePerl [all|package ...]</b><br>
        Updates outdated Perl packages. Without an argument or with <b>all</b>, all updatable packages are updated. Which packages these are is determined by the attributes
        <a href="#Installer-attr-updatePerlDualLifeModules">updatePerlDualLifeModules</a> and <a href="#Installer-attr-updatePerlUsedModulesOnly">updatePerlUsedModulesOnly</a>.
        Individual packages can also be given, separated by spaces, optionally with a version (<code>package@version</code>). This requires that
        <b>outdatedPerl</b> has been executed before and that the package was detected as outdated.<br>
        Example: <code>set fhemInstaller updatePerl all</code>
    </li>
    <br>

    <a id="Installer-set-uninstallPerl"></a>
    <li><b>uninstallPerl &lt;package&gt; [package ...]</b><br>
        Removes one or more Perl packages using <code>cpanm -U</code>. <code>cpanminus</code> and <code>cpan-outdated</code> cannot be removed this way.<br>
        Example: <code>set fhemInstaller uninstallPerl JSON::XS</code>
    </li>
    <br>
    
    <a id="Installer-set-zzExportPerlList"></a>
    <li><b>zzExportPerlList &lt;filename&gt;</b><br>
        Exports the list of installed Perl packages (name and version) into a JSON file. An existing file is overwritten.
        The list is taken from the last execution of <b>outdatedPerl</b> and is kept after a restart of FHEM.
        If <b>outdatedPerl</b> has never been executed, the export is rejected. The file is written with the permissions of the FHEM user.<br>
        Example: <code>set fhemInstaller zzExportPerlList /opt/fhem/perl_packages.json</code>
    </li>
    <br>

    <a id="Installer-set-zzImportPerlList"></a>
    <li><b>zzImportPerlList &lt;filename&gt;</b><br>
        Reads an exported JSON package list, compares it with the most recently determined list of locally installed Perl packages and automatically starts the installation
        of all missing packages and of all packages whose local version is older than the one in the file. In each case the version given in the file is installed.
        Packages with a newer local version are left unchanged, the entry <code>Perl</code> is ignored.
        This requires that <b>outdatedPerl</b> has been executed beforehand. The differences can be reviewed in advance with <b>showDiffPerlList</b>.<br>
        Example: <code>set fhemInstaller zzImportPerlList /opt/fhem/perl_packages.json</code>
    </li>
    
  </ul>
  <br>

  <a id="Installer-get"></a>
  <b>Get</b>
  <ul>
    Which get commands are offered in the selection list depends on the attribute <a href="#Installer-attr-installerMode">installerMode</a>.
    Commands that are not offered can still be entered directly.
    <br><br>

    <a id="Installer-get-checkPrereqs"></a>
    <li><b>checkPrereqs [mode]</b><br>
        Lists all missing prerequisites (Perl packages) of the FHEM modules, separated into <i>required</i>, <i>recommended</i> and <i>suggested</i>.
        In FHEMWEB a missing package can be installed directly using the "Install" link.
        What is checked is determined by the parameter:
        <ul>
          <li>no parameter: the running system, i.e. all loaded modules</li>
          <li><code>1</code>: all modules known to FHEM, including unused ones</li>
          <li>the file name of a FHEM configuration file: the modules used there with <code>define</code>. In <code>installerMode</code> <b>install</b> the <code>*.cfg</code> files from the directory of the global attribute <code>modpath</code> are offered for selection.</li>
          <li>a list of module names, separated by spaces: exactly these modules</li>
        </ul>
        Example: <code>get fhemInstaller checkPrereqs 76_SolarForecast</code>
    </li>
    <br>

    <a id="Installer-get-search"></a>
    <li><b>search [search term]</b><br>
        Searches FHEM for device names, module names, package names, keywords, authors and Perl packages.
        The search is not case sensitive. The search term is evaluated as a regular expression, several words are searched in the given order
        with any amount of whitespace between them. Without a search term all hits are shown.<br>
        Example: <code>get fhemInstaller search MQTT</code>
    </li>
    <br>

    <a id="Installer-get-showDiffPerlList"></a>
    <li><b>showDiffPerlList &lt;filename&gt;</b><br>
        Reads an exported JSON package list and compares it with the most recently determined list of locally installed Perl packages.
        The table only shows differences:
        <ul>
          <li><b>Missing</b> - present in the file, not installed locally ("Install" link)</li>
          <li><b>Outdated</b> - an older version is installed locally than in the file ("Update" link, installs the version from the file)</li>
          <li><b>Newer locally</b> - a newer version is installed locally than in the file (no action)</li>
          <li><b>Extra</b> - installed locally but not in the file ("Deinstall" link with confirmation)</li>
        </ul>
        The entry <code>Perl</code> is ignored, <code>App::cpanminus</code> and <code>App::cpanoutdated</code> are never offered for removal.
        This requires that <b>outdatedPerl</b> has been executed beforehand.<br>
        <b>Caution:</b> "Deinstall" can also remove packages that are required by other modules.<br>
        Example: <code>get fhemInstaller showDiffPerlList /opt/fhem/perl_packages.json</code>
    </li>

    <a id="Installer-get-showModuleInfo"></a>
    <li><b>showModuleInfo &lt;module&gt;</b><br>
        Shows the metadata of a FHEM module, for example description, version, authors, license, support, bug tracker, repository and the Perl prerequisites with their installation status,
        as well as the devices defined for it. For <code>fhem.pl</code> specify <b>FHEM</b>.<br>
        Example: <code>get fhemInstaller showModuleInfo FHEM</code>
    </li>
    <br>

    <a id="Installer-get-showPackageInfo"></a>
    <li><b>showPackageInfo &lt;package&gt;</b><br>
        Shows the metadata of a FHEM package, structured like <b>showModuleInfo</b>.<br>
        Only offered in the selection list in <code>installerMode</code> <b>developer</b>.
    </li>
    <br>

    <li><b>showOutdatedPerlList</b><br>
        Shows the outdated Perl packages with installed and latest version. Only packages that are updatable according to the attributes
        <a href="#Installer-attr-updatePerlDualLifeModules">updatePerlDualLifeModules</a> and <a href="#Installer-attr-updatePerlUsedModulesOnly">updatePerlUsedModulesOnly</a> are listed.<br>
        Only offered if there are updatable packages.
    </li>
    <br>

    <a id="Installer-get-showOutdatedPerlList"></a>
    <li><b>showInstalledPerlList</b><br>
        Shows all installed Perl packages with their version, as determined by the last execution of <b>outdatedPerl</b>.<br>
        Only offered if this list is available.
    </li>
    <br>

    <a id="Installer-get-showErrorList"></a>
    <li><b>showErrorList</b><br>
        Shows the errors of the last executed command with error code and description. If the sudo permission is missing, the list also contains the required sudoers lines.<br>
        Only offered if errors are present.
    </li>
    <br>

    <a id="Installer-get-zzGetModuleMETAjson"></a>
    <li><b>zzGetModuleMETAjson &lt;module&gt;</b><br>
        Prints the unmodified metadata of a FHEM module in JSON format. For <code>fhem.pl</code> specify <b>FHEM</b>.<br>
        Only offered in the selection list in <code>installerMode</code> <b>developer</b>.
    </li>
    <br>

    <a id="Installer-get-zzGetPackageMETAjson"></a>
    <li><b>zzGetPackageMETAjson &lt;package&gt;</b><br>
        Prints the unmodified metadata of a FHEM package in JSON format.<br>
        Only offered in the selection list in <code>installerMode</code> <b>developer</b>.
    </li>
  </ul>
  <br>

  <a id="Installer-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="Installer-attr-disable"></a>
    <li><b>disable</b> <br>
    Disables the device. The automatic queries (at startup and by timer) are suspended, <b>state</b> is <b>disabled</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-disabledForIntervals"></a>
    <li><b>disabledForIntervals HH:MM-HH:MM HH:MM-HH:MM ...</b> <br>
    Disables the device during the given time intervals, works like <b>disable</b>. Several intervals can be given, separated by spaces,
    for example <code>13:00-18:30 22:00-23:00</code>.
    </li>
    <br>

    <a id="Installer-attr-installerMode"></a>
    <li><b>installerMode update | developer | install</b> <br>
    Determines which get commands are offered and which selection is available for them:
    <ul>
      <li><b>update</b> - <b>showModuleInfo</b> only offers loaded modules, <b>checkPrereqs</b> checks the running system.</li>
      <li><b>developer</b> - additionally <b>showPackageInfo</b>, <b>zzGetModuleMETAjson</b> and <b>zzGetPackageMETAjson</b> are offered, <b>showModuleInfo</b> and <b>zzGetModuleMETAjson</b> offer all modules.</li>
      <li><b>install</b> - <b>showModuleInfo</b> offers all modules, <b>checkPrereqs</b> offers the configuration files (<code>*.cfg</code>) from the directory of the global attribute <code>modpath</code> for selection.</li>
    </ul>
    (default: update)
    </li>
    <br>

    <a id="Installer-attr-updateListReading"></a>
    <li><b>updateListReading 0 | 1</b> <br>
    Additionally writes the list of outdated Perl packages as JSON to the reading <b>updateListAsJSON</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-updatePerlDualLifeModules"></a>
    <li><b>updatePerlDualLifeModules 0 | 1</b> <br>
    Perl packages that are also part of Perl itself (dual-life modules) are normally updated together with Perl.
    With <b>0</b> they are not included in the list of updatable packages, with <b>1</b> they are. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-updatePerlUsedModulesOnly"></a>
    <li><b>updatePerlUsedModulesOnly 0 | 1</b> <br>
    With <b>1</b> only packages are offered as updatable that are listed as a prerequisite in the metadata of the FHEM modules in use.
    With <b>0</b> all outdated packages (unless excluded by <b>updatePerlDualLifeModules</b>) appear in the list of <b>updatePerl</b>, <b>showOutdatedPerlList</b> and in the reading <b>updatesAvailablePerl</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlReinstall"></a>
    <li><b>installPerlReinstall 0 | 1</b> <br>
    With <b>1</b> packages are reinstalled by <b>installPerl</b> and <b>updatePerl</b> even if they are already installed (<code>cpanm --reinstall</code>). <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlNoTest"></a>
    <li><b>installPerlNoTest 0 | 1</b> <br>
    With <b>1</b> the tests of the packages are skipped during installation (<code>cpanm --notest</code>). This speeds up the installation, but a faulty package will not be detected. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlEnforced"></a>
    <li><b>installPerlEnforced 0 | 1</b> <br>
    With <b>1</b> packages are installed even if their tests fail (<code>cpanm --force</code>). <br>
    (default: 0)
    </li>
  </ul>
  <br>

  <a id="Installer-Readings"></a>
  <b>Readings</b>
  <ul>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>cpanminusVersion</b>      </td><td>installed version of <code>cpanm</code>                                                                                                            </td></tr>
      <tr><td> <b>installedPerl</b>         </td><td>result of the last execution of <b>installPerl</b>: successful, warning or error                                                                   </td></tr>
      <tr><td> <b>outdatedPerl</b>          </td><td>result of the last detection of outdated packages: <b>check completed</b> or <b>check failed</b>                                                   </td></tr>
      <tr><td> <b>perlVersion</b>           </td><td>version of the Perl interpreter                                                                                                                    </td></tr>
      <tr><td> <b>uninstalledPerl</b>       </td><td>result of the last execution of <b>uninstallPerl</b>: successful, warning or error                                                                 </td></tr>
      <tr><td> <b>updateListAsJSON</b>      </td><td>list of outdated Perl packages in JSON format (only if the attribute <a href="#Installer-attr-updateListReading">updateListReading</a> is set)     </td></tr>
      <tr><td> <b>updatedPerl</b>           </td><td>result of the last execution of <b>updatePerl</b>: successful, warning or error                                                                    </td></tr>
      <tr><td> <b>updatesAvailablePerl</b>  </td><td>number of updatable Perl packages                                                                                                                  </td></tr>
      <tr><td> <b>state</b>                 </td><td>current state of the module. Possible values:                                                                                                      </td></tr>
      <tr><td>                              </td><td><ul><b>initialized</b> - the device was created or FHEM was restarted    </ul>                                                                     </td></tr>
      <tr><td>                              </td><td><ul><b>ready</b> - ready                                                  </ul>                                                                    </td></tr>
      <tr><td>                              </td><td><ul><b>command '&lt;command&gt;' in progress</b> - a command is being executed in the background </ul>                                             </td></tr>
      <tr><td>                              </td><td><ul><b>up to date</b> - there are no updatable Perl packages              </ul>                                                                    </td></tr>
      <tr><td>                              </td><td><ul><b>updates available</b> - there are updatable Perl packages          </ul>                                                                    </td></tr>
      <tr><td>                              </td><td><ul><b>warning '&lt;command&gt;'</b> - the command finished with warnings  </ul>                                                                   </td></tr>
      <tr><td>                              </td><td><ul><b>error '&lt;command&gt;'</b> - the command failed, details in <code>get &lt;name&gt; showErrorList</code> </ul>                              </td></tr>
      <tr><td>                              </td><td><ul><b>disabled</b> - the device is disabled by <b>disable</b> or <b>disabledForIntervals</b> </ul>                                                </td></tr>
      <tr><td>                              </td><td><ul><b>Cannot execute command asynchronously</b> - the background process could not be started </ul>                                               </td></tr>
    </table>
  </ul>

</ul>

=end html

=begin html_DE

<a id="Installer"></a>
<h3>Installer</h3>
<ul>
  <b>Hinweis: Dieses Modul ist für Linux-/Unix-Systeme ausgelegt, da es <code>sh</code>, <code>sudo</code> und <code>cpanm</code> verwendet.</b><br><br>
  Unterstützt bei der Verwaltung der Systemvoraussetzungen von FHEM: Das Modul ermittelt, welche Perl-Pakete die verwendeten FHEM-Module benötigen und ob diese
  installiert oder veraltet sind, und installiert, aktualisiert oder entfernt Perl-Pakete mit <code>cpanm</code>.
  Zusätzlich zeigt es Metadaten zu FHEM-Modulen und -Packages (Autoren, Support, Repository, Abhängigkeiten) und bietet eine Suche über Devices, Module, Packages, Keywords, Autoren und Perl-Pakete. <br>
  Derzeit werden Perl-Pakete unterstützt. Das Modul ist eng mit dem Modul FHEM::Meta.pm verknüpft. <br>
  Weiterführende Informationen enthalten die begleitenden Wiki Artikel zu <a href="https://wiki.fhem.de/wiki/Meta">Meta</a> und <a href="https://wiki.fhem.de/wiki/CPAN">CPAN</a>.
  <br><br>

  <b>Voraussetzungen</b>
  <ul>
    <li>Ein JSON-Modul: <code>JSON::PP</code> (Bestandteil von Perl), besser <code>JSON</code>, <code>JSON::XS</code> oder <code>Cpanel::JSON::XS</code>. Ohne JSON-Modul kann kein Device angelegt werden.</li>
    <li><code>cpanm</code> (<code>App::cpanminus</code>) zum Installieren und <code>cpan-outdated</code> (<code>App::cpanoutdated</code>) zum Ermitteln veralteter Pakete.
        Beide können über <code>set &lt;name&gt; installPerl App::cpanminus</code> bzw. <code>set &lt;name&gt; installPerl App::cpanoutdated</code> installiert werden, dafür wird <code>curl</code> oder <code>wget</code> benötigt.</li>
    <li>Passwortloses <code>sudo</code> für den FHEM-Benutzer. Installationen laufen über <code>sudo -n</code> bzw. <code>sudo -H -n</code>.
        Fehlt die Berechtigung, meldet das Modul den Fehler und zeigt in <code>get &lt;name&gt; showErrorList</code> die benötigten Zeilen für <code>/etc/sudoers.d/&lt;Benutzer&gt;</code> an. Beispiel (Pfade ggf. mit <code>which cpanm</code> und <code>which perl</code> prüfen):<br>
        <code>fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/cpanm *</code><br>
        <code>fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/perl - App\:\:cpanminus</code></li>
  </ul>
  <br>

  <a id="Installer-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Installer</code><br><br>
    Das Modul hat keine Parameter. Es kann nur eine Instanz definiert werden.<br>
    Beispiel: <code>define fhemInstaller Installer</code><br><br>
    Beim erstmaligen Anlegen setzt das Modul Voreinstellungen für FHEMWEB (<code>alias</code>, <code>devStateIcon</code>, <code>group</code>, <code>icon</code> und <code>room</code>).
    Nach dem Start von FHEM lädt es die Metadaten der verwendeten Module und fragt die Versionen von Perl und <code>cpanm</code> ab.
    Danach wird die Liste der veralteten Perl-Pakete einmal täglich automatisch aktualisiert (Prüfung alle 4 Stunden, ob sich das Datum seit der letzten Aktualisierung geändert hat).
  </ul>
  <br>

  <a id="Installer-set"></a>
  <b>Set</b>
  <ul>
    Alle Aktionen laufen im Hintergrund in einem eigenen Prozess, FHEM wird nicht blockiert. Der <b>state</b> zeigt während der Ausführung
    <code>command '&lt;Kommando&gt;' in progress</code>. Nach erfolgreicher Installation, Aktualisierung oder Deinstallation wird die Liste der veralteten Pakete automatisch neu ermittelt.<br>
    Welche Set-Befehle angeboten werden, hängt vom Stand der Ermittlung ab: Solange <code>cpanm</code> nicht erkannt wurde, stehen nur <b>statusRequest</b> und <b>installPerl App::cpanminus</b> zur Verfügung,
    danach (bis <code>cpan-outdated</code> erkannt wurde) <b>installPerl App::cpanoutdated</b>, anschließend alle Befehle.
    <br><br>

    <a id="Installer-set-installPerl"></a>
    <li><b>installPerl &lt;Paket&gt; [Paket ...]</b><br>
        Installiert ein oder mehrere Perl-Pakete mit <code>cpanm</code>. Optional kann eine Version angegeben werden (<code>Paket@Version</code>).
        Das Verhalten lässt sich mit den Attributen <a href="#Installer-attr-installPerlReinstall">installPerlReinstall</a>, <a href="#Installer-attr-installPerlNoTest">installPerlNoTest</a>
        und <a href="#Installer-attr-installPerlEnforced">installPerlEnforced</a> steuern.<br>
        Beispiel: <code>set fhemInstaller installPerl JSON::XS Net::MQTT::Simple@1.29</code>
    </li>
    <br>
    
    <a id="Installer-set-outdatedPerl"></a>
    <li><b>outdatedPerl</b><br>
        Ermittelt, welche installierten Perl-Pakete veraltet sind, und aktualisiert die Liste der installierten Perl-Pakete.
        Das Ergebnis steht in den Readings <b>outdatedPerl</b> und <b>updatesAvailablePerl</b> und kann mit <code>'get &lt;name&gt; showOutdatedPerlList'</code> angezeigt werden.
    </li>
    <br>

    <a id="Installer-set-statusRequest"></a>
    <li><b>statusRequest</b><br>
        Fragt die Versionen von Perl und <code>cpanm</code> ab und prüft, ob <code>cpan-outdated</code> installiert ist.
    </li>
    <br>

    <a id="Installer-set-updatePerl"></a>
    <li><b>updatePerl [all|Paket ...]</b><br>
        Aktualisiert veraltete Perl-Pakete. Ohne Angabe oder mit <b>all</b> werden alle aktualisierbaren Pakete aktualisiert. Welche Pakete das sind, bestimmen die Attribute
        <a href="#Installer-attr-updatePerlDualLifeModules">updatePerlDualLifeModules</a> und <a href="#Installer-attr-updatePerlUsedModulesOnly">updatePerlUsedModulesOnly</a>.
        Es können auch einzelne Pakete, durch Leerzeichen getrennt, angegeben werden, optional mit Version (<code>Paket@Version</code>). Voraussetzung ist, dass vorher
        <b>outdatedPerl</b> ausgeführt wurde und das Paket dort als veraltet erkannt wurde.<br>
        Beispiel: <code>set fhemInstaller updatePerl all</code>
    </li>
    <br>

    <a id="Installer-set-uninstallPerl"></a>
    <li><b>uninstallPerl &lt;Paket&gt; [Paket ...]</b><br>
        Entfernt ein oder mehrere Perl-Pakete mit <code>cpanm -U</code>. <code>cpanminus</code> und <code>cpan-outdated</code> können auf diesem Weg nicht entfernt werden.<br>
        Beispiel: <code>set fhemInstaller uninstallPerl JSON::XS</code>
    </li>
    <br>
    
    <a id="Installer-set-zzExportPerlList"></a>
    <li><b>zzExportPerlList &lt;Dateiname&gt;</b><br>
        Exportiert die Liste der installierten Perl-Pakete (Name und Version) in eine JSON-Datei. Eine bereits vorhandene Datei wird überschrieben.
        Die Liste stammt aus der letzten Ausführung von <b>outdatedPerl</b> und bleibt auch nach einem Neustart von FHEM erhalten.
        Wurde <b>outdatedPerl</b> noch nie ausgeführt, wird der Export abgelehnt. Die Datei wird mit den Rechten des FHEM-Benutzers geschrieben.<br>
        Beispiel: <code>set fhemInstaller zzExportPerlList /opt/fhem/perl_packages.json</code>
    </li>
    <br>

    <a id="Installer-set-zzImportPerlList"></a>
    <li><b>zzImportPerlList &lt;Dateiname&gt;</b><br>
        Liest eine exportierte JSON-Paketliste ein, vergleicht sie mit der zuletzt ermittelten Liste der lokal installierten Perl-Pakete und startet automatisch die Installation
        aller fehlenden Pakete sowie aller Pakete, deren lokale Version älter ist als in der Datei. Installiert wird jeweils die in der Datei angegebene Version.
        Pakete mit neuerer lokaler Version bleiben unverändert, der Eintrag <code>Perl</code> wird ignoriert.
        Voraussetzung ist, dass vorher <b>outdatedPerl</b> ausgeführt wurde. Die Unterschiede können vorab mit <b>showDiffPerlList</b> angesehen werden.<br>
        Beispiel: <code>set fhemInstaller zzImportPerlList /opt/fhem/perl_packages.json</code>
    </li>
    
  </ul>
  <br>

  <a id="Installer-get"></a>
  <b>Get</b>
  <ul>
    Welche Get-Befehle in der Auswahlliste angeboten werden, hängt vom Attribut <a href="#Installer-attr-installerMode">installerMode</a> ab.
    Nicht angebotene Befehle können trotzdem direkt eingegeben werden.
    <br><br>

    <a id="Installer-get-checkPrereqs"></a>
    <li><b>checkPrereqs [Modus]</b><br>
        Listet alle fehlenden Voraussetzungen (Perl-Pakete) der FHEM-Module auf, getrennt nach <i>required</i> (erforderlich), <i>recommended</i> (empfohlen) und <i>suggested</i> (optional).
        In FHEMWEB kann ein fehlendes Paket direkt über den Link "Install" installiert werden.
        Was geprüft wird, bestimmt der Parameter:
        <ul>
          <li>ohne Parameter: das laufende System, also alle geladenen Module</li>
          <li><code>1</code>: alle Module, die FHEM kennt, auch nicht verwendete</li>
          <li>ein Dateiname einer FHEM-Konfigurationsdatei: die darin mit <code>define</code> verwendeten Module. Im <code>installerMode</code> <b>install</b> werden die <code>*.cfg</code>-Dateien aus dem Verzeichnis des globalen Attributs <code>modpath</code> zur Auswahl angeboten.</li>
          <li>eine Liste von Modulnamen, durch Leerzeichen getrennt: genau diese Module</li>
        </ul>
        Beispiel: <code>get fhemInstaller checkPrereqs 76_SolarForecast</code>
    </li>
    <br>

    <a id="Installer-get-search"></a>
    <li><b>search [Suchbegriff]</b><br>
        Durchsucht FHEM nach Device-Namen, Modulnamen, Package-Namen, Keywords, Autoren und Perl-Paketen.
        Die Suche unterscheidet nicht zwischen Groß- und Kleinschreibung. Der Suchbegriff wird als regulärer Ausdruck ausgewertet, mehrere Wörter werden in dieser Reihenfolge
        mit beliebigem Leerraum dazwischen gesucht. Ohne Suchbegriff werden alle Treffer angezeigt.<br>
        Beispiel: <code>get fhemInstaller search MQTT</code>
    </li>
    <br>

    <a id="Installer-get-showDiffPerlList"></a>
    <li><b>showDiffPerlList &lt;Dateiname&gt;</b><br>
        Liest eine exportierte JSON-Paketliste ein und vergleicht sie mit der zuletzt ermittelten Liste der lokal installierten Perl-Pakete.
        Die Tabelle zeigt nur Abweichungen:
        <ul>
          <li><b>Missing</b> - in der Datei vorhanden, lokal nicht installiert (Link "Install")</li>
          <li><b>Outdated</b> - lokal ist eine ältere Version installiert als in der Datei (Link "Update", installiert die Version aus der Datei)</li>
          <li><b>Newer locally</b> - lokal ist eine neuere Version installiert als in der Datei (keine Aktion)</li>
          <li><b>Extra</b> - lokal installiert, aber nicht in der Datei (Link "Deinstall" mit Rückfrage)</li>
        </ul>
        Der Eintrag <code>Perl</code> wird ignoriert, <code>App::cpanminus</code> und <code>App::cpanoutdated</code> werden nie zur Deinstallation angeboten.
        Voraussetzung ist, dass vorher <b>outdatedPerl</b> ausgeführt wurde.<br>
        <b>Achtung:</b> Mit "Deinstall" können auch Pakete entfernt werden, die von anderen Modulen benötigt werden.<br>
        Beispiel: <code>get fhemInstaller showDiffPerlList /opt/fhem/perl_packages.json</code>
    </li>

    <a id="Installer-get-showModuleInfo"></a>
    <li><b>showModuleInfo &lt;Modul&gt;</b><br>
        Zeigt die Metadaten eines FHEM-Moduls an, zum Beispiel Beschreibung, Version, Autoren, Lizenz, Support, Bugtracker, Repository und die Perl-Voraussetzungen mit ihrem Installationsstatus,
        sowie die dazu definierten Devices. Für <code>fhem.pl</code> wird <b>FHEM</b> angegeben.<br>
        Beispiel: <code>get fhemInstaller showModuleInfo FHEM</code>
    </li>
    <br>

    <a id="Installer-get-showPackageInfo"></a>
    <li><b>showPackageInfo &lt;Package&gt;</b><br>
        Zeigt die Metadaten eines FHEM-Packages an, aufgebaut wie bei <b>showModuleInfo</b>.<br>
        Wird nur im <code>installerMode</code> <b>developer</b> in der Auswahlliste angeboten.
    </li>
    <br>

    <a id="Installer-get-showOutdatedPerlList"></a>
    <li><b>showOutdatedPerlList</b><br>
        Zeigt die veralteten Perl-Pakete mit installierter und aktueller Version an. Es werden nur die Pakete aufgeführt, die laut den Attributen
        <a href="#Installer-attr-updatePerlDualLifeModules">updatePerlDualLifeModules</a> und <a href="#Installer-attr-updatePerlUsedModulesOnly">updatePerlUsedModulesOnly</a> aktualisierbar sind.<br>
        Wird nur angeboten, wenn es aktualisierbare Pakete gibt.
    </li>
    <br>

    <li><b>showInstalledPerlList</b><br>
        Zeigt alle installierten Perl-Pakete mit Version an, wie bei der letzten Ausführung von <b>outdatedPerl</b> ermittelt.<br>
        Wird nur angeboten, wenn diese Liste vorhanden ist.
    </li>
    <br>

    <a id="Installer-get-showErrorList"></a>
    <li><b>showErrorList</b><br>
        Zeigt die Fehler des zuletzt ausgeführten Befehls mit Fehlercode und Beschreibung an. Bei fehlender sudo-Berechtigung enthält die Liste auch die erforderlichen sudoers-Zeilen.<br>
        Wird nur angeboten, wenn Fehler vorliegen.
    </li>
    <br>

    <a id="Installer-get-zzGetModuleMETAjson"></a>
    <li><b>zzGetModuleMETAjson &lt;Modul&gt;</b><br>
        Gibt die unveränderten Metadaten eines FHEM-Moduls im JSON-Format aus. Für <code>fhem.pl</code> wird <b>FHEM</b> angegeben.<br>
        Wird nur im <code>installerMode</code> <b>developer</b> in der Auswahlliste angeboten.
    </li>
    <br>

    <a id="Installer-get-zzGetPackageMETAjson"></a>
    <li><b>zzGetPackageMETAjson &lt;Package&gt;</b><br>
        Gibt die unveränderten Metadaten eines FHEM-Packages im JSON-Format aus.<br>
        Wird nur im <code>installerMode</code> <b>developer</b> in der Auswahlliste angeboten.
    </li>
  </ul>
  <br>

  <a id="Installer-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="Installer-attr-disable"></a>
    <li><b>disable</b> <br>
    Deaktiviert das Device. Die automatischen Abfragen (beim Start und per Timer) werden ausgesetzt, der <b>state</b> ist <b>disabled</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-disabledForIntervals"></a>
    <li><b>disabledForIntervals HH:MM-HH:MM HH:MM-HH:MM ...</b> <br>
    Deaktiviert das Device in den angegebenen Zeiträumen, wirkt wie <b>disable</b>. Es können mehrere Zeiträume durch Leerzeichen getrennt angegeben werden,
    zum Beispiel <code>13:00-18:30 22:00-23:00</code>.
    </li>
    <br>

    <a id="Installer-attr-installerMode"></a>
    <li><b>installerMode update | developer | install</b> <br>
    Legt fest, welche Get-Befehle angeboten werden und welche Auswahl dabei zur Verfügung steht:
    <ul>
      <li><b>update</b> - <b>showModuleInfo</b> bietet nur geladene Module an, <b>checkPrereqs</b> prüft das laufende System.</li>
      <li><b>developer</b> - zusätzlich werden <b>showPackageInfo</b>, <b>zzGetModuleMETAjson</b> und <b>zzGetPackageMETAjson</b> angeboten, <b>showModuleInfo</b> und <b>zzGetModuleMETAjson</b> bieten alle Module an.</li>
      <li><b>install</b> - <b>showModuleInfo</b> bietet alle Module an, <b>checkPrereqs</b> bietet die Konfigurationsdateien (<code>*.cfg</code>) aus dem Verzeichnis des globalen Attributs <code>modpath</code> zur Auswahl an.</li>
    </ul>
    (default: update)
    </li>
    <br>

    <a id="Installer-attr-updateListReading"></a>
    <li><b>updateListReading 0 | 1</b> <br>
    Schreibt die Liste der veralteten Perl-Pakete zusätzlich als JSON in das Reading <b>updateListAsJSON</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-updatePerlDualLifeModules"></a>
    <li><b>updatePerlDualLifeModules 0 | 1</b> <br>
    Perl-Pakete, die auch Bestandteil von Perl selbst sind (Dual-Life-Module), werden normalerweise zusammen mit Perl aktualisiert.
    Mit <b>0</b> werden sie nicht in die Liste der aktualisierbaren Pakete aufgenommen, mit <b>1</b> schon. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-updatePerlUsedModulesOnly"></a>
    <li><b>updatePerlUsedModulesOnly 0 | 1</b> <br>
    Mit <b>1</b> werden nur Pakete als aktualisierbar angeboten, die in den Metadaten der verwendeten FHEM-Module als Voraussetzung eingetragen sind.
    Mit <b>0</b> erscheinen alle veralteten Pakete (soweit nicht durch <b>updatePerlDualLifeModules</b> ausgeschlossen) in der Liste von <b>updatePerl</b>, <b>showOutdatedPerlList</b> und im Reading <b>updatesAvailablePerl</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlReinstall"></a>
    <li><b>installPerlReinstall 0 | 1</b> <br>
    Mit <b>1</b> werden Pakete bei <b>installPerl</b> und <b>updatePerl</b> auch dann neu installiert, wenn sie bereits installiert sind (<code>cpanm --reinstall</code>). <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlNoTest"></a>
    <li><b>installPerlNoTest 0 | 1</b> <br>
    Mit <b>1</b> werden die Tests der Pakete bei der Installation übersprungen (<code>cpanm --notest</code>). Das beschleunigt die Installation, ein fehlerhaftes Paket wird dadurch aber nicht erkannt. <br>
    (default: 0)
    </li>
    <br>

    <a id="Installer-attr-installPerlEnforced"></a>
    <li><b>installPerlEnforced 0 | 1</b> <br>
    Mit <b>1</b> werden Pakete auch dann installiert, wenn ihre Tests fehlschlagen (<code>cpanm --force</code>). <br>
    (default: 0)
    </li>
  </ul>
  <br>

  <a id="Installer-Readings"></a>
  <b>Readings</b>
  <ul>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>cpanminusVersion</b>      </td><td>installierte Version von <code>cpanm</code>                                                                                                            </td></tr>
      <tr><td> <b>installedPerl</b>         </td><td>Ergebnis der letzten Ausführung von <b>installPerl</b>: successful, warning oder error                                                                 </td></tr>
      <tr><td> <b>outdatedPerl</b>          </td><td>Ergebnis der letzten Ermittlung veralteter Pakete: <b>check completed</b> oder <b>check failed</b>                                                     </td></tr>
      <tr><td> <b>perlVersion</b>           </td><td>Version des Perl-Interpreters                                                                                                                          </td></tr>
      <tr><td> <b>uninstalledPerl</b>       </td><td>Ergebnis der letzten Ausführung von <b>uninstallPerl</b>: successful, warning oder error                                                               </td></tr>
      <tr><td> <b>updateListAsJSON</b>      </td><td>Liste der veralteten Perl-Pakete im JSON-Format (nur wenn das Attribut <a href="#Installer-attr-updateListReading">updateListReading</a> gesetzt ist)  </td></tr>
      <tr><td> <b>updatedPerl</b>           </td><td>Ergebnis der letzten Ausführung von <b>updatePerl</b>: successful, warning oder error                                                                  </td></tr>
      <tr><td> <b>updatesAvailablePerl</b>  </td><td>Anzahl der aktualisierbaren Perl-Pakete                                                                                                                </td></tr>
      <tr><td> <b>state</b>                 </td><td>aktueller Zustand des Moduls. Mögliche Werte:                                                                                                          </td></tr>
      <tr><td>                              </td><td><ul><b>initialized</b> - das Device wurde angelegt oder FHEM neu gestartet   </ul>                                                                     </td></tr>
      <tr><td>                              </td><td><ul><b>ready</b> - bereit                                                    </ul>                                                                     </td></tr>
      <tr><td>                              </td><td><ul><b>command '&lt;Kommando&gt;' in progress</b> - ein Kommando wird im Hintergrund ausgeführt </ul>                                                  </td></tr>
      <tr><td>                              </td><td><ul><b>up to date</b> - es gibt keine aktualisierbaren Perl-Pakete           </ul>                                                                     </td></tr>
      <tr><td>                              </td><td><ul><b>updates available</b> - es gibt aktualisierbare Perl-Pakete           </ul>                                                                     </td></tr>
      <tr><td>                              </td><td><ul><b>warning '&lt;Kommando&gt;'</b> - das Kommando wurde mit Warnungen beendet </ul>                                                                 </td></tr>
      <tr><td>                              </td><td><ul><b>error '&lt;Kommando&gt;'</b> - das Kommando ist fehlgeschlagen, Details in <code>get &lt;name&gt; showErrorList</code> </ul>                    </td></tr>
      <tr><td>                              </td><td><ul><b>disabled</b> - das Device ist durch <b>disable</b> oder <b>disabledForIntervals</b> deaktiviert </ul>                                           </td></tr>
      <tr><td>                              </td><td><ul><b>Cannot execute command asynchronously</b> - der Hintergrundprozess konnte nicht gestartet werden </ul>                                          </td></tr>
    </table>
  </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 98_Installer.pm
{
  "abstract": "Module to install, update and remove (CPAN) Perl modules and to manage system prerequisites of FHEM",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Installation, Aktualisierung und Deinstallation von (CPAN) Perl-Modulen und zur Verwaltung der Systemvoraussetzungen von FHEM"
    }
  },
  "version": "v1.0.0",
  "release_status": "stable",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "DS_Starter"
  ],
  "keywords": [
    "Dependencies",
    "Prerequisites",
    "Setup"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "Data::Dumper": 0,
        "Encode": 0,
        "FHEM": 5.00918623,
        "FHEM::Meta": 0.001006,
        "FHEM::npmjs": 0,
        "File::stat": 0,
        "GPUtils": 0,
        "HttpUtils": 0,
        "IO::Socket::SSL": 0,
        "Config": 0,
        "ExtUtils::Installed": 0,
        "B": 0,
        "JSON::PP": 0,
        "perl": 5.014,
        "version": 0,
        "SubProcess": 0
      },
      "recommends": {
        "Perl::PrereqScanner::NotQuiteLite": 0,
        "CPAN::Meta::Requirements::Range": "2.143",
        "JSON": 0
      },
      "suggests": {
        "Cpanel::JSON::XS": 0,
        "JSON::XS": 0
      }
    }
  },
  "resources": {
    "bugtracker": {
      "web": "https://github.com/fhem/Installer/issues"
    }
  }
}
=end :application/json;q=META.json

=cut
