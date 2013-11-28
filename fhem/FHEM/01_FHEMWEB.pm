##############################################
# $Id$
package main;

use strict;
use warnings;
use TcpServerUtils;
use HttpUtils;

#########################
# Forward declaration
sub FW_IconURL($);
sub FW_answerCall($);
sub FW_calcWeblink($$);
sub FW_dev2image($);
sub FW_digestCgi($);
sub FW_doDetail($);
sub FW_dumpFileLog($$$);
sub FW_fatal($);
sub FW_fileList($);
sub FW_logWrapper($);
sub FW_makeEdit($$$);
sub FW_makeImage($);
sub FW_makeTable($$@);
sub FW_makeTableFromArray($@);
sub FW_pH(@);
sub FW_pHPlain(@);
sub FW_pO(@);
sub FW_pathList();
sub FW_readIcons($);
sub FW_readIconsFrom($$);
sub FW_returnFileAsStream($$$$$);
sub FW_roomOverview($);
sub FW_select($$$$@);
sub FW_serveSpecial($$$$);
sub FW_setDirs();
sub FW_showLog($);
sub FW_showRoom();
sub FW_showWeblink($$$$);
sub FW_style($$);
sub FW_submit($$@);
sub FW_substcfg($$$$$$);
sub FW_textfield($$$);
sub FW_textfieldv($$$$);
sub FW_updateHashes();
sub FW_zoomLink($$$);
sub pF($@);

use vars qw($FW_dir);     # base directory for web server: the first available
                          # from $modpath/www, $modpath/FHEM
use vars qw($FW_icondir); # icon base directory for web server: the first
                          # available from $FW_dir/icons, $FW_dir
use vars qw($FW_docdir);  # doc directory for web server: the first available
                          # from $FW_dir/docs, $modpath/docs, $FW_dir
use vars qw($FW_cssdir);  # css directory for web server: the first available
                          # from $FW_dir/css, $FW_dir
use vars qw($FW_gplotdir);# gplot directory for web server: the first
                          # available from $FW_dir/gplot,$FW_dir
use vars qw($FW_jsdir);   # js directory for web server: the first available
                          # from $FW_dir/javascript, $FW_dir
use vars qw($MW_dir);     # moddir (./FHEM), needed by edit Files in new
                          # structure
use vars qw($FW_ME);      # webname (default is fhem), needed by 97_GROUP
use vars qw($FW_ss);      # is smallscreen, needed by 97_GROUP/95_VIEW
use vars qw($FW_tp);      # is touchpad (iPad / etc)

# global variables, also used by 97_GROUP/95_VIEW/95_FLOORPLAN
use vars qw(%FW_types);   # device types,
use vars qw($FW_RET);     # Returned data (html)
use vars qw($FW_wname);   # Web instance
use vars qw($FW_subdir);  # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
use vars qw(%FW_pos);     # scroll position
use vars qw($FW_cname);   # Current connection name

my $FW_zlib_checked;
my $FW_use_zlib = 1;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my @FW_httpheader; # HTTP header, line by line
my @FW_enc;        # Accepted encodings (browser header)
my %FW_webArgs;    # all arguments specified in the GET
my $FW_cmdret;     # Returned data by the fhem call
my $FW_data;       # Filecontent from browser when editing a file
my $FW_detail;     # currently selected device for detail view
my %FW_devs;       # hash of from/to entries per device
my %FW_icons;      # List of icons
my $FW_plotmode;   # Global plot mode (WEB attribute)
my $FW_plotsize;   # Global plot size (WEB attribute)
my $FW_commandref; # $FW_docdir/commandref.html;
my $FW_RETTYPE;    # image/png or the like
my $FW_room;       # currently selected room
my %FW_rooms;      # hash of all rooms
my %FW_types;      # device types, for sorting
my @FW_zoom;       # "qday", "day","week","month","year"
my %FW_zoom;       # the same as @FW_zoom
my %FW_hiddenroom; # hash of hidden rooms
my %FW_hiddengroup;# hash of hidden groups
my $FW_longpoll;   # Set if longpoll (i.e. server notification) is active
my $FW_inform;
my $FW_XHR;        # Data only answer, no HTML
my $FW_jsonp;      # jasonp answer (sending function calls to the client)
my $FW_headercors; # 
my $FW_chash;      # client fhem hash
#my $FW_encoding="ISO-8859-1";
my $FW_encoding="UTF-8";


# don't forget to amend FW_serveSpecial if you change this!
my $ICONEXTENSION = "gif|ico|png|jpg|jpeg";


#####################################
sub
FHEMWEB_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FW_Read";
  $hash->{GetFn}   = "FW_Get";
  $hash->{SetFn}   = "FW_Set";
  $hash->{AttrFn}  = "FW_Attr";
  $hash->{DefFn}   = "FW_Define";
  $hash->{UndefFn} = "FW_Undef";
  $hash->{NotifyFn}= "FW_SecurityCheck";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 webname fwmodpath fwcompress:0,1 ".
                     "plotmode:gnuplot,gnuplot-scroll,SVG plotsize refresh " .
                     "touchpad smallscreen plotfork basicAuth basicAuthMsg ".
                     "stylesheetPrefix iconpath hiddenroom hiddengroup HTTPS longpoll:1,0 ".
                     "redirectCmds:0,1 reverseLogs:0,1 allowfrom CORS:0,1 endPlotToday:1,0";

  ###############
  # Initialize internal structures
  my $n = 0;
  @FW_zoom = ("qday", "day","week","month","year");
  %FW_zoom = map { $_, $n++ } @FW_zoom;

  addToAttrList("webCmd");
  addToAttrList("icon");
  addToAttrList("devStateIcon");
  InternalTimer(time()+60, "FW_closeOldClients", 0, 0);
}

#####################################
sub
FW_SecurityCheck($$)
{
  my ($ntfy, $dev) = @_;
  return if($dev->{NAME} ne "global" ||
            !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));
  my $motd = AttrVal("global", "motd", "");
  if($motd =~ "^SecurityCheck") {
    my @list = grep { !AttrVal($_, "basicAuth", undef) }
               devspec2array("TYPE=FHEMWEB");
    $motd .= (join(",", sort @list)." has no basicAuth attribute.\n")
        if(@list);
    $attr{global}{motd} = $motd;
  }
  $modules{FHEMWEB}{NotifyFn}= "FW_Notify";
  return;
}

#####################################
sub
FW_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/ || ($global && $global ne "global"));


  FW_setDirs();
  # we do it only once at startup to save ressources at runtime
  FW_readIcons($hash);
        
  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log 1, "$ret. Exiting.";
    exit(1);
  }

  return $ret;
}

#####################################
sub
FW_Undef($$)
{
  my ($hash, $arg) = @_;
  return TcpServer_Close($hash);
}

#####################################
sub
FW_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    TcpServer_Accept($hash, "FHEMWEB");
    return;
  }

  $FW_chash = $hash;
  $FW_wname = $hash->{SNAME};
  $FW_cname = $name;
  $FW_subdir = "";

  my $ll = GetLogLevel($FW_wname,4);
  my $c = $hash->{CD};
  if(!$FW_zlib_checked) {
    $FW_zlib_checked = 1;
    $FW_use_zlib = AttrVal($FW_wname, "fwcompress", 1);
    if($FW_use_zlib) {
      eval { require Compress::Zlib; };
      if($@) {
        $FW_use_zlib = 0;
        Log 1, $@;
        Log 1, "$FW_wname: Can't load Compress::Zlib, deactivating compression";
        $attr{$FW_wname}{fwcompress} = 0;
      }
    }
  }

  # This is a hack... Dont want to do it each time after a fork.
  if(!$modules{SVG}{LOADED} && -f "$attr{global}{modpath}/FHEM/98_SVG.pm") {
    my $ret = CommandReload(undef, "98_SVG");
    Log 0, $ret if($ret);
  }

  # Data from HTTP Client
  my $buf;
  my $ret = sysread($c, $buf, 1024);

  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    Log($ll, "Connection closed for $name");
    return;
  }

  $hash->{BUF} .= $buf;
  return if($hash->{BUF} !~ m/\n\n$/ && $hash->{BUF} !~ m/\r\n\r\n$/);

  @FW_httpheader = split("[\r\n]", $hash->{BUF});


  my @origin = grep /Origin/, @FW_httpheader;
  $FW_headercors = (AttrVal($FW_wname, "CORS", 0) ?
              "Access-Control-Allow-".$origin[0]."\r\n".
              "Access-Control-Allow-Methods: GET OPTIONS\r\n".
              "Access-Control-Allow-Headers: Origin, Authorization, Accept\r\n".
              "Access-Control-Allow-Credentials: true\r\n".
              "Access-Control-Max-Age:86400\r\n" : "");


  #############################
  # BASIC HTTP AUTH
  my $basicAuth = AttrVal($FW_wname, "basicAuth", undef);
  my @headerOptions = grep /OPTIONS/, @FW_httpheader;
  if($basicAuth) {
    $hash->{BUF} =~ m/Authorization: Basic ([^\r\n]*)/s;
    my $secret = $1;
    my $pwok = ($secret && $secret eq $basicAuth);
    if($secret && $basicAuth =~ m/^{.*}$/ || $headerOptions[0]) {
      eval "use MIME::Base64";
      if($@) {
        Log 1, $@;

      } else {
        my ($user, $password) = split(":", decode_base64($secret));
        $pwok = eval $basicAuth;
        Log 1, "basicAuth expression: $@" if($@);
      }
    }
    if($headerOptions[0]) {
      print $c "HTTP/1.1 200 OK\r\n",
             $FW_headercors,
             "Content-Length: 0\r\n\r\n";
      $hash->{BUF}="";
      return;
      exit(1);
    };
    if(!$pwok) {
      my $msg = AttrVal($FW_wname, "basicAuthMsg", "Fhem: login required");
      print $c "HTTP/1.1 401 Authorization Required\r\n",
             "WWW-Authenticate: Basic realm=\"$msg\"\r\n",
             $FW_headercors,
             "Content-Length: 0\r\n\r\n";
      $hash->{BUF}="";
      return;
    };
  }
  #############################
  
  my $now = time();
  @FW_enc = grep /Accept-Encoding/, @FW_httpheader;
  my ($mode, $arg, $method) = split(" ", $FW_httpheader[0]);
  $hash->{BUF} = "";
  $hash->{LASTACCESS} = $now;

  $arg = "" if(!defined($arg));
  Log $ll, "HTTP $name GET $arg";
  my $pid;
  if(AttrVal($FW_wname, "plotfork", undef)) {
    # Process SVG rendering as a parallel process
    return if(($arg =~ m/cmd=showlog/) && ($pid = fork));
  }

  my $cacheable = FW_answerCall($arg);
  return if($cacheable == -1); # Longpoll / inform request;

  my $compressed = "";
  if(($FW_RETTYPE =~ m/text/i ||
      $FW_RETTYPE =~ m/svg/i ||
      $FW_RETTYPE =~ m/script/i) &&
     (int(@FW_enc) == 1 && $FW_enc[0] =~ m/gzip/) &&
     $FW_use_zlib) {
    $FW_RET = Compress::Zlib::memGzip($FW_RET);
    $compressed = "Content-Encoding: gzip\r\n";
  }

  my $length = length($FW_RET);
  my $expires = ($cacheable?
                        ("Expires: ".localtime($now+900)." GMT\r\n") : "");
  Log $ll, "$arg / RL: $length / $FW_RETTYPE / $compressed / $expires";
  print $c "HTTP/1.1 200 OK\r\n",
           "Content-Length: $length\r\n",
           $expires, $compressed, $FW_headercors,
           "Content-Type: $FW_RETTYPE\r\n\r\n",
           $FW_RET;
  exit if(defined($pid));
}

###########################
sub
FW_serveSpecial($$$$)
{
  my ($file,$ext,$dir,$cacheable)= @_;
  $file =~ s,\.\./,,g; # little bit of security

  if($ext eq "css") {
    my $prf = AttrVal($FW_wname, "stylesheetPrefix", "");
    $prf = "smallscreen" if(!$prf && $FW_ss);
    $prf = "touchpad"    if(!$prf && $FW_tp);
    $file = "$prf$file" if(-f "$dir/$prf$file.$ext");
  }

  $FW_RETTYPE = ext2MIMEType($ext);
  #Log 1, "We serve $dir/$file.$ext, $FW_RETTYPE";
  return FW_returnFileAsStream("$dir/$file.$ext", "",
                                        $FW_RETTYPE, 0, $cacheable);
}
  
sub
FW_setDirs()
{

  # web server root
  if(-d "$attr{global}{modpath}/www") {
    $FW_dir = AttrVal($FW_wname, "fwmodpath", "$attr{global}{modpath}/www");
  } else {
    $FW_dir = AttrVal($FW_wname, "fwmodpath", "$attr{global}{modpath}/FHEM");
  }
  # icon dir
  if(-d "$FW_dir/images") {
    $FW_icondir = "$FW_dir/images";
  } elsif( -d "$FW_dir/pgm2") {
    $FW_icondir = "$FW_dir/pgm2";
  } else {
    $FW_icondir = $FW_dir;
  }
  # doc dir
  if(-d "$FW_dir/docs") {
    $FW_docdir = "$FW_dir/docs";
  } elsif(-d "$attr{global}{modpath}/docs") {
    $FW_docdir = "$attr{global}{modpath}/docs";
  } elsif(-f "$FW_dir/pgm2/commandref.html") {
    $FW_docdir = "$FW_dir/pgm2";
  } else {
    $FW_docdir = $FW_dir;
  }
  # css dir
  if(-d "$FW_dir/pgm2") {
    $FW_cssdir = "$FW_dir/pgm2";
  } else {
    $FW_cssdir = $FW_dir;
  }
  # gplot dir
  if(-d "$FW_dir/gplot") {
    $FW_gplotdir = "$FW_dir/gplot";
  } elsif(-d "$FW_dir/pgm2") {
    $FW_gplotdir = "$FW_dir/pgm2";
  } else {
    $FW_gplotdir = $FW_dir;
  }
  # javascript dir
  if(-d "$FW_dir/pgm2") {
    $FW_jsdir = "$FW_dir/pgm2";
  } else {
    $FW_jsdir = $FW_dir;
  }

  Log 4, "FHEMWEB directories:";
  Log 4, "  web server root: $FW_dir";
  Log 4, "  icon directory: $FW_icondir";
  Log 4, "    Notice: if style-specific subdirectories ${FW_icondir}/default etc. exist, icons are only read from there and not from ${FW_icondir}!";
  Log 4, "  doc directory: $FW_docdir";
  Log 4, "  css directory: $FW_cssdir";
  Log 4, "  gplot directory: $FW_gplotdir";
  Log 4, "  javascript directory: $FW_jsdir";
  
}


sub
FW_answerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FW_cname};      # cache, else rereadcfg will delete us

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=$FW_encoding";
  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");

  $FW_commandref = "$FW_docdir/commandref.html";
  #Debug "commandref.html is at $FW_commandref";
  
  
  $MW_dir = AttrVal($FW_wname, "fwmodpath", "$attr{global}{modpath}/FHEM");
  $FW_ss = AttrVal($FW_wname, "smallscreen", 0);
  $FW_tp = AttrVal($FW_wname, "touchpad", $FW_ss);
  %FW_icons= %{$defs{$FW_wname}{fhemIcons}};

  # Lets go:
  if($arg =~ m,^$FW_ME/docs/(.*)\.(html|txt|pdf)$,) {
    return FW_serveSpecial($1, $2, $FW_docdir, 1);

  } elsif($arg =~ m,^${FW_ME}/css/(.*)\.css$,) {
    return FW_serveSpecial($1, "css", $FW_cssdir, 1);

  } elsif($arg =~ m,^${FW_ME}/js/(.*)\.js$,) {
    return FW_serveSpecial($1, "js", $FW_jsdir, 1);

  } elsif($arg =~ m,^$FW_ME/icons/(.*)$,) {
    my ($icon,$cacheable) = ($1, 1);
    #Debug "You want $icon which is " . $FW_icons{$icon};
    # if we do not have the icon, we convert the device state to the icon name
    $icon =~ s/\.($ICONEXTENSION)$//;
    if(!$FW_icons{$icon}) {
      $icon = FW_dev2image($icon);
      #Debug "We do not have it and thus use $icon which is ".$FW_icons{$icon};
      $cacheable = 0;
      return 0 if(!$icon);
    }
    $FW_icons{$icon} =~ m/(.*)\.($ICONEXTENSION)/;
    return FW_serveSpecial($1, $2, $FW_icondir, $cacheable);

  } elsif($arg !~ m/^$FW_ME(.*)/) {
    my $c = $me->{CD};
    Log 4, "$FW_wname: redirecting $arg to $FW_ME";
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n", $FW_headercors,
             "Location: $FW_ME\r\n\r\n";
    return -1;

  }
  
  $arg = $1; # The stuff behind FW_ME

  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");
  my ($cmd, $cmddev) = FW_digestCgi($arg);


  if($FW_inform) {      # Longpoll header
    $me->{inform} = ($FW_room ? $FW_room : $FW_inform);
    # NTFY_ORDER is larger than the normal order (50-)
    $me->{NTFY_ORDER} = $FW_cname;   # else notifyfn won't be called
    my $c = $me->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
       $FW_headercors,
       "Content-Type: application/octet-stream; charset=$FW_encoding\r\n\r\n";
    return -1;
  }

  my $docmd = 0;
  $docmd = 1 if($cmd &&
                $cmd !~ /^showlog/ &&
                $cmd !~ /^logwrapper/ &&
                $cmd !~ /^toweblink/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  #If we are in XHR or json mode, execute the command directly
  if($FW_XHR || $FW_jsonp) {
    $FW_cmdret = $docmd ? FW_fC($cmd, $cmddev) : "";
    $FW_RETTYPE = "text/plain; charset=$FW_encoding";
    if($FW_jsonp) {
      $FW_cmdret =~ s/'/\\'/g;
      # Escape newlines in JavaScript string
      $FW_cmdret =~ s/\n/\\\n/g;
      FW_pO "$FW_jsonp('$FW_cmdret');";
    } else {
      FW_pO $FW_cmdret;
    }
    return 0;
  }

  ##############################
  # Axels FHEMWEB modules...
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      if($arg =~ m/^$k/) {
        no strict "refs";
        #Returns undef if it already sent a HTTP header
        ($FW_RETTYPE, $FW_RET) = &{$data{FWEXT}{$k}{FUNC}}($arg);
        use strict "refs";
        return defined($FW_RETTYPE) ? 0 : -1;
      }
    }
  }

  #Now execute the command
  $FW_cmdret = $docmd ? FW_fC($cmd, $cmddev) : "";

  # Redirect after a command, to clean the browser URL window
  if($docmd && !$FW_cmdret && AttrVal($FW_wname, "redirectCmds", 1)) {
    my $tgt = $FW_ME;
       if($FW_detail) { $tgt .= "?detail=$FW_detail" }
    elsif($FW_room)   { $tgt .= "?room=$FW_room" }
    my $c = $me->{CD};
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n", $FW_headercors,
             "Location: $tgt\r\n",
             "\r\n";
    return -1;
  }

  FW_updateHashes();
  if($cmd =~ m/^showlog /) {
    FW_showLog($cmd);
    return 0;
  }

  $FW_longpoll = (AttrVal($FW_wname, "longpoll", undef) &&
                  (($FW_room && !$FW_detail) || ($FW_subdir ne "")));

  if($cmd =~ m/^toweblink (.*)$/) {
    my @aa = split(":", $1);
    my $max = 0;
    for my $d (keys %defs) {
      $max = ($1+1) if($d =~ m/^wl_(\d+)$/ && $1 >= $max);
    }
    $defs{$aa[0]}{currentlogfile} =~ m,([^/]*)$,;
    $aa[2] = "CURRENT" if($1 eq $aa[2]);
    $FW_cmdret = FW_fC("define wl_$max weblink fileplot $aa[0]:$aa[1]:$aa[2]");
    if(!$FW_cmdret) {
      $FW_detail = "wl_$max";
      FW_updateHashes();
    }
  }

  my $t = AttrVal("global", "title", "Home, Sweet Home");

  FW_pO '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  FW_pO '<html xmlns="http://www.w3.org/1999/xhtml">';
  FW_pO "<head>\n<title>$t</title>";
  FW_pO "<link rel=\"shortcut icon\" href=\"$FW_ME/icons/favicon.ico\" />";

  # Enable WebApp
  if($FW_tp || $FW_ss) {
    FW_pO '<link rel="apple-touch-icon-precomposed" href="'.$FW_ME.'/icons/fhemicon"/>';
    FW_pO '<meta name="apple-mobile-web-app-capable" content="yes"/>';
    if($FW_ss) {
      FW_pO '<meta name="viewport" content="width=320"/>';
    } elsif($FW_tp) {
      FW_pO '<meta name="viewport" content="width=768"/>';
    }
  }

  # meta refresh in rooms only
  if ($FW_room) {
    my $rf = AttrVal($FW_wname, "refresh", "");
    FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  }

  my $prf = AttrVal($FW_wname, "stylesheetPrefix", "");
  FW_pO "<link href=\"$FW_ME/css/style.css\" rel=\"stylesheet\"/>";
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/js/svg.js\"></script>"
                        if($FW_plotmode eq "SVG");
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/js/fhemweb.js\"></script>";
  my $onload = $FW_longpoll ? "onload=\"FW_delayedStart()\"" : "";
  FW_pO "</head>\n<body name=\"$t\" $onload>";

  if($FW_cmdret) {
    $FW_detail = "";
    $FW_room = "";
    $FW_cmdret =~ s/</&lt;/g;
    $FW_cmdret =~ s/>/&gt;/g;
    FW_pO "<div id=\"content\">";
    $FW_cmdret = "<pre>$FW_cmdret</pre>" if($FW_cmdret =~ m/\n/);
    if($FW_ss) {
      FW_pO "<div class=\"tiny\">$FW_cmdret</div>";
    } else {
      FW_pO $FW_cmdret;
    }
    FW_pO "</div>";

  } 

  FW_roomOverview($cmd);
     if($cmd =~ m/^style /)    { FW_style($cmd,undef);    }
  elsif($FW_detail)            { FW_doDetail($FW_detail); }
  elsif($FW_room)              { FW_showRoom();           }
  elsif($cmd =~ /^logwrapper/) { return FW_logWrapper($cmd); }
  elsif(!$FW_cmdret && AttrVal("global", "motd", "none") ne "none") {
    my $motd = AttrVal("global","motd",undef);
    $motd =~ s/\n/<br>/g;
    FW_pO "<div id=\"content\">$motd</div>";
  }
  FW_pO "</body></html>";
  return 0;
}


###########################
# Digest CGI parameters
sub
FW_digestCgi($)
{
  my ($arg) = @_;
  my (%arg, %val, %dev);
  my ($cmd, $c) = ("","","");

  %FW_pos = ();
  $FW_room = "";
  $FW_detail = "";
  $FW_XHR = undef;
  $FW_jsonp = undef;
  $FW_inform = undef;

  %FW_webArgs = ();
  #Remove (nongreedy) everything including the first '?'
  $arg =~ s,^.*?[?],,;
  foreach my $pv (split("&", $arg)) {
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);

    # Multiline: escape the NL for fhem
    $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
    $FW_webArgs{$p} = $v;

    if($p eq "detail")       { $FW_detail = $v; }
    if($p eq "room")         { $FW_room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c = $1; }
    if($p eq "pos")          { %FW_pos =  split(/[=;]/, $v); }
    if($p eq "data")         { $FW_data = $v; }
    if($p eq "XHR")          { $FW_XHR = 1; }
    if($p eq "jsonp")        { $FW_jsonp = $v; }
    if($p eq "inform")       { $FW_inform = $v; }

  }
  $cmd.=" $dev{$c}" if(defined($dev{$c}));
  $cmd.=" $arg{$c}" if(defined($arg{$c}) &&
                       ($arg{$c} ne "state" || $cmd !~ m/^set/));
  $cmd.=" $val{$c}" if(defined($val{$c}));
  return ($cmd, $c);
}

#####################
sub
FW_updateHashes()
{
  #################
  # Make a room  hash
  %FW_rooms = ();
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    foreach my $r (split(",", AttrVal($d, "room", "Unsorted"))) {
      $FW_rooms{$r}{$d} = 1;
    }
  }

  ###############
  # Needed for type sorting
  %FW_types = ();
  foreach my $d (sort keys %defs ) {
    next if(IsIgnored($d));
    my $t = AttrVal($d, "subType", $defs{$d}{TYPE});
    $t = AttrVal($d, "model", $t) if($t eq "unknown");
    $FW_types{$d} = $t;
  }

  $FW_room = AttrVal($FW_detail, "room", "Unsorted") if($FW_detail);
}

##############################
sub
FW_makeTable($$@)
{
  my($name, $hash, $cmd) = (@_);

  return if(!$hash || !int(keys %{$hash}));
  FW_pO "<table class=\"block wide\">";

  my $row = 1;
  foreach my $n (sort keys %{$hash}) {
    my $val = $hash->{$n};
    $val = $hash->{$n}{NAME} if($n eq "IODev" && ref($val) eq "HASH" && defined($hash->{$n}{NAME}));

    my $r = ref($val);
    next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));

    pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
    $row++;

    if($n eq "DEF" && !$FW_hiddenroom{input}) {
      FW_makeEdit($name, $n, $val);

    } else {

      FW_pO "<td><div class=\"dname\">$n</div></td>";
      if(ref($val)) {
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        if($FW_ss) {
          $t = ($t ? "<br><div class=\"tiny\">$t</div>" : "");
          FW_pO "<td><div class=\"dval\">$v$t</div></td>";

        } else {
          $t = "" if(!$t);
          FW_pO "<td>$v</td><td>$t</td>";

        }

      } else {
        FW_pO "<td><div class=\"dval\">$val</div></td>";

      }

    }
    FW_pH "cmd.$name=$cmd $name $n&amp;detail=$name", $cmd, 1
        if($cmd && !$FW_ss);


    FW_pO "</tr>";
  }
  FW_pO "</table>";
  FW_pO "<br>";
  
}

##############################
sub
FW_makeSelect($$$$)
{
  my ($d, $cmd, $list,$class) = @_;
  return if(!$list || $FW_hiddenroom{input});
  my @al = sort map { s/:.*//;$_ } split(" ", $list);

  my $selEl = $al[0];
  $selEl = $1 if($list =~ m/([^ ]*):slider,/); # promote a slider if available
  $selEl = "room" if($list =~ m/room:/);

  FW_pO "<form method=\"get\" action=\"$FW_ME$FW_subdir\">";
  FW_pO FW_hidden("detail", $d);
  FW_pO FW_hidden("dev.$cmd$d", $d);
  FW_pO FW_submit("cmd.$cmd$d", $cmd, $class);
  FW_pO "<div class=\"$class downText\">&nbsp;$d&nbsp;</div>";
  FW_pO FW_select("arg.$cmd$d",\@al, $selEl, $class,
        "FW_selChange(this.options[selectedIndex].text,'$list','val.$cmd$d')");
  FW_pO FW_textfield("val.$cmd$d", 30, $class);

  # Initial setting
  FW_pO "<script type=\"text/javascript\">" .
        "FW_selChange('$selEl','$list','val.$cmd$d')</script>";
  FW_pO "</form>";
}

##############################
sub
FW_makeImage($)
{
  my ($name)= @_;
  my $iconpath= FW_IconPath($name);
  if(defined($iconpath)) {
    my $iconurl= FW_IconURL($name);
    return "<img src=\"$iconurl\"><!-- $iconpath -->";
  } else {
    return "<b>Image <i>$name</i> not found in $FW_icondir</b>";
  }
}

##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  FW_pO "<form method=\"get\" action=\"$FW_ME\">";
  FW_pO FW_hidden("detail", $d);

  my $h = $defs{$d};
  my $t = $h->{TYPE};
  FW_pO "<div id=\"content\">";

  if($FW_ss) { # FS20MS2 special: on and off, is not the same as toggle
    my $webCmd = AttrVal($d, "webCmd", undef);
    if($webCmd) {
      FW_pO "<table>";
      foreach my $cmd (split(":", $webCmd)) {
        FW_pO "<tr>";
        FW_pH "cmd.$d=set $d $cmd&detail=$d", $cmd, 1, "col1";
        FW_pO "</tr>";
      }
      FW_pO "</table>";
    }
  }
  FW_pO "<table><tr><td>";
  FW_makeSelect($d, "set", getAllSets($d), "set");
  FW_makeTable($d, $h);
  FW_pO "Readings" if($h->{READINGS});
  FW_makeTable($d, $h->{READINGS});

  my $attrList = getAllAttr($d);
  my $roomList = join(",", sort grep !/ /, keys %FW_rooms);
  $attrList =~ s/room /room:$roomList /;

  FW_makeSelect($d, "attr", $attrList,"attr");
  FW_makeTable($d, $attr{$d}, "deleteattr");


  if($t eq "FileLog" ) {
    FW_pO "<table class=\"block wide\">";
    FW_dumpFileLog($d, 0, 1);
    FW_pO "</table>";
  }

  ## dependent objects
  my @dob;  # dependent objects - triggered by current device
  foreach my $dn (sort keys %defs) { 
    next if($dn eq $d);
    my $dh = $defs{$dn};
    if(($dh->{DEF} && $dh->{DEF} =~ m/\b$d\b/) ||
       ($h->{DEF}  && $h->{DEF}  =~ m/\b$dn\b/)) {
      push(@dob, $dn);
    }
  }
  FW_makeTableFromArray("Probably associated with", @dob);

  FW_pO "</td></tr></table>";

  if($t eq "weblink") {
    FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, 1);
    FW_pO "<br><br>";
  }

  FW_pH "cmd=style iconFor $d", "Select icon";
  FW_pH "$FW_ME/docs/commandref.html#${t}", "Device specific help";
  FW_pO "<br><br>";
  FW_pO "</div>";
  FW_pO "</form>";

}

##############################
sub
FW_makeTableFromArray($@) {
  my ($txt,@obj) = @_;
  if (@obj>0) {
    my $row=1;
    FW_pO "<br>" if($FW_RET !~ m/<br>$/);
    FW_pO "$txt";
    FW_pO '<table class="block wide">';
    foreach (sort @obj) {
      pF "<tr class=\"%s\"><td>", ($row&1)?"odd":"even";
      $row++;
      FW_pH "detail=$_", $_;
      FW_pO "</td><td>$defs{$_}{TYPE}</td><td> </td>";
      FW_pO "</tr>";
    }
    FW_pO "</table><br>";
  }
}

##############
# Header, Zoom-Icons & list of rooms at the left.
sub
FW_roomOverview($)
{
  my ($cmd) = @_;

  %FW_hiddenroom = ();
  foreach my $r (split(",",AttrVal($FW_wname, "hiddenroom", ""))) {
    $FW_hiddenroom{$r} = 1;
  }

  ##############
  # LOGO
  if($FW_detail && $FW_ss) {
    $FW_room = AttrVal($FW_detail, "room", undef);
    $FW_room = $1 if($FW_room && $FW_room =~ m/^([^,]*),/);
    $FW_room = "" if(!$FW_room);
    FW_pHPlain "room=$FW_room",
        "<div id=\"back\">" . FW_makeImage("back") . "</div>";
    FW_pO "<div id=\"menu\">$FW_detail details</div>";
    return;

  } else {
    FW_pH "", "<div id=\"logo\"></div>";

  }


  ##############
  # HEADER
  FW_pO "<div id=\"hdr\">";
  FW_pO '<table border="0"><tr><td style="padding:0">';
  FW_pO "<form method=\"get\" action=\"$FW_ME\">";
  FW_pO FW_hidden("room", "$FW_room") if($FW_room);
  FW_pO FW_textfield("cmd", $FW_ss ? 25 : 40, "maininput");
  if(!$FW_ss && !$FW_hiddenroom{save}) {
    FW_pO "</form></td><td><form>" . FW_submit("cmd", "save");
  }
  FW_pO "</form>";
  FW_pO "</td></tr></table>";
  FW_pO "</div>";

  ##############
  # MENU
  my (@list1, @list2);
  push(@list1, ""); push(@list2, "");

  ########################
  # FW Extensions
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{LINK} || !$h->{NAME});
      push(@list1, $h->{NAME});
      push(@list2, $FW_ME ."/".$h->{LINK});
    }
    push(@list1, ""); push(@list2, "");
  }
  $FW_room = "" if(!$FW_room);

  ##########################
  # Rooms and other links
  foreach my $r (sort keys %FW_rooms) {
    next if($r eq "hidden" || $FW_hiddenroom{$r});
    $FW_room = $r if(!$FW_room && $FW_ss);
    $r =~ s/</&lt;/g;
    $r =~ s/>/&lt;/g;
    push @list1, $r;
    $r =~ s/ /%20/g;
    push @list2, "$FW_ME?room=$r";
  }
  my @list = (
     "Everything",    "$FW_ME?room=all",
     "",              "",
     "Howto",         "$FW_ME/docs/HOWTO.html",
     "Wiki",          "http://fhemwiki.de",
     "Commandref",    "$FW_ME/docs/commandref.html",
     "Definition...", "$FW_ME?cmd=style%20addDef",
     "Edit files",    "$FW_ME?cmd=style%20list",
     "Select style",  "$FW_ME?cmd=style%20select",
     "Event monitor", "$FW_ME?cmd=style%20eventMonitor",
     "",           "");
  my $lastname = ","; # Avoid double "".

  my $lfn = "Logfile";
  if($defs{$lfn}) { # Add the current Logfile to the list if defined
    my @l = FW_fileList($defs{$lfn}{logfile});
    my $fn = pop @l;
    splice @list, 4,0, ("Logfile","$FW_ME?cmd=logwrapper%20$lfn%20text%20$fn");
  }

  for(my $idx = 0; $idx < @list; $idx+= 2) {
    next if($FW_hiddenroom{$list[$idx]} || $list[$idx] eq $lastname);
    push @list1, $list[$idx];
    push @list2, $list[$idx+1];
    $lastname = $list[$idx];
  }


  FW_pO "<div id=\"menu\">";
  FW_pO "<table>";
  if($FW_ss) {  # Make a selection sensitive dropdown list
    FW_pO "<tr><td><select OnChange=\"location.href=" .
                              "this.options[this.selectedIndex].value\">";
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      next if(!$list1[$idx]);
      my $sel = ($list1[$idx] eq $FW_room ? " selected=\"selected\""  : "");
      FW_pO "<option value=$list2[$idx]$sel>$list1[$idx]</option>";
    }
    FW_pO "</select></td>";
    if(!$FW_hiddenroom{save}) {
      FW_pO "<td><form method=\"get\" action=\"$FW_ME\">" .
            FW_submit("cmd", "save").
          "</form></td>";
    }
    FW_pO "</tr>";

  } else {

    foreach(my $idx = 0; $idx < @list1; $idx++) {
      my ($l1, $l2) = ($list1[$idx], $list2[$idx]);
      if(!$l1) {
        FW_pO "</table></td></tr>" if($idx);
        FW_pO "<tr><td><table id=\"room\">"
          if($idx<int(@list1)-1);
      } else {
        pF "<tr%s>", $l1 eq $FW_room ? " class=\"sel\"" : "";
        # image tag if we have an icon, else empty
        my $icon= $FW_icons{"ico${l1}"} ? FW_makeImage("ico${l1}") . "&nbsp;" : "";

        if($l2 =~ m/.html$/ || $l2 =~ m/^http/) {
           FW_pO "<td><a href=\"$l2\">$icon$l1</a></td>";
        } else {
          FW_pH $l2, "$icon$l1", 1;
        }
        FW_pO "</tr>";
      }
    }

  }
  FW_pO "</table>";
  FW_pO "</div>";
}


########################
# Show the overview of devices in one room
# room can be a room, all or Unsorted
sub
FW_showRoom()
{
  return if(!$FW_room);
  
  %FW_hiddengroup = ();
  foreach my $r (split(",",AttrVal($FW_wname, "hiddengroup", ""))) {
    $FW_hiddengroup{$r} = 1;
  }
  
  FW_pO "<form method=\"get\" action=\"$FW_ME\" autocomplete=\"off\">";
  FW_pO "<div id=\"content\">";
  FW_pO "<table>";  # Need for equal width of subtables

  my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room
  
  # array of all device names in the room except weblinkes
  my @devs= grep { ($FW_rooms{$FW_room}{$_}||$FW_room eq "all") &&
                      !IsIgnored($_) } keys %defs;

  my %group;
  foreach my $dev (@devs) {
    next if($defs{$dev}{TYPE} eq "weblink" && !AttrVal($dev, "group", undef));
    foreach my $grp (split(",", AttrVal($dev, "group", $FW_types{$dev}))) {
      next if($FW_hiddengroup{$grp}); 
      $group{$grp}{$dev} = 1;
    }
  }

  # row counter
  my $row=1;
    
  # iterate over the distinct groups  
  foreach my $g (sort keys %group) {

    #################
    # Check if there is a device of this type in the room

    FW_pO "\n<tr><td><div class=\"devType\">$g</div></td></tr>";
    FW_pO "<tr><td>";
    FW_pO "<table class=\"block wide\" id=\"$g\">";

    foreach my $d (sort @devs) {
      next if(!$group{$g}{$d}); 
      
      my $type = $defs{$d}{TYPE};

      pF "\n<tr class=\"%s\">", ($row&1)?"odd":"even";
      my $devName = AttrVal($d, "alias", $d);
      my $icon = AttrVal($d, "icon", "");
      if($icon =~ m/^(.*)\.($ICONEXTENSION)$/) {
        $icon= $1; # silently remove the extension
      }
      $icon = FW_makeImage($icon) . "&nbsp;" if($icon);

      if($FW_hiddenroom{detail}) {
        FW_pO "<td><div class=\"col1\">$icon$devName</div></td>";
      } else {
        FW_pH "detail=$d", "$icon$devName", 1, "col1";
      }
      $row++;

      if($type eq "weblink") {
        FW_pO "<td>";
        FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, undef);
        FW_pO "</td>";
        next;
      }

      my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf);
      FW_pO "<td id=\"$d\">$txt";

      ######
      # Commands, slider, dropdown
      if(!$FW_ss) {
        FW_pO "</td>";
        if($cmdlist) {
          my @cList = split(":", $cmdlist);
          my $firstIdx = 0;

          # Special handling (slider, dropdown)
          my $cmd = $cList[0];
          if($allSets && $allSets =~ m/$cmd:([^ ]*)/) {
            my $values = $1;

            if($values =~ m/^slider,(.*),(.*),(.*)/) { ##### Slider
              my ($min,$stp, $max) = ($1, $2, $3);
              my $srf = $FW_room ? "&room=$FW_room" : "";
              my $cv = ReadingsVal($d, $cmd, Value($d));
              $cmd = "" if($cmd eq "state");
              $cv =~ s/[^\d\.]//g;
              FW_pO "<td colspan='2'>".
                      "<div class='slider' id='slider.$d'>".
                        "<div class='handle'>$min</div></div>".
                      "</div>".
                      "<script type=\"text/javascript\">" .
                        "Slider(document.getElementById('slider.$d'),".
                              "'$min','$stp','$max','$cv',".
                              "'$FW_ME?cmd=set $d $cmd %$srf')".
                      "</script>".
                    "</td>";
              $firstIdx=1;

            } elsif($values =~ m/^time$/) { ##### Time picker
              my $srf = $FW_room ? "&room=$FW_room" : "";
              my $cv = ReadingsVal($d, $cmd, Value($d));
              $cmd = "" if($cmd eq "state");
              my $c = "\"$FW_ME?cmd=set $d $cmd %$srf\"";
              FW_pO "<td colspan='2'>".
                      "<input name='time.$d' value='$cv' type='text'".
                                                " readonly size='5'>".
                      "<input type='button' value='+'".
                                                " onclick='addTime(this,$c)'>".
                    "</td>";
              $firstIdx=1;

            } else {    ##### Dropdown

              my @tv = split(",", $values);
              # Hack: eventmap (translation only) should not result in a
              # dropdown.  eventMap/webCmd/etc handling must be cleaned up.
              if(@tv > 1) {
                $firstIdx=1;
                if($cmd eq "desired-temp") {
                  $txt = ReadingsVal($d, "desired-temp", 20);
                  $txt =~ s/ .*//;        # Cut off Celsius
                  $txt = sprintf("%2.1f", int(2*$txt)/2) if($txt =~ m/[0-9.-]/);
                } else {
                  $txt = Value($d);
                  $txt =~ s/$cmd //;
                }
                FW_pO "<td>".
                  FW_hidden("arg.$d", $cmd) .
                  FW_hidden("dev.$d", $d) .
                  ($FW_room ? FW_hidden("room", $FW_room) : "") .
                  FW_select("val.$d", \@tv, $txt, "dropdown").
                  "</td><td>".
                  FW_submit("cmd.$d", "set").
                  "</td>";
              }
            }
          }

          for(my $idx=$firstIdx; $idx < @cList; $idx++) {
            FW_pH "cmd.$d=set $d $cList[$idx]$rf", $cList[$idx], 1,"col3";
          }


        } elsif($type eq "FileLog") {
          $row = FW_dumpFileLog($d, 1, $row);

        }
      }
      FW_pO "</td>";
    }
    FW_pO "</table>";
    FW_pO "</td></tr>";
  }
  FW_pO "</table><br>";

  # Now the weblinks
  my $buttons = 1;
  $FW_room = "" if(!defined($FW_room));
  my @list = ($FW_room eq "all" ? keys %defs : keys %{$FW_rooms{$FW_room}});
  foreach my $d (sort @list) {
    next if(IsIgnored($d));
    my $type = $defs{$d}{TYPE};
    next if(!$type || $type ne "weblink" || AttrVal($d, "group", undef));

    $buttons = FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, $buttons);
  }
  FW_pO "</div>";
  FW_pO "</form>";
}

#################
# return a sorted list of actual files for a given regexp
sub
FW_fileList($)
{
  my ($fname) = @_;
  $fname =~ m,^(.*)/([^/]*)$,; # Split into dir and file
  my ($dir,$re) = ($1, $2);
  return if(!$re);
  $re =~ s/%./[A-Za-z0-9]*/g; 
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$,);
    push(@ret, $f);
  }
  closedir(DH);
  return sort @ret;
}


###################################
# Stream big files in chunks, to avoid bloating ourselves.
# This is a "terminal" function, no data can be appended after it is called.
sub
FW_outputChunk($$$)
{
  my ($c, $buf, $d) = @_;
  $buf = $d->deflate($buf) if($d);
  print $c sprintf("%x\r\n", length($buf)), $buf, "\r\n" if(length($buf));
}

sub
FW_returnFileAsStream($$$$$)
{
  my ($path, $suffix, $type, $doEsc, $cacheable) = @_;

  my $etag;
  my $c = $FW_chash->{CD};

  if($cacheable) {
    #Check for If-None-Match header (ETag)
    my @if_none_match_lines = grep /If-None-Match/, @FW_httpheader;
    my $if_none_match = undef;
    if(@if_none_match_lines) {
      $if_none_match = $if_none_match_lines[0];
      $if_none_match =~ s/If-None-Match: \"(.*)\"/$1/;
    }

    $etag = (stat($path))[9]; #mtime

    if(defined($etag) && defined($if_none_match) && $etag eq $if_none_match) {
      print $c "HTTP/1.1 304 Not Modified\r\n",
        $FW_headercors, "\r\n";
      return -1;
    }
  }

  if(!open(FH, $path)) {
    FW_pO "<div id=\"content\">$path: $!</div>";
    return 0;
  }
  binmode(FH) if($type !~ m/text/); # necessary for Windows

  $etag = defined($etag) ? "ETag: \"$etag\"\r\n" : "";
  my $expires = $cacheable ? ("Expires: ".localtime(time()+900)." GMT\r\n"): "";
  my $compr = ((int(@FW_enc) == 1 && $FW_enc[0] =~ m/gzip/) && $FW_use_zlib) ?
                "Content-Encoding: gzip\r\n" : "";
  print $c "HTTP/1.1 200 OK\r\n",
           $compr, $expires, $FW_headercors, $etag,
           "Transfer-Encoding: chunked\r\n",
           "Content-Type: $type; charset=$FW_encoding\r\n\r\n";

  my $d = Compress::Zlib::deflateInit(-WindowBits=>31) if($compr);
  FW_outputChunk($c, $FW_RET, $d);
  my $buf;
  while(sysread(FH, $buf, 2048)) {
    if($doEsc) { # FileLog special
      $buf =~ s/</&lt;/g;
      $buf =~ s/>/&gt;/g;
    }
    FW_outputChunk($c, $buf, $d);
  }
  close(FH);
  FW_outputChunk($c, $suffix, $d);

  if($compr) {
    $buf = $d->flush();
    print $c sprintf("%x\r\n", length($buf)), $buf, "\r\n" if($buf);
  }
  print $c "0\r\n\r\n";
  return -1;
}

######################
# Show the content of the log (plain text), or an image and offer a link
# to convert it to a weblink
# If text and no reverse required, try to return the data as a stream;
sub
FW_logWrapper($)
{
  my ($cmd) = @_;
  my (undef, $d, $type, $file) = split(" ", $cmd, 4);
  if(defined($type) && $type eq "text") {
    $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path = AttrVal($d,"archivedir","") . "/$file" if(!-f $path);

    FW_pO "<div id=\"content\">";
    FW_pO "<div class=\"tiny\">" if($FW_ss);
    FW_pO "<pre class=\"log\">";
    my $suffix = "</pre>".($FW_ss ? "</div>" : "")."</div>";

    my $reverseLogs = AttrVal($FW_wname, "reverseLogs", 0);
    if(!$reverseLogs) {
      $suffix .= "</body></html>";
      return FW_returnFileAsStream($path, $suffix, "text/html", 1, 0);
    }

    if(!open(FH, $path)) {
      FW_pO "<div id=\"content\">$path: $!</div></body></html>";
      return 0;
    }
    my $cnt = join("", reverse <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;
    FW_pO $cnt;
    FW_pO $suffix;

  } else {
    FW_pO "<div id=\"content\">";
    FW_pO "<br>";
    FW_zoomLink("cmd=$cmd;zoom=-1", "Zoom-in", "zoom in");
    FW_zoomLink("cmd=$cmd;zoom=1",  "Zoom-out","zoom out");
    FW_zoomLink("cmd=$cmd;off=-1",  "Prev",    "prev");
    FW_zoomLink("cmd=$cmd;off=1",   "Next",    "next");
    FW_pO "<table><tr><td>";
    FW_pO "<td>";
    my $logtype = $defs{$d}{TYPE};
    my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);
    my $arg = "$FW_ME?cmd=showlog $logtype $d $type $file$wl";
    if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
      my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
      FW_pO "<embed src=\"$arg\" type=\"image/svg+xml\" " .
                    "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

    } else {
      FW_pO "<img src=\"$arg\"/>";
    }

    FW_pO "<br>";
    FW_pH "cmd=toweblink $d:$type:$file", "Convert to weblink";
    FW_pO "</td>";
    FW_pO "</td></tr></table>";
    FW_pO "</div>";

  }
  FW_pO "</body></html>";
  return 0;
}

sub
FW_readgplotfile($$$)
{
  my ($wl, $gplot_pgm, $file) = @_;

  ############################
  # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
  # the plot directive with our own, as we offer a file for each line
  my (@filelog, @data, $plot);

  my $wltype = "";
  $wltype = $defs{$wl}{WLTYPE} if($defs{$wl} && $defs{$wl}{WLTYPE});

  open(FH, $gplot_pgm) || return (FW_fatal("$gplot_pgm: $!"), undef);
  while(my $l = <FH>) {
    $l =~ s/\r//g;
    my $plotfn = undef;
    if($l =~ m/^#FileLog (.*)$/ &&
       ($wltype eq "fileplot" || $wl eq "FileLog")) {
      $plotfn = $1;
    } elsif ($l =~ m/^#DbLog (.*)$/ && 
       ($wltype eq "dbplot" || $wl eq "DbLog")) {
      $plotfn = $1;
    } elsif($l =~ "^plot" || $plot) {
      $plot .= $l;
    } else {
      push(@data, $l);
    }
    
    if($plotfn) {
      my $specval = AttrVal($wl, "plotfunction", undef);
      if ($specval) {
        my @spec = split(" ",$specval);
        my $spec_count=1;
        foreach (@spec) {
          $plotfn =~ s/<SPEC$spec_count>/$_/g;
          $spec_count++;
        }
      }
      push(@filelog, $plotfn);
    }
  }
  close(FH);

  return (undef, \@data, $plot, \@filelog);
}

sub
FW_substcfg($$$$$$)
{
  my ($splitret, $wl, $cfg, $plot, $file, $tmpfile) = @_;

  # interpret title and label as a perl command and make
  # to all internal values e.g. $value.

  my $oll = $attr{global}{verbose};
  $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged

  my $fileesc = $file;
  $fileesc =~ s/\\/\\\\/g;      # For Windows, by MarkusRR
  my $title = AttrVal($wl, "title", "\"$fileesc\"");

  $title = AnalyzeCommand($FW_chash, "{ $title }");
  my $label = AttrVal($wl, "label", undef);
  my @g_label;
  if ($label) {
    @g_label = split("::",$label);
    foreach (@g_label) {
      $_ = AnalyzeCommand($FW_chash, "{ $_ }");
    }
  }
  $attr{global}{verbose} = $oll;

  my $gplot_script = join("", @{$cfg});
  $gplot_script .=  $plot if(!$splitret);

  $gplot_script =~ s/<OUT>/$tmpfile/g;
  $gplot_script =~ s/<IN>/$file/g;

  my $ps = AttrVal($wl,"plotsize",$FW_plotsize);
  $gplot_script =~ s/<SIZE>/$ps/g;

  $gplot_script =~ s/<TL>/$title/g;
  my $g_count=1; 
  if ($label) {
    foreach (@g_label) {
      $gplot_script =~ s/<L$g_count>/$_/g;
      $plot =~ s/<L$g_count>/$_/g;
      $g_count++;
    }
  }

  $plot =~ s/\r//g;             # For our windows friends...
  $gplot_script =~ s/\r//g;

  if($splitret == 1) {
    my @ret = split("\n", $gplot_script); 
    return (\@ret, $plot);
  } else {
    return $gplot_script;
  }
}


######################
# Generate an image from the log via gnuplot or SVG
sub
FW_showLog($)
{
  my ($cmd) = @_;
  my (undef, $wl, $d, $type, $file) = split(" ", $cmd, 5);

  my $pm = AttrVal($wl,"plotmode",$FW_plotmode);

  my $gplot_pgm = "$FW_gplotdir/$type.gplot";

  if(!-r $gplot_pgm) {
    my $msg = "Cannot read $gplot_pgm";
    Log 1, $msg;

    if($pm =~ m/SVG/) { # FW_fatal for SVG:
      $FW_RETTYPE = "image/svg+xml";
      FW_pO '<svg xmlns="http://www.w3.org/2000/svg">';
      FW_pO '<text x="20" y="20">'.$msg.'</text>';
      FW_pO '</svg>';
      return;

    } else {
      return FW_fatal($msg);

    }
  }
  FW_calcWeblink($d,$wl);

  if($pm =~ m/gnuplot/) {

    my $tmpfile = "/tmp/file.$$";
    my $errfile = "/tmp/gnuplot.err";

    if($pm eq "gnuplot" || !$FW_devs{$d}{from}) {

      # Looking for the logfile....
      $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
      my $path = "$1/$file";
      $path = AttrVal($d,"archivedir","") . "/$file" if(!-f $path);
      return FW_fatal("Cannot read $path") if(!-r $path);

      my ($err, $cfg, $plot, undef) = FW_readgplotfile($wl, $gplot_pgm, $file);
      return $err if($err);
      my $gplot_script = FW_substcfg(0, $wl, $cfg, $plot, $file,$tmpfile);

      my $fr = AttrVal($wl, "fixedrange", undef);
      if($fr) {
        $fr =~ s/ /\":\"/;
        $fr = "set xrange [\"$fr\"]\n";
        $gplot_script =~ s/(set timefmt ".*")/$1\n$fr/;
      }

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script;
      close(FH);

    } elsif($pm eq "gnuplot-scroll") {


      my ($err, $cfg, $plot, $flog) = FW_readgplotfile($wl, $gplot_pgm, $file);
      return $err if($err);


      # Read the data from the filelog
      my ($f,$t)=($FW_devs{$d}{from}, $FW_devs{$d}{to});
      my $oll = $attr{global}{verbose};
      $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged
      my @path = split(" ", FW_fC("get $d $file $tmpfile $f $t " .
                                  join(" ", @{$flog})));
      $attr{global}{verbose} = $oll;


      # replace the path with the temporary filenames of the filelog output
      my $i = 0;
      $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
      my $xrange = "set xrange [\"$f\":\"$t\"]\n";
      foreach my $p (@path) {   # If the file is empty, write a 0 line
        next if(!-z $p);
        open(FH, ">$p");
        print FH "$f 0\n";
        close(FH);
      }

      my $gplot_script = FW_substcfg(0, $wl, $cfg, $plot, $file, $tmpfile);

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script, $xrange, $plot;
      close(FH);
      foreach my $p (@path) {
        unlink($p);
      }
    }
    $FW_RETTYPE = "image/png";
    open(FH, "$tmpfile.png");         # read in the result and send it
    binmode (FH); # necessary for Windows
    FW_pO join("", <FH>);
    close(FH);
    unlink("$tmpfile.png");

  } elsif($pm eq "SVG") {

    my ($err, $cfg, $plot, $flog) = FW_readgplotfile($wl, $gplot_pgm, $file);
    return $err if($err);

    my ($f,$t)=($FW_devs{$d}{from}, $FW_devs{$d}{to});
    $f = 0 if(!$f);     # From the beginning of time...
    $t = 9 if(!$t);     # till the end

    my $ret;
    if(!$modules{SVG}{LOADED}) {
      $ret = CommandReload(undef, "98_SVG");
      Log 0, $ret if($ret);
    }
    Log 5, "plotcommand: get $d $file INT $f $t " . join(" ", @{$flog});
    $ret = FW_fC("get $d $file INT $f $t " . join(" ", @{$flog}));
    ($cfg, $plot) = FW_substcfg(1, $wl, $cfg, $plot, $file, "<OuT>");
    FW_pO SVG_render($wl, $f, $t, $cfg, $internal_data, $plot, $FW_wname, $FW_cssdir);
    $FW_RETTYPE = "image/svg+xml";

  }

}

##################
sub
FW_fatal($)
{
  my ($msg) = @_;
  FW_pO "<html><body>$msg</body></html>";
}

##################
sub
FW_hidden($$)
{
  my ($n, $v) = @_;
  return "<input type=\"hidden\" name=\"$n\" value=\"$v\"/>";
}

##################
# Generate a select field with option list
sub
FW_select($$$$@)
{
  my ($n, $va, $def, $class, $jSelFn) = @_;
  $jSelFn = ($jSelFn ? "onchange=\"$jSelFn\"" : "");
  my $s = "<select $jSelFn name=\"$n\" class=\"$class\">";

  foreach my $v (@{$va}) {
    if($def && $v eq $def) {
      $s .= "<option selected=\"selected\" value=\"$v\">$v</option>\n";
    } else {
      $s .= "<option value=\"$v\">$v</option>\n";
    }
  }
  $s .= "</select>";
  return $s;
}

##################
sub
FW_textfieldv($$$$)
{
  my ($n, $z, $class, $value) = @_;
  my $v;
  $v=" value=\"$value\"" if(defined($value));
  return if($FW_hiddenroom{input});
  my $s = "<input type=\"text\" name=\"$n\" class=\"$class\" size=\"$z\"$v/>";
  return $s;
}

sub
FW_textfield($$$)
{
  return FW_textfieldv($_[0], $_[1], $_[2], "");
}

##################
sub
FW_submit($$@)
{
  my ($n, $v, $class) = @_;
  $class = ($class ? "class=\"$class\"" : "");
  my $s ="<input type=\"submit\" name=\"$n\" value=\"$v\" $class/>";
  return $s;
}

##################
# Generate the zoom and scroll images with links if appropriate
sub
FW_zoomLink($$$)
{
  my ($cmd, $img, $alt) = @_;

  my $prf;
  $cmd =~ m/^(.*);([^;]*)$/;
  ($prf, $cmd) = ($1, $2) if($2);
  my ($d,$off) = split("=", $cmd, 2);

  my $val = $FW_pos{$d};
  $cmd = ($FW_detail ? "detail=$FW_detail":
                        ($prf ? $prf : "room=$FW_room")) . "&amp;pos=";

  if($d eq "zoom") {

    $val = "day" if(!$val);
    $val = $FW_zoom{$val};
    return if(!defined($val) || $val+$off < 0 || $val+$off >= int(@FW_zoom) );
    $val = $FW_zoom[$val+$off];
    return if(!$val);

    # Approximation of the next offset.
    my $w_off = $FW_pos{off};
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
    $cmd .= "zoom=$val;off=$w_off";

  } else {

    return if((!$val && $off > 0) || ($val && $val+$off > 0)); # no future
    $off=($val ? $val+$off : $off);
    my $zoom=$FW_pos{zoom};
    $zoom = 0 if(!$zoom);
    $cmd .= "zoom=$zoom;off=$off";

  }

  FW_pO "&nbsp;&nbsp;";
  FW_pHPlain "$cmd", "<img style=\"border-color:transparent\" alt=\"$alt\" ".
                "src=\"$FW_ME/icons/$img\"/>";
}

##################
# Calculate either the number of scrollable weblinks (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
FW_calcWeblink($$)
{
  my ($d,$wl) = @_;

  my $pm = AttrVal($d,"plotmode",$FW_plotmode);
  return if($pm eq "gnuplot");

  my $frx;
  if($defs{$wl}) {
    my $fr = AttrVal($wl, "fixedrange", undef);
    if($fr) {
      #klaus fixed range day, week, month or year
      if($fr eq "day" || $fr eq "week" || $fr eq "month" || $fr eq "year" ) {
        $frx=$fr;
      }
      else {
        my @range = split(" ", $fr);
        my @t = localtime;
        $FW_devs{$d}{from} = ResolveDateWildcards($range[0], @t);
        $FW_devs{$d}{to} = ResolveDateWildcards($range[1], @t); 
        return;
      }
    }
  }

  my $off = $FW_pos{$d};
  $off = 0 if(!$off);
  $off += $FW_pos{off} if($FW_pos{off});

  my $now = time();
  my $zoom = $FW_pos{zoom};
  $zoom = "day" if(!$zoom);
  $zoom = $frx if ($frx); #for fixedrange {day|week|...} klaus

  if($zoom eq "qday") {

    my $t = $now + $off*21600;
    my @l = localtime($t);
    $l[2] = int($l[2]/6)*6;
    $FW_devs{$d}{from}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]);
    $FW_devs{$d}{to}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]+6);

  } elsif($zoom eq "day") {

    my $t = $now + $off*86400;
    my @l = localtime($t);
    $FW_devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);
    $FW_devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]+1);

  } elsif($zoom eq "week") {

    my @l = localtime($now);
    my $start = (AttrVal($FW_wname, "endPlotToday", undef) ? 6 : $l[6]);
    my $t = $now - ($start*86400) + ($off*86400)*7;
    @l = localtime($t);
    $FW_devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

    @l = localtime($t+7*86400);
    $FW_devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

 } elsif($zoom eq "month") {

    my ($endDay, @l);
    if(AttrVal($FW_wname, "endPlotToday", undef)) {
      @l = localtime($now+86400);
      $endDay = $l[3];
      $off--;
    } else {
      @l = localtime($now);
      $endDay = 1;
    }
    while($off < -12) { # Correct the year
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $FW_devs{$d}{from} = sprintf("%04d-%02d-%02d", $l[5]+1900, $l[4]+1,$endDay);

    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $FW_devs{$d}{to}   = sprintf("%04d-%02d-%02d", $l[5]+1900, $l[4]+1,$endDay);

  } elsif($zoom eq "year") {

    my @l = localtime($now);
    $l[5] += $off;
    $FW_devs{$d}{from} = sprintf("%04d", $l[5]+1900);
    $FW_devs{$d}{to}   = sprintf("%04d", $l[5]+1901);

  }
}

##################
sub
FW_displayFileList($@)
{
  my ($heading,@files)= @_;
  FW_pO "$heading<br>";
  FW_pO "<table class=\"block\" id=\"at\">";
  my $row = 0;
  foreach my $f (@files) {
    FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
    FW_pH "cmd=style edit $f", $f, 1;
    FW_pO "</tr>";
    $row = ($row+1)%2;
  }
  FW_pO "</table>";
  FW_pO "<br>";
} 

##################
sub
FW_fileNameToPath($)
{
  my $name = shift;

  $attr{global}{configfile} =~ m,([^/]*)$,;
  my $cfgFileName = $1;
  if($name eq $cfgFileName) {
    return $attr{global}{configfile};
  } elsif($name =~ m/.*(css|svg)$/) {
    return "$FW_cssdir/$name";
  } elsif($name =~ m/.*gplot$/) {
    return "$FW_gplotdir/$name";
  } else {
    return "$MW_dir/$name";
  }
}

##################
# List/Edit/Save css and gnuplot files
sub
FW_style($$)
{
  my ($cmd, $msg) = @_;
  my @a = split(" ", $cmd);

  my $start = "<div id=\"content\"><table><tr><td>";
  my $end   = "</td></tr></table></div>";
  
  if($a[1] eq "list") {
    FW_pO $start;
    FW_pO "$msg<br><br>" if($msg);

    $attr{global}{configfile} =~ m,([^/]*)$,;
    my $cfgFileName = $1;
    FW_displayFileList("config file", $cfgFileName);
    FW_displayFileList("Own modules and helper files",
        FW_fileList("$MW_dir/^(.*sh|[0-9][0-9].*Util.*pm|.*cfg|.*holiday)\$"));
    FW_displayFileList("styles",
        FW_fileList("$FW_cssdir/^.*(css|svg)\$"));
    FW_displayFileList("gplot files",
        FW_fileList("$FW_gplotdir/^.*gplot\$"));
    FW_pO $end;


  } elsif($a[1] eq "select") {

    my @fl = FW_fileList("$FW_cssdir/.*style.css");

    FW_pO "$start<table class=\"block\" id=\"at\">";
    my $row = 0;
    foreach my $file (@fl) {
      next if($file =~ m/(svg_|smallscreen|touchpad)style.css/);
      $file =~ s/style.css//;
      $file = "Default" if($file eq "");
      FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      FW_pH "cmd=style set $file", "$file", 1;
      FW_pO "</tr>";
      $row = ($row+1)%2;
    }
    FW_pO "</table>$end";

  } elsif($a[1] eq "set") {
    if($a[2] eq "Default") {
      delete($attr{$FW_wname}{stylesheetPrefix});
    } else {
      $attr{$FW_wname}{stylesheetPrefix} = $a[2];
    }
    FW_readIcons($defs{$FW_wname});
    FW_pO "${start}Reload the page in the browser.$end";

  } elsif($a[1] eq "edit") {

    my $fileName = $a[2]; 
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FW_fileNameToPath($fileName);
    if(!open(FH, $filePath)) {
      FW_pO "<div id=\"content\">$filePath: $!</div>";
      return;
    }
    my $data = join("", <FH>);
    close(FH);

    my $ncols = $FW_ss ? 40 : 80;
    FW_pO "<div id=\"content\">";
    FW_pO "<form>";
    FW_pO     FW_submit("save", "Save $fileName");
    FW_pO     "&nbsp;&nbsp;";
    FW_pO     FW_submit("saveAs", "Save as");
    FW_pO     FW_textfieldv("saveName", 30, "saveName", $fileName);
    FW_pO     "<br><br>";
    FW_pO     FW_hidden("cmd", "style save $fileName");
    FW_pO     "<textarea name=\"data\" cols=\"$ncols\" rows=\"30\">" .
                "$data</textarea>";
    FW_pO   "</form>";
    FW_pO "</div>";

  } elsif($a[1] eq "save") {
    my $fileName = $a[2];
    $fileName = $FW_webArgs{saveName}
        if($FW_webArgs{saveAs} && $FW_webArgs{saveName});
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FW_fileNameToPath($fileName);

    if(!open(FH, ">$filePath")) {
      FW_pO "<div id=\"content\">$filePath: $!</div>";
      return;
    }
    $FW_data =~ s/\r//g if($^O !~ m/Win/);
    binmode (FH);
    print FH $FW_data;
    close(FH);

    my $ret = FW_fC("rereadcfg") if($filePath eq $attr{global}{configfile});
    $ret = FW_fC("reload $fileName") if($fileName =~ m,\.pm$,);
    $ret = ($ret ? "<h3>ERROR:</h3><b>$ret</b>" : "Saved the file $fileName");
    FW_style("style list", $ret);
    $ret = "";

  } elsif($a[1] eq "iconFor") {
    FW_pO "<div id=\"content\"><table class=\"iconFor\">";
    foreach my $i (sort grep {/^ico/} keys %FW_icons) {
      FW_pO "<tr><td>";
      FW_pO "<a href=\"$FW_ME?cmd=attr $a[2] icon $i\">$i</a>";
      FW_pO "</td><td>";
      FW_pO FW_makeImage($i);
      FW_pO "</td></tr>";
    }
    FW_pO "</table></div>";

  } elsif($a[1] eq "eventMonitor") {
    FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/js/console.js\"></script>";
    FW_pO "<div id=\"content\">";
    FW_pO "<div id=\"console\">";
    FW_pO "Events:<br>\n";
    FW_pO "</div>";
    FW_pO "</div>";

  } elsif($a[1] eq "addDef") {
    my $cnt = 0;
    my %isHelper;
    my $colCnt = ($FW_ss ? 2 : 8);
    FW_pO "<div id=\"content\">";

    FW_pO "Helpers:";
    FW_pO "<div id=\"block\"><table><tr>";
    foreach my $mn ( "at", "notify", "average", "dummy", "holiday", "sequence",
                     "structure", "watchdog", "weblink", "FileLog", "PID", "Twilight") {
      $isHelper{$mn} = 1;
      FW_pH "cmd=style addDef $mn", "$mn", 1;
      FW_pO "</tr><tr>" if(++$cnt % $colCnt == 0);
    }
    FW_pO "</tr>" if($cnt % $colCnt);
    FW_pO "</table></div>";

    $cnt = 0;
    FW_pO "<br>Other Modules:";
    FW_pO "<div id=\"block\"><table><tr>";
    foreach my $mn (sort keys %modules) {
      my $mp = $modules{$mn};
      next if($isHelper{$mn});
      # If it is not loaded, read it through to check if it has a Define
      # Function
      if(!$mp->{LOADED} && !$mp->{defChecked}) {
        $mp->{defChecked} = 1;
        if(open(FH,"$attr{global}{modpath}/FHEM/$modules{$mn}{ORDER}_$mn.pm")) {
          while(my $l = <FH>) {
            $mp->{DefFn} = 1 if(index($l, "{DefFn}")   > 0);
          }
          close(FH);
        }
      }

      next if(!$mp->{DefFn});
      FW_pH "cmd=style addDef $mn", "$mn", 1;
      FW_pO "</tr><tr>" if(++$cnt % $colCnt == 0);
    }
    FW_pO "</tr>" if($cnt % $colCnt);
    FW_pO "</table></div><br>";

    if($a[2]) {
      if(!open(FH, "$FW_commandref")) {
        FW_pO "<h3>comandref.html is missing</h3>";
      } else {
        my $inDef;
        while(my $l = <FH>) {
          if($l =~ m/<h3>$a[2]</) {
            $inDef = 1;
          } else {
            next if (!$inDef);
            last if($l =~ m/<h3>/);
          }
          chomp($l);
          $l =~ s/href="#/href="$FW_commandref#/g;
          FW_pO $l;
        }
        close(FH);
      }
    }

    FW_pO "</div>";

  }

}

##################
# print (append) to output
sub
FW_pO(@)
{
  my $arg = shift;
  return if(!defined($arg));
  $FW_RET .= $arg;
  $FW_RET .= "\n";
}

#################
# add href
sub
FW_pH(@)
{
   my ($link, $txt, $td, $class) = @_;

   FW_pO "<td>" if($td);
   $link = ($link =~ m,^/,) ? $link : "$FW_ME$FW_subdir?$link";
   $class = "" if(!defined($class));
   $class  = " class=\"$class\"" if($class);

   if($FW_ss || $FW_tp) {       # No pointer change if using onClick
     FW_pO "<a onClick=\"location.href='$link'\"><div$class>$txt</div></a>";

   } else {
     FW_pO "<a href=\"$link\"><div$class>$txt</div></a>";
   }
   FW_pO "</td>" if($td);
}

sub
FW_pHPlain(@)
{
   my ($link, $txt, $td) = @_;

   FW_pO "<td>" if($td);
   if($FW_ss || $FW_tp) {
     FW_pO "<a onClick=\"location.href='$FW_ME$FW_subdir?$link'\">$txt</a>";
   } else {
     FW_pO "<a href=\"$FW_ME$FW_subdir?$link\">$txt</a>";
   }
   FW_pO "</td>" if($td);
}



##################
# print formatted
sub
pF($@)
{
  my $fmt = shift;
  $FW_RET .= sprintf $fmt, @_;
}

##################
# fhem command
sub
FW_fC($@)
{
  my ($cmd, $unique) = @_;
  my $ret;
  if($unique) {
    $ret = AnalyzeCommand($FW_chash, $cmd);
  } else {
    $ret = AnalyzeCommandChain($FW_chash, $cmd);
  }
  return $ret;
}

##################
sub
FW_showWeblink($$$$)
{
  my ($d, $v, $t, $buttons) = @_;

  my $attr = AttrVal($d, "htmlattr", "");

  if($t eq "htmlCode") {
    $v = AnalyzePerlCommand($FW_chash, $v) if($v =~ m/^{(.*)}$/);
    FW_pO $v;

  } elsif($t eq "link") {
    FW_pO "<a href=\"$v\" $attr>$d</a>";    # no FW_pH, want to open extra browser

  } elsif($t eq "image") {
    FW_pO "<img src=\"$v\" $attr><br>";
    FW_pO "<br>";
    FW_pHPlain "detail=$d", $d if(!$FW_subdir);
    FW_pO "<br>";

  } elsif($t eq "iframe") {
    FW_pO "<iframe src=\"$v\" $attr>Iframes disabled</iframe>";
    FW_pO "<br>";
    FW_pHPlain "detail=$d", $d if(!$FW_subdir);
    FW_pO "<br>";


  } elsif($t eq "fileplot" || $t eq "dbplot" ) {

    # plots navigation buttons
    if($buttons &&
       ($defs{$d}{WLTYPE} eq "fileplot" || $defs{$d}{WLTYPE} eq "dbplot")&&
       !AttrVal($d, "fixedrange", undef)) {

      FW_zoomLink("zoom=-1", "Zoom-in", "zoom in");
      FW_zoomLink("zoom=1",  "Zoom-out","zoom out");
      FW_zoomLink("off=-1",  "Prev",    "prev");
      FW_zoomLink("off=1",   "Next",    "next");
      $buttons = 0;
      FW_pO "<br>";
    }

    my @va = split(":", $v, 3);
    if($defs{$d}{WLTYPE} eq "fileplot" && (@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile})) {
      FW_pO "Broken definition for fileplot $d: $v<br>";
    } elsif ($defs{$d}{WLTYPE} eq "dbplot" && (@va != 2 || !$defs{$va[0]})) {
      FW_pO "Broken definition for dbplot $d: $v<br>";
    } else {
      if(defined($va[2]) && $va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
      }

      if ($defs{$d}{WLTYPE} eq "dbplot") {
        $va[2] = "-";
      }

      my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);

      my $arg="$FW_ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
      if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
        my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
        FW_pO "<embed src=\"$arg\" type=\"image/svg+xml\" " .
              "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

      } else {
        FW_pO "<img src=\"$arg\"/>";
      }

      FW_pO "<br>";
      FW_pHPlain "detail=$d", $d if(!$FW_subdir);
      FW_pO "<br>";

    }
  }
  return $buttons;
}

sub
FW_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $name = $hash->{NAME};

  if($a[0] eq "set" && $a[2] eq "HTTPS") {
    TcpServer_SetSSL($hash);
  }

  if($a[2] eq "stylesheetPrefix" ||
     $a[2] eq "smallscreen") {

    # AttrFn is called too early, we have to set/del the attr here
    if($a[0] eq "set") {
      $attr{$name}{$a[2]} = (defined($a[3]) ? $a[3] : 1);
    } else {
      delete $attr{$name}{$a[2]};
    }
    FW_readIcons($hash);

  }

  return undef;
}


# recursively reads .gif .ico .jpg .png files and returns filenames as array
# recursion starts at $FW_icondir/$dir
# filenames are relative to $FW_icondir
sub
FW_readIconsFrom($$)
{
  my ($prepend,$dir)= @_;
  return if($dir =~ m,/\.svn,);

  #Debug "read icons from \"${FW_icondir}/${dir}\", prepend \"$prepend\"";
  
  my (@entries, @filenames);
  if(opendir(DH, "${FW_icondir}/${dir}")) {
    @entries= sort readdir(DH); # assures order: .gif  .ico  .jpg  .png
    closedir(DH);
  }
  #Debug "$#entries entries found.";
  foreach my $entry (@entries) {
    my $filename= "$dir/$entry";
    #Debug " entry: \"$entry\", filename= \"$filename\"";

    if( -d "${FW_icondir}/${filename}" ) {      # entry is a directory
      FW_readIconsFrom("${prepend}${entry}/", $filename)
        unless($entry eq "." || $entry eq "..");

    } elsif( -f "${FW_icondir}/${filename}") {  # entry is a regular file
      if($entry =~ m/^(.*)\.($ICONEXTENSION)$/i) {
        my $logicalname= $1;
        my $iconname= "${prepend}${logicalname}";
        #Debug "    icon: $iconname / $filename";
        $FW_icons{$iconname}= $filename;
      }
    }
  }
}

sub
FW_readIcons($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};
  
  %FW_icons = ();

  # read icons from default directory
  FW_readIconsFrom("", "default");

  # read icons from stylesheet specific directory, icons found here supersede
  # default icons with same name. Smallscreen a special "stylesheet"
  my $prefix = AttrVal($name, "smallscreen", "") ? "smallscreen" : "";
  $prefix = AttrVal($name, "stylesheetPrefix", $prefix);
  FW_readIconsFrom("", "$prefix") unless($prefix eq "");

  # read icons from explicit directory, icons found here supersede all other
  # icons with same name
  my $iconpath= AttrVal($name, "iconpath", "");
  FW_readIconsFrom("", "$iconpath") unless($iconpath eq "");

  # if now icons were found so far, read icons from icondir itself
  FW_readIconsFrom("", "") unless(%FW_icons);

  my %icons = %FW_icons;
  $hash->{fhemIcons} = \%icons;

  my $dumpLevel = 5;
  if($attr{global}{verbose} >= $dumpLevel) {
    Log $dumpLevel, "$name Icon dictionary for $FW_icondir follows...";
    foreach my $k (sort keys %FW_icons) {
      Log $dumpLevel, "$name $k => " . $FW_icons{$k};
    }
  }
}


sub
FW_getIcon($)
{
  my ($name)= @_;
  return $FW_icons{$name} ? $name : undef;
}

# returns the physical absolute path relative for the logical path
# examples:
#       FS20.on         ->      $FW_icondir/dark/FS20.on.png
#       weather/sunny   ->      $FW_icondir/default/weather/sunny.gif
sub
FW_IconPath($)
{
  my ($name)= @_;
  my $path= $FW_icons{$name};
  return $path ? $FW_icondir . "/" . $path : undef;
}

# returns the URL for the logical path 
# examples:
#       FS20.on         ->      /icons/FS20.on
#       weather/sunny   ->      /icons/sunny
sub
FW_IconURL($)
{
  my ($name)= @_;
  return "$FW_ME/icons/${name}";
}


sub
FW_dev2image($)
{
  my ($name) = @_;
  my $d = $defs{$name};
  return "" if(!$name || !$d);

  my ($type, $state) = ($d->{TYPE}, $d->{STATE});
  return "" if(!$type || !defined($state));

  my $model = $attr{$name}{model} if(defined($attr{$name}{model}));

  my (undef, $rstate) = ReplaceEventMap($name, [undef, $state], 0);
  $state =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"

  my $icon;
  my $devStateIcon = AttrVal($name, "devStateIcon", undef);
  if(defined($devStateIcon)) {
    my @list = split(" ", $devStateIcon);
    foreach my $l (@list) {
      my ($re,$iconName) = split(":", $l);
      if(defined($re) && $state =~ m/^$re$/) {
        return FW_getIcon($iconName);   # Can be used to preserve text
      }
    }
  }

  $icon = FW_getIcon("$name.$state")   if(!$icon);           # lamp.Aus.png
  $icon = FW_getIcon("$name.$rstate")  if(!$icon);           # lamp.on.png
  $icon = FW_getIcon($name)            if(!$icon);           # lamp.png
  $icon = FW_getIcon("$model.$state")  if(!$icon && $model); # HM-OU-LED16.off.png
  $icon = FW_getIcon($model)           if(!$icon && $model); # HM-OU-LED16.png
  $icon = FW_getIcon("$type.$state")   if(!$icon);           # FS20.Aus.png
  $icon = FW_getIcon("$type.$rstate")  if(!$icon);           # FS20.on.png
  $icon = FW_getIcon($type)            if(!$icon);           # FS20.png
  $icon = FW_getIcon($state)           if(!$icon);           # Aus.png
  $icon = FW_getIcon($rstate)          if(!$icon);           # on.png
  return $icon;
}

sub
FW_makeEdit($$$)
{
  my ($name, $n, $val) = @_;

  # Toggle Edit-Window visibility script.
  my $pgm = "Javascript:" .
             "s=document.getElementById('edit').style;".
             "s.display = s.display=='none' ? 'block' : 'none';".
             "s=document.getElementById('disp').style;".
             "s.display = s.display=='none' ? 'block' : 'none';";
  FW_pO "<td>";
  FW_pO "<a onClick=\"$pgm\">$n</a>";
  FW_pO "</td>";

  $val =~ s,\\\n,\n,g;
  my $eval = $val;
  $eval = "<pre>$eval</pre>" if($eval =~ m/\n/);
  FW_pO "<td>";
  FW_pO   "<div class=\"dval\" id=\"disp\">$eval</div>";
  FW_pO  "</td>";

  FW_pO  "</tr><tr><td colspan=\"2\">";
  FW_pO   "<div id=\"edit\" style=\"display:none\"><form>";
  my $cmd = "modify";
  my $ncols = $FW_ss ? 30 : 60;
  FW_pO     "<textarea name=\"val.${cmd}$name\" cols=\"$ncols\" rows=\"10\">".
          "$val</textarea>";
  FW_pO     "<br>" . FW_submit("cmd.${cmd}$name", "$cmd $name");
  FW_pO   "</form></div>";
  FW_pO  "</td>";
}

sub
FW_dumpFileLog($$$)
{
  my ($d, $oneRow,$row) = @_;

  foreach my $f (FW_fileList($defs{$d}{logfile})) {
    my $nr;

    if($oneRow) {
      pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
      pF "<td><div class=\"dname\">$f</div></td>";
    }
    foreach my $ln (split(",", AttrVal($d, "logtype", "text"))) {
      my ($lt, $name) = split(":", $ln);
      $name = $lt if(!$name);
      if(!$oneRow) {
        pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
        pF "<td><div class=\"dname\">%s</div></td>", ($nr ? "" : $f);
      }
      FW_pH "cmd=logwrapper $d $lt $f",
              "<div class=\"dval\">$name</div>", 1, "dval";
      if(!$oneRow) {
        FW_pO "</tr>";
        $row++;
      }
      $nr++;
    }
    if($oneRow) {
      FW_pO "</tr>";
      $row++;
    }
  }
  return $row;
}

sub
FW_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $filter = $ntfy->{inform};
  return undef if(!$filter);

  my $ln = $ntfy->{NAME};
  my $dn = $dev->{NAME};
  my $data;

  my $rn = AttrVal($dn, "room", "");
  if($filter eq "all" || $rn =~ m/\b$filter\b/) {
    my @old = ($FW_wname, $FW_ME, $FW_longpoll, $FW_ss, $FW_tp, $FW_subdir);
    $FW_wname = $ntfy->{SNAME};
    $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
    $FW_subdir = "";
    $FW_longpoll = 1;
    $FW_ss = AttrVal($FW_wname, "smallscreen", 0);
    $FW_tp = AttrVal($FW_wname, "touchpad", $FW_ss);
    my ($allSet, $cmdlist, $txt) = FW_devState($dn, "");
    ($FW_wname, $FW_ME, $FW_longpoll, $FW_ss, $FW_tp, $FW_subdir) = @old;
    $data = "$dn;$dev->{STATE};$txt\n";

  } elsif($filter eq "console") {
    if($dev->{CHANGED}) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      if($attr{global}{mseclog}) {
        my ($seconds, $microseconds) = gettimeofday();
        $tn .= sprintf(".%03d", $microseconds/1000);
      }
      my $max = int(@{$dev->{CHANGED}});
      my $dt = $dev->{TYPE};
      for(my $i = 0; $i < $max; $i++) {
        $data .= "$tn $dt $dn ".$dev->{CHANGED}[$i]."<br>\n";
      }
    }

  }

  if($data) {
    # Collect multiple changes (e.g. from noties) into one message
    $ntfy->{INFORMBUF} .= $data;
    RemoveInternalTimer($ln);
    InternalTimer(gettimeofday()+0.1, "FW_FlushInform", $ln, 0);
  }

  return undef;
}

sub
FW_FlushInform($)
{
  my ($name) = @_;
  my $hash = $defs{$name};
  return if(!$hash);
  my $c = $hash->{CD};
  print $c $hash->{INFORMBUF};
  $hash->{INFORMBUF}="";
}

###################
# Compute the state (==second) column
sub
FW_devState($$)
{
  my ($d, $rf) = @_;

  my ($hasOnOff, $cmdlist, $link);

  my $webCmd = AttrVal($d, "webCmd", "");
  my $allSets = getAllSets($d);
  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));

  $hasOnOff = (!$webCmd && $allSets =~ m/\bon\b/ && $allSets =~ m/\boff\b/);
  my $txt = $state;
  if(defined(AttrVal($d, "showtime", undef))) {
    my $v = $defs{$d}{READINGS}{state}{TIME};
    $txt = $v if(defined($v));

  } elsif($allSets =~ m/\bdesired-temp:/) {
    $txt = ReadingsVal($d, "measured-temp", "");
    $txt =~ s/ .*//;
    $txt .= "&deg;C";
    $cmdlist = "desired-temp";

  } else {
    my $icon;
    $icon = FW_dev2image($d);
    #Debug "Dev2Image returned $icon for $d";
    $txt = "<img src=\"" . FW_IconURL($icon) . "\" alt=\"$txt\"/>" if($icon);
  }

  $txt = "<div id=\"$d\" align=\"center\" class=\"col2\">$txt</div>";
  if($webCmd) {
    my @a = split(":", $webCmd);
    $link = "cmd.$d=set $d $a[0]";
    $cmdlist = $webCmd;

  } elsif($hasOnOff && !$cmdlist) {
    # Have to cover: "on:An off:Aus", "A0:Aus AI:An Aus:off An:on"
    my $on  = ReplaceEventMap($d, "on", 1);
    my $off = ReplaceEventMap($d, "off", 1);
    $link = "cmd.$d=set $d " . ($state eq $on ? $off : $on);
    $cmdlist = "$on:$off";

  }

  if($link) {
    my $room = AttrVal($d, "room", undef);
    if($room) {
      if($FW_room && $room =~ m/\b$FW_room\b/) {
        $room = $FW_room;
      } else {
        $room =~ s/,.*//;
      }
      $link .= "&room=$room";
    }
    if($FW_longpoll) {
      $txt = "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";

    } elsif($FW_ss || $FW_tp) {
      $txt ="<a onClick=\"location.href='$FW_ME$FW_subdir?$link$rf'\">$txt</a>";

    } else {
      $txt = "<a href=\"$FW_ME$FW_subdir?$link$rf\">$txt</a>";

    }
  }
  return ($allSets, $cmdlist, $txt);
}

#####################################
sub
FW_pathList()
{
   return "web server root:      $FW_dir\n".
          "icon directory:       $FW_icondir\n".
          "doc directory:        $FW_docdir\n".
          "css directory:        $FW_cssdir\n".
          "gplot directory:      $FW_gplotdir\n".
          "javascript directory: $FW_jsdir";
}


sub
FW_Get($@)
{
  my ($hash, @a) = @_;
  $FW_wname= $hash->{NAME};
  %FW_icons= %{$hash->{fhemIcons}};

  my $arg = (defined($a[1]) ? $a[1] : "");
  if($arg eq "icon") {
    return "need one icon as argument" if(int(@a) != 3);
    my $icon= FW_IconPath($a[2]);
    return defined($icon) ? $icon : "no such icon";

  } elsif($arg eq "pathlist") {
    return FW_pathList();

  } else {
    return "Unknown argument $arg choose one of icon pathlist";

  }
}


#####################################
sub
FW_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . "rereadicons"
        unless($a[1] eq "rereadicons");

  FW_readIcons($hash);
  return undef;
}

#####################################
sub
FW_closeOldClients()
{
  my $now = time();
  foreach my $dev (keys %defs) {
    next if(!$defs{$dev}{TYPE} || $defs{$dev}{TYPE} ne "FHEMWEB" ||
            !$defs{$dev}{LASTACCESS} || $defs{$dev}{inform} ||
            ($now - $defs{$dev}{LASTACCESS}) < 60);
    Log 4, "Closing connection $dev";
    FW_Undef($defs{$dev}, "");
    delete $defs{$dev};
  }
  InternalTimer($now+60, "FW_closeOldClients", 0, 0);
}

1;

=pod
=begin html

<a name="FHEMWEB"></a>
<h3>FHEMWEB</h3>
<ul>
  FHEMWEB is the builtin web-frontend (webpgm2). It implements a simple web
  server (optionally with Basic-Auth and HTTPS), so no additional program is
  needed.
  <br> <br>

  <a name="FHEMWEBdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMWEB &lt;tcp-portnr&gt; [global]</code>
    <br><br>
    Enable the webfrontend on port &lt;tcp-portnr&gt;. If global is specified,
    then requests from all interfaces (not only localhost / 127.0.0.1) are
    serviced.<br>
    To enable listening on IPV6 see the comments <a href="#port">here</a>.
    <br><br>
    Feature: http://host:port/fhem/icons/&lt;devicename&gt; will return
    the icon associated with the current status of &lt;devicename&gt;.

  </ul>
  <br>

  <a name="FHEMWEBset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; rereadicons</code>
    <br><br>
    Rereads the icons in the icon path and updates the mapping from logical icons to physical files.
    Use after adding, deleting or changing icons.
    <br><br>

  </ul>

  <a name="FHEMWEBget"></a>
  <b>Get</b>
  <ul>
    <li>icon &lt;logical icon&gt;<br>

        returns the absolute path to the logical icon. Example:
        <ul>
          <code>get myFHEMWEB icon FS20.on<br>
          /data/Homeautomation/fhem/FHEM/FS20.on.png
          </code>
        </ul>
    <li>pathlist<br>
        return FHEMWEB specific directories, where files for given types are located
    <br><br>

  </ul>

  <a name="FHEMWEBattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="webname"></a>
    <li>webname<br>
        Path after the http://hostname:port/ specification. Defaults to fhem,
        i.e the default http address is http://localhost:8083/fhem
        </li><br>

    <a name="refresh"></a>
    <li>refresh<br>
        If set, a http-equiv="refresh" entry will be genererated with the given
        argument (i.e. the browser will reload the page after the given
        seconds).
        </li><br>

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
              Fhemweb will offer zoom and scroll buttons in order to navigate
              in the current logfile, i.e. you can select just a part of the
              data to be displayed. The more data is contained in a single
              logfile, the easier you can navigate. The recommendation is to
              store the data for a whole year in one logfile.  The data is
              converted into an image on the backend with gnuplot.</li>
          <li>SVG<br>
              The same scrolling as with gnuplot scroll, but the data is sent
              as an SVG script to the frontend, which will compute
              the image: no need for gnuplot on the backend.
              This is the default. Note: SVG is supported on the Android
              platform by Opera/Firefox and the Internet Explorer before 9
              needs a plugin.
              </li>
        </ul>
        See also the attribute fixedrange.
        Note: for gnuplot & gnuplot-scroll mode the gnuplot output is
        redirected to the file gnuplot.err in the /tmp directory
        </li><br>

    <a name="plotsize"></a>
    <li>plotsize<br>
        the default size of the plot, in pixels, separated by comma:
        width,height. You can set individual sizes by setting the plotsize of
        the weblink. Default is 800,160 for desktop, and 480,160 for
        smallscreen.
        </li><br>

    <a name="fixedrange"></a>
    <li>fixedrange<br>
        Can be applied to weblink devices (FHEMWEB).<br>
        Contains two time specs in the form YYYY-MM-DD separated by a space.
        In plotmode gnuplot-scroll or SVG the given time-range will be used,
        and no scrolling for this weblinks will be possible. Needed e.g. for
        looking at last-years data without scrolling.<br><br>
        If the value is one of day, week, month, year than set the zoom level
        for this weblink independently of the user specified zoom-level.
        This is useful for pages with multiple plots: one of the plots is best
        viewed in with the default (day) zoom, the other one with a week zoom.
        </li><br>

    <a name="endPlotToday"></a>
    <li>endPlotToday<br>
        If this FHEMWEB attribute ist set to 1, then week and month plots will
        end today. Else the current week (starting at Sunday) or the current
        month will be shown.<br>
        </li><br>

    <a name="smallscreen"></a>
    <a name="touchpad"></a>
    <li>smallscreen, touchpad<br>
        Optimize for small screen size (i.e. smartphones) or for touchpad
        devices (i.e. tablets)<br>
        Note: The default configuration installed with make install-pgm2
        installs 2 FHEMWEB instances: port 8083 for desktop browsers and
        port 8084 for smallscreen browsers, both using SVG rendering.
        On Android SVG is supported by Opera/Firefox.<br>

        WebApp suppport if specifying one of the above options: After viewing
        the site on the iPhone or iPad in Safari, add it to the home-screen to
        get full-screen support.
        </li><br>

    <a name="plotfork"></a>
    <li>plotfork<br>
        If set, generate the logs in a parallel process. Note: do not use it
        on Windows and on systems with small memory foorprint.
    </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        request a username/password authentication for access. You have to set
        the basicAuth attribute to the Base64 encoded value of
        &lt;user&gt;:&lt;password&gt;, e.g.:<ul>
        # Calculate first the encoded string with the commandline program<br>
        $ echo -n fhemuser:secret | base64<br>
        ZmhlbXVzZXI6c2VjcmV0<br>
        fhem.cfg:<br>
        attr WEB basicAuth ZmhlbXVzZXI6c2VjcmV0
        </ul>
        You can of course use other means of base64 encoding, e.g. online
        Base64 encoders. If basicAuthMsg is set, it will be displayed in the
        popup window when requesting the username/password.<br>
        <br>
        If the argument of basicAuth is enclosed in {}, then it will be
        evaluated, and the $user and $password variable will be set to the
        values entered. If the return value is true, then the password will be
        accepted.
        Example:<br>
        <code>
        attr WEB basicAuth { "$user:$password" eq "admin:secret" }<br>
        attr WEB basicAuth {use FritzBoxUtils;;FB_checkPw("localhost","$password") }
        </code>


    </li><br>

    <a name="HTTPS"></a>
    <li>HTTPS<br>
        Enable HTTPS connections. This feature requires the perl module
        IO::Socket::SSL, to be installed with cpan -i IO::Socket::SSL or
        apt-get install libio-socket-ssl-perl; OSX and the FritzBox-7390
        already have this module.<br>

        A local certificate has to be generated into a directory called certs,
        this directory <b>must</b> be in the <a href="#modpath">modpath</a>
        directory, at the same level as the FHEM directory.
        <ul>
        mkdir certs<br>
        cd certs<br>
        openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
        </ul>
      <br><br>
    </li>

    <li><a href="#allowfrom">allowfrom</a></li>
    </li><br>
    <li><a href="#loglevel">loglevel</a></li>
    </li><br>

    <a name="stylesheetPrefix"></a>
    <li>stylesheetPrefix<br>
      prefix for the files style.css, svg_style.css and svg_defs.svg. If the file
      with the prefix is missing, the default file (without prefix) will be used.
      These files have to be placed into the FHEM directory, and can be selected
      directly from the "Select style" FHEMWEB menu entry. Example:
      <ul>
        attr WEB stylesheetPrefix dark<br>
        <br>
        Referenced files:<br>
        <ul>
        darksvg_defs.svg<br>
        darksvg_style.css<br>
        darkstyle.css<br>
        </ul>
        <br>
      </ul>
      </li>

    <a name="hiddenroom"></a>
    <li>hiddenroom<br>
        Comma separated list of rooms to "hide", i.e. not to show. Special
        values are input, detail and save, in which case the input areas, link
        to the detailed views or save button is hidden (although each aspect
        still can be addressed through url manipulation).<br>
        The list can also contain values from the additional "Howto/Wiki/FAQ"
        block.
        </li>
        <br>

    <a name="hiddengroup"></a>
    <li>hiddengroup<br>
        Comma separated list of groups to "hide", i.e. not to show in any room
        of this FHEMWEB instance.<br>
        Example:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li>
        <br>


    <a name="longpoll"></a>
    <li>longpoll<br>
        Affects devices states in the room overview only.<br>
        In this mode status update is refreshed more or less instantaneously,
        and state change (on/off only) is done without requesting a complete
        refresh from the server.
        </li>
        <br>

    <a name="redirectCmds"></a>
    <li>redirectCmds<br>
        Clear the browser URL window after issuing the command by redirecting
        the browser, as a reload for the same site might have unintended
        side-effects. Default is 1 (enabled). Disable it by setting this
        attribute to 0 if you want to study the command syntax, in order to
        communicate with FHEMWEB.
        </li>
        <br>

    <a name="webCmd"></a>
    <li>webCmd<br>
        Colon separated list of commands to be shown in the room overview for a
        certain device.  On smallscreen devices only the first value is
        accessible.<br>
        If the first value references a command, for which "set
        device ?" lists a number possible choices (e.g. desired-temp for FHT
        devices), then a select widget will be displayed. If the values are
        "slider,min,step,max", then a javascript driven slider is displayed.
        if the value is "time", then a javascript timepicker is displayed.
        If the command is state, then the value will be used as a command.<br>
        Examples:
        <ul>
          attr lamp webCmd on:off:on-for-timer 10<br>
          define d1 dummy<br>
          attr d1 webCmd state<br>
          attr d1 set setList state:on,off<br>
          define d2 dummy<br>
          attr d2 webCmd state<br>
          attr d2 set setList state:slider,0,1,10<br>
          define d3 dummy<br>
          attr d3 webCmd state<br>
          attr d3 set setList state:time<br>
        </ul>
        Note: this is an attribute for the displayed device, not for the FHEMWEB
        instance.
        </li>
        <br>

    <a name="fwmodpath"></a>
    <li>fwmodpath<br>
        Set the "modpath" for this intance of FHEMWEB. Used to search .gplot
        files, pictures, etc. Default is the <a href="#modpath">modpath</a>/FHEM directory.
        </li>
        <br>

    <a name="fwcompress"></a>
    <li>fwcompress<br>
        Enable compressing the HTML data (default is 1, i.e. yes, use 0 to switch it off).
        </li>
        <br>

    <a name="icon"></a>
    <li>icon<br>
        Set the icon for a device in the room overview. There is an
        icon-chooser in FHEMWEB to ease this task.  Setting icons for the room
        itself is indirect: there must exist an icon with the name
        ico<ROOMNAME>.png in the modpath/fwmodpath directory.
        </li>
        <br>

    <a name="reverseLogs"></a>
    <li>reverseLogs<br>
        Display the lines from the logfile in a reversed order, newest on the
        top, so that you dont have to scroll down to look at the latest entries.
        Note: enabling this attribute will prevent FHEMWEB from streaming
        logfiles, resulting in a considerably increased memory consumption
        (about 6 times the size of the file on the disk).
        </li>
        <br>

    <a name="CORS"></a>
    <li>CORS<br>
        If set to 1, FHEMWEB will supply a "Cross origin resource sharing"
        header, see the wikipedia for details.
        </li>
        <br>

    <a name="devStateIcon"></a>
    <li>devStateIcon<br>
        Space separated list of regexp/icon-name pairs. If the state of the
        device matches regexp, then the corresponding icon-name will be
        displayed. If icon-name does not exist in the fhem/www/images
        directory, then the status text will be displayed. Note: the icon-name
        must be specified without the trailing .png/.jpg suffix.<br>
        Example:<br>
        <ul>
        attr lamp devStateIcon on:closed off:open<br>
        attr lamp devStateIcon .*:noIcon<br>
        </ul>
        </li>
        <br>

    </ul>

    See also <a href="#room">room</a> and <a href="#group">group</a> attributes.
  </ul>



=end html
=cut
