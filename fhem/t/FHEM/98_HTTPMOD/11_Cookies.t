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
    plan tests => 3;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

fhem('set H1 reread');

#print Dumper($defs{H1});

fhem('set H1 reread');

is(FhemTestUtils_gotLog(qr/sends update with .*header.*DE630e14e5/s), 1, "Match cookie 1 in second request");
is(FhemTestUtils_gotLog(qr/sends update with .*header.*CgAD4ACBfTP9kM2Y5ZjQ1YmUxNzQwYTRjYzM0OTY5YzQzZmZmZmY2Z/s), 1, "Match cookie 2 in second request");
is(FhemTestUtils_gotLog(qr/sends update with .*header.*23000000/s), 1, "Match cookie 3 in second request");

done_testing;
exit(0);

1;
