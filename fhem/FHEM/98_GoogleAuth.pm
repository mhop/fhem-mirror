# $Id$

# License & technical informations
=for comment
#
################################################################
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#  Homepage:  http://www.fhem.de
#
################################################################
#
# Module 98_GoogleAuth.pm
# written by pandabaer_de, revised by betateilchen
#
# based on informations from this website
# https://blog.darkpan.com/article/6/Perl-and-Google-Authenticator.html
#
# requires additional perl modules
# Convert::Base32 Authen::OATH Crypt::URandom
#
# on Debian systems, use apt-get to install appropriate packages
# libconvert-base32-perl libauthen-oath-perl libcrypt-urandom-perl
#
################################################################
#
=cut

# Development history
=for comment
#
# 2017-01-15 - first commit to ./contrib
#
# 2017-01-15 - added:   direct QR display after set
#              added:   attribute ga_qrSize
#              added:   FW_detailFn
#              added:   attribute ga_labelName
#              added:   reading lastCheck
#              removed: reading qr_url
#              added:   show link to qrcode and key for manual use
#                       in device details
#              added:   set command "revoke" to prevent overwrite
#                       of existing key
#              added:   attribute ga_showKey
#                       attribute ga_showLink
#              added:   function gAuth(<device>,<token>) for easy use
#              added:   FW_summaryFn
#              added:   commandref documentation EN
#
# 2017-01-15 - published to FHEM
#              fixed:   problem on iOS if label contains spaces
#              added:   issuer=FHEM in qr-code
#
# 2017-01-16 - added:   attributes ga_showQR, ga_strictCheck
#              removed: FW_summaryFn (not really useful)
#
=cut

package main;
use strict;
use warnings;

use Convert::Base32;
use Authen::OATH;
use URI::Escape;
use Crypt::URandom qw( urandom );


sub GoogleAuth_Initialize {
  my ($hash) = @_;

  $hash->{DefFn}        = "GoogleAuth_Define";
  $hash->{DeleteFn}	    = "GoogleAuth_Delete";
  $hash->{SetFn}        = "GoogleAuth_Set";
  $hash->{GetFn}        = "GoogleAuth_Get";
  $hash->{FW_detailFn}  = "GoogleAuth_Detail";

  $hash->{AttrList} = "ga_labelName ".
                      "ga_qrSize:100x100,200x200,300x300,400x400 ".
                      "ga_showKey:0,1 ga_showLink:0,1 ga_showQR:1,0 ".
                      "ga_strictCheck:0,1 ".
                      "$readingFnAttributes";
}

sub GoogleAuth_Define {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  return "Usage: Use Google Authenticator"  if(@a != 2);

  Log3($hash,4,"googleAuth $name: defined");
  readingsSingleUpdate($hash,'state','defined',1);
  return;
}

sub GoogleAuth_Delete {
  my ($hash,$name) = @_;
  setKeyValue("googleAuth$name",undef);
}

sub GoogleAuth_Set {
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
  return;
}

sub GoogleAuth_Get {
  my ($hash, $name, $cmd, $given_token) = @_;
  my $usage = "Unknown argument, choose one of check";

  if ($cmd eq "check") {
    return "Token missing!" unless (defined($given_token) && $given_token);
    $given_token   = _ga_make_token_6($given_token);
    Log3($hash,4,"googleAuth $name: given: $given_token");

    my $secret_base32 = getKeyValue("googleAuth$name"); # read from fhem keystore
    Log3($hash,5,"googleAuth $name: get secret_base32=$secret_base32");
    $secret_base32 = decode_base32($secret_base32);
    Log3($hash,5,"googleAuth $name: secret_bytes=$secret_base32");
           
	my $oath     = Authen::OATH->new;
    my @possible;
    if (AttrVal($name,'ga_strictCheck',0) == 1) {
      @possible    = _ga_make_token_6($oath->totp($secret_base32));
    } else {
      @possible    = map { _ga_make_token_6($oath->totp($secret_base32, $_)) } time-30, time, time+30;
    }      
    Log3($hash,4,"googleAuth $name: possible: ".join ' ',@possible);

    my $result = (grep /^$given_token$/, @possible) ? 1 : -1;
    readingsSingleUpdate($hash,'lastResult',$result,0);    
    Log3($hash,4,"googleAuth $name: result: $result");
    return $result;
  }
  return $usage;
}

sub GoogleAuth_Detail {
  my ($FW_wname, $name, $room, $pageHash) = @_;
  my $qr_url = _ga_make_url($name);
  my $secret_base32 = getKeyValue("googleAuth$name"); # read from fhem keystore
  return unless defined($qr_url);
  my $ret  = "<table>";
     $ret .= "<tr><td rowspan=2>";
     $ret .= "<a href=\"$qr_url\"><img src=\"$qr_url\"><\/a>"
       if AttrVal($name,'ga_showQR',1);
     $ret .= "</td>";
     $ret .= "<td><br>&nbsp;<a href=\"$qr_url\">Link to QR code<\/a><\/td>"
       if AttrVal($name,'ga_showLink',0);
     $ret .= "</tr>";
     $ret .= "<tr><td>&nbsp;Key (for manual use):<br>&nbsp;$secret_base32</td><tr>"
       if AttrVal($name,'ga_showKey',0);
     $ret .= "</table>";
  return $ret;
}


# helper functions
sub _ga_make_url {
  my ($name)        = @_;
  my $label         = AttrVal($name,'ga_labelName',"FHEM Authentication $name");
     $label        =~ s/\s/\%20/g;
  my $qrsize        = AttrVal($name,'ga_qrSize','200x200');
  my $secret_base32 = getKeyValue("googleAuth$name");
  return unless defined($secret_base32);
  my $url           = "otpauth://totp/$label?secret=$secret_base32&issuer=FHEM";
  my $qr_url        = "https://chart.googleapis.com/chart?cht=qr&chs=$qrsize"."&chl=";
     $qr_url       .= uri_escape($url);
  return $qr_url;
}

sub _ga_make_token_6 {
  my $token = shift;
  while (length $token < 6) {
    $token = "0$token";
  }
  return $token;
}

sub gAuth {
  my($name,$token) = @_;
  return CommandGet(undef,"$name check $token");
}

1;

=pod
=item helper
=item summary    Module to use GoogleAuthenticator
=item summary_DE Modul zur Nutzung von GoogleAuthenticator
=begin html

<a name="GoogleAuth"></a>
<h3>GoogleAuth</h3>

<ul>
  GoogleAuthenticator provides two-factor-authentication using one-time-passwords (token).<br/>
  These tokens are generated using the mobile app „Google Authenticator“ for example on a smartphone.<br/>
  See <a href="https://en.wikipedia.org/wiki/Google_Authenticator">https://en.wikipedia.org/wiki/Google_Authenticator</a>
  for more informations.<br/>
  <br/>
  <br/>
  <b>Prerequesits</b><br/>
  <br/>

  <li>The fhem implementation of the Google Authenticator is credited to the following publication:<br/>
  <a href="https://blog.darkpan.com/article/6/Perl-and-Google-Authenticator.html">https://blog.darkpan.com/article/6/Perl-and-Google-Authenticator.html</a></li>
  <br/>

  <li>Module uses following additional Perl modules:<br/>
  <br/>
  <ul><code>Convert::Base32 Authen::OATH Crypt::URandom</code></ul>
  <br/>
  If not already installed in your environment, please install them using appropriate commands from your environment.<br/>
  <br/>
  Package installation in debian environments:<br/>
  <br/>
  <ul><code>apt-get install libconvert-base32-perl libauthen-oath-perl libcrypt-urandom-perl</code></ul></li>
  <br/>
  <br/>
  
  <a name="GoogleAuthdefine"></a>
  <b>Define</b><br/><br/>
  <ul>
    <code>define &lt;name&gt; GoogleAuth</code><br/>
    <br/>
    Example:<br/><br/>
    <ul><code>define googleAuth GoogleAuth</code><br/></ul>
  </ul>
  <br/>
  <br/>

  <a name="GoogleAuthset"></a>
  <b>Set Commands</b><br/><br/>
  <ul>
    <li><code>set &lt;name&gt; new</code><br/>
    <br/>
    Generates a new secret key and displays the corresponding QR image.<br/>
    Using the photo function of the Google Authenticator app,<br/>
    this QR image can be used to transfer the secret key to the app.
    </li>
    <br/>
    <li><code>set &lt;name&gt; revoke</code><br/>
    <br/>
    Remove existing key.<br/>
    <b>You can not create a new key before</b> an existing key was deleted.<br/>
    </li>
  </ul>
  <br/>
  <br/>

  <a name="GoogleAuthget"></a>
  <b>Get Commands</b><br/><br/>
  <ul>
    <li><code>get &lt;name&gt; check &lt;token&gt;</code><br/>
    <br/>
    Check the validity of a given token; return value is 1 for a valid token, otherwise -1.<br/>
    <ul>
    <li>Token always consists of six numerical digits and will change every 30 seconds.</li>
    <li>Token is valid if it matches one of three tokens calculated by FHEM<br/>
    using three timestamps: -30 seconds, now and +30 seconds.<br/>
    This behavior can be changed by attribute ga_strictCheck.</li>
    </ul>
    <br/>
    </li>
    <li><code>gAuth(&lt;name&gt;,&lt;token&gt;)</code><br/>
    <br/>
    For easy use in your own functions you can call function gAuth(),<br/>
    which will return same result codes as the "get" command.
    </li>
  </ul>
  <br/>
  <br/>

  <a name="GoogleAuthattr"></a>
  <b>Attributes</b><br/><br/>
  <ul>
    <li><b>ga_labelName</b> - define a Name to identify PassCode inside the app.<br/>
        <b>Do not use any special characters,</b> except SPACE, in this attribute!</li>
    <li><b>ga_qrSize</b> - select image size of qr code</li>
    <li><b>ga_showKey</b> - show key for manual use if set to 1</li>
    <li><b>ga_showLink</b> - show link to qr code if set to 1</li>
    <li><b>ga_showQR</b> - show qr code if set to 1</li>
    <li><b>ga_strictCheck</b><br/>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;AttrVal = 1 : check given token against one token<br/>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;AttrVal = 0 : check given token against three tokens(default)</li>
  </ul>
  <br/>
  <br/>

  <a name="GoogleAuthreadings"></a>
  <b>Generated Readings/Events</b><br/><br/>
  <ul>
    <li><b>lastResult</b> - contains result from last token check</li>
    <li><b>state</b> - "active" if a key is set, otherwise "defined"</li>
  </ul>
  <br/>
  <br/>

</ul>
=end html
=begin html_DE

<a name="GoogleAuth"></a>
<h3>GoogleAuth</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='commandref.html#GoogleAuth'>GoogleAuth</a><br/>
</ul>
=end html_DE

=cut