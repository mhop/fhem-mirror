##############################################
# test attr errLogLvl
##############################################
package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

fhem 'attr global mseclog 1';
InternalTimer(gettimeofday()+5, "testStepLast", 0);            # last resort
NextStep();

sub testStep1 {
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    LogStep "request without further settings but timeout 0";
    fhem ('set H1 reread');
    return;
}

sub testStep2 {
    # loginform used fot FhemTestUtils inserts a space between the level and :
    is(FhemTestUtils_gotLog('3 : H1: Read callback: Error'), 1, "standard log level");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    LogStep "set level go 4";
    fhem ('attr H1 errLogLevel 4');
    fhem ('set H1 reread');
    return;
}

sub testStep3 {
    is(FhemTestUtils_gotLog('4 : H1: Read callback: Error: t/FHEM/98_HTTPMOD/NoSuchFile'), 1, "log level 4");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    LogStep "set level regex to timeout only";
    fhem ('attr H1 errLogLevel 4');
    fhem ('attr H1 errLogLevelRegex timeout');
    fhem ('set H1 reread');
    return;
}

sub testStep4 {
    is(FhemTestUtils_gotLog('3 : H1: Read callback: Error: t/FHEM/98_HTTPMOD/NoSuchFile'), 1, "standard log level because regex doesnt match");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    LogStep "set level regex to no such file";
    fhem ('attr H1 errLogLevel 4');
    fhem ('attr H1 errLogLevelRegex No such file');
    fhem ('set H1 reread');
    return;
}

sub testStep5 {
    is(FhemTestUtils_gotLog('4 : H1: Read callback: Error: t/FHEM/98_HTTPMOD/NoSuchFile'), 1, "log level 4 with match");
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    return;
}

1;