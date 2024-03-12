##############################################
# test master slave end to end
# also map, min max, ...
##############################################

package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

fhem 'attr global mseclog 1';
NextStep();

sub testStep1 {
    fhem 'attr Master disable 0';
    fhem 'set Master sendRaw 63';   # dec 99
    return 0.1;
}

sub testStep2 {
    is(FhemTestUtils_gotLog('Send 05e301e931'), 1, "saw sending");
    return 0.1;
}


1;
