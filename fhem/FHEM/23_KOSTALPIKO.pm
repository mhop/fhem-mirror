# $Id$
####################################################################################################
#
#	23_KOSTALPIKO.pm
#
#  This modul supports the KOSTAL Piko Inverter.
#  All Value of Piko's Home-page are captured.
#
#  Futhermore the Global-Radion value is captured from http://www.proplanta.de/Wetter/<city>-Wetter-Heute.html
#  so the expected energy ca be estimated
#
# 2013-06-28 john  : added some snippets for getting all readings
#                  : added UndefFn
# 2013-06-28 john  : global radiation support; updated hourly; needs attribute GR.Link
#                    the link must have the form of: http://www.proplanta.de/Wetter/<city>-Wetter-Heute.html
#                    take a look to the site http://www.proplanta.de
#                    you can calculate the expected daily power by using userReadings
#                    Daily.Energy.Last is updated once at the hour 23
# 2013-06-28 john  : Delay.Counter added
#                    will be decremented until 0,
#                    if not 0, then only AC.Power is scanned, otherwise alle Values are scanned
# 2013-07-02 john  : AC.Power.Fast added
# 2013-07-14 john  : some fixes with minor priority
# 2014-06-01 john  V2.00 : adaption to common developer standards
#                    attribute changes
#                      - verbose is supported instead of loglevel
#                      - disable is supported
#                      - new attribute  : GRIntervall : intervall for capturing global radiation
#                    new software-design
#                      - non-blocking calls for capturing and parsing of html-pages
#                      - reducing side-effects for other devices due timeouts
# 2014-06-29 john  V2.01 : supporting sensor values for http://<name>/Info.fhtml
# 2014-06-05 john  V2.02 : supporting UV-Index and sunshine duration
# 2014-07-05 john  V2.03 : fix: value extraction was faulty
# 2014-09-08 john  V2.04 : fix: device name with dot made trouble (checked against Kostal Pikos Firmware 10.1)
#                          adjusting KOSTALPIKO_Log
#                          Inital Checkin to FHEM ; docu revised
# 2014-09-08 john  V2.05 : support of battery option; developed by  jannik_78
# 2014-12-22 john  V2.06 : checked HTML
# 2015-01-25 john  V2.07 : adjusted argument agent for http-request of proplanta (thanks to framller)
# 2016-02-25 john  V2.08 : support of Piko 7 with only 2 strings instead of 3 (thanks to erwin)
# 2016-02-25 john  V2.09 : substitution of term given/when with if/then
# 2017-19-26 john  V2.10 : support of https
####################################################################################################

# --------------------------------------------
# parser for the site http://<ip-kostal>/index.fhtml
package MyParser;
use base qw(HTML::Parser);
our @texte = ();
my $isTD     = 0;
my $takeNext = 0;

# is called if a text content is detected
# results in an array of string with alternating description / value
sub text
{
  my ( $self, $text ) = @_;
  if ( $isTD == 1 )    # if we are inside a TD-Tag
  {
    $text =~ s/^\s+//;    # trim string
    $text =~ s/\s+$//;
    if ( $takeNext == 1 )    # first text is description, next text is value
    {
      $takeNext = 0;
      push( @texte, $text );
    }

    # filter only interesting captions
    if ( $text eq "aktuell"
      || $text eq "Gesamtenergie"
      || $text eq "Tagesenergie"
      || $text eq "Status"
      || $text eq "Spannung"
      || $text eq "Strom"
      || $text eq "Leistung" )
    {
      $takeNext = 1;    # expect next tag as value
      push( @texte, $text );
    }
  }
}

# callback, if start tag is detected
sub start
{
  my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;

  # we are only interested on TD-Tags
  if ( $tagname eq 'td' )
  {
    $isTD = 1;
  } else
  {
    $isTD = 0;
  }
}

# after end-tag reset TD-marker
sub end
{
  $isTD = 0;
}

# --------------------------------------------
# parser for the site http://<ip-kostal>/BA.fhtml
package MyBatteryParser;
use base qw(HTML::Parser);
our @texte = ();
my $isTD     = 0;
my $isBold   = 0;
my $takeNext = 0;

# is called if a text content is detected
# results in an array of string with alternating description / value
sub text
{

  my ( $self, $text ) = @_;
  if ( $isTD == 1 )    # if we are inside a TD-Tag
  {
    # filter only interesting captions
    if ( $text eq "Ladezustand:"
      || $text eq "Spannung:"
      || $text eq "Ladestrom:"
      || $text eq "Temperatur:"
      || $text eq "Zyklenanzahl:"
      || $text eq "Solargenerator:"
      || $text eq "Batterie:"
      || $text eq "Netz:"
      || $text eq "Phase 1:"
      || $text eq "Phase 2:"
      || $text eq "Phase 3:" )
    {
      $takeNext = 1;    # expect next tag as value
      push( @texte, $text );
    }
  }

  if ( $isBold == 1 && $takeNext == 1 )
  {
    $takeNext = 0;
    $text =~ s/[^0-9\.]//g;
    push( @texte, $text );
  }

}

# callback, if start tag is detected
sub start
{
  my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;

  # we are only interested on TD-Tags
  $isTD   = 0;
  $isBold = 0;
  if ( $tagname eq 'td' )
  {
    $isTD = 1;
  }

  if ( $tagname eq 'b' )
  {
    $isBold = 1;
  }
}

# after end-tag reset TD-marker
sub end
{
  $isTD = 0;
}
###############################################
# parser for the global radiation
package MyRadiationParser;
use base qw(HTML::Parser);
our @texte = ();
my $lookupTag = "span";
my $curTag    = "";
my $takeNext  = 0;

# here HTML::text/start/end are overridden
sub text
{
  my ( $self, $text ) = @_;
  if ( $curTag eq $lookupTag )
  {
    $text =~ s/^\s+//;    # trim string
    $text =~ s/\s+$//;
    if ( $takeNext == 1 )
    {
      $takeNext = 0;
      push( @texte, $text );
    }
    if ( $text eq "Globalstrahlung" )
    {
      $takeNext = 1;
      push( @texte, $text );
    } elsif ( $text eq "UV-Index" )
    {
      $takeNext = 1;
      push( @texte, $text );
    } elsif ( $text eq "rel. Sonnenscheindauer" )
    {
      $takeNext = 1;
      push( @texte, $text );
    }
  }
}

sub start
{
  my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
  $curTag = $tagname;
}

sub end
{
  $curTag = "";
}

##############################################
# parser for the site http://<kostal-piko-ip>/Info.fhtml with sensor values
package MyInfoParser;
use base qw(HTML::Parser);
our @texte = ();
my $isTD     = 0;
my $isBold   = 0;
my $takeNext = 0;

# is called if a text content is detected
sub text
{
  my ( $self, $text ) = @_;
  if ( $isTD == 1 )    # if we are inside a TD-Tag
  {
    # filter only interesting captions
    if ( $text =~ m/.*Eingang.*/ )
    {
      $takeNext = 1;    # expect next tag as value
      push( @texte, $text );
    }
  }

  if ( $isBold == 1 && $takeNext == 1 )
  {
    $takeNext = 0;
    $text =~ s/^\s+//;               # trim string
    $text =~ s/\s+$//;
    $text =~ m/([0-9]+\.[0-9]+)/;    # find substring 0.00V : 0.00
    my $value = $1;
    push( @texte, $value );
  }
}

# callback, if start tag is detected
sub start
{
  my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;

  # we are only interested on TD-Tags
  $isTD   = 0;
  $isBold = 0;
  if ( $tagname eq 'td' )
  {
    $isTD = 1;
  }

  if ( $tagname eq 'b' )
  {
    $isBold = 1;
  }
}

# after end-tag reset TD-marker
sub end
{
  $isTD = 0;
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
my $MODUL          = "KOSTALPIKO";
my $KOSTAL_VERSION = "2.10";

########################################
sub KOSTALPIKO_Log($$$)
{
  my ( $hash, $loglevel, $text ) = @_;
  my $xline = ( caller(0) )[2];

  my $xsubroutine = ( caller(1) )[3];
  my $sub = ( split( ':', $xsubroutine ) )[2];
  $sub =~ s/KOSTALPIKO_//;

  my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $MODUL;
  Log3 $hash, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}
###################################
sub KOSTALPIKO_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "KOSTALPIKO_Define";
  $hash->{UndefFn} = "KOSTALPIKO_Undef";
  $hash->{SetFn}   = "KOSTALPIKO_Set";
  $hash->{AttrList} =
    "delay " . "delayCounter " . "GR.Link " . "GR.Interval " . "disable:0,1 " . "BAEnable:0,1 " . $readingFnAttributes;
}
###################################
sub KOSTALPIKO_Define($$)
{
  my ( $hash, $def ) = @_;
  my $name = $hash->{NAME};
  my @a    = split( "[ \t][ \t]*", $def );
  my $host = $a[2];
  my $user = $a[3];
  my $pass = $a[4];
  if ( int(@a) < 5 )
  {
    return "Wrong syntax: use define <name> KOSTALPIKO <ip-address> <user> <pass>";
  }
  $hash->{VERSION}             = $KOSTAL_VERSION;
  $hash->{helper}{Host}        = $host;
  $hash->{helper}{User}        = $user;
  $hash->{helper}{Pass}        = $pass;
  $hash->{helper}{GRHour}      = 25;
  $hash->{helper}{TimerStatus} = $name . ".STATUS";    # like "Kostal.STATUS"
  $hash->{helper}{TimerGR}     = $name . ".GR";
  InternalTimer( gettimeofday() + 10, "KOSTALPIKO_StatusTimer", $hash->{helper}{TimerStatus}, 0 );
  InternalTimer( gettimeofday() + 20, "KOSTALPIKO_GrTimer",     $hash->{helper}{TimerGR},     0 );
  return undef;
}
#####################################
sub KOSTALPIKO_Undef($$)
{
  my ( $hash, $arg ) = @_;

  RemoveInternalTimer( $hash->{helper}{TimerStatus} );
  RemoveInternalTimer( $hash->{helper}{TimerGR} );
  BlockingKill( $hash->{helper}{RUNNING_STATUS} ) if ( defined( $hash->{helper}{RUNNING_STATUS} ) );
  BlockingKill( $hash->{helper}{RUNNING_GR} )     if ( defined( $hash->{helper}{RUNNING_GR} ) );

  KOSTALPIKO_Log $hash, 3, "--- done ---";
  return undef;
}
#####################################
sub KOSTALPIKO_Set($@)
{
  my ( $hash, @a ) = @_;
  my $name   = $hash->{NAME};
  my $reUINT = '^([\\+]?\\d+)$';
  my $usage  = "Unknown argument $a[1], choose one of captureKostalData:noArg ";
  my $URL    = AttrVal( $name, 'GR.Link', "" );
  if ($URL)
  {
    $usage .= "captureGlobalRadiation:noArg ";
  }

  # for debugging issues
  # $usage .= "test:noArg sleeper ";

  return $usage if ( @a < 2 );

  my $cmd = lc( $a[1] );

  if ( $cmd eq "?" )
  {
    return $usage;
  } elsif ( $cmd eq "capturekostaldata" )
  {
    KOSTALPIKO_Log $hash, 3, "set command: " . $a[1] . " para:" . $hash->{helper}{TimerStatus};
    KOSTALPIKO_StatusStart($hash);
  } elsif ( $cmd eq "captureglobalradiation" )
  {
    KOSTALPIKO_Log $hash, 3, "set command: " . $a[1];
    KOSTALPIKO_GrStart($hash);
  } elsif ( $cmd eq "test" )
  {
    KOSTALPIKO_Log $hash, 3, "set command: " . $a[1];
    KOSTALPIKO_GrStart($hash);
  } elsif ( $cmd eq "sleeper" )
  {
    return "Set sleeper needs a <value> parameter"
      if ( @a != 3 );
    my $value = $a[2];
    $value = ( $value =~ m/$reUINT/ ) ? $1 : undef;
    return "value " . $a[2] . " is not a number"
      if ( !defined($value) );

    KOSTALPIKO_Log $hash, 3, "set command: " . $a[1] . " value:" . $a[2];
    $hash->{helper}{Sleeper} = $a[2];
  } else
  {
    return $usage;
  }
  return;
}
#############################################
# get hour as number, input is a serial date
sub KOSTAL_GetHourSD($)
{
  my @t = localtime(shift);
  return $t[2];
}
#############################################
# current datetime round off to current hour
sub KOSTAL_GetDateTrunc($)
{
  my @t = localtime(shift);
  return sprintf( "%04d-%02d-%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], 0, 0 );
}
#############################################
# converts string-datetime to serial-datetime
# input:  datetime as string
# output: serial datetime
sub KOSTAL_DateStr2Serial($)
{
  my $datestr = shift;
  my ( $yyyy, $mm, $dd, $hh, $mi, $ss ) = $datestr =~ /(\d+)-(\d+)-(\d+) (\d+)[:](\d+)[:](\d+)/;

  # months are zero based
  my $t2 = fhemTimeLocal( $ss, $mi, $hh, $dd, $mm - 1, $yyyy - 1900 );
  return $t2;
}

#####################################
# acquires the sensor html page of kostalpiko
sub KOSTALPIKO_SensorHtmlAcquire($)
{
  my ($hash) = @_;
  return unless ( defined( $hash->{NAME} ) );

  my $err_log = '';

  my $URL =
    "http://" . $hash->{helper}{User} . ":" . $hash->{helper}{Pass} . "\@" . $hash->{helper}{Host} . "/Info.fhtml";

  KOSTALPIKO_Log $hash, 4, "$URL";
  my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, timeout => 3 );
  my $header = HTTP::Request->new( GET => $URL );
  my $request = HTTP::Request->new( 'GET', $URL, $header );
  my $response = $agent->request($request);
  $err_log .= "Can't get $URL -- " . $response->status_line
    unless $response->is_success;

  if ( $err_log ne "" )
  {
    KOSTALPIKO_Log $hash, 1, $err_log;
    return "";
  }
  return $response->content;
}
#####################################
# acquires the battery html page of kostalpiko
sub KOSTALPIKO_BatteryHtmlAcquire($)
{
  my ($hash) = @_;
  return unless ( defined( $hash->{NAME} ) );

  my $err_log = '';

  my $URL =
    "http://" . $hash->{helper}{User} . ":" . $hash->{helper}{Pass} . "\@" . $hash->{helper}{Host} . "/BA.fhtml";

  # $URL = "http://192.168.178.20/XBA.html";    # for testing only uncomment

  KOSTALPIKO_Log $hash, 4, "$URL";
  my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, timeout => 3 );
  my $header = HTTP::Request->new( GET => $URL );
  my $request = HTTP::Request->new( 'GET', $URL, $header );
  my $response = $agent->request($request);
  $err_log .= "Can't get $URL -- " . $response->status_line
    unless $response->is_success;

  if ( $err_log ne "" )
  {
    KOSTALPIKO_Log $hash, 1, $err_log;
    return "";
  }
  return $response->content;
}
#####################################
# acquires the html page of kostalpiko
sub KOSTALPIKO_StatusHtmlAcquire($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return unless ( defined( $hash->{NAME} ) );

  my $err_log = '';

  my $URL =
    "http://" . $hash->{helper}{User} . ":" . $hash->{helper}{Pass} . "\@" . $hash->{helper}{Host} . "/index.fhtml";

  KOSTALPIKO_Log $hash, 4, "$URL";
  my $agent = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, timeout => 3 );
  my $header = HTTP::Request->new( GET => $URL );
  my $request = HTTP::Request->new( 'GET', $URL, $header );
  my $response = $agent->request($request);
  $err_log .= "Can't get $URL -- " . $response->status_line
    unless $response->is_success;

  if ( $err_log ne "" )
  {
    KOSTALPIKO_Log $hash, 1, $err_log;
    return "";
  }
  return $response->content;
}

#####################################
sub KOSTALPIKO_StatusStart($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return unless ( defined( $hash->{NAME} ) );

  my $err_log   = '';
  my $sdCurTime = gettimeofday();
  my $hour      = KOSTAL_GetHourSD($sdCurTime);
  my $disable   = AttrVal( $name, "disable", 0 );
  my $delay     = AttrVal( $name, "delay", 300 );

  while (1)
  {
    KOSTALPIKO_Log $hash, 3, "--- started ---";

    # check disable attribute
    if ( $disable == 1 )
    {
      KOSTALPIKO_Log $hash, 3, "disabled";
      last;
    }

    if ( !defined( $hash->{helper}{delayCounter} ) )
    {
      $hash->{helper}{delayCounter} = AttrVal( $name, "delayCounter", "0" );
    }

    # wenn delayCounter aktiv
    if ( $hash->{helper}{delayCounter} > 0 )
    {
      $hash->{helper}{delayCounter}--;
    }

    $hash->{helper}{RUNNING_STATUS} = BlockingCall(
      "KOSTALPIKO_StatusRun",        # callback worker task
      $name,                         # name of the device
      "KOSTALPIKO_StatusDone",       # callback result method
      50,                            # timeout seconds
      "KOSTALPIKO_StatusAborted",    #  callback for abortion
      $hash
    );                               # parameter for abortion

    last;
  }
  KOSTALPIKO_Log $hash, 3, "--- done ---";
}

#####################################
sub KOSTALPIKO_StatusRun($)
{
  my ($string) = @_;
  my ( $name, $server ) = split( "\\|", $string );
  my $level = 5;

  return unless ( defined($name) );

  my $hash = $defs{$name};
  return unless ( defined( $hash->{NAME} ) );

  KOSTALPIKO_Log $hash, 3, "--- started ---";

  # acquire the html-page
  my $response = KOSTALPIKO_StatusHtmlAcquire($hash);

  # perform parsing
  #KOSTALPIKO_Log $hash, $level, "before parsing of response-Len:".length($response);
  my $parser = MyParser->new;
  @MyParser::texte = ();

  # parsing the complete html-page-response, needs some time
  # only <td> tags will be regarded
  $parser->parse($response);

  # for testing issues
  if ( defined( $hash->{helper}{Sleeper} ) )
  {
    my $sleep = $hash->{helper}{Sleeper};
    $hash->{helper}{Sleeper} = 0;
    sleep($sleep) if ( $sleep > 0 );
  }

  # pack the results in a single string
  my $ptext = $name;
  foreach my $text (@MyParser::texte)
  {
    $ptext = $ptext . "|" . $text;
  }

  #---------------------------- Sensor values
  $response            = KOSTALPIKO_SensorHtmlAcquire($hash);
  $parser              = MyInfoParser->new;
  @MyInfoParser::texte = ();
  $parser->parse($response);
  foreach my $text (@MyInfoParser::texte)
  {
    $ptext = $ptext . "|" . $text;
  }

  #---------------------------- battery values
  if ( AttrVal( $name, 'BAEnable', 0 ) == 1 )
  {
    $response               = KOSTALPIKO_BatteryHtmlAcquire($hash);
    $parser                 = MyBatteryParser->new;
    @MyBatteryParser::texte = ();
    $parser->parse($response);
    foreach my $text (@MyBatteryParser::texte)
    {
      $ptext = $ptext . "|" . $text;
    }
  }

  #------------------------------ aquire is finished
  KOSTALPIKO_Log $hash, 3, "--- done ---";
  return $ptext;
}
#####################################
# assyncronous callback by blocking
sub KOSTALPIKO_StatusDone($)
{
  my ($string) = @_;
  return unless ( defined($string) );

  # need to do this before split !!!
  my @nVoltages   = $string =~ m/Spannung/g;    ##MH how often did we find the word Spannung?
  my $strangCount = int( @nVoltages / 2 );      # the number of strings

  # all term are separated by "|" , the first ist the name of the instance
  my ( $name, @values ) = split( "\\|", $string );
  my $hash = $defs{$name};
  return unless ( defined( $hash->{NAME} ) );

  KOSTALPIKO_Log $hash, 3, '--- started --- with numStrings:' . $strangCount;

  # show the values
  KOSTALPIKO_Log $hash, 5, "values:" . join( ', ', @values );

  # delete the marker for running process
  delete( $hash->{helper}{RUNNING_STATUS} );

  #------------------
  while (1)
  {
    my $tag    = "";    # der Name des parameters in der web site
    my $index  = 0;     # laufindex von 1..4 f. String x und Lx
    my $strang = 1;     # gruppe  String<n>/ L<n>
    my $rdName = "";    # name for reading
    my $rdValue;        # value for reading
    my %hashValues = ();                             # hash for name,value
    my $sdCurTime  = gettimeofday();
    my $hour       = KOSTAL_GetHourSD($sdCurTime);

    foreach my $text (@values)
    {
      if ( $text eq "aktuell"
        || $text eq "Gesamtenergie"
        || $text eq "Tagesenergie"
        || $text eq "Status"
        || $text =~ m/.*analoger Eingang.*/
        || $text eq "Ladezustand:"
        || $text eq "Spannung:"
        || $text eq "Ladestrom:"
        || $text eq "Temperatur:"
        || $text eq "Zyklenanzahl:"
        || $text eq "Solargenerator:"
        || $text eq "Batterie:"
        || $text eq "Netz:"
        || $text eq "Phase 1:"
        || $text eq "Phase 2:"
        || $text eq "Phase 3:" )
      {
        $tag = $text;    # remember the identifier
      } elsif ( $text eq "Spannung" || $text eq "Strom" || $text eq "Leistung" )
      {
        $index++;

        # there are max 4 values per group
        if ( $index > 4 )
        {
          $strang++;
          $index = 1;
        }
        $tag = $text;    # remember the identifier
      } else
      {
        if ( $tag ne "" )    # last text was a identifier, so we expect a value
        {
          $rdValue = $text;

          # translate the identifier of the html.page to internal identifiers
          $rdName = "AC.Power"     if ( $tag eq "aktuell" );
          $rdName = "Total.Energy" if ( $tag eq "Gesamtenergie" );
          $rdName = "Daily.Energy" if ( $tag eq "Tagesenergie" );
          $rdName = "Mode"         if ( $tag eq "Status" );

          # MH change for PIKO7 (2 Strings only / should work for 3 string PIKO's
          if ( $tag eq "Spannung" )
          {
            $rdName = "output.$strang.voltage" if ( $index == 2 );
            if ( $index == 1 )
            {
              if ( $strang <= $strangCount )
              {
                $rdName = "generator.$strang.voltage";
              } else
              {
                # useful for PIKO7 with 2 Strings only
                $rdName = "output.$strang.voltage";
              }
            }
          }
          $rdName = "generator.$strang.current" if ( $tag eq "Strom" );
          $rdName = "output.$strang.power"      if ( $tag eq "Leistung" );
          $rdName = "sensor.1"                  if ( $tag eq "1. analoger Eingang:" );
          $rdName = "sensor.2"                  if ( $tag eq "2. analoger Eingang:" );
          $rdName = "sensor.3"                  if ( $tag eq "3. analoger Eingang:" );
          $rdName = "sensor.4"                  if ( $tag eq "4. analoger Eingang:" );

          # BA.fhtml
          $rdName = "Battery.StateOfCharge" if ( $tag eq "Ladezustand:" );
          $rdName = "Battery.Voltage"       if ( $tag eq "Spannung:" );
          $rdName = "Battery.ChargeCurrent" if ( $tag eq "Ladestrom:" );
          $rdName = "Battery.Temperature"   if ( $tag eq "Temperatur:" );
          $rdName = "Battery.CycleCount"    if ( $tag eq "Zyklenanzahl:" );
          $rdName = "Power.Solar"           if ( $tag eq "Solargenerator:" );
          $rdName = "Power.Battery"         if ( $tag eq "Batterie:" );
          $rdName = "Power.Net"             if ( $tag eq "Netz:" );
          $rdName = "Power.Phase1"          if ( $tag eq "Phase 1:" );
          $rdName = "Power.Phase2"          if ( $tag eq "Phase 2:" );
          $rdName = "Power.Phase3"          if ( $tag eq "Phase 3:" );

          # set 0, if "x x x" is given
          $rdValue = 0 if ( index( $rdValue, "x x x" ) != -1 );

          # add the pair of identifier and value to the hash
          $hashValues{$rdName} = $rdValue;

          #special treatment for fast value
          $hashValues{ $rdName . ".Fast" } = $rdValue if ( $rdName eq "AC.Power" );
          $tag    = "";    # next text will be an identifier
          $rdName = "";
        }
      }
    }    # foreach

    # add the state for reading update
    $rdValue = "W: " . $hashValues{"AC.Power"} . " - " . $hashValues{"Mode"};
    $hashValues{state} = $rdValue;

    # set the ModeNum
    my $NMode = 9;
    $rdValue             = $hashValues{"Mode"};
    $NMode               = 0 if ( $rdValue eq "Aus" );
    $NMode               = 1 if ( $rdValue eq "Leerlauf" );
    $NMode               = 2 if ( $rdValue eq "Einspeisen MPP" );
    $hashValues{ModeNum} = $NMode;

    # Daily.Energy.Last, remember the last value of dayly energy
    # check from  23 hour
    if ( defined( $hash->{READINGS}{"Daily.Energy"} ) && $hour == 23 )
    {
      my $ss          = KOSTAL_GetDateTrunc($sdCurTime);    # string date rounded to hour
      my $sdDateTrunc = KOSTAL_DateStr2Serial($ss);         # string date to serial date
      $ss = ReadingsTimestamp( $name, "Daily.Energy.Last", $ss );    # determine reading timestamp
      my $sdEnergyLast = KOSTAL_DateStr2Serial($ss);                 # serial format
      KOSTALPIKO_Log $hash, 5, "DateTrunc : $ss  sdDateTrunc: $sdDateTrunc sdEnergyLast:$sdEnergyLast";
      if ( $sdEnergyLast <= $sdDateTrunc )
      {
        KOSTALPIKO_Log $hash, 4, "update Daily.Energy.Last with " . $hash->{READINGS}{"Daily.Energy"}{VAL};
        readingsSingleUpdate( $hash, "Daily.Energy.Last", $hash->{READINGS}{"Daily.Energy"}{VAL}, 1 );
      }
    }

    # update readings
    my $upd;
    readingsBeginUpdate($hash);
    foreach my $xxx ( sort keys %hashValues )
    {
      $upd = 0;

      # update if reading not exists or if new/old value differs
      if ( !defined( $hash->{READINGS}{$xxx}{VAL} ) || $hash->{READINGS}{$xxx}{VAL} ne $hashValues{$xxx} )
      {
        # AC.Power.FAst will every time updated, the others only, if delaycount is 0
        if ( $xxx eq "AC.Power.Fast" || $hash->{helper}{delayCounter} == 0 )
        {
          readingsBulkUpdate( $hash, $xxx, $hashValues{$xxx} );
          $upd = 1;
        }
      }
      KOSTALPIKO_Log $hash, 4, "$xxx: $hashValues{ $xxx } upd:$upd";
    }
    readingsEndUpdate( $hash, 1 );
    last;
  }

  # wir arbeiten mit delay counter
  if ( AttrVal( $name, "delayCounter", "0" ) ne "0" && $hash->{helper}{delayCounter} == 0 )
  {
    $hash->{helper}{delayCounter} = AttrVal( $name, "delayCounter", "0" );
    KOSTALPIKO_Log $hash, 3, "delayCounter restarted";
  }

  KOSTALPIKO_Log $hash, 3, "--- done ---";

}
#####################################
sub KOSTALPIKO_StatusAborted($)
{
  my ($hash) = @_;
  delete( $hash->{helper}{RUNNING_STATUS} );
  KOSTALPIKO_Log $hash, 3, "--- done ---";
}
#####################################
sub KOSTALPIKO_StatusTimer($)
{
  my ($timerpara) = @_;

  #my ( $name, $func ) = split( /\./, $timerpara );
  my $index = rindex( $timerpara, "." );    # rechter punkt
  my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
  my $name = substr $timerpara, 0, $index;                         # name extrahieren
  my $hash = $defs{$name};

  #KOSTALPIKO_Log "", 3, "--- started --- name:$name";
  return unless ( defined( $hash->{NAME} ) );
  KOSTALPIKO_Log $hash, 3, "--- started ---";

  KOSTALPIKO_StatusStart($hash);
  $hash->{helper}{TimerInterval} = AttrVal( $name, "delay", 60 );

  # setup timer
  RemoveInternalTimer( $hash->{helper}{TimerStatus} );

  InternalTimer( gettimeofday() + $hash->{helper}{TimerInterval},
    "KOSTALPIKO_StatusTimer", $hash->{helper}{TimerStatus}, 0 );

  KOSTALPIKO_Log $hash, 3, "--- done ---";
}

#####################################
# acquires the html page of Global radiation
sub KOSTALPIKO_GrHtmlAcquire($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return unless ( defined( $hash->{NAME} ) );

  my $URL = AttrVal( $name, 'GR.Link', "" );

  # abbrechen, wenn wichtig parameter nicht definiert sind
  return "" if ( !defined($URL) );
  return "" if ( $URL eq "" );

  my $err_log = "";

  # my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, timeout => 3 );
  my $agent = LWP::UserAgent->new(
    env_proxy         => 1,
    keep_alive        => 1,
    protocols_allowed => ['http','https'],
    timeout           => 10,
    agent             => "Mozilla/5.0 (Windows NT 5.1) [de-DE,de;q=0.8,en-US;q=0.6,en;q=0.4]"
  );

  my $header = HTTP::Request->new( GET => $URL );
  my $request = HTTP::Request->new( 'GET', $URL, $header );
  my $response = $agent->request($request);
  $err_log = "Can't get $URL -- " . $response->status_line
    unless $response->is_success;

  if ( $err_log ne "" )
  {
    KOSTALPIKO_Log $hash, 1, "Error: $err_log";
    return "";
  }

  return $response->content;
}

#####################################
sub KOSTALPIKO_GrStart($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return unless ( defined( $hash->{NAME} ) );

  return if ( AttrVal( $name, 'GR.Link', "" ) eq "" );

  while (1)
  {
    KOSTALPIKO_Log $hash, 3, "--- started ---";

    $hash->{helper}{RUNNING_GR} = BlockingCall(
      "KOSTALPIKO_GrRun",        # callback worker task
      $name,                     # name of the device
      "KOSTALPIKO_GrDone",       # callback result method
      50,                        # timeout seconds
      "KOSTALPIKO_GrAborted",    #  callback for abortion
      $hash
    );                           # parameter for abortion

    last;
  }
  KOSTALPIKO_Log $hash, 3, "--- done ---";
}

#####################################
sub KOSTALPIKO_GrRun($)
{
  my ($string) = @_;
  my ( $name, $server ) = split( "\\|", $string );
  my $ptext = $name;

  return unless ( defined($name) );

  my $hash = $defs{$name};
  return unless ( defined( $hash->{NAME} ) );

  KOSTALPIKO_Log $hash, 3, "--- started ---";
  while (1)
  {
    # acquire the html-page
    my $response = KOSTALPIKO_GrHtmlAcquire($hash);
    last if ( $response eq "" );

    my $parser = MyRadiationParser->new;
    @MyRadiationParser::texte = ();

    # parsing the complete html-page-response, needs some time
    # only <td> tags will be regarded
    $parser->parse($response);
    KOSTALPIKO_Log $hash, 4, "parsed terms:" . @MyRadiationParser::texte;

    # pack the results in a single string
    foreach my $text (@MyRadiationParser::texte)
    {
      $ptext = $ptext . "|" . $text;
    }

    last;
  }

  KOSTALPIKO_Log $hash, 3, "--- done ---";
  return $ptext;
}
#####################################
# assyncronous callback by blocking
sub KOSTALPIKO_GrDone($)
{
  my ($string) = @_;
  return unless ( defined($string) );

  # all term are separated by "|" , the first ist the name of the instance
  my ( $name, @values ) = split( "\\|", $string );
  my $hash = $defs{$name};
  return unless ( defined( $hash->{NAME} ) );

  KOSTALPIKO_Log $hash, 3, "--- started ---";

  # show the values
  KOSTALPIKO_Log $hash, 5, "values:" . join( ', ', @values );

  # delete the marker for running process
  delete( $hash->{helper}{RUNNING_GR} );

  my $tag        = "";
  my $rdName     = "";
  my $rdValue    = "";
  my %hashValues = ();

  # nach myRadiation suchen
  foreach my $text (@values)
  {
    if ( $text eq "Globalstrahlung" || $text eq "UV-Index" || $text eq "rel. Sonnenscheindauer" )
    {
      $tag = $text;
    } else
    {
      if ( $tag ne "" )
      {
        $rdValue = $text;
        $rdValue =~ tr/,/./;                  # komma gegen punkt tauschen
        $rdValue =~ m/([-,\+]?\d+\.?\d*)/;    # zahl extrahieren
        $rdValue             = $1;
        $rdName              = $tag;
        $rdName              = "Global.Radiation" if ( $tag eq "Globalstrahlung" );
        $rdName              = "UV.Index" if ( $tag eq "UV-Index" );
        $rdName              = "sunshine.duration" if ( $tag eq "rel. Sonnenscheindauer" );
        $hashValues{$rdName} = $rdValue;
        $tag                 = "";
        KOSTALPIKO_Log $hash, 5, "tag:$rdName value:$rdValue";
      }
    }
  }
  my $upd = 1;

  # hash sortieren und ausgeben, immer updaten, damit kurve angezeigt wird
  readingsBeginUpdate($hash);
  foreach my $xxx ( sort keys %hashValues )    # alle schluessel abfragen
  {
    readingsBulkUpdate( $hash, $xxx, $hashValues{$xxx} );    # alten zustand merken
    KOSTALPIKO_Log $hash, 5, "$xxx: $hashValues{ $xxx } upd:$upd";
  }
  readingsEndUpdate( $hash, 1 );

  KOSTALPIKO_Log $hash, 3, "--- done ---";
}
#####################################
sub KOSTALPIKO_GrAborted($)
{
  my ($hash) = @_;
  delete( $hash->{helper}{RUNNING_GR} );
  KOSTALPIKO_Log $hash, 3, "--- done ---";
}

#####################################
sub KOSTALPIKO_GrTimer($)
{
  my ($timerpara) = @_;

  # my ( $name, $func ) = split( /\./, $timerpara );
  my $index = rindex( $timerpara, "." );    # rechter punkt
  my $func = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
  my $name = substr $timerpara, 0, $index;                         # name extrahieren
  my $hash = $defs{$name};

  return unless ( defined( $hash->{NAME} ) );
  KOSTALPIKO_Log $hash, 3, "--- started ---";

  $hash->{helper}{TimerGRInterval} = AttrVal( $name, "GR.Interval", 3600 );

  KOSTALPIKO_GrStart($hash);

  # setup timer
  RemoveInternalTimer( $hash->{helper}{TimerGR} );

  InternalTimer( gettimeofday() + $hash->{helper}{TimerGRInterval}, "KOSTALPIKO_GrTimer", $hash->{helper}{TimerGR}, 0 );

  KOSTALPIKO_Log $hash, 3, "--- done ---";
}

#####################################
1;

=pod
=item summary   Module for Kostal Piko Inverter 
=begin html


  <a name="KOSTALPIKO"></a>

  <h3>KOSTALPIKO</h3>

  <div>
    <a name="KOSTALPIKOdefine" id="KOSTALPIKOdefine"></a> <b>Define</b>

    <div>
      <br />
      <code>define &lt;name&gt; KOSTALPIKO &lt;ip-address&gt; &lt;user&gt; &lt;password&gt;</code><br />
      <br />
      The module reads the current values from web page of a Kostal Piko inverter.<br />
      It can also be used, to capture the values of global radiation, UV-index and sunshine duration<br />
      from a special web-site (proplanta) regardless of the existence of the inverter.<br />
      <br />
      <b>Parameters:</b><br />

      <ul>
        <li><b>&lt;ip-address&gt;</b> - the ip address of the inverter</li>

        <li><b>&lt;user&gt;</b> - the login-user for the inverter's web page</li>

        <li><b>&lt;password&gt;</b> - the login-password for the inverter's web page</li>
      </ul><br />
      <br />
      <b>Example:</b><br />

      <div>
        <code>define Kostal KOSTALPIKO 192.168.2.4 pvserver pvwr</code><br />
      </div>
    </div><br />
    <a name="KOSTALPIKOset" id="KOSTALPIKOset"></a> <b>Set-Commands</b>

    <div>
      <br />
      <code>set &lt;name&gt; captureGlobalRadiation</code><br />

      <div>
        The values for global radiation, UV-index and sunshine duration are immediately polled.
      </div><br />
      <br />
      <code>set &lt;name&gt; captureKostalData</code><br />

      <div>
        All values of the inverter are immediately polled.
      </div><br />
    </div><a name="KOSTALPIKOattr" id="KOSTALPIKOattr"></a> <b>Attributes</b><br />
    <br />

    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>

      <li><b>BAEnable</b> - if 1, data from ../BA.fhtml site is captured</li>

      <li><b>GR.Interval</b> - poll interval for global radiation in seconds</li>

      <li><b>GR.Link</b> - regionalised link the to the proplanta web page (global radiation, UV-index and sunshine
      duration)<br />
      (see Wiki for further information)</li>

      <li><b>delay</b> - poll interval for the values of the inverter in seconds</li>

      <li>
        <b>delayCounter</b> - delay counter for poll of invert's values beside AC.Power;<br />
          needed for fast acquisition scenarios to limit the log-output.
      </li>

      <li><b>disable</b> - if disable=1, the poll of inverter's values is disabled,<br /> ut not the the poll of proplanta-values</li>
    </ul><br />
    <br />
    <a name="KOSTALPIKOreading" id="KOSTALPIKOreading"></a> <b>Generated Readings/Events</b><br />
    <br />

    <ul>
      <li><b>AC.Power</b> - the current power, captured only if the internal delayCounter = 0</li>

      <li><b>AC.Power.Fast</b> - the current power, on each poll cycle; used for fast acquisition scenarios</li>

      <li><b>Daily.Energie</b> - the current procduced energie of the day</li>

      <li><b>Daily.Energie.Last</b> - the value of daily energy at 23:00 clock</li>

      <li><b>Global.Radiation</b> - the value of global radiation (proplanta);useful for determing the expected energy amount of the day</li>

      <li><b>ModeNum</b> - the current processing state of the inverter (1=off 2=idle 3=active)</li>

      <li><b>Mode</b> - the german term for the current ModeNum</li>

      <li><b>Total.Energy</b> - the total produced energie</li>

      <li><b>generator.1.current</b> - the electrical current at string 1</li>

      <li><b>generator.2.current</b> - the electrical current at string 2</li>

      <li><b>generator.3.current</b> - the electrical current at string 3</li>

      <li><b>generator.1.voltage</b> - the voltage at string 1</li>

      <li><b>generator.2.voltage</b> - the voltage at string 2</li>

      <li><b>generator.3.voltage</b> - the voltage at string 3</li>

      <li><b>output.1.voltage</b> - the voltage at output 1</li>

      <li><b>output.2.voltage</b> - the voltage at output 2</li>

      <li><b>output.3.voltage</b> - the voltage at output 3</li>

      <li><b>output.1.power</b> - the power at output 1</li>

      <li><b>output.2.power</b> - the power at output 2</li>

      <li><b>output.3.power</b> - the power at output 3</li>

      <li><b>sensor.1</b> - the voltage at analog input 1</li>

      <li><b>sensor.2</b> - the voltage at analog input 2</li>

      <li><b>sensor.3</b> - the voltage at analog input 3</li>

      <li><b>sensor.4</b> - the voltage at analog input 4</li>

      <li><b>UV.Index</b> - the UV Index (proplanta)</li>

      <li><b>sunshine.duration</b> - the sunshine duration (proplanta)</li>
    </ul><br />
    <b>Additional Readings/Events, if BAEnable=1</b><br />
    <br />

    <ul>
      <li><b>Battery.CycleCount</b> - count of charge cycles</li>

      <li><b>Battery.StateOfCharge</b> - State of charge for the battery in percent</li>

      <li><b>Battery.Voltage</b> - the voltage of the battery</li>

      <li><b>Battery.ChargeCurrent</b> - the charge current of the battery</li>

      <li><b>Battery.Temperature</b> - the temperature of the battery</li>

      <li><b>Power.Solar</b> - the sum of the power produced by the solarinverter</li>

      <li><b>Power.Battery</b> - the power drawn from the battery</li>

      <li><b>Power.Net</b> - the power drawn from the main</li>

      <li><b>Power.Phase1</b> - the power used on phase L1</li>

      <li><b>Power.Phase2</b> - the power used on phase L2</li>

      <li><b>Power.Phase3</b> - the power used on phase L3</li>
    </ul><br />
    <br />
    <b>Additional information</b><br />
    <br />

    <ul>
      <li><a href="http://forum.fhem.de/index.php/topic,24409.msg175253.html#msg175253">Discussion in FHEM forum</a></li>
      <li><a href="http://www.fhemwiki.de/wiki/KostalPiko#FHEM-Modul">Information in FHEM Wiki</a></li>
    </ul>
  </div>


=end html
=cut
