# $Id$
##############################################################################
#
#     59_WWO.pm
#     Copyright by Andreas Vogt
#     e-mail: sourceforge at baumrasen dot de
#
#     get current weather condition and forecast from worldweatheronline.com
#
#     based / modified from  59_Weather.pm written by Dr. Boris Neubert
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
# use Date::Calc qw(Day_of_Week Day_of_Week_to_Text);

#
# uses the Free Weather API: http://developer.worldweatheronline.com
#

# Mapping of current supported encodings
my %DEFAULT_ENCODINGS = (
    en      => 'latin1',
    da      => 'latin1',
    de      => 'latin1',
    es      => 'latin1',
    fi      => 'latin1',
    fr      => 'latin1',
    it      => 'latin1',
    ja      => 'utf-8',
    ko      => 'utf-8',
    nl      => 'latin1',
    no      => 'latin1',
    'pt-BR' => 'latin1',
    ru      => 'utf-8',
    sv      => 'latin1',
    'zh-CN' => 'utf-8',
    'zh-TW' => 'utf-8',
);

#####################################
sub WWO_Initialize($) {

  my ($hash) = @_;

# Provider
#  $hash->{Clients} = undef;

# Consumer
  $hash->{DefFn}   = "WWO_Define";
  $hash->{UndefFn} = "WWO_Undef";
  $hash->{GetFn}   = "WWO_Get";
  $hash->{SetFn}   = "WWO_Set";
  #$hash->{AttrFn}  = "WWO_Attr";
  #$hash->{AttrList}= "days:0,1,2,3,4,5 loglevel:0,1,2,3,4,5 localicons event-on-update-reading event-on-change-reading";
  #$hash->{AttrList}= "loglevel:0,1,2,3,4,5 localicons event-on-update-reading event-on-change-reading";
  $hash->{AttrList}= "localicons ".
                      $readingFnAttributes;
  

}

###################################
sub latin1_to_utf8($) {

  # http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
  my ($s)= @_;
  $s =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
  return $s;
}

###################################

#sub temperature_in_c {
#  my ($temperature, $unitsystem)= @_;
#  return $unitsystem ne "SI" ? int(($temperature-32)*5/9+0.5) : $temperature;
#}

#sub wind_in_km_per_h {
#  my ($wind, $unitsystem)= @_;
#  return $unitsystem ne "SI" ? int(1.609344*$wind+0.5) : $wind;
#}

###################################
sub WWO_UpdateReading($$$$) {

  my ($hash,$prefix,$key,$value)= @_;

  #Debug "WWO: $prefix $key $value";

  #my $unitsystem= $hash->{READINGS}{unit_system}{VAL};
  
  #not needed
  if($key eq "date") {
  		my @da = split("-", $value);
        $value = sprintf("%02d.%02d.",$da[2],$da[1]);
        $value= $value;
  	} 
#  elsif($key eq "tempMaxC") {
#        $key= "tempMaxC";
#        #$value= temperature_in_c($value,$unitsystem);
#        $value= $value;
#  } elsif($key eq "humidity") {
#        # standardize reading - allow generic logging of humidity.
#        $value=~ s/.*?(\d+).*/$1/; # extract numeric
#  } 

  #Debug "WWO: $prefix $key $value";

  my $reading= $prefix . $key;

  readingsBulkUpdate($hash,$reading,$value);
  if($key eq "temp_C") {
    readingsBulkUpdate($hash,"temperature",$value); # additional entry for compatibility
  }
#  if($key eq "date") {
#  	$reading = $prefix . "shortdate";
#  	my @da = split("-", $value);
#  	$value = left(Day_of_Week_to_Text(Day_of_Week($da[0], $da[1], $da[2]), 3),2);
#    readingsBulkUpdate($hash,$reading,$value); # additional entry
#  }
  
  if($key eq "weatherIconUrl") {
  	# $value =~ s/.*\/([^.\/]*)\.*/$1/;
  	$value =~ s/.*\/([^\/]+\.[^\.]+)/$1/;
  	
  	$reading= $prefix . "icon";
    readingsBulkUpdate($hash,$reading,$value); # additional entry for icon name
  }
  if($reading eq "windspeedKmph") {
    #$value=~ s/.*?(\d+).*/$1/; # extract numeric
    # readingsBulkUpdate($hash,"wind",wind_in_km_per_h($value,$unitsystem)); # additional entry for compatibility
    readingsBulkUpdate($hash,"wind",$value); # additional entry for compatibility
  }

  return 1;
}

###################################
sub WWO_RetrieveDataDirectly($)
{
  my ($hash)= @_;
  my $location= $hash->{LOCATION};
  my $apikey  = $hash->{APIKEY};
  my $days    = $hash->{DAYS};
  
  $days = 5;
  
  #$location =~ s/([^\w()â€™*~!.-])/sprintf '%%%02x', ord $1/eg;
  my $lang= $hash->{LANG}; 

  my $fc = 0;
  my $fd = 0;
  my $days_addon = "&fx=no";
  if ($days > 0) {$days_addon = "&num_of_days=" . $days;} 
  my $theurl = "http://api.worldweatheronline.com/free/v1/weather.ashx?q=" . $location . "&extra=localObsTime&format=xml" . $days_addon . "&key=" . $apikey;
  #Debug "WWO: fecht url: $theurl";
  # my $xml = GetFileFromURL("http://free.worldweatheronline.com/feed/weather.ashx?q=" . $location . "&extra=localObsTime&format=xml" . $days_addon . "&key=" . $apikey);
  # my $xml = GetFileFromURL($theurl);
  my $xml = CustomGetFileFromURL(0, $theurl);
  #Debug "WWO: xml file content: $xml";
  
  # return 0 if( ! defined $xml || $xml eq "");

  if( ! defined $xml || $xml eq "") { # Log-Entry if nothing is returned
  	Log3 $hash, 1,
    "WWO The API returns nothing. Look for an output of CustomGetFileFromURL above";
    return 0;
  }
  
  if ($xml eq "<h1>Developer Inactive</h1>") { # Log-Entry if API-Key not valid
  	Log3 $hash, 1,
    "WWO The API returns, that the Developer is Inactive. Maybe the API-Key is not valid.";
    return 0;
  }
  
  if (index($xml, "error") != -1) { # check for an error-tag in the returned xml file
  	Log3 $hash, 1,
    "WWO The API returns an error: $xml";
    return 0;
  }
  
  foreach my $llll (split("\/request>",$xml)) {
  	  			  #Debug "WWO: llll=\"$llll\"";
  	foreach my $lll (split("\/current_condition>",$llll)) {
  		  			  #Debug "WWO: lll=\"$lll\"";
  		$fc++;
  		foreach my $ll (split("\/weather>",$lll)) {
  			$fd++;  
  			  		# fc/fd = 1/1    > City/Type
			  		# fc/fd = 2/2    > current_condition
			  		# fc/fd = 3/3..5 > today, and following days
  		
  			#Debug "WWO: ll=\"$ll\"";
  			foreach my $l (split(/<\/[\w]*>/,$ll)) {  		 # with closing tag 
	        #Debug "WWO: all_line fc=\"$fc\" line=\"$l\"";
	          next if($l eq "");                   # skip empty lines
	          next if($l =~ m/\/[\w]*>/);		   # skip closing tag lines
	          next if($l =~ m/\?xml/);             # skip xml declaration
	          
	          $l =~ s/<!\[CDATA\[//;                # strip off <![CDATA[
	          $l =~ s/\]\]>//;                      # strip of [[>
	          #$l =~ s/<!\[CDATA\[([\w\d\s.\/:]*)]]>/$1/;                      # strip of [[>	          
	          #Debug "WWO: clean1 fc=\"$fc\" line=\"$l\"";
	          
	          #Debug "WWO: 1fc=\"$fc\" fd=\"$fd\" line=\"$l\"";
	          $l =~ s/(<[\w]*>)(<[\w]*>)/$2/;     # remove first tag in case of two tags in line
	          #Debug "WWO: 2fc=\"$fc\" fd=\"$fd\" line=\"$l\"";
	          
	          	          
	          #$l =~ s/(\/|\?)?>$//;                # strip off /> and >
	          $l =~ s/<//;                # strip off /> and >
	          
	          my ($tag,$value)= split(">", $l, 2); # split tag data=..... at the first blank
	          #Debug "WWO: 3tag=\"$tag\" value=\"$value\"";
	          
	          #$fc= 0 if($tag eq "current_condition");
	          #$fc++ if($tag eq "weather");
	          #next if((!defined($value)) || ($value == ""));
	          next if((!defined($value)) || (!defined($tag)) || ($tag eq "") || ($value eq ""));
	          #Debug "WWO: CHECKED tag=\"$tag\" value=\"$value\"";
	          my $prefix = "";
	          if ($fc == 3) {
	             $prefix= $fd ? "fc" . ($fd-3) ."_" : "";	
	          } else {
	          	$prefix= "";   # may be it would be helpfull to set to 'now_' or so
	          }
	          
	          my $key= $tag;
	          #$value=~ s/^data=\"(.*)\"$/$1/;      # extract DATA from data="DATA"

#	          if($DEFAULT_ENCODINGS{$lang} eq "latin1") {
#	            $value= latin1_to_utf8($value); # latin1 -> UTF-8
#	          }

	          #Debug "WWO: prefix=\"$prefix\" tag=\"$tag\" value=\"$value\"";
	          WWO_UpdateReading($hash,$prefix,$key,$value);
  			}
  		}
  	}
  }
  
  return 1;
}

###################################
sub WWO_GetUpdate($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WWO_GetUpdate", $hash, 1);
  }
  
  readingsBeginUpdate($hash);

  WWO_RetrieveDataDirectly($hash);

  my $temperature= $hash->{READINGS}{temperature}{VAL};
  my $humidity= $hash->{READINGS}{humidity}{VAL};
  my $pressure= $hash->{READINGS}{pressure}{VAL};
  my $wind= $hash->{READINGS}{wind}{VAL};
  my $val= "T: $temperature  H: $humidity W: $wind P: $pressure";
  
    #Log GetLogLevel($hash->{NAME},4), "WWO: Log-->". $hash->{NAME} . ": $val";
    Log3 $hash, 4, "WWO ". $hash->{NAME} . ": $val";
    
    #Debug "Now i will push the changed notify";
    #$hash->{CHANGED}[0]= $val;
    #push @{$hash->{CHANGED}}, "$val";
    #$hash->{STATE}= $val;
    
    ##$hash->{STATE} = $val;                      # List overview
    ##$hash->{READINGS}{state}{VAL} = $val;
    ##$hash->{CHANGED}[0] = $val;                 # For notify
    
    ##Log 1, "WWO $val";
  
    ##addEvent($hash, $val);
    ##readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1)); # DoTrigger, because sub is called by a timer instead of dispatch
      
    readingsBulkUpdate($hash, "state", $val);
    readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1)); # DoTrigger, because sub is called by a timer instead of dispatch
  
    return 1;
}

# Perl Special: { $defs{WWO}{READINGS}{condition}{VAL} }
# conditions: Mostly Cloudy, Overcast, Clear, Chance of Rain

###################################
sub WWO_Get($@) {

  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  $hash->{LOCAL} = 1;
  WWO_GetUpdate($hash);
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

sub WWO_Set($@) {
  my ($hash, @a) = @_;

  my $cmd= $a[1];

  # usage check
  if((@a == 2) && ($a[1] eq "update")) {
    RemoveInternalTimer($hash);
    WWO_GetUpdate($hash);
    return undef;
  } else {
    return "Unknown argument $cmd, only update is valid";
  }
}


#####################################
sub WWO_Define($$) {

  my ($hash, $def) = @_;

  # define <name> WWO <location> <apikey>
  # define MyWWO WWO Berlin,Germany xxxxxxxxxxxxxxxxxxxx 3600

  my @a = split("[ \t][ \t]*", $def);

  #return "syntax: define <name> WWO <location> <apikey> [interval]" 
  return "syntax: define <name> WWO <location> <apikey> [interval]" # interval option not acitve
    #if(int(@a) < 3 && int(@a) > 4); 
    if(int(@a) < 3 && int(@a) > 3); # interval option not acitve

  $hash->{STATE} = "Initialized";
  $hash->{fhem}{interfaces}= "temperature;humidity;wind";

  my $name      = $a[0];
  my $location  = $a[2];
  my $apikey    = $a[3];
  my $interval  = 3600;
  my $lang      = "en"; 
  
  # if(int(@a)>=5) { $interval= $a[4]; }

  my $days      = 5; # fixed to 5 days, right values are a number from 0-5
  
  $hash->{LOCATION}     = $location;
  $hash->{INTERVAL}     = $interval;
  $hash->{APIKEY}       = $apikey;
  $hash->{LANG}         = $lang;
  $hash->{DAYS}         = $days;
  $hash->{READINGS}{current_date_time}{TIME}= TimeNow();
  $hash->{READINGS}{current_date_time}{VAL}= "none";

  $hash->{LOCAL} = 1;
  WWO_GetUpdate($hash);
  delete $hash->{LOCAL};

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WWO_GetUpdate", $hash, 0);

  return undef;
}

#####################################
sub WWO_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

######################################
# sub
# WWO_Attr(@)
# {
#   my @a = @_;
#   my $attr= $a[2];
# 
#   if($a[0] eq "set") {  # set attribute
#     if($attr eq "days") {
#     }
#   }
#   elsif($a[0] eq "del") { # delete attribute
#     if($attr eq "days") {
#     }
#   }
# 
#   return undef;
# 
# }

#####################################
sub
WWOIconIMGTag($$$) {

  use constant WWOURL => "http://www.worldweatheronline.com/images/wsymbols01_png_64/";
  use constant SIZE => "50%";

  my ($icon,$uselocal,$isday)= @_;

  my $url;
  my $style= "";
  
  if($uselocal) {
    # strip off path and extension
    $icon =~ s,^/images/wsymbols01_png_64/(.*)\.png$,$1,;

    if($isday) {
      $icon= "weather/${icon}"
    } else {
      $icon= "weather/${icon}_night"
    }

    $url= "fhem/icons/$icon";
    $style= " height=".SIZE." width=".SIZE;
  } else {
    $url= WWOURL . $icon;
  }

  return "<img src=\"$url\"$style>";

}

#####################################
sub
WWOAsHtml($)
{

  my ($d) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a WWO instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "WWO");

  my $uselocal= AttrVal($d,"localicons",0);
  my $isday;
  if(exists &isday) {
                $isday = isday();
        } else {
                $isday = 1; #($hour>6 && $hour<19);
  }
        
  my $ret = "<table>";
  $ret .= sprintf('<tr><td>%s</td><td><br></td></tr>',
        ReadingsVal($d, "query", ""));

  $ret .= sprintf('<tr><td>%s</td><td>%s %s<br>temp: %s °C, hum %s<br>wind: %s km/h %s<br>pressure: %s bar visibility: %s km</td></tr>',
        WWOIconIMGTag(ReadingsVal($d, "icon", ""),$uselocal,$isday),
        ReadingsVal($d, "localObsDateTime", ""),ReadingsVal($d, "weatherDesc", ""),
        ReadingsVal($d, "temp_C", ""), ReadingsVal($d, "humidity", ""),
        ReadingsVal($d, "windspeedKmph", ""), ReadingsVal($d, "winddir16Point", ""),
        ReadingsVal($d, "pressure", ""),ReadingsVal($d, "visibility", ""));

  for(my $i=0; $i<=4; $i++) {
    $ret .= sprintf('<tr><td>%s</td><td>%s: %s<br>min %s °C max %s °C<br>wind: %s km/h %s<br>precip: %s mm</td></tr>',
        WWOIconIMGTag(ReadingsVal($d, "fc${i}_icon", ""),$uselocal,$isday),
        ReadingsVal($d, "fc${i}_date", ""),
        ReadingsVal($d, "fc${i}_weatherDesc", ""),
        ReadingsVal($d, "fc${i}_tempMinC", ""), ReadingsVal($d, "fc${i}_tempMaxC", ""),
        ReadingsVal($d, "fc${i}_windspeedKmph", ""), ReadingsVal($d, "fc${i}_winddir16Point", ""),
        ReadingsVal($d, "fc${i}_precipMM", ""));
  }
  
  $ret .= "</table>";
  
  $ret .= "<br> Powered by <a href=\"[url]http://www.worldweatheronline.com/[/url]\" title=\"Free local weather content provider\" target=\"_blank\">World Weather Online</a> ";
  
  return $ret;
}

#####################################
sub right{
    my ($string,$nr) = @_;
    return substr $string, -$nr, $nr;
}

#####################################
sub left{
    my ($string,$nr) = @_;
    return substr $string, 0, $nr;
}

#####################################


1;

=pod
=begin html

<a name="WWO"></a>
<h3>WWO</h3>
<ul>
  <br>

  <a name="WWOdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WWO &lt;location&gt; &lt;apikey&gt;</code><br>
    <br>
    Defines a virtual device for WWO forecasts.<br><br>

    A WWO device periodically gathers current and forecast weather conditions
    from worldweatheronline.com (the free api version)<br>
    You need to signup at <a href="http://developer.worldweatheronline.com">http://developer.worldweatheronline.com</a> to get an apikey)<br><br>

    The parameter <code>location</code> is the WOEID (WHERE-ON-EARTH-ID), go to
    <a href="http://www.worldweatheronline.com">http://www.worldweatheronline.com</a> to find it out for your valid location.<br><br>

    The natural language in which the forecast information appears is english.
    <br><br>
    
    The interval is set to update the values every hour.
    <br><br>

    Examples:
    <pre>
      define MyWeather WWO Berlin,Germany
     </pre>
     
    The module provides one additional function <code>WWOAsHtml</code>. The function return the HTML code for a
    vertically arranged weather forecast.
    <br><br>
    
    Example:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WWOAsHtml("MyWeather") }
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

    Valid readings and their meaning (? can be one of 0, 1, 2, 3, 4, 5 and stands
    for today, tomorrow, etc. - with 'fc?_' or without! - without is meaning 'current condition'):<br>
    <table>
    <tr><td>cloudcover</td><td>cloudcover in percent</td></tr>
    <tr><td>current_date_time</td><td>last update of forecast on server</td></tr>   
    <tr><td>fc?_date</td><td>date of the forecast condition - not valid without 'fc?'</td></tr>
    <tr><td>fc?_icon</td><td>name of the forecasticon</td></tr>
    <tr><td>fc?_precipMM</td><td>preciption for day</td></tr>
    <tr><td>fc?_tempMaxC</td><td>forecasted daily high in degrees centigrade</td></tr>
    <tr><td>fc?_tempMaxF</td><td>forecasted daily high in degrees fahrenheit</td></tr>
    <tr><td>fc?_tempMinC</td><td>forecasted daily low in degrees centigrade</td></tr>
    <tr><td>fc?_tempMinF</td><td>forecasted daily low in degrees fahrenheit</td></tr>
    <tr><td>fc?_weatherCode</td><td>weathercode</td></tr>
    <tr><td>fc?_weatherDesc</td><td>short weather desciption</td></tr>
    <tr><td>fc?_weatherIconUrl</td><td>full url to the weathericonfile</td></tr>
    <tr><td>fc?_winddir16Point</td><td>winddirection with 16 points</td></tr>
    <tr><td>fc?_winddirDegree</td><td>windirection in degrees</td></tr>
    <tr><td>fc?_winddirection</td><td>winddirection</td></tr>
    <tr><td>fc?_windspeedKmph</td><td>windspeed in km/h</td></tr>
    <tr><td>fc?_windspeedMiles</td><td>windspeed in miles/h</td></tr>
    <tr><td>humidity</td><td>current humidity in %</td></tr>
    <tr><td>localObsDateTime</td><td>local time of observation</td></tr>
    <tr><td>observation_time</td><td>time of observation</td></tr>
    <tr><td>pressure</td><td>air pressure in hPa</td></tr>
    <tr><td>query</td><td>returns the queried location</td></tr>
    <tr><td>temperature</td><td>current temperature in degrees centigrade</td></tr>
    <tr><td>visibility</td><td>current visibilit in km</td></tr>
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
=cut
