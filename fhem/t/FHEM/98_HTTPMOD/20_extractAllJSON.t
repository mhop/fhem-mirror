##############################################
# test extractAllReadings
##############################################
use strict;
use warnings;
use Test::More;

eval "use JSON";
if ($@) {
    plan skip_all => "This test checks an optional JSON-Feature of HTTPMOD and can only be run with the JSON library installed. Please install JSON Library (apt-get install libjson-perl)";
} else {
    plan tests => 3;
}


fhem('set H1 reread');
InternalTimer(time()+1, sub() {

    is(FhemTestUtils_gotLog("Read response matched 24"), 1, "Match 24 Readings log");
    is(FhemTestUtils_gotEvent("H1:MQTT_ip_1: 168"), 1, "Reading creation 1");
    is(FhemTestUtils_gotEvent("H1:modes_2: RainbowChase"), 1, "Reading creation 2");

    done_testing;
    exit(0);
}, 0);

1;
