################################################################################
# 95 FLOORPLAN
# Feedback: http://groups.google.com/group/fhem-users
# Define Custom Floorplans
# Released : 26.02.2012
# Version  : 1.01
# Revisions:
# 0001: Released
# 0002: use local FP_select and FP_submit after clash with FHEMWEB update
# 0003: FP_arrange_default repaired
# 0004: WebApp-enabled links in floorplanlist, fixed message 'use of uninitialized value' (FW_pO - $FP_name)
# 0005: Change arrange-mode: When selected, display device-name instead of selection
# 0006: kicked out various routines previously copied from FHEMWEB - now using FW_*-versions thanks to addtl. global variables $FW_RET, $FW_wname, $FW_subdir, %FW_pos
# 0007: Added fp_default
# 0008: Changed name of background-picture from <floorplan-name> to fp_<floorplan-name> to avoid display of picture in device-list at fhem-menu 'Everything'
# 0009: updated selection of add-device-list: suppress CUL$ only (instead of CUL.*)
# 0010: Added Style3, fp_stylesheetPrefix, fp_noMenu (Mar 13, 2012)
#
################################################################
#
#  Copyright notice
#
#  (c) 2012 Copyright: Ulrich Maass
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################################
# Usage
# define <NAME> FLOORPLAN
#
# Step-by-Step HowTo - mind all is case sensitive:
# Step 1:
# define <name> FLOORPLAN
# Example: define Groundfloor FLOORPLAN
#
# Step 2:
# store picture fp_<name>.png in your modpath. This will be used as background-picture.
# Example: fhem/FHEM/Groundfloor.png
#
# Step 3:
# Activate 'Arrange-Mode' to have user-friendly fields to move items: 
# attr <floorplanname> fp_arrange 1
# Delete this attribute when you're done with setup
# To make objects display, they will thereby get assigned
# attr <device> fp_<name> <top>,<left>,<style>,<text>
# displays device <device> on floorplan <name> at position top:<top>,left:<left> with style <style> and description <text>
# styles: 0: icon/state only, 1: name+icon, 2: name+icon+commands
# Example: attr lamp fp_Groundfloor 100,100,1,TableLamp #displays lamp at position 100px,100px
#
# Repeat step 3 to add further devices. Delete attr fp_<name> when all devices are arranged on your screen. Enjoy.
#
################################################################################

package main;
use strict;
use warnings;
#use Data::Dumper;
use vars qw(%data);

#########################
# Forward declaration
sub FLOORPLAN_Initialize($);     # Initialize
sub FP_define();                 # define <name> FLOORPLAN
sub FP_CGI();                    # analyze URL
sub FP_digestCgi($);             # digest CGI
sub FP_htmlHeader($);            # html page - header
sub FP_menu();                   # html page - menu left - floorplan-list
sub FP_menuArrange();            # html page - menu bottom - arrange-mode
sub FP_showstart();              # html page - startscreen
sub FP_show();                   # produce floorplan
sub FP_input(@);                 # prepare selection list for forms

##
#  $ret_html;                    # Returned data (html)
my $FP_name;                     # current floorplan-name
my $FP_arrange;                  # arrange-mode
my $FP_arrange_selected;	     # device selected to be arranged
my $FP_arrange_default;          # device selected in previous round
my $FP_ll;                       # Loglevel
my %FP_webArgs = ();             # sections of analyzed URL
#  $FW_encoding                  # from FHEMWEB: html-encoding
my $FW_encoding="UTF-8";
#  $FW_ME                        # from FHEMWEB: fhem URL
#  $FW_tp                        # from FHEMWEB: is touchpad
#  $FW_ss                        # from FHEMWEB: is smallscreen
my $FW_longpoll=0;               # from FHEMWEB
#  $FW_wname;                    # from FHEMWEB: name of web-instance
#  %FW_pos=();                   # from FHEMWEB: scroll position
my $FW_plotmode="";              # from FHEMWEB:
my $FW_plotsize;				 # from FHEMWEB:
my $FW_detail;                   # from FHEMWEB:
my %FW_zoom;                     # from FHEMWEB:
my @FW_zoom;                     # from FHEMWEB:

#-------------------------------------------------------------------------------
sub 
FLOORPLAN_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn} = "FP_define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 refresh fp_arrange commandfield fp_default fp_stylesheetPrefix fp_noMenu";
  # fp_arrange: show addtl. menu for  attr fp_<name> ....
  # commandfield: shows an fhem-commandline inputfield on floorplan
  
  # CGI
  my $name = "floorplan";
  my $fhem_url = "/" . $name ;
  $data{FWEXT}{$fhem_url}{FUNC} = "FP_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = "Floorplans";
#  $data{FWEXT}{$fhem_url}{EMBEDDED} = 1;             # not using embedded-mode to save space
  $data{FWEXT}{$fhem_url}{STYLESHEET} = "floorplanstyle.css";
  # Global-Config for CSS
  $attr{global}{VIEW_CSS} = "";
  $modules{_internal_}{AttrList} .= " VIEW_CSS";
  my $n = 0;
  @FW_zoom = ("qday", "day","week","month","year");    #copied from FHEMWEB - using local version to avoid global variable
  %FW_zoom = map { $_, $n++ } @FW_zoom;                #copied from FHEMWEB - using local version to avoid global variable
  return undef;
}
#-------------------------------------------------------------------------------
##################
# method 'define'
sub 
FP_define(){
  my ($hash, $def) = @_;
  $hash->{STATE} = $hash->{NAME};
  return undef;
  }
#-------------------------------------------------------------------------------
##################
# FP MAIN: Answer URL call
sub 
FP_CGI(){
  my ($htmlarg) = @_;         #URL

  ## reset parameters
  $FP_name = undef;
  $FP_ll = 4;                 #default loglevel
  my ($p,$v) = ("","");       #parameter and value of analyzed URL
  $FW_RET = "";               #returned html-code
  $FW_longpoll = (AttrVal($FW_wname, "longpoll", undef));
  $FW_detail = 0;
  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");  
  $FW_subdir = "";
  $htmlarg =~ s/^\///;
  # URL: http(s)://IP:port/fhem/floorplan
  my @params = split(/\//,$htmlarg);    # split URL by /
  #  possible parameters:     [0]:floorplan, [1]:FP_fp?command(s)
  #  Log $FP_ll, "95_FLOORPLAN - params[0] : $params[0]; 95_FLOORPLAN - params[1] : $params[1]";

  # URL with CGI-parameters has addtl /
  if ($params[2]) {
    $FP_name = $params[1];
    $params[1] = $params[2];
  }
  
  my @htmlpart = ();
  @htmlpart = split("\\?", $params[1]) if ($params[1]);  #split URL by ? 
  #  htmlpart[0] = FP_name, htmlpart[1] = commandstring
  
  ### set global parameters, check florplan-name
  $FP_name = $htmlpart[0] if (!$FP_name);
  
  if ($FP_name) {
	addToAttrList("fp_$FP_name");                                                  # create userattr fp_<name> if it doesn't exist yet
	$FP_arrange = AttrVal($FP_name, "fp_arrange", 0) if ($FP_name);
	#Log 1, "95_FLOORPLAN: FP_arrange ist $FP_arrange";	                           #testmode
	if(!defined($defs{$FP_name})){
		$FW_RET = "ERROR: Floorplan $FP_name not defined \n";
		return ("text/plain; charset=$FW_encoding", $FW_RET);
	}
	$FW_subdir = "/floorplan/$FP_name";
  } else {
    $FW_subdir = "/floorplan";
	my $dev = undef;
	my @devs = devspec2array("*");
	foreach my $fp (@devs) {
	   if (AttrVal($fp, "fp_default", undef)) {
			$FP_name = $fp;
			$FW_subdir = "/floorplan/$fp";
	   }
	}
  }  
#  Log $FP_ll, "95_FLOORPLAN - FP_name     = $FP_name";                            #testmode
#  Log $FP_ll, "95_FLOORPLAN - htmlpart[1] = $htmlpart[1]" if $htmlpart[1];        #testmode
 
  my $commands = FP_digestCgi($htmlpart[1]) if $htmlpart[1];                       # analyze URL-commands
  #Log $FP_ll, "95_floorplan: commands after FP_digestCgi = $commands";

  my $FP_ret = AnalyzeCommand(undef, $commands) if $commands;                      # Execute commands
#  Log $FP_ll, "95_floorplan: return of AnalyzeCommand = $FP_ret" if ($FP_ret && $FP_ret ne "");

  ######################################
  ### output html-pages  
  if($FP_name) {
    FP_show();         # show floorplan
  }
  else {
    FP_showStart();    # show startscreen
  }

  # finish HTML
  FW_pO "</html>\n";
  $FW_subdir = "";
  return ("text/html; charset=$FW_encoding", $FW_RET); # $FW_RET composed by FW_pO, FP_pH etc
}
#-------------------------------------------------------------------------------
###########################
# Digest CGI parameters - portion after '?' in URL
sub
FP_digestCgi($) {
  my ($arg) = @_;
  my (%arg, %val, %dev, %deva, %attr, %top, %left, %style, %text);
  my ($cmd, $c) = ("","","");
  %FW_pos = ();
#  Log 1, "95_floorplan: FW_digestCgi started with: $arg";              #testmode
  %FP_webArgs = ();
  $arg =~ s,^[?/],,;
  foreach my $pv (split("&", $arg)) {                                   #per each URL-section devided by &
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);                                     #$p = parameter, $v = value
#    Log 1, "95_floorplan: p is : $p ; v is $v";                        #testmode
    # Multiline: escape the NL for fhem
    $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
    $FP_webArgs{$p} = $v;

    if($p eq "arr.dev")        { $FP_arrange_selected = $v; $FP_arrange_default = $v; }
    if($p eq "add.dev")        { $cmd = "attr $v fp_$FP_name 50,100"; }
    if($p eq "cmd")            { $cmd = $v; }
    if($p =~ m/^cmd\.(.*)$/)   { $cmd = $v; $c = $1; }
    if($p =~ m/^dev\.(.*)$/)   { $dev{$1} = $v; }
    if($p =~ m/^arg\.(.*)$/)   { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/)   { $val{$1} = $v; }
    if($p =~ m/^deva\.(.*)$/)  { $deva{$1} = $v; $FP_arrange_selected = undef;}
    if($p =~ m/^attr\.(.*)$/)  { $attr{$1} = $v; }
    if($p =~ m/^top\.(.*)$/)   { $top{$1} = $v; }
    if($p =~ m/^left\.(.*)$/)  { $left{$1} = $v; }
    if($p =~ m/^style\.(.*)$/) { $style{$1} = $v; }
    if($p =~ m/^text\.(.*)$/)  { $text{$1} = $v; }
	if($p eq "pos")            { %FW_pos =  split(/[=;]/, $v); }
  }
  $cmd.=" $dev{$c}"   if(defined($dev{$c}));     #FHT device
  $cmd.=" $arg{$c}"   if(defined($arg{$c}));     #FHT argument (e.g. desired-temp)
  $cmd.=" $val{$c}"   if(defined($val{$c}));     #FHT value
  $cmd.=" $deva{$c}"  if(defined($deva{$c}));    #arrange device
  $cmd.=" $attr{$c}"  if(defined($attr{$c}));    #arrange attr
  $cmd.=" $top{$c}"   if(defined($top{$c}));     #arrange top
  $cmd.=",$left{$c}"  if(defined($left{$c}));    #arrange left
  $cmd.=",$style{$c}" if(defined($style{$c}));   #arrange style
  $cmd.=",$text{$c}"  if(defined($text{$c}));    #arrange text
#  Log 1, "95_floorplan: FW_digestCgi returns: $cmd";              #testmode
  return $cmd;
}
#-------------------------------------------------------------------------------
##################
# Page header, set webapp & css
sub 
FP_htmlHeader($) {
  my $title = shift;
  $title = "FHEM floorplan" if (!$title);
  ### Page start
  $FW_RET = "";
  $FW_RET .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'."\n";
  $FW_RET .= '<html xmlns="http://www.w3.org/1999/xhtml">'."\n";
  FW_pO  "<head>";
  FW_pO  "<title>".$title."</title>";
  # Enable WebApp
  if($FW_tp || $FW_ss) { 
    FW_pO "<link rel=\"apple-touch-icon-precomposed\" href=\"$FW_ME/fhemicon.png\"/>";
    FW_pO "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\"/>";
    if($FW_ss) {
      FW_pO "<meta name=\"viewport\" content=\"width=320\"/>";
    } elsif($FW_tp) {
      FW_pO "<meta name=\"viewport\" content=\"width=768\"/>";
    }
  }
 
  my $rf = AttrVal($FW_wname, "refresh", "");
  FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  # Select CSS-Style-Sheet: use floorplanstyle if not indicated differently by attr VIEW_CSS
  my $css = $attr{global}{VIEW_CSS};
  if($css){
	FW_pO  "<link href=\"$FW_ME/$css\" rel=\"stylesheet\"/>";                   #always use $css if set as attribute
  } elsif ($FP_name) {
    my $prf = AttrVal($FP_name, "fp_stylesheetPrefix", "");
  	FW_pO  ("<link href=\"$FW_ME/$prf"."floorplanstyle.css\" rel=\"stylesheet\"/>"); #use floorplanstyle.css for floorplans, evtl. with fp_stylesheetPrefix
  } else {
    FW_pO  "<link href=\"$FW_ME/style.css\" rel=\"stylesheet\"/>";              #use style.css for fp-start-screen
  }
  #set sripts
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/svg.js\"></script>"
                        if($FW_plotmode eq "SVG");
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/longpoll.js\"></script>"
                        if($FW_longpoll);
  FW_pO "</head>\n";
}
#-------------------------------------------------------------------------------
##################
# show startscreen
sub 
FP_showStart() {
  FP_htmlHeader("Floorplans");
  FW_pO "<body>";  
  FW_pO "<div id=\"logo\"></div>";
  FW_pO "<div class=\"screen\" id=\"hdr\">";
  FW_pO "<form method=\"get\" action=\"" . $FW_ME . "\">";
  FW_pO "<table WIDTH=\"100%\"><tr>";
  FW_pO "<td><input type=\"text\" name=\"cmd\" size=\"30\"/></td>";   #input-field
  FW_pO "</tr></table>";
  FP_menu();
  # add edit floorplanstyle.css if FP_arrange ?
  FW_pO "</form></div>";
  FW_pO "</body>";
}
#-------------------------------------------------------------------------------
##################
# show floorplan
sub 
FP_show(){
  ### Page start
  FP_htmlHeader("$FP_name");
 
  ## body
  FW_pO "<body>\n";
  FW_pO "<img src=\"$FW_ME/fp_$FP_name.png\">\n";            # alternative: jpg - how?

  ## menus
  FP_menu();
  FP_menuArrange() if ($FP_arrange);


  # (re-) list the icons
  FW_ReadIcons();

  ## start floorplan  
  FW_pO "<div class=\"screen\" id=\"floorplan\">";
  FW_pO "<div id=\"logo\"></div>";

  #commandfield in floorplan  
  if (AttrVal("$FP_name", "commandfield", undef)) {
       FW_pO "<div id=\"hdr\">\n";
       FW_pO " <form>";
       FW_pO "  <input type=\"text\" name=\"cmd\" size=\"30\"/>\n";   #fhem-commandfield
       FW_pO " </form>";
       FW_pO "</div>\n";
   }
    
  my @devs = devspec2array("*");
	foreach my $d (@devs) {                                                                    # loop all devices
		my $type = $defs{$d}{TYPE};
		my $attr = AttrVal("$d","fp_$FP_name", undef);
		next if(!$attr || $type eq "weblink");                                                 # skip if device-attribute not set for current floorplan-name
		
		my ($top, $left, $style, $text, $text2) = split(/,/ , $attr);
		# $top   = position in px, top
		# $left  = position in px, left
		# $style = style (0=icon only, 1=name+icon, 2=name+icon+commands, 3=name from $text2+reading))
		# $text  = alternativeCaption
		$left = 0 if (!$left);
		$style = 0 if (!$style);
		FW_pO "\n<div style=\"position:absolute; top:".$top."px; left:".$left."px\">";
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name/$d\">";
		FW_pO " <table class=\"$type fp_$FP_name\" id=\"$d\" align=\"center\">";               # Main table per device
		my ($allSets, $cmdlist, $txt) = FW_devState($d, "");
		$txt = ReadingsVal($d, $text, "Undefined Reading $d-<b>$text</b>") if ($style == 3);		   # Style3 = DeviceReading given in $text
		my $cols = ($cmdlist ? (split(":", $cmdlist)) : 0);                                    # Need command-count for colspan of devicename+state
		
    ########################
    # Device-name per device
		if ($style gt 0) {
			FW_pO "   <tr class=\"devicename fp_$FP_name\" id=\"$d\">";                        # For css: class=devicename, id=devicename
			my $devName = "";
			if ($style == 3) {
				$devName = $text2;														   # Style 3 = Reading - use last part of comma-separated description
				} else {
				$devName = ($text ? $text : AttrVal($d, "alias", $d));
			}
			FW_pO "<td colspan=\"$cols\">";
			FW_pO "$devName" ;
			FW_pO "</td></tr>";
		}

    ########################
    # Device-state per device
		FW_pO "</tr><tr class=\"devicestate fp_$FP_name\" id=\"$d\">";                         # For css: class=devicestate, id=devicename
		FW_pO "<td colspan=\"$cols\">$txt";
		FW_pO "</td></tr>";

    ########################
    # Commands per device		  
		if($style == 2 && $cols gt 0) {
    	  FW_pO "  <tr class=\"devicecommands\" id=\"$d\">";                                   # For css: class=devicecommands, id=devicename
		  foreach my $cmd (split(":", $cmdlist)) {
			FW_pH "cmd.$d=set $d $cmd",  ReplaceEventMap($d,$cmd,1), 1, "devicecommands"; 
		  }
          FW_pO "  </tr>";
		} elsif($type eq "FileLog") {
#		  Log $FP_ll, "FileLogs cannot be displayed on floorplans.";
		# devices with desired-temp-reading, e.g. FHT
		} elsif($style == 2 && $allSets =~ m/ desired-temp /) {                                # FHT-set
    	  FW_pO "  <tr class=\"devicecommands\" id=\"$d\">";
          $txt = ReadingsVal($d, "measured-temp", "");
          $txt =~ s/ .*//;
          $txt = sprintf("%2.1f", int(2*$txt)/2) if($txt =~ m/[0-9.-]/);
          my @tv = split(" ", getAllSets("$d desired-temp"));
          $txt = int($txt*20)/$txt if($txt =~ m/^[0-9].$/);
          FW_pO "<td>".
             FP_input("dev.$d", $d, "hidden") .
             FP_input("arg.$d", "desired-temp", "hidden") .
             FW_select("val.$d", \@tv, ReadingsVal($d, "desired-temp", $txt),"devicecommands") .
             FW_submit("cmd.$d", "set").
             "</td></tr>";
        } 
	  FW_pO "\n";
	  FW_pO "</table></div>\n";
	  FW_pO "</form>";
	}
   
 	########################  
	# Now the weblinks
	my $buttons = 1;
	my @list = (keys %defs);

	foreach my $d (sort @list) {
	    my $attr = AttrVal("$d","fp_$FP_name", undef);
		next if(IsIgnored($d) || !$attr);
		my $type = $defs{$d}{TYPE};
		next if(!$type);
        next if($type ne "weblink");
		# set position per weblink
		my ($top, $left, $style, $text) = split(/,/ , AttrVal("$d", "fp_$FP_name", undef));
		FW_pO "\n<div style=\"position:absolute; top:".$top."px; left:".$left."px\" class = \"fp_$type fp_$FP_name\" id = \"$d\">";
		# print weblink
		$buttons = FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, $buttons);
		FW_pO "</div>";
	}
	FW_pO "</div>";
	FW_pO "</body>\n";
}
#-------------------------------------------------------------------------------
##################
# Floorplan menu left
sub
FP_menu() {
    return if ($FP_name && AttrVal($FP_name, "fp_noMenu", 0));                       # fp_noMenu suppresses the menu
	FW_pO "<div class=\"floorplan\" id=\"menu\">";
  # List FPs
	FW_pO "<table class=\"start\" id=\"floorplans\">";
	FW_pO "<tr>";
	FW_pH "$FW_ME", "fhem", 1;
	FW_pO "</tr>";
	foreach my $f (sort keys %defs) {
		next if ($defs{$f}{TYPE} ne "FLOORPLAN");
    	FW_pO "<tr>";
		FW_pH "$FW_ME/floorplan/$f", $f, 1;
    	FW_pO "</tr>";
	}
	FW_pO "</table><br>";
	FW_pO "</div>\n";
}
#-------------------------------------------------------------------------------
##################
# Arrange-menu
sub
FP_menuArrange() {
	# collect data
	$FP_arrange_default  = "" if (!$FP_arrange_default);
	#		Log 1, "Arrange-selected    : $FP_arrange_selected";   
	#		Log 1, "Arrange-default     : $FP_arrange_default";
	my @fpl;
	my @nfpl;
	my @devs = devspec2array("*");
	foreach my $d (@devs) {                                                                    # loop all devices
		my $type = $defs{$d}{TYPE};
		# exclude these types from list of available devices
		next if($type =~ m/(WEB|CUL$|FHEM.*|FileLog|PachLog|PID|SUNRISE.*|FLOORPLAN|holiday|Global|notify)/ );
		my $av = AttrVal("$d","fp_$FP_name", undef);
		push(@fpl, $d)  if ($av);
		push(@nfpl, $d) if (!$av);
	}
	my $attrd = "";
	my $d = $FP_arrange_selected;
	$attrd = AttrVal($d, "fp_$FP_name", undef) if ($d);
	FW_pO "<div class=\"fp_arrange\" id=\"fpmenu\">\n";

	# add device to floorplan
	if (!defined($FP_arrange_selected)) {
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form1
		FW_pO "<div class=\"menu-add\" id=\"fpmenu\">\n" .                                       
		FW_select("add.dev", \@nfpl, "", "menu-add") .
		FW_submit("ccc.one", "add");
		FW_pO "</div></form>\n"; #form1
	}

	# select device to be arranged
	if (!defined($FP_arrange_selected)) {
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form2
		FW_pO "<div class=\"menu-select\" id=\"fpmenu\">\n" .                                       
		FW_select("arr.dev", \@fpl, $FP_arrange_default, "menu-select") .
		FW_submit("ccc.one", "select");
		FW_pO "</div></form>"; #form2
	}

	# fields for top,left,style,text
	if ($attrd) {
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form3
		my ($top, $left, $style, $text, $text2) = split(",", $attrd);
		$text .= ','.$text2 if ($text2);														# re-append Description after reading-ID for style3
		my @styles = ("0","1","2","3");
		FW_pO "<div class=\"menu-arrange\" id=\"fpmenu\">\n" .
			FP_input("deva.$d", $d, "hidden") . "\n" .
			FP_input("dscr.$d", $d, "text", "Selected device", 45, "", "disabled") . "\n<br>\n" .
			FP_input("attr.$d", "fp_$FP_name", "hidden") . "\n" .
			FP_input("top.$d", $top ? $top : 10, "text", "Top", 4, 4 ) . "\n" .
			FP_input("left.$d", $left ? $left : 10, "text", "Left", 4, 4 ) . "\n" .
			FW_select("style.$d", \@styles, $style ? $style : 0, "menu-arrange") . "\n" .
			FP_input("text.$d", $text ? $text : "", "text", "Description", 15) . "\n" .
			FW_submit("cmd.$d", "attr") ;
		FW_pO "</div></form>"; # form3
	}
	FW_pO "</div>";
}
#-------------------------------------------------------------------------------
##################
# input-fields for html-forms
sub
FP_input(@)
{
	my ($n, $v, $type, $title, $size, $maxlength, $addition) = @_;
	$title =      "" if(!defined($title));
	$title  =     " title=\"$title\"" if($title);
	$size =      "" if(!defined($size));
	$size  =     " size=\"$size\"" if($size);
	$maxlength = "" if(!defined($maxlength));
	$maxlength = " maxlength=\"$maxlength\"" if($maxlength);
	$addition = "" if (!defined($addition));
	return "<input type=\"$type\"$title$size$maxlength $addition name=\"$n\" value=\"$v\"/>\n";
}
1;
