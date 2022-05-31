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
    plan tests => 2;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem 'set H1 Msg Hallo Du da';
is(FhemTestUtils_gotLog("HandleSendQueue sends set01 with timeout.*text=Hallo Du da"), 1, "send normal request");
FhemTestUtils_resetLogs();

fhem 'attr H1 set01IExpr $val =~ s/\s/%20/g;; $val;';
fhem 'set H1 Msg Hallo Du da';
is(FhemTestUtils_gotLog("HandleSendQueue sends set01 with timeout.*text=Hallo%20Du%20da"), 1, "send normal request");
FhemTestUtils_resetLogs();


done_testing;
exit(0);

1;
