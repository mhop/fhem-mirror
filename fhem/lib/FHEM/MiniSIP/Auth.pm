# $Id$

################################################################
#
#  Copyright notice
#
#  (c) 2026 - today
#  Copyright: betateilchen (betateilchen dot quantentunnel dot de)
#  All rights reserved
#
#  This program is part of FHEM; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License V2.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
#  See the GNU General Public License V2 for more details.
#
################################################################

package FHEM::MiniSIP::Auth;

use strict;
use warnings;
use Data::Dumper;
use JSON::XS;

use MIME::Base64;
use Digest::MD5 qw(md5_hex);

use Net::SIP;
use Net::SIP::Packet;
use Net::SIP::Request;
use Net::SIP::Response;

use FHEM::Core::MiniSIP  qw ( sendmsg );
use FHEM::MiniSIP::Utils qw ( _log3 );

use Exporter ('import');
our @EXPORT_OK = qw( doAuth 
                     user_add 
                     user_delete 
                     user_list
                   );
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

use GPUtils         qw(:all);
BEGIN {
    GP_Import( qw(
        data
        Debug
        getKeyValue
        setKeyValue
        json2nameValue
        toJSON
      )
    );
};

my $p = __PACKAGE__;
$::data{modules}{version}{$p} = 
'$Id$';

my $REALM     = "FHEM.SIP";
my $NONCE_TTL = 300; # seconds

sub parse_digest {
	my ($str) = @_;
	return {} unless defined $str;
	my %h;
	# remove leading "Digest " falls vorhanden
	$str =~ s/^\s*Digest\s+//i;
	while ($str =~ m/(\w+)=("(?:[^"\\]|\\.)*"|[^,]*)/g) {
		my ($k,$v) = ($1,$2);
		$v =~ s/^"(.*)"$/$1/;
		$v =~ s/\\(["\\])/$1/g;
		$h{$k} = $v;
	}
	return \%h;
}

sub make_nonce {
  my $secret = rand() . $$ . time();
  my $raw    = md5_hex(time() . $secret . rand());
  my $nonce  = encode_base64($raw, '');
  $data{minisip}{nonce}{$nonce} = time();
  my $n = $data{minisip}{nonce};
  foreach my $key (keys %{$n}) {
    delete $data{minisip}{nonce}{$key} if ( time() - $data{minisip}{nonce}{$key} > $NONCE_TTL );
  }
  return $nonce;
}

sub send_401_nonce {
  my ($hash,$peer,$req) = @_;
  my $nonce = make_nonce();
  my $err = 401;
  my %hdr = (
    'Proxy-Authenticate' => qq{Digest realm="$REALM",nonce="$nonce",algorithm=MD5,qop="auth"}
	);
	my $response = $req->create_response($err, \%hdr, '');
	sendmsg($hash,$peer,$response->as_string);
}

sub valid_nonce {
  my ($nonce) = @_;
  return 0 unless defined $nonce;
  return 0 unless exists($data{minisip}{nonce}{$nonce});
  my $created = $data{minisip}{nonce}{$nonce};
  return 0 if time() - $created > $NONCE_TTL;
  return 1;
}

sub compute_response {
  my ($ha1, $method, $uri, $nonce, $nc, $cnonce, $qop) = @_;
  my $ha2 = md5_hex("$method:$uri");
  my $resp;
  if (defined $qop && length $qop) {
    $resp = md5_hex("$ha1:$nonce:$nc:$cnonce:$qop:$ha2");
  } else {
    $resp = md5_hex("$ha1:$nonce:$ha2");
  }
  return lc $resp;
}

sub doAuth {
  my($hash,$peer,$req)  = @_;
  my $method      = $req->method;
  my $auth_header = $req->get_header('Proxy-Authorization') || $req->get_header('Proxy-Authorization');
  my $digest      = parse_digest($auth_header // '');

	# No authorization header: send 401 with Proxy-Authenticate
  unless ($digest && $digest->{username}) {
    send_401_nonce($hash,$peer,$req);
		return;
	}

	my $nonce = $digest->{nonce};
	unless (valid_nonce($nonce)) {
		# nonce expired -> 401 with nonce
    send_401_nonce($hash,$peer,$req);
		return;
	}

	my $username = $digest->{username};
	my $uri      = $digest->{uri} || $req->uri;
	my $response = $digest->{response};
	my $nc       = $digest->{nc} || '';
	my $cnonce   = $digest->{cnonce} || '';
	my $qop      = $digest->{qop} || '';

	my $ha1 = get_ha1($hash,$username);
	unless ($ha1) {
	  # unknown user -> 403
		my $response = $req->create_response(403, 'Unknown user', {}, '');
		sendmsg($hash,$peer,$response->as_string);
		return;
	}

  my $expected = compute_response($ha1, $method, $uri, $nonce, $nc, $cnonce, $qop);
  if (lc($expected) eq lc($response)) {
    # Auth success - proceed processing (e.g. 200 OK)
    my $resp = $req->create_response(200, 
                                       { 'contact',$req->get_header('contact'),
                                         'expires',$req->get_header('expires') },
                                       '');
		sendmsg($hash,$peer,$resp->as_string);
    delete $hash->{server}->{buf};
  	return 1;
  } else {
    # wrong credentials -> 401
    send_401_nonce($hash,$peer,$req);
		return;
  }
}

sub get_ha1 {
  my ($hash,$username) = @_;
  my $name  = $hash->{NAME};
  return unless defined $username;
  my $users = getKeyValue($name."_users");
  $users    = json2nameValue($users);
  my $ha1   = $users->{$username};
  return $ha1 ? $ha1 : undef;
}

sub user_add {
  my ($hash,$username,$password) = @_;
  my $name = $hash->{NAME};
  my $ha1 = md5_hex("$username:$REALM:$password");

  my $users = getKeyValue($name."_users");
  $users  //= "{}";
  $users    = decode_json($users);
  $users->{$username} = $ha1;
  $users    = encode_json($users);
  setKeyValue($name."_users",$users);
  return "user $username added";
}

sub user_delete {
  my ($hash,$username) = @_;
  my $name = $hash->{NAME};

  my $users = getKeyValue($name."_users");
  $users    = json2nameValue($users);
  delete $users->{$username} if exists($users->{$username});
  $users    = toJSON($users);
  setKeyValue($name."_users",$users);
  return "user $username deleted";
}

sub user_list {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $users = getKeyValue($name."_users");
  return "no users found" unless $users;
  $users    = decode_json($users);
  return (join("\n",(sort (keys %{$users}))));
}

1;


__END__
