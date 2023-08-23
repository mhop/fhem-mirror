# perl fhem.pl -t t/FHEM/90_Cron/10_Cronlib.t
use v5.14;

use strict;
use warnings;
use Test::More;
use FHEM::Scheduler::Cron;

$ENV{EXTENDED_DEBUG} = 0;

# syntax of list 
# description of test | cron expr | err expected (regex) | from | next (more next.., ..)

my $test = [
    ['must throw an error if no cron text given', '', qr(no cron expression), 20230101000000 ],
    ['must throw an error if cron expression exceeds 255 chars', q(0) x 256, qr(cron expression exceeds limit), 20230101000000 ],
    [q(accept '$cron_text'), '* * * * *', qr(^$), 20230101000000, 20230101000100 ],
    # [q(precedence mday '$cron_text'), '* * 1 * *', 0, 0, qr(^$)],
    # [q(precedence wday '$cron_text'), '* * * * 2', 0, 0, qr(^$)],
    # [q(mday OR wday logic '$cron_text'), '* * 1 * 2', 0, 0, qr(^$)],
    # [q(mday AND wday logic '$cron_text'), '5/5 10 * * *', 20230101105500, 20230102100500, 20230102101000, 20230102101500, qr(^$)],
    # [q(RULE4 logic '$cron_text'), '* * * * 1,&2', 0, 0, qr(^$)],
    # [q(validate date '$cron_text'), '* * 30 2 *', 0, 0, qr(^$)],
    
    # positive tests for minute
    [q(handle '$cron_text'), '1 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
    [q(handle '$cron_text'), '1-5 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1..5) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
    [q(handle '$cron_text'), '1-5/1 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1..5) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
    [q(handle '$cron_text'), '1-5/2 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0..23) {for my $m (1,3,5) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
#     [q(accept '$cron_text'), '*/1 * * * *', 0, 0, qr(^$)],
#     # positive tests for minute / value range
#     [q(accept '$cron_text'), '0 * * * *', 0, join (',', ((20200101120000 .. 20200101120059 ), (20200101120100 .. 20200101120159 ))), qr(^$)],
#     [q(accept '$cron_text'), '00 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '01 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1-59 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '01-059 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1-59/1 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '01-059/01 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1-59/59 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '01-059/059 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '10~20 * * * *', 0, 0, qr(^$)],
#     # negative tests for minute / syntax
#     [q(must throw an error '$cron_text'), 'a * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '*,a * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '1,a * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '*-5 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '5-1 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '60 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '0-60 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '0-59/60 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     [q(must throw an error '$cron_text'), '20~10 * * * *', 0, 0, qr(^syntax error in minute item:)],
#     # negative tests for minute / value range

    # time series
    [q(Timeseries '$cron_text'), '0 12 3,4,5 2 0,2,3,4', qr(^$), 20230102150000, 20230201120000, 20230202120000, 20230203120000, 20230204120000], 
    [q(Feb-29 & Sunday '$cron_text'), '0 12 29 2 &7', qr(^$), 20230102150000, 20320229120000], 
];

# print join ",", (20200101120000 .. 20200101120010 ), (20200101120100 .. 20200101120110 );
# print "\n";

my $cron_lib_loadable = eval{use FHEM::Scheduler::Cron;1;};
ok($cron_lib_loadable, "FHEM::Scheduler::Cron loaded");

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
