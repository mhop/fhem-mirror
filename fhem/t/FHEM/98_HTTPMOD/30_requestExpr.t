##############################################
# test Expressions in config
##############################################
use strict;
use warnings;
use Test::More;


fhem('attr H1 verbose 5');
fhem('attr H1 get02IExpr $vale');
is(FhemTestUtils_gotLog('attr H1 get02IExpr \$vale : Invalid Expression'), 1, "perl syntax check in attrs");

fhem('get H1 TestGet');

is(FhemTestUtils_gotLog("with timeout 2 to file://t/FHEM/98_HTTPMOD/JSON.testdata"), 1, "URL Expression log");
is(FhemTestUtils_gotLog("header Content-Type: application/json345"), 1, "Header expression in log");
is(FhemTestUtils_gotLog(", data Post Data for Test567"), 1, "Post Data expression in log");

fhem('set H2 reread');
is(FhemTestUtils_gotEvent(qr/H2:TestReading:\s336/xms), 1, "Regex Reading creation with OExpr Expression");
is(FhemTestUtils_gotEvent("H2:TestReading2-10: UDP"), 1, "Regex multiple Reading creation");

is(FhemTestUtils_gotEvent("H2:CombReading: tvlights 0 Off SimpleColor"), 1, "Reading recombine expresion");
is(FhemTestUtils_gotLog(qr/HandleSendQueue\ssends\supdate.*header:\sContent-Type:\sTest-Content.*TestHeader:\sT1E2S3T/xms), 1, "requestHeader");

fhem('set H2 TestSet1 4');
is(FhemTestUtils_gotLog("TestSet1 PostData 8"), 1, "set IExpr1 to Post Data in log");

done_testing;
exit(0);

1;
