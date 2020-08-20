##############################################
# test MaxAge
##############################################
use strict;
use warnings;
use Test::More;

fhem('get H1 G1');
is(FhemTestUtils_gotEvent("H1:TestReading1: 168"), 1, "Normal Reading 1");
is(FhemTestUtils_gotEvent("H1:TestReading2-1: Off"), 1, "Normal Reading 2");

sleep 0.15;

fhem('setreading H1 tr 789');
fhem('get H1 G2');

is(FhemTestUtils_gotEvent("H1:TestReading1: outdated"), 1, "Outdated Reading 1 with mode text");
is(FhemTestUtils_gotEvent("H1:TestReading2-1: old - was Off"), 1, "Outdated Reading 2 with mode expression");
is(FhemTestUtils_gotEvent("H1:TestReading2-2: 789"), 1, "Outdated Reading 3 with mode reading");
is(FhemTestUtils_gotEvent("H1:TestReading2-3: H1"), 1, "Outdated Reading 4 with mode internal");
is(FhemTestUtils_gotEvent("H1:TestReading2-4:"), 1, "Outdated Reading 5 with mode delete");

done_testing;
exit(0);

1;
