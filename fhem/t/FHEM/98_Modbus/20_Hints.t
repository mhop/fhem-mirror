##############################################
# test hints for set
##############################################
use strict;
use warnings;
use Test::More;

fhem 'set M1 ?';
is(FhemTestUtils_gotLog('choose one of .* o1:off,on o2:1,2,3'), 1, "hints in log");

InternalTimer(gettimeofday() + 0.2, "testStepEnd", 0);

sub testStepEnd {
    done_testing;
    exit(0);
}

1;
