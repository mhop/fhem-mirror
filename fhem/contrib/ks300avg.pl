#!/usr/bin/perl

# Compute Daily and monthly avarage temp/hum/wind and cumulative rain values
# from the "standard" KS300 logs.
# Best to concatenate all KS300-logs into one big file (cat out*.log > big.log)
# and then start the program with ks300avg.pl big.log
# Note: the program assumes that there are no "holes" in the logs.

use strict;
use warnings;

if(@ARGV != 1) {
  print "Usage: ks300avg.pl KS300-logfile\n";
  exit(1);
}

open(FH, $ARGV[0]) || die("$ARGV[0]: $!\n");

my ($mt, $mh, $mw, $md) = (0,0,0,0);
my ($t, $h, $w) = (0,0,0);
my (@ld, $lsec, $lr, $mr, $ldsec);
my ($dt, $dev, $sec, @a);

while(my $l = <FH>) {
  next if($l =~ m/avg/);

  chomp $l;
  @a = split(" ", $l);
  $dev = $a[1];
  $dt = $a[0];
  my @d = split("[_:-]", $a[0]);
  $sec = $d[3]*3600+$d[4]*60+$d[5];

  if(!$lsec) {
    @ld = @d;
    $lr = $a[9];
    $mr = $a[9];
    $lsec = $ldsec = $sec;
    next;
  }

  my $difft = $sec - $lsec;
  $difft += 86400 if($d[2] != $ld[2]);

  $lsec = $sec;
  $t += $difft * $a[3];
  $h += $difft * $a[5];
  $w += $difft * $a[7];

  $l = <FH>;

  if($d[2] != $ld[2]) {	# Day changed
    my $diff = ($sec - $ldsec) + 86400;
    $t /= $diff; $h /= $diff; $w /= $diff;
    printf("$dt $dev avg_day T: %.1f H: %d W: %0.1f R: %.1f\n",
	      $t, $h, $w, $a[9]-$lr);
    $lr = $a[9];
    $md++;
    $mt += $t; $mh += $h; $mw += $w;
    $t = $h = $w = 0;
    $ldsec = $sec;
  }

  if($d[1] != $ld[1]) { # Month changed
    printf("$dt $dev avg_month T: %.1f H: %d W: %0.1f R: %.1f\n",
	      $mt/$md, $mh/$md, $mw/$md, $a[9]-$mr);
    $mr = $a[9];
    $mt = $mh = $mw = $md = 0;
  }

  @ld = @d;
}

printf("$dt $dev avg_day T: %.1f H: %d W: %0.1f R: %.1f\n",
	  $t/$sec, $h/$sec, $w/$sec, $a[9]-$lr);
printf("$dt $dev avg_month T: %.1f H: %d W: %0.1f R: %.1f\n",
	  $mt/$md, $mh/$md, $mw/$md, $a[9]-$mr);
