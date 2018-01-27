# $Id$
##############################################################################
#
#     59_Twilight.pm
#     Copyright by Sebastian Stuecker
#     erweitert von Dietmar Ortmann
#     Maintained by igami since 02-2018
#
#     used algorithm see:          http://lexikon.astronomie.info/zeitgleichung/
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
use Time::Local 'timelocal_nocheck';

sub Twilight_calc($$);
sub Twilight_my_gmt_offset();
sub Twilight_midnight_seconds($);

################################################################################
sub Twilight_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "Twilight_Define";
  $hash->{UndefFn} = "Twilight_Undef";
  $hash->{GetFn}   = "Twilight_Get";
  $hash->{AttrList}= "$readingFnAttributes " ."useExtWeather";
  return undef;
}
################################################################################
sub Twilight_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
     $value= $hash->{READINGS}{$reading}{VAL};
  } else {
     return "no such reading: $reading";
  }
  return "$a[0] $reading => $value";
}
################################################################################
sub Twilight_Define($$)
{
  my ($hash, $def) = @_;

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

  my $weather         = 0;
  my $indoor_horizon  = 0;
  if(int(@a)>5) { $weather=$a[5] }
  if(int(@a)>4) { if ($a[4] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[4] !~ /^[\. ]*$/ ) {
     $indoor_horizon  = $a[4];
 	   if($indoor_horizon > 20) { $indoor_horizon=20;}
       # minimal indoor_horizon makes values like  civil_sunset and civil_sunrise
	   if($indoor_horizon <  -6) { $indoor_horizon= -6;}
  }else{
     return "Argument Indoor_Horizon is not a valid number";}
  }

  $hash->{WEATHER_HORIZON}  = 0;
  $hash->{INDOOR_HORIZON} = $indoor_horizon;
  $hash->{LATITUDE}       = $latitude;
  $hash->{LONGITUDE}      = $longitude;
  $hash->{WEATHER}        = $weather;
  $hash->{VERSUCHE}       = 0;
  $hash->{DEFINE}         = 1;
  $hash->{CONDITION}      = 50;
  $hash->{SUNPOS_OFFSET}  = 5*60;

  $attr{$name}{verbose} = 4    if ($name =~ /^tst.*$/ );

  my $mHash = { HASH=>$hash };
  Twilight_sunpos($mHash);
  Twilight_Midnight($mHash);

  delete $hash->{DEFINE};

  return undef;
}
################################################################################
sub Twilight_Undef($$) {
  my ($hash, $arg) = @_;

  foreach my $key (keys %{$hash->{TW}}) {
     myRemoveInternalTimer($key, $hash);
  }
  myRemoveInternalTimer    ("Midnight", $hash);
  myRemoveInternalTimer    ("weather",  $hash);
  myRemoveInternalTimer    ("sunpos",   $hash);

  return undef;
}
################################################################################
sub myInternalTimer($$$$$) {
   my ($modifier, $tim, $callback, $hash, $waitIfInitNotDone) = @_;

   my $timerName = "$hash->{NAME}_$modifier";
   my $mHash = { HASH=>$hash, NAME=>"$hash->{NAME}_$modifier", MODIFIER=>$modifier};
   if (defined($hash->{TIMER}{$timerName})) {
      Log3 $hash, 1, "[$hash->{NAME}] possible overwriting of timer $timerName - please delete first";
      stacktrace();
   } else {
      $hash->{TIMER}{$timerName} = $mHash;
   }

   Log3 $hash, 5, "[$hash->{NAME}] setting  Timer: $timerName " . FmtDateTime($tim);
   InternalTimer($tim, $callback, $mHash, $waitIfInitNotDone);
   return $mHash;
}
################################################################################
sub myRemoveInternalTimer($$) {
   my ($modifier, $hash) = @_;

   my $timerName = "$hash->{NAME}_$modifier";
   my $myHash = $hash->{TIMER}{$timerName};
   if (defined($myHash)) {
      delete $hash->{TIMER}{$timerName};
      Log3 $hash, 5, "[$hash->{NAME}] removing Timer: $timerName";
      RemoveInternalTimer($myHash);
   }
}
################################################################################
#sub myRemoveInternalTimerByName($){
#  my ($name) = @_;
#  foreach my $a (keys %intAt) {
#     my $nam = "";
#     my $arg = $intAt{$a}{ARG};
#        if (ref($arg) eq "HASH" && defined($arg->{NAME})  ) {
#           $nam = $arg->{NAME} if (ref($arg) eq "HASH" && defined($arg->{NAME})  );
#        }
#     delete($intAt{$a}) if($nam =~  m/^$name/g);
#  }
#}
################################################################################
sub myGetHashIndirekt ($$) {
  my ($myHash, $function) = @_;

  if (!defined($myHash->{HASH})) {
    Log 3, "[$function] myHash not valid";
    return undef;
  };
  return $myHash->{HASH};
}
################################################################################
sub Twilight_midnight_seconds($) {
  my ($now) = @_;
  my @time = localtime($now);
  my $secs = ($time[2] * 3600) + ($time[1] * 60) + $time[0];
  return $secs;
}
################################################################################
#sub Twilight_ssTimeAsEpoch($) {
#   my ($zeit) = @_;
#   my ($hour, $min, $sec) = split(":",$zeit);
#
#   my $days=0;
#   if ($hour>=24) {$days = 1; $hour -=24};
#
#   my @jetzt_arr = localtime(time());
#   #Stunden               Minuten               Sekunden
#   $jetzt_arr[2]  = $hour; $jetzt_arr[1] = $min; $jetzt_arr[0] = $sec;
#   $jetzt_arr[3] += $days;
#   my $next = timelocal_nocheck(@jetzt_arr);
#
#   return $next;
#}
################################################################################
sub Twilight_calc($$) {
   my ($deg, $idx) = @_;

   my $midnight = time() - Twilight_midnight_seconds(time());

   my $sr = sunrise_abs("Horizon=$deg");
   my $ss = sunset_abs ("Horizon=$deg");

   my ($srhour, $srmin, $srsec) = split(":",$sr); $srhour -= 24 if($srhour>=24);
   my ($sshour, $ssmin, $sssec) = split(":",$ss); $sshour -= 24 if($sshour>=24);

   my $sr1 = $midnight + 3600*$srhour+60*$srmin+$srsec;
   my $ss1 = $midnight + 3600*$sshour+60*$ssmin+$sssec;

   return (0,0) if (abs ($sr1 - $ss1) < 30);
   #return Twilight_ssTimeAsEpoch($sr) + 0.01*$idx,
   #       Twilight_ssTimeAsEpoch($ss) - 0.01*$idx;
   return ($sr1 + 0.01*$idx), ($ss1 - 0.01*$idx);
}
################################################################################
sub Twilight_TwilightTimes(@) {
  my ($hash, $whitchTimes, $xml) = @_;

  my $Name = $hash->{NAME};

  my $horizon    = $hash->{HORIZON};
  my $swip       = $hash->{SWIP} ;

  my $lat  = $attr{global}{latitude};  $attr{global}{latitude}  = $hash->{LATITUDE};
  my $long = $attr{global}{longitude}; $attr{global}{longitude} = $hash->{LONGITUDE};
# ------------------------------------------------------------------------------
  my $idx = -1;
  my @horizons = ("_astro:-18", "_naut:-12", "_civil:-6",":0", "_indoor:$hash->{INDOOR_HORIZON}", "_weather:$hash->{WEATHER_HORIZON}");
  foreach my $horizon (@horizons) {
    $idx++; next if ($whitchTimes eq "weather" && !($horizon =~ m/weather/) );

    my ($name, $deg) = split(":", $horizon);
    my $sr = "sr$name"; my $ss = "ss$name";
    $hash->{TW}{$sr}{NAME}   = $sr;   $hash->{TW}{$ss}{NAME}  = $ss;
    $hash->{TW}{$sr}{DEG}    = $deg;  $hash->{TW}{$ss}{DEG}   = $deg;
    $hash->{TW}{$sr}{LIGHT}  = $idx+1;$hash->{TW}{$ss}{LIGHT} = $idx;
    $hash->{TW}{$sr}{STATE}  = $idx+1;$hash->{TW}{$ss}{STATE} = 12 - $idx;
    $hash->{TW}{$sr}{SWIP}   = $swip; $hash->{TW}{$ss}{SWIP}  = $swip;

    ($hash->{TW}{$sr}{TIME}, $hash->{TW}{$ss}{TIME}) = Twilight_calc ($deg, $idx);

    if ($hash->{TW}{$sr}{TIME} == 0) {
       Log3 $hash, 4, "[$Name] hint: $hash->{TW}{$sr}{NAME},  $hash->{TW}{$ss}{NAME} are not defined(HORIZON=$deg)";
    }
  }
  $attr{global}{latitude}  = $lat;
  $attr{global}{longitude} = $long;
# ------------------------------------------------------------------------------
  readingsBeginUpdate ($hash);
  foreach my $ereignis (keys %{$hash->{TW}}) {
    next if ($whitchTimes eq "weather" && !($ereignis =~ m/weather/) );
    readingsBulkUpdate($hash, $ereignis, $hash->{TW}{$ereignis}{TIME} == 0 ? "undefined" : FmtTime($hash->{TW}{$ereignis}{TIME}));
  }
  if ($hash->{CONDITION} != 50 ) {
     readingsBulkUpdate  ($hash,"condition",    $hash->{CONDITION});
     readingsBulkUpdate  ($hash,"condition_txt",$hash->{CONDITION_TXT});
  }
  readingsEndUpdate   ($hash, defined($hash->{LOCAL} ? 0 : 1));
# ------------------------------------------------------------------------------
  my @horizonsOhneDeg = map {my($e, $deg)=split(":",$_); "$e"} @horizons;
  my @ereignisse = ((map {"sr$_"}@horizonsOhneDeg),(map {"ss$_"} reverse @horizonsOhneDeg),"sr$horizonsOhneDeg[0]");
  map { $hash->{TW}{$ereignisse[$_]}{NAMENEXT} = $ereignisse[$_+1] } 0..$#ereignisse-1;
# ------------------------------------------------------------------------------
  my $myHash;
  my $now                 = time();
  my $secSinceMidnight    = Twilight_midnight_seconds($now);
  my $lastMitternacht     = $now-$secSinceMidnight;
  my $nextMitternacht     = ($secSinceMidnight > 12*3600) ? $lastMitternacht+24*3600 : $lastMitternacht;
  my $jetztIstMitternacht = abs($now+5-$nextMitternacht)<=10;

  my @keyListe = qw "DEG LIGHT STATE SWIP TIME NAMENEXT";
  foreach my $ereignis (sort keys %{$hash->{TW}}) {
    next if ($whitchTimes eq "weather" && !($ereignis =~ m/weather/) );

    myRemoveInternalTimer($ereignis, $hash); # if(!$jetztIstMitternacht);
    if($hash->{TW}{$ereignis}{TIME} > 0) {
      $myHash = myInternalTimer($ereignis, $hash->{TW}{$ereignis}{TIME}, "Twilight_fireEvent", $hash, 0);
      map {$myHash->{$_} = $hash->{TW}{$ereignis}{$_} } @keyListe;
    }
  }
# ------------------------------------------------------------------------------
  return 1;
}
################################################################################
sub Twilight_fireEvent($) {
   my ($myHash) = @_;

   my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
   return if (!defined($hash));

   my $name          = $hash->{NAME};

   my $event         = $myHash->{MODIFIER};
   my $deg           = $myHash->{DEG};
   my $light         = $myHash->{LIGHT};
   my $state         = $myHash->{STATE};
   my $swip          = $myHash->{SWIP};

   my $eventTime     = $myHash->{TIME};
   my $nextEvent     = $myHash->{NAMENEXT};

   my $delta      = int($eventTime - time());
   my $oldState   = ReadingsVal($name,"state","0");

   my $nextEventTime = ($hash->{TW}{$nextEvent}{TIME} > 0) ? FmtTime($hash->{TW}{$nextEvent}{TIME}) : "undefined";

   my $doTrigger = !(defined($hash->{LOCAL})) && ( abs($delta)<6 || $swip  && $state gt $oldState);
  #Log3 $hash, 3, "[$hash->{NAME}] swip-delta-oldState-doTrigger===>$swip/$delta/$oldState/$doTrigger";

   Log3 $hash, 4,
     sprintf  ("[$hash->{NAME}] %-10s %-19s  ",        $event,     FmtDateTime($eventTime)).
     sprintf  ("(%2d/$light/%+5.1f°/$doTrigger)   ",   $state,     $deg).
     sprintf  ("===> %-10s %-19s  ",                   $nextEvent, $nextEventTime);


   readingsBeginUpdate($hash);
   readingsBulkUpdate ($hash, "state",           $state);
   readingsBulkUpdate ($hash, "light",           $light);
   readingsBulkUpdate ($hash, "horizon",         $deg);
   readingsBulkUpdate ($hash, "aktEvent",        $event);
   readingsBulkUpdate ($hash, "nextEvent",       $nextEvent);
   readingsBulkUpdate ($hash, "nextEventTime",   $nextEventTime);

   readingsEndUpdate  ($hash, $doTrigger);

}
################################################################################
sub Twilight_Midnight($) {
  my ($myHash) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  $hash->{SWIP} = 0;
  my $param = Twilight_CreateHttpParameterAndGetData($myHash, "Mid");
}
################################################################################
# {Twilight_WeatherTimerUpdate( {HASH=$defs{"Twilight"}} ) }
sub Twilight_WeatherTimerUpdate($) {
  my ($myHash) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  $hash->{SWIP} = 1;
  my $param = Twilight_CreateHttpParameterAndGetData($myHash, "weather");
}
################################################################################
sub Twilight_CreateHttpParameterAndGetData($$) {
  my ($myHash, $mode) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  my $location = $hash->{WEATHER};
  my $verbose  = AttrVal($hash->{NAME}, "verbose", 3 );

  my $URL = "http://query.yahooapis.com/v1/public/yql?q=select%%20*%%20from%%20weather.forecast%%20where%%20woeid=%s%%20and%%20u=%%27c%%27&format=%s&env=store%%3A%%2F%%2Fdatatables.org%%2Falltableswithkeys";
  my $url = sprintf($URL, $location, "json");
  Log3 $hash, 4, "[$hash->{NAME}] url=$url";

  my $param = {
      url        => $url,
      timeout    => defined($hash->{DEFINE}) ? 10 :10,
      hash       => $hash,
      method     => "GET",
      loglevel   => 4-($verbose-3),
      header     => "User-Agent: Mozilla/5.0\r\nAccept: application/xml",
      callback   => \&Twilight_WeatherCallback,
      mode       => $mode };

  if (defined($hash->{DEFINE})) {
    delete $param->{callback};
    my ($err, $result) = HttpUtils_BlockingGet($param);
    Twilight_WeatherCallback($param, $err, $result);
  } else {
    HttpUtils_NonblockingGet($param);
  }

}
################################################################################
sub Twilight_WeatherCallback(@) {
  my ($param, $err, $result) = @_;

  my $hash = $param->{hash};
  return if (!defined($hash));

  if ($err) {
    Log3 $hash, 3, "[$hash->{NAME}] got no weather info from yahoo. Error code: $err";
    $result = undef;
  } else {
     Log3 $hash, 4, "[$hash->{NAME}] got weather info from yahoo for $hash->{WEATHER}";
     Log3 $hash, 5, "[$hash->{NAME}] answer=$result" if defined $result;
  }

  Twilight_getWeatherHorizon($hash, $result);
  #$hash->{CONDITION} = 50;

  if ($hash->{CONDITION} == 50 && $hash->{VERSUCHE} <= 10) {
     $hash->{VERSUCHE} += 1;
     Twilight_RepeatTimerSet($hash, $param->{mode});
     return;
  }

  Twilight_TwilightTimes      ($hash, $param->{mode}, $result);

  Log3 $hash, 3, "[$hash->{NAME}] " . ($hash->{VERSUCHE}+1) . " attempt(s) needed to get valid weather data from yahoo"   if ($hash->{CONDITION} != 50 && $hash->{VERSUCHE} >  0);
  Log3 $hash, 3, "[$hash->{NAME}] " . ($hash->{VERSUCHE}+1) . " attempt(s) needed got NO valid weather data from yahoo"   if ($hash->{CONDITION} == 50 && $hash->{VERSUCHE} >  0);
  $hash->{VERSUCHE} = 0;

  Twilight_StandardTimerSet   ($hash);
}
################################################################################
sub Twilight_RepeatTimerSet($$) {
  my ($hash, $mode) = @_;
  my $midnight = time() + 60;

  myRemoveInternalTimer("Midnight", $hash);
  if ($mode eq "Mid") {
     myInternalTimer   ("Midnight", $midnight, "Twilight_Midnight", $hash, 0);
  } else {
     myInternalTimer   ("Midnight", $midnight, "Twilight_WeatherTimerUpdate", $hash, 0);
  }

}
################################################################################
sub Twilight_StandardTimerSet($) {
  my ($hash) = @_;
  my $midnight = time() - Twilight_midnight_seconds(time()) + 24*3600 + 1;

  myRemoveInternalTimer       ("Midnight", $hash);
  myInternalTimer             ("Midnight", $midnight, "Twilight_Midnight", $hash, 0);
  Twilight_WeatherTimerSet    ($hash);
}
################################################################################
sub Twilight_WeatherTimerSet($) {
  my ($hash) = @_;
  my $now    = time();

  myRemoveInternalTimer    ("weather", $hash);
  foreach my $key ("sr_weather", "ss_weather") {
     my $tim = $hash->{TW}{$key}{TIME};
     if ($tim-60*60>$now+60) {
        myInternalTimer       ("weather", $tim-60*60, "Twilight_WeatherTimerUpdate", $hash, 0);
        last;
     }
  }
}
################################################################################
sub Twilight_sunposTimerSet($) {
  my ($hash) = @_;

  myRemoveInternalTimer       ("sunpos", $hash);
  myInternalTimer             ("sunpos", time()+$hash->{SUNPOS_OFFSET},  "Twilight_sunpos", $hash, 0);

}
################################################################################
sub Twilight_getWeatherHorizon(@)
{
  my ($hash, $result) = @_;

  my $location=$hash->{WEATHER};
  if ($location == 0)  {
     $hash->{WEATHER_HORIZON}="0";
     $hash->{CONDITION}="0";
     return 1;
  }

  my $mod = "[".$hash->{NAME} ."] ";
  my @faktor_cond_code = (10,10,10,10, 9, 7, 7, 7, 7, 7,
                           7, 5, 5, 5, 5, 7, 7, 5, 5, 5,
                           7, 5, 5, 5, 5, 5, 2, 4, 4, 2,
                           2, 0, 0, 0, 0, 5, 0, 8, 8, 8,
                           6, 8, 6, 5, 2, 5, 6, 6, 0, 0,
                           0);

  # condition codes are described in FHEM wiki and in the documentation of the yahoo weather API

  my ($cond_code, $cond_txt, $temperatur, $aktTemp);
  if (defined($result)) {

    # ersetze in result(json) ": durch "=>
    # dadurch entsteht ein Perlausdruck, der direkt geparst werden kann

     my $perlAusdruck = $result;
       #$perlAusdruck = "<h1>could";
        $perlAusdruck =~ s/("[\w ]+")(\s*)(:)/$1=>/g;
        $perlAusdruck =~ s/null/undef/g;
        $perlAusdruck =~ s/true/1/g;
        $perlAusdruck =~ s/false/0/g;
        $perlAusdruck = 'return ' .$perlAusdruck;

     my $anonymSub = eval "sub {$perlAusdruck}";
     Log3 $hash, 3, "[$hash->{NAME}] error $@ parsing $result"   if($@);
     if (!$@) {
        my $resHash = $anonymSub->() if ($anonymSub gt "");
        Log3 $hash, 3, "[$hash->{NAME}] error $@ parsing $result"   if($@);
       #Log3 $hash, 3, "jsonAsPerl". Dumper $resHash->{query}{results}{channel}{item}{condition};
       if (!$@) {

          $cond_code  = $resHash->{query}{results}{channel}{item}{condition}{code};
          $cond_txt   = $resHash->{query}{results}{channel}{item}{condition}{text};
          $temperatur = $resHash->{query}{results}{channel}{item}{condition}{temp};
       }
     }
  }

  # wenn kein Code ermittelt werden kann, wird ein Pseudocode gesetzt
  if (!defined($cond_code) ) {
     $cond_code  = "50";         # eigener neutraler Code
     $cond_txt   = "undefined";
     $temperatur = "undefined";
  } else {
     $hash->{WEATHER_CORRECTION} = $faktor_cond_code[$cond_code] / 25 * 20;
     $hash->{WEATHER_HORIZON}    = $hash->{WEATHER_CORRECTION} + $hash->{INDOOR_HORIZON};
     $hash->{CONDITION}          = $cond_code;
     $hash->{CONDITION_TXT}      = $cond_txt;
     $hash->{TEMPERATUR}         = $temperatur;
     Log3 $hash, 4, "[$hash->{NAME}] $cond_code=$cond_txt $temperatur, correction: $hash->{WEATHER_CORRECTION}°";
  }

  my $doy         = strftime("%j",localtime);
  my $declination =  0.4095*sin(0.016906*($doy-80.086));
  if($hash->{WEATHER_HORIZON} > (89-$hash->{LATITUDE}+$declination) ){
     $hash->{WEATHER_HORIZON} =  89-$hash->{LATITUDE}+$declination;
  }

  return 1;

}
################################################################################
sub Twilight_sunpos($)
{
  my ($myHash) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  my $hashName = $hash->{NAME};

  return "" if(AttrVal($hashName, "disable", undef));

  my $tn = TimeNow();
  my ($dSeconds,$dMinutes,$dHours,$iDay,$iMonth,$iYear,$wday,$yday,$isdst) = gmtime(time);
  $iMonth++;
  $iYear += 100;

  my $dLongitude = $hash->{LONGITUDE};
  my $dLatitude  = $hash->{LATITUDE};
  Log3 $hash, 5, "Compute sunpos for latitude $dLatitude , longitude $dLongitude" if($dHours == 0 && $dMinutes <= 6 );

  my $pi=3.14159265358979323846;
  my $twopi=(2*$pi);
  my $rad=($pi/180);
  my $dEarthMeanRadius=6371.01;       # In km
  my $dAstronomicalUnit=149597890;    # In km

  # Calculate difference in days between the current Julian Day
  # and JD 2451545.0, which is noon 1 January 2000 Universal Time

  # Calculate time of the day in UT decimal hours
  my $dDecimalHours=$dHours + $dMinutes/60.0 + $dSeconds/3600.0;

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

  my $twilight = int(($dElevation+12.0)/18.0 * 1000)/10;
     $twilight = 100 if ($twilight>100);
     $twilight = 0   if ($twilight<  0);

  my $twilight_weather	 ;

  if( (my $ExtWeather = AttrVal($hashName, "useExtWeather", "")) eq "") {
     $twilight_weather = int(($dElevation-$hash->{WEATHER_HORIZON}+12.0)/18.0 * 1000)/10;
	    Log3 $hash, 5, "[$hash->{NAME}] " . "Original weather readings";
  } else {
	   my($extDev,$extReading) = split(":",$ExtWeather);
	   my $extWeatherHorizont = ReadingsVal($extDev,$extReading,-1);
	   if ($extWeatherHorizont >= 0){
		     $extWeatherHorizont = 100 if ($extWeatherHorizont > 100);
		     Log3 $hash, 5, "[$hash->{NAME}] " . "New weather readings from: ".$extDev.":".$extReading.":".$extWeatherHorizont;
		     $twilight_weather = $twilight - int(0.007 * ($extWeatherHorizont ** 2)); ## SCM: 100% clouds => 30% light (rough estimation)
	   } else {
		     $twilight_weather = int(($dElevation-$hash->{WEATHER_HORIZON}+12.0)/18.0 * 1000)/10;
		     Log3 $hash, 3, "[$hash->{NAME}] " . "Error with external readings from: ".$extDev.":".$extReading." , taking original weather readings";
	   }
  }

  $twilight_weather = 100 if ($twilight_weather>100);
  $twilight_weather = 0   if ($twilight_weather<  0);

  #  set readings
  $dAzimuth   = int(100*$dAzimuth  )/100;
  $dElevation = int(100*$dElevation)/100;

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
################################################################################
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

sub twilight($$$$) {
  my ($twilight, $reading, $min, $max) = @_;

  my $t = hms2h(ReadingsVal($twilight,$reading,0));

  $t = hms2h($min) if(defined($min) && (hms2h($min) > $t));
  $t = hms2h($max) if(defined($max) && (hms2h($max) < $t));

  return h2hms_fmt($t);
}

1;

=pod
=item device
=item summary    delivers twilight and other sun related events for use in notify
=item summary_DE liefert Dämmerungs Sonnen basierte Ereignisse, für notify
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
	   The parameter <b>indoor_horizon</b> gives a virtual horizon, that shall be used for calculation of indoor twilight. Minimal value -6 means indoor values are the same like civil values.
	   indoor_horizon 0 means indoor values are the same as real values. indoor_horizon > 0 means earlier indoor sunset resp. later indoor sunrise.
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
    <tr><td><b>light</b></td><td>the current virtual daylight value</td></tr>
    <tr><td><b>nextEvent</b></td><td>the name of the next event</td></tr>
    <tr><td><b>nextEventTime</b></td><td>the time when the next event will probably happen (during light phase 5 and 6 this is updated when weather conditions change</td></tr>
    <tr><td><b>sr_astro</b></td><td>time of astronomical sunrise</td></tr>
    <tr><td><b>sr_naut</b></td><td>time of nautical sunrise</td></tr>
    <tr><td><b>sr_civil</b></td><td>time of civil sunrise</td></tr>
    <tr><td><b>sr</b></td><td>time of sunrise</td></tr>
    <tr><td><b>sr_indoor</b></td><td>time of indoor sunrise</td></tr>
    <tr><td><b>sr_weather</b></td><td>time of weather sunrise</td></tr>
    <tr><td><b>ss_weather</b></td><td>time of weather sunset</td></tr>
    <tr><td><b>ss_indoor</b></td><td>time of indoor sunset</td></tr>
    <tr><td><b>ss</b></td><td>time of sunset</td></tr>
    <tr><td><b>ss_civil</b></td><td>time of civil sunset</td></tr>
    <tr><td><b>ss_nautic</b></td><td>time of nautic sunset</td></tr>
    <tr><td><b>ss_astro</b></td><td>time of astro sunset</td></tr>
    <tr><td><b>azimuth</b></td><td>the current azimuth of the sun 0&deg; ist north 180&deg; is south</td></tr>
    <tr><td><b>compasspoint</b></td><td>a textual representation of the compass point</td></tr>
    <tr><td><b>elevation</b></td><td>the elevaltion of the sun</td></tr>
    <tr><td><b>twilight</b></td><td>a percetal value of a new (twi)light value: (elevation+12)/18 * 100) </td></tr>
    <tr><td><b>twilight_weather</b></td><td>a percetal value of a new (twi)light value: (elevation-WEATHER_HORIZON+12)/18 * 100). So if there is weather, it
                                     is always a little bit darker than by fair weather</td></tr>
    <tr><td><b>condition</b></td><td>the yahoo condition weather code</td></tr>
    <tr><td><b>condition_txt</b></td><td>the yahoo condition weather code as textual representation</td></tr>
    <tr><td><b>horizon</b></td><td>value auf the actual horizon 0&deg;, -6&deg;, -12&deg;, -18&deg;</td></tr>
    </table>

  </ul>
  <br>

  <a name="Twilightattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	<li><b>useExtWeather &lt;device&gt;:&lt;reading&gt;</b></li>
	use data from other devices to calculate <b>twilight_weather</b>.<br/>
	The reading used shoud be in the range of 0 to 100 like the reading <b>c_clouds</b>	in an <b><a href="#openweathermap">openweathermap</a></b> device, where 0 is clear sky and 100 are overcast clouds.<br/>
	With the use of this attribute weather effects like heavy rain or thunderstorms are neglegted for the calculation of the <b>twilight_weather</b> reading.<br/>
  </ul>
  <br>

  <a name="Twilightfunc"></a>
  <b>Functions</b>
  <ul>
     <li><b>twilight</b>(<b>$twilight</b>, <b>$reading</b>, <b>$min</b>, <b>$max</b>)</li> - implements a routine to compute the twilighttimes like sunrise with min max values.<br><br>
     <table>
     <tr><td><b>$twilight</b></td><td>name of the twilight instance</td></tr>
     <tr><td><b>$reading</b></td><td>name of the reading to use example: ss_astro, ss_weather ...</td></tr>
     <tr><td><b>$min</b></td><td>parameter min time - optional</td></tr>
     <tr><td><b>$max</b></td><td>parameter max time - optional</td></tr>
     </table>
  </ul>
  <br>
Example:
<pre>
    define BlindDown at *{twilight("myTwilight","sr_indoor","7:30","9:00")} set xxxx position 100
    # xxxx is a defined blind
</pre>

</ul>

=end html

=begin html_DE

<a name="Twilight"></a>
<h3>Twilight</h3>
<ul>
  <br>

  <a name="Twilightdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Twilight &lt;latitude&gt; &lt;longitude&gt; [&lt;indoor_horizon&gt; [&lt;Weather_Position&gt;]]</code><br>
    <br>
    Erstellt ein virtuelles Device f&uuml;r die D&auml;mmerungsberechnung (Zwielicht)<br><br>

  <b>latitude, longitude (geografische L&auml;nge & Breite)</b>
  <br>
    Die Parameter <b>latitude</b> und <b>longitude</b> sind Dezimalzahlen welche die Position auf der Erde bestimmen, f&uuml;r welche der Dämmerungs-Status berechnet werden soll.
    <br><br>
  <b>indoor_horizon</b>
  <br>
	   Der Parameter <b>indoor_horizon</b> bestimmt einen virtuellen Horizont, der f&uuml;r die Berechnung der D&auml;mmerung innerhalb von R&auml;men genutzt werden kann. Minimalwert ist -6 (ergibt gleichen Wert wie Zivile D&auml;mmerung). Bei 0 fallen
	   indoor- und realer D&aumlmmerungswert zusammen. Werte gr&oumlsser 0 ergeben fr&uumlhere Werte für den Abend bzw. sp&aumltere f&uumlr den Morgen.
    <br><br>
  <b>Weather_Position</b>
  <br>
	   Der Parameter <b>Weather_Position</b> ist die Yahoo! Wetter-ID welche f&uuml;r den Bezug der Wetterinformationen gebraucht wird. Gehe auf http://weather.yahoo.com/ und gebe einen Ort (ggf. PLZ) ein. In der URL der daraufhin geladenen Seite ist an letzter Stelle die ID. Beispiel: München, Deutschland -> 676757
    <br><br>

    Ein Twilight-Device berechnet periodisch die D&auml;mmerungszeiten und -phasen w&auml;hrend des Tages.
    Es berechnet ein virtuelles "Licht"-Element das einen Indikator f&uuml;r die momentane Tageslichtmenge ist.
    Neben der Position auf der Erde wird es vom sog. "indoor horizon" (Beispielsweise hohe Geb&auml;de oder Berge)
    und dem Wetter beeinflusst. Schlechtes Wetter f&uuml;hrt zu einer Reduzierung des Tageslichts f&uuml;r den ganzen Tag.
    Das berechnete Licht liegt zwischen 0 und 6 wobei die Werte folgendes bedeuten:<br><br>
  <b>light</b>
  <br>
	<code>0 - Totale Nacht, die Sonne ist mind. -18 Grad hinter dem Horizont</code><br>
	<code>1 - Astronomische D&auml;mmerung, die Sonne ist zw. -12 und -18 Grad hinter dem Horizont</code><br>
	<code>2 - Nautische D&auml;mmerung, die Sonne ist zw. -6 and -12 Grad hinter dem Horizont</code><br>
	<code>3 - Zivile/B&uuml;rgerliche D&auml;mmerung, die Sonne ist zw. 0 and -6 hinter dem Horizont</code><br>
	<code>4 - "indoor twilight", die Sonne ist zwischen dem Wert indoor_horizon und 0 Grad hinter dem Horizont (wird nicht verwendet wenn indoor_horizon=0)</code><br>
	<code>5 - Wetterbedingte D&auml;mmerung, die Sonne ist zwischen indoor_horizon und einem virtuellen Wetter-Horizonz (der Wetter-Horizont ist Wetterabh&auml;ngig (optional)</code><br>
	<code>6 - Maximales Tageslicht</code><br>
	<br>
 <b>Azimut, Elevation, Twilight (Seitenwinkel, Höhenwinkel, D&auml;mmerung)</b>
 <br>
   Das Modul berechnet zus&auml;tzlich Azimuth und Elevation der Sonne. Diese Werte k&ouml;nnen zur Rolladensteuerung verwendet werden.<br><br>

Das Reading <b>Twilight</b> wird als neuer "(twi)light" Wert hinzugef&uuml;gt. Er wird aus der Elevation der Sonne mit folgender Formel abgeleitet: (Elevation+12)/18 * 100). Das erlaubt eine detailliertere Kontrolle der Lampen w&auml;hrend Sonnenauf - und untergang. Dieser Wert ist zwischen 0% und 100% wenn die Elevation zwischen -12&deg; und 6&deg;

   <br><br>
Wissenswert dazu ist, dass die Sonne, abh&auml;gnig vom Breitengrad, bestimmte Elevationen nicht erreicht. Im Juni und Juli liegt die Sonne in Mitteleuropa nie unter -18&deg;. In n&ouml;rdlicheren Gebieten (Norwegen, ...) kommt die Sonne beispielsweise nicht &uuml;ber 0&deg.
   <br><br>
   All diese Aspekte m&uuml;ssen ber&uuml;cksichtigt werden bei Schaltungen die auf Twilight basieren.
 	<br><br>

	Beispiel:
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
    <tr><td><b>light</b></td><td>der aktuelle virtuelle Tageslicht-Wert</td></tr>
    <tr><td><b>nextEvent</b></td><td>Name des n&auml;chsten Events</td></tr>
    <tr><td><b>nextEventTime</b></td><td>die Zeit wann das n&auml;chste Event wahrscheinlich passieren wird (w&auml;hrend Lichtphase 5 und 6 wird dieser Wert aktualisiert wenn sich das Wetter &auml;ndert)</td></tr>
    <tr><td><b>sr_astro</b></td><td>Zeit des astronomitschen Sonnenaufgangs</td></tr>
    <tr><td><b>sr_naut</b></td><td>Zeit des nautischen Sonnenaufgangs</td></tr>
    <tr><td><b>sr_civil</b></td><td>Zeit des zivilen/b&uuml;rgerlichen Sonnenaufgangs</td></tr>
    <tr><td><b>sr</b></td><td>Zeit des Sonnenaufgangs</td></tr>
    <tr><td><b>sr_indoor</b></td><td>Zeit des "indoor" Sonnenaufgangs</td></tr>
    <tr><td><b>sr_weather</b></td><td>"Wert" des Wetters beim Sonnenaufgang</td></tr>
    <tr><td><b>ss_weather</b></td><td>"Wert" des Wetters beim Sonnenuntergang</td></tr>
    <tr><td><b>ss_indoor</b></td><td>Zeit des "indoor" Sonnenuntergangs</td></tr>
    <tr><td><b>ss</b></td><td>Zeit des Sonnenuntergangs</td></tr>
    <tr><td><b>ss_civil</b></td><td>Zeit des zivilen/b&uuml;rgerlichen Sonnenuntergangs</td></tr>
    <tr><td><b>ss_nautic</b></td><td>Zeit des nautischen Sonnenuntergangs</td></tr>
    <tr><td><b>ss_astro</b></td><td>Zeit des astro. Sonnenuntergangs</td></tr>
    <tr><td><b>azimuth</b></td><td>aktueller Azimuth der Sonne. 0&deg; ist Norden 180&deg; ist S&uuml;den</td></tr>
    <tr><td><b>compasspoint</b></td><td>Ein Wortwert des Kompass-Werts</td></tr>
    <tr><td><b>elevation</b></td><td>the elevaltion of the sun</td></tr>
    <tr><td><b>twilight</b></td><td>Prozentualer Wert eines neuen "(twi)light" Wertes: (elevation+12)/18 * 100) </td></tr>
    <tr><td><b>twilight_weather</b></td><td>Prozentualer Wert eines neuen "(twi)light" Wertes: (elevation-WEATHER_HORIZON+12)/18 * 100). Wenn ein Wetterwert vorhanden ist, ist es immer etwas dunkler als bei klarem Wetter.</td></tr>
    <tr><td><b>condition</b></td><td>Yahoo! Wetter code</td></tr>
    <tr><td><b>condition_txt</b></td><td>Yahoo! Wetter code als Text</td></tr>
    <tr><td><b>horizon</b></td><td>Wert des aktuellen Horizont 0&deg;, -6&deg;, -12&deg;, -18&deg;</td></tr>
    </table>

  </ul>
  <br>

  <a name="Twilightattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	<li><b>useExtWeather &lt;device&gt;:&lt;reading&gt;</b></li>
	Nutzt Daten von einem anderen Device um <b>twilight_weather</b> zu berechnen.<br/>
	Das Reading sollte sich im Intervall zwischen 0 und 100 bewegen, z.B. das Reading <b>c_clouds</b> in einem<b><a href="#openweathermap">openweathermap</a></b> device, bei dem 0 heiteren und 100 bedeckten Himmel bedeuten.
	Wird diese Attribut genutzt , werden Wettereffekte wie Starkregen oder Gewitter fuer die Berechnung von <b>twilight_weather</b> nicht mehr herangezogen.
  </ul>
  <br>

  <a name="Twilightfunc"></a>
  <b>Functions</b>
  <ul>
     <li><b>twilight</b>(<b>$twilight</b>, <b>$reading</b>, <b>$min</b>, <b>$max</b>)</li> - implementiert eine Routine um die D&auml;mmerungszeiten wie Sonnenaufgang mit min und max Werten zu berechnen.<br><br>
     <table>
     <tr><td><b>$twilight</b></td><td>Name der twiligh Instanz</td></tr>
     <tr><td><b>$reading</b></td><td>Name des zu verwendenden Readings. Beispiel: ss_astro, ss_weather ...</td></tr>
     <tr><td><b>$min</b></td><td>Parameter min time - optional</td></tr>
     <tr><td><b>$max</b></td><td>Parameter max time - optional</td></tr>
     </table>
  </ul>
  <br>
Anwendungsbeispiel:
<pre>
    define BlindDown at *{twilight("myTwilight","sr_indoor","7:30","9:00")} set xxxx position 100
    # xxxx ist ein definiertes Rollo
</pre>

</ul>

=end html_DE
=cut
