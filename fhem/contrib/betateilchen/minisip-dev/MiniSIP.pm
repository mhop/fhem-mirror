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
use Data::Dumper;

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
$::data{modules}{version}{$p} = 
'$Id: MiniSIP.pm 31283 2026-05-25 12:45:47Z betateilchen $';

sub Define {
  my ($hash, $a, $h) = @_; #parseParams
  my $name = $a->[0];
  return "Only one device with TYPE=MiniSIP can be defined" 
      if($modules{MiniSIP}{inUse});

  $hash->{server}->{from}  = $h->{from};
  $hash->{server}->{host}  = (split(/@/,$h->{from}))[1];
  $hash->{server}->{port}  = $h->{port};
  $hash->{server}->{local} = "<sip:$h->{from}>";
  $hash->{server}->{proto} = 'udp';

  my $sock = IO::Socket::INET->new(
    LocalAddr => $hash->{server}->{host},
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

  my $leg = Net::SIP::Leg->new( sock => $sock );
  $hash->{server}->{leg} = $leg;

  FHEM::MiniSIP::Utils::restore_peers($hash);
  
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

  %cmd = ( %cmd, 
           user_add => "", 
           user_delete => "",
          ) if AttrVal($name,'useAuth',0);

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
  if( $a->[1] eq 'user_add')       { 
    return "username or password missing!" unless ($h->{username} && $h->{password});  
    return user_add($hash,$h->{username},$h->{password});
  }
  if( $a->[1] eq 'user_delete')    { 
    return "username missing!" unless $h->{username};
    return user_delete($hash,$h->{username});
  }
  return undef;
}

sub Get {
  my ($hash,$a,$h) = @_;
  my $name = $hash->{NAME};
  my %cmd = ("peer"  => "",
             "peers" => ":table,json",
            );

  %cmd = ( %cmd, 
           user_list => ":noArg", 
          ) if AttrVal($name,'useAuth',0);

  return ("Unknown argument $a->[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a->[1]}));

  if( $a->[1] eq 'peer' ) {
    return "no peer given" unless $h->{peer};
    return getpeer($hash,$h->{peer});
  }
  if( $a->[1] eq 'peers' ) {
    if (!havepeer($hash,undef)) {
      return "no peer registered";
    } elsif (lc($a->[2]) eq 'table') {
      return FHEM::MiniSIP::Utils::makeTable($hash,$hash->{peers});
    } elsif (lc($a->[2]) eq 'json') {
      return toJSON($hash->{peers});
    }
  }
  if( $a->[1] eq 'user_list' ) {
    return user_list($hash);
  }
}

sub Attr { 
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};
  my $ret;
  
  if($attrName eq "useAuth") {
    if($type eq "set") {
      if ($param[0]) {
        eval "use FHEM::MiniSIP::Auth qw(:all)";
        return $@ if($@);
      }
    } 
  }
  return $ret;
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


sub ntf_body_1 {
  my $body   = <<"BODY";
Messages-Waiting: yes
Message-Account: sip:12345\@192.168.123.254
Voice-Message: 1/1 (1/0)
BODY
  return $body;
}

sub ntf_body_0 {
  my $body   = <<"BODY";
Messages-Waiting: yes
Message-Account: sip:12345\@192.168.123.254
Voice-Message: 0/0 (0/0)
BODY
  return $body;
}

sub send_notify_for_subscribe {
	my ($hash,$peer,$req) = @_;
	my $subscribe = Net::SIP::Request->new($hash->{server}->{buf});
	my $body  = ntf_body_1;
	my $state = 'active;expires=3600';

	# read header
	my $callid = $subscribe->get_header('Call-ID');
	my $event  = $subscribe->get_header('Event');
	my $contact = $subscribe->get_header('Contact');

	# From/To and tags: SUBSCRIBE has From (with tag) and To (without tag)
	my $from_hdr = $subscribe->get_header('From');
	my $to_hdr   = $subscribe->get_header('To');
	my ($from_tag) = $from_hdr =~ /tag=([^;>\s]+)/;
	my ($to_tag)   = $to_hdr   =~ /tag=([^;>\s]+)/; # oft undef in incoming SUBSCRIBE

	# NOTIFY: From = (server), To = remote (client) with their tag
	my $server_tag = gen_tag();
	my $client_tag = $from_tag // gen_tag();

	# build  Request-URI: from Contact in SUBSCRIBE
	# contact can be "<sip:...>" or "sip:..."
# to be reworked!
	$contact =~ s/^\s+|\s+$//g;
	if ($contact =~ /^<(.+)>$/) { $contact = $1 }
	# remove parameters behind ;
	$contact =~ s/;.*//;
	my $req_uri = $contact;

	# CSeq: compute valid number monotonic > SUBSCRIBE's CSeq
	my $sub_cseq = $subscribe->get_header('CSeq') || '1 SUBSCRIBE';
	$sub_cseq =~ /^(\d+)/; my $sub_cseq_num = $1 || 1;
	my $notify_cseq = $sub_cseq_num + 1;

	my %hdr = (
			'Contact'            => sprintf('<%s>', 'sip:sipdev@192.168.123.219'),
			'From'               => sprintf('<%s>;tag=%s', 'sip:sipdev@192.168.123.219', $server_tag),
			'To'                 => sprintf('<%s>;tag=%s', $contact, $client_tag),
			'Call-ID'            => $callid,
			'CSeq'               => $notify_cseq . ' NOTIFY',
			'Event'              => $event,
			'Subscription-State' => $state,
			'Content-Type'       => ($body ? 'application/simple-message-summary' : 'text/plain'),
	);

  my $resp = Net::SIP::Request->new(
    'NOTIFY',
    $req_uri,
    \%hdr,
    $body,
  );
#  my $leg = $hash->{server}->{leg};
#  $leg->add_via($resp);
  sendmsg($hash,$peer,$resp->as_string);
  return;    
}

sub sendmsg {
  my ($hash,$peer,$msg) = @_;
  my $name = $hash->{NAME};

  if (!havepeer($hash,undef)) {
    return _log3($hash,1,"no peer registered");
  } elsif (!havepeer($hash,$peer)) {
    return _log3($hash,1,"$name: unknown peer >$peer<");
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
  
  my $req     = eval { Net::SIP::Packet->new( $hash->{server}->{buf} ) };
  return unless $req;

  (AttrVal($name,'logFullMessage',0))?
    _log3($hash,4,"in:\n".$req->as_string):
    _log3($hash,4,"in: ".(split(/\n/,$req->as_string))[0]);

  #my $method  = $req->method(); # not working as expected
    
  my $method =  $req->as_string;
  $method    =~ s/^([^ ]*) .*$/$1/s;

  if ($method ne "SIP/2.0") {
		(AttrVal($name,'showFullMessage',0))?
			readingsSingleUpdate($hash, lc($method), $req->as_string, 0):
			readingsSingleUpdate($hash, lc($method), (split(/\n/,$req->as_string))[0], 1);
  } elsif ($req->is_response) {
    return; # end processing if 200 OK received as response
  }

  my ($peer,$ip,$port) = FHEM::MiniSIP::Utils::extract_peer($hash,$req,0);

  if ($method eq 'REGISTER') {
    FHEM::MiniSIP::Utils::savepeer($hash,$req);
    if (AttrVal($name,'useAuth',0)) {
      # with authentication
      doAuth($hash,$peer,$req);
      return;
    }
  }

  if ($method eq 'MESSAGE') {
    message2reading($hash,$peer,$req);    
  }

  if ($method eq 'SUBSCRIBE') {
    $hash->{peers}{$peer}{subscribe} = $req;
    my $resp = $req->create_response(200, {}, '');
    sendmsg($hash,$peer,$resp->as_string);

    send_notify_for_subscribe($hash,$peer,$req);
    
    return;
  }
=pod
    my $req_uri = $req->get_header('contact');
    $req_uri    =~ s/;.*>/>/;
    my $from    = $req->get_header('from');
    my $to      = $req->get_header('to');
    my $cseq    = (split(/ /,$req->get_header('cseq')))[0] + 1;

    my ($from_peer,$from_uri,$from_tag) = $from =~ m/:(.*)@(.*)>.*=(.*)/;
    my ($to_peer,$to_uri,$to_tag) = $to =~ m/:(.*)@(.*)>(.*)/;

    my %hdr = (
      'Via'                => 'SIP/2.0/UDP 192.168.123.219:5060;branch=z9hG4bKserverbranch;rport',
      'Event'              => $req->get_header('event'),
      'Subscription-State' => 'active;expires=' . $req->get_header('expires'),
      'Max-Forwards'       => 70,
      'Call-ID'            => $req->get_header('call-id'),
      'CSeq'               => "$cseq NOTIFY",
      'Content-Type'       => $req->get_header('accept'),

      'From'               => sprintf('<sip:%s>;tag=%s', $hash->{server}{from}, $to_tag || 'serverTag'),
#      'To'                 => sprintf('<sip:%s>;tag=%s', "$from_peer\@$hash->{peers}{$peer}{peer_ip}", $from_tag),
      'To'                 => $from,
    );
    
    my $body   = <<"BODY";
Messages-Waiting: yes
Message-Account: sip:12345\@192.168.123.254
Voice-Message: 1/1 (1/0)
BODY
    
    my $notify = Net::SIP::Packet->new_from_parts('NOTIFY',$req_uri,\%hdr,$body);
    Debug $notify->as_string;
    sendmsg($hash,$peer,$notify->as_string);
    return;
  }
=cut   
       
=pod
    my $body   = <<"BODY";
Messages-Waiting: yes
Message-Account: sip:12345\@192.168.123.254
Voice-Message: 1/1 (1/0)
BODY
    $body =~ s/\n/\r\n/g;

    my %hdr = ( 'User-Agent'         => "custom-notify/1.0",
                'Event'              => "message-summary",
                'Subscription-State' => "active;expires=300",
                'Content-Type'       => "application/simple-message-summary",
              );

    my $resp = $req->new_from_parts("NOTIFY","sip:fritzbox7530ax\@192.168.123.254",\%hdr,$body);

    my $via = $req->get_header('via');
    $via =~ s/123.254:/123\.219:/;
    $resp->set_header('via',$via);
    my $to = $req->get_header('from');
    $to =~ s/123\.219/123\.254/;
    $resp->set_header('to',$to);

    $resp->set_header('contact','<sip:'.$hash->{server}{from}.';transport=udp>');
    $resp->set_header('from','<sip:'.$hash->{server}{from}.'>;tag=server12345');
    $resp->set_header('call-id',$req->get_header('call-id'));
    $resp->set_header('cseq',"1 NOTIFY");
    $resp->set_header('max-forwards',70);

#   my $toTag = $req->get_header('from');
#   my $toTag = m/tag=(.*)/;
#Debug $toTag;
=cut    
  
  if ($method eq 'INVITE') {
    if (AttrVal($name,'useAuth',0)) {
      # with authentication
      my $success = doAuth($hash,$peer,$req);
      invite2reading($hash,$req) if $success;
      return;
    } else {
      invite2reading($hash,$req);    
    }
  }

  my @known_methods = qw(REGISTER INVITE MESSAGE SUBSCRIBE BYE);
  if (contains_string($method,@known_methods)) {
    my $resp = $req->create_response(200, {'contact',$req->get_header('contact'),'expires',$req->get_header('expires')}, '');
    sendmsg($hash,$peer,$resp->as_string);
  }

  delete $hash->{server}->{buf};
}

1;

#

=pod
REGISTER — zur Bindung einer Adresse (Anmeldung) an einen Standort (Authentifizierung erforderlich).
INVITE — zum Aufbau von Sessions, insbesondere bei kostenpflichtigen/benutzerspezifischen Diensten.
MESSAGE / PUBLISH — für Signalisierung von Nachrichten/Status‑Updates, wenn Schutz nötig.
SUBSCRIBE / NOTIFY — bei Presence/Event‑Subscriptions (Zugriffssteuerung auf Events).

BYE / CANCEL — beim Beenden/Abbrechen von Sessions (bei dienstekritischen Szenarien).
UPDATE / INFO / PRACK / REINVITE — für Mid‑dialog Änderungen (Medienänderungen, Re‑INVITE für Hold/Resume).
OPTIONS — optional, wenn Informationen über Ressourcen nur authentifizierten Clients gezeigt werden.
REFER — für Call‑Transfer/Weiterleitungen, wenn nur berechtigte Nutzer Zielreferenzen setzen dürfen.
=cut