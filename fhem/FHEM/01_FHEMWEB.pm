##############################################
# $Id$
package main;

use strict;
use warnings;
use TcpServerUtils;
use HttpUtils;
use Time::HiRes qw(gettimeofday);

#########################
# Forward declaration
sub FW_IconURL($);
sub FW_addContent(;$);
sub FW_addToWritebuffer($$@);
sub FW_answerCall($);
sub FW_dev2image($;$);
sub FW_devState($$@);
sub FW_digestCgi($);
sub FW_directNotify($@);
sub FW_doDetail($);
sub FW_fatal($);
sub FW_fileList($;$);
sub FW_htmlEscape($);
sub FW_iconName($);
sub FW_iconPath($);
sub FW_logWrapper($);
sub FW_makeEdit($$$);
sub FW_makeImage(@);
sub FW_makeTable($$$@);
sub FW_makeTableFromArray($$@);
sub FW_pF($@);
sub FW_pH(@);
sub FW_pHPlain(@);
sub FW_pO(@);
sub FW_parseColumns($);
sub FW_readIcons($);
sub FW_readIconsFrom($$);
sub FW_returnFileAsStream($$$$$);
sub FW_roomOverview($);
#sub FW_roomStatesForInform($$); # Forum 30515
sub FW_select($$$$$@);
sub FW_serveSpecial($$$$);
sub FW_showRoom();
sub FW_style($$);
sub FW_submit($$@);
sub FW_textfield($$$);
sub FW_textfieldv($$$$);
sub FW_updateHashes();
sub FW_visibleDevices(;$);
sub FW_widgetOverride($$);
sub FW_Read($$);

use vars qw($FW_dir);     # base directory for web server
use vars qw($FW_icondir); # icon base directory
use vars qw($FW_cssdir);  # css directory
use vars qw($FW_gplotdir);# gplot directory
use vars qw($MW_dir);     # moddir (./FHEM), needed by edit Files in new
                          # structure

use vars qw($FW_ME);      # webname (default is fhem), used by 97_GROUP/weblink
use vars qw($FW_CSRF);    # CSRF Token or empty
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
use vars qw($FW_fhemwebjs);# List of fhemweb*js scripts to load
use vars qw($FW_detail);  # currently selected device for detail view
use vars qw($FW_cmdret);  # Returned data by the fhem call
use vars qw($FW_room);    # currently selected room
use vars qw($FW_formmethod);
use vars qw(%FW_visibleDeviceHash);
use vars qw(@FW_httpheader); # HTTP header, line by line
use vars qw(%FW_httpheader); # HTTP header, as hash
use vars qw($FW_userAgent); # user agent string

$FW_formmethod = "post";

my $FW_zlib_checked;
my $FW_use_zlib = 1;
my $FW_use_sha = 0;
my $FW_activateInform = 0;
my $FW_lastWebName = "";  # Name of last FHEMWEB instance, for caching
my $FW_lastHashUpdate = 0;
my $FW_httpRetCode = "";
my %FW_csrfTokenCache;
my %FW_id2inform;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my $FW_data;       # Filecontent from browser when editing a file
my %FW_icons;      # List of icons
my @FW_iconDirs;   # Directory search order for icons
my $FW_RETTYPE;    # image/png or the like
my %FW_rooms;      # hash of all rooms
my @FW_roomsArr;   # ordered list of rooms
my %FW_groups;     # hash of all groups
my %FW_types;      # device types, for sorting
my %FW_hiddengroup;# hash of hidden groups
my $FW_inform;
my $FW_XHR;        # Data only answer, no HTML
my $FW_id="";      # id of current page
my $FW_jsonp;      # jasonp answer (sending function calls to the client)
my $FW_headerlines; #
my $FW_chash;      # client fhem hash
my $FW_encoding="UTF-8";
my $FW_styleStamp=time();


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
  $hash->{NotifyFn}= "FW_Notify";
  $hash->{AsyncOutputFn} = "FW_AsyncOutput";
  $hash->{ActivateInformFn} = "FW_ActivateInform";
  no warnings 'qw';
  my @attrList = qw(
    CORS:0,1
    HTTPS:1,0
    CssFiles
    JavaScripts
    SVGcache:1,0
    addHtmlTitle:1,0
    addStateEvent
    csrfToken
    csrfTokenHTTPHeader:0,1
    alarmTimeout
    allowedCommands
    allowfrom
    basicAuth
    basicAuthMsg
    closeConn:1,0
    column
    confirmDelete:0,1
    confirmJSError:0,1
    defaultRoom
    deviceOverview:always,iconOnly,onClick,never
    editConfig:1,0
    editFileList:textField-long
    endPlotNow:1,0
    endPlotToday:1,0
    fwcompress:0,1
    hiddengroup
    hiddengroupRegexp
    hiddenroom
    hiddenroomRegexp
    iconPath
    longpoll:0,1,websocket
    longpollSVG:1,0
    menuEntries
    mainInputLength
    nameDisplay
    ploteditor:always,onClick,never
    plotfork:1,0
    plotmode:gnuplot-scroll,gnuplot-scroll-svg,SVG
    plotEmbed:0,1
    plotsize
    plotWeekStartDay:0,1,2,3,4,5,6
    nrAxis
    redirectCmds:0,1
    refresh
    reverseLogs:0,1
    roomIcons
    sortRooms
    showUsedFiles:0,1
    sslVersion
    smallscreen:unused
    smallscreenCommands:0,1
    stylesheetPrefix
    styleData:textField-long
    title
    touchpad:unused
    viewport
    webname
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);


  ###############
  # Initialize internal structures
  map { addToAttrList($_) } ( "webCmd", "webCmdLabel:textField-long", "icon",
      "cmdIcon", "devStateIcon", "widgetOverride",  "sortby", "devStateStyle");
  InternalTimer(time()+60, "FW_closeInactiveClients", 0, 0);

  $FW_dir      = "$attr{global}{modpath}/www";
  $FW_icondir  = "$FW_dir/images";
  $FW_cssdir   = "$FW_dir/pgm2";
  $FW_gplotdir = "$FW_dir/gplot";

  if(opendir(DH, "$FW_dir/pgm2")) {
    $FW_fhemwebjs = join(",", map { $_ = ~m/^fhemweb_(.*).js$/; $1 }
                              grep { /fhemweb_(.*).js$/ }
                              readdir(DH));
    closedir(DH);
  }

  $data{webCmdFn}{"~"} = "FW_widgetFallbackFn"; # Should be the last

  if($init_done) {      # reload workaround
    foreach my $pe ("fhemSVG", "openautomation", "default") {
      FW_readIcons($pe);
    }
  }
}

#####################################
sub
FW_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/ || ($global && $global ne "global"));

  FW_Undef($hash, undef) if($hash->{OLDDEF}); # modify

  foreach my $pe ("fhemSVG", "openautomation", "default") {
    FW_readIcons($pe);
  }

  my $ret = TcpServer_Open($hash, $port, $global);

  # Make sure that fhem only runs once
  if($ret && !$init_done) {
    Log3 $hash, 1, "$ret. Exiting.";
    exit(1);
  }

  $hash->{CSRFTOKEN} = $FW_csrfTokenCache{$name};
  if(!defined($hash->{CSRFTOKEN})) {    # preserve over rereadcfg
    InternalTimer(1, sub(){
      if($featurelevel >= 5.8 && !AttrVal($name, "csrfToken", undef)) {
        my ($x,$y) = gettimeofday();
        ($defs{$name}{CSRFTOKEN}="csrf_".(rand($y)*rand($x))) =~s/[^a-z_0-9]//g;
        $FW_csrfTokenCache{$name} = $hash->{CSRFTOKEN};
      }
    }, $hash, 0);
  }

  return $ret;
}

#####################################
sub
FW_Undef($$)
{
  my ($hash, $arg) = @_;
  my $ret = TcpServer_Close($hash);
  if($hash->{inform}) {
    delete $FW_id2inform{$hash->{FW_ID}} if($hash->{FW_ID});
    %FW_visibleDeviceHash = FW_visibleDevices();
    delete($logInform{$hash->{NAME}});
  }
  return $ret;
}

#####################################
sub
FW_Read($$)
{
  my ($hash, $reread) = @_;
  my $name = $hash->{NAME};

  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $nhash = TcpServer_Accept($hash, "FHEMWEB");
    return if(!$nhash);
    my $wt = AttrVal($name, "alarmTimeout", undef);
    $nhash->{ALARMTIMEOUT} = $wt if($wt);
    $nhash->{CD}->blocking(0);
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

  if(!$reread) {
    # Data from HTTP Client
    my $buf;
    my $ret = sysread($c, $buf, 1024);

    if(!defined($ret) && $! == EWOULDBLOCK ){
      $hash->{wantWrite} = 1
        if(TcpServer_WantWrite($hash));
      return;
    } elsif(!$ret) { # 0==EOF, undef=error
      CommandDelete(undef, $name);
      Log3 $FW_wname, 4, "Connection closed for $name: ".
                  (defined($ret) ? 'EOF' : $!);
      return;
    }
    $hash->{BUF} .= $buf;
    if($hash->{SSL} && $c->can('pending')) {
      while($c->pending()) {
        sysread($c, $buf, 1024);
        $hash->{BUF} .= $buf;
      }
    }
  }

  if($hash->{websocket}) { # Work in Progress (Forum #59713)
    my $fin  = (ord(substr($hash->{BUF},0,1)) & 0x80)?1:0;
    my $op   = (ord(substr($hash->{BUF},0,1)) & 0x0F);
    my $mask = (ord(substr($hash->{BUF},1,1)) & 0x80)?1:0;
    my $len  = (ord(substr($hash->{BUF},1,1)) & 0x7F);
    my $i = 2;

    if( $len == 126 ) {
      $len = unpack( 'n', substr($hash->{BUF},$i,2) );
      $i += 2;
    } elsif( $len == 127 ) {
      $len = unpack( 'q', substr($hash->{BUF},$i,8) );
      $i += 8;
    }

    if( $mask ) {
      $mask = substr($hash->{BUF},$i,4);
      $i += 4;
    }

    my $data = substr($hash->{BUF}, $i, $len);
    #for( my $i = 0; $i < $len; $i++ ) {
    #  substr( $data, $i, 1, substr( $data, $i, 1, ) ^ substr($mask, $i% , 1) );
    #}
    #Log 1, "Received via websocket: ".unpack("H*",$data);
    return;
  }



  if(!$hash->{HDR}) {
    return if($hash->{BUF} !~ m/^(.*?)(\n\n|\r\n\r\n)(.*)$/s);
    $hash->{HDR} = $1;
    $hash->{BUF} = $3;
    if($hash->{HDR} =~ m/Content-Length:\s*([^\r\n]*)/si) {
      $hash->{CONTENT_LENGTH} = $1;
    }
  }

  my $POSTdata = "";
  if($hash->{CONTENT_LENGTH}) {
    return if(length($hash->{BUF})<$hash->{CONTENT_LENGTH});
    $POSTdata = substr($hash->{BUF}, 0, $hash->{CONTENT_LENGTH});
    $hash->{BUF} = substr($hash->{BUF}, $hash->{CONTENT_LENGTH});
  }

  @FW_httpheader = split(/[\r\n]+/, $hash->{HDR});
  %FW_httpheader = map {
                         my ($k,$v) = split(/: */, $_, 2);
                         $k =~ s/(\w+)/\u$1/g; # Forum #39203
                         $k=>(defined($v) ? $v : 1);
                       } @FW_httpheader;
  delete($hash->{HDR});

  my @origin = grep /Origin/i, @FW_httpheader;
  $FW_headerlines = (AttrVal($FW_wname, "CORS", 0) ?
              (($#origin<0) ? "": "Access-Control-Allow-".$origin[0]."\r\n").
              "Access-Control-Allow-Methods: GET POST OPTIONS\r\n".
              "Access-Control-Allow-Headers: Origin, Authorization, Accept\r\n".
              "Access-Control-Allow-Credentials: true\r\n".
              "Access-Control-Max-Age:86400\r\n".
              "Access-Control-Expose-Headers: X-FHEM-csrfToken\r\n": "");
   $FW_headerlines .= "X-FHEM-csrfToken: $defs{$FW_wname}{CSRFTOKEN}\r\n"
        if(defined($defs{$FW_wname}{CSRFTOKEN}) &&
           AttrVal($FW_wname, "csrfTokenHTTPHeader", 1));

  #########################
  # Return 200 for OPTIONS or 405 for unsupported method
  my ($method, $arg, $httpvers) = split(" ", $FW_httpheader[0], 3)
        if($FW_httpheader[0]);
  $method = "" if(!$method);
  if($method !~ m/^(GET|POST)$/i){
    my $retCode = ($method eq "OPTIONS") ? "200 OK" : "405 Method Not Allowed";
    TcpServer_WriteBlocking($FW_chash,
      "HTTP/1.1 $retCode\r\n" .
      $FW_headerlines.
      "Content-Length: 0\r\n\r\n");
    delete $hash->{CONTENT_LENGTH};
    FW_Read($hash, 1) if($hash->{BUF});
    Log 3, "$FW_cname: unsupported HTTP method $method, rejecting it."
        if($retCode ne "200 OK");
    FW_closeConn($hash);
    return;
  }

  #############################
  # AUTH
  if(!defined($FW_chash->{Authenticated})) {
    my $ret = Authenticate($FW_chash, \%FW_httpheader);
    if($ret == 0) {
      $FW_chash->{Authenticated} = 0; # not needed

    } elsif($ret == 1) {
      $FW_chash->{Authenticated} = 1; # ok
      # Need to send set-cookie (if set) after succesful authentication
      my $ah = $FW_chash->{".httpAuthHeader"};
      $FW_headerlines .= $ah if($ah);
      delete $FW_chash->{".httpAuthHeader"}; 
      
    } else {
      my $ah = $FW_chash->{".httpAuthHeader"};
      TcpServer_WriteBlocking($hash,
             ($ah ? $ah : "").
             $FW_headerlines.
             "Content-Length: 0\r\n\r\n");
      delete $hash->{CONTENT_LENGTH};
      FW_Read($hash, 1) if($hash->{BUF});
      return;
    }
  } else {
    my $ah = $FW_chash->{".httpAuthHeader"};
    $FW_headerlines .= $ah if($ah);
  }
  #############################

  my $now = time();
  $arg .= "&".$POSTdata if($POSTdata);
  delete $hash->{CONTENT_LENGTH};
  $hash->{LASTACCESS} = $now;

     
  if($FW_use_sha && $method eq 'GET' &&
     $FW_httpheader{Connection} && $FW_httpheader{Connection} =~ /Upgrade/i) {

    my $shastr = Digest::SHA::sha1_base64($FW_httpheader{'Sec-WebSocket-Key'}.
                                "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

    TcpServer_WriteBlocking($FW_chash,
       "HTTP/1.1 101 Switching Protocols\r\n" .
       "Upgrade: websocket\r\n" .
       "Connection: Upgrade\r\n" .
       "Sec-WebSocket-Accept:$shastr=\r\n".
       "\r\n" );
    $FW_chash->{websocket} = 1;

    my $me = $FW_chash;
    my ($cmd, $cmddev) = FW_digestCgi($arg);
    if($FW_id) {
      $me->{FW_ID} = $FW_id;
      $me->{canAsyncOutput} = 1;
    }
    FW_initInform($me, 0) if($FW_inform);
    return -1;
  }

  $FW_userAgent = $FW_httpheader{"User-Agent"};
  $arg = "" if(!defined($arg));
  Log3 $FW_wname, 4, "$name $method $arg; BUFLEN:".length($hash->{BUF});
  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
  my $pf = AttrVal($FW_wname, "plotfork", undef);
  if($pf) {   # 0 disables
    # Process SVG rendering as a parallel process
    my $p = $data{FWEXT};
    if(grep { $p->{$_}{FORKABLE} && $arg =~ m+^$FW_ME$_+ } keys %{$p}) {
      my $pid = fhemFork();
      if($pid) { # success, parent
        use constant PRIO_PROCESS => 0;
        setpriority(PRIO_PROCESS, $pid, getpriority(PRIO_PROCESS,$pid) + $pf)
          if($^O !~ m/Win/);
        # a) while child writes a new request might arrive if client uses
        # pipelining or
        # b) parent doesn't know about ssl-session changes due to child writing
        # to socket
        # -> have to close socket in parent... so that its only used in this
        # child.
        TcpServer_Disown( $hash );
        delete($defs{$name});
        delete($attr{$name});
        FW_Read($hash, 1) if($hash->{BUF});
        return;

      } elsif(defined($pid)){ # child
        delete $hash->{BUF};
        $hash->{isChild} = 1;

      } # fork failed and continue in parent
    }
  }

  $FW_httpRetCode = "200 OK";
  my $cacheable = FW_answerCall($arg);
  if($cacheable == -1) {
    FW_closeConn($hash);
    return;
  }

  my $compressed = "";
  if($FW_RETTYPE =~ m/(text|xml|json|svg|script)/i &&
     ($FW_httpheader{"Accept-Encoding"} &&
      $FW_httpheader{"Accept-Encoding"} =~ m/gzip/) &&
     $FW_use_zlib) {
    utf8::encode($FW_RET)
        if(utf8::is_utf8($FW_RET) && $FW_RET =~ m/[^\x00-\xFF]/ );
    eval { $FW_RET = Compress::Zlib::memGzip($FW_RET); };
    if($@) {
      Log 1, "memGzip: $@"; $FW_RET=""; #Forum #29939
    } else {
      $compressed = "Content-Encoding: gzip\r\n";
    }
  }

  my $length = length($FW_RET);
  my $expires = ($cacheable?
                ("Expires: ".FmtDateTimeRFC1123($now+900)."\r\n") : "");
  Log3 $FW_wname, 4,
        "$FW_wname: $arg / RL:$length / $FW_RETTYPE / $compressed / $expires";
  if( ! FW_addToWritebuffer($hash,
           "HTTP/1.1 $FW_httpRetCode\r\n" .
           "Content-Length: $length\r\n" .
           $expires . $compressed . $FW_headerlines .
           "Content-Type: $FW_RETTYPE\r\n\r\n" .
           $FW_RET, "FW_closeConn", 1) ){
    Log3 $name, 4, "Closing connection $name due to full buffer in FW_Read"
      if(!$hash->{isChild});
    FW_closeConn($hash);
    TcpServer_Close($hash, 1);
  } 
}

sub
FW_initInform($$)
{
  my ($me, $longpoll) = @_;

  if($FW_inform =~ /type=/) {
    foreach my $kv (split(";", $FW_inform)) {
      my ($key,$value) = split("=", $kv, 2);
      $me->{inform}{$key} = $value;
    }

  } else {                     # Compatibility mode
    $me->{inform}{type}   = ($FW_room ? "status" : "raw");
    $me->{inform}{filter} = ($FW_room ? $FW_room : ".*");
  }
  $FW_id2inform{$FW_id} = $me if($FW_id);

  my $filter = $me->{inform}{filter};
  $filter =~ s/([[\]().+?])/\\$1/g if($filter =~ m/room=/); # Forum #80390
  $filter = "NAME=.*" if($filter eq "room=all");
  $filter = "room!=.+" if($filter eq "room=Unsorted");

  my %h = map { $_ => 1 } devspec2array($filter);
  $h{global} = 1 if( $me->{inform}{addglobal} );
  $h{"#FHEMWEB:$FW_wname"} = 1;
  $me->{inform}{devices} = \%h;
  %FW_visibleDeviceHash = FW_visibleDevices();

  # NTFY_ORDER is larger than the normal order (50-)
  $me->{NTFY_ORDER} = $FW_cname;   # else notifyfn won't be called
  %ntfyHash = ();
  $me->{inform}{since} = time()-5
      if(!defined($me->{inform}{since}) || $me->{inform}{since} !~ m/^\d+$/);

  my $sinceTimestamp = FmtDateTime($me->{inform}{since});
  if($longpoll) {
    TcpServer_WriteBlocking($me,
       "HTTP/1.1 200 OK\r\n".
       $FW_headerlines.
       "Content-Type: application/octet-stream; charset=$FW_encoding\r\n\r\n".
       FW_roomStatesForInform($me, $sinceTimestamp));

  } else { # websocket
     FW_addToWritebuffer($me,
        FW_roomStatesForInform($me, $sinceTimestamp));
  }

  if($me->{inform}{withLog}) {
    $logInform{$me->{NAME}} = "FW_logInform";
  } else {
    delete($logInform{$me->{NAME}});
  }
}


sub
FW_addToWritebuffer($$@)
{
  my ($hash, $txt, $callback, $nolimit) = @_;

  if( $hash->{websocket} ) {
    my $len = length($txt);
    if( $len < 126 ) {
      $txt = chr(0x81) . chr($len) . $txt;
    } else {
      if ( $len < 65536 ) {
        $txt = chr(0x81) . chr(0x7E) . pack('n', $len) . $txt;
      } else {
        $txt = chr(0x81) . chr(0x7F) . chr(0x00) . chr(0x00) .
               chr(0x00) . chr(0x00) . pack('N', $len) . $txt;
      }
    }
  }
  return addToWritebuffer($hash, $txt, $callback, $nolimit);
}

sub
FW_AsyncOutput($$)
{
  my ($hash, $ret) = @_;

  return if(!$hash || !$hash->{FW_ID});
  if( $ret =~ m/^<html>(.*)<\/html>$/s ) {
    $ret = $1;

  } else {
    $ret = FW_htmlEscape($ret);
    $ret = "<pre>$ret</pre>" if($ret =~ m/\n/ );
    $ret =~ s/\n/<br>/g;
  }

  # find the longpoll connection with the same fw_id as the page that was the
  # origin of the get command
  my $data = FW_longpollInfo('JSON',
                             "#FHEMWEB:$FW_wname","FW_okDialog('$ret')","");
  FW_addToWritebuffer($hash, "$data\n");
  return undef;
}

sub
FW_closeConn($)
{
  my ($hash) = @_;
  if(!$hash->{inform} && !$hash->{BUF}) { # Forum #41125
    my $cc = AttrVal($hash->{SNAME}, "closeConn",
                        $FW_userAgent && $FW_userAgent=~m/(iPhone|iPad|iPod)/);
    if(!$FW_httpheader{Connection} || $cc) {
      TcpServer_Close($hash, 1);
    }
  }

  POSIX::exit(0) if($hash->{isChild});
  FW_Read($hash, 1) if($hash->{BUF});
}

###########################
sub
FW_serveSpecial($$$$)
{
  my ($file,$ext,$dir,$cacheable)= @_;
  $file =~ s,\.\./,,g; # little bit of security

  $file = "$FW_sp$file" if($ext eq "css" && -f "$dir/$FW_sp$file.$ext");
  $FW_RETTYPE = ext2MIMEType($ext);
  my $fname = ($ext ? "$file.$ext" : $file);
  return FW_returnFileAsStream("$dir/$fname", "", $FW_RETTYPE, 0, $cacheable);
}

sub
FW_answerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FW_cname};      # cache, else rereadcfg will delete us

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=$FW_encoding";
  $FW_CSRF = (defined($defs{$FW_wname}{CSRFTOKEN}) ?
                "&fwcsrf=".$defs{$FW_wname}{CSRFTOKEN} : "");

  $MW_dir = "$attr{global}{modpath}/FHEM";
  $FW_sp = AttrVal($FW_wname, "stylesheetPrefix", "");
  $FW_ss = ($FW_sp =~ m/smallscreen/);
  $FW_tp = ($FW_sp =~ m/smallscreen|touchpad/);
  @FW_iconDirs = grep { $_ } split(":", AttrVal($FW_wname, "iconPath",
                                "$FW_sp:default:fhemSVG:openautomation"));
  @FW_fhemwebjs = ("fhemweb.js");
  push(@FW_fhemwebjs, "$FW_sp.js") if(-r "$FW_dir/pgm2/$FW_sp.js");

  if($arg =~ m,$FW_ME/floorplan/([a-z0-9.:_]+),i) { # FLOORPLAN: special icondir
    unshift @FW_iconDirs, $1;
    FW_readIcons($1);
  }

  # /icons/... => current state of ...
  # also used for static images: unintended, but too late to change

  my ($dir1, $dirN, $ofile) = ($1, $2, $3)
             if($arg =~ m,^$FW_ME/([^/]*)(.*/)([^/]*)$,);
  if($arg =~ m,\brobots.txt$,) {
    Log3 $FW_wname, 1, "NOTE: $FW_wname is probed by a search engine";
    $FW_RETTYPE = "text/plain; charset=$FW_encoding";
    FW_pO "User-agent: *\r";
    FW_pO "Disallow: *\r";
    return 0;

  } elsif($arg =~ m,^$FW_ME/icons/(.*)$,) {
    my ($icon,$cacheable) = (urlDecode($1), 1);
    my $iconPath = FW_iconPath($icon);

    # if we do not have the icon, we convert the device state to the icon name
    if(!$iconPath) {
      my ($img, $link, $isHtml) = FW_dev2image($icon);
      $cacheable = 0;
      return 0 if(!$img);
      $iconPath = FW_iconPath($img);
      if($iconPath =~ m/\.svg$/i) {
        $FW_RETTYPE = ext2MIMEType("svg");
        FW_pO FW_makeImage($img, $img);
        return 0;
      }
    } elsif($iconPath =~ m/\.svg$/i && $icon=~ m/@/) {
      $FW_RETTYPE = ext2MIMEType("svg");
      FW_pO FW_makeImage($icon, $icon);
      return 0;
    }
    $iconPath =~ m/(.*)\.([^.]*)/;
    return FW_serveSpecial($1, $2, $FW_icondir, $cacheable);

  } elsif($dir1 && !$data{FWEXT}{"/$dir1"}) {
    my $dir = "$dir1$dirN";
    my $ext = "";
    $dir =~ s,/$,,;
    $dir =~ s/\.\.//g;
    $dir =~ s,www/,,g; # Want commandref.html to work from file://...

    my $file = urlDecode($ofile);        # 69164
    $file =~ s/\?.*//; # Remove timestamp of CSS reloader
    if($file =~ m/^(.*)\.([^.]*)$/) {
      $file = $1; $ext = $2;
    }
    my $ldir = "$FW_dir/$dir";
    $ldir = "$FW_dir/pgm2" if($dir eq "css" || $dir eq "js"); # FLOORPLAN compat
    $ldir = "$attr{global}{modpath}/docs" if($dir eq "docs");

    # pgm2 check is for jquery-ui images
    my $static = ($ext =~ m/(css|js|png|jpg)/i || $dir =~ m/^pgm2/);
    my $fname = ($ext ? "$file.$ext" : $file);
    return FW_serveSpecial($file, $ext, $ldir, ($arg =~ m/nocache/) ? 0 : 1)
      if(-r "$ldir/$fname" || $static); # no return for FLOORPLAN
    $arg = "/$dir/$ofile";

  } elsif($arg =~ m/^$FW_ME(.*)/s) {
    $arg = $1; # The stuff behind FW_ME, continue to check for commands/FWEXT

  } else {
    Log3 $FW_wname, 4, "$FW_wname: redirecting $arg to $FW_ME";
    TcpServer_WriteBlocking($me,
             "HTTP/1.1 302 Found\r\n".
             "Content-Length: 0\r\n".
             $FW_headerlines.
             "Location: $FW_ME\r\n\r\n");
    FW_closeConn($FW_chash);
    return -1;
  }


  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");
  my ($cmd, $cmddev) = FW_digestCgi($arg);
  if($cmd && $FW_CSRF) {
    my $supplied = defined($FW_webArgs{fwcsrf}) ? $FW_webArgs{fwcsrf} : "";
    my $want = $defs{$FW_wname}{CSRFTOKEN};
    if($supplied ne $want) {
      Log3 $FW_wname, 3, "FHEMWEB $FW_wname CSRF error: $supplied ne $want ".
                         "for client $FW_chash->{NAME}. ".
                         "For details see the csrfToken FHEMWEB attribute.";
      $FW_httpRetCode = "400 Bad Request";
      return 0;
    }
  }

  if( $FW_id ) {
    $me->{FW_ID} = $FW_id;
    $me->{canAsyncOutput} = 1;
  }

  if($FW_inform) {      # Longpoll header
    FW_initInform($me, 1);
    return -1;
  }

  my $docmd = 0;
  $docmd = 1 if($cmd &&
                $cmd !~ /^showlog/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  #If we are in XHR or json mode, execute the command directly
  if($FW_XHR || $FW_jsonp) {
    $FW_cmdret = $docmd ? FW_fC($cmd, $cmddev) : undef;
    $FW_RETTYPE = $FW_chash->{contenttype} ?
        $FW_chash->{contenttype} : "text/plain; charset=$FW_encoding";
    delete($FW_chash->{contenttype});

    if($FW_jsonp) {
      $FW_cmdret =~ s/'/\\'/g;
      # Escape newlines in JavaScript string
      $FW_cmdret =~ s/\n/\\\n/g;
      FW_pO "$FW_jsonp('$FW_cmdret');";

    } else {
      $FW_cmdret = FW_addLinks($FW_cmdret) if($FW_webArgs{addLinks});
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
      if(defined($FW_RETTYPE) && $FW_RETTYPE =~ m,text/html,) {
        my $dataAttr = FW_dataAttr();
        $FW_RET =~ s/<body/<body $dataAttr/;
      }
      use strict "refs";
      return defined($FW_RETTYPE) ? 0 : -1;
    }
  }


  #Now execute the command
  $FW_cmdret = undef;
  if($docmd) {
    $FW_cmdret = FW_fC($cmd, $cmddev);
    if($cmd =~ m/^define +([^ ]+) /) { # "redirect" after define to details
      $FW_detail = $1;
    }
    elsif($cmd =~ m/^copy +([^ ]+) +([^ ]+)/) { # redirect define to details
      $FW_detail = $2;
    }
  }

  # Redirect after a command, to clean the browser URL window
  if($docmd && !defined($FW_cmdret) && AttrVal($FW_wname, "redirectCmds", 1)) {
    my $tgt = $FW_ME;
       if($FW_detail) { $tgt .= "?detail=$FW_detail&fw_id=$FW_id" }
    elsif($FW_room)   { $tgt .= "?room=".urlEncode($FW_room)."&fw_id=$FW_id" }
    else              { $tgt .= "?fw_id=$FW_id" }
    TcpServer_WriteBlocking($me,
             "HTTP/1.1 302 Found\r\n".
             "Content-Length: 0\r\n". $FW_headerlines.
             "Location: $tgt\r\n".
             "\r\n");
    return -1;
  }

  if($FW_lastWebName ne $FW_wname || $FW_lastHashUpdate != $lastDefChange) {
    FW_updateHashes();
    $FW_lastWebName = $FW_wname;
    $FW_lastHashUpdate = $lastDefChange;
  }

  my $hsh = "Home, Sweet Home";
  my $t = AttrVal($FW_wname, "title", AttrVal("global", "title", $hsh));
  $t = eval $t if($t =~ m/^{.*}$/s); # Forum #48668
  $t = $hsh if(!defined($t));


  FW_pO '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" '.
                '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  FW_pO '<html xmlns="http://www.w3.org/1999/xhtml">';
  FW_pO "<head root=\"$FW_ME\">\n<title>$t</title>";
  FW_pO '<link rel="shortcut icon" href="'.FW_IconURL("favicon").'" />';
  FW_pO "<meta charset=\"$FW_encoding\">"; # Forum 28666
  FW_pO "<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\">";#Forum 18316

  # Enable WebApps
  if($FW_tp || $FW_ss) {
    my $icon = FW_iconPath("fhemicon_ios.png");
    $icon = $FW_ME."/images/".($icon ? $icon : "default/fhemicon_ios.png");
    my $viewport = '';
    if($FW_ss) {
       my $stf = $FW_userAgent =~ m/iPad|iPhone|iPod/ ? ",shrink-to-fit=no" :"";
       $viewport = "initial-scale=1.0,user-scalable=1$stf";
    } elsif($FW_tp) {
      $viewport = "width=768";
    }
    $viewport = AttrVal($FW_wname, "viewport", $viewport);
    FW_pO '<meta name="viewport" content="'.$viewport.'"/>' if ($viewport);
    FW_pO '<meta name="apple-mobile-web-app-capable" content="yes"/>';
    FW_pO '<meta name="mobile-web-app-capable" content="yes"/>'; # Forum #36183
    FW_pO '<link rel="apple-touch-icon" href="'.$icon.'"/>';
    FW_pO '<link rel="shortcut-icon"    href="'.$icon.'"/>';
  }

  if(!$FW_detail) {
    my $rf = AttrVal($FW_wname, "refresh", "");
    FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  }

  ########################
  # CSS
  my $cssTemplate = "<link href=\"$FW_ME/%s\" rel=\"stylesheet\"/>";
  FW_pO sprintf($cssTemplate, "pgm2/style.css?v=$FW_styleStamp");
  FW_pO sprintf($cssTemplate, "pgm2/jquery-ui.min.css");
  map { FW_pO sprintf($cssTemplate, $_); }
                        split(" ", AttrVal($FW_wname, "CssFiles", ""));

  ########################
  # JavaScripts
  my $jsTemplate =
        '<script attr=\'%s\' type="text/javascript" src="%s"></script>';
  FW_pO sprintf($jsTemplate, "", "$FW_ME/pgm2/jquery.min.js");
  FW_pO sprintf($jsTemplate, "", "$FW_ME/pgm2/jquery-ui.min.js");

  my (%jsNeg, @jsList); # jsNeg was used to exclude automatically loaded files
  map { $_ =~ m/^-(.*)$/ ? $jsNeg{$1} = 1 : push(@jsList, $_); }
      split(" ", AttrVal($FW_wname, "JavaScripts", ""));
  map { FW_pO sprintf($jsTemplate, "", "$FW_ME/pgm2/$_") if(!$jsNeg{$_}); }
      @FW_fhemwebjs;

  #######################
  # "Own" JavaScripts + their Attributes
  map {
    my $n = $_; $n =~ s+.*/++; $n =~ s/.js$//; $n =~ s/fhem_//; $n .= "Param";
    FW_pO sprintf($jsTemplate, AttrVal($FW_wname, $n, ""), "$FW_ME/$_");
  } @jsList;

  ########################
  # FW Extensions
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($h !~ m/HASH/ || !$h->{SCRIPT} || $h->{SCRIPT} =~ m+pgm2/jquery+);
      my $script = $h->{SCRIPT};
      $script = ($script =~ m,^/,) ? "$FW_ME$script" : "$FW_ME/pgm2/$script";
      FW_pO sprintf($jsTemplate, "", $script);
    }
  }

  my $csrf= ($FW_CSRF ? "fwcsrf='$defs{$FW_wname}{CSRFTOKEN}'" : "");
  my $gen = 'generated="'.(time()-1).'"';
  my $lp = 'longpoll="'.AttrVal($FW_wname,"longpoll",1).'"';
  $FW_id = $FW_chash->{NR} if( !$FW_id );

  my $dataAttr = FW_dataAttr();
  FW_pO "</head>\n<body name='$t' fw_id='$FW_id' $gen $lp $csrf $dataAttr>";

  if($FW_activateInform) {
    $cmd = "style eventMonitor $FW_activateInform";
    $FW_cmdret = undef;
    $FW_activateInform = "";
  }

  FW_roomOverview($cmd);

  if(defined($FW_cmdret)) {
    $FW_detail = "";
    $FW_room = "";

    if( $FW_cmdret =~ m/^<html>(.*)<\/html>$/s ) {
      $FW_cmdret = $1;

    } else {             # "linkify" output (e.g. for list)
      $FW_cmdret = FW_addLinks(FW_htmlEscape($FW_cmdret));
      $FW_cmdret =~ s/:\S+//g if($FW_cmdret =~ m/unknown.*choose one of/i);
      $FW_cmdret = "<pre>$FW_cmdret</pre>" if($FW_cmdret =~ m/\n/);
    }

    FW_addContent();
    if($FW_ss) {
      FW_pO "<div class=\"tiny\">$FW_cmdret</div>";
    } else {
      FW_pO $FW_cmdret;
    }
    FW_pO "</div>";

  }

  if($FW_contentFunc) {
    no strict "refs";
    my $ret = &{$FW_contentFunc}($arg);
    use strict "refs";
    return $ret if($ret);
  }

     if($cmd =~ m/^style /)    { FW_style($cmd,undef);    }
  elsif($FW_detail)            { FW_doDetail($FW_detail); }
  elsif($FW_room)              { FW_showRoom();           }
  elsif(!defined($FW_cmdret) &&
        !$FW_contentFunc) {

    $FW_room = AttrVal($FW_wname, "defaultRoom", '');
    if($FW_room ne '') {
      FW_showRoom(); 

    } else {
      my $motd = AttrVal("global","motd","none");
      if($motd ne "none") {
        FW_addContent("><pre class='motd'>$motd</pre></div");
      }
    }
  }
  FW_pO "</body></html>";
  return 0;
}

sub
FW_dataAttr()
{
  sub
  addParam($$)
  {
    my ($p, $default) = @_;
    my $val = AttrVal($FW_wname,$p, $default);
    $val =~ s/&/&amp;/g;
    $val =~ s/'/&quot;/g;
    return "data-$p='$val' ";
  }

  return
    addParam("confirmDelete", 1).
    addParam("confirmJSError", 1).
    addParam("addHtmlTitle", 1).
    addParam("styleData", "").
    "data-availableJs='$FW_fhemwebjs' ".
    "data-webName='$FW_wname '";
}

sub
FW_addContent(;$)
{
  my $add = ($_[0] ? " $_[0]" : "");
  FW_pO "<div id='content' $add>";
}

sub
FW_addLinks($)
{
  my ($txt) = @_;
  return undef if(!defined($txt));
  $txt =~ s,\b([a-z0-9._]+)\b,
            $defs{$1} ? "<a href='$FW_ME$FW_subdir?detail=$1'>$1</a>" : $1,gei;
  return $txt;
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
  $FW_id = "";
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
    $v = "" if(!defined($v));

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
    if($p eq "fw_id")        { $FW_id = $v; }
    if($p eq "jsonp")        { $FW_jsonp = $v; }
    if($p eq "inform")       { $FW_inform = $v; }

  }
  $cmd.=" $dev{$c}" if(defined($dev{$c}));
  $cmd.=" $arg{$c}" if(defined($arg{$c}) &&
                       ($arg{$c} ne "state" || $cmd !~ m/^set/));
  $cmd.=" $val{$c}" if(defined($val{$c}));

  #replace unicode newline symbol \u2424 with real newline
  my $nl = chr(226) . chr(144) . chr(164);
  $cmd =~ s/$nl/\n/g;

  return ($cmd, $c);
}

#####################
# create FW_rooms && FW_types
sub
FW_updateHashes()
{
  %FW_rooms = ();  # Make a room  hash
  %FW_groups = (); # Make a group  hash
  %FW_types = ();  # Needed for type sorting

  my $hre = AttrVal($FW_wname, "hiddenroomRegexp", "");
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));

    foreach my $r (split(",", AttrVal($d, "room", "Unsorted"))) {
      next if($hre && $r =~ m/$hre/);
      $FW_rooms{$r}{$d} = 1;
    }
    foreach my $r (split(",", AttrVal($d, "group", ""))) {
      $FW_groups{$r}{$d} = 1;
    }
    my $t = AttrVal($d, "subType", $defs{$d}{TYPE});
    $t = AttrVal($d, "model", $t) if($t && $t eq "unknown"); # RKO: ???
    $FW_types{$d} = $t;
  }

  $FW_room = AttrVal($FW_detail, "room", "Unsorted") if($FW_detail);

  if(AttrVal($FW_wname, "sortRooms", "")) { # Slow!
    my @sortBy = split( " ", AttrVal( $FW_wname, "sortRooms", "" ) );
    my %sHash;                                                       
    map { $sHash{$_} = FW_roomIdx(\@sortBy,$_) } keys %FW_rooms;
    @FW_roomsArr = sort { $sHash{$a} cmp $sHash{$b} } keys %FW_rooms;

  } else {
    @FW_roomsArr = sort keys %FW_rooms;

  }
}

##############################
sub
FW_makeTable($$$@)
{
  my($title, $name, $hash, $cmd) = (@_);

  return if(!$hash || !int(keys %{$hash}));
  my $class = lc($title);
  $class =~ s/[^A-Za-z]/_/g;
  FW_pO "<div class='makeTable wide ".lc($title)."'>";
  FW_pO "<span class='mkTitle'>$title</span>";
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
      FW_pO "<td><div class=\"dname\" data-name=\"$name\">$n</div></td>";

      if(ref($val)) { #handle readings
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        if($v =~ m,^<html>(.*)</html>$,) {
          $v = $1;
        } else {
          $v = FW_htmlEscape($v);
        }

        if($FW_ss) {
          $t = ($t ? "<br><div class=\"tiny\">$t</div>" : "");
          FW_pO "<td><div class=\"dval\">$v$t</div></td>";
        } else {
          $t = "" if(!$t);
          FW_pO "<td><div class=\"dval\" informId=\"$name-$n\">$v</div></td>";
          FW_pO "<td><div informId=\"$name-$n-ts\">$t</div></td>";
        }
      } else {
        $val = FW_htmlEscape($val);
        my $tattr = "informId=\"$name-$n\" class=\"dval\"";

        # if possible provide some links
        if ($n eq "room"){
          FW_pO "<td><div $tattr>".
                join(",", map { FW_pH("room=$_",$_,0,"",1,1) } split(",",$val)).
                "</div></td>";

        } elsif ($n =~ m/^fp_(.*)/ && $defs{$1}){ #special for Floorplan
          FW_pH "detail=$1", $val,1;

        } elsif ($modules{$val} ) {
          FW_pH "cmd=list%20TYPE=$val", $val,1;

        } else {
           $val = "<pre>$val</pre>" if($val =~ m/\n/ && $title eq "Attributes");
           FW_pO "<td><div $tattr>".
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
FW_detailSelect(@)
{
  my ($d, $cmd, $list, $param) = @_;
  return "" if(!$list || $FW_hiddenroom{input});
  my %al = map { s/:.*//;$_ => 1 } split(" ", $list);
  my @al = sort keys %al; # remove duplicate items in list

  my $selEl = (defined($al[0]) ? $al[0] : " ");
  $selEl = $1 if($list =~ m/([^ ]*):slider,/); # promote a slider if available
  $selEl = "room" if($list =~ m/room:/);
  $list =~ s/"/&quot;/g;

  my $ret ="";
  my $psc = AttrVal("global", "perlSyntaxCheck", ($featurelevel>5.7) ? 1 : 0);
  $ret .= "<div class='makeSelect' dev=\"$d\" cmd=\"$cmd\" list=\"$list\">";
  $ret .= "<form method=\"$FW_formmethod\" ".
                  "action=\"$FW_ME$FW_subdir\" autocomplete=\"off\">";
  $ret .= FW_hidden("detail", $d);
  $ret .= FW_hidden("dev.$cmd$d", $d.($param ? " $param":""));
  $ret .= FW_submit("cmd.$cmd$d", $cmd, $cmd.($psc?" psc":""));
  $ret .= "<div class=\"$cmd downText\">&nbsp;$d&nbsp;".
                ($param ? "&nbsp;$param":"")."</div>";
  $ret .= FW_select("sel_$cmd$d","arg.$cmd$d",\@al, $selEl, $cmd);
  $ret .= FW_textfield("val.$cmd$d", 30, $cmd);
  $ret .= "</form></div>";
  return $ret;
}

##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  return if($FW_hiddenroom{detail});
  return if(!defined($defs{$d}));
  my $h = $defs{$d};
  my $t = $h->{TYPE};
  $t = "MISSING" if(!defined($t));
  FW_addContent();

  if($FW_ss) {
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

  if(!$modules{$t}{FW_detailFn} || $modules{$t}{FW_deviceOverview}) {
    my $show = AttrVal($FW_wname, "deviceOverview", "always");

    if( $show ne 'never' ) {
      my %extPage = ();

      if( $show eq 'iconOnly' ) {
        my ($allSets, $cmdlist, $txt) = FW_devState($d, $FW_room, \%extPage);
        FW_pO "<div informId='$d'".
                ($FW_tp?"":" style='float:right'").">$txt</div>";

      } else {
        my $nameDisplay = AttrVal($FW_wname,"nameDisplay",undef);
        my %usuallyAtEnd = ();

        my $style = "";
        if( $show eq 'onClick' ) {
          my $pgm = "Javascript:" .
                     "s=document.getElementById('ddtable').style;".
                     "s.display = s.display=='none' ? 'block' : 'none';".
                     "s=document.getElementById('ddisp').style;".
                     "s.display = s.display=='none' ? 'block' : 'none';";
          FW_pO "<div id=\"ddisp\"><br><a style=\"cursor:pointer\" ".
                     "onClick=\"$pgm\">Show DeviceOverview</a><br><br></div>";
          $style = 'style="display:none"';
        }

        FW_pO "<div $style id=\"ddtable\" class='makeTable wide'>";
        FW_pO "<span class='mkTitle'>DeviceOverview</span>";
        FW_pO "<table class=\"block wide\">";
        FW_makeDeviceLine($d,1,\%extPage,$nameDisplay,\%usuallyAtEnd);
        FW_pO "</table></div>";
      }
    }
  }
  if($modules{$t}{FW_detailFn}) {
    no strict "refs";
    my $txt = &{$modules{$t}{FW_detailFn}}($FW_wname, $d, $FW_room);
    FW_pO "</td></tr><tr><td>$txt<br>" if(defined($txt));
    use strict "refs";
  }


  FW_pO FW_detailSelect($d, "set", FW_widgetOverride($d, getAllSets($d)));
  FW_pO FW_detailSelect($d, "get", FW_widgetOverride($d, getAllGets($d)));

  FW_makeTable("Internals", $d, $h);
  FW_makeTable("Readings", $d, $h->{READINGS});

  my $attrList = getAllAttr($d);
  my $roomList = "multiple,".join(",", 
                sort map { $_ =~ s/ /#/g ;$_} keys %FW_rooms);
  my $groupList = "multiple,".join(",", 
                sort map { $_ =~ s/ /#/g ;$_} keys %FW_groups);				
  $attrList =~ s/room /room:$roomList /;
  $attrList =~ s/group /group:$groupList /;
  $attrList = FW_widgetOverride($d, $attrList);
  $attrList =~ s/\\/\\\\/g;
  $attrList =~ s/'/\\'/g;
  FW_pO FW_detailSelect($d, "attr", $attrList);

  FW_makeTable("Attributes", $d, $attr{$d}, "deleteattr");
  FW_makeTableFromArray("Probably associated with", "assoc", getPawList($d));

  FW_pO "</td></tr></table>";

  my ($link, $txt, $td, $class, $doRet,$nonl) = @_;

  FW_pH "cmd=style iconFor $d", "Select icon",         undef, "detLink iconFor";
  FW_pH "cmd=style showDSI $d", "Extend devStateIcon", undef, "detLink showDSI";
  FW_pH "cmd=rawDef $d", "Raw definition", undef, "detLink rawDef";
  FW_pH "cmd=delete $d", "Delete this device ($d)",    undef, "detLink delDev"
         if($d ne "global");
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");
  FW_pH "$FW_ME/docs/commandref${sfx}.html#${t}", "Device specific help", 
         undef, "detLink devSpecHelp";
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
    FW_pO "<span class='mkTitle'>$txt</span>";
    FW_pO "<table class=\"block wide $class\">";
    foreach (sort @obj) {
      FW_pF "<tr class=\"%s\"><td>", (($row++)&1)?"odd":"even";
      FW_pH "detail=$_", $_;
      FW_pO "</td><td>";
      FW_pO $defs{$_}{STATE} if(defined($defs{$_}{STATE}));
      FW_pO "</td><td>";
      FW_pH "cmd=list TYPE=$defs{$_}{TYPE}", $defs{$_}{TYPE};
      FW_pO "</td>";
      FW_pO "</tr>";
    }
    FW_pO "</table></div>";
  }
}

sub
FW_roomIdx($$)
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


  ##########################
  # Rooms and other links
  foreach my $r (@FW_roomsArr) {
    next if($r eq "hidden" || $FW_hiddenroom{$r});
    $FW_room = AttrVal($FW_wname, "defaultRoom", $r)
        if(!$FW_room && $FW_ss);
    push @list1, FW_htmlEscape($r);
    push @list2, "$FW_ME?room=".urlEncode($r);
  }
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");
  my @list = (
     "Everything",    "$FW_ME?room=all",
     "",              "",
     "Commandref",    "$FW_ME/docs/commandref${sfx}.html",
     "Remote doc",    "http://fhem.de/fhem.html#Documentation",
     "Edit files",    "$FW_ME?cmd=style%20list",
     "Select style",  "$FW_ME?cmd=style%20select",
     "Event monitor", "$FW_ME?cmd=style%20eventMonitor",
     "",           "");
  my $lastname = ","; # Avoid double "".

  my $lfn = "Logfile";
  if($defs{$lfn}) { # Add the current Logfile to the list if defined
    my @l = FW_fileList($defs{$lfn}{logfile},1);
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
      my $csrf = ($list2[$idx] =~ m/cmd=/ ? $FW_CSRF : '');
      FW_pO "<option value='$list2[$idx]$csrf'$sel>$list1[$idx]</option>";
    }
    FW_pO "</select></td>";
    FW_pO "</tr>";

  } else {

    my $tblnr = 1;
    my $roomEscaped = FW_htmlEscape($FW_room);
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      my ($l1, $l2) = ($list1[$idx], $list2[$idx]);
      if(!$l1) {
        FW_pO "</table></td></tr>" if($idx);
        if($idx<int(@list1)-1) {
          FW_pO "<tr><td><table class=\"room roomBlock$tblnr\">";
          $tblnr++;
        }

      } else {
        FW_pF "<tr%s>", $l1 eq $roomEscaped ? " class=\"sel\"" : "";

        my $class = "menu_$l1";
        $class =~ s/[^A-Z0-9]/_/gi;

        # image tag if we have an icon, else empty
        my $icoName = "ico$l1";
        map { my ($n,$v) = split(":",$_); $icoName=$v if($l1 =~ m/^$n$/); }
                        split(" ", AttrVal($FW_wname, "roomIcons", ""));
        my $icon = FW_iconName($icoName) ?
                        FW_makeImage($icoName,$icoName,"icon")."&nbsp;" : "";

        if($l1 eq "Save config") {
          $l1 .= '</a> <a id="saveCheck" class="changed" style="visibility:'.
                      (int(@structChangeHist) ? 'visible' : 'hidden').'">?';
        }

        # Force external browser if FHEMWEB is installed as an offline app.
        my $target = '';        # Forum 33066, 39854
        $target = 'target="_blank"' if($l2 =~ s/^$FW_ME\/\+/$FW_ME\//);
        $target = 'target="_blank"' if($l2 =~ m/commandref|fhem.de.fhem.html/);
        if($l2 =~ m/.html$/ || $l2 =~ m/^(http|javascript)/ || length($target)){
           FW_pO "<td><div><a href='$l2' $target>$icon<span>$l1</span></a>".
                 "</div></td>";
        } else {
          FW_pH $l2, "$icon<span>$l1</span>", 1, $class;
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
  FW_pO FW_hidden("fw_id", $FW_id) if($FW_id);
  FW_pO FW_hidden("room", $FW_room) if($FW_room);
  FW_pO FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
  FW_pO FW_textfield("cmd", 
        AttrVal($FW_wname, "mainInputLength", $FW_ss ? 25 : 40), "maininput");
  FW_pO "</form>";
  FW_pO "</td></tr></table>";
  FW_pO "</div>";

}

sub
FW_alias($)
{
  my ($d) = @_;
  if($FW_room) {
    return AttrVal($d, "alias_$FW_room", AttrVal($d, "alias", $d));
  } else {
    return AttrVal($d, "alias", $d);
  }
}

sub
FW_makeDeviceLine($$$$$)
{
  my ($d,$row,$extPage,$nameDisplay,$usuallyAtEnd) = @_;
  my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

  FW_pF "\n<tr class=\"%s\">", ($row&1)?"odd":"even";
  my $devName = FW_alias($d);
  if(defined($nameDisplay)) {
    my ($DEVICE, $ALIAS) = ($d, $devName);
    $devName = eval $nameDisplay;
  }
  my $icon = AttrVal($d, "icon", "");
  $icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);

  if($FW_hiddenroom{detail}) {
    FW_pO "<td><div class=\"col1\">$icon$devName</div></td>"
          if(!$usuallyAtEnd->{$d});
  } else {
    FW_pH "detail=$d", "$icon$devName", 1, "col1" if(!$usuallyAtEnd->{$d});
  }

  my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf, $extPage);
  if($cmdlist) {
    my $cl2 = $cmdlist; $cl2 =~ s/ [^:]*//g; $cl2 =~ s/:/ /g;  # Forum #74053
    $allSets = "$allSets $cl2";
  }
  $allSets = FW_widgetOverride($d, $allSets);

  my $colSpan = ($usuallyAtEnd->{$d} ? ' colspan="2"' : '');
  FW_pO "<td informId=\"$d\"$colSpan>$txt</td>";

  ######
  # Commands, slider, dropdown
  my $smallscreenCommands = AttrVal($FW_wname, "smallscreenCommands", "");
  if((!$FW_ss || $smallscreenCommands) && $cmdlist) {
    my @a = split("[: ]", AttrVal($d, "cmdIcon", ""));
    Log 1, "ERROR: bad cmdIcon definition for $d" if(@a % 2);
    my %cmdIcon = @a;

    my @cl = split(":", $cmdlist);
    my @wcl = split(":", AttrVal($d, "webCmdLabel", ""));
    my $nRows;
    $nRows = split("\n", AttrVal($d, "webCmdLabel", "")) if(@wcl);
    @wcl = () if(@wcl != @cl);  # some safety

    for(my $i1=0; $i1<@cl; $i1++) {
      my $cmd = $cl[$i1];
      my $htmlTxt;
      my @c = split(' ', $cmd);   # @c==0 if $cmd==" ";
      if(int(@c) && $allSets && $allSets =~ m/\b$c[0]:([^ ]*)/) {
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
        $htmlTxt =~ s,^<td[^>]*>(.*)</td>$,$1,;
      } else {
        my $nCmd = $cmdIcon{$cmd} ? 
                      FW_makeImage($cmdIcon{$cmd},$cmd,"webCmd") : $cmd;
        $htmlTxt = FW_pH "cmd.$d=set $d $cmd$rf", $nCmd, 0, "", 1, 1;
      }

      if(@wcl > $i1) {
        if($nRows > 1) {
          FW_pO "<td><table class='wide'><tr>" if($i1 == 0);
          FW_pO  "<td>$wcl[$i1]</td><td>$htmlTxt</td>";
          FW_pO "</tr><tr>"          if($wcl[$i1] =~ m/\n/);
          FW_pO "</tr></table></td>" if($i1 == @cl-1);
        } else {
          FW_pO  "<td><div class='col3'>$wcl[$i1]$ htmlTxt</div></td>";
        }

      } else {
        FW_pO  "<td><div class='col3'>$htmlTxt</div></td>";
      }
    }
  }
  FW_pO "</tr>";
}

sub
FW_sortIndex($)
{
  my ($d) = @_;
  return $d if(!$attr{$d});

  my $val = $attr{$d}{sortby};
  if($val) {
    if($val =~ m/^{.*}/) {
      my %specials=("%NAME" => $d);
      my $exec = EvalSpecials($val, %specials);
      return AnalyzePerlCommand($FW_chash, $exec);
    }
    return lc($val);
  }

  if($FW_room) {
    $val = $attr{$d}{"alias_$FW_room"};
    return $val if($val);
  }

  $val = $attr{$d}{"alias"};
  return $val if($val);
  return $d;
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
  my $hge = AttrVal($FW_wname, "hiddengroupRegexp", undef);

  FW_pO "<form method=\"$FW_formmethod\" ".  # Why do we need a form here?
                "action=\"$FW_ME\" autocomplete=\"off\">";
  FW_addContent("room='$FW_room'");
  FW_pO "<table class=\"roomoverview\">";  # Need for equal width of subtables

  # array of all device names in the room (exception weblinks without group
  # attribute)
  my @devs= grep { (($FW_rooms{$FW_room} && $FW_rooms{$FW_room}{$_}) ||
                    $FW_room eq "all") && !IsIgnored($_) } keys %defs;
  my (%group, @atEnds, %usuallyAtEnd, %sortIndex);
  foreach my $dev (@devs) {
    if($modules{$defs{$dev}{TYPE}}{FW_atPageEnd}) {
      $usuallyAtEnd{$dev} = 1;
      if(!AttrVal($dev, "group", undef)) {
        $sortIndex{$dev} = FW_sortIndex($dev);
        push @atEnds, $dev;
        next;
      }
    }
    next if(!$FW_types{$dev});   # FHEMWEB connection, missed due to caching
    foreach my $grp (split(",", AttrVal($dev, "group", $FW_types{$dev}))) {
      next if($FW_hiddengroup{$grp}); 
      next if($hge && $grp =~ m/$hge/);
      $sortIndex{$dev} = FW_sortIndex($dev);
      $group{$grp}{$dev} = 1;
    }
  }

  # row counter
  my $row=1;
  my %extPage = ();
  my $nameDisplay = AttrVal($FW_wname,"nameDisplay",undef);

  my ($columns, $maxc) = FW_parseColumns(\%group);
  FW_pO "<tr class=\"column\">" if($maxc != -1);
  for(my $col=1; $col < ($maxc==-1 ? 2 : $maxc); $col++) {
    FW_pO "<td><table class=\"column tblcol_$col\">" if($maxc != -1);

    # iterate over the distinct groups  
    foreach my $g (sort { $maxc==-1 ?
                    $a cmp $b :
                    ($columns->{$a} ? $columns->{$a}->[0] : 99) <=>
                    ($columns->{$b} ? $columns->{$b}->[0] : 99) } keys %group) {

      next if($maxc != -1 && (!$columns->{$g} || $columns->{$g}->[1] != $col));

      #################
      # Check if there is a device of this type in the room
      FW_pO "<tr class='devTypeTr'><td><div class='devType'>$g</div></td></tr>";
      FW_pO "<tr><td>";
      FW_pO "<table class=\"block wide\" id=\"TYPE_$g\">";

      foreach my $d (sort { $sortIndex{$a} cmp $sortIndex{$b} }
                     keys %{$group{$g}}) {
        my $type = $defs{$d}{TYPE};
        $extPage{group} = $g;

        FW_makeDeviceLine($d,$row,\%extPage,$nameDisplay,\%usuallyAtEnd);

        if($modules{$type}{FW_addDetailToSummary}) {
          no strict "refs";
          my $txt = &{$modules{$type}{FW_detailFn}}($FW_wname, $d, $FW_room);
          use strict "refs";
          if(defined($txt)) {
            FW_pO "<tr class='".($row&1?"odd":"even").
                "'><td colspan='50'>$txt</td></tr>";
          }
        }
        $row++;
      }
      FW_pO "</table>";
      FW_pO "</td></tr>";
    }
    FW_pO "</table></td>" if($maxc != -1); # Column
  }
  FW_pO "</tr>" if($maxc != -1);

  FW_pO "</table><br>";

  # Now the "atEnds"
  foreach my $d (sort { $sortIndex{$a} cmp $sortIndex{$b} } @atEnds) {
    no strict "refs";
    $extPage{group} = "atEnd";
    FW_pO &{$modules{$defs{$d}{TYPE}}{FW_summaryFn}}($FW_wname, $d, 
                                                        $FW_room, \%extPage);
    use strict "refs";
  }
  FW_pO "</div>";
  FW_pO "</form>";
}

# Room1:col1group1,col1group2|col2group1,col2group2 Room2:...
sub
FW_parseColumns($)
{
  my ($aGroup) = @_;
  my %columns;
  my $colNo = -1;

  foreach my $roomgroup (split("[ \t\r\n]+", AttrVal($FW_wname,"column",""))) {
    my ($room, $groupcolumn)=split(":",$roomgroup,2);
    $room =~ s/%20/ /g; # Space
    next if(!defined($groupcolumn) || $FW_room !~ m/^$room$/);
    $colNo = 1;
    my @grouplist = keys %$aGroup;
    my %handled;

    foreach my $groups (split(/\|/,$groupcolumn)) {
      my $lineNo = 1;
      foreach my $group (split(",",$groups)) {
        $group =~ s/%20/ /g; # Forum #33612
        $group = "^$group\$"; #71381
        foreach my $g (grep /$group/ ,@grouplist) {
          next if($handled{$g});
          $handled{$g} = 1;
          $columns{$g} = [$lineNo++, $colNo]; #23212
        }
      }
      $colNo++;
    }
    last;
  }
  return (\%columns, $colNo);
}


#################
# return a sorted list of actual files for a given regexp
sub
FW_fileList($;$)
{
  my ($fname,$mtime) = @_;
  $fname =~ m,^(.*)/([^/]*)$,; # Split into dir and file
  my ($dir,$re) = ($1, $2);
  return $fname if(!$re);
  $dir =~ s/%L/$attr{global}{logdir}/g # %L present and log directory defined
        if($dir =~ m/%/ && $attr{global}{logdir});
  $re =~ s/%./[A-Za-z0-9]*/g;    # logfile magic (%Y, etc)
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$, || $f eq "99_Utils.pm");
    push(@ret, $f);
  }
  closedir(DH);
  return sort { (CORE::stat("$dir/$a"))[9] <=> (CORE::stat("$dir/$b"))[9] }
         @ret if($mtime);
  @ret = cfgDB_FW_fileList($dir,$re,@ret) if (configDBUsed());
  return sort @ret;
}


###################################
# Stream big files in chunks, to avoid bloating ourselves.
# This is a "terminal" function, no data can be appended after it is called.
sub
FW_outputChunk($$$)
{
  my ($hash, $buf, $d) = @_;
  $buf = $d->deflate($buf) if($d);
  if( length($buf) ){
    TcpServer_WriteBlocking($hash, sprintf("%x\r\n",length($buf)) .$buf."\r\n");
  }
}

sub
FW_returnFileAsStream($$$$$)
{
  my ($path, $suffix, $type, $doEsc, $cacheable) = @_;

  my $etag;

  if($cacheable) {
    #Check for If-None-Match header (ETag)
    my $if_none_match = $FW_httpheader{"If-None-Match"};
    $if_none_match =~ s/"(.*)"/$1/ if($if_none_match);
    $etag = (stat($path))[9]; #mtime
    if(defined($etag) && defined($if_none_match) && $etag eq $if_none_match) {
      my $now = time();
      my $rsp = "Date: ".FmtDateTimeRFC1123($now)."\r\n".
                "ETag: $etag\r\n".
                "Expires: ".FmtDateTimeRFC1123($now+900)."\r\n";
      Log3 $FW_wname, 4, "$FW_chash->{NAME} => 304 Not Modified";
      TcpServer_WriteBlocking($FW_chash,"HTTP/1.1 304 Not Modified\r\n".
                    $rsp . $FW_headerlines . "\r\n");
      return -1;
    }
  }

  if(!open(FH, $path)) {
    Log3 $FW_wname, 4, "FHEMWEB $FW_wname $path: $!";
    TcpServer_WriteBlocking($FW_chash, 
        "HTTP/1.1 404 Not Found\r\n".
        "Content-Length:0\r\n\r\n");
    FW_closeConn($FW_chash);
    return -1;
  }
  binmode(FH) if($type !~ m/text/); # necessary for Windows
  my $sz = -s $path;

  $etag = defined($etag) ? "ETag: \"$etag\"\r\n" : "";
  my $expires = $cacheable ? ("Expires: ".gmtime(time()+900)." GMT\r\n"): "";
  my $compr = ($FW_httpheader{"Accept-Encoding"} &&
               $FW_httpheader{"Accept-Encoding"} =~ m/gzip/ && $FW_use_zlib) ?
                "Content-Encoding: gzip\r\n" : "";
  TcpServer_WriteBlocking($FW_chash, "HTTP/1.1 200 OK\r\n".
                  $compr . $expires . $FW_headerlines . $etag .
                  "Transfer-Encoding: chunked\r\n" .
                  "Content-Type: $type; charset=$FW_encoding\r\n\r\n");

  my $d = Compress::Zlib::deflateInit(-WindowBits=>31) if($compr);
  FW_outputChunk($FW_chash, $FW_RET, $d);
  FW_outputChunk($FW_chash,
        "<a href='#end_of_file'>jump to the end</a><br><br>", $d)
    if($doEsc && $sz > 2048);
  my $buf;
  while(sysread(FH, $buf, 2048)) {
    if($doEsc) { # FileLog special
      $buf =~ s/</&lt;/g;
      $buf =~ s/>/&gt;/g;
    }
    FW_outputChunk($FW_chash, $buf, $d);
  }
  close(FH);
  FW_outputChunk($FW_chash, "<br/><a name='end_of_file'></a>".
        "<a href='#top'>jump to the top</a><br/><br/>", $d)
    if($doEsc && $sz > 2048);
  FW_outputChunk($FW_chash, $suffix, $d);

  if($compr) {
    $buf = $d->flush();
    if($buf){
      TcpServer_WriteBlocking($FW_chash,
                sprintf("%x\r\n",length($buf)) .$buf."\r\n");
    }
  }
  TcpServer_WriteBlocking($FW_chash, "0\r\n\r\n");
  FW_closeConn($FW_chash);
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
  my ($id, $name, $valueArray, $selected, $class, $jSelFn) = @_;
  $jSelFn = ($jSelFn ? "onchange=\"$jSelFn\"" : "");
  $id =~ s/\./_/g if($id);      # to avoid problems in JS DOM Search
  $id = ($id ? "id=\"$id\" informId=\"$id\"" : "");
  my $s = "<select $jSelFn $id name=\"$name\" class=\"$class\">";
  foreach my $v (@{$valueArray}) {
    if(defined($selected) && $v eq $selected) {
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
  $v=" value='$value'" if(defined($value));
  return if($FW_hiddenroom{input});
  my $s = "<input type='text' name='$n' class='$class' size='$z'$v ".
            "autocorrect='off' autocapitalize='off'/>";
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
  $s = FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}).$s if($FW_CSRF);
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
  FW_pO "<table class=\"block wide fileList\">";
  my $cfgDB = "";
  my $row = 0;
  foreach my $f (@files) {
    $cfgDB = ($f =~ s,\.configDB$,,);
    $cfgDB = ($cfgDB) ? "configDB" : "";
    FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
    FW_pH "cmd=style edit $f $cfgDB", $f, 1;
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
  } elsif($name =~ m/.*(js|css|_defs.svg)$/) {
    return "$FW_cssdir/$name";
  } elsif($name =~ m/.*(png|svg)$/) {
    my $d="";
    map { $d = $_ if(!$d && -d "$FW_icondir/$_") } @FW_iconDirs;
    return "$FW_icondir/$d/$name";
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

  return if(!Authorized($FW_chash, "cmd", $a[0]));

  my $start = '><table><tr><td';
  my $end   = "</td></tr></table></div>";
  
  if($a[1] eq "list") {
    FW_addContent($start);
    FW_pO "$msg<br><br>" if($msg);

    $attr{global}{configfile} =~ m,([^/]*)$,;
    my $cfgFileName = $1;
    FW_displayFileList("config file", $cfgFileName)
                                if(!configDBUsed());

    my $efl = AttrVal($FW_wname, 'editFileList',
      "Own modules and helper files:\$MW_dir:^(.*sh|[0-9][0-9].*Util.*pm|".
                        ".*cfg|.*\.holiday|myUtilsTemplate.pm|.*layout)\$\n".
      "Gplot files:\$FW_gplotdir:^.*gplot\$\n".
      "Styles:\$FW_cssdir:^.*(css|svg)\$");
    foreach my $l (split(/[\r\n]/, $efl)) {
      my ($t, $v, $re) = split(":", $l, 3);
      $v = eval $v;
      my @fList;
      if($v eq $FW_gplotdir && AttrVal($FW_wname,'showUsedFiles',0)) {
        @fList = defInfo('TYPE=SVG','GPLOTFILE');
        @fList = map { "$_.gplot" } @fList;
        @fList = map { "$_.configDB" } @fList if configDBUsed();
        my %fListUnique = map { $_, 1 } @fList;
        @fList = sort keys %fListUnique;
      } else {
        @fList = FW_fileList("$v/$re");
      }
      FW_displayFileList($t, @fList);
    }
    FW_pO $end;

  } elsif($a[1] eq "select") {
    my @fl = grep { $_ !~ m/(floorplan|dashboard)/ }
                        FW_fileList("$FW_cssdir/.*style.css");
    FW_addContent($start);
    FW_pO "<div class='fileList styles'>Styles</div>";
    FW_pO "<table class='block wide fileList'>";
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
    $FW_styleStamp = time();
    $FW_RET =~ s,/style.css\?v=\d+,/style.css?v=$FW_styleStamp,;
    FW_addContent($start);
    FW_pO "Reload the page in the browser.$end";

  } elsif($a[1] eq "edit") {
    my $fileName = $a[2]; 
    my $data = "";
    my $cfgDB = defined($a[3]) ? $a[3] : "";
    my $forceType = ($cfgDB eq 'configDB') ? $cfgDB : "file";
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FW_fileNameToPath($fileName);
    my($err, @content) = FileRead({FileName=>$filePath, ForceType=>$forceType});
    if($err) {
      FW_addContent(">$err</div");
      return;
    }
    $data = join("\n", @content);

    $data =~ s/&/&amp;/g;

    $attr{global}{configfile} =~ m,([^/]*)$,;
    my $readOnly = (AttrVal($FW_wname, "editConfig", ($1 ne $fileName)) ?
                        "" : "readonly");

    my $ncols = $FW_ss ? 40 : 80;
    FW_addContent();
    FW_pO "<form method=\"$FW_formmethod\">";
    if($readOnly) {
      FW_pO "You can enable saving this file by setting the editConfig ";
      FW_pO "attribute, but read the documentation first for the side effects.";
      FW_pO "<br><br>";
    } else {
      FW_pO FW_submit("save", "Save $fileName");
      FW_pO "&nbsp;&nbsp;";
      FW_pO FW_submit("saveAs", "Save as");
      FW_pO FW_textfieldv("saveName", 30, "saveName", $fileName);
      FW_pO "<br><br>";
    }
    FW_pO FW_hidden("cmd", "style save $fileName $cfgDB");
    FW_pO "<textarea $readOnly name=\"data\" cols=\"$ncols\" rows=\"30\">" .
            "$data</textarea>";
    FW_pO "</form>";
    FW_pO "</div>";

  } elsif($a[1] eq "save") {
    my $fileName = $a[2];
    my $cfgDB = defined($a[3]) ? $a[3] : "";
    $fileName = $FW_webArgs{saveName}
        if($FW_webArgs{saveAs} && $FW_webArgs{saveName});
    $fileName =~ s,.*/,,g;        # Little bit of security
    my $filePath = FW_fileNameToPath($fileName);
    my $isImg = ($fileName =~ m,\.(svg|png)$,i);
    my $forceType = ($cfgDB eq 'configDB' && !$isImg) ? $cfgDB : "file";

    $FW_data =~ s/\r//g if(!$isImg);
    my $err;
    if($fileName =~ m,\.png$,) {
      $err = FileWrite({FileName=>$filePath,ForceType=>$forceType,NoNL=>1},
                       $FW_data);
    } else {
      $err = FileWrite({ FileName=>$filePath, ForceType=>$forceType },
                        split("\n", $FW_data));
    }

    if($err) {
      FW_addContent(">$filePath: $!</div");
      return;
    }
    my $ret = FW_fC("rereadcfg") if($filePath eq $attr{global}{configfile});
    $ret = FW_fC("reload $fileName") if($fileName =~ m,\.pm$,);
    $ret = FW_Set("","","rereadicons") if($isImg);
    DoTrigger("global", "FILEWRITE $filePath", 1) if(!$ret); # Forum #32592
    $ret = ($ret ? "<h3>ERROR:</h3><b>$ret</b>" : "Saved $fileName");
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
    FW_addContent();
    my $filter = $a[2] ? ($a[2] eq "log" ? "global" : $a[2]) : ".*";
    FW_pO "Events (Filter: <a href=\"#\" id=\"eventFilter\">$filter</a>) ".
          "&nbsp;&nbsp;<span class='fhemlog'>FHEM log ".
                "<input id='eventWithLog' type='checkbox'".
                ($a[2] && $a[2] eq "log" ? " checked":"")."></span>".
          "&nbsp;&nbsp;<button id='eventReset'>Reset</button><br><br>\n";
    FW_pO "<div id=\"console\"></div>";
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

  FW_addContent();
  FW_pO "<form method=\"$FW_formmethod\">";
  FW_pO "Filter:&nbsp;".FW_textfieldv("icon-filter",20,"iconTable","")."<br>";
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

  $link .= $FW_CSRF if($link =~ m/cmd/);
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
  $link .= $FW_CSRF;
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
      my $data;
      do {
        $data = <FH>;
        if(!defined($data)) {
          Log 1, "$FW_icondir/$p is not useable";
          return "";
        }
      } until( $data =~ m/^<svg/ );
      $data .= join("", <FH>);
      close(FH);
      $data =~ s/[\r\n]/ /g;
      $data =~ s/ *$//g;
      $data =~ s/<svg/<svg class="$class" data-txt="$txt"/; #52967
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
    $p = urlEncodePath($p);
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
  my $cl = $FW_id && $FW_id2inform{$FW_id} ? $FW_id2inform{$FW_id} : $FW_chash;
  if($unique) {
    $ret = AnalyzeCommand($cl, $cmd);
  } else {
    $ret = AnalyzeCommandChain($cl, $cmd);
  }
  return $ret;
}

sub
FW_Attr(@)
{
  my ($type, $devName, $attrName, @param) = @_;
  my $hash = $defs{$devName};
  my $sP = "stylesheetPrefix";
  my $retMsg;

  if($type eq "set" && $attrName eq "HTTPS") {
    TcpServer_SetSSL($hash);
  }

  if($type eq "set") { # Converting styles
    if($attrName eq "smallscreen" || $attrName eq "touchpad") {
      $attr{$devName}{$sP} = $attrName;
      $retMsg="$devName: attribute $attrName deprecated, converted to $sP";
      $param[0] = $attrName; $attrName = $sP;
    }
  }

  if($attrName eq $sP) {
    # AttrFn is called too early, we have to set/del the attr here
    if($type eq "set") {
      $attr{$devName}{$sP} = (defined($param[0]) ? $param[0] : "default");
      FW_readIcons($attr{$devName}{$sP});
    } else {
      delete $attr{$devName}{$sP};
    }
  }

  if(($attrName eq "allowedCommands" ||
      $attrName eq "basicAuth" ||
      $attrName eq "basicAuthMsg")
      && $type eq "set") {
    my $aName = "allowed_$devName";
    my $exists = ($defs{$aName} ? 1 : 0);
    AnalyzeCommand(undef, "defmod $aName allowed");
    AnalyzeCommand(undef, "attr $aName validFor $devName");
    AnalyzeCommand(undef, "attr $aName $attrName ".join(" ",@param));
    return "$devName: ".($exists ? "modifying":"creating").
                " device $aName for attribute $attrName";
  }

  if($attrName eq "iconPath" && $type eq "set") {
    foreach my $pe (split(":", $param[0])) {
      $pe =~ s+\.\.++g;
      FW_readIcons($pe);
    }
  }

  if($attrName eq "JavaScripts" && $type eq "set") { # create some attributes
    my (%a, @add);
    map { $a{$_} = 1 } split(" ", $modules{FHEMWEB}{AttrList});
    map {
      $_ =~ s+.*/++; $_ =~ s/.js$//; $_ =~ s/fhem_//; $_ .= "Param";
      push @add, $_ if(!$a{$_} && $_ !~ m/^-/);
    } split(" ", $param[0]);
    $modules{FHEMWEB}{AttrList} .= " ".join(" ",@add) if(@add);
  }

  if($attrName eq "csrfToken") {
    return undef if($FW_csrfTokenCache{$devName} && !$init_done);
    my $csrf = $param[0];
    if($type eq "del" || $csrf eq "random") {
      my ($x,$y) = gettimeofday();
      ($csrf = "csrf_".(rand($y)*rand($x))) =~ s/[^a-z_0-9]//g;
    }

    if($csrf eq "none") {
      delete($hash->{CSRFTOKEN});
      delete($FW_csrfTokenCache{$devName});
    } else {
      $hash->{CSRFTOKEN} = $csrf;
      $FW_csrfTokenCache{$devName} = $hash->{CSRFTOKEN};
    }
  }

  if($attrName eq "longpoll" && $type eq "set" && $param[0] eq "websocket") {
    eval { require Digest::SHA; };
    if($@) {
      Log3 $FW_wname, 1, $@;
      return "$devName: Can't load Digest::SHA, no websocket";
      return -1;
    }
    $FW_use_sha = 1;
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
  my ($oname)= @_;
  return undef if(!defined($oname));
  my $name = $oname;
  $name =~ s/@.*//;
  foreach my $pe (@FW_iconDirs) {
    return $oname if($pe && $FW_icons{$pe} && $FW_icons{$pe}{$name});
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

  my $model = AttrVal($name, "model", "");

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
        if(defined($iconName) && $iconName eq "") {
          $rlink = $link;
          last;
        }
        if(defined($iconName) && defined(FW_iconName($iconName)))  {
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
  my $psc = AttrVal("global", "perlSyntaxCheck", ($featurelevel>5.7) ? 1 : 0);
  FW_pO "<td>";
  FW_pO "<a id=\"DEFa\" style=\"cursor:pointer\">$n</a>";
  FW_pO "</td>";

  $val =~ s,\\\n,\n,g;
  $val = FW_htmlEscape($val);
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
  FW_pO     "<br>" . FW_submit("cmd.${cmd}$name", "$cmd $name",($psc?"psc":""));
  FW_pO   "</form></div>";
  FW_pO  "</td>";
}


sub
FW_longpollInfo($@)
{
  my $fmt = shift;
  if($fmt && $fmt eq "JSON") {
    my @a;
    map { my $x = $_; #Forum 57377, ASCII 0-19 \ "
          $x=~ s/([\x00-\x1f\x22\x5c\x7f])/sprintf '\u%04x', ord($1)/ge;
          push @a,$x; } @_;
    return '["'.join('","', @a).'"]';
  } else {
    return join('<<', @_);
  }
}

sub
FW_roomStatesForInform($$)
{
  my ($me, $sinceTimestamp ) = @_;
  return "" if($me->{inform}{type} !~ m/status/);

  my %extPage = ();
  my @data;
  foreach my $dn (keys %{$me->{inform}{devices}}) {
    next if(!defined($defs{$dn}));
    my $t = $defs{$dn}{TYPE};
    next if(!$t || $modules{$t}{FW_atPageEnd});

    my $lastChanged = OldTimestamp( $dn );
    next if(!defined($lastChanged) || $lastChanged lt $sinceTimestamp);

    my ($allSet, $cmdlist, $txt) = FW_devState($dn, "", \%extPage);
    if($defs{$dn} && $defs{$dn}{STATE} && $defs{$dn}{TYPE} ne "weblink") {
      push @data,
           FW_longpollInfo($me->{inform}{fmt}, $dn, $defs{$dn}{STATE}, $txt);
    }
  }
  my $data = join("\n", map { s/\n/ /gm; $_ } @data)."\n";
  return $data;
}

sub
FW_logInform($$)
{
  my ($me, $msg) = @_; # _NO_ Log3 here!

  my $ntfy = $defs{$me};
  if(!$ntfy) {
    delete $logInform{$me};
    return;
  }
  $msg = FW_htmlEscape($msg);
  if(!FW_addToWritebuffer($ntfy, "<div class='fhemlog'>$msg</div>") ){
    TcpServer_Close($ntfy, 1);
    delete $logInform{$me};
  }
}

sub
FW_Notify($$)
{
  my ($ntfy, $dev) = @_;
  my $h = $ntfy->{inform};
  return undef if(!$h);
  my $isStatus = ($h->{type} =~ m/status/);
  my $events;

  my $dn = $dev->{NAME};
  if($dn eq "global" && $isStatus) {
    my $vs = int(@structChangeHist) ? 'visible' : 'hidden';
    my $data = FW_longpollInfo($h->{fmt},
        "#FHEMWEB:$ntfy->{NAME}","\$('#saveCheck').css('visibility','$vs')","");
    FW_addToWritebuffer($ntfy, $data."\n");

    if($dev->{CHANGED}) {
      $dn = $1 if($dev->{CHANGED}->[0] =~ m/^MODIFIED (.*)$/);
      if($dev->{CHANGED}->[0] =~ m/^ATTR ([^ ]+) ([^ ]+) (.*)$/s) {
        $dn = $1;
        my @a = ("$2: $3");
        $events = \@a;
      }
    }
  }

  if($dn eq $ntfy->{SNAME} &&
     $dev->{CHANGED} &&
     $dev->{CHANGED}->[0] =~ m/^JS(#([^:]*))?:(.*)$/) {
    my $data = $3;
    return if( $2 && $ntfy->{PEER} !~ m/$2/ );
    $data = FW_longpollInfo($h->{fmt}, "#FHEMWEB:$ntfy->{NAME}",$data,"");
    FW_addToWritebuffer($ntfy, $data."\n");
    return;
  }

  return undef if($isStatus && !$h->{devices}{$dn});

  my @data;
  my %extPage;
  my $isRaw = ($h->{type} =~ m/raw/);
  $events = deviceEvents($dev, AttrVal($FW_wname, "addStateEvent",!$isRaw))
        if(!$events);

  if($isStatus) {
    # Why is saving this stuff needed? FLOORPLAN?
    my @old = ($FW_wname, $FW_ME, $FW_ss, $FW_tp, $FW_subdir);
    $FW_wname = $ntfy->{SNAME};
    $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
    $FW_subdir = ($h->{iconPath} ? "/floorplan/$h->{iconPath}" : ""); # 47864
    $FW_sp = AttrVal($FW_wname, "stylesheetPrefix", 0);
    $FW_ss = ($FW_sp =~ m/smallscreen/);
    $FW_tp = ($FW_sp =~ m/smallscreen|touchpad/);
    @FW_iconDirs = grep { $_ } split(":", AttrVal($FW_wname, "iconPath",
                                "$FW_sp:default:fhemSVG:openautomation"));
    if($h->{iconPath}) {
      unshift @FW_iconDirs, $h->{iconPath};
      FW_readIcons($h->{iconPath});
    }

    if( !$modules{$defs{$dn}{TYPE}}{FW_atPageEnd} ) {
      my ($allSet, $cmdlist, $txt) = FW_devState($dn, "", \%extPage);
      ($FW_wname, $FW_ME, $FW_ss, $FW_tp, $FW_subdir) = @old;
      push @data, FW_longpollInfo($h->{fmt}, $dn, $dev->{STATE}, $txt);
    }

    #Add READINGS
    if($events) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      my $max = int(@{$events});
      for(my $i = 0; $i < $max; $i++) {
        if($events->[$i] !~ /: /) {
          if($dev->{NAME} eq 'global') { # Forum #47634
            my($type,$args) = split(' ', $events->[$i], 2);
            $args = "" if(!defined($args)); # global SAVE
            push @data, FW_longpollInfo($h->{fmt}, "$dn-$type", $args, $args);
          }

          next; #ignore 'set' commands
        }
        my ($readingName,$readingVal) = split(": ",$events->[$i],2);
        next if($readingName !~ m/^[A-Za-z\d_\.\-\/:]+$/); # Forum #70608,70844
        push @data, FW_longpollInfo($h->{fmt},
                                "$dn-$readingName", $readingVal,$readingVal);
        push @data, FW_longpollInfo($h->{fmt}, "$dn-$readingName-ts", $tn, $tn);
      }
    }
  }

  if($isRaw) {
    if($events) {    # It gets deleted sometimes (?)
      my $tn = TimeNow();
      if($attr{global}{mseclog}) {
        my ($seconds, $microseconds) = gettimeofday();
        $tn .= sprintf(".%03d", $microseconds/1000);
      }
      my $max = int(@{$events});
      my $dt = $dev->{TYPE};
      for(my $i = 0; $i < $max; $i++) {
        my $line = "$tn $dt $dn ".$events->[$i]."<br>";
        eval { 
          my $ok;
          if($h->{filterType} && $h->{filterType} eq "notify") {
            $ok = ($dn =~ m/^$h->{filter}$/ ||
                   "$dn:$events->[$i]" =~ m/^$h->{filter}$/) ;
          } else {
            $ok = ($line =~ m/$h->{filter}/) ;
          }
          push @data,$line if($ok);
        }
      }
    }
  }

  if(@data){
    if(!FW_addToWritebuffer($ntfy,
                join("\n", map { s/\n/ /gm; $_ } @data)."\n") ){
      my $name = $ntfy->{NAME};
      Log3 $name, 4, "Closing connection $name due to full buffer in FW_Notify";
      TcpServer_Close($ntfy, 1);
    }
  }

  return undef;
}

sub
FW_directNotify($@) # Notify without the event overhead (Forum #31293)
{
  my $filter;
  if($_[0] =~ m/^FILTER=(.*)/) {
    $filter = "^$1\$";
    shift;
  }
  my $dev = $_[0];
  foreach my $ntfy (values(%defs)) {
    next if(!$ntfy->{TYPE} ||
            $ntfy->{TYPE} ne "FHEMWEB" ||
            !$ntfy->{inform} ||
            !$ntfy->{inform}{devices}{$dev} ||
            $ntfy->{inform}{type} ne "status");
    next if($filter && $ntfy->{inform}{filter} !~ m/$filter/);
    if(!FW_addToWritebuffer($ntfy, 
        FW_longpollInfo($ntfy->{inform}{fmt}, @_)."\n")) {
      my $name = $ntfy->{NAME};
      Log3 $name, 4, "Closing connection $name due to full buffer in FW_Notify";
      TcpServer_Close($ntfy, 1);
    }
  }
}

###################
# Compute the state (==second) column
sub
FW_devState($$@)
{
  my ($d, $rf, $extPage) = @_;

  my ($hasOnOff, $link);

  my $cmdList = AttrVal($d, "webCmd", "");
  my $allSets = FW_widgetOverride($d, getAllSets($d));
  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));

  $hasOnOff = ($allSets =~ m/(^| )on(:[^ ]*)?( |$)/ &&
               $allSets =~ m/(^| )off(:[^ ]*)?( |$)/);
  my $txt = $state;
  my $dsi = ($attr{$d} && ($attr{$d}{stateFormat} || $attr{$d}{devStateIcon}));

  if(AttrVal($d, "showtime", undef)) {
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

    my $cmdlist = (defined($link) ? $link : "");
    my $h = "";
    foreach my $cmd (split(":", $cmdlist)) {
      my $htmlTxt;
      my @c = split(' ', $cmd);   # @c==0 if $cmd==" ";
      if(int(@c) && $allSets && $allSets =~ m/\b$c[0]:([^ ]*)/) {
        my $values = $1;
        foreach my $fn (sort keys %{$data{webCmdFn}}) {
          no strict "refs";
          $htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname,
                                           $d, $FW_room, $cmd, $values);
          use strict "refs";
          last if(defined($htmlTxt));
        }
      }

      if( $htmlTxt ) {
        $h .= "<p>$htmlTxt</p>";
      }
    }

    if( $h ) {
      $link = undef;
      $h =~ s/'/\\"/g;
      $txt = "<a onClick='FW_okDialog(\"$h\",this)'\>$txt</a>";
    } else {
      $link = "cmd.$d=set $d $link" if(defined($link));
    }

  }


  if($hasOnOff) {
    # Have to cover: "on:An off:Aus", "A0:Aus AI:An Aus:off An:on"
    my $on  = ReplaceEventMap($d, "on", 1);
    my $off = ReplaceEventMap($d, "off", 1);
    $link = "cmd.$d=set $d " . ($state eq $on ? $off : $on) if(!defined($link));
    $cmdList = "$on:$off" if(!$cmdList);

  }

  if(defined($link)) { # Have command to execute
    my $room = AttrVal($d, "room", undef);
    if($room) {
      if($FW_room && $room =~ m/\b$FW_room\b/) {
        $room = $FW_room;
      } else {
        $room =~ s/,.*//;
      }
      $link .= "&room=".urlEncode($room);
    }
    $txt = "<a href=\"$FW_ME$FW_subdir?$link$rf$FW_CSRF\">$txt</a>"
       if($link !~ m/ noFhemwebLink\b/);
  }

  my $style = AttrVal($d, "devStateStyle", "");
  $state =~ s/"//g;
  $txt = "<div id=\"$d\" $style title=\"$state\" class=\"col2\">$txt</div>";

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

  my $arg = (defined($a[1]) ? $a[1] : "");
  if($arg eq "icon") {
    return "need one icon as argument" if(int(@a) != 3);
    my $ofn = $FW_wname;
    $FW_wname = $hash->{NAME};
    my $icon = FW_iconPath($a[2]);
    $FW_wname = $ofn;
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
      map { my $n="$cDir/$_"; unlink($n) if(-f $n); } readdir(DH);
      closedir(DH);
    } else {
      return "Can't open $cDir: $!";
    }
  }
  return undef;
}

#####################################
sub
FW_closeInactiveClients()
{
  my $now = time();
  foreach my $dev (keys %defs) {
    next if(!$defs{$dev}{TYPE} || $defs{$dev}{TYPE} ne "FHEMWEB" ||
            !$defs{$dev}{LASTACCESS} || $defs{$dev}{inform} ||
            ($now - $defs{$dev}{LASTACCESS}) < 60);
    Log3 $FW_wname, 4, "Closing inactive connection $dev";
    FW_Undef($defs{$dev}, undef);
    delete $defs{$dev};
    delete $attr{$dev};
  }
  InternalTimer($now+60, "FW_closeInactiveClients", 0, 0);
}

sub
FW_htmlEscape($)
{
  my ($txt) = @_;
  $txt =~ s/&/&amp;/g;
  $txt =~ s/</&lt;/g;
  $txt =~ s/>/&gt;/g;
  $txt =~ s/'/&apos;/g;
#  $txt =~ s/\n/<br>/g;
  return $txt;
}

###########################
# Widgets START
sub 
FW_widgetFallbackFn()
{
  my ($FW_wname, $d, $FW_room, $cmd, $values) = @_;

  # webCmd "temp 30" should remain text
  # noArg is needed for fhem.cfg.demo / Cinema
  return "" if(!$values || $values eq "noArg");

  my($reading) = split( ' ', $cmd, 2 );
  my $current;
  if($cmd eq "desired-temp" || $cmd eq "desiredTemperature") {
    $current = ReadingsVal($d, $cmd, 20);
    $current =~ s/ .*//;        # Cut off Celsius
    $current = sprintf("%2.1f", int(2*$current)/2) if($current =~ m/[0-9.-]/);
  } else {
    $current = ReadingsVal($d, $reading, undef);
    if( !defined($current) ) {
      $reading = 'state';
      $current = Value($d);
    }
    $current =~ s/$cmd //;
    $current = ReplaceEventMap($d, $current, 1);
  }
  return "<td><div class='fhemWidget' cmd='$cmd' reading='$reading' ".
                "dev='$d' arg='$values' current='$current'></div></td>";
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
FW_ActivateInform($;$)
{
  my ($cl, $arg) = @_;
  $FW_activateInform = ($arg ? $arg : 1);
}

sub
FW_widgetOverride($$)
{
  my ($d, $str) = @_;

  return $str if(!$str);

  my $da = AttrVal($d, "widgetOverride", "");
  my $fa = AttrVal($FW_wname, "widgetOverride", "");
  return $str if(!$da && !$fa);

  my @list;
  push @list, split(" ", $fa) if($fa);
  push @list, split(" ", $da) if($da);
  foreach my $na (@list) {
    my ($n,$a) = split(":", $na, 2);
    $str =~ s/\b($n)\b(:[^ ]*)?/$1:$a/g;
  }
  return $str;
}


1;

=pod
=item helper
=item summary    HTTP Server and FHEM Frontend
=item summary_DE HTTP Server und FHEM Frontend
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
    <a name="addHtmlTitle"></a>
    <li>addHtmlTitle<br>
      If set to 0, do not add a title Attribute to the set/get/attr detail
      widgets. This might be necessary for some screenreaders. Default is 1.
      </li><br>



    <li><a href="#addStateEvent">addStateEvent</a></li><br>

    <li>alias_&lt;RoomName&gt;<br>
        If you define a userattr alias_&lt;RoomName&gt; and set this attribute
        for a device assgined to &lt;RoomName&gt;, then this value will be used
        when displaying &lt;RoomName&gt;.<br>
        Note: you can use the userattr alias_.* to allow all rooms, but in this
        case the attribute dropdown in the device detail view won't work for the
        alias_.* attributes.
        </li><br>

    <li><a href="#allowfrom">allowfrom</a></li>
    </li><br>

    <li>allowedCommands, basicAuth, basicAuthMsg<br>
        Please create these attributes for the corresponding <a
        href="#allowed">allowed</a> device, they are deprecated for the FHEMWEB
        instance from now on.
    </li><br>

    <a name="closeConn"></a>
    <li>closeConn<br>
      If set, a TCP Connection will only serve one HTTP request. Seems to
      solve problems on iOS9 for WebApp startup.
      </li><br>


    <a name="column"></a>
    <li>column<br>
      Allows to display more than one column per room overview, by specifying
      the groups for the columns. Example:<br>
      <ul><code>
        attr WEB column LivingRoom:FS20,notify|FHZ,notify DiningRoom:FS20|FHZ
      </code></ul>
      In this example in the LivingRoom the FS20 and the notify group is in
      the first column, the FHZ and the notify in the second.<br>
      Notes: some elements like SVG plots and readingsGroup can only be part of
      a column if they are part of a <a href="#group">group</a>.
      This attribute can be used to sort the groups in a room, just specify
      the groups in one column.
      Space in the room and group name has to be written as %20 for this
      attribute. Both the room name and the groups are regular expressions.
      </li>
      <br>

    <a name="confirmDelete"></a>
    <li>confirmDelete<br>
        confirm delete actions with a dialog. Default is 1, set it to 0 to
        disable the feature.
        </li>
        <br> 

    <a name="confirmJSError"></a>
    <li>confirmJSError<br>
        JavaScript errors are reported in a dialog as default.
        Set this attribute to 0 to disable the reporting.
        </li>
        <br> 

    <a name="CORS"></a>
    <li>CORS<br>
        If set to 1, FHEMWEB will supply a "Cross origin resource sharing"
        header, see the wikipedia for details.
        </li>
        <br>

    <a name="csrfToken"></a>
    <li>csrfToken<br>
       If set, FHEMWEB requires the value of this attribute as fwcsrf Parameter
       for each command. It is used as countermeasure for Cross Site Resource
       Forgery attacks. If the value is random, then a random number will be
       generated on each FHEMWEB start. If it is set to the literal string
       none, no token is expected. Default is random for featurelevel 5.8 and
       greater, and none for featurelevel below 5.8 </li><br>

    <a name="csrfTokenHTTPHeader"></a>
    <li>csrfTokenHTTPHeader<br>
       If set (default), FHEMWEB sends the token with the X-FHEM-csrfToken HTTP
       header, which is used by some clients. Set it to 0 to switch it off, as
       a measurre against shodan.io like FHEM-detection.</li><br>

    <a name="CssFiles"></a>
    <li>CssFiles<br>
       Space separated list of .css files to be included. The filenames
       are relative to the www directory. Example:
       <ul><code>
         attr WEB CssFiles pgm2/mystyle.css
       </code></ul>
       </li><br>

    <a name="cmdIcon"></a>
    <li>cmdIcon<br>
        Space separated list of cmd:iconName pairs. If set, the webCmd text is
        replaced with the icon. An easy method to set this value is to use 
        "Extend devStateIcon" in the detail-view, and copy its value.<br>
        Example:<ul>
        attr lamp cmdIcon on:control_centr_arrow_up off:control_centr_arrow_down
        </ul>
        </li><br>

    <a name="defaultRoom"></a>
    <li>defaultRoom<br>
        show the specified room if no room selected, e.g. on execution of some
        commands.  If set hides the <a href="#motd">motd</a>. Example:<br>
        attr WEB defaultRoom Zentrale
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
        attr Fax devStateIcon on:control_building_empty@red
                              off:control_building_filled:278727
        </ul>
        If the cmd is noFhemwebLink, then no HTML-link will be generated, i.e.
        nothing will happen when clicking on the icon or text.

        </ul>
        Second form:<br>
        <ul>
        Perl code enclosed in {}. If the code returns undef, then the default
        icon is used, if it retuns a string enclosed in <>, then it is
        interpreted as an html string. Else the string is interpreted as a
        devStateIcon of the first fom, see above.
        Example:<br>
        {'&lt;div
         style="width:32px;height:32px;background-color:green"&gt;&lt;/div&gt;'}
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

    <li>deviceOverview<br>
        Configures if the device line from the room view (device icon, state
        icon and webCmds/cmdIcons) should also be shown in the device detail
        view. Can be set to always, onClick, iconOnly or never. Default is
        always.
        </li><br>

    <a name="editConfig"></a>
    <li>editConfig<br>
        If this FHEMWEB attribute is set to 1, then you will be able to edit
        the FHEM configuration file (fhem.cfg) in the "Edit files" section.
        After saving this file a rereadcfg is executed automatically, which has
        a lot of side effects.<br>
        </li><br>

    <a name="editFileList"></a>
    <li>editFileList<br>
        Specify the list of Files shown in "Edit Files" section. It is a
        newline separated list of triples, the first is the Title, the next is
        the directory to search for, the third the regular expression. Default
        is:
        <ul>
        <code>
          Own modules and helper files:$MW_dir:^(.*sh|[0-9][0-9].*Util.*pm|.*cfg|.*holiday|myUtilsTemplate.pm|.*layout)$<br>
          Gplot files:$FW_gplotdir:^.*gplot$<br>
          Styles:$FW_cssdir:^.*(css|svg)$<br>
        </code>
        </ul>
        NOTE: The directory spec is not flexible: all .js/.css/_defs.svg files
        come from www/pgm2 ($FW_cssdir), .gplot files from $FW_gplotdir
        (www/gplot), everything else from $MW_dir (FHEM).
        </li><br>

    <a name="endPlotNow"></a>
    <li>endPlotNow<br>
        If this FHEMWEB attribute is set to 1, then day and hour plots will
        end at current time. Else the whole day, the 6 hour period starting at
        0, 6, 12 or 18 hour or the whole hour will be shown. This attribute
        is not used if the SVG has the attribute startDate defined.<br>
        </li><br>

    <a name="endPlotToday"></a>
    <li>endPlotToday<br>
        If this FHEMWEB attribute is set to 1, then week and month plots will
        end today. Else the current week or the current month will be shown.
        <br>
        </li><br>

    <a name="fwcompress"></a>
    <li>fwcompress<br>
        Enable compressing the HTML data (default is 1, i.e. yes, use 0 to switch it off).
        </li>
        <br>

    <a name="hiddengroup"></a>
    <li>hiddengroup<br>
        Comma separated list of groups to "hide", i.e. not to show in any room
        of this FHEMWEB instance.<br>
        Example:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li>
        <br>

    <a name="hiddengroupRegexp"></a>
    <li>hiddengroupRegexp<br>
        One regexp for the same purpose as hiddengroup.
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

    <a name="hiddenroomRegexp"></a>
    <li>hiddenroomRegexp<br>
        One regexp for the same purpose as hiddenroom. Example:
        <ul>
          attr WEB hiddenroomRegexp .*config
        </ul>
        Note: the special values input, detail and save cannot be specified
        with hiddenroomRegexp.
        </li>
        <br>


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

    <a name="icon"></a>
    <li>icon<br>
        Set the icon for a device in the room overview. There is an
        icon-chooser in FHEMWEB to ease this task.  Setting icons for the room
        itself is indirect: there must exist an icon with the name
        ico<ROOMNAME>.png in the iconPath.
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

    <a name="JavaScripts"></a>
    <li>JavaScripts<br>
       Space separated list of JavaScript files to be included. The filenames
       are relative to the www directory.  For each file an additional
       user-settable FHEMWEB attribute will be created, to pass parameters to
       the script. The name of this additional attribute gets the Param
       suffix,  directory and the fhem_ prefix will be deleted. Example:
       <ul><code>
         attr WEB JavaScripts codemirror/fhem_codemirror.js<br>
         attr WEB codemirrorParam { "theme":"blackboard", "lineNumbers":true }
       </code></ul>
       </li><br>

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
        need some help from the definition in the .gplot file: the filter used
        there (second parameter if the source is FileLog) must either contain
        only the deviceName or have the form deviceName.event or deviceName.*.
        This is always the case when using the <a href="#plotEditor">Plot
        editor</a>. The SVG will be reloaded for <b>any</b> event triggered by
        this deviceName. Default is off.
        </li>
        <br>


    <a name="mainInputLength"></a>
    <li>mainInputLength<br>
        length of the maininput text widget in characters (decimal number).
        </li>
        <br>

    <a name="menuEntries"></a>
    <li>menuEntries<br>
        Comma separated list of name,html-link pairs to display in the
        left-side list.  Example:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries
                AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li>
        <br>


    <a name="nameDisplay"></a>
    <li>nameDisplay<br>
        The argument is perl code, which is executed for each single device in
        the room to determine the name displayed. $DEVICE is the name of the
        current device, and $ALIAS is the value of the alias attribute or the
        name of the device, if no alias is set.  E.g. you can add a a global
        userattr named alias_hu for the Hungarian translation, and specify
        nameDisplay for the hungarian FHEMWEB instance as
        <ul>
          AttrVal($DEVICE, "alias_hu", $ALIAS)
        </ul>
        </li>
        <br>

    <a name="nrAxis"></a>
    <li>nrAxis<br>
        the number of axis for which space should be reserved  on the left and
        right sides of a plot and optionaly how many axes should realy be used
        on each side, separated by comma: left,right[,useLeft,useRight].  You
        can set individual numbers by setting the nrAxis of the SVG. Default is
        1,1.
        </li><br>

    <a name="ploteditor"></a>
    <li>ploteditor<br>
        Configures if the <a href="#plotEditor">Plot editor</a> should be shown
        in the SVG detail view.
        Can be set to always, onClick or never. Default is always.
        </li><br>

    <a name="plotEmbed"></a>
    <li>plotEmbed 0<br>
        SVG plots are rendered as part of &lt;embed&gt; tags, as in the past
        this was the only way to display SVG, and it allows to render them in
        parallel, see plotfork.
        Setting plotEmbed to 0 will render SVG in-place, but as a side-effect
        makes the plotfork attribute meaningless.<br>
    </li><br>

    <a name="plotfork"></a>
    <li>plotfork [&lt;&Delta;p&gt;]<br>
        If set to a nonzero value, run part of the processing (e.g. <a
        href="#SVG">SVG</a> plot generation or <a href="#RSS">RSS</a> feeds) in
        parallel processes.  Actually, child processes are forked whose
        priorities are the FHEM process' priority plus &Delta;p. 
        Higher values mean lower priority. e.g. use &Delta;p= 10 to renice the
        child processes and provide more CPU power to the main FHEM process.
        &Delta;p is optional and defaults to 0.<br>
        Note: do not use it
        on Windows and on systems with small memory footprint.
    </li><br>

    <a name="plotmode"></a>
    <li>plotmode<br>
        Specifies how to generate the plots:
        <ul>
          <li>SVG<br>
              The plots are created with the <a href="#SVG">SVG</a> module.
              This is the default.</li>
          <li>gnuplot-scroll<br>
              The plots are created with the gnuplot program. The gnuplot 
              output terminal PNG is assumed. Scrolling to historical values 
              is also possible, just like with SVG.</li>
          <li>gnuplot-scroll-svg<br>
              Like gnuplot-scroll, but the output terminal SVG is assumed.</li>
        </ul>
        </li><br>

    <a name="plotsize"></a>
    <li>plotsize<br>
        the default size of the plot, in pixels, separated by comma:
        width,height. You can set individual sizes by setting the plotsize of
        the SVG. Default is 800,160 for desktop, and 480,160 for
        smallscreen.
        </li><br>

    <a name="plotWeekStartDay"></a>
    <li>plotWeekStartDay<br>
        Start the week-zoom of the SVG plots with this day.
        0 is Sunday, 1 is Monday, etc.<br>
    </li><br>

    <a name="redirectCmds"></a>
    <li>redirectCmds<br>
        Clear the browser URL window after issuing the command by redirecting
        the browser, as a reload for the same site might have unintended
        side-effects. Default is 1 (enabled). Disable it by setting this
        attribute to 0 if you want to study the command syntax, in order to
        communicate with FHEMWEB.
        </li>
        <br>

    <a name="refresh"></a>
    <li>refresh<br>
        If set, a http-equiv="refresh" entry will be genererated with the given
        argument (i.e. the browser will reload the page after the given
        seconds).
        </li><br>

    <a name="reverseLogs"></a>
    <li>reverseLogs<br>
        Display the lines from the logfile in a reversed order, newest on the
        top, so that you dont have to scroll down to look at the latest entries.
        Note: enabling this attribute will prevent FHEMWEB from streaming
        logfiles, resulting in a considerably increased memory consumption
        (about 6 times the size of the file on the disk).
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

    <a name="smallscreenCommands"></a>
    <li>smallscreenCommands<br>
       If set to 1, commands, slider and dropdown menues will appear in
       smallscreen landscape mode.
       </li><br>

    <a name="sortby"></a>
    <li>sortby<br>
        Take the value of this attribute when sorting the devices in the room
        overview instead of the alias, or if that is missing the devicename
        itself. If the sortby value is enclosed in {} than it is evaluated as a
        perl expression. $NAME is set to the device name.
        </li>
        <br>

    <a name="showUsedFiles"></a>
    <li>showUsedFiles<br>
        In the Edit files section, show only the used files.
        Note: currently this is only working for the "Gplot files" section.
        </li>
        <br>

    <a name="sortRooms"></a>
    <li>sortRooms<br>
        Space separated list of rooms to override the default sort order of the
        room links.  As the rooms in this attribute are actually regexps, space
        in the roomname has to be specified as dot (.).
        Example:<br>
        attr WEB sortRooms DG OG EG Keller
        </li>
        <br>
        
    <li>sslVersion<br>
       See the global attribute sslVersion.
       </li><br>

    <a name="styleData"></a>
    <li>styleData<br>
      data-storage used by dynamic styles like f18
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

    <a name="SVGcache"></a>
    <li>SVGcache<br>
        if set, cache plots which won't change any more (the end-date is prior
        to the current timestamp). The files are written to the www/SVGcache
        directory. Default is off.<br>
        See also the clearSvgCache command for clearing the cache.
        </li><br>

    <a name="title"></a>
    <li>title<br>
        Sets the title of the page. If enclosed in {} the content is evaluated.
    </li><br>

    <a name="viewport"></a>
    <li>viewport<br>
       Sets the &quot;viewport&quot; attribute in the HTML header. This can for
       example be used to force the width of the page or disable zooming.<br>
       Example: attr WEB viewport
       width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no
    </li><br>

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
        by a comma separated list), then a different widget will be displayed.
        See also the widgetOverride attribute below. Examples:
        <ul>
          define d1 dummy<br>
          attr d1 webCmd state<br>
          attr d1 readingList state<br>
          attr d1 setList state:on,off<br><br>
       
          define d2 dummy<br>
          attr d2 webCmd state<br>
          attr d2 readingList state<br>
          attr d2 setList state:slider,0,1,10<br><br>
       
          define d3 dummy<br>
          attr d3 webCmd state<br>
          attr d3 readingList state<br>
          attr d3 setList state:time<br>
        </ul>
        If the command is state, then the value will be used as a command.<br>
        Note: this is an attribute for the displayed device, not for the FHEMWEB
        instance.
        </li>
        <br>

    <a name="webCmdLabel"></a>
    <li>webCmdLabel<br>
        Colon separated list of labels, used to prefix each webCmd. The number
        of labels must exactly match the number of webCmds. To implement
        multiple rows, insert a return character after the text and before the
        colon.</li></br>

    <a name="webname"></a>
    <li>webname<br>
        Path after the http://hostname:port/ specification. Defaults to fhem,
        i.e the default http address is http://localhost:8083/fhem
        </li><br>

    <a name="widgetOverride"></a>
    <li>widgetOverride<br>
        Space separated list of name:modifier pairs, to override the widget
        for a set/get/attribute specified by the module author.
        Following is the list of known modifiers:
        <ul>
        <!-- INSERT_DOC_FROM: www/pgm2/fhemweb.*.js -->
        </ul>
        </li>
        <br>
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
  <b>Attribute</b>
  <ul>
    <a name="addHtmlTitle"></a>
    <li>addHtmlTitle<br>
      Falls der Wert 0 ist, wird bei den set/get/attr Parametern in der
      DetailAnsicht der Ger&auml;te kein title Attribut gesetzt. Das is bei
      manchen Screenreadern erforderlich. Die Voreinstellung ist 1.
      </li><br>

    <li><a href="#addStateEvent">addStateEvent</a></li><br>

    <li>alias_&lt;RoomName&gt;<br>
        Falls man das Attribut alias_&lt;RoomName&gt; definiert, und dieses
        Attribut f&uuml;r ein Ger&auml;t setzt, dann wird dieser Wert bei
        Anzeige von &lt;RoomName&gt; verwendet.<br>
        Achtung: man kann im userattr auch alias_.* verwenden um alle
        m&ouml;glichen R&auml;ume abzudecken, in diesem Fall wird aber die
        Attributauswahl in der Detailansicht f&uuml;r alias_.* nicht
        funktionieren.
        </li><br>

    <li><a href="#allowfrom">allowfrom</a>
        </li><br>

    <li>allowedCommands, basicAuth, basicAuthMsg<br>
        Diese Attribute m&uuml;ssen ab sofort bei dem passenden <a
        href="#allowed">allowed</a> Ger&auml;t angelegt werden, und sind
        f&uuml;r eine FHEMWEB Instanz unerw&uuml;nscht.
    </li><br>

     <a name="closeConn"></a>
     <li>closeConn<br>
        Falls gesetzt, wird pro TCP Verbindung nur ein HTTP Request
        durchgef&uuml;hrt. F&uuml;r iOS9 WebApp startups scheint es zu helfen.
        </li><br>

    <a name="cmdIcon"></a>
    <li>cmdIcon<br>
        Leerzeichen getrennte Auflistung von cmd:iconName Paaren.
        Falls gesetzt, wird das webCmd text durch den icon gesetzt.
        Am einfachsten setzt man cmdIcon indem man "Extend devStateIcon" im
        Detail-Ansicht verwendet, und den Wert nach cmdIcon kopiert.<br>
        Beispiel:<ul>
        attr lamp cmdIcon on:control_centr_arrow_up off:control_centr_arrow_down
        </ul>
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
       
        Anmerkungen: einige Elemente, wie SVG Plots und readingsGroup
        k&ouml;nnen nur dann Teil einer Spalte sein wenn sie in <a
        href="#group">group</a> stehen. Dieses Attribut kann man zum sortieren
        der Gruppen auch dann verwenden, wenn man nur eine Spalte hat.
        Leerzeichen im Raum- und Gruppennamen sind f&uuml;r dieses Attribut als
        %20 zu schreiben. Raum- und Gruppenspezifikation ist jeweils ein
        %regul&auml;rer Ausdruck.
        </li><br>

    <a name="confirmDelete"></a>
    <li>confirmDelete<br>
        L&ouml;schaktionen weden mit einem Dialog best&auml;tigt.
        Falls dieses Attribut auf 0 gesetzt ist, entf&auml;llt das.
        </li>
        <br> 

    <a name="confirmJSError"></a>
    <li>confirmJSError<br>
        JavaScript Fehler werden per Voreinstellung in einem Dialog gemeldet.
        Durch setzen dieses Attributes auf 0 werden solche Fehler nicht 
        gemeldet.
        </li>
        <br> 

    <a name="CORS"></a>
    <li>CORS<br>
        Wenn auf 1 gestellt, wird FHEMWEB einen "Cross origin resource sharing"
        Header bereitstellen, n&auml;heres siehe Wikipedia.
        </li><br>

     <a name="csrfToken"></a>
     <li>csrfToken<br>
        Falls gesetzt, wird der Wert des Attributes als fwcsrf Parameter bei
        jedem &uuml;ber FHEMWEB abgesetzten Kommando verlangt, es dient zum
        Schutz von Cross Site Resource Forgery Angriffen.
        Falls der Wert random ist, dann wird ein Zufallswert beim jeden FHEMWEB
        Start neu generiert, falls er none ist, dann wird kein Parameter
        verlangt. Default ist random f&uuml;r featurelevel 5.8 und
        gr&ouml;&szlig;er, und none f&uuml;r featurelevel kleiner 5.8
        </li><br>

    <a name="csrfTokenHTTPHeader"></a>
    <li>csrfTokenHTTPHeader<br>
       Falls gesetzt (Voreinstellung), FHEMWEB sendet im HTTP Header den
       csrfToken als X-FHEM-csrfToken, das wird von manchen FHEM-Clients
       benutzt. Mit 0 kann man das abstellen, um Sites wie shodan.io die
       Erkennung von FHEM zu erschweren.</li><br>

     <a name="CssFiles"></a>
     <li>CssFiles<br>
        Leerzeichen getrennte Liste von .css Dateien, die geladen werden.
        Die Dateinamen sind relativ zum www Verzeichnis anzugeben. Beispiel:
        <ul><code>
          attr WEB CssFiles pgm2/mystyle.css
        </code></ul>
        </li><br>

    <a name="defaultRoom"></a>
    <li>defaultRoom<br>
        Zeigt den angegebenen Raum an falls kein Raum explizit ausgew&auml;hlt
        wurde.  Achtung: falls gesetzt, wird motd nicht mehr angezeigt.
        Beispiel:<br>
        attr WEB defaultRoom Zentrale
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
          attr Fax devStateIcon on:control_building_empty@red
          off:control_building_filled:278727
        </ul>
        Falls cmd noFhemwebLink ist, dann wird kein HTML-Link generiert, d.h.
        es passiert nichts, wenn man auf das Icon/Text klickt.
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

    <li>deviceOverview<br>
        Gibt an ob die Darstellung aus der Raum-Ansicht (Zeile mit
        Ger&uuml;teicon, Stateicon und webCmds/cmdIcons) auch in der
        Detail-Ansicht angezeigt werden soll. Kann auf always, onClick,
        iconOnly oder never gesetzt werden.  Der Default ist always.
        </li><br>

    <a name="editConfig"></a>
    <li>editConfig<br>
        Falls dieses FHEMWEB Attribut (auf 1) gesetzt ist, dann kann man die
        FHEM Konfigurationsdatei in dem "Edit files" Abschnitt bearbeiten. Beim
        Speichern dieser Datei wird automatisch rereadcfg ausgefuehrt, was
        diverse Nebeneffekte hat.<br>
        </li><br>

    <a name="editFileList"></a>
    <li>editFileList<br>
        Definiert die Liste der angezeigten Dateien in der "Edit Files" Abschnitt.
        Es ist eine Newline getrennte Liste von Tripeln bestehend aus Titel,
        Verzeichnis f&uuml;r die Suche, und Regexp. Die Voreinstellung ist:
        <ul>
        <code>
          Own modules and helper files:$MW_dir:^(.*sh|[0-9][0-9].*Util.*pm|.*cfg|.*holiday|myUtilsTemplate.pm|.*layout)$<br>
          Gplot files:$FW_gplotdir:^.*gplot$<br>
          Styles:$FW_cssdir:^.*(css|svg)$<br>
        </code>
        </ul>
        Achtung: die Verzeichnis Angabe ist nicht flexibel: alle
        .js/.css/_defs.svg Dateien sind in www/pgm2 ($FW_cssdir), .gplot
        Dateien in $FW_gplotdir (www/gplot), alles andere in $MW_dir (FHEM).
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

    <a name="endPlotToday"></a>
    <li>endPlotToday<br>
        Wird dieses FHEMWEB Attribut gesetzt, so enden Wochen- bzw. Monatsplots
        am aktuellen Tag, sonst wird die aktuelle Woche/Monat angezeigt.
        </li><br>

    <a name="fwcompress"></a>
    <li>fwcompress<br>
        Aktiviert die HTML Datenkompression (Standard ist 1, also ja, 0 stellt
        die Kompression aus).
        </li><br>

    <a name="hiddengroup"></a>
    <li>hiddengroup<br>
        Wie hiddenroom (siehe unten), jedoch auf Ger&auml;tegruppen bezogen.
        <br>
        Beispiel:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li><br>

    <a name="hiddengroupRegexp"></a>
    <li>hiddengroupRegexp<br>
        Ein regul&auml;rer Ausdruck, um Gruppen zu verstecken.
        </li>
        <br>

    <a name="hiddenroom"></a>
    <li>hiddenroom<br>
       Eine Komma getrennte Liste, um R&auml;ume zu verstecken, d.h. nicht 
       anzuzeigen. Besondere Werte sind input, detail und save. In diesem
       Fall werden diverse Eingabefelder ausgeblendent. Durch direktes Aufrufen
       der URL sind diese R&auml;ume weiterhin erreichbar!<br>
       Ebenso k&ouml;nnen Eintr&auml;ge in den Logfile/Commandref/etc Block
       versteckt werden.  </li><br>

    <a name="hiddenroomRegexp"></a>
    <li>hiddenroomRegexp<br>
        Ein regul&auml;rer Ausdruck, um R&auml;ume zu verstecken. Beispiel:
        <ul>
          attr WEB hiddenroomRegexp .*config
        </ul>
        Achtung: die besonderen Werte input, detail und save m&uuml;ssen mit
        hiddenroom spezifiziert werden.
        </li>
        <br>

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
        openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout
        server-key.pem
        </ul>

      <br>
    </li>

    <a name="icon"></a>
    <li>icon<br>
        Damit definiert man ein Icon f&uuml;r die einzelnen Ger&auml;te in der
        Raum&uuml;bersicht. Es gibt einen passenden Link in der Detailansicht
        um das zu vereinfachen. Um ein Bild f&uuml;r die R&auml;ume selbst zu
        definieren muss ein Icon mit dem Namen ico&lt;Raumname&gt;.png im
        iconPath existieren (oder man verwendet roomIcons, s.u.)
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

    <a name="JavaScripts"></a>
    <li>JavaScripts<br>
       Leerzeichen getrennte Liste von JavaScript Dateien, die geladen werden.
       Die Dateinamen sind relativ zum www Verzeichnis anzugeben. F&uuml;r
       jede Datei wird ein zus&auml;tzliches Attribut angelegt, damit der
       Benutzer dem Skript Parameter weiterreichen kann. Bei diesem
       Attributnamen werden Verzeichnisname und fhem_ Pr&auml;fix entfernt
       und Param als Suffix hinzugef&uuml;gt. Beispiel:
       <ul><code>
         attr WEB JavaScripts codemirror/fhem_codemirror.js<br>
         attr WEB codemirrorParam { "theme":"blackboard", "lineNumbers":true }
       </code></ul>
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
        &auml;ndert. Funktioniert nur, falls die dazugeh&ouml;rige Definition
        der Quelle in der .gplot Datei folgenden Form hat: deviceName.Event
        bzw. deviceName.*. Wenn man den <a href="#plotEditor">Plot Editor</a>
        benutzt, ist das &uuml;brigens immer der Fall. Die SVG Datei wird bei
        <b>jedem</b> ausl&ouml;senden Event dieses Ger&auml;tes neu geladen.
        Die Voreinstellung ist aus.
        </li><br>

    <a name="mainInputLength"></a>
    <li>mainInputLength<br>
        L&auml;nge des maininput Eingabefeldes (Anzahl der Buchstaben,
        Ganzzahl).
        </li> <br>

    <a name="menuEntries"></a>
    <li>menuEntries<br>
        Komma getrennte Liste; diese Links werden im linken Men&uuml; angezeigt.
        Beispiel:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries
                      AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li><br>

    <a name="nameDisplay"></a>
    <li>nameDisplay<br>
        Das Argument ist Perl-Code, was f&uuml;r jedes Ger&auml;t in der
        Raum-&Uuml;bersicht ausgef&uuml;hrt wird, um den angezeigten Namen zu
        berechnen. Dabei kann man die Variable $DEVICE f&uuml;r den aktuellen
        Ger&auml;tenamen, und $ALIAS f&uuml;r den aktuellen alias bzw. Name,
        falls alias nicht gesetzt ist, verwenden.  Z.Bsp. f&uuml;r eine FHEMWEB
        Instanz mit ungarischer Anzeige f&uuml;gt man ein global userattr
        alias_hu hinzu, und man setzt nameDisplay f&uuml;r diese FHEMWEB
        Instanz auf dem Wert:
        <ul>
          AttrVal($DEVICE, "alias_hu", $ALIAS)
        </ul>
        </li>
        <br>

    <a name="nrAxis"></a>
    <li>nrAxis<br>
        (bei mehrfach-Y-Achsen im SVG-Plot) Die Darstellung der Y Achsen
        ben&ouml;tigt Platz. Hierdurch geben Sie an wie viele Achsen Sie
        links,rechts [useLeft,useRight] ben&ouml;tigen. Default ist 1,1 (also 1
        Achse links, 1 Achse rechts).
        </li><br>

    <a name="ploteditor"></a>
    <li>ploteditor<br>
        Gibt an ob der <a href="#plotEditor">Plot Editor</a> in der SVG detail
        ansicht angezeigt werden soll.  Kann auf always, onClick oder never
        gesetzt werden. Der Default ist always.
        </li><br>

    <a name="plotEmbed"></a>
    <li>plotEmbed 0<br>
        SVG Grafiken werden als Teil der &lt;embed&gt; Tags dargestellt, da
        fr&uuml;her das der einzige Weg war SVG darzustellen, weiterhin
        erlaubt es das parallele Berechnen via plotfork (s.o.)
        Falls plotEmbed auf 0 gesetzt wird, dann werden die SVG Grafiken als
        Teil der HTML-Seite generiert, was leider das plotfork Attribut
        wirkungslos macht.
    </li><br>

    <a name="plotfork"></a>
    <li>plotfork<br>
        Normalerweise wird die Ploterstellung im Hauptprozess ausgef&uuml;hrt,
        FHEM wird w&auml;rend dieser Zeit nicht auf andere Ereignisse
        reagieren.
        Falls dieses Attribut auf einen nicht 0 Wert gesetzt ist, dann wird die
        Berechnung in weitere Prozesse ausgelagert. Das kann die Berechnung auf
        Rechnern mit mehreren Prozessoren beschleunigen, allerdings kann es auf
        Rechnern mit wenig Speicher (z.Bsp. FRITZ!Box 7390) zum automatischen
        Abschuss des FHEM Prozesses durch das OS f&uuml;hren.
        </li><br>

    <a name="plotmode"></a>
    <li>plotmode<br>
        Spezifiziert, wie Plots erzeugt werden sollen:
        <ul>
          <li>SVG<br>
          Die Plots werden mit Hilfe des <a href="#SVG">SVG</a> Moduls als SVG
          Grafik gerendert. Das ist die Standardeinstellung.</li>

          <li>gnuplot-scroll<br>
          Die plots werden mit dem Programm gnuplot erstellt. Das output
          terminal ist PNG. Der einfache Zugriff auf historische Daten
          ist m&ouml;glich (analog SVG).
          </li>

          <li>gnuplot-scroll-svg<br>
          Wie gnuplot-scroll, aber als output terminal wird SVG angenommen.
          </li>
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

    <a name="plotWeekStartDay"></a>
    <li>plotWeekStartDay<br>
        Starte das Plot in der Wochen-Ansicht mit diesem Tag.
        0 ist Sonntag, 1 ist Montag, usw.
    </li><br>

    <a name="redirectCmds"></a>
    <li>redirectCmds<br>
        Damit wird das URL Eingabefeld des Browser nach einem Befehl geleert.
        Standard ist eingeschaltet (1), ausschalten kann man es durch
        setzen des Attributs auf 0, z.Bsp. um den Syntax der Kommunikation mit
        FHEMWEB zu untersuchen.
        </li><br>

    <a name="refresh"></a>
    <li>refresh<br>
        Damit erzeugen Sie auf den ausgegebenen Webseiten einen automatischen
        Refresh, z.B. nach 5 Sekunden.
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

    <a name="roomIcons"></a>
    <li>roomIcons<br>
        Leerzeichen getrennte Liste von room:icon Zuordnungen
        Der erste Teil wird als regexp interpretiert, daher muss ein
        Leerzeichen als Punkt geschrieben werden. Beispiel:<br>
          attr WEB roomIcons Anlagen.EDV:icoEverything
        </li><br>

    <a name="sortby"></a>
    <li>sortby<br>
        Der Wert dieses Attributs wird zum sortieren von Ger&auml;ten in
        R&auml;umen verwendet, sonst w&auml;re es der Alias oder, wenn keiner
        da ist, der Ger&auml;tename selbst. Falls der Wert des sortby
        Attributes in {} eingeschlossen ist, dann wird er als ein perl Ausdruck
        evaluiert. $NAME wird auf dem Ger&auml;tenamen gesetzt.
        </li><br>

    <a name="showUsedFiles"></a>
    <li>showUsedFiles<br>
        Zeige nur die verwendeten Dateien in der "Edit files" Abschnitt.
        Achtung: aktuell ist das nur f&uuml;r den "Gplot files" Abschnitt
        implementiert.
        </li>
        <br>

    <a name="sortRooms"></a>
    <li>sortRooms<br>
        Durch Leerzeichen getrennte Liste von R&auml;umen, um deren Reihenfolge
        zu definieren.
        Da die R&auml;ume in diesem Attribut als Regexp interpretiert werden,
        sind Leerzeichen im Raumnamen als Punkt (.) zu hinterlegen.
        Beispiel:<br>
          attr WEB sortRooms DG OG EG Keller
        </li><br>

    <a name="smallscreenCommands"></a>
    <li>smallscreenCommands<br>
      Falls auf 1 gesetzt werden Kommandos, Slider und Dropdown Men&uuml;s im
      Smallscreen Landscape Modus angezeigt.
      </li><br>

    <li>sslVersion<br>
      Siehe das global Attribut sslVersion.
      </li><br>

    <a name="styleData"></a>
    <li>styleData<br>
      wird von dynamischen styles wie f18 werwendet
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

    <a name="SVGcache"></a>
    <li>SVGcache<br>
        Plots die sich nicht mehr &auml;ndern, werden im SVGCache Verzeichnis
        (www/SVGcache) gespeichert, um die erneute, rechenintensive
        Berechnung der Grafiken zu vermeiden. Default ist 0, d.h. aus.<br>
        Siehe den clearSvgCache Befehl um diese Daten zu l&ouml;schen.
        </li><br>

    <a name="title"></a>
    <li>title<br>
       Setzt den Titel der Seite. Falls in {} eingeschlossen, dann wird es
       als Perl Ausdruck evaluiert.
    </li><br>

    <a name="viewport"></a>
    <li>viewport<br>
       Setzt das &quot;viewport&quot; Attribut im HTML Header. Das kann benutzt
       werden um z.B. die Breite fest vorzugeben oder Zoomen zu verhindern.<br>
       Beispiel: attr WEB viewport
       width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no
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
        wird ein anderes Widget angezeigt. Siehe auch widgetOverride.<br>
        Wenn der Befehl state ist, wird der Wert als Kommando interpretiert.<br>
        Beispiele:
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

    <a name="webCmdLabel"></a>
    <li>webCmdLabel<br>
        Durch Doppelpunkte getrennte Auflistung von Texten, die vor dem
        jeweiligen webCmd angezeigt werden. Der Anzahl der Texte muss exakt den
        Anzahl der webCmds entsprechen. Um mehrzeilige Anzeige zu realisieren,
        kann ein Return nach dem Text und vor dem Doppelpunkt eingefuehrt
        werden.</li><br>

    <a name="webname"></a>
    <li>webname<br>
        Der Pfad nach http://hostname:port/ . Standard ist fhem,
        so ist die Standard HTTP Adresse http://localhost:8083/fhem
        </li><br>

    <a name="widgetOverride"></a>
    <li>widgetOverride<br>
        Leerzeichen separierte Liste von Name/Modifier Paaren, mit dem man den
        vom Modulautor f&uuml;r einen bestimmten Parameter (Set/Get/Attribut)
        vorgesehene Widgets &auml;ndern kann.  Folgendes ist die Liste der
        bekannten Modifier:
        <ul>
        <!-- INSERT_DOC_FROM: www/pgm2/fhemweb.*.js -->
        </ul></li>

    </ul>
  </ul>

=end html_DE

=cut
