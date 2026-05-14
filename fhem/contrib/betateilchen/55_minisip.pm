# $Id$

package minisip;
use strict;
use warnings;
use Socket;
use IO::Socket::INET;
use Time::HiRes qw(time);
use GPUtils qw(GP_Import);

# Import from main context
BEGIN {
	GP_Import(
	 qw(readingFnAttributes
	    defs
			selectlist
			Debug
		  Log3
		  AttrVal
		  readingsBeginUpdate
      readingsBulkUpdate
      readingsEndUpdate)
	);
}

sub main::minisip_Initialize {
	goto &Initialize;
}

our %location;
our $ip;
our $contact;
our $to;

sub Initialize($) {
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
  my @a = split("[ \t][ \t]*", $def);
  my $port = $a[2] || 5060;
  my $sock = IO::Socket::INET->new(
    LocalPort => $port,
    Proto     => 'udp',
    Reuse     => 1,
 #   Blocking  => 0
  );
  return "can't create socket" unless $sock;
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
  my $peer;
  my $buf;
  my $bytes = $sock->recv($buf, 4096);
  if (defined $bytes) {
    _process($hash,$bytes,$buf);
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

sub _sender_ip {
  my $headers = shift;
  $contact = _header("Contact",$headers);
  my $s;
  $s=$contact;
  $s=~s/^.*\@(\d+(\.\d+){3})\D.*$/$1/s;
  return $s;
}

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
  }
  
  my $sock = new IO::Socket::INET (
    PeerAddr =>$ip, 
    PeerPort => '5060',
    Proto => 'udp');
  die "Could not create socket: $!\n" unless $sock;
  print $sock $msg;
  close($sock);
}

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

  my $payload = "\n\nk=18\nn=**18\nc=on\no=red\nl=Ventilator\n";
  my $clen = length($payload); $clen++;
  push(@msg,"Content-Length: $clen$payload");

  _send_msg($hash,$ip,"",join("\n",@msg),"");

}


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

  if($method eq "REGISTER") {
    _save($headers);
    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");
  }

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

#  if($method eq "MESSAGE") {
#    readingsBulkUpdate($hash, "lastMsgIn", $infoline);
#    my $msg=$headers;
#    $msg=~s/\nContent-Type:[^\n]*\n/\n/s;
#    $msg=~s/\nContent-Length:[^\n]*\n/\n/s;
##    _send_msg($hash,$ip,"SIP/2.0 500 Error",$msg,"");
#    _send_msg($hash,$ip,"SIP/2.0 200 OK",$headers,"");
#  }

  if($method eq "ACK") {

  }
}

1;

#
