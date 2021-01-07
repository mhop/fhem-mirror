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
InternalTimer(gettimeofday()+5, "testStepLast", 0);            # last resort
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
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);   

    fhem ('setreading Slave c0 1');
    fhem ('setreading Slave c5 1');
    fhem ('setreading Slave c17 1');
    return 0.1;
}

sub testStep2 {     # get holding registers 
    LogStep "get TempWasserEin";
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 5');
    fhem ('get Master TempWasserEin');
    fhem ('get Master Test1');
    fhem ('get Master Test2');
    fhem ('get Master Test3');
    fhem ('get Master Test4');
    fhem ('get Master Test5');
    return 0.3;
}

sub testStep3 { 
    fhem 'set Master reread';
    return 0.3;
}

sub testStep4 { 
    fhem 'set Master reread';
    return 0.3;
}




1;
