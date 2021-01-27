##############################################
# test RTU slave
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
    LogStep "set values at Slave";
    fhem 'setreading Slave TempWasserEin 12';
    fhem 'setreading Slave Test1 1';
    fhem 'setreading Slave Test2 2.123';
    fhem 'setreading Slave Test3 abcdefg';
    fhem 'setreading Slave Test4 40';
    fhem 'setreading Slave c0 1';
    fhem 'setreading Slave c5 1';
    fhem 'setreading Slave c17 1';
    fhem 'attr Slave verbose 5';

    fhem 'attr Master disable 0';
    fhem 'attr Master verbose 5';
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);   
    return 0.1;
}

sub testStep2 {     
    LogStep "simulate get TempWasserEin";
    #fhem 'attr Slave verbose 4';
    SimRead('ModbusIO1', '0503010000018472');            # get TempWasserEin
    return 0.1;
}


sub testStep3 {     
    is(FhemTestUtils_gotLog('ModbusIO1: Simulate sending to none: 050302000c4981'), 1, "correct reply 0 with temp 12");
    return 0.1;
}


sub testStep4 {     
    LogStep "simulate get TempWasserEin with broken frame 1 (garbage in front";
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('ModbusIO1', '010503010000018472');            
    return 0.1;
}


sub testStep5 {     
    is(FhemTestUtils_gotLog('ModbusIO1: Simulate sending to none: 050302000c4981'), 1, "correct reply 1 with temp 12");
    return 0.1;
}



sub testStep6 {     
    LogStep "simulate get TempWasserEin with broken frame 2 (garbage at end";
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('ModbusIO1', '05030100000184720505');            
    return 0.1;
}


sub testStep7 {     
    is(FhemTestUtils_gotLog('ModbusIO1: Simulate sending to none: 050302000c4981'), 1, "correct reply 2 with temp 12");
    return 0.1;
}



sub testStep8 {     
    LogStep "simulate get TempWasserEin with broken frame 3 (garbage at end";
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    SimRead('ModbusIO1', '0503010000018472FF');            
    return 0.1;
}


sub testStep9 {     
    is(FhemTestUtils_gotLog('ModbusIO1: Simulate sending to none: 050302000c4981'), 1, "correct reply 3 with temp 12");
    return 0.1;
}



sub testStep10 {     
    LogStep "simulate get TempWasserEin with broken frame 4 (garbage at start, skipGarbage";
    FhemTestUtils_resetLogs();
    FhemTestUtils_resetEvents();
    fhem 'attr ModbusIO1 skipGarbage 1';
    SimRead('ModbusIO1', '0708090503010000018472');            
    return 0.1;
}


sub testStep11 {     
    is(FhemTestUtils_gotLog('ModbusIO1: Simulate sending to none: 050302000c4981'), 1, "correct reply 3 with temp 12");
    return 0.1;
}



sub testStep50 {     
    return 0.1;
}

1;
