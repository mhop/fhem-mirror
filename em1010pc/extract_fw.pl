#!/usr/bin/perl

use warnings;
use strict;

if(@ARGV != 3) {
  die("Usage: extract_fw.pl update.exe <hex_offset> <output_file>\n" .
      "       <hex_offset> is usually 25808\n")
}

open(IN, $ARGV[0]) || die("$ARGV[0]: $!\n");
open(OUT, ">$ARGV[2]") || die("$ARGV[2]: $!\n");

my ($b1, $b2);
my $len = hex($ARGV[1]);
(sysread(IN, $b1, $len) == $len) || die("Cannot read $ARGV[1]/$len bytes\n");

my $count = 0;
for(;;) {
  (sysread(IN, $b1, 2) == 2) || last;
  $len = unpack("n", $b1);
  ($len <= 255) || last;
  (sysread(IN, $b2, $len) == $len) || last;
  print OUT unpack("H*", $b1) . unpack("H*", $b2) . "\n";
  $count++;
}
print "Read $count packets\n";
exit(0);
