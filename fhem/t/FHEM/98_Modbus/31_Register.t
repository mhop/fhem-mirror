##############################################
# test master slave end to end
# attr disable
# and set inactive / set active
##############################################
use strict;
use warnings;
use Test::More;
use Time::HiRes     qw(gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils qw(:all);
use Data::Dumper;

InternalTimer(gettimeofday() + 0.1, "testStep1", 0);

sub testStep1 {    
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep1: define Master over MS";

    fhem ('define Master ModbusAttr 5 0');
    InternalTimer(gettimeofday() + 0.1, "testStep2", 0);
}

sub testStep2 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep2: ";
    is(FhemTestUtils_gotLog('registers Master at MS with id 5, MODE master, PROTOCOL RTU'), 1, "Master registered");
    fhem ('define Master2 ModbusAttr 4 0');
    InternalTimer(gettimeofday() + 0.1, "testStep3", 0);
}

sub testStep3 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep3: ";
    is(FhemTestUtils_gotLog('registers Master2 at MS with id 4, MODE master, PROTOCOL RTU'), 1, "Master2 registered");
    fhem ('define Master3 ModbusAttr 4 0 ASCII');
    fhem ('attr Master3 enableSetInactive 1');
    fhem ('attr Master3 verbose 5');
    fhem ('attr Master3 obj-h100-reading test');
    fhem ('attr Master3 obj-h100-showGet 1');
    InternalTimer(gettimeofday() + 0.1, "testStep4", 0);
}

sub testStep4 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep4: ";
    is(FhemTestUtils_gotLog('Master3: SetIODev found no usable physical modbus device'), 1, "No IODev for Master3 (MS already locked as RTU)");
    FhemTestUtils_resetLogs();
    fhem ('attr Master disable 1');
    fhem ('get Master3 test');
    InternalTimer(gettimeofday() + 0.1, "testStep5", 0);
}
sub testStep5 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep5: ";
    is(FhemTestUtils_gotLog('Master3: SetIODev found no usable physical modbus device'), 1, "No IODev for Master3 (MS still locked as RTU)");
    FhemTestUtils_resetLogs();
    fhem ('attr Master2 disable 1');
    fhem ('get Master3 test');
    InternalTimer(gettimeofday() + 0.1, "testStep6", 0);
}
sub testStep6 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep6: ";
    is(FhemTestUtils_gotLog('registers Master3 at MS with id 4, MODE master, PROTOCOL ASCII'), 1, "Now MS is locked as ASCII");
    FhemTestUtils_resetLogs();
    fhem ('define Slave1 ModbusAttr 10 slave ASCII');
    InternalTimer(gettimeofday() + 0.1, "testStep7", 0);
}
sub testStep7 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep7: ";
    is(FhemTestUtils_gotLog('Slave1: SetIODev found no usable physical modbus device'), 1, "no io device for slave");
    fhem ('delete Slave1');
    fhem ('attr Master3 disable 1');
    fhem ('define Slave1 ModbusAttr 10 slave ASCII');
    InternalTimer(gettimeofday() + 0.1, "testStep8", 0);
}
sub testStep8 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep8: ";
    is(FhemTestUtils_gotLog('registers Slave1 at MS with id 10, MODE slave, PROTOCOL ASCII'), 1, "now slave can use MS as IO Device");
    InternalTimer(gettimeofday() + 0.1, "testStep9", 0);
}
sub testStep9 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep9: ";
    InternalTimer(gettimeofday() + 0.1, "testStep10", 0);
}
sub testStep10 {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStep10: ";
    InternalTimer(gettimeofday() + 0.1, "testStepEnd", 0);
}

sub testStepX {
    Log3 undef, 1, "----------------";    
    Log3 undef, 1, "TestStepX: ";
    #fhem ('get ');
    InternalTimer(gettimeofday() + 0.1, "testStepEnd", 0);
}


sub testStepEnd {
    done_testing;
    exit(0);
}


1;
