# perl fhem.pl -t t/FHEM/90_Cron/99_Cronlib_DEBUG.t
use v5.14;

use strict;
use warnings;
use Test::More;
use FHEM::Scheduler::Cron;

$ENV{EXTENDED_DEBUG} = 1;

# syntax of list 
# description of test | cron expr | err expected (regex) | from | next (more next.., ..)

my $test = [
    #[q(Timeseries '$cron_text'), '0 12 3,4,5 2 0,2,3,4', qr(^$), 20230102150000, 20230201120000, 20230202120000, 20230203120000, 20230204120000], 
    #[q(Feb-29 & Sunday '$cron_text'), '0 12 29 2 &7', qr(^$), 20230102150000, 20320229120000, sub {20600229120000}->()], 
    [q(accept '$cron_text'), '1-5 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1..5) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
];

foreach my $t (@$test) {
    my ($desc, $cron_text, $err_expected, @series) = @$t;
    my ($cron_obj, $err) = FHEM::Scheduler::Cron->new($cron_text);
    my $ok = 1;
    my $count = 0;
    
    for my $iter (0 .. $#series -1) {
        # next unless ($series[$iter]);
        my $got = $cron_obj->next($series[$iter]);
        $count++;
        $ok = 0 if ($got ne $series[$iter +1]);
        say sprintf('%s   -> expected: %s, got: %s', ($got ne $series[$iter +1])?'not ok':'ok', $series[$iter +1], $got) if $ENV{EXTENDED_DEBUG};
    }
    $ok &&= ($err // '' =~ /$err_expected/);
    ok($ok, sprintf('%s %s', eval qq{"$desc"} , $err?"(got '$err')":"(# of passes: $count)"));
};

done_testing;
exit(0);
