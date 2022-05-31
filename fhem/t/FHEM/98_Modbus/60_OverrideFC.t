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

    fhem 'setreading Slave c0 1';
    fhem 'setreading Slave c5 1';
    fhem 'setreading Slave c17 1';
    return 0.1;
}


sub testStep10 {    # check combined read of holding registers and coils
    LogStep "getUpdate with combine";
    fhem 'attr Master verbose 5'; # 3
    fhem 'attr Slave verbose 3';
    fhem 'set Master reread';
    return 0.2;
}

sub testStep11 {    # check results coming from slave and write coils to slave
    is(FhemTestUtils_gotEvent(qr/Master:c0: 1/), 1, "Combined Retrieve coil bit 0 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c1: 0/), 1, "Combined Retrieve coil bit 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c5: 1/), 1, "Combined Retrieve coil bit 5 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c17: 1/), 1, "Combined Retrieve coil bit 17 from local slave");
    is(FhemTestUtils_gotLog('GetUpdate will now create requests for c400 len 18'), 1, "log for combined coils");

    fhem 'attr Slave obj-c402-allowWrite 1';
    fhem 'attr Master verbose 5';
    fhem 'set Master c2 1';
    return 0.1;
}

sub testStep12 {
    LogStep "check coil comm";
    
    is(FhemTestUtils_gotLog('sending 05050192ff002daf'), 1, "set c2 1 sending message in log");
    is(FhemTestUtils_gotEvent(qr/Master:c2: 1/), 1, "fc5 response for coil shows 1 from local slave");
    return 0.4;
}


sub testStep20 {    
    LogStep "override FC";
    fhem ('attr Master obj-c400-overrideFCread 99');
    fhem ('set Master reread');
    return 0.1;
}

sub testStep21 {
    LogStep "check overridden comm";
    is(FhemTestUtils_gotLog('cant combine c400 len 1 c0 with c405 len 1 c5, different function codes'), 1, "prevent combining different FCs");
    return 0.5;
}


sub testStep30 {
    LogStep "override coil write FC";
    fhem 'attr Master obj-c400-overrideFCwrite 6';
    fhem 'attr Slave obj-h400-allowWrite 1';          # arrives as h400 on slave side
    fhem 'attr Slave verbose 5';
    fhem 'set Master c0 1';
    return 0.1;
}

sub testStep31 {
    LogStep "check overridden write to coil";
    is(FhemTestUtils_gotEvent(qr/Slave:DummyRegister: 1/), 1, "DummyRegister set to 1");
    CheckAndReset();
    return 0.1;
}



sub testStep40 {
    LogStep "override holding register write FC";
    fhem 'attr Master obj-h400-reading Dummy2';
    fhem 'attr Master obj-h400-overrideFCwrite 5';
    fhem 'attr Slave obj-c400-allowWrite 1';        # h400 now arrives as c400
    fhem 'set Master Dummy2 255';
    return 0.1;
}

sub testStep41 {
    LogStep "check overridden write to holding register";
    #is(FhemTestUtils_gotEvent(qr/Slave:DummyRegister: 1/), 1, "DummyRegister set to 1");
    CheckAndReset();
    return 0.1;
}


1;
