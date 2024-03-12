##############################################
# test custom function codes 
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
    CheckAndReset();
    LogStep "enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave Lampe 123.4');

    fhem ('setreading Slave Test 223.4');
    return 0.1;
}

sub testStep2 {     # get digital input 
    LogStep "retrieve normal values";
    fhem 'get Master Lampe';
    return 0.3;
}

sub testStep3 {     # check results
    LogStep "check result for normal values";
    is(FhemTestUtils_gotEvent(qr/Master:Lampe:\s123.4/xms), 1, "Retrieve value 123.4 from local slave");
    CheckAndReset();
    fhem 'attr Master verbose 5';
    fhem 'attr Slave verbose 5';
    return;
}

sub testStep10 {     # use custom fc now
    LogStep "send request with custom fc";
    fhem 'attr Master dev-h-read 93';
    fhem 'attr Master dev-h-write 96';
    fhem 'get Master Lampe';
    return 0.3;
}

sub testStep11 {     # check results
    LogStep "check result for custom fc";
    is(FhemTestUtils_gotEvent(qr/Master:Lampe:\s223.4/xms), 1, "Retrieve value 123.4 with custom fc from local slave");
    CheckAndReset();
    return;
}

sub testStep20 {     # use custom fc now
    LogStep "send request with custom fc 66 without data";
    fhem 'attr Master verbose 5';
    fhem 'attr Slave verbose 3'; 
    fhem 'attr Master obj-h900-overrideFCwrite 66';
    fhem 'set Master Reset';
    return 0.3;
}

sub testStep21 {     # check results
    LogStep "check result for custom fc";
    is(FhemTestUtils_gotEvent(qr/Master:Reset:\s1/xms), 1, "Reset successful");
    CheckAndReset();
    return;
}

sub testStep30 {     # invalid field 
    LogStep "check attr validation";
    fhem 'attr Master dev-fc66Request-fieldExpr-INVAL 1';
    is(FhemTestUtils_gotLog('invalid field'), 2, "detected invalid field");
    CheckAndReset();
    return;
}

1;
