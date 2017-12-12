##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::File;

# This block is only needed when FileLog is loaded bevore FHEMWEB
sub FW_pO(@);
sub FW_pH(@);
sub FW_addContent(;$);
use vars qw($FW_ME);      # webname (default is fhem)
use vars qw($FW_RET);     # Returned data (html)
use vars qw($FW_RETTYPE); 
use vars qw($FW_cmdret);  # error msg forwarding from toSVG
use vars qw($FW_detail);  # for redirect after toSVG
use vars qw($FW_plotmode);# Global plot mode (WEB attribute), used by weblink
use vars qw($FW_plotsize);# Global plot size (WEB attribute), used by weblink
use vars qw($FW_ss);      # is smallscreen
use vars qw($FW_wname);   # Web instance
use vars qw(%FW_pos);     # scroll position
use vars qw(%FW_webArgs); # all arguments specified in the GET

sub FileLog_seekTo($$$$$);
sub FileLog_dailySwitch($);

#####################################
sub
FileLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FileLog_Define";
  $hash->{SetFn}    = "FileLog_Set";
  $hash->{GetFn}    = "FileLog_Get";
  $hash->{UndefFn}  = "FileLog_Undef";
  #$hash->{DeleteFn} = "FileLog_Delete";
  $hash->{NotifyFn} = "FileLog_Log";
  $hash->{AttrFn}   = "FileLog_Attr";
  # logtype is used by the frontend
  no warnings 'qw';
  my @attrList = qw(
    addStateEvent:0,1 
    archiveCompress
    archivecmd
    archivedir
    createGluedFile:0,1
    disable:0,1
    disabledForIntervals
    eventOnThreshold
    ignoreRegexp
    logtype
    mseclog:1,0
    nrarchive
    reformatFn 
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

  $hash->{FW_summaryFn}     = "FileLog_fhemwebFn";
  $hash->{FW_detailFn}      = "FileLog_fhemwebFn";
  $hash->{SVG_sampleDataFn} = "FileLog_sampleDataFn";
  $hash->{SVG_regexpFn}     = "FileLog_regexpFn";
  $data{FWEXT}{"/FileLog_toSVG"}{CONTENTFUNC} = "FileLog_toSVG";
  $data{FWEXT}{"/FileLog_logWrapper"}{CONTENTFUNC} = "FileLog_logWrapper";
  
  InternalTimer(time()+0.1, sub() {      # Forum #39792
    map { HandleArchiving($defs{$_},1) } devspec2array("TYPE=FileLog");
    FileLog_dailySwitch($hash);          # Forum #42415
  }, $hash, 0);
}

sub
FileLog_dailySwitch($)
{
  my ($hash) = @_;
  map { FileLog_Switch($defs{$_}) } devspec2array("TYPE=FileLog");

  my $t = time();
  my $off = fhemTzOffset($t);
  $t = 86400*(int(($t+$off)/86400)+1)+1-$off; # tomorrow, 1s after midnight
  InternalTimer($t, "FileLog_dailySwitch", $hash, 0);
}



#####################################
sub
FileLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  if(@a == 5 && $a[4] eq "readonly") {
    $hash->{READONLY} = 1;
    pop(@a);
  }
  return "wrong syntax: define <name> FileLog filename regexp [readonly]"
        if(int(@a) != 4);

  return "Bad regexp: starting with *" if($a[3] =~ m/^\*/);
  eval { "Hallo" =~ m/^$a[3]$/ };
  return "Bad regexp: $@" if($@);

  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  if(!$hash->{READONLY}) {
    $fh = new IO::File ">>$f";
    return "Can't open $f: $!" if(!defined($fh));
  }

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[3];
  $hash->{logfile} = $a[2];
  $hash->{currentlogfile} = $f;
  $hash->{STATE} = "active";
  InternalTimer(0, sub(){  notifyRegexpChanged($hash, $a[3]); }, $hash);

  return undef;
}

#####################################
sub
FileLog_Undef($$)
{
  my ($hash, $name) = @_;
  close($hash->{FH}) if($hash->{FH});
  return undef;
}

# Unused
sub
FileLog_Delete($$)
{
  my ($hash, $name) = @_;
  return if(!$hash->{currentlogfile});
  unlink($hash->{currentlogfile});
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
    $log->{currentlogfile} = $cn;
    return 1 if($log->{READONLY});
    $fh->close() if($fh);
    HandleArchiving($log);
    $fh = new IO::File ">>$cn";
    if(!defined($fh)) {
      Log3 $log, 0, "Can't open $cn";
      return 0;
    }
    $log->{FH} = $fh;
    setReadingsVal($log, "linesInTheFile", 0, TimeNow());
    return 1;
  }
  return 0;
}

#####################################
sub
FileLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;
  return if($log->{READONLY});

  my $ln = $log->{NAME};
  return if(IsDisabled($ln));
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events);

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $iRe = AttrVal($ln, "ignoreRegexp", undef);
  my $max = int(@{$events});
  my $tn = $dev->{NTFY_TRIGGERTIME};
  if($log->{mseclog}) {
    my ($seconds, $microseconds) = gettimeofday();
    $tn .= sprintf(".%03d", $microseconds/1000);
  }
  my $ct = $dev->{CHANGETIME};
  my $fh;
  my $switched;
  my $written = 0;

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {
      next if($iRe && ($n =~ m/^$iRe$/ || "$n:$s" =~ m/^$iRe$/));
      $t =~ s/ /_/; # Makes it easier to parse with gnuplot

      if(!$switched) {
        FileLog_Switch($log);
        $switched = 1;
      }
      $fh = $log->{FH};
      $s =~ s/\n/ /g;
      print $fh "$t $n $s\n";
      $written++;
    }
  }
  return "" if(!$written);

  if($fh) {
    $fh->flush;
    # Skip sync, it costs too much HD strain, esp. on SSD
    # $fh->sync if !($^O eq 'MSWin32'); #not implemented in Windows
  }
  my $owr = ReadingsVal($ln, "linesInTheFile", 0);
  my $eot = AttrVal($ln, "eventOnThreshold", 0);
  if($eot && ($owr+$written) % $eot == 0) {
    readingsSingleUpdate($log, "linesInTheFile", $owr+$written, 1);
  } else {
    setReadingsVal($log, "linesInTheFile", $owr+$written, $tn);
  }

  return "";
}

###################################
sub
FileLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[2] eq "mseclog") {
    $defs{$a[1]}{mseclog} = ($a[0] eq "set" && (!defined($a[3]) || $a[3]) );
    return;
  }

  if($a[0] eq "set" && $a[2] eq "ignoreRegexp") {
    return "Missing argument for ignoreRegexp" if(!defined($a[3]));
    eval { "HALLO" =~ m/$a[3]/ };
    return $@;
  }

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
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);
  my %sets = (reopen=>0, clear=>0, absorb=>1, addRegexpPart=>2, 
              removeRegexpPart=>1);
  
  my $cmd = $a[1];
  if(!defined($sets{$cmd})) {
    my $r = "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets);
    my $fllist = join(",", grep { $me ne $_ } devspec2array("TYPE=FileLog"));
    $r =~ s/absorb/absorb:$fllist/;
    $r =~ s/clear/clear:noArg/;
    $r =~ s/reopen/reopen:noArg/;
    return $r;
  }
  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 2);

  if(($cmd eq "reopen") or ($cmd eq "clear")) {
    if(!FileLog_Switch($hash)) { # No rename, reopen anyway
      my $fh = $hash->{FH};
      my $cn = $hash->{currentlogfile};
      $fh->close();
      if($cmd eq "clear") {
        $fh = new IO::File(">$cn");
        setReadingsVal($hash, "linesInTheFile", 0, TimeNow());
      } else {
        $fh = new IO::File(">>$cn");
      }
      return "Can't open $cn" if(!defined($fh));
      $hash->{FH} = $fh;
    }

  } elsif($cmd eq "addRegexpPart") {
    my %h;
    my $re = "$a[2]:$a[3]";
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    $h{$re} = 1;
    $re = join("|", sort keys %h);
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = $hash->{logfile} ." $re";
    notifyRegexpChanged($hash, $re);
    
  } elsif($cmd eq "removeRegexpPart") {
    my %h;
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    return "Cannot remove regexp part: not found" if(!$h{$a[2]});
    return "Cannot remove last regexp part" if(int(keys(%h)) == 1);
    delete $h{$a[2]};
    my $re = join("|", sort keys %h);
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = $hash->{logfile} ." $re";
    notifyRegexpChanged($hash, $re);

  } elsif($cmd eq "absorb") {
    my $victim = $a[2];
    return "need another FileLog as argument."
      if(!$victim ||
         !$defs{$victim} ||
         $defs{$victim}{TYPE} ne "FileLog" ||
         $victim eq $me);
    my $vh = $defs{$victim};
    my $mylogfile = $hash->{currentlogfile};
    return "Cant open the associated files"
        if(!open(FH1, $mylogfile) ||
           !open(FH2, $vh->{currentlogfile}) ||
           !open(FH3, ">$mylogfile.new"));

    my $fh = $hash->{FH};
    $fh->close();

    my $b1 = <FH1>; my $b2 = <FH2>;
    while(defined($b1) && defined($b2)) {
      if($b1 lt $b2) {
        print FH3 $b1; $b1 = <FH1>;
      } else {
        print FH3 $b2; $b2 = <FH2>;
      }
    }

    while($b1 = <FH1>) { print FH3 $b1; }
    while($b2 = <FH2>) { print FH3 $b2; }
    close(FH1); close(FH2); close(FH3);
    rename("$mylogfile.new", $mylogfile);
    $fh = new IO::File(">>$mylogfile");
    $hash->{FH} = $fh;

    $hash->{REGEXP} .= "|".$vh->{REGEXP};
    $hash->{DEF} = $hash->{logfile} . " ". $hash->{REGEXP};
    notifyRegexpChanged($hash, $hash->{REGEXP});
    CommandDelete(undef, $victim);

  }
  return undef;
}

sub
FileLog_loadSVG()
{
  if(!$modules{SVG}{LOADED} && -f "$attr{global}{modpath}/FHEM/98_SVG.pm") {
    my $ret = CommandReload(undef, "98_SVG");
    Log3 undef, 1, $ret if($ret);
  }
}

#########################
sub
FileLog_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return "<div id=\"$d\" align=\"center\" class=\"FileLog col2\">".
                "$defs{$d}{STATE}</div>" if($FW_ss && $pageHash);

  my $row = 0;
  my $ret = sprintf("<table class=\"FileLog %swide\">",
                        $pageHash ? "" : "block ");
  foreach my $f (FW_fileList($defs{$d}{logfile})) {
    my $class = (!$pageHash ? (($row++&1)?"odd":"even") : "");
    $ret .= "<tr class=\"$class\">";
    $ret .= "<td><div class=\"dname\">$f</div></td>";
    my $idx = 0;
    foreach my $ln (split(",", AttrVal($d, "logtype", "text"))) {
      if($FW_ss && $idx++) {
        $ret .= "</tr><tr class=\"".(($row++&1)?"odd":"even")."\"><td>";
      }
      my ($lt, $name) = split(":", $ln);
      $name = $lt if(!$name);
      $ret .= FW_pH("$FW_ME/FileLog_logWrapper&dev=$d&type=$lt&file=$f",
                    "<div class=\"dval\">$name</div>", 1, "dval", 1);
    }
    $ret .= "</tr>";
  }
  $ret .= "</table>";
  return $ret if($pageHash);

  # DETAIL only from here on
  my $hash = $defs{$d};

  $ret .= "<br>Regexp parts";
  $ret .= "<br><table class=\"block wide\">";
  my @ra = split(/\|/, $hash->{REGEXP});
  if(@ra > 1) {
    foreach my $r (@ra) {
      $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
      my $cmd = "cmd.X= set $d removeRegexpPart&val.X=$r"; # =.set: avoid JS
      $ret .= "<td>$r</td>";
      $ret .= FW_pH("$cmd&detail=$d", "removeRegexpPart", 1,undef,1);
      $ret .= "</tr>";
    }
  }

  my @et = devspec2array("TYPE=eventTypes");
  if(!@et) {
    $ret .= FW_pH("$FW_ME/docs/commandref.html#eventTypes",
                  "To add a regexp an eventTypes definition is needed",
                  1, undef, 1);
  } else {
    my %dh;
    my $etList = AnalyzeCommand(undef, "get $et[0] list");
    $etList = "" if(!$etList);
    foreach my $l (split("\n", $etList)) {
      my @a = split(/[ \r\n]/, $l);
      $a[1] = "" if(!defined($a[1]));
      $a[1] =~ s/\.\*//g;
      $a[1] =~ s/,.*//g;
      next if(@a < 2);
      $dh{$a[0]}{".*"} = 1;
      $dh{$a[0]}{$a[1].".*"} = 1;
    }
    my $list = "";
    foreach my $dev (sort keys %dh) {
      $list .= " $dev:" . join(",", sort keys %{$dh{$dev}});
    }
    $list =~ s/(['"])/./g;

    $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
    $ret .= '<td colspan="2">';
    $ret .= FW_detailSelect($d, "set", $list, "addRegexpPart");
    $ret .= "</td></tr>";
  }
  $ret .= "</table>";

  my $newIdx=1;
  while($defs{"SVG_${d}_$newIdx"}) {
    $newIdx++;
  }
  my $name = "SVG_${d}_$newIdx";
  $ret .= FW_pH("cmd=define $name SVG $d:template:CURRENT;".
                     "set $name copyGplotFile&detail=$name",
                "<div class=\"dval\">Create SVG plot</div>", 0, "dval", 1);

  return $ret;
}

###################################
sub
FileLog_toSVG($)
{
  my ($arg) = @_;
  FW_digestCgi($arg);
  return("text/html;", "bad url: cannot create SVG def")
    if(!defined($FW_webArgs{arg}));

  my @aa = split(":", $FW_webArgs{arg});
  my $max = 0;
  for my $d (keys %defs) {
    $max = ($1+1) if($d =~ m/^SVG_(\d+)$/ && $1 >= $max);
  }
  $defs{$aa[0]}{currentlogfile} =~ m,([^/]*)$,;
  $aa[2] = "CURRENT" if($1 eq $aa[2]);
  $FW_cmdret = FW_fC("define SVG_$max SVG $aa[0]:$aa[1]:$aa[2]");
  $FW_detail = "SVG_$max" if(!$FW_cmdret);
  return;
}

######################
# Show the content of the log (plain text), or an image and offer a link
# to convert it to an SVG instance
# If text and no reverse required, try to return the data as a stream;
sub
FileLog_logWrapper($)
{
  my ($cmd) = @_;

  my $d    = $FW_webArgs{dev};
  my $type = $FW_webArgs{type};
  my $file = $FW_webArgs{file};
  my $ret = "";

  if(!$d || !$type || !$file) {
    FW_addContent(">FileLog_logWrapper: bad arguments</div");
    return 0;
  }

  if(defined($type) && $type eq "text") {
    $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path =~ s/%L/$attr{global}{logdir}/g
        if($path =~ m/%/ && $attr{global}{logdir});
    $path = AttrVal($d,"archivedir","") . "/$file" if(!-f $path);

    FW_addContent();
    FW_pO "<div class=\"tiny\">" if($FW_ss);
    FW_pO "<pre class=\"log\">";
    my $suffix = "</pre>".($FW_ss ? "</div>" : "")."</div>";

    my $reverseLogs = AttrVal($FW_wname, "reverseLogs", 0);
    if(!$reverseLogs) {
      $suffix .= "</body></html>";
      return FW_returnFileAsStream($path, $suffix, "text/html", 1, 0);
    }

    if(!open(FH, $path)) {
      FW_addContent(">$path: $!</div></body></html");
      return 0;
    }
    my $cnt = join("", reverse <FH>);
    close(FH);
    $cnt = FW_htmlEscape($cnt);
    FW_pO $cnt;
    FW_pO $suffix;
    return 1;

  } else {
    FileLog_loadSVG();
    FW_pO "<script type='text/javascript' src='$FW_ME/pgm2/svg.js'></script>";
    FW_addContent();
    FW_pO "<br>";
    if(AttrVal($d,"plotmode",$FW_plotmode) ne "gnuplot") {
      FW_pO SVG_zoomLink("$cmd;zoom=-1", "Zoom-in", "zoom in");
      FW_pO SVG_zoomLink("$cmd;zoom=1",  "Zoom-out","zoom out");
      FW_pO SVG_zoomLink("$cmd;off=-1",  "Prev",    "prev");
      FW_pO SVG_zoomLink("$cmd;off=1",   "Next",    "next");
    }
    FW_pO "<table><tr><td>";
    FW_pO "<td>";
    my $logtype = $defs{$d}{NAME};
    my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);
    my $arg = "$FW_ME/SVG_showLog&dev=$logtype&logdev=$d".
                "&gplotfile=$type&logfile=$file$wl";
    if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
      my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
      FW_pO "<embed src=\"$arg\" type=\"image/svg+xml\" " .
                    "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

    } else {
      FW_pO "<img src=\"$arg\"/>";
    }

    FW_pO "<br>";
    FW_pH "$FW_ME/FileLog_toSVG&arg=$d:$type:$file", "Create SVG instance";
    FW_pO "</td>";
    FW_pO "</td></tr></table>";
    FW_pO "</div>";

  }
  return 0;
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
#  mindate<x>, min<x>, maxdate<x>, max<x>, avg<x>, cnt<x>, currdate<x>,
#  currval<x>, sum<x>
# for each requested column, beginning with <x> = 1

sub
FileLog_Get($@)
{
  my ($hash, @a) = @_;
  
  return "Usage: get $a[0] <infile> <outfile> <from> <to> [<column_spec>...]\n".
         "  where column_spec is <col>:<regexp>:<default>:<fn>\n" .
         "  see the FileLogGrep entries in he .gplot files\n" .
         "  <infile> is without direcory, - means the current file\n" .
         "  <outfile> is a prefix, - means stdout\n"
        if(int(@a) < 4);
  shift @a;
  my $inf  = shift @a;
  my $outf = shift @a;
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my $internal;

  my $name = $hash->{NAME};

  if($outf eq "INT") {
    $outf = "-";
    $internal = 1;
  }

  my $reformatFn = AttrVal($name, "reformatFn", "");
  my $tempread;

  if($inf eq "-") {
    # In case now is after midnight, before the first event is logged.
    FileLog_Switch($hash);
    $inf = $hash->{currentlogfile};

  } else {
    my $linf;
    if($inf eq "CURRENT") {
      # Try to guess
      if($from =~ m/^(....)-(..)-(..)/) {
        $linf = $hash->{logfile};
        my ($Y,$m,$d) = ($1,$2,$3);
        sub expandFileWildcards($$$$) {
           my ($f,$Y,$m,$d)=@_;
           return ResolveDateWildcards($f,
                        localtime(time_str2num("$Y-$m-$d 00:00:00")));
        };
        $linf=expandFileWildcards($linf,$Y,$m,$d);
        if(AttrVal($name, "createGluedFile", 0)) {
          if($to =~ m/^(....)-(..)-(..)/) {
            my $linf_to = $hash->{logfile};
            my ($Y,$m,$d) = ($1,$2,$3);
            $linf_to=expandFileWildcards($linf_to,$Y,$m,$d);
            if($linf ne $linf_to){  # use to log files
              $tempread=$linf_to.".transit.temp.log";
              if(open(my $temp,'>',$tempread)){
                if(open(my $i,'<',$linf)){
                  print $temp join("",<$i>);
                  close($i);
                }
                if(open(my $i,'<',$linf_to)){
                  print $temp join("",<$i>);
                  close($i);
                }
                $linf=$tempread;
                close($temp);
              }
            }
          }
        }
        $linf = $hash->{currentlogfile} if($linf =~ m/%/ || ! -f $linf);
      } else {
        $linf = $hash->{currentlogfile};
      }

    } else {
      $linf = "$1/$inf" if($hash->{currentlogfile} =~ m,^(.*)/[^/]*$,);
      $linf = "" if(!$linf); # Missing log directory

    }

    # Look for the file in the log directory...
    if(!-f $linf) {
      # ... or in the archivelog
      $linf = AttrVal($name, "archivedir",".") ."/". $inf;
    }
    $inf = $linf;
  }
  Log3 $name, 4, "$name get: Input file $inf, from:$from  to:$to";

  my $ifh = new IO::File $inf if($inf);
  FileLog_seekTo($inf, $ifh, $hash, $from, $reformatFn) if($ifh);

  # Return the the plain file data, $outf is ignored
  if(!@a) {
    return "" if(!$ifh);
    my $out = "";
    while(my $l = <$ifh>) {
      if($reformatFn) { no strict; $l = &$reformatFn($l); use strict; }
      next if($l lt $from);
      last if($l gt $to);
      $out .= $l;
    }
    return $out;
  }

  #############
  # Digest the input.
  # last1: first delta value after d/h change
  # last2: last delta value recorded (for the very last entry)
  # last3: last delta timestamp (d or h)
  my (@d, @fname);
  my (@min, @max, @sum, @cnt, @lastv, @lastd, @mind, @maxd, @firstv, @firstd);

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
    $firstv[$i] = 0;
    $firstd[$i] = "undef";
    $mind[$i] = "undef";
    $maxd[$i] = "undef";
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
      $l = <$ifh> if($ifh);
      last if(!$l);
      if($reformatFn) { no strict; $l = &$reformatFn($l); use strict; }
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

        next if($rescan);

        my $hd = $h->{didx};                # TimeStamp-Length
        my $ld = substr($fld[0],0,$hd);     # TimeStamp-Part (hour or date)
        if(!defined($h->{last1}) || $h->{last3} ne $ld) {
          if(defined($h->{last1})) {
            my @lda = split("[_:]", $lastdate{$hd});
            my $ts = "12:00:00";            # middle timestamp
            $ts = "$lda[1]:30:00" if($hd == 13);
            my $v = $fld[$col]-$h->{last1};
#            $v = 0 if($v < 0);              # Skip negative delta (why?)
            $dte = "$lda[0]_$ts";
            $val = sprintf("%g", $v);
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
        $cmdFromAnalyze = $h->{fn};
        $val = eval($cmdFromAnalyze);
        $cmdFromAnalyze = undef;

      }

      next if(!defined($val) || $val !~ m/^-?[.\d]+$/o);
      if($val < $min[$i]) {
        $min[$i] = $val;
        $mind[$i] = $dte;
      }
      if($val > $max[$i]) {
        $max[$i] = $val;
        $maxd[$i] = $dte;
      }
      $sum[$i] += $val;
      $cnt[$i]++;
      if($firstd[$i] eq "undef") {
        $firstv[$i] = $val;
        $firstd[$i] = $dte;
      }
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
  if(!$rescan && $ifh) {
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

  $ifh->close() if($ifh);
  unlink($tempread) if($tempread);

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
      my $line = sprintf("%s_%s %0.1f\n", $lda[0],$ts,
                defined($h->{last1}) ? $h->{last2}-$h->{last1} : 0);

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
    $j += $data{svgOffset} if($data{svgOffset});
    $data{"min$j"} = $min[$i];
    $data{"max$j"} = $max[$i];
    $data{"avg$j"} = $cnt[$i] ? sprintf("%0.1f", $sum[$i]/$cnt[$i]) : 0;
    $data{"sum$j"} = $sum[$i];
    $data{"cnt$j"} = $cnt[$i];
    $data{"currval$j"} = $lastv[$i];
    $data{"currdate$j"} = $lastd[$i];
    $data{"firstval$j"} = $firstv[$i];
    $data{"firstdate$j"} = $firstd[$i];
    $data{"mindate$j"} = $mind[$i];
    $data{"maxdate$j"} = $maxd[$i];
    $data{"lastraw$j"} = $h->{last2} if($h->{last2});

    Log3 $name, 4,
        "$name get: line $j, regexp:".$d[$i]->{re}.", col:".$d[$i]->{col}.
        ", output lines:".$data{"cnt$j"};

  }
  if($internal) {
    $internal_data = \$ret;
    return undef;
  }

  return ($outf eq "-") ? $ret : join(" ", @fname);
}

###############
# this is not elegant. Assume, that current seek pos is after a cr/nl
sub
seekBackOneLine($$)
{
  my ($fh, $pos) = @_;
  my $buf;

  while($pos > 0) { # skip current CR/NL
    $fh->seek(--$pos, 0);
    $fh->read($buf, 1);
    last if($buf ne "\n" && $buf ne "\r");
  }
  $fh->seek($pos, 0);

  while($pos > 0 && $fh->read($buf, 1)) {
    return ++$pos if($buf eq "\n" || $buf eq "\r");
    $fh->seek(--$pos, 0);
  }
  return 0;
}

###################################
#($1-40587)*86400+$2
sub
FileLog_seekTo($$$$$)
{
  my ($fname, $fh, $hash, $ts, $reformatFn) = @_;

  # If its cached
  if($hash->{pos} && $hash->{pos}{"$fname:$ts"}) {
    $fh->seek($hash->{pos}{"$fname:$ts"}, 0);
    return;
  }

  $fh->seek(0, 2); # Go to the end
  my $upper = $fh->tell;

  my ($lower, $next, $last) = (0, $upper/2, -1);
  for(my $iter=0; $iter<200; $iter++) {       # Binary search
    if($next == $last) {
      $fh->seek($next, 0);
      last;
    }

    $fh->seek($next, 0);
    my $data = <$fh>;
    if(!$data) {
      $last = $next;
      last;
    }
    if($reformatFn) { no strict; $data = &$reformatFn($data); use strict; }
    if($data !~ m/^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /o) {
      $next = seekBackOneLine($fh, $fh->tell);
      next;
    }

    $last = $next;
    if(!$data || $data lt $ts) {
      ($lower, $next) = ($next, int(($next+$upper)/2));
    } else {
      ($upper, $next) = ($next, int(($lower+$next)/2));
    }
  }
  $last = 0 if($last < 0); # Forum #46512
  $hash->{pos}{"$fname:$ts"} = $last;
}

sub
FileLog_addTics($$)
{
  my ($in, $p) = @_;
  return if(!$in || $in !~ m/^\((.*)\)$/);
  map { $p->{"\"$2\""}=1 if(m/^ *([^ ]+) ([^ ]+) */); } split(",",$1);
}

sub
FileLog_sampleDataFn($$$$$)
{
  my ($flName, $flog, $max, $conf, $wName) = @_;
  my $desc = "Input:Column,Regexp,DefaultValue,Function";
  my @htmlArr;

  my $fName = $defs{$flName}{currentlogfile};
  my $reformatFn = AttrVal($flName, "reformatFn", "");
  my $fh = new IO::File $fName;
  if(!$fh) {
    $fName = "<undefined>" if(!defined($fName));
    Log3 $wName, 1, "FileLog get sample data: $fName: $!";
    return ($desc, \@htmlArr, "");
  }
  $fh->seek(0, 2); # Go to the end
  my $sz = $fh->tell;
  $fh->seek($sz > 65536 ? $sz-65536 : 0, 0);
  my $data;
  $data = <$fh> if($sz > 65536); # discard the first/partial line
  my $maxcols = 0;
  my %h;
  while($data = <$fh>) {
    if($reformatFn) { no strict; $data = &$reformatFn($data); use strict; }
    my @cols = split(" ", $data);
    next if(@cols < 3);
    $maxcols = @cols if(@cols > $maxcols);
    $cols[2] = "*" if($cols[2] =~ m/^[-\.\d]+$/);
    $h{"$cols[1].$cols[2]"} = $data;
    $h{"$cols[1].*"} = "" if($cols[2] ne "*");
  }
  $fh->close();

  my $colnums = $maxcols;
  my $colregs = join(",", sort keys %h);
  my $example = join("<br>", grep /.+/,map { $h{$_} } sort keys %h);

  $colnums = join(",", 3..$colnums);

  my %tickh;
  FileLog_addTics($conf->{ytics}, \%tickh);
  FileLog_addTics($conf->{y2tics}, \%tickh);
  $colnums = join(",", sort keys %tickh).",$colnums" if(%tickh);

  for(my $r=0; $r < $max; $r++) {
    my @f = split(":", ($flog->[$r] ? $flog->[$r] : ":::"), 4);
    my $ret = "";
    $f[1] =~ s/\\x(..)/chr(hex($1))/ge;       # Convert \x3a to :
    $colregs .= ",$f[1]" if($f[1] && !$h{$f[1]});
    $ret .= SVG_sel("par_${r}_0", $colnums, $f[0], undef, "svgColumn");
    $ret .= SVG_sel("par_${r}_1", $colregs, $f[1], undef, "svgRegexp");
    $ret .= SVG_txt("par_${r}_2", "", $f[2], 2);
    $ret .= SVG_txt("par_${r}_3", "", $f[3],10);
    push @htmlArr, $ret;
  }

  return ($desc, \@htmlArr, $example);
}

sub
FileLog_regexpFn($$)
{
  my ($name, $filter) = @_;
  $filter = " $filter ";
  $filter =~ s/ [^: ]*:/ /g;
  $filter =~ s/:[^ ]* / /g;
  $filter =~ s/(^ | $)//g;
  $filter =~ s/ /|/g;
  return $filter;
}

1;

=pod
=item helper
=item summary    log events to a file
=item summary_DE schreibt Events in eine Logdatei
=begin html

<a name="FileLog"></a>
<h3>FileLog</h3>
<ul>
  <br>

  <a name="FileLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FileLog &lt;filename&gt; &lt;regexp&gt; [readonly]</code>
    <br><br>

    Log events to <code>&lt;filename&gt;</code>. The log format is
    <ul><code><br>
      YYYY-MM-DD_HH:MM:SS &lt;device&gt; &lt;event&gt;<br>
    <br></code></ul>
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
    <li><code>%Y</code> year (1970...)</li>
    <li><code>%w</code> day of week (0..6);  0 represents Sunday</li>
    <li><code>%j</code> day of year (001..366)</li>
    <li><code>%U</code> week number of year with Sunday as first day of week (00..53)</li>
    <li><code>%W</code> week number of year with Monday as first day of week (00..53)</li>
    </ul>
    FHEM also replaces <code>%L</code> by the value of the global logdir attribute.<br>
    Before using <code>%V</code> for ISO 8601 week numbers check if it is
    correctly supported by your system (%V may not be replaced, replaced by an
    empty string or by an incorrect ISO-8601 week number, especially
    at the beginning of the year)
    If you use <code>%V</code> you will also have to use %G
    instead of %Y for the year!<br>

    If readonly is specified, then the file is used only for visualisation, and
    it is not opened for writing.
    Examples:
    <ul>
      <code>define lamplog FileLog %L/lamp.log lamp</code><br>
      <code>define wzlog FileLog ./log/wz-%Y-%U.log
              wz:(measured-temp|actuator).*</code><br>
      With ISO 8601 week numbers, if supported:<br>
      <code>define wzlog FileLog ./log/wz-%G-%V.log
              wz:(measured-temp|actuator).*</code><br>
    </ul>
    <br>
  </ul>

  <a name="FileLogset"></a>
  <b>Set </b>
  <ul>
    <li>reopen
      <ul>
        Reopen a FileLog after making some manual changes to the
        logfile.
      </ul>
      </li>
    <li>clear
      <ul>
        Clears and reopens the logfile.
      </ul>
      </li>
    <li>addRegexpPart &lt;device&gt; &lt;regexp&gt;
      <ul>
        add a regexp part, which is constructed as device:regexp.  The parts
        are separated by |.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid.
      </ul>
      </li>
    <li>removeRegexpPart &lt;re&gt;
      <ul>
        remove a regexp part.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid.<br>
        The inconsistency in addRegexpPart/removeRegexPart arguments originates
        from the reusage of javascript functions.
      </ul>
      </li>
    <li>absorb secondFileLog 
      <ul>
        merge the current and secondFileLog into one file, add the regexp of the
        secondFileLog to the current one, and delete secondFileLog.<br>
        This command is needed to create combined plots (weblinks).<br>
        <b>Notes:</b>
        <ul>
          <li>secondFileLog will be deleted (i.e. the FHEM definition).</li>
          <li>only the current files will be merged.</li>
          <li>weblinks using secondFilelog will become broken, they have to be
              adopted to the new logfile or deleted.</li>
        </ul>
      </ul>
      </li>
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
        Name of the logfile to open. Special case: "-" is the currently active
        logfile, "CURRENT" opens the file corresponding to the "from"
        parameter.
        </li>

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
            not a column number.</li>
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
      <ul><code><br>
        get outlog out-2008.log - 2008-01-01 2008-01-08 4:IR:int: 9:IR::
      </code></ul>
    <br>
  </ul>

  <a name="FileLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li><br><br>

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

        If this attribute is not set, but nrarchive is set, then nrarchive old
        logfiles are kept along the current one while older ones are moved to
        archivedir (or deleted if archivedir is not set).<br>
        Note: "old" means here the first ones in the alphabetically soreted
        list. <br>

        Note: setting these attributes for the global instance will effect the
        <a href="#logfile">FHEM logfile</a> only.
        </li><br>

    <a name="archiveCompress"></a>
    <li>archiveCompress<br>
        If nrarchive, archivedir and archiveCompress is set, then the files
        in the archivedir will be compressed.
        </li><br>

    <a name="createGluedFile"></a>
    <li>createGluedFile<br>
        If set (to 1), and the SVG-Plot requests a time-range wich is stored
        in two files, a temporary file with the content of both files will be
        created, in order to satisfy the request.
        </li><br>

    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <br>

    <a name="eventOnThreshold"></a>
    <li>eventOnThreshold<br>
        If set (to a nonzero number), the event linesInTheFile will be
        generated, if the lines in the file is a multiple of the set number.
        Note: the counter is only correct for files created after this
        feature was implemented. A FHEM crash or kill will falsify the counter.
        </li><br>

    <li><a href="#ignoreRegexp">ignoreRegexp</a></li>

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
           attr ks300log1 logtype
                temp4rain10:Temp/Rain,hum6wind8:Hum/Wind,text:Raw-data
    </li><br>

    <li><a href="#mseclog">mseclog</a></li><br>

    <a name="reformatFn"></a>
    <li>reformatFn<br>
      used to convert "foreign" logfiles for the SVG Module, contains the
      name(!) of a function, which will be called with a "raw" line from the
      original file, and has to return a line in "FileLog" format.<br>

      E.g. to visualize the NTP loopstats, set reformatFn to ntpLoopstats, and
      copy the following into your 99_myUtils.pm:
      <pre><code>
      sub            
      ntpLoopstats($)
      {
        my ($d) = @_;
        return $d if($d !~ m/^(\d{5}) (\d+)\.(\d{3}) (.*)$/);
        my ($r, $t) = ($4, FmtDateTime(($1-40587)*86400+$2));
        $t =~ s/ /_/;
        return "$t ntpLoopStats $r";
      }</code></pre>
      </li>



  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="FileLog"></a>
<h3>FileLog</h3>
<ul>
  <br>

  <a name="FileLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FileLog &lt;filename&gt; &lt;regexp&gt; [readonly]</code>
    <br><br>

    Speichert Ereignisse in einer Log-Datei mit Namen <code>&lt;filename&gt;</code>. Das Log-Format ist
    <ul><code><br>
      YYYY-MM-DD_HH:MM:SS &lt;device&gt; &lt;event&gt;<br>
    <br></code></ul>
    Der Ausdruck unter regexp wird anhand des Ger&auml;tenames &uuml;berpr&uuml;ft und zwar 
    devicename:event oder der timestamp:devicename:event-Kombination.
    Der regexp muss mit dem kompletten String &uuml;bereinstimmen und nicht nur teilweise.
    <br>
    <code>&lt;filename&gt;</code> k&ouml;nnen %-wildcards der POSIX
    strftime-Funktion des darunterliegenden OS enthalten (siehe auch strftime
    Beschreibung).
    Allgemein gebr&auml;uchliche Wildcards sind:
    <ul>
    <li><code>%d</code> Tag des Monats (01..31)</li>
    <li><code>%m</code> Monat (01..12)</li>
    <li><code>%Y</code> Jahr (1970...)</li>
    <li><code>%w</code> Wochentag (0..6);  beginnend mit Sonntag (0)</li>
    <li><code>%j</code> Tag des Jahres (001..366)</li>
    <li><code>%U</code> Wochennummer des Jahres, wobei Wochenbeginn = Sonntag (00..53)</li>
    <li><code>%W</code> Wochennummer des Jahres, wobei Wochenbeginn = Montag (00..53)</li>
    </ul>
    FHEM ersetzt <code>%L</code> mit dem Wert des global logdir Attributes.<br>

    Bevor <code>%V</code> f&uuml;r ISO 8601 Wochennummern verwendet werden,
    muss &uuml;berpr&uuml;ft werden, ob diese Funktion durch das Brriebssystem
    unterst&uuml;tzt wird (Es kann sein, dass %V nicht umgesetzt wird, durch
    einen Leerstring ersetzt wird oder durch eine falsche ISO-Wochennummer
    dargestellt wird - besonders am Jahresanfang)

    Bei der Verwendung von <code>%V</code> muss gleichzeitig f&uuml;r das Jahr
    ein <code>%G</code> anstelle von <code>%Y</code> benutzt werden.<br>

    Falls man readonly spezifiziert, dann wird die Datei nur zum visualisieren
    verwendet, und nicht zum Schreiben ge&ouml;ffnet.
    <br>

    Beispiele:
    <ul>
      <code>define lamplog FileLog %L/lamp.log lamp</code><br>
      <code>define wzlog FileLog ./log/wz-%Y-%U.log
              wz:(measured-temp|actuator).*</code><br>
      Mit ISO 8601 Wochennummern falls unterst&uuml;tzt:<br>
      <code>define wzlog FileLog ./log/wz-%G-%V.log
              wz:(measured-temp|actuator).*</code><br>
    </ul>
    <br>
  </ul>

  <a name="FileLogset"></a>
  <b>Set </b>
  <ul>
    <li>reopen
      <ul>
        Erneutes &Ouml;ffnen eines FileLogs nach h&auml;ndischen
        &Auml;nderungen in dieser Datei.
      </ul></li>
    <li>clear
      <ul>
        L&ouml;schen und erneutes &Ouml;ffnen eines FileLogs.
      </ul></li>
    <li>addRegexpPart &lt;device&gt; &lt;regexp&gt;
      <ul>
        F&uuml;gt ein regexp Teil hinzu, der als device:regexp aufgebaut ist.
        Die Teile werden nach Regexp-Regeln mit | getrennt.  Achtung: durch
        hinzuf&uuml;gen k&ouml;nnen manuell erzeugte Regexps ung&uuml;ltig
        werden.
      </ul></li>
    <li>removeRegexpPart &lt;re&gt;
      <ul>
        Entfernt ein regexp Teil.  Die Inkonsistenz von addRegexpPart /
        removeRegexPart-Argumenten hat seinen Ursprung in der Wiederverwendung
        von Javascript-Funktionen.
      </ul></li>
    <li>absorb secondFileLog 
      <ul>
        F&uuml;hrt den gegenw&auml;rtigen Log und den secondFileLog zu einer
        gemeinsamen Datei zusammen, f&uuml;gt danach die regexp des
        secondFileLog dem gegenw&auml;rtigen Filelog hinzu und l&ouml;scht dann
        anschlie&szlig;end das secondFileLog.<br>

        Dieses Komanndo wird zur Erzeugung von kombinierten Plots (weblinks)
        ben&ouml;tigt.<br>

        <b>Hinweise:</b>
        <ul>
          <li>secondFileLog wird gel&ouml;scht (d.h. die FHEM-Definition und
              die Datei selbst).</li>
          <li>nur das aktuelle File wird zusammengef&uuml;hrt, keine
              archivierten Versionen.</li>
          <li>Weblinks, die das secondFilelog benutzen werden unbrauchbar, sie
              m&uuml;ssen deshalb auf das neue Logfile angepasst oder
              gel&ouml;scht werden.</li>
        </ul>
      </ul></li>
      <br>
    </ul>
    <br>


  <a name="FileLogget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Liest Daten aus einem Logfile und wird von einem Frontend ben&ouml;tigt, um
    Daten ohne direkten Zugriff aus der Datei zu lesen.<br>

    <ul>
      <li>&lt;infile&gt;<br>
        Name des Logfiles, auf das zugegriffen werden soll. Sonderf&auml;lle:
        "-" steht f&uuml;r das aktuelle Logfile, und "CURRENT" &ouml;ffnet die
        zum "from" passende Datei.</li>

      <li>&lt;outfile&gt;<br>
        Bei einem  "-", bekommt man die Daten auf der aktuellen Verbindung
        zur&uuml;ck, anderenfall ist es das Name (eigentlich Prefix, s.u.) des
        Output-Files. Wenn mehr als ein File angesprochen wird, werden die
        einzelnen Dateinamen durch ein "-" getrennt, anderenfalls werden die
        Daten in einzelne Dateien geschrieben, die - beginnend mit 0 -
        durchnummeriert werden.

        </li>
      <li>&lt;from&gt; &lt;to&gt;<br>
        Bezeichnet den gew&uuml;nschten Datenbereich. Die beiden Elemente
        m&uuml;ssen ganz oder mit dem Anfang des Zeitformates
        &uuml;bereinstimmen.</li>

      <li>&lt;column_spec&gt;<br>
        Jede column_spec sendet die gew&uuml;nschten Daten entweder in eine
        gesonderte Datei oder &uuml;ber die gegenw&auml;rtige Verbindung durch
        "-" getrennt.<br>

        Syntax: &lt;col&gt;:&lt;regexp&gt;:&lt;default&gt;:&lt;fn&gt;<br>
        <ul>
          <li>&lt;col&gt;
            gibt die Spaltennummer zur&uuml;ck, beginnend mit 1 beim Datum.
            Wenn die Spaltenmummer in doppelten Anf&uuml;hrungszeichen steht,
            handelt es sich um einen festen Text und nicht um eine
            Spaltennummer.</li>

          <li>&lt;regexp&gt;
            gibt, falls vorhanden, Zeilen mit Inhalten von regexp zur&uuml;ck.
            Gro&szlig;- und Kleinschreibung beachten.  </li>
          <li>&lt;default&gt;<br>
            Wenn keine Werte gefunden werden, und der Default-Wert
            (Voreinstellung) wurde gesetzt, wird eine Zeile zur&uuml;ckgegeben,
            die den von-Wert (from) und diesen Default-Wert enth&auml;lt.
            Dieses Leistungsmerkmal ist notwendig, da gnuplot abbricht, wenn
            ein Datensatz keine Daten enth&auml;lt.
            </li>
          <li>&lt;fn&gt;
            Kann folgende Inhalte haben:
            <ul>
              <li>int<br>
                L&ouml;st den Integer-Wert zu Beginn eines Strings heraus. Wird
                z.B. bei 10% gebraucht.</li>
              <li>delta-h oder delta-d<br>
                Gibt nur den Unterschied der Werte-Spalte pro
                Stunde oder pro Tag aus. Wird ben&ouml;tigt, wenn die Spalte
                einen Z&auml;hler enth&auml;lt, wie im Falles des KS300 in der
                Spalte f&uuml;r die Regenmenge.</li>
              <li>alles andere<br>
                Dieser String wird als Perl-Ausdruck ausgewertet. @fld enthaelt
                die aktuelle Zeile getrennt durch Leerzeichen. Achtung:
                Dieser String/Perl-Ausdruck darf keine Leerzeichen enthalten.
                </li>
            </ul></li>
        </ul></li>
      </ul>
    <br><br>
    Beispiel:
      <ul><code><br>
        get outlog out-2008.log - 2008-01-01 2008-01-08 4:IR:int: 9:IR::
      </code></ul>
    <br>
  </ul>

  <a name="FileLogattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li><br><br>

    <a name="archivedir"></a>
    <a name="archivecmd"></a>
    <a name="nrarchive"></a>
    <li>archivecmd / archivedir / nrarchive<br>
        Wenn eine neue FileLog-Datei ge&ouml;ffnet wird, wird der FileLog
        archiver aufgerufen.  Das geschieht aber nur , wenn der Name der Datei
        sich ge&auml;ndert hat(abh&auml;ngig von den zeitspezifischen
        Wildcards, die weiter oben unter <a href="#FileLogdefine">FileLog
        (define)</a> beschrieben werden) und gleichzeitig ein neuer Datensatz
        in diese Datei geschrieben werden muss.  <br>

        Wenn das Attribut archivecmd benutzt wird, startet es als
        shell-Kommando ( eine Einbettung in " ist nicht notwendig), und jedes %
        in diesem Befehl wird durch den Namen des alten Logfiles ersetzt.<br>

        Wenn dieses Attribut nicht gesetzt wird, aber daf&uuml;r nrarchive,
        werden nrarchive viele Logfiles im aktuellen Verzeichnis gelassen, und
        &auml;ltere Dateien in das Archivverzeichnis (archivedir) verschoben
        (oder gel&ouml;scht, falls kein archivedir gesetzt wurde).<br>
        Achtung: "&auml;ltere Dateien" sind die, die in der alphabetisch
        sortierten Liste oben sind.<br>
		
        Hinweis: Werden diese Attribute als global instance gesetzt, hat das
        auschlie&szlig;lich auf das <a href="#logfile">FHEM logfile</a>
        Auswirkungen.  </li><br>

    <a name="archiveCompress"></a>
    <li>archiveCompress<br>
        Falls nrarchive, archivedir und archiveCompress gesetzt ist, dann
        werden die Dateien im archivedir komprimiert abgelegt.
        </li><br>

    <a name="createGluedFile"></a>
    <li>createGluedFile<br>
        Falls gesetzt (1), und im SVG-Plot ein Zeitbereich abgefragt wird, was
        in zwei Logdateien gespeichert ist, dann wird f&uuml;r die Anfrage eine
        tempor&auml;re Datei mit dem Inhalt der beiden Dateien erzeugt.
        </li><br>

    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <br>

    <a name="eventOnThreshold"></a>
    <li>eventOnThreshold<br>
        Falls es auf eine (nicht Null-) Zahl gesetzt ist, dann wird das
        linesInTheFile Event generiert, falls die Anzahl der Zeilen in der
        Datei ein Mehrfaches der gesetzen Zahl ist. Achtung: der Z&auml;hler ist
        nur f&uuml;r solche Dateien korrekt, die nach dem Impementieren dieses
        Features angelegt wurden. Ein Absturz/Abschu&szlig; von FHEM
        verf&auml;lscht die Z&auml;hlung.
        </li><br>

    <li><a href="#ignoreRegexp">ignoreRegexp</a></li>

    <a name="logtype"></a>
    <li>logtype<br>
        Wird vom SVG Modul ben&ouml;tigt, um daten grafisch aufzubereiten.
        Der String wird aus komma-separierten Tokens
        (,) erzeugt, wobei jeder Token ein eigenes gnuplot-Programm bezeichnet.
        Die Token k&ouml;nnen Doppelpunkte (:) enthalten. Der Teil vor dem
        Doppelpunkt bezeichnet den Namen des Programms; der Teil nach dem
        Doppelpunkt ist der String, der im Web.Frontend dargestellt werden
        soll. Gegenw&auml;rtig sind folgende Typen von gnuplot-Programmen
        implementiert:<br>

        <ul>
           <li>fs20<br>
               Zeichnet  on als 1 and off als 0. Die geeignete
               filelog-Definition f&uuml;r das Ger&auml;t fs20dev lautet:<br>
               define fslog FileLog log/fs20dev-%Y-%U.log fs20dev
          </li>
           <li>fht<br>
               Zeichnet die Ist-Temperatur/Soll-temperatur/Aktor Kurven. Die
               passende FileLog-Definition (f&uuml;r das FHT-Ger&auml;t mit
               Namen fht1)sieht wie folgt aus: <br>
               <code>define fhtlog1 FileLog log/fht1-%Y-%U.log
                fht1:.*(temp|actuator).*</code>
          </li>
           <li>temp4rain10<br>
               Zeichnet eine Kurve aus der Temperatur und dem Niederschlag (pro
               Stunde und pro Tag) eines KS300. Die dazu passende
               FileLog-Definition (f&uuml;r das KS300
               Ger&auml;t mit Namen ks300) sieht wie folgt aus:<br>
               define ks300log FileLog log/fht1-%Y-%U.log ks300:.*H:.*
          </li>
           <li>hum6wind8<br>
               Zeichnet eine Kurve aus der Feuchtigkeit und der
               Windgeschwindigkeit eines ks300. Die geeignete
               FileLog-Definition ist identisch mit der vorhergehenden
               Definition. Beide programme erzeugen das gleiche Log.
          </li>
           <li>text<br>
               Zeigt das LogFile in seiner urspr&uuml;nglichen Form (Nur
               Text).Eine gnuplot-Definition ist nicht notwendig.
               </li>
        </ul>
        Beispiel:<br> attr ks300log1 logtype
        temp4rain10:Temp/Rain,hum6wind8:Hum/Wind,text:Raw-data
    </li><br>

    <li><a href="#mseclog">mseclog</a></li><br>

    <a name="reformatFn"></a>
    <li>reformatFn<br>
      wird verwendet, um "fremde" Dateien f&uuml;r die SVG-Anzeige ins
      FileLog-Format zu konvertieren. Es enth&auml;lt nur den Namen einer
      Funktion, der mit der urspr&uuml;nglichen Zeile aufgerufen wird.  Z.Bsp.
      um die NTP loopstats Datei zu visualisieren kann man den Wert von
      reformatFn auf ntpLoopstats setzen, und folgende Funktion in
      99_myUtils.pm definieren:
      <pre><code>
      sub            
      ntpLoopstats($)
      {
        my ($d) = @_;
        return $d if($d !~ m/^(\d{5}) (\d+)\.(\d{3}) (.*)$/);
        my ($r, $t) = ($4, FmtDateTime(($1-40587)*86400+$2));
        $t =~ s/ /_/;
        return "$t ntpLoopStats $r";
      }</code></pre>
      </li>
  </ul>
  <br>
</ul>

=end html_DE

=cut
