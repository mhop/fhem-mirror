#
#
# 81_M232Counter.pm
# written by Dr. Boris Neubert 2007-11-26
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub M232Counter_Get($@);
sub M232Counter_Set($@);
sub M232Counter_SetBasis($@);
sub M232Counter_Define($$);
sub M232Counter_GetStatus($);

###################################
sub
M232Counter_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "M232Counter_Get";
  $hash->{SetFn}     = "M232Counter_Set";
  $hash->{DefFn}     = "M232Counter_Define";

  $hash->{AttrList}  = "dummy:1,0 model:M232Counter loglevel:0,1,2,3,4,5";
}

###################################
sub
M232Counter_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "M232Counter_GetStatus", $hash, 1);
  }

  my $name = $hash->{NAME};
  my $r= $hash->{READINGS};

  my $d = IOWrite($hash, "z");
  if(!defined($d)) {
    my $msg = "M232Counter $name tick count read error";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  # time
  my $tn = TimeNow();

  #tsecs
  my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC

  # previous tsecs
  my $tsecs_prev;
  if(defined($r->{tsecs})) {
      $tsecs_prev= $r->{tsecs}{VAL};
  } else{
      $tsecs_prev= $tsecs; # 1970-01-01
  }

  # basis
  my $basis;
  if(defined($r->{basis})) {
	$basis= $r->{basis}{VAL};
  } else {
        $basis= 0;
  }
  my $basis_prev= $basis;


  # previous count (this variable is currently unused)
  my $count_prev;
  if(defined($r->{count})) {
	$count_prev= $r->{count}{VAL};
  } else {
        $count_prev= 0;
  }

  # current count
  my $count= hex $d;
  # If the counter reaches 65536, the counter does not wrap around but
  # stops at 0. We therefore purposefully reset the counter to 0 before
  # it reaches its final tick count.
  if($count > 64000) {
    $basis+= $count;
    $count= 0;
    $r->{basis}{VAL} = $basis;
    $r->{basis}{TIME}= $tn;
    my $ret = IOWrite($hash, "Z1");
    if(!defined($ret)) {
      my $msg = "M232Counter $name reset error";
      Log GetLogLevel($name,2), $msg;
      return $msg;
    }
  }

  # previous value
  my $value_prev;
  if(defined($r->{value})) {
        $value_prev= $r->{value}{VAL};
  } else {
        $value_prev= 0;
  }

  # current value
  my $value= ($basis+$count) * $hash->{FACTOR};
  # round to 3 digits
  $value= int($value*1000.0+0.5)/1000.0;

  # set new values
  $r->{count}{TIME} = $tn;
  $r->{count}{VAL} = $count;
  $r->{value}{TIME} = $tn;
  $r->{value}{VAL} = $value;
  $r->{tsecs}{TIME} = $tn;
  $r->{tsecs}{VAL} = $tsecs;

  $hash->{CHANGED}[0]= "count: $count";
  $hash->{CHANGED}[1]= "value: $value";

  # delta
  my $tsecs_delta= $tsecs-$tsecs_prev;
  my $count_delta= ($count+$basis)-($count_prev+$basis_prev);
  if($tsecs_delta>0) {
    my $delta= ($count_delta/$tsecs_delta)*$hash->{DELTAFACTOR};
    # round to 3 digits
    $delta= int($delta*1000.0+0.5)/1000.0;
    $r->{delta}{TIME} = $tn;
    $r->{delta}{VAL} = $delta;
    $hash->{CHANGED}[2]= "delta: $delta";
  }


  if(!$hash->{LOCAL}) {
    DoTrigger($name, undef) if($init_done);
  }

  $hash->{STATE} = $value;
  Log GetLogLevel($name,4), "M232Counter $name: $value $hash->{UNIT}";

  return $hash->{STATE};
}

###################################
sub
M232Counter_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = M232Counter_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

#############################
sub
M232Counter_Calibrate($@)
{
  my ($hash, $value) = @_;
  my $rm= undef;
  my $name = $hash->{NAME};


  # adjust basis
  my $tn = TimeNow();
  $hash->{READINGS}{basis}{VAL}= $value / $hash->{FACTOR};
  $hash->{READINGS}{basis}{TIME}= $tn;
  $hash->{READINGS}{count}{VAL}= 0;
  $hash->{READINGS}{count}{TIME}= $tn;

  # recalculate value
  $hash->{READINGS}{value}{VAL} = $value;
  $hash->{READINGS}{value}{TIME} = $tn;

  # reset counter
  my $ret = IOWrite($hash, "Z1");
  if(!defined($ret)) {
    my $rm = "M232Counter $name read error";
    Log GetLogLevel($name,2), $rm;
  }

  return $rm;
}

#############################
sub
M232Counter_Set($@)
{
  my ($hash, @a) = @_;
  my $u = "Usage: set <name> value <value>\n" .
                 "set <name> interval <seconds>\n" ;

  return $u if(int(@a) != 3);
  my $reading= $a[1];

  if($a[1] eq "value") {
      my $value= $a[2];
      my $rm= M232Counter_Calibrate($hash, $value);
  } elsif($a[1] eq "interval") {
      my $interval= $a[2];
      $hash->{INTERVAL}= $interval;
  } else {
      return $u;
  }

  return undef;
}


#############################
sub
M232Counter_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> M232Counter [unit] [factor] [deltaunit] [deltafactor]"
    if(int(@a) < 2 && int(@a) > 6);

  my $unit= ((int(@a) > 2) ? $a[2] : "ticks");
  my $factor= ((int(@a) > 3) ? $a[3] : 1.0);
  my $deltaunit= ((int(@a) > 4) ? $a[4] : "ticks per second");
  my $deltafactor= ((int(@a) > 5) ? $a[5] : 1.0);
  $hash->{UNIT}= $unit;
  $hash->{FACTOR}= $factor;
  $hash->{DELTAUNIT}= $deltaunit;
  $hash->{DELTAFACTOR}= $deltafactor;
  $hash->{INTERVAL}= 60; # poll every minute per default

  AssignIoPort($hash);

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "M232Counter_GetStatus", $hash, 0);
  }
  return undef;
}

1;
