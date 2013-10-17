# $Id$
##############################################################################
#
#     59_Twilight.pm
#     Copyright by Sebastian Stuecker
#     erweitert von Dietmar Ortmann
#
#     Sun position computing
#     Copyright (C) 2013 Julian Pawlowski, julian.pawlowski AT gmail DOT com
#     based on Twilight.tcl  http://www.homematic-wiki.info/mw/index.php/TCLScript:twilight
#     With contribution from http://www.ip-symcon.de/forum/threads/14925-Sonnenstand-berechnen-(Azimut-amp-Elevation)
#
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
use HttpUtils;
use Math::Trig;

sub Twilight_calc($$$$$$$);
sub Twilight_getWeatherHorizon($);
sub Twilight_my_gmt_offset();
sub Twilight_midnight_seconds();

sub Twilight_my_gmt_offset()
{
  # inspired by http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
  # avoid use of any CPAN module and ensure system independent behavior

  my $t  = time;
  my @a  = localtime($t);
  my @b  = gmtime($t);
  my $hh = $a[2] - $b[2];
  my $mm = $a[1] - $b[1];
  # in the unlikely event that localtime and gmtime are in different years
  if ($a[5]*366+$a[4]*31+$a[3] > $b[5]*366+$b[4]*31+$b[3]) {
    $hh += 24;
  } elsif ($a[5]*366+$a[4]*31+$a[3] < $b[5]*366+$b[4]*31+$b[3]) {
    $hh -= 24;
  }
  if ($hh < 0 && $mm > 0) {
    $hh++;
    $mm = 60-$mm;
  }
  return $hh+($mm/60);
}

##################################### 
sub Twilight_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "Twilight_Define";
  $hash->{UndefFn} = "Twilight_Undef";
  $hash->{GetFn}   = "Twilight_Get";
  $hash->{AttrList}= $readingFnAttributes;
}
#
#
#
sub Twilight_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  #$hash->{LOCAL} = 1;
  #Twilight_GetUpdate($hash);
  #delete $hash->{LOCAL};
  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
     $value= $hash->{READINGS}{$reading}{VAL};
  } else {
     return "no such reading: $reading";
  }
  return "$a[0] $reading => $value";
}
#
#
#
sub Twilight_Define($$)
{
  my ($hash, $def) = @_;
  # define <name> Twilight <latitude> <longitude> [indoor_horizon [Weather_Position]]
  # define MyTwilight Twilight 48.47 11.92 Weather_Position

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Twilight <latitude> <longitude> [indoor_horizon [Weather]]"
    if(int(@a) < 4 && int(@a) > 6);

  $hash->{STATE} = "0";

  my $latitude;
  my $longitude;
  my $name      = $a[0];
  if ($a[2] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[2] !~ /^[\. ]*$/ ) {
     $latitude  = $a[2];
	    if($latitude >  90){$latitude =  90;}
	    if($latitude < -90){$latitude = -90;}
	 }else{
     return "Argument Latitude is not a valid number";
  }

  if ($a[3] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[3] !~ /^[\. ]*$/ ) {
     $longitude  = $a[3];
	    if($longitude >  180){$longitude =  180;}
	    if($longitude < -180){$longitude = -180;}
	 }else{
     return "Argument Longitude is not a valid number";
  }

  my $weather   = "";
  my $indoor_horizon="4";
  if(int(@a)>5) { $weather=$a[5] }
  if(int(@a)>4) { if ($a[4] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[4] !~ /^[\. ]*$/ ) {
     $indoor_horizon  = $a[4];
 	   if($indoor_horizon > 20) { $indoor_horizon=20;}
	    if($indoor_horizon <  0) { $indoor_horizon= 0;}
  }else{
     return "Argument Indoor_Horizon is not a valid number";}
  }
   
  $hash->{WEATHER_HORIZON}  = 0;
  $hash->{INDOOR_HORIZON} = $indoor_horizon;
  $hash->{LATITUDE}       = $latitude;
  $hash->{LONGITUDE}      = $longitude;
  $hash->{WEATHER}        = $weather;
  $hash->{SUNPOS_OFFSET}  = 1;
 
  Twilight_sunposTimerSet($hash);
  RemoveInternalTimer($hash);
  InternalTimer(time()+1, "Twilight_Midnight", $hash, 0);
  return undef;
}
#
#
#
sub Twilight_Undef($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash->{$hash->{SP}{SUNPOS}});
  foreach my $key (keys %{$hash->{TW}}) {
     my $hashSx = $hash->{$hash->{TW}{$key}{NAME}};
     RemoveInternalTimer($hashSx);
  }
  RemoveInternalTimer($hash);
  return undef;
}
#
#
#
sub Twilight_midnight_seconds()
{
  my @time = localtime();
  my $secs = ($time[2] * 3600) + ($time[1] * 60) + $time[0];
  return $secs;
}
#
#
#
sub Twilight_TwilightTimes($$)
{
  my ($hash, $whitchTimes) = @_;
  my $latitude   = $hash->{LATITUDE};
  my $longitude  = $hash->{LONGITUDE};
  my $horizon    = $hash->{HORIZON};
  my $now        = time();
  my $midnight   = Twilight_midnight_seconds();
  my $midseconds = $now-$midnight;

  my $doy        = strftime("%j",localtime);

  my $timezone   = Twilight_my_gmt_offset();
  my $timediff   = -0.171 *sin(0.0337  * $doy+0.465) - 0.1299*sin(0.01787 * $doy - 0.168);
  my $declination=  0.4095*sin(0.016906*($doy-80.086));
  my $twilight_midnight = $now+(0-$timediff-$longitude/15+$timezone)*3600;

  my $yesterday_offset;
  if($now<$twilight_midnight){
     $yesterday_offset=86400;
  }else{
     $yesterday_offset=0;
  }

  Twilight_getWeatherHorizon($hash);

  if($hash->{WEATHER_HORIZON} > (89-$hash->{LATITUDE}+$declination) ){
     $hash->{WEATHER_HORIZON} =  89-$hash->{LATITUDE}+$declination;
  }

  readingsBeginUpdate ($hash);
  my $idx = -1; my ($sr, $ss, $or, $os);
  my @names = ("_astro:-18", "_naut:-12", "_civil:-6",":0", "_indoor:0", "_weather:0");

  $sr = "ss_astro"; $ss = "";
  foreach my $horizon (@names) {
    $idx++; next if ($whitchTimes eq "Wea" && $idx < 5 );

    my ($name, $deg) = split(":", $horizon);

    $deg = $hash->{INDOOR_HORIZON}  if ($idx==4);
    $deg = $hash->{WEATHER_HORIZON} if ($idx==5);

	               $or = $sr;                        $os = $ss;
                $sr          = "sr$name";         $ss         = "ss$name";
    $hash->{TW}{$sr}{NAME}   = $sr;   $hash->{TW}{$ss}{NAME}  = $ss;
    $hash->{TW}{$sr}{DEG}    = $deg;  $hash->{TW}{$ss}{DEG}   = $deg;
    $hash->{TW}{$sr}{LIGHT}  = $idx+1;$hash->{TW}{$ss}{LIGHT} = $idx;
    $hash->{TW}{$sr}{STATE}  = $idx+1;$hash->{TW}{$ss}{STATE} = 12 - $idx;
    $hash->{TW}{$or}{NEXTE}  = $sr;   $hash->{TW}{$ss}{NEXTE} = $os if ($os ne "");

    ($hash->{TW}{$sr}{TIME}, $hash->{TW}{$ss}{TIME})=
       Twilight_calc($latitude, $longitude, $deg, $declination, $timezone, $midseconds, $timediff);

    Log3 $hash, 3, "$hash->{TW}{$sr}{NAME},  $hash->{TW}{$ss}{NAME} are not defined(nan)"      if ($hash->{TW}{$sr}{TIME} eq "nan");
    $hash->{TW}{$sr}{TIME} += 0.01*$idx                                                if ($hash->{TW}{$sr}{TIME} ne "nan");
    $hash->{TW}{$ss}{TIME} -= 0.01*$idx                                                if ($hash->{TW}{$ss}{TIME} ne "nan");

    readingsBulkUpdate($hash, $sr, $hash->{TW}{$sr}{TIME} eq "nan" ? "undefined" : strftime("%H:%M:%S",localtime($hash->{TW}{$sr}{TIME})));
    readingsBulkUpdate($hash, $ss, $hash->{TW}{$ss}{TIME} eq "nan" ? "undefined" : strftime("%H:%M:%S",localtime($hash->{TW}{$ss}{TIME})));

    #         {Twilight_TwilightTimes($defs{"Twilight"}, "Wea")}
    #readingsBulkUpdate($hash, $sr."_el", sunrise_abs("Horizon=$hash->{TW}{$sr}{DEG}"));
    #readingsBulkUpdate($hash, $ss."_el", sunset_abs ("Horizon=$hash->{TW}{$ss}{DEG}"));

    my $sr_wea = $hash->{TW}{$sr}{TIME} - time();
    Twilight_EventsSet($hash, $sr)      if ($whitchTimes ne "Wea" or ($whitchTimes eq "Wea" and $sr_wea > -2*3600));
    Twilight_EventsSet($hash, $ss);
  }

  $hash->{TW}{sr_weather}{NEXTE}  = "ss_weather";
  $hash->{TW}{ss_astro}{STATE}    = 0;

  readingsBulkUpdate  ($hash,"condition",    $hash->{CONDITION});
  readingsBulkUpdate  ($hash,"condition_txt",$hash->{CONDITION_TXT});

  readingsEndUpdate  ($hash, defined($hash->{LOCAL} ? 0 : 1));
  return 1;
}
#
#
#
sub Twilight_EventsSet($$) {
   my ($hash, $key) = @_;

   if (!exists $hash->{SX}{$hash->{TW}{$key}{NAME}}) {
      my $hashSx = { HASH=>$hash, NAME=>"Twilight_$hash->{TW}{$key}{NAME}", SX_NAME=>"$hash->{TW}{$key}{NAME}" };
      $hash->{SX}{$hash->{TW}{$key}{NAME}} = $hashSx;
   }
   my $hashSx = $hash->{SX}{$hash->{TW}{$key}{NAME}};
   RemoveInternalTimer($hashSx);
   if ($hash->{TW}{$key}{TIME} ne "nan") {
      InternalTimer ($hash->{TW}{$key}{TIME},  "Twilight_fireEvent", $hashSx, 0);
   }
}
#
#
#
sub Twilight_WeatherTimerSet($)
{
  my ($hash) = @_;
  my $now    = time();

  foreach my $key ("ss_weather", "sr_weather" ) {
     my $tim = $hash->{TW}{$key}{TIME};
     if ($tim-60*60>$now) {
        InternalTimer     ($tim - 60*60, "Twilight_WeatherTimerUpdate", $hash, 0);
     }
  }
}
#
#
#
sub Twilight_Midnight($)
{
  my ($hash) = @_;

  Twilight_TwilightTimes      ($hash, "Mid");
  Twilight_StandardTimerSet   ($hash);
}
#
sub Twilight_WeatherTimerUpdate($)
{
  my ($hash) = @_;

  Twilight_TwilightTimes      ($hash, "Wea");
  Twilight_StandardTimerSet   ($hash);
}
#
sub Twilight_StandardTimerSet($) {
  my ($hash) = @_;
  my $midnight = time() - Twilight_midnight_seconds() + 24*3600 + 30;

  RemoveInternalTimer         ($hash);
  InternalTimer($midnight,    "Twilight_Midnight", $hash, 0);
  Twilight_WeatherTimerSet    ($hash);
}
#
sub Twilight_sunposTimerSet($) {
  my ($hash) = @_;

  $hash->{SP}{SUNPOS} = "sunpos";

  if (!exists $hash->{$hash->{SP}{SUNPOS}}) {
     my $hashSp = { HASH=>$hash, NAME=>"Twilight_sunpos" };
     $hash->{$hash->{SP}{SUNPOS}} = $hashSp;
  }
  my $hashSp = $hash->{$hash->{SP}{SUNPOS}};

  RemoveInternalTimer($hashSp);
  InternalTimer (time()+$hash->{SUNPOS_OFFSET},  "Twilight_sunpos", $hashSp, 0);
  $hash->{SUNPOS_OFFSET} = 5*60;
}
#
#
#
sub Twilight_fireEvent($)
{
   my ($hashSx) = @_;
   my $hash     = $hashSx->{HASH};
   my $name     = $hashSx->{NAME};
   my $sx_name  = $hashSx->{SX_NAME};

   my $deg      = $hash->{TW}{$sx_name}{DEG};
   my $light    = $hash->{TW}{$sx_name}{LIGHT};
   my $state    = $hash->{TW}{$sx_name}{STATE};

   my $nextEvent      = $hash->{TW}{$sx_name}{NEXTE};
   my $nextEventTime  = "undefined";
      $nextEventTime  = strftime("%H:%M:%S",localtime($hash->{TW}{$nextEvent}{TIME})) if ($hash->{TW}{$nextEvent}{TIME} ne "nan");
   Log3 $hash, 4, "[".$hash->{NAME}."] " . sprintf  ("%-10s state=%-2s light=%-2s nextEvent=%-10s %-14s  deg=%+.1f°",$sx_name, $state, $light, $nextEvent, strftime("%d.%m.%Y  %H:%M:%S",localtime($hash->{TW}{$nextEvent}{TIME})), $deg);

   my $eventTime  = $hash->{TW}{$sx_name}{TIME};
   my $now        = time();
   my $delta      = abs ($now - $eventTime);

   $hash->{STATE} = $state;
   readingsBeginUpdate($hash);
   readingsBulkUpdate ($hash, "light",           $light);
   readingsBulkUpdate ($hash, "horizon",         $deg);
   readingsBulkUpdate ($hash, "aktEvent",        $sx_name);
   readingsBulkUpdate ($hash, "nextEvent",       $nextEvent);
   readingsBulkUpdate ($hash, "nextEventTime",   $nextEventTime);

   my $doNotTrigger  = ((defined($hash->{LOCAL})) ? 1 : 0);
      $doNotTrigger  = $doNotTrigger   ||   ($delta > 5);
   readingsEndUpdate  ($hash, !$doNotTrigger);

}
#
sub Twilight_calc($$$$$$$)
{
  my ($latitude, $longitude, $horizon, $declination, $timezone, $midseconds, $timediff) = @_;

  my $s1 = sin($horizon /57.29578);
  my $s2 = sin($latitude/57.29578) * sin($declination);
  my $s3 = cos($latitude/57.29578) * cos($declination);

  my ($suntime, $sunrise, $sunset);
  my $acosArg = ($s1 - $s2) / $s3;
  if (abs($acosArg) < 1.0) {   # ok
     $suntime = 12*acos($acosArg)/pi;
     $sunrise = $midseconds + (12-$timediff -$suntime -$longitude/15+$timezone) * 3600;
     $sunset  = $midseconds + (12-$timediff +$suntime -$longitude/15+$timezone) * 3600;
  } else {
     $sunrise = $sunset = "nan";
  }

  return $sunrise, $sunset;
}
#
sub Twilight_getWeatherHorizon($)
{
  my $hash=shift; # 0

  my $mod = "[".$hash->{NAME} ."] ";
  my @a_current = (25,25,25,25,20,10,10,10,10,10,
                   10, 7, 7, 7, 5,10,10, 6, 6, 6,
                   10, 6 ,6, 6, 6, 6, 6, 5, 5, 3,
                    3, 0, 0, 0, 0, 7, 0,15,15,15,
                    9,15, 8, 5,12, 6, 8, 8);

  # condition codes are described in FHEM wiki and in the documentation of the yahoo weather API
  my $location=$hash->{WEATHER};
  my $url = "http://weather.yahooapis.com/forecastrss?w=".$location."&u=c";
  my $xml = GetFileFromURL($url, 3, undef, 1);

  my $current, my $cond, my $temp, my $aktTemp;
  if($xml=~/text="(.*)"(\ *)code="(.*)"(\ *)temp="(.*)"(\ *)date/){
    if(defined($1)){
      $cond   =$1;
      $current=$3;
      $temp   =$5;
    }else{
      $current=-1;
   }

   if(($current>=0) && ($current <=47)) {
     $hash->{WEATHER_CORRECTION} = $a_current[$current] / 25 * 20;
     $hash->{WEATHER_HORIZON}    = $hash->{WEATHER_CORRECTION} + $hash->{INDOOR_HORIZON};
     $hash->{CONDITION_TXT}      = $cond;
     $hash->{CONDITION}          = $current;
     $hash->{TEMPERATUR}         = $temp;
     return 1;
   }
  }

  Log3 $hash, 3, "[$hash->{NAME}] "
    ."No Weather location found at yahoo weather for location ID: $location\n"
    ."=======\n"
    .$xml
    ."\n=======";

  $hash->{WEATHER_HORIZON}="0";
  $hash->{CONDITION}="-1";
}

sub Twilight_sunpos($)
{
  my ($hashSp) = @_;
  my $hash = $hashSp->{HASH};
  my $hashName = $hash->{NAME};

  return "" if(AttrVal($hashName, "disable", undef));

  my $tn = TimeNow();
  my ($dSeconds,$dMinutes,$dHours,$iDay,$iMonth,$iYear,$wday,$yday,$isdst) = gmtime(time);
  $iMonth++;
  $iYear += 100;
  $dSeconds = 0;

  ############################
  my $dLongitude = $hash->{LONGITUDE};
  my $dLatitude  = $hash->{LATITUDE};
  Log3 $hash, 5, "Compute sunpos for latitude $dLatitude , longitude $dLongitude";

  my $pi=3.14159265358979323846;
  my $twopi=(2*$pi);
  my $rad=($pi/180);
  my $dEarthMeanRadius=6371.01;    # In km
  my $dAstronomicalUnit=149597890;    # In km

  # Calculate difference in days between the current Julian Day
  # and JD 2451545.0, which is noon 1 January 2000 Universal Time

  # Calculate time of the day in UT decimal hours
  my $dDecimalHours=$dHours + ($dMinutes + $dSeconds / 60.0 ) / 60.0;

  # Calculate current Julian Day
  my $iYfrom2000=$iYear;#expects now as YY ;
  my $iA=(14 - ($iMonth)) / 12;
  my $iM=($iMonth) + 12 * $iA -3;
  my $liAux3=(153 * $iM + 2)/5;
  my $liAux4=365 * ($iYfrom2000 - $iA);
  my $liAux5=( $iYfrom2000 - $iA)/4;
  my $dElapsedJulianDays=($iDay + $liAux3 + $liAux4 + $liAux5 + 59)+ -0.5 + $dDecimalHours/24.0;

  # Calculate ecliptic coordinates (ecliptic longitude and obliquity of the
  # ecliptic in radians but without limiting the angle to be less than 2*Pi
  # (i.e., the result may be greater than 2*Pi)

  my $dOmega         = 2.1429    - 0.0010394594   * $dElapsedJulianDays;
  my $dMeanLongitude = 4.8950630 + 0.017202791698 * $dElapsedJulianDays; # Radians
  my $dMeanAnomaly   = 6.2400600 + 0.0172019699   * $dElapsedJulianDays;
  my $dEclipticLongitude = $dMeanLongitude + 0.03341607 * sin( $dMeanAnomaly ) + 0.00034894 * sin( 2 * $dMeanAnomaly ) -0.0001134 -0.0000203 * sin($dOmega);
  my $dEclipticObliquity = 0.4090928 - 6.2140e-9 * $dElapsedJulianDays +0.0000396 * cos($dOmega);

  # Calculate celestial coordinates ( right ascension and declination ) in radians
  # but without limiting the angle to be less than 2*Pi (i.e., the result may be
  # greater than 2*Pi)

  my $dSin_EclipticLongitude=sin( $dEclipticLongitude );
  my $dY1=cos( $dEclipticObliquity ) * $dSin_EclipticLongitude;
  my $dX1=cos( $dEclipticLongitude );
  my $dRightAscension=atan2( $dY1,$dX1 );
  if ( $dRightAscension < 0.0 ) { $dRightAscension=$dRightAscension + $twopi };
  my $dDeclination=asin( sin( $dEclipticObliquity )* $dSin_EclipticLongitude );

  # Calculate local coordinates ( azimuth and zenith angle ) in degrees
  my $dGreenwichMeanSiderealTime=6.6974243242 + 0.0657098283 * $dElapsedJulianDays + $dDecimalHours;

  my $dLocalMeanSiderealTime=($dGreenwichMeanSiderealTime*15 + $dLongitude)* $rad;
  my $dHourAngle=$dLocalMeanSiderealTime - $dRightAscension;
  my $dLatitudeInRadians=$dLatitude * $rad;
  my $dCos_Latitude=cos( $dLatitudeInRadians );
  my $dSin_Latitude=sin( $dLatitudeInRadians );
  my $dCos_HourAngle=cos( $dHourAngle );
  my $dZenithAngle=(acos( $dCos_Latitude * $dCos_HourAngle * cos($dDeclination) + sin( $dDeclination )* $dSin_Latitude));
  my $dY=-sin( $dHourAngle );
  my $dX=tan( $dDeclination )* $dCos_Latitude - $dSin_Latitude * $dCos_HourAngle;
  my $dAzimuth=atan2( $dY, $dX );
  if ( $dAzimuth < 0.0 ) {$dAzimuth=$dAzimuth + $twopi};
  $dAzimuth=$dAzimuth / $rad;

  # Parallax Correction
  my $dParallax=($dEarthMeanRadius / $dAstronomicalUnit) * sin( $dZenithAngle);
  $dZenithAngle=($dZenithAngle + $dParallax) / $rad;
  my $dElevation=90 - $dZenithAngle;

  # set readings
  $dAzimuth   = int(100*$dAzimuth  )/100;
  $dElevation = int(100*$dElevation)/100;

  my $twilight = int(($dElevation+12.0)/18.0 * 1000)/10;
     $twilight = 100 if ($twilight>100);
     $twilight = 0   if ($twilight<  0);

  my $twilight_weather = int(($dElevation-$hash->{WEATHER_HORIZON}+12.0)/18.0 * 1000)/10;
     $twilight_weather = 100 if ($twilight_weather>100);
     $twilight_weather = 0   if ($twilight_weather<  0);

  my $compassPoint   = Twilight_CompassPoint($dAzimuth);

  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash,  "azimuth",               $dAzimuth    );
  readingsBulkUpdate ($hash,  "elevation",             $dElevation  );
  readingsBulkUpdate ($hash,  "twilight",              $twilight    );
  readingsBulkUpdate ($hash,  "twilight_weather",      $twilight_weather    );
  readingsBulkUpdate ($hash,  "compasspoint",          $compassPoint);
  readingsEndUpdate  ($hash,  defined($hash->{LOCAL} ? 0 : 1));

  Twilight_sunposTimerSet($hash);

  return undef;
}

##########################
sub Twilight_CompassPoint($) {
  my ($azimuth) = @_;

  my $compassPoint = "unknown";

  if ($azimuth      < 22.5) {
     $compassPoint = "north";
  } elsif ($azimuth < 45)   {
     $compassPoint = "north-northeast";
  } elsif ($azimuth < 67.5) {
     $compassPoint = "northeast";
  } elsif ($azimuth < 90)   {
     $compassPoint = "east-northeast";
  } elsif ($azimuth < 112.5){
     $compassPoint = "east";
  } elsif ($azimuth < 135)  {
     $compassPoint = "east-southeast";
  } elsif ($azimuth < 157.5){
    $compassPoint = "southeast";
  } elsif ($azimuth < 180)  {
    $compassPoint = "south-southeast";
  } elsif ($azimuth < 202.5){
    $compassPoint = "south";
  } elsif ($azimuth < 225)  {
    $compassPoint = "south-southwest";
  } elsif ($azimuth < 247.5){
    $compassPoint = "southwest";
  } elsif ($azimuth < 270)  {
    $compassPoint = "west-southwest";
  } elsif ($azimuth < 292.5){
    $compassPoint = "west";
  } elsif ($azimuth < 315)  {
    $compassPoint = "west-northwest";
  } elsif ($azimuth < 337.5){
    $compassPoint = "northwest";
  } elsif ($azimuth <= 361)  {
    $compassPoint = "north-northwest";
  }
  return $compassPoint;
}

1;


=pod
=begin html

<a name="Twilight"></a>
<h3>Twilight</h3>
<ul>
  <br>

  <a name="Twilightdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Twilight &lt;latitude&gt; &lt;longitude&gt; [&lt;indoor_horizon&gt; [&lt;Weather_Position&gt;]]</code><br>
    <br>
    Defines a virtual device for Twilight calculations <br><br>

  <b>latitude, longitude</b>
  <br>
    The parameters <b>latitude</b> and <b>longitude</b> are decimal numbers which give the position on earth for which the twilight states shall be calculated.
    <br><br>
  <b>indoor_horizon</b>
  <br>
	   The parameter <b>indoor_horizon</b> gives a virtual horizon higher than 0, that shall be used for calculation of indoor twilight (typical values are between 0 and 6)
    <br><br>
  <b>Weather_Position</b>
  <br>
	   The parameter <b>Weather_Position</b> is the yahoo weather id used for getting the weather condition. Go to http://weather.yahoo.com/ and enter a city or zip code. In the upcoming webpage, the id is a the end of the URL. Example: Munich, Germany -> 676757
    <br><br>

    A Twilight device periodically calculates the times of different twilight phases throughout the day.
	It calculates a virtual "light" element, that gives an indicator about the amount of the current daylight.
	Besides the location on earth it is influenced by a so called "indoor horizon" (e.g. if there are high buildings, mountains) as well as by weather conditions. Very bad weather conditions lead to a reduced daylight for nearly the whole day.
	The light calculated spans between 0 and 6, where the values mean the following:
 <br><br>
  <b>light</b>
  <br>
	<code>0 - total night, sun is at least -18 degree below horizon</code><br>
	<code>1 - astronomical twilight, sun is between -12 and -18 degree below horizon</code><br>
	<code>2 - nautical twilight, sun is between -6 and -12 degree below horizon</code><br>
	<code>3 - civil twilight, sun is between 0 and -6 degree below horizon</code><br>
	<code>4 - indoor twilight, sun is between the indoor_horizon and 0 degree below horizon (not used if indoor_horizon=0)</code><br>
	<code>5 - weather twilight, sun is between indoor_horizon and a virtual weather horizon (the weather horizon depends on weather conditions (optional)</code><br>
	<code>6 - maximum daylight</code><br>
	<br>
 <b>Azimut, Elevation, Twilight</b>
 <br>
   The module calculates additionally the <b>azimuth</b> and the <b>elevation</b> of the sun. The values can be used to control a roller shutter.
   <br><br>
   As a new (twi)light value the reading <b>Twilight</b> ist added. It is derived from the elevation of the sun with the formula: (Elevation+12)/18 * 100). The value allows a more detailed
   control of any lamp during the sunrise/sunset phase. The value ist betwenn 0% and 100% when the elevation is between -12&deg; and 6&deg;.
   <br><br>
   You must know, that depending on the latitude, the sun will not reach any elevation. In june/july the sun never falls in middle europe
   below -18&deg;. In more northern countries(norway ...) the sun may not go below 0&deg;.
   <br><br>
   Any control depending on the value of Twilight must
   consider these aspects.
 	<br><br>

	Example:
    <pre>
      define myTwilight Twilight 49.962529  10.324845 3 676757
    </pre>
  </ul>
  <br>

  <a name="Twilightset"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>


  <a name="Twilightget"></a>
  <b>Get</b>
  <ul>

    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>
    <table>
    <tr><td>light</td><td>the current virtual daylight value</td></tr>
    <tr><td>nextEvent</td><td>the name of the next event</td></tr>
    <tr><td>nextEventTime</td><td>the time when the next event will probably happen (during light phase 5 and 6 this is updated when weather conditions change</td></tr>
    <tr><td>sr_astro</td><td>time of astronomical sunrise</td></tr>
    <tr><td>sr_naut</td><td>time of nautical sunrise</td></tr>
    <tr><td>sr_civil</td><td>time of civil sunrise</td></tr>
    <tr><td>sr</td><td>time of sunrise</td></tr>
    <tr><td>sr_indoor</td><td>time of indoor sunrise</td></tr>
    <tr><td>sr_weather</td><td>time of weather sunrise</td></tr>
    <tr><td>ss_weather</td><td>time of weather sunset</td></tr>
    <tr><td>ss_indoor</td><td>time of indoor sunset</td></tr>
    <tr><td>ss</td><td>time of sunset</td></tr>
    <tr><td>ss_civil</td><td>time of civil sunset</td></tr>
    <tr><td>ss_nautic</td><td>time of nautic sunset</td></tr>
    <tr><td>ss_astro</td><td>time of astro sunset</td></tr>
    <tr><td>azimuth</td><td>the current azimuth of the sun 0&deg; ist north 180&deg; is south</td></tr>
    <tr><td>compasspoint</td><td>a textual representation of the compass point</td></tr>
    <tr><td>elevation</td><td>the elevaltion of the sun</td></tr>
    <tr><td>twilight</td><td>a percetal value of a new (twi)light value: (elevation+12)/18 * 100) </td></tr>
    <tr><td>twilight_weather</td><td>a percetal value of a new (twi)light value: (elevation-WEATHER_HORIZON+12)/18 * 100). So if there is weather, it
                                     is always a little bit darker than by fair weather</td></tr>
    <tr><td>condition</td><td>the yahoo condition weather code</td></tr>
    <tr><td>condition_txt</td><td>the yahoo condition weather code as textual representation</td></tr>
    <tr><td>horizon</td><td>value auf the actual horizon 0&deg;, -6&deg;, -12&deg;, -18&deg;</td></tr>
    </table>

  </ul>
  <br>

  <a name="Twilightattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html
=cut
