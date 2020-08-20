##############################################
# test other small features
##############################################
use strict;
use warnings;
use Test::More;

fhem('attr H2 bodyDecode none');
fhem('set H2 reread');

is(FhemTestUtils_gotEvent("H2:Fhem_Mem"), 1, "memReading");
is(FhemTestUtils_gotEvent("H2:TestReading1: \x8e\x6e"), 1, "TestReading without bodyDecode");

fhem('attr H2 bodyDecode auto');
fhem('set H2 reread');

is(FhemTestUtils_gotEvent("H2:TestReading1: \xc4\x6e"), 1, "TestReading with body decode");

done_testing;
exit(0);

1;
