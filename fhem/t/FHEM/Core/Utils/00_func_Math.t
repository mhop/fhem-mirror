#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Compare qw{is};

use FHEM::Core::Utils::Math;

subtest 'Round to three decimals after dot' => sub {
 	is (FHEM::Core::Utils::Math::round(100/3,3),33.333,'round returned three decimals after dot');
};

subtest 'Round negative, to one decimals after dot' => sub {
 	is (FHEM::Core::Utils::Math::round(-100/3,1),-33.3,'round returned one decimals after dot');
};

subtest 'Round negative, to no decimals after dot' => sub {
 	is (FHEM::Core::Utils::Math::round(100/3,0),33,'round returned zero decimals after dot');
};

subtest 'No decimals specified' => sub {
 	is (FHEM::Core::Utils::Math::round(100/3),U(),'round returned undef');
};


subtest 'No value specified' => sub {
 	is (FHEM::Core::Utils::Math::round(),U(),'round returned undef');
};

done_testing();
exit(0);
1;