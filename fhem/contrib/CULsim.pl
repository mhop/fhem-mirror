#!/usr/bin/perl

# Used for SCC testing.

use strict;
use warnings;
use IO::Socket;

my $port = "12345";
my $serverSock = IO::Socket::INET->new(
   Listen    => 5,
   LocalAddr => 'localhost',
   LocalPort => $port,
   Proto     => 'tcp',
   ReuseAddr => 1
);

die "Can't open server port: $!" if(!$serverSock);
print "Opened port $port\n";

my %selectlist;
$selectlist{$serverSock->fileno()} = $serverSock;
my $cnt=0;

for(;;) {
  my ($rout,$rin) = ('','');
  map { vec($rin, $_, 1) = 1; } keys %selectlist;

  my $nfound = select($rout=$rin, undef, undef, 60);
  die "select error: $!" if($nfound < 0);

  if($nfound == 0) { # timeout
    $cnt++;

    my $msg = "";
    if($cnt % 3 == 0) {
      $msg = "T123400A62D04";
    } elsif($cnt % 3 == 1) {
      $msg = "*T123400A62D04";
    } else {
      $msg = "**T123400A62D04";
    }
    
    foreach my $fd (keys %selectlist) {
      if($fd != $serverSock->fileno()) {
        my $h = $selectlist{$fd};
        print "$h->{addr}:$h->{port}: snd >$msg<\n";
        syswrite($h->{sock}, $msg."\n");
      }
    }
  }

  foreach my $fd (keys %selectlist) {
    next if(!vec($rout, $fd, 1));
    my $h = $selectlist{$fd};

    if($fd == $serverSock->fileno()) {
      my @clientinfo = $h->accept();
      if(!@clientinfo) {
        print "Accept failed: $!\n";

      } else {
        my ($port, $iaddr) = sockaddr_in($clientinfo[1]);
        my %hash = ( port    => $port,
                     addr    => inet_ntoa($iaddr),
                     sock    => $clientinfo[0],
                     partial => "");
        print "$hash{addr}:$hash{port}: Connect\n";
        $selectlist{$clientinfo[0]->fileno()} = \%hash;
      }

      next;
    }

    my $buf;
    if(sysread($h->{sock}, $buf, 256) <= 0) {
      print "$h->{addr}:$h->{port}: left us\n";
      delete $selectlist{$fd};
      next;
    }

    $buf = $h->{partial} . $buf;
    while($buf =~ m/\n/) {
      $cnt++;
      my ($cmd, $rest) = split("\n", $buf, 2);
      print "$h->{addr}:$h->{port}: $cnt rcv >$cmd<\n";
      my $stars;
      $cmd =~ m/^(\**)(.*)$/;
      $stars = $1; $cmd = $2;

      my @msg;
      if($cmd eq "V")  {
        push @msg, "E01015BE2940100B80B" if($cnt > 5); # Forum #57806
        push @msg, $stars."V 1.6".length($stars)." CUL868";

      } elsif($cmd eq "T01"){
        push @msg, $stars."0000";

      } elsif($cmd =~ m/^is/){
        push @msg, $stars.$cmd;

      } elsif($cmd eq "?") {
        push @msg, $stars."? (? is unknown) Use one of A B b C E e F f G h i K l M m N R T t U u V W X x Y Z";

      } elsif($cmd eq "t") {
        push @msg, $stars.sprintf("%08X", (time()%86400)*125);

      }
      if(@msg) {
        print "$h->{addr}:$h->{port}:    =>".join(",",@msg)."<\n";
        syswrite($h->{sock}, join("\n",@msg)."\n");
      }

      $buf = $rest;
    }
    $h->{partial} = $buf;

  }
}

