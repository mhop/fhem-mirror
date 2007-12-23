##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub EMGZ_Get($@);
sub EMGZ_Set($@);
sub EMGZ_Define($$);
sub EMGZ_GetStatus($);

###################################
sub
EMGZ_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "EMGZ_Get";
  $hash->{SetFn}     = "EMGZ_Set";
  $hash->{DefFn}     = "EMGZ_Define";

  $hash->{AttrList}  = "dummy:1,0 model;EM1000GZ loglevel:0,1,2,3,4,5,6";
}


###################################
sub
EMGZ_GetStatus($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+300, "EMGZ_GetStatus", $hash, 0);
  }

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};

  return "Empty status: dummy IO device" if(IsIoDummy($name));

  my $d = IOWrite($hash, sprintf("7a%02x", $dnr-1));
  if(!defined($d)) {
    my $msg = "EMGZ $name read error (GetStatus 1)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }


  if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6)) {
    my $msg = "EMGZ no device no. $dnr present";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my $pulses=w($d,13);
  my $ec=w($d,49) / 10;
  if($ec < 0) {					# war <=
    my $msg = "EMGZ read error (GetStatus 2)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  $ec = 100; 	# fixed value
 
  my $cur_energy = $pulses / $ec;       # ec = U/m^3
  my $cur_power = $cur_energy / 5 * 60; # 5minute interval scaled to 1h

  if($cur_power > 30) { 		# depending on "Anschlussleistung" 
    my $msg = "EMGZ Bogus reading: curr. power is reported to be $cur_power";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  my %vals;
  $vals{"5min_pulses"} = $pulses;
  $vals{"act_flow_m3"} = sprintf("%0.3f", $cur_energy);
  $vals{"m3ph"} = sprintf("%.3f", $cur_power);
  $vals{"alarm_PA"} = w($d,45) . " Watt";		# nonsens
  $vals{"price_CF"} = sprintf("%.3f", w($d,47)/10000);
  $vals{"Rperm3_EC"} = $ec;

  my $tn = TimeNow();
  my $idx = 0;
  foreach my $k (keys %vals) {
    my $v = $vals{$k};
    $hash->{CHANGED}[$idx++] = "$k: $v";
    $hash->{READINGS}{$k}{TIME} = $tn;
    $hash->{READINGS}{$k}{VAL} = $v
  }

  if(!$hash->{LOCAL}) {
    DoTrigger($name, undef) if($init_done);
  }

  $hash->{STATE} = "$cur_power m3ph";
  Log GetLogLevel($name,4), "EMGZ $name: $cur_power m3ph / $vals{act_flow_m3}";

  return $hash->{STATE};
}

###################################
sub
EMGZ_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  my $v = EMGZ_GetStatus($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => $v";
}

sub
EMGZ_Set($@)
{
  my ($hash, @a) = @_;
  my $u = "Usage: set <name> <type> <value>, " .
                "<type> is one of price,alarm,rperkw";

  return $u if(int(@a) != 3);

  my $name = $hash->{NAME};
  return "" if(IsIoDummy($name));

  my $v = $a[2];
  my $d = $hash->{DEVNR};
  my $msg;

  if($a[1] eq "price") {
    $v *= 10000; # Make display and input the same
    $msg = sprintf("79%02x2f02%02x%02x", $d-1, $v%256, int($v/256));
  } elsif($a[1] eq "alarm") {
    $msg = sprintf("79%02x2d02%02x%02x", $d-1, $v%256, int($v/256));
  } elsif($a[1] eq "rperkw") {
    $v *= 10; # Make display and input the same
    $msg = sprintf("79%02x3102%02x%02x", $d-1, $v%256, int($v/256));
  } else {
    return $u;
  }


  my $ret = IOWrite($hash, $msg);
  if(!defined($ret)) {
    my $msg = "EMWZ $name read error (Set)";
    Log GetLogLevel($name,2), $msg;
    return $msg;
  }

  if(ord(substr($ret,0,1)) != 6) {
    $ret = "EMGZ Error occured: " .  unpack('H*', $ret);
    Log GetLogLevel($name,2), $ret;
    return $ret;
  }

  return undef;
}

#############################
sub
EMGZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> EMGZ devicenumber"
    if(@a != 3 || $a[2] !~ m,^[9]$,);
  $hash->{DEVNR} = $a[2];
  AssignIoPort($hash);


  EMGZ_GetStatus($hash);
  return undef;
}

1;
