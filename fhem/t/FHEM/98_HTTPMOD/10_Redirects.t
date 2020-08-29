##############################################
# test redirects
##############################################
use strict;
use warnings;
use Test::More;

my $hash = $defs{'H2'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 1;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem('set H2 reread');

is(FhemTestUtils_gotLog("AddToQueue prepends type update to URL http://test.url/"), 1, "Match redirected url");

done_testing;
exit(0);

1;
