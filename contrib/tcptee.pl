#!/usr/bin/perl

# it is actually a 1-m tcp data distributor.

use warnings;
use strict;
use IO::Socket;

my $bidi;
my $loop;
my $myIp;
my $myPort;
my $serverHost;
my $serverPort;
my $usage = "Usage: tcptee.pl [--bidi] [--loop] " .
            "[myIp:]myPort:serverHost:serverPort\n";

while(@ARGV) {
  my $opt = shift @ARGV;

  if($opt =~ m/^--bidi$/i) {
    $bidi = 1;

  } elsif($opt =~ m/^--loop$/i) {
    $loop = 1

  } elsif($opt =~ m/^(.*):(\d+):(.*):(\d+)/) {
    $myIp = $1;
    $myPort = $2;
    $serverHost = $3;
    $serverPort = $4;

  } elsif($opt =~ m/^(\d+):(.*):(\d+)/) {
    $myPort = $1;
    $serverHost = $2;
    $serverPort = $3;

  } else {
    die $usage;

  }
}

die $usage if(!$serverHost);

my ($sfd, $myfd, %clients, $discoMsg);

sub
tPrint($)
{
  my $arg = shift;
  my @t = localtime;
  printf("%04d.%02d.%02d %02d:%02d:%02d %s\n",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0], $arg);
}


for(;;) {

  # Open the server first
  $sfd = IO::Socket::INET->new(PeerAddr => "$serverHost:$serverPort");
  if(!$sfd) {
    tPrint "Cannot connect to $serverHost:$serverPort : $!" if(!$discoMsg);
    $discoMsg = 1;
    last if(!$loop);
    sleep(5);
    next;
  }
  $discoMsg = 1;
  tPrint "Connected to $serverHost:$serverPort";


  # Now open our listener
  $myfd = IO::Socket::INET->new(
              LocalHost => $myIp,
              LocalPort => $myPort,
              Listen    => 10,
              ReuseAddr => 1
          );
  die "Opening port $myPort: $!\n" if(!$myfd);
  tPrint "Port $myPort opened";

  my $firstmsg; # HMLAN special

  # Data loop
  for(;;) {
    my ($rin,$rout) = ('','');
    vec($rin, $sfd->fileno(),  1) = 1;
    vec($rin, $myfd->fileno(), 1) = 1;
    foreach my $c (keys %clients) {
      vec($rin, fileno($clients{$c}{fd}), 1) = 1;
    }

    my $nfound = select($rout=$rin, undef, undef, undef);
    if($nfound < 0) {
      tPrint("select: $!");
      last;
    }

    # New connection
    if(vec($rout, $myfd->fileno(), 1)) {
      my @clientinfo = $myfd->accept();
      if(!@clientinfo) {
        tPrint "Accept failed: $!";
        next;
      }
      my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
      my $fd = $clientinfo[0];
      $clients{$fd}{fd} = $fd;
      $clients{$fd}{addr} = inet_ntoa($iaddr) . ":$port";
      tPrint "Connection accepted from $clients{$fd}{addr}";

      syswrite($fd, $firstmsg) if($firstmsg);
    }

    # Data from the server
    if(vec($rout, $sfd->fileno(), 1)) {
      my $buf;
      my $ret = sysread($sfd, $buf, 256);
      if(!defined($ret) || $ret <= 0) {
        tPrint "Short read from the server, disconnecting the clients.";
        last;
      }
      foreach my $c (keys %clients) {
        syswrite($clients{$c}{fd}, $buf);
      }
      $firstmsg = $buf if(!$firstmsg);
    }

    # Data from one of the clients
    foreach my $c (keys %clients) {
      next if(!vec($rout, fileno($clients{$c}{fd}), 1));
      my $buf;
      my $ret = sysread($clients{$c}{fd}, $buf, 256);
      if(!defined($ret) || $ret <= 0) {
        close($clients{$c}{fd});
        tPrint "Client $clients{$c}{addr} left us";
        delete($clients{$c});
        next;
      }

      syswrite($sfd, $buf);
      if($bidi) {
        foreach my $c2 (keys %clients) {
          syswrite($clients{$c2}{fd}, $buf) if($c2 ne $c);
        }
      }
    }

  }

  close($sfd);
  close($myfd);
  foreach my $c (keys %clients) {
    close($clients{$c}{fd});
    delete($clients{$c});
  }
  last if(!$loop);
  sleep(1);
}
