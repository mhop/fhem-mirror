##############################################
# $Id$
package main;

use strict;
use warnings;
use vars qw($FW_subdir);  # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
use vars qw($FW_ME);      # webname (default is fhem), needed by 97_GROUP
use vars qw(%FW_hiddenroom); # hash of hidden rooms, used by weblink
use vars qw($FW_plotmode);# Global plot mode (WEB attribute), used by weblink
use vars qw($FW_plotsize);# Global plot size (WEB attribute), used by weblink
use vars qw(%FW_pos);     # scroll position
use vars qw($FW_gplotdir);# gplot directory for web server: the first
use vars qw(%FW_webArgs); # all arguments specified in the GET

use IO::File;

#####################################
sub
weblink_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "weblink_Define";
  $hash->{AttrList} = "fixedrange plotmode plotsize label ".
                        "title htmlattr plotfunction";
  $hash->{SetFn}    = "weblink_Set";
  $hash->{FW_summaryFn} = "weblink_FwFn";
  $hash->{FW_detailFn}  = "weblink_FwFn";
  $hash->{FW_atPageEnd} = 1;
  $data{FWEXT}{"/weblinkDetails"}{FUNC} = "weblink_WriteGplot";
}


#####################################
sub
weblink_Define($$)
{
  my ($hash, $def) = @_;
  my ($type, $name, $wltype, $link) = split("[ \t]+", $def, 4);
  my %thash = ( link=>1, fileplot=>1, dbplot=>1, image=>1, iframe=>1, htmlCode=>1, cmdList=>1 );
  
  if(!$link || !$thash{$wltype}) {
    return "Usage: define <name> weblink [" .
                join("|",sort keys %thash) . "] <arg>";
  }
  $hash->{WLTYPE} = $wltype;
  $hash->{LINK} = $link;
  $hash->{STATE} = "initial";
  return undef;
}

sub
weblink_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};
  return "no set argument specified" if(int(@a) < 2);
  my %sets = (copyGplotFile=>0);
  
  my $cmd = $a[1];
  return "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets)
    if(!defined($sets{$cmd}));
  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 2);

  if($cmd eq "copyGplotFile") {
    return "type is not fileplot" if($hash->{WLTYPE} ne "fileplot");
    my @a = split(":", $hash->{LINK});
    my $srcName = "$FW_gplotdir/$a[1].gplot";
    $a[1] = $hash->{NAME};
    my $dstName = "$FW_gplotdir/$a[1].gplot";
    $hash->{LINK} = join(":", @a);
    return "this is already a unique gplot file" if($srcName eq $dstName);
    $hash->{DEF} = "$hash->{WLTYPE} $hash->{LINK}";
    open(SFH, $srcName) || return "Can't open $srcName: $!";
    open(DFH, ">$dstName") || return "Can't open $dstName: $!";
    while(my $l = <SFH>) {
      print DFH $l;
    }
    close(SFH); close(DFH);
  }
  return undef;
}


#####################################
# FLOORPLAN compat
sub
FW_showWeblink($$$$)
{
  my ($d,undef,undef,$buttons) = @_;

  if($buttons !~ m/HASH/) {
    my %h = (); $buttons = \%h;
  }
  FW_pO(weblink_FwFn(undef, $d, "", $buttons));
  return $buttons;
}


##################
sub
weblink_FwDetail($@)
{
  my ($d, $text)= @_;
  return "" if(AttrVal($d, "group", ""));
  my $alias= AttrVal($d, "alias", $d);

  my $ret = "<br>";
  $ret .= "$text " if($text);
  $ret .= FW_pHPlain("detail=$d", $alias) if(!$FW_subdir);
  $ret .= "<br>";
  return $ret;
}

sub
weblink_FwFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  my $wltype = $hash->{WLTYPE};
  my $ret = "";

  my $attr = AttrVal($d, "htmlattr", "");
  if($wltype eq "htmlCode") {
    $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/);
    $ret = $link;

  } elsif($wltype eq "link") {
    $ret = "<a href=\"$link\" $attr>$d</a>"; # no FW_pH, open extra browser

  } elsif($wltype eq "image") {
    $ret = "<img src=\"$link\" $attr><br>" . 
           weblink_FwDetail($d);

  } elsif($wltype eq "iframe") {
    $ret = "<iframe src=\"$link\" $attr>Iframes disabled</iframe>" .
           weblink_FwDetail($d);

  } elsif($wltype eq "cmdList") {

    my @lines = split(" ", $link);
    my $row = 0;
    my $ret = "<table>";
    $ret .= "<tr><td><div class=\"devType\"><a href=\"/fhem?detail=$d\">".AttrVal($d, "alias", $d)."</div></td></tr>";
    $ret .= "<tr><td><table class=\"block wide\">";
    foreach my $line (@lines) {
      my @args = split(":", $line, 3);

      $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
      $ret .= "<td><a href=\"/fhem?cmd=$args[2]\"><div class=\col1\"><img src=\"/fhem/icons/$args[0]\" width=19 height=19 align=\"center\" alt=\"$args[0]\" title=\"$args[0]\"> $args[1]</div></a></td></td>";
      $ret .= "</tr>";
    }
    $ret .= "</table></td></tr>";
    $ret .= "</table><br>";

    return $ret;

  } elsif($wltype eq "fileplot" || $wltype eq "dbplot" ) {

    # plots navigation buttons
    if((!$pageHash || !$pageHash->{buttons}) &&
       ($wltype eq "fileplot" || $wltype eq "dbplot") &&
       AttrVal($d, "fixedrange", "x") !~ m/^[ 0-9:-]*$/) {

      $ret .= FW_zoomLink("zoom=-1", "Zoom-in", "zoom in");
      $ret .= FW_zoomLink("zoom=1",  "Zoom-out","zoom out");
      $ret .= FW_zoomLink("off=-1",  "Prev",    "prev");
      $ret .= FW_zoomLink("off=1",   "Next",    "next");
      $pageHash->{buttons} = 1 if($pageHash);
      $ret .= "<br>";
    }

    my @va = split(":", $link, 3);
    if($wltype eq "fileplot" &&
            (@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile})) {
      $ret .= weblink_FwDetail($d, "Broken definition ");

    } elsif ($wltype eq "dbplot" && (@va != 2 || !$defs{$va[0]})) {
      $ret .= weblink_FwDetail($d, "Broken definition ");

    } else {
      if(defined($va[2]) && $va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
      }

      if ($wltype eq "dbplot") {
        $va[2] = "-";
      }

      my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);

      my $arg="$FW_ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
      if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
        my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
        $ret .= "<embed src=\"$arg\" type=\"image/svg+xml\" " .
              "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

      } else {
        $ret .= "<img src=\"$arg\"/>";
      }

      if(!$pageHash) {
        $ret .= wl_PEdit($FW_wname,$d,$room,$pageHash)
                if($wltype eq "fileplot" && $FW_plotmode eq "SVG");
        $ret .= "<br>";

      } else {
        $ret .= weblink_FwDetail($d) if(!$FW_hiddenroom{detail});

      }

    }
  }
  return $ret;
}

sub
wl_cb($$$)
{
  my ($v,$t,$c) = @_;
  $c = ($c ? " checked" : "");
  return "<td>$t&nbsp;<input type=\"checkbox\" name=\"$v\" value=\"$v\"$c></td>";
}

sub
wl_txt($$$$)
{
  my ($v,$t,$c,$sz) = @_;
  $c = "" if(!defined($c));
  $c =~ s/"/\&quot;/g;
  return "$t&nbsp;<input type=\"text\" name=\"$v\" size=\"$sz\" ".
                "value=\"$c\"/>";
}

sub
wl_sel($$$@)
{
  my ($v,$l,$c,$fnData) = @_;
  my @al = split(",",$l);
  $c =~ s/\\x3a/:/g if($c);
  return FW_select($v,$v,\@al,$c, "set", $fnData);
}

sub
wl_getRegFromFile($)
{
  my ($fName) = @_;
  my $fh = new IO::File $fName;
  if(!$fh) {
    Log 1, "$fName: $!";
    return (3, "NoFile", "NoFile");
  }
  $fh->seek(0, 2); # Go to the end
  my $sz = $fh->tell;
  $fh->seek($sz > 65536 ? $sz-65536 : 0, 0);
  my $data = <$fh>;
  my $maxcols = 0;
  my %h;
  while($data = <$fh>) {
    my @cols = split(" ", $data);
    $maxcols = @cols if(@cols > $maxcols);
    $cols[2] = "*" if($cols[2] =~ m/^[-\.\d]+$/);
    $h{"$cols[1].$cols[2]"} = $data;
    $h{"$cols[1].*"} = "" if($cols[2] ne "*");
  }
  $fh->close();
  return ($maxcols+1, 
                join(",", sort keys %h),
                join("<br>", grep /.+/,map { $h{$_} } sort keys %h)),
  close(FH);
}

############################
# gnuplot file "editor"
sub
wl_PEdit($$$$)
{
  my ($FW_wname,$d,$room,$pageHash) = @_;
  my @a = split(":", $defs{$d}{LINK});
  my $gp = "$FW_gplotdir/$a[1].gplot";
  my $file = $defs{$a[0]}{currentlogfile};
  
  my ($err, $cfg, $plot, $flog) = FW_readgplotfile($d, $gp, $file);
  my %conf = SVG_digestConf($cfg, $plot);

  my $ret .= "<br><form autocomplete=\"off\" action=\"$FW_ME/weblinkDetails\">";
  $ret .= FW_hidden("detail", $d);
  $ret .= FW_hidden("gplotName", $gp);
  $ret .= "<table class=\"block wide\">";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Plot title</td>";
  $ret .= "<td>".wl_txt("title", "", $conf{title}, 32)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"odd\">";
  $ret .= "<td>Y-Axis label</td>";
  $conf{ylabel} =~ s/"//g if($conf{ylabel});
  $ret .= "<td>".wl_txt("ylabel", "left", $conf{ylabel}, 16)."</td>";
  $conf{y2label} =~ s/"//g if($conf{y2label});
  $ret .= "<td>".wl_txt("y2label","right", $conf{y2label}, 16)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Grid aligned</td>";
  $ret .= wl_cb("gridy", "left", $conf{hasygrid});
  $ret .= wl_cb("gridy2","right",$conf{hasy2grid});
  $ret .= "</tr>";
  $ret .= "<tr class=\"odd\">";
  $ret .= "<td>Range as [min:max]</td>";
  $ret .= "<td>".wl_txt("yrange", "left", $conf{yrange}, 16)."</td>";
  $ret .= "<td>".wl_txt("y2range", "right", $conf{y2range}, 16)."</td>";
  $ret .= "</tr>";
  $ret .= "<tr class=\"even\">";
  $ret .= "<td>Tics as (\"Txt\" val, ...)</td>";
  $ret .= "<td>".wl_txt("ytics", "left", $conf{ytics}, 16)."</td>";
  $ret .= "<td>".wl_txt("y2tics","right", $conf{y2tics}, 16)."</td>";
  $ret .= "</tr>";

  $ret .= "<tr class=\"odd\"><td>Diagramm label</td>";
  $ret .= "<td>Input:Column,Regexp,DefaultValue,Function</td>";
  $ret .=" <td>Y-Axis,Plot-Type,Style,Width</td></tr>";

  my ($colnums, $colregs, $coldata) = wl_getRegFromFile($file);
  $colnums = join(",", 3..$colnums);
  my $max = @{$conf{lAxis}}+1;
  $max = 8 if($max > 8);
  $max = 1 if(!$conf{lTitle}[0]);
  my $r = 0;
  for($r=0; $r < $max; $r++) {
    $ret .= "<tr class=\"".(($r&1)?"odd":"even")."\"><td>";
    $ret .= wl_txt("title_${r}", "", $conf{lTitle}[$r], 12);
    $ret .= "</td><td>";
    my @f = split(":", ($flog->[$r] ? $flog->[$r] : ":::"), 4);
    $ret .= wl_sel("cl_${r}", $colnums, $f[0]);
    $ret .= wl_sel("re_${r}", $colregs, $f[1]);
    $ret .= wl_txt("df_${r}", "", $f[2], 1);
    $ret .= wl_txt("fn_${r}", "", $f[3], 6);

    $ret .= "</td><td>";
    my $v = $conf{lAxis}[$r];
    $ret .= wl_sel("axes_${r}", "left,right", 
                    ($v && $v eq "x1y1") ? "left" : "right");
    $ret .= wl_sel("type_${r}", "lines,points,steps,fsteps,histeps,bars",
                    $conf{lType}[$r]);
    my $ls = $conf{lStyle}[$r]; 
    if($ls) {
      $ls =~ s/class=//g;
      $ls =~ s/"//g; 
    }
    $ret .= wl_sel("style_${r}", "l0,l1,l2,l3,l4,l5,l6,l7,l8,".
                    "l0fill,l1fill,l2fill,l3fill,l4fill,l5fill,l6fill", $ls);
    my $lw = $conf{lWidth}[$r]; 
    if($lw) {
      $lw =~ s/.*stroke-width://g;
      $lw =~ s/"//g; 
    }
    $ret .= wl_sel("width_${r}", "0.2,0.5,1,1.5,2,3,4", ($lw ? $lw : 1));
    $ret .= "</td></tr>";
  }
  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= "Example lines for input:<br>$coldata</td></tr>";

  $ret .= "<tr class=\"".(($r++&1)?"odd":"even")."\"><td colspan=\"3\">";
  $ret .= FW_submit("submit", "Write .gplot file")."</td></tr>";

  $ret .= "</table></form>";
}

sub
weblink_WriteGplot($)
{
  my ($arg) = @_;
  FW_digestCgi($arg);

  my $hasTl;
  for(my $i=0; $i <= 8; $i++) {
    $hasTl = 1 if($FW_webArgs{"title_$i"});
  }
  return if(!$hasTl);

  my $fName = $FW_webArgs{gplotName};
  return if(!$fName);
  if(!open(FH, ">$fName")) {
    Log 1, "weblink_WriteGplot: Can't write $fName";
    return;
  }
  print FH "# Created by FHEMWEB, ".TimeNow()."\n";
  print FH "set terminal png transparent size <SIZE> crop\n";
  print FH "set output '<OUT>.png'\n";
  print FH "set xdata time\n";
  print FH "set timefmt \"%Y-%m-%d_%H:%M:%S\"\n";
  print FH "set xlabel \" \"\n";
  print FH "set title '$FW_webArgs{title}'\n";
  print FH "set ytics ".$FW_webArgs{ytics}."\n";
  print FH "set y2tics ".$FW_webArgs{y2tics}."\n";
  print FH "set grid".($FW_webArgs{gridy}  ? " ytics" :"").
                      ($FW_webArgs{gridy2} ? " y2tics":"")."\n";
  print FH "set ylabel \"$FW_webArgs{ylabel}\"\n";
  print FH "set y2label \"$FW_webArgs{y2label}\"\n";
  print FH "set yrange $FW_webArgs{yrange}\n" if($FW_webArgs{yrange});
  print FH "set y2range $FW_webArgs{yrange}\n" if($FW_webArgs{y2range});
  print FH "\n";

  my @plot;
  for(my $i=0; $i <= 8; $i++) {
    next if(!$FW_webArgs{"title_$i"});
    my $re = $FW_webArgs{"re_$i"};
    $re = "" if(!defined($re));
    $re =~ s/:/\\x3a/g;
    print FH "#FileLog ". $FW_webArgs{"cl_$i"} .":$re:".
                          $FW_webArgs{"df_$i"} .":".
                          $FW_webArgs{"fn_$i"} ."\n";
    push @plot, "\"<IN>\" using 1:2 axes ".
                ($FW_webArgs{"axes_$i"} eq "right" ? "x1y2" : "x1y1").
                " title '".$FW_webArgs{"title_$i"} ."'".
                " ls "    .$FW_webArgs{"style_$i"} .
                " lw "    .$FW_webArgs{"width_$i"} .
                " with "  .$FW_webArgs{"type_$i"};
  }
  print FH "\n";
  print FH "plot ".join(",\\\n     ", @plot)."\n";
  close(FH);

  #foreach my $k (sort keys %FW_webArgs) {
  #  Log 1, "$k: $FW_webArgs{$k}";
  #}
}

1;

=pod
=begin html

<a name="weblink"></a>
<h3>weblink</h3>
<ul>
  <a name="weblinkdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; weblink [link|fileplot|dbplot|image|iframe|htmlCode|cmdList]
                &lt;argument&gt;</code>
    <br><br>
    This is a placeholder used with webpgm2 to be able to integrate links
    into it, and to be able to put more than one gnuplot/SVG picture on one
    page.  It has no set or get methods.

    Examples:
    <ul>
      <code>define homepage weblink link http://www.fhem.de</code><br>
      <code>define webcam_picture weblink image http://w.x.y.z/current.jpg</code><br>
      <code>define interactive_webcam weblink iframe http://w.x.y.z/webcam.cgi</code><br>
      <code>define hr weblink htmlCode &lt;hr&gt</code><br>
      <code>define w_Frlink weblink htmlCode { WeatherAsHtml("w_Frankfurt") }</code><br>
      <code>define MyPlot weblink fileplot &lt;logdevice&gt;:&lt;gnuplot-file&gt;:&lt;logfile&gt;</code><br>
      <code>define MyPlot weblink dbplot &lt;logdevice&gt;:&lt;gnuplot-file&gt;</code><br>
      <code>define systemCommands weblink cmdList pair:Pair:set+cul2+hmPairForSec+60 restart:Restart:shutdown+restart update:UpdateCheck:update+check</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>Normally you won't have to define fileplot weblinks manually, as
          FHEMWEB makes it easy for you, just plot a logfile (see
          <a href="#logtype">logtype</a>) and convert it to weblink.  Now you
          can group these weblinks by putting them into rooms.  If you convert
          the current logfile to a weblink, it will always refer to the current
          file, even if its name changes regularly (and not the one you
          originally specified).</li>
      <li>For cmdList &lt;argument&gt; consist of a list of space separated icon:label:cmd triples.</li>
	</ul>
  </ul>

  <a name="weblinkset"></a>
  <b>Set</b>
  <ul>
    <li>copyGplotFile<br>
      Only applicable to fileplot type weblinks.<br>
      Copy the currently specified gplot file to a new file, which is named
      after the weblink (existing files will be overwritten), in order to be
      able to modify it locally without the problem of being overwritten by
      update. The weblink definition will be updated.
    </li>
  </ul><br>

  <a name="weblinkget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="weblinkattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="htmlattr"></a>
    <li>htmlattr<br>
      HTML attributes to be used for link, image and iframe type of links. E.g.:<br>
      <ul>
        <code>
        define yw weblink wl_im1 iframe http://weather.yahooapis.com/forecastrss?w=650272&u=c<br>
        attr yw weblink htmlattr width="480" height="560"<br>
        </code>
      </ul>
      </li>
      <br>
    <li><a href="#fixedrange">fixedrange</a></li>
    <li><a href="#plotsize">plotsize</a></li>
    <li><a href="#plotmode">plotmode</a></li>
    <a name="label"></a>
    <li>label<br>
      Double-Colon separated list of values. The values will be used to replace
      &lt;L#&gt; type of strings in the .gplot file, with # beginning at 1
      (&lt;L1&gt;, &lt;L2&gt;, etc.). Each value will be evaluated as a perl
      expression, so you have access e.g. to the Value functions.<br><br>

      If the plotmode is gnuplot-scroll or SVG, you can also use the min, max,
      avg, cnt, sum, currval (last value) and currdate (last date) values of the
      individual curves, by accessing the corresponding values from the data
      hash, see the example below:<br>

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
            with: attr <weblinkdevice> plotfunction "4:IR\x3a:0:"<br>
            instead of<br>  
            #FileLog 4:IR\x3a:0:
        </li>
        <li>#DbLog <SPEC1><br>
            with: attr <weblinkdevice> plotfunction "Garage_Raumtemp:temperature::"<br>
            instead of<br>
            #DbLog Garage_Raumtemp:temperature::
        </li>
      </ul>
    </li>

  </ul>
  <br>

</ul>

=end html
=cut
