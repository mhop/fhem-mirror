##############################################
# test basic define
##############################################
package main;
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

NextStep();

sub testStep1 {    
    fhem 'define ZL ComfoAir none';
    return;
}

sub testStep2 {
    is(FhemTestUtils_gotLog("Defined with device none"), 1, "defined");
    is($defs{'ZL'}{Interval} // 0, 0, "no interval");
    FhemTestUtils_resetLogs();
    fhem 'delete ZL';
    fhem 'define ZL ComfoAir none 60';
    return;
}

sub testStep3 {
    is($defs{'ZL'}{Interval} // 0, 60, "interval correct");
    #is(FhemTestUtils_gotLog("ZL: Can't open NoSuchDevice: No such file or directory"), 1, "correct error if no device");
    #is(FhemTestUtils_gotLog("Defined with device NoSuchDevice"), 0, "no defined log if no device");
    FhemTestUtils_resetLogs();
    return;
}


1;
