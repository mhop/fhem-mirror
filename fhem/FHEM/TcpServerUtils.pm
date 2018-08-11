##############################################
# $Id$

package main;
use strict;
use warnings;
use IO::Socket;
use vars qw($SSL_ERROR);

sub
TcpServer_Open($$$)
{
  my ($hash, $port, $global) = @_;
  my $name = $hash->{NAME};

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
  my @opts = (
    Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC), # Linux bug
    LocalHost => $lh,
    LocalPort => $port,
    Listen    => 32,    # For Windows
    Blocking  => ($^O =~ /Win/ ? 1 : 0), # Needed for .WRITEBUFFER@darwin
    ReuseAddr => 1
  );
  readingsSingleUpdate($hash, "state", "Initialized", 0);
  $hash->{SERVERSOCKET} = $hash->{IPV6} ?
        IO::Socket::INET6->new(@opts) : 
        IO::Socket::INET->new(@opts);

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
TcpServer_Accept($$)
{
  my ($hash, $type) = @_;

  my $name = $hash->{NAME};
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
                     AttrVal("global", "sslVersion", "TLSv12:!SSLv3"));

    # Certs directory must be in the modpath, i.e. at the same level as the
    # FHEM directory
    my $mp = AttrVal("global", "modpath", ".");
    my $ret;
    eval {
      $ret = IO::Socket::SSL->start_SSL($clientinfo[0], {
        SSL_server    => 1, 
        SSL_key_file  => "$mp/certs/server-key.pem",
        SSL_cert_file => "$mp/certs/server-cert.pem",
        SSL_version => $sslVersion,
        SSL_cipher_list => 'HIGH:!RC4:!eNULL:!aNULL',
        Timeout       => 4,
        });
    };
    my $err = $!;
    if( !$ret
      && $err != EWOULDBLOCK
      && $err ne "Socket is not connected") {
      $err = "" if(!$err);
      $err .= " ".($SSL_ERROR ? $SSL_ERROR : IO::Socket::SSL::errstr());
      Log3 $name, 1, "$type SSL/HTTPS error: $err (peer: $caddr)"
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
  } else {
    $hash->{SSL} = 1;
  }
}


sub
TcpServer_Close($@)
{
  my ($hash, $dodel) = @_;
  my $name = $hash->{NAME};

  if(defined($hash->{CD})) { # Clients
    close($hash->{CD});
    delete($hash->{CD}); 
    delete($selectlist{$name});
    delete($hash->{FD});  # Avoid Read->Close->Write
    delete $attr{$name} if($dodel);
    delete $defs{$name} if($dodel);
  }
  if(defined($hash->{SERVERSOCKET})) {          # Server
    close($hash->{SERVERSOCKET});
    $name = $name . "." . $hash->{PORT};
    delete($selectlist{$name});
    delete($hash->{FD});  # Avoid Read->Close->Write
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

  my $sock = $hash->{CD};
  return undef if(!$sock);
  my $off = 0;
  my $len = length($txt);

  while($off < $len) {
    if(!TcpServer_Wait($hash, 'write')) {
      TcpServer_Close($hash);
      return undef;
    }

    my $ret = syswrite($sock, $txt, $len-$off, $off);

    if( defined $ret ){
      $off += $ret;

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

1;
