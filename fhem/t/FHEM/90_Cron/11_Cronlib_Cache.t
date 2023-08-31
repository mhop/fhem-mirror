# perl fhem.pl -t t/FHEM/90_Cron/99_Cronlib_DEBUG.t
use v5.14;

use strict;
use warnings;
use Test::More;
use FHEM::Scheduler::Cron;

$ENV{EXTENDED_DEBUG} = 1;

my ($cron_obj, $err, $got);

($cron_obj, $err) = FHEM::Scheduler::Cron->new("1 12,13 1-15 * 2#1");
($got, $err) = $cron_obj->next(20230101120000);
ok((not $err and ($got) and ($got eq 20230101120100)), "after new: $got");
($got, $err) = $cron_obj->next(20230101120100);
ok((not $err and ($got) and ($got eq 20230101130100)), "time cache: $got");
($got, $err) = $cron_obj->next(20230101130100);
ok((not $err and ($got) and ($got eq 20230102120100)), "time cache: $got");
($got, $err) = $cron_obj->next(20230102120100);
ok((not $err and ($got) and ($got eq 20230102130100)), "time cache: $got");
($got, $err) = $cron_obj->next(20230102130100);
ok((not $err and ($got) and ($got eq 20230103120100)), "time cache: $got");
($got, $err) = $cron_obj->next(20230103120100);
ok((not $err and ($got) and ($got eq 20230103130100)), "time cache: $got");
($got, $err) = $cron_obj->next(20230103130100);
ok((not $err and ($got) and ($got eq 20230104120100)), "time cache: $got");
# jumps
($got, $err) = $cron_obj->next(20230105130500);
ok((not $err and ($got) and ($got eq 20230106120100)), "jump forward: $got");
($got, $err) = $cron_obj->next(20230101120000);
ok((not $err and ($got) and ($got eq 20230101120100)), "jump forward: $got");

done_testing;
exit(0);
