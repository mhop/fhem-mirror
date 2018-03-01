# $Id$
##############################################################################
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;

use SetExtensions;

sub logProxy_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "logProxy_Define";
  $hash->{UndefFn}  = "logProxy_Undefine";
  #$hash->{SetFn}    = "logProxy_Set";
  $hash->{GetFn}    = "logProxy_Get";
  #$hash->{AttrList} = "disable:1 ";

  $hash->{SVG_sampleDataFn} = "logProxy_sampleDataFn";
  $hash->{SVG_regexpFn}     = "logProxy_regexpFn";
}


sub logProxy_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  my $name = $args[0];

  my $usage = "Usage: define <name> logProxy";

  return $usage if( int(@args) != 2 );

  my $d = $modules{logProxy}{defptr};
  return "logProxy device already defined as $d->{NAME}." if( defined($d) );
  $modules{logProxy}{defptr} = $hash;

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub logProxy_Undefine($$)
{
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};

  delete $modules{logProxy}{defptr};

  return undef;
}

my $logProxy_columns = "ConstX,ConstY,Func,Polar,FileLog,DbLog";
sub
logProxy_sampleDataFn($$$$$)
{
  my ($ldName, $flog, $max, $conf, $wName) = @_;

  my $desc = "Type,Spec";

  my @htmlArr;
  $max = 16 if($max > 16);
  for(my $r=0; $r < $max; $r++) {
    my @f = split(":", ($flog->[$r] ? $flog->[$r] : ":"), 6);
    my $ret = "";
    $ret .= SVG_sel("par_${r}_0", $logProxy_columns, $f[0]);
    $ret .= SVG_txt("par_${r}_1", "", join(":", @f[1..@f-1]), 30);
    push @htmlArr, $ret;
  }

  my @example;
  push @example, 'ConstY:0';
  push @example, 'ConstY:$data{avg1}';
  push @example, 'ConstY:$data{avg2}';
  push @example, 'DbLog:myDB:myReading';
  push @example, 'FileLog:myFileLog:4:myReading';
  push @example, 'FileLog:FileLog_&lt;SPEC1&gt;:4:&lt;SPEC1&gt;.power';
  push @example, 'FileLog:FileLog_&lt;SPEC1&gt;:4:&lt;SPEC1&gt;.consumption';
  push @example, 'Func:logProxy_WeekProfile2Plot("HCB",$from,$to)';
  push @example, 'Func:logProxy_WeekProfile2Plot("myHeatingControl",$from,$to,"(\\d*)\$")';
  push @example, 'ConstX:logProxy_shiftTime($from,60*60*2),$data{min1},$data{max1}';

#Log 3, Dumper $desc;
#Log 3, Dumper @htmlArr;
#Log 3, Dumper $example;

  return ($desc, \@htmlArr, join("<br>", @example));
}
sub
logProxy_regexpFn($$)
{
  my ($name, $filter) = @_;

  my $ret;

  my @a = split( ' ', $filter );
  for(my $i = 0; $i < int(@a); $i++) {
    my @fld = split(":", $a[$i]);
    if( $a[$i] =~ m/^(FileLog|DbLog):([^:]*):(.*)/ ) {
      my @options = split( ',', $fld[1] );
      my $log_dev = shift(@options);
      my $column_specs = $3;

      $ret .= '|' if( $ret );
      $ret .=  CallFn($log_dev, "SVG_regexpFn", $log_dev, $column_specs);
    }
  }

  return $ret;
}

sub
logProxy_Set($@)
{
  return undef;
}

#WeekProfile format: {$wday}{$time}{$value} with 0 = sunday
sub
logProxy_Heating_Controll2WeekProfile($)
{
  my ($d) = @_;

  return undef if( !defined($defs{$d}) );
  return undef if( !defined($defs{$d}->{helper}{SWITCHINGTIME}) );

  return $defs{$d}->{helper}{SWITCHINGTIME};
}
sub
logProxy_HM2WeekProfile($;$)
{
  my ($d,$list) = @_;

  return undef if( !defined($defs{$d}) );

  # default to 1st list of tc-it
  $list = "P1" if ( !$list );

  # if tc-it
  my @rl = sort( grep /^R_${list}_[0-7]_tempList...$/,keys %{$defs{$d}{READINGS}} );
  # else cc-tc and rt
  @rl = sort( grep /^R_[0-7]_tempList...$/,keys %{$defs{$d}{READINGS}} ) if( !@rl );

  return undef if( !@rl );

  my %profile = ();
  for(my $i=0; $i<7; ++$i) {
    # correct wday
    my $reading = ReadingsVal($d,$rl[($i+1)%7],undef);

    # collect 'until' switching times
    my %tmp = ();
    my @parts = split( ' ', $reading );
    while( @parts ) {
      my $time = shift @parts;
      $tmp{$time} = shift @parts;
    }

    # shift 'until' switching times into 'from' switching times
    # can not be done in one step if times are out of order
    my %st = ();
    my $time = "00:00";
    foreach my $key (sort (keys %tmp)) {
      $st{$time} = $tmp{$key};
      $time = $key;
    }

    $profile{$i} = \%st;

  }

  return undef if (scalar (keys %profile) != 7);

  return \%profile;
}
sub
logProxy_MAX2WeekProfile($)
{
  my ($d) = @_;

  return undef if( !defined($defs{$d}) );

  my @rl = sort( grep /^weekprofile-.-...-(temp|time)$/,keys %{$defs{$d}{READINGS}} );

  return undef if( !@rl );

  my %profile = ();
  for(my $i=0; $i<7; ++$i) {
    # correct wday
    my $temps = ReadingsVal($d,$rl[(($i+1)%7)*2],undef);
    my $times = ReadingsVal($d,$rl[(($i+1)%7)*2+1],undef);

    my %st = ();

    my @temps = split( '/', $temps );
    my @times = split( '/', $times );
    while( @times ) {
      my $temp = shift @temps;
      $temp =~ s/\s*([\d\.]*).*/$1/;

      my $time = shift @times;
      $time =~ s/\s*(\d\d:\d\d).*/$1/;

      $st{$time} = $temp;
    }

    $profile{$i} = \%st;
  }

  return \%profile;
}
# sample implementaion to plot the week profile of a Heating_Control or HM Thermostat device.
sub
logProxy_WeekProfile2Plot($$$;$)
{
  my ($profile, $from, $to, $regex) = @_;

  return undef if( !$profile );

  if( $regex ) {
    eval { "test" =~ m/$regex/ };
    if( $@ ) {
      Log3 undef, 3, "logProxy_WeekProfile2Plot: $regex: $@";
      return undef;
    }
  }

  if( defined($defs{$profile}) ) {
    if( $defs{$profile}{TYPE} eq "Heating_Control" ) {
      $profile = logProxy_Heating_Controll2WeekProfile($profile);
    } elsif( $defs{$profile}{TYPE} eq "WeekdayTimer" ) {
      $profile = logProxy_Heating_Controll2WeekProfile($profile);
    } elsif( $defs{$profile}{TYPE} eq "CUL_HM" ) {
      my ($p,$l) = split( ',', $profile, 2 );
      $profile = logProxy_HM2WeekProfile($p, $l);
    } elsif( $defs{$profile}{TYPE} eq "MAX" ) {
      $profile = logProxy_MAX2WeekProfile($profile);
    } else {
      Log3 undef, 2, "logProxy_WeekProfile2Plot: $profile is not a Heating_Control, WeekdayTimer, CUL_HM or MAX device";
      return undef;
    }
  }

#Log 3, Dumper $profile;

  if( ref($profile) ne "HASH" ) {
    Log3 undef, 2, "logProxy_WeekProfile2Plot: no profile hash given";
    return undef;
  }

  my $fromsec = SVG_time_to_sec($from);
  my $tosec   = SVG_time_to_sec($to);

  my (undef,undef,undef,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($fromsec);

  my $min = 999999;
  my $max = -999999;

  # go back one day to get the start value, TODO: go back multiple days
  $mday -= 1;
  $wday -= 1;
  $wday %= 7;

  my $ret = "";
  my $value;
  my $prev_value;
  my $sec = $fromsec;
  # while not end of plot range reached
  while( $sec < $tosec ) {
    return undef if( !defined($profile->{$wday}) );

    # for all switching times of current day
    foreach my $st (sort (keys %{ $profile->{$wday} })) {
      #remember previous value for start of plot range
      $prev_value = $value;

      my ($h, $m, $s) = split( ':', $st );
      $s = 0 if( !$s );
      $value = $profile->{$wday}{$st};

      if( $regex ) {
        if( $value =~ m/$regex/ ) {
          Log3 undef, 4, "logProxy_WeekProfile2Plot: $value =~ m/$regex/ => $1";
          $value = $1;
        } else {
          Log3 undef, 3, "logProxy_WeekProfile2Plot: $value =~ m/$regex/ => no match";
        }
      }

      # map some specials to values and eco and comfort to temperatures
      $value = 0 if( $value eq "off" );
      $value = 1 if( $value eq "on" );
      $value = 1 if( $value eq "up" );
      $value = 0 if( $value eq "down" );
      $value = 18 if( $value eq "eco" );
      $value = 22 if( $value eq "comfort" );

      # 'dirty' hack that exploits the feature that $mday can be < 0 and > 31.
      # everything should better be based on a real second counter
      my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", 1900+$year, 1+$mon, $mday, $h, $m, $s );
      $sec = SVG_time_to_sec($timestamp);

      # skip all values before start of plot range
      next if( SVG_time_to_sec($timestamp) < $fromsec );

      # add first value at start of plot range
      if( !$ret && defined($prev_value) ) {
        $min = $prev_value if( $prev_value < $min );
        $max = $prev_value if( $prev_value > $max );
        $ret .= "$from $prev_value\n";
      }

      # done if after end of plot range
      last if( SVG_time_to_sec($timestamp) > $tosec );

      $min = $value if( $value < $min );
      $max = $value if( $value > $max );

      # add actual controll point
      $ret .= "$timestamp $value\n";
    }

    # next day
    $mday += 1;
    $wday += 1;
    $wday %= 7;
  }
  # add last value at end of plot range
  $ret .= "$to $prev_value\n";

  return ($ret,$min,$max,$prev_value);
}

sub logProxy_hms2sec($){
  my ($h,$m,$s) = split(":", shift);
  $m = 0 if(!$m);
  $s = 0 if(!$s);
  my $t  = $s;
     $t += $m * 60;
     $t += $h * 60*60;
  return ($t)
}
sub logProxy_isDay($) {
  my ($sec) = @_;

  my $sr = logProxy_hms2sec(sunrise_abs_dat($sec));
  my $ss = logProxy_hms2sec(sunset_abs_dat($sec));

  my ($s,$m,$h) = localtime($sec);
  my $cur = logProxy_hms2sec( "$h:$m:$s" );

  return ($cur > $sr && $cur < $ss)?1:0;
}

sub logProxy_hms2dec($){
  my ($h,$m,$s) = split(":", shift);
  $m = 0 if(!$m);
  $s = 0 if(!$s);
  my $t  = $m * 60;
     $t += $s;
     $t /= 3600;
     $t += $h;
  return ($t)
}

sub logProxy_dec2hms($){
  my ($t) = @_;
  my $h = int($t);
  my $r = ($t - $h)*3600;
  my $m = int($r/60);
  my $s = $r - $m*60;
  return sprintf("%02d:%02d:%02d",$h,$m,$s);
}

sub
logProxy_Range2Zoom($)
{
  my( $range ) = @_;

  return "year"  if( $range > 1+60*60*24*28*6);
  return "month" if( $range > 1+60*60*24*28);
  return "week"  if( $range > 1+60*60*24);
  return "day"   if( $range > 1+60*60*6);
  return "qday"  if( $range > 1+60*60 );
  return "hour";
}
my %logProxy_stepDefault = ( year  => 60*60*24,
                             month => 60*60*24,
                             week  => 60*60*6,
                             day   => 60*60,
                             qday  => 60*15,
                             hour  => 60, );

# sample implementaion to plot an arbitrary function
sub
logProxy_Func2Plot($$$;$)
{
  my ($from, $to, $func, $step) = @_;

  my $fromsec = SVG_time_to_sec($from);
  my $tosec   = SVG_time_to_sec($to);
  my $secs = $tosec - $fromsec;

  $step = \%logProxy_stepDefault if( !$step );
  $step = eval $step if( $step =~ m/^{.*}$/ );
  $step = $step->{logProxy_Range2Zoom($secs)} if( ref($step) eq "HASH" );
  $step = $logProxy_stepDefault{logProxy_Range2Zoom($secs)} if( !$step );

  my $min = 999999;
  my $max = -999999;

  my $ret = "";

  my $value;
  for(my $sec=$fromsec; $sec<$tosec; $sec+=$step) {
    my ($s,$m,$h,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($sec);

    $value = eval $func;
    if( $@ ) {
      Log3 undef, 1, "logProxy_Func2Plot: $func: $@";
      next;
    }

    my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", 1900+$year, 1+$mon, $mday, $h, $m, $s );

    $min = $value if( $value < $min );
    $max = $value if( $value > $max );

    # add actual controll point
    $ret .= "$timestamp $value\n";
  }

  return ($ret,$min,$max,$value);
}


# shift time by offset seconds (or months if offset ends with m)
sub
logProxy_shiftTime($$)
{
  my ($time, $offset) = @_;

  $time =~ s/ /_/;

  if( $offset =~ m/((-)?\d)*m/ ) {
    my @t = split("[-_:]", $time);
    $time = mktime($t[5],$t[4],$t[3],$t[2],$t[1]-1+$1,$t[0]-1900,0,0,-1);;
  } else {
    $time = SVG_time_to_sec($time);
    $time += $offset;
  }

  my @t = localtime($time);
  $time = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

  return $time;
}

# shift plot data by offset
sub
logProxy_shiftData($$;$$)
{
  my ($dp, $offset, $from, $to) = @_;

  my ($dpl,$dpoff,$l) = (length($$dp), 0, "");
  while($dpoff < $dpl) {                # using split instead is memory hog
    my $ndpoff = index($$dp, "\n", $dpoff);
    if($ndpoff == -1) {
      $l = substr($$dp, $dpoff);

    } else {
      $l = substr($$dp, $dpoff, $ndpoff-$dpoff);

    }

    if($l =~ m/^#/) {
    } else {
      my ($d, $v) = split(" ", $l);

      $d = logProxy_shiftTime($d, $offset);

      substr($$dp, $dpoff, 19, $d);

    }

    $dpoff = $ndpoff+1;
    last if($ndpoff == -1);
  }
}

sub
logProxy_linearInterpolate($$$$$) {
  my ($t1, $v1, $t2, $v2, $t ) = @_;

  my $dt = $t2 - $t1;

  return $v1 if( !$dt );

  my $dv = $v2 - $v1;

  my $v = $v1 + $dv * ( ($t-$t1) / $dt );

  return $v;
}

# clip plot data to [$from,$to] range
sub
logProxy_clipData($$$$;$)
{
  my ($dp, $from, $to, $interpolate, $predict) = @_;

  my $ret = "";
  my $min = 999999;
  my $max = -999999;
  my $comment = "";

  my ($dpl,$dpoff,$l) = (length($$dp), 0, "");
  my $prev_value;
  my $prev_timestamp;
  my $next_value;
  my $next_timestamp;
  while($dpoff < $dpl) {                # using split instead is memory hog
    my $ndpoff = index($$dp, "\n", $dpoff);
    if($ndpoff == -1) {
      $l = substr($$dp, $dpoff);
    } else {
      $l = substr($$dp, $dpoff, $ndpoff-$dpoff);
    }

    if($l =~ m/^#/) {
      $comment .= "$l\n";
    } else {
      my ($d, $v) = split(" ", $l);

      my $sec = SVG_time_to_sec($d);
      if( $sec < $from ) {
         $prev_timestamp = $d;
         $prev_value = $v;

      } elsif( $sec > $to ) {
         if( !$next_value ) {
           $next_timestamp = $d;
           $next_value = $v;
         }

      } else {
        if( !$ret && $sec > $from && defined($prev_value) ) {

          my $value = $prev_value;
          $value = logProxy_linearInterpolate( SVG_time_to_sec($prev_timestamp), $prev_value, SVG_time_to_sec($d), $v, $from ) if( $interpolate );

          $min = $value if( $value < $min );
          $max = $value if( $value > $max );

          my @t = localtime($from);
          my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
          $ret .= "$timestamp $value\n";
        }
        $min = $v if( $v < $min );
        $max = $v if( $v > $max );

        $ret .= "$l\n";

        $prev_timestamp = $d;
        $prev_value = $v;

      }
    }

    $dpoff = $ndpoff+1;
    last if($ndpoff == -1);
  }

  #if predict is set -> extend bejond last value
  if( defined($predict) && !defined($next_value) ) {
    $next_value = $prev_value;

    my $sec = SVG_time_to_sec($prev_timestamp);
    if( !$ret && $sec < $from && defined($prev_value) ) {
      my @t = localtime($from);
      my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
      $ret .= "$timestamp $prev_value\n";
    }

    #if $predict = 0 -> predict to end of plot
    my $time = $to;
    #else predict by $predict
    $time = SVG_time_to_sec($prev_timestamp) + $predict if( $predict );

    #but not later than now
    my ($now) = gettimeofday();
    $to = minNum( $time, $now );

    my @t = localtime($to);
    $next_timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
  }

  if( defined($next_value) ) {
    my $value = $prev_value;
    $value = logProxy_linearInterpolate( SVG_time_to_sec($prev_timestamp), $prev_value, SVG_time_to_sec($next_timestamp), $next_value, $to ) if( $interpolate );
    $min = $value if( $value < $min );
    $max = $value if( $value > $max );

    my @t = localtime($to);
    my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
    $ret .= "$timestamp $value\n";
  }

  $ret .= $comment;

  return (\$ret, $min, $max);
}

#parse plot data to array
sub
logProxy_data2Array($)
{
  my ($dp) = @_;

  my @ret = ();
  my $comment;

  my ($dpl,$dpoff,$l) = (length($$dp), 0, "");
  while($dpoff < $dpl) {                # using split instead is memory hog
    my $ndpoff = index($$dp, "\n", $dpoff);
    if($ndpoff == -1) {
      $l = substr($$dp, $dpoff);
    } else {
      $l = substr($$dp, $dpoff, $ndpoff-$dpoff);
    }

    if($l =~ m/^#/) {
      $comment .= "$l\n";
    } else {
      my ($d, $v) = split(" ", $l);

      my $sec = SVG_time_to_sec($d);

      push( @ret, [$sec, $v, $d] );
    }

    $dpoff = $ndpoff+1;
    last if($ndpoff == -1);
  }

  return (\@ret,$comment);
}
#create plot data from array
sub
logProxy_array2Data($$)
{
  my ($array,$comment) = @_;
  my $ret = "";

  my $min = 999999;
  my $max = -999999;
  my $last;

  return ($ret,$min,$max,$last) if( !ref($array) eq "ARRAY" );

  foreach my $point ( @{$array} ) {
    my @t = localtime($point->[0]);
    my $timestamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

    my $value = $point->[1];
    $min = $value if( $value < $min );
    $max = $value if( $value > $max );
    $last = $value;

    $ret .= $timestamp . " " . $value ."\n";
  }

  $ret .= $comment;

  return (\$ret,$min,$max,$last);
}
#create plot data from xy-array
sub
logProxy_xy2Plot($)
{
  my ($array) = @_;
  my $ret = ";c 0\n";

  my $min = 999999;
  my $max = -999999;
  my $last;
  my $xmin = 999999;
  my $xmax = -999999;

  return ($ret,$min,$max,$last) if( !ref($array) eq "ARRAY" );

  foreach my $point ( @{$array} ) {
    my $x = $point->[0];
    my $value = $point->[1];

    $min = $value if( $value < $min );
    $max = $value if( $value > $max );
    $last = $value;
    $xmin = $x if( $x < $xmin );
    $xmax = $x if( $x > $xmax );

    $ret .= ";p $x $value\n";
  }

  return ($ret,$min,$max,$last,$xmin,$xmax);
}
#create plot data from xy-file
#assume colums separated by whitespace and x,y pairs separated by comma
sub
logProxy_xyFile2Plot($$$)
{
  my ($filename, $column, $regex)= @_;
  my @array;

  $filename =~ s/%L/$attr{global}{logdir}/g
    if($filename =~ m/%L/ && $attr{global}{logdir});
  if (open(F, "<$filename")) {
    while(<F>) {
          chomp;
          if(/$regex/) {
            my @a= split(/\s/,$_);
            my @pp= split(";", $a[$column-1]);
            map { my @p= split(",", $_); push @array, \@p; } @pp;
          }
    }
    close(F);
  }
  return logProxy_xy2Plot(\@array);
}
#create plot data from date-y-array
sub
logProxy_values2Plot($)
{
  my ($array) = @_;
  my $ret = ";c 0\n";

  my $min = 999999;
  my $max = -999999;
  my $last;

  return ($ret,$min,$max,$last) if( !ref($array) eq "ARRAY" );

  foreach my $point ( @{$array} ) {
    $ret .= "$point->[0] $point->[1]\n";
  }

  return ($ret,$min,$max,$last);
}
sub
logProxy_Get($@)
{
  my ($hash, $name, @a) = @_;
#Log 3, "logProxy_Get";
#Log 3, Dumper @a;

  my $inf  = shift @a;
  my $outf = shift @a;
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my $internal;

  if($outf && $outf eq "INT") {
    $outf = "-";
    $internal = 1;
  }


  my $ret = "";
  my %data;
  for(my $i = 0; $i < int(@a); $i++) {

    my $j = $i+1;
    $data{"min$j"} = undef;
    $data{"max$j"} = undef;
    $data{"avg$j"} = undef;
    $data{"sum$j"} = 0;
    $data{"cnt$j"} = undef;
    $data{"currval$j"} = 0;
    $data{"currdate$j"} = undef;
    $data{"mindate$j"} = undef;
    $data{"maxdate$j"} = undef;
    $data{"xmin$j"} = undef;
    $data{"xmax$j"} = undef;

    my @fld = split(":", $a[$i]);

    if( $a[$i] =~ m/^(FileLog|DbLog):([^:]*):(.*)/ ) {
      my @options = split( ',', $fld[1] );
      my $log_dev = shift(@options);
      my $infile = $fld[0] eq "DbLog" ? "HISTORY" : "CURRENT";
      my $column_specs = $3;

      my $extend;
      my $extend_scale;
      my $offset;
      my $offset_scale;
      my $interpolate;
      my $clip;
      my $predict;
      my $postFn;
      my $scale2reading;

      if( !defined($defs{$log_dev}) ) {
        Log3 $hash->{NAME}, 1, "$hash->{NAME}: $log_dev does not exist";
        $ret .= "#$a[$i]\n";
        next;
      }

      while (@options) {
        my $option = shift(@options);
        while ($option && $option =~ m/=\{/ && $option !~ m/>}/ ) {
          my $next = shift(@options);
          last if( !defined($next) );
          $option .= ",". $next;
        }

        my ($name,$value) = split( '=', $option, 2 );

        if( $value ) {
          $value = eval $value;

          if( $@ ) {
            Log3 $hash->{NAME}, 1, "$hash->{NAME}: $option: $@";
            $ret .= "#$a[$i]\n";
            next;
          }
        }

        if( $name eq "extend" ) {
          $value =~ m/(-?\d*)(m?)/;

          $extend = $1;
          $extend_scale = $2;
          $extend_scale = "" if( !$extend_scale );

          $clip = 1;

        } elsif( $name eq "offset" ) {
          $value =~ m/(-?\d*)(m?)/;

          $offset = $1;
          $offset_scale = $2;
          $offset_scale = "" if( !$offset_scale );

        } elsif( $name eq "interpolate" ) {
          $interpolate = 1;

        } elsif( $name eq "clip" ) {
          $clip = 1;

        } elsif( $name eq "predict" ) {
          $predict = 0;
          $predict = $value if( defined($value) );

        } elsif( $name eq "postFn" ) {
          $postFn = $value;

        } elsif( $name eq "scale2reading" ) {
          $scale2reading = $value if( defined($value) );

        } else {
          Log3 $hash->{NAME}, 2, "$hash->{NAME}: line $i: $fld[0]: unknown option >$option<";

        }
      }

      my $fromsec = SVG_time_to_sec($from);
      my $tosec   = SVG_time_to_sec($to);

      my $from = $from;
      my $to = $to;
      # shift $from and $to
      $from = logProxy_shiftTime($from,-$offset.$offset_scale) if( $offset );
      $to = logProxy_shiftTime($to,-$offset.$offset_scale) if( $offset );

      # extend query range
      $from = logProxy_shiftTime($from,-$extend.$extend_scale) if( $extend );
      $to = logProxy_shiftTime($to,$extend.$extend_scale) if( $extend );

      # zoom dependent reading
      if( $scale2reading ) {
        my @fld = split(':', $column_specs, 3);

        my $reading;
        my $zoom = logProxy_Range2Zoom($tosec-$fromsec);
        if( ref($scale2reading) eq "HASH" ) {
          $reading = $scale2reading->{$zoom};
          $reading = $scale2reading->{"$fld[1].$zoom"} if( defined($scale2reading->{"$fld[1].$zoom"}) );
        } elsif($scale2reading =~ m/^{.*}$/) {
        } else {
          no strict "refs";
          $reading = eval {&{$scale2reading}($zoom,$fld[1])};
          use strict "refs";
          if( $@ ) {
            Log3 $hash->{NAME}, 1, "$hash->{NAME}:readingOfScale $a[$i]: $@";
          }
        }

        if( $reading
            && $reading ne $fld[1] ) {
          Log3 $hash->{NAME}, 4, "$hash->{NAME}:scale $zoom: using $reading instead of $fld[1]";
          $fld[1] = $reading;
          $column_specs = join( ':', @fld );
        } else {
          Log3 $hash->{NAME}, 5, "$hash->{NAME}:scale $zoom: keeping $fld[1]";
        }
      }

      $internal_data = "";
      my $cmd = "get $log_dev $infile INT $from $to $column_specs";
      Log3 $hash->{NAME}, 4, "$hash->{NAME}: calling $cmd";
      FW_fC($cmd, 1);

      # shift data and specials back
      logProxy_shiftData($internal_data,$offset.$offset_scale) if( $offset );
      $main::data{"currdate1"} = logProxy_shiftTime($main::data{"currdate1"},$offset.$offset_scale) if( $offset );

      # clip extended query range to plot range
      if( $clip || defined($predict) ) {
        ($internal_data,$main::data{"min1"},$main::data{"max1"}) = logProxy_clipData($internal_data,$fromsec,$tosec,$interpolate,$predict);
      }

      #call postprocessing function
      if( $postFn ) {
        my($data,$comment) = logProxy_data2Array($internal_data);

        $main::data{"avg1"} = undef;
        $main::data{"sum1"} = undef;
        $main::data{"cnt1"} = int(@{$data});
        $main::data{"currdate1"} = undef;
        $main::data{"mindate1"} = undef;
        $main::data{"maxdate1"} = undef;

        no strict "refs";
        my $d = eval {&{$postFn}($a[$i],$data)};
        use strict "refs";
        if( $@ ) {
          Log3 $hash->{NAME}, 1, "$hash->{NAME}: postFn: $a[$i]: $@";
          $ret .= "#$a[$i]\n";
          next;
        }

        $data = $d;

        $comment = "#$a[$i]\n";
        ($internal_data,$main::data{"min1"},$main::data{"max1"},$main::data{"currval1"}) = logProxy_array2Data($data,$comment);
      }

      if( ref($internal_data) eq "SCALAR" && $$internal_data ) {
        $ret .= $$internal_data;

        $data{"min$j"} = $main::data{"min1"};
        $data{"max$j"} = $main::data{"max1"};
        $data{"avg$j"} = $main::data{"avg1"};
        $data{"sum$j"} = $main::data{"sum1"};
        $data{"cnt$j"} = $main::data{"cnt1"};
        $data{"currval$j"} = $main::data{"currval1"};
        $data{"currdate$j"} = $main::data{"currdate1"};
        $data{"mindate$j"} = $main::data{"mindate1"};
        $data{"maxdate$j"} = $main::data{"maxdate1"};

      } else {
        $ret .= "#$a[$i]\n";

      }

      next;
    } elsif( $fld[0] eq "ConstX" && $fld[1] ) {
      $fld[1] = join( ':', @fld[1..@fld-1]);
      my ($t,$y,$y2) = eval $fld[1];
      if( $@ ) {
        Log3 $hash->{NAME}, 1, "$hash->{NAME}: $fld[1]: $@";
        $ret .= "#$a[$i]\n";
        next;
      }

      if( !$t || !defined($y) || $y eq "undef" ) {
        $ret .= "#$a[$i]\n";
        next;
      }

      $t =~ s/ /_/;

      my $from = $t;
      my $to = $t;
      $y2 = $y if( !defined($y2) );

      $data{"min$j"} = $y > $y2 ? $y2 : $y;
      $data{"max$j"} = $y > $y2 ? $y : $y2;
      $data{"avg$j"} = ($y+$y2)/2;
      $data{"cnt$j"} = $y != $y2 ? 2 : 1;
      $data{"curdval$j"} = $y2;
      $data{"curddate$j"} = $to;
      $data{"maxdate$j"} = $to;
      $data{"mindate$j"} = $to;

      $ret .= "$from $y\n";
      $ret .= "$to $y2\n";
      $ret .= "#$a[$i]\n";
      next;

    } elsif( $fld[0] eq "ConstY" && defined($fld[1]) ) {
      $fld[1] = join( ':', @fld[1..@fld-1]);
      my ($y,$f,$t) = eval $fld[1];
      if( $@ ) {
        Log3 $hash->{NAME}, 1, "$hash->{NAME}: $fld[1]: $@";
        $ret .= "#$a[$i]\n";
        next;
      }

      if( !defined($y) || $y eq "undef" ) {
        $ret .= "#$a[$i]\n";
        next;
      }

      $f =~ s/ /_/ if( $f );
      $t =~ s/ /_/ if( $t );

      my $from = $from;
      $from = $f if( $f );
      my $to = $to;
      $to = $t if( $t );

      $data{"min$j"} = $y;
      $data{"max$j"} = $y;
      $data{"avg$j"} = $y;
      $data{"cnt$j"} = 2;
      $data{"currval$j"} = $y;
      $data{"currdate$j"} = $to;
      $data{"maxdate$j"} = $to;
      $data{"mindate$j"} = $to;

      $ret .= "$from $y\n";
      $ret .= "$to $y\n";
      $ret .= "#$a[$i]\n";
      next;

    } elsif( $fld[0] eq "Func" && $fld[1] ) {
      $fld[1] = join( ':', @fld[1..@fld-1]);
      #my $fromsec = SVG_time_to_sec($from);
      #my $tosec   = SVG_time_to_sec($to);
      my ($r,$min,$max,$last,$xmin,$xmax) = eval $fld[1];
      if( $@ ) {
        Log3 $hash->{NAME}, 1, "$hash->{NAME}: $fld[1]: $@";
        next;
      }

      $data{"min$j"} = $min;
      $data{"max$j"} = $max;
      $data{"currval$j"} = $last;
      $data{"xmin$j"} = $xmin;
      $data{"xmax$j"} = $xmax;

      $ret .= $r;
      $ret .= "#$a[$i]\n";
      next;

    } elsif( $fld[0] eq "Polar" ) {

      my $axis;
      my $noaxis;
      my $range;
      my $segments;
      my $isolines = "10|20|30";
      my @options = split( ',', $fld[1] );
      foreach my $option ( @options[0..@options-1] ) {
        my ($name,$value) = split( '=', $option, 2 );

        if( $value ) {
          $value = eval $value;

          if( $@ ) {
            Log3 $hash->{NAME}, 1, "$hash->{NAME}: $option: $@";
            $ret .= "#$a[$i]\n";
            next;
          }
        }

        if( $name eq "axis" ) {
          $axis = 1;

        } elsif( $name eq "noaxis" ) {
          $noaxis = 1;

        } elsif( 0 && $name eq "isolines" && defined($value) ) {
          $isolines = $value;

        } elsif( $name eq "segments" && defined($value) ) {
          $segments = $value;

        } elsif( $name eq "range" && defined($value) ) {
          $range = $value;

        } else {
          Log3 $hash->{NAME}, 2, "$hash->{NAME}: line $i: $fld[0]: unknown option >$option<";

        }
      }

      my $values;
      if( defined( $fld[2] ) ) {
        $fld[2] = join( ':', @fld[2..@fld-1]);
        $values = eval $fld[2];
        if( $@ ) {
          Log3 $hash->{NAME}, 1, "$hash->{NAME}: $fld[2]: $@";
          next;
        }
      }
      next if( !$values && !$segments );
      next if( $values && ref($values) ne "ARRAY" );

      $segments = scalar @{$values} if( !$segments );
      next if( !$segments );
      my $isText = $values && @{$values}[0] !~ m/^[.\d+-]*$/;

      $axis = 1 if( $isText );
      $axis = 1 if( !defined($values) && $segments );

      my $f = 3.14159265 / 180;
      if( $segments && defined( $values ) ) {
        my $segment = 0;
        my $first;
        $ret .= ";c 0\n";
        for( my $a = 0; $a < 360; $a += (360/$segments) ) {
          my $value = @{$values}[$segment++];
          next if( !defined($value) );

          my $r;
          if( $isText ) {
            $r = 32;
            $r = 34 if( $a > 90 && $a < 270 );
          } else {
            $r = $value;
          }

          my $x = sin( $a * $f );
          my $y = cos( $a * $f );

          $x *= $r;
          $y *= $r;

          if( $value =~ m/^[.\d+-]*$/ ) {
            $ret .= ";p $x $y\n";
            $first .= ";p $x $y\n" if( !$first );
          } else {
            my $align = "middle";
            #$align = "start" if( $a > 30 && $a < 150 );
            #$align = "end" if( $a > 210 && $a < 330 );
            $align = "start" if( $a > 0 && $a < 180 );
            $align = "end" if( $a > 180 && $a < 360 );

            $ret .= ";t $x $y $align $value\n";
          }
        }
        $ret .= $first if( $first );

      }

      if( $axis && !$noaxis ) {
        my $axis;
        $ret .= ";\n" if( $ret );
        $ret .= ";ls l7\n";
        foreach my $r (split( '\|', $isolines)) {
          $ret .= ";\n"; #FIXME: this is one to many at the end...
          my $first;
          for( my $a = 0; $a < 360; $a += (360/$segments) ) {
            my $x = sin( $a * $f );
            my $y = cos( $a * $f );

            $x *= $r;
            $y *= $r;

            $ret .= ";p $x $y\n";
            $ret .= ";t $x $y start $r\n" if( $a == 0 && ( $r == 10 || $r == 20 ) ) ;

            $first .= ";p $x $y\n" if( !$first );

            if( $r == 30 ) {
              $axis .= ";\n" if( $axis );
              $axis .= ";p 0 0\n";
              $axis .= ";p $x $y\n";
            }
          }
          $ret .= $first;
        }

        $ret .= ";\n";
        $ret .= $axis;

      }

      $ret .= "#$a[0]\n";

    } else {
      Log3 $name, 2, "$name: unknown keyword $fld[0] in column_spec, must be one of $logProxy_columns";

    }
  }

  for(my $i = 0; $i < int(@a); $i++) {
    my $j = $i+1;
    $main::data{"min$j"} = $data{"min$j"};
    $main::data{"max$j"} = $data{"max$j"};
    $main::data{"avg$j"} = $data{"avg$j"};
    $main::data{"sum$j"} = $data{"sum$j"};
    $main::data{"cnt$j"} = $data{"cnt$j"};
    $main::data{"currval$j"} = $data{"currval$j"};
    $main::data{"currdate$j"} = $data{"currdate$j"};
    $main::data{"mindate$j"} = $data{"mindate$j"};
    $main::data{"maxdate$j"} = $data{"maxdate$j"};
    $main::data{"xmin$j"} = $data{"xmin$j"};
    $main::data{"xmax$j"} = $data{"xmax$j"};
  }

#Log 3, Dumper $ret;

  if( $internal ) {
    $internal_data = \$ret;
    return undef;
  }

  return $ret;
}

1;

=pod
=item helper
=item summary    manipulate the date to be plotted in an SVG device
=item summary_DE manipulation von mit SVG zu plottenden SVG Daten
=begin html

<a name="logProxy"></a>
<h3>logProxy</h3>
<ul>
  Allows the manipulation of data to be plotted in an SVG device:
  <ul>
    <li>addition of horizontal lines at fixed values</li>
    <li>addition of horizontal lines at dynamic values eg: min, max or average values of another plot </li>
    <li>addition of vertical lines at fixed or dynamic times between two fixed or dynamic y values</li>
    <li>addition of calculated data like week profiles of HeatingControll devices or heating thermostats</li>
    <li>merge plot data from different sources. eg. different FileLog devices</li>
    <li>horizontaly shifting a (merged) plot to align average or statistic data to the correct day,week and month</li>
  </ul>
  <br>

  <a name="logProxy_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; logProxy</code><br>
    <br>
    Only one logProxy device can be defined and is needed.<br><br>

    Example:
    <ul>
      <code>define myProxy logProxy</code><br>
    </ul>
  </ul><br>

  <a name="logProxy_Set"></a>
    <b>Set</b>
    <ul>
    </ul><br>

  <a name="logProxy_Get"></a>
    <b>Get</b>
    <ul>
      see <a href="#FileLogget">FileLog</a> and <a href="#DbLogget">DbLog</a>
    </ul><br>

  <a name="logProxy_Attr"></a>
    <b>Attributes</b>
    <ul>
    </ul><br>
  <br>

  <b>#logProxy &lt;column_spec&gt;</b><br>
  where &lt;column_spec&gt; can be one or more of the following:
  <ul>
    <li>FileLog:&lt;log device&gt;[,&lt;options&gt;]:&lt;column_spec&gt;<br></li>
    <li>DbLog:&lt;log device&gt;[,&lt;options&gt;]:&lt;column_spec&gt;<br></li><br>
      options is a comma separated list of zero or more of:<br>
        <ul>
          <li>clip<br>
            clip the plot data to the plot window</li>
          <li>extend=&lt;value&gt;<br>
            extend the query range to the log device by &lt;value&gt; seconds (or &lt;value&gt; months if &lt;value&gt; ends in m).
            also activates cliping.</li>
          <li>interpolate<br>
            perform a linear interpolation to the values in the extended range to get the values at the plot boundary. only usefull
            if plotfunction is lines.</li>
          <li>offset=&lt;value&gt;<br>
            shift plot by &lt;value&gt; seconds (or &lt;value&gt; months if &lt;value&gt; ends in m).
            allows alignment of values calculated by average or statsitics module to the correct day, week or month.  </li>
          <li>predict[=&lt;value&gt;]<br>
            no value -> extend the last plot value to now.<br>
            value -> extend the last plot value by &lt;value&gt; but maximal to now.<br></li>
          <li>postFn='&lt;myPostFn&gt;'<br>
            myPostFn is the name of a postprocessing function that is called after all processing of the data by logProxy
            has been done. it is called with two arguments: the devspec line from the gplot file and a reference to a data
            array containing the points of the plot. each point is an array with three components: the point in time in seconds,
            the value at this point and the point in time in string form. the return value must return a reference to an array
            of the same format. the third component of each point can be omittet and is not evaluated.<br></li>
          <li>scale2reading=&lt;scaleHashRef&gt;<br>
            Use zoom step dependent reading names. <br>
            The reading name to be used is the result of a lookup with the current zoom step into <code>scaleHashRef</code>.
            The keys can be from the following list: year, month, week, day, qday, hour<br>
            Example:
            <ul>
              <code>#logProxy DbLog:dbLog,scale2reading={year=>'temperature_avg_day',month=>'temperature_avg_day'}:s300ht_1:temperature::</code><br>
            </ul><br>

            <br></li>
        </ul>

    <li>ConstX:&lt;time&gt;,&lt;y&gt;[,&lt;y2&gt;]<br>
      Will draw a vertical line (or point) at &lt;time&gt; between &lt;y&gt; to &lt;y2&gt;.<br>
      Everything after the : is evaluated as a perl expression that hast to return one time string and one or two y values.<br>
      Examples:
      <ul>
        <code>#logProxy ConstX:$data{currdate1},$data{currval1}</code><br>
        <code>#logProxy ConstX:$data{mindate1},$data{min1},$data{avg1}</code><br>
        <code>#logProxy ConstX:$data{maxdate1},$data{max1},$data{avg1}</code><br>
        <code>#logProxy ConstX:logProxy_shiftTime($from,60*60*2),$data{min1},$data{max1}</code><br>
      </ul></li><br>

    <li>ConstY:&lt;value&gt;[,&lt;from&gt;[,&lt;to&gt;]]<br>
      Will draw a horizontal line at &lt;value&gt;, optional only between the from and to times.<br>
      Everything after the : is evaluated as a perl expression that hast to return one value and optionaly one or two time strings.<br>
      Examples:
      <ul>
        <code>#logProxy ConstY:0</code><br>
        <code>#logProxy ConstY:1234+15+myFunc(123)</code><br>
        <code>#logProxy ConstY:$data{avg1}</code><br>
        <code>#logProxy ConstY:$data{avg2},$from,$to</code><br>
        <code>#logProxy ConstY:$data{avg2},logProxy_shiftTime($from,60*60*12),logProxy_shiftTime($from,-60*60*12)</code>
      </ul></li><br>

    <li>Polar:[&lt;options&gt;]:&lt;values&gt;<br>
      Will draw a polar/spiderweb diagram with the given values. &lt;values&gt; has to evaluate to a perl array.<br>
      If &lt;values&gt; contains numbers these values are plottet and the last value will be connected to the first.<br>
      If &lt;values&gt; contains strings these strings are used as labels for the segments.<br>
      The axis are drawn automaticaly if the values are strings or if no values are given but the segments option is set.<br>
      The corrosponding SVG device should have the plotsize attribute set (eg: attr &lt;mySvg&gt; plotsize 340,300) and the used gplot file has to contain xrange and yrange entries and the x- and y-axis labes should be switched off with xtics, ytics  and y2tics entries.<br>
      The following example will plot the temperature and desiredTemperature values of all devices named MAX.*:
      <ul>
        <code>set xtics ()</code><br>
        <code>set ytics ()</code><br>
        <code>set y2tics ()</code><br>

        <code>set xrange [-40:40]</code><br>
        <code>set yrange [-40:40]</code><br><br>

        <code>#logProxy Polar::{[map{ReadingsVal($_,"temperature",0)}devspec2array("MAX.*")]}</code><br>
        <code>#logProxy Polar::{[map{ReadingsVal($_,"desiredTemperature",0)}devspec2array("MAX.*")]}</code><br>
        <code>#logProxy Polar::{[map{ReadingsVal($_,"temperature",0)}devspec2array("MAX.*")]}</code><br>
        <code>#logProxy Polar::{[devspec2array("MAX.*")]}</code><br><br>

        <code>plot "&lt;IN&gt;" using 1:2 axes x1y1 title 'Ist' ls l0 lw 1 with lines,\</code><br>
        <code>plot "&lt;IN&gt;" using 1:2 axes x1y1 title 'Soll' ls l1fill lw 1 with lines,\</code><br>
        <code>plot "&lt;IN&gt;" using 1:2 axes x1y1 notitle ls l0 lw 1 with points,\</code><br>
        <code>plot "&lt;IN&gt;" using 1:2 axes x1y1 notitle  ls l2 lw 1 with lines,\</code><br>
      </ul><br>
      options is a comma separated list of zero or more of:<br>
        <ul>
          <li>axis<br>
            force to draw the axis</li>
          <li>noaxis<br>
            disable to draw the axis</li>
          <li>range=&lt;value&gt;<br>
            the range to use for the radial axis</li>
          <li>segments=&lt;value&gt;<br>
            the number of circle/spiderweb segments to use for the plot</li>
          <li>isolines=&lt;value&gt;<br>
            a | separated list of values for which an isoline shoud be drawn. defaults to 10|20|30.</li>
        </ul>
      </li><br>

    <li>Func:&lt;perl expression&gt;<br>
      Specifies a perl expression that returns the data to be plotted and its min, max and last value. It can not contain
      space or : characters. The data has to be
      one string of newline separated entries of the form: <code>yyyy-mm-dd_hh:mm:ss value</code><br>Example:
      <ul>
        <code>#logProxy Func:logProxy_WeekProfile2Plot("HCB",$from,$to)</code><br>
        <code>#logProxy Func:logProxy_WeekProfile2Plot("myHeatingControll",$from,$to,"(\\d)*\$")</code><br>
        <code>#logProxy Func:logProxy_Func2Plot($from,$to,'{logProxy_hms2dec(sunrise_abs_dat($sec))}')</code><br>
        <code>#logProxy Func:logProxy_Func2Plot($from,$to,'{logProxy_hms2dec(sunset_abs_dat($sec))}')</code><br>
      </ul><br>
      Notes:<ul>
        <li>logProxy_WeekProfile2Plot is a sample implementation of a function that will plot the week profile
          of a Heating_Control, WeekdyTimer, HomeMatic or MAX Thermostat device can be found in the 98_logProxy.pm module file.</li>
        <li>logProxy_Func2Plot($from,$to,$func) is a sample implementation of a function that will evaluate the given
          function (3rd parameter) for a zoom factor dependent number of times. the current time is given in $sec.
          the step width can be given in an optional 4th parameter. either as a number or as an hash with the keys from
          the following list: hour,qday,day,week,month,year and the values representing the step with for the zoom level.</li>
        <li>logProxy_xy2Plot(\@xyArray) is a sample implementation of a function that will accept a ref to an array
          of xy-cordinate pairs as the data to be plotted.</li>
        <li>logProxy_xyFile2Plot($filename,$column,$regex) is a sample implementation of a function that will accept a filename,
            a column number and a regular expression. The requested column in all lines in the file that match the regular expression
            needs to be in the format x,y to indicate the xy-cordinate pairs as the data to be plotted.</li>
        <li>logProxy_values2Plot(\@xyArray) is a sample implementation of a function that will accept a ref to an array
          of date-y-cordinate pairs as the data to be plotted.</li>
        <li>The perl expressions have access to $from and $to for the begining and end of the plot range and also to the
          SVG specials min, max, avg, cnt, sum, currval (last value) and currdate (last date) values of the individual curves
          already plotted are available as $data{&lt;special-n&gt;}.<br>
        <li>logProxy_Range2Zoom($seconds) can be used to get the approximate zoom step for a plot range of $seconds.</li>
        <li>SVG_time_to_sec($timestamp) can be used to convert the timestamp strings to epoch times for calculation.</li>
        </ul>
      </li><br>
      </li><br>

    </ul>
    Please see also the column_spec paragraphs of FileLog, DbLog and SVG.<br>
  <br>
  NOTE: spaces are not allowed inside the colums_specs.<br>
  <br>
  To use any of the logProxy features with an existing plot the associated SVG file hast to be changed to use the logProxy
  device and the  .gplot file has to be changed in the following way:<br>
  All existing #FileLog and #Dblog lines have to be changed to #logProxy lines and<br>the column_spec of these line has to
  be prepended by <code>FileLog:&lt;log device&gt;:</code> or <code>DbLog:&lt;log device&gt;:</code> respectively.<br>
  Examples:
  <ul>
    <code>#DbLog &lt;myDevice&gt;:&lt;myReading&gt;</code></br>
    <code>#FileLog 4:&lt;SPEC1&gt;:power\x3a::</code><br>
    <code>#FileLog 4:&lt;SPEC1&gt;:consumption\x3a::</code><br><br>
    will become:<br><br>
    <code>#logProxy DbLog:&lt;myDb&gt;:&lt;myDevice&gt;:&lt;myReading&gt;</code></br>
    <code>#logProxy FileLog:FileLog_&lt;SPEC1&gt;:4:&lt;SPEC1&gt;.power\x3a::</code><br>
    <code>#logProxy FileLog:FileLog_&lt;SPEC1&gt;:4:&lt;SPEC1&gt;.consumption\x3a::</code><br>
  </ul>

</ul>

=end html
=cut
