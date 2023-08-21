# perl fhem.pl -t t/FHEM/90_Cron/10_Cronlib.t

use strict;
use warnings;
use Test::More;
use FHEM::Scheduler::Cron;

$ENV{EXTENDED_DEBUG} = 1;

# syntax of list 
# description of test | cron expr | from | next, (more next.., ..) | err expected (regex) | 

my $test = [
    #['must throw an error if no cron text given', '', 0, 0, qr(no cron expression)],
    #['must throw an error if cron expression exceeds 255 chars', q(0) x 256, 0, 0, qr(cron expression exceeds limit)],

    # [q(accept '$cron_text'), '* * * * *', 0, 0, qr(^$)],
    # [q(precedence mday '$cron_text'), '* * 1 * *', 0, 0, qr(^$)],
    # [q(precedence wday '$cron_text'), '* * * * 2', 0, 0, qr(^$)],
    # [q(mday OR wday logic '$cron_text'), '* * 1 * 2', 0, 0, qr(^$)],
    [q(mday AND wday logic '$cron_text'), '5/5 10 * * *', 20230101120000, 20230101000000, qr(^$)],
    # [q(RULE4 logic '$cron_text'), '* * * * 1,&2', 0, 0, qr(^$)],
    # [q(validate date '$cron_text'), '* * 30 2 *', 0, 0, qr(^$)],
];
    
#     # positive tests for minute
#     [q(accept '$cron_text'), '* * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1-5 * * * *', 0, 0, qr(^$)],
#     [q(accept '$cron_text'), '1-5/1 * * * *', 0, 0, qr(^$)],
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
# ];

# print join ",", (20200101120000 .. 20200101120010 ), (20200101120100 .. 20200101120110 );
# print "\n";

# my $cron_lib_loadable = eval{use FHEM::Scheduler::Cron;1;};
# ok($cron_lib_loadable, "FHEM::Scheduler::Cron loaded");

foreach my $test (@$test) {
    my ($desc, $cron_text, $from, $next, $err_expected) = @$test;
    # print "$desc, $cron_text, $from, $next, $err_expected \n";
    my $cron_obj = FHEM::Scheduler::Cron->new($cron_text);
    my $err = $cron_obj->{error} // '';

    my $ok = 1;
    my @r = split(',', $next);
    for my $iter (0 .. $#r) {
        next unless ($r[$iter]);
        # next;
        print "iteration $iter $#r ";
        print "$r[$iter]\n";
        $cron_obj->next($r[$iter]);
        #print "\n";
    }
    $ok &&= ($err =~ /$err_expected/);
    ok($ok, sprintf('%s %s', eval qq{"$desc"} , $err?"(got '$err')":''));
}

done_testing;
exit(0);
