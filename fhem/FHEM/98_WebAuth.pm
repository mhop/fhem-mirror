##############################################
# $Id$
#
# WebAuth
# authenticate FHEMWEB requests based on HTTP headers
#
# Author: Sidey
# Version: 0.3.0
#
package main;

use strict;
use warnings;

use Socket ();

use FHEM::Core::Authentication::HeaderPolicy qw(
  evaluate_header_auth_policy
  parse_header_auth_policy
  validate_header_auth_policy
);

our $VERSION = '0.3.0';

#####################################
sub WebAuth_Initialize {
  my ($hash) = @_;

  $hash->{DefFn} = \&FHEM::WebAuth::Define;
  $hash->{AuthenticateFn} = \&FHEM::WebAuth::Authenticate;
  $hash->{AttrFn} = \&FHEM::WebAuth::Attr;
  $hash->{RenameFn} = \&FHEM::WebAuth::Rename;
  $hash->{UndefFn} = \&FHEM::WebAuth::Undef;

  no warnings 'qw';
  my @attrList = qw(
    disable:1,0
    disabledForIntervals
    headerAuthPolicy:textField-long
    noCheckFor
    trustedProxy:textField-long
    reportAuthAttempts
    strict:1,0
    validFor:
  );
  $attrList[-1] .= join(",", devspec2array("TYPE=FHEMWEB"));
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
}


package FHEM::WebAuth;

#####################################
sub Define {
  my ($hash, $def) = @_;
  my @l = split(" ", $def);

  return "Wrong syntax: use define <name> WebAuth" if(int(@l) != 2);

  $main::auth_refresh = 1;
  $hash->{".validFor"} = () if(!$hash->{OLDDEF});
  main::readingsSingleUpdate($hash, "state", "validFor:", 0);
  main::SecurityCheck() if($main::init_done);
  return;
}

sub Undef {
  $main::auth_refresh = 1;
  return;
}

sub Rename {
  $main::auth_refresh = 1;
  return;
}

#####################################
# Return
# - 0 for authentication not needed
# - 1 for auth-ok
# - 2 for wrong username/password
# - 3 authentication not needed this time (FHEMWEB special)
sub Authenticate {
  my ($me, $cl, $param) = @_;
  my $aName = $me->{NAME};
  my $path = (ref($param) eq 'HASH' && defined($param->{_Path})) ? $param->{_Path} : '<undef>';

  my $doReturn = sub($;$){
    my ($r,$a) = @_;
    $cl->{AuthenticatedBy} = $aName if($r == 1);
    $cl->{AuthenticationDeniedBy} = $aName if($r == 2 && $a);
    if($me->{doReport} && $cl->{PEER}) {
      my $peer = "$cl->{SNAME}:$cl->{PEER}:$cl->{PORT}";
      main::DoTrigger($aName, "accepting connection from $peer")
        if($r != 2 && $me->{doReport} & 1);
      main::DoTrigger($aName, "denying connection from $peer")
        if($r == 2 && $me->{doReport} & 2);
    }
    return $r;
  };

  if($me->{disabled} && main::IsDisabled($aName)) {
    main::Log3 $aName, 5, "$aName: skipping authentication for path=$path because device is disabled";
    return 0;
  }
  if($cl->{TYPE} ne "FHEMWEB") {
    main::Log3 $aName, 5, "$aName: skipping authentication for path=$path because client type is ".($cl->{TYPE} // '<undef>');
    return 0;
  }

  my $vName = $cl->{SNAME} ? $cl->{SNAME} : $cl->{NAME};
  if(!$me->{".validFor"}{$vName}) {
    main::Log3 $aName, 5, "$aName: skipping authentication for path=$path because frontend=$vName is not covered by validFor";
    return 0;
  }
  if(!$me->{".headerAuthPolicy"}) {
    main::Log3 $aName, 5, "$aName: skipping authentication for path=$path because no headerAuthPolicy is configured";
    return 0;
  }

  if(!$param) {
    main::Log3 $aName, 5, "$aName: denying path=$path because no request headers were provided";
    return &$doReturn(2);
  }

  my ($excRaw, $exc) = _GetStoredRegex($me, $aName, "noCheckFor");
  if($exc && $param->{_Path} =~ $exc) {
    main::Log3 $aName, 5, "$aName: bypassing authentication for path=$path due to noCheckFor";
    return 3;
  }

  my ($trustedProxy, $trustedProxyRe) = _GetStoredRegex($me, $aName, "trustedProxy");
  if($trustedProxy) {
    my ($trustedProxyMatched, $peerHostname) = _TrustedProxyMatches($cl->{PEER}, $trustedProxyRe, $trustedProxy);
    if(!$trustedProxyMatched) {
      main::Log3 $aName, 5,
        "$aName: proxy mismatch for path=$path peer=".(defined($cl->{PEER}) ? $cl->{PEER} : '<undef>').
        " peerHostname=".(defined($peerHostname) ? $peerHostname : '<undef>')." trustedProxy=$trustedProxy";
      return &$doReturn(0);
    }
    main::Log3 $aName, 5,
      "$aName: trusted proxy matched for path=$path peer=$cl->{PEER}".
      (defined($peerHostname) ? " peerHostname=$peerHostname" : '');
  }

  my %effectiveHeaders = %{$param};
  my $clientIp = $cl->{PEER};
  $effectiveHeaders{"X-FHEM-Client-IP"} = $clientIp if(defined($clientIp) && $clientIp ne '');

  if($trustedProxy) {
    my $forwardedIp = _ExtractForwardedClientIP($param);
    $effectiveHeaders{"X-FHEM-Forwarded-Client-IP"} = $forwardedIp
      if(defined($forwardedIp) && $forwardedIp ne '');
    $effectiveHeaders{"X-FHEM-Trusted-Proxy-IP"} = $clientIp
      if(defined($clientIp) && $clientIp ne '');
    main::Log3 $aName, 5,
      "$aName: effective client context for path=$path peer=".(defined($clientIp) ? $clientIp : '<undef>').
      " forwarded=".(defined($forwardedIp) ? $forwardedIp : '<undef>');
  }

  main::Log3 $aName, 5,
    "$aName: relevant headers for path=$path: "._SummarizeRelevantHeaders($me->{".headerAuthPolicy"}, \%effectiveHeaders);

  if(!_HasRelevantHeaders($me->{".headerAuthPolicy"}, \%effectiveHeaders)) {
    if(main::AttrVal($aName, "strict", 1)) {
      main::Log3 $aName, 5, "$aName: denying path=$path because no relevant policy headers were present and strict=1";
      $cl->{".httpAuthHeader"} = "HTTP/1.1 403 Forbidden\r\n";
      return &$doReturn(2, "headerAuthPolicy");
    }
    main::Log3 $aName, 5, "$aName: returning not-responsible for path=$path because no relevant policy headers were present and strict=0";
    return &$doReturn(0);
  }
  delete $cl->{".httpAuthHeader"};

  my ($ok, $error) = FHEM::Core::Authentication::HeaderPolicy::evaluate_header_auth_policy(
    $me->{".headerAuthPolicy"},
    \%effectiveHeaders
  );
  if($error) {
    main::Log3 $aName, 1, "$aName: headerAuthPolicy evaluation failed: $error";
    main::Log3 $aName, 5, "$aName: denying path=$path because policy evaluation returned an error";
    $cl->{".httpAuthHeader"} = "HTTP/1.1 403 Forbidden\r\n";
    return &$doReturn(2, "headerAuthPolicy");
  }

  if($ok) {
    main::Log3 $aName, 5, "$aName: authentication succeeded for path=$path via headerAuthPolicy";
    return &$doReturn(1, "headerAuthPolicy");
  }

  main::Log3 $aName, 5, "$aName: denying path=$path because relevant headers were present but headerAuthPolicy did not match";
  $cl->{".httpAuthHeader"} = "HTTP/1.1 403 Forbidden\r\n";
  return &$doReturn(2, "headerAuthPolicy");
}

sub _SummarizeRelevantHeaders {
  my ($policy, $headers) = @_;

  return '<no-policy>' if(ref($policy) ne 'HASH');
  return '<no-headers>' if(ref($headers) ne 'HASH');

  my %wanted;
  _CollectPolicyHeaders($policy, \%wanted);

  my @summary;
  foreach my $name (sort keys %wanted) {
    my $value = _HeaderValue($headers, $name);
    $value = '<absent>' if(!defined($value));
    $value = _MaskSensitiveHeaderValue($name, $value);
    push @summary, "$name=$value";
  }

  foreach my $synthetic (qw(X-FHEM-Client-IP X-FHEM-Forwarded-Client-IP X-FHEM-Trusted-Proxy-IP)) {
    next if(!$wanted{$synthetic} && !_HeaderValue($headers, $synthetic));
    my $value = _HeaderValue($headers, $synthetic);
    $value = '<absent>' if(!defined($value));
    push @summary, "$synthetic=$value";
  }

  return @summary ? join(', ', @summary) : '<no-policy-headers>';
}

sub _MaskSensitiveHeaderValue {
  my ($name, $value) = @_;

  return $value if(!defined($value) || $value eq '<absent>');

  return '<redacted>' if($name =~ m/^(?:authorization|cookie|set-cookie)$/i);

  if($name =~ m/^x-client-cert-serial$/i) {
    return '<redacted>' if(length($value) <= 4);
    return ('*' x (length($value) - 4)) . substr($value, -4);
  }

  return $value;
}

sub _CollectPolicyHeaders {
  my ($node, $headers) = @_;

  return if(ref($node) ne 'HASH' || ref($headers) ne 'HASH');

  if(exists $node->{op}) {
    foreach my $item (@{$node->{items}}) {
      _CollectPolicyHeaders($item, $headers);
    }
    return;
  }

  $headers->{$node->{header}} = 1 if(defined($node->{header}));
}

sub _HasRelevantHeaders {
  my ($node, $headers) = @_;

  return 0 if(ref($node) ne 'HASH' || ref($headers) ne 'HASH');

  if(exists $node->{op}) {
    foreach my $item (@{$node->{items}}) {
      return 1 if(_HasRelevantHeaders($item, $headers));
    }
    return 0;
  }

  foreach my $headerName (keys %{$headers}) {
    next if(!defined($headerName));
    return 1 if(lc($headerName) eq lc($node->{header}));
  }

  return 0;
}

sub _ExtractForwardedClientIP {
  my ($headers) = @_;

  return undef if(ref($headers) ne 'HASH');

  my $forwarded = _HeaderValue($headers, 'Forwarded');
  if(defined($forwarded) && $forwarded ne '') {
    foreach my $element (split(/\s*,\s*/, $forwarded)) {
      next if(!defined($element) || $element eq '');
      if($element =~ m/(?:^|;)\s*for=(?:"?)([^";,]+)(?:"?)/i) {
        my $ip = $1;
        $ip =~ s/^\[//;
        $ip =~ s/\]$//;
        $ip =~ s/:\d+$// if($ip !~ m/^\d{1,3}(?:\.\d{1,3}){3}$/);
        return $ip if($ip ne '');
      }
    }
  }

  my $xff = _HeaderValue($headers, 'X-Forwarded-For');
  if(defined($xff) && $xff ne '') {
    my ($ip) = split(/\s*,\s*/, $xff, 2);
    return undef if(!defined($ip));
    $ip =~ s/^\s+//;
    $ip =~ s/\s+$//;
    $ip =~ s/^"//;
    $ip =~ s/"$//;
    $ip =~ s/^\[//;
    $ip =~ s/\]$//;
    $ip =~ s/:\d+$// if($ip !~ m/^\d{1,3}(?:\.\d{1,3}){3}$/);
    return $ip if($ip ne '');
  }

  return undef;
}

sub _TrustedProxyMatches {
  my ($peer, $trustedProxyRe, $trustedProxy) = @_;

  return (0, undef) if(!defined($peer) || $peer eq '' || !defined($trustedProxyRe) || !defined($trustedProxy) || $trustedProxy eq '');
  return (1, undef) if($peer =~ $trustedProxyRe);

  my $peerHostname = _ResolvePeerHostname($peer);
  return (1, $peerHostname) if(defined($peerHostname) && $peerHostname =~ $trustedProxyRe);

  my $normalizedPeer = _NormalizeIPAddress($peer);
  foreach my $hostname (_LiteralTrustedProxyHostnames($trustedProxy)) {
    foreach my $resolvedIp (_ResolveHostnameToIPs($hostname)) {
      next if(!defined($resolvedIp));
      return (1, $peerHostname) if(defined($normalizedPeer) && $normalizedPeer eq _NormalizeIPAddress($resolvedIp));
    }
  }

  return (0, $peerHostname);
}

sub _ResolvePeerHostname {
  my ($peer) = @_;

  my ($family, $packedAddress) = _ParseIPAddress($peer);
  return undef if(!defined($family) || !defined($packedAddress));

  my $hostname = gethostbyaddr($packedAddress, $family);
  return undef if(!defined($hostname) || $hostname eq '');

  return lc($hostname);
}

sub _LiteralTrustedProxyHostnames {
  my ($trustedProxy) = @_;

  return () if(!defined($trustedProxy));

  my $candidate = $trustedProxy;
  $candidate =~ s/\A\^//;
  $candidate =~ s/\$\z//;

  return () if($candidate !~ m/\A(?:[A-Za-z0-9-]+\.)*[A-Za-z0-9-]+\z/);
  return () if($candidate !~ m/[A-Za-z]/);

  return (lc($candidate));
}

sub _ResolveHostnameToIPs {
  my ($hostname) = @_;

  return () if(!defined($hostname) || $hostname eq '');

  my ($err, @results) = Socket::getaddrinfo($hostname, undef);
  return () if($err);

  my %seen;
  my @ips;
  foreach my $result (@results) {
    next if(ref($result) ne 'HASH');
    my $ip = _SocketAddressToIP($result->{family}, $result->{addr});
    next if(!defined($ip) || $seen{$ip}++);
    push @ips, $ip;
  }

  return @ips;
}

sub _SocketAddressToIP {
  my ($family, $socketAddress) = @_;

  return undef if(!defined($family) || !defined($socketAddress));

  if($family == Socket::AF_INET()) {
    my (undef, $packedAddress) = Socket::unpack_sockaddr_in($socketAddress);
    return Socket::inet_ntop(Socket::AF_INET(), $packedAddress);
  }

  if($family == Socket::AF_INET6()) {
    my (undef, $packedAddress) = Socket::unpack_sockaddr_in6($socketAddress);
    return Socket::inet_ntop(Socket::AF_INET6(), $packedAddress);
  }

  return undef;
}

sub _ParseIPAddress {
  my ($ip) = @_;

  my $normalizedIp = _NormalizeIPAddress($ip);
  return (undef, undef) if(!defined($normalizedIp));

  my $packedIPv4 = Socket::inet_pton(Socket::AF_INET(), $normalizedIp);
  return (Socket::AF_INET(), $packedIPv4) if(defined($packedIPv4));

  my $packedIPv6 = Socket::inet_pton(Socket::AF_INET6(), $normalizedIp);
  return (Socket::AF_INET6(), $packedIPv6) if(defined($packedIPv6));

  return (undef, undef);
}

sub _NormalizeIPAddress {
  my ($ip) = @_;

  return undef if(!defined($ip) || $ip eq '');

  $ip =~ s/^\[//;
  $ip =~ s/\]$//;
  $ip =~ s/%[A-Za-z0-9_.-]+\z//;

  return lc($ip);
}

sub _HeaderValue {
  my ($headers, $wanted) = @_;

  return undef if(ref($headers) ne 'HASH' || !defined($wanted));

  foreach my $key (keys %{$headers}) {
    next if(!defined($key));
    return $headers->{$key} if(lc($key) eq lc($wanted));
  }

  return undef;
}

sub _CompileRegex {
  my ($raw) = @_;

  return undef if(!defined($raw));

  my $compiled = eval { qr/$raw/ };
  return undef if($@);

  return $compiled;
}

sub _GetStoredRegex {
  my ($hash, $devName, $attrName) = @_;

  return (undef, undef) if(ref($hash) ne 'HASH' || !defined($attrName));

  my $raw = $hash->{".$attrName"};
  if(!defined($raw) && defined($devName)) {
    $raw = main::AttrVal($devName, $attrName, undef);
    $hash->{".$attrName"} = $raw if(defined($raw));
  }

  return (undef, undef) if(!defined($raw) || $raw eq '');

  my $compiled = $hash->{".$attrName"."Re"};
  if(!defined($compiled)) {
    $compiled = _CompileRegex($raw);
    if(defined($compiled)) {
      $hash->{".$attrName"."Re"} = $compiled;
      main::Log3 $devName, 5, "$devName: lazily compiled $attrName regex from stored attribute value";
    }
  }

  return ($raw, $compiled);
}

sub Attr {
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $main::defs{$devName};

  $main::auth_refresh = 1;
  my $set = ($type eq "del" ? 0 : (!defined($param[0]) || $param[0]) ? 1 : 0);

  if($attrName eq "disable" ||
     $attrName eq "disabledForIntervals") {
    main::readingsSingleUpdate($hash, "state", $set ? "disabled" : "active", 1)
      if($attrName eq "disable");
    if($set) {
      $hash->{disabled} = 1;
    } else {
      delete($hash->{disabled});
    }

  } elsif($attrName eq "headerAuthPolicy" ||
          $attrName eq "noCheckFor" ||
          $attrName eq "trustedProxy" ||
          $attrName eq "validFor") {
    if($set) {
      if($attrName eq "validFor") {
        my %vf = map { $_, 1 } split(",", join(",", @param));
        $hash->{".$attrName"} = \%vf;
      } else {
        my $raw = join(" ", @param);
        if($attrName eq "headerAuthPolicy") {
          my ($policy, $parseError) =
            FHEM::Core::Authentication::HeaderPolicy::parse_header_auth_policy($raw);
          return $parseError if($parseError);

          my $validationError =
            FHEM::Core::Authentication::HeaderPolicy::validate_header_auth_policy($policy);
          return $validationError if($validationError);

          $hash->{".$attrName"} = $policy;
        } else {
          my $compiled = _CompileRegex($raw);
          return "$attrName must be a valid Perl regular expression"
            if(!defined($compiled));
          $hash->{".$attrName"} = $raw;
          $hash->{".$attrName"."Re"} = $compiled;
        }
      }
    } else {
      delete($hash->{".$attrName"});
      delete($hash->{".$attrName"."Re"}) if($attrName eq "noCheckFor" || $attrName eq "trustedProxy");
    }

    if($attrName eq "validFor") {
      main::readingsSingleUpdate($hash, "state", "validFor:".join(",",@param), 1);
      main::InternalTimer(1, "SecurityCheck", 0) if($main::init_done);
    }
    if($attrName eq "headerAuthPolicy") {
      foreach my $d (main::devspec2array("TYPE=FHEMWEB")) {
        my $sname = $main::defs{$d}{SNAME};
        delete $main::defs{$d}{Authenticated} if($sname && $hash->{".validFor"}{$sname});
      }
      main::InternalTimer(1, "SecurityCheck", 0) if($main::init_done);
    }
    if($attrName eq "trustedProxy") {
      foreach my $d (main::devspec2array("TYPE=FHEMWEB")) {
        my $sname = $main::defs{$d}{SNAME};
        delete $main::defs{$d}{Authenticated} if($sname && $hash->{".validFor"}{$sname});
      }
      main::InternalTimer(1, "SecurityCheck", 0) if($main::init_done);
    }

  } elsif($attrName eq "reportAuthAttempts") {
    if($set) {
      my $p = $param[0];
      return "Wrong value $p for attr $devName report."
        if($p !~ m/^[123]$/);
      $hash->{doReport} = $p;
    } else {
      delete $hash->{doReport};
    }
  } elsif($attrName eq "strict") {
    if($set) {
      my $p = $param[0];
      return "Wrong value $p for attr $devName strict."
        if($p !~ m/^[01]$/);
    }
  }

  return;
}

1;

=pod
=item helper
=item summary    authenticate FHEMWEB requests based on HTTP headers
=item summary_DE authentifiziert FHEMWEB Anfragen anhand von HTTP Headern
=begin html

<a id="WebAuth"></a>
<h3>WebAuth</h3>
<ul>
  <br>

  <a id="WebAuth-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WebAuth</code>
    <br><br>
    Authenticate FHEMWEB requests based on HTTP headers, typically injected by
    a trusted reverse proxy or external authentication layer.<br><br>
  </ul>

  <a id="WebAuth-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="WebAuth-attr-headerAuthPolicy"></a>
    <li>headerAuthPolicy<br>
        JSON object describing nested AND/OR groups and leaf rules.<br>
        Supported matchers are: <code>present</code>, <code>equals</code>,
        <code>notEquals</code>, <code>regex</code>, <code>contains</code>,
        <code>prefix</code>, <code>suffix</code>.<br><br>

        Syntax of a group node:<br>
        <code>{"op":"AND|OR","items":[&lt;node&gt;,...]}</code><br><br>

        Syntax of a leaf rule:<br>
        <code>{"header":"Header-Name","match":"present"}</code><br>
        <code>{"header":"Header-Name","match":"equals|notEquals|regex|contains|prefix|suffix","value":"..."}</code><br><br>

        Header lookup is case-insensitive. <code>contains</code> splits the
        incoming header value on commas and matches whole trimmed items.<br><br>

        Example:<br>
<pre>{
  "op": "AND",
  "items": [
    { "header": "X-Forwarded-User", "match": "present" },
    {
      "op": "OR",
      "items": [
        { "header": "X-Auth-Source", "match": "equals", "value": "oauth2-proxy" },
        { "header": "X-Forwarded-Groups", "match": "contains", "value": "admins" }
      ]
    }
  ]
}</pre>
    </li><br>

    <a id="WebAuth-attr-trustedProxy"></a>
    <li>trustedProxy<br>
        Regexp of trusted reverse-proxy IP addresses or hostnames.<br>
        The check uses the socket peer address of the TCP connection.
        If the regexp does not match the peer IP directly, WebAuth also tries
        the reverse-resolved hostname of the peer. For literal hostname
        patterns like <code>proxy.example.org</code> or
        <code>^proxy.example.org$</code>, WebAuth additionally resolves the
        configured hostname via DNS and compares the resulting IP addresses
        with the socket peer.<br><br>

        If the peer does not match, WebAuth does not handle the request and
        lets another authenticator, for example <code>allowed</code> with
        <code>basicAuth</code>, try next.<br><br>

        When the peer matches, WebAuth additionally makes the peer IP and a
        client IP derived from <code>Forwarded</code> or
        <code>X-Forwarded-For</code> available to
        <code>headerAuthPolicy</code> via synthetic internal headers.<br><br>

        Example:<br>
<pre>{
  "op": "AND",
  "items": [
    { "header": "X-Forwarded-User", "match": "present" },
    {
      "header": "X-FHEM-Forwarded-Client-IP",
      "match": "regex",
      "value": "^(192\\.168\\.1\\.|10\\.0\\.0\\.)"
    }
  ]
}</pre>
    </li><br>

    <a id="WebAuth-attr-noCheckFor"></a>
    <li>noCheckFor<br>
        Regexp matching paths for which no authentication is required.
    </li><br>

    <a id="WebAuth-attr-reportAuthAttempts"></a>
    <li>reportAuthAttempts {1|2|3}<br>
        If set to 1 or 3, each successful authentication attempt will
        generate an event. If set to 2 or 3, each unsuccessful authentication
        attempt will generate an event.
    </li><br>

    <a id="WebAuth-attr-strict"></a>
    <li>strict {1|0}<br>
        Controls how requests without any relevant authentication headers are
        handled. If set to <code>1</code> (default), such requests are denied
        with <code>403 Forbidden</code>. If set to <code>0</code>, WebAuth
        returns not-responsible and allows a later authenticator, such as
        <code>allowed</code> with <code>basicAuth</code>, to handle the
        request.
    </li><br>

    <a id="WebAuth-attr-validFor"></a>
    <li>validFor<br>
        Comma separated list of frontend instances for which this module is
        active, e.g. <code>WEB</code>.
    </li><br>
  </ul>
</ul>

=end html

=for :application/json;q=META.json 98_WebAuth.pm
{
  "abstract": "authenticates FHEMWEB requests based on HTTP headers",
  "author": [
    "Sidey"
  ],
  "keywords": [
    "Authentication",
    "Authorization",
    "Header",
    "Reverse Proxy",
    "Trusted Proxy",
    "Forward Auth",
    "SSO",
    "OIDC",
    "Web"
  ],
  "x_fhem_prereqs": [
    "a configured FHEMWEB instance referenced by attr validFor",
    "an upstream reverse proxy or authentication layer that injects trusted HTTP headers"
  ],
  "x_lang": {
    "de": {
      "abstract": "authentifiziert FHEMWEB Requests anhand von HTTP Headern"
    }
  },
  "x_version": "0.3.0"
}
=end :application/json;q=META.json

=cut
