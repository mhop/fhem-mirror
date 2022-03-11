##############################################
# $Id$
#

package RHASSPY::Demo;    ## no critic 'Package declaration'

use strict;
use warnings;
use JSON;
use Encode;
use List::Util qw(max min);

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          AttrVal
          InternalVal
          ReadingsVal
          ReadingsNum
          ReadingsAge
          fhem
          Log3
          decode
          defs
          round
          )
    );
}

sub ::RHASSPY_Utils_Demo_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub BasicTest {
    my $site = shift; 
    my $type = shift;
    Log3('rhasspy',3 , "RHASSPY: Site $site, Type $type");
    return "RHASSPY: Site $site, Type $type";
}

sub DataTest {
    my $name = shift; 
    my $rawd = shift;

    my $hash = $defs{$name} // return;
    my $data;
    if ( !eval { $data  = decode_json($rawd) ; 1 } ) {
        Log3($hash->{NAME}, 1, "JSON decoding error, $rawd seems not to be valid JSON data:  $@");
        return "Error! $rawd seems not to be valid JSON data!";
    }
    my $site = $data->{siteId};
    my $type = $data->{Type};
    Log3('rhasspy',3 , "RHASSPY: Site $site, Type $type");
    my @devices = sort keys %{$hash->{helper}{devicemap}->{devices}};
    while (@devices > 2) {
        shift @devices; # limit triggered devices two to minimize unwanted side effects
    }
    my @rets;

    $rets[0] = "RHASSPY: Site $site, Type $type";
    $rets[1] = join q{,}, @devices;
    return \@rets;
}

sub DialogueTest{
    my $name = shift; 
    my $rawd = shift;

    my $hash = $defs{$name} // return;
    my $data;
    if ( !eval { $data  = decode_json($rawd) ; 1 } ) {
        Log3($hash->{NAME}, 1, "JSON decoding error, $rawd seems not to be valid JSON data:  $@");
        return "Error! $rawd seems not to be valid JSON data!";
    }
    my $site = $data->{siteId};
    my $type = $data->{Type};
    Log3('rhasspy',3 , "RHASSPY: Site $site, Type $type");
    my @devices = sort keys %{$hash->{helper}{devicemap}->{devices}};
    while (@devices > 2) {
        shift @devices; # limit triggered devices two to minimize unwanted side effects
    }
    my @rets;

    #interactive dialogue as described in https://rhasspy.readthedocs.io/en/latest/reference/#dialoguemanager_continuesession and https://docs.snips.ai/articles/platform/dialog/multi-turn-dialog

    #This example here just lets you confirm the action, as intent filter is limited to ConfirmAction 

    my $response = "RHASSPY asking for OK or cancellation: Site $site, Type $type";
    my $ca_string = qq{$hash->{LANGUAGE}.$hash->{fhemId}:ConfirmAction};
    my $reaction = { text         => $response, 
                     intentFilter => ["$ca_string"] };

    $rets[0] = $reaction;
    $rets[2] = 30; #timeout to replace default timeout

    return \@rets;
}

1;

__END__

=pod
=begin html

<a name="RHASSPY_Demo_Utils"></a>
<h3>RHASSPY_Demo_Utils</h3>
<ul>
  <b>Routines to demonstrate how to handle function calls from within Custom intents in RHASSPY context</b><br> 
  <li>BasicTest</li>
  This is to demonstrate how to get single elements from the message hash just by their name.</p>
  Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents SetCustomIntentsBasicTest=RHASSPY::Demo::BasicTest(siteId,Type)</code></p>
  <li>DataTest</li>
  This is to demonstrate how to get NAME and entire message hash and return a list of devices that may have been triggered. This is just a showcase to extended options and might be a good starting point for developing own complex Custom Intent functions.</p>
  Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents SetCustomIntentsDataTest=RHASSPY::Demo::DataTest(NAME,DATA)</code></p>
  <li>DialogueTest</li>
  This is to demonstrate how to keep dialogue open for some time and dynamically fill a slot for possible answer values to the dialoge. This is not fully tested jet and might somewhen in time be a good starting point for developing own complex Custom Intent functions including dialogues.</p>
  Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents SetCustomIntentsDialogueTest=RHASSPY::Demo::DialogueTest(NAME,DATA)</code></p>
</ul>
=end html
=cut
