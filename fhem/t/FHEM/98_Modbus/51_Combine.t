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
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave Test1 1');
    fhem ('setreading Slave Test2 2.123');
    fhem ('setreading Slave Test3 abcdefg');
    fhem ('setreading Slave Test4 40');
    fhem ('setreading Slave c0 1');
    fhem ('setreading Slave c5 1');
    fhem ('setreading Slave c17 1');
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);   
    fhem ('attr Master verbose 4');
    fhem ('attr Slave verbose 3');
    return 0.1;
}


sub testStep10 {    # check combined read of holding registers and coils
    LogStep "getUpdate with combine";
    FhemTestUtils_resetEvents();
    fhem ('set Master reread');
    return 0.2;
}

sub testStep11 {    # check results coming from slave 
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Combined retrieve integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 2.12/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test3: abcdefg/), 1, "Combined Retrieve ascii value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c0: 1/), 1, "Combined Retrieve coil bit 0 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c1: 0/), 1, "Combined Retrieve coil bit 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c17: 1/), 1, "Combined Retrieve coil bit 17 from local slave");

    return 0.1;
}

sub testStep20 {    # check timeout handling / logging
    LogStep "getUpdate with timeout";
    FhemTestUtils_resetEvents();
    fhem 'defmod Slave ModbusAttr 55 slave global:5501';
    fhem 'set Master reread';
    return 1;
}


sub testStep21 {    # check results coming from slave 
    return;
}


1;
