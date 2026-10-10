########################################################################################################################
# $Id$
#########################################################################################################################
#       98_MemSaver.pm
#
#       (c) 2026 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#       FHEM module for regularly returning unused glibc memory blocks
#       to the OS and for recording memory & CPU readings.
#
#       Requires: Linux:   FFI::Platypus (apt install libffi-platypus-perl)
#                 Windows: Win32::API
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
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 98_MemSaver.pm
#  Zeilenenden auf LF umstellen: sed -i 's/\r$//' 98_MemSaver.pm
#
#########################################################################################################################

package FHEM::MemSaver;

use strict;
use warnings;
use feature 'state';

use POSIX qw(strftime);
eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'

use GPUtils qw(GP_Import GP_Export);

# Versions History
my %vNotesIntern = (
  "1.5.0"  => "10.10.2026  Set 'trimNow' um ein optionales Tag erweitert, das mit verbose 4 geloggt wird ".
                           "neue Readings `swap_sys_total_mb` und `swap_sys_used_mb` (systemweiter Swap-Bestand aus `/proc/meminfo`) ".
                           "Logzeile RAM/CPU um `SysSwapTot` und `SysSwapUsed` erweitert ".
                           "Windows-Unterstützung (Beitrag von czcbe): Working Set leeren per EmptyWorkingSet, ".
                           "Speicher- und CPU-Werte per Win32::API (GetProcessMemoryInfo, GetSystemTimes), ".
                           "Leak-Analyse unter Windows auf Basis des Commit Charge, Nachmessung nach WINTRIMDELAY per Timer, ".
                           "mallocTrim_Analyse in trimAnalysis umbenannt, Timer von trimAnalysis in Undef und Attr disable entfernt ",
  "1.4.0"  => "06.10.2026  Drift-Berechnung in _leakAssessment mittels linearer Regression statt Endpunktdifferenz, ".
                           "fragmentation_cleared basiert auf der Summe der freigegebenen MB im Zeitfenster FREEDWINDOW statt auf einem Einzelwert, ".
                           "Filter fuer leak_status_weighted (Attribut leakFilterWindow), neues Reading leak_status_raw ".
                           "Mindest-Zeitspanne MINSPAN in _leakAssessment, Mindestanzahl Messpunkte MINPOINTS, ".
                           "Plausibilitätsprüfung gegen Einmalsprünge (beide Fensterhälften müssen mindestens STEADYFACTOR der Gesamtsteigung zeigen), ".
                           "Messgröße der Drift-Berechnung ist RSS statt Private (Clean + Dirty) ".
                           "Messwert fuer die Drift-Berechnung wird nach malloc_trim erfasst (bereinigter RSS) ".
                           "Reading leak_status in leak_status_weighted umbenannt ",
  "1.3.0"  => "05.10.2026  siehe Changelog, fhem_warming_up Status für Uptime < WARMUP in _leakAssessment integriert ".
                           "Set-Kommando 'trimNow' eingebaut ",
  "1.2.0"  => "04.10.2026  Einbau _leakAssessment zur Bewertung Leak vs. Fragmentierung ",
  "1.1.0"  => "04.10.2026  cpu_load, cpu_usage_pct und trim_next_run integriert ".
                           "fhem_uptime, fhem_start_time und fhem_uptime_sec als Readings eingebaut ".
                           "Perl Verion als Internal eingebaut ",
  "1.0.0"  => "03.10.2026  initiale Version "
);

BEGIN {
    GP_Import( qw(
        AttrVal
        FmtDateTime
        gettimeofday
        IsDisabled
        InternalTimer
        Log3
        modules
        readingsSingleUpdate
        readingsBeginUpdate
        readingsBulkUpdate
        readingsEndUpdate
        readingsDelete
        readingFnAttributes
        ReadingsVal
        RemoveInternalTimer
    ));
}

GP_Export( qw(
    Initialize
));


## Konstanten
######################
use constant {
  FREEDWINDOW  => 1800,                 # Zeitfenster (Sekunden) zur Aufsummierung der von malloc_trim freigegebenen MB
  FILTERWINDOW => 1800,                 # Default Zeitfenster (Sekunden) des leak_status_weighted-Filters (Attribut leakFilterWindow)
  MAXAGE       => 7200,                 # Historie-Zeitfenster (Sekunden) für stabile Regressions- bzw. Trendlinie der Leak-Analyse
  MINPOINTS    => 8,                    # Mindestanzahl Messpunkte der Historie, bevor die Trendanalyse startet (wird bei großem Intervall begrenzt)
  MINSPAN      => 2700,                 # Mindest-Zeitspanne (Sekunden) der Historie, bevor die Trendanalyse startet (45 Minuten)
  MINVOTES     => 5,                    # Mindestanzahl Bewertungen im Filterfenster, sonst wird der Rohwert veroeffentlicht
  STEADYFACTOR => 0.5,                  # beide Fensterhälften müssen mindestens diesen Anteil der Gesamtsteigung zeigen (Schutz vor Einmalsprüngen)
  WARMUP       => 7200,                 # Warm-up-Phase (Sekunden)
  WINTRIMDELAY => 15,                   # Windows: Wartezeit (Sekunden) zwischen EmptyWorkingSet und Nachmessung (wird bei kleinem Intervall begrenzt)
};


##############################################################################
sub Initialize {
  my ($hash) = @_;

  $hash->{DefFn}      = \&Define;
  $hash->{SetFn}      = \&Set;
  $hash->{UndefFn}    = \&Undef;
  $hash->{AttrFn}     = \&Attr;
  $hash->{AttrList}   = "disable:0,1 ".
                        "leakFilterWindow ".
                        $readingFnAttributes;

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'

return;
}

##############################################################################
sub Define {
  my ($hash, $def) = @_;
  my @a = split m{\s+}x, $def;

  return "Usage: define <name> MemSaver [interval]" if @a < 2;

  my $name     = $a[0];
  my $interval = $a[2] // 900;

  return "Interval must be a positive integer (seconds)"
      unless $interval =~ m/^[0-9]+$/x && $interval > 0;

  return "MemSaver: Unsupported operating system ($^O). This module requires Linux or Windows."
      unless $^O eq 'linux' || $^O eq 'MSWin32';

  if ($^O eq 'MSWin32') {
      eval { require Win32::API; 1; }                                           ## no critic 'eval'
          or return "MemSaver: Required Perl module Win32::API is missing. Please install it via cpan.";
  }
  else {
      eval { require FFI::Platypus; 1; }                                        ## no critic 'eval'
          or return "MemSaver: Required Perl module FFI::Platypus is missing. Please install it via 'apt install libffi-platypus-perl' or cpan.";
  }

  $hash->{INTERVAL}              = $interval;
  $hash->{DEF}                   = $interval;                                   # DEF immer setzen, damit das Intervall in FHEMWEB per modify änderbar ist
  $hash->{PERLVERSION}           = sprintf "%vd", $^V;                          # Perl Version z.B. "5.36.0"
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                        # Modul Meta.pm nicht vorhanden

  use version 0.77; our $VERSION = moduleVersion ($hash, \%vNotesIntern);       # Versionsinformationen setzen

  readingsSingleUpdate ($hash, 'state', 'active', 1);

  scheduleRun ($hash, 5);                                                       # Erster Lauf nach 5 Sekunden

return;
}

##############################################################################
sub Set {
  my ($hash, @a) = @_;

  return qq{"Set ..." needs at least an argument} if @a < 2;

  my $name = shift @a;
  my $cmd  = shift @a;
  my $arg  = join " ", map { my $p = $_; $p =~ s/\s+/ /xg; $p; } @a;            ## no critic 'Map blocks'

  return if IsDisabled($name);

  my $setlist = "Unknown argument $cmd, choose one of ".
                "trimNow:textField,the&nbsp;input&nbsp;is&nbsp;logged&nbsp;with&nbsp;verbose&nbsp;4 ";

  if ($cmd eq 'trimNow') {                                                      # Messwerte erneuern und malloc_trim ausführen
      Log3 ($name, 4, "$name - MemSaver trim tag: $arg") if length $arg;

      collectMemReadings ($hash);
      mallocTrim         ($hash);
      return;
  }

return $setlist;
}

##############################################################################
sub Undef {
  my ($hash) = @_;

  RemoveInternalTimer ($hash, \&run);
  RemoveInternalTimer ($hash, \&trimAnalysis);

return;
}

##############################################################################
sub Attr {
  my ($cmd, $name, $attr, $val) = @_;
  my $hash = $main::defs{$name};

  if ($attr eq 'disable') {
      if ($cmd eq 'set' && ($val // '') eq '1') {
          RemoveInternalTimer  ($hash, \&run);
          RemoveInternalTimer  ($hash, \&trimAnalysis);
          readingsSingleUpdate ($hash, 'state', 'disabled', 1);
      }
      else {
          readingsSingleUpdate ($hash, 'state', 'active', 1);
          scheduleRun          ($hash, 1);
      }
  }

  if ($attr eq 'leakFilterWindow') {
      if ($cmd eq 'set' && ($val // '') !~ /^[0-9]+$/x) {
          return qq{leakFilterWindow must be a non-negative integer (seconds, 0 = filter off)};
      }

      delete $hash->{HELPER}{STATUS_HISTORY};                                   # Filter neu aufsetzen
      delete $hash->{HELPER}{LEAK_STATUS_PUB};
  }

return;
}

##############################################################################
sub scheduleRun {
  my ($hash, $delay) = @_;
  $delay //= $hash->{INTERVAL};

  my $next_ts = gettimeofday() + $delay;

  RemoveInternalTimer ($hash, \&run);
  InternalTimer       ($next_ts, \&run, $hash, 0);

  readingsSingleUpdate ($hash, 'trim_next_run', FmtDateTime($next_ts), 1);

return;
}

##############################################################################
sub run {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if (IsDisabled($name)) {
      readingsSingleUpdate ($hash, 'state', 'disabled', 1);
      return;
  }

  collectMemReadings ($hash);
  mallocTrim         ($hash);
  scheduleRun        ($hash);

return;
}

##############################################################################
#  Speicher- & CPU-Readings aus /proc erfassen
##############################################################################
sub collectMemReadings {
  my ($hash) = @_;

  return _collectMemWin ($hash) if $^O eq 'MSWin32';                            # Windows: eigene Erfassung ohne /proc

  my $name = $hash->{NAME};
  my $v5   = AttrVal ($name, 'verbose', 3) >= 5;
  my %m;

  # --- 1. RAM / Proc Status ---
  my $status_file = "/proc/$$/status";

  if (open my $fh, '<', $status_file) {
      my @lines;
      while (<$fh>) {
          push @lines, $_ if $v5;
          $m{VmRSS}  = $1 if /^VmRSS:\s+(\d+)/x;
          $m{VmHWM}  = $1 if /^VmHWM:\s+(\d+)/x;
          $m{VmSize} = $1 if /^VmSize:\s+(\d+)/x;
      }
      close $fh;

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $status_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $status_file content:\n" . join('', @lines));
          Log3 ($name, 5, "$name - MemSaver [diag] parsed:"
                                 . " VmRSS="  . ($m{VmRSS}  // 'undef')
                                 . " VmHWM="  . ($m{VmHWM}  // 'undef')
                                 . " VmSize=" . ($m{VmSize} // 'undef'));
      }
  }
  else {
      Log3 ($name, 2, "$name - MemSaver: cannot open $status_file: $!");
      Log3 ($name, 5, "$name - MemSaver [diag] $status_file readable: NO ($!)") if $v5;
      return;
  }

  # --- /proc/$$/smaps_rollup ---
  my $smaps_file = "/proc/$$/smaps_rollup";

  if (open my $fh, '<', $smaps_file) {
      my @lines;
      while (<$fh>) {
          push @lines, $_ if $v5;
          $m{Pss}           = $1 if /^Pss:\s+(\d+)/x;
          $m{Shared_Clean}  = $1 if /^Shared_Clean:\s+(\d+)/x;
          $m{Shared_Dirty}  = $1 if /^Shared_Dirty:\s+(\d+)/x;
          $m{Private_Clean} = $1 if /^Private_Clean:\s+(\d+)/x;
          $m{Private_Dirty} = $1 if /^Private_Dirty:\s+(\d+)/x;
          $m{Swap}          = $1 if /^Swap:\s+(\d+)/x;
      }
      close $fh;

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $smaps_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $smaps_file content:\n" . join('', @lines));
          Log3 ($name, 5, "$name - MemSaver [diag] parsed:"
                                 . " Pss="           . ($m{Pss}           // 'undef')
                                 . " Shared_Clean="  . ($m{Shared_Clean}  // 'undef')
                                 . " Shared_Dirty="  . ($m{Shared_Dirty}  // 'undef')
                                 . " Private_Clean=" . ($m{Private_Clean} // 'undef')
                                 . " Private_Dirty=" . ($m{Private_Dirty} // 'undef')
                                 . " Swap="          . ($m{Swap}          // 'undef'));
      }
  }
  else {
      Log3 ($name, 4, "$name - MemSaver: $smaps_file not available — PSS/Shared/Private/Swap readings skipped") if !$v5;    # Herabgestuft auf Log-Level 4, da das Fehlen auf vielen Kerneln/Containern normal ist
      Log3 ($name, 5, "$name - MemSaver [diag] $smaps_file readable: NO ($!)") if $v5;
  }

  # --- 2. Systemweite Swap-Aktivität ---
  my $vmstat_file = '/proc/vmstat';
  my %vmstat_cur;

  if (open my $fh, '<', $vmstat_file) {
      my @lines;
      while (<$fh>) {
          push @lines, $_ if $v5 && /^pswp/x;                                       # nur relevante Zeilen
          $vmstat_cur{pswpin}  = $1 if /^pswpin\s+(\d+)/x;
          $vmstat_cur{pswpout} = $1 if /^pswpout\s+(\d+)/x;
      }
      close $fh;

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $vmstat_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $vmstat_file relevant lines:\n" . join('', @lines));
          Log3 ($name, 5, "$name - MemSaver [diag] parsed:"
                                 . " pswpin="  . ($vmstat_cur{pswpin}  // 'undef')
                                 . " pswpout=" . ($vmstat_cur{pswpout} // 'undef'));
      }
  }
  else {
      Log3 ($name, 3, "$name - MemSaver: $vmstat_file not available — swap activity readings skipped") if !$v5;
      Log3 ($name, 5, "$name - MemSaver [diag] $vmstat_file readable: NO ($!)") if $v5;
  }

  # --- 2a. Systemweiter Swap-Bestand ---
  my $meminfo_file = '/proc/meminfo';
  my %meminfo;

  if (open my $fh, '<', $meminfo_file) {
      my @lines;
      while (<$fh>) {
          push @lines, $_ if $v5 && /^Swap(?:Total|Free)/x;                         # nur relevante Zeilen
          $meminfo{SwapTotal} = $1 if /^SwapTotal:\s+(\d+)/x;
          $meminfo{SwapFree}  = $1 if /^SwapFree:\s+(\d+)/x;
      }
      close $fh;

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $meminfo_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $meminfo_file relevant lines:\n" . join('', @lines));
          Log3 ($name, 5, "$name - MemSaver [diag] parsed:"
                                 . " SwapTotal=" . ($meminfo{SwapTotal} // 'undef')
                                 . " SwapFree="  . ($meminfo{SwapFree}  // 'undef'));
      }
  }
  else {
      Log3 ($name, 3, "$name - MemSaver: $meminfo_file not available — swap usage readings skipped") if !$v5;
      Log3 ($name, 5, "$name - MemSaver [diag] $meminfo_file readable: NO ($!)") if $v5;
  }

  my $swap_sys_ok      = defined $meminfo{SwapTotal} && defined $meminfo{SwapFree};
  my $swap_sys_used_kb = $swap_sys_ok ? $meminfo{SwapTotal} - $meminfo{SwapFree} : 0;
  $swap_sys_used_kb    = 0 if $swap_sys_used_kb < 0;

  my $swapin = do {
      my $prev  = $hash->{HELPER}{VMSTAT_PREV}{pswpin} // $vmstat_cur{pswpin} // 0;
      my $delta = ($vmstat_cur{pswpin} // 0) - $prev;
      sprintf '%.2f', ($delta * 4) / 1024;
  };

  my $swapout = do {
      my $prev  = $hash->{HELPER}{VMSTAT_PREV}{pswpout} // $vmstat_cur{pswpout} // 0;
      my $delta = ($vmstat_cur{pswpout} // 0) - $prev;
      sprintf '%.2f', ($delta * 4) / 1024;
  };

  $hash->{HELPER}{VMSTAT_PREV} = \%vmstat_cur;

  # Prozess-Swap-Delta
  my $prev_proc_swap              = $hash->{HELPER}{PREV_PROC_SWAP} // ($m{Swap} // 0);
  my $proc_swap_delta             = ($m{Swap} // 0) - $prev_proc_swap;
  $hash->{HELPER}{PREV_PROC_SWAP} = ($m{Swap} // 0);

  # --- 3. CPU Load ---
  my $loadavg_file = '/proc/loadavg';
  my $load1        = 0;

  if (open my $fh, '<', $loadavg_file) {
      my $line = <$fh>;
      close $fh;
      ($load1) = $line =~ /^([\d\.]+)/;
      $load1 //= 0;

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $loadavg_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $loadavg_file content: $line");
          Log3 ($name, 5, "$name - MemSaver [diag] parsed: cpu_load1=$load1");
      }
  }
  else {
      Log3 ($name, 3, "$name - MemSaver: $loadavg_file not available — cpu_load1 reading skipped") if !$v5;
      Log3 ($name, 5, "$name - MemSaver [diag] $loadavg_file readable: NO ($!)") if $v5;
  }

  # --- /proc/stat (CPU times) ---
  my $stat_file              = '/proc/stat';
  my ($cpu_idle, $cpu_total) = (0, 0);
  my $cpu_pct                = 0;

  if (open my $fh, '<', $stat_file) {
      my $line = <$fh>;
      close $fh;
      my @v  = split /\s+/, $line;
      $cpu_idle  = ($v[4] || 0) + ($v[5] || 0);
      $cpu_total = 0;
      $cpu_total += $_ for @v[1..8];

      if ($v5) {
          Log3 ($name, 5, "$name - MemSaver [diag] $stat_file readable: YES");
          Log3 ($name, 5, "$name - MemSaver [diag] $stat_file cpu line: $line");
          Log3 ($name, 5, "$name - MemSaver [diag] parsed: cpu_idle=$cpu_idle cpu_total=$cpu_total");
      }
  }
  else {
      Log3 ($name, 3, "$name - MemSaver: $stat_file not available — cpu_usage_pct reading skipped") if !$v5;
      Log3 ($name, 5, "$name - MemSaver [diag] $stat_file readable: NO ($!)") if $v5;
  }

  if (defined $hash->{HELPER}{LAST_CPU_IDLE} && defined $hash->{HELPER}{LAST_CPU_TOTAL}) {
      my $diff_total = $cpu_total - $hash->{HELPER}{LAST_CPU_TOTAL};
      my $diff_idle  = $cpu_idle  - $hash->{HELPER}{LAST_CPU_IDLE};

      if ($diff_total > 0) {
          $cpu_pct = sprintf '%.2f', (1 - ($diff_idle / $diff_total)) * 100;
      }
  }

  $hash->{HELPER}{LAST_CPU_IDLE}  = $cpu_idle;
  $hash->{HELPER}{LAST_CPU_TOTAL} = $cpu_total;

  # --- 4. FHEM Uptime ---
  my $fhem_start = $main::fhem_started // gettimeofday();
  my $uptime_sec = int(gettimeofday() - $fhem_start);
  my $uptime_str = _formatUptime ($uptime_sec);
  my $start_time = FmtDateTime ($fhem_start);                                           # Formatiert z.B. zu "2026-10-02 14:30:00"

  # --- Priv + Shared RAM konsolidiert ---
  my $priv_kb   = ($m{Private_Clean} // 0) + ($m{Private_Dirty} // 0);
  my $shared_kb = ($m{Shared_Clean}  // 0) + ($m{Shared_Dirty}  // 0);

  # --- Umrechnungsroutine ---
  my $fmt = sub {                                                                       # Safe conversion: stellt sicher, dass undef, "" oder Nicht-Zahlen zu 0 werden
      my $val = $_[0];
      $val = 0 if !defined $val || $val eq '' || $val !~ /^-?\d+(?:\.\d+)?$/;
      return sprintf '%.2f', $val / 1024;
  };

  # --- Readings schreiben ---

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'mem_private_mb',        $fmt->($priv_kb));
  readingsBulkUpdate  ($hash, 'mem_shared_mb',         $fmt->($shared_kb));
  readingsBulkUpdate  ($hash, 'mem_rss_mb',            $fmt->($m{VmRSS} // 0));                         # Resident Set Size
  readingsBulkUpdate  ($hash, 'mem_hwm_mb',            $fmt->($m{VmHWM} // 0));                         # High Water Mark (Peak seit Start)
  readingsBulkUpdate  ($hash, 'mem_pss_mb',            $fmt->($m{Pss} // 0));                           # Proportional Set Size
  readingsBulkUpdate  ($hash, 'mem_vsize_mb',          $fmt->($m{VmSize} // 0));                        # Virtueller Adressraum
  readingsBulkUpdate  ($hash, 'swap_process_total_mb', $fmt->($m{Swap} // 0));                          # Ausgelagerter Prozess-Swap gesamt
  readingsBulkUpdate  ($hash, 'swap_process_delta_mb', $fmt->($proc_swap_delta // 0));                  # Swap-Delta seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'swap_sys_in_mb',        $swapin // '0.00');                              # Systemweiter Swap-In seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'swap_sys_out_mb',       $swapout // '0.00');                             # Systemweiter Swap-Out seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'swap_sys_total_mb',     $fmt->($meminfo{SwapTotal})) if $swap_sys_ok;    # Systemweiter Swap gesamt
  readingsBulkUpdate  ($hash, 'swap_sys_used_mb',      $fmt->($swap_sys_used_kb))   if $swap_sys_ok;    # Systemweiter Swap belegt
  readingsBulkUpdate  ($hash, 'cpu_load1',             sprintf('%.2f', $load1 // 0));                   # Load Average (1 Min)
  readingsBulkUpdate  ($hash, 'cpu_usage_pct',         $cpu_pct // 0);                                  # CPU-Auslastung über das Intervall
  readingsBulkUpdate  ($hash, 'fhem_start_time',       $start_time);                                    # Lesbare Startzeit
  readingsBulkUpdate  ($hash, 'fhem_uptime',           $uptime_str);                                    # z. B. "12d 4h 15m 30s"
  readingsBulkUpdate  ($hash, 'fhem_uptime_sec',       $uptime_sec);                                    # z. B. 1052130
  readingsBulkUpdate  ($hash, 'state',                 'active');
  readingsEndUpdate   ($hash, 1);

  my $ram = join ", ",
      "RSS="         . $fmt->($m{VmRSS} // 0),
      "HWM="         . $fmt->($m{VmHWM} // 0),
      "PSS="         . $fmt->($m{Pss} // 0),
      "Priv="        . $fmt->($priv_kb),
      "Shared="      . $fmt->($shared_kb),
      "ProcSwapTot=" . $fmt->($m{Swap} // 0),
      "ProcSwapDta=" . $fmt->($proc_swap_delta // 0),
      "SysSwapIn="   . ($swapin // '0.00'),
      "SysSwapOut="  . ($swapout // '0.00'),
      "VSize="       . $fmt->($m{VmSize} // 0),
      "SysSwapTot="  . ($swap_sys_ok ? $fmt->($meminfo{SwapTotal}) : 'n/a'),
      "SysSwapUsed=" . ($swap_sys_ok ? $fmt->($swap_sys_used_kb)   : 'n/a');

  Log3 ($name, 4, "$name - RAM/CPU: " . $ram . sprintf(", CPU_Load1=%.2f, CPU_Usage=%.2f%%", $load1 // 0, $cpu_pct // 0));

  ### nicht mehr benötigte Daten verarbeiten - Bereich kann später wieder raus !!
  ########################################################################################################################
  if (!$hash->{HELPER}{LS_deleted}) {                       # läuft nur einmal pro Session
      readingsDelete ($hash, 'leak_status');
      $hash->{HELPER}{LS_deleted} = 1;
  }

return;
}

##############################################################################
#  Speicher- & CPU-Readings unter Windows erfassen (Win32::API)
#  - es gibt kein /proc, daher nur eine Teilmenge der Linux-Readings
#  - cpu_usage_pct: Systemauslastung aus GetSystemTimes, Delta zum letzten Zyklus
#  - cpu_load1 und swap_* gibt es unter Windows nicht und werden nicht erzeugt
##############################################################################
sub _collectMemWin {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $mem = _winMemInfo();

  if (!$mem) {
      Log3 ($name, 2, "$name - MemSaver: GetProcessMemoryInfo failed — memory readings skipped");
      return;
  }

  # --- CPU-Auslastung des Systems ---
  my $cpu_pct                = 0;
  my ($cpu_idle, $cpu_total) = _winCpuTimes();

  if (defined $cpu_idle) {
      if (defined $hash->{HELPER}{LAST_CPU_IDLE} && defined $hash->{HELPER}{LAST_CPU_TOTAL}) {
          my $diff_total = $cpu_total - $hash->{HELPER}{LAST_CPU_TOTAL};
          my $diff_idle  = $cpu_idle  - $hash->{HELPER}{LAST_CPU_IDLE};

          if ($diff_total > 0) {
              $cpu_pct = sprintf '%.2f', (1 - ($diff_idle / $diff_total)) * 100;
          }
      }

      $hash->{HELPER}{LAST_CPU_IDLE}  = $cpu_idle;
      $hash->{HELPER}{LAST_CPU_TOTAL} = $cpu_total;
  }
  else {
      Log3 ($name, 3, "$name - MemSaver: GetSystemTimes failed — cpu_usage_pct reading skipped");
  }

  # --- FHEM Uptime ---
  my $fhem_start = $main::fhem_started // gettimeofday();
  my $uptime_sec = int(gettimeofday() - $fhem_start);
  my $uptime_str = _formatUptime ($uptime_sec);
  my $start_time = FmtDateTime ($fhem_start);

  # --- Readings schreiben ---
  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'mem_private_mb',  sprintf('%.2f', $mem->{commit}));                      # Commit Charge (Private Bytes)
  readingsBulkUpdate  ($hash, 'mem_rss_mb',      sprintf('%.2f', $mem->{rss}));                         # Working Set
  readingsBulkUpdate  ($hash, 'mem_hwm_mb',      sprintf('%.2f', $mem->{hwm}));                         # Peak Working Set
  readingsBulkUpdate  ($hash, 'cpu_usage_pct',   $cpu_pct)             if defined $cpu_idle;
  readingsBulkUpdate  ($hash, 'fhem_start_time', $start_time);
  readingsBulkUpdate  ($hash, 'fhem_uptime',     $uptime_str);
  readingsBulkUpdate  ($hash, 'fhem_uptime_sec', $uptime_sec);
  readingsBulkUpdate  ($hash, 'state',           'active');
  readingsEndUpdate   ($hash, 1);

  Log3 ($name, 4, "$name - RAM/CPU:"
                         . " RSS="  . sprintf('%.2f', $mem->{rss})
                         . ", HWM=" . sprintf('%.2f', $mem->{hwm})
                         . ", Priv=". sprintf('%.2f', $mem->{commit})
                         . sprintf(", CPU_Usage=%.2f%%", $cpu_pct));

return;
}

##############################################################################
#  Speicherfreigabe triggern
#  Linux:   malloc_trim(0) - glibc gibt freie Arenen an das OS zurück (synchron)
#  Windows: EmptyWorkingSet - Nachmessung nach WINTRIMDELAY per Timer (nicht blockierend)
#  Die Auswertung erfolgt in trimAnalysis
##############################################################################
sub mallocTrim {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  $hash->{HELPER}{RSS_BEFORE_TRIM} = _currentRssMb();                           # RAM-Wert VOR der Bereinigung sichern

  if ($^O eq 'MSWin32') {
      state $empty_ws;

      if (!defined $empty_ws) {
          $empty_ws = eval { require Win32::API; Win32::API->new('psapi', 'EmptyWorkingSet', 'N', 'I') } || 0;     ## no critic 'eval'
      }

      if (!$empty_ws || !$empty_ws->Call(-1)) {                                 # -1 = Pseudo-Handle des eigenen Prozesses
          Log3 ($name, 3, "$name - MemSaver: EmptyWorkingSet failed");
      }

      my $delay = WINTRIMDELAY;
      my $half  = ($hash->{INTERVAL} || 1) / 2;
      $delay    = $half if $half < $delay;                                      # Nachmessung muss vor dem nächsten Lauf stattfinden

      RemoveInternalTimer ($hash, \&trimAnalysis);
      InternalTimer       (gettimeofday() + $delay, \&trimAnalysis, $hash, 0);
  }
  else {
      state $malloc_trim_fn;
      state $has_platypus;

      if (!defined $has_platypus) {
          $has_platypus = eval {
              require FFI::Platypus;
              $malloc_trim_fn = FFI::Platypus->new(lib => undef)->function(malloc_trim => ['size_t'] => 'int');
              1;
          };
      }

      if ($has_platypus && $malloc_trim_fn) {
          $malloc_trim_fn->(0);
      }

      trimAnalysis ($hash);                                                     # Linux misst sofort synchron nach
  }

return;
}

##############################################################################
#  Nachmessung nach der Speicherfreigabe auswerten und Readings schreiben
#  (Windows: Aufruf per Timer nach WINTRIMDELAY, Linux: direkt aus mallocTrim)
##############################################################################
sub trimAnalysis {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $rss_before = $hash->{HELPER}{RSS_BEFORE_TRIM} // _currentRssMb();
  my $rss_after  = _currentRssMb();
  my $now        = gettimeofday();
  my $freed      = sprintf '%.2f', $rss_before - $rss_after;

  # Messwert der Leak-Analyse: Linux = RSS nach malloc_trim
  # Windows = Commit Charge, da EmptyWorkingSet diesen nicht verändert und ein Leak (nicht mehr angefasste Seiten) im Working Set nicht sichtbar wäre
  my $val = $rss_after;

  if ($^O eq 'MSWin32') {
      my $mem = _winMemInfo();
      $val    = $mem ? $mem->{commit} : 0;
  }

  if ($val > 0) {
      $hash->{HELPER}{RSS_HISTORY} //= [];
      push @{$hash->{HELPER}{RSS_HISTORY}}, { time => $now, val => $val };                                          # Aktuellen Messwert mit Zeitstempel anfügen
      @{$hash->{HELPER}{RSS_HISTORY}} = grep { $_->{time} >= ($now - MAXAGE) } @{$hash->{HELPER}{RSS_HISTORY}};     # Einträge entfernen, die älter als MAXAGE Sekunden sind
  }

  # unter Windows gibt EmptyWorkingSet keinen Heap zurück -> keine Bewertung "fragmentation_cleared"
  my ($leak_raw, $drift) = _leakAssessment ($hash, $^O eq 'MSWin32' ? 0 : $freed);
  my $leak_weighted      = _filterStatus   ($hash, $leak_raw);

  # --- Readings schreiben ---
  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'trim_last_freed_mb',    $freed);
  readingsBulkUpdate  ($hash, 'trim_last_run',         FmtDateTime(gettimeofday()));
  readingsBulkUpdate  ($hash, 'leak_status_weighted',  $leak_weighted);
  readingsBulkUpdate  ($hash, 'leak_status_raw',       $leak_raw);
  readingsBulkUpdate  ($hash, 'mem_drift_per_hour_mb', sprintf('%.2f', $drift)) if defined $drift;
  readingsEndUpdate   ($hash, 1);

  Log3 ($name, 5, "$name - Speicheranalyse ausgeführt");
  Log3 ($name, 5, "$name - malloc_trim executed: freed ~${freed} MB");
  Log3 ($name, 4, "$name - Leak Assessment: raw=$leak_raw, weighted=$leak_weighted, drift=" . sprintf('%.2f', $drift // 0) . " MB/h");

return;
}

##############################################################################
#        Leak vs. Fragmentierung mittels Regression bewerten
##############################################################################
sub _leakAssessment {
  my ($hash, $freed) = @_;

  my $now = gettimeofday();

  # von malloc_trim freigegebene MB der letzten FREEDWINDOW Sekunden aufsummieren
  # (Einzelwerte sind bei kurzen Zyklen zu klein um Fragmentierung zu erkennen)
  $hash->{HELPER}{FREED_HISTORY} //= [];
  push @{$hash->{HELPER}{FREED_HISTORY}}, { time => $now, val => ($freed > 0 ? $freed : 0) };
  @{$hash->{HELPER}{FREED_HISTORY}} = grep { $_->{time} >= ($now - FREEDWINDOW) } @{$hash->{HELPER}{FREED_HISTORY}};

  my $freed_sum = 0;
  $freed_sum   += $_->{val} for @{$hash->{HELPER}{FREED_HISTORY}};

  my $hist = $hash->{HELPER}{RSS_HISTORY} // [];
  return ('initializing', 0) if scalar(@$hist) < 3;

  my $fhem_start = $main::fhem_started // $now;
  my $uptime_sec = int($now - $fhem_start);
  return ('warming_up', 0) if $uptime_sec < WARMUP;                  # Warm-up-Phase berücksichtigen (z.B. erste 2 Stunden nach FHEM-Start)

  my $first = $hist->[0];
  my $last  = $hist->[-1];

  my $timespan_min = ($last->{time} - $first->{time}) / 60;
  my $iv     = $hash->{INTERVAL} || 1;
  my $maxpts = int(MAXAGE / $iv) - 1;                                   # mehr Punkte kann die Historie bei diesem Intervall nicht dauerhaft halten
  my $minpts = MINPOINTS;
  $minpts    = $maxpts if $maxpts < $minpts;
  $minpts    = 3       if $minpts < 3;

  # Mindest-Zeitspanne und Mindestanzahl Messpunkte der Historie, bevor die Trendanalyse startet
  return ('collecting_data', 0) if $timespan_min < MINSPAN / 60 || scalar(@$hist) < $minpts;

  # Drift per linearer Regression (Least Squares) über alle Punkte der Historie, Einheit MB pro Stunde
  my $n = scalar @$hist;
  my ($sx, $sy, $sxx, $sxy) = (0, 0, 0, 0);

  for my $pt (@$hist) {
      my $x  = ($pt->{time} - $first->{time}) / 3600;                   # Zeit in Stunden relativ zum ersten Punkt
      my $y  = $pt->{val};
      $sx   += $x;
      $sy   += $y;
      $sxx  += $x * $x;
      $sxy  += $x * $y;
  }

  my $den            = $n * $sxx - $sx * $sx;
  my $drift_per_hour = $den > 0 ? ($n * $sxy - $sx * $sy) / $den : 0;

  # Einmalsprung vs. stetiger Anstieg: beide Fensterhälften müssen mindestens STEADYFACTOR der Gesamtsteigung zeigen
  my $steady = 1;

  if ($drift_per_hour > 0) {
      my $mid = $first->{time} + ($last->{time} - $first->{time}) / 2;
      my @h1  = grep { $_->{time} <= $mid } @$hist;
      my @h2  = grep { $_->{time} >  $mid } @$hist;
      my $s1  = _halfSlope (\@h1);
      my $s2  = _halfSlope (\@h2);

      $steady = 0 if (defined $s1 && defined $s2 && ($s1 < STEADYFACTOR * $drift_per_hour || $s2 < STEADYFACTOR * $drift_per_hour));
  }

  # Bewertung: ein Leak wird nur vermutet, wenn der Anstieg stetig ist (kein Einmalsprung)
  my $leak_rating = 'ok';

  if ($drift_per_hour > 5.0 && $steady) {                                       # sehr starker und stetiger Drift
      $leak_rating = 'leak_suspected';
  }
  elsif ($drift_per_hour > 1.5 && $steady) {                                    # kontinuierlicher Anstieg
      $leak_rating = 'potential_leak_warning';
  }
  elsif ($freed_sum > 5.0 && $drift_per_hour <= 1.5) {                          # malloc_trim konnte im Zeitfenster signifikant Speicher freigeben -> Fragmentierung aufgeräumt
      $leak_rating = 'fragmentation_cleared';
  }

return ($leak_rating, $drift_per_hour);
}

##############################################################################
# Steigung (MB/h) einer Teilmenge der Historie, undef bei weniger als 3 Punkten
##############################################################################
sub _halfSlope {
  my ($pts) = @_;

  my $n = scalar @$pts;
  return if $n < 3;

  my $t0 = $pts->[0]{time};
  my ($sx, $sy, $sxx, $sxy) = (0, 0, 0, 0);

  for my $pt (@$pts) {
      my $x  = ($pt->{time} - $t0) / 3600;
      $sx   += $x;
      $sy   += $pt->{val};
      $sxx  += $x * $x;
      $sxy  += $x * $pt->{val};
  }

  my $den = $n * $sxx - $sx * $sx;

return $den > 0 ? ($n * $sxy - $sx * $sy) / $den : undef;
}

##############################################################################
#  Rohbewertung glätten: im Zeitfenster (Attribut leakFilterWindow) überwiegend
#  aufgetretene Bewertung veröffentlichen
#  - technische Zustände (initializing, collecting_data, warming_up) werden nicht
#    gefiltert und setzen den Filter zurück
#  - Gewichtung nach Dauer (Zeitabstand zum vorherigen Eintrag)
#  - Gleichstand: zuletzt veröffentlichter Status bleibt, sonst der schwerwiegendere
##############################################################################
sub _filterStatus {
  my ($hash, $raw) = @_;
  my $name = $hash->{NAME};

  my $win = AttrVal ($name, 'leakFilterWindow', FILTERWINDOW);

  if (!$win || $raw eq 'initializing' || $raw eq 'collecting_data' || $raw eq 'warming_up') {
      delete $hash->{HELPER}{STATUS_HISTORY};
      delete $hash->{HELPER}{LEAK_STATUS_PUB};
      return $raw;
  }

  my $iv  = $hash->{INTERVAL};
  my $min = MINVOTES * $iv;
  $win    = $min if $win < $min;                                    # Fenster mindestens MINVOTES Zyklen lang

  my $now  = gettimeofday();
  my $hist = $hash->{HELPER}{STATUS_HISTORY} //= [];
  push @$hist, { time => $now, status => $raw };
  @$hist = grep { $_->{time} >= ($now - $win) } @$hist;

  my $pub = $hash->{HELPER}{LEAK_STATUS_PUB};                       # zuletzt veröffentlichter Status

  if (scalar(@$hist) < MINVOTES) {                                  # noch zu wenige Bewertungen -> Rohwert
      $hash->{HELPER}{LEAK_STATUS_PUB} = $raw;
      return $raw;
  }

  my (%w, $prev);
  my $max_gap = 2 * $iv;                                            # große Lücken (z.B. nach disable) begrenzen

  for my $e (@$hist) {
      my $dt = defined $prev ? $e->{time} - $prev : $iv;
      $dt    = $max_gap if $dt > $max_gap;
      $w{$e->{status}} += $dt;
      $prev  = $e->{time};
  }

  my $max = 0;
  for my $v (values %w) { $max = $v if $v > $max }

  my @top = grep { $w{$_} >= $max - 1 } keys %w;                    # Gleichstand mit 1 s Toleranz
  my $res;

  if (scalar(@top) == 1) {
      $res = $top[0];
  }
  elsif (defined $pub && grep { $_ eq $pub } @top) {
      $res = $pub;
  }
  else {
      my %sev = (ok => 0, fragmentation_cleared => 1, potential_leak_warning => 2, leak_suspected => 3);
      ($res)  = sort { ($sev{$b} // 0) <=> ($sev{$a} // 0) } @top;
  }

  $hash->{HELPER}{LEAK_STATUS_PUB} = $res;

return $res;
}

##############################################################################
#  Formatiert eine Sekunden-Anzahl in ein lesbares Format (d, h, m, s)
##############################################################################
sub _formatUptime {
  my ($sec) = @_;

  my $days = int($sec / 86400);
  $sec %= 86400;
  my $hours = int($sec / 3600);
  $sec %= 3600;
  my $mins = int($sec / 60);
  my $secs = $sec % 60;

  my @parts;
  push @parts, "${days}d"   if $days  > 0;
  push @parts, "${hours}h"  if $hours > 0  || $days  > 0;
  push @parts, "${mins}m"   if $mins  > 0  || $hours > 0 || $days > 0;
  push @parts, "${secs}s";

return join(' ', @parts);
}

##############################################################################
#  Schneller RAM-Messer für Vorher-Nachher-Differenzen (Windows- & Linux-safe)
#  Linux: VmRSS, Windows: Working Set
##############################################################################
sub _currentRssMb {

  if ($^O eq 'MSWin32') {
      my $mem = _winMemInfo();
      return $mem ? $mem->{rss} : 0;
  }

  my $rss = 0;

  if (open my $fh, '<', "/proc/$$/status") {
      while (<$fh>) { $rss = $1 if /^VmRSS:\s+(\d+)/x }
      close $fh;
  }

return $rss / 1024;
}

##############################################################################
#  Windows: Speicherwerte des eigenen Prozesses per GetProcessMemoryInfo
#  Rückgabe: Hashref (MB) { rss => Working Set, hwm => Peak Working Set,
#            commit => Commit Charge (PagefileUsage) } oder undef bei Fehler
#  Aufbau PROCESS_MEMORY_COUNTERS: 64 Bit 72 Byte, 32 Bit 40 Byte
##############################################################################
sub _winMemInfo {
  state $api;
  state $is64;
  state $size;

  if (!defined $api) {
      $is64 = length(pack 'P', 0) == 8 ? 1 : 0;                                 # Zeigergröße bestimmt die Struktur
      $size = $is64 ? 72 : 40;
      $api  = eval { require Win32::API; Win32::API->new('psapi', 'GetProcessMemoryInfo', 'NPN', 'I') } || 0;      ## no critic 'eval'
  }

  return if !$api;

  my $buf = pack('L', $size) . "\0" x ($size - 4);                              # cb = Strukturgröße
  return if !$api->Call(-1, $buf, $size);

  my ($peak, $ws, $commit) = $is64
      ? (unpack('Q', substr($buf, 8, 8)), unpack('Q', substr($buf, 16, 8)), unpack('Q', substr($buf, 56, 8)))
      : (unpack('L', substr($buf, 8, 4)), unpack('L', substr($buf, 12, 4)), unpack('L', substr($buf, 32, 4)));

return { rss => $ws / 1048576, hwm => $peak / 1048576, commit => $commit / 1048576 };
}

##############################################################################
#  Windows: kumulierte CPU-Zeiten des Systems per GetSystemTimes
#  Rückgabe: (idle, total) in 100-ns-Einheiten, total = kernel + user
#  (kernel enthält bereits idle), leere Liste bei Fehler
##############################################################################
sub _winCpuTimes {
  state $api;

  if (!defined $api) {
      $api = eval { require Win32::API; Win32::API->new('kernel32', 'GetSystemTimes', 'PPP', 'I') } || 0;          ## no critic 'eval'
  }

  return if !$api;

  my $idle   = "\0" x 8;
  my $kernel = "\0" x 8;
  my $user   = "\0" x 8;
  return if !$api->Call($idle, $kernel, $user);

  my ($i, $k, $u) = map { my ($lo, $hi) = unpack 'V V', $_; $hi * 4294967296 + $lo } ($idle, $kernel, $user);

return ($i, $k + $u);
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

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersion {
  my ($sseq, @versions) = @_;

  my @sorted = sort { version->parse($a) <=> version->parse($b) } @versions;

return $sseq eq 'desc' ? reverse(@sorted) : @sorted;
}

1;

=pod
=item helper
=item summary    Frees unused glibc memory blocks and monitors CPU and RAM usage
=item summary_DE Gibt ungenutzte glibc-Speicherbl&ouml;cke frei + Readings CPU/RAM-Auslastung


=begin html

<a id="MemSaver"></a>
<h3>MemSaver</h3>
<ul>
  <b>Note: This module operates on Linux and Windows operating systems.</b><br><br>
  Regularly returns unused glibc memory blocks to the operating system and collects memory & CPU usage data from <code>/proc</code>. <br>
  Linux requires <code>FFI::Platypus</code> (<code>apt install libffi-platypus-perl</code>), Windows requires <code>Win32::API</code>.
  <br><br>

  <b>Windows</b> <br>
  Under Windows (native Perl) the working set of the FHEM process is emptied (<code>EmptyWorkingSet</code>) instead of calling <code>malloc_trim</code>.
  This does not return heap memory to the OS, the pages are only moved out of the working set and reloaded on demand.
  The follow-up measurement is taken 15 seconds after the call (at most half of the interval). Differences to Linux:
  <ul>
    <li>mem_rss_mb = working set, mem_hwm_mb = peak working set, mem_private_mb = commit charge</li>
    <li>trim_last_freed_mb = reduction of the working set measured after the call</li>
    <li>mem_drift_per_hour_mb is calculated from the commit charge, because leaked memory is no longer accessed and would not be visible in the working set</li>
    <li>leak_status_raw / leak_status_weighted never report <b>fragmentation_cleared</b></li>
    <li>not available: cpu_load1, mem_shared_mb, mem_pss_mb, mem_vsize_mb, swap_process_total_mb, swap_process_delta_mb, swap_sys_in_mb, swap_sys_out_mb, swap_sys_total_mb, swap_sys_used_mb</li>
  </ul>
  <br>

  <a id="MemSaver-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MemSaver [interval]</code><br><br>
    <code>interval</code> — run interval in seconds (default: 900).<br>
    Example: <code>define Saver MemSaver 900</code>
  </ul>
  <br>

  <a id="MemSaver-set"></a>
  <b>Set</b>
  <ul>
    <li><b>trimNow [Tag]</b><br>
        Immediately triggers a manual execution of <code>malloc_trim</code> (Windows: <code>EmptyWorkingSet</code>).
        The optional <b>tag</b> is written to the log with verbose level 4, e.g., <code>set Saver trimNow before Backup</code>.
    </li>
  </ul>
  <br>

  <a id="MemSaver-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="MemSaver-attr-disable"></a>
    <li><b>disable</b> <br>
    Enables and disables the module.
    </li>
    <br>

    <a id="MemSaver-attr-leakFilterWindow"></a>
    <li><b>leakFilterWindow &lt;seconds&gt;</b> <br>
    Time window for filtering <b>leak_status_weighted</b>. The rating that occurred most frequently within the window
    (weighted by duration) is published; the unfiltered value is available in
    <b>leak_status_raw</b>. <br>
    In the event of a tie, the last status is retained; otherwise, the more severe status applies.
    The window covers at least 5 cycles of the interval; until then, the raw value is published. <br>
    Technical states (initializing, collecting_data, warming_up) are never filtered. <br>
    <b>0</b> disables the filter. <br>
    (default: 1800)
    </li>
  </ul>
  <br>

  <a id="MemSaver-Readings"></a>
  <b>Readings</b>
  <ul>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>cpu_load1</b>              </td><td>System load average of the last minute: average number of processes that are running or waiting for CPU or I/O.                   </td></tr>
      <tr><td>                               </td><td>The value depends on the number of CPU cores: with one core 1.0 means full utilization,                                           </td></tr>
      <tr><td>                               </td><td>with n cores it takes n. Values below 1 are normal on a lightly loaded system.                                                    </td></tr>
      <tr><td> <b>cpu_usage_pct</b>          </td><td>System CPU usage in % calculated over the interval                                                                                </td></tr>
      <tr><td> <b>fhem_start_time</b>        </td><td>Timestamp when FHEM finished initializing (YYYY-MM-DD HH:MM:SS)                                                                   </td></tr>
      <tr><td> <b>fhem_uptime</b>            </td><td>Human-readable uptime of the FHEM process since start (e.g. "12d 4h 15m 30s")                                                     </td></tr>
      <tr><td> <b>fhem_uptime_sec</b>        </td><td>FHEM process uptime in total seconds                                                                                              </td></tr>
      <tr><td> <b>mem_rss_mb</b>             </td><td>Resident Set Size (physical RAM used by process)                                                                                  </td></tr>
      <tr><td> <b>mem_hwm_mb</b>             </td><td>High Water Mark (peak RSS since start)                                                                                            </td></tr>
      <tr><td> <b>mem_pss_mb</b>             </td><td>Proportional Set Size (shared memory counted proportionally)                                                                      </td></tr>
      <tr><td> <b>mem_private_mb</b>         </td><td>Private memory (not shared with other processes)                                                                                  </td></tr>
      <tr><td> <b>mem_shared_mb</b>          </td><td>Shared memory (CoW pages, shared libraries)                                                                                       </td></tr>
      <tr><td> <b>mem_vsize_mb</b>           </td><td>Virtual address space size                                                                                                        </td></tr>
      <tr><td> <b>swap_process_total_mb</b>  </td><td>Process pages currently swapped out                                                                                               </td></tr>
      <tr><td> <b>swap_process_delta_mb</b>  </td><td>Change in the process swap since the last cycle (negative values = "retrieval from swap")                                         </td></tr>
      <tr><td> <b>swap_sys_total_mb</b>      </td><td>total swap space of the system                                                                                                    </td></tr>
      <tr><td> <b>swap_sys_used_mb</b>       </td><td>currently used swap space of the system (all processes)                                                                           </td></tr>
      <tr><td> <b>swap_sys_in_mb</b>         </td><td>Systemwide swap-in since last cycle (pages recalled)                                                                              </td></tr>
      <tr><td> <b>swap_sys_out_mb</b>        </td><td>Systemwide swap-out since last cycle (pages evicted)                                                                              </td></tr>
      <tr><td> <b>trim_last_freed_mb</b>     </td><td>Approximate MB returned to OS by last malloc_trim call                                                                            </td></tr>
      <tr><td> <b>trim_last_run</b>          </td><td>Timestamp of last malloc_trim execution                                                                                           </td></tr>
      <tr><td> <b>trim_next_run</b>          </td><td>Timestamp of next scheduled malloc_trim execution                                                                                 </td></tr>
      <tr><td> <b>mem_drift_per_hour_mb</b>  </td><td>Indicates the projected memory growth (trend) of the FHEM process in megabytes per hour (MB/h). The value is the slope            </td></tr>
      <tr><td>                               </td><td>of a linear regression (least squares) over the resident set size (RSS) of the last two hours.                                    </td></tr>
      <tr><td>                               </td><td>Negative values indicate an actual reduction in memory. A leak is only assessed if the rise is visible in both halves             </td></tr>
      <tr><td>                               </td><td>of the history; one-time jumps are not rated as a leak.                                                                           </td></tr>
      <tr><td> <b>leak_status_raw</b>        </td><td>Unfiltered assessment of the current cycle (possible values as leak_status_weighted)                                              </td></tr>
      <tr><td> <b>leak_status_weighted</b>   </td><td>Displays the current assessment of memory leaks and fragmentation. The value is filtered: the assessment that prevailed           </td></tr>
      <tr><td>                               </td><td>within the time window defined by attribute <a href="#MemSaver-attr-leakFilterWindow">leakFilterWindow</a> is published.          </td></tr>
      <tr><td>                               </td><td>Possible values:                                                                                                                  </td></tr>
      <tr><td>                               </td><td><ul><b>initializing</b> - fewer than 3 data points are available  </ul>                                                           </td></tr>
      <tr><td>                               </td><td><ul><b>collecting_data</b> - data is being collected (no reliable trend analysis possible yet)  </ul>                             </td></tr>
      <tr><td>                               </td><td><ul><b>warming_up</b> - FHEM has been running for less than the required minimum uptime before trend analysis can start. </ul>    </td></tr>
      <tr><td>                               </td><td><ul><b>ok</b> - normal memory behavior; no alarming increase detected  </ul>                                                      </td></tr>
      <tr><td>                               </td><td><ul><b>fragmentation_cleared</b> - malloc_trim was able to successfully return a significant amount of RAM to the operating system. The increase was solely due to heap fragmentation. </ul>      </td></tr>
      <tr><td>                               </td><td><ul><b>potential_leak_warning</b> - memory is growing continuously and malloc_trim was barely able to free any memory. There may be a slow memory leak. </ul>                                     </td></tr>
      <tr><td>                               </td><td><ul><b>leak_suspected</b> - very strong memory growth trend. Strong suspicion of a memory leak in a loaded module. </ul>                                                                          </td></tr>
    </table>
  </ul>

</ul>

=end html

=begin html_DE

<a id="MemSaver"></a>
<h3>MemSaver</h3>
<ul>
  <b>Hinweis: Dieses Modul funktioniert unter Linux- und Windows-Betriebssystemen.</b><br><br>
  Gibt ungenutzte glibc-Speicherblöcke (Arenen) regelmäßig an das Betriebssystem zurück und erfasst detaillierte Speicher- sowie CPU-Messwerte aus <code>/proc</code>. <br>
  Unter Linux wird das Perl-Modul <code>FFI::Platypus</code> benötigt (<code>apt install libffi-platypus-perl</code>), unter Windows <code>Win32::API</code>.
  <br><br>

  <b>Windows</b> <br>
  Unter Windows (natives Perl) wird anstelle von <code>malloc_trim</code> das Working Set des FHEM-Prozesses geleert (<code>EmptyWorkingSet</code>).
  Dadurch wird kein Heap an das Betriebssystem zurückgegeben, die Seiten werden lediglich aus dem Working Set ausgelagert und bei Bedarf wieder geladen.
  Die Nachmessung erfolgt 15 Sekunden nach dem Aufruf (höchstens die Hälfte des Intervalls). Unterschiede zu Linux:
  <ul>
    <li>mem_rss_mb = Working Set, mem_hwm_mb = Peak Working Set, mem_private_mb = Commit Charge</li>
    <li>trim_last_freed_mb = nach dem Aufruf gemessene Verringerung des Working Sets</li>
    <li>mem_drift_per_hour_mb wird aus dem Commit Charge berechnet, da ein Leak nicht mehr angesprochenen Speicher belegt und im Working Set nicht sichtbar wäre</li>
    <li>leak_status_raw / leak_status_weighted liefern nie <b>fragmentation_cleared</b></li>
    <li>nicht verfügbar: cpu_load1, mem_shared_mb, mem_pss_mb, mem_vsize_mb, swap_process_total_mb, swap_process_delta_mb, swap_sys_in_mb, swap_sys_out_mb, swap_sys_total_mb, swap_sys_used_mb</li>
  </ul>
  <br>

  <a id="MemSaver-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MemSaver [intervall]</code><br><br>
    <code>intervall</code> — Ausführungsintervall in Sekunden (Standard: 900).<br>
    Beispiel: <code>define Saver MemSaver 900</code>
  </ul>
  <br>

  <a id="MemSaver-set"></a>
  <b>Set</b>
  <ul>
    <li><b>trimNow [Tag]</b><br>
        Löst sofort eine manuelle Ausführung von <code>malloc_trim</code> (Windows: <code>EmptyWorkingSet</code>) aus.
        Das optionale <b>Tag</b> wird mit verbose 4 ins Log geschrieben, z.B. <code>set Saver trimNow vor Backup</code>.
    </li>
  </ul>
  <br>

  <a id="MemSaver-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="MemSaver-attr-disable"></a>
    <li><b>disable</b> <br>
    Aktiviert oder deaktiviert das Modul.
    </li>
    <br>

    <a id="MemSaver-attr-leakFilterWindow"></a>
    <li><b>leakFilterWindow &lt;Sekunden&gt;</b> <br>
    Zeitfenster zur Filterung von <b>leak_status_weighted</b>. Veröffentlicht wird die im Fenster
    überwiegend aufgetretene Bewertung (nach Dauer gewichtet), der ungefilterte Wert steht in
    <b>leak_status_raw</b>. <br>
    Bei Gleichstand bleibt der letzte Status erhalten, sonst gilt der schwerwiegendere.
    Das Fenster umfasst mindestens 5 Zyklen des Intervalls, bis dahin wird der Rohwert veröffentlicht. <br>
    Technische Zustände (initializing, collecting_data, warming_up) werden nie gefiltert. <br>
    <b>0</b> schaltet den Filter ab. <br>
    (default: 1800)
    </li>
  </ul>
  <br>

  <a id="MemSaver-Readings"></a>
  <b>Readings</b>
  <ul>
    <table>
      <colgroup><col width="15%"><col width="85%"></colgroup>
      <tr><td> <b>cpu_load1</b>             </td><td>Load Average des Systems der letzten Minute: durchschnittliche Anzahl der Prozesse, die rechnen oder auf CPU bzw. I/O warten.                  </td></tr>
      <tr><td>                              </td><td>Der Wert ist von der Anzahl der CPU-Kerne abhängig: bei einem Kern entspricht 1,0 einer                                                        </td></tr>
      <tr><td>                              </td><td>vollen Auslastung, bei n Kernen erst n. Werte unter 1 sind bei einem schwach ausgelasteten System normal.                                      </td></tr>
      <tr><td> <b>cpu_usage_pct</b>         </td><td>prozentuale CPU-Auslastung des Systems über das Intervall berechnet                                                                            </td></tr>
      <tr><td> <b>fhem_start_time</b>       </td><td>Zeitstempel des FHEM-Initialisierungsendes (YYYY-MM-DD HH:MM:SS)                                                                               </td></tr>
      <tr><td> <b>fhem_uptime</b>           </td><td>lesbare Laufzeit des FHEM-Prozesses seit dem Start (z. B. "12d 4h 15m 30s")                                                                    </td></tr>
      <tr><td> <b>fhem_uptime_sec</b>       </td><td>Laufzeit des FHEM-Prozesses in absoluten Sekunden                                                                                              </td></tr>
      <tr><td> <b>mem_rss_mb</b>            </td><td>Resident Set Size (physisch vom Prozess belegter Arbeitsspeicher)                                                                              </td></tr>
      <tr><td> <b>mem_hwm_mb</b>            </td><td>High Water Mark (Maximalwert des RSS seit Prozessstart)                                                                                        </td></tr>
      <tr><td> <b>mem_pss_mb</b>            </td><td>Proportional Set Size (anteilig berechneter Shared-Memory)                                                                                     </td></tr>
      <tr><td> <b>mem_private_mb</b>        </td><td>privater Speicher (nicht mit anderen Prozessen geteilt)                                                                                        </td></tr>
      <tr><td> <b>mem_shared_mb</b>         </td><td>geteilter Speicher (Copy-on-Write Pages, Shared Libraries)                                                                                     </td></tr>
      <tr><td> <b>mem_vsize_mb</b>          </td><td>Größe des virtuellen Adressraums                                                                                                               </td></tr>
      <tr><td> <b>swap_process_total_mb</b> </td><td>aktuell ausgelagerter Speicher des FHEM-Prozesses                                                                                              </td></tr>
      <tr><td> <b>swap_process_delta_mb</b> </td><td>Änderung des Prozess-Swaps seit dem letzten Zyklus (negative Werte = "Rückholung aus Swap")                                                    </td></tr>
      <tr><td> <b>swap_sys_total_mb</b>     </td><td>gesamter Swap-Speicher des Systems                                                                                                             </td></tr>
      <tr><td> <b>swap_sys_used_mb</b>      </td><td>aktuell belegter Swap-Speicher des Systems (alle Prozesse)                                                                                     </td></tr>
      <tr><td> <b>swap_sys_in_mb</b>        </td><td>systemweit wiedereingelagerter Swap seit dem letzten Zyklus                                                                                    </td></tr>
      <tr><td> <b>swap_sys_out_mb</b>       </td><td>systemweit ausgelagerter Swap seit dem letzten Zyklus                                                                                          </td></tr>
      <tr><td> <b>trim_last_freed_mb</b>    </td><td>ungefähre Speichermenge in MB, die beim letzten malloc_trim an das OS zurückgegeben wurde                                                      </td></tr>
      <tr><td> <b>trim_last_run</b>         </td><td>Zeitstempel der letzten Ausführung von malloc_trim                                                                                             </td></tr>
      <tr><td> <b>trim_next_run</b>         </td><td>Zeitstempel der nächsten geplanten Ausführung                                                                                                  </td></tr>
      <tr><td> <b>mem_drift_per_hour_mb</b> </td><td>Gibt den hochgerechneten Speicherzuwachs (Trend) des FHEM-Prozesses in Megabyte pro Stunde (MB/h) an. Der Wert ist die Steigung                </td></tr>
      <tr><td>                              </td><td>einer linearen Regression (Methode der kleinsten Quadrate) über den Resident Set Size (RSS) der letzten zwei Stunden.                          </td></tr>
      <tr><td>                              </td><td>Negativwerte bedeuten eine echte Speicherreduzierung. Ein Leak wird nur bewertet, wenn der Anstieg in beiden Hälften                           </td></tr>
      <tr><td>                              </td><td>der Historie erkennbar ist; Einmalsprünge werden nicht als Leak bewertet.                                                                      </td></tr>
      <tr><td> <b>leak_status_raw</b>       </td><td>ungefilterte Bewertung des aktuellen Zyklus (mögliche Werte wie leak_status_weighted)                                                          </td></tr>
      <tr><td> <b>leak_status_weighted</b>  </td><td>Zeigt die aktuelle Bewertung bezüglich Speicher-Leaks und Fragmentierung an. Der Wert ist gefiltert: Veröffentlicht wird                       </td></tr>
      <tr><td>                              </td><td>die Bewertung, die im Zeitfenster des Attributs <a href="#MemSaver-attr-leakFilterWindow">leakFilterWindow</a> überwiegend aufgetreten ist.    </td></tr>
      <tr><td>                              </td><td>Mögliche Werte:                                                                                                                                </td></tr>
      <tr><td>                              </td><td><ul><b>initializing</b> - es sind noch weniger als 3 Messwerte vorhanden   </ul>                                                               </td></tr>
      <tr><td>                              </td><td><ul><b>collecting_data</b> - Daten werden gesammelt (noch keine zuverlässige Trendanalyse möglich)  </ul>                                      </td></tr>
      <tr><td>                              </td><td><ul><b>warming_up</b> - FHEM läuft seit weniger als der vorgegebenen Mindestlaufzeit, bevor die Trendanalyse starten kann. </ul>               </td></tr>
      <tr><td>                              </td><td><ul><b>ok</b> - normales Speicherverhalten, kein bedrohlicher Anstieg erkennbar  </ul>                                                         </td></tr>
      <tr><td>                              </td><td><ul><b>fragmentation_cleared</b> - malloc_trim konnte erfolgreich signifikant RAM an das Betriebssystem zurückgeben. Der Anstieg lag nur an Heap-Fragmentierung. </ul>      </td></tr>
      <tr><td>                              </td><td><ul><b>potential_leak_warning</b> - Der Speicher wächst kontinuierlich und malloc_trim konnte kaum Speicher freigeben. Es könnte ein langsames Memory-Leak vorliegen. </ul> </td></tr>
      <tr><td>                              </td><td><ul><b>leak_suspected</b> - Sehr starker Speicherspreizungs-Trend. Dringender Verdacht auf ein Speicherleck in einem geladenen Modul. </ul>                                 </td></tr>
    </table>
  </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 98_MemSaver.pm
{
  "abstract": "Periodically releases unused glibc memory arenas to the OS and tracks CPU/RAM usage",
  "x_lang": {
    "de": {
      "abstract": "Gibt ungenutzte glibc-Speicherarenen periodisch an das OS zur&uuml;ck und erfasst CPU/RAM-Werte"
    }
  },
  "keywords": [
    "memory",
    "malloc",
    "glibc",
    "performance",
    "swap",
    "rss",
    "heap",
    "arena",
    "cpu",
    "load"
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
        "POSIX": 0,
        "feature": 0,
        "GPUtils": 0,
        "FFI::Platypus": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
        "Win32::API": 0
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
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/98_MemSaver.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/98_MemSaver.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut