########################################################################################
#
# generic.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
#
# generic Widget: Marc Pro
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
# generic_get_widgetcss - Create the CSS code for this widget
#
# no parameter
#
########################################################################################
sub generic_get_widgetcss() {
        my $output = "
                .widget_generic {
					width: 200px;
					height: 50px;
					background-repeat:no-repeat;
					background-position:center center;
					opacity:1 !important;
					text-align: center;
                }
        ";
        return $output;
}

########################################################################################
#
# generic_get_widgetjs - Create the javascript code for this widget
#
# no parameter
#
########################################################################################

sub generic_get_widgetjs() {

        my $output = '
				function generic_endsWith(str, suffix) {
					if(!str) {
						return false;
					}
					return str.indexOf(suffix, str.length - suffix.length) !== -1;
				}

				function generic_on_click(view_id, widget_id) {
					$.ajax({
						type: "GET",
						async: true,
						url: "../../ajax/widget/generic/on_click",
						data: "view_id="+view_id+"&widget_id="+widget_id,
						context: document.body,
						success: function(data){
								var mydata = jQuery.parseJSON(data);
								if(mydata[0] == "redirect") {
									window.location.href = mydata[1];
								} else {
									generic_update_widget(view_id, widget_id);
								}

						}
					});
				}

                function generic_update_widget(view_id, widget_id) {
					$.ajax({
						type: "GET",
						async: true,
						url: "../../ajax/widget/generic/get_state",
						data: "view_id="+view_id+"&widget_id="+widget_id,
						context: document.body,
						success: function(get_state) {
							var data = jQuery.parseJSON(get_state);
							var label = data[0];
							var icon = data[1];
							var statesave = $("#widget_generic_state_"+view_id+"_"+widget_id);
							var state = data[2];
							var statespan = data[3];
							var fhemname = data[4];
							var widget = $("#widget_"+view_id+"_"+widget_id);

							if (!statesave.hasClass("widget_generic_"+state)) {
								if(generic_endsWith(icon,"png")) {
									var iconstring = label+"<br /><img src="+icon+" title="+label+"&nbsp;&#10;"+fhemname+"&nbsp;&#10;"+ state +" />"+statespan;
									widget.html(iconstring);
								} else {
									var textstring = "<span title="+fhemname+" >"+label+"</span><br />" + state;
									widget.html(textstring+" "+statespan);
								}
							}
						}
                    });
                }';

	# $output .='
				# function generic_get_reading_keys() {
					# $.ajax({
						# type: "GET",
						# async: true,
						# url: "../../ajax/widget/generic/get_reading_keys",
						# data: "fhemname="+$("#combobox").val(),
						# context: document.body,
						# success: function(dataarr) {
							# var data = jQuery.parseJSON(dataarr);
							# //alert(data[0]);
							# var mySelect = $("#generic_combobox_readings");
							# mySelect
								# .find("option")
								# .remove()
								# .end()
							# ;
# ;
							# $.each(data, function(val,text) {
								# mySelect.append(
									# $("<option></option>").val(text).html(text)
								# );
							# });
						# }
					# });
				# }
        # ';
        return $output;
}

########################################################################################
#
# generic_getwidgethtml - HTML code for this widget
#
# no parameter
#
########################################################################################

sub generic_get_widgethtml() {
        my $output = " ";
        return $output;
}

########################################################################################
#
# generic_get_addwidget_setup_html - Create the selection of devices for this widget
#
# no parameter
#
########################################################################################

sub generic_get_addwidget_setup_html() {
		my $output = "";
        $output = "<script src='js/combobox.js'></script>";
        $output .="<select name='generic_combobox' id='combobox' onClick=generic_get_reading_keys()>";
        my @list = (keys %defs);

        foreach my $d (sort @list) {
            my $type  = $defs{$d}{TYPE};
            my $name  = $defs{$d}{NAME};
			if(defined $name) {
				$output .= "<option value='$name'>$name</option>";
			}
        }

        $output .= "</select>";
		# $output .= "<br />Use Reading as state: <select name='generic_combobox_readings' id ='generic_combobox_readings' />";
		# $output .= "<span onClick=generic_get_reading_keys('FHT_1b1b')>TEST</span>";
        return $output;
}

# sub generic_get_reading_keys() {
		# my $fhemname = $_GET{"fhemname"};

		# my @ret = ();
		# Log 3, "Loading Shit";
		# foreach my $r (keys %{$defs{$fhemname}{READINGS}}) {
			# Log 3,$r;
			# push(@ret,$r);
		# }

		# return encode_json(\@ret);
# }

sub generic_get_editwidget_setup_html() {
		my $viewId = $_GET{"view_id"};
		my $widgetId = $_GET{"widget_id"};
		my $output = "";

		my $fhemname = YAF_getWidgetAttribute($viewId, $widgetId, "fhemname", "");
		my $labeltype = YAF_getWidgetAttribute($viewId, $widgetId, "labeltype","");
		my $statetype = YAF_getWidgetAttribute($viewId, $widgetId, "statetype","");
		my $showlabel = YAF_getWidgetAttribute($viewId, $widgetId, "showlabel","1");
		my $showicon = YAF_getWidgetAttribute($viewId, $widgetId, "showicon","1");

		$output .= "<label title='Name des Devices'>Name:</label><input class='input_edit_widget' disabled='disabled' name='fhemname' value='" . $fhemname . "' /><br />";
		$output .= "<label title='Welches Attributfeld soll als Label des Widgets gezeigt werden?'>Label (Attribut):</label><input class='input_edit_widget' name='labeltype' value='" . $labeltype . "' /><br />";
		$output .= "<label title='Welches Reading soll als Status gezeigt werden?'>Status (Reading):</label><input class='input_edit_widget' name='statetype' value='" . $statetype . "' /><br />";
		$output .= "<label title='Soll das Label angezeigt werden?'>Label anzeigen? (1/0):</label><input class='input_edit_widget' name='showlabel' value='" . $showlabel . "' /><br />";
		$output .= "<label title='Soll das Icon angezeigt werden?'>Icon anzeigen? (1/0):</label><input class='input_edit_widget' name='showicon' value='" . $showicon . "' /><br />";
		return $output;
}

########################################################################################
#
# generic_get_addwidget_prepare_attributes -
#
#
# no parameter
#
########################################################################################

sub generic_get_addwidget_prepare_attributes() {
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
# generic_getwidget_html - HTML code for this widget. DO WE NEED THIS ? SEE ABOVE
# DO WE NEED IT? WHO KNOWS. (It looks like this one fills the initial html of the
#                            widget, so let's keep it for science.)
#
# no parameter
#
########################################################################################

sub generic_getwidget_html() {
        my $output = " ";
        return $output;
}

########################################################################################
#
# generic_get_lamp_status - return the state of the lamp
#
# no parameter
#
########################################################################################

sub generic_get_state() {
		my $viewId = $_GET{"view_id"};
		my $widgetId = $_GET{"widget_id"};

        my $fhemname = YAF_getWidgetAttribute($viewId, $widgetId, "fhemname", "");
		my $labeltype = YAF_getWidgetAttribute($viewId, $widgetId, "labeltype","");
		my $statetype = YAF_getWidgetAttribute($viewId, $widgetId, "statetype","");
		my $showlabel = YAF_getWidgetAttribute($viewId, $widgetId, "showlabel","1");
		my $showicon = YAF_getWidgetAttribute($viewId, $widgetId, "showicon","1");

		my $d = $defs{$fhemname};
		my $state = $d->{STATE};
		my $iconpath = "";
		my @ret = ();

		if(!defined $state) {
			$state = "no-state-defined";
		}

		if(defined $d) {
			my $devStateIcon = AttrVal($fhemname,"devStateIcon",undef);
			if(defined $devStateIcon) {
				foreach my $entry (split (/ /,$devStateIcon)) {
					my @keyval = split(/:/,$entry);
					my $regex = $keyval[0];
					if($state =~ m/$regex/) {
						$iconpath = "/fhem/images/default/" . $keyval[1] . ".png";
					}
				}
				$ret[1] = $iconpath;
			}

			if($labeltype ne "") {
				$ret[0] = AttrVal($fhemname,$labeltype,$fhemname);
			} else {
				$ret[0] = $fhemname;
			}
			$ret[0] =~ s/( )/&nbsp;/g;

			if($statetype ne "") {
				$ret[2] = ReadingsVal($fhemname, $statetype, "no-reading");
			} else {
				$ret[2] = $state;
			}

			$ret[3] = "<span id=widget_generic_state_".$_GET{"view_id"}."_".$_GET{"widget_id"}." class=widget_generic_".$ret[2]." />";

			if($showlabel==0) {
				$ret[0] = "";
			}

			if($showicon==0) {
				$ret[1] = "";
			}

			$ret[4] = $fhemname;

			return encode_json(\@ret);
		} else {
			return "Widget not found. Maybe reload this page?";
		}
}

sub generic_on_click() {
		my $fhemname = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "fhemname");
		my $d = $defs{$fhemname};
		my $clicklink = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "clicklink", "");
		my @ret = ();
		if($clicklink ne "") {
			if($clicklink eq "_detail") {
				$ret[0] = "redirect";
				$ret[1] = "/fhem?detail=" . $fhemname;

			} else {
				$ret[0] = "redirect";
				$ret[1] = $clicklink;
			}
			return encode_json(\@ret);
		}
		my $setstate = YAF_getWidgetAttribute($_GET{"view_id"}, $_GET{"widget_id"}, "_".$d->{STATE}, "",1);

		if($setstate ne "") {
			fhem("set " . $fhemname . " " . $setstate);
			$ret[0] = "setstate";
			return encode_json(\@ret);
		}
}

1;

