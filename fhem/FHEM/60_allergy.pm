##############################################
# $Id$$$
#
#  60_allergy.pm
#
#  2015 Markus Moises < vorname at nachname . de >
#
#  This module provides allergy forecast data
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



##############################################################################


sub allergy_Initialize($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{DefFn}		=	"allergy_Define";
  $hash->{UndefFn}	=	"allergy_Undefine";
  $hash->{GetFn}		=	"allergy_Get";
  $hash->{AttrList}	=	"disable:0,1 ".
						"ignoreList ".
						"updateIgnored:1 ".
						"updateEmpty:1 ".
						"levelsFormat ".
						"weekdaysFormat ".
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

  my $req = eval
  {
    require XML::Simple;
    XML::Simple->import();
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
    $hash->{STATE} = "XML::Simple is required!";
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
  fhem("deletereading $name fc.*", 1);
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
    Log3 $name, 1, "$name: URL error: ".$err;
    $hash->{STATE} = "error";
    return undef;
  }

  Log3 $name, 5, "Received XML data ".$data;

  my $xml = new XML::Simple();
  #my $xmldata = $xml->XMLin($data);
  my $xmldata = $xml->XMLin($data,forcearray => [qw( pollenbelastungen pollen )],keyattr => {pollen => 'name'});

  my @wdays = split(',',AttrVal($hash->{NAME}, "weekdaysFormat", "Sun,Mon,Tue,Wed,Thu,Fri,Sat" ));
  my @levels = split(',',AttrVal($hash->{NAME}, "levelsFormat", "-,low,moderate,high,extreme" ));

  readingsBeginUpdate($hash); # Start update readings

  my $city = Encode::encode('UTF-8',$xmldata->{'pollendaten'}->{'ort'});
  readingsBulkUpdate($hash, "city", $city);
  Log3 $name, 4, "Received data for postcode ".$xmldata->{'pollendaten'}->{'plz'};

  my %umlaute = ( '�' => 'Ae', '�' => 'Oe', '�' => 'Ue', '�' => 'ae', '�' => 'oe', '�' => 'ue', '�' => 'ss' );
  my $umlautkeys = join ("|", keys(%umlaute));

  foreach my $day (@{$xmldata->{'pollendaten'}{'pollenbelastungen'}})
  {
    my $daycode = $day->{'tag'}+1;
    my @daydata = $day->{'pollen'};
    my $daymax = 0;
    my $pollenkey='';
    my $pollenvalue='';
    my $pollenname='';
    my $pollendata=0;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time+($day->{'tag'}*86400));

    readingsBulkUpdate($hash, "fc".$daycode."_day_of_week", $wdays[$wday]);

    foreach my $pollenhash (@daydata)
    {
      while(($pollenkey, $pollenvalue) = each(%$pollenhash))
      {
        # $pollenname = Encode::encode('UTF-8',$pollenkey);
        $pollenkey =~ s/($umlautkeys)/$umlaute{$1}/g;
        $pollendata = $pollenvalue->{'belastung'};

      if (( AttrVal($hash->{NAME}, "updateEmpty", 0 ) gt 0 or $pollendata gt 0) and ( AttrVal($hash->{NAME}, "updateIgnored", 0 ) gt 0 or ( index(AttrVal($hash->{NAME}, "ignoreList", ""), $pollenname ) == -1 )))
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




##########################

1;

=pod
=begin html

<a name="allergy"></a>
<h3>allergy</h3>
(en | <a href="commandref_DE.html#allergy">de</a>)
<div style="width:800px">
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
         Localize levels by adding them comma separated (default: -,low,moderate,high)
      </li><br>
      <li><code>weekdaysFormat</code>
         <br>
         Localize Weekdays by adding them comma separated (default: Sun,Mon,Tue,Wed,Thu,Fr,Sat)
      </li><br>
  </ul>
</ul>
</div>
=end html

=cut
