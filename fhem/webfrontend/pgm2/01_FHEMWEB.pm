##############################################
package main;

use strict;
use warnings;
use IO::Socket;

#########################
# Forward declaration
sub FW_digestCgi($);
sub FW_doDetail($);
sub FW_fileList($);
sub FW_makeTable($$$$$$$$);
sub FW_updateHashes();
sub FW_showRoom();
sub FW_showArchive($);
sub FW_showLog($);
sub FW_logWrapper($);
sub FW_showWeblink($$$);
sub FW_select($$$);
sub FW_textfield($$);
sub FW_submit($$);
sub FW_substcfg($$$$$$);
sub FW_style($$);
sub FW_roomOverview($);
sub FW_fatal($);
sub pF($@);
sub pO(@);
sub pH(@);
sub FW_AnswerCall($);
sub FW_zoomLink($$$);
sub FW_calcWeblink($$);

use vars qw($FW_dir); # moddir (./FHEM), needed by SVG
use vars qw($FW_ME);  # webname (fhem), needed by 97_GROUP
my $zlib_loaded;


#########################
# As we are _not_ multithreaded, it is safe to use global variables.
# Note: for delivering SVG plots we fork
my $FW_cmdret;     # Returned data by the fhem call
my $FW_data;       # Filecontent from browser when editing a file
my $FW_detail;     # currently selected device for detail view
my %FW_devs;       # hash of from/to entries per device
my %FW_icons;      # List of icons
my $FW_iconsread;  # Timestamp of last icondir check
my $FW_plotmode;   # Global plot mode (WEB attribute)
my $FW_plotsize;   # Global plot size (WEB attribute)
my %FW_pos;        # scroll position
my $FW_reldoc;     # $FW_ME/commandref.html;
my $FW_RET;        # Returned data (html)
my $FW_RETTYPE;    # image/png or the like
my $FW_room;       # currently selected room
my %FW_rooms;      # hash of all rooms
my $FW_ss;         # smallscreen
my %FW_types;      # device types, for sorting
my $FW_wname;      # Web instance name
my @FW_zoom;       # "qday", "day","week","month","year"
my %FW_zoom;       # the same as @FW_zoom


#####################################
sub
FHEMWEB_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FW_Read";
  $hash->{AttrFn}  = "FW_Attr";
  $hash->{DefFn}   = "FW_Define";
  $hash->{UndefFn} = "FW_Undef";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 webname fwmodpath fwcompress " .
                     "plotmode:gnuplot,gnuplot-scroll,SVG plotsize refresh " .
                     "smallscreen nofork basicAuth basicAuthMsg HTTPS";

  ###############
  # Initialize internal structures
  my $n = 0;
  @FW_zoom = ("qday", "day","week","month","year");
  %FW_zoom = map { $_, $n++ } @FW_zoom;

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
    Domain    => ($hash->{IPV6} ? AF_INET6 : AF_UNSPEC), # Linux bug
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

  if(defined($hash->{CD})) {                   # Clients
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

    my @clientsock = $hash->{IPV6} ? 
        sockaddr_in6($clientinfo[1]) :
        sockaddr_in($clientinfo[1]);

    my %nhash;
    my $cname = "FHEMWEB:".
        ($hash->{IPV6} ?
                inet_ntop(AF_INET6, $clientsock[1]) :
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
      my $ret = IO::Socket::SSL->start_SSL($nhash{CD}, { SSL_server=>1, });
      Log 1, "SSL: $!" if(!$ret && $! ne "Socket is not connected");
    }

    Log($ll, "Connection accepted from $nhash{NAME}");
    return;
  }

  $FW_wname = $hash->{SNAME};
  my $ll = GetLogLevel($FW_wname,4);
  my $c = $hash->{CD};

  if(!$zlib_loaded && AttrVal($FW_wname, "fwcompress", 1)) {
    $zlib_loaded = 1;
    eval { require Compress::Zlib; };
    if($@) {
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
  my $ret = sysread($hash->{CD}, $buf, 1024);

  if(!defined($ret) || $ret <= 0) {
    my $r = CommandDelete(undef, $name);
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

  Log($ll, "HTTP $name GET $arg");
  my $pid;
  if(!AttrVal($FW_wname, "nofork", undef)) {
    # Process SVG rendering as a parallel process
    return if(($arg =~ m/cmd=showlog/) && ($pid = fork));
  }

  $hash->{INUSE} = 1;
  my $cacheable = FW_AnswerCall($arg);

  delete($hash->{INUSE});
  if(!$selectlist{$name}) {             # removed by rereadcfg, reinsert
    $selectlist{$name} = $hash;
    $defs{$name} = $hash;
  }

  my $compressed = "";
  if(($FW_RETTYPE=~m/text/i ||
      $FW_RETTYPE=~m/svg/i ||
      $FW_RETTYPE=~m/script/i) &&
     (int(@enc) == 1 && $enc[0] =~ m/gzip/) &&
     AttrVal($FW_wname, "fwcompress", 1)) {

    $FW_RET = Compress::Zlib::memGzip($FW_RET);
    $compressed = "Content-Encoding: gzip\r\n";
  }

  my $length = length($FW_RET);
  my $expires = ($cacheable?
                        ("Expires: ".localtime(time()+900)." GMT\r\n") : "");
  #Log 0, "$arg / RL: $length / $FW_RETTYPE / $compressed";
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

  $FW_RET = "";
  $FW_RETTYPE = "text/html; charset=ISO-8859-1";
  $FW_ME = "/" . AttrVal($FW_wname, "webname", "fhem");
  $FW_dir = AttrVal($FW_wname, "fwmodpath", "$attr{global}{modpath}/FHEM");
  $FW_ss = AttrVal($FW_wname, "smallscreen", 0);

  # Lets go:
  if($arg =~ m,^${FW_ME}/(.*html)$, || $arg =~ m,^${FW_ME}/(example.*)$,) {
    my $f = $1;
    $f =~ s,/,,g;    # little bit of security
    open(FH, "$FW_dir/$f") || return;
    pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "text/plain; charset=ISO-8859-1" if($f !~ m/\.*html$/);
    return 1;

  } elsif($arg =~ m,^$FW_ME/(.*).css,) {
    open(FH, "$FW_dir/$1.css") || return;
    pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "text/css";
    return 1;

  } elsif($arg =~ m,^$FW_ME/icons/(.*)$, ||
          $arg =~ m,^$FW_ME/(.*.png)$,) {
    open(FH, "$FW_dir/$1") || return;
    binmode (FH); # necessary for Windows
    pO join("", <FH>);
    close(FH);
    my @f_ext = split(/\./,$1); #kpb
    $FW_RETTYPE = "image/$f_ext[-1]";
    return 1;

 } elsif($arg =~ m,^$FW_ME/(.*).js,) { #kpb java include
    open(FH, "$FW_dir/$1.js") || return;
    pO join("", <FH>);
    close(FH);
    $FW_RETTYPE = "application/javascript";
    return 1;

  } elsif($arg !~ m/^$FW_ME(.*)/) {
    Log(5, "Unknown document $arg requested");
    return 0;

  }

  ##############################
  # Axels FHEMWEB modules...
  $arg = $1;
  if(defined($data{FWEXT})) {
    foreach my $k (sort keys %{$data{FWEXT}}) {
      if($arg =~ m/^$k/) {
        no strict "refs";
        ($FW_RETTYPE, $FW_RET) = &{$data{FWEXT}{$k}{FUNC}}($arg);
        use strict "refs";
        return 0;
      }
    }
  }

  my $cmd = FW_digestCgi($arg);
  my $docmd = 0;
  $docmd = 1 if($cmd && 
                $cmd !~ /^showlog/ &&
                $cmd !~ /^logwrapper/ &&
                $cmd !~ /^toweblink/ &&
                $cmd !~ /^showarchive/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  $FW_plotmode = AttrVal($FW_wname, "plotmode", "SVG");
  $FW_plotsize = AttrVal($FW_wname, "plotsize", $FW_ss ? "480,160" : "800,160");
  $FW_reldoc = "$FW_ME/commandref.html";

  $FW_cmdret = $docmd ? fC($cmd) : "";
  FW_updateHashes();
  if($cmd =~ m/^showlog /) {
    FW_showLog($cmd);
    return 0;
  }

  if($cmd =~ m/^toweblink (.*)$/) {
    my @aa = split(":", $1);
    my $max = 0;
    for my $d (keys %defs) {
      $max = ($1+1) if($d =~ m/^wl_(\d+)$/ && $1 >= $max);
    }
    $defs{$aa[0]}{currentlogfile} =~ m,([^/]*)$,;
    $aa[2] = "CURRENT" if($1 eq $aa[2]);
    $FW_cmdret = fC("define wl_$max weblink fileplot $aa[0]:$aa[1]:$aa[2]");
    if(!$FW_cmdret) {
      $FW_detail = "wl_$max";
      FW_updateHashes();
    }
  }

  my $t = AttrVal("global", "title", "Home, Sweet Home");

  pO '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  pO '<html xmlns="http://www.w3.org/1999/xhtml">';
  pO "<head>\n<title>$t</title>";

  if($FW_ss) {
    pO '<link rel="apple-touch-icon-precomposed" href="'.$FW_ME.'/fhemicon.png"/>';
    pO '<meta name="apple-mobile-web-app-capable" content="yes"/>';
    pO '<meta name="viewport" content="width=device-width"/>';
  }

  my $rf = AttrVal($FW_wname, "refresh", "");
  pO "<meta http-equiv=\"refresh\" content=\"$rf\">" if($rf);
  my $stylecss = ($FW_ss ? "style_smallscreen.css" : "style.css");
  pO "<link href=\"$FW_ME/$stylecss\" rel=\"stylesheet\"/>";
  pO "<script type=\"text/javascript\" src=\"$FW_ME/svg.js\"></script>"
                        if($FW_plotmode eq "SVG");
  pO "</head>\n<body name=\"$t\">";

  if($FW_cmdret) {
    $FW_detail = "";
    $FW_room = "";
    $FW_cmdret =~ s/</&lt;/g;
    $FW_cmdret =~ s/>/&gt;/g;
    pO "<div id=\"content\">";
    pO "<pre>$FW_cmdret</pre>";
    pO "</div>";
  }

  FW_roomOverview($cmd);
  FW_style($cmd,undef)    if($cmd =~ m/^style /);
  FW_doDetail($FW_detail)  if($FW_detail);
  FW_showRoom()           if($FW_room && !$FW_detail);
  FW_logWrapper($cmd)     if($cmd =~ /^logwrapper/);
  FW_showArchive($cmd)    if($cmd =~ m/^showarchive/);
  pO "</body></html>";
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

  $FW_detail = "";
  %FW_pos = ();
  $FW_room = "";

  $arg =~ s,^[?/],,;
  foreach my $pv (split("&", $arg)) {
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);

    # Multiline: escape the NL for fhem
    $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");

    if($p eq "detail")       { $FW_detail = $v; }
    if($p eq "room")         { $FW_room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c= $1; }
    if($p eq "pos")          { %FW_pos =  split(/[=;]/, $v); }
    if($p eq "data")         { $FW_data = $v; }

  }
  $cmd.=" $dev{$c}" if($dev{$c});
  $cmd.=" $arg{$c}" if($arg{$c});
  $cmd.=" $val{$c}" if($val{$c});
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
    my $t = $defs{$d}{TYPE};
    my $st = AttrVal($d, "subType", undef);
    $t .= ":$st" if($st);
    $FW_types{$t}{$d} = 1;
  }

  $FW_room = AttrVal($FW_detail, "room", "Unsorted") if($FW_detail);
}

##############################
sub
FW_makeTable($$$$$$$$)
{
  my($d,$t,$header,$hash,$clist,$ccmd,$makelink,$cmd) = (@_);

  return if(!$hash && !$clist);

  $t = "EM"    if($t =~ m/^EM.*$/);        # EMWZ,EMEM,etc.
  $t = "KS300" if($t eq "HMS");
  pO "  <table class=\"block\" id=\"$t\">";

  # Header
  pO "  <tr>";
  foreach my $h (split(",", $header)) {
    pO "<th>$h</th>";
  }
  pO "</tr>";
  if($clist) {
    pO "<tr>";
    my @al = map { s/[:;].*//;$_ } split(" ", $clist);
    pO "<td>" . FW_select("arg.$ccmd$d",\@al,undef) . "</td>";
    pO "<td>" . FW_textfield("val.$ccmd$d", 20)    . "</td>";
    pO "<td>" .
         FW_submit("cmd.$ccmd$d", $ccmd) .
         FW_hidden("dev.$ccmd$d", $d) .
       "</td>";
    pO "</tr>";
  }

  my $row = 1;
  foreach my $v (sort keys %{$hash}) {
    my $r = ref($hash->{$v});
    next if($r && ($r ne "HASH" || !defined($hash->{$v}{VAL})));
    pF "    <tr class=\"%s\">", $row?"odd":"even";
    $row = ($row+1)%2;
    if($makelink && $FW_reldoc) {
      # no pH, want to open extra browser
      pO "<td><a href=\"$FW_reldoc#$v\">$v</a></td>"; 
    } else {
      pO "<td>$v</td>";
    }

    if(ref($hash->{$v})) {
        pO "<td id=\"show\">$hash->{$v}{VAL}</td>";
        pO "<td>$hash->{$v}{TIME}</td>" if($hash->{$v}{TIME});
    } else {
      if($v eq "DEF") {
        FW_makeEdit($d, $t, "modify", $hash->{$v});
      } else {
        pO "<td id=\"show\">$hash->{$v}</td>";
      }
    }

    pH "cmd.$d=$cmd $d $v&amp;detail=$d", $cmd, 1
        if($cmd);

    pO "</tr>";
  }
  pO "  </table>";
  pO "<br>";
  
}

##############################
sub
FW_showArchive($)
{
  my ($arg) = @_;
  my (undef, $d) = split(" ", $arg);

  my $fn = $defs{$d}{logfile};
  if($fn =~ m,^(.+)/([^/]+)$,) {
    $fn = $2;
  }
  $fn = AttrVal($d, "archivedir", "") . "/" . $fn;
  my $t = $defs{$d}{TYPE};

  pO "<div id=\"content\">";
  pO "<table><tr><td>";
  pO "<table class=\"block\" id=\"$t\"><tr><td>";

  my $row =  0;
  my $l = AttrVal($d, "logtype", undef);
  foreach my $f (FW_fileList($fn)) {
    pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
    $row = ($row+1)%2;
    if(!defined($l)) {
      pH "cmd=logwrapper $d text $f", "text", 1;
    } else {
      foreach my $ln (split(",", $l)) {
	my ($lt, $name) = split(":", $ln);
	$name = $lt if(!$name);
	pH "cmd=logwrapper $d $lt $f", $name, 1;
      }
    }
    pO "</tr>";
  }

  pO "</td></tr></table>";
  pO "</td></tr></table>";
  pO "</div>";
}


##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  pO "<form method=\"get\" action=\"$FW_ME\">";
  pO FW_hidden("detail", $d);

  $FW_room = AttrVal($d, "room", undef);
  my $t = $defs{$d}{TYPE};

  pO "<div id=\"content\">";
  pO "<table><tr><td>";
  pH "cmd=delete $d", "Delete $d";

  my $pgm = "Javascript:" .
             "s=document.getElementById('edit').style;".
             "if(s.display=='none') s.display='block'; else s.display='none';".
             "s=document.getElementById('disp').style;".
             "if(s.display=='none') s.display='block'; else s.display='none';";
  pO "<a onClick=\"$pgm\">Modify $d</a>";

  pH "room=$FW_room", "Back:$FW_room" if($FW_ss);

  pO "</td></tr><tr><td>";
  FW_makeTable($d, $t,
        "<a href=\"$FW_reldoc#${t}set\">State</a>,Value,Measured",
        $defs{$d}{READINGS}, getAllSets($d), "set", 0, undef);
  FW_makeTable($d, $t, "Internal,Value",
        $defs{$d}, "", undef, 0, undef);
  FW_makeTable($d, $t,
        "<a href=\"$FW_reldoc#${t}attr\">Attribute</a>,Value,Action",
        $attr{$d}, getAllAttr($d), "attr", 1,
        $d eq "global" ? "" : "deleteattr");
  pO "</td></tr></table>";

  FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}) if($t eq "weblink");

  pO "</div>";
  pO "</form>";

}

##############
# Room overview
sub
FW_roomOverview($)
{
  my ($cmd) = @_;

  ##############
  # HEADER
  pO "<form method=\"get\" action=\"$FW_ME\">";
  pO "<div id=\"hdr\">";
  pO '<table border="0"><tr><td style="padding:0">';
  my $tf_done;
  if($FW_room) {
    pO FW_hidden("room", "$FW_room");
    # plots navigation buttons
    if(!$FW_detail || $defs{$FW_detail}{TYPE} eq "weblink") {
      if(FW_calcWeblink(undef,undef)) {
        pO FW_textfield("cmd", $FW_ss ? 20 : 40);
        $tf_done = 1;
        pO "</td><td>";
        pO "&nbsp;&nbsp;";
        FW_zoomLink("zoom=-1", "Zoom-in.png", "zoom in");
        FW_zoomLink("zoom=1",  "Zoom-out.png","zoom out");
        FW_zoomLink("off=-1",  "Prev.png",    "prev");
        FW_zoomLink("off=1",   "Next.png",    "next");
      }
    }
  }
  pO FW_textfield("cmd", $FW_ss ? 28 : 40) if(!$tf_done);
  pO "</td></tr></table>";
  pO "</div>";
  pO "</form>";

  ##############
  # LOGO
  my $logo = $FW_ss ? "fhem_smallscreen.png" : "fhem.png";
  pO "<div id=\"logo\"><img src=\"$FW_ME/$logo\"></div>";

  ##############
  # MENU
  my (@list1, @list2);
  push(@list1, ""); push(@list2, "");
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
  foreach my $r (sort keys %FW_rooms) {
    next if($r eq "hidden");
    push @list1, $r;
    push @list2, "$FW_ME?room=$r";
  }
  push(@list1, "All together"); push(@list2, "$FW_ME?room=all");
  push(@list1, ""); push(@list2, "");
  push(@list1, "Howto");      push(@list2, "$FW_ME/HOWTO.html");
  push(@list1, "FAQ");        push(@list2, "$FW_ME/faq.html");
  push(@list1, "Details");    push(@list2, "$FW_ME/commandref.html");
  push(@list1, "Examples");   push(@list2, "$FW_ME/cmd=style%20examples");
  push(@list1, "Edit files"); push(@list2, "$FW_ME/cmd=style%20list");
  push(@list1, ""); push(@list2, "");

  pO "<div id=\"menu\">";
  if($FW_ss) {
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      if(!$list1[$idx]) {
        pO "</select>" if($idx);
        pO "<select OnChange=\"location.href=" .
                              "this.options[this.selectedIndex].value\">"
          if($idx<int(@list1)-1);
      } else {
        my $sel = ($list1[$idx] eq $FW_room ? " selected=\"selected\""  : "");
        pO "  <option value=$list2[$idx]$sel>$list1[$idx]</option>";
      }
    }

  } else {

    pO "<table>";
    foreach(my $idx = 0; $idx < @list1; $idx++) {
      if(!$list1[$idx]) {
        pO "  </table></td></tr>" if($idx);
        pO "  <tr><td><table class=\"block\" id=\"room\">"
          if($idx<int(@list1)-1);
      } else {
        pF "    <tr%s>", $list1[$idx] eq $FW_room ? " class=\"sel\"" : "";
        pO "<td><a href=\"$list2[$idx]\">$list1[$idx]</a></td></tr>";
      }
    }
    pO "</table>";

  }
  pO "</div>";
}


########################
# Generate the html output: i.e present the data
sub
FW_showRoom()
{
  # (re-) list the icons
  if(!$FW_iconsread || (time() - $FW_iconsread) > 5) {
    %FW_icons = ();
    if(opendir(DH, $FW_dir)) {
      while(my $l = readdir(DH)) {
        next if($l =~ m/^\./);
        my $x = $l;
        $x =~ s/\.[^.]+$//;	# Cut .gif/.jpg
        $FW_icons{$x} = $l;
      }
      closedir(DH);
    }
    $FW_iconsread = time();
  }

  pO "<form method=\"get\" action=\"$FW_ME\">";
  pO "<div id=\"content\">";
  pO "  <table><tr><td>";  # Need for equal width of subtables

  foreach my $type (sort keys %FW_types) {
    
    #################
    # Check if there is a device of this type in the room
    if($FW_room && $FW_room ne "all") {
       next if(!grep { $FW_rooms{$FW_room}{$_} } keys %{$FW_types{$type}} );
    }

    my $rf = ($FW_room ? "&amp;room=$FW_room" : ""); # stay in the room

    ############################
    # Print the table headers
    my @sortedDevs = sort keys %{$FW_types{$type}};
    my $allSets = " " . getAllSets($sortedDevs[0]) . " ";

    my $hasOnOff = ($allSets =~ m/ on / && $allSets =~ m/ off /);

    my $th;
    my $id = "class=\"block\"";
    if($hasOnOff) {
      $th = "$type</th><th>State</th><th colspan=\"2\">Set to";
    } elsif($type eq "FHT") {
      $th = "FHT dev.</th><th>Measured</th><th>Set to";
    } elsif($type eq "at")         { $th = "Scheduled commands (at)";
    } elsif($type eq "FileLog")    { $th = "Logs";
    } elsif($type eq "_internal_") { $th = "Global variables";
    } elsif($type eq "weblink")    { $th = ""; $id = "";
    } else {
      $th = $type;
    }
    pO "  <table $id id=\"$type\" summary=\"List of $type devices\">";
    pO "  <tr><th>$th</th></tr>" if($th);

    my $row=1;
    foreach my $d (@sortedDevs) {
      next if($FW_room && $FW_room ne "all" &&
             !$FW_rooms{$FW_room}{$d});

      pF "    <tr class=\"%s\">", $row?"odd":"even";
      $row = ($row+1)%2;
      my $v = $defs{$d}{STATE};

      if($hasOnOff) {

        my $iv = $v;    # icon value
        my $iname = "";

        if(defined(AttrVal($d, "showtime", undef))) {

          $v = $defs{$d}{READINGS}{state}{TIME};

        } elsif($iv) {

          $iv =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"
          $iname = $FW_icons{"FS20.$iv"}  if($FW_icons{"FS20.$iv"});
          $iname = $FW_icons{"$type"}     if($FW_icons{"$type"});
          $iname = $FW_icons{"$type.$iv"} if($FW_icons{"$type.$iv"});
          $iname = $FW_icons{"$d"}        if($FW_icons{"$d"});
          $iname = $FW_icons{"$d.$iv"}    if($FW_icons{"$d.$iv"});

        }
        $v = "" if(!defined($v));

        pH "detail=$d", $d, 1;
        if($iname) {
          pO "<td align=\"center\"><img src=\"$FW_ME/icons/$iname\" ".
                  "alt=\"$v\"/></td>";
        } else {
          pO "<td align=\"center\">$v</td>";
        }
        if($allSets) {
          pH "cmd.$d=set $d on$rf", "on", 1;
          pH "cmd.$d=set $d off$rf", "off", 1;
        }

      } elsif($type eq "FHT") {

        $v = ReadingsVal($d, "measured-temp", "");

        $v =~ s/ .*//;
        pH "detail=$d", $d, 1;
        pO "<td align=\"center\">$v&deg;</td>";

        $v = sprintf("%2.1f", int(2*$v)/2) if($v =~ m/[0-9.-]/);
        my @tv = map { ($_.".0", $_+0.5) } (5..30);
        shift(@tv);     # 5.0 is not valid
        $v = int($v*20)/$v if($v =~ m/^[0-9].$/);


        pO "<td>" .
            FW_hidden("arg.$d", "desired-temp") .
            FW_hidden("dev.$d", $d) .
            FW_select("val.$d", \@tv, ReadingsVal($d, "desired-temp", $v)) .
            FW_submit("cmd.$d", "set") .
            "</td>";

      } elsif($type eq "FileLog") {

        pH "detail=$d", $d, 1;
        pO "<td>$v</td>";
        if(defined(AttrVal($d, "archivedir", undef))) {
          pH "cmd=showarchive $d", "archive", 1;
        }

	foreach my $f (FW_fileList($defs{$d}{logfile})) {
          pF "    </tr>";
	  pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
	  $row = ($row+1)%2;
	  foreach my $ln (split(",", AttrVal($d, "logtype", "text"))) {
	    my ($lt, $name) = split(":", $ln);
	    $name = $lt if(!$name);
	    pH "cmd=logwrapper $d $lt $f", $name, 1;
	  }
	}

      } elsif($type eq "weblink") {

        pO "<td>";
        FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});
        pO "</td>";

      } else {

        pH "detail=$d", $d, 1;
        pO "<td>$v</td>";

      }
      pO "  </tr>";
    }
    pO "  </table>";
    pO "  <br>"; # Empty line
  }
  pO "  </td></tr>\n</table>";
  pO "</div>";
  pO "</form>";
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
      pO "<div id=\"content\">$path: $!</div>";
      return;
    }
    binmode (FH); # necessary for Windows
    my $cnt = join("", <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;

    pO "<div id=\"content\">";
    pO "<pre>$cnt</pre>";
    pO "</div>";

  } else {

    pO "<div id=\"content\">";
    pO "<table><tr><td>";
    pO "<table><tr><td>";
    pO "<td>";
    my $arg = "$FW_ME?cmd=showlog undef $d $type $file";
    if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
      my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
      pO "<embed src=\"$arg\" type=\"image/svg+xml\"" .
                    "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

    } else {
      pO "<img src=\"$arg\"/>";
    }

    pH "cmd=toweblink $d:$type:$file", "<br>Convert to weblink";
    pO "</td>";
    pO "</td></tr></table>";
    pO "</td></tr></table>";
    pO "</div>";
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
  my $title = AttrVal($wl, "title", "\"$file\"");
  $title = AnalyzeCommand(undef, "{ $title }");
  my $label = AttrVal($wl, "label", undef);
  my @g_label;
  if ($label) {
    @g_label = split(":",$label);
    foreach (@g_label) {
      $_ = AnalyzeCommand(undef, "{ $_ }");
    }
  }
  $attr{global}{verbose} = $oll;

  my $gplot_script = join("", @{$cfg});
  $gplot_script .=  $plot if(!$splitret);

  $gplot_script =~ s/<OUT>/$tmpfile/g;

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
      pO '<svg xmlns="http://www.w3.org/2000/svg">';
      pO '<text x="20" y="20">'.$msg.'</text>';
      pO '</svg>';
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
      my @path = split(" ", fC("get $d $file $tmpfile $f $t " .
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
    pO join("", <FH>);
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
    $ret = fC("get $d $file INT $f $t " . join(" ", @{$flog}));
    ($cfg, $plot) = FW_substcfg(1, $wl, $cfg, $plot, $file, "<OuT>");
    SVG_render($wl, $f, $t, $cfg, $internal_data, $plot, $FW_ss);
    $FW_RETTYPE = "image/svg+xml";

  }

}

##################
sub
FW_fatal($)
{
  my ($msg) = @_;
  pO "<html><body>$msg</body></html>";
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
FW_select($$$)
{
  my ($n, $va, $def) = @_;
  my $s = "<select name=\"$n\">";

  foreach my $v (@{$va}) {
    if($def && $v eq $def) {
      $s .= "<option selected=\"selected\" value=\"$v\">$v</option>";
    } else {
      $s .= "<option value=\"$v\">$v</option>";
    }
  }
  $s .= "</select>";
  return $s;
}

##################
sub
FW_textfield($$)
{
  my ($n, $z) = @_;
  my $s = "<input type=\"text\" name=\"$n\" size=\"$z\"/>";
  return $s;
}

##################
# Multiline (for some types of widgets) editor with submit 
sub
FW_makeEdit($$$$)
{
  my ($name, $type, $cmd, $val) = @_;
  pO "<td>";
  pO   "<div id=\"edit\" style=\"display:none\"><form>";
  my $eval = $val;
  $eval =~ s,\\\n,\n,g;
  my $ncols = $FW_ss ? 40 : 60;

  pO     "<textarea name=\"val.${cmd}$name\" cols=\"$ncols\" rows=\"10\">".
            "$eval</textarea>";
  pO     "<br>" . FW_submit("cmd.${cmd}$name", "$cmd $name");
  pO   "</form></div>";
  $eval = "<pre>$eval</pre>" if($eval =~ m/\n/);
  pO   "<div id=\"disp\">$eval</div>";
  pO  "</td>";
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

  my ($d,$off) = split("=", $cmd, 2);

  my $val = $FW_pos{$d};
  $cmd = ($FW_detail ? "detail=$FW_detail":"room=$FW_room") . "&amp;pos=";

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


  pH "$cmd", "<img style=\"border-color:transparent\" alt=\"$alt\" ".
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

  if(!$d) {
    my $cnt = 0;
    foreach my $d (sort keys %defs ) {
      next if($defs{$d}{TYPE} ne "weblink");
      next if($defs{$d}{WLTYPE} ne "fileplot");
      next if(!$FW_room || ($FW_room ne "all" && !$FW_rooms{$FW_room}{$d}));

      next if(AttrVal($d, "fixedrange", undef));
      next if($pm eq "gnuplot");
      $cnt++;
    }
    return $cnt;
  }

  return if(!$defs{$wl});

  my $fr = AttrVal($wl, "fixedrange", undef);
  my $frx;
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

  if($a[1] eq "list") {

    my @fl;
    push(@fl, "fhem.cfg");
    push(@fl, "<br>");
    push(@fl, FW_fileList("$FW_dir/.*.css"));
    push(@fl, "<br>");
    push(@fl, FW_fileList("$FW_dir/.*.js"));
    push(@fl, "<br>");
    push(@fl, FW_fileList("$FW_dir/.*.gplot"));
    push(@fl, "<br>");
    push(@fl, FW_fileList("$FW_dir/.*html"));

    pO "<div id=\"content\">";
    pO "  <table><tr><td>";
    pO "  $msg<br><br>" if($msg);
    pO "  <table class=\"block\" id=\"at\">";
    my $row = 0;
    foreach my $file (@fl) {
      pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      pH "cmd=style edit $file", $file, 1;
      pO "</tr>";
      $row = ($row+1)%2;
    }
    pO "  </table>";
    pO "  </td></tr></table>";
    pO "</div>";

  } elsif($a[1] eq "examples") {

    my @fl = FW_fileList("$FW_dir/example.*");
    pO "<div id=\"content\">";
    pO "  <table><tr><td>";
    pO "  $msg<br><br>" if($msg);
    pO "  <table class=\"block\" id=\"at\">";
    my $row = 0;
    foreach my $file (@fl) {
      pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      pH $file, $file, 1;
      pO "</tr>";
      $row = ($row+1)%2;
    }
    pO "  </table>";
    pO "  </td></tr></table>";
    pO "</div>";

  } elsif($a[1] eq "edit") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$FW_dir/$a[2]");
    if(!open(FH, $f)) {
      pO "$f: $!";
      return;
    }
    my $data = join("", <FH>);
    close(FH);

    my $ncols = $FW_ss ? 40 : 80;
    pO "<div id=\"content\">";
    pO "  <form>";
    pO     FW_submit("save", "Save $f") . "<br><br>";
    pO     FW_hidden("cmd", "style save $a[2]");
    pO     "<textarea name=\"data\" cols=\"$ncols\" rows=\"30\">" .
                "$data</textarea>";
    pO   "</form>";
    pO "</div>";

  } elsif($a[1] eq "save") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$FW_dir/$a[2]");
    if(!open(FH, ">$f")) {
      pO "$f: $!";
      return;
    }
    $FW_data =~ s/\r//g if($^O !~ m/Win/);
    binmode (FH);
    print FH $FW_data;
    close(FH);
    FW_style("style list", "Saved file $f");
    $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} : $a[2]);

    fC("rereadcfg") if($a[2] eq "fhem.cfg");
  }

}

##################
# print (append) to output
sub
pO(@)
{
  $FW_RET .= shift;
  $FW_RET .= "\n";
}

#################
# add href
sub
pH(@)
{
   my ($link, $txt, $td) = @_;

   pO "<td>" if($td);
   if($FW_ss) {
     pO "<a onClick=\"location.href='$FW_ME?$link'\">$txt</a>";
   } else {
     pO "<a href=\"$FW_ME?$link\">$txt</a>";
   }
   pO "</td>" if($td);
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
fC($)
{
  my ($cmd) = @_;
  #Log 0, "Calling $cmd";
  my $ret = AnalyzeCommand(undef, $cmd);
  return $ret;
}

##################
sub
FW_showWeblink($$$)
{
  my ($d, $v, $t) = @_;

  if($t eq "link") {
    pO "<td><a href=\"$v\">$d</a></td>";    # no pH, want to open extra browser

  } elsif($t eq "image") {
    pO "<td><img src=\"$v\"><br>";
    pH "detail=$d", $d;
    pO "</td>";

  } elsif($t eq "fileplot") {
    my @va = split(":", $v, 3);
    if(@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile}) {
      pO "<td>Broken definition: $v</td>";
    } else {
      if($va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
      }

      if($FW_ss) {
        pH "detail=$d", $d;
        pO "<br>";
      } else {
        pO "<table><tr><td>";
      }

      my $wl = "&amp;pos=" . join(";", map {"$_=$FW_pos{$_}"} keys %FW_pos);

      my $arg="$FW_ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
      if(AttrVal($d,"plotmode",$FW_plotmode) eq "SVG") {
        my ($w, $h) = split(",", AttrVal($d,"plotsize",$FW_plotsize));
        pO "<embed src=\"$arg\" type=\"image/svg+xml\"" .
              "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";

      } else {
        pO "<img src=\"$arg\"/>";
      }

      if($FW_ss) {
        pO "<br>";
      } else {
        pO "</td>";
        pH "detail=$d", $d, 1;
        pO "</tr></table>";
      }

    }
  }
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
1;
