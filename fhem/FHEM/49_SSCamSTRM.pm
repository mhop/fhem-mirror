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
# 1.2.0  20.06.2018    running stream as human readable entry for SSCamSTRM-Device
# 1.1.0  16.06.2018    attr hideDisplayName regarding to Forum #88667
# 1.0.1  14.06.2018    commandref revised
# 1.0.0  14.06.2018    switch to longpoll refresh
# 0.4    13.06.2018    new attribute "noDetaillink" (deleted in V1.0.0)
# 0.3    12.06.2018    new attribute "forcePageRefresh"
# 0.2    11.06.2018    check in with SSCam 5.0.0
# 0.1    10.06.2018    initial Version


package main;

use strict;
use warnings;

my $SSCamSTRMVersion = "1.2.0";

################################################################
sub SSCamSTRM_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}              = "SSCamSTRM_Define";
  $hash->{AttrList}           = "disable:1,0 forcePageRefresh:1,0 htmlattr hideDisplayName:1,0 ";
  $hash->{FW_summaryFn}       = "SSCamSTRM_FwFn";
  $hash->{FW_detailFn}        = "SSCamSTRM_FwFn";
  $hash->{AttrFn}             = "SSCamSTRM_Attr";
  $hash->{FW_hideDisplayName} = 1;        # Forum 88667
  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;            # wenn 1 -> kein Longpoll ohne informid in HTML-Tag
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
  
  $attr{$name}{comment} = "when using the device in a Dashboard, set \"attr $name alias <span></span>\" ";
  
  readingsSingleUpdate($hash,"state", "initialized", 1);      # Init für "state" 
  
return undef;
}

################################################################
sub SSCamSTRM_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
		$val = ($do == 1 ? "Stream-device of \"$hash->{PARENT}\" disabled" : "initialized");
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }

return undef;
}

################################################################
sub SSCamSTRM_FwFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  
  return undef if(IsDisabled($d));

  $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/s);
  my $show = $defs{$hash->{PARENT}}->{HELPER}{ACTSTRM};
  $show = $show?"($show)":"";

  my $alias = AttrVal($d, "alias", $d);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = "<a href=\"/fhem?detail=$d\">$alias</a>"; 
  
  my $ret = "";
  $ret   .= "<span>$dlink $show</span><br>"  if(!AttrVal($d,"hideDisplayName",0));
  $ret   .= $link;

return $ret;
}

1;

=pod
=item summary    define a Streaming device by SSCam module
=item summary_DE Erstellung eines Streaming-Device durch das SSCam-Modul
=begin html

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>
<br>
The module SSCamSTRM is a special device module synchronized to the SSCam module. It is used for definition of
Streaming-Devices. <br>
Dependend of the Streaming-Device state, different buttons are provided to start actions:
  <ul>   
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td> MJPEG           </td><td>- starts a MJPEG Livestream </td></tr>
      <tr><td> HLS             </td><td>- starts HLS (HTTP Live Stream) </td></tr>
      <tr><td> Last Record     </td><td>- playback the last recording as iFrame </td></tr>
      <tr><td> Last Rec H.264  </td><td>- playback the last recording if available as H.264 </td></tr>
      <tr><td> Last Rec MJPEG  </td><td>- playback the last recording if available as MJPEG </td></tr>
      <tr><td> Last SNAP       </td><td>- show the last snapshot </td></tr>
      <tr><td> Start Recording </td><td>- starts an endless recording </td></tr>
      <tr><td> Stop Recording  </td><td>- stopps the recording </td></tr>
      <tr><td> Take Snapshot   </td><td>- take a snapshot </td></tr>
      <tr><td> Switch off      </td><td>- stops a running playback </td></tr>
    </table>
   </ul>     
   <br>

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
  <br><br>
  
  <ul>
  <ul>

    <li><b>disable</b><br>
      deactivates the device definition
    </li>
    <br>
    
    <li><b>forcePageRefresh</b><br>
      The attribute is evaluated by SSCam. <br>
      If set, a reload of all browser pages with active FHEMWEB-connections will be enforced. 
      This may be helpful if problems with longpoll are appear.       
    </li>
    <br>
    
    <li><b>hideDisplayName</b><br>
      hide the device/alias name (link to detail view)     
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      HTML attributes to be used for Streaming device e.g.: <br><br>
      <ul>
        <code>
        attr &lt;name&gt; htmlattr width="480" height="560" <br>
        </code>
      </ul>
    </li>
  
  </ul>
  </ul>
  
</ul>

=end html
=begin html_DE

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>

<br>
Das Modul SSCamSTRM ist ein mit SSCam abgestimmtes Gerätemodul zur Definition von Streaming-Devices. <br>
Abhängig vom Zustand des Streaming-Devices werden zum Start von Aktionen unterschiedliche Drucktasten angeboten:
  <ul>   
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td> MJPEG           </td><td>- Startet MJPEG Livestream </td></tr>
      <tr><td> HLS             </td><td>- Startet HLS (HTTP Live Stream) </td></tr>
      <tr><td> Last Record     </td><td>- spielt die letzte Aufnahme als iFrame </td></tr>
      <tr><td> Last Rec H.264  </td><td>- spielt die letzte Aufnahme wenn als H.264 vorliegend </td></tr>
      <tr><td> Last Rec MJPEG  </td><td>- spielt die letzte Aufnahme wenn als MJPEG vorliegend </td></tr>
      <tr><td> Last SNAP       </td><td>- zeigt den letzten Snapshot </td></tr>
      <tr><td> Start Recording </td><td>- startet eine Endlosaufnahme </td></tr>
      <tr><td> Stop Recording  </td><td>- stoppt eine Aufnahme </td></tr>
      <tr><td> Take Snapshot   </td><td>- löst einen Schnappschuß aus </td></tr>
      <tr><td> Switch off      </td><td>- stoppt eine laufende Wiedergabe </td></tr>
    </table>
   </ul>     
   <br>

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
  <br><br>
  
  <ul>
  <ul>
  
    <li><b>disable</b><br>
      aktiviert/deaktiviert das Device
    </li>
    <br>
    
    <li><b>forcePageRefresh</b><br>
      Das Attribut wird durch SSCam ausgewertet. <br>
      Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen bei bestimmten Aktionen erzwungen. 
      Das kann hilfreich sein, falls es mit Longpoll Probleme geben sollte.
      eingefügt ist.       
    </li>
    <br>
    
    <li><b>hideDisplayName</b><br>
      verbirgt den Device/Alias-Namen (Link zur Detailansicht)     
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      HTML-Attribute zur Darstellungsänderung des SSCam Streaming Device z.B.: <br><br>
      <ul>
        <code>
        attr &lt;name&gt; htmlattr width="480" height="560" <br>
        </code>
      </ul>
    </li>

  </ul>
  </ul>
  
</ul>

=end html_DE
=cut
