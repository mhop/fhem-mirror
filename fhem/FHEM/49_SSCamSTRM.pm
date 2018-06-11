########################################################################################################################
# $Id$
#########################################################################################################################
#       49_SSCamSTRM.pm
#
#       (c) 2018 by Heiko Maaz
#       forked from 98_weblink.pm by Rudolf König
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module is used by module 49_SSCam to create Streaming devices.
#       It can't be used without any SSCam-Device.
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################
#  Versions History:
# 
# 0.2    11.06.2018    check in with SSCam 5.0.0
# 0.1    10.06.2018    initial Version


package main;

use strict;
use warnings;
use vars qw($FW_subdir);  # Sub-path in URL for extensions, e.g. 95_FLOORPLAN

my $SSCamSTRMVersion = "0.2";

################################################################
sub SSCamSTRM_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}        = "SSCamSTRM_Define";
  $hash->{AttrList}     = "disable:0,1 htmlattr ";
  $hash->{FW_summaryFn} = "SSCamSTRM_FwFn";
  $hash->{FW_detailFn}  = "SSCamSTRM_FwFn";
  $hash->{FW_atPageEnd} = 1;
}


################################################################
sub SSCamSTRM_Define($$) {
  my ($hash, $def) = @_;
  my ($name, $type, $link) = split("[ \t]+", $def, 3);
  
  if(!$link) {
    return "Usage: define <name> SSCamSTRM <arg>";
  }

  my $arg = (split("[()]",$link))[1];
  $arg   =~ s/'//g;
  ($hash->{PARENT},$hash->{MODEL}) = ((split(",",$arg))[0],(split(",",$arg))[2]);
  
  $hash->{VERSION} = $SSCamSTRMVersion;
  $hash->{LINK}    = $link;
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state", "initialized");           # Init für "state" 
  readingsEndUpdate($hash,1);
  
return undef;
}

################################################################
sub SSCamSTRM_FwDetail($@) {
  my ($d, $text, $nobr)= @_;
  return "" if(AttrVal($d, "group", ""));
  my $alias = AttrVal($d, "alias", $d);

  my $ret = ($nobr ? "" : "<br>");
  $ret   .= "$text " if($text);
  $ret   .= FW_pHPlain("detail=$d", $alias) if(!$FW_subdir);
  $ret   .= "<br>";
  
return $ret;
}

################################################################
sub SSCamSTRM_FwFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  my $ret    = "";

  return "" if(IsDisabled($d));
  
  my $attr = AttrVal($d, "htmlattr", "");

    $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/s);
    $ret = $link;

return $ret;
}

1;

=pod
=item summary    define a Streaming device by SSCam module
=item summary_DE Erstellung eines Streaming-Device durch das SSCam-Modul
=begin html

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  
  <ul>
    A SSCam Streaming-device is defined by the SSCam "set &lt;name&gt; createStreamDev" command.
    Please refer to SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> command.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SSCamSTRMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SSCamSTRMattr"></a>
  <b>Attributes</b>
  
  <ul>
    <a name="htmlattr"></a>
    <li>htmlattr - HTML attributes to be used for Streaming device e.g.:<br>
      <ul>
        <code>
        attr &lt;name&gt; htmlattr width="480" height="560"<br>
        </code>
      </ul></li>

    <li>disable - deactivates the device definition</li>
  </ul>
  <br>
  
</ul>

=end html
=begin html_DE

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  
  <ul>
    Ein SSCam Streaming-Device wird durch den SSCam Befehl "set &lt;name&gt; createStreamDev" erstellt.
    Siehe auch die Beschreibung zum SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> Befehl.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SSCamSTRMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="SSCamSTRMattr"></a>
  <b>Attributes</b>
  
  <ul>
    <a name="htmlattr"></a>
    <li>htmlattr - HTML-Attribute zur Darstellungänderung des SSCam Streaming Device z.B.:<br>
      <ul>
        <code>
        attr &lt;name&gt; htmlattr width="480" height="560"<br>
        </code>
      </ul></li>

    <li>disable - aktiviert/deaktiviert das Device</li>
  </ul>
  <br>
  
</ul>

=end html_DE
=cut
