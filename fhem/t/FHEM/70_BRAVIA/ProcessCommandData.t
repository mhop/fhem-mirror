################################################
# test Set
################################################
package FHEM::BRAVIA;

use strict;
use warnings;
use Test::More;
use JSON qw(decode_json);

# used to import of FHEM functions from fhem.pl
use GPUtils qw(:all);
BEGIN {
    GP_Import(
        qw(
            fhem
            FhemTestUtils_gotEvent
        )
    );
}

# receive getVolumeInformation
{
    my $service = 'getVolumeInformation';
    my %params = (
        hash       => $::defs{tv},
        service    => $service
    );
    ProcessCommandData(\%params, decode_json('{"result":[],"id":2}'));
}
is(FhemTestUtils_gotEvent('tv:volume: 0'), 0, 'getVolumeInformation empty: Reading volume');
is(FhemTestUtils_gotEvent('tv:mute: off'), 0, 'getVolumeInformation empty: Reading mute');

{
    my $service = 'getVolumeInformation';
    my %params = (
        hash       => $::defs{tv},
        service    => $service
    );
    ProcessCommandData(\%params, decode_json('{"result":[[{"target":"headphone","volume":0,"mute":false,"maxVolume":100,"minVolume":0}]],"id":2}'));
}
is(FhemTestUtils_gotEvent('tv:volume: 0'), 1, 'getVolumeInformation headphone: Reading volume');
is(FhemTestUtils_gotEvent('tv:mute: off'), 1, 'getVolumeInformation headphone: Reading mute');

{
    my $service = 'getVolumeInformation';
    my %params = (
        hash       => $::defs{tv},
        service    => $service
    );
    ProcessCommandData(\%params, decode_json('{"result":[[{"target":"headphone","volume":42,"mute":true,"maxVolume":100,"minVolume":0}]],"id":2}'));
}
is(FhemTestUtils_gotEvent('tv:volume: 42'), 1, 'getVolumeInformation speaker: Reading volume');
is(FhemTestUtils_gotEvent('tv:mute: on'), 1, 'getVolumeInformation speaker: Reading mute');

done_testing;
exit(0);

1;