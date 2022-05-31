##############################################
# test map
#
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

NextStep();

sub testStep1 {
    LogStep "Read and process data";
    fhem('set H1 reread');
}

sub testStep2 {
    LogStep "check results";
    is(FhemTestUtils_gotEvent(qr/H1:TestReading1:\smedium/xms), 1, "match simple regex match with map");
    is(FhemTestUtils_gotEvent(qr/H1:TestReading2:\s4/xms), 1, "match simple regex match with map and no match - keep input value");
    CheckAndReset();
}

1;
