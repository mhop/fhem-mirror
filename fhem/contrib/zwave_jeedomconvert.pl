#!/usr/bin/perl

use strict;
use warnings;

if(@ARGV != 0) {
  print "Usage:\n".
    "  git clone https://github.com/jeedom/plugin-openzwave".
    "  cd plugin-openzwave/core/config".
    "  gzip -d < <fhem>/FHEM/lib/zwave_pepperlinks.csv.gz > zwave_pepperlinks.csv\n".
    "  perl <fhem>/contrib/zwave_jeedomconvert.pl\n".
    "  copy *.jpg to fhem.de/deviceimages/zwave\n".
    "  gzip < zwave_pepperlinks.csv.NEW > <fhem>/FHEM/lib/zwave_pepperlinks.csv.gz\n".
    "  rm *.jpg\n";
  exit 1;
}

open(F1, "<zwave_pepperlinks.csv") || die("zwave_pepperlinks.csv: $!\n");

my %m;
while(my $l = <F1>) {
  chomp($l);
  my @a = split(/,/,$l);
  $m{$a[0]}{L} = $a[1];
  $m{$a[0]}{P} = $a[2];
}
close(F1);

open(F1, "find devices -name \\*.jpg -print|") || die("Cant start find: $!\n");
while(my $l = <F1>) {
  chomp($l);
  next if($l !~ m,/(\d+)\.(\d+)\.(\d+)_(.*)$,);
  my $i = sprintf("%04x-%04x-%04x", $1, $2, $3);
  next if($m{$i} && $m{$i}{P});
  my $file = "$1.$2.$3_$4";
  $file =~ s/ /_/g;
  print "WARNING: bogus filename $file\n" if($file =~ m/^[^0-9A-Za-z.]+$/);
  $m{$i}{P} = $file;
  `cp "$l" $file`;
}
close(F1);

open(F2, ">zwave_pepperlinks.csv.NEW") || die("zwave_pepperlinks.csv.NEW: $!\n");
for my $i (sort keys %m) {
  my ($l,$p) = ($m{$i}{L}, $m{$i}{P});
  next if(!$l && !$p);
  $l = "" if(!$l);
  $p = "" if(!$p);
  print F2 "$i,$l,$p\n";
}
close(F2);
