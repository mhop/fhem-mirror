##############################################
# test master slave end to end
# focus on closeAfterResponse and reopening
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
    fhem 'attr Master verbose 5';
    fhem 'attr Master closeAfterResponse 1';
    fhem 'attr Master queueDelay 0.01';
    fhem 'attr Master dev-timing-sendDelay 0';
    fhem 'attr Master dev-timing-commDelay 0';
    
    fhem 'attr Master disable 0';
    fhem 'setreading Slave TempWasserEin 12';
    fhem 'setreading Slave Test1 1';
    return 0.1;
}

sub testStep2 {     # get holding registers 
    LogStep "reread";
    fhem 'attr Slave verbose 3'; 
    #fhem 'get Master TempWasserEin';
    fhem 'set Master reread';
    return 0.3;
}

sub testStep3 {     # check results
    LogStep "check result";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value from local slave");
    is(FhemTestUtils_gotLog('Master device opened'), 1, "one open");
    CheckAndReset();
    
    fhem 'attr Master closeAfterResponse 2';
    fhem 'set Master reread';
    return 0.3;
}

sub testStep4 { 
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value from local slave");
    is(FhemTestUtils_gotLog('Master device opened'), 2, "two opens");
    return 0.2;
}

sub testStep5 {     # 
    return 0.2;
}


1;
