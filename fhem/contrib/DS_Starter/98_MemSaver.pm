########################################################################################################################
# $Id: 98_MemSaver.pm $
#########################################################################################################################
#       98_MemSaver.pm
#
#       (c) 2026 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#       FHEM module for regularly returning unused glibc memory blocks
#       to the OS and for recording memory & CPU readings.
#
#       Requires: FFI::Platypus (apt install libffi-platypus-perl)
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
  "1.1.0"  => "03.10.2026  cpu_load, cpu_usage_pct und trim_next_run integriert ",
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
        readingFnAttributes
        RemoveInternalTimer
    ));
}

GP_Export( qw(
    Initialize
));

##############################################################################
sub Initialize {
  my ($hash) = @_;

  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undef;
  $hash->{AttrFn}     = \&Attr;
  $hash->{AttrList}   = "disable:0,1 ".
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
      unless $interval =~ m/^\d+$/x && $interval > 0;

  $hash->{INTERVAL} = $interval;
  $hash->{VERSION}  = '1.1.0';
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                        # Modul Meta.pm nicht vorhanden

  use version 0.77; our $VERSION = moduleVersion ($hash, \%vNotesIntern);       # Versionsinformationen setzen

  readingsSingleUpdate ($hash, 'state', 'active', 1);

  scheduleRun ($hash, 5);                                                       # Erster Lauf nach 5 Sekunden

return;
}

##############################################################################
sub Undef {
  my ($hash) = @_;

  RemoveInternalTimer ($hash, \&run);

return;
}

##############################################################################
sub Attr {
  my ($cmd, $name, $attr, $val) = @_;
  my $hash = $main::defs{$name};

  if ($attr eq 'disable') {
      if ($cmd eq 'set' && ($val // '') eq '1') {
          RemoveInternalTimer  ($hash, \&run);
          readingsSingleUpdate ($hash, 'state', 'disabled', 1);
      }
      else {
          readingsSingleUpdate ($hash, 'state', 'active', 1);
          scheduleRun          ($hash, 1);
      }
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
  my $name   = $hash->{NAME};
  my %m;

  # --- 1. RAM / Proc Status ---
  if (open my $fh, '<', "/proc/$$/status") {
      while (<$fh>) {
          $m{VmRSS}  = $1 if /^VmRSS:\s+(\d+)/x;
          $m{VmHWM}  = $1 if /^VmHWM:\s+(\d+)/x;
          $m{VmSize} = $1 if /^VmSize:\s+(\d+)/x;
      }
      close $fh;
  }
  else {
      Log3 ($name, 2, "$name - MemSaver: cannot open /proc/$$/status: $!");
      return;
  }

  # /proc/$$/smaps_rollup
  if (open my $fh, '<', "/proc/$$/smaps_rollup") {
      while (<$fh>) {
          $m{Pss}           = $1 if /^Pss:\s+(\d+)/x;
          $m{Shared_Clean}  = $1 if /^Shared_Clean:\s+(\d+)/x;
          $m{Shared_Dirty}  = $1 if /^Shared_Dirty:\s+(\d+)/x;
          $m{Private_Clean} = $1 if /^Private_Clean:\s+(\d+)/x;
          $m{Private_Dirty} = $1 if /^Private_Dirty:\s+(\d+)/x;
          $m{Swap}          = $1 if /^Swap:\s+(\d+)/x;
      }
      close $fh;
  }

  # --- 2. Systemweite Swap-Aktivität ---
  my %vmstat_cur;
  if (open my $fh, '<', '/proc/vmstat') {
      while (<$fh>) {
          $vmstat_cur{pswpin}  = $1 if /^pswpin\s+(\d+)/x;
          $vmstat_cur{pswpout} = $1 if /^pswpout\s+(\d+)/x;
      }
      close $fh;
  }

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
  my $prev_proc_swap  = $hash->{HELPER}{PREV_PROC_SWAP} // ($m{Swap} // 0);
  my $proc_swap_delta = ($m{Swap} // 0) - $prev_proc_swap;
  $hash->{HELPER}{PREV_PROC_SWAP} = ($m{Swap} // 0);

  # --- 3. CPU Load & Usage ---
  my $load1 = 0;
  if (open my $fh_load, '<', '/proc/loadavg') {
      my $line = <$fh_load>;
      close $fh_load;
      ($load1) = $line =~ /^([\d\.]+)/;
  }

  my ($cpu_idle, $cpu_total);
  if (open my $fh_stat, '<', '/proc/stat') {
      my $line = <$fh_stat>;
      close $fh_stat;
      my @v = split /\s+/, $line;
      $cpu_idle  = ($v[4] || 0) + ($v[5] || 0);
      $cpu_total = 0;
      $cpu_total += $_ for @v[1..8];
  }

  my $cpu_pct = 0;
  if (defined $hash->{HELPER}{LAST_CPU_IDLE} && defined $hash->{HELPER}{LAST_CPU_TOTAL}) {
      my $diff_total = $cpu_total - $hash->{HELPER}{LAST_CPU_TOTAL};
      my $diff_idle  = $cpu_idle  - $hash->{HELPER}{LAST_CPU_IDLE};
      if ($diff_total > 0) {
          $cpu_pct = sprintf '%.2f', (1 - ($diff_idle / $diff_total)) * 100;
      }
  }
  $hash->{HELPER}{LAST_CPU_IDLE}  = $cpu_idle;
  $hash->{HELPER}{LAST_CPU_TOTAL} = $cpu_total;

  # --- Readings schreiben ---
  my $fmt = sub { sprintf '%.2f', ($_[0] // 0) / 1024 };

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'mem_private_mb',       $fmt->( ($m{Private_Clean} // 0) + ($m{Private_Dirty} // 0) ));  
  readingsBulkUpdate  ($hash, 'mem_shared_mb',        $fmt->( ($m{Shared_Clean}  // 0) + ($m{Shared_Dirty}  // 0) ));
  readingsBulkUpdate  ($hash, 'mem_rss_mb',           $fmt->($m{VmRSS}));                                      # Resident Set Size
  readingsBulkUpdate  ($hash, 'mem_hwm_mb',           $fmt->($m{VmHWM}));                                      # High Water Mark (Peak seit Start)
  readingsBulkUpdate  ($hash, 'mem_pss_mb',           $fmt->($m{Pss}));                                        # Proportional Set Size
  readingsBulkUpdate  ($hash, 'mem_vsize_mb',         $fmt->($m{VmSize}));                                     # Virtueller Adressraum
  readingsBulkUpdate  ($hash, 'swap_process_total_mb',$fmt->($m{Swap}));                                       # Ausgelagerter Prozess-Swap gesamt
  readingsBulkUpdate  ($hash, 'swap_process_delta_mb',$fmt->($proc_swap_delta));                               # Swap-Delta seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'swap_sys_in_mb',       $swapin);                                                # Systemweiter Swap-In seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'swap_sys_out_mb',      $swapout);                                               # Systemweiter Swap-Out seit letztem Zyklus
  readingsBulkUpdate  ($hash, 'cpu_load1',            sprintf('%.2f', $load1));                                # Load Average (1 Min)
  readingsBulkUpdate  ($hash, 'cpu_usage_pct',        $cpu_pct);                                               # CPU-Auslastung über das Intervall
  readingsBulkUpdate  ($hash, 'state',                'active');
  readingsEndUpdate   ($hash, 1);
  
  my $ram = join ", ",
      "RSS="         . $fmt->($m{VmRSS}),
      "HWM="         . $fmt->($m{VmHWM}),
      "PSS="         . $fmt->($m{Pss}),
      "Priv="        . $fmt->($m{Private_Clean} + $m{Private_Dirty}),
      "Shared="      . $fmt->($m{Shared_Clean}  + $m{Shared_Dirty}),
      "ProcSwapTot=" . $fmt->($m{Swap}),                        		# Prozess-Swap MB
      "ProcSwapDta=" . $fmt->($proc_swap_delta),						# Prozess-Swap-Delta MB
      "SysSwapIn="   . $swapin,    									    # MB systemweit seit letztem Messzyklus eingelagert
      "SysSwapOut="  . $swapout,   									    # MB systemweit seit letztem Messzyklus ausgelagert
      "VSize="       . $fmt->($m{VmSize});

  Log3 ($name, 4, "$name - RAM/CPU: " . $ram . sprintf(", Load1=%.2f, CPU_Usage=%.2f%%", $load1, $cpu_pct));

return;
}

##############################################################################
#  malloc_trim(0): glibc auffordern, freie Arenen ans OS zurückzugeben
##############################################################################
sub mallocTrim {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  return unless $^O eq 'linux';

  state $malloc_trim_fn;
  state $has_platypus;

  if (!defined $has_platypus) {
      $has_platypus = eval {
          require FFI::Platypus;
          $malloc_trim_fn = FFI::Platypus->new(lib => undef)->function(malloc_trim => ['size_t'] => 'int');
          1;
      };

      if (!$has_platypus) {
          Log3 ($name, 2, "$name - MemSaver: FFI::Platypus not available — malloc_trim disabled. Install with: 'apt install libffi-platypus-perl' ");
      }
  }

  return unless $has_platypus && $malloc_trim_fn;

  my $rss_before = _currentRssMb();
  $malloc_trim_fn->(0);
  my $rss_after  = _currentRssMb();
  my $freed      = sprintf '%.2f', $rss_before - $rss_after;

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, 'trim_last_freed_mb', $freed);
  readingsBulkUpdate  ($hash, 'trim_last_run',       FmtDateTime(gettimeofday()));
  readingsEndUpdate   ($hash, 1);

  Log3 ($name, 4,
      "$name - MemSaver: malloc_trim(0) executed, freed ~${freed} MB");

return;
}

##############################################################################
sub _currentRssMb {
  my $rss = 0;

  if (open my $fh, '<', "/proc/$$/status") {
      while (<$fh>) { $rss = $1 if /^VmRSS:\s+(\d+)/x }
      close $fh;
  }
    
return $rss / 1024;
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
      
      if ($modules{$type}{META}{x_version}) {                                               # {x_version} nur gesetzt wenn $Id: xxxxx.pm 29571 2025-01-25 13:45:02Z xxxxxx $ im Kopf komplett! vorhanden
          $modules{$type}{META}{x_version} =~ s/1\.1\.0/$v/gx;
      } 
      else {
          $modules{$type}{META}{x_version} = $v; 
      }
      
      FHEM::Meta::SetInternals ($hash);                                                     # FVERSION wird gesetzt ( nur gesetzt wenn $Id: xxxxx.pm 29571 2025-01-25 13:45:02Z xxxxxx $ im Kopf komplett! vorhanden )
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
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersion {
  my ($sseq, @versions) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./x]} @versions;
             
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./x} @versions;
  
  if ($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

1;

=pod
=item helper
=item summary    Periodically releases unused glibc memory arenas to the OS and tracks CPU/RAM usage
=item summary_DE Gibt ungenutzte glibc-Speicherarenen periodisch an das OS zur&uuml;ck und erfasst CPU/RAM-Werte

=begin html

<a id="MemSaver"></a>
<h3>MemSaver</h3>
<ul>
  Regularly returns unused glibc memory blocks to the operating system and collects memory & CPU usage data from <code>/proc</code>.
  Requires <code>FFI::Platypus</code> (<code>apt install libffi-platypus-perl</code>).
  <br><br>

  <a id="MemSaver-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MemSaver [interval]</code><br><br>
    <code>interval</code> — run interval in seconds (default: 900).<br>
    Example: <code>define Saver MemSaver 900</code>
  </ul>
  <br>

  <a id="MemSaver-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="MemSaver-attr-disable"></a>
    <li>disable <br>
    Enables and disables the module.    
    </li>
  </ul>
  <br>

  <a id="MemSaver-Readings"></a>
  <b>Readings</b>
  <ul>
    <li>cpu_load1 - System load average (1 minute)</li>
    <li>cpu_usage_pct - System CPU usage in % calculated over the interval</li>
    <li>mem_rss_mb - Resident Set Size (physical RAM used by process)</li>
    <li>mem_hwm_mb - High Water Mark (peak RSS since start)</li>
    <li>mem_pss_mb - Proportional Set Size (shared memory counted proportionally)</li>
    <li>mem_private_mb - Private memory (not shared with other processes)</li>
    <li>mem_shared_mb - Shared memory (CoW pages, shared libraries)</li>
    <li>mem_vsize_mb - Virtual address space size</li>
    <li>swap_process_total_mb - Process pages currently swapped out</li>
    <li>swap_process_delta_mb - Change in process swap since last cycle</li>
    <li>swap_sys_in_mb - Systemwide swap-in since last cycle (pages recalled)</li>
    <li>swap_sys_out_mb - Systemwide swap-out since last cycle (pages evicted)</li>
    <li>trim_last_freed_mb - Approximate MB returned to OS by last malloc_trim call</li>
    <li>trim_last_run - Timestamp of last malloc_trim execution</li>
    <li>trim_next_run - Timestamp of next scheduled malloc_trim execution</li>
  </ul>
</ul>

=end html

=begin html_DE

<a id="MemSaver"></a>
<h3>MemSaver</h3>
<ul>
  Gibt ungenutzte glibc-Speicherbl&auml;cke (Arenen) regelm&auml;&szlig;ig an das Betriebssystem zur&uuml;ck und erfasst detaillierte Speicher- sowie CPU-Messwerte aus <code>/proc</code>.
  Erfordert das Perl-Modul <code>FFI::Platypus</code> (<code>apt install libffi-platypus-perl</code>).
  <br><br>

  <a id="MemSaver-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MemSaver [intervall]</code><br><br>
    <code>intervall</code> — Ausf&uuml;hrungsintervall in Sekunden (Standard: 900).<br>
    Beispiel: <code>define Saver MemSaver 900</code>
  </ul>
  <br>

  <a id="MemSaver-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="MemSaver-attr-disable"></a>
    <li>disable <br>
    Aktiviert oder deaktiviert das Modul.
    </li>
  </ul>
  <br>

  <a id="MemSaver-Readings"></a>
  <b>Readings</b>
  <ul>
    <li>cpu_load1 - Systemauslastung (Load Average der letzten 1 Minute)</li>
    <li>cpu_usage_pct - Prozentuale CPU-Auslastung des Systems über das Intervall berechnet</li>
    <li>mem_rss_mb - Resident Set Size (physisch vom Prozess belegter Arbeitsspeicher)</li>
    <li>mem_hwm_mb - High Water Mark (Maximalwert des RSS seit Prozessstart)</li>
    <li>mem_pss_mb - Proportional Set Size (anteilig berechneter Shared-Memory)</li>
    <li>mem_private_mb - Privater Speicher (nicht mit anderen Prozessen geteilt)</li>
    <li>mem_shared_mb - Geteilter Speicher (Copy-on-Write Pages, Shared Libraries)</li>
    <li>mem_vsize_mb - Gr&ouml;&szlig;e des virtuellen Adressraums</li>
    <li>swap_process_total_mb - Aktuell ausgelagerter Speicher des FHEM-Prozesses</li>
    <li>swap_process_delta_mb - &Auml;nderung des Prozess-Swaps seit dem letzten Zyklus</li>
    <li>swap_sys_in_mb - Systemweit wiedereingelagerter Swap seit dem letzten Zyklus</li>
    <li>swap_sys_out_mb - Systemweit ausgelagerter Swap seit dem letzten Zyklus</li>
    <li>trim_last_freed_mb - Ungef&auml;hre Speichermenge in MB, die beim letzten malloc_trim an das OS zur&uuml;ckgegeben wurde</li>
    <li>trim_last_run - Zeitstempel der letzten Ausf&uuml;hrung von malloc_trim</li>
    <li>trim_next_run - Zeitstempel der n&auml;chsten geplanten Ausführung</li>
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
  "version": "v1.1.0",
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