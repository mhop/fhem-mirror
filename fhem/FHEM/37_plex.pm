
# $Id$

#http://10.0.1.21:32400/music/:/transcode/generic.mp3?offset=0&format=mp3&audioCodec=libmp3lame&audioBitrate=320&audioSamples=44100&url=http%3A%2F%2F127.0.0.1%3A32400%2Flibrary%2Fparts%2F71116%2Ffile.mp3


package main;

use strict;
use warnings;

use Sys::Hostname;
use IO::Socket::INET;
#use Net::Address::IP::Local;

#use MIME::Base64;

use JSON;
use Encode qw(encode);
use XML::Simple qw(:strict);

use Digest::MD5 qw(md5_hex);
#use Socket;
use Time::HiRes qw(usleep nanosleep);

use HttpUtils;

use Time::Local;

use Data::Dumper;

my $plex_hasMulticast = 1;

sub
plex_Initialize($)
{
  my ($hash) = @_;

  eval "use IO::Socket::Multicast;";
  $plex_hasMulticast = 0 if($@);

  $hash->{ReadFn}   = "plex_Read";

  $hash->{DefFn}    = "plex_Define";
  $hash->{NotifyFn} = "plex_Notify";
  $hash->{UndefFn}  = "plex_Undefine";
  $hash->{SetFn}    = "plex_Set";
  $hash->{GetFn}    = "plex_Get";
  $hash->{AttrFn}   = "plex_Attr";
  $hash->{AttrList} = "disable:1,0"
                      . " fhemIP httpPort ignoredClients ignoredServers"
                      . " removeUnusedReadings:1,0 responder:1,0"
                      . " user password "
                      . $readingFnAttributes;
}

#####################################

sub
plex_getLocalIP()
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
plex_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> plex [server]" if(@a < 2);

  my $name = $a[0];

  my ($ip,$port);
     ($ip,$port) = split( ':', $a[2] ) if( $a[2] );
  my $server = $ip;
  my $client = $ip;

  $server = '' if( $server && $server !~ m/^\d+\.\d+\.\d+\.\d+$/ );

  $hash->{NAME} = $name;

  if( $server ) {
    $hash->{server} = $server;
    $hash->{port} = $port?$port:32400;

    $modules{plex}{defptr}{$server} = $hash;

  } elsif( $client ) {
    if( $port ) {
      $hash->{client} = $client;
      $hash->{port} = $port;

      $modules{plex}{defptr}{$client} = $hash;
    } else {
      $hash->{machineIdentifier} = $client;

      $modules{plex}{defptr}{$client} = $hash;
    }

  } else {
    my $defptr = $modules{plex}{defptr}{MASTER};
    return "plex master already defined as '$defptr->{NAME}'" if( defined($defptr) && $defptr->{NAME} ne $name);

    $modules{plex}{defptr}{MASTER} = $hash;

    return "give ip or install IO::Socket::Multicast to use server and client autodiscovery" if(!$plex_hasMulticast && !$server);
    $hash->{"HAS_IO::Socket::Multicast"} = $plex_hasMulticast;

  }

  $hash->{id} = md5_hex(getUniqueId());

  $hash->{fhemHostname} = hostname();
  $hash->{fhemIP} = plex_getLocalIP();

  $hash->{NOTIFYDEV} = "global";

  if( $init_done ) {
    plex_getToken($hash);
    plex_startDiscovery($hash);
    plex_startTimelineListener($hash);

    plex_sendApiCmd( $hash, "http://$hash->{server}:$hash->{port}/servers", "servers" ) if( $hash->{server} );

  } else {
    readingsSingleUpdate($hash, 'state', 'initialized', 1 );

  }

  return undef;
}

sub
plex_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if( my $token = ReadingsVal($name, '.token', undef) ) {
    Log3 $name, 3, "$name: restoring token from reading";

    $hash->{token} = $token;

    plex_sendApiCmd($hash, "https://plex.tv/pms/servers.xml", "myPlex:servers" );
    plex_sendApiCmd($hash, "https://plex.tv/devices.xml", "myPlex:devices" );
  }
  plex_getToken($hash);
  plex_startDiscovery($hash);
  plex_startTimelineListener($hash);

  plex_sendApiCmd( $hash, "http://$hash->{server}:$hash->{port}/servers", "servers" ) if( $hash->{server} );

  return undef;
}

sub
plex_sendDiscover($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $pname = $hash->{PNAME} || $name;

  if( $hash->{multicast} ) {
    Log3 $pname, 5, "$name: sending multicast discovery message to $hash->{PORT}";
    $hash->{CD}->mcast_send('M-SEARCH * HTTP/1.1', '239.0.0.250:'.$hash->{PORT});

  } elsif( $hash->{broadcast} ) {
    Log3 $pname, 5, "$name: sending broadcast discovery message to $hash->{PORT}";
    my $sin = sockaddr_in($hash->{PORT}, inet_aton('255.255.255.255'));
    $hash->{CD}->send('M-SEARCH * HTTP/1.1', 0, $sin );

  } else {
    Log3 $pname, 2, "$name: can't send unknown discovery message type to $hash->{PORT}";

  }

  RemoveInternalTimer($hash, "plex_sendDiscover");

  if( $hash->{interval} ) {
    InternalTimer(gettimeofday()+$hash->{interval}, "plex_sendDiscover", $hash, 0);
  }
}
sub
plex_closeSocket($)
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
plex_newChash($$$)
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
plex_startDiscovery($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( $hash->{server} );
  return undef if( $hash->{client} );
  return undef if( $hash->{machineIdentifier} );
  return undef if( !$plex_hasMulticast );

  plex_stopDiscovery($hash);

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  # udp multicast for servers
  if( my $socket = IO::Socket::Multicast->new(Proto => 'udp', Timeout => 5, ReuseAddr=>1, ReusePort=>defined(&SO_REUSEPORT)?1:0) ) {
    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:serverDiscoveryMcast", STATE=>'discovering', multicast => 1} );

    $hash->{helper}{discoverServersMcast} = $chash;

    $chash->{PORT} = 32414;
    $chash->{interval} = 10;
    #plex_sendDiscover($chash);
    InternalTimer(gettimeofday()+$chash->{interval}/2, "plex_sendDiscover", $chash, 0);

    Log3 $name, 3, "$name: multicast server discovery started";

  } else {
    Log3 $name, 3, "$name: failed to start multicast server discovery: $@";

    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
  }

  # udp broadcast for servers
  if( my $socket = new IO::Socket::INET ( Proto => 'udp', Broadcast => 1, ) ) {

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:serverDiscoveryBcast", STATE=>'discovering', broadcast => 1} );

    $hash->{helper}{discoverServersBcast} = $chash;

    $chash->{PORT} = 32414;
    $chash->{interval} = 10;
    plex_sendDiscover($chash);

    Log3 $name, 3, "$name: broadcast server discovery started";

  } else {
    Log3 $name, 3, "$name: failed to start broadcast server discovery: $@";

    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
  }

  # udp multicast for clients
  if( my $socket = IO::Socket::Multicast->new(Proto=>'udp', ReuseAddr=>1, ReusePort=>defined(&SO_REUSEPORT)?1:0) ) {
    $socket->mcast_add('239.0.0.250');

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:clientDiscoveryMcast", STATE=>'discovering', multicast => 1} );

    $hash->{helper}{discoverClientsMcast} = $chash;

    $chash->{PORT} = 32412;
    $chash->{interval} = 10;
    #plex_sendDiscover($chash);
    InternalTimer(gettimeofday()+$chash->{interval}/2, "plex_sendDiscover", $chash, 0);

    Log3 $name, 3, "$name: multicast client discovery started";

  } else {
    Log3 $name, 3, "$name: failed to start multicast client discovery: $@";

    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
  }

  # udp broadcast for clients
  if( my $socket = new IO::Socket::INET ( Proto => 'udp', Broadcast => 1, ) ) {

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:clientDiscoveryBcast", STATE=>'discovering', broadcast => 1} );

    $hash->{helper}{discoverClientsBcast} = $chash;

    $chash->{PORT} = 32412;
    $chash->{interval} = 10;
    plex_sendDiscover($chash);

    Log3 $name, 3, "$name: broadcast client discovery started";

  } else {
    Log3 $name, 3, "$name: failed to start broadcast client discovery: $@";

    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
  }

  # listen for udp mulicast HELLO and BYE messages from PHT
  if( my $socket = IO::Socket::Multicast->new(Proto=>'udp', LocalPort=>32413, ReuseAddr=>1, ReusePort=>defined(&SO_REUSEPORT)?1:0) ) {
    $socket->mcast_add('239.0.0.250');

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:clientDiscoveryPHT", STATE=>'listening', multicast => 1} );

    $hash->{helper}{discoverClientsListen} = $chash;

    Log3 $name, 3, "$name: pht client discovery started";

  } else {
    Log3 $name, 3, "$name: failed to pht start client listener";

    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
  }

  # listen for udp multicast server UPDATE messages (playerAdd, playerDel)
#  if( my $socket = IO::Socket::Multicast->new(Proto=>'udp', LocalPort=>32415, ReuseAddr=>1, ReusePort=>defined(&SO_REUSEPORT)?1:0) ) {
#    $socket->mcast_add('239.0.0.250');
#
#    my $chash = plex_newChash( $hash, $socket,
#                               {NAME=>"$name:clientDiscovery4", STATE=>'discovering', multicast => 1} );
#
#    $hash->{helper}{discoverClients4} = $chash;
#
#    Log3 $name, 3, "$name: client discovery4 started";
#
#  } else {
#    Log3 $name, 3, "$name: failed to start client discovery4: $@";
#
#    InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
#  }

  if( AttrVal($name, 'responder', undef) ) {
    # respond to multicast client discovery messages
    if( my $socket = IO::Socket::Multicast->new(Proto=>'udp', LocalPort=>32412, ReuseAddr=>1, ReusePort=>defined(&SO_REUSEPORT)?1:0) ) {
      $socket->mcast_add('239.0.0.250');

      my $chash = plex_newChash( $hash, $socket,
                                 {NAME=>"$name:clientDiscoveryResponderMcast", STATE=>'listening', multicast => 1} );

      $hash->{helper}{clientDiscoveryResponderMcast} = $chash;

      Log3 $name, 3, "$name: multicast client discovery responder started";

    } else {
      Log3 $name, 3, "$name: failed to start multicast client discovery responder: $@";

      InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
    }

    # respond to broadcast client discovery messages
    #if( my $socket = new IO::Socket::INET ( Proto => 'udp', Broadcast => 1, LocalAddr => '0.0.0.0', LocalPort => 32412, ReuseAddr=>1) ) {

    #  my $chash = plex_newChash( $hash, $socket,
    #                             {NAME=>"$name:clientDiscoveryResponderBcast", STATE=>'listening', broadcast => 1} );

    #  $hash->{helper}{clientDiscoveryResponderBcast} = $chash;

    #  Log3 $name, 3, "$name: broadcast client discovery responder started";

    #} else {
    #  Log3 $name, 3, "$name: failed to start broadcast client discovery responder: $@";

    #  InternalTimer(gettimeofday()+10, "plex_startDiscovery", $hash, 0);
    #}
  }

  readingsSingleUpdate($hash, 'state', 'running', 1 );
}
sub
plex_stopDiscovery($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash, "plex_startDiscovery");

  if( my $chash = $hash->{helper}{discoverServersMcast} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverServersMcast};

    Log3 $name, 3, "$name: multicast server discovery stoped";
  }

  if( my $chash = $hash->{helper}{discoverServersBcast} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverServersBcast};

    Log3 $name, 3, "$name: broadcast server discovery stoped";
  }

  if( my $chash = $hash->{helper}{discoverClientsMcast} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverClientsMcast};

    Log3 $name, 3, "$name: multicast client discovery stoped";
  }

  if( my $chash = $hash->{helper}{discoverClientsBcast} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverClientsBcast};

    Log3 $name, 3, "$name: broadcast client discovery stoped";
  }

  if( my $chash = $hash->{helper}{discoverClientsListen} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverClientsListen};

    Log3 $name, 3, "$name: pht client listener stoped";
  }

  if( my $chash = $hash->{helper}{discoverClients4} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{discoverClients4};

    Log3 $name, 3, "$name: client discovery4 stoped";
  }

  if( my $chash = $hash->{helper}{clientDiscoveryResponderMcast} ) {
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{clientDiscoveryResponderMcast};

    Log3 $name, 3, "$name: multicast client discovery responder stoped";
  }
}

sub
plex_sendSubscription($$)
{
  my ($hash,$ip) = @_;
  return undef if( !$hash );
  my $name = $hash->{NAME};

  my $phash = $hash->{phash};
  return undef if( !$phash );
  my $entry = $phash->{clients}{$ip};
  return undef if( !$entry );

  my $pname = $hash->{PNAME};
  if( !$hash->{subscriptionsTo}{$ip} ) {
    $hash->{subscriptionsTo}{$ip} = $ip;
    Log3 $pname, 4, "$name: adding timeline subscription for $ip";

  } else {
    Log3 $pname, 5, "$name: sending subscribe message to $ip:$entry->{port}";

  }

  plex_sendApiCmd( $phash, "http://$ip:$entry->{port}/player/timeline/subscribe?protocol=http&port=$hash->{PORT}", "subscribe" );
}
sub
plex_removeSubscription($$)
{
  my ($hash,$ip) = @_;
  return undef if( !$hash );
  my $name = $hash->{NAME};

  return undef if( !$hash->{subscriptionsTo}{$ip} );

  my $phash = $hash->{phash};
  return undef if( !$phash );
  my $entry = $phash->{clients}{$ip};
  return undef if( !$entry );

  my $pname = $hash->{PNAME};
  Log3 $pname, 4, "$name: removing timeline subscription for $ip";

  plex_sendApiCmd( $phash, "http://$ip:$entry->{port}/player/timeline/unsubscribe?", "unsubscribe" ) if( $entry->{online} );

  delete $hash->{subscriptionsTo}{$ip};

  if( !%{$hash->{subscriptionsTo}} ) {
    $phash->{commandID} = 0;
  }

  if( my $chash = $hash->{helper}{timelineListener} ) {
    foreach my $key ( keys %{$chash->{connections}} ) {
      my $hash = $chash->{connections}{$key};
      my $name = $hash->{NAME};

      next if( !$hash->{machineIdentifier} );
      next if( $hash->{machineIdentifier} ne $entry->{machineIdentifier} );

      plex_closeSocket($hash);

      delete($defs{$name});
      delete($chash->{connections}{$name});
    }

  }
}
sub
plex_refreshSubscriptions($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $pname = $hash->{PNAME};

  Log3 $pname, 4, "$name: refreshing timeline subscriptions" if( %{$hash->{subscriptionsTo}} );

  foreach my $ip ( keys %{$hash->{subscriptionsTo}} ) {
    plex_sendSubscription($hash, $ip);
  }

  RemoveInternalTimer($hash,"plex_refreshSubscriptions");
  if( $hash->{interval} ) {
    InternalTimer(gettimeofday()+$hash->{interval}, "plex_refreshSubscriptions", $hash, 0);
  }
}
my $lastCommandID;
sub
plex_sendTimelines($$)
{
  my ($hash,$commandID) = @_;
  if( ref($hash) ne 'HASH' ) {
    my ($name) = split( ':', $hash, 2 );
    $hash = $defs{$name};
  }
  my $name = $hash->{NAME};

  $commandID = $lastCommandID if( !$commandID );
  $lastCommandID = $commandID;

  return undef if( !$hash->{subscriptionsFrom} );

  foreach my $key ( keys %{$hash->{subscriptionsFrom}} ) {
    my $addr = $hash->{subscriptionsFrom}{$key};

    my $chash;
    if( $hash->{helper}{subscriptionsFrom}{$key} ) {
      $chash = $hash->{helper}{subscriptionsFrom}{$key};

    } elsif( my $socket = IO::Socket::INET->new(PeerAddr=>$addr, Timeout=>2, Blocking=>1, ReuseAddr=>1) ) {

      $chash = plex_newChash( $hash, $socket,
                              {NAME=>"$name:timelineSubscription:$addr", STATE=>'opened', timeline=>1} );

      Log3 $name, 3, "$name: timeline subscription opened";

      $hash->{helper}{subscriptionsFrom}{$key} = $chash;

      $chash->{machineIdentifier} = $key;
      $chash->{commandID} = $commandID;

    }

    plex_sendTimeline($chash);
  }

  $hash->{interval} = 60;
  $hash->{interval} = 2 if( $hash->{sonos}{status} && $hash->{sonos}{status} eq 'playing' );

  RemoveInternalTimer("$name:sendTimelines");
  if( $hash->{interval} ) {
    InternalTimer(gettimeofday()+$hash->{interval}, 'plex_sendTimelines', "$name:sendTimelines", 0);
  }
}
sub
plex_sendTimeline($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $phash = $hash->{phash};
  my $pname = $hash->{PNAME};

  return undef if( !$hash->{CD} );

  Log3 $pname, 4, "$name: refreshing timeline status";


  my $xml = { MediaContainer => { size => 1,
                                  machineIdentifier => $phash->{id},
                                  Timeline => {        state => $phash->{sonos}{status},
                                                        type => 'music',
                                                      volume => 100, },
                                }, };

  $xml->{MediaContainer}{commandID} = $hash->{commandID} if( defined($hash->{commandID}) );

  if( !$phash->{sonos} || !$phash->{sonos}{playqueue}{size} || $phash->{sonos}{playqueue}{size} < 2 ) {
    $xml->{MediaContainer}{Timeline}{controllable} = 'volume,stop,playPause';
  } else {
    $xml->{MediaContainer}{Timeline}{controllable} = 'volume,stop,playPause,skipNext,skipPrevious';
  }

  if( !$phash->{sonos} || $phash->{sonos}{status} eq 'stopped' ) {
    $xml->{MediaContainer}{Timeline}{location} = 'navigation';

  } else {
    $xml->{MediaContainer}{Timeline}{location} = 'fullScreenMusic';

    $xml->{MediaContainer}{Timeline}{mediaIndex} = $phash->{sonos}{currentTrack}+1;
    $xml->{MediaContainer}{Timeline}{playQueueID} = $phash->{sonos}{playqueue}{playQueueID} if( $phash->{sonos}{playqueue}{playQueueID} );
    $xml->{MediaContainer}{Timeline}{containerKey} = $phash->{sonos}{containerKey} if( $phash->{sonos}{containerKey} );
    $xml->{MediaContainer}{Timeline}{machineIdentifier} = $phash->{sonos}{machineIdentifier};

    my $tracks = $phash->{sonos}{playqueue}{Track};
    my $track = $tracks->[$phash->{sonos}{currentTrack}];
    $xml->{MediaContainer}{Timeline}{duration} = $track->{duration};
    $xml->{MediaContainer}{Timeline}{seekRange} = "0-$track->{duration}";
    $xml->{MediaContainer}{Timeline}{key} = $track->{key};
    $xml->{MediaContainer}{Timeline}{ratingKey} = $track->{ratingKey};
    $xml->{MediaContainer}{Timeline}{playQueueItemID} = $track->{playQueueItemID};

    if( $phash->{sonos}{status} eq 'playing' ) {
      $phash->{sonos}{currentTime} += time() - $phash->{sonos}{updateTime};

      if( $phash->{sonos}{currentTime} >= $track->{duration}/1000 ) {
        if( !$phash->{sonos}{playqueue}{size} || $phash->{sonos}{playqueue}{size} < 2 ) {
          fhem( "set $phash->{id} stop" );
        } else {
          fhem( "set $phash->{id} skipNext" );
        }
        return undef;
      }

    }
    $phash->{sonos}{updateTime} = time();

    $xml->{MediaContainer}{Timeline}{time} = $phash->{sonos}{currentTime}*1000;
  }

  my $body = '<?xml version="1.0" encoding="utf-8" ?>';
  $body .= "\n";
  $body .= XMLout( $xml, KeyAttr => { }, RootName => undef );
  $body =~ s/^  //gm;
#Log 1, $body;

  my $ret = "POST /:/timeline HTTP/1.1\r\n";
  $ret .= plex_hash2header( {                       'Host' => $hash->{CD}->peerhost .':'. $hash->{CD}->peerport,
                                                    #'Host' => '10.0.1.45:32500',
                                                    #'Host' => '10.0.1.17:32400',
                                                  'Accept' => '*/*',
                              'X-Plex-Client-Capabilities' => 'audioDecoders=mp3',
                                'X-Plex-Client-Identifier' => $phash->{id},
                                      'X-Plex-Device-Name' => $phash->{fhemHostname},
                                         'X-Plex-Platform' => $^O,
                                          'X-Plex-Version' => '0.0.0',
                                         'X-Plex-Provides' => 'player',
                                          'Content-Length' => length($body),
                                           #'Content-Range' => 'bytes 0-/-1',
                                              #'Connection' => 'Close',
                                              'Connection' => 'Keep-Alive',
                                           #'Content-Type' => 'text/xml;charset=utf-8',
                                            'Content-Type' => 'application/x-www-form-urlencoded',
                                   #'X-Plex-Http-Pipeline' => 'infinite',
                            } );

  $ret .= "\r\n";
  $ret .= $body;
#Log 1, $ret;

  syswrite($hash->{CD}, $ret );
}
sub
plex_startTimelineListener($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( $hash->{server} && $modules{plex}{defptr}{MASTER} );
  return undef if( $hash->{client} && $modules{plex}{defptr}{MASTER} );
  return undef if( $hash->{machineIdentifier} );

  plex_stopTimelineListener($hash);

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  my $port = AttrVal($name, 'httpPort', 0);
  if( my $socket = IO::Socket::INET->new(LocalPort=>$port, Listen=>10, Blocking=>0, ReuseAddr=>1) ) {

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:timelineListener", STATE=>'accepting'} );

    $chash->{connections} = {};
    $chash->{subscriptionsTo} = {};

    $hash->{helper}{timelineListener} = $chash;

    Log3 $name, 3, "$name: timeline listener started";

    $chash->{interval} = 30;
    plex_refreshSubscriptions($chash);

  } else {
    Log3 $name, 3, "$name: failed to start timeline listener on port $port $@";

    InternalTimer(gettimeofday()+10, "plex_startTimelineListener", $hash, 0);
  }
}
sub
plex_stopTimelineListener($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash, "plex_startTimelineListener");

  if( my $chash = $hash->{helper}{timelineListener} ) {
    my $cname = $chash->{NAME};

    foreach my $key ( keys %{$chash->{connections}} ) {
      my $hash = $chash->{connections}{$key};
      my $name = $hash->{NAME};

      plex_closeSocket($hash);

      delete($defs{$name});
      delete($chash->{connections}{$name});
    }

    plex_closeSocket($chash);

    delete($defs{$cname});
    delete $hash->{helper}{timelineListener};

    Log3 $name, 3, "$name: timeline listener stoped";
  }
}

sub
plex_Undefine($$)
{
  my ($hash, $arg) = @_;

  plex_stopTimelineListener($hash);
  plex_stopWebsockets($hash);
  plex_stopDiscovery($hash);

  delete $modules{plex}{defptr}{MASTER} if( $modules{plex}{defptr}{MASTER} == $hash ) ;

  delete $modules{plex}{defptr}{$hash->{server}} if( $hash->{server} );
  delete $modules{plex}{defptr}{$hash->{client}} if( $hash->{client} );
  delete $modules{plex}{defptr}{$hash->{machineIdentifier}} if( $hash->{machineIdentifier} );

  return undef;
}

sub
plex_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  $hash->{".triggerUsed"} = 1;

  my $list = '';

  if( $hash->{'myPlex-servers'} ) {
    if( $cmd eq 'autocreate' ) {
      return "usage: autocreate <server>" if( !$params[0] );

      if( $hash->{'myPlex-servers'}{Server} ) {
        foreach my $entry (@{$hash->{'myPlex-servers'}{Server}}) {
          if( $entry->{localAddresses} eq $params[0] || $entry->{machineIdentifier} eq $params[0] ) {
            #Log 1, Dumper $entry;

            my $define = "$entry->{machineIdentifier} plex $entry->{address}";

            if( my $cmdret = CommandDefine(undef,$define) ) {
              return $cmdret;
            }

            my $chash = $defs{$entry->{machineIdentifier}};
            $chash->{token} = $entry->{accessToken};

            fhem( "setreading $entry->{machineIdentifier} .token $entry->{accessToken}" );

            return undef;
          }

        }
      }

      return "unknown server: $params[0]";
    }

    $list .= 'autocreate ';
  }

  if( my $entry = plex_serverOf($hash, $cmd, !$hash->{machineIdentifier}) ) {
    my @params = @params;
    $cmd = shift @params if( $cmd eq $entry->{address} );
    $cmd = shift @params if( $cmd eq $entry->{machineIdentifier} );

    my $ip = $entry->{address};

    if( $cmd eq 'refreshToken' ) {
      delete $hash->{token};
      plex_getToken($hash);

      return undef;
    }

    return "server $ip not online" if( $cmd ne '?' && !$entry->{online} );

    if( $cmd eq 'playlistCreate' ) {
      return "usage: playlistCreate <name>" if( !$params[0] );

      return undef;

    } elsif( $cmd eq 'playlistAdd' ) {
      my $server = plex_serverOf($hash, $params[0], 1);
      return "unknown server" if( !$server );

      shift @params if( $params[0] eq $server->{address} );

      my $playlist = shift(@params);
      return "usage: [<server>] playlistAdd <key> <keys>" if( !$params[0] );

      foreach my $key ( @params ) {
        plex_addToPlaylist($hash, $server, $playlist, $key);
      }

      return undef;

    } elsif( $cmd eq 'playlistRemove' ) {
      #my $server = plex_serverOf($hash, $params[0], 1);
      #return "unknown server" if( !$server );

      #shift @params if( $params[0] eq $server->{address} );

      #my $playlist = shift(@params);
      #return "usage: [<server>] playlistRemove <key> <keys>" if( !$params[0] );

      #foreach my $key ( @params ) {
      #  plex_removeFromPlaylist($hash, $server, $playlist, $key);
      #}


    } elsif( $cmd eq 'unwatched' || $cmd eq 'watched' ) {
      return "usage: unwatched <keys>" if( !@params );

      $cmd = $cmd eq 'watched' ? 'scrobble' : 'unscrobble';
      foreach my $key ( @params ) {
        $key =~ s'^/library/metadata/'';
        plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/:/$cmd?key=$key&identifier=com.plexapp.plugins.library", $cmd );
      }

      return undef;

    } elsif( $cmd eq 'smapiRegister' ) {
      return "first use the httpPort attribute to configure a fixed http port" if( !AttrVal($name, 'httpPort', 0) );
      return plex_publishToSonos($name, 'PLEX', $params[0]);

    }

    $list .= 'playlistCreate playlistAdd playlistRemove ';
    $list .= 'smapiRegister ' if( $hash->{helper}{timelineListener} );
    $list .= 'unwatched watched ';
  }

  if( my $entry = plex_clientOf($hash, $cmd) ) {
    my @params = @params;
    $cmd = shift @params if( $cmd eq $entry->{address} );

    my $ip = $entry->{address};

    return "client $ip not online" if( $cmd ne '?' && !$entry->{online} );

    if( ($cmd eq 'playMedia' || $cmd eq 'resume' ) && $params[0] ) {
      my $server = plex_serverOf($hash, $params[0], 1);
      return "unknown server" if( !$server );

      shift @params if( $params[0] eq $server->{address} );

      my $offset = '';
      if( $cmd eq 'resume' ) {
        my $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}$params[0]", '#raw', 1 );
        if( $xml && $xml->{Video} ) {
          $offset = "&offset=$xml->{Video}[0]{viewOffset}" if( $xml->{Video}[0]{viewOffset} );
        }
      }

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/playback/playMedia?key=$params[0]&machineIdentifier=$server->{machineIdentifier}&address=$server->{address}&port=$server->{port}$offset", "playback" );

      return undef;

    } elsif( $cmd eq 'mirror' ) {
      return "mirror not supported" if( $hash->{protocolCapabilities} && $hash->{protocolCapabilities} !~ m/\bmirror\b/ );
      return "usage: mirror <key>" if( !$params[0] );

      my $server = plex_serverOf($hash, $params[0], 1);
      return "unknown server" if( !$server );

      shift @params if( $params[0] eq $server->{address} );

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/mirror/details?key=$params[0]&machineIdentifier=$server->{machineIdentifier}&address=$server->{address}&port=$server->{port}", "mirror" );

      return undef;

    } elsif( lc($cmd) eq 'play' && $params[0] ) {
      return "usage: play <key>" if( !$params[0] );

      my $server = plex_serverOf($hash, $params[0], 1);
      return "unknown server" if( !$server );

      shift @params if( $params[0] eq $server->{address} );

      return plex_play($hash, $entry, $server, $params[0] );

      return undef;

    } elsif( $cmd eq 'pause' || $cmd eq 'play' || $cmd eq 'resume' || $cmd eq 'stop'
             || $cmd eq 'skipNext' || $cmd eq 'skipPrevious' || $cmd eq 'stepBack' || $cmd eq 'stepForward' ) {
      return "$cmd not supported" if( $cmd ne 'pause' && $cmd ne 'play' && $cmd ne 'resume'
                                      && $hash->{controllable} && $hash->{controllable} !~ m/\b$cmd\b/ );
      if( ($cmd eq 'playMedia' || $cmd eq 'resume')  && $hash->{STATE} eq 'stopped' ) {
        my $key = ReadingsVal($name,'key', undef);
        return 'no current media key' if( !$key );
        my $server = ReadingsVal($name,'server', undef);
        return 'no current server' if( !$server );

        my $entry = plex_serverOf($hash, $server, 1);
        return "unknown server: $server" if( !$entry );

        CommandSet( undef, "$hash->{NAME} $cmd $entry->{address} $key" );
        return undef;
      }

      if( $cmd eq 'pause' ) {
        return undef if( $hash->{STATE} !~ m/playing/ );

      } elsif( $cmd eq 'play' ) {
        return undef if( $hash->{STATE} =~ m/playing/ );

      } elsif( $cmd eq 'resume' ) {
        return undef if( $hash->{STATE} =~ m/playing/ );
        $cmd = 'play';

      }

      my $type = $params[0];
      $type = $hash->{currentMediaType} if( !$type );
      $type = "type=$type" if( $type );
      $type = "" if( !$type );

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/playback/$cmd?$type", "playback" );
      return undef;

    } elsif( $cmd eq 'seekTo' ) {
      return "$cmd not supported" if( $hash->{controllable} && $hash->{controllable} !~ m/\b$cmd\b/ );
      return "usage: $cmd <value>" if( !defined($params[0]) );
      $params[0] =~ s/[^\d]//g;

      my $type = $params[1];
      $type = $hash->{currentMediaType} if( !$type );
      $type = "type=$type" if( $type );
      $type = "" if( !$type );

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/playback/seekTo?$type&offset=$params[0]", "parameters" );
      return undef;

    } elsif( $cmd eq 'volume' || $cmd eq 'shuffle' || $cmd eq 'repeat' ) {
      return "$cmd not supported" if( $hash->{controllable} && $hash->{controllable} !~ m/\b$cmd\b/ );
      return "usage: $cmd <value>" if( !defined($params[0]) );
      $params[0] =~ s/[^\d]//g;
      return "usage: $cmd [0/1]" if( $cmd eq 'shuffle' && ($params[0] < 0 || $params[0] > 1) );
      return "usage: $cmd [0/1/2]" if( $cmd eq 'repeat' && ($params[0] < 0 || $params[0] > 2) );
      return "usage: $cmd [0-100]" if( $cmd eq 'volume' && ($params[0] < 0 || $params[0] > 100) );

      my $type = $params[1];
      $type = $hash->{currentMediaType} if( !$type );
      $type = "type=$type" if( $type );
      $type = "" if( !$type );

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/playback/setParameters?$type&$cmd=$params[0]", "parameters" );
      return undef;

    } elsif( $cmd eq 'home' || $cmd eq 'music' ) {
      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/navigation/$cmd?", "navigation" );
      return undef;

    } elsif( $cmd eq 'unwatched' || $cmd eq 'watched' ) {
      my $key = ReadingsVal($name,'key', undef);
      return 'no current media key' if( !$key );
      my $server = ReadingsVal($name,'server', undef);
      return 'no current server' if( !$server );

      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/playback/stop?type=video", "playback" ) if( $cmd == 'watched' );

      my $entry = plex_serverOf($hash, $server, 1);
      return "unknown server: $server" if( !$entry );

      $cmd = $cmd eq 'watched' ? 'scrobble' : 'unscrobble';
      $key =~ s'^/library/metadata/'';
      plex_sendApiCmd( $hash, "http://$entry->{address}:$entry->{port}/:/$cmd?key=$key&identifier=com.plexapp.plugins.library", $cmd );

      return undef;

    }

    $list .= 'playMedia ' if( !$hash->{controllable} || $hash->{controllable} =~ m/\bplayPause\b/ );
    $list .= 'play ' if( $hash->{protocolCapabilities} && $hash->{protocolCapabilities} =~ m/\bplayqueues\b/ );
    $list .= 'resume:noArg ' if( !$hash->{controllable} || $hash->{controllable} =~ m/\bplayPause\b/ );
    $list .= 'pause:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bplayPause\b/ );;
    $list .= 'stop:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bstop\b/ );;
    $list .= 'skipNext:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bskipNext\b/ );;
    $list .= 'skipPrevious:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bskipPrevious\b/ );;
    $list .= 'stepBack:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bstepBack\b/ );;
    $list .= 'stepForward:noArg ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bstepForward\b/ );;
    $list .= 'seekTo ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bseekTo\b/ );;
    $list .= 'mirror ' if( !$hash->{controllable} || $hash->{controllable} =~ m/\bmirror\b/ );
    $list .= 'volume:slider,0,1,100 ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bvolume\b/ );
    $list .= 'repeat ' if( $hash->{controllable} && $hash->{controllable} =~ m/\brepeat\b/ );
    $list .= 'shuffle ' if( $hash->{controllable} && $hash->{controllable} =~ m/\bshuffle\b/ );
    $list .= 'home:noArg music:noArg ';
    $list .= 'unwatched:noArg watched:noArg ';
  }

  if( $modules{plex}{defptr}{MASTER} && $hash == $modules{plex}{defptr}{MASTER} ) {
    if( $cmd eq 'restartDiscovery' ) {
      plex_startDiscovery($hash);

      return undef;

    } elsif( $cmd eq 'subscribe' ) {
      return 'usage: subscribe <id|ip>' if( !$params[0] );

      my $client = plex_clientOf( $hash, $params[0] );
      return "no client found for $params[0]" if( !$client );

      plex_sendSubscription($hash->{helper}{timelineListener}, $client->{address});
      return undef;

    } elsif( $cmd eq 'unsubscribe' ) {
      return 'usage: unsubscribe <id|ip>' if( !$params[0] );

      my $client = plex_clientOf( $hash, $params[0] );
      return "no client found for $params[0]" if( !$client );

      plex_removeSubscription($hash->{helper}{timelineListener}, $client->{address});

      return undef;

    } elsif( $cmd eq 'offline' ) {
      return 'usage: offline <id|ip>' if( !$params[0] );

      my $client = plex_clientOf( $hash, $params[0] );
      return "no client found for $params[0]" if( !$client );

      $client->{online} = 1;
      plex_disappeared($hash, 'client', $client->{address});

      return undef;

    } elsif( $cmd eq 'online' ) {
      return 'usage: online <id|ip>' if( !$params[0] );

      my $client = plex_clientOf( $hash, $params[0] );
      return "no client found for $params[0]" if( !$client );

      $client->{online} = 0;
      plex_discovered($hash, 'client', $client->{address}, $client);

      return undef;

    } elsif( $cmd eq 'showAccount' ) {
      my $user = AttrVal($name, 'user', undef);
      my $password = AttrVal($name, 'password', undef);

      return 'no user set' if( !$user );
      return 'no password set' if( !$password );

      $user = plex_decrypt( $user );
      $password = plex_decrypt( $password );

      return "$user: $password";

    } elsif( $cmd eq 'refreshToken' ) {
      delete $hash->{token};
      plex_getToken($hash);

      return undef;

    }

    $list .= 'restartDiscovery:noArg subscribe unsubscribe showAccount:noArg ';

  }

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
plex_deviceList($$)
{
  my ($hash, $type) = @_;

  my $ret = '';

  my $entries = $hash->{$type};
  $ret .= "$type from discovery:\n";
  $ret .= sprintf( "%16s  %19s  %4s  %-23s  %s\n", 'ip', 'updatedAt', 'onl.', 'name', 'machineIdentifier' );
  foreach my $ip ( keys %{$entries} ) {
    my $entry = $entries->{$ip};
    $ret .= sprintf( "%16s  %19s  %4s  %-23s  %s\n", $entry->{address}, $entry->{updatedAt}?strftime("%Y-%m-%d %H:%M:%S", localtime($entry->{updatedAt}) ):'',, $entry->{online}?'yes':'no', $entry->{name}, $entry->{machineIdentifier} );
  }

  if( $type eq 'servers' && $hash->{'myPlex-servers'} ) {
    $ret .= "\n";
    $ret .= "$type from myPlex:\n";

    if( $hash->{'myPlex-servers'}{Server} ) {
      $ret .= sprintf( "%16s  %19s        %-23s %1s %s\n", 'ip', 'updatedAt', 'name', 'o', 'machineIdentifier' );
      foreach my $entry (@{$hash->{'myPlex-servers'}{Server}}) {
        #next if( !$entry->{owned} );
        $entry->{owned} = 0 if( !defined($entry->{owned}) );
        $entry->{localAddresses} = '' if( !$entry->{localAddresses} );
        $entry->{address} = '' if( !$entry->{address} );
        $ret .= sprintf( "%16s  %19s        %-23s %1s %s\n", $entry->{address}, strftime("%Y-%m-%d %H:%M:%S", localtime($entry->{updatedAt}) ), $entry->{name}, $entry->{owned}, $entry->{machineIdentifier} );
      }
    }
  }
  if( $type eq 'clients' && $hash->{'myPlex-devices'} ) {
    $ret .= "\n";
    $ret .= "$type from myPlex:\n";

    if( $hash->{'myPlex-devices'}{Device} ) {
      $ret .= sprintf( "%16s  %19s  %-25s  %-20s  %-40s  %s\n", 'ip', 'lastSeenAt', 'name', 'product', 'clientIdentifier', 'provides' );
      foreach my $entry (@{$hash->{'myPlex-devices'}{Device}}) {
        next if( !$entry->{provides} );
        #next if( !$entry->{localAddresses} );
        $ret .= sprintf( "%16s  %19s  %-25s  %-20s  %-40s  %s\n", $entry->{localAddresses}?$entry->{localAddresses}:'', $entry->{lastSeenAt}?strftime("%Y-%m-%d %H:%M:%S", localtime($entry->{lastSeenAt}) ):'', $entry->{name}, $entry->{product}, $entry->{clientIdentifier}, $entry->{provides} );
      }
    }
  }

  return $ret;
}

sub
plex_makeLink($$$$;$)
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
plex_makeImage($$$$)
{
  my ($hash, $server, $url, $size) = @_;

  return '' if( !$url );

  my $token = $server->{accessToken};
  $token = $hash->{token} if( !$token );

  my $ret .= "<img src=\"http://$server->{address}:$server->{port}/photo/:/transcode?X-Plex-Token=$token&url=".
             urlEncode("127.0.0.1:32400$url?X-Plex-Token=$token")
             ."&width=$size&height=$size\">\n";

  return $ret;
}


sub
plex_mediaList2($$$$;$)
{
  my ($hash, $type, $xml, $items, $cmd) = @_;

  if( $items ) {
    if( 0 && !$xml->{sortAsc} ) {
      my @items;
      if( $xml->{Track} ) {
        @items = sort { $a->{index} <=> $b->{index} } @{$items};
      } else {
        @items = sort { $a->{title} cmp $b->{title} } @{$items};
      }
      $items = \@items;
    }
  }

  my $ret;
  if( $type eq 'Directory' ) {
#Log 1, Dumper $items;
    $ret .= "\n" if( $ret );
    $ret .= "$type\n";
    $ret .= sprintf( "%-35s %-10s %s\n", 'key', 'type', 'title' );
    foreach my $item (@{$items}) {
      $item->{type} = '' if( !$item->{type} );
      $item->{title} = encode('UTF-8', $item->{title});
      $ret .= plex_makeLink($hash, 'ls', $xml->{parentSection}, $item->{key}, sprintf( "%-35s %-10s %s", $item->{key}, $item->{type}, $item->{title} ) );
      $ret .= " ($item->{year})" if( $item->{year} );
      $ret .= "\n";
    }

  }

 if( $type eq 'Playlist' ) {
    $ret .= "\n" if( $ret );
    $ret .= "$type\n";
    $ret .= sprintf( "%-35s %-10s %s\n", 'key', 'type', 'title' );
    foreach my $item (@{$items}) {
      $item->{type} = '' if( !$item->{type} );
      $item->{title} = encode('UTF-8', $item->{title});
      $ret .= plex_makeLink($hash, 'ls', $xml->{parentSection}, $item->{key}, sprintf( "%-35s %-10s %s\n", $item->{key}, $item->{type}, $item->{title} ) );
      #$ret .= plex_makeImage($hash, $server, $xml->{composite}, 100);
    }

  }

 if( $type  eq 'Video' ) {
    $ret .= "\n" if( $ret );
    $ret .= "$type\n";
    $ret .= sprintf( "%-35s %-10s  nr %s\n", 'key', 'type', 'title' );
    foreach my $item (@{$items}) {
      $item->{title} = encode('UTF-8', $item->{title});
      if( defined($item->{index}) ) {
        $ret .= plex_makeLink($hash, 'detail', $xml->{parentSection}, $item->{key}, sprintf( "%-35s %-10s %3i %s", $item->{key}, $item->{type}, $item->{index}, $item->{title} ) );
        $ret .= plex_makeLink($hash,'detail', undef, $item->{grandparentKey}, "  ($item->{grandparentTitle}" ) if( $item->{grandparentTitle} );
        #$ret .= "  ($item->{year})" if( $item->{year} );
        $ret .= sprintf(": S%02iE%02i",$item->{parentIndex}, $item->{index} ) if( $item->{parentIndex} );
        $ret .= ")" if( $item->{grandparentTitle} );
      } else {
        $ret .= plex_makeLink($hash,'detail',  $xml->{parentSection}, $item->{key}, sprintf( "%-35s %-10s     %s", $item->{key}, $item->{type}, $item->{title} ) );
      }

      if( $cmd && $cmd eq 'files'
          && $item->{Media} && $item->{Media}[0]{Part}  ) {
        $ret .= " ($item->{Media}[0]{Part}[0]{file})";
      }
      $ret .= "\n";
    }
  }

  if( $type eq 'Track' ) {
    $ret .= "\n" if( $ret );
    $ret .= "$type\n";
    $ret .= sprintf( "%-35s %-10s  nr %s\n", 'key', 'type', 'title' );
    foreach my $item (@{$items}) {
      $item->{title} = encode('UTF-8', $item->{title});
      $ret .= sprintf( "%-35s %-10s %3i %s\n", $item->{key}, $item->{type}, $item->{index}, $item->{title} );
    }
  }

  return $ret;
}

sub
plex_mediaList($$$;$)
{
  my ($hash, $server, $xml, $cmd) = @_;

#Log 1, Dumper $xml;
  return $xml if( ref($xml) ne 'HASH' );

  $xml->{librarySectionTitle} = encode('UTF-8', $xml->{librarySectionTitle}) if( $xml->{librarySectionTitle} );
  $xml->{title} = encode('UTF-8', $xml->{title}) if( $xml->{title} );
  $xml->{title1} = encode('UTF-8', $xml->{title1}) if( $xml->{title1} );
  $xml->{title2} = encode('UTF-8', $xml->{title2}) if( $xml->{title2} );
  $xml->{title3} = encode('UTF-8', $xml->{title3}) if( $xml->{title3} );

  my $ret = '';
  $ret .= plex_makeImage($hash, $server, $xml->{thumb}, 100);
  $ret .= plex_makeImage($hash, $server, $xml->{composite}, 100);
  $ret .= "$xml->{librarySectionTitle}: " if( $xml->{librarySectionTitle} );
  $ret .= plex_makeLink($hash, 'detail', undef, $xml->{ratingKey}, "$xml->{title} ") if( $xml->{title} );
  $ret .= plex_makeLink($hash, 'detail', undef, $xml->{grandparentRatingKey}, "$xml->{title1} ") if( $xml->{title1} );
  $ret .= plex_makeLink($hash, 'detail', undef, $xml->{key}, "; $xml->{title2} ") if( $xml->{title2} );
  $ret .= "; $xml->{title3} " if( $xml->{title3} );
  $ret .= "\n";

  $ret .= plex_mediaList2( $hash, 'Directory', $xml, $xml->{Directory} ) if( $xml->{Directory} );
  $ret .= plex_mediaList2( $hash, 'Playlist', $xml, $xml->{Playlist} ) if( $xml->{Playlist} );
  $ret .= plex_mediaList2( $hash, 'Video', $xml, $xml->{Video}, $cmd ) if( $xml->{Video} );
  $ret .= plex_mediaList2( $hash, 'Track', $xml, $xml->{Track} ) if( $xml->{Track} );

  if( !$xml->{Directory} && !$xml->{Playlist} && !$xml->{Video} && !$xml->{Track} ) {
    return $xml->{head}[0]{title}[0] if( ref $xml->{head} eq 'ARRAY' && ref $xml->{head}[0]{title} eq 'ARRAY' );
    return "unknown media type";

  }

  return $ret;
}

sub
plex_mediaDetail2($$$$)
{
  my ($hash, $server, $xml, $items) = @_;

#Log 1, Dumper $xml;

  if( $items ) {
    if( 0 && !$xml->{sortAsc} ) {
      my @items = sort { $a->{index} <=> $b->{index} } @{$items};
      #my @items = sort { $a->{title} cmp $b->{title} } @{$items};
      $items = \@items;
    }
  }

  $xml->{viewGroup} = encode('UTF-8', $xml->{viewGroup}) if( $xml->{viewGroup} );

  my $ret = '';
  foreach my $item (@{$items}) {
    $item->{grandparentTitle} = encode('UTF-8', $item->{grandparentTitle}) if( $item->{grandparentTitle} );
    $item->{parentTitle} = encode('UTF-8', $item->{parentTitle}) if( $item->{parentTitle} );
    $item->{title} = encode('UTF-8', $item->{title}) if( $item->{title} );
    $item->{summary} = encode('UTF-8', $item->{summary}) if( $item->{summary} );

    $ret .= "\n" if( $ret && (!$xml->{viewGroup} || ($xml->{viewGroup} ne 'track' && $xml->{viewGroup} ne 'secondary') ) );
    if( $item->{type} eq 'playlist' ) {
      $ret .= sprintf( "%s  ", $item->{title} ) if( $item->{title} );
      $ret .= "\n";
      $ret .= plex_makeImage($hash, $server, $item->{composite}, 250);
      $ret .= "\n";
      $ret .= sprintf( "%s  ", $item->{playlistType} ) if( $item->{playlistType} );
      $ret .= sprintf( "%s  ", plex_timestamp2date($item->{addedAt}) ) if( $item->{addedAt} );
      $ret .= sprintf( "items: %i  ", $item->{leafCount} ) if( $item->{leafCount} && $item->{leafCount} > 1 );
      $ret .= sprintf( "viewCount: %i  ", $item->{viewCount} ) if( $item->{viewCount} );
      $ret .= "\n";

    } elsif( $item->{type} eq 'album' || $item->{type} eq 'artist' || $item->{type} eq 'show' || $item->{type} eq 'season' ) {
      $ret .= plex_makeLink($hash, 'detail', undef, $item->{grandparentRatingKey}, "$item->{grandparentTitle}: ") if( $item->{grandparentTitle} );
      $ret .= plex_makeLink($hash, 'detail', undef, $item->{parentRatingKey}, "$item->{parentTitle}: ") if( $item->{parentTitle} );
      $ret .= sprintf( "%s  ", $item->{title} ) if( $item->{title} );
      $ret .= sprintf("(S%02iE%02i)",$item->{parentIndex}, $item->{index} ) if( $item->{parentIndex} && $item->{type} ne 'season' );
      #$ret .= sprintf("(S%02i)", $item->{index} ) if( $item->{index} && $item->{type} eq 'season' );
      $ret .= "\n";
      $ret .= plex_makeImage($hash, $server, $item->{thumb}, 250);
      $ret .= "\n";
      if( $item->{Genre} ) {
        foreach my $genre ( @{$item->{Genre}}) {
          $ret .= sprintf( "%s ", $genre->{tag} ) if( $genre->{tag} );
        }
        $ret .= ' ';
      }
      $ret .= sprintf( "%s  ", $item->{contentRating} ) if( $item->{contentRating} );
      $ret .= sprintf( "%s  ", $item->{rating} ) if( $item->{rating} );
      $ret .= sprintf( "%i  ", $item->{year} ) if( $item->{year} );
      $ret .= sprintf( "%s  ", plex_timestamp2date($item->{addedAt}) ) if( $item->{addedAt} );
      $ret .= sprintf( "items: %i  ", $item->{leafCount} ) if( $item->{leafCount} && $item->{leafCount} > 1 );
      $ret .= sprintf( "viewCount: %i  ", $item->{viewCount} ) if( $item->{viewCount} );
      $ret .= "\n";

    } elsif( $item->{type} eq 'track' ) {
      $ret .= sprintf("(Disk %02i Track %02i)  ",$item->{parentIndex}, $item->{index} ) if( $item->{parentIndex} );
      $ret .= sprintf("%2i  ",$item->{index}, $item->{index} ) if( !$item->{parentIndex} );
      $ret .= plex_sec2hms($item->{duration}/1000);
      $ret .= "  ";
      $ret .= sprintf( "%s: ", $item->{grandparentTitle} ) if( !$xml->{title1} && $item->{grandparentTitle} );
      $ret .= sprintf( "%s: ", $item->{parentTitle} ) if( !$xml->{title2} && $item->{parentTitle} );
      $ret .= sprintf( "%s  ", $item->{title} ) if( $item->{title} );
      #$ret .= "\n";
      $ret .= "\n";
      $ret .= plex_makeImage($hash, $server, $item->{thumb}, 250);
      #$ret .= "\n";
      $ret .= sprintf( "%s  ", $item->{contentRating} ) if( $item->{contentRating} );
      $ret .= sprintf( "%i  ", $item->{year} ) if( $item->{year} );
      #$ret .= sprintf( "%s  ", plex_timestamp2date($item->{addedAt}) ) if( $item->{addedAt} );
      #$ret .= sprintf( "viewCount: %i  ", $item->{viewCount} ) if( $item->{viewCount} );
      #$ret .= "\n";

    } elsif( $item->{type} eq 'episode' || $item->{type} eq 'movie' ) {
      $ret .= plex_makeLink($hash, 'detail', undef, $item->{grandparentRatingKey}, "$item->{grandparentTitle}: ") if( $item->{grandparentTitle} );
      $ret .= plex_makeLink($hash, 'detail', undef, $item->{parentKey}, "; $item->{parentTitle} ") if( $item->{parentTitle} );
      $ret .= sprintf( "%s  ", $item->{title} ) if( $item->{title} );
      $ret .= sprintf("(S%02iE%02i)",$item->{parentIndex}, $item->{index} ) if( defined($item->{parentIndex}) );
      $ret .= sprintf("(Episode %02i)",$item->{index}, $item->{index} ) if( !defined($item->{parentIndex}) && $item->{index} );
      $ret .= "  ";
      $ret .= plex_sec2hms($item->{duration}/1000);
      $ret .= "\n";
      $ret .= plex_makeImage($hash, $server, $item->{thumb}, 250);
      $ret .= "\n";
      $ret .= sprintf( "%s  ", $item->{contentRating} ) if( $item->{contentRating} );
      $ret .= sprintf( "%s  ", $item->{rating} ) if( $item->{rating} );
      $ret .= sprintf( "%i  ", $item->{year} ) if( $item->{year} );
      $ret .= sprintf( "%s  ", plex_timestamp2date($item->{addedAt}) ) if( $item->{addedAt} );
      $ret .= sprintf( "viewCount: %i  ", $item->{viewCount} ) if( $item->{viewCount} );
      $ret .= "\n";
    } elsif( $item->{type} ) {
      $ret .= "unknown item type: $item->{type}\n";

    } else {
      $ret .= sprintf( "%-35s %-10s %s\n", $item->{key}, $item->{title} );

    }

    if( !$xml->{viewGroup} || ($xml->{viewGroup} ne 'track' && $xml->{viewGroup} ne 'secondary')  ) {
      if( my $mhash = $modules{plex}{defptr}{MASTER} ) {
        if( my $clients = $mhash->{clients} ) {
          $ret .= "\nplay: ";
          foreach my $ip ( keys %{$clients} ) {
            my $client = $clients->{$ip};
            next if( !$client->{online} );

            my $cmd = 'play';
            my $key = $item->{key};
            $key =~ s/.children$//;
            $cmd = "set $hash->{NAME} $client->{address} $cmd $key";
            $ret .= "<a style=\"cursor:pointer\" onClick=\"FW_cmd(\\\'$FW_ME$FW_subdir?XHR=1&cmd=$cmd\\\')\">$ip</a>  ";
          }
          $ret .= "\n\n";
        }
      }
    }

    $ret .=  $item->{summary} ."\n" if( $item->{summary} );
  }

  return $ret;
}

sub
plex_mediaDetail($$$)
{
  my ($hash, $server, $xml) = @_;

  return $xml if( ref($xml) ne 'HASH' );

  $xml->{title} = encode('UTF-8', $xml->{title}) if( $xml->{title} );
  $xml->{title1} = encode('UTF-8', $xml->{title1}) if( $xml->{title1} );
  $xml->{title2} = encode('UTF-8', $xml->{title2}) if( $xml->{title2} );
  $xml->{summary} = encode('UTF-8', $xml->{summary}) if( $xml->{summary} );

#Log 1, Dumper $xml;
  my $ret = '';
  $ret .= plex_makeImage($hash, $server, $xml->{thumb}, 250);
  $ret .= plex_makeLink($hash, 'detail', undef, $xml->{ratingKey}, "$xml->{title} ") if( $xml->{title} );
  $ret .= sprintf( "%s: ", $xml->{title1} ) if( $xml->{title1} );
  $ret .= sprintf( "%s: ", $xml->{title2} ) if( $xml->{title2} );
  $ret .= sprintf( "(%s)\n", $xml->{parentYear} ) if( $xml->{parentYear} );

  $ret .=  $xml->{summary} ."\n" if( $xml->{summary} );

  $ret .= plex_mediaDetail2( $hash, $server, $xml, $xml->{Directory} ) if( $xml->{Directory} );
  $ret .= plex_mediaDetail2( $hash, $server, $xml, $xml->{Playlist} ) if( $xml->{Playlist} );
  $ret .= plex_mediaDetail2( $hash, $server, $xml, $xml->{Video} ) if( $xml->{Video} );
  $ret .= plex_mediaDetail2( $hash, $server, $xml, $xml->{Track} ) if( $xml->{Track} );

  if( !$xml->{Directory} && !$xml->{Playlist} && !$xml->{Video} && !$xml->{Track} ) {
Log 1, Dumper $xml;
    return "unknown media type";

  }

  return $ret;
}

sub
plex_Get($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  my $list = '';

  if( my $hash = $modules{plex}{defptr}{MASTER} ) {
    if( $cmd eq 'servers' || $cmd eq 'clients' ) {
      if( my $entry = plex_serverOf($hash, $cmd, !$hash->{machineIdentifier}) ) {
        plex_sendApiCmd( $hash, "http://$entry->{address}:$entry->{port}/clients", "clients" );
      }

      return plex_deviceList($hash, $cmd );

    } elsif( $cmd eq 'pin' ) {
      return plex_getPinForToken($hash);

    }

    $list .= 'clients:noArg servers:noArg pin:noArg ';
  }

  if( my $entry = plex_serverOf($hash, $cmd, !$hash->{machineIdentifier}) ) {
    my @params = @params;
    $cmd = shift @params if( $cmd eq $entry->{address} );
    $cmd = shift @params if( $cmd eq $entry->{machineIdentifier} );

    if( $cmd eq 'servers' ) {
      return plex_deviceList($hash, 'servers' );

    } elsif( $cmd eq 'clients' ) {
      return plex_deviceList($hash, 'clients' );

    } elsif( $cmd eq 'pin' ) {
      return plex_getPinForToken($hash);

    }

    my $ip = $entry->{address};

    return "server $ip not online" if( $cmd ne '?' && !$entry->{online} );

    my $param = shift( @params );
    if( !$param ) {
      $param = '';
    }

    if( $cmd eq 'sections' || $cmd eq 'ls' || $cmd eq 'files' ) {
      $param = "/$param" if( $param && $param !~ '^/' );
      my $ret;
      if( $param =~ m'/playlists' ) {
        $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}$param", 'sections', $hash->{CL} || 1, $entry->{accessToken} );

      } elsif( $param =~ m'^/library' ) {
        $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}$param", "sections:$param $cmd", $hash->{CL} || 1, $entry->{accessToken} );

      } else {
        $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/library/sections$param", "sections:$param $cmd", $hash->{CL} || 1, $entry->{accessToken} );
      }

      return $ret;

    } elsif( $cmd eq 'search' ) {
      return "usage: search <keywords>" if( !$param );
      $param .= ' '. join( ' ', @params ) if( @params );
      $param = urlEncode( $param );
      my $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/search?query=$param", 'search', $hash->{CL} || 1 );

      return $ret;

    } elsif( $cmd eq 'playlists' ) {
      $param = "/$param" if( $param && $param !~ '^/' );
      $param = '' if( !$param );
      $param =~ s'^/playlists'';
      my $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/playlists$param", "playlists", $hash->{CL} || 1 );

      return $ret;

    } elsif( $cmd eq 'sessions' ) {
      my $xml = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/status/sessions", 'sessions', 1 );
      return undef if( !$xml );
      return Dumper $xml;

    } elsif( $cmd eq 'identity' ) {
      my $xml = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/identity", 'identity', 1 );
      return undef if( !$xml );
      return Dumper $xml;

    } elsif( $cmd eq 'detail' ) {
      return "usage: detail <key>" if( !$param );
      my $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}$param", 'detail', $hash->{CL} || 1 );

      return $ret;

    } elsif( lc($cmd) eq 'ondeck' ) {
      my $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/library/onDeck", 'onDeck', $hash->{CL} || 1 );

      return $ret;

    } elsif( lc($cmd) eq 'recentlyadded' ) {
      my $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/library/recentlyAdded", 'recentlyAdded', $hash->{CL} || 1 );

      return $ret;

    } elsif( $cmd eq 'm3u' || $cmd eq 'pls' ) {
      return "usage: $cmd <key>" if( !$param );

      $param = "/library/metadata/$param" if( $param !~ '^/' );

      my $ret;
      if( $param =~ m'/playlists' ) {
        $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}$param", "#$cmd:$entry->{machineIdentifier}", $hash->{CL} || 1 );

      } else {
        $ret = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}$param", "#$cmd:$entry->{machineIdentifier}", $hash->{CL} || 1 );

      }

      return $ret;

    }

    $list .= 'identity:noArg ls files search sessions:noArg detail onDeck:noArg recentlyAdded:noArg playlists:noArg ';
    $list .= 'servers:noArg pin:noArg ' if( $list !~ m/\bservers\b/ );

  }

  if( my $entry = plex_clientOf($hash, $cmd) ) {
    my @params = @params;
    $cmd = shift @params if( $cmd eq $entry->{address} );
    $cmd = shift @params if( $cmd eq $entry->{machineIdentifier} );

    my $key = ReadingsVal($name,'key', undef);
    my $server = ReadingsVal($name,'server', undef);
    if( $cmd eq 'detail' ) {
      return 'no current media key' if( !$key );
      return 'no current server' if( !$server );

      my $entry = plex_serverOf($hash, $server, 1);
      return "unknown server: $server" if( !$entry );

      my $ret = plex_sendApiCmd( $hash, "http://$entry->{address}:$entry->{port}$key", 'detail', $hash->{CL} || 1 );

      return $ret;

    }

    my $ip = $entry->{address};
    return "client $ip not online" if( $cmd ne '?' && !$entry->{online} );

    if( $cmd eq 'resources' ) {
      my $xml = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/resources", 'resources', 1 );
      return undef if( !$xml );
      return Dumper $xml;

    } elsif( $cmd eq 'timeline' ) {
      my $xml = plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/player/timeline/poll?&wait=0", 'timeline', 1 );
      return undef if( !$xml );
      return Dumper $xml;

    }

    $list .= 'detail:noArg ';
    $list .= 'resources:noArg timeline:noArg ';
  }

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
plex_encrypt($)
{
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /^crypt:(.*)/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'. $encoded;
}
sub
plex_decrypt($)
{
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  $encoded = $1 if( $encoded =~ /^crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}

sub
plex_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  my $hash = $defs{$name};
  if( $attrName eq 'disable' ) {
    if( $cmd eq "set" && $attrVal ) {
      plex_stopTimelineListener($hash);
      plex_stopWebsockets($hash);
      plex_stopDiscovery($hash);
      foreach my $ip ( keys %{$hash->{clients}} ) {
        $hash->{clients}{$ip}{online} = 0;
      }
      readingsSingleUpdate($hash, 'state', 'disabled', 1 );
    } else {
      readingsSingleUpdate($hash, 'state', 'running', 1 );
      $attr{$name}{$attrName} = 0;
      plex_startDiscovery($hash);
      plex_startTimelineListener($hash);
    }

  } elsif( $attrName eq 'httpPort' ) {
      plex_stopTimelineListener($hash);
      plex_startTimelineListener($hash);

  } elsif( $attrName eq 'responder' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attr{$name}{$attrName} = 1;
      plex_startDiscovery($hash);

    } else {
      $attr{$name}{$attrName} = 0;
      plex_startDiscovery($hash);

    }

  } elsif( $attrName eq 'user' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attrVal = plex_encrypt($attrVal);

      if( $attr{$name}{'user'} && $attr{$name}{'password'} ) {
        delete $hash->{token};
        plex_getToken($hash);
      }
    }

  } elsif( $attrName eq 'password' ) {
    if( $cmd eq "set" && $attrVal ) {
      $attrVal = plex_encrypt($attrVal);

      if( $attr{$name}{'user'} && $attr{$name}{'password'} ) {
        delete $hash->{token};
        plex_getToken($hash);
      }
    }

  } elsif( $attrName eq 'fhemIP' ) {
    if( $cmd eq "set" && $attrVal ) {
      $hash->{fhemIP} = $attrVal;
    } else {
      $hash->{fhemIP} = plex_getLocalIP();
    }
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
plex_getToken($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return $hash->{token} if( $hash->{token} );

  my $user = AttrVal($name, 'user', undef);
  my $password = AttrVal($name, 'password', undef);

  return '' if( !$user );
  return '' if( !$password );

  $user = plex_decrypt( $user );
  $password = plex_decrypt( $password );

  my $url = 'https://plex.tv/users/sign_in.xml';

  Log3 $name, 4, "$name: requesting $url";

  my $param = {
    url => $url,
    method => 'POST',
    timeout => 5,
    noshutdown => 0,
    hash => $hash,
    key => 'token',
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
    data => { 'user[login]' => $user, 'user[password]' => $password },
  };

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}
sub
plex_getPinForToken($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "plex_getTokenOfPin");

  my $url = 'https://plex.tv/pins.xml';

  Log3 $name, 4, "$name: requesting $url";

  my $param = {
    url => $url,
    method => 'POST',
    timeout => 5,
    noshutdown => 0,
    hash => $hash,
    key => 'getPinForToken',
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
  };

  $param->{cl} = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}
sub
plex_getTokenOfPin($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash, "plex_getTokenOfPin");

  Log3 $name, 2, "$name: no PIN" if( !$hash->{PIN} );

  return undef if( !$hash->{PIN} );
  return undef if( !$hash->{PIN_ID} );

  my $url = "https://plex.tv/pins/$hash->{PIN_ID}.xml";

  Log3 $name, 4, "$name: requesting $url";

  my $param = {
    url => $url,
    method => 'GET',
    timeout => 5,
    noshutdown => 0,
    hash => $hash,
    key => 'tokenOfPin',
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
  };

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}
sub
plex_sendApiCmd($$$;$$)
{
  my ($hash,$url,$key,$blocking,$token) = @_;
  $token = $hash->{token} if( !$token && $hash->{token} );
  my $name = $hash->{NAME};

  if( $url =~ m/.player./ ) {
    my $mhash = $modules{plex}{defptr}{MASTER};
    $mhash = $hash if( !$mhash );
    ++$mhash->{commandID};
    $url .= "&commandID=$mhash->{commandID}";
  }

  Log3 $name, 4, "$name: requesting $url";

  my $address;
  my $port;
  if( $url =~ m'//([^:]*):(\d*)' ) {
    $address = $1;
    $port = $2;
  }

#X-Plex-Platform (Platform name, eg iOS, MacOSX, Android, LG, etc)
#X-Plex-Platform-Version (Operating system version, eg 4.3.1, 10.6.7, 3.2)
#X-Plex-Provides (one or more of [player, controller, server])
#X-Plex-Product (Plex application name, eg Laika, Plex Media Server, Media Link)
#X-Plex-Version (Plex application version number)
#X-Plex-Device (Device name and model number, eg iPhone3,2, Motorola XOOM™, LG5200TV)
#X-Plex-Client-Identifier (UUID, serial number, or other number unique per device)

  my $param = {
    url => $url,
    timeout => 5,
    noshutdown => 1,
    httpversion => '1.1',
    hash => $hash,
    key => $key,
    address => $address,
    port => $port,
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
  };
  $param->{header}{'X-Plex-Token'} = $token if( $token );
  if( my $entry = plex_entryOfIP($hash, 'client', $address) ) {
    $param->{header}{'X-Plex-Target-Client-Identifier'} = $entry->{machineIdentifier} if( $entry->{machineIdentifier} );
  }

  $param->{cl} = $blocking if( ref($blocking) eq 'HASH' );

  if( $blocking && (!ref($blocking) || !$blocking->{canAsyncOutput}) ) {
    my($err,$data) = HttpUtils_BlockingGet( $param );

    return $err if( $err );

    $param->{blocking} = 1;
    return( plex_parseHttpAnswer( $param, $err, $data ) );
  }

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}
sub
plex_play($$$$)
{
  my ($hash, $client, $server,$key) = @_;
  my $name = $hash->{NAME};

  my $url;
  if ($key =~ m/\bplaylists\b/) { #play playlist
    $key =~ s/[^0-9]//g;
    $url = "http://$server->{address}:$server->{port}/playQueues?type=&playlistID=$key";
    $url .= "&shuffle=0&repeat=0&includeChapters=1&includeRelated=1";
  } else { # play album or single track
    $key = "/library/metadata/$key" if( $key !~ '^/' );
    my $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}$key", '#raw', 1, $server->{accessToken} );
    #Log 1, Dumper $xml;
    if( !$xml || !$xml->{librarySectionUUID} ) {
      return $xml->{head}[0]{title}[0] if( ref $xml->{head} eq 'ARRAY' && ref $xml->{head}[0]{title} eq 'ARRAY' );
      return "item not found";
    }
    $url = "http://$server->{address}:$server->{port}/playQueues?type=&uri=". urlEncode( "library://$xml->{librarySectionUUID}/item/$key" );
    $url .= "&shuffle=0&repeat=0&includeChapters=1&includeRelated=1";
  }
  Log3 $name, 4, "$name: requesting $url";

  my $address;
  my $port;
  if( $url =~ m'//([^:]*):(\d*)' ) {
    $address = $1;
    $port = $2;
  }

#X-Plex-Platform (Platform name, eg iOS, MacOSX, Android, LG, etc)
#X-Plex-Platform-Version (Operating system version, eg 4.3.1, 10.6.7, 3.2)
#X-Plex-Provides (one or more of [player, controller, server])
#X-Plex-Product (Plex application name, eg Laika, Plex Media Server, Media Link)
#X-Plex-Version (Plex application version number)
#X-Plex-Device (Device name and model number, eg iPhone3,2, Motorola XOOM™, LG5200TV)
#X-Plex-Client-Identifier (UUID, serial number, or other number unique per device)

  my $param = {
    url => $url,
    method => 'POST',
    timeout => 5,
    noshutdown => 1,
    httpversion => '1.1',
    hash => $hash,
    key => 'playAlbum',
    album => $key,
    client => $client,
    server => $server,
    address => $address,
    port => $port,
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
  };
  $param->{header}{'X-Plex-Token'} = $hash->{token} if( $hash->{token} );
  $param->{header}{'X-Plex-Token'} = $server->{accessToken} if( $server->{accessToken} );
  if( my $entry = plex_entryOfIP($hash, 'client', $address) ) {
    $param->{header}{'X-Plex-Target-Client-Identifier'} = $entry->{machineIdentifier} if( $entry->{machineIdentifier} );
  }

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}
sub
plex_addToPlaylist($$$$)
{
  my ($hash, $server,$playlist,$key) = @_;
  my $name = $hash->{NAME};

  $playlist = "/playlists/$playlist" if( $playlist !~ '^/' );
  $playlist .= "/items" if( $playlist !~ '/items$' );

  $key = "/library/metadata/$key" if( $key !~ '^/' );

  my $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}$key", '#raw', 1 );
#Log 1, Dumper $xml;
  return "item not found" if( !$xml || !$xml->{librarySectionUUID} );

  my $url = "http://$server->{address}:$server->{port}$playlist?uri=". urlEncode( "library://$xml->{librarySectionUUID}/directory$key" );

  Log3 $name, 4, "$name: requesting $url";

  my $address;
  my $port;
  if( $url =~ m'//([^:]*):(\d*)' ) {
    $address = $1;
    $port = $2;
  }

#X-Plex-Platform (Platform name, eg iOS, MacOSX, Android, LG, etc)
#X-Plex-Platform-Version (Operating system version, eg 4.3.1, 10.6.7, 3.2)
#X-Plex-Provides (one or more of [player, controller, server])
#X-Plex-Product (Plex application name, eg Laika, Plex Media Server, Media Link)
#X-Plex-Version (Plex application version number)
#X-Plex-Device (Device name and model number, eg iPhone3,2, Motorola XOOM™, LG5200TV)
#X-Plex-Client-Identifier (UUID, serial number, or other number unique per device)

  my $param = {
    url => $url,
    method => 'PUT',
    timeout => 5,
    noshutdown => 1,
    httpversion => '1.1',
    hash => $hash,
    key => 'addToPlaylist',
    server => $server,
    address => $address,
    port => $port,
    header => { 'X-Plex-Provides' => 'controller',
                'X-Plex-Client-Identifier' => $hash->{id},
                'X-Plex-Platform' => $^O,
                #'X-Plex-Device' => 'FHEM',
                'X-Plex-Device-Name' => $hash->{fhemHostname},
                'X-Plex-Product' => 'FHEM',
                'X-Plex-Version' => '0.0', },
  };
  $param->{header}{'X-Plex-Token'} = $hash->{token} if( $hash->{token} );
  $param->{header}{'X-Plex-Token'} = $server->{accessToken} if( $server->{accessToken} );
  if( my $entry = plex_entryOfIP($hash, 'client', $address) ) {
    $param->{header}{'X-Plex-Target-Client-Identifier'} = $entry->{machineIdentifier} if( $entry->{machineIdentifier} );
  }

  $param->{callback} = \&plex_parseHttpAnswer;
  HttpUtils_NonblockingGet( $param );

  return undef;
}

sub plex_entryOfID($$$);
sub plex_entryOfIP($$$);
sub
plex_entryOfID($$$)
{
  my ($hash,$type,$id) = @_;

  return undef if( !$id );

  $hash->{$type.'s'} = {} if( !$hash->{$type.'s'} );

  my $entries = $hash->{$type.'s'};
  foreach my $ip ( keys %{$entries} ) {
    return $entries->{$ip} if( $entries->{$ip}{machineIdentifier} && $entries->{$ip}{machineIdentifier} eq $id );
    return $entries->{$ip} if( $entries->{$ip}{resourceIdentifier} && $entries->{$ip}{resourceIdentifier} eq $id );
  }

  if( $type eq 'server' ) {
    if( $hash->{'myPlex-servers'}{Server} ) {
      foreach my $entry (@{$hash->{'myPlex-servers'}{Server}}) {
        if( $id eq  $entry->{machineIdentifier} ) {
          $entry->{online} = 1;
          return $entry;
        }
      }
    }
  }

  if( my $mhash = $modules{plex}{defptr}{MASTER} ) {
    return plex_entryOfID($mhash,$type,$id) if( $mhash != $hash );
  }

  return undef;
}
sub
plex_entryOfIP($$$)
{
  my ($hash,$type,$ip) = @_;

  return undef if( !$ip );

  $hash->{$type.'s'} = {} if( !$hash->{$type.'s'} );

  my $entries = $hash->{$type.'s'};

  foreach my $key ( keys %{$entries} ) {
    return $entries->{$key} if( $entries->{$key}{address} eq $ip );
  }

  if( $type eq 'server' ) {
    if( $hash->{'myPlex-servers'}{Server} ) {
      foreach my $entry (@{$hash->{'myPlex-servers'}{Server}}) {
        if( $ip eq  $entry->{address} ) {
          $entry->{online} = 1;
          return $entry;
        }
      }
    }
  }

  if( my $mhash = $modules{plex}{defptr}{MASTER} ) {
    return plex_entryOfIP($mhash,$type,$ip) if( $mhash != $hash );
  }

  return undef;
}
sub
plex_serverOf($$;$)
{
  my ($hash,$server,$only) = @_;

  my $entry;
  $entry = plex_entryOfID($hash, 'server', $hash->{currentServer} ) if( $hash->{currentServer} );

  $entry = plex_entryOfIP($hash, 'server', $server) if( $server && $server =~ m/^\d+\.\d+\.\d+\.\d+$/ );

  $entry = plex_entryOfID($hash, 'server', $server) if( $server && !$entry );

  $entry = plex_entryOfIP($hash, 'server', $hash->{server} ) if( !$entry );

  $entry = plex_entryOfID($hash, 'server', $hash->{machineIdentifier} ) if( !$entry );

  $entry = plex_entryOfID($hash, 'server', $hash->{resourceIdentifier} ) if( !$entry );

  if( !$entry && $only ) {
    if( my $mhash = $modules{plex}{defptr}{MASTER} ) {
#Log 1, Dumper $mhash;
      my @keys = keys(%{$modules{plex}{defptr}{MASTER}{servers}});
      if( @keys == 1 ) {
        $entry = $modules{plex}{defptr}{MASTER}{servers}{$keys[0]};
      }
    } elsif( $hash->{server} && $hash->{servers} ) {
      my @keys = keys(%{$hash->{servers}});
      if( @keys == 1 ) {
        $entry = $hash->{servers}{$keys[0]};
      }
    }
  }

  return $entry;
}
sub
plex_clientOf($$)
{
  my ($hash,$client) = @_;

  if( my $chash = $defs{$client} ) {
    $client = $chash->{machineIdentifier} if( $chash->{machineIdentifier} );
  }

  my $entry;
     $entry = plex_entryOfIP($hash, 'client', $client) if( $client =~ m/^\d+\.\d+\.\d+\.\d+$/ );

  $entry = plex_entryOfID($hash, 'client', $client) if( !$entry );

  $entry = plex_entryOfIP($hash, 'client', $hash->{client} ) if( !$entry );

  $entry = plex_entryOfID($hash, 'client', $hash->{machineIdentifier} ) if( !$entry );

  $entry = plex_entryOfID($hash, 'client', $hash->{resourceIdentifier} ) if( !$entry );

  return $entry;
}

sub
plex_msg2hash($;$)
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
      $key = lcfirst( $key );
    }

    $value =~ s/^ //;
    $hash{$key} = $value;
  }

  return \%hash;
}
sub
plex_hash2header($)
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
plex_hash2form($)
{
  my ($hash) = @_;

  return $hash if( ref($hash) ne 'HASH' );

  my $form;
  foreach my $key (keys %{$hash}) {
    $form .= "&" if( $form );
    $form .= "$key=".urlEncode($hash->{$key});
  }

  return $form;
}
sub
plex_discovered($$$$)
{
  my ($hash, $type, $ip, $entry) = @_;
  my $name = $hash->{NAME};

  if( !$type ) {
    $type = 'server' if( $hash->{servers}{$ip} || ($hash->{server} && $hash->{server} eq $ip) );
    $type = 'client' if( $hash->{clients}{$ip} || ($hash->{client} && $hash->{client} eq $ip) );

    return undef if( !$type );
  }

  $hash->{$type.'s'} = {} if( !$hash->{$type.'s'} );

  my $entries = $hash->{$type.'s'};
  my $new;
     $new = 1 if( !$entries->{$ip} || !$entries->{$ip}{online}
                  || !$entries->{$ip}{port} || !$entry->{port} || $entries->{$ip}{port} ne $entry->{port} );

  if( $new ) {
    $entry->{machineIdentifier} = $entry->{resourceIdentifier} if( $entry->{resourceIdentifier} && !$entry->{machineIdentifier} );
    my $type = ucfirst( $type );
    if( my $ignored = AttrVal($name, "ignored${type}s", '' ) ) {
      if( $ignored =~ m/\b$ip\b/ ) {
        Log3 $name, 5, "$name: ignoring $type $ip";
        return undef;

      } elsif( $entry->{machineIdentifier} && $ignored =~ m/\b$entry->{machineIdentifier}\b/ ) {
        Log3 $name, 5, "$name: ignoring $type $entry->{machineIdentifier}";
        return undef;

      }
    }

    $entries->{$ip} = $entry;
    $entries->{$ip}{online} = 1;

  } else {
    @{$entries->{$ip}}{ keys %{$entry} } = values %{$entry};

  }
  $entry = $entries->{$ip};

  $entry->{address} = $ip;
  $entry->{updatedAt} = gettimeofday();

  if( $type eq 'client' &&  $entry->{machineIdentifier} ) {
    if( my $chash = $modules{plex}{defptr}{$entry->{machineIdentifier}} ) {
      readingsBeginUpdate($chash);
      readingsBulkUpdate($chash, 'presence', 'present' ) if( ReadingsVal($chash->{NAME}, 'presence', '') ne 'present' );
      readingsBulkUpdate($chash, 'state', 'appeared' ) if( ReadingsVal($chash->{NAME}, 'state', '') eq 'disappeared' );
      readingsEndUpdate($chash, 1);

      #$chash->{name} = $entry->{name};
      $chash->{product} = $entry->{product};
      $chash->{version} = $entry->{version};
      $chash->{platform} = $entry->{platform};
      $chash->{deviceClass} = $entry->{deviceClass};
      $chash->{platformVersion} = $entry->{platformVersion};
      $chash->{protocolCapabilities} = $entry->{protocolCapabilities};
    }
  }

  if( $type eq 'server' ) {
    Log3 $name, 3, "$name: $type discovered: $ip" if( $new );

    if( $new && $entry->{port} ) {
      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/clients", "clients" );
    }

    plex_requestNotifications( $hash, $entry );

  } elsif( $type eq 'client' ) {
    Log3 $name, 3, "$name: $type discovered: $ip" if( $new );

    if( $new && $entry->{port} ) {
      plex_sendApiCmd( $hash, "http://$ip:$entry->{port}/resources", "resources" );
    }

  } else {
    Log3 $name, 2, "$name: discovered unknown type: $type";

  }
}
sub
plex_disappeared($$$)
{
  my ($hash, $type, $ip) = @_;
  my $name = $hash->{NAME};

  if( !$type ) {
    $type = 'server' if( $hash->{servers}{$ip} || ($hash->{server} && $hash->{server} eq $ip) );
    $type = 'client' if( $hash->{clients}{$ip} || ($hash->{client} && $hash->{client} eq $ip) );

    return undef if( !$type );
  }

  $hash->{$type.'s'} = {} if( !$hash->{$type.'s'} );

  my $entries = $hash->{$type.'s'};
  my $new;
     $new = 1 if( !$entries->{$ip} || $entries->{$ip}{online} );

  $entries->{$ip} = {} if( !$entries->{$ip} );
  $entries->{$ip}{online} = 0;

  my $machineIdentifier = $entries->{$ip}{machineIdentifier};
  if( $type eq 'client' && $new && $machineIdentifier ) {
    delete $hash->{subscriptionsFrom}{$machineIdentifier};
    if( my $chash = $hash->{helper}{subscriptionsFrom}{$machineIdentifier} ) {
      plex_closeSocket( $chash );
      delete($defs{$chash->{NAME}});

      delete $hash->{helper}{subscriptionsFrom}{$machineIdentifier};
    }

    if( my $chash = $modules{plex}{defptr}{$machineIdentifier} ) {
      delete $chash->{controllable};
      delete $chash->{currentMediaType};

      readingsBeginUpdate($chash);
      readingsBulkUpdate($chash, 'presence', 'absent' );
      readingsBulkUpdate($chash, 'state', 'disappeared' );
      readingsEndUpdate($chash, 1);

      CommandDeleteReading( undef, "$chash->{NAME} currentTitle|currentAlbum|currentArtist|episode|series|key|cover|duration|type|track|playQueueID|playQueueItemID|server|section|shuffle|repeat" ) if( AttrVal($chash->{NAME}, 'removeUnusedReadings', 0 ) );

    }
  }

  if( $type eq 'server' ) {
    Log3 $name, 3, "$name: $type disappeared: $ip" if( $new );

  } elsif( $type eq 'client' ) {
    Log3 $name, 3, "$name: $type disappeared: $ip" if( $new );

    plex_removeSubscription($hash->{helper}{timelineListener}, $ip);

  } else {
    Log3 $name, 2, "$name: unknown type $type disappeared";

  }
}
sub
plex_requestNotifications($$)
{
  my ($hash,$server) = @_;
  my $name = $hash->{NAME};

  return if( $hash->{helper}{websockets}{$server->{machineIdentifier}} );

  if( my $socket = IO::Socket::INET->new(PeerAddr=>"$server->{address}:$server->{port}", Timeout=>2, Blocking=>1, ReuseAddr=>1) ) {

    my $chash = plex_newChash( $hash, $socket,
                               {NAME=>"$name:websocket:$server->{machineIdentifier}", STATE=>'listening', websocket=>0} );

    $chash->{address} = $server->{address};
    $chash->{machineIdentifier} = $server->{machineIdentifier};

    Log3 $name, 3, "$name: notification websocket opened to $server->{address}";

    $hash->{helper}{websockets}{$server->{machineIdentifier}} = $chash;


    my $ret = "GET /:/websockets/notifications HTTP/1.1\r\n";
    $ret .= plex_hash2header( {                       'Host' => "$server->{address}:$server->{port}",
                                              'X-Plex-Token' => $server->{accessToken}?$server->{accessToken}:$hash->{token},
                                                   'Upgrade' => 'websocket',
                                                'Connection' => 'Upgrade',
                                                    'Pragma' => 'no-cache',
                                             'Cache-Control' => 'no-cache',
                                         'Sec-WebSocket-Key' => 'RkhFTQ==',
                                     'Sec-WebSocket-Version' => '13',
                                } );

    $ret .= "\r\n";
#Log 1, $ret;

    syswrite($chash->{CD}, $ret );

  } else {
    Log3 $name, 2, "$name: failed to open notification websocket to $server->{address}";

  }
}
sub
plex_closeNotifications($)
{
  my ($hash,$server) = @_;
  my $name = $hash->{NAME};
}
sub
plex_stopWebsockets($)
{
  my ($hash,$server) = @_;
  my $name = $hash->{NAME};

  return if( !$hash->{helper}{websockets} );

  foreach my $key ( keys %{$hash->{helper}{websockets}} ) {
    my $chash = $hash->{helper}{websockets}{$key};
    my $cname = $chash->{NAME};

    plex_closeSocket($chash);

    delete($hash->{servers}{$chash->{address}}{sessions});
    delete($hash->{helper}{websockets}{$key});
    delete($defs{$cname});
  }

  Log3 $name, 3, "$name: websockets stoped";
}

sub
plex_readingsBulkUpdateIfChanged($$$)
{
  my ($hash,$reading,$value) = @_;
  readingsBulkUpdate($hash, $reading, $value ) if( defined($value) && $value ne ReadingsVal($hash->{NAME}, $reading, '') );
}

sub
plex_parseTimeline($$$)
{
  my ($hash,$id,$xml) = @_;
  my $name = $hash->{NAME};

  if( !$id ) {
    Log3 $name, 2, "$name: can't parse timeline for unknown device";

    return undef if( !$id );
  }

  my $chash = $modules{plex}{defptr}{$id};
  if( !$chash ) {
    my $cname = $id;
    $cname =~ s/-//g;
    my $define = "$cname plex $id";

    if( my $cmdret = CommandDefine(undef,$define) ) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";

      return undef;
    }
    CommandAttr(undef, "$cname room plex");
    if( my $entry = plex_entryOfID($hash, 'client', $id ) ) {
      CommandAttr(undef, "$cname alias ".$entry->{name});
      #CommandAttr(undef, "$cname alias ".$entry->{product});
    }

    $chash = $modules{plex}{defptr}{$id};
  }

  readingsBeginUpdate($chash);
  plex_readingsBulkUpdateIfChanged($chash, 'location', $xml->{location} );
  my $state;
  my $entries;
  delete $chash->{time};
  delete $chash->{seekRange};
  delete $chash->{controllable};
  foreach my $entry (@{$xml->{Timeline}}) {
    next if( !$entry->{state} );

    my $key = $entry->{key};
    if( $key && $key ne ReadingsVal($chash->{NAME}, 'key', '') ) {
      $chash->{currentServer} = $entry->{machineIdentifier};

      readingsBulkUpdate($chash, 'key', $key );
      readingsBulkUpdate($chash, 'server', $entry->{machineIdentifier} );

      my $server = plex_entryOfID($hash, 'server', $entry->{machineIdentifier} );
      $server = $entry if( !$server );
      plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}$key", "#update:$chash->{NAME}" );
    }

    plex_readingsBulkUpdateIfChanged($chash, 'volume', $entry->{volume} ) if( $entry->{controllable} && $entry->{controllable} =~ m/\bvolume\b/ );

    $chash->{controllable} = $entry->{controllable} if( $entry->{controllable} );

    if( $entry->{type} ) {
      $entries->{ $entry->{type} } = $entry;
    }

    my $time = $entry->{time};
    if( defined($time) ) {
#      if( !$chash->{helper}{time} || abs($time - $chash->{helper}{time}) > 2000 ) {
#        plex_readingsBulkUpdateIfChanged($chash, 'time', plex_sec2hms($time/1000) );
#
#        $chash->{helper}{time} = $time;
#      }
      $chash->{time} = $time;
    }

    $chash->{seekRange} = $entry->{seekRange} if( $entry->{seekRange} && $entry->{seekRange} ne "0-0" );

    $state .= ' ' if( $state );
    $state .= "$entry->{type}:$entry->{state}";

    #$state = undef if( $state && $entry->{continuing} );
  }
  $state = 'stopped' if( !$state );
  $state = $1 if( $state =~ /^[\w]*:(stopped)$/ );
  if( $state =~ '\w*:(\w*) \w*:(\w*) .*:(\w*)' ) {
    $state = $1 if( $1 eq $2 && $2 eq $3 );
  }

  if( $state =~ '(\w*):(playing|paused)' ) {
    $chash->{currentMediaType} = $1;
    if( defined($entries->{$1}) ) {
      $chash->{controllable} = $entries->{$1}->{controllable} if ( defined($entries->{$1}->{controllable}) );

      plex_readingsBulkUpdateIfChanged($chash, 'repeat', $entries->{$1}->{repeat} );
      plex_readingsBulkUpdateIfChanged($chash, 'shuffle', $entries->{$1}->{shuffle} );
      plex_readingsBulkUpdateIfChanged($chash, 'playQueueID', $entries->{$1}->{playQueueID} );
      plex_readingsBulkUpdateIfChanged($chash, 'playQueueItemID', $entries->{$1}->{playQueueItemID} );
    }

  } else {
    delete $chash->{currentMediaType};

    #FIXME: move after stop event
    CommandDeleteReading( undef, "$chash->{NAME} currentTitle|currentAlbum|currentArtist|episode|series|key|cover|duration|type|track|playQueueID|playQueueItemID|server|section|shuffle|repeat" ) if( AttrVal($chash->{NAME}, 'removeUnusedReadings', 0 ) );

  }

  plex_readingsBulkUpdateIfChanged($chash, 'state', $state );
  readingsEndUpdate($chash, 1);
}
sub
plex_getDataForSMAPI($$$)
{
  my ($hash,$server,$key) = @_;
  my $name = $hash->{NAME};

  my ($seconds) = gettimeofday();
  foreach my $key ( keys %{$hash->{helper}{SMAPIcache}} ) {
    delete $hash->{helper}{SMAPIcache}{$key} if( $seconds - $hash->{helper}{SMAPIcache}{$key}{timestamp} > 10 );
  }

  my $xml;
  if( !$hash->{helper}{SMAPIcache}{$key} ) {
Log 1, "get: $key";
    if( $key =~ m'^/library' ) {
      $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}$key", '#raw', 1 );

    } else {
      $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}/library/sections$key", '#raw', 1 );

      return undef if( !$xml || ref($xml) ne 'HASH' );
      if( $key eq '' && $xml->{Directory} ) {
        my $section;
        foreach my $item (@{$xml->{Directory}}) {
          if( $item->{type} && $item->{type} eq 'artist' ) {
            if( $section ) {
              $section = undef;
              last;
            } else {
              $section = $item->{key};
            }
          }
        }

        if( $section ) {
          Log3 $name, 4, "$name: found only one music section, using this as root";
          $xml = plex_sendApiCmd( $hash, "http://$server->{address}:$server->{port}/library/sections/$section", '#raw', 1 );

        } else {
          Log3 $name, 4, "$name: found multiple music sections";

        }
      }
    }

    return undef if( !$xml || ref($xml) ne 'HASH' );
    if( $xml->{Directory} ) {
      for(my $i = int(@{$xml->{Directory}}); $i >= 0; --$i) {
        my $item = $xml->{Directory}[$i];

        # at the toplevel only care about music sections
        if( !$key && $item->{type} && $item->{type} ne 'artist' ) {
          splice @{$xml->{Directory}}, $i, 1;
          --$xml->{size};
          next;
        }
        # ignore search nodes
        if( $item->{key} =~ /^search/ ) {
          splice @{$xml->{Directory}}, $i, 1;
          --$xml->{size};
          next;
        }
      }
    }

    my ($seconds) = gettimeofday();
    $hash->{helper}{SMAPIcache}{$key} = { value => $xml, timestamp => $seconds };

  } else {
Log 1, "cached: $key";

    my ($seconds) = gettimeofday();
    $hash->{helper}{SMAPIcache}{$key}{value}{timestamp} = $seconds;

    $xml = $hash->{helper}{SMAPIcache}{$key}{value}
  }
  Log3 $name, 5, "$name: got:". Dumper $xml;

  return $xml;
}
sub
plex_metadataResponseForSMAPI($$$$$)
{
  my ($hash,$request,$server,$key,$xml) = @_;
  my $name = $hash->{NAME};

  return undef if( !$request || ref($request) ne 'HASH' );
  return undef if( !$server || ref($server) ne 'HASH' );
  return undef if( !$xml || ref($xml) ne 'HASH' );

  my $type;
  if( $request->{getMetadata} ) {
    $type = 'getMetadata';
  } elsif( $request->{getExtendedMetadata} ) {
    $type = 'getExtendedMetadata';
  } else {
    return undef;
  }

  my $index = $request->{$type}{index};
  my $count = $request->{$type}{count};

  my $body;
  $body .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">';
  $body .= '  <s:Body>';
  $body .= '    <'.$type.'Response xmlns="http://www.sonos.com/Services/1.1">';
  $body .= '      <'.$type.'Result>';
  my $i = 0;
  my $total = $xml->{size};
  $total = 0 if( !$total );
  if( $xml->{Directory} ) {
    foreach my $item (@{$xml->{Directory}}) {
      if( $i < $index ) {
        ++$i;
        next;
      }

      my $title = $item->{titleSort};
      $title = $item->{title};# if( !$title );

      $title =~ s/&/&amp;/g;

      $body .= '<mediaCollection>';
      $body .= "  <title>$title</title>";
      $body .= "  <id>$item->{key}</id>" if( $item->{key} =~ '^/' );
      $body .= "  <id>$key/$item->{key}</id>" if( $item->{key} !~ '^/' );
      $body .= "  <albumArtURI>http://$server->{address}:$server->{port}$item->{thumb}</albumArtURI>" if( $item->{thumb} );
      $body .= '  <canScroll>true</canScroll>';
      if( $item->{type} eq 'album' ) {
        $body .= '<canPlay>true</canPlay>';
        $body .= '<itemType>album</itemType>';
      } elsif( $item->{type} eq 'artist' ) {
        $body .= '<canPlay>true</canPlay>';
        $body .= '<itemType>artist</itemType>';
      } elsif( $item->{type} eq 'genre' ) {
        $body .= '<canPlay>true</canPlay>';
        $body .= '<itemType>genre</itemType>';
      } else {
        $body .= '<itemType>collection</itemType>';
      }
      $body .= '</mediaCollection>';

      last if( ++$i >= $index + $count );
    }

  } elsif( $xml->{Track} ) {
    foreach my $item (@{$xml->{Track}}) {
      if( $i < $index ) {
        ++$i;
        next;
      }

      $item->{title} =~ s/&/&amp;/g;
      $item->{parentTitle} =~ s/&/&amp;/g;
      $item->{grandparentTitle} =~ s/&/&amp;/g;

      $body .= '<mediaMetadata>';
      $body .= "  <title>$item->{title}</title>";
      $body .= "  <id>$item->{key}</id>" if( $item->{key} =~ '^/' );
      $body .= "  <id>$key/$item->{key}</id>" if( $item->{key} !~ '^/' );
      $body .= '  <mimeType>audio/mp3</mimeType>';
      $body .= '  <itemType>track</itemType>';
      $body .= '  <trackMetadata>';
      $body .= "    <album>$item->{parentTitle}</album>";
      $body .= "    <albumId>$item->{parentKey}</albumId>";
      $body .= "    <artist>$item->{grandparentTitle}</artist>";
      $body .= "    <artistId>$item->{grandparentKey}</artistId>";
      $body .= "    <trackNumber>$item->{index}</trackNumber>";
      $body .= "    <duration>". int($item->{duration}/1000) ."</duration>";
      $body .= "    <albumArtURI>http://$server->{address}:$server->{port}$item->{parentThumb}</albumArtURI>" if( $item->{parentThumb} );
      $body .= '  </trackMetadata>';
      $body .= '</mediaMetadata>';

      last if( ++$i >= $index + $count );
    }
  }
  $body .= "        <total>$total</total>";
  $body .= "        <index>$index</index>";
  $body .= "        <count>". ($i-$index) ."</count>";
  $body .= '      </'.$type.'Result>';
  $body .= '    </'.$type.'Response>';
  $body .= '  </s:Body>';
  $body .= '</s:Envelope>';
#Log 1, $body;

  my $ret = "HTTP/1.1 200 OK\r\n";
  $ret .= plex_hash2header( {               'Connection' => 'Close',
                                          'Content-Type' => 'text/xml; charset=utf-8',
                                          'Content-Length' => length($body),
                            } );
  $ret .= "\r\n";
  $ret .= $body;

#Log 1, $ret;
  return $ret;
}
sub
plex_getScrollindicesForSMAPI($$)
{
  my ($hash,$xml) = @_;
  my $name = $hash->{NAME};

  my $indices ='';
  my $last;
  my $i = 0;
  if( $xml->{Directory} ) {
    foreach my $item (@{$xml->{Directory}}) {
      my $title = $item->{titleSort};
      $title = $item->{title} if( !$title );

      my $current = uc(substr($title, 0, 1));

      return '' if( $last && ord($last) > ord($current ) );

      if( $current =~ /[A-Z]/ && (!$last || $current ne $last) ) {
        $indices .= ',' if( $indices );
        $indices .= "$current,$i";

        $last = $current;
      }

      ++$i;
    }
  }

  return $indices;
}

sub
plex_handleSMAPI($$)
{
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  my $handled;

  my $server = plex_serverOf($hash, $hash->{machineIdentifier}, !$hash->{machineIdentifier});
  if( !$server ) {
    Log3 $name, 2, "$name: no server found for SMAPI request";
    return undef;
  }

  if( $msg =~ m/^(.*?)\r?\n\r?\n(.*)$/s ) {
    my $header = $1;
    my $body = $2;
#Log 1, $header;
#Log 1, $body;

    if( my $xml = eval { XMLin( $body, KeyAttr => {}, ForceArray => 0 ); } ) {
      if( my $body = $xml->{'s:Body'} ) {
        Log3 $name, 4, "$name: got soap request:". Dumper $body;

        if( $body->{getMetadata} ) {
          $handled = 1;

#Log 1, Dumper $body;
          my $key = $body->{getMetadata}{id};
          $key = '' if( $key eq 'root' );
          $key = "/$key" if( $key && $key !~ '^/' );

          my $xml = plex_getDataForSMAPI($hash, $server, $key);
#Log 1, Dumper $xml;

          return plex_metadataResponseForSMAPI($hash, $body, $server, $key, $xml);

        } elsif( $body->{getExtendedMetadata} ) {
          $handled = 1;

#Log 1, Dumper $body;
          my $key = $body->{getExtendedMetadata}{id};
          $key = "" if( $key eq 'root' );
          $key = "/$key" if( $key && $key !~ '^/' );

          my $xml = plex_getDataForSMAPI($hash, $server, $key);

          return plex_metadataResponseForSMAPI($hash, $body, $server, $key, $xml);

        } elsif( $body->{getScrollIndices} ) {
          $handled = 1;

          if( my $key = $body->{getScrollIndices}{id} ) {
            $key = "/$key" if( $key && $key !~ '^/' );

            my $xml = plex_getDataForSMAPI($hash, $server, $key);
            return undef if( !$xml || ref($xml) ne 'HASH' );

            my $body;
            $body .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">';
            $body .= '  <s:Body>';
            $body .= '    <getScrollIndicesResponse xmlns="http://www.sonos.com/Services/1.1">';
            $body .= '      <getScrollIndicesResult>';
            $body .=          plex_getScrollindicesForSMAPI($hash,$xml);
            $body .= '      </getScrollIndicesResult>';
            $body .= '    </getScrollIndicesResponse>';
            $body .= '  </s:Body>';
            $body .= '</s:Envelope>';

            my $ret = "HTTP/1.1 200 OK\r\n";
            $ret .= plex_hash2header( {               'Connection' => 'Close',
                                                    'Content-Type' => 'text/xml; charset=utf-8',
                                                  'Content-Length' => length($body),
                                      } );
            $ret .= "\r\n";
            $ret .= $body;

#Log 1, $ret;
            return $ret;
          }

        } elsif( $body->{getMediaMetadata} ) {
          $handled = 1;

          if( my $key = $body->{getMediaMetadata}{id} ) {
            $key = "/$key" if( $key && $key !~ '^/' );

            my $xml = plex_getDataForSMAPI($hash, $server, $key);
            return undef if( !$xml || ref($xml) ne 'HASH' );

            my $body;
            $body .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">';
            $body .= '  <s:Body>';
            $body .= '    <getMediaMetadataResponse xmlns="http://www.sonos.com/Services/1.1">';
            $body .= '      <getMediaMetadataResult>';
            if( $xml->{Track} ) {
              foreach my $item (@{$xml->{Track}}) {
                $item->{title} =~ s/&/&amp;/g;
                $item->{parentTitle} =~ s/&/&amp;/g;
                $item->{grandparentTitle} =~ s/&/&amp;/g;

                $body .= "<title>$item->{title}</title>";
                $body .= "<id>$item->{key}</id>" if( $item->{key} =~ '^/' );
                $body .= "<id>$key/$item->{key}</id>" if( $item->{key} !~ '^/' );
                $body .= '<mimeType>audio/mp3</mimeType>';
                $body .= '<itemType>track</itemType>';
                $body .= '<trackMetadata>';
                $body .= "  <album>$item->{parentTitle}</album>";
                $body .= "  <albumId>$item->{parentKey}</albumId>";
                $body .= "  <artist>$item->{grandparentTitle}</artist>";
                $body .= "  <artistId>$item->{grandparentKey}</artistId>";
                $body .= "  <trackNumber>$item->{index}</trackNumber>";
                $body .= "  <duration>". int($item->{duration}/1000) ."</duration>";
                $body .= "  <albumArtURI>http://$server->{address}:$server->{port}$item->{parentThumb}</albumArtURI>" if( $item->{parentThumb} );
                $body .= '</trackMetadata>';
              }
            }
            $body .= '      </getMediaMetadataResult>';
            $body .= '    </getMediaMetadataResponse>';
            $body .= '  </s:Body>';
            $body .= '</s:Envelope>';

            my $ret = "HTTP/1.1 200 OK\r\n";
            $ret .= plex_hash2header( {               'Connection' => 'Close',
                                                    'Content-Type' => 'text/xml; charset=utf-8',
                                                  'Content-Length' => length($body),
                                      } );
            $ret .= "\r\n";
            $ret .= $body;

#Log 1, $ret;
            return $ret;
          }

        } elsif( $body->{getMediaURI} ) {
          $handled = 1;

          if( my $key = $body->{getMediaURI}{id} ) {
            my $xml = plex_getDataForSMAPI($hash, $server, $key);
            return undef if( !$xml || ref($xml) ne 'HASH' );

            my $body;
            $body .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">';
            $body .= '  <s:Body>';
            $body .= '    <getMediaURIResponse xmlns="http://www.sonos.com/Services/1.1">';
            $body .= '      <getMediaURIResult>';
            if( $xml->{Track} ) {
              foreach my $item (@{$xml->{Track}}) {
                if( $item->{Media} && $item->{Media}[0]{Part}  ) {
                  $body .= "http://$server->{address}:$server->{port}$item->{Media}[0]{Part}[0]{key}";
                  #$body .= "&X-Plex-Token=$hash->{token}" if( $hash->{token} );
                  last;
                }
              }
            }
            $body .= '      </getMediaURIResult>';
            if( $hash->{token} ) {
              $body .= '<httpHeaders>';
              $body .= '  <httpHeader>';
              $body .= '    <header>X-Plex-Token</header>';
              $body .= "    <value>$hash->{token}</value>";
              $body .= '  </httpHeader>';
              $body .= '</httpHeaders>';
            }
            $body .= '    </getMediaMetadataResponse>';
            $body .= '  </s:Body>';
            $body .= '</s:Envelope>';

            my $ret = "HTTP/1.1 200 OK\r\n";
            $ret .= plex_hash2header( {               'Connection' => 'Close',
                                                    'Content-Type' => 'text/xml; charset=utf-8',
                                                  'Content-Length' => length($body),
                                      } );
            $ret .= "\r\n";
            $ret .= $body;

#Log 1, $ret;
            return $ret;
          }

        } elsif( $body->{getLastUpdate} ) {
          $handled = 1;

          my ($seconds) = gettimeofday();
          my $body;
          $body .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">';
          $body .= '  <s:Body>';
          $body .= '    <getLastUpdateResponse xmlns="http://www.sonos.com/Services/1.1">';
          $body .= '      <getLastUpdateResult>';
          $body .= "        <catalog>$seconds</catalog>";
          $body .= '        <favorites></favorites>';
          $body .= '        <pollInterval>120</pollInterval>';
          $body .= '      </getLastUpdateResult>';
          $body .= '    </getLastUpdateResponse>';
          $body .= '  </s:Body>';
          $body .= '</s:Envelope>';

          my $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {               'Connection' => 'Close',
                                                  'Content-Type' => 'text/xml; charset=utf-8',
                                                'Content-Length' => length($body),
                                    } );
          $ret .= "\r\n";
          $ret .= $body;

#Log 1, $ret;
          return $ret;
        }

        Log3 $name, 2, "$name: unhandled soap request:". Dumper $body if( !$handled );

        return undef;
      }
    }
  }

  Log3 $name, 2, "$name: unhandled message: $msg" if( !$handled );

  return undef;
}
sub
plex_Parse($$;$$$)
{
  my ($hash,$msg,$peerhost,$peerport,$sockport) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: from: $peerhost" if( $peerhost );
  Log3 $name, 5, "$name: $msg";

  my $handled = 0;
  if( $peerhost ) { #from broadcast
    if( $msg =~ '^HTTP/1.\d 200 OK' ) {
      my $params = plex_msg2hash($msg);
      if( $params->{'contentType'} eq 'plex/media-server' ) {
        $handled = 1;
        plex_discovered($hash, 'server', $peerhost, $params );

      } elsif( $params->{'contentType'} eq 'plex/media-player' ) {
        return undef if( $peerhost eq $hash->{fhemIP} && $hash->{clients}{$peerhost}{online} );
        $handled = 1;
        plex_discovered($hash, 'client', $peerhost, $params );

      }

    } elsif( $msg =~ '^([\w\-]+) \* HTTP/1.\d' ) {
      my $type = $1;
      my $params = plex_msg2hash($msg);

      if( $type eq 'HELLO' ) {
        $handled = 1;
        plex_discovered($hash, 'client', $peerhost, $params );

      } elsif( $type eq 'BYE' ) {
        plex_disappeared($hash, 'client', $peerhost );
        $handled = 1;

      } elsif( $type eq 'UPDATE' ) {
        if( $params->{parameters} =~ m/playerAdd=(.*)/ ) {
          $handled = 1;

          my $ip = $peerhost;
          if( $hash->{servers}{$ip}{port} ) {
            plex_sendApiCmd( $hash, "http://$ip:$hash->{servers}{$ip}{port}/clients", "clients" );
          }

        } elsif( $params->{parameters} =~ m/playerDel=(.*)/ ) {
          my $ip = $1;
          $handled = 1;
          if( !$hash->{clients}{$ip} || $hash->{clients}{$ip}{product} ne 'Plex Home Theater' ) {
            plex_disappeared($hash, 'client', $ip );
          }

        }

      } elsif( $type eq 'M-SEARCH' ) {
        $handled = 1;
        if( $peerhost eq $hash->{fhemIP} && $hash->{clients}{$peerhost}{online} ) {
          if( $hash->{helper}{discoverClientsMcast} && $hash->{helper}{discoverClientsMcast}->{CD}->sockport() == $peerport ) {
            #Log3 $name, 5, "$name: ignoring multicast M-Search from self ($peerhost:$peerport)";
            return undef;
          }

          if( $hash->{helper}{discoverClientsBcast} && $hash->{helper}{discoverClientsBcast}->{CD}->sockport() == $peerport ) {
            #Log3 $name, 5, "$name: ignoring broadcast M-Search from self ($peerhost:$peerport)";
            return undef;
          }
        }

        #Log3 $name, 5, "$name: received from: $peerhost:$peerport to $sockport: $msg";

        my $msg = "HTTP/1.0 200 OK\r\n";
        $msg .= plex_hash2header( {          'Content-Type' => 'plex/media-player',
                                      'Resource-Identifier' => $hash->{id},
                                                     'Name' => $hash->{fhemHostname},
                                                     #'Host' => $hash->{fhemIP},
                                                     'Port' => $hash->{helper}{timelineListener}{PORT},
                                               #'Updated-At' => 1447614540,
                                                  'Product' => 'FHEM SONOS Proxy',
                                                  'Version' => '0.0.0',
                                                 #'Protocol' => 'plex',
                                         'Protocol-Version' => 1,
                                    'Protocol-Capabilities' => 'playback,timeline', } );
        $msg .= "\r\n";

        my $sin = sockaddr_in($peerport, inet_aton($peerhost));
        $hash->{helper}{clientDiscoveryResponderMcast}->{CD}->send($msg, 0, $sin );

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

      $header = plex_msg2hash($header, 1);

      my $ret;
      if( $request =~ m'^/resources' ) {
        $handled = 1;
        Log3 $name, 4, "$name: answering $request";

        my $xml = { MediaContainer => [ {Player => {                title => $hash->{fhemHostname},
                                                                 protocol => 'plex',
                                                          protocolVersion =>'1',
                                                     protocolCapabilities => 'playback,timeline,skipNext,skipPrevious',
                                                        machineIdentifier => $hash->{id},
                                                                  product => 'FHEM SONOS Proxy',
                                                                 platform => $^O,
                                                          platformVersion => '0.0.0',
                                                              deviceClass => 'pc',
                                                           deviceProtocol => 'sonos' } }] };

        my $body = '<?xml version="1.0" encoding="utf-8" ?>';
        $body .= "\n";
        $body .= XMLout( $xml, KeyAttr => { }, RootName => undef );

        $ret = "HTTP/1.1 200 OK\r\n";
        $ret .= plex_hash2header( {               'Connection' => 'Close',
                                    'X-Plex-Client-Identifier' => $hash->{id},
                                                'Content-Type' => 'text/xml;charset=utf-8',
                                              'Content-Length' => length($body), } );
        $ret .= "\r\n";
        $ret .= $body;
      }

      my $entry = plex_entryOfID($hash, 'client', $header->{'X-Plex-Client-Identifier'} );

      if( $entry ) {
        my $addr = "$entry->{address}:$entry->{port}";
        if( $request =~ m'^/player/timeline/subscribe' ) {
          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          $hash->{subscriptionsFrom}{$header->{'X-Plex-Client-Identifier'}} = $addr;

          plex_sendTimelines($hash, $params->{commandID});

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {               'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        } elsif( $request =~ m'^/player/timeline/unsubscribe' ) {
          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          delete $hash->{subscriptionsFrom}{$header->{'X-Plex-Client-Identifier'}};
          if( my $chash = $hash->{helper}{subscriptionsFrom}{$header->{'X-Plex-Client-Identifier'}} ) {
            plex_closeSocket( $chash );
            delete($defs{$chash->{NAME}});

            delete $hash->{helper}{subscriptionsFrom}{$header->{'X-Plex-Client-Identifier'}};
          }

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {               'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        } elsif( $request =~ m'^/player/mirror/details' ) {
          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          if( my $chash = $hash->{helper}{subscriptionsFrom}{$header->{'X-Plex-Client-Identifier'}} ) {
            $chash->{commandID} = $params->{commandID};
          }

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {              'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        } elsif( $request =~ m'^/player/playback/playMedia' ) {

          delete $hash->{sonos}{playqueue};
          delete $hash->{sonos}{containerKey} ;
          delete $hash->{sonos}{machineIdentifier};

          my $entry = plex_entryOfID($hash, 'server', $params->{machineIdentifier} );
          if( $params->{containerKey} ) {
            my ($containerKey) = split( '\?', $params->{containerKey}, 2 );
            return "HTTP/1.1 400 Bad Request\r\n\r\n" if( !$containerKey);
            my $xml = plex_sendApiCmd( $hash, "http://$entry->{address}:$entry->{port}$containerKey", '#raw', 1 );
            return undef if( !$xml || ref($xml) ne 'HASH' );

            $hash->{sonos}{playqueue} = $xml;
            $hash->{sonos}{containerKey} = $containerKey;

          } elsif( my $key = $params->{key} ) {
            my $xml = plex_sendApiCmd( $hash, "http://$entry->{address}:$entry->{port}$key", '#raw', 1 );
            return undef if( !$xml || ref($xml) ne 'HASH' || !$xml->{Track} );

            $hash->{sonos}{playqueue} = ();
            $hash->{sonos}{playqueue}{size} = 1;

            $hash->{sonos}{playqueue}{Track} = $xml->{Track};

          }

          $hash->{sonos}{machineIdentifier} = $params->{machineIdentifier};
          $hash->{sonos}{currentTrack} = 0;
          $hash->{sonos}{updateTime} = time();
          $hash->{sonos}{currentTime} = 0;
          $hash->{sonos}{status} = 'playing';

          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          my $tracks = $hash->{sonos}{playqueue}{Track};
          my $track = $tracks->[$hash->{sonos}{currentTrack}];
          my $server = plex_entryOfID($hash, 'server', $hash->{sonos}{machineIdentifier});
          fhem( "set sonos_Esszimmer playURI http://$server->{address}:$server->{port}$track->{Media}[0]{Part}[0]{key}" );

          plex_sendTimelines($hash, $params->{commandID});

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {               'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        } elsif( $request =~ m'^/player/playback/setParameters' ) {
          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          plex_sendTimelines($hash, $params->{commandID});

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {               'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        } elsif( $request =~ m'^/player/playback/(\w*)' ) {
          my $cmd = $1;
          $handled = 1;
          Log3 $name, 4, "$name: answering $request";

          return "HTTP/1.1 400 Bad Request\r\n\r\n" if( !$hash->{sonos}{playqueue} );

if( $cmd eq 'play' ) {
  $cmd = 'playing';
  fhem( "set sonos_Esszimmer play" );

} elsif( $cmd eq 'pause' ) {
  $cmd = 'paused';
  fhem( "set sonos_Esszimmer pause" );

} elsif( $cmd eq 'stop' ) {
  $cmd = 'stopped' if( $cmd eq 'stop' );
  fhem( "set sonos_Esszimmer stop" );

} elsif( $cmd eq 'skipNext' ) {
  $cmd = 'playing';
  $hash->{sonos}{currentTrack}++;
  $hash->{sonos}{currentTrack} = 0 if( $hash->{sonos}{currentTrack} > $hash->{sonos}{playqueue}{size}-1 );
  $hash->{sonos}{updateTime} = time();
  $hash->{sonos}{currentTime} = 0;

          my $server = plex_entryOfID($hash, 'server', $hash->{sonos}{machineIdentifier});
          my $tracks = $hash->{sonos}{playqueue}{Track};
          my $track = $tracks->[$hash->{sonos}{currentTrack}];
          fhem( "set sonos_Esszimmer playURI http://$server->{address}:$server->{port}$track->{Media}[0]{Part}[0]{key}" );

} elsif( $cmd eq 'skipPrevious' ) {
  $cmd = 'playing';
  if( $hash->{sonos}{currentTime} < 10 ) {
    $hash->{sonos}{currentTrack}--;
    $hash->{sonos}{currentTrack} = $hash->{sonos}{playqueue}{size} - 1 if( $hash->{sonos}{currentTrack} < 0 );

          my $server = plex_entryOfID($hash, 'server', $hash->{sonos}{machineIdentifier});
          my $tracks = $hash->{sonos}{playqueue}{Track};
          my $track = $tracks->[$hash->{sonos}{currentTrack}];
          fhem( "set sonos_Esszimmer playURI http://$server->{address}:$server->{port}$track->{Media}[0]{Part}[0]{key}" );
  }

  $hash->{sonos}{updateTime} = time();
  $hash->{sonos}{currentTime} = 0;

} elsif( $cmd eq 'seekTo' ) {
  $cmd = $hash->{sonos}{status};
  $hash->{sonos}{updateTime} = time();
  $hash->{sonos}{currentTime} = int($params->{offset} / 1000);

  fhem( "set sonos_Esszimmer currentTrackPosition ". plex_sec2hms(int($params->{offset} / 1000) ) );
}
$hash->{sonos}{updateTime} = time() if( $cmd eq 'playing' && $hash->{sonos}{status} ne 'playing' );
$hash->{sonos}{status} = $cmd;

          plex_sendTimelines($hash, $params->{commandID});

          $ret = "HTTP/1.1 200 OK\r\n";
          $ret .= plex_hash2header( {                'Connection' => 'Close',
                                      'X-Plex-Client-Identifier' => $hash->{id},
                                                  'Content-Type' => 'text/xml;charset=utf-8',
                                                'Content-Length' => 0, } );
          $ret .= "\r\n";

        }
      }

      if( !$handled ) {
        $peerhost = $peerhost ? " from $peerhost" : '';
        Log3 $name, 2, "$name: unhandled request: $msg";
      }

      return $ret;

    }

  } elsif( $msg =~ '^POST /:/timeline\?? HTTP/1.\d' ) {
#Log 1, $msg;

    if( $msg =~ m/^(.*?)\r?\n\r?\n(.*)$/s ) {
      my $header = $1;
      my $body = $2;

      if( !$body ) {
        $handled = 1;
        Log3 $name, 5, "$name: empty timeline received";

      } elsif( $body !~ m/^<.*>$/ms ) {
        $handled = 1;
        Log3 $name, 2, "$name: unknown timeline content: $body";

      } else {
        $handled = 1;
        my $header = plex_msg2hash($header, 1);
        my $id = $header->{'X-Plex-Client-Identifier'};
        if( !$id ) {
          my $entry = plex_entryOfIP($hash, 'client', $peerhost);
          $id = $entry->{machineIdentifier};
        }

#Log 1, ">>$body<<";
        my $xml = eval { XMLin( $body, KeyAttr => {}, ForceArray => 1 ); };
        Log3 $name, 2, "$name: xml error: $@" if( $@ );
        return undef if( !$xml );

        plex_parseTimeline($hash, $id, $xml);

      }
    }

  } elsif( $msg =~ '^POST /SMAPI HTTP/1.\d' ) {
    return plex_handleSMAPI($hash, $msg);

  }

  if( !$handled ) {
    $peerhost = $peerhost ? " from $peerhost" : '';
    Log3 $name, 2, "$name: unhandled message$peerhost: $msg";
  }

  return undef;
}
sub
plex_sec2hms($)
{
  my ($sec) = @_;

  my $s = $sec % 60;
  $sec = int( $sec / 60 );
  my $m = $sec % 60;
  $sec = int( $sec / 60 );
  my $h = $sec % 24;

  return sprintf("%02d:%02d:%02d", $h, $m, $s);
}
sub
plex_timestamp2date($)
{
  my @t = localtime(shift);

  return sprintf("%04d-%02d-%02d",
      $t[5]+1900, $t[4]+1, $t[3]);
}

sub
plex_parseHttpAnswer($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    if( $param->{key} eq 'publishToSonos' ) {
      if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
        asyncOutput( $param->{cl}, "SMAPI registration for $param->{player}: failed\n" );
      }

    } elsif( $err =~ m/Connection refused$/ || $err =~ m/timed out$/ || $err =~ m/empty answer received$/ ) {
      if( !$param->{retry} || $param->{retry} < 1 ) {
        ++$param->{retry};

        delete $param->{conn};
        Log3 $name, 4, "$name: http request ($param->{url}) failed: $err; retrying";
        if( $param->{url} =~ m/.player./ ) {
          ++$hash->{commandID};
          $param->{url} =~ s/commandID=\d*/commandID=$hash->{commandID}/;
        }
        Log3 $name, 5, "  ($param->{url})";
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+5, "HttpUtils_NonblockingGet", $param, 0);

        return;
      }

    }

    Log3 $name, 2, "$name: http request ($param->{url}) failed: $err";

    plex_disappeared($hash, undef, $param->{address} ) if( $param->{retry} );

    return undef;
    return $err;
  }

  Log3 $name, 5, "$name: received $data";
  return undef if( !$data );

  $data = encode('UTF-8', $data );
  if( $data =~ m/^<!DOCTYPE html>(.*)/ ) {
    if( $param->{key} eq 'tokenOfPin' ) {
      delete $hash->{PIN};
      delete $hash->{PIN_ID};
      delete $hash->{PIN_EXPIRES};

      Log3 $name, 2, "$name: PIN expired";

      return undef;
    }

    Log3 $name, 2, "$name: failed: $1";

    return undef;

  } elsif( $data =~ m/200 OK/ ) {
      Log3 $name, 5, "$name: http request ($param->{url}) received code : $data";

      return undef;

  } elsif( $data !~ m/^<.*>$/ms ) {
    Log3 $name, 2, "$name: http request ($param->{url}) unknown content: $data";

    return undef;
  }

#Log 1, $param->{url};
#Log 1, Dumper $xml;
  my $handled = 0;
#Log 1, $data;
  my $xml = eval { XMLin( $data, KeyAttr => {}, ForceArray => 1 ); };
  Log3 $name, 2, "$name: xml error: $@" if( $@ );
  return undef if( !$xml );

  if( $param->{key} eq 'token' ) {
    $handled = 1;

    $hash->{token} = $xml->{'authenticationToken'};
    readingsSingleUpdate($hash, '.token', $hash->{token}, 0 );
    CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

    Log3 $name, 3, "$name: got token from user/password";

    plex_sendApiCmd($hash, "https://plex.tv/pms/servers.xml", "myPlex:servers" );
    plex_sendApiCmd($hash, "https://plex.tv/devices.xml", "myPlex:devices" );

    #https://plex.tv/pms/resources.xml?includeHttps=1

  } elsif( $param->{key} eq 'getPinForToken' ) {
    $handled = 1;

    delete $hash->{PIN};
    delete $hash->{PIN_ID};
    delete $hash->{PIN_EXPIRES};

    $hash->{PIN} = $xml->{code}[0] if( $xml->{code} );
    $hash->{PIN_ID} = $xml->{id}[0]{content} if( $xml->{id} );
    $hash->{PIN_EXPIRES} = $xml->{'expires-at'}[0]{content} if( $xml->{'expires-at'} );

    Log3 $name, 2, "$name: PIN: $hash->{PIN}";

    #plex_sendApiCmd($hash, "https://plex.tv/pms/servers.xml", "myPlex:servers" );
    #plex_sendApiCmd($hash, "https://plex.tv/devices.xml", "myPlex:devices" );

    #https://plex.tv/pms/resources.xml?includeHttps=1

    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
      asyncOutput( $param->{cl}, "PIN: $hash->{PIN}\n" );

      plex_getTokenOfPin($hash);
    }

  } elsif( $param->{key} eq 'tokenOfPin' ) {
    $handled = 1;

    RemoveInternalTimer($hash, "plex_getTokenOfPin");

    if( $xml->{auth_token}[0] && !ref($xml->{auth_token}[0]) ) {
      delete $hash->{PIN};
      delete $hash->{PIN_ID};
      delete $hash->{PIN_EXPIRES};

      $hash->{token} = $xml->{auth_token}[0];
      readingsSingleUpdate($hash, '.token', $hash->{token}, 0 );
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

      Log3 $name, 3, "$name: got token from pin";

      plex_sendApiCmd($hash, "https://plex.tv/pms/servers.xml", "myPlex:servers" );
      plex_sendApiCmd($hash, "https://plex.tv/devices.xml", "myPlex:devices" );

    } else {

      InternalTimer(gettimeofday()+4, "plex_getTokenOfPin", $hash, 0);
    }

  } elsif( $param->{key} eq 'clients' ) {
    $handled = 1;

    foreach my $entry (@{$xml->{Server}}) {
      #next if( $entry->{address} eq $hash->{fhemIP}
      #         && $hash->{helper}{timelineListener} && $hash->{helper}{timelineListener}->{PORT} == $entry->{port} );

      plex_discovered($hash, 'client', $entry->{address}, $entry);
    }

  } elsif( $param->{key} eq 'servers' ) {
    $handled = 1;
    foreach my $entry (@{$xml->{Server}}) {
      my $ip = $entry->{address};

      $ip = $param->{address} if( !$ip );
      $entry->{port} = $param->{port} if( !$entry->{port} );

      plex_discovered($hash, 'server', $ip, $entry);
    }

  } elsif( $param->{key} eq 'resources' ) {
    $handled = 1;
    foreach my $entry (@{$xml->{Server}}) {
      my $ip = $entry->{address};

      $ip = $param->{address} if( !$ip );
      $entry->{port} = $param->{port} if( !$entry->{port} );

      plex_discovered($hash, 'server', $ip, $entry);
    }

    foreach my $entry (@{$xml->{Player}}) {
      my $ip = $entry->{address};

      $ip = $param->{address} if( !$ip );
      $entry->{port} = $param->{port} if( !$entry->{port} );

      plex_discovered($hash, 'client', $ip, $entry);
      plex_sendSubscription($hash->{helper}{timelineListener}, $ip) if( $entry->{protocolCapabilities} && $entry->{protocolCapabilities} =~ m/timeline/);
    }

  } elsif( $param->{key} eq 'detail' ) {
    $handled = 1;

    my $server = plex_entryOfIP($hash, 'server', $param->{address});
    my $ret = plex_mediaDetail( $hash, $server, $xml );
#Log 1, Dumper $xml;
    if( $param->{cl} && $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
      $ret =~ s/&/&amp;/g;
      $ret =~ s/'/&apos;/g;
      $ret =~ s/\n/<br>/g;
      $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
      $ret = "<html>$ret</html>";
    } else {
      $ret =~ s/<a[^>]*>//g;
      $ret =~ s/<\/a>//g;
      $ret =~ s/<img[^>]*>\n//g;
      $ret .= "\n";
    }

    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
#Log 1, $ret;
      asyncOutput( $param->{cl}, $ret );

    } elsif( $param->{blocking} ) {
      return $ret;

    }

    return undef;

  } elsif( $param->{key} eq 'onDeck'
           || $param->{key} eq 'playlists'
           || $param->{key} eq 'recentlyAdded'
           || $param->{key} eq 'search'
           || $param->{key} =~ m'sections(:(\S*))?( (.*))?' ) {
    $handled = 1;
    my $cmd = $4;

    $xml->{parentSection} = $2;
    my $server = plex_entryOfIP($hash, 'server', $param->{address});
    my $ret = plex_mediaList( $hash, $server, $xml, $cmd );
    if( $param->{cl} && $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
      $ret =~ s/&/&amp;/g;
      $ret =~ s/'/&apos;/g;
      $ret =~ s/\n/<br>/g;
      $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
      $ret = "<html>$ret</html>";
    } else {
      $ret =~ s/<a[^>]*>//g;
      $ret =~ s/<\/a>//g;
      $ret =~ s/<img[^>]*>//g;
      $ret .= "\n";
    }

    if( $param->{cl} ) {
#Log 1, $ret;
      asyncOutput( $param->{cl}, $ret ."\n" );

    } elsif( $param->{blocking} ) {
      return $ret;

    }

    return undef;

  } elsif( $param->{key} eq 'playAlbum' ) {
    $handled = 1;
    my $client = $param->{client};
    my $server = $param->{server};
    my $queue = $xml->{playQueueID};
    my $key = $param->{album};
    my $url =  "http://$client->{address}:$client->{port}/player/playback/playMedia?key=$key&offset=0";
    $url .= "&machineIdentifier=$server->{machineIdentifier}&protocol=http&address=$server->{address}&port=$server->{port}";
    $url .= "&containerKey=/playQueues/$queue?own=1&window=200";
    plex_sendApiCmd( $hash, $url, "playback" );

  } elsif( $param->{key} eq 'timeline' ) {
    $handled = 1;
    my $id = $xml->{machineIdentifier};
    if( !$id ) {
      my $entry = plex_entryOfIP($hash, 'client', $param->{address});
      $id = $entry->{machineIdentifier};
    }
    plex_parseTimeline($hash, $id, $xml);

  } elsif( $param->{key} eq 'subscribe' ) {
    $handled = 1;
    my $id = $xml->{machineIdentifier};
    if( !$id ) {
      my $entry = plex_entryOfIP($hash, 'client', $param->{address});
      $id = $entry->{machineIdentifier};
    }
    #plex_parseTimeline($hash, $id, $xml);

  } elsif( $param->{key} =~ m/#update:(.*)/ ) {
    $handled = 1;
    my $chash = $defs{$1};
    return undef if( !$chash );

#Log 1, Dumper $xml;
#Log 1, Dumper $param;
    if( $xml->{librarySectionTitle} ne ReadingsVal($chash->{NAME}, 'section', '' ) ) {
      CommandDeleteReading( undef, "$chash->{NAME} currentAlbum|currentArtist|episode|series|track" );
    }

    readingsBeginUpdate($chash);
    plex_readingsBulkUpdateIfChanged($chash, 'section', $xml->{librarySectionTitle} );
    if( $xml->{Video} ) {
      foreach my $entry (@{$xml->{Video}}) {
        plex_readingsBulkUpdateIfChanged($chash, 'type', $entry->{type} );
        plex_readingsBulkUpdateIfChanged($chash, 'series', $entry->{grandparentTitle} );
        plex_readingsBulkUpdateIfChanged($chash, 'currentTitle', $entry->{title} );
        if( $entry->{parentThumb} ) {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{parentThumb}" );
        } elsif( $entry->{grandparentThumb} ) {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{grandparentThumb}" );
        } else {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{thumb}" );
        }
        plex_readingsBulkUpdateIfChanged($chash, 'episode', sprintf("S%02iE%02i",$entry->{parentIndex}, $entry->{index} ) ) if( $entry->{parentIndex} );

        if( !$chash->{duration} || $chash->{duration} != $entry->{duration} ) {
          $chash->{duration} = $entry->{duration};
          plex_readingsBulkUpdateIfChanged($chash, 'duration', plex_sec2hms($entry->{duration}/1000) );
        }
      }
    } elsif( $xml->{Track} ) {
      foreach my $entry (@{$xml->{Track}}) {
        plex_readingsBulkUpdateIfChanged($chash, 'type', $entry->{type} );
        plex_readingsBulkUpdateIfChanged($chash, 'currentArtist', $entry->{grandparentTitle} );
        plex_readingsBulkUpdateIfChanged($chash, 'currentAlbum', $entry->{parentTitle} );
        plex_readingsBulkUpdateIfChanged($chash, 'currentTitle', $entry->{title} );
        plex_readingsBulkUpdateIfChanged($chash, 'track', $entry->{index} );
        if( $entry->{parentThumb} ) {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{parentThumb}" );
        } elsif( $entry->{grandparentThumb} ) {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{grandparentThumb}" );
        } else {
          plex_readingsBulkUpdateIfChanged($chash, 'cover', "http://$param->{address}:$param->{port}$entry->{thumb}" );
        }

        if( !$chash->{duration} || $chash->{duration} != $entry->{duration} ) {
          $chash->{duration} = $entry->{duration};
          plex_readingsBulkUpdateIfChanged($chash, 'duration', plex_sec2hms($entry->{duration}/1000) );
        }
      }
    }
    readingsEndUpdate($chash, 1);

  } elsif( $param->{key} =~ m/myPlex:servers/ ) {
    $handled = 1;
    $hash->{'myPlex-servers'} = $xml;

    foreach my $server (@{$xml->{Server}}) {
      if( $hash->{server} && $server->{address} eq $hash->{server} )  {
        my $entry = $server;
        my $ip = $entry->{address};

        $ip = $param->{address} if( !$ip );
        $entry->{port} = $param->{port} if( !$entry->{port} );

        if( my $entry = plex_serverOf($hash, $entry->{machineIdentifier}, !$hash->{machineIdentifier}) ) {
          $entry->{address} = $server->{address};
          $entry->{port} = $server->{port};
        }

        #plex_discovered($hash, 'server', $ip, $entry);
      } elsif( my $entry = plex_entryOfID($hash, 'server', $server->{machineIdentifier} ) ) {
      }

      if( my $chash = $modules{plex}{defptr}{$server->{machineIdentifier}} ) {
      }
    }

  } elsif( $param->{key} =~ m/myPlex:devices/ ) {
    $handled = 1;
    $hash->{'myPlex-devices'} = $xml;

    foreach my $device (@{$xml->{Device}}) {
      if( my $entry = plex_entryOfID($hash, 'server', $device->{clientIdentifier} ) ) {
      }

      if( my $entry = plex_entryOfID($hash, 'client', $device->{clientIdentifier} ) ) {
      }

      if( my $chash = $modules{plex}{defptr}{$device->{clientIdentifier}} ) {
      }

    }

  } elsif( $param->{key} eq 'sessions' ) {
    $handled = 1;

    if( my $server = plex_serverOf($hash, $param->{host}) ) {
      delete $server->{sessions};
      foreach my $type ( keys %{$xml} ) {
        next if( ref($xml->{$type}) ne 'ARRAY' );

        foreach my $item (@{$xml->{$type}}) {
          $server->{sessions}{$item->{sessionKey}} = $item;
        }
      }
    }

  } elsif( $param->{key} =~ m/#m3u:(.*)/ ) {
    my $entry = plex_entryOfID($hash, 'server', $1);

    $handled = 1;

    my $items;
    $items = $xml->{Directory} if( $xml->{Directory} );
    $items =$xml->{Playlist} if( $xml->{Playlist} );
    $items = $xml->{Video} if( $xml->{Video} );
    $items = $xml->{Track} if( $xml->{Track} );

    my $artist = '';
    $artist = $xml->{grandparentTitle} if( $xml->{grandparentTitle} );
    my $album = '';
    $album = $xml->{parentTitle} if( $xml->{parentTitle} );

    my $ret = "#EXTM3U\n";
    if( $entry && $items ) {
      foreach my $item (@{$items}) {
        $ret .= '#EXTINF:'. int($item->{duration}/1000) .",$artist - $album - $item->{title}\n";
        if( $item->{Media} && $item->{Media}[0]{Part}  ) {
          $ret .= "http://$entry->{address}:$entry->{port}$item->{Media}[0]{Part}[0]{key}\n";
        }
      }
    }

    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
#Log 1, $ret;
      asyncOutput( $param->{cl}, $ret );

    } elsif( $param->{blocking} ) {
      return $ret;

    }

  } elsif( $param->{key} =~ m/#pls:(.*)/ ) {
    my $entry = plex_entryOfID($hash, 'server', $1);

    $handled = 1;

    my $items;
    $items = $xml->{Directory} if( $xml->{Directory} );
    $items =$xml->{Playlist} if( $xml->{Playlist} );
    $items = $xml->{Video} if( $xml->{Video} );
    $items = $xml->{Track} if( $xml->{Track} );

    my $artist = '';
    $artist = $xml->{grandparentTitle} if( $xml->{grandparentTitle} );
    my $album = '';
    $album = $xml->{parentTitle} if( $xml->{parentTitle} );

    my $ret = "[playlist]\n";
    if( $entry && $items ) {
      my $i = 0;
      foreach my $item (@{$items}) {
        ++$i;
        if( $item->{Media} && $item->{Media}[0]{Part}  ) {
          $ret .= "File$i=http://$entry->{address}:$entry->{port}$item->{Media}[0]{Part}[0]{key}\n";
        }
        $ret .= "Title$i=$artist - $album - $item->{title}\n";
        $ret .= "Length$i=". int($item->{duration}/1000) ."\n";
      }
      $ret .= "NumberOfEntries=". $i ."\n";
      $ret .= "Version=2\n";
    }

    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
#Log 1, $ret;
      asyncOutput( $param->{cl}, $ret );

    } elsif( $param->{blocking} ) {
      return $ret;

    }

  } elsif( $param->{key} eq 'publishToSonos' ) {
    $handled = 1;

    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
      asyncOutput( $param->{cl}, "SMAPI registration for $param->{player}: $xml->{body}[0]\n" );
    }

  } elsif( $param->{key} eq '#raw' ) {
    $handled = 1;

    return $xml if( $param->{blocking} );

  } elsif( $xml->{code} && $xml->{status} ) {
    $handled = 1;
    if( $xml->{code} == 200 ) {
      Log3 $name, 5, "$name: http request ($param->{url}) received code $xml->{code}: $xml->{status}";

    } else {
      Log3 $name, 2, "$name: http request ($param->{url}) received code $xml->{code}: $xml->{status}";

    }

  }

  if( !$handled ) {
    Log3 $name, 2, "$name: unhandled message '$param->{key}': ". Dumper $xml;
  }

  return $xml if( $param->{blocking} );
}

sub
plex_Read($)
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
    plex_Parse($phash, $buf, $peerhost, $peerport, $sockport);

  } elsif( $hash->{timeline} ) {
    $len = sysread($hash->{CD}, $buf, 10240);
#Log 1, "1:$len: $buf";
    my $peerhost = $hash->{CD}->peerhost;
    my $peerport = $hash->{CD}->peerport;

    if( !defined($len) || !$len ) {
      plex_closeSocket( $hash );
      delete($defs{$name});

      if( my $entry = plex_clientOf($hash->{phash}, $peerhost) ) {
        delete($hash->{phash}{helper}{subscriptionsFrom}{$entry->{machineIdentifier}});
      }

      return undef;
    }
#Log 1, "timeline ($peerhost:$peerport): $buf";

    return undef;

  } elsif( defined($hash->{websocket}) ) {
    my $pname = $hash->{PNAME} || $name;

    $len = sysread($hash->{CD}, $buf, 10240);
#Log 1, "2:$len: $buf";
    my $peerhost = $hash->{CD}->peerhost;
    my $peerport = $hash->{CD}->peerport;

    my $close = 0;
    if( !defined($len) || !$len ) {
      $close = 1;

    } elsif( $hash->{websocket} ) {
      $hash->{buf} .= $buf;

      do {
        my $fin = (ord(substr($hash->{buf},0,1)) & 0x80)?1:0;
        my $op = (ord(substr($hash->{buf},0,1)) & 0x0F);
        my $mask = (ord(substr($hash->{buf},1,1)) & 0x80)?1:0;
        my $len = (ord(substr($hash->{buf},1,1)) & 0x7F);
        my $i = 2;
        if( $len == 126 ) {
          $len = unpack( 'n', substr($hash->{buf},$i,2) );
          $i += 2;
        } elsif( $len == 127 ) {
          $len = unpack( 'N', substr($hash->{buf},$i+4,8) );
          $i += 8;
        }
        if( $mask ) {
          $i += 4;
        }
#Log 1, "$fin $op $mask $len";
        #FIXME: hande !$fin
        return if( $len > length($hash->{buf})-$i );

        my $data = substr($hash->{buf}, $i, $len);
        $hash->{buf} = substr($hash->{buf},$i+$len);
#Log 1, ">>>$data<<<";

        if( $data eq '?' ) {
          #ignore keepalive

        } elsif( $op == 0x01 ) {
          my $obj = eval { decode_json($data) };

          if( $obj ) {
            Log3 $pname, 5, "$pname: websocket data: ". Dumper $obj;

            my $phash = $hash->{phash};
            my $handled = 0;

            if( $obj->{NotificationContainer} ) {
              $obj = $obj->{NotificationContainer};
              if( $obj->{type} eq 'update.statechange' ) {
                $handled = 1;
                Log3 $pname, 4, "$pname: update available $obj->{AutoUpdateNotification}[0]{fixed}";
              }

            } elsif( $obj->{_elementType} && $obj->{_elementType} eq 'NotificationContainer' ) {
              if( $obj->{type} eq 'playing' ) {
                $handled = 1;

                my $cname;
                my $session_info_requested;

                if( my $session = $obj->{_children}[0]{sessionKey} ) {
                  if( my $server = plex_serverOf($phash, $peerhost) ) {
                    if( my $session = $server->{sessions}{$session} ) {
                      if( my $chash = $modules{plex}{defptr}{$session->{Player}[0]{machineIdentifier}} ) {
                        $cname = $chash->{NAME};
#Log 1, Dumper $obj;
                        readingsBeginUpdate($chash);
                        my $key = $obj->{_children}[0]{key};
                        if( $key && $key ne ReadingsVal($chash->{NAME}, 'key', '') ) {
                          $chash->{currentServer} = $server->{machineIdentifier};

                          readingsBulkUpdate($chash, 'key', $key );
                          readingsBulkUpdate($chash, 'server', $server->{machineIdentifier} );

                          plex_sendApiCmd( $phash, "http://$server->{address}:$server->{port}$key", "#update:$chash->{NAME}" );
                        }

                        my $time = $obj->{_children}[0]{viewOffset};
                        if( defined($time) ) {
#                          if( !$chash->{helper}{time} || abs($time - $chash->{helper}{time}) > 2000 ) {
#                            plex_readingsBulkUpdateIfChanged($chash, 'time', plex_sec2hms($time/1000) );
#
#                            $chash->{helper}{time} = $time;
#                          }
                          $chash->{time} = $time;
                        }

                        plex_readingsBulkUpdateIfChanged($chash, 'state', $obj->{_children}[0]{state} );
                        readingsEndUpdate($chash, 1);

                      } else {
                        Log3 $pname, 3, "$pname: unknown player: $session->{Player}[0]{machineIdentifier}";
                      }
                    } else {
                      Log3 $pname, 3, "$pname: new session $obj->{_children}[0]{sessionKey}";

                      $session_info_requested = 1;
                      plex_sendApiCmd( $phash, "http://$server->{address}:$server->{port}/status/sessions", 'sessions' );
                    }
                  }
                } else {
                  Log3 $pname, 3, "$pname: no session in notifcation ";
                }

                if( !$session_info_requested ) {
                  if( $obj->{_children}[0]{state} eq 'playing'
                      || $obj->{_children}[0]{state} eq 'stopped' ) {
                    if(  !$cname || $obj->{_children}[0]{key} ne ReadingsVal($cname, 'key', '' ) ) {
                      if( my $server = plex_serverOf($phash, $peerhost) ) {
                        plex_sendApiCmd( $phash, "http://$server->{address}:$server->{port}/status/sessions", 'sessions' );
                      }
                    }
                  }
                }

              } elsif( $obj->{type} eq 'status' ) {
                $handled = 1;
#Log 1, Dumper $obj;
               DoTrigger( $pname, "$obj->{_children}[0]{notificationName}: $obj->{_children}[0]{title}" );

              }
            }

            if( $obj->{type} ) {
              Log3 $pname, 4, "$pname: unhandled websocket text type: $obj->{type}: $data" if( !$handled );
            } else {
              Log3 $pname, 4, "$pname: unhandled websocket data: $data" if( !$handled );
            }

          } else {
            Log3 $pname, 2, "$pname: unhandled websocket text $data";

          }

        } else {
          Log3 $pname, 2, "$pname: unhandled websocket data: $data";

        }

      } while( $hash->{buf} && !$close );

    } elsif( $buf =~ m'^HTTP/1.1 101 Switching Protocols'i )  {
      $hash->{websocket} = 1;
      my $buf = plex_msg2hash($buf, 1);

      Log3 $pname, 3, "$pname: notification websocket: Switching Protocols ok";

    } else {
      $close = 1;
      Log3 $pname, 2, "$pname: notification websocket: Switching Protocols failed";
    }

    if( $close ) {
      my $phash = $hash->{phash};
      plex_closeSocket( $hash );
      delete($phash->{helper}{websockets}{$hash->{machineIdentifier}});
      delete($phash->{servers}{$hash->{address}}{sessions});
      delete($defs{$name});
    }

    return undef;

  } elsif ( $hash->{phash} ) {
    my $phash = $hash->{phash};
    my $pname = $hash->{PNAME};

    if( $phash->{helper}{timelineListener} == $hash ) {
      my @clientinfo = $hash->{CD}->accept();
      if( !@clientinfo ) {
        Log3 $name, 1, "Accept failed ($name: $!)" if($! != EAGAIN);
        return undef;
      }
      $hash->{CONNECTS}++;

      my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
      my $caddr = inet_ntoa($iaddr);

      my $chash = plex_newChash( $phash, $clientinfo[0],
                                 {NAME=>"$name:$port", STATE=>'listening'} );

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

            if( !$hash->{machineIdentifier} && $header =~ m/X-Plex-Client-Identifier:\s*(.*)/i ) {
              $hash->{machineIdentifier} = $1;
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
      $ret = plex_Parse($phash, $hash->{buf}) if( $hash->{buf} );

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

        if( $add_header ) {
          Log3 $pname, 5, "$name: add header: $add_header";
          syswrite($hash->{CD}, $add_header);
        }

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
        plex_closeSocket( $hash );

        delete($defs{$name});
        delete($hash->{phash}{helper}{timelineListener}{connections}{$hash->{NAME}});

        return;
      }

    } while( $hash->{buf} );

  }

  return undef;
}

sub
plex_publishToSonos(;$$$)
{
  my ($hash,$service,$player) = @_;
  $hash = $modules{plex}{defptr}{MASTER} if( !$hash && defined($modules{plex}{defptr}{MASTER}) );
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return 'no plex device found'  if( !$hash );
  my $name = $hash->{NAME};

  return 'no timeline listener started' if( !$hash->{helper}{timelineListener} );

  $service = 'PLEX' if( !$service );

  my $i = 0;
  foreach my $d (devspec2array("TYPE=SONOSPLAYER")) {
    next if( $player && $d !~ /$player/ );
    my $location = ReadingsVal($d,'location',undef);

    my $ip = ($location =~ m/https?:..([\d.]*)/)[0];
    next if( !$ip );

    my $url = "http://$ip:1400/customsd";

    Log3 $name, 4, "$name: requesting $url";

    my $fhem_base_url = "http://$hash->{fhemIP}:$hash->{helper}{timelineListener}{PORT}";

    my $data = plex_hash2form( { 'sid' => '246',
                                 'name' => $service,
                                 'uri' => "$fhem_base_url/SMAPI",
                                 'secureUri' => "$fhem_base_url/SMAPI",
                                 'pollInterval' => '1200',
                                 'authType' => 'Anonymous',
                                 'containerType' => 'MService',
                                 #'presentationMapVersion' => '1',
                                 #'presentationMapUri' => "$fhem_base_url/sonos/presentationMap.xml",
                                 #'stringsVersion' => '5',
                                 #'stringsUri' => "$fhem_base_url/sonos/strings.xml",
                               } );
    $data .= "&caps=search";
    $data .= "&caps=ucPlaylists";
    $data .= "&caps=extendedMD";

    my $param = {
      url => $url,
      method => 'POST',
      timeout => 10,
      noshutdown => 0,
      hash => $hash,
      key => 'publishToSonos',
      player => $d,
      data => $data,
    };

    $param->{cl} = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );

    $param->{callback} = \&plex_parseHttpAnswer;
    HttpUtils_NonblockingGet( $param );

    ++$i;
  }

  if( !$i && $player  ) {
    my $url = "http://$player:1400/customsd";

    Log3 $name, 4, "$name: requesting $url";

    my $fhem_base_url = "http://$hash->{fhemIP}:$hash->{helper}{timelineListener}{PORT}";

    my $data = plex_hash2form( { 'sid' => '246',
                                 'name' => $service,
                                 'uri' => "$fhem_base_url/SMAPI",
                                 'secureUri' => "$fhem_base_url/SMAPI",
                                 'pollInterval' => '1200',
                                 'authType' => 'Anonymous',
                                 'containerType' => 'MService',
                                 #'presentationMapVersion' => '1',
                                 #'presentationMapUri' => "$fhem_base_url/sonos/presentationMap.xml",
                                 #'stringsVersion' => '5',
                                 #'stringsUri' => "$fhem_base_url/sonos/strings.xml",
                               } );
    $data .= "&caps=search";
    $data .= "&caps=ucPlaylists";
    $data .= "&caps=extendedMD";

    my $param = {
      url => $url,
      method => 'POST',
      timeout => 10,
      noshutdown => 0,
      hash => $hash,
      key => 'publishToSonos',
      player => $player,
      data => $data,
    };

    $param->{cl} = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );

    $param->{callback} = \&plex_parseHttpAnswer;
    HttpUtils_NonblockingGet( $param );

    ++$i;
  }

  return 'no sonos players found' if( !$i );

  return "send SMAPI registration to $i players";

  return undef;
}

1;

=pod
=item summary    control and receive events from PLEX players
=item summary_DE Steuern und &uuml;berwachen von PLEX Playern
=begin html

<a name="plex"></a>
<h3>plex</h3>
<ul>
  This module allows you to control and receive events from plex.<br><br>
  <br><br>
  Notes:
  <ul>
    <li>IO::Socket::Multicast is needed to use server and client autodiscovery.</li>
    <li>As far as possible alle get and set commands are non-blocking.
        Any output is displayed asynchronous and is using fhemweb popup windows.</li>

  </ul>

  <br><br>


  <a name="plex_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; plex [&lt;server&gt;]</code>
    <br><br>
  </ul>

  <a name="plex_Set"></a>
  <b>Set</b>
  <ul>
    <li>play [&lt;server&gt; [&lt;item&gt;]]<br>
      </li>
    <li>resume [&lt;server&gt;] &lt;item&gt;]<br>
      </li>
    <li>pause [&lt;type&gt;]</li>
    <li>stop [&lt;type&gt;]</li>
    <li>skipNext [&lt;type&gt;]</li>
    <li>skipPrevious [&lt;type&gt;]</li>
    <li>stepBack [&lt;type&gt;]</li>
    <li>stepForward [&lt;type&gt;]</li>
    <li>seekTo &lt;value&gt; [&lt;type&gt;]</li>
    <li>volume &lt;value&gt; [&lt;type&gt;]</li>
    <li>shuffle 0|1 [&lt;type&gt;]</li>
    <li>repeat 0|1|2 [&lt;type&gt;]</li>
    <li>mirror [&lt;server&gt;] &lt;item&gt;<br>
      show preplay screen for &lt;item&gt;</li>
    <li>home</li>
    <li>music</li>
    <li>showAccount<br>
      display obfuscated user and password in cleartext</li>
    <li>playlistCreate [&lt;server&gt;] &lt;name&gt;</li>
    <li>playlistAdd [&lt;server&gt;] &lt;key&gt; &lt;keys&gt;</li>
    <li>playlistRemove [&lt;server&gt;] &lt;key&gt; &lt;keys&gt;</li>
    <li>unwatched [[&lt;server&gt;] &lt;items&gt;]</li>
    <li>watched [[&lt;server&gt;] &lt;items&gt;]</li>
    <li>autocreate &lt;machineIdentifier&gt;<br>
      create device for remote/shared server</li>
  </ul><br>

  <a name="plex_Get"></a>
  <b>Get</b>
  <ul>
    <li>[&lt;server&gt;] ls [&lt;path&gt;]<br>
      browse the media library. eg:<br><br>
      <b><code>get &lt;plex&gt; ls</code></b>
      <pre>  Plex Library
  key                                 type       title
  1                                   artist       Musik
  2                      ...</pre><br>

      <b><code>get &lt;plex&gt; ls /1</code></b>
      <pre>  Musik
  key                                 type       title
  all                                            All Artists
  albums                                         By Album
  collection                                     By Collection
  decade                                         By Decade
  folder                                         By Folder
  genre                                          By Genre
  year                                           By Year
  recentlyAdded                                  Recently Added
  search?type=9                                  Search Albums...
  search?type=8                                  Search Artists...
  search?type=10                                 Search Tracks...</pre><br>

      <b><code>get &lt;plex&gt; ls /1/albums</code></b>
      <pre>  Musik ; By Album
  key                                  type       title
  /library/metadata/133999/children   album       ...
  /library/metadata/134207/children   album       ...
  /library/metadata/168437/children   album       ...
  /library/metadata/82906/children    album       ...
  ...</pre><br>

      <b><code>get &lt;plex&gt; ls /library/metadata/133999/children</code></b>
      <pre>  ...</pre><br>
      <br>if used from fhemweb album art can be displayed and keys and other items are klickable.<br><br>

    </li>

    <li>[&lt;server&gt;] search &lt;keywords&gt;<br>
      search the media library for items that match &lt;keywords&gt;</li>

    <li>[&lt;server&gt;] onDeck<br>
      list the global onDeck items</li>

    <li>[&lt;server&gt;] recentlyAdded<br>
      list the global recentlyAdded items</li>

    <li>[&lt;server&gt;] detail &lt;key&gt;<br>
      show detail information for media item &lt;key&gt;</li>

    <li>[&lt;server&gt;] playlists<br>
      list playlists</li>

    <li>[&lt;server&gt;] m3u [album]<br>
      creates an album playlist in m3u format. can be used with other players like sonos.</li>

    <li>[&lt;server&gt;] pls [album]<br>
      creates an album playlist in pls format. can be used with other players like sonos.</li>

    <li>clients<br>
      list the known clients</li>

    <li>servers<br>
      list the known servers</li>

    <li>pin<br>
      get a pin for authentication at <a href="https://plex.tv/pin">https://plex.tv/pin</a></li>

  </ul><br>

  <a name="plex_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>httpPort</li>
    <li>ignoredClients</li>
    <li>ignoredServers</li>
    <li>removeUnusedReadings</li>
    <li>user</li>
    <li>password<br>
      user and password of a myPlex account. required if plex home is used. both are stored obfuscated</li>
  </ul>

</ul><br>

=end html
=cut
