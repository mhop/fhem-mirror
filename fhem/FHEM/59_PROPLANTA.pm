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

  my %intensity = ( "keine" => 0
     ,"nein" => 0
     ,"gering" => 1
     ,"ja" => 1
     ,"m&auml;&szlig;ig" => 2
     ,"stark" => 3
  );
  
  my @knownNoneIDs = ( ["Temperatur", "temperature"] 
      ,["relative Feuchte", "humidity"]
      ,["Sichtweite", "visibility"]
      ,["Windgeschwindigkeit", "wind"]
      ,["Luftdruck", "pressure"]
      ,["Taupunkt", "dewpoint"]
  );

  # 1 = Tag-ID, 2 = readingName, 3 = Tag-Type
  # Tag-Types: 1 = Number Col 2, 2 = Number Col 2-5, 3 = Number Col 2|4|6|8, 4 = Intensity-Text Col 2-5
  my @knownIDs = ( ["GS", "rad", 3] 
      ,["UV", "uv", 2]
      ,["SD", "sun", 2]
      ,["TMAX", "high_c", 2]
      ,["TMIN", "low_c", 2]
      ,["VERDUNST", "evapor", 4]
      ,["TAUBILDUNG", "dew", 4]
      ,["BF", "frost", 4]
      ,["T_0", "t00_c", 2]
      ,["T_3", "t03_c", 2]
      ,["T_6", "t06_c", 2]
      ,["T_9", "t09_c", 2]
      ,["T_12", "t12_c", 2]
      ,["T_15", "t15_c", 2]
      ,["T_18", "t18_c", 2]
      ,["T_21", "t21_c", 2]
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
                  $curReadingType = 1;
                  last;
               }
            }
         }
      }
   # Tag-Type 1 = Number Col 2
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
            $readingName = "fc".($curCol-1)."_".$curReadingName;
            if ( $text =~ m/([-,\+]?\d+[,\.]?\d*)/ )
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
               $readingName = "fc".($curCol-1)."_".$curReadingName;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
               push( @texte, $readingName."|".$text ); 
            }
         }
      }
   # Tag-Type 4 = Intensity-Text Col 2-5
      elsif ($curReadingType == 4) {
         if ( 1 < $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($curCol-1)."_".$curReadingName;
            push( @texte, $readingName."|".$intensity{$text} ); 
         }
      }
   }
}

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

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $MODUL;
   Log3 $hash, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
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
   my @a    = split( "[ \t][ \t]*", $def );
   if ( int(@a) > 4 ) 
   {
      return "Wrong syntax: use define <name> PROPLANTA [City] [Country]";
   }
   elsif ( int(@a) == 3 ) 
   {
      $hash->{URL} = "http://www.proplanta.de/Wetter/".$a[2]."-Wetter.html";
   }

   $hash->{STATE}          = "Initializing";
   
   RemoveInternalTimer($hash);
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
         PROPLANTA_Start($hash);
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
   
   $hash->{Interval} = AttrVal( $name, "Interval",  3600 );
   
   # setup timer
   RemoveInternalTimer( $hash );
   InternalTimer(
      gettimeofday() + $hash->{Interval},
      "PROPLANTA_Start",
       $name,
       0 );  

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
   my ($string) = @_;
   my ( $name, $server ) = split( "\\|", $string );
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
   readingsBulkUpdate($hash,"state","T: ".$values{temperature}." H: ".$values{humidity}." W: ".$values{wind} );

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
  <a name="PROPLANTAdefine"></a>
  <b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; PROPLANTA &lt;City&gt;</code>
    <br>
     The module extracts certain weather data from the above web page.<br/>
    <br>
    <b>Parameters:</b><br>
    <ul>    
      <li><b>&lt;City&gt</b> - check www.proplanta.de if your city is known. The city has to start with a <b>capital</b> letter.</li>
    </ul>
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
		<li><b>Interval</b> - poll interval for weather data in seconds (default 3600)</li>
		<li><b>URL</b> - url to extract information from</li>
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
		<li><b>URL</b> - url to extract information from</li>
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
