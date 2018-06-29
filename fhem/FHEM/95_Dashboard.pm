# $Id$
########################################################################################
#
# 95_Dashboard.pm
#
########################################################################################
# Released : 20.12.2013 Sascha Hermann
# Version :
# 1.00: Released to testers
# 1.02: Don't show link on Groups with WebLinks. Hide GroupToogle Button (new Attribut dashboard_showtogglebuttons).
#       Set the Columnheight (new Attribur dashboard_colheight).
# 1.03: Dashboard Entry over the Room-List, set the Room "Dashboard" to hiddenroom. Build weblink independently.
#       Dashboard Row on Top and Bottom (no separately columns). Detail Button
#		to jump into define Detailview. Don't show link on Groups with SVG and readingsGroup.
# 1.04: Sort the Groupentrys (@gemx). Hide Room Dashboard.
# 1.05: Fix dashboard_row center
# 1.10: Released Version 1.10. Rename Module from 95_FWViews to 95_Dashboard. Rename view_* Attributes to
#       dashboard_*. Rename fhemweb_FWViews.js to dashboard.js. Cleanup CSS. Reduce single png-Images to one File only.
#		Fix duplicated run of JS Script. Dashboard STAT show "Missing File" Information if installation is wrong.
# 1.11: use jquery.min and jquery-ui.min. add dashboard_debug attribute. Check dashboard_sorting value plausibility.
#       Change default Values. First Release to FHEM SVN.
# 1.12: Add Germyn command_ref Text. Add Default Values to command_ref (@cotecmania). Fix identification of an existing
#       Dashboard-Weblink (Message *_weblink already defined, delete it first on rereadcfg). Remove white space from 
#		both ends of a group in dashboard_groups. Fix dashboard_sorting check. Wrong added hiddenroom to FHEMWEB 
#		Browsersession fixed. Buttonbar can now placed on top or bottom of the Dashboard (@cotecmania).
#		Dashboard is always edited out the Room Dashboard (@justme1968)
#		Fix Dashboard Entry over the Room-List after 01_FHEMWEB.pm changes
# 2.00: First Changes vor Dashboard Tabs. Change while saving positioning. Alterd max/min Group positioning.
#		Many changes in Dasboard.js. Replaced the attributes dashboard_groups, dashboard_colheight and dashboard_sorting
#		Many new Attributes vor Tabs, Dashboard sizing. Set of mimimal attributes (helpful for beginners).
#		Provisionally the columns widths are dependent on the total width of the Dashboard.
# 2.01: attibute dashboard_colwidth replace with dashboard_rowcentercolwidth. rowcentercolwidth can now be defined per 
#			column. Delete Groups Attribut with Value 1. Dashboard can hide FHEMWEB Roomliste and Header => Fullscreenmode
# 2.02: Tabs can set on top, bottom or hidden. Fix "variable $tabgroups masks earlier" Errorlog.
# 2.03: dashboard_showfullsize only in DashboardRoom. Tabs can show Icons (new Attributes). Fix showhelper Bug on lock/unlock.
#			 The error that after a trigger action the curren tab is changed to the "old" activetab tab has been fixed. dashboard_activetab 
#			 is stored after tab change
# 2.04: change view of readingroups. Attribute dashboard_groups removed. New Attribute dashboard_webfrontendfilter to define 
#			separate Dashboards per FHEMWEB Instance.
# 2.05: bugfix, changes in dashboard.js, groups can show Icons (group:icon@color,group:icon@color ...). "Back"-Button in Fullsize-Mode.
# 		 Dashboard near top in Fullsize-Mode. dashboard_activetab store the active Tab, not the last active tab.
# 2.06: Attribute dashboard_colheight removed. Change Groupcontent sorting in compliance by alias and sortby.
#          Custom CSS over new Attribute dashboard_customcss. Fix Bug that affect new groups.
# 2.07: Fix GroupWidget-Error with readingGroups in hiddenroom
# 2.08: Fix dashboard_webfrontendfilter Error-Message. Internal changes. Attribute dashboard_colwidth and dashboard_sorting removed.
# 2.09: dashboard_showfullsize not applied in room "all" resp. "Everything". First small implementation over Dashboard_DetailFN.
# 2.10: Internal Changes. Lock/Unlock now only in Detail view. Attribut dashboard_lockstate are obsolet.
# 2.11: Attribute dashboard_showhelper ist obolet. Erase tabs-at-the-top-buttonbar-hidden and tabs-on-the-bottom-buttonbar-hidden values 
#       from Attribute dashboard_showtabs. Change Buttonbar Style. Clear CSS and Dashboard.js.
# 2.12: Update Docu. CSS Class Changes. Insert Configdialog for Tabs. Change handling of parameters in both directions.
# 2.13: Changed View of readingsHistory. Fix Linebrake in unlock state. Bugfix Display Group with similar group names.
# 3.00: Tabs are loading via ajax (asynchronous).
#	Removed attribute "dashboard_tabcount". The number of tabs is determined automatically based on the gorup definitions.
#	Group names now also support regular expressions.
#	Dashboard is not limited to 1 for every FHEMWEB instance.
#	Dashboard link in left menu has the same name as the dashboard definition in fhem.cfg.
#	dashboard_webfrontendfilter has been removed. To hide a dashboard put its name into the FHEMWEB instance's hiddenroom attribute.
#	Flexible mode to be able to position groups absolutely on the dashboard screen.
#	The number of columns can be defined per tab (additionally to the global definition)
#	Optimized icon loading.
#	Optimized fullscreen view.
#	Minor improvements in javascript and css.
# 3.10: added attribute dashboard_tabXdevices, which can contain devspec definitions and thus allow to also shown not grouped devices
#
# ---- Changes by DS_Starter ----
# 3.10.1   29.06.2018   added FW_hideDisplayName, Forum #88727
#
#
# Known Bugs/Todos:
# BUG: Nicht alle Inhalte aller Tabs laden, bei Plots dauert die bedienung des Dashboards zu lange. -> elemente hidden? -> widgets aus js über XHR nachladen und dann anzeigen (jquery xml nachladen...)
# BUG: Variabler abstand wird nicht gesichert
# BUG: Überlappen Gruppen andere? ->Zindex oberer reihe > als darunter liegenden
#
# Log 1, "[DASHBOARD simple debug] '".$g."' ";
########################################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################################
# Helpfull Links:
# http://jquery.10927.n7.nabble.com/saving-portlet-state-td125831.html
# http://jsfiddle.net/w7ZvQ/
# http://jsfiddle.net/adamboduch/e6zdX/1/
# http://www.innovativephp.com/jquery-resizable-practical-examples-and-demos/
# http://jsfiddle.net/raulfernandez/mAuxn/
# http://jsfiddle.net/zeTP8/

package main;

use strict;
use warnings;
use vars qw(%FW_icons); 	# List of icons
use vars qw($FW_dir);      	# base directory for web server
use vars qw($FW_icondir);   # icon base directory
use vars qw($FW_room);      # currently selected room
use vars qw(%defs);		    # FHEM device/button definitions
#use vars qw(%FW_groups);	# List of Groups
use vars qw($FW_wname);     # Web instance
use vars qw(%FW_types);     # device types
use vars qw($FW_ss);      	# is smallscreen, needed by 97_GROUP/95_VIEW

#########################
# Forward declaration
sub Dashboard_GetGroupList();

#########################
# Global variables
my %group;
my $dashboard_groupListfhem;
my $fwjquery = "jquery.min.js";
my $fwjqueryui = "jquery-ui.min.js";
my $dashboardversion = "3.10.1";

#############################################################################################
sub Dashboard_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}       = "Dashboard_define";
  $hash->{SetFn}       = "Dashboard_Set";  
  $hash->{GetFn}       = "Dashboard_Get";
  $hash->{UndefFn}     = "Dashboard_undef";
  $hash->{FW_detailFn} = "Dashboard_DetailFN";    
  $hash->{AttrFn}      = "Dashboard_attr";
  $hash->{AttrList}    = "disable:0,1 ".
  						 "dashboard_colcount:1,2,3,4,5 ".						 						 
						 "dashboard_debug:0,1 ".						 
						 "dashboard_rowtopheight ".
						 "dashboard_rowbottomheight ".
						 "dashboard_row:top,center,bottom,top-center,center-bottom,top-center-bottom ".						 
						 "dashboard_showtogglebuttons:0,1 ".						 
						 #new attribute vers. 2.00
						 "dashboard_activetab:1,2,3,4,5,6,7 ".						 
						 "dashboard_width ".
						 "dashboard_rowcenterheight ".
						 #new attribute vers. 2.01
						 "dashboard_rowcentercolwidth ".
						 "dashboard_showfullsize:0,1 ".
						 #new attribute vers. 2.02
						 "dashboard_showtabs:tabs-and-buttonbar-at-the-top,tabs-and-buttonbar-on-the-bottom,tabs-and-buttonbar-hidden ".
						 #new attribute vers. 2.06
						 "dashboard_customcss " .
						 #new attribute vers. 3.00
						 "dashboard_flexible " .
						 #tab-specific attributes
						 "dashboard_tab1name " .
						 "dashboard_tab1groups " .
						 #new attribute vers. 3.10
						 "dashboard_tab1devices " .
						 "dashboard_tab1sorting " .
						 "dashboard_tab1icon " .
						 "dashboard_tab1colcount " .
						 "dashboard_tab1rowcentercolwidth " .
						 "dashboard_tab1backgroundimage " .
						 # dynamic attributes
						 "dashboard_tab[0-9]+name " .
						 "dashboard_tab[0-9]+groups " .
						 #new attribute vers. 3.10
						 "dashboard_tab[0-9]+devices " .
						 "dashboard_tab[0-9]+sorting " .
						 "dashboard_tab[0-9]+icon " .
						 "dashboard_tab[0-9]+colcount " .
						 "dashboard_tab[0-9]+rowcentercolwidth " .
						 "dashboard_tab[0-9]+backgroundimage " .
						 "dashboard_backgroundimage";

	$data{FWEXT}{jquery}{SCRIPT} = "/pgm2/".$fwjquery if (!$data{FWEXT}{jquery}{SCRIPT});
	$data{FWEXT}{jqueryui}{SCRIPT} = "/pgm2/".$fwjqueryui if (!$data{FWEXT}{jqueryui}{SCRIPT});
	$data{FWEXT}{z_dashboard}{SCRIPT} = "/pgm2/dashboard.js" if (!$data{FWEXT}{z_dashboard});					 
	$data{FWEXT}{x_dashboard}{SCRIPT} = "/pgm2/svg.js" if (!$data{FWEXT}{x_dashboard});					 
  			 
	
	
  return undef;
}

sub Dashboard_DetailFN() {
	my ($name, $d, $room, $pageHash) = @_;
	my $hash = $defs{$name};
  
	my $ret = ""; 
	$ret .= "<table class=\"block wide\" id=\"dashboardtoolbar\"  style=\"width:100%\">\n";
	$ret .= "<tr><td>Helper:\n<div>\n";   
	$ret .= "	   <a href=\"$FW_ME/dashboard/" . $d . "\"><button type=\"button\">Return to Dashboard</button></a>\n";
	$ret .= "	   <a href=\"$FW_ME?cmd=shutdown restart\"><button type=\"button\">Restart FHEM</button></a>\n";
	$ret .= "	   <a href=\"$FW_ME?cmd=save\"><button type=\"button\">Save config</button></a>\n";
	$ret .= "  </div>\n";
	$ret .= "</td></tr>\n"; 	
	$ret .= "</table>\n";
	return $ret;
}

sub Dashboard_Set($@) {
	my ( $hash, $name, $cmd, @args ) = @_;
	
	if ( $cmd eq "lock" ) {
		readingsSingleUpdate( $hash, "lockstate", "lock", 0 ); 
		return;
	} elsif ( $cmd eq "unlock" ) {
		readingsSingleUpdate( $hash, "lockstate", "unlock", 0 );
		return;
	}else { 
		return "Unknown argument " . $cmd . ", choose one of lock:noArg unlock:noArg";
	}
}

sub Dashboard_Escape($) {
  my $a = shift;
  return "null" if(!defined($a));
  my %esc = ("\n" => '\n', "\r" => '\r', "\t" => '\t', "\f" => '\f', "\b" => '\b', "\"" => '\"', "\\" => '\\\\', "\'" => '\\\'', );
  $a =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/eg;
  return $a;
}

sub Dashboard_Get($@) {
  my ($hash, @a) = @_;
  my $res = "";
  
  my $arg = (defined($a[1]) ? $a[1] : "");
  my $arg2 = (defined($a[2]) ? $a[2] : "");
  if ($arg eq "config") {
		my $name = $hash->{NAME};
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
			$res  .= "    \"icondirs\": \"$iconDirs\", \"dashboard_tabcount\": " . GetTabCount($hash, 0). ", \"dashboard_activetab\": " . GetActiveTab($hash->{NAME});
			
			$res .=  ($i != $x) ? ",\n" : "\n";
			foreach my $attr (sort keys %$attrdata) {
				$i++;				
				@splitattr = split("@", $attrdata->{$attr});
				if (@splitattr == 2) {
					$res .= "    \"".Dashboard_Escape($attr)."\": \"".$splitattr[0]."\",\n";
					$res .= "    \"".Dashboard_Escape($attr)."color\": \"".$splitattr[1]."\"";
				} elsif ($attr ne "dashboard_activetab") { $res .= "    \"".Dashboard_Escape($attr)."\": \"".$attrdata->{$attr}."\"";}
				else {
					next;
				}
				$res .=  ($i != $x) ? ",\n" : "\n";
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
		#%group = BuildGroupList($dashboard_groupListfhem);
		#$res .= BuildGroupWidgets(1,1,1212,trim($dbgroup),"t1c1,".trim($dbgroup).",true,0,0:"); 
		#return $res;		
  #For dynamic loading of tabs
  } elsif ($arg eq "tab" && $arg2 =~ /^\d+$/) {
    return BuildDashboardTab($arg2, $hash->{NAME});
  } elsif ($arg eq "icon") {
    shift @a;
    shift @a;

    my $icon = join (' ', @a);

    return FW_iconPath($icon);
  } else {
    return "Unknown argument $arg choose one of config:noArg groupWidget tab icon";
  }
}

sub Dashboard_define ($$) {
 my ($hash, $def) = @_;

 my @args = split (" ", $def);

 my $now          = time();
 my $name         = $hash->{NAME}; 
 $hash->{VERSION} = $dashboardversion;
 
 readingsSingleUpdate( $hash, "state", "Initialized", 0 ); 
  
 RemoveInternalTimer($hash);
 InternalTimer      ($now + 5, 'CheckDashboardAttributUssage', $hash, 0);

  my $url = '/dashboard/' . $name;

  $data{FWEXT}{$url}{CONTENTFUNC} = 'Dashboard_CGI';
  $data{FWEXT}{$url}{LINK} = 'dashboard/' . $name;
  $data{FWEXT}{$url}{NAME} = $name;
		
 return;
}

sub Dashboard_undef ($$) {
  my ($hash,$arg) = @_;

  # remove dashboard links from left menu
  my $url = '/dashboard/' . $hash->{NAME};
  delete $data{FWEXT}{$url};

  RemoveInternalTimer($hash);
  
  return undef;
}

sub Dashboard_attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  # add dynamic attributes
  if (
    $cmd eq "set" &&
    (
         $attrName =~ m/dashboard_tab([1-9][0-9]*)groups/
      || $attrName =~ m/dashboard_tab([1-9][0-9]*)devices/
    )
  ) {
	addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "name");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "devices");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "groups");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "sorting");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "icon");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "colcount");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "rowcentercolwidth");
        addToDevAttrList($name, "dashboard_tab" . ($1 + 1) . "backgroundimage");
  }

  # if an alias is set to the dashboard, replace the name shown in the left navigation
  # by this alias
  if (
       $cmd eq "set"
    && $attrName =~ m/alias/
  ) {
    my $url = '/dashboard/' . $name;

    $data{FWEXT}{$url}{NAME} = $attrVal;
  }

  return;  
}

#############################################################################################
#############################################################################################

sub Dashboard_CGI($)
{
  my ($htmlarg) = @_;

  $htmlarg =~ s/^\///;                                                             # eliminate leading /
  my @params = split(/\//,$htmlarg);                                               # split URL by /
  my $ret = '';
  my $name = $params[1];

  $ret = '<div id="content">';
  
  if ($name && defined($defs{$name})) {                                                                
    my $showfullsize  = AttrVal($defs{$name}{NAME}, "dashboard_showfullsize", 0); 

    if ($showfullsize) {
      if ($FW_RET =~ m/<body[^>]*class="([^"]+)"[^>]*>/) {
        $FW_RET =~ s/class="$1"/class="$1 dashboard_fullsize"/;
      }
      else {
        $FW_RET =~ s/<body/<body class="dashboard_fullsize"/;
      }
    }

    $ret .= Dashboard_SummaryFN($FW_wname,$name,$FW_room,undef);
  }
  else {
    $ret .= 'Dashboard "' . $name . '" not found';
  }

  $ret .= '</div>';

  FW_pO $ret;

  # empty room to make sure no room actions are taken by the framework
  $FW_room = '';

  return 0;
}

sub DashboardAsHtml($)
{
	my ($d) = @_; 
	Dashboard_SummaryFN($FW_wname,$d,$FW_room,undef);
}

sub Dashboard_SummaryFN($$$$)
{
 my ($FW_wname, $d, $room, $pageHash) = @_;
 
 my $ret = "";
 my $showbuttonbar = "hidden";
 my $debugfield = "hidden";
 
 my $h = $defs{$d};
 my $name = $defs{$d}{NAME};
 my $id = $defs{$d}{NR};
 
 ######################### Read Dashboard Attributes and set Default-Values ####################################
 my $lockstate = ($defs{$d}->{READINGS}{lockstate}{VAL}) ? $defs{$d}->{READINGS}{lockstate}{VAL} : "unlock";
 my $showhelper = ($lockstate eq "unlock") ? 1 : 0; 
  
 my $disable = AttrVal($defs{$d}{NAME}, "disable", 0);
 my $colcount = AttrVal($defs{$d}{NAME}, "dashboard_colcount", 1);
 my $colwidth = AttrVal($defs{$d}{NAME}, "dashboard_rowcentercolwidth", 100);
 my $colheight = AttrVal($defs{$d}{NAME}, "dashboard_rowcenterheight", 400); 
 my $rowtopheight = AttrVal($defs{$d}{NAME}, "dashboard_rowtopheight", 250);
 my $rowbottomheight = AttrVal($defs{$d}{NAME}, "dashboard_rowbottomheight", 250);  
 my $showtabs = AttrVal($defs{$d}{NAME}, "dashboard_showtabs", "tabs-and-buttonbar-at-the-top"); 
 my $showtogglebuttons = AttrVal($defs{$d}{NAME}, "dashboard_showtogglebuttons", 1); 
 my $showfullsize  = AttrVal($defs{$d}{NAME}, "dashboard_showfullsize", 0); 
 my $flexible = AttrVal($defs{$d}{NAME}, "dashboard_flexible", 0);
 my $customcss = AttrVal($defs{$d}{NAME}, "dashboard_customcss", "none");
 my $backgroundimage = AttrVal($defs{$d}{NAME}, "dashboard_backgroundimage", "");
 
 my $row = AttrVal($defs{$d}{NAME}, "dashboard_row", "center");
 my $debug = AttrVal($defs{$d}{NAME}, "dashboard_debug", "0");
 
 my $activetab = GetActiveTab($d);
 my $tabcount = GetTabCount($defs{$d}, 1);  
 my $dbwidth = AttrVal($defs{$d}{NAME}, "dashboard_width", "100%"); 
 my @tabnames = ();
 my @tabsortings = ();

 for (my $i = 0; $i < $tabcount; $i++) {
   $tabnames[$i] = AttrVal($defs{$d}{NAME}, "dashboard_tab" . ($i + 1) . "name", "Dashboard-Tab " . ($i + 1));
   $tabsortings[$i] = AttrVal($defs{$d}{NAME}, "dashboard_tab" . ($i + 1) . "sorting", "");
 }

 #############################################################################################
  
 if ($disable == 1) { 
	readingsSingleUpdate( $defs{$d}, "state", "Disabled", 0 );
	return "";
 }
 
 ##################################################################################
 
 if ($debug == 1) { $debugfield = "edit" }; 
 if ($showtabs eq "tabs-and-buttonbar-at-the-top") { $showbuttonbar = "top"; }
 if ($showtabs eq "tabs-and-buttonbar-on-the-bottom") { $showbuttonbar = "bottom"; }
 if ($showbuttonbar eq "hidden") { $lockstate = "lock" };
 
 if ($activetab > $tabcount) { $activetab = $tabcount; }

 $colwidth =~ tr/,/:/;
 if (not ($colheight =~ /^\d+$/)) { $colheight = 400 };  
 if (not ($rowtopheight =~ /^\d+$/)) { $rowtopheight = 50 };
 if (not ($rowbottomheight =~ /^\d+$/)) { $rowbottomheight = 50 };  
 
 #------------------- Check dashboard_sorting on false content ------------------------------------
 for (my $i=0;$i<@tabsortings;$i++){ 
	if (($tabsortings[$i-1] !~ /[0-9]+/ || $tabsortings[$i-1] !~ /:/ || $tabsortings[$i-1] !~ /,/  ) && ($tabsortings[$i-1] ne "," && $tabsortings[$i-1] ne "")){
		Log3 $d, 3, "[".$name." V".$dashboardversion."] Value of attribut dashboard_tab".$i."sorting is wrong. Saved sorting can not be set. Fix Value or delete the Attribute. [".$tabsortings[$i-1]."]";	
	} else { Log3 $d, 5, "[".$name." V".$dashboardversion."] Sorting OK or Empty: dashboard_tab".$i."sorting "; }	
 }
 #-------------------------------------------------------------------------------------------------
 
 if ($room ne "all") { 
 
	################################ 
	################################

	############################ Set FHEM url to avoid hardcoding it in javascript ############################ 
	$ret .= "<script type='text/javascript'>var fhemUrl = '" . $FW_ME . "';</script>";
 
	$ret .= "<div id=\"tabEdit\" class=\"dashboard-dialog-content dashboard-widget-content\" title=\"Dashboard-Tab\" style=\"display:none;\">\n";		
	$ret .= "	<div id=\"dashboard-dialog-tabs\" class=\"dashboard dashboard_tabs\">\n";	
	$ret .= "		<ul class=\"dashboard dashboard_tabnav\">\n";
	$ret .= "			<li class=\"dashboard dashboard_tab\"><a href=\"#tabs-1\">Current Tab</a></li>\n";
	$ret .= "			<li class=\"dashboard dashboard_tab\"><a href=\"#tabs-2\">Common</a></li>\n";
	$ret .= "		</ul>\n";	
	$ret .= "		<div id=\"tabs-1\" class=\"dashboard_tabcontent\">\n";
	$ret .= "			<table>\n";
	$ret .= "				<tr colspan=\"2\"><td><div id=\"tabID\"></div></td></tr>\n";		
	$ret .= "				<tr><td>Tabtitle:</td><td colspan=\"2\"><input id=\"tabTitle\" type=\"text\" size=\"25\"></td></tr>";
	$ret .= "				<tr><td>Tabicon:</td><td><input id=\"tabIcon\" type=\"text\" size=\"10\"></td><td><input id=\"tabIconColor\" type=\"text\" size=\"7\"></td></tr>";
	# the method FW_multipleSelect seems not to be available any more in fhem
	#$ret .= "				<tr><td>Groups:</td><td colspan=\"2\"><input id=\"tabGroups\" type=\"text\" size=\"25\" onfocus=\"FW_multipleSelect(this)\" allvals=\"multiple,$dashboard_groupListfhem\" readonly=\"readonly\"></td></tr>";	
	$ret .= "				<tr><td>Groups:</td><td colspan=\"2\"><input id=\"tabGroups\" type=\"text\" size=\"25\"></td></tr>";	
	$ret .= "				<tr><td></td><td colspan=\"2\"><input type=\"checkbox\" id=\"tabActiveTab\" value=\"\"><label for=\"tabActiveTab\">This Tab is currently selected</label></td></tr>";	
	$ret .= "			</table>\n";
	$ret .= "		</div>\n";	
	$ret .= "		<div id=\"tabs-2\" class=\"dashboard_tabcontent\">\n";
	$ret .= "Comming soon";
	$ret .= "		</div>\n";	
	$ret .= "	</div>\n";		
	$ret .= "</div>\n";

	$ret .= "<div id=\"dashboard_define\" style=\"display: none;\">$d</div>\n";
	$ret .= "<table class=\"roomoverview dashboard\" id=\"dashboard\">\n";

	$ret .= "<tr style=\"height: 0px;\"><td><div class=\"dashboardhidden\">\n"; 
	 $ret .= "<input type=\"$debugfield\" size=\"100%\" id=\"dashboard_attr\" value=\"$name,$dbwidth,$showhelper,$lockstate,$showbuttonbar,$colheight,$showtogglebuttons,$colcount,$rowtopheight,$rowbottomheight,$tabcount,$activetab,$colwidth,$showfullsize,$customcss,$flexible\">\n";
	 $ret .= "<input type=\"$debugfield\" size=\"100%\" id=\"dashboard_jsdebug\" value=\"\">\n";
	 $ret .= "</div></td></tr>\n"; 
	 $ret .= "<tr><td><div id=\"dashboardtabs\" class=\"dashboard dashboard_tabs\" style=\"background: " . ($backgroundimage ? "url(/fhem/images/" . FW_iconPath($backgroundimage) . ")" : "") . " no-repeat !important;\">\n";  

	 ########################### Dashboard Tab-Liste ##############################################
	 $ret .= "	<ul id=\"dashboard_tabnav\" class=\"dashboard dashboard_tabnav dashboard_tabnav_".$showbuttonbar."\">\n";	   		
	 for (my $i=0;$i<$tabcount;$i++){$ret .= "    <li class=\"dashboard dashboard_tab dashboard_tab_".$showbuttonbar."\"><a href=\"#dashboard_tab".$i."\">".trim($tabnames[$i])."</a></li>";}
	 $ret .= "	</ul>\n"; 	 
	 ########################################################################################
	 
	 for (my $t=0;$t<$tabcount;$t++){ 
		if ($t == $activetab - 1) {
			$ret .= BuildDashboardTab($t, $d);
		}
	 }
	 $ret .= "</div></td></tr>\n";
	 $ret .= "</table>\n";
 } else { 
 	$ret .= "<table>";
	$ret .= "<tr><td><div class=\"devType\">".$defs{$d}{TYPE}."</div></td></tr>";
	$ret .= "<tr><td><table id=\"TYPE_".$defs{$d}{TYPE}."\" class=\"block wide\">";
	$ret .= "<tbody><tr>";   
	$ret .= "<td><div><a href=\"$FW_ME?detail=$d\">$d</a></div></td>";
	$ret .= "<td><div>".$defs{$d}{STATE}."</div></td>";	
	$ret .= "</tr></tbody>";
	$ret .= "</table></td></tr>";
	$ret .= "</table>";
 }
 
 return $ret; 
}

sub BuildDashboardTab($$)
{
	my ($t, $d) = @_;

	my $id              = $defs{$d}{NR};
	my $colcount        = AttrVal($defs{$d}{NAME}, 'dashboard_tab' . ($t + 1) . 'colcount', AttrVal($defs{$d}{NAME}, "dashboard_colcount", 1));
	my $colwidths       = AttrVal($defs{$d}{NAME}, 'dashboard_tab' . ($t + 1) . 'rowcentercolwidth', AttrVal($defs{$d}{NAME}, "dashboard_rowcentercolwidth", 100));
        $colwidths          =~ tr/,/:/;
	my $backgroundimage = AttrVal($defs{$d}{NAME}, 'dashboard_tab' . ($t + 1) . 'backgroundimage', "");
	my $row             = AttrVal($defs{$d}{NAME}, "dashboard_row", "center");
	my $tabcount        = GetTabCount($defs{$d}, 1);
        my $tabgroups       = AttrVal($defs{$d}{NAME}, "dashboard_tab" . ($t + 1) . "groups", "");
        my $tabsortings     = AttrVal($defs{$d}{NAME}, "dashboard_tab" . ($t + 1) . "sorting", "");
        my $tabdevicegroups = AttrVal($defs{$d}{NAME}, "dashboard_tab" . ($t + 1) . "devices", "");

	unless ($tabgroups || $tabdevicegroups) { 
		readingsSingleUpdate( $defs{$d}, "state", "No Groups or devices set", 0 );
		return "";
	}
	
        my @temptabdevicegroup = split(' ', $tabdevicegroups);
        my @tabdevicegroups = ();

	# make sure device groups without a group name are splitted into
	# separate groups for every device they are containing
        for my $devicegroup (@temptabdevicegroup) {
          my @groupparts = split(':', $devicegroup);

          if (@groupparts == 1) {
            my @devices = map { $_ . '$$$' . $_ } devspec2array($groupparts[0]);
            push(@tabdevicegroups, @devices);
          }
          else {
            push(@tabdevicegroups, $devicegroup);
          }
        }

	my $groups   = Dashboard_GetGroupList();
        $groups   =~ s/#/ /g;
        my @groups   = split(',', $groups);
        my @temptabgroup = split(",", $tabgroups);
	
        # resolve group names from regular expressions
	for (my $i=0;$i<@temptabgroup;$i++) {
		my @stabgroup = split(":", trim($temptabgroup[$i]));		
		my @index = grep { $groups[$_] eq $stabgroup[0] } (0 .. @groups-1);

                if (@index == 0) {
			my $matchGroup = '^' . $stabgroup[0] . '$';
			@index = grep { $groups[$_] =~ m/$matchGroup/ } (0 .. @groups-1);
		}

		if (@index > 0) {
			for (my $j=0; $j<@index;$j++) {
				my $groupname = @groups[$index[$j]];
				$groupname .= '$$$' . 'a:group=' . $groupname;
				if (@stabgroup > 1) {
					$groupname .= '$$$' . $stabgroup[1];
				}
				push(@tabdevicegroups,$groupname);
			}
		}
	}

        $tabgroups = join('§§§', @tabdevicegroups);

        # add sortings for groups not already having a defined sorting
        for (my $i=0;$i<@tabdevicegroups;$i++) {
		my @stabgroup = split(/\$\$\$/, trim($tabdevicegroups[$i]));		
		my $matchGroup = "," . quotemeta(trim($stabgroup[0])) . ",";

		if ($tabsortings !~ m/$matchGroup/) {
			$tabsortings = $tabsortings."t".$t."c".GetMaxColumnId($row,$colcount).",".trim($stabgroup[0]).",true,0,0:";
		}
	}

	my $ret =  "	<div id=\"dashboard_tab".$t."\" data-tabwidgets=\"".$tabsortings."\" data-tabcolwidths=\"".$colwidths."\" class=\"dashboard dashboard_tabpanel\" style=\"background: " . ($backgroundimage ? "url(/fhem/images/" . FW_iconPath($backgroundimage) . ")" : "none") . " no-repeat !important;\">\n";
	$ret .= "   <ul class=\"dashboard_tabcontent\">\n";
	$ret .= "	<table class=\"dashboard_tabcontent\">\n";	 
	##################### Top Row (only one Column) #############################################
	if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "top"){
		$ret .= BuildDashboardTopRow($t,$id,$tabgroups,$tabsortings);
	}
	##################### Center Row (max. 5 Column) ############################################
	if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "center-bottom" || $row eq "center") {
		$ret .= BuildDashboardCenterRow($t,$id,$tabgroups,$tabsortings,$colcount);
	}
	############################# Bottom Row (only one Column) ############################################
	if ($row eq "top-center-bottom" || $row eq "center-bottom" || $row eq "bottom"){
		$ret .= BuildDashboardBottomRow($t,$id,$tabgroups,$tabsortings);
	}
	#############################################################################################	 
	$ret .= "	</table>\n";
	$ret .= " 	</ul>\n";
	$ret .= "	</div>\n";

	return $ret;
}

sub BuildDashboardTopRow($$$$){
 my ($t,$id, $devicegroups, $groupsorting) = @_;
 my $ret; 
 $ret .= "<tr><td  class=\"dashboard_row\">\n";
 $ret .= "<div id=\"dashboard_rowtop_tab".$t."\" class=\"dashboard dashboard_rowtop\">\n";
 $ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column100\">\n";
 $ret .= BuildGroupWidgets($t,"100",$id,$devicegroups,$groupsorting); 
 $ret .= "		</div>\n";
 $ret .= "</div>\n";
 $ret .= "</td></tr>\n";
 return $ret;
}

sub BuildDashboardCenterRow($$$$$){
 my ($t,$id, $devicegroups, $groupsorting, $colcount) = @_;

 my $ret = "<tr><td  class=\"dashboard_row\">\n";
 $ret .= "<div id=\"dashboard_rowcenter_tab".$t."\" class=\"dashboard dashboard_rowcenter\">\n";

 my $currentcol  = $colcount;
 my $maxcolindex = $colcount - 1;
 my $replace     = "t" . $t . "c" . $maxcolindex . ",";

 # replace all sortings referencing not existing columns
 # this does only work if there is no empty column inbetween
 while (index($groupsorting, "t".$t."c".$currentcol.",") >= 0) {
   my $search  = "t" . $t . "c" . $currentcol . ",";
   $groupsorting  =~ s/$search/$replace/g;
   $currentcol++;
 }

 for (my $i=0;$i<$colcount;$i++){
	$ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column".$i."\">\n";
	$ret .= BuildGroupWidgets($t,$i,$id,$devicegroups,$groupsorting); 
	$ret .= "		</div>\n";
 }
 $ret .= "</div>\n";
 $ret .= "</td></tr>\n";
 return $ret;
}

sub BuildDashboardBottomRow($$$$){
 my ($t,$id, $devicegroups, $groupsorting) = @_;
 my $ret; 
 $ret .= "<tr><td  class=\"dashboard_row\">\n";
 $ret .= "<div id=\"dashboard_rowbottom_tab".$t."\" class=\"dashboard dashboard_rowbottom\">\n";
 $ret .= "		<div class=\"dashboard ui-row dashboard_row dashboard_column\" id=\"dashboard_tab".$t."column200\">\n";
 $ret .= BuildGroupWidgets($t,"200",$id,$devicegroups,$groupsorting); 
 $ret .= "		</div>\n";
 $ret .= "</div>\n";
 $ret .= "</td></tr>\n";
 return $ret;
}

sub BuildGroupWidgets($$$$$) {
	my ($tab,$column,$id,$devicegroups, $groupsorting) = @_;
	my $ret = "";

 	my $counter = 0;
        my %sorting = ();
        my %groups = ();
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

	  $ret .= BuildGroup( ($groupname,$groupdevices,$sorting{$groupname},$groupId,$groupicon) );

          $counter++;
        }
		
     	return $ret; 
}

sub BuildGroupList($) {
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

sub Dashboard_GetGroupList() {
  my %allGroups = ();
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    foreach my $g (split(",", AttrVal($d, "group", ""))) { $allGroups{$g}{$d} = 1; }
  }  
  my $ret = join(",", sort map { $_ =~ s/ /#/g ;$_} keys %allGroups);
  return $ret;
}

sub BuildGroup
{
 	my ($groupname,$devices,$sorting,$groupId,$icon) = @_;
 	my $ret = ""; 
 	my $row = 1;
 	my %extPage = ();
 	my $foundDevices = 0;
 	my $replaceGroup = "";
 
 	my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

	$ret .= "  <div class=\"dashboard dashboard_widget ui-widget\" data-groupwidget=\"".$sorting."\" id=\"".$groupId."\">\n";
	$ret .= "   <div class=\"dashboard_widgetinner\">\n";	

        if ($groupname && $groupname ne $devices) {
		$ret .= "    <div class=\"dashboard_widgetheader ui-widget-header dashboard_group_header\">";
		if ($icon) {
			$ret.= FW_makeImage($icon,$icon,"dashboard_group_icon");
        	}
        	$ret .= $groupname . "</div>\n";
	}
	$ret .= "    <div data-userheight=\"\" class=\"dashboard_content\">\n";
	$ret .= "<table class=\"dashboard block wide\" id=\"TYPE_$groupname\">";

	my %seen;
	# make sure devices are not contained twice in the list
	my @devices = grep { ! $seen{$_} ++ } devspec2array($devices);
        # sort the devices in alphabetical order by sortby, alias, name
        @devices = sort {
		lc(AttrVal($a,'sortby',AttrVal($a,'alias',$a))) cmp lc(AttrVal($b,'sortby',AttrVal($b,'alias',$b)))
	} @devices;

	foreach my $d (@devices) {	
        next if (!defined($defs{$d}));
        $foundDevices++;

		$ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
		
		my $type = $defs{$d}{TYPE};
		my $devName = AttrVal($d, "alias", $d);
		my $icon = AttrVal($d, "icon", "");

		$icon = FW_makeImage($icon,$icon,"icon dashboard_groupicon") . "&nbsp;" if($icon);
	
        $devName="" if($modules{$defs{$d}{TYPE}}{FW_hideDisplayName}); # Forum 88667
		if (!$modules{$defs{$d}{TYPE}}{FW_atPageEnd}) { # Don't show Link for "atEnd"-devices
			$ret .= FW_pH "detail=$d", "$icon$devName", 1, "col1", 1; 
		}			
		
		$row++;		
			
                $extPage{group} = $groupname;
		my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf, \%extPage);
		$allSets = FW_widgetOverride($d, $allSets);
		
	        ##############   Customize Result for Special Types #####################
		my @txtarray = split(">", $txt);				
                if ($modules{$defs{$d}{TYPE}}{FW_atPageEnd}) {
			no strict "refs"; 
			my $devret = &{$modules{$defs{$d}{TYPE}}{FW_summaryFn}}($FW_wname, $d,
                                                        $FW_room, \%extPage);
 			$ret .= "<td class=\"dashboard_dev_container\"";
			if ($devret !~ /informId/i) {
			  $ret .= " informId=\"$d\"";
  			}
			$ret .= ">$devret</td>";
			use strict "refs"; 
		} else  {
			$ret .= "<td informId=\"$d\">$txt</td>";
		}
		###########################################################

		###### Commands, slider, dropdown
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
						$htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname,
										   $d, $FW_room, $cmd, $values);
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

sub GetMaxColumnId($$) {
	my ($row, $colcount) = @_;
	my $maxcolid = "0";
	
	if (index($row,"bottom") > 0) { $maxcolid = "200"; } 
	elsif (index($row,"center") > 0) { $maxcolid = $colcount-1; } 
	elsif (index($row,"top") > 0) { $maxcolid = "100"; }
	return $maxcolid;
}

sub CheckDashboardEntry($) {
	my ($hash) = @_;
	my $now = time();
	my $timeToExec = $now + 5;
	
	RemoveInternalTimer($hash);
	InternalTimer      ($timeToExec, 'CheckDashboardAttributUssage', $hash, 0);
}

sub CheckDashboardAttributUssage($) { # replaces old disused attributes and their values | set minimal attributes
 my ($hash) = @_;
 my $d = $hash->{NAME};
 my $detailnote = "";
 
 # --------- Set minimal Attributes in the hope to make it easier for beginners --------------------
 my $tab1groups = AttrVal($defs{$d}{NAME}, "dashboard_tab1groups", "<noGroup>");
 if ($tab1groups eq "<noGroup>") { FW_fC("attr ".$d." dashboard_tab1groups Set Your Groups - See Attribute dashboard_tab1groups-"); }
 # ------------------------------------------------------------------------------------------------- 
 # ---------------- Delete empty Groups entries ---------------------------------------------------------- 
 my $tabgroups = AttrVal($defs{$d}{NAME}, "dashboard_tab1groups", "999");
 if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab1groups"); }
 $tabgroups = AttrVal($defs{$d}{NAME}, "dashboard_tab2groups", "999");
 if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab2groups"); } 
 $tabgroups = AttrVal($defs{$d}{NAME}, "dashboard_tab3groups", "999");
 if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab3groups"); }  
 $tabgroups = AttrVal($defs{$d}{NAME}, "dashboard_tab4groups", "999");
 if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab4groups"); }   
 $tabgroups = AttrVal($defs{$d}{NAME}, "dashboard_tab5groups", "999");
 if ($tabgroups eq "1"  ) { FW_fC("deleteattr ".$d." dashboard_tab5groups"); }   
 # -------------------------------------------------------------------------------------------------
 
 my $lockstate = AttrVal($defs{$d}{NAME}, "dashboard_lockstate", ""); # outdates 04.2014
 if ($lockstate ne "") {
	{ FW_fC("deleteattr ".$d." dashboard_lockstate"); }
	Log3 $hash, 3, "[".$hash->{NAME}. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [dashboard_lockstate]";
 } 
 my $showhelper = AttrVal($defs{$d}{NAME}, "dashboard_showhelper", ""); # outdates 04.2014 
 if ($showhelper ne "") {
	{ FW_fC("deleteattr ".$d." dashboard_showhelper"); }
	Log3 $hash, 3, "[".$hash->{NAME}. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [dashboard_showhelper]";
 }  
 my $showtabs = AttrVal($defs{$d}{NAME}, "dashboard_showtabs", ""); # delete values 04.2014 
 if ($showtabs eq "tabs-at-the-top-buttonbar-hidden") {
	{ FW_fC("set ".$d." dashboard_showtabs tabs-and-buttonbar-at-the-top"); }
	Log3 $hash, 3, "[".$hash->{NAME}. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [tabs-at-the-top-buttonbar-hidden]";
 }
 if ($showtabs eq "tabs-on-the-bottom-buttonbar-hidden") {
	{ FW_fC("set ".$d." dashboard_showtabs tabs-and-buttonbar-on-the-bottom"); } 
	Log3 $hash, 3, "[".$hash->{NAME}. " V".$dashboardversion."]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config. [tabs-on-the-bottom-buttonbar-hidden]";
 }  
}

sub
GetTabCount ($$)
{
 my ($hash, $defaultTabCount) = @_;
 
 my $tabCount = 0;

 while (
      AttrVal($hash->{NAME}, 'dashboard_tab' . ($tabCount + 1) . 'groups', '') ne ""
   || AttrVal($hash->{NAME}, 'dashboard_tab' . ($tabCount + 1) . 'devices', '') ne ""
 ) {
   $tabCount++;
 }

 return $tabCount ? $tabCount : $defaultTabCount;
}

sub
GetActiveTab ($)
{
  my ($d) = @_;

  if (defined($FW_httpheader{Cookie})) {
    my %cookie = map({ split('=', $_) } split(/; */, $FW_httpheader{Cookie}));
    if (defined($cookie{dashboard_activetab})) {
      my $activeTab = $cookie{dashboard_activetab};
      if ($activeTab <= GetTabCount($defs{$d}, 1)) {
        return $activeTab;
      }
    }
  }

  return AttrVal($defs{$d}{NAME}, 'dashboard_activetab', 1);
}

1;

=pod
=item summary    Dashboard for showing multiple devices sorted in tabs
=item summary_DE Dashboard zur Anzeige mehrerer Geräte in verschiedenen Tabs
=begin html

<a name="Dashboard"></a>
<h3>Dashboard</h3>
<ul>
  Creates a Dashboard in any group can be arranged. The positioning may depend the Groups and column width are made<br>
  arbitrarily by drag'n drop. Also, the width and height of a Group can be increased beyond the minimum size.<br>
  <br> 
  
  <a name="Dashboarddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Dashboard</code>
	<br><br>
    Example:<br>
    <ul>
     <code>define anyViews Dashboard</code>
    </ul><br>
	
  <b>Bestpractice beginner configuration</b>
	<br><br>
	<code>
	define anyViews Dashboard<br>
	attr anyViews dashboard_colcount 2<br>
	attr anyviews dashboard_rowcentercolwidth 30,70<br>
	attr anyViews dashboard_tab1groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
	</code>	
  </ul>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; lock</code><br><br>
	locks the Dashboard so that no position changes can be made<br>
	<code>set &lt;name&gt; unlock</code><br><br>
    unlock the Dashboard<br>
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="Dashboardattr"></a>
  <b>Attributes</b> 
  <ul>
	  <a name="dashboard_tabcount"></a>
		<li>dashboard_tabcount<br>
			Returns the number of displayed tabs. (Does not need to be set any more. It is read automatically from the configured tabs)
			Default: 1
		</li><br>	  
	  <a name="dashboard_activetab"></a>
		<li>dashboard_activetab<br>
			Specifies which tab is activated. Can be set manually, but is also set by the switch "Set" to the currently active tab.
			Default: 1
		</li><br>	 
	  <a name="dashboard_tabXname"></a>
		<li>dashboard_tabXname<br>
			Title of Tab at position X.
		</li><br>	   
	  <a name="dashboard_tabXsorting"></a>	
		<li>dashboard_tabXsorting<br>
			Contains the position of each group in Tab X. Value is written by the "Set" button. It is not recommended to take manual changes.
		</li><br>		
	  <a name="dashboard_row"></a>	
		<li>dashboard_row<br>
			To select which rows are displayed. top only; center only; bottom only; top and center; center and bottom; top,center and bottom.<br>
			Default: center
		</li><br>		
	  <a name="dashboard_width"></a>	
		<li>dashboard_width<br>
			To determine the Dashboardwidth. The value can be specified, or an absolute width value (eg 1200) in pixels in% (eg 80%).<br>
			Default: 100%
		</li><br>			
	  <a name="dashboard_rowcenterheight"></a>	
		<li>dashboard_rowcenterheight<br>
			Height of the center row in which the groups may be positioned. <br> 		
			Default: 400		
		</li><br>			
	  <a name="dashboard_rowcentercolwidth"></a>	
		<li>dashboard_rowcentercolwidth<br>
			About this attribute, the width of each column of the middle Dashboardrow can be set. It can be stored for each column a separate value. 
			The values ​​must be separated by a comma (no spaces). Each value determines the column width in%! The first value specifies the width of the first column, 
			the second value of the width of the second column, etc. Is the sum of the width greater than 100 it is reduced. 
			If more columns defined as widths the missing widths are determined by the difference to 100. However, are less columns are defined as the values ​​of 
			ignores the excess values​​.<br>
			Default: 100
		</li><br>			
	  <a name="dashboard_rowtopheight"></a>	
		<li>dashboard_rowtopheight<br>
			Height of the top row in which the groups may be positioned. <br>
			Default: 250
		</li><br>		
	  <a name="dashboard_rowbottomheight"></a>	
		<li>"dashboard_rowbottomheight<br>
			Height of the bottom row in which the groups may be positioned.<br>
			Default: 250
		</li><br>		
	  <a name="dashboard_tabXgroups"></a>	
		<li>dashboard_tabXgroups<br>
			Comma-separated list of the names of the groups to be displayed in Tab X.<br>
			Each group can be given an icon for this purpose the group name, the following must be completed ":&lt;icon&gt;@&lt;color&gt;"<br>
			Example: Light:Icon_Fisch@blue,AVIcon_Fisch@red,Single Lights:Icon_Fisch@yellow<br/>
			Additionally a group can contain a regular expression to show all groups matching a criteria.
			Example: .*Light.* to show all groups that contain the string "Light"
		</li><br>		
          <a name="dashboard_tabXdevices"></a>	
		<li>dashboard_tabXdevices<br>
			devspec list of devices that should appear in the tab. The format is:<br/>
    			GROUPNAME:devspec1,devspec2,...,devspecN:ICONNAME</br/>
			THe icon name is optional. Also the group name is optional. In case of missing group name, the matching devices are not grouped but shown as separate widgets without titles. For further details on the devspec format see:<br/>
			<a href="#devspec">Dev-Spec</a>
		</li><br>		
	  <a name="dashboard_tabXicon"></a>	
		<li>dashboard_tabXicon<br>
			Set the icon for a Tab. There must exist an icon with the name ico.(png|svg) in the modpath directory. If the image is referencing an SVG icon, then you can use the @colorname suffix to color the image. 
		</li><br>
	  <a name="dashboard_colcount"></a>	
		<li>dashboard_colcount<br>
			Number of columns in which the groups can be displayed. Nevertheless, it is possible to have multiple groups <br>
			to be positioned in a column next to each other. This is depend on the width of columns and groups. <br>
			Default: 1
		</li><br>		
         <a name="dashboard_tabXcolcount"></a>	
		<li>dashboard_tabXcolcount<br>
			Number of columns for a specific tab in which the groups can be displayed. Nevertheless, it is possible to have multiple groups <br>
			to be positioned in a column next to each other. This depends on the width of columns and groups. <br>
			Default: <dashboard_colcount>
		</li><br>	
	 <a name="dashboard_tabXbackgroundimage"></a>	
		<li>dashboard_tabXbackgroundimage<br>
			Shows a background image for the X tab. The image is not stretched in any way, it should therefore match the tab size or extend it.
			Standard: 
		</li><br>		
         <a name="dashboard_flexible"></a>		
		<li>dashboard_flexible<br>
			If set to a value > 0, the widgets are not positioned in columns any more but can be moved freely to any position in the tab.<br/>
			The value for this parameter also defines the grid, in which the position "snaps in".
			Default: 0
		</li><br>	
	 <a name="dashboard_showfullsize"></a>	
		<li>dashboard_showfullsize<br>
			Hide FHEMWEB Roomliste (complete left side) and Page Header if Value is 1.<br>
			Default: 0
		</li><br>		
	 <a name="dashboard_showtabs"></a>	
		<li>dashboard_showtabs<br>
			Displays the Tabs/Buttonbar on top or bottom, or hides them. If the Buttonbar is hidden lockstate is "lock" is used.<br>
			Default: tabs-and-buttonbar-at-the-top
		</li><br>
	 <a name="dashboard_showtogglebuttons"></a>		
		<li>dashboard_showtogglebuttons<br>
			Displays a Toogle Button on each Group do collapse.<br>
			Default: 0
		</li><br>	
         <a name="dashboard_backgroundimage"></a>		
		<li>dashboard_backgroundimage<br>
			Displays a background image for the complete dashboard. The image is not stretched in any way so the size should match/extend the
			dashboard height/width.
			Default: 
		</li><br>	
	 <a name="dashboard_debug"></a>		
		<li>dashboard_debug<br>
			Show Hiddenfields. Only for Maintainer's use.<br>
			Default: 0
		</li><br>	
	</ul>
</ul>

=end html
=begin html_DE

<a name="Dashboard"></a>
<h3>Dashboard</h3>
<ul>
  Erstellt eine Übersicht in der Gruppen angeordnet werden können. Dabei können die Gruppen mit Drag'n Drop frei positioniert<br>
  und in mehreren Spalten angeordnet werden. Auch kann die Breite und Höhe einer Gruppe über die Mindestgröße hinaus gezogen werden. <br>
  <br> 
  
  <a name="Dashboarddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Dashboard</code>
	<br><br>
    Beispiel:<br>
    <ul>
     <code>define anyViews Dashboard</code>
    </ul><br>
	
  <b>Bestpractice Anfängerkonfiguration</b>
	<br><br>
	<code>
	define anyViews Dashboard<br>
	attr anyViews dashboard_colcount 2<br>
	attr anyViews dashboard_rowcentercolwidth 30,70<br>
	attr anyViews dashboard_tab1groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
	</code>	
  </ul>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; lock</code><br><br>
	Sperrt das Dashboard so das keine Positionsänderungen vorgenommen werden können<br>
	<code>set &lt;name&gt; unlock</code><br><br>
    Entsperrt das Dashboard<br>
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="Dashboardattr"></a>
  <b>Attributes</b> 
  <ul>
	  <a name="dashboard_tabcount"></a>	
		<li>dashboard_tabcount<br>
			Gibt die Anzahl der angezeigten Tabs an. (Dieser Parameter is veraletet, die Anzahl der Tabs wird aus der Dashboard-Konfiguration gelesen)
			Standard: 1
		</li><br>	  
	  <a name="dashboard_activetab"></a>	
		 <li>dashboard_activetab<br>
			Gibt an welches Tab aktiviert ist. Kann manuell gesetzt werden, wird aber auch durch den Schalter "Set" auf das gerade aktive Tab gesetzt.
			Standard: 1
		</li><br>	  
	  <a name="dashboard_tabXname"></a>
		<li>dashboard_tabXname<br>
			Titel des X. Tab.
		</li><br>	   
	  <a name="dashboard_tabXsorting"></a>	
		<li>dashboard_tabXsorting<br>
			Enthält die Poistionierung jeder Gruppe im Tab X. Der Wert wird mit der Schaltfläche "Set" geschrieben. Es wird nicht empfohlen dieses Attribut manuelle zu ändern
		</li><br>		
	  <a name="dashboard_row"></a>	
		<li>dashboard_row<br>
			Auswahl welche Zeilen angezeigt werden sollen. top (nur Oben), center (nur Mitte), bottom (nur Unten) und den Kombinationen daraus.<br>
			Standard: center
		</li><br>		
	  <a name="dashboard_width"></a>	
		<li>dashboard_width<br>
			Zum bestimmen der Dashboardbreite. Der Wert kann in % (z.B. 80%) angegeben werden oder als absolute Breite (z.B. 1200) in Pixel.<br>
			Standard: 100%
		</li><br>		
	  <a name="dashboard_rowcenterheight"></a>	
		<li>dashboard_rowcenterheight<br>
			Höhe der mittleren Zeile, in der die Gruppen angeordnet werden. <br>
			Standard: 400
		</li><br>			
	  <a name="dashboard_rowcentercolwidth"></a>	
		<li>dashboard_rowcentercolwidth<br>
			Über dieses Attribut wird die Breite der einzelnen Spalten der mittleren Dashboardreihe festgelegt. Dabei kann je Spalte ein separater Wert hinterlegt werden. 
			Die Werte sind durch ein Komma (ohne Leerzeichen) zu trennen. Jeder Wert bestimmt die Spaltenbreite in %! Der erste Wert gibt die Breite der ersten Spalte an, 
			der zweite Wert die Breite der zweiten Spalte usw. Ist die Summe der Breite größer als 100 werden die Spaltenbreiten reduziert.
			Sind mehr Spalten als Breiten definiert werden die fehlenden Breiten um die Differenz zu 100 festgelegt. Sind hingegen weniger Spalten als Werte definiert werden 
			die überschüssigen Werte ignoriert.<br>
			Standard: 100
		</li><br>			
	  <a name="dashboard_rowtopheight"></a>	
		<li>dashboard_rowtopheight<br>
			Höhe der oberen Zeile, in der die Gruppen angeordnet werden. <br>
			Standard: 250
		</li><br>		
	  <a name="dashboard_rowbottomheight"></a>	
		<li>"dashboard_rowbottomheight<br>
			Höhe der unteren Zeile, in der die Gruppen angeordnet werden.<br>
			Standard: 250
		</li><br>		
	  <a name="dashboard_tabXgroups"></a>	
		<li>dashboard_tab1groups<br>
			Durch Komma getrennte Liste mit den Namen der Gruppen, die im Tab 1 angezeigt werden. Falsche Gruppennamen werden hervorgehoben.<br>
			Jede Gruppe kann zusätzlich ein Icon anzeigen, dazu muss der Gruppen name um ":&lt;icon&gt;@&lt;farbe&gt;"ergänzt werden<br>
			Beispiel: Light:Icon_Fisch@blue,AVIcon_Fisch@red,Single Lights:Icon_Fisch@yellow<br/>
			Der Gruppenname kann ebenfalls einen regulären Ausdruck beinhalten, um alle Gruppen anzuzeigen, die darauf passen.<br/>
			Beispiel: .*Licht.* zeigt alle Gruppen an, die das Wort "Licht" im Namen haben.
		</li><br>		
	  <a name="dashboard_tabXdevices"></a>	
		<li>dashboard_tabXdevices<br>
 			devspec Liste von Geräten, die im Tab angezeigt werden sollen. Das format ist:<br/>
    			GROUPNAME:devspec1,devspec2,...,devspecN:ICONNAME</br/>
			Das Icon ist optional. Auch der Gruppenname muss nicht vorhanden sein. Im Falle dass dieser fehlt, werden die gefunden Geräte nicht gruppiert sondern als einzelne Widgets im Tab angezeigt. Für weitere Details bezüglich devspec:
			<a href="#devspec">Dev-Spec</a>
		</li><br>		
	  <a name="dashboard_tabXicon"></a>	
		<li>dashboard_tabXicon<br>
			Zeigt am Tab ein Icon an. Es muss sich dabei um ein exisitereindes Icon mit modpath Verzeichnis handeln. Handelt es sich um ein SVG Icon kann der Suffix @colorname für die Farbe des Icons angegeben werden.
		</li><br>
	  <a name="dashboard_colcount"></a>	
		<li>dashboard_colcount<br>
			Die Anzahl der Spalten in der  Gruppen dargestellt werden können. Dennoch ist es möglich, mehrere Gruppen <br>
			in einer Spalte nebeneinander zu positionieren. Dies ist abhängig von der Breite der Spalten und Gruppen. <br>
			Gilt nur für die mittlere Spalte! <br>
			Standard: 1
		</li><br>		
          <a name="dashboard_tabXcolcount"></a>	
		<li>dashboard_tabXcolcount<br>
			Die Anzahl der Spalten im Tab X in der  Gruppen dargestellt werden können. Dennoch ist es möglich, mehrere Gruppen <br>
			in einer Spalte nebeneinander zu positionieren. Dies ist abhängig von der Breite der Spalten und Gruppen. <br>
			Gilt nur für die mittlere Spalte! <br>
			Standard: <dashboard_colcount>
		</li><br>		
 	  <a name="dashboard_tabXbackgroundimage"></a>	
		<li>dashboard_tabXbackgroundimage<br>
			Zeigt ein Hintergrundbild für den X-ten Tab an. Das Bild wird nicht gestreckt, es sollte also auf die Größe des Tabs passen oder diese überschreiten.
			Standard: 
		</li><br>		
  	  <a name="dashboard_flexible"></a>	
		<li>dashboard_flexible<br>
			Hat dieser Parameter  einen Wert > 0, dann können die Widgets in den Tabs frei positioniert werden und hängen nicht mehr an den Spalten fest. Der Wert gibt ebenfalls das Raster an, in dem die Positionierung "zu schnappt".
			Standard: 0
		</li><br>		
	 <a name="dashboard_showfullsize"></a>	
		<li>dashboard_showfullsize<br>
			Blendet die FHEMWEB Raumliste (kompleter linker Bereich der Seite) und den oberen Bereich von FHEMWEB aus wenn der Wert auf 1 gesetzt ist.<br>
			Default: 0
		</li><br>		
	 <a name="dashboard_showtabs"></a>	
		<li>dashboard_showtabs<br>
			Zeigt die Tabs/Schalterleiste des Dashboards oben oder unten an, oder blendet diese aus. Wenn die Schalterleiste ausgeblendet wird ist das Dashboard gespert.<br>
			Standard: tabs-and-buttonbar-at-the-top
		</li><br>	
	 <a name="dashboard_showtogglebuttons"></a>		
		<li>dashboard_showtogglebuttons<br>
			Zeigt eine Schaltfläche in jeder Gruppe mit der man diese auf- und zuklappen kann.<br>
			Standard: 0
		</li><br>	
	<a name="dashboard_backgroundimage"></a>		
		<li>dashboard_backgroundimage<br>
			Zeig in Hintergrundbild im Dashboard an. Das Bild wird nicht gestreckt, es sollte daher auf die Größe des Dashboards passen oder diese überschreiten.
			Default: 
		</li><br>	
	 <a name="dashboard_debug"></a>		
		<li>dashboard_debug<br>
			Zeigt Debug-Felder an. Sollte nicht gesetzt werden!<br>
			Standard: 0
		</li><br>	
	</ul>
</ul>

=end html_DE
=cut
