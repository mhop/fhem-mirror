##############################################
# $Id: 99_WOL.pm 1116 2012-01-21 15:01:34Z matthiasklass $
package main;

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);

sub
WOL_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "WOL_Set";
  $hash->{DefFn}     = "WOL_Define";
  $hash->{UndefFn}   = "WOL_Undef";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

###################################
sub
WOL_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of refresh on" if($a[1] eq "?");

  
  my $name = shift @a;
  my $v = join(" ", @a);
  my $logLevel = GetLogLevel($name,2);

  Log $logLevel, "WOL set $name $v";
  
  if($v eq "on") 
  {
    eval {
      for(my $i = 1; $i <= 3; $i++) {
        wake($hash, $logLevel);
      }
    };
    if ($@){
      ### catch block
      Log $logLevel, "WOL error: $@";
    };
    Log $logLevel, "WOL waking $name";
    
  } elsif ($v eq "refresh") 
  {
    WOL_GetUpdate($hash);
  } else
  {
    return "unknown argument $v, choose one of refresh, on";
  }
  
  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;
  
  return undef;
}

sub
WOL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> WOL MAC_ADRESS IP";
  return $u if(int(@a) < 4);
  
  $hash->{MAC} = $a[2];
  $hash->{IP} = $a[3];
  $hash->{INTERVAL} = 600;
  
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_GetUpdate", $hash, 0);
  return undef;
}

sub WOL_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

sub WOL_GetUpdate($)
{
  my ($hash) = @_;
  
  my $ip = $hash->{IP};
  #if (system("ping -q -c 1 $ip > /dev/null") == 0)
  if (`ping -c 1 $ip` =~ m/100/)
  {
    $hash->{READINGS}{state}{VAL} = "off";
    $hash->{READINGS}{isRunning}{VAL} = "false";
  } else
  {
    $hash->{READINGS}{state}{VAL} = "on";
    $hash->{READINGS}{isRunning}{VAL} = "true";
  }
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{isRunning}{TIME} = TimeNow();
  
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_GetUpdate", $hash, 0);
}

sub wake
{
  my ($hash, $logLevel) = @_;
  my $mac = $hash->{MAC};
  
  Log $logLevel, "trying to wake $mac";

  my $response = `/usr/bin/ether-wake $mac`;
  Log $logLevel, "trying etherwake with response: $response";
  
  wol_by_udp($mac);
  Log $logLevel, "trying direct socket via UDP";
}

# method to wake via lan, taken from Net::Wake package
sub wol_by_udp {
  my ($mac_addr, $host, $port) = @_;

  # use the discard service if $port not passed in
  if (! defined $host) { $host = '255.255.255.255' }
  if (! defined $port || $port !~ /^\d+$/ ) { $port = 9 }

  my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
  die "Can't create WOL socket" if(!$sock);
  
  my $ip_addr = inet_aton($host);
  my $sock_addr = sockaddr_in($port, $ip_addr);
  $mac_addr =~ s/://g;
  my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
  
  send($sock, $packet, 0, $sock_addr) or die "send : $!";
  close ($sock);

  return 1;
}

1;
