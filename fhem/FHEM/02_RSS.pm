#
#
# 02_RSS.pm
# written by Dr. Boris Neubert 2012-03-24
# e-mail: omega at online dot de
#
##############################################
# $Id$

package main;
use strict;
use warnings;
use GD;
use vars qw(%data);
use HttpUtils;

# we can 
# use vars qw(%FW_types);  # device types,
# use vars qw($FW_RET);    # Returned data (html)
# use vars qw($FW_wname);  # Web instance
# use vars qw($FW_subdir); # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
# use vars qw(%FW_pos);    # scroll position
# use vars qw($FW_cname);  # Current connection name

#########################
sub
RSS_addExtension($$$) {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = $link;
    $data{FWEXT}{$url}{NAME} = $friendlyname;
}

##################
sub
RSS_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}   = "RSS_Define";
    #$hash->{AttrFn}  = "RSS_Attr";
    $hash->{AttrList}= "loglevel:0,1,2,3,4,5 size bg tmin";
    $hash->{SetFn}   = "RSS_Set";


    RSS_addExtension("RSS_CGI","rss","RSS");

    return undef;
 }

##################
sub
RSS_readLayout($) {

  my ($hash)= @_;
  my $filename= $hash->{fhem}{filename};
  my $name= $hash->{NAME};

  if(open(LAYOUT, $filename)) {
    my @layout= <LAYOUT>;
    $hash->{fhem}{layout}= join("", @layout);
    close(LAYOUT);
  } else {
    $hash->{fhem}{layout}= ();
    Log 1, "RSS $name: Cannot open $filename";
  }
}  
 
##################
sub
RSS_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def);

  return "Usage: define <name> RSS jpg hostname filename"  if(int(@a) != 5);
  my $name= $a[0];
  my $style= $a[2];
  my $hostname= $a[3];
  my $filename= $a[4];

  $hash->{fhem}{style}= $style;
  $hash->{fhem}{hostname}= $hostname;
  $hash->{fhem}{filename}= $filename;

  RSS_readLayout($hash);
  
  $hash->{STATE} = $name;
  return undef;
}

##################
sub
RSS_Set() {

  my ($hash, @a) = @_;
  my $name = $a[0];

  # usage check
  my $usage= "Unknown argument, choose one of rereadcfg:noArg";
  if((@a == 2) && ($a[1] eq "rereadcfg")) {
     RSS_readLayout($hash);
     return undef;
  } else {
    return $usage;
  }
}

####################
# 
sub
RSS_getURL($) {
  my ($hostname)= @_;
  # http://hostname:8083/fhem
  return "http://$hostname:" . $defs{$FW_wname}{PORT} . $FW_ME;
}

# ##################
# sub
# RSS_Attr(@)
# {
#   my @a = @_;
#   my $attr= $a[2];
# 
#   if($a[0] eq "set") {  # set attribute
#     if($attr eq "bgdir") {
#     }
#   }
#   elsif($a[0] eq "del") { # delete attribute
#     if($attr eq "bgdir") {
#     }
#   }
# 
#   return undef;
# 
# }

##################
# list all RSS devices
sub
RSS_Overview {

  my ($name, $url);
  my $html= "<body>\n";
  foreach my $def (sort keys %defs) {
    if($defs{$def}{TYPE} eq "RSS") {
        $name= $defs{$def}{NAME};
        $url= RSS_getURL($defs{$def}{fhem}{hostname});
        $html.= " <a href='$url/rss/$name.rss'>$name</a><br>\n";
        }
  }
  $html.="</body>";

  return ("text/html; charset=utf-8", $html);
}

##################
sub
RSS_splitRequest($) {

  # http://hostname:8083/fhem/rss
  # http://hostname:8083/fhem/rss/myDeviceName.rss
  # http://hostname:8083/fhem/rss/myDeviceName.jpg
  # |--------- url ----------|     |---name --| ext

  my ($request) = @_;

  if($request =~ /^.*\/rss$/) {
    # http://localhost:8083/fhem/rss
    return (undef,undef); # name, ext
  } else {
    # http://hostname:8083/fhem/rss/myDeviceName.rss
    # http://hostname:8083/fhem/rss/myDeviceName.jpg
    my $call= $request;
    $call =~ s/^.*\/rss\/([^\/]*)$/$1/;
    my $name= $call;
    $name =~ s/^(.*)\.(jpg|rss)$/$1/;
    my $ext= $call;
    $ext =~ s/^$name\.(.*)$/$1/;
    return ($name,$ext);
  }
}

##################
sub
RSS_returnRSS($) {
  my ($name) = @_;

  my $url= RSS_getURL($defs{$name}{fhem}{hostname});
 
  my $code= "<rss version='2.0' xmlns:media='http://search.yahoo.com/mrss/'><channel><title>$name</title><ttl>1</ttl><item><media:content url='$url/rss/$name.jpg' type='image/jpeg'/></item></channel></rss>";
  
  return ("application/xml; charset=utf-8", $code);
}

##################
# Library
##################

sub
RSS_xy($$$) {
  my ($S,$x,$y)= @_;
  if($x<=1) { $x*= $S->width; }
  if($y<=1) { $y*= $S->height; }
  return($x,$y);
}

sub
RSS_color {
  my ($S,$rgb)= @_;
  my @d= split("", $rgb);
  return $S->colorResolve(hex("$d[0]$d[1]"),hex("$d[2]$d[3]"),hex("$d[4]$d[5]"));
}

sub
RSS_itemText {
  my ($S,$x,$y,$text,%params)= @_;
  return unless(defined($text));
  ($x,$y)= RSS_xy($S,$x,$y);
  $S->stringFT(RSS_color($S,$params{rgb}),$params{font},$params{pt},0,$x,$y,$text);
}

sub
RSS_itemTime {
  my ($S,$x,$y,%params)= @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  RSS_itemText($S,$x,$y,sprintf("%02d:%02d", $hour, $min),%params);
}
sub
RSS_itemSeconds {
   my ($S,$x,$y,$format,%params)= @_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  if ($format eq "colon")
  {
    RSS_itemText($S,$x,$y,sprintf(":%02d", $sec),%params);
  }
  else
  {
     RSS_itemText($S,$x,$y,sprintf("%02d", $sec),%params);
  }
}
sub
RSS_itemDate {
  my ($S,$x,$y,%params)= @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
 RSS_itemText($S,$x,$y,sprintf("%02d.%02d.%04d", $mday, $mon+1, $year+1900),%params);

}

sub
RSS_itemImg {
  my ($S,$x,$y,$scale,$imgtype,$srctype,$arg,%params)= @_;
  return if($arg eq "");
  my $I;
  if($srctype eq "url") {
    my $data = GetFileFromURL($arg,3,undef,1);
    if($imgtype eq "gif") {
      $I= GD::Image->newFromGifData($data);
    } elsif($imgtype eq "png") {
      $I= GD::Image->newFromPngData($data);
    } elsif($imgtype eq "jpeg") {
      $I= GD::Image->newFromJpegData($data);
    } else {
      return;
    }
  } elsif($srctype eq "file") {
    if($imgtype eq "gif") {
      $I= GD::Image->newFromGif($arg);
    } elsif($imgtype eq "png") {
      $I= GD::Image->newFromPng($arg);
    } elsif($imgtype eq "jpeg") {
      $I= GD::Image->newFromJpeg($arg);
    } else {
      return;
    }
  } else {
    return;
  }
  ($x,$y)= RSS_xy($S,$x,$y);
  my ($width,$height)= $I->getBounds();
  my ($swidth,$sheight)= (int($scale*$width), int($scale*$height));
  #Debug "RSS placing $arg ($swidth x $sheight) at ($x,$y)";
  Log 5, "RSS placing $arg ($swidth x $sheight) at ($x,$y)";
  $S->copyResampled($I,$x,$y,0,0,$swidth,$sheight,$width,$height);
}  

sub
RSS_itemLine {
  my ($S,$x1,$y1,$x2,$y2,%params)= @_;
  ($x1,$y1)= RSS_xy($S,$x1,$y1);
  ($x2,$y2)= RSS_xy($S,$x2,$y2);
  $S->line($x1,$y1,$x2,$y2,RSS_color($S,$params{rgb}));  
}

##################
sub
RSS_evalLayout($$@) {
  my ($S,$name,$layout)= @_;

  my @layout= split("\n", $layout);

  my %params;
  $params{font}= "Arial";
  $params{pt}= 12;
  $params{rgb}= "ffffff";

  my ($x,$y,$x1,$y1,$x2,$y2,$scale,$text,$imgtype,$srctype,$arg,$format);
  
  my $cont= "";
  foreach my $line (@layout) {
          # kill trailing newline
          chomp $line;
          # kill comments and blank lines
          $line=~ s/\#.*$//;
          $line=~ s/\s+$//;
          $line= $cont . $line;
          if($line=~ s/\\$//) { $cont= $line; undef $line; }
          next unless($line);
          $cont= "";
          #Log 5, "$name: evaluating >$line<";
          # split line into command and definition
          my ($cmd, $def)= split("[ \t]+", $line, 2);
          #Log 5, "CMD= \"$cmd\", DEF= \"$def\"";
          if($cmd eq "rgb") {
            $def= "\"$def\"" if(length($def) == 6 && $def =~ /[[:xdigit:]]{6}/);
            $params{rgb}= AnalyzePerlCommand(undef, $def);
          } elsif($cmd eq "font") {
            $params{font}= $def;
          } elsif($cmd eq "pt") {
            $params{pt}= $def;
          } elsif($cmd eq "text") {
            ($x,$y,$text)= split("[ \t]+", $def, 3);
            my $txt= AnalyzePerlCommand(undef, $text);
            #Log 5, "$name: ($x,$y) $txt";
            RSS_itemText($S,$x,$y,$txt,%params);
          } elsif($cmd eq "line") {
            ($x1,$y1,$x2,$y2)= split("[ \t]+", $def, 4);
            RSS_itemLine($S,$x1,$y1,$x2,$y2,%params);
          } elsif($cmd eq "time") {
            ($x,$y)= split("[ \t]+", $def, 2);
            RSS_itemTime($S,$x,$y,%params);
          } elsif($cmd eq "seconds") {
            ($x,$y,$format) = split("[ \+]", $def,3);
            RSS_itemSeconds($S,$x,$y,$format,%params);
          } elsif($cmd eq "date") {
            ($x,$y)= split("[ \t]+", $def, 2);
            RSS_itemDate($S,$x,$y,%params);
          }  elsif($cmd eq "img") {
            ($x,$y,$scale,$imgtype,$srctype,$arg)= split("[ \t]+", $def,6);
            my $arg= AnalyzePerlCommand(undef, $arg);
            RSS_itemImg($S,$x,$y,$scale,$imgtype,$srctype,$arg,%params);
          } else {
            Log 1, "$name: Illegal command $cmd in layout definition.";
          }  
            
  }
}

##################
sub
RSS_returnJPEG($) {
  my ($name)= @_;

  my ($width,$height)= split(/x/, AttrVal($name,"size","800x600"));

  #
  # increase counter
  #
  if(defined($defs{$name}{fhem}) && defined($defs{$name}{fhem}{counter})) {
    $defs{$name}{fhem}{counter}++;
  } else {
    $defs{$name}{fhem}{counter}= 1;
  }

  # true color
  GD::Image->trueColor(1);
  
  #
  # create the image
  #
  my $S;
  # let's create a blank image, we will need it in most cases. 
  $S= GD::Image->newTrueColor($width,$height);
  $S->colorAllocate(0,0,0); # black is the background

  # wrap to make problems with GD non-lethal

  eval {

    #
    # set the background
    #
    # check if background directory is set
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
		if(opendir(BGDIR, $bgdir)){
			my @bgfiles= grep {$_ !~ /^\./} readdir(BGDIR);
			closedir(BGDIR);
			# get item number
			if($#bgfiles>=0) {
				if($bgnr > $#bgfiles) { $bgnr= 0; }
				$defs{$name}{fhem}{bgnr}= $bgnr;
				my $bgfile= $bgdir . "/" . $bgfiles[$bgnr];
				my $bg= newFromJpeg GD::Image($bgfile);
				my ($bgwidth,$bgheight)= $bg->getBounds();
				if($bgwidth != $width or $bgheight != $height) {
					# we need to resize
					my ($w,$h);
					my ($u,$v)= ($bgwidth/$width, $bgheight/$height);
					if($u>$v) {
						$w= $width;
						$h= $bgheight/$u;
					} else {
						$h= $height;
						$w= $bgwidth/$v;
					}
					$S->copyResized($bg,($width-$w)/2,($height-$h)/2,0,0,$w,$h,$bgwidth,$bgheight);
				} else {
					# size is as required
					# kill the predefined image and take the original
					$S = undef;
					$S= $bg;
				}
			}
		}
	}
    #
    # evaluate layout
    #
    RSS_evalLayout($S, $name, $defs{$name}{fhem}{layout});

  }; warn $@ if $@;
    
  #
  # return jpeg image
  #
  return ("image/jpeg; charset=utf-8", $S->jpeg);
}
  
##################
#
# here we answer any request to http://host:port/fhem/rss and below
sub
RSS_CGI(){

  my ($request) = @_;   # /rss or /rss/name.rss or /rss/name.jpg

  my ($name,$ext)= RSS_splitRequest($request); # name, ext (rss, jpg)

  if(defined($name)) {
    if($ext eq "") {
          return("text/plain; charset=utf-8", "Illegal extension.");
    }
    if(!defined($defs{$name})) {
          return("text/plain; charset=utf-8", "Unknown RSS device: $name");
    }
  
    if($ext eq "jpg") {
          return RSS_returnJPEG($name);
    } elsif($ext eq "rss") {
          return RSS_returnRSS($name);
    }
  } else {
    return RSS_Overview();
  }

}


#

1;




=pod
=begin html

<a name="RSS"></a>
<h3>RSS</h3>
<ul>
  Provides a freely configurable RSS feed.<p>

  Currently a media RSS feed delivering status pictures in JPEG format is supported. This media
  RSS feed can be used to feed a status display to a network-enabled photo frame.<p>

  You need to have the perl module <code>GD</code> installed. This module is most likely not
  available for small systems like Fritz!Box.<p>
  RSS is an extension to <a href="#FHEMWEB">FHEMWEB</a>. You must install FHEMWEB to use RSS.</p>

  <a name="RSSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RSS jpg &lt;hostname&gt; &lt;filename&gt;</code><br><br>

    Defines the RSS feed. <code>jpg</code> is a fixed literal to allow for future
    extensions. <code>&lt;hostname&gt;</code> is the hostname of the fhem server as
    seen from the consumer of the RSS feed. <code>&lt;filename&gt;</code> is the
    name of the file that contains the <a href="RSSlayout">layout definition</a>.<p>

    Examples:
    <ul>
      <code>define FrameRSS RSS jpg host.example.org /etc/fhem/layout</code><br>
      <code>define MyRSS RSS jpg 192.168.1.222 /var/fhem/conf/layout.txt</code><br>
    </ul>
    <br>
  </ul>

  <a name="RSSset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; rereadcfg</code>
    <br><br>
    Rereads the <a href="RSSlayout">layout definition</a> from the file. Useful to enable
    changes in the layout on-the-fly.
    <br><br>
  </ul>

  <a name="RSSattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>size<br>The dimensions of the JPEG picture in the format
    <code>&lt;width&gt;x&lt;height&gt;</code>.</li><br>
    <li>bg<br>The directory that contains the background pictures (must be in JPEG format).</li><br>
    <li>tmin<br>The background picture is shown at least <code>tmin</code> seconds,
    no matter how frequently the RSS feed consumer accesses the page.</li><br>
  </ul>
  <br><br>

  <b>Usage information</b>
  <br><br>
  <ul>
  If a least one RSS feed is defined, the menu entry <code>RSS</code> appears in the FHEMWEB
  side menu. If you click it you get a list of all defined RSS feeds. The URL of any such is
  RSS feed is <code>http://hostname:port/fhem/rss/name.rss</code> with <code>hostname</code> and
  <code>name</code> from the RSS feed's <a href="RSSdefine">definition</a> and the <code>port</code>
  (usually 8083) and literal <code>/fhem</code> from the underlying <a href="#FHEMWEB">FHEMWEB</a>
  definition.<p>

  Example:
  <ul><code>http://host.example.org:8083/fhem/rss/FrameRSS.rss</code></ul><p>

  The media RSS feed points to a dynamically generated JPEG picture. The URL of the JPEG picture
  belonging to the RSS feed is <code>http://hostname:port/fhem/rss/name.jpg</code>, i.e. the URL
  of the RSS feed with the extension <code>rss</code> changed to <code>jpg</code>.<p>

  Example:
  <ul><code>http://host.example.org:8083/fhem/rss/FrameRSS.jpg</code></ul><p>

  To render the JPEG picture the current, or, if <code>tmin</code> seconds have elapsed, the next
  JPEG picture from the directory <code>bg</code> is chosen and scaled to the dimensions given
  in <code>size</code>. The background is black if no usable JPEG picture can be found. Next the
  script in the <a href="RSSlayout">layout definition</a> is used to superimpose items on
  the background.<p>

  You can directly access the URL of the JPEG picture in your browser. Reload the page to see
  how it works.<p>

  The media RSS feed advertises to refresh after 1 minute (ttl). Some photo frames ignore it and
  use their preset refresh rate. Go for a photo frame with an adjustable refresh rate (e.g
  every 5 seconds) if you have the choice!<p>

  This is how the fhem config part might look like:<p>
  <code>
  define ui FHEMWEB 8083 global<br><br>

  define FrameRSS RSS jpg host.example.org /etc/fhem/layout<br>
  attr FrameRSS size 800x600<br>
  attr FrameRSS bg /usr/share/pictures<br>
  attr FrameRSS tmin 10<br>
  </code>

  </ul>

  <a name="RSSlayout"></a>
  <b>Layout definition</b>
  <br><br>
  <ul>
    The layout definition is a script for placing items on the background. It is read top-down.
    It consists of layout control commands and items placement commands. Layout control
    commands define the appearance of subsequent items. Item placement commands actually
    render items.<p>

    Everything after a # is treated as a comment and ignored. You can fold long lines by
    putting a \ at the end.<p>

    <i>Layout control commands</i><p>
    <ul>
    <li>font &lt;font&gt;<br>Sets the font. &lt;font&gt; is the name of a TrueType font (e.g.
    <code>Arial</code>) or the full path to a TrueType font
    (e.g. <code>/usr/share/fonts/truetype/arial.ttf</code>),
    whatever works on your system.</li><br>

    <li>rgb &lt;color&gt;<br>Sets the color. &lt;color&gt; is a 6-digit hex number, every 2 digits
    determining the red, green and blue color components as in HTML color codes (e.g.
    <code>FF0000</code> for red, <code>C0C0C0</code> for light gray). You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;color&gt.</li><br>

    <li>pt &lt;pt&gt;<br>Sets the font size in points.</li><br>
    </ul>

    <i>Item placement commands</i><p>
    <ul>
    <li>text &lt;x&gt; &lt;y&gt; &lt;text&gt;<br>Renders the text &lt;text&gt; at the
    position (&lt;x&gt;, &lt;y&gt;) using the current font, font size and color.
    (0,0) is the upper left corner. Coordinates equal or
    greater than 1 are considered to be pixels, coordinates between 0 and 1 are considered to
    be relative to the total width or height of the picture. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;text&gt; to fully
    access device readings and do some programming on the fly. See below for examples.</li><br>

    <li>time &lt;x&gt; &lt;y&gt;<br>Renders the current time in HH:MM format.</li><br>
    <li>seconds &lt;x&gt; &lt;y&gt; &lt;format&gt<br>Renders the curent seconds. Maybe usefull for a RSS Clock. With option colon a : </li><br>
    <li>date &lt;x&gt; &lt;y&gt;<br>Renders the current date in DD:MM:YYY format.</li><br>
    <li>line &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt;<br>Draws a line from position (&lt;x1&gt;, &lt;y1&gt;) to position (&lt;x2&gt;, &lt;y2&gt;).</li><br>
    <li>img &lt;x&gt; &lt;y&gt; &lt;s&gt; &lt;imgtype&gt; &lt;srctype&gt; &lt;arg&gt; <br>Renders a picture at the
    position (&lt;x&gt;, &lt;y&gt;). The &lt;imgtype&gt; is one of <code>gif</code>, <code>jpeg</code>, <code>png</code>.
    The picture is scaled by the factor &lt;s&gt; (a decimal value). If &lt;srctype&gt; is <code>file</code>, the picture
    is loaded from the filename &lt;arg&gt;, if &lt;srctype&gt; is <code>url</code>, the picture
    is loaded from the URL &lt;arg&gt;. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;arg&gt. See below for example.
    Notice: do not load the image from URL that is served by fhem as it leads to a deadlock.<br></li>
    <br>
    </ul>

    This is how a layout definition might look like:<p>
    <code>
    font /usr/share/fonts/truetype/arial.ttf # must be a TrueType font<br>
    rgb c0c0c0 # HTML color notation, RGB<br>
    pt 48 # font size in points<br>
    time 0.10 0.90<br>
    pt 24<br>
    text 0.10 0.95 { ReadingsVal("MyWeather","temperature","?"). "C" }<br>
    img 20 530 0.5 png file { "/usr/share/fhem/www/images/weather/" . ReadingsVal("MyWeather","icon","") . ".png" }<br>
    </code>

  </ul>








</ul>


=end html
=cut
