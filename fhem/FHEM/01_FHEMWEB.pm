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
sub FW_iconName($);
sub FW_iconPath($);
sub FW_answerCall($);
sub FW_dev2image($;$);
sub FW_devState($$@);
sub FW_digestCgi($);
sub FW_doDetail($);
sub FW_fatal($);
sub FW_fileList($);
sub FW_parseColumns();
sub FW_htmlEscape($);
sub FW_logWrapper($);
sub FW_makeEdit($$$);
sub FW_makeImage(@);
sub FW_makeTable($$$@);
sub FW_makeTableFromArray($$@);
sub FW_pF($@);
sub FW_pH(@);
sub FW_pHPlain(@);
sub FW_pO(@);
sub FW_readIcons($);
sub FW_readIconsFrom($$);
sub FW_returnFileAsStream($$$$$);
sub FW_roomOverview($);
sub FW_select($$$$$@);
sub FW_serveSpecial($$$$);
sub FW_showRoom();
sub FW_style($$);
sub FW_submit($$@);
sub FW_textfield($$$);
sub FW_textfieldv($$$$);
sub FW_updateHashes();
sub FW_visibleDevices(;$);

use vars qw($FW_dir);     # base directory for web server
use vars qw($FW_icondir); # icon base directory
use vars qw($FW_cssdir);  # css directory
use vars qw($FW_gplotdir);# gplot directory
use vars qw($MW_dir);     # moddir (./FHEM), needed by edit Files in new
                          # structure

use vars qw($FW_ME);      # webname (default is fhem), used by 97_GROUP/weblink
use vars qw($FW_ss);      # is smallscreen, needed by 97_GROUP/95_VIEW
use vars qw($FW_tp);      # is touchpad (iPad / etc)
use vars qw($FW_sp);      # stylesheetPrefix

# global variables, also used by 97_GROUP/95_VIEW/95_FLOORPLAN
use vars qw(%FW_types);   # device types,
use vars qw($FW_RET);     # Returned data (html)
use vars qw($FW_RETTYPE); # image/png or the like
use vars qw($FW_wname);   # Web instance
use vars qw($FW_subdir);  # Sub-path in URL, used by FLOORPLAN/weblink
use vars qw(%FW_pos);     # scroll position
use vars qw($FW_cname);   # Current connection name
use vars qw(%FW_hiddenroom); # hash of hidden rooms, used by weblink
use vars qw($FW_plotmode);# Global plot mode (WEB attribute), used by SVG
use vars qw($FW_plotsize);# Global plot size (WEB attribute), used by SVG
use vars qw(%FW_webArgs); # all arguments specified in the GET
use vars qw(@FW_fhemwebjs);# List of fhemweb*js scripts to load
use vars qw($FW_detail);   # currently selected device for detail view
use vars qw($FW_cmdret);   # Returned data by the fhem call
use vars qw($FW_room);      # currently selected room
use vars qw($FW_formmethod);
use vars qw(%FW_visibleDeviceHash);

$FW_formmethod = "post";

my $FW_zlib_checked;
my $FW_use_zlib = 1;
my $FW_activateInform = 0;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my @FW_httpheader; # HTTP header, line by line
my @FW_enc;        # Accepted encodings (browser header)
my $FW_data;       # Filecontent from browser when editing a file
my %FW_icons;      # List of icons
my @FW_iconDirs;   # Directory search order for icons
my $FW_RETTYPE;    # image/png or the like
my %FW_rooms;      # hash of all rooms
my %FW_types;      # device types, for sorting
my %FW_hiddengroup;# hash of hidden groups
my $FW_inform;
my $FW_XHR;        # Data only answer, no HTML
my $FW_jsonp;      # jasonp answer (sending function calls to the client)
my $FW_headercors; #
my $FW_chash;      # client fhem hash
my $FW_encoding="UTF-8";


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
  $hash->{ActivateInformFn} = "FW_ActivateInform";
  no warnings 'qw';
  my @attrList = qw(
    CORS:0,1
    HTTPS:1,0
    SVGcache:1,0
    allowedCommands
    allowfrom
    basicAuth
    basicAuthMsg
    column
    defaultRoom
    endPlotNow:1,0
    endPlotToday:1,0
    fwcompress:0,1
    hiddengroup
    hiddenroom
    iconPath
    longpoll:0,1
    longpollSVG:1,0
    menuEntries
    ploteditor:always,onClick,never
    plotfork:1,0
    plotmode:gnuplot,gnuplot-scroll,SVG
    plotsize
    nrAxis
    redirectCmds:0,1
    refresh
    reverseLogs:0,1
    roomIcons
    sortRooms
    smallscreen:unused
    stylesheetPrefix
    touchpad:unused
    webname
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);


  ###############
  # Initialize internal structures
  map { addToAttrList($_) } ( "webCmd", "icon", "devStateIcon",
                                "sortby", "devStateStyle");
  InternalTimer(time()+60, "FW_closeOldClients", 0, 0);

  $FW_dir      = "$attr{global}{modpath}/www";
  $FW_icondir  = "$FW_dir/images";
  $FW_cssdir   = "$FW_dir/pgm2";
  $FW_gplotdir = "$FW_dir/gplot";
  if(opendir(DH, "$FW_dir/pgm2")) {
    @FW_fhemwebjs = sort grep /^fhemweb.*js$/, readdir(DH);
    closedir(DH);
  }

  $data{webCmdFn}{slider}     = "FW_sliderFn";
  $data{webCmdFn}{timepicker} = "FW_timepickerFn";
  $data{webCmdFn}{noArg}      = "FW_noArgFn";
  $data{webCmdFn}{textField}  = "FW_textFieldFn";
  $data{webCmdFn}{"~dropdown"}= "FW_dropdownFn"; # Should be the last
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

  foreach my $pe ("fhemSVG", "openautomation", "default") {
    FW_readIcons($pe);
  }

  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log3 $hash, 1, "$ret. Exiting.";
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

  my $c = $hash->{CD};
  if(!$FW_zlib_checked) {
    $FW_zlib_checked = 1;
    $FW_use_zlib = AttrVal($FW_wname, "fwcompress", 1);
    if($FW_use_zlib) {
      eval { require Compress::Zlib; };
      if($@) {
        $FW_use_zlib = 0;
        Log3 $FW_wname, 1, $@;
        Log3 $FW_wname, 1,
               "$FW_wname: Can't load Compress::Zlib, deactivating compression";
        $attr{$FW_wname}{fwcompress} = 0;
      }
    }
  }



  # Data from HTTP Client
  my $buf;
  my $ret = sysread($c, $buf, 1024);

  if(!defined($ret) || $ret <= 0) {
    CommandDelete(undef, $name);
    Log3 $FW_wname, 4, "Connection closed for $name";
    return;
  }

  $hash->{BUF} .= $buf;
  if($defs{$FW_wname}{SSL}) {
    while($c->pending()) {
      sysread($c, $buf, 1024);
      $hash->{BUF} .= $buf;
    }
  }

  if(!$hash->{HDR}) {
    return if($hash->{BUF} !~ m/^(.*)(\n\n|\r\n\r\n)(.*)$/s);
    $hash->{HDR} = $1;
    $hash->{BUF} = $3;
    if($hash->{HDR} =~ m/Content-Length: ([^\r\n]*)/s) {
      $hash->{CONTENT_LENGTH} = $1;
    }
  }
  return if($hash->{CONTENT_LENGTH} &&
            length($hash->{BUF})<$hash->{CONTENT_LENGTH});

  @FW_httpheader = split("[\r\n]", $hash->{HDR});
  delete($hash->{HDR});

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
    my @authLine = grep /Authorization: Basic/, @FW_httpheader;
    my $secret = $authLine[0];
    $secret =~ s/^Authorization: Basic // if($secret);
    my $pwok = ($secret && $secret eq $basicAuth);
    if($secret && $basicAuth =~ m/^{.*}$/ || $headerOptions[0]) {
      eval "use MIME::Base64";
      if($@) {
        Log3 $FW_wname, 1, $@;

      } else {
        my ($user, $password) = split(":", decode_base64($secret));
        $pwok = eval $basicAuth;
        Log3 $FW_wname, 1, "basicAuth expression: $@" if($@);
      }
    }
    if($headerOptions[0]) {
      print $c "HTTP/1.1 200 OK\r\n",
             $FW_headercors,
             "Content-Length: 0\r\n\r\n";
      delete $hash->{CONTENT_LENGTH};
      delete $hash->{BUF};
      return;
      exit(1);
    };
    if(!$pwok) {
      my $msg = AttrVal($FW_wname, "basicAuthMsg", "Fhem: login required");
      print $c "HTTP/1.1 401 Authorization Required\r\n",
             "WWW-Authenticate: Basic realm=\"$msg\"\r\n",
             $FW_headercors,
             "Content-Length: 0\r\n\r\n";
      delete $hash->{CONTENT_LENGTH};
      delete $hash->{BUF};
      return;
    };
  }
  #############################

  my $now = time();
  @FW_enc = grep /Accept-Encoding/, @FW_httpheader;
  my ($method, $arg, $httpvers) = split(" ", $FW_httpheader[0], 3);
  $arg .= "&".$hash->{BUF} if($hash->{CONTENT_LENGTH});
  delete $hash->{CONTENT_LENGTH};
  delete $hash->{BUF};
  $hash->{LASTACCESS} = $now;

  $arg = "" if(!defined($arg));
  Log3 $FW_wname, 4, "HTTP $name GET $arg";
  my $pid;
  if(AttrVal($FW_wname, "plotfork", undef)) {
    # Process SVG rendering as a parallel process
    return if(($arg =~ m+/SVG_showLog+) && ($pid = fork));
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
  Log3 $FW_wname, 4, "$arg / RL:$length / $FW_RETTYPE / $compressed / $expires";
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

  $file = "$FW_sp$file" if($ext eq "css" && -f "$dir/$FW_sp$file.$ext");
  $FW_RETTYPE = ext2MIMEType($ext);
  return FW_returnFileAsStream("$dir/$file.$ext", "",
                                        $FW_RETTYPE, 0, $cacheable);
}

sub
FW_answerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FW_cname};      # cache, else rereadcfg will delete us

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=$FW_encoding";
  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");

  $MW_dir = "$attr{global}{modpath}/FHEM";
  $FW_sp = AttrVal($FW_wname, "stylesheetPrefix", "");
  $FW_ss = ($FW_sp =~ m/smallscreen/);
  $FW_tp = ($FW_sp =~ m/smallscreen|touchpad/);
  @FW_iconDirs = grep { $_ } split(":", AttrVal($FW_wname, "iconPath",
                                "$FW_sp:default:fhemSVG:openautomation"));
  if($arg =~ m,$FW_ME/floorplan/([a-z0-9.:_]+),i) { # FLOORPLAN: special icondir
    unshift @FW_iconDirs, $1;
    FW_readIcons($1);
  }

  # /icons/... => current state of ...
  # also used for static images: unintended, but too late to change
  if($arg =~ m,^$FW_ME/icons/(.*)$,) {
    my ($icon,$cacheable) = (urlDecode($1), 1);
    my $iconPath = FW_iconPath($icon);

    # if we do not have the icon, we convert the device state to the icon name
    if(!$iconPath) {
      ($icon, undef, undef) = FW_dev2image($icon);
      $cacheable = 0;
      return 0 if(!$icon);
      $iconPath = FW_iconPath($icon);
    }
    $iconPath =~ m/(.*)\.([^.]*)/;
    return FW_serveSpecial($1, $2, $FW_icondir, $cacheable);

  } elsif($arg =~ m,^$FW_ME/(.*)/([^/]*)$,) {          # the "normal" case
    my ($dir, $ofile, $ext) = ($1, $2, "");
    $dir =~ s/\.\.//g;
    $dir =~ s,www/,,g; # Want commandref.html to work from file://...

    my $file = $ofile;
    $file =~ s/\?.*//; # Remove timestamp of CSS reloader
    if($file =~ m/^(.*)\.([^.]*)$/) {
      $file = $1; $ext = $2;
    }
    my $ldir = "$FW_dir/$dir";
    $ldir = "$FW_dir/pgm2" if($dir eq "css" || $dir eq "js"); # FLOORPLAN compat
    $ldir = "$attr{global}{modpath}/docs" if($dir eq "docs");

    if(-r "$ldir/$file.$ext") {                # no return for FLOORPLAN
      return FW_serveSpecial($file, $ext, $ldir, ($arg =~ m/nocache/) ? 0 : 1);
    }
    $arg = "/$dir/$ofile";

  } elsif($arg =~ m/^$FW_ME(.*)/) {
    $arg = $1; # The stuff behind FW_ME, continue to check for commands/FWEXT

  } else {
    my $c = $me->{CD};
    Log3 $FW_wname, 4, "$FW_wname: redirecting $arg to $FW_ME";
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n", $FW_headercors,
             "Location: $FW_ME\r\n\r\n";
    return -1;

  }


  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");
  my ($cmd, $cmddev) = FW_digestCgi($arg);


  if($FW_inform) {      # Longpoll header
    if($FW_inform =~ /type=/) {
      foreach my $kv (split(";", $FW_inform)) {
        my ($key,$value) = split("=", $kv, 2);
        $me->{inform}{$key} = $value;
      }

    } else {                     # Compatibility mode
      $me->{inform}{type}   = ($FW_room ? "status" : "raw");
      $me->{inform}{filter} = ($FW_room ? $FW_room : ".*");
    }
    my $filter = $me->{inform}{filter};
    $filter = "NAME=.*" if($filter eq "room=all");
    $filter = "room!=.*" if($filter eq "room=Unsorted");

    my %h = map { $_ => 1 } devspec2array($filter);
    $me->{inform}{devices} = \%h;
    %FW_visibleDeviceHash = FW_visibleDevices();

    # NTFY_ORDER is larger than the normal order (50-)
    $me->{NTFY_ORDER} = $FW_cname;   # else notifyfn won't be called
    %ntfyHash = ();

    my $c = $me->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
       $FW_headercors,
       "Content-Type: application/octet-stream; charset=$FW_encoding\r\n\r\n",
       FW_roomStatesForInform($me);
    return -1;
  }

  my $docmd = 0;
  $docmd = 1 if($cmd &&
                $cmd !~ /^showlog/ &&
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
  # FHEMWEB extensions (FLOORPLOAN, SVG_WriteGplot, etc)
  my $FW_contentFunc;
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($arg !~ m/^$k/);
      $FW_contentFunc = $h->{CONTENTFUNC};
      next if($h !~ m/HASH/ || !$h->{FUNC});
      #Returns undef as FW_RETTYPE if it already sent a HTTP header
      no strict "refs";
      ($FW_RETTYPE, $FW_RET) = &{$h->{FUNC}}($arg);
      use strict "refs";
      return defined($FW_RETTYPE) ? 0 : -1;
    }
  }


  #Now execute the command
  $FW_cmdret = "";
  if($docmd) {
    $FW_cmdret = FW_fC($cmd, $cmddev);
    if($cmd =~ m/^define +([^ ]+) /) { # "redirect" after define to details
      $FW_detail = $1;
    }
  }

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

  my $t = AttrVal("global", "title", "Home, Sweet Home");

  FW_pO '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" '.
                '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  FW_pO '<html xmlns="http://www.w3.org/1999/xhtml">';
  FW_pO "<head>\n<title>$t</title>";
  FW_pO '<link rel="shortcut icon" href="'.FW_IconURL("favicon").'" />';

  # Enable WebApps
  if($FW_tp || $FW_ss) {
    my $icon = $FW_ME."/images/default/fhemicon_ios.png";
    if($FW_ss) {
       FW_pO '<meta name="viewport" '.
                   'content="initial-scale=1.0,user-scalable=1"/>';
    } elsif($FW_tp) {
      FW_pO '<meta name="viewport" content="width=768"/>';
    }
    FW_pO '<meta name="apple-mobile-web-app-capable" content="yes"/>';
    FW_pO '<link rel="apple-touch-icon" href="'.$icon.'"/>';
    FW_pO '<link rel="shortcut-icon"    href="'.$icon.'"/>';
  }

  # meta refresh in rooms only
  if ($FW_room) {
    my $rf = AttrVal($FW_wname, "refresh", "");
    FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  }

  FW_pO "<link href=\"$FW_ME/pgm2/style.css\" rel=\"stylesheet\"/>";

  ########################
  # FW Extensions
  my $jsTemplate = '<script type="text/javascript" src="%s"></script>';
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{SCRIPT});
      my $script = $h->{SCRIPT};
      $script = ($script =~ m,^/,) ? "$FW_ME$script" : "$FW_ME/pgm2/$script";
      FW_pO sprintf($jsTemplate, $script);
    }
  }

  FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/svg.js") if($FW_plotmode eq "SVG");
  if($FW_plotmode eq"jsSVG") {
    FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/jsSVG.js");
    FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/jquery.min.js");
  }
  foreach my $js (@FW_fhemwebjs) {
    FW_pO sprintf($jsTemplate, "$FW_ME/pgm2/$js");
  }

  my $onload = AttrVal($FW_wname, "longpoll", 1) ?
                      "onload=\"FW_delayedStart()\"" : "";
  FW_pO "</head>\n<body name=\"$t\" $onload>";

  if($FW_activateInform) {
    $FW_cmdret = $FW_activateInform = "";
    $cmd = "style eventMonitor";
  }

  if($FW_cmdret) {
    $FW_detail = "";
    $FW_room = "";
    $FW_cmdret = FW_htmlEscape($FW_cmdret);
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
  if($FW_contentFunc) {
    no strict "refs";
    my $ret = &{$FW_contentFunc}($arg);
    use strict "refs";
    return $ret if($ret);
  }

     if($cmd =~ m/^style /)    { FW_style($cmd,undef);    }
  elsif($FW_detail)            { FW_doDetail($FW_detail); }
  elsif($FW_room)              { FW_showRoom();           }
  elsif(!$FW_cmdret &&
        !$FW_contentFunc) {

    $FW_room = AttrVal($FW_wname, "defaultRoom", '');
    if($FW_room ne '') {
      FW_showRoom(); 

    } else {
      my $motd = AttrVal("global","motd","none");
      if($motd ne "none") {
        $motd =~ s/\n/<br>/g;
        FW_pO "<div id=\"content\">$motd</div>";
      }
    }
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
    next if($pv eq ""); # happens when post forgot to set FW_ME
    $pv =~ s/\+/ /g;
    $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
    my ($p,$v) = split("=",$pv, 2);

    # Multiline: escape the NL for fhem
    $v =~ s/[\r]//g if($v && $p && $p ne "data");
    $FW_webArgs{$p} = $v;

    if($p eq "detail")       { $FW_detail = $v; }
    if($p eq "room")         { $FW_room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = ($val{$1} ? $val{$1}.",$v" : $v) }
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
# create FW_rooms && FW_types
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
    $t = AttrVal($d, "model", $t) if($t && $t eq "unknown"); # RKO: ???
    $FW_types{$d} = $t;
  }

  $FW_room = AttrVal($FW_detail, "room", "Unsorted") if($FW_detail);
}

##############################
sub
FW_makeTable($$$@)
{
  my($title, $name, $hash, $cmd) = (@_);

  return if(!$hash || !int(keys %{$hash}));
  my $class = lc($title);
  $class =~ s/[^A-Za-z]/_/g;
  FW_pO "<div class='makeTable wide'>";
  FW_pO $title;
  FW_pO "<table class=\"block wide $class\">";
  my $si = AttrVal("global", "showInternalValues", 0);

  my $row = 1;
  foreach my $n (sort keys %{$hash}) {
    next if(!$si && $n =~ m/^\./);      # Skip "hidden" Values
    my $val = $hash->{$n};
    $val = "" if(!defined($val));

    $val = $hash->{$n}{NAME}    # Exception
        if($n eq "IODev" && ref($val) eq "HASH" && defined($hash->{$n}{NAME}));

    my $r = ref($val);
    next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));

    FW_pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
    $row++;

    if($n eq "DEF" && !$FW_hiddenroom{input}) {
      FW_makeEdit($name, $n, $val);

    } else {
      if( $title eq "Attributes" ) {
        FW_pO "<td><div class=\"dname\">".
                "<a onClick='FW_querySetSelected(\"sel.attr$name\",\"$n\")'>".
              "$n</a></div></td>";
      } else {
         FW_pO "<td><div class=\"dname\">$n</div></td>";
      }

      if(ref($val)) { #handle readings
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        $v = FW_htmlEscape($v);
        if($FW_ss) {
          $t = ($t ? "<br><div class=\"tiny\">$t</div>" : "");
          FW_pO "<td><div class=\"dval\">$v$t</div></td>";
        } else {
          $t = "" if(!$t);
          FW_pO "<td><div informId=\"$name-$n\">$v</div></td>";
          FW_pO "<td><div informId=\"$name-$n-ts\">$t</div></td>";
        }
      } else {
        $val = FW_htmlEscape($val);

        # if possible provide som links
        if ($n eq "room"){
          FW_pO "<td><div class=\"dval\">".
                join(",", map { FW_pH("room=$_",$_,0,"",1,1) } split(",",$val)).
                "</div></td>";

        } elsif ($n eq "webCmd"){
          my $lc = "detail=$name&cmd.$name=set $name";
          FW_pO "<td><div name=\"$name-$n\" class=\"dval\">".
                  join(":", map {FW_pH("$lc $_",$_,0,"",1,1)} split(":",$val) ).
                "</div></td>";

        } elsif ($n =~ m/^fp_(.*)/ && $defs{$1}){ #special for Floorplan
          FW_pH "detail=$1", $val,1;

        } else {
           FW_pO "<td><div class=\"dval\">".
                   join(",", map { ($_ ne $name && $defs{$_}) ?
                     FW_pH( "detail=$_", $_ ,0,"",1,1) : $_ } split(",",$val)).
                 "</div></td>";
        }
      }

    }

    FW_pH "cmd.$name=$cmd $name $n&amp;detail=$name", $cmd, 1
        if($cmd && !$FW_ss);
    FW_pO "</tr>";
  }
  FW_pO "</table>";
  FW_pO "</div>";

}

##############################
# Used only for set or attr lists.
sub
FW_makeSelect($$$$)
{
  my ($d, $cmd, $list,$class) = @_;
  return if(!$list || $FW_hiddenroom{input});
  my @al = sort map { s/:.*//;$_ } split(" ", $list);

  my $selEl = (defined($al[0]) ? $al[0] : " ");
  $selEl = $1 if($list =~ m/([^ ]*):slider,/); # promote a slider if available
  $selEl = "room" if($list =~ m/room:/);

  FW_pO "<div class='makeSelect'>";
  FW_pO "<form method=\"$FW_formmethod\" ".
                "action=\"$FW_ME$FW_subdir\" autocomplete=\"off\">";
  FW_pO FW_hidden("detail", $d);
  FW_pO FW_hidden("dev.$cmd$d", $d);
  FW_pO FW_submit("cmd.$cmd$d", $cmd, $class);
  FW_pO "<div class=\"$class downText\">&nbsp;$d&nbsp;</div>";
  FW_pO FW_select("sel.$cmd$d","arg.$cmd$d",\@al, $selEl, $class,
        "FW_selChange(this.options[selectedIndex].text,'$list','val.$cmd$d')");
  FW_pO FW_textfield("val.$cmd$d", 30, $class);
  # Initial setting
  FW_pO "<script type=\"text/javascript\">" .
        "FW_selChange('$selEl','$list','val.$cmd$d')</script>";
  FW_pO "</form></div>";
}

##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  my $h = $defs{$d};
  my $t = $h->{TYPE};
  $t = "MISSING" if(!defined($t));
  FW_pO "<div id=\"content\">";

  if($FW_ss) { # FS20MS2 special: on and off, is not the same as toggle
    my $webCmd = AttrVal($d, "webCmd", undef);
    if($webCmd) {
      FW_pO "<table class=\"webcmd\">";
      foreach my $cmd (split(":", $webCmd)) {
        FW_pO "<tr>";
        FW_pH "cmd.$d=set $d $cmd&detail=$d", $cmd, 1, "col1";
        FW_pO "</tr>";
      }
      FW_pO "</table>";
    }
  }
  FW_pO "<table><tr><td>";

  if($modules{$t}{FW_detailFn}) {
    no strict "refs";
    my $txt = &{$modules{$t}{FW_detailFn}}($FW_wname, $d, $FW_room);
    FW_pO "$txt<br>" if(defined($txt));
    use strict "refs";
  }

  FW_pO "<form method=\"$FW_formmethod\" action=\"$FW_ME\">";
  FW_pO FW_hidden("detail", $d);

  FW_makeSelect($d, "set", getAllSets($d), "set");
  FW_makeSelect($d, "get", getAllGets($d), "get");

  FW_makeTable("Internals", $d, $h);
  FW_makeTable("Readings", $d, $h->{READINGS});

  my $attrList = getAllAttr($d);
  my $roomList = "multiple,".join(",", sort map { $_ =~ s/ /#/g ;$_} keys %FW_rooms);
  $attrList =~ s/room /room:$roomList /;
  FW_makeSelect($d, "attr", $attrList,"attr");

  FW_makeTable("Attributes", $d, $attr{$d}, "deleteattr");
  ## dependent objects
  my @dob;  # dependent objects - triggered by current device
  foreach my $dn (sort keys %defs) {
    next if(!$dn || $dn eq $d);
    my $dh = $defs{$dn};
    if(($dh->{DEF} && $dh->{DEF} =~ m/\b$d\b/) ||
       ($h->{DEF}  && $h->{DEF}  =~ m/\b$dn\b/)) {
      push(@dob, $dn);
    }
  }
  FW_pO "</form>";
  FW_makeTableFromArray("Probably associated with", "assoc", @dob,);

  FW_pO "</td></tr></table>";

  FW_pH "cmd=style iconFor $d", "Select icon";
  FW_pH "cmd=style showDSI $d", "Extend devStateIcon";
  FW_pH "$FW_ME/docs/commandref.html#${t}", "Device specific help";
  FW_pO "<br><br>";
  FW_pO "</div>";

}

##############################
sub
FW_makeTableFromArray($$@) {
  my ($txt,$class,@obj) = @_;
  if (@obj>0) {
    my $row=1;
    FW_pO "<div class='makeTable wide'>";
    FW_pO "$txt";
    FW_pO "<table class=\"block wide $class\">";
    foreach (sort @obj) {
      FW_pF "<tr class=\"%s\"><td>", ($row&1)?"odd":"even";
      $row++;
      FW_pH "detail=$_", $_;
      FW_pO "</td><td>$defs{$_}{TYPE}</td><td> </td>";
      FW_pO "</tr>";
    }
    FW_pO "</table></div>";
  }
}

sub
FW_roomIdx(\@$)
{
  my ($arr,$v) = @_; 
  my ($index) = grep { $v =~ /^$arr->[$_]$/ } 0..$#$arr;
 
  if( !defined($index) ) { 
    $index = 9999;
  } else {
    $index = sprintf( "%03i", $index );
  }
 
  return "$index-$v";
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
  my $hasMenuScroll;
  if($FW_detail && $FW_ss) {
    $FW_room = AttrVal($FW_detail, "room", undef);
    $FW_room = $1 if($FW_room && $FW_room =~ m/^([^,]*),/);
    $FW_room = "" if(!$FW_room);
    FW_pO(FW_pHPlain("room=$FW_room",
        "<div id=\"back\">" . FW_makeImage("back") . "</div>"));
    FW_pO "<div id=\"menu\">$FW_detail details</div>";
    return;

  } else {
    $hasMenuScroll = 1;
    FW_pO '<div id="menuScrollArea">';
    FW_pH "", '<div id="logo"></div>';

  }


  ##############
  # MENU
  my (@list1, @list2);
  push(@list1, ""); push(@list2, "");
  if(!$FW_hiddenroom{save} && !$FW_hiddenroom{"Save config"}) {
    push(@list1, "Save config");
    push(@list2, "$FW_ME?cmd=save");
    push(@list1, ""); push(@list2, "");
  }

  ########################
  # Show FW Extensions in the menu
  if(defined($data{FWEXT})) {
    my $cnt = 0;
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{LINK} || !$h->{NAME});
      next if($FW_hiddenroom{$h->{NAME}});
      push(@list1, $h->{NAME});
      push(@list2, $FW_ME ."/".$h->{LINK});
      $cnt++;
    }
    if($cnt > 0) {
      push(@list1, ""); push(@list2, "");
    }
  }
  $FW_room = "" if(!$FW_room);

  my @sortBy = split( " ", AttrVal( $FW_wname, "sortRooms", "" ) );
  @sortBy = sort keys %FW_rooms if( scalar @sortBy == 0 );

  ##########################
  # Rooms and other links
  foreach my $r ( sort { FW_roomIdx(@sortBy,$a) cmp
                         FW_roomIdx(@sortBy,$b) } keys %FW_rooms ) {
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
     "Commandref",    "$FW_ME/docs/commandref.html",
     "Remote doc",    "http://fhem.de/fhem.html#Documentation",
     "Edit files",    "$FW_ME?cmd=style%20list",
     "Select style",  "$FW_ME?cmd=style%20select",
     "Event monitor", "$FW_ME?cmd=style%20eventMonitor",
     "",           "");
  my $lastname = ","; # Avoid double "".

  my $lfn = "Logfile";
  if($defs{$lfn}) { # Add the current Logfile to the list if defined
    my @l = FW_fileList($defs{$lfn}{logfile});
    my $fn = pop @l;
    splice @list, 4,0, ("Logfile",
                      "$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn");
  }

  my @me = split(",", AttrVal($FW_wname, "menuEntries", ""));
  push @list, @me, "", "" if(@me);

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
      FW_pO "<option value='$list2[$idx]'$sel>$list1[$idx]</option>";
    }
    FW_pO "</select></td>";
    FW_pO "</tr>";

  } else {

    my $tblnr = 1;
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      my ($l1, $l2) = ($list1[$idx], $list2[$idx]);
      if(!$l1) {
        FW_pO "</table></td></tr>" if($idx);
        if($idx<int(@list1)-1) {
          FW_pO "<tr><td><table class=\"room roomBlock$tblnr\">";
          $tblnr++;
        }

      } else {
        FW_pF "<tr%s>", $l1 eq $FW_room ? " class=\"sel\"" : "";

        # image tag if we have an icon, else empty
        my $icoName = "ico$l1";
        map { my ($n,$v) = split(":",$_); $icoName=$v if($l1 =~ m/$n/); }
                        split(" ", AttrVal($FW_wname, "roomIcons", ""));
        my $icon = FW_iconName($icoName) ?
                        FW_makeImage($icoName,$icoName,"icon")."&nbsp;" : "";

        # Force external browser if FHEMWEB is installed as an offline app.
        if($l2 =~ m/.html$/ || $l2 =~ m/^http/) {
           FW_pO "<td><div><a href=\"$l2\">$icon$l1</a></div></td>";
        } else {
          FW_pH $l2, "$icon$l1", 1;
        }
        FW_pO "</tr>";
      }
    }

  }
  FW_pO "</table>";
  FW_pO "</div>";
  FW_pO "</div>" if($hasMenuScroll);

  ##############
  # HEADER
  FW_pO "<div id=\"hdr\">";
  FW_pO '<table border="0" class="header"><tr><td style="padding:0">';
  FW_pO "<form method=\"$FW_formmethod\" action=\"$FW_ME\">";
  FW_pO FW_hidden("room", "$FW_room") if($FW_room);
  FW_pO FW_textfield("cmd", $FW_ss ? 25 : 40, "maininput");
  FW_pO "</form>";
  FW_pO "</td></tr></table>";
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

  FW_pO "<form method=\"$FW_formmethod\" ".
                "action=\"$FW_ME\" autocomplete=\"off\">";
  FW_pO "<div id=\"content\" room=\"$FW_room\">";
  FW_pO "<table class=\"roomoverview\">";  # Need for equal width of subtables

  my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

  # array of all device names in the room (exception weblinks without group
  # attribute)
  my @devs= grep { ($FW_rooms{$FW_room}{$_}||$FW_room eq "all") &&
                      !IsIgnored($_) } keys %defs;
  my (%group, @atEnds, %usuallyAtEnd);
  foreach my $dev (@devs) {
    if($modules{$defs{$dev}{TYPE}}{FW_atPageEnd}) {
      $usuallyAtEnd{$dev} = 1;
      if(!AttrVal($dev, "group", undef)) {
        push @atEnds, $dev;
        next;
      }
    }
    foreach my $grp (split(",", AttrVal($dev, "group", $FW_types{$dev}))) {
      next if($FW_hiddengroup{$grp}); 
      $group{$grp}{$dev} = 1;
    }
  }

  # row counter
  my $row=1;
  my %extPage = ();

  my ($columns, $maxc) = FW_parseColumns();
  FW_pO "<tr class=\"column\">" if($maxc != -1);
  for(my $col=1; $col < ($maxc==-1 ? 2 : $maxc); $col++) {
    FW_pO "<td><table class=\"column tblcol_$col\">" if($maxc != -1);

    # iterate over the distinct groups  
    foreach my $g (sort keys %group) {

      next if($maxc != -1 && (!$columns->{$g} || $columns->{$g} != $col));

      #################
      # Check if there is a device of this type in the room
      FW_pO "\n<tr><td><div class=\"devType\">$g</div></td></tr>";
      FW_pO "<tr><td>";
      FW_pO "<table class=\"block wide\" id=\"TYPE_$g\">";

      foreach my $d (sort { lc(AttrVal($a,"sortby",AttrVal($a,"alias",$a))) cmp
                            lc(AttrVal($b,"sortby",AttrVal($b,"alias",$b))) }
                     keys %{$group{$g}}) {
        my $type = $defs{$d}{TYPE};

        FW_pF "\n<tr class=\"%s\">", ($row&1)?"odd":"even";
        my $devName = AttrVal($d, "alias", $d);
        my $icon = AttrVal($d, "icon", "");
        $icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);

        if($FW_hiddenroom{detail}) {
          FW_pO "<td><div class=\"col1\">$icon$devName</div></td>";
        } else {
          FW_pH "detail=$d", "$icon$devName", 1, "col1" if(!$usuallyAtEnd{$d});
        }
        $row++;

        my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf, \%extPage);

        my $colSpan = ($usuallyAtEnd{$d} ? ' colspan="2"' : '');
        FW_pO "<td informId=\"$d\"$colSpan>$txt</td>";

        ######
        # Commands, slider, dropdown
        if(!$FW_ss && $cmdlist) {
          foreach my $cmd (split(":", $cmdlist)) {
            my $htmlTxt;
            my @c = split(' ', $cmd);   # @c==0 if $cmd==" ";
            if(int(@c) && $allSets && $allSets =~ m/$c[0]:([^ ]*)/) {
              my $values = $1;
              foreach my $fn (sort keys %{$data{webCmdFn}}) {
                no strict "refs";
                $htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname,
                                                   $d, $FW_room, $cmd, $values);
                use strict "refs";
                last if(defined($htmlTxt));
              }
            }
            if($htmlTxt) {
              FW_pO $htmlTxt;

            } else {
              FW_pH "cmd.$d=set $d $cmd$rf", $cmd, 1, "col3";
            }
          }
        }
        FW_pO "</tr>";
      }
      FW_pO "</table>";
      FW_pO "</td></tr>";
    }
    FW_pO "</table></td>" if($maxc != -1); # Column
  }
  FW_pO "</tr>";

  FW_pO "</table><br>";

  # Now the "atEnds"
  foreach my $d (sort { lc(AttrVal($a, "sortby", AttrVal($a,"alias",$a))) cmp
                        lc(AttrVal($b, "sortby", AttrVal($b,"alias",$b))) }
                   @atEnds) {
    no strict "refs";
    FW_pO &{$modules{$defs{$d}{TYPE}}{FW_summaryFn}}($FW_wname, $d, 
                                                        $FW_room, \%extPage);
    use strict "refs";
  }
  FW_pO "</div>";
  FW_pO "</form>";
}

sub
FW_parseColumns()
{
  my %columns;
  my $colNo = -1;

  foreach my $roomgroup (split("[ \t\r\n]+", AttrVal($FW_wname,"column",""))) {
    my ($room, $groupcolumn)=split(":",$roomgroup);
    last if(!defined($room) || !defined($groupcolumn));
    next if($room ne $FW_room);
    $colNo = 1;
    foreach my $groups (split(/\|/,$groupcolumn)) {
      foreach my $group (split(",",$groups)) {
        $columns{$group} = $colNo;
      }
      $colNo++;
    }
  }
  return (\%columns, $colNo);
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
  $dir =~ s/%L/$attr{global}{logdir}/g if($dir =~ m/%/ && $attr{global}{logdir}); # %L present and log directory defined
  $re =~ s/%./[A-Za-z0-9]*/g;    # logfile magic (%Y, etc)
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
    Log3 $FW_wname, 2, "FHEMWEB $FW_wname $path: $!";
    FW_pO "<div id=\"content\">$path: $!</div>";
    return 0;
  }
  binmode(FH) if($type !~ m/text/); # necessary for Windows

  $etag = defined($etag) ? "ETag: \"$etag\"\r\n" : "";
  my $expires = $cacheable ? ("Expires: ".gmtime(time()+900)." GMT\r\n"): "";
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
FW_select($$$$$@)
{
  my ($id, $n, $va, $def, $class, $jSelFn) = @_;
  $jSelFn = ($jSelFn ? "onchange=\"$jSelFn\"" : "");
  $id = ($id ? "id=\"$id\" informId=\"$id\"" : "");
  my $s = "<select $jSelFn $id name=\"$n\" class=\"$class\">";
  foreach my $v (@{$va}) {
    if($def && $v eq $def) {
      $s .= "<option selected=\"selected\" value='$v'>$v</option>\n";
    } else {
      $s .= "<option value='$v'>$v</option>\n";
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
sub
FW_displayFileList($@)
{
  my ($heading,@files)= @_;
  my $hid = lc($heading);
  $hid =~ s/[^A-Za-z]/_/g;
  FW_pO "<div class=\"fileList $hid\">$heading</div>";
  FW_pO "<table class=\"block fileList\">";
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

  my $ac = AttrVal($FW_wname,"allowedCommands","");
  return if($ac && $ac !~ m/\b$a[0]\b/);

  my $start = "<div id=\"content\"><table><tr><td>";
  my $end   = "</td></tr></table></div>";
  
  if($a[1] eq "list") {
    FW_pO $start;
    FW_pO "$msg<br><br>" if($msg);

    $attr{global}{configfile} =~ m,([^/]*)$,;
    my $cfgFileName = $1;
    FW_displayFileList("config file", $cfgFileName)
                                if($attr{global}{configfile} ne 'configDB');
    FW_displayFileList("Own modules and helper files",
        FW_fileList("$MW_dir/^(.*sh|[0-9][0-9].*Util.*pm|.*cfg|.*holiday".
                                  "|.*layout)\$"));
    FW_displayFileList("styles",
        FW_fileList("$FW_cssdir/^.*(css|svg)\$"));
    FW_displayFileList("gplot files",
        FW_fileList("$FW_gplotdir/^.*gplot\$"));
    FW_pO $end;

  } elsif($a[1] eq "select") {
    my @fl = grep { $_ !~ m/(floorplan|dashboard)/ } FW_fileList("$FW_cssdir/.*style.css");
    FW_pO "$start<table class=\"block fileList\">";
    my $row = 0;
    foreach my $file (@fl) {
      next if($file =~ m/svg_/);
      $file =~ s/style.css//;
      $file = "default" if($file eq "");
      FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      FW_pH "cmd=style set $file", "$file", 1;
      FW_pO "</tr>";
      $row = ($row+1)%2;
    }
    FW_pO "</table>$end";

  } elsif($a[1] eq "set") {
    if($a[2] eq "default") {
      CommandDeleteAttr(undef, "$FW_wname stylesheetPrefix");
    } else {
      CommandAttr(undef, "$FW_wname stylesheetPrefix $a[2]");
    }
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

    $data =~ s/&/&amp;/g;
	
    my $ncols = $FW_ss ? 40 : 80;
    FW_pO "<div id=\"content\">";
    FW_pO "<form method=\"$FW_formmethod\">";
    FW_pO     FW_submit("save", "Save $fileName");
    FW_pO     "&nbsp;&nbsp;";
    FW_pO     FW_submit("saveAs", "Save as");
    FW_pO     FW_textfieldv("saveName", 30, "saveName", $fileName);
    FW_pO     "<br><br>";
    FW_pO     FW_hidden("cmd", "style save $fileName");
    FW_pO     "<textarea name=\"data\" cols=\"$ncols\" rows=\"30\">" .
                "$data</textarea>";
    FW_pO "</form>";
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
    FW_iconTable("iconFor", "icon", "style setIF $a[2] %s", undef);

  } elsif($a[1] eq "setIF") {
    FW_fC("attr $a[2] icon $a[3]");
    FW_doDetail($a[2]);

  } elsif($a[1] eq "showDSI") {
    FW_iconTable("devStateIcon", "",
                 "style addDSI $a[2] %s", "Enter value/regexp for STATE");

  } elsif($a[1] eq "addDSI") {
    my $dsi = AttrVal($a[2], "devStateIcon", "");
    $dsi .= " " if($dsi);
    FW_fC("attr $a[2] devStateIcon $dsi$FW_data:$a[3]");
    FW_doDetail($a[2]);

  } elsif($a[1] eq "eventMonitor") {
    FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/console.js\">".
          "</script>";
    FW_pO "<div id=\"content\">";
    FW_pO "<div id=\"console\">";
    FW_pO "Events:<br>\n";
    FW_pO "</div>";
    FW_pO "</div>";

  }

}

sub
FW_iconTable($$$$)
{
  my ($name, $class, $cmdFmt, $textfield) = @_;

  my %icoList = ();
  foreach my $style (@FW_iconDirs) {
    foreach my $imgName (sort keys %{$FW_icons{$style}}) {
      $imgName =~ s/\.[^.]*$//; # Cut extension
      next if(!$FW_icons{$style}{$imgName}); # Dont cut it twice: FS20.on.png
      next if($FW_icons{$style}{$imgName} !~ m/$imgName/); # Skip alias
      next if($imgName=~m+^(weather/|shutter.*big|fhemicon|favicon|ws_.*_kl)+);
      next if($imgName=~m+^(dashboardicons)+);
      $icoList{$imgName} = 1;
    }
  }

  FW_pO "<div id=\"content\">";
  FW_pO "<form method=\"$FW_formmethod\">";
  if($textfield) {
    FW_pO "$textfield:&nbsp;".FW_textfieldv("data",20,"iconTable",".*")."<br>";
  }
  foreach my $i (sort keys %icoList) {
    FW_pF "<button title='%s' type='submit' class='dist' name='cmd' ".
              "value='$cmdFmt'>%s</button>", $i, $i, FW_makeImage($i,$i,$class);
  }
  FW_pO "</form>";
  FW_pO "</div>";
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
  my ($link, $txt, $td, $class, $doRet,$nonl) = @_;
  my $ret;

  $link = ($link =~ m,^/,) ? $link : "$FW_ME$FW_subdir?$link";
  
  # Using onclick, as href starts safari in a webapp.
  # Known issue: the pointer won't change
  if($FW_ss || $FW_tp) { 
    $ret = "<a onClick=\"location.href='$link'\">$txt</a>";
  } else {
    $ret = "<a href=\"$link\">$txt</a>";
  }

  #actually 'div' should be removed if no class is defined
  #  as I can't check all code for consistancy I add nonl instead
  $class = ($class)?" class=\"$class\"":"";
  $ret = "<div$class>$ret</div>" if (!$nonl);

  $ret = "<td>$ret</td>" if($td);
  return $ret if($doRet);
  FW_pO $ret;
}

#################
# href without class/div, returned as a string
sub
FW_pHPlain(@)
{
  my ($link, $txt, $td) = @_;

  $link = "?$link" if($link !~ m+^/+);
  my $ret = "";
  $ret .= "<td>" if($td);
  if($FW_ss || $FW_tp) {
    $ret .= "<a onClick=\"location.href='$FW_ME$FW_subdir$link'\">$txt</a>";
  } else {
    $ret .= "<a href=\"$FW_ME$FW_subdir$link\">$txt</a>";
  }
  $ret .= "</td>" if($td);
  return $ret;
}


##############################
sub
FW_makeImage(@)
{
  my ($name, $txt, $class)= @_;

  $txt = $name if(!defined($txt));
  $class = "" if(!$class);
  $class = "$class $name";
  $class =~ s/\./_/g;
  $class =~ s/@/ /g;

  my $p = FW_iconPath($name);
  return $name if(!$p);
  if($p =~ m/\.svg$/i) {
    if(open(FH, "$FW_icondir/$p")) {
      <FH>; <FH>; <FH>; # Skip the first 3 lines;
      my $data = join("", <FH>);
      close(FH);
      $data =~ s/[\r\n]/ /g;
      $data =~ s/ *$//g;
      $data =~ s/<svg/<svg class="$class"/;
      $name =~ m/(@.*)$/;
      my $col = $1 if($1);
      if($col) {
        $col =~ s/@//;
        $col = "#$col" if($col =~ m/^([A-F0-9]{6})$/);
        $data =~ s/fill="#000000"/fill="$col"/g;
        $data =~ s/fill:#000000/fill:$col/g;
      } else {
        $data =~ s/fill="#000000"//g;
        $data =~ s/fill:#000000//g;
      }
      return $data;
    } else {
      return $name;
    }
  } else {
    $class = "class='$class'" if($class);
    return "<img $class src=\"$FW_ME/images/$p\" alt=\"$txt\" title=\"$txt\">";
  }
}

####
sub
FW_IconURL($) 
{
  my ($name)= @_;
  return "$FW_ME/icons/$name";
}

##################
# print formatted
sub
FW_pF($@)
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
    $ret = AnalyzeCommand($FW_chash, $cmd,
                AttrVal($FW_wname,"allowedCommands",undef));
  } else {
    $ret = AnalyzeCommandChain($FW_chash, $cmd,
                AttrVal($FW_wname,"allowedCommands",undef));
  }
  return $ret;
}

sub
FW_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $name = $hash->{NAME};
  my $sP = "stylesheetPrefix";
  my $retMsg;

  if($a[0] eq "set" && $a[2] eq "HTTPS") {
    TcpServer_SetSSL($hash);
  }

  if($a[0] eq "set") { # Converting styles
   if($a[2] eq "smallscreen" || $a[2] eq "touchpad") {
     $attr{$name}{$sP} = $a[2];
     $retMsg="$name: attribute $a[2] deprecated, converted to $sP";
     $a[3] = $a[2]; $a[2] = $sP;
   }
  }
  if($a[2] eq $sP) {
    # AttrFn is called too early, we have to set/del the attr here
    if($a[0] eq "set") {
      $attr{$name}{$sP} = (defined($a[3]) ? $a[3] : "default");
      FW_readIcons($attr{$name}{$sP});
    } else {
      delete $attr{$name}{$sP};
    }
  }

  if($a[2] eq "iconPath" && $a[0] eq "set") {
    foreach my $pe (split(":", $a[3])) {
      $pe =~ s+\.\.++g;
      FW_readIcons($pe);
    }
  }

  return $retMsg;
}


# recursion starts at $FW_icondir/$dir
# filenames are relative to $FW_icondir
sub
FW_readIconsFrom($$)
{
  my ($dir,$subdir)= @_;

  my $ldir = ($subdir ? "$dir/$subdir" : $dir);
  my @entries;
  if(opendir(DH, "$FW_icondir/$ldir")) {
    @entries= sort readdir(DH); # assures order: .gif  .ico  .jpg  .png .svg
    closedir(DH);
  }

  foreach my $entry (@entries) {
    if( -d "$FW_icondir/$ldir/$entry" ) {  # directory -> recurse
      FW_readIconsFrom($dir, $subdir ? "$subdir/$entry" : $entry)
        unless($entry eq "." || $entry eq ".." || $entry eq ".svn");

    } else {
      if($entry =~ m/^iconalias.txt$/i && open(FH, "$FW_icondir/$ldir/$entry")){
        while(my $l = <FH>) {
          chomp($l);
          my @a = split(" ", $l);
          next if($l =~ m/^#/ || @a < 2);
          $FW_icons{$dir}{$a[0]} = $a[1];
        }
        close(FH);
      } elsif($entry =~ m/(gif|ico|jpg|png|jpeg|svg)$/i) {
        my $filename = $subdir ? "$subdir/$entry" : $entry;
        $FW_icons{$dir}{$filename} = $filename;

        my $tag = $filename;     # Add it without extension too
        $tag =~ s/\.[^.]*$//;
        $FW_icons{$dir}{$tag} = $filename;
      }
    }
  }
  $FW_icons{$dir}{""} = 1; # Do not check empty directories again.
}

sub
FW_readIcons($)
{
  my ($dir)= @_;
  return if($FW_icons{$dir});
  FW_readIconsFrom($dir, "");
}


# check if the icon exists, and if yes, returns its "logical" name;
sub
FW_iconName($)
{
  my ($name)= @_;
  $name =~ s/@.*//;
  foreach my $pe (@FW_iconDirs) {
    return $name if($pe && $FW_icons{$pe} && $FW_icons{$pe}{$name});
  }
  return undef;
}

# returns the physical absolute path relative for the logical path
# examples:
#   FS20.on       -> dark/FS20.on.png
#   weather/sunny -> default/weather/sunny.gif
sub
FW_iconPath($)
{
  my ($name) = @_;
  $name =~ s/@.*//;
  foreach my $pe (@FW_iconDirs) {
    return "$pe/$FW_icons{$pe}{$name}"
        if($pe && $FW_icons{$pe} && $FW_icons{$pe}{$name});
  }
  return undef;
}

sub
FW_dev2image($;$)
{
  my ($name, $state) = @_;
  my $d = $defs{$name};
  return "" if(!$name || !$d);

  my $type = $d->{TYPE};
  $state = $d->{STATE} if(!defined($state));
  return "" if(!$type || !defined($state));

  my $model = $attr{$name}{model} if(defined($attr{$name}{model}));

  my (undef, $rstate) = ReplaceEventMap($name, [undef, $state], 0);

  my ($icon, $rlink);
  my $devStateIcon = AttrVal($name, "devStateIcon", undef);
  if(defined($devStateIcon) && $devStateIcon =~ m/^{.*}$/) {
    my ($html, $link) = eval $devStateIcon;
    Log3 $FW_wname, 1, "devStateIcon $name: $@" if($@);
    return ($html, $link, 1) if(defined($html) && $html =~ m/^<.*>$/s);
    $devStateIcon = $html;
  }

  if(defined($devStateIcon)) {
    my @list = split(" ", $devStateIcon);
    foreach my $l (@list) {
      my ($re, $iconName, $link) = split(":", $l, 3);
      if(defined($re) && $state =~ m/^$re$/) {
        if($iconName eq "") {
          $rlink = $link;
          last;
        }
        if(defined(FW_iconName($iconName)))  {
          return ($iconName, $link, 0);
        } else {
          return ($state, $link, 1);
        }
      }
    }
  }

  $state =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"

  $icon = FW_iconName("$name.$state")   if(!$icon);           # lamp.Aus.png
  $icon = FW_iconName("$name.$rstate")  if(!$icon);           # lamp.on.png
  $icon = FW_iconName($name)            if(!$icon);           # lamp.png
  $icon = FW_iconName("$model.$state")  if(!$icon && $model); # fs20st.off.png
  $icon = FW_iconName($model)           if(!$icon && $model); # fs20st.png
  $icon = FW_iconName("$type.$state")   if(!$icon);           # FS20.Aus.png
  $icon = FW_iconName("$type.$rstate")  if(!$icon);           # FS20.on.png
  $icon = FW_iconName($type)            if(!$icon);           # FS20.png
  $icon = FW_iconName($state)           if(!$icon);           # Aus.png
  $icon = FW_iconName($rstate)          if(!$icon);           # on.png
  return ($icon, $rlink, 0);
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
  FW_pO   "<div id=\"edit\" style=\"display:none\">";
  FW_pO   "<form method=\"$FW_formmethod\">";
  FW_pO       FW_hidden("detail", $name);
  my $cmd = "modify";
  my $ncols = $FW_ss ? 30 : 60;
  FW_pO      "<textarea name=\"val.${cmd}$name\" ".
                "cols=\"$ncols\" rows=\"10\">$val</textarea>";
  FW_pO     "<br>" . FW_submit("cmd.${cmd}$name", "$cmd $name");
  FW_pO   "</form></div>";
  FW_pO  "</td>";
}


sub
FW_roomStatesForInform($)
{
  my ($me) = @_;
  return "" if($me->{inform}{type} !~ m/status/);

  my %extPage = ();
  my @data;
  foreach my $dn (keys %{$me->{inform}{devices}}) {
    next if(!defined($defs{$dn}));
    my $t = $defs{$dn}{TYPE};
    next if(!$t || $modules{$t}{FW_atPageEnd});
    my ($allSet, $cmdlist, $txt) = FW_devState($dn, "", \%extPage);
    if($defs{$dn} && $defs{$dn}{STATE} && $defs{$dn}{TYPE} ne "weblink") {
      push @data, "$dn<<$defs{$dn}{STATE}<<$txt";
    }
  }
  my $data = join("\n", map { s/\n/ /gm; $_ } @data)."\n";
  return $data;
}

sub
FW_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $h = $ntfy->{inform};
  return undef if(!$h);

  my $dn = $dev->{NAME};
  return undef if(!$h->{devices}{$dn});

  my @data;
  my %extPage;

  if($h->{type} =~ m/status/) {
    # Why is saving this stuff needed? FLOORPLAN?
    my @old = ($FW_wname, $FW_ME, $FW_ss, $FW_tp, $FW_subdir);
    $FW_wname = $ntfy->{SNAME};
    $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
    $FW_subdir = "";
    $FW_sp = AttrVal($FW_wname, "stylesheetPrefix", 0);
    $FW_ss = ($FW_sp =~ m/smallscreen/);
    $FW_tp = ($FW_sp =~ m/smallscreen|touchpad/);
    @FW_iconDirs = grep { $_ } split(":", AttrVal($FW_wname, "iconPath",
                                "$FW_sp:default:fhemSVG:openautomation"));
    if($h->{iconPath}) {
      unshift @FW_iconDirs, $h->{iconPath};
      FW_readIcons($h->{iconPath});
    }

    my ($allSet, $cmdlist, $txt) = FW_devState($dn, "", \%extPage);
    ($FW_wname, $FW_ME, $FW_ss, $FW_tp, $FW_subdir) = @old;
    push @data, "$dn<<$dev->{STATE}<<$txt";

    #Add READINGS
    if($dev->{CHANGED}) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      my $max = int(@{$dev->{CHANGED}});
      for(my $i = 0; $i < $max; $i++) {
        if( $dev->{CHANGED}[$i] !~ /: /) {
          next; #ignore 'set' commands
        }
        my ($readingName,$readingVal) = split(": ",$dev->{CHANGED}[$i],2);
        push @data, "$dn-$readingName<<$readingVal<<$readingVal";
        push @data, "$dn-$readingName-ts<<$tn<<$tn";
      }
    }
  }

  if($h->{type} =~ m/raw/) {
    if($dev->{CHANGED}) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      if($attr{global}{mseclog}) {
        my ($seconds, $microseconds) = gettimeofday();
        $tn .= sprintf(".%03d", $microseconds/1000);
      }
      my $max = int(@{$dev->{CHANGED}});
      my $dt = $dev->{TYPE};
      for(my $i = 0; $i < $max; $i++) {
        push @data,("$tn $dt $dn ".$dev->{CHANGED}[$i]."<br>");
      }
    }
  }

  addToWritebuffer($ntfy, join("\n", map { s/\n/ /gm; $_ } @data)."\n")
    if(@data);
  return undef;
}

###################
# Compute the state (==second) column
sub
FW_devState($$@)
{
  my ($d, $rf, $extPage) = @_;

  my ($hasOnOff, $link);

  my $cmdList = AttrVal($d, "webCmd", "");
  my $allSets = getAllSets($d);
  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));

  $hasOnOff = ($allSets =~ m/(^| )on(:[^ ]*)?( |$)/ &&
               $allSets =~ m/(^| )off(:[^ ]*)?( |$)/);
  my $txt = $state;
  my $dsi = AttrVal($d, "devStateIcon", undef);

  if(defined(AttrVal($d, "showtime", undef))) {
    my $v = $defs{$d}{READINGS}{state}{TIME};
    $txt = $v if(defined($v));

  } elsif(!$dsi && $allSets =~ m/\bdesired-temp:/) {
    $txt = "$1 &deg;C" if($txt =~ m/^measured-temp: (.*)/);      # FHT fix
    $cmdList = "desired-temp" if(!$cmdList);

  } elsif(!$dsi && $allSets =~ m/\bdesiredTemperature:/) {
    $txt = ReadingsVal($d, "temperature", "");  # ignores stateFormat!!!
    $txt =~ s/ .*//;
    $txt .= "&deg;C";
    $cmdList = "desiredTemperature" if(!$cmdList);

  } else {
    my ($icon, $isHtml);
    ($icon, $link, $isHtml) = FW_dev2image($d);
    $txt = ($isHtml ? $icon : FW_makeImage($icon, $state)) if($icon);
    $link = "cmd.$d=set $d $link" if($link);

  }


  if($hasOnOff) {
    # Have to cover: "on:An off:Aus", "A0:Aus AI:An Aus:off An:on"
    my $on  = ReplaceEventMap($d, "on", 1);
    my $off = ReplaceEventMap($d, "off", 1);
    $link = "cmd.$d=set $d " . ($state eq $on ? $off : $on) if(!$link);
    $cmdList = "$on:$off" if(!$cmdList);

  }

  if($link) { # Have command to execute
    my $room = AttrVal($d, "room", undef);
    if($room) {
      if($FW_room && $room =~ m/\b$FW_room\b/) {
        $room = $FW_room;
      } else {
        $room =~ s/,.*//;
      }
      $link .= "&room=$room";
    }
    if(AttrVal($FW_wname, "longpoll", 1)) {
      $txt = "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";

    } elsif($FW_ss || $FW_tp) {
      $txt ="<a onClick=\"location.href='$FW_ME$FW_subdir?$link$rf'\">$txt</a>";

    } else {
      $txt = "<a href=\"$FW_ME$FW_subdir?$link$rf\">$txt</a>";

    }
  }

  my $style = AttrVal($d, "devStateStyle", "");
  $txt = "<div id=\"$d\" $style class=\"col2\">$txt</div>";

  my $type = $defs{$d}{TYPE};
  my $sfn = $modules{$type}{FW_summaryFn};
  if($sfn) {
    if(!defined($extPage)) {
       my %hash;
       $extPage = \%hash;
    }
    no strict "refs";
    my $newtxt = &{$sfn}($FW_wname, $d, $FW_room, $extPage);
    use strict "refs";
    $txt = $newtxt if(defined($newtxt)); # As specified
  }

  return ($allSets, $cmdList, $txt);
}


sub
FW_Get($@)
{
  my ($hash, @a) = @_;
  $FW_wname= $hash->{NAME};

  my $arg = (defined($a[1]) ? $a[1] : "");
  if($arg eq "icon") {
    return "need one icon as argument" if(int(@a) != 3);
    my $icon = FW_iconPath($a[2]);
    return defined($icon) ? "$FW_icondir/$icon" : "no such icon";

  } elsif($arg eq "pathlist") {
    return "web server root:      $FW_dir\n".
           "icon directory:       $FW_icondir\n".
           "css directory:        $FW_cssdir\n".
           "gplot directory:      $FW_gplotdir";

  } else {
    return "Unknown argument $arg choose one of icon pathlist:noArg";

  }
}


#####################################
sub
FW_Set($@)
{
  my ($hash, @a) = @_;
  my %cmd = ("rereadicons" => 1, "clearSvgCache" => 1);

  return "no set value specified" if(@a < 2);
  return ("Unknown argument $a[1], choose one of ".
        join(" ", map { "$_:noArg" } sort keys %cmd))
    if(!$cmd{$a[1]});

  if($a[1] eq "rereadicons") {
    my @dirs = keys %FW_icons;
    %FW_icons = ();
    foreach my $d  (@dirs) {
      FW_readIcons($d);
    }
  }
  if($a[1] eq "clearSvgCache") {
    my $cDir = "$FW_dir/SVGcache";
    if(opendir(DH, $cDir)) {
      map { my $n="$cDir/$_"; unlink($n) if(-f $n); } readdir(DH);;
      closedir(DH);
    } else {
      return "Can't open $cDir: $!";
    }
  }
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
    Log3 $FW_wname, 4, "Closing connection $dev";
    FW_Undef($defs{$dev}, "");
    delete $defs{$dev};
  }
  InternalTimer($now+60, "FW_closeOldClients", 0, 0);
}

sub
FW_htmlEscape($)
{
  my ($txt) = @_;
  $txt =~ s/</&lt;/g;
  $txt =~ s/>/&gt;/g;
  return $txt;
}

###########################
# Widgets START
sub
FW_sliderFn($$$$$)
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  return undef if($values !~ m/^slider,(.*),(.*),(.*)$/);
  return "" if($cmd =~ m/ /);   # webCmd pct 30 should generate a link
  my ($min,$stp, $max) = ($1, $2, $3);
  my $srf = $FW_room ? "&room=$FW_room" : "";
  my $cv = ReadingsVal($d, $cmd, Value($d));
  my $id = ($cmd eq "state") ? "" : "-$cmd";
  $cmd = "" if($cmd eq "state");
  $cv =~ s/.*?([.\-\d]+).*/$1/; # get first number
  $cv = 0 if($cv !~ m/\d/);
  return "<td colspan='2'>".
           "<div class='slider' id='slider.$d$id' min='$min' stp='$stp' ".
                 "max='$max' cmd='$FW_ME?cmd=set $d $cmd %$srf'>".
             "<div class='handle'>$min</div>".
           "</div>".
           "<script type=\"text/javascript\">".
             "FW_sliderCreate(document.getElementById('slider.$d$id'),'$cv');".
           "</script>".
         "</td>";
}

sub
FW_noArgFn($$$$$)
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  return undef if($values !~ m/^noArg$/);
  return "";
}

sub
FW_timepickerFn()
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  return undef if($values ne "time");
  return "" if($cmd =~ m/ /);   # webCmd on-for-timer 30 should generate a link
  my $srf = $FW_room ? "&room=$FW_room" : "";
  my $cv = ReadingsVal($d, $cmd, Value($d));
  $cmd = "" if($cmd eq "state");
  my $c = "\"$FW_ME?cmd=set $d $cmd %$srf\"";
  return "<td colspan='2'>".
            "<input name='time.$d' value='$cv' type='text' readonly size='5'>".
            "<input type='button' value='+' onclick='FW_timeCreate(this,$c)'>".
          "</td>";
}

sub 
FW_dropdownFn()
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  return "" if($cmd =~ m/ /);   # webCmd temp 30 should generate a link
  my @tv = split(",", $values);
  # Hack: eventmap (translation only) should not result in a
  # dropdown.  eventMap/webCmd/etc handling must be cleaned up.
  if(@tv > 1) {
    my $txt;
    if($cmd eq "desired-temp" || $cmd eq "desiredTemperature") {
      $txt = ReadingsVal($d, $cmd, 20);
      $txt =~ s/ .*//;        # Cut off Celsius
      $txt = sprintf("%2.1f", int(2*$txt)/2) if($txt =~ m/[0-9.-]/);
    } else {
      $txt = ReadingsVal($d, $cmd, Value($d));
      $txt =~ s/$cmd //;
    }

    my $fpname = $FW_wname;
    $fpname =~ s/.*floorplan\/(\w+)$/$1/;  #allow usage of attr fp_setbutton
    my $fwsel;
    $fwsel = ($cmd eq "state" ? "" : "$cmd&nbsp;") .
             FW_select("$d-$cmd","val.$d", \@tv, $txt,"dropdown","submit()").
             FW_hidden("cmd.$d", "set");

    return "<td colspan='2'><form method=\"$FW_formmethod\">".
      FW_hidden("arg.$d", $cmd) .
      FW_hidden("dev.$d", $d) .
      ($FW_room ? FW_hidden("room", $FW_room) : "") .
      "$fwsel</form></td>";
  }
  return undef;
}

sub
FW_textFieldFn($$$$)
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  my @args = split("[ \t]+", $cmd);

  return undef if($values !~ m/^textField$/);
  return "" if($cmd =~ m/ /);
  my $srf = $FW_room ? "&room=$FW_room" : "";
  my $cv = ReadingsVal($d, $cmd, "");
  my $id = ($cmd eq "state") ? "" : "-$cmd";

  my $c = "$FW_ME?XHR=1&cmd=setreading $d $cmd %$srf";
  return '<td align="center">'.
           "<div>$cmd:<input id='textField.$d$id' type='text' value='$cv' ".
                        "onChange='textField_setText(this,\"$c\")'></div>".
         '</td>';
}

# Widgets END
###########################

sub
FW_visibleDevices(;$)
{
  my($FW_wname) = @_; 
 
  my %devices = (); 
  foreach my $d (sort keys %defs) {
    next if(!defined($defs{$d}));
    my $h = $defs{$d};
    next if(!$h->{TEMPORARY});
    next if($h->{TYPE} ne "FHEMWEB");
    next if(defined($FW_wname) && $h->{SNAME} ne $FW_wname);
 
    next if(!defined($h->{inform}));
 
    @devices{ keys %{$h->{inform}->{devices}} } = 
                values %{$h->{inform}->{devices}};
  }
  return %devices;
}

sub 
FW_ActivateInform()
{
  $FW_activateInform = 1;
}

1;

=pod
=begin html

<a name="FHEMWEB"></a>
<h3>FHEMWEB</h3>
<ul>
  FHEMWEB is the builtin web-frontend, it also implements a simple web
  server (optionally with Basic-Auth and HTTPS).
  <br> <br>

  <a name="FHEMWEBdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMWEB &lt;tcp-portnr&gt; [global]</code>
    <br><br>
    Enable the webfrontend on port &lt;tcp-portnr&gt;. If global is specified,
    then requests from all interfaces (not only localhost / 127.0.0.1) are
    serviced.<br>
    To enable listening on IPV6 see the comments <a href="#telnet">here</a>.
    <br>
  </ul>
  <br>

  <a name="FHEMWEBset"></a>
  <b>Set</b>
  <ul>
    <li>rereadicons<br>
      reads the names of the icons from the icon path.  Use after adding or
      deleting icons.
      </li>
    <li>clearSvgCache<br>
      delete all files found in the www/SVGcache directory, which is used to
      cache SVG data, if the SVGcache attribute is set.
      </li>
  </ul>
  <br>

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
        </li>
    <li>pathlist<br>
        return FHEMWEB specific directories, where files for given types are
        located
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
          <li>SVG<br>
              The plots are created with the <a href="#SVG">SVG</a> module.
              This is the default.</li>

          <li>gnuplot<br>
              The plots are created with the gnuplot program. Note: this mode
              ist only available due to historic reasons.</li>

          <li>gnuplot-scroll<br>
              Like the gnuplot-mode, but scrolling to historical values is alos
              possible, just like with SVG.</li>
        </ul>
        </li><br>

    <a name="plotsize"></a>
    <li>plotsize<br>
        the default size of the plot, in pixels, separated by comma:
        width,height. You can set individual sizes by setting the plotsize of
        the SVG. Default is 800,160 for desktop, and 480,160 for
        smallscreen.
        </li><br>

    <a name="nrAxis"></a>
    <li>nrAxis<br>
        the number of axis for which space should be reserved  on the left and
        right sides of a plot and optionaly how many axes should realy be used
        on each side, separated by comma: left,right[,useLeft,useRight].  You
        can set individual numbers by setting the nrAxis of the SVG. Default is
        1,1.
        </li><br>

    <a name="SVGcache"></a>
    <li>SVGcache<br>
        if set, cache plots which won't change any more (the end-date is prior
        to the current timestamp). The files are written to the www/SVGcache
        directory. Default is off.<br>
        See also the clearSvgCache command for clearing the cache.
        </li><br>

    <a name="endPlotToday"></a>
    <li>endPlotToday<br>
        If this FHEMWEB attribute is set to 1, then week and month plots will
        end today. Else the current week (starting at Sunday) or the current
        month will be shown.<br>
        </li><br>

    <a name="endPlotNow"></a>
    <li>endPlotNow<br>
        If this FHEMWEB attribute is set to 1, then day and hour plots will
        end at current time. Else the whole day, the 6 hour period starting at
        0, 6, 12 or 18 hour or the whole hour will be shown. This attribute
        is not used if the SVG has the attribute startDate defined.<br>
        </li><br>

    <a name="ploteditor"></a>
    <li>ploteditor<br>
        Configures if the <a href="#plotEditor">Plot editor</a> should be shown
        in the SVG detail view.
        Can be set to always, onClick or never. Default is always.
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
      <br>
    </li>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        A comma separated list of commands allowed from this FHEMWEB
        instance.<br> If set to an empty list <code>, (i.e. comma only)</code>
        then this FHEMWEB instance will be read-only.<br> If set to
        <code>get,set</code>, then this FHEMWEB instance will only allow
        regular usage of the frontend by clicking the icons/buttons/sliders but
        not changing any configuration.<br>


        This attribute intended to be used together with hiddenroom/hiddengroup
        <br>

        <b>Note:</b>allowedCommands should work as intended, but no guarantee
        can be given that there is no way to circumvent it.  If a command is
        allowed it can be issued by URL manipulation also for devices that are
        hidden.</li><br>

    <li><a href="#allowfrom">allowfrom</a></li>
    </li><br>

    <a name="stylesheetPrefix"></a>
    <li>stylesheetPrefix<br>
      prefix for the files style.css, svg_style.css and svg_defs.svg. If the
      file with the prefix is missing, the default file (without prefix) will
      be used.  These files have to be placed into the FHEM directory, and can
      be selected directly from the "Select style" FHEMWEB menu entry. Example:
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
      <b>Note:</b>if the argument contains the string smallscreen or touchpad,
      then FHEMWEB will optimize the layout/access for small screen size (i.e.
      smartphones) or touchpad devices (i.e. tablets)<br>

      The default configuration installs 3 FHEMWEB instances: port 8083 for
      desktop browsers, port 8084 for smallscreen, and 8085 for touchpad.<br>

      If touchpad or smallscreen is specified, then WebApp support is
      activated: After viewing the site on the iPhone or iPad in Safari, you
      can add a link to the home-screen to get full-screen support. Links are
      rendered differently in this mode to avoid switching back to the "normal"
      browser.
      </li>
      <br>

    <a name="iconPath"></a>
    <li>iconPath<br>
      colon separated list of directories where the icons are read from.
      The directories start in the fhem/www/images directory. The default is
      $styleSheetPrefix:default:fhemSVG:openautomation<br>
      Set it to fhemSVG:openautomation to get only SVG images.
      </li>
      <br>

    <a name="hiddenroom"></a>
    <li>hiddenroom<br>
        Comma separated list of rooms to "hide", i.e. not to show. Special
        values are input, detail and save, in which case the input areas, link
        to the detailed views or save button is hidden (although each aspect
        still can be addressed through URL manipulation).<br>
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

    <a name="menuEntries"></a>
    <li>menuEntries<br>
        Comma separated list of name,html-link pairs to display in the
        left-side list.  Example:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li>
        <br>

    <a name="longpoll"></a>
    <li>longpoll<br>
        Affects devices states in the room overview only.<br>
        In this mode status update is refreshed more or less instantaneously,
        and state change (on/off only) is done without requesting a complete
        refresh from the server.
        Default is on.
        </li>
        <br>

    <a name="longpollSVG"></a>
    <li>longpollSVG<br>
        Reloads an SVG weblink, if an event should modify its content. Since 
        an exact determination of the affected events is too complicated, we
        need some help from the #FileLog definition in the .gplot file: the
        filter used there (second parameter) must either contain only the
        deviceName or have the form deviceName.event or deviceName.*. This is
        always the case when using the <a href="#plotEditor">Plot
        editor</a>. The SVG will be reloaded for <b>any</b> event triggered by
        this deviceName.
        Default is off.
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

    <a name="fwcompress"></a>
    <li>fwcompress<br>
        Enable compressing the HTML data (default is 1, i.e. yes, use 0 to switch it off).
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

    <a name="icon"></a>
    <li>icon<br>
        Set the icon for a device in the room overview. There is an
        icon-chooser in FHEMWEB to ease this task.  Setting icons for the room
        itself is indirect: there must exist an icon with the name
        ico<ROOMNAME>.png in the iconPath.
        </li>
        <br>

    <a name="roomIcons"></a>
    <li>roomIcons<br>
        Space separated list of room:icon pairs, to override the default
        behaviour of showing an icon, if there is one with the name of
        "icoRoomName". This is the correct way to remove the icon for the room
        Everything, or to set one for rooms with / in the name (e.g.
        Anlagen/EDV). The first part is treated as regexp, so space is
        represented by a dot.  Example:<br>
        attr WEB roomIcons Anlagen.EDV:icoEverything
        </li>
        <br>

    <a name="sortRooms"></a>
    <li>sortRooms<br>
        Space separated list of rooms to override the default
        sort order of the room links. Example:<br>
        attr WEB sortRooms DG OG EG Keller
        </li>
        <br>
        
    <a name="defaultRoom"></a>
    <li>defaultRoom<br>
        show the specified room if no room selected, e.g. on execution of some
        commands.  If set hides the <a href="#motd">motd</a>. Example:<br>
        attr WEB defaultRoom Zentrale
        </li>
        <br> 

    <a name="sortby"></a>
    <li>sortby<br>
        Take the value of this attribute when sorting the devices in the room
        overview instead of the alias, or if that is missing the devicename
        itself.
        </li>
        <br>

    <a name="devStateIcon"></a>
    <li>devStateIcon<br>
        First form:<br>
        <ul>
        Space separated list of regexp:icon-name:cmd triples, icon-name and cmd
        may be empty.<br>
        If the state of the device matches regexp, then icon-name will be
        displayed as the status icon in the room, and (if specified) clicking
        on the icon executes cmd.  If fhem cannot find icon-name, then the
        status text will be displayed. 
        Example:<br>
        <ul>
        attr lamp devStateIcon on:closed off:open<br>
        attr lamp devStateIcon on::A0 off::AI<br>
        attr lamp devStateIcon .*:noIcon<br>
        </ul>
        Note: if the image is referencing an SVG icon, then you can use the
        @colorname suffix to color the image. E.g.:<br>
        <ul>
        attr Fax devStateIcon on:control_building_empty@red off:control_building_filled:278727
        </ul>

        </ul>
        Second form:<br>
        <ul>
        Perl regexp enclosed in {}. If the code returns undef, then the default
        icon is used, if it retuns a string enclosed in <>, then it is
        interpreted as an html string. Else the string is interpreted as a
        devStateIcon of the first fom, see above.
        Example:<br>
        {'&lt;div style="width:32px;height:32px;background-color:green"&gt;&lt;/div&gt;'}
        </ul>
        </li>
        <br>

    <a name="devStateStyle"></a>
    <li>devStateStyle<br>
        Specify an HTML style for the given device, e.g.:<br>
        <ul>
        attr sensor devStateStyle style="text-align:left;;font-weight:bold;;"<br>
        </ul>
        </li>
        <br>

    <a name="webCmd"></a>
    <li>webCmd<br>
        Colon separated list of commands to be shown in the room overview for a
        certain device.  Has no effect on smallscreen devices, see the
        devStateIcon command for an alternative.<br>
        Example:
        <ul>
          attr lamp webCmd on:off:on-for-timer 10<br>
        </ul>
        <br>

        The first specified command is looked up in the "set device ?" list
        (see the <a href="#setList">setList</a> attribute for dummy devices).
        If <b>there</b> it contains some known modifiers (colon, followed
        by a comma separated list), then a different widget will be displayed:
        <ul>
          <li>if the modifier is ":noArg", then no further input field is
            displayed </li>
          <li>if the modifier is ":time", then a javascript driven timepicker is
            displayed.</li>
          <li>if the modifier is ":textField", an input field is displayed.</li>
          <li>if the modifier is of the form
            ":slider,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;", then a javascript
            driven slider is displayed</li>
          <li>if the modifier is of the form ":multiple,val1,val2,...", then
            multiple values can be selected, the result is comma separated.</li>
          <li>else a dropdown with all the modifier values is displayed</li>
        </ul>
        If the command is state, then the value will be used as a command.<br>
        Examples for the modifier:
        <ul>
          define d1 dummy<br>
          attr d1 webCmd state<br>
          attr d1 setList state:on,off<br>
          define d2 dummy<br>
          attr d2 webCmd state<br>
          attr d2 setList state:slider,0,1,10<br>
          define d3 dummy<br>
          attr d3 webCmd state<br>
          attr d3 setList state:time<br>
        </ul>
        Note: this is an attribute for the displayed device, not for the FHEMWEB
        instance.
        </li>
        <br>

     <a name="column"></a>
     <li>column<br>
       Allows to display more than one column per room overview, by specifying
       the groups for the columns. Example:<br>
       <ul><code>
         attr WEB column LivingRoom:FS20,notify|FHZ,notify DiningRoom:FS20|FHZ
       </code></ul>
       In this example in the LivingRoom the FS20 and the notify group is in
       the first column, the FHZ and the notify in the second.<br>
       Note: some elements like SVG plots and readingsGroup can only be part of
       a column if they are part of a <a href="#group">group</a>.
       </li>
    </ul>
  </ul>

=end html

=begin html_DE

<a name="FHEMWEB"></a>
<h3>FHEMWEB</h3>
<ul>
  FHEMWEB ist das default WEB-Frontend, es implementiert auch einen einfachen
  Webserver (optional mit Basic-Auth und HTTPS).
  <br> <br>

  <a name="FHEMWEBdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMWEB &lt;tcp-portnr&gt; [global]</code>
    <br><br>
    Aktiviert das Webfrontend auf dem Port &lt;tcp-portnr&gt;. Mit dem
    Parameter global werden Anfragen von allen Netzwerkschnittstellen
    akzeptiert (nicht nur vom localhost / 127.0.0.1) .  <br>

    Informationen f&uuml;r den Betrieb mit IPv6 finden Sie <a
    href="#telnet">hier</a>.<br>
  </ul>
  <br>

  <a name="FHEMWEBset"></a>
  <b>Set</b>
  <ul>
    <li>rereadicons<br>
      Damit wird die Liste der Icons neu eingelesen, f&uuml;r den Fall, dass
      Sie Icons l&ouml;schen oder hinzuf&uuml;gen.
      </li>
    <li>clearSvgCache<br>
      Im Verzeichnis www/SVGcache werden SVG Daten zwischengespeichert, wenn
      das Attribut SVGcache gesetzt ist.  Mit diesem Befehl leeren Sie diesen
      Zwischenspeicher.
      </li>
  </ul>
  <br>

  <a name="FHEMWEBget"></a>
  <b>Get</b>
  <ul>
    <li>icon &lt;logical icon&gt;<br>
        Liefert den absoluten Pfad des (logischen) Icons zur&uuml;ck. Beispiel:
        <ul>
          <code>get myFHEMWEB icon FS20.on<br>
          /data/Homeautomation/fhem/FHEM/FS20.on.png
          </code>
        </ul></li>
    <li>pathlist<br>
        Zeigt diejenigen Verzeichnisse an, in welchen die verschiedenen Dateien
        f&uuml;r FHEMWEB liegen.
        </li>
    <br><br>

  </ul>

  <a name="FHEMWEBattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="webname"></a>
    <li>webname<br>
        Der Pfad nach http://hostname:port/ . Standard ist fhem,
        so ist die Standard HTTP Adresse http://localhost:8083/fhem
        </li><br>

    <a name="refresh"></a>
    <li>refresh<br>
        Damit erzeugen Sie auf den ausgegebenen Webseiten einen automatischen
        Refresh, z.B. nach 5 Sekunden.
        </li><br>

    <a name="plotmode"></a>
    <li>plotmode<br>
        Spezifiziert, wie Plots erzeugt werden sollen:
        <ul>
          <li>SVG<br>
          Die Plots werden mit Hilfe des <a href="#SVG">SVG</a> Moduls als SVG
          Grafik gerendert. Das ist die Standardeinstellung.</li>

          <li>gnuplot<br>
          Die Plots werden mit Hilfe des gnuplot Programmes erzeugt. Diese
          Option ist aus historischen Gr&uuml;nden vorhanden.
          </li>

          <li>gnuplot-scroll<br>
          Wie gnuplot, der einfache Zugriff auf historische Daten ist aber
          genauso m&ouml;glich wie mit dem SVG Modul.</li>

        </ul>
        </li><br>

    <a name="plotsize"></a>
    <li>plotsize<br>
        gibt die Standardbildgr&ouml;&szlig;e aller erzeugten Plots an als
        Breite,H&ouml;he an. Um einem individuellen Plot die Gr&ouml;&szlig;e zu
        &auml;ndern muss dieses Attribut bei der entsprechenden SVG Instanz
        gesetzt werden.  Default sind 800,160 f&uuml;r Desktop und 480,160
        f&uuml;r Smallscreen
        </li><br>

    <a name="nrAxis"></a>
    <li>nrAxis<br>
        (bei mehrfach-Y-Achsen im SVG-Plot) Die Darstellung der Y Achsen
        ben&ouml;tigt Platz. Hierdurch geben Sie an wie viele Achsen Sie
        links,rechts [useLeft,useRight] ben&ouml;tigen. Default ist 1,1 (also 1
        Achse links, 1 Achse rechts).
        </li><br>

    <a name="SVGcache"></a>
    <li>SVGcache<br>
        Plots die sich nicht mehr &auml;ndern, werden im SVGCache Verzeichnis
        (www/SVGcache) gespeichert, um die erneute, rechenintensive
        Berechnung der Grafiken zu vermeiden. Default ist 0, d.h. aus.<br>
        Siehe den clearSvgCache Befehl um diese Daten zu l&ouml;schen.
        </li><br>

    <a name="endPlotToday"></a>
    <li>endPlotToday<br>
        Wird dieses FHEMWEB Attribut gesetzt, so enden Wochen- bzw. Monatsplots
        am aktuellen Tag, sonst wird die aktuelle Woche/Monat angezeigt.
        </li><br>

    <a name="endPlotNow"></a>
    <li>endPlotNow<br>
        Wenn Sie dieses FHEMWEB Attribut auf 1 setzen, werden Tages und
        Stunden-Plots zur aktuellen Zeit beendet. (&Auml;hnlich wie
        endPlotToday, nur eben min&uuml;tlich).
        Ansonsten wird der gesamte Tag oder eine 6 Stunden Periode (0, 6, 12,
        18 Stunde) gezeigt. Dieses Attribut wird nicht verwendet, wenn das SVG
        Attribut startDate benutzt wird.<br>
        </li><br>

    <a name="ploteditor"></a>
    <li>ploteditor<br>
        Gibt an ob der <a href="#plotEditor">Plot Editor</a> in der SVG detail
        ansicht angezeigt werden soll.  Kann auf always, onClick oder never
        gesetzt werden. Der Default ist always.
        </li><br>

    <a name="plotfork"></a>
    <li>plotfork<br>
        Normalerweise wird die Ploterstellung im Hauptprozess ausgef&uuml;hrt,
        FHEM wird w&auml;rend dieser Zeit nicht auf andere Ereignisse
        reagieren. Auf Rechnern mit sehr wenig Speicher (z.Bsp. FRITZ!Box 7170)
        kann das zum automatischen Abschuss des FHEM Prozesses durch das OS
        f&uuml;hren.
        </li><br>

    <a name="basicAuth"></a>
    <li>basicAuth, basicAuthMsg<br>
        Fragt username/password zur Autentifizierung ab. Es gibt mehrere
        Varianten:
        <ul>
        <li>falls das Argument <b>nicht</b> in {} eingeschlossen ist, dann wird
          es als base64 kodiertes benutzername:passwort interpretiert.
          Um sowas zu erzeugen kann man entweder einen der zahlreichen
          Webdienste verwenden, oder das base64 Programm. Beispiel:
          <ul><code>
            $ echo -n fhemuser:secret | base64<br>
            ZmhlbXVzZXI6c2VjcmV0<br>
            fhem.cfg:<br>
            attr WEB basicAuth ZmhlbXVzZXI6c2VjcmV0
          </code></ul>
          </li>
        <li>Werden die Argumente in {} angegeben, wird es als perl-Ausdruck
          ausgewertet, die Variablen $user and $password werden auf die
          eingegebenen Werte gesetzt. Falls der R&uuml;ckgabewert wahr ist,
          wird die Anmeldung akzeptiert.

          Beispiel:<br>
          <code>
            attr WEB basicAuth { "$user:$password" eq "admin:secret" }<br>
          </code>
          </li>
        </ul>
    </li><br>

    <a name="HTTPS"></a>
    <li>HTTPS<br>
        Erm&ouml;glicht HTTPS Verbindungen. Es werden die Perl Module
        IO::Socket::SSL ben&ouml;tigt, installierbar mit cpan -i
        IO::Socket::SSL oder apt-get install libio-socket-ssl-perl; (OSX und
        die FritzBox-7390 haben dieses Modul schon installiert.)<br>

        Ein lokales Zertifikat muss im Verzeichis certs erzeugt werden.
        Dieses Verzeichnis <b>muss</b> im <a href="#modpath">modpath</a>
        angegeben werden, also auf der gleichen Ebene wie das FHEM Verzeichnis.
        Beispiel:
        <ul>
        mkdir certs<br>
        cd certs<br>
        openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
        </ul>

      <br>
    </li>

    <a name="allowedCommands"></a>
    <li>allowedCommands<br>
        Eine Komma getrennte Liste der erlaubten Befehle. Bei einer leeren
        Liste (, dh. nur ein Komma)  wird dieser FHEMWEB-Instanz "read-only".
        <br> Falls es auf <code>get,set</code> gesetzt ist, dann sind in dieser
        FHEMWEB Instanz keine Konfigurations&auml;nderungen m&ouml;glich, nur
        "normale" Bedienung der Schalter/etc.<br>

        Dieses Attribut sollte zusammen mit dem hiddenroom/hiddengroup
        Attributen verwendet werden.  <br>

        <b>Achtung:</b> allowedCommands sollte wie hier beschrieben
        funktionieren, allerdings k&ouml;nnen wir keine Garantie geben,
        da&szlig; man sie nicht &uuml;berlisten, und Schaden anrichten kann.
        </li><br>

    <li><a href="#allowfrom">allowfrom</a>
        </li><br>

    <a name="stylesheetPrefix"></a>
    <li>stylesheetPrefix<br>
      Pr&auml;fix f&uuml;r die Dateien style.css, svg_style.css und
      svg_defs.svg. Wenn die Datei mit dem Pr&auml;fix fehlt, wird die Default
      Datei (ohne Pr&auml;fix) verwendet.  Diese Dateien  m&uuml;ssen im FHEM
      Ordner liegen und k&ouml;nnen direkt mit "Select style" im FHEMWEB
      Men&uuml;eintrag ausgew&auml;hlt werden. Beispiel:
      <ul>
        attr WEB stylesheetPrefix dark<br>
        <br>
        Referenzdateien:<br>
        <ul>
        darksvg_defs.svg<br>
        darksvg_style.css<br>
        darkstyle.css<br>
        </ul>
        <br>
      </ul>
      <b>Anmerkung:</b>Wenn der Parametername smallscreen oder touchpad
      enth&auml;lt, wird FHEMWEB das Layout/den Zugriff f&uuml;r entsprechende
      Ger&auml;te (Smartphones oder Touchpads) optimieren<br>

      Standardm&auml;&szlig;ig werden 3 FHEMWEB Instanzen aktiviert: Port 8083
      f&uuml;r Desktop Browser, Port 8084 f&uuml;r Smallscreen, und 8085
      f&uuml;r Touchpad.<br>

      Wenn touchpad oder smallscreen benutzt werden, wird WebApp support
      aktiviert: Nachdem Sie eine Seite am iPhone oder iPad mit Safari
      angesehen haben, k&ouml;nnen Sie einen Link auf den Homescreen anlegen um
      die Seite im Fullscreen Modus zu sehen. Links werden in diesem Modus
      anders gerendert, um ein "Zur&uuml;ckfallen" in den "normalen" Browser zu
      verhindern.
      </li><br>

    <a name="iconPath"></a>
    <li>iconPath<br>
      Durch Doppelpunkt getrennte Aufz&auml;hlung der Verzeichnisse, in
      welchen nach Icons gesucht wird.  Die Verzeichnisse m&uuml;ssen unter
      fhem/www/images angelegt sein. Standardeinstellung ist:
      $styleSheetPrefix:default:fhemSVG:openautomation<br>
      Setzen Sie den Wert auf fhemSVG:openautomation um nur SVG Bilder zu
      benutzen.
      </li><br>

    <a name="hiddenroom"></a>
    <li>hiddenroom<br>
       Eine Komma getrennte Liste, um R&auml;ume zu verstecken, d.h. nicht 
       anzuzeigen. Besondere Werte sind input, detail und save. In diesem
       Fall werden diverse Eingabefelder ausgeblendent. Durch direktes Aufrufen
       der URL sind diese R&auml;ume weiterhin erreichbar!<br>
       Ebenso k&ouml;nnen Eintr&auml;ge in den Logfile/Commandref/etc Block
       versteckt werden.  </li><br>

    <a name="hiddengroup"></a>
    <li>hiddengroup<br>
        Wie hiddenroom (siehe oben), jedoch auf Ger&auml;tegruppen bezogen.
        <br>
        Beispiel:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li><br>

    <a name="menuEntries"></a>
    <li>menuEntries<br>
        Komma getrennte Liste; diese Links werden im linken Men&uuml; angezeigt.
        Beispiel:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li><br>

    <a name="longpoll"></a>
    <li>longpoll<br>
        Dies betrifft die Aktualisierung der Ger&auml;testati in der
        Weboberfl&auml;che. Ist longpoll aktiviert, werden
        Status&auml;nderungen sofort im Browser dargestellt. ohne die Seite
        manuell neu laden zu m&uuml;ssen. Standard ist aktiviert.
        </li><br>


    <a name="longpollSVG"></a>
    <li>longpollSVG<br>
        L&auml;dt SVG Instanzen erneut, falls ein Ereignis dessen Inhalt
        &auml;ndert. Funktioniert nur, falls der dazugeh&ouml;rige #FileLog
        Definition in der .gplot Datei folgenden Form hat: deviceName.Event
        bzw. deviceName.*. Wenn man den <a href="#plotEditor">Plot
        Editor</a> benutzt, ist das &uuml;brigens immer der Fall. Die SVG Datei
        wird bei <b>jedem</b> ausl&ouml;senden Event dieses Ger&auml;tes neu
        geladen.  Standard ist aus.
        </li><br>

    <a name="redirectCmds"></a>
    <li>redirectCmds<br>
        Damit wird das URL Eingabefeld des Browser nach einem Befehl geleert.
        Standard ist eingeschaltet (1), ausschalten kann man es durch
        setzen des Attributs auf 0, z.Bsp. um den Syntax der Kommunikation mit
        FHEMWEB zu untersuchen.
        </li><br>

    <a name="fwcompress"></a>
    <li>fwcompress<br>
        Aktiviert die HTML Datenkompression (Standard ist 1, also ja, 0 stellt
        die Kompression aus).
        </li><br>

    <a name="reverseLogs"></a>
    <li>reverseLogs<br>
        Damit wird das Logfile umsortiert, die neuesten Eintr&auml;ge stehen
        oben.  Der Vorteil ist, dass man nicht runterscrollen muss um den
        neuesten Eintrag zu sehen, der Nachteil dass FHEM damit deutlich mehr
        Hauptspeicher ben&ouml;tigt, etwa 6 mal so viel, wie das Logfile auf
        dem Datentr&auml;ger gro&szlig; ist. Das kann auf Systemen mit wenig
        Speicher (FRITZ!Box) zum Terminieren des FHEM Prozesses durch das
        Betriebssystem f&uuml;hren.
        </li><br>

    <a name="CORS"></a>
    <li>CORS<br>
        Wenn auf 1 gestellt, wird FHEMWEB einen "Cross origin resource sharing"
        Header bereitstellen, n&auml;heres siehe Wikipedia.
        </li><br>

    <a name="icon"></a>
    <li>icon<br>
        Damit definiert man ein Icon f&uuml;r die einzelnen Ger&auml;te in der
        Raum&uuml;bersicht. Es gibt einen passenden Link in der Detailansicht
        um das zu vereinfachen. Um ein Bild f&uuml;r die R&auml;ume selbst zu
        definieren muss ein Icon mit dem Namen ico&lt;Raumname&gt;.png im
        iconPath existieren (oder man verwendet roomIcons, s.u.)
        </li><br>

    <a name="roomIcons"></a>
    <li>roomIcons<br>
        Leerzeichen getrennte Liste von room:icon Zuordnungen
        Der erste Teil wird als regexp interpretiert, daher muss ein
        Leerzeichen als Punkt geschrieben werden. Beispiel:<br>
          attr WEB roomIcons Anlagen.EDV:icoEverything
        </li><br>

    <a name="sortRooms"></a>
    <li>sortRooms<br>
        Durch Leerzeichen getrennte Liste von R&auml;umen, um deren Reihenfolge
        zu definieren.  Beispiel:<br>
          attr WEB sortRooms DG OG EG Keller
        </li><br>

    <a name="defaultRoom"></a>
    <li>defaultRoom<br>
        Zeigt den angegebenen Raum an falls kein Raum explizit ausgew&auml;hlt
        wurde.  Achtung: falls gesetzt, wird motd nicht mehr angezeigt.
        Beispiel:<br>
        attr WEB defaultRoom Zentrale
        </li><br> 

    <a name="sortby"></a>
    <li>sortby<br>
        Der Wert dieses Attributs wird zum sortieren von Ger&auml;ten in
        R&auml;umen verwendet, sonst w&auml;re es der Alias oder, wenn keiner
        da ist, der Ger&auml;tename selbst.
        </li><br>

    <a name="devStateIcon"></a>
    <li>devStateIcon<br>
        Erste Variante:<br>
        <ul>
        Leerzeichen getrennte Auflistung von regexp:icon-name:cmd
        Dreierp&auml;rchen, icon-name und cmd d&uuml;rfen leer sein.<br>

        Wenn der Zustand des Ger&auml;tes mit der regexp &uuml;bereinstimmt,
        wird als icon-name das entsprechende Status Icon angezeigt, und (falls
        definiert), l&ouml;st ein Klick auf das Icon das entsprechende cmd aus.
        Wenn fhem icon-name nicht finden kann, wird der Status als Text
        angezeigt. 
        Beispiel:<br>
        <ul>
        attr lamp devStateIcon on:closed off:open<br>
        attr lamp devStateIcon on::A0 off::AI<br>
        attr lamp devStateIcon .*:noIcon<br>
        </ul>
        Anmerkung: Wenn das Icon ein SVG Bild ist, kann das @colorname Suffix
        verwendet werden um das Icon einzuf&auml;rben. Z.B.:<br>
        <ul>
          attr Fax devStateIcon on:control_building_empty@red off:control_building_filled:278727
        </ul>

        </ul>
        Zweite Variante:<br>
        <ul>
        Perl regexp eingeschlossen in {}. Wenn der Code undef
        zur&uuml;ckliefert, wird das Standard Icon verwendet; wird ein String
        in <> zur&uuml;ck geliefert, wird dieser als HTML String interpretiert.
        Andernfalls wird der String als devStateIcon gem&auml;&szlig; der
        ersten Variante interpretiert, siehe oben.  Beispiel:<br>

        {'&lt;div style="width:32px;height:32px;background-color:green"&gt;&lt;/div&gt;'}
        </ul>
        </li><br>

    <a name="devStateStyle"></a>
    <li>devStateStyle<br>
        F&uuml;r ein best. Ger&auml;t einen best. HTML-Style benutzen.
        Beispiel:<br>
        <ul>
        attr sensor devStateStyle style="text-align:left;;font-weight:bold;;"<br>
        </ul>
        </li><br>

    <a name="webCmd"></a>
    <li>webCmd<br>
        Durch Doppelpunkte getrennte Auflistung von Befehlen, die f&uuml;r ein
        bestimmtes Ger&auml;t gelten sollen.  Funktioniert nicht mit
        smallscreen, ein Ersatz daf&uuml;r ist der devStateIcon Befehl.<br>
        Beispiel:
        <ul>
          attr lamp webCmd on:off:on-for-timer 10<br>
        </ul>
        <br>

        Der erste angegebene Befehl wird in der "set device ?" list
        nachgeschlagen (Siehe das <a href="#setList">setList</a> Attrib
        f&uuml;r Dummy Ger&auml;te).  Wenn <b>dort</b> bekannte Modifier sind,
        wird ein anderes Widget angezeigt:
        <ul>
          <li>Ist der Modifier ":noArg", wird kein weiteres Eingabefeld
              angezeigt.</li>

          <li>Ist der Modifier ":time", wird ein in Javaskript geschreibenes
              Zeitauswahlmen&uuml; angezeigt.</li>

          <li>Ist der Modifier ":textField", wird ein Eingabefeld
              angezeigt.</li>

          <li>Ist der Modifier in der Form
            ":slider,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;", so wird ein in
            JavaScript programmierter Slider angezeigt</li>

          <li>Ist der Modifier ":multiple,val1,val2,...", dann ein
            Mehrfachauswahl ist m&ouml;glich, das Ergebnis ist Komma-separiert.</li>

          <li>In allen anderen F&auml;llen erscheint ein Dropdown mit allen
            Modifier Werten.</li>
        </ul>

        Wenn der Befehl state ist, wird der Wert als Kommando interpretiert.<br>
        Beispiele f&uuml;r modifier:
        <ul>
          define d1 dummy<br>
          attr d1 webCmd state<br>
          attr d1 setList state:on,off<br>
          define d2 dummy<br>
          attr d2 webCmd state<br>
          attr d2 setList state:slider,0,1,10<br>
          define d3 dummy<br>
          attr d3 webCmd state<br>
          attr d3 setList state:time<br>
        </ul>

        Anmerkung: dies ist ein Attribut f&uuml;r das anzuzeigende Ger&auml;t,
        nicht f&uuml;r die FHEMWEBInstanz.
        </li><br>

     <a name="column"></a>
     <li>column<br>
        Damit werden mehrere Spalten f&uuml;r einen Raum angezeigt, indem
        sie verschiedene Gruppen Spalten zuordnen. Beispiel:<br>
        <ul><code>
          attr WEB column LivingRoom:FS20,notify|FHZ,notify DiningRoom:FS20|FHZ
        </code></ul>
       
        In diesem Beispiel werden im Raum LivingRoom die FS20 sowie die notify
        Gruppe in der ersten Spalte, die FHZ und das notify in der zweiten
        Spalte angezeigt.<br>
       
        Anmerkung: einige Elemente, wie SVG Plots und readingsGroup k&ouml;nnen
        nur Teil einer Spalte sein wenn sie in <a href="#group">group</a>
        stehen.
        </li><br>

    </ul>
  </ul>

=end html_DE

=cut
