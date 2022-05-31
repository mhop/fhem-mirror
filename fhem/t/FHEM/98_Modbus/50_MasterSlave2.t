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
    CheckAndReset();
    LogStep "enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12.123');
    fhem ('setreading Slave TempWasserAus 32.999');

    return 0.1;
}

sub testStep2 {     # get holding registers 
    LogStep "retrieve normal values";
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 5'); 
    fhem ('set Master reread');
    return 0.3;
}

sub testStep3 {     # check results
    LogStep "check result for normal values";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12.123/xms), 1, "Retrieve float 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserAus:\s32.999/xms), 1, "Retrieve float 2 from local slave");
    CheckAndReset();
    return;
}

sub testStep10 {     # get holding registers with revregs
    LogStep "retrieve values with revRegs";
    fhem ('attr Master obj-h258-revRegs 1');
    fhem ('attr Slave obj-h258-revRegs 1');
    fhem ('set Master reread');
    return 0.3;
}

sub testStep11 {     # check results 2
    LogStep "check result with revRegs";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12.123/xms), 1, "Retrieve float 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserAus:\s32.999/xms), 1, "Retrieve float 2 from local slave");
    CheckAndReset();
    return;
}

sub testStep20 {     # get holding registers with revregs
    LogStep "retrieve values with wrong revRegs";
    fhem ('attr Master obj-h258-revRegs 0');
    fhem ('attr Slave obj-h258-revRegs 1');
    fhem ('set Master reread');
    return 0.3;
}

sub testStep21 {     # check results 2
    LogStep "check result with wrong revRegs";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12.123/xms), 1, "Retrieve float 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserAus:\s32.999/xms), 0, "no valid retrieve float 2 from local slave");
    return;
}

1;
