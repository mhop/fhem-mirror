##############################################
# $Id$

# Note: this is not really a telnet server, but a TCP server with slight telnet
# features (disable echo on password)

package main;
use strict;
use warnings;
use TcpServerUtils;

##########################
sub
telnet_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "telnet_Define";
  $hash->{ReadFn}  = "telnet_Read";
  $hash->{AsyncOutputFn}  = "telnet_Output";
  $hash->{UndefFn} = "telnet_Undef";
  $hash->{AttrFn}  = "telnet_Attr";
  no warnings 'qw';
  my @attrList = qw(
    SSL
    allowedCommands
    allowfrom
    connectInterval
    connectTimeout
    encoding:utf8,latin1
    globalpassword
    password
    prompt
    sslCertPrefix
    sslVersion
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
  $hash->{ActivateInformFn} = "telnet_ActivateInform";
  $hash->{CanAuthenticate} = 2;

  $cmds{encoding} = { Fn=>"CommandTelnetEncoding",
            ClientFilter => "telnet",
            Hlp=>"[utf8|latin1],query and set the character encoding ".
                            "for the current telnet session" };

  $cmds{inform} = { Fn=>"CommandTelnetInform",
          ClientFilter => "telnet",
          Hlp=>"{on|onWithState|off|log|raw|timer|status},".
                        "echo all events to this client" };
}

sub
CommandTelnetEncoding($$)
{
  my ($hash, $param) = @_;

  my $ret = "";

  if( !$param ) {
    $ret = "current encoding is $hash->{encoding}";
  } elsif( $param eq "utf8" || $param eq "latin1"  ) {
    $hash->{encoding} = $param;
    syswrite($hash->{CD}, sprintf("%c%c%c", 255, 253, 0) );
    $ret = "encoding changed to $param";
  } else {
    $ret = "unknown encoding >>$param<<";
  }

  return $ret;
}

##########################
sub
telnet_ClientConnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  $hash->{DEF} =~ m/^(IPV6:)?(.*):(\d+)$/;
  my ($isIPv6, $server, $port) = ($1, $2, $3);

  Log3 $name, 4, "$name: Connecting to $server:$port...";
  my @opts = (
        PeerAddr => "$server:$port",
        Timeout => AttrVal($name, "connectTimeout", 2),
  );

  my $client;
  if($hash->{SSL}) {
    $client = IO::Socket::SSL->new(@opts);
  } else {
    $client = IO::Socket::INET->new(@opts);
  }
  if($client) {
    $hash->{FD}    = $client->fileno();
    $hash->{CD}    = $client;         # sysread / close won't work on fileno
    $hash->{BUF}   = "";
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    $hash->{STATE} = "Connected";
    RemoveInternalTimer($hash);
    Log3 $name, 3, "$name: connected to $server:$port";

  } else {
    telnet_ClientDisconnect($hash, 1);

  }
}

##########################
sub
telnet_ClientDisconnect($$)
{
  my ($hash, $connect) = @_;
  my $name   = $hash->{NAME};
  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  $hash->{STATE} = "Disconnected";
  InternalTimer(gettimeofday()+AttrVal($name, "connectInterval", 60),
                "telnet_ClientConnect", $hash, 0);
  if($connect) {
    Log3 $name, 4, "$name: Connect failed.";
  } else {
    Log3 $name, 3, "$name: Disconnected";
  }
}

##########################
sub
telnet_Define($$$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);
  my ($name, $type, $pport, $global) = split("[ \t]+", $def);

  my $port = $pport;
  $port =~ s/^IPV6://;

  my $isServer = 1 if(defined($port) && $port =~ m/^\d+$/);
  my $isClient = 1 if($port && $port =~ m/^(.+):\d+$/);

  return "Usage: define <name> telnet { [IPV6:]<tcp-portnr> [global] | ".
                                      " [IPV6:]serverName:port }"
        if(!($isServer || $isClient) ||
            ($isClient && $global));

  # Make sure that fhem only runs once
  if($isServer) {
    my $ret = TcpServer_Open($hash, $pport, $global);
    if($ret && !$init_done) {
      Log3 $name, 1, "$ret. Exiting.";
      exit(1);
    }
    return $ret;
  }

  if($isClient) {
    $hash->{isClient} = 1;
    telnet_ClientConnect($hash);
  }
}

##########################
sub
telnet_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "telnet");
    return if(!$chash);
    $chash->{canAsyncOutput} = 1;
    $chash->{encoding} = AttrVal($name, "encoding", "utf8");
    $chash->{prompt}  = AttrVal($name, "prompt",
                        AttrVal('global','title','fhem'));
    if($chash->{prompt} =~ m/^{.*}$/s) {
      $chash->{prompt} = eval $chash->{prompt};
      $chash->{prompt} =~ s/\n//;
    }
    $chash->{prompt} .= '>';  # Not really nice, but dont know better.
    syswrite($chash->{CD}, sprintf("%c%c%c", 255, 253, 0) )
        if( AttrVal($name, "encoding", "") ); #DO BINARY
    $chash->{CD}->flush();
    my $auth = Authenticate($chash, undef);
    syswrite($chash->{CD}, sprintf("%c%c%cPassword: ", 255, 251, 1)) # WILL ECHO
        if($auth);
    $chash->{Authenticated} = 0 if(!$auth);
    return;
  }

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 256);
  if(!defined($ret) || $ret <= 0) {
    if($hash->{isClient}) {
      telnet_ClientDisconnect($hash, 0);
    } else {
      delete $hash->{canAsyncOutput};
      CommandDelete(undef, $name);
    }
    return;
  }

  if(ord($buf) == 4) {	# EOT / ^D
    CommandQuit($hash, "");
    return;
  }

  $buf =~ s/\r//g;
  my $sname = ($hash->{isClient} ? $name : $hash->{SNAME});
  if(!defined($hash->{Authenticated}) || $hash->{Authenticated}) {
    $buf =~ s/\xff..//g;              # Telnet IAC stuff
    $buf =~ s/\xfd(.)//;              # Telnet Do ?
    syswrite($hash->{CD}, sprintf("%c%c%c", 0xff, 0xfc, ord($1)))
                      if(defined($1)) # Wont / ^C handling
  }
  $hash->{BUF} .= $buf;
  my @ret;
  my $gotCmd;

  while($hash->{BUF} =~ m/\n/) {
    my ($cmd, $rest) = split("\n", $hash->{BUF}, 2);
    $hash->{BUF} = $rest;

    if(!defined($hash->{Authenticated})) {
      syswrite($hash->{CD}, sprintf("%c%c%c\r\n", 255, 252, 1)); # WONT ECHO

      if(Authenticate($hash, $cmd) != 2) {
        $hash->{Authenticated} = 1;
        next;
      } else {
        if($hash->{isClient}) {
          telnet_ClientDisconnect($hash, 0);
        } else {
          delete($hash->{rcvdQuit});
          CommandDelete(undef, $name);
        }
        return;
      }
    }

    $gotCmd = 1;
    if($cmd || $hash->{prevlines}) {
      if($cmd =~ m/\\\s*$/) {                     # Multi-line
        $cmd =~ s/\\\s*$//;
        $hash->{prevlines} .= $cmd . "\n";
      } else {
        if($hash->{prevlines}) {
          $cmd = $hash->{prevlines} . $cmd;
          undef($hash->{prevlines});
        }
        $cmd = latin1ToUtf8($cmd) if( $hash->{encoding} eq "latin1" );
        $ret = AnalyzeCommandChain($hash, $cmd);
        push @ret, $ret if(defined($ret));
      }
    } else {
      $hash->{showPrompt} = 1;                  # Empty return
      if(!$hash->{motdDisplayed}) {
        my $motd = $attr{global}{motd};
        push @ret, $motd if($motd && $motd ne "none");
        $hash->{motdDisplayed} = 1;
      }
    }
    next if($rest);
  }

  $ret = "";
  $ret .= (join("\n", @ret) . "\n") if(@ret);
  $ret .= ($hash->{prevlines} ? "> " : $hash->{prompt}." ")
          if($gotCmd && $hash->{showPrompt} && !$hash->{rcvdQuit});

  $ret =~ s/\n/\r\n/g if($hash->{Authenticated});  # only for DOS telnet 
  telnet_Output($hash, $ret, 1);

  if($hash->{rcvdQuit}) {
    if($hash->{isClient}) {
      delete($hash->{rcvdQuit});
      telnet_ClientDisconnect($hash, 0);
    } else {
      CommandDelete(undef, $name);
    }
  }
}

sub
telnet_Output($$$)
{
  my ($hash,$ret,$nonl) = @_;

  if($ret) {
    $ret = utf8ToLatin1($ret) if( $hash->{encoding} eq "latin1" );
    if(!$nonl) {        # AsyncOutput stuff
      $ret = "\n$ret\n$hash->{prompt} " if( $hash->{showPrompt});
      $ret = "$ret\n"                   if(!$hash->{showPrompt});
    }
    for(;;) {
      utf8::encode($ret) if(utf8::is_utf8($ret) && $ret =~ m/[^\x00-\xFF]/);
      my $l = syswrite($hash->{CD}, $ret);
      last if(!$l || $l == length($ret));
      $ret = substr($ret, $l);
    }
    $hash->{CD}->flush();

  }

  return undef;
}

##########################
sub
telnet_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my @a = @_;
  my $hash = $defs{$devName};

  if($type eq "set" && $attrName eq "SSL") {
    TcpServer_SetSSL($hash);
    if($hash->{CD}) {
      my $ret = IO::Socket::SSL->start_SSL($hash->{CD});
      Log3 $devName, 1, "$hash->{NAME} start_SSL: $ret" if($ret);
    }
  }

  if(($attrName eq "allowedCommands" ||
      $attrName eq "password" ||
      $attrName eq "globalpassword" ) && $type eq "set") {
    my $aName = "allowed_$devName";
    my $exists = ($defs{$aName} ? 1 : 0);
    AnalyzeCommand(undef, "defmod $aName allowed");
    AnalyzeCommand(undef, "attr $aName validFor $devName");
    AnalyzeCommand(undef, "attr $aName $attrName ".join(" ",@param));
    return "$devName: ".($exists ? "modifying":"creating").
                " device $aName for attribute $attrName";
  }

  return undef;
}

sub
telnet_Undef($$)
{
  my ($hash, $arg) = @_;
  delete($logInform{$hash->{NAME}});
  delete($inform{$hash->{NAME}});
  return TcpServer_Close($hash);
}

#####################################
sub
CommandTelnetInform($$)
{
  my ($cl, $param) = @_;

  return if(!$cl);
  my $name = $cl->{NAME};

  return "Usage: inform {on|onWithState|off|raw|timer|log|status} [regexp]"
        if($param !~ m/^(on|onWithState|off|raw|timer|log|status)/);

  if($param eq "status") {
    my $i = $inform{$name};
    return $i ? ($i->{type} . ($i->{regexp} ? " ".$i->{regexp} : "")) : "off";
  }

  if($param eq "off") {
    delete($logInform{$name});
    delete($inform{$name});

  } elsif($param eq "log") {
    $logInform{$name} = sub($$){
      my ($me, $msg) = @_; # _NO_ Log3 here!
      telnet_Output($defs{$me}, $msg."\n", 1);
    }
    
  } elsif($param ne "off") {
    my ($type, $regexp) = split(" ", $param);
    $inform{$name}{NR} = $cl->{NR};
    $inform{$name}{type} = $type;
    if($regexp) {
      eval { "Hallo" =~ m/$regexp/ };
      return "Bad regexp: $@" if($@);
      $inform{$name}{regexp} = $regexp;
    }
    Log 4, "Setting inform to $param";

  }

  return undef;
}

sub
telnet_ActivateInform($)
{
  my ($cl) = @_;
  CommandTelnetInform($cl, "log");
}


1;

=pod
=item helper
=item summary    telnet server for FHEM
=item summary_DE FHEM telnet Server
=begin html

<a name="telnet"></a>
<h3>telnet</h3>
<ul>
  <br>
  <a name="telnetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; telnet &lt;portNumber&gt;
    [global|hostname]</code><br>

    or<br>
    <code>define &lt;name&gt; telnet &lt;servername&gt;:&lt;portNumber&gt;</code>
    <br><br>

    First form, <b>server</b> mode:<br>
    Listen on the TCP/IP port <code>&lt;portNumber&gt;</code> for incoming
    connections. If the second parameter is <b>not</b> specified,
    the server will only listen to localhost connections. If the second
    parameter is global, telnet will listen on all interfaces, else it wil try
    to resolve the parameter as a hostname, and listen only on this interface.
    <br>
    To use IPV6, specify the portNumber as IPV6:&lt;number&gt;, in this
    case the perl module IO::Socket:INET6 will be requested.
    On Linux you may have to install it with cpan -i IO::Socket::INET6 or
    apt-get libio-socket-inet6-perl; OSX and the FritzBox-7390 perl already has
    this module.<br>
    Examples:
    <ul>
        <code>define tPort telnet 7072 global</code><br>
        <code>attr tPort SSL</code><br>
        <code>attr allowed_tPort allowed</code><br>
        <code>attr allowed_tPort validFor tPort</code><br>
        <code>attr allowed_tPort globalpassword mySecret</code><br>
    </ul>
    Note: The old global attribute port is automatically converted to a
    telnet instance with the name telnetPort. The global allowfrom attibute is
    lost in this conversion.

    <br><br>
    Second form, <b>client</b> mode:<br>
    Connect to the specified server port, and execute commands received from
    there just like in server mode. This can be used to connect to a fhem
    instance sitting behind a firewall, when installing exceptions in the
    firewall is not desired or possible. Note: this client mode supprts SSL,
    but not IPV6.<br>
    Example:
    <ul>
      Start tcptee first on publicly reachable host outside the firewall.<ul>
        perl contrib/tcptee.pl --bidi 3000</ul>
      Configure fhem inside the firewall:<ul>
        define tClient telnet &lt;tcptee_host&gt;:3000</ul>
      Connect to the fhem from outside of the firewall:<ul>
        telnet &lt;tcptee_host&gt; 3000</ul>
    </ul>

  </ul>
  <br>


  <a name="telnetset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="telnetget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="telnetattr"></a>
  <b>Attributes:</b>
  <ul>
    <a name="prompt"></a>
    <li>prompt<br>
        Sets the string for the telnet prompt, the default is fhem&gt;
        </li><br>

    <a name="SSL"></a>
    <li>SSL<br>
        Enable SSL encryption of the connection, see the description <a
        href="#HTTPS">here</a> on generating the needed SSL certificates. To
        connect to such a port use one of the following commands:
        <ul>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </ul>
        </li><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set, only connections
        from these addresses are allowed.<br>
        NOTE: if this attribute is not defined and there is no valid allowed
        device defined for the telnet/FHEMWEB instance and the client tries to
        connect from a non-local net, then the connection is refused. Following
        is considered a local net:<br>
        <ul>
          IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16<br>
          IPV6: ::1, fe80/10<br>
        </ul>
        </li><br>

    <a name="connectTimeout"></a>
    <li>connectTimeout<br>
        Wait at maximum this many seconds for the connection to be established.
        Default is 2.
        </li><br>

    <a name="connectInterval"></a>
    <li>connectInterval<br>
        After closing a connection, or if a connection cannot be estblished,
        try to connect again after this many seconds. Default is 60.
        </li><br>

    <a name="encoding"></a>
    <li>encoding<br>
        Sets the encoding for the data send to the client. Possible values are
        latin1 and utf8. Default is utf8.
        </li><br>

     <li>sslVersion<br>
        See the global attribute sslVersion.
        </li><br>
     <li>sslCertPrefix<br>
        Set the prefix for the SSL certificate, default is certs/server-, see
        also the SSL attribute.
        </li><br>

  </ul>

</ul>

=end html

=begin html_DE

<a name="telnet"></a>
<h3>telnet</h3>
<ul>
  <br>
  <a name="telnetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; telnet &lt;portNumber&gt;
    [global|hostname]</code><br> oder<br>

    <code>define &lt;name&gt; telnet &lt;servername&gt;:&lt;portNummer&gt;</code>
    <br><br>

    Erste Form, <b>Server</b>-mode:<br>
    &Uuml;berwacht den TCP/IP-Port <code>&lt;portNummer&gt;</code> auf
    ankommende Verbindungen. Wenn der zweite Parameter <b>nicht</b>
    angegeben wird, wird der Server nur auf Verbindungen von localhost achten.
    Falls der zweite Parameter global ist, dann wird telnet auf allen lokalen
    Netzwerk-Interfaces zuh&ouml;ren, ansonsten wird der Parameter als Hostname
    oder Adresse interpretiert, und nur diese lokale Adresse bedient.
    <br>
    F&uuml;r den Gebrauch von IPV6 muss die Portnummer als IPV6:&lt;nummer&gt;
    angegeben werden, in diesem Fall wird das Perl-Modul IO::Socket:INET6
    angesprochen. Unter Linux kann es sein, dass dieses Modul mittels cpan -i
    IO::Socket::INET6 oder apt-get libio-socket-inet6-perl nachinstalliert werden
    muss; OSX und Fritzbox-7390 enthalten bereits dieses Modul.<br>

    Beispiele:
    <ul>
        <code>define tPort telnet 7072 global</code><br>
        <code>attr tPort SSL</code><br>
        <code>attr allowed_tPort allowed</code><br>
        <code>attr allowed_tPort validFor tPort</code><br>
        <code>attr allowed_tPort globalpassword mySecret</code><br>
    </ul>
    Hinweis: Das alte (pre 5.3) "global attribute port" wird automatisch in
    eine telnet-Instanz mit dem Namen telnetPort umgewandelt. Im Rahmen dieser
    Umwandlung geht das globale Attribut allowfrom verloren.

    <br><br>
    Zweite Form, <b>Client</b>-mode:<br>
    Verbindet zu einem angegebenen Server-Port und f&uuml;hrt die von dort aus
    empfangenen Anweisungen - genau wie im Server-mode - aus. Dies kann
    verwendet werden, um sich mit einer fhem-Instanz, die sich hinter einer
    Firewall befindet, zu verbinden, f&uuml;r den Fall, wenn das Installieren
    von Ausnahmen in der Firewall nicht erw&uuml;nscht oder nicht m&ouml;glich
    sind. Hinweis: Dieser Client-mode unterst&uuml;tzt zwar SSL, aber nicht
    IPV6.<br>

    Beispiel:
    <ul>
      Starten von tcptee auf einem &ouml;ffentlich erreichbaren Host ausserhalb
      der Firewall:<ul>
        <code>perl contrib/tcptee.pl --bidi 3000</code></ul>
      Konfigurieren von fhem innerhalb der Firewall:<ul>
        <code>define tClient telnet &lt;tcptee_host&gt;:3000</code></ul>
      Verbinden mit fhem (hinter der Firewall) von ausserhalb der Firewall:<ul>
        <code>telnet &lt;tcptee_host&gt; 3000</code></ul>
    </ul>

  </ul>
  <br>


  <a name="telnetset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="telnetget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="telnetattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="prompt"></a>
    <li>prompt<br>
        Gibt die Zeichenkette an, welche in der Telnet-Sitzung als
        Kommandoprompt ausgegeben wird. Die Voreinstellung ist fhem&gt;
        </li><br>

    <a name="SSL"></a>
    <li>SSL<br>
        SSL-Verschl&uuml;sselung f&uuml;r eine Verbindung aktivieren. <a
        href="#HTTPS">Hier</a> gibt es eine Beschreibung, wie das erforderliche
        SSL-Zertifikat generiert werden kann. Um eine Verbindung mit solch
        einem Port herzustellen, sind folgende Befehle m&ouml;glich:
        <ul>
        <code>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </code>
        </ul>		
	</li><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp der erlaubten IP-Adressen oder Hostnamen. Wenn dieses Attribut
        gesetzt wurde, werden ausschlie&szlig;lich Verbindungen von diesen
        Adressen akzeptiert.<br>
        Achtung: falls allowfrom nicht gesetzt ist, und keine g&uuml;tige
        allowed Instanz definiert ist, und die Gegenstelle eine nicht lokale
        Adresse hat, dann wird die Verbindung abgewiesen. Folgende Adressen
        werden als local betrachtet:
        <ul>
          IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16<br>
          IPV6: ::1, fe80/10<br>
        </ul>
        </li><br>

    <a name="connectTimeout"></a>
    <li>connectTimeout<br>
        Gibt die maximale Wartezeit in Sekunden an, in der die Verbindung
        aufgebaut sein muss. Standardwert ist 2.
    </li><br>

    <a name="connectInterval"></a>
    <li>connectInterval<br>
        Gibt die Dauer an, die entweder nach Schlie&szlig;en einer Verbindung
        oder f&uuml;r den Fall, dass die Verbindung nicht zustande kommt,
        gewartet werden muss, bis ein erneuter Verbindungsversuch gestartet
        werden soll. Standardwert ist 60.
        </li><br>

    <a name="encoding"></a>
    <li>encoding<br>
        Bezeichnet die Zeichentabelle f&uuml;r die zum Client gesendeten Daten.
        M&ouml;gliche Werte sind utf8 und latin1. Standardwert ist utf8. 
    </li><br>

     <li>sslVersion<br>
        Siehe das global Attribut sslVersion.
        </li><br>

     <li>sslCertPrefix<br>
       Setzt das Pr&auml;fix der SSL-Zertifikate, die Voreinstellung ist
       certs/server-, siehe auch das SSL Attribut.
      </li><br>

  </ul>

</ul>

=end html_DE

=cut

1;
