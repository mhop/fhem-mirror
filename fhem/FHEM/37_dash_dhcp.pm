
# $Id$

package main;

use strict;
use warnings;

use IO::Socket::INET;

sub
dash_dhcp_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "dash_dhcp_Read";

  $hash->{DefFn}    = "dash_dhcp_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "dash_dhcp_Notify";
  $hash->{UndefFn}  = "dash_dhcp_Undefine";
  #$hash->{SetFn}    = "dash_dhcp_Set";
  #$hash->{GetFn}    = "dash_dhcp_Get";
  $hash->{AttrFn}   = "dash_dhcp_Attr";
  $hash->{AttrList} = "devAlias disable:1,0 disabledForIntervals allowed port $readingFnAttributes";
}

#####################################

sub
dash_dhcp_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> dash_dhcp"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  if( $init_done ) {
    dash_dhcp_startListener($hash);

  } else {
    readingsSingleUpdate($hash, 'state', 'initialized', 1 );

  }

  return undef;
}

sub
dash_dhcp_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  dash_dhcp_startListener($hash);

  return undef;
}

sub
dash_dhcp_startListener($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  dash_dhcp_stopListener($hash);

  return undef if( IsDisabled($name) > 0 );

  $hash->{PORT} = (!defined(getlogin) || getlogin eq 'root')?67:6767;
  $hash->{PORT} = AttrVal($name, 'port', $hash->{PORT});
  Log3 $name, 4, "$name: using port $hash->{PORT}";

  if( my $socket = IO::Socket::INET->new(LocalPort=>$hash->{PORT}, Proto=>'udp', Broadcast=>1, ReuseAddr=>1) ) {
    readingsSingleUpdate($hash, 'state', 'listening', 1 );
    Log3 $name, 3, "$name: listening";
    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;

  } else {
    Log3 $name, 2, "$name: failed to open port $hash->{PORT} $@";

    dash_dhcp_stopListener($hash);
    InternalTimer(gettimeofday()+30, "dash_dhcp_startListener", $hash, 0);

  }
}
sub
dash_dhcp_stopListener($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  return if( !$hash->{CD} );

  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  readingsSingleUpdate($hash, 'state', 'stopped', 1 );
  Log3 $name, 3, "$name: stopped";
  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}

sub
dash_dhcp_Undefine($$)
{
  my ($hash, $arg) = @_;

  dash_dhcp_stopListener($hash);

  return undef;
}

sub
dash_dhcp_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
dash_dhcp_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
dash_dhcp_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};

  my $chaddr;
  if (($data) =~ /^.*DHCPACK[^:]*([\da-z]{2}(:[\da-z]{2}){5}) .*/ ) {
    $chaddr=$1;

  } else {
    my ($op, $htype, $hlen, $hops, $xid, $secs, $flags ) = unpack( 'CCCCNnn', $data );
    #my $ciaddr = join '.', unpack('C4', substr($data, 12 ) );
    #my $yiaddr = join '.', unpack('C4', substr($data, 16 ) );
    #my $siaddr = join '.', unpack('C4', substr($data, 20 ) );
    #my $giaddr = join '.', unpack('C4', substr($data, 24 ) );
    $chaddr = join ':', unpack('(H2)*', substr($data, 28, $hlen ) );

  }

  my $allowed = AttrVal($name, "allowed", undef );
  if( !$chaddr || $chaddr !~ m/[\da-z]{2}(:[\da-z]{2}){5}/i ) {
    $chaddr = '<empty>' if( !$chaddr );
    Log3 $name, 2, "$name: invalid mac: $chaddr";

  } elsif( !$allowed || ",$allowed," =~/,$chaddr,/i ) {
    Log3 $name, 4, "$name: got $chaddr";

    $chaddr =~ s/:/-/g;
    $chaddr = $hash->{helper}{devAliases}{$chaddr} if( defined($hash->{helper}{devAliases}{$chaddr}) );
    readingsSingleUpdate( $hash, $chaddr, 'short', 1 );

  } else {
    Log3 $name, 4, "$name: ignoring $chaddr";

  }

}

sub
dash_dhcp_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $len;
  my $buf;

  $len = $hash->{CD}->recv($buf, 1024);
  if( !defined($len) || !$len ) {
Log 1, "!!!!!!!!!!";
    return;
  }

  #$buf = pack('H*', '010106000597ee0e05b90000c0a8a10d000000000000000000000000005056a3e69700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000638253633501030c0a646e732d7562756e7475370d011c02030f06770c2c2f1a792aff0000000000000000000000000000000000000000000000000000000000' );

  dash_dhcp_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
dash_dhcp_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq "devAlias" ) {
    delete $hash->{helper}{devAliases};
    if( $cmd eq 'set' && $attrVal ) {
      $hash->{helper}{devAliases}  = {};
      foreach my $entry (split( ' ', $attrVal ) ) {
        my ($mac, $alias) = split( ':', $entry );
        $hash->{helper}{devAliases}{$mac} = $alias;
      }
    }

  } elsif( $attrName eq "disable" ) {
    if( $cmd eq 'set' && $attrVal ne "0" ) {
      dash_dhcp_stopListener($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      dash_dhcp_startListener($hash);
    }
  } elsif( $attrName eq "disabledForIntervals" ) {
    delete $attr{$name}{$attrName};
    $attr{$name}{$attrName} = $attrVal if( $cmd eq 'set' );

    dash_dhcp_startListener($hash);

  } elsif( $attrName eq "port" ) {
    delete $attr{$name}{$attrName};
    $attr{$name}{$attrName} = $attrVal if( $cmd eq 'set' );

    dash_dhcp_startListener($hash);
  }

  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=item summary    module for the amazon dash button
=item summary_DE Modul f&uuml;r den amazon dash button
=begin html

<a name="dash_dhcp"></a>
<h3>dash_dhcp</h3>
<ul>
  Module to integrate amazon dash buttons into FHEM;.<br><br>

  The module can listen direclty to dhcp broadcast messages or listen to redirected openwrt dhcp log messages.

  Notes:
  <ul>
    <li>if listening for dhcp messages the module has to run as root or you have to redirect port 67 with
<ul><code>iptables -A PREROUTING -t nat -i eth0 -p udp --dport 67 -j REDIRECT --to-port 6767</code></ul>
or
<ul><code>iptables -I PREROUTING -t nat -i eth0 -p udp --src 0.0.0.0 --dport 67 -j DNAT --to 0.0.0.0:6767</code></ul>
and use the port attribute to configure the redirected port.</li>
    <li>to make iptables rules permanent see for example: https://www.thomas-krenn.com/de/wiki/Iptables_Firewall_Regeln_dauerhaft_speichern</li>
  </ul>

  <a name="dash_dhcp_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>devAlias<br>
      space separated list of &lt;mac&gt;:&lt;alias&gt; pairs.</li>
    <li>allowed<br>
      comma separated list of allowed mac adresses</li>
    <li>port<br>
      the listen port. defaults to 67 for root and 6767 for other users.</li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul><br>
</ul><br>

=end html
=cut
