##############################################
# $Id$
#
# 97_TrashCal.pm
#
# written by Tobias Faust 2013-10-23
# e-mail: tobias dot faust at online dot de
#
##############################################  
#
##############################################
#
#   Log-Levels
#    0 - server start/stop
#    1 - error messages or unknown packets
#    2 - major events/alarms.
#    3 - commands sent out will be logged.
#    4 - you'll see whats received by the different devices.
#    5 - debugging.

##############################################


###############################################
# parser for the Trash
package MyTrashCalParser;
use base qw(HTML::Parser);
our %dates = ();
my $lookupTag = "div";
my $curTag    = "";
my $category = "--";

# here HTML::text/start/end are overridden
sub text
{
   my ( $self, $text ) = @_;
   if ( $curTag eq $lookupTag )
   {
      #print "MyTrashCalParser_Text: original: $text \n";
      $text =~ s/[^0-9]*([0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4}).*/$1/;
      #print "MyTrashCalParser_Text: Modifiziert: $text \n";

      if($category ne "" && $text =~ m/([0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4})/) {
        push(@{$dates{$category}}, $text);
        #print "MyTrashCalParser_Text: Values of $category: ". keys(%{$data{$category}}) ."\n";
      }

   } elsif ($curTag eq "h3") {
      $category = $text;
      #print "MyTrashCalParser_Text: neue Kategorie: $text \n";
   }
}

sub start
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = $tagname;
   #print "MyTrashCalParser_Start: $tagname, $attr, $attrseq, $origtext";
}

sub end
{
   $curTag = "";
   #print "MyTrashCalParser_End: ----- done -----";
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

# use vars qw(%attr);
use vars qw(%defs);
my $MODUL          = "TrashCal";


###################################
sub TrashCal_Initialize($)
{
   my ($hash) = @_;
   $hash->{DefFn}    = "TrashCal_Define";
   $hash->{UndefFn}  = "TrashCal_Undef";
   $hash->{AttrList} = " TrashCal_Link". 
                       " TrashCal_Interval". 
                       " disable:0,1".
                       " ".$readingFnAttributes;
}
###################################
sub TrashCal_Define($$)
{
   my ( $hash, $def ) = @_;
   my $name = $hash->{NAME};
   my @a    = split( "[ \t][ \t]*", $def );
   my $type = $a[2];
   if ( int(@a) < 3 )
   {
      return "Wrong syntax: use define <name> TrashCal <type>";
   }

   my $nt = time;
   $nt += 20; # aquire in 20sec
   my @lt = localtime($nt);
   my $ntm = sprintf("%02d.%02d.%04d %02d:%02d:%02d", $lt[3], ($lt[4]+1), ($lt[5]+1900), $lt[2], $lt[1], $lt[0]);
   $hash->{TriggerTime_FMT} = $ntm;
   $hash->{TriggerTime} = $nt;

   InternalTimer( $nt, "TrashCal_Timer", $hash, 0 );
   Log3 $hash, 4, "TrashCal_Define: InternalTimer auf in 20sek gesetzt: $ntm";
   return undef;
}

#####################################
sub TrashCal_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer( $hash );
   BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
   Log3 $hash, 4, "TrashCal_Undef: --- done ---";  
   return undef;
}


#####################################
sub TrashCal_Timer(@)
{
   my ($hash) = @_;
   my $me = $hash->{NAME};
   
   Log3 $hash, 4, "TrashCal_Timer: GrTimer aufgerufen.....";
   return unless (defined($hash->{NAME}));
   Log3 $hash, 4, "TrashCal_Timer: --- started ---";
  
   $hash->{helper}{TimerGRInterval} = AttrVal( $me, "TrashCal_Interval",  3600 );
      
   TrashCal_Start($hash) if(!IsDisabled($me));
   
    # setup timer
   RemoveInternalTimer( $hash );

   my $nt = time;
   $nt += $hash->{helper}{TimerGRInterval}; 
   my @lt = localtime($nt);
   my $ntm = sprintf("%02d.%02d.%04d %02d:%02d:%02d", $lt[3], ($lt[4]+1), ($lt[5]+1900), $lt[2], $lt[1], $lt[0]);
   $hash->{TriggerTime_FMT} = $ntm;
   $hash->{TriggerTime} = $nt;   

   InternalTimer($nt, "TrashCal_Timer", $hash, 0 );  
     
   Log3 $hash, 4, "TrashCal_Timer: --- done ---";  
}

#####################################
# acquires the html page
sub TrashCal_HtmlAcquire($)
{
   my ($hash)  = @_;
   my $name    = $hash->{NAME};
   return unless (defined($hash->{NAME}));
 
   my $URL = AttrVal( $name, 'TrashCal_Link', "" );

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
      Log3 $hash, 1, "TrashCal_HtmlAcquire: Error: $err_log";
      return "";
   }

   return $response->content;
}


#####################################
sub TrashCal_Start($)
{
  my ($hash)  = @_;
  return unless (defined($hash->{NAME}));
  my $me    = $hash->{NAME};

  if (AttrVal( $me, 'TrashCal_Link', "" ) eq "") {
    Log3 $hash, 3, "$me: Kein Link im Attribut 'TrashCal_Link' angebeben, breche Ausführung ab.";
    return;
  }
   
  while (1)
  {
     Log3 $hash, 4, "TrashCal_Start: --- started ---";
   
     $hash->{helper}{RUNNING_PID} =
          BlockingCall( 
          "TrashCal_Run",   # callback worker task
          $me,                    # name of the device
          "TrashCal_Done",  # callback result method
          50,                       # timeout seconds
          "TrashCal_Aborted", #  callback for abortion
          $hash );                 # parameter for abortion
           
     last;      
  }
  Log3 $hash, 4, "TrashCal_Start: --- done ---";
}

#####################################
sub TrashCal_Run($) {
   my ($string) = @_;
   my ( $me, $server ) = split( "\\|", $string );
   my $ptext = $me ."+";
   
   return unless ( defined($me) );
   
   my $hash = $defs{$me};
   return unless (defined($hash->{NAME}));
   
   Log3 $hash, 4, "TrashCal_Run: --- started ---";  
   while (1)
   {
      # acquire the html-page
      my $response = TrashCal_HtmlAcquire($hash); 
      last if ($response eq "");
     
      my $parser = MyTrashCalParser->new;
      %MyTrashCalParser::dates = ();
      # parsing the complete html-page-response, needs some time
      # only <td> tags will be regarded   
      $parser->parse($response);
      Log3 $hash, 4, "TrashCal_Run: parsed terms:" . keys(%MyTrashCalParser::dates);
      
      foreach my $cat (keys(%MyTrashCalParser::dates) ) {
        $ptext .= $cat . '|';
        #Log3 $hash, 4, "TrashCal_Run: Values of $cat: ". keys(%{$MyTrashCalParser::data{$cat}});
        #foreach my $dat (keys(%{$MyTrashCalParser::dates{$cat}}) ) {
        #  $ptext .= "|".$dat;
        #}
        $ptext .= join('|', @{$MyTrashCalParser::dates{$cat}});
        $ptext .= "+";
      }

      last;
   }

   Log3 $hash, 4, "TrashCal_Run: return value: $ptext";  
   Log3 $hash, 4, "TrashCal_Run: --- done ---";  
   return $ptext;
   #return "TrashCal|Altpapier|12.09.2014|07.11.2014|05.12.2014|18.07.2014|10.10.2014|15.08.2014";
}

#####################################
# assyncronous callback by blocking
sub TrashCal_Done($) {
  my ($string) = @_;
  Log3 undef, 4, "TrashCal_Done: --- begin ---";
  return unless ( defined($string) );
   
  # all term are separated by "#" , the first is the name of the instance
  my ( $me, @values ) = split("\\+", $string );
  my $hash = $defs{$me};
  return unless (defined($hash->{NAME}));
   
  # delete the marker for running process
  delete( $hash->{helper}{RUNNING_PID} );  

  Log3 $hash, 4, "TrashCal_Done: --- started ---";   
  #Log3 $hash, 5, "TrashCal_Done: values:".join(', ', @values);
   
  # Aktualisierung der Readings
  my $category;
  my $tstamp;
  my $NextEvent_Tstamp = time() + (28*86400); #hoher Initialwert
  my $NextEvent_Cat = "";
  my $NextEvent_Dat = "";
  my %hashValues = ();

  # Durch jede Kategorie
  for(my $i=0; $i<int(@values); $i++) {
    # show the values
    Log3 $hash, 5, "TrashCal_Done: Category with all values:".$values[$i];
    my @dates = split( "\\|", $values[$i] );
    $category = shift(@dates);
    for(my $j=0; $j<int(@dates); $j++) {
      if ( $dates[$j] =~ /([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})/i ) {
        #berechne dazu passenden Unix-Timestamp
        $tstamp = mktime(0, 0, 12, $1, ($2 -1), ($3 -1900), 0, 0, -1);
        if($tstamp < $NextEvent_Tstamp) {
          # das nächste/jüngste Event ermitteln
          $NextEvent_Dat = $dates[$j];
          $NextEvent_Cat = $category;
          $NextEvent_Tstamp = $tstamp;
        }

        if(!defined($hashValues{$category}{TSTAMP}) || (($tstamp > time()) && ($tstamp < $hashValues{$category}{TSTAMP}))) {
          # nur den zeitlich nächsten Wert in die Readings pro Categorie uebernehmen
          $hashValues{$category}{DATE}   = $dates[$j];
          $hashValues{$category}{TSTAMP} = $tstamp;
        }
      }
      
      # show the values
      Log3 $hash, 5, "TrashCal_Done: category:$category - date: ".$dates[$j];
    }   
  }

  readingsBeginUpdate($hash);
  foreach my $xxx ( sort keys %hashValues )  {
     #my $daysleft = ($hashValues{$xxx}{TSTAMP} - time()) / 60 / 24;
     readingsBulkUpdate( $hash, $xxx,            $hashValues{$xxx}{DATE} ); 
     readingsBulkUpdate( $hash, $xxx."_Tstamp",  $hashValues{$xxx}{TSTAMP} );
     #readingsBulkUpdate( $hash, $xxx."_DaysLeft", $daysleft); 
  }

  readingsBulkUpdate( $hash, "NextEvent Category", $NextEvent_Cat );
  readingsBulkUpdate( $hash, "NextEvent Date", $NextEvent_Dat );
  readingsBulkUpdate( $hash, "NextEvent Tstamp", $NextEvent_Tstamp );

  readingsBulkUpdate( $hash, "state", $NextEvent_Cat .": ". $NextEvent_Dat );
  readingsEndUpdate( $hash, 1 );
   
  Log3 $hash, 4, "TrashCal_Done: --- done ---";
}

#####################################
sub TrashCal_Aborted($)
{
   my ($hash) = @_;
   delete( $hash->{helper}{RUNNING_PID} );
   Log3 $hash, 3, "TrashCal_Aborted: --- done ---";  
}


##################################### 
1;

=pod
=item helper
=item summary fetches shared dates at an public webpage of waste disposal   
=item summary_DE holt auf einer Webseite bereitgestellte Abfalltermine ab
=begin html

<a name="TrashCal"></a>
<h3>TrashCal</h3>
<ul>
  Note: this module needs the HTTP::Request,HTML::Parser and LWP::UserAgent perl modules.
  <br>
  At this moment only city "Magdeburg" is supported at this site:<br>
  <i>http://sab.metageneric.de/app/sab_i_tp/index.php</i>
  <br><br>
  <a name="TrashCal define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TrashCal &lt;type&gt; </code>
    <br><br>
    Defines a new instanze of Trashcalendar. At this time the &lt;type&gt; is not used
    <br>
    Examples:
    <ul>
      <code>define MyTrashCal TrashCal Restabfall</code><br>
    </ul>
  </ul>
  <br>

  <a name="TrashCalset"></a>
  <b>Set</b> 
  <ul>N/A</ul><br> 

  <a name="TrashCalget"></a>
  <b>Get</b> 
  <ul>N/A</ul><br> 

  <a name="TrashCalattr"></a>
  <b>Attributes</b>
  <ul>
    <li>TrashCal_Link<br>
      setting up the URL to grab the Trashcalendar
      <br>Example:
      <ul>
        <code>http://sab.metageneric.de/app/sab_i_tp/index.php?r=getHausnummerInfo&strasse=Torplatz&hausnummer=1&stadtteil_id=1609&dsd_behaelter_value=b120_b240</code>
        <br>
      </ul>
    </li> 

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>

    <li><a href="#disable">disable</a><br>
      If this attribute is activated, the module will be disabled.<br>
      Possible values: 0 => not disabled , 1 => disabled<br>
      Default Value is 0 (not disabled)<br><br> 
    </li>

    <li><a href="#verbose">verbose</a><br>
      <b>4:</b> each major step will be logged<br>
      <b>5:</b> Additionally some minor steps will be logged
    </li>

  </ul>
</ul>

=end html
=cut
