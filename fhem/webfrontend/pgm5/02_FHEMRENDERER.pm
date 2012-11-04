#################################################################################
#  Copyright notice
#
#  (c) 2008-2012
#  Copyright: Dr. Olaf Droegehorn
#  o.droegehorn@dhs-computertechnik.de
#  www.dhs-computertechnik.de
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

package main;

use strict;
use warnings;

use IO::Socket;


###################
# Config
use vars qw($__ME);
my $FHEMRENDERERdir = "$attr{global}{modpath}/FHEM";    # 

use vars qw(%defs);
use vars qw(%attr);

# Nothing to config below
#########################

#########################
# Forward declaration

sub FHEMRENDERER_getAttr($$);
sub FHEMRENDERER_setAttr($$);
sub FHEMRENDERER_parseXmlList($);
sub FHEMRENDERER_render($);
sub FHEMRENDERER_fatal($);
sub FHEMRENDERER_pF($@);
sub FHEMRENDERER_pO(@);
#sub FHEMRENDERER_zoomLink($$$$);
sub FHEMRENDERER_calcWeblink($$);

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
my %__icons;                    # List of icons
my $__iconsread;                # Timestamp of last icondir check
my %__rooms;                    # hash of all rooms
my %__devs;                     # hash of all devices ant their attributes
my %__types;                    # device types, for sorting
my $__room;                     # currently selected room
my $__detail;                   # durrently selected device for detail view
my $__title;                    # Page title
my $__cmdret;                   # Returned data by the fhem call
my $__scrolledweblinkcount;     # Number of scrolled weblinks
my %__pos;                      # scroll position
my $__RET;                      # Returned data (html)
my $__RETTYPE;                  # image/png or the like
my $__SF;                       # Short for submit form
my $__ti;                       # Tabindex for all input fields
my @__zoom;                     # "qday", "day","week","month","year"
my %__zoom;                     # the same as @__zoom
my $__wname;                    # instance name
my $__plotmode;					        # Current plotmode
my $__plotsize;                 # Size for a plot
my $__timeinterval;				      # Time-Intervall for Renderer
my $__data;                     # Filecontent from browser when editing a file
my $__svgloaded;                # Do not load the SVG twice
my $__lastxmllist;              # last time xmllist was parsed
my $FHEMRENDERER_tmpfile;       # TempDir & File for the rendered graphics
my $__mp;

#####################################
sub
FHEMRENDERER_Initialize($)
{
  my ($hash) = @_;

#  $hash->{ReadFn}  = "FHEMRENDERER_Read";
  $hash->{DefFn}   = "FHEMRENDERER_Define";
  $hash->{UndefFn} = "FHEMRENDERER_Undef";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 plotmode:gnuplot,gnuplot-scroll plotsize refresh tmpfile status multiprocess";
  $hash->{SetFn}   = "FHEMRENDERER_Set";
  $hash->{GetFn}   = "FHEMRENDERER_Get";
}

#####################################
sub
FHEMRENDERER_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMRENDERER [global]"
        if($global && $global ne "global");

  $hash->{STATE} = "Initialized";
  Log(2, "FHEMRENDERER defined");
  
  ###############
  # Initialize internal structures
  my $n = 0;
  @__zoom = ("qday", "day","week","month","year");
  %__zoom = map { $_, $n++ } @__zoom;
  $__wname = $hash->{NAME};

  $__timeinterval = FHEMRENDERER_getAttr("refresh", "00:10:00");
  $__plotmode = FHEMRENDERER_getAttr("plotmode", "gnuplot");
  $__plotsize = FHEMRENDERER_getAttr("plotsize", "800,200");
  $__mp = FHEMRENDERER_getAttr("multiprocess", "off");
  $FHEMRENDERER_tmpfile = FHEMRENDERER_getAttr("tmpfile", "/tmp/");
  FHEMRENDERER_setAttr("status", "off");
  
  return undef;
}

#####################################
sub
FHEMRENDERER_Undef($$)
{
  my ($hash, $arg) = @_;
  return undef;
}


###################################
sub
FHEMRENDERER_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);
  $__wname = $hash->{NAME};
  
  return "no set value specified" if($na < 2 || $na > 3);
  
#  if($__plotmode eq "SVG" && !$modules{SVG}{LOADED}) {
#    my $ret = CommandReload(undef, "98_SVG");
#    Log 0, $ret if($ret);
#  }

  if($a[1] eq "on") {
	  $__timeinterval = FHEMRENDERER_getAttr("refresh", "00:10:00");
	  CommandDefine(undef, $hash->{NAME} . "_trigger at +*$__timeinterval get $a[0]");
	  FHEMRENDERER_setAttr("status", "on");
	} elsif($a[1] eq "off") {
		CommandDelete(undef, $__wname . "_trigger");
		FHEMRENDERER_setAttr("status", "off");
	}
  
  return $ret;
}


#####################################
sub
FHEMRENDERER_Get($@)
{
  my ($hash, @a) = @_;

  my $ret = undef;
  my $v;
  my $t;
  my $pid;
  
	FHEMRENDERER_parseXmlList(0);

  $__wname = "";
  $__wname = $hash->{NAME};
  
  $__plotmode = FHEMRENDERER_getAttr("plotmode", "gnuplot");
  $__plotsize = FHEMRENDERER_getAttr("plotsize", "800,200");
  $FHEMRENDERER_tmpfile = FHEMRENDERER_getAttr("tmpfile", "/tmp/");
  $__mp = FHEMRENDERER_getAttr("multiprocess", "off");
  
   if (@a <= 2) {
  	if (@a == 2) {
  		my ($p,$v) = split("=",$a[1], 2);

     	# Multiline: escape the NL for fhem
     	$v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
   	  Log(2, "P: $p, V: $v");

   	  if($p eq "pos") {
       	%__pos =  split(/[=&]/, $v);
      }
    }

	  if ($__mp ne "off") {
	  	$pid = fork();
	  	if (not defined $pid) {
	  		return ("ERROR: No MultiProcessing possible");
	  	}
	  	if ($pid > 0) {
	  		return $ret;
	  	}
  	}

    foreach my $type (sort keys %__types) {
	  	if($type eq "weblink") {
      	foreach my $d (sort keys %__devs ) {
		  	  next if($__devs{$d}{type} ne $type);

          $v = $__devs{$d}{INT}{LINK}{VAL};  
          $t = $__devs{$d}{INT}{WLTYPE}{VAL};
          if($t eq "fileplot") {
            my @va = split(":", $v, 3);
            if(@va != 3 || !$__devs{$va[0]}{INT}{currentlogfile}) {
		  			    FHEMRENDERER_pO "<td>Broken definition: $v</a></td>";
            } else {
              if($va[2] eq "CURRENT") {
                $__devs{$va[0]}{INT}{currentlogfile}{VAL} =~ m,([^/]*)$,;
                $va[2] = $1;
              }      
    					FHEMRENDERER_render ("undef $d $va[0] $va[1] $va[2]");
    				}
    			}
  	  	}
  	  }
    }

  } elsif (@a == 4 ) {
			FHEMRENDERER_render ("undef $a[3] $a[1] $a[2] $a[3]"); 

  } elsif (@a == 5 ) {
			my ($p,$v) = split("=",$a[4], 2);

      # Multiline: escape the NL for fhem
      $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
      Log(2, "P: $p, V: $v");

      if($p eq "pos") {
      	%__pos =  split(/[=&]/, $v);
  			FHEMRENDERER_render ("undef $a[3] $a[1] $a[2] $a[3]"); 

		  } else {
			  FHEMRENDERER_render ("undef $a[1] $a[2] $a[3] $a[4]"); 
			}

  } elsif (@a == 6 ) {
			my ($p,$v) = split("=",$a[5], 2);

      # Multiline: escape the NL for fhem
      $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
      Log(2, "P: $p, V: $v");

      if($p eq "pos") {
      	%__pos =  split(/[=&]/, $v);
  			FHEMRENDERER_render ("undef $a[1] $a[2] $a[3] $a[4]"); 

		  } else {
  	    return "\"get FHEMRENDERER\" needs either none, 1(pos) or 3-5 arguments ([file-name] device type logfile [pos=zoom=XX&off=YYY])";
			}
  } else {
  	return "\"get FHEMRENDERER\" needs either none, 1(pos) or 3-5 arguments ([file-name] device type logfile [pos=zoom=XX&off=YYY])";
  }
 	if (not defined $pid) {
		return $ret;
	} else {
		exit(0);
	}
}

#####################
# Get the data and parse it. We are parsing XML in a non-scientific way :-)
sub
FHEMRENDERER_parseXmlList($)
{
  my $docmd = shift;
  my $name;

  if(!$docmd && $__lastxmllist && (time() - $__lastxmllist) < 2) {
    $__room = $__devs{$__detail}{ATTR}{room}{VAL} if($__detail);
    return;
  }

  $__lastxmllist = time();
  %__rooms = ();
  %__devs = ();
  %__types = ();
  $__title = "";

  foreach my $l (split("\n", FHEMRENDERER_fC("xmllist"))) {

    ####### Device
    if($l =~ m/^\t\t<(.*) name="(.*)" state="(.*)" sets="(.*)" attrs="(.*)">/){
      $name = $2;
      $__devs{$name}{type}  = ($1 eq "HMS" ? "KS300" : $1);
      $__devs{$name}{state} = $3;
      $__devs{$name}{sets}  = $4;
      $__devs{$name}{attrs} = $5;
      next;
    }
    ####### INT, ATTR & STATE
    if($l =~ m,^\t\t\t<(.*) key="(.*)" value="([^"]*)"(.*)/>,) {
      my ($t, $n, $v, $m) = ($1, $2, $3, $4);
      $v =~ s,&lt;br&gt;,<br/>,g;
      $__devs{$name}{$t}{$n}{VAL} = $v;
      if($m) {
        $m =~ m/measured="(.*)"/;
        $__devs{$name}{$t}{$n}{TIM} = $1;
      }

      if($t eq "ATTR" && $n eq "room") {
        $__rooms{$v}{$name} = 1;
	if($name eq "global") {
	  $__rooms{$v}{LogFile} = 1;
	  $__devs{LogFile}{ATTR}{room}{VAL} = $v;
	}
      }

      if($name eq "global" && $n eq "logfile") {
	my $ln = "LogFile";
	$__devs{$ln}{type}  = "FileLog";
        $__devs{$ln}{INT}{logfile}{VAL} = $v;
        $__devs{$ln}{state} = "active";
      }
    }

  }
  if(defined($__devs{global}{ATTR}{archivedir})) {
    $__devs{LogFile}{ATTR}{archivedir}{VAL} = 
     $__devs{global}{ATTR}{archivedir}{VAL};
  }

  #################
  #Tag the gadgets without room with "Unsorted"
  if(%__rooms) {
    foreach my $name (keys %__devs ) {
      if(!$__devs{$name}{ATTR}{room}) {
        $__devs{$name}{ATTR}{room}{VAL} = "Unsorted";
        $__rooms{Unsorted}{$name} = 1;
      }
    }
  }

  ###############
  # Needed for type sorting
  foreach my $d (sort keys %__devs ) {
    $__types{$__devs{$d}{type}} = 1;
  }
  $__title = $__devs{global}{ATTR}{title}{VAL} ? 
               $__devs{global}{ATTR}{title}{VAL} : "First page";
  $__room = $__devs{$__detail}{ATTR}{room}{VAL} if($__detail);
}


######################
# Generate an image from the log via gnuplot
sub
FHEMRENDERER_render($)
{
  my ($cmd) = @_;
  my (undef, $wl, $d, $type, $file) = split(" ", $cmd, 5);

  my $gplot_pgm = "$FHEMRENDERERdir/$type.gplot";
  return FHEMRENDERER_fatal("Cannot read $gplot_pgm") if(!-r $gplot_pgm);
  FHEMRENDERER_calcWeblink($d,$wl);
 
  if($__plotmode =~ m/gnuplot/) {
    if($__plotmode eq "gnuplot" || !$__devs{$d}{from}) {

      # Looking for the logfile....

      $__devs{$d}{INT}{logfile}{VAL} =~ m,^(.*)/([^/]*)$,; # Dir and File
      my $path = "$1/$file";
      $path = $__devs{$d}{ATTR}{archivedir}{VAL} . "/$file" if(!-f $path);
      return FHEMRENDERER_fatal("Cannot read $path") if(!-r $path);

      open(FH, $gplot_pgm) || return FHEMRENDERER_fatal("$gplot_pgm: $!"); 
      my $gplot_script = join("", <FH>);
      close(FH);

      $gplot_script =~ s/<OUT>/$FHEMRENDERER_tmpfile$wl/g;
      $gplot_script =~ s/<SIZE>/$__plotsize/g;
      $gplot_script =~ s/<IN>/$path/g;
      $gplot_script =~ s/<TL>/$file/g;

      if($__devs{$wl} && $__devs{$wl}{ATTR}{fixedrange}) {
        my $fr = $__devs{$wl}{ATTR}{fixedrange}{VAL};
        $fr =~ s/ /\":\"/;
        $fr = "set xrange [\"$fr\"]\n";
        $gplot_script =~ s/(set timefmt ".*")/$1\n$fr/;
      }

      open(FH, "|gnuplot > /dev/null");# feed it to gnuplot
      print FH $gplot_script;
      close(FH);

    } elsif($__plotmode eq "gnuplot-scroll") {

      ############################
      # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
      # the plot directive with our own, as we offer a file for each line

      my (@filelog, @data, $plot);
      open(FH, $gplot_pgm) || return FHEMRENDERER_fatal("$gplot_pgm: $!"); 
      while(my $l = <FH>) {
        if($l =~ m/^#FileLog (.*)$/) {
          push(@filelog, $1);
        } elsif($l =~ "^plot" || $plot) {
          $plot .= $l;
        } else {
          push(@data, $l);
        }
      }
      close(FH);

      my $gplot_script = join("", @data);
      $gplot_script =~ s/<OUT>/$FHEMRENDERER_tmpfile$wl/g;
      $gplot_script =~ s/<SIZE>/$__plotsize/g;
      $gplot_script =~ s/<TL>/$file/g;

      my ($f,$t)=($__devs{$d}{from}, $__devs{$d}{to});

      my @path = split(" ", FHEMRENDERER_fC("get $d $file $FHEMRENDERER_tmpfile$wl $f $t " .
                                  join(" ", @filelog)));
      my $i = 0;
      $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
      my $xrange = "set xrange [\"$f\":\"$t\"]\n";
      foreach my $p (@path) {   # If the file is empty, write a 0 line
        next if(!-z $p);
        open(FH, ">$p");
        print FH "$f 0\n";
        close(FH);
      }

      open(FH, "|gnuplot > /dev/null");# feed it to gnuplot
      print FH $gplot_script, $xrange, $plot;
      close(FH);
      foreach my $p (@path) {
        unlink($p);
      }
    }

  } #elsif($__plotmode eq "SVG") {

#    my (@filelog, @data, $plot);
#    open(FH, $gplot_pgm) || return FHEMRENDERER_fatal("$gplot_pgm: $!"); 
#    while(my $l = <FH>) {
#      if($l =~ m/^#FileLog (.*)$/) {
#        push(@filelog, $1);
#      } elsif($l =~ "^plot" || $plot) {
#        $plot .= $l;
#      } else {
#        push(@data, $l);
#      }
#    }
#    close(FH);
#    my ($f,$t)=($__devs{$d}{from}, $__devs{$d}{to});
#    $f = 0 if(!$f);     # From the beginning of time...
#    $t = 9 if(!$t);     # till the end
#
#    my $ret = FHEMRENDERER_fC("get $d $file INT $f $t " . join(" ", @filelog));
#    SVG_render($file, $__plotsize, $f, $t, \@data, $internal_data, $plot);
#
#		open (FH, ">$FHEMRENDERER_tmpfile$wl.svg");
#		print FH $__RET;
#		close (FH);
#  }
}



##################
sub
FHEMRENDERER_fatal($)
{
  my ($msg) = @_;
  FHEMRENDERER_pO "<html><body>$msg</body></html>";
}

##################
# print formatted
sub
FHEMRENDERER_pF($@)
{
  my $fmt = shift;
  $__RET .= sprintf $fmt, @_;
}

##################
# print output
sub
FHEMRENDERER_pO(@)
{
  $__RET .= shift;
}

##################
# fhem command
sub
FHEMRENDERER_fC($)
{
  my ($cmd) = @_;
  #Log 0, "Calling $cmd";
  my $oll = $attr{global}{verbose};
  $attr{global}{verbose} = 0 if($cmd ne "save");
  my $ret = AnalyzeCommand(undef, $cmd);
  $attr{global}{verbose} = $oll if($cmd !~ m/attr.*global.*verbose/);
  return $ret;
}

##################
sub
FHEMRENDERER_getAttr($$)
{
  my ($aname, $def) = @_;
  if($attr{$__wname} && defined($attr{$__wname}{$aname})) {
  	return $attr{$__wname}{$aname};
  } else {
  	CommandAttr (undef, $__wname . " $aname $def");
  }
  return $def;
}

##################
sub
FHEMRENDERER_setAttr($$)
{
  my ($aname, $def) = @_;
 	CommandAttr (undef, $__wname . " $aname $def");
}


##################
# Calculate either the number of scrollable weblinks (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
FHEMRENDERER_calcWeblink($$)
{
  my ($d,$wl) = @_;

  return if($__plotmode eq "gnuplot");
  my $now = time();

  my $zoom = $__pos{zoom};
  $zoom = "day" if(!$zoom);

  if(!$d) {
    foreach my $d (sort keys %__devs ) {
      next if($__devs{$d}{type} ne "weblink");
      next if(!$__room || ($__room ne "all" && !$__rooms{$__room}{$d}));
      next if($__devs{$d}{ATTR} && $__devs{$d}{ATTR}{noscroll});
      next if($__devs{$d}{ATTR} && $__devs{$d}{ATTR}{fixedrange});
      $__scrolledweblinkcount++;
    }
    return;
  }


#  return if(!$__devs{$wl});
  return if($__devs{$wl} && $__devs{$wl}{ATTR}{noscroll});

  if($__devs{$wl} && $__devs{$wl}{ATTR}{fixedrange}) {
    my @range = split(" ", $__devs{$wl}{ATTR}{fixedrange}{VAL});
    $__devs{$d}{from} = $range[0];
    $__devs{$d}{to}   = $range[1];
    return;
  }

  my $off = $__pos{$d};
  $off = 0 if(!$off);
  $off += $__pos{off} if($__pos{off});

  if($zoom eq "qday") {

    my $t = $now + $off*21600;
    my @l = localtime($t);
    $l[2] = int($l[2]/6)*6;
    $__devs{$d}{from}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]);
    $__devs{$d}{to}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]+6);

  } elsif($zoom eq "day") {

    my $t = $now + $off*86400;
    my @l = localtime($t);
    $__devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);
    $__devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]+1);

  } elsif($zoom eq "week") {

    my @l = localtime($now);
    my $t = $now - ($l[6]*86400) + ($off*86400)*7;
    @l = localtime($t);
    $__devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

    @l = localtime($t+7*86400);
    $__devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);


  } elsif($zoom eq "month") {

    my @l = localtime($now);
    while($off < -12) {
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $__devs{$d}{from} = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $__devs{$d}{to}   = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

  } elsif($zoom eq "year") {

    my @l = localtime($now);
    $l[5] += $off;
    $__devs{$d}{from} = sprintf("%04d", $l[5]+1900);
    $__devs{$d}{to}   = sprintf("%04d", $l[5]+1901);

  }
}


1;
=pod
=begin html

<a name="FHEMRENDERER"></a>
<h3>FHEMRENDERER</h3>
<ul>
  The FHEMRENDERER module is intended to render (draw) graphics based on the FHEM Log-Files.
  This can be done either based on a timer (used in the module) or based on a direct call of GET.
  The rendered graphics will be stored in a pre-defined directory with a predefined prefix of the files. The renderer can also work in a multi-process mode,
  which doesn't block the main FHEM-Loop.
  <br> <br>

  <a name="FHEMRENDERERdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMRENDERER [global]</code>
        <br><br>
        This defines a new "device", that is of type FHEMRENDERER. The option 'global' can be used if needed for sorting reasons.
        Otherwise this option has no real meaning for FHEMRENDERER.<br>
        <br>
        As a side-effect of defining this "device" the following attributes will be set for this "device":<br>
        &nbsp;&nbsp;plotmode        gnuplot    <br>
        &nbsp;&nbsp;plotsize        800,200 <br>
        &nbsp;&nbsp;refresh            00:10:00 <br>
        &nbsp;&nbsp;room            Unsorted <br>
        &nbsp;&nbsp;status            off <br>
        &nbsp;&nbsp;tmpfile            /tmp/ <br>
        &nbsp;&nbsp;multiprocess    off <br>
<br>
        NOTE: The Logfile will report (with LogLevel 2) that the FHEMRENDERER has been defined.

  </ul>
  <br>

  <a name="FHEMRENDERERset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set either on or off.<br>
    <br>
    This switches the timer-based rendering on/off. The attribute 'status' will be modified accordingly.<br>
    NOTE: only WebLink based graphics will be rendered.

  </ul>
  <br>

  <a name="FHEMRENDERERget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;[[file-name] device type logfile [pos=zoom=XX&off=YY]]&gt</code><br>
    <br>
    The get function supports different sets of arguments: <br>
    Arguments:<br />
    &nbsp;&nbsp;&nbsp;NONE: all WebLink based FilePlots will be rerendered<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The resulting filename will be '<attr-tmpfile><weblinkname>.png'<br>
    &nbsp;&nbsp;&nbsp;THREE: device type logfile <br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;In this case only one specific graphic will be rendered:<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The resulting filename will be 'attr-tmpfile logfile.png'<br>
    &nbsp;&nbsp;&nbsp;FOUR:    file-name device type logfile<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;In this case only one specific graphic will be rendered:<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The resulting filename will be 'attr-tmpfile file-name.png'<br>
    &nbsp;&nbsp;&nbsp;FIVE:    file-name device type logfile pos=zoom=XX&off=YYY <br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;In this case only one specific graphic will be rendered assuming that plotmode is 'gnuplot-scroll':<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The 'zoom' will be either qday/day/week/month/year (same as used in FHEMWEB).<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The offset 'off' is either 0 (then the second part can be omitted), or -1/-2.... to jump back in time.<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The resulting filename will be 'attr-tmpfile file-name.png'<br>
<br>
            NOTE: If you want to use zoom AND offset then you have to concatenate via '&' !!<br>
<br>
        NOTE: combinations are possible in limited ranges:<br>
            meaning: you can add the 'pos=zoom=XX&off=YY' to any of the first three sets. <br>
                     This may e.g. result in rendering all WebLinks with a specific zoom or offset <br>
                 (if you just pass the 'pos=zoom=xx&off=yy' parameter);<br>
<br>
    Any rendered image (one or all WebLinks) will be stored in 'attr-tmpfile' followed by a 'filename.png'. The filename will be
    either derived (from weblink-name or logfile-name) or, for single files, can be assigend.<br>

  </ul>
  <br>


  <a name="FHEMRENDERERattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="plotmode"></a>
    <li>plotmode<br>
        Specifies how to generate the plots:
        <ul>
          <li>gnuplot<br>
              Call the gnuplot script with each logfile. The filename
              specification of the <a href="#FileLog">FileLog</a> device will
              determine what is in the plot.  The data is converted into an
              image on the backend with gnuplot.</li>
          <li>gnuplot-scroll<br>
              FHEMRENDERER will offer zoom and offset possibilities in order to navigate
              in the current logfile, i.e. you can select just a part of the
              data to be displayed. The more data is contained in a single
              logfile, the easier you can navigate. The recommendation is to
              store the data for a whole year in one logfile.  The data is
              converted into an image on the backend with gnuplot.</li>
        </ul>
        </li><br>

    <a name="plotsize"></a>
    <li>plotsize<br>
        the default size of the plot, in pixels, separated by comma:
        width,height. You can set individual sizes by setting the plotsize of
        the weblink.
        </li><br>
    <a name="status="></a>
    <li>status<br>
        Reflects the status, if the renderer timer has been set to ON or OFF.
        By reading the status, you can detect, if the timer is running, or not.
        </li><br>

    <a name="refresh"></a>
    <li>refresh<br>
        This defines the time-interval in which a new rendering of the defined
        WebLinks will be done.
        </li><br>

    <a name="tmpfile"></a>
    <li>tmpfile<br>
        This gives the path and a possible prefix for the rendered
        filenames.<br> You can specify a path to which the files will be
        rendered. If you also specify a prefix, this will be used to build the
        resulting filename.
        </li><br>
    <li>multiprocess<br>
        This defines if the Renderer works in a multiprocessing mode.<br>
        You can set multiprocessing either to on / off and the renderer will draw the
        time-scheduled tasks either in multiprocessing mode, or not.
        NOTE: Direct GET calls, except for a general GET (for all weblinks) will be renderer
        in an interactive mode, meaning that the FHEM-Loop will be block as long as the graphics are rendered.
        If you want to use multiprocessing, set the RENDERER and multiprocessing to on and the
        weblink-graphics will be rendered in the background.
        </li><br>

     </ul>
  </ul>


=end html
=cut
