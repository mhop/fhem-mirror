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

<<<<<<< .mine
##########################################################################
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
##########################################################################

||||||| .r31235
=======

>>>>>>> .r31250
package minisip;

use strict;
use warnings;
<<<<<<< .mine
use Data::Dumper;
||||||| .r31235
use Socket;
use IO::Socket::INET;
=======
use Data::Dumper;

use Socket;
use IO::Socket::INET;
>>>>>>> .r31250

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

use Time::HiRes qw(time);
use Time::Piece;
use GPUtils qw(GP_Import);

use Socket;
use IO::Socket::INET;

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

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
<<<<<<< .mine
      readingsSingleUpdate
      contains_string
      FileWrite)
||||||| .r31235
		  readingsBeginUpdate
      readingsBulkUpdate
      readingsEndUpdate
      readingSingleUpdate)
=======
		  readingsBeginUpdate
      readingsBulkUpdate
      readingsEndUpdate
      readingsSingleUpdate
      FileWrite)
>>>>>>> .r31250
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
<<<<<<< .mine
#  my $peer;
#  my $buf;
#  $hash->{SIP}->{bytes} = $sock->recv($hash->{SIP}->{buf}, 4096);
  my $iaddr;
  my $peer_addr = $sock->recv($hash->{SIP}->{buf}, 4096);
  ($hash->{peer}->{port}, $iaddr) = sockaddr_in($peer_addr);
  $hash->{peer}->{peer_ip} = inet_ntoa($iaddr);
  _process($hash);
||||||| .r31235
  my $peer;
  my $buf;
  my $bytes = $sock->recv($buf, 4096);
  if (defined $bytes) {
    _process($hash,$bytes,$buf);
  }
=======
#  my $peer;
#  my $buf;
  $hash->{SIP}->{bytes} = $sock->recv($hash->{SIP}->{buf}, 4096);
  if (defined $hash->{SIP}->{bytes}) {
    _process($hash);
  }
>>>>>>> .r31250
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

<<<<<<< .mine
sub _sendmsg {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
||||||| .r31235
sub _save {
  my $headers    = shift;
  $contact       = _header("Contact",$headers);
  $to            = _header("To",$headers);
  $to           =~ s/^.*<(.*)>.*$/$1/;
  $contact      =~ s/^.*<(.*)>.*$/$1/;
  $ip            = _sender_ip($headers);
  $location{$to} = $ip;
#  Debug "contact: $contact to: $to ip: $ip";
}
=======
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
>>>>>>> .r31250

<<<<<<< .mine
  (AttrVal($name,'logFullMessage',0))?  
    _log($hash,4,"Message out:\n$msg"):
    _log($hash,4,"Message out: ".(split(/\n/,$msg))[0]);
  
  (AttrVal($name,'showFullMessage',0))?  
     readingsSingleUpdate($hash, "lastMsgOut", $msg, 0):
     readingsSingleUpdate($hash, "lastMsgOut", (split(/\n/,$msg))[0], 1);
||||||| .r31235
sub _header {
  my $field = shift;
  my $headers = shift;
  my $s;
  $s=$headers;
  $s=~s/(^|\n)(?!$field)[^\n]*/$1/gs;
  $s=~s/(^\n*|\n*$)//gs;
  $s=~s/\n+/\n/gs;
  return $s
}
=======
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
>>>>>>> .r31250

<<<<<<< .mine
  my $sock = new IO::Socket::INET (
    PeerAddr => '192.168.123.20', 
    PeerPort => '5060',
    Proto    => 'udp');
||||||| .r31235
sub _sender_ip {
  my $headers = shift;
  $contact = _header("Contact",$headers);
  my $s;
  $s=$contact;
  $s=~s/^.*\@(\d+(\.\d+){3})\D.*$/$1/s;
  return $s;
}
=======
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
>>>>>>> .r31250

<<<<<<< .mine
  if($sock) {
    print $sock $msg;
    close($sock);
  } else {
    _log($hash,1,"$!");
||||||| .r31235
sub _send_msg {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $ip = shift;
  my $infoline = shift;
  my $headers = shift;
  my $body = shift;
  my $msg=$infoline."\r\n".$headers.$body;

  _log($hash,4,"Message out:\n$infoline\n");
  if (AttrVal($name,'showFullMessage',0) == 1) {  
     readingSingleUpdate($hash, "lastMsgOut", $msg);
  } else {
     readingSingleUpdate($hash, "lastMsgOut", $infoline);
=======
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
>>>>>>> .r31250
  }
<<<<<<< .mine
||||||| .r31235
  
  my $sock = new IO::Socket::INET (
    PeerAddr =>$ip, 
    PeerPort => '5060',
    Proto => 'udp');
  die "Could not create socket: $!\n" unless $sock;
  print $sock $msg;
  close($sock);
=======

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
>>>>>>> .r31250
}

<<<<<<< .mine
sub reply_200_register {
||||||| .r31235
sub _button {
  Debug "_button called";
  my $hash = %defs{minisip};
  my @msg = split("\n",'MESSAGE snom@192.168.123.20;transport=udp SIP/2.0
From: sip:minisip@192.168.123.111:1036;tag=38473
To: snom@192.168.123.20
Call-ID: 6algjorv@test
CSeq: 59620 MESSAGE
Max-Forwards: 70
Contact: <snom$@192.168.123.20;transport=udp>
Subject: buttons
Content-Type: application/x-buttons');
=======
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
>>>>>>> .r31250

<<<<<<< .mine
||||||| .r31235
  my $payload = "\n\nk=18\nn=**18\nc=on\no=red\nl=Ventilator\n";
  my $clen = length($payload); $clen++;
  push(@msg,"Content-Length: $clen$payload");
=======
  my $payload = <<"PAYLOAD";
k=$key
c=$command
o=$color
l=$label
a=message
n=**
>>>>>>> .r31250

<<<<<<< .mine
}
||||||| .r31235
  _send_msg($hash,$ip,"",join("\n",@msg),"");
=======
>>>>>>> .r31250

<<<<<<< .mine
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
||||||| .r31235
}
=======
>>>>>>> .r31250

<<<<<<< .mine
sub _process {
  my ($hash)  = @_;
  my $name = $hash->{NAME};
  
  my $pkt     = eval { Net::SIP::Packet->new( $hash->{SIP}->{buf} ) };
  return _log($hash,1,"$name: $@") if ($@);
||||||| .r31235
sub _process {
  my ($hash,$bytes,$buf) = @_;
  my $name = $hash->{NAME};
  my $infoline = $buf;
  my $headers  = $buf;
  my $body     = $buf;
  my $method   = $buf;
  my $uri      = $buf;
  
  $infoline =~ s/^([^\r\n]*).*$/$1/s;
  $headers  =~ s/^[^\r\n]*\r?\n(.*(\r?\n){2}).*$/$1/s;
  $body     =~ s/^.*(\r?\n){2}(.*)$/$2/s;
  $method   =~ s/^([^ ]*) .*$/$1/s;
  $ip       =  _sender_ip($headers);
  
  (AttrVal($name,'logFullMessage',0))?  
    _log($hash,4,"Message in:\n$buf"):
    _log($hash,4,"Message in:\n$infoline");
=======
>>>>>>> .r31250

<<<<<<< .mine
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
||||||| .r31235
  if($method eq "REGISTER") {
    _save($headers);
    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");
  }
=======
>>>>>>> .r31250

<<<<<<< .mine
  if ($method eq 'INVITE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    $user =~ m/sip:([*#\d]+)@/;
    my $input = $1 // "?";
    readingsSingleUpdate($hash, "input", $input, 1);
  }
||||||| .r31235
  if($method eq "INVITE") {
    (AttrVal($name,'showFullMessage',0))?  
       readingsBulkUpdate($hash, "lastMsgIn", $headers):
       readingsBulkUpdate($hash, "lastMsgIn", $infoline);
    my $msg=$infoline;
    $msg =~ s/%23/#/g;
    $msg =~ m/^INVITE.sip:([\d*#]+)@/;
    readingsBulkUpdate($hash, "input", $1);
    $msg=$headers;
    $msg=~s/\nContent-Type:[^\n]*\n/\n/s;
    $msg=~s/\nContent-Length:[^\n]*\n/\n/s;
    _send_msg($hash,$ip,"SIP/2.0 500 Error",$msg,"");
  }
=======
PAYLOAD
>>>>>>> .r31250

<<<<<<< .mine
  if ($method eq 'MESSAGE') {
    my ($info,$user,$header,$body) = $pkt->as_parts;
    $body =~ m/k=(\d+)/;
    my $input = $1 // "?";
    readingsSingleUpdate($hash, "input", $input, 1);
  }
||||||| .r31235
#  if($method eq "MESSAGE") {
#    readingsBulkUpdate($hash, "lastMsgIn", $infoline);
#    my $msg=$headers;
#    $msg=~s/\nContent-Type:[^\n]*\n/\n/s;
#    $msg=~s/\nContent-Length:[^\n]*\n/\n/s;
##    _send_msg($hash,$ip,"SIP/2.0 500 Error",$msg,"");
#    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");
#  }
=======
  my $body = <<"BODY";
Content-Length: @{[ length($payload) ]}
>>>>>>> .r31250

<<<<<<< .mine
  if($method eq "SUBSCRIBE") {
||||||| .r31235
  if($method eq "ACK") {
=======
$payload
BODY
#Content-Length: @{[ length($payload) ]}
>>>>>>> .r31250

  my @h = split(/\n/,$headers);
  my @b = split(/\n/,$body);

  my $filename = "/tmp/ledControl.txt";
  my $err = FileWrite({FileName => $filename,ForceType => 'file'},(@h,@b));
  system("sipsak -G --hostname 192.168.123.111 -s sip:snom\@192.168.123.20 --filename $filename");

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

<<<<<<< .mine
=pod
  if($method eq "SUBSCRIBE") {
    _save($headers);
    _sendmsg($hash,$ip,"SIP/2.0 200 OK",$headers,"");  
  }
}
=cut

||||||| .r31235
=======
=pod
  if($method eq "SUBSCRIBE") {
    _save($headers);
    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");  
  }
}
=cut

>>>>>>> .r31250
#
