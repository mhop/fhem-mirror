##############################################
#
# 55_InfoPanel.pm written by betateilchen
#
# forked from 02_RSS.pm by Dr. Boris Neubert
#
##############################################
# $Id: $

package main;
use strict;
use warnings;

use MIME::Base64;
use Image::Info qw(image_info dim);
#use Data::Dumper;

use feature qw/switch/;
use vars qw(%data);
use HttpUtils;

my @cmd_halign= qw(thalign ihalign);
my @cmd_valign= qw(tvalign ivalign);
my @valid_valign = qw(auto baseline middle center hanging);
my @valid_halign = qw(start middle end);

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# we can 
# use vars qw(%FW_types);  # device types,
# use vars qw($FW_RET);    # Returned data (html)
# use vars qw($FW_wname);  # Web instance
# use vars qw($FW_subdir); # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
# use vars qw(%FW_pos);    # scroll position
# use vars qw($FW_cname);  # Current connection name

#sub InfoPanel_Initialize($);
sub btIP_Define($$);
sub btIP_Set;
sub btIP_Notify;
sub btIP_readLayout($);

sub btIP_itemArea;
sub btIP_itemCircle;
sub btIP_itemDate;
sub btIP_itemEllipse;
sub btIP_itemImg;
sub _btIP_imgData;
sub _btIP_imgRescale;
sub btIP_itemLine;
sub btIP_itemPlot;
sub btIP_itemRect;
sub btIP_itemSeconds;
sub btIP_itemText;
sub btIP_itemTextBox;
sub btIP_itemTime;
sub btIP_color;
sub btIP_xy;

sub btIP_ReturnSVG($);
sub btIP_evalLayout($$@);

sub btIP_addExtension($$$);
sub btIP_CGI;
sub btIP_splitRequest($);

sub btIP_returnHTML($);
sub btIP_getURL($);
sub btIP_HTMLHead($$);
sub btIP_getScript;
sub btIP_HTMLTail;
sub btIP_Overview;

######################################

sub InfoPanel_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}    = "btIP_Define";
    #$hash->{AttrFn}   = "btIP_Attr";
    $hash->{AttrList} = "autoreload:1,0 bg bgcolor refresh size title tmin";
    $hash->{SetFn}    = "btIP_Set";
    $hash->{NotifyFn} = "btIP_Notify";

    btIP_addExtension("btIP_CGI","btip","InfoPanel");

    return undef;
}

sub btIP_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def);

  return "Usage: define <name> InfoPanel hostname filename"  if(int(@a) != 4);
  my $name= $a[0];
  my $hostname= $a[2];
  my $filename= $a[3];

  $hash->{NOTIFYDEV} = 'global';
  $hash->{fhem}{hostname}= $hostname;
  $hash->{fhem}{filename}= $filename;
  $hash->{fhem}{div} = '';
  $hash->{LAYOUTFILE} = $filename;

  btIP_readLayout($hash);
  
  $hash->{STATE} = 'defined';
  return undef;
}

sub btIP_Set {

  my ($hash, @a) = @_;
  my $name = $a[0];

  # usage check
  my $usage= "Unknown argument, choose one of reread:noArg";
  if((@a == 2) && ($a[1] eq "reread")) {
     btIP_readLayout($hash);
     return undef;
  } else {
    return $usage;
  }
}

sub btIP_Notify {
  my ($hash,$dev) = @_;

  return unless AttrVal($hash->{NAME},'autoreload',1);
  return if($dev->{NAME} ne "global");
  return if(!grep(m/^FILEWRITE $hash->{LAYOUTFILE}$/, @{$dev->{CHANGED}}));

  Log3(undef, 4, "InfoPanel: $hash->{NAME} reread layout after edit.");
  undef = btIP_readLayout($hash);
  return undef;
}

sub btIP_readLayout($) {

  my ($hash)= @_;
  my $filename= $hash->{fhem}{filename};
  my $name= $hash->{NAME};

  my ($err, @layoutfile) = FileRead($filename);
  if($err) {
    Log 1, "InfoPanel $name: $err";
    $hash->{fhem}{layout}= ("text 0.1 0.1 'Error: $err'");
  } else {
    $hash->{fhem}{layout} = join("\n", @layoutfile);
    while($hash->{fhem}{layout} =~ m/\@include/ ) {
      my (@layout2,@include);
      foreach my $ll (@layoutfile) {
        if($ll !~ m/^\@include/) {
          push(@layout2,$ll);
        } else {
          my ($cmd, $def)= split("[ \t]+", $ll, 2);
          ($err,@include) = FileRead($def) if($def);
          splice(@layout2,-1,0,@include) unless $err;          
        }
      }
      @layoutfile = @layout2;
      @layout2    = undef;
      $hash->{fhem}{layout} = join("\n",@layoutfile);
    }
    $hash->{fhem}{layout} =~ s/\n\n/\n/g;
  }
  return;
}
  

##################
#
# Layout evaluation
#

##### Items 

sub btIP_itemArea {
  my ($id,$x1,$y1,$x2,$y2,$target,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $width  = $x2 - $x1;
  my $height = $y2 - $y1;
  my $output  = "<a id=\”$id\” x=\"$x1\" y=\"$y1\" width=\"$width\" height=\"$height\" xlink:href=\"$target\" >\n";
     $output .= "<rect id=\”$id\” x=\"$x1\" y=\"$y1\" width=\"$width\" height=\"$height\" opacity=\"0\" />\n";
     $output .= "</a>\n";
  return $output;
}

sub btIP_itemCircle {
  my ($id,$x,$y,$r,$filled,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $output = "<circle id=\”$id\” cx=\"$x\" cy=\"$y\" r=\"$r\" ";
  if($filled) {
    my ($r,$g,$b,$a) = btIP_color($params{rgb});
    $output .= "style=\"fill:rgb($r,$g,$b); fill-opacity:$a; stroke-width:0;\" "
  }
  $output .= "/>\n";
  return $output;
}

sub btIP_itemDate {
  my ($id,$x,$y,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return btIP_itemText($id,$x,$y,sprintf("%02d.%02d.%04d", $mday, $mon+1, $year+1900),%params);
}

sub btIP_itemEllipse {
  my ($id,$x,$y,$rx,$ry,$filled,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $output = "<ellipse $id=\"$id\" cx=\"$x\" cy=\"$y\" rx=\"$rx\" ry=\"$ry\" ";
  if($filled) {
    my ($r,$g,$b,$a) = btIP_color($params{rgb});
    $output .= "style=\"fill:rgb($r,$g,$b); fill-opacity:$a; stroke-width:0;\" "
  }
  $output .= "/>\n";
  return $output;
}

sub btIP_itemGroup {
  my($id,$type,$arg) = @_;
  return "</g>\n"               if $type eq 'close';
  $arg = defined($arg) ? $arg : "";
  $id = ($id eq '-') ? createUniqueId() : $id;
  return "<g id=\"$id\" $arg >" if $type eq 'open';
}

sub btIP_itemImg {
  my ($id,$x,$y,$scale,$srctype,$arg,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  return unless(defined($arg));
  return if($arg eq "");
  my ($data,$info,$width,$height,$mimetype,$output);

  if($srctype eq 'file') {
     Log3(undef,4,"InfoPanel img name: $arg");
     my $length = -s "$arg";
     Log3(undef,4,"InfoPanel img len : $length");
     open(GRAFIK, "<", $arg) or die("File not found $!");
     binmode(GRAFIK);
     my $readBytes = read(GRAFIK, $data, $length);
     close(GRAFIK);
  } elsif ($srctype eq "url" || $srctype eq "urlq") {
     if($srctype eq "url") {
       $data= GetFileFromURL($arg,3,undef,1);
     } else {
       $data= GetFileFromURLQuiet($arg,3,undef,1);
     }
  } elsif ($srctype eq 'data') {
     $data = $arg;
  } else {
     Log3(undef,2,"InfoPanel: unknown sourcetype for image tag");
     return "";
  }

  ($width,$height,$data) = _btIP_imgData($data,$scale);
  $output = "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"".$width."px\" height=\"".$height."px\" \nxlink:href=\"$data\" />\n";
  return $output;
}

sub _btIP_imgData {
  my ($arg,$scale) = @_;
  my $info     = image_info(\$arg);
  my $width    = $info->{width};
  my $height   = $info->{height};
  ($width,$height)= _btIP_imgRescale($width,$height,$scale) unless $scale eq '1';
  my $mimetype = $info->{file_media_type};
  my $data     = "data:$mimetype;base64,".encode_base64($arg);
  return ($width,$height,$data);
}

sub _btIP_imgRescale {
  my ($width,$height,$scale) = @_;
  if ($scale =~ s/([whWH])([\d]*)/$2/) { 
    $scale = (uc($1) eq "W") ? $scale/$width : $scale/$height;
  }
  $width  = int($scale*$width);
  $height = int($scale*$height);
  return ($width,$height);
}

sub btIP_itemLine {
  my ($id,$x1,$y1,$x2,$y2,$th,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($r,$g,$b,$a) = btIP_color($params{rgb});
  return "<line id=\"$id\" x1=\"$x1\" y1=\"$y1\" x2=\"$x2\" y2=\"$y2\" style=\"stroke:rgb($r,$g,$b); stroke-width:$th; stroke-opacity:$a; \" />\n";
}

sub btIP_itemPlot {
  my ($id,$x,$y,$scale,$inline,$arg) = @_;
  my (@plotName) = split(";",$arg);
  $id = ($id eq '-') ? createUniqueId() : $id;
  my (@webs,$width,$height,$output,$mimetype,$svgdata);
  
  @webs=devspec2array("TYPE=FHEMWEB");
  foreach(@webs) {
    if(!InternalVal($_,'TEMPORARY',undef)) {
      $FW_wname=InternalVal($_,'NAME','');
      last;
    }
  }

  ($width,$height) = split(",", AttrVal($plotName[0],"plotsize","800,160"));
  ($width,$height) = _btIP_imgRescale($width,$height,$scale) unless $scale eq '1';

  if($inline eq "1") {
#
# embed base64 data
#
    $FW_RET                 = undef;
    $FW_webArgs{dev}        = $plotName[0];
    $FW_webArgs{logdev}     = InternalVal($plotName[0], "LOGDEVICE", "");
    $FW_webArgs{gplotfile}  = InternalVal($plotName[0], "GPLOTFILE", "");
    $FW_webArgs{logfile}    = InternalVal($plotName[0], "LOGFILE", "CURRENT"); 
    $FW_pos{zoom}           = ($plotName[1]) ? $plotName[1] : 'day';
    $FW_pos{off}            = ($plotName[2]) ? $plotName[2] : undef;

    ($mimetype, $svgdata)   = SVG_showLog("unused");
    $svgdata =~ s/<\/svg>/<polyline opacity="0" points="0,0 $width,$height"\/><\/svg>/;
#    $svgdata =~ s/<svg/<svg width="$width" height="$height" /;

    $output  = "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"".$width."px\" height=\"".$height."px\" \n";
    $output .= "xlink:href=\"data:$mimetype;base64,".encode_base64($svgdata)."\" />\n";

  } else {
#
# embed link to plot
#
    my $url;
    $url  = "$FW_ME/SVG_showLog?dev=". $plotName[0].
          "&amp;logdev=".            InternalVal($plotName[0], "LOGDEVICE", "").
          "&amp;gplotfile=".         InternalVal($plotName[0], "GPLOTFILE", "").
          "&amp;logfile=".           InternalVal($plotName[0], "LOGFILE", "CURRENT");
     $url .= "&amp;pos=".            ($plotName[1]) ? $plotName[1] : 'day';
     $url .= "&amp;zoom=".           ($plotName[2]) ? $plotName[2] : undef;

    $output = "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"".$width."px\" height=\"".$height."px\" \nxlink:href=\"$url\" />\n";
  }

  return $output; 
}

sub btIP_itemRect {
  my ($id,$x1,$y1,$x2,$y2,$rx,$ry,$filled,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $width  = $x2 - $x1;
  my $height = $y2 - $y1;
  my $output = "<rect id=\”$id\” x=\"$x1\" y=\"$y1\" width=\"$width\" height=\"$height\" rx=\"$rx\" ry=\"$ry\" ";
  if($filled) {
    my ($r,$g,$b,$a) = btIP_color($params{rgb});
    $output .= "style=\"fill:rgb($r,$g,$b); fill-opacity:$a; stroke-width:0;\" "
  }
  $output .= "/>\n";
  return $output;
}

sub btIP_itemSeconds {
  my ($id,$x,$y,$format,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  if ($format eq "colon")
  { return btIP_itemText($id,$x,$y,sprintf(":%02d", $sec),%params); }
  else
  { return btIP_itemText($id,$x,$y,sprintf("%02d", $sec),%params); }
}

sub btIP_itemText {
  my ($id,$x,$y,$text,%params)= @_;
  return unless(defined($text));
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($r,$g,$b,$a) = btIP_color($params{rgb});

  my $output = "<text id=\”$id\” x=\"$x\" y=\"$y\" ".
               "fill=\"rgb($r,$g,$b)\" fill-opacity=\"$a\" ".
               "font-size=\"$params{pt}px\" font-family=\"$params{font}\" ".
               "text-anchor=\"$params{thalign}\" ".
               "alignment-baseline=\"$params{tvalign}\" ".
               ">\n$text\n</text>\n";

  return $output;
}

sub btIP_itemTextBox {
  my ($id,$x,$y,$boxwidth,$boxheight,$text,%params)= @_;
  return unless(defined($text));
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $color = substr($params{rgb},0,6);
  my ($d,$output);

  if(defined($params{boxcolor})) {
     my $orgcolor = $params{rgb};
     $params{rgb} = $params{boxcolor};
     my $bx1 = $x - $params{padding};
     my $by1 = $y - $params{padding};
     my $bx2 = $x + $boxwidth  + $params{padding};
     my $by2 = $y + $boxheight + $params{padding};
     $output .= btIP_itemRect("box_$id",$bx1,$by1,$bx2,$by2,1,1,1,%params);
     $params{rgb} = $orgcolor;
  }

  $d = "<div id=\"text_$id\" style=\"position:absolute; top:".$y."px; left:".$x."px; ".
       "width:".$boxwidth."px; height:".$boxheight."px; text-overflow:ellipsis; z-index:2\" >\n".
       "<p style=\"font-family:$params{font}; font-size:$params{pt}; color:#$color; ".
       "width:".$boxwidth."px; height:".$boxheight."px; ".
       "margin-top:0px; text-align:$params{tbalign}; text-overflow:ellipsis; ".
       "\">\n$text\n</p>\n".
       "</div>\n";

  $defs{$params{name}}{fhem}{div} .= $d;

  return $output; 
}

sub btIP_itemTime {
  my ($id,$x,$y,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return btIP_itemText($id,$x,$y,sprintf("%02d:%02d", $hour, $min),%params);
}

##### Helper

sub btIP_color {
  my ($rgb)= @_;
  my $alpha = 1;
  my @d= split("", $rgb);
  if(length($rgb) == 8) {
    $alpha = hex("$d[6]$d[7]"); 
    $alpha = $alpha/255;
  }
  return (hex("$d[0]$d[1]"),hex("$d[2]$d[3]"),hex("$d[4]$d[5]"),$alpha);
}

sub btIP_xy {
  my ($x,$y,%params)= @_;

  $x = $params{xx} if($x eq 'x');
  $y = $params{yy} if($y eq 'y');
  if((-1 < $x) && ($x < 1)) { $x *= $params{width}; }
  if((-1 < $y) && ($y < 1)) { $y *= $params{height}; }
  return($x,$y);
}


##################
#
# create SVG content
#

sub btIP_returnSVG($) {
  my ($name)= @_;


  #
  # increase counter
  #
  if(defined($defs{$name}{fhem}) && defined($defs{$name}{fhem}{counter})) {
    $defs{$name}{fhem}{counter}++;
  } else {
    $defs{$name}{fhem}{counter}= 1;
  }

  my ($width,$height)= split(/x/, AttrVal($name,"size","800x600"));
  my $bgcolor = AttrVal($name,'bgcolor','000000'); 

  our $svg;

  eval {

    $svg = "\n<svg \n".
           "xmlns=\"http://www.w3.org/2000/svg\"\nxmlns:xlink=\"http://www.w3.org/1999/xlink\"\n".
           "width=\"".$width."px\" height=\"".$height."px\" \n ".
           "viewPort=\"0 0 $width $height\"\n".
           "style=\"stroke-width: 0px; background-color:$bgcolor; ";

    # set the background
    # check if background directory is set
    my $reason= "?"; # remember reason for undefined image
    my $bgdir= AttrVal($name,"bg","undef");
	if(defined($bgdir)){
		my $bgnr; # item number
		if(defined($defs{$name}{fhem}) && defined($defs{$name}{fhem}{bgnr})) {
			$bgnr= $defs{$name}{fhem}{bgnr};
		} else {
			$bgnr= 0;
		}
		# check if at least tmin seconds have passed
		my $t0= 0;
		my $tmin= AttrVal($name,"tmin",0);
		if(defined($defs{$name}{fhem}) && defined($defs{$name}{fhem}{t})) {
			$t0= $defs{$name}{fhem}{t};
		}
		my $t1= time();
		if($t1-$t0>= $tmin) {
			$defs{$name}{fhem}{t}= $t1;
			$bgnr++;
		}
		# detect pictures
# 		if(opendir(BGDIR, $bgdir)){
# 			my @bgfiles= grep {$_ !~ /^\./} readdir(BGDIR);
# 			
# 			#foreach my $f (@bgfiles) {
# 			#  Debug sprintf("File \"%s\"\n", $f);
# 			#}
# 			closedir(BGDIR);
# 			# get item number
# 			if($#bgfiles>=0) {
# 				if($bgnr > $#bgfiles) { $bgnr= 0; }
# 				$defs{$name}{fhem}{bgnr}= $bgnr;
# 				my $bgfile= $bgdir . "/" . $bgfiles[$bgnr];
# 				my $filetype =(split(/\./,$bgfile))[-1];
# 				my $bg;
# 				$bg= newFromGif  GD::Image($bgfile) if $filetype =~ m/^gif$/i;
# 				$bg= newFromJpeg GD::Image($bgfile) if $filetype =~ m/^jpe?g$/i;
# 				$bg= newFromPng  GD::Image($bgfile) if $filetype =~ m/^png$/i;
# 				if(defined($bg)) {
# 				  my ($bgwidth,$bgheight)= $bg->getBounds();
# 				  if($bgwidth != $width or $bgheight != $height) {
# 					  # we need to resize
# 					  my ($w,$h);
# 					  my ($u,$v)= ($bgwidth/$width, $bgheight/$height);
# 					  if($u>$v) {
# 						  $w= $width;
# 						  $h= $bgheight/$u;
# 					  } else {
# 						  $h= $height;
# 						  $w= $bgwidth/$v;
# 					  }
# 					  $svg->copyResized($bg,($width-$w)/2,($height-$h)/2,0,0,$w,$h,$bgwidth,$bgheight);
# 				  } else {
# 					  # size is as required
# 					  # kill the predefined image and take the original
# 					  undef $svg;
# 					  $svg= $bg;
# 				  }
# 				} else {
# 				  undef $svg;
# 				  $reason= "Something was wrong with background image \"$bgfile\".";
# 				}
# 			}
# 		} # end opendir()
	} # end defined()

    $svg .= "\" >\n\n";
    $svg = btIP_evalLayout($svg, $name, $defs{$name}{fhem}{layout});

    $defs{$name}{STATE} = localtime();

    
  }; #warn $@ if $@;
  if($@) {
    my $msg= $@;
    chomp $msg;
    Log3 $name, 2, $msg;
  }

  $svg .= "Sorry, your browser does not support inline SVG.\n</svg>\n";

  return $svg;

}

sub btIP_evalLayout($$@) {
  my ($svg,$name,$layout)= @_;
  my ($width,$height)= split(/x/, AttrVal($name,"size","800x600"));
  my @layout= split("\n", $layout);

  my %h4params;
  
  my %params;
  $params{name}= $name;
  $params{width}= $width;
  $params{height}= $height;
  $params{font}= "Arial";
  $params{pt}= 12;
  $params{rgb}= "ffffff";
  $params{condition} = 1;
  # we need two pairs of align parameters
  # due to different default values for text and img
  $params{ihalign} = 'left';
  $params{ivalign} = 'top';
  $params{thalign} = 'start';
  $params{tvalign} = 'auto';
  $params{tbalign} = 'left';
  $params{linespace} = 0;
  $params{boxcolor} = undef;
  $params{padding} = 0;
  $params{xx}= 0;
  $params{yy}= 0;

  $defs{$name}{fhem}{div} = undef;  

  my ($id,$x,$y,$x1,$y1,$x2,$y2,$r1,$r2);
  my ($scale,$inline,$boxwidth,$boxheight,$boxcolor);
  my ($text,$imgtype,$srctype,$arg,$format);
  
  my $cont= "";
  foreach my $line (@layout) {
    # kill trailing newline
	chomp $line;
	# kill comments and blank lines
	$line=~ s/\#.*$//;
	$line=~ s/\@.*$//;
	$line=~ s/\s+$//;
	$line= $cont . $line;
	if($line=~ s/\\$//) { $cont= $line; undef $line; }
	next unless($line);
	$cont= "";
	#Debug "$name: evaluating >$line<";
	# split line into command and definition
	my ($cmd, $def)= split("[ \t]+", $line, 2);

# Debug "CMD= \"$cmd\", DEF= \"$def\"";
	  
    # separate condition handling
    if($cmd eq 'condition') {
	  $params{condition} = AnalyzePerlCommand(undef, $def);
	  next;
	}  
    next unless($params{condition});
	  
# Debug "before command $line: x= " . $params{xx} . ", y= " . $params{yy};

    eval {
      given($cmd) {

	    when("push") {
        }
        
	    when("pop") {
        }

	    when("area") {
	      ($id,$x1,$y1,$x2,$y2,$arg)= split("[ \t]+", $def, 6);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
	      my $arg = AnalyzePerlCommand(undef,$arg);
          $params{xx} = $x;
          $params{yy} = $y;
	      $svg .= btIP_itemArea($id,$x1,$y1,$x2,$y2,$arg,%params);
	    }

        when("boxcolor"){
	      $def = "\"$def\"" if(length($def) == 6 && $def =~ /[[:xdigit:]]{6}/);
	      $params{boxcolor} = AnalyzePerlCommand(undef, $def);
	    }

	    when("circle") {
	      ($id,$x1,$y1,$r1,$format)= split("[ \t]+", $def, 5);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      $format //= 0; # set format to 0 as default (not filled)
	      $svg .= btIP_itemCircle($id,$x1,$y1,$r1,$format,%params);
	    }
	    
	    when("date") {
	      ($id,$x,$y)= split("[ \t]+", $def, 3);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemDate($id,$x,$y,%params);
	    }
	    
	    when("ellipse") {
	      ($id,$x1,$y1,$r1,$r2,$format)= split("[ \t]+", $def, 6);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      $format //= 0; # set format to 0 as default (not filled)
	      $svg .= btIP_itemEllipse($id,$x1,$y1,$r1,$r2,$format,%params);
	    }
	    
	    when("font") {
          $params{font} = $def;
        }

	    when("font") {
          $params{font} = $def;
        }

	    when("group") {
	      ($id,$text,$arg) = split("[ \t]+", $def, 3);
	      my $arg = AnalyzePerlCommand(undef, $arg) if($arg);
	      $svg .= btIP_itemGroup($id,$text,$arg);
        }

	    when("img") {
	      ($id,$x,$y,$scale,$srctype,$arg)= split("[ \t]+", $def,6);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y; 
	      my $arg= AnalyzePerlCommand(undef, $arg);
          $svg .= btIP_itemImg($id,$x,$y,$scale,$srctype,$arg,%params);
	    }
	    
        when("line") {
	      ($id,$x1,$y1,$x2,$y2,$format)= split("[ \t]+", $def, 6);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
	      $format //= 1; # set format to 1 as default thickness for the line
	      $svg .= btIP_itemLine($id,$x1,$y1,$x2,$y2, $format,%params);
	    }
	    
        when("linespace") {
          $params{linespace}= $def;
        }

        when("moveby") {
          my ($byx,$byy)= split('[ \t]+', $def, 2);
          my ($x,$y)= btIP_xy($byx,$byy,%params);
          $params{xx} += $x;
          $params{yy} += $y;
        }
        
        when("moveto") {
          my ($tox,$toy)= split('[ \t]+', $def, 2);
          my ($x,$y)= btIP_xy($tox,$toy,%params);
          $params{xx} = $x;
          $params{yy} = $y;
        }

        when("padding") {
          $params{padding}= AnalyzePerlCommand(undef,$def);
        }

	    when("plot") {
	      ($id,$x,$y,$scale,$inline,$arg)= split("[ \t]+", $def,6);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y; 
	      my $arg = AnalyzePerlCommand(undef, $arg);
	      $svg .= btIP_itemPlot($id,$x,$y,$scale,$inline,$arg,%params);
	    }
	    
        when("pt") {
          $def = AnalyzePerlCommand(undef, $def);
	      if($def =~ m/^[+-]/) {
		    $params{pt} += $def;
	      } else {
		    $params{pt} =  $def;
	      }
          $params{pt} = 6 if($params{pt} < 0);
        }
        
	    when("rect") {
	      ($id,$x1,$y1,$x2,$y2,$r1,$r2,$format)= split("[ \t]+", $def, 8);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
          $params{xx} = $x;
          $params{yy} = $y;
	      $format //= 0; # set format to 0 as default (not filled)
	      $svg .= btIP_itemRect($id,$x1,$y1,$x2,$y2,$r1,$r2,$format,%params);
	    }
	    
        when("rgb"){
	      $def = "\"$def\"" if(length($def) == 6 && $def =~ /[[:xdigit:]]{6}/);
	      $params{rgb} = AnalyzePerlCommand(undef, $def);
	    }

	    when("seconds") {
          ($id,$x,$y,$format) = split("[ \+]", $def,4);
          ($x,$y)= btIP_xy($x,$y,%params);
          $params{xx} = $x;
          $params{yy} = $y;
          $svg .= btIP_itemSeconds($id,$x,$y,$format,%params);
	    }
	    
        when("text") {
          ($id,$x,$y,$text)= split("[ \t]+", $def, 4);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      my $txt= AnalyzePerlCommand(undef, $text);
          $svg .= btIP_itemText($id,$x,$y,$txt,%params);
        }
        
        when("textbox") {
          ($id,$x,$y,$boxwidth,$boxheight,$text)= split("[ \t]+", $def, 6);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      my $txt= AnalyzePerlCommand(undef, $text);
	      $txt =~ s/\n/<br\/>/g;
	      my $name = $params{name};
	      $svg .= btIP_itemTextBox($id,$x,$y,$boxwidth,$boxheight,$txt,%params);
          $params{xx} = $x;
          $params{yy} = $y + $boxheight;
        }
        
        when("textboxalign") {
          $params{tbalign} = $def;
        }

	    when("time") {
	      ($id,$x,$y)= split("[ \t]+", $def, 3);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemTime($id,$x,$y,%params);
	    }

	    default {
          if($cmd ~~ @cmd_halign) {
	        my $d = AnalyzePerlCommand(undef, $def);
            if($d ~~ @valid_halign) { 
              $params{ihalign}= $d unless($cmd eq "thalign");
              $params{thalign}= $d unless($cmd eq "ihalign");
            } else {
              Log3 $name, 2, "InfoPanel: $name Illegal horizontal alignment $d";
            }
          } elsif($cmd ~~ @cmd_valign) {
            my $d = AnalyzePerlCommand(undef, $def);
            if( $d ~~ @valid_valign) {
              $params{ivalign}= $d unless($cmd eq "tvalign");
              $params{tvalign}= $d unless($cmd eq "ivalign");
            } else {
              Log3 $name, 2, "InfoPanel: $name: Illegal vertical alignment $d";
            }
          } else {
            Log3 $name, 2, "InfoPanel $name: Illegal command $cmd in layout definition.";
          }
        } # default
      } # given
	} # eval

# Debug "after  command $line: x= " . $params{xx} . ", y= " . $params{yy};

  } # foreach
  return $svg;
}
   
##################
#
# here we answer any request to http://host:port/fhem/rss and below
#

sub btIP_addExtension($$$) {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $link;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
    $data{FWEXT}{$url}{FORKABLE} = 0;
}

sub btIP_CGI{

  my ($request) = @_;
  
  my ($name,$ext)= btIP_splitRequest($request);

  if(defined($name)) {
    if($ext eq "") {
          return("text/plain; charset=utf-8", "Illegal extension.");
    }
    if(!defined($defs{$name})) {
          return("text/plain; charset=utf-8", "Unknown InfoPanel device: $name");
    }
    if($ext eq "info" || $ext eq "html") {
          return btIP_returnHTML($name);
    }
  } else {
    return btIP_Overview();
  }

}

sub btIP_splitRequest($) {

  my ($request) = @_;

  if($request =~ /^.*\/btip$/) {
    # http://localhost:8083/fhem/btip
    return (undef,undef); # name, ext
  } else {
    my $call= $request;
    $call =~ s/^.*\/btip\/([^\/]*)$/$1/;
    my $name= $call;
    $name =~ s/^(.*)\.(svg|info|html)$/$1/;
    my $ext= $call;
    $ext =~ s/^$name\.(.*)$/$1/;
    return ($name,$ext);
  }
}


####################
#
# HTML Stuff
#

sub btIP_returnHTML($) {
  my ($name) = @_;

  my $url     = btIP_getURL($defs{$name}{fhem}{hostname});
  my $refresh = AttrVal($name, 'refresh', 60);
  my $title   = AttrVal($name, 'title', $name);
  
  my $code    = btIP_HTMLHead($title,$refresh);

  $code .=  "<body topmargin=\"0\" leftmargin=\"0\" margin=\"0\" padding=\"0\">\n".
            "<div id=\"svg_content\" z-index=\"1\" >\n".
            btIP_returnSVG($name)."\n</div>\n";
  $code .=  $defs{$name}{fhem}{div} if($defs{$name}{fhem}{div});
  $code .=  "</body>\n".btIP_HTMLTail();

  return ("text/html; charset=utf-8", $code);
}

sub btIP_getURL($) {
  my ($hostname)= @_;
  # http://hostname:8083/fhem
  my $proto = (AttrVal($FW_wname, 'HTTPS', 0) == 1) ? 'https' : 'http';
  return $proto."://$hostname:" . $defs{$FW_wname}{PORT} . $FW_ME;
}

sub btIP_HTMLHead($$) {
  my ($title,$refresh) = @_;
  
#  my $doctype= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
#  my $xmlns= 'xmlns="http://www.w3.org/1999/xhtml"';
  my $doctype= '<?xml version="1.0" standalone="no"?> '."\n".
               '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '.
               '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">'."\n";
  my $xmlns= "";

  my $r= (defined($refresh) && $refresh) ? "<meta http-equiv=\"refresh\" content=\"$refresh\"/>\n" : "";
  # css and js header output should be coded only in one place
  my $css= "";
  my $scripts= btIP_getScript();
  my $code= "$doctype\n<html $xmlns>\n<head>\n<title>$title</title>\n$r$css$scripts</head>\n";
  return $code;
}

sub btIP_getScript {

  my $scripts= "";
  my $jsTemplate = '<script type="text/javascript" src="%s"></script>';
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{SCRIPT});
      my $script = $h->{SCRIPT};
      $script = ($script =~ m,^/,) ? "$FW_ME$script" : "$FW_ME/pgm2/$script";
      $scripts .= sprintf($jsTemplate, $script) . "\n";
    }
  }
  return $scripts; 
}

sub btIP_HTMLTail {
  return "</html>";
}

sub btIP_Overview {
  my ($name, $url);
  my $html= btIP_HTMLHead("InfoPanel Overview", undef) . "<body>\n";
  foreach my $def (sort keys %defs) {
    if($defs{$def}{TYPE} eq "InfoPanel") {
        $name= $defs{$def}{NAME};
        $url= btIP_getURL($defs{$def}{fhem}{hostname});
        $html.= "$name<br>\n<ul>";
#        $html.= "<a href='$url/btip/$name.rss'>RSS</a><br>\n";
        $html.= "<a href='$url/btip/$name.info' target='_new'>HTML</a><br>\n";
#        $html.= "<a href='$url/btip/$name.png'>Portable Network Graphics</a><br>\n";
#        $html.= "<a href='$url/btip/$name.jpg'>JPEG Graphics</a><br>\n";
        $html.= "</ul>\n<p>\n";
        }
  }
  $html.="</body>\n" . btIP_HTMLTail();

  return ("text/html; charset=utf-8", $html);
}


1;
 
#
