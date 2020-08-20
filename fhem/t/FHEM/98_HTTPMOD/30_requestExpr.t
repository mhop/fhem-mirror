##############################################
# test Expressions in config
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::HTTPMOD::Utils qw(:all);

fhem('attr H1 verbose 5');
fhem('attr H1 get02IExpr $vale');
is(FhemTestUtils_gotLog('attr H1 get02IExpr \$vale : Invalid Expression'), 1, "perl syntax check in attrs");

fhem('get H1 TestGet');

is(FhemTestUtils_gotLog("with timeout 2 to file://t/FHEM/98_HTTPMOD/JSON.testdata"), 1, "URL Expression log");
is(FhemTestUtils_gotLog("header Content-Type: application/json345"), 1, "Header expression in log");
is(FhemTestUtils_gotLog(", data Post Data for Test567"), 1, "Post Data expression in log");

fhem('set H2 reread');
is(FhemTestUtils_gotEvent(qr/H2:TestReading:\s336/xms), 1, "JSON Reading creation with OExpr Expression");
is(FhemTestUtils_gotEvent("H2:TestReading2-8: UDP"), 1, "JSON multiple Reading creation");
is(FhemTestUtils_gotEvent("H2:CombReading: Off SimpleColor RainbowChase"), 1, "Reading recombine expresion");
is(FhemTestUtils_gotLog(qr/HandleSendQueue\ssends\supdate.*header:\sContent-Type:\sTest-Content.*TestHeader:\sT1E2S3T/xms), 1, "requestHeader");

fhem('set H2 TestSet1 4');
is(FhemTestUtils_gotLog("TestSet1 PostData 8"), 1, "set IExpr1 to Post Data in log");

my $hash  = $defs{'H2'};
my $name  = 'H2';
my $val   = 5;
my @array = (1,2,3);
my %tHash = (a => 10, b => 20);
my $exp   = '$val * 2';

my $result = EvalExpr($hash, $exp, {'$val' => $val, '@array' => \@array});
#Log3 $name, 3, "$name: result of EvalExpr test 1 = $result";
is $result, 10, "simple expression with one scalar in list";

$exp   = '$array[1] * 2';
$result = EvalExpr($hash, $exp, {'$val' => $val, '@array' => \@array});
is $result, 4, "simple expression with array ref in hash";

$exp   = '$hash{a} * 2';
$result = EvalExpr($hash, $exp, {'$val' => $val, '%hash' => \%tHash});
is $result, 20, "simple expression with hash ref in hash";

$exp   = '$hash->{a} * 2';
$result = EvalExpr($hash, $exp, {'$val' => $val, '$hash' => \%tHash});
is $result, 20, "simple expression with hash ref as ref in hash";


done_testing;
exit(0);

1;
