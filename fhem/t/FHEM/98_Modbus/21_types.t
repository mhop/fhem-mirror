##############################################
# test master slave end to end
# also map, min max, ...
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
    #fhem 'setreading Slave Test1 99';
    return;
}

sub testStep2 {     # get holding registers
    LogStep "";
    fhem 'attr Master verbose 5';
    fhem 'attr Slave verbose 3'; 
    fhem 'set Master reread';
    return 0.1;
}

sub testStep3 {     # check results
    LogStep "check result";
    fhem 'attr Master verbose 3';
    fhem 'attr Slave verbose 3';
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 99/), 1, "Retrieve ");
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 99/), 1, "Retrieve ");
    return;
}


1;
