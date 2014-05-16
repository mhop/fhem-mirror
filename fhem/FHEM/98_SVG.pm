##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
#use Devel::Size qw(size total_size);

# This block is only needed when SVG is loaded bevore FHEMWEB
sub FW_pO(@);
use vars qw($FW_ME);      # webname (default is fhem), needed by 97_GROUP
use vars qw($FW_RET);     # Returned data (html)
use vars qw($FW_RETTYPE); # image/png or the like
use vars qw($FW_cssdir);  # css directory
use vars qw($FW_detail);  # currently selected device for detail view
use vars qw($FW_dir);     # base directory for web server
use vars qw($FW_gplotdir);# gplot directory for web server: the first
use vars qw($FW_plotmode);# Global plot mode (WEB attribute), used by SVG
use vars qw($FW_plotsize);# Global plot size (WEB attribute), used by SVG
use vars qw($FW_room);    # currently selected room
use vars qw($FW_subdir);  # Sub-path in URL, used by FLOORPLAN/weblink
use vars qw($FW_wname);   # Web instance
use vars qw(%FW_hiddenroom); # hash of hidden rooms, used by weblink
use vars qw(%FW_pos);     # scroll position
use vars qw(%FW_webArgs); # all arguments specified in the GET
use vars qw($FW_formmethod);

my $SVG_RET;        # Returned data (SVG)
sub SVG_calcOffsets($$);
sub SVG_doround($$$);
sub SVG_fmtTime($$);
sub SVG_pO($);
sub SVG_readgplotfile($$);
sub SVG_render($$$$$$$$$);
sub SVG_showLog($);
sub SVG_substcfg($$$$$$);
sub SVG_time_align($$);
sub SVG_time_to_sec($);
sub SVG_openFile($$$);

my ($SVG_lt, $SVG_ltstr);
my %SVG_devs;       # hash of from/to entries per device

#####################################
sub
SVG_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "SVG_Define";
  $hash->{AttrList} = "fixedoffset fixedrange startDate plotsize nrAxis label title plotfunction";
  $hash->{SetFn}    = "SVG_Set";
  $hash->{FW_summaryFn} = "SVG_FwFn";
  $hash->{FW_detailFn}  = "SVG_FwFn";
  $hash->{FW_atPageEnd} = 1;
  $data{FWEXT}{"/SVG_WriteGplot"}{CONTENTFUNC} = "SVG_WriteGplot";
  $data{FWEXT}{"/SVG_showLog"}{FUNC} = "SVG_showLog";
}

#####################################
sub
SVG_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $arg) = split("[ \t]+", $def, 3);
  
  if(!$arg ||
     !($arg =~ m/^(.*):(.*):(.*)$/ || $arg =~ m/^(.*):(.*)$/)) {
    return "Usage: define <name> SVG <logdevice>:<gnuplot-file>:<logfile>";
  }

  $hash->{LOGDEVICE} = $1;
  $hash->{GPLOTFILE} = $2;
  $hash->{LOGFILE}   = ($3 ? $3 : "CURRENT");
  $hash->{STATE} = "initialized";
  $hash->{LOGDEVICE} =~ s/^fileplot //; # Autocreate bug.

  return undef;
}

##################
sub
SVG_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};
  return "no set argument specified" if(int(@a) < 2);
  
  my $cmd = $a[1];
  return "Unknown argument $cmd, choose one of copyGplotFile:noArg"
    if($cmd ne "copyGplotFile");

  my $srcName = "$FW_gplotdir/$hash->{GPLOTFILE}.gplot";
  $hash->{GPLOTFILE} = $hash->{NAME};
  my $dstName = "$FW_gplotdir/$hash->{GPLOTFILE}.gplot";
  return "this is already a unique gplot file" if($srcName eq $dstName);
  $hash->{DEF} = $hash->{LOGDEVICE} . ":".
                 $hash->{GPLOTFILE} . ":".
                 $hash->{LOGFILE};

  my ($err,@rows) = FileRead($srcName);
  return $err if($err);
  $err = FileWrite($dstName, @rows);
  return $err;
}

##################
sub
SVG_FwDetail($@)
{
  my ($d, $text, $nobr)= @_;
  return "" if(AttrVal($d, "group", ""));
  my $alias= AttrVal($d, "alias", $d);

  my $ret = ($nobr ? "" : "<br>");
  $ret .= "$text " if($text);
  $ret .= FW_pHPlain("detail=$d", $alias) if(!$FW_subdir);
  $ret .= "<br>";
  return $ret;
}

sub
jsSVG_getAttrs($)
{
  my ($d) = @_;
  return join("&#01;", map { #00 arrives as 65533 in JS
     my $v=$attr{$d}{$_};
     $v =~ s/'/&#39;/g;
    "$_=$v";
  } keys %{$attr{$d}});
}

##################
sub
SVG_FwFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ld = $defs{$hash->{LOGDEVICE}};
  my $ret = "";

  if(AttrVal($FW_wname, "plotmode", "SVG") eq "jsSVG") {

    my @d=split(":",$defs{$d}{DEF});
    my $gplot;
    if(open(FH, "$FW_gplotdir/$d[1].gplot")) {
      $gplot = join("&#01;",<FH>);
      $gplot =~ s/'/&#39;/g;
      $gplot =~ s/\n//g;
    }
    close(FH);

    $ret .= "<div id='jsSVG_$d' class='jsSVG' ".
                "attr='".jsSVG_getAttrs($d)."' ".
                "parentAttr='".jsSVG_getAttrs($FW_wname)."' ".
                "gplotFile='$gplot' source='$d[0]'>".
            "</div>";
    return $ret;
  }


  # plots navigation buttons
  if (AttrVal($d,"plotmode",$FW_plotmode) ne "gnuplot") {
    if((!$pageHash || !$pageHash->{buttons}) &&
       AttrVal($d, "fixedrange", "x") !~ m/^[ 0-9:-]*$/) {

      $ret .= SVG_zoomLink("zoom=-1", "Zoom-in", "zoom in");
      $ret .= SVG_zoomLink("zoom=1",  "Zoom-out","zoom out");
      $ret .= SVG_zoomLink("off=-1",  "Prev",    "prev");
      $ret .= SVG_zoomLink("off=1",   "Next",    "next");
      $pageHash->{buttons} = 1 if($pageHash);
      $ret .= "<br>";
    }
  }

  my $arg="$FW_ME/SVG_showLog?dev=$d".
                "&amp;logdev=$hash->{LOGDEVICE}".
                "&amp;gplotfile=$hash->{GPLOTFILE}".
                "&amp;logfile=$hash->{LOGFILE}".
                "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);

  if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
    my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
    $ret .= "<div class=\"SVGplot\">";
    $ret .= "<embed src=\"$arg\" type=\"image/svg+xml\" " .
          "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
    $ret .= "</div>";

  } else {
    $ret .= "<img src=\"$arg\"/>";
  }

  if(!$pageHash) {
    if($FW_plotmode eq "SVG") {
      $ret .= SVG_PEdit($FW_wname,$d,$room,$pageHash) . "<br>";
    }

  } else {
    $ret .= SVG_FwDetail($d, "", 1) if(!$FW_hiddenroom{detail});

  }

  return $ret;
}

sub
SVG_cb($$$)
{
  my ($v,$t,$c) = @_;
  $c = ($c ? " checked" : "");
  return "<td>$t&nbsp;<input type=\"checkbox\" name=\"$v\" value=\"$v\"$c></td>";
}

sub
SVG_txt($$$$)
{
  my ($v,$t,$c,$sz) = @_;
  $c = "" if(!defined($c));
  $c =~ s/"/\&quot;/g;
  return "$t&nbsp;<input type=\"text\" name=\"$v\" size=\"$sz\" ".
                "value=\"$c\"/>";
}

sub
SVG_sel($$$@)
{
  my ($v,$l,$c,$fnData) = @_;
  my @al = split(",",$l);
  $c =~ s/\\x3a/:/g if($c);
  return FW_select($v,$v,\@al,$c, "set", $fnData);
}

############################
# gnuplot file "editor"
sub
SVG_PEdit($$$$)
{
  my ($FW_wname,$d,$room,$pageHash) = @_;

  my $pe = AttrVal($FW_wname, "ploteditor", "always");

  return "" if( $pe eq 'never' );

  my $ld = $defs{$d}{LOGDEVICE};
  my $ldt = $defs{$ld}{TYPE};

  my $gp = "$FW_gplotdir/$defs{$d}{GPLOTFILE}.gplot";
  
  my ($err, $cfg, $plot, $flog) = SVG_readgplotfile($d, $gp);
  my %conf = SVG_digestConf($cfg, $plot);

  my $ret = "<br>";

  my $pestyle = "";
  if( $pe eq 'onClick' ) {
    my $pgm = "Javascript:" .
               "s=document.getElementById('pedit').style;".
               "s.display = s.display=='none' ? 'block' : 'none';".
               "s=document.getElementById('pdisp').style;".
               "s.display = s.display=='none' ? 'block' : 'none';";
    $ret .= "<a id=\"pdisp\" style=\"cursor:pointer\" onClick=\"$pgm\">Show Plot Editor</a>";
    $pestyle = 'style="display:none"';
  }

  $ret .= "<form $pestyle id=\"pedit\" method=\"$FW_formmethod\" autocomplete=\"off\" ".
                "action=\"$FW_ME/SVG_WriteGplot\">";
  $ret .= "Plot Editor";
  $ret .= FW_hidden("detail", $d); # go to detail after save
  $ret .= FW_hidden("gplotName", $gp);
  $ret .= FW_hidden("logdevicetype", $ldt);
  $ret .= "<table class=\"block wide plotEditor\">";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Plot title</td>";
  $ret .= "<td>".SVG_txt("title", "", $conf{title}, 32)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"odd\">";
  $ret .= "<td>Y-Axis label</td>";
  $conf{ylabel} =~ s/"//g if($conf{ylabel});
  $ret .= "<td>".SVG_txt("ylabel", "left", $conf{ylabel}, 16)."</td>";
  $conf{y2label} =~ s/"//g if($conf{y2label});
  $ret .= "<td>".SVG_txt("y2label","right", $conf{y2label}, 16)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Grid aligned</td>";
  $ret .= SVG_cb("gridy", "left", $conf{hasygrid});
  $ret .= SVG_cb("gridy2","right",$conf{hasy2grid});
  $ret .= "</tr>";
  $ret .= "<tr class=\"odd\">";
  $ret .= "<td>Range as [min:max]</td>";
  $ret .= "<td>".SVG_txt("yrange", "left", $conf{yrange}, 16)."</td>";
  $ret .= "<td>".SVG_txt("y2range", "right", $conf{y2range}, 16)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Tics as (\"Txt\" val, ...)</td>";
  $ret .= "<td>".SVG_txt("ytics", "left", $conf{ytics}, 16)."</td>";
  $ret .= "<td>".SVG_txt("y2tics","right", $conf{y2tics}, 16)."</td>";
  $ret .= "</tr>";

  my $max = @{$conf{lType}}+1;
  $max = 8 if($max > 8);
  my ($desc, $htmlArr, $example) = ("Spec", undef, "");
  if($modules{$ldt}{SVG_sampleDataFn}) {
    no strict "refs";
    ($desc, $htmlArr, $example) = 
        &{$modules{$ldt}{SVG_sampleDataFn}}($ld, $flog, $max,\%conf, $FW_wname);
    use strict "refs";
  } else {
    my @htmlArr; 
    @htmlArr = map { SVG_txt("par_${_}_0","",$flog->[$_] ? $flog->[$_]:"",20) }
                   (0..$max-1);
    $htmlArr = \@htmlArr;
  }

  $ret .= "<tr class=\"odd\"><td>Diagramm label</td>";
  $ret .= "<td>$desc</td>";
  $ret .=" <td>Y-Axis,Plot-Type,Style,Width</td></tr>";

  my @lineStyles;
  if(SVG_openFile($FW_cssdir,
                  AttrVal($FW_wname,"stylesheetPrefix",""), "svg_style.css")) {
    map { push(@lineStyles,$1) if($_ =~ m/^\.(l[^{ ]*)/) } <FH>;
    close(FH);
  }

  my $r = 0;
  for($r=0; $r < $max; $r++) {
    $ret .= "<tr class=\"".(($r&1)?"odd":"even")."\"><td>";
    $ret .= SVG_txt("title_${r}", "", !$conf{lTitle}[$r]&&$r<($max-1) ? 
                                      "notitle" : $conf{lTitle}[$r], 12);
    $ret .= "</td><td>";
    $ret .= $htmlArr->[$r] if($htmlArr && @{$htmlArr} > $r);
    $ret .= "</td><td>";
    my $v = $conf{lAxis}[$r];
    $ret .= SVG_sel("axes_${r}", "left,right", 
                    ($v && $v eq "x1y1") ? "left" : "right");
    $ret .= SVG_sel("type_${r}", "lines,points,steps,fsteps,histeps,bars",
                    $conf{lType}[$r]);
    my $ls = $conf{lStyle}[$r]; 
    if($ls) {
      $ls =~ s/class=//g;
      $ls =~ s/"//g; 
    }
    $ret .= SVG_sel("style_${r}", join(",", @lineStyles), $ls);
    my $lw = $conf{lWidth}[$r]; 
    if($lw) {
      $lw =~ s/.*stroke-width://g;
      $lw =~ s/"//g; 
    }
    $ret .= SVG_sel("width_${r}", "0.2,0.5,1,1.5,2,3,4", ($lw ? $lw : 1));
    $ret .= "</td></tr>";
  }
  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= "Example lines for input:<br>$example</td></tr>";

  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= FW_submit("submit", "Write .gplot file")."</td></tr>";

  $ret .= "</table></form>";
}

##################
# Generate the zoom and scroll images with links if appropriate
sub
SVG_zoomLink($$$)
{
  my ($cmd, $img, $alt) = @_;

  my $prf;
  $cmd =~ m/^(.*);([^;]*)$/;
  if($2) {
    ($prf, $cmd) = ($1, $2);
    $prf =~ s/&pos=.*//;
  }
  my ($d,$off) = split("=", $cmd, 2);

  my $val = $FW_pos{$d};
  $cmd = ($FW_detail ? "detail=$FW_detail":
                        ($prf ? $prf : "room=$FW_room")) . "&amp;pos=";
  if($d eq "zoom") {

    my $n = 0;
    my @FW_zoom = ("hour","qday","day","week","month","year");
    my %FW_zoom = map { $_, $n++ } @FW_zoom;

    $val = "day" if(!$val);
    $val = $FW_zoom{$val};
    return "" if(!defined($val) || $val+$off < 0 || $val+$off >= int(@FW_zoom));
    $val = $FW_zoom[$val+$off];
    return "" if(!$val);

    # Approximation of the next offset.
    my $w_off = $FW_pos{off};
    $w_off = 0 if(!$w_off);

    if ($val eq "hour") {
      $w_off =              $w_off*6;
    } elsif($val eq "qday") {
      $w_off = ($off < 0) ? $w_off*4 : int($w_off/6);
    } elsif($val eq "day") {
      $w_off = ($off < 0) ? $w_off*7 : int($w_off/4);
    } elsif($val eq "week") {
      $w_off = ($off < 0) ? $w_off*4 : int($w_off/7);
    } elsif($val eq "month") {
      $w_off = ($off < 0) ? $w_off*12: int($w_off/4);
    } elsif($val eq "year") {
      $w_off =                         int($w_off/12);
    }
    $cmd .= "zoom=$val;off=$w_off";

  } else {

    return "" if((!$val && $off > 0) || ($val && $val+$off > 0)); # no future
    $off=($val ? $val+$off : $off);
    my $zoom=$FW_pos{zoom};
    $zoom = 0 if(!$zoom);
    $cmd .= "zoom=$zoom;off=$off";

  }

  return "&nbsp;&nbsp;".FW_pHPlain("$cmd", FW_makeImage($img, $alt));
}


sub
SVG_WriteGplot($)
{
  my ($arg) = @_;
  FW_digestCgi($arg);

  if(!defined($FW_webArgs{par_0_0})) {
    FW_pO "missing data in logfile: won't write incomplete .gplot definition";
    return 0;
  }

  my $hasTl;
  for(my $i=0; $i <= 8; $i++) {
    $hasTl = 1 if($FW_webArgs{"title_$i"});
  }
  return 0 if(!$hasTl);

  my $fName = $FW_webArgs{gplotName};
  return if(!$fName);

  my @rows;
  push @rows, "# Created by FHEM/98_SVG.pm, ".TimeNow()."\n";
  push @rows, "set terminal png transparent size <SIZE> crop\n";
  push @rows, "set output '<OUT>.png'\n";
  push @rows, "set xdata time\n";
  push @rows, "set timefmt \"%Y-%m-%d_%H:%M:%S\"\n";
  push @rows, "set xlabel \" \"\n";
  push @rows, "set title '$FW_webArgs{title}'\n";
  push @rows, "set ytics ".$FW_webArgs{ytics}."\n";
  push @rows, "set y2tics ".$FW_webArgs{y2tics}."\n";
  push @rows, "set grid".($FW_webArgs{gridy}  ? " ytics" :"").
                      ($FW_webArgs{gridy2} ? " y2tics":"")."\n";
  push @rows, "set ylabel \"$FW_webArgs{ylabel}\"\n";
  push @rows, "set y2label \"$FW_webArgs{y2label}\"\n";
  push @rows, "set yrange $FW_webArgs{yrange}\n" if($FW_webArgs{yrange});
  push @rows, "set y2range $FW_webArgs{y2range}\n" if($FW_webArgs{y2range});
  push @rows, "\n";

  my $ld = $FW_webArgs{logdevicetype};
  my @plot;
  for(my $i=0; $i <= 8; $i++) {
    next if(!$FW_webArgs{"title_$i"});
    my $prf = "par_${i}_";
    my @v = map {$FW_webArgs{"$prf$_"}}
            grep {defined($FW_webArgs{"$prf$_"})} (0..9);
    my $r = @v > 1 ?
            join(":", map { $v[$_] =~ s/:/\\x3a/g if($_<$#v); $v[$_] } 0..$#v) :
            $v[0];

    push @rows, "#$ld $r\n";
    push @plot, "\"<IN>\" using 1:2 axes ".
                ($FW_webArgs{"axes_$i"} eq "right" ? "x1y2" : "x1y1").
                ($FW_webArgs{"title_$i"} eq "notitle" ? " notitle" :
                            " title '".$FW_webArgs{"title_$i"} ."'").
                " ls "    .$FW_webArgs{"style_$i"} .
                " lw "    .$FW_webArgs{"width_$i"} .
                " with "  .$FW_webArgs{"type_$i"};
  }
  push @rows, "\n";
  push @rows, "plot ".join(",\\\n     ", @plot)."\n";

  my $err = FileWrite($fName, @rows);
  FW_pO "SVG_WriteGplot: $err" if($err);

  return 0;
}

sub
SVG_readgplotfile($$)
{
  my ($wl, $gplot_pgm) = @_;

  ############################
  # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
  # the plot directive with our own, as we offer a file for each line
  my (@filelog, @data, $plot);

  my $ldType = $defs{$defs{$wl}{LOGDEVICE}}{TYPE}
     if($defs{$wl} && $defs{$wl}{LOGDEVICE} && $defs{$defs{$wl}{LOGDEVICE}});
  $ldType = $defs{$wl}{TYPE}
     if(!$ldType && $defs{$wl});

  my ($err, @svgplotfile) = FileRead($gplot_pgm);
  return ("$err", undef) if($err);

  foreach my $l (@svgplotfile) {
    $l = "$l\n" unless $l =~ m/\n$/;
    $l =~ s/\r//g;
    my $plotfn = undef;
    if($l =~ m/^#$ldType (.*)$/) {
      $plotfn = $1;
    } elsif($l =~ "^plot" || $plot) {
      $plot .= $l;
    } else {
      push(@data, $l);
    }
    
    if($plotfn) {
      my $specval = AttrVal($wl, "plotfunction", undef);
      if ($specval) {
        my @spec = split(" ",$specval);
        my $spec_count=1;
        foreach (@spec) {
          $plotfn =~ s/<SPEC$spec_count>/$_/g;
          $spec_count++;
        }
      }
      push(@filelog, $plotfn);
    }
  }

  return (undef, \@data, $plot, \@filelog);
}

sub
SVG_substcfg($$$$$$)
{
  my ($splitret, $wl, $cfg, $plot, $file, $tmpfile) = @_;

  # interpret title and label as a perl command and make
  # to all internal values e.g. $value.

  my $oll = $attr{global}{verbose};
  $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged

  my $ldt = $defs{$defs{$wl}{LOGDEVICE}}{TYPE}
        if($defs{$wl} && $defs{$wl}{LOGDEVICE});
  $ldt = "" if(!defined($ldt));
  if($file eq "CURRENT" && $ldt eq "FileLog") {
    $file = $defs{$defs{$wl}{LOGDEVICE}}{currentlogfile};
    $file =~ s+.*/++;
  }
  my $fileesc = $file;
  $fileesc =~ s/\\/\\\\/g;      # For Windows, by MarkusRR
  my $title = AttrVal($wl, "title", "\"$fileesc\"");

  $title = AnalyzeCommand(undef, "{ $title }");
  my $label = AttrVal($wl, "label", undef);
  my @g_label;
  if ($label) {
    @g_label = split("::",$label);
    foreach (@g_label) {
      $_ = AnalyzeCommand(undef, "{ $_ }");
    }
  }
  $attr{global}{verbose} = $oll;

  my $gplot_script = join("", @{$cfg});
  $gplot_script .=  $plot if(!$splitret);

  $gplot_script =~ s/<OUT>/$tmpfile/g;
  $gplot_script =~ s/<IN>/$file/g;

  my $ps = AttrVal($wl,"plotsize",$FW_plotsize);
  $gplot_script =~ s/<SIZE>/$ps/g;

  $gplot_script =~ s/<TL>/$title/g;
  my $g_count=1; 
  if ($label) {
    foreach (@g_label) {
      $gplot_script =~ s/<L$g_count>/$_/g;
      $plot =~ s/<L$g_count>/$_/g;
      $g_count++;
    }
  }

  $plot =~ s/\r//g;             # For our windows friends...
  $gplot_script =~ s/\r//g;

  if($splitret == 1) {
    my @ret = split("\n", $gplot_script); 
    return (\@ret, $plot);
  } else {
    return $gplot_script;
  }
}

sub
SVG_tspec($$@)
{
  my ($n,$e) = (shift,shift);
  for(my $i=1; $i<$n; $i++) {
    $_[$i] = 0;
  }
  return sprintf("%04d-%02d-%02d_%02d:%02d:%02d",
                 $_[5]+1900,$_[4]+1,$_[3],$_[2],$_[1],$e);
}

##################
# Calculate either the number of scrollable SVGs (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
SVG_calcOffsets($$)
{
  my ($d,$wl) = @_;

  my $pm = AttrVal($d,"plotmode",$FW_plotmode);
  return if($pm eq "gnuplot");

  my ($fr, $fo);
  my $frx; #fixedrange with offset
  if($defs{$wl}) {
    $fr = AttrVal($wl, "fixedrange", undef);
    if($fr) {
      if($fr =~ "^(hour|qday|day|week|month|year)" ||
         $fr =~ m/^\d+days$/ ) { #fixedrange with offset
        $frx=$fr; #fixedrange with offset

      } else {
        my @range = split(" ", $fr);
        my @t = localtime;
        $SVG_devs{$d}{from} = ResolveDateWildcards($range[0], @t);
        $SVG_devs{$d}{to} = ResolveDateWildcards($range[1], @t); 
        return;

      }
    }

    $fo = AttrVal( $wl, "fixedoffset", undef);
  }

  my $off = $FW_pos{$d};
  $off = 0 if(!$off);
  $off += $FW_pos{off} if($FW_pos{off});
  $off = $fo if(defined($fo) && $fo =~ m/^[+-]?\d+$/);

  my $now;
  my $st = AttrVal($wl, "startDate", undef);
  if($st) {
    $now = mktime(0,0,12,$3,$2-1,$1-1900,0,0,-1)
      if($st =~ m/(\d\d\d\d)-(\d\d)-(\d\d)/);
  }
  $now = time() if(!$now);

  my $zoom = $FW_pos{zoom};
  $zoom = "day" if(!$zoom);
  $zoom = $fr if(defined($fr)); 
  $zoom = $frx if ($frx); #fixedrange with offset  
  my @zrange = split(" ", $zoom); #fixedrange with offset
  if(defined($zrange[1])) { $off += $zrange[1]; $zoom=$zrange[0]; }  #fixedrange with offset

  my $endPlotNow = (AttrVal($FW_wname, "endPlotNow", undef) && !$st);
  if($zoom eq "hour") {
    if($endPlotNow) {
      my $t = int(($now + $off*3600 - 3600)/300.0)*300 + 300;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(1,0,@l);
      @l = localtime($t+3600);
      $SVG_devs{$d}{to}   = SVG_tspec(1,1,@l);
    } else { 
      my $t = $now + $off*3600;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(2,0,@l);
      @l = localtime($t+3600);
      $SVG_devs{$d}{to}   = SVG_tspec(2,1,@l);
    }

  } elsif($zoom eq "qday") {
    if($endPlotNow) {
      my $t = int(($now + $off*21600 - 21600)/300.0)*300 + 300;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(1,0,@l);
      @l = localtime($t+21600);
      $SVG_devs{$d}{to}   = SVG_tspec(1,1,@l);
    } else { 
      my $t = $now + $off*21600;
      my @l = localtime($t);
      $l[2] = int($l[2]/6)*6;
      $SVG_devs{$d}{from} = SVG_tspec(2,0,@l);
      @l = localtime($t+21600);
      $l[2] = int($l[2]/6)*6;
      $SVG_devs{$d}{to}   = SVG_tspec(2,1,@l);
    }

  } elsif($zoom =~ m/^(\d+)?day/) {
    my $nDays = $1 ? ($1-1) : 0;
    if($endPlotNow) {
      my $t = int(($now + ($off-$nDays-1)*86400)/900.0)*900 + 900;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(1,0,@l);
      @l = localtime($t+(1+$nDays)*86400);
      $SVG_devs{$d}{to}   = SVG_tspec(1,1,@l);
    } else { 
      my $t = $now + ($off-$nDays)*86400;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(3,0,@l);
      @l = localtime($t+(1+$nDays)*86400);
      $SVG_devs{$d}{to}   = SVG_tspec(3,1,@l);
    }

  } elsif($zoom eq "week") {
    my @l = localtime($now);
    my $start = (AttrVal($FW_wname, "endPlotToday", undef) ? 6 : $l[6]);
    my $t = $now - ($start*86400) + ($off*86400)*7;
    @l = localtime($t);
    $SVG_devs{$d}{from} = SVG_tspec(3,0,@l);
    @l = localtime($t+7*86400);
    $SVG_devs{$d}{to}   = SVG_tspec(3,1,@l);

 } elsif($zoom eq "month") {
    my ($endDay, @l);
    if(AttrVal($FW_wname, "endPlotToday", undef)) {
      @l = localtime($now+86400);
      $endDay = $l[3];
      $off--;
    } else {
      @l = localtime($now);
      $endDay = 1;
    }
    while($off < -12) { # Correct the year
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $l[3] = $endDay;
    $SVG_devs{$d}{from} = SVG_tspec(3,0,@l);
    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $SVG_devs{$d}{to}   = SVG_tspec(3,1,@l);

  } elsif($zoom eq "year") {
    my @l = localtime($now);
    $l[5] += $off;
    $SVG_devs{$d}{from} = sprintf("%04d-01-01_00:00:00", $l[5]+1900);
    $SVG_devs{$d}{to}   = sprintf("%04d-01-01_00:00:01", $l[5]+1901);

  }
}


######################
# Generate an image from the log via gnuplot or SVG
sub
SVG_showLog($)
{
  my ($cmd) = @_;
  my $wl   = $FW_webArgs{dev};
  my $d    = $FW_webArgs{logdev};
  my $type = $FW_webArgs{gplotfile};
  my $file = $FW_webArgs{logfile};
  my $pm = AttrVal($wl,"plotmode",$FW_plotmode);

  my $gplot_pgm = "$FW_gplotdir/$type.gplot";

  my ($err, $cfg, $plot, $flog) = SVG_readgplotfile($wl, $gplot_pgm);
  if($err) {
    my $msg = "Cannot read $gplot_pgm";
    Log3 $FW_wname, 1, $msg;

    if($pm =~ m/SVG/) { # FW_fatal for SVG:
      $FW_RETTYPE = "image/svg+xml";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg">';
      FW_pO '<text x="20" y="20">'.$msg.'</text>';
      FW_pO '</svg>';
      return ($FW_RETTYPE, $FW_RET);

    } else {
      return ($FW_RETTYPE, $msg);

    }
  }
  SVG_calcOffsets($d,$wl);

  if($pm =~ m/gnuplot/) {

    my $tmpfile = "/tmp/file.$$";
    my $errfile = "/tmp/gnuplot.err";

    if($pm eq "gnuplot" || !$SVG_devs{$d}{from}) {
      # Fix range, as we are without scroll
      my $f = 0;     # From the beginning of time...
      my $t = 9;     # till the end

      # Read the data from the filelog
      my $oll = $attr{global}{verbose};
      $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged
      my @path = split(" ", FW_fC("get $d $file $tmpfile $f $t " .
                                  join(" ", @{$flog})));
      $attr{global}{verbose} = $oll;

      # replace the path with the temporary filenames of the filelog output
      my $i = 0;
      $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
      my $xrange = "\n";        #We don't have a range, but need the new line
      foreach my $p (@path) {   # If the file is empty, write a 0 line
        next if(!-z $p);
        open(FH, ">$p");
        print FH "$f 0\n";
        close(FH);
      }

      my $gplot_script = SVG_substcfg(0, $wl, $cfg, $plot, $file, $tmpfile);

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script, $xrange, $plot;
      close(FH);

    } elsif($pm eq "gnuplot-scroll") {
      # Read the data from the filelog
      my ($f,$t)=($SVG_devs{$d}{from}, $SVG_devs{$d}{to});
      my $oll = $attr{global}{verbose};
      $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged
      my @path = split(" ", FW_fC("get $d $file $tmpfile $f $t " .
                                  join(" ", @{$flog})));
      $attr{global}{verbose} = $oll;

      # replace the path with the temporary filenames of the filelog output
      my $i = 0;
      $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
      my $xrange = "set xrange [\"$f\":\"$t\"]\n";
      foreach my $p (@path) {   # If the file is empty, write a 0 line
        next if(!-z $p);
        open(FH, ">$p");
        print FH "$f 0\n";
        close(FH);
      }

      my $gplot_script = SVG_substcfg(0, $wl, $cfg, $plot, $file, $tmpfile);

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script, $xrange, $plot;
      close(FH);
      foreach my $p (@path) {
        unlink($p);
      }
    }
    $FW_RETTYPE = "image/png";
    open(FH, "$tmpfile.png");         # read in the result and send it
    binmode (FH); # necessary for Windows
    FW_pO join("", <FH>);
    close(FH);
    unlink("$tmpfile.png");

  } elsif($pm eq "SVG") {
    my ($f,$t)=($SVG_devs{$d}{from}, $SVG_devs{$d}{to});
    $f = 0 if(!$f);     # From the beginning of time...
    $t = 9 if(!$t);     # till the end

    Log3 $FW_wname, 5,
        "plotcommand: get $d $file INT $f $t " . join(" ", @{$flog});

    $FW_RETTYPE = "image/svg+xml";

    (my $cachedate = TimeNow()) =~ s/ /_/g;
    my $SVGcache = (AttrVal($FW_wname, "SVGcache", undef) && $t lt $cachedate);
    my $cDir = "$FW_dir/SVGcache";
    my $cName = "$cDir/$wl-$f-$t.svg";
    if($SVGcache && open(CFH, $cName)) {
      FW_pO join("", <CFH>);
      close(CFH);

    } else {
      FW_fC("get $d $file INT $f $t " . join(" ", @{$flog}), 1);
      ($cfg, $plot) = SVG_substcfg(1, $wl, $cfg, $plot, $file, "<OuT>");
      my $ret = SVG_render($wl, $f, $t, $cfg,
                        $internal_data, $plot, $FW_wname, $FW_cssdir, $flog);
      FW_pO $ret;
      if($SVGcache) {
        mkdir($cDir) if(! -d $cDir);
        if(open(CFH, ">$cName")) {
          print CFH $ret;
          close(CFH);
        }
      }
    }

  }
  return ($FW_RETTYPE, $FW_RET);

}


######################
# Convert the configuration to a "readable" form -> array to hash
sub
SVG_digestConf($$)
{
  my ($confp,$plot) = @_;

  my %conf;
  map { chomp; my @a=split(" ",$_, 3);
        if($a[0] && $a[0] eq "set") { $conf{lc($a[1])} = $a[2]; }
      } @{$confp};

  $conf{title} = "" if(!defined($conf{title}));
  $conf{title} =~ s/'//g;

  ######################
  # Digest grid
  my $t = ($conf{grid} ? $conf{grid} : "");
  #$conf{hasxgrid} = ( $t =~ /.*xtics.*/ ? 1 : 0); # Unused
  $conf{hasygrid} = ( $t =~ /.*ytics.*/ ? 1 : 0);
  $conf{hasy2grid}= ( $t =~ /.*y2tics.*/ ? 1 : 0);

  # Digest axes/title/etc from $plot (gnuplot) and draw the line-titles
  my (@lAxis,@lTitle,@lType,@lStyle,@lWidth);
  my ($i, $pTemp);
  $pTemp = $plot; $i = 0; $pTemp =~ s/ axes (\w+)/$lAxis[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ title '([^']*)'/$lTitle[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ with (\w+)/$lType[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ ls (\w+)/$lStyle[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ lw ([\w.]+)/$lWidth[$i++]=$1/gse;

  for my $i (0..int(@lType)-1) {         # lAxis is optional
    $lAxis[$i] = "x1y2" if(!$lAxis[$i]);
    $lStyle[$i] = "class=\"". (defined($lStyle[$i]) ? $lStyle[$i] : "l$i")."\"";
    $lWidth[$i] = (defined($lWidth[$i]) ?
                        "style=\"stroke-width:$lWidth[$i]\"" :"");
  }

  $conf{lAxis}  = \@lAxis;
  $conf{lTitle} = \@lTitle;
  $conf{lType}  = \@lType;
  $conf{lStyle} = \@lStyle;
  $conf{lWidth} = \@lWidth;
  return %conf;
}

sub
SVG_openFile($$$)
{
  my ($dir, $prf, $fName) = @_;
  my $baseStyle = $prf;
  $baseStyle =~ s/(touchpad|smallscreen)//;
  if(open(FH, "$dir/${prf}$fName") ||
     open(FH, "$dir/${baseStyle}$fName") ||
     open(FH, "$dir/$fName")) {
    return 1;
  }
  return 0;
}

#####################################
sub
SVG_render($$$$$$$$$)
{
  my $name = shift;  # e.g. wl_8
  my $from = shift;  # e.g. 2008-01-01
  my $to = shift;    # e.g. 2009-01-01
  my $confp = shift; # lines from the .gplot file, w/o FileLog and plot
  my $dp = shift;    # pointer to data (one string)
  my $plot = shift;  # Plot lines from the .gplot file
  my $parent_name = shift;  # e.g. FHEMWEB instance name
  my $parent_dir  = shift;  # FW_dir
  my $flog        = shift;  # #FileLog lines, as array pointer

  $SVG_RET="";
  my $SVG_ss = AttrVal($parent_name, "smallscreen", 0);
  return $SVG_RET if(!defined($dp));

  my $nr_axis = AttrVal($parent_name,"nrAxis","1,1");
  my ($nr_left_axis,$nr_right_axis,$use_left_axis,$use_right_axis) = split(",", AttrVal($name,"nrAxis",$nr_axis));
  $use_left_axis = $nr_left_axis if( !defined($use_left_axis) );
  $use_right_axis = $nr_right_axis if( !defined($use_right_axis) );

  my $th = 16;                          # "Font" height
  my $axis_width = ($SVG_ss ? 2 : 3)*$th;
  my ($x, $y) = ($axis_width*$nr_left_axis,  1.2*$th);      # Rect offset

  ######################
  # Convert the configuration to a "readable" form -> array to hash
  my %conf = SVG_digestConf($confp, $plot);

  my $ps = "800,400";
  $ps = $1 if($conf{terminal} =~ m/.*size[ ]*([^ ]*)/);
  my ($ow,$oh) = split(",", $ps);       # Original width
  my ($w, $h) = ($ow-$nr_left_axis*$axis_width-$nr_right_axis*$axis_width, $oh-2*$y);   # Rect size

  # Keep only the Filter part of the #FileLog
  $flog = join(" ", map { my @a=split(":",$_);
                          $a[1]=~s/\.[^\.]*$//; $a[1]; } @{$flog});
  $flog = AttrVal($parent_name, "longpollSVG", 0) ? "flog=\" $flog \"" : "";

  ######################
  # Html Header
  SVG_pO '<?xml version="1.0" encoding="UTF-8"?>';
  SVG_pO '<!DOCTYPE svg>';
  SVG_pO '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" '.
         'xmlns:xlink="http://www.w3.org/1999/xlink" '.$flog.'>';

  my $prf = AttrVal($parent_name, "stylesheetPrefix", "");
  SVG_pO "<style type=\"text/css\"><![CDATA[";
  if(SVG_openFile($parent_dir, $prf, "svg_style.css")) {
    SVG_pO join("", <FH>);
    close(FH);
  } else {
    Log3 $name, 0, "Can't open $parent_dir/svg_style.css"
  }
  SVG_pO "]]></style>";

  ######################
  # gradient definitions
  if(SVG_openFile($parent_dir, $prf, "svg_defs.svg")) {
    SVG_pO join("", <FH>);
    close(FH);
  } else {
    Log3 $name, 0, "Can't open $parent_dir/svg_defs.svg"
  }

  ######################
  # Rectangle
  SVG_pO "<rect x=\"$x\" y=\"$y\" width =\"$w\" height =\"$h\" rx=\"8\" ry=\"8\" ".
        "fill=\"none\" class=\"border\"/>";

  my ($off1,$off2) = ($x+$w/2, 3*$y/4);
  my $title = ($conf{title} ? $conf{title} : " ");
  $title =~ s/</&lt;/g;
  $title =~ s/>/&gt;/g;
  SVG_pO "<text id=\"svg_title\" x=\"$off1\" y=\"$off2\" " .
        "class=\"title\" text-anchor=\"middle\">$title</text>";

  ######################
  # Copy and Paste labels, hidden by default
  SVG_pO "<text id=\"svg_paste\" x=\"" . ($ow-$axis_width-$nr_right_axis*$axis_width) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_paste(evt)\" " .
        "class=\"paste\" text-anchor=\"end\"> </text>";
  SVG_pO "<text id=\"svg_copy\" x=\"" . ($ow-$nr_right_axis*$axis_width) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_copy(evt)\" " .
        "class=\"copy\" text-anchor=\"end\"> </text>";

  ######################
  # Left label = ylabel and right label = y2label
  if(!$SVG_ss) {
    for my $idx (1..$use_left_axis)  {
      my $name = "y".($idx)."label";
      $name = "ylabel" if( $idx == 1 );
      my $t = ($conf{$name} ? $conf{$name} : "");
      $t =~ s/"//g;
      ($off1,$off2) = ($x-($idx)*$axis_width+3*$th/4, $oh/2);
      SVG_pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
          "class=\"ylabel\" transform=\"rotate(270,$off1,$off2)\">$t</text>";
    }

    for my $idx ($use_left_axis+1..$use_left_axis+$use_right_axis)  {
      my $name = "y".($idx)."label";
      $name = "ylabel" if( $idx == 1 );
      my $t = ($conf{$name} ? $conf{$name} : "");
      $t =~ s/"//g;
      ($off1,$off2) = ($x+$w+($idx-$use_left_axis)*$axis_width-$th/4, $oh/2);
      SVG_pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
          "class=\"y2label\" transform=\"rotate(270,$off1,$off2)\">$t</text>";
    }
  }

  ######################
  ($off1,$off2) = ($ow-$nr_right_axis*$axis_width-$th, $y+$th);


  ######################
  # Plot caption (title)
  for my $i (0..int(@{$conf{lTitle}})-1) {
    my $j = $i+1;
    my $t = $conf{lTitle}[$i];
    my $desc = "";
    if(defined($data{"min$j"}) && $data{"min$j"} ne "undef") {
      $desc = sprintf("%s: Min:%g Max:%g Last:%g",
        $t, $data{"min$j"}, $data{"max$j"}, $data{"currval$j"});
    }
    SVG_pO "<text title=\"$desc\" ".
          "onclick=\"parent.svg_labelselect(evt)\" line_id=\"line_$i\" " .
          "x=\"$off1\" y=\"$off2\" text-anchor=\"end\" ".
                "$conf{lStyle}[$i]>$t</text>";
    $off2 += $th;
  }

  ######################
  # Loop over the input, digest dates, calculate min/max values
  my ($fromsec, $tosec);
  $fromsec = SVG_time_to_sec($from) if($from ne "0"); # 0 is special
  $tosec   = SVG_time_to_sec($to)   if($to ne "9");   # 9 is special
  my $tmul; 
  $tmul = $w/($tosec-$fromsec) if($tosec && $fromsec);

  my ($min, $max, $idx) = (99999999, -99999999, 0);
  my (%hmin, %hmax, @hdx, @hdy);
  my ($dxp, $dyp) = (\(), \());

  my ($d, $v, $ld, $lv) = ("","","","");

  my ($dpl,$dpoff,$l) = (length($$dp), 0, "");
  while($dpoff < $dpl) {                # using split instead is memory hog
    my $ndpoff = index($$dp, "\n", $dpoff);
    if($ndpoff == -1) {
      $l = substr($$dp, $dpoff);
    } else {
      $l = substr($$dp, $dpoff, $ndpoff-$dpoff);
    }
    $dpoff = $ndpoff+1;
    if($l =~ m/^#/) {
      my $a = $conf{lAxis}[$idx];
      if(defined($a)) {
        $hmin{$a} = $min if(!defined($hmin{$a}) || $hmin{$a} > $min);
        $hmax{$a} = $max if(!defined($hmax{$a}) || $hmax{$a} < $max);
      }
      ($min, $max) = (99999999, -99999999);
      $hdx[$idx] = $dxp; $hdy[$idx] = $dyp;
      ($dxp, $dyp) = (\(), \());
      $idx++;

    } else {
      ($d, $v) = split(" ", $l);
      $d =  ($tmul ? int((SVG_time_to_sec($d)-$fromsec)*$tmul) : $d);
      if($ld ne $d || $lv ne $v) {              # Saves a lot on year zoomlevel
        $ld = $d; $lv = $v;
        push @{$dxp}, $d;
        push @{$dyp}, $v;
        $min = $v if($min > $v);
        $max = $v if($max < $v);
      }
    }
    last if($ndpoff == -1);
  }

  $dxp = $hdx[0];
  if(($dxp && int(@{$dxp}) < 2 && !$tosec) ||   # not enough data and no range...
     (!$tmul && !$dxp)) {
    SVG_pO "</svg>";
    return $SVG_RET;
  }
  if(!$tmul) {                     # recompute the x data if no range sepcified
    $fromsec = SVG_time_to_sec($dxp->[0]) if(!$fromsec);
    $tosec = SVG_time_to_sec($dxp->[int(@{$dxp})-1]) if(!$tosec);
    $tmul = $w/($tosec-$fromsec);

    for my $i (0..@hdx-1) {
      $dxp = $hdx[$i];
      for my $i (0..@{$dxp}-1) {
        $dxp->[$i] = int((SVG_time_to_sec($dxp->[$i])-$fromsec)*$tmul);
      }
    }
  }


  ######################
  # Compute & draw vertical tics, grid and labels
  my $ddur = ($tosec-$fromsec)/86400;
  my ($first_tag, $tag, $step, $tstep, $aligntext,  $aligntics);
  
  if ($ddur <= 0.1) {
    $first_tag=". 2 1"; $tag=": 3 4"; $step = 300; $tstep = 60;
  } elsif($ddur <= 0.5) {
    $first_tag=". 2 1"; $tag=": 3 4"; $step = 3600; $tstep = 900;
  } elsif($ddur <= 1.1) {       # +0.1 -> DST
    $first_tag=". 2 1"; $tag=": 3 4"; $step = 4*3600; $tstep = 3600;
  } elsif ($ddur <= 7.1) {
    $first_tag=". 6";   $tag=". 2 1"; $step = 24*3600; $tstep = 6*3600;
  } elsif ($ddur <= 31.1) {
    $first_tag=". 6";   $tag=". 2 1"; $step = 7*24*3600; $tstep = 24*3600;
    $aligntext = 1;
  } else {
    $first_tag=". 6";   $tag=". 1";   $step = 28*24*3600; $tstep = 28*24*3600;
    $aligntext = 2; $aligntics = 2;
  }

  my $barwidth = $tstep;

  ######################
  # First the tics
  $off2 = $y+4;
  my ($off3, $off4) = ($y+$h-4, $y+$h);
  my $initoffset = $tstep;
  $initoffset = int(($tstep/2)/86400)*86400 if($aligntics);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $tstep) {
    $i = SVG_time_align($i,$aligntics);
    $off1 = int($x+($i-$fromsec)*$tmul);
    SVG_pO "<polyline points=\"$off1,$y $off1,$off2\"/>";
    SVG_pO "<polyline points=\"$off1,$off3 $off1,$off4\"/>";
  }

  ######################
  # then the text and the grid
  $off1 = $x;
  $off2 = $y+$h+$th;
  my $t = SVG_fmtTime($first_tag, $fromsec);
  SVG_pO "<text x=\"0\" y=\"$off2\" class=\"ylabel\">$t</text>";
  $initoffset = $step;
  $initoffset = int(($step/2)/86400)*86400 if($aligntext);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $step) {
    $i = SVG_time_align($i,$aligntext);
    $off1 = int($x+($i-$fromsec)*$tmul);
    $t = SVG_fmtTime($tag, $i);
    SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
              "text-anchor=\"middle\">$t</text>";
    SVG_pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>";
  }


  ######################
  # Left and right axis tics / text / grid
  #-- just in case we have only one data line, but want to draw both axes
  $hmin{x1y1}=$hmin{x1y2}, $hmax{x1y1}=$hmax{x1y2} if(!defined($hmin{x1y1}));
  $hmin{x1y2}=$hmin{x1y1}, $hmax{x1y2}=$hmax{x1y1} if(!defined($hmin{x1y2}));

  my (%hstep,%htics,%axdrawn);
  
  #-- yrange handling for axes x1y1..x1y8
  for my $idx (0..7)  {
    my $a = "x1y".($idx+1);
    next if( !defined($hmax{$a}) || !defined($hmin{$a}) );
    my $yra="y".($idx+1)."range";
    $yra="yrange" if ($yra eq "y1range");  
    #-- yrange is specified in plotfile
    if($conf{$yra} && $conf{$yra} =~ /\[(.*):(.*)\]/) {
      $hmin{$a} = $1 if($1 ne "");
      $hmax{$a} = $2 if($2 ne "");
    }
    #-- tics handling
    my $yt="y".($idx+1)."tics";
    $yt="ytics" if ($yt eq"y1tics");
    $htics{$a} = defined($conf{$yt}) ? $conf{$yt} : "";
    
    #-- Round values, compute a nice step  
    my $dh = $hmax{$a} - $hmin{$a};
    my ($step, $mi, $ma) = (1, 1, 1);
    my @limit = (0.001, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50,
                 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000,
                 200000, 500000, 1000000, 2000000);

    for my $li (0..$#limit-1) {
      my $l = $limit[$li];
      next if($dh > $l*10);
      $ma = $conf{$yra} ? $hmax{$a} : SVG_doround($hmax{$a}, $l, 1);
      $mi = $conf{$yra} ? $hmin{$a} : SVG_doround($hmin{$a}, $l, 0);
      if(($ma-$mi)/$l >= 7) {    # If more then 7 steps, then choose next
        $l = $limit[$li+1];
        $ma = $conf{$yra} ? $hmax{$a} : SVG_doround($hmax{$a}, $l, 1);
        $mi = $conf{$yra} ? $hmin{$a} : SVG_doround($hmin{$a}, $l, 0);
      }
      $step = $l;
      last;
    }
    if($step==0.001 && $hmax{$a}==$hmin{$a}) { # Don't want 0.001 range for nil
       $step = 1;
       $ma = $mi + $step;
    }
    $hmax{$a}    = $ma;
    $hmin{$a}    = $mi;
    $hstep{$a}   = $step;
    $axdrawn{$a} = 0;
    
    #Log3 $name, 2, "Axis $a has interval [$hmin{$a},$hmax{$a}], step $hstep{$a}, tics $htics{$a}\n";
  }

  #-- run through all axes for drawing (each only once !) 
  foreach my $a (sort keys %hmin) {
    next if( $axdrawn{$a} );
    $axdrawn{$a}=1;
   
    next if(!defined($hmin{$a})); # Bogus case

    #-- safeguarding against pathological data
    if( !$hstep{$a} ){
        $hmax{$a} = $hmin{$a}+1;
        $hstep{$a} = 1;
    }

    #-- Draw the y-axis values and grid
    my $dh = $hmax{$a} - $hmin{$a};
    my $hmul = $dh>0 ? $h/$dh : $h;
   
    # offsets
    my ($align,$display,$cll);
    if( $a =~ m/x1y(\d)/ ) {
      my $idx = $1;
      if( $idx <= $use_left_axis ) {
        $off1 = $x - ($idx-1)*$axis_width-4-$th*0.3;
        $off3 = $x - ($idx-1)*$axis_width-4;
        $off4 = $off3+5;
        $align = " text-anchor=\"end\"";
        $display = "";
        $cll = "";
      } elsif( $idx <= $use_left_axis+$use_right_axis ) {
        $off1 = $x+4+$w+($idx-1-$use_left_axis)*$axis_width+$th*0.3;
        $off3 = $x+4+$w+($idx-1-$use_left_axis)*$axis_width-5;
        $off4 = $off3+5;
        $align = "";
        $display = "";
        $cll = "";
      } else {
        $off1 = $x-$th*0.3+30;
        $off3 = $x+30;
        $off4 = $off3+5;
        $align = " text-anchor=\"end\"";
        $display = " display=\"none\" id=\"hline_$idx\"";
        $cll = " class=\"l$idx\"";
      }
    };
    
    #-- grouping
    SVG_pO "<g$display>";
    my $yp = $y + $h;
    
    #-- axis if not left or right axis
    SVG_pO "<polyline points=\"$off3,$y $off3,$yp\" $cll/>" if( ($a ne "x1y1") && ($a ne "x1y2") );

    #-- tics handling
    my $tic = $htics{$a};
    #-- tics as in the config-file
    if($tic && $tic !~ m/mirror/) {
      $tic =~ s/^\((.*)\)$/$1/;   # Strip ()
      foreach my $onetic (split(",", $tic)) {
        $onetic =~ s/^ *(.*) *$/$1/;
        my ($tlabel, $tvalue) = split(" ", $onetic);
        $tlabel =~ s/^"(.*)"$/$1/;
        $tvalue = 0 if( !$tvalue );

        $off2 = int($y+($hmax{$a}-$tvalue)*$hmul);
        #-- tics
        SVG_pO "<polyline points=\"$off3,$off2 $off4,$off2\" $cll/>";
        #--grids
        my $off6 = $x+$w;
        if( ($a eq "x1y1") && $conf{hasygrid} )  {
          SVG_pO "<polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($tvalue > $hmin{$a} && $tvalue < $hmax{$a});
        }elsif( ($a eq "x1y2") && $conf{hasy2grid} )  {
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($tvalue > $hmin{$a} && $tvalue < $hmax{$a});
        }
        $off2 += $th/4;
        #--  text
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$tlabel</text>";
      }
    #-- tics automatically 
    } elsif( $hstep{$a}>0 ) {            
      for(my $i = $hmin{$a}; $i <= $hmax{$a}; $i += $hstep{$a}) {
        $off2 = int($y+($hmax{$a}-$i)*$hmul);
        #-- tics
        SVG_pO "  <polyline points=\"$off3,$off2 $off4,$off2\" $cll/>";
        #--grids
        my $off6 = $x+$w;
        if( ($a eq "x1y1") && $conf{hasygrid} )  {
          my $off6 = $x+$w;
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }elsif(  ($a eq "x1y2") && $conf{hasy2grid} )  {
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }
        $off2 += $th/4;
        #--  text   
        my $txt = sprintf("%g", $i);
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$txt</text>";
      }
    }
    SVG_pO "</g>";

  }

  ######################
  # Second loop over the data: draw the measured points
  for(my $idx=$#hdx; $idx >= 0; $idx--) {
    my $a = $conf{lAxis}[$idx];

    SVG_pO "<!-- Warning: No axis for data item $idx defined -->" if(!defined($a));
    next if(!defined($a));
    $min = $hmin{$a};
    $hmax{$a} += 1 if($min == $hmax{$a});  # Else division by 0 in the next line
    my $hmul = $h/($hmax{$a}-$min);
    my $ret = "";
    my ($dxp, $dyp) = ($hdx[$idx], $hdy[$idx]);
    SVG_pO "<!-- Warning: No data item $idx defined -->" if(!defined($dxp));
    next if(!defined($dxp));

    my $yh = $y+$h;
    #-- Title attributes
    my $tl = $conf{lTitle}[$idx] ? $conf{lTitle}[$idx]  : "";
    #my $dec = int(log($hmul*3)/log(10)); # perl can be compiled without log() !
    my $dec = length(sprintf("%d",$hmul*3))-1;
    $dec = 0 if($dec < 0);
    my $attributes = "id=\"line_$idx\" decimals=\"$dec\" ".
          "x_off=\"$fromsec\" x_min=\"$x\" x_mul=\"$tmul\" ".
          "y_h=\"$yh\" y_min=\"$min\" y_mul=\"$hmul\" title=\"$tl\" ".
          "onclick=\"parent.svg_click(evt)\" ".
                "$conf{lWidth}[$idx] $conf{lStyle}[$idx]";
    my $isFill = ($conf{lStyle}[$idx] =~ m/fill/);

    my ($lx, $ly) = (-1,-1);

    if($conf{lType}[$idx] eq "points" ) {
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $ly = $x1; $ly = $y1;
        $ret =  sprintf(" %d,%d %d,%d %d,%d %d,%d %d,%d",
              $x1-3,$y1, $x1,$y1-3, $x1+3,$y1, $x1,$y1+3, $x1-3,$y1);
        SVG_pO "<polyline $attributes points=\"$ret\"/>";
      }

    } elsif($conf{lType}[$idx] eq "steps" || $conf{lType}[$idx] eq "fsteps" ) {

      $ret .=  sprintf(" %d,%d", $x+$dxp->[0], $y+$h) if($isFill && @{$dxp});
      if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
      } else {
        foreach my $i (1..int(@{$dxp})-1) {
          my ($x1, $y1) = ($x+$dxp->[$i-1], $y+$h-($dyp->[$i-1]-$min)*$hmul);
          my ($x2, $y2) = ($x+$dxp->[$i],   $y+$h-($dyp->[$i]  -$min)*$hmul);
          next if(int($x2) == $lx && int($y1) == $ly);
          $lx = int($x2); $ly = int($y2);
          if($conf{lType}[$idx] eq "steps") {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x2,$y1, $x2,$y2);
          } else {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x1,$y2, $x2,$y2);
          }
        }
      }
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);

      SVG_pO "<polyline $attributes points=\"$ret\"/>";

    } elsif($conf{lType}[$idx] eq "histeps" ) {
      $ret .=  sprintf(" %d,%d", $x+$dxp->[0], $y+$h) if($isFill && @{$dxp});
      if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
      } else {
        foreach my $i (1..int(@{$dxp})-1) {
          my ($x1, $y1) = ($x+$dxp->[$i-1], $y+$h-($dyp->[$i-1]-$min)*$hmul);
          my ($x2, $y2) = ($x+$dxp->[$i],   $y+$h-($dyp->[$i]  -$min)*$hmul);
          next if(int($x2) == $lx && int($y1) == $ly);
          $lx = int($x2); $ly = int($y2);
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
             $x1,$y1, ($x1+$x2)/2,$y1, ($x1+$x2)/2,$y2, $x2,$y2);
        }
      }
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);
      SVG_pO "<polyline $attributes points=\"$ret\"/>";

    } elsif( $conf{lType}[$idx] eq "bars" ) {
       if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
       } else {
          $barwidth = $barwidth*$tmul;
          # bars are all of equal width (see far above !), 
          # position rounded to integer multiples of bar width
          foreach my $i (0..int(@{$dxp})-1) {
            my ($x1, $y1) = ( $x +4 + $dxp->[$i] - $barwidth,
                               $y +$h-($dyp->[$i]-$min)*$hmul);
            my ($x2, $y2) = ($barwidth, ($dyp->[$i]-$min)*$hmul);    
            SVG_pO "<rect $attributes x=\"$x1\" y=\"$y1\" width=\"$x2\" height=\"$y2\"/>";
         }
       }

    } else {                            # lines and everything else
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $ret .=  sprintf(" %d,%d", $x1, $y+$h) if($i == 0 && $isFill);
        $lx = $x1; $ly = $y1;
        $ret .=  sprintf(" %d,%d", $x1, $y1);
      }
      #-- insert last point for filled line
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);

      SVG_pO "<polyline $attributes points=\"$ret\"/>";
    }

  }
  SVG_pO "</svg>";
  return $SVG_RET;
}

sub
SVG_time_to_sec($)
{
  my ($str) = @_;
  if(!$str) {
    return 0;
  }
  my ($y,$m,$d,$h,$mi,$s) = split("[-_:]", $str);
  $s = 0 if(!$s);
  $mi= 0 if(!$mi);
  $h = 0 if(!$h);
  $d = 1 if(!$d);
  $m = 1 if(!$m);

  if(!$SVG_ltstr || $SVG_ltstr ne "$y-$m-$d-$h") { # 2.5x faster
    $SVG_lt = mktime(0,0,$h,$d,$m-1,$y-1900,0,0,-1);
    $SVG_ltstr = "$y-$m-$d-$h";
  }
  return $s+$mi*60+$SVG_lt;
}

sub
SVG_fmtTime($$)
{
  my ($sepfmt, $sec) = @_;
  my @tarr = split("[ :]+", localtime($sec));
  my ($sep, $fmt) = split(" ", $sepfmt, 2);
  my $ret = "";
  for my $f (split(" ", $fmt)) {
    $ret .= $sep if($ret);
    $ret .= $tarr[$f];
  }
  return $ret;
}

sub
SVG_time_align($$)
{
  my ($v,$align) = @_;
  return $v if(!$align);
  if($align == 1) {             # Look for the beginning of the week
    for(;;) {
      my @a = localtime($v);
      return $v if($a[6] == 0);
      $v += 86400;
    }
  }
  if($align == 2) {             # Look for the beginning of the month
    for(;;) {
      my @a = localtime($v);
      return $v if($a[3] == 1);
      $v += 86400;
    }
  }
}

sub
SVG_doround($$$)
{
  my ($v, $step, $isup) = @_;
  $step = 1 if(!$step); # Avoid division by zero

  my $d = $v/$step;
  my $dr = int($d);
  return $v if($d == $dr);

  if($v >= 0) {
    return int($v/$step)*$step+($isup ? $step : 0);
  } else {
    return int($v/$step)*$step+($isup ? 0 : -$step);
  }
}

##################
# print (append) to output
sub
SVG_pO($)
{
  my $arg = shift;
  return if(!defined($arg));
  $SVG_RET .= $arg;
  $SVG_RET .= "\n";
}

##################

# this is a helper function which creates a PNG image from a given plot
sub
plotAsPng(@)
{
  my (@plotName) = @_;
  my (@webs, $mimetype, $svgdata, $rsvg, $pngImg);
  
  @webs=devspec2array("TYPE=FHEMWEB");
  foreach(@webs) {
    if(!InternalVal($_,'TEMPORARY',undef)) {
      $FW_wname=InternalVal($_,'NAME','');
      last;
    }
  }
  #Debug "FW_wname= $FW_wname, plotName= $plotName[0]";

  $FW_RET                 = undef;
  $FW_webArgs{dev}        = $plotName[0];
  $FW_webArgs{logdev}     = InternalVal($plotName[0], "LOGDEVICE", "");
  $FW_webArgs{gplotfile}  = InternalVal($plotName[0], "GPLOTFILE", "");
  $FW_webArgs{logfile}    = InternalVal($plotName[0], "LOGFILE", "CURRENT"); 
  $FW_pos{zoom}           = $plotName[1] if $plotName[1];
  $FW_pos{off}            = $plotName[2] if $plotName[2];

  ($mimetype, $svgdata)   = SVG_showLog("unused");
  
  #Debug "MIME type= $mimetype";
  #Debug "SVG= $svgdata";

  my ($w, $h) = split(",", AttrVal($plotName[0],"plotsize","800,160"));
  $svgdata =~ s/<\/svg>/<polyline opacity="0" points="0,0 $w,$h"\/><\/svg>/;

  eval {
    require Image::LibRSVG;
    $rsvg = new Image::LibRSVG();
    $rsvg->loadImageFromString($svgdata);
    $pngImg = $rsvg->getImageBitmap();
  };
  Log3 $FW_wname, 1, 
    "plotAsPng(): Cannot create plot as png image for \"" . 
    join(" ", @plotName) . "\": $@" 
    if($@ or !defined($pngImg) or ($pngImg eq ""));

  return $pngImg if $pngImg;
  return;
}

##################

1;

##################

=pod
=begin html

<a name="SVG"></a>
<h3>SVG</h3>
<ul>
  <a name="SVGlinkdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SVG
        &lt;logDevice&gt;:&lt;gplotfile&gt;:&lt;logfile&gt;</code>
    <br><br>
    This is the Plotting/Charting device of FHEMWEB
    Examples:
    <ul>
      <code>define MyPlot SVG inlog:temp4hum4:CURRENT</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>Normally you won't define an SVG device manually, as
          FHEMWEB makes it easy for you, just plot a logfile (see <a
          href="#logtype">logtype</a>) and click on "Create SVG instance".
          Specifying CURRENT as a logfilename will always access the current
          logfile, even if its name changes regularly.</li>
      <li>For historic reasons this module uses a Gnuplot file description
          to store different attributes. Some special commands (beginning with
          #FileLog  or #DbLog) are used additionally, and not all gnuplot
          attribtues are implemented.</li>
    </ul>
  </ul>

  <a name="SVGset"></a>
  <b>Set</b>
  <ul>
    <li>copyGplotFile<br>
      Copy the currently specified gplot file to a new file, which is named
      after the SVG device, existing files will be overwritten.
      This operation is needed in order to use the plot editor (see below)
      without affecting other SVG instances using the same gplot file.
      Creating the SVG instance from the FileLog detail menu will also
      create a unique gplot file, in this case this operation is not needed.
    </li>
  </ul><br>

  <a name="SVGget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SVGattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="fixedrange"></a>
    <li>fixedrange [offset]<br>
        Contains two time specs in the form YYYY-MM-DD separated by a space.
        In plotmode gnuplot-scroll or SVG the given time-range will be used,
        and no scrolling for this SVG will be possible. Needed e.g. for
        looking at last-years data without scrolling.<br><br>
        If the value is one of hour, day, &lt;N&gt;days, week, month, year than
        set the zoom level for this SVG independently of the user specified
        zoom-level. This is useful for pages with multiple plots: one of the
        plots is best viewed in with the default (day) zoom, the other one with
        a week zoom.<br>

        If given, the optional integer parameter offset refers to a different
        period (e.g. last year: fixedrange year -1, 2 days ago: fixedrange day
        -2).

        </li><br>

    <a name="fixedoffset"></a>
    <li>fixedoffset &lt;nDays&gt;<br>
        Set an fixed offset (in days) for the plot.
        </li><br>

    <a name="startDate"></a>
    <li>startDate<br>
        Set the start date for the plot. Used for demo installations.
        </li><br>

    <li><a href="#plotsize">plotsize</a></li><br>

    <li><a href="#plotmode">plotmode</a></li><br>

    <a name="label"></a>
    <li>label<br>
      Double-Colon separated list of values. The values will be used to replace
      &lt;L#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;L1&gt;, &lt;L2&gt;, etc.). Each value will be evaluated as a perl
      expression, so you have access e.g. to the Value functions.<br><br>

      If the plotmode is gnuplot-scroll or SVG, you can also use the min, max,
      avg, cnt, sum, currval (last value) and currdate (last date) values of
      the individual curves, by accessing the corresponding values from the
      data hash, see the example below:<br>

      <ul>
        <li>Fixed text for the right and left axis:<br>
          <ul>
            <li>Fhem config:<br>
                attr wl_1 label "Temperature"::"Humidity"</li>
            <li>.gplot file entry:<br>
                set ylabel &lt;L1&gt;<br>
                set y2label &lt;L2&gt;</li>
          </ul></li>
        <li>Title with maximum and current values of the 1st curve (FileLog)
          <ul>
            <li>Fhem config:<br>
                attr wl_1 label "Max $data{max1}, Current $data{currval1}"</li>
            <li>.gplot file entry:<br>
                set title &lt;L1&gt;<br></li>
          </ul></li>
      </ul>
      </li>

    <a name="title"></a>
    <li>title<br>
      A special form of label (see above), which replaces the string &lt;TL&gt;
      in the .gplot file. It defaults to the filename of the logfile.
    </li>

    <a name="plotfunction"></a>
    <li>plotfunction<br>
      Space value separated list of values. The value will be used to replace
      &lt;SPEC#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;SPEC1&gt;, &lt;SPEC2&gt;, etc.) in the #FileLog or #DbLog directive.
      With this attribute you can use the same .gplot file for multiple devices
      with the same logdevice.
      <ul><b>Example:</b><br>
        <li>#FileLog <SPEC1><br>
            with: attr <SVGdevice> plotfunction "4:IR\x3a:0:"<br>
            instead of<br>  
            #FileLog 4:IR\x3a:0:
        </li>
        <li>#DbLog <SPEC1><br>
            with: attr <SVGdevice> plotfunction
            "Garage_Raumtemp:temperature::"<br> instead of<br>
            #DbLog Garage_Raumtemp:temperature::
        </li>
      </ul>
    </li>
  </ul>
  <br>

  <a name="plotEditor"></a>
  <b>Plot-Editor</b>
  <br>
    This editor is visible on the detail screen of the SVG instance.
    Most features are obvious here, up to some exceptions:
  <ul>
    <li>if you want to omit the title for a Diagram label, enter notitle in the
      input field.</li>
    <li>if you want to specify a fixed value (not taken from a column) if a
      string found (e.g. 1 if the FS20 switch is on and 0 if it is off), then
      you have to specify the Tics first, and write the .gplot file, before you
      can select this value from the dropdown.<br>
      Example:
      <ul>
      Enter in the Tics field: ("On" 1, "Off" 0)<br>
      Write .gplot file<br>
      Select "1" from the column dropdown (note the double quote!) for the
      regexp switch.on, and "0" for the regexp switch.off.<br>
      Write .gplot file again<br>
      </ul></li>
  </ul>
  The visibility of the ploteditor can be configured with the FHEMWEB attribute
  <a href="#ploteditor">ploteditor</a>.
  <br>
</ul>

=end html

=begin html_DE

<a name="SVG"></a>
<h3>SVG</h3>
<ul>
  <a name="SVGlinkdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SVG &lt;logDevice&gt;:&lt;gplotfile&gt;:&lt;logfile&gt;</code>
    <br><br>
    Dies ist das Zeichenmodul von FHEMWEB, mit dem Vektorgrafiken (SVG) erzeugt
    werden. <br><br>
    Beispiel:
    <ul>
      <code>define MyPlot SVG inlog:temp4hum4:CURRENT</code><br>
    </ul>
    <br>

    Hinweise:
    <ul>
      <li>Normalerweise m&uuml;ssen SVG-Ger&auml;te nicht manuell erzeugt
        werden, da FHEMWEB es f&uuml;r den Nutzer einfach macht: man muss in
        der Detailansicht eines FileLogs wechseln und auf "Create SVG instance"
        klicken.</li>

      <li>CURRENT als &lt;logfile&gt; wird immer das aktuelle Logfile
        benutzen, selbst dann, wenn der Name des Logfiles sich
        regelm&auml;&szlig;ig &auml;ndert.  </li>

      <li>Aus historischen Gr&uuml;nden ben&ouml;tigt jede SVG-Instanz eine
        sog. .gplot Datei, die auch als Input f&uuml;r das gnuplot Programm
        verwendet werden kann.  Einige besondere Zeilen (welche mit #FileLog
        oder #DbLog beginnen) werden zus&auml;tzlich benutzt, diese werden von
        gnuplot als Kommentar betrachtet. Auf der anderen Seite implementiert
        dieses Modul nicht alle gnuplot-Attribute.</li>

    </ul>
  </ul>
  <br>

  <a name="SVGset"></a>
  <b>Set</b>
  <ul>
    <li>copyGplotFile<br>
      Kopiert die aktuell ausgew&auml;hlte .gplot Datei in eine neue Datei, die
      den Namen der SVG Instanz tr&auml;gt; bereits bestehende Dateien mit
      gleichem Namen werden &uuml;berschrieben. Diese Vorgehensweise ist
      notwendig, wenn man den Ploteditor benutzt. Erzeugt man aus der
      Detailansicht des FileLogs die SVG Instanz, wird eine eindeutige
      .gplot-Datei erzeugt. In diesem Fall ist dieses Befehl nicht
      erforderlich.</li>

  </ul><br>

  <a name="SVGget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SVGattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="fixedrange"></a>
    <li>fixedrange [offset]<br>
      Version 1<br>
      Enth&auml;lt zwei Zeit-Spezifikationen in der Schreibweise YYYY-MM-DD,
      getrennt durch ein Leerzeichen. Im Plotmodus gnuplot-Scroll oder SVG wird
      das vorgegebene Intervall verwendet und ein Scrolling der Zeitachse ist
      nicht m&ouml;glich. Dies wird z.B. verwendet, um sich die Daten des
      vergangenen Jahres ohne Scrollen anzusehen.<br><br>   

      Version 2<br>
      Wenn der Wert entweder Tag, &lt;N&gt;Tage, Woche, Monat oder Jahr lautet,
      kann der Zoom-Level f&uuml;r dieses SVG unabh&auml;ngig vom
      User-spezifischen Zoom eingestellt werden. Diese Einstellung ist
      n&uuml;tzlich f&uuml;r mehrere Plots auf einer Seite: Eine Grafik ist mit
      dem Standard-Zoom am aussagekr&auml;ftigsten, die anderen mit einem Zoom
      &uuml;ber eine Woche.
      Der optionale ganzzahlige Parameter [offset] setzt ein anderes
      Zeitintervall (z.B. letztes Jahr: <code> fixedrange year -1</code>,
      vorgestern: <code> fixedrange day -2</code>).
      </li><br>

    <a name="fixedoffset"></a>
    <li>fixedoffset &lt;nTage&gt;<br>
      Verschiebt den Plot-Offset um einen festen Wert (in Tagen). 
      </li><br>

    <a name="startDate"></a>
    <li>startDate<br>
      Setzt das Startdatum f&uuml;r den Plot. Wird f&uuml;r Demo-Installationen
      verwendet.
      </li><br>

    <li><a href="#plotsize">plotsize</a></li><br>

    <li><a href="#plotmode">plotmode</a></li><br>

    <a name="label"></a>
    <li>label<br>
      Eine Liste, bei der die einzelnen Werte mit einem zweifachen Doppelpunkt
      voneinander getrennt werden. Diese Liste wird verwendet um die &lt;L#&gt;
      Zeichenfolgen in der .gplot-Datei zu ersetzen. Dabei steht das # f&uuml;r
      eine laufende Ziffer beginnend mit 1 (&lt;L1&gt;, &lt;L2&gt;, usw.).
      Jeder Wert wird als Perl-Ausdruck bewertet, deshalb hat man Zugriff z.B.
      auf die hinterlegten Funktionen. <br><br>

      Egal, ob es sich bei der Plotart um gnuplot-scroll oder SVG handelt, es
      k&ouml;nnen ebenfalls die Werte der individuellen Kurve f&uuml;r min,
      max, avg, cnt, sum, currval (letzter Wert) und currdate (letztes Datum)
      durch Zugriff der entsprechenden Werte &uuml;ber das DataHash verwendet
      werden. Siehe untenstehendes Beispiel:<br>
      <ul>
        <li>Beschriftunng der rechten und linken y-Achse:<br>
          <ul>
            <li>Fhem config:<br>
                <code>attr wl_1 label "Temperature"::"Humidity"</code></li>
            <li>Eintrag in der .gplot-Datei:<br>
                <code>set ylabel &lt;L1&gt;<br>
                set y2label &lt;L2&gt;</code></li>
          </ul>
          </li>
        <li>&Uuml;berschrift aus Maximum und dem letzten Wert der ersten
          Kurve(FileLog)
          <ul>
            <li>Fhem config:<br>
                <code>attr wl_1 label "Max $data{max1}, Current
                        $data{currval1}"</code></li>
            <li>Eintrag in der .gplot-Datei:<br>
                <code>set title &lt;L1&gt;</code><br></li>
          </ul>
          </li>
      </ul>
      </li>

    <a name="title"></a>
    <li>title<br>
      Eine besondere Form der &Uuml;berschrift (siehe oben), bei der die
      Zeichenfolge &lt;TL&gt; in der .gplot-Datei ersetzt wird.
      Standardm&auml;&szlig;ig wird als &lt;TL&gt; der Dateiname des Logfiles
      eingesetzt.
      </li><br>

    <a name="plotfunction"></a>
    <li>plotfunction<br>
      Eine Liste, deren Werte durch Leerzeichen voneinander getrennt sind.
      Diese Liste wird verwendet um die &lt;SPEC#&gt; Zeichenfolgen in der
      .gplot-Datei zu ersetzen. Dabei steht das # f&uuml;r eine laufende Ziffer
      beginnend mit 1 (&lt;SPEC1&gt;, &lt;SPEC2&gt;, usw.) in der #FileLog oder
      #DBLog Anweisung. Mit diesem Attrbute ist es m&ouml;glich eine
      .gplot-Datei f&uuml;r mehrere Ger&auml;te mit einem einzigen logdevice zu
      verwenden. <br><br>

      <ul><b>Beispiel:</b><br>
        <li>#FileLog &lt;SPEC1&gt;<br>
          mit:<br>
            <code>attr &lt;SVGdevice&gt; plotfunction "4:IR\x3a:0:"</code><br>
          anstelle von:<br>  
            <code>#FileLog 4:IR\x3a:0:</code>
          </li>
        <li>#DbLog &lt;SPEC1&gt;<br>
          mit:<br> 
            <code>attr &lt;SVGdevice&gt; plotfunction
                    "Garage_Raumtemp:temperature::"</code><br>
          anstelle von:<br>
            <code>#DbLog Garage_Raumtemp:temperature::</code>
          </li>
      </ul>
      </li>
  </ul>
  <br>

  <a name="plotEditor"></a>
  <b>Plot-Editor</b>
   <br>
    Dieser Editor ist in der Detailansicht der SVG-Instanz zu sehen. Die
    meisten Features sind hier einleuchtend und bekannt, es gibt aber auch
    einige Ausnahmen:
  <ul>
    <li>wenn f&uuml;r ein Diagramm die &Uuml;berschrift unterdr&uuml;ckt werden
      soll, muss im Eingabefeld <code>notitle</code> eingetragen werden.
      </li>

    <li>wenn ein fester Wert (nicht aus einer Wertespalte) definiert werden
      soll, f&uuml;r den Fall, das eine Zeichenfoge gefunden wurde (z.B. 1
      f&uuml;r eine FS20 Schalter, der AN ist und 0 f&uuml;r den AUS-Zustand),
      muss zuerst das Tics-Feld gef&uuml;llt, und die .gplot-Datei
      gespeichert werden, bevor der Wert &uuml;ber die Dropdownliste erreichbar
      ist.
      <ul><b>Beispiel:</b><br>
        Eingabe im Tics-Feld: ("On" 1, "Off" 0)<br>
        .gplot-Datei speichern<br>
        "1" als Regexp switch.on und "0" f&uuml;r den Regexp switch.off vom
        Spalten-Dropdown ausw&auml;hlen (auf die G&auml;nsef&uuml;&szlig;chen
        achten!).<br>
        .gplot-Datei erneut speichern<br>
      </ul>
      </li>
  </ul>
  Die sichtbarkeit des  Plot-Editors kann mit dem FHEMWEB Attribut <a
  href="#ploteditor">ploteditor</a> konfiguriert werden.
  <br>
</ul>

=end html_DE

=cut
