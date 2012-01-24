#!/usr/bin/perl

#################################################################################
#  Copyright notice
#
#  (c) 2008-2012
#  Copyright: Dr. Olaf Droegehorn
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
#  This copyright notice MUST APPEAR in all copies of the script!
#################################################################################

#Note: use warnings/-w is deadly on some linux devices (e.g.WL500GX)
use strict;
use warnings;
use POSIX;

use Time::HiRes qw(gettimeofday);


use CGI;
use IO::Socket;

###################
# Config
my $addr       = "localhost:7072";      		# FHZ server
my $absicondir = "/home/httpd/icons";   		# Copy your icons here
my $relicondir = "/icons";
my $gnuplotdir = "/usr/local/FHEM"; 				# the .gplot filees live here (should be the FHEM dir, as FHEMRENDERER needs them there)
my $fhemwebdir = "/home/httpd/cgi-bin";			# the fhemweb.pl & style.css files live here
my $faq				 = "/home/httpd/cgi-bin/faq.html";
my $howto      = "/home/httpd/cgi-bin/HOWTO.html";
my $doc        = "/home/httpd/cgi-bin/commandref.html";
my $tmpfile    = "/tmp/pgm5-";							# the Images will be rendered there with beginning of name
my $configfile = "/etc/fhem.conf";					# the fhem.conf file is that
my $plotmode   = "gnuplot";     						# Current plotmode
my $plotsize	 = "800,200";                 # Size for a plot
my $renderer   = "pgm5_renderer";						# Name of suitable renderer
my $rendrefresh= "00:15:00";								# Refresh Interval for the Renderer
my $render_before = 1;									# Render graphics before drawing
my $render_after = 0;										# Render graphics after drawing

# Nothing to config below
#########################

#########################
# Forward declaration
sub checkDirs();
sub digestCgi();
sub doDetail($);
sub fhemcmd($);
sub fileList($);
sub makeTable($$$$$$$$);
sub parseXmlList($);
sub showRoom();
sub showArchive($);
sub showLog($);
sub showLogWrapper($);
sub roomOverview($);
sub style($$);
sub fatal($);
sub zoomLink($$$$);
sub calcWeblink($$);
sub makeEdit($$$$);


#########################
# Global variables;
my $me = $ENV{SCRIPT_NAME};

my %icons;                    # List of icons
my $iconsread;                # Timestamp of last icondir check
my %rooms;                    # hash of all rooms
my %devs;                     # hash of all devices ant their attributes
my %types;                    # device types, for sorting
my $room;                     # currently selected room
my $detail;                   # durrently selected device for detail view
my $title;                    # Page title
my $cmdret;                   # Returned data by the fhem call
my $scrolledweblinkcount;     # Number of scrolled weblinks
my %pos;                      # scroll position
my $RET;                      # Returned data (html)
my $RETTYPE;                  # image/png or the like
my $SF;                       # Short for submit form
my $ti;                       # Tabindex for all input fields
my @zoom;                     # "qday", "day","week","month","year"
my %zoom;                     # the same as @zoom
my $wname;                    # Web instance name
my $data;                     # Filecontent from browser when editing a file
my $lastxmllist;              # last time xmllist was parsed
my $renderer_status;					# Status of the Renderer

my ($lt, $ltstr);

###############
# Initialize internal structures
my $n = 0;
@zoom = ("qday", "day","week","month","year");
%zoom = map { $_, $n++ } @zoom;

open(FH, "$fhemwebdir/style.css") || fatal("$fhemwebdir/style.css: $!");  # Read in the template Stylesheet file
my $css = join("", <FH>);
close(FH);

$me = "" if(!$me);
my $q = new CGI;
$ti = 1;

##################
# Lets go:
my ($cmd,$debug) = digestCgi();

my $docmd = 0;
$docmd = 1 if($cmd && 
              $cmd !~ /^showlog/ &&
              $cmd !~ /^toweblink/ &&
              $cmd !~ /^showarchive/ &&
              $cmd !~ /^style / &&
              $cmd !~ /^edit/);
              
$cmdret = fhemcmd($cmd) if($docmd); 
                           
parseXmlList($docmd);

if($cmd =~ m/^showlog /) {
  showLog($cmd);
  exit (0);
}


if($cmd =~ m/^toweblink (.*)$/) {
  my @aa = split(":", $1);
  my $max = 0;
  for my $d (keys %devs) {
    $max = ($1+1) if($d =~ m/^wl_(\d+)$/ && $1 >= $max);
  }
  $devs{$aa[0]}{INT}{currentlogfile}{VAL} =~ m,([^/]*)$,;
  $aa[2] = "CURRENT" if($1 eq $aa[2]);
  $cmdret = fhemcmd("define wl_$max weblink fileplot $aa[0]:$aa[1]:$aa[2]");
  if(!$cmdret) {
    $detail = "wl_$max";
    parseXmlList($docmd);
  }
}

print $q->header;
print $q->start_html(-name=>$title, -title=>$title, -style=>{ -code=>$css });

if($cmdret) {
  $detail = "";
  $room = "";
  $cmdret =~ s/</&lt;/g;
  $cmdret =~ s/>/&gt;/g;
  print "<div id=\"right\">\n";
  print "<pre>$cmdret</pre>\n";
  print "</div>\n";
}

roomOverview($cmd);

style($cmd,undef)    if($cmd =~ m/^style /);

doDetail($detail)    if($detail);
showRoom()           if($room && !$detail);
showLogWrapper($cmd) if($cmd =~ /^showlogwrapper/);
showArchive($cmd)    if($cmd =~ m/^showarchive/);
print $q->end_html;
exit(0);


###################
sub
fhemcmd($)
{
  my $p = shift;

  my $server = IO::Socket::INET->new(PeerAddr => $addr);
  if(!$server) {
    print $q->h3("Can't connect to the server on $addr");
    print $q->end_html;
    return 0;
  }
  syswrite($server, "$p; quit\n");
  my ($lst, $buf) = ("", "");
  while(sysread($server, $buf, 2048) > 0) {
    $lst .= $buf;
  }
  close($server);
  return $lst;
}

###########################
# Digest CGI parameters
sub
digestCgi()
{
  my (%arg, %val, %dev);
  my ($cmd, $debug, $c) = ("","","");
  
  foreach my $p ($q->param) {
    my $v = $q->param($p);
    $debug .= "$p : $v<br>\n";

    if($p eq "detail")       { $detail = $v; }
    if($p eq "room")         { $room = $v; }
    if($p eq "cmd")          { $cmd = $v; delete($q->{$p}); }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c= $1; delete($q->{$p}); }
    if($p eq "pos")          { %pos =  split(/[=]/, $v); }
    if($p eq "data")         { $data = $v; }


  }
  $cmd.=" $dev{$c}" if($dev{$c});
  $cmd.=" $arg{$c}" if($arg{$c});
  $cmd.=" $val{$c}" if($val{$c});
  return ($cmd, $debug);
}

#####################
# Get the data and parse it. We are parsing XML in a non-scientific way :-)
sub
parseXmlList($)
{
  my $docmd = shift;
  my $name;
  
  if(!$docmd && $lastxmllist && (time() - $lastxmllist) < 2) {
    $room = $devs{$detail}{ATTR}{room}{VAL} if($detail);
    return;
  }

  $lastxmllist = time();
  %rooms = ();
  %devs = ();
  %types = ();
  $title = "";
  
  foreach my $l (split("\n", fhemcmd("xmllist"))) {

    ####### Device
    if($l =~ m/^\t\t<(.*) name="(.*)" state="(.*)" sets="(.*)" attrs="(.*)">/){
      $name = $2;
      $devs{$name}{type}  = ($1 eq "HMS" ? "KS300" : $1);
      $devs{$name}{state} = $3;
      $devs{$name}{sets}  = $4;
      $devs{$name}{attrs} = $5;
      next;
    }
    ####### INT, ATTR & STATE
    if($l =~ m,^\t\t\t<(.*) key="(.*)" value="([^"]*)"(.*)/>,) {
      my ($t, $n, $v, $m) = ($1, $2, $3, $4);
      #### NEW ######
      $v =~ s,&lt;br&gt;,<br/>,g;
      $devs{$name}{$t}{$n}{VAL} = $v;
      if($m) {
        $m =~ m/measured="(.*)"/;
        $devs{$name}{$t}{$n}{TIM} = $1;
      }

      if($t eq "ATTR" && $n eq "room") {
        $rooms{$v}{$name} = 1;
	if($name eq "global") {
	  $rooms{$v}{LogFile} = 1;
	  $devs{LogFile}{ATTR}{room}{VAL} = $v;
	}
      }

      if($name eq "global" && $n eq "logfile") {
	my $ln = "LogFile";
	$devs{$ln}{type}  = "FileLog";
        $devs{$ln}{INT}{logfile}{VAL} = $v;
        $devs{$ln}{state} = "active";
      }
    }

  }
  if(defined($devs{global}{ATTR}{archivedir})) {
    $devs{LogFile}{ATTR}{archivedir}{VAL} = 
     $devs{global}{ATTR}{archivedir}{VAL};
  }

  #################
  #Tag the gadgets without room with "Unsorted"
  if(%rooms) {
    foreach my $name (keys %devs ) {
      if(!$devs{$name}{ATTR}{room}) {
        $devs{$name}{ATTR}{room}{VAL} = "Unsorted";
        $rooms{Unsorted}{$name} = 1;
      }
    }
  }

  ###############
  # Needed for type sorting
  foreach my $d (sort keys %devs ) {
    $types{$devs{$d}{type}} = 1;
  }
  $title = $devs{global}{ATTR}{title}{VAL} ? 
               $devs{global}{ATTR}{title}{VAL} : "HOME Management";
  $room = $devs{$detail}{ATTR}{room}{VAL} if($detail);
}

##############################
sub
makeTable($$$$$$$$)
{
  my($d,$t,$header,$hash,$clist,$ccmd,$makelink,$cmd) = (@_);

  return if(!$hash && !$clist);

  $t = "EM" if($t =~ m/^EM.*$/);        # EMWZ,EMEM,etc.
  print "  <table class=\"$t\">\n";

  # Header
  print "  <tr>";
  foreach my $h (split(",", $header)) {
    print "<th>$h</th>";
  }
  print "</tr>\n";
  if($clist) {
    print "</tr>\n";
    my @al = map { s/[:;].*//;$_ } split(" ", $clist);
    print "<td>" . $q->popup_menu(-name=>"arg.$ccmd$d", -value=>\@al) . "</td>";
    print "<td>" . $q->textfield(-name=>"val.$ccmd$d",  -size=>6)     . "</td>";
    print "<td>" . $q->submit(-name=>"cmd.$ccmd$d", -value=>$ccmd)    . "</td>";
    print $q->hidden("dev.$ccmd$d", $d);
    print "</td></tr><tr><td>\n";
  }

  my $row = 1;
  foreach my $v (sort keys %{$hash}) {
    printf("    <tr class=\"%s\">", $row?"odd":"even");
    $row = ($row+1)%2;
    if($makelink && $doc) {
      print "<td><a href=\"$doc#$v\">$v</a></td>";
    } else {
      print "<td>$v</td>";
    }
    
    if($v eq "DEF") {
      makeEdit($d, $t, "modify", $hash->{$v}{VAL});
    } else {
      print "<td id=\"show\">$hash->{$v}{VAL}</td>";
    }    
    
    print "<td>$hash->{$v}{TIM}</td>" if($hash->{$v}{TIM});
    print "<td><a href=\"$me?cmd.$d=$cmd $d $v&amp;detail=$d\">$cmd</a></td>"
        if($cmd);

    print "</tr>\n";
  }
  print "  </table>\n";
  print "<br>\n";
  
}

##############################
sub
showArchive($)
{
  my ($arg) = @_;
  my (undef, $d) = split(" ", $arg);

  my $fn = $devs{$d}{INT}{logfile}{VAL};
  if($fn =~ m,^(.+)/([^/]+)$,) {
    $fn = $2;
  }
  $fn = $devs{$d}{ATTR}{archivedir}{VAL} . "/" . $fn;
  my $t = $devs{$d}{type};

  print "<div id=\"right\">\n";
  print "<table><tr><td>\n";
  print "<table class=\"$t\"><tr><td>\n";

  my $row =  0;
  my $l = $devs{$d}{ATTR}{logtype};
  foreach my $f (fileList($fn)) {
    printf("    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even");
    $row = ($row+1)%2;
    if(!defined($l)) {
      print("<td><a href=\"$me?cmd=showlogwrapper $d text $f\">text</a></td>");
    } else {
      foreach my $ln (split(",", $l->{VAL})) {
	my ($lt, $name) = split(":", $ln);
	$name = $lt if(!$name);
	print("<td><a href=\"$me?cmd=showlogwrapper $d $lt $f\">$name</a></td>");
      }
    }
    print "</tr>";
  }

  print "</td></tr></table>\n";
  print "</td></tr></table>\n";
  print "</div>\n";
}


##############################
sub
doDetail($)
{
  my ($d) = @_;

  print $q->start_form;
  print $q->hidden("detail", $d);

  $room = $devs{$d}{ATTR}{room}{VAL} if($devs{$d}{ATTR}{room});

  my $t = $devs{$d}{type};

  print "<div id=\"right\">\n";
  print "<table><tr><td>\n";
  print "<a href=\"$me?cmd=delete $d\">Delete $d</a>\n";
 
  my $pgm = "Javascript:" .
               "s=document.getElementById('edit').style;".
               "if(s.display=='none') s.display='block'; else s.display='none';".
               "s=document.getElementById('disp').style;".
               "if(s.display=='none') s.display='block'; else s.display='none';";
  print "<a href=\"#top\" onClick=\"$pgm\">Modify $d</a>";

 
  print "</td></tr><tr><td>\n";
  makeTable($d, $t, "<a href=\"$doc#${t}set\">State</a>,Value,Measured",
        $devs{$d}{STATE}, $devs{$d}{sets}, "set", 0, undef);
  makeTable($d, $t, "Internal,Value",
        $devs{$d}{INT}, "", undef, 0, undef);
  makeTable($d, $t, "<a href=\"$doc#attr\">Attribute</a>,Value,Action",
        $devs{$d}{ATTR}, $devs{$d}{attrs}, "attr", 1,
        $d eq "global" ? "" : "deleteattr");
  print "</td></tr></table>\n";
  print "</div>\n";

  print $q->end_form;
}

##############
# Room overview
sub
roomOverview($)
{
  my ($cmd) = @_;
  print $q->start_form;

  print "<div id=\"hdr\">\n";

  print "<table><tr><td>"; 
  
  print "<a href=\"$doc\">Cmd</a>: ";
  print $q->textfield(-name=>"cmd", -size=>30);

  $scrolledweblinkcount = 0;
  if($room) {
    print $q->hidden(-name=>"room", -value=>"$room");
    if(!$detail) {    # Global navigation buttons for weblink >= 2
      calcWeblink(undef,undef);
      if($scrolledweblinkcount) {
        print "</td><td>";
        print "&nbsp;&nbsp;";
        zoomLink("zoom=-1", "Zoom-in.png", "zoom in", 0);
        zoomLink("zoom=1",  "Zoom-out.png","zoom out", 0);
        zoomLink("off=-1",  "Prev.png",    "prev", 0);
        zoomLink("off=1",   "Next.png",    "next", 0);
      }
    }
  }
  print "</td></tr></table>";
  print "</div>\n";

  print "<div id=\"left\">\n";
  print "  <table><tr><td>\n";  # Need for "right" compatibility
  print "  <table class=\"room\" summary=\"Room list\">\n";
  $room = "" if(!$room);
  foreach my $r (sort keys %rooms) {
    next if($r eq "hidden");
    printf("    <tr%s>", $r eq $room ? " class=\"sel\"" : "");
    print "<td><a href=\"$me?room=$r\">$r</a>";
    print "</td></tr>\n";
  }

  printf("    <tr%s>",  "all" eq $room ? " class=\"sel\"" : "");
  print "<td><a href=\"$me?room=all\">All together</a></td>";
  print "    </tr>\n";

  print "  </table>\n";
  print "  </td></tr>\n";
  print "  <tr><td>\n";
  print "    <table class=\"room\" summary=\"Help/Configuration\">\n";
  print "      <tr><td><a href=\"$howto\">Howto</a></td></tr>\n";
  print "      <tr><td><a href=\"$faq\">FAQ</a></td></tr>\n";
  print "      <tr><td><a href=\"$doc\">Details</a></td></tr>\n";
  my $sel = ($cmd =~ m/examples/) ? " class=\"sel\"" : "";
  print "      <tr$sel><td><a href=\"$me?cmd=style examples\">Examples</a></td></tr>\n";
  $sel = ($cmd =~ m/list/) ? " class=\"sel\"" : "";
  print "      <tr$sel><td><a href=\"$me?cmd=style list\">Edit files</a></td></tr>\n";
  print "    </table>\n";
  print "  </td></tr>\n";
  print "  </table>\n";
  print "</div>\n";
  print $q->end_form;
}

#################
# Read in the icons
sub
checkDirs()
{
  return if($iconsread && (time() - $iconsread) < 5);
  %icons = ();

  if(opendir(DH, $absicondir)) {
    while(my $l = readdir(DH)) {
      next if($l =~ m/^\./);
      my $x = $l;
      $x =~ s/\.[^.]+$//;	# Cut .gif/.jpg
      $icons{$x} = $l;
    }
    closedir(DH);
  }
  $iconsread = time();
}

########################
# Generate the html output: i.e present the data
sub
showRoom()
{
  checkDirs();
  my $havelookedforrenderer;

  print $q->start_form;
  print "<div id=\"right\">\n";
  print "  <table><tr><td>\n";  # Need for equal width of subtables

  foreach my $type (sort keys %types) {
    
    #################
    # Filter the devices in the room
    if($room && $room ne "all") {
      my $havedev;
      foreach my $d (sort keys %devs ) {
        next if($devs{$d}{type} ne $type);
        next if(!$rooms{$room}{$d});
        $havedev = 1;
        last;
      }
      next if(!$havedev);
    }

    my $rf = ($room ? "&amp;room=$room" : "");


    ############################
    # Print the table headers
    my $t = $type;
    $t = "EM" if($t =~ m/^EM.*$/);
    if (!(($t eq "FS20") || ($t eq "IT") || ($t eq "FHT") || ($t eq "FileLog") || ($t eq "at") || ($t eq "notify") || ($t eq "KS300") || ($t eq "FHZ") || ($t eq "FHEMWEB") || ($t eq "EM") || ($t eq "FHEMRENDERER") || ($t eq "weblink"))) {
 			$t = "_internal_";   
 		}  
    print "  <table class=\"$t\" summary=\"List of $type devices\">\n";

    if($type eq "FS20") {
      print "    <tr><th>FS20 dev.</th><th>State</th>";
      print "<th colspan=\"2\">Set to</th>";
      print "</tr>\n";
    }
    if($type eq "IT") {
      print "    <tr><th>IT dev.</th><th>State</th>";
      print "<th colspan=\"2\">Set to</th>";
      print "</tr>\n";
    }
    if($type eq "FHT") {
      print "    <tr><th>FHT dev.</th><th>Measured</th>";
      print "<th>Set to</th>";
      print "</tr>\n";
    }

    my $hstart = "    <tr><th>";
    my $hend   = "</th></tr>\n";
    print $hstart . "Logs" . $hend                       if($type eq "FileLog");
    print $hstart . "HMS/KS300</th><th>Readings" . $hend if($type eq "KS300");
    print $hstart . "Scheduled commands (at)" . $hend    if($type eq "at");
    print $hstart . "Triggers (notify)" . $hend          if($type eq "notify");
    print $hstart . "Global variables" . $hend        if($type eq "_internal_");

    my $row=1;
    foreach my $d (sort keys %devs ) {

      next if($devs{$d}{type} ne $type);
      next if($room && $room ne "all" && !$rooms{$room}{$d});

      printf("    <tr class=\"%s\">", $row?"odd":"even");
      $row = ($row+1)%2;

      #####################
      # Check if the icon exists

      my $v = $devs{$d}{state};

      if(($type eq "FS20") || ($type eq "IT")) {

        my $v = $devs{$d}{state};
        my $iv = $v;
        my $iname = "";

        if(defined($devs{$d}) &&
           defined($devs{$d}{ATTR}{showtime})) {
          $v = $devs{$d}{STATE}{state}{TIM};
        } elsif($iv) {
          $iv =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"
          $iname = $icons{"$type"}     if($icons{"$type"});
          $iname = $icons{"$type.$iv"} if($icons{"$type.$iv"});
          $iname = $icons{"$d"}        if($icons{"$d"});
          $iname = $icons{"$d.$iv"}    if($icons{"$d.$iv"});
        }
        $v = "" if(!defined($v));

        print "<td><a href=\"$me?detail=$d\">$d</a></td>";
        if($iname) {
          print "<td align=\"center\"><img src=\"$relicondir/$iname\" " .
                  "alt=\"$v\"/></td>";
        } else {
          print "<td align=\"center\">$v</td>";
        }
        if($devs{$d}{sets}) {
          print "<td><a href=\"$me?cmd.$d=set $d on$rf\">on</a></td>";
          print "<td><a href=\"$me?cmd.$d=set $d off$rf\">off</a></td>";
        }

      } elsif($type eq "FHT") {

        $v = $devs{$d}{STATE}{"measured-temp"}{VAL};
        $v = "" if(!defined($v));

        $v =~ s/ .*//;
        print "<td><a href=\"$me?detail=$d\">$d</a></td>";
        print "<td align=\"center\">$v&deg;</td>";

        $v = sprintf("%2.1f", int(2*$v)/2) if($v =~ m/[0-9.-]/);
        my @tv = map { ($_.".0", $_+0.5) } (16..26);
        $v = int($v*20)/$v if($v =~ m/^[0-9].$/);
        print $q->hidden("arg.$d", "desired-temp");
        print $q->hidden("dev.$d", $d);
        print "<td align=\"center\">" .
            $q->popup_menu(-name=>"val.$d", -values=>\@tv, -default=>$v) .
            $q->submit(-name=>"cmd.$d", -value=>"set") . "</td>";

      } elsif($type eq "FileLog") {
        print "<td><a href=\"$me?detail=$d\">$d</a></td><td>$v</td>\n";
        if($devs{$d}{ATTR}{archivedir}) {
          print("<td><a href=\"$me?cmd=showarchive $d\">archive</a></td>");
        }
        my $l = $devs{$d}{ATTR}{logtype};
        if(!defined($l)) {
	  			my %h = ("VAL" => "text");
	  			$l = \%h;
				}

				foreach my $f (fileList($devs{$d}{INT}{logfile}{VAL})) {
	  			printf("    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even");
	  			$row = ($row+1)%2;
	  			foreach my $ln (split(",", $l->{VAL})) {
		    		my ($lt, $name) = split(":", $ln);
	    			$name = $lt if(!$name);
	    			print("<td><a href=\"$me?cmd=showlogwrapper $d $lt $f\">$name</a></td>");
	  			}
	  			print "</tr>";
				}

      } elsif($type eq "weblink" && $room ne "all") {
        $v = $devs{$d}{INT}{LINK}{VAL};
        $t = $devs{$d}{INT}{WLTYPE}{VAL};
        if($t eq "link") {
          print "<td><a href=\"$v\">$d</a></td>\n";
        } elsif($t eq "fileplot") {
          my @va = split(":", $v, 3);
          if(@va != 3 || !$devs{$va[0]}{INT}{currentlogfile}) {
	    			print("<td>Broken definition: $v</a></td>");
          } else {
            if($va[2] eq "CURRENT") {
              $devs{$va[0]}{INT}{currentlogfile}{VAL} =~ m,([^/]*)$,;
              $va[2] = $1;
            }
            
					  ###################
					  # Search for fitting renderer
					  if (!$havelookedforrenderer) {
							my $haverend;
						  foreach my $rend (sort keys %devs ) {
					 			next if($rend ne $renderer);
								$haverend = 1;
								last;
							}
							$havelookedforrenderer = 1;
							if (!$haverend) {
							 	fhemcmd ("define $renderer FHEMRENDERER");
						 		fhemcmd ("attr $renderer plotmode $plotmode");
						 		fhemcmd ("attr $renderer plotsize $plotsize");
						 		fhemcmd ("attr $renderer refresh $rendrefresh");
						 		fhemcmd ("attr $renderer tmpfile $tmpfile");
						 		fhemcmd ("get $renderer");
							}  else {
								$renderer_status = fhemcmd ("{\$attr{" . $renderer . "}{status} }");
  							if (($renderer_status =~ m/off/) && ($render_before)) {
									fhemcmd ("get $renderer");
  							}								
							}
						}						
            print "<td>";

            my $wl = "&amp;pos=" . join("=", map {"$_=$pos{$_}"} keys %pos);

            my $arg="$me?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
            if($plotmode eq "SVG") {
              my ($w, $h) = split(",", $plotsize);
              print "<embed src=\"$arg\" type=\"image/svg+xml\"" .
                    " width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
            } else {
              print "<img src=\"$arg\"/>\n";
            }

            print "</td><td>";
            print "<a href=\"$me?detail=$d\">$d</a></td>";
            print "</td></tr>";
          }
        }

      } else {
        print "<td><a href=\"$me?detail=$d\">$d</a></td><td>$v</td>\n";
      }
    }
    if (($havelookedforrenderer) && ($renderer_status =~ m/off/) && ($render_after)) {
			fhemcmd ("define render_after at +00:01:30 get $renderer");
  	}
    print "  </table>\n";
    print "  <br>\n"; # Empty line
  }
  print "  </td></tr>\n</table>\n";
  print "</div>\n";
  print $q->end_form;
}

#################
sub
fileList($)
{
  my ($fname) = @_;
  $fname =~ m,^(.*)/([^/]*)$,; # Split into dir and file
  my ($dir,$re) = ($1, $2);
  return if(!$re);
  $re =~ s/%./\.*/g;
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$,);
    push(@ret, $f);
  }
  closedir(DH);
  return sort @ret;
}

######################
sub
showLogWrapper($)
{
  my ($cmd) = @_;
  my (undef, $d, $type, $file) = split(" ", $cmd, 4);
  my $havelookedforrenderer;

  if($type eq "text") {
    $devs{$d}{INT}{logfile}{VAL} =~ m,^(.*)/([^/]*)$,; # Split into dir and file
    my $path = "$1/$file";
    $path = $devs{$d}{ATTR}{archivedir}{VAL} . "/$file" if(!-f $path);

    open(FH, $path) || fatal("$path: $!"); 
    my $cnt = join("", <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;

    print "<div id=\"right\">\n";
    print "<pre>$cnt</pre>\n";
    print "</div>\n";

  } else {

	  ###################
	  # Search for fitting renderer
	  if (!$havelookedforrenderer) {
			my $havedev;
		  foreach my $d (sort keys %devs ) {
	 			next if($d ne $renderer);
				$havedev = 1;
				last;
			}
			$havelookedforrenderer = 1;
			if (!$havedev) {
			 	fhemcmd ("define $renderer FHEMRENDERER");
		 		fhemcmd ("attr $renderer plotmode $plotmode");
		 		fhemcmd ("attr $renderer plotsize $plotsize");
		 		fhemcmd ("attr $renderer refresh $rendrefresh");
		 		fhemcmd ("attr $renderer tmpfile $tmpfile");
		 		fhemcmd ("get $renderer");
			} else {
				$renderer_status = fhemcmd ("{\$attr{" . $renderer . "}{status} }");
			}
			
		}
    print "<div id=\"right\">\n";
    print "<table><tr></td>\n";
    print "<table><tr></td>\n";

    print "<td>";
    my $arg = "$me?cmd=showlog undef $d $type $file";
    if($plotmode eq "SVG") {
      my ($w, $h) = split(",", $plotsize);
      print "<embed src=\"$arg\" type=\"image/svg+xml\"" .
                    "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
    } else {
      print "<img src=\"$arg\"/>\n";
    }

    print "<a href=\"$me?cmd=toweblink $d:$type:$file\"><br>Convert to weblink</a></td>";
    print "</td></tr></table>\n";
    print "</td></tr></table>\n";
    print "</div>\n";
  }
}

######################
sub
showLog($)
{
  my ($cmd) = @_;
  my (undef, $wl, $d, $type, $file) = split(" ", $cmd, 5);

  my $arguments = "pos=" . join("&", map {"$_=$pos{$_}"} keys %pos);

  if (($wl eq "undef") || ($pos{off}) || ($pos{zoom})) {
  	if ($wl eq "undef") {
  		fhemcmd ("get $renderer $d $type $file $arguments");
  	} else {
  		if (!$arguments) {
  			fhemcmd ("get $renderer $wl $d $type $file");
  		} else {
  			fhemcmd ("get $renderer $wl $d $type $file $arguments");
  		}
  	}
  } 

  print $q->header(-type=>"image/png");

	if ($wl eq "undef") {
		open (FH, "$tmpfile$file.png");							# read in the result and send it
	  print join("", <FH>);
	  close(FH);
		unlink ("$tmpfile$file.png");
	} else {
	  open(FH, "$tmpfile$wl.png");                 # read in the result and send it
	  print join("", <FH>);
	  close(FH);
  }

  exit(0);
}

##################
sub
fatal($)
{
  my ($msg) = @_;
  print $q->header;
  print $q->start_html();
  print($msg);
  print $q->end_html;
  exit(0);
}

##################
# Multiline (for some types of widgets) editor with submit 
sub
makeEdit($$$$)
{
  my ($name, $type, $cmd, $val) = @_;

  print "<td>";
  print   "<div id=\"edit\" style=\"display:none\"><form>";
  my $eval = $val;
  $eval =~ s,<br/>,\n,g;

  if($type eq "at" || $type eq "notify") {
    print     "<textarea name=\"val.${cmd}$name\" cols=\"60\" rows=\"10\" ".
            "tabindex=\"$ti\">$eval</textarea>";
  } else {
    print     "<input type=\"text\" name=\"val.${cmd}$name\" size=\"40\" ".
            "tabindex=\"$ti\" value=\"$eval\"/>";
  }
  $ti++;
  print     "<br/>" . $q->submit(-name=>"cmd.${cmd}$name", -value=>"$cmd $name");
  
  print   "</form></div>";
  $eval = "<pre>$eval</pre>" if($eval =~ m/\n/);
  print   "<div id=\"disp\">$eval</div>";
  print  "</td>";
}

##################
# Generate the zoom and scroll images with links if appropriate
sub
zoomLink($$$$)
{
  my ($cmd, $img, $alt, $br) = @_;

  my ($d,$off) = split("=", $cmd, 2);

  return if($plotmode eq "gnuplot");                    # No scrolling
  return if($devs{$d} && $devs{$d}{ATTR}{fixedrange});
  return if($devs{$d} && $devs{$d}{ATTR}{noscroll});

  my $val = $pos{$d};

  $cmd = "room=$room&amp;pos=";
  if($d eq "zoom") {

    $val = "day" if(!$val);
    $val = $zoom{$val};
    return if(!defined($val) || $val+$off < 0 || $val+$off >= int(@zoom) );
    $val = $zoom[$val+$off];
    return if(!$val);

    # Approximation of the next offset.
    my $w_off = $pos{off};
    $w_off = 0 if(!$w_off);
    if($val eq "qday") {
      $w_off =              $w_off*4;
    } elsif($val eq "day") {
      $w_off = ($off < 0) ? $w_off*7 : int($w_off/4);
    } elsif($val eq "week") {
      $w_off = ($off < 0) ? $w_off*4 : int($w_off/7);
    } elsif($val eq "month") {
      $w_off = ($off < 0) ? $w_off*12: int($w_off/4);
    } elsif($val eq "year") {
      $w_off =                         int($w_off/12);
    }
    $cmd .= "zoom=$val=off=$w_off";

  } else {

    return if((!$val && $off > 0) || ($val && $val+$off > 0)); # no future
    $off=($val ? $val+$off : $off);
    my $zoom=$pos{zoom};
    $zoom = 0 if(!$zoom);
    $cmd .= "zoom=$zoom=off=$off";

  }

  print "<a href=\"$me?$cmd\">";
  print "<img style=\"border-color:transparent\" alt=\"$alt\" ".
                "src=\"$relicondir/$img\"/></a>";
  print "<br/>" if($br);
}

##################
# Calculate either the number of scrollable weblinks (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
calcWeblink($$)
{
  my ($d,$wl) = @_;

  return if($plotmode eq "gnuplot");
  my $now = time();

  my $zoom = $pos{zoom};
  $zoom = "day" if(!$zoom);

  if(!$d) {
    foreach my $d (sort keys %devs ) {
      next if($devs{$d}{type} ne "weblink");
      next if(!$room || ($room ne "all" && !$rooms{$room}{$d}));
      next if($devs{$d}{ATTR} && $devs{$d}{ATTR}{noscroll});
      next if($devs{$d}{ATTR} && $devs{$d}{ATTR}{fixedrange});
      $scrolledweblinkcount++;
    }
    return;
  }

  return if(!$devs{$wl});
  return if($devs{$wl} && $devs{$wl}{ATTR}{noscroll});

  if($devs{$wl} && $devs{$wl}{ATTR}{fixedrange}) {
    my @range = split(" ", $devs{$wl}{ATTR}{fixedrange}{VAL});
    $devs{$d}{from} = $range[0];
    $devs{$d}{to}   = $range[1];
    return;
  }

  my $off = $pos{$d};
  $off = 0 if(!$off);
  $off += $pos{off} if($pos{off});

  if($zoom eq "qday") {

    my $t = $now + $off*21600;
    my @l = localtime($t);
    $l[2] = int($l[2]/6)*6;
    $devs{$d}{from}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]);
    $devs{$d}{to}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]+6);

  } elsif($zoom eq "day") {

    my $t = $now + $off*86400;
    my @l = localtime($t);
    $devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);
    $devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]+1);

  } elsif($zoom eq "week") {

    my @l = localtime($now);
    my $t = $now - ($l[6]*86400) + ($off*86400)*7;
    @l = localtime($t);
    $devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

    @l = localtime($t+7*86400);
    $devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);


  } elsif($zoom eq "month") {

    my @l = localtime($now);
    while($off < -12) {
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $devs{$d}{from} = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $devs{$d}{to}   = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

  } elsif($zoom eq "year") {

    my @l = localtime($now);
    $l[5] += $off;
    $devs{$d}{from} = sprintf("%04d", $l[5]+1900);
    $devs{$d}{to}   = sprintf("%04d", $l[5]+1901);

  }
}

##################
# List/Edit/Save css and gnuplot files
sub
style($$)
{
  my ($cmd, $msg) = @_;
  my @a = split(" ", $cmd);

  if($a[1] eq "list") {

    my @fl;
    push(@fl, "fhem.cfg");
    push(@fl, "<br>");
    push(@fl, fileList("$fhemwebdir/.*.css"));
    push(@fl, "<br>");
    push(@fl, fileList("$gnuplotdir/.*.gplot"));
    push(@fl, "<br>");
    push(@fl, fileList("$fhemwebdir/.*html"));

    print "<div id=\"right\">\n";
    print "  <table><tr><td>\n";
    print "  $msg<br/><br/>\n" if($msg);
    print "  <table class=\"at\">\n";
    my $row = 0;
    foreach my $file (@fl) {
      print "<tr class=\"" . ($row?"odd":"even") . "\">";
      print "<td><a href=\"$me?cmd=style edit $file\">$file</a></td></tr>";
      $row = ($row+1)%2;
    }
    print "  </table>\n";
    print "  </td></tr></table>\n";
    print "</div>\n";

  } elsif($a[1] eq "examples") {

    my @fl = fileList("$fhemwebdir/example.*");
    print "<div id=\"right\">\n";
    print "  <table><tr><td>\n";
    print "  $msg<br/><br/>\n" if($msg);
    print "  <table class=\"at\">\n";
    my $row = 0;
    foreach my $file (@fl) {
      print "<tr class=\"" . ($row?"odd":"even") . "\">";
      print "<td><a href=\"$me/$file\">$file</a></td></tr>";
      $row = ($row+1)%2;
    }
    print "  </table>\n";
    print "  </td></tr></table>\n";
    print "</div>\n";

  } elsif($a[1] eq "edit") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $configfile :
                                   "$fhemwebdir/$a[2]");
    if(!open(FH, $f)) {
      print "$f: $!";
      return;
    }
    my $data = join("", <FH>);
    close(FH);

    print "<div id=\"right\">\n";
    print "  <form>";
    
    print $q->submit(-name=>"save", -value=>"Save $f") . "<br/><br/>";

    print $q->hidden("cmd", "style save $a[2]");
    print "<textarea name=\"data\" cols=\"80\" rows=\"30\">" .
                "$data</textarea>";
    print "</form>";
    print "</div>\n";

  } elsif($a[1] eq "save") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $configfile :
                                   "$fhemwebdir/$a[2]");
    if(!open(FH, ">$f")) {
      print "$f: $!";
      return;
    }
    print FH $data;
    close(FH);
    style("style list", "Saved file $f");
    $f = ($a[2] eq "fhem.cfg" ? $configfile : $a[2]);

    fhemcmd("rereadcfg") if($a[2] eq "fhem.cfg");
  }

}

1;
