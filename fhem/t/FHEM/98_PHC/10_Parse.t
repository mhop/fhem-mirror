##############################################
# test parsing
##############################################

use strict;
use warnings;
use Test::More;

my $hash = $defs{'PHC'};
$hash->{helper}{buffer} = pack ('H*', '0c011224490c0100b77a4301463411430200062a1f');
PHC::ParseFrames($hash);

is(FhemTestUtils_gotEvent("EMD12i01: Ein > 0"), 1, "EMD Event");
is(FhemTestUtils_gotEvent("Arbeiten-Deckenlampe_Mitte: 1"), 1, "AMD Feedback Event 1");
is(FhemTestUtils_gotEvent("Wohnen-Auslass_ueber_Bar_Aquarium: 0"), 1, "AMD Feedback Event 2");

fhem ('set PHC AZLicht ein>0');
is(FhemTestUtils_gotLog("PHC: sends 1a01a2e3af"), 1, "sending virtual EMD");

fhem 'attr PHC verbose 5';
$hash->{helper}{buffer} = pack ('H*', '0d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108400101ebc8400201400d04408101274440820140e108');
PHC::ParseFrames($hash);
# todo: check


$hash->{helper}{buffer} = pack ('H*', 'a183086700cbc8a18200818d6e');
PHC::ParseFrames($hash);
is(FhemTestUtils_gotEvent("DIM01o00: Heller Dimmen"), 1, "DIM Event");


$hash->{helper}{buffer} = pack ('H*', 'a18309070042f7a18200818d6e');
PHC::ParseFrames($hash);
is(FhemTestUtils_gotEvent("DIM01o00: Dunkler Dimmen"), 1, "DIM Event2");


done_testing;

exit(0);

1;





