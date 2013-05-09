########################################################################################
#
# fs20easylamp.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
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
# fs20easylamp_get_widgetcss - Create the CSS code for this widget
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_widgetcss() {
	my $output = "
		.widget_fs20easylamp {
            width: 33px;
            height: 33px;
            background-repeat:no-repeat;
            background-position:center center;
            opacity:1 !important;
		}
		
		.widget_fs20easylamp_on {
			background-image:url(./img/lamp_on.png) !important;
		}
		
		.widget_fs20easylamp_off {
			background-image:url(./img/lamp_off.png) !important; 
		}
	";
	return $output;
}

########################################################################################
#
# fs20easylamp_get_widgetjs - Create the javascript code for this widget
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_widgetjs() {
	
	my $output = '
		function fs20easylamp_on_click(view_id, widget_id) {
			var widget = $("#widget_"+view_id+"_"+widget_id);
			var newState;
			if (widget.hasClass("widget_fs20easylamp_on")) {
				newState = "off";
			} else{
				newState = "on";
			}
			$.ajax({
				type: "GET",
				async: true,
				url: "../../ajax/widget/fs20easylamp/set_lamp_status",
				data: "view_id="+view_id+"&widget_id="+widget_id+"&status="+newState,
				context: document.body,
				success: function(){
						fs20easylamp_update_widget(view_id, widget_id);
				}
			});
		}
		
		function fs20easylamp_update_widget(view_id, widget_id) {
            $.ajax({
		 		type: "GET",
				async: true,
				url: "../../ajax/widget/fs20easylamp/get_lamp_status",
				data: "view_id="+view_id+"&widget_id="+widget_id,
				context: document.body,
				success: function(lamp_status) {
					var widget = $("#widget_"+view_id+"_"+widget_id);
					if (lamp_status == "off") {
						if (widget.hasClass("widget_fs20easylamp_on")) {
							widget.removeClass("widget_fs20easylamp_on");
						}
						if (!widget.hasClass("widget_fs20easylamp_off")) {
							widget.addClass("widget_fs20easylamp_off");
						}
					}
					else if (lamp_status == "on") {
						if (!widget.hasClass("widget_fs20easylamp_on")) {
							widget.addClass("widget_fs20easylamp_on");
						}
						if (widget.hasClass("widget_fs20easylamp_off")) {
							widget.removeClass("widget_fs20easylamp_off");
						}	
					}
				}   
			});
		}
	';
	return $output;
}

########################################################################################
#
# fs20easylamp_getwidgethtml - HTML code for this widget
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_widgethtml() {
        my $output = "";
        return $output;
}

########################################################################################
#
# fs20easylamp_get_addwidget_setup_html - Create the selection of devices for this widget
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_addwidget_setup_html() {
	my $output = "<script src='js/combobox.js'></script>
				  <select name='fs20_combobox' id='combobox'>";
	my @list = (keys %defs);
	
	foreach my $d (sort @list) {
	    my $type  = $defs{$d}{TYPE};
	    my $name  = $defs{$d}{NAME};

	    if( $type eq "FS20"){
	    	
	    	$output = $output."<option value='$name'>$name</option>";
	    } 
	}
	
	$output = $output."</select>";
	
	return $output;	
}

########################################################################################
#
# fs20easylamp_get_addwidget_prepare_attributes - 
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_addwidget_prepare_attributes() {
	my $output = '
		var temp_array = new Array();
		temp_array[0] = "attribute";
		temp_array[1] = $("#combobox option:selected").val()
		attributes_array[0] = temp_array;
	';
	return $output;	
}

########################################################################################
#
# fs20easylamp_getwidget_html - HTML code for this widget. DO WE NEED THIS ? SEE ABOVE
# 
# no parameter
#
########################################################################################

sub fs20easylamp_getwidget_html() {
	my $output = " ";
	return $output;	
}

########################################################################################
#
# fs20easylamp_get_lamp_status - return the state of the lamp
# 
# no parameter
#
########################################################################################

sub fs20easylamp_get_lamp_status () {
	my $attribute = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "attribute");
	my $d = $defs{$attribute};
	return $d->{STATE};
}

########################################################################################
#
# fs20easylamp_set_lamp_status - set the state of the lamp
# 
# no parameter
#
########################################################################################

sub fs20easylamp_set_lamp_status() {
	my $attribute = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "attribute");
	my $d = $defs{$attribute};
	Log 3, "set ".$d->{NAME}." ".$_GET{"status"};
	fhem "set ".$d->{NAME}." ".$_GET{"status"};
}

1;