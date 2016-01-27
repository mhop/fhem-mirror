#!/usr/bin/perl

# Details in Forum #35416

if(@ARGV == 0) {
  print "Usage:\n".
    "  mkdir -p <fhem>/www/deviceimages/zwave\n".
    "  cd <fhem>/www/deviceimages/zwave\n".
    "  wget http://www.pepper1.net/zwavedb/device/export/device_archive.zip\n".
    "  unzip device_archive.zip\n".
    "  perl <fhem>/contrib/zwave_pepperconvert.pl *.xml\n".
    "  sh getpics.sh\n".
    "  rm *.xml *.txt *.sh *.zip\n".
    "  gzip zwave_pepperlinks.csv\n";
    "  mv zwave_pepperlinks.csv.gz <fhem>/FHEM/lib\n";
  exit 1;
}

open(F1, ">zwave_pepperlinks.csv") || die("zwave_pepperlinks.csv: $!\n");
open(F2, ">getpics.sh") || die("getpics.sh: $!\n");
my $d="";
my %toget;
while(my $l = <>) {
  if($l =~ m,<deviceImage\s*url="(.*)"\s*/>,) {
    $d = $1;
    $d =~ s/^\s*//;
    $d =~ s/\s*$//;
  }
  if($l =~ m,</ZWaveDevice,i) {
    my $lf = $d;
    $lf =~ s,^.*/,,;
    if($ARGV =~ m/^([0-9A-F]+)-([0-9A-F]+)-([0-9A-F]+)-([0-9A-F]+)-/i) {
      print F1 "$2-$3-$4,$1,$lf\n";
    } else {
      print F1 "$ARGV\n";
    }

    if($lf && !-f $lf && !$toget{$lf}) {
      printf F2 "wget $d\n";
      $toget{$lf} = 1;
    }
    $d="";
  }
}
close(F1);
close(F2);
