##############################################
# $Id$
package main;

use strict;
use warnings;
use vars qw(@FW_httpheader); # HTTP header, line by line
use MIME::Base64;
my $allowed_haveSha;

sub allowed_CheckBasicAuth($$$$@);

#####################################
sub
allowed_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "allowed_Define";
  $hash->{AuthorizeFn} = "allowed_Authorize";
  $hash->{AuthenticateFn} = "allowed_Authenticate";
  $hash->{SetFn}    = "allowed_Set";
  $hash->{AttrFn}   = "allowed_Attr";
  no warnings 'qw';
  my @attrList = qw(
    allowedCommands
    allowedDevices
    allowedDevicesRegexp
    basicAuth
    basicAuthExpiry
    basicAuthMsg
    disable:0,1
    globalpassword
    password
    validFor
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

  $hash->{UndefFn} = "allowed_Undef";
  $hash->{FW_detailFn} = "allowed_fhemwebFn";

  eval { require Digest::SHA; };
  if($@) {
    Log3 $hash, 4, $@;
    $allowed_haveSha = 0;
  } else {
    $allowed_haveSha = 1;
  }
}


#####################################
sub
allowed_Define($$)
{
  my ($hash, $def) = @_;
  my @l = split(" ", $def);

  if(@l > 2) {
    my %list;
    for(my $i=2; $i<@l; $i++) {
      $list{$l[$i]} = 1;
    }
    $hash->{devices} = \%list;
  }
  $auth_refresh = 1;
  readingsSingleUpdate($hash, "state", "validFor:", 0);
  SecurityCheck() if($init_done);
  return undef;
}

sub
allowed_Undef($$)
{
  $auth_refresh = 1;
  return undef;
}

#####################################
# Return 0 for don't care, 1 for Allowed, 2 for forbidden.
sub
allowed_Authorize($$$$)
{
  my ($me, $cl, $type, $arg) = @_;

  return 0 if($me->{disabled});
  if( $cl->{SNAME} ) {
    return 0 if(!$me->{validFor} || $me->{validFor} !~ m/\b$cl->{SNAME}\b/);
  } else {
    return 0 if(!$me->{validFor} || $me->{validFor} !~ m/\b$cl->{NAME}\b/);
  }

  if($type eq "cmd") {
    return 0 if(!$me->{allowedCommands});
    # Return 0: allow stacking with other instances, see Forum#46380
    return 0 if($me->{allowedCommands} =~ m/\b\Q$arg\E\b/);
    Log3 $me, 3, "Forbidden command $arg for $cl->{NAME}";
    stacktrace() if(AttrVal($me, "verbose", 5));
    return 2;
  }

  if($type eq "devicename") {
    return 0 if(!$me->{allowedDevices} &&
                !$me->{allowedDevicesRegexp});
    return 1 if($me->{allowedDevices} &&
                $me->{allowedDevices} =~ m/\b\Q$arg\E\b/);
    return 1 if($me->{allowedDevicesRegexp} &&
                $arg =~ m/^$me->{allowedDevicesRegexp}$/);
    Log3 $me, 3, "Forbidden device $arg for $cl->{NAME}";
    stacktrace() if(AttrVal($me, "verbose", 5));
    return 2;
  }
  return 0;
}

#####################################
# Return 0 for authentication not needed, 1 for auth-ok, 2 for wrong password
sub
allowed_Authenticate($$$$)
{
  my ($me, $cl, $param) = @_;

  return 0 if($me->{disabled});
  return 0 if(!$me->{validFor} || $me->{validFor} !~ m/\b$cl->{SNAME}\b/);
  my $aName = $me->{NAME};

  if($cl->{TYPE} eq "FHEMWEB") {
    my $basicAuth = AttrVal($aName, "basicAuth", undef);
    delete $cl->{".httpAuthHeader"};
    return 0 if(!$basicAuth);
    return 2 if(!$param);

    my $FW_httpheader = $param;
    my $secret = $FW_httpheader->{Authorization};
    $secret =~ s/^Basic //i if($secret);

    # Check for Cookie in headers if no basicAuth header is set
    my $authcookie;
    if (!$secret && $FW_httpheader->{Cookie}) {
      if(AttrVal($aName, "basicAuthExpiry", 0)) {
        my $cookie = "; ".$FW_httpheader->{Cookie}.";";
        $authcookie = $1 if ( $cookie =~ /; AuthToken=([^;]+);/ );
        $secret = $authcookie;
      }
    }

    my $pwok = (allowed_CheckBasicAuth($me, $cl, $secret, $basicAuth, 0) == 1);

    # Add Cookie header ONLY if authentication with basicAuth was succesful
    if($pwok && (!defined($authcookie) || $secret ne $authcookie)) {
      my $time = AttrVal($aName, "basicAuthExpiry", 0);
      if ( $time ) {
        my ($user, $password) = split(":", decode_base64($secret)) if($secret);
        $time = int($time*86400+time());
        # generate timestamp according to RFC-1130 in Expires
        my $expires = FmtDateTimeRFC1123($time);

        readingsBeginUpdate($me);
        readingsBulkUpdate($me,'lastAuthUser', $user, 1);
        readingsBulkUpdate($me,'lastAuthExpires', $time, 1);
        readingsBulkUpdate($me,'lastAuthExpiresFmt', $expires, 1);
        readingsEndUpdate($me, 1);

        # set header with expiry
        $cl->{".httpAuthHeader"} = "Set-Cookie: AuthToken=".$secret.
                "; Path=/ ; Expires=$expires\r\n" ;
      }
    }

    return 1 if($pwok);

    my $msg = AttrVal($aName, "basicAuthMsg", "FHEM: login required");
    $cl->{".httpAuthHeader"} = "HTTP/1.1 401 Authorization Required\r\n".
                               "WWW-Authenticate: Basic realm=\"$msg\"\r\n";
    return 2;

  } elsif($cl->{TYPE} eq "telnet") {
    my $pw = AttrVal($aName, "password", undef);
    if(!$pw) {
      $pw = AttrVal($aName, "globalpassword", undef);
      $pw = undef if($pw && $cl->{NAME} =~ m/_127.0.0.1_/);
    }
    return 0 if(!$pw);
    return 2 if(!defined($param));

    if($pw =~ m/^{.*}$/) {
      my $password = $param;
      my $ret = eval $pw;
      Log3 $aName, 1, "password expression: $@" if($@);
      return ($ret ? 1 : 2);

    } elsif($pw =~ m/^SHA256:(.{8}):(.*)$/) {
      if($allowed_haveSha) {
        return (Digest::SHA::sha256_base64("$1:$param") eq $2) ? 1 : 2;
      } else {
        Log3 $me, 3, "Cant load Digest::SHA to decode $me->{NAME} beiscAuth";
      }
    }

    return ($pw eq $param) ? 1 : 2;

  } else {
    $param =~ m/^basicAuth:(.*)/;
    return allowed_CheckBasicAuth($me, $cl, $1,
                                AttrVal($aName,"basicAuth",undef), $param);

  }
}

sub
allowed_CheckBasicAuth($$$$@)
{
  my ($me, $cl, $secret, $basicAuth, $verbose) = @_;

  return 0 if(!$basicAuth);

  my $aName = $me->{NAME};

  my $pwok = ($secret && $secret eq $basicAuth) ? 1 : 2;      # Base64
  my ($user, $password) = split(":", decode_base64($secret)) if($secret);
  ($user,$password) = ("","") if(!defined($user) || !defined($password));

  if($secret && $basicAuth =~ m/^{.*}$/) {
    $pwok = eval $basicAuth;
    if($@) {
      Log3 $aName, 1, "basicAuth expression: $@";
      $pwok = 2;
    } else {
      $pwok = ($pwok ? 1 : 2);
    }

  } elsif($basicAuth =~ m/^SHA256:(.{8}):(.*)$/) {
    if($allowed_haveSha) {
      $pwok = (Digest::SHA::sha256_base64("$1:$user:$password") eq $2 ? 1 : 2);
    } else {
      Log3 $me, 3, "Cannot load Digest::SHA to decode $aName basicAuth";
      $pwok = 2;
    }

  }
  Log3 $me, 3, "Login denied by $aName for $user via $cl->{NAME}"
      if($pwok != 1 && ($verbose || $user));

  return $pwok;
}


sub
allowed_Set(@)
{
  my ($hash, @a) = @_;
  my %sets = (globalpassword=>1, password=>1, basicAuth=>2);

  return "no set argument specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of ".join(" ",sort keys %sets)
    if(!defined($sets{$a[1]}));
  return "$a[1] needs $sets{$a[1]} parameters"
    if(@a-2 != $sets{$a[1]});

  return "Cannot load Digest::SHA" if(!$allowed_haveSha);
  my $plain = ($a[1] eq "basicAuth" ? "$a[2]:$a[3]" : $a[2]);
  my ($x,$y) = gettimeofday();
  my $salt = substr(sprintf("%08X", rand($y)*rand($x)),0,8);

  CommandAttr($hash->{CL}, "$a[0] $a[1] SHA256:$salt:".
                           Digest::SHA::sha256_base64("$salt:$plain"));
}

sub
allowed_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};

  my $set = ($type eq "del" ? 0 : (!defined($param[0]) || $param[0]) ? 1 : 0);

  if($attrName eq "disable") {
    readingsSingleUpdate($hash, "state", $set ? "disabled" : "active", 1);
    if($set) {
      $hash->{disabled} = 1;
    } else {
      delete($hash->{disabled});
    }

  } elsif($attrName eq "allowedCommands" ||     # hoping for some speedup
          $attrName eq "allowedDevices"  ||
          $attrName eq "allowedDevicesRegexp"  ||
          $attrName eq "validFor") {
    if($set) {
      $hash->{$attrName} = join(" ", @param);
    } else {
      delete($hash->{$attrName});
    }
    if($attrName eq "validFor") {
      readingsSingleUpdate($hash, "state", "validFor:".join(",",@param), 1);
      InternalTimer(1, "SecurityCheck", 0) if($init_done);
    }

  } elsif(($attrName eq "basicAuth" ||
           $attrName eq "password" || $attrName eq "globalpassword") &&
          $type eq "set") {
    foreach my $d (devspec2array("TYPE=(FHEMWEB|telnet)")) {
      delete $defs{$d}{Authenticated} if($defs{$d});
    }
    InternalTimer(1, "SecurityCheck", 0) if($init_done);
  }

  return undef;
}

#########################
sub
allowed_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};

  my $vf = $defs{$d}{validFor} ? $defs{$d}{validFor} : "";
  my (@F_arr, @t_arr);
  my @arr = map {
              my $ca = $modules{$defs{$_}{TYPE}}{CanAuthenticate};
              push(@F_arr, $_) if($ca == 1);
              push(@t_arr, $_) if($ca == 2);
              "<input type='checkbox' ".($vf =~ m/\b$_\b/ ? "checked ":"").
                   "name='$_' class='vfAttr'><label>$_</label>"
            }
            grep { !$defs{$_}{SNAME} && 
                   $modules{$defs{$_}{TYPE}}{CanAuthenticate} } 
            sort keys %defs;
  my $r = "<input id='vfAttr' type='button' value='attr'> $d validFor <ul>".
          join("<br>",@arr)."</ul><script>var dev='$d';".<<'EOF';
$("#vfAttr").click(function(){
  var names=[];
  $("input.vfAttr:checked").each(function(){names.push($(this).attr("name"))});
  FW_cmd(FW_root+"?cmd=attr "+dev+" validFor "+names.join(",")+"&XHR=1");
});
</script>
EOF

  $r .= "For ".join(",",@F_arr).
        ": \"set $d basicAuth &lt;username&gt; &lt;password&gt;\"<br>"
    if(@F_arr);
  $r .= "For ".join(",",@t_arr).
        ": \"set $d password &lt;password&gt;\" or".
        "  \"set $d globalpassword &lt;password&gt;\"<br>"
    if(@t_arr);
  return $r;
}

1;

=pod
=item helper
=item summary    authorize command execution based on frontend
=item summary_DE authorisiert Befehlsausf&uuml;hrung basierend auf dem Frontend
=begin html

<a name="allowed"></a>
<h3>allowed</h3>
<ul>
  <br>

  <a name="alloweddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allowed &lt;deviceList&gt;</code>
    <br><br>
    Authorize execution of commands and modification of devices based on the
    frontend used and/or authenticate users.<br><br>

    If there are multiple instances defined which are valid for a given
    frontend device, then all authorizations must succeed. For authentication
    it is sufficient when one of the instances succeeds. The checks are
    executed in alphabetical order of the allowed instance names.<br><br>

    <b>Note:</b> this module should work as intended, but no guarantee
    can be given that there is no way to circumvent it.<br><br>
    Examples:
    <ul><code>
      define allowedWEB allowed<br>
      attr allowedWEB validFor WEB,WEBphone,WEBtablet<br>
      attr allowedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
      attr allowedWEB allowedCommands set,get<br><br>

      define allowedTelnet allowed<br>
      attr allowedTelnet validFor telnetPort<br>
      attr allowedTelnet password secret<br>
    </code></ul>
    <br>
  </ul>

  <a name="allowedset"></a>
  <b>Set</b>
  <ul>
    <li>basicAuth &lt;username&gt; &lt;password&gt;</li>
    <li>password &lt;password&gt;</li>
    <li>globalpassword &lt;password&gt;<br>
      these commands set the corresponding attribute, by computing an SHA256
      hash from the arguments and a salt. Note: the perl module Device::SHA is
      needed.
    </li>
  </ul><br>

  <a name="allowedget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="allowedattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li><br>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        A comma separated list of commands allowed from the matching frontend
        (see validFor).<br>
        If set to an empty list <code>, (i.e. comma only)</code>
        then no comands are allowed. If set to <code>get,set</code>, then only
        a "regular" usage is allowed via set and get, but changing any
        configuration is forbidden.<br>
        </li><br>

    <a name="allowedDevices"></a>
    <li>allowedDevices<br>
        A comma or space separated list of device names which can be
        manipulated via the matching frontend (see validFor).
        </li><br>

    <a name="allowedDevicesRegexp"></a>
    <li>allowedDevices<br>
        Comma separated list of device names which can be manipulated via the
        frontends specified by validFor. The regexp is prepended with ^ and
        suffixed with $, as usual.  Only devices listed in allowedDevices or
        matching allowedDevicesRegexp may manipulated.
        </li><br>

    <a name="allowedDevicesRegexp"></a>
    <li>allowedDevicesRegexp<br>
        A regexp to match device names which can be manipulated via the
        frontends specified by validFor. Only devices listed in allowedDevices
        or matching allowedDevicesRegexp may manipulated.
        </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        request a username/password authentication for FHEMWEB access.
        It can be a base64 encoded string of user:password, an SHA256 hash
        (which should be set via the corresponding set command) or a perl
        expression if enclosed in {}, where $user and $password are set, and
        which returns true if accepted or false if not. Examples:
        <ul><code>
          attr allowed basicAuth ZmhlbXVzZXI6c2VjcmV0<br>
          attr allowed basicAuth SHA256:F87740B5:q8dHeiClaPLaWVsR/rqkzcBhw/JvvwVi4bEwKmJc/Is<br>
          attr allowed basicAuth {"$user:$password" eq "fhemuser:secret"}<br>
        </code></ul>
        If basicAuthMsg is set, it will be displayed in the popup window when
        requesting the username/password. Note: not all browsers support this
        feature.<br>
    </li><br>

    <a name="basicAuthExpiry"></a>
    <li>basicAuthExpiry<br>
        allow the basicAuth to be kept valid for a given number of days.
        So username/password as specified in basicAuth are only requested
        after a certain period.
        This is achieved by sending a cookie to the browser that will expire
        after the given period.
        Only valid if basicAuth is set.
    </li><br>

    <a name="password"></a>
    <li>password<br>
        Specify a password for telnet instances, which has to be entered as the
        very first string after the connection is established. The same rules
        apply as for basicAuth, with the expception that there is no user to be
        specified.<br>
        Note: if this attribute is set, you have to specify a password as the
        first argument when using fhem.pl in client mode:
        <ul>
          perl fhem.pl localhost:7072 secret "set lamp on"
        </ul>
        </li><br>

    <a name="globalpassword"></a>
    <li>globalpassword<br>
        Just like the attribute password, but a password will only required for
        non-local connections.
        </li><br>


    <a name="validFor"></a>
    <li>validFor<br>
        A comma separated list of frontend names. Currently supported frontends
        are all devices connected through the FHEM TCP/IP library, e.g. telnet
        and FHEMWEB. The allowed instance is only active, if this attribute is
        set.
        </li>

  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="allowed"></a>
<h3>allowed</h3>
<ul>
  <br>

  <a name="alloweddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allowed &lt;deviceList&gt;</code>
    <br><br>
    Authorisiert das Ausf&uuml;hren von Kommandos oder das &Auml;ndern von
    Ger&auml;ten abh&auml;ngig vom verwendeten Frontend.<br>

    Falls man mehrere allowed Instanzen definiert hat, die f&uuml;r dasselbe
    Frontend verantwortlich sind, dann m&uuml;ssen alle Authorisierungen
    genehmigt sein, um das Befehl ausf&uuml;hren zu k&ouml;nnen. Auf der
    anderen Seite reicht es, wenn einer der Authentifizierungen positiv
    entschieden wird.  Die Pr&uuml;fungen werden in alphabetischer Reihenfolge
    der Instanznamen ausgef&uuml;hrt.  <br><br>

    <b>Achtung:</b> das Modul sollte wie hier beschrieben funktionieren,
    allerdings k&ouml;nnen wir keine Garantie geben, da&szlig; man sie nicht
    &uuml;berlisten, und Schaden anrichten kann.<br><br>

    Beispiele:
    <ul><code>
      define allowedWEB allowed<br>
      attr allowedWEB validFor WEB,WEBphone,WEBtablet<br>
      attr allowedWEB basicAuth { "$user:$password" eq "admin:secret" }<br>
      attr allowedWEB allowedCommands set,get<br><br>

      define allowedTelnet allowed<br>
      attr allowedTelnet validFor telnetPort<br>
      attr allowedTelnet password secret<br>
    </code></ul>
    <br>
  </ul>

  <a name="allowedset"></a>
  <b>Set</b>
  <ul>
    <li>basicAuth &lt;username&gt; &lt;password&gt;</li>
    <li>password &lt;password&gt;</li>
    <li>globalpassword &lt;password&gt;<br>
      diese Befehle setzen das entsprechende Attribut, indem sie aus den
      Parameter und ein Salt ein SHA256 Hashwert berechnen. Achtung: das perl
      Modul Device::SHA wird ben&ouml;tigt.
    </li>
  </ul><br>


  <a name="allowedget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="allowedattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#disable">disable</a>
      </li><br>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        Eine Komma getrennte Liste der erlaubten Befehle des passenden
        Frontends (siehe validFor). Bei einer leeren Liste (, dh. nur ein
        Komma)  wird dieser Frontend "read-only".
        Falls es auf <code>get,set</code> gesetzt ist, dann sind in dieser
        Frontend keine Konfigurations&auml;nderungen m&ouml;glich, nur
        "normale" Bedienung der Schalter/etc.
        </li><br>

    <a name="allowedDevices"></a>
    <li>allowedDevices<br>
        Komma getrennte Liste von Ger&auml;tenamen, die mit dem passenden
        Frontend (siehe validFor) ge&auml;ndert werden k&ouml;nnen.
        </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        Erzwingt eine Authentifizierung mit Benutzername/Passwort f&uuml;r die
        zugerdnete FHEMWEB Instanzen. Der Wert kann entweder das base64
        kodierte Benutzername:Passwort sein, ein SHA256 hash (was man am besten
        mit dem passenden set Befehl erzeugt), oder, falls er in {}
        eingeschlossen ist, ein Perl Ausdruck. F&uuml;r Letzteres wird
        $user und $passwort gesetzt, und muss wahr zur&uuml;ckliefern, falls
        Benutzername und Passwort korrekt sind. Beispiele:
        <ul><code>
          attr allowed basicAuth ZmhlbXVzZXI6c2VjcmV0<br>
          attr allowed basicAuth SHA256:F87740B5:q8dHeiClaPLaWVsR/rqkzcBhw/JvvwVi4bEwKmJc/Is<br>
          attr allowed basicAuth {"$user:$password" eq "fhemuser:secret"}<br>
        </code></ul>
        basicAuthMsg wird (in manchen Browsern) in dem Passwort Dialog als
        &Uuml;berschrift angezeigt.<br>
    </li><br>


    <a name="password"></a>
    <li>password<br>
        Betrifft nur telnet Instanzen (siehe validFor): Bezeichnet ein
        Passwort, welches als allererster String eingegeben werden muss,
        nachdem die Verbindung aufgebaut wurde. F&uuml;r die Werte gelten die
        Regeln von basicAuth, mit der Ausnahme, dass nur Passwort und kein
        Benutzername spezifiziert wird.<br> Falls dieser Parameter gesetzt
        wird, sendet FHEM telnet IAC Requests, um ein Echo w&auml;hrend der
        Passworteingabe zu unterdr&uuml;cken.  Ebenso werden alle
        zur&uuml;ckgegebenen Zeilen mit \r\n abgeschlossen.<br>
        Falls dieses Attribut gesetzt wird, muss als erstes Argument ein
        Passwort angegeben werden, wenn fhem.pl im Client-mode betrieben wird:
        <ul><code>
          perl fhem.pl localhost:7072 secret "set lamp on"
        </code></ul>
    </li><br>

    <a name="globalpassword"></a>
    <li>globalpassword<br>
        Betrifft nur telnet Instanzen (siehe validFor): Entspricht dem
        Attribut password; ein Passwort wird aber ausschlie&szlig;lich f&uuml;r
        nicht-lokale Verbindungen verlangt.
        </li><br>

    <a name="validFor"></a>
    <li>validFor<br>
        Komma separierte Liste von Frontend-Instanznamen.  Aktuell werden nur
        Frontends unterst&uuml;tzt, die das FHEM TCP/IP Bibliothek verwenden,
        z.Bsp. telnet und FHEMWEB. Falls nicht gesetzt, ist die allowed Instanz
        nicht aktiv.
        </li>

  </ul>
  <br>

</ul>
=end html_DE

=cut
