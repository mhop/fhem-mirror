##############################################
# test Auth Tokens
##############################################
use strict;
use warnings;
use Test::More;
use Data::Dumper;

my $hash = $defs{'H1'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 1;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem('set H1 reread');

#print Dumper($defs{H1});

is($hash->{TOKENS}{ACCESS_TOKEN}, "2YotnFZFEjr1zCsicMWpAA", "got token");

done_testing;
exit(0);

1;
