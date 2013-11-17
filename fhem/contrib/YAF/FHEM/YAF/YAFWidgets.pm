########################################################################################
#
# YAFWidgets.pm
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

my $yaf_version = 0.45;
my $mp = AttrVal("global", "modpath", ".");
my $yaf_dir = $mp."/FHEM/YAF/";
my @yaf_widgets;

#######################################################################################
#
# YAF_YAF_getWidgetArray
# 
# no parameter
#
########################################################################################

sub YAF_getWidgetArray() {
	@yaf_widgets = ();
	my $widgets_directory = $yaf_dir."widgets/";
	#-- open directory with widgets
	if( !opendir(DIR, $widgets_directory) ){
	  Log 1,"YAF: directory with widgets not found";
      return undef;
    }
	my $is_dir = 0;
	#-- loop through all subdirectories
	while (my $entry = readdir DIR) {
		#-- check if it is really a directory
		if (-d $widgets_directory.$entry) {
			$is_dir = 1;
			#-- check for proper file widgetname.pm
			if (-e $widgets_directory.$entry."/".$entry.".pm") {
				$yaf_widgets[scalar(@yaf_widgets)] = $entry;
			}
		}
	}
	#-- close directory
	closedir DIR;	
	return @yaf_widgets;
}

#######################################################################################
#
# YAF_requireWidgets - load all widgets
# 
# no parameter
#
########################################################################################

sub YAF_requireWidgets() {
	YAF_getWidgetArray();
	foreach (@yaf_widgets){
		require($yaf_dir."widgets/".$_."/".$_.".pm");
	}
	return 1;
}

#######################################################################################
#
# YAF_getWidgetsCss - assemble the CSS code of all widgets
# 
# no parameter
#
########################################################################################

sub YAF_getWidgetsCss() {
	my $output_widget_css = "";
	foreach (@yaf_widgets){
		my $widget_css = "";
		$widget_css = eval($_."_get_widgetcss();");
		$output_widget_css .= $widget_css;
	}
	return $output_widget_css;
}

#######################################################################################
#
# YAF_getWidgetsJs - assemble the JavaScript code of all widgets
# 
# no parameter
#
########################################################################################

sub YAF_getWidgetsJs() {
	my $output_widget_js = "";
	foreach (@yaf_widgets){
		my $widget_js = "";
		$widget_js = eval($_."_get_widgetjs();");
		$output_widget_js .= $widget_js;
	}
	return $output_widget_js;
}

1;