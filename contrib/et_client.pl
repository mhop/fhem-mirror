#!/usr/bin/perl

# et_server/et_client: an "ssh -Rport" replacement.
# Problem: webserver is behind a firewall without the possibility of opening a
# hole in th firewall. Solution: start et_server on a publicly available host,
# and connect to it via et_client from inside of the firewall. 

use warnings;
use strict;
use IO::Socket;

die "Usage: et_client.pl et_serverhost:Port localhost:Port\n"
  if(int(@ARGV) != 2);

my $cfd = IO::Socket::INET->new(PeerAddr=>$ARGV[0]);
die "Opening port $ARGV[0]: $!\n" if(!$cfd);

my %clients;
for(;;) {
  my ($rin,$rout) = ('','');
  vec($rin, $cfd->fileno(),  1) = 1;
  foreach my $c (keys %clients) {
    vec($rin, fileno($clients{$c}{fd}), 1) = 1;
  }

  my $nfound = select($rout=$rin, undef, undef, undef);
  if($nfound < 0) {
    print("select: $!");
    last;
  }

  # New et-line request
  if(vec($rout, $cfd->fileno(), 1)) {
    my $buf;
    my $ret = sysread($cfd, $buf, 1);
    if(!defined($ret) || $ret <= 0) {
      print "ET_Server left us\n";
      exit(1);
    }
    my $fd1 = IO::Socket::INET->new(PeerAddr=>$ARGV[0]);
    if(!$fd1) {
      print "Connect to $ARGV[0] failed";
      exit(1);
    }
    $fd1->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1); 

    my $fd2 = IO::Socket::INET->new(PeerAddr=>$ARGV[1]);
    if(!$fd2) {
      print "Connect to $ARGV[1] failed";
      exit(1);
    }
    $fd2->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1); 

    $clients{$fd1}{fd}   = $fd1;
    $clients{$fd2}{fd}   = $fd2;
    $clients{$fd1}{peer} = $fd2;
    $clients{$fd2}{peer} = $fd1;
    $clients{$fd1}{type} = "ET";
    $clients{$fd2}{type} = "LC";
    print "ET line established\n";
  }

  # Data from one of the clients
CLIENT:foreach my $c (keys %clients) {
    my $fno = fileno($clients{$c}{fd});
    next if(!vec($rout, $fno, 1));

    my $peer = $clients{$c}{peer};

    my $buf;
    my $ret = sysread($clients{$c}{fd}, $buf, 256);
    #print "$c: $ret\n";
    if(!defined($ret) || $ret <= 0) {
      print "Client $fno left us ($clients{$c}{type})\n";
      if($peer) {
        close($clients{$peer}{fd}); delete($clients{$peer});
      }
      close($clients{$c}{fd}); delete($clients{$c});
      last CLIENT;
    }

    while(length($buf)) {
      my $ret = syswrite($clients{$peer}{fd}, $buf);
      if(!$ret) {
        print "Write error to peer of $fno ($clients{$c}{type})\n";
        close($clients{$peer}{fd}); delete($clients{$peer});
        close($clients{$c}{fd});   delete($clients{$c});
        last CLIENT;
      }
      $buf = substr($buf, $ret);
    }

  }
}
