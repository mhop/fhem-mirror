##############################################
# test communication delays
##############################################
package main;
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

my %rData = (
'010403d1000221b6' => '01040400000000fb84',
'010404c100022107' => '010404000041b4cba3',
'0104060100022083' => '0104045262419dbb1b',
'01040691000220ae' => '010404000042524ad9',
'01040a4100022207' => '010404533c458c19',
'01040a61000223cd' => '01040400000000fb84',
'01040a810002223b' => '0104049dff454cd77d',
'01040aa1000223f1' => '01040400000000fb84',
'01040ac1000223ef' => '0104044d6345282e78',
'01040ae100022225' => '010404b6f644980f54',
'010411d1000224ce' => '01040400000000fb84',

'050303020001240a' => '0503020122c80d',
'05030309000155c8' => '05030200004984',
'0503010600016473' => '0503020106c816',
'05030100000585b1' => '05030a0137110001381100010dac7b',
'0503010000018472' => '050302013709c2',

'0506030900005808' => '0506030900005808',                   # set hyst mode
'0506030201182850' => '0506030201182850'                    # set temp soll 28
);

fhem 'attr global mseclog 1';

SetTestOptions(
    {   IODevice      => 'MS',                                    # for loginform
        RespondTo     => 'MS: Simulate sending to none: (.*)',    # auto reponder / go to next step at reception
        ResponseHash  => \%rData,                                 # to find the right response

        Time1Name     => 'Sending',
        Time1Regex    => qr{MS:\sSimulate\ssending},
        Time2Name     => 'Reception',
        Time2Regex    => qr{ParseFrameStart\s\(RTU\)\sextracted\sid},
    }                                
);                             


fhem 'get M1 SolarTemp';        # will cause step 1 to be called when send is detected and response is simulated

sub testStep1 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    
    is(FhemTestUtils_gotEvent('M1:SolarTemp'), 1, "Event SolarTemp ...");
    
    fhem 'get M1 HeatOff';
    # read simulation is triggered when sending is seen in the log.
    # next step is called when read simulation is done.
    return 'wait';
}


sub testStep2 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    # check no delay between read (get SolarTemp) after Step 0 and send (get HeatOff) in step 1
    ok($commDelay < 0.1, 'normal delay from read solar temp to send get HeatOff smaller than 0.1');
    
    fhem 'attr M1 dev-timing-sendDelay 0.2';            # send in step2 should be 0.2 after send in step1
    fhem 'get M1 HeatOff';
    return 'wait';
}


sub testStep3 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    # check send delay between read (get HeatOff) after Step 1 and send (get HeatOff) in step 2
    ok($sendDelay >= 0.2, 'defined send delay from read HeatOff to next send get HeatOff big enough');
    ok($sendDelay < 0.25, 'defined send delay from read HeatOff to next send get HeatOff not too big');
    
    fhem 'get M5 TempWasserEin';
    return 'wait';
}


sub testStep4 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();

    # check no send delay between read (get HeatOff) after Step 2 and send (get TempWasserEin to id 5) in step 3
    ok($sendDelay < 0.15, 'defined send delay on id 1 from read HeatOff to send get TempWasserEin not used for id 5');
    
    fhem 'attr MS busDelay 0.2';
    fhem 'get M5 TempWasserAus';            # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep5 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    # check bus delay between read (get TempWasserEin) after Step 3 and send (get TempWasserAus) in step 4
    ok($commDelay >= 0.2, 'defined bus delay big enough');
    ok($commDelay < 0.3, 'defined bus delay not too big');
    
    fhem 'attr MS busDelay 0';
    fhem 'attr M1 dev-timing-sendDelay 0';
    fhem 'attr MS clientSwitchDelay 0';
    fhem 'get M1 SolarTemp';                # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep6 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    ok($sendDelay < 0.2, 'no delay');
    fhem 'attr MS clientSwitchDelay 0.2';
    fhem 'get M5 TempWasserEin';            # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep7 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    ok($commDelay >= 0.2, 'defined clsw delay big enough');
    ok($commDelay < 0.3, 'defined clsw delay not too big');
    
    fhem 'get M5 TempWasserAus';            # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep8 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    ok($sendDelay < 0.2, 'no delay for same id');
    
    fhem 'attr M5 dev-timing-commDelay 0.2';  
    fhem 'get M5 TempWasserEin';            # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep9 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    ok($commDelay >= 0.2, 'defined comm delay big enough');
    ok($commDelay < 0.22, 'defined comm delay not too big');

    fhem 'attr M5 dev-timing-commDelay 0';  
    fhem 'get M5 TempWasserEin';            # new request, go to next step when response is simulated
    return 'wait';  
}


sub testStep10 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay) = calcDelays();
    
    ok($commDelay < 0.07, 'zero comm delay');
    
    fhem 'attr M5 dev-timing-commDelay 0.2';  
    fhem 'attr M5 verbose 4';  
    fhem 'set M5 o1 on';                    # new request, go to next step when response is simulated
    return 'wait';
}


sub testStep11 {
    findTimesInLog();
    my ($commDelay, $sendDelay) = calcDelays();
    
    is(FhemTestUtils_gotLog('commDelay not over.*sleep'), 1, "sleep message in log");
    ok($commDelay >0.2, 'forced comm delay big enough');
    ok($commDelay < 0.22, 'forced comm delay not too big');
    FhemTestUtils_resetLogs();
    return;
}


1;
