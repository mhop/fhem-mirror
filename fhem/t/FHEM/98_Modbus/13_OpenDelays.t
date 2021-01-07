##############################################
# test master slave end to end
# attr disable
# and set inactive / set active
##############################################
package main;
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use Data::Dumper;

my $closeTime;
my $openTime;
my $startTime;

InternalTimer(gettimeofday() + 0.1, "testStep1", 0);


sub getLogTime {
    my $regex = shift;
    my $times = shift // 1;
    is(FhemTestUtils_gotLog($regex), $times, "search $regex in log");
    my $time = FhemTestUtils_getLogTime($regex, 'last');
    Log3 undef, 1, "Test: found $regex in log at $startTime " . FmtTimeMs($time) if $time;
    return $time;
}


sub testStep1 {     # preparation of slave content, enable devices
    Log3 undef, 1, "----------------";    
    #is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    Log3 undef, 1, "TestStep1: enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave Test1 1');
    fhem ('setreading Slave Test2 2.123');
    fhem ('setreading Slave Test3 abcdefg');
    fhem ('setreading Slave Test4 40');   

    InternalTimer(gettimeofday() + 0.1, "testStep2", 0);
}

sub testStep2 {     # get holding registers 
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep2: get TempWasserEin";
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 3');
    fhem ('get Master TempWasserEin');
    InternalTimer(gettimeofday() + 0.1, "testStep3", 0);
}

sub testStep3 {     # check first result, disable and request again
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep3: check result, disable master and request again";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value from local slave");
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master disable 1');
    fhem ('get Master TempWasserEin');

    InternalTimer(gettimeofday(), "testStep4", 0);
}

sub testStep4 {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep4: check that master disable worked";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for disabled");
    is(FhemTestUtils_gotEvent(qr/Master:disabled/xms), 1, "state disabled");
    fhem ('attr Master disable 0');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    InternalTimer(gettimeofday() + 0.1, "testStep5", 0);
}

sub testStep5 {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep5: now set master inactive";
    $startTime = getLogTime ('Master device opened');
    fhem ('attr Master enableSetInactive 1');
    fhem ('set Master inactive');
    InternalTimer(gettimeofday(), "testStep6", 0);
}

sub testStep6 {    
    Log3 undef, 1, "----------------";     
    Log3 undef, 1, "TestStep6: now try to get reading again";
    fhem ('get Master TempWasserEin');
    InternalTimer(gettimeofday(), "testStep7a", 0);
}

sub testStep7a {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep7a: check if reading was not requested and then set master to active again";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for inactive");
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master nextOpenDelay2 0');              # don't wait with open 
    fhem ('set Master active');
    InternalTimer(gettimeofday(), "testStep7b", 0);
}

sub testStep7b {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep7b: try retrieve again";
    $openTime = getLogTime ('Master device opened');
    Log3 undef, 1, "TestStep7b: Time diff is " . sprintf ('%.3f', $openTime - $startTime);
    ok($openTime - $startTime < 0.25, 'time between two open calls is smaller than 0.25');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('get Master TempWasserEin');
    InternalTimer(gettimeofday() + 0.1, "testStep8", 0);
}


sub testStep8 {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep8: check result and then set slave to inactive and try again";    
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value again from local slave");
    fhem ('set Slave inactive');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master dev-timing-timeout 0.2');    
    fhem ('attr Master openTimeout 0.5');               # 
    fhem ('attr Master nextOpenDelay2 0.1');            # 
    fhem ('attr Master nextOpenDelay 1');               # can not be smaller than 1
    fhem ('get Master TempWasserEin');                  # should run into timeout
    InternalTimer(gettimeofday()+0.5, "testStep8b", 0);
}

sub testStep8b {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep8b: check that request was not answered and get last open time";    
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for inactive Slave");
    #is(FhemTestUtils_gotLog('Master: Timeout waiting for a modbus response'), 1, "saw timeout");
    $startTime = getLogTime ('HttpUtils url=http://localhost:5501');    # time of first try
    fhem ('set Slave active');
    InternalTimer(gettimeofday()+1, "testStep8c", 0);
}


sub testStep8c {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep8c: ";    
    InternalTimer(gettimeofday()+1, "testStep9a", 0);
}


sub testStep9a {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep9a: check nextOpenDelay";    
    $openTime = getLogTime ('5501 reappeared');
    Log3 undef, 1, "TestStep7b: Time diff is " . sprintf ('%.3f', $openTime - $startTime);
    ok($openTime - $startTime >= 1, 'time between two open calls is bigger than 1');
    ok($openTime - $startTime < 2, 'time between two open calls is smaller than 2');
    InternalTimer(gettimeofday() + 0.1, "testStep9b", 0);
}

sub testStep9b {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep9b: ";    
    InternalTimer(gettimeofday(), "testStep9c", 0);
}

sub testStep9c {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep9b: retrieve value and then let Slave close after inactivity timeout";    
    # now open should happen and event should come
    fhem('attr Slave dev-timing-serverTimeout 1');
    fhem('attr Slave dev-timing-serverTimeout 1');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('get Master TempWasserEin');
    InternalTimer(gettimeofday() + 1.1, "testStep10", 0);
}

sub testStep10 {    
    # check that we now got the value
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep10: check successful retrieve after slave is active again and master did open connection";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value again from local slave");
    InternalTimer(gettimeofday() + 0.5, "testStep11", 0);
}

sub testStep11 {    
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep11:";
    InternalTimer(gettimeofday() + 1, "testStep12", 0);
}

sub testStep12 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep12:";
    InternalTimer(gettimeofday() + 1, "testStep13", 0);
}

sub testStep13 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep13:";
    InternalTimer(gettimeofday(), "testStepEnd", 0);
}


sub testStepX {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStepX: ";
    #fhem ('get ');
    InternalTimer(gettimeofday() + 0.1, "testStepEnd", 0);
}


sub testStepEnd {
    done_testing;
    exit(0);
}


1;
