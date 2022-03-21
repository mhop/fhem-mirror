##############################################
# $Id$

package main;
use strict;
use warnings;
use IO::Socket;
use vars qw($SSL_ERROR);

my ($joinGroup, $leaveGroup, $multiCastLoop, $addMembership, $dropMembership);

# Perl 5.16 / wheezy compatibility mode / #126290
eval "Socket::IPV6_JOIN_GROUP";
if($@) {
  $joinGroup      = 20;
  $leaveGroup     = 21;
  $multiCastLoop  = 34;
  $addMembership  = 35;
  $dropMembership = 36;

} else {
  $joinGroup      = eval "Socket::IPV6_JOIN_GROUP";
  $leaveGroup     = eval "Socket::IPV6_LEAVE_GROUP";
  $multiCastLoop  = eval "Socket::IP_MULTICAST_LOOP";
  $addMembership  = eval "Socket::IP_ADD_MEMBERSHIP";
  $dropMembership = eval "Socket::IP_DROP_MEMBERSHIP";

}

sub
TcpServer_Open($$$;$)
{
  my ($hash, $port, $global, $multicast) = @_;
  my $name = $hash->{NAME};

  return 'multicast not supported without SO_REUSEPORT'
        if($multicast && !defined(&SO_REUSEPORT));

  if($port =~ m/^IPV6:(\d+)$/i) {
    $port = $1;
    eval "require IO::Socket::INET6; use Socket6;";
    if($@) {
      Log3 $hash, 1, $@;
      Log3 $hash, 1, "$name: Can't load INET6, falling back to IPV4";
    } else {
      $hash->{IPV6} = 1;
    }
  }

  my $lh = ($global ? ($global eq "global"? undef : $global) :
                      ($hash->{IPV6} ? "::1" : "127.0.0.1"));
  my %opts = (
    Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC), # Linux bug / #126448
    LocalHost => $lh,
    LocalPort => $port,
    Listen    => 32,    # For Windows
    Blocking  => ($^O =~ /Win/ ? 1 : 0), # Needed for .WRITEBUFFER@darwin
    ReuseAddr => 1
  );
  
  if($multicast) {
    $opts{ReusePort} = 1;
    $opts{Proto} = 'udp';
    delete($opts{Listen});
    $hash->{MULTICAST} = $multicast;
  }

  readingsSingleUpdate($hash, "state", "Initialized", 0);
  $hash->{SERVERSOCKET} = $hash->{IPV6} ?
        IO::Socket::INET6->new(%opts) : 
        IO::Socket::INET->new(%opts);

  if(!$hash->{SERVERSOCKET}) {
    return "$name: Can't open server port at $port: $!";
  }

  $hash->{FD} = $hash->{SERVERSOCKET}->fileno();
  $hash->{PORT} = $hash->{SERVERSOCKET}->sockport();

  $selectlist{"$name.$port"} = $hash;
  Log3 $hash, 3, "$name: port ". $hash->{PORT} ." opened";
  return undef;
}

sub
TcpServer_SetLoopbackMode($$)
{
  my ($hash, $loopback) = @_;
  my $name = $hash->{NAME};
  my $sock = $hash->{SERVERSOCKET};

  my $old;
  if( !$hash->{IPV6} && $sock->sockdomain() == AF_INET ) {
    my $packed = getsockopt($sock, Socket::IPPROTO_IP, $multiCastLoop);
    if( !$packed ) {
      Log3 $name, 1, "$name: failed to get loopback mode: $!";
      return undef;
    }
    $old = unpack("I", $packed);

    if( !setsockopt($sock, Socket::IPPROTO_IP,
                    $multiCastLoop, pack("I", $loopback ) ) ) {
      Log3 $name, 1, "$name: could not set loopback mode: $!";
      return undef;
    }

  } elsif( !$hash->{IPV6} && $sock->sockdomain() == AF_INET6 ) {
    my $packed = getsockopt($sock, Socket::IPPROTO_IPV6,
                            Socket::IPV6_MULTICAST_LOOP);
    if( !$packed ) {
      Log3 $name, 1, "$name: failed to get loopback mode: $!";
      return undef;
    }
    $old = unpack("I", $packed);

    if( setsockopt($sock, Socket::IPPROTO_IPV6,
                   Socket::IPV6_MULTICAST_LOOP, pack("I", $loopback ) ) ) {
      Log3 $name, 1, "$name: could not set loopback mode: $!";
      return undef;
    }

  } else {
    Log3 $name, 1,
        "$name: TcpServer_SetLoopbackMode failed: unsupported socket family";
    return undef;
  }

  return $old;
}

sub
TcpServer_MCastAdd($$)
{
  my ($hash, $addr) = @_;
  my $name = $hash->{NAME};
  my $sock = $hash->{SERVERSOCKET};

  $hash->{ADDR} = $addr;

  # disable loopback
  TcpServer_SetLoopbackMode($hash, 0);

  # add multicast address
  if(!$hash->{IPV6} && $sock->sockdomain() == AF_INET) {
    my $ip_mreq = Socket::pack_ip_mreq( inet_aton( $addr ), INADDR_ANY );
    setsockopt($sock, Socket::IPPROTO_IP, $addMembership, $ip_mreq )
      or return "$name: could not set IP_ADD_MEMBERSHIP socket option: $!";

  } elsif($hash->{IPV6} && $sock->sockdomain() == AF_INET6) {
    my $ipv6_mreq = Socket::pack_ipv6_mreq( inet_pton( AF_INET6, $addr ), 0 );
    setsockopt($sock, Socket::IPPROTO_IPV6, $joinGroup, $ipv6_mreq )
      or return "$name: could not set IPV6_JOIN_GROUP socket option: $!";

  } else {
    return("$name: TcpServer_MCastAdd failed: unsupported socket family" );

  }

  readingsSingleUpdate($hash, "state", "Multicast listen", 0);

  return undef;
}

sub
TcpServer_MCastRecv($$$;$)
{
  my ($hash, undef, $length, $flags) = @_;
  my $name = $hash->{NAME};
  my $sock = $hash->{SERVERSOCKET};

  my $sockaddr = $sock->recv($_[1], $length, $flags);
  if(!$hash->{IPV6} && $sock->sockdomain() == AF_INET) {
    my ($peer_port, $addr) = Socket::unpack_sockaddr_in($sockaddr);
    my $peer_host = inet_ntoa($addr);
    return $peer_host, $peer_port;

  } elsif($hash->{IPV6} && $sock->sockdomain() == AF_INET6) {
    my ($peer_port, $addr) = Socket::unpack_sockaddr_in6($sockaddr);
    my $peer_host = inet_ntop(AF_INET6(),$addr);
    return $peer_host, $peer_port;

  } else {
    Log3 $name, 1,"$name: TcpServer_MCastRecv failed: unsupported socket family";
    return undef;
  }
}

sub
TcpServer_MCastSend($$;$$)
{
  my ($hash, $data, $addr, $port) = @_;
  my $name = $hash->{NAME};
  my $sock = $hash->{SERVERSOCKET};

  $addr = $hash->{ADDR} if( !$addr );
  $port = $hash->{PORT} if( !$port );

  if( !$addr ) {
    Log3 $name, 1, "$name: TcpServer_MCastSend failed: address unknown";
    return undef;
  }
  if( !$port ) {
    Log3 $name, 1, "$name: TcpServer_MCastSend failed: port unknown";
    return undef;
  }

  if(!$hash->{IPV6} && $sock->sockdomain() == AF_INET) {
    my $sockaddr = Socket::pack_sockaddr_in($port, inet_aton($addr));
    return $sock->send($data,0,$sockaddr);

  } elsif($hash->{IPV6} && $sock->sockdomain() == AF_INET6) {
    my $sockaddr = Socket::pack_sockaddr_in6($port, inet_pton($addr));
    return $sock->send($data,0,$sockaddr);

  } else {
    Log3 $name, 1,"$name: TcpServer_MCastSend failed: unsupported socket family";
    return undef;
  }

}

sub
TcpServer_MCastRemove($$)
{
  my ($hash, $addr) = @_;
  my $name = $hash->{NAME};
  my $sock = $hash->{SERVERSOCKET};

  delete $hash->{ADDR};

  if(!$hash->{IPV6} && $sock->sockdomain() == AF_INET) {
    my $ip_mreq = Socket::pack_ip_mreq( inet_aton( $addr ), INADDR_ANY );
    setsockopt($sock, Socket::IPPROTO_IP, $dropMembership, $ip_mreq )
      or return "$name: could not set IP_DROP_MEMBERSHIP socket option: $!";

  } elsif($hash->{IPV6} && $sock->sockdomain() == AF_INET6) {
    my $ipv6_mreq = Socket::pack_ipv6_mreq( inet_pton( AF_INET6, $addr ), 0 );
    setsockopt($sock, Socket::IPPROTO_IPV6, $leaveGroup, $ipv6_mreq) 
      or return "$name: could not set IPV6_LEAVE_GROUP socket option: $!";

  } else {
    return("$name: TcpServer_MCastRemove failed: unsupported socket family" );

  }

  readingsSingleUpdate($hash, "state", "Multicast listen stopped", 0);
  return undef;
}

sub
TcpServer_Accept($$)
{
  my ($hash, $type) = @_;
  my $name = $hash->{NAME};

  if($hash->{MULTICAST}) {
    Log3 $name, 1, "$name: can't accept on a mutlicast socket";
    return undef;
  }

  my @clientinfo = $hash->{SERVERSOCKET}->accept();
  if(!@clientinfo) {
    Log3 $name, 1, "Accept failed ($name: $!)" if($! != EAGAIN);
    return undef;
  }
  $hash->{CONNECTS}++;

  my ($port, $iaddr) = $hash->{IPV6} ? 
      sockaddr_in6($clientinfo[1]) :
      sockaddr_in($clientinfo[1]);
  my $caddr = $hash->{IPV6} ?
                inet_ntop(AF_INET6(), $iaddr) :
                inet_ntoa($iaddr);

  my $af = $attr{$name}{allowfrom};
  if(!$af) {
    my $re ="^(::ffff:)?(127|192.168|172.(1[6-9]|2[0-9]|3[01])|10|169.254)\\.|".
            "^(f[cde]|::1)";
    if($caddr !~ m/$re/) {
      my %empty;
      $hash->{SNAME} = $hash->{NAME};
      my $auth = Authenticate($hash, \%empty);
      delete $hash->{SNAME};
      if($auth == 0) {
        Log3 $name, 1,
             "Connection refused from the non-local address $caddr:$port, ".
             "as there is no working allowed instance defined for it";
        close($clientinfo[0]);
        return undef;
      }
    }
  }

  if($af) {
    if($caddr !~ m/$af/) {
      my $hostname = gethostbyaddr($iaddr, AF_INET);
      if(!$hostname || $hostname !~ m/$af/) {
        Log3 $name, 1, "Connection refused from $caddr:$port";
        close($clientinfo[0]);
        return undef;
      }
    }
  }

  #$clientinfo[0]->blocking(0);  # Forum #24799

  if($hash->{SSL}) {
    # Forum #27565: SSLv23:!SSLv3:!SSLv2', #35004: TLSv12:!SSLv3
    my $sslVersion = AttrVal($hash->{NAME}, "sslVersion", 
                     AttrVal("global", "sslVersion", undef));

    # Certs directory must be in the modpath, i.e. at the same level as the
    # FHEM directory
    my $mp = AttrVal("global", "modpath", ".");
    my $certPrefix = AttrVal($name, "sslCertPrefix", "certs/server-");
    my $ret;
    eval {
      $ret = IO::Socket::SSL->start_SSL($clientinfo[0], {
        SSL_server    => 1, 
        SSL_key_file  => "$mp/${certPrefix}key.pem",
        SSL_cert_file => "$mp/${certPrefix}cert.pem",
        SSL_version => $sslVersion,
        SSL_cipher_list => 'HIGH:!RC4:!eNULL:!aNULL',
        Timeout       => 4,
        });
      $! = EINVAL if(!$clientinfo[0]->blocking() && $!==EWOULDBLOCK);
    };
    my $err = $!;
    if( !$ret
      && $err != EWOULDBLOCK
      && $err ne "Socket is not connected") {
      $err = "" if(!$err);
      $err .= " ".($SSL_ERROR ? $SSL_ERROR : IO::Socket::SSL::errstr());
      my $errLevel = ($err =~ m/error:14094416:SSL/ ? 5 : 1); # 61511
      Log3 $name, $errLevel, "$type SSL/HTTPS error: $err (peer: $caddr)"
        if($err !~ m/error:00000000:lib.0.:func.0.:reason.0./); #Forum 56364
      close($clientinfo[0]);
      return undef;
    }
  }

  my $cname = "${name}_${caddr}_${port}";
  my %nhash;
  $nhash{NR}    = $devcount++;
  $nhash{NAME}  = $cname;
  $nhash{PEER}  = $caddr;
  $nhash{PORT}  = $port;
  $nhash{FD}    = $clientinfo[0]->fileno();
  $nhash{CD}    = $clientinfo[0];     # sysread / close won't work on fileno
  $nhash{TYPE}  = $type;
  $nhash{SSL}   = $hash->{SSL};
  readingsSingleUpdate(\%nhash, "state", "Connected", 0);
  $nhash{SNAME} = $name;
  $nhash{TEMPORARY} = 1;              # Don't want to save it
  $nhash{BUF}   = "";
  $attr{$cname}{room} = "hidden";
  $defs{$cname} = \%nhash;
  $selectlist{$nhash{NAME}} = \%nhash;

  my $ret = $clientinfo[0]->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);

  Log3 $name, 4, "Connection accepted from $nhash{NAME}";
  return \%nhash;
}

sub
TcpServer_SetSSL($)
{
  my ($hash) = @_; 
  eval "require IO::Socket::SSL";
  if($@) {
    Log3 $hash, 1, $@;
    Log3 $hash, 1, "Can't load IO::Socket::SSL, falling back to HTTP";
    return;
  }

  my $name = $hash->{NAME};
  my $cp = AttrVal("global", "modpath", ".")."/".
           AttrVal($name, "sslCertPrefix", "certs/server-");
  if(! -r "${cp}key.pem") {

    Log 1, "$name: Server certificate missing, trying to create one";
    if($cp =~ m,^(.*)/(.*?), && ! -d $1 && !mkdir($1)) {
      Log 1, "$name: failed to create $1: $!, falling back to HTTP";
      return;
    }

    if(!open(FH,">certreq.txt")) {
      Log 1, "$name: failed to create certreq.txt: $!, falling back to HTTP";
      return;
    }
    my $hostname = `hostname`;
    chomp($hostname);
    print FH << "EOF";
[ req ]
prompt = no
distinguished_name = dn
x509_extensions = ext

[ dn ]
CN = $hostname
O = FHEM
OU = localhost

[ ext ]
basicConstraints=CA:TRUE
extendedKeyUsage = serverAuth
subjectAltName=\@san

[san]
DNS.1=localhost
DNS.2=$hostname
IP.1=127.0.0.1
IP.2=::1
EOF

    close(FH);

    my $cmd = "openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 ".
                "-config certreq.txt -out ${cp}cert.pem -keyout ${cp}key.pem";
    Log 1, "Executing $cmd";
    `$cmd`;
    unlink("certreq.txt");
  }
  $hash->{SSL} = 1;
}


sub
TcpServer_Close($@)
{
  my ($hash, $dodel, $ignoreNtfy) = @_;
  my $name = $hash->{NAME};

  if(defined($hash->{CD})) { # Clients
    close($hash->{CD});
    delete($hash->{CD}); 
    delete($selectlist{$name});
    delete($hash->{FD});  # Avoid Read->Close->Write
    removeFromNtfyHash($name) if(!$ignoreNtfy); # can be expensive
  }

  if(defined($hash->{SERVERSOCKET})) {          # Server
    close($hash->{SERVERSOCKET});
    $name = $name . "." . $hash->{PORT};
    delete($selectlist{$name});
    delete($hash->{FD});  # Avoid Read->Close->Write
  }

  if($dodel) {
    delete $attr{$name};
    delete $defs{$name};
  } else {
    $hash->{stacktrace} = stacktraceAsString(1);
  }
  return undef;
}

# close a (SSL-)Socket in local process
# avoids interfering with other processes using it
# this is critical for SSL and helps with other issues, too 
sub
TcpServer_Disown($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( defined($hash->{CD}) ){
    if( $hash->{SSL} ){
      $hash->{CD}->close( SSL_no_shutdown => 1);
    } else {
      close( $hash->{CD} );
    }
    delete($hash->{CD});
    delete($selectlist{$name});
    delete($hash->{FD});  # Avoid Read->Close->Write
    $hash->{stacktrace} = stacktraceAsString(1);
  }

  return;
}

# wait for a socket to become ready
# takes IO::Socket::SSL + non-blocking into account
sub
TcpServer_Wait($$)
{
  my( $hash, $direction ) = @_;

  my $read = '';
  my $write ='';

  if( $direction eq 'read' || $hash->{wantRead} ){
    vec( $read, $hash->{FD}, 1) = 1;
  } elsif( $direction eq 'write' || $hash->{wantWrite} ){
    vec( $write, $hash->{FD}, 1) = 1;
  } else {
    return undef;
  }

  my $ret = select( $read, $write, undef, undef );
  return if $ret == -1;

  if( vec( $read, $hash->{FD}, 1) ){
    delete $hash->{wantRead};
  }
  if( vec( $write, $hash->{FD}, 1) ){
    delete $hash->{wantWrite};
  }

  # return true on success
  return 1;
}

# WantRead/Write: keep ssl constants local
sub
TcpServer_WantRead($)
{
  my( $hash ) = @_;

  return $hash->{SSL}
	&& $hash->{CD}
	&& $hash->{CD}->errstr == &IO::Socket::SSL::SSL_WANT_READ;
}

sub
TcpServer_WantWrite($)
{
  my( $hash ) = @_;

  return $hash->{SSL}
	&& $hash->{CD}
	&& $hash->{CD}->errstr == &IO::Socket::SSL::SSL_WANT_WRITE;
}

# write until all data is done.
# hanldes both, blocking and non-blocking sockets
# ... with or without SSL
sub
TcpServer_WriteBlocking($$)
{
  my( $hash, $txt ) = @_;

  if($hash->{WriteFn}) { # FWTP needs it
    no strict "refs";
    return &{$hash->{WriteFn}}($hash, \$txt);
    use strict "refs";
  }

  my $sock = $hash->{CD};
  return undef if(!$sock);
  my $off = 0;
  my $len = length($txt);

  while($off < $len) {
    if(!TcpServer_Wait($hash, 'write')) {
      TcpServer_Close($hash);
      return undef;
    }

    my $ret;
    eval { $ret = syswrite($sock, $txt, $len-$off, $off); }; # Wide character
    if($@) {
      Log 1, $@;
      Log 1, "txt:".join(":",unpack("C*",$txt)).",len:$len,off:$off";
      stacktrace();
    }

    if( defined $ret ){
      $off += $ret;
      my $sh = $defs{$hash->{SNAME}};
      $sh->{BYTES_WRITTEN} += $ret if(defined($sh->{BYTES_WRITTEN}));

    } elsif( $! == EWOULDBLOCK ){
      $hash->{wantRead} = 1
        if TcpServer_WantRead($hash);

    } else {
      TcpServer_Close($hash);
      return undef; # error
    }
  }

  return 1; # success
}

=pod

Multicast:
(https://forum.fhem.de/index.php/topic,126290.msg1209591.html#msg1209591)
verwendet wird es so:
- das socket mit gesetztem optionalen vierten paramter von TcpServer_Open
  erzeugen: d.h. im define oder sonst wo mit my $ret = TcpServer_Open($hash,
  '5353', '0.0.0.0', 1); initialisieren. statt der 0.0.0.0 kann man auch die
  multicast adresse angeben, ich bin mir nicht sicher was richtiger ist und ob
  es einen unterschied macht. funktionieren tut bei mir beides.
- TcpServer_Open schaltet automatisch den loopback mode aus.  d.h. man empfängt
  seine eigenen daten nicht. ich vermute das ist der normalfall.  mit
  TcpServer_SetLoopbackMode($hash,[0|1]); kann man das ändern wenn man es
  braucht.
- mit TcpServer_MCastAdd die multicast adresse zum socket explizit hinzufügen:
  z.b.: TcpServer_MCastAdd($hash,'224.0.0.251'); erst ab jetzt bekommt man auch
  tatsächlich daten.
- im (device) hash wird für jedes udp packet die ReadFn aufgerufen.  dort kann
  man mit TcpServer_MCastRecv dann die empfangenen daten abholen:
  my($peer_host, $peer_port) = TcpServer_MCastRecv($hash,$data,$length);

  alternativ kann man auch die low leven routinen direkt aufrufen:
  - my $sockaddr = $hash->{SERVERSOCKET}->recv($data, 4096);
    der empfang geht über SERVERSOCKET, nicht wie bei tcp über CD, es wird auch
    kein accept verwendet
  - aus $sockaddr kann man sich die gegenstelle zum udp packet holen falls man
    die braucht:
    my ($peer_port, $addr) = Socket::sockaddr_in($sockaddr);
    my $peer_host = inet_ntoa($addr);
- eigene daten sendet man mit TcpServer_MCastSend:
  TcpServer_MCastSend($hash,$data[,$host[,$port]]); hier bei wird der port aus
  dem TcpServer_Open und die adresse aus TcpServer_MCastAdd verwendet.
  alternativ kann man beides auch beim aufruf mitgeben.
- mit TcpServer_MCastRemove kann man die multicast adresse auch wieder vom
  socket entfernen:
  z.b.: TcpServer_MCastRemove($hash,'224.0.0.251');
  das socket empfängt dann keine daten für diese adresse mehr.
- mit wechselweisem TcpServer_MCastAdd und TcpServer_MCastRemove kann man auch
  zeitweise zwischen empfangen und ignorieren hin und her wechseln. z.b. als
  reaktion auf disable.
- mit TcpServer_Close($hash); das ganze am ende z.b. in der UndefFn wieder zu
  machen.

=cut

1;
