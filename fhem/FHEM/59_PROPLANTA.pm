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
     ,"gering" => 1
     ,"m&auml;&szlig;ig" => 2
     ,"stark" => 3
  );
  
  # 1 = Tag-ID, 2 = readingName, 3 = Tag-Type
  # Tag-Types: 1 = Number Col 2, 2 = Number Col 2-5, 3 = Number Col 2|4|6|8, 4 = Intensity-Text Col 2-5
  my @knownIDs = ( ["GS", "rad", 3] 
      ,["UV", "uv", 2]
      ,["SD", "sun", 2]
      ,["TMAX", "high_c", 2]
      ,["TMIN", "low_c", 2]
      ,["VERDUNST", "evapor", 4]
      ,["T_0", "0000_c", 2]
      ,["T_3", "0300_c", 2]
      ,["T_6", "0600_c", 2]
      ,["T_9", "0900_c", 2]
      ,["T_12", "1200_c", 2]
      ,["T_15", "1500_c", 2]
      ,["T_18", "1800_c", 2]
      ,["T_21", "2100_c", 2]
  );

# here HTML::text/start/end are overridden
sub text
{
   my ( $self, $text ) = @_;
   my $found = 0;
   my $readingName;
   if ( $curTag =~ $lookupTag )
   {
      $text =~ s/^\s+//;    # trim string
      $text =~ s/\s+$//;
   # Tag-Type 1 = Number Col 2, 2 = Number Col 2-5, 3 = Number Col 2|4|6|8, 4 = Intensity-Text Col 2-5

   # Tag-Type 2 = Number Col 2-5
      if ($curReadingType == 2) {
         if ( 1 < $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($curCol-1)."_".$curReadingName;
            if ( $text =~ m/([-,\+]?\d+\.?\d*)/ )
            {
               $text = $1;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 3 = Number Col 2|4|6|8
      elsif ($curReadingType == 3) {
         $curTextPos++;
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
   if ( $tagname eq "tr" && defined( $attr->{id} ) ) 
   {
      foreach my $r (@knownIDs) 
      { 
         if ( $$r[0] eq $attr->{id} ) 
         {
            $curReadingName = $$r[1];
            $curReadingType = $$r[2];
            $curCol = 0;
            $curTextPos = 0;
            last;
         }
      }
   };
  if ($tagname eq "td" && $curReadingType != 0) {
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
my $PROPLANTA_VERSION = "0.01";


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
   $hash->{AttrList} = "delay " . "delayCounter " . "Interval " . "disable:0,1 " . $readingFnAttributes;
}
###################################
sub PROPLANTA_Define($$)
{
   my ( $hash, $def ) = @_;
   my $name = $hash->{NAME};
   my @a    = split( "[ \t][ \t]*", $def );
   if ( int(@a) < 3 ) 
   {
      return "Wrong syntax: use define <name> PROPLANTA";
   }
   $hash->{URL} = $a[2];
   
   $hash->{STATE}          = "Initializing";
   $hash->{helper}{Timer}  = $name ;
   InternalTimer( gettimeofday() + 20, "PROPLANTA_Timer",     $hash->{helper}{Timer},     0 );
   return undef;
}
#####################################
sub PROPLANTA_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer( $hash->{helper}{TimerStatus} );
   RemoveInternalTimer( $hash->{helper}{Timer} );
   BlockingKill( $hash->{helper}{RUNNING} ) if ( defined( $hash->{helper}{RUNNING} ) );
   
   return undef;
}
#####################################
sub PROPLANTA_Set($@)
{
   my ( $hash, @a ) = @_;
   my $name    = $hash->{NAME};
   my $reUINT = '^([\\+]?\\d+)$';
   my $usage   = "Unknown argument $a[1], choose one of captureWeatherData:noArg ";
 
   return $usage if ( @a < 2 );
   
   my $cmd = lc( $a[1] );
   given ($cmd)
   {
      when ("?")
      {
         return $usage;
      }
      when ("captureweatherdata")
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
# acquires the html page of Global radiation
sub PROPLANTA_HtmlAcquire($)
{
   my ($hash)  = @_;
   my $name    = $hash->{NAME};
   return unless (defined($hash->{NAME}));
 
   my $URL = $hash->{URL};

   # abbrechen, wenn wichtig parameter nicht definiert sind
   return "" if ( !defined($URL) );
   return "" if ( $URL eq "" );

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
   my ($hash)  = @_;
   my $name    = $hash->{NAME};
   
   return unless (defined($hash->{NAME}));
   
   return if ($hash->{URL} eq "");
   
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
   my ( $name, @values ) = split( "\\|", $string );
   my $hash = $defs{$name};
   return unless (defined($hash->{NAME}));
   
   # delete the marker for running process
   delete( $hash->{helper}{RUNNING} );  

   my $rdName     = "";

   # Wetterdaten speichern
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash,"state","Connected");

   my $x = 0;
   foreach my $text (@values)
   {
      $x++;
      if ( $x % 2 == 1 )
      {
         $rdName = $text;
      } 
      else
      {
         readingsBulkUpdate( $hash, $rdName, $text );
         PROPLANTA_Log $hash, 5, "tag:$rdName value:$text";
      }
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
sub PROPLANTA_Timer($)
{
   my ($timerpara) = @_;
  # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex($timerpara,".");  # rechter punkt
   my $func  = substr $timerpara,$index+1,length($timerpara); # function extrahieren
   my $name =  substr $timerpara,0,$index; # name extrahieren     
   my $hash      = $defs{$name};
   
   return unless (defined($hash->{NAME}));
  
   $hash->{helper}{TimerInterval} = AttrVal( $name, "Interval",  3600 );
      
   PROPLANTA_Start($hash);
   
    # setup timer
   RemoveInternalTimer( $hash->{helper}{Timer} );

   InternalTimer(
     gettimeofday() + $hash->{helper}{TimerInterval},
    "PROPLANTA_Timer",
     $hash->{helper}{Timer},
     0 );  
     
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
    <code>define &lt;name&gt; PROPLANTA http://www.proplanta.de/Wetter/&lt;city&gt;-Wetter.html</code>
    <br>
     The module extracts certain weather data from the above web page.<br/>
    <br>
    <b>Parameters:</b><br>
    <ul>    
      <li><b>&lt;city&gt</b> - check www.proplanta.de if your city is known</li>
    </ul>
  </ul>
  <br>
  
  <a name="PROPLANTAset"></a>
  <b>Set-Commands</b>
  <ul>
     
     <br/>
     <code>set &lt;name&gt; captureWeatherData</code>
   	 <br/>
   	 <ul>
          The weather data are immediately polled.
     </ul><br/>
  </ul>  
  
    <a name="PROPLANTAattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>Interval</b> - poll interval for weather data in seconds (default 3600)</li>
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
=cut
