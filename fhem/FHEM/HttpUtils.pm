##############################################
# $Id: HttpUtils.pm 1148 2011-12-28 19:21:19Z rudolfkoenig $
package main;

use strict;
use warnings;
use IO::Socket::INET;

##################
sub
urlEncode($) {
  $_= $_[0];
  s/([\x00-\x2F,\x3A-\x40,\x5B-\x60,\x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}


##################
# if data (which is urlEncoded) is set, then a POST is performed, else a GET
# noshutdown must be set for e.g the Fritz!Box
sub
GetFileFromURL($@)
{
  my ($url, $timeout, $data, $noshutdown) = @_;
  $timeout = 2.0 if(!defined($timeout));

  if($url !~ /^(http):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log 1, "GetFileFromURL $url: malformed URL";
    return undef;
  }
  
  my ($protocol,$host,$port,$path)= ($1,$2,$3,$4);

  if(defined($port)) {
    $port=~ s/^://;
  } else {
    $port= 80;
  }
  $path= '/' unless defined($path);

  if($protocol ne "http") {
    Log 1, "GetFileFromURL $url: invalid protocol";
    return undef;
  }

  my $conn = IO::Socket::INET->new(PeerAddr => "$host:$port");
  if(!$conn) {
    Log 1, "GetFileFromURL: Can't connect to $host:$port\n";
    undef $conn;
    return undef;
  }
  $host =~ s/:.*//;
  my $hdr = ($data ? "POST" : "GET")." $path HTTP/1.0\r\nHost: $host\r\n";
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/x-www-form-urlencoded";
  }
  $hdr .= "\r\n\r\n";
  syswrite $conn, $hdr;
  syswrite $conn, $data if(defined($data));
  shutdown $conn, 1 if(!$noshutdown);

  my ($buf, $ret) = ("", "");
  $conn->timeout($timeout);
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $conn->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $timeout);
    if($nfound <= 0) {
      Log 1, "GetFileFromURL: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  Log 4, "GetFileFromURL: Got http://$host$path, length: ".length($ret);
  undef $conn;
  return $ret;
}

1;
