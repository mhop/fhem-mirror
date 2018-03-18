###############################################################
# $Id$
#
#  59_OPENWEATHER.pm 
#
#  (c) 2014 Torsten Poitzsch
#  (c) 2014-2016 tupol http://forum.fhem.de/index.php?action=profile;u=5432
#
#  This module reads weather forecast data via the openweather-api of www.wetter.com
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> OPENWEATHER <project> <cityCode> <apikey>
#
##############################################################################

###############################################
# parser for the weather data
package MyOPENWEATHERParser;
use base qw(HTML::Parser);
our %fcReadings = ();
my $curTag      = "";
our $day         = -2;
our $time        = "";
# here HTML::text/start/end are overridden

%knownTags = ( tn => "tempMin"
   , tx => "tempMax"
   , w => "weatherCode"
   , w_txt => "weather"
   , ws => "wind"
   , wd => "windDir"
   , wd_txt => "windDirTxt"
   , pc => "chOfRain"
   , p => "valHours"
   , title => "error"
   , message => "errorMsg"
   , name => "city"
   , post_code => "postcode"
   , url => "url"
);

sub 
get_wday($)
{
   my ($date) = @_;
   my @wday_txt = qw(So Mo Di Mi Do Fr Sa);
   my @th=localtime $date;
  
   return $wday_txt [$th[6]];
}

sub text
{
   my ( $self, $text ) = @_;

   my $rName = $knownTags{$curTag};
   if (defined $rName)
   {
      if ($day == -2)
      {
         $fcReadings{$rName} = $text ; 
      }
      elsif ( $day >= 0 )
      {
         #Umlaute entfernen
         if ($curTag eq "w_txt") {$text =~ s/�/oe/; $text =~ s/�/ae/; $text =~ s/�/ue/; $text =~ s/�/ss/;}         
         $fcReadings{"fc".$day."_".$rName.$time} = $text ; 
        # icon erzeugen
         # if ($curTag eq "w") 
         # {
            # if ($time != "23") 
            # {
               # $fcReadings{"fc".$day."_".$rName.$time} = "d_".$text."_L.png" ;
            # }
            # else
            # {
               # $fcReadings{"fc".$day."_".$rName.$time} = "n_".$text."_L.png" ;
            # }
         # }         
         
      }
   }
   elsif ($curTag eq "d" && $time eq "")
   {
      $fcReadings{"fc".$day."_wday"} = get_wday $text ; 
   }
}

sub start
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = $tagname;
   
   if ($tagname eq "forecast")
   {
      $day = -1;
   }
   elsif ( $tagname eq "date" && $day >= -1 )
   {
      $day++;
      $time = "";
   }
   elsif ($tagname eq "time")
   {
      $time = substr($attr->{value}, 0, 2);
   }
}

sub end
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = "";
   if ($tagname eq "time")
   {
      $time = "";
   }
}

#######################################################################
package main;


use strict;
use warnings;
use Blocking;
my $missingModul;
eval "use MIME::Base64;1" or $missingModul .= "MIME::Base64 ";
eval "use Digest::MD5 'md5_hex';1" or $missingModul .= "Digest::MD5 ";
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use HTTP::Request;1" or $missingModul .= "HTTP::Request ";
eval "use HTML::Parser;1" or $missingModul .= "HTML::Parser ";

my $MODUL = "OPENWEATHER";

sub OPENWEATHER_Log($$$);
sub OPENWEATHER_Start($);
sub OPENWEATHER_Run($);
sub OPENWEATHER_Done($);
sub OPENWEATHER_UpdateAborted($);
  
sub ##########################################
OPENWEATHER_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/OPENWEATHER_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

sub ##########################################
OPENWEATHER_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "OPENWEATHER_Define";
  $hash->{UndefFn}  = "OPENWEATHER_Undefine";

  $hash->{SetFn}    = "OPENWEATHER_Set";
  $hash->{GetFn}    = "OPENWEATHER_Get";
  $hash->{AttrFn}   = "OPENWEATHER_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."INTERVAL "
                .$readingFnAttributes;

} # end OPENWEATHER_Initialize


sub ##########################################
OPENWEATHER_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Error: Perl moduls ".$missingModul."are missing on this system"
      if $missingModul;

   return "Usage: define <name> OPENWEATHER <project> <cityCode> <apiKey> [language]" if(@args <5 || @args >6);

  
  my $name = $args[0];

  $hash->{NAME} = $name;

  $hash->{STATE}       = "Initializing";
  $hash->{INTERVAL}    = 3600;
  $hash->{PROJECT}     = $args[2];
  $hash->{CITYCODE}    = $args[3];
  $hash->{APIKEY}      = $args[4];
  $hash->{LANGUAGE}    = $args[5] if defined $args[5];
  $hash->{CREDIT}      = "Powered by wetter.com";

   my $checkSum = md5_hex( $args[2] . $args[4] . $args[3] );
   
   my $URL = 'http://api.wetter.com/forecast/weather';
   $URL   .= '/city/'    . $args[3];
   $URL   .= '/project/' . $args[2];
   $URL   .= '/cs/'      . $checkSum;
   $URL   .= '/language/'. $args[5] if defined $args[5];
   
   $hash->{URL}   = $URL;

   $hash->{fhem}{LOCAL} = 0;
   $hash->{fhem}{modulVersion} = '$Date$';

   RemoveInternalTimer($hash);
 # Get first data after 7 seconds
   InternalTimer(gettimeofday() + 7, "OPENWEATHER_Start", $hash, 0);
 
   return undef;
} #end OPENWEATHER_Define


sub ##########################################
OPENWEATHER_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
} # end OPENWEATHER_Undefine


sub ##########################################
OPENWEATHER_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($cmd eq "set")
   {
      if ($aName eq "INTERVAL")
      {
         if ($aVal < 3600 && $aVal != 0)
         {
            OPENWEATHER_Log $name, 3, "Error: Minimum of attribute INTERVAL is 3600 or 0";
            return "Minimum of attribute INTERVAL is 3600 or 0";
         }
         else
         {
            # Internal Timer neu starten
            RemoveInternalTimer($hash);
            if ($aVal >0)
            {
               InternalTimer(gettimeofday()+7, "OPENWEATHER_Start", $hash, 0);
            }
         }
      }
   }
   elsif ($cmd eq "del")
   {
      if ($aName eq "INTERVAL")
      {
         # Internal Timer neu starten
         RemoveInternalTimer($hash);
         InternalTimer(gettimeofday()+1, "OPENWEATHER_Start", $hash, 0);
      }
   }

   return undef;
} # OPENWEATHER_Attr ende


sub ##########################################
OPENWEATHER_Set($$@) 
{
   my ($hash, $name, $cmd, $val) = @_;
   my $resultStr = "";
   
   if(lc $cmd eq 'update') 
   {
      $hash->{fhem}{LOCAL} = 1;
      OPENWEATHER_Start($hash);
      $hash->{fhem}{LOCAL} = 0;
      return undef;
   }
   my $list = "update:noArg";
   return "Unknown argument $cmd, choose one of $list";

} # end OPENWEATHER_Set


sub ##########################################
OPENWEATHER_Get($@)
{
  my ($hash, $name, $cmd) = @_;
  my $result;
  my $message;
  
  if (lc $cmd eq "apiresponse") 
  {
      my $time = gettimeofday();
      $result = OPENWEATHER_Run $name;
      my @a = split /\|/, $result;
      if ($a[1]==0) 
      { 
         $message = $a[2]; 
      } 
      else 
      {
         $message = decode_base64($a[2]);
      }
      $time = gettimeofday() - $time;
      if ($time > AttrVal($name, "timeOut", 10)) { 
         $message =  sprintf( "Runtime: %.2f s (!!! Increase attribute 'timeOut' !!!)\n_________________\n\n", $time) . $message;
      } else {
         $message =  sprintf( "Response of %s\nRuntime: %.2f s\n_________________\n\n %s", $hash->{URL}, $time, $message);
      }
      return $message;
      
  }
  
  my $list = "apiResponse:noArg";
  return "Unknown argument $cmd, choose one of $list";

} # end OPENWEATHER_Get


# Starts the data capturing and sets the new timer
sub ##########################################
OPENWEATHER_Start($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL", 3600 );

   readingsSingleUpdate($hash, "state", "disabled", 1)     if AttrVal($name, "disable", 0 ) == 1;

   if( $hash->{fhem}{LOCAL} != 1 && $hash->{INTERVAL} > 0 )
   {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OPENWEATHER_Start", $hash, 1);
      return undef      if AttrVal($name, "disable", 0 ) == 1;
   }

   my $timeOut = AttrVal($name, "timeOut", 10);
   $hash->{helper}{RUNNING_PID} = BlockingCall("OPENWEATHER_Run", $name, 
                                          "OPENWEATHER_Done", $timeOut,
                                          "OPENWEATHER_UpdateAborted", $hash) 
                                unless(exists($hash->{helper}{RUNNING_PID}));
}


sub ##########################################
OPENWEATHER_Run ($)
{
   my ($name) = @_;
   my $returnStr;
   my $hash = $defs{$name};
   
   return $name."|0|Error: URL not created. Please re-define device."
      unless defined $hash->{URL};
   my $URL = $hash->{URL};

   OPENWEATHER_Log $hash, 5, "Start capturing data from $URL";

   my $err_log  = "";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10
                                       , agent => "Mozilla/5.0 (FHEM)" );
   my $request  = HTTP::Request->new( GET => $URL );
   my $response = $agent->request($request);
   $err_log = "Error: Can't get $URL -- " . $response->status_line
     unless $response->is_success;
     
   if ( $err_log ne "" )
   {
      return "$name|0|" . $err_log;
   }

   OPENWEATHER_Log $hash, 5, length($response->content)." characters captured";
   
   my $message = encode_base64($response->content,"");
   return "$name|1|$message" ;

} # end OPENWEATHER_Run


sub ###########################
OPENWEATHER_Done($)
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
  
   delete($hash->{helper}{RUNNING_PID});

   readingsBeginUpdate($hash);

   if ( $success == 1 ) {
      my $message = decode_base64($result);

      OPENWEATHER_Log $hash, 5, "Start parsing of XML data.";

      my $parser = MyOPENWEATHERParser->new;
      %MyOPENWEATHERParser::fcReadings = ();
      $MyOPENWEATHERParser::day        = -2;
      $MyOPENWEATHERParser::time       = "";
      $parser->parse($message);

      OPENWEATHER_Log $hash, 4, "Captured values: " . keys (%MyOPENWEATHERParser::fcReadings);
 
      if (defined $MyOPENWEATHERParser::fcReadings{error} )
      {
         readingsBulkUpdate($hash, "lastConnection", $MyOPENWEATHERParser::fcReadings{error});
         OPENWEATHER_Log $hash, 1, $MyOPENWEATHERParser::fcReadings{error}." - ".$MyOPENWEATHERParser::fcReadings{errorMsg};
      }
      else
      {
         readingsBulkUpdate($hash, "lastConnection", keys (%MyOPENWEATHERParser::fcReadings) . " values captured");
         
         while (my ($rName, $rValue) = each(%MyOPENWEATHERParser::fcReadings) )
         {
            readingsBulkUpdate( $hash, $rName, $rValue );
            OPENWEATHER_Log $hash, 5, "reading:$rName value:$rValue";
         }

         my $state = "Tmin: ".$MyOPENWEATHERParser::fcReadings{fc0_tempMin};
         $state   .= " Tmax: ".$MyOPENWEATHERParser::fcReadings{fc0_tempMax};
         readingsBulkUpdate ($hash, "state", $state);
      }
   }
   else {
      readingsBulkUpdate($hash, "lastConnection", $result);
      readingsBulkUpdate($hash, "state", "Error");
      OPENWEATHER_Log $hash, 1, $result;
   }

    readingsEndUpdate( $hash, 1 );

} # end OPENWEATHER_Done

sub ############################
OPENWEATHER_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  OPENWEATHER_Log $hash, 1, "Timeout when connecting to wetter.com";
  readingsSingleUpdate($hash, "lastConnection", "Error: Timeout when connecting to wetter.com", 1);

} # end OPENWEATHER_UpdateAborted

##### noch nicht fertig ###########
sub #####################################
OPENWEATHER_Html($@)
{
   my %fhemicons = (
        0 => "sunny.png",      1 => "partly_cloudy.png", 2 => "cloudy.png",           3 => "overcast.png"
      , 4 => "fog.png",        5 => "drizzle.png",       6 => "rain.png",             7 => "snow.png"
      , 8 => "shower.png",     9 => "thunderstorm.png", 10 => "partly_cloudy.png",   20 => "cloudy.png"
      , 30 => "overcast.png", 40 => "fog.png",          45 => "fog.png",             48 => "fog.png"
      , 49 => "fog.png",      50 => "drizzle.png",      51 => "drizzle.png",         53 => "drizzle.png"
      , 55 => "drizzle.png",  56 => "drizzle.png",      57 => "icy.png",             60 => "rain.png"
      , 61 => "rain.png",     63 => "rain.png",         65 => "heavyrain.png",       66 => "rain.png"
      , 67 => "icy.png",      68 => "sleet.png",        69 => "sleet.png",           70 => "snow.png"
      , 71 => "snow.png",     73 => "snow.png",         75 => "snow.png",            80 => "scatteredshowers.png"
      , 81 => "showers.png",  82 => "showers.png",      83 => "chance_of_sleet.png", 84 => "sleet.png"
      , 85 => "chance_of_snow.png", 86 => "sleet.png",  90 => "thunderstorm.png",    95 => "scatteredthunderstorm.png"
      , 96 => "thunderstorm.png", 999 => "na.png"
   );
  my ($d, $icons) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a OPENWEATHER instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "OPENWEATHER");

  my $uselocal= 0; #AttrVal($d,"localicons",0);
  my $isday;
   if ( exists &isday) 
   {
      $isday = isday();
   }
   else 
   {
      $isday = 1; #($hour>6 && $hour<19);
   }
        
  my $ret = "<table>";
  $ret .= sprintf '<tr><td colspan=2><b>Vorhersage %s</b></td></tr>', ReadingsVal($d, "city", "");

   for(my $i=0; $i<=2; $i++) 
   {
     $ret .= sprintf('<tr><td valign=top><b>%s</b></td><td>%s<br>min. %s °C max. %s °C<br>Nieders.risiko: %s %%<br>Wind: %s km/h aus %s</td></tr>',
         $i==0 ? "heute" : ReadingsVal($d, "fc".$i."_wday", "")
         , ReadingsVal($d, "fc".$i."_weather", "")
         , ReadingsVal($d, "fc".$i."_tempMin", ""), ReadingsVal($d, "fc".$i."_tempMax", "")
         , ReadingsVal($d, "fc".$i."_chOfRain", "")
         , ReadingsVal($d, "fc".$i."_wind", ""), ReadingsVal($d, "fc".$i."_windDirTxt", "")
         );
   }
  
   $ret .= sprintf ('<tr><td colspan=2>powered by <a href="http://www.wetter.com/%s">wetter.com</a></td></tr>', ReadingsVal($d, "url", "") );
   $ret .= "</table>";

  return $ret;
}

##################################### 

1;

=pod
=item device
=item summary Extracts weather data via the "openweather" API of www.wetter.com.
=item summary_DE Extrahiert Wetterdaten über die "openweather"-Schnittstelle von www.wetter.com.

=begin html

<a name="OPENWEATHER"></a>
<h3>OPENWEATHER</h3>
<div> 
<ul>
   The module extracts weather data via the <a href="http://www.wetter.com/apps_und_mehr/website/api/dokumentation">openweather API</a> of <a href="http://www.wetter.com">www.wetter.com</a>.
   <br>
   It requires a registration on this website to obtain the necessary parameters.
   <br>
   It uses the perl modules HTTP::Request, LWP::UserAgent, HTML::Parse and Digest::MD5.
   <br/><br/>
   <a name="OPENWEATHERdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; OPENWEATHER &lt;project&gt; &lt;cityCode&gt; &lt;apiKey&gt; [language]</code>
      <br>
      Example:
      <br>
      <code>define wetter OPENWEATHER projectx DE0001020 3c551bc20819c19ee88d</code>
      <br/><br/>
      To obtain the below parameter you have to create a new project on <a href="http://www.wetter.com/apps_und_mehr/website/api/projekte/">www.wetter.com</a>.
      <br/><br/>
      <li><code>&lt;project&gt;</code>
         <br>
         Name of the 'openweather' project (create with a user account on wetter.com).
      </li><br>
      <li><code>&lt;cityCode&gt;</code>
         <br>
         Code of the location for which the forecast is requested. 
         The code is part of the URL of the weather forecast page. For example <i>DE0009042</i> in:
         <br>
         <i>http://www.wetter.com/wetter_aktuell/aktuelles_wetter/deutschland/rostock/<u>DE0009042</u>.html</i>
      </li><br>
      <li><code>&lt;apiKey&gt;</code>
         <br>
         Secret key that is provided when the user creates a 'openweather' project on wetter.com.
      </li><br>
      <li><code>[language]</code>
         <br>
         Optional. Default language of weather description is German. Change with <i>en</i> to English or <i>es</i> to Spanish.
      </li><br>
      The function <code>OPENWEATHER_Html</code> creates a HTML code for a vertically arranged weather forecast.
      <br>
      Example:
      <br>
      <code>define MyForecast weblink htmlCode { OPENWEATHER_Html("MyWeather") }</code>
      <br/><br/>
   </ul>
  
   <a name="OPENWEATHERset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         The weather data are immediately polled from the website.
      </li><br>
   </ul>  

   <a name="OPENWEATHERget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; apiResponse</code>
         <br>
         Shows the response of the web site.
      </li><br>
   </ul>  
  
   <a name="OPENWEATHERattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>disable &lt;0 | 1&gt;</code>
      <br>
      Automatic update is stopped if set to 1.
      </li><br>
      <li><code>INTERVAL &lt;seconds&gt;</code>
         <br>
         Polling interval for weather data in seconds (default and smallest value is 3600 = 1 hour). 0 will stop automatic updates.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="OPENWEATHERreading"></a>
   <b>Forecast readings</b>
   <ul>
      Note! The forecast values (in brackets) have first to be selected on the project setup page on wetter.com.
      <br/>&nbsp;<br/>
      <li><b>fc</b><i>0|1|2</i><b>_...</b> - forecast values for <i>today|tomorrow|in 2 days</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>06|11|17|23</i></b> - forecast values for <i>today</i> at <i>06|11|17|23</i> o'clock</li>
      <li><b>fc</b><i>1</i><b>_temp</b><i>Min|Max</i> - <i>minimal|maximal</i> temperature for <i>tomorrow</i> in °C (tn,tx)</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min06</i> - <i>minimal</i> temperature<i>today</i> at <i>06:00</i> o'clock in °C</li>
      <li><b>fc</b><i>0</i><b>_chOfRain</b> - chance of rain <i>today</i> in % (pc)</li>
      <li><b>fc</b><i>0</i><b>_valHours</b><i>06</i> - validity period in hours of the forecast values starting at <i>06:00</i> o'clock (p)</li>
      <li><b>fc</b><i>0</i><b>_weather</b> - weather situation <i>today</i> in German (w_txt)</li>
      <li><b>fc</b><i>0</i><b>_weatherCode</b> - code of weather situation <i>today</i> (w)</li>
      <li><b>fc</b><i>0</i><b>_wday</b> - German abbreviation of week day of <i>today</i> (d)</li>
      <li><b>fc</b><i>0</i><b>_wind</b> - wind speed <i>today</i> in km/h (ws)</li>
      <li><b>fc</b><i>0</i><b>_windDir</b> - wind direction <i>today</i> in ° (degree) (wd)</li>
      <li><b>fc</b><i>0</i><b>_windDirTxt</b> - wind direction <i>today</i> in text form (wd_txt</li>
      <li>etc.</li>
   </ul>
   <br>
</ul>
</div>

=end html

=begin html_DE

<a name="OPENWEATHER"></a>
<h3>OPENWEATHER</h3>
<div> 
<ul>
   <a name="OPENWEATHERdefine"></a>
   Das Modul extrahiert  Wetterdaten über die <a href="http://www.wetter.com/apps_und_mehr/website/api/dokumentation">"openweather"-Schnittstelle (API)</a> von <a href="http://www.wetter.com">www.wetter.com</a>.
   <br/>
   Zuvor ist eine Registrierung auf der Webseite notwendig.
   <br/>
   Das Modul nutzt die Perl-Module HTTP::Request, LWP::UserAgent, HTML::Parse und Digest::MD5.
   <br>
   Für detailierte Anleitungen bitte die <a href="http://www.fhemwiki.de/wiki/OPENWEATHER"><b>FHEM-Wiki</b></a> konsultieren und ergänzen.
      <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; OPENWEATHER &lt;Projekt&gt; &lt;Ortscode&gt; &lt;apiSchlüssel&gt; [Sprache]</code>
      <br>
      Beispiel:
      <br>
      <code>define wetter OPENWEATHER projectx DE0001020 3c551bc20819c19ee88d</code>
      <br/><br/>
      Um die unteren Parameter zu erhalten, ist die  Registrierung eines neuen Projektes auf <a href="http://www.wetter.com/apps_und_mehr/website/api/projekte/">www.wetter.com</a> notwendig.
      <br/><br/>
      <li><code>&lt;Projekt&gt;</code>
         <br>
         Name des benutzerspezifischen 'openweather'-Projektes (erzeugt über ein Konto auf wetter.com).
      </li><br>
      <li><code>&lt;Ortscode&gt;</code>
         <br>
         Code des Ortes, für den die Wettervorhersage ben&ouml;tigt wird. Er kann direkt aus der Adresszeile der jeweiligen Vorhersageseite genommen werden. Zum Beispiel <i>DE0009042</i> aus:
         <br>
         <i>http://www.wetter.com/wetter_aktuell/aktuelles_wetter/deutschland/rostock/<u>DE0009042</u>.html</i>
      </li><br>
      <li><code>&lt;apiSchlüssel&gt;</code>
         <br>
         Geheimer Schlüssel, den man erhält, nachdem man ein neues 'Openweather'-Projekt auf der Website registriert hat.
      </li><br>
      <li><code>[Sprache]</code>
         <br>
         Optional. Standardsprache für die Wettersituation ist Deutsch. Mit <i>en</i> kann man zu Englisch und mit <i>es</i> zu Spanisch wechseln.
      </li><br>
      &Uuml;ber die Funktion <code>OPENWEATHER_Html</code> wird ein HTML-Code für ein vertikal arrangierte Wettervorhersage erzeugt.
      <br>
      Beispiel:
      <br>
      <code>define MyForecast weblink htmlCode { OPENWEATHER_Html("MyWeather") }</code>
      <br/><br/>
   </ul>

   <a name="OPENWEATHERset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Wetterdaten.
      </li><br>
   </ul>  
  
   <a name="OPENWEATHERget"></a>
   <b>Get</b>
   <ul>
      <br>
      <li><code>get &lt;name&gt; apiResponse</code>
         <br>
         Zeigt die Rückgabewerte der Website an.
      </li><br>
   </ul>  

   <a name="OPENWEATHERattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><code>disable &lt;0 | 1&gt;</code>
      <br>
      Automatische Aktualisierung ist angehalten, wenn der Wert auf 1 gesetzt wird.
      </li><br>
      <li><code>INTERVAL &lt;Abfrageintervall&gt;</code>
         <br>
         Abfrageintervall in Sekunden (Standard und kleinster Wert ist 3600 = 1 Stunde). 0 stoppt die automatische Aktualisierung
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br/>

   <a name="OPENWEATHERreading"></a>
   <b>Vorhersagewerte</b>
   <ul>
      Wichtig! Die Vorhersagewerte (in Klammern) müssen zuerst in den Vorhersageeinstellungen des Projektes auf wetter.com ausgewählt werden.
      <br/>&nbsp;<br/>
      <li><b>fc</b><i>0|1|2</i><b>_...</b> - Vorhersagewerte für <i>heute|morgen|übermorgen</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>06|11|17|23</i></b> - Vorhersagewerte für <i>heute</i> um <i>06|11|17|23</i> Uhr</li>
      <li><b>fc</b><i>0</i><b>_chOfRain</b> - <i>heutige</i> Niederschlagswahrscheinlichkeit in % (pc)</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min|Max</i> - <i>Mindest|Maximal</i>temperatur <i>heute</i> in °C (tn, tx)</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min06</i> - <i>Mindest</i>temperatur <i>heute</i> um <i>06:00</i> Uhr in °C</li>
      <li><b>fc</b><i>0</i><b>_valHours</b><i>06</i> - Gültigkeitszeitraum der Prognose von <i>heute</i> ab <i>6:00 Uhr</i> in Stunden (p)</li>
      <li><b>fc</b><i>0</i><b>_weather</b> - Wetterzustand <i>heute</i> (w_txt)</li>
      <li><b>fc</b><i>0</i><b>_weatherCode</b> - Code des Wetterzustand <i>heute</i> (w)</li>
      <li><b>fc</b><i>0</i><b>_wday</b> - Abkürzung des Wochentags von <i>heute</i> (d)</li>
      <li><b>fc</b><i>0</i><b>_wind</b> - Windgeschwindigkeit <i>heute</i> in km/h (ws)</li>
      <li><b>fc</b><i>0</i><b>_windDir</b> - Windrichtung <i>heute</i> in ° (Grad) (wd)</li>
      <li><b>fc</b><i>0</i><b>_windDirTxt</b> - Windrichtung <i>heute</i> in Textform (wd_txt)</li>
      <li>etc.</li>
   </ul>
   <br/>
</ul>
</div> 

=end html_DE
=cut