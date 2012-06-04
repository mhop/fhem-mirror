##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::File;
#use Devel::Size qw(size total_size);

sub seekTo($$$$);

#####################################
sub
FileLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FileLog_Define";
  $hash->{SetFn}    = "FileLog_Set";
  $hash->{GetFn}    = "FileLog_Get";
  $hash->{UndefFn}  = "FileLog_Undef";
  $hash->{NotifyFn} = "FileLog_Log";
  $hash->{AttrFn}   = "FileLog_Attr";
  # logtype is used by the frontend
  $hash->{AttrList} = "disable:0,1 logtype nrarchive archivedir archivecmd";
}


#####################################
sub
FileLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  return "wrong syntax: define <name> FileLog filename regexp" if(int(@a) != 4);

  eval { "Hallo" =~ m/^$a[3]$/ };
  return "Bad regexp: $@" if($@);

  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  $fh = new IO::File ">>$f";
  return "Can't open $f: $!" if(!defined($fh));

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[3];
  $hash->{logfile} = $a[2];
  $hash->{currentlogfile} = $f;
  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
FileLog_Undef($$)
{
  my ($hash, $name) = @_;
  close($hash->{FH});
  return undef;
}

sub
FileLog_Switch($)
{
  my ($log) = @_;

  my $fh = $log->{FH};
  my @t = localtime;
  my $cn = ResolveDateWildcards($log->{logfile},  @t);

  if($cn ne $log->{currentlogfile}) { # New logfile
    $fh->close();
    HandleArchiving($log);
    $fh = new IO::File ">>$cn";
    if(!defined($fh)) {
      Log(0, "Can't open $cn");
      return;
    }
    $log->{currentlogfile} = $cn;
    $log->{FH} = $fh;
  }

}

#####################################
sub
FileLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;

  my $ln = $log->{NAME};
  return if($attr{$ln} && $attr{$ln}{disable});

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
      my $t = TimeNow();
      $t = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
      $t =~ s/ /_/; # Makes it easier to parse with gnuplot

      FileLog_Switch($log);

      my $fh = $log->{FH};
      print $fh "$t $n $s\n";
      $fh->flush;
      $fh->sync if !($^O eq 'MSWin32'); #not implemented in Windows
    }
  }
  return "";
}

###################################
sub
FileLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

###################################
sub
FileLog_Set($@)
{
  my ($hash, @a) = @_;
  
  return "no set argument specified" if(int(@a) != 2);
  return "Unknown argument $a[1], choose one of reopen"
        if($a[1] ne "reopen");

  my $fh = $hash->{FH};
  my $cn = $hash->{currentlogfile};
  $fh->close();
  $fh = new IO::File ">>$cn";
  return "Can't open $cn" if(!defined($fh));
  $hash->{FH} = $fh;
  return undef;
}

###################################
# We use this function to be able to scroll/zoom in the plots created from the
# logfile.  When outfile is specified, it is used with gnuplot post-processing,
# when outfile is "-" it is used to create SVG graphics
#
# Up till now following functions are impemented:
# - int (to cut off % from a number, as for the actuator)
# - delta-h / delta-d to get rain/h and rain/d values from continuous data.
#
# It will set the %data values
#  min<x>, max<x>, avg<x>, cnt<x>, currdate<x>, currval<x>, sum<x>
# for each requested column, beginning with <x> = 1

sub
FileLog_Get($@)
{
  my ($hash, @a) = @_;
  
  return "Usage: get $a[0] <infile> <outfile> <from> <to> <column_spec>...\n".
         "  where column_spec is <col>:<regexp>:<default>:<fn>\n" .
         "  see the FileLogGrep entries in he .gplot files\n" .
         "  <infile> is without direcory, - means the current file\n" .
         "  <outfile> is a prefix, - means stdout\n"
        if(int(@a) < 5);
  shift @a;
  my $inf  = shift @a;
  my $outf = shift @a;
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my $internal;
  if($outf eq "INT") {
    $outf = "-";
    $internal = 1;
  }

  FileLog_Switch($hash);
  if($inf eq "-") {
    $inf = $hash->{currentlogfile};

  } else {
    # Look for the file in the log directory...
    my $linf = "$1/$inf" if($hash->{currentlogfile} =~ m,^(.*)/[^/]*$,);
    return undef if(!$linf);
    if(!-f $linf) {
      # ... or in the archivelog
      $linf = AttrVal($hash->{NAME},"archivedir",".") ."/". $inf;
      return "Error: cannot access $linf" if(!-f $linf);
    }
    $inf = $linf;
  }
  my $ifh = new IO::File $inf;
  seekTo($inf, $ifh, $hash, $from);

  #############
  # Digest the input.
  # last1: first delta value after d/h change
  # last2: last delta value recorded (for the very last entry)
  # last3: last delta timestamp (d or h)
  my (@d, @fname);
  my (@min, @max, @sum, @cnt, @lastv, @lastd);

  for(my $i = 0; $i < int(@a); $i++) {
    my @fld = split(":", $a[$i], 4);

    my %h;
    if($outf ne "-") {
      $fname[$i] = "$outf.$i";
      $h{fh} = new IO::File "> $fname[$i]";
    }
    $h{re} = $fld[1];                                   # Filter: regexp
    $h{df} = defined($fld[2]) ? $fld[2] : "";           # default value
    $h{fn} = $fld[3];                                   # function
    $h{didx} = 10 if($fld[3] && $fld[3] eq "delta-d");  # delta idx, substr len
    $h{didx} = 13 if($fld[3] && $fld[3] eq "delta-h");

    if($fld[0] =~ m/"(.*)"/o) {
      $h{col} = $1;
      $h{type} = 0;
    } else {
      $h{col} = $fld[0]-1;
      $h{type} = 1;
    }
    if($h{fn}) {
      $h{type} = 4;
      $h{type} = 2 if($h{didx});
      $h{type} = 3 if($h{fn} eq "int");
    }
    $h{ret} = "";
    $d[$i] = \%h;
    $min[$i] =  999999;
    $max[$i] = -999999;
    $sum[$i] = 0;
    $cnt[$i] = 0;
    $lastv[$i] = 0;
    $lastd[$i] = "undef";
  }

  my %lastdate;
  my $d;                    # Used by eval functions

  my ($rescan, $rescanNum, $rescanIdx, @rescanArr);
  $rescan = 0;

RESCAN:
  for(;;) {
    my $l;

    if($rescan) {
      last if($rescanIdx<1 || !$rescanNum);
      $l = $rescanArr[$rescanIdx--];
    } else {
      $l = <$ifh>;
      last if(!$l);
    }

    next if($l lt $from && !$rescan);
    last if($l gt $to);
    my @fld = split("[ \r\n]+", $l);     # 40% CPU

    for my $i (0..int(@a)-1) {           # Process each req. field
      my $h = $d[$i];
      next if($rescan && $h->{ret});
      my @missingvals;
      next if($h->{re} && $l !~ m/$h->{re}/);      # 20% CPU

      my $col = $h->{col};
      my $t = $h->{type};

      my $val = undef;
      my $dte = $fld[0];

      if($t == 0) {                         # Fixed text
        $val = $col;

      } elsif($t == 1) {                    # The column
        $val = $fld[$col] if(defined($fld[$col]));

      } elsif($t == 2) {                    # delta-h  or delta-d

        my $hd = $h->{didx};                # TimeStamp-Length
        my $ld = substr($fld[0],0,$hd);     # TimeStamp-Part (hour or date)
        if(!defined($h->{last1}) || $h->{last3} ne $ld) {
          if(defined($h->{last1})) {
            my @lda = split("[_:]", $lastdate{$hd});
            my $ts = "12:00:00";            # middle timestamp
            $ts = "$lda[1]:30:00" if($hd == 13);
            my $v = $fld[$col]-$h->{last1};
            $v = 0 if($v < 0);              # Skip negative delta
            $dte = "$lda[0]_$ts";
            $val = sprintf("%0.1f", $v);
            if($hd == 13) {                 # Generate missing 0 values / hour
              my @cda = split("[_:]", $ld);
              for(my $mi = $lda[1]+1; $mi < $cda[1]; $mi++) {
                push @missingvals, sprintf("%s_%02d:30:00 0\n", $lda[0], $mi);
              }
            }
          }
          $h->{last1} = $fld[$col];
          $h->{last3} = $ld;
        }
        $h->{last2} = $fld[$col];
        $lastdate{$hd} = $fld[0];

      } elsif($t == 3) {                    # int function
        $val = $1 if($fld[$col] =~ m/^(\d+).*/o);

      } else {                              # evaluate
        $val = eval($h->{fn});

      }

      next if(!defined($val) || $val !~ m/^[-\.\d]+$/o);
      $min[$i] = $val if($val < $min[$i]);
      $max[$i] = $val if($val > $max[$i]);
      $sum[$i] += $val;
      $cnt[$i]++;
      $lastv[$i] = $val;
      $lastd[$i] = $dte;
      map { $cnt[$i]++; $min[$i] = 0 if(0 < $min[$i]); } @missingvals;

      if($outf eq "-") {
        $h->{ret} .= "$dte $val\n";
        map { $h->{ret} .= $_ } @missingvals;

      } else {
        my $fh = $h->{fh};      # cannot use $h->{fh} in print directly
        print $fh "$dte $val\n";
        map { print $fh $_ } @missingvals;
      }
      $h->{count}++;
      $rescanNum--;
      last if(!$rescanNum);

    }
  }

  # If no value found for some of the required columns, then look for the last
  # matching entry outside of the range. Known as the "window left open
  # yesterday" problem
  if(!$rescan) {
    $rescanNum = 0;
    map { $rescanNum++ if(!$d[$_]->{count} && $d[$_]->{df} eq "") } (0..$#a);
    if($rescanNum) {
      $rescan=1;
      my $buf;
      my $end = $hash->{pos}{"$inf:$from"};
      my $start = $end - 1024;
      $start = 0 if($start < 0);
      $ifh->seek($start, 0);
      sysread($ifh, $buf, $end-$start);
      @rescanArr = split("\n", $buf);
      $rescanIdx = $#rescanArr;
      goto RESCAN;
    }
  }

  $ifh->close();

  my $ret = "";
  for(my $i = 0; $i < int(@a); $i++) {
    my $h = $d[$i];
    my $hd = $h->{didx};
    if($hd && $lastdate{$hd}) {
      my $val = defined($h->{last1}) ? $h->{last2}-$h->{last1} : 0;
      $min[$i] = $val if($min[$i] ==  999999);
      $max[$i] = $val if($max[$i] == -999999);
      $lastv[$i] = $val if(!$lastv[$i]);
      $sum[$i] = ($sum[$i] ? $sum[$i] + $val : $val);
      $cnt[$i]++;

      my @lda = split("[_:]", $lastdate{$hd});
      my $ts = "12:00:00";                   # middle timestamp
      $ts = "$lda[1]:30:00" if($hd == 13);
      my $line = sprintf("%s_%s %0.1f\n", $lda[0],$ts, $h->{last2}-$h->{last1});

      if($outf eq "-") {
        $h->{ret} .= $line;
      } else {
        my $fh = $h->{fh};
        print $fh $line;
        $h->{count}++;
      }
    }

    if($outf eq "-") {
      $h->{ret} .= "$from $h->{df}\n" if(!$h->{ret} && $h->{df} ne "");
      $ret .= $h->{ret} if($h->{ret});
      $ret .= "#$a[$i]\n";
    } else {
      my $fh = $h->{fh};
      if(!$h->{count} && $h->{df} ne "") {
        print $fh "$from $h->{df}\n";
      }
      $fh->close();
    }

    my $j = $i+1;
    $data{"min$j"} = $min[$i] == 999999 ? "undef" : $min[$i];
    $data{"max$j"} = $max[$i] == -999999 ? "undef" : $max[$i];
    $data{"avg$j"} = $cnt[$i] ? sprintf("%0.1f", $sum[$i]/$cnt[$i]) : "undef";
    $data{"sum$j"} = $sum[$i];
    $data{"cnt$j"} = $cnt[$i] ? $cnt[$i] : "undef";
    $data{"currval$j"} = $lastv[$i];
    $data{"currdate$j"} = $lastd[$i];

  }
  if($internal) {
    $internal_data = \$ret;
    return undef;
  }

  return ($outf eq "-") ? $ret : join(" ", @fname);
}

###################################
sub
seekTo($$$$)
{
  my ($fname, $fh, $hash, $ts) = @_;

  # If its cached
  if($hash->{pos} && $hash->{pos}{"$fname:$ts"}) {
    $fh->seek($hash->{pos}{"$fname:$ts"}, 0);
    return;
  }

  $fh->seek(0, 2); # Go to the end
  my $upper = $fh->tell;

  my ($lower, $next, $last) = (0, $upper/2, 0);
  my $div = 2;
  while() {                                             # Binary search
    $fh->seek($next, 0);
    my $data = <$fh>;
    if(!$data) {
      $last = $next;
      last;
    }
    if($data !~ m/^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /o) {
      $next = $fh->tell;
      $data = <$fh>;
      if(!$data) {
        $last = $next;
        last;
      }

      # If the second line is longer then the first,
      # binary search will never get it: 
      if($next eq $last && $data ge $ts && $div < 8192 && $next < 1024) {
        $last = 0;
        $div *= 2;
      }
    }
    if($next eq $last) {
      $fh->seek($next, 0);
      last;
    }

    $last = $next;
    if(!$data || $data lt $ts) {
      ($lower, $next) = ($next, int(($next+$upper)/$div));
    } else {
      ($upper, $next) = ($next, int(($lower+$next)/$div));
    }
  }
  $hash->{pos}{"$fname:$ts"} = $last;

}

1;
