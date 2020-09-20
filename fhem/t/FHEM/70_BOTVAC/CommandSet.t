################################################
# test Set
################################################
package FHEM::BOTVAC;

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
        )
    );
}

# trigger without argument
fhem('set botvac');
is(FhemTestUtils_gotLog('set botvac : No Argument given'), 1, 'Match: No Argument given');

# trigger with unknown argument
fhem('set botvac missing');
is( FhemTestUtils_gotLog('set botvac missing : Unknown argument missing, choose one of password statusRequest:noArg schedule:on,off syncRobots:noArg pollingMode:on,off'),
    1, 'Match: Unknown argument missing' );

# trigger preferences
fhem('setreading botvac pref_filterChangeReminderInterval 3');
fhem('setreading botvac .secretKey testing');
fhem('set botvac filterChangeReminderInterval 1');
is( FhemTestUtils_gotLog('REQ messages/setPreferences'),
    1, 'Match: REQ messages/setPreferences' );
is( FhemTestUtils_gotLog('REQ option {"filterChangeReminderInterval":43200}'),
    1, 'Match: REQ option {"filterChangeReminderInterval":43200}' );

done_testing;
exit(0);

1;