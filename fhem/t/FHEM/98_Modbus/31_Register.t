##############################################
# test attr disable
# and set inactive / set active
##############################################
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw(gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use FHEM::Modbus::TestUtils qw(:all);
use Data::Dumper;

NextStep();


sub testStep1 {    
    fhem ('define Master ModbusAttr 5 0');
    return 0.1;
}

sub testStep2 {
    is(FhemTestUtils_gotLog('registers Master at MS with id 5, MODE master, PROTOCOL RTU'), 1, "Master registered");
    fhem ('define Master2 ModbusAttr 4 0');
    return 0.1;
}

sub testStep3 {
    is(FhemTestUtils_gotLog('registers Master2 at MS with id 4, MODE master, PROTOCOL RTU'), 1, "Master2 registered");
    fhem ('define Master3 ModbusAttr 4 0 ASCII');
    fhem ('attr Master3 enableSetInactive 1');
    fhem ('attr Master3 verbose 5');
    fhem ('attr Master3 obj-h100-reading test');
    fhem ('attr Master3 obj-h100-showGet 1');
    return 0.1;
}

sub testStep4 {
    is(FhemTestUtils_gotLog('Master3: SetIODev found no usable physical modbus device'), 1, "No IODev for Master3 (MS already locked as RTU)");
    FhemTestUtils_resetLogs();
    fhem ('attr Master disable 1');
    fhem ('get Master3 test');
    return 0.1;
}

sub testStep5 {
    is(FhemTestUtils_gotLog('Master3: SetIODev found no usable physical modbus device'), 1, "No IODev for Master3 (MS still locked as RTU)");
    FhemTestUtils_resetLogs();
    fhem ('attr Master2 disable 1');
    fhem ('get Master3 test');
    return 0.1;
}

sub testStep6 {
    is(FhemTestUtils_gotLog('registers Master3 at MS with id 4, MODE master, PROTOCOL ASCII'), 1, "Now MS is locked as ASCII");
    FhemTestUtils_resetLogs();
    fhem ('define Slave1 ModbusAttr 10 slave ASCII');
    return 0.1;
}

sub testStep7 {
    is(FhemTestUtils_gotLog('Slave1: SetIODev found no usable physical modbus device'), 1, "no io device for slave");
    fhem ('delete Slave1');
    fhem ('attr Master3 disable 1');
    fhem ('define Slave1 ModbusAttr 10 slave ASCII');
    return 0.1;
}

1;
