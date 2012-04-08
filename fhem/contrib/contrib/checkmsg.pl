#!/usr/bin/perl
die("Usage: checkmsg HEX-FHZ-MESSAGE\n") if(int(@ARGV) != 1);
my $msg = $ARGV[0];

die("Bad prefix (not 0x81)\n") if($msg !~ m/^81/);
print("Prefix is ok (0x81)\n");

my $l = hex(substr($msg, 2, 2));
my $rl = length($msg)/2-2;
die("Bad length $rl (should be $l)\n") if($rl != $l);
print("Length is ok ($l)\n");

my @data;
for(my $i = 8; $i < length($msg); $i += 2) {
  push(@data, ord(pack('H*', substr($msg, $i, 2))));
}

my $rcrc = 0;
map { $rcrc += $_; } @data;
$rcrc &= 0xFF;

my $crc = hex(substr($msg, 6, 2));
my $str = sprintf("Bad CRC 0x%02x (should be 0x%02x)\n", $crc, $rcrc);
die($str) if($crc ne $rcrc);
printf("CRC is ok (0x%02x)\n", $crc);

exit(0);
