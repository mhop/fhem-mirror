#!/usr/bin/perl -w

use strict;
use Time::Local;

##############################################################################
#
# date and time routines
#
##############################################################################

sub
fhemTzOffset($) {
    # see http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
    my $t = shift;
    my @l = localtime($t);
    my @g = gmtime($t);

    # the offset is positive if the local timezone is ahead of GMT, e.g. we get 2*3600 seconds for CET DST vs GMT
    return 60*(($l[2] - $g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1] - $g[1]);
}

sub
fhemTimeGm($$$$$$) {
    # see http://de.wikipedia.org/wiki/Unixzeit
    my ($sec,$min,$hour,$mday,$month,$year) = @_;

    # $mday= 1..
    # $month= 0..11
    # $year is year-1900= 70..138
    
    $year+= 1900;
    my $isleapyear= $year % 4 ? 0 : $year % 100 ? 1 : $year % 400 ? 0 : 1;
    my $leapyears= int(($year-1969)/4) - int(($year-1901)/100) + int(($year-1601)/400);
    #printf("%02d.%02d.%04d %02d:%02d:%02d %d leap years, is leap year: %d\n", $mday,$month+1,$year,$hour,$min,$sec,$leapyears,$isleapyear);
    if ( $^O eq 'MacOS' ) {
      $year-= 1904;
    } else {
      $year-= 1970; # the Unix Epoch
    }

    my @d= (0,31,59,90,120,151,181,212,243,273,304,334); # no leap day
    # add one day in leap years if month is later than February
    $mday++ if($month>1 && $isleapyear);
    return $sec+60*($min+60*($hour+24*($d[$month]+$mday-1+365*$year+$leapyears)));
}

sub
fhemTimeLocal($$$$$$) {
    my $t= fhemTimeGm($_[0],$_[1],$_[2],$_[3],$_[4],$_[5]);
    return $t-fhemTzOffset($t);
}


##############################################################################

my ($y, $m, $d, $t1, $t2);

for($y= 70; $y< 115; $y++) {
  for($m= 0; $m< 12; $m++) {
    for($d= 1; $d< 29; $d++) {
      $t1= timelocal(0,0,0,$d,$m,$y);
      $t2= fhemTimeLocal(0,0,0,$d,$m,$y);
      if($t1 ne $t2) {
	printf("%02d.%02d.%04d %d %d %d\n", $d, $m+1, $y+1900, $t1, $t2, $t2-$t1);      
      } 
    }
  }
}



