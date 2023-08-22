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
    [q(Timeseries '$cron_text'), '0 12 29 2 &7', qr(^$), 20230102150000, 20320229120000], 
];

foreach my $test (@$test) {
    my ($desc, $cron_text, $err_expected, @series) = @$test;
    my ($cron_obj, $err) = FHEM::Scheduler::Cron->new($cron_text);
    my $ok = 1;
    
    for my $iter (0 .. $#series -1) {
        # next unless ($series[$iter]);
        my $got = $cron_obj->next($series[$iter]);
        $ok = 0 if ($got ne $series[$iter +1]);
        say sprintf('%s   -> expected: %s, got: %s', ($got ne $series[$iter +1])?'not ok':'ok', $series[$iter +1], $got) if $ENV{EXTENDED_DEBUG};
    }
    $ok &&= ($err // '' =~ /$err_expected/);
    ok($ok, sprintf('%s %s', eval qq{"$desc"} , $err?"(got '$err')":''));
};

done_testing;
exit(0);
