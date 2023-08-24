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
    #[q(accept '$cron_text'), '1-5 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1..5) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
    #[q(handle '$cron_text'), '0 0 2-8 * &1-5,6', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230114000000 ],
    # [q(handle '$cron_text'), '0 0 * * 4#l', qr(^$), 20230101000000, 20230126000000, 20230223000000, 20230330000000, 20230427000000, 20230525000000, 20230629000000 ],
    [q(handle '$cron_text'), '0 0 * 2 6#-5', qr(^$), 20230201000000, 20480201000000, 20760201000000, 21160201000000, 21440201000000, 21720201000000, 22120201000000 ],
];

foreach my $t (@$test) {
    my ($desc, $cron_text, $err_expected, @series) = @$t;
    my ($cron_obj, $err) = FHEM::Scheduler::Cron->new($cron_text);
    my $ok = 1;
    my $count = 0;
    
    unless ($err) {
        for my $iter (0 .. $#series -1) {
            # next unless ($series[$iter]);
            my ($got, $err) = $cron_obj->next($series[$iter]);
            $count++;
            $ok = 0 if ($err or (not $got) or ($got ne $series[$iter +1]));
            say sprintf('%s   -> expected: %s, got: %s', ($got ne $series[$iter +1])?'not ok':'ok', $series[$iter +1], $got) if $ENV{EXTENDED_DEBUG};
            last if (not $ok);
        }
    }
    $ok &&= (($err // '') =~ /$err_expected/);
    ok($ok, sprintf('%s %s', eval qq{"$desc"} , $err?"(got '$err')":"(# of passes: $count)"));
};

done_testing;
exit(0);
