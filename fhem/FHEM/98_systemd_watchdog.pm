###############################################################################
#
#  Copyright notice
#
#  (c)  2018 Alexander Schulz
#       2020 Christoph 'knurd' Morrison
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
###############################################################################

# $Id$

package main;

use strict;
use warnings;
use POSIX;
use Time::HiRes qw(gettimeofday);
use Socket;

sub watchdog_client_NotifySystemD($$);
sub watchdog_client_Stop($);
sub watchdog_client_Start($);
sub watchdog_client_ProcessTimer(@);
sub watchdog_client_IsWDAvailable($);

sub systemd_watchdog_Initialize($) {
  my ($hash) = @_;

  # Consumer
  $hash->{DefFn}      = "watchdog_client_Define";
  $hash->{UndefFn}    = "watchdog_client_Undefine";
  $hash->{ShutdownFn} = "watchdog_client_Shutdown";
  $hash->{NotifyFn}   = "watchdog_client_Notify";

  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Initialize");
  RemoveInternalTimer($hash);

  return undef;
}

sub watchdog_client_IsWDAvailable($) {
  my ( $hash ) = @_;
  #return 1; # TODO XXX TEST
  return defined($hash->{'.systemd'});
}

sub watchdog_client_Define($$) {
  my ( $hash, $def ) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Define");
  my $name = $hash->{NAME};

  # prevent multiple instances
  my @devices = devspec2array("TYPE=watchdog_client");
  foreach my $dev (@devices) {
    if($dev ne $name) {
      return "only one instance is allowed";
    }
  }
  
  # remove old timer
  RemoveInternalTimer($hash);

  # check systemd watchdog available
  my $sname = $ENV{NOTIFY_SOCKET};
  if(defined($sname)) {
    $hash->{'systemd-watchdog'}="available";
    $hash->{'.systemd'}=1;
    Log3($hash->{NAME},4,"Watchdog Client: systemd-watchdog available. starting watchdog client");
  } else {
    $hash->{'systemd-watchdog'}="not available";
    $hash->{'.systemd'}=undef;
    Log3($hash->{NAME},1,"Watchdog Client: systemd watchdog is not available. Module inactiv.");
  }
  # Initialize
  watchdog_client_Start($hash);
  return undef;
}

sub watchdog_client_Undefine($) {
  my ($hash) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Undefine");
  # Clean up
  watchdog_client_Stop($hash);
  return undef;
}

sub watchdog_client_Shutdown($) {
  my ($hash) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Shutdown");
  return undef unless defined $hash->{'.initialized'};
  # Shutdown => Deaktivate watchdog
  my $name = $hash->{NAME};
  Log3($name,2,"Watchdog Client: Shutting down");
  watchdog_client_Stop($hash);
  return undef;
}

sub watchdog_client_Notify($$) {
  my ($hash,$dev) = @_;
  #Log3($hash->{NAME},1,"Watchdog Client: Debug: watchdog_client_Notify: --- ");
  if( $dev->{NAME} eq "global" ) {
    # if( grep(m/^INITIALIZED$/, @{$events}) ) {
    #   Log3($hash->{NAME},1,"Watchdog Client: Debug: watchdog_client_Notify: INITIALIZED");
    #   watchdog_client_Start($hash) unless defined $hash->{'.initialized'};
    #   return undef;
    # } elsif( grep(m/^REREADCFG$/, @{$events}) ) {
    #   #
    #   return undef;
    # }
    if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
      #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Notify: GLOBAL");
      watchdog_client_Start($hash) unless defined $hash->{'.initialized'};
    }
  }
}

sub watchdog_client_ProcessTimer(@) {
  my ($hash) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_ProcessTimer");
  # Reset watchdog
  watchdog_client_NotifySystemD($hash, "WATCHDOG=1\n");

  my $sleep = $hash->{'sleep-time'};
  $sleep = 30 unless defined $sleep;
  my $now = gettimeofday();
  my $next = int($now) + $sleep;
  InternalTimer($next, 'watchdog_client_ProcessTimer', $hash, 0);
  readingsSingleUpdate($hash,"next",FmtTime($next),1);
}

sub watchdog_client_Start($) {
  my ($hash) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Start");
  unless ($main::init_done) {
    return if $hash->{'.firsttime'};
    watchdog_client_NotifySystemD($hash, "STATUS=starting\n");
    watchdog_client_NotifySystemD($hash, "MAINPID=$$\n");
    readingsSingleUpdate($hash,"state","starting",1);
    $hash->{'.firsttime'}=1;
    return;
  }
  return if $hash->{'.initialized'};
  
  unless (watchdog_client_IsWDAvailable($hash)) {
    Log3($hash->{NAME},2,"Watchdog Client: no systemd watchdog available");
    readingsSingleUpdate($hash,"state","inactiv",1);
    readingsSingleUpdate($hash,"next","none",1);
    return;
  }

  my $sleep = ($ENV{WATCHDOG_USEC} // 120000000) / 4 / 1000000;
  $hash->{'sleep-time'} = $sleep;
  $hash->{'.initialized'} = 1;

  my $next = int(gettimeofday()) + 1; 
  InternalTimer($next, 'watchdog_client_ProcessTimer', $hash, 0);

  # System ready
  watchdog_client_NotifySystemD($hash, "READY=1\n");
  watchdog_client_NotifySystemD($hash, "MAINPID=$$\n");
  watchdog_client_NotifySystemD($hash, "STATUS=started\n");

  Log3($hash->{NAME},2,"Watchdog Client: initialized");
  readingsSingleUpdate($hash,"state","active",1);
}

sub watchdog_client_Stop($) {
  my ($hash) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_Stop");
  watchdog_client_NotifySystemD($hash, "STOPPING=1\n");
  watchdog_client_NotifySystemD($hash, "STATUS=stopping\n");
  RemoveInternalTimer($hash);
  $hash->{'.initialized'} = 0;
  my $name = $hash->{NAME};
  Log3($name,2,"Watchdog Client: deactivated");
  readingsSingleUpdate($hash,"state","deactivated",1);
}

sub watchdog_client_NotifySystemD($$) {
  my ($hash,$cmd) = @_;
  #Log3($hash->{NAME},5,"Watchdog Client: Debug: watchdog_client_NotifySystemD: $cmd");
  return unless defined $hash->{'.initialized'};
  return unless watchdog_client_IsWDAvailable($hash);

  my $name = $hash->{NAME};
  #Log3($name,1,"Watchdog Client: notify systemd-watchdog: $cmd");

  my $sname = $ENV{NOTIFY_SOCKET};
  if(!defined($sname)) {
    #watchdog_client_Stop($hash);
    Log3($name,1,"Watchdog Client: NOTIFY_SOCKET not available. Please configure systemd-watchdog properly!");
    return;
  }

  Log3($name,4,"Watchdog Client: notify systemd-watchdog: $cmd");
  my $sock_addr = sockaddr_un($sname);
  socket(my $server, PF_UNIX,SOCK_DGRAM,0);
  connect($server, $sock_addr);
  print $server $cmd;
  close($server); 
}

1;

=pod
=item summary_DE Sendet periodisch eine keep-alive-Nachricht an systemd.
=item summary Sends periodically keep-alive message to the systemd.

=begin html_DE

<a name="systemd_watchdog"></a>
<h3>systemd Watchdog Client</h3>
<ul>
  <p>
    systemd erlaubt die &Uuml;berwachung von Programmen mittels eines Watchdogs.
    Sendet der beobachtete Prozess innerhalb eines definierten Intervalls kein Lebenszeichen an den systemd,
    wird dieser den &uuml;berwachten Prozess stoppen und neu starten.
    Dieses Modul sendet periodisch eine <var>keep-alive</var> Nachricht an den systemd-Watchdog.
  </p>

  <a name="systemd_watchdogdefine"></a>
  <strong>Define</strong>
  <pre><code>define &lt;name&gt; systemd_watchdog</code></pre>
  <p>Legt einen neuen systemd-Watchdog mit dem Namen <var>name</var> an.</p>
   <strong>systemd service facility</strong>
  <p>
    Um den Status &uuml;berwachen zu k&ouml;nnen, muss FHEM durch systemd gestartet werden
    und der systemd-Watchdog muss korrekt konfiguriert sein. Dazu kann das die folgende
    <var lang="en">systemd service facility</var> genutzt werden:
  </p>

  <pre>
  <code>
[Unit]
Description=FHEM Home Automation
Requires=network.target
After=dhcpcd.service

[Service]
Type=forking
NotifyAccess=all
User=fhem
Group=dialout

# Run ExecStartPre with root-permissions
ExecStartPre=-+/bin/mkdir -p /run/fhem
ExecStartPre=+/bin/chown -R fhem:dialout /run/fhem

# Run ExecStart with defined user and group
WorkingDirectory=/opt/fhem
ExecStart=/usr/bin/perl fhem.pl fhem.cfg
#ExecStart=/usr/bin/perl fhem.pl configDB   # use for configDB
TimeoutStartSec=240
TimeoutStopSec=120

# Stop service with root priviliges
ExecStop=+/usr/bin/pkill -F /run/fhem/fhem.pid

# Restart options: no, on-success, on-failure, on-abnormal, on-watchdog, on-abort, or always.
Restart=on-failure
RestartSec=3
WatchdogSec=180
PIDFile=/run/fhem/fhem.pid

[Install]
WantedBy=multi-user.target
  </code>
  </pre>

  <p>
    Das Script kann unter <var>/etc/systemd/system/fhem.service</var> abgelegt werden.
    Mit <code><kbd>sudo systemctl daemon-reload</kbd></code> wird die systemd-Konfiguration
    erneuert um die &Auml;nderungen zu aktivieren. Anschlie&szlig;end kann
    FHEM mit <code><kbd>sudo service fhem start</kbd></code> gestartet werden.
  </p>

  <p>
    Wenn in der service unit <var>Type=notify</var> verwendet wird, muss in FHEM das globale Attribut
    <var>nofork=1</var> gesetzt sein: <code><kbd>attr global nofork 1</kbd></code>.
  </p>

  <p>
    Wird  <code><var>Type=forking</var></code> muss in der systemd service facility der korrekte Pfad zu
    der PID-Datei angegeben werden, die dann im globalen Device in FHEM mit
    <code><kbd>attr global pidfilename /run/fhem/fhem.pid</kbd></code> konfiguriert werden kann.
  </p>
</ul>

=end html_DE

=begin html

<a name="systemd_watchdog"></a>
<h3>Systemd Watchdog Client</h3>
<ul>
  <p>
    Systemd allows monitoring of programs by a watchdog. 
    If a process does not respond within a certain time interval, it will be stopped and restarted. 
    This module periodically sends keep-alive message to the systemd.
  </p>
  <p>
    fhem must be started under control of systemd. Watchdog must be also configured properly.<br/>
    You can use the following script:<br/>

  <pre>
  <code>
[Unit]
Description=FHEM Home Automation
Requires=network.target
After=dhcpcd.service

[Service]
Type=forking
NotifyAccess=all
User=fhem
Group=dialout

# Run ExecStartPre with root-permissions
ExecStartPre=-+/bin/mkdir -p /run/fhem
ExecStartPre=+/bin/chown -R fhem:dialout /run/fhem

# Run ExecStart with defined user and group
WorkingDirectory=/opt/fhem
ExecStart=/usr/bin/perl fhem.pl fhem.cfg
#ExecStart=/usr/bin/perl fhem.pl configDB   # use for configDB
TimeoutStartSec=240
TimeoutStopSec=120

# Stop service with root priviliges
ExecStop=+/usr/bin/pkill -F /run/fhem/fhem.pid

# Restart options: no, on-success, on-failure, on-abnormal, on-watchdog, on-abort, or always.
Restart=on-failure
RestartSec=3
WatchdogSec=180
PIDFile=/run/fhem/fhem.pid

[Install]
WantedBy=multi-user.target
  </code>
  </pre>
</ul>
  <a name="systemd_watchdogdefine"></a>
  <p><b>Define</b></p>
<ul>
  <p><code>define &lt;name&gt; systemd_watchdog</code></p>
  <p>Specifies the device.</p>
</ul>

=end html
=cut


