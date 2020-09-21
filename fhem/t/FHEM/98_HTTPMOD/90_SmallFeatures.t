##############################################
# test other small features
##############################################
use strict;
use warnings;
use Test::More;

my $hash = $defs{'H2'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 3;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem('attr H2 bodyDecode none');
fhem('attr H2 readingEncode none');
fhem('set H2 reread');

SKIP: {
    skip "this test can only run on Linux", 1 if (!-e "/proc/$$/status");
    is(FhemTestUtils_gotEvent("H2:Fhem_Mem"), 1, "memReading");
}

is(FhemTestUtils_gotEvent("H2:TestReading1: \x8e\x6e"), 1, "TestReading without bodyDecode");

fhem('attr H2 bodyDecode auto');
fhem('attr H2 readingEncode utf8');
fhem('set H2 reread');

is(FhemTestUtils_gotEvent("H2:TestReading1: \xc3\x84\x6e"), 1, "TestReading with body decode");

done_testing;
exit(0);

1;
