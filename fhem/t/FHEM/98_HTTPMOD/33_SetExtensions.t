##############################################
# test set extensions
##############################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);

#use Data::Dumper;

my $hash = $defs{'H1'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 7;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

NextStep();


sub testStep10 {    
    fhem 'set H1 toggle';
    return 0.1;
}

sub testStep11 {    # check result
    #is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Combined retrieve integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotLog('HandleSendQueue sends set01.*state=on'), 1,'saw set on in log');
    CheckAndReset();
    return 0.1;
}


sub testStep20 {    
    fhem 'set H1 off-for-timer 0.5';
    return 0.6;
}

sub testStep21 {    
    #is(FhemTestUtils_gotEvent(qr/Master:Test1: 6/), 1, "Combined retrieve integer value with expressions on both sides from local slave");
    is(FhemTestUtils_gotLog('HandleSendQueue sends set02.*state=off'), 1,'saw set off in log');
    is(FhemTestUtils_gotLog('HandleSendQueue sends set01.*state=on'), 1,'saw set on in log');

    my $t1 = FhemTestUtils_getLogTime('HandleSendQueue sends set02.*state=off');      
    my $t2 = FhemTestUtils_getLogTime('HandleSendQueue sends set01.*state=on');
    my $d  = $t2 - $t1;

    ok($d >= 0.4, 'time big enough');
    ok($d < 0.6, 'time not too big');
    CheckAndReset();
    return;
}

1;
