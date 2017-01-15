# $Id$

=pod
#
# Development history
#
# 2017-01-15 - first commit to ./contrib
# 2017-01-15 - added:   direct QR display after set
#              added:   attribute ga_qrSize
#              added:   FW_detailFn
#              added:   attribute ga_labelName
#              added:   reading lastCheck
#
#              removed: reading qr_url
#              added:   show link to qrcode and key for manual use
#                       in device details
#              added:   set command "revoke" to prevent overwrite
#                       of existing key
#              added:   attribute ga_showKey
#                       attribute ga_showLink
#              added:   function gAuth(<device>,<token>) for easy use
#
=cut

package main;
use strict;
use warnings;

## apt-get install libconvert-base32-perl libauthen-oath-perl libcrypt-urandom-perl

use Convert::Base32;
use Authen::OATH;
use URI::Escape;
use Crypt::URandom qw( urandom );


sub GoogleAuth_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}        = "GoogleAuth_Define";
  $hash->{DeleteFn}	    = "GoogleAuth_Delete";
  $hash->{SetFn}        = "GoogleAuth_Set";
  $hash->{GetFn}        = "GoogleAuth_Get";
  $hash->{FW_detailFn}  = "GoogleAuth_Detail";
#  $hash->{AttrFn}   = "GoogleAuth_Attr";
  $hash->{AttrList} = "ga_labelName ".
                      "ga_qrSize:100x100,200x200,300x300,400x400 ".
                      "ga_showKey:0,1 ".
                      "ga_showLink:0,1 ".
                      "$readingFnAttributes";
}

sub GoogleAuth_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  return "Usage: Use Google Authenticator"  if(@a != 2);

  Log3($hash,4,"googleAuth $name: defined");
  readingsSingleUpdate($hash,'state','defined',1);
  return undef;
}

sub GoogleAuth_Delete($$) {
  my ($hash,$name) = @_;
  setKeyValue("googleAuth$name",undef);
}

sub GoogleAuth_Set($$@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $usage = "Unknown argument, choose one of new:noArg revoke:noArg";

  if($cmd eq "new") {
    #SOURCE: https://blog.darkpan.com/article/6/Perl-and-Google-Authenticator.html
    return "Please revoke existing key first!" if defined(getKeyValue("googleAuth$name"));
    my $secret_bytes  = urandom(50);
    my $secret_base32 = encode_base32( $secret_bytes );
    Log3($hash,5,"googleAuth $name: secret_bytes=$secret_bytes");
    Log3($hash,5,"googleAuth $name: set secret_base32=$secret_base32");
    setKeyValue("googleAuth$name",$secret_base32); # write to fhem keystore
    readingsSingleUpdate($hash,'state','active',1);
  } elsif ($cmd eq "revoke") {
    setKeyValue("googleAuth$name",undef);
    readingsSingleUpdate($hash,'state','defined',1);
  } else { 
    return $usage 
  }
  return undef;
}

sub GoogleAuth_Get($$@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $usage = "Unknown argument, choose one of check";

  if ($cmd eq "check") {
    my $given_token = shift @args;
    return "Token missing!" unless (defined($given_token) && $given_token);

    $given_token   = _ga_make_token_6($given_token);
    Log3($hash,4,"googleAuth $name: given: $given_token");

    my $secret_base32 = getKeyValue("googleAuth$name"); # read from fhem keystore
    Log3($hash,5,"googleAuth $name: get secret_base32=$secret_base32");
    $secret_base32 = decode_base32($secret_base32);
    Log3($hash,5,"googleAuth $name: secret_bytes=$secret_base32");
           
	my $oath     = Authen::OATH->new;
    my @possible = map { _ga_make_token_6($oath->totp($secret_base32, $_)) } time-30, time, time+30;
    Log3($hash,4,"googleAuth $name: possible: ".join ' ',@possible);

    my $result = (grep /^$given_token$/, @possible) ? 1 : -1;
    readingsSingleUpdate($hash,'lastResult',$result,0);    
    Log3($hash,4,"googleAuth $name: result: $result");
    return $result;
  }
  return $usage;
}

sub GoogleAuth_Detail($@) {
  my ($FW_wname, $name, $room, $pageHash) = @_;
  my $qr_url = _ga_make_url($name);
  my $secret_base32 = getKeyValue("googleAuth$name"); # read from fhem keystore

#  my $qr_url = ReadingsVal($d,'qr_url',undef);
  return unless defined($qr_url);
  my $ret  = "<table>";
     $ret .= "<tr><td rowspan=2><a href=\"$qr_url\"><img src=\"$qr_url\"><\/a></td>";
     $ret .= "<td><br>&nbsp;<a href=\"$qr_url\">Link to QR code<\/a><\/td>"
       if AttrVal($name,'ga_showLink',0);
     $ret .= "</tr>";
     $ret .= "<tr><td>&nbsp;Key (for manual use):<br>&nbsp;$secret_base32</td><tr>"
       if AttrVal($name,'ga_showKey',0);
     $ret .= "</table>";
  return $ret;
}



# helper functions
sub _ga_make_url($) {
  my ($name)        = @_;
  my $label         = AttrVal($name,'ga_labelName',"FHEM Authentication $name");
  my $qrsize        = AttrVal($name,'ga_qrSize','200x200');
  my $secret_base32 = getKeyValue("googleAuth$name");
  return undef unless defined($secret_base32);
  my $url           = "otpauth://totp/$label?secret=$secret_base32";
  my $qr_url        = "https://chart.googleapis.com/chart?cht=qr&chs=$qrsize"."&chl=";
     $qr_url       .= uri_escape($url);
  return $qr_url;
}

sub _ga_make_token_6($) {
  my $token = shift;
  while (length $token < 6) {
    $token = "0$token";
  }
  return $token;
}

sub gAuth($$) {
  my($name,$token) = @_;
  return CommandGet(undef,"$name check $token");
}

1;

=pod
=item helper
=item summary    Module to use GoogleAuthnticator
=item summary_DE Modul zur Nutzung von GoogleAuthenticator
=begin html

<a name="GoogleAuthenticator"></a>
<h3>GoogleAuthenticator</h3>
<ul>
  Module to use GoogleAuthenticator.<br><br>
</ul>
<br>
=end html
=cut