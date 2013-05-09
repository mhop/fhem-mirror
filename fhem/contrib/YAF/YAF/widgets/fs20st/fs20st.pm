########################################################################################
#
# fs20st.pm - YAF widget for device FS20ST
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
# fs20st_get_widgetcss - Create the CSS code for this widget
# 
# no parameter
#
########################################################################################

sub fs20st_get_widgetcss() {
	my $output = "
		.widget_fs20st {
            width: 33px;
            height: 33px;
            background-repeat:no-repeat;
            background-position:center center;
            opacity:1 !important;
		}
		
		.widget_fs20st_on {
			background-image:url(./img/lamp_on.png) !important;
		}
		
		.widget_fs20st_off {
			background-image:url(./img/lamp_off.png) !important; 
		}
	";
	return $output;
}

########################################################################################
#
# fs20st_get_widgetjs - Create the JavaScript code for this widget
# 
# no parameter
#
########################################################################################

sub fs20st_get_widgetjs() {
	
	my $output = '
		function fs20st_on_click(view_id, widget_id) {
			var widget = $("#widget_"+view_id+"_"+widget_id);
			var newState;
			if (widget.hasClass("widget_fs20st_on")) {
				newState = "off";
			} else{
				newState = "on";
			}
			$.ajax({
				type: "GET",
				async: true,
				url: "../../ajax/widget/fs20st/set_state",
				data: "view_id="+view_id+"&widget_id="+widget_id+"&state="+newState,
				context: document.body,
				success: function(){
						fs20st_update_widget(view_id, widget_id);
				}
			});
		}
		
		function fs20st_update_widget(view_id, widget_id) {
            $.ajax({
		 		type: "GET",
				async: true,
				url: "../../ajax/widget/fs20st/get_state",
				data: "view_id="+view_id+"&widget_id="+widget_id,
				context: document.body,
				success: function(state) {
					var widget = $("#widget_"+view_id+"_"+widget_id);
					if (state == "off") {
						if (widget.hasClass("widget_fs20st_on")) {
							widget.removeClass("widget_fs20st_on");
						}
						if (!widget.hasClass("widget_fs20st_off")) {
							widget.addClass("widget_fs20st_off");
						}
					}
					else if (state == "on") {
						if (!widget.hasClass("widget_fs20st_on")) {
							widget.addClass("widget_fs20st_on");
						}
						if (widget.hasClass("widget_fs20st_off")) {
							widget.removeClass("widget_fs20st_off");
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
# fs20st_getwidgethtml - HTML code for this widget
# 
# no parameter
#
########################################################################################

sub fs20st_get_widgethtml() {
        my $output = "";
        return $output;
}

########################################################################################
#
# fs20st_get_addwidget_setup_html - Create the selection of devices for this widget
# 
# no parameter
#
########################################################################################

sub fs20st_get_addwidget_setup_html() {
	my $output = "<script src='js/combobox.js'></script>
				  <select name='fs20_combobox' id='combobox'>";
	my @list = (keys %defs);
	
	foreach my $d (sort @list) {
	    my $type  = $defs{$d}{TYPE};
	    my $name  = $defs{$d}{NAME};
	    
	    if( $type eq "FS20" ){
	      my $model = defined(AttrVal($name,"model",undef)) ? AttrVal($name,"model",undef) : "";
	      if( $model eq "fs20st" ){
	        #-- ignore those that are already defined in this view
	    	$output = $output."<option value='$name'>$name</option>"
	    	  if( !YAF_isWidget($_GET{"view_id"},$name) );
	    } 
	  }
	}
	
	$output = $output."</select>";
	
	return $output;	
}

########################################################################################
#
# fs20st_get_addwidget_prepare_attributes - 
# 
# no parameter
#
########################################################################################

sub fs20st_get_addwidget_prepare_attributes() {
	my $output = '
		var temp_array = new Array();
		temp_array[0] = "fhemname";
		temp_array[1] = $("#combobox option:selected").val()
		attributes_array[0] = temp_array;
	';
	return $output;	
}

########################################################################################
#
# fs20st_getwidget_html - HTML code for this widget. DO WE NEED THIS ? SEE ABOVE
# 
# no parameter
#
########################################################################################

sub fs20st_getwidget_html() {
	my $output = " ";
	return $output;	
}

########################################################################################
#
# fs20st_get_state - return the state of the switch
# 
# no parameter
#
########################################################################################

sub fs20st_get_state () {
	my $name = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "fhemname");
	my $d    = $defs{$name};
	return $d->{STATE};
}

########################################################################################
#
# fs20st_set_state - set the state of the switch
# 
# no parameter
#
########################################################################################

sub fs20st_set_state() {
	my $name = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "fhemname");
	Log 3, "set ".$name." ".$_GET{"state"};
	fhem   "set ".$name." ".$_GET{"state"};
}

1;