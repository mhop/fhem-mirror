########################################################################################################################
# $Id: $
#########################################################################################################################
#       76_SMAPortalSPG.pm
#
#       (c) 2019 by Heiko Maaz  e-mail: Heiko dot Maaz at t-online dot de
#       forked from 98_weblink.pm by Rudolf König
#
#       This Module is used by module 76_SMAPortal to create graphic devices.
#       It can't be used standalone without any SMAPortal-Device.
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
use Time::HiRes qw(gettimeofday);
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1; 

# Versions History intern
our %SMAPortalSPG_vNotesIntern = (
  "1.0.0"  => "03.06.2019  initial Version "
);

################################################################
sub SMAPortalSPG_Initialize($) {
  my ($hash) = @_;

  my $fwd = join(",",devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized")); 
  
  $hash->{DefFn}              = "SMAPortalSPG_Define";
  $hash->{AttrList}           = "autoRefresh:selectnumbers,120,0.2,1800,0,log10 ".
                                "autoRefreshFW:$fwd ".
                                "beamColor:colorpicker,RGB ".
                                "beamColor2:colorpicker,RGB ".
                                "beamHeight ".
                                "beamWidth ".
                                "consumerList ".
                                "consumerLegend:none,icon_top,icon_bottom,text_top,text_bottom ".
                                "disable:1,0 ".
                                "forcePageRefresh:1,0 ".
                                "hourCount:slider,4,1,24 ".
                                "hourStyle ".
                                "maxPV ".
                                "htmlStart ".
                                "htmlEnd ".
                                "showDiff:no,top,bottom ".
                                "showHeader:1,0 ".
                                "showLink:1,0 ".
                                "showNight:1,0 ".
                                "showWeather:1,0 ".
                                "spaceSize ".
                                "suggestIcon ".
                                "layoutType:pv,co,pvco,diff ".
                                "W/kW:W,kW ".
                                "weatherColor:colorpicker,RGB ".                                
                                $readingFnAttributes;
  $hash->{RenameFn}           = "SMAPortalSPG_Rename";
  $hash->{CopyFn}             = "SMAPortalSPG_Copy";
  $hash->{FW_summaryFn}       = "SMAPortalSPG_FwFn";
  $hash->{FW_detailFn}        = "SMAPortalSPG_FwFn";
  $hash->{AttrFn}             = "SMAPortalSPG_Attr";
  $hash->{FW_hideDisplayName} = 1;                     # Forum 88667

  # $hash->{FW_addDetailToSummary} = 1;
  # $hash->{FW_atPageEnd} = 1;                         # wenn 1 -> kein Longpoll ohne informid in HTML-Tag

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
 
return; 
}

################################################################
sub SMAPortalSPG_Define($$) {
  my ($hash, $def) = @_;
  my ($name, $type, $link) = split("[ \t]+", $def, 3);
  
  if(!$link) {
    return "Usage: define <name> SMAPortalSPG <arg>";
  }

  my $arg = (split("[()]",$link))[1];
  $arg   =~ s/'//g;
  $hash->{PARENT}                 = (split(",",$arg))[0]; 
  $hash->{HELPER}{MODMETAABSENT}  = 1 if($modMetaAbsent);                          # Modul Meta.pm nicht vorhanden
  $hash->{LINK}                   = $link;
  
  # Versionsinformationen setzen
  SMAPortalSPG_setVersionInfo($hash);
  
  readingsSingleUpdate($hash,"state", "initialized", 1);                           # Init für "state" 
  
return undef;
}

################################################################
sub SMAPortalSPG_Rename($$) {
	my ($new_name,$old_name) = @_;
    my $hash = $defs{$new_name};
    
    $hash->{DEF}  =~ s/$old_name/$new_name/g;
    $hash->{LINK} =~ s/$old_name/$new_name/g;

return;
}

################################################################
sub SMAPortalSPG_Copy($$) {
	my ($old_name,$new_name) = @_;
    my $hash = $defs{$new_name};
    
    $hash->{DEF}  =~ s/$old_name/$new_name/g;
    $hash->{LINK} =~ s/$old_name/$new_name/g;

return;
}

################################################################
sub SMAPortalSPG_Attr($$$$) {
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
        
        if($do == 1) {
            my @allrds = keys%{$defs{$name}{READINGS}};
            foreach my $key(@allrds) {
                delete($defs{$name}{READINGS}{$key}) if($key ne "state");
            }
        }
    }
    
    if($aName eq "icon") {
        $_[2] = "suggestIcon";
    }

return undef;
}

################################################################
sub SMAPortalSPG_FwFn($;$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  my $height;
  
  RemoveInternalTimer($hash);
  $hash->{HELPER}{FW} = $FW_wname;
       
  $link = AnalyzePerlCommand(undef, $link) if($link =~ m/^{(.*)}$/s);

  my $alias = AttrVal($d, "alias", $d);                            # Linktext als Aliasname oder Devicename setzen
  my $dlink = "<a href=\"/fhem?detail=$d\">$alias</a>"; 
  
  my $ret = "";
  if(IsDisabled($d)) {
      $height   = AttrNum($d, 'beamHeight', 200);   
      $ret     .= "<table class='roomoverview'>";
      $ret     .= "<tr style='height:".$height."px'>";
      $ret     .= "<td>";
      $ret     .= "SMA Portal graphic device <a href=\"/fhem?detail=$d\">$d</a> is disabled"; 
      $ret     .= "</td>";
      $ret     .= "</tr>";
      $ret     .= "</table>";
  } else {
      $ret .= "<span>$dlink </span><br>"  if(AttrVal($d,"showLink",0));
      $ret .= $link;  
  }
  
  # Autorefresh nur des aufrufenden FHEMWEB-Devices
  my $al = AttrVal($d, "autoRefresh", 0);
  if($al) {  
      InternalTimer(gettimeofday()+$al, "SMAPortalSPG_refresh", $hash, 0);
      Log3($d, 5, "$d - next start of autoRefresh: ".FmtDateTime(gettimeofday()+$al));
  }

return $ret;
}

################################################################
sub SMAPortalSPG_refresh($) { 
  my ($hash) = @_;
  my $d      = $hash->{NAME};
  
  # Seitenrefresh festgelegt durch SMAPortalSPG-Attribut "autoRefresh" und "autoRefreshFW"
  my $rd = AttrVal($d, "autoRefreshFW", $hash->{HELPER}{FW});
  { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } $rd }
  
  my $al = AttrVal($d, "autoRefresh", 0);
  if($al) {      
      InternalTimer(gettimeofday()+$al, "SMAPortalSPG_refresh", $hash, 0);
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
sub SMAPortalSPG_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %SMAPortalSPG_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 49_SMAPortalSPG.pm 19051 2019-03-27 22:10:48Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 49_SMAPortalSPG.pm 19051 2019-03-27 22:10:48Z DS_Starter $ im Kopf komplett! vorhanden )
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

1;

=pod
=item summary    Definition of grapic devices by the SMAPortal module
=item summary_DE Erstellung von Grafik-Devices durch das SMAPortal-Modul
=begin html

<a name="SMAPortalSPG"></a>
<h3>SMAPortalSPG</h3>

  Is coming soon. 

=end html
=begin html_DE

<a name="SMAPortalSPG"></a>
<h3>SMAPortalSPG</h3>

<br>
Das Modul SMAPortalSPG ist ein mit SMAPortal abgestimmtes Gerätemodul zur Definition von Grafik-Devices. <br>

<ul>
  <a name="SMAPortalSPGdefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
    Ein SMAPortal Grafik Device wird durch den SMAPortal Befehl "set &lt;name&gt; createPortalGraphic &lt;Typ&gt;" erstellt.
    Siehe auch die Beschreibung zum SMAPortal <a href="#SMAPortalCreatePortalGraphic">"createPortalGraphic"</a> Befehl.  
    <br><br>
  </ul>

  <a name="SMAPortalSPGset"></a>
  <b>Set</b> 
  <ul>
  N/A
  </ul>
  <br>
  
  <a name="SMAPortalSPGget"></a>
  <b>Get</b> 
  
  <ul>
  N/A
  </ul>
  <br>

  <a name="SMAPortalSPGattr"></a>
  <b>Attribute</b>
  <br><br>
  <ul>
     <ul>
        <a name="alias"></a>
        <li><b>alias </b><br>
          In Verbindung mit "showLink" beliebiger Abzeigename.
        </li>
        <br>  
       
       <a name="autoRefresh"></a>
       <li><b>autoRefresh</b><br>
         Wenn gesetzt, werden aktive Browserseiten des FHEMWEB-Devices welches das SMAPortalSPG-Device aufgerufen hat, nach der 
         eingestellten Zeit (Sekunden) neu geladen. Sollen statt dessen Browserseiten eines bestimmten FHEMWEB-Devices neu 
         geladen werden, kann dieses Device mit dem Attribut "autoRefreshFW" festgelegt werden.
       </li>
       <br>
    
       <a name="autoRefreshFW"></a>
       <li><b>autoRefreshFW</b><br>
         Ist "autoRefresh" aktiviert, kann mit diesem Attribut das FHEMWEB-Device bestimmt werden dessen aktive Browserseiten
         regelmäßig neu geladen werden sollen.
       </li>
       <br>
    
       <a name="beamColor"></a>
       <li><b>beamColor </b><br>
         Farbauswahl der primären Balken.  
       </li>
       <br>
       
       <a name="beamColor2"></a>
       <li><b>beamColor2 </b><br>
         Farbauswahl der sekundären Balken. Die zweite Farbe ist nur sinnvoll für Anzeigedevice "Generation_Consumption" 
         (Type pvco) und "Differential" (Type diff).
       </li>
       <br>  
       
       <a name="beamHeight"></a>
       <li><b>beamHeight &lt;value&gt; </b><br>
         Höhe der Balken in px und damit Bestimmung der gesammten Höhe.
         In Verbindung mit hourCount lassen sich damit auch recht kleine Grafikausgaben erzeugen. (default: 200)
       </li>
       <br>
       
       <a name="beamWidth"></a>
       <li><b>beamWidth &lt;value&gt; </b><br>
         Breite der Balken in px. ( default: 6 (auto) )
       </li>
       <br>  

       <a name="consumerList"></a>
       <li><b>consumerList </b><br>
         Komma getrennte Liste der am Sunny Home Manager angeschlossenen Geräte in der Form &lt;Verbrauchername&gt;:&lt;Icon&gt;@&lt;Farbe&gt;. <br>
	     Sobald die Einschaltung einer der angegebenen Verbraucher geplant ist, wird der geplante Zeitraum in der Grafik 
         angezeigt. 
         Der Name des Verbrauchers muss dabei dem Namen im Reading "L3_&lt;Verbrauchername&gt;_Planned" entsprechen. <br><br>
       
         <b>Beispiel: </b> <br>
         Trockner:scene_clothes_dryer@yellow,Waschmaschine:scene_washing_machine@lightgreen,Geschirrspueler:scene_dishwasher@orange
         <br>
       </li>
       <br>  
           
       <a name="consumerLegend"></a>
       <li><b>consumerLegend &ltnone | icon_top | icon_bottom | text_top | text_bottom&gt; </b><br>
         Lage bzw. Art und Weise der angezeigten Consumers Legende.
       </li>
       <br>       
  
       <a name="disable"></a>
       <li><b>disable</b><br>
         Aktiviert/deaktiviert das Device.
       </li>
       <br>
     
       <a name="forcePageRefresh"></a>
       <li><b>forcePageRefresh</b><br>
         Das Attribut wird durch SMAPortal ausgewertet. <br>
         Wenn gesetzt, wird ein Reload aller Browserseiten mit aktiven FHEMWEB-Verbindungen nach dem Abschluß bestimmter 
         SMAPortal-Befehle erzwungen.    
       </li>
       <br>
       
       <a name="hourCount"></a>
       <li><b>hourCount &lt;4...24&gt; </b><br>
         Anzahl der Balken/Stunden. (default: 24)
       </li>
       <br>
       
       <a name="hourStyle"></a>
       <li><b>hourStyle </b><br>
         Format der Zeitangabe. <br><br>
       
	     <ul>   
	     <table>  
	     <colgroup> <col width=10%> <col width=90%> </colgroup>
		    <tr><td> <b>nicht gesetzt</b>  </td><td>- nur Stundenangabe ohne Minuten (default)</td></tr>
	  	    <tr><td> <b>:00</b>            </td><td>- Stunden sowie Minuten zweistellig, z.B. 10:00 </td></tr>
		    <tr><td> <b>:0</b>             </td><td>- Stunden sowie Minuten einstellig, z.B. 8:0 </td></tr>
	     </table>
	     </ul>       
       </li>
       <br>
 
       <a name="maxPV"></a>
       <li><b>maxPV &lt;0...val&gt; </b><br>
         Maximaler Ertrag in einer Stunde zur Berechnung der Balkenhöhe, 0 = dynamisch. (default: 0)
       </li>
       <br>
       
       <a name="htmlStart"></a>
       <li><b>htmlStart &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der vor der generierten Portalgrafik ausgegeben wird. 
       </li>
       <br>

       <a name="htmlEnd"></a>
       <li><b>htmlEnd &lt;HTML-String&gt; </b><br>
         Angabe eines beliebigen HTML-Strings der nach der generierten Portalgrafik ausgegeben wird. 
       </li>
       <br> 
   
       <a name="showDiff"></a>
       <li><b>showDiff &lt;no | top | bottom&gt; </b><br>
         Zusätzliche Anzeige der Differenz "Ertrag - Verbrauch" wie beim Anzeigetyp Differential (diff). (default: no)
       </li>
       <br>
       
       <a name="showHeader"></a>
       <li><b>showHeader &lt;1|0&gt; </b><br>
         Anzeige der Kopfzeile mit Prognosedaten, Rest des aktuellen Tages und des nächsten Tages (default: 1)
       </li>
       <br>
       
       <a name="showLink"></a>
       <li><b>showLink &lt;1|0&gt; </b><br>
         Anzeige des Device-Detaillinks über der grafischen Ausgabe (default: 1)
       </li>
       <br>
       
       <a name="showNight"></a>
       <li><b>showNight &lt;1|0&gt; </b><br>
         Ebenfalls die Nachtstunden ohne Ertragsprognose anzeigen (default: 0)
       </li>
       <br>

       <a name="showWeather"></a>
       <li><b>showWeather &lt;1|0&gt; </b><br>
         Wettericons anzeigen. (default: 1)
       </li>
       <br> 
       
       <a name="spaceSize"></a>
       <li><b>spaceSize &lt;value&gt; </b><br>
         Legt fest wieviel Platz in px über den Balken (bei Anzeigetyp Differential (diff) auch unter diesen) zur Anzeige der 
         Werte freigehalten wird. Bei Styles die große Fonts benutzen, kann der default-Wert zu klein sein, bzw. u.U. rutscht ein 
         Balken über die Grundlinie. In diesen Fällen bitte den Wert erhöhen. (default: 24)
       </li>
       <br> 
       
       <a name="suggestIcon"></a>
       <li><b>suggestIcon </b><br>
         Setzt das Icon zur Darstellung der Zeiten mit Verbraucherempfehlung. 
         Dazu kann ein beliebiges Icon mit Hilfe der Standard "Select Icon"-Funktion (links unten im FHEMWEB) direkt ausgewählt 
         werden. 
       </li>  
       <br>

       <a name="layoutType"></a>
       <li><b>layoutType &lt;pv | co | pvco | diff&gt; </b><br>
       Layout der Portalgrafik. (default: pv)  <br><br>
       
	   <ul>   
	   <table>  
	   <colgroup> <col width=15%> <col width=85%> </colgroup>
		  <tr><td> <b>pv</b>    </td><td>- Erzeugung </td></tr>
		  <tr><td> <b>co</b>    </td><td>- Verbrauch </td></tr>
		  <tr><td> <b>pvco</b>  </td><td>- Erzeugung und Verbrauch </td></tr>
          <tr><td> <b>diff</b>  </td><td>- Differenz von Erzeugung und Verbrauch </td></tr>
	   </table>
	   </ul>
       </li>
       <br> 
       
       <a name="W/kW"></a>
       <li><b>W/kW &lt;W | kW&gt; </b><br>
         Wertanzeige in W oder in kW auf eine Nachkommastelle gerundet. (default: W)
       </li>
       <br>   

       <a name="weatherColor"></a>
       <li><b>weatherColor </b><br>
         Farbe der Wetter-Icons.
       </li>
       <br>        

     </ul>
  </ul>
  
</ul>

=end html_DE

=for :application/json;q=META.json 76_SMAPortalSPG.pm
{
  "abstract": "Definition of grapic devices by the SMAPortal module",
  "x_lang": {
    "de": {
      "abstract": "Erstellung von Grafik-Devices durch das SMAPortal-Modul"
    }
  },
  "keywords": [
    "sma",
    "photovoltaik",
    "electricity",
    "portal",
    "smaportal",
    "graphics",
    "longpoll",
    "refresh"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
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
        "perl": 5.014,
        "Time::HiRes": 0        
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/76_SMAPortalSPG.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/76_SMAPortalSPG.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
