######################################################
# test Auth Token handling and PKCE support
# use the following command to run this test:
# perl /opt/fhem/fhem.pl -t /opt/fhem/t/13_Tokens.t
######################################################
use strict;
use warnings;
use Test::More;
use FHEM::Modbus::TestUtils qw(:all);
use Data::Dumper;

my $hash = $defs{'H1'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    #plan tests => 5;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}

NextStep();

sub testStep1 {
    LogStep "start with step 1";
    CheckAndReset();
    fhem 'set H1 reread';
    #print Dumper($defs{H1});
    return 0;
}

sub testStep2 {
    LogStep "check results";
    is($hash->{TOKENS}{ACCESS_TOKEN}, "2YotnFZFEjr1zCsicMWpAA", "got token");
    is(FhemTestUtils_gotLog('GetTokens scheduled token refresh after 90 percent at'), 1, "refresh timer scheduled on token response");
    isnt(ReadingsVal('H1', '.TOKEN_REFRESH_AT', ''), '', "refresh timer timestamp stored");
    CheckAndReset();
    return 0;
}


sub testStep10 {
    fhem 'set H1 authorize';
    return 0.1;
}

sub testStep12 {
    is(FhemTestUtils_gotLog('created new code verifier'), 1, "new code challenge created");
    is(FhemTestUtils_gotLog('MyClientId'), 3, "client id replaced");
    CheckAndReset();
    return 0;
}

sub testStep15 {
    fhem 'get H1 EnergyState';
    return 0.1;
}

sub testStep16 {
    # check token replacements
    is(FhemTestUtils_gotLog('Replacing %%ACCESS_TOKEN%% in header'), 1, "access token replacement");
    CheckAndReset();
    return 0;
}

sub testStep17 {
    RemoveInternalTimer("tokenrefresh:H1");
    fhem 'deletereading H1 .TOKEN_REFRESH_AT';
    CheckAndReset();
    HTTPMOD::RestoreTokenRefreshTimer($hash, 'test restore');
    return 0;
}

sub testStep18 {
    is(FhemTestUtils_gotLog('RestoreTokenRefreshTimer derived refresh time from \.REFRESH_TOKEN_EXPIRATION'), 1, "refresh timer can be restored from expiration");
    is(FhemTestUtils_gotLog('RestoreTokenRefreshTimer scheduled token refresh at'), 1, "refresh timer restoration schedules timer");
    isnt(ReadingsVal('H1', '.TOKEN_REFRESH_AT', ''), '', "refresh timer timestamp restored");
    CheckAndReset();
    return 0;
}

sub testStep20 {
    fhem 'set H1 REFRESH_TOKEN 12345';
    return 0;
}

sub testStep21 {
    LogStep "check set results";
    is($hash->{TOKENS}{REFRESH_TOKEN}, "12345", "got refresh token");
    CheckAndReset();
    return 0;
}


sub testStep90 {
    CheckAndReset();
    return 0;
}

1;
