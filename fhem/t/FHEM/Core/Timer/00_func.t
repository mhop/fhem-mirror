#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Compare qw{is};


use FHEM::Core::Timer::Helper qw(addTimer removeTimer);
use Time::HiRes;


sub timerCallback
{
	my $arg = shift;

	is ($arg,'timer called test',"Check argument");
	done_testing();
	exit(0);
}


sub timerCallback2
{
	fail('this timerCallback2 should never be called');
}
my $count;

subtest 'Add two timers ' => sub {
	$count = addTimer('myName',gettimeofday+2,\&timerCallback,'addTimer test',0);
	is ($count,1,'addtimer returned one');
	$count = addTimer('myName',gettimeofday+1,\&timerCallback2,'remove timer test',0);
	is ($count,2,'addtimer returned two');
};


subtest 'Remove all timers for myName' => sub {
	is(removeTimer('myName'),2,'check number of removed timers');
};

subtest 'add Timer for myName to end test in 2 secs' => sub {
	is(addTimer('myName',gettimeofday+2,\&timerCallback,'timer called test',0),1,'one timer in list');
};


subtest 'add and remove timer by callback func' => sub {
	$count = addTimer('myName',gettimeofday+1,\&timerCallback2,'addTimer test',0);
	is ($count,2,'addtimer returned two');
	is(removeTimer('myName',\&timerCallback2),1,'check number of removed timers');
};


subtest 'add and remove timer by arg' => sub {
	$count = addTimer('myName',gettimeofday+1,\&timerCallback2,'addTimer test',0);
	$count = addTimer('myName',gettimeofday+1,\&timerCallback,'addTimer test',0);
	is ($count,3,'addtimer returned three');
	is(removeTimer('myName',undef,'addTimer test'),2,'check both added timers with arg are removed');
};

subtest 'add and remove timer by callback func and arg' => sub {
	$count = addTimer('myName',gettimeofday+1,\&timerCallback2,'addTimer test',0);
	$count = addTimer('myName',gettimeofday+1,\&timerCallback2,'other arg',0);
	is ($count,3,'addtimer returned three');
	is(removeTimer('myName',\&timerCallback2,'addTimer test'),1,'check only one timer removed');
	is(removeTimer('myName',\&timerCallback2,'other arg'),1,'check only one timer removed');
};


subtest 'optimize ListOFTimers' => sub {
	is(FHEM::Core::Timer::Helper::optimizeLOT(),0,'no elements if no name specified');
	is(FHEM::Core::Timer::Helper::optimizeLOT('myName'),1,'one element left after optimize');
};

1;