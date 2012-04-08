#!/usr/bin/perl

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub kmcrc($);
sub fmt_now();


my $stx = pack('H*', "02");
my $dle = pack('H*', "10");
my $etx = pack('H*', "03");
my $nak = pack('H*', "15");
my $logmode = pack('H*', "EE00001003FD");

# Thx to Himtronics
# http://www.mikrocontroller.net/topic/141831
# http://www.mikrocontroller.net/attachment/63563/km271-protokoll.txt
# Buderus documents: 63011376, 63011377, 63011378
# http://www.buderus.de/pdf/unterlagen/0063061377.pdf
my %trhash =
(
  "8000" =>  'Betriebswerte_1_HK1',             # 76, 4 [repeat]
  "8001" =>  'Betriebswerte_2_HK1',             # 0 (22:33), 2 (7:33)
  "8002" =>  'Vorlaufsolltemperatur_HK1',       # 50-65
  "8003" =>  'Vorlaufisttemperatur_HK1',        # Schwingt um soll herum
  "8004" =>  'Raumsolltemperatur_HK1',          # 34 (22:33) 42 (7:33)
  "8005" =>  'Raumisttemperatur_HK1',
  "8006" =>  'Einschaltoptimierungszeit_HK1',
  "8007" =>  'Ausschaltoptimierungszeit_HK1',
  "8008" =>  'Pumpenleistung_HK1',              # 0/100 == Ladepumpe
  "8009" =>  'Mischerstellung_HK1',
  "800a" =>  'nicht_belegt',
  "800b" =>  'nicht_belegt',
  "800c" =>  'Heizkennlinie_HK1_bei_+_10_Grad', # bei Umschaltung tag/nacht
  "800d" =>  'Heizkennlinie_HK1_bei_0_Grad',    # bei Umschaltung tag/nacht
  "800e" =>  'Heizkennlinie_HK1_bei_-_10_Grad', # bei Umschaltung tag/nacht
  "800f" =>  'nicht_belegt',
  "8010" =>  'nicht_belegt',
  "8011" =>  'nicht_belegt',

  "8112" =>  'Betriebswerte_1_HK2',
  "8113" =>  'Betriebswerte_1_HK2',
  "8114" =>  'Vorlaufsolltemperatur_HK2',
  "8115" =>  'Vorlaufisttemperatur_HK2',
  "8116" =>  'Raumsolltemperatur_HK2',
  "8117" =>  'Raumisttemperatur_HK2',
  "8118" =>  'Einschaltoptimierungszeit_HK2',
  "8119" =>  'Ausschaltoptimierungszeit_HK2',
  "811a" =>  'Pumpenleistung_HK2',
  "811b" =>  'Mischerstellung_HK2',
  "811c" =>  'nicht_belegt',
  "811d" =>  'nicht_belegt',
  "811e" =>  'Heizkennlinie_HK2_bei_+_10_Grad', # == HK1 - (1 bis 3)
  "811f" =>  'Heizkennlinie_HK2_bei_0_Grad',    # == HK1 - (1 bis 3)
  "8120" =>  'Heizkennlinie_HK2_bei_-_10_Grad', # == HK1 - (1 bis 3)
  "8121" =>  'nicht_belegt',
  "8122" =>  'nicht_belegt',
  "8123" =>  'nicht_belegt',

  "8424" =>  'Betriebswerte_1_WW',
  "8425" =>  'Betriebswerte_2_WW',               # 0 64 96 104 225 228
  "8426" =>  'Warmwassersolltemperatur',         # 10/55
  "8427" =>  'Warmwasseristtemperatur',          # 32-55
  "8428" =>  'Warmwasseroptimierungszeit',
  "8429" =>  'Ladepumpe',                        # 0 1 (an/aus?)

  # 1377, page 13
  "882a" =>  'Kesselvorlaufsolltemperatur',
  "882b" =>  'Kesselvorlaufisttemperatur',       # == Vorlaufisttemperatur_HK1
  "882c" =>  'Brennereinschalttemperatur',       #  5-81
  "882d" =>  'Brennerausschalttemperatur',       # 19-85
  "882e" =>  'Kesselintegral_1',                 #  0-23
  "882f" =>  'Kesselintegral_2',                 #  0-255
  "8830" =>  'Kesselfehler',
  "8831" =>  'Kesselbetrieb',                    # 0 2 32 34
  "8832" =>  'Brenneransteuerung',               # 0 1 (an/aus?)
  "8833" =>  'Abgastemperatur',
  "8834" =>  'modulare_Brenner_Stellwert',
  "8835" =>  'nicht_belegt',
  "8836" =>  'Brennerlaufzeit_1_Stunden_2',
  "8837" =>  'Brennerlaufzeit_1_Stunden_1',      # 176
  "8838" =>  'Brennerlaufzeit_1_Stunden_0',      # 0-255 (Minuten)
  "8839" =>  'Brennerlaufzeit_2_Stunden_2',
  "883a" =>  'Brennerlaufzeit_2_Stunden_1',
  "883b" =>  'Brennerlaufzeit_2_Stunden_0',

  # 1377, page 16
  "893c" =>  'Aussentemperatur',                # 0 1 254 255
  "893d" =>  'gedaempfte_Aussentemperatur',     # 0 1 2
  "893e" =>  'Versionsnummer_VK',
  "893f" =>  'Versionsnummer_NK',
  "8940" =>  'Modulkennung',
  "8941" =>  'nicht_belegt',
);


die("Usage: km271.pl <device>\n") if(int(@ARGV) != 1);

require Device::SerialPort;
my $po = new Device::SerialPort($ARGV[0]);
die("Can't open $ARGV[0]: $!\n") if(!$po);

$po->reset_error();
$po->baudrate(2400);
$po->databits(8);
$po->parity('none');
$po->stopbits(1);
$po->handshake('none');

my $fdin = $po->FILENO;
printf("Setting device into logmode\n");
$po->write($logmode);


$| = 1;
my $tbuf = "";

for(;;) {
  my ($rout, $rin) = ('', '');

  vec($rin, $fdin, 1) = 1;

  my $nfound = select($rout=$rin, undef, undef, undef);
  die("Select error: $!\n") if(!defined($nfound) || $nfound < 0);

  if(vec($rout, $fdin, 1)) {
    my $buf = $po->input();
    if(!defined($buf)) {
      printf("EOF on dev\n");
      exit(1);
    }

    $buf = unpack('H*', $buf);
    #printf("%s DEV %s\n", fmt_now(), $buf);
    if($buf eq "02") {
      $tbuf = "";
      $po->write($dle);
      next;
    }

    $tbuf .= $buf;
    my $len = length($tbuf);
    next if($tbuf !~ m/^(.*)1003(..)$/);
    my ($data, $crc) = ($1, $2);
    if(kmcrc($data) ne $crc) {
      printf("Wrong CRC in $tbuf ($crc vs. %s)\n", kmcrc($data));
      $tbuf = "";
      $po->write($nak);
      next;
    }
    $po->write($dle);

    $data =~ s/1010/10/g;
    if($data =~ m/^(8...)(..)/) {
      my ($fn, $arg) = ($1, $2);
      printf("%s %s %d\n", fmt_now(), $trhash{$fn}, hex($arg));
    } elsif($data eq "04000701c4024192") {
      # No data message
    } else {
      printf("%s UNKNOWN %s\n", fmt_now(), $data);
    }
    $tbuf = "";

  }
}

sub
kmcrc($)
{
  my $in = shift;
  my $x = 0;
  foreach my $a (split("", pack('H*', $in))) {
    $x ^= ord($a);
  }
  $x ^= 0x10;
  $x ^= 0x03;
  return sprintf("%02x", $x);
}

sub
fmt_now()
{
  my $now = gettimeofday()+0.0;
  my @t = localtime($now);
  my $t = sprintf("%04d-%02d-%02d_%02d:%02d:%02d.%03d",
               $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0],
               ($now-int($now)) * 1000);
  return $t;
}

