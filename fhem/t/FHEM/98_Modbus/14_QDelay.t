##############################################
# test queue delays
##############################################
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);


fhem 'attr global mseclog 1';

SetTestOptions(
    {   IODevice    => 'MS',                                    # for loginform
        Time1Name   => 'busy',
        Time1Regex  => qr{Fhem is still waiting},
        Time2Name   => 'queue run',
        Time2Regex  => qr{ProcessRequestQueue called from Fhem internal timer as queue:MS},
    }                                
);                             

NextStep();

sub testStep1 {
    findTimesInLog();
    fhem 'get M1 SolarTemp';
    fhem 'get M5 TempWasserEin';
    return 0.5;
}


sub testStep2 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    return 0.5;
}


sub testStep3 {
    findTimesInLog();
    FhemTestUtils_resetLogs();
    my ($commDelay, $sendDelay, $lastDelay) = calcDelays();
    
    # check no delay between read (get SolarTemp) after Step 0 and send (get HeatOff) in step 1
    ok($sendDelay < 0.5, 'queue delay not too big');
    ok($sendDelay > 0.3, 'queue delay not too small');
    
}

1;
