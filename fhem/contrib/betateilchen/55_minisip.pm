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
		  readingsBeginUpdate
      readingsBulkUpdate
      readingsEndUpdate
      readingsSingleUpdate
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
#  my $peer;
#  my $buf;
  $hash->{SIP}->{bytes} = $sock->recv($hash->{SIP}->{buf}, 4096);
  if (defined $hash->{SIP}->{bytes}) {
    _process($hash);
  }
}

sub _Undef {
  my ($hash, $arg) = @_;
  my $sock = $hash->{SOCK};
  if ($sock) {
    close($sock);
  }
  delete $selectlist{$hash->{FD}} if defined $hash->{FD};
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

sub _send_msg {
  my ($hash,$msg) = @_;

#  (AttrVal($name,'logFullMessage',0))?  
#    _log($hash,4,"Message out:\n$msg"):
#    _log($hash,4,"Message out:\n$infoline");
  
#  (AttrVal($name,'showFullMessage',0))?  
#     readingsSingleUpdate($hash, "lastMsgOut", $msg,1):
#     readingsSingleUpdate($hash, "lastMsgOut", $infoline,1);

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

sub _ensure_to_has_tag {
    my ($to_hdr, $tag) = @_;
    return $to_hdr if $to_hdr =~ /;tag=/;
    # insert tag before any > or end
    if ($to_hdr =~ /(>)/) {
        $to_hdr =~ s/>/;tag=$tag>/;
        return $to_hdr;
    } else {
        return $to_hdr . ";tag=$tag";
    }
}

sub reply_200_short {
    my ($req, $local_contact) = @_;

#    # erzeuge To-Tag wenn noch nicht vorhanden
#    my $to_hdr = $req->get_header('To');
#    my $to_tag;
#    if ($to_hdr =~ /;tag=([^;>\s]+)/) {
#        $to_tag = $1;
#    } else {
#        $to_tag = int(rand(1_000_000));
#    }

    # build Antwort
    my $res = Net::SIP::Response->new(
        200,
        'OK',
         { Via         => [ $req->get_header('Via') ],
           From        => $req->get_header('From'),
#           To          => _ensure_to_has_tag($req->get_header('To'), $to_tag),
           To          => $req->get_header('To'),
           'Call-ID'   => $req->get_header('Call-ID'),
           CSeq        => $req->get_header('CSeq'),
           'Content-Length' => '0',
         }
    );
    return $res;
}

sub reply_200_no_sdp {
    my ($req, $local_contact) = @_;

    # erzeuge To-Tag wenn noch nicht vorhanden
    my $to_hdr = $req->get_header('To');
    my $to_tag;
    if ($to_hdr =~ /;tag=([^;>\s]+)/) {
        $to_tag = $1;
    } else {
        $to_tag = int(rand(1_000_000));
    }

    # build Antwort
    my $res = Net::SIP::Response->new(
        200,
        'OK',
         { Via         => [ $req->get_header('Via') ],
           From        => $req->get_header('From'),
           To          => _ensure_to_has_tag($req->get_header('To'), $to_tag),
           'Call-ID'   => $req->get_header('Call-ID'),
           CSeq        => $req->get_header('CSeq'),
           Contact     => $local_contact // '<sip:minisip@fhem.h5u.de>',
           'User-Agent'=> 'MyPerlSIP/1.0',
           Allow       => 'INVITE, ACK, BYE, CANCEL, OPTIONS, INFO, REFER, NOTIFY',
           Supported   => 'replaces, timer',
           Accept      => 'application/sdp',
           'Content-Length' => '0',
           body => '',
        }
    );

    return $res;
}

sub _process {
  my ($hash)  = @_;
  my $pkt     = eval { Net::SIP::Packet->new( $hash->{SIP}->{buf} ) };
  my $method  = $pkt->method();

#  (AttrVal($name,'logFullMessage',0))?  
#    _log($hash,4,"Message in:\n$buf"):
#    _log($hash,4,"Message in:\n$infoline");

#  (AttrVal($name,'showFullMessage',0))?
#    readingsSingleUpdate($hash, "lastMsgIn", $headers, 1):
#    readingsSingleUpdate($hash, "lastMsgIn", $infoline, 1);

  readingsSingleUpdate($hash, lc($method), $pkt->as_string, 0);

  my @known_methods = qw(REGISTER INVITE BYE MESSAGE);
  if (contains_string($method,@known_methods)) {
    my $resp = reply_200_short($pkt,'<sip:minisip@fhem.h5u.de>');
    _send_msg($hash,$resp->as_string);
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
  my $hash = $defs{minisip};
  my ($key,$command,$color,$label) = @_;

my $headers = <<"HEADER";
MESSAGE \$user\$\@\$dsthost\$:5060;transport=udp SIP/2.0
From: "minisip" <sip:minisip\@\$srchost\$>;tag=38473
To: <sip:\$user\$\@\$dsthost\$:5060>
Call-ID: 12345678\@\$srchost\$
CSeq: 59620 MESSAGE
Max-Forwards: 70
Contact: <\$user\$\@\$dsthost\$;transport=udp>
Subject: buttons
Content-Type: application/x-buttons
HEADER

  my $payload = <<"PAYLOAD";
k=$key
c=$command
o=$color
l=$label
a=message
n=**






PAYLOAD

  my $body = <<"BODY";
Content-Length: @{[ length($payload) ]}

$payload
BODY
#Content-Length: @{[ length($payload) ]}

  my @h = split(/\n/,$headers);
  my @b = split(/\n/,$body);

  my $filename = "/tmp/ledControl.txt";
  my $err = FileWrite({FileName => $filename,ForceType => 'file'},(@h,@b));
  system("sipsak -G --hostname 192.168.123.111 -s sip:snom\@192.168.123.20 --filename $filename");
}

1;

=pod
  if($method eq "SUBSCRIBE") {
    _save($headers);
    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");  
  }
}
=cut

#
