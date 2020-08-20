##############################################
# test redirects
##############################################
use strict;
use warnings;
use Test::More;

fhem('set H2 reread');

is(FhemTestUtils_gotLog("AddToQueue prepends type update to URL http://test.url/"), 1, "Match redirected url");

done_testing;
exit(0);

1;
