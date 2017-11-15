##############################################
# $Id$

package main;

use strict;
use warnings;
use Digest::MD5;
use HttpUtils;
use Data::Dumper;
sub TR064_Action($);

# Demo/Examples, result is written into the FHEM-log
# FHEM-Modules have to use TR064_Action directly
# { setKeyValue("TR064_user", "replaceMe") }
# { setKeyValue("TR064_password", "replaceMe") }
#
# { TR064Cmd("DeviceInfo:1", "GetSecurityPort") }
# { TR064Cmd("WANCommonInterfaceConfig:1", "GetCommonLinkProperties") }
# { TR064Cmd("Time:1", "GetInfo") }
# { TR064Cmd("X_AVM-DE_OnTel:1", "GetPhoneBook", {NewPhonebookID=>0}) }
# { TR064Cmd("X_AVM-DE_Homeauto:1", "GetGenericDeviceInfos", {NewIndex=>0}) }

sub
TR064Cmd($$;$)
{
  my ($serviceType, $action, $param) = @_;
  my $usr = getKeyValue("TR064_user");
  my $pwd = getKeyValue("TR064_password");
  TR064_Action({
    server => sprintf('http://%s:%s@fritz.box:49000', 
                      urlEncode($usr),urlEncode($pwd)),
    serviceType => "urn:dslforum-org:service:$serviceType",
    action => $action,
    param => $param,
    retFn => sub { Log 1, $_[1] ? $_[1] : Dumper($_[2]); }
  });

}

my $tr064_es   = "http://schemas.xmlsoap.org/soap/encoding/";
my $tr064_ns   = "http://schemas.xmlsoap.org/soap/envelope/";
my $tr064_auth = "http://soap-authentication.org/digest/2001/10/";

sub
TR064_Action($)
{
  my ($hash) = @_;

  my $retFn = sub {
    my ($hash, $err, $data) = @_;
    delete $hash->{callback};
    delete $hash->{data};
    delete $hash->{header};
    delete $hash->{httpheader};
    return &{$hash->{retFn}}($hash, $err, $data);
  };

  $hash->{digest} = 1;
  if(!$hash->{control_url} || !$hash->{control_url}{$hash->{serviceType}}) {
    $hash->{url} = $hash->{server}."/tr64desc.xml";
    $hash->{callback} = sub($$$) {
      my ($par, $err, $data) = @_;
      return &$retFn($hash, "GET tr64desc.xml: $err") if($err);
      my $pattern = "\<serviceType\>(.*?)\<\/serviceType\>.*?"
                  . "\<controlURL\>(.*?)\<\/controlURL\>";
      $data =~ s/$pattern/$hash->{control_url}{$1} = $2/sge;
      if(!$hash->{control_url} || !$hash->{control_url}{$hash->{serviceType}}) {
        return &$retFn($hash,"$hash->{server} offers no $hash->{serviceType}");
      }
      TR064_Action($hash);
    };
    return HttpUtils_NonblockingGet($hash);
  }

  my $param="";
  $param = join("", map {"<$_>$hash->{param}{$_}</$_>"} keys %{$hash->{param}})
    if($hash->{param});

  $hash->{data} = <<EOD;
    <?xml version="1.0" encoding="utf-8"?>
    <s:Envelope s:encodingStyle="$tr064_es" xmlns:s="$tr064_ns">
      <s:Body>
        <u:$hash->{action} xmlns:u="$hash->{serviceType}">
          $param
        </u:$hash->{action}>
      </s:Body>
    </s:Envelope>
EOD

  $hash->{url} = $hash->{server}.$hash->{control_url}{$hash->{serviceType}};
  $hash->{method} = "POST";
  $hash->{header} = "SOAPACTION: $hash->{serviceType}#$hash->{action}\r\n".
                    "Content-Type: text/xml; charset=utf-8";

  $hash->{callback} = sub($$$) {
    my ($par, $err, $data) = @_;
    return &$retFn($hash, "POST $err") if($err);
    my %ret; # Quick&Dirty: Extract Tags, 1st. level only
    $data =~ s/.*<s:Body>//s;
    $data =~ s,<([^\n\r/>]+)>([^<\n\r]+)<,$ret{$1}=$2;,ge;
    return &$retFn($hash, undef, \%ret);
  };
  return HttpUtils_NonblockingGet($hash);
}
 
1;
