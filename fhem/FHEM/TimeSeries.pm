# $Id$

##############################################################################
#
#     TimeSeries.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package TimeSeries;

use warnings;
use strict;
#use Data::Dumper;


no if $] >= 5.017011, warnings => 'experimental::smartmatch';


# If two subsequent points in the time series are less than
# EPS seconds apart, the second value is ignored. This feature catches
# - time running backwards,
# - two points at the same time (within the resolution of time),
# - precision loss due to points too close in time.
# Ignored values are counted in the lost property.
use constant EPS => 0.001; # 1 millisecond

#
# A time series is a sequence of points (t,v) with timestamp t and value v.
#

sub new() {
  my ($class, $args)= @_;
  my @METHODS= qw(none linear const);
  # none = no time weighting at all
  # we must have an assumption about how the value varies between
  # two data points in the time series (discretization method).
  # The const method assumes, that the value was constant
  # since the previous one.
  # The linear method assumes, that the value changed linearly
  # from the previous one to the current one.
  my $self= {
    method => $args->{method} || "none",
    autoreset => $args->{autoreset}, # if set, resets series every autoreset seconds
    count => 0, 	# number of points added
    lost => 0,		# number of points rejected
    t0 => undef,	# timestamp of first value added
    t => undef,		# timestamp of last value added
    v0 => undef,	# first value added
    v => undef,		# last value added
    min => undef,	# smallest value in the series
    max => undef,	# largest value in the series
    # statistics
    n => 0,		# size of sample
    mean => undef,	# arithmetic mean of time-weighted values
    sd => undef,	# standard deviation of time-weighted values
    _t0 => undef,	# same as t0; moved to _t on reset
    _t => undef,	# same as t but survives a reset
    _v => undef,	# same as v but survives a reset
    _M => undef,	# see below
    _S => undef,	# see below
  }; # we are a hash reference
  $self->{method}= "none" unless($self->{method} ~~ @METHODS);
  return bless($self, $class); # make $self an object of class $class
}

#
# reset the series
#
sub reset() {
  my $self= shift;
  # statistics
  # _t and _v is taken care of in new() and in add()
  $self->{n}= 0;	
  $self->{mean}= undef;	
  $self->{sd}= undef;	
  $self->{_M}= undef;	
  $self->{_S}= undef;
  $self->{_t0}= $self->{_t};	
  # 
  $self->{count}= 0;		
  $self->{lost}= 0;		
  $self->{t0}= undef;	
  $self->{t}= undef;	
  $self->{v0}= undef;
  $self->{v}= undef;	
  $self->{min}= undef;
  $self->{max}= undef;
}

sub _updatestat($$$) {
  my ($self, $V)= @_;

  # see Donald Knuth, The Art of Computer Programming, ch. 4.2.2, formulas 14ff.
  my $n= ++$self->{n};
  if($n> 1) {
    my $M= $self->{_M};
    $self->{_M}= $M + ($V - $M) / $n;
    $self->{_S}= $self->{_S} + ($V - $M) * ($V - $self->{_M});
    #main::Debug("V= $V M= $M _M= ".$self->{_M}." _S= " . $self->{_S});
  } else {
    $self->{_M}= $V;
    $self->{_S}= 0;
  }
  #main::Debug("STAT UPD n= $n");
}  
  
#
# has autoreset period elapsed?
#

sub elapsed($$) {
  my ($self, $t)= @_;
  return  defined($self->{autoreset}) && 
	  defined($self->{_t0}) && 
	  ($t - $self->{_t0} >= $self->{autoreset});
}

#
# add a point to the series
#
sub add($$$) {
  my ($self, $t, $v)= @_;

  # reject values if time resolution is insufficient
  if(defined($self->{_t}) &&  $t - $self->{_t} < EPS) {
    $self->{lost}++;
    return; # note: for consistency, the value is not considered at all
  }
 
  # autoreset 
  $self->reset() if($self->elapsed($t));
  
  #main::Debug("ADD ($t,$v)");  ###

  # count
  $self->{count}++;

  # statistics
  if($self->{method} eq "none") {
    # no time-weighting
    $self->_updatestat(1, $v);
  } elsif(defined($self->{_t})) {
    # time-weighting
    my $dt= $t - $self->{_t};
    if($self->{method} eq "const") {
	# steps
	$self->_updatestat($self->{_v} * $dt);
    } else {
	# linear interpolation  
	$self->_updatestat(0.5 * ($self->{_v} + $v) * $dt);
    }
  }
  $self->{_t}= $t;
  $self->{_v}= $v;
  
  # first point 
  if(!defined($self->{t0})) {
    $self->{t0}= $t;
    $self->{v0}= $v;
  }
  if(!defined($self->{_t0})) {
    $self->{_t0}= $t;
  }
  
  # last point
  $self->{t}= $t; 
  $self->{v}= $v;
  
  # min, max
  $self->{min}= $v if(!defined($self->{min}) || $v< $self->{min});
  $self->{max}= $v if(!defined($self->{max}) || $v> $self->{max});
  
  # mean, standard deviation
  my $n= $self->{n};
  if($n) {
    my $T= $self->{method} eq "none" ? 1 : ( $self->{t} - $self->{_t0} ) / $n;
    if($T> 0) {
      #main::Debug("T= $T  _M= " . $self->{_M} );
      $self->{mean}= $self->{_M} / $T;
      # in the time-weighted methods, this is just a measure for the variation of the values
      $self->{sd}= sqrt($self->{_S}/ ($n-1)) / $T if($n> 1); 
    }  
  }
  #main::Debug(Dumper($self)); ###
  
}


1;  


=pod

B<TimeSeries> is a perl module to feed data points and get some statistics on them as you go.

  my $ts= TimeSeries->new( { method => "const" } );
  $ts->add(3.3, 2.1);
  $ts->add(5.1, 1.8);
  $ts->add(8.8, 2.4);
  printf("count= %d, n= %d, lost= %d, first= %f, last= %f, min= %f, max= %f, mean= %f, sd= %f\n", 
      $ts->{count}, $ts->{n}, $ts->{lost}, $ts->{v0}, $ts->{v},
      $ts->{min}, $ts->{max},
      $ts->{mean}, $ts->{sd}
      );
      
=cut
  
  