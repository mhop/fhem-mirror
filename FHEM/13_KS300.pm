##############################################
# $Id$
package main;

use strict;
use warnings;


#####################################
sub
KS300_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # 810d04f94027a00171212730000008
  # 81 0d 04 f9 4027a00171 212730000008

  $hash->{Match}     = "^810d04..4027a001";
  $hash->{DefFn}     = "KS300_Define";
  $hash->{UndefFn}   = "KS300_Undef";
  $hash->{ParseFn}   = "KS300_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 model:ks300 loglevel:0,1 rainadjustment:0,1 ignore:0,1";
}

#####################################
sub
KS300_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> KS300 <code> " .
          "[ml/raincounter] [wind-factor]" if(int(@a) < 3 || int(@a) > 5);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
                if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);

  $hash->{CODE} = $a[2];
  my $rainunit = ((int(@a) > 3) ? $a[3] : 255);
  my $windunit = ((int(@a) > 4) ? $a[4] : 1.0);
  $hash->{CODE} = $a[2];
  $hash->{RAINUNIT} = $rainunit;
  $hash->{WINDUNIT} = $windunit;
  $modules{KS300}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
KS300_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{KS300}{defptr}{$hash->{CODE}});
  return undef;
}


#####################################
sub
KS300_Parse($$)
{
  my ($hash,$msg) = @_;

  ###############################
  #          1          2
  #0123456789012345 67890123456789
  #
  #810d04f94027a001 71212730000008
  ###############################
  my @a = split("", $msg);

  ##########################
  # I've seldom (1 out of 700) seen messages of length 10 and 11 with correct
  # CRC, they seem to contain partial data (e.g. temp/wind/hum but not rain)
  # They are suppressed as of now.
  if(hex($a[3]) != 13) {
    Log 4, "Strange KS300 message received, won't decode ($msg)";
    return "";
  }

  if(int(keys %{ $modules{KS300}{defptr} })) {

    my @arr = keys(%{ $modules{KS300}{defptr} }); # No code is known yet
    my $dev = shift(@arr);
    my $def = $modules{KS300}{defptr}{$dev};
    my $haverain = 0;
    my $name= $def->{NAME};
    return "" if(IsIgnored($name));

    my @v;
    my @txt = ( "rain_raw", "rain", "wind", "humidity", "temperature",
                "israining", "unknown1", "unknown2", "unknown3");
    my @sfx = ( "(counter)", "(l/m2)", "(km/h)", "(%)", "(Celsius)",
                "(yes/no)", "","","");
    my %repchanged = ("rain"=>1, "wind"=>1, "humidity"=>1, "temperature"=>1,
                "israining"=>1);

    # counter for the change hash
    my $n= 1; # 0 is STATE and will b explicitely set

    # time
    my $tm = TimeNow();
    my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC

    # The next instr wont work for empty hashes, so we init it now
    $def->{READINGS}{$txt[0]}{VAL} = 0 if(!$def->{READINGS});
    my $r = $def->{READINGS};


    # preset current $rain_raw
    $v[0] = hex("$a[28]$a[27]$a[26]");
    my $rain_raw= $v[0];

    # get previous rain_raw
    my $rain_raw_prev= $rain_raw;
    if(defined($r->{rain_raw})) {
      ($rain_raw_prev, undef)= split(" ", $r->{rain_raw}{VAL}); # cut off "(counter)"
    };

    # unadjusted value as default
    my $rain_raw_adj= $rain_raw;

    # get previous rain_raw_adj
    my $rain_raw_adj_prev= $rain_raw;
    if(defined($r->{rain_raw_adj})) {
         $rain_raw_adj_prev= $r->{rain_raw_adj}{VAL};
    };

    if(defined($attr{$name}) &&
       defined($attr{$name}{"rainadjustment"}) &&
       ($attr{$name}{"rainadjustment"}>0)) {

       # The rain values delivered by my KS300 randomly switch between two
       # different values. The offset between the two values follows no
       # identifiable principle. It is even unclear whether the problem is
       # caused by KS300 or by FHZ1300. ELV denies any problem with the KS300.
       # The problem is known to several people. For instance, see
       # http://www.ipsymcon.de/forum/showthread.php?t=3303&highlight=ks300+regen&page=3
       # The following code detects and automatically corrects these offsets.

       my $rain_raw_ofs;
       my $rain_raw_ofs_prev;
       my $tsecs_prev;

       # get previous offet
       if(defined($r->{rain_raw_ofs})) {
         $rain_raw_ofs_prev= $r->{rain_raw_ofs}{VAL};
       } else{
         $rain_raw_ofs_prev= 0;
       }

       # the current offset is the same, but this may change later
       $rain_raw_ofs= $rain_raw_ofs_prev;

       # get previous tsecs
       if(defined($r->{tsecs})) {
         $tsecs_prev= $r->{tsecs}{VAL};
       } else{
         $tsecs_prev= 0; # 1970-01-01
       }

       # detect error condition
       # delta is negative or delta is too large
       # see http://de.wikipedia.org/wiki/Niederschlagsintensit??t#Niederschlagsintensit.C3.A4t
       # during a thunderstorm in middle europe, 50l/m^2 rain may fall per hour
       # 50l/(m^2*h) correspond to 200 ticks/h
       # Since KS300 sends every 2,5 minutes, a maximum delta of 8 ticks would
       # be reasonable. The observed deltas are in most cases 1 or 2 orders
       # of magnitude larger.
       # The code also handles counter resets after battery replacement

       my $rain_raw_delta= $rain_raw- $rain_raw_prev;
       if($tsecs!= $tsecs_prev) { # avoids a rare but relevant condition
            my $thours_delta= ($tsecs- $tsecs_prev)/3600.0; # in hours
            my $rain_raw_per_hour= $rain_raw_delta/$thours_delta;
            if(($rain_raw_delta<0) || ($rain_raw_per_hour> 200.0)) {
                $rain_raw_ofs= $rain_raw_ofs_prev-$rain_raw_delta;
                # If the switch in the tick count occurs simultaneously with an
                # increase due to rain, the tick is lost. We therefore assume that
                # offsets between -5 and 0 are indeed rain.
                if(($rain_raw_ofs>=-5) && ($rain_raw_ofs<0)) { $rain_raw_ofs= 0; }
                $r->{rain_raw_ofs}{TIME} = $tm;
                $r->{rain_raw_ofs}{VAL} = $rain_raw_ofs;
                $def->{CHANGED}[$n++] = "rain_raw_ofs: $rain_raw_ofs";
            }
       }
       $rain_raw_adj= $rain_raw+ $rain_raw_ofs;

    }

    # remember tsecs
    $r->{tsecs}{TIME} = $tm;
    $r->{tsecs}{VAL} = "$tsecs";

    # remember rain_raw_adj
    $r->{rain_raw_adj}{TIME} = $tm;
    $r->{rain_raw_adj}{VAL} = $rain_raw_adj;


    # KS300 has a sensor which detects any drop of rain and immediately
    # sends out the israining message. The sensors consists of two parallel
    # strips of metal separated by a small gap. The rain bridges the gap
    # and closes the contact. If the KS300 pole is not perfectly vertical the
    # drop runs along only one side and the contact is not closed. To get the
    # israining information anyway, the respective flag is also set when the
    # a positive amount of rain is detected.
    $haverain = 1 if($rain_raw_adj != $rain_raw_adj_prev);

    $v[1] = sprintf("%0.1f", $rain_raw_adj * $def->{RAINUNIT} / 1000);
    $v[2] = sprintf("%0.1f", ("$a[25]$a[24].$a[23]"+0) * $def->{WINDUNIT});
    $v[3] = "$a[22]$a[21]" + 0;
    $v[4] = "$a[20]$a[19].$a[18]" + 0; $v[4] = "-$v[4]" if($a[17] eq "7");
    $v[4] = sprintf("%0.1f", $v[4]);

    $v[5] = ((hex($a[17]) & 0x2) || $haverain) ? "yes" : "no";
    $v[6] = $a[29];
    $v[7] = $a[16];
    $v[8] = $a[17];

    # Negative temp
    $v[4] = -$v[4] if($v[8] & 8);

    Log GetLogLevel($def->{NAME},4), "KS300 $dev: $msg";

    my $max = int(@v);

    # For logging/summary
    my $val = "T: $v[4]  H: $v[3]  W: $v[2]  R: $v[1]  IR: $v[5]";
    Log GetLogLevel($def->{NAME},4), "KS300 $dev: $val";
    $def->{STATE} = $val;
    $def->{CHANGED}[0] = $val;

    for(my $i = 0; $i < $max; $i++) {
      $r->{$txt[$i]}{TIME} = $tm;
      #$val = "$v[$i] $sfx[$i]";
      $val = $v[$i];
      $r->{$txt[$i]}{VAL} = $val;
      $def->{CHANGED}[$n++] = "$txt[$i]: $val"
                if(defined($repchanged{$txt[$i]}));
    }

    ###################################
    # AVG computing
    if(!$r->{cum_day}) {

      $r->{cum_day}{VAL} = "$tm T: 0 H: 0 W: 0 R: $v[1]";
      $r->{avg_day}{VAL} = "T: $v[4]  H: $v[3]  W: $v[2]  R: $v[1]";

    } else {

      my @cv = split(" ", $r->{cum_day}{VAL});

      my @cd = split("[ :-]", $r->{cum_day}{TIME});
      my $csec = 3600*$cd[3] + 60*$cd[4] + $cd[5]; # Sec of last reading

      my @d = split("[ :-]", $tm);
      my $sec = 3600*$d[3] + 60*$d[4] + $d[5];     # Sec now

      my @sd = split("[ :-]", "$cv[0] $cv[1]");
      my $ssec = 3600*$sd[3] + 60*$sd[4] + $sd[5]; # Sec at start of day

      my $difft = $sec - $csec;
      $difft += 86400 if($d[2] != $cd[2]);         # Sec since last reading

      my $t = $cv[3] + $difft * $v[4];
      my $h = $cv[5] + $difft * $v[3];
      my $w = $cv[7] + $difft * $v[2];
      my $e = $cv[9];

      $r->{cum_day}{VAL} = "$cv[0] $cv[1] T: $t  H: $h  W: $w  R: $e";

      $difft = $sec - $ssec;
      $difft += 86400 if($d[2] != $sd[2]);         # Sec since last reading

      $difft = 1 if(!$difft);                      # Don't want illegal division.
      $t /= $difft; $h /= $difft; $w /= $difft; $e = $v[1] - $cv[9];
      $r->{avg_day}{VAL} =
      		sprintf("T: %.1f  H: %d  W: %.1f  R: %.1f", $t, $h, $w, $e);

      if($d[2] != $sd[2]) {			   # Day changed, report it

        $def->{CHANGED}[$n++] = "avg_day $r->{avg_day}{VAL}";
        $r->{cum_day}{VAL} = "$tm T: 0 H: 0 W: 0 R: $v[1]";

	if(!$r->{cum_month}) {                     # Check the month

	  $r->{cum_month}{VAL} = "1 $r->{avg_day}{VAL}";
	  $r->{avg_month}{VAL} = $r->{avg_day}{VAL};

	} else {

	  my @cmv = split(" ", $r->{cum_month}{VAL});
	  $t += $cmv[2]; $w += $cmv[4]; $h += $cmv[6];

	  $cmv[0]++;
	  $r->{cum_month}{VAL} =
	  	sprintf("%d T: %.1f  H: %d  W: %.1f  R: %.1f",
				$cmv[0], $t, $h, $w, $cmv[8]+$e);
	  $r->{avg_month}{VAL} =
	  	sprintf("T: %.1f  H: %d  W: %.1f  R: %.1f",
				$t/$cmv[0], $h/$cmv[0], $w/$cmv[0], $cmv[8]+$e);

	  if($d[1] != $sd[1]) {                   # Month changed, report it

	    $def->{CHANGED}[$n++] = "avg_month $r->{avg_month}{VAL}";
	    $r->{cum_month}{VAL} = "0 T: 0 H: 0 W: 0 R: 0";

	  }

        }
        $r->{cum_month}{TIME} = $r->{avg_month}{TIME} = $tm;

      }

    }
    $r->{cum_day}{TIME} = $r->{avg_day}{TIME} = $tm;
    # AVG computing
    ###################################

    return $name;

  } else {

    Log 4, "KS300 detected: $msg";
    return "UNDEFINED KS300 KS300 1234";

  }

}

1;

=pod
=begin html

<a name="KS300"></a>
<h3>KS300</h3>
<ul>
  Fhem can receive the KS300 radio (868.35 MHz) messages through <a
  href="#FHZ">FHZ</a>, <a href="WS300">WS300</a> or an <a href="#CUL">CUL</a>
  device, so one of them must be defined first.<br>
  This module services messages received by the FHZ device, if you use one of
  the other alternetives, see the <a href="#WS300">WS300</a> or <a
  href="#CUL_WS">CUL_WS</a> entries.<br>
  Note: The KS555 is also reported to work.<br>
  <br>

  <a name="KS300define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KS300 &lt;housecode&gt; [ml/raincounter [wind-factor]]</code>
    <br><br>

    <code>&lt;housecode&gt;</code> is a four digit hex number,
    corresponding to the address of the KS300 device, right now it is ignored.
    The ml/raincounter defaults to 255 ml, but it must be specified if you wish
    to set the wind factor, which defaults to 1.0.
    <br>

    Examples:
    <ul>
      <code>define ks1 KS300 1234</code><br>
    </ul>
  </ul>
  <br>

  <a name="KS300set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="KS300attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (ks300)</li>
    <li>rainadjustment<br>
        If this attribute is set, fhem automatically accounts for rain counter
        resets after a battery change and random counter switches as experienced
        by some users. The raw rain counter values are adjusted by an offset
        in order to flatten out the sudden large increases and decreases in
        the received rain counter values. Default is off.</li>
  </ul>
  <br>

</ul>

=end html
=cut
