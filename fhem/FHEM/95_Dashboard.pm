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
#
# Known Bugs/Todos:
# 95_Dashboard.pm : Message *_weblink already defined, delete it first on rereadcfg
# Dashboard.js : No Change to iconplus on restoreOrder
# Add German commandref =begin html_DE / =end html_DE
# Add/Write FHEM Wiki-Doku
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
use vars qw(%FW_types);     # device types,

# --------------------------- Globale Variabeln ----------------------------------------------
my %group;
my $fwjquery = "jquery.min.js";
my $fwjqueryui = "jquery-ui.min.js";
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
						 "dashboard_showbuttonbar:0,1 ".
						 "dashboard_showhelper:0,1 ".
						 "dashboard_showtooglebuttons:0,1 ".
						 "dashboard_row:top,center,bottom,top-center,center-bottom,top-center-bottom ".
						 "dashboard_debug:0,1 ".
						 $readingFnAttributes;					  

  $data{FWEXT}{Dashboard}{LINK} = "?room=Dashboard";
  $data{FWEXT}{Dashboard}{NAME} = "Dashboard";
	
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
 my $disable = AttrVal($defs{$d}{NAME}, "disable", 0);
 my $sorting = AttrVal($defs{$d}{NAME}, "dashboard_sorting", ",");
 my $colcount = AttrVal($defs{$d}{NAME}, "dashboard_colcount", 1);
 my $colwidth = AttrVal($defs{$d}{NAME}, "dashboard_colwidth", 320);
 my $colheight = AttrVal($defs{$d}{NAME}, "dashboard_colheight", 400); 
 my $rowtopheight = AttrVal($defs{$d}{NAME}, "dashboard_rowtopheight", 250);
 my $rowbottomheight = AttrVal($defs{$d}{NAME}, "dashboard_rowbottomheight", 250); 
 my $showhelper = AttrVal($defs{$d}{NAME}, "dashboard_showhelper", 1);
 my $lockstate = AttrVal($defs{$d}{NAME}, "dashboard_lockstate", "unlock");
 my $showbuttonbar = AttrVal($defs{$d}{NAME}, "dashboard_showbuttonbar", 1);
 my $showtooglebuttons = AttrVal($defs{$d}{NAME}, "dashboard_showtooglebuttons", 1);
 my $row = AttrVal($defs{$d}{NAME}, "dashboard_row", "center");
 my $debug = AttrVal($defs{$d}{NAME}, "dashboard_debug", "0");
 my $dashboardgroups = AttrVal($defs{$d}{NAME}, "dashboard_groups", "");
 
 if ($sorting !~ /,:[0-9]/ && $sorting ne ",") {Log3 $d, 3, "[".$name. "] Value of attribut dashboard_sorting is wrong. Saved sorting can not be set. Fix Value or delete the Attribute.";}
 if ($disable == 1) { $defs{$d}{STATE} = "disabled"; }
 return $ret if (($dashboardgroups eq "") || ($disable == 1));
 if ($debug == 1) { $debugfield = "edit" }; 
 if (not ($colwidth =~ /^\d+$/)) { $colwidth = 320 }; 
 if (not ($colheight =~ /^\d+$/)) { $colheight = 400 };  
 if (not ($rowtopheight =~ /^\d+$/)) { $rowtopheight = 50 };
 if (not ($rowbottomheight =~ /^\d+$/)) { $rowbottomheight = 50 }; 
 %group = BuildGroupList($dashboardgroups);
 
 $ret .= "<table class=\"dashboard\" id=\"dashboard\">";
 ############################ Dashboard-Optionbar #################################################
 if ($showbuttonbar == 1) {
	$ret .= "<tr><td><div class=\"dashboard_buttonbar\">";
	$ret .= "	<div class=\"dashboard_button\"> <span class=\"dashboard_button_icon dashboard_button_iconset\"></span> <a id=\"dashboard_button_set\" href=\"javascript:dashboard_setposition()\" title=\"Set the Position\">Set</a> </div>";
	$ret .= "	<div class=\"dashboard_button\"> <a id=\"dashboard_button_lock\" href=\"javascript:dashboard_tooglelock()\" title=\"Lock Dashboard\">Lock</a> </div>";
	$ret .= "	<div class=\"dashboard_button\"> <span class=\"dashboard_button_icon dashboard_button_icondetail\"></span> <a id=\"dashboard_button_detail\" href=\"/fhem?detail=$d\" title=\"Dashboard Details\">Detail</a> </div>";		
	$ret .= "</div></td></tr>";
 } else { $lockstate = "lock"; }
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
 $ret .= "</table>";
 
 return $ret;
}

sub BuildGroupList($) {
#---------------------------------------------------------------------------------------------------------- 
 my @dashboardgroups = split(",", $_[0]); #array for all groups to build an widget
 my %group = ();
 
 foreach my $d (sort keys %defs) {
    foreach my $grp (split(",", AttrVal($d, "group", ""))) {
		foreach my $g (@dashboardgroups){ $group{$grp}{$d} = 1 if($g eq $grp); }
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

sub CreateDashboardEntry($) {
 my ($hash) = @_;

 my $h = $hash->{NAME};
 if (!defined $defs{$h."_weblink"}) {
 	FW_fC("define ".$h."_weblink weblink htmlCode {DashboardAsHtml(\"".$h."\")}");
	Log3 $hash, 3, "[".$hash->{NAME}. "]"." Weblink dosen't exists. Created weblink ".$h."_weblink. Don't forget to save config.";
 }
 FW_fC("attr ".$h."_weblink room Dashboard");

 foreach my $dn (sort keys %defs) {
  if ($defs{$dn}{TYPE} eq "FHEMWEB") {
	my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");
	if (index($hr,"Dashboard") == -1){ 		
		if ($hr eq "") {FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom Dashboard");}
		else {FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",Dashboard");}
		Log3 $hash, 3, "[".$hash->{NAME}. "]"." Added hiddenroom \"Dashboard\" to  ".$defs{$dn}{NAME}.". Don't forget to save config.";
	}	 
  }
 }
}

sub Dashboard_define ($@) {
 my ($hash, $def) = @_;
 $data{FWEXT}{jquery}{SCRIPT} = "/pgm2/".$fwjquery;
 $data{FWEXT}{jqueryui}{SCRIPT} = "/pgm2/".$fwjqueryui;
 $data{FWEXT}{testjs}{SCRIPT} = "/pgm2/dashboard.js";
 $hash->{STATE} = 'Initialized';  
 
 CheckInstallation($hash);
 CreateDashboardEntry($hash);
 return;
}

sub Dashboard_Undef ($$) {
  my ($hash,$arg) = @_;
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
        To select which rows are displayed. top only; center only; bottom only; top and center; center and bottom; top,center and bottom.
    </li><br>	
  <a name="dashboard_colwidth"></a>	
    <li>dashboard_colwidth<br>
        Width of each column in which the groups may be positioned.
    </li><br>		
  <a name="dashboard_colheight"></a>	
    <li>dashboard_colheight<br>
        Height of each column in which the groups may be positioned.
    </li><br>		
  <a name="dashboard_rowtopheight"></a>	
    <li>vdashboard_rowtopheight<br>
        Height of the top row in which the groups may be positioned.
    </li><br>		
  <a name=""dashboard_rowbottomheight"></a>	
    <li>"dashboard_rowbottomheight<br>
        Height of the bottom row in which the groups may be positioned.
    </li><br>		
  <a name="dashboard_groups"></a>	
    <li>dashboard_groups<br>
        Comma-separated list of the names of the groups to be displayed.
    </li><br>		
  <a name="dashboard_lockstate"></a>		
    <li>dashboard_lockstate<br>
        When set to "unlock" you can edit the Dashboard. When set to "lock" no change can be made. <br>
		If the bar is hidden dashboard_lockstate is "lock". Editing is possible only with activated switch panel.
    </li><br>	
  <a name="dashboard_colcount"></a>	
    <li>dashboard_colcount<br>
        Number of columns in which the groups can be displayed. Nevertheless, it is possible to have multiple groups <br>
		to be positioned in a column next to each other. This is dependent on the width of columns and groups.
    </li><br>	
 <a name="dashboard_showbuttonbar"></a>	
    <li>dashboard_showbuttonbar<br>
        Displayed above the Dashboard a buttonbar panel. If the bar is hidden dashboard_lockstate the "lock" is used.
    </li><br>
 <a name="dashboard_showhelper"></a>		
    <li>dashboard_showhelper<br>
        Displays frames in order to facilitate the positioning of the groups.
    </li><br>	 
 <a name="dashboard_showtooglebuttons"></a>		
    <li>dashboard_showtooglebuttons<br>
        Displays a Toogle Button on each Group do collapse.
    </li><br>	
  <ul>
  </ul><br>
</ul>

=end html
=cut
