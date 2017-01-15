# $Id$

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
  $hash->{AttrList} = "ga_qrsize ".
                      "ga_labelName ".
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

sub GoogleAuth_Delete() {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  setKeyValue("googleAuth$name",undef);
}

sub GoogleAuth_Set($$@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $usage = "Unknown argument, choose one of new:noArg";

  if($cmd eq "new") {
    #SOURCE: https://blog.darkpan.com/article/6/Perl-and-Google-Authenticator.html
    my $secret_bytes  = urandom(50);
    my $secret_base32 = encode_base32( $secret_bytes );
    Log3($hash,5,"googleAuth $name: secret_bytes=$secret_bytes");
    Log3($hash,5,"googleAuth $name: set secret_base32=$secret_base32");

    setKeyValue("googleAuth$name",$secret_base32); # write to fhem keystore

    my $label  = AttrVal($name,'ga_labelName',"FHEM Authentication $name");
    my $qrsize = AttrVal($name,'ga_qrsize','200x200');
    my $url    = "otpauth://totp/$label?secret=$secret_base32";
    my $qr_url = "https://chart.googleapis.com/chart?cht=qr&chs=$qrsize"."&chl=".uri_escape($url);

    readingsSingleUpdate($hash,'qr_url',$qr_url,0);
    readingsSingleUpdate($hash,'state','active',1);
    return undef;
  }
  return $usage;
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
    Log3($hash,4,"googleAuth $name: result: $result");
    return $result;
  }
  return $usage;
}

sub GoogleAuth_Detail($@) {
  my ($FW_wname, $d, $room, $pageHash) = @_;
  my $qr_url = ReadingsVal($d,'qr_url',undef);
  return unless defined($qr_url);
  my $ret = "<a href=\"$qr_url\"><img src=\"$qr_url\"><\/a><br>";
  return $ret;
}



# helper functions

sub _ga_make_token_6($) {
  my $token = shift;
  while (length $token < 6) {
    $token = "0$token";
  }
  return $token;
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