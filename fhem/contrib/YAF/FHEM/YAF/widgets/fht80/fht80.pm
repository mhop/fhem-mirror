########################################################################################
#
# fht80.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
#
# fht80 Widget: Marc Pro
#
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
package main;

use strict;
use warnings;

my $yaf_version = 0.41;

use vars qw(%_GET);
use vars qw(%defs);

#######################################################################################
#
# fht80_get_widgetcss - Create the CSS code for this widget
# 
# no parameter
#
########################################################################################

sub fht80_get_widgetcss() {
	my $output = "
		.widget_fht80 {
            width: 175px;
            height: 33px;
            background-repeat:no-repeat;
            background-position:center center;
            opacity:1 !important;
            white-space: nowrap;
			text-align: center;
		}
		.widget_fht80_alias {
			font-size: 12px;
		}
	";
	return $output;
}

########################################################################################
#
# fht80_get_widgetjs - Create the javascript code for this widget
# 
# no parameter
#
########################################################################################

sub fht80_get_widgetjs() {
	
	my $output = '
		function fht80_update_widget(view_id, widget_id) {
            $.ajax({
		 		type: "GET",
				async: true,
				url: "../../ajax/widget/fht80/get_temp",
				data: "view_id="+view_id+"&widget_id="+widget_id,
				context: document.body,
				success: function(get_temp) {
					var widget = $("#widget_"+view_id+"_"+widget_id);
					widget.html(get_temp);
				}   
			});
		}
	';
	return $output;
}

########################################################################################
#
# fht80t_getwidgethtml - HTML code for this widget
# 
# no parameter
#
########################################################################################

sub fht80_get_widgethtml() {
        my $output = "-###-";
        return $output;
}

########################################################################################
#
# fht80t_get_addwidget_setup_html - Create the selection of devices for this widget
# 
# no parameter
#
########################################################################################

sub fht80_get_addwidget_setup_html() {
	my $output = "<script src='js/combobox.js'></script>
				  <select name='fht80_combobox' id='combobox'>";
	my @list = (keys %defs);
	
	foreach my $d (sort @list) {
	    my $type  = $defs{$d}{TYPE};
	    my $name  = $defs{$d}{NAME};

	    if( $type eq "FHT"){
	    	
	    	$output = $output."<option value='$name'>$name</option>";
	    } 
	}
	
	$output = $output."</select>";
	
	$output .= "<br /><label>Label:</label>
				<script src='js/combobox.js'></script>
				<select name='fht80_combobox_label' id='combobox_label'>";
	$output .= "<option value='Name'>Name</option>";
	$output .= "<option value='Alias'>Alias</option>";
	$output .= "<option value='Comment'>Comment</option>";
	$output .= "</select>";
	
	return $output;	
}

########################################################################################
#
# fht80t_get_addwidget_prepare_attributes - 
# 
# no parameter
#
########################################################################################

sub fht80_get_addwidget_prepare_attributes() {
	my $output = '
		var temp_array = new Array();
		temp_array[0] = "fhemname";
		temp_array[1] = $("#combobox option:selected").val()
		attributes_array[0] = temp_array;
		var temp_array2 = new Array();
		temp_array2[0] = "labeltype";
		temp_array2[1] = $("#combobox_label option:selected").val()
		attributes_array[1] = temp_array2;
	';
	return $output;	
}

########################################################################################
#
# fht80t_getwidget_html - HTML code for this widget. DO WE NEED THIS ? SEE ABOVE
# DO WE NEED IT? WHO KNOWS. (It looks like this one fills the initial html of the
#                            widget, so let's keep it for science.)
# 
# no parameter
#
########################################################################################

sub fht80_getwidget_html() {
	my $output = "###";
	return $output;	
}

########################################################################################
#
# fht80t_get_lamp_status - return the state of the lamp
# 
# no parameter
#
########################################################################################

sub fht80_get_temp() {
 	my $attribute = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "fhemname");
	if(!($attribute)) {
		return("Widget not found ".$_GET{"view_id"}." ".$_GET{"widget_id"});
	}
	
	my $labeltype = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "labeltype");
	
    my $d = $defs{$attribute};
    my $ret = "";
	
	my $temp = $defs{$attribute}{READINGS}{temperature}{VAL};
	my $temptimestamp = $defs{$attribute}{READINGS}{temperature}{TIME};
	my $actuator = $defs{$attribute}{READINGS}{actuator}{VAL};
	my $label = "";
	if($labeltype eq "Comment") {
		$label = AttrVal($attribute,"comment",$d->{NAME});	
	} elsif ($labeltype eq "Alias") {
		$label = AttrVal($attribute,"alias",$d->{NAME});		
	} else {
		$label = $d->{NAME}
	}
	$label =~ s/(_)/&nbsp;/g;
	my $mode = $defs{$attribute}{READINGS}{mode}{VAL};
	my $desi = $defs{$attribute}{READINGS}{"desired-temp"}{VAL};	
	my $battery = $defs{$attribute}{READINGS}{battery}{VAL};	
	
	if($mode eq "manual") {
		$mode = " <span title='manual'>&oplus;</span> ";
	} else {
		$mode = " <span title='$mode'>&otimes;</span> ";
	}
	
	if($desi ne "off") {
		$desi .= " &deg;C";
	}
	
	if($battery ne "ok") {
		$battery = "Check Battery: " . $battery . "<br />";
	} else {
		$battery = "";
	}
	
	$ret = "<span class='widget_fht80_alias'>" . $label . "</span><br />" . $battery;
	$ret .= "<span title='$temptimestamp'>" . $temp . "</span>" . " &deg;C" . $mode;
	$ret .= "<span title='Actuator: $actuator'>" . $desi . "</span>";
	 
    return $ret;
}
1;
