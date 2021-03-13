##############################################
# test passive reception
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
    LogStep "send first request in parts";
    FhemTestUtils_resetLogs();
    SimRead('MS', 'fe03');                    # part of a request
    return;
}


sub testStep2 {
    FhemTestUtils_resetLogs();
    SimRead('MS', '0164000810');              # part of a request
    return;
}


sub testStep3 {
    FhemTestUtils_resetLogs();
    SimRead('MS', '20');                      # final part of a request
    return;
}


sub testStep4 {
    LogStep "check reception of request and send another request";
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "first request reassembled correctly");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', 'fe03016400081020');        # another request
    return;
}


sub testStep5 {
    LogStep "check reception of repeated request and send first reply";
    is(FhemTestUtils_gotLog('no valid response -> try interpretation as request instead'), 1, "corectly detected invalid respone and switch to request");
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "second request interpreted");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', 'fe03100000000b000000400000011a00000167f378');   # the reply
    return;
}


sub testStep6 {
    LogStep "check reception of reply and send another repeated reply";
    is(FhemTestUtils_gotLog('has no information about handling h356'), 1, "try parsing registers");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', 'fe03100000000b000000400000011a00000167f378');   # the reply repeated
    return;
}


sub testStep7 {
    LogStep "check reception of repeated reply";
    is(FhemTestUtils_gotLog('has no information about handling'), 0, "no try parsing registers again since request is missing");   
    is(FhemTestUtils_gotLog('HandleResponse got data but we don.t have a request'), 1, "next response without a request seen");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();    
    SimRead('MS', 'fe03064000810209');        # a broken frame
    return;
}


sub testStep8 {
    is(FhemTestUtils_gotLog('HandleRequest Done, error: '), 1, "invalid frame");
    FhemTestUtils_resetLogs();
    SimRead('MS', 'fe03016400081020');        # another request
    return;
}

sub testStep9 {
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "request after garbage interpreted");
    FhemTestUtils_resetLogs();
    return;
}


sub testStep10 {
    LogStep "check broken frame with illegal fcode";
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();    
    SimRead('MS', 'fe00064000810209');        # a broken frame
    return;
}


sub testStep11 {
    is(FhemTestUtils_gotLog('HandleRequest Done, error:'), 1, "invalid frame");
    FhemTestUtils_resetLogs();
    SimRead('MS', 'fe03016400081020');        # another request
    return;
}

sub testStep12 {
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "request after illegal fcode interpreted");
    FhemTestUtils_resetLogs();
    return;
}


1;
