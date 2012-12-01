##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::Socket::INET;

my %ext2MIMEType= qw{
  txt   text/plain
  html  text/html
  pdf   application/pdf
  css   text/css
  jpg   image/jpeg
  png   image/png
  gif   image/gif
  ico   image/x-icon
};

my $KNOWNEXTENSIONS= 'txt|html|pdf|css|jpg|png|gif|ico';

sub
ext2MIMEType($) {
  my ($ext)= @_;
  my $MIMEType= $ext ? $ext2MIMEType{$ext} : "";
  return $MIMEType ? $MIMEType : "";
}

sub
filename2MIMEType($) {
  my ($filename)= @_;
  $filename =~ m/^(.*)\.($KNOWNEXTENSIONS)$/;
  return ext2MIMEType($2);
}
  

##################
sub
urlEncode($) {
  $_= $_[0];
  s/([\x00-\x2F,\x3A-\x40,\x5B-\x60,\x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}

##################
# - if data (which is urlEncoded) is set, then a POST is performed, else a GET.
# - noshutdown must be set for e.g the Fritz!Box
# 4.0 is needed for some clients trying to reach fhem.de, 2.0 was not enough
sub
CustomGetFileFromURL($$@)
{
  my ($quiet, $url, $timeout, $data, $noshutdown) = @_;
  $timeout = 4.0 if(!defined($timeout));

  my $displayurl= $quiet ? "<hidden>" : $url;
  if($url !~ /^(http|https):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log 1, "CustomGetFileFromURL $displayurl: malformed or unsupported URL";
    return undef;
  }
  
  my ($protocol,$host,$port,$path)= ($1,$2,$3,$4);

  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($protocol eq "https" ? 443: 80);
  }
  $path= '/' unless defined($path);


  my $conn;
  if($protocol eq "https") {
    eval "use IO::Socket::SSL";
    if($@) {
      Log 1, $@;
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  if(!$conn) {
    Log 1, "CustomGetFileFromURL $displayurl: Can't connect to $protocol://$host:$port\n";
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
      Log 1, "CustomGetFileFromURL $displayurl: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  my @header= split("\r\n", $1);
  my $hostpath= $quiet ? "<hidden>" : $host . $path;
  Log 4, "CustomGetFileFromURL $displayurl: Got data, length: ".length($ret);
  if(!length($ret)) {
    Log 4, "CustomGetFileFromURL $displayurl: Zero length data, header follows...";
    for (@header) {
        Log 4, "CustomGetFileFromURL $displayurl: $_";
    }
  }
  undef $conn;
  return $ret;
}

##################
# Compatibility mode

sub
GetFileFromURL($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(0, $url, @a);
}

sub
GetFileFromURLQuiet($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(1, $url, @a);
}

sub
GetHttpFile($$)
{
  my ($host,$file) = @_;
  return GetFileFromURL("http://$host$file");
}


1;
