################################################
# test Set
################################################
package FHEM::BRAVIA;

use strict;
use warnings;
use Test::More;

# used to import of FHEM functions from fhem.pl
use GPUtils qw(:all);
BEGIN {
    GP_Import(
        qw(
            fhem
            FhemTestUtils_gotLog
            FhemTestUtils_resetLogs
        )
    );
}

# execute checkRegistration
{
    CheckRegistration($::defs{tv});
}
is(FhemTestUtils_gotLog("BRAVIA tv: authCookie not valid ' '"), 1, "Registration missing");

FhemTestUtils_resetLogs();

fhem('setreading tv authCookie test');
{
    CheckRegistration($::defs{tv});
}
is(FhemTestUtils_gotLog("BRAVIA tv: authCookie not valid '.*'"), 0, "Registration valid");
is(FhemTestUtils_gotLog("BRAVIA tv: registration valid until .*"), 1, "Registration period");

done_testing;
exit(0);

1;