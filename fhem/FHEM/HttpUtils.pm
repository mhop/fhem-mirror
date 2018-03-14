##############################################
# $Id$
package main;

use strict;
use warnings;
use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use vars qw($SSL_ERROR);

# Note: video does not work for every browser (Forum #73214)
my %ext2MIMEType= qw{
  bmp   image/bmp
  css   text/css
  gif   image/gif
  html  text/html
  ico   image/x-icon
  jpg   image/jpeg
  js    text/javascript
  mp4   video/mp4
  pdf   application/pdf
  png   image/png
  svg   image/svg+xml
  txt   text/plain

};

my $HU_use_zlib;

sub
ext2MIMEType($) {
  my ($ext)= @_;
  return "text/plain" if(!$ext);
  my $MIMEType = $ext2MIMEType{lc($ext)};
  return ($MIMEType ? $MIMEType : "text/$ext");
}

sub
filename2MIMEType($) {
  my ($filename)= @_;
  $filename =~ m/^.*\.([^\.]*)$/;
  return ext2MIMEType($1);
}
  

##################
sub
urlEncode($) {
  $_= $_[0];
  s/([\x00-\x2F \x3A-\x40 \x5B-\x60 \x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}

sub
urlEncodePath($) {
  $_= $_[0];
  s/([\x00-\x20 \x25 \x3F \x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}

##################
sub
urlDecode($) {
  $_= $_[0];
  s/%([0-9A-F][0-9A-F])/chr(hex($1))/egi;
  return $_;
}

sub
HttpUtils_Close($)
{
  my ($hash) = @_;
  delete($hash->{FD});
  delete($selectlist{$hash});
  if(defined($hash->{conn})) {  # Forum #85640
    my $ref = eval { $hash->{conn}->can('close') };
    if($ref) {
      $hash->{conn}->close();
    } else {
      stacktrace();
    }
  }
  delete($hash->{conn});
  delete($hash->{hu_sslAdded});
  delete($hash->{hu_filecount});
  delete($hash->{hu_blocking});
  delete($hash->{hu_portSfx});
  delete($hash->{hu_proxy});
  delete($hash->{hu_port});
  delete($hash->{directReadFn});
  delete($hash->{directWriteFn});
  delete($hash->{compress});
}

sub
HttpUtils_Err($)
{
  my ($lhash, $errtxt) = @_;
  my $hash = $lhash->{hash};

  if($lhash->{sts} && $lhash->{sts} == $selectTimestamp) { # busy loop check
    Log 4, "extending '$lhash->{msg} $hash->{addr}' timeout due to busy loop";
    InternalTimer(gettimeofday()+1, "HttpUtils_Err", $lhash);
    return;
  }
  return if(!defined($hash->{FD})); # Already closed
  HttpUtils_Close($hash);
  $hash->{callback}($hash, "$lhash->{msg} $hash->{addr} timed out", "");
}

sub
HttpUtils_File($)
{
  my ($hash) = @_;

  return 0 if($hash->{url} !~ m+^file://(.*)$+);

  my $fName = $1;
  return (1, "Absolute URL is not supported") if($fName =~ m+^/+);
  return (1, ".. in URL is not supported") if($fName =~ m+\.\.+);
  open(FH, $fName) || return(1, "$fName: $!");
  my $data = join("", <FH>);
  close(FH);
  return (1, undef, $data);
}

sub
ip2str($)
{
  my ($addr) = @_;

  return sprintf("%d.%d.%d.%d", unpack("C*", $addr)) if(length($addr) == 4);
  my $h = join(":",map { sprintf("%x",$_) } unpack("n*",$addr));
  $h =~ s/(:0)+/:/g;
  $h =~ s/^0://g;
  return "[$h]";
}

# http://www.ccs.neu.edu/home/amislove/teaching/cs4700/fall09/handouts/project1-primer.pdf
my %HU_dnsCache;
sub
HttpUtils_dnsParse($$$)
{
  my ($a, $ql,$try6) = @_;    # $ql: avoid hardcoding query length
  return "wrong message ID" if(unpack("H*",substr($a,0,2)) ne "7072");

  while(length($a) >= $ql+16) {
    my $l = unpack("C",substr($a,$ql, 1));
    if(($l & 0xC0) == 0xC0) { # DNS packed compression
      $ql += 2;
    } else {
      while($l != 0) {
        $ql += $l+1;
        $l = unpack("C",substr($a,$ql,2));
      }
      $ql++;
    }
    return (undef, substr($a,$ql+10,16),unpack("N",substr($a,$ql+4,4)))
        if(unpack("N",substr($a,$ql,4)) == 0x1c0001 && $try6);
    return (undef, substr($a,$ql+10,4), unpack("N",substr($a,$ql+4,4)))
        if(unpack("N",substr($a,$ql,4)) == 0x10001 && !$try6);
    $ql += 10+unpack("n",substr($a,$ql+8)) if(length($a) >= $ql+10);
  }
  return "No A record found";
}

# { HttpUtils_gethostbyname({timeout=>4}, "google.com", 1,
#   sub(){my($h,$e,$a)=@_;; Log 1, $e ? "ERR:$e": ("IP:".ip2str($a)) }) }
sub
HttpUtils_gethostbyname($$$$)
{
  my ($hash, $host, $try6, $fn) = @_;

  if($host =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ &&        # IP-Address
     $1<256 && $2<256 && $3<256 && $4<256) {
    $fn->($hash, undef, pack("CCCC", $1, $2, $3, $4));
    return;
  }

  my $dnsServer = AttrVal("global", "dnsServer", undef);

  if(!$dnsServer) { # use the blocking libc to get the IP
    if($haveInet6) {
      $host = $1 if($host =~ m/^\[([a-f0-9:]+)\]+$/);
      my $iaddr = Socket6::inet_pton(AF_INET6, $host);
      return $fn->($hash, undef, $iaddr) if($iaddr);

      $iaddr = Socket6::inet_pton(AF_INET , $host);
      return $fn->($hash, undef, $iaddr) if($iaddr);

      my ($s4, $s6);
      my @res = Socket6::getaddrinfo($host, 80);
      for(my $i=0; $i+5<=@res; $i+=5) {
        $s4 = $res[$i+3] if($res[$i] == AF_INET  && !$s4);
        $s6 = $res[$i+3] if($res[$i] == AF_INET6 && !$s6);
      }
      if($s6) {
        (undef, $iaddr) = Socket6::unpack_sockaddr_in6($s6);
        return $fn->($hash, undef, $iaddr);
      }
      if($s4) {
        (undef, $iaddr) = sockaddr_in($s4);
        return $fn->($hash, undef, $iaddr);
      }
      $fn->($hash, "gethostbyname $host failed", undef);

    } else {
      my $iaddr = inet_aton($host);
      my $err;
      if(!defined($iaddr)) {
        $iaddr = gethostbyname($host); # This is still blocking
        $err = (($iaddr && length($iaddr)==4) ? 
                          undef : "gethostbyname $host failed");
      }
      $fn->($hash, $err, $iaddr);
    }

    return;
  }

  return $fn->($hash, undef, $HU_dnsCache{$host}{addr}) # check the cache
        if($HU_dnsCache{$host} &&
           $HU_dnsCache{$host}{TS}+$HU_dnsCache{$host}{TTL} > gettimeofday());

  my $dh = AttrVal("global", "dnsHostsFile", "undef");
  if($dh) {
    my $fh;
    if(open($fh, $dh)) {
      while(my $line = <$fh>) {
        if($line =~ m/^([^# \t]+).*\b\Q$host\E\b/) {
          if($1 =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ &&        # IP-Address
             $1<256 && $2<256 && $3<256 && $4<256) {
            $fn->($hash, undef, pack("CCCC", $1, $2, $3, $4));
            close($fh);
            return;
          }
        }
      }
      close($fh);
    }
  }

  # Direct DNS Query via UDP
  my $c = IO::Socket::INET->new(Proto=>'udp', PeerAddr=>"$dnsServer:53");
  return $fn->($hash, "Cant create UDP socket:$!", undef) if(!$c);

  my %dh = ( conn=>$c, FD=>$c->fileno(), NAME=>"DNS", origHash=>$hash,
             addr=>$dnsServer, callback=>$fn );
  my %timerHash = ( hash=>\%dh, msg=>"DNS" );
  my $bhost = join("", map { pack("CA*",length($_),$_) } split(/\./, $host));
  my $qry = pack("nnnnnn", 0x7072,0x0100,1,0,0,0) .
                $bhost . pack("Cnn", 0,$try6 ? 28:1,1);
  my $ql = length($qry);
  Log 5, "DNS QUERY ".unpack("H*", $qry);

  $dh{directReadFn} = sub() {                           # Parse the answer
    RemoveInternalTimer(\%timerHash);
    my $buf;
    my $len = sysread($dh{conn},$buf,65536);
    HttpUtils_Close(\%dh);
    Log 5, "DNS ANSWER ".($len?$len:0).":".($buf ? unpack("H*", $buf):"N/A");
    my ($err, $addr, $ttl) = HttpUtils_dnsParse($buf,$ql,$try6);
    return HttpUtils_gethostbyname($hash, $host, 0, $fn) if($err && $try6);
    return $fn->($hash, "DNS: $err", undef) if($err);
    Log 4, "DNS result for $host: ".ip2str($addr).", ttl:$ttl";
    $HU_dnsCache{$host}{TS} = gettimeofday();
    $HU_dnsCache{$host}{TTL} = $ttl;
    $HU_dnsCache{$host}{addr} = $addr;
    return $fn->($hash, undef, $addr);
  };
  $selectlist{\%dh} = \%dh;

  my $dnsQuery;
  my $dnsTo = 0.25;
  my $lSelectTs = $selectTimestamp;
  $dnsQuery = sub()
  {
    $dnsTo *= 2 if($lSelectTs != $selectTimestamp);
    $lSelectTs = $selectTimestamp;
    return HttpUtils_Err(\%timerHash) if($dnsTo > $hash->{timeout}/2);
    my $ret = syswrite $dh{conn}, $qry;
    if(!$ret || $ret != $ql) {
      my $err = $!;
      HttpUtils_Close(\%dh);
      return $fn->($hash, "DNS write error: $err", undef);
    }
    InternalTimer(gettimeofday()+$dnsTo, $dnsQuery, \%timerHash);
  };
  $dnsQuery->();
}


sub
HttpUtils_Connect($)
{
  my ($hash) = @_;

  $hash->{timeout}    = 4 if(!defined($hash->{timeout}));
  $hash->{loglevel}   = 4 if(!$hash->{loglevel});
  $hash->{redirects}  = 0 if(!$hash->{redirects});
  $hash->{displayurl} = $hash->{hideurl} ? "<hidden>" : $hash->{url};
  $hash->{sslargs}    = {} if(!defined($hash->{sslargs}));

  Log3 $hash, $hash->{loglevel}+1, "HttpUtils url=$hash->{displayurl}";

  if($hash->{url} !~ /
      ^(http|https):\/\/                # $1: proto
       (([^:\/]+):([^:\/]+)@)?          # $2: auth, $3:user, $4:password
       ([^:\/]+|\[[0-9a-f:]+\])         # $5: host or IPv6 address
       (:\d+)?                          # $6: port
       (\/.*)$                          # $7: path
    /xi) {
    return "$hash->{displayurl}: malformed or unsupported URL";
  }

  my ($authstring,$user,$pwd,$port,$host);
  ($hash->{protocol},$authstring,$user,$pwd,$host,$port,$hash->{path})
        = (lc($1),$2,$3,$4,$5,$6,$7);
  $hash->{host} = $host;
  
  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($hash->{protocol} eq "https" ? 443: 80);
  }
  $hash->{hu_portSfx} = ($port =~ m/^(80|443)$/ ? "" : ":$port");
  $hash->{hu_port} = $port;
  $hash->{path} = '/' unless defined($hash->{path});
  $hash->{addr} = "$hash->{protocol}://$host:$port";
  
  if($authstring) {
   $hash->{auth} = 1;
   $hash->{user} = urlDecode("$user");
   $hash->{pwd} = urlDecode("$pwd");
  } elsif(defined($hash->{user}) && defined($hash->{pwd})) {
   $hash->{auth} = 1;
  } else  {
   $hash->{auth} = 0;
  }
  

  my $proxy = AttrVal("global", "proxy", undef);
  if($proxy) {
    my $pe = AttrVal("global", "proxyExclude", undef);
    if(!$pe || $host !~ m/$pe/) {
      my @hp = split(":", $proxy);
      $host = $hp[0];
      $port = $hp[1] if($hp[1]);
      $hash->{hu_proxy} = 1;
    }
  }

  if((!defined($hash->{compress}) || $hash->{compress}) &&
      AttrVal("global", "httpcompress", 1)) {
    if(!defined($HU_use_zlib)) {
      $HU_use_zlib = 1;
      eval { require Compress::Zlib; };
      $HU_use_zlib = 0 if($@);
    }
    $hash->{compress} = $HU_use_zlib;
  }


  return HttpUtils_Connect2($hash) if($hash->{conn} && $hash->{keepalive});

  if($hash->{callback}) { # Nonblocking staff
    HttpUtils_gethostbyname($hash, $host, $haveInet6, sub($$$) {
      my ($hash, $err, $iaddr) = @_;
      $hash = $hash->{origHash} if($hash->{origHash});
      if($err) {
        HttpUtils_Close($hash);
        return $hash->{callback}($hash, $err, "") ;
      }
      Log 5, "IP: $host -> ".ip2str($iaddr);
      $hash->{conn} = length($iaddr) == 4 ?
                      IO::Socket::INET ->new(Proto=>'tcp', Blocking=>0) :
                      IO::Socket::INET6->new(Proto=>'tcp', Blocking=>0);
      return $hash->{callback}($hash, "Creating socket: $!", "")
              if(!$hash->{conn});
      my $sa = length($iaddr)==4 ?  sockaddr_in($port, $iaddr) : 
                        Socket6::pack_sockaddr_in6($port, $iaddr);
      my $ret = connect($hash->{conn}, $sa);
      if(!$ret) {
        if($!{EINPROGRESS} || int($!)==10035 ||
           (int($!)==140 && $^O eq "MSWin32")) { # Nonblocking connect

          $hash->{FD} = $hash->{conn}->fileno();
          my %timerHash=(hash=>$hash,sts=>$selectTimestamp,msg=>"connect to");
          $hash->{directWriteFn} = sub() {
            delete($hash->{FD});
            delete($hash->{directWriteFn});
            delete($selectlist{$hash});

            RemoveInternalTimer(\%timerHash);
            my $packed = getsockopt($hash->{conn}, SOL_SOCKET, SO_ERROR);
            my $errno = unpack("I",$packed);
            if($errno) {
              HttpUtils_Close($hash);
              return $hash->{callback}($hash, "$host: ".strerror($errno), "");
            }

            my $err = HttpUtils_Connect2($hash);
            $hash->{callback}($hash, $err, "") if($err);
            return $err;
          };
          $hash->{NAME}="" if(!defined($hash->{NAME}));#Delete might check it
          $selectlist{$hash} = $hash;
          InternalTimer(gettimeofday()+$hash->{timeout},
                        "HttpUtils_Err", \%timerHash);
          return undef;

        } else {
          HttpUtils_Close($hash);
          $hash->{callback}($hash, "connect to $hash->{addr}: $!", "");
          return undef;

        }
      }
    });
    return;

  } else {
    $hash->{conn} = $haveInet6 ?
      IO::Socket::INET6->new(PeerAddr=>"$host:$port",Timeout=>$hash->{timeout}):
      IO::Socket::INET ->new(PeerAddr=>"$host:$port",Timeout=>$hash->{timeout});

    return "$hash->{displayurl}: Can't connect(1) to $hash->{addr}: $@"
      if(!$hash->{conn});
  }

  return HttpUtils_Connect2($hash);
}

sub
HttpUtils_Connect2($)
{
  my ($hash) = @_;
  my $usingSSL;

  $hash->{host} =~ s/:.*//;
  if($hash->{protocol} eq "https" && $hash->{conn} && !$hash->{hu_sslAdded}) {
    eval "use IO::Socket::SSL";
    if($@) {
      my $errstr = "$hash->{addr}: $@";
      Log3 $hash, $hash->{loglevel}, $errstr;
      HttpUtils_Close($hash);
      return $errstr;
    } else {
      $hash->{conn}->blocking(1);
      $usingSSL = 1;

      if($hash->{hu_proxy}) {   # can block!
        my $pw = AttrVal("global", "proxyAuth", "");
        $pw = "Proxy-Authorization: Basic $pw\r\n" if($pw);
        my $hdr = "CONNECT $hash->{host}:$hash->{hu_port} HTTP/1.0\r\n".
                  "User-Agent: fhem\r\n$pw\r\n";
        syswrite $hash->{conn}, $hdr;
        my $buf;
        my $len = sysread($hash->{conn},$buf,65536);
        if(!defined($len) || $len <= 0 || $buf !~ m/HTTP.*200/) {
          HttpUtils_Close($hash);
          return "Proxy denied CONNECT";
        }
      }

      my $sslVersion = AttrVal("global", "sslVersion", "SSLv23:!SSLv3:!SSLv2");
      $sslVersion = AttrVal($hash->{NAME}, "sslVersion", $sslVersion)
        if($hash->{NAME});
      my %par = %{$hash->{sslargs}};
      $par{Timeout}      = $hash->{timeout};
      $par{SSL_version}  = $sslVersion if(!$par{SSL_version});
      $par{SSL_hostname} = $hash->{host} 
        if(IO::Socket::SSL->can('can_client_sni') &&
           IO::Socket::SSL->can_client_sni() &&
           (!$hash->{sslargs} || !defined($hash->{sslargs}{SSL_hostname})));
      $par{SSL_verify_mode} = 0
        if(!$hash->{sslargs} || !defined($hash->{sslargs}{SSL_verify_mode}));

      eval {
        IO::Socket::SSL->start_SSL($hash->{conn}, \%par) || undef $hash->{conn};
      };
      if($@) {
        Log3 $hash, $hash->{loglevel}, $@;
        HttpUtils_Close($hash);
        return $@;
      }
      
      $hash->{hu_sslAdded} = 1 if($hash->{keepalive});
    }
  }

  if(!$hash->{conn}) {
    undef $hash->{conn};
    my $err = $@;
    if($hash->{protocol} eq "https") {
      $err = "" if(!$err);
      $err .= " ".($SSL_ERROR ? $SSL_ERROR : IO::Socket::SSL::errstr());
    }
    return "$hash->{displayurl}: Can't connect(2) to $hash->{addr}: $err"; 
  }

  if($hash->{noConn2}) {
    $hash->{callback}($hash);
    return undef;
  }

  my $data;
  if(defined($hash->{data})) {
    if( ref($hash->{data}) eq 'HASH' ) {
      foreach my $key (keys %{$hash->{data}}) {
        $data .= "&" if( $data );
        $data .= "$key=". urlEncode($hash->{data}{$key});
      }
    } else {
      $data = $hash->{data};
    }
  }

  if(defined($hash->{header})) {
    if( ref($hash->{header}) eq 'HASH' ) {
      $hash->{header} = join("\r\n",
        map(($_.': '.$hash->{header}{$_}), keys %{$hash->{header}}));
    }
  }

  my $method = $hash->{method};
  $method = ($data ? "POST" : "GET") if( !$method );

  my $httpVersion = $hash->{httpversion} ? $hash->{httpversion} : "1.0";

  my $path = $hash->{path};
  $path = "$hash->{protocol}://$hash->{host}$hash->{hu_portSfx}$path"
        if($hash->{hu_proxy});
  my $hdr = "$method $path HTTP/$httpVersion\r\n";
  $hdr .= "Host: $hash->{host}$hash->{hu_portSfx}\r\n";
  $hdr .= "User-Agent: fhem\r\n"
        if(!$hash->{header} || $hash->{header} !~ "User-Agent:");
  $hdr .= "Accept-Encoding: gzip,deflate\r\n" if($hash->{compress});
  $hdr .= "Connection: keep-alive\r\n" if($hash->{keepalive});
  $hdr .= "Connection: Close\r\n"
                              if($httpVersion ne "1.0" && !$hash->{keepalive});

  $hdr .= "Authorization: Basic ".
                      encode_base64($hash->{user}.":".$hash->{pwd}, "")."\r\n"
              if($hash->{auth} && !$hash->{digest} &&
                 !($hash->{header} &&
                   $hash->{header} =~ /^Authorization:\s*Digest/mi));
  $hdr .= $hash->{header}."\r\n" if($hash->{header});
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/x-www-form-urlencoded\r\n"
                if ($hdr !~ "Content-Type:");
  }
  if(!$usingSSL) {
    my $pw = AttrVal("global", "proxyAuth", "");
    $hdr .= "Proxy-Authorization: Basic $pw\r\n" if($pw);
  }
  Log3 $hash, $hash->{loglevel}+1, "HttpUtils request header:\n$hdr";
  $hdr .= "\r\n";

  my $s = $hash->{shutdown};
  $s =(defined($hash->{noshutdown}) && $hash->{noshutdown}==0) if(!defined($s));
  $s = 0 if($hash->{protocol} eq "https");

  if($hash->{callback}) { # Nonblocking read
    $hash->{FD} = $hash->{conn}->fileno();
    $hash->{buf} = "";
    delete($hash->{httpdatalen});
    delete($hash->{httpheader});
    $hash->{NAME} = "" if(!defined($hash->{NAME})); 
    my %timerHash = (hash=>$hash, checkSTS=>$selectTimestamp, msg=>"write to");
    $hash->{directReadFn} = sub() {
      my $buf;
      my $len = sysread($hash->{conn},$buf,65536);
      $hash->{buf} .= $buf if(defined($len) && $len > 0);
      if(!defined($len) || $len <= 0 || 
         HttpUtils_DataComplete($hash)) {
        delete($hash->{FD});
        delete($hash->{directReadFn});
        delete($selectlist{$hash});
        RemoveInternalTimer(\%timerHash);
        my ($err, $ret, $redirect) = HttpUtils_ParseAnswer($hash);
        $hash->{callback}($hash, $err, $ret) if(!$redirect);

      } elsif($hash->{incrementalTimeout}) {    # Forum #85307
        RemoveInternalTimer(\%timerHash);
        InternalTimer(gettimeofday()+$hash->{timeout},
                      "HttpUtils_Err", \%timerHash);
      }
    };

    $data = $hdr.(defined($data) ? $data:"");
    $hash->{directWriteFn} = sub($) { # Nonblocking write
      my $ret = syswrite $hash->{conn}, $data;
      if($ret <= 0) {
        my $err = $!;
        RemoveInternalTimer(\%timerHash);
        HttpUtils_Close($hash);
        return $hash->{callback}($hash, "write error: $err", undef)
      }
      $data = substr($data,$ret);
      if(length($data) == 0) {
        shutdown($hash->{conn}, 1) if($s);
        delete($hash->{directWriteFn});
        RemoveInternalTimer(\%timerHash);
        $timerHash{msg} = "read from";
        InternalTimer(gettimeofday()+$hash->{timeout},
                      "HttpUtils_Err", \%timerHash);
      }
    };
    $selectlist{$hash} = $hash;
    InternalTimer(gettimeofday()+$hash->{timeout}, "HttpUtils_Err",\%timerHash);
    return undef;

  } else {
    syswrite $hash->{conn}, $hdr;
    syswrite $hash->{conn}, $data if(defined($data));
    shutdown($hash->{conn}, 1) if($s);

  }


  return undef;
}

sub
HttpUtils_DataComplete($)
{
  my ($hash) = @_;
  my $hl = $hash->{httpdatalen};
  if(!defined($hl)) {
    return 0 if($hash->{buf} !~ m/^(.*?)\r?\n\r?\n(.*)$/s);
    my ($hdr, $data) = ($1, $2);
    if($hdr =~ m/Transfer-Encoding:\s*chunked/si) {
      $hash->{httpheader} = $hdr;
      $hash->{httpdata} = "";
      $hash->{buf} = $data;
      $hash->{httpdatalen} = -1;

    } elsif($hdr =~ m/Content-Length:\s*(\d+)/si) {
      $hash->{httpdatalen} = $1;
      $hash->{httpheader} = $hdr;
      $hash->{httpdata} = $data;
      $hash->{buf} = "";

    } else {
      $hash->{httpdatalen} = -2;

    }
    $hl = $hash->{httpdatalen};
  }
  return 0 if($hl == -2);

  if($hl == -1) {       # chunked
    while($hash->{buf} =~ m/^[\r\n]*([0-9A-F]+)\r?\n(.*)$/si) {
      my ($l, $r) = (hex($1), $2);
      if($l == 0) {
        $hash->{buf} = "";
        return 1;
      }
      return 0 if(length($r) < $l);
      $hash->{httpdata} .= substr($r, 0, $l);
      $hash->{buf} = substr($r, $l);
    }
    return 0;

  } else {
    $hash->{httpdata} .= $hash->{buf};
    $hash->{buf} = "";
    return 0 if(length($hash->{httpdata}) < $hash->{httpdatalen});
    return 1;
    
  }
}

sub
HttpUtils_DigestHeader($$)
{
  my ($hash, $header) = @_;
  my %digdata;
 
  while($header =~ /(\w+)="?([^"]+?)"?(?:\s*,\s*|$)/gc) {
    $digdata{$1} = $2;
  } 
 
  my ($ha1, $ha2, $response);
  my ($user,$passwd) = ($hash->{user}, $hash->{pwd});

  if(exists($digdata{qop})) {
    $digdata{nc} = "00000001";
    $digdata{cnonce} = md5_hex(rand().time());
  }
  $digdata{uri} = $hash->{path};
  $digdata{username} = $user;

  if(exists($digdata{algorithm}) && $digdata{algorithm} eq "MD5-sess") {
    $ha1 = md5_hex(md5_hex($user.":".$digdata{realm}.":".$passwd).
                  ":".$digdata{nonce}.":".$digdata{cnonce});
  } else {
    $ha1 = md5_hex($user.":".$digdata{realm}.":".$passwd);
  }
 
  # forcing qop=auth as qop=auth-int is not implemented
  $digdata{qop} = "auth" if($digdata{qop});
  my $method = $hash->{method};
  $method = ($hash->{data} ? "POST" : "GET") if( !$method );
  $ha2 = md5_hex($method.":".$hash->{path});

  if(exists($digdata{qop}) && $digdata{qop} =~ /(auth-int|auth)/) {
    $digdata{response} =  md5_hex($ha1.":".
                                  $digdata{nonce}.":".
                                  $digdata{nc}.":".
                                  $digdata{cnonce}.":".
                                  $digdata{qop}.":".
                                  $ha2);
  } else {
    $digdata{response} = md5_hex($ha1.":".$digdata{nonce}.":".$ha2)
  }
 
  return "Authorization: Digest ".
         join(", ", map(($_.'='.($_ ne "nc" ? '"' :'').
                         $digdata{$_}.($_ ne "nc" ? '"' :'')), keys(%digdata)));

}

sub
HttpUtils_ParseAnswer($)
{
  my ($hash) = @_;

  if(!$hash->{keepalive}) {
    $hash->{conn}->close();
    undef $hash->{conn};
  }

  if(!$hash->{buf} && !$hash->{httpheader}) {
    # Server answer: Keep-Alive: timeout=2, max=200
    if($hash->{keepalive} && $hash->{hu_filecount}) {
      my $bc = $hash->{hu_blocking};
      HttpUtils_Close($hash);
      if($bc) {
        return HttpUtils_BlockingGet($hash);
      } else {
        return HttpUtils_NonblockingGet($hash);
      }
    }

    return ("$hash->{displayurl}: empty answer received", "");
  }

  $hash->{hu_filecount} = 0 if(!$hash->{hu_filecount});
  $hash->{hu_filecount}++;

  if(!defined($hash->{httpheader})) {   # response without Content-Length
    if($hash->{buf} =~ m/^(HTTP.*?)\r?\n\r?\n(.*)$/s) {
      $hash->{httpheader} = $1;
      $hash->{httpdata} = $2;
      delete($hash->{buf});
    } else {
      my $ret = $hash->{buf};
      delete($hash->{buf});
      return ("", $ret);
    }
  }
  my $ret = $hash->{httpdata};
  $ret = "" if(!defined($ret));
  delete $hash->{httpdata};
  delete $hash->{httpdatalen};

  my @header= split("\r\n", $hash->{httpheader});
  my @header0= split(" ", shift @header);
  my $code= $header0[1];

  # Close if server doesn't support keepalive
  HttpUtils_Close($hash)
        if($hash->{keepalive} &&
           $hash->{httpheader} =~ m/^Connection:\s*close\s*$/mi);
  
  if(!defined($code) || $code eq "") {
    return ("$hash->{displayurl}: empty answer received", "");
  }
  Log3 $hash,$hash->{loglevel}, "$hash->{displayurl}: HTTP response code $code";
  $hash->{code} = $code;

  # if servers requests digest authentication
  if($code==401 && $hash->{auth} &&
    !($hash->{header} && $hash->{header} =~ /^Authorization:\s*Digest/mi) &&
    $hash->{httpheader} =~ /^WWW-Authenticate:\s*Digest\s*(.+?)\s*$/mi) {
   
    $hash->{header} .= "\r\n".
                      HttpUtils_DigestHeader($hash, $1) if($hash->{header});
    $hash->{header} = HttpUtils_DigestHeader($hash, $1) if(!$hash->{header});
 
    # Request the URL with the Digest response
    if($hash->{callback}) {
      HttpUtils_NonblockingGet($hash);
      return ("", "", 1);
    } else {
      return HttpUtils_BlockingGet($hash);
    }
   
  } elsif($code==401 && $hash->{auth}) {
    return ("$hash->{displayurl}: wrong authentication", "")

  }
  
  if(($code==301 || $code==302 || $code==303) 
	&& !$hash->{ignoreredirects}) { # redirect
    if(++$hash->{redirects} > 5) {
      return ("$hash->{displayurl}: Too many redirects", "");

    } else {
      my $ra;
      map { $ra=$1 if($_ =~ m/Location:\s*(\S+)$/) } @header;
      $ra = "/$ra" if($ra !~ m/^http/ && $ra !~ m/^\//);
      $hash->{url} = ($ra =~ m/^http/) ? $ra: $hash->{addr}.$ra;
      Log3 $hash, $hash->{loglevel}, "HttpUtils $hash->{displayurl}: ".
          "Redirect to ".($hash->{hideurl} ? "<hidden>" : $hash->{url});
      if($hash->{callback}) {
        HttpUtils_NonblockingGet($hash);
        return ("", "", 1);
      } else {
        return HttpUtils_BlockingGet($hash);
      }
    }
  }
  
  if($HU_use_zlib) {
    if($hash->{httpheader} =~ /^Content-Encoding: gzip/mi) {
      eval { $ret =  Compress::Zlib::memGunzip($ret) };
      return ($@, $ret) if($@);
    }
  
    if($hash->{httpheader} =~ /^Content-Encoding: deflate/mi) {
      eval { my $i =  Compress::Zlib::inflateInit();
             my $out = $i->inflate($ret);
             $ret = $out if($out) };
      return ($@, $ret) if($@);
    }
  }

  # Debug
  Log3 $hash, $hash->{loglevel}+1,
    "HttpUtils $hash->{displayurl}: Got data, length: ". length($ret);
  Log3 $hash, $hash->{loglevel}+1,
    "HttpUtils response header:\n$hash->{httpheader}" if($hash->{httpheader});
  return ("", $ret);
}

# Parameters in the hash:
#  mandatory:
#    url, callback
#  optional(default):
#    digest(0),hideurl(0),timeout(4),data(""),loglevel(4),header("" or HASH),
#    noshutdown(1),shutdown(0),httpversion("1.0"),ignoreredirects(0)
#    method($data?"POST":"GET"),keepalive(0),sslargs({}),user(),pwd()
#    compress(1), incrementalTimeout(0)
# Example:
#   { HttpUtils_NonblockingGet({ url=>"http://fhem.de/MAINTAINER.txt",
#     callback=>sub($$$){ Log 1,"ERR:$_[1] DATA:".length($_[2]) } }) }
sub
HttpUtils_NonblockingGet($)
{
  my ($hash) = @_;
  $hash->{hu_blocking} = 0;
  my ($isFile, $fErr, $fContent) = HttpUtils_File($hash);
  return $hash->{callback}($hash, $fErr, $fContent) if($isFile);
  my $err = HttpUtils_Connect($hash);
  $hash->{callback}($hash, $err, "") if($err);
}

#################
# Parameters same as HttpUtils_NonblockingGet up to callback
# Returns (err,data)
sub
HttpUtils_BlockingGet($)
{
  my ($hash) = @_;
  delete $hash->{callback}; # Forum #80712
  $hash->{hu_blocking} = 1;
  my ($isFile, $fErr, $fContent) = HttpUtils_File($hash);
  return ($fErr, $fContent) if($isFile);
  my $err = HttpUtils_Connect($hash);
  return ($err, undef) if($err);
  
  my $buf = "";
  $hash->{conn}->timeout($hash->{timeout});
  $hash->{buf} = "";
  delete($hash->{httpdatalen});
  delete($hash->{httpheader});
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $hash->{conn}->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $hash->{timeout});
    if($nfound <= 0) {
      undef $hash->{conn};
      return ("$hash->{displayurl}: Select timeout/error: $!", undef);
    }

    my $len = sysread($hash->{conn},$buf,65536);
    last if(!defined($len) || $len <= 0);
    $hash->{buf} .= $buf;
    last if(HttpUtils_DataComplete($hash));
  }
  return HttpUtils_ParseAnswer($hash);
}

# Deprecated, use GetFileFromURL/GetFileFromURLQuiet
sub
CustomGetFileFromURL($$@)
{
  my ($hideurl, $url, $timeout, $data, $noshutdown, $loglevel) = @_;
  $loglevel = 4 if(!defined($loglevel));
  my $hash = { hideurl   => $hideurl,
               url       => $url,
               timeout   => $timeout,
               data      => $data,
               noshutdown=> $noshutdown,
               loglevel  => $loglevel,
             };
  my ($err, $ret) = HttpUtils_BlockingGet($hash);
  if($err) {
    Log3 undef, $hash->{loglevel}, "CustomGetFileFromURL $err";
    return undef;
  }
  return $ret;
}


##################
# Parameter: $url, $timeout, $data, $noshutdown, $loglevel
# - if data (which is urlEncoded) is set, then a POST is performed, else a GET.
# - noshutdown must be set e.g. if calling the Fritz!Box Webserver
sub
GetFileFromURL($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(0, $url, @a);
}

##################
# Same as GetFileFromURL, but the url is not displayed in the log.
sub
GetFileFromURLQuiet($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(1, $url, @a);
}

sub
GetHttpFile($$)
{
  my ($host,$file) = @_;
  return GetFileFromURL("http://$host$file");
}

1;
