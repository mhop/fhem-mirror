#!/usr/bin/perl

use XML::XSLT;
use CGI;
use warnings;
use IO::Socket::INET;

my $host="localhost:7072";
my $xsl="/home/httpd/cgi-bin/xsl/hfm_tc.xsl";

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
print $cgi->header( "-type" => "text/html", 
                "-Expires" => "0",
                "-Cache-Control" => "no-chache",
                "-Pragma" => "no-cache"
                );                


my $xml=getXmlList();

my $xslt = XML::XSLT->new ($xsl, warnings => 1);

$xslt->transform ($xml);
print $xslt->toString;
$xslt->dispose();




