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

sub testStep1 {
    SimRead('ZL', '07f000d209503e4e55550f28282895070f');
    SimRead('ZL', '07f3');
    return;
}

sub testStep2 {
    is(FhemTestUtils_gotEvent(qr/ZL:Temp_Komfort:\s20/xms), 1, "Parse TempKomfort with expression");
    CheckAndReset();
    return;
}


sub testStep3 {
    SimRead('ZL', '07f000ce0e0f23320f23322d000300464600000d070f');
    SimRead('ZL', '07f3');
    return;
}

sub testStep4 {
    is(FhemTestUtils_gotEvent(qr/ZL:Stufe:\smittel/xms), 1, "Parse TempKomfort with expression");
    CheckAndReset();
    return;
}


sub testStep10 {
    fhem 'attr ZL verbose 5';
    # start 07f0, cmd 00de, len 14, data, chk af, end 070f
    #SimRead('ZL', '07f000de14004e0f003e8900018e05590000002e31128000010daf070f');
    SimRead('ZL', '07f000de144e0f003e8900018e05590000002e31128000010daf070f');
    return;
}

sub testStep11{
    #is(FhemTestUtils_gotEvent(qr/ZL:Stufe:\smittel/xms), 1, "Parse TempKomfort with expression");
    return;
}



1;
