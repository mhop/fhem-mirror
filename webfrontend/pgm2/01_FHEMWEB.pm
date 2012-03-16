##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::Socket;

#########################
# Forward declaration
sub FW_AnswerCall($);
sub FW_calcWeblink($$);
sub FW_dev2image($);
sub FW_digestCgi($);
sub FW_doDetail($);
sub FW_dumpFileLog($$$);
sub FW_fatal($);
sub FW_fileList($);
sub FW_logWrapper($);
sub FW_makeEdit($$$);
sub FW_makeTable($$@);
sub FW_ReadIcons();
sub FW_roomOverview($);
sub FW_select($$$$);
sub FW_showLog($);
sub FW_showRoom();
sub FW_showWeblink($$$$);
sub FW_style($$);
sub FW_submit($$);
sub FW_substcfg($$$$$$);
sub FW_textfield($$$);
sub FW_updateHashes();
sub FW_zoomLink($$$);
sub pF($@);
sub FW_pH(@);
sub FW_pHPlain(@);
sub FW_pO(@);

use vars qw($FW_dir);  # moddir (./FHEM), needed by SVG
use vars qw($FW_ME);   # webname (default is fhem), needed by 97_GROUP
use vars qw($FW_ss);   # is smallscreen, needed by 97_GROUP/95_VIEW
use vars qw($FW_tp);   # is touchpad (iPad / etc)

# global variables, also used by 97_GROUP/95_VIEW/95_FLOORPLAN
use vars qw(%FW_types);  # device types,
use vars qw($FW_RET);    # Returned data (html)
use vars qw($FW_wname);  # Web instance
use vars qw($FW_subdir); # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
use vars qw(%FW_pos);    # scroll position

my $zlib_loaded;
my $try_zlib = 1;

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my %FW_webArgs;    # all arguments specifie in the GET
my $FW_cmdret;     # Returned data by the fhem call
my $FW_data;       # Filecontent from browser when editing a file
my $FW_detail;     # currently selected device for detail view
my %FW_devs;       # hash of from/to entries per device
my %FW_icons;      # List of icons
my $FW_iconsread;  # Timestamp of last icondir check
my $FW_plotmode;   # Global plot mode (WEB attribute)
my $FW_plotsize;   # Global plot size (WEB attribute)
my $FW_reldoc;     # $FW_ME/commandref.html;
my $FW_RETTYPE;    # image/png or the like
my $FW_room;       # currently selected room
my %FW_rooms;      # hash of all rooms
my %FW_types;      # device types, for sorting
my $FW_cname;      # Current connection
my @FW_zoom;       # "qday", "day","week","month","year"
my %FW_zoom;       # the same as @FW_zoom
my %FW_hiddenroom; # hash of hidden rooms
my $FW_longpoll;
my $FW_inform;
my $FW_XHR;
my $FW_jsonp;
#my $FW_encoding="ISO-8859-1";
my $FW_encoding="UTF-8";


#####################################
sub
FHEMWEB_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FW_Read";
  $hash->{AttrFn}  = "FW_Attr";
  $hash->{DefFn}   = "FW_Define";
  $hash->{UndefFn} = "FW_Undef";
  $hash->{NotifyFn}= "FW_Notify";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 webname fwmodpath fwcompress " .
                     "plotmode:gnuplot,gnuplot-scroll,SVG plotsize refresh " .
                     "touchpad smallscreen plotfork basicAuth basicAuthMsg ".
                     "stylesheetPrefix hiddenroom HTTPS longpoll redirectCmds ";

  ###############
  # Initialize internal structures
  my $n = 0;
  @FW_zoom = ("qday", "day","week","month","year");
  %FW_zoom = map { $_, $n++ } @FW_zoom;

  addToAttrList("webCmd");
  addToAttrList("icon");
}

#####################################
sub
FW_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB <tcp-portnr> [global]"
        if($port !~ m/^(IPV6:)?\d+$/ || ($global && $global ne "global"));

  if($port =~ m/^IPV6:(\d+)$/i) {
    $port = $1;
    eval "require IO::Socket::INET6; use Socket6;";
    if($@) {
      Log 1, $@;
      Log 1, "Can't load INET6, falling back to IPV4";
    } else {
      $hash->{IPV6} = 1;
    }
  }

  my @opts = (
    Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC), # Linux bug
    LocalHost => ($global ? undef : "localhost"),
    LocalPort => $port,
    Listen    => 10,
    ReuseAddr => 1
  );
  $hash->{STATE} = "Initialized";
  $hash->{SERVERSOCKET} = $hash->{IPV6} ?
        IO::Socket::INET6->new(@opts) : 
        IO::Socket::INET->new(@opts);

  if(!$hash->{SERVERSOCKET}) {
    my $msg = "Can't open server port at $port: $!";
    Log 1, $msg;
    return $msg;
  }

  $hash->{FD} = $hash->{SERVERSOCKET}->fileno();
  $hash->{PORT} = $port;

  $selectlist{"$name.$port"} = $hash;
  Log(2, "FHEMWEB port $port opened");
  return undef;
}

#####################################
sub
FW_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  return undef if($hash->{INUSE});

  if(defined($hash->{CD})) { # Clients
    close($hash->{CD});
    delete($selectlist{$name});
  }
  if(defined($hash->{SERVERSOCKET})) {          # Server
    close($hash->{SERVERSOCKET});
    $name = $name . "." . $hash->{PORT};
    delete($selectlist{$name});
  }
  return undef;
}

#####################################
sub
FW_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if($hash->{SERVERSOCKET}) {   # Accept and create a child

    my $ll = GetLogLevel($name,4);
    my @clientinfo = $hash->{SERVERSOCKET}->accept();
    if(!@clientinfo) {
      Log(1, "Accept failed for HTTP port ($name: $!)");
      return;
    }
    $hash->{CONNECTS}++;

    my @clientsock = $hash->{IPV6} ? 
        sockaddr_in6($clientinfo[1]) :
        sockaddr_in($clientinfo[1]);

    my %nhash;
    my $cname = "FHEMWEB:".
        ($hash->{IPV6} ?
                inet_ntop(AF_INET6(), $clientsock[1]) :
                inet_ntoa($clientsock[1])) .":".$clientsock[0];
    $nhash{NR}    = $devcount++;
    $nhash{NAME}  = $cname;
    $nhash{FD}    = $clientinfo[0]->fileno();
    $nhash{CD}    = $clientinfo[0];     # sysread / close won't work on fileno
    $nhash{TYPE}  = "FHEMWEB";
    $nhash{STATE} = "Connected";
    $nhash{SNAME} = $name;
    $nhash{TEMPORARY} = 1;              # Don't want to save it
    $nhash{BUF}   = "";
    $attr{$cname}{room} = "hidden";

    $defs{$nhash{NAME}} = \%nhash;
    $selectlist{$nhash{NAME}} = \%nhash;

    if($hash->{SSL}) {
      # Certs directory must be in the modpath, i.e. at the same level as the FHEM directory
      my $mp = AttrVal("global", "modpath", ".");
      my $ret = IO::Socket::SSL->start_SSL($nhash{CD}, {
        SSL_server    => 1, 
        SSL_key_file  => "$mp/certs/server-key.pem",
        SSL_cert_file => "$mp/certs/server-cert.pem",
        });
      Log 1, "FHEMWEB HTTPS: $!" if(!$ret && $! ne "Socket is not connected");
    }

    Log($ll, "Connection accepted from $nhash{NAME}");
    return;
  }

  $FW_wname = $hash->{SNAME};
  $FW_cname = $name;
  $FW_subdir = "";

  my $ll = GetLogLevel($FW_wname,4);
  my $c = $hash->{CD};
  if(!$zlib_loaded && $try_zlib && AttrVal($FW_wname, "fwcompress", 1)) {
    $zlib_loaded = 1;
    eval { require Compress::Zlib; };
    if($@) {
      $try_zlib = 0;
      Log 1, $@;
      Log 1, "$FW_wname: Can't load Compress::Zlib, deactivating compression";
      $attr{$FW_wname}{fwcompress} = 0;
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

  #Log 0, "Got: >$hash->{BUF}<";
  my @lines = split("[\r\n]", $hash->{BUF});

  #############################
  # BASIC HTTP AUTH
  my $basicAuth = AttrVal($FW_wname, "basicAuth", undef);
  if($basicAuth) {
    my @auth = grep /^Authorization: Basic $basicAuth/, @lines;
    if(!@auth) {
      my $msg = AttrVal($FW_wname, "basicAuthMsg", "Fhem: login required");
      print $c "HTTP/1.1 401 Authorization Required\r\n",
             "WWW-Authenticate: Basic realm=\"$msg\"\r\n",
             "Content-Length: 0\r\n\r\n";
      return;
    };
  }
  #############################
  
  my @enc = grep /Accept-Encoding/, @lines;
  my ($mode, $arg, $method) = split(" ", $lines[0]);
  $hash->{BUF} = "";

  Log $ll, "HTTP $name GET $arg";
  my $pid;
  if(AttrVal($FW_wname, "plotfork", undef)) {
    # Process SVG rendering as a parallel process
    return if(($arg =~ m/cmd=showlog/) && ($pid = fork));
  }

  $hash->{INUSE} = 1;
  my $cacheable = FW_AnswerCall($arg);
  delete($hash->{INUSE});
  return if($cacheable == -1); # Longpoll / inform request;

  if(!$selectlist{$name}) {             # removed by rereadcfg, reinsert
    $selectlist{$name} = $hash;
    $defs{$name} = $hash;
  }

  my $compressed = "";
  if(($FW_RETTYPE=~m/text/i ||
      $FW_RETTYPE=~m/svg/i ||
      $FW_RETTYPE=~m/script/i) &&
     (int(@enc) == 1 && $enc[0] =~ m/gzip/) &&
     $try_zlib &&
     AttrVal($FW_wname, "fwcompress", 1)) {
    $FW_RET = Compress::Zlib::memGzip($FW_RET);
    $compressed = "Content-Encoding: gzip\r\n";
  }

  my $length = length($FW_RET);
  my $expires = ($cacheable?
                        ("Expires: ".localtime(time()+900)." GMT\r\n") : "");
  Log $ll, "$arg / RL: $length / $FW_RETTYPE / $compressed / $expires";
  print $c "HTTP/1.1 200 OK\r\n",
           "Content-Length: $length\r\n",
           $expires, $compressed,
           "Content-Type: $FW_RETTYPE\r\n\r\n",
           $FW_RET;
  exit if(defined($pid));
}

###########################
sub
FW_AnswerCall($)
{
  my ($arg) = @_;
  my $me=$defs{$FW_cname};      # cache, else rereadcfg will delete us

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=$FW_encoding";
  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
  $FW_dir = AttrVal($FW_wname, "fwmodpath", "$attr{global}{modpath}/FHEM");
  $FW_ss = AttrVal($FW_wname, "smallscreen", 0);
  $FW_tp = AttrVal($FW_wname, "touchpad", $FW_ss);

  # Lets go:
  if($arg =~ m,^${FW_ME}/(example.*|.*html)$,) {
    my $f = $1;
    $f =~ s,/,,g;    # little bit of security
    open(FH, "$FW_dir/$f") || return 0;
    FW_pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "text/plain; charset=$FW_encoding" if($f !~ m/\.*html$/);
    return 1;

  } elsif($arg =~ m,^$FW_ME/(.*).css,) {
    my $cssName = $1;
    return 0 if(!open(FH, "$FW_dir/$cssName.css"));
    FW_pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "text/css";
    return 1;

  } elsif($arg =~ m,^$FW_ME/icons/(.*)$, ||
          $arg =~ m,^$FW_ME/(.*.png)$,i) {
    my $img = $1;
    my $cachable = 1;
    if(!open(FH, "$FW_dir/$img")) {
      FW_ReadIcons();
      $img = FW_dev2image($img);
      $cachable = 0;
      return 0 if(!$img || !open(FH, "$FW_dir/$img"));
    }
    binmode (FH); # necessary for Windows
    FW_pO join("", <FH>);
    close(FH);
    my @f_ext = split(/\./,$img); #kpb
    $FW_RETTYPE = "image/$f_ext[-1]";
    return $cachable;

 } elsif($arg =~ m,^$FW_ME/(.*).js,) { #kpb java include
    open(FH, "$FW_dir/$1.js") || return 0;
    FW_pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "application/javascript";
    return 1;

  } elsif($arg !~ m/^$FW_ME(.*)/) {
    Log(5, "Unknown document $arg requested");
    return 0;

  }

  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" :
                                                $FW_tp ? "640,160" : "800,160");
  ##############################
  # Axels FHEMWEB modules...
  $arg = $1;
  my $fwextPtr;
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      if($arg =~ m/^$k/) {

        if($data{FWEXT}{$k}{EMBEDDED}) {
          $fwextPtr = $data{FWEXT}{$k};
          last;

        } else {
          no strict "refs";
          ($FW_RETTYPE, $FW_RET) = &{$data{FWEXT}{$k}{FUNC}}($arg);
          use strict "refs";
          return 0;

        }

      }
    }
  }

  my $cmd = FW_digestCgi($arg);
  my $docmd = 0;
  $docmd = 1 if($cmd && 
                $cmd !~ /^showlog/ &&
                $cmd !~ /^logwrapper/ &&
                $cmd !~ /^toweblink/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  $FW_reldoc = "$FW_ME/commandref.html";
  $FW_cmdret = $docmd ? FW_fC($cmd) : "";

  if($FW_inform) {      # Longpoll header
    $me->{inform} = ($FW_room ? $FW_room : $FW_inform);
    # NTFY_ORDER is larger than the normal order (50-)
    $me->{NTFY_ORDER} = $FW_cname;   # else notifyfn won't be called
    my $c = $me->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
             "Content-Type: text/plain; charset=$FW_encoding\r\n\r\n";
    return -1;
  }

  if($FW_XHR || $FW_jsonp) {
    $FW_RETTYPE = "text/plain; charset=$FW_encoding";
    if($FW_jsonp) {
      $FW_cmdret =~ s/'/\\'/g;
      FW_pO "$FW_jsonp('$FW_cmdret');";
    } else {
      FW_pO $FW_cmdret;
    }
    return 0;
  }

  # Redirect after a command, to clean the browser URL window
  if($docmd && !$FW_cmdret && AttrVal($FW_wname, "redirectCmds", 1)) {
    my $tgt = $FW_ME;
       if($FW_detail) { $tgt .= "?detail=$FW_detail" }
    elsif($FW_room)   { $tgt .= "?room=$FW_room" }
    my $c = $me->{CD};
    print $c "HTTP/1.1 302 Found\r\n",
             "Content-Length: 0\r\n",
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

  # Enable WebApp
  if($FW_tp || $FW_ss) {
    FW_pO '<link rel="apple-touch-icon-precomposed" href="'.$FW_ME.'/fhemicon.png"/>';
    FW_pO '<meta name="apple-mobile-web-app-capable" content="yes"/>';
    #FW_pO '<meta name="viewport" content="width=device-width"/>'
    if($FW_ss) {
      FW_pO '<meta name="viewport" content="width=320"/>';
    } elsif($FW_tp) {
      FW_pO '<meta name="viewport" content="width=768"/>';
    }
  }

  my $rf = AttrVal($FW_wname, "refresh", "");
  FW_pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  
  my $prf = AttrVal($FW_wname, "stylesheetPrefix", "");
  $prf = "smallscreen" if(!$prf && $FW_ss);
  $prf = "touchpad"    if(!$prf && $FW_tp);
  FW_pO "<link href=\"$FW_ME/".$prf."style.css\" rel=\"stylesheet\"/>";
  FW_pO "<link href=\"$fwextPtr->{STYLESHEET}\" rel=\"stylesheet\"/>"
                        if($fwextPtr && $fwextPtr->{STYLESHEET});
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/svg.js\"></script>"
                        if($FW_plotmode eq "SVG");
  FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/longpoll.js\"></script>"
                        if($FW_longpoll);
  FW_pO "<script type=\"text/javascript\" src=\"$fwextPtr->{JAVASCRIPT}\"></script>"
                        if($fwextPtr && $fwextPtr->{JAVASCRIPT});
  FW_pO "</head>\n<body name=\"$t\">";

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
     if($fwextPtr)             { &{$fwextPtr->{FUNC}}($arg); }
  elsif($cmd =~ m/^style /)    { FW_style($cmd,undef);    }
  elsif($FW_detail)            { FW_doDetail($FW_detail); }
  elsif($FW_room)              { FW_showRoom();           }
  elsif($cmd =~ /^logwrapper/) { FW_logWrapper($cmd);     }
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
  $arg =~ s,^[?/],,;
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
  $cmd.=" $arg{$c}" if(defined($arg{$c}));
  $cmd.=" $val{$c}" if(defined($val{$c}));
  return $cmd;
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
    $FW_types{$t}{$d} = 1;
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
    my $r = ref($hash->{$n});
    next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));
    pF "<tr class=\"%s\">", ($row&1)?"odd":"even";
    $row++;

    my $val = $hash->{$n};

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
  my @al = sort map { s/[:;].*//;$_ } split(" ", $list);

  FW_pO "<form method=\"get\" action=\"$FW_ME$FW_subdir\">";
  FW_pO FW_hidden("detail", $d);
  FW_pO FW_hidden("dev.$cmd$d", $d);
  FW_pO FW_submit("cmd.$cmd$d", $cmd) . "&nbsp;$d";
  FW_pO FW_select("arg.$cmd$d",\@al,undef,$class);
  FW_pO FW_textfield("val.$cmd$d", 30, $class);
  FW_pO "</form>";
}


##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  FW_pO "<form method=\"get\" action=\"$FW_ME\">";
  FW_pO FW_hidden("detail", $d);

  my $t = $defs{$d}{TYPE};
  FW_pO "<div id=\"content\">";
  if($FW_ss) { # FS20MS2 special: on and off, is not the same as toggle
    my $webCmd = AttrVal($d, "webCmd", undef);
    if($webCmd) {
      FW_pO "<table>";
      foreach my $cmd (split(":", $webCmd)) {
        FW_pO "<tr>";
        FW_pH "cmd.$d=set $d $cmd&detail=$d",  ReplaceEventMap($d,$cmd,1), 1, "col1";
        FW_pO "</tr>";
      }
      FW_pO "</table>";
    }
  }
  FW_pO "<table><tr><td>";
  FW_makeSelect($d, "set", getAllSets($d),"set");
  FW_makeTable($d, $defs{$d});
  FW_pO "Readings" if($defs{$d}{READINGS});
  FW_makeTable($d, $defs{$d}{READINGS});
  FW_makeSelect($d, "attr", getAllAttr($d),"attr");
  FW_makeTable($d, $attr{$d}, "deleteattr");


  if($t eq "FileLog" ) {
    FW_pO "<table class=\"block wide\">";
    FW_dumpFileLog($d, 0, 1);
    FW_pO "</table>";
  }

  FW_pO "</td></tr></table>";

  if($t eq "weblink") {
    FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}, 1);
    FW_pO "<br><br>";
  }

  FW_pH "cmd=style iconFor $d", "Select icon";
  FW_pH "$FW_reldoc#${t}", "Device specific help";
  FW_pO "<br><br>";
  FW_pO "</div>";
  FW_pO "</form>";


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
        "<div id=\"back\"><img src=\"$FW_ME/back.png\"></div>";
    FW_pO "<div id=\"menu\">$FW_detail details</div>";
    return;

  } else {
    FW_pO "<div id=\"logo\"></div>";

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
     "Everything", "$FW_ME?room=all",
     "",           "",
     "Howto",      "$FW_ME/HOWTO.html",
     "Wiki",       "http://fhemwiki.de",
#     "FAQ",        "$FW_ME/faq.html",
     "Details",    "$FW_ME/commandref.html",
#     "Examples",   "$FW_ME/cmd=style%20examples",
     "Edit files", "$FW_ME/cmd=style%20list",
     "Select style","$FW_ME/cmd=style%20select",
     "Event monitor","$FW_ME/cmd=style%20eventMonitor",
     "",           "");
  my $lastname = ","; # Avoid double "".
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

    FW_ReadIcons();
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      my ($l1, $l2) = ($list1[$idx], $list2[$idx]);
      if(!$l1) {
        FW_pO "</table></td></tr>" if($idx);
        FW_pO "<tr><td><table id=\"room\">"
          if($idx<int(@list1)-1);
      } else {
        pF "<tr%s>", $l1 eq $FW_room ? " class=\"sel\"" : "";
        my $icon = "";
        $icon = "<img src=\"$FW_ME/icons/".$FW_icons{"ico$l1"}."\">&nbsp;"
                if($FW_icons{"ico$l1"});

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
sub
FW_showRoom()
{
  return if(!$FW_room);

  # (re-) list the icons
  FW_ReadIcons();

  FW_pO "<form method=\"get\" action=\"$FW_ME\">";
  FW_pO "<div id=\"content\">";
  FW_pO "<table>";  # Need for equal width of subtables

  my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room
  my $row=1;
  foreach my $type (sort keys %FW_types) {

    next if(!$type || $type eq "weblink");

    #################
    # Check if there is a device of this type in the room
    $FW_room = "" if(!defined($FW_room));
    my @devs = grep { ($FW_rooms{$FW_room}{$_}||$FW_room eq "all") &&
                      !IsIgnored($_) } keys %{$FW_types{$type}};
    next if(!@devs);

    FW_pO "\n<tr><td><div class=\"devType\">$type</div></td></tr>";
    FW_pO "<tr><td>";
    FW_pO "<table class=\"block wide\" id=\"$type\">";

    foreach my $d (sort @devs) {
      my $type = $defs{$d}{TYPE};

      pF "\n<tr class=\"%s\">", ($row&1)?"odd":"even";
      my $devName = AttrVal($d, "alias", $d);
      my $icon = AttrVal($d, "icon", "");
      $icon = "<img src=\"$FW_ME/icons/$icon\">&nbsp;" if($icon);

      if($FW_hiddenroom{detail}) {
        FW_pO "<td><div class=\"col1\">$icon$devName</div></td>";
      } else {
        FW_pH "detail=$d", "$icon$devName", 1, "col1";
      }
      $row++;

      my ($allSets, $cmdlist, $txt) = FW_devState($d, $rf);
      FW_pO "<td id=\"$d\">$txt";

      if(!$FW_ss) {
        FW_pO "</td>";
        if($cmdlist) {
          foreach my $cmd (split(":", $cmdlist)) {
            FW_pH "cmd.$d=set $d $cmd$rf",  ReplaceEventMap($d,$cmd,1), 1, "col3";
          }

        } elsif($allSets =~ m/ desired-temp /) {
          $txt = ReadingsVal($d, "measured-temp", "");
          $txt =~ s/ .*//;
          $txt = sprintf("%2.1f", int(2*$txt)/2) if($txt =~ m/[0-9.-]/);
          my @tv = split(" ", getAllSets("$d desired-temp"));
          $txt = int($txt*20)/$txt if($txt =~ m/^[0-9].$/);

          FW_pO "<td>".
             FW_hidden("arg.$d", "desired-temp") .
             FW_hidden("dev.$d", $d) .
             FW_select("val.$d", \@tv, ReadingsVal($d, "desired-temp", $txt),"fht") .
             "</td><td>".
             FW_submit("cmd.$d", "set").
             "</td>";
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
  my @list = ($FW_room eq "all" ? keys %defs : keys %{$FW_rooms{$FW_room}});
  foreach my $d (sort @list) {
    next if(IsIgnored($d));
    my $type = $defs{$d}{TYPE};
    next if(!$type || $type ne "weblink");

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
# Show the content of the log (plain text), or an image and offer a link
# to convert it to a weblink
sub
FW_logWrapper($)
{
  my ($cmd) = @_;
  my (undef, $d, $type, $file) = split(" ", $cmd, 4);

  if($type eq "text") {
    $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path = AttrVal($d,"archivedir","") . "/$file" if(!-f $path);

    if(!open(FH, $path)) {
      FW_pO "<div id=\"content\">$path: $!</div>";
      return;
    }
    binmode (FH); # necessary for Windows
    my $cnt = join("", <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;

    FW_pO "<div id=\"content\">";
    FW_pO "<div class=\"tiny\">" if($FW_ss);
    FW_pO "<pre>$cnt</pre>";
    FW_pO "</div>" if($FW_ss);
    FW_pO "</div>";

  } else {
    FW_pO "<div id=\"content\">";
    FW_pO "<br>";
    FW_zoomLink("cmd=$cmd;zoom=-1", "Zoom-in.png", "zoom in");
    FW_zoomLink("cmd=$cmd;zoom=1",  "Zoom-out.png","zoom out");
    FW_zoomLink("cmd=$cmd;off=-1",  "Prev.png",    "prev");
    FW_zoomLink("cmd=$cmd;off=1",   "Next.png",    "next");
    FW_pO "<table><tr><td>";
    FW_pO "<td>";
    my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);
    my $arg = "$FW_ME?cmd=showlog undef $d $type $file$wl";
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
}

sub
FW_readgplotfile($$$)
{
  my ($wl, $gplot_pgm, $file) = @_;
  
  ############################
  # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
  # the plot directive with our own, as we offer a file for each line
  my (@filelog, @data, $plot);
  open(FH, $gplot_pgm) || return (FW_fatal("$gplot_pgm: $!"), undef);
  while(my $l = <FH>) {
    $l =~ s/\r//g;
    if($l =~ m/^#FileLog (.*)$/) {
      push(@filelog, $1);
    } elsif($l =~ "^plot" || $plot) {
      $plot .= $l;
    } else {
      push(@data, $l);
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

  $title = AnalyzeCommand(undef, "{ $title }");
  my $label = AttrVal($wl, "label", undef);
  my @g_label;
  if ($label) {
    @g_label = split("::",$label);
    foreach (@g_label) {
      $_ = AnalyzeCommand(undef, "{ $_ }");
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

  my $gplot_pgm = "$FW_dir/$type.gplot";

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
    $ret = FW_fC("get $d $file INT $f $t " . join(" ", @{$flog}));
    ($cfg, $plot) = FW_substcfg(1, $wl, $cfg, $plot, $file, "<OuT>");
    FW_pO SVG_render($wl, $f, $t, $cfg, $internal_data, $plot, $FW_wname, $FW_dir);
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
FW_select($$$$)
{
  my ($n, $va, $def,$class) = @_;
  my $s = "<select name=\"$n\" class=\"$class\">";

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
FW_textfield($$$)
{
  my ($n, $z, $class) = @_;
  return if($FW_hiddenroom{input});
  my $s = "<input type=\"text\" name=\"$n\" class=\"$class\" size=\"$z\"/>";
  return $s;
}

##################
sub
FW_submit($$)
{
  my ($n, $v) = @_;
  my $s ="<input type=\"submit\" name=\"$n\" value=\"$v\"/>";
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
    my $t = $now - ($l[6]*86400) + ($off*86400)*7;
    @l = localtime($t);
    $FW_devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

    @l = localtime($t+7*86400);
    $FW_devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);


  } elsif($zoom eq "month") {

    my @l = localtime($now);
    while($off < -12) {
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $FW_devs{$d}{from} = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $FW_devs{$d}{to}   = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

  } elsif($zoom eq "year") {

    my @l = localtime($now);
    $l[5] += $off;
    $FW_devs{$d}{from} = sprintf("%04d", $l[5]+1900);
    $FW_devs{$d}{to}   = sprintf("%04d", $l[5]+1901);

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

    my @fl = ("fhem.cfg");
    push(@fl, "");
    push(@fl, FW_fileList("$FW_dir/.*(sh|Util.*|cfg|holiday)"));
    push(@fl, "");
    push(@fl, FW_fileList("$FW_dir/.*.(css|svg)"));
    push(@fl, "");
    push(@fl, FW_fileList("$FW_dir/.*.gplot"));

    FW_pO $start;
    FW_pO "$msg<br><br>" if($msg);
    FW_pO "<table class=\"block\" id=\"at\">";
    my $row = 0;
    foreach my $file (@fl) {
      FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      if($file eq "") {
        FW_pO "<td><br></td>";
      } else {
        FW_pH "cmd=style edit $file", $file, 1;
      }
      FW_pO "</tr>";
      $row = ($row+1)%2;
    }
    FW_pO "</table>$end";

  } elsif($a[1] eq "select") {

    my @fl = FW_fileList("$FW_dir/.*style.css");

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
    FW_pO "${start}Reload the page in the browser.$end";

  } elsif($a[1] eq "examples") {

    my @fl = FW_fileList("$FW_dir/example.*");
    FW_pO "$start<table class=\"block\" id=\"at\">";
    my $row = 0;
    foreach my $file (@fl) {
      FW_pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      FW_pO "<td><a href=\"$FW_ME/$file\">$file</a></td>"; 
      FW_pO "</tr>";
      $row = ($row+1)%2;
    }
    FW_pO "</table>$end";

  } elsif($a[1] eq "edit") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$FW_dir/$a[2]");
    if(!open(FH, $f)) {
      FW_pO "$f: $!";
      return;
    }
    my $data = join("", <FH>);
    close(FH);

    my $ncols = $FW_ss ? 40 : 80;
    FW_pO "<div id=\"content\">";
    FW_pO "<form>";
    $f =~ s,^.*/,,;
    FW_pO     FW_submit("save", "Save $f");
    FW_pO     "&nbsp;&nbsp;";
    FW_pO     FW_submit("saveAs", "Save as");
    FW_pO     FW_textfield("saveName", 30, "saveName");
    FW_pO     "<br><br>";
    FW_pO     FW_hidden("cmd", "style save $a[2]");
    FW_pO     "<textarea name=\"data\" cols=\"$ncols\" rows=\"30\">" .
                "$data</textarea>";
    FW_pO   "</form>";
    FW_pO "</div>";

  } elsif($a[1] eq "save") {
    my $fName = $a[2];
    $fName = $FW_webArgs{saveName}
        if($FW_webArgs{saveAs} && $FW_webArgs{saveName});
    $fName =~ s,/,,g;    # little bit of security
    $fName = ($fName eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$FW_dir/$fName");
    if(!open(FH, ">$fName")) {
      FW_pO "$fName: $!";
      return;
    }
    $FW_data =~ s/\r//g if($^O !~ m/Win/);
    binmode (FH);
    print FH $FW_data;
    close(FH);
    my $ret = FW_fC("rereadcfg") if($fName eq $attr{global}{configfile});
    $ret = ($ret ? "<h3>ERROR:</h3><b>$ret</b>" : "Saved the file $fName");
    FW_style("style list", $ret);
    $ret = "";

  } elsif($a[1] eq "iconFor") {
    FW_ReadIcons();
    FW_pO "<div id=\"content\"><table class=\"iconFor\">";
    foreach my $i (sort grep {/^ico/} keys %FW_icons) {
      FW_pO "<tr><td>";
      FW_pO "<a href=\"$FW_ME?cmd=attr $a[2] icon $FW_icons{$i}\">$i</a>";
      FW_pO "</td><td>";
      FW_pO "<img src=\"$FW_ME/icons/$FW_icons{$i}\">";
      FW_pO "</td></tr>";
    }
    FW_pO "</table></div>";

  } elsif($a[1] eq "eventMonitor") {
    FW_pO "<script type=\"text/javascript\" src=\"$FW_ME/console.js\"></script>";
    FW_pO "<div id=\"content\">";
    FW_pO "<div id=\"console\">";
    FW_pO "Events:<br>\n";
    FW_pO "</div>";
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
FW_fC($)
{
  my ($cmd) = @_;
  my $ret = AnalyzeCommand(undef, $cmd);
  return $ret;
}

##################
sub
FW_showWeblink($$$$)
{
  my ($d, $v, $t, $buttons) = @_;

  my $attr = AttrVal($d, "htmlattr", "");

  if($t eq "htmlCode") {
    $v = AnalyzePerlCommand(undef, $v) if($v =~ m/^{(.*)}$/);
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


  } elsif($t eq "fileplot") {

    # plots navigation buttons
    if($buttons && 
       $defs{$d}{WLTYPE} eq "fileplot" &&
       !AttrVal($d, "fixedrange", undef)) {

      FW_zoomLink("zoom=-1", "Zoom-in.png", "zoom in");
      FW_zoomLink("zoom=1",  "Zoom-out.png","zoom out");
      FW_zoomLink("off=-1",  "Prev.png",    "prev");
      FW_zoomLink("off=1",   "Next.png",    "next");
      $buttons = 0;
      FW_pO "<br>";
    }

    my @va = split(":", $v, 3);
    if(@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile}) {
      FW_pO "Broken definition for $d: $v<br>";

    } else {
      if($va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
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

  if($a[0] eq "set" && $a[2] eq "HTTPS") {
    eval "require IO::Socket::SSL";
    if($@) {
      Log 1, $@;
      Log 1, "Can't load IO::Socket::SSL, falling back to HTTP";
    } else {
      $hash->{SSL} = 1;
    }
  }
  return undef;
}

sub
FW_ReadIcons()
{
  my $now = time();
  return if($FW_iconsread && ($now - $FW_iconsread) <= 5);
  %FW_icons = ();
  if(opendir(DH, $FW_dir)) {
    my @files = readdir(DH);
    closedir(DH);
    foreach my $l (sort @files) {     # Order: .gif,.jpg,.png
      next if($l !~ m/\.(png|gif|jpg)$/i);
      my $x = $l;
      $x =~ s/\.[^.]+$//;	# Cut .gif/.jpg
      $FW_icons{$x} = $l;
    }
  }
  $FW_iconsread = $now;
}

sub
FW_dev2image($)
{
  my ($name) = @_;
  my $icon = "";
  return $icon if(!$name || !$defs{$name});

  my ($type, $state) = ($defs{$name}{TYPE}, $defs{$name}{STATE});
  return $icon if(!$type || !$state);

  $state =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"
  $icon = $FW_icons{$state}         if($FW_icons{$state});         # on.png
  $icon = $FW_icons{$type}          if($FW_icons{$type});          # FS20.png
  $icon = $FW_icons{"$type.$state"} if($FW_icons{"$type.$state"}); # FS20.on.png
  $icon = $FW_icons{$name}          if($FW_icons{$name});          # lamp.png
  $icon = $FW_icons{"$name.$state"} if($FW_icons{"$name.$state"}); # lamp.on.png
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

  if($filter eq "all" || AttrVal($dn, "room", "") eq $filter) {
    FW_ReadIcons();

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

  CommandDelete(undef, $name);
}

sub
FW_devState($$)
{
  my ($d, $rf) = @_;

  my ($allSets, $hasOnOff, $cmdlist, $link);
  my $webCmd = AttrVal($d, "webCmd", undef);

  if(!$webCmd) {
    $allSets = " " . getAllSets($d) . " ";
    $hasOnOff = ($allSets =~ m/ on / && $allSets =~ m/ off /);
    if(!$hasOnOff) {    # Check the eventMap
      my $em = AttrVal($d, "eventMap", "") . " ";
      $hasOnOff = ($em =~ m/:on\b/ && $em =~ m/:off\b/);
    }
  }

  my $state = $defs{$d}{STATE};
  $state = "" if(!defined($state));
  my $txt = $state;

  if(defined(AttrVal($d, "showtime", undef))) {
    my $v = $defs{$d}{READINGS}{state}{TIME};
    $txt = $v if(defined($v));

  } elsif($allSets && $allSets =~ m/ desired-temp /) {
    $txt = ReadingsVal($d, "measured-temp", "");
    $txt =~ s/ .*//;
    $txt .= "&deg;"

  } else {
    my $icon;
    $icon = FW_dev2image($d);
    $txt = "<img src=\"$FW_ME/icons/$icon\" alt=\"$txt\"/>"
                    if($icon);
  }

  $txt = "<div id=\"$d\" align=\"center\" class=\"col2\">$txt</div>";

  if($webCmd) {
    my @a = split(":", $webCmd);
    $link = "cmd.$d=set $d $a[0]";
    $cmdlist = $webCmd;

  } elsif($hasOnOff) {
    $link = "cmd.$d=set $d ".($state eq "on" ? "off":"on");
    $cmdlist = "on:off";

  }

  if($link) {
    my $room = AttrVal($d, "room", undef);
    $link .= "&room=$room" if($room);
    if($FW_longpoll) {
      $txt = "<a onClick=\"cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";

    } elsif($FW_ss || $FW_tp) {
      $txt = "<a onClick=\"location.href='$FW_ME$FW_subdir?$link$rf'\">$txt</a>";

    } else {
      $txt = "<a href=\"$FW_ME$FW_subdir?$link\">$txt</a>";

    }
  }
  return ($allSets, $cmdlist, $txt);
}

#####################################
# This has to be modularized in the future.
sub
WeatherAsHtml($)
{
  my ($d) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a Weather instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "Weather");
  my $imgHome="http://www.google.com";

  my $ret = "<table>";
  $ret .= sprintf('<tr><td><img src="%s%s"></td><td>%s<br>temp %s, hum %s, %s</td></tr>',
        $imgHome, ReadingsVal($d, "icon", ""),
        ReadingsVal($d, "condition", ""),
        ReadingsVal($d, "temp_c", ""), ReadingsVal($d, "humidity", ""),
        ReadingsVal($d, "wind_condition", ""));

  for(my $i=1; $i<=4; $i++) {
    $ret .= sprintf('<tr><td><img src="%s%s"></td><td>%s: %s<br>min %s max %s</td></tr>',
        $imgHome, ReadingsVal($d, "fc${i}_icon", ""),
        ReadingsVal($d, "fc${i}_day_of_week", ""),
        ReadingsVal($d, "fc${i}_condition", ""),
        ReadingsVal($d, "fc${i}_low_c", ""), ReadingsVal($d, "fc${i}_high_c", ""));
  }

  $ret .= "</table>";
  return $ret;
}

1;
