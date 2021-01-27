##############################################
# test relay
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
    fhem ('attr RM disable 0');
    fhem ('attr Relay disable 0');
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave Test1 1');
    fhem ('setreading Slave Test2 2.123');
    fhem ('setreading Slave Test3 abcdefg');
    fhem ('setreading Slave Test4 40');
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);   

    fhem ('setreading Slave c0 1');
    fhem ('setreading Slave c5 1');
    fhem ('setreading Slave c17 1');
    return 0.1;
}

sub testStep2 {     # get holding registers 
    LogStep "get TempWasserEin";
    fhem ('attr Master verbose 3');
    fhem ('attr Slave verbose 3');
    fhem ('attr Relay verbose 3');
    fhem ('attr RM verbose 3');
    fhem ('get Master TempWasserEin');
    fhem ('get Master Test1');
    fhem ('get Master Test2');
    fhem ('get Master Test3');
    fhem ('get Master Test4');
    fhem ('get Master Test5');
    return 1;
}

sub testStep3 {     # check results
    LogStep "check result";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "Retrieve integer value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Retrieve another integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 2.12/), 1, "Retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test3: abcdefg/), 1, "Retrieve ascii value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test4: 40/), 0, "ignoreExpr prohibits Test4 set to 40");
    is(FhemTestUtils_gotEvent(qr/Master:Test5: äöü/), 1, "encode worked for Test5");
    return;
}

sub testStep4 {     # set holding register without allowance at salve
    LogStep "set TempWasserAus at Slave";
    fhem ('set Master TempWasserAus 20');
    fhem ('attr Master verbose 4');
    return 0.2;
}

sub testStep5 {     # check that write was forbidden
    LogStep "Check error response";
    is(FhemTestUtils_gotLog('Master: HandleResponse got response with error code 86 / 01, illegal function'), 1, "disallow write by default");
    fhem ('attr Master verbose 3');
    return;
}

sub testStep6 {     # allow write at slave and try again to write
    LogStep "allow write and try again";
    fhem ('attr Slave obj-h258-allowWrite 1');
    fhem ('set Master TempWasserAus 20');
    return 0.1;
}

sub testStep7 {     # check that write holding register did work
    LogStep "check result";
    is(FhemTestUtils_gotEvent(qr/D1:TempWasserAus:\s20/xms), 1, "Write value to local slave");
    return 0.1;
}

sub testStep8 {     # check input validation at master and write
    LogStep "set with map and min/max";
    fhem ('set Master o1 one');
    is(FhemTestUtils_gotLog('set Master o1 one : set value one did not match defined map'), 1, "map error message in log");
    fhem ('set Master o2 0');
    is(FhemTestUtils_gotLog('set Master o2 0 : value 0 is not within defined min/max range'), 1, "min error message in log");
    fhem ('set Master o2 4');
    is(FhemTestUtils_gotLog('set Master o2 4 : value 4 is not within defined min/max range'), 1, "max error message in log");

    fhem ('attr Master verbose 4');
    fhem ('set Master o2 2');
    fhem ('set Master o1 on');
    return 0.2;
}


sub testStep9 {     # check write data
    LogStep "check log for map and set o2 2";
    is(FhemTestUtils_gotLog('0506000a0001698c'), 1, "set o1 on message in log");
    is(FhemTestUtils_gotLog('0506000b0002784d'), 1, "set O2 2 message in log");
    fhem ('attr Master verbose 3');
    return 0.2;
}


sub testStep10 {    # check combined read of holding registers and coils
    LogStep "getUpdate with combine";
    FhemTestUtils_resetEvents();
    fhem ('set Master reread');
    return 0.2;
}

sub testStep11 {    # check results coming from slave and write coils to slave
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Combined retrieve integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test2: 2.12/), 1, "Combined retrieve float value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:Test3: abcdefg/), 1, "Combined Retrieve ascii value from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c0: 1/), 1, "Combined Retrieve coil bit 0 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c1: 0/), 1, "Combined Retrieve coil bit 1 from local slave");
    is(FhemTestUtils_gotEvent(qr/Master:c17: 1/), 1, "Combined Retrieve coil bit 17 from local slave");

    fhem ('attr Slave obj-c402-allowWrite 1');
    fhem ('attr Master verbose 5');
    #fhem ('attr Slave verbose 5');  # todo: remove
    fhem ('set Master c2 1');
    return 0.2;
}

sub testStep12 {
    LogStep "check coil comm";
    
    is(FhemTestUtils_gotLog('sending 05050192ff002daf'), 1, "set c2 1 sending message in log");
    is(FhemTestUtils_gotEvent(qr/Master:c2: 1/), 1, "fc5 response for coil shows 1 from local slave");

    Log3 undef, 1, "TestStep12: try to write with fc16";
    fhem ('attr Master verbose 3');
    fhem ('attr Slave verbose 3');
    fhem ('attr Master dev-h-write 16');
    fhem ('set Master TempWasserAus 29');
    return 0.2;
}

sub testStep13 {
    LogStep "check write result of fc16";
    is(FhemTestUtils_gotEvent(qr/D1:TempWasserAus:\s29/xms), 1, "Write value with fc16 to local slave");
    return 0.1;
}

sub testStep14 {
    LogStep "closeAfterResponse";
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master closeAfterResponse 1');
    fhem ('attr Master verbose 4');
    fhem ('set Master reread');
    return 0.2;
}

sub testStep15 {
    is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Retrieve Test1");
    is(FhemTestUtils_gotEvent(qr/Master:Test4: 40/), 0, "Retrieve Test4");   
    is(FhemTestUtils_gotLog('HandleResponse will close because closeAfterResponse is set and queue is empty'), 1, "closed");
    return 0.1;
}

sub testStep16 {
    LogStep "try get while closed";
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('get Master TempWasserEin');
    fhem ('attr Master queueDelay 0.3');
    return 0.1;
}

sub testStep17 {
    LogStep "check get result while connection closed";
    is(FhemTestUtils_gotLog('device opened'), 1, "device opened");
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 0, "No retrieve from local slave yet");
    return 0.3;
}

sub testStep18 {
    LogStep "check get result after another delay";
    is(FhemTestUtils_gotEvent(qr/Master:TempWasserEin:\s12/xms), 1, "retrieve from local slave after open and QueueDelay");
    is(FhemTestUtils_gotLog('close because closeAfterResponse'), 1, "device closed again");
    return 0.1;
}


sub testStep19 {
    LogStep "now that the connection is closed again, try another prioritized get";
    FhemTestUtils_resetEvents();
    FhemTestUtils_resetLogs();
    fhem ('attr Master nonPrioritizedGet 0');
    fhem ('attr Master dev-timing-timeout 0.5');
    fhem ('attr Master verbose 5');
    fhem ('attr Slave verbose 5');
    fhem ('attr Relay verbose 5');
    fhem ('get Master TempWasserEin');
    return 0.1;
}

sub testStep20 {
    LogStep "check result after prio get";
    is(FhemTestUtils_gotLog('device opened'), 1, "device opened");
    is(FhemTestUtils_gotLog('Master: Timeout in Readanswer'), 1, "readanswer called but slave cannot answer while sitting in readanswer");
    return 0.1;
}

sub testStep21 {
    LogStep "check result after prio get";
    is(FhemTestUtils_gotLog('Master: read.* buffer: 050302000c4981'), 1, "answer arrives after readanswer timeout");
    return;
}


1;
