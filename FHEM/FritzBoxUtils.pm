##############################################
# $Id$
package main;

use strict;
use warnings;
use Digest::MD5 "md5_hex";
use HttpUtils;

my ($lastOkPw, $lastOkHost, $lastOkTime) =("", "", 0);

sub
FB_doCheckPW($$)
{
  my ($host, $pw) = @_;
  my $data = GetFileFromURL("http://$host/login_sid.lua", undef, undef, 1);
  return undef if(!$data);

  my $chl;
  $chl = $1 if($data =~ /<Challenge>(\w+)<\/Challenge>/i);
  my $chlAnsw .= "$chl-$pw";
  $chlAnsw =~ s/(.)/$1.chr(0)/eg; # works probably only with ascii
  $chlAnsw = "$chl-".lc(md5_hex($chlAnsw));

  if($data =~ m/iswriteaccess/) {      # Old version
    my @d = ( "login:command/response=$chlAnsw",
              "getpage=../html/de/internet/connect_status.txt" );
    $data = join("&", map {join("=", map {urlEncode($_)} split("=",$_,2))} @d);
    $data = GetFileFromURL("http://$host/cgi-bin/webcm", undef, $data, 1);
    my $isOk = ($data =~ m/checkStatus/);
    return $isOk;

  } else {                            # FritzOS >= 5.50
    my @d = ( "response=$chlAnsw", "page=/login_sid.lua" );
    $data = join("&", map {join("=", map {urlEncode($_)} split("=",$_,2))} @d);
    $data = GetFileFromURL("http://$host/login_sid.lua", undef, $data, 1);
    my $sid = $1 if($data =~ /<SID>(\w+)<\/SID>/i);
    $sid = undef if($sid =~ m/^0*$/);
    return $sid;
  }
}

sub
FB_checkPw($$)
{
  my ($host, $pw) = @_;
  my $now = time();

  return 1 if($lastOkPw eq $pw && $lastOkHost eq $host && 
              ($now - $lastOkTime) < 300); # 5min cache

  if(FB_doCheckPW($host, $pw)) {
    $lastOkPw = $pw;
    $lastOkTime = $now;
    $lastOkHost = $host;
    return 1;

  } else {
    return 0;

  }
}


######## FB_mail ##################################################
# What  : Sends a mail
# Call  : { FB_mail('empfaenger@mail.de','Subject','text 123') }
# Source: http://www.fhemwiki.de/wiki/E-Mail_senden
# Prereq: - FB7390 needs fhem-installation from fhem.de; installation from AVM will _not_ work (chroot)
#         - In FritzBox, Push-Service needs to be active
sub 
FB_mail($$$)
{
  my ($rcpt, $subject, $text) = @_;
  my $tmpfile = "fhem_nachricht.txt";
  system("/bin/echo \'$text\' > \'$tmpfile\' ");
  system("/sbin/mailer send -i \"$tmpfile\" -s \"$subject\" -t \"$rcpt\"");
  system("rm \"$tmpfile\"");
  Log 3, "Mail sent to $rcpt";
}


######## FB_WLANswitch ############################################
# What  : Switches WLAN on or off
# Call  : { FB_WLANswitch("on") }
# Source: http://www.fhemwiki.de/wiki/Fritzbox:_WLAN_ein/ausschalten
sub
FB_WLANswitch($) {
 my $cmd = shift;
 my $ret = ""; 
 if ($cmd =~ m"on"i) {            # on or ON
  $ret .= "ATD: " . `echo "ATD#96*1*" | nc 127.0.0.1 1011` ;
  sleep 1 ;
  $ret .= " ATH: " . `echo "ATH" | nc 127.0.0.1 1011` ;
 }
 if ($cmd =~ m"off"i) {           # off or OFF
  $ret .= "ATD: " . `echo "ATD#96*0*" | nc 127.0.0.1 1011` ;
  sleep 1 ;
  $ret .= " ATH: " . `echo "ATH" | nc 127.0.0.1 1011` ;
 }
 $ret =~ s,[\r\n]*,,g;        # remove CR from return-string
 Log 4, "FB_WLANswitch($cmd) returned: $ret";
}

1;
