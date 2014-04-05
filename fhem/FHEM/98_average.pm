##############################################
# $Id$
# Average computing

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
  $hash->{AttrList} = "disable:0,1 " .
                      "disabledForIntervals " .
                      "computeMethod:integral,counter " .
                      "noaverage:0,1 " .
                      "nominmax:0,1 " .
                      "floatformat:%0.1f,%0.2f";
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


sub
avg_setValTime($$$$)
{
  my ($r, $rname, $val, $tn) = @_;
  $r->{$rname}{VAL} = $val;
  $r->{$rname}{TIME} = $tn; 
}
##########################
sub
average_Notify($$)
{
  my ($avg, $dev) = @_;
  my $myName = $avg->{NAME};

  return "" if(IsDisabled($myName));

  my $devName = $dev->{NAME};
  my $re = $avg->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $tn;
  my $myIdx = $max;

  my $doCounter = (AttrVal($myName, "computeMethod", "integral") eq "counter");
  my $doMMx  = (AttrVal($myName, "nominmax", "0") eq "0");
  my $doAvg  = (AttrVal($myName, "noaverage", "0") eq "0");
  my $ffmt   =  AttrVal($myName, "floatformat", "%0.1f");
  my $r = $dev->{READINGS};
  
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];

    ################
    # Filtering
    next if(!defined($s));
    my ($evName, $val) = split(" ", $s, 2); # resets $1
    next if($devName !~ m/^$re$/ && "$devName:$s" !~ m/^$re$/ ||
            $s =~ m/(_avg_|_cum_|_min_|_max_|_cnt_)/);
    if(defined($1)) {
      my $reArg = $1;
      if(defined($2)) {
        $evName = $1;
        $reArg = $2;
      }
      $val = $reArg if(defined($reArg) && $reArg =~ m/^(-?\d+\.?\d*)/);
    }
    next if(!defined($val) || $val !~ m/^(-?\d+\.?\d*)/);
    $val = $1;

    ################
    # Avg computing
    $evName =~ s/[^A-Za-z_-].*//;
    $tn = TimeNow() if(!$tn);

    my @dNow = split("[ :-]", $tn);

    for(my $idx = 0; $idx <= 1; $idx++) { # 0:day 1:month

      my $secNow = 3600*$dNow[3] + 60*$dNow[4] + $dNow[5];
      $secNow += $dNow[2]*86400 if($idx);

      my $cumName = "${evName}_cum_" . ($idx ? "month" : "day");
      my $avgName = "${evName}_avg_" . ($idx ? "month" : "day");
      my $minName = "${evName}_min_" . ($idx ? "month" : "day");
      my $maxName = "${evName}_max_" . ($idx ? "month" : "day");
      my $cntName = "${evName}_cnt_" . ($idx ? "month" : "day");

      if($doCounter && !defined($r->{$cntName})) {
        avg_setValTime($r, $cntName, 1, $tn);
        delete $r->{$cumName};         # Reset when switching to counter-mode
        delete $r->{$avgName};
      }
  
      if($doMMx && (!defined($r->{$maxName}) || !defined($r->{$minName}))) {
        avg_setValTime($r, $maxName, $val, $tn);
        avg_setValTime($r, $minName, $val, $tn);
      }

      if(!defined($r->{$cumName}) || ($doAvg && !defined($r->{$avgName}))) {
        my $cum = ($doCounter ? $val : $secNow*$val);
        avg_setValTime($r, $cumName, $cum, $tn);
        avg_setValTime($r, $avgName, $val, $tn) if ($doAvg);
        next;
      }
  
      my @dLast = split("[ :-]", $r->{$cumName}{TIME});
      my $secLast = 3600*$dLast[3] + 60*$dLast[4] + $dLast[5];
      $secLast += $dLast[2]*86400 if($idx);

      if($idx == 0 && ($dLast[2] == $dNow[2]) ||
         $idx == 1 && ($dLast[1] == $dNow[1])) {         # same day or month

        my $cVal = $r->{$cumName}{VAL};
        $cVal += ($doCounter ? $val : ($secNow-$secLast) * $val);
        avg_setValTime($r, $cumName, $cVal, $tn);

        if($doAvg) {
          my $div = ($secNow ? $secNow : 1);
          if($doCounter) {
            $div = $r->{$cntName}{VAL}+1;
            avg_setValTime($r, $cntName, $div, $tn);
          }
          my $lVal = sprintf($ffmt, $r->{$cumName}{VAL}/$div);
          avg_setValTime($r, $avgName, $lVal, $tn);
        }

        if($doMMx) {
          avg_setValTime($r, $maxName, sprintf($ffmt,$val), $tn)
                if($r->{$maxName}{VAL} < $val);
          avg_setValTime($r, $minName, sprintf($ffmt,$val), $tn)
                if($r->{$minName}{VAL} > $val);
        }

      } else {           # day or month changed: create events and reset values

        if($doAvg) {
          $dev->{CHANGED}[$myIdx++] = "$avgName: ".$r->{$avgName}{VAL};
          avg_setValTime($r, $cumName, $secNow*$val, $tn);
          avg_setValTime($r, $avgName, $val, $tn);
        }

        if($doCounter) {
          $dev->{CHANGED}[$myIdx++] = "$cumName: ".$r->{$cumName}{VAL};
          avg_setValTime($r, $cumName, 0, $tn);
          avg_setValTime($r, $cntName, 0, $tn) if($doAvg);

        } else {
          avg_setValTime($r, $cumName, $secNow*$val, $tn);

        }

        if($doMMx) {
          $dev->{CHANGED}[$myIdx++] = "$maxName: ".$r->{$maxName}{VAL};
          $dev->{CHANGED}[$myIdx++] = "$minName: ".$r->{$minName}{VAL};
          avg_setValTime($r, $maxName, sprintf($ffmt, $val), $tn);
          avg_setValTime($r, $minName, sprintf($ffmt, $val), $tn);
        }
      }
    }
  }
  return undef;
}

1;


=pod
=begin html

<a name="average"></a>
<h3>average</h3>
<ul>

  Compute additional average, minimum and maximum values for current day and
  month.

  <br>

  <a name="averagedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; average &lt;regexp&gt;</code><br>
    <br>
    <ul>
      The syntax for &lt;regexp&gt; is the same as the
      regexp for <a href="#notify">notify</a>.<br>
      If it matches, and the event is of the form "eventname number", then this
      module computes the daily and monthly average, maximum and minimum values
      and sums depending on attribute settings and generates events of the form
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_day: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_day: &lt;minimum day value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_day: &lt;maximum day value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_day: &lt;sum of the values during the day&gt;
      </ul>
      and
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_month: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_month: &lt;minimum month value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_month: &lt;maximum month value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_month: &lt;sum of the values during the month&gt;
      </ul>

      at the beginning of the next day or month respectively depending on attributes defined.<br>
      The current average, minimum, maximum and the cumulated values are stored
      in the device readings depending on attributes defined.
    </ul>
    <br>

    Example:<PRE>
    # Compute the average, minimum and maximum for the temperature events of
    # the ws1 device
    define avg_temp_ws1 average ws1:temperature.*

    # Compute the average, minimum and maximum for each temperature event
    define avg_temp_ws1 average .*:temperature.*

    # Compute the average, minimum and maximum for all temperature and humidity events
    # Events:
    # ws1 temperature: 22.3
    # ws1 humidity: 67.4
    define avg_temp_ws1 average .*:(temperature|humidity).*

    # Compute the same from a combined event. Note: we need two average
    # definitions here, each of them defining the name with the first
    # paranthesis, and the value with the second.
    # 
    # Event: ws1 T: 52.3  H: 67.4
    define avg_temp_ws1_t average ws1:(T):.([-\d\.]+).*
    define avg_temp_ws1_h average ws1:.*(H):.([-\d\.]+).*
    </PRE>
  </ul>

  <a name="averageset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="averageget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="averageattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li>computeMethod</li>
      defines how values are added up for the average calculation. This
      attribute can be set to integral or counter.
      The integral mode is meant for measuring continuous values like
      temperature, counter is meant for adding up values, e.g. from a
      feeding unit. In the first case, the time between the events plays an
      important role, in the second case not. Default is integral.
    <li>nominmax</li>
      don't compute min and max values. Default is 0 (compute min & max).
    <li>noaverage</li>
      don't compute average values. Default is 0 (compute avarage).
  </ul>

  <a name="averageevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>&lt;eventname&gt;_avg_day: $avg_day</li>
    <li>&lt;eventname&gt;_avg_month: $avg_month</li>
    <li>&lt;eventname&gt;_cum_day: $cum_day (only if cumtype is set to raw)</li>
    <li>&lt;eventname&gt;_cum_month: $cum_month (only if cumtype is set to raw)</li>
    <li>&lt;eventname&gt;_min_day: $min_day</li>
    <li>&lt;eventname&gt;_min_month: $min_month</li>
    <li>&lt;eventname&gt;_max_day: $max_day</li>
    <li>&lt;eventname&gt;_max_month: $max_month</li>
  </ul>
</ul>


=end html
=cut
