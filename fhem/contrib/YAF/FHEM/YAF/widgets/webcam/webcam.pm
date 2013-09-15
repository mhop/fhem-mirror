########################################################################################
#
# webcam.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
#
# webcam Widget: Marc Pro
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
# webcam_get_widgetcss - Create the CSS code for this widget
#
# no parameter
#
########################################################################################
sub webcam_get_widgetcss() {
		my $output = "
				.widget_webcam {
					width: 100px;
					height: 100px;
					background-repeat:no-repeat;
					background-position:center center;
					opacity:1 !important;
				}				
		";
		return $output;
}

########################################################################################
#
# webcam_get_widgetjs - Create the javascript code for this widget
#
# no parameter
#
########################################################################################

sub webcam_get_widgetjs() {
		my $output = '
				function webcam_endsWith(str, suffix) {
					return str.indexOf(suffix, str.length - suffix.length) !== -1;
				}
						function webcam_on_click(view_id, widget_id) {
		}
				function webcam_update_widget(view_id, widget_id) {
					$.ajax({
						type: "GET",
						async: true,
						url: "../../ajax/widget/webcam/get_state",
						data: "view_id="+view_id+"&widget_id="+widget_id,
						context: document.body,
						success: function(get_state) {
							var widget = $("#widget_"+view_id+"_"+widget_id);
							widget.html(get_state);
						}
					});
				}
		';
		return $output;
}

########################################################################################
#
# webcamt_getwidgethtml - HTML code for this widget
#
# no parameter
#
########################################################################################

sub webcam_get_widgethtml() {
		my $output = " ";
		return $output;
}

########################################################################################
#
# webcamt_get_addwidget_setup_html - Create the selection of devices for this widget
#
# no parameter
#
########################################################################################

sub webcam_get_addwidget_setup_html() {
		my $output = "<script src='js/combobox.js'></script>
								  <select name='webcam_combobox' id='combobox'>";
		my @list = (keys %defs);

		foreach my $d (sort @list) {
			my $type  = $defs{$d}{TYPE};
			my $name  = $defs{$d}{NAME};

			if(lc $type eq "presence" or lc $type eq "dummy"){

				$output = $output."<option value='$name'>$name</option>";
			}
		}

		$output = $output."</select>";

		return $output;
}

########################################################################################
#
# webcamt_get_addwidget_prepare_attributes -
#
#
# no parameter
#
########################################################################################

sub webcam_get_addwidget_prepare_attributes() {
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
# webcamt_getwidget_html - HTML code for this widget. DO WE NEED THIS ? SEE ABOVE
# DO WE NEED IT? WHO KNOWS. (It looks like this one fills the initial html of the
#							widget, so let's keep it for science.)
#
# no parameter
#
########################################################################################

sub webcam_getwidget_html() {
		my $output = " ";
		return $output;
}

########################################################################################
#
# webcamt_get_lamp_status - return the state of the lamp
#
# no parameter
#
########################################################################################

sub webcam_get_state() {
		my $fhemname = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "fhemname");	#get name of device
		
		my $showm = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "showmethod", "img");
		my $spath = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "path");
		my $hover = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "hover", "0");
		my $proto = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "protocol", "http");
		my $width = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "width", "100");
		
		my $address = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "address", $defs{$fhemname}{ADDRESS});
		
		my $d = $defs{$fhemname};																	#get device
		my $name = AttrVal($fhemname,"alias",undef);												#get alias
		if(!defined $name) {																		#if alias is defined, use it as name
			$name = $fhemname;
		}
		if(defined $d) {
			if(lc $showm eq "img") {
				my $ret = "<img style=\"border:1px solid black;\" src=\"".$proto."://".$address.$spath."\" width=\"".$width."\">";
				return $ret;
			}
		} else {
			return "<span onClick=document.location.reload(true)>Widget not found. Maybe reload this page?</span>";
		}
}
1;