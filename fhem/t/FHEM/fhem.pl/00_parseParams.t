# Simple test. NOTE: exit(0) is necessary
use strict;
use warnings;
use Test::More;

my $cmd = 'set name test1 test2=abc test3 "test4 test4" test5="test5 test5" test6=\'test6=test6\' test7= test8="\'" test9=\'"\' {my $x = "abc"} test10={ { my $abc ="xyz" } }';

my $expected_a = [ 'set', 'name', 'test1', 'test3', 'test4 test4', '{my $x = "abc"}' ];
my $expected_h = {
           'test2' => 'abc',
           'test5' => 'test5 test5',
           'test6' => 'test6=test6',
           'test7' => '',
           'test8' => '\'',
           'test9' => '"',
          'test10' => '{ { my $abc ="xyz" } }'
        };


my ($a,$h) = parseParams( $cmd );

is_deeply($h, $expected_h, "parseParams hash");
is_deeply($a, $expected_a, "parseParams array");

done_testing;
exit(0);
1;
