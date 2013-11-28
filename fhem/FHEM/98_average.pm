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
# Log 1,"mytestavg pre-filter: ".$devName.$evName." s=".$s; 
    next if($devName !~ m/^$re$/ && "$devName:$s" !~ m/^$re$/ || $s =~ m/_avg_/);
    if(defined($1)) {
      my $reArg = $1;
      $val = $reArg if(defined($reArg) && $reArg =~ m/^(-?\d+\.?\d*)/);
    }
    next if(!defined($val) || $val !~ m/^(-?\d+\.?\d*)/);
    $val = $1;

# Log 1,"mytestavg pst-filter: ".$devName.$evName." val=".$val; 

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
      my $minName = "${evName}_min_" . ($idx ? "month" : "day"); ##MH
      my $maxName = "${evName}_max_" . ($idx ? "month" : "day"); ##MH

      if(!$r->{$cumName}) {
        $r->{$cumName}{VAL} = $secNow*$val;
        $r->{$avgName}{VAL} = $val;
        $r->{$maxName}{VAL} = $val; ##MH
        $r->{$minName}{VAL} = $val; ##MH
        $r->{$cumName}{TIME} = $r->{$avgName}{TIME} = $tn;
        next;
      }

      ##MH take care of existing average definitions - just add this one..
      if(!$r->{$maxName}) {
        $r->{$maxName}{VAL} = $val;
        $r->{$maxName}{TIME} = $tn; 
      }
      ##MH take care of existing average definitions - just add this one..
      if(!$r->{$minName}) {
        $r->{$minName}{VAL} = $val;
        $r->{$minName}{TIME} = $tn; 
      }

      my @dLast = split("[ :-]", $r->{$cumName}{TIME});
      my $secLast = 3600*$dLast[3] + 60*$dLast[4] + $dLast[5];
      $secLast += $dLast[2]*86400 if($idx);

      if($idx == 0 && ($dLast[2] == $dNow[2]) ||
         $idx == 1 && ($dLast[1] == $dNow[1])) {
        my $cum = $r->{$cumName}{VAL} + ($secNow-$secLast) * $val;
        $r->{$cumName}{VAL} = $cum;
        $r->{$avgName}{VAL} = sprintf("%0.1f", $cum/$secNow);
        ##MH change only if current value bigger than maxvalue
        if($r->{$maxName}{VAL} < $val) {
          $r->{$maxName}{VAL} = sprintf("%0.1f", $val); ##MH
          $r->{$maxName}{TIME} = $tn; ##MH
        }

        ##MH change only if current value smaller than minvalue
        if($r->{$minName}{VAL} > $val) {
          $r->{$minName}{VAL} = sprintf("%0.1f", $val); ##MH
          $r->{$minName}{TIME} = $tn; ##MH
        }
      } else {
        $dev->{CHANGED}[$myIdx++] = "$avgName: ".$r->{$avgName}{VAL};
        $dev->{CHANGED}[$myIdx++] = "$maxName: ".$r->{$maxName}{VAL}; ##MH
        $dev->{CHANGED}[$myIdx++] = "$minName: ".$r->{$minName}{VAL}; ##MH
        $r->{$cumName}{VAL} = $secNow*$val;
        $r->{$avgName}{VAL} = $val;

        ##MH set to current value
        $r->{$maxName}{VAL} = sprintf("%0.1f", $val); ##MH
        $r->{$maxName}{TIME} = $tn; ##MH
        $r->{$minName}{VAL} = sprintf("%0.1f", $val); ##MH
        $r->{$minName}{TIME} = $tn; ##MH
      }
      $r->{$cumName}{TIME} = $r->{$avgName}{TIME} = $tn;
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
      and generates events of the form
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_day: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_day: &lt;minimum day value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_day: &lt;maximum day value&gt;
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

      at the beginning of the next day or month respectively.<br>
      The current average, minimum, maximum and the cumulated values are stored
      in the device readings.
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

    # Hunt only for the humidity: take the value from the first
    # parenthesis ($1 in perl regexp) if it is a number
    # Event: ws1 T: 52.3  H: 67.4
    define avg_temp_ws1 average ws1:.*H:.([-\d\.]+)
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
  </ul>

  <a name="averageevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>&lt;eventname&gt;_avg_day: $avg_day
    <li>&lt;eventname&gt;_avg_month: $avg_month
    <li>&lt;eventname&gt;_min_day: $min_day
    <li>&lt;eventname&gt;_min_month: $min_month
    <li>&lt;eventname&gt;_max_day: $max_day
    <li>&lt;eventname&gt;_max_month: $max_month
  </ul>
</ul>


=end html
=cut
