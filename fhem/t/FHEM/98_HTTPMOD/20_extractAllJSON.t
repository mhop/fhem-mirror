##############################################
# test extractAllReadings
##############################################
use strict;
use warnings;
use Test::More;

fhem('set H1 reread');
InternalTimer(time()+1, sub() {

    is(FhemTestUtils_gotLog("Read response matched 24"), 1, "Match 24 Readings log");
    is(FhemTestUtils_gotEvent("H1:MQTT_ip_1: 168"), 1, "Reading creation 1");
    is(FhemTestUtils_gotEvent("H1:modes_2: RainbowChase"), 1, "Reading creation 2");

    done_testing;
    exit(0);
}, 0);

1;
