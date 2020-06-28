# $Id$
package FHEM::Core::Timer::Helper;
use strict;
use warnings;
use utf8;
use Carp qw(croak carp);
use Time::HiRes;

use version; our $VERSION = qv('1.0.0');
my %LOT;  # Hash for ListOfTimers

use Exporter qw(import);
 
our @EXPORT_OK = qw(addTimer removeTimer optimizeLOT); 

sub addTimer {
	my $defName 	= shift // carp 'No definition name'	 	&& return;
	my $time 		= shift	// carp q[No time specified] 		&& return;
	my $func 		= shift	// carp q[No function specified] 	&& return;
	my $arg 		= shift	// q{};
	my $initFlag 	= shift	// 0;
	
	
	my %h = (
			arg		 	=> $arg, 
			func 		=> $func,
			calltime 	=> $time,
	);

	
	::InternalTimer($time, $func, $arg , $initFlag);      

	return push @{$LOT{$defName}} , \%h;
}


sub removeTimer {
	my $defName 	= shift // carp q[No definition name];
	my $func 		= shift	// undef;
	my $arg 		= shift	// q{};

	return 0 if ( !exists $LOT{$defName} );
	
	my $numRemoved	=	0;
    for my $index (0 .. scalar @{$LOT{$defName}}-1 ) {
     	if ( ref $LOT{$defName}[$index] eq 'HASH' && exists	$LOT{$defName}[$index]->{func}
     		&&	(!defined $func 		|| $LOT{$defName}[$index]->{func} 		== $func ) 
			&& 	( $arg eq q{} 			|| $LOT{$defName}[$index]->{arg}		eq $arg) 
		   ) {
			::RemoveInternalTimer($LOT{$defName}[$index]->{arg},$LOT{$defName}[$index]->{func});
			delete($LOT{$defName}[$index]);
			$numRemoved++;
		}  
    }
	return $numRemoved;
}


sub optimizeLOT
{
	my $defName 	= shift // carp q[No definition name];
	return 0 if ( !exists $LOT{$defName} );
	
	my $now= ::gettimeofday();
	@{$LOT{$defName}} = grep {  $_->{calltime} >= $now  } @{$LOT{$defName}};

	return scalar @{$LOT{$defName}};
}

1;