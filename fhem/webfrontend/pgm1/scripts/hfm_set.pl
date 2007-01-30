#!/usr/bin/perl

use CGI;
use IO::Socket;
use warnings;

$host="localhost:7072";

sub setFs20($){
	my $cgi = shift;
  	my $name=$cgi->param("name");
    my $cmd=$cgi->param("cmd");
    return sendCommand("set $name $cmd");
}

sub setFht($){
	my $cgi = shift;
	my $name=$cgi->param("name");
	my $tempToSet=$cgi->param("tempToSet");
	my $degreeToSet=$cgi->param("degreeToSet");
	return sendCommand("set $name $tempToSet $degreeToSet");
}

sub sendCommand($) {
  my $cmd = shift;
  my $server;
  $server = IO::Socket::INET->new(PeerAddr => $host);
  if ($server) {
  	syswrite($server, "$cmd; quit\n");
  	return "<OK/>\n";
  } else {
    return "<ERROR msg='Cannot connect to the server'/>\n";
  }  
}


my $cgi = new CGI;

my $str="<ERROR msg='Unknown command'/>\n";
my $action=$cgi->param("action");

if ($action eq "setFS20") {
	$str = setFs20($cgi);
} 

if ($action eq "setFHT") {
	$str = setFht($cgi);
}

my $thinClient = $cgi->param("thinclient") || "false";

if ("true" eq $thinClient) {
	# No ajax, send redirect
	print $cgi->header( "-type" => "text/xml",
                "-Expires" => "0",
                "-Cache-Control" => "no-chache",
                "-Pragma" => "no-cache",               
				"-Status" => "302 Moved Temporarily",
				"-Location" => "/hfm/scripts/hfm_tc.pl"
	);
} else {
	print $cgi->header( "-type" => "text/xml",
                "-Expires" => "0",
                "-Cache-Control" => "no-chache",
                "-Pragma" => "no-cache"
               );

}

print "<?xml version='1.0'?>\n";
print $str;
	