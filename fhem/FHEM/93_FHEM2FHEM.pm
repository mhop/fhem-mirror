##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub FHEM2FHEM_Read($);
sub FHEM2FHEM_Ready($);
sub FHEM2FHEM_OpenDev($$);
sub FHEM2FHEM_CloseDev($);
sub FHEM2FHEM_Disconnected($);
sub FHEM2FHEM_Define($$);
sub FHEM2FHEM_Undef($$);

sub
FHEM2FHEM_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "FHEM2FHEM_Read";
  $hash->{WriteFn} = "FHEM2FHEM_Write";
  $hash->{ReadyFn} = "FHEM2FHEM_Ready";
  $hash->{noRawInform} = 1;

# Normal devices
  $hash->{DefFn}   = "FHEM2FHEM_Define";
  $hash->{UndefFn} = "FHEM2FHEM_Undef";
  $hash->{AttrList}= "dummy:1,0 disable:0,1 disabledForIntervals";
}

#####################################
sub
FHEM2FHEM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4 || @a > 5 || !($a[3] =~ m/^(LOG|RAW):(.*)$/)) {
    my $msg = "wrong syntax: define <name> FHEM2FHEM host[:port][:SSL] ".
                        "[LOG:regexp|RAW:device] {portpasswort}";
    Log3 $hash, 2, $msg;
    return $msg;
  }

  $hash->{informType} = $1;
  if($1 eq "LOG") {
    $hash->{regexp} = $2;

  } else {
    my $rdev = $2;
    my $iodev = $defs{$rdev};
    return "Undefined local device $rdev" if(!$iodev);
    $hash->{rawDevice} = $rdev;
    $hash->{Clients} = $iodev->{Clients};
    $hash->{Clients} = $modules{$iodev->{TYPE}}{Clients}
        if(!$hash->{Clients});

  }

  my $dev = $a[2];
  if($dev =~ m/^(.*):SSL$/) {
    $dev = $1;
    $hash->{SSL} = 1;
  }
  if($dev !~ m/^.+:[0-9]+$/) {       # host:port
    $dev = "$dev:7072";
    $hash->{Host} = $dev;
  }
  $hash->{Host} = $dev;
  $hash->{portpassword} = $a[4] if(@a == 5);

  FHEM2FHEM_CloseDev($hash);    # Modify...
  return FHEM2FHEM_OpenDev($hash, 0);
}

#####################################
sub
FHEM2FHEM_Undef($$)
{
  my ($hash, $arg) = @_;
  FHEM2FHEM_CloseDev($hash); 
  return undef;
}

sub
FHEM2FHEM_Write($$)
{
  my ($hash,$fn,$msg) = @_;
  my $dev = $hash->{Host};

  if(!$hash->{TCPDev2}) {
    my $conn;
    if($hash->{SSL}) {
      $conn = IO::Socket::SSL->new(PeerAddr => $dev);
    } else {
      $conn = IO::Socket::INET->new(PeerAddr => $dev);
    }
    return if(!$conn);  # Hopefuly it is reported elsewhere
    $hash->{TCPDev2} = $conn;
    syswrite($hash->{TCPDev2}, $hash->{portpassword} . "\n")
        if($hash->{portpassword});
  }
  my $rdev = $hash->{rawDevice};
  syswrite($hash->{TCPDev2}, "iowrite $rdev $fn $msg\n");
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
FHEM2FHEM_Read($)
{
  my ($hash) = @_;

  my $buf = FHEM2FHEM_SimpleRead($hash);
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = FHEM2FHEM_SimpleRead($hash);
  }

  if(!defined($buf) || length($buf) == 0) {
    FHEM2FHEM_Disconnected($hash);
    return;
  }

  return if(IsDisabled($name));

  my $data = $hash->{PARTIAL};
  Log3 $hash, 5, "FHEM2FHEM/RAW: $data/$buf";
  $data .= $buf;

  while($data =~ m/\n/) {
    my $rmsg;
    ($rmsg,$data) = split("\n", $data, 2);
    $rmsg =~ s/\r//;
    Log3 $name, 4, "$name: $rmsg";

    if($hash->{informType} eq "LOG") {
      my ($type, $name, $msg) = split(" ", $rmsg, 3);
      next if(!defined($msg)); # Bogus data
      my $re = $hash->{regexp};
      next if($re && !($name =~ m/^$re$/ || "$name:$msg" =~ m/^$re$/));

      if(!$defs{$name}) {
        #LoadModule($type); Why do we need this line?
        $defs{$name}{NAME}  = $name;
        $defs{$name}{TYPE}  = $type;
        $defs{$name}{STATE} = $msg;
        $defs{$name}{FAKEDEVICE} = 1; # Avoid set/attr/delete/etc in notify
        $defs{$name}{TEMPORARY} = 1;  # Do not save it
        DoTrigger($name, $msg);
        delete($defs{$name});

      } else {
        DoTrigger($name, $msg);

      }

    } else {    # RAW
      my ($type, $rname, $msg) = split(" ", $rmsg, 3);
      my $rdev = $hash->{rawDevice};
      next if($rname ne $rdev);
      Dispatch($defs{$rdev}, $msg, undef);

    }
  }
  $hash->{PARTIAL} = $data;
}


#####################################
sub
FHEM2FHEM_Ready($)
{
  my ($hash) = @_;

  return FHEM2FHEM_OpenDev($hash, 1);
}

########################
sub
FHEM2FHEM_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{Host};

  return if(!$dev);
  
  $hash->{TCPDev}->close() if($hash->{TCPDev});
  $hash->{TCPDev2}->close() if($hash->{TCPDev2});
  delete($hash->{TCPDev});
  delete($hash->{TCPDev2});
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
FHEM2FHEM_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  $hash->{PARTIAL} = "";
  Log3 $name, 3, "FHEM2FHEM opening $name at $dev"
        if(!$reopen);

  # This part is called every time the timeout (5sec) is expired _OR_
  # somebody is communicating over another TCP connection. As the connect
  # for non-existent devices has a delay of 3 sec, we are sitting all the
  # time in this connect. NEXT_OPEN tries to avoid this problem.
  if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
    return;
  }

  my $conn;
  if($hash->{SSL}) {
    eval "use IO::Socket::SSL";
    Log3 $name, 1, $@ if($@);
    $conn = IO::Socket::SSL->new(PeerAddr => "$dev") if(!$@);
  } else {
    $conn = IO::Socket::INET->new(PeerAddr => $dev);
  }

  if($conn) {
    delete($hash->{NEXT_OPEN})

  } else {
    Log3($name, 3, "Can't connect to $dev: $!") if(!$reopen);
    $readyfnlist{"$name.$dev"} = $hash;
    $hash->{STATE} = "disconnected";
    $hash->{NEXT_OPEN} = time()+60;
    return "";
  }

  $hash->{TCPDev} = $conn;
  $hash->{FD} = $conn->fileno();
  delete($readyfnlist{"$name.$dev"});
  $selectlist{"$name.$dev"} = $hash;

  if($reopen) {
    Log3 $name, 1, "FHEM2FHEM $dev reappeared ($name)";
  } else {
    Log3 $name, 3, "FHEM2FHEM device opened ($name)";
  }

  $hash->{STATE}= "connected";
  DoTrigger($name, "CONNECTED") if($reopen);
  syswrite($hash->{TCPDev}, $hash->{portpassword} . "\n")
        if($hash->{portpassword});
  my $msg = $hash->{informType} eq "LOG" ? "inform on" : "inform raw";
  syswrite($hash->{TCPDev}, $msg . "\n");
  return undef;
}

sub
FHEM2FHEM_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{Host};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted
  Log3 $name, 1, "$dev disconnected, waiting to reappear";
  FHEM2FHEM_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

########################
sub
FHEM2FHEM_SimpleRead($)
{
  my ($hash) = @_;
  my $buf;
  if(!defined(sysread($hash->{TCPDev}, $buf, 256))) {
    FHEM2FHEM_Disconnected($hash);
    return undef;
  }
  return $buf;
}

1;

=pod
=begin html

<a name="FHEM2FHEM"></a>
<h3>FHEM2FHEM</h3>
<ul>
  FHEM2FHEM is a helper module to connect separate FHEM installations.
  <br><br>
  <a name="FHEM2FHEMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEM2FHEM &lt;host&gt;[:&lt;portnr&gt;][:SSL] [LOG:regexp|RAW:devicename] {portpassword}
    </code>
  <br>
  <br>
  Connect to the <i>remote</i> FHEM on &lt;host&gt;. &lt;portnr&gt; is a telnet
  port on the remote FHEM, defaults to 7072. The optional :SSL suffix is
  needed, if the remote FHEM configured SSL for this telnet port. In this case
  the IO::Socket::SSL perl module must be installed for the local host too.<br>

  Note: if the remote FHEM is on a separate host, the telnet port on the remote
  FHEM musst be specified with the global option.<br>

  The next parameter specifies the connection
  type:
  <ul>
  <li>LOG<br>
    Using this type you will receive all events generated by the remote FHEM,
    just like when using the <a href="#inform">inform on</a> command, and you
    can use these events just like any local event for <a
    href="#FileLog">FileLog </a> or <a href="#notify">notify</a>.
    The regexp will prefilter the events distributed locally, for the syntax
    see the notify definition.<br>
    Drawbacks: the remote devices wont be created locally, so list wont
    show them and it is not possible to manipulate them from the local
    FHEM. It is possible to create a device with the same name on both FHEM
    instances, but if both of them receive the same event (e.g. because both
    of them have a CUL attached), then all associated FileLogs/notifys will be
    triggered twice.  </li>

  <li>RAW<br>
    By using this type the local FHEM will receive raw events from the remote
    FHEM device <i>devicename</i>, just like if it would be attached to the
    local FHEM.
    Drawback: only devices using the Dispatch function (CUL, FHZ, CM11,
    SISPM, RFXCOM, TCM, TRX, TUL) generate raw messages, and you must create a
    FHEM2FHEM instance for each remote device.<br>
    <i>devicename</i> must exist on the local
    FHEM server too with the same name and same type as the remote device, but
    with the device-node "none", so it is only a dummy device. 
    All necessary attributes (e.g. <a href="#rfmode">rfmode</a> if the remote
    CUL is in HomeMatic mode) must also be set for the local device.
    Do not reuse a real local device, else duplicate filtering (see dupTimeout)
    won't work correctly.
    </li>
  </ul>
  The last parameter specifies an optional portpassword, if the remote server
  activated <a href="#portpassword">portpassword</a>.
  <br>
  Examples:
  <ul>
    <code>define ds1 FHEM2FHEM 192.168.178.22:7072 LOG:.*</code><br>
    <br>
    <code>define RpiCUL CUL none 0000</code><br>
    <code>define ds2 FHEM2FHEM 192.168.178.22:7072 RAW:RpiCUL</code><br>
    and on the RPi (192.168.178.22):<br>
    <code>rename CUL_0 RpiCUL</code><br>
  </ul>
  </ul>
  <br>

  <a name="FHEM2FHEMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="FHEM2FHEMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="FHEM2FHEMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul>

</ul>

=end html

=begin html_DE

<a name="FHEM2FHEM"></a>
<h3>FHEM2FHEM</h3>
<ul>
   FHEM2FHEM ist ein Hilfsmodul, um mehrere FHEM-Installationen zu verbinden.
   <br><br>
   <a name="FHEM2FHEMdefine"></a>
   <b>Define</b>
   <ul>
    <code>define &lt;name&gt; FHEM2FHEM &lt;host&gt;[:&lt;portnr&gt;][:SSL] [LOG:regexp|RAW:devicename] {portpassword}
    </code>
   <br>
   <br>
    Zum <i>remote (entfernten)</i> FHEM auf Rechner &lt;host&gt; verbinden.
    &lt;portnr&gt; ist der telnetPort des remote FHEM, Standardport ist 7072.
    Der Zusatz :SSL wird ben&ouml;tigt, wenn das remote FHEM
    SSL-Verschl&uuml;sselung voraussetzt.  Auch auf dem lokalen Host muss dann
    das Perl-Modul IO::Socket::SSL installiert sein.<br>

   Anmerkung: Wenn das remote FHEM auf einem eigenen Host l&auml;uft, muss
   "telnetPort" des remote FHEM als global festgelegt sein.  <br>

   Der n&auml;chste Parameter spezifiziert den Verbindungs-Typ:
   <ul>
   <li>LOG<br>
    Bei Verwendung dieses Verbindungstyps werden alle Ereignisse (Events) der
    remote FHEM-Installation empfangen.  Die Ereignisse sehen aus wie die, die
    nach <a href="#inform">inform on</a> Befehl erzeugt werden. Sie k&ouml;nnen
    wie lokale Ereignisse durch <a href="#FileLog">FileLog </a> oder <a
    href="#notify">notify</a> genutzt werden und mit einem regul&auml;ren
    Ausdruck gefiltert werden. Die Syntax daf&uuml;r ist unter der
    notify-Definition beschrieben.<br>

    Einschr&auml;nkungen: die Ger&auml;te der remote Installation werden nicht
    lokal angelegt und k&ouml;nnen weder mit list angezeigt noch lokal
    angesprochen werden.  Auf beiden FHEM-Installationen k&ouml;nnen
    Ger&auml;te gleichen Namens angelegt werden, aber wenn beide dasselbe
    Ereignis empfangen (z.B. wenn an beiden Installationen CULs angeschlossen
    sind), werden alle FileLogs und notifys doppelt ausgel&ouml;st.  </li>

   <li>RAW<br>
    Bei diesem Verbindungstyp werden unaufbereitete Ereignisse (raw messages)
    des remote FHEM-Ger&auml;ts <i>devicename</i> genau so empfangen, als
    w&auml;re das Ger&auml;t lokal verbunden.<br>

    Einschr&auml;nkungen: nur Ger&auml;te, welche die "Dispatch-Funktion"
    unterst&uuml;tzen (CUL, FHZ, CM11, SISPM, RFXCOM, TCM, TRX, TUL) erzeugen
    raw messages, und f&uuml;r jedes entfernte Ger&auml;t muss ein eigenes
    FHEM2FHEM Objekt erzeugt werden.<br>

    <i>devicename</i> muss mit demselben Namen und Typ wie das Remote Devive
    angelegt sein, aber als Dummy, d.h. als device-node "none".
    Zus&auml;tzlich m&uuml;ssen alle notwendigen Attribute lokal gesetzt sein
    (z.B. <a href="#rfmode">rfmode</a>, wenn die remote CUL im HomeMatic-Modus
    l&auml;uft).  Die Verwendung bereits bestehender lokaler Ger&auml;te ist zu
    vermeiden, weil sonst die Duplikatsfilterung nicht richtig funktioniert
    (siehe dupTimeout).  </li>

   </ul>
   Der letzte Parameter enth&auml;lt das Passwort des Remote-Servers, wenn dort
   eines aktiviert ist <a href="#portpassword">portpassword</a>.

   <br>
   Beispiele:
   <ul>
     <code>define ds1 FHEM2FHEM 192.168.178.22:7072 LOG:.*</code><br>
     <br>
     <code>define RpiCUL CUL none 0000</code><br>
     <code>define ds2 FHEM2FHEM 192.168.178.22:7072 RAW:RpiCUL</code><br> und auf dem RPi (192.168.178.22):<br>
     <code>rename CUL_0 RpiCUL</code><br>
   </ul>
   </ul>
   <br>

   <a name="FHEM2FHEMset"></a>
   <b>Set</b> <ul>N/A</ul><br>

   <a name="FHEM2FHEMget"></a>
   <b>Get</b> <ul>N/A</ul><br>

   <a name="FHEM2FHEMattr"></a>
   <b>Attribute</b>
   <ul>
     <li><a href="#dummy">dummy</a></li>
      <li><a href="#disable">disable</a></li>
      <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
   </ul>

</ul>

=end html_DE

=cut
