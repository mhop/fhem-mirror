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
dw($$)
{
  my ($t,$p) = @_;
  return w($t,$p+2)*65536 + w($t,$p);
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
  my $pulses=w($d,13);
  my $pulses_max=w($d,15);
  my $ec=w($d,49) / 10;
  my $cur_energy=0;
  my $cur_power=0;
  my $cur_power_max=0;
  my $sum_h_energy=0;
  my $sum_d_energy=0;
  my $sum_w_energy=0;
  my $total_energy=0;
  my $iec=0;

  printf("     Readings       (off  2): %d\n",   w($d,2));
  printf("     Nr devs        (off  6): %d\n",   b($d,6));
  printf("     puls/5min      (off 13): %d\n",   $pulses);
  printf("     puls.max/5min  (off 15): %d\n",   $pulses_max);
  #printf("     Startblk  (off 18): %d\n",   b($d,18)+13);
  #for (my $lauf = 19; $lauf < 45; $lauf += 2) {
  #	printf("     t wert    (off $lauf): %d\n",   w($d,$lauf));
  #}
  # The data must interpreted depending on the sensor type.
  # Currently we use the EC value to quess the sensor type.
  if ($ec eq 0) {
		# Sensor 5..
    $iec = 1000;
    $cur_power  = $pulses / 100;
    $cur_power_max  = $pulses_max / 100;
  } else {
	 # Sensor 1..4
    $iec = $ec;
    $cur_energy = $pulses / $ec; # ec = U/kWh
    $cur_power = $cur_energy / 5 * 60; # 5minute interval scaled to 1h
    printf("     cur.energy(off   ): %.3f kWh\n", $cur_energy);
  }
  $sum_h_energy= dw($d,33) / $iec; # 33= pulses this hour
  $sum_d_energy= dw($d,37) / $iec; # 37= pulses today
  $sum_w_energy= dw($d,41) / $iec; # 41= pulses this week
  $total_energy= dw($d, 7) / $iec; #  7= pulses total
  printf("     cur.power      (      ): %.3f kW\n", $cur_power);
  printf("     cur.power max  (      ): %.3f kW\n", $cur_power_max);
  printf("     energy h       (off 33): %.3f kWh (h)\n", $sum_h_energy);
  printf("     energy d       (off 37): %.3f kWh (d)\n", $sum_d_energy);
  printf("     energy w       (off 41): %.3f kWh (w)\n", $sum_w_energy);
  printf("     total energy   (off  7): %.3f kWh (total)\n", $total_energy);
  printf("     Alarm PA       (off 45): %d W\n", w($d,45));
  printf("     Price CF       (off 47): %0.2f EUR/kWh\n",   w($d,47)/10000);
  printf("     R/kW  EC       (off 49): %d\n",   $ec);
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
  my $smooth = 1; # Set this to 0 to get the "real" values

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
  my $div = w($d,49)/10;
  if ($div eq 0) {
	$div = 1;
  }

  #printf("Total $nrreadings, $start - $end, Nr $step\n");

  my $tm = time()-(($nrreadings-1)*300);
  my $backlog = 0;
  for(my $p = $start; $p <= $end; $p += $step) {
    #printf("Get page $p\n");

    $d = getData(sprintf("52%02x%02x00000801", $p%256, int($p/256)));

    #hexdump($d);

    my $max = (($p == $end) ? ($nrreadings%64)*4+4 : 260);
    my $step = b($d, 7); # Switched from 6 to 7 (Thomas, 2009-12-31)

    for(my $off = 8; $off <= $max; $off += 4) {
      $backlog++;
      if($smooth && (w($d,$off+2) == 0xffff)) { # "smoothing"
        next;
      } else {
	my $v = w($d,$off)*12/$div/$backlog;
	my $f1 = b($d,$off+2);
	my $f2 = b($d,$off+3);
	my $f3 = w($d,$off+2);

        while($backlog--) {
	  printf("%s %0.3f kWh (%d %d %d)\n", maketime($tm), $v,
		    ($backlog?-1:$f1), ($backlog?-1:$f2), ($backlog?-1:$f3));
	  $tm += 300;
	}
	$backlog = 0;
      }
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

  $v = $v * 10;
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
  my $a2 = '';
  my $a3 = '';

  if (@ARGV == 2) {
    my @lt = localtime;
	 $a2 = sprintf ("%04d-%02d-%02d", $lt[5]+1900, $lt[4]+1, $lt[3]);
	 $a3 = sprintf ("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  } else {
    die "Usage: setTime [time] (as YYYY-MM-DD HH:MM:SS, localtime if empty)\n"
          if(@ARGV != 4);
	 $a2 = $ARGV[2];
	 $a3 = $ARGV[3];
  }
  my @d = split("-", $a2);
  my @t = split(":", $a3);

  my $s = sprintf("73%02x%02x%02x00%02x%02x%02x",
        $d[2],$d[1],$d[0]-2000+0xd0,
        $t[0],$t[1],$t[2]);
  print("-> $s\n");

  my $d = getData($s);
  if(b($d,0) == 6) {
    print("OK");
  } else {
    print("Error occured");
    hexdump($d);
  }
}
