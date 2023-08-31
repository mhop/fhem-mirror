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

     # positive tests for minute
     [q(accept '$cron_text'), '0 * * * *', qr(^$), join (',', ((20230101120000 .. 20230101120059 ), (20230101120100 .. 20230101120159 )))],
     [q(accept '$cron_text'), '00 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '1 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '01 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '1-59 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0) {for my $m (1..59) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '01-059 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '1-59/1 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0) {for my $m (1..59) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '1-59/30 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0) {for my $m (1,31) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '01-059/01 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '1-59/59 * * * *', qr(^$), sub {my @r = (20230101000000); for my $h (0) {for my $m (1) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '01-059/059 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '10~20 * * * *', qr(^$), 0],
     [q(accept '$cron_text'), '10~20,30~40 * * * *', qr(^$), 0],
     # negative tests for minute
     [q(reject '$cron_text'), 'a * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '*,a * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '1,a * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '*-5 * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '5-1 * * * *', qr(^syntax error in minute item:), 0], 
     [q(reject '$cron_text'), '60 * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '0-60 * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '0-59/60 * * * *', qr(^syntax error in minute item:), 0],
     [q(reject '$cron_text'), '20~10 * * * *', qr(^syntax error in minute item:), 0],
     # positive test for hour
     [q(accept '$cron_text'), '0 0 * * *', qr(^$), 20230101000000, 20230102000000, 20230103000000],
     [q(accept '$cron_text'), '0 00 * * *', qr(^$), 0],
     [q(accept '$cron_text'), '0 1 * * *', qr(^$), 0],
     [q(accept '$cron_text'), '0 01 * * *', qr(^$), 0],
     [q(accept '$cron_text'), '0 1-23 * * *', qr(^$), sub {my @r = (20230101000000); for my $h (1..23) {for my $m (0) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '0 01-023 * * *', qr(^$), sub {my @r = (20230101000000); for my $h (1..23) {for my $m (0) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '0 1-23/1 * * *', qr(^$), sub {my @r = (20230101000000); for my $h (1..23) {for my $m (0) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '0 01-023/01 * * *', qr(^$), sub {my @r = (20230101000000); for my $h (1..23) {for my $m (0) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '0 1-23/12 * * *', qr(^$), sub {my @r = (20230101000000); for my $h (1,13) {for my $m (0) {push @r, sprintf('20230101%02d%02d00', $h, $m)}}; @r}->()],
     [q(accept '$cron_text'), '0 1-23/23 * * *', qr(^$), 20230101010000, 20230102010000, 20230103010000],
     [q(accept '$cron_text'), '0 1~10 * * *', qr(^$), 0],
     [q(accept '$cron_text'), '0 1~10,11~20 * * *', qr(^$), 0],

    # positive tests for weekday
    [q(handle '$cron_text'), '0 0 * * *', qr(^$), sub {my @r = (20230101000000); for my $d (2..31) {for my $h (0) {for my $m (0) {push @r, sprintf('202301%02d%02d%02d00', $d, $h, $m)}}}; @r}->()],
    [q(handle '$cron_text'), '0 0 * * 1', qr(^$), 20230101000000, 20230102000000, 20230109000000, 20230116000000 ],
    [q(handle '$cron_text'), '0 0 * * 1-5', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000 ],
    [q(handle '$cron_text'), '0 0 * * 1-5/1', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000 ],
    [q(handle '$cron_text'), '0 0 * * 1-5/2', qr(^$), 20230101000000, 20230102000000, 20230104000000, 20230106000000 ],
    [q(handle '$cron_text'), '0 0 * * 1-5,6', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000 ],
    [q(handle '$cron_text'), '0 0 8 * 1-5,6', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230108000000 ],
    [q(handle '$cron_text'), '0 0 8 * Mon-Fri,Sat', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230108000000 ],
    [q(handle '$cron_text'), '0 0 8 * mon-fri,sat', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230108000000 ],
    [q(handle '$cron_text'), '0 0 8 * MON-FRI,SAT', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230108000000 ],
    [q(handle '$cron_text'), '0 0 2-8 * &1-5,6', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230114000000 ],
    [q(handle '$cron_text'), '0 0 2-8 * &Mon-Fri,Sat', qr(^$), 20230101000000, 20230102000000, 20230103000000, 20230104000000, 20230105000000, 20230106000000, 20230107000000, 20230114000000 ],
    # positional
    [q(handle '$cron_text'), '0 0 * 2 0#F', qr(^$), 20230201000000, 20230205000000, 20240204000000, 20250202000000, 20260201000000, 20270207000000, 20280206000000 ],
    [q(handle '$cron_text'), '0 0 * 2 Sun#F', qr(^$), 20230201000000, 20230205000000, 20240204000000, 20250202000000, 20260201000000, 20270207000000, 20280206000000 ],
    [q(handle '$cron_text'), '0 0 * * 4#L', qr(^$), 20230101000000, 20230126000000, 20230223000000, 20230330000000, 20230427000000, 20230525000000, 20230629000000 ],
    [q(handle '$cron_text'), '0 0 * * Thu#L', qr(^$), 20230101000000, 20230126000000, 20230223000000, 20230330000000, 20230427000000, 20230525000000, 20230629000000 ],
    [q(handle '$cron_text'), '0 0 * 2 6#5', qr(^$), 20230201000000, 20480229000000, 20760229000000, 21160229000000, 21440229000000, 21720229000000, 22120229000000 ],
    [q(handle '$cron_text'), '0 0 * 2 6#-5', qr(^$), 20230201000000, 20480201000000, 20760201000000, 21160201000000, 21440201000000, 21720201000000, 22120201000000 ],
    # reject
    [q(reject '$cron_text'), '0 0 * 2 8', qr(^syntax error in wday item: 8$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0/Mon', qr(^syntax error in wday item: 0/Mon$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0#0', qr(^syntax error in wday item: 0#0$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0#6', qr(^syntax error in wday item: 0#6$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0#-6', qr(^syntax error in wday item: 0#-6$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0#A', qr(^syntax error in wday item: 0#A$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 0#Mon', qr(^syntax error in wday item: 0#Mon$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 FOO', qr(^syntax error in wday item: FOO$), 20230201000000 ],
    [q(reject '$cron_text'), '0 0 * 2 Sunday', qr(^syntax error in wday item: Sunday$), 20230201000000 ],

    # time series
    [q(Timeseries '$cron_text'), '0 12 3,4,5 2 0,2,3,4', qr(^$), 20230102150000, 20230201120000, 20230202120000, 20230203120000, 20230204120000],
    [q(Feb-29 (leap year)'$cron_text'), '0 12 29 2 *', qr(^$), 20230101150000, 20240229120000, 20280229120000, 20320229120000],
    [q(Feb-29 & Sunday '$cron_text'), '0 12 29 2 &Sun', qr(^$), 20230102150000, 20320229120000],
    [q(Fri 13 '$cron_text'), '0 12 13 * &Fri', qr(^$), 20230101150000, 20230113120000, 20231013120000, 20240913120000],
    [q(daylight eu '$cron_text'), '0 2 * 3,10 Sun#L', qr(^$), 20230101150000, 20230326020000, 20231029020000, 20240331020000],
];

my $cron_lib_loadable = eval{use FHEM::Scheduler::Cron;1;};
ok($cron_lib_loadable, "FHEM::Scheduler::Cron loaded");

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
    ok($ok, sprintf('%s %s', eval qq{"$desc"} , $err?"(got '$err')":"(# of successful passes: $count)"));
};

done_testing;
exit(0);
