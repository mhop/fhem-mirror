########################################################################################################################
# $Id$
#########################################################################################################################
#       98_Analyze.pm
#
#       (c) 2020-2026 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module analyzes the memory usage of the FHEM process: data structures of devices, modules and
#       core hashes, process memory, timers, file descriptors. It supports snapshots, comparison of snapshots
#       and the detection of growing structures (memory leak candidates).
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
#########################################################################################################################
#
# Definition: define <name> Analyze
#
# Example:    define anaData Analyze
#
# Quick start:
#   set anaData snapshot t0              # take a snapshot now (runs in a forked process)
#   ... wait some hours ...
#   set anaData snapshot t1
#   get anaData diff t0 t1               # what changed between both snapshots
#   get anaData leakCandidates           # needs >= 3 snapshots, lists consistently growing objects
#
package FHEM::Analyze;                                                                                    ## no critic 'package'

use strict;
use warnings;
use utf8;
use Scalar::Util qw(refaddr reftype blessed);
use Time::HiRes  qw(gettimeofday tv_interval);
use POSIX        qw(strftime ceil);
use B ();
use File::Spec;
use Data::Dumper;                                                                                         # Perl Core module
use GPUtils qw(GP_Import GP_Export);                                                                      # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Blocking;
use MIME::Base64;
eval "use Devel::Size; 1;"             or my $modSizeAbsent = "Devel::Size";                              ## no critic 'eval'
eval "use Storable qw(freeze thaw);1;" or my $storabs = 'Storable';                                       ## no critic 'eval'
eval "use FHEM::Meta;1"                or my $modMetaAbsent = 1;                                          ## no critic 'eval'
my $hasPadWalker = eval { require PadWalker; 1 } ? 1 : 0;                                                 # optional: erfasst file-scope 'my' Variablen der Module

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          AttrVal
          asyncOutput
          BlockingCall
          BlockingKill
          CommandAttr
          defs
          devspec2array
          getKeyValue
          init_done
          unicodeEncoding
          InternalTimer
          intAt
          IsDisabled
          Log3
          modules
          readingFnAttributes
          readingsBeginUpdate
          readingsBulkUpdate
          readingsDelete
          readingsEndUpdate
          readingsSingleUpdate
          readyfnlist
          RemoveInternalTimer
          selectlist
          setKeyValue
        )
  );

  GP_Export(
      qw(
          Initialize
        )
  );
}

# Versions History intern
  my %vNotesIntern = (
    "0.7.0"  => "10.11.2026  Hinweis: nur Fortschreibung der Version, Tracking der Änderungen in Changelog.md ",
    "0.1.0"  => "25.11.2020  initial "
  );

# Voreinstellungen
  my %hset = (                                                                                           # Hash der Set-Funktion
    snapshot       => { fn => \&_setSnapshot       },
    deleteSnapshot => { fn => \&_setDeleteSnapshot },
    allDevices     => { fn => \&_setDeviceType     },
    deviceType     => { fn => \&_setDeviceType     },
    xHashDetail    => { fn => \&_setTree           },
    mainHash       => { fn => \&_setTree           },
    abortJob       => { fn => \&_setAbortJob       },
    clearCrashList => { fn => \&_setClearCrashList },
  );

  my %hget = (                                                                                           # Hash der Get-Funktion
    snapshots      => { fn => \&_getSnapshots      },
    report         => { fn => \&_getReport         },
    diff           => { fn => \&_getDiff           },
    leakCandidates => { fn => \&_getLeakCandidates },
    timers         => { fn => \&_getTimers         },
    process        => { fn => \&_getProcess        },
    rssTrend       => { fn => \&_getRssTrend       },
    lastResult     => { fn => \&_getLastResult     },
    crashList      => { fn => \&_getCrashList      },
    track          => { fn => \&_getTrack          },
  );

  my %hexcl = ();                                                                                        # keine Standard-Excludes, Typen per Attribut excludeTypes ausschließen

  my @MAINHASHES = qw(attr cmds data defaultattr defs inform intAt logInform modules oldvalue
                      readyfnlist selectlist duplicate internal_data);                                   # FHEM Kernstrukturen

  my $RVSIZE     = 24;                                                                                   # Bytes pro Referenz-Slot (SV head), Devel::Size::size() zählt ihn nicht
  my $CRUMBDEPTH = 2;                                                                                    # bis zu dieser Tiefe wird jedes Kind einzeln gemessen und protokolliert ($defs{dev}{key}{sub})
  my $CRUMBFAN   = 2000;                                                                                 # Container mit mehr Kindern werden nicht einzeln protokolliert
  my %NOWALK     = map { $_ => 1 } qw(CODE GLOB IO FORMAT LVALUE REGEXP);                                # Sockets, Dateihandles, Code usw. werden nie angefasst
  my $PARTMIN    = 512;                                                                                  # nur Teilstrukturen >= $PARTMIN Bytes werden gespeichert

  my %UNIT = (                                                                                           # Einheit je Kategorie im Snapshot ('B' Bytes, 'kB', '#' Anzahl)
    proc => 'kB', cnt => '#', type => 'B', typen => '#', dev => 'B', part => 'B', reads => '#',
    mod  => 'B',  main => 'B', file => 'B', var => 'B',  pkg => 'B', pkgvar => 'B', timer => '#', timerdev => '#',
    track => 'B', trackn => '#',
  );

  my @CATORDER = qw(proc cnt timer timerdev track trackn reads part dev type typen var pkgvar file pkg main mod);    # Reihenfolge der Ausgabe

  my %CATTITLE = (
    proc     => 'Process memory (kB)',
    cnt      => 'Counters',
    timer    => 'Timers by function',
    timerdev => 'Timers by device',
    track    => 'Tracked objects (attribute trackObjects, size)',
    trackn   => 'Tracked objects (attribute trackObjects, number of entries)',
    reads    => 'Readings per device',
    part     => 'Parts of devices ($defs{device}{key})',
    dev      => 'Devices',
    type     => 'Device types (sum of devices)',
    typen    => 'Number of devices per type',
    var      => 'File-scope variables of module files (PadWalker)',
    pkgvar   => 'Package variables (our)',
    file     => 'Module files (file-scope variables, PadWalker)',
    pkg      => 'Packages (our variables)',
    main     => 'FHEM core hashes',
    mod      => 'Module hashes ($modules{TYPE})',
  );

# Texte (EN/DE), Sprache gemäß globalem Attribut 'language' (DE -> deutsch, sonst englisch), Zugriff über _t()
  my %TXT = (
    attr_int         => { EN => q{The value of %s is not valid. Use an integer ≥ %s.},
                          DE => q{Der Wert von %s ist ungültig. Verwende eine ganze Zahl ≥ %s.} },
    attr_hours       => { EN => q{The value of %s is not valid. Use hours as number, e.g. 6 (0 = off).},
                          DE => q{Der Wert von %s ist ungültig. Gib Stunden als Zahl an, z.B. 6 (0 = aus).} },
    attr_sample      => { EN => q{The value of %s must be 0 (off) or at least 60 seconds.},
                          DE => q{Der Wert von %s muss 0 (aus) oder mindestens 60 Sekunden sein.} },
    attr_track       => { EN => q{Invalid entry in %s: "%s". Allowed: $hash{key}[index] (e.g. $defs{myDevice}{.cache}), %%Package::name (also @ and $) or file.pm:%%name.},
                          DE => q{Ungültiger Eintrag in %s: "%s". Erlaubt: $hash{key}[index] (z.B. $defs{meinDevice}{.cache}), %%Paket::name (auch @ und $) oder datei.pm:%%name.} },
    label_invalid    => { EN => q{The label "%s" is not valid. Allowed are letters, digits, '_', '-' and '.'.},
                          DE => q{Das Label "%s" ist ungültig. Erlaubt sind Buchstaben, Ziffern, '_', '-' und '.'.} },
    del_needs        => { EN => q{The command "deleteSnapshot" needs a label or "all".},
                          DE => q{Das Kommando "deleteSnapshot" benötigt ein Label oder "all".} },
    del_all          => { EN => q{all snapshots deleted},
                          DE => q{alle Snapshots gelöscht} },
    snap_missing     => { EN => q{Snapshot "%s" does not exist.},
                          DE => q{Snapshot "%s" existiert nicht.} },
    snap_deleted     => { EN => q{snapshot '%s' deleted},
                          DE => q{Snapshot '%s' gelöscht} },
    no_dev_type      => { EN => q{No device of TYPE "%s" found.},
                          DE => q{Kein Device vom TYPE "%s" gefunden.} },
    tree_needs       => { EN => q{The command "%s" needs an argument, e.g. $defs{myDevice}{helper} or $data.},
                          DE => q{Das Kommando "%s" benötigt ein Argument, z.B. $defs{meinDevice}{helper} oder $data.} },
    not_ref          => { EN => q{%s is not a reference. Value (%d Bytes):},
                          DE => q{%s ist keine Referenz. Wert (%d Bytes):} },
    no_job           => { EN => q{no job is running},
                          DE => q{es läuft kein Job} },
    job_aborted      => { EN => q{job aborted},
                          DE => q{Job abgebrochen} },
    no_snaps         => { EN => q{no snapshots available. Use: set %s snapshot <label>},
                          DE => q{keine Snapshots vorhanden. Verwende: set %s snapshot <label>} },
    snap_notexist_av => { EN => q{Snapshot "%s" does not exist (available: %s)},
                          DE => q{Snapshot "%s" existiert nicht (vorhanden: %s)} },
    need_two         => { EN => q{need at least two snapshots. Use: set %s snapshot <label>},
                          DE => q{es werden mindestens zwei Snapshots benötigt. Verwende: set %s snapshot <label>} },
    snap_missing_av  => { EN => q{Snapshot missing (available: %s)},
                          DE => q{Snapshot fehlt (vorhanden: %s)} },
    need_three       => { EN => q{need at least 3 snapshots (have %d). Take them some hours apart: set %s snapshot <label>},
                          DE => q{es werden mindestens 3 Snapshots benötigt (vorhanden: %d). Lege sie im Abstand von einigen Stunden an: set %s snapshot <label>} },
    proc_hint        => { EN => q{Hint: private/pss/shared change whenever child processes (BlockingCall) start or end. Use rss for trends and compare private/pss only for equal number of child processes.},
                          DE => q{Hinweis: private/pss/shared ändern sich, sobald Kindprozesse (BlockingCall) starten oder enden. Für Trends rss verwenden, private/pss nur bei gleicher Anzahl Kindprozesse vergleichen.} },
    rss_notenough    => { EN => q{not enough samples yet (attribute sampleInterval, default 600 s).},
                          DE => q{noch nicht genug Messwerte (Attribut sampleInterval, Standard 600 s).} },
    rss_ns           => { EN => q{not enough samples},
                          DE => q{nicht genug Messwerte} },
    rss_hint         => { EN => q{Hint: the process size grows after start-up until the Perl heap is warmed up and rarely shrinks afterwards. A trend is only meaningful after some hours; use snapshots/diff to find the cause.},
                          DE => q{Hinweis: die Prozessgröße wächst nach dem Start, bis der Perl-Heap warmgelaufen ist, und schrumpft danach selten. Ein Trend ist erst nach einigen Stunden aussagekräftig; die Ursache lässt sich mit Snapshots/diff finden.} },
    no_result        => { EN => q{no result available yet},
                          DE => q{noch kein Ergebnis vorhanden} },
    job_running      => { EN => q{Job '%s' is still running. Use 'set %s abortJob' to cancel it.},
                          DE => q{Job '%s' läuft noch. Mit 'set %s abortJob' kann er abgebrochen werden.} },
    fork_failed      => { EN => q{Cannot start the background process (fork failed). You can set attribute useFork=0 to analyze inside the FHEM process (blocks FHEM while running).},
                          DE => q{Der Hintergrundprozess kann nicht gestartet werden (fork fehlgeschlagen). Mit dem Attribut useFork=0 kann innerhalb des FHEM-Prozesses analysiert werden (blockiert FHEM während der Laufzeit).} },
    analysis_failed  => { EN => q{Analysis failed: %s},
                          DE => q{Analyse fehlgeschlagen: %s} },
    crash_msg        => { EN => q{Analysis '%s' ended without a result (%s).},
                          DE => q{Analyse '%s' ohne Ergebnis beendet (%s).} },
    crash_last       => { EN => q{Last object being measured: %s},
                          DE => q{Zuletzt gemessenes Objekt: %s} },
    crash_retry      => { EN => q{Crash at %s (%s): object skipped, measurement repeated (attempt %d of %d)},
                          DE => q{Absturz bei %s (%s): Objekt übersprungen, Messung wird wiederholt (Versuch %d von %d)} },
    crash_restartfail=> { EN => q{Restart failed: %s},
                          DE => q{Neustart fehlgeschlagen: %s} },
    crash_maxretry   => { EN => q{The maximum number of automatic retries (%d) is reached. Start the job again, every run skips the objects found so far.},
                          DE => q{Die maximale Anzahl automatischer Wiederholungen (%d) ist erreicht. Den Job erneut starten, jeder Lauf überspringt die bisher gefundenen Objekte.} },
    crash_onlist     => { EN => q{The object is on the crash list and is skipped in future runs (get %s crashList). Remove it with 'set %s clearCrashList <object>' once the cause is fixed.},
                          DE => q{Das Objekt steht auf der Crash-Liste und wird in künftigen Läufen übersprungen (get %s crashList). Nach Behebung der Ursache mit 'set %s clearCrashList <object>' entfernen.} },
    crash_inside     => { EN => q{The crash happened inside this object or its direct content (for example sockets, file handles or magic values).},
                          DE => q{Der Absturz ereignete sich innerhalb dieses Objekts oder seines direkten Inhalts (z.B. Sockets, Dateihandles oder Magic-Werte).} },
    crash_unknown    => { EN => q{The breadcrumb file contains no object, the crash location is unknown.},
                          DE => q{Die Breadcrumb-Datei enthält kein Objekt, die Absturzstelle ist unbekannt.} },
    crash_exclude    => { EN => q{Exclude suspected device types with attribute excludeTypes.},
                          DE => q{Verdächtige Device-Typen mit dem Attribut excludeTypes ausschließen.} },
    crash_empty      => { EN => q{The crash list is empty.},
                          DE => q{Die Crash-Liste ist leer.} },
    crash_head       => { EN => q{Objects that crashed the analysis and are skipped (remove with: set %s clearCrashList <object>|all):},
                          DE => q{Objekte, die die Analyse zum Absturz gebracht haben und übersprungen werden (entfernen mit: set %s clearCrashList <object>|all):} },
    clear_needs      => { EN => q{The command "clearCrashList" needs an object from the crash list or "all".},
                          DE => q{Das Kommando "clearCrashList" benötigt ein Objekt aus der Crash-Liste oder "all".} },
    clear_notlisted  => { EN => q{"%s" is not on the crash list.},
                          DE => q{"%s" steht nicht auf der Crash-Liste.} },
    clear_all        => { EN => q{crash list cleared},
                          DE => q{Crash-Liste geleert} },
    clear_one        => { EN => q{%s removed from the crash list},
                          DE => q{%s von der Crash-Liste entfernt} },
    path_parse       => { EN => q{Cannot parse object path "%s". Example: $defs{myDevice}{helper}},
                          DE => q{Der Objektpfad "%s" kann nicht gelesen werden. Beispiel: $defs{meinDevice}{helper}} },
    path_parse_near  => { EN => q{Cannot parse object path "%s" near "%s"},
                          DE => q{Der Objektpfad "%s" kann bei "%s" nicht gelesen werden} },
    path_noroot      => { EN => q{No hash or array named "%s" found in FHEM.},
                          DE => q{In FHEM wurde kein Hash oder Array "%s" gefunden.} },
    path_nokey       => { EN => q{Key {%s} not found below %s},
                          DE => q{Schlüssel {%s} unterhalb von %s nicht gefunden} },
    path_noidx       => { EN => q{Index [%s] not found below %s},
                          DE => q{Index [%s] unterhalb von %s nicht gefunden} },
    path_notcont     => { EN => q{%s is not a hash or array reference, cannot go down to "%s"},
                          DE => q{%s ist keine Hash- oder Array-Referenz, "%s" kann nicht aufgelöst werden} },
    unattr_note      => { EN => q{  (not attributable = Perl interpreter, loaded code, shared libraries, memory fragmentation)},
                          DE => q{  (nicht zuordenbar = Perl-Interpreter, geladener Code, Shared Libraries, Speicherfragmentierung)} },
    unattr_note_nd   => { EN => q{  (not attributable = Perl interpreter, loaded code, shared libraries, memory fragmentation, file-scope variables of modules - see attribute deepScan)},
                          DE => q{  (nicht zuordenbar = Perl-Interpreter, geladener Code, Shared Libraries, Speicherfragmentierung, file-scope-Variablen der Module - siehe Attribut deepScan)} },
    diff_kids        => { EN => q{  Note: the number of child processes differs - private/pss/shared are not comparable, use rss.},
                          DE => q{  Hinweis: die Anzahl der Kindprozesse unterscheidet sich - private/pss/shared sind nicht vergleichbar, rss verwenden.} },
    diff_hint        => { EN => q{Hint: for a reliable verdict take at least 3 snapshots some hours apart and use "get &lt;name&gt; leakCandidates".},
                          DE => q{Hinweis: für eine belastbare Aussage mindestens 3 Snapshots im Abstand von einigen Stunden anlegen und "get &lt;name&gt; leakCandidates" verwenden.} },
    leak_head        => { EN => q{Leak candidates: objects growing in at least %d of %d intervals without ever shrinking},
                          DE => q{Leak-Kandidaten: Objekte, die in mindestens %d von %d Intervallen wachsen und nie schrumpfen} },
    leak_none        => { EN => q{No consistently growing object found.},
                          DE => q{Kein durchgehend wachsendes Objekt gefunden.} },
    interp_head      => { EN => q{Interpretation:},
                          DE => q{Interpretation:} },
    interp_part      => { EN => q{  part/dev/type  : data inside a device grows (readings, helper hashes, queues, caches) -> look at the TYPE and use "set &lt;name&gt; xHashDetail $defs{device}{key}".},
                          DE => q{  part/dev/type  : Daten innerhalb eines Devices wachsen (Readings, Helper-Hashes, Queues, Caches) -> den TYPE ansehen und "set &lt;name&gt; xHashDetail $defs{device}{key}" verwenden.} },
    interp_var       => { EN => q{  var/pkgvar/file: global or file-scope variables of a module grow (needs deepScan, PadWalker for file-scope variables).},
                          DE => q{  var/pkgvar/file: globale oder file-scope-Variablen eines Moduls wachsen (benötigt deepScan, für file-scope-Variablen zusätzlich PadWalker).} },
    interp_timer     => { EN => q{  timer/timerdev : timers accumulate -> a module sets timers without removing old ones.},
                          DE => q{  timer/timerdev : Timer sammeln sich an -> ein Modul setzt Timer, ohne alte zu entfernen.} },
    interp_cnt       => { EN => q{  cnt fds/kids   : file descriptor or child process leak (e.g. BlockingCall children not ending).},
                          DE => q{  cnt fds/kids   : Leck bei Dateideskriptoren oder Kindprozessen (z.B. BlockingCall-Kinder, die nicht enden).} },
    interp_track     => { EN => q{  track/trackn   : a tracked object (attribute trackObjects) grows in size or number of entries -> see "get &lt;name&gt; track".},
                          DE => q{  track/trackn   : ein getracktes Objekt (Attribut trackObjects) wächst in Größe oder Anzahl der Einträge -> siehe "get &lt;name&gt; track".} },
    interp_proc      => { EN => q{  proc unattributed grows but no structure does: memory outside the walked structures (XS/C libraries, fragmentation, file-scope variables without deepScan).},
                          DE => q{  proc unattributed wächst, aber keine Struktur: Speicher außerhalb der durchsuchten Strukturen (XS/C-Bibliotheken, Fragmentierung, file-scope-Variablen ohne deepScan).} },
    tree_excl        => { EN => q{Sizes are exclusive: shared references and references to other devices/core hashes are counted once or not at all.},
                          DE => q{Die Größen sind exklusiv: gemeinsam genutzte Referenzen sowie Referenzen auf andere Devices/Kern-Hashes werden nur einmal oder gar nicht gezählt.} },
    track_none       => { EN => q{No objects are tracked. Set attribute trackObjects, e.g. trackObjects $defs{myDevice}{.cache} (see commandref).},
                          DE => q{Es werden keine Objekte getrackt. Attribut trackObjects setzen, z.B. trackObjects $defs{meinDevice}{.cache} (siehe Commandref).} },
    track_nosamples  => { EN => q{No samples yet. Tracked objects are measured with every snapshot (set %s snapshot <label> or attribute autoSnapshot).},
                          DE => q{Noch keine Messwerte. Getrackte Objekte werden mit jedem Snapshot gemessen (set %s snapshot <label> oder Attribut autoSnapshot).} },
    track_unknown    => { EN => q{Tracked object "%s" not found. Use "all" or an object from the list (attribute trackObjects).},
                          DE => q{Getracktes Objekt "%s" nicht gefunden. "all" oder ein Objekt aus der Liste (Attribut trackObjects) angeben.} },
    track_hint       => { EN => q{Hint: the values are taken with every snapshot (also automatic ones). Details: get %s track &lt;object&gt;},
                          DE => q{Hinweis: die Werte werden mit jedem Snapshot erfasst (auch automatischen). Details: get %s track &lt;Objekt&gt;} },
    track_shown      => { EN => q{(last %d of %d samples shown)},
                          DE => q{(die letzten %d von %d Messwerten)} },
    track_net        => { EN => q{Net change over %.1f h: %s (%s/h), entries %s (%s/h)},
                          DE => q{Netto-Änderung über %.1f h: %s (%s/h), Einträge %s (%s/h)} },
    track_err_head   => { EN => q{Tracked objects not measured},
                          DE => q{Getrackte Objekte nicht gemessen} },
    track_err_pw     => { EN => q{PadWalker is not installed},
                          DE => q{PadWalker ist nicht installiert} },
    track_err_var    => { EN => q{variable %s not found in %s (it must be used by at least one function of that file)},
                          DE => q{Variable %s in %s nicht gefunden (sie muss von mindestens einer Funktion der Datei verwendet werden)} },
    track_err_pkg    => { EN => q{package variable %s not found},
                          DE => q{Paketvariable %s nicht gefunden} },
    track_err_crash  => { EN => q{on the crash list},
                          DE => q{steht auf der Crash-Liste} },
    track_err_undef  => { EN => q{value is not defined},
                          DE => q{Wert ist nicht definiert} },
  );

################################################################
sub Initialize {
 my ($hash) = @_;
 $hash->{DefFn}                 = \&Define;
 $hash->{UndefFn}               = \&Undef;
 $hash->{DeleteFn}              = \&Delete;
 $hash->{ShutdownFn}            = \&Shutdown;
 $hash->{SetFn}                 = \&Set;
 $hash->{GetFn}                 = \&Get;
 $hash->{AttrFn}                = \&Attr;

 $hash->{FW_deviceOverview}     = 1;

 $hash->{AttrList} = "analyzeObject ".
                     "autoSnapshot ".                                   # Stunden, 0 = aus
                     "crashRetries ".
                     "deepScan:1,0 ".
                     "disable:1,0 ".
                     "excludeTypes ".
                     "forkTimeout ".
                     "largeObjectNum ".
                     "leakMinBytes ".
                     "maxNodes ".
                     "maxSnapshots ".
                     "noOutput:1,0 ".
                     "sampleInterval ".                                 # Sekunden, 0 = aus
                     "topNum ".
                     "trackMaxSamples ".
                     "trackObjects ".
                     "treeDepth ".
                     "useFork:1,0 ".
                     $readingFnAttributes;

 FHEM::Meta::InitMod( __FILE__, $hash ) if(!$modMetaAbsent);            # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;
}

################################################################
#                 Define
################################################################
sub Define {
  my ($hash, $def) = @_;

  my $name = $hash->{NAME};
  my $err;

  if ($modSizeAbsent) {
      $err = "Perl module '$modSizeAbsent' is missing. You need to install it first (Debian/Ubuntu: apt install libdevel-size-perl).";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  if ($storabs) {
      $err = "Perl module '$storabs' is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  my @a = split /\s+/x, $def;
  return "Usage: define &lt;name&gt; Analyze" if(@a != 2);

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                              # Modul Meta.pm nicht vorhanden
  $hash->{HELPER}{SNAP}          = {};
  $hash->{HELPER}{SNAPORD}       = [];
  $hash->{HELPER}{RSSLOG}        = [];
  $hash->{HELPER}{CRASH}         = {};
  $hash->{HELPER}{JOBID}         = 0;

  _loadCrash ($hash);

  CommandAttr (undef, "$name room SYSTEM") if($init_done);

  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useSMUtils  => 1
  };
  
  use version 0.77; our $VERSION = moduleVersion ($hash, \%vNotesIntern);       # Versionsinformationen setzen

  $hash->{PADWALKER} = $hasPadWalker ? 'available' : 'not installed (optional, needed for attribute deepScan file-scope variables)';

  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, "state", "Initialized");                                                 # Init state
  readingsBulkUpdate ($hash, "crashListCount", scalar keys %{$hash->{HELPER}{CRASH}});
  readingsEndUpdate  ($hash,1);

  InternalTimer (time + 2, 'FHEM::Analyze::startTimers', $hash);

return;
}

################################################################
#   Undef: Timer und laufenden Hintergrundjob entfernen
################################################################
sub Undef {
  my $hash = shift;
  my $arg  = shift;

  RemoveInternalTimer ($hash);
  BlockingKill ($hash->{HELPER}{RUNNING_PID}) if(defined $hash->{HELPER}{RUNNING_PID});

return;
}

################################################################
#   Shutdown: laufenden Hintergrundjob beenden
################################################################
sub Shutdown {
  my $hash = shift;

  RemoveInternalTimer ($hash);
  BlockingKill ($hash->{HELPER}{RUNNING_PID}) if(defined $hash->{HELPER}{RUNNING_PID});

return;
}

################################################################
sub Delete {
  my $hash  = shift;
  my $arg   = shift;

return;
}

################################################################
sub Attr {
    my $cmd   = shift;
    my $name  = shift;
    my $aName = shift;
    my $aVal  = shift;

    my $hash  = $defs{$name};

    if ($aName eq "disable") {
        my $do = 0;
        $do    = ($aVal ? 1 : 0) if($cmd eq "set");

        if ($do) {
            RemoveInternalTimer ($hash);
            BlockingKill ($hash->{HELPER}{RUNNING_PID}) if(defined $hash->{HELPER}{RUNNING_PID});
            delete $hash->{HELPER}{RUNNING_PID};
            delete $hash->{HELPER}{JOB};
            delete $hash->{JOB};
            unlink _traceFile ($name);
            _delReadings ($hash, qr/^(?!state$)/x);
        }

        readingsSingleUpdate ($hash, "state", ($do ? "disabled" : "initialized"), 1);
    }

    if ($cmd eq "set") {
        my %int = ( crashRetries => 0, largeObjectNum => 1, maxNodes => 1, maxSnapshots => 1, forkTimeout => 1,
                    leakMinBytes   => 0, sampleInterval => 0, topNum => 1, treeDepth => 1, trackMaxSamples => 2 );

        if (exists $int{$aName}) {
            return _t ('attr_int', $aName, $int{$aName}) if($aVal !~ /^[0-9]+$/x || $aVal < $int{$aName});
        }

        if ($aName eq 'autoSnapshot') {
            return _t ('attr_hours', $aName) if($aVal !~ /^[0-9]+(?:\.[0-9]+)?$/x);
        }

        if ($aName eq 'sampleInterval') {
            return _t ('attr_sample', $aName) if($aVal != 0 && $aVal < 60);
        }

        if ($aName eq 'trackObjects') {
            my (undef, $bad) = _trackParse ($aVal);
            return _t ('attr_track', $aName, join (', ', @$bad)) if(@$bad);
        }
    }

    if ($aName eq 'trackObjects') {                                                       # Verlauf und Readings nicht mehr getrackter Objekte entfernen
        my ($ok) = $cmd eq 'set' ? _trackParse ($aVal) : ([]);
        _trackCleanup ($hash, $ok);
    }

    if ($aName =~ /^(?:autoSnapshot|sampleInterval|disable)$/x) {                         # Timer neu aufsetzen (Attribut ist erst nach Rückkehr gesetzt)
        RemoveInternalTimer ($hash, 'FHEM::Analyze::startTimers');
        InternalTimer       (time + 1, 'FHEM::Analyze::startTimers', $hash);
    }

return;
}

################################################################
#                 Timer: Sampling und Auto-Snapshot
################################################################
sub startTimers {
  my $hash = shift;
  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash, 'FHEM::Analyze::sampleTimer');
  RemoveInternalTimer ($hash, 'FHEM::Analyze::autoTimer');

  if (!$hash->{HELPER}{INITREAD}) {                                                  # einmal pro Start: aus dem Statefile wiederhergestellte Readings sind veraltet
      $hash->{HELPER}{INITREAD} = 1;
      _initReadings ($hash);
  }

  _checkStaleTrace ($hash);                                                          # Absturz einer früheren Analyse erkennen

  return if(IsDisabled($name));

  InternalTimer (gettimeofday() + 5, 'FHEM::Analyze::sampleTimer', $hash) if(AttrVal ($name, 'sampleInterval', 600) > 0);

  my $ah = AttrVal ($name, 'autoSnapshot', 0);
  InternalTimer (gettimeofday() + $ah * 3600, 'FHEM::Analyze::autoTimer', $hash) if($ah > 0);

return;
}

################################################################
#   Readings nach dem Start zurücksetzen. Das Statefile wird erst nach Define eingelesen
#   und stellt Readings wieder her, deren Grundlage (Snapshots, Probenverlauf, Tracking)
#   nach einem Neustart nicht mehr existiert. Nur die Readings, die beim Start gültig
#   sind, werden neu gesetzt, alle anderen entstehen mit der nächsten Messung.
################################################################
sub _initReadings {
  my $hash = shift;
  my $name = $hash->{NAME};

  _delReadings ($hash, qr/^(?!state$)/x);

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'state',          IsDisabled ($name) ? 'disabled' : 'Initialized');
  readingsBulkUpdate  ($hash, 'crashListCount', scalar keys %{$hash->{HELPER}{CRASH} // {}});
  readingsBulkUpdate  ($hash, 'snapshots',      0);
  readingsBulkUpdate  ($hash, 'snapshot_last',  '-');
  readingsEndUpdate   ($hash, 1);

return;
}

################################################################
#   leichtgewichtige Probe: nur Prozessspeicher aus /proc,
#   Basis für den RSS-Trend (kein Fork, praktisch kostenlos)
################################################################
sub sampleTimer {
  my $hash = shift;
  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash, 'FHEM::Analyze::sampleTimer');
  return if(IsDisabled($name));

  my $iv = AttrVal ($name, 'sampleInterval', 600);
  return if(!$iv);

  my $p   = procInfo ();
  my $log = $hash->{HELPER}{RSSLOG} //= [];

  push @$log, [time, $p->{rss}];
  shift @$log while(@$log > 1000);

  my $slope = _rssSlope ($log, 24);

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'proc_rss_kB',            $p->{rss});
  readingsBulkUpdate  ($hash, 'proc_rssPeak_kB',        $p->{hwm});
  readingsBulkUpdate  ($hash, 'proc_rssTrend_kBperHour', sprintf ("%.1f", $slope)) if(defined $slope);
  readingsEndUpdate   ($hash, 1);

  InternalTimer (gettimeofday() + $iv, 'FHEM::Analyze::sampleTimer', $hash);

return;
}

################################################################
sub autoTimer {
  my $hash = shift;
  my $name = $hash->{NAME};

  RemoveInternalTimer ($hash, 'FHEM::Analyze::autoTimer');
  return if(IsDisabled($name));

  my $ah = AttrVal ($name, 'autoSnapshot', 0);
  return if(!$ah);

  InternalTimer (gettimeofday() + $ah * 3600, 'FHEM::Analyze::autoTimer', $hash);

  return if($hash->{HELPER}{RUNNING_PID});                                              # laufender Job -> diesmal auslassen

  my $ret = _startJob ($hash, { mode => 'snapshot', label => 'auto_'.strftime('%Y%m%d_%H%M%S', localtime), auto => 1 });
  Log3 ($name, 2, "$name - auto snapshot not started: $ret") if($ret);

return;
}

#############################################################################################
#                                      Setter
#############################################################################################
sub Set {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if (@a < 2);

  my $name = shift @a;
  my $opt  = shift @a;
  my $arg  = join " ", @a;
  my $prop = $a[0];

  my $mods    = join ",", sort keys (%modules);
  my $labels  = join ",", @{$hash->{HELPER}{SNAPORD}};
  my $mh      = join ",", map { '$'.$_ } _mainHashes ();

  my $setlist = "Unknown argument $opt, choose one of ".
                "snapshot ".
                "deleteSnapshot:".($labels ? "$labels," : "")."all ".
                "allDevices:noArg ".
                "deviceType:$mods ".
                "xHashDetail ".
                "mainHash:$mh ".
                "abortJob:noArg ".
                "clearCrashList "
                ;

  return "Device $name is disabled" if(IsDisabled($name));

  if ($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $params = {
          hash => $hash,
          name => $name,
          opt  => $opt,
          arg  => $arg,
          prop => $prop,
      };

      return &{$hset{$opt}{fn}} ($params);
  }

return $setlist;
}

#############################################################################################
#                                      Getter
#############################################################################################
sub Get {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if (@a < 2);

  my $name = shift @a;
  my $opt  = shift @a;
  my $labels = join ",", @{$hash->{HELPER}{SNAPORD}};

  my ($tlist) = _trackParse (AttrVal ($name, 'trackObjects', q{}));

  my $getlist = "Unknown argument $opt, choose one of ".
                "snapshots:noArg ".
                "report".($labels ? ":$labels" : "")." ".
                "diff ".
                "leakCandidates:noArg ".
                "timers:noArg ".
                "process:noArg ".
                "rssTrend:noArg ".
                "lastResult:noArg ".
                "crashList:noArg ".
                "track".(@$tlist ? ":widgetList,".(scalar @$tlist + 2).",select,all,".join (',', map { _trackKey ($_->{spec}) } @$tlist).
                                    ",2,textField,rows&nbsp;e.g.&nbsp;100" : ":noArg")." "
                ;

  if ($hget{$opt} && defined &{$hget{$opt}{fn}}) {
      my $params = {
          hash => $hash,
          name => $name,
          opt  => $opt,
          args => \@a,
      };

      return &{$hget{$opt}{fn}} ($params);
  }

return $getlist;
}

######################################################################################
#                                   Setter snapshot
######################################################################################
sub _setSnapshot {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $prop  = $paref->{prop} // 'snap_'.strftime('%Y%m%d_%H%M%S', localtime);

  return _t ('label_invalid', $prop) if($prop !~ /^[\w.\-]+$/x);

return _startJob ($hash, { mode => 'snapshot', label => $prop });
}

######################################################################################
#                                   Setter deleteSnapshot
######################################################################################
sub _setDeleteSnapshot {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $prop  = $paref->{prop} // return _t ('del_needs');

  if ($prop eq 'all') {
      $hash->{HELPER}{SNAP}    = {};
      $hash->{HELPER}{SNAPORD} = [];
      _updateSnapReadings ($hash);
      return _t ('del_all');
  }

  return _t ('snap_missing', $prop) if(!$hash->{HELPER}{SNAP}{$prop});

  delete $hash->{HELPER}{SNAP}{$prop};
  @{$hash->{HELPER}{SNAPORD}} = grep { $_ ne $prop } @{$hash->{HELPER}{SNAPORD}};

  _updateSnapReadings ($hash);

return _t ('snap_deleted', $prop);
}

######################################################################################
#   Readings snapshots / snapshot_last mit dem aktuellen Bestand abgleichen
######################################################################################
sub _updateSnapReadings {
  my $hash = shift;

  my $ord = $hash->{HELPER}{SNAPORD};

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'snapshot_last', $ord->[-1] // '-');
  readingsBulkUpdate  ($hash, 'snapshots',     scalar @$ord);
  readingsEndUpdate   ($hash, 1);

return;
}

######################################################################################
#                                   Setter deviceType / allDevices
######################################################################################
sub _setDeviceType {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};

  my $allt  = ($opt eq 'allDevices' || !$prop) ? '.*' : $prop;
  my @devs  = devspec2array ("TYPE=$allt");

  return _t ('no_dev_type', $allt) if(!@devs);

return _startJob ($hash, { mode => 'devices', devs => \@devs, label => $allt });
}

######################################################################################
#                                   Setter xHashDetail / mainHash
######################################################################################
sub _setTree {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};

  my $arg   = $paref->{arg} || AttrVal ($name, 'analyzeObject', q{});

  return _t ('tree_needs', $opt) if(!$arg);

  my ($ref, $path, $err) = _resolvePath ($arg);
  return $err if($err);

  if (!ref $ref) {                                                                    # Wert ist keine Referenz
      local $Data::Dumper::Terse = 1;
      return _t ('not_ref', $path, Devel::Size::size($ref))."\n\n".Dumper ($ref);
  }

return _startJob ($hash, { mode => 'tree', spec => $arg, label => $path });
}

######################################################################################
#                                   Setter abortJob
######################################################################################
sub _setAbortJob {
  my $paref = shift;
  my $hash  = $paref->{hash};

  return _t ('no_job') if(!$hash->{HELPER}{RUNNING_PID});

  BlockingKill ($hash->{HELPER}{RUNNING_PID});
  RemoveInternalTimer ($hash, 'FHEM::Analyze::watchJob');
  delete $hash->{HELPER}{RUNNING_PID};
  delete $hash->{HELPER}{JOB};
  delete $hash->{JOB};
  unlink _traceFile ($paref->{name});

  readingsSingleUpdate ($hash, 'state', 'aborted', 1);

return _t ('job_aborted');
}

######################################################################################
#                                   Getter snapshots
######################################################################################
sub _getSnapshots {
  my $paref = shift;
  my $hash  = $paref->{hash};

  my @s = _orderedSnaps ($hash);
  return _t ('no_snaps', $paref->{name}) if(!@s);

  my @o = ('label                          taken                 rss        attributed  devices  timers  fds  kids');

  for my $s (@s) {
      my $f = $s->{flat};
      push @o, sprintf ("%-30s %s  %7d kB  %9s  %7d  %6d  %3d  %4d",
                        $s->{label}, strftime('%Y-%m-%d %H:%M:%S', localtime $s->{time}), $f->{'proc:rss'} // 0,
                        defined $f->{'proc:attributed'} ? sprintf('%d kB', $f->{'proc:attributed'}) : '-',
                        $f->{'cnt:defs'} // 0, $f->{'cnt:timers'} // 0, $f->{'cnt:fds'} // 0, $f->{'cnt:kids'} // 0);
  }

return join ("\n", @o);
}

######################################################################################
#                                   Getter report
######################################################################################
sub _getReport {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $label = $paref->{args}[0];

  my @s = _orderedSnaps ($hash);
  return _t ('no_snaps', $name) if(!@s);

  my $snap = $label ? $hash->{HELPER}{SNAP}{$label} : $s[-1];
  return _t ('snap_notexist_av', $label, join (', ', map { $_->{label} } @s)) if(!$snap);

return _reportSnap ($snap, AttrVal ($name, 'topNum', 15));
}

######################################################################################
#                                   Getter diff
######################################################################################
sub _getDiff {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my ($l0, $l1) = @{$paref->{args}};

  my @s = _orderedSnaps ($hash);
  return _t ('need_two', $name) if(@s < 2);

  my ($s0, $s1);
  if (!$l0)    { ($s0, $s1) = @s[-2, -1]; }                                          # ohne Angabe: die letzten beiden
  elsif (!$l1) { ($s0, $s1) = ($hash->{HELPER}{SNAP}{$l0}, $s[-1]); }                # nur A: A gegen den neuesten
  else         { ($s0, $s1) = @{$hash->{HELPER}{SNAP}}{($l0, $l1)}; }

  return _t ('snap_missing_av', join (', ', map { $_->{label} } @s)) if(!$s0 || !$s1);

return _reportDiff ($s0, $s1, AttrVal ($name, 'topNum', 15));
}

######################################################################################
#                                   Getter leakCandidates
######################################################################################
sub _getLeakCandidates {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my @s = _orderedSnaps ($hash);
  return _t ('need_three', scalar (@s), $name) if(@s < 3);

return _reportLeaks (\@s, AttrVal ($name, 'topNum', 15), AttrVal ($name, 'leakMinBytes', 2048));
}

######################################################################################
#                                   Getter timers
######################################################################################
sub _getTimers {
  my $paref = shift;

  my ($tf, $td) = timersByFn ();
  my @o = ('Timers by function:');

  for my $k (sort { $tf->{$b} <=> $tf->{$a} || $a cmp $b } keys %$tf) {
      push @o, sprintf ("  %5d  %s", $tf->{$k}, $k);
  }

  push @o, '', 'Devices with most timers:';
  my @d = sort { $td->{$b} <=> $td->{$a} || $a cmp $b } keys %$td;
  push @o, map { sprintf ("  %5d  %s", $td->{$_}, $_) } @d[0 .. ($#d < 14 ? $#d : 14)];

return join ("\n", @o);
}

######################################################################################
#                                   Getter process
######################################################################################
sub _getProcess {
  my $p = procInfo ();
  my $c = counters ();

return sprintf ("rss %d kB (peak %d kB, anonymous %d kB)\npss %d kB  private %d kB  shared %d kB  swap %d kB\n".
                "devices %d  timers %d  fds %d  child processes %d  selectlist %d  readyfnlist %d\n\n",
                @{$p}{qw(rss hwm anon pss priv shared swap)}, @{$c}{qw(defs timers fds kids select ready)}).
                _t ('proc_hint');
}

######################################################################################
#                                   Getter rssTrend
######################################################################################
sub _getRssTrend {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $log   = $hash->{HELPER}{RSSLOG} // [];

  return _t ('rss_notenough') if(@$log < 6);

  my @o = (sprintf ("%d samples from %s to %s", scalar @$log, strftime ('%Y-%m-%d %H:%M', localtime $log->[0][0]),
                                                           strftime ('%Y-%m-%d %H:%M', localtime $log->[-1][0])));

  for my $h (1, 6, 24, 72) {
      my $s = _rssSlope ($log, $h);
      push @o, sprintf ("  last %2d h: %s", $h, defined $s ? sprintf ("%+.1f kB/h", $s) : _t ('rss_ns'));
  }

  push @o, '', _t ('rss_hint');

return join ("\n", @o);
}

######################################################################################
#                                   Getter track
#   get <name> track [all|<Objekt>] [<Zeilen>]
######################################################################################
sub _getTrack {
  my $paref        = shift;
  my $hash         = $paref->{hash};
  my $name         = $paref->{name};
  my ($sel, $rows) = @{$paref->{args}};

  if (defined $sel && $sel =~ /^(.*),([^,]*)$/xs) {                               # widgetList liefert 'Auswahl,Textfeld' als ein Argument (Komma auch bei leerem Textfeld)
      $sel  = $1;
      $rows = $2 if(!defined $rows || $rows eq q{});
  }

  my ($list) = _trackParse (AttrVal ($name, 'trackObjects', q{}));
  return _t ('track_none') if(!@$list);

  my $tr = $hash->{HELPER}{TRACK} // {};
  return _t ('track_nosamples', $name) if(!grep { $tr->{$_->{spec}} && @{$tr->{$_->{spec}}} } @$list);

  if (!defined $sel || $sel eq q{} || lc ($sel) eq 'all') {
      return _trackOverview ($name, $list, $tr);
  }

  my $t     = _trackSpec ($sel);                                                  # Schreibweise des Attributs (auch ohne führendes $)
  my $key   = _trackKey  ($sel);                                                  # Schreibweise der Auswahlliste
  my ($one) = grep { ($t && $_->{spec} eq $t->{spec}) || _trackKey ($_->{spec}) eq $key } @$list;

  return _t ('track_unknown', $sel) if(!$one);

return _trackSeries ($one, $tr->{$one->{spec}} // [], $rows);
}

######################################################################################
#   Schreibweise eines Objekts in der Auswahlliste: der Doppelpunkt ist im Widget-Syntax von
#   FHEMWEB ein Trenner und wird daher durch '/' ersetzt (%FHEM::Modul::x -> %FHEM/Modul/x,
#   datei.pm:%x -> datei.pm/%x)
######################################################################################
sub _trackKey {
  my $spec = shift // q{};

  $spec =~ s/:+/\//xg;

return $spec;
}

######################################################################################
sub _trackOverview {
  my ($name, $list, $tr) = @_;

  my $fmt = "%12s  %9s  %12s  %10s  %7s  %s";
  my @o   = (sprintf ($fmt, 'size', 'entries', 'change', 'per hour', 'samples', 'object'));

  for my $t (@$list) {
      my $s = $tr->{$t->{spec}} // [];
      my @v = grep { defined $_->[1] } @$s;

      if (!@v) {
          push @o, sprintf ($fmt, '-', '-', '-', '-', scalar @$s, $t->{spec});
          next;
      }

      my ($f, $l) = @v[0, -1];
      my $h       = ($l->[0] - $f->[0]) / 3600;
      my $db      = $l->[1] - $f->[1];

      push @o, sprintf ($fmt, _hs ($l->[1]), defined $l->[2] ? $l->[2] : '-', _fmtDelta ('track', $db),
                        @v > 1 && $h ? _fmtDelta ('track', $db / $h).'/h' : '-', scalar @$s, $t->{spec});
  }

  push @o, '', _t ('track_hint', $name);

return join ("\n", @o);
}

######################################################################################
sub _trackSeries {
  my ($t, $s, $rows) = @_;

  $rows = 40 if(!defined $rows || $rows !~ /^[0-9]+$/x || !$rows);

  my @o = (sprintf ("Tracked object %s", $t->{spec}));
  my (@l, $pv, $first, $last);

  for my $x (@$s) {
      my ($tm, $b, $n) = @$x;
      my ($ds, $rate)  = ('-', '-');

      if (defined $b) {
          if ($pv) {
              my $d  = $b - $pv->[1];
              my $hh = ($tm - $pv->[0]) / 3600;
              $ds    = _fmtDelta ('track', $d);
              $rate  = _fmtDelta ('track', $d / $hh).'/h' if($hh);
          }

          $pv    = $x;
          $first = $x if(!$first);
          $last  = $x;
      }

      push @l, sprintf ("%-19s  %12s  %9s  %12s  %10s", strftime ('%Y-%m-%d %H:%M:%S', localtime $tm),
                        defined $b ? _hs ($b) : 'n/a', defined $n ? $n : '-', $ds, $rate);
  }

  push @o, sprintf ("%-19s  %12s  %9s  %12s  %10s", 'time', 'size', 'entries', 'delta size', 'per hour');

  if (@l > $rows) {
      @l = @l[-$rows .. -1];
      push @o, _t ('track_shown', $rows, scalar @$s);
  }

  push @o, @l;

  if ($first && $last && $last != $first) {
      my $h  = ($last->[0] - $first->[0]) / 3600;
      my $db = $last->[1] - $first->[1];
      my $dn = defined $last->[2] && defined $first->[2] ? $last->[2] - $first->[2] : undef;

      push @o, '', _t ('track_net', $h, _fmtDelta ('track', $db), $h ? _fmtDelta ('track', $db / $h) : '-',
                       defined $dn ? sprintf ('%+d', $dn) : '-', defined $dn && $h ? sprintf ('%+.1f', $dn / $h) : '-');
  }

return join ("\n", @o);
}

######################################################################################
#                                   Getter lastResult
######################################################################################
sub _getLastResult {
  my $paref = shift;

return $paref->{hash}{HELPER}{LASTTEXT} // _t ('no_result');
}

#############################################################################################
#                                   Job-Steuerung
#############################################################################################

######################################################################################
#   Job starten (im Fork via BlockingCall, optional inline)
#   $job: mode (snapshot|devices|tree), label, devs, spec, auto
######################################################################################
sub _startJob {
  my $hash = shift;
  my $job  = shift;

  my $name = $hash->{NAME};

  if ($hash->{HELPER}{RUNNING_PID}) {
      return _t ('job_running', ($hash->{HELPER}{JOB}{mode} // '?'), $name);
  }

  $job->{time}  = time;
  $job->{cl}  //= $hash->{CL} if(!$job->{auto});                                    # Client für asyncOutput
  $job->{fork}  = AttrVal ($name, 'useFork', 1);
  $job->{async} = $job->{fork} ? 1 : 0;
  $job->{id}    = ++$hash->{HELPER}{JOBID};

  if ($job->{mode} eq 'snapshot') {                                                 # Messwerte des Hauptprozesses VOR dem Fork erfassen
      my $pf = {};
      my $p  = procInfo ();
      my $c  = counters ();
      my ($tf, $td) = timersByFn ();

      $pf->{"proc:$_"}  = $p->{$_} for keys %$p;
      $pf->{"cnt:$_"}   = $c->{$_} for keys %$c;
      $pf->{"timer:$_"} = $tf->{$_} for keys %$tf;
      $pf->{"timerdev:$_"} = $td->{$_} for keys %$td;

      $job->{pre} = $pf;
  }

  my %excl = %hexcl;
  $excl{$_} = 1 for grep { $_ } split /[\s,]+/x, AttrVal ($name, 'excludeTypes', '');

  my ($tl) = $job->{mode} eq 'snapshot' ? _trackParse (AttrVal ($name, 'trackObjects', q{})) : ([]);
  $job->{track} = $tl;                                                                # Liste der getrackten Objekte dieses Jobs

  my $pars = {
      name      => $name,
      id        => $job->{id},
      mode      => $job->{mode},
      devs      => $job->{devs},
      spec      => $job->{spec},
      full      => ($job->{mode} eq 'snapshot' ? 1 : 0),
      deep      => AttrVal ($name, 'deepScan', 0),
      maxNodes  => AttrVal ($name, 'maxNodes', 3_000_000),
      treeDepth => AttrVal ($name, 'treeDepth', 3),
      treeTop   => AttrVal ($name, 'topNum', 15),
      excl      => \%excl,
      track     => $tl,
      skip      => { map { $_ => 1 } keys %{$hash->{HELPER}{CRASH} // {}} },       # Objekte aus der Crash-Liste werden übersprungen
      trace     => _traceFile ($name),                                             # Breadcrumb-Datei
  };

  $hash->{HELPER}{JOB} = $job;
  $hash->{JOB}         = $job->{mode}.' '.($job->{label} // '');

  if ($job->{fork}) {
      my $bc = BlockingCall ('FHEM::Analyze::blockMeasure', $pars,
                             'FHEM::Analyze::blockDone', AttrVal ($name, 'forkTimeout', 1800),
                             'FHEM::Analyze::blockAbort', { hash => $hash, id => $job->{id} });

      if (!$bc) {
          delete $hash->{HELPER}{JOB};
          delete $hash->{JOB};
          return _t ('fork_failed');
      }

      $hash->{HELPER}{RUNNING_PID} = $bc;
      $hash->{HELPER}{WATCHGONE}   = 0;
      readingsSingleUpdate ($hash, 'state', "running: $job->{mode}", 1);

      RemoveInternalTimer ($hash, 'FHEM::Analyze::watchJob');
      InternalTimer       (gettimeofday() + 10, 'FHEM::Analyze::watchJob', $hash);   # Wächter: erkennt einen abgestürzten Hintergrundprozess

      return;                                                                      # Ergebnis kommt per asyncOutput bzw. 'get lastResult'
  }

  readingsSingleUpdate ($hash, 'state', "running: $job->{mode}", 1);

  my $res = eval { _measure ($pars) };
  $res    = { error => "$@" } if(!$res);

return _finishJob ($hash, $res);
}

######################################################################################
#   Child-Funktion von BlockingCall: misst und liefert serialisiertes Ergebnis
######################################################################################
sub blockMeasure {
  my $pars = shift;
  my $name = $pars->{name};

  my $res = eval { _measure ($pars) };
  $res    = { error => "$@" } if(!$res);

  my $ser = eval { freeze ($res) };

  if (!$ser) {
      $ser = freeze ({ error => "serialization failed: ".($@ // 'unknown') });
  }

return $name.'|'.($pars->{id} // 0).'|'.encode_base64 ($ser, '');
}

######################################################################################
#   Finish-Funktion von BlockingCall (Parent)
######################################################################################
sub blockDone {
  my $string = shift // '';

  my ($name, $id, $b64) = split /\|/x, $string, 3;
  my $hash = defined $name && $defs{$name} ? $defs{$name} : _findRunning ();

  return if(!$hash);                                                                # Gerät inzwischen gelöscht

  my $cur = $hash->{HELPER}{JOB};
  return if(!$cur);                                                                 # Job wurde bereits abgeschlossen (z.B. durch den Wächter)
  return if(defined $id && $id =~ /^\d+$/x && ($cur->{id} // 0) != $id);            # Ergebnis eines alten Jobs

  my $res;
  $res = eval { thaw (decode_base64 ($b64)) } if($b64);

  if (!$res || ref $res ne 'HASH') {
      _handleCrash ($hash, 'no result received from the background process');
      return;
  }

  _finishJob ($hash, $res);

return;
}

######################################################################################
sub blockAbort {
  my $arg   = shift;
  my $cause = shift // 'unknown';

  return if(ref $arg ne 'HASH' || !$arg->{hash});

  my $hash = $arg->{hash};
  return if(!$defs{$hash->{NAME}});

  my $cur = $hash->{HELPER}{JOB};
  return if(!$cur || ($cur->{id} // 0) != ($arg->{id} // 0));                      # Job bereits abgeschlossen oder ersetzt

  _handleCrash ($hash, $cause);

return;
}

######################################################################################
#   Wächter: erkennt einen abgestürzten Hintergrundprozess, auch wenn Blocking weder
#   finishFn noch abortFn aufruft (Prozess ist weg, kein Ergebnis angekommen)
######################################################################################
sub watchJob {
  my $hash = shift;

  RemoveInternalTimer ($hash, 'FHEM::Analyze::watchJob');

  my $bc = $hash->{HELPER}{RUNNING_PID} or return;

  if (ref $bc eq 'HASH' && $bc->{pid} && !_pidAlive ($bc->{pid})) {
      if (++$hash->{HELPER}{WATCHGONE} >= 2) {                                     # zweimal in Folge: ein evtl. noch ungelesenes Ergebnis wäre längst verarbeitet
          $hash->{HELPER}{WATCHGONE} = 0;
          _handleCrash ($hash, 'background process terminated unexpectedly');
          return;
      }
  }
  else {
      $hash->{HELPER}{WATCHGONE} = 0;
  }

  InternalTimer (gettimeofday() + 10, 'FHEM::Analyze::watchJob', $hash);

return;
}

######################################################################################
sub _pidAlive {
  my $pid = shift;

  return 1 if(!-d '/proc/self');                                                   # kein /proc: keine Aussage möglich
  return 0 if(!$pid);

  open my $fh, '<', "/proc/$pid/stat" or return 0;
  my $l = <$fh> // q{};
  close $fh;

return ($l =~ /^\d+\s+\(.*\)\s+(\S)/x && $1 ne 'Z') ? 1 : 0;                      # Zombie gilt als beendet
}

######################################################################################
#   Absturz eines Jobs: letzte Fundstelle aus der Breadcrumb-Datei lesen, Objekt in die
#   Crash-Liste aufnehmen und den Job (bis crashRetries mal) ohne dieses Objekt wiederholen
######################################################################################
sub _handleCrash {
  my $hash  = shift;
  my $cause = shift // 'unknown';

  my $name = $hash->{NAME};
  my $job  = delete $hash->{HELPER}{JOB} // {};
  my $bc   = delete $hash->{HELPER}{RUNNING_PID};

  delete $hash->{JOB};
  RemoveInternalTimer ($hash, 'FHEM::Analyze::watchJob');
  eval { BlockingKill ($bc) } if($bc);

  my $file = _traceFile ($name);
  my $t    = _readTrace ($file);
  unlink $file;

  my $path = $t && $t->{path} ne 'start' ? $t->{path} : undef;
  my $msg  = _t ('crash_msg', ($job->{mode} // '?'), $cause);
  my @adv;

  my $retry = $job->{retry} // 0;
  my $max   = AttrVal ($name, 'crashRetries', 3);

  if ($path) {
      $msg .= ' '._t ('crash_last', $path);

      _addCrash ($hash, $path, $cause);
      Log3 ($name, 1, "$name - $msg - added to the crash list, it is skipped from now on");

      if ($job->{fork} && $retry < $max) {
          my %nj = map { $_ => $job->{$_} } grep { exists $job->{$_} } qw(mode label devs spec auto cl);

          $nj{retry} = $retry + 1;
          $nj{notes} = [ @{$job->{notes} // []},
                         _t ('crash_retry', $path, $cause, $retry + 1, $max) ];

          my $r = _startJob ($hash, \%nj);
          return if(!$r);                                                          # läuft erneut im Hintergrund

          $msg .= ' '._t ('crash_restartfail', $r);
      }
      elsif ($job->{fork}) {
          push @adv, _t ('crash_maxretry', $max);
      }

      push @adv, _t ('crash_onlist', $name, $name),
                 _t ('crash_inside');
  }
  else {
      $msg .= ' '._t ('crash_unknown');
      Log3 ($name, 1, "$name - $msg");
      push @adv, _t ('crash_exclude');
  }

  readingsSingleUpdate ($hash, 'state', 'error: crashed'.($path ? " at $path" : ''), 1);

  my $text = join ("\n", @{$job->{notes} // []}, $msg, '', @adv);
  $hash->{HELPER}{LASTTEXT} = $text;

  if ($job->{async} && $job->{cl} && ref $job->{cl} eq 'HASH' && !AttrVal ($name, 'noOutput', 0)) {
      asyncOutput ($job->{cl}, $text);
  }

return;
}

######################################################################################
#   Breadcrumb-Datei: der Messprozess schreibt vor jedem Objekt dessen Pfad hinein
######################################################################################
sub _traceFile {
  my $name = shift;

return File::Spec->catfile (File::Spec->tmpdir (), "fhem_analyze_${name}.trace");
}

sub _crumbOpen {
  my ($ctx, $file, $mode) = @_;

  $ctx->{mode} = $mode // q{};
  return if(!$file);

  open (my $fh, '>', $file) or return;
  $ctx->{trace} = $fh;

  _crumb ($ctx, 'start');

return;
}

sub _crumb {
  my ($ctx, $path) = @_;

  my $fh = $ctx->{trace} or return;
  my $l  = ($ctx->{mode} // q{})."\t$path\n";

  utf8::encode ($l);
  sysseek  ($fh, 0, 0);
  syswrite ($fh, $l);
  truncate ($fh, length $l);

return;
}

sub _readTrace {
  my $file = shift;

  return if(!-e $file);
  open my $fh, '<', $file or return;
  local $/ = "\n";                                                                # unabhängig von einem geänderten Zeilentrenner
  my $l = <$fh>;
  close $fh;

  return if(!defined $l);
  $l =~ s/[\r\n]+$//x;
  utf8::decode ($l);

  my ($mode, $path) = split /\t/x, $l, 2;
  return if(!defined $path);

return { mode => $mode, path => $path };
}

######################################################################################
#   Spur einer früheren Analyse gefunden, die nicht beendet wurde (FHEM selbst abgestürzt,
#   z.B. bei useFork=0): letztes Objekt in die Crash-Liste aufnehmen
######################################################################################
sub _checkStaleTrace {
  my $hash = shift;
  my $name = $hash->{NAME};

  return if($hash->{HELPER}{RUNNING_PID});

  my $file = _traceFile ($name);
  my $t    = _readTrace ($file) or return;

  unlink $file;
  return if($t->{path} eq 'start');

  _addCrash ($hash, $t->{path}, 'FHEM or the analysis terminated unexpectedly');
  Log3 ($name, 1, "$name - a previous analysis ($t->{mode}) did not finish, last object being measured: $t->{path} - added to the crash list");

return;
}

######################################################################################
#   Crash-Liste (bleibt über Neustarts erhalten, via setKeyValue)
######################################################################################
sub _addCrash {
  my ($hash, $path, $cause) = @_;

  $cause =~ s/[\t\n]/ /xg;
  $hash->{HELPER}{CRASH}{$path} = { time => time, cause => $cause };

  _saveCrash ($hash);

return;
}

sub _saveCrash {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $c    = $hash->{HELPER}{CRASH} // {};
  my $key  = "Analyze_${name}_crashList";

  if (%$c) {
      my $s = join ("\n", map { "$_\t$c->{$_}{time}\t$c->{$_}{cause}" } sort keys %$c);
      utf8::encode ($s);
      setKeyValue ($key, unpack ('H*', $s));
  }
  else {
      setKeyValue ($key, undef);
  }

  readingsSingleUpdate ($hash, 'crashListCount', scalar keys %$c, 1);

return;
}

sub _loadCrash {
  my $hash = shift;
  my $name = $hash->{NAME};

  my ($err, $v) = getKeyValue ("Analyze_${name}_crashList");
  return if($err || !$v);

  my $s = eval { pack ('H*', $v) } // return;
  utf8::decode ($s);

  for my $l (split /\n/x, $s) {
      my ($p, $t, $c) = split /\t/x, $l, 3;
      next if(!$p);
      $hash->{HELPER}{CRASH}{$p} = { time => $t // 0, cause => $c // q{} };
  }

return;
}

######################################################################################
sub _getCrashList {
  my $paref = shift;
  my $c     = $paref->{hash}{HELPER}{CRASH} // {};

  return _t ('crash_empty') if(!%$c);

  my @o = (_t ('crash_head', $paref->{name}), '');

  for my $p (sort keys %$c) {
      push @o, sprintf ("  %s  (%s, %s)", $p, strftime ('%Y-%m-%d %H:%M:%S', localtime $c->{$p}{time}), $c->{$p}{cause});
  }

return join ("\n", @o);
}

######################################################################################
sub _setClearCrashList {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg} // q{};

  $arg =~ s/\s+//xg;

  return _t ('clear_needs') if(!$arg);

  if ($arg eq 'all') {
      $hash->{HELPER}{CRASH} = {};
  }
  else {
      return _t ('clear_notlisted', $arg) if(!$hash->{HELPER}{CRASH}{$arg});
      delete $hash->{HELPER}{CRASH}{$arg};
  }

  _saveCrash ($hash);

return $arg eq 'all' ? _t ('clear_all') : _t ('clear_one', $arg);
}

######################################################################################
sub _findRunning {
  for my $d (keys %defs) {
      next if(ref $defs{$d} ne 'HASH' || ($defs{$d}{TYPE} // '') ne 'Analyze');
      return $defs{$d} if($defs{$d}{HELPER}{RUNNING_PID});
  }

return;
}

######################################################################################
#   Ergebnis verarbeiten: Snapshot ablegen, Readings, Text erzeugen
######################################################################################
sub _finishJob {
  my $hash = shift;
  my $res  = shift;

  my $name = $hash->{NAME};
  my $job  = delete $hash->{HELPER}{JOB} // {};

  delete $hash->{HELPER}{RUNNING_PID};
  delete $hash->{JOB};

  RemoveInternalTimer ($hash, 'FHEM::Analyze::watchJob');
  unlink _traceFile ($name);                                                         # Job regulär beendet: Breadcrumb-Datei nicht mehr nötig

  if (!$res || $res->{error}) {
      my $e = $res->{error} // 'unknown error';
      Log3 ($name, 2, "$name - analysis failed: $e");
      readingsSingleUpdate ($hash, 'state', 'error', 1);
      return $hash->{HELPER}{LASTTEXT} = _t ('analysis_failed', $e);
  }

  my $top  = AttrVal ($name, 'topNum', 15);
  my $text = q{};

  if ($job->{mode} eq 'snapshot') {
      my %flat = (%{$job->{pre} // {}}, %{$res->{flat}});
      my $att  = $res->{attributed} // 0;

      $flat{'proc:attributed'}   = sprintf ("%d", $att / 1024);
      $flat{'proc:unattributed'} = ($flat{'proc:rss'} // 0) - $flat{'proc:attributed'};

      my $snap = {
          label   => $job->{label},
          time    => $job->{time},
          flat    => \%flat,
          nodes   => $res->{nodes},
          trunc   => $res->{trunc},
          secs    => $res->{secs},
          skipped => $res->{skipped},
          skippedPaths => $res->{skippedPaths},
          skipc   => $res->{skipc},
          deep    => $res->{deep},
          trackErr => $res->{trackErr},
      };

      _storeSnapshot ($hash, $snap);
      _setReadings   ($hash, \%flat, 1);
      _storeTrack    ($hash, $job, \%flat);

      $hash->{HELPER}{SNAP_LAST} = $job->{label};
      $text = _reportSnap ($snap, $top);
  }
  elsif ($job->{mode} eq 'devices') {
      my $snap = { label => "devices TYPE=$job->{label}", time => time, flat => $res->{flat}, nodes => $res->{nodes},
                   trunc => $res->{trunc}, secs => $res->{secs}, skipped => $res->{skipped}, partial => 1,
                   skippedPaths => $res->{skippedPaths}, skipc => $res->{skipc} };

      _setReadings ($hash, $res->{flat}, 0);
      $text = _reportSnap ($snap, $top);
  }
  else {
      my %flat = ();
      _setReadings ($hash, { map { ("obj:".$_->[0] => $_->[1]) } @{$res->{top} // []} }, 0) if($res->{top});
      $text = $res->{text};
  }

  $text = join ("\n", @{$job->{notes}}, '', $text) if($job->{notes} && @{$job->{notes}});   # Hinweise zu Abstürzen/Wiederholungen

  readingsSingleUpdate ($hash, 'state', 'done', 1);

  $hash->{HELPER}{LASTTEXT} = $text;

  if ($job->{async} && $job->{cl} && ref $job->{cl} eq 'HASH' && !AttrVal ($name, 'noOutput', 0)) {
      asyncOutput ($job->{cl}, $text);
  }

return AttrVal ($name, 'noOutput', 0) ? undef : $text;
}

######################################################################################
sub _storeSnapshot {
  my $hash = shift;
  my $snap = shift;

  my $name = $hash->{NAME};
  my $max  = AttrVal ($name, 'maxSnapshots', 10);
  my $ord  = $hash->{HELPER}{SNAPORD};

  @$ord = grep { $_ ne $snap->{label} } @$ord;                                        # gleiches Label ersetzen
  push @$ord, $snap->{label};
  $hash->{HELPER}{SNAP}{$snap->{label}} = $snap;

  while (@$ord > $max) {
      my $old = shift @$ord;
      delete $hash->{HELPER}{SNAP}{$old};
  }

return;
}

######################################################################################
sub _orderedSnaps {
  my $hash = shift;

return map { $hash->{HELPER}{SNAP}{$_} } grep { $hash->{HELPER}{SNAP}{$_} } @{$hash->{HELPER}{SNAPORD}};
}

######################################################################################
#   Readings aus Messwerten setzen
######################################################################################
sub _setReadings {
  my ($hash, $flat, $full) = @_;
  my $name = $hash->{NAME};

  my $ml = AttrVal ($name, 'largeObjectNum', 5);
  my $l  = length $ml;

  _delReadings ($hash, qr/^\d+_largest(?:Object|Device|Type)$/x);

  my (%obj, %dev, %typ);

  for my $k (keys %$flat) {
      if    ($k =~ /^part:(.+?)\{(.*)\}$/x) { $obj{'$defs{'.$1.'}{'.$2.'}'} = $flat->{$k}; }
      elsif ($k =~ /^main:(.+)$/x)          { $obj{'$'.$1}                  = $flat->{$k}; }
      elsif ($k =~ /^obj:(.+)$/x)           { $obj{$1}                      = $flat->{$k}; }       # xHashDetail/mainHash: Objektpfad unverändert
      elsif ($k =~ /^dev:(.+)$/x)           { $dev{$1}                      = $flat->{$k}; }
      elsif ($k =~ /^type:(.+)$/x)          { $typ{$1}                      = $flat->{$k}; }
  }

  readingsBeginUpdate ($hash);

  for my $set (['largestObject', \%obj], ['largestDevice', \%dev], ['largestType', \%typ]) {
      my ($rn, $h) = @$set;
      my $n = 0;

      for my $o (sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h) {
          last if(++$n > $ml);
          readingsBulkUpdate ($hash, sprintf ("%0${l}d_%s", $n, $rn), "$h->{$o}, $o");
      }
  }

  if ($full) {
      readingsBulkUpdate ($hash, 'proc_rss_kB',          $flat->{'proc:rss'}          // 0);
      readingsBulkUpdate ($hash, 'proc_pss_kB',          $flat->{'proc:pss'}          // 0);
      readingsBulkUpdate ($hash, 'proc_private_kB',      $flat->{'proc:priv'}         // 0);
      readingsBulkUpdate ($hash, 'proc_swap_kB',         $flat->{'proc:swap'}         // 0);
      readingsBulkUpdate ($hash, 'attributed_kB',        $flat->{'proc:attributed'}   // 0);
      readingsBulkUpdate ($hash, 'unattributed_kB',      $flat->{'proc:unattributed'} // 0);

      for my $c (qw(defs timers fds kids)) {
          readingsBulkUpdate ($hash, "count_$c", $flat->{"cnt:$c"} // 0);
      }

      readingsBulkUpdate ($hash, 'snapshot_last', $hash->{HELPER}{SNAPORD}[-1] // '-');
      readingsBulkUpdate ($hash, 'snapshots',     scalar @{$hash->{HELPER}{SNAPORD}});
  }

  readingsEndUpdate ($hash, 1);

return;
}

######################################################################################
#      Löschen von Readings per Regex
######################################################################################
sub _delReadings {
  my ($hash, $re) = @_;

  for my $r (keys %{$hash->{READINGS} // {}}) {
      readingsDelete ($hash, $r) if($r =~ $re);
  }

return;
}

#############################################################################################
#                                   Messung (läuft normalerweise im Fork)
#############################################################################################

######################################################################################
#   Kontext für den Walker
#   foreign: Wurzeln anderer Devices und der FHEM-Kernhashes. Referenzen dorthin werden nicht
#   verfolgt, sonst würde z.B. ein Device mit IODev den gesamten IO-Device-Hash mitzählen
#   (Devel::Size::total_size zählt so doppelt).
######################################################################################
sub _newCtx {
  my $p = shift;

  my %foreign;

  for my $d (keys %defs) {
      $foreign{refaddr ($defs{$d})} = $d if(ref $defs{$d});
  }

  for my $n (_mainHashes ()) {
      my $r = _mainRef ($n);
      $foreign{refaddr ($r)} = '$'.$n if($r);
  }

return { seen => {}, foreign => \%foreign, nodes => 0, max => $p->{maxNodes} // 3_000_000, trunc => 0,
         skip => $p->{skip} // {}, skippedPaths => [], skipc => {} };
}

######################################################################################
sub _mainHashes {
  my @m;

  no strict 'refs';                                                               ## no critic 'NoStrict'
  for my $n (@MAINHASHES) {
      push @m, $n if(*{"main::$n"}{HASH});
  }

return @m;
}

######################################################################################
sub _mainRef {
  my $n = shift;

  no strict 'refs';                                                               ## no critic 'NoStrict'

return *{"main::$n"}{HASH};
}

######################################################################################
#   Größe einer Struktur (exklusiv): jede Speicheradresse wird nur einmal gezählt
#   (ctx->{seen}), Referenzen auf fremde Wurzeln werden nicht verfolgt.
#   Iterativ (kein Rekursionslimit), Devel::Size::size() liefert nur die Flachgröße.
######################################################################################
sub _walk {
  my ($ctx, $root) = @_;

  return 0 if(!ref $root);

  my $seen    = $ctx->{seen};
  my $foreign = $ctx->{foreign};
  my $skipc   = $ctx->{skipc};
  my @stack   = ($root);
  my $sum     = 0;

  while (@stack) {
      my $r = pop @stack;
      my $t = reftype ($r) // next;

      next if($seen->{refaddr ($r)}++);

      if ($NOWALK{$t}) {                                                            # Sockets, Dateihandles, Code, ...: nicht anfassen
          $skipc->{$t}++;
          next;
      }

      if (_isTied ($r, $t)) {                                                       # tied/magic: Zugriff würde fremden Code ausführen
          $skipc->{tied}++;
          next;
      }

      if (++$ctx->{nodes} > $ctx->{max}) {
          $ctx->{trunc} = 1;
          last;
      }

      if ($t eq 'HASH') {
          $sum += Devel::Size::size ($r);
          for my $v (values %$r) {
              if (ref $v) { $sum += $RVSIZE; push @stack, $v if(!$foreign->{refaddr ($v)}); }
              else        { $sum += _safeSize ($ctx, $v); }
          }
      }
      elsif ($t eq 'ARRAY') {
          $sum += Devel::Size::size ($r);
          for my $v (@$r) {
              next if(!defined $v);
              if (ref $v) { $sum += $RVSIZE; push @stack, $v if(!$foreign->{refaddr ($v)}); }
              else        { $sum += _safeSize ($ctx, $v); }
          }
      }
      elsif ($t eq 'REF') {
          $sum += Devel::Size::size ($r);
          my $v = $$r;
          push @stack, $v if(ref $v && !$foreign->{refaddr ($v)});
      }
      elsif ($t eq 'SCALAR') {
          $sum += Devel::Size::size ($r);
      }
  }

return $sum;
}

######################################################################################
#   tied/magic Strukturen werden nicht angefasst
######################################################################################
sub _isTied {
  my ($r, $t) = @_;

  return defined tied (%$r) ? 1 : 0 if($t eq 'HASH');
  return defined tied (@$r) ? 1 : 0 if($t eq 'ARRAY');
  return defined tied ($$r) ? 1 : 0 if($t eq 'SCALAR' || $t eq 'REF');

return 0;
}

######################################################################################
#   Größe eines Skalars - Dateihandles/Globs (z.B. $hash->{FH} = *FH) werden übersprungen.
#   Der Wert wird als Alias in @_ übergeben (keine Kopie großer Strings).
######################################################################################
sub _safeSize {
  my $ctx = shift;

  return 0 if(!defined $_[0]);

  my $t = ref \$_[0];

  if ($t ne 'SCALAR' && $t ne 'VSTRING') {
      $ctx->{skipc}{$t}++;
      return 0;
  }

return Devel::Size::size ($_[0]);
}

######################################################################################
sub _skipped {
  my ($ctx, $path) = @_;

  return 0 if(!$ctx->{skip}{$path});

  push @{$ctx->{skippedPaths}}, $path;

return 1;
}

######################################################################################
#   Wie _walk, aber bis $CRUMBDEPTH wird jedes Kind einzeln gemessen und vorher in die
#   Breadcrumb-Datei geschrieben. Stürzt Devel::Size ab, steht dort der Pfad des Objekts,
#   das gerade gemessen wurde. Objekte aus der Crash-Liste werden übersprungen.
######################################################################################
sub _walkCrumb {
  my ($ctx, $v, $path, $depth) = @_;

  return 0 if(!ref $v);
  return 0 if(_skipped ($ctx, $path));

  _crumb ($ctx, $path);

  my $t = reftype ($v) // return 0;

  if ($depth >= $CRUMBDEPTH || ($t ne 'HASH' && $t ne 'ARRAY') || $NOWALK{$t} || _isTied ($v, $t)) {
      return _walk ($ctx, $v);
  }

  my $n = $t eq 'HASH' ? scalar keys %$v : scalar @$v;
  return _walk ($ctx, $v) if($n > $CRUMBFAN);

  return 0 if($ctx->{seen}{refaddr ($v)}++);

  if (++$ctx->{nodes} > $ctx->{max}) {
      $ctx->{trunc} = 1;
      return 0;
  }

  my $sum   = Devel::Size::size ($v);
  my @keys  = $t eq 'HASH' ? sort keys %$v : (0 .. $#{$v});

  for my $k (@keys) {
      my $c = $t eq 'HASH' ? $v->{$k} : $v->[$k];

      if (!ref $c) {
          $sum += $t eq 'HASH' ? _safeSize ($ctx, $v->{$k}) : _safeSize ($ctx, $v->[$k]);
          next;
      }

      $sum += $RVSIZE;
      next if($ctx->{foreign}{refaddr ($c)});

      $sum += _walkCrumb ($ctx, $c, $path.($t eq 'HASH' ? "{$k}" : "[$k]"), $depth + 1);
  }

return $sum;
}

######################################################################################
#   ein Device vermessen: Gesamtgröße, Größe je Top-Level-Key, Anzahl Readings
######################################################################################
sub _measureDevice {
  my ($ctx, $h, $d) = @_;

  my $path    = "\$defs{$d}";
  my $foreign = $ctx->{foreign};
  my %parts;

  _crumb ($ctx, $path);

  return (0, \%parts, 0) if(_isTied ($h, 'HASH'));

  my $total = Devel::Size::size ($h);

  $ctx->{seen}{refaddr ($h)}++;

  for my $k (sort keys %$h) {                                                      # jeden Schlüssel einzeln messen
      if (!ref $h->{$k}) {
          $total += _safeSize ($ctx, $h->{$k});
          next;
      }

      my $v = $h->{$k};

      $total += $RVSIZE;
      next if($foreign->{refaddr ($v)});                                           # z.B. IODev

      my $s = _walkCrumb ($ctx, $v, "$path\{$k}", 1);
      $parts{$k} = $s;
      $total    += $s;
  }

  my $nread = ref $h->{READINGS} eq 'HASH' ? scalar keys %{$h->{READINGS}} : 0;

return ($total, \%parts, $nread);
}

######################################################################################
#   Hauptmessung
######################################################################################
sub _measure {
  my $p = shift;

  my $t0 = [gettimeofday];

  return { error => "Perl module Devel::Size is missing" } if(!eval { require Devel::Size; 1 });

  $Devel::Size::warn = 0;

  return _measureTree ($p) if($p->{mode} eq 'tree');

  my $ctx  = _newCtx ($p);
  my $excl = $p->{excl} // {};

  _crumbOpen ($ctx, $p->{trace}, $p->{mode});
  my @devs = $p->{devs} ? @{$p->{devs}} : keys %defs;

  my (%flat, @skipped, %tsz, %tn);
  my $attrib = 0;
  my $trackErr;

  for my $d (sort @devs) {
      my $h = $defs{$d};
      next if(ref $h ne 'HASH');

      my $type = $h->{TYPE} // 'unknown';

      if ($excl->{$type}) {
          push @skipped, $d;
          next;
      }

      next if(_skipped ($ctx, "\$defs{$d}"));                                      # Device steht auf der Crash-Liste

      my %own;                                                                      # eigene Snapshot-Ablage nicht mitmessen, sonst würde sie als "wachsend" erscheinen
      if ($type eq 'Analyze' && ref $h->{HELPER} eq 'HASH') {
          for my $k (qw(SNAP RSSLOG LASTTEXT TRACK)) { $own{$k} = delete $h->{HELPER}{$k} if(exists $h->{HELPER}{$k}); }
      }

      my ($size, $parts, $nread) = _measureDevice ($ctx, $h, $d);

      $h->{HELPER}{$_} = $own{$_} for keys %own;

      $flat{"dev:$d"}   = $size;
      $flat{"reads:$d"} = $nread if($nread);

      for my $k (keys %$parts) {
          $flat{"part:$d\{$k}"} = $parts->{$k} if($parts->{$k} >= $PARTMIN);
      }

      $tsz{$type} += $size;
      $tn{$type}++;
      $attrib     += $size;
  }

  $flat{"type:$_"}  = $tsz{$_} for keys %tsz;
  $flat{"typen:$_"} = $tn{$_}  for keys %tn;

  if ($p->{full}) {
      for my $t (sort keys %modules) {                                              # Modul-Hashes ($modules{TYPE})
          my $r = $modules{$t};
          next if(ref $r ne 'HASH');
          my $s = _walkCrumb ($ctx, $r, "\$modules{$t}", 1);
          next if(!$s);
          $flat{"mod:$t"} = $s;
          $attrib        += $s;
      }

      for my $n (_mainHashes ()) {                                                  # FHEM Kernstrukturen
          my $s = _walkCrumb ($ctx, _mainRef ($n), "\$$n", 0);
          $flat{"main:$n"} = $s;
          $attrib         += $s;
      }

      $attrib += _measureDeep ($ctx, \%flat) if($p->{deep});

      $trackErr = _measureTrack ($p, $ctx, \%flat) if($p->{track} && @{$p->{track}});   # nicht in 'attributed' enthalten (eigene Messkontexte)
  }

return {
    flat       => \%flat,
    attributed => $attrib,
    nodes      => $ctx->{nodes},
    trunc      => $ctx->{trunc},
    skipped    => \@skipped,
    skippedPaths => $ctx->{skippedPaths},
    skipc      => $ctx->{skipc},
    secs       => tv_interval ($t0),
    deep       => $p->{deep} ? 1 : 0,
    trackErr   => $trackErr,
};
}

######################################################################################
#   deepScan: Paketvariablen ('our') unter FHEM:: und - mit PadWalker - file-scope 'my'
#   Variablen aller FHEM-Modul-Dateien (über die Closures ihrer Subs).
######################################################################################
sub _measureDeep {
  my ($ctx, $flat) = @_;

  my $sum = 0;
  my @pkgs;

  _packages ('FHEM', 0, \@pkgs);

  no strict 'refs';                                                               ## no critic 'NoStrict'

  my %skip = map { $_ => 1 } qw(BEGIN END ISA EXPORT EXPORT_OK VERSION AUTOLOAD DESTROY import);

  for my $pkg (@pkgs) {                                                           # Paketvariablen
      for my $k (keys %{"${pkg}::"}) {
          next if($k =~ /::$/x || $skip{$k} || $k !~ /^\w+$/x);

          for my $slot (['$', 'SCALAR'], ['@', 'ARRAY'], ['%', 'HASH']) {
              my ($sigil, $type) = @$slot;

              my $s = eval {
                  my $ref = *{"${pkg}::$k"}{$type};
                  return 0 if(!$ref);
                  return 0 if($type eq 'SCALAR' && !defined $$ref);
                  _walkCrumb ($ctx, $ref, "pkgvar:${pkg}::$sigil$k", $CRUMBDEPTH);
              } // 0;

              next if(!$s);

              $flat->{"pkg:$pkg"}                    += $s;
              $flat->{"pkgvar:$pkg\::$sigil$k"}       = $s if($s >= $PARTMIN);
              $sum                                   += $s;
          }
      }
  }

  return $sum if(!$hasPadWalker);

  my %done;
  for my $pkg ('main', @pkgs) {                                                   # file-scope 'my' Variablen
      for my $k (keys %{"${pkg}::"}) {
          next if($k =~ /::$/x || $k !~ /^\w+$/x);

          _crumb ($ctx, "code:${pkg}::$k");

          my $cv = eval { *{"${pkg}::$k"}{CODE} } or next;
          next if($done{refaddr ($cv)}++);

          my $file = eval { B::svref_2object ($cv)->FILE } // next;
          next if($file !~ m{(?:^|/)(?:FHEM/[^/]+\.pm|[^/]*\.pl)$}x || $file =~ m{(?:^|/)fhem\.pl$}x);

          (my $fk = $file) =~ s{^.*/}{}x;

          next if(_skipped ($ctx, "closed_over:$fk"));
          _crumb ($ctx, "closed_over:$fk");

          my $vars = eval { PadWalker::closed_over ($cv) } or next;

          for my $vn (keys %$vars) {
              my $s = _walkCrumb ($ctx, $vars->{$vn}, "var:$fk:$vn", $CRUMBDEPTH);
              next if(!$s);

              $flat->{"file:$fk"}        += $s;
              $flat->{"var:$fk:$vn"}      = $s if($s >= $PARTMIN);
              $sum                       += $s;
          }
      }
  }

return $sum;
}

######################################################################################
sub _packages {
  my ($pkg, $depth, $out) = @_;

  push @$out, $pkg;
  return if($depth > 3);

  no strict 'refs';                                                               ## no critic 'NoStrict'

  for my $k (keys %{"${pkg}::"}) {
      next if($k !~ /^(\w+)::$/x);
      my $sub = $1;
      next if($sub eq 'main' || $sub eq 'FHEM' || $sub eq 'GPUtils');
      _packages ("${pkg}::$sub", $depth + 1, $out);
  }

return;
}

######################################################################################
#   Pfadangabe auflösen: $defs{dev}{helper}, $data{x}[2], ...
#   Rückgabe: ($ref, $pfad, $fehlertext)
######################################################################################
sub _resolvePath {
  my $spec = shift // q{};

  $spec =~ s/\s+//xg;

  my ($root, $rest) = $spec =~ /^\$?([A-Za-z_]\w*)(.*)$/x
      or return (undef, undef, _t ('path_parse', $spec));

  no strict 'refs';                                                               ## no critic 'NoStrict'
  my $ref = *{"main::$root"}{HASH} // *{"main::$root"}{ARRAY};
  use strict 'refs';

  return (undef, undef, _t ('path_noroot', $root)) if(!$ref);

return _descend ($ref, '$'.$root, $rest, $spec);
}

######################################################################################
#   Teilpfad {key}[index]... ab einer Referenz auflösen
#   Rückgabe: ($ref, $pfad, $fehlertext)
######################################################################################
sub _descend {
  my ($ref, $path, $rest, $spec) = @_;

  my @seg;
  my $pos = 0;

  while ($rest =~ /\G(?:\{([^}]*)\}|\[(\d+)\])/xgc) {
      if (defined $1) {
          (my $key = $1) =~ s/^(["'])(.*)\1$/$2/x;
          push @seg, ['h', $key];
      }
      else {
          push @seg, ['a', $2];
      }
      $pos = pos ($rest);
  }

  return (undef, undef, _t ('path_parse_near', $spec, substr ($rest, $pos))) if($pos != length $rest);

  for my $s (@seg) {
      my ($type, $key) = @$s;
      my $rt = reftype ($ref) // q{};

      if ($rt eq 'HASH') {
          return (undef, undef, _t ('path_nokey', $key, $path)) if(!exists $ref->{$key});
          $ref   = $ref->{$key};
          $path .= "{$key}";
      }
      elsif ($rt eq 'ARRAY' && $key =~ /^\d+$/x) {
          return (undef, undef, _t ('path_noidx', $key, $path)) if($key > $#{$ref});
          $ref   = $ref->[$key];
          $path .= "[$key]";
      }
      else {
          return (undef, undef, _t ('path_notcont', $path, $key));
      }
  }

return ($ref, $path, undef);
}

######################################################################################
#   Tracking: Attribut trackObjects auswerten
#   Erlaubt sind (Trenner: Leerzeichen oder Komma, Schlüssel ohne diese Zeichen)
#     $defs{dev}{.key}  $data{x}[2]   Hash/Array der FHEM-Hauptebene (wie xHashDetail)
#     %FHEM::Modul::name              Paketvariable (our), auch @ und $
#     datei.pm:%name                  file-scope 'my' Variable (benötigt PadWalker)
#   Rückgabe: (\@gültige, \@ungültige Einträge)
######################################################################################
sub _trackParse {
  my $str = shift // q{};

  my (@ok, @bad, %seen);

  for my $e (grep { length } split /[\s,]+/x, $str) {
      my $t = _trackSpec ($e);

      if (!$t) {
          push @bad, $e;
          next;
      }

      push @ok, $t if(!$seen{$t->{spec}}++);
  }

return (\@ok, \@bad);
}

######################################################################################
sub _trackSpec {
  my $e = shift;

  my $t;

  if ($e =~ /^([\w.\-]+\.(?:pm|pl)):([\$\@%][A-Za-z_]\w*)((?:\{[^}]*\}|\[[0-9]+\])*)$/x) {
      $t = { kind => 'file', file => $1, var => $2, rest => $3, spec => "$1:$2$3" };
  }
  elsif ($e =~ /^([\$\@%])((?:[A-Za-z_]\w*::)+[A-Za-z_]\w*)((?:\{[^}]*\}|\[[0-9]+\])*)$/x) {
      $t = { kind => 'pkg', sigil => $1, name => $2, rest => $3, spec => "$1$2$3" };
  }
  elsif ($e =~ /^\$?([A-Za-z_]\w*)((?:\{[^}]*\}|\[[0-9]+\])*)$/x) {
      $t = { kind => 'main', spec => '$'.$1.$2 };
  }

  return if(!$t);

  (my $id = $t->{spec}) =~ s/^[\$\@%]//x;                                         # Basis für den Readingnamen: track_<id>_bytes|count
  $id =~ s/[^A-Za-z0-9_\-]+/_/xg;
  $id =~ s/^_+|_+$//xg;
  $t->{id} = $id;

return $t;
}

######################################################################################
#   Verlauf und Readings von Objekten entfernen, die nicht mehr getrackt werden
######################################################################################
sub _trackCleanup {
  my ($hash, $list) = @_;

  my %keep = map { $_->{spec} => 1 } @$list;
  my %kid  = map { $_->{id}   => 1 } @$list;

  delete $hash->{HELPER}{TRACK}{$_} for grep { !$keep{$_} } keys %{$hash->{HELPER}{TRACK} // {}};

  for my $r (keys %{$hash->{READINGS} // {}}) {
      next if($r !~ /^track_(.+)_(?:bytes|count)$/x);
      readingsDelete ($hash, $r) if(!$kid{$1});
  }

return;
}

######################################################################################
#   Messwerte der getrackten Objekte in Verlauf (Ringpuffer) und Readings übernehmen
#   Verlauf: $hash->{HELPER}{TRACK}{<spec>} = [[Zeit, Bytes, Einträge], ...]
######################################################################################
sub _storeTrack {
  my ($hash, $job, $flat) = @_;

  my $list = $job->{track} // [];
  return if(!@$list);

  my $name = $hash->{NAME};
  my $max  = AttrVal ($name, 'trackMaxSamples', 500);
  my $tr   = $hash->{HELPER}{TRACK} //= {};
  my @del;

  readingsBeginUpdate ($hash);

  for my $t (@$list) {
      my $b = $flat->{"track:$t->{spec}"};
      my $n = $flat->{"trackn:$t->{spec}"};

      my $s = $tr->{$t->{spec}} //= [];
      push @$s, [$job->{time}, $b, $n];
      shift @$s while(@$s > $max);

      for my $v (['bytes', $b], ['count', $n]) {
          my $rn = "track_$t->{id}_$v->[0]";

          if (defined $v->[1]) { readingsBulkUpdate ($hash, $rn, $v->[1]); }
          else                 { push @del, $rn; }                                                  # Objekt in diesem Lauf nicht messbar: kein Wert statt eines veralteten
      }
  }

  readingsEndUpdate ($hash, 1);

  readingsDelete ($hash, $_) for @del;

return;
}

######################################################################################
#   file-scope 'my' Variablen der angegebenen Dateien über die Closures ihrer Subs suchen
#   (PadWalker). Es werden nur Subs der genannten Dateien untersucht, deepScan ist nicht nötig.
#   Rückgabe: { datei.pm => { '%name' => Referenz, ... } }
######################################################################################
sub _fileVars {
  my ($ctx, $files) = @_;

  my %found;
  return \%found if(!$hasPadWalker);

  my @pkgs;
  _packages ('FHEM', 0, \@pkgs);

  my %done;

  no strict 'refs';                                                               ## no critic 'NoStrict'

  for my $pkg ('main', @pkgs) {
      for my $k (keys %{"${pkg}::"}) {
          next if($k =~ /::$/x || $k !~ /^\w+$/x);

          my $cv = eval { *{"${pkg}::$k"}{CODE} } or next;
          next if($done{refaddr ($cv)}++);

          my $file = eval { B::svref_2object ($cv)->FILE } // next;
          (my $fk  = $file) =~ s{^.*/}{}x;
          next if(!$files->{$fk});

          next if(_skipped ($ctx, "closed_over:$fk"));
          _crumb ($ctx, "closed_over:$fk");

          my $vars = eval { PadWalker::closed_over ($cv) } or next;
          $found{$fk}{$_} //= $vars->{$_} for keys %$vars;
      }
  }

return \%found;
}

######################################################################################
#   Objekt eines Tracking-Eintrags auflösen
#   Rückgabe: ($ref, $pfad, $fehlertext)
######################################################################################
sub _trackResolve {
  my ($t, $fv) = @_;

  return _resolvePath ($t->{spec}) if($t->{kind} eq 'main');

  my ($ref, $path, $sigil);

  if ($t->{kind} eq 'file') {
      return (undef, undef, _t ('track_err_pw')) if(!$hasPadWalker);

      $ref = $fv->{$t->{file}}{$t->{var}};
      return (undef, undef, _t ('track_err_var', $t->{var}, $t->{file})) if(!$ref);

      $sigil = substr ($t->{var}, 0, 1);
      $path  = "var:$t->{file}:$t->{var}";
  }
  else {
      my ($pkg, $var) = $t->{name} =~ /^(.+)::([^:]+)$/x;
      $sigil          = $t->{sigil};
      $path           = "pkgvar:$sigil$t->{name}";

      no strict 'refs';                                                           ## no critic 'NoStrict'
      if (%{"${pkg}::"} && exists ${"${pkg}::"}{$var}) {
          $ref = *{"${pkg}::$var"}{$sigil eq '%' ? 'HASH' : $sigil eq '@' ? 'ARRAY' : 'SCALAR'};
      }
      use strict 'refs';

      return (undef, undef, _t ('track_err_pkg', "$sigil$t->{name}")) if(!$ref);
  }

  $ref = ${$ref} if($sigil eq '$');                                               # Skalar: Wert (kann selbst eine Referenz sein)

return _descend ($ref, $path, $t->{rest}, $t->{spec}) if(length $t->{rest});

return ($ref, $path, undef);
}

######################################################################################
#   getrackte Objekte (Attribut trackObjects): Größe und Anzahl der Einträge je Objekt.
#   Jedes Objekt wird mit eigenem Kontext gemessen, die Größe ist daher inklusiv und
#   unabhängig von der Messreihenfolge. Die Werte gehen nicht in 'attributed' ein,
#   sonst würde doppelt gezählt.
#   Rückgabe: { spec => Grund } der nicht messbaren Objekte
######################################################################################
sub _measureTrack {
  my ($p, $ctx0, $flat) = @_;

  my %err;
  my $list  = $p->{track} // [];
  my %files = map { $_->{file} => 1 } grep { $_->{kind} eq 'file' } @$list;
  my $fv    = %files ? _fileVars ($ctx0, \%files) : {};

  for my $t (@$list) {
      my ($ref, $path, $e) = _trackResolve ($t, $fv);

      if ($e) {
          $err{$t->{spec}} = $e;
          next;
      }

      if ($ctx0->{skip}{$path}) {                                                 # Objekt steht auf der Crash-Liste
          $err{$t->{spec}} = _t ('track_err_crash');
          next;
      }

      if (!defined $ref) {
          $err{$t->{spec}} = _t ('track_err_undef');
          next;
      }

      my ($bytes, $cnt);

      if (!ref $ref) {                                                            # einfacher Wert
          $bytes = Devel::Size::size ($ref);
      }
      else {
          my $c = _newCtx ($p);
          @{$c}{qw(trace mode)} = @{$ctx0}{qw(trace mode)};                       # Breadcrumb-Datei weiter verwenden
          delete $c->{foreign}{refaddr ($ref)};                                   # das Objekt selbst ist nicht 'fremd'

          $bytes = _walkCrumb ($c, $ref, $path, 1);

          my $rt = reftype ($ref) // q{};
          if (!_isTied ($ref, $rt)) {
              $cnt = $rt eq 'HASH' ? scalar keys %$ref : $rt eq 'ARRAY' ? scalar @$ref : undef;
          }
      }

      $flat->{"track:$t->{spec}"}  = $bytes;
      $flat->{"trackn:$t->{spec}"} = $cnt if(defined $cnt);
  }

return \%err;
}

######################################################################################
#   Baumansicht eines Objekts: Größe je Unterstruktur (exklusiv gezählt)
######################################################################################
sub _measureTree {
  my $p = shift;

  my $t0 = [gettimeofday];
  my ($ref, $path, $err) = _resolvePath ($p->{spec});

  return { error => $err } if($err);

  my $ctx = _newCtx ($p);
  delete $ctx->{foreign}{refaddr ($ref)} if(ref $ref);                             # das Objekt selbst ist nicht 'fremd'

  _crumbOpen ($ctx, $p->{trace}, 'tree');

  my $depth = $p->{treeDepth} // 3;
  my $node  = _node ($ctx, $ref, 0, $depth, $path);
  my @out;

  push @out, sprintf ("Object %s: %s total, type %s%s, %d objects walked in %.1f s%s",
                      $path, _hs ($node->{size}), $node->{type} // '?', $node->{class} ? " ($node->{class})" : '',
                      $ctx->{nodes}, tv_interval ($t0), $ctx->{trunc} ? ' (TRUNCATED by maxNodes)' : '');
  push @out, _t ('tree_excl');
  push @out, 'Not measured (no data memory): '.join (', ', map { "$_ x$ctx->{skipc}{$_}" } sort keys %{$ctx->{skipc}}) if(%{$ctx->{skipc}});
  push @out, 'Skipped (crash list): '.join (', ', @{$ctx->{skippedPaths}}) if(@{$ctx->{skippedPaths}});
  push @out, '';

  _printNode ($node, $path, 0, $p->{treeTop} // 15, $node->{size}, \@out);

  my @top;
  for my $k (@{$node->{kids} // []}) { push @top, [ "$path\{$k->[0]}", $k->[1]{size} ]; }

  my @sorted = sort { $b->[1] <=> $a->[1] } @top;
  splice(@sorted, 20);

  return {
      text => join("\n", @out),
      top  => \@sorted
  };
}

######################################################################################
sub _node {
  my ($ctx, $r, $depth, $maxd, $path) = @_;

  no warnings 'recursion';                                                        ## no critic 'ProhibitNoWarnings'

  my $t = reftype ($r) // return { size => 0, type => 'scalar' };

  my $node = { type => $t, class => blessed ($r), size => 0 };

  if (_skipped ($ctx, $path)) {                                                   # steht auf der Crash-Liste
      $node->{crash} = 1;
      return $node;
  }

  _crumb ($ctx, $path) if($depth <= $maxd + 1);

  if ($ctx->{seen}{refaddr ($r)}++) {
      $node->{shared} = 1;
      return $node;
  }

  if ($NOWALK{$t}) {
      $node->{skip} = $t;
      $ctx->{skipc}{$t}++;
      return $node;
  }

  if (_isTied ($r, $t)) {
      $node->{skip} = 'tied';
      $ctx->{skipc}{tied}++;
      return $node;
  }

  return $node if(++$ctx->{nodes} > $ctx->{max} && ($ctx->{trunc} = 1));

  my @pairs;

  if ($t eq 'HASH') {
      $node->{size} = Devel::Size::size ($r);
      $node->{cnt}  = scalar keys %$r;
      @pairs        = map { [$_, $r->{$_}] } sort keys %$r;
  }
  elsif ($t eq 'ARRAY') {
      $node->{size} = Devel::Size::size ($r);
      $node->{cnt}  = scalar @$r;
      @pairs        = map { ["[$_]", $r->[$_]] } 0 .. $#{$r};
  }
  elsif ($t eq 'REF') {
      $node->{size} = Devel::Size::size ($r);
      @pairs        = (['${}', $$r]);
  }
  elsif ($t eq 'SCALAR') {
      $node->{size} = Devel::Size::size ($r);
      return $node;
  }
  else {
      return $node;
  }

  for my $pr (@pairs) {
      my ($k, $v) = @$pr;

      if (!ref $v) {
          $node->{size} += _safeSize ($ctx, $v);
          next;
      }

      $node->{size} += $RVSIZE;
      next if($ctx->{foreign}{refaddr ($v)});

      my $c = _node ($ctx, $v, $depth + 1, $maxd, $path.($t eq 'HASH' ? "{$k}" : $k));
      $node->{size} += $c->{size};

      push @{$node->{kids}}, [$k, $c] if($depth < $maxd);
  }

return $node;
}

######################################################################################
sub _printNode {
  my ($n, $label, $lvl, $top, $total, $out) = @_;

  no warnings 'recursion';                                                        ## no critic 'ProhibitNoWarnings'

  my $pct = $total ? 100 * $n->{size} / $total : 0;
  my $inf = $n->{type} // '';
  $inf   .= ", $n->{cnt} entries" if(defined $n->{cnt});
  $inf   .= ", $n->{class}"       if($n->{class});
  $inf   .= ", shared (counted elsewhere)" if($n->{shared});
  $inf   .= ", SKIPPED (crash list)"       if($n->{crash});
  $inf   .= ", not measured ($n->{skip})"  if($n->{skip});

  push @$out, sprintf ("%s%10s %5.1f%%  %s  [%s]", '  ' x $lvl, _hs ($n->{size}), $pct, $label, $inf);

  my @k = sort { $b->[1]{size} <=> $a->[1]{size} } @{$n->{kids} // []};
  my $i = 0;

  for my $k (@k) {
      if (++$i > $top) {
          my $rest = 0;
          $rest   += $_->[1]{size} for @k[$top .. $#k];
          push @$out, sprintf ("%s%10s         ... %d further entries", '  ' x ($lvl + 1), _hs ($rest), scalar @k - $top);
          last;
      }
      _printNode ($k->[1], $k->[0], $lvl + 1, $top, $total, $out);
  }

return;
}

#############################################################################################
#                                   Prozess- und Zählerdaten (Hauptprozess)
#############################################################################################

######################################################################################
#   Prozessspeicher in kB
#   rss    = Resident Set Size (für Trends verwenden)
#   priv   = Private_Clean+Private_Dirty, shared = Shared_*, pss = proportional set size
#   hwm    = Spitzenwert rss, anon = anonymer Speicher (Heap)
######################################################################################
sub procInfo {
  my %r = (rss => 0, pss => 0, priv => 0, shared => 0, swap => 0, hwm => 0, anon => 0);

  if (open my $fs, '<', '/proc/self/status') {
      while (my $l = <$fs>) {
          $r{rss}  = $1 if $l =~ /^VmRSS:\s+(\d+)/x;
          $r{hwm}  = $1 if $l =~ /^VmHWM:\s+(\d+)/x;
          $r{anon} = $1 if $l =~ /^RssAnon:\s+(\d+)/x;
          $r{swap} = $1 if $l =~ /^VmSwap:\s+(\d+)/x;
      }
      close $fs;
  }

  if (open my $fh, '<', '/proc/self/smaps_rollup') {
      while (my $l = <$fh>) {
          $r{pss}     = $1 if $l =~ /^Pss:\s+(\d+)/x;
          $r{priv}   += $1 if $l =~ /^Private_(?:Clean|Dirty):\s+(\d+)/x;
          $r{shared} += $1 if $l =~ /^Shared_(?:Clean|Dirty):\s+(\d+)/x;
      }
      close $fh;
  }

return \%r;
}

######################################################################################
sub counters {
  my %c = (
      defs   => scalar (keys %defs),
      timers => scalar (keys %intAt),
      select => scalar (keys %selectlist),
      ready  => scalar (keys %readyfnlist),
  );

  my $fds = 0;
  if (opendir my $dh, '/proc/self/fd') {
      $fds = grep { !/^\./x } readdir $dh;
      closedir $dh;
      $fds-- if($fds);                                                            # das Verzeichnishandle selbst nicht mitzählen
  }

  $c{fds}  = $fds;
  $c{kids} = _countKids ();

return \%c;
}

######################################################################################
sub _countKids {
  my @cf = glob '/proc/self/task/*/children';
  my $k  = 0;

  if (@cf) {
      for my $f (@cf) {
          open my $fh, '<', $f or next;
          local $/;
          my $c = <$fh> // q{};
          $k   += () = $c =~ /\d+/xg;
          close $fh;
      }
      return $k;
  }

  if (opendir my $dh, '/proc') {                                                  # Fallback ohne CONFIG_PROC_CHILDREN
      for my $pid (grep { /^\d+$/x } readdir $dh) {
          open my $fh, '<', "/proc/$pid/stat" or next;
          my $l = <$fh> // q{};
          close $fh;
          $k++ if($l =~ /^\d+\s+\(.*\)\s+\S\s+(\d+)\s/x && $1 == $$);
      }
      closedir $dh;
  }

return $k;
}

######################################################################################
#   Timer nach Funktion und nach Device (Argument)
######################################################################################
sub timersByFn {
  my (%fn, %dev);

  for my $k (keys %intAt) {
      my $t = $intAt{$k};
      next if(ref $t ne 'HASH');

      $fn{_fnName ($t->{FN})}++;

      my $arg = $t->{ARG};

      if (ref $arg eq 'HASH' && defined $arg->{NAME}) {
          $dev{$arg->{NAME}}++;
      }
      elsif (defined $arg && !ref $arg && exists $defs{$arg}) {
          $dev{$arg}++;
      }
  }

return (\%fn, \%dev);
}

######################################################################################
sub _fnName {
  my $fn = shift;

  return 'undef' if(!defined $fn);
  return $fn     if(!ref $fn);
  return 'REF'   if(ref $fn ne 'CODE');

  my $n = eval {
      my $cv = B::svref_2object ($fn);
      my $gv = $cv->GV;
      my $nm = $gv->STASH->NAME.'::'.$gv->NAME;

      if ($gv->NAME eq '__ANON__') {
          (my $f = $cv->FILE // q{}) =~ s{^.*/}{}x;
          my $line = eval { $cv->START->line } // 0;
          $nm .= " ($f:$line)";
      }

      $nm;
  };

return $n // 'CODE';
}

######################################################################################
#   Steigung des RSS in kB/h über die letzten $hours Stunden (lineare Regression)
######################################################################################
sub _rssSlope {
  my ($log, $hours) = @_;

  my $tmin = time - $hours * 3600;
  my @p    = grep { $_->[0] >= $tmin } @$log;

  return if(@p < 6);

  my $n = scalar @p;
  my ($sx, $sy, $sxy, $sxx) = (0, 0, 0, 0);

  for my $q (@p) {
      my ($x, $y) = (($q->[0] - $p[0][0]) / 3600, $q->[1]);
      $sx += $x; $sy += $y; $sxy += $x * $y; $sxx += $x * $x;
  }

  my $den = $n * $sxx - $sx * $sx;
  return if(!$den);

return ($n * $sxy - $sx * $sy) / $den;
}

#############################################################################################
#                                   Auswertung / Ausgabe
#############################################################################################

######################################################################################
# Text in der Sprache des globalen Attributs 'language' (DE, sonst EN)
# Ohne Argumente wird der Text unverändert geliefert, sonst über sprintf aufgefüllt
######################################################################################
sub _t {
  my $key = shift;

  my $t = $TXT{$key} or return $key;
  my $l = uc (AttrVal ('global', 'language', 'EN'));
  my $f = $t->{$l} // $t->{EN};
  
  utf8::encode ($f) if(!$unicodeEncoding);                                        # bytestream: FHEM erwartet UTF-8 Bytes, unicode: Zeichenstrings (kodiert wird beim Ausgeben)

return @_ ? sprintf ($f, @_) : $f;
}

######################################################################################
sub _hs {                                                                         # Bytes lesbar
  my $bytes = shift // 0;
  my $sign = $bytes < 0 ? '-' : q{};
  $bytes   = abs $bytes;

  return sprintf ('%s%d B',    $sign, $bytes)             if($bytes < 1024);
  return sprintf ('%s%.1f kB', $sign, $bytes / 1024)      if($bytes < 1048576);

return sprintf ('%s%.2f MB', $sign, $bytes / 1048576);
}

######################################################################################
sub _fmtVal {                                                                     # Wert abhängig von der Kategorie
  my ($cat, $v) = @_;

  my $u = $UNIT{$cat} // '#';

  return _hs ($v)                if($u eq 'B');
  return sprintf ('%d kB', $v)   if($u eq 'kB');

return sprintf ('%d', $v);
}

######################################################################################
sub _fmtDelta {
  my ($cat, $d) = @_;

  my $s = _fmtVal ($cat, $d);

return ($d > 0 ? '+' : q{}).$s;
}

######################################################################################
sub _label {                                                                      # Schlüssel -> lesbarer Name
  my ($cat, $key) = @_;

  return '$defs{'.$1.'}{'.$2.'}' if($cat eq 'part' && $key =~ /^(.+?)\{(.*)\}$/x);
  return "$1  $2"                if($cat eq 'var'  && $key =~ /^([^:]+):(.+)$/x);

return $key;
}

######################################################################################
sub _cat {                                                                        # alle Einträge einer Kategorie
  my ($flat, $cat) = @_;

  my $pl = length ($cat) + 1;
  my %r;

  for my $k (keys %$flat) {
      next if(index ($k, "$cat:") != 0);
      $r{substr ($k, $pl)} = $flat->{$k};
  }

return \%r;
}

######################################################################################
sub _topLines {
  my ($flat, $cat, $top) = @_;

  my $h = _cat ($flat, $cat);
  my @k = sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h;
  my @o;

  for my $k (@k[0 .. ($#k < $top - 1 ? $#k : $top - 1)]) {
      push @o, sprintf ("  %12s  %s", _fmtVal ($cat, $h->{$k}), _label ($cat, $k));
  }

return @o;
}

######################################################################################
#   Bericht zu einem Snapshot
######################################################################################
sub _reportSnap {
  my ($s, $top) = @_;

  my $f = $s->{flat};
  my @o;

  push @o, sprintf ("Snapshot '%s' from %s  (%d objects walked in %.1f s%s%s)",
                    $s->{label}, strftime ('%Y-%m-%d %H:%M:%S', localtime $s->{time}), $s->{nodes} // 0, $s->{secs} // 0,
                    $s->{trunc} ? ', TRUNCATED by maxNodes - sizes incomplete' : q{}, $s->{deep} ? ', deepScan' : q{});

  push @o, '';

  if (defined $f->{'proc:rss'}) {
      push @o, sprintf ("Process:   rss %d kB (peak %d)  pss %d  private %d  shared %d  swap %d",
                        map { $f->{"proc:$_"} // 0 } qw(rss hwm pss priv shared swap));
      push @o, sprintf ("Counters:  devices %d  timers %d  fds %d  child processes %d  selectlist %d  readyfnlist %d",
                        map { $f->{"cnt:$_"} // 0 } qw(defs timers fds kids select ready));
  }

  if (defined $f->{'proc:attributed'}) {
      push @o, sprintf ("Attributed to FHEM data structures: %d kB of %d kB rss;  not attributable: %d kB",
                        $f->{'proc:attributed'}, $f->{'proc:rss'} // 0, $f->{'proc:unattributed'} // 0);
      push @o, $s->{deep} ? _t ('unattr_note') : _t ('unattr_note_nd');
  }

  push @o, '';

  my %sec = (
      type   => 'Largest device types',
      dev    => 'Largest devices',
      part   => 'Largest parts of devices',
      main   => 'FHEM core hashes',
      mod    => 'Largest module hashes',
      file   => 'Module files (file-scope variables)',
      var    => 'Largest file-scope variables',
      pkgvar => 'Largest package variables (our)',
      reads  => 'Devices with most readings',
      timer  => 'Timers by function',
      track  => 'Tracked objects',
  );

  for my $c (qw(track type dev part main mod file var pkgvar reads timer)) {
      my @l = _topLines ($f, $c, ($c eq 'main' ? 20 : $top));
      next if(!@l);

      my $title = "$sec{$c} (top ".($c eq 'main' ? 'all' : $top).")";
      push @o, $title.":";

      if ($c eq 'type') {                                                            # Typen mit Anzahl und Durchschnitt
          my $n = _cat ($f, 'typen');
          my $t = _cat ($f, 'type');
          my @k = sort { $t->{$b} <=> $t->{$a} || $a cmp $b } keys %$t;
          @l    = map { sprintf ("  %12s  %4dx  avg %-10s  %s", _hs ($t->{$_}), $n->{$_} // 0, _hs ($n->{$_} ? $t->{$_} / $n->{$_} : 0), $_) }
                  @k[0 .. ($#k < $top - 1 ? $#k : $top - 1)];
      }

      if ($c eq 'track') {                                                           # getrackte Objekte mit Anzahl der Einträge
          my $n = _cat ($f, 'trackn');
          my $t = _cat ($f, 'track');
          my @k = sort { $t->{$b} <=> $t->{$a} || $a cmp $b } keys %$t;
          @l    = map { sprintf ("  %12s  %7s entries  %s", _hs ($t->{$_}), defined $n->{$_} ? $n->{$_} : '-', $_) }
                  @k[0 .. ($#k < $top - 1 ? $#k : $top - 1)];
      }

      push @o, @l, '';
  }

  if ($s->{skipped} && @{$s->{skipped}}) {
      push @o, 'Skipped (excluded types): '.join (', ', @{$s->{skipped}}), '';
  }

  if ($s->{skippedPaths} && @{$s->{skippedPaths}}) {
      push @o, 'Skipped objects (crash list): '.join (', ', @{$s->{skippedPaths}}), '';
  }

  if ($s->{skipc} && %{$s->{skipc}}) {
      push @o, 'Not measured (no data memory): '.join (', ', map { "$_ x$s->{skipc}{$_}" } sort keys %{$s->{skipc}}), '';
  }

  if ($s->{trackErr} && %{$s->{trackErr}}) {
      push @o, _t ('track_err_head').': '.join (', ', map { "$_ ($s->{trackErr}{$_})" } sort keys %{$s->{trackErr}}), '';
  }

return join ("\n", @o);
}

######################################################################################
#   Vergleich zweier Snapshots
######################################################################################
sub _reportDiff {
  my ($s0, $s1, $top) = @_;

  my ($f0, $f1) = ($s0->{flat}, $s1->{flat});
  my $hours     = ($s1->{time} - $s0->{time}) / 3600;
  my @o;

  push @o, sprintf ("Comparison '%s' -> '%s'   period: %.2f h", $s0->{label}, $s1->{label}, $hours), '';

  push @o, 'Process memory:';
  for my $k (qw(rss anon pss priv shared swap)) {
      next if(!defined $f1->{"proc:$k"});
      my $d = ($f1->{"proc:$k"} // 0) - ($f0->{"proc:$k"} // 0);
      push @o, sprintf ("  %-12s %8d kB -> %8d kB   %+8d kB  (%+.0f kB/h)", $k, $f0->{"proc:$k"} // 0, $f1->{"proc:$k"}, $d, $hours ? $d / $hours : 0);
  }

  if (defined $f1->{'proc:attributed'} && defined $f0->{'proc:attributed'}) {
      my $da = $f1->{'proc:attributed'}   - $f0->{'proc:attributed'};
      my $du = $f1->{'proc:unattributed'} - $f0->{'proc:unattributed'};
      push @o, sprintf ("  %-12s %+8d kB   (attributed to FHEM structures)", 'attributed',   $da);
      push @o, sprintf ("  %-12s %+8d kB   (rest: interpreter, code, fragmentation, file-scope variables)", 'unattributed', $du);
  }

  if (($f0->{'cnt:kids'} // 0) != ($f1->{'cnt:kids'} // 0)) {
      push @o, _t ('diff_kids');
  }

  push @o, '', 'Counters:';
  for my $k (sort keys %{_cat ($f1, 'cnt')}) {
      my ($v0, $v1) = ($f0->{"cnt:$k"} // 0, $f1->{"cnt:$k"});
      push @o, sprintf ("  %-8s %6d -> %6d  (%+d)", $k, $v0, $v1, $v1 - $v0);
  }

  for my $c (grep { $_ ne 'proc' && $_ ne 'cnt' } @CATORDER) {
      my $h0  = _cat ($f0, $c);                                                    # nicht $a/$b nennen: das sind die Variablen von sort
      my $h1  = _cat ($f1, $c);
      my %u   = map { $_ => 1 } (keys %$h0, keys %$h1);
      my $min = $UNIT{$c} eq 'B' ? 1024 : 1;

      my @g = sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] }
              grep { $_->[1] >= $min }
              map  { [$_, ($h1->{$_} // 0) - ($h0->{$_} // 0), $h0->{$_} // 0, $h1->{$_} // 0] } keys %u;

      next if(!@g);

      push @o, '', "$CATTITLE{$c} - growth (top $top):";
      push @o, map { sprintf ("  %12s  %s  (%s -> %s)", _fmtDelta ($c, $_->[1]), _label ($c, $_->[0]), _fmtVal ($c, $_->[2]), _fmtVal ($c, $_->[3])) }
               @g[0 .. ($#g < $top - 1 ? $#g : $top - 1)];
  }

  push @o, '', _t ('diff_hint');

return join ("\n", @o);
}

######################################################################################
#   Leak-Kandidaten: Objekte, die über alle Snapshots kontinuierlich wachsen
######################################################################################
sub _reportLeaks {
  my ($snaps, $top, $minBytes) = @_;

  my $n     = scalar @$snaps;
  my $hours = ($snaps->[-1]{time} - $snaps->[0]{time}) / 3600;
  my %keys  = map { $_ => 1 } map { keys %{$_->{flat}} } @$snaps;

  my %tol = ('B' => 128, 'kB' => 128, '#' => 0);
  my %min = ('B' => $minBytes, 'kB' => 512, '#' => 3);
  my $need = ceil (0.75 * ($n - 1));

  my %cand;

  for my $key (keys %keys) {
      my ($cat, $rest) = split /:/x, $key, 2;
      next if(!$UNIT{$cat} || $key eq 'proc:unattributed' && 0);
      next if($cat eq 'proc' && $rest !~ /^(?:rss|anon|unattributed|attributed)$/x);

      my @v = map { $_->{flat}{$key} // 0 } @$snaps;
      my $u = $UNIT{$cat};
      my $net = $v[-1] - $v[0];

      next if($net < $min{$u});

      my ($up, $down) = (0, 0);
      for my $i (1 .. $#v) {
          my $d = $v[$i] - $v[$i-1];
          if    ($d >  $tol{$u}) { $up++;   }
          elsif ($d < -$tol{$u}) { $down++; }
      }

      next if($down || $up < $need);

      push @{$cand{$cat}}, { key => $rest, net => $net, rate => $hours ? $net / $hours : 0, v => \@v };
  }

  my @o = (_t ('leak_head', $need, $n - 1),
           sprintf ("Snapshots: %s   period: %.1f h", join (', ', map { $_->{label} } @$snaps), $hours), '');

  my $found = 0;

  for my $c (@CATORDER) {
      next if(!$cand{$c});
      my @l = sort { $b->{net} <=> $a->{net} } @{$cand{$c}};

      push @o, "$CATTITLE{$c}:";

      for my $e (@l[0 .. ($#l < $top - 1 ? $#l : $top - 1)]) {
          push @o, sprintf ("  %12s  %-45s %s  (%s/h)", _fmtDelta ($c, $e->{net}), _label ($c, $e->{key}),
                            join (' -> ', map { _fmtVal ($c, $_) } @{$e->{v}}), _fmtVal ($c, $e->{rate}));
          $found++;
      }

      push @o, '';
  }

  push @o, _t ('leak_none'), '' if(!$found);

  push @o, _t ('interp_head'), _t ('interp_part'), _t ('interp_var'), _t ('interp_timer'), _t ('interp_cnt'), _t ('interp_track'), _t ('interp_proc');

return join ("\n", @o);
}

#############################################################################################
#  liefert die Versionierung des Moduls zurück
#  Verwendung mit Packages:  use version 0.77; our $VERSION = moduleVersion ($hash, $notes)
#  Verwendung ohne Packages: moduleVersion ($params)
#
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub moduleVersion {
  my ($hash, $notes) = @_;

  my $type    = $hash->{TYPE};
  my $package = (caller)[0];                                                                # das PACKAGE des aufrufenden Moduls

  my $v                    = (sortVersion ("desc", keys %{$notes}))[0];                     # die Modulversion aus Versionshash selektieren
  $hash->{HELPER}{VERSION} = $v;
  $hash->{HELPER}{PACKAGE} = $package;

  if ($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {            # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{<TYPE>}{META}}

      if ($modules{$type}{META}{x_version}) {                                               # {x_version} nur gesetzt wenn $Id$ im Kopf komplett! vorhanden
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      }
      else {
          $modules{$type}{META}{x_version} = $v;
      }

      FHEM::Meta::SetInternals ($hash);                                                     # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
  }
  else {                                                                                    # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;                                                                # Internal VERSION setzen
  }

  if ($package =~ /FHEM::$type/x || $package eq $type) {                                    # es wird mit Packages gearbeitet -> mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
      return $v;
  }

return;
}

#############################################################################################
#  sortiert Versionsnummern: sortVersion ("asc"|"desc", @versions)
#############################################################################################
sub sortVersion {
  my ($sseq, @versions) = @_;

  my @sorted = sort { (eval { version->parse ($a) <=> version->parse ($b) }) // ($a cmp $b) } @versions;
  @sorted    = reverse @sorted if(($sseq // 'asc') eq 'desc');

return @sorted;
}


1;

=pod
=encoding utf8
=item helper
=item summary       Module to analyze the memory usage and to find memory leak candidates
=item summary_DE    Modul zur Analyse des Speicherverbrauchs und Speicherleck-Kandidaten

=begin html

<a id="Analyze"></a>
<h3>Analyze</h3>
<ul>
  <b>Note: The process data (rss, pss, private, swap, file descriptors, child processes) are read from <code>/proc</code>. This module is therefore designed for Linux systems.</b><br><br>
  Analyzes the memory usage of the FHEM process: the size of devices and of their parts, of module hashes and of the FHEM core hashes, the process memory,
  timers, file descriptors and child processes. Snapshots can be stored and compared with each other. Structures that grow continuously
  over time are reported as memory leak candidates. The module helps to find the device, the module or the data structure that is responsible for a growing memory consumption. <br>
  Analyze is one of several tools for the care and analysis of the system: <a href="#MemSaver">MemSaver</a> keeps the RAM of FHEM clean and small as far as possible,
  Analyze shows where the memory is used and which module, device or data structure is responsible for its growth, and <a href="#Installer">Installer</a> takes care of
  clean installations and updates of the Perl packages that FHEM modules need, including the prerequisites of this module. <br>
  All measurements run in a separate process (BlockingCall). FHEM is not blocked, and a crash of <code>Devel::Size</code> on a single device does not take FHEM down.
  <br><br>

  <b>Basics</b>
  <ul>
    <li>Analyze only measures and reports, it does not free any memory. To keep the RAM small use <a href="#MemSaver">MemSaver</a>.</li>
    <li>The separate process is a copy of FHEM at the moment of the call. All sizes therefore describe exactly this moment.</li>
    <li>Sizes are counted <b>exclusively</b>: every memory address is counted only once, references to other devices (for example <code>IODev</code>) and to the FHEM core hashes are not followed.
        In contrast to <code>Devel::Size::total_size</code> nothing is counted twice, so the sizes of the devices can be added up. The values are approximations with a deviation of a few percent.</li>
    <li><b>Crash protection:</b> Every key of a device is measured separately, and up to the second level (<code>$defs{device}{key}{subkey}</code>) every entry is measured on its own.
        Sockets, file handles, code references, tied/magic values and file handles stored as plain values are never touched (the report shows how many were not measured).
        Before each object the measuring process writes its path to a small file (<code>fhem_analyze_&lt;name&gt;.trace</code> in the temp directory).
        If <code>Devel::Size</code> crashes, the module reads the last path from this file, reports <i>which object</i> caused it, puts it on the <a href="#Analyze-get-crashList">crash list</a>
        and repeats the job without it (attribute <a href="#Analyze-attr-crashRetries">crashRetries</a>). Objects on the crash list are skipped in all following runs, also after a restart of FHEM.</li>
    <li>The snapshot storage of this module itself is not part of the measurement, otherwise the module would always appear as a growing object.</li>
    <li>The sum of all measured structures is shown as <i>attributed</i>. The remainder of the process size (rss) is shown as <i>not attributable</i>. It consists of the Perl interpreter, loaded program code,
        shared libraries, memory fragmentation and - without <a href="#Analyze-attr-deepScan">deepScan</a> - the file-scope variables of the modules.</li>
    <li>The process size (rss) usually grows after the start of FHEM until the Perl memory is warmed up, and it rarely shrinks afterwards. Snapshots should therefore be taken after some hours of runtime.</li>
    <li><b>private</b>, <b>pss</b> and <b>shared</b> change whenever child processes (BlockingCall) start or end. Use <b>rss</b> for trends and compare the other values only if the number of child processes is equal.</li>
  </ul>
  <br>

  <b>Typical procedure</b>
  <ul>
    <code>set &lt;name&gt; snapshot t0</code><br>
    ... wait some hours ...<br>
    <code>set &lt;name&gt; snapshot t1</code><br>
    <code>get &lt;name&gt; diff t0 t1</code> - what has changed between two snapshots<br>
    <code>get &lt;name&gt; leakCandidates</code> - from 3 snapshots on: objects that grow continuously<br>
    <code>set &lt;name&gt; xHashDetail $defs{myDevice}{helper}</code> - look into a suspicious object<br><br>
    Alternatively, <code>attr &lt;name&gt; autoSnapshot 6</code> creates a snapshot every 6 hours automatically.
  </ul>
  <br>

  <b>Prerequisites</b>
  <ul>
    <li><code>Devel::Size</code> - mandatory. Without this module no device can be defined.</li>
    <li>Optional: <code>PadWalker</code> - with it <a href="#Analyze-attr-deepScan">deepScan</a> also measures the file-scope <code>my</code> variables of the module files.
        Whether it is available is shown in the internal <b>PADWALKER</b>.</li>
    <li>The perl modules <code>Storable</code>, <code>MIME::Base64</code>, <code>Scalar::Util</code>, <code>Time::HiRes</code>, <code>POSIX</code> and <code>B</code> (all part of Perl) and the FHEM module <code>Blocking</code>.</li>
  </ul>
  <br>

  <b>Installation of the Perl modules</b>
  <ul>
    The easiest way is the module <a href="#Installer">Installer</a>. The prerequisites of this module are part of its metadata, so the Installer finds out what is missing and installs it:
    <ul>
      <li><code>get &lt;installer&gt; checkPrereqs Analyze</code> lists the missing Perl packages. In FHEMWEB a missing package can be installed with the "Install" link.</li>
      <li>Alternatively: <code>set &lt;installer&gt; installPerl Devel::Size PadWalker</code></li>
    </ul>
    The Installer builds the packages with <code>cpanm</code>. <code>Devel::Size</code> and <code>PadWalker</code> contain compiled code, so a C compiler and <code>make</code> are required
    (Debian/Ubuntu: <code>sudo apt install build-essential</code>). The prerequisites of the Installer itself are described in its help.<br><br>
    <b>Fallback</b> without the Installer (Debian/Ubuntu): <code>sudo apt install libdevel-size-perl</code> and optionally <code>sudo apt install libpadwalker-perl</code>.
  </ul>
  <br>

  <a id="Analyze-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Analyze</code><br><br>
    Example: <code>define anaData Analyze</code><br><br>
    When the device is created interactively, the attribute <code>room</code> is set to <b>SYSTEM</b>. A single instance is sufficient.
    After the definition the cheap periodic sampling of the process size starts (see attribute <a href="#Analyze-attr-sampleInterval">sampleInterval</a>).
    The snapshots are kept in the memory of FHEM and are lost when FHEM is restarted.
  </ul>
  <br>

  <a id="Analyze-set"></a>
  <b>Set</b>
  <ul>
    Measurements run in the background in a separate process. While a job is running, <b>state</b> shows <code>running: &lt;job&gt;</code> and the internal <b>JOB</b> names the job.
    Only one job can run at a time. When the job has finished, the result is shown in FHEMWEB (unless the attribute <a href="#Analyze-attr-noOutput">noOutput</a> is set),
    the readings are updated and the text can be displayed again with <code>get &lt;name&gt; lastResult</code>.
    <br><br>

    <a id="Analyze-set-snapshot"></a>
    <li><b>snapshot [&lt;label&gt;]</b><br>
        Takes a snapshot of the whole system: all devices (with their parts), module hashes, FHEM core hashes, process memory, timers and counters. With the attribute <a href="#Analyze-attr-deepScan">deepScan</a>
        also package variables and file-scope variables of the modules are included. The snapshot is stored under the label and a report is shown.
        The label may consist of letters, digits, <code>_</code>, <code>-</code> and <code>.</code>. Without a label <code>snap_&lt;date&gt;_&lt;time&gt;</code> is used. An existing snapshot with the same label is replaced,
        if more than <a href="#Analyze-attr-maxSnapshots">maxSnapshots</a> exist, the oldest one is deleted.<br>
        <br>
        Example: <code>set anaData snapshot t0</code>
    </li>
    <br>

    <a id="Analyze-set-deleteSnapshot"></a>
    <li><b>deleteSnapshot &lt;label&gt;|all</b><br>
        Deletes one snapshot or all snapshots.
    </li>
    <br>

    <a id="Analyze-set-allDevices"></a>
    <li><b>allDevices</b><br>
        Measures all devices and shows the sizes per device type, device and part of a device. The result is not stored as a snapshot. The readings <b>*_largestObject</b>, <b>*_largestDevice</b>
        and <b>*_largestType</b> are updated.
    </li>
    <br>

    <a id="Analyze-set-deviceType"></a>
    <li><b>deviceType &lt;TYPE&gt;</b><br>
        Like <b>allDevices</b>, but only for the devices of one module type. A regular expression is allowed.<br>
        <br>
        Example: <code>set anaData deviceType HTTPMOD</code>
    </li>
    <br>

    <a id="Analyze-set-xHashDetail"></a>
    <li><b>xHashDetail &lt;object&gt;</b><br>
        Shows the size of an object and of its substructures as a tree: size, share of the whole object, type and number of entries. The object is given as a path:
        <code>$defs{myDevice}{helper}</code>, <code>$data{SolCast6}</code>, <code>$modules{SolarForecast}</code> or with an array index <code>$data{x}[2]</code>.
        The leading <code>$</code> is optional, blanks are ignored. All hashes and arrays of FHEM can be addressed, for example <code>$defs</code>, <code>$data</code>, <code>$attr</code>, <code>$cmds</code>, <code>$intAt</code>.
        If no argument is given, the object from the attribute <a href="#Analyze-attr-analyzeObject">analyzeObject</a> is used.<br>
        The depth of the tree is set by <a href="#Analyze-attr-treeDepth">treeDepth</a>, the number of entries shown per level by <a href="#Analyze-attr-topNum">topNum</a>.
        The readings <b>*_largestObject</b> contain the largest direct substructures with their complete path, which can be copied directly into a further <b>xHashDetail</b>.<br>
        <br>
        Example: <code>set anaData xHashDetail $data{SolCast6}</code>
    </li>
    <br>

    <a id="Analyze-set-mainHash"></a>
    <li><b>mainHash &lt;object&gt;</b><br>
        Works exactly like <b>xHashDetail</b>. The drop-down list offers the core hashes of FHEM that exist in the running system.
    </li>
    <br>

    <a id="Analyze-set-abortJob"></a>
    <li><b>abortJob</b><br>
        Aborts a running job.
    </li>
    <br>

    <a id="Analyze-set-clearCrashList"></a>
    <li><b>clearCrashList &lt;object&gt;|all</b><br>
        Removes an object (as shown by <b>get crashList</b>) or all objects from the crash list. They are measured again in the next run.
        Useful after the cause of a crash was fixed, for example after a module update.<br>
        <br>
        Example: <code>set anaData clearCrashList $defs{myDevice}{helper}{big}</code>
    </li>
  </ul>
  <br>

  <a id="Analyze-get"></a>
  <b>Get</b>
  <ul>
    The explanations and hints in the outputs are shown in German if the global attribute <b>language</b> is <b>DE</b>, otherwise in English. Table headings and object names are always English.<br><br>
    <a id="Analyze-get-snapshots"></a>
    <li><b>snapshots</b><br>
        Lists the stored snapshots with time, process size, attributed memory and the number of devices, timers, file descriptors and child processes.
    </li>
    <br>

    <a id="Analyze-get-report"></a>
    <li><b>report [&lt;label&gt;]</b><br>
        Shows the report of a snapshot, by default of the latest one. The report contains the process memory, the counters, the share of the attributed memory
        and the largest device types, devices, parts of devices, core hashes, module hashes, variables, devices with the most readings and the timers by function.
    </li>
    <br>

    <a id="Analyze-get-diff"></a>
    <li><b>diff [&lt;label1&gt; [&lt;label2&gt;]]</b><br>
        Compares two snapshots and lists the growth of the process memory (also per hour), of the counters and of all measured objects.
        Without a label the last two snapshots are compared, with one label this snapshot is compared with the latest one.<br>
        <br>
        Example: <code>get anaData diff t0 t1</code>
    </li>
    <br>

    <a id="Analyze-get-leakCandidates"></a>
    <li><b>leakCandidates</b><br>
        Evaluates all stored snapshots (at least 3). Listed are objects that grow in at least 75% of the intervals, never shrink and whose total growth reaches a minimum
        (<a href="#Analyze-attr-leakMinBytes">leakMinBytes</a> for sizes). For each object the values of all snapshots and the growth per hour are shown. The more snapshots at larger intervals exist, the more reliable the result is.<br>
        How the result can be read:
        <ul>
          <li><b>part, dev, type</b> - data inside a device grows (readings, helper hashes, queues, caches). Look into the object with <b>xHashDetail</b>.</li>
          <li><b>var, pkgvar, file, pkg</b> - global or file-scope variables of a module grow (requires <a href="#Analyze-attr-deepScan">deepScan</a>, file-scope variables also PadWalker).</li>
          <li><b>timer, timerdev</b> - timers pile up, a module sets timers without removing old ones.</li>
          <li><b>cnt fds, kids</b> - file descriptors or child processes are not released.</li>
          <li><b>track, trackn</b> - a tracked object (attribute <a href="#Analyze-attr-trackObjects">trackObjects</a>) grows in size or in number of entries. Details with <a href="#Analyze-get-track">get track</a>.</li>
          <li><b>proc unattributed</b> grows, but no structure does - memory outside of the measured structures (C libraries, fragmentation, file-scope variables without deepScan).</li>
        </ul>
    </li>
    <br>

    <a id="Analyze-get-timers"></a>
    <li><b>timers</b><br>
        Shows the current timers grouped by function and the devices with the most timers.
    </li>
    <br>

    <a id="Analyze-get-process"></a>
    <li><b>process</b><br>
        Shows the current process memory (rss, peak, anonymous memory, pss, private, shared, swap) and the counters (devices, timers, file descriptors, child processes, selectlist, readyfnlist).
    </li>
    <br>

    <a id="Analyze-get-rssTrend"></a>
    <li><b>rssTrend</b><br>
        Shows the slope of the process size in kB per hour for the last 1, 6, 24 and 72 hours. The values come from the periodic samples (see <a href="#Analyze-attr-sampleInterval">sampleInterval</a>),
        at least 6 samples are required per period. The trend only shows <i>that</i> memory grows, snapshots show <i>where</i>.
    </li>
    <br>

    <a id="Analyze-get-lastResult"></a>
    <li><b>lastResult</b><br>
        Shows the output of the last job again.
    </li>
    <br>

    <a id="Analyze-get-crashList"></a>
    <li><b>crashList</b><br>
        Shows the objects that crashed the measuring process, with time and cause. These objects are skipped in all measurements. The list is kept over a restart of FHEM.
        When a job crashes, the path of the object that was measured at that moment is added automatically.
    </li>
    <br>

    <a id="Analyze-get-track"></a>
    <li><b>track [all | &lt;object&gt;] [&lt;rows&gt;]</b><br>
        Shows the history of the objects that are tracked with the attribute <a href="#Analyze-attr-trackObjects">trackObjects</a>.
        Without argument (or with <b>all</b>) an overview with the last size, the number of entries, the change and the change per hour over the whole recorded period is shown.
        With the path of an object from the attribute every recorded sample is listed with the difference to the previous one. <b>&lt;rows&gt;</b> limits the output to the latest samples (default: 40).<br>
        The drop-down list offers <b>all</b> and every object of the attribute, followed by a text field for <b>&lt;rows&gt;</b>. In the list the colons of package and file-scope paths are replaced by "/" (e.g. <code>93_DbLog.pm/%cache</code>), because the colon is a separator in the FHEMWEB widget syntax. On the command line the original notation is accepted as well.<br>
        The values are recorded with every snapshot (manual or by <a href="#Analyze-attr-autoSnapshot">autoSnapshot</a>). The history is kept in memory (see <a href="#Analyze-attr-trackMaxSamples">trackMaxSamples</a>) and is empty again after a restart of FHEM.
        For a long-term evaluation the readings <b>track_&lt;object&gt;_bytes</b> and <b>track_&lt;object&gt;_count</b> can be logged and plotted.
    </li>
  </ul>
  <br>

  <a id="Analyze-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="Analyze-attr-analyzeObject"></a>
    <li><b>analyzeObject &lt;object&gt;</b> <br>
    Object that is analyzed by <b>xHashDetail</b> if no argument is given, for example <code>$data{SolCast6}</code>.
    </li>
    <br>

    <a id="Analyze-attr-autoSnapshot"></a>
    <li><b>autoSnapshot &lt;hours&gt;</b> <br>
    Creates a snapshot automatically at this interval (in hours, decimals are allowed). The labels are <code>auto_&lt;date&gt;_&lt;time&gt;</code>.
    If a job is still running at that time, the snapshot is skipped. The oldest snapshots are deleted according to <a href="#Analyze-attr-maxSnapshots">maxSnapshots</a>. <br>
    (default: 0, off)
    </li>
    <br>

    <a id="Analyze-attr-crashRetries"></a>
    <li><b>crashRetries &lt;number&gt;</b> <br>
    Number of automatic repetitions of a job after a crash of the measuring process. The object that caused the crash is put on the crash list and skipped in the repetition.
    With 0 the job is not repeated, the object is still put on the crash list. <br>
    (default: 3)
    </li>
    <br>

    <a id="Analyze-attr-deepScan"></a>
    <li><b>deepScan 0 | 1</b> <br>
    With <b>1</b> snapshots additionally contain the package variables (<code>our</code>) of all <code>FHEM::*</code> packages and, if <code>PadWalker</code> is installed, the file-scope <code>my</code> variables
    of the FHEM module files. This is useful if the growth is not found in the devices. The snapshot takes longer and the separate process needs more memory. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-disable"></a>
    <li><b>disable 0 | 1</b> <br>
    Disables the device. A running job is aborted, the timers and the readings are removed, <b>state</b> is <b>disabled</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-excludeTypes"></a>
    <li><b>excludeTypes &lt;TYPE1,TYPE2,...&gt;</b> <br>
    Comma-separated list of module types whose devices are not measured. No type is excluded by default.
    Normally not needed: if a measurement crashes, the module finds the responsible object itself and skips it (see crash protection). Use this attribute to exclude whole device types from the beginning. <br>
    (default: empty)
    </li>
    <br>

    <a id="Analyze-attr-forkTimeout"></a>
    <li><b>forkTimeout &lt;seconds&gt;</b> <br>
    Timeout of the separate process. <br>
    (default: 1800)
    </li>
    <br>

    <a id="Analyze-attr-largeObjectNum"></a>
    <li><b>largeObjectNum &lt;number&gt;</b> <br>
    Number of the readings <b>*_largestObject</b>, <b>*_largestDevice</b> and <b>*_largestType</b>. <br>
    (default: 5)
    </li>
    <br>

    <a id="Analyze-attr-leakMinBytes"></a>
    <li><b>leakMinBytes &lt;bytes&gt;</b> <br>
    Minimum growth in bytes that an object must reach to be listed by <b>leakCandidates</b>. <br>
    (default: 2048)
    </li>
    <br>

    <a id="Analyze-attr-maxNodes"></a>
    <li><b>maxNodes &lt;number&gt;</b> <br>
    Safety limit for the number of objects that are walked in one job. When the limit is reached, the job stops and the sizes are marked as incomplete.
    The separate process needs memory for every walked object, so reduce the value on small systems (for example a Raspberry Pi with little RAM). <br>
    (default: 3000000)
    </li>
    <br>

    <a id="Analyze-attr-maxSnapshots"></a>
    <li><b>maxSnapshots &lt;number&gt;</b> <br>
    Number of snapshots that are kept in memory. If more are created, the oldest one is deleted. <br>
    (default: 10)
    </li>
    <br>

    <a id="Analyze-attr-noOutput"></a>
    <li><b>noOutput 0 | 1</b> <br>
    With <b>1</b> the result of a job is not shown in FHEMWEB. The readings are still updated and <b>get &lt;name&gt; lastResult</b> shows the text. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-sampleInterval"></a>
    <li><b>sampleInterval &lt;seconds&gt;</b> <br>
    Interval of the cheap sampling of the process size from <code>/proc</code> (no separate process). The readings <b>proc_rss_kB</b>, <b>proc_rssPeak_kB</b> and <b>proc_rssTrend_kBperHour</b> are updated
    and <b>get rssTrend</b> is based on these values. Allowed are 0 (off) or at least 60. <br>
    (default: 600)
    </li>
    <br>

    <a id="Analyze-attr-topNum"></a>
    <li><b>topNum &lt;number&gt;</b> <br>
    Number of entries per section in reports and per level in the tree of <b>xHashDetail</b>. <br>
    (default: 15)
    </li>
    <br>

    <a id="Analyze-attr-trackMaxSamples"></a>
    <li><b>trackMaxSamples &lt;number&gt;</b> <br>
    Maximum number of samples that are kept per object tracked with <a href="#Analyze-attr-trackObjects">trackObjects</a>. The oldest sample is dropped first. <br>
    (default: 500)
    </li>
    <br>

    <a id="Analyze-attr-trackObjects"></a>
    <li><b>trackObjects &lt;object&gt; [&lt;object&gt; ...]</b> <br>
    List of objects (separated by blank or comma, keys must not contain blanks or commas) whose size and number of entries are recorded with every snapshot, so that their growth can be evaluated over a longer period (<a href="#Analyze-get-track">get track</a>).
    Allowed are:
    <ul>
      <li><code>$defs{myDevice}{.pvHistCache}</code>, <code>$data{x}{y}[2]</code> - hashes and arrays of the FHEM main level (same syntax as <b>xHashDetail</b>)</li>
      <li><code>%FHEM::Module::cache</code>, <code>@Package::list</code>, <code>$Package::value</code> - package variables (<code>our</code>), optionally followed by <code>{key}</code> or <code>[index]</code></li>
      <li><code>93_DbLog.pm:%cache</code> - file-scope <code>my</code> variable of a module file (requires <code>PadWalker</code>, the variable must be used by at least one function of the file)</li>
    </ul>
    Neither <a href="#Analyze-attr-deepScan">deepScan</a> nor a snapshot with deep scan is required, for file-scope variables only the named file is searched.
    Every object is measured on its own, so its size is complete and independent of other objects. The sizes are <b>not</b> part of the attributed memory, otherwise they would be counted twice.
    Objects that cannot be found are listed in the snapshot report. They are also evaluated by <b>diff</b> and <b>leakCandidates</b>.<br>
    The readings <b>track_&lt;object&gt;_bytes</b> and <b>track_&lt;object&gt;_count</b> are created for each object. The name is derived from the path, for example
    <code>track_defs_myDevice_pvHistCache_bytes</code>. <br>
    <br>
    Example: <code>attr &lt;name&gt; trackObjects $defs{VictronVRM}{.pvHistCache} 93_DbLog.pm:%cache</code>
    </li>
    <br>

    <a id="Analyze-attr-treeDepth"></a>
    <li><b>treeDepth &lt;number&gt;</b> <br>
    Depth of the tree shown by <b>xHashDetail</b> and <b>mainHash</b>. Deeper levels are included in the sizes but not shown. <br>
    (default: 3)
    </li>
    <br>

    <a id="Analyze-attr-useFork"></a>
    <li><b>useFork 0 | 1</b> <br>
    With <b>0</b> the measurement runs inside the FHEM process. FHEM is blocked while it is running, and a crash of <code>Devel::Size</code> takes FHEM down.
    The breadcrumb file survives, so after the restart the module recognizes the unfinished analysis and puts the object that caused the crash on the crash list.
    Only useful if no separate process can be started ("Cannot fork"). <br>
    (default: 1)
    </li>
  </ul>
  <br>

  <a id="Analyze-Readings"></a>
  <b>Readings</b>
  <ul>
    Readings that belong to a snapshot or to the periodic sampling are removed when FHEM starts, because the snapshots and samples only exist in memory. Only <b>state</b>, <b>crashListCount</b>, <b>snapshots</b> and <b>snapshot_last</b> are set again, all others are created by the next measurement.<br><br>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>NN_largestObject</b>          </td><td>the largest objects, format <code>&lt;size in bytes&gt;, &lt;object&gt;</code>, for example <code>1048576, $data{SolCast6}</code>. The object can be copied into <b>xHashDetail</b>.     </td></tr>
      <tr><td> <b>NN_largestDevice</b>          </td><td>the largest devices, format <code>&lt;size in bytes&gt;, &lt;device&gt;</code>                                                                                                     </td></tr>
      <tr><td> <b>NN_largestType</b>            </td><td>the largest device types (sum of all devices of the type), format <code>&lt;size in bytes&gt;, &lt;TYPE&gt;</code>                                                                  </td></tr>
      <tr><td> <b>attributed_kB</b>             </td><td>memory in kB that belongs to measured FHEM structures (last snapshot)                                                                                                               </td></tr>
      <tr><td> <b>crashListCount</b>            </td><td>number of objects on the crash list                                                                                                                                                  </td></tr>
      <tr><td> <b>count_defs</b>                </td><td>number of devices (last snapshot)                                                                                                                                                  </td></tr>
      <tr><td> <b>count_fds</b>                 </td><td>number of open file descriptors (last snapshot)                                                                                                                                     </td></tr>
      <tr><td> <b>count_kids</b>                </td><td>number of child processes (last snapshot)                                                                                                                                           </td></tr>
      <tr><td> <b>count_timers</b>              </td><td>number of timers (last snapshot)                                                                                                                                                    </td></tr>
      <tr><td> <b>proc_pss_kB</b>               </td><td>proportional set size in kB (last snapshot)                                                                                                                                         </td></tr>
      <tr><td> <b>proc_private_kB</b>           </td><td>private memory in kB (last snapshot)                                                                                                                                                </td></tr>
      <tr><td> <b>proc_rss_kB</b>               </td><td>resident set size of the FHEM process in kB (last snapshot or sample)                                                                                                               </td></tr>
      <tr><td> <b>proc_rssPeak_kB</b>           </td><td>highest resident set size since the start of FHEM in kB (last sample)                                                                                                               </td></tr>
      <tr><td> <b>proc_rssTrend_kBperHour</b>   </td><td>slope of the resident set size over the last 24 hours in kB per hour (last sample, at least 6 samples are required)                                                                  </td></tr>
      <tr><td> <b>proc_swap_kB</b>              </td><td>swapped memory in kB (last snapshot)                                                                                                                                                </td></tr>
      <tr><td> <b>snapshot_last</b>             </td><td>label of the latest snapshot                                                                                                                                                        </td></tr>
      <tr><td> <b>snapshots</b>                 </td><td>number of stored snapshots                                                                                                                                                          </td></tr>
      <tr><td> <b>track_&lt;object&gt;_bytes</b> </td><td>size in bytes of an object tracked with <b>trackObjects</b> (last snapshot)                                                                                                       </td></tr>
      <tr><td> <b>track_&lt;object&gt;_count</b> </td><td>number of entries of an object tracked with <b>trackObjects</b> (last snapshot)                                                                                                    </td></tr>
      <tr><td> <b>unattributed_kB</b>           </td><td>part of the process size that cannot be attributed to measured structures (interpreter, program code, libraries, fragmentation, without deepScan also file-scope variables)            </td></tr>
      <tr><td> <b>state</b>                     </td><td>current state of the module. Possible values:                                                                                                                                       </td></tr>
      <tr><td>                                  </td><td><ul><b>Initialized</b> - the device was created                                                  </ul>                                                                        </td></tr>
      <tr><td>                                  </td><td><ul><b>running: &lt;job&gt;</b> - a job (snapshot, devices, tree) is running in the background    </ul>                                                                        </td></tr>
      <tr><td>                                  </td><td><ul><b>done</b> - the last job has finished successfully                                         </ul>                                                                        </td></tr>
      <tr><td>                                  </td><td><ul><b>aborted</b> - the job was aborted with <b>abortJob</b>                                    </ul>                                                                        </td></tr>
      <tr><td>                                  </td><td><ul><b>error</b> - the job failed, details in <code>get &lt;name&gt; lastResult</code> and in the Log </ul>                                                                    </td></tr>
      <tr><td>                                  </td><td><ul><b>error: crashed at &lt;object&gt;</b> - the measuring process crashed while measuring this object, details in <code>get &lt;name&gt; lastResult</code> </ul>                  </td></tr>
      <tr><td>                                  </td><td><ul><b>error: &lt;cause&gt;</b> - the background process was aborted, for example by the timeout </ul>                                                                        </td></tr>
      <tr><td>                                  </td><td><ul><b>disabled</b> - the device is disabled by <b>disable</b>                                   </ul>                                                                        </td></tr>
    </table>
  </ul>

</ul>

=end html

=begin html_DE

<a id="Analyze"></a>
<h3>Analyze</h3>
<ul>
  <b>Hinweis: Die Prozessdaten (rss, pss, private, swap, Filedeskriptoren, Kindprozesse) werden aus <code>/proc</code> gelesen. Das Modul ist deshalb für Linux-Systeme ausgelegt.</b><br><br>
  Analysiert den Speicherverbrauch des FHEM-Prozesses: die Größe von Devices und ihrer Teilstrukturen, von Modul-Hashes und von den Kern-Hashes von FHEM, den Prozessspeicher,
  Timer, Filedeskriptoren und Kindprozesse. Snapshots können gespeichert und miteinander verglichen werden. Strukturen, die über die Zeit kontinuierlich wachsen,
  werden als Speicherleck-Kandidaten gemeldet. Das Modul hilft dabei, das Device, das Modul oder die Datenstruktur zu finden, die für einen wachsenden Speicherverbrauch verantwortlich ist. <br>
  Analyze ist einer von mehreren Bausteinen für die Systempflege und Analyse: <a href="#MemSaver">MemSaver</a> hält den RAM von FHEM so weit wie möglich sauber und klein,
  Analyze zeigt, wo der Speicher verwendet wird und welches Modul, Device oder welche Datenstruktur für sein Wachstum verantwortlich ist, und <a href="#Installer">Installer</a> sorgt für
  saubere Installationen und Updates der Perl-Pakete, die FHEM-Module benötigen, einschließlich der Voraussetzungen dieses Moduls. <br>
  Alle Messungen laufen in einem eigenen Prozess (BlockingCall). FHEM wird nicht blockiert, und ein Absturz von <code>Devel::Size</code> bei einem einzelnen Device reißt FHEM nicht mit.
  <br><br>

  <b>Grundlagen</b>
  <ul>
    <li>Analyze misst und berichtet nur, es gibt keinen Speicher frei. Um den RAM klein zu halten, dient <a href="#MemSaver">MemSaver</a>.</li>
    <li>Der eigene Prozess ist eine Kopie von FHEM zum Zeitpunkt des Aufrufs. Alle Größen beschreiben deshalb genau diesen Zeitpunkt.</li>
    <li>Größen werden <b>exklusiv</b> gezählt: Jede Speicheradresse wird nur einmal gezählt, Referenzen auf andere Devices (zum Beispiel <code>IODev</code>) und auf die Kern-Hashes von FHEM werden nicht verfolgt.
        Anders als bei <code>Devel::Size::total_size</code> wird nichts doppelt gezählt, die Größen der Devices lassen sich also addieren. Die Werte sind Näherungen mit wenigen Prozent Abweichung.</li>
    <li><b>Crash-Schutz:</b> Jeder Schlüssel eines Devices wird einzeln gemessen, bis zur zweiten Ebene (<code>$defs{device}{key}{subkey}</code>) sogar jeder Eintrag für sich.
        Sockets, Dateihandles, Code-Referenzen, tied/Magic-Werte und als einfache Werte abgelegte Dateihandles werden nie angefasst (der Bericht zeigt, wie viele nicht gemessen wurden).
        Vor jedem Objekt schreibt der Messprozess dessen Pfad in eine kleine Datei (<code>fhem_analyze_&lt;name&gt;.trace</code> im Temp-Verzeichnis).
        Stürzt <code>Devel::Size</code> ab, liest das Modul den letzten Pfad aus dieser Datei, meldet, <i>welches Objekt</i> die Ursache war, nimmt es in die <a href="#Analyze-get-crashList">Crash-Liste</a> auf
        und wiederholt den Job ohne dieses Objekt (Attribut <a href="#Analyze-attr-crashRetries">crashRetries</a>). Objekte der Crash-Liste werden in allen folgenden Läufen übersprungen, auch nach einem Neustart von FHEM.</li>
    <li>Die Snapshot-Ablage des Moduls selbst wird nicht mitgemessen, sonst würde das Modul immer als wachsendes Objekt erscheinen.</li>
    <li>Die Summe aller gemessenen Strukturen wird als <i>attributed</i> (zugeordnet) ausgewiesen. Der Rest der Prozessgröße (rss) erscheint als <i>not attributable</i> (nicht zuordenbar). Er besteht aus dem Perl-Interpreter, geladenem Programmcode,
        Shared Libraries, Speicherfragmentierung und - ohne <a href="#Analyze-attr-deepScan">deepScan</a> - den file-scope Variablen der Module.</li>
    <li>Die Prozessgröße (rss) wächst nach dem Start von FHEM üblicherweise, bis der Perl-Speicher "warmgelaufen" ist, und schrumpft danach selten. Snapshots sollten deshalb nach einigen Stunden Laufzeit erstellt werden.</li>
    <li><b>private</b>, <b>pss</b> und <b>shared</b> ändern sich immer dann, wenn Kindprozesse (BlockingCall) starten oder enden. Für Trends wird <b>rss</b> verwendet, die anderen Werte sind nur bei gleicher Anzahl Kindprozesse vergleichbar.</li>
  </ul>
  <br>

  <b>Typischer Ablauf</b>
  <ul>
    <code>set &lt;name&gt; snapshot t0</code><br>
    ... einige Stunden warten ...<br>
    <code>set &lt;name&gt; snapshot t1</code><br>
    <code>get &lt;name&gt; diff t0 t1</code> - was hat sich zwischen zwei Snapshots verändert<br>
    <code>get &lt;name&gt; leakCandidates</code> - ab 3 Snapshots: Objekte, die kontinuierlich wachsen<br>
    <code>set &lt;name&gt; xHashDetail $defs{myDevice}{helper}</code> - ein auffälliges Objekt genauer ansehen<br><br>
    Alternativ erstellt <code>attr &lt;name&gt; autoSnapshot 6</code> automatisch alle 6 Stunden einen Snapshot.
  </ul>
  <br>

  <b>Voraussetzungen</b>
  <ul>
    <li><code>Devel::Size</code> - zwingend erforderlich. Ohne dieses Modul kann kein Device angelegt werden.</li>
    <li>Optional: <code>PadWalker</code> - damit erfasst <a href="#Analyze-attr-deepScan">deepScan</a> auch die file-scope <code>my</code> Variablen der Modul-Dateien.
        Ob es verfügbar ist, zeigt das Internal <b>PADWALKER</b>.</li>
    <li>Die Perl-Module <code>Storable</code>, <code>MIME::Base64</code>, <code>Scalar::Util</code>, <code>Time::HiRes</code>, <code>POSIX</code> und <code>B</code> (alle Bestandteil von Perl) sowie das FHEM-Modul <code>Blocking</code>.</li>
  </ul>
  <br>

  <b>Installation der Perl-Module</b>
  <ul>
    Am einfachsten geht es mit dem Modul <a href="#Installer">Installer</a>. Die Voraussetzungen dieses Moduls stehen in seinen Metadaten, der Installer findet daher selbst heraus, was fehlt, und installiert es:
    <ul>
      <li><code>get &lt;installer&gt; checkPrereqs Analyze</code> listet die fehlenden Perl-Pakete auf. In FHEMWEB kann ein fehlendes Paket über den Link "Install" installiert werden.</li>
      <li>Alternativ: <code>set &lt;installer&gt; installPerl Devel::Size PadWalker</code></li>
    </ul>
    Der Installer baut die Pakete mit <code>cpanm</code>. <code>Devel::Size</code> und <code>PadWalker</code> enthalten kompilierten Code, daher werden ein C-Compiler und <code>make</code> benötigt
    (Debian/Ubuntu: <code>sudo apt install build-essential</code>). Die Voraussetzungen des Installers selbst stehen in dessen Hilfe.<br><br>
    <b>Fallback</b> ohne Installer (Debian/Ubuntu): <code>sudo apt install libdevel-size-perl</code> und optional <code>sudo apt install libpadwalker-perl</code>.
  </ul>
  <br>

  <a id="Analyze-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Analyze</code><br><br>
    Beispiel: <code>define anaData Analyze</code><br><br>
    Beim interaktiven Anlegen des Devices wird das Attribut <code>room</code> auf <b>SYSTEM</b> gesetzt. Eine einzelne Instanz genügt.
    Nach dem Define startet die günstige periodische Messung der Prozessgröße (siehe Attribut <a href="#Analyze-attr-sampleInterval">sampleInterval</a>).
    Die Snapshots liegen im Speicher von FHEM und gehen bei einem Neustart von FHEM verloren.
  </ul>
  <br>

  <a id="Analyze-set"></a>
  <b>Set</b>
  <ul>
    Messungen laufen im Hintergrund in einem eigenen Prozess. Während ein Job läuft, zeigt <b>state</b> <code>running: &lt;Job&gt;</code> und das Internal <b>JOB</b> nennt den Job.
    Es kann nur ein Job gleichzeitig laufen. Ist der Job fertig, wird das Ergebnis in FHEMWEB angezeigt (außer das Attribut <a href="#Analyze-attr-noOutput">noOutput</a> ist gesetzt),
    die Readings werden aktualisiert und der Text kann mit <code>get &lt;name&gt; lastResult</code> erneut angezeigt werden.
    <br><br>

    <a id="Analyze-set-snapshot"></a>
    <li><b>snapshot [&lt;Label&gt;]</b><br>
        Erstellt einen Snapshot des gesamten Systems: alle Devices (mit ihren Teilstrukturen), Modul-Hashes, Kern-Hashes von FHEM, Prozessspeicher, Timer und Zähler. Mit dem Attribut <a href="#Analyze-attr-deepScan">deepScan</a>
        werden zusätzlich Paketvariablen und file-scope Variablen der Module erfasst. Der Snapshot wird unter dem Label gespeichert und ein Bericht angezeigt.
        Das Label darf aus Buchstaben, Ziffern, <code>_</code>, <code>-</code> und <code>.</code> bestehen. Ohne Label wird <code>snap_&lt;Datum&gt;_&lt;Zeit&gt;</code> verwendet. Ein vorhandener Snapshot mit gleichem Label wird ersetzt,
        gibt es mehr als <a href="#Analyze-attr-maxSnapshots">maxSnapshots</a>, wird der älteste gelöscht.<br>
        <br>
        Beispiel: <code>set anaData snapshot t0</code>
    </li>
    <br>

    <a id="Analyze-set-deleteSnapshot"></a>
    <li><b>deleteSnapshot &lt;Label&gt;|all</b><br>
        Löscht einen Snapshot oder alle Snapshots.
    </li>
    <br>

    <a id="Analyze-set-allDevices"></a>
    <li><b>allDevices</b><br>
        Misst alle Devices und zeigt die Größen je Device-Typ, Device und Teil eines Devices. Das Ergebnis wird nicht als Snapshot gespeichert. Die Readings <b>*_largestObject</b>, <b>*_largestDevice</b>
        und <b>*_largestType</b> werden aktualisiert.
    </li>
    <br>

    <a id="Analyze-set-deviceType"></a>
    <li><b>deviceType &lt;TYPE&gt;</b><br>
        Wie <b>allDevices</b>, aber nur für die Devices eines Modultyps. Ein regulärer Ausdruck ist erlaubt.<br>
        <br>
        Beispiel: <code>set anaData deviceType HTTPMOD</code>
    </li>
    <br>

    <a id="Analyze-set-xHashDetail"></a>
    <li><b>xHashDetail &lt;Objekt&gt;</b><br>
        Zeigt die Größe eines Objekts und seiner Unterstrukturen als Baum: Größe, Anteil am Gesamtobjekt, Typ und Anzahl der Einträge. Das Objekt wird als Pfad angegeben:
        <code>$defs{myDevice}{helper}</code>, <code>$data{SolCast6}</code>, <code>$modules{SolarForecast}</code> oder mit Array-Index <code>$data{x}[2]</code>.
        Das führende <code>$</code> ist optional, Leerzeichen werden ignoriert. Alle Hashes und Arrays von FHEM sind ansprechbar, zum Beispiel <code>$defs</code>, <code>$data</code>, <code>$attr</code>, <code>$cmds</code>, <code>$intAt</code>.
        Ohne Angabe wird das Objekt aus dem Attribut <a href="#Analyze-attr-analyzeObject">analyzeObject</a> verwendet.<br>
        Die Tiefe des Baums bestimmt <a href="#Analyze-attr-treeDepth">treeDepth</a>, die Anzahl der gezeigten Einträge pro Ebene <a href="#Analyze-attr-topNum">topNum</a>.
        Die Readings <b>*_largestObject</b> enthalten die größten direkten Unterstrukturen mit vollständigem Pfad, der direkt in ein weiteres <b>xHashDetail</b> kopiert werden kann.<br>
        <br>
        Beispiel: <code>set anaData xHashDetail $data{SolCast6}</code>
    </li>
    <br>

    <a id="Analyze-set-mainHash"></a>
    <li><b>mainHash &lt;Objekt&gt;</b><br>
        Arbeitet genau wie <b>xHashDetail</b>. Die Auswahlliste bietet die Kern-Hashes von FHEM an, die im laufenden System vorhanden sind.
    </li>
    <br>

    <a id="Analyze-set-abortJob"></a>
    <li><b>abortJob</b><br>
        Bricht einen laufenden Job ab.
    </li>
    <br>

    <a id="Analyze-set-clearCrashList"></a>
    <li><b>clearCrashList &lt;Objekt&gt;|all</b><br>
        Entfernt ein Objekt (wie von <b>get crashList</b> angezeigt) oder alle Objekte aus der Crash-Liste. Sie werden im nächsten Lauf wieder gemessen.
        Sinnvoll, nachdem die Ursache eines Absturzes behoben wurde, zum Beispiel nach einem Modul-Update.<br>
        <br>
        Beispiel: <code>set anaData clearCrashList $defs{myDevice}{helper}{big}</code>
    </li>
  </ul>
  <br>

  <a id="Analyze-get"></a>
  <b>Get</b>
  <ul>
    Die Erläuterungen und Hinweise in den Ausgaben erscheinen auf Deutsch, wenn das globale Attribut <b>language</b> den Wert <b>DE</b> hat, sonst auf Englisch. Tabellenköpfe und Objektnamen sind immer englisch.<br><br>
    <a id="Analyze-get-snapshots"></a>
    <li><b>snapshots</b><br>
        Listet die gespeicherten Snapshots mit Zeit, Prozessgröße, zugeordnetem Speicher und der Anzahl der Devices, Timer, Filedeskriptoren und Kindprozesse.
    </li>
    <br>

    <a id="Analyze-get-report"></a>
    <li><b>report [&lt;Label&gt;]</b><br>
        Zeigt den Bericht eines Snapshots, standardmäßig des neuesten. Der Bericht enthält den Prozessspeicher, die Zähler, den Anteil des zugeordneten Speichers
        und die größten Device-Typen, Devices, Teile von Devices, Kern-Hashes, Modul-Hashes, Variablen, Devices mit den meisten Readings sowie die Timer nach Funktion.
    </li>
    <br>

    <a id="Analyze-get-diff"></a>
    <li><b>diff [&lt;Label1&gt; [&lt;Label2&gt;]]</b><br>
        Vergleicht zwei Snapshots und listet das Wachstum des Prozessspeichers (auch je Stunde), der Zähler und aller gemessenen Objekte auf.
        Ohne Label werden die letzten beiden Snapshots verglichen, mit einem Label dieser Snapshot mit dem neuesten.<br>
        <br>
        Beispiel: <code>get anaData diff t0 t1</code>
    </li>
    <br>

    <a id="Analyze-get-leakCandidates"></a>
    <li><b>leakCandidates</b><br>
        Wertet alle gespeicherten Snapshots aus (mindestens 3). Aufgelistet werden Objekte, die in mindestens 75% der Intervalle wachsen, nie schrumpfen und deren Gesamtwachstum ein Minimum erreicht
        (<a href="#Analyze-attr-leakMinBytes">leakMinBytes</a> bei Größen). Zu jedem Objekt werden die Werte aller Snapshots und das Wachstum pro Stunde angezeigt. Je mehr Snapshots in größeren Abständen vorliegen, desto verlässlicher ist das Ergebnis.<br>
        So lässt sich das Ergebnis lesen:
        <ul>
          <li><b>part, dev, type</b> - Daten innerhalb eines Devices wachsen (Readings, Helper-Hashes, Warteschlangen, Caches). Das Objekt mit <b>xHashDetail</b> ansehen.</li>
          <li><b>var, pkgvar, file, pkg</b> - globale oder file-scope Variablen eines Moduls wachsen (setzt <a href="#Analyze-attr-deepScan">deepScan</a> voraus, file-scope Variablen zusätzlich PadWalker).</li>
          <li><b>timer, timerdev</b> - Timer häufen sich an, ein Modul setzt Timer, ohne alte zu entfernen.</li>
          <li><b>cnt fds, kids</b> - Filedeskriptoren oder Kindprozesse werden nicht freigegeben.</li>
          <li><b>track, trackn</b> - ein getracktes Objekt (Attribut <a href="#Analyze-attr-trackObjects">trackObjects</a>) wächst in der Größe oder in der Anzahl der Einträge. Details mit <a href="#Analyze-get-track">get track</a>.</li>
          <li><b>proc unattributed</b> wächst, aber keine Struktur - Speicher außerhalb der gemessenen Strukturen (C-Bibliotheken, Fragmentierung, file-scope Variablen ohne deepScan).</li>
        </ul>
    </li>
    <br>

    <a id="Analyze-get-timers"></a>
    <li><b>timers</b><br>
        Zeigt die aktuellen Timer gruppiert nach Funktion sowie die Devices mit den meisten Timern.
    </li>
    <br>

    <a id="Analyze-get-process"></a>
    <li><b>process</b><br>
        Zeigt den aktuellen Prozessspeicher (rss, Spitzenwert, anonymer Speicher, pss, private, shared, swap) und die Zähler (Devices, Timer, Filedeskriptoren, Kindprozesse, selectlist, readyfnlist).
    </li>
    <br>

    <a id="Analyze-get-rssTrend"></a>
    <li><b>rssTrend</b><br>
        Zeigt die Steigung der Prozessgröße in kB pro Stunde für die letzten 1, 6, 24 und 72 Stunden. Die Werte stammen aus den periodischen Messungen (siehe <a href="#Analyze-attr-sampleInterval">sampleInterval</a>),
        je Zeitraum sind mindestens 6 Messwerte nötig. Der Trend zeigt nur, <i>dass</i> der Speicher wächst, Snapshots zeigen, <i>wo</i>.
    </li>
    <br>

    <a id="Analyze-get-lastResult"></a>
    <li><b>lastResult</b><br>
        Zeigt die Ausgabe des letzten Jobs erneut an.
    </li>
    <br>

    <a id="Analyze-get-crashList"></a>
    <li><b>crashList</b><br>
        Zeigt die Objekte, die den Messprozess zum Absturz gebracht haben, mit Zeit und Ursache. Diese Objekte werden bei allen Messungen übersprungen. Die Liste bleibt über einen Neustart von FHEM erhalten.
        Stürzt ein Job ab, wird der Pfad des Objekts, das in diesem Moment gemessen wurde, automatisch aufgenommen.
    </li>
    <br>

    <a id="Analyze-get-track"></a>
    <li><b>track [all | &lt;Objekt&gt;] [&lt;Zeilen&gt;]</b><br>
        Zeigt den Verlauf der Objekte, die mit dem Attribut <a href="#Analyze-attr-trackObjects">trackObjects</a> getrackt werden.
        Ohne Argument (oder mit <b>all</b>) erscheint eine Übersicht mit der letzten Größe, der Anzahl der Einträge, der Änderung und der Änderung pro Stunde über den gesamten aufgezeichneten Zeitraum.
        Mit dem Pfad eines Objekts aus dem Attribut wird jeder aufgezeichnete Messwert mit der Differenz zum vorherigen aufgelistet. <b>&lt;Zeilen&gt;</b> begrenzt die Ausgabe auf die letzten Messwerte (default: 40).<br>
        Die Auswahlliste bietet <b>all</b> und jedes Objekt des Attributs an, danach folgt ein Textfeld für <b>&lt;Zeilen&gt;</b>. In der Liste sind die Doppelpunkte von Paket- und file-scope-Pfaden durch "/" ersetzt (z.B. <code>93_DbLog.pm/%cache</code>), weil der Doppelpunkt in der Widget-Syntax von FHEMWEB ein Trenner ist. In der Kommandozeile wird auch die Originalschreibweise akzeptiert.<br>
        Die Werte werden mit jedem Snapshot aufgezeichnet (manuell oder durch <a href="#Analyze-attr-autoSnapshot">autoSnapshot</a>). Der Verlauf liegt im Speicher (siehe <a href="#Analyze-attr-trackMaxSamples">trackMaxSamples</a>) und ist nach einem Neustart von FHEM wieder leer.
        Für eine Langzeitauswertung können die Readings <b>track_&lt;Objekt&gt;_bytes</b> und <b>track_&lt;Objekt&gt;_count</b> geloggt und geplottet werden.
    </li>
  </ul>
  <br>

  <a id="Analyze-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="Analyze-attr-analyzeObject"></a>
    <li><b>analyzeObject &lt;Objekt&gt;</b> <br>
    Objekt, das <b>xHashDetail</b> analysiert, wenn kein Argument angegeben wird, zum Beispiel <code>$data{SolCast6}</code>.
    </li>
    <br>

    <a id="Analyze-attr-autoSnapshot"></a>
    <li><b>autoSnapshot &lt;Stunden&gt;</b> <br>
    Erstellt in diesem Abstand (in Stunden, Dezimalzahlen sind erlaubt) automatisch einen Snapshot. Die Labels lauten <code>auto_&lt;Datum&gt;_&lt;Zeit&gt;</code>.
    Läuft zu diesem Zeitpunkt noch ein Job, wird der Snapshot ausgelassen. Die ältesten Snapshots werden entsprechend <a href="#Analyze-attr-maxSnapshots">maxSnapshots</a> gelöscht. <br>
    (default: 0, aus)
    </li>
    <br>

    <a id="Analyze-attr-crashRetries"></a>
    <li><b>crashRetries &lt;Anzahl&gt;</b> <br>
    Anzahl der automatischen Wiederholungen eines Jobs nach einem Absturz des Messprozesses. Das Objekt, das den Absturz verursacht hat, kommt in die Crash-Liste und wird bei der Wiederholung übersprungen.
    Mit 0 wird der Job nicht wiederholt, das Objekt kommt trotzdem in die Crash-Liste. <br>
    (default: 3)
    </li>
    <br>

    <a id="Analyze-attr-deepScan"></a>
    <li><b>deepScan 0 | 1</b> <br>
    Mit <b>1</b> enthalten Snapshots zusätzlich die Paketvariablen (<code>our</code>) aller <code>FHEM::*</code> Pakete und, wenn <code>PadWalker</code> installiert ist, die file-scope <code>my</code> Variablen
    der FHEM-Modul-Dateien. Sinnvoll, wenn das Wachstum nicht in den Devices gefunden wird. Der Snapshot dauert länger und der eigene Prozess braucht mehr Speicher. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-disable"></a>
    <li><b>disable 0 | 1</b> <br>
    Deaktiviert das Device. Ein laufender Job wird abgebrochen, die Timer und die Readings werden entfernt, der <b>state</b> ist <b>disabled</b>. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-excludeTypes"></a>
    <li><b>excludeTypes &lt;TYPE1,TYPE2,...&gt;</b> <br>
    Kommagetrennte Liste von Modultypen, deren Devices nicht gemessen werden. Standardmäßig wird kein Typ ausgeschlossen.
    Normalerweise nicht nötig: Stürzt eine Messung ab, findet das Modul das verantwortliche Objekt selbst und überspringt es (siehe Crash-Schutz). Mit dem Attribut lassen sich ganze Device-Typen von Anfang an ausschließen. <br>
    (default: leer)
    </li>
    <br>

    <a id="Analyze-attr-forkTimeout"></a>
    <li><b>forkTimeout &lt;Sekunden&gt;</b> <br>
    Timeout des eigenen Prozesses. <br>
    (default: 1800)
    </li>
    <br>

    <a id="Analyze-attr-largeObjectNum"></a>
    <li><b>largeObjectNum &lt;Anzahl&gt;</b> <br>
    Anzahl der Readings <b>*_largestObject</b>, <b>*_largestDevice</b> und <b>*_largestType</b>. <br>
    (default: 5)
    </li>
    <br>

    <a id="Analyze-attr-leakMinBytes"></a>
    <li><b>leakMinBytes &lt;Bytes&gt;</b> <br>
    Mindestwachstum in Bytes, das ein Objekt erreichen muss, um von <b>leakCandidates</b> aufgelistet zu werden. <br>
    (default: 2048)
    </li>
    <br>

    <a id="Analyze-attr-maxNodes"></a>
    <li><b>maxNodes &lt;Anzahl&gt;</b> <br>
    Sicherheitsgrenze für die Anzahl der Objekte, die in einem Job durchlaufen werden. Wird die Grenze erreicht, bricht der Job ab und die Größen werden als unvollständig gekennzeichnet.
    Der eigene Prozess benötigt Speicher für jedes durchlaufene Objekt, auf kleinen Systemen (zum Beispiel ein Raspberry Pi mit wenig RAM) sollte der Wert deshalb verkleinert werden. <br>
    (default: 3000000)
    </li>
    <br>

    <a id="Analyze-attr-maxSnapshots"></a>
    <li><b>maxSnapshots &lt;Anzahl&gt;</b> <br>
    Anzahl der Snapshots, die im Speicher gehalten werden. Werden mehr erstellt, wird der älteste gelöscht. <br>
    (default: 10)
    </li>
    <br>

    <a id="Analyze-attr-noOutput"></a>
    <li><b>noOutput 0 | 1</b> <br>
    Mit <b>1</b> wird das Ergebnis eines Jobs nicht in FHEMWEB angezeigt. Die Readings werden trotzdem aktualisiert und <b>get &lt;name&gt; lastResult</b> zeigt den Text. <br>
    (default: 0)
    </li>
    <br>

    <a id="Analyze-attr-sampleInterval"></a>
    <li><b>sampleInterval &lt;Sekunden&gt;</b> <br>
    Intervall der günstigen Messung der Prozessgröße aus <code>/proc</code> (kein eigener Prozess). Die Readings <b>proc_rss_kB</b>, <b>proc_rssPeak_kB</b> und <b>proc_rssTrend_kBperHour</b> werden aktualisiert
    und <b>get rssTrend</b> basiert auf diesen Werten. Erlaubt sind 0 (aus) oder mindestens 60. <br>
    (default: 600)
    </li>
    <br>

    <a id="Analyze-attr-topNum"></a>
    <li><b>topNum &lt;Anzahl&gt;</b> <br>
    Anzahl der Einträge je Abschnitt in Berichten und je Ebene im Baum von <b>xHashDetail</b>. <br>
    (default: 15)
    </li>
    <br>

    <a id="Analyze-attr-trackMaxSamples"></a>
    <li><b>trackMaxSamples &lt;Anzahl&gt;</b> <br>
    Maximale Anzahl der Messwerte, die je Objekt aus <a href="#Analyze-attr-trackObjects">trackObjects</a> gehalten werden. Der älteste Messwert fällt zuerst weg. <br>
    (default: 500)
    </li>
    <br>

    <a id="Analyze-attr-trackObjects"></a>
    <li><b>trackObjects &lt;Objekt&gt; [&lt;Objekt&gt; ...]</b> <br>
    Liste von Objekten (getrennt durch Leerzeichen oder Komma, Schlüssel dürfen weder Leerzeichen noch Kommas enthalten), deren Größe und Anzahl der Einträge mit jedem Snapshot aufgezeichnet werden. So lässt sich ihr Wachstum über einen längeren Zeitraum auswerten (<a href="#Analyze-get-track">get track</a>).
    Erlaubt sind:
    <ul>
      <li><code>$defs{meinDevice}{.pvHistCache}</code>, <code>$data{x}{y}[2]</code> - Hashes und Arrays der FHEM-Hauptebene (gleiche Syntax wie bei <b>xHashDetail</b>)</li>
      <li><code>%FHEM::Modul::cache</code>, <code>@Paket::liste</code>, <code>$Paket::wert</code> - Paketvariablen (<code>our</code>), optional gefolgt von <code>{key}</code> oder <code>[index]</code></li>
      <li><code>93_DbLog.pm:%cache</code> - file-scope <code>my</code> Variable einer Moduldatei (benötigt <code>PadWalker</code>, die Variable muss von mindestens einer Funktion der Datei verwendet werden)</li>
    </ul>
    Weder <a href="#Analyze-attr-deepScan">deepScan</a> noch ein Snapshot mit Deep Scan ist nötig, bei file-scope Variablen wird nur die genannte Datei durchsucht.
    Jedes Objekt wird für sich gemessen, die Größe ist daher vollständig und unabhängig von anderen Objekten. Die Größen sind <b>nicht</b> Teil des zugeordneten Speichers, sonst würden sie doppelt gezählt.
    Objekte, die nicht gefunden werden, stehen im Bericht des Snapshots. Sie werden auch von <b>diff</b> und <b>leakCandidates</b> ausgewertet.<br>
    Je Objekt entstehen die Readings <b>track_&lt;Objekt&gt;_bytes</b> und <b>track_&lt;Objekt&gt;_count</b>. Der Name wird aus dem Pfad abgeleitet, zum Beispiel
    <code>track_defs_meinDevice_pvHistCache_bytes</code>. <br>
    <br>
    Beispiel: <code>attr &lt;name&gt; trackObjects $defs{VictronVRM}{.pvHistCache} 93_DbLog.pm:%cache</code>
    </li>
    <br>

    <a id="Analyze-attr-treeDepth"></a>
    <li><b>treeDepth &lt;Anzahl&gt;</b> <br>
    Tiefe des Baums, den <b>xHashDetail</b> und <b>mainHash</b> anzeigen. Tiefere Ebenen sind in den Größen enthalten, werden aber nicht angezeigt. <br>
    (default: 3)
    </li>
    <br>

    <a id="Analyze-attr-useFork"></a>
    <li><b>useFork 0 | 1</b> <br>
    Mit <b>0</b> läuft die Messung innerhalb des FHEM-Prozesses. FHEM ist währenddessen blockiert, und ein Absturz von <code>Devel::Size</code> reißt FHEM mit.
    Die Breadcrumb-Datei bleibt erhalten, nach dem Neustart erkennt das Modul die unvollständige Analyse und nimmt das Objekt, das den Absturz verursacht hat, in die Crash-Liste auf.
    Nur sinnvoll, wenn kein eigener Prozess gestartet werden kann ("Cannot fork"). <br>
    (default: 1)
    </li>
  </ul>
  <br>

  <a id="Analyze-Readings"></a>
  <b>Readings</b>
  <ul>
    Readings, die zu einem Snapshot oder zur periodischen Messung gehören, werden beim Start von FHEM entfernt, weil Snapshots und Messwerte nur im Speicher liegen. Nur <b>state</b>, <b>crashListCount</b>, <b>snapshots</b> und <b>snapshot_last</b> werden neu gesetzt, alle anderen entstehen mit der nächsten Messung.<br><br>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>NN_largestObject</b>          </td><td>die größten Objekte, Format <code>&lt;Größe in Bytes&gt;, &lt;Objekt&gt;</code>, zum Beispiel <code>1048576, $data{SolCast6}</code>. Das Objekt kann in <b>xHashDetail</b> kopiert werden.   </td></tr>
      <tr><td> <b>NN_largestDevice</b>          </td><td>die größten Devices, Format <code>&lt;Größe in Bytes&gt;, &lt;Device&gt;</code>                                                                                                                </td></tr>
      <tr><td> <b>NN_largestType</b>            </td><td>die größten Device-Typen (Summe aller Devices des Typs), Format <code>&lt;Größe in Bytes&gt;, &lt;TYPE&gt;</code>                                                                              </td></tr>
      <tr><td> <b>attributed_kB</b>             </td><td>Speicher in kB, der gemessenen FHEM-Strukturen zugeordnet ist (letzter Snapshot)                                                                                                               </td></tr>
      <tr><td> <b>crashListCount</b>            </td><td>Anzahl der Objekte in der Crash-Liste                                                                                                                                                </td></tr>
      <tr><td> <b>count_defs</b>                </td><td>Anzahl der Devices (letzter Snapshot)                                                                                                                                                          </td></tr>
      <tr><td> <b>count_fds</b>                 </td><td>Anzahl der offenen Filedeskriptoren (letzter Snapshot)                                                                                                                                         </td></tr>
      <tr><td> <b>count_kids</b>                </td><td>Anzahl der Kindprozesse (letzter Snapshot)                                                                                                                                                     </td></tr>
      <tr><td> <b>count_timers</b>              </td><td>Anzahl der Timer (letzter Snapshot)                                                                                                                                                            </td></tr>
      <tr><td> <b>proc_pss_kB</b>               </td><td>Proportional Set Size in kB (letzter Snapshot)                                                                                                                                                 </td></tr>
      <tr><td> <b>proc_private_kB</b>           </td><td>privater Speicher in kB (letzter Snapshot)                                                                                                                                                     </td></tr>
      <tr><td> <b>proc_rss_kB</b>               </td><td>Resident Set Size des FHEM-Prozesses in kB (letzter Snapshot oder letzte Messung)                                                                                                              </td></tr>
      <tr><td> <b>proc_rssPeak_kB</b>           </td><td>höchste Resident Set Size seit dem Start von FHEM in kB (letzte Messung)                                                                                                                       </td></tr>
      <tr><td> <b>proc_rssTrend_kBperHour</b>   </td><td>Steigung der Resident Set Size über die letzten 24 Stunden in kB pro Stunde (letzte Messung, mindestens 6 Messwerte nötig)                                                                     </td></tr>
      <tr><td> <b>proc_swap_kB</b>              </td><td>ausgelagerter Speicher in kB (letzter Snapshot)                                                                                                                                                </td></tr>
      <tr><td> <b>snapshot_last</b>             </td><td>Label des neuesten Snapshots                                                                                                                                                                   </td></tr>
      <tr><td> <b>snapshots</b>                 </td><td>Anzahl der gespeicherten Snapshots                                                                                                                                                             </td></tr>
      <tr><td> <b>track_&lt;Objekt&gt;_bytes</b> </td><td>Größe in Bytes eines mit <b>trackObjects</b> getrackten Objekts (letzter Snapshot)                                                                                                </td></tr>
      <tr><td> <b>track_&lt;Objekt&gt;_count</b> </td><td>Anzahl der Einträge eines mit <b>trackObjects</b> getrackten Objekts (letzter Snapshot)                                                                                            </td></tr>
      <tr><td> <b>unattributed_kB</b>           </td><td>Teil der Prozessgröße, der nicht gemessenen Strukturen zugeordnet werden kann (Interpreter, Programmcode, Bibliotheken, Fragmentierung, ohne deepScan auch file-scope Variablen)               </td></tr>
      <tr><td> <b>state</b>                     </td><td>aktueller Zustand des Moduls. Mögliche Werte:                                                                                                                                                  </td></tr>
      <tr><td>                                  </td><td><ul><b>Initialized</b> - das Device wurde angelegt                                                   </ul>                                                                                      </td></tr>
      <tr><td>                                  </td><td><ul><b>running: &lt;Job&gt;</b> - ein Job (snapshot, devices, tree) läuft im Hintergrund             </ul>                                                                                      </td></tr>
      <tr><td>                                  </td><td><ul><b>done</b> - der letzte Job wurde erfolgreich beendet                                           </ul>                                                                                      </td></tr>
      <tr><td>                                  </td><td><ul><b>aborted</b> - der Job wurde mit <b>abortJob</b> abgebrochen                                   </ul>                                                                                      </td></tr>
      <tr><td>                                  </td><td><ul><b>error</b> - der Job ist fehlgeschlagen, Details in <code>get &lt;name&gt; lastResult</code> und im Log </ul>                                                                    </td></tr>
      <tr><td>                                  </td><td><ul><b>error: crashed at &lt;Objekt&gt;</b> - der Messprozess ist beim Messen dieses Objekts abgestürzt, Details in <code>get &lt;name&gt; lastResult</code> </ul>                  </td></tr>
      <tr><td>                                  </td><td><ul><b>error: &lt;Ursache&gt;</b> - der Hintergrundprozess wurde abgebrochen, zum Beispiel durch das Timeout </ul>                                                                    </td></tr>
      <tr><td>                                  </td><td><ul><b>disabled</b> - das Device ist durch <b>disable</b> deaktiviert                                 </ul>                                                                                      </td></tr>
    </table>
  </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 98_Analyze.pm
{
  "abstract": "Module to analyze the memory usage and to find memory leak candidates.",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Analyse des Speicherverbrauchs und Speicherleck-Kandidaten."
    }
  },
  "keywords": [
    "Analyze",
    "Cannot fork",
    "Memory",
    "Memory leak",
    "Data",
    "Crash"
  ],
  "version": "v1.1.1",
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
        "Data::Dumper": 0,
        "GPUtils": 0,
        "Devel::Size": 0,
        "Blocking": 0,
        "Storable": 0,
        "MIME::Base64": 0,
        "Scalar::Util": 0,
        "File::Spec": 0,
        "Time::HiRes": 0,
        "POSIX": 0,
        "B": 0,
        "utf8": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "PadWalker": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Analyze_-_Analyse_von_FHEM_Datenstrukturen",
      "title": "Analyze - Analyse von FHEM Datenstrukturen"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/98_Analyze.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/98_Analyze.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
