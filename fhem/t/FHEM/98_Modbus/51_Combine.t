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
    fhem 'setreading Slave TempWasserEin 12';
    fhem 'setreading Slave Test1 1';
    fhem 'setreading Slave Test2 2.123';
    fhem 'setreading Slave Test3 abcdefg';
    fhem 'setreading Slave Test4 40';
    fhem 'setreading Slave Test5 10';
    fhem 'setreading Slave Test6 6';
    fhem 'setreading Slave c0 1';
    fhem 'setreading Slave c5 1';
    fhem 'setreading Slave c17 1';
    fhem 'attr Master verbose 5';   # 4
    fhem 'attr Slave verbose 3';    #3
    CheckAndReset();
    return 0.1;
}


sub testStep10 {    # check combined read of holding registers and coils
    LogStep "getUpdate with combine";
    fhem 'set Master reread';
    return 0.7;
}

sub testStep11 {    # check results coming from slave 
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Combined retrieve integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 2.12/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test3: abcdefg/), 1, "Combined Retrieve ascii value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c0: 1/), 1, "Combined Retrieve coil bit 0 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c1: 0/), 1, "Combined Retrieve coil bit 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c17: 1/), 1, "Combined Retrieve coil bit 17 from local slave");

    ok(FhemTestUtils_gotLog('read fc 3 h100, len 7') >= 2,'saw right first combination in log');
    ok(FhemTestUtils_gotLog('read fc 3 h120, len 13') >= 2,'saw right second combination in log');

    CheckAndReset();
    return 0.1;
}

sub testStep20 {    # check timeout handling / logging
    LogStep "getUpdate with timeout";
    fhem 'defmod Slave ModbusAttr 55 slave global:5501';
    fhem 'attr Master dev-timing-timeout 0.2';
    fhem 'set Master reread';
    return 1.5;
}


sub testStep21 {    # check results coming from slave 
    ok(FhemTestUtils_gotLog('Timeout waiting for a modbus response') > 1,'timeout for missing salve');
    return;
}



1;
