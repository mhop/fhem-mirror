##############################################
# test master slave with setexpr
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
    fhem ('attr Master obj-h258-setExpr $val * 3');
    fhem ('setreading Slave TempWasserEin 12');
    return 0.1;
}

sub testStep10 {  # set with setexpr   
    fhem ('attr Slave obj-h258-allowWrite 1');
    fhem ('attr Master obj-h258-setexpr $val * 2');
    fhem ('set Master TempWasserAus 20');
    return 0.1;
}

sub testStep11 {     # check that write holding register did work
    LogStep "check result";
    is(FhemTestUtils_gotEvent(qr/Slave:TempWasserAus:\s40/xms), 1, "Write value to local slave");
    return 0.1;
}

sub setExprSub {
    my $val = shift;
    return $val * 3;
}

sub testStep20 {  
    fhem ('attr Slave obj-h258-allowWrite 1');
    fhem ('attr Master obj-h258-setexpr setExprSub ($val)');
    fhem ('attr Master verbose 5');
    fhem ('set Master TempWasserAus 20');
    return 0.1;
}

sub testStep21 {     # check that write holding register did work
    LogStep "check result";
    is(FhemTestUtils_gotEvent(qr/Slave:TempWasserAus:\s60/xms), 1, "Write value to local slave");
    return 0.1;
}

1;
