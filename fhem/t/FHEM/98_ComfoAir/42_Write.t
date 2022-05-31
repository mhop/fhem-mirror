##############################################
# test ComfoAir listen and create readings
##############################################

package main;

use strict;
use warnings;
use Test::More;
use Time::HiRes             qw( gettimeofday tv_interval);  # return time as float, not just full seconds
use FHEM::HTTPMOD::Utils    qw(:all);
use FHEM::Modbus::TestUtils qw(:all);

NextStep;      


sub testStep5 {
    fhem 'set ZL Stufe niedrig';
    return 0.1;
}

sub testStep6 {
    is(FhemTestUtils_gotLog('Simulate sending to none: 07f00099010249070f'), 1, "got sending correct data for Stufe");
    CheckAndReset();
    return 0.1;
}


sub testStep7 {
    fhem 'set ZL Temp_Komfort 21';
    return 0.1;
}

sub testStep8 {
    is(FhemTestUtils_gotLog('Simulate sending to none: 07f000d30152d3070f'), 1, "got sending correct data for Temp_Comfort");
    CheckAndReset();
return;
}


sub testStep10 {
    fhem 'set ZL Temp_Komfort 1';
    return 0.1;
}

sub testStep11 {
    is(FhemTestUtils_gotLog('Set Value 1 is smaller than Min'), 1, "got error from min check");
    CheckAndReset();
    return;
}

sub testStep12 {
    fhem 'set ZL Temp_Komfort 50';
    return 0.1;
}

sub testStep13 {
    is(FhemTestUtils_gotLog('Set Value 50 is bigger than Max'), 1, "got error from min check");
    CheckAndReset();
    return;
}


1;
