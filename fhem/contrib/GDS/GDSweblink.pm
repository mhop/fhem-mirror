# $Id: GDSweblink.pm 9426 2015-10-11 10:07:59Z betateilchen $
package main;

use strict;
use warnings;
use POSIX;

####################################################################################################
#
#  create weblinks 
#  provided and maintained by jensb
#
####################################################################################################

# weather description to icon name mapping
my %GDSDayWeatherIconMap = (
  'bedeckt' => 'overcast',
  'bewölkt' => 'mostlycloudy',
  'Dunst oder flacher Nebel' => 'haze',
  'gefrierender Nebel' => 'icy',
  'gering bewölkt' => 'partlycloudy',
  'Gewitter' => 'thunderstorm',
  'Glatteisbildung' => 'icy',
  'Graupelschauer' => 'snow',
  'Hagelschauer' => 'snow',
  'heiter' => 'partlycloudy',
  'in Wolken' => 'mostlycloudy',
  'kein signifikantes Wetter' => 'na',
  'kräftiger Graupelschauer' => 'heavysnow',
  'kräftiger Hagelschauer' => 'heavysnow',
  'kräftiger Regen' => 'heavyrain',
  'kräftiger Regenschauer' => 'scatteredshowers',
  'kräftiger Schneefall' => 'heavysnow',
  'kräftiger Schneeregen' => 'rainsnow',
  'kräftiger Schneeregenschauer' => 'rainsnow',
  'kräftiger Schneeschauer' => 'heavysnow',
  'leicht bewölkt' => 'partlycloudy',
  'leichter Regen' => 'mist',
  'leichter Schneefall' => 'snow',
  'leichter Schneeregen' => 'rainsnow',
  'Nebel' => 'fog',
  'Regen' => 'rain',
  'Regenschauer' => 'scatteredshowers',
  'Sandsturm' => 'dust',
  'Schneefall' => 'snow',
  'Schneefegen' => 'snow',
  'Schneeregen' => 'rainsnow',
  'Schneeregenschauer' => 'rainsnow',
  'Schneeschauer' => 'snow',
  'schweres Gewitter' => 'thunderstorm',
  'stark bewölkt' => 'mostlycloudy',
  'starkes Gewitter' => 'thunderstorm',
  'wolkenlos' => 'sunny',
  '---' => 'mostlycloudy',
  );
  
my %GDSNightWeatherIconMap = (
  'bedeckt' => 'overcast',
  'bewölkt' => 'mostlycloudy_night',
  'Dunst oder flacher Nebel' => 'haze_night',
  'gefrierender Nebel' => 'icy',
  'gering bewölkt' => 'partlycloudy_night',
  'Gewitter' => 'thunderstorm',
  'Glatteisbildung' => 'icy',
  'Graupelschauer' => 'snow',
  'Hagelschauer' => 'snow',
  'heiter' => 'partlycloudy_night',
  'in Wolken' => 'mostlycloudy_night',
  'kein signifikantes Wetter' => 'na',
  'kräftiger Graupelschauer' => 'heavysnow',
  'kräftiger Hagelschauer' => 'heavysnow',
  'kräftiger Regen' => 'heavyrain',
  'kräftiger Regenschauer' => 'scatteredshowers_night',
  'kräftiger Schneefall' => 'heavysnow',
  'kräftiger Schneeregen' => 'rainsnow',
  'kräftiger Schneeregenschauer' => 'rainsnow',
  'kräftiger Schneeschauer' => 'heavysnow',
  'leicht bewölkt' => 'partlycloudy_night',
  'leichter Regen' => 'mist',
  'leichter Schneefall' => 'snow',
  'leichter Schneeregen' => 'rainsnow',
  'Nebel' => 'fog',
  'Regen' => 'rain',
  'Regenschauer' => 'scatteredshowers_night',
  'Sandsturm' => 'dust',
  'Schneefall' => 'snow',
  'Schneefegen' => 'snow',
  'Schneeregen' => 'rainsnow',
  'Schneeregenschauer' => 'rainsnow',
  'Schneeschauer' => 'snow',
  'schweres Gewitter' => 'thunderstorm',
  'stark bewölkt' => 'mostlycloudy_night',
  'starkes Gewitter' => 'thunderstorm',
  'wolkenlos' => 'sunny_night',
  '---' => 'mostlycloudy_night',
  );
  
# icon parameters
use constant ICONHIGHT => 120;
use constant ICONWIDTH => 175;
use constant ICONSCALE => 0.5;

sub GDSIsDay($$) {
# check if it is day at given time
#
# @param: time
# @param: altitude, see documentation of module SUNRISE_EL
  my ($time, $altitude) = @_;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
  my $t = ($hour*60 + $min) + $sec;
  
  my (undef, $srHour, $srMin, $srSec, undef) = GetTimeSpec(sunrise_abs_dat($time, $altitude));
  my $sunrise = ($srHour*60 + $srMin) + $srSec;

  my (undef, $ssHour, $ssMin, $ssSec, undef) = GetTimeSpec(sunset_abs_dat($time, $altitude));
  my $sunset = ($ssHour*60 + $ssMin) + $ssSec;
  
  return $t >= $sunrise && $t <= $sunset;
}

sub GDSIconIMGTag($;$) {
# get FHEM weather icon
#
# @param: weather description
# @param: time of weather description or 1 for night, optional, defaults to daytime icons
  my $width = int(ICONSCALE*ICONWIDTH);
  my ($weather, $time) = @_;
  my $icon;
  if (!defined($time) || (defined($time) && $time > 1 && GDSIsDay($time, "REAL"))) {
    $icon = $GDSDayWeatherIconMap{$weather};
  } else {
    $icon = $GDSNightWeatherIconMap{$weather};
  }
  if (defined($icon)) {
    my $url= FW_IconURL("weather/$icon");
    my $style= " width=$width";
    return "<img src=\"$url\"$style alt=\"$icon\">";
  } else {
    return "";
  }
}

sub GDSAsHtmlV($;$) {
# create forecast in a vertical HTML table 
#
# @param: device name
# @param: number of icons, optional, default 8
  my ($d,$items) = @_;
  $d = "<none>" if(!$d);
  $items = $items? $items - 1 : 7;
  return "$d is not a GDS instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "GDS");

  my $width = int(ICONSCALE*ICONWIDTH);
      
  my $ret = sprintf('<table class="weather"><tr><th width=%d></th><th></th></tr>', $width);
  $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">Aktuell: </span><span class="weatherCondition">%s</span><br><span class="weatherValue">%s°C</span><br><span class="weatherWind">Wind %s km/h %s</span></td></tr>',
        $width,
        GDSIconIMGTag(ReadingsVal($d, "c_weather", "?"), time_str2num(ReadingsTimestamp($d, "c_weather", TimeNow()))),
        ReadingsVal($d, "c_weather", "?"),
        ReadingsVal($d, "c_temperature", "?"),
        ReadingsVal($d, "c_windSpeed", "?"), ReadingsVal($d, "c_windDir", "?"));

  # get time of last forecast
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time_str2num(ReadingsTimestamp($d, "fc3_weather24", TimeNow())));
        
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    my $weekday = $i == 0? ($hour < 17? 'Spät' : 'Nachts') : ($i - 1)%2 == 0? ReadingsVal($d, "fc".$day."_weekday", "?").' früh' : ReadingsVal($d, "fc".$day."_weekday", "?").' spät';

    if (($i - 1)%2 == 0) {
      $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: </span><span class="weatherCondition">%s</span><br><span class="weatherMin">min %s°C</span><br><span class="weatherWind">%s</span></span></td></tr>',
          $width,
          GDSIconIMGTag(ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?")),
          $weekday,
          ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?"),
          ReadingsVal($d, "fc".$day."_tMinAir", "?"),
          ReadingsVal($d, "fc".$day."_windGust".$timeLabel, ""));
    } else {    
      if ($i == 0 && $hour >= 17) {
        $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: </span><span class="weatherCondition">%s</span><br><span class="weatherValue">%s°C</span><br><span class="weatherWind">%s</span></td></tr>',
            $width,
            GDSIconIMGTag(ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?"), 1),
            $weekday,
            ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?"),
            ReadingsVal($d, "fc".$day."_tAvgAir".$timeLabel, "?"),
            ReadingsVal($d, "fc".$day."_windGust".$timeLabel, ""));
      } else {
        $ret .= sprintf('<tr><td class="weatherIcon" width=%d>%s</td><td class="weatherValue"><span class="weatherDay">%s: </span><span class="weatherCondition">%s</span><br><span class="weatherMax">max %s°C</span><br><span class="weatherWind">%s</span></td></tr>',
            $width,
            GDSIconIMGTag(ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?")),
            $weekday,
            ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?"),
            ReadingsVal($d, "fc".$day."_tMaxAir", "?"),
            ReadingsVal($d, "fc".$day."_windGust".$timeLabel, ""));
      }
    }
  }
      
  $ret .= "</table>";
  return $ret;
}

sub GDSAsHtmlH($;$) {
# create forecast in a horizontal HTML table 
#
# @param: device name
# @param: number of icons, optional, default 8
  my ($d, $items) = @_;
  $d = "<none>" if(!$d);
  $items = $items? $items - 1 : 7;
  return "$d is not a GDS instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "GDS");

  my $width = 110;
  
  my $ret = '<table class="weather">';

  # get time of last forecast
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time_str2num(ReadingsTimestamp($d, "fc3_weather24", TimeNow())));
  
  # weekday / time
  $ret .= sprintf('<tr><td align="center" class="weatherDay">Aktuell</td>');
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    my $weekday = $i == 0? ($hour < 17? 'Spät' : 'Nachts') : ($i - 1)%2 == 0? ReadingsVal($d, "fc".$day."_weekday", "").' früh' : ReadingsVal($d, "fc".$day."_weekday", "").' spät';
    $ret .= sprintf('<td align="center" class="weatherDay">%s</td>', $weekday);
  }
  $ret .= '</tr>';
  
  # condition icon
  $ret .= sprintf('<tr><td align="center" class="weatherIcon" width=%d>%s</td>', $width, GDSIconIMGTag(ReadingsVal($d, "c_weather", "na"), time_str2num(ReadingsTimestamp($d, "c_weather", TimeNow()))));
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    $ret .= sprintf('<td align="center" class="weatherIcon" width=%d>%s</td>', $width, GDSIconIMGTag(ReadingsVal($d, "fc".$day."_weather".$timeLabel, "na"), $i==0 && $hour >= 17? 1 : undef));
  }
  $ret .= '</tr>';
  
  # condition text
  $ret .= sprintf('<tr><td align="center" class="weatherCondition">%s</td>', ReadingsVal($d, "c_weather", "?"));
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    $ret .= sprintf('<td align="center" class="weatherCondition">%s</td>', ReadingsVal($d, "fc".$day."_weather".$timeLabel, "?"));
  }
  $ret .= '</tr>';
  
  # temperature / min temperature
  $ret .= sprintf('<tr><td align="center" class="weatherValue">%s°C</td>', ReadingsVal($d, "c_temperature", "?"));
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    if (($i - 1)%2 == 0) {
      $ret .= sprintf('<td align="center" class="weatherMin">min %s°C</td>', ReadingsVal($d, "fc".$day."_tMinAir", "?"));
    } else {
      if ($i == 0 && $hour >= 17) {
        $ret .= sprintf('<td align="center" class="weatherValue">%s°C</td>', ReadingsVal($d, "fc".$day."_tAvgAir".$timeLabel, "?"));
      } else {
        $ret .= sprintf('<td align="center" class="weatherMax">max %s°C</td>', ReadingsVal($d, "fc".$day."_tMaxAir", "?"));
      }
    }
  }
  $ret .= '</tr>';
  
  # wind
  $ret .= sprintf('<tr><td align="center" class="weatherWind">%s km/h %s</td>', ReadingsVal($d, "c_windSpeed", "?"), ReadingsVal($d, "c_windDir", "?"));
  for(my $i=0; $i<$items; $i++) {
    my $day = int(($i + 1)/2);
    my $timeLabel = $i == 0? ($hour < 17? '18' : '24') : ($i - 1)%2 == 0? '12' : '24';
    $ret .= sprintf('<td align="center" class="weatherWind">%s</td>', ReadingsVal($d, "fc".$day."_windGust".$timeLabel, ""));
  }
  $ret .= "</tr></table>";

  return $ret;
}

sub GDSAsHtmlD($;$) {
# create forecast in a horizontal or vertical HTML table 
# depending on the display orientation
# @param: device name
# @param: number of icons, optional, default 8

  my ($d,$i) = @_;
  if(defined($FW_ss) && $FW_ss) {
    GDSAsHtmlV($d,$i);
  } else {
    GDSAsHtmlH($d,$i);
  }
}

1;

=pod
=begin html

<a name="gdsUtils"></a>
<h3>gdsUtils</h3>
<ul>
<li>	This module provides three additional functions:<br/> 
	<code>GDSAsHtmlV</code>, <code>GDSAsHtmlH</code> and <code>GDSAsHtmlD</code>. <br/>
	The first function returns the HTML code for a vertically arranged weather forecast. <br/>
	The second function returns the HTML code for a horizontally arranged weather forecast. <br/>
	The third function dynamically picks the orientation depending on whether a <br/>
	smallscreen style is set (vertical layout) or not (horizontal layout).<br/>
	The attributes gdsSetCond and gdsSetForecast must be configured for the functions to work.<br/>
	Each of these functions accepts an additional parameter to limit the number of icons to display (1...8). <br/>
	If the attribute gdsSetForecast is not configured this parameter should be set to 1.<br/>
	<br/>
	Example: <code>define MyForecastWeblink weblink htmlCode { GDSAsHtml("MyWeather") }</code> <br/>
	where "MyWeather" is the name of your GDS device.<br/>
</li>
</ul>

=end html
=cut
