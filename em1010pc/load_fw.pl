#!/usr/bin/perl

use strict;
use warnings;
use Device::SerialPort;

die("Usage: perl load_fw.pl firmware_file serial-device\n") if(@ARGV != 2);

open(IN, $ARGV[0]) || die("$ARGV[0]: $!\n");

#####################
# Open serial port
my $serport = new Device::SerialPort ($ARGV[1]);
die "$ARGV[1]: $!\n" if(!$serport);
$serport->reset_error();
$serport->baudrate(38400);
$serport->databits(8);
$serport->parity('none');
$serport->stopbits(1);
$serport->handshake('none');

my $count;
while(my $l = <IN>) {
  
  chomp($l);
  my $buf = pack("H*", $l);
  $serport->write($buf);

  my ($rout, $rin) = ('', '');
  vec($rin, $serport->FILENO, 1) = 1;
  my $nfound = select($rout=$rin, undef, undef, 3.0);

  die("Select error $nfound / $!\n") if($nfound < 0);
  die("Timeout!\n") if($nfound == 0);

  $buf = $serport->input();
  die("Received ".unpack("H*",$buf)." after $count packets\n")
        if(unpack("H*",$buf) ne "11");

  $count++;
  print "$count\r";
  $| = 1;
}
print "$count packets written\n";
