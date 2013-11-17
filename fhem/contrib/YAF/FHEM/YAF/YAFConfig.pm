########################################################################################
#
# YAFConfig.pm - sub-module to read and interpret the configuration file
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

my $yaf_version=0.45;

my %fhemwidgets;
my %fhemviews;
my %fhemviewbgs;
my $isInit = 0;

#######################################################################################
#
# YAF_FHEMConfig - Initializes the module after loading the Website
#				   Loads the distributed config from the devices
#
# no parameter
#
########################################################################################

sub YAF_FHEMConfig { #this is called via ajax when the page is loaded.
		#get the views
		my $views = AttrVal("yaf","views",undef);
		my $backgrounds = AttrVal("yaf", "backgrounds", undef);
		if(defined $views and $isInit == 0) {
			foreach my $view (split (/;/,$views)) {
				my @aview = split(/,/,$view);
				$fhemviews{$aview[0]} = $aview[1];
			}
			
			foreach my $bg (split (/;/,$backgrounds)) {
				my @abg = split(/,/,$bg);
				$fhemviewbgs{$abg[0]} = $abg[3];
			}			

			my $retAttr = "";
			foreach my $viewId (keys %fhemviews) {
				foreach my $key (keys %defs) {									#for every def in the system
					my $attrvalue = AttrVal($key,"yaf_$viewId",undef);			#check if it has the correct attribute set
					if (defined $attrvalue && length $attrvalue > 0) {			#if the attr is set
						my @tokens = split(/,/, $attrvalue);					#split the value by comma

						my @idarr = split(/=/,$tokens[0]);
						my $widgetId = $idarr[1];

						$fhemwidgets{$viewId}{$widgetId} = $key;
					}
				}
			}
		} else {
			return 0;
		}
		Log 3, "YAF initialized";
		$isInit = 1;
		return 1;
}

#######################################################################################
#
# YAF_getViews - Assembles defined views from config
#
# no parameter
# Returns pointer to array of views.
#
########################################################################################

sub YAF_getViews{
		my @viewsArray;
		my $index = 0;

		foreach my $view (keys %fhemviews){
				$viewsArray[$index][0] = $view;
				$viewsArray[$index][1] = $fhemviews{$view};
				$viewsArray[$index][2] = $fhemviewbgs{$view};
				$index++;
		}

		return \@viewsArray;
}

#######################################################################################
#
# YAF_getView - Assembles parts of a view from config
#
# viewId - The view id to search
# Returns Pointer to the view hash, hash may be empty
#
########################################################################################

sub YAF_getView{
		my $viewId = $_[0];
		my %viewHash = ();
		my @widgetsArray = ();

		foreach my $widget (keys %{$fhemwidgets{$viewId}}) {
			my @attributes = split(/,/,AttrVal($fhemwidgets{$viewId}{$widget},"yaf_".$viewId,undef));
			my %widgetHash = ();

			$widgetHash{fhemname} = $fhemwidgets{$viewId}{$widget};

			foreach my $attribute (@attributes){
				my @attrArr = split(/=/,$attribute);
				$widgetHash{$attrArr[0]} = $attrArr[1];
			}

			#my %attrHash = ();				#needed?
			#%attrHash = %widgetHash;

			push(@widgetsArray, \%widgetHash);
		}

		$viewHash{'widgets'} = \@widgetsArray;

		my @backgroundsArray = ();
		my @backgrounds = split (/;/,AttrVal("yaf","backgrounds",undef));
		foreach my $background (@backgrounds){
			my @attributes = split (/,/,$background);
			if ($attributes[0] eq $viewId) {
				my %backgroundHash = ();

				$backgroundHash{x_pos} = $attributes[1];
				$backgroundHash{y_pos} = $attributes[2];
				$backgroundHash{img_url} = $attributes[3];

				push(@backgroundsArray, \%backgroundHash);
			}
		}
		$viewHash{'backgrounds'} = \@backgroundsArray;
		return \%viewHash;
}

#######################################################################################
#
# YAF_editView - Edits the view with the given id
#
# viewId - The view id to search
# viewName The view name to be set
# @return 1 if successful, otherwise 0
#
########################################################################################

sub YAF_editView{
		my $viewId = $_[0];
		my $viewName = $_[1];
		my $viewImage = $_[2];

		my %viewhash = ();
		my %viewbghash = ();

		#load current config
		foreach my $views (split(/;/,AttrVal("yaf","views",undef))) {
			my @view = split(/,/,$views);
			$viewhash{$view[0]} = $view[1];
		}
		
		foreach my $bgs (split(/;/,AttrVal("yaf","backgrounds",undef))) {
			my @bg = split(/,/,$bgs);
			$viewbghash{$bg[0]} = $bg[3];
		}

		#set new config value
		$viewhash{$viewId} = $viewName;
		$viewbghash{$viewId} = $viewImage;

		#create new config
		my $newview = "";
		foreach my $key (keys %viewhash) {
			$newview .= $key . "," . $viewhash{$key} . ";;";
		}
		
		my $newbg = "";
		foreach my $key (keys %viewbghash) {
			$newbg .= $key . ",1,1," . $viewbghash{$key} . ";;";
		}		

		#save new config
		fhem ("attr yaf views $newview");
		fhem ("attr yaf backgrounds $newbg");

		return 1;
}

#######################################################################################
#
# YAF_deleteView - Deletes the view with the given id
#
# viewId - The view id to search
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_deleteView{
		my $viewId = $_[0];

		my %viewhash = ();
		my %backgroundhash = ();

		delete $fhemviews{$viewId};

		foreach my $delwidget (keys %{$fhemwidgets{$viewId}}) {
			YAF_deleteWidget($viewId,$delwidget);
		}

		delete $fhemwidgets{$viewId};

		my $userattr = AttrVal("global","userattr",undef);
		my $newuserattr = "";
		foreach my $attr (split (/ /,$userattr)) {
			if($attr ne "yaf_$viewId") {
				$newuserattr .= $attr . " ";
			}
		}

		#load current config
		foreach my $views (split(/;/,AttrVal("yaf","views",undef))) {
			my @view = split(/,/,$views);
			$viewhash{$view[0]} = $view[1];
		}

		foreach my $bgs (split(/;/,AttrVal("yaf","backgrounds",undef))) {
			my @bg = split(/,/,$bgs);
			$backgroundhash{$bg[0]} = $bg[1] . "," . $bg[2] . "," . $bg[3];
		}

		#create new config, leave out the deleted view
		my $newview = "";
		foreach my $key (keys %viewhash) {
			if($key ne $viewId) {
				$newview .= $key . "," . $viewhash{$key} . ";;";
			}
		}

		my $newbackground = "";
		foreach my $key (keys %backgroundhash) {
			if($key ne $viewId) {
				$newbackground .= $key . "," . $backgroundhash{$key} . ";;";
			}
		}

		if(length($newview) == 0) { #remove the attributes if they are empty
			fhem("deleteattr yaf views");
			fhem("deleteattr yaf backgrounds");
			fhem ("attr global userattr $newuserattr");
		} else {
		#save new config
			fhem ("attr yaf views $newview");
			fhem ("attr yaf backgrounds $newbackground");
			fhem ("attr global userattr $newuserattr");
		}

		return 1;
}

#######################################################################################
#
# YAF_addView - Add the view with the given id
#
# viewId - The view id to search
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_addView{
		my $viewName = $_[0];

		my %viewhash = ();
		my %backgroundhash = ();

		#-- determine id for new element
		my $newId = 0;
		my @views = sort {$a <=> $b} keys %fhemviews;

		foreach my $view (@views){
				my $tempId = $view;

				if($newId < $tempId){
						$newId = $tempId;
				}
		}
		$newId++;

 		my $newuserattr = AttrVal("global","userattr","") . " yaf_" . $newId;
		my $newview =  $newId . "," . $viewName. ";" .AttrVal("yaf","views","");
		my $newbackground = $newId . ",1,1,FILENAME;" . AttrVal("yaf","backgrounds","");

		#escape ";"
		$newview =~ s/;/;;/g;
		$newbackground =~ s/;/;;/g;

		#save new config
		$fhemviews{$newId} = $viewName;
		fhem ("attr yaf views $newview");
		fhem ("attr yaf backgrounds $newbackground");
		fhem ("attr global userattr $newuserattr");
		return 1;
}

#######################################################################################
#
# YAF_addWidget - Add widget the the view with the given id
#
# Parameters:
# widgetName The name of the new widget
# xPos The x coordinate of the widget position
# yPos The y coordinate of the widget position
# attributesArray The array of attribute elements
# @return The widget id if successful, otherwise 0
#
#########################################################################################

sub YAF_addWidget{
		if($_[0] ne "null") {	#if you want to add a widget, but there is no view
			my $viewId = $_[0];
			my $widgetName = $_[1];
			my $xPos = $_[2];
			my $yPos = $_[3];
			my @attributesArray = @{$_[4]};

			my $widgetString = "name=" . $widgetName . ",x_pos=" . $xPos . ",y_pos=" . $yPos;

			my $newId = 0;
			my @sortedWidgets = sort {$a <=> $b} (keys %{$fhemwidgets{$viewId}});
			foreach my $currentWidget (@sortedWidgets) {
				my $tempId = $currentWidget;

				if($newId < $tempId){
					$newId = $tempId;
				}
			}
			$newId++;
			$widgetString = "id=" . $newId . "," . $widgetString; #put id as first attribute

			#-- add widgets attributes
			my $fhemname = "";
			foreach my $attribute (@attributesArray){
				$widgetString .= "," . @$attribute[0] . "=" . @$attribute[1];

				if(@$attribute[0] eq "fhemname") {
					$fhemname = @$attribute[1];
				}
			}

			#-- append the new widget to the configuration
			$fhemwidgets{$viewId}{$newId} = $fhemname;
			if(defined AttrVal($fhemname,"yaf_$viewId",undef)) {
				Log 3, "Device $fhemname has already been added to view " . $fhemviews{$viewId};
				$newId = 0;
			} else {
				fhem("attr $fhemname yaf_$viewId $widgetString");
			}

			return $newId;
		} else {
			return 0;
		}
}

#######################################################################################
#
# YAF_deleteWidget - Delete the Widget
#
# Parameters
# viewId - The view id to search
# widgetId - The widget id
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_deleteWidget{
		my $viewId = $_[0];
		my $widgetId = $_[1];

		my $widgetname = $fhemwidgets{$viewId}{$widgetId};

		delete $fhemwidgets{$viewId}{$widgetId};

		fhem("deleteattr $widgetname yaf_$viewId");

		return 1;
}

#######################################################################################
#
# YAF_isWidget - test, if a FHEM device name is already a widget
#
# viewId - The view id to search
# fhemname - the name of a FHEM device
#
########################################################################################

sub YAF_isWidget {
		my $viewId = $_[0];
		my $fhemname = $_[1];

		if(defined AttrVal($fhemname,"yaf_".$viewId,undef)) {
			return 1;
		} else {
			return 0;
		}
}

#######################################################################################
#
# YAF_setWidgetPosition - Sets the position (x, y) of the widget to the given values
#
# Parameters
# viewId - The view id to search
# widgetId - The widget id
# @param xPos The new x coordinate of the widget position
# @param yPos The new y coordinate of the widget position
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_setWidgetPosition{
		my $viewId = $_[0];
		my $widgetId = $_[1];
		my $xPos = $_[2];
		my $yPos = $_[3];

		my $widgetname = $fhemwidgets{$viewId}{$widgetId};
		my %attrhash = ();

		foreach my $attrs (split (/,/,AttrVal($widgetname, "yaf_".$viewId, undef))) {
			my @attr = split(/=/,$attrs);
			$attrhash{$attr[0]} = $attr[1];
		}

		$attrhash{x_pos} = $xPos;
		$attrhash{y_pos} = $yPos;

		my $newattr = "id=" . $widgetId . ",";
		foreach my $key (keys %attrhash) {
			if ($key ne "id") {
				$newattr .= $key."=".$attrhash{$key}.",";
			}
		}

		fhem("attr $widgetname yaf_$viewId $newattr");
}

#######################################################################################
#
# YAF_getWidgetAttribute - Searches the widget attribute properties of the specified widget
#
# Parameters
# viewId - The view id to search
# widgetId - The widget id
# attributeName - name of the attribute properties to search for
# default - Value to return on undefined
#
# @return The value property if successful, otherwise 0
#
#######################################################################################

sub YAF_getWidgetAttribute{
		my $viewId = $_[0];
		my $widgetId = $_[1];
		my $attributeName = $_[2];
		my $default = (defined $_[3]) ? $_[3] : 0;
		my $regex = (defined $_[4]) ? $_[4] : 0;

		if($isInit == 0) {						#after a restart of fhem the config hashes might be empty, because they are filled while
			YAF_FHEMConfig();					#loading the "yaf.htm" page. However, when restarting FHEM without reloading the page, there
		}										#will be lots of errors. Since this method is called by any update method, we check if YAF
												#is initialized and load the config, if not.
		my $retAttr = "";
		my $widgetName = "";

		if(defined $fhemwidgets{$viewId}{$widgetId}) {
			$widgetName = $fhemwidgets{$viewId}{$widgetId};
		}

		if("fhemname" eq $attributeName) {						#special case: get the fhemname
			$retAttr = $widgetName;								#the key is the name of the device
		} else {
			my $attrString = AttrVal($widgetName,"yaf_$viewId",undef);
			if(defined $attrString) {
				my @tokens = split(/,/,$attrString);
				foreach my $akey (@tokens) {					#cycle through the other values
					my @skey = split(/=/, $akey);				#split them for =
					if($regex == 0) {
						if($skey[0] eq $attributeName) {			#the first value is the key, if it is the wanted attribute
							$retAttr = $skey[1];					#return it.
						}
					} else {
						if($attributeName =~ $skey[0]) {
							$retAttr = $skey[1];
						}
					}
				}
			}
		}
		if(length $retAttr > 0) {
			return $retAttr;											#return the found config
		} else {
			return $default;
		}
}

#######################################################################################
#
# YAF_getRefreshTime - Get refresh time interval
#
# @return time successful, otherwise 0
#
#######################################################################################

sub YAF_getRefreshTime{
		my $ret = AttrVal("yaf","refresh_interval",undef);
		if (defined $ret) {
			return $ret;
		} else {
			Log 1,"YAF_getRefreshTime: refresh_interval attribute was not found (so it will be created with a default value)";
			fhem("attr yaf refresh_interval 60");
			return 60;
		}
}

#######################################################################################
#
# YAF_setRefreshTime - Set refresh time interval to the given value
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_setRefreshTime{
		my $newRefreshInterval = $_[0];

		if($newRefreshInterval =~ /^\d+$/) {
			fhem("attr yaf refresh_interval $newRefreshInterval");
			return 1;
		} else {
			Log 1,"YAF_setRefreshTime: no valid refresh value or refresh attribute was not found";
			return 0;
		}
}

sub YAF_setWidgetAttribute{
		my $viewId = $_[0];
		my $widgetId = $_[1];
		my $key = $_[2];
		my $val = $_[3];

		my $widgetname = $fhemwidgets{$viewId}{$widgetId};
		my %attrhash = ();

		foreach my $attrs (split (/,/,AttrVal($widgetname, "yaf_".$viewId, undef))) {
			my @attr = split(/=/,$attrs);
			$attrhash{$attr[0]} = $attr[1];
		}

		$attrhash{$key} = $val;

		my $newattr = "id=" . $widgetId . ",";
		foreach my $ckey (keys %attrhash) {
			if ($ckey ne "id" and defined $attrhash{$ckey}) {
				$newattr .= $ckey."=".$attrhash{$ckey}.",";
			}
		}

		fhem("attr $widgetname yaf_$viewId $newattr");
}
1;
