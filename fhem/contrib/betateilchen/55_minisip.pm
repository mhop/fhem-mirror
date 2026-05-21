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
#  $Id$
#

package minisip;

use strict;
use warnings;
use Data::Dumper;

use Socket;
use IO::Socket::INET;

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

use Time::HiRes qw(time);
use Time::Piece;
use GPUtils qw(GP_Import);

# Import from main context
BEGIN {
	GP_Import(
	 qw(readingFnAttributes
	    defs
	    snom
			selectlist
			Debug
		  Log3
		  AttrVal
      readingsSingleUpdate
      contains_string
      FileWrite)
	);
}

sub main::minisip_Initialize {
	goto &_Initialize;
}

sub _Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}   = \&_Define;
  $hash->{ReadFn}  = \&_Read;
  $hash->{UndefFn} = \&_Undef;
#  $hash->{AttrFn}  = \&minisip_Attr;
  $hash->{AttrList}= "disable:1,0 "
                    ."logFullMessage:0,1 "
                    ."showFullMessage:0,1 "
                    .$readingFnAttributes;
}

sub _Define {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  my $port = $a[2] || 5060;

  my $sock = IO::Socket::INET->new(
    LocalPort => $port,
    Proto     => 'udp',
    Reuse     => 1,
 #   Blocking  => 0
  );
  return "$name: $!" unless $sock;
  $hash->{PORT} = $port;
  $hash->{SOCK} = $sock;
  my $fh = $sock->fileno();
  $hash->{FD} = $fh;
  $selectlist{$fh} = $hash;
  return undef;
}

sub _Read {
#  return if(IsDisabled());
  my ($hash) = @_;
  my $sock = $hash->{SOCK};
  my $iaddr;
  my $peer_addr = $sock->recv($hash->{SIP}->{buf}, 4096);
  ($hash->{peer}->{port}, $iaddr) = sockaddr_in($peer_addr);
  $hash->{peer}->{peer_ip} = inet_ntoa($iaddr);
  _process($hash);
}

sub _Undef {
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

###------------------------------------------------------------------

sub _log {
  my ($hash,$loglevel,$text ) = @_;
  my $xline       = ( caller(0) )[2];
  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "minisip";
  Log3 $hash, $loglevel, "$instName: $sub.$xline " . $text;
}

sub _sendmsg {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  (AttrVal($name,'logFullMessage',0))?  
    _log($hash,4,"Message out:\n$msg"):
    _log($hash,4,"Message out: ".(split(/\n/,$msg))[0]);
  
  (AttrVal($name,'showFullMessage',0))?  
     readingsSingleUpdate($hash, "lastMsgOut", $msg, 0):
     readingsSingleUpdate($hash, "lastMsgOut", (split(/\n/,$msg))[0], 1);

  my $sock = new IO::Socket::INET (
    PeerAddr => '192.168.123.20', 
    PeerPort => '5060',
    Proto    => 'udp');
  if($sock) {
    print $sock $msg;
    close($sock);
  } else {
    _log($hash,1,"$!");
  }
}

sub reply_200_short {
  my ($req, $local_contact) = @_;

  my $res = Net::SIP::Response->new(
      200,
      'OK',
     { 'Via'            => [ $req->get_header('Via') ],
       'From'           => $req->get_header('From'),
       'To'             => $req->get_header('To'),
       'Call-ID'        => $req->get_header('Call-ID'),
       'CSeq'           => $req->get_header('CSeq'),
       'Contact'        => $req->get_header('Contact'),
       'Expires'        => $req->get_header('Expires') // 3600,
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
    _log($hash,4,"Message in:\n".$pkt->as_string):
    _log($hash,4,"Message in:  ".(split(/\n/,$pkt->as_string))[0]);

  #my $method  = $pkt->method(); # funktioniert nicht zuverlässig für MESSAGE
    
  my $method =  $pkt->as_string;
  $method    =~ s/^([^ ]*) .*$/$1/s;
    
  (AttrVal($name,'showFullMessage',0))?
    readingsSingleUpdate($hash, lc($method), $pkt->as_string, 0):
    readingsSingleUpdate($hash, lc($method), (split(/\n/,$pkt->as_string))[0], 1);

  my @known_methods = qw(REGISTER INVITE BYE MESSAGE SUBSCRIBE);
  if (contains_string($method,@known_methods)) {
    my $resp = reply_200_short($pkt,'<sip:minisip@192.168.123.111>');
    _sendmsg($hash,$resp->as_string);
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

sub _button {
  my ($key,$command,$color,$label) = @_;
  my $hash = $defs{minisip};

  $label //= $snom{$key};

  my $from   = 'sip:minisip@192.168.123.111';
  my $to     = 'sip:snom@192.168.123.20';
  my $callid = 'cid'.int(rand(1_000_000));
  my $cseq   = 1;
  my $branch = 'z9hG4bK'.int(rand(1_000_000));

  my $body = <<"BODY";
k=$key
a=message
c=$command
o=$color
l=$label
n=**
BODY

  $body =~ s/\n/\r\n/g;

  my $req = Net::SIP::Request->new(
    'MESSAGE',
    $to,
    {
        'Via'          => "SIP/2.0/UDP 192.168.123.111:5060;branch=$branch",
        'Max-Forwards' => 70,
        'From'         => "<$from>;tag=12345",
        'To'           => "<$to>",
        'Call-ID'      => $callid,
        'CSeq'         => "$cseq MESSAGE",
        'Contact'      => "<$from>",
        'Subject'      => 'buttons',
        'Content-Type' => 'application/x-buttons',
    },
    $body
  );
  _sendmsg($hash,$req->as_string);
}

1;

#
