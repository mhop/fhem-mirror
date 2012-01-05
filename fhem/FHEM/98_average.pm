##############################################
# $Id$
# Avarage computing

package main;
use strict;
use warnings;

##########################
sub
average_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "average_Define";
  $hash->{NotifyFn} = "average_Notify";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1";
}


##########################
sub
average_Define($$$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $re, $rest) = split("[ \t]+", $def, 4);

  if(!$re || $rest) {
    my $msg = "wrong syntax: define <name> average device[:event]";
    return $msg;
  }

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$re$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $re;
  $hash->{STATE} = "active";
  return undef;
}

##########################
sub
average_Notify($$)
{
  my ($avg, $dev) = @_;
  my $avgName = $avg->{NAME};

  return "" if(AttrVal($avgName, "disable", undef));

  my $devName = $dev->{NAME};
  my $re = $avg->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $tn;
  my $myIdx = $max;

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];

    ################
    # Filtering
    next if(!defined($s));
    my ($evName, $val) = split(" ", $s, 2); # resets $1
    next if($devName !~ m/^$re$/ && "$devName:$s" !~ m/^$re$/ || $s =~ m/_avg_/);
    if(defined($1)) {
      my $reArg = $1;
      $val = $reArg if(defined($reArg) && $reArg =~ m/^(-?\d+\.?\d*)/);
    }
    next if(!defined($val) || $val !~ m/^(-?\d+\.?\d*)/);
    $val = $1;

    ################
    # Avg computing
    $evName =~ s/[^A-Za-z_-].*//;
    $tn = TimeNow() if(!$tn);

    my $r = $dev->{READINGS};
    my @dNow = split("[ :-]", $tn);

    for(my $idx = 0; $idx <= 1; $idx++) {

      my $secNow = 3600*$dNow[3] + 60*$dNow[4] + $dNow[5];
      $secNow += $dNow[2]*86400 if($idx);

      my $cumName = "${evName}_cum_" . ($idx ? "month" : "day");
      my $avgName = "${evName}_avg_" . ($idx ? "month" : "day");

      if(!$r->{$cumName}) {
        $r->{$cumName}{VAL} = $secNow*$val;
        $r->{$avgName}{VAL} = $val;
        $r->{$cumName}{TIME} = $r->{$avgName}{TIME} = $tn;
        next;
      }

      my @dLast = split("[ :-]", $r->{$cumName}{TIME});
      my $secLast = 3600*$dLast[3] + 60*$dLast[4] + $dLast[5];
      $secLast += $dLast[2]*86400 if($idx);

      if($idx == 0 && ($dLast[2] == $dNow[2]) ||
         $idx == 1 && ($dLast[1] == $dNow[1])) {
        my $cum = $r->{$cumName}{VAL} + ($secNow-$secLast) * $val;
        $r->{$cumName}{VAL} = $cum;
        $r->{$avgName}{VAL} = sprintf("%0.1f", $cum/$secNow);
      } else {
        $dev->{CHANGED}[$myIdx++] = "$avgName:".$r->{$avgName}{VAL};
        $r->{$cumName}{VAL} = $secNow*$val;
        $r->{$avgName}{VAL} = $val;

      }
      $r->{$cumName}{TIME} = $r->{$avgName}{TIME} = $tn;
    }
  }
  return undef;
}

1;
