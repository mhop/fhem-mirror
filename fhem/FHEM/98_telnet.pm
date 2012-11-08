##############################################
# $Id$

# Note: this is not really a telnet server, but a TCP server with slight telnet
# features (disable echo on password)

package main;
use strict;
use warnings;
use TcpServerUtils;

##########################
sub
telnet_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "telnet_Define";
  $hash->{ReadFn}  = "telnet_Read";
  $hash->{UndefFn} = "telnet_Undef";
  $hash->{AttrFn}  = "telnet_Attr";
  $hash->{NotifyFn}= "telnet_SecurityCheck";
  $hash->{AttrList} = "loglevel:0,1,2,3,4,5,6 globalpassword password ".
                        "allowfrom SSL";
}

#####################################
sub
telnet_SecurityCheck($$)
{
  my ($ntfy, $dev) = @_;
  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));
  my $motd = AttrVal("global", "motd", "");
  if($motd =~ "^SecurityCheck") {
      my @list = grep { !(AttrVal($_, "password", undef) ||
                        AttrVal($_, "globalpassword", undef)) }
               devspec2array("TYPE=telnet");
    $motd .= (join(",", sort @list).
                        " has no password/globalpassword attribute.\n")
        if(@list);
    $attr{global}{motd} = $motd;
  }
  delete $modules{telnet}{NotifyFn};
  return;
}

##########################
sub
telnet_Define($$$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> telnet [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/ || ($global && $global ne "global"));

  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log 1, "$ret. Exiting.";
    exit(1);
  }
  return $ret;

}

sub
telnet_pw($$)
{
  my ($sname, $cname) = @_;
  my $pw = $attr{$sname}{password};
  return $pw if($pw);

  $pw = $attr{$sname}{globalpassword};
  return $pw if($pw && $cname !~ m/^telnet:127.0.0.1/);

  return undef;
}

##########################
sub
telnet_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "telnet");
    return if(!$chash);
    syswrite($chash->{CD}, sprintf("%c%c%cPassword: ", 255, 251, 1)) # WILL ECHO
        if(telnet_pw($name, $chash->{NAME}));
    return;
  }

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 256);
  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    return;
  }
  if(ord($buf) == 4) {	# EOT / ^D
    CommandQuit($hash, "");
    return;
  }

  $buf =~ s/\r//g;
  my $pw = telnet_pw($hash->{SNAME}, $name);
  if($pw) {
    $buf =~ s/\xff..//g;              # Telnet IAC stuff
    $buf =~ s/\xfd(.)//;              # Telnet Do ?
    syswrite($hash->{CD}, sprintf("%c%c%c", 0xff, 0xfc, ord($1)))
                      if(defined($1)) # Wont / ^C handling
  }
  $hash->{BUF} .= $buf;
  my @ret;
  my $gotCmd;

  while($hash->{BUF} =~ m/\n/) {
    my ($cmd, $rest) = split("\n", $hash->{BUF}, 2);
    $hash->{BUF} = $rest;

    if(!$hash->{pwEntered}) {
      if($pw) {
        syswrite($hash->{CD}, sprintf("%c%c%c\r\n", 255, 252, 1)); # WONT ECHO

        $ret = ($pw eq $cmd);
        if($pw =~ m/^{.*}$/) {  # Expression as pw
          my $password = $cmd;
          $ret = eval $pw;
          Log 1, "password expression: $@" if($@);
        }

        if($ret) {
          $hash->{pwEntered} = 1;
          next;
        } else {
          CommandDelete(undef, $name);
          return;
        }
      }
    }
    $gotCmd = 1;
    if($cmd) {
      if($cmd =~ m/\\ *$/) {                     # Multi-line
        $hash->{prevlines} .= $cmd . "\n";
      } else {
        if($hash->{prevlines}) {
          $cmd = $hash->{prevlines} . $cmd;
          undef($hash->{prevlines});
        }
        $ret = AnalyzeCommandChain($hash, $cmd);
        push @ret, $ret if(defined($ret));
      }
    } else {
      $hash->{prompt} = 1;                  # Empty return
      if(!$hash->{motdDisplayed}) {
        my $motd = $attr{global}{motd};
        push @ret, $motd if($motd && $motd ne "none");
        $hash->{motdDisplayed} = 1;
      }
    }
    next if($rest);
  }

  $ret = "";
  $ret .= (join("\n", @ret) . "\n") if(@ret);
  $ret .= ($hash->{prevlines} ? "> " : "fhem> ")
          if($gotCmd && $hash->{prompt} && !$hash->{rcvdQuit});
  if($ret) {
    $ret =~ s/\n/\r\n/g if($pw);  # only for DOS telnet 
    for(;;) {
      my $l = syswrite($hash->{CD}, $ret);
      last if(!$l || $l == length($ret));
      $ret = substr($ret, $l);
    }
  }
  CommandDelete(undef, $name) if($hash->{rcvdQuit});
}

##########################
sub
telnet_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "SSL") {
    TcpServer_SetSSL($hash);
  }
  return undef;
}

sub
telnet_Undef($$)
{
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

1;

=pod
=begin html

<a name="telnet"></a>
<h3>telnet</h3>
<ul>
  <br>
  <a name="telnetdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; telnet &lt;portNumber&gt; [global]</code>
    <br><br>

    Listen on the TCP/IP port <code>&lt;portNumber&gt;</code> for incoming
    connections. If the second parameter global is <b>not</b> specified,
    the server will only listen to localhost connections.
    <br><br>

    To use IPV6, specify the portNumber as IPV6:&lt;number&gt;, in this
    case the perl module IO::Socket:INET6 will be requested.
    On Linux you may have to install it with cpan -i IO::Socket::INET6 or
    apt-get libio-socket-inet6-perl; OSX and the FritzBox-7390 perl already has
    this module.
    <br><br>
    Examples:
    <ul>
        <code>define tPort telnet 7072 global</code><br>
        <code>attr tPort globalpassword mySecret</code><br>
        <code>attr tPort SSL</code><br>
    </ul>
    <br>
    Note: The old global attribute port is automatically converted to a
    telnet instance with the name telnetPort. The global allowfrom attibute is
    lost in this conversion.
  </ul>
  <br>


  <a name="telnetset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="telnetget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="telnetattr"></a>
  <b>Attributes:</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <br>

    <a name="password"></a>
    <li>password<br>
        Specify a password, which has to be entered as the very first string
        after the connection is established. If the argument is enclosed in {},
        then it will be evaluated, and the $password variable will be set to
        the password entered. If the return value is true, then the password
        will be accepted. If thies parameter is specified, fhem sends telnet
        IAC requests to supress echo while entering the password.
        Also all returned lines are terminated with \r\n.
        Example:<br>
        <code>
        attr tPort password secret<br>
        attr tPort password {use FritzBoxUtils;;FB_checkPw("localhost","$password") }
        </code>
        <br><br>

    <a name="globalpassword"></a>
    <li>globalpassword<br>
        Just like the attribute password, but a password will only required for
        non-local connections.
        <br><br>

    <a name="SSL"></a>
    <li>SSL<br>
        Enable SSL encryption of the connection, see the description <a
        href="#HTTPS">here</a> on generating the needed SSL certificates. To
        connect to such a port use one of the following commands:
        <ul>
          socat openssl:fhemhost:fhemport,verify=0 readline<br>
          ncat --ssl fhemhost fhemport<br>
          openssl s_client -connect fhemhost:fhemport<br>
        </ul>
        <br><br>

    <a name="allowfrom"></a>
    <li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set,
        only connections from these addresses are allowed.
        <br><br>

  </ul>

</ul>


=end html
=cut
