#
#
# 02_RSS.pm
# written by Dr. Boris Neubert 2012-03-24
# e-mail: omega at online dot de
#
##############################################
# $Id:  $

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
  my $usage= "Usage: set $name rereadcfg";
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
  if($x<1) { $x*= $S->width; }
  if($y<1) { $y*= $S->height; }
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
RSS_itemGif {
  my ($S,$x,$y,$host,$filename,%params)= @_;
  return if($host eq "");
  return if($filename eq "");
  ($x,$y)= RSS_xy($S,$x,$y);
  my $data = GetFileFromURL("http://$host$filename");
  return unless(defined($data));
  my $I= GD::Image->newFromGifData($data);
  my ($width,$height)= $I->getBounds();
  Log 5, "RSS placing $host$filename ($width x $height) at ($x,$y)";
  $S->copy($I,$x,$y,0,0,$width,$height);
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

  my ($x,$y,$text,$host,$filename,$format);
  
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
            $params{rgb}= $def;
          } elsif($cmd eq "font") {
            $params{font}= $def;
          } elsif($cmd eq "pt") {
            $params{pt}= $def;
          } elsif($cmd eq "text") {
            ($x,$y,$text)= split("[ \t]+", $def, 3);
            my $txt= AnalyzePerlCommand(undef, $text);
            #Log 5, "$name: ($x,$y) $txt";
            RSS_itemText($S,$x,$y,$txt,%params);
          } elsif($cmd eq "time") {
            ($x,$y)= split("[ \t]+", $def, 2);
            RSS_itemTime($S,$x,$y,%params);
          } elsif($cmd eq "seconds") {
            ($x,$y,$format) = split("[ \+]", $def,3);
            RSS_itemSeconds($S,$x,$y,$format,%params);
          } elsif($cmd eq "date") {
            ($x,$y)= split("[ \t]+", $def, 2);
            RSS_itemDate($S,$x,$y,%params);
          }  elsif($cmd eq "gif") {
            ($x,$y,$host,$filename)= split("[ \t]+", $def,4);
            my $fn= AnalyzePerlCommand(undef, $filename);
            RSS_itemGif($S,$x,$y,$host,$fn,%params);
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
  my $S= GD::Image->newTrueColor($width,$height);
  $S->colorAllocate(0,0,0); # black is the background

  # wrap to make problems with GD non-lethal

  eval {

    #
    # set the background
    #
    # check if background directory is set
    my $bgdir= AttrVal($name,"bg","");
    goto SKIPBG unless($bgdir ne "");

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
    goto SKIPBG unless(opendir(BGDIR, $bgdir));
    my @bgfiles= grep {$_ !~ /^\./} readdir(BGDIR);
    closedir(BGDIR);
    # get item number
    if($#bgfiles>=0) {
      if($bgnr > $#bgfiles) { $bgnr= 0; }
      $defs{$name}{fhem}{bgnr}= $bgnr;
      my $bgfile= $bgdir . "/" . $bgfiles[$bgnr];
      my $bg= newFromJpeg GD::Image($bgfile);
      my ($bgwidth,$bgheight)= $bg->getBounds();
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
    }
    SKIPBG:

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



