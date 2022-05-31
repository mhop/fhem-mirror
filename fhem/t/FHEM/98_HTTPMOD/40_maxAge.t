##############################################
# test MaxAge
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
    LogStep "TestStep1: get H1 G1";
    fhem('get H1 G1');
    return 1;
}

sub testStep2 {
    LogStep "check normal readings";
    is(FhemTestUtils_gotEvent("H1:TestReading1: 168"), 1, "Normal Reading 1");
    is(FhemTestUtils_gotEvent("H1:TestReading2-1: tvlights"), 1, "Normal Reading 2");
    CheckAndReset();
    return 1;
}

sub testStep10 {
    LogStep "get H1 G2";
    fhem('setreading H1 tr 789');
    fhem('get H1 G2');
    return 1;
}

sub testStep11 {
    LogStep "check outdated readings";
    is(FhemTestUtils_gotEvent("H1:TestReading1: outdated"), 1, "Outdated Reading 1 with mode text");
    is(FhemTestUtils_gotEvent("H1:TestReading2-1: old - was tvlights"), 1, "Outdated Reading 2 with mode expression");
    is(FhemTestUtils_gotEvent("H1:TestReading2-2: 789"), 1, "Outdated Reading 3 with mode reading");
    is(FhemTestUtils_gotEvent("H1:TestReading2-3: H1"), 1, "Outdated Reading 4 with mode internal");
    is(FhemTestUtils_gotEvent("H1:TestReading2-4:"), 0, "Outdated Reading 5 with mode delete");
    CheckAndReset();
    return 1;
}

1;
