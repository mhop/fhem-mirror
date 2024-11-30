##############################################
# $Id$
package main;

use strict;
use warnings;
use TcpServerUtils;
use HttpUtils;
use Blocking;

#########################
# Forward declaration
sub FW_IconURL($);
sub FW_addContent(;$);
sub FW_addToWritebuffer($$@);
sub FW_alias($$);
sub FW_answerCall($);
sub FW_confFiles($);
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
sub FW_textfieldv($$$$;$);
sub FW_updateHashes();
sub FW_visibleDevices(;$);
sub FW_widgetOverride($$;$);
sub FW_Read($$);

use vars qw($FW_dir);     # base directory for web server
use vars qw($FW_icondir); # icon base directory
use vars qw($FW_cssdir);  # css directory
use vars qw($FW_gplotdir);# gplot directory
use vars qw($FW_confdir); # conf dir
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
use vars qw($FW_RETTYPE); # image/png or the like. Note: also as my below!
use vars qw($FW_wname);   # Web instance
use vars qw($FW_subdir);  # Sub-path in URL, used by FLOORPLAN/weblink
use vars qw(%FW_pos);     # scroll position
use vars qw($FW_cname);   # Current connection name
use vars qw($FW_chash);   # client fhem hash
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
use vars qw($FW_addJs);     # Only for helper like AttrTemplate
use vars qw(%FW_id2inform);

$FW_formmethod = "post";

my %FW_use;
my $FW_activateInform = 0;
my $FW_lastWebName = "";  # Name of last FHEMWEB instance, for caching
my $FW_lastHashUpdate = 0;
my $FW_httpRetCode = "";
my %FW_csrfTokenCache;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my $FW_data;       # Filecontent from browser when editing a file
my %FW_icons;      # List of icons
my @FW_iconDirs;   # Directory search order for icons
my $FW_RETTYPE;    # image/png or the like: Note: also as use vars above!
my %FW_rooms;      # hash of all rooms
my %FW_extraRooms; # hash of extra rooms
my @FW_roomsArr;   # ordered list of rooms
my %FW_groups;     # hash of all groups
my %FW_types;      # device types, for sorting
my %FW_hiddengroup;# hash of hidden groups
my $FW_inform;
my $FW_XHR;        # Data only answer, no HTML
my $FW_id="";      # id of current page
my $FW_jsonp;      # jasonp answer (sending function calls to the client)
my $FW_headerlines; #
my $FW_encoding="UTF-8";
my $FW_styleStamp=time();
my %FW_svgData;
my $FW_encodedByPlugin; # unicodeEncoding: data is encoded by plugin
my $FW_needIsDay;


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
  $hash->{CanAuthenticate} = 1;
  no warnings 'qw';
  my @attrList = qw(
    CORS:0,1
    HTTPS:1,0
    CssFiles
    Css:textField-long
    JavaScripts
    SVGcache:1,0
    addHtmlTitle:1,0
    addStateEvent
    csrfToken
    csrfTokenHTTPHeader:0,1
    alarmTimeout
    allowedHttpMethods
    allowfrom
    closeConn:1,0
    column
    confirmDelete:0,1
    confirmJSError:0,1
    defaultRoom
    detailLinks
    deviceOverview:always,iconOnly,onClick,never
    editConfig:1,0
    editFileList:textField-long
    endPlotNow:1,0
    endPlotNowByHour:1,0
    endPlotToday:1,0
    extraRooms:textField-long
    forbiddenroom
    fwcompress:0,1
    hiddengroup
    hiddengroupRegexp
    hiddenroom
    hiddenroomRegexp
    htmlInEventMonitor:1,0
    httpHeader
    iconPath
    jsLog:1,0
    longpoll:0,1,websocket
    longpollSVG:1,0
    logDevice
    logFormat
    menuEntries
    mainInputLength
    nameDisplay
    nrAxis
    ploteditor:always,onClick,never
    plotfork:1,0
    plotmode:gnuplot-scroll,gnuplot-scroll-svg,SVG
    plotEmbed:2,1,0
    plotsize
    plotWeekStartDay:0,1,2,3,4,5,6
    redirectCmds:0,1
    redirectTo
    refresh
    rescueDialog:1,0
    reverseLogs:0,1
    roomIcons:textField-long
    showUsedFiles:0,1
    sortRooms
    sslVersion
    sslCertPrefix
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
  map { addToAttrList($_, "FHEMWEB") } (
    "cmdIcon",
    "devStateIcon:textField-long",
    "devStateStyle",
    "icon",
    "sortby",
    "webCmd",
    "webCmdLabel:textField-long",
    "widgetOverride"
  );

  $FW_confdir  = "$attr{global}{modpath}/conf";
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

  my %optMod = (
    zlib   => { mod=>"Compress::Zlib", txt=>"compressed HTTP transfer" },
    sha    => { mod=>"Digest::SHA",    txt=>"longpoll via websocket" },
    base64 => { mod=>"MIME::Base64",   txt=>"parallel SVG computing" }
  );
  foreach my $mod (keys %optMod) {
    eval "require $optMod{$mod}{mod}";
    if($@) {
      Log 4, $@;
      Log 3, "FHEMWEB: Can't load $optMod{$mod}{mod}, ".
             "$optMod{$mod}{txt} is not available";
    } else {
      $FW_use{$mod} = 1;
    }
  }

  $cmds{show} = {
    Fn=>"FW_show", ClientFilter=>"FHEMWEB",
    Hlp=>"<devspec>, show temporary room with devices from <devspec>"
  };

}

#####################################
sub
FW_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB [IPV6:]<tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/);

  FW_Undef($hash, undef) if($hash->{OLDDEF}); # modify

  RemoveInternalTimer(0, "FW_closeInactiveClients");
  InternalTimer(time()+60, "FW_closeInactiveClients", 0, 0);


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
  $hash->{BYTES_READ} = 0;
  $hash->{BYTES_WRITTEN} = 0;

  return $ret;
}

#####################################
sub
FW_Undef($$)
{
  my ($hash, $arg) = @_;
  my $ret = TcpServer_Close($hash, 0, !$hash->{inform});
  if($hash->{inform}) {
    delete $FW_id2inform{$hash->{FW_ID}} if($hash->{FW_ID});
    %FW_visibleDeviceHash = FW_visibleDevices();
    delete($logInform{$hash->{NAME}});
  }
  delete $FW_svgData{$hash->{NAME}};
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

  if(!$reread) {
    # Data from HTTP Client
    my $buf;
    my $ret = sysread($c, $buf, 1024);
    $buf = Encode::decode($hash->{encoding}, $buf)
                if($unicodeEncoding && $hash->{encoding} && !$hash->{websocket});

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
    my $sh = $defs{$FW_wname};
    $sh->{BYTES_READ} += length($buf);

    $hash->{BUF} .= $buf;
    if($hash->{SSL} && $c->can('pending')) {
      while($c->pending()) {
        sysread($c, $buf, 1024);
        $hash->{BUF} .= $buf;
        $sh->{BYTES_READ} += length($buf);
      }
    }
  }

  if($hash->{websocket}) { # 59713
    # https://tools.ietf.org/html/rfc6455
    my $fin  = (ord(substr($hash->{BUF},0,1)) & 0x80)?1:0;
    my $op   = (ord(substr($hash->{BUF},0,1)) & 0x0F);
    my $mask = (ord(substr($hash->{BUF},1,1)) & 0x80)?1:0;
    my $len  = (ord(substr($hash->{BUF},1,1)) & 0x7F);
    my $i = 2;

    # $op: 0=>Continuation, 1=>Text, 2=>Binary, 8=>Close, 9=>Ping, 10=>Pong
    if($op == 8) {
      # Close, Normal, empty mask. #104718
      TcpServer_WriteBlocking($hash, pack("CCn",0x88,0x2,1000));
      TcpServer_Close($hash, 1, !$hash->{inform});
      return;

    } elsif($op == 9) { # Ping
      return addToWritebuffer($hash, chr(0x8A).chr(0)); # Pong

    }

    if( $len == 126 ) {
      $len = unpack( 'n', substr($hash->{BUF},$i,2) );
      $i += 2;
    } elsif( $len == 127 ) {
      $len = unpack( 'Q>', substr($hash->{BUF},$i,8) );
      $i += 8;
    }

    my @m;
    if($mask) {
      @m = unpack("C*", substr($hash->{BUF},$i,4));
      $i += 4;
    }
    return if(length($hash->{BUF}) < $i+$len);

    my $data = substr($hash->{BUF}, $i, $len);
    if($mask) {
      my $idx = 0;
      $data = pack("C*", map { $_ ^ $m[$idx++ % 4] } unpack("C*", $data));
    }

    $data = Encode::decode('UTF-8', $data) if($unicodeEncoding && $op == 1);

    my $ret = FW_fC($data);
    FW_addToWritebuffer($hash,
                       FW_longpollInfo("JSON", defined($ret) ? $ret : "")."\n");
    $hash->{BUF} = substr($hash->{BUF}, $i+$len);
    FW_Read($hash, 1) if($hash->{BUF});
    return;
  }



  if(!$hash->{HDR}) {
    if(length($hash->{BUF}) > 1000000) {
      Log3 $FW_wname, 2, "Too much header, terminating $hash->{PEER}";
      return TcpServer_Close($hash, 1, !$hash->{inform});
    }
    return if($hash->{BUF} !~ m/^(.*?)(\n\n|\r\n\r\n)(.*)$/s);
    $hash->{HDR} = $1;
    $hash->{BUF} = $3;
    if($hash->{HDR} =~ m/Content-Length:\s*([^\r\n]*)/si) {
      $hash->{CONTENT_LENGTH} = $1;
    }
  }

  Log3 $FW_wname, 5, $hash->{HDR};
  my $POSTdata = "";
  if($hash->{CONTENT_LENGTH}) {
    return if(length($hash->{BUF})<$hash->{CONTENT_LENGTH});
    $POSTdata = substr($hash->{BUF}, 0, $hash->{CONTENT_LENGTH});
    $hash->{BUF} = substr($hash->{BUF}, $hash->{CONTENT_LENGTH});
  }

  @FW_httpheader = split(/[\r\n]+/, $hash->{HDR});
  %FW_httpheader = map {
                         my ($k,$v) = split(/: */, $_, 2);
                         $k = lc($k);          #88205
                         $k =~ s/(\w+)/\u$1/g; #39203
                         $k=>(defined($v) ? $v : 1);
                       } @FW_httpheader;
  if(!$hash->{encoding}) {
    my $ct = $FW_httpheader{"Content-Type"};
    $hash->{encoding} =
        ($ct && $ct =~ m/charset\s*=\s*(\S*)/i ? $1 : $FW_encoding);
  }
  delete($hash->{HDR});

  my @origin = grep /Origin/i, @FW_httpheader;
  $FW_headerlines = (AttrVal($FW_wname, "CORS", 0) ?
              (($#origin<0) ? "": "Access-Control-Allow-".$origin[0]."\r\n").
              "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n".
              "Access-Control-Allow-Headers: Origin, Authorization, Accept\r\n".
              "Access-Control-Allow-Credentials: true\r\n".
              "Access-Control-Max-Age:86400\r\n".
              "Access-Control-Expose-Headers: X-FHEM-csrfToken\r\n": "");
   $FW_headerlines .= "X-FHEM-csrfToken: $defs{$FW_wname}{CSRFTOKEN}\r\n"
        if(defined($defs{$FW_wname}{CSRFTOKEN}) &&
           AttrVal($FW_wname, "csrfTokenHTTPHeader", 1));

   my $hh = AttrVal($FW_wname, "httpHeader", undef);
   $FW_headerlines .= "$hh\r\n" if($hh);

  #########################
  # Return 200 for OPTIONS or 405 for unsupported method
  my ($method, $arg, $httpvers) = split(" ", $FW_httpheader[0], 3)
        if($FW_httpheader[0]);
  $method = "" if(!$method);
  my $ahm = AttrVal($FW_wname, "allowedHttpMethods", "GET|POST");
  if($method !~ m/^($ahm)$/i){
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

  $FW_userAgent = $FW_httpheader{"User-Agent"};
  $FW_userAgent = "" if(!defined($FW_userAgent));

  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
  $FW_CSRF = (defined($defs{$FW_wname}{CSRFTOKEN}) ?
                "&fwcsrf=".$defs{$FW_wname}{CSRFTOKEN} : "");

  if($FW_use{sha} && $method eq 'GET' &&
     $FW_httpheader{Connection} && $FW_httpheader{Connection} =~ /Upgrade/i &&
     $FW_httpheader{Upgrade} && $FW_httpheader{Upgrade} =~ /websocket/i &&
     $FW_httpheader{'Sec-Websocket-Key'}) {

    my $shastr = Digest::SHA::sha1_base64($FW_httpheader{'Sec-Websocket-Key'}.
                                "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

    TcpServer_WriteBlocking($FW_chash,
       "HTTP/1.1 101 Switching Protocols\r\n" .
       "Upgrade: websocket\r\n" .
       "Connection: Upgrade\r\n" .
       "Sec-WebSocket-Accept:$shastr=\r\n".
      $FW_headerlines.
       "\r\n" );
    $FW_chash->{websocket} = 1;
    $FW_chash->{encoding} = 'UTF-8'; # WS specifies its own encoding

    my $me = $FW_chash;
    my ($cmd, $cmddev) = FW_digestCgi($arg);
    if($FW_id) {
      $me->{FW_ID} = $FW_id;
      $me->{canAsyncOutput} = 1;
    }
    FW_initInform($me, 0) if($FW_inform);
    return -1;
  }

  $arg = "" if(!defined($arg));
  Log3 $FW_wname, 4, "$name $method $arg; BUFLEN:".length($hash->{BUF});
  my $pf = AttrVal($FW_wname, "plotfork", undef);
  $pf = 1 if(!defined($pf) &&
              AttrVal($FW_wname, "plotEmbed", ($numCPUs>1 ? 2:0)) == 2);
  if($pf) {
    my $p = $data{FWEXT};
    if(grep { $p->{$_}{FORKABLE} && $arg =~ m+^$FW_ME$_+ } keys %{$p}) {
      my $pid = fhemFork();
      if($pid) {                                # success, parent
        use constant PRIO_PROCESS => 0;
        setpriority(PRIO_PROCESS, $pid, getpriority(PRIO_PROCESS,$pid) + $pf)
          if($^O !~ m/Win/);
        TcpServer_Disown( $hash );
        delete($defs{$name});
        delete($attr{$name});
        FW_Read($hash, 1) if($hash->{BUF});
        return;

      } elsif(defined($pid)){                   # child
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
  return if($cacheable == -2); # async op, well be answered later
  FW_finishRead($hash, $cacheable, $arg);

}

sub
FW_finishRead($$$)
{
  my ($hash, $cacheable, $arg) = @_;
  my $name = $hash->{NAME};

  my $compressed = "";
  if($FW_RETTYPE =~ m/(text|xml|json|svg|script)/i &&
     ($FW_httpheader{"Accept-Encoding"} &&
      $FW_httpheader{"Accept-Encoding"} =~ m/gzip/) &&
     $FW_use{zlib}) {
    $FW_RET = Encode::encode($hash->{encoding}, $FW_RET)
        if(!$FW_encodedByPlugin &&
           ($unicodeEncoding ||
           (utf8::is_utf8($FW_RET) && $FW_RET =~ m/[^\x00-\xFF]/)));

    eval { $FW_RET = Compress::Zlib::memGzip($FW_RET); };
    if($@) {
      Log 1, "memGzip: $@"; $FW_RET=""; #Forum #29939
    } else {
      $compressed = "Content-Encoding: gzip\r\n";
    }
  }
  $FW_encodedByPlugin = undef;

  my $length = length($FW_RET);
  my $expires = ($cacheable ?
         "Expires: ".FmtDateTimeRFC1123($hash->{LASTACCESS}+900)."\r\n" :
         "Cache-Control: no-cache, no-store, must-revalidate\r\n");
  FW_log($arg, $length) if(AttrVal($FW_wname, "logDevice", undef));
  Log3 $FW_wname, 4,
        "$FW_wname: $arg / RL:$length / $FW_RETTYPE / $compressed / $expires";
  if( ! FW_addToWritebuffer($hash,
           "HTTP/1.1 $FW_httpRetCode\r\n" .
           "Content-Length: $length\r\n" .
           $expires . $compressed . $FW_headerlines .
           "Content-Type: $FW_RETTYPE\r\n\r\n" .
           $FW_RET, "FW_closeConn", "nolimit", "encoded") ){
    Log3 $name, 4, "Closing connection $name due to full buffer in FW_Read"
      if(!$hash->{isChild});
    FW_closeConn($hash);
    TcpServer_Close($hash, 1, !$hash->{inform});
  }
  $FW_RET="";
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
  # Regexp escaping moved to fhemweb.js (#80390, #128362, #128442 )
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

  if($FW_id && $defs{$FW_wname}{asyncOutput}) {
    my $data = $defs{$FW_wname}{asyncOutput}{$FW_id};
    if($data) {
      FW_addToWritebuffer($me, $data."\n");
      delete $defs{$FW_wname}{asyncOutput}{$FW_id};
    }
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
  my ($hash, $txt, $callback, $nolimit, $encoded) = @_;
  return 0 if(!defined($hash->{FD})); # No success

  $txt = Encode::encode($hash->{encoding}, $txt)
          if($hash->{encoding} && !$encoded && ($unicodeEncoding ||
                            (utf8::is_utf8($txt) && $txt =~ m/[^\x00-\xFF]/)));
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
  $defs{$hash->{SNAME}}{BYTES_WRITTEN} += length($txt);
  return addToWritebuffer($hash, $txt, $callback, $nolimit);
}

sub
FW_AsyncOutput($$;$)
{
  my ($hash, $ret, $directData) = @_;

  return if(!$hash || !$hash->{FW_ID});
  if( $ret =~ m/^<html>(.*)<\/html>$/s ) {
    $ret = $1;

  } else {
    $ret = FW_htmlEscape($ret);
    $ret = "<pre>$ret</pre>" if($ret =~ m/\n/ );
    $ret =~ s/\n/<br>/g;
  }

  my $data = FW_longpollInfo('JSON',
                             "#FHEMWEB:$FW_wname","FW_okDialog('$ret')","");
  $data = $directData if($directData);

  # find the longpoll connection with the same fw_id as the page that was the
  # origin of the get command
  my $fwid = $hash->{FW_ID};
  if(!$fwid) {
    Log3 $hash->{SNAME}, 4, "AsyncOutput from $hash->{NAME} without FW_ID";
    return;
  }
  Log3 $hash->{SNAME}, 4, "AsyncOutput from $hash->{NAME}";
  $hash = $FW_id2inform{$fwid};
  if($hash) {
    FW_addToWritebuffer($hash, $data."\n") if(defined($hash->{FD})); #120181
  } else {
    $defs{$FW_wname}{asyncOutput}{$fwid} = $data;
  }
  return undef;
}

sub
FW_closeConn($)
{
  my ($hash) = @_;
  # Forum #41125, 88470
  if(!$hash->{inform} && !$hash->{BUF} && !defined($hash->{".WRITEBUFFER"})) {
    my $cc = AttrVal($hash->{SNAME}, "closeConn",
                     $FW_userAgent =~ m/(iPhone|iPad|iPod)/);
    if(!$FW_httpheader{Connection} || $cc) {
      TcpServer_Close($hash, 1, !$hash->{inform});
      delete $FW_svgData{$hash->{NAME}};
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
FW_setStylesheet()
{
  $FW_sp = AttrVal($FW_wname, "stylesheetPrefix", "f18");
  $FW_sp = "" if($FW_sp eq "default");
  $FW_sp =~ s/^f11//; # Compatibility, #90983
  $FW_ss = ($FW_sp =~ m/smallscreen/);
  $FW_tp = ($FW_sp =~ m/smallscreen|touchpad/);
  @FW_iconDirs = grep { $_ } split(":", AttrVal($FW_wname, "iconPath",
                              "${FW_sp}:fhemSVG:openautomation:default"));
}

sub
FW_answerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FW_cname};      # cache, else rereadcfg will delete us

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=$FW_encoding";
  $FW_encodedByPlugin = undef;

  $MW_dir = "$attr{global}{modpath}/FHEM";
  FW_setStylesheet();
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
    my $static = ($ext =~ m/(css|js|png|jpg|html|svg)/i || $dir =~ m/^pgm2/);
    my $fname = ($ext ? "$file.$ext" : $file);
    return FW_serveSpecial($file, $ext, $ldir, ($arg =~ m/nocache/) ? 0 : 1)
      if(-r "$ldir/$fname" || $static); # no return for FLOORPLAN
    $arg = "/$dir/$ofile";

  } elsif($arg =~ m/^$FW_ME(.*)/s) {
    $arg = $1; # The stuff behind FW_ME, continue to check for commands/FWEXT

  } elsif($arg =~ m,^/favicon.ico$,) {
    return FW_serveSpecial("favicon", "ico", "$FW_icondir/default", 1);

  } else {
    my $redirectTo = AttrVal($FW_wname, "redirectTo","");
    if($redirectTo) {
      if($redirectTo =~ m/^eventFor:(.*)/ && $arg =~ m/$1/) {
        DoTrigger($FW_wname, $arg);
        FW_finishRead($FW_chash, 0, "");
        return -1;
      }
      Log3 $FW_wname, 1,"$FW_wname: redirecting $arg to $FW_ME/$redirectTo$arg";
      return FW_answerCall("$FW_ME/$redirectTo$arg") 
    }

    Log3 $FW_wname, 4, "$FW_wname: redirecting $arg to $FW_ME";
    FW_redirect($FW_ME);
    FW_closeConn($FW_chash);
    return -1;
  }


  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");
  my ($cmd, $cmddev) = FW_digestCgi($arg);
  if($cmd && $FW_CSRF && $cmd !~ m/style (list|select|eventMonitor)/) {
    my $supplied = defined($FW_webArgs{fwcsrf}) ? $FW_webArgs{fwcsrf} : "";
    my $want = $defs{$FW_wname}{CSRFTOKEN};
    if($supplied ne $want) {
      Log3 $FW_wname, 3, "FHEMWEB $FW_wname CSRF error: $supplied ne $want ".
                         "for client $FW_chash->{NAME} / command $cmd. ".
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
    if($FW_webArgs{asyncCmd}) {
      my $pid = fhemFork();
      if($pid) {                                # success, parent
        TcpServer_Disown( $me );
        delete($defs{$FW_cname});
        delete($attr{$FW_cname});
        FW_Read($me, 1) if($me->{BUF});
        return -2;

      } elsif(defined($pid)){                   # child
        delete $me->{BUF};
        $me->{isChild} = 1;

      }
    }

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
    foreach my $k (reverse sort keys %{$data{FWEXT}}) {
      my $h = $data{FWEXT}{$k};
      next if($arg !~ m/^$k/);
      $FW_contentFunc = $h->{CONTENTFUNC};
      next if($h !~ m/HASH/ || !$h->{FUNC});
      #Returns undef as FW_RETTYPE if it already sent a HTTP header
      $FW_encodedByPlugin = 1;
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
    FW_redirect($tgt);
    return -1;
  }

  if($FW_lastWebName ne $FW_cname || $FW_lastHashUpdate != $lastDefChange) {
    FW_updateHashes();
    $FW_lastWebName = $FW_cname;
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

  my $sd = AttrVal($FW_wname, "styleData", ""); # Avoid flicker in f18
  if($sd && $sd =~ m/"$FW_sp":/s) {
    my $bg;
    $bg = $1 if($FW_room && $sd =~ m/"Room\.$FW_room\.cols.bg": "([^"]*)"/s);
    $bg = $1 if(!defined($bg) && $sd =~ m/"cols.bg": "([^"]*)"/s);

    my $bgImg;
    $bgImg = $1 if($FW_room && $sd =~ m/"Room\.$FW_room\.bgImg": "([^"]*)"/s);
    $bgImg = $1 if(!defined($bgImg) && $sd =~ m/"bgImg": "([^"]*)"/s);

    FW_pO "<style id='style_css'>";
    FW_pO "body { background-color:#$bg; }" if($bg);
    FW_pO "body { background-image:url($FW_ME/images/background/$bgImg); }"
        if($bgImg);
    FW_pO "</style>";
  }

  my $css = AttrVal($FW_wname, "Css", "");
  FW_pO "<style id='fhemweb_css'>$css</style>\n" if($css);

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
  FW_pO $FW_addJs if($FW_addJs);

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
  my $lp = 'longpoll="'.AttrVal($FW_wname,"longpoll",
                 $FW_use{sha} && $FW_userAgent=~m/Chrome/ ? "websocket": 1).'"';
  $FW_id = gettimeofday() if( !$FW_id ); #132013

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

  my $srVal = 0;
     if($cmd =~ m/^style /)    { FW_style($cmd,undef);    }
  elsif($FW_detail)            { FW_doDetail($FW_detail); }
  elsif($FW_room)              { $srVal = FW_showRoom();  }
  elsif(!defined($FW_cmdret) &&
        !$FW_contentFunc) {

    $FW_room = AttrVal($FW_wname, "defaultRoom", '');
    if($FW_room ne '') {
      $srVal = FW_showRoom();

    } else {
      my $motd = AttrVal("global", "motd", "");
      my $gie = $defs{global}{init_errors};
      $gie = "" if(!defined($gie));
      if($motd ne "none" && ($motd || $gie)) {
        FW_addContent("><pre class='motd'>$motd\n$gie</pre></div");
      }
    }
  }
  return $srVal if($srVal);
  FW_pO "</body></html>";
  return 0;
}

sub
FW_redirect($)
{
  my ($tgt) = @_;

  TcpServer_WriteBlocking($defs{$FW_cname},
           "HTTP/1.1 302 Found\r\n".
           "Content-Length: 0\r\n".
           $FW_headerlines.
           "Location: $tgt\r\n\r\n");
}

sub
FW_dataAttr()
{
  sub
  addParam($$$)
  {
    my ($dev, $p, $default) = @_;
    my $val = AttrVal($dev, $p, $default);
    $val =~ s/&/&amp;/g;
    $val =~ s/'/&#39;/g;
    return "data-$p='$val' ";
  }

  return
    ($FW_needIsDay ? 'data-isDay="'.(isday()?1:0).'"' : '') .
    addParam($FW_wname, "jsLog", 0).
    addParam($FW_wname, "confirmDelete", 1).
    addParam($FW_wname, "confirmJSError", 1).
    addParam($FW_wname, "addHtmlTitle", 1).
    addParam($FW_wname, "styleData", "").
    addParam($FW_wname, "hiddenroom", "").
    addParam($FW_wname, "htmlInEventMonitor", 0). #139453
    addParam("global",  "language", "EN").
    "data-availableJs='$FW_fhemwebjs' ".
    "data-webName='$FW_wname' ";
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
    if($unicodeEncoding) {
      $pv = Encode::decode('UTF-8', $pv);
      $pv =~ s/\x{2424}/\n/g; # revert fhemweb.js hack
    }
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
  $cmd.=" $arg{$c}" if(defined($arg{$c}));
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
  foreach my $d (devspec2array(".*", $FW_chash)) {
    next if(IsIgnored($d));
    $FW_rooms{all}{$d} = 1;

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

  %FW_extraRooms = ();
  if(my $extra = AttrVal($FW_wname, "extraRooms", undef)) {
    foreach my $room (split(/ |\n/, $extra)) {
      next if(!$room || $room =~ /^#/);
      $room =~ m/name=([^:]+):devspec=([^\s]+)/;
      my $r = $1;
      my $d = "#devspec=$2";
      $FW_rooms{$r}{$d} = 1;
      $FW_extraRooms{$r} = $d;
    }
  }


  $FW_room = AttrVal($FW_detail, "room", "Unsorted") if($FW_detail);
  @FW_roomsArr = sort grep { $_ ne "all" } keys %FW_rooms;

  if(AttrVal($FW_wname, "sortRooms", "")) { # Slow!
    my @sortBy = split( " ", AttrVal( $FW_wname, "sortRooms", "" ) );
    my %sHash;
    map { $sHash{$_} = FW_roomIdx(\@sortBy,$_) } keys %FW_rooms;
    @FW_roomsArr = sort { $sHash{$a} cmp $sHash{$b} } @FW_roomsArr;
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
  my $prefix = ($title eq "Attributes" ? "a-" : "");
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
          $v = "<pre>$v</pre>" if($v =~ m/\n/);
        }

        my $ifid = "class='dval' informId='$name-$prefix$n'";
        my $ifidts = "informId='$name-$prefix$n-ts'";
        if($FW_ss) {
          $t = ($t ? "<br><div class='tiny' $ifidts>$t</div>" : "");
          FW_pO "<td><span $ifid>$v</span>$t</td>";
        } else {
          $t = "" if(!$t);
          FW_pO "<td><div class='dval' $ifid>$v</div></td>";
          FW_pO "<td><div $ifidts>$t</div></td>";
        }
      } else {
        if($val =~ m,^<html>(.*)</html>$,s) {
          $val = $1;
        } else {
          $val = FW_htmlEscape($val);
        }
        my $tattr = "informId=\"$name-$prefix$n\" class=\"dval\"";

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
           $val = "<pre>$val</pre>" if($val =~ m/\n/);
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
  my ($d, $cmd, $list, $param, $typeHash) = @_;
  return "" if(!$list || $FW_hiddenroom{input});
  my @al = sort { 
             my $ta = $typeHash && $typeHash->{$a} ? $typeHash->{$a}.$a : $a;
             my $tb = $typeHash && $typeHash->{$b} ? $typeHash->{$b}.$b : $b;
             $ta cmp $tb;
           } map { s/:.*//; $_ } split(" ", $list);

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
  $ret .= "<div class=\"$cmd downText\"> $d ".($param ? "$param":"")."</div>";
  $ret .= FW_select("sel_$cmd$d","arg.$cmd$d",\@al,$selEl,$cmd,undef,$typeHash);
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
  return if(!defined($defs{$d}) || !devspec2array($d,$FW_chash));#check allowed
  my $h = $defs{$d};
  my $t = $h->{TYPE};
  $t = "MISSING" if(!defined($t));
  FW_addContent();

  if($FW_ss) {
    my $webCmd = AttrVal($d, "webCmd", $h->{webCmd});
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
        my ($allSets, $cmdlist, $txt) = FW_devState($d, "", \%extPage);
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
        FW_makeDeviceLine($d,-1,\%extPage,$nameDisplay,\%usuallyAtEnd);
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


  FW_pO FW_detailSelect($d, "set",
                      FW_widgetOverride($d, getAllSets($d, $FW_chash), "set"));
  FW_pO FW_detailSelect($d, "get",
                      FW_widgetOverride($d, getAllGets($d, $FW_chash), "get"));

  FW_makeTable("Internals", $d, $h);
  FW_makeTable("Readings", $d, $h->{READINGS});

  my %attrTypeHash;
  my $attrList = getAllAttr($d, undef, \%attrTypeHash);
  my $roomList = "multiple,".join(",",
                sort map { $_ =~ s/ /#/g ;$_} keys %FW_rooms);
  my $groupList = "multiple,".join(",",
                sort map { $_ =~ s/ /#/g ;$_} keys %FW_groups);
  $attrList =~ s/\broom\b/room:$roomList/;
  $attrList =~ s/\bgroup\b/group:$groupList/;

  $attrList = FW_widgetOverride($d, $attrList, "attr");
  if($attrList =~ m/[\\']/) {
    $attrList =~ s/([\\'])/\\$1/g;
    foreach my $k (keys %attrTypeHash) { # Forum #134526
      if($k =~ m/[\\']/) {
        my $nk = $k;
        $nk =~ s/([\\'])/\\$1/g;
        $attrTypeHash{$nk} = $attrTypeHash{$k};
      }
    }
  }
  FW_pO FW_detailSelect($d, "attr", $attrList, undef, \%attrTypeHash);

  FW_makeTable("Attributes", $d, $attr{$d}, "deleteattr");
  FW_makeTableFromArray("Probably associated with", "assoc", getPawList($d));

  FW_pO "</td></tr></table>";

  my ($link, $txt, $td, $class, $doRet,$nonl) = @_;

  FW_pO "<div id='detLink'>";
  my @detCmd = (
    'devSpecHelp',        "Help for $t",
    'forumCopy',          'Copy for forum.fhem.de',
    'rawDef',             'Raw definition',
    'style iconFor',      'Select icon',
    'style showDSI',      'Extend devStateIcon',
    'style eventMonitor', 'Event Monitor (filtered)',
    'delete',             "Delete $d"
  );
  my $lNum = AttrVal($FW_wname, "detailLinks", 2);
  if($lNum =~ m/^(\d),(.+)$/) {
    $lNum = $1;
    my %dc = @detCmd;
    @detCmd = map { ($_, $dc{$_}) if($dc{$_}) } split(",", $2);
  }
  my $li = 0;
  while($li < $lNum && $li < @detCmd / 2) {
    FW_pH "cmd=$detCmd[2*$li] $d", $detCmd[2*$li+1], undef, "detLink"
      if(!$FW_hiddenroom{$detCmd[2*$li]});
    $li++;
  }
  if($li < @detCmd/2) {
    FW_pO   "<select id='moreCmds'>";
    FW_pO     "<option >...</option>";
    while($li < @detCmd / 2) {
      FW_pO "<option data-cmd='$detCmd[2*$li] $d'>$detCmd[2*$li+1]</option>"
        if(!$FW_hiddenroom{$detCmd[2*$li]});
      $li++;
    }
    FW_pO   "</select>"
  }
  FW_pO "<br><br>";
  FW_pO "</div>";
}

##############################
sub
FW_makeTableFromArray($$@) {
  my ($txt,$class,@obj) = @_;
  if (@obj>0) {
    my $row=1;
    my $nameDisplay = AttrVal($FW_wname,"nameDisplay",undef);
    FW_pO "<div class='makeTable wide'>";
    FW_pO "<span class='mkTitle'>$txt</span>";
    FW_pO "<table class=\"block wide $class\">";
    foreach (sort @obj) {
      FW_pF "<tr class=\"%s\"><td>", (($row++)&1)?"odd":"even";
      my $alias = FW_alias($_, $nameDisplay);
      FW_pH "detail=$_", $alias eq $_ ? $_ : "$_ <span>($alias)</span>";
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
  map { $FW_hiddenroom{$_}=1 } split(",",AttrVal($FW_wname,"hiddenroom", ""));
  map { $FW_hiddenroom{$_}=1 } split(",",AttrVal($FW_wname,"forbiddenroom",""));

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
    if(my $devspec = $FW_extraRooms{$r}) {
      my $r = $r;
      $r =~ s/&nbsp;/ /g;
      push @list1, FW_htmlEscape($r);
      push @list2, "$FW_ME?room=".urlEncode($devspec);
    } else {
      push @list1, FW_htmlEscape($r);
      push @list2, "$FW_ME?room=".urlEncode($r);
    }

  }
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");
  my @list = (
     'Everything',    "$FW_ME?room=all",
     '',              '',
     'Commandref',    "$FW_ME/docs/commandref${sfx}.html",
     'Remote doc',    'http://fhem.de/fhem.html#Documentation',
     'Edit files',    "$FW_ME?cmd=style%20list",
     'Select style',  "$FW_ME?cmd=style%20select",
     'Event monitor', "$FW_ME?cmd=style%20eventMonitor",
     '',              '');

  my $lfn = "Logfile";
  if($defs{$lfn}) { # Add the current Logfile to the list if defined
    my @l = FW_fileList($defs{$lfn}{logfile},1);
    my $fn = pop @l;
    splice @list, 4,0, ('Logfile',
                      "$FW_ME/FileLog_logWrapper?dev=$lfn&type=text&file=$fn");
  }

  if(AttrVal($FW_wname, 'rescueDialog', undef)) {
    my $pid = $defs{$FW_wname}{rescuePID};
    $pid = 0 if(!$pid || !kill(0,$pid));
    my $key="";

    if(!-r "certs/fhemrescue.pub") {
      mkdir("certs");
      `ssh-keygen -N "" -t ed25519 -f certs/fhemrescue`;
    }
    if(open(my $fh, "certs/fhemrescue.pub")) {
      $key =  <$fh>;
      close($fh);
    }
    splice @list, @list-2,0, ('Rescue',
                      "javascript:FW_rescueClient(\"$pid\",\"$key\")");
  }

  my @me = split(",", AttrVal($FW_wname, "menuEntries", ""));
  push @list, @me, "", "" if(@me);

  my $lastname = ",";
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
      my $v = $list2[$idx];
      $v .= $FW_CSRF if($v =~ m/cmd=/);
      FW_pO "<option value='$v'$sel>$list1[$idx]</option>";
    }
    FW_pO "</select></td>";
    FW_pO "</tr>";

  } else {

    my $tblnr = 1;
    my $roomEscaped = FW_htmlEscape($FW_room);
    my $current;
    $current = "$FW_ME?room=".urlEncode($FW_room) if($FW_room);
    $current = "$FW_ME?cmd=".urlEncode($cmd) if($cmd);
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      my ($l1, $l2) = ($list1[$idx], $list2[$idx]);
      if(!$l1) {
        FW_pO "</table></td></tr>" if($idx);
        if($idx<int(@list1)-1) {
          FW_pO "<tr><td><table class=\"room roomBlock$tblnr\">";
          $tblnr++;
        }

      } else {
        FW_pF "<tr%s>", ($current && $current eq $l2) ? " class=\"sel\"" : "";

        my $class = "menu_$l1";
        $class =~ s/[^A-Z0-9]/_/gi;

        # image tag if we have an icon, else empty
        my $icoName = "ico$l1";
        map { my ($n,$v) = split(":",$_); $icoName=$v if($l1 =~ m/^$n$/); }
                        split(" ", AttrVal($FW_wname, "roomIcons", ""));
        my $icon = FW_iconName($icoName) ?
                        FW_makeImage($icoName,$icoName,"icon")."&nbsp;" : "";

        if($l1 eq "Save config") {
          $l1 .= '</span></a> '.
                  '<a id="saveCheck" class="changed" style="visibility:'.
                  (int(@structChangeHist) ? 'visible' : 'hidden').'"><span>?';
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
FW_alias($$)
{
  my ($DEVICE,$nameDisplay) = @_;
  my $ALIAS = AttrVal($DEVICE, "alias", $DEVICE);
  $ALIAS = AttrVal($DEVICE, "alias_$FW_room", $ALIAS) if($FW_room);
  $ALIAS = eval $nameDisplay if(defined($nameDisplay));

  return $ALIAS;
}

sub
FW_makeDeviceLine($$$$$)
{
  my ($d,$row,$extPage,$nameDisplay,$usuallyAtEnd) = @_;
  my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

  FW_pF "\n<tr class=\"%s devname_$d\">", ($row&1)?"odd":"even";
  my $devName = FW_alias($d,$nameDisplay);
  my $icon = AttrVal($d, "icon", $defs{$d}{icon});
  $icon = "" if(!defined($icon));
  $icon = FW_makeImage($icon,$icon,"icon") . "&nbsp;" if($icon);

  $devName="" if($modules{$defs{$d}{TYPE}}{FW_hideDisplayName}); # Forum 88667
  if(!$usuallyAtEnd->{$d}) {
    if($FW_hiddenroom{detail}) {
      FW_pO "<td><div class=\"col1\">$icon$devName</div></td>";
    } else {
      FW_pH "detail=$d", "$icon$devName", 1, "col1";
    }
  }

  my ($allSets, $cmdlist, $txt) = FW_devState($d, $row==-1 ? "":$rf, $extPage);
  if($cmdlist) {
    my $cl2 = $cmdlist; $cl2 =~ s/ [^:]*//g; $cl2 =~ s/:/ /g;  # Forum #74053
    $allSets = "$allSets $cl2";
  }
  $allSets = FW_widgetOverride($d, $allSets, "set");

  my $colSpan = ($usuallyAtEnd->{$d} ? ' colspan="2"' : '');
  FW_pO "<td informId=\"$d\"$colSpan>$txt</td>";

  ######
  # Commands, slider, dropdown
  my $smallscreenCommands = AttrVal($FW_wname, "smallscreenCommands", "");
  if((!$FW_ss || $smallscreenCommands) && $cmdlist) {
    my @a = split("[: ]", AttrVal($d, "cmdIcon",
                                $defs{$d}{cmdIcon} ? $defs{$d}{cmdIcon} : ""));
    Log 1, "ERROR: bad cmdIcon definition for $d" if(@a % 2);
    my %cmdIcon = @a;

    my @cl = split(":", $cmdlist);
    my $wclDefault = $defs{$d}{webCmdLabel} ? $defs{$d}{webCmdLabel} : "";
    my @wcl = split(":", AttrVal($d, "webCmdLabel", $wclDefault));
    my $nRows;
    $nRows = split("\n", AttrVal($d, "webCmdLabel", $wclDefault)) if(@wcl);
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
        $htmlTxt =~ s,^<td[^>]*>(.*)</td>$,$1,s;
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
          FW_pO  "<td><div class='col3 col3_$i1'>$wcl[$i1]$htmlTxt</div></td>";
        }

      } else {
        FW_pO  "<td><div class='col3 col3_$i1'>$htmlTxt</div></td>";
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
  my $roomRe = $FW_room;
  $roomRe =~ s/([[\\\]().+*?])/\\$1/g;
  return 0 if(!$FW_room ||
              AttrVal($FW_wname,"forbiddenroom","") =~ m/\b$roomRe\b/);

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
  my @devs;
  if( $FW_room =~ m/^#devspec=(.*)$/ ) {
    @devs = devspec2array($1) if( $1 );
    @devs = () if( int(@devs) == 1 && !defined($defs{$devs[0]}) );

  } else {
    @devs = grep { $FW_rooms{$FW_room} && $FW_rooms{$FW_room}{$_} } keys %defs;
  }

  my (%group, @atEnds, %usuallyAtEnd, %sortIndex);
  my $nDevsInRoom = 0;
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
      $nDevsInRoom++;
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

  FW_pO "</table>";
  FW_pO "<br>" if(@atEnds && $nDevsInRoom);

  # Now the "atEnds"
  my $doBC = (AttrVal($FW_wname, "plotfork", 0) &&
              AttrVal($FW_wname, "plotEmbed", ($numCPUs>1 ? 2:0)) == 0);
  my %res;
  my ($idx,$svgIdx) = (1,1);
  @atEnds =  sort { $sortIndex{$a} cmp $sortIndex{$b} } @atEnds;
  $FW_svgData{$FW_cname} = { FW_RET=>$FW_RET, RES=>\%res, ATENDS=>\@atEnds };
  my $svgDataUsed = 1;
  foreach my $d (@atEnds) {
    no strict "refs";
    my $fn = $modules{$defs{$d}{TYPE}}{FW_summaryFn};
    $extPage{group} = "atEnd";
    $extPage{index} = $idx++;
    if($doBC && $defs{$d}{TYPE} eq "SVG" && $FW_use{base64}) {
      $extPage{svgIdx} = $svgIdx++;
      BlockingCall(sub {
        return "$FW_cname,$d,".
               encode_base64(&{$fn}($FW_wname,$d,$FW_room,\%extPage),'');
      }, undef, "FW_svgCollect");
      $svgDataUsed++;
    } else {
      $res{$d} = &{$fn}($FW_wname,$d,$FW_room,\%extPage);
    }
    use strict "refs";
  }
  delete($FW_svgData{$FW_cname}) if(!$svgDataUsed);
  return FW_svgDone(\%res, \@atEnds, undef);
}

sub
FW_svgDone($$$)
{
  my ($res, $atEnds, $delayedReturn) = @_;
  return -2 if(int(keys %{$res}) != int(@{$atEnds}));

  foreach my $d (@{$atEnds}) {
    FW_pO $res->{$d};
  }
  FW_pO "</div>";
  FW_pO "</form>";
  FW_pO "</body></html>" if($delayedReturn);
  return 0;
}

sub
FW_svgCollect($)
{
  my ($cname,$d,$enc) = split(",",$_[0],3);
  my $h = $FW_svgData{$cname};
  my ($res, $atEnds) = ($h->{RES}, $h->{ATENDS});
  $res->{$d} = decode_base64($enc);
  return if(!defined($atEnds) || int(keys %{$res}) != int(@{$atEnds}));
  $FW_RET = $h->{FW_RET};
  delete($FW_svgData{$cname});
  FW_svgDone($res, $atEnds, 1);
  FW_finishRead($defs{$cname}, 0, "");
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
        eval { "Hallo" =~ m/^$group$/ };
        if($@) {
          Log3 $FW_wname, 1, "Bad regexp in column spec: $@";
        } else {
          foreach my $g (grep /$group/ ,@grouplist) {
            next if($handled{$g});
            $handled{$g} = 1;
            $columns{$g} = [$lineNo++, $colNo]; #23212
          }
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
  my $logdir = Logdir();
  $fname =~ s/%L/$logdir/g; #Forum #89744
  $fname =~ m,^(.*)/([^/]*)$,; # Split into dir and file
  my ($dir,$re) = ($1, $2);
  return $fname if(!$re);
  $re =~ s/%./[A-Za-z0-9]*/g;    # logfile magic (%Y, etc)
  my @ret;
  return @ret if(!opendir(DH, $dir));
  while(my $f = readdir(DH)) {
    next if($f !~ m,^$re$, || $f eq "98_FhemTestUtils.pm" || 
                              $f eq "99_Utils.pm");

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
               $FW_httpheader{"Accept-Encoding"} =~ m/gzip/ && $FW_use{zlib}) ?
                "Content-Encoding: gzip\r\n" : "";
  TcpServer_WriteBlocking($FW_chash, "HTTP/1.1 200 OK\r\n".
                  $compr . $expires . $FW_headerlines . $etag .
                  "Transfer-Encoding: chunked\r\n" .
                  "Content-Type: $type; charset=$FW_encoding\r\n\r\n");

  my $d;
  $d = Compress::Zlib::deflateInit(-WindowBits=>31) if($compr);
  FW_outputChunk($FW_chash, $FW_RET, $d);
  FW_outputChunk($FW_chash, "<a name='top'></a>".
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
  my ($id, $name, $valueArray, $selected, $class, $jSelFn, $typeHash) = @_;
  $jSelFn = ($jSelFn ? "onchange=\"$jSelFn\"" : "");
  $id =~ s/\./_/g if($id);      # to avoid problems in JS DOM Search
  $id = ($id ? "id=\"$id\" informId=\"$id\"" : "");
  my $s = "<select $jSelFn $id name=\"$name\" class=\"$class\">";
  my $oldType="";
  my %processed;
  foreach my $v (@{$valueArray}) {
    next if($processed{$v});
    if($typeHash) {
      my $newType = $typeHash->{$v};
      $newType =~ s/^#//; #124538, see also getAllAttr
      if($newType ne $oldType) {
        $s .= "</optgroup>" if($oldType);
        $s .= "<optgroup label='$newType'>" if($newType);
      }
      $oldType = $newType;
    }
    if(defined($selected) && $v eq $selected) {
      $s .= "<option selected=\"selected\" value='$v'>$v</option>\n";
    } else {
      $s .= "<option value='$v'>$v</option>\n";
    }
    $processed{$v} = 1;
  }
  $s .= "</optgroup>" if($oldType);
  $s .= "</select>";
  return $s;
}

##################
sub
FW_textfieldv($$$$;$)
{
  my ($n, $z, $class, $value, $place) = @_;
  my $v;
  $v.=" value='$value'" if(defined($value));
  $v.=" placeholder='$place'" if(defined($place));
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
  return if(!@files);
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

  my @f = FW_confFiles(2);
  return "$FW_confdir/$name" if ( map { $name =~ $_ } @f );

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

  } elsif($name =~ m/.*log$/) {
    return Logdir()."/$name";

  } else {
    return "$MW_dir/$name";

  }
}

sub FW_confFiles($) {
   my ($param) = @_;
   # create and return regexp for editFileList
   return "(".join ( "|" , sort keys %{$data{confFiles}} ).")" if $param == 1;
   # create and return array with filenames
   return sort keys %{$data{confFiles}} if $param == 2;
}

##################
# List/Edit/Save files
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
      "Config files for external programs:\$FW_confdir:^".FW_confFiles(1)."\$\n".
      "Gplot files:\$FW_gplotdir:^.*gplot\$\n".
      "Style files:\$FW_cssdir:^.*(css|svg)\$");
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
    my %smap= ( ""=>"f11", "touchpad"=>"f11touchpad",
                "smallscreen"=>"f11smallscreen");
    my @fl = map { $_ =~ s/style.css//; $smap{$_} ? $smap{$_} : $_ }
             grep { $_ !~ m/(svg_|floorplan|dashboard)/ }
             FW_fileList("$FW_cssdir/.*style.css");
    FW_addContent($start);
    FW_pO "<div class='fileList styles'>Styles</div>";
    FW_pO "<table class='block wide fileList'>";
    my $sp = $FW_sp eq "default" ? "" : $FW_sp;;
    $sp = $smap{$sp} if($smap{$sp});
    my $row = 0;
    foreach my $file (sort @fl) {
      FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      FW_pH "cmd=style set $file", "$file", 1,
        "style$file ".($sp eq $file ? "changed":"");
      FW_pO "</tr>";
      $row = ($row+1)%2;
    }
    FW_pO "</table>$end";

  } elsif($a[1] eq "set") {
    CommandAttr(undef, "$FW_wname stylesheetPrefix $a[2]");
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
    my $ret;
    $ret = FW_fC("rereadcfg") if($filePath eq $attr{global}{configfile});
    $ret = FW_fC("reload $fileName") if($fileName =~ m,\.pm$,);
    $ret = FW_Set("","","rereadicons") if($isImg);
    DoTrigger("global", "FILEWRITE $filePath", 1) if(!$ret); # Forum #32592
    my $sfx = ($forceType eq "configDB" ? " to configDB" : "");
    $ret = ($ret ? "<h3>ERROR:</h3><b>$ret</b>" : "Saved $fileName$sfx");
    FW_style("style list", $ret);
    $ret = "";

  } elsif($a[1] eq "iconFor") {
    FW_iconTable("iconFor", "icon", "style setIF $a[2] %s", undef);

  } elsif($a[1] eq "setIF") {
    FW_fC("attr $a[2] icon $a[3]");
    FW_redirect("$FW_ME?detail=$a[2]");

  } elsif($a[1] eq "showDSI") {
    FW_iconTable("devStateIcon", "",
                 "style addDSI $a[2] %s", "Enter value/regexp for STATE");

  } elsif($a[1] eq "addDSI") {
    my $dsi = AttrVal($a[2], "devStateIcon", "");
    $dsi .= " " if($dsi);
    FW_fC("attr $a[2] devStateIcon $dsi$FW_data:$a[3]");
    FW_redirect("$FW_ME?detail=$a[2]");

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
      next if($imgName =~ m+^\.+ || $imgName =~ m+/\.+); # Skip dot files
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

  $link .= $FW_CSRF if($link =~ m/cmd/ &&
                       $link !~m/cmd=style%20(list|select|eventMonitor)/);
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
      if($name =~ m/@([^:@]*)([:@](.*))?$/) {
        my ($fill, $stroke) = ($1, $3);
        if($fill ne "") {
          $fill = "#$fill" if($fill =~ m/^([A-F0-9]{6})$/);
          $data =~ s/fill="#000000"/fill="$fill"/g;
          $data =~ s/fill:#000000/fill:$fill/g;
        }
        if(defined($stroke)) {
          $stroke = "#$stroke" if($stroke =~ m/^([A-F0-9]{6})$/);
          $data =~ s/stroke="#000000"/stroke="$stroke"/g;
          $data =~ s/stroke:#000000/stroke:$stroke/g;
        }
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
  if($unique) {
    $ret = AnalyzeCommand($FW_chash, $cmd);
  } else {
    $ret = AnalyzeCommandChain($FW_chash, $cmd);
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

  if($type eq "set" && $attrName eq "HTTPS" && $param[0]) {
    InternalTimer(1, "TcpServer_SetSSL", $hash, 0); # Wait for sslCertPrefix
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

  if($attrName eq "extraRooms") {
    foreach my $room (split(/ |\n/, $param[0])) {
      next if(!$room || $room =~ /^#/);
      return "Bad extraRooms entry $room, not name=<name>:devspec=<devspec>"
        if($room !~ m/name=([^:]+):devspec=([^\s]+)/);
    }
  }

  if($attrName eq "longpoll" && $type eq "set" && $param[0] eq "websocket") {
    return "$devName: Could not load Digest::SHA on startup, no websocket"
        if(!$FW_use{sha});
  }

  if($attrName eq "styleData" && $type eq "set") {
     $FW_needIsDay = ($param[0] =~ m/dayNightActive.*true/);
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
  $FW_icons{$dir}{""} = undef; # Do not check empty directories again.
}

sub
FW_readIcons($)
{
  my ($dir)= @_;
  return if(exists($FW_icons{$dir}));
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
  my $devStateIcon = AttrVal($name, "devStateIcon", $d->{devStateIcon});
  return "" if(defined($devStateIcon) && lc($devStateIcon)  eq 'none');

  my $type = $d->{TYPE};
  $state = $d->{STATE} if(!defined($state));
  return "" if(!$type || !defined($state));

  my $model = AttrVal($name, "model", "");
  my (undef, $rstate) = ReplaceEventMap($name, [undef, $state], 0);

  my ($icon, $rlink);
  if(defined($devStateIcon) && $devStateIcon =~ m/^{.*}$/s) {
    $cmdFromAnalyze = $devStateIcon; # help the __WARN__ sub
    my ($html, $link) = eval $devStateIcon;
    $cmdFromAnalyze = undef;
    Log3 $FW_wname, 1, "devStateIcon $name: $@" if($@);
    return ($html, $link, 1) if(defined($html) && $html =~ m/^<.*>$/s);
    $devStateIcon = $html;
    if($devStateIcon) { # 132483
      foreach my $l (split(" ", $devStateIcon)) {
        my ($re, $iconName, $link) = split(":", $l, 3);
        eval { "Hallo" =~ m/^$re$/ };    
        if($@) {
          Log 1, "ERROR: $name devStateIcon evaluated to $devStateIcon => $@";
          return "ERROR, check the log";
        }
      }
    }
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
    TcpServer_Close($ntfy, 1, !$ntfy->{inform});
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
        my @a = ("a-$2: $3");
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
    FW_setStylesheet();
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
      my $ct = $dev->{CHANGETIME};
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
        my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
        push @data, FW_longpollInfo($h->{fmt}, "$dn-$readingName-ts", $t, $t);
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
      my $ct = $dev->{CHANGETIME};
      my $max = int(@{$events});
      my $dt = $dev->{TYPE};
      for(my $i = 0; $i < $max; $i++) {
        my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
        my $line = "$t $dt $dn ".$events->[$i]."<br>";
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
      TcpServer_Close($ntfy, 1, !$ntfy->{inform});
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
  $dev =~ s/-.*//;      # 131373
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
      TcpServer_Close($ntfy, 1, !$ntfy->{inform});
    }
  }
}

###################
# Compute the state (==second) column
# return ($allSets, $cmdList, $txt);
sub
FW_devState($$@)
{
  my ($d, $rf, $extPage) = @_;

  my ($hasOnOff, $link);
  return ("","","") if(!$FW_wname);

  my $cmdList = AttrVal($d, "webCmd", $defs{$d}{webCmd});
  $cmdList = "" if(!defined($cmdList));
  my $allSets = FW_widgetOverride($d, getAllSets($d, $FW_chash), "set");
  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));

  my $txt = $state;
  my ($ad,$hash) = ($attr{$d}, $defs{$d});
  my $dsi = ($ad && ($ad->{stateFormat}||$ad->{webCmd}||$ad->{devStateIcon})) ||
             $hash->{webCmd} || $hash->{devStateIcon};

  $hasOnOff = ($allSets =~ m/(^| )on(:[^ ]*)?( |$)/i &&
               $allSets =~ m/(^| )off(:[^ ]*)?( |$)/i);
  if(AttrVal($d, "showtime", undef)) {
    my $v = $hash->{READINGS}{state}{TIME};
    $txt = $v if(defined($v));

  } elsif(!$dsi && $allSets =~ m/\bdesired-temp:/) {
    $txt = "$1 &deg;C" if($txt =~ m/^measured-temp: (.*)/);
    $cmdList = "desired-temp" if(!$cmdList);

  } elsif(!$dsi && $allSets =~ m/\bdesiredTemperature:/) {
    $txt = ReadingsVal($d, "temperature", "");
    $txt =~ s/ .*//;
    $txt .= "&deg;C";
    $cmdList = "desiredTemperature" if(!$cmdList);

  } else {
    my $html = "";
    foreach my $state (split("\n", $state)) {
      $state =~ s/ *$//;
      $txt = $state;
      my ($icon, $isHtml);
      ($icon, $link, $isHtml) = FW_dev2image($d,$state);
      $txt = ($isHtml ? $icon : FW_makeImage($icon, $state)) if(defined($icon));

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

      if($hasOnOff) {
        my $isUpperCase = ($allSets =~ m/(^| )ON(:[^ ]*)?( |$)/ &&
                           $allSets =~ m/(^| )OFF(:[^ ]*)?( |$)/);
        # Have to cover: "on:An off:Aus", "A0:Aus AI:An Aus:off An:on"
        my $on  = ReplaceEventMap($d, $isUpperCase ? "ON" :"on" , 1);
        my $off = ReplaceEventMap($d, $isUpperCase ? "OFF":"off", 1);
        $link = "cmd.$d=set $d " . ($state eq $on ? $off : $on)
                if(!defined($link));
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
      $html .= ' ' if( $html );
      $html .= $txt;
    }
    $txt = $html;
  }

  my $style = AttrVal($d, "devStateStyle", $hash->{devStateStyle});
  $style = "" if(!defined($style));

  $state =~ s/"//g;
  $state =~ s/<.*?>/ /g; # remove HTML tags for the title
  $txt = "<div id=\"$d\" $style title=\"$state\" class=\"col2\">$txt</div>";

  my $type = $hash->{TYPE};
  my $sfn = $modules{$type}{FW_summaryFn};
  if($sfn) {
    $extPage = {} if(!defined($extPage));
    no strict "refs";
    my $newtxt = &{$sfn}($FW_wname, $d, $rf ? $FW_room : "", $extPage);
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
  my %cmd = ("clearSvgCache" => ":noArg",
             "reopen" => ":noArg",
             "rereadicons" => ":noArg");

  if(AttrVal($hash->{NAME}, "rescueDialog", "")) {
    $cmd{"rescueStart"} = "";
    $cmd{"rescueTerminate"} = ":noArg";
  }

  return "no set value specified" if(@a < 2);
  return ("Unknown argument $a[1], choose one of ".
        join(" ", map { "$_$cmd{$_}" } sort keys %cmd))
    if(!defined($cmd{$a[1]}));

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

  if($a[1] eq "reopen") {
    TcpServer_Close($hash);
    delete($hash->{stacktrace});
    my ($port, $global) = split("[ \t]+", $hash->{DEF});
    my $ret = TcpServer_Open($hash, $port, $global);
    return $ret if($ret);
    TcpServer_SetSSL($hash) if(AttrVal($hash->{NAME}, "SSL", 0));
    return undef;
  }

  if($a[1] eq "rescueStart") {
    return "error: rescueStart needs two arguments: host and port"
      if(!$a[2] || !$a[3] || $a[3] !~ m/[0-9]{1,5}/ || $a[3] > 65536);
    return "error: rescue process is running with PID $hash->{rescuePID}"
      if($hash->{rescuePID} && kill(0, $hash->{rescuePID}));
    return "error: certificate certs/fhemrescue is not available"
      if(! -r "certs/fhemrescue");
    $hash->{rescuePID} = fhemFork();
    return "error: cannot fork rescue pid\n"
      if($hash->{rescuePID} == -1);
    return undef if($hash->{rescuePID}); # Parent
    my $cmd = "ssh ".
              "-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ".
              "-N -R0.0.0.0:18083:localhost:$hash->{PORT} -i certs/fhemrescue ".
              "-p$a[3] fhemrescue\@$a[2]";

    Log3 $hash, 2, "Starting $cmd";
    exec("exec $cmd");
  }

  if($a[1] eq "rescueTerminate") {
    return "error: nothing to terminate"
      if(!$hash->{rescuePID});
    kill(15, $hash->{rescuePID});
    delete($hash->{rescuePID});
  }

  return undef;
}

#####################################
sub
FW_closeInactiveClients()
{
  my $now = time();
  foreach my $dev (keys %defs) {
    my $h = $defs{$dev};
    next if(!$h->{TYPE} || $h->{TYPE} ne "FHEMWEB" ||
            !$h->{LASTACCESS} || $h->{inform} ||
            ($now - $h->{LASTACCESS}) < 60);
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

  my($source) = split(' ', $cmd, 2); # cmd part only, #136049
  my $current;
  if($cmd eq "desired-temp" || $cmd eq "desiredTemperature") {
    $current = ReadingsVal($d, $cmd, 20);
    $current =~ s/ .*//;        # Cut off Celsius
    $current = sprintf("%2.1f", int(2*$current)/2) if($current =~ m/[0-9.-]/);
  } else {
    $current = ReadingsVal($d, $source, undef);
    if( !defined($current) ) {
      $source = 'state';
      $current = Value($d);
    }
    $current =~ s/$cmd //;
    $current = ReplaceEventMap($d, $current, 1);
  }
  return "<td><div class='fhemWidget' cmd='$cmd' reading='$source' ".
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
FW_widgetOverride($$;$)
{
  my ($d, $str, $type) = @_;

  return $str if(!$str);

  my $da = AttrVal($d, "widgetOverride", "");
  my $fa = AttrVal($FW_wname, "widgetOverride", "");
  return $str if(!$da && !$fa);

  my @list;
  push @list, split(" ", $fa) if($fa);
  push @list, split(" ", $da) if($da);
  foreach my $na (@list) {
    if($type && $na =~ m/^([^:]*)@(set|get|attr):(.*)/) {
      next if($2 ne $type);
      $na = "$1:$3";
    }
    my ($n,$a) = split(":", $na, 2);
    $str =~ s/\b($n)\b(:[^ ]*)?/$1:$a/g;
  }
  return $str;
}

sub
FW_show($$)
{
  my ($hash, $param) = @_;
  return "usage: show <devspec>" if( !$param);

  $FW_room = "#devspec=$param";
  return undef;
}

sub
FW_log($$)
{
  my ($arg, $length) = @_;

  my $c = $defs{$FW_cname};
  my $fmt = AttrVal($FW_wname, "logFormat", '%h %l %u %t "%r" %>s %b');
  my $rc = $FW_httpRetCode;
  $rc =~ s/ .*//;
  $arg = substr($arg,0,5000)."..." if(length($arg) > 5000);

  my @t = localtime;
  my %cp = (
    h=>$c->{PEER},
    l=>"-",
    u=>$c->{AuthenticatedUser} ? $c->{AuthenticatedUser} : "-",
    t=>"[".strftime("%d/%b/%Y:%H:%M:%S %z",@t)."]",
    r=>$arg,
    ">s"=>$rc,
    b=>$length
  );

  $fmt =~ s/%\{([^" ]*)\}i/
        defined($FW_httpheader{$1}) ? $FW_httpheader{$1} : "-" /gex;
  $fmt =~ s/%([^" ]*)/defined($cp{$1}) ? $cp{$1} : "-"/ge;

  my $ld = AttrVal($FW_wname, "logDevice", undef);
  CallFn($ld, "LogFn", $defs{$ld}, $fmt) if($defs{$ld});
}


1;

=pod
=item helper
=item summary    HTTP Server and FHEM Frontend
=item summary_DE HTTP Server und FHEM Frontend
=begin html

<a id="FHEMWEB"></a>
<h3>FHEMWEB</h3>
<ul>
  FHEMWEB is the builtin web-frontend, it also implements a simple web
  server (optionally with Basic-Auth and HTTPS).
  <br> <br>

  <a id="FHEMWEB-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMWEB &lt;tcp-portnr&gt; [global|IP]</code>
    <br><br>
    Enable the webfrontend on port &lt;tcp-portnr&gt;. If global is specified,
    then requests from all interfaces (not only localhost / 127.0.0.1) are
    serviced. If IP is specified, then FHEMWEB will only listen on this IP.<br>
    To enable listening on IPV6 see the comments <a href="#telnet">here</a>.
    <br>
  </ul>
  <br>

  <a id="FHEMWEB-set"></a>
  <b>Set</b>
  <ul>
    <a id="FHEMWEB-set-rereadicons"></a>
    <li>rereadicons<br>
      reads the names of the icons from the icon path.  Use after adding or
      deleting icons.
      </li>
    <a id="FHEMWEB-set-clearSvgCache"></a>
    <li>clearSvgCache<br>
      delete all files found in the www/SVGcache directory, which is used to
      cache SVG data, if the SVGcache attribute is set.
      </li>
    <a id="FHEMWEB-set-reopen"></a>
    <li>reopen<br>
      reopen the server port. This is an alternative to restart FHEM when
      the SSL certificate is replaced.
      </li>
  </ul>
  <br>

  <a id="FHEMWEB-get"></a>
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
        located</li>
    <br><br>

  </ul>

  <a id="FHEMWEB-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="addHtmlTitle"></a>
    <li>addHtmlTitle<br>
      If set to 0, do not add a title Attribute to the set/get/attr detail
      widgets. This might be necessary for some screenreaders. Default is 1.
      </li><br>

    <li>alias_&lt;RoomName&gt;<br>
        If you define a userattr alias_&lt;RoomName&gt; and set this attribute
        for a device assgined to &lt;RoomName&gt;, then this value will be used
        when displaying &lt;RoomName&gt;.<br>
        Note: you can use the userattr alias_.* to allow all rooms, but in this
        case the attribute dropdown in the device detail view won't work for the
        alias_.* attributes.
        </li><br>

    <a id="FHEMWEB-attr-allowfrom"></a>
    <li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set, only connections
        from these addresses are allowed.<br>
        NOTE: if this attribute is not defined and there is no valid allowed
        device defined for the telnet/FHEMWEB instance and the client tries to
        connect from a non-local net, then the connection is refused. Following
        is considered a local net:<br>
        <ul>
          IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16<br>
          IPV6: ::1, fe80/10<br>
        </ul>
        </li><br>

    <a id="FHEMWEB-attr-allowedHttpMethods"></a>
    <li>allowedHttpMethods<br>
      FHEMWEB implements the GET, POST and OPTIONS HTTP methods. Some external
      devices require the HEAD method, which is not implemented correctly in
      FHEMWEB, as FHEMWEB always returns a body, which, according to the spec,
      is wrong. As in some cases this not a problem, enabling GET may work.
      To do this, set this attribute to GET|POST|HEAD, default ist GET|POST.
      OPTIONS is always enabled.
      </li><br>

    <a id="FHEMWEB-attr-closeConn"></a>
    <li>closeConn<br>
      If set, a TCP Connection will only serve one HTTP request. Seems to
      solve problems on iOS9 for WebApp startup.
      </li><br>

    <a id="FHEMWEB-attr-column"></a>
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

    <a id="FHEMWEB-attr-confirmDelete"></a>
    <li>confirmDelete<br>
        confirm delete actions with a dialog. Default is 1, set it to 0 to
        disable the feature.
        </li>
        <br>

    <a id="FHEMWEB-attr-confirmJSError"></a>
    <li>confirmJSError<br>
        JavaScript errors are reported in a dialog as default.
        Set this attribute to 0 to disable the reporting.
        </li>
        <br>

    <a id="FHEMWEB-attr-CORS"></a>
    <li>CORS<br>
        If set to 1, FHEMWEB will supply a "Cross origin resource sharing"
        header, see the wikipedia for details.
        </li>
        <br>

    <a id="FHEMWEB-attr-csrfToken"></a>
    <li>csrfToken<br>
       If set, FHEMWEB requires the value of this attribute as fwcsrf Parameter
       for each command. It is used as countermeasure for Cross Site Resource
       Forgery attacks. If the value is random, then a random number will be
       generated on each FHEMWEB start. If it is set to the literal string
       none, no token is expected. Default is random for featurelevel 5.8 and
       greater, and none for featurelevel below 5.8 </li><br>

    <a id="FHEMWEB-attr-csrfTokenHTTPHeader"></a>
    <li>csrfTokenHTTPHeader<br>
       If set (default), FHEMWEB sends the token with the X-FHEM-csrfToken HTTP
       header, which is used by some clients. Set it to 0 to switch it off, as
       a measurre against shodan.io like FHEM-detection.</li><br>

    <a id="FHEMWEB-attr-CssFiles"></a>
    <li>CssFiles<br>
       Space separated list of .css files to be included. The filenames
       are relative to the www directory. Example:
       <ul><code>
         attr WEB CssFiles pgm2/mystyle.css
       </code></ul>
       </li><br>

    <a id="FHEMWEB-attr-Css"></a>
    <li>Css<br>
       CSS included in the header after the CssFiles section.
       </li><br>

    <a id="FHEMWEB-attr-cmdIcon"></a>
    <li>cmdIcon<br>
        Space separated list of cmd:iconName pairs. If set, the webCmd text is
        replaced with the icon. An easy method to set this value is to use
        "Extend devStateIcon" in the detail-view, and copy its value.<br>
        Example:<ul>
        attr lamp cmdIcon on:control_centr_arrow_up off:control_centr_arrow_down
        </ul>
        </li><br>

    <a id="FHEMWEB-attr-defaultRoom"></a>
    <li>defaultRoom<br>
        show the specified room if no room selected, e.g. on execution of some
        commands.  If set hides the <a href="#motd">motd</a>. Example:<br>
        attr WEB defaultRoom Zentrale
        </li>
        <br>

    <a id="FHEMWEB-attr-detailLinks"></a>
    <li>detailLinks<br>
        number of links to show on the bottom of the device detail page.
        The rest of the commands is shown in a dropdown menu. Default is 2.<br>
        This can optionally followed by a comma separated list of ids to order
        or filter the desired links, the ids being one of devSpecHelp,
        forumCopy, rawDef, style iconFor, style showDSI, style eventMonitor, delete.<br>
        Example:<br>
        attr WEB detailLinks 2,devSpecHelp,forumCopy
        </li>
        <br>

    <a id="FHEMWEB-attr-devStateIcon"></a>
    <li>devStateIcon<br>
        First form:<br>
        <ul>
        Space separated list of regexp:icon-name:cmd triples, icon-name and cmd
        may be empty.<br>
        If the STATE of the device matches regexp, then icon-name will be
        displayed as the status icon in the room, and (if specified) clicking
        on the icon executes cmd.  If FHEM cannot find icon-name, then the
        STATE text will be displayed.
        Example:<br>
        <ul>
        attr lamp devStateIcon on:closed off:open<br>
        attr lamp devStateIcon on::A0 off::AI<br>
        attr lamp devStateIcon .*:noIcon<br>
        </ul>
        Note: if the image is referencing an SVG icon, then you can use the
        @fill:stroke suffix to color the image, where fill replaces the fill
        color in the SVG (if it is specified as #000000) and the optional
        stroke the stroke color (if it is specified as #000000). E.g.:<br>
        <ul>
        attr Fax devStateIcon on:control_building_empty@red
                              off:control_building_filled:278727
        </ul>
        If the cmd is noFhemwebLink, then no HTML-link will be generated, i.e.
        nothing will happen when clicking on the icon or text.<br>
        Note: if you need stroke coloring in the devStateIcon, you have to use
        the alternative @fill@stroke syntax.
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
        Note: The above is valid for each line of STATE. If STATE (through stateFormat)
        is multilined, multiple icons (one per line) will be created.<br>
        <br>

    <a id="FHEMWEB-attr-devStateStyle"></a>
    <li>devStateStyle<br>
        Specify an HTML style for the given device, e.g.:<br>
        <ul>
        attr sensor devStateStyle style="text-align:left;;font-weight:bold;;"<br>
        </ul>
        </li>
        <br>

    <a id="FHEMWEB-attr-deviceOverview"></a>
    <li>deviceOverview<br>
        Configures if the device line from the room view (device icon, state
        icon and webCmds/cmdIcons) should also be shown in the device detail
        view. Can be set to always, onClick, iconOnly or never. Default is
        always.
        </li><br>

    <a id="FHEMWEB-attr-editConfig"></a>
    <li>editConfig<br>
        If this FHEMWEB attribute is set to 1, then you will be able to edit
        the FHEM configuration file (fhem.cfg) in the "Edit files" section.
        After saving this file a rereadcfg is executed automatically, which has
        a lot of side effects.<br>
        </li><br>

    <a id="FHEMWEB-attr-editFileList"></a>
    <li>editFileList<br>
        Specify the list of Files shown in "Edit Files" section. It is a
        newline separated list of triples, the first is the Title, the next is
        the directory to search for as a perl expression(!), the third the
        regular expression. Default
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

    <a id="FHEMWEB-attr-endPlotNow"></a>
    <li>endPlotNow<br>
        Set the default for all SVGs: If this FHEMWEB attribute is set to 1,
        then day and hour plots will end at current time. Else the whole day,
        the 6 hour period starting at 0, 6, 12 or 18 hour or the whole hour
        will be shown.  This attribute is not used if the SVG has the attribute
        startDate defined.
        </li><br>

    <a id="FHEMWEB-attr-endPlotNowByHour"></a>
    <li>endPlotNowByHour<br>
        Set the default for all SVGs: If endPlotNow and this attribute are set
        to 1 and the zoom-level is "day", then the displayed hour ticks will be
        rounded to the complete hour.
        </li><br>

    <a id="FHEMWEB-attr-endPlotToday"></a>
    <li>endPlotToday<br>
        set the default for alls SVGs: If this FHEMWEB attribute is set to 1,
        then week and month plots will end today. Else the current week or the
        current month will be shown.
        </li><br>

    <a id="FHEMWEB-attr-fwcompress"></a>
    <li>fwcompress<br>
        Enable compressing the HTML data (default is 1, i.e. yes, use 0 to
        switch it off).
        </li><br>

    <a id="FHEMWEB-attr-extraRooms"></a>
    <li>extraRooms<br>
        Space or newline separated list of dynamic rooms to add to the room
        list.<br>
        Example:<br>
          attr WEB extraRooms
                    name=open:devspec=contact=open.*
                    name=closed:devspec=contact=closed.*
        </li><br>

    <a id="FHEMWEB-attr-forbiddenroom"></a>
    <li>forbiddenroom<br>
        just like hiddenroom (see below), but accessing the room or the
        detailed view via direct URL is prohibited.
        </li><br>

    <a id="FHEMWEB-attr-hiddengroup"></a>
    <li>hiddengroup<br>
        Comma separated list of groups to "hide", i.e. not to show in any room
        of this FHEMWEB instance.<br>
        Example:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li>
        <br>

    <a id="FHEMWEB-attr-hiddengroupRegexp"></a>
    <li>hiddengroupRegexp<br>
        One <a href="#regexp">regexp</a> for the same purpose as hiddengroup.
        </li>
        <br>

    <a id="FHEMWEB-attr-hiddenroom"></a>
    <li>hiddenroom<br>
        Comma separated list of rooms to "hide", i.e. not to show. Special
        values are input, detail and save, in which case the input areas, link
        to the detailed views or save button are hidden (although each aspect
        still can be addressed through URL manipulation).<br>
        The list can also contain values from the additional "Howto/Wiki/FAQ"
        block, and from the bottom of the detail page: devSpecHelp, forumCopy,
        rawDef, style iconFor, style showDSI, delete.
        </li>
        <br>

    <a id="FHEMWEB-attr-hiddenroomRegexp"></a>
    <li>hiddenroomRegexp<br>
        One <a href="#regexp">regexp</a> for the same purpose as hiddenroom.
        Example:
        <ul>
          attr WEB hiddenroomRegexp .*config
        </ul>
        Note: the special values input, detail and save cannot be specified
        with hiddenroomRegexp.
        </li>
        <br>

    <a id="FHEMWEB-attr-httpHeader"></a>
    <li>httpHeader<br>
        One or more HTTP header lines to be sent out with each answer. Example:
        <ul><code>
          attr WEB httpHeader X-Clacks-Overhead: GNU Terry Pratchett
        </code></ul>
        </li>
        <br>

    <a id="FHEMWEB-attr-htmlInEventMonitor"></a>
    <li>htmlInEventMonitor<br>
        if set to 1, text enclosed in &lt;html&gt;...&lt;/html&gt; will not be
        escaped in the event monitor.
        </li>
        <br>

    <a id="FHEMWEB-attr-HTTPS"></a>
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
        openssl req -new -x509 -nodes -out server-cert.pem -days 3650
                -keyout server-key.pem
        </ul>
        These commands are automatically executed if there is no certificate.
        Because of this automatic execution, the attribute sslCertPrefix should
        be set, if necessary, before this attribute.
      <br>
    </li>

    <a id="FHEMWEB-attr-icon"></a>
    <li>icon<br>
        Set the icon for a device in the room overview. There is an
        icon-chooser in FHEMWEB to ease this task.  Setting icons for the room
        itself is indirect: there must exist an icon with the name
        ico&lt;ROOMNAME&gt;.png in the iconPath.
        </li>
        <br>

    <a id="FHEMWEB-attr-iconPath"></a>
    <li>iconPath<br>
      colon separated list of directories where the icons are read from.
      The directories start in the fhem/www/images directory. The default is
      $styleSheetPrefix:fhemSVG:openautomation:default<br>
      Set it to fhemSVG:openautomation to get only SVG images.
      </li>
      <br>

    <a id="FHEMWEB-attr-JavaScripts"></a>
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
       -fhemweb.js and/or -f18.js will prevent the loading of the corresponding
       file, this, in combination with the addition of an old version of the
       file may be a solution for old tablets with an outdated browser.
       <ul>
         attr WEB_iOS6 JavaScripts -fhemweb.js -f18.js pgm2/iOS6_fhemweb.js pgm2/iOS6_f18.js
       </ul>
       </li><br>

    <a id="FHEMWEB-attr-logDevice"></a>
    <li>logDevice fileLogName<br>
       Name of the FileLog instance, which is used to log each FHEMWEB access.
       To avoid writing wrong lines to this file, the FileLog regexp should be
       set to &lt;WebName&gt;:Log
       </li><br>

    <a id="FHEMWEB-attr-logFormat"></a>
    <li>logFormat ...<br>
        Default is the Apache common Format (%h %l %u %t "%r" %>s %b).
        Currently only these "short" place holders are replaced. Additionally,
        each HTTP Header X can be accessed via %{X}i.
       </li><br>

    <a id="FHEMWEB-attr-jsLog"></a>
    <li>jsLog [1|0]<br>
        if set, and longpoll is websocket, send the browser console log
        messages to the FHEM log. Useful for debugging tablet/phone problems.
       </li><br>

    <a id="FHEMWEB-attr-longpoll"></a>
    <li>longpoll [0|1|websocket]<br>
        If activated, the browser is notifed when device states, readings or
        attributes are changed, a reload of the page is not necessary.
        Default is 1 (on), use 0 to deactivate it.<br>
        If websocket is specified, then this API is used to notify the browser,
        else HTTP longpoll. Note: some older browser do not implement websocket.
        </li>
        <br>

    <a id="FHEMWEB-attr-longpollSVG"></a>
    <li>longpollSVG<br>
        Reloads an SVG weblink, if an event should modify its content. Since
        an exact determination of the affected events is too complicated, we
        need some help from the definition in the .gplot file: the filter used
        there (second parameter if the source is FileLog) must either contain
        only the deviceName or have the form deviceName.event or deviceName.*.
        This is always the case when using the <a href="#plotEditor">Plot
        editor</a>. The SVG will be reloaded for <b>any</b> event triggered by
        this deviceName. Default is off.<br>
        Note: this feature needs the plotEmbed attribute set to 1.
        </li>
        <br>


    <a id="FHEMWEB-attr-mainInputLength"></a>
    <li>mainInputLength<br>
        length of the maininput text widget in characters (decimal number).
        </li>
        <br>

    <a id="FHEMWEB-attr-menuEntries"></a>
    <li>menuEntries<br>
        Comma separated list of name,html-link pairs to display in the
        left-side list.  Example:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries
                AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li>
        <br>


    <a id="FHEMWEB-attr-nameDisplay"></a>
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

    <a id="FHEMWEB-attr-nrAxis"></a>
    <li>nrAxis<br>
        the number of axis for which space should be reserved  on the left and
        right sides of a plot and optionaly how many axes should realy be used
        on each side, separated by comma: left,right[,useLeft,useRight].  You
        can set individual numbers by setting the nrAxis of the SVG. Default is
        1,1.
        </li><br>

    <a id="FHEMWEB-attr-ploteditor"></a>
    <li>ploteditor<br>
        Configures if the <a href="#plotEditor">Plot editor</a> should be shown
        in the SVG detail view.
        Can be set to always, onClick or never. Default is always.
        </li><br>

    <a id="FHEMWEB-attr-plotEmbed"></a>
    <li>plotEmbed<br>
        If set to 1, SVG plots will be rendered as part of &lt;embed&gt;
        tags, as in the past this was the only way to display SVG. Setting
        plotEmbed to 0 will render SVG in-place.<br>
        Setting plotEmbed to 2 will load the SVG via JavaScript, in order to
        enable parallelization without the embed tag.
        Default is 2 for multi-CPU hosts on Linux, and 0 everywhere else.
    </li><br>

    <a id="FHEMWEB-attr-plotfork"></a>
    <li>plotfork<br>
        If set to a nonzero value, run part of the processing (e.g. <a
        href="#SVG">SVG</a> plot generation or <a href="#RSS">RSS</a> feeds) in
        parallel processes, default is 0.  Note: do not use it on systems with
        small memory footprint.
    </li><br>

    <a id="FHEMWEB-attr-plotmode"></a>
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

    <a id="FHEMWEB-attr-plotsize"></a>
    <li>plotsize<br>
        the default size of the plot, in pixels, separated by comma:
        width,height. You can set individual sizes by setting the plotsize of
        the SVG. Default is 800,160 for desktop, and 480,160 for
        smallscreen.
        </li><br>

    <a id="FHEMWEB-attr-plotWeekStartDay"></a>
    <li>plotWeekStartDay<br>
        Start the week-zoom of the SVG plots with this day.
        0 is Sunday, 1 is Monday, etc.<br>
    </li><br>

    <a id="FHEMWEB-attr-redirectCmds"></a>
    <li>redirectCmds<br>
        Clear the browser URL window after issuing the command by redirecting
        the browser, as a reload for the same site might have unintended
        side-effects. Default is 1 (enabled). Disable it by setting this
        attribute to 0 if you want to study the command syntax, in order to
        communicate with FHEMWEB.
        </li>
        <br>

    <a id="FHEMWEB-attr-redirectTo"></a>
    <li>redirectTo<br>
        If set, and FHEMWEB cannot handle a request, redirect the client to
        $FW_ME/$redirectTo$arg. If not set, redirect to $FW_ME. If set to
        eventFor:<regexp>, and $arg matches the regexp, then an event for the
        FHEMWEB instance with $arg will be generated.
        </li>
        <br>

    <a id="FHEMWEB-attr-refresh"></a>
    <li>refresh<br>
        If set, a http-equiv="refresh" entry will be genererated with the given
        argument (i.e. the browser will reload the page after the given
        seconds).
        </li><br>

    <a id="FHEMWEB-attr-rescueDialog"></a>
    <li>rescueDialog<br>
        If set, show a Rescue link in the menu. The goal is to be able to get
        help from someone with more knowlege (rescuer), who is then able to
        remote control this installation.<br>
        After opening the dialog, a key is shown, which is to be sent to the
        rescuer. After the rescuer installed the key (see below), the
        connection can be established, by entering the adress of the
        rescuers server.<br><br>

        <b>TODO for the rescuer:</b>
        <ul>
          <li>Forward a public IP/PORT combination to your SSH server.</li>
          <li>create a fhemrescue user on this server, and store the key from
             the client:<br>
            <ul><code>
            useradd -d /tmp -s /bin/false fhemrescue<br>
            echo "KEY_FROM_THE_CLIENT" > /etc/sshd/fhemrescue.auth<br>
            chown fhemrescue:fhemrescue /etc/sshd/fhemrescue.auth<br>
            chmod 600 /etc/sshd/fhemrescue.auth
            </code></ul>
            </li>
          <li>Append to /etc/ssh/sshd_config:<br>
            <ul><code>
              Match User fhemrescue<br>
              <ul>
                AllowTcpForwarding remote<br>
                PermitTTY no<br>
                GatewayPorts yes<br>
                ForceCommand /bin/false<br>
                AuthorizedKeysFile /etc/ssh/fhemrescue.auth<br>
              </ul>
            </code></ul>
            </li>
          <li>Restart sshd, e.g. with systemctl restart sshd
            </li>
          <li>Tell the client your public IP/PORT.</li>
          <li>After the client started the connection in the rescue dialog, you
          can access the clients FHEM via your host, port 18083.</li>
        </ul>
        </li><br>

    <a id="FHEMWEB-attr-reverseLogs"></a>
    <li>reverseLogs<br>
        Display the lines from the logfile in a reversed order, newest on the
        top, so that you dont have to scroll down to look at the latest entries.
        Note: enabling this attribute will prevent FHEMWEB from streaming
        logfiles, resulting in a considerably increased memory consumption
        (about 6 times the size of the file on the disk).
        </li>
        <br>

    <a id="FHEMWEB-attr-roomIcons"></a>
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

    <a id="FHEMWEB-attr-smallscreenCommands"></a>
    <li>smallscreenCommands<br>
       If set to 1, commands, slider and dropdown menues will appear in
       smallscreen landscape mode.
       </li><br>

    <a id="FHEMWEB-attr-sortby"></a>
    <li>sortby<br>
        Take the value of this attribute when sorting the devices in the room
        overview instead of the alias, or if that is missing the devicename
        itself. If the sortby value is enclosed in {} than it is evaluated as a
        perl expression. $NAME is set to the device name.
        </li>
        <br>

    <a id="FHEMWEB-attr-showUsedFiles"></a>
    <li>showUsedFiles<br>
        In the Edit files section, show only the used files.
        Note: currently this is only working for the "Gplot files" section.
        </li>
        <br>

    <a id="FHEMWEB-attr-sortRooms"></a>
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

    <a id="FHEMWEB-attr-sslCertPrefix"></a>
    <li>sslCertPrefix<br>
       Set the prefix for the SSL certificate, default is certs/server-, see
       also the HTTPS attribute.
       </li><br>

    <a id="FHEMWEB-attr-styleData"></a>
    <li>styleData<br>
      data-storage used by dynamic styles like f18
      </li><br>

    <a id="FHEMWEB-attr-stylesheetPrefix"></a>
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

    <a id="FHEMWEB-attr-SVGcache"></a>
    <li>SVGcache<br>
        if set, cache plots which won't change any more (the end-date is prior
        to the current timestamp). The files are written to the www/SVGcache
        directory. Default is off.<br>
        See also the clearSvgCache command for clearing the cache.
        </li><br>

    <a id="FHEMWEB-attr-title"></a>
    <li>title<br>
        Sets the title of the page. If enclosed in {} the content is evaluated.
    </li><br>

    <a id="FHEMWEB-attr-viewport"></a>
    <li>viewport<br>
       Sets the &quot;viewport&quot; attribute in the HTML header. This can for
       example be used to force the width of the page or disable zooming.<br>
       Example: attr WEB viewport
       width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no
    </li><br>

    <a id="FHEMWEB-attr-webCmd"></a>
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

    <a id="FHEMWEB-attr-webCmdLabel"></a>
    <li>webCmdLabel<br>
        Colon separated list of labels, used to prefix each webCmd. The number
        of labels must exactly match the number of webCmds. To implement
        multiple rows, insert a return character after the text and before the
        colon.</li></br>

    <a id="FHEMWEB-attr-webname"></a>
    <li>webname<br>
        Path after the http://hostname:port/ specification. Defaults to fhem,
        i.e the default http address is http://localhost:8083/fhem
        </li><br>

    <a id="FHEMWEB-attr-widgetOverride"></a>
    <li>widgetOverride<br>
        Space separated list of name:modifier pairs, to override the widget
        for a set/get/attribute specified by the module author.
        To specify the widget for a specific type, use the name@type:modifier
        syntax, where type is one of set, get and attr.
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

<a id="FHEMWEB"></a>
<h3>FHEMWEB</h3>
<ul>
  FHEMWEB ist das default WEB-Frontend, es implementiert auch einen einfachen
  Webserver (optional mit Basic-Auth und HTTPS).
  <br> <br>

  <a id="FHEMWEB-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHEMWEB &lt;tcp-portnr&gt; [global|IP]</code>
    <br><br>
    Aktiviert das Webfrontend auf dem Port &lt;tcp-portnr&gt;. Mit dem
    Parameter global werden Anfragen von allen Netzwerkschnittstellen
    akzeptiert (nicht nur vom localhost / 127.0.0.1). Falls IP angegeben wurde,
    dann werden nur Anfragen an diese IP Adresse akzeptiert.  <br>

    Informationen f&uuml;r den Betrieb mit IPv6 finden Sie <a
    href="#telnet">hier</a>.<br>
  </ul>
  <br>

  <a id="FHEMWEB-set"></a>
  <b>Set</b>
  <ul>
    <a id="FHEMWEB-set-rereadicons"></a>
    <li>rereadicons<br>
      Damit wird die Liste der Icons neu eingelesen, f&uuml;r den Fall, dass
      Sie Icons l&ouml;schen oder hinzuf&uuml;gen.
      </li>
    <a id="FHEMWEB-set-clearSvgCache"></a>
    <li>clearSvgCache<br>
      Im Verzeichnis www/SVGcache werden SVG Daten zwischengespeichert, wenn
      das Attribut SVGcache gesetzt ist.  Mit diesem Befehl leeren Sie diesen
      Zwischenspeicher.
      </li>
    <a id="FHEMWEB-set-reopen"></a>
    <li>reopen<br>
      Schlie&szlig;t und &ouml;ffnet der Serverport. Das kann eine Alternative
      zu FHEM-Neustart sein, wenn das SSL-Zertifikat sich ge&auml;ndert hat.
      </li>
  </ul>
  <br>

  <a id="FHEMWEB-get"></a>
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

  <a id="FHEMWEB-attr"></a>
  <b>Attribute</b>
  <ul>
    <a id="FHEMWEB-attr-addHtmlTitle"></a>
    <li>addHtmlTitle<br>
      Falls der Wert 0 ist, wird bei den set/get/attr Parametern in der
      DetailAnsicht der Ger&auml;te kein title Attribut gesetzt. Das is bei
      manchen Screenreadern erforderlich. Die Voreinstellung ist 1.
      </li><br>

    <li>alias_&lt;RoomName&gt;<br>
        Falls man das Attribut alias_&lt;RoomName&gt; definiert, und dieses
        Attribut f&uuml;r ein Ger&auml;t setzt, dann wird dieser Wert bei
        Anzeige von &lt;RoomName&gt; verwendet.<br>
        Achtung: man kann im userattr auch alias_.* verwenden um alle
        m&ouml;glichen R&auml;ume abzudecken, in diesem Fall wird aber die
        Attributauswahl in der Detailansicht f&uuml;r alias_.* nicht
        funktionieren.
        </li><br>

    <a id="FHEMWEB-attr-allowfrom"></a>
    <li>allowfrom<br>
        Regexp der erlaubten IP-Adressen oder Hostnamen. Wenn dieses Attribut
        gesetzt wurde, werden ausschlie&szlig;lich Verbindungen von diesen
        Adressen akzeptiert.<br>
        Achtung: falls allowfrom nicht gesetzt ist, und keine g&uuml;tige
        allowed Instanz definiert ist, und die Gegenstelle eine nicht lokale
        Adresse hat, dann wird die Verbindung abgewiesen. Folgende Adressen
        werden als local betrachtet:
        <ul>
          IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16<br>
          IPV6: ::1, fe80/10<br>
        </ul>
        </li><br>

    <a id="FHEMWEB-attr-allowedHttpMethods"></a>
    <li>allowedHttpMethods</br>
      FHEMWEB implementiert die HTTP Methoden GET, POST und OPTIONS. Manche
      externe Ger&auml;te ben&ouml;tigen HEAD, das ist aber in FHEMWEB nicht
      korrekt implementiert, da FHEMWEB immer ein body zur&uuml;ckliefert, was
      laut Spec falsch ist. Da ein body in manchen F&auml;llen kein Problem
      ist, kann man HEAD durch setzen dieses Attributes auf GET|POST|HEAD
      aktivieren, die Voreinstellung ist GET|POST. OPTIONS ist immer
      aktiviert.
      </li><br>

     <a id="FHEMWEB-attr-closeConn"></a>
     <li>closeConn<br>
        Falls gesetzt, wird pro TCP Verbindung nur ein HTTP Request
        durchgef&uuml;hrt. F&uuml;r iOS9 WebApp startups scheint es zu helfen.
        </li><br>

    <a id="FHEMWEB-attr-cmdIcon"></a>
    <li>cmdIcon<br>
        Leerzeichen getrennte Auflistung von cmd:iconName Paaren.
        Falls gesetzt, wird das webCmd text durch den icon gesetzt.
        Am einfachsten setzt man cmdIcon indem man "Extend devStateIcon" im
        Detail-Ansicht verwendet, und den Wert nach cmdIcon kopiert.<br>
        Beispiel:<ul>
        attr lamp cmdIcon on:control_centr_arrow_up off:control_centr_arrow_down
        </ul>
        </li><br>

     <a id="FHEMWEB-attr-column"></a>
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

    <a id="FHEMWEB-attr-confirmDelete"></a>
    <li>confirmDelete<br>
        L&ouml;schaktionen werden mit einem Dialog best&auml;tigt.
        Falls dieses Attribut auf 0 gesetzt ist, entf&auml;llt das.
        </li>
        <br>

    <a id="FHEMWEB-attr-confirmJSError"></a>
    <li>confirmJSError<br>
        JavaScript Fehler werden per Voreinstellung in einem Dialog gemeldet.
        Durch setzen dieses Attributes auf 0 werden solche Fehler nicht
        gemeldet.
        </li>
        <br>

    <a id="FHEMWEB-attr-CORS"></a>
    <li>CORS<br>
        Wenn auf 1 gestellt, wird FHEMWEB einen "Cross origin resource sharing"
        Header bereitstellen, n&auml;heres siehe Wikipedia.
        </li><br>

     <a id="FHEMWEB-attr-csrfToken"></a>
     <li>csrfToken<br>
        Falls gesetzt, wird der Wert des Attributes als fwcsrf Parameter bei
        jedem &uuml;ber FHEMWEB abgesetzten Kommando verlangt, es dient zum
        Schutz von Cross Site Resource Forgery Angriffen.
        Falls der Wert random ist, dann wird ein Zufallswert beim jeden FHEMWEB
        Start neu generiert, falls er none ist, dann wird kein Parameter
        verlangt. Default ist random f&uuml;r featurelevel 5.8 und
        gr&ouml;&szlig;er, und none f&uuml;r featurelevel kleiner 5.8
        </li><br>

    <a id="FHEMWEB-attr-csrfTokenHTTPHeader"></a>
    <li>csrfTokenHTTPHeader<br>
       Falls gesetzt (Voreinstellung), FHEMWEB sendet im HTTP Header den
       csrfToken als X-FHEM-csrfToken, das wird von manchen FHEM-Clients
       benutzt. Mit 0 kann man das abstellen, um Sites wie shodan.io die
       Erkennung von FHEM zu erschweren.</li><br>

     <a id="FHEMWEB-attr-CssFiles"></a>
     <li>CssFiles<br>
        Leerzeichen getrennte Liste von .css Dateien, die geladen werden.
        Die Dateinamen sind relativ zum www Verzeichnis anzugeben. Beispiel:
        <ul><code>
          attr WEB CssFiles pgm2/mystyle.css
        </code></ul>
        </li><br>

    <a id="FHEMWEB-attr-Css"></a>
    <li>Css<br>
       CSS, was nach dem CssFiles Abschnitt im Header eingefuegt wird.
       </li><br>

    <a id="FHEMWEB-attr-defaultRoom"></a>
    <li>defaultRoom<br>
        Zeigt den angegebenen Raum an falls kein Raum explizit ausgew&auml;hlt
        wurde.  Achtung: falls gesetzt, wird motd nicht mehr angezeigt.
        Beispiel:<br>
        attr WEB defaultRoom Zentrale
        </li><br>

    <a id="FHEMWEB-attr-detailLinks"></a>
    <li>detailLinks<br>
        Anzahl der Links, die auf der Detailseite unten angezeigt werden. Die
        weiteren Befehle werden in einem Auswahlmen&uuml; angezeigt.
        Voreinstellung ist 2.<br>
        Das kann optional mit der Liste der anzuzeigenden IDs erweitert werden,
        um die Links zu sortieren oder zu filtern. Die m&ouml;glichen IDs sind
        devSpecHelp, forumCopy, rawDef, style iconFor, style showDSI,
        style eventMonitor, delete.<br>
        Beispiel:<br> attr WEB detailLinks 2,devSpecHelp,forumCopy
        </li>
        <br>

    <a id="FHEMWEB-attr-devStateIcon"></a>
    <li>devStateIcon<br>
        Erste Variante:<br>
        <ul>
        Leerzeichen getrennte Auflistung von regexp:icon-name:cmd
        Dreierp&auml;rchen, icon-name und cmd d&uuml;rfen leer sein.<br>

        Wenn STATE des Ger&auml;tes mit der regexp &uuml;bereinstimmt,
        wird als icon-name das entsprechende Status Icon angezeigt, und (falls
        definiert), l&ouml;st ein Klick auf das Icon das entsprechende cmd aus.
        Wenn FHEM icon-name nicht finden kann, wird STATE als Text
        angezeigt.
        Beispiel:<br>
        <ul>
        attr lamp devStateIcon on:closed off:open<br>
        attr lamp devStateIcon on::A0 off::AI<br>
        attr lamp devStateIcon .*:noIcon<br>
        </ul>
        Anmerkung: Wenn das Icon ein SVG Bild ist, kann das @fill:stroke
        Suffix verwendet werden um das Icon einzuf&auml;rben, dabei wird in
        der SVG die F&uuml;llfarbe durch das spezifizierte fill ersetzt, und
        die Stiftfarbe durch das optionale stroke.
        Z.B.:<br>
        <ul>
          attr Fax devStateIcon on:control_building_empty@red
          off:control_building_filled:278727
        </ul>
        Falls cmd noFhemwebLink ist, dann wird kein HTML-Link generiert, d.h.
        es passiert nichts, wenn man auf das Icon/Text klickt.
        Achtung: falls im devStateIcons das &Auml;ndern der Stiftfarbe
        ben&oumltigt wird, dann ist die alternative @fill@stroke Syntax zu
        verwenden.
        </ul>
        Zweite Variante:<br>
        <ul>
        Perl Ausdruck eingeschlossen in {}. Wenn der Code undef
        zur&uuml;ckliefert, wird das Standard Icon verwendet; wird ein String
        in <> zur&uuml;ck geliefert, wird dieser als HTML String interpretiert.
        Andernfalls wird der String als devStateIcon gem&auml;&szlig; der
        ersten Variante interpretiert, siehe oben.  Beispiel:<br>

        {'&lt;div style="width:32px;height:32px;background-color:green"&gt;&lt;/div&gt;'}
        </ul>
        Anmerkung: Obiges gilt pro STATE Zeile. Wenn STATE (durch stateFormat) mehrzeilig
        ist, wird pro Zeile ein Icon erzeugt.<br>
        </li><br>

    <a id="FHEMWEB-attr-devStateStyle"></a>
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

    <a id="FHEMWEB-attr-editConfig"></a>
    <li>editConfig<br>
        Falls dieses FHEMWEB Attribut (auf 1) gesetzt ist, dann kann man die
        FHEM Konfigurationsdatei in dem "Edit files" Abschnitt bearbeiten. Beim
        Speichern dieser Datei wird automatisch rereadcfg ausgefuehrt, was
        diverse Nebeneffekte hat.<br>
        </li><br>

    <a id="FHEMWEB-attr-editFileList"></a>
    <li>editFileList<br>
        Definiert die Liste der angezeigten Dateien in der "Edit Files"
        Abschnitt.  Es ist eine Newline getrennte Liste von Tripeln bestehend
        aus Titel, Verzeichnis f&uuml;r die Suche als perl Ausdruck(!), und
        Regexp. Die Voreinstellung ist:
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

    <a id="FHEMWEB-attr-endPlotNow"></a>
    <li>endPlotNow<br>
        Setzt die Voreinstellung f&uuml;r alle SVGs: Wenn Sie dieses FHEMWEB
        Attribut auf 1 setzen, werden Tages und Stunden-Plots zur aktuellen
        Zeit beendet. (&Auml;hnlich wie endPlotToday, nur eben min&uuml;tlich).
        Ansonsten wird der gesamte Tag oder eine 6 Stunden Periode (0, 6, 12,
        18 Stunde) gezeigt. Dieses Attribut wird nicht verwendet, wenn das SVG
        Attribut startDate benutzt wird.
        </li><br>

    <a id="FHEMWEB-attr-endPlotNowByHour"></a>
    <li>endPlotNowByHour<br>
        Setzt die Voreinstellung f&uuml;r alle SVGs: Falls endPlotNow und
        dieses Attribut auf 1 gesetzt sind, und Zoom-Level ein Tag ist, dann
        werden die angezeigten Zeitmarker auf die volle Stunde gerundet.
        </li><br>

    <a id="FHEMWEB-attr-endPlotToday"></a>
    <li>endPlotToday<br>
        Setzt die Voreinstellung f&uuml;r alle SVGs: Wird dieses FHEMWEB
        Attribut gesetzt, so enden Wochen- bzw. Monatsplots am aktuellen Tag,
        sonst wird die aktuelle Woche/Monat angezeigt.
        </li><br>

    <a id="FHEMWEB-attr-extraRooms"></a>
    <li>extraRooms<br>
        Durch Leerzeichen oder Zeilenumbruch getrennte Liste von dynamischen
        R&auml;umen, die zus&auml;tzlich angezeigt werden sollen.
        Beispiel:<br>
          attr WEB extraRooms
                        name=Offen:devspec=contact=open.*
                        name=Geschlossen:devspec=contact=closed.*
        </li><br>


    <a id="FHEMWEB-attr-forbiddenroom"></a>
    <li>forbiddenroom<br>
       Wie hiddenroom, aber der Zugriff auf die Raum- oder Detailansicht
       &uuml;ber direkte URL-Eingabe wird unterbunden.
       </li><br>

    <a id="FHEMWEB-attr-fwcompress"></a>
    <li>fwcompress<br>
        Aktiviert die HTML Datenkompression (Standard ist 1, also ja, 0 stellt
        die Kompression aus).
        </li><br>

    <a id="FHEMWEB-attr-hiddengroup"></a>
    <li>hiddengroup<br>
        Wie hiddenroom (siehe unten), jedoch auf Ger&auml;tegruppen bezogen.
        <br>
        Beispiel:  attr WEBtablet hiddengroup FileLog,dummy,at,notify
        </li><br>

    <a id="FHEMWEB-attr-hiddengroupRegexp"></a>
    <li>hiddengroupRegexp<br>
        Ein <a href="#regexp">regul&auml;rer Ausdruck</a>, um Gruppen zu
        verstecken.
        </li>
        <br>

    <a id="FHEMWEB-attr-hiddenroom"></a>
    <li>hiddenroom<br>
       Eine Komma getrennte Liste, um R&auml;ume zu verstecken, d.h. nicht
       anzuzeigen. Besondere Werte sind input, detail und save. In diesem
       Fall werden diverse Eingabefelder ausgeblendent. Durch direktes Aufrufen
       der URL sind diese R&auml;ume weiterhin erreichbar!<br>
       Ebenso k&ouml;nnen Eintr&auml;ge in den Logfile/Commandref/etc Block
       versteckt werden, oder die Links unten auf der Detailseite: devSpecHelp,
       forumCopy, rawDef, style iconFor, style showDSI, delete.
       </li><br>

    <a id="FHEMWEB-attr-hiddenroomRegexp"></a>
    <li>hiddenroomRegexp<br>
        Ein <a href="#regexp">regul&auml;rer Ausdruck</a>, um R&auml;ume zu
        verstecken. Beispiel:
        <ul>
          attr WEB hiddenroomRegexp .*config
        </ul>
        Achtung: die besonderen Werte input, detail und save m&uuml;ssen mit
        hiddenroom spezifiziert werden.
        </li>
        <br>

    <a id="FHEMWEB-attr-httpHeader"></a>
    <li>httpHeader<br>
        Eine oder mehrere HTTP-Header Zeile, die in jede Antwort eingebettet
        wird. Beispiel:
        <ul><code>
          attr WEB httpHeader X-Clacks-Overhead: GNU Terry Pratchett
        </code></ul>
        </li>
        <br>

    <a id="FHEMWEB-attr-htmlInEventMonitor"></a>
    <li>htmlInEventMonitor<br>
        falls 1, Text in &lt;html&gt;...&lt;/html&gt; wird im Event Monitor als
        HTML interpretiert.
        </li>
        <br>

    <a id="FHEMWEB-attr-HTTPS"></a>
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
        Diese Befehle werden beim Setzen des Attributes automatisch
        ausgef&uuml;hrt, falls kein Zertifikat gefunden wurde. Deswegen, falls
        n&ouml;tig, sslCertPrefix vorher setzen.
      <br>
    </li>

    <a id="FHEMWEB-attr-icon"></a>
    <li>icon<br>
        Damit definiert man ein Icon f&uuml;r die einzelnen Ger&auml;te in der
        Raum&uuml;bersicht. Es gibt einen passenden Link in der Detailansicht
        um das zu vereinfachen. Um ein Bild f&uuml;r die R&auml;ume selbst zu
        definieren muss ein Icon mit dem Namen ico&lt;Raumname&gt;.png im
        iconPath existieren (oder man verwendet roomIcons, s.u.)
        </li><br>

    <a id="FHEMWEB-attr-iconPath"></a>
    <li>iconPath<br>
      Durch Doppelpunkt getrennte Aufz&auml;hlung der Verzeichnisse, in
      welchen nach Icons gesucht wird.  Die Verzeichnisse m&uuml;ssen unter
      fhem/www/images angelegt sein. Standardeinstellung ist:
      $styleSheetPrefix:fhemSVG:openautomation:default<br>
      Setzen Sie den Wert auf fhemSVG:openautomation um nur SVG Bilder zu
      benutzen.
      </li><br>

    <a id="FHEMWEB-attr-JavaScripts"></a>
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
       -fhemweb.js und/oder -f18.js verhindert das Laden diese Dateien, was, in
       Kombination mit einer alter Version der Datei, eine Abhilfe bei alten
       Tablets mit nicht mehr aktulisierbaren Browser sein kann:
       <ul>
         attr WEB_iOS6 JavaScripts -fhemweb.js -f18.js pgm2/iOS6_fhemweb.js pgm2/iOS6_f18.js
       </ul>

       </li><br>

    <a id="FHEMWEB-attr-logDevice"></a>
    <li>logDevice fileLogName<br>
       Name einer FileLog Instanz, um Zugriffe zu protokollieren.
       Um das Protokollieren falscher Eintr&auml;ge zu vermeiden, sollte das
       FileLog Regexp der Form &lt;WebName&gt;:Log sein.
       </li><br>

    <a id="FHEMWEB-attr-logFormat"></a>
    <li>logFormat ...<br>
        Voreinstellung ist das Apache common Format (%h %l %u %t "%r" %>s %b).
        Z.Zt. werden nur diese "kurzen" Platzhalter ersetzt, weiterhin kann man
        mit %{X} den HTTP-Header-Eintrag X spezifizieren.
       </li><br>


    <a id="FHEMWEB-attr-jsLog"></a>
    <li>jsLog [1|0]<br>
        falls gesetzt, und longpoll=websocket, dann werden Browser
        Konsolenmeldungen in das FHEM-Log geschrieben. N&uuml;tzlich bei der
        Fehlersuche auf Tablets oder Handys.
       </li><br>

    <a id="FHEMWEB-attr-longpoll"></a>
    <li>longpoll [0|1|websocket]<br>
        Falls gesetzt, FHEMWEB benachrichtigt den Browser, wenn
        Ger&auml;testatuus, Readings or Attribute sich &auml;ndern, ein
        Neuladen der Seite ist nicht notwendig. Zum deaktivieren 0 verwenden.
        <br>
        Falls websocket spezifiziert ist, l&auml;uft die Benachrichtigung des
        Browsers &uuml;ber dieses Verfahren sonst &uuml;ber HTTP longpoll.
        Achtung: &auml;ltere Browser haben keine websocket Implementierung.
        </li><br>


    <a id="FHEMWEB-attr-longpollSVG"></a>
    <li>longpollSVG<br>
        L&auml;dt SVG Instanzen erneut, falls ein Ereignis dessen Inhalt
        &auml;ndert. Funktioniert nur, falls die dazugeh&ouml;rige Definition
        der Quelle in der .gplot Datei folgenden Form hat: deviceName.Event
        bzw. deviceName.*. Wenn man den <a href="#plotEditor">Plot Editor</a>
        benutzt, ist das &uuml;brigens immer der Fall. Die SVG Datei wird bei
        <b>jedem</b> ausl&ouml;senden Event dieses Ger&auml;tes neu geladen.
        Die Voreinstellung ist aus.<br>
        Achtung: fuer dieses Feature muss das plotEmbed Attribute auf 1 gesetzt
        sein.
        </li><br>

    <a id="FHEMWEB-attr-mainInputLength"></a>
    <li>mainInputLength<br>
        L&auml;nge des maininput Eingabefeldes (Anzahl der Buchstaben,
        Ganzzahl).
        </li> <br>

    <a id="FHEMWEB-attr-menuEntries"></a>
    <li>menuEntries<br>
        Komma getrennte Liste; diese Links werden im linken Men&uuml; angezeigt.
        Beispiel:<br>
        attr WEB menuEntries fhem.de,http://fhem.de,culfw.de,http://culfw.de<br>
        attr WEB menuEntries
                      AlarmOn,http://fhemhost:8083/fhem?cmd=set%20alarm%20on<br>
        </li><br>

    <a id="FHEMWEB-attr-nameDisplay"></a>
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

    <a id="FHEMWEB-attr-nrAxis"></a>
    <li>nrAxis<br>
        (bei mehrfach-Y-Achsen im SVG-Plot) Die Darstellung der Y Achsen
        ben&ouml;tigt Platz. Hierdurch geben Sie an wie viele Achsen Sie
        links,rechts [useLeft,useRight] ben&ouml;tigen. Default ist 1,1 (also 1
        Achse links, 1 Achse rechts).
        </li><br>

    <a id="FHEMWEB-attr-ploteditor"></a>
    <li>ploteditor<br>
        Gibt an ob der <a href="#plotEditor">Plot Editor</a> in der SVG detail
        ansicht angezeigt werden soll.  Kann auf always, onClick oder never
        gesetzt werden. Der Default ist always.
        </li><br>

    <a id="FHEMWEB-attr-plotEmbed"></a>
    <li>plotEmbed<br>
        Falls 1, dann werden SVG Grafiken mit &lt;embed&gt; Tags
        gerendert, da auf &auml;lteren Browsern das die einzige
        M&ouml;glichkeit war, SVG dastellen zu k&ouml;nnen. Falls 0, dann
        werden die SVG Grafiken "in-place" gezeichnet.  Falls 2, dann werden
        die Grafiken per JavaScript nachgeladen, um eine Parallelisierung auch
        ohne embed Tags zu erm&ouml;glichen.
        Die Voreinstellung ist 2 auf Mehrprozessor-Linux-Rechner und 0 sonst.
    </li><br>

    <a id="FHEMWEB-attr-plotfork"></a>
    <li>plotfork<br>
        Falls gesetzt, dann werden bestimmte Berechnungen (z.Bsp. SVG und RSS)
        auf nebenl&auml;ufige Prozesse verteilt. Voreinstellung ist 0. Achtung:
        nicht auf Systemen mit wenig Hauptspeicher verwenden.
        </li><br>

    <a id="FHEMWEB-attr-plotmode"></a>
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

    <a id="FHEMWEB-attr-plotsize"></a>
    <li>plotsize<br>
        gibt die Standardbildgr&ouml;&szlig;e aller erzeugten Plots an als
        Breite,H&ouml;he an. Um einem individuellen Plot die Gr&ouml;&szlig;e zu
        &auml;ndern muss dieses Attribut bei der entsprechenden SVG Instanz
        gesetzt werden.  Default sind 800,160 f&uuml;r Desktop und 480,160
        f&uuml;r Smallscreen
        </li><br>

    <a id="FHEMWEB-attr-plotWeekStartDay"></a>
    <li>plotWeekStartDay<br>
        Starte das Plot in der Wochen-Ansicht mit diesem Tag.
        0 ist Sonntag, 1 ist Montag, usw.
    </li><br>

    <a id="FHEMWEB-attr-redirectCmds"></a>
    <li>redirectCmds<br>
        Damit wird das URL Eingabefeld des Browser nach einem Befehl geleert.
        Standard ist eingeschaltet (1), ausschalten kann man es durch
        setzen des Attributs auf 0, z.Bsp. um den Syntax der Kommunikation mit
        FHEMWEB zu untersuchen.
        </li><br>

    <a id="FHEMWEB-attr-redirectTo"></a>
    <li>redirectTo<br>
        Falls gesetzt, und FHEMWEB eine Anfrage nicht bedienen kann, wird die
        Seite nach $FW_ME/$redirectTo$arg umgeleitet. Falls nicht gesetzt, dann
        nach $FW_ME. Falls der Wert den Form eventFor:<regexp> hat, und $arg
        auf <regexp> passt, dann wird ein Event mit der FHEMWEB Instanz und
        $arg generiert.
        </li>
        <br>

    <a id="FHEMWEB-attr-refresh"></a>
    <li>refresh<br>
        Damit erzeugen Sie auf den ausgegebenen Webseiten einen automatischen
        Refresh, z.B. nach 5 Sekunden.
        </li><br>

    <a id="FHEMWEB-attr-rescueDialog"></a>
    <li>rescueDialog<br>
        Falls gesetzt, im Menue wird ein Rescue Link angezeigt. Das Ziel ist
        von jemanden mit mehr Wissen (Retter) Hilfe zu bekommen, indem er die
        lokale FHEM-Installation fernsteuert.<br>
        Nach &ouml;ffnen des Dialogs wird ein Schl&uuml;ssel angezeigt, was dem
        Retter zu schicken ist. Nachdem er diesen Schl&uuml;ssel bei sich
        installiert hat, muss seine Adresse (Host und Port) im Dialog
        eingetragen werden. Danach kann er die Verbindung fernsteuern.
        <br><br>

        <b>TODO f&uuml;r den Retter:</b>
        <ul>
          <li>eine &ouml;ffentliche IP/PORT Kombination zum eigenen SSH Server
              weiterleiten.</li>

          <li>einen fhemrescue Benutzer auf diesem Server anlegen, und den
              Schl&uuml;ssel vom Hilfesuchenden eintragen:<br>
            <ul><code>
            useradd -d /tmp -s /bin/false fhemrescue<br>
            echo "KEY_FROM_THE_CLIENT" > /etc/sshd/fhemrescue.auth<br>
            chown fhemrescue:fhemrescue /etc/sshd/fhemrescue.auth<br>
            chmod 600 /etc/sshd/fhemrescue.auth
            </code></ul>
            </li>
          <li>Zu /etc/ssh/sshd_config Folgendes hinzuf&uuml;gen:<br>
            <ul><code>
              Match User fhemrescue<br>
              <ul>
                AllowTcpForwarding remote<br>
                PermitTTY no<br>
                GatewayPorts yes<br>
                ForceCommand /bin/false<br>
                AuthorizedKeysFile /etc/ssh/fhemrescue.auth<br>
              </ul>
            </code></ul>
            </li>
          <li>sshd neu starten, z.Bsp. mit systemctl restart sshd
            </li>
          <li>Dem Hilfesuchenden die &ouml;ffentliche IP/PORT Kombination
            mitteilen.</li>
          <li>Nachdem der Hilfesuchende diese Daten eingegeben hat, und die
            Verbindung gestartet hat, kann die Remote-FHEM-Installation ueber
            den eigenen SSH-Server, Port 1803 erreicht wedern.</li>
        </ul>
        </li><br>

    <a id="FHEMWEB-attr-reverseLogs"></a>
    <li>reverseLogs<br>
        Damit wird das Logfile umsortiert, die neuesten Eintr&auml;ge stehen
        oben.  Der Vorteil ist, dass man nicht runterscrollen muss um den
        neuesten Eintrag zu sehen, der Nachteil dass FHEM damit deutlich mehr
        Hauptspeicher ben&ouml;tigt, etwa 6 mal so viel, wie das Logfile auf
        dem Datentr&auml;ger gro&szlig; ist. Das kann auf Systemen mit wenig
        Speicher (FRITZ!Box) zum Terminieren des FHEM Prozesses durch das
        Betriebssystem f&uuml;hren.
        </li><br>

    <a id="FHEMWEB-attr-roomIcons"></a>
    <li>roomIcons<br>
        Leerzeichen getrennte Liste von room:icon Zuordnungen
        Der erste Teil wird als regexp interpretiert, daher muss ein
        Leerzeichen als Punkt geschrieben werden. Beispiel:<br>
          attr WEB roomIcons Anlagen.EDV:icoEverything
        </li><br>

    <a id="FHEMWEB-attr-sortby"></a>
    <li>sortby<br>
        Der Wert dieses Attributs wird zum sortieren von Ger&auml;ten in
        R&auml;umen verwendet, sonst w&auml;re es der Alias oder, wenn keiner
        da ist, der Ger&auml;tename selbst. Falls der Wert des sortby
        Attributes in {} eingeschlossen ist, dann wird er als ein perl Ausdruck
        evaluiert. $NAME wird auf dem Ger&auml;tenamen gesetzt.
        </li><br>

    <a id="FHEMWEB-attr-showUsedFiles"></a>
    <li>showUsedFiles<br>
        Zeige nur die verwendeten Dateien in der "Edit files" Abschnitt.
        Achtung: aktuell ist das nur f&uuml;r den "Gplot files" Abschnitt
        implementiert.
        </li>
        <br>

    <a id="FHEMWEB-attr-sortRooms"></a>
    <li>sortRooms<br>
        Durch Leerzeichen getrennte Liste von R&auml;umen, um deren Reihenfolge
        zu definieren.
        Da die R&auml;ume in diesem Attribut als Regexp interpretiert werden,
        sind Leerzeichen im Raumnamen als Punkt (.) zu hinterlegen.
        Beispiel:<br>
          attr WEB sortRooms DG OG EG Keller
        </li><br>

    <a id="FHEMWEB-attr-smallscreenCommands"></a>
    <li>smallscreenCommands<br>
      Falls auf 1 gesetzt werden Kommandos, Slider und Dropdown Men&uuml;s im
      Smallscreen Landscape Modus angezeigt.
      </li><br>

    <li>sslVersion<br>
      Siehe das global Attribut sslVersion.
      </li><br>

    <a id="FHEMWEB-attr-sslCertPrefix"></a>
    <li>sslCertPrefix<br>
       Setzt das Pr&auml;fix der SSL-Zertifikate, die Voreinstellung ist
       certs/server-, siehe auch das HTTP Attribut.
       </li><br>

    <a id="FHEMWEB-attr-styleData"></a>
    <li>styleData<br>
      wird von dynamischen styles wie f18 werwendet
      </li><br>

    <a id="FHEMWEB-attr-stylesheetPrefix"></a>
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

    <a id="FHEMWEB-attr-SVGcache"></a>
    <li>SVGcache<br>
        Plots die sich nicht mehr &auml;ndern, werden im SVGCache Verzeichnis
        (www/SVGcache) gespeichert, um die erneute, rechenintensive
        Berechnung der Grafiken zu vermeiden. Default ist 0, d.h. aus.<br>
        Siehe den clearSvgCache Befehl um diese Daten zu l&ouml;schen.
        </li><br>

    <a id="FHEMWEB-attr-title"></a>
    <li>title<br>
       Setzt den Titel der Seite. Falls in {} eingeschlossen, dann wird es
       als Perl Ausdruck evaluiert.
    </li><br>

    <a id="FHEMWEB-attr-viewport"></a>
    <li>viewport<br>
       Setzt das &quot;viewport&quot; Attribut im HTML Header. Das kann benutzt
       werden um z.B. die Breite fest vorzugeben oder Zoomen zu verhindern.<br>
       Beispiel: attr WEB viewport
       width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no
    </li><br>

    <a id="FHEMWEB-attr-webCmd"></a>
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

    <a id="FHEMWEB-attr-webCmdLabel"></a>
    <li>webCmdLabel<br>
        Durch Doppelpunkte getrennte Auflistung von Texten, die vor dem
        jeweiligen webCmd angezeigt werden. Der Anzahl der Texte muss exakt den
        Anzahl der webCmds entsprechen. Um mehrzeilige Anzeige zu realisieren,
        kann ein Return nach dem Text und vor dem Doppelpunkt eingefuehrt
        werden.</li><br>

    <a id="FHEMWEB-attr-webname"></a>
    <li>webname<br>
        Der Pfad nach http://hostname:port/ . Standard ist fhem,
        so ist die Standard HTTP Adresse http://localhost:8083/fhem
        </li><br>

    <a id="FHEMWEB-attr-widgetOverride"></a>
    <li>widgetOverride<br>
        Leerzeichen separierte Liste von Name:Modifier Paaren, mit dem man den
        vom Modulautor f&uuml;r einen bestimmten Parameter (Set/Get/Attribut)
        vorgesehenes Widget &auml;ndern kann.  Die Syntax f&uuml;r eine
        Typspezifische &Auml;nderung ist Name@Typ:Modifier, wobei Typ set, get
        oder attr sein kann. Folgendes ist die Liste der bekannten Modifier:
        <ul>
        <!-- INSERT_DOC_FROM: www/pgm2/fhemweb.*.js -->
        </ul></li>

    </ul>
  </ul>

=end html_DE

=cut
