##############################################
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

  $hash->{AttrList}  = "dummy:1,0 model;M232Counter loglevel:0,1,2,3,4,5";
}

###################################
sub
M232Counter_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "M232Counter_GetStatus", $hash);
  }

  my $name = $hash->{NAME};

  my $d = IOWrite($hash, "z");
  if(!defined($d)) {
    my $msg = "M232Counter $name read error";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my $tn = TimeNow();
  if(!defined($hash->{READINGS}{basis})) {
	$hash->{READINGS}{basis}{VAL}= 0;
	$hash->{READINGS}{basis}{TIME}= $tn;
  }
  if(!defined($hash->{READINGS}{count})) {
	$hash->{READINGS}{count}{VAL}= 0;
	$hash->{READINGS}{count}{TIME}= $tn;
  }
  my $count= hex $d;
  if($count< $hash->{READINGS}{count}{VAL}) {
	$hash->{READINGS}{basis}{VAL}+= 65536;
	$hash->{READINGS}{basis}{TIME}= $tn;
  }
  my $value= ($hash->{READINGS}{basis}{VAL}+$count) * $hash->{FACTOR};

  $hash->{READINGS}{count}{TIME} = $tn;
  $hash->{READINGS}{count}{VAL} = $count;
  $hash->{READINGS}{value}{TIME} = $tn;
  $hash->{READINGS}{value}{VAL} = $value;

  $hash->{CHANGED}[0]= "value: $value";

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
  my $u = "Usage: set <name> value <value>";

  return $u if(int(@a) != 3);
  my $reading= $a[1];
  my $value = $a[2];
  return $u unless($reading eq "value");

  my $rm= M232Counter_Calibrate($hash, $value);

  return undef;
}


#############################
sub
M232Counter_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> M232Counter [unit] [multiplicator]"
    if(int(@a) < 2 && int(@a) > 4);

  my $unit= ((int(@a) > 2) ? $a[2] : "ticks");
  my $factor= ((int(@a) > 3) ? $a[3] : 1.0);
  $hash->{UNIT}= $unit;
  $hash->{FACTOR}= $factor;

  AssignIoPort($hash);

  # InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+60, "M232Counter_GetStatus", $hash);
  }

  $init_done = $oid;
  return undef;
}

1;
