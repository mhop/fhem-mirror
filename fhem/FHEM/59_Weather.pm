# $Id$
##############################################################################
#
#     59_Weather.pm
#     Copyright by Dr. Boris Neubert
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
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use vars qw($FW_ss);

my %pressure_trend_txt_en = ( 0 => "steady", 1 => "rising", 2 => "falling" );
my %pressure_trend_txt_de = ( 0 => "gleichbleibend", 1 => "steigend", 2 => "fallend" );
my %pressure_trend_txt_nl = ( 0 => "stabiel", 1 => "stijgend", 2 => "dalend" );
my %pressure_trend_txt_fr = ( 0 => "stable", 1 => "croissant", 2 => "décroissant" );
my %pressure_trend_txt_pl = ( 0 => "stabilne", 1 => "rośnie", 2 => "spada" );
my %pressure_trend_txt_it = ( 0 => "stabile", 1 => "in aumento", 2 => "in diminuzione" );
my %pressure_trend_sym = ( 0 => "=", 1 => "+", 2 => "-" );

my @directions_txt_en = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_de = ('N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_nl = ('N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO', 'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_fr = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO');
my @directions_txt_pl = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_it = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO');

my %wdays_txt_en = ('Mon' => 'Mon', 'Tue' => 'Tue', 'Wed'=> 'Wed', 'Thu' => 'Thu', 'Fri' => 'Fri', 'Sat' => 'Sat', 'Sun' => 'Sun');
my %wdays_txt_de = ('Mon' => 'Mo', 'Tue' => 'Di', 'Wed'=> 'Mi', 'Thu' => 'Do', 'Fri' => 'Fr', 'Sat' => 'Sa', 'Sun' => 'So');
my %wdays_txt_nl = ('Mon' => 'Maa', 'Tue' => 'Din', 'Wed'=> 'Woe', 'Thu' => 'Don', 'Fri' => 'Vri', 'Sat' => 'Zat', 'Sun' => 'Zon');
my %wdays_txt_fr= ('Mon' => 'Lun', 'Tue' => 'Mar', 'Wed'=> 'Mer', 'Thu' => 'Jeu', 'Fri' => 'Ven', 'Sat' => 'Sam', 'Sun' => 'Dim');
my %wdays_txt_pl = ('Mon' => 'Pon', 'Tue' => 'Wt', 'Wed'=> 'Śr', 'Thu' => 'Czw', 'Fri' => 'Pt', 'Sat' => 'Sob', 'Sun' => 'Nie');
my %wdays_txt_it = ('Mon' => 'Lun', 'Tue' => 'Mar', 'Wed'=> 'Mer', 'Thu' => 'Gio', 'Fri' => 'Ven', 'Sat' => 'Sab', 'Sun' => 'Dom');

my %status_items_txt_en = ( 0 => "Wind", 1 => "Humidity", 2 => "Temperature", 3 => "Right Now", 4 => "Weather forecast for " );
my %status_items_txt_de = ( 0 => "Wind", 1 => "Feuchtigkeit", 2 => "Temperatur", 3 => "Jetzt Sofort", 4 => "Wettervorhersage für " );
my %status_items_txt_nl = ( 0 => "Wind", 1 => "Vochtigheid", 2 => "Temperatuur", 3 => "Direct", 4 => "Weersvoorspelling voor " );
my %status_items_txt_fr = ( 0 => "Vent", 1 => "Humidité", 2 => "Température", 3 => "Maintenant", 4 => "Prévisions météo pour " );
my %status_items_txt_pl = ( 0 => "Wiatr", 1 => "Wilgotność", 2 => "Temperatura", 3 => "Teraz", 4 => "Prognoza pogody w " );
my %status_items_txt_it = ( 0 => "Vento", 1 => "Umidità", 2 => "Temperatura", 3 => "Adesso", 4 => "Previsioni del tempo per " );

my %wdays_txt_i18n;
my @directions_txt_i18n;
my %pressure_trend_txt_i18n;
my %status_items_txt_i18n;

my @iconlist = (
       'storm', 'storm', 'storm', 'thunderstorm', 'thunderstorm', 'rainsnow',
       'sleet', 'snow', 'drizzle', 'drizzle', 'icy' ,'chance_of_rain',
       'chance_of_rain', 'snowflurries', 'chance_of_snow', 'heavysnow', 'snow', 'sleet',
       'sleet', 'dust', 'fog', 'haze', 'smoke', 'flurries',
       'windy', 'icy', 'cloudy', 'mostlycloudy_night', 'mostlycloudy', 'partly_cloudy_night',
       'partly_cloudy', 'sunny', 'sunny', 'mostly_clear_night', 'mostly_sunny', 'heavyrain',
       'sunny', 'scatteredthunderstorms', 'scatteredthunderstorms', 'scatteredthunderstorms', 'scatteredshowers', 'heavysnow',
       'chance_of_snow', 'heavysnow', 'partly_cloudy', 'heavyrain', 'chance_of_snow', 'scatteredshowers');

###################################
sub Weather_LanguageInitialize($) {

  my ($lang) = @_;

  if($lang eq "de") {
      %wdays_txt_i18n= %wdays_txt_de;
      @directions_txt_i18n= @directions_txt_de;
      %pressure_trend_txt_i18n= %pressure_trend_txt_de;
      %status_items_txt_i18n= %status_items_txt_de;
  } elsif($lang eq "nl") {
      %wdays_txt_i18n= %wdays_txt_nl;
      @directions_txt_i18n= @directions_txt_nl;
      %pressure_trend_txt_i18n= %pressure_trend_txt_nl;
      %status_items_txt_i18n= %status_items_txt_nl;
  } elsif($lang eq "fr") {
      %wdays_txt_i18n= %wdays_txt_fr;
      @directions_txt_i18n= @directions_txt_fr;
      %pressure_trend_txt_i18n= %pressure_trend_txt_fr;
      %status_items_txt_i18n= %status_items_txt_fr;
  } elsif($lang eq "pl") {
      %wdays_txt_i18n= %wdays_txt_pl;
      @directions_txt_i18n= @directions_txt_pl;
      %pressure_trend_txt_i18n= %pressure_trend_txt_pl;
      %status_items_txt_i18n= %status_items_txt_pl;
  } elsif($lang eq "it") {
      %wdays_txt_i18n= %wdays_txt_it;
      @directions_txt_i18n= @directions_txt_it;
      %pressure_trend_txt_i18n= %pressure_trend_txt_it;
      %status_items_txt_i18n= %status_items_txt_it;
  } else {
      %wdays_txt_i18n= %wdays_txt_en;
      @directions_txt_i18n= @directions_txt_en;
      %pressure_trend_txt_i18n= %pressure_trend_txt_en;
      %status_items_txt_i18n= %status_items_txt_en;
  }
}

###################################
sub Weather_DebugCodes($) {

  my ($lang)= @_;
  my @YahooCodes_i18n= YahooWeatherAPI_getYahooCodes($lang);

  Debug "Weather Code List, see http://developer.yahoo.com/weather/#codes";
  for(my $c= 0; $c<= 47; $c++) {
    Debug sprintf("%2d %30s %30s", $c, $iconlist[$c], $YahooCodes_i18n[$c]);
  }

}


#####################################
sub Weather_Initialize($) {

  my ($hash) = @_;

  $hash->{DefFn}   = "Weather_Define";
  $hash->{UndefFn} = "Weather_Undef";
  $hash->{GetFn}   = "Weather_Get";
  $hash->{SetFn}   = "Weather_Set";
  $hash->{AttrList}= "disable " . $readingFnAttributes;
  $hash->{NotifyFn}= "Weather_Notify";

  #Weather_DebugCodes('de');
}

###################################

sub degrees_to_direction($@) {
   my ($degrees,@directions_txt_i18n) = @_;
   my $mod = int((($degrees + 11.25) % 360) / 22.5);
   return $directions_txt_i18n[$mod];
}

###################################
sub Weather_RetrieveData($$) {
    my ($name, $blocking) = @_;
    my $hash = $defs{$name};

    # WOEID [WHERE-ON-EARTH-ID], go to http://weather.yahoo.com to find out
    my $location= $hash->{LOCATION};
    my $units= $hash->{UNITS};

    my %args= (
        woeid => $location,
        format => "json",
        blocking => $blocking,
        callbackFnRef => \&Weather_RetrieveDataFinished,
        hash => $hash,
    );

    # this needs to be finalized to use the APIOPTIONS
    my $maxage= $hash->{fhem}{allowCache} ? 600 : 0; # use cached data if allowed
    $hash->{fhem}{allowCache}= 1;
    YahooWeatherAPI_RetrieveDataWithCache($maxage, \%args);
}


sub Weather_ReturnWithError($$$$$) {
    my ($hash, $doTrigger, $err, $pubDate, $pubDateComment)= @_;
    my $name= $hash->{NAME};

    $hash->{fhem}{allowCache}= 0; # do not use cache on next try

    Log3 $hash, 3, "$name: $err";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastError", $err);
    readingsBulkUpdate($hash, "pubDateComment", $pubDateComment) if(defined($pubDateComment));
    readingsBulkUpdate($hash, "pubDateRemote", $pubDate) if(defined($pubDate));
    readingsBulkUpdate($hash, "validity", "stale");
    readingsEndUpdate($hash, $doTrigger);

    my $next= 60; # $next= $hash->{INTERVAL};
    Weather_RearmTimer($hash, gettimeofday()+$next);

    return;
}

sub Weather_RetrieveDataFinished($$$) {

    my ($argsRef, $err, $response)= @_;

    my $hash= $argsRef->{hash};
    my $name= $hash->{NAME};
    my $doTrigger= $argsRef->{blocking} ? 0 : 1;

    # check for error from retrieving data
    return Weather_ReturnWithError($hash, $doTrigger, $err, undef, undef) if($err);

    # decode JSON data from Weather Channel
    my $data;
    ($err, $data)= YahooWeatherAPI_JSONReturnChannelData($response);
    return Weather_ReturnWithError($hash, $doTrigger, $err, undef, undef) if($err);

    # check if up-to-date
    my ($pubDateComment, $pubDate, $pubDateTs)= YahooWeatherAPI_pubDate($data);
    return Weather_ReturnWithError($hash, $doTrigger, $pubDateComment, $pubDate, $pubDateComment)
        unless(defined($pubDateTs));
    my $ts= defined($hash->{READINGS}{pubDateTs}) ? $hash->{READINGS}{pubDateTs}{VAL} : 0;
    return Weather_ReturnWithError($hash, $doTrigger, "stale data received", $pubDate, $pubDateComment)
        if($ts> $pubDateTs);


    #
    # from here on we assume that $data is complete and correct
    #
    my $lang= $hash->{LANG};

    my @YahooCodes_i18n= YahooWeatherAPI_getYahooCodes($lang);

    my $item= $data->{item};

    readingsBeginUpdate($hash);

    # delete some unused readings
    delete($hash->{READINGS}{temp_f}) if(defined($hash->{READINGS}{temp_f}));
    delete($hash->{READINGS}{unit_distance}) if(defined($hash->{READINGS}{unit_distance}));
    delete($hash->{READINGS}{unit_speed}) if(defined($hash->{READINGS}{unit_speed}));
    delete($hash->{READINGS}{unit_pressuree}) if(defined($hash->{READINGS}{unit_pressuree}));
    delete($hash->{READINGS}{unit_temperature}) if(defined($hash->{READINGS}{unit_temperature}));

    # convert to metric units as far as required
    my $isConverted= YahooWeatherAPI_ConvertChannelData($data);

    # housekeeping information
    readingsBulkUpdate($hash, "lastError", "");
    readingsBulkUpdate($hash, "pubDateComment", $pubDateComment);
    readingsBulkUpdate($hash, "pubDate", $pubDate);
    readingsBulkUpdate($hash, "pubDateRemote", $pubDate);
    readingsBulkUpdate($hash, "pubDateTs", $pubDateTs);
    readingsBulkUpdate($hash, "isConverted", $isConverted);
    readingsBulkUpdate($hash, "validity", "up-to-date");

    # description
    readingsBulkUpdate($hash, "description", $data->{description});

    # location
    readingsBulkUpdate($hash, "city", $data->{location}{city});
    readingsBulkUpdate($hash, "region", $data->{location}{region});
    readingsBulkUpdate($hash, "country", $data->{location}{country});
    readingsBulkUpdate($hash, "lat", $item->{lat});
    readingsBulkUpdate($hash, "long", $item->{long});

    # wind
    my $windspeed= int($data->{wind}{speed}+0.5);
    readingsBulkUpdate($hash, "wind", $windspeed);
    readingsBulkUpdate($hash, "wind_speed", $windspeed);
    readingsBulkUpdate($hash, "wind_chill", $data->{wind}{chill});
    my $winddir= $data->{wind}{direction};
    readingsBulkUpdate($hash, "wind_direction", $winddir);
    my $wdir= degrees_to_direction($winddir, @directions_txt_i18n);
    readingsBulkUpdate($hash, "wind_condition", "Wind: $wdir $windspeed km/h");

    # atmosphere
    my $humidity= $data->{atmosphere}{humidity};
    readingsBulkUpdate($hash, "humidity", $humidity);
    my $pressure= $data->{atmosphere}{pressure};
    readingsBulkUpdate($hash, "pressure", $pressure);
    readingsBulkUpdate($hash, "visibility", int($data->{atmosphere}{visibility}+0.5));
    my $pressure_trend= $data->{atmosphere}{rising};
    readingsBulkUpdate($hash, "pressure_trend", $pressure_trend);
    readingsBulkUpdate($hash, "pressure_trend_txt", $pressure_trend_txt_i18n{$pressure_trend});
    readingsBulkUpdate($hash, "pressure_trend_sym", $pressure_trend_sym{$pressure_trend});

    # condition
    my $date= $item->{condition}{date};
    readingsBulkUpdate($hash, "current_date_time", $date);
    readingsBulkUpdate($hash, "day_of_week", $wdays_txt_i18n{substr($date,0,3)});
    my $code= $item->{condition}{code};
    readingsBulkUpdate($hash, "code", $code);
    readingsBulkUpdate($hash, "condition", $YahooCodes_i18n[$code]);
    readingsBulkUpdate($hash, "icon",  $iconlist[$code]);
    my $temp= $item->{condition}{temp};
    readingsBulkUpdate($hash, "temp_c", $temp);
    readingsBulkUpdate($hash, "temperature", $temp);

    # forecast
    my $forecast= $item->{forecast};
    my $i= 0;
    foreach my $fc (@{$forecast}) {
        $i++;
        my $f= "fc" . $i ."_";
        readingsBulkUpdate($hash, $f . "day_of_week", $wdays_txt_i18n{$fc->{day}});
        readingsBulkUpdate($hash, $f . "date", $fc->{date});
        readingsBulkUpdate($hash, $f . "low_c", $fc->{low});
        readingsBulkUpdate($hash, $f . "high_c", $fc->{high});
        my $fccode= $fc->{code};
        readingsBulkUpdate($hash, $f . "code", $fccode);
        readingsBulkUpdate($hash, $f . "condition",  $YahooCodes_i18n[$fccode]);
        readingsBulkUpdate($hash, $f . "icon",  $iconlist[$fccode]);
    }

    #my $val= "T:$temp°C  " . substr($status_items_txt_i18n{1}, 0, 1) .":$humidity%  " . substr($status_items_txt_i18n{0}, 0, 1) . ":$windspeed km/h  P:$pressure mbar";
    my $val= "T: $temp  H: $humidity  W: $windspeed  P: $pressure";
    Log3 $hash, 4, "$name: $val";
    readingsBulkUpdate($hash, "state", $val);

    readingsEndUpdate($hash, $doTrigger);

    Weather_RearmTimer($hash, gettimeofday()+$hash->{INTERVAL});
    return;

}

###################################
sub Weather_GetUpdate($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};

    if($attr{$name} && $attr{$name}{disable}) {
      Log3 $hash, 5, "Weather $name: retrieval of weather data is disabled by attribute.";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "pubDateComment", "disabled by attribute");
      readingsBulkUpdate($hash, "validity", "stale");
      readingsEndUpdate($hash, 1);
      Weather_RearmTimer($hash, gettimeofday()+$hash->{INTERVAL});
    } else {
      Weather_RetrieveData($name, 0);
    }

    return 1;
}

###################################
sub Weather_Get($@) {

  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
        $value= $hash->{READINGS}{$reading}{VAL};
  } else {
        my $rt= "";
        if(defined($hash->{READINGS})) {
                $rt= join(" ", sort keys %{$hash->{READINGS}});
        }
        return "Unknown reading $reading, choose one of " . $rt;
  }

  return "$a[0] $reading => $value";
}

###################################
sub Weather_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];

  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
    Weather_DisarmTimer($hash);
    Weather_GetUpdate($hash);
    return undef;
  } else {
    return "Unknown argument $cmd, choose one of update";
  }
}

###################################
sub Weather_RearmTimer($$) {

  my ($hash, $t) = @_;
  InternalTimer($t, "Weather_GetUpdate", $hash, 0) ;

}

sub Weather_DisarmTimer($) {

    my ($hash)= @_;
    RemoveInternalTimer($hash);
}

sub Weather_Notify($$) {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  # return if($attr{$name} && $attr{$name}{disable});

  # update weather after initialization or change of configuration
  # wait 10 to 29 seconds to avoid congestion due to concurrent activities
  Weather_DisarmTimer($hash);
  my $delay= 10+int(rand(20));

  #$delay= 3; # delay removed until further notice

  Log3 $hash, 5, "Weather $name: FHEM initialization or rereadcfg triggered update, delay $delay seconds.";
  Weather_RearmTimer($hash, gettimeofday()+$delay) ;

  return undef;
}

#####################################
sub Weather_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Weather <location> [interval]
  # define MyWeather Weather "Maintal,HE" 3600

  # define <name> Weather location=<location> [API=<API>] [interval=<interval>] [lang=<lang>]

  my $name;
  my $API="YahooWeatherAPI,transport:https,cachemaxage:600";
  my $location;
  my $interval  = 3600;
  my $lang      = "en";

  if($def =~ /=/) {

    my $usage= "syntax: define <name> Weather location=<location> [API=<API>] [lang=<lang>]";

    my ($arrayref, $hashref)= parseParams($def);
    my @a= @{$arrayref};
    my %h= %{$hashref};

    return $usage unless(scalar @a == 2);
    $name= $a[0];

    return $usage unless exists $h{location};
    $location= $h{location};
    $lang= $h{lang} if exists $h{lang};
    $interval= $h{interval} if exists $h{interval};
    $API= $h{API} if exists $h{API};

  } else {
    my @a = split("[ \t][ \t]*", $def);

    return "syntax: define <name> Weather <location> [interval [en|de|nl|fr|pl|it]]"
        if(int(@a) < 3 && int(@a) > 5);

    $name      = $a[0];
    $location  = $a[2];
    if(int(@a)>=4) { $interval= $a[3]; }
    if(int(@a)==5) { $lang= $a[4]; }

  }

  my ($api,$apioptions)= split(',', $API, 2);
  $apioptions= "" unless(defined($apioptions));
  eval {
    require "$api.pm";
  };
  return "$name: cannot load API $api: $@" if($@);

  $hash->{NOTIFYDEV} = "global";
  $hash->{STATE} = "Initialized";
  $hash->{fhem}{interfaces}= "temperature;humidity;wind";

  $hash->{LOCATION}     = $location;
  $hash->{INTERVAL}     = $interval;
  $hash->{LANG}         = $lang;
  $hash->{API}          = $api;
  $hash->{APIOPTIONS}   = $apioptions;
  $hash->{UNITS}        = "c"; # hardcoded to use degrees centigrade (Celsius)
  $hash->{READINGS}{current_date_time}{TIME}= TimeNow();
  $hash->{READINGS}{current_date_time}{VAL}= "none";

  $hash->{fhem}{allowCache}= 1;

  Weather_LanguageInitialize($lang);

  Weather_GetUpdate($hash) if($init_done);

  return undef;
}

#####################################
sub Weather_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

#####################################

# Icon Parameter

use constant ICONHIGHT => 120;
use constant ICONWIDTH => 175;
use constant ICONSCALE => 0.5;

#####################################

sub
WeatherIconIMGTag($) {

  my $width= int(ICONSCALE*ICONWIDTH);
  my ($icon)= @_;
  my $url= FW_IconURL("weather/$icon");
  my $style= " width=$width";
  return "<img src=\"$url\"$style alt=\"$icon\">";

}

#####################################

sub
WeatherAsHtmlV($;$)
{

  my ($d,$items) = @_;
  $d = "<none>" if(!$d);
  $items = 10 if( !$items );
  return "$d is not a Weather instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Weather");

  my $width= int(ICONSCALE*ICONWIDTH);

  my $ret = '<table class="weather">';
  $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue">%s<br>%s°C  %s%%<br>%s</td></tr>',
        $width,
        WeatherIconIMGTag(ReadingsVal($d, "icon", "")),
        ReadingsVal($d, "condition", ""),
        ReadingsVal($d, "temp_c", ""), ReadingsVal($d, "humidity", ""),
        ReadingsVal($d, "wind_condition", ""));

  for(my $i=1; $i<$items; $i++) {
    $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: %s</span><br><span class="weatherMin">min %s°C</span> <span class="weatherMax">max %s°C</span></td></tr>',
        $width,
        WeatherIconIMGTag(ReadingsVal($d, "fc${i}_icon", "")),
        ReadingsVal($d, "fc${i}_day_of_week", ""),
        ReadingsVal($d, "fc${i}_condition", ""),
        ReadingsVal($d, "fc${i}_low_c", ""), ReadingsVal($d, "fc${i}_high_c", ""));
  }

  $ret .= "</table>";
  return $ret;
}

sub
WeatherAsHtml($;$)
{
  my ($d,$i) = @_;
  WeatherAsHtmlV($d,$i);
}

sub
WeatherAsHtmlH($;$)
{

  my ($d,$items) = @_;
  $d = "<none>" if(!$d);
  $items = 10 if( !$items );
  return "$d is not a Weather instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Weather");

  my $width= int(ICONSCALE*ICONWIDTH);



  my $format= '<td><table border=1><tr><td class="weatherIcon" width=%d>%s</td></tr><tr><td class="weatherValue">%s</td></tr><tr><td class="weatherValue">%s°C %s%%</td></tr><tr><td class="weatherValue">%s</td></tr></table></td>';

  my $ret = '<table class="weather">';

  # icons
  $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td>', $width, WeatherIconIMGTag(ReadingsVal($d, "icon", "")));
  for(my $i=1; $i<$items; $i++) {
    $ret .= sprintf('<td class="weatherIcon" width=%d>%s</td>', $width, WeatherIconIMGTag(ReadingsVal($d, "fc${i}_icon", "")));
  }
  $ret .= '</tr>';

  # condition
  $ret .= sprintf('<tr><td class="weatherDay">%s</td>', ReadingsVal($d, "condition", ""));
  for(my $i=1; $i<$items; $i++) {
    $ret .= sprintf('<td class="weatherDay">%s: %s</td>', ReadingsVal($d, "fc${i}_day_of_week", ""),
        ReadingsVal($d, "fc${i}_condition", ""));
  }
  $ret .= '</tr>';

  # temp/hum | min
  $ret .= sprintf('<tr><td class="weatherMin">%s°C %s%%</td>', ReadingsVal($d, "temp_c", ""), ReadingsVal($d, "humidity", ""));
  for(my $i=1; $i<$items; $i++) {
    $ret .= sprintf('<td class="weatherMin">min %s°C</td>', ReadingsVal($d, "fc${i}_low_c", ""));
  }
  $ret .= '</tr>';

  # wind | max
  $ret .= sprintf('<tr><td class="weatherMax">%s</td>', ReadingsVal($d, "wind_condition", ""));
  for(my $i=1; $i<$items; $i++) {
    $ret .= sprintf('<td class="weatherMax">max %s°C</td>', ReadingsVal($d, "fc${i}_high_c", ""));
  }
  $ret .= "</tr></table>";

  return $ret;
}

sub
WeatherAsHtmlD($;$)
{
  my ($d,$i) = @_;
  if($FW_ss) {
    WeatherAsHtmlV($d,$i);
  } else {
    WeatherAsHtmlH($d,$i);
  }
}

#####################################


1;

=pod
=item device
=item summary provides current weather condition and forecast (source: Yahoo Weather API)
=item summary_DE stellt Wetterbericht und -vorhersage bereit (Quelle: Yahoo Weather API)
=begin html

<a name="Weather"></a>
<h3>Weather</h3>
<ul>
  You need the JSON perl module. Use <code>apt-get install libjson-perl</code> on Debian and derivatives.<br><br>

  <a name="Weatherdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Weather &lt;location&gt; [&lt;interval&gt; [&lt;language&gt;]]</code><br>
    <br>
    Defines a virtual device for weather forecasts.<br><br>

    A Weather device periodically gathers current and forecast weather conditions
    from the Yahoo Weather API.<br><br>

    The parameter <code>location</code> is the WOEID (WHERE-ON-EARTH-ID), go to
    <a href="http://weather.yahoo.com">http://weather.yahoo.com</a> to find it out for your location.<br><br>

    The optional parameter <code>interval</code> is the time between subsequent updates
    in seconds. It defaults to 3600 (1 hour).<br><br>

    The optional language parameter may be one of
    <code>de</code>,
    <code>en</code>,
    <code>pl</code>,
    <code>fr</code>,
    <code>nl</code>,
    <code>it</code>,

    It determines the natural language in which the forecast information appears.
    It defaults to <code>en</code>. If you want to set the language you also have to set the interval.<br><br>

    Examples:
    <pre>
      define MyWeather Weather 673513
      define Forecast Weather 673513 1800
     </pre>

    The module provides four additional functions <code>WeatherAsHtml</code>, <code>WeatherAsHtmlV</code>, <code>WeatherAsHtmlH</code> and
    <code>WeatherAsHtmlD</code>. The former two functions are identical: they return the HTML code for a
    vertically arranged weather forecast. The third function returns the HTML code for a horizontally arranged weather forecast. The
    latter function dynamically picks the orientation depending on wether a smallscreen style is set (vertical layout) or not (horizontal layout). Each version accepts an additional paramter to limit the numer of icons to display.<br><br>
    Example:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather") }
    </pre>


  </ul>
  <br>

  <a name="Weatherset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; update</code><br><br>

    Forces the retrieval of the weather data. The next automatic retrieval is scheduled to occur
    <code>interval</code> seconds later.<br><br>
  </ul>
  <br>

  <a name="Weatherget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    Valid readings and their meaning (? can be one of 1, 2, 3, 4, 5 and stands
    for today, tomorrow, etc.):<br>
    <table>
    <tr><td>city</td><td>name of town returned for location</td></tr>
    <tr><td>code</td><td>current condition code</td></tr>
    <tr><td>condition</td><td>current condition</td></tr>
    <tr><td>current_date_time</td><td>last update of forecast on server</td></tr>
    <tr><td>fc?_code</td><td>forecast condition code</td></tr>
    <tr><td>fc?_condition</td><td>forecast condition</td></tr>
    <tr><td>fc?_day_of_week</td><td>day of week for day +?</td></tr>
    <tr><td>fc?_high_c</td><td>forecasted daily high in degrees centigrade</td></tr>
    <tr><td>fc?_icon</td><td>forecast icon</td></tr>
    <tr><td>fc?_low_c</td><td>forecasted daily low in degrees centigrade</td></tr>
    <tr><td>humidity</td><td>current humidity in %</td></tr>
    <tr><td>icon</td><td>relative path for current icon</td></tr>
    <tr><td>pressure</td><td>air pressure in hPa</td></tr>
    <tr><td>pressure_trend</td><td>air pressure trend (0= steady, 1= rising, 2= falling)</td></tr>
    <tr><td>pressure_trend_txt</td><td>textual representation of air pressure trend</td></tr>
    <tr><td>pressure_trend_sym</td><td>symbolic representation of air pressure trend</td></tr>
    <tr><td>temperature</td><td>current temperature in degrees centigrade</td></tr>
    <tr><td>temp_c</td><td>current temperature in degrees centigrade</td></tr>
    <tr><td>temp_f</td><td>current temperature in degrees Fahrenheit</td></tr>
    <tr><td>visibility</td><td>visibility in km</td></tr>
    <tr><td>wind</td><td>wind speed in km/h</td></tr>
    <tr><td>wind_chill</td><td>wind chill in degrees centigrade</td></tr>
    <tr><td>wind_condition</td><td>wind direction and speed</td></tr>
    <tr><td>wind_direction</td><td>direction wind comes from in degrees (0 = north wind)</td></tr>
    <tr><td>wind_speed</td><td>same as wind</td></tr>
    </table>
    <br>
    The following readings help to identify whether a workaround has kicked in to avoid the retrieval of
    stale data from the remote server:
    <table>
    <tr><td>pubDate</td><td>publication time of forecast for current set of readings</td></tr>
    <tr><td>pubDateRemote</td><td>publication time of forecast as seen on remote server</td></tr>
    <tr><td>validity</td><td>stale, if publication time as seen on remote server is before that of current set of readings</td></tr>
    </table>

  </ul>
  <br>

  <a name="Weatherattr"></a>
  <b>Attributes</b>
  <ul>
    <li>disable: disables the retrieval of weather data - the timer runs according to schedule,
    though no data is requested from the API.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="Weather"></a>
<h3>Weather</h3>
<ul>
    Es wird das Perl-Modul JSON ben&ouml;tigt. Mit <code>apt-get install libjson-perl</code> kann es unter Debian und Derivaten installiert werden.<br><br>

  <a name="Weatherdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Weather &lt;location&gt; [&lt;interval&gt; [&lt;language&gt;]]</code><br>
    <br>
    Bezechnet ein virtuelles Gerät für Wettervorhersagen.<br><br>

    Eine solche virtuelle Wetterstation sammelt periodisch aktuelle und zukünftige Wetterdaten aus der Yahoo-Wetter-API.<br><br>

    Der Parameter <code>location</code> entspricht der sechsstelligen WOEID (WHERE-ON-EARTH-ID). Die WOEID für den eigenen Standort kann auf <a href="http://weather.yahoo.com">http://weather.yahoo.com</a> gefunden werden.<br><br>

    Der optionale Parameter  <code>interval</code> gibt die Dauer in Sekunden zwischen den einzelnen Aktualisierungen der Wetterdaten an. Der Standardwert ist 3600 (1 Stunde). Wird kein Wert angegeben, gilt der Standardwert.<br><br>

    Der optionale Parameter für die möglichen Sprachen darf einen der folgende Werte annehmen: <code>de</code>, <code>en</code>, <code>pl</code>, <code>fr</code> oder <code>nl</code>. Er bezeichnet die natürliche Sprache, in der die Wetterinformationen dargestellt werden. Der Standardwert ist <code>en</code>. Wird für die Sprache kein Wert angegeben, gilt der Standardwert. Wird allerdings der Parameter für die Sprache gesetzt, muss ebenfalls ein Wert für das Abfrageintervall gesetzt werden.<br><br>


    Beispiele:
    <pre>
      define MyWeather Weather 673513
      define Forecast Weather 673513 1800
     </pre>

    Das Modul unterstützt zusätzlich vier verschiedene Funktionen <code>WeatherAsHtml</code>, <code>WeatherAsHtmlV</code>, <code>WeatherAsHtmlH</code> und <code>WeatherAsHtmlD</code>. Die ersten beiden Funktionen sind identisch: sie erzeugen den HTML-Code für eine vertikale Darstellung des Wetterberichtes. Die dritte Funktion liefert den HTML-Code für eine horizontale Darstellung des Wetterberichtes. Die letztgenannte Funktion wählt automatisch eine Ausrichtung, die abhängig davon ist, ob ein Smallcreen Style ausgewählt ist (vertikale Darstellung) oder nicht (horizontale Darstellung). Alle vier Funnktionen akzeptieren einen zusätzlichen optionalen Paramter um die Anzahl der darzustellenden Icons anzugeben.<br><br>
    Beispiel:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather") }
    </pre>


  </ul>
  <br>

  <a name="Weatherset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; update</code><br><br>

    Erzwingt eine Abfrage der Wetterdaten. Die darauffolgende Abfrage wird gemäß dem eingestellten Intervall <code>interval</code> Sekunden später durchgeführt.<br><br>
  </ul>
  <br>

  <a name="Weatherget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    Gültige ausgelesene Daten (readings) und ihre Bedeutung (das ? kann einen der Werte 1, 2, 3 , 4 oder 5 annehmen und steht für heute, morgen, übermorgen etc.):<br><br>
    <table>
    <tr><td>city</td><td>Name der Stadt, der aufgrund der WOEID übermittelt wird</td></tr>
    <tr><td>code</td><td>Code für die aktuellen Wetterverhältnisse</td></tr>
    <tr><td>condition</td><td>aktuelle Wetterverhältnisse</td></tr>
    <tr><td>current_date_time</td><td>Zeitstempel der letzten Aktualisierung der Wetterdaten vom Server</td></tr>
    <tr><td>fc?_code</td><td>Code für die vorhergesagten Wetterverhältnisse</td></tr>
    <tr><td>fc?_condition</td><td>vorhergesagte Wetterverhältnisse</td></tr>
    <tr><td>fc?_day_of_week</td><td>Wochentag des Tages, der durch ? dargestellt wird</td></tr>
    <tr><td>fc?_high_c</td><td>vorhergesagte maximale Tagestemperatur in Grad Celsius</td></tr>
    <tr><td>fc?_icon</td><td>Icon für Vorhersage</td></tr>
    <tr><td>fc?_low_c</td><td>vorhergesagte niedrigste Tagestemperatur in Grad Celsius</td></tr>
    <tr><td>humidity</td><td>gegenwärtige Luftfeuchtgkeit in %</td></tr>
    <tr><td>icon</td><td>relativer Pfad für das aktuelle Icon</td></tr>
    <tr><td>pressure</td><td>Luftdruck in hPa</td></tr>
    <tr><td>pressure_trend</td><td>Luftdrucktendenz (0= gleichbleibend, 1= steigend, 2= fallend)</td></tr>
    <tr><td>pressure_trend_txt</td><td>textliche Darstellung der Luftdrucktendenz</td></tr>
    <tr><td>pressure_trend_sym</td><td>symbolische Darstellung der Luftdrucktendenz</td></tr>
    <tr><td>temperature</td><td>gegenwärtige Temperatur in Grad Celsius</td></tr>
    <tr><td>temp_c</td><td>gegenwärtige Temperatur in Grad Celsius</td></tr>
    <tr><td>temp_f</td><td>gegenwärtige Temperatur in Grad Celsius</td></tr>
    <tr><td>visibility</td><td>Sichtweite in km</td></tr>
    <tr><td>wind</td><td>Windgeschwindigkeit in km/h</td></tr>
    <tr><td>wind_chill</td><td>gefühlte Temperatur in Grad Celsius</td></tr>
    <tr><td>wind_condition</td><td>Windrichtung und -geschwindigkeit</td></tr>
    <tr><td>wind_direction</td><td>Gradangabe der Windrichtung (0 = Nordwind)</td></tr>
    <tr><td>wind_speed</td><td>Windgeschwindigkeit in km/h (mit wind identisch)</td></tr>
    </table>
    <br>
    Die folgenden Daten helfen zu identifizieren, ob ein Workaround angeschlagen hat, der die Verwendung von
    veralteten Daten auf dem entfernten Server verhindert:
    <table>
    <tr><td>pubDate</td><td>Ver&ouml;ffentlichungszeitpunkt der Wettervorhersage in den aktuellen Daten (readings)</td></tr>
    <tr><td>pubDateRemote</td><td>Ver&ouml;ffentlichungszeitpunkt der Wettervorhersage auf dem entfernten Server</td></tr>
    <tr><td>validity</td><td>stale, wenn der Ver&ouml;ffentlichungszeitpunkt auf dem entfernten Server vor dem Zeitpunkt der aktuellen Daten (readings) liegt</td></tr>
    </table>

  </ul>
  <br>

  <a name="Weatherattr"></a>
  <b>Attribute</b>
  <ul>
    <li>disable: stellt die Abfrage der Wetterdaten ab - der Timer l&auml;ft gem&auml;&szlig Plan doch es werden keine Daten vom
    API angefordert.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
