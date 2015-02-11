##############################################
#
# 55_InfoPanel.pm written by betateilchen
#
# forked from 02_RSS.pm by Dr. Boris Neubert
#
##############################################
# $Id$

package main;
use strict;
use warnings;

#use Data::Dumper;

use feature qw/switch/;
use vars qw(%data);
use HttpUtils;

my @cmd_halign= qw(thalign ihalign);
my @cmd_valign= qw(tvalign ivalign);
my @valid_valign = qw(auto baseline middle center hanging);
my @valid_halign = qw(start middle end);

my $useImgTools = 1;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub btIP_Define;
sub btIP_Undef;
sub btIP_Set;
sub btIP_Notify;
sub btIP_readLayout;

sub btIP_itemArea;
sub btIP_itemButton;
sub btIP_itemCircle;
sub btIP_itemCounter;
sub btIP_itemDate;
sub btIP_itemEllipse;
sub btIP_itemGroup;
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
sub btIP_itemTrash;

sub btIP_color;
sub btIP_findTarget;
sub btIP_xy;
sub btIP_changeColor;
sub btIP_FileRead;

sub btIP_ReturnSVG;
sub btIP_evalLayout;

sub btIP_addExtension;
sub btIP_CGI;
sub btIP_splitRequest;

sub btIP_returnHTML;
sub btIP_HTMLHead;
sub btIP_getScript;
sub btIP_HTMLTail;
sub btIP_Overview;
sub btIP_getURL;

######################################

sub InfoPanel_Initialize($) {
    my ($hash) = @_;

    eval "use MIME::Base64";
    $useImgTools = 0 if($@);
    Log3(undef,4,"InfoPanel: MIME::Base64 missing.") unless $useImgTools;
    eval "use Image::Info qw(image_info dim)";
    $useImgTools = 0 if($@);
    Log3(undef,4,"InfoPanel: Image::Info missing.") unless $useImgTools;

    $hash->{DefFn}     = "btIP_Define";
	$hash->{UndefFn}   = "btIP_Undef";
    $hash->{SetFn}     = "btIP_Set";
    $hash->{NotifyFn}  = "btIP_Notify";
    $hash->{AttrList}  = "autoreread:1,0 bgcolor refresh size title";
    $hash->{AttrList} .= " bgcenter:1,0 bgdir bgopacity tmin" if $useImgTools;

    return undef;
}

sub btIP_Define {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  return "Usage: define <name> InfoPanel filename"  if(int(@a) != 3);
  my $name= $a[0];
  my $filename= $a[2];

  $hash->{NOTIFYDEV} = 'global';
  $hash->{fhem}{div} = '';
  $hash->{LAYOUTFILE} = $filename;

  btIP_addExtension("btIP_CGI","btip","InfoPanel");
  btIP_readLayout($hash);
  
  readingsSingleUpdate($hash,'state','defined',1);
  return undef;
}

sub btIP_Undef {
	my ($hash, $arg) = @_;
    # check if last device
    my $url = '/btip';
    delete $data{FWEXT}{$url} if int(devspec2array('TYPE=InfoPanel')) == 1;
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

sub btIP_readLayout {
  my ($hash)= @_;
  my $filename= $hash->{LAYOUTFILE};
  my $name= $hash->{NAME};

  my ($err, @layoutfile) = FileRead($filename);
  if($err) {
    Log 1, "InfoPanel $name: $err";
    $hash->{fhem}{layout} = "text ERROR 50 50 \"Error on reading layout!\"";
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
  my ($id,$x1,$y1,$x2,$y2,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;

  my $oldrgb = $params{rgb};
  $params{rgb} = '00000000';
  my $output = btIP_itemRect($id,$x1,$y1,$x2,$y2,0,0,1,0,$link,%params);
  $params{rgb} = $oldrgb;

  return $output;
}

sub btIP_itemButton {
  my ($id,$x1,$y1,$x2,$y2,$rx,$ry,$link,$text,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $width  = $x2 - $x1;
  my $height = $y2 - $y1;

  my $oldrgb = $params{rgb};
  $params{rgb} = $params{boxcolor};
  my $output = btIP_itemRect($id,$x1,$y1,$x2,$y2,$rx,$ry,1,0,$link,%params);
  $params{rgb} = $oldrgb;

  my $oldhalign = $params{thalign};
  my $oldvalign = $params{tvalign};
  $params{thalign} = "middle";
  $params{tvalign} = "middle";
  my $textoutput .= btIP_itemText("${id}_text",($x1+$x2)/2,($y1+$y2)/2,$text,%params);
  $params{thalign} = $oldhalign;
  $params{tvalign} = $oldvalign;

  $output =~ s/<\/a>/$textoutput<\/a>/;
  return $output;
}

sub btIP_itemCircle {
  my ($id,$x,$y,$r,$filled,$stroked,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $target;
  ($link,$target) = btIP_findTarget($link);
  my $output  = "";
     $output .= "<a xlink:href=\"$link\" target=\"$target\">\n" if($link && length($link));
     $output .= "<circle id=\”$id\” cx=\"$x\" cy=\"$y\" r=\"$r\" ";
  if($filled > 0 || $stroked > 0) {
    $output .= "style=\"";
    if($filled > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "fill:rgb($r,$g,$b); fill-opacity:$a; ";
    }
    if($stroked > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "stroke:rgb($r,$g,$b); stroke-width:$stroked; ";
       $output .= "fill:none; " if ($filled == 0);
    }
    $output .= "\" ";
  } else {
    $output .= "style=\"fill:none; stroke-width:0; \" ";
  }
  $output .= "/>\n";
  $output .= "</a>\n" if($link && length($link));
  return $output;
}

sub btIP_itemCounter {
  my ($id,$x,$y,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  return btIP_itemText($id,$x,$y,$defs{$params{name}}{fhem}{counter},%params);
}

sub btIP_itemDate {
  my ($id,$x,$y,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return btIP_itemText($id,$x,$y,sprintf("%02d.%02d.%04d", $mday, $mon+1, $year+1900),%params);
}

sub btIP_itemEllipse {
  my ($id,$x,$y,$rx,$ry,$filled,$stroked,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $target;
  ($link,$target) = btIP_findTarget($link);
  my $output  = "";
     $output .= "<a xlink:href=\"$link\" target=\"$target\">\n" if($link && length($link));
     $output .= "<ellipse $id=\"$id\" cx=\"$x\" cy=\"$y\" rx=\"$rx\" ry=\"$ry\" ";
  if($filled > 0 || $stroked > 0) {
    $output .= "style=\"";
    if($filled > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "fill:rgb($r,$g,$b); fill-opacity:$a; ";
    }
    if($stroked > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "stroke:rgb($r,$g,$b); stroke-width:$stroked; ";
       $output .= "fill:none; " if ($filled == 0);
    }
    $output .= "\" ";
  } else {
    $output .= "style=\"fill:none; stroke-width:0; \" ";
  }
  $output .= "/>\n";
  $output .= "</a>\n" if($link && length($link));
  return $output;
}

sub btIP_itemGroup {
  my($id,$type,$x,$y) = @_;
  return "</g>\n"               if $type eq 'close';
  $id = ($id eq '-') ? createUniqueId() : $id;
  return "<g id=\"$id\" transform=\"translate($x,$y)\" >\n" if $type eq 'open';
}

sub btIP_itemImg {
  return unless $useImgTools;
  my ($id,$x,$y,$scale,$srctype,$arg,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  return unless(defined($arg));
  return if($arg eq "");
  my ($counter,$data,$info,$width,$height,$mimetype,$output);

  if($srctype eq 'file') {
    ($counter,$data) = btIP_FileRead($arg);
    return unless $counter;
  } elsif ($srctype eq "url" || $srctype eq "urlq") {
     if($srctype eq "url") {
       $data= GetFileFromURL($arg,3,undef,1);
     } else {
       $data= GetFileFromURLQuiet($arg,3,undef,1);
     }
  } elsif ($srctype eq 'data') {
     $data = $arg;
  } else {
     Log3(undef,4,"InfoPanel: unknown sourcetype $srctype for image tag");
     return "";
  }

  ($width,$height,$mimetype,undef)    = _btIP_imgData($data,1);
  if($mimetype eq 'image/svg+xml') {
     if($data !~ m/viewBox/) {
        $data =~ s/width=/viewBox="0 0 $width $height"\n\twidth=/;
     } 
     ($width,$height) = _btIP_imgRescale($width,$height,$scale);
     $data =~ s/width=".*"/width="$width"/;
     $data =~ s/height=".*"/height="$height"/;
     $scale = 1;
     (undef,undef,undef,$data) = _btIP_imgData($data,$scale);
  } else {
     ($width,$height,$mimetype,$data) = _btIP_imgData($data,$scale);
  }

  my $target;
  ($link,$target) = btIP_findTarget($link);

  $output  = "<!-- s: $scale w: $width h: $height t: $mimetype -->\n";
  $output .= "<a xlink:href=\"$link\" target=\"$target\">\n" if($link && length($link));
  $output .= "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"${width}px\" height=\"${height}px\" \nxlink:href=\"$data\" />\n";
  $output .= "</a>\n" if($link && length($link));

  return $output;
}

sub _btIP_imgData {
  my ($arg,$scale) = @_;
  my $info     = image_info(\$arg);
  my $width    = $info->{width};
  my $height   = $info->{height};
  ($width,$height)= _btIP_imgRescale($width,$height,$scale);
  my $mimetype = $info->{file_media_type};
  
  if($FW_userAgent =~ m/Trident/ && $mimetype =~ m/svg/) {
     $arg =~ s/width=".*"//g;
     $arg =~ s/height=".*"//g;
  }
  
  my $data     = "data:$mimetype;base64,".encode_base64($arg);
  return ($width,$height,$mimetype,$data);
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
  my (@webs,$width,$height,$newWidth,$newHeight,$output,$mimetype,$svgdata);
  
  @webs=devspec2array("TYPE=FHEMWEB");
  foreach(@webs) {
    if(!InternalVal($_,'TEMPORARY',undef)) {
      $FW_wname=InternalVal($_,'NAME','');
      last;
    }
  }

  if(!$useImgTools) {
     $scale  = 1;
     $inline = 0;
  }

  ($width,$height)              = split(",", AttrVal($plotName[0],"plotsize","800,160"));
  ($newWidth,$newHeight)        = _btIP_imgRescale($width,$height,$scale);

  if($inline == 1) {
    # embed base64 data

    $FW_RET                 = undef;
    $FW_webArgs{dev}        = $plotName[0];
    $FW_webArgs{logdev}     = InternalVal($plotName[0], "LOGDEVICE", "");
    $FW_webArgs{gplotfile}  = InternalVal($plotName[0], "GPLOTFILE", "");
    $FW_webArgs{logfile}    = InternalVal($plotName[0], "LOGFILE", "CURRENT"); 
    $FW_pos{zoom}           = $plotName[1] if(length($plotName[1]));
    $FW_pos{off}            = $plotName[2] if(length($plotName[2]));
    $FW_plotsize            = "$newWidth,$newHeight";

    ($mimetype, $svgdata)   = SVG_showLog("unused");
    $svgdata =~ s/<\/svg>/<polyline opacity="0" points="0,0 $newWidth,$newHeight"\/><\/svg>/;
    (undef,undef,undef,$svgdata) = _btIP_imgData($svgdata,1);

    $output  = "<!-- s: $scale ow: $width oh: $height nw: $newWidth nh: $newHeight t: $mimetype -->\n";
    $output .= "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"${newWidth}px\" height=\"${newHeight}px\" \n";
    $output .= "xlink:href=\"$svgdata\" />\n";
  } else {
    # embed link to plot

    my $url;
    $url  = "$FW_ME/SVG_showLog?dev=". $plotName[0].
            "&amp;logdev=".            InternalVal($plotName[0], "LOGDEVICE", "").
            "&amp;gplotfile=".         InternalVal($plotName[0], "GPLOTFILE", "").
            "&amp;logfile=".           InternalVal($plotName[0], "LOGFILE", "CURRENT").
            "&amp;plotsize=".          "$newWidth,$newHeight";
    $url .= "&amp;pos=";
    $url .= "zoom=".                   "$plotName[1];" if(length($plotName[1]));
    $url .= "off=".                    $plotName[2] if(length($plotName[2]));

    $output  = "<!-- $url -->\n";
    $output .= "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"${newWidth}px\" height=\"${newHeight}px\" \nxlink:href=\"$url\" />\n";
  }

  return $output; 

}

sub btIP_itemRect {
  my ($id,$x1,$y1,$x2,$y2,$rx,$ry,$filled,$stroked,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $target;
  ($link,$target) = btIP_findTarget($link);
  my $width  = $x2 - $x1;
  my $height = $y2 - $y1;
  my $output  = "";
     $output .= "<a id=\”${id}_link\” xlink:href=\"$link\" target=\"$target\">\n" if($link && length($link));
     $output .= "<rect id=\”${id}_rect\” x=\"$x1\" y=\"$y1\" width=\"$width\" height=\"$height\" rx=\"$rx\" ry=\"$ry\" ";
  if($filled > 0 || $stroked > 0) {
    $output .= "style=\"";
    if($filled > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "fill:rgb($r,$g,$b); fill-opacity:$a; ";
    }
    if($stroked > 0) {
       my ($r,$g,$b,$a) = btIP_color($params{rgb});
       $output .= "stroke:rgb($r,$g,$b); stroke-width:$stroked; ";
       $output .= "fill:none; " if ($filled == 0);
    }
    $output .= "\" ";
  } else {
    $output .= "style=\"fill:none; stroke-width:0; \" ";
  }
  $output .= "/>\n";
  $output .= "</a>\n" if($link && length($link));
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

  my $output =  "<text id=\”$id\” x=\"$x\" y=\"$y\" ".
                "fill=\"rgb($r,$g,$b)\" fill-opacity=\"$a\" ".
                "font-family=\"$params{font}\" ".
                "font-style=\"$params{fontstyle}\" ".
                "font-size=\"$params{pt}px\" ".
                "font-weight=\"$params{fontweight}\" ".
                "text-anchor=\"$params{thalign}\" ".
                "text-decoration=\"$params{textdecoration}\" ".
                "alignment-baseline=\"$params{tvalign}\" >\n".
                "$text\n".
                "</text>\n";
  return $output;
}

sub btIP_itemTextBox {
  my ($id,$x,$y,$boxwidth,$boxheight,$text,$link,%params)= @_;
  return unless(defined($text));
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $color = substr($params{rgb},0,6);
  $link =~ s/"//g;
  my $target;
  ($link,$target) = btIP_findTarget($link);
  
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
  } else {
     $output = "";
  }

  $d  = "<div id=\"text_$id\" style=\"position:absolute; top:".$y."px; left:".$x."px; ".
        "width:".$boxwidth."px; height:".$boxheight."px; text-overflow:ellipsis; z-index:2\" >\n".
        "<style type=\"text/css\">a {text-decoration: none;}</style>\n";
  $d .= "<a href=\"$link\" target=\"$target\">\n" if($link && length($link));
  $d .= "<p style=\"font-family:$params{font}; font-size:$params{pt}; color:#$color; ".
        "width:".$boxwidth."px; height:".$boxheight."px; ".
        "margin-top:0px; text-align:$params{tbalign}; text-overflow:ellipsis; ".
        "\">\n$text\n</p>\n";
  $d .= "</a>" if($link && length($link));
  $d .= "</div>\n";

  $defs{$params{name}}{fhem}{div} .= $d;

  return $output; 
}

sub btIP_itemTime {
  my ($id,$x,$y,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  return btIP_itemText($id,$x,$y,sprintf("%02d:%02d", $hour, $min),%params);
}

sub btIP_itemTrash {
  return unless $useImgTools;
  my ($id,$x,$y,$scale,$fgcolor,$bgcolor,$link,%params)= @_;
  $id = ($id eq '-') ? createUniqueId() : $id;
  my $target;
  ($link,$target) = btIP_findTarget($link);

  my ($counter,$data,$info,$width,$height,$mimetype,$output);

$data = '<?xml version="1.0" encoding="utf-8"?>'.
'<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'.
'<svg version="1.1" id="Capa_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '.
'width="66" height="84" style="enable-background:new 0 0 66 84;" xml:space="preserve">'.
'<g>'.
'	<path d="M60.093,9.797H48.984V2.578C48.984,1.125,47.812,0,46.359,0c-0.141,0-0.235,0.047-0.281,0.094'.
'		C46.031,0.047,45.937,0,45.89,0H19.781h-0.187h-0.188c-1.453,0-2.578,1.125-2.578,2.578v7.219H5.672C2.484,9.797,0,12.281,0,15.469'.
'		v4.125v5.156h4.922v52.827c0,3.188,2.437,5.625,5.625,5.625h44.671c3.188,0,5.672-2.437,5.672-5.625V24.75h4.875v-5.156v-4.125'.
'		C65.765,12.281,63.28,9.797,60.093,9.797z M21.984,5.156h21.797v4.641H21.984V5.156z M55.687,77.577'.
'		c0,0.329-0.141,0.469-0.469,0.469H10.547c-0.328,0-0.469-0.14-0.469-0.469V24.75h45.609V77.577z M60.562,19.594H5.203v-4.125'.
'		c0-0.328,0.141-0.516,0.469-0.516h54.421c0.328,0,0.469,0.188,0.469,0.516V19.594z" stroke="fgcolor" stroke-width="3" fill="none"/>'.
'	<rect x="18" y="31" width="6" height="42" stroke="fgcolor" stroke-width="3" fill="none"/>'.
'	<rect x="30" y="31" width="6" height="42" stroke="fgcolor" stroke-width="3" fill="none"/>'.
'	<rect x="42" y="31" width="6" height="42" stroke="fgcolor" stroke-width="3" fill="none"/>'.
'</g>'.
'</svg>';

  my ($r,$g,$b,$a) = btIP_color($fgcolor);
  $fgcolor = "rgb($r,$g,$b)";
  $data =~ s/fgcolor/$fgcolor/g;

  ($r,$g,$b,$a) = btIP_color($bgcolor);
  $bgcolor = "rgb($r,$g,$b)";
  ($width,$height,$mimetype,$data) = _btIP_imgData($data,$scale);
  $output  = "";
  $output .= "<a xlink:href=\"$link\" target=\"$target\">\n" if($link && length($link));
  $output .= "<rect  id=\"$id\" x=\"$x\" y=\"$y\" width=\"".$width."px\" height=\"".$height."px\" ".
             "fill=\"$bgcolor\" fill-opacity=\"$a\" stroke=\"$bgcolor\" stroke-width=\"2\" stroke-opacity=\"$a\" />\n";
  $output .= "<image id=\"$id\" x=\"$x\" y=\"$y\" width=\"".$width."px\" height=\"".$height."px\" \nxlink:href=\"$data\" />\n";
  $output .= "</a>\n" if($link && length($link));

  return $output;
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

sub btIP_findTarget {
  my ($link) = shift;
  my $target = 'secret';
     $target = '_top' if $link =~ s/^-//;
     $target = '_blank' if $link =~ s/^\+//;
  return ($link,$target);
}

sub btIP_xy {
  my ($x,$y,%params)= @_;

  $x = $params{xx} if($x eq 'x');
  $y = $params{yy} if($y eq 'y');
  if((-1 < $x) && ($x < 1)) { $x *= $params{width}; }
  if((-1 < $y) && ($y < 1)) { $y *= $params{height}; }
  return($x,$y);
}

sub btIP_changeColor {
  my($file,$oldcolor,$newcolor) = @_;
  Log3(undef,4,"InfoPanel: read file $file for changeColor");
  my ($counter,$data) = btIP_FileRead($file);
  return unless $counter;
  if($newcolor =~ /[[:xdigit:]]{6}/) {
     Log3(undef,4,"InfoPanel: changing color from $oldcolor to $newcolor");
     $data =~ s/fill="#$oldcolor"/fill="#$newcolor"/g;
     $data =~ s/fill:#$oldcolor/fill:#$newcolor/g;
  } else {
     Log3(undef,4,"InfoPanel: invalid rgb value for changeColor!");
  }
  return $data;
}

sub btIP_FileRead {
   my ($file) = @_;
   my ($data,$counter);

   Log3(undef,4,"InfoPanel: looking for img $file");

   if(configDBUsed()){
      Log3(undef,4,"InfoPanel: reading from configDB");
      ($data,$counter) = _cfgDB_Fileexport($file,1);
      Log3(undef,4,"InfoPanel: file not found in database") unless $counter;
   }
   
   if(!$counter) {
      Log3(undef,4,"InfoPanel: reading from filesystem");
      my $length = -s "$file";
      open(GRAFIK, "<", $file) or die("File not found $!");
      binmode(GRAFIK);
      $counter = read(GRAFIK, $data, $length);
      close(GRAFIK);
      Log3(undef,4,"InfoPanel: file not found in filesystem") unless $counter;
   }
   return "" unless $counter;
   Log3(undef,4,"InfoPanel: file found.");
   return ($counter,$data);
}

##################
#
# create SVG content
#

sub btIP_returnSVG {
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
  my $bgcolor = AnalyzePerlCommand(undef,AttrVal($name,'bgcolor','"000000"'));
  my $output = "";
  our $svg = "";

  eval {

    $svg  = "\n<svg \n".
            "xmlns=\"http://www.w3.org/2000/svg\"\nxmlns:xlink=\"http://www.w3.org/1999/xlink\"\n".
            "width=\"".$width."px\" height=\"".$height."px\" \n".
            "viewPort=\"0 0 $width $height\"\n".
            "style=\"stroke-width: 0px; ";
    $svg .= "background-color:$bgcolor; " unless $bgcolor eq 'none';

    # set the background
    # check if background directory is set
    my $reason= "?"; # remember reason for undefined image
    my $bgdir= AnalyzePerlCommand(undef,AttrVal($name,"bgdir",undef));
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

		if(opendir(BGDIR, $bgdir)){
			my @bgfiles= grep {$_ !~ /^\./} readdir(BGDIR);
			closedir(BGDIR);
			if($#bgfiles>=0) {
				if($bgnr > $#bgfiles) { $bgnr= 0; }
				$defs{$name}{fhem}{bgnr}= $bgnr;
				my $bgfile     = $bgdir . "/" . $bgfiles[$bgnr];
				my $info       = image_info($bgfile);
				my $bgwidth    = $info->{width};
  				my $bgheight   = $info->{height};
                my ($u,$v)     = ($bgwidth/$width, $bgheight/$height);
                my $scale      = ($u>$v) ? 1/$u : 1/$v;
                my ($bgx,$bgy) = (0,0);
                   $bgx        = ($width - $bgwidth/$u)/2   if AttrVal($name,'bgcenter',1);
                   $bgy        = ($height - $bgheight/$u)/2 if AttrVal($name,'bgcenter',1);
                   $output     = btIP_itemImg('-',$bgx,$bgy,$scale,'file',$bgfile,undef);
                my $opacity    = AttrVal($name,'bgopacity',1);
                   $output    =~ s/<image\ /<image\ opacity="$opacity" /;
 			}
 		} # end opendir()
	} # end defined()

    $svg .= "\" >\n";
    $svg .= "$output\n";
    $svg = btIP_evalLayout($svg, $name, $defs{$name}{fhem}{layout});

    readingsSingleUpdate($defs{$name},'state',localtime(),1);
#    $defs{$name}{STATE} = localtime();

  }; #warn $@ if $@;
  if($@) {
    my $msg= $@;
    chomp $msg;
    Log3($name, 2, $msg);
  }

  $svg .= "Sorry, your browser does not support inline SVG.\n</svg>\n";

  return $svg;

}

sub btIP_evalLayout {
  my ($svg,$name,$layout)= @_;
  my ($width,$height)= split(/x/, AttrVal($name,"size","800x600"));
  my @layout= split("\n", $layout);

  my %pstack;
  my $pstackcount = 0;
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
  $params{boxcolor} = undef;
  $params{padding} = 0;
  $params{xx}= 0;
  $params{yy}= 0;
  $params{fontstyle}      = "initial";
  $params{fontweight}     = "normal";
  $params{textdecoration} = "none";

  $defs{$name}{fhem}{div} = undef;  

  my ($id,$x,$y,$x1,$y1,$x2,$y2,$r1,$r2);
  my ($scale,$inline,$boxwidth,$boxheight,$boxcolor);
  my ($text,$link,$imgtype,$srctype,$arg,$format,$filled,$stroked);
  
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
#	Debug "$name: evaluating >$line<";
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
$pstackcount++;
while ( my ($key, $value) = each(%params) ) {
        $pstack{$pstackcount}{$key} = $value;
    }
}

when("pop") {
while ( my ($key, $value) = each($pstack{$pstackcount}) ) {
        $params{$key} = $value;
    }
delete $pstack{$pstackcount};
$pstackcount--;
}

	    when("area") {
	      ($id,$x1,$y1,$x2,$y2,$link)= split("[ \t]+", $def, 6);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
	      $link = AnalyzePerlCommand(undef,$link);
          $params{xx} = $x;
          $params{yy} = $y;
	      $svg .= btIP_itemArea($id,$x1,$y1,$x2,$y2,$link,%params);
	    }

        when("boxcolor"){
	      $def = "\"$def\"" if(length($def) == 6 && $def =~ /[[:xdigit:]]{6}/);
	      $params{boxcolor} = AnalyzePerlCommand(undef, $def);
	    }

        when("button") {
	      ($id,$x1,$y1,$x2,$y2,$r1,$r2,$link,$text)= split("[ \t]+", $def, 9);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
          $params{xx} = $x;
          $params{yy} = $y;
          $link = AnalyzePerlCommand(undef,$link);
          $link = (length($link)) ? $link : "-$params{name}.html";
          $text = AnalyzePerlCommand(undef,$text);
	      $svg .= btIP_itemButton($id,$x1,$y1,$x2,$y2,$r1,$r2,$link,$text,%params);
        }
	    
        when("buttonpanel"){
           $defs{$params{name}}{fhem}{div} .= "<div id=\"hiddenDiv\" ".
              "style=\"display:none\" >".
              "<iframe id=\"secretFrame\" name=\"secret\" src=\"\"></div>\n";
        }

	    when("circle") {
	      ($id,$x1,$y1,$r1,$filled,$stroked,$link)= split("[ \t]+", $def, 7);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      $filled  //= 0; 
	      $stroked //= 0;
          $link = AnalyzePerlCommand(undef,$link);
	      $svg .= btIP_itemCircle($id,$x1,$y1,$r1,$filled,$stroked,$link,%params);
	    }
	    
	    when("counter") {
	      ($id,$x,$y)= split("[ \t]+", $def, 3);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemCounter($id,$x,$y,%params);
	    }
	    
	    when("date") {
	      ($id,$x,$y)= split("[ \t]+", $def, 3);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemDate($id,$x,$y,%params);
	    }
	    
	    when("ellipse") {
	      ($id,$x1,$y1,$r1,$r2,$filled,$stroked,$link)= split("[ \t]+", $def, 8);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      $filled  //= 0;
	      $stroked //= 0;
          $link = AnalyzePerlCommand(undef,$link);
	      $svg .= btIP_itemEllipse($id,$x1,$y1,$r1,$r2,$filled,$stroked,$link,%params);
	    }
	    
	    when("font") {
          $params{font} = $def;
        }

	    when("group") {
	      ($id,$text,$x,$y) = split("[ \t]+", $def, 4);
	      $x //= 0;
	      $y //= 0;
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemGroup($id,$text,$x,$y);
        }

	    when("img") {
	      ($id,$x,$y,$scale,$srctype,$arg,$link)= split("[ \t]+", $def,7);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y; 
	      $arg  = AnalyzePerlCommand(undef, $arg);
          $link = AnalyzePerlCommand(undef,$link);
          $svg .= btIP_itemImg($id,$x,$y,$scale,$srctype,$arg,$link,%params);
	    }
	    
        when("line") {
	      ($id,$x1,$y1,$x2,$y2,$format)= split("[ \t]+", $def, 6);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
	      $format //= 1; # set format to 1 as default thickness for the line
	      $svg .= btIP_itemLine($id,$x1,$y1,$x2,$y2, $format,%params);
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
	      ($id,$x1,$y1,$x2,$y2,$r1,$r2,$filled,$stroked,$link)= split("[ \t]+", $def, 10);
	      ($x1,$y1)= btIP_xy($x1,$y1,%params);
	      ($x2,$y2)= btIP_xy($x2,$y2,%params);
          $params{xx} = $x;
          $params{yy} = $y;
	      $filled  //= 0; # set 0 as default (not filled)
          $stroked //= 0; # set 0 as default (not stroked)
          $link = AnalyzePerlCommand(undef,$link);
	      $svg .= btIP_itemRect($id,$x1,$y1,$x2,$y2,$r1,$r2,$filled,$stroked,$link,%params);
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
          ($id,$x,$y,$boxwidth,$boxheight,$link,$text)= split("[ \t]+", $def, 7);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $text =  AnalyzePerlCommand(undef, $text);
	      $text =~ s/\n/<br\/>/g;
          $link =  AnalyzePerlCommand(undef, $link);
	      $svg .= btIP_itemTextBox($id,$x,$y,$boxwidth,$boxheight,$text,$link,%params);
          $params{xx} = $x;
          $params{yy} = $y + $boxheight;
        }
        
        when("textboxalign") {
          $params{tbalign} = $def;
        }
        
        when("textdesign") {
          my @args   = split(/,/,$def);
          my @deco   = qw(underline overline line-through); #text-decoration
          my @style  = qw(italic oblique); #font-style
          my @weight = qw(bold); #font-weight
          $params{fontstyle}      = "initial";
          $params{fontweight}     = "initial";
          $params{textdecoration} = "none";

          foreach my $s (@args) {
             if($s ne 'clear') {
                $params{fontstyle}      = "$s " if($s ~~ @style);
                $params{fontweight}     = "$s " if($s ~~ @weight);
                $params{textdecoration} = "$s " if($s ~~ @deco);
             }
          }
        }

	    when("time") {
	      ($id,$x,$y)= split("[ \t]+", $def, 3);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $svg .= btIP_itemTime($id,$x,$y,%params);
	    }

	    when("trash") {
	      ($id,$x,$y,$scale,$r1,$r2,$link)= split("[ \t]+", $def,7);
	      ($x,$y)= btIP_xy($x,$y,%params);
	      $params{xx} = $x;
	      $params{yy} = $y;
	      $r1 = AnalyzePerlCommand(undef,$r1);
	      $r2 = AnalyzePerlCommand(undef,$r2);
          $link = AnalyzePerlCommand(undef,$link);
          $svg .= btIP_itemTrash($id,$x,$y,$scale,$r1,$r2,$link,%params);
	    }
	    
	    default {
          if($cmd ~~ @cmd_halign) {
	        my $d = AnalyzePerlCommand(undef, $def);
            if($d ~~ @valid_halign) { 
              $params{ihalign}= $d unless($cmd eq "thalign");
              $params{thalign}= $d unless($cmd eq "ihalign");
            } else {
              Log3($name, 2, "InfoPanel: $name Illegal horizontal alignment $d");
            }
          } elsif($cmd ~~ @cmd_valign) {
            my $d = AnalyzePerlCommand(undef, $def);
            if( $d ~~ @valid_valign) {
              $params{ivalign}= $d unless($cmd eq "tvalign");
              $params{tvalign}= $d unless($cmd eq "ivalign");
            } else {
              Log3($name, 2, "InfoPanel: $name: Illegal vertical alignment $d");
            }
          } else {
            Log3($name, 2, "InfoPanel $name: Illegal command $cmd in layout definition.");
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

sub btIP_addExtension {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = "+$link";
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
    if($ext eq "png") {
          return btIP_returnPNG($name);
    }
    if($ext eq "info" || $ext eq "html") {
          return btIP_returnHTML($name);
    }
  } else {
    return btIP_Overview();
  }

}

sub btIP_splitRequest {

  my ($request) = @_;

  if($request =~ /^.*\/btip$/) {
    # http://localhost:8083/fhem/btip
    return (undef,undef); # name, ext
  } else {
    my $call= $request;
    $call =~ s/^.*\/btip\/([^\/]*)$/$1/;
    my $name= $call;
    $name =~ s/^(.*)\.(png|svg|info|html)$/$1/;
    my $ext= $call;
    $ext =~ s/^$name\.(.*)$/$1/;
    return ($name,$ext);
  }
}

####################
#
# HTML Stuff
#

sub btIP_returnHTML {
  my ($name) = @_;

#  my $url     = btIP_getURL();
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

sub btIP_HTMLHead {
  my ($title,$refresh) = @_;
  
#  my $doctype= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
#  my $xmlns= 'xmlns="http://www.w3.org/1999/xhtml"';
  my $doctype= '<?xml version="1.0" encoding="utf-8" standalone="no"?> '."\n".
               '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '.
               '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">'."\n";
  my $xmlns= "";

  my $r= (defined($refresh) && $refresh) ? "<meta http-equiv=\"refresh\" content=\"$refresh\"/>\n" : "";
  # css and js header output should be coded only in one place
  my $css= "";
  my $scripts= btIP_getScript();
  my $meta = "<meta charset=\"UTF-8\">\n";
  my $code= "$doctype\n<html $xmlns>\n<head>\n<title>$title</title>\n$meta$r$css$scripts</head>\n";
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
        $url= btIP_getURL();
        $html.= "$name<br>\n<ul>";
        $html.= "<a href='$url/btip/$name.html' target='_blank'>HTML</a><br>\n";
        $html.= "</ul>\n<p>\n";
        }
  }
  $html.="</body>\n" . btIP_HTMLTail();

  return ("text/html; charset=utf-8", $html);
}

sub btIP_getURL {
  my $proto = (AttrVal($FW_wname, 'HTTPS', 0) == 1) ? 'https' : 'http';
  return $proto."://$FW_httpheader{Host}$FW_ME";
}

1;
 
#

=pod
=begin html

<a name="InfoPanel"></a>
<h3>InfoPanel</h3>

<ul><b>!!! This module is "under development" as of 2015-02-06 !!!</b><br/>
Please read <a href="http://forum.fhem.de/index.php/topic,32828.0.html" target="_blank">&gt;&gt;&gt; the development thread &lt;&lt;&lt;</a> in fhem forum for actual informations.</ul>
<br/>

<ul>
    InfoPanel is an extension to <a href="#FHEMWEB">FHEMWEB</a>. You must install FHEMWEB to use InfoPanel.<br/>
    <br/>
    <br/>
	<b>Prerequesits</b><br/>
	<br/>
	<ul>
	  <li>InfoPanel is an extension to <a href="#FHEMWEB">FHEMWEB</a>. You must install FHEMWEB to use InfoPanel.</li>
	  <br/>
	  <li>Module uses following additional Perl modules:<br/><br/>
		<ul><code>MIME::Base64 Image::Info</code></ul><br/>
		If not already installed in your environment, please install them using appropriate commands from your environment.<br/><br/>
		Package installation in debian environments: <code>apt-get install libmime-base64-perl libimage-info-perl</code></li>
	  <br/>
	  <li>You can use this module without the two additional perl modules, but in this case, you have to accept some limitations:<br/>
	      <br/>
	      <ul>
	         <li>layout tag img can not be used</li>
	         <li>layout tag trash can not be used</li>
	         <li>layout tag plot can only handle scale = 1 and inline = 0</li>
	      </ul>
	  </li>
	</ul>
	<br/><br/>
	
	<a name="InfoPaneldefine"></a>
	<b>Define</b><br/><br/>
    <ul>
       <code>define &lt;name&gt; InfoPanel &lt;layoutFileName&gt;</code><br/>
       <br/>
       Example:<br/><br>
       <ul><code>define myInfoPanel InfoPanel ./FHEM/panel.layout</code><br/></ul>
    </ul>
	<br/><br/>

	<a name="InfoPanelset"></a>
	<b>Set-Commands</b><br/><br/>
    <ul>
       <code>set &lt;name&gt; reread</code>
       <ul><br/>
          Rereads the <a href="#InfoPanellayout">layout definition</a> from the file.<br/><br/>
          <b>Important:</b><br/>
          <ul>
             Layout will be reread automatically if edited via fhem's "Edit files" function.<br/>
             Autoread can be disabled via <a href="#InfoPanelattr">attribute</a>.
          </ul>
       </ul>
    </ul>
	<br/><br/>

	<a name="InfoPanelget"></a>
	<b>Get-Commands</b><br/><br/>
	<ul>
	   n/a<br/>
	</ul>
	<br/><br/>

	<a name="InfoPanelattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>autoreread</b> - disables automatic layout reread after edit if set to 1</li>
		<li><b>refresh</b> - time (in seconds) after which the HTML page will be reloaded automatically</li>
		<li><b>size</b> - The dimensions of the picture in the format
            <code>&lt;width&gt;x&lt;height&gt;</code></li>
		<li><b>title</b> - webpage title to be shown in Browser</li>
		<br/>
		<li><b>bgcenter</b> - background images will not be centered if attribute set to 0. Default: show centered</li>
		<li><b>bgcolor</b> - defines the background color, use html-hexcodes to specify color, eg 00FF00 for green background. Default color is black. You can use bgcolor=none to disable use of any background color</li>
		<li><b>bgdir</b> - directory containing background images</li>
		<li><b>bgopacity</b> - set opacity for background image, values 0...1.0</li>
		<li><b>tmin</b> - background picture will be shown at least <code>tmin</code> seconds, 
		    no matter how frequently the RSS feed consumer accesses the page.</li>
		<br/>
		<b>Important:</b> bgcolor and bgdir will be evaluated by <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> use quotes for absolute values!<br/>
	</ul>
	<br/><br/>

    <a name="InfoPanelreadings"></a>
	<b>Generated Readings/Events:</b><br/><br/>
	<ul>
	   <li>state - show time and date of last layout evaluation</li>
	</ul>
	<br/><br/>

    <a name="InfoPanellayout"></a>
	<b>Layout definition</b><br/>
	<br/>
	<ul>
       All parameters in curly brackets can be evaluated by <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code></br>
       <br/>
       <li><code>area &lt;id&gt; &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; &lt;{link}&gt;</code><br/>
           <br/>
           <ul>create a responsive area which will call a link when clicked.<br/>
               <br/>
               id = element id<br/>
               x1,y1 = upper left corner<br/>
               x2,y2 = lower right corner<br/>
               link = url to be called<br/>
           </ul></li><br/>
       <br>
       <li><code>boxcolor &lt;{rgba}&gt;</code><br/>
           <br/>
           <ul>define an rgb color code to be used for filling button and textbox<br/>
           </ul></li><br/>
       <br>
       <li><code>button &lt;id&gt; &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; &lt;r1&gt; &lt;r2&gt; &lt;link&gt; &lt;text&gt;</code><br/>
           <br/>
           <ul>create a responsive colored button which will call a link when clicked.<br/>
               <br/>
               id = element id<br/>
               x1,y1 = upper left corner<br/>
               x2,y2 = lower right corner<br/>
               r1,r2 = radius for rounded corners<br/>
               link  = url to be called<br/>
               text  = text that will be written onto the button<br/>
               <br/>
               button will be filled with color defined by "boxcolor"<br/>
               text color will be read from "rgb" value<br/>
           </ul></li><br/>
       <br/>
       <li><code>buttonpanel</code><br/>
           <br/>
           <ul>needed once in your layout file if you intend to use buttons in the same layout.<br/>
           </ul></li><br/>
       <br/>
       <li><code>circle &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;r&gt; [&lt;fill&gt;] [&lt;stroke-width&gt;] [&lt;link&gt;]</code><br/>
           <br/>
           <ul>create a circle<br/>
               <br/>
               id = element id<br/>
               x,y = center coordinates of circle<br/>
               r = radius<br/>
               fill = circle will be filled with "rgb" color if set to 1. Default = 0<br/>
               stroke-width = defines stroke width to draw around the circle. Default = 0<br/>
               link = URL to be linked to item<br/>
           </ul></li><br/>
       <br/>
       <li><code>counter &lt;id&gt; &lt;x&gt; &lt;y&gt;</code><br/>
           <br/>
           <ul>print internal counter<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
           </ul></li><br/>
       <br/>
       <li><code>date &lt;id&gt; &lt;x&gt; &lt;y&gt;</code><br/>
           <br/>
           <ul>print date<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
           </ul></li><br/>
       <br/>
       <li><code>ellipse &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;r1&gt; &lt;r2&gt; [&lt;fill&gt;] [&lt;stroke-width&gt;] [&lt;link&gt;]</code><br/>
           <br/>
           <ul>create an ellipse<br/>
               <br/>
               id = element id<br/>
               x,y = center coordinates of circle<br/>
               r1,r2 = radius<br/>
               fill = ellipse will be filled with "rgb" color if set to 1. Default = 0<br/>
               stroke-width = defines stroke width to draw around the ellipse. Default = 0<br/>
               link = URL to be linked to item<br/>
           </ul></li><br/>
       <br/>
       <li><code>font &lt;font-family&gt;</code><br/>
           <br/>
           <ul>define font family used for text elements (text, date, time, seconds ...)<br/>
               <br/>
               Example: <code>font arial</code><br/>
           </ul></li><br/>
       <br/>
       <li><code>group &lt;id&gt; open &lt;x&gt; &lt;y&gt;<br/>
                 group - close</code>&nbsp;&nbsp;(id will not be evaluated, just give any value)<br/>
           <br/>
           <ul>group items<br/>
               <br/>
               open|close = define start and end of group<br/>
               x,y = upper left corner as reference for all grouped items, will be inherited to all elements.<br/>
               <br/>
               Examples:<br/>
               <code>
                 group - open 150 150<br/>
                 rect ...<br/>
                 img ...<br/>
                 group - close<br/>
               </code>
           </ul></li><br/>
       <br/>
       <li><code>img &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;scale&gt; &lt;sourceType&gt; &lt;{dataSource}&gt; [&lt;link&gt;]</code><br/>
           <br/>
           <ul>embed an image into InfoPanel<br/>
               <br/>
               id = element id<br/>
               x,y = upper left corner<br/>
               scale = scale to be used for resizing; may be factor or defined by width or height<br/>
               sourceType = file | url | data<br/>
               dataSource = where to read data from, depends on sourceType<br/>
               link = URL to be linked to item<br/>
           </ul></li><br/>
       <br/>
       <li><code>line &lt;id&gt; &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; [&lt;stroke&gt;]</code><br/>
           <br/>
           <ul>draw a line<br/>
               <br/>
               id = element id<br/>
               x1,y1 = coordinates (start)<br/>
               x2,y2 = coordinates (end)<br/>
               stroke = stroke width for line; if omitted, default = 0<br/>
           </ul></li><br/>
       <br/>
       <li><code>moveby &lt;x&gt; &lt;y&gt;</code><br/>
           <br/>
           <ul>move most recently x- and y-coordinates by given steps<br/>
           </ul></li><br/>
       <br/>
       <li><code>moveto &lt;x&gt; &lt;y&gt;</code><br/>
           <br/>
           <ul>move x- and y-coordinates to the given positon<br/>
           </ul></li><br/>
       <br/>
       <li><code>padding &lt;width&gt;</code><br/>
           <br/>
           <ul>border width (in pixel) to be used in textboxes<br/>
           </ul></li><br/>
       <br/>
       <li><code>plot &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;scale&gt; &lt;inline&gt; &lt;{plotName}&gt;</code><br/>
           <br/>
           <ul>embed an SVG plot into InfoPanel<br/>
               <br/>
               id = element id<br/>
               x,y = upper left corner<br/>
               scale = scale to be used for resizing; may be factor or defined by width or height<br/>
               inline = embed plot as data (inline=1) or as link (inline=0)<br/>
               plotName = name of desired SVG device from your fhem installation<br/>
           </ul></li><br/>
       <br/>
       <li><code>pt &lt;[+-]font-size&gt;</code><br/>
           <br/>
           <ul>define font size used for text elements (text, date, time, seconds ...)<br/>
               can be given as absolute or relative value.<br/>
               <br/>
               Examples:<br/>
               <code>pt 12</code><br/>
               <code>pt +3</code><br/>
               <code>pt -2</code><br/>
           </ul></li><br/>
       <br/>
       <li><code>rect &lt;id&gt; &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; &lt;r1&gt; &lt;r2&gt; [&lt;fill&gt;] [&lt;stroke-width&gt;] [&lt;link&gt;]</code><br/>
           <br/>
           <ul>create a rectangle<br/>
               <br/>
               id = element id<br/>
               x1,y1 = upper left corner<br/>
               x2,y2 = lower right corner<br/>
               r1,r2 = radius for rounded corners<br/>
               fill = rectangle will be filled with "rgb" color if set to 1. Default = 0<br/>
               stroke-width = defines stroke width to draw around the rectangle. Default = 0<br/>
               link = URL to be linked to item<br/>
           </ul></li><br/>
       <br/>
       <li><code>rgb &lt;{rgb[a]}&gt;</code><br/>
           <br/>
           <ul>define rgba value (hex digits!) used for text, lines, circles, ellipses<br/>
               <br/>
               <code>r = red value</code><br/>
               <code>g = green value</code><br/>
               <code>b = blue value</code><br/>
               <code>a = alpha value used for opacity; optional</code><br/>
           </ul></li><br/>
       <br/>
       <li><code>seconds &lt;id&gt; &lt;x&gt; &lt;y&gt; [&lt;format&gt;]</code><br/>
           <br/>
           <ul>print seconds<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
               format = seconds will be preceeded by ':' if set to 'colon'; optional<br/>
           </ul></li><br/>
       <br/>
       <li><code>text &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;{text}&gt;</code><br/>
           <br/>
           <ul>print text<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
               text = text content to be printed<br/>
           </ul></li><br/>
       <br/>
       <li><code>textbox &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;boxWidth&gt; &lt;boxHeight&gt; &lt;{link}&gt; &lt;{text}&gt; </code><br/>
           <br/>
           <ul>create a textbox to print text with auto wrapping<br/>
               <br/>
               id = element id<br/>
               x,y = upper left corner<br/>
               boxWidth,boxHeight = dimensions of textbox<br/>
               link = url to be used when clicked; use "" if not needed<br/>
               text = text to be printed in textbox<br/>
               <br/>
               <b>Important:</b> textboxes are not responsive via area tag. Use optional link parameter in textbox tag<br/>
           </ul></li><br/>
       <br/>
       <li><code>textboxalign &lt;align&gt;</code><br/>
           <br/>
           <ul>define horizontal alignment for text inside textboxes<br/>
               <br/>
               valid values: left center right justify<br/>
           </ul></li><br/>
       <br/>
       <li><code>textdesign &lt;align&gt;</code><br/>
           <br/>
           <ul>define comma-separated list for text design and decoration<br/>
               <br/>
               valid values: underline overline line-through bold italic oblique clear<br/>
               <br/>
               Examples:<br/>
               <code>
               textdesign underline<br/>
               textdesign bold,italic,underline
               </code><br/>
               <br/>
               <b>Important:</b> "clear" resets all to default values!<br/>
           </ul></li><br/>
       <br/>
       <li><code>thalign &lt;align&gt;</code><br/>
           <br/>
           <ul>define horizontal alignment for text output<br/>
               <br/>
               valid values: start middle end<br/>
           </ul></li><br/>
       <br/>
       <li><code>time &lt;id&gt; &lt;x&gt; &lt;y&gt;</code><br/>
           <br/>
           <ul>print time<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
           </ul></li><br/>
       <br/>

       <li><code>trash &lt;id&gt; &lt;x&gt; &lt;y&gt; &lt;scale&gt; &lt;{foregroundColor}&gt; &lt;{backgroundColor}&gt; [&lt;link&gt;]</code><br/>
           <br/>
           <ul>print a trashcan with selectable colors for foreground and background<br/>
               <br/>
               id = element id<br/>
               x,y = position<br/>
               scale = scale to be used for resizing; may be factor or defined by width or height<br/>
               foregroundColor = hex digits used for foreground<br/>
               backgroundColor = hex digits used for background<br/>
               link = URL to be linked to item<br/>
           </ul></li><br/>
       <br/>
       <li><code>tvalign &lt;align&gt;</code><br/>
           <br/>
           <ul>define vertical alignment for text output<br/>
               <br/>
               valid values: auto baseline middle center hanging<br/>
           </ul></li><br/>
       <br/>

	</ul>
	<br/>

	<b>Author's notes</b><br/>
	<br/>
	<ul>
		<li>Have fun!</li><br/>
	</ul>
</ul>

=end html
=begin html_DE

<a name="InfoPanel"></a>
<h3>InfoPanel</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='commandref.html#InfoPanel'>InfoPanel</a><br/>
</ul>
=end html_DE
=cut
