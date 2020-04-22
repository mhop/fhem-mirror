# $Id$
#  erweitert um die Funktion nas_control        Dietmar Ortmann $
#
#	  Maintenance since 2019 KernSani - Thanks Dietmar for all you did for FHEM, RIP
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
#
#============================================================================
#	  	Changelog:
#		2020-01-08, v1.04:	Minor fixes and improved error handling
#							Added option to execute perl/FHEM/System command for wakeup (local or ssh)
#							Added option to execute shutdown command via ssh
#		2019-02-10, v1.03:	Fixed check for invalid broadcast address
#		2019-02-07, v1.02:	First quick revision of commandref
#							Added German commandref
#							Removed textboxes for set commands
#		2019-02-07, v1.01:	Removed dependency on Twilight Module
#
#
##############################################################################
package main;

use strict;
use warnings;
use IO::Socket;
use Blocking;
use Time::HiRes qw(gettimeofday);

my $version = "1.04";

################################################################################
sub WOL_Initialize($) {
    my ($hash) = @_;

    $hash->{SetFn}   = "WOL_Set";
    $hash->{DefFn}   = "WOL_Define";
    $hash->{UndefFn} = "WOL_Undef";
    $hash->{AttrFn}  = "WOL_Attr";
    $hash->{AttrList} =
"interval shutdownCmd:textField-long wolCmd:textField-long sysCmd:textField-long sshHostShutdown sysInterface useUdpBroadcast sshHost "
      . $readingFnAttributes;
}
################################################################################
sub WOL_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    my $u = "wrong syntax: define <name> WOL <MAC_ADRESS> <IP> <mode> <repeat> ";
    return $u if ( int(@a) < 4 );
    my $name   = shift @a;
    my $type   = shift @a;
    my $mac    = shift @a;
    my $ip     = shift @a;
    my $mode   = shift @a;
    my $repeat = shift @a;

    $repeat = "000"  if ( !defined $repeat );
    $mode   = "BOTH" if ( !defined $mode );

    return "invalid MAC<$mac> - use HH:HH:HH:HH:HH:HH"
      if ( !( $mac =~ m/^([0-9a-f]{2}([:-]|$)){6}$/i ) );

    return "invalid IP<$ip> - use ddd.ddd.ddd.ddd"
      if ( !( $ip =~ m/^([0-9]{1,3}([.-]|$)){4}$/i ) );

    return "invalid mode<$mode> - use BOTH|EW|UDP|CMD"
      if ( !( $mode =~ m/^(BOTH|EW|UDP|CMD)$/ ) );

    return "invalid repeat<$repeat> - use 999"
      if ( !( $repeat =~ m/^[0-9]{1,3}$/i ) );

    $hash->{NAME}   = $name;
    $hash->{MAC}    = $mac;
    $hash->{IP}     = $ip;
    $hash->{REPEAT} = $repeat;
    $hash->{MODE}   = $mode;

    $hash->{VERSION} = $version;

    delete $hash->{helper}{RUNNING_PID};

    readingsSingleUpdate( $hash, "packet_via_EW",  "none", 0 );
    readingsSingleUpdate( $hash, "packet_via_UDP", "none", 0 );
    readingsSingleUpdate( $hash, "state",          "none", 0 );
    readingsSingleUpdate( $hash, "active",         "off",  0 );

    RemoveInternalTimer($hash);

    WOL_SetNextTimer( $hash, 10 );
    return undef;
}
################################################################################
sub WOL_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
    return undef;
}

################################################################################
sub WOL_Set($@) {
    my ( $hash, @a ) = @_;
    return "no set value specified" if ( int(@a) < 2 );
    return "Unknown argument $a[1], choose one of on:noArg off:noArg refresh:noArg" if ( $a[1] eq "?" );

    my $name = shift @a;
    my $v = join( " ", @a );

    Log3 $hash, 3, "[$name] set $name $v";

    if ( $v eq "on" ) {
        readingsSingleUpdate( $hash, "active", $v, 1 );
        Log3 $hash, 3, "[$name] waking  $name with MAC $hash->{MAC} IP $hash->{IP} via $hash->{MODE}";
        WOL_GetUpdate($hash);
    }
    elsif ( $v eq "off" ) {
        my $cmd = AttrVal( $name, "shutdownCmd", "" );
        if ( $cmd eq "" ) {
            Log3 $hash, 3, "[$name] no shutdown command given (see shutdownCmd attribute)!";
            return "no shutdown command given (see shutdownCmd attribute)!";
        }
        readingsSingleUpdate( $hash, "active", $v, 1 );
        Log3 $hash, 3, "[$name] shutting down with $cmd ";
        WOL_by_cmd( $hash, "off" );
    }
    elsif ( $v eq "refresh" ) {
        WOL_UpdateReadings($hash);
    }

    return undef;
}
################################################################################
sub WOL_UpdateReadings($) {
    my ($hash) = @_;

    return if ( !defined($hash) );
    my $name = $hash->{NAME};

    my $timeout    = 10;
    my $arg        = $hash->{NAME} . "|" . $hash->{IP};
    my $blockingFn = "WOL_Ping";
    my $finishFn   = "WOL_PingDone";
    my $abortFn    = "WOL_PingAbort";

    if ( !( exists( $hash->{helper}{RUNNING_PID} ) ) ) {
        $hash->{helper}{RUNNING_PID} =
          BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
		   $hash->{helper}{RUNNING_PID}{loglevel} = 4;
    }
    else {
        Log3 $hash, 3, "[$name] Blocking Call running no new started";
        WOL_SetNextTimer($hash);
    }
}
################################################################################
sub WOL_Ping($) {
    my ($string) = @_;
    my ( $name, $ip ) = split( "\\|", $string );
    my $hash = $defs{$name};

    my $ping = "ping -c 1 -w 2 $ip";
    Log3 $hash, 4, "[$name] executing: $ping";
    my $res = qx ($ping);
    $res = "" if ( !defined($res) );

    Log3 $hash, 4, "[$name] result executing ping: $res";

    my $erreichbar = !( $res =~ m/100%/ );
    my $return     = "$name|$erreichbar";
    return $return;
}
################################################################################
sub WOL_PingDone($) {
    my ($string) = @_;
    my ( $name, $erreichbar ) = split( "\\|", $string );
    my $hash = $defs{$name};

    readingsBeginUpdate($hash);

    if ($erreichbar) {
        Log3 $hash, 4, "[$name] ping succesful - state = on";
        readingsBulkUpdate( $hash, "isRunning", "true" );
        readingsBulkUpdate( $hash, "state",     "on" );
    }
    else {
        Log3 $hash, 4, "[$name] ping not succesful - state = off";
        readingsBulkUpdate( $hash, "isRunning", "false" );
        readingsBulkUpdate( $hash, "state",     "off" );
    }

    readingsEndUpdate( $hash, defined( $hash->{LOCAL} ? 0 : 1 ) );

    delete( $hash->{helper}{RUNNING_PID} );

    WOL_SetNextTimer($hash);
}
################################################################################
sub WOL_PingAbort($) {
    my ($hash) = @_;

    delete( $hash->{helper}{RUNNING_PID} );

    Log3 $hash->{NAME}, 3, "BlockingCall for " . $hash->{NAME} . " was aborted";
    WOL_SetNextTimer($hash);
}
################################################################################
sub WOL_GetUpdate($) {
    my ($hash) = @_;

    return if ( !defined($hash) );

    my $active = ReadingsVal( $hash->{NAME}, "active", "nF" );
    if ( $active eq "on" ) {
        WOL_wake($hash);
        if ( $hash->{REPEAT} > 0 ) {
            RemoveInternalTimer( $hash, "WOL_GetUpdate" );
            InternalTimer( gettimeofday() + $hash->{REPEAT}, "WOL_GetUpdate", $hash );
        }
    }

}
################################################################################
sub WOL_wake($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $mac    = $hash->{MAC};
    my $host   = $hash->{IP};

    #$host = '255.255.255.255' if ( !defined $host );
    $host = AttrVal( $name, "useUdpBroadcast", "" );
	if ($host eq "" && $hash->{MODE} =~/UDP|BOTH/) {
		my @ip = split(/\./,$hash->{IP});
		$ip[3] = "255";
		$host = join("\.",@ip);
		Log3 $name, 1, "[$name] Guessing broadcast address: $host"; 
	}

    readingsBeginUpdate($hash);

    Log3 $hash, 4, "[$name] keeping $name with MAC $mac IP $host busy";

    if ( $hash->{MODE} eq "BOTH" || $hash->{MODE} eq "EW" ) {
        WOL_by_ew( $hash, $mac );
        readingsBulkUpdate( $hash, "packet_via_EW", $mac );
    }
    if ( $hash->{MODE} eq "BOTH" || $hash->{MODE} eq "UDP" ) {
        WOL_by_udp( $hash, $mac, $host );
        readingsBulkUpdate( $hash, "packet_via_UDP", $host );
    }
    if ( $hash->{MODE} eq "CMD" ) {
        WOL_by_cmd( $hash, "on" );
    }
    readingsEndUpdate( $hash, defined( $hash->{LOCAL} ? 0 : 1 ) );
}

################################################################################
# method to wake/shutdown via cmd
sub WOL_by_cmd($$) {
    my ( $hash, $mode ) = @_;
    my $name = $hash->{NAME};
    my $mac  = $hash->{MAC};
    my $ip   = $hash->{IP};

    my $host;
    my $cmd;

    if ( $mode eq "on" ) {
        $host = AttrVal( $name, "sshHost", "" );
        $cmd  = AttrVal( $name, "wolCmd",  "" );
        if ( $cmd eq "" ) {
            Log3 $hash, 1, "[$name] no command given (see wolCmd attribute)!";
            return undef;
        }
    }
    else {
        $host = AttrVal( $name, "sshHostShutdown", "" );
        $host =~ s/\$IP/$ip/;
        $cmd = AttrVal( $name, "shutdownCmd", "" );
        if ( $cmd eq "" )
        {    #we're checking this already earlier, so actually not required, but to be on the safe side...
            Log3 $hash, 1, "[$name] no shutdown command given (see shutdownCmd attribute)!";
            return undef;
        }
    }

    #Replacements
    $cmd =~ s/\$MAC/$mac/g;
    $cmd =~ s/\$IP/$ip/g;

    #Execute via SSH if sshHost given
    if ( $host ne "" ) {
        my $sshCmd = "\"ssh ";

        #Sample call   ssh fhem_USR@192.168.2.99 -p 50 sudo wake em0 33:96:1F:1F:1F:1F
        #if ssh command is not enclosed in "" we'll do that...
        if ( $cmd =~ /^\"(.*)\"$/ ) {
            $cmd = $1;
        }

        $sshCmd .= $host . " ";

        #TODO: Check command, restrict to wake, etherwake, wakeonlan (security)?
        #if ( $cmd =~ /.*(ether-wake|etherwake|wakonlan|wake|shutdown).*/) {
        #$sshCmd .= "sudo " . $cmd; # sudo not recommended

     #}
     #else {
     #	Log3 $hash, 1, "[$name] ssh command should be one of ether-wake|etherwake|wakonlan|wake (see sysCmd attribute)!";
     #	return undef;
     #}
		$sshCmd .= " -T ".$cmd;
        #Enclose SSH command in double quotes
        $sshCmd .= "\"";
        $cmd = $sshCmd;
    }

    $cmd = SemicolonEscape($cmd);
    Log3 $hash, 3, "[$name] Executing command >$cmd< ";
    my $ret = AnalyzeCommandChain( undef, $cmd );
    Log3( $hash, 3, "[$name]" . $ret ) if ($ret);

    return 1;
}
################################################################################
# method to wake via lan, taken from Net::Wake package
sub WOL_by_udp {
    my ( $hash, $mac_addr, $host, $port ) = @_;
    my $name = $hash->{NAME};

    # use the discard service if $port not passed in
    if ( !defined $port || $port !~ /^\d+$/ ) { $port = 9 }

    my $sock = new IO::Socket::INET( Proto => 'udp' ) or die "socket : $!";
    if ( !$sock ) {
        Log3 $hash, 1, "[$name] Can't create WOL socket";
        return 1;
    }

    my $ip_addr = inet_aton($host);
    my $sock_addr = sockaddr_in( $port, $ip_addr );
    $mac_addr =~ s/://g;
    my $packet = pack( 'C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16 );

    setsockopt( $sock, SOL_SOCKET, SO_BROADCAST, 1 ) or die "setsockopt : $!";
    send( $sock, $packet, 0, $sock_addr ) or die "send : $!";
    close($sock);

    return 1;
}
################################################################################
# method to wake via system command
sub WOL_by_ew($$) {
    my ( $hash, $mac ) = @_;
    my $name = $hash->{NAME};

    #               Fritzbox               Raspberry             Raspberry aber root
    my @commands = ( "/usr/bin/ether-wake", "/usr/bin/wakeonlan", "/usr/sbin/etherwake" );

    # Kernsani, 08.01.2020: Optimize error handling

    # my $standardEtherwake =
    # "no WOL found - use '/usr/bin/ether-wake' or '/usr/bin/wakeonlan' or define Attribut sysCmd";
    # foreach my $tstCmd (@commands) {
    # if ( -e $tstCmd ) {
    # $standardEtherwake = $tstCmd;
    # last;
    # }
    # }

    #Log3 $hash, 4, "[$name] standard wol command: $standardEtherwake";

    my $sysCmd       = AttrVal( $hash->{NAME}, "sysCmd",       "" );
    my $sysInterface = AttrVal( $hash->{NAME}, "sysInterface", "" );

    if ( $sysCmd gt "" ) {
        Log3 $hash, 4, "[$name] user wol command(sysCmd): '$sysCmd'";
    }
    else {
        foreach my $tstCmd (@commands) {
            if ( -e $tstCmd ) {
                $sysCmd = $tstCmd;
                last;
            }
        }
        if ( $sysCmd eq "" ) {
            Log3 $name, 1,
"[$name] no system command for WOL found - use '/usr/bin/ether-wake' or '/usr/bin/wakeonlan' or define Attribut sysCmd";
            return undef;
        }

    }

    # wenn noch keine $mac dann $mac anhängen.
    $sysCmd .= ' $mac' if ( $sysCmd !~ m/\$mac/g );

    # sysCmd splitten und den nur ersten Teil (-e teil[0])prüfen
    my ($sysWake) = split( " ", $sysCmd );
    if ( -e $sysWake ) {
        $sysCmd =~ s/\$mac/$mac/;
        $sysCmd =~ s/\$sysInterface/$sysInterface/;
        Log3 $hash, 4, "[$name] executing $sysCmd";
        qx ($sysCmd);
    }
    else {
        Log3 $hash, 1, "[$hash->{NAME}] system command '$sysWake' not found";
    }

    return;
}
################################################################################
sub WOL_SetNextTimer($;$) {
    my ( $hash, $int ) = @_;

    my $name = $hash->{NAME};

    $int = AttrVal( $hash->{NAME}, "interval", 900 ) if not defined $int;
    if ( $int != 0 ) {
        Log3 $hash, 5, "[$name] WOL_SetNextTimer to $int";
        RemoveInternalTimer( $hash, "WOL_UpdateReadings" );
        InternalTimer( gettimeofday() + $int, "WOL_UpdateReadings", $hash );
    }
    return;
}
################################################################################
sub WOL_Attr($$$) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    $attrVal = "" if ( !defined $attrVal );

    my $hash = $defs{$name};

    if ( $attrName eq "useUdpBroadcast" ) {
        if ( !( $attrVal =~ m/^([0-9]{1,3}([.-]|$)){4}$/i ) ) {
            return "[$name] invalid Broadcastadress<$attrVal> - use ddd.ddd.ddd.ddd";
        }
    }

    if ( $attrName eq "interval" ) {
        RemoveInternalTimer($hash);

        # when deleting the interval we trigger an update in one second
        my $int = ( $cmd eq "del" ) ? 1 : $attrVal;
        if ( $int != 0 ) {

            # restart timer with new interval
            WOL_SetNextTimer( $hash, $int );
        }
    }

    if ( ( $attrName eq "sshHost" or $attrName eq "sshHostShutdown" ) and $cmd eq "set" ) {
        my $cmd = "timeout 5 ssh -q $attrVal exit || echo 1";
        my $res = qx ($cmd);
        if ( ($res) ) {
            return "[$name] SSH-Login to Host failed: timeout or invalid ssh String <$attrVal>";
        }
    }

    return undef;
}

1;

=pod
=item helper
=item summary    turn on or wake up a computer by sending it a network message
=item summary_DE Einschalten oder Aufwecken eines Computers durch Netzwerknachricht
=begin html

<a name="WOL"></a>
<h3>WOL</h3>

Defines a WOL device via its MAC and IP address.<br><br>

when sending the <b>on</b> command to a WOL device it wakes up the dependent device by sending a magic packet. When running in repeat mode the magic packet ist sent every n seconds to the device.
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
	   <dd>CMD: wakeup via own command (FHEM command, Perl Code or system Command - see Attribut wolCmd</dd>
    </dl>
    <br><br>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;switching only one time</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 EW&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          by ether-wake(linux command)</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 BOTH&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          by both methods</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 UDP 200 &nbsp;&nbsp;&nbsp;                                        in repeat mode</code><br>
	  <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 CMD </code><br>
    </ul>
    <br><br>

    <b><font size="+1">Notes</font></b>:
    <ul>
    Not every hardware is able to wake up other devices by default. Often firewalls filter magic packets and have to be configured accordingly.
    You may need a packet sniffer to check some malfunction.
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
     <li><code>attr &lt;name&gt; wolCmd &lt;command&gt;</code>
                <br>Custom command executed to wakeup a remote machine. Can be &lt;command&gt;, as in at, notify oder Watchdog. If the attribute sshHost is set, the command will be executed as a shell command in remote system</li>
   <li><code>attr &lt;name&gt; shutdownCmd &lt;command&gt;</code>
                <br>Custom command executed to shutdown a remote machine. You can use &lt;command&gt;, like you use it in at, notify or Watchdog If the attribute sshHostShutdown is set, the command will be executed as a shell command in remote system</li>
    <br><br>
    Examples:
    <PRE>
    attr wol shutdownCmd    set lamp on                            # fhem command
    attr wol shutdownCmd    { Log 1, "Teatime" }                   # Perl command
    attr wol shutdownCmd    "/bin/echo "Teatime" > /dev/console"   # shell command
    </PRE>
       <li><code>attr &lt;name&gt; sshHost &lt;IP Address&gt;</code></a>
        <br>Expects a value like [pi@]ip-adresse[:port]. If the attribute is set, the wolCmd will be executed via ssh on the remote host. Prerequisite is that the fhem-User is allowed to login to the remote host without password prompt. (see e.g. https://www.schlittermann.de/doc/ssh.html).  </li>
    <li><code>attr &lt;name&gt; sshHostShutdown &lt;IP Address&gt;</code></a>
        <br>Expects a value like [pi@]ip-adresse[:port]. If the attribute is set, the shutdownCmd will be executed via ssh on the remote host. Prerequisite is that the fhem-User is allowed to login to the remote host without password prompt. (see e.g. https://www.schlittermann.de/doc/ssh.html).  </li>
    <li><code>attr &lt;name&gt; interval &lt;seconds&gt;</code></a>
        <br>defines the time between two checks by a <i>ping</i> if state of &lt;name&gt is <i>on</i>. By using 0 as parameter for interval you can switch off checking the device.</li>
    <li><code>attr &lt;name&gt; useUdpBroadcast &lt;broadcastAdress&gt;</code>
        <br>When using UDP then the magic packet can be send to one of the broadcastAdresses (x.x.x.255, x.x.255.255, x.255.255.255) instead of the target host address. 
        Try using this, when you want to wake up a machine in your own subnet and the wakekup with the target adress is instable or doesn't work.</li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="WOL"></a>
<h3>WOL</h3>

Definiert ein WOL Gerät über seine MAC und IP Addresse.<br><br>

Wenn der <b>on</b> Befehl an das WOL Gerät gesendet wird, wird das entsprechende Gerät durch das Senden eines "magic packet" aufgeweckt. Wenn WOL im repeat Modus läuft, wird das "magic packet" alle n Sekunden zum Gerät geschickt.
So kann z.B. ein Buffalo NAS "wach" gehalten werden.
<ul>
  <a name="WOLdefine"></a>
  <h4>Define</h4>
  <ul>
    <code><b><font size="+1">define &lt;name&gt; WOL &lt;MAC&gt; &lt;IP&gt; [&lt;mode&gt; [&lt;repeat&gt;]]</font></b></code>
    <br><br>

    <dl>
    <dt><b>MAC</b></dt>
       <dd>MAC-Adresse des Hosts</dd>
    <dt><b>IP</b></dt>
       <dd>IP-Adresse des Hosts (oder broadcast Addresse des lokalen Netzwerks, wenn die IP des Hosts unbekannt ist)</dd>
    <dt><b>mode <i>[EW|UDP]</i></b></dt>
       <dd>EW:  aufwecken durch <i>usr/bin/ether-wake</i> </dd>
       <dd>UDP: aufwecken durch eine Implementierung wie <i>Net::Wake(CPAN)</i></dd>
	   <dd>CMD: aufwecken durch einen eigenen Befehl (FHEM Kommando, Perl Code oder system Command - siehe Attribut wolCmd</dd>
    </dl>
    <br><br>

    <b><font size="+1">Beispiele</font></b>:
    <ul>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;nur einmal schalten</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 EW&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          über ether-wake(Linux Befehl)</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 BOTH&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;                          über beide Methoden</code><br>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 UDP 200 &nbsp;&nbsp;&nbsp;                                        im repeat Modus</code><br>
	  <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24 CMD </code><br>
    </ul>
    <br><br>

    <b><font size="+1">Anmerkungen</font></b>:
    <ul>
    Nicht jede Hardware kann standardmäßig andere Geräte aufwecken. Firewalls filtern häufig magic packets und müssen entsprechend konfiguriert werden.
    Möglicherweise ist ein Packet Sniffer notwendig um Fehlfunktionen zu überprüfen.
    </ul>
  </ul>

  <a name="WOLset"></a>
  <h4>Set </h4>
  <ul>
    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    wobei <code>value</code> einer der folgenden ist:<br>
    <pre>
    <b>refresh</b>           # überprüft (mittels ping) ob das Gerät gerade läuft
    <b>on</b>                # schickt ein magic packet an die definierte MAC-Adresse
    <b>off</b>               # beemdet das Senden von magic packets schickt das <b>shutdownCmd</b>(siehe Attribute)
    </pre>

    <b><font size="+1">Beispiele</font></b>:
    <ul>
      <code>set computer1 on</code><br>
      <code>set computer1 off</code><br>
      <code>set computer1 refresh</code><br>
    </ul>
  </ul>

  <a name="WOLattr"></a>
  <h4>Attribute</h4>
  <ul>
    <li><code>attr &lt;name&gt; sysCmd &lt;string&gt;</code>
                <br>Eigener Befehl, um ein entferntes Gerät aufzuwecken, z.B. <code>/usr/bin/ether-wake or /usr/bin/wakeonlan</code></li>
    <li><code>attr &lt;name&gt; wolCmd &lt;command&gt;</code>
                <br>Eigener Befehl, um ein entferntes Gerät aufzuwecken. Es können &lt;command&gt;, wie in at, notify oder Watchdog verwendet werden. Wenn das Attribut sshHost gesetzt ist, wird ein shell Befehl im remote System ausgeführt.
    </li>
	<li><code>attr &lt;name&gt; shutdownCmd &lt;command&gt;</code>
                <br>Eigener Befehl, um ein entferntes Gerät herunter zu fahren. Es können &lt;command&gt;, wie in at, notify oder Watchdog verwendet werden. Wenn das Attribut sshHostShutdown gesetzt ist, wird ein shell Befehl im remote System ausgeführt.
    </li>

    <br><br>
    Beispiele:
    <PRE>
    attr wol shutdownCmd    set lamp on                            # fhem Befehl
    attr wol shutdownCmd    { Log 1, "Teatime" }                   # Perl Befehl
    attr wol shutdownCmd    "/bin/echo "Teatime" > /dev/console"   # shell Befehl
    </PRE>
    <li><code>attr &lt;name&gt; sshHost &lt;IP Address&gt;</code></a>
        <br>Erwartet eine Wert der Form [pi@]ip-adresse[:port]. Ist das Attribut gesetzt wird wolCmd über ssh auf dem angegebenen remote host ausgeführt. Voraussetzung ist, dass der fhem-User sich ohne Passwort auf dem remote host einloggen kann (siehe z.B. https://www.schlittermann.de/doc/ssh.html).  </li>
    <li><code>attr &lt;name&gt; sshHostShutdown &lt;IP Address&gt;</code></a>
        <br>Erwartet eine Wert der Form [pi@]ip-adresse[:port]. Ist das Attribut gesetzt wird shutdownCmd über ssh auf dem angegebenen remote host ausgeführt. Voraussetzung ist, dass der fhem-User sich ohne Passwort auf dem remote host einloggen kann (siehe z.B. https://www.schlittermann.de/doc/ssh.html).  </li>
    <li><code>attr &lt;name&gt; interval &lt;seconds&gt;</code></a>
        <br>definiert die Zeit zwischen zwei Checks mittels <i>ping</i> Wenn der state von &lt;name&gt <i>on</i> ist. Mit dem Wert 0 als interval wird die regelmäßige Überprüfung abgeschaltet.</li>
    <li><code>attr &lt;name&gt; useUdpBroadcast &lt;broadcastAdress&gt;</code>
        <br>Bei der Nutzung von UDP kann das magic packet an eine det broadcastAdressen (x.x.x.255, x.x.255.255, x.255.255.255) geschickt werden, an Stelle des Ziel-Hosts address. 
        Diese Methode sollte verwendet werden, wenn ein Gerät im eigenen Subnetz aufgeweckt werden soll, aber der wakeup mit dem Zielhost nicht funktioniert oder nicht stabil ist.</li>
  </ul>
</ul>

=end html_DE

=cut
