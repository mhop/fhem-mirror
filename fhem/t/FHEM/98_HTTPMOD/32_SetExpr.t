##############################################
# test set expressions
##############################################
use strict;
use warnings;
use Test::More;
#use Data::Dumper;

my $hash = $defs{'H1'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 3;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem 'set H1 Msg Hallo Du da';
is(FhemTestUtils_gotLog("HandleSendQueue sends set01 with timeout.*text=Hallo Du da"), 1, "send normal request");
FhemTestUtils_resetLogs();

fhem 'attr H1 set01IExpr $val =~ s/\s/%20/g;; $val;';
fhem 'set H1 Msg Hallo Du da';
is(FhemTestUtils_gotLog("HandleSendQueue sends set01 with timeout.*text=Hallo%20Du%20da"), 1, "send S1 request");
FhemTestUtils_resetLogs();


fhem 'attr H1 set02ValueSeparator ,';
#fhem 'attr H1 set02TextArg ,';
fhem 'set H1 S2 1,22,333';
is(FhemTestUtils_gotLog("HandleSendQueue sends .*v1=1&v2=22&v3=333"), 1, "send S2 request");
FhemTestUtils_resetLogs();


done_testing;
exit(0);

1;
