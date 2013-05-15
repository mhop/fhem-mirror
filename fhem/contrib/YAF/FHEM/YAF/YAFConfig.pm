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
use XML::LibXML;
use XML::LibXML::PrettyPrint;

my $yaf_version=0.41;
my $mp   = AttrVal("global", "modpath", ".");
my $configurationFilepath = $mp."/FHEM/YAF/xml/yafConfig.xml";
my $schemaFilepath = $mp."/FHEM/YAF/xml/xmlSchema.xsd";
my $xmlSchema;
my $prettyPrinter;
my $config;

#######################################################################################
#
# YAF_Config - Initializes this module by creating the schema, pretty printer and 
#              loading the configuration from the filepath
# 
# no parameter
#
########################################################################################

sub YAF_Config {
        $xmlSchema     = XML::LibXML::Schema->new(location => $schemaFilepath);
        $prettyPrinter = XML::LibXML::PrettyPrint->new(indent_string => "  ");
        $config        = XML::LibXML->load_xml(location => $configurationFilepath);
        YAF_validate();
}

#######################################################################################
#
# YAF_validate - Validates the current state of the configuration instance
# 
# no parameter
# Returns 1 if valid, otherwise 0.
#
########################################################################################

sub YAF_validate{
	eval{ $xmlSchema->validate($config); };

	if($@){
		Log 1,"YAF: error validating configuration file";
		return 0;
	}
	return 1;
}

#######################################################################################
#
# YAF_getViews - Assembles defined views from configuration file
# 
# no parameter
# Returns pointer to array of views.
#
########################################################################################

sub YAF_getViews{
        my @views = $config->findnodes('//view');
        my @viewsArray;
        my $index = 0;
        
        foreach my $view (@views){
                $viewsArray[$index][0] = $view->findvalue('@id');
                $viewsArray[$index][1] = $view->findvalue('@name');             
                $index++; 
        }
        
        return \@viewsArray;
}

#######################################################################################
#
# YAF_getView - Assembles parts of a view from configuration file
# 
# viewId - The view id to search
# Returns Pointer to the view hash, hash may be empty
#
########################################################################################

sub YAF_getView{
        my $viewId = $_[0];
        
        my %viewHash = ();
        
        #-- query view id
        my $viewResult = $config->findnodes('//view[@id = '.$viewId.']');
        if($viewResult->size() == 1){
	        my $view = $viewResult->get_node(0);
	        
	        #-- prepare view hash and add simple key/value pairs (name)     
	        $viewHash{'name'} = $view->findvalue('@name');
	
	        #-- collect all widgets and add them to an array which is then connected to the view hash
	        my @widgetsArray = ();
	        my @widgets = $view->findnodes('widgets/widget');
	        
			foreach my $widget (@widgets){
	                my @attributes = $widget->attributes();
	                my %widgetHash = ();
	                
	                foreach my $attribute (@attributes){
	                        $widgetHash{$attribute->nodeName} = $attribute->getValue();
	                }
	                
				#-- collect attr nodes in a hash and add to widget
				my %attrHash = ();
				my @attrs = $widget->getChildrenByTagName('attr');
			
				foreach my $attr (@attrs){
					my $key = $attr->findvalue('@name');
					my $value = $attr->findvalue('@value');
					$attrHash{$key} = $value;
				}
				$widgetHash{'attr'} = \%attrHash;
			
			
				push(@widgetsArray, \%widgetHash);
	        }
	        $viewHash{'widgets'} = \@widgetsArray;
	        
	        #-- collect all backgrounds and add them to an array which is then connected to the view hash
	        my @backgroundsArray = ();
	        my @backgrounds = $view->findnodes('backgrounds/background');
	        
	        foreach my $background (@backgrounds){
	                my @attributes = $background->attributes();
	                my %backgroundHash = ();
	                
	                foreach my $attribute (@attributes){
	                        $backgroundHash{$attribute->nodeName} = $attribute->getValue();
	                }
	                
	                push(@backgroundsArray, \%backgroundHash);
	        }
	        $viewHash{'backgrounds'} = \@backgroundsArray;        	
       } else{
       	     Log 1,"YAF_getView: view with id = ".$viewId." was not found";
       }
       
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
        
        my $viewResult = $config->findnodes('//view[@id = '.$viewId.']');
        if($viewResult->size() == 1){
        	my $view = $viewResult->get_node(0);
        	$view->setAttribute('name', $viewName);
        	YAF_saveConfiguration();
        	return 1;
        } else {
        	Log 1,"YAF_editView: view with id = ".$viewId." was not found";
        	return 0;
        }
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
        
        my $viewResult = $config->findnodes('//view[@id = '.$viewId.']');
        if($viewResult->size() == 1){
         	my $view = $viewResult->get_node(0);
	        my $views = $view->parentNode;
	        $views->removeChild($view);
	        YAF_saveConfiguration();
	        return 1;
        } else{
	                	Log 1,"YAF_deleteView: view with id = ".$viewId." was not found";
	        return 0;	
	    }
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
        
        #-- determine id for new element
        my $newId = 0;
        my @views = $config->findnodes('//view');
        
        foreach my $view (@views){
                my $tempId = $view->findvalue('@id'); 
                
                if($newId < $tempId){
                        $newId = $tempId;
                }
        }
        $newId++;
        
        #-- initialize view and append to document
        my $view = $config->createElement('view');
        $view->setAttribute('id', $newId);
        $view->setAttribute('name', $viewName);
        #-- set default background
 		my $backgrounds = $config->createElement('backgrounds');
 		my $background = $config->createElement('background');
 		$background->setAttribute('img_url', "./img/background.png");
 		$background->setAttribute('x_pos', 1);
 		$background->setAttribute('y_pos', 1);
 		$backgrounds->appendChild($background);
 		$view->appendChild($backgrounds);
 		#-- initialize empty widgets node
 		my $widgets = $config->createElement('widgets');
 		$view->appendChild($widgets);
 		
 		#-- add new view to configuration
 		my $parent = $config->findnodes('//views')->get_node(0);
 		$parent->appendChild($view);
        
        YAF_saveConfiguration();
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
        my $viewId = $_[0];
        my $widgetName = $_[1];
        my $xPos = $_[2];
        my $yPos = $_[3];
        my @attributesArray = @{$_[4]};
        
        my $viewsResult = $config->findnodes('//view[@id = '.$viewId.']');
        if($viewsResult->size() == 1){
        	my $view = $viewsResult->get_node(0);
    
            #-- create a new widget with given properties
	        my $widget = $config->createElement('widget');
	        $widget->setAttribute('name', $widgetName);
	        $widget->setAttribute('x_pos', $xPos);
	        $widget->setAttribute('y_pos', $yPos);
	        my @widgets = $view->findnodes('widgets/widget');
	        my $newId = 0;
	        
	        foreach my $currentWidget (@widgets){
	                my $tempId = $currentWidget->findvalue('@id'); 
	                
	                if($newId < $tempId){
	                        $newId = $tempId;
	                }
	        }
	        $newId++;
	        $widget->setAttribute('id', $newId);
	        
	        #-- add widgets attribute nodes
	        foreach my $attribute (@attributesArray){
	        	my $attr = $config->createElement('attr'); 	
	            $attr->setAttribute('name', @$attribute[0]);
	       		$attr->setAttribute('value', @$attribute[1]);
	        	$widget->appendChild($attr);
	        }
	        
		    #-- append the new widget to the configuration
	        my $widgetsNode = $view->findnodes('widgets')->get_node(0);
	        $widgetsNode->appendChild($widget);
	        
	        YAF_saveConfiguration();
	        return $newId;   
        } else{
        	Log 1,"YAF_addWidget: view with id = ".$viewId." was not found";
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
	
	my $widgetResult = $config->findnodes('//view[@id = '.$viewId.']/widgets/widget[@id = '.$widgetId.']');
	if($widgetResult->size() == 1){
		my $widget = $widgetResult->get_node(0);
		my $widgets = $widget->parentNode;
		$widgets->removeChild($widget);
		
		YAF_saveConfiguration();
		return 1;
	} else{
		Log 1,"YAF_deleteWidget: widget with id = ".$widgetId." in view with id = ".$viewId." was not found";
		return 0;	
	}
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
	my $ret = 0;

	my $widgetResult = $config->findnodes('//view[@id = '.$viewId.']/widgets/widget/attr[@value = "'.$fhemname.'"]');
	$ret = 1
	  if($widgetResult->size() != 0);
	#Log 1,"YAF_isWidget: Checking with XPath //view[\@id = ".$viewId."]/widgets/widget/attr[\@value = \"".$fhemname."\"] => $ret";
	
	return $ret;
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
        
        my $widgetResult = $config->findnodes('//view[@id = '.$viewId.']/widgets/widget[@id = '.$widgetId.']');
        if($widgetResult->size() == 1){
        	my $widget = $widgetResult->get_node(0);
	        $widget->setAttribute('x_pos', $xPos);
	        $widget->setAttribute('y_pos', $yPos);
	        
	        YAF_saveConfiguration();
	        return 1;
        } else{
        	Log 1,"YAF_setWidgetPosition: widget with id = ".$widgetId." in view with id = ".$viewId." was not found";
        	return 0;
        }
}

#######################################################################################
#
# YAF_getWidgetAttribute - Searches the widget attribute properties of the specified widget
# 
# Parameters
# viewId - The view id to search
# widgetId - The widget id
# attributeName - name of the attribute properties to search for
#
# @return The value property if successful, otherwise 0
#
#######################################################################################

sub YAF_getWidgetAttribute{
	my $viewId = $_[0];
	my $widgetId = $_[1];
	my $attributeName = $_[2];
	
	my $attributes = $config->findnodes('//view[@id = '.$viewId.']/widgets/widget[@id = '.$widgetId.']/attr');
	
	foreach my $attr (@{$attributes}){
		if ($attr->getAttribute('name') eq $attributeName) {
			return $attr->getAttribute('value');
		}
	}
	Log 1,"YAF_getWidgetAttribute: attribute $attributeName was not found for widget with id = $widgetId";
	return 0;
}

#######################################################################################
#
# YAF_getRefreshTime - Get refresh time interval
# 
# @return time successful, otherwise 0
#
#######################################################################################

sub YAF_getRefreshTime{
	my $refreshNodeResult = $config->findnodes('configuration/settings/refresh');
	if($refreshNodeResult->size() == 1){
		my $refreshNode = $refreshNodeResult->get_node(0);
		my $refreshTime = $refreshNode->getAttribute('interval');	
		return $refreshTime;
	} else{
		Log 1,"YAF_getRefreshTime: refresh node was not found";
		return 0;		
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
	
	my $refreshNodeResult = $config->findnodes('configuration/settings/refresh');
	if(($newRefreshInterval =~ /^\d+$/) && ($refreshNodeResult->size() == 1)){
		my $refreshNode = $refreshNodeResult->get_node(0);
		$refreshNode->setAttribute('interval', $newRefreshInterval);
		
		YAF_saveConfiguration();
		return 1;		
	} else{
		Log 1,"YAF_setRefreshTime: no valid refresh value or refresh node was not found";
		return 0;	
	}
}

#######################################################################################
#
# YAF_saveConfiguration - Save XML configuration file
# 
# no parameter
# @return 1 if successful, otherwise 0
#
#######################################################################################

sub YAF_saveConfiguration{
	my $state = 0;
	
	if(YAF_validate() == 1){
        $prettyPrinter->pretty_print($config);
        $state = $config->toFile("$configurationFilepath");
	}
	return $state;
}

1;