#  $Id: 55_minisip.pm 31259 2026-05-22 07:08:28Z betateilchen $

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
use POSIX qw(strftime);
use MIME::Base64;
use Data::Dumper;
use HTML::HashTable;


use Socket;
use IO::Socket::INET;

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

use GPUtils qw(GP_Import);

# Import from main context
BEGIN {
	GP_Import(
	 qw(readingFnAttributes
	    defs
	    snom
			selectlist
		  AttrVal
			Debug
      FileWrite
		  Log3
      contains_string
      readingsSingleUpdate
      toJSON
      )
	);
}


sub Define {
  my ($hash, $a, $h) = @_; #parseParams
  my $name = $a->[0];

  $hash->{SIP}->{PORT} = $h->{port};
  $hash->{SIP}->{FROM} = $h->{from};
  $hash->{SIP}->{LOCAL_CONTACT} = "<sip:$h->{from}>";
  $hash->{SIP}->{PROTO} = 'udp';

  my $sock = IO::Socket::INET->new(
    LocalPort => $hash->{SIP}->{PORT},
    Proto     => $hash->{SIP}->{PROTO},
    Reuse     => 1,
 #   Blocking  => 0
  );
  return "$name: $!" unless $sock;
  $hash->{SOCK} = $sock;
  my $fh = $sock->fileno();
  $hash->{FD} = $fh;
  $selectlist{$fh} = $hash;
  return undef;
}

sub Read {
#  return if(IsDisabled());
  my ($hash) = @_;
  my $sock = $hash->{SOCK};
  my $iaddr;
  my $peer_addr = $sock->recv($hash->{SIP}->{buf}, 4096);
#  ($hash->{peer}->{port}, $iaddr) = sockaddr_in($peer_addr);
#  $hash->{peer}->{ip} = inet_ntoa($iaddr);
  _process($hash);
}

sub Undef {
  my ($hash, $arg) = @_;
  my $sock = $hash->{SOCK};
  if ($sock) {
    close($sock);
  }
  delete $selectlist{$hash->{FD}} if defined $hash->{FD};
  delete $hash->{peer};
  delete $hash->{SIP};
  return undef;
}

sub Set {
  my ($hash,$a,$h) = @_;
  my $name = $hash->{NAME};
  my %cmd = ("sendmsg" => "", );
  
  return ("Unknown argument $a->[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a->[1]}));

  if( $a->[1] eq 'sendmsg' ) {
    my $peer = $a->[2];
    my $msg  = $a->[3];
    $msg .= "==";
    $msg =  decode_base64($msg);
    _sendmsg($hash,$peer,$msg);
  }

  return undef;
}

sub Get {
  my ($hash,$a,$h) = @_;
  my $name = $hash->{NAME};
  my %cmd = ("peers" => ":noArg", );
  
  #Debug Dumper $a->[1];

  return ("Unknown argument $a->[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a->[1]}));

  if( $a->[1] eq 'peers' ) {
    my $count = scalar keys %{$hash->{peers}};
    if (!$count) {
      return "no peer registered";
    } else {
      return _makeTablePeers($hash);
    }
  }
}

###------------------------------------------------------------------

sub _log {
  my ($hash,$loglevel,$text ) = @_;
  my $xline       = ( caller(0) )[2];
  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "minisip";
  Log3 $hash, $loglevel, "$instName: $sub.$xline " . $text;
}

sub _makeTablePeers {
  my ($hash) = @_;
  my $table = tablify({
       BORDER      => 1, 
       DATA        => $hash->{peers},
       SORTBY      => 'key', 
       ORDER       => 'asc'}
   );
  return "<html>$table</html>";
}

sub _getpeer {
  my ($hash,$pkt) = @_;
  my $contact = $pkt->get_header('contact');
  my ($peer,$ip,$port) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+):(\d+)/;
  if ($peer eq '') {
    $contact = $pkt->get_header('from');
    ($peer,$ip) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+)/;
    $contact = $pkt->get_header('via');
    ($port) = $contact =~ m/\d+\.\d+\.\d+\.\d+:(\d+)/;
  }
  return ($peer,$ip,$port);
}

sub _sendmsg {
  my ($hash,$peer,$msg) = @_;
  my $name = $hash->{NAME};

  my $count = scalar keys %{$hash->{peers}};
  if (!$count) {
    _log($hash,1,"$name: no peer registered");
    return;
  } elsif (!defined($hash->{peers}->{$peer})) {
    _log($hash,1,"$name: unknown peer >$peer<");
    return;
  }

  (AttrVal($name,'logFullMessage',0))?  
    _log($hash,4,"out to $peer:\n$msg"):
    _log($hash,4,"out to $peer: ".(split(/\n/,$msg))[0]);
  
  (AttrVal($name,'showFullMessage',0))?  
     readingsSingleUpdate($hash, "lastMsgOut", $msg, 0):
     readingsSingleUpdate($hash, "lastMsgOut", (split(/\n/,$msg))[0], 1);

  my $sock = new IO::Socket::INET (
    PeerAddr => $hash->{peers}->{$peer}->{peer_ip},
    PeerPort => $hash->{peers}->{$peer}->{peer_port},
    Proto    => $hash->{SIP}->{PROTO});

  if($sock) {
    print $sock $msg;
    close($sock);
  } else {
    _log($hash,1,"$!");
  }
}

sub _reply_200_short {
  my ($hash,$req) = @_;

  my $res = Net::SIP::Response->new(
      200,
      'OK',
     { 'Via'            => [ $req->get_header('Via') ],
       'From'           => $req->get_header('From'),
       'To'             => $req->get_header('To'),
       'Call-ID'        => $req->get_header('Call-ID'),
       'CSeq'           => $req->get_header('CSeq'),
       'Contact'        => $req->get_header('Contact') // $hash->{SIP}->{LOCAL_CONTACT},
       'Expires'        => 300,
#       'Expires'        => $req->get_header('Expires') // 300,
       'Content-Length' => '0',
     }
    );
    return $res;
}

sub _process {
  my ($hash)  = @_;
  my $name = $hash->{NAME};
  
  my $pkt     = eval { Net::SIP::Packet->new( $hash->{SIP}->{buf} ) };

  (AttrVal($name,'logFullMessage',0))?
    _log($hash,4,"in:\n".$pkt->as_string):
    _log($hash,4,"in:  ".(split(/\n/,$pkt->as_string))[0]);

  #my $method  = $pkt->method(); # funktioniert nicht zuverlässig für MESSAGE
    
  my $method =  $pkt->as_string;
  $method    =~ s/^([^ ]*) .*$/$1/s;

  my ($peer,$ip,$port) = _getpeer($hash,$pkt);

  (AttrVal($name,'showFullMessage',0))?
    readingsSingleUpdate($hash, lc($method), $pkt->as_string, 0):
    readingsSingleUpdate($hash, lc($method), (split(/\n/,$pkt->as_string))[0], 1);

  if ($method eq 'REGISTER') {
#    my $contact = $pkt->get_header('contact');
#    my ($peer,$ip,$port) = $contact =~ m/<sip:(.*)@(\d+\.\d+\.\d+\.\d+):(\d+)/;
    if (defined($peer) && $peer ne '') {
      my $ts                  = strftime("%a, %d %b %Y %H:%M:%S", localtime(time()));
      $hash->{peers}->{$peer} = { 'peer'       => $peer,
                                  'peer_ip'    => $ip,
                                  'peer_port'  => $port,
                                  'registered' => $ts,
                                };

      my $c = $pkt->get_header('contact');
      $c =~ s/</&lt;/g; $c =~ s/>/&gt;/g; # die <> müssen ersetzt werden, um eine Darstellung im Get zu haben
      $hash->{peers}->{$peer}->{contact}    = $c if (defined($c) && $c);      

      my $e = $pkt->get_header('expires');
      $hash->{peers}->{$peer}->{expires}    = $e if (defined($e) && $e);      

      my $u = $pkt->get_header('user_agent');
      $hash->{peers}->{$peer}->{user_agent} = $u if (defined($u) && $u);

      my $x = $pkt->get_header('x-real-ip');
      $hash->{peers}->{$peer}->{x_real_ip}  = $x if (defined($x) && $x);
      #Debug toJSON($hash->{peers}->{$peer});
    }
  }

  my @known_methods = qw(REGISTER INVITE BYE MESSAGE SUBSCRIBE);
  if (contains_string($method,@known_methods)) {
    my $resp = _reply_200_short($hash,$pkt);
    _sendmsg($hash,$peer,$resp->as_string);
  }

  if ($method eq 'INVITE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    $user =~ m/sip:([*#\d]+)@/;
    my $input = $1 // "?";
    readingsSingleUpdate($hash, "input", $input, 1);
  }

  if ($method eq 'MESSAGE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    $body =~ m/k=(\d+)/;
    my $input = $1 // "?";
    readingsSingleUpdate($hash, "input", $input, 1);
  }
}

1;

#
