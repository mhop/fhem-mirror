#!/usr/bin/perl

use strict;
use warnings;
use Device::SerialPort;
use Time::HiRes qw(gettimeofday);
sub pp($$);

if(@ARGV != 4) {
  printf("Usage: perl serial.pl serial-device baudrate outfile initial-hex-msg\n");
  exit(1);
}
my $ser = $ARGV[0];
my $baud = $ARGV[1];
my $fil = $ARGV[2];
my $hm  = $ARGV[3];

my $fd;
open($fd, ">$fil") || die("Can't open $fil for writing\n");
select $fd;
$| = 1;

my $serport = new Device::SerialPort ($ser);
die "Can't open $ser: $!\n" if(!$serport);
$serport->reset_error();
$serport->baudrate($baud);
$serport->databits(8);
$serport->parity('none');
$serport->stopbits(1);
$serport->handshake('none');

my $interval = 2.0;	# Seconds

my $nto = gettimeofday();
my $nfound;

$hm=~ s/ //g;
$hm = pack('H*', $hm);

while (1) {
  my ($rout, $rin) = ('', '');
  vec($rin, 0, 1) = 1;			# stdin
  vec($rin, $serport->FILENO, 1) = 1;

  my $to = $nto - gettimeofday();
  if($to > 0) {
    $nfound = select($rout=$rin, undef, undef, $to);
    die("Select error $nfound / $!\n") if($nfound < 0);
  }

  if($to <= 0 || $nfound == 0) {	# Timeout
    $serport->write($hm);
    pp("S>", $hm);
    $nto = gettimeofday() + $interval;
  }

  if(vec($rout, 0, 1)) {
    my $buf = <STDIN>;
    die "EOF on STDIN\n" if(!defined($buf) || length($buf) == 0);
    $buf=~ s/[ \r\n]//g;
    $buf = pack('H*', $buf);
    $serport->write($buf);
    pp("X>", $buf);
  }
  if(vec($rout, $serport->FILENO, 1)) {
    my $buf = $serport->input();
    die "EOF on $ser\n" if(!defined($buf) || length($buf) == 0);
    pp("S<", $buf);
  }
}

sub
pp($$) {
  my ($prompt, $txt) = @_;

  my ($s, $ms) = gettimeofday();
  my @t = localtime($s);
  my $tim = sprintf("%02d:%02d:%02d.%03d", $t[2],$t[1],$t[0], $ms/1000);

  for(my $i = 0; $i < length($txt); $i += 16) {
    my $a = substr($txt, $i, 16);
    my $h = unpack("H*", $a);
    $a =~ s/[\r\n]/./g;
    $a =~ s/\P{IsPrint}/\./g;
    $h =~ s/(....)/$1 /g;
    printf $fd "%s %s %04d   %-40s %s\n", $prompt, $tim, $i, $h, $a;
  }
  print $fd "\n";

}
