##############################################
# (c) by STefan Mayer (stefan(at)clumsy.ch)  #
#                                            #
# please feel free to contact me for any     #
# changes, improvments, suggestions, etc     #
#                                            #
##############################################
# $Id$

package main;

use strict;
use warnings;

my %codes = (
  "19fa" => "ESA2000_LED",
);


#####################################
sub
ESA2000_Initialize($)
{
  my ($hash) = @_;

#                        S0119FA011E00007D6E003100000007C9 ESA2000_LED

  $hash->{Match}     = "^S................................\$";
  $hash->{DefFn}     = "ESA2000_Define";
  $hash->{UndefFn}   = "ESA2000_Undef";
  $hash->{ParseFn}   = "ESA2000_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 model:esa2000-led loglevel:0,1,2,3,4,5,6 ignore:0,1 base_1 base_2";
}

#####################################
sub
ESA2000_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> ESA2000 CODE" if(int(@a) != 3);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);


  $hash->{CODE} = $a[2];
  $modules{ESA2000}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
ESA2000_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{ESA2000}{defptr}{$hash->{CODE}})
        if(defined($hash->{CODE}) &&
           defined($modules{ESA2000}{defptr}{$hash->{CODE}}));
  return undef;
}

#####################################
sub
ESA2000_Parse($$)
{
  my ($hash, $msg) = @_;

# 0123456789012345678901234567890123456789
# S0119FA011E00007D6E003100000007C9F9 ESA2000_LED
  $msg = lc($msg);
  my $seq = substr($msg, 1, 2);
  my $cde = substr($msg, 3, 4);
  my $dev = substr($msg, 7, 4);
  my $val = substr($msg, 11, 22);

  Log 5, "ESA2000 msg $msg";
  Log 5, "ESA2000 seq $seq";
  Log 5, "ESA2000 device $dev";
  Log 5, "ESA2000 code $cde";

  my $type = "";
  foreach my $c (keys %codes) {
    $c = lc($c);
    if($cde =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  if(!defined($modules{ESA2000}{defptr}{$dev})) {
    Log 3, "Unknown ESA2000 device $dev, please define it";
    $type = "ESA2000" if(!$type);
    return "UNDEFINED ${type}_$dev ESA2000 $dev";
  }

  my $def = $modules{ESA2000}{defptr}{$dev};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my $now = TimeNow();
  my (@v, @txt);

#  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
#  $year = $year + 1900;

  if($type eq "ESA2000_LED") {

    @txt = ( "repeat", "sequence", "total_ticks", "actual_ticks", "ticks_kwh", "raw", "total_kwh", "actual_kwh", "diff_kwh", "diff_sec", "diff_ticks", "last_sec", "raw_total_kwh", "max_kwh", "day_kwh", "month_kwh", "year_kwh", "rate", "hr_kwh", "lr_kwh", "day_hr_kwh", "day_lr_kwh", "month_hr_kwh", "month_lr_kwh", "year_hr_kwh", "year_lr_kwh" );


    # Codierung Hex
    $v[0] =  int(hex($seq) / 128) ? "+" : "-"; # repeated
    $v[1] =  hex($seq) % 128;
    $v[2] =  hex(substr($val,0,8));
    $v[3] =  hex(substr($val,8,4));
    $v[4] =  hex(substr($val,18,4)) ^ 25; # XOR 25, whyever bit 1,4,5 are swapped?!?! Probably a (receive-) error in CUL-FW?

    $v[11] = time();
    # check if low-rate or high-rate. note that this is different per electricity company! (Here weekday from 6-20 is high rate)
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
    if ( (0 < $wday ) && ($wday < 6) && (5 < $hour) && ($hour < 20) ) {
      $v[17] = "HR";
    } else {
      $v[17] = "LR";
    } 

    $v[5] = sprintf("CNT: %d%s CUM: %d CUR: %d  TICKS: %d %s",
                         $v[1], $v[0], $v[2], $v[3], $v[4], $v[17] );

    if (defined($def->{READINGS}{$txt[11]}{VAL})) {
      $v[9] =  $v[11] - $def->{READINGS}{$txt[11]}{VAL}; # seconds since last update
    } 
    if(defined($v[9]) && $v[9] != 0) {
      $v[7] =  $v[3]/$v[4]/$v[9]*3600; # calculate kW/h since last update
    } else {
      $v[7] = -1;
    }
    $v[8] =  $v[3]/$v[4]; # calculate kWh diff from readings (raw from device....), whats this relly?
    if(defined($def->{READINGS}{$txt[2]}{VAL})) {
      if($def->{READINGS}{$txt[2]}{VAL} <=$v[2]) { # check for resetted counter.... only accept increase in counter
        $v[10] = $v[2] - $def->{READINGS}{$txt[2]}{VAL}; # shoudl be the same as actual_ticks if no packets are lost
      }
    }
    if(defined($v[10])) {
      $v[6] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[6]}{VAL}) ? $def->{READINGS}{$txt[6]}{VAL} : 0); # cumulate kWh to ensure tick-changes are calculated correctly (does this ever happen?)
      if(defined($def->{READINGS}{$txt[14]}{TIME})) {
        if(substr($now,0,10) eq substr($def->{READINGS}{$txt[14]}{TIME},0,10)) { # a bit clumsy, I agree, but it works and its logical and this is pearl, right?
          $v[14] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[14]}{VAL}) ? $def->{READINGS}{$txt[14]}{VAL} : 0); # cumulate kWh to ensure tick-changes are calculated correctly (does this ever happen?)
          if ($v[17] eq "HR" ) {
            $v[18] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[18]}{VAL}) ? $def->{READINGS}{$txt[18]}{VAL} : 0); # high-rate
          } else {
            $v[19] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[19]}{VAL}) ? $def->{READINGS}{$txt[19]}{VAL} : 0); # low-rate
          }
        } else {
          $v[14] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[18] = $v[10]/$v[4];
          } else {
            $v[19] = $v[10]/$v[4];
          }
       }
      } else {
          $v[14] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[18] = $v[10]/$v[4];
          } else {
            $v[19] = $v[10]/$v[4];
          }
        }
      if(defined($def->{READINGS}{$txt[15]}{TIME})) {
        if(substr($now,0,7) eq substr($def->{READINGS}{$txt[15]}{TIME},0,7)) { # a bit clumsy, I agree, but it works and its logical and this is pearl, right?
          $v[15] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[15]}{VAL}) ? $def->{READINGS}{$txt[15]}{VAL} : 0); # cumulate kWh to ensure tick-changes are calculated correctly (does this ever happen?)
          if ($v[17] eq "HR" ) {
            $v[20] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[20]}{VAL}) ? $def->{READINGS}{$txt[20]}{VAL} : 0); # high-rate
          } else {
            $v[21] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[21]}{VAL}) ? $def->{READINGS}{$txt[21]}{VAL} : 0); # low-rate
          }
        } else {
          $v[15] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[20] = $v[10]/$v[4];
          } else {
            $v[21] = $v[10]/$v[4];
          }
        }
      } else {
          $v[15] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[20] = $v[10]/$v[4];
          } else {
            $v[21] = $v[10]/$v[4];
          }
        }
      if(defined($def->{READINGS}{$txt[16]}{TIME})) {
        if(substr($now,0,4) eq substr($def->{READINGS}{$txt[16]}{TIME},0,4)) { # a bit clumsy, I agree, but it works and its logical and this is pearl, right?
          $v[16] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[16]}{VAL}) ? $def->{READINGS}{$txt[16]}{VAL} : 0); # cumulate kWh to ensure tick-changes are calculated correctly (does this ever happen?)
          if ($v[17] eq "HR" ) {
            $v[22] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[22]}{VAL}) ? $def->{READINGS}{$txt[22]}{VAL} : 0); # high-rate
          } else {
            $v[23] = $v[10]/$v[4] + (defined($def->{READINGS}{$txt[23]}{VAL}) ? $def->{READINGS}{$txt[23]}{VAL} : 0); # low-rate
          }
        } else {
          $v[16] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[22] = $v[10]/$v[4];
          } else {
            $v[23] = $v[10]/$v[4];
          }
        }
      } else {
          $v[16] = $v[10]/$v[4];
          if ($v[17] eq "HR" ) {
            $v[22] = $v[10]/$v[4];
          } else {
            $v[23] = $v[10]/$v[4];
          }
        }
    } else {
      $v[6] = 0;
    } 

    $v[12] =  $v[2]/$v[4]; # calculate kWh total since reset of device (does only make sense if ticks per kWh does not change!!)
    if(defined($def->{READINGS}{$txt[13]}{VAL})) {
      if($v[7] >= $def->{READINGS}{$txt[13]}{VAL}) {
        $v[13] = $v[7]; # update max kw/h
      }
    } else {
      $v[13] = $v[7]; # update max kw/h
    }
      

    # add counter_1 and counter_2 (Hoch- und Niedertarif Basiswerte)
    if(defined($attr{$name}) &&
       defined($attr{$name}{"count_1"}) &&
       ($attr{$name}{"count_1"}>0)) {
         $v[13] = $v[12] + $attr{$name}{"count_1"};
      }

    if(defined($attr{$name}) &&
       defined($attr{$name}{"count_2"}) &&
       ($attr{$name}{"count_2"}>0)) {
        $v[13] = $v[12] + $attr{$name}{"count_2"};
      }

    $val = sprintf("CNT: %d%s CUM: %0.3f CUR: %0.3f TICKS: %d %s",
                         $v[1], $v[0], $v[6], $v[7], $v[4], $v[17]);

  } else {

    Log 3, "ESA2000 Device $dev (Unknown type: $type)";
    return "";

  }


  my $max = int(@txt);

  if ( (defined($def->{READINGS}{"sequence"}{VAL}) ? $def->{READINGS}{"sequence"}{VAL} : "") ne $v[1] ) {
    Log GetLogLevel($name,4), "ESA2000 $name: $val";
    for( my $i = 0; $i < $max; $i++) {
      if ( $v[$i] ) {
        $def->{READINGS}{$txt[$i]}{TIME} = $now;
        $def->{READINGS}{$txt[$i]}{VAL} = $v[$i];
        $def->{CHANGED}[$i] = "$txt[$i]: $v[$i]";
      }
    }
    $def->{READINGS}{type}{TIME} = $now;
    $def->{READINGS}{type}{VAL} = $type;

    $def->{STATE} = $val;
    $def->{CHANGED}[$max++] = $val;
  } else {
    Log GetLogLevel($name,4), "(ESA2000/DISCARDED $name: $val)";
    return "($name)";
  }

  return $name;
}

1;

=pod
=begin html

<a name="ESA2000"></a>
<h3>ESA2000</h3>
<ul>
  The ESA2000 module interprets ESA2000 type of messages received by the CUL,
  currently only for ESA2000 LED devices.
  <br><br>

  <a name="ESA2000define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ESA2000 &lt;code&gt;
        [base1 base2]</code> <br>
    <br>
    &lt;code&gt; is the 4 digit HEX code identifying the devices.<br><br>

    <b>base1/2</b> is added to the total kwh as a base (Hoch- und Niedertarifz&auml;hlerstand).
  </ul>
  <br>

  <a name="CUL_EMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_EMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_EMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#model">model</a> (ESA2000_LED)</li><br>
    <li><a href="#IODev">IODev</a></li><br>
  </ul>
  <br>
</ul>


=end html
=cut
