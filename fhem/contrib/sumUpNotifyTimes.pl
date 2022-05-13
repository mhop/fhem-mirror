#!/usr/bin/perl

# Sum up the time spent in notify loop from a verbose 5 log:
#   2022.05.13 09:36:13.210 5: Starting notify loop for OG1_WZ_MMXBOX, 1 event(s), first is AUS
#   2022.05.13 09:36:13.220 5: End notify loop for OG1_WZ_MMXBOX
# produces
#   2022.05.13 09:36:13.210 0.010 OG1_WZ_MMXBOX
#   ...
#   2022-05-13_09:36:13 percent spent in event loop:  31
# Forum #127077

use strict;
use warnings;

my ($lName, $sTime, $tStamp, $dumped);
my $tsTime = 0;
while(my $l = <>) {

  if($l =~ m/^(.{10}) (..):(..):(..)/) { # Compute the %
    my $ts = $2*3600+$3*60+$4;
    my $ltStamp = $1;
    $ltStamp =~ s/[.]/-/g;
    if($tsTime && $ts != int($sTime) && !$dumped) {
      for(my $i = int($sTime); $i<$ts; $i++) {
        printf("%s_%02d:%02d:%02d percent spent in event loop: %3d\n",
                $ltStamp, $i/3600, ($i%3600)/60, $i%60, 
                ($tsTime-int($tsTime))*100);
        $tsTime -= 1;
        if($tsTime <= 0) {
          $tsTime = 0;
          last;
        }
      }
      $dumped = 1;
    }
  }

  if(!$lName) {
    if($l =~ m/^(.{10} (..):(..):(..).(...)) 5: Starting notify loop for ([^,]+),/) {
      $tStamp = $1;
      $sTime = $2*3600+$3*60+$4+($5/1000);
      $lName = $6;
      $tStamp =~ s/^(....).(..)./$1-$2-/;
      $tStamp =~ s/ /_/;
      $dumped = undef;
    }

  } elsif($lName) {
    if($l =~ m/^.{10} (..):(..):(..).(...) 5: End notify loop for $lName/) {
      my $ts = $1*3600+$2*60+$3+($4/1000)-$sTime;
      $tsTime += $ts;
      printf("%s %0.3f %s\n", $tStamp, $ts, $lName);
      $lName = undef;
      $dumped = undef;
    }

  }
}
