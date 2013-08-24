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
  "011e" => "ESAx000WZ",
  "031e" => "ESA1000Z",
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
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 ignore:0,1 ".
                       "model:esa2000-led,esa2000-wz,esa2000-s0,esa1000wz-ir,esa1000wz-s0,esa1000wz-led,esa1000gas base_1 base_2 ".
                       $readingFnAttributes;
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

# 0 00 0000 0001 11111111 1222 222222 2333
# 0 12 3456 7890 12345678 9012 345678 9012
# S                                            Sensorkennung
#   ss                                         Sequenze und Sequenzwiederhohlung mit gesetzten höchsten Bit
#      dddd                                    Device
#           cccc                               Code
#                vvvvvvvv vvvv vvvvvv vvvv     Valves
#                tttttttt                      Gesamtimpules
#                         aaaa                 Impule je Sequenz
#                              zzzzzz          Zeitstempel seit Start des Adapters             (ESA1000)
#                                     kkkk     Impulse je kWh/m3
#
# Examples:
# ---------
# S 01 19FA 011E 00007D6E 0031 000000 07C9     ESA2000_LED      Zählerkonstante = 2000
# S 12 5E42 011E 00000030 0002 000000 0206     ESA2000_WZ       Zählerkonstante = 600
# S 48 6062 011E 00000061 0001 000000 002B     ESA2000_WZ       Zählerkonstante = 75
# S 93 5DDA 011E 00004F85 0000 000000 0205     ESA2000_WZ       Zählerkonstante = 600
# S 16 68C5 011E 000000BB 0000 001FB4 03CB     ESA1000WZ_LED    Zählerkonstante = 1000
# S AB 0595 031E 000A047E 0000 227C46 0004     ESA1000GAS       Zählerkonstante = 1
# S 1C 0785 011E 00011CDA 0002 0D056C 004C     ESA1000WZ_LED    Zählerkonstante = 75
# S 6E 003D 011E 00037650 0011 02C1DA 07D0     ESA1000WZ_S0     Zählerkonstante = 2000
# S A3 0543 031E 0000099C 0064 001147 000F     ESA1000GAS       Zählerkonstante = 10

  $msg = lc($msg);
  my $seq = substr($msg, 1, 2);
  my $dev = substr($msg, 3, 4);
  my $cde = substr($msg, 7, 4);
  my $val = substr($msg, 11, 22);

  Log3 $hash, 5, "ESA2000 msg $msg";
  Log3 $hash, 5, "ESA2000 seq $seq";
  Log3 $hash, 5, "ESA2000 device $dev";
  Log3 $hash, 5, "ESA2000 code $cde";

  my $type = "";
  foreach my $c (keys %codes) {
    $c = lc($c);
    if($cde =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  if(!defined($modules{ESA2000}{defptr}{$dev})) {
    Log3 $hash, 3, "Unknown ESA2000 device $dev, please define it";
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

#  0- 5     repeat, sequence, total_ticks, actual_ticks, ticks, raw
#  6-12     total, actual, diff, diff_sec, diff_ticks, last_sec, raw_total
# 13-17     max, day, month, year, rate
# 18-23     day_hr, day_lr, month_hr, month_lr, year_hr, year_lr
# 24-28     day_last, month_last, year_last, hour, hour_last

  if(($type eq "ESAx000WZ") || ($type eq "ESA1000Z")) {

    @txt = ( "repeat", "sequence", "total_ticks", "actual_ticks", "ticks", "raw", 
             "total", "actual", "diff", "diff_sec", "diff_ticks", "last_sec", "raw_total", 
             "max", "day", "month", "year", "rate", 
             "day_hr", "day_lr", "month_hr", "month_lr", "year_hr", "year_lr",
             "day_last", "month_last", "year_last", "hour", "hour_last" );

  } else {

    Log3 $name, 3, "ESA2000 Device $dev (Unknown type: $type)";
    return "";

  }

    # Codierung Hex
    $v[0] =  int(hex($seq) / 128) ? "+" : "-";
    $v[1] =  hex($seq) % 128;
    $v[2] =  hex(substr($val,0,8));
    $v[3] =  hex(substr($val,8,4));
    $v[4] =  hex(substr($val,18,4)) ^ hex(substr($msg,3,2));    # XOR high byte of device-id

    my $corr = 1;
    if ($type eq "ESA1000Z") {
      $corr = 1000/$v[4];
    }

    # check if low-rate or high-rate. note that this is different per electricity company! (Here weekday from 6-20 is high rate)
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;

    if ( (0 < $wday ) && ($wday < 6) && (5 < $hour) && ($hour < 20) ) {
      $v[17] = "HR";
    } else {
      $v[17] = "LR";
    }

    $v[5] = sprintf("CNT: %d%s CUM: %d CUR: %d  TICKS: %d %s",
                         $v[1], $v[0], $v[2], $v[3], $v[4], $v[17] );

    $v[11] = time();
    $v[9] =  $v[11] - (defined($def->{READINGS}{$txt[11]}{VAL}) ? $def->{READINGS}{$txt[11]}{VAL} : $v[11]); # seconds since last update

    $v[7] = -1;
    $v[8] = sprintf("%.4f", $v[3]/$v[4]/$corr);    # calculate kWh diff from readings (raw from device....), whats this relly?

    if(defined($def->{READINGS}{$txt[2]}{VAL}) && $def->{READINGS}{$txt[2]}{VAL} <=$v[2]) {    # check for resetted counter.... only accept increase in counter
      $v[10] = $v[2] - $def->{READINGS}{$txt[2]}{VAL};                                         # should be the same as actual_ticks if no packets are lost
    }

    if(defined($v[10])) {
      my $con = $v[10]/$v[4]/$corr;
      if($v[9] >= 110) {
        # Zeitdifferenz zu gering (ESA 120s bis 184s)
        # $v[9] = (($v[9] lt 110) ? 150 : $v[9]);
        $v[7] = $con/$v[9]*3600;                                        # calculate kW/h since last update
      }
      $v[6] = $con + (defined($def->{READINGS}{$txt[6]}{VAL}) ? $def->{READINGS}{$txt[6]}{VAL} : 0); # cumulate kWh to ensure tick-changes are calculated correctly (does this ever happen?)
      # 27 "hour"
      # 28 "hour_last"
      if(defined($def->{READINGS}{$txt[27]}{VAL})) {
        $v[27] = $con + ((substr($now,0,13) eq substr($def->{READINGS}{$txt[27]}{TIME},0,13)) ? $def->{READINGS}{$txt[27]}{VAL} : 0);
        $v[28] = $def->{READINGS}{$txt[27]}{VAL} if(substr($now,0,13) ne substr($def->{READINGS}{$txt[27]}{TIME},0,13));
      } else {
        $v[27] = $con
      }
      #     Day          #     Month          #     Year
      # 14 "day"         # 15 "month"         # 16 "year"
      # 18 "day_hr"      # 20 "month_hr"      # 22 "year_hr"
      # 19 "day_lr"      # 21 "month_lr"      # 23 "year_lr"
      # 24 "day_last"    # 25 "month_last"    # 26 "year_last"
      for(my $i = 0; $i < 3; $i++) {
        if(defined($def->{READINGS}{$txt[$i+14]}{VAL})) {
          $v[14+$i] = $con + ((substr($now,0,10-$i*3) eq substr($def->{READINGS}{$txt[$i+14]}{TIME},0,10-$i*3)) ? $def->{READINGS}{$txt[14+$i]}{VAL} : 0);
          $v[24+$i] = $def->{READINGS}{$txt[14+$i]}{VAL} if(substr($now,0,10-$i*3) ne substr($def->{READINGS}{$txt[$i+14]}{TIME},0,10-$i*3));
        } else {
          $v[14+$i] = $con
        }
        if ($v[17] eq "HR" ) {
          # high-rate
          $v[18+2*$i] = $con + (defined($def->{READINGS}{$txt[18+2*$i]}{VAL}) && (substr($now,0,10-3*$i) eq substr($def->{READINGS}{$txt[18+2*$i]}{TIME},0,10-3*$i)) ? $def->{READINGS}{$txt[18+2*$i]}{VAL} : 0);
        } else {
          # low-rate
          $v[19+2*$i] = $con + (defined($def->{READINGS}{$txt[19+2*$i]}{VAL}) && (substr($now,0,10-3*$i) eq substr($def->{READINGS}{$txt[19+2*$i]}{TIME},0,10-3*$i)) ? $def->{READINGS}{$txt[19+2*$i]}{VAL} : 0);
        }
      }

      if(!defined($def->{READINGS}{$txt[13]}{VAL})) {
        $v[13] = $v[7];    # update max kw/h
      } elsif($v[7] >= $def->{READINGS}{$txt[13]}{VAL}) {
        $v[13] = $v[7];    # update max kw/h
      }

      $v[12] = $v[2]/$v[4]/$corr;   # calculate kWh total since reset of device (does only make sense if ticks per kWh does not change!!)
      # add counter_1 and counter_2 (Hoch- und Niedertarif Basiswerte)
      if(defined($attr{$name}) &&
        defined($attr{$name}{"base_1"})) {
          $v[12] = sprintf("%.3f", $v[12] + $attr{$name}{"base_1"});
      }
      if(defined($attr{$name}) &&
        defined($attr{$name}{"base_2"})) {
          $v[12] = sprintf("%.3f", $v[12] + $attr{$name}{"base_2"});
      }

    } else {
      #  6 "total_kwh"
      $v[6] = (defined($def->{READINGS}{$txt[6]}{VAL}) ? $def->{READINGS}{$txt[6]}{VAL} : 0);
    }

    $val = sprintf("CNT: %d%s CUM: %0.3f CUR: %0.3f TICKS: %d %s",
                       $v[1], $v[0], $v[6], $v[7], $v[4], $v[17]);

  #
  # from here readings are effectively updated
  #
  readingsBeginUpdate($def);

  Log3 $name, 4, "ESA2000 $name: $val";

  if ( (defined($def->{READINGS}{"sequence"}{VAL}) ? $def->{READINGS}{"sequence"}{VAL} : "") ne $v[1] ) {
    my $max = int(@txt);
    for( my $i = 0; $i < $max; $i++) {
      if (defined($v[$i])) {
        readingsBulkUpdate($def, $txt[$i], $v[$i]);
      }
    }

    readingsBulkUpdate($def, "type", $type);
    readingsBulkUpdate($def, "state", $val);

  } else {
    Log3 $name, 4, "ESA2000/DISCARDED $name: $val";
  }
  #
  # now we are done with updating readings
  #
  readingsEndUpdate($def, 1);

  return $name;
}

1;

=pod
=begin html

<a name="ESA2000"></a>
<h3>ESA2000</h3>
<ul>
  The ESA2000 module interprets ESA1000 or ESA2000 type of messages received by the CUL.
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

  <a name="ESA2000set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="ESA2000get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="ESA2000attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#model">model</a> (esa2000-led, esa2000-wz, esa2000-s0, esa1000wz-ir, esa1000wz-s0, esa1000wz-led, esa1000gas)</li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
  </ul>
  <br>
</ul>


=end html
=cut
