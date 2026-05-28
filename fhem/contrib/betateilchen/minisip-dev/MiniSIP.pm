#  $Id: MiniSIP.pm 31283 2026-05-25 12:45:47Z betateilchen $

################################################################
#
#  Copyright notice
#
#  (c) 2026 - today
#  Copyright: betateilchen (betateilchen dot quantentunnel dot de)
#  All rights reserved
#
#  This program is part of FHEM; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
#  See the GNU General Public License V2 for more details.
#
################################################################

package FHEM::Core::MiniSIP;

use strict;
use warnings;

use Socket;
use IO::Socket::INET;

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

use FHEM::MiniSIP::Utils qw(:all);

use Exporter ('import');
our @EXPORT_OK = qw(sendmsg);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

use GPUtils qw(GP_Import);
# Import from main context
BEGIN {
	GP_Import(
	 qw(readingFnAttributes
	    data
	    defs
	    modules
	    snom
			selectlist
		  AttrVal
			Debug
      FileWrite
      IsDisabled
		  Log3
      contains_string
      readingsSingleUpdate
      setKeyValue
      toJSON
      )
	);
}

my $p = __PACKAGE__;
$::data{modules}{version}{$p} = '$Id: MiniSIP.pm 31283 2026-05-25 12:45:47Z betateilchen $';

sub Define {
  my ($hash, $a, $h) = @_; #parseParams
  my $name = $a->[0];
  return "Only one device with TYPE=MiniSIP can be defined" 
      if($modules{MiniSIP}{inUse});

  $hash->{server}->{port} = $h->{port};
  $hash->{server}->{from} = $h->{from};
  $hash->{server}->{local} = "<sip:$h->{from}>";
  $hash->{server}->{proto} = 'udp';

  my $sock = IO::Socket::INET->new(
    LocalPort => $hash->{server}->{port},
    Proto     => $hash->{server}->{proto},
    Reuse     => 1,
 #   Blocking  => 0
  );
  return "$name: $!" unless $sock;
  $hash->{SOCK} = $sock;
  my $fh = $sock->fileno();
  $hash->{FD} = $fh;
  $selectlist{$fh} = $hash;

  #FHEM::MiniSIP::Utils::restore_peers($hash);
  
  readingsSingleUpdate($hash,'state','initialized',1);
  $modules{MiniSIP}{inUse} = 1;
  return undef;
}

sub Read {
  my ($hash) = @_;
  return if(IsDisabled($hash->{NAME}));
  my $sock = $hash->{SOCK};
  my $res = $sock->recv($hash->{server}->{buf}, 4096);
  processmsg($hash);
}

sub Set {
  my ($hash,$a,$h) = @_;
  my $name = $hash->{NAME};

  my %cmd = ("sendmsg"      => "",
             "backup_peers" => ":noArg", 
             "restore_peers" => ":noArg", 
            );
  return ("Unknown argument $a->[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a->[1]}));

  if( $a->[1] eq 'sendmsg' )       {
    my $peer    = $h->{peer};
    my $type    = $h->{type};
    my $payload = $h->{msg};
    my $msg;
    
    if ($type eq 'data') {
       $msg  = $data{$payload};
    }

    sendmsg($hash,$peer,$msg);
  }
  if( $a->[1] eq 'backup_peers' )  { FHEM::MiniSIP::Utils::backup_peers($hash); }
  if( $a->[1] eq 'restore_peers' ) { FHEM::MiniSIP::Utils::restore_peers($hash); }

  return undef;
}

sub Get {
  my ($hash,$a,$h) = @_;
  my $name = $hash->{NAME};
  my %cmd = ("peer"  => "",
             "peers" => ":table,json",
            );

  return ("Unknown argument $a->[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a->[1]}));

  if( $a->[1] eq 'peers' ) {
    if (!havepeer($hash,undef)) {
      return "no peer registered";
    } elsif (lc($a->[2]) eq 'table') {
      return FHEM::MiniSIP::Utils::makeTable($hash,$hash->{peers});
    } elsif (lc($a->[2]) eq 'json') {
      return toJSON($hash->{peers});
    }
  }
  if( $a->[1] eq 'peer' ) {
    return "no peer given" unless $a->[2];
    return getpeer($hash,$a->[2]);
  }
}

sub Undef {
  my ($hash, $arg) = @_;
  my $sock = $hash->{SOCK};
  if ($sock) {
    close($sock);
  }
  delete $selectlist{$hash->{FD}} if defined $hash->{FD};
  delete $hash->{peer};
  delete $hash->{server};
  delete $modules{MiniSIP}{inUse};
  return undef;
}

sub Delete {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  setKeyValue($name,undef);
  return Undef($hash,$arg);
}

sub Shutdown {
  my ($hash) = @_;
  _log3($hash,4,"ShutdownFn called");
  FHEM::MiniSIP::Utils::backup_peers($hash);
}

###------------------------------------------------------------------

sub sendmsg {
  my ($hash,$peer,$msg) = @_;
  my $name = $hash->{NAME};

#  my $count = scalar keys %{$hash->{peers}};
#  if (!$count) {
#    _log3($hash,1,"no peer registered");
#    return;
#  } elsif (!defined($hash->{peers}->{$peer})) {
#    _log3($hash,1,"$name: unknown peer >$peer<");
#    return;
#  }

  if (!havepeer($hash,undef)) {
    return _log3($hash,1,"no peer registered");
#    return;
  } elsif (!havepeer($hash,$peer)) {
    return _log3($hash,1,"$name: unknown peer >$peer<");
#    return;
  }


  (AttrVal($name,'logFullMessage',0))?  
    _log3($hash,4,"out to $peer:\n$msg"):
    _log3($hash,4,"out to $peer: ".(split(/\n/,$msg))[0]);
  
  (AttrVal($name,'showFullMessage',0))?  
     readingsSingleUpdate($hash, "lastMsgOut", $msg, 0):
     readingsSingleUpdate($hash, "lastMsgOut", (split(/\n/,$msg))[0], 1);

  my $sock = new IO::Socket::INET (
    PeerAddr => $hash->{peers}->{$peer}->{peer_ip},
    PeerPort => $hash->{peers}->{$peer}->{peer_port},
    Proto    => $hash->{server}->{proto});

  if($sock) {
    print $sock $msg;
    close($sock);
  } else {
    _log3($hash,1,"$!");
  }
}

sub processmsg {
  my ($hash)  = @_;
  my $name = $hash->{NAME};
  
  my $pkt     = eval { Net::SIP::Packet->new( $hash->{server}->{buf} ) };

  (AttrVal($name,'logFullMessage',0))?
    _log3($hash,4,"in:\n".$pkt->as_string):
    _log3($hash,4,"in: ".(split(/\n/,$pkt->as_string))[0]);

  #my $method  = $pkt->method(); # not working as expected
    
  my $method =  $pkt->as_string;
  $method    =~ s/^([^ ]*) .*$/$1/s;

  if ($method ne "SIP/2.0") {
		(AttrVal($name,'showFullMessage',0))?
			readingsSingleUpdate($hash, lc($method), $pkt->as_string, 0):
			readingsSingleUpdate($hash, lc($method), (split(/\n/,$pkt->as_string))[0], 1);
  } elsif ($pkt->is_response) {
    return; # end processing if 200 OK received as response
  }

  my ($peer,$ip,$port) = FHEM::MiniSIP::Utils::extract_peer($hash,$pkt,0);

  if ($method eq 'REGISTER') {
    FHEM::MiniSIP::Utils::savepeer($hash,$pkt);
  }

  my @known_methods = qw(REGISTER INVITE BYE MESSAGE SUBSCRIBE);
  if (contains_string($method,@known_methods)) {
    my $resp = FHEM::MiniSIP::Utils::build_200_short($hash,$pkt);
    sendmsg($hash,$peer,$resp->as_string);
  }

  if ($method eq 'INVITE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    $user =~ m/sip:([*#\d]+)@/;
    my $input = $1 // "?";
    readingsSingleUpdate($hash, "input", $input, 1);
  }

  if ($method eq 'MESSAGE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    my $input = FHEM::MiniSIP::Utils::parsemsgbody($hash,$peer,$body);
    readingsSingleUpdate($hash, "input", $input, 1);
  }
  delete $hash->{server}->{buf};
}

1;

#
