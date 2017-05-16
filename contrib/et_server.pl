#!/usr/bin/perl

# et_server/et_client: an "ssh -Rport" replacement.
# Problem: webserver is behind a firewall without the possibility of opening a
# hole in th firewall. Solution: start et_server on a publicly available host,
# and connect to it via et_client from inside of the firewall. 

use warnings;
use strict;
use IO::Socket;

die "Usage: et_server.pl controlPort serverPort\n"
  if(int(@ARGV) != 2);

my $csfd = IO::Socket::INET->new(LocalPort=>$ARGV[0], Listen=>10, ReuseAddr=>1);
die "Opening port $ARGV[0]: $!\n" if(!$csfd);
my $sfd  = IO::Socket::INET->new(LocalPort=>$ARGV[1], Listen=>10, ReuseAddr=>1);
die "Opening port $ARGV[1]: $!\n" if(!$sfd);
print "Serverports opened, waiting for et_client\n";
my @clientinfo = $csfd->accept();
my $cfd = $clientinfo[0];

my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
print "et called from ".inet_ntoa($iaddr).":$port\n";

my %clients;
for(;;) {
  my ($rin,$rout) = ('','');
  vec($rin, $sfd->fileno(),  1) = 1;
  vec($rin, $cfd->fileno(),  1) = 1;
  vec($rin, $csfd->fileno(), 1) = 1;
  foreach my $c (keys %clients) {
    vec($rin, fileno($clients{$c}{fd}), 1) = 1;
  }

  my $nfound = select($rout=$rin, undef, undef, undef);
  if($nfound < 0) {
    print("select: $!");
    last;
  }

  # New server connection
  if(vec($rout, $sfd->fileno(), 1)) {
    #print "SRV: ACC\n";
    my @clientinfo = $sfd->accept();
    if(!@clientinfo) {
      print "Accept failed: $!";
      next;
    }
    my $fd = $clientinfo[0];
    $clients{$fd}{fd} = $fd;
    syswrite($cfd, "1");
    print "Local conn request\n";
  }

  # New et-line
  if(vec($rout, $csfd->fileno(), 1)) {
    #print "CTL: ACC\n";
    my @clientinfo = $csfd->accept();
    if(!@clientinfo) {
      print "Accept failed: $!\n";
      next;
    }
    my $fd = $clientinfo[0];
    my $peer;
    map { $peer = $_ if(!defined($clients{$_}{peer})) } keys %clients;
    if(!$peer) {
      close($fd);
      print "ET without request\n";
      next;
    }
    $clients{$fd}{fd} = $fd;
    my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
    $clients{$fd}{fd} = $fd;
    $clients{$fd}{addr} = inet_ntoa($iaddr) . ":$port";

    $clients{$fd}{peer} = $peer;
    $clients{$peer}{peer} = $fd;
    if($clients{$peer}{buf}) {
      syswrite($fd, $clients{$peer}{buf});
      delete($clients{$peer}{buf});
    }
    print "ET line established\n";
  }

  if(vec($rout, $cfd->fileno(), 1)) {
    print "ET client left, exiting\n";
    exit(1);
  }

  # Data from one of the clients
CLIENT:foreach my $c (keys %clients) {
    next if(!vec($rout, fileno($clients{$c}{fd}), 1));

    my $peer = $clients{$c}{peer}; $peer = "" if(!$peer);
    my $addr = $clients{$c}{addr}; $addr = "" if(!$addr);

    my $buf;
    my $ret = sysread($clients{$c}{fd}, $buf, 256);
    #print "C:$c: P:$peer R:$ret\n";
    if(!defined($ret) || $ret <= 0) {
      print "Client $addr left us\n";
      if($peer) {
        close($clients{$peer}{fd}); delete($clients{$peer});
      }
      close($clients{$c}{fd}); delete($clients{$c});
      last CLIENT;
    }

    if($peer) {
      while(length($buf)) {
        my $ret = syswrite($clients{$peer}{fd}, $buf);
        if(!$ret) {
          print "Write error to $peer from $c\n";
          close($clients{$peer}{fd}); delete($clients{$peer});
          close($clients{$c}{fd});   delete($clients{$c});
          last CLIENT;
        }
        $buf = substr($buf, $ret);
      }

    } else {
      $clients{$c}{buf} = "" if(!defined($clients{$c}{buf}));
      $clients{$c}{buf} .= $buf;

    }
  }
}
