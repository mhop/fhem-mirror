##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::Socket::INET;
use MIME::Base64;

my %ext2MIMEType= qw{
  css   text/css
  gif   image/gif
  html  text/html
  ico   image/x-icon
  jpg   image/jpeg
  js    text/javascript
  pdf   application/pdf
  png   image/png
  svg   image/svg+xml
  txt   text/plain

};

sub
ext2MIMEType($) {
  my ($ext)= @_;
  return "text/plain" if(!$ext);
  my $MIMEType = $ext2MIMEType{lc($ext)};
  return ($MIMEType ? $MIMEType : "text/$ext");
}

sub
filename2MIMEType($) {
  my ($filename)= @_;
  $filename =~ m/^.*\.([^\.]*)$/;
  return ext2MIMEType($1);
}
  

##################
sub
urlEncode($) {
  $_= $_[0];
  s/([\x00-\x2F,\x3A-\x40,\x5B-\x60,\x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}

##################
sub
urlDecode($) {
  $_= $_[0];
  s/%([0-9A-F][0-9A-F])/chr(hex($1))/egi;
  return $_;
}

##################
# - if data (which is urlEncoded) is set, then a POST is performed, else a GET.
# - noshutdown must be set for e.g the Fritz!Box
# 4.0 is needed for some clients trying to reach fhem.de, 2.0 was not enough
sub
CustomGetFileFromURL($$@)
{
  my ($quiet, $url, $timeout, $data, $noshutdown, $loglevel) = @_;
  $timeout = 4.0 if(!defined($timeout));
  $loglevel = 4 if(!$loglevel);
  
  my $redirects= 0;
  
  RETRY:

  my $displayurl= $quiet ? "<hidden>" : $url;
  Log3 undef, $loglevel, "CustomGetFileFromURL url=$displayurl";
  if($url !~ /^(http|https):\/\/(([^:\/]+):([^:\/]+)@)?([^:\/]+)(:\d+)?(\/.*)$/) {
    Log3 undef, $loglevel, 
        "CustomGetFileFromURL $displayurl: malformed or unsupported URL";
    return undef;
  }
  
  my ($protocol,$authstring,$user,$pwd,$host,$port,$path) =
        ($1,$2,$3,$4,$5,$6,$7);
  
  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($protocol eq "https" ? 443: 80);
  }
  $path= '/' unless defined($path);

  my $auth64; 
  if(defined($authstring)) {
    $auth64 = encode_base64("$user:$pwd","");
  }

  my $conn;
  my $errstr= "";
  if($protocol eq "https") {
    eval "use IO::Socket::SSL";
    if($@) {
      Log3 undef, $loglevel, $@;
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  $errstr= $@ if(!$conn);
  if(!$conn) {
    Log3 undef, $loglevel, "CustomGetFileFromURL $displayurl: ".
                           "Can't connect to $protocol://$host:$port, $errstr"; 
    undef $conn;
    return undef;
  }

  $host =~ s/:.*//;
  my $hdr = ($data ? "POST" : "GET")." $path HTTP/1.0\r\nHost: $host\r\n";
  if(defined($authstring)) {
    $hdr .= "Authorization: Basic $auth64\r\n";
  }
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
      Log3 undef, $loglevel,
          "CustomGetFileFromURL $displayurl: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  my @header= split("\r\n", $1);
  my @header0= split(" ", shift @header);
  my $code= $header0[1];

  if(!defined($code) || $code eq "") {
    Log3 undef, $loglevel,
           "CustomGetFileFromURL $displayurl: empty answer received";
    return undef;
  }
  Log3 undef, $loglevel,
       "CustomGetFileFromURL $displayurl: HTTP Response code $code";

  if($code == 301 || $code == 302 || $code == 303) { # redirect
    if(++$redirects > 5) {
      Log3 undef, $loglevel,
           "CustomGetFileFromURL $displayurl: Too many redirects";

    } else {
      map { $url=$1 if($_ =~ m/Location:\s*(\S+)$/) } @header;
      Log3 undef, $loglevel, "CustomGetFileFromURL $displayurl: ".
          "Redirect to ".($quiet ? "<hidden>" : $url);
      goto RETRY;

    }
  }
  
  my $hostpath= $quiet ? "<hidden>" : $host . $path;
  Log3 undef, $loglevel,
        "CustomGetFileFromURL $displayurl: Got data, length: ".length($ret);
  if(!length($ret)) {
    Log3 undef, $loglevel,
        "CustomGetFileFromURL $displayurl: Zero length data, header follows...";
    for (@header) {
      Log3 undef, $loglevel, "CustomGetFileFromURL $displayurl: $_";
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
