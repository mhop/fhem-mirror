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

#####################################
sub
weblink_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "weblink_Define";
  $hash->{AttrList} = "fixedrange plotmode plotsize label ".
                        "title htmlattr plotfunction";
  $hash->{FW_summaryFn} = "weblink_FwFn";
  $hash->{FW_detailFn}  = "weblink_FwFn";
  $hash->{FW_atPageEnd} = 1;
}


#####################################
sub
weblink_Define($$)
{
  my ($hash, $def) = @_;
  my ($type, $name, $wltype, $link) = split("[ \t]+", $def, 4);
  my %thash = ( link=>1, fileplot=>1, dbplot=>1, image=>1, iframe=>1, htmlCode=>1 );
  
  if(!$link || !$thash{$wltype}) {
    return "Usage: define <name> weblink [" .
                join("|",sort keys %thash) . "] <arg>";
  }
  $hash->{WLTYPE} = $wltype;
  $hash->{LINK} = $link;
  $hash->{STATE} = "initial";
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

      $ret .= weblink_FwDetail($d) if(!$FW_hiddenroom{detail} && $pageHash);
    }
  }
  return $ret;
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
    <code>define &lt;name&gt; weblink [link|fileplot|dbplot|image|iframe|htmlCode]
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
	</ul>
  </ul>

  <a name="weblinkset"></a>
  <b>Set</b> <ul>N/A</ul><br>

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
