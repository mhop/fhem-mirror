####################################################################################################
# $Id: $
#
#  59_PROPLANTA.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#  
#  Weather forecast values for next 4 days are captured from http://www.proplanta.de/Wetter/<city>-Wetter.html
#  inspired by 23_KOSTALPIKO.pm
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
####################################################################################################

###############################################
# parser for the weather data
package MyProplantaParser;
use base qw(HTML::Parser);
our @texte = ();
my $lookupTag = "span|b";
my $curTag    = "";
my $curReadingName = "";
my $curRowID = "";
my $curCol = 0;
my $curTextPos = 0;
my $curReadingType = 0;

  # 1 = Span Text, 2 = readingName, 3 = Tag-Type
  # Tag-Types: 
  #   1 = Number Col 3
  #   2 = Number Col 2-5 
  #   3 = Number Col 2|4|6|8
  #   4 = Intensity-Text Col 2-5
  #   5 = Time Col 2-5
  #   6 = Time Col 3
  #   7 = Image Col 2-5
  my @knownNoneIDs = ( ["Temperatur", "temperature", 1] 
      ,["relative Feuchte", "humidity", 1]
      ,["Sichtweite", "visibility", 1]
      ,["Windgeschwindigkeit", "wind", 1]
      ,["Luftdruck", "pressure", 1]
      ,["Taupunkt", "dewPoint", 1]
      ,["Uhrzeit", "time", 6]
  );

  # 1 = Tag-ID, 2 = readingName, 3 = Tag-Type (see above)
  my @knownIDs = (  
      ["TMAX", "tempMaxC", 2]
      ,["TMIN", "tempMinC", 2]
      ,["NW", "chOfRainDay", 2]
      ,["NW_Nacht", "chOfRainNight", 2]
      ,["BF", "frost", 4]
      ,["VERDUNST", "evapor", 4]
      ,["TAUBILDUNG", "dew", 4]
      ,["SD", "sun", 2]
      ,["UV", "uv", 2]
      ,["GS", "rad", 3]
      ,["WETTER_ID_MORGENS", "weatherMorning", 7]
      ,["WETTER_ID_TAGSUEBER", "weatherDay", 7]
      ,["WETTER_ID_ABENDS", "weatherEvening", 7]
      ,["WETTER_ID_NACHT", "weatherNight", 7]
      ,["T_0", "temp00C", 2]
      ,["T_3", "temp03C", 2]
      ,["T_6", "temp06C", 2]
      ,["T_9", "temp09C", 2]
      ,["T_12", "temp12C", 2]
      ,["T_15", "temp15C", 2]
      ,["T_18", "temp18C", 2]
      ,["T_21", "temp21C", 2]
      ,["BD_0", "cloud00", 2]
      ,["BD_3", "cloud03", 2]
      ,["BD_6", "cloud06", 2]
      ,["BD_9", "cloud09", 2]
      ,["BD_12", "cloud12", 2]
      ,["BD_15", "cloud15", 2]
      ,["BD_18", "cloud18", 2]
      ,["BD_21", "cloud21", 2]
      ,["MA", "moonRise", 5]
      ,["MU", "moonSet", 5]
  );

   my %intensity = ( "keine" => 0
     ,"nein" => 0
     ,"gering" => 1
     ,"leicht" => 1
     ,"ja" => 1
     ,"m&auml;&szlig;ig" => 2
     ,"stark" => 3
  );
  
   my %url_start =( "de" => "http://www.proplanta.de/Wetter/"
   , "at" => "http://www.proplanta.de/Agrarwetter-Oesterreich/"
   , "ch" => "http://www.proplanta.de/Agrarwetter-Schweiz/"
   , "fr" => "http://www.proplanta.de/Agrarwetter-Frankreich/"
   , "it" => "http://www.proplanta.de/Agrarwetter-Italien/"
   );

   my %url_end = ( "de" => "-Wetter.html"
   , "at" => "/"
   , "ch" => "/"
   , "fr" => "/"
   , "it" => "/"
   );

# here HTML::text/start/end are overridden
sub text
{
   my ( $self, $text ) = @_;
   my $found = 0;
   my $readingName;
   if ( $curTag =~ $lookupTag )
   {
      $curTextPos++;

      $text =~ s/^\s+//;    # trim string
      $text =~ s/\s+$//;
      $text =~ s/&#48;/0/g;  # replace 0
      
   # Tag-Type 0 = Check for readings without tag-ID
      if ($curReadingType == 0)
      {
         if ($curCol == 1 && $curTextPos == 1)
         {
            foreach my $r (@knownNoneIDs) 
            { 
               if ( $$r[0] eq $text ) 
               {
                  $curReadingName = $$r[1];
                  $curReadingType = $$r[2];
                  last;
               }
            }
         }
      }
   # Tag-Type 1 = Number Col 3
      elsif ($curReadingType == 1) 
      {
         if ( $curCol == 3 )
         {
            $readingName = $curReadingName;
            if ( $text =~ m/([-,\+]?\d+[,\.]?\d*)/ )
            {
               $text = $1;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
            $curReadingType = 0;
         }
      }
   # Tag-Type 2 = Number Col 2-5
      elsif ($curReadingType == 2) 
      {
         if ( 1 < $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($curCol-2)."_".$curReadingName;
            if ( $text =~ m/([-+]?\d+[,.]?\d*)/ )
            {
               $text = $1;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 3 = Number Col 2|4|6|8
      elsif ($curReadingType == 3) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            if ( $curTextPos % 2 == 1 ) 
            { 
               $readingName = "fc".($curCol-2)."_".$curReadingName;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
               push( @texte, $readingName."|".$text ); 
            }
         }
      }
   # Tag-Type 4 = Intensity-Text Col 2-5
      elsif ($curReadingType == 4) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($curCol-2)."_".$curReadingName;
            $text = $intensity{$text} if defined $intensity{$text};
            push( @texte, $readingName . "|" . $text ); 
         }
      }
   # Tag-Type 5 = Time Col 2-5
      elsif ($curReadingType == 5) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($curCol-2)."_".$curReadingName;
            if ( $text =~ m/([012-]?[-0-9][.:][-0-5][-0-9])/ )
            {
               $text = $1;
               $text =~ tr/./:/;    # Punkt durch Doppelpunkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 6 = Time Col 3
      elsif ($curReadingType == 6) 
      {
         if ( $curCol == 3 )
         {
            $readingName = $curReadingName;
            if ( $text =~ m/([012-]?[-0-9][.:][-0-5][-0-9])/ )
            {
               $text = $1;
               $text =~ tr/./:/;    # Punkt durch Doppelpunkt ersetzen
            } 
            push( @texte, $readingName."|".$text ); 
         }
      }
   }
}

#{"50 %" =~ m/([-+]?\d+[,.]?\d*)/;;return $1;;}

sub start
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = $tagname;
   if ( $tagname eq "tr" )
   {
      $curReadingType = 0;
      $curCol = 0;
      $curTextPos = 0;
      if ( defined( $attr->{id} ) ) 
      {
         foreach my $r (@knownIDs) 
         { 
            if ( $$r[0] eq $attr->{id} ) 
            {
               $curReadingName = $$r[1];
               $curReadingType = $$r[2];
               last;
            }
         }
      }
   }
   elsif ($tagname eq "td") 
   {
      $curCol++;
      $curTextPos = 0;
   }
   #wetterstate and icon
   elsif ($tagname eq "img" && $curReadingType == 7) 
   {
      if ( 2 <= $curCol && $curCol <= 5 )
      {
       # Alternative text
         $readingName = "fc".($curCol-2)."_".$curReadingName;
         $text = $attr->{alt};
         $text =~ s/Wetterzustand: //;
         $text =~ s/ö/oe/;
         $text =~ s/ä/ae/;
         $text =~ s/ü/ue/;
         $text =~ s/ß/ss/;
         push( @texte, $readingName . "|" . $text ); 
       # Image URL
         push( @texte, $readingName."Icon" . "|" . $attr->{src} ); 
      }
   }
}

sub end
{
   $curTag = "";

   if ( $tagname eq "tr" ) 
   {       
      $curReadingType = 0 
   };
}


##############################################
package main;
use strict;
use feature qw/say switch/;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

use vars qw(%defs);
my $MODUL          = "PROPLANTA";
my $modulVersion = "1.01";


########################################
sub PROPLANTA_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/PROPLANTA_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}
###################################
sub PROPLANTA_Initialize($)
{
   my ($hash) = @_;
   $hash->{DefFn}    = "PROPLANTA_Define";
   $hash->{UndefFn}  = "PROPLANTA_Undef";
   $hash->{SetFn}    = "PROPLANTA_Set";
   $hash->{AttrList} = "INTERVAL URL disable:0,1 " . $readingFnAttributes;
}
###################################
sub PROPLANTA_Define($$)
{
   my ( $hash, $def ) = @_;
   my $name = $hash->{NAME};
   my $lang = "";
   my @a    = split( "[ \t][ \t]*", $def );
   
   return "Wrong syntax: use define <name> PROPLANTA [City] [CountryCode]" if int(@a) > 4;

   $lang = "de" if int(@a) == 3;
   $lang = lc( $a[3] ) if int(@a) == 4;

   if ( $lang ne "")
   {
      return "Wrong country code '$lang': use " . join(" | ",  keys( %url_start ) ) unless defined( $url_start{$lang} );
      $hash->{URL} = $url_start{$lang} . $a[2] . $url_end{$lang};
   }

   $hash->{STATE}          = "Initializing";
   $hash->{LOCAL}          = 0;
   $hash->{INTERVAL}       = 3600;
   $hash->{fhem}{modulVersion} = $modulVersion;
   
   RemoveInternalTimer($hash);
   
   #Get first data after 12 seconds
   InternalTimer( gettimeofday() + 12, "PROPLANTA_Start", $hash, 0 );

   return undef;
}
#####################################
sub PROPLANTA_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer( $hash );
   
   BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
   return undef;
}
#####################################
sub PROPLANTA_Set($@)
{
   my ( $hash, @a ) = @_;
   my $name    = $hash->{NAME};
   my $reUINT = '^([\\+]?\\d+)$';
   my $usage   = "Unknown argument $a[1], choose one of update:noArg ";
 
   return $usage if ( @a < 2 );
   
   my $cmd = lc( $a[1] );
   given ($cmd)
   {
      when ("?")
      {
         return $usage;
      }
      when ("update")
      {
         PROPLANTA_Log $hash, 3, "set command: " . $a[1];
         $hash->{LOCAL} = 1;
         PROPLANTA_Start($hash);
         $hash->{LOCAL} = 0;
      }
       default
      {
         return $usage;
      }
   }
   return;
}

#####################################
# acquires the html page
sub PROPLANTA_HtmlAcquire($)
{
   my ($hash)  = @_;
   my $name    = $hash->{NAME};
   return unless (defined($hash->{NAME}));
 
   my $URL = AttrVal( $name, 'URL', "" );
   $URL = $hash->{URL} if $URL eq "";

   # abbrechen, wenn wichtige parameter nicht definiert sind
   return "" if ( !defined($URL) );
   return "" if ( $URL eq "" );

   PROPLANTA_Log $hash, 5, "Start polling of ".$URL;

   my $err_log  = "";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, timeout => 3 );
   my $header   = HTTP::Request->new( GET => $URL );
   my $request  = HTTP::Request->new( 'GET', $URL, $header );
   my $response = $agent->request($request);
   $err_log = "Can't get $URL -- " . $response->status_line
     unless $response->is_success;
     
   if ( $err_log ne "" )
   {
      PROPLANTA_Log $hash, 1, "Error: $err_log";
      return "";
   }

   return $response->content;
}


#####################################
sub PROPLANTA_Start($)
{
   my ($hash) = @_;
   my $name   = $hash->{NAME};
   
   return unless (defined($hash->{NAME}));
   
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL",  $hash->{INTERVAL} );
   
   if(!$hash->{LOCAL} && $hash->{INTERVAL} > 0) {
    # set up timer if automatically call
      RemoveInternalTimer( $hash );
      InternalTimer(gettimeofday() + $hash->{INTERVAL}, "PROPLANTA_Start", $hash, 1 );  
      return undef if( AttrVal($name, "disable", 0 ) == 1 );
   }
   
   if ( AttrVal( $name, 'URL', '') eq '' && not defined( $hash->{URL} ) )
   {
      PROPLANTA_Log $hash, 3, "missing URL";
      return;
   }
  
   $hash->{helper}{RUNNING_PID} =
           BlockingCall( 
           "PROPLANTA_Run",   # callback worker task
           $name,                    # name of the device
           "PROPLANTA_Done",  # callback result method
           120,                       # timeout seconds
           "PROPLANTA_Aborted", #  callback for abortion
           $hash );                 # parameter for abortion
}

#####################################
sub PROPLANTA_Run($)
{
   my ($name) = @_;
   my $ptext=$name;
   
   return unless ( defined($name) );
   
   my $hash = $defs{$name};
   return unless (defined($hash->{NAME}));
   
   while (1)
   {
      # acquire the html-page
      my $response = PROPLANTA_HtmlAcquire($hash); 
      last if ($response eq "");
 
      my $parser = MyProplantaParser->new;
      @MyProplantaParser::texte = ();
      # parsing the complete html-page-response, needs some time
      # only <span> tags will be regarded   
      $parser->parse($response);
      PROPLANTA_Log $hash, 4, "parsed terms:" . @MyProplantaParser::texte;
      
      # pack the results in a single string
      if (@MyProplantaParser::texte > 0) 
      {
         $ptext .= "|". join('|', @MyProplantaParser::texte);
      }
      PROPLANTA_Log $hash, 4, "parsed values:" . $ptext;
      
      last;
   }
   return $ptext;
}
#####################################
# asyncronous callback by blocking
sub PROPLANTA_Done($)
{
   my ($string) = @_;
   return unless ( defined($string) );
   
   # all term are separated by "|" , the first is the name of the instance
   my ( $name, %values ) = split( "\\|", $string );
   my $hash = $defs{$name};
   return unless ( defined($hash->{NAME}) );
   
   # delete the marker for RUNNING_PID process
   delete( $hash->{helper}{RUNNING_PID} );  

   # Wetterdaten speichern
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "state", sprintf "T: %.1f H: %.1f W: %.1f P: %.1f ", $values{temperature}, $values{humidity}, $values{wind}, $values{pressure} );

   my $x = 0;
   while (my ($rName, $rValue) = each(%values) )
   {
      readingsBulkUpdate( $hash, $rName, $rValue );
      PROPLANTA_Log $hash, 5, "reading:$rName value:$rValue";
   }

   readingsEndUpdate( $hash, 1 );
}
#####################################
sub PROPLANTA_Aborted($)
{
   my ($hash) = @_;
   delete( $hash->{helper}{RUNNING_PID} );
}


##################################### 
1;

=pod
=begin html

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<ul>
  The module extracts certain weather data from <a href="http://www.proplanta.de">www.proplanta.de</a>.
  <br>
   <i>Required perl moduls: HTTP::Request and LWP::UserAgent</i>
  <br>
  &nbsp;
  <br>
  <a name="PROPLANTAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PROPLANTA [City] [CountryCode]</code>
    <br>
    Example: <code>define wetter PROPLANTA Bern ch</code>
    <br>&nbsp;
    <li><code>[City]</code> <i>(optional)</i>
      <br>
      City must be selectable on www.proplanta.de. Pay attention to the <b>Capital</b> letters in the city names.
    </li><br>
    <li><code>[CountryCode]</code> <i>(optional)</i>
      <br>
      Possible values: de (default), at, ch, fr, it 
    </li><br>
  </ul>
  <br>
  
  <a name="PROPLANTAset"></a>
  <b>Set</b>
  <ul>
     <br>
     <li><code>set &lt;name&gt; update</code>
      <br>
      The weather data are immediately polled from the website.
     </li><br>
  </ul>  
  
    <a name="PROPLANTAattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      <li><code>Interval</code>
      <br>
      poll interval for weather data in seconds (default 3600 = 1 hour)
      </li><br>
      <li><code>URL</code>
      <br>
      URL to extract information from. Overwrites the values in the 'define' term.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br><br>

   <a name="PROPLANTAreading"></a>
   <b>Forecast readings</b>
   <ul>
      <li><b>fc</b><i>0</i><b>_chOfRainDay</b><i>15</i><b>C</b> - chance of rain by day <i>today</i> in %</li>
      <li><b>fc</b><i>0</i><b>_chOfRainNight</b><i>15</i><b>C</b> - chance of rain by night  <i>today</i> in %</li>
      <li><b>fc</b><i>0</i><b>_cloud</b><i>15</i><b>C</b> - cloud coverage <i>15:00</i> <i>today</i> in %</li>
      <li><b>fc</b><i>0</i><b>_dew</b> - dew formation <i>today</i> (0=none, 1=small, 2=medium, 3=strong)</li>
      <li><b>fc</b><i>0</i><b>_evapor</b> - evaporation <i>today</i> (0=none, 1=small, 2=medium, 3=strong)</li>
      <li><b>fc</b><i>0</i><b>_frost</b> - ground frost <i>today</i> (0=no, 1=yes)</li>
      <li><b>fc</b><i>0</i><b>_moonRise</b> - moon rise <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_moonSet</b> - moon set <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_rad</b> - global radiation <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_sun</b> - relative sun shine duration <i>today</i> in % (between sun rise and set)</li>
      <li><b>fc</b><i>0</i><b>_tempMaxC</b> - maximal temperature <i>today</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_tempMaxC</b> - minimal temperatur <i>today</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>15</i><b>C</b> - temperatur at <i>15:00</i> <i>today</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_uv</b> - UV-Index <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i> - weather situation by <i>day</i> <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i><b>Icon</b> - icon of weather situation by <i>day</i> <i>today</i></li>
      <li>etc.</li>
   </ul>
   <br>
   <br>
</ul>

=end html

=begin html_DE

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<ul>
  <a name="PROPLANTAdefine"></a>
  <b>Define</b>
  <ul>
    <br>
    <code>define &lt;Name&gt; PROPLANTA [Stadt] [L&auml;ndercode]</code>
    <br>
     Das Modul extrahiert bestimmte Wetterdaten von der website www.proplanta.de.<br/>
    <br>
    <ul>    
      <li><code>[Stadt]</code> <i>(optional)</i>
      <br>
      Die Stadt muss auf www.proplanta.de ausw&auml;hlbar sein. Wichtig!! Auf die <b>gro&szig;en</b> Anfangsbuchstaben achten.
      </li><br>
      <li><code>[L&auml;ndercode]</code> <i>(optional)</i>
      <br>
      M&ouml;gliche Werte: de (Standard), at, ch, fr, it
      </li><br>
    </ul>
  </ul>
  <br>
  
  <a name="PROPLANTAset"></a>
  <b>Set</b>
  <ul>
     <li><code>set &lt;name&gt; update</code>
     <br>
          Liest die Wetterdaten sofort von der Webseite aus.
     </li><br>
  </ul>  
  
    <a name="PROPLANTAattr"></a>
	<b>Attribute</b><br/><br/>
	<ul>
      <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
      <br>
      Abfrageinterval in Sekunden (Standard 3600 = 1 Stunde)
      </li><br>
      <li><code>URL &lt;Internetadresse&gt;</code>
      <br>
      Internetadresse, von der die Daten ausgelesen werden (&uuml;berschreibt die Werte im 'define'-Term
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>
	
    <a name="PROPLANTAreading"></a>
	<b>Vorhersagewerte</b><br/><br/>
   <ul>
      <li><b>fc</b><i>0</i><b>_chOfRainDay</b><i>15</i><b>C</b> - Niederschlagsrisiko tags&uuml;ber <i>heute</i> in %</li>
      <li><b>fc</b><i>0</i><b>_chOfRainNight</b><i>15</i><b>C</b> - Niederschlagsrisiko nachts  <i>heute</i> in %</li>
      <li><b>fc</b><i>0</i><b>_cloud</b><i>15</i><b>C</b> - Wolkenbedeckungsgrad <i>15:00</i> Uhr <i>heute</i> in %</li>
      <li><b>fc</b><i>0</i><b>_dew</b> - Taubildung <i>heute</i> (0=keine, 1=leicht, 2=m&auml;&szig;ig, 3=stark)</li>
      <li><b>fc</b><i>0</i><b>_evapor</b> - Verdunstung <i>heute</i> (0=keine, 1=gering, 2=m&auml;&szig;ig, 3=stark)</li>
      <li><b>fc</b><i>0</i><b>_frost</b> - Bodenfrost <i>heute</i> (0=nein, 1=ja)</li>
      <li><b>fc</b><i>0</i><b>_moonRise</b> - Mondaufgang <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_moonSet</b> - Monduntergang <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_rad</b> - Globalstrahlung <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_sun</b> - relative Sonnenscheindauer <i>heute</i> in % (zwischen Sonnenauf- und -untergang)</li>
      <li><b>fc</b><i>0</i><b>_tempMaxC</b> - Maximaltemperatur <i>heute</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_tempMaxC</b> - Minimaltemperatur <i>heute</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>15</i><b>C</b> - Temperatur <i>15:00</i> Uhr <i>heute</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_uv</b> - UV-Index <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i> - Wetterzustand <i>tagsüber</i> <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i><b>Icon</b> - Icon Wetterzustand <i>tagsüber</i> <i>heute</i></li>
      <li>etc.</li>
   </ul>
   <br><br>
</ul>

=end html_DE
=cut