##############################################
# test ignoreExpr in HTTPMOD
# perl /opt/fhem/fhem.pl -t /opt/fhem/t/...
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

NextStep();

sub testStep1 {     # preparation of slave content, enable devices
    is(FhemTestUtils_gotLog('attribute'), 0, "no unknown attributes");     # logs during init are not collected.
    LogStep "enable Master and set value at Slave";
    fhem ('attr Master disable 0');
    fhem ('setreading Slave TempWasserEin 12');
    fhem ('setreading Slave TempWasserEin 1');
    fhem ('setreading Slave Test1 3');
    fhem ('setreading Slave Test2 2.123');
    fhem ('setreading Slave Test3 abcdefg');
    fhem ('setreading Slave Test4 40');
    readingsSingleUpdate($defs{'Slave'}, 'Test5', pack('H*', 'e4f6fc'), 0);   
    return 0.3;
}

sub testStep10 {
    LogStep "Read and process data";
    fhem 'set Master reread';
    return 0.2;
}

sub testStep12 {
    LogStep "check initial results";
    
    is(FhemTestUtils_gotEvent(qr/Master:Test1:\s3/xms), 1, "match Test1 without ignoreExpr");
    is(FhemTestUtils_gotEvent(qr/Master:Test2:\s2.12/xms), 1, "match Test2 without ignoreExpr");
    CheckAndReset();
    
    fhem 'attr Master obj-h100-ignoreExpr $val < 2';
    #fhem 'attr Master verbose 5';
    #fhem 'attr Slave verbose 5';
    #fhem 'set Slave reconnect';
    fhem 'set Master reread';
    return 0.2;
}

sub testStep14{
    LogStep "check results with ignore < 2";
    
    is(FhemTestUtils_gotEvent(qr/Master:Test1:\s3/xms), 1, "match with ignore < 2");   # should succeed
    CheckAndReset();
    
    fhem 'attr Master obj-h100-ignoreExpr $val > 2';
    #fhem 'attr Master verbose 5';
    #fhem 'attr Slave verbose 5';
    #fhem 'set Slave reconnect';

    fhem 'set Master reread';
    return 0.2;
}

sub testStep16{
    LogStep "check results with ignore > 2";
    
    is(FhemTestUtils_gotEvent(qr/Master:Test1:\s3/xms), 0, "no match with ignore > 2");  # now value should be ignored
    CheckAndReset();
    
    fhem 'attr Master obj-h100-ignoreExpr $val > ReadingsVal("Master","Test1",0)';
    fhem 'setreading Slave Test1 4';      # now increase value
    #fhem 'attr Master verbose 5';
    #fhem 'attr Slave verbose 5';
    #fhem 'set Slave reconnect';
    fhem 'set Master reread';
    return 0.2;
}

sub testStep20 { 
    LogStep "check results with ignore > oldVal";
    
    is(FhemTestUtils_gotEvent(qr/Master:Test1:\s4/xms), 0, "no match Master with ignore > old");   # should be ignored now
    CheckAndReset();
    fhem 'attr Master verbose 3';
    fhem 'attr Master obj-h100-ignoreExpr $val < ReadingsVal("Master","Test1",0)';
    fhem 'set Master reread';
    return 0.2;
}

sub testStep22 { 
    LogStep "check results with ignore < oldVal";
    is(FhemTestUtils_gotEvent(qr/Master:Test1:\s4/xms), 1, "match Master with ignore < old");    # now it should not be ignored (4 > 3)
    CheckAndReset();
}

1;
