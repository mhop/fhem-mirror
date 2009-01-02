##############################################
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

  if($inf eq "-") {
    $inf = $hash->{currentlogfile};
  } else {
    my $linf = "$1/$inf" if($hash->{currentlogfile} =~ m,^(.*)/[^/]*$,);
    if(!-f $linf) {
      $linf = $attr{$hash->{NAME}}{archivedir} . "/" . $inf;
      return "Error: File-not-found" if(!-f $linf);
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
  for(my $i = 0; $i < int(@a); $i++) {
    my @fld = split(":", $a[$i], 4);

    my %h;
    if($outf ne "-") {
      $fname[$i] = "$outf.$i";
      $h{fh} = new IO::File "> $fname[$i]";
    }
    $h{re} = $fld[1];

    $h{df} = defined($fld[2]) ? $fld[2] : "";
    $h{fn} = $fld[3];
    $h{didx} = 10 if($fld[3] && $fld[3] eq "delta-d");
    $h{didx} = 13 if($fld[3] && $fld[3] eq "delta-h");

    if($fld[0] =~ m/"(.*)"/) {
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
  }

  my %lastdate;
  my $d;                    # Used by eval functions
  while(my $l = <$ifh>) {
    next if($l lt $from);
    last if($l gt $to);
    my @fld = split("[ \r\n]+", $l);     # 40%

    for my $i (0..int(@a)-1) {           # Process each req. field
      my $h = $d[$i];
      next if($h->{re} && $l !~ m/$h->{re}/);      # 20%

      my $col = $h->{col};
      my $t = $h->{type};
      my $line;


      if($t == 0) {                         # Fixed text
        $line = "$fld[0] $col\n";

      } elsif($t == 1) {                    # The column
        $line = "$fld[0] $fld[$col]\n" if(defined($fld[$col]));

      } elsif($t == 2) {                    # delta-h  or delta-d

        my $hd = $h->{didx};
        my $ld = substr($fld[0],0,$hd);
        if(!defined($h->{last1}) || $h->{last3} ne $ld) {
          if(defined($h->{last1})) {
            my @lda = split("[_:]", $lastdate{$hd});
            my $ts = "12:00:00";                   # middle timestamp
            $ts = "$lda[1]:30:00" if($hd == 13);
            my $v = $fld[$col]-$h->{last1};
            $v = 0 if($v < 0);                     # Skip negative delta
            $line = sprintf("%s_%s %0.1f\n", $lda[0],$ts, $v);
          }
          $h->{last1} = $fld[$col];
          $h->{last3} = $ld;
        }
        $h->{last2} = $fld[$col];
        $lastdate{$hd} = $fld[0];

      } elsif($t == 3) {                    # int function
        my $val = $fld[$col];
        $line = "$fld[0] $1\n" if($val =~ m/^([0-9]+).*/);

      } else {                              # evaluate
        $line = "$fld[0] " . eval($h->{fn}) . "\n";
      }
      next if(!$line);

      if($outf eq "-") {
        $h->{ret} .= $line;
      } else {
        my $fh = $h->{fh};
        print $fh $line;
        $h->{count}++;
      }
    }
  }
  $ifh->close();

  my $ret = "";
  for(my $i = 0; $i < int(@a); $i++) {
    my $h = $d[$i];
    my $hd = $h->{didx};
    if($hd && $lastdate{$hd}) {
      my $val = defined($h->{last1}) ?  $h->{last2}-$h->{last1} : 0;

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
    if($data !~ m/^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /) {
      $next = $fh->tell;
      $data = <$fh>;
      if(!$data) {
        $last = $next;
        last;
      }

      # If the second line is longer then the first,
      # binary search will never get it: 
      if($next eq $last && $data ge $ts && $div < 8192) {
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
