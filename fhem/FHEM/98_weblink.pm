##############################################
# $Id$
package main;

use strict;
use warnings;
use vars qw($FW_subdir);  # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
use IO::File;

#####################################
sub
weblink_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "weblink_Define";
  $hash->{AttrList} = "htmlattr";
  $hash->{FW_summaryFn} = "weblink_FwFn";
  $hash->{FW_detailFn}  = "weblink_FwFn";
  $hash->{FW_atPageEnd} = 1;
}


#####################################
sub
weblink_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $wltype, $link) = split("[ \t]+", $def, 4);
  my %thash = ( link=>1, image=>1, iframe=>1, htmlCode=>1, 
                cmdList=>1,
                fileplot=>1, dbplot=>1);
  
  if(!$link || !$thash{$wltype}) {
    return "Usage: define <name> weblink [" .
                join("|",sort keys %thash) . "] <arg>";
  }

  if($wltype eq "fileplot" || $wltype eq "dbplot") {
    Log3 $name, 1, "Converting weblink $name ($wltype) to SVG";
    my $newm = LoadModule("SVG");
    return "Cannot load module SVG" if($newm eq "UNDEFINED");
    $hash->{TYPE} = "SVG";
    $hash->{DEF} = $link;
    return CallFn($name, "DefFn", $hash, "$name $type $link");
  }

  $hash->{WLTYPE} = $wltype;
  $hash->{LINK} = $link;
  $hash->{STATE} = "initialized";
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
    my $row = 1;
    $ret = "<table>";
    $ret .= "<tr><td><div class=\"devType\"><a href=\"/fhem?detail=$d\">".AttrVal($d, "alias", $d)."</a></div></td></tr>";
    $ret .= "<tr><td><table class=\"block wide\">";
    foreach my $line (@lines) {
      my @args = split(":", $line, 3);

      $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
      $ret .= "<td><a href=\"/fhem?cmd=$args[2]\"><div class=\col1\"><img src=\"/fhem/icons/$args[0]\" width=19 height=19 align=\"center\" alt=\"$args[0]\" title=\"$args[0]\"> $args[1]</div></a></td></td>";
      $ret .= "</tr>";
    }
    $ret .= "</table></td></tr>";
    $ret .= "</table><br>";

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
    <code>define &lt;name&gt; weblink [link|image|iframe|htmlCode|cmdList]
                &lt;argument&gt;</code>
    <br><br>
    This is a placeholder device used with FHEMWEB to be able to add user
    defined links.
    Examples:
    <ul>
      <code>define homepage weblink link http://www.fhem.de</code><br>
      <code>define webcam_picture weblink image http://w.x.y.z/current.jpg</code><br>
      <code>define interactive_webcam weblink iframe http://w.x.y.z/webcam.cgi</code><br>
      <code>define hr weblink htmlCode &lt;hr&gt</code><br>
      <code>define w_Frlink weblink htmlCode { WeatherAsHtml("w_Frankfurt") }</code><br>
      <code>define systemCommands weblink cmdList pair:Pair:set+cul2+hmPairForSec+60 restart:Restart:shutdown+restart update:UpdateCheck:update+check</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>For cmdList &lt;argument&gt; consist of a list of space separated icon:label:cmd triples.</li>
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
      HTML attributes to be used for link, image and iframe type of links.
      E.g.:<br>
      <ul>
        <code>
        define yw weblink wl_im1 iframe http://weather.yahooapis.com/forecastrss?w=650272&u=c<br>
        attr yw weblink htmlattr width="480" height="560"<br>
        </code>
      </ul></li>
  </ul>
  <br>

</ul>

=end html
=cut
