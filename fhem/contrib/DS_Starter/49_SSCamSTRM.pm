########################################################################################################################
# $Id: 49_SSCamSTRM.pm 19051 2019-03-27 22:10:48Z DS_Starter $
#########################################################################################################################
#       49_SSCamSTRM.pm
#
#       (c) 2018-2019 by Heiko Maaz
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

package main;

use strict;
use warnings;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1; 

# Versions History intern
our %SSCamSTRM_vNotesIntern = (
  "2.8.0"  => "09.09.2019  new attribute hideFooter ",
  "2.7.0"  => "15.07.2019  FTUI support, new attributes htmlattrFTUI, hideDisplayNameFTUI, ptzButtonSize, ptzButtonSizeFTUI ",
  "2.6.0"  => "21.06.2019  GetFn -> get <name> html ",
  "2.5.0"  => "27.03.2019  add Meta.pm support ",
  "2.4.0"  => "24.02.2019  support for \"genericStrmHtmlTag\" in streaming device MODEL generic ",
  "2.3.0"  => "04.02.2019  SSCamSTRM_Rename / SSCamSTRM_Copy added, Streaming device can now be renamed or copied ",
  "2.2.1"  => "19.12.2018  commandref revised ",
  "2.2.0"  => "13.12.2018  load sscam_hls.js, sscam_tooltip.js from pgm2 for HLS Streaming support and tooltips ",
  "2.1.0"  => "11.12.2018  switch \"popupStream\" from get to set ",
  "2.0.0"  => "09.12.2018  get command \"popupStream\" and attribute \"popupStreamFW\" ",
  "1.5.0"  => "02.12.2018  new attribute \"popupWindowSize\" ",
  "1.4.1"  => "31.10.2018  attribute \"autoLoop\" changed to \"autoRefresh\", new attribute \"autoRefreshFW\" ",
  "1.4.0"  => "29.10.2018  readingFnAttributes added ",
  "1.3.0"  => "28.10.2018  direct help for attributes, new attribute \"autoLoop\" ",
  "1.2.4"  => "27.10.2018  fix undefined subroutine &main::SSCam_ptzpanel (https://forum.fhem.de/index.php/topic,45671.msg850505.html#msg850505) ",
  "1.2.3"  => "03.07.2018  behavior changed if device is disabled ",
  "1.2.2"  => "26.06.2018  make changes for generic stream dev ",
  "1.2.1"  => "23.06.2018  no name add-on if MODEL is snapgallery ",
  "1.2.0"  => "20.06.2018  running stream as human readable entry for SSCamSTRM-Device ",
  "1.1.0"  => "16.06.2018  attr hideDisplayName regarding to Forum #88667 ",
  "1.0.1"  => "14.06.2018  commandref revised ",
  "1.0.0"  => "14.06.2018  switch to longpoll refresh ",
  "0.4.0"  => "13.06.2018  new attribute \"noDetaillink\" (deleted in V1.0.0) ",
  "0.3.0"  => "12.06.2018  new attribute \"forcePageRefresh\" ",
  "0.2.0"  => "11.06.2018  check in with SSCam 5.0.0 ",
  "0.1.0"  => "10.06.2018  initial Version "
);

# Standardvariablen und Forward-Declaration
sub SSCam_ptzpanel(@);
sub SSCam_StreamDev($$$;$);
sub SSCam_getclhash($;$$);

################################################################
sub SSCamSTRM_Initialize($) {
  my ($hash) = @_;

  my $fwd = join(",",devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized")); 
  
  $hash->{DefFn}              = "SSCamSTRM_Define";
  $hash->{SetFn}              = "SSCamSTRM_Set";
  $hash->{GetFn}              = "SSCamSTRM_Get";
  $hash->{AttrList}           = "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "disable:1,0 ". 
                                "forcePageRefresh:1,0 ".
                                "genericStrmHtmlTag ".
                                "htmlattr ".
                                "htmlattrFTUI ".
                                "hideDisplayName:1,0 ".
                                "hideDisplayNameFTUI:1,0 ".
                                "hideButtons:1,0 ".
                                "popupWindowSize ".
                                "popupStreamFW:$fwd ".
                                "popupStreamTo:OK,1,2,3,4,5,6,7,8,9,10,15,20,25,30,40,50,60 ".
                                "ptzButtonSize:selectnumbers,50,5,100,0,lin ".
                                "ptzButtonSizeFTUI:selectnumbers,50,5,100,0,lin ".
                                $readingFnAttributes;
  $hash->{RenameFn}           = "SSCamSTRM_Rename";
  $hash->{CopyFn}             = "SSCamSTRM_Copy";
  $hash->{FW_summaryFn}       = "SSCamSTRM_FwFn";
  $hash->{FW_detailFn}        = "SSCamSTRM_FwFn";
  $hash->{AttrFn}             = "SSCamSTRM_Attr";
  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667
  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
 
return; 
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
  $hash->{HELPER}{MODMETAABSENT}   = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  $hash->{LINK}                    = $link;
  
  # Versionsinformationen setzen
  SSCamSTRM_setVersionInfo($hash);
  
  readingsSingleUpdate($hash,"state", "initialized", 1);      # Init für "state" 
  
return undef;
}

################################################################
sub SSCamSTRM_Rename($$) {
	my ($new_name,$old_name) = @_;
    my $hash = $defs{$new_name};
    
    $hash->{DEF}  =~ s/$old_name/$new_name/g;
    $hash->{LINK} =~ s/$old_name/$new_name/g;

return;
}

###############################################################
#                  SSCamSTRM Copy
#  passt die Deviceparameter bei kopierten Device an
###############################################################
sub SSCamSTRM_Copy($$) {
	my ($old_name,$new_name) = @_;
    my $hash = $defs{$new_name};
    
    $hash->{DEF}  =~ s/$old_name/$new_name/g;
    $hash->{LINK} =~ s/$old_name/$new_name/g;

return;
}

###############################################################
#                  SSCamSTRM Get
###############################################################
sub SSCamSTRM_Get($@) {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $cmd  = shift @a;
       
 if ($cmd eq "html") {
     return SSCamSTRM_AsHtml($hash);
 } 
 
 if ($cmd eq "ftui") {
     return SSCamSTRM_AsHtml($hash,"ftui");
 }
 
return undef;
return "Unknown argument $cmd, choose one of html:noArg";
}

################################################################
sub SSCamSTRM_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];    
  
  return if(IsDisabled($name) || $hash->{MODEL} =~ /ptzcontrol|snapgallery/);
  
  my $setlist = "Unknown argument $opt, choose one of ".
	             "popupStream "
                 ;
  
  if ($opt eq "popupStream") {
  	  my $txt = SSCam_getclhash($hash);
      return $txt if($txt);
      
      my $link = AnalyzePerlCommand(undef, $hash->{LINK});
      
      # OK-Dialogbox oder Autoclose
      my $todef = 5;
      my $temp  = AttrVal($name, "popupStreamTo", $todef);
      my $to    = $prop?$prop:$temp;
      unless ($to =~ /^\d+$/ || lc($to) eq "ok") { $to = $todef; }
      $to       = ($to =~ /\d+/)?(1000 * $to):$to;
      
      my $pd = AttrVal($name, "popupStreamFW", "TYPE=FHEMWEB");
      
      my $parent = $hash->{PARENT};
      my $parentHash = $defs{$parent};
      
      my $htmlCode = $hash->{HELPER}{STREAM};
      
      if ($hash->{HELPER}{STREAMACTIVE}) {
          my $out = "<html>";
          $out .= $htmlCode;
          $out .= "</html>";
          
          Log3($name, 4, "$name - Stream to display: $htmlCode");
          Log3($name, 4, "$name - Stream display to webdevice: $pd");
		  
          if($to =~ /\d+/) {
              map {FW_directNotify("#FHEMWEB:$_", "FW_errmsg('$out', $to)", "")} devspec2array("$pd"); 
          } else {
              map {FW_directNotify("#FHEMWEB:$_", "FW_okDialog('$out')", "")} devspec2array("$pd");
          }	
      }
  
  } else {
      return "$setlist";
  }
  
return;  
}

################################################################
sub SSCamSTRM_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
		$val = ($do == 1 ? "disabled" : "initialized");
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }
    
    if($aName eq "genericStrmHtmlTag" && $hash->{MODEL} ne "generic") {
        return "This attribute is only usable for devices of MODEL \"generic\" ";
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/popupStreamTo/) {
            unless ($aVal =~ /^\d+$/ || $aVal eq "OK") { $_[3] = 5; }
        }        
    }

return undef;
}

################################################################
sub SSCamSTRM_FwFn($;$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  
  RemoveInternalTimer($hash);
  $hash->{HELPER}{FW} = $FW_wname;
       
  $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/s); 
  
  my $ret = "";
  if(IsDisabled($d)) {
      if(AttrVal($d,"hideDisplayName",0)) {
          $ret .= "Stream-device <a href=\"/fhem?detail=$d\">$d</a> is disabled";
      } else {
          $ret .= "<html>Stream-device is disabled</html>";
      }  
  } else {
      $ret .= $link;  
  }
  
  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal($d, "autoRefresh", 0);
  if($al) {  
      InternalTimer(gettimeofday()+$al, "SSCamSTRM_refresh", $hash, 0);
      Log3($d, 5, "$d - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }

return $ret;
}

################################################################
sub SSCamSTRM_refresh($) { 
  my ($hash) = @_;
  my $d      = $hash->{NAME};
  
  # Seitenrefresh festgelegt durch SSCamSTRM-Attribut "autoRefresh" und "autoRefreshFW"
  my $rd = AttrVal($d, "autoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }
  
  my $al = AttrVal($d, "autoRefresh", 0);
  if($al) {      
      InternalTimer(gettimeofday()+$al, "SSCamSTRM_refresh", $hash, 0);
      Log3($d, 5, "$d - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  } else {
      RemoveInternalTimer($hash);
  }
  
return;
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SSCamSTRM_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %SSCamSTRM_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 49_SSCamSTRM.pm 19051 2019-03-27 22:10:48Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 49_SSCamSTRM.pm 19051 2019-03-27 22:10:48Z DS_Starter $ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#    Grafik als HTML zurück liefern    (z.B. für Widget)
################################################################
sub SSCamSTRM_AsHtml($;$) { 
  my ($hash,$ftui) = @_;
  my $name         = $hash->{NAME};
  my $link         = $hash->{LINK};
  
  if ($ftui && $ftui eq "ftui") {
      # Aufruf aus TabletUI -> FW_cmd ersetzen gemäß FTUI Syntax
      my $s = substr($link,0,length($link)-2);
      $link = $s.",'$ftui')}";
  }
  
  $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/s); 
  
  my $ret = "<html>";
  if(IsDisabled($name)) {  
      if(AttrVal($name,"hideDisplayName",0)) {
          $ret .= "Stream-device <a href=\"/fhem?detail=$name\">$name</a> is disabled";
      } else {
          $ret .= "Stream-device is disabled";
      }

  } else {
	  $ret .= $link;  
  }
  
  $ret .= "</html>";
  
return $ret;
}

1;

=pod
=item summary    Definition of a streaming device by the SSCam module
=item summary_DE Erstellung eines Streaming-Device durch das SSCam-Modul
=begin html

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>
<br>
  <ul>
  The module SSCamSTRM is a special device module synchronized to the SSCam module. It is used for definition of
  Streaming-Devices. <br>
  Dependend of the Streaming-Device state, different buttons are provided to start actions:
    <ul>   
      <table>  
      <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> Switch off      </td><td>- stops a running playback </td></tr>
        <tr><td> Refresh         </td><td>- refresh a view (no page reload) </td></tr>
        <tr><td> Restart         </td><td>- restart a running content (e.g. a HLS-Stream) </td></tr>
        <tr><td> MJPEG           </td><td>- starts a MJPEG Livestream </td></tr>
        <tr><td> HLS             </td><td>- starts HLS (HTTP Live Stream) </td></tr>
        <tr><td> Last Record     </td><td>- playback the last recording as iFrame </td></tr>
        <tr><td> Last Rec H.264  </td><td>- playback the last recording if available as H.264 </td></tr>
        <tr><td> Last Rec MJPEG  </td><td>- playback the last recording if available as MJPEG </td></tr>
        <tr><td> Last SNAP       </td><td>- show the last snapshot </td></tr>
        <tr><td> Start Recording </td><td>- starts an endless recording </td></tr>
        <tr><td> Stop Recording  </td><td>- stopps the recording </td></tr>
        <tr><td> Take Snapshot   </td><td>- take a snapshot </td></tr>
      </table>
     </ul>     
     <br>
   
  <b>Integration into FHEM TabletUI: </b> <br><br>
  There is a widget provided for integration of SSCam-Streaming devices into FTUI. For further information please be informed by the
  (german) FHEM Wiki article: <br>
   <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
  <br><br>
  </ul>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    A SSCam Streaming-device is defined by the SSCam "set &lt;name&gt; createStreamDev" command.
    Please refer to SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> command.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> 
  <ul>
  
  <ul>
  <li><b>popupStream</b>  <br>
  
  The current streaming content is depicted in a popup window. By setting attribute "popupWindowSize" the 
  size of display can be adjusted. The attribute "popupStreamTo" determines the type of the popup window.
  If "OK" is set, an OK-dialog window will be opened. A specified number in seconds closes the popup window after this 
  time automatically (default 5 seconds). <br>
  Optionally you can append "OK" or &lt;seconds&gt; directly to override the adjustment by attribute "popupStreamTo".
  </li>
  </ul>
  <br>
  
  </ul>
  <br>
  
  <a name="SSCamSTRMget"></a>
  <b>Get</b> 
  <ul>
    <br>
    <ul>
      <li><b> get &lt;name&gt; html </b> </li>  
      The stream object (camera live view, snapshots or replay) is fetched as HTML-code and depicted. 
    </ul>
    <br>
    
    <br>
  </ul>
  
  <a name="SSCamSTRMattr"></a>
  <b>Attributes</b>
  <br><br>
  
  <ul>
  <ul>

    <a name="autoRefresh"></a>
    <li><b>autoRefresh</b><br>
      If set, active browser pages of the FHEMWEB-Device which has called the SSCamSTRM-Device, are new reloaded after  
      the specified time (seconds). Browser pages of a particular FHEMWEB-Device to be refreshed can be specified by 
      attribute "autoRefreshFW" instead.
      This may stabilize the video playback in some cases.
    </li>
    <br>
    
    <a name="autoRefreshFW"></a>
    <li><b>autoRefreshFW</b><br>
      If "autoRefresh" is activated, you can specify a particular FHEMWEB-Device whose active browser pages are refreshed 
      periodically.
    </li>
    <br>
    
    <a name="disable"></a>
    <li><b>disable</b><br>
      Deactivates the device.
    </li>
    <br>
    
    <a name="forcePageRefresh"></a>
    <li><b>forcePageRefresh</b><br>
      The attribute is evaluated by SSCam. <br>
      If set, a reload of all browser pages with active FHEMWEB connections will be enforced when particular camera operations 
      were finished. 
      This may stabilize the video playback in some cases.       
    </li>
    <br>
    
  <a name="genericStrmHtmlTag"></a>
  <li><b>genericStrmHtmlTag</b> &nbsp;&nbsp;&nbsp;&nbsp;(only valid for MODEL "generic") <br>
  This attribute contains HTML-Tags for video-specification in a Streaming-Device of type "generic". 
  <br><br> 
  
    <ul>
	  <b>Examples:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt; 
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS&gt')"
                               &gt  
      </pre>
      The variables $HTMLATTR, $NAME and $PWS are placeholders and absorb the attribute "htmlattr" (if set), the SSCam-Devicename 
      respectively the value of attribute "popupWindowSize" in streaming-device, which specify the windowsize of a popup window.
    </ul>
    <br><br>
    </li>
    
    <a name="hideButtons"></a>
    <li><b>hideButtons</b><br>
      Hide the buttons in the footer. It has no impact for streaming devices of type "switched".    
    </li>
    <br>
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Hide the device/alias name (link to detail view).     
    </li>
    <br>
    
    <a name="hideDisplayNameFTUI"></a>
    <li><b>hideDisplayNameFTUI</b><br>
      Hide the device/alias name (link to detail view) in FHEM TabletUI.     
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Additional HTML tags to manipulate the streaming device. 
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460" <br>
      </ul>
    </li>
    <br>
    
    <a name="htmlattrFTUI"></a>
    <li><b>htmlattrFTUI</b><br>
      Additional HTML tags to manipulate the streaming device in TabletUI. 
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460" <br>
      </ul>
    </li>
    <br>
    
    <a name="popupStreamFW"></a>
    <li><b>popupStreamFW</b><br>
      You can specify a particular FHEMWEB device whose active browser pages should open a popup window by the 
      "set &lt;name&gt; popupStream" command (default: all active FHEMWEB devices).
    </li>
    <br>
    
    <a name="popupStreamTo"></a>
    <li><b>popupStreamTo [OK | &lt;seconds&gt;]</b><br>
      The attribute "popupStreamTo" determines the type of the popup window which is opend by set-function "popupStream".
      If "OK" is set, an OK-dialog window will be opened. A specified number in seconds closes the popup window after this 
      time automatically (default 5 seconds)..
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; popupStreamTo 10  <br>
      </ul>
      <br>
    </li>
    
    <a name="popupWindowSize"></a>
    <li><b>popupWindowSize</b><br>
      If the content of playback (Videostream or Snapshot gallery) is suitable, by clicking the content a popup window will 
      appear. 
      The size of display can be setup by this attribute. 
      It is also valid for the get-function "popupStream".
      <br><br>
      <ul>
        <b>Example: </b><br>
        attr &lt;name&gt; popupWindowSize width="600" height="425"  <br>
      </ul>
    </li>
    <br>
    
    <a name="ptzButtonSize"></a>
    <li><b>ptzButtonSize</b><br>
      Specifies the PTZ-panel button size (in %).
    </li>
    <br>
    
    <a name="ptzButtonSizeFTUI"></a>
    <li><b>ptzButtonSizeFTUI</b><br>
      Specifies the PTZ-panel button size used in a Tablet UI (in %).
    </li>
  
  </ul>
  </ul>
  
</ul>

=end html
=begin html_DE

<a name="SSCamSTRM"></a>
<h3>SSCamSTRM</h3>
<ul>
  <br>
  Das Modul SSCamSTRM ist ein mit SSCam abgestimmtes Gerätemodul zur Definition von Streaming-Devices. <br>
  Abhängig vom Zustand des Streaming-Devices werden zum Start von Aktionen unterschiedliche Drucktasten angeboten:
    <ul>   
      <table>  
      <colgroup> <col width=25%> <col width=75%> </colgroup>
        <tr><td> Switch off      </td><td>- stoppt eine laufende Wiedergabe </td></tr>
        <tr><td> Refresh         </td><td>- auffrischen einer Ansicht (kein Browser Seiten-Reload) </td></tr>
        <tr><td> Restart         </td><td>- neu starten eines laufenden Contents (z.B. eines HLS-Streams) </td></tr>
        <tr><td> MJPEG           </td><td>- Startet MJPEG Livestream </td></tr>
        <tr><td> HLS             </td><td>- Startet HLS (HTTP Live Stream) </td></tr>
        <tr><td> Last Record     </td><td>- spielt die letzte Aufnahme als iFrame </td></tr>
        <tr><td> Last Rec H.264  </td><td>- spielt die letzte Aufnahme wenn als H.264 vorliegend </td></tr>
        <tr><td> Last Rec MJPEG  </td><td>- spielt die letzte Aufnahme wenn als MJPEG vorliegend </td></tr>
        <tr><td> Last SNAP       </td><td>- zeigt den letzten Snapshot </td></tr>
        <tr><td> Start Recording </td><td>- startet eine Endlosaufnahme </td></tr>
        <tr><td> Stop Recording  </td><td>- stoppt eine Aufnahme </td></tr>
        <tr><td> Take Snapshot   </td><td>- löst einen Schnappschuß aus </td></tr>
      </table>
     </ul>     
     <br>
   
    <b>Integration in FHEM TabletUI: </b> <br><br>
    Zur Integration von SSCam Streaming Devices (Typ SSCamSTRM) wird ein Widget bereitgestellt. 
	Für weitere Information dazu bitte den Artikel im Wiki durchlesen: <br>
    <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
    <br><br><br>
</ul>

<ul>
  <a name="SSCamSTRMdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    Ein SSCam Streaming-Device wird durch den SSCam Befehl "set &lt;name&gt; createStreamDev" erstellt.
    Siehe auch die Beschreibung zum SSCam <a href="#SSCamcreateStreamDev">"createStreamDev"</a> Befehl.  
    <br><br>
  </ul>

  <a name="SSCamSTRMset"></a>
  <b>Set</b> 
  <ul>
  
  <ul>
  <li><b>popupStream [OK | &lt;Sekunden&gt;]</b>  <br>
  
  Der aktuelle Streaminhalt wird in einem Popup-Fenster dargestellt. Mit dem Attribut "popupWindowSize" kann die 
  Darstellungsgröße eingestellt werden. Das Attribut "popupStreamTo" legt die Art des Popup-Fensters fest.
  Ist "OK" eingestellt, öffnet sich ein OK-Dialogfenster. Die angegebene Zahl in Sekunden schließt das Fenster nach dieser 
  Zeit automatisch (default 5 Sekunden). <br>
  Durch die optionalen Angabe von "OK" oder &lt;Sekunden&gt; kann die Einstellung des Attributes "popupStreamTo" übersteuert 
  werden.
  </li>
  </ul>
  <br>
  
  </ul>
  <br>
  
  <a name="SSCamSTRMget"></a>
  <b>Get</b> 
  <ul>
    <br>
    <ul>
      <li><b> get &lt;name&gt; html </b> </li>  
      Das eingebundene Streamobjekt (Kamera Live View, Schnappschüsse oder Wiedergabe einer Aufnahme) wird als HTML-code 
      abgerufen und dargestellt. 
    </ul>
    <br>
    
    <br>
  </ul>

  <a name="SSCamSTRMattr"></a>
  <b>Attribute</b>
  <br><br>
  
  <ul>
  <ul>
  
    <a name="autoRefresh"></a>
    <li><b>autoRefresh</b><br>
      Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SSCamSTRM-Device aufgerufen hat, nach der 
      eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu 
      geladen werden, kann dieses Device mit dem Attribut "autoRefreshFW" festgelegt werden.
      Dies kann in manchen Fällen die Wiedergabe innerhalb einer Anwendung stabilisieren.
    </li>
    <br>
    
    <a name="autoRefreshFW"></a>
    <li><b>autoRefreshFW</b><br>
      Ist "autoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
      regelmäßig neu geladen werden sollen.
    </li>
    <br>
  
    <a name="disable"></a>
    <li><b>disable</b><br>
      Aktiviert/deaktiviert das Device.
    </li>
    <br>
    
    <a name="forcePageRefresh"></a>
    <li><b>forcePageRefresh</b><br>
      Das Attribut wird durch SSCam ausgewertet. <br>
      Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen nach dem Abschluß bestimmter 
      SSCam-Befehle erzwungen. 
      Dies kann in manchen Fällen die Wiedergabe innerhalb einer Anwendung stabilisieren.     
    </li>
    <br>
    
  <a name="genericStrmHtmlTag"></a>  
  <li><b>genericStrmHtmlTag</b> &nbsp;&nbsp;&nbsp;&nbsp;(nur für MODEL "generic")<br>
  Das Attribut enthält HTML-Tags zur Video-Spezifikation in einem Streaming-Device von Typ "generic". 
  <br><br> 
  
    <ul>
	  <b>Beispiele:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt;
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS &gt')"
                               &gt                              
      </pre>
      Die Variablen $HTMLATTR, $NAME und $PWS sind Platzhalter und übernehmen ein gesetztes Attribut "htmlattr", den SSCam-
      Devicenamen bzw. das Attribut "popupWindowSize" im Streaming-Device, welches die Größe eines Popup-Windows festlegt.    
    </ul>
    <br><br>
    </li> 

    <a name="hideButtons"></a>
    <li><b>hideButtons</b><br>
      Verbirgt die Drucktasten in der Fußzeile. Dieses Attribut hat keinen Einfluß bei Streaming-Devices vom Typ "switched".    
    </li>
    <br>    
    
    <a name="hideDisplayName"></a>
    <li><b>hideDisplayName</b><br>
      Verbirgt den Device/Alias-Namen (Link zur Detailansicht).    
    </li>
    <br>
    
    <a name="hideDisplayNameFTUI"></a>
    <li><b>hideDisplayNameFTUI</b><br>
      Verbirgt den Device/Alias-Namen (Link zur Detailansicht) im TabletUI.    
    </li>
    <br>
    
    <a name="htmlattr"></a>
    <li><b>htmlattr</b><br>
      Zusätzliche HTML Tags zur Darstellung im Streaming Device. 
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460"  <br>
      </ul>
    </li>
    <br>
    
    <a name="htmlattrFTUI"></a>
    <li><b>htmlattrFTUI</b><br>
      Zusätzliche HTML Tags zur Darstellung des Streaming Device im TabletUI. 
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; htmlattr width="580" height="460"  <br>
      </ul>
    </li>
    <br>
    
    <a name="popupStreamFW"></a>
    <li><b>popupStreamFW</b><br>
      Es kann mit diesem Attribut das FHEMWEB-Device bestimmt werden, auf dessen Browserseiten sich Popup-Fenster mit 
      "set &lt;name&gt; popupStream" öffnen sollen (default: alle aktiven FHEMWEB-Devices).
    </li>
    <br>
    
    <a name="popupStreamTo"></a>
    <li><b>popupStreamTo [OK | &lt;Sekunden&gt;]</b><br>
      Das Attribut "popupStreamTo" legt die Art des Popup-Fensters fest welches mit der set-Funktion "popupStream" geöffnet wird.
      Ist "OK" eingestellt, öffnet sich ein OK-Dialogfenster. Die angegebene Zahl in Sekunden schließt das Fenster nach dieser 
      Zeit automatisch (default 5 Sekunden).
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; popupStreamTo 10  <br>
      </ul>
      <br>
    </li>
    
    <a name="popupWindowSize"></a>
    <li><b>popupWindowSize</b><br>
      Bei geeigneten Wiedergabeinhalten (Videostream oder Schnappschußgalerie) öffnet ein Klick auf den Bildinhalt ein 
      Popup-Fenster mit diesem Inhalt. Die Darstellungsgröße kann mit diesem Attribut eingestellt werden. 
      Das Attribut gilt ebenfalls für die set-Funktion "popupStream".
      <br><br>
      <ul>
        <b>Beispiel: </b><br>
        attr &lt;name&gt; popupWindowSize width="600" height="425"  <br>
      </ul>
    </li>
    <br>
    
    <a name="ptzButtonSize"></a>
    <li><b>ptzButtonSize</b><br>
      Legt die Größe der Drucktasten des PTZ Paneels fest (in %).
    </li>
    <br>
    
    <a name="ptzButtonSizeFTUI"></a>
    <li><b>ptzButtonSizeFTUI</b><br>
      Legt die Größe der Drucktasten des PTZ Paneels in einem Tablet UI fest (in %).
    </li>

  </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 49_SSCamSTRM.pm
{
  "abstract": "Definition of a streaming device by the SSCam module",
  "x_lang": {
    "de": {
      "abstract": "Erstellung eines Streaming-Device durch das SSCam-Modul"
    }
  },
  "keywords": [
    "camera",
    "streaming",
    "PTZ",
    "Synology Surveillance Station",
    "MJPEG",
    "HLS",
    "RTSP"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014       
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station",
      "title": "SSCAM - Steuerung von Kameras in Synology Surveillance Station"
    }
  }
}
=end :application/json;q=META.json

=cut
