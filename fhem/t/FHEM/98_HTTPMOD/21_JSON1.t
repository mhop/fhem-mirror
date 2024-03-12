##############################################
# test redirects
# perl /opt/fhem/fhem.pl -t /opt/fhem/t/...
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

is(FhemTestUtils_gotEvent('H2:data_viewer_home_consumption_nodes_01_consumption:' ), 1, "got empty reading ");


done_testing;
exit(0);

1;
