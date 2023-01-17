# $Id$
package FHEM::Core::Utils::Math;
use strict;
use warnings;
use utf8;
use Carp qw(croak carp);
use Time::HiRes;

use version; our $VERSION = qv('1.0.0');
use Exporter qw(import);
 
#our @EXPORT_OK = qw(); 

sub round
{
  my $number = shift        // carp q[No number specified]                          && return;
  my $decimalPoint 	= shift	// carp q[No number of decimal points specified] 		&& return;
  
  return sprintf("%.${decimalPoint}f",$number);
}


1;


__END__

=head1 NAME

FHEM::Core::Utils::Math - Perl Module to provide calculation utilitys

=head1 VERSION

This document describes FHEM::Core::Utils::Math version 1.0


=head1 SYNOPSIS

  use FHEM::Core::Utils::Math;
  

=head1 DESCRIPTION


# round a given number to specified number of digits
FHEM::Core::Utils::Math::round($number,3);


=head1 EXPORT

The following functions are exported by this module: 

none

=back

=head1 NOTES

round isn't exported per default, because there are already two perl packages, wich can export round (POSIX and Math::round)
To be sure, which round funtion is used, it is savest to not export round and use it withhin is package name. So no problems are caused, if somewhere POSIX or math::round is used, which overrides round in main.

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Sidey79

=head1 LICENSE

FHEM::Core::Utils::Math is released under the same license as FHEM.

=cut
