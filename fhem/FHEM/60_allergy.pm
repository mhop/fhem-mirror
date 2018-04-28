##############################################
# $Id$$$
#
#  60_allergy.pm
#
#  2017 Markus Moises < vorname at nachname . de >
#
#  This module provides allergy forecast data
#
#  http://forum.fhem.de/index.php/topic,37194.0.html
#
#
##############################################################################
#
# define <name> allergy <zipcode>
#
##############################################################################

package main;

use strict;
use warnings;
use Time::Local;
use Encode;

use XML::Simple;
use LWP::UserAgent;
use HTTP::Request;

use utf8;


my %pollen_types = (  0 => "Unknown",
                      1 => "Ahorn",
                      2 => "Ambrosia",
                      3 => "Beifuss",
                      4 => "Birke",
                      5 => "Brennnessel",
                      6 => "Buche",
                      7 => "Eiche",
                      8 => "Erle",
                      9 => "Esche",
                      10 => "Fichte",
                      11 => "Flieder",
                      12 => "Gaensefuss",
                      13 => "Gerste",
                      14 => "Graeser",
                      15 => "Hafer",
                      16 => "Hasel",
                      17 => "Holunder",
                      18 => "Hopfen",
                      19 => "Kiefer",
                      20 => "Linde",
                      21 => "Loewenzahn",
                      22 => "Mais",
                      23 => "Nessel",
                      24 => "Pappel",
                      25 => "Platane",
                      26 => "Raps",
                      27 => "Roggen",
                      28 => "Rotbuche",
                      29 => "Spitzwegerich",
                      30 => "Tanne",
                      31 => "Ulme",
                      32 => "Weide",
                      33 => "Weizen", );

##############################################################################


sub allergy_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}        = "allergy_Define";
  $hash->{UndefFn}      = "allergy_Undefine";
  $hash->{GetFn}        = "allergy_Get";
  $hash->{AttrFn}       = "allergy_Attr";
  $hash->{AttrList}     = "disable:0,1 ".
                          "ignoreList ".
                          "updateIgnored:1,0 ".
                          "updateEmpty:1,0 ".
                          "levelsFormat ".
                          "weekdaysFormat ".
                          "extended5Day:1,0 ".
                          $readingFnAttributes;
}

sub allergy_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($found, $dummy);

  return "syntax: define <name> allergy <zipcode>" if(int(@a) != 3 );
  my $name = $hash->{NAME};

  $hash->{helper}{ZIPCODE} = $a[2];
  $hash->{helper}{INTERVAL} = 10800;
  $hash->{ERROR} = 0;

  my $req = eval
  {
    require XML::Simple;
    XML::Simple->import();
    require JSON;
    JSON->import();
    1;
  };

  if($req)
  {
    InternalTimer( gettimeofday() + 60, "allergy_GetUpdate", $hash, 0);
    if (!defined($attr{$name}{stateFormat}))
    {
      $attr{$name}{stateFormat} = 'fc1_maximum';
    }
  }
  else
  {
    $hash->{STATE} = "XML::Simple and JSON is required!";
    $attr{$name}{disable} = "1";
    return undef;
  }

  $hash->{STATE} = "Initialized";

  return undef;
}

sub allergy_Undefine($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  #fhem("deletereading $name fc.*", 1);
  return undef;
}


sub allergy_Get($@) {
  my ($hash, @a) = @_;
  my $command = $a[1];
  my $parameter = $a[2] if(defined($a[2]));
  my $name = $hash->{NAME};


  my $usage = "Unknown argument $command, choose one of data:noArg ";

  return $usage if $command eq '?';

  RemoveInternalTimer($hash);

  if(AttrVal($name, "disable", 0) eq 1) {
    $hash->{STATE} = "disabled";
    return "allergy $name is disabled. Aborting...";
  }

  allergy_GetUpdate($hash);

  return undef;
}


sub allergy_GetUpdate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(AttrVal($name, "disable", 0) eq 1) {
    $hash->{STATE} = "disabled";
    Log3 ($name, 2, "allergy $name is disabled, data update cancelled.");
    return undef;
  }




  my $url="http://www.allergie.hexal.de/pollenflug/xml-interface-neu/pollen_de_7tage.php?plz=".$hash->{helper}{ZIPCODE};

  if(AttrVal($name, "extended5Day", 0) eq 1) {
    $url="https://pollenwarner-live.herokuapp.com/pollen/".$hash->{helper}{ZIPCODE};
  Log3 ($name, 4, "Getting URL $url");
    HttpUtils_NonblockingGet({
      url => $url,
      noshutdown => 1,
      hash => $hash,
      type => 'allergydata',
      callback => \&allergy_ParseExtended,
    });
    return undef;
  }

  Log3 ($name, 4, "Getting URL $url");

  HttpUtils_NonblockingGet({
    url => $url,
    noshutdown => 1,
    hash => $hash,
    type => 'allergydata',
    callback => \&allergy_Parse,
  });



  return undef;


}


sub allergy_Parse($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err )
  {
    Log3 $name, 1, "$name: URL error (".($hash->{ERROR}+1)."): ".$err;
    my $nextupdate = gettimeofday()+( (900*$hash->{ERROR}) + 90 );
    InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);
    $hash->{STATE} = "error" if($hash->{ERROR} > 1);
    $hash->{ERROR} = $hash->{ERROR}+1;
    return undef;
  }

  $hash->{ERROR} = 0;
  Log3 $name, 5, "Received XML data ".$data;

  my $xml = new XML::Simple();
  #my $xmldata = $xml->XMLin($data,forcearray => [qw( pollenbelastungen pollen )],keyattr => {pollen => 'name'});
  my $xmldata = eval { $xml->XMLin($data,forcearray => [qw( pollenbelastungen pollen )],keyattr => {pollen => 'name'}) };
  if($@)
  {
    Log3 $name, 2, "$name: XML error ".$@;
    my $nextupdate = gettimeofday()+$hash->{helper}{INTERVAL};
    InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);
    return undef;
  }

  my @wdays = split(',',AttrVal($hash->{NAME}, "weekdaysFormat", "Sun,Mon,Tue,Wed,Thu,Fri,Sat" ));
  my @levels = split(',',AttrVal($hash->{NAME}, "levelsFormat", "-,low,moderate,high,extreme" ));

  readingsBeginUpdate($hash); # Start update readings

  my $city = $xmldata->{'pollendaten'}->{'ort'};
  readingsBulkUpdate($hash, "city", allergy_utf8clean($city));
  Log3 $name, 4, "Received data for postcode ".$xmldata->{'pollendaten'}->{'plz'};

  foreach my $day (@{$xmldata->{'pollendaten'}{'pollenbelastungen'}})
  {
    my $daycode = $day->{'tag'}+1;
    my @daydata = $day->{'pollen'};
    my $daymax = 0;
    my $pollenkey='';
    my $pollenvalue='';
    my $pollendata=0;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time+($day->{'tag'}*86400));

    readingsBulkUpdate($hash, "fc".$daycode."_day_of_week", $wdays[$wday]);

    foreach my $pollenhash (@daydata)
    {
      while(($pollenkey, $pollenvalue) = each(%$pollenhash))
      {
        $pollenkey = allergy_utf8clean($pollenkey);
        $pollendata = $pollenvalue->{'belastung'};

      if (( AttrVal($hash->{NAME}, "updateEmpty", 0 ) gt 0 or $pollendata gt 0) and ( AttrVal($hash->{NAME}, "updateIgnored", 0 ) gt 0 or ( index(AttrVal($hash->{NAME}, "ignoreList", ""), $pollenkey ) == -1 )))
      {
        readingsBulkUpdate($hash, "fc".$daycode."_".$pollenkey, $levels[$pollendata]);
        $daymax = $pollendata if($pollendata gt $daymax);
        Log3 $name, 4, "Received pollen level for ".$pollenkey.": day".$daycode." level ".$pollendata;
      }
      else
      {
        fhem( "deletereading $name fc".$daycode."_".$pollenkey, 1 );
        Log3 $name, 5, "Received pollen level for ".$pollenkey.": day".$daycode." level ".$pollendata." (ignored)";
      }

      }


    }
    readingsBulkUpdate($hash, "fc".$daycode."_maximum", $levels[$daymax]);


  }

  readingsEndUpdate($hash, 1);


  $hash->{UPDATED} = FmtDateTime(time());

  my $nextupdate = gettimeofday()+$hash->{helper}{INTERVAL};
  InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);

  return undef;
}

sub allergy_ParseExtended($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err )
  {
    Log3 $name, 1, "$name: URL error (".($hash->{ERROR}+1)."): ".$err;
    my $nextupdate = gettimeofday()+( (900*$hash->{ERROR}) + 90 );
    InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);
    $hash->{STATE} = "error" if($hash->{ERROR} > 1);
    $hash->{ERROR} = $hash->{ERROR}+1;
    return undef;
  }

  $hash->{ERROR} = 0;
  Log3 $name, 5, "Received data ".$data;

  my $json = eval { JSON::decode_json($data) };
  if($@)
  {
    Log3 $name, 2, "$name: JSON error ".$@;
    my $nextupdate = gettimeofday()+$hash->{helper}{INTERVAL};
    InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);
    return undef;
  }

  Log3 $name, 5, "$name: parse json\n".Dumper($json);


  my @wdays = split(',',AttrVal($hash->{NAME}, "weekdaysFormat", "Sun,Mon,Tue,Wed,Thu,Fri,Sat" ));
  my @levels = split(',',AttrVal($hash->{NAME}, "levelsFormat", "-,low,moderate,high,extreme" ));

  readingsBeginUpdate($hash); # Start update readings

  my $city = $json->{region};
  readingsBulkUpdate($hash, "city", allergy_utf8clean($city)) if($json->{region});
  my $day = $json->{date};
  readingsBulkUpdate($hash, "date", $day) if($json->{date});
  Log3 $name, 4, "Received data for postcode ".$json->{region};

  my @daymax;

  return undef if(!defined($json->{polls}));
  #Log3 $name, 1, "found polls ".ref($json->{polls});

  foreach my $pollenid ( keys %{$json->{polls}}) {
    my $pollenid = $json->{polls}->{$pollenid}->{id};
    #Log3 $name, 1, "polls step ".$pollenid;
    my $pollenkey = 'Unknown';
    $pollenkey = $pollen_types{$pollenid} if( defined($pollen_types{$pollenid}) );

    return undef if(!defined($json->{polls}->{$pollenid}->{forecast}));
    #Log3 $name, 1, "forecast ";
    return undef if(ref($json->{polls}->{$pollenid}->{forecast}) ne "ARRAY");

    #my @forecast = $json->{polls}->{$pollenid}->{forecast};

    my $daycode = 0;
    while(defined($json->{polls}->{$pollenid}->{forecast}[$daycode])) {

      my $pollendata = int($json->{polls}->{$pollenid}->{forecast}[$daycode]);
      #Log3 $name, 1, "forecast array".ref($pollendata);

      if (( AttrVal($hash->{NAME}, "updateEmpty", 0 ) gt 0 or $pollendata gt 0) and ( AttrVal($hash->{NAME}, "updateIgnored", 0 ) gt 0 or ( index(AttrVal($hash->{NAME}, "ignoreList", ""), $pollenkey ) == -1 )))
      {
        readingsBulkUpdate($hash, "fc".($daycode+1)."_".$pollenkey, $levels[$pollendata]);
        $daymax[$daycode] = $pollendata if(!defined($daymax[$daycode]) || $pollendata gt $daymax[$daycode]);
        Log3 $name, 4, "Received pollen level for ".$pollenkey.": day".($daycode+1)." level ".$pollendata;
      }
      else
      {
        fhem( "deletereading $name fc".($daycode+1)."_".$pollenkey, 1 );
        Log3 $name, 5, "Received pollen level for ".$pollenkey.": day".($daycode+1)." level ".$pollendata." (ignored)";
      }
      $daymax[$daycode] = 0 if(!defined($daymax[$daycode]));
      $daycode++;
    }
  }

  my $daycode = 0;
  while(defined($daymax[$daycode])) {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time+($daycode*86400));
    readingsBulkUpdate($hash, "fc".($daycode+1)."_day_of_week", $wdays[$wday]);
    readingsBulkUpdate($hash, "fc".($daycode+1)."_maximum", $levels[$daymax[$daycode]]);
    $daycode++;
  }


  readingsEndUpdate($hash, 1);


  $hash->{UPDATED} = FmtDateTime(time());

  my $nextupdate = gettimeofday()+$hash->{helper}{INTERVAL};
  InternalTimer($nextupdate, "allergy_GetUpdate", $hash, 1);

  return undef;
}


sub allergy_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $attrVal = 1;
    } else {
      $attr{$name}{$attrName} = 0;
      allergy_GetUpdate($hash);
    }
  }
  elsif ($attrName eq "extended5Day") {
    fhem("deletereading $name fc.*", 1);
    fhem("deletereading $name date", 1);
    my $hash = $defs{$name};
    allergy_GetUpdate($hash);
  }

  if( $cmd eq "set" ) {
    if( !defined($orig) || $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}




sub allergy_utf8clean($) {
  my ($string) = @_;
  my $log = "";
  if($string !~ m/^[A-Za-z\d_\.-]+$/)
  {
    $log .= $string."(standard) ";
    $string =~ s/Ä/Ae/g;
    $string =~ s/Ö/Oe/g;
    $string =~ s/Ü/Ue/g;
    $string =~ s/ä/ae/g;
    $string =~ s/ö/oe/g;
    $string =~ s/ü/ue/g;
    $string =~ s/ß/ss/g;
  }
  if($string !~ m/^[A-Za-z\d_\.-]+$/)
  {
    $log .= $string."(single) ";
    $string =~ s/Ã„/Ae/g;
    $string =~ s/Ã–/Oe/g;
    $string =~ s/Ãœ/Ue/g;
    $string =~ s/Ã¤/ae/g;
    $string =~ s/Ã¶/oe/g;
    $string =~ s/Ã¼/ue/g;
    $string =~ s/ÃŸ/ss/g;
  }
  if($string !~ m/^[A-Za-z\d_\.-]+$/)
  {
    $log .= $string."(double) ";
    $string =~ s/Ãƒâ€ž/Ae/g;
    $string =~ s/Ãƒâ€“/Oe/g;
    $string =~ s/ÃƒÅ“/Ue/g;
    $string =~ s/ÃƒÂ¤/ae/g;
    $string =~ s/ÃƒÂ¶/oe/g;
    $string =~ s/ÃƒÂ¼/ue/g;
    $string =~ s/ÃƒÅ¸/ss/g;
  }
  if($string !~ m/^[A-Za-z\d_\.-]+$/)
  {
    $log .= $string."(unknown)";
    #$string =~ s/[^!-~\s]//g;
    $string =~ s/[^A-Za-z\d_\.-]//g;
  }
  Log3 "utf8clean", 5, "Cleaned $string // $log" if($log ne "");

  return $string;
}

##########################

1;

=pod
=item device
=item summary Allergy forecast data for Germany
=begin html

<a name="allergy"></a>
<h3>allergy</h3>
<ul>
  This modul provides allergy forecast data for Germany.<br/>
  It requires the Perl module XML::Simple to be installed
  <br/><br/>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allergy &lt;zipcode&gt;</code>
    <br>
    Example: <code>define allergydata allergy 12345</code>
    <br>&nbsp;
    <li><code>zipcode</code>
      <br>
      German zipcode
    </li><br>
  </ul>
  <br>
  <b>Get</b>
   <ul>
      <li><code>data</code>
      <br>
      Manually trigger data update
      </li><br>
  </ul>
  <br>
  <b>Readings</b>
   <ul>
      <li><code>city</code>
      <br>
      Name of the city the forecast is read for
      </li><br>
      <li><code>fc<i>n</i>_total</code>
      <br>
      Daily maximum levels for all allergens that are not being ignored due to <i>ignoreList</i><br/>
      </li><br>
      <li><code>fc<i>n</i>_day_of_week</code>
      <br>
      Weekday, can be localized through <i>weekdaysFormat</i><br/>
      </li><br>
      <li><code>fc<i>n</i>_<i>allergen</i></code>
      <br>
      Daily levels for all allergens that are not being ignored due to <i>ignoreList</i>
      </li><br>
  </ul>
  <br>
   <b>Attributes</b>
   <ul>
      <li><code>ignoreList</code>
         <br>
         Comma-separated list of allergen names that are to be ignored during updates and for cumulated day levels calculation
      </li><br>
      <li><code>updateEmpty</code>
         <br>
         Also update (and keep) level readings for inactive allergens that are otherwise removed
      </li><br>
      <li><code>updateIgnored</code>
         <br>
         Also update (and keep) level readings for ignored allergens that are otherwise removed
      </li><br>
      <li><code>levelsFormat</code>
         <br>
         Localize levels by adding them comma separated (default: -,low,moderate,high,extreme)
      </li><br>
      <li><code>weekdaysFormat</code>
         <br>
         Localize Weekdays by adding them comma separated (default: Sun,Mon,Tue,Wed,Thu,Fr,Sat)
      </li><br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="allergy"></a>
<h3>allergy</h3>
<ul>
  <br>Dieses Modul prognostiziert Allergie Daten für Deutschland.</br>
  Es erfordert dass das Perlmodul XML:: Simple installiert ist.
  <br/><br/>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; allergy &lt;Postleitzahl&gt;</code>
    <br>
    Beispiel: <code>define allergydata allergy 12345</code>
    <br><br>
    <li><code>Postleitzahl</code>
      <br>
      Deutsche Postleitzahl
    </li><br>
  </ul>
  <br>
  <b>Get</b>
   <ul>
      <li><code>data</code>
      <br>
      Manuelles Datenupdate
      </li><br>
  </ul>
  <br>
  <b>Readings</b>
   <ul>
      <li><code>city</code>
      <br>
      Name der Stadt, für die Prognosen gelesen werden.
      </li><br>
    <li><code>fc<i>n</i>_total</code>
      <br>
      Täglicher Höchstwerte für alle Allergene, die nicht aufgrund der Ignoreliste <i>(attr ignoreList)</i> ignoriert werden<br/>
      </li><br>
    <li><code>fc<i>n</i>_day_of_week</code>
      <br>
      Wochentag, kann durch <i>weekdaysFormat</i> lokalisiert werden.<br/>
      </li><br>
      <li><code>fc<i>n</i>_<i>allergen</i></code>
      <br>
      Tägliche Werte für alle Allergene, die nicht aufgrund der Ignoreliste <i>(attr ignoreList)</i> ignoriert werden.
      </li><br>
  </ul>
  <br>
   <b>Attribute</b>
   <ul>
      <li><code>ignoreList</code>
         <br>
         Kommagetrennte Liste von Allergen-Namen, die bei der Aktualisierung ignoriert werden sollen.
    <br>
      </li><br>
      <li><code>updateEmpty (Standard: 0|1)</code>
         <br>
         Aktualisierung von Allergenen.
    <code> <br>
    0 = nur Allergene mit Belastung.
    <br>
    1 = auch Allergene die keine Belastung haben.
    </code>
      </li><br>
      <li><code>updateIgnored (1)</code>
         <br>
         Aktualisierung von Allergenen, die sonst durch die ignoreList entfernt werden.
      </li><br>
      <li><code>extended5Days (1)</code>
         <br>
         Alternative Datenquelle mit 5 Tagen Vorhersage für mehr Allergene
      </li><br>
      <li><code>levelsFormat (Standard: -,low,moderate,high,extreme)</code>
         <br>
         Lokalisierte Levels, durch Kommas getrennt.
      </li><br>
      <li><code>weekdaysFormat (Standard: Sun,Mon,Tue,Wed,Thu,Fri,Sat)</code>
         <br>
         Lokalisierte Wochentage, durch Kommas getrennt.
      </li><br>
  </ul>
</ul>

=end html_DE
=cut