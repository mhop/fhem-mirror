##############################################
# test replacements
#
##############################################
use strict;
use warnings;
use Test::More;

fhem('set GeoTest reread');


InternalTimer(time()+1, sub() {
    is(FhemTestUtils_gotLog(qr/Read callback: Error: geocache\-planer.*date=[\d]+\.\d+\.\d+/), 1, "Expr replacement in URL");
    done_testing;
    exit(0);
}, 0);

1;
