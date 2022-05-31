##############################################
# test parsing
##############################################

use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

fhem 'attr global mseclog 1';
NextStep();

sub testStep1 {
    CheckAndReset();
    fhem 'set PHC JRM22o1 senken';
    return 0.1;
}

sub testStep2 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0x56,0x26,0x03,0x58,0x02"), 1, "got XMLRPC Log");
}


sub testStep10 {
    CheckAndReset();
    fhem 'set PHC JRM22o1 senken prio=2 set=1 time=50';
    return 0.1;
}

sub testStep11 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0x56,0x26,0x42,0x32,0x00"), 1, "got XMLRPC Log");
}


sub testStep20 {
    CheckAndReset();
    fhem 'set PHC Rollade_AZ_Teich senken prio=2 set=1 time=50';
    return 0.1;
}

sub testStep21 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0x56,0x26,0x42,0x32,0x00"), 1, "got XMLRPC Log");
}


sub testStep30 {
    CheckAndReset();
    #fhem 'attr PHC HTTPMOD PHCService';
    fhem 'set PHC Wohnen_Deckenleuchte_am_Kamin Dunkler Dimmen time=10';
    return 0.1;
}

sub testStep31 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0xA5,0x09,0x0F,0x00"), 1, "got XMLRPC Log");
}


sub testStep50 {
    CheckAndReset();
    fhem 'set PHC Arbeiten-Lampenschiene An_mit_Timer time=5';
    return 0.1;
}

sub testStep51 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0x43,0x4A,0x05,0x00"), 1, "got XMLRPC Log");
}


sub testStep60 {
    CheckAndReset();
    #fhem 'attr PHC HTTPMOD PHCService';
    fhem 'set PHC Arbeiten-Lampenschiene An mit Timer time=5';
    return 0.1;
}

sub testStep61 {
    is(FhemTestUtils_gotLog("XMLRPC called with service.stm.sendTelegram and 0x00,0x43,0x4A,0x05,0x00"), 1, "got XMLRPC Log");
}


sub testStep90 {
    CheckAndReset();
    fhem 'set PHC ?';
    return 0.1;
}


1;
