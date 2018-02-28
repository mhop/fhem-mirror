# $Id$

package main;

use strict;
use warnings;

use Sys::Hostname;
use IO::Socket::INET;
#use Net::Address::IP::Local;

use Encode qw(encode);
use XML::Simple qw(:strict);

use Digest::MD5 qw(md5_hex);

use HttpUtils;

use Time::Local;

use Data::Dumper;

my $fakeRoku_hasMulticast = 1;

sub
fakeRoku_Initialize($)
{
  my ($hash) = @_;

  eval "use IO::Socket::Multicast;";
  $fakeRoku_hasMulticast = 0 if($@);

  $hash->{ReadFn}   = "fakeRoku_Read";

  $hash->{DefFn}    = "fakeRoku_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "fakeRoku_Notify";
  $hash->{UndefFn}  = "fakeRoku_Undefine";
  #$hash->{SetFn}    = "fakeRoku_Set";
  #$hash->{GetFn}    = "fakeRoku_Get";
  $hash->{AttrFn}   = "fakeRoku_Attr";
  $hash->{AttrList} = "disable:1,0 favourites fhemIP httpPort reusePort:1,0 serial";
}

#####################################

sub
fakeRoku_getLocalIP()
{
  my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => '8.8.8.8:53',    # google dns
        #PeerAddr    => '198.41.0.4:53', # a.root-servers.net
    );
  return '<unknown>' if( !$socket );

  my $ip = $socket->sockhost;
  close( $socket );

  return $ip if( $ip );

  #$ip = inet_ntoa( scalar gethostbyname( hostname() || 'localhost' ) );
  #return $ip if( $ip );

  return '<unknown>';
}

sub
fakeRoku_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> fakeRoku" if(@a < 2);

  my $name = $a[0];
  my $id = $a[2];

  $hash->{NAME} = $name;
  $hash->{ID} = $id?$id:'';

  my $defptr = $modules{fakeRoku}{defptr}{$hash->{ID}?$hash->{ID}:'MASTER'};
  return "fakeRoku $hash->{ID} already defined as '$defptr->{NAME}'" if( defined($defptr) && $defptr->{NAME} ne $name);

  $modules{fakeRoku}{defptr}{$hash->{ID}?$hash->{ID}:'MASTER'} = $hash;

  return "install IO::Socket::Multicast to use autodiscovery" if(!$fakeRoku_hasMulticast);
  $hash->{"HAS_IO::Socket::Multicast"} = $fakeRoku_hasMulticast;

  $hash->{helper}{serial} = md5_hex(getUniqueId());
  $hash->{helper}{serial} .= "-$hash->{ID}" if( $hash->{ID} );

  $attr{$name}{serial} = $hash->{helper}{serial} if( !defined($attr{$name}{serial}) );

  $hash->{fhemHostname} = hostname();
  $hash->{fhemIP} = fakeRoku_getLocalIP();

  if( $init_done ) {
    fakeRoku_startDiscovery($hash);
    fakeRoku_startListener($hash);

  } else {
    readingsSingleUpdate($hash, 'state', 'initialized', 1 );

  }

  return undef;
}

sub
fakeRoku_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  fakeRoku_startDiscovery($hash);
  fakeRoku_startListener($hash);

  return undef;
}

sub
fakeRoku_closeSocket($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{CD} ) {
    my $pname = $hash->{PNAME} || $name;

    Log3 $pname, 2, "$name: trying to close a non socket hash";
    return undef;
  }

  RemoveInternalTimer($hash);

  close($hash->{CD});
  delete($hash->{CD});
  delete($selectlist{$name});
  delete($hash->{FD});
}
sub
fakeRoku_newChash($$$)
{
  my ($hash,$socket,$chash) = @_;

  $chash->{TYPE}  = $hash->{TYPE};

  $chash->{NR}    = $devcount++;

  $chash->{phash} = $hash;
  $chash->{PNAME} = $hash->{NAME};

  $chash->{CD}    = $socket;
  $chash->{FD}    = $socket->fileno();

  $chash->{PORT}  = $socket->sockport if( $socket->sockport );

  $chash->{TEMPORARY} = 1;
  $attr{$chash->{NAME}}{room} = 'hidden';

  $defs{$chash->{NAME}}       = $chash;
  $selectlist{$chash->{NAME}} = $chash;
}
sub
fakeRoku_startDiscovery($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( !$fakeRoku_hasMulticast );

  fakeRoku_stopDiscovery($hash);

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  if( 1 ) {
    # respond to multicast client discovery messages
    $hash->{reusePort} = AttrVal($name, 'reusePort', defined(&SO_REUSEPORT)?1:0)?1:0;
    if( my $socket = IO::Socket::Multicast->new(Proto=>'udp', LocalPort=>1900, ReuseAddr=>1, ReusePort=>$hash->{reusePort} ) ) {
      $socket->mcast_add('239.255.255.250');

      my $chash = fakeRoku_newChash( $hash, $socket,
                                 {NAME=>"$name:responder", STATE=>'listening', multicast => 1} );

      $hash->{helper}{responder} = $chash;

      Log3 $name, 3, "$name: ssdp responder started";

    } else {
      Log3 $name, 3, "$name: failed to start ssdp responder: $@";

      InternalTimer(gettimeofday()+10, "fakeRoku_startDiscovery", $hash, 0);
    }

  }

}
sub
fakeRoku_stopDiscovery($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash, "fakeRoku_startDiscovery");

  if( my $chash = $hash->{helper}{responder} ) {
    my $cname = $chash->{NAME};

    fakeRoku_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{responder};

    Log3 $name, 3, "$name: ssdp responder stoped";
  }
}

sub
fakeRoku_startListener($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  fakeRoku_stopListener($hash);

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  my $port = AttrVal($name, 'httpPort', 0);
  if( my $socket = IO::Socket::INET->new(LocalPort=>$port, Listen=>10, Blocking=>0, ReuseAddr=>1) ) {
    readingsSingleUpdate($hash, 'state', 'listening', 1 );


    my $chash = fakeRoku_newChash( $hash, $socket, {NAME=>"$name:listener", STATE=>'accepting'} );

    $chash->{connections} = {};

    $hash->{helper}{listener} = $chash;

    Log3 $name, 3, "$name: listener started";

  } else {
    Log3 $name, 3, "$name: failed to start listener on port $port: $@";
    readingsSingleUpdate($hash, 'state', 'disconnected', 1 );

    InternalTimer(gettimeofday()+10, "fakeRoku_startListener", $hash, 0);
  }
}
sub
fakeRoku_stopListener($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash, "fakeRoku_startListener");

  if( my $chash = $hash->{helper}{listener} ) {
    my $cname = $chash->{NAME};

    foreach my $key ( keys %{$chash->{connections}} ) {
      my $hash = $chash->{connections}{$key};
      my $name = $hash->{NAME};

      fakeRoku_closeSocket($hash);

      delete($defs{$name});
      delete($chash->{connections}{$name});
    }

    fakeRoku_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{listener};

    readingsSingleUpdate($hash, 'state', 'stopped', 1 );
    Log3 $name, 3, "$name: listener stoped";
  }
}

sub
fakeRoku_Undefine($$)
{
  my ($hash, $arg) = @_;

  fakeRoku_stopListener($hash);
  fakeRoku_stopDiscovery($hash);

  delete $modules{fakeRoku}{defptr}{$hash->{ID}?$hash->{ID}:'MASTER'};

  return undef;
}

sub
fakeRoku_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  $hash->{".triggerUsed"} = 1;

  my $list = '';

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
fakeRoku_makeLink($$$$;$)
{
  my ($hash, $cmd, $parentSection, $key, $txt) = @_;

  return $txt if( !$key );

  $txt = $key if( !$txt );
  if( defined($parentSection) && $parentSection eq '' && $key !~ '^/' ) {
    $cmd = "get $hash->{NAME} $cmd /library/sections/$key";
  } elsif( defined($parentSection) && $key !~ '^/' ) {
    $cmd = "get $hash->{NAME} $cmd $parentSection/$key";
  } elsif( $key !~ '^/' ) {
    $cmd = "get $hash->{NAME} $cmd /library/metadata/$key";
  } else {
    $cmd = "get $hash->{NAME} $cmd $key";
  }

  return $txt if( !$FW_ME );

  return "<a style=\"cursor:pointer\" onClick=\"FW_cmd(\\\'$FW_ME$FW_subdir?XHR=1&cmd=$cmd\\\')\">$txt</a>";
}


sub
fakeRoku_Get($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  my $list = '';

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
fakeRoku_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  my $hash = $defs{$name};
  if( $attrName eq 'disable' ) {
    if( $cmd eq "set" && $attrVal ) {
      fakeRoku_stopListener($hash);
      fakeRoku_stopDiscovery($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      fakeRoku_startDiscovery($hash);
      fakeRoku_startListener($hash);
    }

  } elsif( $attrName eq 'fhemIP' ) {
    if( $cmd eq "set" && $attrVal ) {
      $hash->{fhemIP} = $attrVal;
    } else {
      $hash->{fhemIP} = fakeRoku_getLocalIP();
    }

    fakeRoku_startDiscovery($hash);
    fakeRoku_startListener($hash);

  } elsif( $attrName eq 'reusePort' ) {
    if( $cmd eq "set" ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      delete $attr{$name}{$attrName};
    }

    fakeRoku_startDiscovery($hash);
  }


  if( $cmd eq "set" ) {
    if( $attrVal && $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal if( $init_done );
    }
  }

  return;
}


sub
fakeRoku_msg2hash($;$)
{
  my ($string,$keep) = @_;

  my %hash = ();

  if( $string !~ m/\r/ ) {
    $string =~ s/\n/\r\n/g;
  }
  foreach my $line (split("\r\n", $string)) {
    my ($key,$value) = split( ": ", $line );
    next if( !$value );

    if( !$keep ) {
      $key =~ s/-//g;
      $key = uc( $key );
    }

    $value =~ s/^ //;
    $hash{$key} = $value;
  }

  return \%hash;
}
sub
fakeRoku_hash2header($)
{
  my ($hash) = @_;

  return $hash if( ref($hash) ne 'HASH' );

  my $header;
  foreach my $key (keys %{$hash}) {
    #$header .= "\r\n" if( $header );
    $header .= "$key: $hash->{$key}\r\n";
  }

  return $header;
}

sub
fakeRoku_Parse($$;$$$)
{
  my ($hash,$msg,$peerhost,$peerport,$sockport) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: from: $peerhost" if( $peerhost );
  Log3 $name, 5, "$name: $msg";

  my $handled = 0;
  if( $peerhost ) { #from broadcast
    if( $msg =~ '^([\w\-]+) \* HTTP/1.\d' ) {
      my $type = $1;
      my $params = fakeRoku_msg2hash($msg);

      if( $type eq 'M-SEARCH' ) {
        $handled = 1;
        if( $peerhost eq $hash->{fhemIP} ) {
          if( $hash->{helper}{discoverClientsBcast} && $hash->{helper}{discoverClientsBcast}->{CD}->sockport() == $peerport ) {
            #Log3 $name, 5, "$name: ignoring broadcast M-Search from self ($peerhost:$peerport)";
            return undef;
          }
        }

        if( !$params->{MAN} ) {
          Log3 $name, 5, "$name: ignoring broadcast M-Search without MAN";
          return undef;
        } elsif( $params->{MAN} ne '"ssdp:discover"' ) {
          Log3 $name, 5, "$name: ignoring broadcast M-Search with MAN $params->{MAN}";
          return undef;
        }

        Log3 $name, 5, "$name: received from: $peerhost:$peerport to $sockport: $msg";

        my $msg = "HTTP/1.1 200 OK\r\n";
        $msg .= fakeRoku_hash2header( { 'Cache-Control' => 'max-age=300',
                                                     'ST' => 'roku:ecp',
                                               'Location' => "http://$hash->{fhemIP}:$hash->{helper}{listener}{PORT}/",
                                                    'USN' => "uuid:roku:ecp:". AttrVal($name,'serial',$hash->{helper}{serial}), } );
        $msg .= "\r\n";

        my $sin = sockaddr_in($peerport, inet_aton($peerhost));
        $hash->{helper}{responder}->{CD}->send($msg, 0, $sin );

      }
      elsif( $type eq 'NOTIFY' ) {
        $handled = 1;
      }
    }

  } elsif( $msg =~ '^GET\s*([^\s]*)\s*HTTP/1.\d' ) {
    my $request = $1;

    if( $msg =~ m/^(.*?)\r?\n\r?\n(.*)$/s ) {
      my $header = $1;
      my $body = $2;

      my $params;
      if( $request =~ m/^([^?]*)(\?(.*))?/ ) {
        #$request = $1;

        if( $3 ) {
          foreach my $param (split("&", $3)) {
            my ($key,$value) = split("=",$param);
            $params->{$key} = $value;
          }
        }
      }

      $header = fakeRoku_msg2hash($header, 1);

      my $ret;
      if( $request =~ m'^/$' ) {
        $handled = 1;
        #Log3 $name, 4, "$name: request: $msg";
        Log3 $name, 4, "$name: answering $request";

        my $xml = { root => {       xmlns => 'urn:schemas-upnp-org:device-1-0',
                              specVersion => { major => [1], minor => [0] },
                                   device => {       deviceType => ['urn:roku-com:device:player:1-0'],
                                                   friendlyName => ['FHEM'],
                                                   manufacturer => ['FHEM'],
                                                manufacturerURL => ['http://www.fhem.de/'],
                                               modelDescription => ['FHEM fake Roku player'],
                                                      modelName => ['FHEM'],
                                                    modelNumber => ['4200X'],
                                                       modelURL => ['http://www.fhem.de/'],
                                                   serialNumber => [$hash->{serial}],
                                                            UDN => ["uuid:roku:ecp:$hash->{serial}"],
                                                    serviceList => [ { service => [ { serviceType => ['urn:roku-com:service:ecp:1'],
                                                                                        serviceId => ['urn:roku-com:serviceId:ecp1-0'],
                                                                                       controlURL => [''],
                                                                                      eventSubURL => [''],
                                                                                          SCPDURL => ['ecp_SCPD.xml'],
                                                                                } ],
                                                                      }, ],
                                             },
                            }, };

        my $body = '<?xml version="1.0" encoding="utf-8" ?>';
        $body .= XMLout( $xml, KeyAttr => { }, RootName => undef, NoIndent => 1 );
        #$body =~ s/\n/\r\n/g;

        $ret = "HTTP/1.1 200 OK\r\n";
        $ret .= fakeRoku_hash2header( {     'Connection' => 'Close',
                                          'Content-Type' => 'text/xml; charset=utf-8',
                                        'Content-Length' => length($body), } );
        $ret .= "\r\n";
        $ret .= $body;

      } elsif( $request =~ m'^/query/apps' ) {
        $handled = 1;
        #Log3 $name, 4, "$name: request: $msg";
        Log3 $name, 4, "$name: answering $request";

        my $xml = { app => [], };
        if( my $favourites = AttrVal($name, "favourites", undef ) ) {
          my @favourites = split( ',', $favourites );
          for (my $i=0; $i<=$#favourites; $i++) {
            $xml->{app}[$i] = { id => $i+1, content => $favourites[$i], };
          }
        }

        #my $body = '<?xml version="1.0" encoding="utf-8" ?>';
        my $body .= XMLout( $xml, KeyAttr => { }, RootName => 'apps' );
        #$body =~ s/\n/\r\n/g;

        $ret = "HTTP/1.1 200 OK\r\n";
        $ret .= fakeRoku_hash2header( {     'Connection' => 'Close',
                                          'Content-Type' => 'text/xml; charset=utf-8',
                                        'Content-Length' => length($body), } );
        $ret .= "\r\n";
        $ret .= $body;

      }

      if( !$handled ) {
        $peerhost = $peerhost ? " from $peerhost" : '';
        Log3 $name, 2, "$name: unhandled request: $msg";
      }

#Log 1, $ret;
      return $ret;

    }

  } elsif( $msg =~ '^POST\s*([^\s]*)\s*HTTP/1.\d' ) {
    my $request = $1;

    if( $request =~ '^/key(down|up|press)/(.*)' ) {
      $handled = 1;

      my $action = $1;
      my $key = $2;

      if( $key =~ /Lit_(%.*)/ ) {
        $key = urlDecode($1);

      } elsif( $key =~ /Lit_(.*)/ ) {
        $key = $1;

      }

      DoTrigger( $name, "key$action: $key" );

    } elsif( $request =~ '^/launch/(.*)' ) {
      $handled = 1;

      DoTrigger( $name, "launch: $1" );
    }

  }

  if( !$handled ) {
    $peerhost = $peerhost ? " from $peerhost" : '';
    Log3 $name, 2, "$name: unhandled message$peerhost: $msg";
  }

  return undef;
}

sub
fakeRoku_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $len;
  my $buf;

  if( $hash->{multicast} || $hash->{broadcast} ) {
    my $phash = $hash->{phash};

    $len = $hash->{CD}->recv($buf, 1024);
    if( !defined($len) || !$len ) {
Log 1, "!!!!!!!!!!";
      return;
    }

    my $peerhost = $hash->{CD}->peerhost;
    my $peerport = $hash->{CD}->peerport;
    my $sockport = $hash->{CD}->sockport;
    fakeRoku_Parse($phash, $buf, $peerhost, $peerport, $sockport);

  } elsif( $hash->{timeline} ) {
    $len = sysread($hash->{CD}, $buf, 10240);
#Log 1, "1:$len: $buf";
    my $peerhost = $hash->{CD}->peerhost;
    my $peerport = $hash->{CD}->peerport;

    if( !defined($len) || !$len ) {
      fakeRoku_closeSocket( $hash );
      delete($defs{$name});

      return undef;
    }
#Log 1, "timeline ($peerhost:$peerport): $buf";

    return undef;

  } elsif ( $hash->{phash} ) {
    my $phash = $hash->{phash};
    my $pname = $hash->{PNAME};

    if( $phash->{helper}{listener} == $hash ) {
      my @clientinfo = $hash->{CD}->accept();
      if( !@clientinfo ) {
        Log3 $name, 1, "Accept failed ($name: $!)" if($! != EAGAIN);
        return undef;
      }
      $hash->{CONNECTS}++;

      my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
      my $caddr = inet_ntoa($iaddr);

      my $chash = fakeRoku_newChash( $phash, $clientinfo[0], {NAME=>"$name:$port", STATE=>'listening'} );

      $chash->{buf}  = '';

      $hash->{connections}{$chash->{NAME}} = $chash;

      Log3 $name, 5, "$name: timeline sender $caddr connected to $port";

      return;
    }

    $len = sysread($hash->{CD}, $buf, 10240);
#Log 1, "2:$len: $buf";

    do {
      my $close = 1;
      if( $len ) {
        $hash->{buf} .= $buf;

        return if $hash->{buf} !~ m/^(.*?)\r?\n\r?\n(.*)?$/s;
        my $header = $1;
        my $body = $2;

        my $content_length;
        my $length = length($body);

        if( $header =~ m/Content-Length:\s*(\d+)/si ) {
          $content_length = $1;
          return if( $length < $content_length );

          if( $header !~ m/Connection: Close/si ) {
            $close = 0;
            Log3 $pname, 5, "$name: keepalive";
            #syswrite($hash->{CD}, "HTTP/1.1 200 OK\r\nConnection: Keep-Alive\r\nContent-Length: 0\r\n\r\n" );

            if( $length > $content_length ) {
              $buf = substr( $body, $content_length );
              $hash->{buf} = "$header\r\n\r\n". substr( $body, 0, $content_length );
            } else {
              $buf ='';
            }

          } else {
            Log3 $pname, 5, "$name: close";
            #syswrite($hash->{CD}, "HTTP/1.1 200 OK\r\nConnection: Close\r\n\r\n" );

          }

        } elsif( $length == 0 && $header =~ m/^GET/ ) {
          $buf = '';

        } else {

          return;
        }

      }

      Log3 $pname, 4, "$name: disconnected" if( !$len );

      my $ret;
      $ret = fakeRoku_Parse($phash, $hash->{buf}) if( $hash->{buf} );

      if( $len ) {
        my $add_header;
        if( !$ret || $ret !~ m/^HTTP/si ) {
          $add_header .= "HTTP/1.1 200 OK\r\n";
        }
        if( !$ret || $ret !~ m/Connection:/si ) {
          if( $close ) {
            $add_header .= "Connection: Close\r\n";
          } else {
            $add_header .= "Connection: Keep-Alive\r\n";
          }
        }
        if( !$ret ) {
          $add_header .= "Content-Length: 0\r\n";
        }

        syswrite($hash->{CD}, $add_header) if( $add_header );
        Log3 $pname, 5, "$name: add header: $add_header" if( $add_header );

        if( $ret ) {
          syswrite($hash->{CD}, $ret);

          if( $ret !~ m/Connection: Close/si ) {
            $close = 0;
            Log3 $pname, 5, "$name: keepalive";
          }

        } else {
          syswrite($hash->{CD}, "\r\n" );

        }
      }

      $hash->{buf} = $buf;
      $buf = '';

      if( $close || !$len ) {
        fakeRoku_closeSocket( $hash );

        delete($defs{$name});
        delete($hash->{phash}{helper}{listener}{connections}{$hash->{NAME}});

        return;
      }

    } while( $hash->{buf} );

  }

  return undef;
}

1;

=pod
=item summary    roku remote control protocol server
=item summary_DE Roku Remote Control Protokoll Server
=begin html

<a name="fakeRoku"></a>
<h3>fakeRoku</h3>
<ul>
  This module allows you to add a 'fake' roku player device to a harmony hub based remote and to receive and
  process configured key presses in FHEM.
  <br><br>
  Notes:
  <ul>
    <li>XML::Simple is needed.</li>
    <li>IO::Socket::Multicast is needed.</li>
    <li>The following 12 functions are available and can be used:
      <ul>
        <li>InstantReplay</li>
        <li>Home</li>
        <li>Info</li>
        <li>Search</li>
        <li>Back</li>
        <li>FastForward = Fwd</li>
        <li>Rewind = Rev</li>
        <li>Select</li>
        <li>DirectionUp</li>
        <li>DirectionRight</li>
        <li>DirectionLeft</li>
        <li>DirectionDown</li>
      </ul></li>
  </ul>

  <br><br>


  <a name="fakeRoku_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; fakeRoku</code>
    <br><br>
  </ul>

  <a name="fakeRoku_Set"></a>
  <b>Set</b>
  <ul>none
  </ul><br>

  <a name="fakeRoku_Get"></a>
  <b>Get</b>
  <ul>none
  </ul><br>

  <a name="fakeRoku_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>favourites<br>
      comma separated list of names to use as apps/channels/favourites. the list can be reloaded on the harmony with edit->reset.</li>
    <li>fhemIP<br>
      overwrites autodetected local ip used in advertising</li>
    <li>httpPort</li>
    <li>reusePort<br>
      not set -> set ReusePort on multicast socket if SO_REUSEPORT flag ist known. should work in most cases.<br>
      0 -> don't set ReusePort on multicast socket<br>
      1 -> set ReusePort on multicast socket</li>
    <li>serial</li>
  </ul>

</ul><br>

=end html
=cut
