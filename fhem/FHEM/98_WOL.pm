# $Id$
#  erweitert um die Funktion nas_control        Dietmar Ortmann $
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
##############################################################################
package main;

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);
################################################################################
sub WOL_Initialize($) {
  my ($hash) = @_;

  $hash->{SetFn}     = "WOL_Set";
  $hash->{DefFn}     = "WOL_Define";
  $hash->{UndefFn}   = "WOL_Undef";
  $hash->{AttrList}  = "interval shutdownCmd sysCmd ".
                        $readingFnAttributes;
}
################################################################################
sub WOL_Set($@) {
  my ($hash, @a) = @_;
  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of on off refresh" if($a[1] eq "?");
  
  my $name = shift @a;
  my $v = join(" ", @a);
  my $mod = "[".$hash->{NAME} ."] ";

  Log3 $hash, 3, "WOL set $name $v";
  
  if      ($v eq "on")  {
     $hash->{STATE}  = $v;
     Log3 $hash, 3, "WOL waking  $name with MAC $hash->{MAC} IP $hash->{IP} ";
  } elsif ($v eq "off") {
     $hash->{STATE}  = $v;
     my $cmd = AttrVal($name, "shutdownCmd", "");
     if ($cmd eq "") {
       Log3 $hash, 3, "No shutdown command given (see shutdownCmd attribute)!";
     } else {
#      qx ($cmd);
       $cmd  = SemicolonEscape($cmd);
       Log3 $hash, 3, $mod."shutdownCmd: $cmd executed";
       my $ret  = AnalyzeCommandChain(undef, $cmd);
       Log3 ($hash, 3, $ret) if($ret);
     }
  } elsif ($v eq "refresh") {
    ;
  }

  WOL_UpdateReadings($hash);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_UpdateReadings", $hash, 0);

  if ($hash->{STATE} eq "on") {
      WOL_GetUpdate($hash);
  }
  return undef;
}
################################################################################
sub WOL_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> WOL <MAC_ADRESS> <IP> <mode> <repeat> ";
  return $u if(int(@a) < 4);
  my $name       = shift @a;
  my $type       = shift @a;
  my $mac        = shift @a;
  my $ip         = shift @a;
  my $mode       = shift @a;
  my $repeat     = shift @a;

  $repeat = "000"   if (!defined $repeat);
  $mode   = "BOTH"  if (!defined $mode);

  return "invalid MAC<$mac> - use HH:HH:HH:HH:HH"
     if(!($mac =~  m/^([0-9a-f]{2}([:-]|$)){6}$/i   ));

  return "invalid IP<$ip> - use ddd.ddd.ddd.ddd"
     if(!($ip =~  m/^([0-9]{1,3}([.-]|$)){4}$/i    ));

  return "invalid mode<$mode> - use EW|UDP|BOTH"
     if(!($mode =~  m/^(BOTH|EW|UDP)$/));

  return "invalid repeat<$repeat> - use 999"
     if(!($repeat =~  m/^[0-9]{3,3}$/i));

  $hash->{NAME}     = $name;
  $hash->{MAC}      = $mac;
  $hash->{IP}       = $ip;
  $hash->{REPEAT}   = $repeat;
  $hash->{MODE}     = $mode;

  $hash->{INTERVAL} = AttrVal($hash->{NAME}, "interval", 900);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "WOL_UpdateReadings", $hash, 0);
  InternalTimer(gettimeofday()+30,"WOL_GetUpdate",      $hash, 0);

  readingsSingleUpdate($hash, "packet_via_EW",  "none",0);
  readingsSingleUpdate($hash, "packet_via_UDP", "none",0);
  return undef;
}
################################################################################
sub WOL_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}
################################################################################
sub WOL_UpdateReadings($) {
  my ($hash) = @_;
  $hash->{INTERVAL} = AttrVal($hash->{NAME}, "interval", 900);

  my $ip = $hash->{IP};

  readingsBeginUpdate ($hash);

  if (`ping -c 1 -w 2 $ip` =~ m/100%/) {
    readingsBulkUpdate   ($hash, "isRunning", "false");
  } else {
    readingsBulkUpdate   ($hash, "isRunning", "true");
  }

  readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_UpdateReadings", $hash, 0);
}
################################################################################
sub WOL_GetUpdate($) {
  my ($hash) = @_;

  if ($hash->{STATE} eq "on") {
     wake($hash);
  }

  if ($hash->{REPEAT} > 0 && $hash->{STATE} eq "on" ) {
     InternalTimer(gettimeofday()+$hash->{REPEAT}, "WOL_GetUpdate", $hash, 0);
  }
}
################################################################################
sub wake($){
  my ($hash) = @_;
  my $name  = $hash->{NAME};
  my $mac   = $hash->{MAC};
  my $host  = $hash->{IP};

  readingsBeginUpdate ($hash);
  
  Log3 $hash, 3, "WOL keeping $name with MAC $mac IP $host busy";

  if ($hash->{MODE} eq "BOTH" || $hash->{MODE} eq "EW" ) {
     wol_by_ew ($hash, $mac);
     readingsBulkUpdate   ($hash, "packet_via_EW", $mac);
  }
  if ($hash->{MODE} eq "BOTH" || $hash->{MODE} eq "UDP" ) {
     wol_by_udp ($hash, $mac, $host);
     readingsBulkUpdate   ($hash, "packet_via_UDP", $host);
  }
  readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
}
################################################################################
# method to wakevia lan, taken from Net::Wake package
sub wol_by_udp {
  my ($hash, $mac_addr, $host, $port) = @_;

  # use the discard service if $port not passed in
  if (! defined $host) { $host = '255.255.255.255' }
  if (! defined $port || $port !~ /^\d+$/ ) { $port = 9 }

  my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
  if(!$sock) {
     Log3 $hash, 1, "Can't create WOL socket";
     return 1;
  }

  my $ip_addr   = inet_aton($host);
  my $sock_addr = sockaddr_in($port, $ip_addr);
  $mac_addr     =~ s/://g;
  my $packet    = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
  send($sock, $packet, 0, $sock_addr) or die "send : $!";
  close ($sock);

  return 1;
}
################################################################################
# method to wake via system command
sub wol_by_ew($$) {
  my ($hash, $mac) = @_;

  my $sysCmd = AttrVal($hash->{NAME}, "sysCmd", "/usr/bin/ether-wake");
  if (-e $sysCmd) {
     my $response = `$sysCmd $mac`;
  } else {
     Log3 $hash, 1, "[$hash->{NAME}] system command '$sysCmd' not found";
  }

  return 1;
}

1;


=pod
=begin html

<a name="WOL"></a>
<h3>WOL</h3>

Defines a WOL device via its MAC and IP address.<br><br>

when sending the <b>on</b> command to a WOL device it wakes up the dependent device by sending a magic packet. When running in repeat mode the magic paket ist sent every n seconds to the device.
So, for example a Buffalo NAS can be kept awake.
<ul>
  <a name="WOLdefine"></a>
  <h4>Define</h4>
  <ul>
    <code><b><font size="+1">define &lt;name&gt; WOL &lt;MAC&gt; &lt;IP&gt; [&lt;mode&gt; [&lt;repeat&gt;]]</font></b></code>
    <br><br>

    <dl>
    <dt><b>MAC</b></dt>
       <dd>MAC-Adress of the host</dd>
    <dt><b>IP</b></dt>
       <dd>IP-Adress of the host (or broadcast address of the local network if IP of the host is unknown)</dd>
    <dt><b>mode <i>[EW|UDP]</i></b></dt>
       <dd>EW:  wakeup by <i>usr/bin/ether-wake</i> </dd>
       <dd>UDP: wakeup by an implementation like <i>Net::Wake(CPAN)</i></dd>
    </dl>
    <br><br>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;switching only one time</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 EW&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          by ether-wake(linux command)</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 BOTH&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          by both methods</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 UDP 200 &nbsp;&nbsp;&nbsp;                                        in repeat mode<i><b>usr/bin/ether-wake</b></i> in repeatmode</code><br>
    </ul>
    <br><br>

    <b><font size="+1">Notes</font></b>:
    <ul>
    Not every hardware is able to wake up other devices by default. Oftenly firewalls filter magic packets. Switch them first off.
    You may need a packet sniffer to check some malfunktion.
    With this module you get two methods to do the job: see the mode parameter.
    </ul>
  </ul>

  <a name="WOLset"></a>
  <h4>Set </h4>
  <ul>
    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    <b>refresh</b>           # checks(by ping) whether the device is currently running
    <b>on</b>                # sends a magic packet to the defined MAC address
    <b>off</b>               # stops sending magic packets and sends the <b>shutdownCmd</b>(see attributes)
    </pre>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>set computer1 on</code><br>
      <code>set computer1 off</code><br>
      <code>set computer1 refresh</code><br>
    </ul>
  </ul>

  <a name="WOLattr"></a>
  <h4>Attributes</h4>
  <ul>
    <li><code>attr &lt;name&gt; sysCmd &lt;string&gt;</code>
                <br>Custom command executed to wakeup a remote machine, i.e. <code>/usr/bin/ether-wake or /usr/bin/wakeonlan</code></li>
    <li><code>attr &lt;name&gt; shutdownCmd &lt;command&gt;</code>
                <br>Custom command executed to shutdown a remote machine. You can use &lt;command&gt;, like you use it in at, notify or Watchdog</li>
    <br><br>
    Examples:
    <PRE>
    shutdownCmd    set lamp on                            # fhem command
    shutdownCmd    { Log 1, "Teatime" }                   # Perl command
    shutdownCmd    "/bin/echo "Teatime" > /dev/console"   # shell command
    </PRE>
    <li><code>attr &lt;name&gt; interval &lt;seconds&gt;</code></a>
                <br>defines the time between two checks by a <i>ping</i> if state of &lt;name&gt is <i>on</i></li>
  </ul>
</ul>

=end html
=cut