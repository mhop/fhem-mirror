########################################################################################
#
# 95_Dashboard.pm
#
########################################################################################
# Released : 20.12.2013 @svenson08
# Version  : 1.15
# Revisions:
# 0001: Released to testers
# 0002: Don't show link on Groups with WebLinks. Hide GroupToogle Button (new Attribut dashboard_showtooglebuttons).
#       Set the Columnheight (new Attribur dashboard_colheight).
# 0003: Dashboard Entry over the Room-List, set the Room "Dashboard" to hiddenroom. Build weblink independently.
#       Dashboard Row on Top and Bottom (no separately columns). Detail Button
#		to jump into define Detailview. Don't show link on Groups with SVG and readingsGroup.
# 0004: Sort the Groupentrys (@gemx). Hide Room Dashboard.
# 0005: Fix dashboard_row center
# 0006: Released Version 1.10. Rename Module from 95_FWViews to 95_Dashboard. Rename view_* Attributes to
#       dashboard_*. Rename fhemweb_FWViews.js to dashboard.js. Cleanup CSS. Reduce single png-Images to one File only.
#		Fix duplicated run of JS Script. Dashboard STAT show "Missing File" Information if installation is wrong.
# 0007: use jquery.min and jquery-ui.min. add dashboard_debug attribute. Check dashboard_sorting value plausibility.
#       Change default Values. First Release to FHEM SVN.
# 0008: Add Germyn command_ref Text. Add Default Values to command_ref (@cotecmania). Fix identification of an existing
#       Dashboard-Weblink (Message *_weblink already defined, delete it first on rereadcfg). Remove white space from 
#		both ends of a group in dashboard_groups. Fix dashboard_sorting check. Wrong added hiddenroom to FHEMWEB 
#		Browsersession fixed. Buttonbar can now placed on top or bottom of the Dashboard (@cotecmania).
#		Dashboard is always edited out the Room Dashboard (@justme1968)
#		Fix Dashboard Entry over the Room-List after 01_FHEMWEB.pm changes
#
# Known Bugs/Todos:
# Add/Write FHEM Wiki-Doku
# Nachträglich hinzufügen von gruppen
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

package main;

use strict;
use warnings;

use vars qw($FW_dir);       # base directory for web server
use vars qw($FW_icondir);   # icon base directory
use vars qw($FW_room);      # currently selected room
use vars qw(%defs);		    # FHEM device/button definitions
use vars qw($FW_wname);     # Web instance
use vars qw(%FW_hiddenroom);# hash of hidden rooms, used by weblink
use vars qw(%FW_types);     # device types

# --------------------------- Global Variable -----------------------------------------------
my %group;
my $fwjquery = "jquery.min.js";
my $fwjqueryui = "jquery-ui.min.js";
my $dashboardname = "Dashboard"; # Link Text
my $dashboardhiddenroom = "DashboardRoom"; # Hiddenroom
# -------------------------------------------------------------------------------------------

sub Dashboard_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "Dashboard_define";
  $hash->{UndefFn}     = "Dashboard_Undef";
  $hash->{FW_detailFn} = "Dashboard_detailFn";    
  $hash->{AttrList}    = "disable:0,1 ".
						 "dashboard_sorting ".
						 "dashboard_colwidth ".
						 "dashboard_colheight ".
						 "dashboard_rowtopheight ".
						 "dashboard_rowbottomheight ".
						 "dashboard_groups ".
						 "dashboard_lockstate:unlock,lock ".
						 "dashboard_colcount:1,2,3,4,5 ".
						 "dashboard_showbuttonbar:top,bottom,hidden ".
						 "dashboard_showhelper:0,1 ".
						 "dashboard_showtooglebuttons:0,1 ".
						 "dashboard_row:top,center,bottom,top-center,center-bottom,top-center-bottom ".
						 "dashboard_debug:0,1 ".
						 $readingFnAttributes;					  

  $data{FWEXT}{Dashboardx}{LINK} = "?room=".$dashboardhiddenroom;
  $data{FWEXT}{Dashboardx}{NAME} = $dashboardname;
	
  return undef;
}

sub DashboardAsHtml($)
{
 my ($d) = @_;
 
 my $ret = "";
 my $debugfield = "hidden";
 
 my $h = $defs{$d};
 my $name = $defs{$d}{NAME};
 my $id = $defs{$d}{NR};
 
 ############# Read Dashboard Attributes and set Default-Values ##############################
 my $disable = AttrVal($defs{$d}{NAME}, "disable", 0);
 my $sorting = AttrVal($defs{$d}{NAME}, "dashboard_sorting", ",");
 my $colcount = AttrVal($defs{$d}{NAME}, "dashboard_colcount", 1);
 my $colwidth = AttrVal($defs{$d}{NAME}, "dashboard_colwidth", 320);
 my $colheight = AttrVal($defs{$d}{NAME}, "dashboard_colheight", 400); 
 my $rowtopheight = AttrVal($defs{$d}{NAME}, "dashboard_rowtopheight", 250);
 my $rowbottomheight = AttrVal($defs{$d}{NAME}, "dashboard_rowbottomheight", 250); 
 my $showhelper = AttrVal($defs{$d}{NAME}, "dashboard_showhelper", 1);
 my $lockstate = AttrVal($defs{$d}{NAME}, "dashboard_lockstate", "unlock");
 my $showbuttonbar = AttrVal($defs{$d}{NAME}, "dashboard_showbuttonbar", "top");
 my $showtooglebuttons = AttrVal($defs{$d}{NAME}, "dashboard_showtooglebuttons", 1);
 my $row = AttrVal($defs{$d}{NAME}, "dashboard_row", "center");
 my $debug = AttrVal($defs{$d}{NAME}, "dashboard_debug", "0");
 my $dashboardgroups = AttrVal($defs{$d}{NAME}, "dashboard_groups", "");
 #############################################################################################

 #---------------- Dashboard is always edited out the Room Dashboard -------------------------
 if ($FW_room ne $dashboardhiddenroom) { #Dashboard is always edited out the Room Dashboard 	
	if ($showbuttonbar eq "hidden") {$showbuttonbar = "top" };
	$showhelper = 1;
	$showtooglebuttons = 1;
	$lockstate = "unlock";
 }
 #----------------------------------------------------------------------------

 if ($disable == 1) { $defs{$d}{STATE} = "disabled"; }
 if ($dashboardgroups eq "") { $defs{$d}{STATE} = "No Groups set"; }
 return $ret if (($dashboardgroups eq "") || ($disable == 1));
 
 if ($debug == 1) { $debugfield = "edit" }; 
 if ($showbuttonbar eq "hidden") { $lockstate = "lock" };
 if (not ($colwidth =~ /^\d+$/)) { $colwidth = 320 }; 
 if (not ($colheight =~ /^\d+$/)) { $colheight = 400 };  
 if (not ($rowtopheight =~ /^\d+$/)) { $rowtopheight = 50 };
 if (not ($rowbottomheight =~ /^\d+$/)) { $rowbottomheight = 50 };  
 #------------------- Check dashboard_sorting on false content ------------------------------------
 if (($sorting !~ /[0-9]/ || $sorting !~ /:/ || $sorting !~ /,/  ) && ($sorting ne ",")){
	Log3 $d, 3, "[".$name."] Value of attribut dashboard_sorting is wrong. Saved sorting can not be set. Fix Value or delete the Attribute.";
 } else { Log3 $d, 5, "[".$name."] Sorting OK: ".$sorting; }
 #-------------------------------------------------------------------------------------------------
 
 %group = BuildGroupList($dashboardgroups);
 
 $ret .= "<table class=\"dashboard\" id=\"dashboard\">";
 ############################ Dashboard-Optionbar ############################################
 if ($showbuttonbar eq "top") { $ret .= BuildButtonBar($d); }
 #############################################################################################
 
 $ret .= "<tr><td><div class=\"dashboardhidden\">";
 $ret .= "<input type=\"$debugfield\" size=\"100\" id=\"dashboard_attr\" value=\"$name,$colwidth,$showhelper,$lockstate,$showbuttonbar,$colheight,$showtooglebuttons,$colcount,$rowtopheight,$rowbottomheight\">";
 $ret .= "<input type=\"$debugfield\" size=\"100\" id=\"dashboard_currentsorting\" value=\"$sorting\">";
 $ret .= "<input type=\"$debugfield\" size=\"100\" id=\"dashboard_jsdebug\" value=\"\">";
 $ret .= "</div></td></tr>";
 
 ##################### Top Row (only one Column) #############################################
 if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "top"){
	$ret .= "<tr><td>";
	$ret .= "<div id=\"top\">";
	$ret .= "		<div class=\"ui-row dashboard_column\" id=\"sortablecolumn100\">";
	$ret .= "		</div>";
	$ret .= "</div>";
	$ret .= "</td></tr>";
 }
 #############################################################################################
 
 ##################### Center Row (max. 5 Column) ############################################
 if ($row eq "top-center-bottom" || $row eq "top-center" || $row eq "center-bottom" || $row eq "center"){
	$ret .= "<tr><td>"; 
	$ret .= "<div id=\"center\">";  
	$ret .= "	<div class=\"dashboard_column\" id=\"sortablecolumn0\" >";
	my @dashboardgroups = split(",", $dashboardgroups);
	for (my $i=0;$i<@dashboardgroups;$i++){
		$dashboardgroups[$i] = trim($dashboardgroups[$i]); #remove white space from both ends of a string 
		$dashboardgroups[$i] =~ tr/<+>/ /; #Fix Groupname if use wrong Groupnames from Bestpractice beginner configuration
		$ret .= "  <div class=\"dashboard_widget\" data-status=\"\" id=\"".$id."w".$i."\">";
		$ret .= "   <div class=\"dashboard_widgetinner\">";	
		$ret .= "    <div class=\"dashboard_widgetheader\">".$dashboardgroups[$i]."</div>";
		$ret .= "    <div data-userheight=\"\" class=\"dashboard_content\">";
		$ret .= BuildGroup($dashboardgroups[$i]);
		$ret .= "    </div>";	
		$ret .= "   </div>";	
		$ret .= "  </div>";		
	}	
	$ret .= "	</div>";  
	$ret .= BuildEmptyColumn($colcount);
	$ret .= "</div>";
	$ret .= "</td></tr>";
 }
 #############################################################################################
 
 ##################### Bottom Row (only one Column) ##########################################
 if ($row eq "top-center-bottom" || $row eq "center-bottom" || $row eq "bottom"){ 
	$ret .= "<tr><td>";
	$ret .= "<div id=\"bottom\">";
	$ret .= "		<div class=\"ui-row dashboard_column\" id=\"sortablecolumn200\">";
	$ret .= "		</div>";
	$ret .= "</div>";
	$ret .= "</td></tr>";
 }
 #############################################################################################
 
 ############################ Dashboard-Optionbar ############################################
 if ($showbuttonbar eq "bottom") { $ret .= BuildButtonBar($d); }
 #############################################################################################
 
 $ret .= "</table>";
 
 return $ret;
}

sub BuildButtonBar($){
 my ($d) = @_;
 my $ret;
 $ret .= "<tr><td><div class=\"dashboard_buttonbar\">";
 $ret .= "	<div class=\"dashboard_button\"> <span class=\"dashboard_button_icon dashboard_button_iconset\"></span> <a id=\"dashboard_button_set\" href=\"javascript:dashboard_setposition()\" title=\"Set the Position\">Set</a> </div>";
 $ret .= "	<div class=\"dashboard_button\"> <a id=\"dashboard_button_lock\" href=\"javascript:dashboard_tooglelock()\" title=\"Lock Dashboard\">Lock</a> </div>";
 $ret .= "	<div class=\"dashboard_button\"> <span class=\"dashboard_button_icon dashboard_button_icondetail\"></span> <a id=\"dashboard_button_detail\" href=\"/fhem?detail=$d\" title=\"Dashboard Details\">Detail</a> </div>";		
 $ret .= "</div></td></tr>";
}

sub BuildGroupList($) {
#---------------------------------------------------------------------------------------------------------- 
 my @dashboardgroups = split(",", $_[0]); #array for all groups to build an widget
 my %group = ();
 
 foreach my $d (sort keys %defs) {
    foreach my $grp (split(",", AttrVal($d, "group", ""))) {
		$grp = trim($grp);
		foreach my $g (@dashboardgroups){ 
			$g = trim($g);
			$group{$grp}{$d} = 1 if($g eq $grp); 
		}
    }
 } 
#---------------------------------------------------------------------------------------------------------- 
 return %group;
}  

sub BuildGroup($)
{
 my ($currentgroup) = @_;
 my $ret = ""; 
 my $row = 1;
 my %extPage = ();
 
 my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

 foreach my $g (keys %group) {

	next if ($g ne $currentgroup);
	$ret .= "<table class=\"block wide\" id=\"TYPE_$currentgroup\">";
	foreach my $d (sort keys %{$group{$g}}) {
		$ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
		
		my $type = $defs{$d}{TYPE};
		my $devName = AttrVal($d, "alias", $d);
		my $icon = AttrVal($d, "icon", "");
		$icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);
	
		if($FW_hiddenroom{detail}) { $ret .= "<td><div class=\"col1\">$icon$devName</div></td>"; } 
		else { 
			if ($type ne "weblink" && $type ne "SVG" && $type ne "readingsGroup") { # Don't show Link by weblink, svg and readingsGroup
				$ret .=FW_pH "detail=$d", "$icon$devName", 1, "col1", 1; 
			}			
		}
		$row++;		
			
		my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf, \%extPage);
		$ret .= "<td informId=\"$d\">$txt</td>";

		###### Commands, slider, dropdown
        if(!$FW_ss && $cmdlist) {
			foreach my $cmd (split(":", $cmdlist)) {
				my $htmlTxt;
				my @c = split(' ', $cmd);
				if($allSets && $allSets =~ m/$c[0]:([^ ]*)/) {
					my $values = $1;
					foreach my $fn (sort keys %{$data{webCmdFn}}) {
						no strict "refs";
						$htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname, $d, $FW_room, $cmd, $values);
						use strict "refs";
						last if(defined($htmlTxt));
					}
				}
				if($htmlTxt) {
					$ret .= $htmlTxt;
				} else {
				  $ret .=FW_pH "cmd.$d=set $d $cmd$rf", $cmd, 1, "col3", 1;
				}
			}
		}
		$ret .= "</tr>";
	}
	$ret .= "</table>";
 }
 if ($ret eq "") { 
	$ret .= "<table class=\"block wide\" id=\"TYPE_unknowngroup\">";
	$ret .= "<tr class=\"odd\"><td class=\"changed\">Unknown Group: $currentgroup</td></tr>";
	$ret .= "<tr class=\"even\"><td class=\"changed\">Check if the group attribute is really set</td></tr>";
	$ret .= "<tr class=\"odd\"><td class=\"changed\">Check if the groupname is correct written</td></tr>";
	$ret .= "</table>"; 	
 }
 return $ret;
}

sub BuildEmptyColumn($) {
 my ($colcount) = @_;
 my $ret = "";
 my $id = 1;
 
 if ($colcount == 1) { return $ret } else { $colcount = $colcount -1};
 for (my $i=0;$i<$colcount;$i++){
  ########### Empty Column ##################
  $id = $id+$i;
  $ret .= "<div class=\"dashboard_column\" id=\"sortablecolumn$id\"></div>";
  ########################################### 
 }  
 return $ret; 
}

sub CheckInstallation($) {
 my ($hash) = @_;

 unless (-e $FW_dir."/pgm2/".$fwjquery) {
	Log3 $hash, 3, "[".$hash->{NAME}. "] Missing File ".$FW_dir."/pgm2/".$fwjquery;
	$hash->{STATE} = 'Missing File, see LogFile for Details';
 } 
 unless (-e $FW_dir."/pgm2/".$fwjqueryui) {
	Log3 $hash, 3, "[".$hash->{NAME}. "] Missing File ".$FW_dir."/pgm2/".$fwjqueryui;
	$hash->{STATE} = 'Missing File, see LogFile for Details';
 } 
 unless (-e $FW_dir."/pgm2/dashboard.js") {
	Log3 $hash, 3, "[".$hash->{NAME}. "] Missing File ".$FW_dir."/pgm2/dashboard.js";
	$hash->{STATE} = 'Missing File, see LogFile for Details';
 }  
 unless (-e $FW_icondir."/default/dashboardicons.png") {
	Log3 $hash, 3, "[".$hash->{NAME}. "] Missing File ".$FW_icondir."/default/dashboardicons.png";
	$hash->{STATE} = 'Missing File, see LogFile for Details';
 }  
}

sub CheckDashboardEntry($) {
	my ($hash) = @_;
	my $now = time();
	my $timeToExec = $now + 5;
	
	RemoveInternalTimer($hash);
	InternalTimer      ($timeToExec, 'CreateDashboardEntry', $hash, 0);
	InternalTimer      ($timeToExec, 'CheckDashboardAttributUssage', $hash, 0);
}

sub CheckDashboardAttributUssage($) { # replaces old disused attributes and their values
 my ($hash) = @_;
 my $d = $hash->{NAME};
 
 # Replae older dashboard_showbuttonbar value (outdated 01.2014)
 my $showbuttonbarvalue = AttrVal($defs{$d}{NAME}, "dashboard_showbuttonbar", "top");
 if ($showbuttonbarvalue eq "0") { FW_fC("attr ".$d." dashboard_showbuttonbar hidden"); }
 if ($showbuttonbarvalue eq "1") { FW_fC("attr ".$d." dashboard_showbuttonbar top"); }

 # Get out any change to the Logfile 
 if ($showbuttonbarvalue eq "0" || $showbuttonbarvalue eq "1") {   
  Log3 $hash, 3, "[".$hash->{NAME}. "]"." Using an outdated no longer used Attribute or Value. This has been corrected. Don't forget to save config."; 
 }
}

sub CreateDashboardEntry($) {
 my ($hash) = @_;
 
 my $h = $hash->{NAME};
 if (!defined $defs{$h."_weblink"}) {
 	FW_fC("define ".$h."_weblink weblink htmlCode {DashboardAsHtml(\"".$h."\")}");
	Log3 $hash, 3, "[".$hash->{NAME}. "]"." Weblink dosen't exists. Created weblink ".$h."_weblink. Don't forget to save config.";
 }
 FW_fC("attr ".$h."_weblink room ".$dashboardhiddenroom);

 foreach my $dn (sort keys %defs) {
  if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");
	
	#---------- Delete older Hiddenroom for Dashboard due changes in 01_FHEMWEB.pm (01.2014) ---------
	if (index($hr,$dashboardname) != -1  && index($hr,$dashboardhiddenroom) == -1) { 
	 $hr =~ s/$dashboardname/$dashboardhiddenroom/g;
	 FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr);	 
	 Log3 $hash, 3, "[".$hash->{NAME}. "]"." Corrected hiddenroom '".$dashboardname."' -> '".$dashboardhiddenroom."' in ".$defs{$dn}{NAME}.". Don't forget to save config.";
	}
	#-------------------------------------------------------------------------------------------------
	
	if (index($hr,$dashboardhiddenroom) == -1){ 		
		if ($hr eq "") {FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$dashboardhiddenroom);}
		else {FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$dashboardhiddenroom);}
		Log3 $hash, 3, "[".$hash->{NAME}. "]"." Added hiddenroom '".$dashboardhiddenroom."' to ".$defs{$dn}{NAME}.". Don't forget to save config.";
	}	
  }
 }
 
} 

sub Dashboard_define ($$) {
 my ($hash, $def) = @_;
 my $name = $hash->{NAME};
 
 $data{FWEXT}{jquery}{SCRIPT} = "/pgm2/".$fwjquery;
 $data{FWEXT}{jqueryui}{SCRIPT} = "/pgm2/".$fwjqueryui;
 $data{FWEXT}{testjs}{SCRIPT} = "/pgm2/dashboard.js";
 $hash->{STATE} = 'Initialized';  
 
 CheckInstallation($hash);
 CheckDashboardEntry($hash);
 return;
}

sub Dashboard_Undef ($$) {
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

sub Dashboard_detailFn() {
  my ($name, $d, $room, $pageHash) = @_;
  my $hash = $defs{$name};
  return DashboardAsHtml($d);
}

1;

=pod
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
	attr anyViews dashboard_colwidth 400<br>
	attr anyViews dashboard_groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
	attr anyViews dashboard_lockstate unlock<br>
	attr anyViews dashboard_showhelper 1<br>
	</code>	
  </ul>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b> 
  <ul>
	N/A
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <h4>Get</h4> <ul>N/A</ul><br>
  <a name="Dashboardattr"></a>
  <h4>Attributes</h4> 
  
  <a name="dashboard_sorting"></a>	
    <li>dashboard_sorting<br>
        Contains the position of each group. Value is written by the "Set" button. It is not recommended to take manual changes.
    </li><br>	
  <a name="dashboard_row"></a>	
    <li>dashboard_row<br>
        To select which rows are displayed. top only; center only; bottom only; top and center; center and bottom; top,center and bottom.<br>
		Default: center
    </li><br>	
  <a name="dashboard_colwidth"></a>	
    <li>dashboard_colwidth<br>
        Width of each column in which the groups may be positioned. <br>
		Default: 320
    </li><br>		
  <a name="dashboard_colheight"></a>	
    <li>dashboard_colheight<br>
        Height of each column in which the groups may be positioned. <br>
		Default: 400
    </li><br>		
  <a name="dashboard_rowtopheight"></a>	
    <li>dashboard_rowtopheight<br>
        Height of the top row in which the groups may be positioned. <br>
		Default: 250
    </li><br>		
  <a name=""dashboard_rowbottomheight"></a>	
    <li>"dashboard_rowbottomheight<br>
        Height of the bottom row in which the groups may be positioned.<br>
		Default: 250
    </li><br>		
  <a name="dashboard_groups"></a>	
    <li>dashboard_groups<br>
        Comma-separated list of the names of the groups to be displayed.
    </li><br>		
  <a name="dashboard_lockstate"></a>		
    <li>dashboard_lockstate<br>
        When set to "unlock" you can edit the Dashboard. When set to "lock" no change can be made. <br>
		If the bar is hidden dashboard_lockstate is "lock". Editing is possible only with activated switch panel.<br>
		Default: unlock
    </li><br>	
  <a name="dashboard_colcount"></a>	
    <li>dashboard_colcount<br>
        Number of columns in which the groups can be displayed. Nevertheless, it is possible to have multiple groups <br>
		to be positioned in a column next to each other. This is dependent on the width of columns and groups. <br>
		Default: 1
    </li><br>	
 <a name="dashboard_showbuttonbar"></a>	
    <li>dashboard_showbuttonbar<br>
        Displayed a buttonbar panel. Can set on Top or on Bottom of the Dashboard If the bar is hidden dashboard_lockstate the "lock" is used.<br>
		Default: top
    </li><br>
 <a name="dashboard_showhelper"></a>		
    <li>dashboard_showhelper<br>
        Displays frames in order to facilitate the positioning of the groups.<br>
		Default: 1
    </li><br>	 
 <a name="dashboard_showtooglebuttons"></a>		
    <li>dashboard_showtooglebuttons<br>
        Displays a Toogle Button on each Group do collapse.<br>
		Default: 1
    </li><br>	
 <a name="dashboard_debug"></a>		
    <li>dashboard_debug<br>
        Show Hiddenfields. Only for Maintainer's use.<br>
		Default: 0
    </li><br>	

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
	attr anyViews dashboard_colwidth 400<br>
	attr anyViews dashboard_groups &lt;Group1&gt;,&lt;Group2&gt;,&lt;Group3&gt;<br>
	attr anyViews dashboard_lockstate unlock<br>
	attr anyViews dashboard_showhelper 1<br>
	</code>	
  </ul>
  <br>

  <a name="Dashboardset"></a>
  <b>Set</b> 
  <ul>
	N/A
  </ul>
  <br>
  
  <a name="Dashboardget"></a>
  <h4>Get</h4> <ul>N/A</ul><br>
  <a name="Dashboardattr"></a>
  <h4>Attributes</h4> 
  
  <a name="dashboard_sorting"></a>	
    <li>dashboard_sorting<br>
        Enthält die Poistionierung jeder Gruppe. Der Wert wird mit der Schaltfläche "Set" geschrieben. Es wird nicht empfohlen dieses Attribut manuelle zu ändern
    </li><br>	
  <a name="dashboard_row"></a>	
    <li>dashboard_row<br>
   		Auswahl welche Zeilen angezeigt werden sollen. top (nur Oben), center (nur Mitte), bottom (nur Unten) und den Kombinationen daraus.<br>
		Standard: center
    </li><br>	
  <a name="dashboard_colwidth"></a>	
    <li>dashboard_colwidth<br>
        Breite der Spalte, in der die Gruppen angeordnet werden. Gilt für "dashboard_row center, top-center-bottom, center-bottom".<br>
		Nur die Zeile in der Mitte kann mehrere Spalten enthalten! <br>
		Standard: 320
    </li><br>		
  <a name="dashboard_colheight"></a>	
    <li>dashboard_colheight<br>
        Höhe der Spalten, in der die Gruppen angeordnet werden. Gilt nur für "dashboard_row center, top-center-bottom, center-bottom". <br>
		Standard: 400
    </li><br>		
  <a name="dashboard_rowtopheight"></a>	
    <li>dashboard_rowtopheight<br>
        Höhe der oberen Zeile, in der die Gruppen angeordnet werden. <br>
		Standard: 250
    </li><br>		
  <a name=""dashboard_rowbottomheight"></a>	
    <li>"dashboard_rowbottomheight<br>
        Höhe der unteren Zeile, in der die Gruppen angeordnet werden.<br>
		Standard: 250
    </li><br>		
  <a name="dashboard_groups"></a>	
    <li>dashboard_groups<br>
        Durch Komma getrennte Liste mit den Namen der Gruppen, die angezeigt werden. Falsche Gruppennamen werden hervorgehoben.
    </li><br>		
  <a name="dashboard_lockstate"></a>		
    <li>dashboard_lockstate<br>
		Bei Dashboard Einstellung "unlock" kann dieses bearbeitet werden. Bei der Einstellung "lock" können keine Änderung vorgenommen werden. <br>
		Wenn die Leiste ausgeblendet ist (dashboard_showbuttonbar) ist das Dashboard gespert. Die Bearbeitung ist daher nur mit sichtbarer Buttonbar möglich ist.<br>
		Standard: unlock
    </li><br>	
  <a name="dashboard_colcount"></a>	
    <li>dashboard_colcount<br>
		Die Anzahl der Spalten in der  Gruppen dargestellt werden können. Dennoch ist es möglich, mehrere Gruppen <br>
		in einer Spalte nebeneinander zu positionieren. Dies ist abhängig von der Breite der Spalten und Gruppen. <br>
		Gilt nur für die mittlere Spalte! <br>
		Standard: 1
    </li><br>	
 <a name="dashboard_showbuttonbar"></a>	
    <li>dashboard_showbuttonbar<br>
		Eine Buttonbar kann über oder unter dem Dashboard angezeigt werden. Wenn die Leiste ausgeblendet wird ist das Dashboard gespert.<br>
		Standard: top
    </li><br>
 <a name="dashboard_showhelper"></a>		
    <li>dashboard_showhelper<br>
		Blendet Ränder ein, die eine Positionierung der Gruppen erleichtern. <br>
		Standard: 1
    </li><br>	 
 <a name="dashboard_showtooglebuttons"></a>		
    <li>dashboard_showtooglebuttons<br>
		Zeigt eine Schaltfläche in jeder Gruppe mit der man diese auf- und zuklappen kann.<br>
		Standard: 1
    </li><br>	
 <a name="dashboard_debug"></a>		
    <li>dashboard_debug<br>
        Zeigt Debug-Felder an. Sollte nicht gesetzt werden!<br>
		Standard: 0
    </li><br>	

</ul>

=end html_DE
=cut
