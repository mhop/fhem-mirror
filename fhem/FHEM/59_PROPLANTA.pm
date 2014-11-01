# $Id: $
####################################################################################################
#
#	23_PROPLANTA.pm
#  
#  Weather forecast values for next 4 days are captured from http://www.proplanta.de/Wetter/<city>-Wetter.html
#  inspired by 23_KOSTALPIKO.pm
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

  my %intensity = ( "keine" => 0
     ,"nein" => 0
     ,"gering" => 1
     ,"ja" => 1
     ,"m&auml;&szlig;ig" => 2
     ,"stark" => 3
  );
  
  # 1 = Span Text, 2 = readingName, 3 = Tag-Type
  # Tag-Types: 
  #   1 = Number Col 3
  #   2 = Number Col 2-5 
  #   3 = Number Col 2|4|6|8
  #   4 = Intensity-Text Col 2-5
  #   5 = Time Col 2-5
  #   6 = Time Col 3
  my @knownNoneIDs = ( ["Temperatur", "temperature", 1] 
      ,["relative Feuchte", "humidity", 1]
      ,["Sichtweite", "visibility", 1]
      ,["Windgeschwindigkeit", "wind", 1]
      ,["Luftdruck", "pressure", 1]
      ,["Taupunkt", "dewPoint", 1]
      ,["Uhrzeit", "time", 6]
  );

  # 1 = Tag-ID, 2 = readingName, 3 = Tag-Type (see above)
  my @knownIDs = ( ["GS", "rad", 3] 
      ,["UV", "uv", 2]
      ,["SD", "sun", 2]
      ,["TMAX", "tempMaxC", 2]
      ,["TMIN", "tempMinC", 2]
      ,["VERDUNST", "evapor", 4]
      ,["TAUBILDUNG", "dew", 4]
      ,["BF", "frost", 4]
      ,["MA", "moonRise", 5]
      ,["MU", "moonSet", 5]
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
         if ( 1 < $curCol && $curCol <= 5 )
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
         if ( 1 < $curCol && $curCol <= 5 )
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
            if ( $text =~ m/([012]?\d[.:][0-5]\d)/ )
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
            if ( $text =~ m/([012]?\d[.:][0-5]\d)/ )
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
   };
  if ($tagname eq "td") {
      $curCol++;
      $curTextPos = 0;
   };
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
my $PROPLANTA_VERSION = "1.01";


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
   $hash->{AttrList} = "Interval URL disable:0,1 " . $readingFnAttributes;
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
   
   BlockingKill( $hash->{helper}{RUNNING} ) if ( defined( $hash->{helper}{RUNNING} ) );
   
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
   
   $hash->{INTERVAL} = AttrVal( $name, "Interval",  $hash->{INTERVAL} );
   
   if(!$hash->{LOCAL} && $hash->{INTERVAL} > 0) {
      # setup timer
      RemoveInternalTimer( $hash );
      InternalTimer(gettimeofday() + $hash->{INTERVAL}, "PROPLANTA_Start", $hash, 1 );  
      return undef if( AttrVal($name, "disable", 0 ) == 1 );
   }
   
   if ( AttrVal( $name, 'URL', '') eq '' && not defined( $hash->{URL} ) )
   {
      PROPLANTA_Log $hash, 3, "missing URL";
      return;
   }
  
   $hash->{helper}{RUNNING} =
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
   
   # delete the marker for running process
   delete( $hash->{helper}{RUNNING} );  

   # Wetterdaten speichern
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash, "state", sprintf "T: %.1f H: %.1f W: %.1f P: %.1f ", $values{temperature}, $values{humidity}, $values{wind}, $values{pressure} );

   my $x = 0;
   while (my ($rName, $rValue) = each(%values) )
   {
      readingsBulkUpdate( $hash, $rName, $rValue );
      PROPLANTA_Log $hash, 5, "tag:$rName value:$rValue";
   }

   readingsEndUpdate( $hash, 1 );
}
#####################################
sub PROPLANTA_Aborted($)
{
   my ($hash) = @_;
   delete( $hash->{helper}{RUNNING} );
}


##################################### 
1;

=pod
=begin html

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<ul style="width:800px">
  The module extracts certain weather data from www.proplanta.de.<br/>
  <a name="PROPLANTAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PROPLANTA [City] [CountryCode]</code>
    <br>&nbsp;
    <li><code>[City]<code> (optional)
      <br>
      Check www.proplanta.de if your city is known. The city has to start with a <b>capital</b> letter.
    </li><br>
    <li><code>[CountryCode]<code> (optional)
      <br>
      Possible values: de (default), at, ch, fr, it 
    </li><br>
  </ul>
  <br>
  
  <a name="PROPLANTAset"></a>
  <b>Set-Commands</b>
  <ul>
     
     <br/>
     <code>set &lt;name&gt; update</code>
   	 <br/>
   	 <ul>
          The weather data are immediately polled from the website.
     </ul><br/>
  </ul>  
  
    <a name="PROPLANTAattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
      <li><code>Interval</code>
      <br>
      poll interval for weather data in seconds (default 3600)
      </li><br>
      <li><code>URL</code>
      <br>
      URL to extract information from. Overwrites the values in the 'define' term.
      </li><br>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>
	
    <a name="PROPLANTAreading"></a>
	<b>Generated Readings</b><br/><br/>
	<ul>
		<li><b>fc?_uv</b> - UV index</li>
		<li><b>fc?_sun</b> - sunshine duration</li>
	</ul>
	<br/><br/>	

</ul>

=end html

=begin html_DE

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<ul style="width:800px">
  <a name="PROPLANTAdefine"></a>
  <b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; PROPLANTA &lt;Stadt&gt;</code>
    <br>
     Das Modul extrahiert bestimmte Wetterdaten von der website www.proplanta.de.<br/>
    <br>
    <b>Parameters:</b><br>
    <ul>    
      <li><b>&lt;Stadt&gt</b> - Prüfe auf www.proplanta.de, ob die Stadt bekannt ist. Die Stadt muss mit <b>großem</b> Anfangsbuchstaben anfangen.</li>
    </ul>
  </ul>
  <br>
  
  <a name="PROPLANTAset"></a>
  <b>Set</b>
  <ul>
     
     <br/>
     <code>set &lt;name&gt; update</code>
   	 <br/>
   	 <ul>
          The weather data are immediately polled from the website.
     </ul><br/>
  </ul>  
  
    <a name="PROPLANTAattr"></a>
	<b>Attribute</b><br/><br/>
	<ul>
		<li><b>Interval</b> - poll interval for weather data in seconds (default 3600)</li>
		<li><b>URL</b> - url to extract the weather data from</li>
		<br/>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br/><br/>
	
    <a name="PROPLANTAreading"></a>
	<b>Generated Readings/Events</b><br/><br/>
	<ul>
		<li><b>fc?_uv</b> - the UV Index</li>
		<li><b>fc?_sun</b> - the sunshine duration</li>
	</ul>
	<br/><br/>	

</ul>

=end html_DE
=cut
