##############################################
# This code is derived from DateTime::Event::Sunrise, version 0.0501.
# Simplified and removed further package # dependency (DateTime,
# Params::Validate, etc). For comments see the original code.
#

package main;
use strict;
use warnings;
use Math::Trig;

sub sr($$$$$$);
sub sunrise_rel(@);
sub sunset_rel(@);
sub sunrise_abs(@);
sub sunset_abs(@);
sub isday();
sub sunrise_coord($$$);

sub SUNRISE_Initialize($);

# See perldoc DateTime::Event::Sunrise for details
my $long   = "8.686";
my $lat    = "50.112";
my $tz     = ""; # will be overwritten
my $altit  = "-6";        # Civil twilight
my $RADEG  = ( 180 / 3.1415926 );
my $DEGRAD = ( 3.1415926 / 180 );
my $INV360 = ( 1.0 / 360.0 );


sub
SUNRISE_EL_Initialize($)
{
  my ($hash) = @_;
}


##########################
# Compute the _next_ event
# rise:  1: event is sunrise (else sunset)
# isrel: 1: relative times
# seconds: second offset to event
# daycheck: if set, then return 1 if the sun is visible, 0 else
sub
sr($$$$$$)
{
  my ($rise, $seconds, $isrel, $daycheck, $min, $max) = @_;
  my $needrise = ($rise || $daycheck) ? 1 : 0;
  my $needset = (!$rise || $daycheck) ? 1 : 0;
  $seconds = 0 if(!$seconds);

  my $nt = time;
  my @lt = localtime($nt);
  my $gmtoff = _calctz($nt,@lt); # in hour

  my ($rt,$st) = _sr($needrise,$needset, $lt[5]+1900,$lt[4]+1,$lt[3], $gmtoff);
  my $sst = ($rise ? $rt : $st) + ($seconds/3600);

  my $nh = $lt[2] + $lt[1]/60 + $lt[0]/3600;    # Current hour since midnight
  if($daycheck) {
    return 0 if($nh < $rt || $nh > $st);
    return 1;
  }

  my $diff = 0;
  if($data{AT_RECOMPUTE} ||                     # compute it for tommorow
     int(($nh-$sst)*3600) >= 0) {               # if called a subsec earlier
    $nt += 86400;
    $diff = 24;
    @lt = localtime($nt);
    $gmtoff = _calctz($nt,@lt); # in hour

    ($rt,$st) = _sr($needrise,$needset, $lt[5]+1900,$lt[4]+1,$lt[3], $gmtoff);
    $sst = ($rise ? $rt : $st) + ($seconds/3600);
  }

  $sst = hms2h($min) if(defined($min) && (hms2h($min) > $sst));
  $sst = hms2h($max) if(defined($max) && (hms2h($max) < $sst));

  $sst += $diff if($isrel);
  $sst -= $nh if($isrel == 1);

  return h2hms_fmt($sst);
}


sub
_sr($$$$$$)
{
  my ($needrise, $needset, $y, $m, $dy, $offset) = @_;

  my $d = _days_since_2000_Jan_0($y,$m,$dy) + 0.5 - $long / 360.0;
  my ( $tmp_rise_1, $tmp_set_1 ) =
    _sunrise_sunset( $d, $long, $lat, $altit, 15.04107 );

  my ($tmp_rise_2, $tmp_rise_3) = (0,0);

  if($needrise) {
    $tmp_rise_2 = 9; $tmp_rise_3 = 0;
    until ( _equal( $tmp_rise_2, $tmp_rise_3, 8 ) ) {

        my $d_sunrise_1 = $d + $tmp_rise_1 / 24.0;
        ( $tmp_rise_2, undef ) =
          _sunrise_sunset( $d_sunrise_1, $long, $lat, $altit, 15.04107 );
        $tmp_rise_1 = $tmp_rise_3;
        my $d_sunrise_2 = $d + $tmp_rise_2 / 24.0;
        ( $tmp_rise_3, undef ) =
          _sunrise_sunset( $d_sunrise_2, $long, $lat, $altit, 15.04107 );
    }
  }

  my ($tmp_set_2, $tmp_set_3) = (0,0);
  if($needset) {
    $tmp_set_2 = 9; $tmp_set_3 = 0;
    until ( _equal( $tmp_set_2, $tmp_set_3, 8 ) ) {

        my $d_sunset_1 = $d + $tmp_set_1 / 24.0;
        ( undef, $tmp_set_2 ) =
          _sunrise_sunset( $d_sunset_1, $long, $lat, $altit, 15.04107 );
        $tmp_set_1 = $tmp_set_3;
        my $d_sunset_2 = $d + $tmp_set_2 / 24.0;
        ( undef, $tmp_set_3 ) =
          _sunrise_sunset( $d_sunset_2, $long, $lat, $altit, 15.04107 );

    }
  }

  return $tmp_rise_3+$offset, $tmp_set_3+$offset;
}



sub
_sunrise_sunset($$$$$)
{
  my ( $d, $lon, $lat, $altit, $h ) = @_;

  my $sidtime = _revolution( _GMST0($d) + 180.0 + $lon );

  # Compute Sun's RA + Decl + distance at this moment
  my ( $sRA, $sdec, $sr ) = _sun_RA_dec($d);

  # Compute time when Sun is at south - in hours UT
  my $tsouth  = 12.0 - _rev180( $sidtime - $sRA ) / $h;

  # Compute the Sun's apparent radius, degrees
  my $sradius = 0.2666 / $sr;

  # Do correction to upper limb, if necessary
  $altit -= $sradius;

  # Compute the diurnal arc that the Sun traverses to reach 
  # the specified altitude altit: 
  my $cost =
    ( sind($altit) - sind($lat) * sind($sdec) ) /
    ( cosd($lat) * cosd($sdec) );

  my $t;
  if ( $cost >= 1.0 ) {
      $t = 0.0;    # Sun always below altit
  }
  elsif ( $cost <= -1.0 ) {
      $t = 12.0;    # Sun always above altit
  }
  else {
      $t = acosd($cost) / 15.0;    # The diurnal arc, hours
  }

  # Store rise and set times - in hours UT 

  my $hour_rise_ut = $tsouth - $t;
  my $hour_set_ut  = $tsouth + $t;
  return ( $hour_rise_ut, $hour_set_ut );

}

sub
_GMST0($)
{
  my ($d) = @_;

  my $sidtim0 =
    _revolution( ( 180.0 + 356.0470 + 282.9404 ) +
    ( 0.9856002585 + 4.70935E-5 ) * $d );
  return $sidtim0;

}

sub
_sunpos($)
{
  my ($d) = @_;

  my $Mean_anomaly_of_sun = _revolution( 356.0470 + 0.9856002585 * $d );
  my $Mean_longitude_of_perihelion = 282.9404 + 4.70935E-5 * $d;
  my $Eccentricity_of_Earth_orbit  = 0.016709 - 1.151E-9 * $d;

  # Compute true longitude and radius vector 
  my $Eccentric_anomaly =
    $Mean_anomaly_of_sun + $Eccentricity_of_Earth_orbit * $RADEG *
    sind($Mean_anomaly_of_sun) *
    ( 1.0 + $Eccentricity_of_Earth_orbit * cosd($Mean_anomaly_of_sun) );

  my $x = cosd($Eccentric_anomaly) - $Eccentricity_of_Earth_orbit;

  my $y =
    sqrt( 1.0 - $Eccentricity_of_Earth_orbit * $Eccentricity_of_Earth_orbit )
    * sind($Eccentric_anomaly);

  my $Solar_distance = sqrt( $x * $x + $y * $y );    # Solar distance
  my $True_anomaly = atan2d( $y, $x );               # True anomaly

  my $True_solar_longitude =
    $True_anomaly + $Mean_longitude_of_perihelion;    # True solar longitude

  if ( $True_solar_longitude >= 360.0 ) {
      $True_solar_longitude -= 360.0;    # Make it 0..360 degrees
  }

  return ( $Solar_distance, $True_solar_longitude );
}


# Sun's Right Ascension (RA), Declination (dec) and distance (r)
sub
_sun_RA_dec($)
{
  my ($d) = @_;

  my ( $r, $lon ) = _sunpos($d);

  my $x = $r * cosd($lon);
  my $y = $r * sind($lon);

  my $obl_ecl = 23.4393 - 3.563E-7 * $d;

  my $z = $y * sind($obl_ecl);
  $y = $y * cosd($obl_ecl);

  my $RA  = atan2d( $y, $x );
  my $dec = atan2d( $z, sqrt( $x * $x + $y * $y ) );

  return ( $RA, $dec, $r );
}

sub
_days_since_2000_Jan_0($$$)
{
  my ($y, $m, $d) = @_;
  my @mn = (31,28,31,30,31,30,31,31,30,31,30,31);
  
  my $ms = 0;
  for(my $i = 0; $i < $m-1; $i++) {
    $ms += $mn[$i];
  }
  my $x = ($y-2000)*365.25 + $ms + $d;
  $x++ if($m > 2 && ($y%4) == 0);
  return int($x);
}

sub sind($) { sin( ( $_[0] ) * $DEGRAD ); }
sub cosd($) { cos( ( $_[0] ) * $DEGRAD ); }
sub tand($) { tan( ( $_[0] ) * $DEGRAD ); }
sub atand($) { ( $RADEG * atan( $_[0] ) ); }
sub asind($) { ( $RADEG * asin( $_[0] ) ); }
sub acosd($) { ( $RADEG * acos( $_[0] ) ); }
sub atan2d($$) { ( $RADEG * atan2( $_[0], $_[1] ) ); }

sub
_revolution($)
{
  my $x = $_[0];
  return ( $x - 360.0 * int( $x * $INV360 ) );
}

sub
_rev180($)
{
  my ($x) = @_;
  return ( $x - 360.0 * int( $x * $INV360 + 0.5 ) );
}

sub
_equal($$$)
{
  my ( $A, $B, $dp ) = @_;
  return sprintf( "%.${dp}g", $A ) eq sprintf( "%.${dp}g", $B );
}

sub
_calctz($@)
{
  my ($nt,@lt) = @_;

  my $off = $lt[2]*3600+$lt[1]*60+$lt[0];
  $off = 12*3600-$off;
  $nt += $off;  # This is noon, localtime

  my @gt = gmtime($nt);

  return (12-$gt[2]);
}
  

sub
hms2h($)
{
  my $in = shift;
  my @a = split(":", $in);
  return 0 if(int(@a) < 2 || $in !~ m/^[\d:]*$/);
  return $a[0]+$a[1]/60 + ($a[2] ? $a[2]/3600 : 0);
}

sub
h2hms($)
{
  my ($in) = @_;
  my ($h,$m,$s);
  $h = int($in);
  $m = int(60*($in-$h));
  $s = int(3600*($in-$h)-60*$m);
  return ($h, $m, $s);
}

sub
h2hms_fmt($)
{
  my ($in) = @_;
  my ($h,$m,$s) = h2hms($in);
  return sprintf("%02d:%02d:%02d", $h, $m, $s);
}


sub sunrise_rel(@) { return sr(1, shift, 1, 0, shift, shift) }
sub sunset_rel(@)  { return sr(0, shift, 1, 0, shift, shift) }
sub sunrise_abs(@) { return sr(1, shift, 0, 0, shift, shift) }
sub sunset_abs(@)  { return sr(0, shift, 0, 0, shift, shift) }
sub sunrise(@)     { return sr(1, shift, 2, 0, shift, shift) }
sub sunset(@)      { return sr(0, shift, 2, 0, shift, shift) }
sub isday()        { return sr(1,     0, 0, 1, undef, undef) }
sub sunrise_coord($$$) { ($long, $lat, $tz) = @_; return undef; }

1;
