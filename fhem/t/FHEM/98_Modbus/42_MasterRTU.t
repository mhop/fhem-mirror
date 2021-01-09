##############################################
# test modbus RTU Master
##############################################

package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes             qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils    qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

fhem 'attr global mseclog 1';
NextStep();


sub testStep1 {
    LogStep('start reread');
    FhemTestUtils_resetLogs();
    fhem('set PWP reread');
    return;
}


sub testStep2 {
    LogStep('simulate normal reception');
    SimRead('MS', '05030a0137110001381100010dac7b');        # normal response 
    return;
}


sub testStep3 {
    LogStep('check reception and start second reread');
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Ein:\s31\.1/xms), 1, "Parse TempEin");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Aus:\s31\.2/xms), 1, "Parse TempAus");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Verdampfer:\s26\.9/xms), 1, "Parse TempVerdampfer");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    fhem('set PWP reread');
    return;
}


sub testStep4 {
    LogStep('simulate short response');
    SimRead('MS', '05030a013711000138110091a8');            # short response
    return 1.1;         # next step after 1.1 seconds
}


sub testStep5 {
    LogStep('verify failed short response and then allow them and reread');
    is(FhemTestUtils_gotLog('frame that looks valid but is too short'), 1, "short frame");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Ein:\s31\.1/xms), 0, "No TempEin");
    
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    fhem('attr PWP dev-h-allowShortResponses 1');
    fhem('set PWP reread');
    return;
}


sub testStep6 {
    LogStep('simulate another short response');
    SimRead('MS', '05030a013711000138110091a8');            # short response
    return;
}


sub testStep7 {
    LogStep('verify valid short response reception and send another reread');
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Ein:\s31\.1/xms), 1, "Parse TempEin");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Aus:\s31\.2/xms), 1, "Parse TempAus");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Verdampfer:\s26\.9/xms), 0, "No Parse TempVerdampfer");
    
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    fhem('attr PWP dev-h-brokenFC3 1');
    fhem('set PWP reread');
    return;
}


sub testStep8 {
    LogStep('simulate broken fc3 response');
    SimRead('MS', '050301000137110001381100010dd04d');      # response type broken FC3
    return;
}


sub testStep9 {
    LogStep('verify brokenfc3 reception and send another reread');
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Ein:\s31\.1/xms), 1, "Parse TempEin");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Wasser_Aus:\s31\.2/xms), 1, "Parse TempAus");
    is(FhemTestUtils_gotEvent(qr/PWP:Temp_Verdampfer:\s26\.9/xms), 1, "Parse TempVerdampfer");
    
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    fhem('attr PWP dev-h-brokenFC3 0');
    return 0.1;
}

sub testStep10 {
    LogStep('check polldelay');
    fhem('attr PWP obj-h256-polldelay 0');
    fhem('attr PWP obj-h258-polldelay 0');
    fhem('attr PWP obj-h260-polldelay 0.4');
    fhem('set PWP reread');
    return;
}

sub testStep11 {
    LogStep('check results');
    is(FhemTestUtils_gotLog('Simulate sending to none: 05030100000305b3'), 1, "request for 256 and 258 without 260 seen");
    return;
}


1;
