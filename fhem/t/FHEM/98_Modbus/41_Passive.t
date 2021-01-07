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

#$logInform{'MS'} = \&ReactOnSendingLog;

my @rData = (

    '05030100000585b1',                     # request       h 256 - h 260 (TempWasserEin, TempWasserAus)
    '05030a0137110001381100010dac7b',       # response

    '0503010600016473',                     # request       h 262
    '0503020106c816',                       # response

    '050303020001240a',                     # request       h 770
    '0503020122c80d',                       # response

    '05030309000155c8',                     # request
    '05030200004984',                       # response

    '0503010000018472',
    '050302013709c2',                       # response

    '0506030900005808',                     # request   set hyst mode
    '0506030900005808',                     # response

    '0506030201182850',                     # request   set temp soll 28
    '0506030201182850'                      # response
);
my $dataPtr  = 0;

fhem 'attr global mseclog 1';
InternalTimer(gettimeofday()+5, "testStepLast", 0);             # last resort
NextStep();


sub testStep1 {
    LogStep "send first request in parts";
    FhemTestUtils_resetLogs();
    SimRead('MS', \&Modbus::ReadFn, 'fe03');                    # part of a request
    return;
}


sub testStep2 {
    FhemTestUtils_resetLogs();
    SimRead('MS', \&Modbus::ReadFn, '0164000810');              # part of a request
    return;
}


sub testStep3 {
    FhemTestUtils_resetLogs();
    SimRead('MS', \&Modbus::ReadFn, '20');                      # final part of a request
    return;
}


sub testStep4 {
    LogStep "check reception of request and send another request";
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "first request reassembled correctly");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', \&Modbus::ReadFn, 'fe03016400081020');        # another request
    return;
}


sub testStep5 {
    LogStep "check reception of repeated request and send first reply";
    is(FhemTestUtils_gotLog('no valid response -> try interpretation as request instead'), 1, "invalid respone and switch to request");
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "second request interpreted");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', \&Modbus::ReadFn,'fe03100000000b000000400000011a00000167f378');   # the reply
    return;
}


sub testStep6 {
    LogStep "check reception of reply and send another repeated reply";
    is(FhemTestUtils_gotLog('ParseObj has no information about handling h356'), 1, "try parsing registers");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('MS', \&Modbus::ReadFn,'fe03100000000b000000400000011a00000167f378');   # the reply repeated
    return;
}


sub testStep7 {
    LogStep "check reception of repeated reply";
    is(FhemTestUtils_gotLog('ParseObj has no information about handling'), 0, "no try parsing registers again since request is missing");   
    is(FhemTestUtils_gotLog('HandleResponse got data but we don.t have a request'), 1, "next response without a request seen");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();    
    SimRead('MS', \&Modbus::ReadFn, 'fe03064000810209');        # a broken frame
    return;
}


sub testStep8 {
    is(FhemTestUtils_gotLog('HandleRequest Done, error: '), 1, "invalid frame");
    FhemTestUtils_resetLogs();
    SimRead('MS', \&Modbus::ReadFn, 'fe03016400081020');        # another request
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
    SimRead('MS', \&Modbus::ReadFn, 'fe00064000810209');        # a broken frame
    return;
}


sub testStep11 {
    is(FhemTestUtils_gotLog('HandleRequest Done, error:'), 1, "invalid frame");
    FhemTestUtils_resetLogs();
    SimRead('MS', \&Modbus::ReadFn, 'fe03016400081020');        # another request
    return;
}

sub testStep12 {
    is(FhemTestUtils_gotLog('received valid request, now wait for the reponse'), 1, "request after illegal fcode interpreted");
    FhemTestUtils_resetLogs();
    return;
}


1;
