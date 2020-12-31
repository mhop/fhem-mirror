##############################################
# test evalExpr and other Util functions
##############################################
use strict;
use warnings;
use Test::More;

use_ok ('FHEM::HTTPMOD::Utils', qw(:all));

my $hash  = $defs{'H2'};
my $name  = 'H2';
my $val   = 5;
my @array = (1,2,3);
my %tHash = (a => 10, b => 20);
my $exp   = '$val * 2';

my $result = EvalExpr($hash, {expr => $exp, '$val' => $val, '@array' => \@array});
#Log3 $name, 3, "$name: result of EvalExpr test 1 = $result";
is $result, 10, "simple expression with one scalar in list";

$exp   = '$array[1] * 2';
$result = EvalExpr($hash, {expr => $exp, '$val' => $val, '@array' => \@array});
is $result, 4, "simple expression with array ref in hash";

$exp   = '$hash{a} * 2';
$result = EvalExpr($hash, {expr => $exp, '$val' => $val, '%hash' => \%tHash});
is $result, 20, "simple expression with hash ref in hash";

$exp   = '$hash->{a} * 2';
$result = EvalExpr($hash, {expr => $exp, '$val' => $val, '$hash' => \%tHash});
is $result, 20, "simple expression with hash ref as ref in hash";

my $format = '';
$val = undef;
$result = FormatVal($hash, {val => $val, format => $format});        
is $result, undef, "FormatVal with empty format and undef value";

$format = '%.2f';
$result = FormatVal($hash, {val => $val, format => $format});        
is $result, "0.00", "FormatVal with empty format and undef value";

done_testing;
exit(0);

1;
