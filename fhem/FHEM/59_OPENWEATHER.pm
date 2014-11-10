###############################################################
# $Id: $
#
#  59_OPENWEATHER.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
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
my $day         = -1;
my $time        = "";
# here HTML::text/start/end are overridden

%knownTags = ( tn => "tempMin"
   , tx => "tempMax"
   , w => "weatherCode"
   , w_txt => "weather"
   , ws => "wind"
   , wd => "windDir"
   , wd_txt => "windDirTxt"
   , pc => "presChange"
   , p => "valHours"
);

sub text
{
   my ( $self, $text ) = @_;

   if ($curTag eq "name")
   {
      $fcReadings{"city"} = $text ; 
   }
   elsif ($curTag eq "post_code")
   {
      $fcReadings{"postCode"} = $text ; 
   }
   else
   {
      my $rName = $knownTags{$curTag};
      if (defined $rName && $day >= 0)
      {
         #Umlaute entfernen
         if ($curTag eq "w_txt") {$text =~ s/ö/oe/; $text =~ s/ä/ae/; $text =~ s/ü/ue/; $text =~ s/ß/ss/;}         
         $fcReadings{"fc".$day."_".$rName.$time} = $text ; 
      }
   }
}

sub start
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = $tagname;
   
   if ($tagname eq "forecast")
   {
      $day=-1;
   }
   if ($tagname eq "date")
   {
      $day++;
      $time = "";
   }
   if ($tagname eq "time")
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
use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use LWP::UserAgent;
use HTTP::Request;
use HTML::Parser;

# Modul Version for remote debugging
  my $MODUL = "OPENWEATHER";
  my $modulVersion = '$Id $';

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
                .$readingFnAttributes;

} # end OPENWEATHER_Initialize


sub ##########################################
OPENWEATHER_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);

  return "Usage: define <name> OPENWEATHER <project> <cityCode> <apiKey>" if(@args <5 || @args >5);

  my $name = $args[0];
  my $interval = 3600;

  $hash->{NAME} = $name;

  $hash->{STATE}      = "Initializing" if $interval > 0;
  $hash->{STATE}      = "Manual mode" if $interval == 0;
  $hash->{INTERVAL}   = $interval;
  $hash->{PROJECT}       = $args[2];
  $hash->{CITYCODE}       = $args[3];
  $hash->{APIKEY}       = $args[4];
  $hash->{CREDIT}    = "Powered by wetter.com";
  RemoveInternalTimer($hash);
  #Get first data after 13 seconds
  InternalTimer(gettimeofday() + 13, "OPENWEATHER_Start", $hash, 0) if $interval > 0;

  $hash->{fhem}{modulVersion} = '$ID $';
  OPENWEATHER_Log $hash, 5, "OPENWEATHER.pm version is " . $hash->{fhem}{modulVersion};
 
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
   if ($cmd eq "set") 
   {
      if ($aName eq "1allowSetParameter") 
      {
         eval { qr/$aVal/ };
         if ($@) 
         {
            OPENWEATHER_Log $name, 3, "Invalid allowSetParameter in attr $name $aName $aVal: $@";
            return "Invalid allowSetParameter $aVal";
         }
      }
   }
   
   return undef;
} # OPENWEATHER_Attr ende


sub ##########################################
OPENWEATHER_Set($$@) 
{
   my ($hash, $name, $cmd, $val) = @_;
   my $resultStr = "";
   
   if($cmd eq 'update') 
   {
      $hash->{LOCAL} = 1;
      OPENWEATHER_Start($hash);
      $hash->{LOCAL} = 0;
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
  
  if ($cmd eq "apiResponse") 
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
         $message =  sprintf( "Runtime: %.2f s\n_________________\n\n", $time) . $message;
      }
      return $message;
      
  }
  # elsif ($cmd eq "jsonAnalysis") {
      # my $time = gettimeofday();
      # $hash->{fhem}{jsonInterpreter} = "";
      # $result = OPENWEATHER_Run $name;
      # my @a = split /\|/, $result;
      # if ($a[1]==0) { return $a[2]; }
      
      # $result = OPENWEATHER_Done $result;
      # my @a = split /\|/, $result;
      # $time = gettimeofday() - $time;
      # $message = sprintf( "Runtime: %.2f s\n_________________\n\n", $time);
      # $message .= decode_base64($result); #$a[2]);
      # return $message;
  # }
  
  my $list = "apiResponse:noArg";
  return "Unknown argument $cmd, choose one of $list";

} # end OPENWEATHER_Get


# Starts the data capturing and sets the new timer
sub ##########################################
OPENWEATHER_Start($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   
   
   if(!$hash->{LOCAL} && $hash->{INTERVAL} > 0) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "OPENWEATHER_Start", $hash, 1);
      return undef if( AttrVal($name, "disable", 0 ) == 1 );
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
   my $projectName = $hash->{PROJECT};
   my $apiKey = $hash->{APIKEY};
   my $cityCode = $hash->{CITYCODE};

   my $checkSum = md5_hex( $projectName . $apiKey . $cityCode );
   
   my $URL = 'http://api.wetter.com/forecast/weather';
   $URL   .= '/city/' . $cityCode;
   $URL   .= '/project/' . $projectName;
   $URL   .= '/cs/' . $checkSum;
   
   $hash->{URL}   = $URL;

   OPENWEATHER_Log $hash, 5, "Start capturing data from $URL";

   my $err_log  = "";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
   my $request  = HTTP::Request->new( GET => $URL );
   my $response = $agent->request($request);
   $err_log = "Can't get $URL -- " . $response->status_line
     unless $response->is_success;
     
   if ( $err_log ne "" )
   {
      return "$name|0|" . $response->status_line;
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
   my $returnStr ="";
  
   delete($hash->{helper}{RUNNING_PID});

   readingsBeginUpdate($hash);

   if ( $success == 1 ){
      my $message = decode_base64($result);

      OPENWEATHER_Log $hash, 5, "Start parsing of XML data.";
      my $parser = MyOPENWEATHERParser->new;
      %MyOPENWEATHERParser::fcReadings = ();
      $MyOPENWEATHERParser::day        = -1;
      $MyOPENWEATHERParser::time       = "";
      $parser->parse($message);

      OPENWEATHER_Log $hash, 4, "Captured values: " . keys (%MyOPENWEATHERParser::fcReadings);
 
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
   else
   {
      readingsBulkUpdate($hash, "lastConnection", $result);
      readingsBulkUpdate($hash, "state", $result);
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

} # end OPENWEATHER_UpdateAborted

1;

=pod
=begin html

<a name="OPENWEATHER"></a>
<h3>OPENWEATHER</h3>
<div  style="width:800px"> 
<ul>
   The module extracts weather data via the <a href="http://www.wetter.com/apps_und_mehr/website/api/dokumentation">openweather API</a> of <a href="http://www.wetter.com">www.wetter.com</a>.
   <br>
   It requires a registration on this website to obtain the necessary parameters.
   <br>
   It requires the perl moduls HTTP::Request, LWP::UserAgent, HTML::Parse and Digest::MD5.
   <br/><br/>
   <a name="OPENWEATHERdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; OPENWEATHER &lt;project&gt; &lt;cityCode&gt; &lt;apiKey&gt; </code>
      <br>
      Example: <code>define wetter OPENWEATHER beispielprojekt DE0001020 3c551bc20819c19ee88c9ec94280a61d</code>
      <br>&nbsp;
      To obtain the below parameter a requistration of a personal project is necessary on <a href="http://www.wetter.com/apps_und_mehr/website/api/projekte/">www.wetter.com</a>.
      <br>
      <li><code>&lt;project&gt;</code>
         <br>
         Name of the users 'openweather' project (create with a user account on the website).
      </li><br>
      <li><code>&lt;cityCode&gt;</code>
         <br>
         Code of the location for which the forecast is requested. Can be obtained from the URL of the weather forecast page of the concerned city.
      </li><br>
      <li><code>&lt;apiKey&gt;</code>
         <br>
         Secret key the can be obtain after the users 'openweather' project is created on the web site.
      </li><br>
   </ul>
   <br>
  
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
      <li><code>set &lt;name&gt; apiResponse</code>
         <br>
         Shows the response of the web site.
      </li><br>
   </ul>  
  
   <a name="OPENWEATHERattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="OPENWEATHERreading"></a>
   <b>Forecast readings</b>
   <ul>
      <br>
      <li><b>fc</b><i>0|1|2</i><b>_...</b> - forecast values for <i>today|tommorrow|in 2 days</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>06|11|17|23</i></b> - forecast values for <i>today</i> at <i>06|11|17|23</i> o'clock</li>
      <li><b>fc</b><i>1</i><b>_temp</b><i>Min|Max</i> - <i>minimal|maximal</i> temperature <i>tommorrow</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min06</i> - <i>minimal</i> temperatur <i>today</i> at <i>06:00</i> o'clock in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_presChange</b> - atmospheric pressure change <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_valHours</b><i>06</i> - validity period of the forecast values in hours</li>
      <li><b>fc</b><i>0</i><b>_weather</b> - weather situation <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_wind</b> - wind speed <i>today</i> in km/h</li>
      <li><b>fc</b><i>0</i><b>_windDir</b> - wind direction <i>today</i> in &deg;</li>
      <li><b>fc</b><i>0</i><b>_windDirTxt</b> - wind direction <i>today</i> in text form</li>
      <li>etc.</li>
   </ul>
   <br>
</ul>
</div>

=end html

=begin html_DE

<a name="OPENWEATHER"></a>
<h3>OPENWEATHER</h3>
<div  style="width:800px"> 
<ul>
   <a name="OPENWEATHERdefine"></a>
   Das Modul extrahiert  Wetterdaten &uuml;ber die <a href="http://www.wetter.com/apps_und_mehr/website/api/dokumentation">"openweather"-Schnittstelle</a> von <a href="http://www.wetter.com">www.wetter.com</a>.
   Zuvor ist eine Registrierung auf der Webseite notwendig.
   <br/>
   Das Modul ben&ouml;tigt die Perlmodule HTTP::Request, LWP::UserAgent, HTML::Parse und Digest::MD5.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; OPENWEATHER &lt;Projekt&gt; &lt;Ortscode&gt; &lt;apiSchl&uuml;ssel&gt; </code>
      <br>
      Beispiel: <code>define wetter OPENWEATHER beispielprojekt DE0001020 3c551bc20819c19ee88c9ec94280a61d</code>
      <br>
      Um die unteren Paramter zu erhalten, ist die  Registrierung eines eigenen Projektes auf <a href="http://www.wetter.com/apps_und_mehr/website/api/projekte/">www.wetter.com</a> notwendig.
      <li><code>&lt;Projekt&gt;</code>
         <br>
         Name des benutzerspezifischen 'Openweather'-Projektes (erzeugt &uuml;ber ein Benutzerkonto auf der Website).
      </li><br>
      <li><code>&lt;Ortscode&gt;</code>
         <br>
         Code des Ortes f&uuml;r den die Wettervorhersage ben&ouml;tigt wird. Er kann direkt aus der Adresszeile der jeweiligen Vorhersageseite genommen werden.
      </li><br>
      <li><code>&lt;apiSchl&uuml;ssel&gt;</code>
         <br>
         Geheimer Schl&uuml;ssel, den man erh&auml;lt, nachdem man ein neues 'Openweather'-Projekt auf der Website registriert hat.
      </li><br>
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
      <li><code>set &lt;name&gt; apiResponse</code>
         <br>
         Zeigt die R&uuml;ckgabewerte der Website an.
      </li><br>
   </ul>  

   <a name="OPENWEATHERattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br/>

   <a name="OPENWEATHERreading"></a>
   <b>Vorhersagewerte</b>
   <ul>
      <br>
      <li><b>fc</b><i>0|1|2</i><b>_...</b> - Vorhersagewerte f&uuml;r <i>heute|morgen|&uuml;bermorgen</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>06|11|17|23</i></b> - Vorhersagewerte f&uuml;r <i>heute</i> um <i>06|11|17|23</i> Uhr</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min|Max</i> - <i>Mindest|Maximal</i>temperatur <i>heute</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min06</i> - <i>Mindest</i>temperatur <i>heute</i> um <i>06:00</i> Uhr in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_presChange</b> - <i>heutige</i> &Auml;nderung des Luftdruckes</li>
      <li><b>fc</b><i>0</i><b>_valHours</b><i>06</i> - G&uuml;ltigkeitszeitraum der Prognose von <i>heute 6:00 Uhr</i> in Stunden</li>
      <li><b>fc</b><i>0</i><b>_weather</b> - Wetterzustand <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_wind</b> - Windgeschwindigkeit <i>heute</i> in km/h</li>
      <li><b>fc</b><i>0</i><b>_windDir</b> - Windrichtung <i>heute</i> in &deg;</li>
      <li><b>fc</b><i>0</i><b>_windDirTxt</b> - Windrichtung <i>heute</i> in Textform</li>
      <li>etc.</li>
   </ul>
   <br><br>
</ul>
</div> 

=end html_DE
=cut