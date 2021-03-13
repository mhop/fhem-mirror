##############################################
# test update timer 
##############################################
package main;
use strict;
use warnings;
use Test::More;

fhem('set M1 interval 0.2');
is(FhemTestUtils_gotLog("changed interval to 0.2 seconds"), 1, "set interval in log");
fhem('set M1 interval test');
is(FhemTestUtils_gotLog("set interval test not valid"), 1, "invalid interval in log");


InternalTimer(time()+1, sub() {
    isnt(FhemTestUtils_gotLog("GetUpdate .* called from"), 0, "GetUpdate in log");
    isnt(FhemTestUtils_gotLog("UpdateTimer called from.*GetUpdate"), 0, "UpdateTimer in log");

    done_testing;
    exit(0);
}, 0);

1;
