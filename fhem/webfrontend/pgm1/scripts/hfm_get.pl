#!/usr/bin/perl

use CGI;
use IO::Socket::INET;
use warnings;


$host="localhost:7072";

sub
getXmlList() {
  my $server = IO::Socket::INET->new(PeerAddr => $host);
  my $str = "";

  if ($server) {
    my $buf;
  
    syswrite($server, "xmllist; quit\n");
    while(sysread($server, $buf, 256) > 0) {
      $str .= $buf
    }
  } else {
    $str="<ERROR msg='Cannot connect to the server'/>\n";
  }
  return $str;
}

my $cgi = new CGI;
print $cgi->header( "-type" => "text/xml; charset=UTF-8",
                "-Expires" => "0",
                "-Cache-Control" => "no-chache",
                "-Pragma" => "no-cache"
               );

print "<?xml version='1.0'?>\n";
print getXmlList();

