########################################################################################
#
# 01_YAF.pm
#
# YAF - Yet Another Floorplan
# FHEM Projektgruppe Hochschule Karlsruhe, 2013
# Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
#
# $Id: 01_YAF.pm 2013-05 - pahenning $
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

# JSON::XS verwenden, falls nicht vorhanden auf JSON (in libraries enthalten) zurückfallen
eval "use JSON::XS;";
if ($@) {
	use FindBin;
	use lib "$FindBin::Bin/FHEM/YAF/libs/json";
	use JSON;
}

use YAF::YAFWidgets;
use YAF::YAFConfig;

use vars qw(%data);
use vars qw(%_GET);
use vars qw(%defs);
use vars qw($FW_cname);
use vars qw($FW_RET);
use vars qw($FW_dir);

sub YAF_Request($@);

my $fhem_url;
my $yaf_version=0.41;
my $yafw_encoding = "UTF-8";
my $mp   = AttrVal("global", "modpath", ".");
my $yaf_www_directory = $mp."/FHEM/YAF/www";

########################################################################################
#
# YAF_Initialize - register YAF with FHEM
#
# Parameter hash
#
########################################################################################

sub YAF_Initialize ($) {
	my ($hash) = @_;

	$hash->{DefFn} = "YAF_define";
	$hash->{AttrList} = "views backgrounds refresh_interval";

	my $name = "YAF";
	$fhem_url = "/" . $name;
	$data{FWEXT}{$fhem_url}{FUNC} = "YAF_Request";
	$data{FWEXT}{$fhem_url}{LINK} = "YAF/www/global/yaf.htm";
	$data{FWEXT}{$fhem_url}{NAME} = "YAF";

	#-- load widgets
	YAF_requireWidgets();

}

########################################################################################
#
# YAF_Print
#
# Parameter hash
#
########################################################################################

sub YAF_Print($@) {
	if ($_[0]) {
		$FW_RET .= $_[0];
	}
}

########################################################################################
#
# YAF_Clean - clear output buffer
#
# no parameter
#
########################################################################################

sub YAF_Clean() {
	$FW_RET = "";
}

########################################################################################
#
# YAF_LoadResource - Load a file from YAF directory
#
# Parameter hash
#
########################################################################################

sub YAF_LoadResource($@) {
	my $absoluteFilePath = $_[0];

	my $filebuffer = "";
	my $fh;

	# Filename
	my @absoluteFilePathSplitted = split(/\//, $absoluteFilePath);
	my $filename = $absoluteFilePathSplitted[scalar(@absoluteFilePathSplitted)-1];

	# Extension
	my @filenameSplitted = split(/\./, $filename);
	my $extension = $filenameSplitted[scalar(@filenameSplitted)-1];
	#Log 1,"YAF_LoadResource absoluteFilePath $absoluteFilePath filename $filename extension $extension";

	# Datei laden
	if ((-f $absoluteFilePath) && open($fh, "<", $absoluteFilePath)) {
		binmode $fh;
		my ($data, $n);
		while (($n = read $fh, $data, 4) != 0) {
			$filebuffer .= $data;
		}
	}
	else {
		# Datei nicht gefunden
		Log 1,"YAF_LoadResource: file $filename not found";
		return YAF_NotFound($absoluteFilePath);
	}
	close($fh);

	if ($extension eq "htm" || $extension eq "html") {
		if ($filename eq "yaf.htm") {
			# replace:
			# ###widget_css###
			# ###widget_js###
			my $widget_css = YAF_getWidgetsCss();
			my $widget_js = YAF_getWidgetsJs();
			$filebuffer =~ s/###widget_css###/$widget_css/g;
			$filebuffer =~ s/###widget_js###/$widget_js/g;
		}
		YAF_Print($filebuffer);
		return ("text/html; charset=$yafw_encoding", $FW_RET);
	}
	elsif ($extension eq "gif") {
		YAF_Print($filebuffer);
		return ("image/gif; charset=$yafw_encoding", $FW_RET);
	}
	elsif ($extension eq "jpg" || $extension eq "jpeg") {
		YAF_Print($filebuffer);
		return ("image/jpeg; charset=$yafw_encoding", $FW_RET);
	}
	elsif ($extension eq "png") {
		YAF_Print($filebuffer);
		return ("image/png; charset=$yafw_encoding", $FW_RET);
	}
	elsif ($extension eq "css") {
		YAF_Print($filebuffer);
		return ("text/css; charset=$yafw_encoding", $FW_RET);
	}
	elsif ($extension eq "js") {
		YAF_Print($filebuffer);
		return ("text/javascript; charset=$yafw_encoding", $FW_RET);
	}
	else {
		YAF_Print($filebuffer);
		return ("text/plain; charset=$yafw_encoding", $FW_RET);
	}
}

########################################################################################
#
# YAF_define
#
# Parameter hash
#
########################################################################################

sub YAF_define ($@) {
	my ($hash, $def) = @_;
	return;
}

########################################################################################
#
# YAF_LoadView
#
# Parameter hash
#
########################################################################################

sub YAF_LoadView($@) {
	my ($view) = @_;
	YAF_Print("ddd");
	return ("text/html; charset=$yafw_encoding", $FW_RET);
}

########################################################################################
#
# YAF_Request - http://fhemurl:fhemport/YAF is processed here
#
# Parameter hash, request-string
#
########################################################################################

sub YAF_Request ($@) {
	my ($htmlarg) = @_;
	# %20 durch Leerzeichen ersetzen
	$htmlarg =~ s/%20/ /g;

	# GET Parameter
	my @params = split(/\?/, $htmlarg);

	if (scalar(@params) > 1) {
		my @attributesArray = split("&",$params[1]);
		my @attributePair;
		for (my $i = 0; $i < scalar(@attributesArray); $i++) {
			@attributePair = split("=",$attributesArray[$i]);
			$_GET{$attributePair[0]} = $attributePair[1];
		}
	}

	@params = split(/\//, $params[0]);

	#-- clean output buffer
	YAF_Clean();

	#-- take URI apart
	my $controler_count = scalar(@params);
    #Log 1,"YAF_Request: arguments $htmlarg params ".join(' ',@params);

	#-- examples are
	#/YAF/global/yaf.htm
	#/YAF/global/js/yaf-dialogs.js
	#/YAF/ajax/global/getRefreshTime

	my $control_1 = $params[1];
	my $control_2 = $params[2];
	my $control_3 = $params[3];

	if ($controler_count > 3) {
	    #-- either global, widget or ajax
   	    if ($control_2 eq "global") {
			my $request_file = $yaf_www_directory;
			my $pos = 3;
			for (; $pos < scalar(@params); $pos++) {
				$request_file .= "/";
				$request_file .= $params[$pos];
			}
			# Resource aus dem global www Verzeichnis laden
			return YAF_LoadResource($request_file);
		}
		elsif ($control_2 eq "widget") {
			return ("text/plain; charset=$yafw_encoding", $FW_RET);
		}
		elsif ($control_2 eq "ajax") {
			if ($control_3 eq "global") {
				if ($controler_count > 4) {
					my $function = "";
					$function = $params[4];
					if ($function eq "getViews") {
						YAF_FHEMConfig();
						my $views = encode_json(YAF_getViews());
						YAF_Print($views);
					}
					#-- adds a View
					elsif ($function eq "addView") {
						if ($_GET{"name"} && (YAF_addView($_GET{"name"}) == 1)) {
							YAF_Print("1");
						}
						else {
							YAF_Print("0");
						}
					}
					#-- deletes a View
					elsif ($function eq "deleteView") {
						if ($_GET{"id"} && (YAF_deleteView($_GET{"id"}) == 1)) {
							YAF_Print("1");
						}
						else {
							YAF_Print("0");
						}
					}
					#-- returns all Widgets of a View
					elsif ($function eq "getView") {
						if ($_GET{"id"}) {
							YAF_Print(encode_json(YAF_getView($_GET{"id"})));
						}
						else {
							YAF_Print("0");
						}
					}
					#-- changes the name of a View
					elsif ($function eq "editView") {
						if ($_GET{"id"} && $_GET{"name"}) {
							YAF_Print(YAF_editView($_GET{"id"}, $_GET{"name"}, $_GET{"image"}));
						}
						else {
							YAF_Print("0");
						}
					}
					#-- modify position of a Widget
					elsif ($function eq "setWidgetPosition") {
						if ($_GET{"view_id"} && $_GET{"widget_id"} && $_GET{"x_pos"} && $_GET{"y_pos"}) {
							YAF_setWidgetPosition($_GET{"view_id"}, $_GET{"widget_id"}, $_GET{"x_pos"}, $_GET{"y_pos"});
							YAF_Print("1");
						}
						else {
							YAF_Print("0");
						}
					}
					#-- get Widgets
					elsif ($function eq "getWidgets") {
						my @widgets = YAF_getWidgetArray();
						YAF_Print(encode_json(\@widgets));
					}
					#-- add Widget
					elsif ($function eq "addWidget") {
						if ($_GET{"view_id"} && $_GET{"widget"} && $_GET{"attributes"}) {
							# %22 wieder durch " ersetzen!
							# @TODO Probleme mit Sonderzeichen müssen noch behoben werden!
							$_GET{"attributes"} =~ s/%22/"/g;
							my @attributes_array = @{decode_json($_GET{"attributes"})};
							my $widgetId = YAF_addWidget($_GET{"view_id"},$_GET{"widget"}, 28, 69, \@attributes_array);
							YAF_Print($widgetId);
						}
						else {
							YAF_Print("0");
						}
					}
					#-- delete Widget
					elsif($function eq "deleteWidget"){
						if ($_GET{"view_id"} && $_GET{"widget_id"} && (YAF_deleteWidget($_GET{"view_id"}, $_GET{"widget_id"}) == 1)) {
							YAF_Print("1");
						}
						else {
							YAF_Print("0");
						}
					}
					#-- edit Widget // more or less: set widget attributes
					elsif($function eq "editWidget"){
						if ($_GET{"view_id"} && $_GET{"widget_id"} && $_GET{"keys"} && $_GET{"vals"}) {
							my $viewid = $_GET{"view_id"};
							my $widgetid = $_GET{"widget_id"};
							my @keys = split(/,/,$_GET{"keys"});
							my @vals = split(/,/,$_GET{"vals"});
							for my $i (0 .. $#keys) {
								YAF_setWidgetAttribute($viewid,$widgetid,$keys[$i],$vals[$i]);
							}
							YAF_Print("1");
						}
						else {
							YAF_Print("0");
						}
					}
					#-- get RefreshTime
					elsif($function eq "getRefreshTime"){
						my $refreshTime = YAF_getRefreshTime();
						YAF_Print($refreshTime);
					}
					#-- set RefreshTime
					elsif($function eq "setRefreshTime"){
						if($_GET{"interval"}){
							my $newRefreshTime = $_GET{"interval"};
							YAF_setRefreshTime($newRefreshTime);
							YAF_Print($newRefreshTime);
						} else{
							YAF_Print("0");
						}
					}
					#-- save config
					elsif($function eq "saveconfig"){
						fhem("save");
						Log 3, "Saved running config";
						YAF_Print("1");
					}
					else {
						YAF_Print("0");
					}
				}
				else {
					YAF_Print("1");
				}
				return ("text/plain; charset=$yafw_encoding", $FW_RET);
			}
			#-- evaluation of a widget function
			elsif ($control_3 eq "widget") {
				my $widget   = $params[4];
				my $function = $params[5];
				if ($widget ne "") {
					YAF_Print(eval($widget."_".$function."();")) or YAF_Print("0");
				}
				else {
					YAF_Print("0");
				}
				#Log 1,"++++++++++++> Widget $widget called with function $function, length of return was ".length($FW_RET);
				return ("text/plain; charset=$yafw_encoding", $FW_RET);
			}
			else {
                Log 1,"YAF_Request: B response not found $control_1 $control_2";
				return YAF_NotFound($htmlarg);
			}
		}
		else {
            Log 1,"YAF_Request: C response not found $control_1 $control_2";
			return YAF_NotFound($htmlarg);
		}
	}
	else {
        Log 1,"YAF_Request: D response not found $control_1 $control_2";
		return YAF_NotFound($htmlarg);
	}
}

########################################################################################
#
# YAF_NotFound - Return a 404 Error
#
# Parameter hash, request-string
#
########################################################################################

sub YAF_NotFound{
		my $file = $_[0];
		YAF_Print("Error 404: $file");
		YAF_Print("\n");
		return ("text/html; charset=$yafw_encoding", $FW_RET);
}

1;
