##############################################
# test ignoreExpr in HTTPMOD
# perl /opt/fhem/fhem.pl -t /opt/fhem/t/...
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

NextStep();

sub testStep1 {
    LogStep "Read and process data";
    fhem 'set H1 reread';
}

sub testStep2 {
    LogStep "check initial results";
    
    is(FhemTestUtils_gotEvent(qr/H1:Test1:\s3/xms), 1, "match1 without ignoreExpr");
    is(FhemTestUtils_gotEvent(qr/H1:Test2-2:\s4/xms), 1, "match2 without ignoreExpr");
    CheckAndReset();
    
    fhem 'attr H1 reading01IgnoreExpr $val > 1';
    fhem 'set H1 reread';
}

sub testStep4{
    LogStep "check results with ignore > 1";
    
    is(FhemTestUtils_gotEvent(qr/H1:Test1:\s3/xms), 0, "match1 with ignore >1");   # should be ignored
    CheckAndReset();
    
    fhem 'attr H1 reading01IgnoreExpr $val > 9';
    fhem 'set H1 reread';
}

sub testStep6{
    LogStep "check results with ignore > 9";
    
    is(FhemTestUtils_gotEvent(qr/H1:Test1:\s3/xms), 1, "match1 with ignore >9");
    CheckAndReset();
    
    fhem 'attr H1 reading01IgnoreExpr $val <= $oldVal';
    fhem 'set H1 reread';
}

sub testStep10 { 
    LogStep "check results with ignore <= oldVal";
    
    is(FhemTestUtils_gotEvent(qr/H1:Test1:\s3/xms), 0, "match1 with ignore <=old");
    CheckAndReset();
}


1;
