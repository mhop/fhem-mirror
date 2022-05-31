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
    fhem ('setreading Slave Lampe 1');
    return 0.1;
}

sub testStep2 {     # get digital input 
    LogStep "retrieve normal values";
    fhem 'attr Master verbose 5';
    fhem 'attr Slave verbose 5'; 
    fhem 'get Master Lampe';
    return 0.3;
}

sub testStep3 {     # check results
    LogStep "check result for normal values";
    is(FhemTestUtils_gotEvent(qr/Master:Lampe:\s1/xms), 1, "Retrieve value 1 from local slave");
    CheckAndReset();
    return;
}

sub testStep10 {     # check doepke fix
    LogStep "use doepke fix";
    fhem 'attr Master dev-d-brokenFC2 doepke';
    fhem 'set Master reread';
    return 0.2;
}

sub testStep11 {     # check results
    LogStep "check result for combined inputs with doepke fix sumulation";
    is(FhemTestUtils_gotEvent(qr/Master:Lampe:\s0/xms), 1, "Retrieve value 0 from local slave");
    CheckAndReset();
    return;
}

1;
