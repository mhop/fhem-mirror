# $Id:$
####################################################################################################
#
#   A FHEM Perl module to retrieve data from an APC uninterruptible power supply (UPS) via APCUPSD.
#
#   This file is part of fhem.
#
#   Fhem is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 2 of the License, or
#   (at your option) any later version.
#
#   Fhem is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package FHEM::apcstatus;

use strict;
use warnings;
use POSIX;
#use FHEM::Meta;

# wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsTimestamp
          defs
          readingFnAttributes
          modules
          Log3
          CommandAttr
          attr
          AttrVal
          ReadingsVal
          Value
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          Debug
          InternalTimer
          RemoveInternalTimer)
    );
}

# _Export - Export references to main context using a different naming schema
sub _Export {
    no strict qw/refs/;    ## no critic
    my $pkg  = caller(0);
    my $main = $pkg;
    $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
    foreach (@_) {
        *{ $main . $_ } = *{ $pkg . '::' . $_ };
    }
}

#-- Export to main context with different name
_Export(
    qw(
      Initialize
      )
);

sub Initialize($) {

    my ($hash) = @_;

    $hash->{DefFn}      = "FHEM::apcstatus::Define";
#    $hash->{SetFn}      = "FHEM::apcstatus::Set";
#    $hash->{GetFn}      = "FHEM::apcstatus::Get";
#    $hash->{NotifyFn}   = "FHEM::apcstatus::Notify";
    $hash->{UndefFn}    = "FHEM::apcstatus::Undef";
#    $hash->{DeleteFn}   = "FHEM::apcstatus::Delete";
#    $hash->{ShutDownFn} = "FHEM::apcstatus::ShutDown";
    $hash->{AttrFn}     = "FHEM::apcstatus::Attr";
    $hash->{AttrList}   =
        "disable:1,0 "
      . "disabledForIntervals "
#      . "upgradeListReading:1 "
#      . "distupgrade:1 "
      . $readingFnAttributes;

#    foreach my $d ( sort keys %{ $modules{AptToDate}{defptr} } ) {
#        my $hash = $modules{AptToDate}{defptr}{$d};
#        $hash->{VERSION} = $VERSION;
#    }

Debug ${__PACKAGE__.'::Test'};
    
#    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define() {}
sub Undef() {}
sub Attr() {}

1;

=for comment
package main;

use strict;
use warnings;

my $apcaccess = "/sbin/apcaccess";


sub APCUPSD_Initialize($) {
  my ($hash) = @_;

  #$hash->{internals}{interfaces}= "temperature:battery";

  $hash->{DefFn}    = "APCUPSD_Define";
  $hash->{UndefFn}  = "APCUPSD_Undef";

  $hash->{AttrList} = "disable:0,1 asReadings ".$readingFnAttributes;
}


sub APCUPSD_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> APCUPSD [interval [<host>[:<port>]]]"  if ( @a < 2 or @a > 4 );

  if ( ! -e $apcaccess ) {
    return "ERROR: $apcaccess does not exist. Please install APCUPSD.";
  }
  if ( ! -x $apcaccess ) {
    return "ERROR: $apcaccess is not executable.";
  }

  my $name = $a[0];

  my $interval = 60;
  if ( int(@a)>=3 ) { $interval = $a[2]; }
  if ( $interval < 10 ) { $interval = 10; }

  my $dev = $a[3];
  if ( defined $dev ) {
     $dev .= ":3551" if ( $dev !~ m/:/ );
  } else {
     $dev = "localhost:3551";
  }

  $hash->{HOST} = $dev;
  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;
  $hash->{LOWBATT} = 20;

  $attr{$name}{asReadings} = "BATTV,BCHARGE,LINEV,LOADPCT,OUTPUTV,TIMELEFT,LASTXFER";

  APCUPSD_PollTimer($hash);

  return undef;
}


sub APCUPSD_Undef($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}


sub APCUPSD_RetrieveData($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my ($cmd, $val);
  $cmd = $apcaccess." status ".$hash->{HOST}."  2>&1";
  $val = `$cmd`;

  if ( $val =~ m/^Error/ | ! length($val) ) {
    Log3 $hash, 1, $val;
    readingsSingleUpdate($hash, 'state', 'ERROR', 1);
    return $val;
  }

  my @lines = split /\n/, $val;

  no warnings 'numeric';

  foreach my $line (@lines) {
    if ( $line =~ m/^(.+?)\s*:\s*(.+?)\s*$/ ) {
      $hash->{helper}{$1} = $2;

      if ( $1 eq 'STATUS' ) {
        readingsSingleUpdate($hash, 'state', $2, 1);
      }
      if ( $1 eq 'ITEMP' ) {
        readingsSingleUpdate($hash, 'temperature', 0+$2, 1);
      }
      if ( $1 eq 'BCHARGE' ) {
        readingsSingleUpdate($hash, 'battery', $2 > $hash->{LOWBATT} ? 'ok' : 'low', 1);
      }
      if ( $1 eq 'MODEL' ) {
        $hash->{MODEL} = $2;
      }
      if ( $1 eq 'SERIALNO' ) {
        $hash->{SERIALNO} = $2;
      }
      if ( $1 eq 'BATTDATE' ) {
        $hash->{BATTDATE} = $2;
      }
    }
  }

  readingsBeginUpdate($hash);
  foreach (split (',', $attr{$name}{asReadings})) {
    s/^\s+//;
    s/\s+$//;
    $hash->{helper}{$_} =~ m/^([\-\d\.]*)(.*)$/;
    if ( length($1) > 0 ) {
      readingsBulkUpdate($hash, lc($_), 0+$1) if defined $hash->{helper}{$_};
    } else {
      readingsBulkUpdate($hash, lc($_), $2) if defined $hash->{helper}{$_};
    }
  }
  readingsEndUpdate($hash, 1);

  return undef;
}


sub APCUPSD_PollTimer($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "APCUPSD_PollTimer", $hash, 0);
  return if ( AttrVal($name, "disable", 0) > 0 );

  APCUPSD_RetrieveData($hash);
}


1;
=cut

=pod
=begin html

<a name="APCUPSD"></a>
<h3>APCUPSD</h3>
<ul>
  APCUPSD (<a href="http://www.apcupsd.com/">www.apcupsd.com</a>) provides support for uninterruptible power supplies (UPS) manufactured by APC. This module provides access to a APCUPSD server for data readout (eg status, remaining time, input voltage, temperature, etc. ).<br>

  <br><br>

  <a name=APCUPSDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;devicename&gt; APCUPSD [&lt;intervall&gt; [&lt;host&gt;[:&lt;port&gt;]]</code><br>
    <br>
    &lt;intervall&gt; is the interval of data queries to APCUPSD. Default is <code>60</code> seconds.<br>
    &lt;host&gt; is the hostname or IP address of the APCUPSD server. Default is <code>localhost</code>.<br>
    :&lt;port&gt; is the TCP port APCUPSD server is listening on. Default is <code>:3551</code>.<br>
    <br>
    For the function of this module a local installation of APCUPSD package is required. The apcaccess tool is used for data access.
    The apcupsd service may not run on the local FHEM system.
    Network access to external APCUPSD hosts is possible. A local and networked mixed operation is supported too.<br>
    <br>
    If multiple UPS systems are connected to a single host multiple APCUPSD instances on different TCP ports have to be configured there.<br>
    To set up such a "multiple UPS system" please note <a href="http://www.apcupsd.com/manual/manual.html#controlling-multiple-upses-on-one-machine">www.apcupsd.com/manual/manual.html#controlling-multiple-upses-on-one-machine</a>.<br>
    <br><br>
    Examples: <br>
    <code>define Usv1 APCUPSD</code><br>
    <code>define Usv2 APCUPSD 60 localhost:3552</code><br>
    <code>define Usv3 APCUPSD 60 192.168.0.100:3551</code><br>
  </ul>
  <br>

  <a name="APCUPSDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li><br>
    <li><a name="APCUPSD_asReadings">asReadings</a><br>
        Comma-separated list of UPS values ​​to be used as readings. Default is <code>BATTV,BCHARGE,LINEV,LOADPCT,OUTPUTV,TIMELEFT,LASTXFER</code>.<br>
        Available values ​​can be listed using <code>list &lt;devicename&gt;</code>.<br>
        All availible readings for specific UPS model are listed in the section following "Helper:".<br>
        Example:<br>
        <code>attr &lt;name&gt; asReadings TONBATT,NUMXFERS,LINEFREQ</code></li><br>
  </ul>

  <a name="APCUPSDreadings"></a>
  <b>Readings</b>
  <ul>
    <li><a href="APCUPSD_battery">battery</a><br>
    Battery level of the UPS. "ok" if > 20%, else "low" (if availible)</li><br>
    <li><a href="APCUPSD_state">state</a><br>
    The state of the UPS (ONLINE, ON BATTERY, ...)</li><br>
    <li><a href="APCUPSD_temperature">temperature</a><br>
    Internal system temperature (if availible) in degrees Celsius</li><br>
    <li>and the configured parameters by asReadings</li><br>
  </ul>
</ul>

=end html

=begin html_DE

<a name="APCUPSD"></a>
<h3>APCUPSD</h3>
<ul>
  APCUPSD (<a href="http://www.apcupsd.com/">www.apcupsd.com</a>) bietet Unterstützung für unterbrechungsfreie Stromversorgungen (USV) von APC. Dieses Modul ermöglicht den Zugriff auf einen APCUPSD-Server, womit man Daten auslesen kann (z.B. den Status, Restlaufzeit, Eingangsspannung, Temperatur usw.).<br>

  <br><br>

  <a name=APCUPSDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;devicename&gt; APCUPSD [&lt;intervall&gt; [&lt;host&gt;[:&lt;port&gt;]]</code><br>
    <br>
    &lt;intervall&gt; ist das Poll-Intervall mit dem Daten von APCUPSD abgefragt werden. Default ist <code>60</code> Sekunden.<br>
    &lt;host&gt; ist der Hostname oder die IP-Adresse des APCUPSD-Servers. Default ist <code>localhost</code>.<br>
    :&lt;port&gt; ist der TCP-Port auf den die APCUPSD-Instanz konfiguriert wurde. Default ist <code>:3551</code>.<br>
    <br>
    Für die Funktion dieses Moduls wird eine lokale Installation des APCUPSD-Pakets benötigt da das darin enthaltene apcaccess-Tool für den Datenzugriff genutzt wird.
    Der ebenfalls enthaltene APCUPSD-Dienst muss hingegen nicht zwingend auf dem FHEM-System laufen.
    Der Netzwerkzugriff auf externe APCUPSD-Hosts ist möglich. Ebenso ein lokaler und vernetzter Mischbetrieb.<br>
    <br>
    Sollen mehrere USV-Systeme an einem Host von APCUPSD überwacht werden sind dort mehrere APCUPSD-Instanzen auf verschiedenen TCP-Ports notwendig.<br>
    Zur Einrichtung eines solchen "Mehrfach-USV-Systems" bitte <a href="http://www.apcupsd.com/manual/manual.html#controlling-multiple-upses-on-one-machine">www.apcupsd.com/manual/manual.html#controlling-multiple-upses-on-one-machine</a> beachten.<br>
    <br><br>
    Beispiele: <br>
    <code>define Usv1 APCUPSD</code><br>
    <code>define Usv2 APCUPSD 60 localhost:3552</code><br>
    <code>define Usv3 APCUPSD 60 192.168.0.100:3551</code><br>
  </ul>
  <br>

  <a name="APCUPSDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li><br>
    <li><a name="APCUPSD_asReadings">asReadings</a><br>
        Mit Kommata getrennte Liste der USV-Werte, die als Readings verwendet werden sollen. Der Standardwert lautet <code>BATTV,BCHARGE,LINEV,LOADPCT,OUTPUTV,TIMELEFT,LASTXFER</code>.<br>
        Verfügbare Werte lassen sich mittels <code>list &lt;devicename&gt;</code> darstellen.<br>
        Die vom jeweiligen USV-Modell auslesbaren Parameter werden dort im Abschnitt "Helper:" gelistet.<br>
        Beispiel:<br>
        <code>attr &lt;name&gt; asReadings TONBATT,NUMXFERS,LINEFREQ</code></li><br>
  </ul>

  <a name="APCUPSDreadings"></a>
  <b>Readings</b>
  <ul>
    <li><a href="APCUPSD_battery">battery</a><br>
    Akkuladestand der USV. "ok" wenn > 20%, sonst "low" (wenn verfügbar)</li><br>
    <li><a href="APCUPSD_state">state</a><br>
    Der Zustand der USV (ONLINE, ON BATTERY, ...)</li><br>
    <li><a href="APCUPSD_temperature">temperature</a><br>
    Interne Systemtemperatur (wenn verfügbar) in Grad Celsius</li><br>
    <li>sowie die unter asReadings konfigurierten Parameter</li><br>
  </ul>
</ul>

=end html_DE
=cut

