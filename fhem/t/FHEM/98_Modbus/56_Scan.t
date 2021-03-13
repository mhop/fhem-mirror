##############################################
# test master slave end to end
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

sub testStep1 {     # preparation of slave content, enable devices
    is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    LogStep "enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave Test1 1');          # h100  (*4 -> 4)
    fhem ('setreading Slave Test2 2.123');      # h101
    fhem ('setreading Slave Test3 abcdefg');    # h103
    fhem ('setreading Slave Test4 40');         # h120
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);     # h130

    fhem ('setreading Slave c0 1');
    fhem ('setreading Slave c5 1');
    fhem ('setreading Slave c17 1');
    return 0.1;
}

sub testStep2 {
    LogStep "Start Scan h";
    fhem ('attr Master verbose 3');
    fhem ('attr Slave verbose 3');
    fhem ('attr Master scanDelay 0.1');
    fhem ('set Master scanModbusObjects h100-105');
    return 1;
}

sub testStep3 {
    is(FhemTestUtils_gotEvent('scan-h00100: .*s>=4'), 1, "got h100 correctly");
    is(FhemTestUtils_gotEvent('scan-h00101: .*hex=4007'), 1, "got h101 correctly");
    is(FhemTestUtils_gotEvent('scan-h00103: .*hex=6162'), 1, "got h103 correctly");
    CheckAndReset();
    return 1;
}

sub testStep5 {
    fhem ('set Master scanModbusObjects h100-105 2');
    return 1;
}

sub testStep6 {
    is(FhemTestUtils_gotEvent('scan-h00100: .*s>=4'), 1, "got h100 len 2 correctly");
    is(FhemTestUtils_gotEvent('scan-h00101: .*f>=2.12'), 1, "got h101 len 2  correctly");
    is(FhemTestUtils_gotEvent('scan-h00103: .*string=abcd'), 1, "got h103 len 2  correctly");
    CheckAndReset();
    return 1;
}

sub testStep7 {
    fhem ('attr Master verbose 4');
    fhem ('attr Slave verbose 5');
    fhem ('attr Master dev-timing-timeout 0.3');
    fhem ('set Master scanModbusId 1-8 h100');
    return 6;
}


sub testStep10 {
    #fhem 'list Master';
    is(FhemTestUtils_gotEvent('scanId-5-Response-h100: .*s>=4'), 1, "got h100 scanid response");
    return 1;
}


1;
