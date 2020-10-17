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
#
#     CHANGES
#
#     27.06.2015 Jens Beyer (jensb at forum dot fhem dot de)
#       new: properties holdTime (in), integral (out) and tSeries/vSeries (data buffer)
#       new: defining holdTime will enable data buffer and calculation of moving stat values instead of block stat values
#       modified: method _updatestat requires only one parameter apart from self
#       modified: when property 'method' is set to 'none' _updatestat() will be called with new data value instead of const 1
#
#     19.07.2015 Jens Beyer (jensb at forum dot fhem dot de)
#       new: static method selftest
#
#     23.07.2015 Jens Beyer (jensb at forum dot fhem dot de)
#       new: method getValue
#
#     24.01.2016 knxhm at forum dot fhem dot de & Jens Beyer (jensb at forum dot fhem dot de)
#       new: property median (out)
#
#     29.01.2016 Jens Beyer (jensb at forum dot fhem dot de)
#       modified: method elapsed reverted to version from 2015-01-31 to provide downsampling and buffering through fhem.pl
#       modified: method _housekeeping does not reset time series if hold time is specified
#
#     17.10.2020 Boris Neubert
#       modified: fix for calculation of standard deviation
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
    holdTime => $args->{holdTime}, # if set, enables data buffer and limits series to holdTime seconds
    count => 0, 	# number of points successfully added
    lost => 0,		# number of points rejected
    t0 => undef,	# timestamp of first value added
    t => undef,		# timestamp of last value added
    v0 => undef,	# first value added
    v => undef,		# last value added
    min => undef,	# smallest value in the series
    max => undef,	# largest value in the series
    tSeries => undef,# array of timestamps, used if holdTime is defined
    vSeries => undef,# array of values, used if holdTime is defined
    # statistics
    n => 0,		# size of sample (non time weighted) or number of intervals (time weighted)
    mean => undef,	# arithmetic mean of values
    sd => undef,	# standard deviation of values
    integral => undef,  # sum (holdTime undefined) or integral area (holdTime defined) of all values
    median => undef, # median of all values (method must be "none" and holdTime must be defined)
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
  $self->{integral}= 0;	
  $self->{median}= undef;	
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
  #     
  $self->{tSeries}= undef;
  $self->{vSeries}= undef;
  
  if (!defined($self->{autoreset})) {
    $self->{_t0}= undef; 
    $self->{_t}= undef; 
    $self->{_v}= undef; 
  } 
}

#
# trim series depth to holdTime relative to now
#
sub trimToHoldTime() {
  my $self= shift;
  
  my $n = @{$self->{tSeries}};
  #main::Debug("TimeSeries::trimToHoldTime: old count=$n\n");
  
  if (defined($self->{holdTime}) && defined($self->{tSeries})) {
    # trim series cache depth to holdTime relative to now
    my $keepTime = time() - $self->{holdTime};
    my $trimCount = 0;
    foreach (@{$self->{tSeries}}) {
      if ($_ >= $keepTime) {
        last;
      }
      $trimCount++;
    }
    
    if ($trimCount > 0) {
      # remove aged out samples
      splice(@{$self->{tSeries}}, 0, $trimCount);
      splice(@{$self->{vSeries}}, 0, $trimCount);
      
      # update properties
      # - lost is kept untouched because it cannot be consistently manipulated      
      $self->{count} = @{$self->{tSeries}};
      #main::Debug("TimeSeries::trimToHoldTime: new count=$count before\n");
      if ($self->{count} > 0) {
        $self->{t0} = $self->{tSeries}[0];
        $self->{t}  = $self->{tSeries}[$#{$self->{tSeries}}]; 
        $self->{v0} = $self->{vSeries}[0];
        $self->{v}  = $self->{vSeries}[$#{$self->{vSeries}}];
        $self->{_t0}= $self->{t0}; 
        $self->{_t} = $self->{t}; 
        $self->{_v} = $self->{v}; 
      } else {
        $self->{t0} = undef; 
        $self->{t}  = undef;  
        $self->{v0} = undef;
        $self->{v}  = undef;
        $self->{_t0}= undef; 
        $self->{_t} = undef; 
        $self->{_v} = undef; 
      }             
   
      # reset statistics 
      $self->{n}       = 0;
      $self->{min}     = undef;
      $self->{max}     = undef;
      $self->{mean}    = undef; 
      $self->{sd}      = undef; 
      $self->{integral}= 0;
      $self->{_M}      = undef; 
      $self->{_S}      = undef;

      # rebuild statistic for remaining samples
      for my $i (0 .. $#{$self->{tSeries}}) {
        my $tn= $self->{tSeries}[$i];
        my $vn= $self->{vSeries}[$i];
            
        # min, max
        $self->{min}= $vn if(!defined($self->{min}) || $vn< $self->{min});
        $self->{max}= $vn if(!defined($self->{max}) || $vn> $self->{max});
  
        # statistics
        if($self->{method} eq "none") {
          # no time-weighting
          $self->_updatestat($vn); 
        } else {
          # time-weighting
          if($i > 0) {
            my $to= $self->{tSeries}[$i-1];
            my $vo= $self->{vSeries}[$i-1];
            my $dt= $tn - $to;
            if($self->{method} eq "const") {
              # steps
              $self->_updatestat($vo * $dt);
            } else {
              # linear interpolation  
              $self->_updatestat(0.5 * ($vo + $vn) * $dt);
            }
          }
        }
      }
    }
  }
  
  #my $count = @{$self->{tSeries}};
  #main::Debug("TimeSeries::trimToHoldTime: new count=$count\n");  
}

sub _updatestat($$) {
  my ($self, $V)= @_;

  # see Donald Knuth, The Art of Computer Programming, ch. 4.2.2, p. 232ff, formulas 14ff.
  # https://doc.lagout.org/science/0_Computer%20Science/2_Algorithms/The%20Art%20of%20Computer%20Programming%20%28vol.%202_%20Seminumerical%20Algorithms%29%20%283rd%20ed.%29%20%5BKnuth%201997-11-14%5D.pdf
  my $n= ++$self->{n};
  if($n> 1) {
    my $M= $self->{_M};
    $self->{_M}= $M + ($V - $M) / $n;
    $self->{_S}= $self->{_S} + ($V - $M) * ($V - $self->{_M});
    $self->{integral}+= $V;
    #main::Debug("V= $V M= $M _M= ".$self->{_M}." _S= " .$self->{_S}." int= ".$self->{integral});
  } else {
    $self->{_M}= $V;
    $self->{_S}= 0;
    $self->{integral}= $V;
  }
  #main::Debug("STAT UPD n=$n");
}  
  
#
# has autoreset period elapsed?
# used by fhem.pl for downsampling
#
sub elapsed($$) {
  my ($self, $t)= @_;
  return defined($self->{autoreset}) && defined($self->{_t0}) && ($t - $self->{_t0} >= $self->{autoreset});
}

#
# reset or trim series
#
sub _housekeeping($) {
  my ($self, $t)= @_;

  if($self->elapsed($t) && !defined($self->{holdTime})) {
    #main::Debug("TimeSeries::_housekeeping: reset\n");
    $self->reset(); 
  } elsif(defined($self->{holdTime}) && defined($self->{_t0}) && ($t - $self->{_t0} >= $self->{holdTime})) { 
    #main::Debug("TimeSeries::_housekeeping: trimToHoldTime\n");
    $self->trimToHoldTime();
  } 
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
 
  # reset or trim series 
  $self->_housekeeping($t);
  
  #main::Debug("ADD ($t,$v)");  ###

  # add point to data buffer
  if(defined($self->{holdTime})) {
    $self->{tSeries}[$self->{count}] = $t;
    $self->{vSeries}[$self->{count}] = $v;
  }

  # count
  $self->{count}++;
  
  # statistics
  if($self->{method} eq "none") {
    # no time-weighting
    $self->_updatestat($v);
    
    # median
    if(defined($self->{holdTime})) {    
      my @sortedVSeries = sort {$TimeSeries::a <=> $TimeSeries::b} @{$self->{vSeries}}; 
      my $center = int($self->{count} / 2);
      if($self->{count} % 2 == 0) {
        $self->{median} = ($sortedVSeries[$center - 1] + $sortedVSeries[$center]) / 2;
      } else {
        $self->{median} = $sortedVSeries[$center];
      }
    }
  } else {
    # time-weighting
    if(defined($self->{_t})) {
      my $dt= $t - $self->{_t};
      if($self->{method} eq "const") {
        # steps
        $self->_updatestat($self->{_v} * $dt);
      } else {
        # linear interpolation  
        $self->_updatestat(0.5 * ($self->{_v} + $v) * $dt);
      }
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

#
# get corresponding value for given timestamp (data buffer must be enabled by setting holdTime)
#
# - if there is no exact match found for timestamp, 
#   the value of the next smallest timestamp available is returned
# - if timestamp is not inside the current time range undef is returned
# 
sub getValue($$) {
  my ($self, $t)= @_;
  
  my $v = undef;  
  if (defined($self->{tSeries}) && $t >= $self->{t0} && $t <= $self->{t}) {
    my $index = 0;
    for my $i (0 .. $#{$self->{tSeries}}) {
      my $ti= $self->{tSeries}[$i];
      if ($ti > $t) {
        last;
      }
      $index++;
    }  
    $v = $self->{vSeries}[--$index];
  }
  
  return $v;
}

#
# static class selftest performs unit test and logs validation errors
#
sub selftest() {
  my ($self, @params) = @_;
  die "static sub selftest may not be called as object method" if ref($self);
  
  my $success = 1;
  
  # block operation tests
  my $tsb = TimeSeries->new( { method => "none", autoreset => 3 } );
  $tsb->add(0, 0.8);
  $tsb->add(1, 1.0);
  $tsb->add(2, 1.2);
  if ($tsb->{count} != 3)      { $success = 0; main::Debug("unweighed block add test failed: count mismatch $tsb->{count}/3\n"); }
  if ($tsb->{lost} != 0)       { $success = 0; main::Debug("unweighed block add test failed: lost mismatch $tsb->{lost}/0\n"); }
  if ($tsb->{n} != 3)          { $success = 0; main::Debug("unweighed block add test failed: n mismatch $tsb->{n}/3\n"); }
  if ($tsb->{t0} != 0)         { $success = 0; main::Debug("unweighed block add test failed: first time mismatch $tsb->{t0}/0\n"); }
  if ($tsb->{t} != 2)          { $success = 0; main::Debug("unweighed block add test failed: last time mismatch $tsb->{t}/2\n"); }
  if ($tsb->{v0} != 0.8)       { $success = 0; main::Debug("unweighed block add test failed: first value mismatch $tsb->{v0}/0.8\n"); }
  if ($tsb->{v} != 1.2)        { $success = 0; main::Debug("unweighed block add test failed: last value mismatch $tsb->{v}/1.2\n"); }
  if ($tsb->{min} != 0.8)      { $success = 0; main::Debug("unweighed block add test failed: min mismatch $tsb->{min}/0.8\n"); }
  if ($tsb->{max} != 1.2)      { $success = 0; main::Debug("unweighed block add test failed: max mismatch $tsb->{max}/1.2\n"); }
  if ($tsb->{mean} != 1.0)     { $success = 0; main::Debug("unweighed block add test failed: mean mismatch $tsb->{mean}/1.0\n"); }
  if (!defined($tsb->{sd}) || $tsb->{sd} ne sqrt(0.13/2)) { $success = 0; main::Debug("unweighed block add test failed: sd mismatch $tsb->{sd}/0.254950975679639\n"); }
  if ($tsb->{integral} != 3.0) { $success = 0; main::Debug("unweighed block add test failed: sum mismatch $tsb->{integral}/3.0\n"); }
  $tsb->add(3, 0.8);
  $tsb->add(4, 1.2);
  if ($tsb->{count} != 2)      { $success = 0; main::Debug("unweighed block autoreset test failed: count mismatch $tsb->{count}/2\n"); }
  if ($tsb->{lost} != 0)       { $success = 0; main::Debug("unweighed block autoreset test failed: lost mismatch $tsb->{lost}/0\n"); }
  if ($tsb->{n} != 2)          { $success = 0; main::Debug("unweighed block autoreset test failed: n mismatch $tsb->{n}/2\n"); }
  if ($tsb->{t0} != 3)         { $success = 0; main::Debug("unweighed block autoreset test failed: first time mismatch $tsb->{t0}/3\n"); }
  if ($tsb->{t} != 4)          { $success = 0; main::Debug("unweighed block autoreset test failed: last time mismatch $tsb->{t}/4\n"); }
  if ($tsb->{v0} != 0.8)       { $success = 0; main::Debug("unweighed block autoreset test failed: first value mismatch $tsb->{v0}/0.8\n"); }
  if ($tsb->{v} != 1.2)        { $success = 0; main::Debug("unweighed block autoreset test failed: last value mismatch $tsb->{v}/1.2\n"); }
  if ($tsb->{min} != 0.8)      { $success = 0; main::Debug("unweighed block autoreset test failed: min mismatch $tsb->{min}/0.8\n"); }
  if ($tsb->{max} != 1.2)      { $success = 0; main::Debug("unweighed block autoreset test failed: max mismatch $tsb->{max}/1.2\n"); }
  if ($tsb->{mean} != 1.0)     { $success = 0; main::Debug("unweighed block autoreset test failed: mean mismatch $tsb->{mean}/1.0\n"); }
  if (!defined($tsb->{sd}) || $tsb->{sd} ne "0.4") { $success = 0; main::Debug("unweighed block autoreset test failed: sd mismatch $tsb->{sd}/0.4\n"); }
  if ($tsb->{integral} != 2.0) { $success = 0; main::Debug("unweighed block autoreset test failed: sum mismatch $tsb->{integral}/2.0\n"); }

  $tsb->reset();
  $tsb->{_t0} = undef;
  $tsb->{_t} = undef;
  $tsb->{_v} = undef;
  $tsb->{method} = 'const';
  $tsb->{autoreset} = 4;
  $tsb->add(0, 1.0);
  $tsb->add(1, 2.0);
  $tsb->add(3, 0.5);
  if ($tsb->{count} != 3)      { $success = 0; main::Debug("const weighed block add test failed: count mismatch $tsb->{count}/3\n"); }
  if ($tsb->{lost} != 0)       { $success = 0; main::Debug("const weighed block add test failed: lost mismatch $tsb->{lost}/0\n"); }
  if ($tsb->{n} != 2)          { $success = 0; main::Debug("const weighed block add test failed: n mismatch $tsb->{n}/2\n"); }
  if ($tsb->{t0} != 0)         { $success = 0; main::Debug("const weighed block add test failed: first time mismatch $tsb->{t0}/0\n"); }
  if ($tsb->{t} != 3)          { $success = 0; main::Debug("const weighed block add test failed: last time mismatch $tsb->{t}/3\n"); }
  if ($tsb->{v0} != 1.0)       { $success = 0; main::Debug("const weighed block add test failed: first value mismatch $tsb->{v0}/1.0\n"); }
  if ($tsb->{v} != 0.5)        { $success = 0; main::Debug("const weighed block add test failed: last value mismatch $tsb->{v}/0.5\n"); }
  if ($tsb->{min} != 0.5)      { $success = 0; main::Debug("const weighed block add test failed: min mismatch $tsb->{min}/0.5\n"); }
  if ($tsb->{max} != 2.0)      { $success = 0; main::Debug("const weighed block add test failed: max mismatch $tsb->{max}/2.0\n"); }
  if ($tsb->{mean} ne (2.5/1.5)) { $success = 0; main::Debug("const weighed block add test failed: mean mismatch $tsb->{mean}/1.66666666666667\n"); }
  if (!defined($tsb->{sd}) || $tsb->{sd} ne 2) { $success = 0; main::Debug("const weighed block add test failed: sd mismatch $tsb->{sd}/2\n"); }
  if ($tsb->{integral} != 5.0) { $success = 0; main::Debug("const weighed block add test failed: sum mismatch $tsb->{integral}/5.0\n"); }
  
  # moving operation tests
  my $now = time();
  my $tsm = TimeSeries->new( { method => "none", holdTime => 3 } );
  $tsm->add($now-2, 0.8);
  $tsm->add($now-1, 1.0);
  $tsm->add($now,   1.2);
  if ($tsm->{count} != 3)      { $success = 0; main::Debug("unweighed moving add test failed: count mismatch $tsm->{count}/3\n"); }
  if ($tsm->{lost} != 0)       { $success = 0; main::Debug("unweighed moving add test failed: lost mismatch $tsm->{lost}/0\n"); }
  if ($tsm->{n} != 3)          { $success = 0; main::Debug("unweighed moving add test failed: n mismatch $tsm->{n}/3\n"); }
  if ($tsm->{t0} != ($now-2))  { $success = 0; main::Debug("unweighed moving add test failed: first time mismatch $tsm->{t0}\n"); }
  if ($tsm->{t} != $now)       { $success = 0; main::Debug("unweighed moving add test failed: last time mismatch $tsm->{t}\n"); }
  if ($tsm->{v0} != 0.8)       { $success = 0; main::Debug("unweighed moving add test failed: first value mismatch $tsm->{v0}/0.8\n"); }
  if ($tsm->{v} != 1.2)        { $success = 0; main::Debug("unweighed moving add test failed: last value mismatch $tsm->{v}/1.2\n"); }
  if ($tsm->{min} != 0.8)      { $success = 0; main::Debug("unweighed moving add test failed: min mismatch $tsm->{min}/0.8\n"); }
  if ($tsm->{max} != 1.2)      { $success = 0; main::Debug("unweighed moving add test failed: max mismatch $tsm->{max}/1.2\n"); }
  if ($tsm->{mean} != 1.0)     { $success = 0; main::Debug("unweighed moving add test failed: mean mismatch $tsm->{mean}/1.0\n"); }
  if (!defined($tsm->{sd}) || $tsm->{sd} ne sqrt(0.13/2)) { $success = 0; main::Debug("unweighed moving add test failed: sd mismatch $tsm->{sd}/0.254950975679639\n"); }
  if ($tsm->{integral} != 3.0) { $success = 0; main::Debug("unweighed moving add test failed: sum mismatch $tsm->{integral}/3.0\n"); }
  if ($tsm->{median} != 1.0)   { $success = 0; main::Debug("unweighed moving add test failed: median mismatch $tsm->{median}/1.0\n"); }
  sleep(3);  
  $tsm->add($now+1, 1.0);
  $tsm->add($now+2, 0.8);
  if ($tsm->{count} != 3)      { $success = 0; main::Debug("unweighed moving holdTime test failed: count mismatch $tsm->{count}/3\n"); }
  if ($tsm->{lost} != 0)       { $success = 0; main::Debug("unweighed moving holdTime test failed: lost mismatch $tsm->{lost}/0\n"); }
  if ($tsm->{n} != 3)          { $success = 0; main::Debug("unweighed moving holdTime test failed: n mismatch $tsm->{n}/3\n"); }
  if ($tsm->{t0} != $now)      { $success = 0; main::Debug("unweighed moving holdTime test failed: first time mismatch $tsm->{t0}\n"); }
  if ($tsm->{t} != ($now+2))   { $success = 0; main::Debug("unweighed moving holdTime test failed: last time mismatch $tsm->{t}\n"); }
  if ($tsm->{v0} != 1.2)       { $success = 0; main::Debug("unweighed moving holdTime test failed: first value mismatch $tsm->{v0}/1.2\n"); }
  if ($tsm->{v} != 0.8)        { $success = 0; main::Debug("unweighed moving holdTime test failed: last value mismatch $tsm->{v}/0.8\n"); }
  if ($tsm->{min} != 0.8)      { $success = 0; main::Debug("unweighed moving holdTime test failed: min mismatch $tsm->{min}/0.8\n"); }
  if ($tsm->{max} != 1.2)      { $success = 0; main::Debug("unweighed moving holdTime test failed: max mismatch $tsm->{max}/1.2\n"); }
  if ($tsm->{mean} != 1.0)     { $success = 0; main::Debug("unweighed moving holdTime test failed: mean mismatch $tsm->{mean}/1.0\n"); }
  if (!defined($tsm->{sd}) || $tsm->{sd} ne sqrt(0.13/2)) { $success = 0; main::Debug("unweighed moving holdTime test failed: sd mismatch $tsm->{sd}/0.254950975679639\n"); }
  if ($tsm->{integral} != 3.0) { $success = 0; main::Debug("unweighed moving holdTime test failed: sum mismatch $tsm->{integral}/3.0\n"); }
  if ($tsm->{median} != 1.0)   { $success = 0; main::Debug("unweighed block autoreset test failed: median mismatch $tsm->{median}/1.0\n"); }

  $tsm->reset();
  $tsm->{method} = 'const';
  $tsm->{holdTime} = 5;
  $now = time();
  $tsm->add($now-4,  1.0);
  $tsm->add($now-3,  2.0);
  $tsm->add($now-1, -1.0);
  if ($tsm->{count} != 3)      { $success = 0; main::Debug("const weighed moving add test 1 failed: count mismatch $tsm->{count}/3\n"); }
  if ($tsm->{lost} != 0)       { $success = 0; main::Debug("const weighed moving add test 1 failed: lost mismatch $tsm->{lost}/0\n"); }
  if ($tsm->{n} != 2)          { $success = 0; main::Debug("const weighed moving add test 1 failed: n mismatch $tsm->{n}/2\n"); }
  if ($tsm->{t0} != ($now-4))  { $success = 0; main::Debug("const weighed moving add test 1 failed: first time mismatch $tsm->{t0}\n"); }
  if ($tsm->{t} != ($now-1))   { $success = 0; main::Debug("const weighed moving add test 1 failed: last time mismatch $tsm->{t}\n"); }
  if ($tsm->{v0} != 1.0)       { $success = 0; main::Debug("const weighed moving add test 1 failed: first value mismatch $tsm->{v0}/1.0\n"); }
  if ($tsm->{v} != -1.0)       { $success = 0; main::Debug("const weighed moving add test 1 failed: last value mismatch $tsm->{v}/-1.0\n"); }
  if ($tsm->{min} != -1.0)     { $success = 0; main::Debug("const weighed moving add test 1 failed: min mismatch $tsm->{min}/-1.0\n"); }
  if ($tsm->{max} != 2.0)      { $success = 0; main::Debug("const weighed moving add test 1 failed: max mismatch $tsm->{max}/2.0\n"); }
  if ($tsm->{mean} ne (2.5/1.5)) { $success = 0; main::Debug("const weighed moving add test 1 failed: mean mismatch $tsm->{mean}/1.66666666666667\n"); }
  if (!defined($tsm->{sd}) || $tsm->{sd} ne 2) { $success = 0; main::Debug("const weighed moving add test 1 failed: sd mismatch $tsm->{sd}/2\n"); }
  if ($tsm->{integral} != 5.0) { $success = 0; main::Debug("const weighed moving add test 1 failed: sum mismatch $tsm->{integral}/5.0\n"); }
  $tsm->add($now,    0.5);
  if ($tsm->{count} != 4)      { $success = 0; main::Debug("const weighed moving add test 2 failed: count mismatch $tsm->{count}/4\n"); }
  if ($tsm->{lost} != 0)       { $success = 0; main::Debug("const weighed moving add test 2 failed: lost mismatch $tsm->{lost}/0\n"); }
  if ($tsm->{n} != 3)          { $success = 0; main::Debug("const weighed moving add test 2 failed: n mismatch $tsm->{n}/3\n"); }
  if ($tsm->{t0} != ($now-4))  { $success = 0; main::Debug("const weighed moving add test 2 failed: first time mismatch $tsm->{t0}\n"); }
  if ($tsm->{t} != ($now))     { $success = 0; main::Debug("const weighed moving add test 2 failed: last time mismatch $tsm->{t}\n"); }
  if ($tsm->{v0} != 1.0)       { $success = 0; main::Debug("const weighed moving add test 2 failed: first value mismatch $tsm->{v0}/1.0\n"); }
  if ($tsm->{v} != 0.5)        { $success = 0; main::Debug("const weighed moving add test 2 failed: last value mismatch $tsm->{v}/0.5\n"); }
  if ($tsm->{min} != -1.0)     { $success = 0; main::Debug("const weighed moving add test 2 failed: min mismatch $tsm->{min}/-1.0\n"); }
  if ($tsm->{max} != 2.0)      { $success = 0; main::Debug("const weighed moving add test 2 failed: max mismatch $tsm->{max}/2.0\n"); }
  if ($tsm->{mean} != 1)       { $success = 0; main::Debug("const weighed moving add test 2 failed: mean mismatch $tsm->{mean}/1\n"); }
  if (!defined($tsm->{sd}) || $tsm->{sd} ne sqrt(21.25/2)*3/4) { $success = 0; main::Debug("const weighed moving add test 2 failed: sd mismatch $tsm->{sd}/2.44470090195099\n"); }
  if ($tsm->{integral} != 4.0) { $success = 0; main::Debug("const weighed moving add test 2 failed: sum mismatch $tsm->{integral}/4.0\n"); }  
  
  # get value tests
  if ($tsm->getValue($now-4) ne 1.0) { $success = 0; main::Debug("getValue test failed: first value mismatch ".$tsm->getValue($now-4)."/1.0\n"); }
  if ($tsm->getValue($now-3) ne 2.0) { $success = 0; main::Debug("getValue test failed: exact value mismatch ".$tsm->getValue($now-3)."/2.0\n"); }
  if ($tsm->getValue($now-2) ne 2.0) { $success = 0; main::Debug("getValue test failed: before value mismatch ".$tsm->getValue($now-2)."/2.0\n"); }
  if ($tsm->getValue($now) ne 0.5) { $success = 0; main::Debug("getValue test failed: last value mismatch ".$tsm->getValue($now)."/0.5\n"); }
  if (defined($tsm->getValue($now+1))) { $success = 0; main::Debug("getValue test failed: out of range value mismatch ".$tsm->getValue($now+1)."/undef\n"); }
  
  if ($success) {
    return "selftest passed";
  } else {
    return "selftest failed, see log for details";
  }
}

1;  


=pod

B<TimeSeries> is a perl module to feed time/value data points and get some statistics on them as you go:

  my $ts= TimeSeries->new( { method => "const" } );
  $ts->add(3.3, 2.1);
  $ts->add(5.1, 1.8);
  $ts->add(8.8, 2.4);
  printf("count= %d, n= %d, lost= %d, first= %f, last= %f, min= %f, max= %f, mean= %f, sd= %f\n", 
      $ts->{count}, $ts->{n}, $ts->{lost}, $ts->{v0}, $ts->{v},
      $ts->{min}, $ts->{max},
      $ts->{mean}, $ts->{sd}
      );
      
  Mean, standard deviation and integral calculation also depends on the property method. You may choose from
  none (no time weighting), const (time weighted, step) or linear (time weighted, linear interpolation).
  
  The statistics may be reset manually using
  $ts->reset();
  
  By defining autoreset, the reset will occur automatically when the specified duration (seconds)
  is accumulated. 
  
  If alternatively holdTime is defined, all data points are kept in a time limited data buffer that is
  re-evaluated each time a data point is added. Note that this may require significant amounts
  of memory depending on the sample rate and the holdTime.
  
  If method is none and holdtime is defined then the median of the values will be calculated additionally.
      
  It is also possible to define autoreset and holdtime at the same time. In this case the data buffer 
  is enabled and will be cleared each time an autoreset occurs, independent of the value of holdtime.
      
=cut
