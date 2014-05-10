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

#
# uses the Yahoo! Weather API: http://developer.yahoo.com/weather/
#


# Mapping / translation of current weather codes 0-47
my @YahooCodes_en = (
       'tornado', 'tropical storm', 'hurricane', 'severe thunderstorms', 'thunderstorms', 'mixed rain and snow',
       'mixed rain and sleet', 'mixed snow and sleet', 'freezing drizzle', 'drizzle', 'freezing rain' ,'showers',
       'showers', 'snow flurries', 'light snow showers', 'blowing snow', 'snow', 'hail',
       'sleet', 'dust', 'foggy', 'haze', 'smoky', 'blustery',
       'windy', 'cold', 'cloudy',
       'mostly cloudy', # night
       'mostly cloudy', # day
       'partly cloudy', # night
       'partly cloudy', # day
       'clear', #night
       'sunny',
       'fair', #night
       'fair', #day
       'mixed rain and hail',
       'hot', 'isolated thunderstorms', 'scattered thunderstorms', 'scattered thunderstorms', 'scattered showers', 'heavy snow',
       'scattered snow showers', 'heavy snow', 'partly cloudy', 'thundershowers', 'snow showers', 'isolated thundershowers');

my @YahooCodes_de = (
       'Tornado', 'schwerer Sturm', 'Orkan', 'schwere Gewitter', 'Gewitter', 'Regen und Schnee',
       'Regen und Graupel', 'Schnee und Graupel', 'Eisregen', 'Nieselregen', 'gefrierender Regen' ,'Schauer',
       'Schauer', 'Schneetreiben', 'leichte Schneeschauer', 'Schneeverwehungen', 'Schnee', 'Hagel',
       'Graupel', 'Staub', 'Nebel', 'Dunst', 'Smog', 'Sturm',
       'windig', 'kalt', 'wolkig',
       'überwiegend wolkig', # night
       'überwiegend wolkig', # day
       'teilweise wolkig', # night
       'teilweise wolkig', # day
       'klar', # night
       'sonnig',
       'heiter', # night
       'heiter', # day
       'Regen und Hagel',
       'heiß', 'einzelne Gewitter', 'vereinzelt Gewitter', 'vereinzelt Gewitter', 'vereinzelt Schauer', 'starker Schneefall',
       'vereinzelt Schneeschauer', 'starker Schneefall', 'teilweise wolkig', 'Gewitterregen', 'Schneeschauer', 'vereinzelt Gewitter');

my @YahooCodes_nl = (
       'tornado', 'zware storm', 'orkaan', 'hevig onweer', 'onweer',
       'regen en sneeuw',
       'regen en ijzel', 'sneeuw en ijzel', 'aanvriezende motregen',
       'motregen', 'aanvriezende regen' ,'buien',
       'buien', 'sneeuw windstoten', 'lichte sneeuwbuien',
       'stuifsneeuw', 'sneeuw', 'hagel',
       'ijzel', 'stof', 'mist', 'waas', 'smog', 'heftig',
       'winderig', 'koud', 'bewolkt',
       'overwegend bewolkt', # night
       'overwegend bewolkt', # day
       'gedeeltelijk bewolkt', # night
       'gedeeltelijk bewolkt', # day
       'helder', #night
       'zonnig',
       'mooi', #night
       'mooi', #day
       'regen en hagel',
       'heet', 'plaatselijk onweer', 'af en toe onweer', 'af en toe onweer', 'af en toe regenbuien', 'hevige sneeuwval',
       'af en toe sneeuwbuien', 'hevige sneeuwval', 'deels bewolkt',
       'onweersbuien', 'sneeuwbuien', 'af en toe onweersbuien');


my %pressure_trend_txt_en = ( 0 => "steady", 1 => "rising", 2 => "falling" );
my %pressure_trend_txt_de = ( 0 => "gleichbleibend", 1 => "steigend", 2 => "fallend" );
my %pressure_trend_txt_nl = ( 0 => "stabiel", 1 => "stijgend", 2 => "dalend" );
my %pressure_trend_sym = ( 0 => "=", 1 => "+", 2 => "-" );


my @directions_txt_en = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_de = ('N', 'NNO', 'NO', 'ONO', 'O', 'OSO', 'SO', 'SSO', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
my @directions_txt_nl = ('N', 'NNO', 'NO', 'ONO', 'O', 'OZO', 'ZO', 'ZZO', 'Z', 'ZZW', 'ZW', 'WZW', 'W', 'WNW', 'NW', 'NNW');

my %wdays_txt_en = ('Mon' => 'Mon', 'Tue' => 'Tue', 'Wed'=> 'Wed', 'Thu' => 'Thu', 'Fri' => 'Fri', 'Sat' => 'Sat', 'Sun' => 'Sun');
my %wdays_txt_de = ('Mon' => 'Mo', 'Tue' => 'Di', 'Wed'=> 'Mi', 'Thu' => 'Do', 'Fri' => 'Fr', 'Sat' => 'Sa', 'Sun' => 'So');
my %wdays_txt_nl = ('Mon' => 'Maa', 'Tue' => 'Din', 'Wed'=> 'Woe', 'Thu' => 'Don', 'Fri' => 'Vri', 'Sat' => 'Zat', 'Sun' => 'Zon');

my @iconlist = (
       'storm', 'storm', 'storm', 'thunderstorm', 'thunderstorm', 'rainsnow',
       'sleet', 'snow', 'drizzle', 'drizzle', 'icy' ,'chance_of_rain',
       'chance_of_rain', 'snowflurries', 'chance_of_snow', 'heavysnow', 'snow', 'sleet',
       'sleet', 'dust', 'fog', 'haze', 'smoke', 'flurries',
       'windy', 'icy', 'cloudy', 'mostlycloudy_night', 'mostlycloudy', 'partly_cloudy_night',
       'partly_cloudy', 'clear', 'sunny', 'mostly_clear_night', 'clear', 'heavyrain',
       'clear', 'scatteredthunderstorms', 'scatteredthunderstorms', 'scatteredthunderstorms', 'scatteredshowers', 'heavysnow',
       'chance_of_snow', 'heavysnow', 'partly_cloudy', 'heavyrain', 'chance_of_snow', 'scatteredshowers');

###################################
sub Weather_DebugCodes() {

  Debug "Weather Code List, see http://developer.yahoo.com/weather/#codes";
  for(my $c= 0; $c<= 47; $c++) {
    Debug sprintf("%2d %30s %30s %30s %30s", $c, $iconlist[$c], $YahooCodes_en[$c], $YahooCodes_de[$c], $YahooCodes_nl[$c]);
  }

}


#####################################
sub Weather_Initialize($) {

  my ($hash) = @_;

  $hash->{DefFn}   = "Weather_Define";
  $hash->{UndefFn} = "Weather_Undef";
  $hash->{GetFn}   = "Weather_Get";
  $hash->{SetFn}   = "Weather_Set";
  $hash->{AttrList}= "localicons ".
                      $readingFnAttributes;

  #Weather_DebugCodes();                    
}

###################################
sub latin1_to_utf8($) {

  # http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
  my ($s)= @_;
  $s =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
  return $s;
}

###################################

sub temperature_in_c($$) {
  my ($temperature, $unitsystem)= @_;
  return $unitsystem ne "SI" ? int(($temperature-32)*5/9+0.5) : $temperature;
}

sub wind_in_km_per_h($$) {
  my ($wind, $unitsystem)= @_;
  return $unitsystem ne "SI" ? int(1.609344*$wind+0.5) : $wind;
}

sub degrees_to_direction($@) {
   my ($degrees,@directions_txt_i18n) = @_;
   my $mod = int((($degrees + 11.25) % 360) / 22.5);
   return $directions_txt_i18n[$mod];
}

###################################
sub Weather_UpdateReading($$$$) {

  my ($hash,$prefix,$key,$value)= @_;

  #Debug "DEBUG WEATHER: $prefix $key $value";

  my $unitsystem= $hash->{READINGS}{unit_system}{VAL};
  
  if($key eq "low") {
        $key= "low_c";
        $value= temperature_in_c($value,$unitsystem);
  } elsif($key eq "high") {
        $key= "high_c";
        $value= temperature_in_c($value,$unitsystem);
  } elsif($key eq "humidity") {
        # standardize reading - allow generic logging of humidity.
        $value=~ s/.*?(\d+).*/$1/; # extract numeric
  }

  my $reading= $prefix . $key;

  readingsBulkUpdate($hash,$reading,$value);
  if($reading eq "temp_c") {
    readingsBulkUpdate($hash,"temperature",$value); # additional entry for compatibility
  }
  if($reading eq "wind_condition") {
    $value=~ s/.*?(\d+).*/$1/; # extract numeric
    readingsBulkUpdate($hash,"wind",wind_in_km_per_h($value,$unitsystem)); # additional entry for compatibility
  }

  return 1;
}


################################### 
sub Weather_RetrieveData($)
{
  my ($hash)= @_;
  
  my $location= $hash->{LOCATION}; # WOEID [WHERE-ON-EARTH-ID], go to http://weather.yahoo.com to find out
  my $units= $hash->{UNITS}; 

  my $fc = undef;
  my $xml = GetFileFromURL("http://weather.yahooapis.com/forecastrss?w=" . $location . "&u=" . $units, 3, undef, 1);
  return 0 if( ! defined $xml || $xml eq "");

  my $lang= $hash->{LANG};
  my @YahooCodes_i18n;
  my %wdays_txt_i18n;
  my @directions_txt_i18n;
  my %pressure_trend_txt_i18n;

  if($lang eq "de") {
    @YahooCodes_i18n= @YahooCodes_de;
    %wdays_txt_i18n= %wdays_txt_de;
    @directions_txt_i18n= @directions_txt_de;
    %pressure_trend_txt_i18n= %pressure_trend_txt_de;
  } elsif($lang eq "nl") {
    @YahooCodes_i18n= @YahooCodes_nl;
    %wdays_txt_i18n= %wdays_txt_nl;
    @directions_txt_i18n= @directions_txt_nl;
    %pressure_trend_txt_i18n= %pressure_trend_txt_nl;
  } else {
    @YahooCodes_i18n= @YahooCodes_en;
    %wdays_txt_i18n= %wdays_txt_en;
    @directions_txt_i18n= @directions_txt_en;
    %pressure_trend_txt_i18n= %pressure_trend_txt_en;
  }


  foreach my $l (split("<",$xml)) {
          #Debug "DEBUG WEATHER: line=\"$l\"";
          next if($l eq "");                   # skip empty lines
          $l =~ s/(\/|\?)?>$//;                # strip off /> and >
          my ($tag,$value)= split(" ", $l, 2); # split tag data=..... at the first blank
          next if(!defined($tag) || ($tag !~ /^yweather:/));
          $fc= 0 if($tag eq "yweather:condition");
          $fc++ if($tag eq "yweather:forecast");
          my $prefix= $fc ? "fc" . $fc ."_" : "";
  
          ### location
          if ($tag eq "yweather:location" ) {
            $value =~/city="(.*?)" .*country="(.*?)".*/;
            my $loc = "";
            $loc = $1 if (defined($1)); 
            $loc .= ", $2" if (defined($2)); 
            readingsBulkUpdate($hash, "city", $loc);
          }
        
          ### current condition and forecast
          if (($tag eq "yweather:condition" ) || ($tag eq "yweather:forecast" )) {
             my $code = (($value =~/code="([0-9]*?)".*/) ? $1 : undef);
             if(defined($code)) {
               readingsBulkUpdate($hash, $prefix . "code", $code);
               my $text = $YahooCodes_i18n[$code];
               if ($text) { readingsBulkUpdate($hash, $prefix . "condition", $text); }
               #### add icon logic here - generate from code
               $text = $iconlist[$code];
               readingsBulkUpdate($hash, $prefix . "icon", $text) if ($text);
             }  
          }

          ### current condition 
          if ($tag eq "yweather:condition" ) {
             my $temp = (($value =~/temp="(-?[0-9.]*?)".*/) ? $1 : undef);
             if(defined($temp)) {
                readingsBulkUpdate($hash, "temperature", $temp);
                readingsBulkUpdate($hash, "temp_c", $temp); # compatibility
                $temp = int(( $temp * 9  / 5 ) + 32.5);  # Celsius to Fahrenheit
                readingsBulkUpdate($hash, "temp_f", $temp); # compatibility
             }  

             my $datum = (($value =~/date=".*? ([0-9].*)".*/) ? $1 : undef);  
             readingsBulkUpdate($hash, "current_date_time", $datum) if (defined($1));

             my $day = (($value =~/date="(.*?), .*/) ? $1 : undef);  
             if(defined($day)) {
                readingsBulkUpdate($hash, "day_of_week", $wdays_txt_i18n{$day});
             }          
          }

          ### forecast 
          if ($tag eq "yweather:forecast" ) {
             my $low_c = (($value =~/low="(-?[0-9.]*?)".*/) ? $1 : undef);
             if(defined($low_c)) { readingsBulkUpdate($hash, $prefix . "low_c", $low_c); }
             my $high_c = (($value =~/high="(-?[0-9.]*?)".*/) ? $1 : undef);
             if(defined($high_c)) { readingsBulkUpdate($hash, $prefix . "high_c", $high_c); }
             my $day1 = (($value =~/day="(.*?)" .*/) ? $1 : undef); # forecast
             if(defined($day1)) {
                readingsBulkUpdate($hash, $prefix . "day_of_week", $wdays_txt_i18n{$day1});
             }   
          }

          ### humidiy / Pressure
          if ($tag eq "yweather:atmosphere" ) {
            $value =~/humidity="([0-9.]*?)" .*visibility="([0-9.]*?|\s*?)" .*pressure="([0-9.]*?)"  .*rising="([0-9.]*?)" .*/;

            if ($1) { readingsBulkUpdate($hash, "humidity", $1); }
            my $vis = (($2 eq "") ? " " : int($2+0.5));   # clear visibility field
            readingsBulkUpdate($hash, "visibility", $vis);
            if ($3) { readingsBulkUpdate($hash, "pressure", int($3+0.5)); }
            if ($4) {
              readingsBulkUpdate($hash, "pressure_trend", $4);
              readingsBulkUpdate($hash, "pressure_trend_txt", $pressure_trend_txt_i18n{$4});
              readingsBulkUpdate($hash, "pressure_trend_sym", $pressure_trend_sym{$4});
            }
          }

          ### wind
          if ($tag eq "yweather:wind" ) {
            $value =~/chill="(-?[0-9.]*?)" .*direction="([0-9.]*?)" .*speed="([0-9.]*?)" .*/;
            readingsBulkUpdate($hash, "wind_chill", $1) if (defined($1));
            readingsBulkUpdate($hash, "wind_direction", $2) if (defined($2));
            my $windspeed= defined($3) ? int($3+0.5) : "";
            readingsBulkUpdate($hash, "wind_speed", $windspeed);
            readingsBulkUpdate($hash, "wind", $windspeed); # duplicate for compatibility
            if (defined($2) & defined($3)) {
              my $wdir = degrees_to_direction($2,@directions_txt_i18n);
              readingsBulkUpdate($hash, "wind_condition", "Wind: $wdir $windspeed km/h"); # compatibility
            }
          }   
  }
}  #end sub



###################################
sub Weather_GetUpdate($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Weather_GetUpdate", $hash, 1);
  }

  readingsBeginUpdate($hash);

  Weather_RetrieveData($hash);

  my $temperature= $hash->{READINGS}{temperature}{VAL};
  my $humidity= $hash->{READINGS}{humidity}{VAL};
  my $wind= $hash->{READINGS}{wind}{VAL};
  my $val= "T: $temperature  H: $humidity  W: $wind";
  Log3 $hash, 4, "Weather ". $hash->{NAME} . ": $val";
  readingsBulkUpdate($hash, "state", $val);
  readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1)); # DoTrigger, because sub is called by a timer instead of dispatch
      
  return 1;
}

# Perl Special: { $defs{Weather}{READINGS}{condition}{VAL} }
# conditions: Mostly Cloudy, Overcast, Clear, Chance of Rain

###################################
sub Weather_Get($@) {

  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  $hash->{LOCAL} = 1;
  Weather_GetUpdate($hash);
  delete $hash->{LOCAL};

  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
        $value= $hash->{READINGS}{$reading}{VAL};
  } else {
        return "no such reading: $reading";
  }

  return "$a[0] $reading => $value";
}

###################################

sub Weather_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];

  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
    RemoveInternalTimer($hash);
    Weather_GetUpdate($hash);
    return undef;
  } else {
    return "Unknown argument $cmd, choose one of update";
  }
}


#####################################
sub Weather_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Weather <location> [interval]
  # define MyWeather Weather "Maintal,HE" 3600

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Weather <location> [interval [en|de|nl]]"
    if(int(@a) < 3 && int(@a) > 5); 

  $hash->{STATE} = "Initialized";
  $hash->{fhem}{interfaces}= "temperature;humidity;wind";

  my $name      = $a[0];
  my $location  = $a[2];
  my $interval  = 3600;
  my $lang      = "en"; 
  if(int(@a)>=4) { $interval= $a[3]; }
  if(int(@a)==5) { $lang= $a[4]; } 

  $hash->{LOCATION}     = $location;
  $hash->{INTERVAL}     = $interval;
  $hash->{LANG}         = $lang;
  $hash->{UNITS}        = "c"; # hardcoded to use degrees centigrade (Celsius)
  $hash->{READINGS}{current_date_time}{TIME}= TimeNow();
  $hash->{READINGS}{current_date_time}{VAL}= "none";

  $hash->{LOCAL} = 1;
  Weather_GetUpdate($hash);
  delete $hash->{LOCAL};

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Weather_GetUpdate", $hash, 0);

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
  $items = 6 if( !$items );
  return "$d is not a Weather instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Weather");

  my $width= int(ICONSCALE*ICONWIDTH);
      
  my $ret = sprintf('<table class="weather"><tr><th width=%d></th><th></th></tr>', $width);
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
  $items = 6 if( !$items );
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
=begin html

<a name="Weather"></a>
<h3>Weather</h3>
<ul>
  <br>

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
    <code>nl</code>,

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

  </ul>
  <br>

  <a name="Weatherattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="Weather"></a>
<h3>Weather</h3>
<ul>
  <br>

  <a name="Weatherdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Weather &lt;location&gt; [&lt;interval&gt; [&lt;language&gt;]]</code><br>
    <br>
    Bezechnet ein virtuelles Gerät für Wettervorhersagen.<br><br>

    Eine solche virtuelle Wetterstation sammelt periodisch aktuelle und zukünftige Wetterdaten aus der Yahoo-Wetter-API.<br><br>

    Der Parameter <code>location</code> entspricht der sechsstelligen WOEID (WHERE-ON-EARTH-ID). Die WOEID für den eigenen Standort kann auf <a href="http://weather.yahoo.com">http://weather.yahoo.com</a> gefunden werden.<br><br>

    Der optionale Parameter  <code>interval</code> gibt die Dauer in Sekunden zwischen den einzelnen Aktualisierungen der Wetterdaten an. Der Standardwert ist 3600 (1 Stunde). Wird kein Wert angegeben, gilt der Standardwert.<br><br>

    Der optionale Parameter für die möglichen Sprachen darf einen der folgende Werte annehmen: <code>de</code>, <code>en</code> oder <code>nl</code>. Er bezeichnet die natürliche Sprache, in der die Wetterinformationen dargestellt werden. Der Standardwert ist <code>en</code>. Wird für die Sprache kein Wert angegeben, gilt der Standardwert. Wird allerdings der Parameter für die Sprache gesetzt, muss ebenfalls ein Wert für das Abfrageintervall gesetzt werden.<br><br>
        
                
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

  </ul>
  <br>

  <a name="Weatherattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
