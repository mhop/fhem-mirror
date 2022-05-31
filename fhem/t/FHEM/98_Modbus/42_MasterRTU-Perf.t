##############################################
# test modbus RTU Master
##############################################

package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes             qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils    qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

my $prepTime = 0;
my $parseTime = 0;

NextStep();

sub CheckTimes {
    my $t1 = FhemTestUtils_getLogTime('GetUpdate.*called from ControlSet');      
    if (!$t1) {
        $t1 = FhemTestUtils_getLogTime('ProcessRequestQueue.*sending');      
    }
    my $t2 = FhemTestUtils_getLogTime('Simulate sending to none');      
    Log3 undef, 1, "Test: Time to prepare request: " . sprintf('%.3f seconds', ($t2 - $t1));
    my $t3 = FhemTestUtils_getLogTime('simulate reception of');      
    my $t4 = FhemTestUtils_getLogTime('HandleResponse done');      
    Log3 undef, 1, "Test: Time to parse request: " . sprintf('%.3f seconds', ($t4 - $t3));
    Log3 undef, 1, "Test: Time inbetween: " . sprintf('%.3f seconds', ($t3 - $t2));
    $prepTime  += ($t2 - $t1);
    $parseTime += ($t4 - $t3);
    return;
}

sub testStep1 {
    fhem 'attr MS verbose 5';
    fhem 'attr PWP verbose 5';
    LogStep('start reread');
    FhemTestUtils_resetLogs();
    fhem('set PWP reread');
    return;
}



sub testStep2 {
    LogStep('check send timing an simulate first normal reception');

    SimRead('MS', '05030a');        # first normal response 
    SimRead('MS', '012e11');        
    SimRead('MS', '00012f11');
    SimRead('MS', '0000db');        
    SimRead('MS', 'ffe6');        

    ok(ReadingsVal('PWP', 'Temp_Wasser_Ein', 0) > 25, "Parse TempEin");
    ok(ReadingsVal('PWP', 'Temp_Verdampfer', 0) > 10, "Parse TempVerdampfer");
    CheckTimes();
    CheckAndReset();
    return;
}

sub testStep3 {
    LogStep('check send timing an simulate second normal reception');
    SimRead('MS', '0503');                        # second normal response 
    SimRead('MS', '0200');
    SimRead('MS', 'bac8');
    SimRead('MS', '37');
    ok(ReadingsVal('PWP', 'Temp_Luft', 0) > 10, "Parse TempLuft");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep4 {
    LogStep('check send timing an simulate third normal reception');
    SimRead('MS', '05');                    # third normal response 
    SimRead('MS', '0304');                
    SimRead('MS', '0122');                
    SimRead('MS', '000a');                
    SimRead('MS', '9e02');                
    ok(ReadingsVal('PWP', 'Temp_Soll', 0) > 10, "Parse TempSoll");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep5 {
    LogStep('check send timing an simulate fourth normal reception');
    SimRead('MS', '05');                        # fourth normal response 
    SimRead('MS', '03');
    SimRead('MS', '0200');
    SimRead('MS', '0049');
    SimRead('MS', '84');
    ok(ReadingsVal('PWP', 'Hyst_Mode', '') eq 'mittig', "Parse Hyst_Mode");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep6 {
    LogStep('check send timing an simulate fifth normal reception');
    SimRead('MS', '0503');            # fifth normal response 
    SimRead('MS', '08ff');
    SimRead('MS', 'fd00');
    SimRead('MS', '0000');
    SimRead('MS', '0000');
    SimRead('MS', '00e3');
    SimRead('MS', '2c');
    ok(ReadingsVal('PWP', 'Temp_Luft_Off', 99) < 2, "Parse TempLuftOff");
    CheckTimes();
    CheckAndReset();
    Log3 undef, 1, "Test: so far cumulated total time: " . sprintf('%.3f seconds', $prepTime + $parseTime);
    return;
}


sub testStep10 {
    LogStep('second round reread');
    fhem('set PWP reread');
    return;
}



sub testStep11 {
    LogStep('check send timing an simulate first normal reception');

    SimRead('MS', '05030a');        # first normal response 
    SimRead('MS', '012e11');        
    SimRead('MS', '00012f11');
    SimRead('MS', '0000db');        
    SimRead('MS', 'ffe6');        

    ok(ReadingsVal('PWP', 'Temp_Wasser_Ein', 0) > 25, "Parse TempEin");
    ok(ReadingsVal('PWP', 'Temp_Verdampfer', 0) > 10, "Parse TempVerdampfer");
    CheckTimes();
    CheckAndReset();
    return;
}

sub testStep12 {
    LogStep('check send timing an simulate second normal reception');
    SimRead('MS', '0503');                        # second normal response 
    SimRead('MS', '0200');
    SimRead('MS', 'bac8');
    SimRead('MS', '37');
    ok(ReadingsVal('PWP', 'Temp_Luft', 0) > 10, "Parse TempLuft");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep13 {
    LogStep('check send timing an simulate third normal reception');
    SimRead('MS', '05');                    # third normal response 
    SimRead('MS', '0304');                
    SimRead('MS', '0122');                
    SimRead('MS', '000a');                
    SimRead('MS', '9e02');                
    ok(ReadingsVal('PWP', 'Temp_Soll', 0) > 10, "Parse TempSoll");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep14 {
    LogStep('check send timing an simulate fourth normal reception');
    SimRead('MS', '05');                        # fourth normal response 
    SimRead('MS', '03');
    SimRead('MS', '0200');
    SimRead('MS', '0049');
    SimRead('MS', '84');
    ok(ReadingsVal('PWP', 'Hyst_Mode', '') eq 'mittig', "Parse Hyst_Mode");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep15 {
    LogStep('check send timing an simulate fifth normal reception');
    SimRead('MS', '0503');            # fifth normal response 
    SimRead('MS', '08ff');
    SimRead('MS', 'fd00');
    SimRead('MS', '0000');
    SimRead('MS', '0000');
    SimRead('MS', '00e3');
    SimRead('MS', '2c');
    ok(ReadingsVal('PWP', 'Temp_Luft_Off', 99) < 2, "Parse TempLuftOff");
    CheckTimes();
    CheckAndReset();
    return;
}


sub testStep90 {
    LogStep('done');
    Log3 undef, 1, "Test: cumulated time to prepare requests: " . sprintf('%.3f seconds', $prepTime);
    Log3 undef, 1, "Test: cumulated time to parse requests: " . sprintf('%.3f seconds', $parseTime);
    Log3 undef, 1, "Test: cumulated total time: " . sprintf('%.3f seconds', $prepTime + $parseTime);
    return;
}


1;
