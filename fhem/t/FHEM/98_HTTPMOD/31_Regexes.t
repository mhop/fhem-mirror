##############################################
# test regexes
#
# readingXRegex
# preProcess
# reAuth
# idRegex
# replacementRegex
#
# reading|get|set regOpt        (gceor are not compiled in, xmsi need to be in compilation)
#
# decode and compile
##############################################
use strict;
use warnings;
use Test::More;

my $hash = $defs{'H2'};
my $modVersion = $hash->{ModuleVersion};
$modVersion =~ /^([0-9]+)\./;
my $major = $1;

if ($major && $major >= 4) {
    plan tests => 13;
} else {
    plan skip_all => "This test only works for HTTPMOD version 4 or later, installed is $modVersion";
}


fhem('set H1 reread');
is(FhemTestUtils_gotEvent(qr/H1:TestReading1:\sRainbowChase/xms), 1, "match simple case with regex compilation");
is(FhemTestUtils_gotEvent(qr/H1:TestReading2:\sRainbowChase/xms), 1, "match with options xms with regex compilation");
is(FhemTestUtils_gotLog(qr/H1:.*TestReading3 did not match/), 1, "No match with wrong options with regex compilation");
is(FhemTestUtils_gotEvent(qr/H1:TestReading4:\s3\s4/xms), 1, "match with options gxms with regex compilation");


fhem('set H2 reread');
is(FhemTestUtils_gotEvent(qr/H2:TestReading1:\sRainbowChase/xms), 1, "match simple case without regex compilation");
is(FhemTestUtils_gotEvent(qr/H2:TestReading2:\sRainbowChase/xms), 1, "match with options xms without regex compilation");
is(FhemTestUtils_gotLog(qr/H2:.*TestReading3 did not match/), 1, "No match with wrong options without regex compilation");
is(FhemTestUtils_gotEvent(qr/H2:TestReading4:\s3\s4/xms), 1, "match with options gxms without regex compilation");

fhem ('attr H2 reading20Name TestReadingBad');
fhem ('attr H2 reading20Regex \"SimpleColor\",\"[^\"]+)\"');
is(FhemTestUtils_gotLog(qr/H2: reading20Regex Regex: Bad regexp/), 2, "validation of a bad regex");

fhem('set H3 reread');
is(FhemTestUtils_gotEvent(qr/H3:TestReading:\s466/xms), 1, "preProcessRegex");

fhem('set H4 reread');

InternalTimer(time()+1, sub() {
    is(FhemTestUtils_gotEvent("H4:LAST_REQUEST: auth01"), 1, "Auth Step 1");
    is(FhemTestUtils_gotEvent("H4:LAST_REQUEST: auth02"), 1, "Auth Step 2");
    is(FhemTestUtils_gotEvent("H4:TestReading: 168"), 1, "Reading after auth");
    done_testing;
    exit(0);
}, 0);


1;
