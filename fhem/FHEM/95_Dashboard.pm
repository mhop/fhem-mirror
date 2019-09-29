# $Id$
########################################################################################
#       95_Dashboard.pm
#
#       written and released by Sascha Hermann 2013
#      
#       maintained 2019 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
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
########################################################################################
# Known Bugs/Todos:
# BUG: Nicht alle Inhalte aller Tabs laden, bei Plots dauert die bedienung des Dashboards zu lange. -> elemente hidden? -> widgets aus js über XHR nachladen und dann anzeigen (jquery xml nachladen...)
# BUG: Variabler abstand wird nicht gesichert
# BUG: Überlappen Gruppen andere? ->Zindex oberer reihe > als darunter liegenden
#
# Helpfull Links:
# http://jquery.10927.n7.nabble.com/saving-portlet-state-td125831.html
# http://jsfiddle.net/w7ZvQ/
# http://jsfiddle.net/adamboduch/e6zdX/1/
# http://www.innovativephp.com/jquery-resizable-practical-examples-and-demos/
# http://jsfiddle.net/raulfernandez/mAuxn/
# http://jsfiddle.net/zeTP8/
#
########################################################################################
package main;

use strict;
use warnings;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;

use vars qw(%FW_icons); 	# List of icons
use vars qw($FW_dir);      	# base directory for web server
use vars qw($FW_icondir);   # icon base directory
use vars qw($FW_room);      # currently selected room
use vars qw(%defs);		    # FHEM device/button definitions
#use vars qw(%FW_groups);	# List of Groups
use vars qw($FW_wname);     # Web instance
use vars qw(%FW_types);     # device types
use vars qw($FW_ss);      	# is smallscreen, needed by 97_GROUP/95_VIEW

# Versions History intern
our %Dashboard_vNotesIntern = (
  "3.15.2" => "29.09.2019  fix warnings, Forum: https://forum.fhem.de/index.php/topic,16503.msg978883.html#msg978883 ",
  "3.15.1" => "25.09.2019  change initial attributes, commandref revised ",
  "3.15.0" => "24.09.2019  set activateTab, rename dashboard_activetab to dashboard_homeTab, ".
                           "rename dashboard_activetabRefresh to dashboard_webRefresh, some bugfixes, comref revised ",
  "3.14.0" => "22.09.2019  new attribute dashboard_activetabRefresh, activate the active tab in browser ",
  "3.13.2" => "21.09.2019  new solution to eliminate links for all Devices ",
  "3.13.1" => "21.09.2019  don't eliminate links for PageEnd-Devices ",
  "3.13.0" => "20.09.2019  change attribute noLinks to dashboard_noLinks, eliminate links for PageEnd-Devices ",
  "3.12.0" => "16.09.2019  new attribute noLinks, review comref and get-options ",
  "3.11.0" => "16.09.2019  attr dashboard_activetab is now working properly, commandref revised, calculate attribute ".
                           "dashboard_activetab (is now a userattr) ",
  "3.10.1" => "29.06.2018  added FW_hideDisplayName, Forum #88727 ",
  "1.0.0"  => "20.12.2013  initial version released to testers "
);


#########################
# Forward declaration
sub Dashboard_GetGroupList();

#########################
# Global variables
my %group;
my $dashboard_groupListfhem;
my $fwjquery         = "jquery.min.js";
my $fwjqueryui       = "jquery-ui.min.js";

#############################################################################################
sub Dashboard_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}       = "Dashboard_define";
  $hash->{SetFn}       = "Dashboard_Set";  
  $hash->{GetFn}       = "Dashboard_Get";
  $hash->{UndefFn}     = "Dashboard_undef";
  $hash->{FW_detailFn} = "Dashboard_DetailFN";    
  $hash->{AttrFn}      = "Dashboard_Attr";
  $hash->{AttrList}    = "disable:0,1 ".
						 "dashboard_backgroundimage ".
  						 "dashboard_colcount:1,2,3,4,5 ".	
						 "dashboard_customcss " .                         
						 "dashboard_debug:0,1 ".
						 "dashboard_flexible " .						 
						 "dashboard_rowtopheight ".
						 "dashboard_rowbottomheight ".
						 "dashboard_row:top,center,bottom,top-center,center-bottom,top-center-bottom ".	
						 "dashboard_rowcenterheight ".
						 "dashboard_rowcentercolwidth ".
						 "dashboard_showfullsize:0,1 ".
						 "dashboard_showtabs:tabs-and-buttonbar-at-the-top,tabs-and-buttonbar-on-the-bottom,tabs-and-buttonbar-hidden ".
						 "dashboard_showtogglebuttons:0,1 ".
						 "dashboard_tab1name " .
						 "dashboard_tab1groups " .
						 "dashboard_tab1devices " .
						 "dashboard_tab1sorting " .
						 "dashboard_tab1icon " .
						 "dashboard_tab1colcount " .
						 "dashboard_tab1rowcentercolwidth " .
						 "dashboard_tab1backgroundimage " .
						 "dashboard_width ".
                         "dashboard_noLinks:1,0 ";
  
  $data{FWEXT}{jquery}{SCRIPT}      = "/pgm2/".$fwjquery   if (!$data{FWEXT}{jquery}{SCRIPT});
  $data{FWEXT}{jqueryui}{SCRIPT}    = "/pgm2/".$fwjqueryui if (!$data{FWEXT}{jqueryui}{SCRIPT});
  $data{FWEXT}{z_dashboard}{SCRIPT} = "/pgm2/dashboard.js" if (!$data{FWEXT}{z_dashboard});					 
  $data{FWEXT}{x_dashboard}{SCRIPT} = "/pgm2/svg.js"       if (!$data{FWEXT}{x_dashboard});		

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };         # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)  
	
return undef;
}

################################################################
#   Definition
################################################################
sub Dashboard_define ($$) {
  my ($hash, $def) = @_;

  my @args = split (" ", $def);
  my $now  = time();
  my $name = $hash->{NAME}; 
  
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden

  # Versionsinformationen setzen
  Dashboard_setVersionInfo($hash);
 
  readingsSingleUpdate( $hash, "state", "Initialized", 0 ); 
  
  RemoveInternalTimer($hash);
  InternalTimer      ($now+2, 'Dashboard_init', $hash, 0);
  InternalTimer      ($now+5, 'Dashboard_CheckDashboardAttributUssage', $hash, 0);

  my $url = '/dashboard/'.$name;

  $data{FWEXT}{$url}{CONTENTFUNC} = 'Dashboard_CGI';                             # $data{FWEXT} = FHEMWEB Extension, siehe 01_FHEMWEB.pm
  $data{FWEXT}{$url}{LINK}        = 'dashboard/'.$name;
  $data{FWEXT}{$url}{NAME}        = $name;
		
return;
}

################################################################
#   Set
################################################################
sub Dashboard_Set($@) {
  my ($hash, $name, $cmd, @args) = @_;
    
  my $setlist = "Unknown argument $cmd, choose one of ".
	             "lock:noArg ".
                 "unlock:noArg "
                 ;
  
  my $tl = Dashboard_possibleTabs ($name);	
  
  $setlist .= "activateTab:$tl " if($tl);
    
  if ( $cmd eq "lock" ) {
      readingsSingleUpdate ($hash, "lockstate", "lock", 0); 
	  return;
  } elsif ( $cmd eq "unlock" ) {
	  readingsSingleUpdate ($hash, "lockstate", "unlock", 0);
	  return;
  } elsif ( $cmd eq "activateTab" ) {
	  Dashboard_activateTab ($name,$args[0]);
	  return;
  } else { 
	  return $setlist;
  }
  
return;
}

################################################################
#   Get
################################################################
sub Dashboard_Get($@) {
  my ($hash, @a) = @_;
  my $res        = "";
  
  my $arg  = (defined($a[1]) ? $a[1] : "");
  my $arg2 = (defined($a[2]) ? $a[2] : "");
  
  if ($arg eq "config") {
      my $name      = $hash->{NAME};
      my $attrdata  = $attr{$name};
      if ($attrdata) {
          my $x = keys %$attrdata;
          my $i = 0;		
          my @splitattr;
          $res  .= "{\n";
          $res  .= "  \"CONFIG\": {\n";
          $res  .= "    \"name\": \"$name\",\n";
          $res  .= "    \"lockstate\": \"".ReadingsVal($name,"lockstate","unlock")."\",\n";			

          my @iconFolders = split(":", AttrVal($FW_wname, "iconPath", "$FW_sp:default:fhemSVG:openautomation"));	
          my $iconDirs = "";
          
          foreach my $idir  (@iconFolders) {$iconDirs .= "$attr{global}{modpath}/www/images/".$idir.",";}
          
          $res .= "    \"icondirs\": \"$iconDirs\", \"dashboard_tabcount\": " . Dashboard_GetTabCount($hash, 0). ", \"dashboard_homeTab\": " . Dashboard_GetActiveTab($name);
          $res .= ($i != $x) ? ",\n" : "\n";
          
          foreach my $attr (sort keys %$attrdata) {
              $i++;				
              @splitattr = split("@", $attrdata->{$attr});
              if (@splitattr == 2) {
                  $res .= "    \"".Dashboard_Escape($attr)."\": \"".$splitattr[0]."\",\n";
                  $res .= "    \"".Dashboard_Escape($attr)."color\": \"".$splitattr[1]."\"";
              } elsif ($attr ne "dashboard_homeTab") { 
                  $res .= "    \"".Dashboard_Escape($attr)."\": \"".$attrdata->{$attr}."\"";
              } else {
                  next;
              }
              $res .= ($i != $x) ? ",\n" : "\n";
          }
          $res .= "  }\n";
          $res .= "}\n";			
          return $res;
      }		
  
  } elsif ($arg eq "groupWidget") {
        #### Comming Soon ######
        # For dynamic load of GroupWidgets from JavaScript  
		#my $dbgroup = "";
		#for (my $p=2;$p<@a;$p++){$dbgroup .= @a[$p]." ";} #For Groupnames with Space
		#for (my $p=2;$p<@a;$p++){$dbgroup .= $a[$p]." ";} #For Groupnames with Space
 
		#$dashboard_groupListfhem = Dashboard_GetGroupList;
		#%group = Dashboard_BuildGroupList($dashboard_groupListfhem);
		#$res .= Dashboard_BuildGroupWidgets(1,1,1212,trim($dbgroup),"t1c1,".trim($dbgroup).",true,0,0:"); 
		#return $res;		
        #For dynamic loading of tabs
  
  } elsif ($arg eq "tab" && $arg2 =~ /^\d+$/) {
      return Dashboard_BuildDashboardTab($arg2, $hash->{NAME});
  
  } elsif ($arg eq "icon") {
      shift @a;
      shift @a;
      return "Please provide only one icon whose path and full name is to show." if(!@a || $a[1]);
      my $icon = join (' ', @a);
      return FW_iconPath($icon);
      
  } else {
      return "Unknown argument $arg choose one of config:noArg icon";
  }
}

################################################################
#   Attr
################################################################
sub Dashboard_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};

  if ($cmd eq "set") {
      if ($attrName =~ m/dashboard_tab([1-9][0-9]*)groups/ || $attrName =~ m/dashboard_tab([1-9][0-9]*)devices/) {
          # add dynamic attributes
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "name");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "devices");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "groups");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "sorting");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "icon");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "colcount");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "rowcentercolwidth");
          addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "backgroundimage");
      }

      if ($attrName =~ m/alias/) {
          # if an alias is set to the dashboard, replace the name shown in the left navigation by this alias
          my $url = '/dashboard/'.$name;
          $data{FWEXT}{$url}{NAME} = $attrVal;
      }
      
      if ($attrName =~ m/dashboard_homeTab/) {
          Dashboard_activateTab ($name,$attrVal);
      }
  }
      
  InternalTimer (time()+2, 'Dashboard_init', $hash, 0);

return;  
}

################################################################
#   Undefine
################################################################
sub Dashboard_undef ($$) {
  my ($hash,$arg) = @_;

  # remove dashboard links from left menu
  my $url = '/dashboard/'.$hash->{NAME};
  delete $data{FWEXT}{$url};

  RemoveInternalTimer($hash);
  
return undef;
}

################################################################
#  Routine für FHEMWEB Detailanzeige
################################################################
sub Dashboard_DetailFN() {
	my ($name, $d, $room, $pageHash) = @_;
	my $hash = $defs{$name};
  
	my $ret = ""; 
	$ret .= "<table class=\"block wide\" id=\"dashboardtoolbar\"  style=\"width:100%\">\n";
	$ret .= "<tr><td>Helper:\n<div>\n";   
	$ret .= "<a href=\"$FW_ME/dashboard/".$d."\"><button type=\"button\">Return to Dashboard</button></a>\n";
	$ret .= "<a href=\"$FW_ME?cmd=shutdown restart\"><button type=\"button\">Restart FHEM</button></a>\n";
	$ret .= "<a href=\"$FW_ME?cmd=save\"><button type=\"button\">Save config</button></a>\n";
	$ret .= "</div>\n";
	$ret .= "</td></tr>\n"; 	
	$ret .= "</table>\n";
	
return $ret;
}

#############################################################################################
#           Common Start
#############################################################################################
sub Dashboard_CGI($) {
  my ($htmlarg) = @_;

  $htmlarg   =~ s/^\///;                                                           # eliminate leading /
  my @params = split(/\//,$htmlarg);                                               # split URL by /
  my $ret    = '';
  my $name   = $params[1];

  $ret = '<div id="content">';
  
  if ($name && defined($defs{$name})) {                                                                
      my $showfullsize  = AttrVal($name, "dashboard_showfullsize", 0); 

      if ($showfullsize) {
          if ($FW_RET =~ m/<body[^>]*class="([^"]+)"[^>]*>/) {
              $FW_RET =~ s/class="$1"/class="$1 dashboard_fullsize"/;
          } else {
              $FW_RET =~ s/<body/<body class="dashboard_fullsize"/;
          }
      }
      $ret .= Dashboard_SummaryFN($FW_wname,$name,$FW_room,undef);
  } else {
      $ret .= 'Dashboard "'.$name.'" not found';
  }

  $ret .= '</div>';
  FW_pO $ret;

  # empty room to make sure no room actions are taken by the framework
  $FW_room = '';

return 0;
}

#############################################################################################
#           Dashboard als HTML-Ausgabe
#############################################################################################
sub DashboardAsHtml($) {
	my ($d) = @_; 
	Dashboard_SummaryFN($FW_wname,$d,$FW_room,undef);
}

#############################################################################################
#    zentrale Dashboard Generierung 
#   (beachte $data{FWEXT} bzw. $data{FWEXT}{CONTENTFUNC} in 01_FHEMWEB.pm)
#############################################################################################
sub Dashboard_SummaryFN ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_;
 
  my $ret             = "";
  my $showbuttonbar   = "hidden";
  my $debugfield      = "hidden";
  my $hash            = $defs{$d};
  my $name            = $d;
  my $id              = $defs{$d}{NR};
 
  ######################### Read Dashboard Attributes and set Default-Values ####################################
  my $lockstate            = ReadingsVal($name, "lockstate", "unlock");
  my $showhelper           = ($lockstate eq "unlock") ? 1 : 0; 
  my $disable              = AttrVal($name, "disable", 0);
  my $colcount             = AttrVal($name, "dashboard_colcount", 1);
  my $colwidth             = AttrVal($name, "dashboard_rowcentercolwidth", 100);
  my $colheight            = AttrVal($name, "dashboard_rowcenterheight", 400); 
  my $rowtopheight         = AttrVal($name, "dashboard_rowtopheight", 250);
  my $rowbottomheight      = AttrVal($name, "dashboard_rowbottomheight", 250);  
  my $showtabs             = AttrVal($name, "dashboard_showtabs", "tabs-and-buttonbar-at-the-top"); 
  my $showtogglebuttons    = AttrVal($name, "dashboard_showtogglebuttons", 1); 
  my $showfullsize         = AttrVal($name, "dashboard_showfullsize", 0); 
  my $flexible             = AttrVal($name, "dashboard_flexible", 0);
  my $customcss            = AttrVal($name, "dashboard_customcss", "none");
  my $backgroundimage      = AttrVal($name, "dashboard_backgroundimage", "");
  my $row                  = AttrVal($name, "dashboard_row", "center");
  my $debug                = AttrVal($name, "dashboard_debug", "0");
  my ($activetab,$tabname) = Dashboard_GetActiveTab($name,1);
  my $tabcount             = Dashboard_GetTabCount($hash, 1);
  my $dashboardversion     = $hash->{HELPER}{VERSION};
  my $dbwidth              = AttrVal($name, "dashboard_width", "100%");   
  my @tabnames             = ();
  my @tabsortings          = ();

  for (my $i = 0; $i < $tabcount; $i++) {
     $tabnames[$i]    = AttrVal($name, "dashboard_tab" . ($i + 1) . "name", "Dashboard-Tab " . ($i + 1));
     $tabsortings[$i] = AttrVal($name, "dashboard_tab" . ($i + 1) . "sorting", "");
  }
  
  if ($disable == 1) { 
	  readingsSingleUpdate($hash, "state", "Disabled", 0 );
	  return "";
  }
 
  if ($debug == 1)                                     { $debugfield    = "edit"; }
  if ($showtabs eq "tabs-and-buttonbar-at-the-top")    { $showbuttonbar = "top"; }
  if ($showtabs eq "tabs-and-buttonbar-on-the-bottom") { $showbuttonbar = "bottom"; }
  if ($showbuttonbar eq "hidden")                      { $lockstate     = "lock"; }
  if ($activetab > $tabcount)                          { $activetab     = $tabcount; }

  $colwidth =~ tr/,/:/;
  if (not ($colheight =~ /^\d+$/))       { $colheight = 400; }
  if (not ($rowtopheight =~ /^\d+$/))    { $rowtopheight = 50; }
  if (not ($rowbottomheight =~ /^\d+$/)) { $rowbottomheight = 50; } 
 
  #------------------- Check dashboard_sorting on false content ------------------------------------
  for (my $i=0;$i<@tabsortings;$i++){ 
	 if (($tabsortings[$i-1] !~ /[0-9]+/ || $tabsortings[$i-1] !~ /:/ || $tabsortings[$i-1] !~ /,/  ) && ($tabsortings[$i-1] ne "," && $tabsortings[$i-1] ne "")) {
	     Log3 ($name, 3, "Dashboard $name - Value of attribut dashboard_tab".$i."sorting is wrong. Saved sorting can not be set. Fix Value or delete the Attribute. [".$tabsortings[$i-1]."]");
	 } else {
		 Log3 ($name, 5, "Dashboard $name - Sorting OK or Empty: dashboard_tab".$i."sorting");
     }	
  }
  #-------------------------------------------------------------------------------------------------
 
  if ($room ne "all") { 
      ############################ Set FHEM url to avoid hardcoding it in javascript ############################ 
	  $ret .= "<script type='text/javascript'>var fhemUrl = '".$FW_ME."';</script>";
 
 	  $ret .= "<div id=\"tabEdit\" class=\"dashboard-dialog-content dashboard-widget-content\" title=\"Dashboard-Tab\" style=\"display:none;\">\n";		
	  $ret .= "<div id=\"dashboard-dialog-tabs\" class=\"dashboard dashboard_tabs\">\n";	
	  $ret .= "<ul class=\"dashboard dashboard_tabnav\">\n";
	  $ret .= "<li class=\"dashboard dashboard_tab\"><a href=\"#tabs-1\">Current Tab</a></li>\n";
	  $ret .= "<li class=\"dashboard dashboard_tab\"><a href=\"#tabs-2\">Common</a></li>\n";
	  $ret .= "</ul>\n";	
	  $ret .= "<div id=\"tabs-1\" class=\"dashboard_tabcontent\">\n";
	  $ret .= "<table>\n";
	  $ret .= "<tr colspan=\"2\"><td><div id=\"tabID\"></div></td></tr>\n";		
	  $ret .= "<tr><td>Tabtitle:</td><td colspan=\"2\"><input id=\"tabTitle\" type=\"text\" size=\"25\"></td></tr>";
	  $ret .= "<tr><td>Tabicon:</td><td><input id=\"tabIcon\" type=\"text\" size=\"10\"></td><td><input id=\"tabIconColor\" type=\"text\" size=\"7\"></td></tr>";
	  # the method FW_multipleSelect seems not to be available any more in fhem
	  #$ret .= "<tr><td>Groups:</td><td colspan=\"2\"><input id=\"tabGroups\" type=\"text\" size=\"25\" onfocus=\"FW_multipleSelect(this)\" allvals=\"multiple,$dashboard_groupListfhem\" readonly=\"readonly\"></td></tr>";	
	  $ret .= "<tr><td>Groups:</td><td colspan=\"2\"><input id=\"tabGroups\" type=\"text\" size=\"25\"></td></tr>";	
	  $ret .= "<tr><td></td><td colspan=\"2\"><input type=\"checkbox\" id=\"tabActiveTab\" value=\"\"><label for=\"tabActiveTab\">This Tab is currently selected</label></td></tr>";	
	  $ret .= "</table>\n";
	  $ret .= "</div>\n";	
	  $ret .= "<div id=\"tabs-2\" class=\"dashboard_tabcontent\">\n";
	  $ret .= "Comming soon";
	  $ret .= "</div>\n";	
	  $ret .= "</div>\n";		
	  $ret .= "</div>\n";

	  $ret .= "<div id=\"dashboard_define\" style=\"display: none;\">$name</div>\n";
	  $ret .= "<table class=\"roomoverview dashboard\" id=\"dashboard\">\n";

	  $ret .= "<tr style=\"height: 0px;\"><td><div class=\"dashboardhidden\">\n"; 
	  $ret .= "<input type=\"$debugfield\" size=\"100%\" id=\"dashboard_attr\" value=\"$name,$dbwidth,$showhelper,$lockstate,$showbuttonbar,$colheight,$showtogglebuttons,$colcount,$rowtopheight,$rowbottomheight,$tabcount,$activetab,$colwidth,$showfullsize,$customcss,$flexible\">\n";
	  $ret .= "<input type=\"$debugfield\" size=\"100%\" id=\"dashboard_jsdebug\" value=\"\">\n";
	  $ret .= "</div></td></tr>\n"; 
	  $ret .= "<tr><td><div id=\"dashboardtabs\" class=\"dashboard dashboard_tabs\" style=\"background: ".($backgroundimage ? "url(/fhem/images/" .FW_iconPath($backgroundimage).")" : "")." no-repeat !important;\">\n";  

	  ########################### Dashboard Tab-Liste ##############################################
	  $ret .= "	<ul id=\"dashboard_tabnav\" class=\"dashboard dashboard_tabnav dashboard_tabnav_".$showbuttonbar."\">\n";	   		
	  for (my $i=0;$i<$tabcount;$i++) {
          $ret .= "<li class=\"dashboard dashboard_tab dashboard_tab_".$showbuttonbar."\"><a href=\"#dashboard_tab".$i."\">".trim($tabnames[$i])."</a></li>";
      }
	  $ret .= "	</ul>\n"; 	 
	  ########################################################################################
	 
	  for (my $t=0;$t<$tabcount;$t++) { 
	 	 if ($t == $activetab - 1) {
		 	 $ret .= Dashboard_BuildDashboardTab($t, $name);
		 }
	  }
	  $ret .= "</div></td></tr>\n";
	  $ret .= "</table>\n";
      
  } else { 
      $ret .= "<table>";
	  $ret .= "<tr><td><div class=\"devType\">".$hash->{TYPE}."</div></td></tr>";
	  $ret .= "<tr><td><table id=\"TYPE_".$hash->{TYPE}."\" class=\"block wide\">";
	  $ret .= "<tbody><tr>";   
	  $ret .= "<td><div><a href=\"$FW_ME?detail=$name\">$name</a></div></td>";
	  $ret .= "<td><div>".$hash->{STATE}."</div></td>";	
	  $ret .= "</tr></tbody>";
	  $ret .= "</table></td></tr>";
	  $ret .= "</table>";
  }
 
return $ret; 
}

#############################################################################################
#           Dashboard Tabs erstellen
#############################################################################################
sub Dashboard_BuildDashboardTab ($$) {
	my ($t, $name) = @_;
    my $hash = $defs{$name};

	my $id              = $hash->{NR};
	my $colcount        = AttrVal($name, 'dashboard_tab'.($t + 1).'colcount', AttrVal($name, "dashboard_colcount", 1));
	my $colwidths       = AttrVal($name, 'dashboard_tab'.($t + 1).'rowcentercolwidth', AttrVal($name, "dashboard_rowcentercolwidth", 100));
    $colwidths          =~ tr/,/:/;
	my $backgroundimage = AttrVal($name, 'dashboard_tab'.($t + 1).'backgroundimage', "");
	my $row             = AttrVal($name, "dashboard_row", "center");
    my $tabgroups       = AttrVal($name, "dashboard_tab".($t + 1)."groups", "");
    my $tabsortings     = AttrVal($name, "dashboard_tab".($t + 1)."sorting", "");
    my $tabdevicegroups = AttrVal($name, "dashboard_tab".($t + 1)."devices", "");
    my $tabcount        = Dashboard_GetTabCount($hash, 1);

	unless ($tabgroups || $tabdevicegroups) { 
		readingsSingleUpdate($hash, "state", "No Groups or devices set", 0);
		return "";
	}
	
    my @temptabdevicegroup = split(' ', $tabdevicegroups);
    my @tabdevicegroups    = ();

	# make sure device groups without a group name are splitted into
	# separate groups for every device they are containing
    for my $devicegroup (@temptabdevicegroup) {
        my @groupparts = split(':', $devicegroup);
        if (@groupparts == 1) {
            my @devices = map { $_ . '$$$' . $_ } devspec2array($groupparts[0]);
            push(@tabdevicegroups, @devices);
        } else {
            push(@tabdevicegroups, $devicegroup);
        }
    }

	my $groups       = Dashboard_GetGroupList();
    $groups          =~ s/#/ /g;
    my @groups       = split(',', $groups);
    my @temptabgroup = split(",", $tabgroups);
	
    # resolve group names from regular expressions
	for (my $i=0;$i<@temptabgroup;$i++) {
	    my @stabgroup = split(":", trim($temptabgroup[$i]));		
		my @index = grep { $groups[$_] eq $stabgroup[0] } (0 .. @groups-1);

        if (@index == 0) {
			my $matchGroup = '^'.$stabgroup[0] . '$';
			@index = grep { $groups[$_] =~ m/$matchGroup/ } (0 .. @groups-1);
		}

		if (@index > 0) {
			for (my $j=0; $j<@index;$j++) {
				my $groupname = @groups[$index[$j]];
				$groupname .= '$$$'.'a:group='.$groupname;
				if (@stabgroup > 1) {
					$groupname .= '$$$'.$stabgroup[1];
				}
				push(@tabdevicegroups,$groupname);
			}
		}
	}

    $tabgroups = join('§§§', @tabdevicegroups);

    # add sortings for groups not already having a defined sorting
    for (my $i=0;$i<@tabdevicegroups;$i++) {
		my @stabgroup = split(/\$\$\$/, trim($tabdevicegroups[$i]));		
		my $matchGroup = ",".quotemeta(trim($stabgroup[0])).",";

		if ($tabsortings !~ m/$matchGroup/) {
			$tabsortings = $tabsortings."t".$t."c".Dashboard_GetMaxColumnId($row,$colcount).",".trim($stabgroup[0]).",true,0,0:";
		}
	}

	my $ret = "	<div id=\"dashboard_tab".$t."\" data-tabwidgets=\"".$tabsortings."\" data-tabcolwidths=\"".$colwidths."\" class=\"dashboard dashboard_tabpanel\" style=\"background: " . ($backgroundimage ? "url(/fhem/images/" . FW_iconPath($backgroundimage) . ")" : "none") . " no-repeat !important;\">\n";
	$ret   .= " <ul class=\"dashboard_tabcontent\">\n";
	$ret   .= "	<table class=\"dashboard_tabcontent\">\n";
    
	##################### Top Row (only one Column) #############################################
	if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "top"){
		$ret .= Dashboard_BuildDashboardTopRow($name,$t,$id,$tabgroups,$tabsortings);
	}
	##################### Center Row (max. 5 Column) ############################################
	if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "center-bottom" || $row eq "center") {
		$ret .= Dashboard_BuildDashboardCenterRow($name,$t,$id,$tabgroups,$tabsortings,$colcount);
	}
	############################# Bottom Row (only one Column) ############################################
	if ($row eq "top-center-bottom" || $row eq "center-bottom" || $row eq "bottom"){
		$ret .= Dashboard_BuildDashboardBottomRow($name,$t,$id,$tabgroups,$tabsortings);
	}
	 
	$ret .= "	</table>\n";
	$ret .= " 	</ul>\n";
	$ret .= "	</div>\n";

return $ret;
}

#############################################################################################
#           Oberste Zeile erstellen
#############################################################################################
sub Dashboard_BuildDashboardTopRow ($$$$$) {
  my ($name,$t,$id, $devicegroups, $groupsorting) = @_;
  my $ret; 
  
  $ret .= "<tr><td  class=\"dashboard_row\">\n";
  $ret .= "<div id=\"dashboard_rowtop_tab".$t."\" class=\"dashboard dashboard_rowtop\">\n";
  $ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column100\">\n";
  $ret .= Dashboard_BuildGroupWidgets($name,$t,"100",$id,$devicegroups,$groupsorting); 
  $ret .= "		</div>\n";
  $ret .= "</div>\n";
  $ret .= "</td></tr>\n";
 
return $ret;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_BuildDashboardCenterRow ($$$$$$) {
  my ($name,$t,$id, $devicegroups, $groupsorting, $colcount) = @_;

  my $ret = "<tr><td  class=\"dashboard_row\">\n";
  $ret   .= "<div id=\"dashboard_rowcenter_tab".$t."\" class=\"dashboard dashboard_rowcenter\">\n";

  my $currentcol  = $colcount;
  my $maxcolindex = $colcount - 1;
  my $replace     = "t" . $t . "c" . $maxcolindex . ",";

  # replace all sortings referencing not existing columns
  # this does only work if there is no empty column inbetween
  while (index($groupsorting, "t".$t."c".$currentcol.",") >= 0) {
      my $search     = "t" . $t . "c" . $currentcol . ",";
      $groupsorting  =~ s/$search/$replace/g;
      $currentcol++;
  }

  for (my $i=0;$i<$colcount;$i++){
	  $ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column".$i."\">\n";
	  $ret .= Dashboard_BuildGroupWidgets($name,$t,$i,$id,$devicegroups,$groupsorting); 
	  $ret .= "		</div>\n";
  }
  $ret .= "</div>\n";
  $ret .= "</td></tr>\n";
 
return $ret;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_BuildDashboardBottomRow ($$$$$) {
  my ($name,$t,$id, $devicegroups, $groupsorting) = @_;
  my $ret; 
  $ret .= "<tr><td  class=\"dashboard_row\">\n";
  $ret .= "<div id=\"dashboard_rowbottom_tab".$t."\" class=\"dashboard dashboard_rowbottom\">\n";
  $ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column200\">\n";
  $ret .= Dashboard_BuildGroupWidgets($name,$t,"200",$id,$devicegroups,$groupsorting); 
  $ret .= "		</div>\n";
  $ret .= "</div>\n";
  $ret .= "</td></tr>\n";

return $ret;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_BuildGroupWidgets ($$$$$$) {
  my ($name,$tab,$column,$id,$devicegroups,$groupsorting) = @_;
  my $ret = "";

  my $counter    = 0;
  my %sorting    = ();
  my %groups     = ();
  my @groupnames = ();

  foreach (split(":", $groupsorting)) {
      my @parts = split (',', $_);
      $sorting{$parts[1]} = $_;
      # add group names to a list to have the correct order afterwards in the foreach loop
      # store the group names in the right order to use them in the foreach loop
      push(@groupnames, $parts[1]);
  }

  my @devicegroups = split('§§§', $devicegroups);

  # sort the devices into a hash to be able to access them via group name
  foreach my $singlegroup (@devicegroups) {
      # make sure that splitting with colon is not destroying the devspec that might
	  # also contain a colon followed by a filter
      my ($groupname, $groupdevices, $groupicon) = split(/\$\$\$/, $singlegroup);

      my @values = ($groupdevices, $groupicon);
          $groups{$groupname} = \@values;
      }

	  my $groupicon = ''; 

      foreach my $groupname (@groupnames) {
          next if (!defined($groups{$groupname}));
          my ($groupdevices, $groupicon) = @{$groups{$groupname}};

          # if the device is not stored in the current column, skip it
          next if (index($sorting{$groupname}, 't'.$tab.'c'.$column) < 0);
	      my $groupId    = $id."t".$tab."c".$column."w".$counter;

	      $ret .= Dashboard_BuildGroup($name,$groupname,$groupdevices,$sorting{$groupname},$groupId,$groupicon);
          $counter++;
      }
		
return $ret; 
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_BuildGroupList ($) {
  my @dashboardgroups = split(",", $_[0]); #array for all groups to build an widget
  my %group = ();
 
  foreach my $d (sort keys %defs) {
      foreach my $grp (split(",", AttrVal($d, "group", ""))) {
	      $grp = trim($grp);
		  foreach my $g (@dashboardgroups){ 
		      my ($gtitle, $iconName) = split(":", trim($g));
			  my $titleMatch = "^" . quotemeta($gtitle) . "\$";
			  $group{$grp}{$d} = 1 if($grp =~ $titleMatch); 			
		  }
      }
  }  
 
return %group;
}  

#############################################################################################
#           
#############################################################################################
sub Dashboard_GetGroupList() {
  my %allGroups = ();
  foreach my $d (keys %defs ) {
      next if(IsIgnored($d));
      foreach my $g (split(",", AttrVal($d, "group", ""))) { $allGroups{$g}{$d} = 1; }
  }  
  my $ret = join(",", sort map { $_ =~ s/ /#/g ;$_} keys %allGroups);
  
return $ret;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_BuildGroup ($$$$$$) {
  my ($name,$groupname,$devices,$sorting,$groupId,$icon) = @_; 
  my $row          = 1;
  my %extPage      = ();
  my $foundDevices = 0;
  my $replaceGroup = "";
  my $ret          = "";
 
  my $rf = ($FW_room ? "&amp;room=$FW_room" : "");                             # stay in the room
  
  $ret .= "<div class=\"dashboard dashboard_widget ui-widget\" data-groupwidget=\"".$sorting."\" id=\"".$groupId."\">\n";
  $ret .= "<div class=\"dashboard_widgetinner\">\n";	

  if ($groupname && $groupname ne $devices) {
      $ret .= "<div class=\"dashboard_widgetheader ui-widget-header dashboard_group_header\">";
	  if ($icon) {
	      $ret.= FW_makeImage($icon,$icon,"dashboard_group_icon");
      }
      $ret .= $groupname."</div>\n";
  }
  $ret .= "<div data-userheight=\"\" class=\"dashboard_content\">\n";
  $ret .= "<table class=\"dashboard block wide\" id=\"TYPE_$groupname\">";

  my %seen;
  
  # make sure devices are not contained twice in the list
  my @devices = grep { !$seen{$_}++ } devspec2array($devices);
  
  # sort the devices in alphabetical order by sortby, alias, name
  @devices = sort { lc(AttrVal($a,'sortby',AttrVal($a,'alias',$a))) cmp lc(AttrVal($b,'sortby',AttrVal($b,'alias',$b))) } @devices;

  foreach my $d (@devices) {	
      next if (!defined($defs{$d}));
      $foundDevices++;

	  $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
		
	  my $type    = $defs{$d}{TYPE};
	  my $devName = AttrVal($d, "alias", $d);
	  my $icon    = AttrVal($d, "icon", "");
	  $icon       = FW_makeImage($icon,$icon,"icon dashboard_groupicon")."&nbsp;" if($icon);
      $devName    = "" if($modules{$defs{$d}{TYPE}}{FW_hideDisplayName});                    # Forum 88667
      
	  if (!$modules{$defs{$d}{TYPE}}{FW_atPageEnd}) {                                        # Don't show Link for "atEnd"-devices
	      if(AttrVal($name, "dashboard_noLinks", 0)) {
              $ret .= "<td>$icon$devName</td>";                                              # keine Links zur Detailansicht des Devices
          } else {
              $ret .= FW_pH ("detail=$d", "$icon$devName", 1, "col1", 1);                    # FW_pH = add href (<link>, <Text>, <?>, <class>, <Wert zurückgeben>, <?>)
          } 
      }	     
		
	  $row++;		
			
      $extPage{group}               = $groupname;
	  my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf, \%extPage);
	  $allSets                      = FW_widgetOverride($d, $allSets);
		
	  ##############   Customize Result for Special Types #####################
	  my @txtarray = split(">", $txt);				
      if ($modules{$defs{$d}{TYPE}}{FW_atPageEnd}) {
	      no strict "refs"; 
		  my $devret = &{$modules{$defs{$d}{TYPE}}{FW_summaryFn}}($FW_wname, $d, $FW_room, \%extPage);
 		  $ret      .= "<td class=\"dashboard_dev_container\"";
		  if ($devret !~ /informId/i) {
		      $ret .= " informId=\"$d\"";
  		  }
		  $ret .= ">$devret</td>";
		  use strict "refs"; 
	  
      } else  {
		  $ret .= "<td informId=\"$d\">$txt</td>";
	  }

	  ##############   Commands, slider, dropdown   #####################
	  my $smallscreenCommands = AttrVal($FW_wname, "smallscreenCommands", "");
	  if((!$FW_ss || $smallscreenCommands) && $cmdlist) {	
	      my @a = split("[: ]", AttrVal($d, "cmdIcon", ""));
		  my %cmdIcon = @a;
		  foreach my $cmd (split(":", $cmdlist)) {
		      my $htmlTxt;
			  my @c = split(' ', $cmd);
			  if(int(@c) && $allSets && $allSets =~ m/\b$c[0]:([^ ]*)/) {
			      my $values = $1;
				  foreach my $fn (sort keys %{$data{webCmdFn}}) {
				      no strict "refs";
					  $htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname, $d, $FW_room, $cmd, $values);
					  use strict "refs";
					  last if(defined($htmlTxt));
				  }	
			  }
			  if($htmlTxt) {
			      # add colspan to avoid squeezed table cells
				  $htmlTxt =~ s/<td>/<td colspan="10">/;
				  $ret .= $htmlTxt;
			  } else {
				  my $nCmd = $cmdIcon{$cmd} ?
                  FW_makeImage($cmdIcon{$cmd},$cmd,"webCmd") : $cmd;
				  $ret .= FW_pH "cmd.$d=set $d $cmd$rf", $nCmd, 1, "col3", 1;
			  }
		  }
	  }
	  $ret .= "</tr>";
      if(AttrVal($name, "dashboard_noLinks", 0)) {   
          $ret   =~ s/(<a\s+href="\/fhem\?detail=$d">(.*)<\/a>)/$2/s;           # keine Links zur Detailansicht des Devices
      }
  }
	
  $ret .= "</table>";
  $ret .= "    </div>\n";	
  $ret .= "   </div>\n";	
  $ret .= "  </div>\n";

  if (!$foundDevices) { 
      $ret .= "<table class=\"block wide\" id=\"TYPE_unknowngroup\">";
	  $ret .= "<tr class=\"odd\"><td class=\"changed\">Devices for group not found: $groupname</td></tr>";
	  $ret .= "<tr class=\"even\"><td class=\"changed\">Check if the device/group attribute is really set</td></tr>";
	  $ret .= "<tr class=\"odd\"><td class=\"changed\">Check if the device spec is correctly written</td></tr>";
	  $ret .= "</table>"; 	
  }

return $ret;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_GetMaxColumnId ($$) {
  my ($row, $colcount) = @_;
  my $maxcolid         = "0";
	
  if (index($row,"bottom") > 0)    { $maxcolid = "200"; } 
  elsif (index($row,"center") > 0) { $maxcolid = $colcount-1; } 
  elsif (index($row,"top") > 0)    { $maxcolid = "100"; }

return $maxcolid;
}

#############################################################################################
#           
#############################################################################################
sub Dashboard_CheckDashboardEntry ($) {
  my ($hash)     = @_;
  my $now        = time();
  my $timeToExec = $now + 5;
	
  RemoveInternalTimer($hash);
  InternalTimer      ($timeToExec, 'Dashboard_CheckDashboardAttributUssage', $hash, 0);
  
return;
}

#############################################################################################
# replaces old disused attributes and their values | set minimal attributes
#############################################################################################
sub Dashboard_CheckDashboardAttributUssage($) { 
  my ($hash) = @_;
  my $d                = $hash->{NAME};
  my $dashboardversion = $hash->{HELPER}{VERSION};
  my $detailnote       = "";
 
  # --------- Set minimal Attributes in the hope to make it easier for beginners --------------------
  my $tab1groups = AttrVal($d, "dashboard_tab1groups", "<noGroup>");
  if ($tab1groups eq "<noGroup>") { 
      FW_fC("attr ".$d." dashboard_tab1groups Set your FHEM groups here and arrange them on tab 1"); 
  }

  # ---------------- Delete empty Groups entries ---------------------------------------------------------- 
  my $tabgroups = AttrVal($d, "dashboard_tab1groups", "999");
  if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab1groups"); }
  $tabgroups = AttrVal($d, "dashboard_tab2groups", "999");
  if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab2groups"); } 
  $tabgroups = AttrVal($d, "dashboard_tab3groups", "999");
  if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab3groups"); }  
  $tabgroups = AttrVal($d, "dashboard_tab4groups", "999");
  if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab4groups"); }   
  $tabgroups = AttrVal($d, "dashboard_tab5groups", "999");
  if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab5groups"); }   
  
  my $lockstate = AttrVal($d, "dashboard_lockstate", "");                  # outdates 04.2014
  if ($lockstate ne "") {
      { FW_fC("deleteattr ".$d." dashboard_lockstate"); }
      Log3 ($d, 3, "Dashboard $d - Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [dashboard_lockstate]");
  } 
  my $showhelper = AttrVal($d, "dashboard_showhelper", "");                # outdates 04.2014 
  if ($showhelper ne "") {
      { FW_fC("deleteattr ".$d." dashboard_showhelper"); }
	  Log3 $hash, 3, "[".$d. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [dashboard_showhelper]";
  }  
  my $showtabs = AttrVal($d, "dashboard_showtabs", "");                    # delete values 04.2014 
  if ($showtabs eq "tabs-at-the-top-buttonbar-hidden") {
      { FW_fC("set ".$d." dashboard_showtabs tabs-and-buttonbar-at-the-top"); }
	  Log3 $hash, 3, "[".$d. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [tabs-at-the-top-buttonbar-hidden]";
  }
  if ($showtabs eq "tabs-on-the-bottom-buttonbar-hidden") {
      { FW_fC("set ".$d." dashboard_showtabs tabs-and-buttonbar-on-the-bottom"); } 
	  Log3 $hash, 3, "[".$d. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [tabs-on-the-bottom-buttonbar-hidden]";
  }  
  
return;
}

#############################################################################################
#           Anzahl der vorhandenen Tabs ermitteln und zurück geben
#############################################################################################
sub Dashboard_GetTabCount ($$) {
  my ($hash, $defaultTabCount) = @_;
  my $tabCount = 0;

  while (AttrVal($hash->{NAME}, 'dashboard_tab' . ($tabCount + 1) . 'groups', '') ne ""
        || AttrVal($hash->{NAME}, 'dashboard_tab' . ($tabCount + 1) . 'devices', '') ne "") {
      $tabCount++;
  }

return $tabCount ? $tabCount : $defaultTabCount;
}

#############################################################################################
#           Aktives Tab selektieren 
#           $gtn setzen um Tabnamen mit abzurufen
#############################################################################################
sub Dashboard_GetActiveTab ($;$) {
  my ($name,$gtn) = @_;

  my $maxTab = Dashboard_GetTabCount($defs{$name}, 1);
  my $activeTab = 1;
  
  foreach my $key (%FW_httpheader) {
      Log3 ($name, 5, "Dashboard $name - FW_httpheader $key: ".$FW_httpheader{$key}) if(defined $FW_httpheader{$key});
  }
  
  if (defined($FW_httpheader{Cookie})) {
      Log3 ($name, 4, "Dashboard $name - Cookie set: ".$FW_httpheader{Cookie});
      my %cookie = map({ split('=', $_) } split(/; */, $FW_httpheader{Cookie}));
      if (defined($cookie{dashboard_activetab})) {
          $activeTab = $cookie{dashboard_activetab};
          $activeTab = ($activeTab <= $maxTab)?$activeTab:$maxTab;
      }
  }
  
  my $tabno   = AttrVal($name, 'dashboard_homeTab', $activeTab);
  $tabno      = ($tabno <= $maxTab)?$tabno:$maxTab;
  my $tabname = AttrVal($name, "dashboard_tab".($tabno)."name", "");
  
  Log3 ($name, 4, "Dashboard $name - Dashboard active tab: $tabno/$tabname");

  if($gtn) {
      return ($tabno,$tabname);
  } else {
      return $tabno;
  }
}

#############################################################################################
#           Wertevorrat der möglichen Tabs ermitteln
#############################################################################################
sub Dashboard_possibleTabs ($) {
  my ($name) = @_;
  my $f;

  my $maxTab = Dashboard_GetTabCount($defs{$name}, 1);
  for my $i (1..$maxTab) { 
      $f .= "," if($f);
      $f .= $i;
  }

return $f;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub Dashboard_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %Dashboard_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {   # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;                                    # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                      # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                         # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {                  # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );   # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden                                       
      }
  } else {
	  $hash->{VERSION} = $v;                                                      # herkömmliche Modulstruktur
  }
  
return;
}

#############################################################################################
#  Tabumschaltung bei setzen Attribut dashboard_homeTab bzw. "set ... activeTab"
#############################################################################################
sub Dashboard_activateTab ($$) {
  my ($name,$tab) = @_;
  my $hash        = $defs{$name};
  
  my $url = '/dashboard/'.$name;
  return if(!$data{FWEXT}{$url});
  
  $tab--;
  my $web = AttrVal($name, "dashboard_webRefresh", $hash->{HELPER}{FW});
  my @wa  = split(",", $web);
  
  { map { FW_directNotify("#FHEMWEB:$_", 'dashboard_load_tab('."$tab".');$("#dashboardtabs").tabs("option", "active", '."$tab".')', "") } @wa }
  
  # Andere Triggermöglichkeiten:
  #{ map { FW_directNotify("#FHEMWEB:$_", 'dashboard_load_tab('."$tab".')', "") } @wa }
  #{ map { FW_directNotify("#FHEMWEB:$_", '$("#dashboardtabs").tabs("option", "active", '."$tab".')', "") } @wa }
  # CommandTrigger(undef,'WEB  JS:dashboard_load_tab('."$tab".');JS:$("#dashboardtabs").tabs("option", "active", '."$tab".')' );

return;
}

######################################################################################
#                   initiale Routinen für Dashboard
######################################################################################
sub Dashboard_init ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "Dashboard_init");
  
  if ($init_done == 1) {
      # die Argumente für das Attribut dashboard_webRefresh dynamisch ermitteln und setzen
      my $fwd = join(",",devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized")); 
      $hash->{HELPER}{FW} = $fwd;
      my $atr = $attr{$name}{dashboard_webRefresh};
      delFromDevAttrList($name, "dashboard_webRefresh");
      addToDevAttrList  ($name, "dashboard_webRefresh:multiple-strict,$fwd");
	  $attr{$name}{dashboard_webRefresh} = $atr if($atr);
	  
      # die Argumente für das Attribut dashboard_homeTab dynamisch ermitteln und setzen
      my $f  = Dashboard_possibleTabs ($name);
      my $at = $attr{$name}{dashboard_homeTab};
      delFromDevAttrList($name, "dashboard_homeTab");
      addToDevAttrList  ($name, "dashboard_homeTab:$f");
      $attr{$name}{dashboard_homeTab} = $at if($at);
  
  } else {
      InternalTimer(time()+3, "Dashboard_init", $hash, 0);
  }
  
return;
}

######################################################################################
#                   Zeichen escapen
######################################################################################
sub Dashboard_Escape($) {
  my $a = shift;
  return "null" if(!defined($a));
  my %esc = ("\n" => '\n', "\r" => '\r', "\t" => '\t', "\f" => '\f', "\b" => '\b', "\"" => '\"', "\\" => '\\\\', "\'" => '\\\'', );
  $a      =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/eg;
  
return $a;
}

1;

=pod
=encoding utf8
=item summary    Dashboard for showing multiple devices sorted in tabs
=item summary_DE Dashboard zur Anzeige mehrerer Geräte in verschiedenen Tabs
=begin html

<a name="Dashboard"></a>
<h3>Dashboard</h3>
<ul>
  Creates a Dashboard in any group and/or devices can be arranged. The positioning may depend the objects and column width are made
  arbitrarily by drag'n drop. Also, the width and height of an object can be increased beyond the minimum size. <br><br>
  
  <b>Note: </b><br>
  A group name in the dashboard respectively the attribute "dashboard_tabXgroups" equates the group name in FHEM and depict the 
  devices which are contained in that group.
  <br> 
  <br>
  
  <a name="Dashboarddefine"></a>
  <b>Define</b>
  <br><br>
  
  <ul>
  <ul>
    <li><b>define &lt;name&gt; Dashboard </b>
	<br><br>
    <b>Example: </b><br>
    define anyViews Dashboard
    <br><br>
	
    <b>Bestpractice beginner configuration: </b>
	<br>
	define anyViews Dashboard<br>
	attr anyViews dashboard_colcount 2<br>
	attr anyviews dashboard_rowcentercolwidth 30,70<br>
	attr anyViews dashboard_tab1groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
  </ul>
  </ul>
  </li>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b>
  <br><br>
  
  <ul>
  <ul>
  
    <li><b>set &lt;name&gt; activateTab &lt;TabNo&gt; </b><br>
	The Tab with the defined number will be activated. 
	If the attribute "dashboard_homeTab" is set, this defined tab will be reactivated at next 
	browser refresh. <br>
    <br>
    </li>
  
    <li><b>set &lt;name&gt; lock </b><br>
	Locks the Dashboard so that no position changes can be made. 
    </li><br>
	
    <li><b>set &lt;name&gt; unlock </b><br>
    Unlock the Dashboard,
    <br>
    </li>
  </ul>
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <b>Get</b> 
  <ul>
  <ul>

    <a name="config"></a>
    <li><b>get &lt;name&gt; config </b><br>
	Delivers the configuration of the dashboard back. <br>
    <br>
    </li>
    
    <a name="icon"></a>
    <li><b>get &lt;name&gt; icon &lt;icon name&gt; </b><br>
	Delivers the path and full name of the denoted icon back. <br><br>
    
    <b>Example: </b><br>
    get &lt;name&gt; icon measure_power_meter
    <br>
    </li>

  </ul>
  </ul>
  <br>
  <br>
  
  <a name="Dashboardattr"></a>
  <b>Attributes</b> 
  <br>
  <br>
  
  <ul>
  <ul>    
        
    <a name="dashboard_backgroundimage"></a>		
    <li><b>dashboard_backgroundimage </b><br>
        Displays a background image for the complete dashboard. The image is not stretched in any way so the size should 
        match/extend the dashboard height/width.
    </li><br>
    
    <a name="dashboard_colcount"></a>	
    <li><b>dashboard_colcount </b><br>
        Number of columns in which the groups can be displayed. Nevertheless, it is possible to have multiple groups <br>
        to be positioned in a column next to each other. This is depend on the width of columns and groups. <br>
        Default: 1
    </li>
    <br>
	
    <a name="dashboard_debug"></a>		
    <li><b>dashboard_debug </b><br>
        Show Hiddenfields. Only for Maintainer's use.<br>
        Default: 0
    </li>
    <br>
    
    <a name="dashboard_flexible"></a>		
    <li><b>dashboard_flexible </b><br>
        If set to a value > 0, the widgets are not positioned in columns any more but can be moved freely to any position in 
        the tab.<br/>
        The value for this parameter also defines the grid, in which the position "snaps in".
        Default: 0
    </li><br>
	
    <a name="dashboard_homeTab"></a>
    <li><b>dashboard_homeTab </b><br>
        Specifies which tab is activated. If it isn't set, the last selected tab will also be the active tab. (Default: 1)
    </li><br>
    
    <a name="dashboard_row"></a>	
    <li><b>dashboard_row </b><br>
        To select which rows are displayed. top only; center only; bottom only; top and center; center and bottom; top,center and bottom.<br>
        Default: center
    </li><br>
    
    <a name="dashboard_rowbottomheight"></a>	
    <li><b>dashboard_rowbottomheight </b><br>
        Height of the bottom row in which the groups may be positioned.<br>
        Default: 250
    </li><br>
    
    <a name="dashboard_rowcenterheight"></a>	
    <li><b>dashboard_rowcenterheight </b><br>
        Height of the center row in which the groups may be positioned. <br> 		
        Default: 400		
    </li><br>
    
    <a name="dashboard_rowcentercolwidth"></a>	
    <li><b>dashboard_rowcentercolwidth </b><br>
        About this attribute, the width of each column of the middle Dashboardrow can be set. It can be stored for each column 
        a separate value. 
        The values ​​must be separated by a comma (no spaces). Each value determines the column width in%! The first value 
        specifies the width of the first column, the second value of the width of the second column, etc. Is the sum of the 
        width greater than 100 it is reduced. 
        If more columns defined as widths the missing widths are determined by the difference to 100. However, are less 
        columns are defined as the values ​​of ignores the excess values​​.<br>
        Default: 100
    </li><br>
    
    <a name="dashboard_rowtopheight"></a>	
    <li><b>dashboard_rowtopheight </b><br>
        Height of the top row in which the groups may be positioned. <br>
        Default: 250
    </li><br>
	
    <a name="dashboard_showfullsize"></a>	
    <li><b>dashboard_showfullsize </b><br>
        Hide FHEMWEB Roomliste (complete left side) and Page Header if Value is 1.<br>
        Default: 0
    </li><br>	
	
    <a name="dashboard_showtabs"></a>	
    <li><b>dashboard_showtabs </b><br>
        Displays the Tabs/Buttonbar on top or bottom, or hides them. If the Buttonbar is hidden lockstate is "lock" is used.<br>
        Default: tabs-and-buttonbar-at-the-top
    </li><br>
    
    <a name="dashboard_showtogglebuttons"></a>		
    <li><b>dashboard_showtogglebuttons </b><br>
        Displays a Toogle Button on each Group do collapse.<br>
        Default: 0
    </li><br>
    
    <a name="dashboard_tab1name"></a>
    <li><b>dashboard_tab1name </b><br>
        Title of Tab. (also valid for further dashboard_tabXname)
    </li><br>
    
    <a name="dashboard_tab1sorting"></a>	
    <li><b>dashboard_tab1sorting </b><br>
        Contains the position of each group in Tab. (also valid for further dashboard_tabXsorting) <br>
		Value is written by the "Set" button. It is not recommended to take manual changes.
    </li><br>
    
    <a name="dashboard_tab1groups"></a>	
    <li><b>dashboard_tab1groups </b><br>
        Comma separated list of FHEM groups (see attribute "group" in a device) to be displayed in Tab. 
		(also valid for further dashboard_tabXgroups) <br>
        Each group can be given an icon for this purpose the group name, the following must be 
        completed ":&lt;icon&gt;@&lt;color&gt;" <br><br>
        
        <b>Example: </b><br>
        Light:Icon_Fisch@blue,AVIcon_Fisch@red,Single Lights:Icon_Fisch@yellow <br><br>
        
        Additionally a group can contain a regular expression to show all groups matching a criteria. <br><br>
        
        <b>Example: </b><br>
        .*Light.* to show all groups that contain the string "Light"
    </li><br>
    
    <a name="dashboard_tab1devices"></a>	
    <li><b>dashboard_tab1devices </b><br>
        DevSpec list of devices that should appear in the tab. (also valid for further dashboard_tabXdevices) <br>
		The format is: <br><br>
		<ul>
            GROUPNAME:devspec1,devspec2,...,devspecX:ICONNAME <br><br>
	    </ul>        
        ICONNAME is optional. Also GROUPNAME is optional. In case of missing GROUPNAME, the matching devices are 
        not grouped, but shown as separate widgets without titles. 
        For further details on the DevSpec format see <a href="#devspec">DevSpec</a>.
    </li><br>
    
    <a name="dashboard_tab1icon"></a>	
    <li><b>dashboard_tab1icon </b><br>
        Set the icon for a Tab. (also valid for further dashboard_tabXicon) <br>
		There must exist an icon with the name ico.(png|svg) in the modpath directory. If the image is 
        referencing an SVG icon, then you can use the @colorname suffix to color the image. 
    </li><br>
    
    <a name="dashboard_tab1colcount"></a>	
    <li><b>dashboard_tab1colcount </b><br>
        Number of columns for a specific tab in which the groups can be displayed. (also valid for further dashboard_tabXcolcount) <br>
		Nevertheless, it is possible to have multiple groups to be positioned in a column next to each other. 
		This depends on the width of columns and groups. <br>
        Default: &lt;dashboard_colcount&gt;
    </li><br>
	
    <a name="dashboard_tab1backgroundimage"></a>	
    <li><b>dashboard_tab1backgroundimage </b><br>
        Shows a background image for the tab. (also valid for further dashboard_tabXbackgroundimage) <br> 
		The image is not stretched in any way, it should therefore match the tab size or extend it.
    </li><br>		
    
    <a name="dashboard_noLinks"></a>
    <li><b>dashboard_noLinks</b><br>
      No link generation to the detail view of the devices takes place. <br><br>

      <b>Note: </b><br>
      Some device types deliver the links to their detail view integrated in the device. 
      In such cases you have to deactivate the link generation inside of the device (for example in SMAPortalSPG).      
    </li>
    <br>
	
    <a name="dashboard_webRefresh"></a>	
    <li><b>dashboard_webRefresh </b><br>
      With this attribute the FHEMWEB-Devices are determined, which: <br><br>
	  <ul>
        <li> are activating the tab of a dashboard when the attribute "dashboard_homeTab" will be set </li>
	    <li> are positioning to the tab specified by command "set &lt;name&gt; activateTab" </li>
	  </ul>
	  <br>
	  (default: all)
	  <br>
    </li>
    <br>
	
    <a name="dashboard_width"></a>	
    <li><b>dashboard_width </b><br>
        To determine the Dashboardwidth. The value can be specified, or an absolute width value (eg 1200) in pixels in% (eg 80%).<br>
        Default: 100%
    </li>
    <br>
    
  </ul>
  </ul>
  </ul>
  
=end html
=begin html_DE

<a name="Dashboard"></a>
<h3>Dashboard</h3>
<ul>
  Erstellt eine Übersicht in der Gruppen und/oder Geräte angeordnet werden können. Dabei können die Objekte mit Drag'n Drop 
  frei positioniert und in mehreren Spalten angeordnet werden. Auch kann die Breite und Höhe eines Objektes über die 
  Mindestgröße hinaus gezogen werden. <br><br>
  
  <b>Hinweis: </b><br>
  Ein Gruppenname im Dashboard bzw. dem Attribut "dashboard_tabXgroups" entspricht der Gruppe in FHEM und stellt die darin enthaltenen 
  Geräte im Dashboard dar.
  <br>
  <br> 
  
  <a name="Dashboarddefine"></a>
  <b>Define</b>
  <ul>
  <ul>
    <li><b>define &lt;name&gt; Dashboard </b><br>
	<br>
    <b>Beispiel: </b><br>
    define anyViews Dashboard
  <br>
  <br>
	
  <b>Bestpractice Anfängerkonfiguration: </b><br>
	define anyViews Dashboard<br>
	attr anyViews dashboard_colcount 2<br>
	attr anyViews dashboard_rowcentercolwidth 30,70<br>
	attr anyViews dashboard_tab1groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
  </li>
  </ul>
  </ul>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b> 
  <ul>
  <ul>
  
    <li><b>set &lt;name&gt; activateTab &lt;TabNo&gt; </b><br>
	Das Tab mit der angegebenen Nummer wird im Dashboard aktiviert.
    Ist das Attribut "dashboard_homeTab" gesetzt, wird das in diesem Attribut 
	definierte Tab beim nächsten Browser-Refresh reaktiviert. <br>
    <br>
    </li>
  
    <li><b>set &lt;name&gt; lock </b><br>
	Sperrt das Dashboard. Es können keine Positionsänderungen vorgenommen werden. <br>
    <br>
    </li>
    
	<li><b>set &lt;name&gt; unlock </b><br>
    Entsperrt das Dashboard.
    </li>
    <br>
  </ul>
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <b>Get</b> 
  <ul>
  <ul>
  
    <a name="config"></a>
    <li><b>get &lt;name&gt; config </b><br>
	Liefert die Konfiguration des Dashboards zurück. <br>
    <br>
    </li>
    
    <a name="icon"></a>
    <li><b>get &lt;name&gt; icon &lt;icon name&gt; </b><br>
	Liefert den Pfad und vollen Namen des angegebenen Icons zurück. <br><br>
    
    <b>Beispiel: </b><br>
    get &lt;name&gt; icon measure_power_meter
    <br>
    </li>
    
  </ul>
  </ul>
  <br>
  
  <a name="Dashboardattr"></a>
  <b>Attributes</b>
  <br>
  <br>
  <ul>
  <ul>	  
    
    <a name="dashboard_backgroundimage"></a>		
    <li><b>dashboard_backgroundimage </b><br>
        Zeig in Hintergrundbild im Dashboard an. Das Bild wird nicht gestreckt, es sollte daher auf die Größe des Dashboards 
        passen oder diese überschreiten.
    </li>
    <br>	
    
    <a name="dashboard_colcount"></a>	
    <li><b>dashboard_colcount </b><br>
        Die Anzahl der Spalten in der  Gruppen dargestellt werden können. Dennoch ist es möglich, mehrere Gruppen <br>
        in einer Spalte nebeneinander zu positionieren. Dies ist abhängig von der Breite der Spalten und Gruppen. <br>
        Gilt nur für die mittlere Spalte! <br>
        Standard: 1
    </li>
    <br>
    
    <a name="dashboard_debug"></a>		
    <li><b>dashboard_debug </b><br>
        Zeigt Debug-Felder an. Sollte nicht gesetzt werden!<br>
        Standard: 0
    </li>
    <br>	
    
    <a name="dashboard_flexible"></a>	
    <li><b>dashboard_flexible </b><br>
        Hat dieser Parameter  einen Wert > 0, dann können die Widgets in den Tabs frei positioniert werden und hängen nicht 
        mehr an den Spalten fest. Der Wert gibt ebenfalls das Raster an, in dem die Positionierung "zu schnappt".
        Standard: 0
    </li>
    <br>
	
    <a name="dashboard_homeTab"></a>	
    <li><b>dashboard_homeTab </b><br>
        Legt das aktuell aktivierte Tab fest. Wenn nicht gesetzt, wird das zuletzt gewählte Tab das aktive Tab. (Default: 1)
    </li>
    <br>
	
    <a name="dashboard_row"></a>	
    <li><b>dashboard_row </b><br>
        Auswahl welche Zeilen angezeigt werden sollen. top (nur Oben), center (nur Mitte), bottom (nur Unten) und den 
        Kombinationen daraus.<br>
        Standard: center
    </li>
    <br>	
	
    <a name="dashboard_rowcenterheight"></a>	
    <li><b>dashboard_rowcenterheight </b><br>
        Höhe der mittleren Zeile, in der die Gruppen angeordnet werden. <br>
        Standard: 400
    </li>
    <br>
    
    <a name="dashboard_rowcentercolwidth"></a>	
    <li><b>dashboard_rowcentercolwidth </b><br>
        Über dieses Attribut wird die Breite der einzelnen Spalten der mittleren Dashboardreihe festgelegt. Dabei kann je Spalte ein separater Wert hinterlegt werden. 
        Die Werte sind durch ein Komma (ohne Leerzeichen) zu trennen. Jeder Wert bestimmt die Spaltenbreite in %! Der erste Wert gibt die Breite der ersten Spalte an, 
        der zweite Wert die Breite der zweiten Spalte usw. Ist die Summe der Breite größer als 100 werden die Spaltenbreiten reduziert.
        Sind mehr Spalten als Breiten definiert werden die fehlenden Breiten um die Differenz zu 100 festgelegt. Sind hingegen weniger Spalten als Werte definiert werden 
        die überschüssigen Werte ignoriert.<br>
        Standard: 100
    </li>
    <br>
    
    <a name="dashboard_rowtopheight"></a>	
    <li><b>dashboard_rowtopheight </b><br>
        Höhe der oberen Zeile, in der die Gruppen angeordnet werden. <br>
        Standard: 250
    </li>
    <br>
    
    <a name="dashboard_rowbottomheight"></a>	
    <li><b>dashboard_rowbottomheight </b><br>
        Höhe der unteren Zeile, in der die Gruppen angeordnet werden.<br>
        Standard: 250
    </li><br>
    
    <a name="dashboard_showfullsize"></a>	
    <li><b>dashboard_showfullsize </b><br>
        Blendet die FHEMWEB Raumliste (kompleter linker Bereich der Seite) und den oberen Bereich von FHEMWEB aus wenn der 
        Wert auf 1 gesetzt ist.<br>
        Default: 0
    </li>
    <br>
    
    <a name="dashboard_showtabs"></a>	
    <li><b>dashboard_showtabs </b><br>
        Zeigt die Tabs/Schalterleiste des Dashboards oben oder unten an, oder blendet diese aus. Wenn die Schalterleiste 
        ausgeblendet wird ist das Dashboard gespert.<br>
        Standard: tabs-and-buttonbar-at-the-top
    </li>
    <br>
	
    <a name="dashboard_showtogglebuttons"></a>		
    <li><b>dashboard_showtogglebuttons </b><br>
        Zeigt eine Schaltfläche in jeder Gruppe mit der man diese auf- und zuklappen kann.<br>
        Standard: 0
    </li><br>	
    
    <a name="dashboard_tab1name"></a>
    <li><b>dashboard_tab1name </b><br>
        Titel des Tab. (gilt ebenfalls für weitere dashboard_tabXname)
    </li>
    <br>	
    
    <a name="dashboard_tab1sorting"></a>	
    <li><b>dashboard_tab1sorting </b><br>
        Enthält die Positionierung jeder Gruppe im Tab. Der Wert wird mit der Schaltfläche "Set" geschrieben. Es wird nicht 
        empfohlen dieses Attribut manuell zu ändern. (gilt ebenfalls für weitere dashboard_tabXsorting)
    </li>
    <br>		
    
    <a name="dashboard_tab1groups"></a>	
    <li><b>dashboard_tab1groups </b><br>
        Durch Komma getrennte Liste der FHEM-Gruppen (siehe Attribut "group" eines Devices), die im Tab angezeigt werden. 
		(gilt ebenfalls für weitere dashboard_tabXgroups)
		Falsche Gruppennamen werden hervorgehoben. <br>
        Jede Gruppe kann zusätzlich ein Icon anzeigen, dazu muss der Gruppen name um ":&lt;icon&gt;@&lt;farbe&gt;"ergänzt 
        werden. <br><br>
		
        <b>Beispiel: </b><br>
		Light:Icon_Fisch@blue,AVIcon_Fisch@red,Single Lights:Icon_Fisch@yellow <br><br>
		
        Der Gruppenname kann ebenfalls einen regulären Ausdruck beinhalten, um alle Gruppen anzuzeigen, die darauf passen. <br><br>
		
        <b>Beispiel: </b><br>
		.*Licht.* zeigt alle Gruppen an, die das Wort "Licht" im Namen haben.
    </li>
    <br>	
	
    <a name="dashboard_tab1devices"></a>	
    <li><b>dashboard_tab1devices </b><br>
        DevSpec Liste von Geräten, die im Tab angezeigt werden sollen. (gilt ebenfalls für weitere dashboard_tabXdevices) <br>
		Das Format ist: <br><br>
		<ul>
            GROUPNAME:devspec1,devspec2,...,devspecX:ICONNAME <br><br>
		</ul>	
        ICONNAME ist optional. Auch GROUPNAME muss nicht vorhanden sein. Fehlt GROUPNAME, werden die angegebenen 
        Geräte nicht gruppiert, sondern als einzelne Widgets im Tab angezeigt. Für weitere Details bezüglich DevSpec: 
        <a href="#devspec">DevSpec</a>
    </li>
    <br>	
	
    <a name="dashboard_tabXicon"></a>	
    <li><b>dashboard_tabXicon </b><br>
        Zeigt am Tab ein Icon an. Es muss sich dabei um ein exisitereindes Icon mit modpath Verzeichnis handeln. Handelt es 
        sich um ein SVG Icon kann der Suffix @colorname für die Farbe des Icons angegeben werden.
    </li>
    <br>
    
    <a name="dashboard_tab1colcount"></a>	
    <li><b>dashboard_tab1colcount </b><br>
        Die Anzahl der Spalten im Tab in der Gruppen dargestellt werden können. (gilt ebenfalls für weitere dashboard_tabXcolcount) <br>
		Dennoch ist es möglich, mehrere Gruppen in einer Spalte nebeneinander zu positionieren. Dies ist abhängig von der Breite 
		der Spalten und Gruppen. <br>
        Gilt nur für die mittlere Spalte! <br>
        Standard: &lt;dashboard_colcount&gt;
    </li>
    <br>
    
    <a name="dashboard_tab1backgroundimage"></a>	
    <li><b>dashboard_tab1backgroundimage </b><br>
        Zeigt ein Hintergrundbild für den Tab an. (gilt ebenfalls für weitere dashboard_tabXbackgroundimage) <br>
		Das Bild wird nicht gestreckt, es sollte also auf die Größe des Tabs passen oder diese überschreiten. 
    </li>
    <br>
    
    <a name="dashboard_noLinks"></a>
    <li><b>dashboard_noLinks</b><br>
      Es erfolgt keine Linkerstellung zur Detailansicht von Devices. <br><br>

      <b>Hinweis: </b><br>
      Bei manchen Devicetypen wird der Link zur Detailansicht integriert im Device mitgeliefert. 
      In diesen Fällen muß die Linkgenerierung direkt im Device abgestellt werden (z.B. bei SMAPortalSPG).      
    </li>
    <br>
	
    
    <a name="dashboard_webRefresh"></a>	
    <li><b>dashboard_webRefresh </b><br>
      Mit diesem Attribut werden FHEMWEB-Devices bestimmt, die: <br><br>
	  <ul>
        <li> beim Setzen des Attributes "dashboard_homeTab" diesen Tab im Dashboard sofort aktivieren </li>
	    <li> beim Ausführen von "set &lt;name&gt; activateTab" auf diesen Tab im Dashboard positionieren </li>
	  </ul>
	  <br>
	  (default: alle)
	  <br>
    </li>
    <br>
	
    <a name="dashboard_width"></a>	
    <li><b>dashboard_width </b><br>
        Zum bestimmen der Dashboardbreite. Der Wert kann in % (z.B. 80%) angegeben werden oder als absolute Breite (z.B. 1200) 
        in Pixel.<br>
        Standard: 100%
    </li>
    <br>

</ul>
</ul>
</ul>

=end html_DE

=for :application/json;q=META.json 95_Dashboard.pm
{
  "abstract": "Dashboard for showing multiple devices sorted in tabs",
  "x_lang": {
    "de": {
      "abstract": "Dashboard zur Anzeige mehrerer Geräte in verschiedenen Tabs"
    }
  },
  "keywords": [
    "Dashboard",
    "Tablet",
    "UI",
    "Browser"
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
      "web": "https://wiki.fhem.de/wiki/Dashboard",
      "title": "Dashboard"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/95_Dashboard.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/95_Dashboard.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
