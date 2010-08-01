#!/usr/bin/perl

die("Usage: crc <HEX-MESSAGE> <CRC>\n") if(int(@ARGV) != 2);
my $msg = $ARGV[0];
$msg =~ s/ //g;

my $des = $ARGV[1];
$des =~ s/ //g;

# FFFF: 77 72 statt 2c 7f
# FFFF: 5C AC statt DC D9


#for(my $ic = 0; $ic < 65536; $ic++) {
for(my $ic = 0; $ic < 2; $ic++) {
  my $crc = ($ic == 0?0:0xffffffff);
  for(my $i = 0; $i < length($msg); $i += 2) {
    my $n  = ord(pack('H*', substr($msg, $i, 2)));

    my $od = $n;
    for my $b (0..7) {
      my $crcbit = ($crc & 0x80000000) ? 1 : 0;
      my $databit = ($n & 0x80) ? 1 : 0;
      $crc <<= 1;
      $n <<= 1;
      $crc ^= 0x04C11DB7 if($crcbit != $databit);
#      printf("%3d.%d %02x CRC %x ($crcbit $databit)\n", $i/2, $b, $n, $crc);
    }
#    printf("%3d %02x CRC %02x %02x\n", $i/2, $od, ($crc&0xff00)>>8, $crc&0xff);
  }
#  print "$ic\n" if($ic % 10000 == 0);
  printf("%02x %02x\n",($crc&0xff00)>>8,$crc&0xff);
  print "got $ic\n"
      if(sprintf("%02x%02x",($crc&0xff00)>>8,$crc&0xff) eq $des);
}
