##############################################
# test cookies
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
    plan tests => 7;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem 'get H1 O1';

is(FhemTestUtils_gotEvent("O1: <h1>Test</h1>"), 1, "got O1");
is(FhemTestUtils_gotEvent("O2: ter>"), 1, "got O2");
is(FhemTestUtils_gotEvent("O3: enter>"), 1, "got O3");

fhem 'attr H1 maxGetChain 1';
FhemTestUtils_resetLogs();
FhemTestUtils_resetEvents();

fhem 'get H1 O1';

is(FhemTestUtils_gotEvent("O1: <h1>Test</h1>"), 1, "got O1");
is(FhemTestUtils_gotEvent("O2: ter>"), 1, "got O2");
is(FhemTestUtils_gotEvent("O3: enter>"), 0, "no O3, chain too long");
is(FhemTestUtils_gotLog("chain would get longer "), 1, "chain too long");

done_testing;
exit(0);

1;
