##############################################
# $Id: FritzBoxUtils.pm 1148 2011-12-28 19:21:19Z rudolfkoenig $
package main;

use strict;
use warnings;
use Digest::MD5 "md5_hex";
use HttpUtils;

my ($lastOkPw, $lastOkTime) =("", 0);

sub
FB_getPage($$$)
{
  my ($host, $pw, $page) = @_;
  my $data = GetFileFromURL("http://$host".
             "/cgi-bin/webcm?getpage=../html/login_sid.xml", undef, undef, 1);
  return undef if(!$data);
  my $chl;
  $chl = $1 if($data =~ /<Challenge>(\w+)<\/Challenge>/i);
  my $chlAnsw .= "$chl-$pw";
  $chlAnsw =~ s/(.)/$1.chr(0)/eg; # works probably only with ascii
  $chlAnsw = "$chl-".lc(md5_hex($chlAnsw));
  my @d = ( "login:command/response=$chlAnsw", "getpage=$page" );
  $data = join("&", map {join("=", map {urlEncode($_)} split("=",$_,2))} @d);
  return GetFileFromURL("http://$host/cgi-bin/webcm", undef, $data, 1);
}

sub
FB_checkPw($$)
{
  my ($host, $pw) = @_;
  my $now = time();

  return 1 if($lastOkPw eq $pw && ($now - $lastOkTime) < 300); # 5min cache

  my $data = FB_getPage($host, $pw, "../html/de/internet/connect_status.txt");

  if(defined($data) && $data =~ m/"checkStatus":/) {
    $lastOkPw = $pw; $lastOkTime = $now;
    return 1;

  } else {
    return 0;

  }
}

1;
