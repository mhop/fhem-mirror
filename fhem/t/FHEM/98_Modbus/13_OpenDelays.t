##############################################
# test open delays
##############################################
package main;
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);
use Data::Dumper;

my $closeTime;
my $openTime;
my $startTime;

NextStep();

sub getLogTime {
    my $regex = shift;
    my $times = shift // 1;
    is(FhemTestUtils_gotLog($regex), $times, "search $regex in log");
    my $time = FhemTestUtils_getLogTime($regex, 'last');
    Log3 undef, 1, "Test: found $regex in log at $startTime " . FmtTimeMs($time) if $time;
    return $time;
}

sub testStep1 {     # preparation of slave content, enable devices
    #is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    LogStep "TestStep1: enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave TempWasserAus 23');
    fhem ('setreading Slave Test1 1');
    fhem ('setreading Slave Test2 2.123');
    fhem ('setreading Slave Test3 abcdefg');
    fhem ('setreading Slave Test4 40');   
    return 0.1;
}

sub testStep2 {     # get holding registers 
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 3');
    fhem ('get Master TempWasserEin');
    return 0.1;
}

sub testStep3 {     # check first result, disable and request again
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value from local slave");
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master disable 1');
    fhem ('get Master TempWasserEin');
    return;
}

sub testStep4 {     
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for disabled");
    is(FhemTestUtils_gotEvent(qr/Master:disabled/xms), 1, "state disabled");
    fhem ('attr Master disable 0');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    return 0.1;
}

sub testStep5 {     
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep5: now set master inactive";
    $startTime = getLogTime ('Master device opened');
    fhem ('attr Master enableSetInactive 1');
    fhem ('set Master inactive');
    return;
}

sub testStep6 {    
    Log3 undef, 1, "----------------";     
    Log3 undef, 1, "TestStep6: now try to get reading again";
    fhem ('get Master TempWasserEin');
    return;
}

sub testStep7 {     
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for inactive");
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master nextOpenDelay2 0');              # don't wait with open 
    fhem ('set Master active');
    return;
}

sub testStep8 {     
    $openTime = getLogTime ('Master device opened');
    Log3 undef, 1, "Test: Time diff is " . sprintf ('%.3f', $openTime - $startTime);
    ok($openTime - $startTime < 0.25, 'time between two open calls is smaller than 0.25');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('get Master TempWasserAus');
    return 0.2;
}


sub testStep9 {     
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserAus:\s23/xms), 1, "Retrieve integer value again from local slave");
    fhem ('set Slave inactive');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master dev-timing-timeout 0.2');    
    fhem ('attr Master openTimeout 0.5');               # 
    fhem ('attr Master nextOpenDelay2 0.1');            # 
    fhem ('attr Master nextOpenDelay 1');               # can not be smaller than 1
    fhem ('get Master TempWasserEin');                  # should run into timeout
    return 0.5;
}

sub testStep10 {     
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "no Retrieve for inactive Slave");
    #is(FhemTestUtils_gotLog('Master: Timeout waiting for a modbus response'), 1, "saw timeout");
    $startTime = getLogTime ('HttpUtils url=http://localhost:5501');    # time of first try
    fhem ('set Slave active');
    return 1.0;
}


sub testStep11 {     
    return 1.0;
}


sub testStep12 {     
    $openTime = getLogTime ('5501 reappeared');
    Log3 undef, 1, "TestStep12: Time diff is " . sprintf ('%.3f', $openTime - $startTime);
    ok($openTime - $startTime >= 1, 'time between two open calls is bigger than 1');
    ok($openTime - $startTime < 2, 'time between two open calls is smaller than 2');
    return 0.1;
}

sub testStep13 {     
    return;
}

sub testStep14 {     
    # now open should happen and event should come
    fhem('attr Slave dev-timing-serverTimeout 1');
    fhem('attr Slave dev-timing-serverTimeout 1');
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('get Master TempWasserEin');
    return 1.1;
}

sub testStep15 {    
    # check that we now got the value
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value again from local slave");
    return 0.5;
}

sub testStep16 {    
    return;
}

1;
