#2017.07.31 08:04:33 1: PERL WARNING: Use of uninitialized value $Astro{"MoonPhaseS"} in sprintf at /opt/fhem/FHEM/95_Astro.pm line 1302.
########################################################################################
#
# 95_Astro.pm
#
# Collection of various routines for astronomical data
# Prof. Dr. Peter A. Henning
#
# Equations from "Practical Astronomy with your Calculator" by Peter Duffett-Smith
# Program skeleton (with some errors) by Arnold Barmettler 
# http://lexikon.astronomie.info/java/sunmoon/
#
#  $Id$
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################

package main;
use strict;
use warnings; 
use POSIX;

use Math::Trig;
use Time::Local;
#use Data::Dumper;

my $DEG = pi/180.0;
my $RAD = 180./pi;

my $deltaT   = 65;  # Correction time in s

my %Astro;
my %Date;

my $astroversion = 1.33;

#-- These we may get on request
my %gets = (
   "version" => "V",
   "json"  => "J",
   "text"  => "T"
);

my $astro_tt;

my %astro_transtable_EN = ( 
    "overview"          =>  "Summary",
    "name"              =>  "Name", 
    "time"              =>  "Time",
    "action"            =>  "Action",
    "type"              =>  "Type",
    "description"       =>  "Description",
    "profile"           =>  "Profile",
    #--
    "coord"             =>  "Coordinates",
    "position"          =>  "Position",
    "longitude"         =>  "Longitude",
    "latitude"          =>  "Latitude",
    "altitude"          =>  "Height above sea",
    "lonecl"            =>  "Ecliptical longitude",
    "latecl"            =>  "Ecliptical latitude",
    "ra"                =>  "Right ascension",        
    "dec"               =>  "Declination",
    "az"                =>  "Azimuth",
    "alt"               =>  "Horizontal altitude",
    "age"               =>  "Age",
    "rise"              =>  "Rise",
    "set"               =>  "Set",
    "transit"           =>  "Transit",
    "distance"          =>  "Distance",
    "diameter"          =>  "Diameter",
    "toobs"             =>  "to observer",
    "toce"              =>  "to Earth center",
    "twilightcivil"     =>  "Civil twilight",
    "twilightnautic"    =>  "Nautical twilight",
    "twilightastro"     =>  "Astronomical twilight",
    "twilightcustom"    =>  "Custom twilight",
    "sign"              =>  "Zodiac sign",
    #--
    "today"             =>  "Today",
    "tomorrow"          =>  "Tomorrow",
    "weekday"           =>  "Day of Week",
    "date"              =>  "Date",
    "jdate"             =>  "Julian date",
    "dayofyear"         =>  "day of year",
    "days"              =>  "days",
    "timezone"          =>  "Time Zone",
    "lmst"              =>  "Local Sidereal Time",  
    #--
    "monday"    =>  ["Monday","Mon"],
    "tuesday"   =>  ["Tuesday","Tue"],
    "wednesday" =>  ["Wednesday","Wed"],
    "thursday"  =>  ["Thursday","Thu"],
    "friday"    =>  ["Friday","Fri"],
    "saturday"  =>  ["Saturday","Sat"],
    "sunday"    =>  ["Sunday","Sun"],
    #--
    "season"    => "Season",
    "spring"    => "Spring",
    "summer"    => "Summer",
    "fall"      => "Fall",
    "winter"    => "Winter",
        #--
    "aries"     => "Ram",
    "taurus"    => "Bull",
    "gemini"    => "Twins",
    "cancer"    => "Crab",
    "leo"       => "Lion",
    "virgo"     => "Maiden",
    "libra"     => "Scales",
    "scorpio"   => "Scorpion",
    "Sagittarius" => "Archer",
    "capricorn" => "Goat",
    "aquarius"  => "Water Bearer",
    "pisces"    => "Fish",
    #--
    "sun"         => "Sun",
    #--
    "moon"           => "Moon",
    "phase"          => "Phase",
    "newmoon"        => "New Moon",
    "waxingcrescent" => "Waxing Crescent",
    "firstquarter   "=> "First Quarter",
    "waxingmoon"     => "Waxing Moon",
    "fullmoon"       => "Full Moon",
    "waningmoon"     => "Waning Moon",
    "lastquarter"    => "Last Quarter",
    "waningcrescent" => "Waning Crescent"
    );
    
 my %astro_transtable_DE = ( 
    "overview"          =>  "Zusammenfassung",
    "name"              =>  "Name", 
    "time"              =>  "Zeit",
    "action"            =>  "Aktion",
    "type"              =>  "Typ",
    "description"       =>  "Beschreibung",
    "profile"           =>  "Profil",
    #--
    "coord"             =>  "Koordinaten",
    "position"          =>  "Position",
    "longitude"         =>  "Länge",
    "latitude"          =>  "Breite",
    "altitude"          =>  "Höhe ü.M.",
    "lonecl"            =>  "Eklipt. Länge",
    "latecl"            =>  "Eklipt. Breite",
    "ra"                =>  "Rektaszension",        
    "dec"               =>  "Deklination",
    "az"                =>  "Azimut",
    "alt"               =>  "Horizontwinkel",
    "age"               =>  "Alter",
    "phase"             =>  "Phase",
    "rise"              =>  "Aufgang",
    "set"               =>  "Untergang",
    "transit"           =>  "Kulmination",
    "distance"          =>  "Entfernung",
    "diameter"          =>  "Durchmesser",
    "toobs"             =>  "z. Beobachter",
    "toce"              =>  "z. Erdmittelpunkt",
    "twilightcivil"     =>  "Bürgerliche Dämmerung",
    "twilightnautic"    =>  "Nautische Dämmerung",
    "twilightastro"     =>  "Astronomische Dämmerung",
    "twilightcustom"    =>  "Konfigurierte Dämmerung",
    "sign"              =>  "Tierkreiszeichen",
    #--
    "today"             =>  "Heute",
    "tomorrow"          =>  "Morgen",
    "weekday"           =>  "Wochentag",
    "date"              =>  "Datum",
    "jdate"             =>  "Julianisches Datum",
    "dayofyear"         =>  "Tag d. Jahres",
    "days"              =>  "Tage",
    "timezone"          =>  "Zeitzone",
    "lmst"              =>  "Lokale Sternzeit",  
    #--
    "monday"    =>  ["Montag","Mo"],
    "tuesday"   =>  ["Dienstag","Di"],
    "wednesday" =>  ["Mittwoch","Mi"],
    "thursday"  =>  ["Donnerstag","Do"],
    "friday"    =>  ["Freitag","Fr"],
    "saturday"  =>  ["Samstag","Sa"],
    "sunday"    =>  ["Sonntag","So"],
    #--
    "season"    => "Jahreszeit",
    "spring"    => "Frühling",
    "summer"    => "Sommer",
    "fall"      => "Herbst",
    "winter"    => "Winter",
    #--
    "aries"     => "Widder",
    "taurus"    => "Stier",
    "gemini"    => "Zwillinge",
    "cancer"    => "Krebs",
    "leo"       => "Löwe",
    "virgo"     => "Jungfrau",
    "libra"     => "Waage",
    "scorpio"   => "Skorpion",
    "Sagittarius" => "Schütze",
    "capricorn" => "Steinbock",
    "aquarius"  => "Wassermann",
    "pisces"    => "Fische",
    #--
    "sun"         => "Sonne",
    #--
    "moon"           => "Mond",
    "phase"          => "Phase",
    "newmoon"        => "Neumond",
    "waxingcrescent" => "Zunehmende Sichel",
    "firstquarter   "=> "Erstes Viertel",
    "waxingmoon"     => "Zunehmender Mond",
    "fullmoon"       => "Vollmond",
    "waningmoon"     => "Abnehmender Mond",
    "lastquarter"    => "Letztes Viertel",
    "waningcrescent" => "Abnehmende Sichel"
    );
 
my @zodiac=("aries","taurus","gemini","cancer","leo","virgo",
    "libra","scorpio","sagittarius","capricorn","aquarius","pisces");

my @phases = ("newmoon","waxingcrescent", "firstquarter", "waxingmoon", 
    "fullmoon", "waningmoon", "lastquarter", "waningcrescent");

my @seasons = (
    "winter","spring","summer","fall");
    
my %seasonn = (
    "spring" => [80,172],       #21./22.3. - 20.6.
    "summer" => [173,265],      #21.06. bis 21./22.09.
    "fall"   => [266,353],      #22./23.09. bis 20./21.12.
    "winter" => [354,79]        
    );
   
sub Astro_SunRise($$$$$$);
sub Astro_MoonRise($$$$$$$);
 
########################################################################################################
#
# Astro_Initialize 
# 
# Parameter hash = hash of device addressed 
#
########################################################################################################

sub Astro_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "Astro_Define";
  #$hash->{SetFn}   	   = "Astro_Set";  
  $hash->{GetFn}       = "Astro_Get";
  $hash->{UndefFn}     = "Astro_Undef";   
  $hash->{AttrFn}      = "Astro_Attr";    
  $hash->{AttrList}    = "interval longitude latitude altitude horizon";			  
	
  return undef;
}

########################################################################################################
#
# Astro_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################################

sub Astro_Define ($$) {
 my ($hash, $def) = @_;
 #my $now = time();
 my $name = $hash->{NAME}; 
 $hash->{VERSION} = $astroversion;
 readingsSingleUpdate( $hash, "state", "Initialized", 1 ); 
 
 $modules{Astro}{defptr}{$name} = $hash;
  
 RemoveInternalTimer($hash);
 
 #-- Call us in n seconds again.
 InternalTimer(gettimeofday()+ 60, "Astro_Update", $hash,0);

 return undef;
}

########################################################################################################
#
# Astro_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################################

sub Astro_Undef ($$) {
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

########################################################################################################
#
# Astro_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
########################################################################################################

sub Astro_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $defs{$name};
  my $ret;
  
  if ( $do eq "set") {
    ARGUMENT_HANDLER: {
      #-- interval modified at runtime
      $key eq "interval" and do {
        #-- check value
        return "[Astro] set $name interval must be >= 0" if(int($value) < 0);
        #-- update timer
        $hash->{INTERVAL} = int($value);
        if ($init_done) {
          RemoveInternalTimer($hash);
          InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Astro_Update", $hash, 0);
        }
        last;
      };
    }
  }
  return $ret;
}

sub Astro_mod($$) { my ($a,$b)=@_;if( $a =~ /\d*\.\d*/){return($a-floor($a/$b)*$b)}else{return undef}; }
sub Astro_mod2Pi($) { my ($x)=@_;$x = Astro_mod($x, 2.*pi);return($x); }
sub Astro_round($$) { my ($x,$n)=@_; return int(10**$n*$x+0.5)/10**$n};

########################################################################################################
#
# time fragments into minutes, seconds
#
########################################################################################################  
  
sub Astro_HHMM($){
  my ($hh) = @_;
  return("")
    if (!defined($hh) || $hh !~ /\d*\.\d*/) ;
  
  my $h = floor($hh);
  my $m = ($hh-$h)*60.;
  return sprintf("%02d:%02d",$h,$m);
}

sub Astro_HHMMSS($){
  my ($hh) = @_;
  return("")
    if ($hh==0) ;
  
  my $m = ($hh-floor($hh))*60.;
  my $s = ($m-floor($m))*60;
  my $h = floor($hh);
  return sprintf("%02d:%02d:%02d",$h,$m,$s);
}

########################################################################################################
#
# Astro_CalcJD - Calculate Julian date: valid only from 1.3.1901 to 28.2.2100
#
########################################################################################################

sub Astro_CalcJD($$$) {
  my ($day,$month,$year) = @_;
  my $jd = 2415020.5-64; # 1.1.1900 - correction of algorithm
  if ($month<=2) { 
    $year--; 
    $month += 12; 
  }
  $jd += int( ($year-1900)*365.25 );
  $jd += int( 30.6001*(1+$month) );
  return($jd + $day);
}

########################################################################################################
#
# Astro_GMST - Julian Date to Greenwich Mean Sidereal Time
#
########################################################################################################

sub Astro_GMST($){
  my ($JD) = @_;
  my $UT   = ($JD-0.5) - int($JD-0.5);
  $UT      = $UT*24.;              # UT in hours
  $JD      = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  my $T    = ($JD-2451545.0)/36525.0;
  my $T0   = 6.697374558 + $T*(2400.051336 + $T*0.000025862);
  
  return( Astro_mod($T0+$UT*1.002737909,24.));
}

########################################################################################################
#
# Astro_GMST2UT - Convert Greenweek mean sidereal time to UT
#
########################################################################################################

sub Astro_GMST2UT($$){
  my ($JD, $gmst) = @_;
  $JD             = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  my $T           = ($JD-2451545.0)/36525.0;
  my $T0          = Astro_mod(6.697374558 + $T*(2400.051336 + $T*0.000025862), 24.);
  my $UT          = 0.9972695663*(($gmst-$T0));
  return($UT);
}

########################################################################################################
#
# Astro_GMST2LMST - Local Mean Sidereal Time, geographical longitude in radians, 
#                   East is positive
#
########################################################################################################

sub Astro_GMST2LMST($$){
  my ($gmst, $lon) = @_;
  my $lmst = Astro_mod($gmst+$RAD*$lon/15, 24.);
  return( $lmst );
}

########################################################################################################
#
# Astro_Ecl2Equ - Transform ecliptical coordinates (lon/lat) to equatorial coordinates (RA/dec)
#
########################################################################################################

sub Astro_Ecl2Equ($$$){
  my ($lon, $lat, $TDT) = @_;
  my $T = ($TDT-2451545.0)/36525.; # Epoch 2000 January 1.5
  my $eps = (23.+(26+21.45/60.)/60. + $T*(-46.815 +$T*(-0.0006 + $T*0.00181) )/3600. )*$DEG;
  my $coseps = cos($eps);
  my $sineps = sin($eps);
  my $sinlon = sin($lon);
  my $ra  = Astro_mod2Pi(atan2( ($sinlon*$coseps-tan($lat)*$sineps), cos($lon) ));  
  my $dec = asin( sin($lat)*$coseps + cos($lat)*$sineps*$sinlon );
 
  return ($ra,$dec);
}

########################################################################################################
#
# Astro_Equ2Altaz - Transform equatorial coordinates (RA/Dec) to horizonal coordinates 
#                   (azimuth/altitude). Refraction is ignored
#
########################################################################################################

sub Astro_Equ2Altaz($$$$$){
  my ($ra, $dec, $TDT, $lat, $lmst)=@_;
  my $cosdec = cos($dec);
  my $sindec = sin($dec);
  my $lha    = $lmst - $ra;
  my $coslha = cos($lha);
  my $sinlha = sin($lha);
  my $coslat = cos($lat);
  my $sinlat = sin($lat);
  
  my $N      = -$cosdec * $sinlha;
  my $D      = $sindec * $coslat - $cosdec * $coslha * $sinlat;
  my $az     = Astro_mod2Pi( atan2($N, $D) );
  my $alt    = asin( $sindec * $sinlat + $cosdec * $coslha * $coslat );

  return ($az,$alt);
}

########################################################################################################
#
# Astro_GeoEqu2TopoEqu - Transform geocentric equatorial coordinates (RA/Dec) to 
#                        topocentric equatorial coordinates
#
########################################################################################################

sub Astro_GeoEqu2TopoEqu($$$$$$$){
  my ($ra, $dec, $distance, $lon, $lat, $radius, $lmst) = @_;

  my $cosdec = cos($dec);
  my $sindec = sin($dec);
  my $coslst = cos($lmst);
  my $sinlst = sin($lmst);
  my $coslat = cos($lat); # we should use geocentric latitude, not geodetic latitude
  my $sinlat = sin($lat);
  my $rho    = $radius; # observer-geocenter in km
  
  my $x = $distance*$cosdec*cos($ra) - $rho*$coslat*$coslst;
  my $y = $distance*$cosdec*sin($ra) - $rho*$coslat*$sinlst;
  my $z = $distance*$sindec - $rho*$sinlat;

  my $distanceTopocentric = sqrt($x*$x + $y*$y + $z*$z);
  my $decTopocentric = asin($z/$distanceTopocentric);
  my $raTopocentric = Astro_mod2Pi( atan2($y, $x) );

  return ( ($distanceTopocentric,$decTopocentric,$raTopocentric) );
}

########################################################################################################
#
# Astro_EquPolar2Cart - Calculate cartesian from polar coordinates
#
########################################################################################################

sub Astro_EquPolar2Cart($$$){
  my ($lon,$lat,$distance) = @_;
  my $rcd = cos($lat)*$distance;
  my $x   = $rcd*cos($lon);
  my $y   = $rcd*sin($lon);
  my $z   = sin($lat)*$distance;
  return( ($x,$y,$z) );
}

########################################################################################################
#
# Astro_Observer2EquCart - Calculate observers cartesian equatorial coordinates (x,y,z in celestial frame) 
#                    from geodetic coordinates (longitude, latitude, height above WGS84 ellipsoid)
#                    Currently only used to calculate distance of a body from the observer
#
########################################################################################################

sub Astro_Observer2EquCart($$$$){
  my ($lon, $lat, $height, $gmst ) = @_;

  my $flat   = 298.257223563;        # WGS84 flatening of earth
  my $aearth = 6378.137;             # GRS80/WGS84 semi major axis of earth ellipsoid

  #-- Calculate geocentric latitude from geodetic latitude
  my $co = cos ($lat);
  my $si = sin ($lat);
  $si    = $si * $si;
  my $fl = 1.0 - 1.0 / $flat;
  $fl    = $fl * $fl;
  my $u  = 1.0 / sqrt ($co * $co + $fl * $si);
  my $a  = $aearth * $u + $height;
  my $b  = $aearth * $fl * $u + $height;
  my $radius = sqrt ($a * $a * $co *$co + $b *$b * $si); # geocentric distance from earth center
  my $y  = acos ($a * $co / $radius); # geocentric latitude, rad
  my $x  = $lon; # longitude stays the same
  my $z;
  if ($lat < 0.0) { $y = -$y; } # adjust sign
  
  #-- convert from geocentric polar to geocentric cartesian, with regard to Greenwich
  ($x,$y,$z) = Astro_EquPolar2Cart( $x, $y, $radius ); 
  
  #-- rotate around earth's polar axis to align coordinate system from Greenwich to vernal equinox
  my $rotangle = $gmst/24*2*pi; # sideral time gmst given in hours. Convert to radians
  my $x2 = $x*cos($rotangle) - $y*sin($rotangle);
  my $y2 = $x*sin($rotangle) + $y*cos($rotangle);
  
  return( ($x2,$y2,$z,$radius) );
}

########################################################################################################
#
# Astro_SunPosition - Calculate coordinates for Sun
# Coordinates are accurate to about 10s (right ascension) 
# and a few minutes of arc (declination)
# 
########################################################################################################

sub Astro_SunPosition($$$){
  my ($TDT, $observerlat, $lmst)=@_;
  
  my $D  = $TDT-2447891.5;
  my $eg = 279.403303*$DEG;
  my $wg = 282.768422*$DEG;
  my $e  = 0.016713;
  my $a  = 149598500; # km
  #-- mean angular diameter of sun
  my $diameter0 = 0.533128*$DEG; 
  
  my $MSun = 360*$DEG/365.242191*$D+$eg-$wg;
  my $nu   = $MSun + 360.*$DEG/pi*$e*sin($MSun);
  
  my %sunCoor;
  
  $sunCoor{lon}  =  Astro_mod2Pi($nu+$wg);
  $sunCoor{lat}  = 0;
  $sunCoor{anomalyMean} = $MSun;
  
  my $distance  = (1-$e*$e)/(1+$e*cos($nu));   # distance in astronomical units
  $sunCoor{diameter} = $diameter0/$distance;        # angular diameter
  $sunCoor{distance} = $distance*$a;                # distance in km
  $sunCoor{parallax} = 6378.137/$sunCoor{distance};          # horizonal parallax

  ($sunCoor{ra},$sunCoor{dec}) = Astro_Ecl2Equ($sunCoor{lon}, $sunCoor{lat}, $TDT);
  
  #-- calculate horizonal coordinates of sun, if geographic positions is given
  if (defined($observerlat) && defined($lmst) ) {
    ($sunCoor{az},$sunCoor{alt}) = Astro_Equ2Altaz($sunCoor{ra}, $sunCoor{dec}, $TDT, $observerlat, $lmst);
  }
  $sunCoor{sig} = $zodiac[floor($sunCoor{lon}*$RAD/30)];
  
  return ( \%sunCoor );
}

########################################################################################################
#
# Astro_MoonPosition - Calculate data and coordinates for the Moon
#                      Coordinates are accurate to about 1/5 degree (in ecliptic coordinates)
# 
########################################################################################################

sub Astro_MoonPosition($$$$$$$){
  my ($sunlon, $sunanomalyMean, $TDT, $observerlon, $observerlat, $observerradius, $lmst) = @_;
  
  my $D = $TDT-2447891.5;
  
  #-- Mean Moon orbit elements as of 1990.0
  my $l0 = 318.351648*$DEG;
  my $P0 =  36.340410*$DEG;
  my $N0 = 318.510107*$DEG;
  my $i  = 5.145396*$DEG;
  my $e  = 0.054900;
  my $a  = 384401; # km
  my $diameter0 = 0.5181*$DEG; # angular diameter of Moon at a distance
  my $parallax0 = 0.9507*$DEG; # parallax at distance a
  
  my $l  = 13.1763966*$DEG*$D+$l0;
  my $MMoon = $l-0.1114041*$DEG*$D-$P0; # Moon's mean anomaly M
  my $N  = $N0-0.0529539*$DEG*$D;          # Moon's mean ascending node longitude
  my $C  = $l-$sunlon;
  my $Ev = 1.2739*$DEG*sin(2*$C-$MMoon);
  my $Ae = 0.1858*$DEG*sin($sunanomalyMean);
  my $A3 = 0.37*$DEG*sin($sunanomalyMean);
  my $MMoon2 = $MMoon+$Ev-$Ae-$A3;  # corrected Moon anomaly
  my $Ec = 6.2886*$DEG*sin($MMoon2);  # equation of centre
  my $A4 = 0.214*$DEG*sin(2*$MMoon2);
  my $l2 = $l+$Ev+$Ec-$Ae+$A4; # corrected Moon's longitude
  my $V  = 0.6583*$DEG*sin(2*($l2-$sunlon));
  my $l3 = $l2+$V; # true orbital longitude;

  my $N2 = $N-0.16*$DEG*sin($sunanomalyMean);
   
  my %moonCoor;
  $moonCoor{lon}      = Astro_mod2Pi( $N2 + atan2( sin($l3-$N2)*cos($i), cos($l3-$N2) ) );
  $moonCoor{lat}      = asin( sin($l3-$N2)*sin($i) );
  $moonCoor{orbitLon} = $l3;
  
  ($moonCoor{ra},$moonCoor{dec}) = Astro_Ecl2Equ($moonCoor{lon},$moonCoor{lat},$TDT);
  #-- relative distance to semi mayor axis of lunar oribt
  my $distance = (1-$e*$e) / (1+$e*cos($MMoon2+$Ec) );
  $moonCoor{diameter} = $diameter0/$distance; # angular diameter in radians
  $moonCoor{parallax} = $parallax0/$distance; # horizontal parallax in radians
  $moonCoor{distance} = $distance*$a;         # distance in km

  #-- Calculate horizonal coordinates of moon, if geographic positions is given

  #-- backup geocentric coordinates
  $moonCoor{raGeocentric}       = $moonCoor{ra}; 
  $moonCoor{decGeocentric}      = $moonCoor{dec};
  $moonCoor{distanceGeocentric} = $moonCoor{distance};

  if (defined($observerlat) && defined($observerlon) && defined($lmst) ) {
    #-- transform geocentric coordinates into topocentric (==observer based) coordinates
	my  ($distanceTopocentric,$decTopocentric,$raTopocentric) = 
	  Astro_GeoEqu2TopoEqu($moonCoor{ra}, $moonCoor{dec}, $moonCoor{distance}, $observerlon, $observerlat, $observerradius, $lmst);
	#-- now ra and dec are topocentric
	$moonCoor{ra}  = $raTopocentric;
	$moonCoor{dec} = $decTopocentric;
    ($moonCoor{az},$moonCoor{alt})= Astro_Equ2Altaz($moonCoor{ra}, $moonCoor{dec}, $TDT, $observerlat, $lmst); 
  }
  
  #-- Age of Moon in radians since New Moon (0) - Full Moon (pi)
  $moonCoor{age}    = Astro_mod2Pi($l3-$sunlon);   
  $moonCoor{phasen} = 0.5*(1-cos($moonCoor{age})); # Moon phase numerical, 0-1
  
  my $mainPhase = 1./29.53*360*$DEG; # show 'Newmoon, 'Quarter' for +/-1 day around the actual event
  my $p = Astro_mod($moonCoor{age}, 90.*$DEG);
  if ($p < $mainPhase || $p > 90*$DEG-$mainPhase){
    $p = 2*floor($moonCoor{age} / (90.*$DEG)+0.5);
  }else{
    $p = 2*floor($moonCoor{age} / (90.*$DEG))+1;
  }
  $p = $p % 8;
  $moonCoor{phases} = $phases[$p]; 
  $moonCoor{phasei} = $p;
  $moonCoor{sig}    = $zodiac[floor($moonCoor{lon}*$RAD/30)];

  return ( \%moonCoor );
}

########################################################################################################
#
# Astro_Refraction - Input true altitude in radians, Output: increase in altitude in degrees
# 
########################################################################################################

sub Astro_Refraction($){
  my ($alt) = @_;
  my $altdeg = $alt*$RAD;
  if ($altdeg<-2 || $altdeg>=90){
    return(0);
  }
   
  my $pressure    = 1015;
  my $temperature = 10;
  if ($altdeg>15){
    return( 0.00452*$pressure/( (273+$temperature)*tan($alt)) );
  }
  
  my $y = $alt;
  my $D = 0.0;
  my $P = ($pressure-80.)/930.;
  my $Q = 0.0048*($temperature-10.);
  my $y0 = $y;
  my $D0 = $D;
  my $N;

  for (my $i=0; $i<3; $i++) {
	$N = $y+(7.31/($y+4.4));
    $N = 1./tan($N*$DEG);
	$D = $N*$P/(60.+$Q*($N+39.));
	$N = $y-$y0;
	$y0 = $D-$D0-$N;
	if (($N != 0.) && ($y0 != 0.)) { 
	  $N = $y-$N*($alt+$D-$y)/$y0; 
	} else { 
	  $N = $alt+$D; 
	}
	$y0 = $y;
	$D0 = $D;
	$y  = $N;
  }
  return( $D ); 
}

########################################################################################################
#
# Astro_GMSTRiseSet - returns Greenwich sidereal time (hours) of time of rise 
# and set of object with coordinates ra/dec
# at geographic position lon/lat (all values in radians)
# Correction for refraction and semi-diameter/parallax of body is taken care of in function RiseSet
# h is used to calculate the twilights. It gives the required elevation of the disk center of the sun
# 
########################################################################################################

sub Astro_GMSTRiseSet($$$$$){
  my ($ra, $dec, $lon, $lat, $h) = @_;
  
  $h = (defined($h)) ? $h : 0.0; # set default value
  #Log 1,"-------------------> Called Astro_GMSTRiseSet with $ra $dec $lon $lat $h";

  # my $tagbogen = acos(-tan(lat)*tan(coor.dec)); // simple formula if twilight is not required
  my $tagbogen = acos((sin($h) - sin($lat)*sin($dec)) / (cos($lat)*cos($dec)));

  my $transit =     $RAD/15*(          +$ra-$lon);
  my $rise    = 24.+$RAD/15*(-$tagbogen+$ra-$lon); # calculate GMST of rise of object
  my $set     =     $RAD/15*(+$tagbogen+$ra-$lon); # calculate GMST of set of object

  #--Using the modulo function Astro_mod, the day number goes missing. This may get a problem for the moon
  $transit = Astro_mod($transit, 24);
  $rise    = Astro_mod($rise, 24);
  $set     = Astro_mod($set, 24);
  
  return( ($transit, $rise, $set) );
}

########################################################################################################
#
# Astro_InterpolateGMST - Find GMST of rise/set of object from the two calculated 
# (start)points (day 1 and 2) and at midnight UT(0)
# 
########################################################################################################

sub Astro_InterpolateGMST($$$$){
  my ($gmst0, $gmst1, $gmst2, $timefactor) = @_;
  return( ($timefactor*24.07*$gmst1- $gmst0*($gmst2-$gmst1)) / ($timefactor*24.07+$gmst1-$gmst2) );
}

########################################################################################################
#
# Astro_RiseSet
#    // JD is the Julian Date of 0h UTC time (midnight)
# 
########################################################################################################

sub Astro_RiseSet($$$$$$$$$$$){
  my ($jd0UT, $diameter, $parallax, $ra1, $dec1, $ra2, $dec2, $lon, $lat, $timeinterval, $altip) = @_;
 
  #--altitude of sun center: semi-diameter, horizontal parallax and (standard) refraction of 34'
  #  true height of sun center for sunrise and set calculation. Is kept 0 for twilight (ie. altitude given):
  my $alt      = (!defined($altip)) ? 0.5*$diameter-$parallax+34./60*$DEG : 0.; 
  my $altitude = (!defined($altip)) ? 0. : $altip; 

  my ($transit1, $rise1, $set1) = Astro_GMSTRiseSet($ra1, $dec1, $lon, $lat, $altitude);
  my ($transit2, $rise2, $set2) = Astro_GMSTRiseSet($ra2, $dec2, $lon, $lat, $altitude);
  
  #-- unwrap GMST in case we move across 24h -> 0h
  $transit2 += 24
    if ($transit1 > $transit2 && abs($transit1-$transit2)>18);
  $rise2 += 24
    if ($rise1 > $rise2    && abs($rise1-$rise2)>18);
  $set2 += 24
    if ($set1 > $set2    && abs($set1-$set2)>18);
    
  my $T0 = Astro_GMST($jd0UT);
  # my $T02 = T0-zone*1.002738; // Greenwich sidereal time at 0h time zone (zone: hours)
  #-- Greenwich sidereal time for 0h at selected longitude
  my $T02 = $T0-$lon*$RAD/15*1.002738;
  $T02 +=24 if ($T02 < 0);

  if ($transit1 < $T02) { 
    $transit1 += 24; 
    $transit2 += 24; 
  }
  if ($rise1    < $T02) { 
    $rise1    += 24; 
    $rise2    += 24; 
  }
  if ($set1     < $T02) { 
    $set1     += 24; 
    $set2     += 24; 
  }
  
  #-- Refraction and Parallax correction
  my $decMean = 0.5*($dec1+$dec2);
  my $psi = acos(sin($lat)/cos($decMean));
  my $y   = asin(sin($alt)/sin($psi));
  my $dt  = 240*$RAD*$y/cos($decMean)/3600; # time correction due to refraction, parallax

  my $transit = Astro_GMST2UT( $jd0UT, Astro_InterpolateGMST( $T0, $transit1, $transit2, $timeinterval) );
  my $rise    = Astro_GMST2UT( $jd0UT, Astro_InterpolateGMST( $T0, $rise1,    $rise2,    $timeinterval) - $dt );
  my $set     = Astro_GMST2UT( $jd0UT, Astro_InterpolateGMST( $T0, $set1,     $set2,     $timeinterval) + $dt );
  
  return( ($transit,$rise,$set) ); 
}

########################################################################################################
#
# Astro_SunRise - Find (local) time of sunrise and sunset, and twilights
#                 JD is the Julian Date of 0h local time (midnight)
#                 Accurate to about 1-2 minutes
#                 recursive: 1 - calculate rise/set in UTC in a second run
#                 recursive: 0 - find rise/set on the current local day. 
#                                This is set when doing the first call to this function
# 
########################################################################################################

sub Astro_SunRise($$$$$$){
  my ($JD, $deltaT, $lon, $lat, $zone, $recursive) = @_;
  
  my $jd0UT = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  
  #-- calculations for noon
  my $sunCoor1 = Astro_SunPosition($jd0UT+   $deltaT/24./3600.,undef,undef);

  #-- calculations for next day's UTC midnight
  my $sunCoor2 = Astro_SunPosition($jd0UT+1.+$deltaT/24./3600.,undef,undef); 
  
  #-- rise/set time in UTC
  my ($transit,$rise,$set) = Astro_RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
    $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1,undef); 
  
  my ($transittemp,$risetemp,$settemp);
  #-- check and adjust to have rise/set time on local calendar day
  if ( $recursive==0 ) { 
    if ($zone>0) {
      #rise time was yesterday local time -> calculate rise time for next UTC day
      if ($rise >=24-$zone || $transit>=24-$zone || $set>=24-$zone) {
        ($transittemp,$risetemp,$settemp) = Astro_SunRise($JD+1, $deltaT, $lon, $lat, $zone, 1);
        $transit = $transittemp
          if ($transit>=24-$zone);
        $rise = $risetemp
          if ($rise>=24-$zone);
        $set = $settemp
          if ($set>=24-$zone);
      }
    }elsif ($zone<0) {
      #rise time was yesterday local time -> calculate rise time for previous UTC day
      if ($rise<-$zone || $transit<-zone || $set<-zone) {
        ($transittemp,$risetemp,$settemp) = Astro_SunRise($JD-1, $deltaT, $lon, $lat, $zone, 1);
      $rise = $risetemp
        if ($rise<-$zone);
      $transit = $transittemp
        if ($transit<-$zone);
      $set  = $settemp
        if ($set <-$zone);
      }
    }
	
    $transit = Astro_mod($transit+$zone, 24.);
    $rise    = Astro_mod($rise   +$zone, 24.);
    $set     = Astro_mod($set    +$zone, 24.);

	#-- Twilight calculation
	#-- civil twilight time in UTC. 
	($transittemp,$risetemp,$settemp) = Astro_RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	   $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -6.*$DEG);
	my $CivilTwilightMorning = Astro_mod($risetemp +$zone, 24.);
	my $CivilTwilightEvening = Astro_mod($settemp  +$zone, 24.);

	#-- nautical twilight time in UTC. 
	($transittemp,$risetemp,$settemp) = Astro_RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -12.*$DEG);
	my $NauticTwilightMorning = Astro_mod($risetemp +$zone, 24.);
	my $NauticTwilightEvening = Astro_mod($settemp  +$zone, 24.);

	#-- astronomical twilight time in UTC. 
	($transittemp,$risetemp,$settemp) = Astro_RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, -18.*$DEG);
	my $AstroTwilightMorning = Astro_mod($risetemp +$zone, 24.);
	my $AstroTwilightEvening = Astro_mod($settemp  +$zone, 24.);
	
	#-- custom twilight time in UTC
    ($transittemp,$risetemp,$settemp) = Astro_RiseSet($jd0UT, $sunCoor1->{diameter}, $sunCoor1->{parallax}, 
	  $sunCoor1->{ra}, $sunCoor1->{dec}, $sunCoor2->{ra}, $sunCoor2->{dec}, $lon, $lat, 1, $Astro{ObsHor}*$DEG);
	my $CustomTwilightMorning = Astro_mod($risetemp +$zone, 24.);
	my $CustomTwilightEvening = Astro_mod($settemp  +$zone, 24.);
	
	return( ($transit,$rise,$set,$CivilTwilightMorning,$CivilTwilightEvening,
	  $NauticTwilightMorning,$NauticTwilightEvening,$AstroTwilightMorning,$AstroTwilightEvening,$CustomTwilightMorning,$CustomTwilightEvening) );  
  }else{
    return( ($transit,$rise,$set) );  
  }
}

########################################################################################################
#
# Astro_MoonRise - Find local time of moonrise and moonset
# JD is the Julian Date of 0h local time (midnight)
# Accurate to about 5 minutes or better
# recursive: 1 - calculate rise/set in UTC
# recursive: 0 - find rise/set on the current local day (set could also be first)
# returns '' for moonrise/set does not occur on selected day
# 
########################################################################################################

sub Astro_MoonRise($$$$$$$){
  my ($JD, $deltaT, $lon, $lat, $radius, $zone, $recursive) = @_;
  my $timeinterval = 0.5;
  
  my $jd0UT = floor($JD-0.5)+0.5;   # JD at 0 hours UT
  #-- calculations for noon
  my $sunCoor1  = Astro_SunPosition($jd0UT+ $deltaT/24./3600.,undef,undef);
  my $moonCoor1 = Astro_MoonPosition($sunCoor1->{lon}, $sunCoor1->{anomalyMean}, $jd0UT+ $deltaT/24./3600.,undef,undef,undef,undef);
 
  #-- calculations for next day's midnight
  my $sunCoor2  = Astro_SunPosition($jd0UT +$timeinterval + $deltaT/24./3600.,undef,undef); 
  my $moonCoor2 = Astro_MoonPosition($sunCoor2->{lon}, $sunCoor2->{anomalyMean}, $jd0UT +$timeinterval + $deltaT/24./3600.,undef,undef,undef,undef); 

  # rise/set time in UTC, time zone corrected later.
  # Taking into account refraction, semi-diameter and parallax
  my ($transit,$rise,$set) = Astro_RiseSet($jd0UT, $moonCoor1->{diameter}, $moonCoor1->{parallax}, 
    $moonCoor1->{ra}, $moonCoor1->{dec}, $moonCoor2->{ra}, $moonCoor2->{dec}, $lon, $lat, $timeinterval,undef); 
  my ($transittemp,$risetemp,$settemp);
  my ($transitprev,$riseprev,$setprev);
  
  # check and adjust to have rise/set time on local calendar day
  if ( $recursive==0 ) { 
    if ($zone>0) {
      # recursive call to MoonRise returns events in UTC
      ($transitprev,$riseprev,$setprev) = Astro_MoonRise($JD-1., $deltaT, $lon, $lat, $radius, $zone, 1);  
      if ($transit >= 24.-$zone || $transit < -$zone) { # transit time is tomorrow local time
        if ($transitprev < 24.-$zone){
           $transit = ""; # there is no moontransit today
        }else{
           $transit  = $transitprev;
        }
      }
      
      if ($rise >= 24.-$zone || $rise < -$zone) { # rise time is tomorrow local time
        if ($riseprev < 24.-$zone){
          $rise = ""; # there is no moontransit today
        }else{ 
          $rise  = $riseprev;
        }
      }

      if ($set >= 24.-$zone || $set < -$zone) { # set time is tomorrow local time
        if ($setprev < 24.-$zone){
          $set = ""; # there is no moontransit today
        }else{
          $set  = $setprev;
        }
      }

    }elsif ($zone<0) { # rise/set time was tomorrow local time -> calculate rise time for previous UTC day
      if ($rise<-$zone || $set<-$zone || $transit<-$zone) { 
        ($transittemp,$risetemp,$settemp) = Astro_MoonRise($JD+1., $deltaT, $lon, $lat, $radius, $zone, 1);  
        if ($rise < -$zone) {
          if ($risetemp > -$zone){
             $rise = ''; # there is no moonrise today
          }else{
             $rise = $risetemp;
          }
        }
        
        if ($transit < -zone){
          if ($transittemp > -zone){
            $transit = ''; # there is no moonset today
          }else{
            $transit  = $transittemp;
          }
        }
        
        if ($set < -zone){
          if ($settemp > -zone){
            $set = ''; # there is no moonset today
          }else{
            $set  = $settemp;
          }
        }     
      }
    }
    #-- correct for time zone, if time is valid
    $transit = Astro_mod($transit +$zone, 24.)
      if( $transit ne ""); 
    $rise = Astro_mod($rise +$zone, 24.)
      if ($rise ne "");    
    $set  = Astro_mod($set +$zone, 24.)
      if ($set ne "");   
  }
  return( ($transit,$rise,$set) );
}

########################################################################################################
#
# Astro_Compute - sequential calculation of properties
# 
########################################################################################################
  
sub Astro_Compute($){
  my ($hash) = @_;

  my $name = $hash->{NAME};
  
  #-- readjust language
  my $lang = AttrVal("global","language","EN");
  if( $lang eq "DE"){
    $astro_tt = \%astro_transtable_DE;
  }else{
    $astro_tt = \%astro_transtable_EN;
  }
  
  return undef if( !$init_done );

  #-- geodetic latitude and longitude of observer on WGS84  
  if( defined($attr{$name}{"latitude"}) ){
    $Astro{ObsLat}  = $attr{$name}{"latitude"};
  }elsif( defined($attr{"global"}{"latitude"}) ){
    $Astro{ObsLat}  = $attr{"global"}{"latitude"};
  }else{
    $Astro{ObsLat}  = 50.0;
    Log3 $name,1,"[Astro] No latitude attribute set in global device, using 50.0°";
  }
  if( defined($attr{$name}{"longitude"}) ){
    $Astro{ObsLon}  = $attr{$name}{"longitude"};
  }elsif( defined($attr{"global"}{"longitude"}) ){
    $Astro{ObsLon}  = $attr{"global"}{"longitude"};
  }else{
    $Astro{ObsLon}  = 10.0;
    Log3 $name,1,"[Astro] No longitude attribute set in global device, using 10.0°";
  } 
  #-- altitude of observer in meters above WGS84 ellipsoid 
  if( defined($attr{$name}{"altitude"}) ){
    $Astro{ObsAlt}  = $attr{$name}{"altitude"};
  }elsif( defined($attr{"global"}{"altitude"}) ){
    $Astro{ObsAlt}  = $attr{"global"}{"altitude"};
  }else{
    $Astro{ObsAlt}  = 0.0;
    Log3 $name,1,"[Astro] No altitude attribute set in global device, using 0.0 m above sea level";
  } 
  #-- custom horizon of observer in degrees
  if( defined($attr{$name}{"horizon"}) ){
    $Astro{ObsHor}  = $attr{$name}{"horizon"};
  }else{
    $Astro{ObsHor}  = 0.0;
    Log3 $name,1,"[Astro] No horizon attribute defined, using 0.0°";
  } 
  
  #-- internal variables converted to Radians and km 
  my $lat      = $Astro{ObsLat}*$DEG;
  my $lon      = $Astro{ObsLon}*$DEG;
  my $height   = $Astro{ObsAlt} * 0.001;   

  #if (eval(form.Year.value)<=1900 || eval(form.Year.value)>=2100 ) {
  #  alert("Dies Script erlaubt nur Berechnungen"+
  #  return;
  #}

  my $JD0 = Astro_CalcJD( $Date{day}, $Date{month}, $Date{year} );
  my $JD  = $JD0 + ( $Date{hour} - $Date{zonedelta} + $Date{min}/60. + $Date{sec}/3600.)/24;
  my $TDT = $JD  + $deltaT/86400.0; 
  
  $Astro{ObsJD}   = Astro_round($JD,2);

  my $gmst        = Astro_GMST($JD);
  $Astro{ObsGMST} = Astro_HHMMSS($gmst);
  my $lmst        = Astro_GMST2LMST($gmst, $lon); 
  $Astro{ObsLMST} = Astro_HHMMSS($lmst);
  
  #-- geocentric cartesian coordinates of observer
  my ($x,$y,$z,$radius) = Astro_Observer2EquCart($lon, $lat, $height, $gmst); 
 
  #-- calculate data for the sun at given time
  my $sunCoor     = Astro_SunPosition($TDT, $lat, $lmst*15.*$DEG);   
  $Astro{SunLon}  = Astro_round($sunCoor->{lon}*$RAD,1);
  #$Astro{SunLat}  = $sunCoor->{lat}*$RAD;
  $Astro{SunRa}   = Astro_round($sunCoor->{ra} *$RAD/15,1);
  $Astro{SunDec}  = Astro_round($sunCoor->{dec}*$RAD,1);
  $Astro{SunAz}   = Astro_round($sunCoor->{az} *$RAD,1);
  $Astro{SunAlt}  = Astro_round($sunCoor->{alt}*$RAD + Astro_Refraction($sunCoor->{alt}),1);  # including refraction WARNUNG => *RAD ???
  $Astro{SunSign} = $astro_tt->{$sunCoor->{sig}};
  $Astro{SunDiameter}=Astro_round($sunCoor->{diameter}*$RAD*60,1); #angular diameter in arc seconds
  $Astro{SunDistance}=Astro_round($sunCoor->{distance},0);
  
  #-- calculate distance from the observer (on the surface of earth) to the center of the sun
  my ($xs,$ys,$zs) = Astro_EquPolar2Cart($sunCoor->{ra}, $sunCoor->{dec}, $sunCoor->{distance});
  $Astro{SunDistanceObserver} = Astro_round(sqrt( ($xs-$x)**2 + ($ys-$y)**2 + ($zs-$z)**2 ),0);
  
  my ($suntransit,$sunrise,$sunset,$CivilTwilightMorning,$CivilTwilightEvening,
    $NauticTwilightMorning,$NauticTwilightEvening,$AstroTwilightMorning,$AstroTwilightEvening,$CustomTwilightMorning,$CustomTwilightEvening) = 
    Astro_SunRise($JD0, $deltaT, $lon, $lat, $Date{zonedelta}, 0);
  $Astro{SunTransit} = Astro_HHMM($suntransit);
  $Astro{SunRise}    = Astro_HHMM($sunrise);
  $Astro{SunSet}     = Astro_HHMM($sunset);
  $Astro{CivilTwilightMorning}    = Astro_HHMM($CivilTwilightMorning);
  $Astro{CivilTwilightEvening}    = Astro_HHMM($CivilTwilightEvening);
  $Astro{NauticTwilightMorning}   = Astro_HHMM($NauticTwilightMorning);
  $Astro{NauticTwilightEvening}   = Astro_HHMM($NauticTwilightEvening);
  $Astro{AstroTwilightMorning}    = Astro_HHMM($AstroTwilightMorning);
  $Astro{AstroTwilightEvening}    = Astro_HHMM($AstroTwilightEvening);
  $Astro{CustomTwilightMorning}    = Astro_HHMM($CustomTwilightMorning);
  $Astro{CustomTwilightEvening}    = Astro_HHMM($CustomTwilightEvening);
  
  #-- calculate data for the moon at given time
  my $moonCoor    = Astro_MoonPosition($sunCoor->{lon}, $sunCoor->{anomalyMean}, $TDT, $lon, $lat, $radius, $lmst*15.*$DEG);
  $Astro{MoonLon} = Astro_round($moonCoor->{lon}*$RAD,1);
  $Astro{MoonLat} = Astro_round($moonCoor->{lat}*$RAD,1);
  $Astro{MoonRa}  = Astro_round($moonCoor->{ra} *$RAD/15.,1);
  $Astro{MoonDec} = Astro_round($moonCoor->{dec}*$RAD,1);
  $Astro{MoonAz}  = Astro_round($moonCoor->{az} *$RAD,1);
  $Astro{MoonAlt} = Astro_round($moonCoor->{alt}*$RAD + Astro_Refraction($moonCoor->{alt}),1);  # including refraction WARNUNG => *RAD ???
  $Astro{MoonSign}     = $astro_tt->{$moonCoor->{sig}};
  $Astro{MoonDistance} = Astro_round($moonCoor->{distance},0);
  $Astro{MoonDiameter} = Astro_round($moonCoor->{diameter}*$RAD*60.,1); # angular diameter in arc seconds
  $Astro{MoonAge}      = Astro_round($moonCoor->{age}*$RAD,1);
  $Astro{MoonPhaseN}   = Astro_round($moonCoor->{phasen},2);
  $Astro{MoonPhaseI}   = $astro_tt->{$moonCoor->{phasei}};
  $Astro{MoonPhaseS}   = $astro_tt->{$moonCoor->{phases}};
  
  #-- calculate distance from the observer (on the surface of earth) to the center of the moon
  my ($xm,$ym,$zm) = Astro_EquPolar2Cart($moonCoor->{ra}, $moonCoor->{dec}, $moonCoor->{distance});
  #Log 1,"  distance=".$moonCoor->{distance}."   test=".sqrt( ($xm)**2 + ($ym)**2 + ($zm)**2 )." $xm  $ym  $zm";
  #Log 1,"  distance=".$radius."   test=".sqrt( ($x)**2 + ($y)**2 + ($z)**2 )." $x  $y  $z";
  $Astro{MoonDistanceObserver} = Astro_round(sqrt( ($xm-$x)**2 + ($ym-$y)**2 + ($zm-$z)**2 ),0);
  
  my ($moontransit,$moonrise,$moonset) = Astro_MoonRise($JD0, $deltaT, $lon, $lat, $radius, $Date{zonedelta}, 0);
  $Astro{MoonTransit} = Astro_HHMM($moontransit);
  $Astro{MoonRise}    = Astro_HHMM($moonrise);
  $Astro{MoonSet}     = Astro_HHMM($moonset);
  
  #-- fix date
  $Astro{ObsDate}= sprintf("%02d.%02d.%04d",$Date{day},$Date{month},$Date{year});
  $Astro{ObsTime}= sprintf("%02d:%02d:%02d",$Date{hour},$Date{min},$Date{sec});
  $Astro{ObsTimezone}= $Date{zonedelta};
  
  #-- check season
  my $doj = $Date{dayofyear};
  $Astro{ObsDayofyear} = $doj;
  
  for( my $i=0;$i<4;$i++){
    my $key = $seasons[$i];
    if(   (($seasonn{$key}[0] < $seasonn{$key}[1]) &&  ($seasonn{$key}[0] <= $doj) && ($seasonn{$key}[1] >= $doj))
       || (($seasonn{$key}[0] > $seasonn{$key}[1]) && (($seasonn{$key}[0] <= $doj) || ($seasonn{$key}[1] >= $doj))) ){
       $Astro{ObsSeason}  = $astro_tt->{$key};
       $Astro{ObsSeasonN} = $i; 
       last;
    }  
  }
 
  return( undef );
};

########################################################################################
#
# Astro_Update - Update readings 
#
#  Parameter hash = hash of the bus master a = argument array
#
########################################################################################

sub Astro_Update($@) {
  my ($hash) = @_;
  
  my $name     = $hash->{NAME};
  RemoveInternalTimer($hash);
  my $interval = ( defined($hash->{INTERVAL})) ? $hash->{INTERVAL} : 3600;
   
  InternalTimer(gettimeofday()+ $interval, "Astro_Update", $hash,1)
    if( $interval > 0 );

  #-- Current time will be used
  my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime(time);
  $year  += 1900;
  $month += 1;
  $Date{year} = $year;
  $Date{month}= $month;
  $Date{day}  = $day;
  $Date{hour} = $hour;
  $Date{min}  = $min;
  $Date{sec}  = $sec; 
  $Date{zonedelta} = (strftime "%z", localtime)/100;
  $Date{dayofyear} = strftime("%-j", localtime);
  
  Astro_Compute($hash);
  
  readingsBeginUpdate($hash);
  foreach my $key (keys %Astro){   
    readingsBulkUpdate($hash,$key,$Astro{$key});
  }
  readingsEndUpdate($hash,1); 
}

########################################################################################
#
# Astro_Get - Implements GetFn function 
#
#  Parameter hash = hash of the bus master a = argument array
#
########################################################################################

sub Astro_Get($@) {
  my ($hash, @a) = @_;
  
  my $name     = $hash->{NAME};
  
  my $wantsreading = 0;
  
  #-- second parameter may be a reading
  if( (int(@a)>2) && exists($Astro{$a[2]})) {
    $wantsreading = 1;
    #Log 1,"=================> WANT as ".$a[1]." READING ".$a[2]." GET READING ".$Astro{$a[2]};
  }
    
  if( int(@a) > (2+$wantsreading) ) {
    my $str = (int(@a) == (4+$wantsreading)) ? $a[2+$wantsreading]." ".$a[3+$wantsreading] : $a[2+$wantsreading];
    if( $str =~ /(\d{4})-(\d{2})-(\d{2})(\D*(\d{2}):(\d{2})(:(\d{2}))?)?/){
      $Date{year} = $1;
      $Date{month}= $2;
      $Date{day}  = $3;
      $Date{hour} = (defined($5)) ? $5 : 12;
      $Date{min}  = (defined($6)) ? $6 : 0;
      $Date{sec}  = (defined($8)) ? $8 : 0; 
      my $fTot = timelocal($Date{sec},$Date{min},$Date{hour},$Date{day},$Date{month}-1,$Date{year});
      $Date{zonedelta} = (strftime "%z", localtime($fTot))/100;
      $Date{dayofyear} = strftime("%-j", localtime($fTot));
    }else{
      return "[Astro_Get] $name has improper time specification, use YYYY-MM-DD HH:MM:SS";
    }
  }else{
    #-- Current time will be used
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime(time);
    $year  += 1900;
    $month += 1;
    $Date{year} = $year;
    $Date{month}= $month;
    $Date{day}  = $day;
    $Date{hour} = $hour;
    $Date{min}  = $min;
    $Date{sec}  = $sec; 
    $Date{zonedelta} = (strftime "%z", localtime)/100;
    $Date{dayofyear} = strftime("%-j", localtime);
  }

  if( $a[1] eq "version") {
    return $astroversion;
    
  }elsif( $a[1] eq "json") {
    Astro_Compute($hash);
    if( $wantsreading==1 ){
      return toJSON($Astro{$a[2]});
    }else{
      return toJSON(\%Astro);
    }
    
  }elsif( $a[1] eq "text") {
  
    Astro_Compute($hash);
    if( $wantsreading==1 ){
      return $Astro{$a[2]};
    }else{
      my $ret=sprintf("%s %s %s \n",$astro_tt->{"date"},$Astro{ObsDate},$Astro{ObsTime});
      $ret .= sprintf("%s %.2f %s, %d %s\n",$astro_tt->{"jdate"},$Astro{ObsJD},$astro_tt->{"days"},$Astro{ObsDayofyear},$astro_tt->{"dayofyear"});
      $ret .= sprintf("%s %s, %s %2d\n",$astro_tt->{"season"},$Astro{ObsSeason},$astro_tt->{"timezone"},$Astro{ObsTimezone});
      $ret .= sprintf("%s %.5f° %s, %.5f° %s, %.0fm %s\n",$astro_tt->{"coord"},$Astro{ObsLon},$astro_tt->{"longitude"},
        $Astro{ObsLat},$astro_tt->{"latitude"},$Astro{ObsAlt},$astro_tt->{"altitude"});
      $ret .= sprintf("%s %s \n\n",$astro_tt->{"lmst"},$Astro{ObsLMST});
      $ret .= "\n".$astro_tt->{"sun"}."\n";
      $ret .= sprintf("%s %s   %s %s   %s %s\n",$astro_tt->{"rise"},$Astro{SunRise},$astro_tt->{"set"},$Astro{SunSet},$astro_tt->{"transit"},$Astro{SunTransit});
      $ret .= sprintf("%s %s  -  %s\n",$astro_tt->{"twilightcivil"},$Astro{CivilTwilightMorning},$Astro{CivilTwilightEvening});
      $ret .= sprintf("%s %s  -  %s\n",$astro_tt->{"twilightnautic"},$Astro{NauticTwilightMorning},$Astro{NauticTwilightEvening});
      $ret .= sprintf("%s %s  -  %s\n",$astro_tt->{"twilightastro"},$Astro{AstroTwilightMorning},$Astro{AstroTwilightEvening});
      $ret .= sprintf("%s: %.0fkm %s (%.0fkm %s)\n",$astro_tt->{"distance"},$Astro{SunDistance},$astro_tt->{"toce"},$Astro{SunDistanceObserver},$astro_tt->{"toobs"});
      $ret .= sprintf("%s:  %s %2.1f°, %s %2.2fh, %s %2.1f°; %s %2.1f°, %s %2.1f°\n",
        $astro_tt->{"position"},$astro_tt->{"lonecl"},$Astro{SunLon},$astro_tt->{"ra"},
        $Astro{SunRa},$astro_tt->{"dec"},$Astro{SunDec},$astro_tt->{"az"},$Astro{SunAz},$astro_tt->{"alt"},$Astro{SunAlt});
      $ret .= sprintf("%s %2.1f', %s %s\n\n",$astro_tt->{"diameter"},$Astro{SunDiameter},$astro_tt->{"sign"},$Astro{SunSign});
      $ret .= "\n".$astro_tt->{"moon"}."\n";
      $ret .= sprintf("%s %s   %s %s   %s %s\n",$astro_tt->{"rise"},$Astro{MoonRise},$astro_tt->{"set"},$Astro{MoonSet},$astro_tt->{"transit"},$Astro{MoonTransit});
      $ret .= sprintf("%s: %.0fkm %s (%.0fkm %s)\n",$astro_tt->{"distance"},$Astro{MoonDistance},$astro_tt->{"toce"},$Astro{MoonDistanceObserver},$astro_tt->{"toobs"});
      $ret .= sprintf("%s:  %s %2.1f°, %s %2.1f°; %s %2.2fh, %s %2.1f°; %s %2.1f°, %s %2.1f°\n",
        $astro_tt->{"position"},$astro_tt->{"lonecl"},$Astro{MoonLon},$astro_tt->{"latecl"},$Astro{MoonLat},$astro_tt->{"ra"},
        $Astro{MoonRa},$astro_tt->{"dec"},$Astro{MoonDec},$astro_tt->{"az"},$Astro{MoonAz},$astro_tt->{"alt"},$Astro{MoonAlt});
      $ret .= sprintf("%s %2.1f',  %s %2.1f°, %s %1.2f = %s, %s %s\n",$astro_tt->{"diameter"},
        $Astro{MoonDiameter},$astro_tt->{"age"},$Astro{MoonAge},$astro_tt->{"phase"},$Astro{MoonPhaseN},$Astro{MoonPhaseS},$astro_tt->{"sign"},$Astro{MoonSign});
    
    #$ret .="\ndistance=".$moonCoor->{distance}."   test=".sqrt( ($xm)**2 + ($ym)**2 + ($zm)**2 )." $xm  $ym  $zm";
    #$ret .="\ndistance=".$radius."   test=".sqrt( ($x)**2 + ($y)**2 + ($z)**2 )." $x  $y  $z";
     return $ret;
    }
  }else {
    return "[Astro_Get] $name with unknown argument $a[1], choose one of ". 
    join(" ", sort keys %gets);
  }
}

1;

=pod
=item helper
=item summary collection of various routines for astronomical data
=item summary_DE Sammlung verschiedener Routinen für astronomische Daten
=begin html

   <a name="Astro"></a>
        <h3>Astro</h3>
        <p> FHEM module with a collection of various routines for astronomical data</p>
        <a name="Astrodefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Astro</code>
            <br />Defines the Astro device (only one is needed per FHEM installation). </p>
        <p>
        Readings with prefix <i>Sun</i> refer to the sun, with prefix <i>Moon</i> refer to the moon.
        The suffixes for these readings are 
        <ul>
        <li><i>Age</i> = angle (in degrees) of body along its track</li>
        <li><i>Az,Alt</i> = azimuth and altitude angle (in degrees) of body above horizon</li>
        <li><i>Dec,Ra</i> = declination (in degrees) and right ascension (in HH:MM) of body position</li>
        <li><i>Lat,Lon</i> = latitude and longituds (in degrees) of body position</li>
        <li><i>Diameter</i> = virtual diameter (in arc minutes) of body</li>
        <li><i>Distance,DistanceObserver</i> = distance (in km) of body to center of earth or to observer</li>
        <li><i>PhaseN,PhaseS</i> = Numerical and string value for phase of body</li>
	    <li><i>Sign</i> = Circadian sign for body along its track</li>
	    <li><i>Rise,Transit,Set</i> = times (in HH:MM) for rise and set as well as for highest position of body</li>
        </ul>
        <p>
        Readings with prefix <i>Obs</i> refer to the observer.
        In addition to some of the suffixes gives above, the following may occur
        <ul>
        <li><i>Date,Dayofyear</i> = date</li>
        <li><i>JD</i> = Julian date</li>
        <li><i>Season,SeasonN</i> = String and numerical (0..3) value of season</li>
        <li><i>Time,Timezone</i> obvious meaning</li>
        <li><i>GMST,ÖMST</i> = Greenwich and Local Mean Sidereal Time (in HH:MM)</li>
	    </ul>
        Notes: <ul>
        <li>Calculations are only valid between the years 1900 and 2100</li>
        <li>Attention: Timezone is taken from the local Perl settings, NOT automatically defined for a location</li>
        <li>This module uses the global attribute <code>language</code> to determine its output data<br/>
         (default: EN=english). For German output set <code>attr global language DE</code>.</li>
        <li>The time zone is determined automatically from the local settings of the <br/>
        operating system. If geocordinates from a different time zone are used, the results are<br/>
        not corrected automatically.
        <li>Some definitions determining the observer position are used<br/>
        from the global device, i.e.<br/>
        <code>attr global longitude &lt;value&gt;</code><br/>
        <code>attr global latitude &lt;value&gt;</code><br/>
        <code>attr global altitude &lt;value&gt;</code> (in m above sea level)<br/>
        These definitions are only used when there are no corresponding local attribute settings.
        </li>
        <li>
        It is not necessary to define an Astro device to use the data provided by this module<br/>
        To use its data in any other module, you just need to put <code>require "95_Astro.pm";</code> <br/>
        at the start of your own code, and then may call, for example, the function<br/> 
        <code>Astro_Get( SOME_HASH_REFERENCE,"dummy","text", "SunRise","2019-12-24");</code><br/>
        to acquire the sunrise on Christmas Eve 2019</li>
        </ul>
        <a name="Astroget"></a>
        <h4>Get</h4>
        Attention: Get-calls are NOT written into the readings of the device ! Readings change only through periodic updates !<br/>
       </li>
        <ul>
            <li><a name="astro_json"></a>
                <code>get &lt;name&gt; json [&lt;reading&gt;]</code><br/>
                <code>get &lt;name&gt; json [&lt;reading&gt;] YYYY-MM-DD</code><br/>
                <code>get &lt;name&gt; json [&lt;reading&gt;] YYYY-MM-DD HH:MM:[SS]</code>
                <br />returns the complete set or an individual reading of astronomical data either for the current time, or for a day and time given in the argument.</li>
            <li><a name="astro_text"></a>
                <code>get &lt;name&gt; text [&lt;reading&gt;]</code><br/>
                <code>get &lt;name&gt; text [&lt;reading&gt;] YYYY-MM-DD</code><br/>
                <code>get &lt;name&gt; text [&lt;reading&gt;] YYYY-MM-DD HH:MM:[SS]</code>
                <br />returns the complete set or an individual reading of astronomical data either for the current time, or for a day and time given in the argument.</li>            
            <li><a name="astro_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>             
        </ul>
        <a name="Astroattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="astro_interval">
                <code>&lt;interval&gt;</code>
                <br />Update interval in seconds. The default is 3600 seconds, a value of 0 disables the automatic update. </li>
                  <li>Some definitions determining the observer position:<br/>
        <code>attr  &lt;name&gt;  longitude &lt;value&gt;</code><br/>
        <code>attr  &lt;name&gt;  latitude &lt;value&gt;</code><br/>
        <code>attr  &lt;name&gt;  altitude &lt;value&gt;</code> (in m above sea level)<br/>
        <code>attr  &lt;name&gt;  horizon &lt;value&gt;</code> custom horizon angle in degrees, default 0<br/>
        These definitions take precedence over global attribute settings.
        </li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
=end html
=begin html_DE

<a name="Astro"></a>
<h3>Astro</h3>
Keine deutsche Dokumentation vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#Astro">Astro</a> 
=end html_DE
=cut