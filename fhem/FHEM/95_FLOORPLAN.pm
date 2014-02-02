################################################################################
# 95 FLOORPLAN
# $Id$
# Feedback: http://groups.google.com/group/fhem-users
# Define Custom Floorplans
# Released : 26.02.2012
# Version  : 2.0
# Revisions:
# 0001: Released to testers
# 0002: use local FP_select and FP_submit after clash with FHEMWEB update
# 0003: FP_arrange_default repaired
# 0004: WebApp-enabled links in floorplanlist, fixed message 'use of uninitialized value' (FW_pO - $FP_name)
# 0005: Change arrange-mode: When selected, display device-name instead of selection
# 0006: kicked out various routines previously copied from FHEMWEB - now using FW_*-versions thanks to addtl. global variables $FW_RET, $FW_wname, $FW_subdir, %FW_pos
# 0007: Added fp_default
# 0008: Changed name of background-picture from <floorplan-name> to fp_<floorplan-name> to avoid display of picture in device-list at fhem-menu 'Everything'
#       -> general release
# 0009: updated selection of add-device-list: suppress CUL$ only (instead of CUL.*)
# 0010: Added Style3, fp_stylesheetPrefix, fp_noMenu (Mar 13, 2012)
# 0011: Added Style4, code beautification, css review, minor $text2-fix (SVN 1342)
# 0012: Added startscreen-text when no floorplans defined, fixed startscreen-stylesheet, added div for bg-img, added arrangeByMouse (1368)
# 0013: implemented redirectCmd, fixed minor </td></tr>-error in html-output, fp_arrange for single web-devices, fp_arrange detail (Mar 23, 2012)
# 0014: deleted $data{FWEXT}{$fhem_url}{STYLESHEET} , added attr-values for FHEMWEB-detail-screen, adapted FHT-representation to FHT.pm updates (Apr 19, 2012)
# 0015: implemented Tobias' icon subfolder solution, fp_arrange detail always (fp_arrange detail deprecated, fp_arrange 1 shows all detail),
#       changed backimg-size to 99% to avoid scrollbars , adopted slider & new FHT representation (May 1, 2012)
# 0016: Minor repair of html-output, allowed devices with dot in name (May 2, 2012)
# 0017: updating for changes in fhemweb: css-path, bgimg-path, deactivating rereadicons (July 30, 2012)
# 0018: Changes by Boris (icon-paths, fp_stylesheetPrefix -> stylesheet
# 0019: added fp_backgroundimg (October 15, 2012)
# 0020: moved creation of userattr to define, added slider and timepicker and setList, added style5 icon+commands, added style 6 readingstimestamp, 
#       added style-descriptions in fp-arrange (October 22, 2012)
# 0021: fixed http-header, unsetting FF-autocomplete, added attribute fp_setbutton (fixes by Matthias) (November 23, 2012)
# 0022: longpoll by Matthias Gehre (November 27, 2012)
# 0023: longpoll updates readings also - by Matthias Gehre; FW_longpoll is now a global variable (January 21, 2013)
# 0024: fix for readings longpoll, added js-extension from Dirk (February 16, 2013)
# 0025: Added fp_viewport-attribute from Jens (March 03, 2013)
# 0026: Adapted to FHEMWEB-changes re webCmdFn - fp_setbutton not functional (May 23, 2013)
# 0027: Added FP_detailFn(), added delete-button in arrange-menu, fixed link for pdf-docu, minor code cleanup, added get config (July 08, 2013)
# 0028: Implemented informid for longpoll, usage of @FW_fhemwebjs (July 19, 2013)
# 0029: Fixed floorplan-specific icons and eliminated FHT-text "desired-temp" - both due to changes in fhemweb (Sep 29, 2013)
# 0030: Style4 (S300TH) now works with longpoll without loosing its formatting (Dec 24, 2013)
# 0031: Text "desiredTemperature" will also be eliminated - for MAX devices (Dec 25, 2013)
# 0032: Ensure URL always contains floorplan-name (redirect if !htmlarg[0]) as basis for fp-specific icon-folder (Jan 06, 2014)
# 0033: Updated loglevel -> verbose, added fp_roomIcons (Feb 2, 2014)
#
################################################################
#
#  Copyright notice
#
#  (c) 2012-2013 Copyright: Ulrich Maass
#
#  This file is part of fhem.
# 
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
# 
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
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
# Example: fhem/www/images/default/Groundfloor.png
#
# Step 3:
# Activate 'Arrange-Mode' to have user-friendly fields to move items: 
# attr <floorplanname> fp_arrange 1
# Delete this attribute when you're done with setup
# To make objects display, they will thereby get assigned
# attr <device> fp_<name> <top>,<left>,<style>,<text>
# displays <device> on floorplan <name> at position top:<top>,left:<left> with style <style> and description <text>
# styles: 0: icon/state only, 1: name+icon, 2: name+icon+commands 3:Device-Readings(+name) 4:S300TH
# Example: attr lamp fp_Groundfloor 100,100,1,TableLamp #displays lamp at position 100px,100px
#
# Repeat step 3 to add further devices. Delete attr fp_<name> when all devices are arranged on your screen. Enjoy.
#
# Check the colorful pdf-docu in http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/fhem-floorplan-installation-guide.pdf
#
################################################################################

package main;
use strict;
use warnings;
use vars qw(%data);
use vars qw($FW_longpoll);
use vars qw(@FW_fhemwebjs);      # List of fhemweb*js scripts to load - from FHEMWEB

#########################
# Forward declaration
sub FLOORPLAN_Initialize($);     # Initialize
sub FP_define();                 # define <name> FLOORPLAN
sub FP_Get($@);                  # get-command
sub FP_CGI();                    # analyze URL
sub FP_digestCgi($);             # digest CGI
sub FP_htmlHeader($);            # html page - header
sub FP_menu();                   # html page - menu left - floorplan-list
sub FP_menuArrange();            # html page - menu bottom - arrange-mode
sub FP_showstart();              # html page - startscreen
sub FP_show();                   # produce floorplan
sub FP_input(@);                 # prepare selection list for forms
sub FP_detailFn($$$$);           # floorplan-specific detail-screen in fhemweb
sub FP_getConfig($);             # display floorplan configuration
sub FP_pOfill($@);               # print line filled up with hash-signs

#########################
# Global variables
#  $ret_html;                    # from FHEMWEB: Returned data (html)
my $FP_name;                     # current floorplan-name
my $FP_arrange;                  # arrange-mode
my $FP_arrange_selected;	     # device selected to be arranged
my $FP_arrange_default;          # device selected in previous round
my %FP_webArgs = ();             # sections of analyzed URL
my $FP_fwdetail;                 # set when floorplan is called from fhemweb-detailscreen
my $FP_viewport;                 # Define width for touchpad device
#  $FW_ME                        # from FHEMWEB: fhem URL
#  $FW_tp                        # from FHEMWEB: is touchpad
#  $FW_ss                        # from FHEMWEB: is smallscreen
#  $FW_longpoll;                 # from FHEMWEB: longpoll 
#  $FW_wname;                    # from FHEMWEB: name of web-instance
#  %FW_pos=();                   # from FHEMWEB: scroll position
#  $FW_subdir					 # from FHEMWEB: path of floorplan-subdir - enables reusability of FHEMWEB-routines for sub-URLS like floorplan
#  $FW_cname                     # from FHEMWEB: Current connection name
my $FW_encoding="UTF-8";		 # like in FHEMWEB: encoding hardcoded
my $FW_plotmode="";              # like in FHEMWEB: SVG
my $FW_plotsize;				 # like in FHEMWEB: like in fhemweb dependent on regular/smallscreen/touchpad
my %FW_zoom;                     # copied from FHEMWEB - using local version to avoid global variable
my @FW_zoom;                     # copied from FHEMWEB - using local version to avoid global variable
my @styles = ("0 (Icon only)","1 (Name+Icon)","2 (Name+Icon+Commands)","3 (Device-Reading)","4 (S300TH-specific)","5 (Icon+Commands)","6 (Reading+Timestamp)");


#-------------------------------------------------------------------------------
sub 
FLOORPLAN_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}        = "FP_define";
  $hash->{GetFn}        = "FP_Get";
  $hash->{FW_detailFn}  = "FP_detailFn";   #floorplan-specific detail-screen
  $hash->{AttrList}     = "refresh fp_arrange:1,detail,WEB,0 commandfield:1,0 fp_default:1,0 ".
                          "stylesheet fp_noMenu:1,0 fp_backgroundimg fp_setbutton:1,0 fp_viewport ".
						  "fp_roomIcons";
  # CGI
  my $name = "floorplan";
  my $fhem_url = "/" . $name ;
  $data{FWEXT}{$fhem_url}{FUNC} = "FP_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = "Floorplans";
 #$data{FWEXT}{$fhem_url}{EMBEDDED} = 1;               # not using embedded-mode to save screen-space
  # Global-Config for CSS
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
  my $name = $hash->{NAME};
  if (AttrVal("global","userattr","") !~ m/fp_$name/) {
	addToAttrList("fp_$name");                                                  # create userattr fp_<name> if it doesn't exist yet
#	Log 3, "Floorplan - added global userattr fp_$name";
    Log3 $name, 3, "Floorplan - added global userattr fp_$name";
  }
  return undef;
}


#-------------------------------------------------------------------------------
##################
# FLOORPLAN get
sub 
FP_Get($@) {
  my ($hash, @a) = @_;
  my $arg = (defined($a[1]) ? $a[1] : ""); #command
  my $name = $hash->{NAME};
  return "use command: get <dev> getConfig" if ($#a != 1 || $arg ne "config");
  return FP_getConfig( $name ) if ($arg eq "config");
}


#-------------------------------------------------------------------------------
##################
# FP MAIN: Answer URL call
sub 
FP_CGI(){
  my ($htmlarg) = @_;                                                               #URL
  ## reset parameters
  $FP_name = undef;
  my ($p,$v) = ("","");                                                             #parameter and value of analyzed URL
  $FW_RET = "";                                                                     # blank out any html-code written so far by fhemweb
  $FW_subdir = "";
  $FW_longpoll = AttrVal($FW_wname, "longpoll", undef);                             # longpoll
  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");  
  $htmlarg =~ s/^\///;                                                             # eliminate leading /
  ## derive floorplan-name
  my @params = split(/\//,$htmlarg);                                               # split URL by /
  if ($params[2]) {                                                                # URL with CGI-parameters has addtl / -> use $FP_name
    $FP_name = $params[1];
    $params[1] = $params[2];
  }
  my @htmlpart = split("\\?", $params[1]) if ($params[1]);                         # split URL by ?   ->   htmlpart[0] = FP_name, htmlpart[1] = commandstring
  $FP_name = $htmlpart[0] if (!$FP_name);
  ### set global parameters, check floorplan-name  
  if ($FP_name) {																   # floorplan-name is part of URL
	if(!defined($defs{$FP_name}) && $FP_name ne "floorplanstartpage"){
      $FW_RET = "ERROR: Floorplan $FP_name not defined \n";					       # check for typo in URL
      return ("text/plain; charset=$FW_encoding", $FW_RET);
	}
    $FP_arrange =  AttrVal($FP_name, "fp_arrange", 0);                             # set arrange mode
    $FP_viewport = AttrVal($FP_name, "fp_viewport", "width=768") if ($FP_name);    # viewport definition
    $FW_subdir = "/floorplan/$FP_name";
  } else {																		   # no floorplan-name in URL....
	$FP_arrange_default = undef;
	$FP_arrange_selected = undef;
	my $dev = undef;
	my $tmpname = undef;
	my $cnt = 0;
	foreach my $fp (keys %defs) {
	  next if ($defs{$fp}{TYPE} ne "FLOORPLAN");
      if (AttrVal($fp, "fp_default", undef)) {									   # use floorplan with attr fp_default
        $FP_name = $fp;
        last;
      } else {
        $tmpname=$fp;
        $cnt++;
      }
    }
    $FP_name = $tmpname if (!$FP_name && $cnt==1);                                 # otherwise, if only one floorplan, use that one
    $FP_name = "floorplanstartpage" if (!$FP_name);                                # otherwise go to startpage
    $FW_subdir = "/floorplan/$FP_name";
    $FP_arrange = AttrVal($FP_name, "fp_arrange", 0);
  }
  ## process cgi
  my $commands = FP_digestCgi($htmlpart[1]) if $htmlpart[1];                       # analyze URL-commands
  my $FP_ret = AnalyzeCommand(undef, $commands) if $commands;                      # Execute commands
#  Log 1, "FLOORPLAN: regex-error. commands: $commands; FP_ret: $FP_ret" if($FP_ret && ($FP_ret =~ m/regex/ ));  #test
  Log3 "FLOORPLAN", 1, "FLOORPLAN: regex-error. commands: $commands; FP_ret: $FP_ret" if($FP_ret && ($FP_ret =~ m/regex/ ));  #test
  #####redirect URL - either back to fhemweb-detailscreen, or for redirectCmds to suppress repeated execution of commands upon browser refresh
  my $me = $defs{$FW_cname};                                                       # from FHEMWEB: Current connection name
  my $tgt = undef;
  if( !$htmlpart[0] || (AttrVal($FW_wname, "redirectCmds", 1) && $me && $commands && !$FP_ret)) {
    if($FP_name) {
      $tgt = "/floorplan/$FP_name" 
	} else {
      $FW_RET = 'ERROR: floorplan-name could not be derived from URL, fp_default or single floorplanname.';
      return ("text/plain; charset=$FW_encoding", $FW_RET);
    }
  }
  $tgt = "?detail=$FP_fwdetail" if ($FP_fwdetail);                                  #return to fhemweb-detail-screen if coming from there
  if ($tgt) {
    my $tgt = $FW_ME.$tgt;
    my $c = $me->{CD};
    print $c "HTTP/1.1 302 Found\r\n",
            "Content-Length: 0\r\n",
            "Location: $tgt\r\n",
            "\r\n";
	return;
  }
  ### output html-pages
  if($FP_name eq "floorplanstartpage") {
    FP_showStart();         # show Startscreen if zero or more than one floorplan, and none with fp_default assigned
  } else {
    FP_show();              # show floorplan
  }
  # finish HTML & leave
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
  %FP_webArgs = ();
  $FP_fwdetail = undef;
  $arg =~ s,^[?/],,;
  foreach my $pv (split("&", $arg)) {                                   #per each URL-section devided by &
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);                                     #$p = parameter, $v = value
    $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");                 # Multiline: escape the NL for fhem
    $FP_webArgs{$p} = $v;
    if($p eq "arr.dev")        { $v =~ m,^([\.\w]*)\s\(,; $v = $1 if ($1); $FP_arrange_selected = $v; $FP_arrange_default = $v; }
    if($p eq "add.dev")        { $v =~ m,^([\.\w]*)\s\(,; $v = $1 if ($1); $cmd = "attr $v fp_$FP_name 50,100"; }
    if($p eq "cmd")            { $cmd = $v; }
    if($p =~ m/^cmd\.(.*)$/)   { $cmd = $v; $c = $1; }
    if($p =~ m/^detl\.(.*)$/)  { $FP_fwdetail = $1; }
    if($p =~ m/^dev\.(.*)$/)   { $dev{$1}   = $v; }
    if($p =~ m/^arg\.(.*)$/)   { $arg{$1}   = $v; }
    if($p =~ m/^val\.(.*)$/)   { $val{$1}   = $v; }
    if($p =~ m/^deva\.(.*)$/)  { $deva{$1}  = $v; $FP_arrange_selected = undef;}
    if($p =~ m/^attr\.(.*)$/)  { $attr{$1}  = $v; }
    if($p =~ m/^top\.(.*)$/)   { $top{$1}   = $v; }
    if($p =~ m/^left\.(.*)$/)  { $left{$1}  = $v; }
    if($p =~ m/^style\.(.*)$/) { $style{$1} = int(substr($v,0,2)); }
    if($p =~ m/^text\.(.*)$/)  { $text{$1}  = $v; }
	if($p eq "pos")            { %FW_pos =  split(/[=;]/, $v); }
  }
  my $dele = ($cmd =~ m/^deleteattr/);
  $cmd.=" $dev{$c}"   if(defined($dev{$c}));              #FHT device
  $cmd.=" $arg{$c}"   if(defined($arg{$c})&&
                       ($arg{$c} ne "state" || $cmd !~ m/^set/));     #FHT argument (e.g. desired-temp)
  $cmd.=" $val{$c}"   if(defined($val{$c}));              #FHT value
  $cmd.=" $deva{$c}"  if(defined($deva{$c}));             #arrange device
  $cmd.=" $attr{$c}"  if(defined($attr{$c}));             #arrange attr
  $cmd.=" $top{$c}"   if(defined($top{$c})  && !$dele);   #arrange top
  $cmd.=",$left{$c}"  if(defined($left{$c}) && !$dele);   #arrange left
  $cmd.=",$style{$c}" if(defined($style{$c})&& !$dele);   #arrange style
  $cmd.=",$text{$c}"  if(defined($text{$c}) && !$dele);   #arrange text
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
    FW_pO "<link rel=\"apple-touch-icon-precomposed\" href=\"" . FW_IconURL("fhemicon") . "\"/>";
    FW_pO "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\"/>";
    if($FW_ss) {
      FW_pO "<meta name=\"viewport\" content=\"width=320\"/>";
    } elsif($FW_tp) {
      FW_pO "<meta name=\"viewport\" content=\"".$FP_viewport."\"/>";
    }
  }
  # refresh-value
  my $rf = AttrVal($FW_wname, "refresh", "");
  FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf); # use refresh-value from Web-Instance
  # stylesheet
  my $defaultcss = AttrVal($FW_wname, "stylesheetPrefix", "") . "floorplanstyle.css";
  my $css= AttrVal($FP_name, "stylesheet", $defaultcss);
  FW_pO  "<link href=\"$FW_ME/css/$css\" rel=\"stylesheet\"/>";
  #set sripts
#  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/js/svg.js\"></script>"
#                        if($FW_plotmode eq "SVG");
#  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/js/fhemweb.js\"></script>";
  my $jsTemplate = '<script type="text/javascript" src="%s"></script>';
  FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/svg.js") if($FW_plotmode eq "SVG");
  foreach my $js (@FW_fhemwebjs) {
    FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/$js");
  }
  # FW Extensions
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{SCRIPT});
      FW_pO "<script type=\"text/javascript\" ".
                "src=\"$FW_ME/js/$h->{SCRIPT}\"></script>";
    }
  }
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
  FP_menu();
  FW_pO "<div class=\"screen\" id=\"hdr\">";
  FW_pO "<form method=\"get\" action=\"" . $FW_ME . "\">";
  FW_pO "<table WIDTH=\"100%\"><tr>";
  FW_pO "<td><input type=\"text\" name=\"cmd\" size=\"30\"/></td>";   						  #input-field
  FW_pO "</tr></table>";
  FW_pO "</form></div>";
  # add edit *floorplanstyle.css if FP_arrange ?
  # no floorplans defined? -> show message
  my $count=0;
  foreach my $f (sort keys %defs) {
	next if ($defs{$f}{TYPE} ne "FLOORPLAN");
	$count++;
  }
  if ($count == 0) {
    FW_pO '<div id="startcontent">';
	FW_pO "<br><br><br><br>No floorplans have been defined yet. For definition, enter<br>";
	FW_pO "<ul><code>define &lt;name&gt; FLOORPLAN</code></ul>";
	FW_pO "Also check the <a href=\"$FW_ME/docs/commandref.html#FLOORPLAN\">commandref</a><br>";
	FW_pO "</div>";
  }
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
  my $onload = $FW_longpoll ? "onload=\"FW_delayedStart()\"" : "";
  FW_pO "<body id=\"$FP_name-body\" $onload>\n";
  FW_pO "<div id=\"backimg\" style=\"width: 99%; height: 99%;\">";
  FW_pO FW_makeImage(AttrVal($FP_name, "fp_backgroundimg", "fp_$FP_name"));
  FW_pO "</div>\n";
  ## menus
  FP_menu();
  FP_menuArrange() if ($FP_arrange && ($FP_arrange eq "1" || ($FP_arrange eq $FW_wname) || $FP_arrange eq "detail"));   #shows the arrange-menu
  ## start floorplan  
  FW_pO "<div class=\"screen\" id=\"floorplan\">";
  FW_pO "<div id=\"logo\"></div>";
  ## commandfield in floorplan  
  if (AttrVal("$FP_name", "commandfield", undef)) {
       FW_pO "<div id=\"hdr\">\n";
       FW_pO " <form>";
       FW_pO "  <input type=\"text\" name=\"cmd\" size=\"30\"/>\n";							   #fhem-commandfield
       FW_pO " </form>";
       FW_pO "</div>\n";
   }
   ## let's go
   foreach my $d (sort keys %defs) {                                                          # loop all devices
		my $type = $defs{$d}{TYPE};
		my $attr = AttrVal("$d","fp_$FP_name", undef);
		next if(!$attr || $type eq "weblink");                                               # skip if device-attribute not set for current floorplan-name
		
		my ($top, $left, $style, $text, $text2) = split(/,/ , $attr);
		# $top   = position in px, top
		# $left  = position in px, left
		# $style = style (0=icon only, 1=name+icon, 2=name+icon+commands, 3=device-Reading + name from $text2, 4=S300TH, 5=icon+commands, 6 device-Reading+timestamp)
		# $text  = alternativeCaption
		# $text2 = special for style3+6: $text = ReadingID, $text2=alternativeCaption
		$left = 0 if (!$left);
		$style = 0 if (!$style);
        # start device-specific table
		FW_pO "\n<div style=\"position:absolute; top:".$top."px; left:".$left."px;\" id=\"div-$d\">";
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name/$d\" autocomplete=\"off\">";
		FW_pO " <table class=\"$type fp_$FP_name\" id=\"table-$d\" align=\"center\">";         # Main table per device
		my ($allSets, $cmdlist, $txt) = FW_devState($d, "");
		$txt = ReadingsVal($d, $text, "Undefined Reading $d-<b>$text</b>") if ($style == 3 || $style == 6);   # Style3+6 = DeviceReading given in $text
		my $cols = ($cmdlist ? (split(":", $cmdlist)) : 0);                                    # Need command-count for colspan of devicename+state
		
    ########################
    # Device-name per device
		if ($style gt 0 && $style ne 5) {
			FW_pO "   <tr class=\"devicename fp_$FP_name\" id=\"$d-devicename\">";             # For css: class=devicename, id=<devicename>-devicename
			my $devName = "";
			if ($style == 3 || $style == 6) {
				$devName = $text2 ? $text2 : "";											   # Style 3 = Reading - use last part of comma-separated description
				} else {
				$devName = ($text ? $text : AttrVal($d, "alias", $d));	 
			}
			if ($style == 4 && $txt =~ /T: ([\-0-9\.]+)[ ]+H: ([\-0-9\.]+).*/) { 		       # S300TH-specific
				$txt = "<span class='fp_tempvalue' display=inline><span informId=$d-temperature>".$1."</span>&deg;C</span><BR><span class='fp_humvalue'><span informId=$d-humidity>".$2."</span>%</span>"; 
			} 
			FW_pO "<td colspan=\"$cols\">";
			FW_pO "$devName" ;
			FW_pO "</td></tr>";
		}

    ########################
    # Device-state per device
#	    FW_pO "<tr class=\"devicestate fp_$FP_name\" id=\"$d\">";                               # For css: class=devicestate, id=devicename
	    if ($style == 3 || $style == 6) {
	      FW_pO "<tr class=\"devicereading fp_$FP_name\" id=\"$d"."-$text\">";                  # For css: class=devicereading, id=<devicename>-<reading>
	    } else {  
	      FW_pO "<tr class=\"devicestate fp_$FP_name\" id=\"$d\">";                             # For css: class=devicestate, id=<devicename>
	    }
        $txt =~ s/measured-temp: ([\.\d]*) \(Celsius\)/$1/;                                     # format FHT-temperature
	    ### use device-specific icons according to userattr fp_image or fp_<floorplan>.image
	    my $fp_image = AttrVal("$d", "fp_image", undef);                                        # floorplan-independent icon
        my $fp_fpimage = AttrVal("$d","fp_$FP_name".".image", undef);                           # floorplan-dependent icon
        if ($fp_image) {
            my $state = ReadingsVal($d, "state", undef);
	    $fp_image =~ s/\{state\}/$state/;                                                       # replace {state} by actual device-status
            $txt =~ s/\<img\ src\=\"(.*)\"/\<img\ src\=\"\/fhem\/icons\/$fp_image\"/;           # replace icon-link in html
            $txt =~ s/\<img\ (.*) src\=\"(.*)\"/\<img\ $1 src\=\"\/fhem\/images\/default\/$fp_image\"/;           # replace icon-link in html (new)
        }
        if ($fp_fpimage) {
            my $state = ReadingsVal($d, "state", undef);
            $fp_fpimage =~ s/\{state\}/$state/;                                                 # replace {state} by actual device-status
            $txt =~ s/\<img\ src\=\"(.*)\"/\<img\ src\=\"\/fhem\/icons\/$fp_fpimage\"/;         # replace icon-link in html
            $txt =~ s/\<img\ (.*) src\=\"(.*)\"/\<img\ $1 src\=\"\/fhem\/images\/default\/$fp_fpimage\"/;     # replace icon-link in html (new)
        }
		if ($style == 3 || $style == 6) {
		  FW_pO "<td><div informId=\"$d-$text\">$txt</div>";                                    # reading
		} elsif ($style == 4) {
		  FW_pO "<td>$txt";                                                                     # state style4
        } else {
	      FW_pO "<td informId=\"$d\" colspan=\"$cols\">$txt";                                   # state
		}
	    FW_pO "</td></tr>";
	
	    if ($style == 6) {                                                                      # add ReadingsTimeStamp for style 6
		  $txt="";
    	  FW_pO "<tr class=\"devicetimestamp fp_$FP_name\" id=\"$d-devicetimestamp\">";         # For css: class=devicetimestamp, id=<devicename>-devicetimestamp
		  $txt = ReadingsTimestamp($d, $text, "Undefined Reading $d-<b>$text</b>");             # Style3+6 = DeviceReading given in $text
#          FW_pO "<td><div colspan=\"$cols\" informId=\"$d-$text-ts\">$txt</div></td>";
		  FW_pO "<td><div colspan=\"$cols\" informId=\"$d-$text-ts\">$txt</div>";
	      FW_pO "</td></tr>";
	    }

    ########################
    # Commands per device		  
        if($cmdlist && ( $style == 2 || $style == 5) ) {
          my @cList = split(":", $cmdlist);
          my @rList = map { ReplaceEventMap($d,$_,1) } @cList;
          my $firstIdx = 0;
		  FW_pO "  <tr class=\"devicecommands\" id=\"$d-devicecommands\">";

          # Special handling (slider, dropdown, timepicker)
#		  my $FW_room = undef;  ##needed to be able to reuse code from FHEMWEB
          my $cmd = $cList[0];
          if($allSets && $allSets =~ m/$cmd:([^ ]*)/) {
            my $values = $1;
            my $oldMe = $FW_ME;
            $FW_ME = "$FW_ME/floorplan/$FP_name";
            foreach my $fn (sort keys %{$data{webCmdFn}}) {
			  my $FW_room = ""; ##needed to be able to reuse code from FHEMWEB
              no strict "refs";
              my $htmlTxt = &{$data{webCmdFn}{$fn}}("$FW_ME",
                                                 $d, $FW_room, $cmd, $values);
              use strict "refs";
              if(defined($htmlTxt)) {
			    $htmlTxt =~ s/>desired-temp/>/;        #mod20130929
				$htmlTxt =~ s/>desiredTemperature/>/;  #mod20131225
				FW_pO $htmlTxt;
                $firstIdx = 1;
                last;
              }
            }
            $FW_ME = $oldMe;
          }
		  # END # Special handling (slider, dropdown, timepicker)
		  
          for(my $idx=$firstIdx; $idx < @cList; $idx++) {
            FW_pH "cmd.$d=set $d $cList[$idx]",
                ReplaceEventMap($d,$cList[$idx],1),1,"devicecommands";
          }
		  FW_pO "</tr>"; 
        } elsif($type eq "FileLog") {
#          $row = FW_dumpFileLog($d, 1, $row);
        }

	    FW_pO "</table></form>";
	    FW_pO "</div>\n";
	}
   
 	########################  
	# Finally the weblinks
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
		FW_pO "\n<div style=\"position:absolute; top:".$top."px; left:".$left."px\" id = \"div-$d\">";              # div to position the weblink
		FW_pO "<div class = \"fp_$type fp_$FP_name weblink\" id = \"$d\">";											# div to make it accessible to arrangeByMouse
		# print weblink
		$buttons = FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, $buttons);
		FW_pO "</div></div>";
	}
	FW_pO "</div>";
	FW_pO "</body>\n";
}


#-------------------------------------------------------------------------------
##################
# Floorplan menu left
sub
FP_menu() {
    return if ($FP_name && AttrVal($FP_name, "fp_noMenu", 0));                       # fp_noMenu suppresses menu
	FW_pO "<div class=\"floorplan\" id=\"menu\">";
    # List FPs
	FW_pO "<table class=\"start\" id=\"floorplans\">";
	FW_pO "<tr>";
	FW_pH "$FW_ME", "fhem", 1;
	FW_pO "</tr>";
	foreach my $f (sort keys %defs) {
		next if ($defs{$f}{TYPE} ne "FLOORPLAN");
    	FW_pO "<tr><td>";
#		FW_pH "$FW_ME/floorplan/$f", $f, 0;
        my $icoName = "ico$f";
        map { my ($n,$v) = split(":",$_); $icoName=$v if($f =~ m/$n/); }
        split(" ", AttrVal($FP_name, "fp_roomIcons", ""));
        my $icon = FW_iconName($icoName) ?  FW_makeImage($icoName,$icoName,"icon")."&nbsp;" : "";
        FW_pO "<a href=\"$FW_ME/floorplan/$f\">$icon$f</a></td>";
    	FW_pO "</td></tr>";
	}
	FW_pO "</table><br>";
	FW_pO "</div>\n";
}


#-------------------------------------------------------------------------------
##################
# Arrange-menu
sub
FP_menuArrange() {
	my %desc=();
	## collect data
	$FP_arrange_default  = "" if (!$FP_arrange_default);
	my @fpl;                                                                # devices assigned to floorplan
	my @nfpl;                                                               # devices not assigned to floorplan
	foreach my $d (sort keys %defs) {                                       # loop all devices
		my $type = $defs{$d}{TYPE};
		# exclude these types from list of available devices
		next if($type =~ m/^(WEB|CUL$|FHEM.*|FileLog|PachLog|PID|SUNRISE.*|FLOORPLAN|holiday|Global|notify|autocreate)/ );
		my $disp = $d;
		$disp .= ' (' . AttrVal($d,"room","Unsorted").") $type";
		my $alias = AttrVal($d, "alias", undef);
		$disp .= ' (' . $alias . ')' if ($alias);
		$desc{$d} = $disp;
		if (AttrVal("$d","fp_$FP_name", undef)) {
			push(@fpl, $disp);                                               # all devices on floorplan
		} else {
			push(@nfpl, $disp);                                              # all devices not on floorplan
		}
	}
	my $d = $FP_arrange_selected;
	my $attrd = AttrVal($d, "fp_$FP_name", undef) if ($d);
	if ( $FP_arrange_selected && !$attrd) {                                  # arrange-selected, but device is not part of fp now chosen -> reset arrange-selected
	  $FP_arrange_selected = undef;
	}
	FW_pO "<div style=\"z-index:999\" class=\"fp_arrange\" id=\"fpmenu\">";

	# add device to floorplan
	if (!defined($FP_arrange_selected)) {
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form1
		FW_pO "<div class=\"menu-add\" id=\"fpmenu\">\n" .                                       
		($FP_fwdetail?FP_input("detl.$FP_fwdetail", $FP_fwdetail, "hidden") . "\n" :"") .
		FW_select("","add.dev", \@nfpl, "", "menu-add") .
		FW_submit("ccc.one", "add");
		FW_pO "</div></form>\n"; #form1
	}

	# select device to be arranged
	if (!defined($FP_arrange_selected)) {
		my $dv = $FP_arrange_default;
		$dv =  $desc{$dv} if ($dv);
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form2
		FW_pO "<div class=\"menu-select\" id=\"fpmenu\">\n" .                                       
		($FP_fwdetail?FP_input("detl.$FP_fwdetail", $FP_fwdetail, "hidden") . "\n" :"") .
		FW_select("","arr.dev", \@fpl, $dv, "menu-select") .
		FW_submit("ccc.one", "select");
		FW_pO "</div></form>"; #form2
	}

	# fields for top,left,style,text
	if ($attrd) {
	  if (!$FP_fwdetail) {                                                                                      # arrange-by-mouse not from fhemweb-screen floorplan-details
	    #### arrangeByMouse by Torsten
		FW_pO "<script type=\"text/javascript\">";
		FW_pO "function show_coords(e){";
		FW_pO "  var device = document.getElementById(\"fp_ar_input_top\").name.replace(/top\./,\"\");";		# get device-ID from 'top'-field
		FW_pO "  var X = e.pageX;";    																		    # e is the event, pageX and pageY the click-ccordinates
		FW_pO "  var Y = e.pageY;";
		FW_pO "  document.getElementById(\"fp_ar_input_top\").value = Y;";									    # updates the input-fields top and left with the click-coordinates
		FW_pO "  document.getElementById(\"fp_ar_input_left\").value = X;";
		FW_pO "  document.getElementById(\"div-\"+device).style.top = Y+\"px\";"; 						    	# moves the device
		FW_pO "  document.getElementById(\"div-\"+device).style.left = X+\"px\";"; 
		FW_pO "}";
		FW_pO "document.getElementById(\"backimg\").addEventListener(\"click\",show_coords,false);";			# attach event-handler to background-picture
		FW_pO "</script>";
      }
	### build the form
		my $disp =  $FP_arrange eq "detail" ? $desc{$d} : $d;
		FW_pO "<form method=\"get\" action=\"$FW_ME/floorplan/$FP_name\">"; #form3
		my ($top, $left, $style, $text, $text2) = split(",", $attrd);
		$text .= ','.$text2 if ($text2);														# re-append Description after reading-ID for style3
		$style = $styles[$style];
		FW_pO "<div class=\"menu-arrange\" id=\"fpmenu\">\n" .
		    ($FP_fwdetail?FP_input("detl.$FP_fwdetail", $FP_fwdetail, "hidden") . "\n" :"") .
			FP_input("deva.$d", $d, "hidden") . "\n" .
			FP_input("dscr.$d", $disp, "text", "Selected device", 45, "", "disabled") . "\n<br>\n" . 
			FP_input("attr.$d", "fp_$FP_name", "hidden") . "\n" .
			FP_input("top.$d", $top ? $top : 10, "text", "Top", 4, 4, 'id="fp_ar_input_top"') . "\n" .
			FP_input("left.$d", $left ? $left : 10, "text", "Left", 4, 4, 'id="fp_ar_input_left"' ) . "\n" .
			FW_select("","style.$d", \@styles, $style ? $style : 0, "menu-arrange") . "\n" .
			FP_input("text.$d", $text ? $text : "", "text", "Description", 15) . "\n" .
			FW_submit("cmd.$d", "attr") . "\n" .
			FW_submit("cmd.$d", "deleteattr");
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
	$title     = $title     ? " title=\"$title\""         : "";
	$size      = $size      ? " size=\"$size\""           : "";
	$maxlength = $maxlength ? " maxlength=\"$maxlength\"" : "";
	$addition = "" if (!defined($addition));
	return "<input type=\"$type\"$title$size$maxlength $addition name=\"$n\" value=\"$v\"/>\n";
}


#-------------------------------------------------------------------------------
##################
#floorplan-specific fhemweb detail-screen
sub 
FP_detailFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $link   = $hash->{LINK};
  my $wltype = $hash->{WLTYPE};
  ## Arrange-menu at top of fhemweb-detail-screen
  FW_pO '<table class="block wide"><tr><td>';
  $FP_name = $d;
  $FP_fwdetail = $d;
  FP_menuArrange();
  $FP_fwdetail = undef;
  FW_pO '</td></tr></table>';
  ## list of assigned devices
  my $row = 0;
  FW_pO "<br>Devices assigned to floorplan \"$d\"<br>";
  FW_pO '<table class="block wide">';
  FW_pO '<thead><tr><th><b>Device</b></th><th><b>X</b></th><th><b>Y</b></th><th><b>Style</b></th><th><b>Text</b></th></tr></thead>';
  foreach my $fpd (sort keys %defs) {
    my $val = AttrVal($fpd,"fp_$d",undef);
	next if (!$val);
    my ($x,$y,$style,$txt,$txt2) = split(",",$val);
	$txt  = "" if (!$txt);
	$txt2 = "" if (!$txt2);
    $row++;
    my $ret  = '<tr class = "';
    $ret .= ($row/2==int($row/2))?"even":"odd";
    $ret .= '">';
    $ret .=   "<td><div class=\"dname\"><a href=\"$FW_ME?detail=$fpd\">$fpd</a></div></td>";
#	FW_pH "detail=$_", $_;
#	$ret = "<a href=\"$link\">$txt</a>";
    $ret .=   "<td><div class=\"dval\">$x</div></td>";
    $ret .=   "<td><div class=\"dval\">$y</div></td>";
    $ret .=   "<td><div class=\"dval\">";
	$ret .=   $styles[$style] if (defined($style)&& defined($styles[$style]));
	$ret .=   "</div></td>";
    $ret .=   "<td><div class=\"dval\">$txt".($txt2?",$txt2":"")."</div></td>";
    $ret .= "</tr>";
    FW_pO $ret;
  }
  FW_pO '</table><br>';
  ## Arrange-mode on/off
  FW_pO "Arrange-mode<br>";
  FW_pO '<table class="block wide">';
  my $armon = "<div class=\"dval\"><a href=\"$FW_ME?cmd.$d=attr $d fp_arrange 1&detail=$d\"><div class=\"col2\">on</div></a></div>";
  my $armoff= "<div class=\"dval\"><a href=\"$FW_ME?cmd.$d=attr $d fp_arrange 0&detail=$d\"><div class=\"col2\">off</div></a></div>";
  FW_pO "<tr><td><div class=\"dname\">fp_arrange</div></td><td>$armon</td><td>$armoff</td></tr>";
  FW_pO '</table><br>';
  return;
}


#-------------------------------------------------------------------------------
##################
# FLOORPLAN getConfig - can be copied into an include-file
sub
FP_getConfig($) {
  my $dev = shift;
  my $html="";
  if (!defined($defs{$dev})) {
     return "get: Device $dev not defined.";
  }
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  $year += 1900;
  $html .= FP_pOfill(80, ("Config for FLOORPLAN $dev","$mday.$month.$year $hour:$min","get $dev config"));
  $html .= FP_pOfill(80, "Definition and attributes for $dev");
  $html .= "define $dev FLOORPLAN\n";
  ## attributes of floorplan-device
  foreach my $a (sort keys %{$attr{$dev}}) { 
    my $val = AttrVal($dev,$a,undef);
	next if (!$val);  
    $html .= "attr $dev $a $val\n";
  }
  $html .= "\n\n";
  $html .= FP_pOfill(80,"Attributes for devices assigned to $dev");
  ## attributes of assigned devices
  foreach my $d (sort keys %defs) {
    my $val = AttrVal($d,"fp_$dev",undef);
	next if (!$val);
    $html .=  "attr $d fp_$dev $val\n";
  }
  $html .= "\n\n".FP_pOfill(80, "End of config for FLOORPLAN $dev");
  return $html;
}


#-------------------------------------------------------------------------------
##################
# FLOORPLAN FP_pOfill - FW_pO with filling up with #
sub 
FP_pOfill($@) {
  my ($digits,@lines,) = @_;
  my $ret = "#" x $digits . "\n";
  $ret .= ("#"." " x ($digits-2))."#\n";
  foreach my $line (@lines) {
    $ret .= "# ".$line;
    my $len = length($line);
    $ret .= (" " x ($digits-$len-3))."#\n" if ( $digits-$len-3 > 0);
  }
  $ret .= ("#"." " x ($digits-2))."#\n";
  $ret .= "#" x $digits . "\n\n";
  return $ret;
}


1;

=pod
=begin html

<a name="FLOORPLAN"></a>
<h3>FLOORPLAN</h3>
<ul>
  Implements an additional entry "Floorplans" to your fhem menu, leading to a userinterface without fhem-menu, rooms or devicelists.
  Devices can be displayed at a defined coordinate on the screen, usually with a clickable icon allowing to switch
  the device on or off by clicking on it. A background-picture can be used - use e.g. a floorplan of your house, or any picture.
  Use floorplanstyle.css to adapt the representation.<br>
  Step-by-step setup guides are available in
  <a href="http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/fhem-floorplan-installation-guide.pdf?format=raw">english</a> and
  <a href="http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/fhem-floorplan-installation-guide_de.pdf?format=raw">german</a>. <br>
  <br>

  <a name="FLOORPLANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FLOORPLAN </code>
    <br><br>

    <b>Hint:</b> Store fp_&lt;name&gt;.png in your image folder (www/images/default , www/pgm2 or FHEM) to use it as background picture.<br><br>
    Example:
    <ul>
      <code>
	  define Groundfloor FLOORPLAN<br>
	  fp_Groundfloor.png
	  </code><br>
    </ul>
  </ul>
  <br>

  <a name="FLOORPLANset"></a>
  <b>Set </b>
  <ul>
      <li>N/A</li>
  </ul>
  <br>

  <a name="FLOORPLANget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; config</code>
    <br>
	Displays the configuration of the floorplan <name> with all attributes. Can be used in an include-file.
  </ul>
  <br>

  <a name="FLOORPLANattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="fp_fpname">userattr fp_&lt;name&gt; &lt;top&gt;,&lt;left&gt;[,&lt;style&gt;[,&lt;description&gt;]]</a><br><br>
    A <a href="#userattr">userattr</a> fp_&lt;name&gt; will be created automatically if it does not exist yet.<br>
	<ul>
      <li>top   = screen-position, pixels from top of screen</li>
      <li>left  = screen-position, pixels from left of screen</li>
      <li>style =
		<ul>
			<li>0  icon/state only</li>
			<li>1  devicename and icon/state</li>
			<li>2  devicename, icon/state and commands</li>
			<li>3  device-reading and optional description</li>
			<li>4  S300TH-specific, displays temperature above humidity</li>
			<li>5  icon/state and commands</li>
			<li>6  device-reading, reading-timestamp and optional description</li>
		</ul>
	  </li>
      <li>description will be displayed instead of the original devicename</li>
    </ul></li><br>
    Examples:<br>
    <ul>
		<table>
			<tr><td><code>attr lamp1 fp_Groundfloor 100,100</code></td><td><code>#display lamp1 with icon only at screenposition 100,100</code></td></tr>
			<tr><td><code>attr lamp2 fp_Groundfloor 100,140,1,Art-Deco</code></td><td><code>#display lamp2 with description 'Art-Deco-Light' at 100,140</code></td></tr>
			<tr><td><code>attr lamp2 fp_FirstFloor  130,100,1</code></td><td><code>#display the same device at different positions on other floorplans</code></td></tr>
			<tr><td><code>attr myFHT fp_Groundfloor 300,20,10,Temperature</code></td><td><code>#display given Text + FHT-temperature</code></td></tr>
		</table>
	</ul>
	<b>Hint:</b> no blanks between parameters<br><br>


    <li><a name="fp_arrange">fp_arrange</a><br>
  	  Activates the "arrange mode" which shows an additional menu on the screen,
	  allowing to place devices easily on the screen.<br>
	  Example:
	<ul>
      <code>attr Groundfloor fp_arrange 1</code><br>
	  <code>attr Groundfloor fp_arrange detail  #displays the devices with infos room, type, alias</code><br>
	  <code>attr Groundfloor fp_arrange WEB     #activates arrange mode for frontend-device WEB only</code><br><br>
    </ul>
    </li>
    <li><a name="stylesheet">stylesheet</a><br>
	Explicitely sets your personal stylesheet for the floorplan. This overrides the standard stylesheet.
	The standard stylesheet for floorplans is <code>floorplanstyle.css</code>. If the <a href="#stylesheetPrefix">stylesheetPrefix</a> is set for the corresponding FHEMWEB instance, this same
	<code>stylesheetPrefix</code> is also prepended to the stylesheet for floorplans.<br>
	All stylesheets must be stored in the stylesheet subfolder of the fhem filesystem hierarchy. Store your personal
	stylesheet along with <code>floorplanstyle.css</code> in the same folder.<br>
	Example:
	<ul>
       <code>attr Groundfloor stylesheet myfloorplanstyle.css</code><br><br>
    </ul>
    </li>

	<li><a name="fp_default">fp_default</a><br>
	The floorplan startscreen is skipped if this attribute is assigned to one of the floorplans in your installation.
	</li>
    Example:
	<ul>
      <code>attr Groundfloor fp_default 1</code><br><br>
    </ul>

	<li><a name="fp_noMenu">fp_noMenu</a><br>
	Suppresses the menu which usually shows the links to all your floorplans.
	</li>
    Example:
	<ul>
      <code>attr Groundfloor fp_noMenu 1</code><br><br>
    </ul>

    <li><a name="commandfield">commandfield</a><br>
	Adds a fhem-commandfield to the floorplan screen.
	</li>
    Example:
	<ul>
      <code>attr Groundfloor commandfield 1</code><br><br>
    </ul>
	
    <li><a name="fp_backgroundimg">fp_backgroundimg</a><br>
	 Allows to choose a background-picture independent of the floorplan-name.
	</li>
    Example:
	<ul>
      <code>attr Groundfloor fp_backgroundimg foobar.png</code><br><br>
    </ul>
	
    <li><a name="fp_viewport">fp_viewport</a><br>
	  Allows usage of a user-defined viewport-value for touchpad.<br>
	  Default-viewport-value is "width=768".
    </li>
	
	<a name="fp_roomIcons"></a>
    <li>fp_roomIcons<br>
        Space separated list of floorplan:icon pairs, to assign icons
        to the floorplan-menu, just like the functionality for rooms
        in FHEMWEB. Example:<br>
        attr Grundriss fp_roomIcons Grundriss:control_building_empty Media:audio_eq
    </li>
	
    <li><a name="fp_inherited">Inherited from FHEMWEB</a><br>
	 The following attributes are inherited from the underlying <a href="#FHEMWEB">FHEMWEB</a> instance:<br>
     <ul>
		<a href="#smallscreen">smallscreen</a><br>
		<a href="#touchpad">touchpad</a><br>
		<a href="#refresh">refresh</a><br>
		<a href="#plotmode">plotmode</a><br>
		<a href="#plotsize">plotsize</a><br>
		<a href="#webname">webname</a><br>
		<a href="#redirectCmds">redirectCmds</a><br>
		<a href="#longpoll">longpoll</a><br>
     </ul>
    </li><br>
  </ul>
  <br>
</ul>



=end html
=begin html_DE

<a name="FLOORPLAN"></a>
<h3>FLOORPLAN</h3>
<ul>
  Fügt dem fhem-Menü einen zusätzlichen Menüpunkt "Floorplans" hinzu, dre zu einer Anzeige ohne fhem-Menü, Räume oder device-Listen führt.
  Geräte können an einer festlegbaren Koordinate auf dem Bildschirm angezeigt werden, üblicherweise mit einem anklickbaren icon, das das Ein- oder Aus-Schalten
  des Geräts durch klicken erlaubt. Ein Hintergrundbild kann verwendet werden - z.B. ein Grundriss oder jegliches andere Bild.
  Mit floorplanstyle.css kann die Formatierung angepasst werden.<br>
  Eine Schritt-für-Schritt-Anleitung zur Einrichtung ist verfügbar in
  <a href="http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/fhem-floorplan-installation-guide.pdf?format=raw">Englisch</a> und
  <a href="http://sourceforge.net/p/fhem/code/HEAD/tree/trunk/fhem/docs/fhem-floorplan-installation-guide_de.pdf?format=raw">Deutsch</a>. <br>
  <br>

  <a name="FLOORPLANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FLOORPLAN </code>
    <br><br>

    <b>Hinweis:</b> Speichern Sie Ihr Hintergrundbild mit dem Dateinamen fp_&lt;name&gt;.png in Ihrem icon_ordner (www/images/default , www/pgm2 or FHEM) .<br><br>
    Beispiel:
    <ul>
      <code>
	  define Grundriss FLOORPLAN<br>
	  fp_Grundriss.png
	  </code><br>
    </ul>
  </ul>
  <br>

  <a name="FLOORPLANset"></a>
  <b>Set</b>
  <ul>
      <li>N/A</li>
  </ul>
  <br>

  <a name="FLOORPLANget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; config</code>
    <br>
	Zeigt die Konfiguration des FLOORPLAN <name> incl. allen Attributen an. Kann fuer ein include-file verwendet werden.<br>
  </ul>
  <br>

  <a name="FLOORPLANattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a name="fp_fpname">userattr fp_&lt;name&gt; &lt;top&gt;,&lt;left&gt;[,&lt;style&gt;[,&lt;description&gt;]]</a><br><br>
    A <a href="#userattr">userattr</a> fp_&lt;name&gt; wird automatisch angelegt, sofern es noch nicht existiert.<br>
	<ul>
      <li>top   = Bildschirmposition, pixel vom oberen Bildschirmrand</li>
      <li>left  = Bildschirmposition, pixel vom linken Bildschirmrand</li>
      <li>style =
		<ul>
			<li>0  nur icon/Status</li>
			<li>1  Gerätename und icon/Status</li>
			<li>2  Gerätename, icon/Status und Kommandos</li>
			<li>3  Geräte-reading und optionale Beschreibung</li>
			<li>4  S300TH-spezifisch, zeigt Temperatur und Luftfeuchtigkeit an</li>
			<li>5  icon/Status und Kommandos (ohne Gerätename)</li>
			<li>6  Geräte-reading, Zeitstempel und optionale Beschreibung</li>
		</ul>
	  </li>
      <li>Eine ggf. angegebene Bschreibung wird anstelle des original-Gerätenamens angezeigt.</li>
    </ul></li><br>
    Beispiele:<br>
    <ul>
		<table>
			<tr><td><code>attr lamp1 fp_Erdgeschoss 100,100</code></td><td><code>#display lamp1 with icon only at screenposition 100,100</code></td></tr>
			<tr><td><code>attr lamp2 fp_Erdgeschoss 100,140,1,Art-Deco</code></td><td><code>#display lamp2 with description 'Art-Deco-Light' at 100,140</code></td></tr>
			<tr><td><code>attr lamp2 fp_ErsteEtage  130,100,1</code></td><td><code>#display the same device at different positions on other floorplans</code></td></tr>
			<tr><td><code>attr myFHT fp_Erdgeschoss 300,20,10,Temperature</code></td><td><code>#display given Text + FHT-temperature</code></td></tr>
		</table>
	</ul>
	<b>Hinweis:</b> Die Parameter müssen ohne Leerstellen aneinandergereiht werden.<br><br>


    <li><a name="fp_arrange">fp_arrange</a><br>
  	  Aktiviert den "arrange-Modus" der ein zusätzliches Menü anzeigt,
	  mit dem Geräte auf dem Bildschirm angeordnet werden können. Dabei können die Koordinaten auch durch Platzieren mit der Maus gesetzt werden.<br>
	  Beispiel:
	<ul>
      <code>attr Erdgeschoss fp_arrange 1</code><br>
	  <code>attr Erdgeschoss fp_arrange detail  #Zeigt die Geräte mit den Infos Raum, Typ und Alias</code><br>
	  <code>attr Erdgeschoss fp_arrange WEB     #Aktiviert den arrange-Modus nur für die Webinstanz WEB</code><br><br>
    </ul>
    </li>
    <li><a name="stylesheet">stylesheet</a><br>
	Ermöglicht die Verwendung eines eigenen css-stylesheet für Ihren floorplan. Dieses Attribut hat Vorrang vor dem Standard-stylesheet.
	Das Standard-stylesheet für floorplans ist <code>floorplanstyle.css</code>. Falls <a href="#stylesheetPrefix">stylesheetPrefix</a> in der korrespondierenden FHEMWEB-Instanz gesetzt ist, wird dieser
	<code>stylesheetPrefix</code> auch dem stylesheet für floorplans vorangestellt (prepend).<br>
	Alle stylesheets werden im stylesheet-Ordner des fhem-Dateisystems abgelegt. Legen Sie dort 
	Ihr eigenes stylesheet neben  <code>floorplanstyle.css</code> in demselben Ordner ab.<br>
	Beispiel:
	<ul>
       <code>attr Erdgeschoss stylesheet myfloorplanstyle.css</code><br><br>
    </ul>
    </li>

	<li><a name="fp_default">fp_default</a><br>
	Der floorplan-Startbildschirm wird übersprungen wenn dieses Attribut einem der von Ihnen definierten floorplans zugeordnet ist.
	</li>
    Beispiel:
	<ul>
      <code>attr Erdgeschoss fp_default 1</code><br><br>
    </ul>

	<li><a name="fp_noMenu">fp_noMenu</a><br>
	Blendet das floorplans-Menü aus, das normalerweise am linken Bildschirmrand angezeigt wird.
	</li>
    Beispiel:
	<ul>
      <code>attr Erdgeschoss fp_noMenu 1</code><br><br>
    </ul>

    <li><a name="commandfield">commandfield</a><br>
	 Fügt Ihrem floorplan ein fhem-Kommandofeld hinzu.
	</li>
    Beispiel:
	<ul>
      <code>attr Erdgeschoss commandfield 1</code><br><br>
    </ul>
	
    <li><a name="fp_backgroundimg">fp_backgroundimg</a><br>
	 Gestattet die Bennung eine Hintergundbilds unabhängig vom floorplan-Namen.<br>
     <b>Hinweis:</b> Das Attribut kann mittels notify geändert werden, um z.B. unterschiedliche Hintergundbidlder am Tag oder in der Nacht anzuzeigen.<br>
     Beispiel:
	 <ul>
       <code>attr Erdgeschoss fp_backgroundimg foobar.png</code><br><br>
     </ul>
	</li>
	
    <li><a name="fp_viewport">fp_viewport</a><br>
	Gestattet die Verwendung eines abweichenden viewport-Wertes für die touchpad-Ausgabe.<br>
	Die Default-viewport-Angbe ist "width=768".
	</li>
	
	<a name="fp_roomIcons"></a>
    <li>fp_roomIcons<br>
        Mit Leerstellen getrennte Liste von floorplan:icon -Paaren, um 
        einem Eintrag des floorplan-Menues icons zuzuordnen, genau wie 
		die entsprechende Funktionalitaet in FHEMWEB. Beispiel:<br>
        attr Grundriss fp_roomIcons Grundriss:control_building_empty Media:audio_eq
    </li>

	
    <li><a name="fp_inherited">Vererbt von FHEMWEB</a><br>
	 Die folgenden Attribute werden von der zugrundliegenden <a href="#FHEMWEB">FHEMWEB</a>-Instanz vererbt:<br>
     <ul>
		<a href="#smallscreen">smallscreen</a><br>
		<a href="#touchpad">touchpad</a><br>
		<a href="#refresh">refresh</a><br>
		<a href="#plotmode">plotmode</a><br>
		<a href="#plotsize">plotsize</a><br>
		<a href="#webname">webname</a><br>
		<a href="#redirectCmds">redirectCmds</a><br>
		<a href="#longpoll">longpoll</a><br>
     </ul>
    </li><br>
  </ul>
  <br>
</ul>

=end html_DE

=cut
