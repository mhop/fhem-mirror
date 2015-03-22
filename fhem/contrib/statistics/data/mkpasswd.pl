#!/usr/bin/perl
use strict;

my $user = $ARGV[0];
my $pass = $ARGV[1];
print "$user:".crypt($pass,"Fhem")."\n";
exit 0;
