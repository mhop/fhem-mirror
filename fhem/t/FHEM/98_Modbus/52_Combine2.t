##############################################
# test master slave end to end
##############################################

package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

fhem 'attr global mseclog 1';
NextStep();

sub testStep1 {     # preparation of slave content, enable devices
    is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    LogStep "enable Master and set value at Slave";
    fhem 'attr Master disable 0';
    fhem 'setreading Slave Test1 1';
    fhem 'setreading Slave TempWasserEin 12';
    fhem 'setreading Slave TempWasserAus 14';

    fhem 'setreading Slave Test2 2.123';
    fhem 'setreading Slave Test2m 2';

    fhem 'setreading Slave Test4a 10';
    fhem 'setreading Slave Test4b 20';

    fhem 'setreading Slave Test5 10';
    fhem 'setreading Slave Test5m 6';

    # initialize readings at master to check the order later
    fhem 'setreading Master Test1 1';

    fhem 'setreading Master Test2 1';
    fhem 'setreading Master Test2m 1';

    fhem 'setreading Master Test3 1';

    fhem 'setreading Master Test4a 1';
    fhem 'setreading Master Test4b 1';

    fhem 'setreading Master Test5 1';
    fhem 'setreading Master Test5m 1';

    fhem 'attr Master verbose 4';   # 4
    fhem 'attr Slave verbose 3';    #3
    CheckAndReset();
    return 0.1;
}


sub testStep10 {    # check combined read of holding registers and coils
    LogStep "getUpdate with combine";
    fhem 'set Master reread';
    return 1;
}

sub testStep11 {    # check results coming from slave 
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 4.25/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test4b: 30/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test5: 10/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test5m: 6/), 1, "Combined retrieve float value from local slave");

    CheckAndReset();
    return 0.1;
}


1;
