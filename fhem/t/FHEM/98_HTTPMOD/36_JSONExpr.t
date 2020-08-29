################################################
# test Expressions with JSON readings in config
################################################
use strict;
use warnings;
use Test::More;

eval "use JSON";
if ($@) {
    plan skip_all => "This test checks an optional JSON-Feature of HTTPMOD and can only be run with the JSON library installed. Please install JSON Library (apt-get install libjson-perl)";
} else {
    plan tests => 5;
}

fhem('set H2 reread');
is(FhemTestUtils_gotEvent(qr/H2:TestReading:\s336/xms), 1, "JSON Reading creation with OExpr Expression");
is(FhemTestUtils_gotEvent("H2:TestReading2-8: UDP"), 1, "JSON multiple Reading creation");
is(FhemTestUtils_gotEvent("H2:CombReading: Off SimpleColor RainbowChase"), 1, "Reading recombine expresion");
is(FhemTestUtils_gotLog(qr/HandleSendQueue\ssends\supdate.*header:\sContent-Type:\sTest-Content.*TestHeader:\sT1E2S3T/xms), 1, "requestHeader");

fhem('attr H1 verbose 5');
fhem('set H2 TestSet1 4');
is(FhemTestUtils_gotLog("TestSet1 PostData 8"), 1, "set IExpr1 to Post Data in log");

done_testing;
exit(0);

1;
