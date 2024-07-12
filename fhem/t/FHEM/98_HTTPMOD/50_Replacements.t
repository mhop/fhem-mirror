##############################################
# test replacements
#
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

NextStep();

sub testStep1 {
    fhem 'attr H verbose 5';
    #fhem 'attr H getReplacement01Value {"new"."val"}';
    fhem 'attr H get01Replacement01Value {"new"."val" err}';
    #is(FhemTestUtils_gotLog('3 : Invalid Expression'), 1, "found invalid expression");
    is(FhemTestUtils_gotLog('3\s*:\s*Invalid Expression'), 1, "found invalid expression");
    fhem 'attr H get01Replacement01Value {"new"."val"}';
    CheckAndReset();
    fhem 'attr H get01Data01 header%%date%%';
    fhem 'get H get01';
    return 0;
}

sub testStep2 {
    LogStep "check results";
    is(FhemTestUtils_gotLog('data: headernewval'), 1, "did replacement");
}

1;
