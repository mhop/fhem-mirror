##############################################
package main;

use strict;
use warnings;

my %defptr;
my $negcount = 0;

######################
# Note: this is just an empty hull.

#####################################
sub
KS300_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # 810d04f94027a00171212730000008
  # 81 0d 04 f9 4027a00171 212730000008

  $hash->{Match}     = "^810.04..402.a001";
  $hash->{DefFn}     = "KS300_Define";
  $hash->{UndefFn}   = "KS300_Undef";
  $hash->{ParseFn}   = "KS300_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:ks300 loglevel:0,1";
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
  $defptr{$a[2]} = $hash;

  return undef;
}

#####################################
sub
KS300_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}


#####################################
sub
KS300_Parse($$)
{
  my ($hash,$msg) = @_;

  if($msg !~ m/^810d04..4027a001/) {
    Log 4, "KS300 unknown message $msg";
    return "";
  }

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
    Log 4, "Strange KS400 message received, wont decode ($msg)";
    return "";
  }

  if(int(keys %defptr)) {

    my @arr = keys(%defptr); # No code is known yet
    my $dev = shift(@arr);
    my $def = $defptr{$dev};
    my $haverain = 0;

    my @v;
    my @txt = ( "rain_raw", "rain", "wind", "humidity", "temperature",
                "israining", "unknown1", "unknown2", "unknown3");
    my @sfx = ( "(counter)", "(l/m2)", "(km/h)", "(%)", "(Celsius)",
                "(yes/no)", "","","");

    # The next instr wont work for empty hashes, so we init it now
    $def->{READINGS}{$txt[0]}{VAL} = 0 if(!$def->{READINGS});
    my $r = $def->{READINGS};

    $v[0] = hex("$a[28]$a[27]$a[26]");

    #############################
    # My KS300 sends a (quite huge) "negative" rain, when the rain begins,
    # then the value is "normal" again. So we have to filter neg. rain out.
    # But if the KS300 is sending this value more than once, then accept it,
    # as the KS300 was probably reset

    if($r->{rain_raw}{VAL}) {
      my ($rrv, undef) = split(" ", $r->{rain_raw}{VAL});
      $haverain = 1 if($v[0] != $rrv);
      if($v[0] < $rrv) {
        if($negcount++ < 3) {
	  Log 3, "KS300 negative rain, ignoring it";
          $v[0] = $rrv;
	} else {
	  Log 1, "KS300 was probably reset, accepting new rain value";
	}
      } else {
        $negcount = 0;
      }
    }

    $v[1] = sprintf("%0.1f", $v[0] * $def->{RAINUNIT} / 1000);
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

    my $tm = TimeNow();

    Log GetLogLevel($def->{NAME},4), "KS300 $dev: $msg";

    my $max = int(@v);

    # For logging/summary
    my $val = "T: $v[4]  H: $v[3]  W: $v[2]  R: $v[1]  IR: $v[5]";
    $def->{STATE} = $val;
    $def->{CHANGED}[0] = $val;

    for(my $i = 0; $i < $max; $i++) {
      $r->{$txt[$i]}{TIME} = $tm;
      $val = "$v[$i] $sfx[$i]";
      $r->{$txt[$i]}{VAL} = $val;
      $def->{CHANGED}[$i+1] = "$txt[$i]: $val";
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

      $t /= $difft; $h /= $difft; $w /= $difft; $e = $v[1] - $cv[9];
      $r->{avg_day}{VAL} =
      		sprintf("T: %.1f  H: %d  W: %.1f  R: %.1f", $t, $h, $w, $e);

      if($d[2] != $sd[2]) {			   # Day changed, report it

        $def->{CHANGED}[$max++] = "avg_day $r->{avg_day}{VAL}";
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

	    $def->{CHANGED}[$max++] = "avg_month $r->{avg_month}{VAL}";
	    $r->{cum_month}{VAL} = "0 T: 0 H: 0 W: 0 R: 0";

	  }

        }
        $r->{cum_month}{TIME} = $r->{avg_month}{TIME} = $tm;

      }

    }
    $r->{cum_day}{TIME} = $r->{avg_day}{TIME} = $tm;
    # AVG computing
    ###################################

    return $def->{NAME};

  } else {

    Log 4, "KS300 detected: $msg";

  }

  return "";
}

1;
