# Simple test. NOTE: exit(0) is necessary
use strict;
use warnings;
use Test::More;

{ MQTT2_SERVER_ReadDebug($defs{m2s}, '0(12)(0)(5)helloworld') }
is(FhemTestUtils_gotLog("ERROR:.*bogus data"), 0, "Correct MQTT message");

FhemTestUtils_resetLogs();
{MQTT2_SERVER_ReadDebug($defs{m2s}, '(162)(50)(164)(252)(0).7c:2f:80:97:b0:98/GenericAc(130)(26)(212)4(0)(21)BLE2MQTT/OTA/')}
is(FhemTestUtils_gotLog("ERROR:.*bogus data"), 1, "Bogus message, as expected");

done_testing;
exit(0);
1;
