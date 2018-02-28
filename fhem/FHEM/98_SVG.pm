##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
use HttpUtils;
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
use vars qw($FW_userAgent);
use vars qw($FW_hiddenroom);
use vars qw($FW_CSRF);

my $SVG_RET;        # Returned data (SVG)
sub SVG_calcOffsets($$);
sub SVG_doround($$$);
sub SVG_fmtTime($$);
sub SVG_pO($);
sub SVG_readgplotfile($$$);
sub SVG_render($$$$$$$$$$);
sub SVG_showLog($);
sub SVG_substcfg($$$$$$);
sub SVG_time_align($$);
sub SVG_time_to_sec($);
sub SVG_openFile($$$);
sub SVG_doShowLog($$$$;$);
sub SVG_getData($$$$$);
sub SVG_sel($$$;$$);
sub SVG_getControlPoints($);
sub SVG_calcControlPoints($$$$$$);

my %SVG_devs;       # hash of from/to entries per device


#####################################
sub
SVG_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "SVG_Define";
  no warnings 'qw';
  my @attrList = qw(
    captionLeft:1,0"
    captionPos:right,left,auto
    endPlotNow
    endPlotToday
    fixedoffset
    fixedrange
    label
    nrAxis
    plotWeekStartDay:0,1,2,3,4,5,6
    plotfunction
    plotmode
    plotsize
    plotReplace:textField-long
    startDate
    title
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
  $hash->{SetFn}    = "SVG_Set";
  $hash->{AttrFn}   = "SVG_AttrFn";
  $hash->{RenameFn} = "SVG_Rename";
  $hash->{FW_summaryFn} = "SVG_FwFn";
  $hash->{FW_detailFn}  = "SVG_FwFn";
  $hash->{FW_atPageEnd} = 1;
  $data{FWEXT}{"/SVG_WriteGplot"}{CONTENTFUNC} = "SVG_WriteGplot";
  $data{FWEXT}{"/SVG_showLog"}{FUNC} = "SVG_showLog";
  $data{FWEXT}{"/SVG_showLog"}{FORKABLE} = 1;
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
  notifyRegexpChanged($hash, "global");

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
  my ($og,$od) = ($hash->{GPLOTFILE}, $hash->{DEF});
  $hash->{GPLOTFILE} = $hash->{NAME};
  my $dstName = "$FW_gplotdir/$hash->{GPLOTFILE}.gplot";
  return "this is already a unique gplot file" if($srcName eq $dstName);
  $hash->{DEF} = $hash->{LOGDEVICE} . ":".
                 $hash->{GPLOTFILE} . ":".
                 $hash->{LOGFILE};

  my ($err,@rows) = FileRead($srcName);
  return $err if($err);
  $err = FileWrite($dstName, @rows);

  if($err) {
    $hash->{DEF} = $od; $hash->{GPLOTFILE} = $og;
  } else {
    addStructChange("modify", $me, "$me $hash->{DEF}")
  }
  return $err;
}

sub
SVG_AttrFn(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;

  if($aName eq "captionLeft" && $cmd eq "set") {
    my $dir = (!defined($aVal) || $aVal) ? "left" : "right";
    AnalyzeCommand(undef, "attr $name captionPos $dir");
    return "attr $name captionLeft converted to attr $name captionPos $dir";
  }
  return undef;
}

sub
SVG_Attr($$$$)
{
  my ($parent, $dev, $attr, $default) = @_;
  my $val = AttrVal($dev, $attr, undef);
  return $val if(defined($val));
  return AttrVal($parent, $attr, $default);
}

sub
SVG_Rename($$)
{
  my ($new, $old) = @_;
  my $hash = $defs{$new};
  return if($hash->{GPLOTFILE} ne $old);
  SVG_Set($hash, $new, "copyGplotFile");   # Forum #59786
}



sub
jsSVG_getAttrs($;$)
{
  my ($d , $flt) = @_;
  return join("&#01;", map { #00 arrives as 65533 in JS
     my $v=$attr{$d}{$_};
     $v =~ s/'/&#39;/g;
    "$_=$v";
  } grep { $flt ? $flt->{$_} : 1 } keys %{$attr{$d}});
}

sub
SVG_getplotsize($)
{
  my ($d) = @_;
  return $FW_webArgs{plotsize} ? 
                $FW_webArgs{plotsize} : AttrVal($d,"plotsize",$FW_plotsize);
}

sub
SVG_isEmbed($)
{
  return (AttrVal($FW_wname, "plotEmbed", 1));
                        # $FW_userAgent !~ m/(iPhone|iPad|iPod).*OS (8|9)/));
}

sub
SVG_log10($)
{
  my ($n) = @_;

  return 0.0000000001 if( $n <= 0 );

  return log(1+$n)/log(10);
}


##################
sub
SVG_FwFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ret = "";

  if(!$pageHash || !$pageHash->{jsLoaded}) {
    $ret .= "<script type='text/javascript' src='$FW_ME/pgm2/svg.js'></script>";
    $pageHash->{jsLoaded} = 1 if($pageHash);
  }

  # plots navigation buttons
  my $pm = AttrVal($d,"plotmode",$FW_plotmode);
  if((!$pageHash || !$pageHash->{buttons}) &&
     AttrVal($d, "fixedrange", "x") !~ m/^[ 0-9:-]*$/) {

    $ret .= '<div class="SVGlabel" data-name="svgZoomControl">';
    $ret .= SVG_zoomLink("zoom=-1", "Zoom-in", "zoom in");
    $ret .= SVG_zoomLink("zoom=1",  "Zoom-out","zoom out");
    $ret .= SVG_zoomLink("off=-1",  "Prev",    "prev");
    $ret .= SVG_zoomLink("off=1",   "Next",    "next");
    $ret .= '</div>';
    $pageHash->{buttons} = 1 if($pageHash);
    $ret .= "<br>";
  }


  if($pm eq "jsSVG") {
    my @d=split(":",$defs{$d}{DEF});
    my ($err, @svgplotfile) = FileRead("$FW_gplotdir/$d[1].gplot");
       ($err, @svgplotfile) = FileRead("$FW_gplotdir/template.gplot") if($err);
    my $gplot = join("&#01;", @svgplotfile);
    $gplot =~ s/'/&#39;/g;
    my %webattrflt = ( endPlotNow=>1, endPlotToday=>1, plotmode=>1,
                       plotsize=>1,   nrAxis=>1,       stylesheetPrefix=>1 );
    if(!$pageHash || !$pageHash->{jssvgLoaded}) {
      $ret .=
          "<script type='text/javascript' src='$FW_ME/pgm2/jsSVG.js'></script>";
      $pageHash->{jssvgLoaded} = 1 if($pageHash);
    }

    SVG_calcOffsets($d[0], $d);
    $ret .= "<div id='jsSVG_$d' class='jsSVG' ".
                "data-webAttr='".jsSVG_getAttrs($FW_wname, \%webattrflt)."' ".
                "data-svgAttr='".jsSVG_getAttrs($d)."' ".
                "data-svgName='".$d."' ".
                "data-from='".$SVG_devs{$d[0]}{from}."' ".
                "data-to='"  .$SVG_devs{$d[0]}{to}  ."' ".
                "data-gplotFile='$gplot' source='$d[0]'>".
            "</div>";
    $ret .= (SVG_PEdit($FW_wname,$d,$room,$pageHash) . "<br>")
      if(!$pageHash);
    return $ret;
  }

  my $arg="$FW_ME/SVG_showLog?dev=$d".
                "&logdev=$hash->{LOGDEVICE}".
                "&gplotfile=$hash->{GPLOTFILE}".
                "&logfile=$hash->{LOGFILE}".
                "&pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);

  if($pm eq "SVG") {
    $ret .= "<div class=\"SVGplot SVG_$d\">";

    if(SVG_isEmbed($FW_wname)) {
      my ($w, $h) = split(",", SVG_getplotsize($d));
      $ret .= "<embed src=\"$arg\" type=\"image/svg+xml\" " .
            "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

    } else {
      my $oret=$FW_RET; $FW_RET="";
      my ($type, $data) = SVG_doShowLog($d, $hash->{LOGDEVICE},
                $hash->{GPLOTFILE}, $hash->{LOGFILE}, 1);
      $FW_RET=$oret;
      $ret .= $data;

    }
    $ret .= "</div>";

  } elsif($pm eq "gnuplot-scroll") {
    $ret .= "<img src=\"$arg\"/>";
  } elsif($pm eq "gnuplot-scroll-svg") {
    $ret .= "<object type=\"image/svg+xml\" ".
                "data=\"$arg\">Your browser does not support SVG.</object>";
  }


  if(!$pageHash) {
    if($FW_plotmode eq "SVG") {
      $ret .= SVG_PEdit($FW_wname,$d,$room,$pageHash) . "<br>";
    }

  } else {
    if(!AttrVal($d, "group", "") && !$FW_subdir) {
      my $alias = AttrVal($d, "alias", $d);
      my $clAdd = "\" data-name=\"$d";
      $clAdd .= "\" style=\"display:none;" if($FW_hiddenroom{detail});
      $ret .= FW_pH("detail=$d", $alias, 0, "SVGlabel SVG_$d $clAdd", 1, 0);
      $ret .= "<br>";
    }
  }

  return $ret;
}

sub
SVG_cb($$$)
{
  my ($v,$t,$c) = @_;
  $c = ($c ? " checked" : "");
  return "$t&nbsp;<input type=\"checkbox\" name=\"$v\" value=\"$v\"$c>";
}

sub
SVG_txt($$$$)
{
  my ($v,$t,$c,$sz) = @_;
  $c = "" if(!defined($c));
  $c =~ s/&/\&amp;/g;
  $c =~ s/"/\&quot;/g;
  return "$t&nbsp;<input type=\"text\" name=\"$v\" size=\"$sz\" ".
                "value=\"$c\"/>";
}

sub
SVG_sel($$$;$$)
{
  my ($v,$l,$c,$fnData,$class) = @_;
  my @al = split(",",$l);
  $c =~ s/\\x3a/:/g if($c);
  return FW_select(undef,$v,\@al,$c, $class?$class:"set", $fnData);
}

############################
# gnuplot file "editor"
sub
SVG_PEdit($$$$)
{
  my ($FW_wname,$d,$room,$pageHash) = @_;

  my $pe = AttrVal($FW_wname, "ploteditor", "always");

  return "" if( $pe eq 'never' );

  my $gpf = $defs{$d}{GPLOTFILE};
  my $gpfEsc = $gpf;
  $gpfEsc =~ s,\.,\\\\.,g;
  my $link = "$FW_ME?cmd=style edit $gpf.gplot".
               (configDBUsed() ? " configDB" : "").$FW_CSRF;
  my $gp = "$FW_gplotdir/$gpf.gplot";
  my $pm = AttrVal($d,"plotmode",$FW_plotmode);

  my ($err, $cfg, $plot, $srcDesc) = SVG_readgplotfile($d, $gp, $pm);
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
  $ret .= FW_hidden("detail", $d); # go to detail after save
  if(defined($FW_pos{zoom}) && defined($FW_pos{off})) { # for showData
    $ret .= FW_hidden("pos", "zoom=$FW_pos{zoom};off=$FW_pos{off}");
  }
  $ret .= "<div class='makeTable wide'><span>Plot Editor</span>";
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
  $ret .= "<td>".SVG_cb("gridy", "left", $conf{hasygrid})."</td>";
  $ret .= "<td>".SVG_cb("gridy2","right",$conf{hasy2grid})."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"odd\">";
  $ret .= "<td>Range as [min:max]</td>";
  $ret .= "<td>".SVG_txt("yrange", "left", $conf{yrange}, 16);
  $ret .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;".
                SVG_cb("yscale", "log", $conf{yscale})."</td>";
  $ret .= "<td>".SVG_txt("y2range", "right", $conf{y2range}, 16);
  $ret .= "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;".
                SVG_cb("y2scale", "log", $conf{y2scale})."</td>";
  $ret .= "</tr>";
  if( $conf{xrange} ) {
    $ret .= "<tr class=\"odd\"><td/><td>";
    $ret .= SVG_txt("xrange", "x&nbsp;&nbsp;&nbsp;",$conf{xrange},16)."</td>";
    $ret .= "<td/></tr>";
  }
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Tics as (\"Txt\" val, ...)</td>";
  $ret .= "<td>".SVG_txt("ytics", "left", $conf{ytics}, 16)."</td>";
  $ret .= "<td>".SVG_txt("y2tics","right", $conf{y2tics}, 16)."</td>";
  $ret .= "</tr>";
  if( $conf{xtics} ) {
    $ret .= "<tr class=\"even\"><td/><td>";
    $ret .= SVG_txt("xtics", "x&nbsp;&nbsp;&nbsp;", $conf{xtics}, 16)."</td>";
    $ret .= "<td/></tr>";
  }

  my ($desc, $cnt) = ("Spec", 0);
  my (@srcHtml, @paramHtml, @exampleHtml, @revIdx);
  my @srcNames = grep { $modules{$defs{$_}{TYPE}}{SVG_sampleDataFn} }
                 sort keys %defs;

  foreach my $src (@{$srcDesc->{order}}) {
    my $lmax = $srcDesc->{src}{$src}{idx}+1;
    my $fn = $modules{$defs{$src}{TYPE}}{SVG_sampleDataFn};
    my @argArr = split(" ", $srcDesc->{src}{$src}{arg});
    if($fn) {
      no strict "refs";
      my ($ldesc, $paramHtml, $example) = 
                                &{$fn}($src, \@argArr, $lmax,\%conf, $FW_wname);
      use strict "refs";
      $desc = $ldesc;
      push @paramHtml, @{$paramHtml} if($paramHtml);
      map { push @exampleHtml, $example } (0..$lmax-1);

    } else {
      push @paramHtml, map { SVG_txt("par_${_}_0","",$_,20) } @argArr;
      map { push @exampleHtml, "" } (0..$lmax-1);
    }

    push @srcHtml,
        map { FW_select(undef,"src_$_",\@srcNames,$src,"svgSrc");} (0..$lmax-1);
    map { push @revIdx,$srcDesc->{rev}{$cnt}{$_}; } (0..$lmax-1);
    $cnt++;
  }
  # Last, empty line
  push @revIdx,int(@revIdx);
  push @srcHtml, FW_select(undef,"src_".int(@srcHtml),\@srcNames,"","svgSrc");
  push @paramHtml, (@paramHtml==0 ? 
                      SVG_txt("par_0_0", "", "parameter", 10) : $paramHtml[0]);
  push @exampleHtml, "Set the label and 'Write .gplot file' first in order to ".
                     "get example data and correct parameter choice";

  my @lineStyles;
  if(SVG_openFile($FW_cssdir,
                  AttrVal($FW_wname,"stylesheetPrefix",""), "svg_style.css")) {
    map { push(@lineStyles,$1) if($_ =~ m/^\.SVGplot.(l[^{ ]*)/) } <FH>; # }
    close(FH);
  }

  $ret .= "<tr class=\"odd\"><td>Diagram label, Source</td>";
  $ret .= "<td>$desc</td>";
  $ret .=" <td>Y-Axis,Plot-Type,Style,Width</td></tr>";


  my ($r, $example, @output) = (0, "");
  my $max = int(@srcHtml);
  for($r=0; $r < $max; $r++) {
    my $idx = $revIdx[$r];
    $example .= "<div class='ex ex_$idx' style='display:".($idx?"none":"block").
                        "'>$exampleHtml[$r]</div>";
    my $o = "<tr row='$idx' class=\"".(($r&1)?"odd":"even")."\"><td>";
    $o .= SVG_txt("title_$idx", "", !$conf{lTitle}[$idx]&&$idx<($max-1) ? 
                                      "notitle" : $conf{lTitle}[$idx], 12);
    my $sh = $srcHtml[$r]; $sh =~ s/src_\d+/src_$idx/g;
    $o .= $sh;
    $o .= "</td><td>";
    my $ph = $paramHtml[$r]; $ph =~ s/par_\d+_/par_${idx}_/g;
    $o .= $ph;
    $o .= "</td><td>";
    my $v = $conf{lAxis}[$idx];
    my $sel = ($v && $v eq "x1y1") ? "left" : "right";
    $o .= SVG_sel("axes_${idx}", "left,right,left log,right log", $sel );
    $o .= SVG_sel("type_${idx}",
                "lines,points,steps,fsteps,histeps,bars,ibars,".
                        "cubic,quadratic,quadraticSmooth",
                $conf{lType}[$idx]);
    my $ls = $conf{lStyle}[$idx]; 
    if($ls) {
      $ls =~ s/class=.* //g;
      $ls =~ s/"//g; 
    }
    $o .= SVG_sel("style_$idx", join(",", @lineStyles), $ls);
    my $lw = $conf{lWidth}[$idx]; 
    if($lw) {
      $lw =~ s/.*stroke-width://g;
      $lw =~ s/"//g; 
    }
    $o .= SVG_sel("width_$idx", "0.2,0.5,1,1.5,2,3,4", ($lw ? $lw : 1));
    $o .= "</td></tr>";
    $output[$idx] = $o;
  }
  $ret .= join("", @output);
  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= "Example lines for input:<br>$example</td></tr>";

  my %gpf;
  map { 
    $gpf{$defs{$_}{GPLOTFILE}}{$_} = 1 if($defs{$_}{TYPE} eq "SVG");
  } sort keys %defs;

  if(int(keys %{$gpf{$defs{$d}{GPLOTFILE}}}) > 1) {
    $ret .= "<tr class='".(($r++&1)?"odd":"even")."'><td colspan='3'>".
      "<b>Note:</b>".
      "The .gplot file ($defs{$d}{GPLOTFILE}) is used by multiple SVG ".
      "devices (".join(",", sort keys %{$gpf{$defs{$d}{GPLOTFILE}}})."), ".
      "writing probably will corrupt the other SVGs. ".
      "Remedy: execute set $d copyGplotFile".
    "</td></tr>";
  }

  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= FW_submit("submit", "Write .gplot file")."&nbsp;".
          FW_submit("showFileLogData", "Show preprocessed input").
          "</td></tr>";

  $ret .= "</table></div></form>";

  my $sl = "$FW_ME/SVG_WriteGplot?detail=$d&showFileLogData=1";
  if(defined($FW_pos{zoom}) && defined($FW_pos{off})) {
    $sl .= "&pos=zoom=$FW_pos{zoom};off=$FW_pos{off}";
  }

  $ret .= <<'EOF';
<script type="text/javascript">
  var sel = "table.plotEditor tr[row] ";
  $(sel+"input,"+sel+"select").focus(function(){
    var row = $(this).closest("tr").attr("row");
    $("table.plotEditor div.ex").css("display","none");
    $("table.plotEditor div.ex_"+row).css("display","block");
  });
  $("table.plotEditor input[name=title_0]").focus();
  $("table.plotEditor input[name=showFileLogData]").click(function(e){
    e.preventDefault();
EOF
    $ret .= 
    "FW_cmd('$sl', function(arg){" .<<"EOF";
      FW_okDialog(arg);
    });
  });
  setTimeout(function(){
    \$("table.internals div[informid=$gpfEsc-GPLOTFILE]")
      .html("<a href='$link'>$gpf</a>");
    }, 10);
</script>
EOF
  return $ret;
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
                        ($prf ? $prf : "room=$FW_room")) . "&pos=";
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


# Debugging: show the data received from GET
sub
SVG_showData()
{
  my $wl = $FW_webArgs{detail};
  my $hash = $defs{$wl};
  my ($d, $gplotfile, $file) = split(":", $hash->{DEF});
  $gplotfile = "$FW_gplotdir/$gplotfile.gplot";
  my $pm = AttrVal($d,"plotmode",$FW_plotmode);
  my ($err, $cfg, $plot, $srcDesc) = SVG_readgplotfile($wl, $gplotfile, $pm);
  if($err) {
    $FW_RET=$err;
    return 1;
  }
  SVG_calcOffsets($d, $wl);
  $FW_RET = SVG_getData($wl,$SVG_devs{$d}{from}, $SVG_devs{$d}{to}, $srcDesc,1);
  $FW_RET =~ s/\n/<br>/gs;
  return 1;
}

sub
SVG_WriteGplot($)
{
  my ($arg) = @_;
  FW_digestCgi($arg);

  return if($FW_hiddenroom{detail});
  return SVG_showData() if($FW_webArgs{showFileLogData});

  if(!defined($FW_webArgs{par_0_0})) {
    $FW_RET .=
      '<div id="errmsg">'.
        "missing data in logfile: won't write incomplete .gplot definition".
      '</div>';
    return 0;
  }

  my $maxLines = 0;
  foreach my $i (keys %FW_webArgs) {
    next if($i !~ m/^title_(.*)$/);
    $maxLines = $1 if($1 > $maxLines);
  }

  my @rows;
  push @rows, "# Created by FHEM/98_SVG.pm, ".TimeNow();
  push @rows, "set terminal png transparent size <SIZE> crop";
  push @rows, "set output '<OUT>.png'";
  push @rows, "set xdata time";
  push @rows, "set timefmt \"%Y-%m-%d_%H:%M:%S\"";
  push @rows, "set xlabel \" \"";
  push @rows, "set title '$FW_webArgs{title}'";
  push @rows, "set xtics ".$FW_webArgs{xtics} if($FW_webArgs{xtics});
  push @rows, "set ytics ".$FW_webArgs{ytics};
  push @rows, "set y2tics ".$FW_webArgs{y2tics};
  push @rows, "set grid".($FW_webArgs{gridy}  ? " ytics" :"").
                      ($FW_webArgs{gridy2} ? " y2tics":"")."";
  push @rows, "set ylabel \"$FW_webArgs{ylabel}\"";
  push @rows, "set y2label \"$FW_webArgs{y2label}\"";
  push @rows, "set xrange $FW_webArgs{xrange}" if($FW_webArgs{xrange});
  push @rows, "set yrange $FW_webArgs{yrange}" if($FW_webArgs{yrange});
  push @rows, "set y2range $FW_webArgs{y2range}" if($FW_webArgs{y2range});
  push @rows, "set yscale log" if($FW_webArgs{yscale});
  push @rows, "set y2scale log" if($FW_webArgs{y2scale});
  push @rows, "";

  my @plot;
  for(my $i=0; $i <= $maxLines; $i++) {
    next if(!$FW_webArgs{"title_$i"});
    my $prf = "par_${i}_";
    my @v = map {$FW_webArgs{"$prf$_"}}
            grep {defined($FW_webArgs{"$prf$_"})} (0..9);
    my $r = @v > 1 ?
            join(":", map { $v[$_] =~ s/:/\\x3a/g if($_<$#v); $v[$_] } 0..$#v) :
            $v[0];

    my $src = $FW_webArgs{"src_$i"};
    push @rows, "#$src $r";
    push @plot, "\"<IN>\" using 1:2 axes ".
                ($FW_webArgs{"axes_$i"} eq "right" ? "x1y2" : "x1y1").
                ($FW_webArgs{"title_$i"} eq "notitle" ? " notitle" :
                            " title '".$FW_webArgs{"title_$i"} ."'").
                " ls "    .$FW_webArgs{"style_$i"} .
                " lw "    .$FW_webArgs{"width_$i"} .
                " with "  .$FW_webArgs{"type_$i"};
  }
  push @rows, "";
  for(my $i=0; $i < @plot; $i++) {
    my $r = $plot[$i];
    $r = "plot $r" if($i == 0);
    $r = "     $r" if($i > 0);
    $r = "$r,\\" if($i+1 < @plot);
    push @rows, $r;
  }

  my $hash = $defs{$FW_webArgs{detail}};
  my $err = FileWrite("$FW_gplotdir/$hash->{GPLOTFILE}.gplot", @rows);
  $FW_RET .= "<div id='errmsg'>SVG_WriteGplot: $err</div>" if($err);

  return 0;
}

#######################################################
# srcDesc:
# - {all}  : space separated plot arguments, in the file order, without devname
# - {order}: unique name of the devs (FileLog,etc) in the .gplot order
# - {src}{X}: hash (X is an order element), consisting of
#     {arg}: plot arguments for one dev, space separated
#     {idx}: number of lines requested from the same source
#     {num}: number of this src in the order array
# - {rev}{orderIdx}{localIdx} = N: reverse lookup of the plot argument index,
#      using {src}{X}{num} as orderIdx and {src}{X}{idx} as localIdx
sub
SVG_readgplotfile($$$)
{
  my ($wl, $gplot_pgm, $plotmode) = @_;

  ############################
  # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
  # the plot directive with our own, as we offer a file for each line
  my (%srcDesc, @data, $plot);

  my $ld = $defs{$wl}{LOGDEVICE}
     if($defs{$wl} && $defs{$wl}{LOGDEVICE});
  my $ldType = $defs{$defs{$wl}{LOGDEVICE}}{TYPE}
     if($ld && $defs{$ld});
  if(!$ldType && $defs{$wl}) {
    $ldType = $defs{$wl}{TYPE};
    $ld = $wl;
  }

  my ($err1, $err2, @svgplotfile);
  ($err1, @svgplotfile) = FileRead($gplot_pgm);
  ($err2, @svgplotfile) = FileRead("$FW_gplotdir/template.gplot") if($err1);
  return ($err1, undef) if($err2);
  my ($plotfnCnt, $srcNum) = (0,0);
  my @empty;
  $srcDesc{all} = "";
  $srcDesc{order} = \@empty;

  my $specval = AttrVal($wl, "plotfunction", undef);

  my $plotReplace = AttrVal($wl, "plotReplace", undef);
  my $pr;
  (undef, $pr) = parseParams($plotReplace,"\\s"," ") if($plotReplace);
  my $prSubst = sub($)
  {
    return "%$_[0]%" if(!$pr);
    my $v = $pr->{$_[0]};
    return "%$_[0]%" if(!$v);
    if($v =~ m/^{.*}$/) {
      $cmdFromAnalyze = $v;
      return eval $v;
    } else {
      return $v;
    }
  };

  foreach my $l (@svgplotfile) {
    $l = "$l\n" unless $l =~ m/\n$/;

    map { $l =~ s/%($_)%/&$prSubst($1)/ge } keys %$pr if($plotReplace);
    my ($src, $plotfn) = (undef, undef);
    if($l =~ m/^#([^ ]*) (.*)$/) {
      if($1 eq $ldType) {
        $src = $ld; $plotfn = $2;
      } elsif($1 && $defs{$1}) {
        $src = $1; $plotfn = $2;
      }
    } elsif($l =~ "^plot" || $plot) {
      $plot .= $l;
    } else {
      push(@data, $l);
    }

    if($plotfn) {
      Log 3, "$wl: space is not allowed in $ldType definition: $plotfn"
        if($plotfn =~ m/\s/);
      if ($specval) {
        my @spec = split(" ",$specval);
        my $spec_count=1;
        foreach (@spec) {
          $plotfn =~ s/<SPEC$spec_count>/$_/g;
          $spec_count++;
        }
      }

      my $p = $srcDesc{src}{$src};
      if(!$p) {
        $p = { arg => $plotfn, idx=>0, num=>$srcNum++ };
        $srcDesc{src}{$src} = $p;
        push(@{$srcDesc{order}}, $src);
      } else {
        $p->{arg} .= " $plotfn";
        $p->{idx}++;
      }
      $srcDesc{rev}{$p->{num}}{$p->{idx}} = $plotfnCnt++;
      $srcDesc{all} .= " $plotfn";
    }
  }

  return (undef, \@data, $plot, \%srcDesc);
}

sub
SVG_substcfg($$$$$$)
{
  my ($splitret, $wl, $cfg, $plot, $file, $tmpfile) = @_;

  # interpret title and label as a perl command and make
  # to all internal values e.g. $value.

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

  my $gplot_script = join("", @{$cfg});
  $gplot_script .=  $plot if(!$splitret);

  my $plotReplace = AttrVal($wl, "plotReplace", undef);
  if($plotReplace) {
    my ($list, $pr) = parseParams($plotReplace, "\\s"," ");
    for my $k (keys %$pr) {
      if($pr->{$k} =~ m/^{.*}$/) {
        $cmdFromAnalyze = $pr->{$k};
        $pr->{$k} = eval $cmdFromAnalyze;
      }
      $gplot_script =~ s/<$k>/$pr->{$k}/g;
    }
  }

  $gplot_script =~ s/<OUT>/$tmpfile/g;
  $gplot_script =~ s/<IN>/$file/g;

  my $ps = SVG_getplotsize($wl);
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
SVG_tspec(@)
{
  return sprintf("%04d-%02d-%02d_%02d:%02d:%02d",
                 $_[5]+1900,$_[4]+1,$_[3],$_[2],$_[1],$_[0]);
}

##################
# Calculate either the number of scrollable SVGs (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
SVG_calcOffsets($$)
{
  my ($d,$wl) = @_;

  my $pm = AttrVal($wl,"plotmode",$FW_plotmode);

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

  my $off = 0;
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

  my $endPlotNow = (SVG_Attr($FW_wname, $wl, "endPlotNow", undef) && !$st);
  if($zoom eq "hour") {
    if($endPlotNow) {
      my $t = int(($now + $off*3600 - 3600)/300.0)*300 + 300;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(@l);
      @l = localtime($t+3599);
      $SVG_devs{$d}{to}   = SVG_tspec(@l);
    } else { 
      my $t = int($now/3600)*3600 + $off*3600;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(@l);
      @l = localtime($t+3600-1);
      $SVG_devs{$d}{to}   = SVG_tspec(@l);
    }

  } elsif($zoom eq "qday") {
    if($endPlotNow) {
      my $t = int($now/300)*300 + ($off-1)*21600;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec( 0,$l[1],$l[2],$l[3],$l[4],$l[5]);
      @l = localtime($t+21600-1);
      $SVG_devs{$d}{to}   = SVG_tspec(59,$l[1],$l[2],$l[3],$l[4],$l[5]);
    } else { 
      my $t = int($now/3600)*3600 + $off*21600;
      my @l = localtime($t);
      $l[2] = int($l[2]/6)*6;
      $SVG_devs{$d}{from} = SVG_tspec( 0, 0,$l[2],$l[3],$l[4],$l[5]);
      $l[2] += 5;
      $SVG_devs{$d}{to}   = SVG_tspec(59,59,$l[2],$l[3],$l[4],$l[5]);
    }

  } elsif($zoom =~ m/^(\d+)?day/) {
    my $nDays = $1 ? ($1-1) : 0;
    if($endPlotNow) {
      my $t = int($now/300)*300 + ($off-$nDays-1)*86400;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec(0,$l[1],$l[2],$l[3],$l[4],$l[5]);
      @l = localtime($t+(1+$nDays)*86400-1);
      $SVG_devs{$d}{to}   = SVG_tspec(59,$l[1],$l[2],$l[3],$l[4],$l[5]);
    } else { 
      my $t = $now + ($off-$nDays)*86400;
      my @l = localtime($t);
      $SVG_devs{$d}{from} = SVG_tspec( 0, 0, 0,$l[3],$l[4],$l[5]);
      @l = localtime($t+$nDays*86400);
      $SVG_devs{$d}{to}   = SVG_tspec(59,59,23,$l[3],$l[4],$l[5]);
    }

  } elsif($zoom eq "week") {
    my @l = localtime($now);
    my $start = (SVG_Attr($FW_wname, $wl, "endPlotToday", undef) ? 
        6 : $l[6] - SVG_Attr($FW_wname, $wl, "plotWeekStartDay", 0));
    $start += 7 if($start < 0);
    my $t = $now - ($start*86400) + ($off*86400)*7;
    @l = localtime($t);
    $SVG_devs{$d}{from} = SVG_tspec( 0, 0, 0,$l[3],$l[4],$l[5]);
    @l = localtime($t+6*86400);
    $SVG_devs{$d}{to}   = SVG_tspec(59,59,23,$l[3],$l[4],$l[5]);

 } elsif($zoom eq "month") {
    my ($sd,$ed,$sm,$em,$sy,$ey);
    my @l = localtime($now);
    while($off < -12) { # Correct the year
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    my @me = (31,28,31,30,31,30,31,31,30,31,30,31);

    if(SVG_Attr($FW_wname, $wl, "endPlotToday", undef)) {
      $sy = $ey = $l[5];
      $sm = $l[4]-1; $em = $l[4];
      $sm += 12, $sy-- if($sm < 0);
      $sd = $l[3]+1; $ed = $l[3];
      $sd = $me[$sm] if($sd > $me[$sm]);

    } else {
      $sy = $ey = $l[5];
      $sm = $em = $l[4];
      $sd = 1; $ed = $me[$l[4]];
      $ed++ if($l[4]==1 && !(($sy+1900)%4)); # leap year
    }
    $SVG_devs{$d}{from} = SVG_tspec( 0, 0, 0,$sd,$sm,$sy);
    $SVG_devs{$d}{to}   = SVG_tspec(59,59,23,$ed,$em,$ey);

  } elsif($zoom eq "year") {
    my @l = localtime($now);
    $l[5] += ($off-1);
    if(SVG_Attr($FW_wname, $wl, "endPlotToday", undef)) {
      $SVG_devs{$d}{from} = SVG_tspec( 0, 0, 0,$l[3],$l[4],$l[5]);
      $l[5]++; # today, 23:59
      $SVG_devs{$d}{to}   = SVG_tspec(59,59,23,$l[3],$l[4],$l[5]);

    } elsif(SVG_Attr($FW_wname, $wl, "endPlotNow", undef)) {
      $SVG_devs{$d}{from} = SVG_tspec(0, $l[0], @l);
      $SVG_devs{$d}{from} = SVG_tspec(@l);
      $l[5]++; # now
      $SVG_devs{$d}{to}   = SVG_tspec(@l);

    } else {
      $l[5]++;
      $SVG_devs{$d}{from} = SVG_tspec( 0, 0, 0, 1, 0,$l[5]); #Jan01 00:00:00
      $SVG_devs{$d}{to}   = SVG_tspec(59,59,23,31,11,$l[5]); #Dec31 23:59:59
    }
  }
}


######################
# Generate an image from the log via gnuplot or SVG
sub
SVG_showLog($)
{
  return SVG_doShowLog($FW_webArgs{dev},
                       $FW_webArgs{logdev},
                       $FW_webArgs{gplotfile},
                       $FW_webArgs{logfile});
}

sub
SVG_doShowLog($$$$;$)
{
  my ($wl, $d, $type, $file, $noHeader) = @_;
  my $pm = AttrVal($wl,"plotmode",$FW_plotmode);
  my $gplot_pgm = "$FW_gplotdir/$type.gplot";

  my ($err, $cfg, $plot, $srcDesc) = SVG_readgplotfile($wl, $gplot_pgm, $pm);
  if($err || !$defs{$d}) {
    my $msg = ($defs{$d} ? "Cannot read $gplot_pgm" : "No Logdevice $d");
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

  my ($f,$t)=($SVG_devs{$d}{from}, $SVG_devs{$d}{to});
  $f = 0 if(!$f);     # From the beginning of time...
  $t = 9 if(!$t);     # till the end

  if($pm =~ m/gnuplot/) {

    my $tmpfile = "/tmp/file.$$";
    my $errfile = "/tmp/gnuplot.err";
    
    my $da = SVG_getData($wl, $f, $t, $srcDesc, 0); # substcfg needs it(!)

    my $tmpstring = "";
    open(FH, ">$tmpfile");
    for(my $dIdx=0; $dIdx<@{$da}; $dIdx++) {
      if (${$da->[$dIdx]}) {
        $tmpstring = ${$da->[$dIdx]};
        $tmpstring =~ s/#.*/\n/g;
      } else {
        $tmpstring = "$f 0\n\n";
      }
      print FH "$tmpstring";

    }
    close(FH);

    # put in the filename of the temporary data file into the plot file string
    my $i = 0;
    $plot =~ s/\".*?using 1:[^ ]+ /"\"$tmpfile\" i " . $i++ . " using 1:2 "/gse;

    $plot = "set xrange [\"$f\":\"$t\"]\n\n$plot" if($SVG_devs{$d}{from});
    my $gplot_script = SVG_substcfg(0, $wl, $cfg, $plot, $file, $tmpfile);
    $gplot_script =~ s/<TMPFILE>/$tmpfile/g;

    $plot =~ s/ls \w+//g;
    open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
    print FH $gplot_script;
    close(FH);
    unlink($tmpfile);

    my $ext;
    if($pm eq "gnuplot-scroll") {
      $FW_RETTYPE = "image/png";
      $ext = "png";
    }
    else {
      $FW_RETTYPE = "image/svg+xml";
      $ext = "svg";
    }
    
    open(FH, "$tmpfile.$ext");         # read in the result and send it
    binmode (FH); # necessary for Windows
    FW_pO join("", <FH>);
    close(FH);
    unlink("$tmpfile.$ext");

  } elsif($pm eq "SVG") {
    my ($f,$t)=($SVG_devs{$d}{from}, $SVG_devs{$d}{to});
    $f = 0 if(!$f);     # From the beginning of time...
    $t = 9 if(!$t);     # till the end

    Log3 $FW_wname, 5, "plotcommand: get $d $file INT $f $t ".$srcDesc->{all};

    $FW_RETTYPE = "image/svg+xml";

    (my $cachedate = TimeNow()) =~ s/ /_/g;
    my $SVGcache = (AttrVal($FW_wname, "SVGcache", undef) && $t lt $cachedate);
    my $cDir = "$FW_dir/SVGcache";
    my $cFile = "$wl-$f-$t.svg";
    $cFile =~ s/:/-/g; # For Windows / #11053
    my $cPath = "$cDir/$cFile";
    if($SVGcache && open(CFH, $cPath)) {
      FW_pO join("", <CFH>);
      close(CFH);

    } else {
      my $da = SVG_getData($wl, $f, $t, $srcDesc, 0); # substcfg needs it(!)
      ($cfg, $plot) = SVG_substcfg(1, $wl, $cfg, $plot, $file, "<OuT>");
      my $ret = SVG_render($wl, $f, $t, $cfg, $da,
                        $plot, $FW_wname, $FW_cssdir, $srcDesc, $noHeader);
      $internal_data = "";
      FW_pO $ret;
      if($SVGcache) {
        mkdir($cDir) if(! -d $cDir);
        if(open(CFH, ">$cPath")) {
          print CFH $ret;
          close(CFH);
        }
      }
    }

  }
  return ($FW_RETTYPE, $FW_RET);

}

sub
SVG_getData($$$$$)
{
  my ($d, $f,$t,$srcDesc,$showData) = @_;
  my (@da, $ret, @vals); 
  my @keys = ("min","mindate","max","maxdate","currval","currdate",
              "firstval","firstdate","avg","cnt","lastraw","sum");

  foreach my $src (@{$srcDesc->{order}}) {
    my $s = $srcDesc->{src}{$src};
    my $fname = ($src eq $defs{$d}{LOGDEVICE} ? $defs{$d}{LOGFILE} : "CURRENT");
    my $cmd = "get $src $fname INT $f $t ".$s->{arg};
    FW_fC($cmd, 1);
    if($showData) {
      $ret .= "\n$cmd\n\n";
      $ret .= $$internal_data if(ref $internal_data eq "SCALAR");

    } else {
      push(@da, $internal_data);
      for(my $i = 0; $i<=$s->{idx}; $i++) {
        my %h;
        foreach my $k (@keys) {
          $h{$k} = $data{$k.($i+1)};
        }
        push @vals, \%h;
      }
    }
  }

  # Reorder the $data{maxX} stuff
  my ($min, $max) = (999999, -999999);
  my $no = int(keys %{$srcDesc->{rev}});
  for(my $oi = 0; $oi < $no; $oi++) {
    my $nl = int(keys %{$srcDesc->{rev}{$oi}});
    for(my $li = 0; $li < $nl; $li++) {
      my $r = $srcDesc->{rev}{$oi}{$li}+1;
      my $val = shift @vals;
      foreach my $k (@keys) {
        $min = $val->{$k} if($k eq "min" && defined($val->{$k}) &&
                        $val->{$k} =~ m/[-+]?\d*\.?\d+/ && $val->{$k} < $min);
        $max = $val->{$k} if($k eq "max" && defined($val->{$k}) &&
                        $val->{$k} =~ m/[-+]?\d*\.?\d+/ && $val->{$k} > $max);
        $data{"$k$r"} = $val->{$k};
      }
    }
  }
  $data{maxAll} = $max;
  $data{minAll} = $min;

  return $ret if($showData);
  return \@da;
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
  $pTemp = $plot; $i = 0;
        $pTemp =~ s/title( '([^']*)')?/$lTitle[$i++]=(defined($2)?$2:"")/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ with (\w+)/$lType[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ ls (\w+)/$lStyle[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ lw ([\w.]+)/$lWidth[$i++]=$1/gse;

  for my $i (0..int(@lType)-1) {         # lAxis is optional
    $lAxis[$i] = "x1y2" if(!$lAxis[$i]);
    $lStyle[$i] = "class=\"SVGplot ".
                        (defined($lStyle[$i]) ? $lStyle[$i] : "l$i")."\"";
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
  if(open(FH, "$dir/${baseStyle}$fName") ||     # Forum #32530
     open(FH, "$dir/$fName")) {
    return 1;
  }
  return 0;
}

#####################################
sub
SVG_getSteps($$$)
{
  my ($range,$min,$max) = @_;

  my $dh = $max - $min;
  my ($step, $mi, $ma) = (1, 1, 1);
  my @limit = (0.001, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50,
               100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000,
               200000, 500000, 1000000, 2000000);

  for my $li (0..$#limit-1) {
    my $l = $limit[$li];
    next if($dh > $l*10);
    $ma = $range ? $max : SVG_doround($max, $l, 1);
    $mi = $range ? $min : SVG_doround($min, $l, 0);
    if(($ma-$mi)/$l >= 7) {    # If more then 7 steps, then choose next
      $l = $limit[$li+1];
      $ma = $range ? $max : SVG_doround($max, $l, 1);
      $mi = $range ? $min : SVG_doround($min, $l, 0);
    }
    $step = $l;
    last;
  }
  if($step==0.001 && $max==$min) { # Don't want 0.001 range for nil
     $step = 1;
     $ma = $mi + $step;
  }

  return ($step, $mi, $ma);
}

sub
SVG_render($$$$$$$$$$)
{
  my $name = shift;  # e.g. wl_8
  my $from = shift;  # e.g. 2008-01-01
  my $to = shift;    # e.g. 2009-01-01
  my $confp = shift; # lines from the .gplot file, w/o FileLog and plot
  my $da = shift;    # data pointer array
  my $plot = shift;  # Plot lines from the .gplot file
  my $parent_name = shift;  # e.g. FHEMWEB instance name
  my $parent_dir  = shift;  # FW_dir
  my $srcDesc     = shift;  # #FileLog lines, as array pointer
  my $noHeader     = shift;

  $SVG_RET="";
  my $SVG_ss = AttrVal($parent_name, "smallscreen", 0);

  my ($nr_left_axis,$nr_right_axis,$use_left_axis,$use_right_axis) =
                      split(",", SVG_Attr($parent_name, $name,"nrAxis","1,1"));

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
  my $w = $ow-$nr_left_axis*$axis_width-$nr_right_axis*$axis_width;
  my $h = $oh-2*$y;   # Rect size

  my @filter;
  foreach my $src (keys %{$srcDesc->{src}}) {
    my $f = CallFn($src, "SVG_regexpFn", $src, $srcDesc->{src}{$src}{arg});
    push(@filter, $f) if($f);
  }
  my $filter = join("|", @filter);
  $filter =~ s/"/./g;
  $filter = AttrVal($parent_name, "longpollSVG", 0) ? "flog=\"$filter\"" : "";

  my %dataIdx;   # Build a reverse Index for the dataSource


  ######################
  # SVG Header
  my $svghdr = 'version="1.1" xmlns="http://www.w3.org/2000/svg" '.
               'xmlns:xlink="http://www.w3.org/1999/xlink" '.
               "id='SVGPLOT_$name' $filter data-origin='FHEM'";
  if(!$noHeader) {
    SVG_pO '<?xml version="1.0" encoding="UTF-8"?>';
    SVG_pO '<!DOCTYPE svg>';
    SVG_pO "<svg $svghdr width=\"${ow}px\" height=\"${oh}px\">";
  } else {
    SVG_pO "<svg $svghdr style='width:${ow}px; height:${oh}px;'>";
  }

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


  my ($xmin, $xmax, $xtics)= (99999999, -99999999, "");
  if(defined($conf{xrange})) {
    my $idx= 1;
    while(defined($data{"xmin$idx"})) {
      $xmin= $data{"xmin$idx"} if($data{"xmin$idx"}< $xmin);
      $xmax= $data{"xmax$idx"} if($data{"xmax$idx"}> $xmax);
      $idx++;
    }
    #main::Debug "xmin= $xmin   xmax=$xmax";
    $conf{xrange} = AnalyzeCommand(undef, $1) if($conf{xrange} =~ /^({.*})$/);
    if($conf{xrange} =~ /\[(.*):(.*)\]/) {
      $xmin = $1 if($1 ne "");
      $xmax = $2 if($2 ne "");
    }
  }
  $xtics = defined($conf{xtics}) ? $conf{xtics} : "";

  ######################
  # Loop over the input, digest dates, calculate min/max values
  my ($fromsec, $tosec);
  $fromsec = SVG_time_to_sec($from) if($from ne "0"); # 0 is special
  $tosec   = SVG_time_to_sec($to)   if($to ne "9");   # 9 is special
  my $tmul; 
  $tmul = $w/($tosec-$fromsec) if($tosec && $fromsec && $tosec != $fromsec);

  my ($min, $max, $idx) = (99999999, -99999999, 0);
  my (%hmin, %hmax, @hdx, @hdy);
  my ($dxp, $dyp) = (\(), \());

  my ($d, $v, $ld, $lv) = ("","","","");
  for(my $dIdx=0; $dIdx<@{$da}; $dIdx++) {
    my $lIdx = 0;
    $idx = $srcDesc->{rev}{$dIdx}{$lIdx};
    my $dp = $da->[$dIdx];
    next if(ref $dp ne "SCALAR");       # Avoid Crash, Forum #34523
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
        $lIdx++;
        $idx = $srcDesc->{rev}{$dIdx}{$lIdx};
        last if(!$idx);

      } elsif( $l =~ /^;/ ) { #allow ;special lines
        if( $l =~ m/^;p (\S+)\s(\S+)/ ) {# point
          my $xmul = $w/($xmax-$xmin) if($xmax-$xmin > 0 );
          my $x1;
          if( $conf{xrange} ) {
            $x1 = int(($1-$xmin)*$xmul);
          } else {
            $x1 = $x1;
          }
          my $y1 = $2;

          push @{$dxp}, $x1;
          push @{$dyp}, $y1;
          $min = $y1 if($min > $y1);
          $max = $y1 if($max < $y1);

        } elsif( $conf{lType}[$idx] eq "lines" ) {
          push @{$dxp}, undef;
          push @{$dyp}, $l;

        }

      } else {
        ($d, $v) = split(" ", $l);
        $d =  ($tmul ? int((SVG_time_to_sec($d)-$fromsec)*$tmul) : $d);
        $d = 0 if($tmul && $d < 0); # Forum #40358
        if($ld ne $d || $lv ne $v) {            # Saves a lot on year zoomlevel
          $ld = $d; $lv = $v;
          push @{$dxp}, $d;
          push @{$dyp}, $v;
          $min = $v if($min > $v);
          $max = $v if($max < $v);
        }
      }
      last if($ndpoff == -1);
    }
  }

  $dxp = $hdx[0];
  if(($dxp && int(@{$dxp}) < 2 && !$tosec) ||  # not enough data and no range...
     (!$tmul && !$dxp)) {
    SVG_pO "</svg>";
    return $SVG_RET;
  }
  if(!$tmul) {                     # recompute the x data if no range sepcified
    $fromsec = SVG_time_to_sec($dxp->[0]) if(!$fromsec);
    $tosec = SVG_time_to_sec($dxp->[int(@{$dxp})-1]) if(!$tosec);
    $tmul = $w/($tosec-$fromsec) if($tosec != $fromsec);

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

  if($ddur <= 0.1) {
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
  if( $conf{xrange} ) { # user defined range
    if( !$xtics || $xtics ne "()" ) { # auto tics
      my $xmul = $w/($xmax-$xmin);
      my ($step,$mi,$ma) = SVG_getSteps( $conf{xrange}, $xmin, $xmax );
      $step /= 5 if( $step > 50 );
      $step /= 2 if( $step > 10 );
      for(my $i = $mi; $i <= $ma; $i += $step) {
        $off1 = int($x+($i-$xmin)*$xmul);
        SVG_pO "<polyline class='SVGplot' points='$off1,$y $off1,$off2'/>";
        SVG_pO "<polyline class='SVGplot' points='$off1,$off3 $off1,$off4'/>";
      }
    }

  } else { # times
    $initoffset = int(($tstep/2)/86400)*86400 if($aligntics);
    for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $tstep) {
      $i = SVG_time_align($i,$aligntics);
      $off1 = int($x+($i-$fromsec)*$tmul);
      SVG_pO "<polyline class='SVGplot' points='$off1,$y $off1,$off2'/>";
      SVG_pO "<polyline class='SVGplot' points='$off1,$off3 $off1,$off4'/>";
    }

  }

  ######################
  # then the text and the grid
  $off1 = $x;
  $off2 = $y+$h+$th;
  my $t = SVG_fmtTime($first_tag, $fromsec);
  SVG_pO "<text x=\"0\" y=\"$off2\" class=\"ylabel\">$t</text>"
        if(!$conf{xrange});
  $initoffset = $step;

  if(SVG_Attr($parent_name,$name,"endPlotNow",undef) && $ddur>1.1 && $ddur<6.9){
    my $now = time();
    $initoffset -= ($now+fhemTzOffset($now))%86400; # Forum #25768
  }

  if( $conf{xrange} ) { # user defined range
    my $xmul = $w/($xmax-$xmin);
    if( $xtics ) { #user tics and grid
      my $tic = $xtics;
      $tic =~ s/^\((.*)\)$/$1/;   # Strip ()
      foreach my $onetic (split(",", $tic)) {
        $onetic =~ s/^ *(.*) *$/$1/;
        my ($tlabel, $tvalue) = split(" ", $onetic);
        $tlabel =~ s/^"(.*)"$/$1/;
        $tvalue = 0 if( !$tvalue );

        $off1 = int($x+($tvalue-$xmin)*$xmul);
        $t = $tvalue;
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
                  "text-anchor=\"middle\">$t</text>";
        SVG_pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>";
      }

    } else { # auto grid
      my ($step,$mi,$ma) = SVG_getSteps( $conf{xrange}, $xmin, $xmax );

      for(my $i = $mi; $i <= $ma; $i += $step) {
        $off1 = int($x+($i-$xmin)*$xmul);
        $t = $i;
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
                  "text-anchor=\"middle\">$t</text>";
        SVG_pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>"
                if( $i != $mi && $i != $ma );
      }

    }

  } else { # times
    $initoffset = int(($step/2)/86400)*86400 if($aligntext);
    for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $step) {
      $i = SVG_time_align($i,$aligntext);
      $off1 = int($x+($i-$fromsec)*$tmul);
      $t = SVG_fmtTime($tag, $i);
      SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
                "text-anchor=\"middle\">$t</text>";
      SVG_pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>";
    }
  }


  ######################
  # Left and right axis tics / text / grid
  #-- just in case we have only one data line, but want to draw both axes
  $hmin{x1y1}=$hmin{x1y2}, $hmax{x1y1}=$hmax{x1y2} if(!defined($hmin{x1y1}));
  $hmin{x1y2}=$hmin{x1y1}, $hmax{x1y2}=$hmax{x1y1} if(!defined($hmin{x1y2}));

  my (%hstep,%htics);

  #-- yrange handling for axes x1y1..x1y8
  for my $idx (0..7)  {
    my $a = "x1y".($idx+1);
    next if( !defined($hmax{$a}) || !defined($hmin{$a}) );
    my $yra="y".($idx+1)."range";
    $yra="yrange" if ($yra eq "y1range");  
    #-- yrange is specified in plotfile
    if($conf{$yra}) {
      $conf{$yra} = AnalyzeCommand(undef, $1)
                         if($conf{$yra} =~ /^({.*})$/);
      if($conf{$yra} =~ /\[(.*):(.*)\]/) {
        $hmin{$a} = $1 if($1 ne "");
        $hmax{$a} = $2 if($2 ne "");
      }
    }

    #-- tics handling
    my $yt="y".($idx+1)."tics";
    $yt="ytics" if ($yt eq"y1tics");
    $htics{$a} = defined($conf{$yt}) ? $conf{$yt} : "";

    #-- Round values, compute a nice step  
    ($hstep{$a}, $hmin{$a}, $hmax{$a}) =
        SVG_getSteps($conf{$yra},$hmin{$a},$hmax{$a});

    #Log3 $name, 2, "Axis $a has interval [$hmin{$a},$hmax{$a}],
    # step $hstep{$a}, tics $htics{$a}\n";
  }

  #-- run through all axes for drawing (each only once !) 
  foreach my $a (sort keys %hmin) {

    next if(!defined($hmin{$a})); # Bogus case

    #-- safeguarding against pathological data
    if( !$hstep{$a} ){
        $hmax{$a} = $hmin{$a}+1;
        $hstep{$a} = 1;
    }

    #-- Draw the y-axis values and grid
    my $dh = $hmax{$a} - $hmin{$a};
    my $hmul = $dh>0 ? $h/$dh : $h;

    my $axis = 1;
    $axis = $1 if( $a =~ m/x\d+y(\d+)/ );

    my $scale = "y".($axis)."scale"; $scale = "yscale" if( $axis == 1 );
    my $log = ""; $log = $conf{$scale} if( $conf{$scale} );
    my $f_log = int($hmax{$a}) ? (SVG_log10($hmax{$a}) / $hmax{$a}) : 1;

    # offsets
    my ($align,$display,$cll);
    if( $axis <= $use_left_axis ) {
      $off1 = $x - ($axis-1)*$axis_width-4-$th*0.3;
      $off3 = $x - ($axis-1)*$axis_width-4;
      $off4 = $off3+5;
      $align = " text-anchor=\"end\"";
      $display = "";
      $cll = "";
    } elsif( $axis <= $use_left_axis+$use_right_axis ) {
      $off1 = $x+4+$w+($axis-1-$use_left_axis)*$axis_width+$th*0.3;
      $off3 = $x+4+$w+($axis-1-$use_left_axis)*$axis_width-5;
      $off4 = $off3+5;
      $align = "";
      $display = "";
      $cll = "";
    } else {
      $off1 = $x-$th*0.3+30;
      $off3 = $x+30;
      $off4 = $off3+5;
      $align = " text-anchor=\"end\"";
      $display = " display=\"none\" id=\"hline_$axis\"";
      $cll = " class=\"SVGplot l$axis\"";
    }

    #-- grouping
    SVG_pO "<g$display>";
    my $yp = $y + $h;

    #-- axis if not left or right axis
    SVG_pO "<polyline points=\"$off3,$y $off3,$yp\" $cll/>"
        if($a ne "x1y1" && $a ne "x1y2");

    #-- tics handling
    my $tic = $htics{$a};
    #-- tics as in the config-file
    if($tic && $tic !~ m/mirror/) {
      $tic =~ s/^\((.*)\)$/$1/;   # Strip ()
      for(my $decimal = 0;
          $decimal < ($log eq 'log'?SVG_log10($hmax{$a}):1);
          $decimal++ ) {
      foreach my $onetic (split(",", $tic)) {
        $onetic =~ s/^ *(.*) *$/$1/;
        my ($tlabel, $tvalue) = split(" ", $onetic);
        $tlabel =~ s/^"(.*)"$/$1/;
        $tvalue = 0 if( !$tvalue );
        $tvalue /= 10 ** $decimal;
        $tlabel = $tvalue if( !$tlabel );

        $off2 = int($y+($hmax{$a}-$tvalue)*$hmul);
        $off2 = int($y+($hmax{$a}-SVG_log10($tvalue)/$f_log)*$hmul)
                if( $log eq 'log' );
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
        SVG_pO
          "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$tlabel</text>";
      }
      }
    #-- tics automatically 
    } elsif( $hstep{$a}>0 ) {            
      for(my $decimal = 0;
          $decimal < ($log eq 'log'?SVG_log10($hmax{$a}):1);
          $decimal++ ) {
      for(my $i = $hmin{$a}; $i <= $hmax{$a}; $i += $hstep{$a}) {
        my $i = $i / 10 ** $decimal;
        $off2 = int($y+($hmax{$a}-$i)*$hmul);
        $off2 = int($y+($hmax{$a}-SVG_log10($i)/$f_log)*$hmul)
                if( $log eq 'log' );
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
        SVG_pO
          "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$txt</text>";
      }
      }
    }
    SVG_pO "</g>";

  }

  ######################
  # Second loop over the data: draw the measured points
  for(my $idx=$#hdx; $idx >= 0; $idx--) {
    my $a = $conf{lAxis}[$idx];

    SVG_pO "<!-- Warning: No axis for data item $idx defined -->"
        if(!defined($a));
    next if(!defined($a));

    my $axis = 1; $axis = $1 if( $a =~ m/x\d+y(\d+)/ );
    my $scale = "y".($axis)."scale"; $scale = "yscale" if( $axis == 1 );
    my $log = ""; $log = $conf{$scale} if( $conf{$scale} );

    $min = $hmin{$a};
    $hmax{$a} += 1 if($min == $hmax{$a});  # Else division by 0 in the next line
    my $xmul;
    $xmul = $w/($xmax-$xmin) if( $conf{xrange} );
    my $hmul = $h/($hmax{$a}-$min);
    my $ret = "";
    my ($dxp, $dyp) = ($hdx[$idx], $hdy[$idx]);
    SVG_pO "<!-- Warning: No data item $idx defined -->" if(!defined($dxp));
    next if(!defined($dxp));

    my $f_log = int($hmax{$a}) ? (SVG_log10($hmax{$a}) / $hmax{$a}) : 1;
    if( $log eq 'log' ) {
      foreach my $i (1..int(@{$dxp})-1) {
        $dyp->[$i] = SVG_log10($dyp->[$i]) / $f_log;
      }
    }

    my $yh = $y+$h;
    #-- Title attributes
    my $tl = $conf{lTitle}[$idx] ? $conf{lTitle}[$idx]  : "";
    #my $dec = int(log($hmul*3)/log(10)); # perl can be compiled without log() !
    my $dec = length(sprintf("%d",$hmul*3))-1;
    $dec = 0 if($dec < 0);
    my $attributes = "id=\"line_$idx\" decimals=\"$dec\" ".
          "x_min=\"$x\" ".
          ($conf{xrange}?"x_off=\"$xmin\" ":"x_off=\"$fromsec\" ").
          ($conf{xrange}?"x_mul=\"$xmul\" ":"t_mul=\"$tmul\" ").
          "y_h=\"$yh\" y_min=\"$min\" y_mul=\"$hmul\" title=\"$tl\" ".
          ($log eq 'log'?"log_scale=\"$f_log\" ":"").
          "onclick=\"parent.svg_click(evt)\" $conf{lWidth}[$idx]";
    my $lStyle = $conf{lStyle}[$idx];
    my $isFill = ($conf{lStyle}[$idx] =~ m/fill/);
    my $doClose = $isFill;

    my ($lx, $ly) = (-1,-1);

    my $lType = $conf{lType}[$idx];
    if($lType eq "points" ) {
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $ly = $x1; $ly = $y1;
        $ret =  sprintf(" %d,%d %d,%d %d,%d %d,%d %d,%d",
              $x1-3,$y1, $x1,$y1-3, $x1+3,$y1, $x1,$y1+3, $x1-3,$y1);
        SVG_pO "<polyline $attributes $lStyle points=\"$ret\"/>";
      }

    } elsif($lType eq "steps" || $lType eq "fsteps" ) {

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
          if($lType eq "steps") {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x2,$y1, $x2,$y2);
          } else {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x1,$y2, $x2,$y2);
          }
        }
      }
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);

      SVG_pO "<polyline $attributes $lStyle points=\"$ret\"/>";

    } elsif($lType eq "histeps" ) {
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
      SVG_pO "<polyline $attributes $lStyle points=\"$ret\"/>";

    } elsif( $lType eq "bars" ) {
      my $bw = $barwidth*$tmul;
      # bars are all of equal width (see far above !), 
      # position rounded to integer multiples of bar width
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = ( $x + $dxp->[$i] - $bw,
                           $y +$h-($dyp->[$i]-$min)*$hmul);
        my $curBw = $bw;
        if($x1 < $x) {
            $curBw -= $x - $x1;
            $x1 = $x;
        }
        my ($x2, $y2) = ($curBw, ($dyp->[$i]-$min)*$hmul);    
        SVG_pO "<rect $attributes $lStyle x=\"$x1\" y=\"$y1\" ".
                    "width=\"$x2\" height=\"$y2\"/>";
      }
    } elsif( $lType eq "ibars" ) { # Forum #35268
      if(@{$dxp} == 1) {
        my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
        $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                         $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
      } else {
        # interconnected bars (ibars):
        # these bars will connect all datapoints. so the width of the bars
        # might vary depending on the distance between data points
        foreach my $i (1..int(@{$dxp})-1) {
          my $x1 = $x + $dxp->[$i-1];
          my $y1 = $y +$h-($dyp->[$i]-$min)*$hmul;

          my $x2 = $x + $dxp->[$i]; # used to calculate bar width later

          my $height =  ($dyp->[$i]-$min)*$hmul;
          my $bw = $x2 - $x1;
          SVG_pO "<rect $attributes $lStyle x=\"$x1\" y=\"$y1\" ".
                        "width=\"$bw\" height=\"$height\"/>";
        }
      }
    } else {                            # lines and everything else
      my ($ymin, $ymax) = (99999999, -99999999);
      my %lt =(cubic=>"C",quadratic=>"Q",quadraticSmooth=>"T");
      my ($x1, $y1);
      my $lt = ($lt{$lType} ? $lt{$lType} : "L"); # defaults to line

      my $maxIdx = int(@{$dxp})-1;
      foreach my $i (0..$maxIdx) {

        if( !defined($dxp->[$i]) ) { # specials
          if(  $dyp->[$i] =~ m/^;$/ ) { # new line segment after newline
 
            my @tvals = split("[ ,]", $ret);
            if (@tvals > 2) {
                if ($tvals[0] ne "M") { # just points, no M/L
                    $ret = sprintf("M %d,%d $lt $ret", $tvals[1],$tvals[2]);
                }
            }

            SVG_pO "<path $attributes $lStyle d=\"$ret\"/>";
            $ret = "";
            
          } elsif( $dyp->[$i] =~ m/^;c (.*)/ ) {# close polyline ?
            $doClose = $1;

          } elsif( $dyp->[$i] =~ m/^;ls (\w+)?/ ) {# line style
            if( $1 ) {
              $lStyle = "class='SVGplot $1'";
            } else {
              $lStyle = $conf{lStyle}[$idx];
            }

          # marker with optional text
          } elsif( $dyp->[$i] =~ m/^;m (\S+)\s(\S+)(\s(\S+)\s(.*))?/ ) {
            if( defined($xmin) ) {
              $x1 = int($x+($1-$xmin)*$xmul);
            } else {
              $x1 = ($tmul ? int((SVG_time_to_sec($1)-$fromsec)*$tmul) : $x);
            }
            $y1 = int($y+$h-($2-$min)*$hmul);

            my $ret = sprintf("%d,%d %d,%d %d,%d %d,%d %d,%d",
                         $x1-3,$y1, $x1,$y1-3, $x1+3,$y1, $x1,$y1+3, $x1-3,$y1);
            SVG_pO "<polyline $attributes $lStyle points=\"$ret\"/>";

            SVG_pO "<text x=\"$x1\" y=\"$y1\" $lStyle text-anchor=\"$4\">$5".
                        "</text>" if( $3 );

          } elsif( $dyp->[$i] =~ m/^;t (\S+)\s(\S+)\s(\S+)\s(.*)/ ) {# text
            if( defined($xmin) ) {
              $x1 = int($x+($1-$xmin)*$xmul);
            } else {
              $x1 = ($tmul ? int((SVG_time_to_sec($1)-$fromsec)*$tmul) : $x);
            }
            $y1 = int($y+$h-($2-$min)*$hmul);


            SVG_pO "<text x=\"$x1\" y=\"$y1\" $lStyle text-anchor=\"$3\">$4".
                        "</text>";

          } else {
            Log3 $name, 2, "unknown special $dyp->[$i]"

          }

          next;
        }

        ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));

        next if($x1 == $lx && $y1 == $ly);

        # calc ymin/ymax for points with the same x coordinates
        if($x1 == $lx && $i < $maxIdx) {
          $ymin = $y1 if($y1 < $ymin);
          $ymax = $y1 if($y1 > $ymax);
          $ly = $y1;
          next;
        }

        if($i == 0) {
          if($doClose) {
            $ret .= sprintf("M %d,%d L %d,%d $lt", $x1,$y+$h, $x1,$y1);
          } else {
            $ret .= sprintf("M %d,%d $lt", $x1,$y1);
          }
          $lx = $x1; $ly = $y1;
          next;
        }

        # plot ymin/ymax range for points with the same x coordinates
        if( $ymin != 99999999 ) {
          $ret .=  sprintf(" %d,%d", $lx, $ymin);
          $ret .=  sprintf(" %d,%d", $lx, $ymax);
          $ret .=  sprintf(" %d,%d", $lx, $ly);
          ($ymin, $ymax) = (99999999, -99999999);
        }

        $ret .=  sprintf(" %d,%d", $x1, $y1) if ($lt ne "T");
        $ret .=  sprintf(" %.1f,%.1f", (($lx+$x1)/2.0), (($ly+$y1)/2.0))
                if (($lt eq "T") && ($lx > -1));
        $lx = $x1; $ly = $y1;
      }

      #-- calculate control points for interpolation
      $ret = SVG_getControlPoints($ret) if (($lt eq "C") || ($lt eq "Q"));
  
      #-- insert last point for filled line
      $ret .= sprintf(" %.1f,%.1f", $x1, $y1) if(($lt eq "T") && defined($x1));
      $ret .= sprintf(" L %d,%d Z", $x1, $y+$h) if($doClose && defined($x1));

      if($ret =~ m/^ (\d+),(\d+)/) { # just points, no M/L
        $ret = sprintf("M %d,%d $lt ", $1, $2).$ret;
      }
      $ret = "" if($maxIdx == 0);

      SVG_pO "<path $attributes $lStyle d=\"$ret\"/>";
    }

  }

  ######################
  # Plot caption (title) at the end, should be draw on top of the lines
  my $caption_pos = SVG_Attr($parent_name, $name, "captionPos", 'right');
  my( $li,$ri ) = (0,0);
  for my $i (0..int(@{$conf{lTitle}})-1) {
    my $caption_anchor = "end";
    if( $caption_pos eq 'auto' ) {
      my $a = $conf{lAxis}[$i];
      my $axis = 1; $axis = $1 if( $a && $a =~ m/x\d+y(\d+)/ );
      if( $axis <= $use_left_axis ) {
        $caption_anchor = "beginning";
      } else {
        $caption_anchor = "end";
      }
    } elsif( $caption_pos eq 'left' ) {
      $caption_anchor = "beginning";
    }

    my $txtoff1 = $nr_left_axis*$axis_width + $w - $th/2;
    $txtoff1 = $nr_left_axis*$axis_width+$th/2
        if($caption_anchor eq 'beginning');

    my $j = $i+1;
    my $t = $conf{lTitle}[$i];
    next if( !$t );
    my $txtoff2;
    if( $caption_anchor eq 'beginning' ) {
      $txtoff2 = $y + 3 + $th/1.3 + $th * $li;
      ++$li;
    } else {
      $txtoff2 = $y + 3 + $th/1.3 + $th * $ri;
      ++$ri;
    }

    my $desc = "";
    if(defined($data{"min$j"})     && $data{"min$j"}     ne "undef" &&
       defined($data{"currval$j"}) && $data{"currval$j"} ne "undef") {
      $desc = sprintf("%s: Min:%g Max:%g Last:%g",
        $t, $data{"min$j"}, $data{"max$j"}, $data{"currval$j"});
    }
    my $style = $conf{lStyle}[$i];
    $style =~ s/class="/class="legend /;
    SVG_pO "<text line_id=\"line_$i\" x=\"$txtoff1\" y=\"$txtoff2\" ".
        "text-anchor=\"$caption_anchor\" $style>$t<title>$desc</title></text>";

    $txtoff2 += $th;
  }

  my $fnName = SVG_isEmbed($FW_wname) ? "parent.window.svg_init" : "svg_init";

  SVG_pO "<script type='text/javascript'>if(typeof $fnName == 'function') ".
                "$fnName('SVGPLOT_$name')</script>";
  SVG_pO "</svg>";
  return $SVG_RET;
}

######################
# Derives control points for interpolation of bezier curves for SVG "path"
sub
SVG_getControlPoints($)
{
  my ($ret) = @_;
  my (@xa, @ya);
  my (@vals) = split("[ ,]", $ret);
  my (@xcp1, @xcp2, @ycp1, @ycp2);
  my $header = "";
  
  foreach my $i (0..int(@vals)-1) {
    $header .= $vals[$i] . ($i == 1 ? "," : " ");
    if ($vals[$i] eq "C" || $vals[$i] eq "Q") {
      my $lt = $vals[$i];
      $i++;

      my $ii = 0;
      
      while (defined($vals[$i])) {
        ($xa[$ii], $ya[$ii]) = ($vals[$i], $vals[$i+1]);
        $i += 2;
        $ii++;
      }

      return(1) if (@xa < 2);

      SVG_calcControlPoints(\@xcp1, \@xcp2, \@ycp1, \@ycp2, \@xa, \@ya);

      $ret = $header;
      foreach my $i (1..int(@xa)-1) {
        $ret .= sprintf(" %d,%d,%d,%d,%d,%d", $xcp1[$i-1], $ycp1[$i-1], $xcp2[$i-1], $ycp2[$i-1], $xa[$i], $ya[$i]) if ($lt eq "C");
        $ret .= sprintf(" %d,%d,%d,%d", $xcp2[$i-1], $ycp2[$i-1], $xa[$i], $ya[$i]) if ($lt eq "Q");
      }


    }
  }
  
  return($ret);
}

######################
# Calculate control points for interpolation of bezier curves for SVG "path"
sub
SVG_calcControlPoints($$$$$$)
{
  my ($px1, $px2, $py1, $py2, $inputx, $inputy) = @_;
  
  my $n = @{$inputx};
  
  # Loop over all Points in Input arrays
  for (my $i=0; $i<$n-1; $i++) {
    my (@lxp, @lyp);

    # Loop over 4 Points around actual Point to calculate
    my $iloc = 0;
    for (my $ii=$i-1; $ii<=$i+2; $ii++) {
      my $icorr = $ii;
      $icorr = 0 if ($icorr < 0);
      $icorr = $n-1 if ($icorr > $n-1);
      $lxp[$iloc] = $inputx->[$icorr];
      $lyp[$iloc] = $inputy->[$icorr];
      $iloc++;
    }

    # Calulcation of first control Point using first 3 Points around actual Point
    my $m1x = ($lxp[0]+$lxp[1])/2.0;
    my $m1y = ($lyp[0]+$lyp[1])/2.0;
    my $m2x = ($lxp[1]+$lxp[2])/2.0;
    my $m2y = ($lyp[1]+$lyp[2])/2.0;
    
    my $l1 = sqrt(($lxp[0]-$lxp[1])*($lxp[0]-$lxp[1])+($lyp[0]-$lyp[1])*($lyp[0]-$lyp[1]));
    my $l2 = sqrt(($lxp[1]-$lxp[2])*($lxp[1]-$lxp[2])+($lyp[1]-$lyp[2])*($lyp[1]-$lyp[2]));
    
    my $dxm = ($m1x - $m2x);
    my $dym = ($m1y - $m2y);
    
    my $k = 0;
    $k = $l2/($l1+$l2) if (($l1+$l2) != 0);
    
    my $tx = $lxp[1] - ($m2x + $dxm*$k);
    my $ty = $lyp[1] - ($m2y + $dym*$k);
    
    $px1->[$i] = $m2x + $tx;
    $py1->[$i] = $m2y + $ty;

    # Calulcation of second control Point using last 3 Points around actual Point
    $m1x = ($lxp[1]+$lxp[2])/2.0;
    $m1y = ($lyp[1]+$lyp[2])/2.0;
    $m2x = ($lxp[2]+$lxp[3])/2.0;
    $m2y = ($lyp[2]+$lyp[3])/2.0;
    
    $l1 = sqrt(($lxp[1]-$lxp[2])*($lxp[1]-$lxp[2])+($lyp[1]-$lyp[2])*($lyp[1]-$lyp[2]));
    $l2 = sqrt(($lxp[2]-$lxp[3])*($lxp[2]-$lxp[3])+($lyp[2]-$lyp[3])*($lyp[2]-$lyp[3]));
    
    $dxm = ($m1x - $m2x);
    $dym = ($m1y - $m2y);
    
    $k=0;
    $k = $l2/($l1+$l2) if (($l1+$l2) != 0);
    
    $tx = $lxp[2] - ($m2x + $dxm*$k);
    $ty = $lyp[2] - ($m2y + $dym*$k);
    
    $px2->[$i] = $m1x + $tx;
    $py2->[$i] = $m1y + $ty;
  }
  
  return (1);
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
  $svgdata =~ s/\.SVGplot\./\./g;

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
=item helper
=item summary    draw an SVG-Plot based on FileLog or DbLog data
=item summary_DE malt ein SVG-Plot aus FileLog oder DbLog Daten
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
    <li><a href="#endPlotNow">endPlotNow</a></li><br>
    <li><a href="#endPlotToday">endPlotToday</a></li><br>

    <a name="captionLeft"></a>
    <li>captionLeft<br>
      Show the legend on the left side (deprecated, will be autoconverted to
      captionPos)
      </li><br>

    <a name="captionPos"></a>
    <li>captionPos<br>
      right - Show the legend on the right side (default)<br>
      left - Show the legend on the left side<br>
      auto - Show the legend labels on the left or on the right side depending
      on the axis it belongs to<br>
      </li><br>

    <a name="fixedrange"></a>
    <li>fixedrange [offset]<br>
        Contains two time specs in the form YYYY-MM-DD separated by a space.
        In plotmode gnuplot-scroll(-svg) or SVG the given time-range will be
        used, and no scrolling for this SVG will be possible. Needed e.g. for
        looking at last-years data without scrolling.<br><br> If the value is
        one of hour, day, &lt;N&gt;days, week, month, year then set the zoom
        level for this SVG independently of the user specified zoom-level. This
        is useful for pages with multiple plots: one of the plots is best
        viewed in with the default (day) zoom, the other one with a week
        zoom.<br>

        If given, the optional integer parameter offset refers to a different
        period (e.g. last year: fixedrange year -1, 2 days ago: fixedrange day
        -2).

        </li><br>

    <a name="fixedoffset"></a>
    <li>fixedoffset &lt;nDays&gt;<br>
        Set an fixed offset (in days) for the plot.
        </li><br>

    <a name="label"></a>
    <li>label<br>
      Double-Colon separated list of values. The values will be used to replace
      &lt;L#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;L1&gt;, &lt;L2&gt;, etc.). Each value will be evaluated as a perl
      expression, so you have access e.g. to the Value functions.<br><br>

      If the plotmode is gnuplot-scroll(-svg) or SVG, you can also use the min,
      max, mindate, maxdate, avg, cnt, sum, firstval, firstdate, currval (last
      value) and currdate (last date) values of the individual curves, by
      accessing the corresponding values from the data hash, see the example
      below:<br>
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
      The value minAll and maxAll (representing the minimum/maximum over all
      values) is also available from the data hash.
      <br>Deprecated, see plotReplace.
      </li><br>

    <li><a href="#nrAxis">nrAxis</a></li><br>

    <a name="plotfunction"></a>
    <li>plotfunction<br>
      Space value separated list of values. The value will be used to replace
      &lt;SPEC#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;SPEC1&gt;, &lt;SPEC2&gt;, etc.) in the #FileLog or #DbLog directive.
      With this attribute you can use the same .gplot file for multiple devices
      with the same logdevice.
      <ul><b>Example:</b><br>
        <li>#FileLog &lt;SPEC1&gt;<br>
            with: attr &lt;SVGdevice&gt; plotfunction "4:IR\x3a:0:"<br>
            instead of<br>  
            #FileLog 4:IR\x3a:0:
        </li>
        <li>#DbLog &lt;SPEC1&gt;<br>
            with: attr &lt;SVGdevice&gt; plotfunction
            "Garage_Raumtemp:temperature::"<br> instead of<br>
            #DbLog Garage_Raumtemp:temperature::
        </li>
      </ul>
      Deprecated, see plotReplace.
      </li><br>

    <li><a href="#plotmode">plotmode</a></li><br>

    <a name="plotReplace"></a>
    <li>plotReplace<br>
      space separated list of key=value pairs. value may contain spaces if
      enclosed in "" or {}. value will be evaluated as a perl expression, if it
      is enclosed in {}.
      <br>
      In the .gplot file &lt;key&gt; is replaced with the corresponding value,
      the evaluation of {} takes place <i>after</i> the input file is
      processed, so $data{min1} etc can be used.
      <br>
      %key% will be repaced <i>before</i> the input file is processed, this
      expression can be used to replace parameters for the input processing.
    </li><br>

    <li><a href="#plotsize">plotsize</a></li><br>
    <li><a href="#plotWeekStartDay">plotWeekStartDay</a></li><br>

    <a name="startDate"></a>
    <li>startDate<br>
        Set the start date for the plot. Used for demo installations.
        </li><br>

    <a name="title"></a>
    <li>title<br>
      A special form of label (see above), which replaces the string &lt;TL&gt;
      in the .gplot file. It defaults to the filename of the logfile.
      <br>Deprecated, see plotReplace.
      </li><br>

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
    <li>If the range is of the form {...}, then it will be evaluated with perl.
        The result is a string, and must have the form [min:max]
      </li>
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
    <a name="captionLeft"></a>
    <li>captionLeft<br>
      Anzeigen der Legende auf der linken Seite. &Uuml;berholt, wird
      automatisch nach captionPos konvertiert.
      </li><br>

    <a name="captionPos"></a>
    <li>captionPos<br>
      right - Anzeigen der Legende auf der rechten Seite (default)<br>
      left - Anzeigen der Legende auf der linken Seite<br>
      auto - Anzeigen der Labels der Legende auf der linken oder rechten Seite
      je nach Achsenzugeh&ouml;rigkeit<br>
      </li><br>

    <li><a href="#endPlotNow">endPlotNow</a></li><br>
    <li><a href="#endPlotToday">endPlotToday</a></li><br>

    <a name="fixedoffset"></a>
    <li>fixedoffset &lt;nTage&gt;<br>
      Verschiebt den Plot-Offset um einen festen Wert (in Tagen). 
      </li><br>

    <a name="fixedrange"></a>
    <li>fixedrange [offset]<br>
      Erste Alternative:<br>
      Enth&auml;lt zwei Zeit-Spezifikationen in der Schreibweise YYYY-MM-DD,
      getrennt durch ein Leerzeichen. scrollen der Zeitachse ist nicht
      m&ouml;glich, es wird z.B. verwendet, um sich die Daten verschiedener
      Jahre auf eine Seite anzusehen.<br><br>

      Zweite Alternative:<br>
      Wenn der Wert entweder hour, day, &lt;N&gt;days, week, month oder year
      lautet, kann der Zoom-Level f&uuml;r dieses SVG unabh&auml;ngig vom
      User-spezifischen Zoom eingestellt werden. Diese Einstellung ist
      n&uuml;tzlich f&uuml;r mehrere Plots auf einer Seite: Eine Grafik ist mit
      dem Standard-Zoom am aussagekr&auml;ftigsten, die anderen mit einem Zoom
      &uuml;ber eine Woche. Der optionale ganzzahlige Parameter [offset] setzt
      ein anderes Zeitintervall (z.B. letztes Jahr: <code>fixedrange year
      -1</code>, vorgestern:<code> fixedrange day -2</code>).
      </li><br>

    <a name="label"></a>
    <li>label<br>
      Eine Liste, bei der die einzelnen Werte mit einem zweifachen Doppelpunkt
      voneinander getrennt werden. Diese Liste wird verwendet um die &lt;L#&gt;
      Zeichenfolgen in der .gplot-Datei zu ersetzen. Dabei steht das # f&uuml;r
      eine laufende Ziffer beginnend mit 1 (&lt;L1&gt;, &lt;L2&gt;, usw.).
      Jeder Wert wird als Perl-Ausdruck bewertet, deshalb hat man Zugriff z.B.
      auf die hinterlegten Funktionen. <br><br>

      Egal, ob es sich bei der Plotart um gnuplot-scroll(-svg) oder SVG
      handelt, es k&ouml;nnen ebenfalls die Werte der individuellen Kurve
      f&uuml;r min, max, mindate, maxdate, avg, cnt, sum, currval (letzter
      Wert) und currdate (letztes Datum) durch Zugriff der entsprechenden Werte
      &uuml;ber das data Hash verwendet werden. Siehe untenstehendes
      Beispiel:<br>
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
      Die Werte minAll und maxAll (die das Minimum/Maximum aller Werte
      repr&auml;sentieren) sind ebenfals im data hash vorhanden.
      <br>&Uuml;berholt, wird durch das plotReplace Attribut abgel&ouml;st.
      </li><br>

    <li><a href="#nrAxis">nrAxis</a></li><br>

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
      &Uuml;berholt, wird durch das plotReplace Attribut abgel&ouml;st.
    </li><br>

    <li><a href="#plotmode">plotmode</a></li><br>

    <a name="plotReplace"></a>
    <li>plotReplace<br>
      Leerzeichen getrennte Liste von Name=Wert Paaren. Wert kann Leerzeichen
      enthalten, falls es in "" oder {} eingeschlossen ist. Wert wird als
      perl-Ausdruck ausgewertet, falls es in {} eingeschlossen ist.
      <br>
      In der .gplot Datei werden &lt;Name&gt; Zeichenketten durch den
      zugehoerigen Wert ersetzt, die Auswertung von {} Ausdr&uuml;cken erfolgt
      <i>nach</i> dem die Daten ausgewertet wurden, d.h. man kann hier
      $data{min1},etc verwenden.
      <br>
      Bei %Name% erfolgt die Ersetzung <i>vor</i> der Datenauswertung, das kann
      man verwenden, um Parameter f&uuml;r die Auswertung zu ersetzen.
    </li><br>

    <li><a href="#plotsize">plotsize</a></li><br>
    <li><a href="#plotWeekStartDay">plotWeekStartDay</a></li><br>

    <a name="startDate"></a>
    <li>startDate<br>
      Setzt das Startdatum f&uuml;r den Plot. Wird f&uuml;r Demo-Installationen
      verwendet.
      </li><br>

    <a name="title"></a>
    <li>title<br>
      Eine besondere Form der &Uuml;berschrift (siehe oben), bei der die
      Zeichenfolge &lt;TL&gt; in der .gplot-Datei ersetzt wird.
      Standardm&auml;&szlig;ig wird als &lt;TL&gt; der Dateiname des Logfiles
      eingesetzt.
      <br>&Uuml;berholt, wird durch das plotReplace Attribut abgel&ouml;st.
      </li><br>

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
    <li>Falls Range der Form {...} entspricht, dann wird sie als Perl -
      Expression ausgewertet. Das Ergebnis muss in der Form [min:max] sein.
      </li>
  </ul>
  Die sichtbarkeit des  Plot-Editors kann mit dem FHEMWEB Attribut <a
  href="#ploteditor">ploteditor</a> konfiguriert werden.
  <br>
</ul>

=end html_DE

=cut
