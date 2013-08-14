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
			font-size: 0.7em;
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
		function fht80_on_click(view_id, widget_id) {
		}
		function fht80_update_widget(view_id, widget_id) {
            $.ajax({
		 		type: "GET",
				async: true,
				url: "../../ajax/widget/fht80/get_temp",
				data: "view_id="+view_id+"&widget_id="+widget_id,
				context: document.body,
				success: function(get_data) {
					var data = jQuery.parseJSON(get_data);
					var get_temp = data[0];
					var sizefac = data[1];
					var widget = $("#widget_"+view_id+"_"+widget_id);
					widget.css("font-size", sizefac+"em");
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

sub fht80_get_editwidget_setup_html() {
	my $output = "";
	$output .= "TEST!";
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
 	my @ret = ();
	my $viewid = $_GET{"view_id"};
	my $widgetid = $_GET{"widget_id"};
	my $fhemname = YAF_getWidgetAttribute($viewid, $widgetid, "fhemname", undef);

	if(!defined $fhemname) {
		$ret[0] = "Widget not found " . $viewid . " " . $widgetid;
		$ret[1] = 1;
		return(encode_json(\@ret));
	}

	# get all the needed data
	my $temp = 			ReadingsVal($fhemname, "temperature", 0);
	my $temptimestamp = ReadingsTimestamp($fhemname, "temperature", "big-bang");
	my $actuator = 		ReadingsVal($fhemname, "actuator", "");
	my $mode = 			ReadingsVal($fhemname, "mode", "none");
	my $desi = 			ReadingsVal($fhemname, "desired-temp", "");
	my $battery = 		ReadingsVal($fhemname, "battery", "");
	my $nomode = 		YAF_getWidgetAttribute($viewid, $widgetid, "nomode", 0);
	my $labeltype = 	YAF_getWidgetAttribute($viewid, $widgetid, "labeltype", "");
	$ret[1] = 			YAF_getWidgetAttribute($viewid, $widgetid, "size", 1);		#we don't process the size, so put it in the return array right away.

	#process data
	my $label = "";
	if($labeltype eq "Comment") {
		$label = AttrVal($fhemname,"comment",$fhemname);
	} elsif ($labeltype eq "Alias") {
		$label = AttrVal($fhemname,"alias",$fhemname);
	} else {
		$label = $fhemname;
	}
	$label =~ s/(_)/&nbsp;/g;

	$mode = ($mode eq "manual") ? " <span title='manual'>&oplus;</span>" : " <span title='$mode'>&otimes;</span>";
	$desi .= ($desi ne "off") ? " &deg;C" : "";
	$battery = ($battery ne "ok") ? "Check Battery: " . $battery . "<br />" : "";

	#create returnstring
	$ret[0] = "<span class='widget_fht80_alias'>" . $label . "</span><br />" . $battery;
	$ret[0] .= "<span title='$temptimestamp'>" . $temp . "</span>" . " &deg;C";
	if($nomode == 0) {
		$ret[0] .= $mode;
	}
	if($desi ne "off") {
		$ret[0] .= " <span title='Actuator: $actuator'>" . $desi . "</span>";
	}

	return encode_json(\@ret);
}
1;
