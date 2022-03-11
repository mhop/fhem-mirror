##############################################
# $Id$
#

package RHASSPY::siteId2room;    ## no critic 'Package declaration'

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
          ReadingsVal
          readingsSingleUpdate
          Log3
          decode
          defs
          makeReadingName
          )
    );
}

sub ::RHASSPY_Utils_siteId2room_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

sub siteId2room {
    my $name = shift; 
    my $rawd = shift;

    my $hash = $defs{$name} // return;
    my $data;
    if ( !eval { $data  = decode_json($rawd) ; 1 } ) {
        Log3($hash->{NAME}, 1, "JSON decoding error, $rawd seems not to be valid JSON data:  $@");
        return "Error! $rawd seems not to be valid JSON data!";
    }
    my $site = encode('UTF-8',$data->{siteId});
    my $room = encode('UTF-8',$data->{Room});
    my $rreading = makeReadingName("siteId2room_$site");
    
    readingsSingleUpdate($hash, $rreading, $room, 1);

    Log3($name, 5, "RHASSPY: Site $site now is in room $room");

    my @rets;

    $rets[0] = "Habe den Raum von $site auf $room geändert";
    $rets[1] = $name;
    return \@rets;
}


1;

__END__

=pod
=begin html

<a name="RHASSPY_Utils_siteId2room"></a>
<h3>RHASSPY_Utils_siteId2room</h3>
<ul>
  <li>siteId2room</li>
  Routine to change the default room a siteId is assigned to. Might be usefull if you use e.g. your mobile phone as satellite.<br> 
  Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents siteId2room=RHASSPY::siteId2room::siteId2room(NAME,DATA)</code></p>
</ul>
=end html
=cut
