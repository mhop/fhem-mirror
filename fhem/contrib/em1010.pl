#!/usr/bin/perl

use strict;
use warnings;
use Device::SerialPort;

sub b($$);
sub w($$);
sub docrc($$);
sub checkcrc($$);
sub getData($);
sub makemsg($);
sub maketime($);

my %cmd = (
  "getVersion" => 1, 
  "getTime" => 1, 
  "getDevStatus" => 1, 
  "getDevPage" => 1, 
  "getDevData" => 1, 
  "setPrice" => 1, 
  "setAlarm" => 1, 
  "setRperKW" => 1, 
  "get62" => 1, 
  "setTime" => 1, 
  "reset" => 1, 
);
  

if(@ARGV < 2) {
  printf("Usage: perl em1010.pl serial-device command args\n");
  exit(1);
}
my $ser = $ARGV[0];

my $fd;

#####################
# Open serial port
my $serport = new Device::SerialPort ($ser);
die "Can't open $ser: $!\n" if(!$serport);
$serport->reset_error();
$serport->baudrate(38400);
$serport->databits(8);
$serport->parity('none');
$serport->stopbits(1);
$serport->handshake('none');

my $cmd = $ARGV[1];
if(!defined($cmd{$cmd})) {
  printf("Unknown command $cmd, use one of " . join(" ",sort keys %cmd) . "\n");
  exit(0);
}

###########################
no strict "refs";
&{$cmd }();
use strict "refs";
exit(0);

#########################
sub
maketime($)
{
 my @l = localtime(shift);
 return sprintf("%04d-%02d-%02d_%02d:%02d:00",
                1900+$l[5],$l[4]+1,$l[3],$l[2],$l[1]-$l[1]%5);
}

#########################
sub
b($$)
{
  my ($t,$p) = @_;
  return ord(substr($t,$p,1));
}

#########################
sub
w($$)
{
  my ($t,$p) = @_;
  return b($t,$p+1)*256 + b($t,$p);
}

#########################
sub
docrc($$)
{
  my ($in, $val) = @_;
  my ($crc, $bits) = (0, 8);
  my $k = (($in >> 8) ^ $val) << 8;
  while($bits--) {
    if(($crc ^ $k) & 0x8000) {
      $crc = ($crc << 1) ^ 0x8005;
    } else {
      $crc <<= 1;
    }
    $k <<= 1;
  }
  return (($in << 8) ^ $crc) & 0xffff;
}

#########################
sub
checkcrc($$)
{
  my ($otxt, $len) = @_;
  my $crc = 0x8c27;
  for(my $l = 2; $l < $len+4; $l++) {
    my $b = ord(substr($otxt,$l,1));
    $crc = docrc($crc, 0x10) if($b==0x02 || $b==0x03 || $b==0x10);
    $crc = docrc($crc, $b);
  }
  return ($crc == w($otxt, $len+4));
}

#########################
sub
esc($)
{
  my ($b) = @_;

  my $out = "";
  $out .= chr(0x10) if($b==0x02 || $b==0x03 || $b==0x10);
  $out .= chr($b);
}

#########################
sub
makemsg($)
{
  my ($data) = @_;
  my $len = length($data);
  $data = chr($len&0xff) . chr(int($len/256)) . $data;

  my $out = pack('H*', "0200");
  my $crc = 0x8c27;
  for(my $l = 0; $l < $len+2; $l++) {
    my $b = ord(substr($data,$l,1));
    $crc = docrc($crc, 0x10) if($b==0x02 || $b==0x03 || $b==0x10);
    $crc = docrc($crc, $b);
    $out .= esc($b);
  }
  $out .= esc($crc&0xff);
  $out .= esc($crc/256);
  $out .= chr(0x03);
  return $out;
}


#########################
sub
getData($)
{
  my ($d) = @_;
  $d = makemsg(pack('H*', $d));
  #print "Sending: " . unpack('H*', $d) . "\n";

  for(my $rep = 0; $rep < 3; $rep++) {

    #printf "write (try nr $rep)\n";
    $serport->write($d);

    my $retval = "";
    my $esc = 0;
    my $started = 0;
    my $complete = 0;
    for(;;) {
      my ($rout, $rin) = ('', '');
      vec($rin, $serport->FILENO, 1) = 1;
      my $nfound = select($rout=$rin, undef, undef, 1.0);

      die("Select error $nfound / $!\n") if($nfound < 0);
      last if($nfound == 0);

      my $buf = $serport->input();
      die "EOF on $ser\n" if(!defined($buf) || length($buf) == 0);

      for(my $i = 0; $i < length($buf); $i++) {
        my $b = ord(substr($buf,$i,1));

        if(!$started && $b != 0x02) { next; }
        $started = 1;
        if($esc) { $retval .= chr($b); $esc = 0; next; }
        if($b == 0x10) { $esc = 1; next; }
        $retval .= chr($b);
        if($b == 0x03) { $complete = 1; last; }
      }
      if($complete) {
        my $l = length($retval);
        if($l < 8)                  { printf("Msg too short\n"); last; }
        if(b($retval,1) != 0)       { printf("Bad second byte\n"); last; }
        if(w($retval,2) != $l-7)    { printf("Length mismatch\n"); last; }
        if(!checkcrc($retval,$l-7)) { printf("Bad CRC\n"); last; }
        return substr($retval, 4, $l-7);
      }
    }
  }

  printf "Timeout reading the answer\n";
  exit(1);
}
#########################
sub
hexdump($)
{
  my ($d) = @_;
  for(my $i = 0; $i < length($d); $i += 16) {
    my $h = unpack("H*", substr($d, $i, 16));
    $h =~ s/(....)/$1 /g;
    printf "RAW    %-40s\n", $h;
  }
}

#########################
sub
getVersion()
{
  my $d = getData("76");
  printf "%d.%d\n", b($d,0), b($d,1);
}

#########################
sub
getTime()
{
  my $d = getData("74");
  printf("%4d-%02d-%02d %02d:%02d:%02d\n",
          b($d,5)+2006, b($d,4), b($d,3),
          b($d,0), b($d,1), b($d,2));
}

#########################
sub
getDevStatus()
{
  die "Usage: getDevStatus devicenumber (1-12)\n" if(@ARGV != 3);
  my $d = getData(sprintf("7a%02x",$ARGV[2]-1));

  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    printf("     No device no. $ARGV[2] present\n");
    return;
  }
  printf("     Readings  (off 02): %d\n",   w($d,2));
  printf("     Nr devs   (off 05): %d\n",   b($d,6));
  printf("     Startblk  (off 18): %d\n",   b($d,18)+13);
  printf("     Alarm     (off 45): %d W\n", w($d,45));
  printf("     PRICE     (off 47): %0.2f (EUR/KWH)\n",   w($d,47)/10000);
  printf("     R/KW user (off 49): %d\n",   w($d,49)/10);
  hexdump($d);
}

#########################
sub
getDevPage()
{
  die "Usage: getDevPage pagenumber [length] (default length is 264)\n"
        if(@ARGV < 3);
  my $l = (@ARGV > 3 ? $ARGV[3] : 264);
  my $d = getData(sprintf("52%02x%02x0000%02x%02x",
                $ARGV[2]%256, int($ARGV[2]/256), $l%256, int($l/256)));
  hexdump($d);
}

#########################
sub
getDevData()
{
  die "Usage: getDevData devicenumber (1-12)\n" if(@ARGV != 3);
  my $d = getData(sprintf("7a%02x",$ARGV[2]-1));

  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    printf("     No device no. $ARGV[2] present\n");
    return;
  }

  my $nrreadings = w($d,2);
  if($nrreadings == 0) {
    printf("No data to read (yet?)\n");
    exit(0);
  }
  my $step = b($d,6);
  my $start =  b($d,18)+13;
  my $end = $start + int(($nrreadings-1)/64)*$step;
  my $offset = ($nrreadings%64)*4+4;
  my $div = w($d,49)/10;

  #printf("Total $nrreadings, $start - $end, Nr $step, Off: $offset\n");

  my $now = time();
  for(my $p = $end; $p >= $start; $p -= $step) {
    #printf("Get page $p\n");
    $d = getData(sprintf("52%02x%02x00000801", $p%256, int($p/256)));
    #hexdump($d);
    $offset = 260 if($p != $end);
    while($offset >= 8) {
      printf("%s %0.3f kWh (%d)\n",
        maketime($now), w($d,$offset)*12/$div, w($d,$offset+2));
      $offset -=4;
      $now -= 300;
    }
  }
}

sub
setPrice()
{
  die "Usage: setPrice device value_in_cent\n"
        if(@ARGV != 4);
  my $d = $ARGV[2];
  my $v = $ARGV[3];

  $d = getData(sprintf("79%02x2f02%02x%02x", $d-1, $v%256, int($v/256)));
  if(b($d,0) == 6) {
    print("OK");
  } else {
    print("Error occured");
    hexdump($d);
  }
}

sub
setAlarm()
{
  die "Usage: setAlarm device value_in_kWh\n"
        if(@ARGV != 4);
  my $d = $ARGV[2];
  my $v = $ARGV[3];

  $d = getData(sprintf("79%02x2d02%02x%02x", $d-1, $v%256, int($v/256)));
  if(b($d,0) == 6) {
    print("OK");
  } else {
    print("Error occured");
    hexdump($d);
  }
}

sub
setRperKW()
{
  die "Usage: setRperKW device rotations_per_KW\n"
        if(@ARGV != 4);
  my $d = $ARGV[2];
  my $v = $ARGV[3];

  $d = getData(sprintf("79%02x3102%02x%02x", $d-1, $v%256, int($v/256)));
  if(b($d,0) == 6) {
    print("OK");
  } else {
    print("Error occured");
    hexdump($d);
  }
}

sub
reset()
{
  my $d = getData("4545");
  hexdump($d);
}

sub
get62()
{
  my $d = getData("62");
  hexdump($d);
}

sub
setTime()
{
  die "Usage: settime time (as YYYY-MM-DD HH:MM:DD)\n"
        if(@ARGV != 4);
  my @d = split("-", $ARGV[2]);
  my @t = split(":", $ARGV[3]);

  my $d = getData(sprintf("73%02x%02x%02x00%02x%02x%02x",
        $d[2],$d[1],$d[0]-2000+0xd0,
        $t[0],$t[1],$2[2]));
  if(b($d,0) == 6) {
    print("OK");
  } else {
    print("Error occured");
    hexdump($d);
  }
}
