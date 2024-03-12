##############################################
# test master timeout
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
    return 0.1;
}

sub testStep2 {     # get holding registers 
    fhem 'attr Master showError 1';
    LogStep "get TempWasserEin";
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 5'); 
    fhem ('get Master TempWasserEin');
    return 0.4;
}

sub testStep3 {     # check results
    LogStep "check result";
    fhem ('attr Master verbose 3');
    fhem ('attr Slave verbose 3');
    is(FhemTestUtils_gotEvent('timeout waiting'), 1, "Got timeout in reading");
    return;
}

sub testStep4 {     # redefine slave
    fhem 'attr Master disable 1';
    fhem 'defmod Slave ModbusAttr 5 slave global:5501';
    fhem 'attr Master disable 0';
    return 0.2;
}

sub testStep5 {     # get holding registers 
    fhem 'attr Slave verbose 5'; 
    fhem 'attr Master verbose 5';
    fhem 'get Master Test1';
    return 0.2;
}

sub testStep6 {     # check results
    LogStep "check result";
    is(FhemTestUtils_gotEvent('slave replied with error code'), 1, "Got error code");
    return;
}
1;
