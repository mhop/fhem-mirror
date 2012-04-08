##############################################
# - Use 99_SUNRISE_EL.pm instead of this module
# - Be aware: Installing the DateTime modules might be tedious, one way is:
#   perl -MCPAN -e shell
#   cpan> install DateTime::Event::Sunrise
# - Please call sunrise_coord before using this module, else you'll get times
#   for frankfurt am main (germany). See the "at" entry in commandref.html

package main;
use strict;
use warnings;

use DateTime;
use DateTime::Event::Sunrise;

sub sr($$$$);
sub sunrise_rel(@);
sub sunset_rel(@);
sub sunrise_abs(@);
sub sunset_abs(@);
sub isday();
sub sunrise_coord($$$);
sub SUNRISE_Initialize($);

# See perldoc DateTime::Event::Sunrise for details
my $long = "8.686";
my $lat  = "50.112";
my $tz   = "Europe/Berlin";

sub
SUNRISE_Initialize($)
{
  my ($hash) = @_;
}


##########################
# Compute:
# rise:  1: event is sunrise (else sunset)
# isrel: 1: _relative_ times until the next event (else absolute for today)
# seconds: second offset to event
# daycheck: if set, then return 1 if the sun is visible, 0 else
sub
sr($$$$)
{
  my ($rise, $seconds, $isrel, $daycheck) = @_;

  my $sunrise = DateTime::Event::Sunrise ->new(
		      longitude => $long,
		      latitude => $lat,
		      altitude => '-6',       # Civil twilight
		      iteration => '3');
  my $now = DateTime->now(time_zone => $tz);
  my $stm  = ($rise ? $sunrise->sunrise_datetime( $now ) : 
                      $sunrise->sunset_datetime( $now ));

  if($daycheck) {
    return 0 if(DateTime->compare($now, $stm) < 0);
    $stm  = $sunrise->sunset_datetime( $now );
    return 0 if(DateTime->compare($now, $stm) > 0);
    return 1;
  }

  if(!$isrel) {
    $stm = $stm->add(seconds => $seconds) if($seconds);
    return $stm->hms();
  }

  $stm = $stm->add(seconds => $seconds) if($seconds);

  if(DateTime->compare($now, $stm) >= 0) {
    my $tom = DateTime->now(time_zone => $tz)->add(days => 1);
    $stm  = ($rise ? $sunrise->sunrise_datetime( $tom ) : 
                      $sunrise->sunset_datetime( $tom ));
    $stm = $stm->add(seconds => $seconds) if($seconds);
  }

  my $diff = $stm->epoch - $now->epoch;
  return sprintf("%02d:%02d:%02d", $diff/3600, ($diff/60)%60, $diff%60);
}

sub sunrise_rel(@) { return sr(1, shift, 1, 0) }
sub sunset_rel(@)  { return sr(0, shift, 1, 0) }
sub sunrise_abs(@) { return sr(1, shift, 0, 0) }
sub sunset_abs(@)  { return sr(0, shift, 0, 0) }
sub isday()        { return sr(1,     0, 0, 1) }
sub sunrise_coord($$$) { ($long, $lat, $tz) = @_; return undef; }

1;
