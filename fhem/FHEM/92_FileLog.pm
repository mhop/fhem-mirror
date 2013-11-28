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
  my $tn = TimeNow();
  my $ct = $dev->{CHANGETIME};
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {
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

=pod
=begin html

<a name="FileLog"></a>
<h3>FileLog</h3>
<ul>
  <br>

  <a name="FileLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FileLog &lt;filename&gt; &lt;regexp&gt;</code>
    <br><br>

    Log events to <code>&lt;filename&gt;</code>. The log format is
    <pre>
      YYYY:MM:DD_HH:MM:SS &lt;device&gt; &lt;event&gt;</pre>
    The regexp will be checked against the device name
    devicename:event or timestamp:devicename:event combination.
    The regexp must match the complete string, not just a part of it.
    <br>
    <code>&lt;filename&gt;</code> may contain %-wildcards of the
    POSIX strftime function of the underlying OS (see your strftime manual).
    Common used wildcards are:
    <ul>
    <li><code>%d</code> day of month (01..31)</li>
    <li><code>%m</code> month (01..12)</li>
    <li><code>%Y</code> year (1970...)
    <li><code>%w</code> day of week (0..6);  0 represents Sunday
    <li><code>%j</code> day of year (001..366)
    <li><code>%U</code> week number of year with Sunday as first day of week (00..53)
    <li><code>%W</code> week number of year with Monday as first day of week (00..53)
    </ul>
    FHEM also replaces <code>%L</code> by the value of the global logdir attribute.<br>
    Before using <code>%V</code> for ISO 8601 week numbers check if it is
    correctly supported by your system (%V may not be replaced, replaced by an
    empty string or by an incorrect ISO-8601 week number, especially
    at the beginning of the year)
    If you use <code>%V</code> you will also have to use %G
    instead of %Y for the year!<br>
    Examples:
    <ul>
      <code>define lamplog FileLog %L/lamp.log lamp</code><br>
      <code>define wzlog FileLog /var/tmp/wz-%Y-%U.log
              wz:(measured-temp|actuator).*</code><br>
      With ISO 8601 week numbers, if supported:<br>
      <code>define wzlog FileLog /var/tmp/wz-%G-%V.log
              wz:(measured-temp|actuator).*</code><br>
    </ul>
    <br>
  </ul>

  <a name="FileLogset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; reopen</code><br>

    Used to reopen a FileLog after making some manual changes to the logfile.
    <br>
  </ul>
  <br>


  <a name="FileLogget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Read data from the logfile, used by frontends to plot data without direct
    access to the file.<br>

    <ul>
      <li>&lt;infile&gt;<br>
        Name of the logfile to grep. "-" is the current logfile, or you can
        specify an older file (or a file from the archive).</li>
      <li>&lt;outfile&gt;<br>
        If it is "-", you get the data back on the current connection, else it
        is the prefix for the output file. If more than one file is specified,
        the data is separated by a comment line for "-", else it is written in
        separate files, numerated from 0.
        </li>
      <li>&lt;from&gt; &lt;to&gt;<br>
        Used to grep the data. The elements should correspond to the
        timeformat or be an initial substring of it.</li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data in a separate file or
        separated by a comment line on the current connection.<br>
        Syntax: &lt;col&gt;:&lt;regexp&gt;:&lt;default&gt;:&lt;fn&gt;<br>
        <ul>
          <li>&lt;col&gt;
            The column number to return, starting at 1 with the date.
            If the column is enclosed in double quotes, then it is a fix text,
            not a column nuber.</li>
          <li>&lt;regexp&gt;
            If present, return only lines containing the regexp. Case sensitive.
            </li>
          <li>&lt;default&gt;<br>
            If no values were found and the default value is set, then return
            one line containing the from value and this default. We need this
            feature as gnuplot aborts if a dataset has no value at all.
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the  integer at the beginning og the string. Used e.g.
                for constructs like 10%</li>
              <li>delta-h or delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>everything else<br>
                The string is evaluated as a perl expression. @fld is the
                current line splitted by spaces. Note: The string/perl
                expression cannot contain spaces, as the part after the space
                will be considered as the next column_spec.</li>
            </ul></li>
        </ul></li>
      </ul>
    <br><br>
    Example:
      <pre>get outlog out-2008.log - 2008-01-01 2008-01-08 4:IR:int: 9:IR::</pre>
    <br><br>
  </ul>

  <a name="FileLogattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="archivedir"></a>
    <a name="archivecmd"></a>
    <a name="nrarchive"></a>
    <li>archivecmd / archivedir / nrarchive<br>
    When a new FileLog file is opened, the FileLog archiver wil be called.
        This happens only, if the name of the logfile has changed (due to
        time-specific wildcards, see the <a href="#FileLog">FileLog</a>
        section), and there is a new entry to be written into the file.
        <br>

        If the attribute archivecmd is specified, then it will be started as a
        shell command (no enclosing " is needed), and each % in the command
        will be replaced with the name of the old logfile.<br>

        If this attribute is not set, but nrarchive and/or archivecmd are set,
        then nrarchive old logfiles are kept along the current one while older
        ones are moved to archivedir (or deleted if archivedir is not set).
        </li><br>

    <li><a href="#disable">disable</a></li>

    <a name="logtype"></a>
    <li>logtype<br>
        Used by the pgm2 webfrontend to offer gnuplot/SVG images made from the
        logs.  The string is made up of tokens separated by comma (,), each
        token specifies a different gnuplot program. The token may contain a
        colon (:), the part before the colon defines the name of the program,
        the part after is the string displayed in the web frontend. Currently
        following types of gnuplot programs are implemented:<br>
        <ul>
           <li>fs20<br>
               Plots on as 1 and off as 0. The corresponding filelog definition
               for the device fs20dev is:<br>
               define fslog FileLog log/fs20dev-%Y-%U.log fs20dev
          </li>
           <li>fht<br>
               Plots the measured-temp/desired-temp/actuator lines. The
               corresponding filelog definitions (for the FHT device named
               fht1) looks like:<br>
               <code>define fhtlog1 FileLog log/fht1-%Y-%U.log fht1:.*(temp|actuator).*</code>

          </li>
           <li>temp4rain10<br>
               Plots the temperature and rain (per hour and per day) of a
               ks300. The corresponding filelog definitions (for the KS300
               device named ks300) looks like:<br>
               define ks300log FileLog log/fht1-%Y-%U.log ks300:.*H:.*
          </li>
           <li>hum6wind8<br>
               Plots the humidity and wind values of a
               ks300. The corresponding filelog definition is the same as
               above, both programs evaluate the same log.
          </li>
           <li>text<br>
               Shows the logfile as it is (plain text). Not gnuplot definition
               is needed.
          </li>
        </ul>
        Example:<br>
           attr ks300log1 logtype temp4rain10:Temp/Rain,hum6wind8:Hum/Wind,text:Raw-data
    </li><br>



  </ul>
  <br>
</ul>

=end html
=cut
