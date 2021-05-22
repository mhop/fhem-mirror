# $Id$
package FHEM::Core::Timer::Register;
use strict;
use warnings;

use Carp qw( carp );
use Scalar::Util qw( weaken );
use version; our $VERSION = qv('1.0.0');

use Exporter ('import');use GPUtils qw(GP_Import);

our @EXPORT_OK = qw(setRegIntTimer deleteSingleRegIntTimer resetRegIntTimer deleteAllRegIntTimer);

our %EXPORT_TAGS = (ALL => [@EXPORT_OK]);

BEGIN {
    GP_Import( qw(
        Log3
        RemoveInternalTimer
        InternalTimer
    ));
};

sub setRegIntTimer {
    my $modifier = shift // carp q[No modifier name]            && return;
    my $time     = shift // carp q[No time specified]           && return;
    my $callback = shift // carp q[No function specified]       && return;
    my $hash     = shift // carp q[No hash reference specified] && return;
    my $initFlag = shift // 0;

    my $timerName = "$hash->{NAME}_$modifier";
    my $fnHash     = {
        HASH     => $hash,
        NAME     => $timerName,
        MODIFIER => $modifier
    };
    weaken($fnHash->{HASH});
    if ( defined( $hash->{TIMER}{$timerName} ) ) {
        ::Log3( $hash, 1, "[$hash->{NAME}] possible overwriting of timer $timerName - please delete it first" );
        ::stacktrace();
    }
    else {
        $hash->{TIMER}{$timerName} = $fnHash;
    }

    ::Log3( $hash, '5', "[$hash->{NAME}] setting  Timer: $timerName " . ::FmtDateTime($time) );
    ::InternalTimer( $time, $callback, $fnHash, $initFlag );
    return $fnHash;
}

sub deleteSingleRegIntTimer {
    my $modifier = shift // carp q[No modifier name]            && return;
    my $hash     = shift // carp q[No hash reference specified] && return;
    my $regonly  = shift // 0;

    my $timerName = "$hash->{NAME}_$modifier";
    my $fnHash    = $hash->{TIMER}{$timerName};
    if ( defined $fnHash ) {
        ::Log3( $hash, '5', "[$hash->{NAME}] removing Timer: $timerName" );
        if ( !$regonly ) { ::RemoveInternalTimer($fnHash) };
        delete $hash->{TIMER}{$timerName};
    }
    return;
}

sub resetRegIntTimer {
    my $modifier = shift // carp q[No modifier name]            && return;
    my $time     = shift // carp q[No time specified]           && return;
    my $callback = shift // carp q[No function specified]       && return;
    my $hash     = shift // carp q[No hash reference specified] && return;
    my $initFlag = shift // 0;

    deleteSingleRegIntTimer( $modifier, $hash );
    return setRegIntTimer ( $modifier, $time, $callback, $hash, $initFlag );
}

sub deleteAllRegIntTimer {
    my $hash     = shift // carp q[No hash reference specified] && return;

    for ( keys %{ $hash->{TIMER} } ) {
        deleteSingleRegIntTimer( $hash->{TIMER}{$_}{MODIFIER}, $hash );
    }
    return;
}

1;

__END__

=head1 NAME

FHEM::Core::Timer::Register - FHEM extension for handling of InternalTimer in special cases

=head1 VERSION

This document describes FHEM::Core::Timer::Register version 1.0


=head1 SYNOPSIS

  use FHEM::Core::Timer::Register qw(:ALL);


This is an example UndefFn() making sure all InternalTimer will be deleted in undefine case
  sub Undefine {
    my $hash = shift // return;  #Module instance hash is essential for proper use!
...
    deleteAllRegIntTimer($hash); #InternalTimer set up by the method provided by this lib 
    RemoveInternalTimer($hash);  #other InternalTimer
...
    return;
  }

This function will renew an registered timer set elswhere by setRegIntTimer
  sub someInternalTimerSetupCall {
    my $hash     = shift // return;
    my $identy   = shift // return;
    my $timeout  = shift // 60;
...
    resetRegIntTimer( $identiy, time + $timeout, \&someOftenCalledFunction, $hash, 0)
...


  sub someOftenCalledFunction {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;
...

=head1 DESCRIPTION

Using the register provided by this lib ONLY makes sense, if you have the need to often call the same $callback (see function description of setRegIntTimer(), but in parallel and with different parameters, and/or you want to add or change additional parameters in between setting the timer and callback time.
If you have different requirements, it's recommended to use other means, e.g. separate callback functions for different purposes, as this method here causes some overhead. Du to the later, using this lib also is not recommended, if you have to often change timers

=head1 EXPORT

The following functions are exported by this module: 
C<setRegIntTimer>,C<deleteSingleRegIntTimer>, C<resetRegIntTimer>, C<deleteAllRegIntTimer>

=over 4

=back

=head1 OBJECTS

=head1 NOTES

=head1 BUGS AND LIMITATIONS

See DESCRIPTION for details on whether you really will have any benefit from thi piece of code. In most cases you will not...

=head1 INCOMPATIBILITIES

=head1 DEPENDENCIES

=head1 CONFIGURATION AND ENVIRONMENT
Obviously needs fhem.pl and it's InternalTimer functions to run.

=head1 DIAGNOSTICS

=head1 SUBROUTINES/METHODS

setRegIntTimer 
Function to set an registered InternalTimer. Needs the following arguments: 
$modifier: a unique identifier, that also will be used to label the timer (in combination with device instance name derived from $hash->{NAME}. For $hash see 4th argument)
$time: endtime for InternalTimer (seconds since 1970/1/1) - as ususally used in direct InternalTimer calls 
$callback: Function to be called by InternalTimer
$hash: Instance hash for the module instance - as usual within FHEM

Will return a reference to a fnhash, which may be used to add further arguments to later function call.

deleteSingleRegIntTimer
Function to remove an registered InternalTimer. Needs $modifier and $hash as arguments as described above. Optionally accepts $regonly as argument, in case you just want to delete the timer hash from the register (in $hash->{TIMER}). Usefull to do some cleanup in $callback function.

resetRegIntTimer
Needs the same arguments like, setRegIntTimer, and will remove the already set InternalTimer with the same modifier (if set). 

deleteAllRegIntTimer
Needs just $hash as argument and will savely remove all registered InternalTimer set up with the above mentionned functions.

=head1 AUTHOR

Beta-User <lt>Beta-User AT fhem DOT de<gt>

=head1 LICENSE AND COPYRIGHT

FHEM::Core::Timer::Register is released under the same license as FHEM.

=cut
