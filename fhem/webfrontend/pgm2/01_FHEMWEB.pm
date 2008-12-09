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
sub FW_getAttr($$$);
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
sub FW_style($$);
sub FW_roomOverview($);
sub FW_fatal($);
sub pF($@);
sub pO(@);
sub FW_AnswerCall($);
sub FW_zoomLink($$$);
sub FW_calcWeblink($$);

use vars qw($__ME); # webname (fhem), needed by SVG

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
my %__icons;      # List of icons
my $__iconsread;  # Timestamp of last icondir check
my %__rooms;      # hash of all rooms
my %__devs;       # hash of from/to entries per device
my %__types;      # device types, for sorting
my $__room;       # currently selected room
my $__detail;     # currently selected device for detail view
my $__cmdret;     # Returned data by the fhem call
my %__pos;        # scroll position
my $__RET;        # Returned data (html)
my $__RETTYPE;    # image/png or the like
my @__zoom;       # "qday", "day","week","month","year"
my %__zoom;       # the same as @__zoom
my $__wname;      # Web instance name
my $__plotmode;   # Global plot mode (WEB attribute)
my $__plotsize;   # Global plot size (WEB attribute)
my $__data;       # Filecontent from browser when editing a file
my $__dir;        # FHEM directory
my $__reldoc;     # $__ME/commandref.html;


#####################################
sub
FHEMWEB_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FW_Read";

  $hash->{DefFn}   = "FW_Define";
  $hash->{UndefFn} = "FW_Undef";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 webname plotmode:gnuplot,gnuplot-scroll,SVG plotsize refresh";

  ###############
  # Initialize internal structures
  my $n = 0;
  @__zoom = ("qday", "day","week","month","year");
  %__zoom = map { $_, $n++ } @__zoom;

  $__dir = "$attr{global}{modpath}/FHEM";
}

#####################################
sub
FW_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB <tcp-portnr> [global]"
        if($port !~ m/^[0-9]+$/ || $port < 1 || $port > 65535 ||
           ($global && $global ne "global"));

  $hash->{STATE} = "Initialized";
  $hash->{SERVERSOCKET} = IO::Socket::INET->new(
          Proto     => 'tcp',
          LocalHost => (($global && $global eq "global") ? undef : "localhost"),
          LocalPort => $port,
          Listen    => 10,
          ReuseAddr => 1);

  return "Can't open server port at $port: $!" if(!$hash->{SERVERSOCKET});

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
    delete($selectlist{$hash->{NAME}});
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

    my @clientinfo = $hash->{SERVERSOCKET}->accept();
    my $ll = GetLogLevel($name,4);

    if(!@clientinfo) {
      Print("ERROR", 1, "016 Accept failed for admin port");
      Log(1, "Accept failed for HTTP port ($name: $!)");
      return;
    }

    my @clientsock = sockaddr_in($clientinfo[1]);

    my %nhash;
    $nhash{NAME}  = "FHEMWEB:". inet_ntoa($clientsock[1]) .":".$clientsock[0];
    $nhash{FD}    = $clientinfo[0]->fileno();
    $nhash{CD}    = $clientinfo[0];     # sysread / close won't work on fileno
    $nhash{TYPE}  = "FHEMWEB";
    $nhash{STATE} = "Connected";
    $nhash{SNAME} = $name;
    $nhash{TEMPORARY} = 1;              # Don't want to save it
    $nhash{BUF}   = "";

    $defs{$nhash{NAME}} = \%nhash;
    $selectlist{$nhash{NAME}} = \%nhash;

    Log($ll, "Connection accepted from $nhash{NAME}");
    return;

  }

  $__wname = $hash->{SNAME};

  my $ll = GetLogLevel($__wname,4);

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

  #Log(0, "Got: >$hash->{BUF}<");
  my @lines = split("[\r\n]", $hash->{BUF});
  my ($mode, $arg, $method) = split(" ", $lines[0]);
  $hash->{BUF} = "";

  Log($ll, "HTTP $name GET $arg");
  $hash->{INUSE} = 1;

  my $cacheable = FW_AnswerCall($arg);

  delete($hash->{INUSE});
  if(!$selectlist{$name}) {             # removed by rereadcfg, reinsert
    $selectlist{$name} = $hash;
    $defs{$name} = $hash;
  }

  my $c = $hash->{CD};
  my $l = length($__RET);
  my $e = ($cacheable? ("Expires: ".localtime(time()+900)." GMT\r\n") : "");
  #Log 0, "$arg / RL: $l";
  print $c "HTTP/1.1 200 OK\r\n",
           "Content-Length: $l\r\n",
           $e,
           "Content-Type: $__RETTYPE\r\n\r\n",
           $__RET;
}

###########################
sub
FW_AnswerCall($)
{
  my ($arg) = @_;

  $__RET = "";
  $__RETTYPE = "text/html; charset=ISO-8859-1";
  $__ME = "/" . FW_getAttr($__wname, "webname", "fhem");

  # Lets go:
  if($arg =~ m,^${__ME}/(.*html)$, || $arg =~ m,^${__ME}/(example.*)$,) {
    my $f = $1;
    $f =~ s,/,,g;    # little bit of security
    open(FH, "$__dir/$f") || return;
    pO join("", <FH>);
    close(FH);
    $__RETTYPE = "text/plain; charset=ISO-8859-1" if($f !~ m/\.*html$/);
    return 1;
  } elsif($arg =~ m,^$__ME/(.*).css,) {
    open(FH, "$__dir/$1.css") || return;
    pO join("", <FH>);
    close(FH);
    $__RETTYPE = "text/css";
    return 1;
  } elsif($arg =~ m,^$__ME/icons/(.*)$,) {
    open(FH, "$__dir/$1") || return;
    pO join("", <FH>);
    close(FH);
    $__RETTYPE = "image/*";
    return 1;
  } elsif($arg !~ m/^$__ME(.*)/) {
    Log(5, "Unknown document $arg requested");
    return 0;
  }

  my $cmd = FW_digestCgi($1);
  my $docmd = 0;
  $docmd = 1 if($cmd && 
                $cmd !~ /^showlog/ &&
                $cmd !~ /^logwrapper/ &&
                $cmd !~ /^toweblink/ &&
                $cmd !~ /^showarchive/ &&
                $cmd !~ /^style / &&
                $cmd !~ /^edit/);

  $__plotmode = FW_getAttr($__wname, "plotmode", "SVG");
  $__plotsize = FW_getAttr($__wname, "plotsize", "800,200");
  $__reldoc = "$__ME/commandref.html";

  $__cmdret = $docmd ? fC($cmd) : "";
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
    $__cmdret = fC("define wl_$max weblink fileplot $aa[0]:$aa[1]:$aa[2]");
    if(!$__cmdret) {
      $__detail = "wl_$max";
      FW_updateHashes();
    }
  }

  my $t = FW_getAttr("global", "title", "Home, Sweet Home");
  pO "<html>\n<head>\n<title>$t</title>\n";
  my $rf = FW_getAttr($__wname, "refresh", "");
  pO "<meta http-equiv=\"refresh\" content=\"$rf\">\n" if($rf);
  pO "<link href=\"$__ME/style.css\" rel=\"stylesheet\"/>\n";
  pO "</head>\n<body name=\"$t\">\n";

  if($__cmdret) {
    $__detail = "";
    $__room = "";
    $__cmdret =~ s/</&lt;/g;
    $__cmdret =~ s/>/&gt;/g;
    pO "<div id=\"right\">\n";
    pO "<pre>$__cmdret</pre>\n";
    pO "</div>\n";
  }

  FW_roomOverview($cmd);
  FW_style($cmd,undef)    if($cmd =~ m/^style /);
  FW_doDetail($__detail)  if($__detail);
  FW_showRoom()           if($__room && !$__detail);
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

  $__detail = "";
  %__pos = ();
  $__room = "";

  $arg =~ s/^\?//;
  foreach my $pv (split("&", $arg)) {
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);

    # Multiline: escape the NL for fhem
    $v =~ s/[\r]\n/\\\n/g if($v && $p && $p ne "data");
    #Log(0, "P: $p, V: $v");

    if($p eq "detail")       { $__detail = $v; }
    if($p eq "room")         { $__room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c= $1; }
    if($p eq "pos")          { %__pos =  split(/[=;]/, $v); }
    if($p eq "data")         { $__data = $v; }

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
  %__rooms = ();
  foreach my $d (keys %defs ) {
    my $r = FW_getAttr($d, "room", "Unsorted");
    $__rooms{$r}{$d} = 1;
  }

  ###############
  # Needed for type sorting
  %__types = ();
  foreach my $d (sort keys %defs ) {
    $__types{$defs{$d}{TYPE}}{$d} = 1;
  }

  $__room = FW_getAttr($__detail, "room", "Unsorted") if($__detail);
}

##############################
sub
FW_makeTable($$$$$$$$)
{
  my($d,$t,$header,$hash,$clist,$ccmd,$makelink,$cmd) = (@_);

  return if(!$hash && !$clist);

  $t = "EM"    if($t =~ m/^EM.*$/);        # EMWZ,EMEM,etc.
  $t = "KS300" if($t eq "HMS");
  pO "  <table class=\"$t\">\n";

  # Header
  pO "  <tr>";
  foreach my $h (split(",", $header)) {
    pO "<th>$h</th>";
  }
  pO "</tr>\n";
  if($clist) {
    pO "<tr>\n";
    my @al = map { s/[:;].*//;$_ } split(" ", $clist);
    pO "<td>" . FW_select("arg.$ccmd$d",\@al,undef) . "</td>";
    pO "<td>" . FW_textfield("val.$ccmd$d", 6)    . "</td>";
    pO "<td>" . FW_submit("cmd.$ccmd$d", $ccmd)    . "</td>";
    pO FW_hidden("dev.$ccmd$d", $d);
    pO "</tr>\n";
  }

  my $row = 1;
  foreach my $v (sort keys %{$hash}) {
    my $r = ref($hash->{$v});
    next if($r && ($r ne "HASH" || !$hash->{$v}{VAL}));
    pF "    <tr class=\"%s\">", $row?"odd":"even";
    $row = ($row+1)%2;
    if($makelink && $__reldoc) {
      pO "<td><a href=\"$__reldoc#$v\">$v</a></td>";
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

    pO "<td><a href=\"$__ME?cmd.$d=$cmd $d $v&amp;detail=$d\">$cmd</a></td>"
        if($cmd);

    pO "</tr>\n";
  }
  pO "  </table>\n";
  pO "<br/>\n";
  
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
  $fn = FW_getAttr($d, "archivedir", "") . "/" . $fn;
  my $t = $defs{$d}{TYPE};

  pO "<div id=\"right\">\n";
  pO "<table><tr><td>\n";
  pO "<table class=\"$t\"><tr><td>\n";

  my $row =  0;
  my $l = FW_getAttr($d, "logtype", undef);
  foreach my $f (FW_fileList($fn)) {
    pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
    $row = ($row+1)%2;
    if(!defined($l)) {
      pO "<td><a href=\"$__ME?cmd=logwrapper $d text $f\">text</a></td>";
    } else {
      foreach my $ln (split(",", $l)) {
	my ($lt, $name) = split(":", $ln);
	$name = $lt if(!$name);
	pO "<td><a href=\"$__ME?cmd=logwrapper $d $lt $f\">$name</a></td>";
      }
    }
    pO "</tr>";
  }

  pO "</td></tr></table>\n";
  pO "</td></tr></table>\n";
  pO "</div>\n";
}


##############################
sub
FW_doDetail($)
{
  my ($d) = @_;

  pO "<form method=\"get\" action=\"$__ME\">";
  pO FW_hidden("detail", $d);

  $__room = FW_getAttr($d, "room", undef);
  my $t = $defs{$d}{TYPE};

  pO "<div id=\"right\">\n";
  pO "<table><tr><td>\n";
  pO "<a href=\"$__ME?cmd=delete $d\">Delete $d</a>\n";

  my $pgm = "Javascript:" .
             "s=document.getElementById('edit').style;".
             "if(s.display=='none') s.display='block'; else s.display='none';".
             "s=document.getElementById('disp').style;".
             "if(s.display=='none') s.display='block'; else s.display='none';";
  pO "<a href=\"#top\" onClick=\"$pgm\">Modify $d</a>";

  pO "</td></tr><tr><td>\n";
  FW_makeTable($d, $t,
        "<a href=\"$__reldoc#${t}set\">State</a>,Value,Measured",
        $defs{$d}{READINGS}, getAllSets($d), "set", 0, undef);
  FW_makeTable($d, $t, "Internal,Value",
        $defs{$d}, "", undef, 0, undef);
  FW_makeTable($d, $t,
        "<a href=\"$__reldoc#attr\">Attribute</a>,Value,Action",
        $attr{$d}, getAllAttr($d), "attr", 1,
        $d eq "global" ? "" : "deleteattr");
  pO "</td></tr></table>\n";

  FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE}) if($t eq "weblink");

  pO "</div>\n";
  pO "</form>\n";

}

##############
# Room overview
sub
FW_roomOverview($)
{
  my ($cmd) = @_;
  pO "<form method=\"get\" action=\"$__ME\">";

  pO "<div id=\"hdr\">\n";
  pO "<table><tr><td>";
  pO "<a href=\"$__reldoc\">Fhem cmd</a>: ";
  pO FW_textfield("cmd", 30);
  if($__room) {
    pO FW_hidden("room", "$__room");

    # plots navigation buttons
    if(!$__detail || $defs{$__detail}{TYPE} eq "weblink") {
      if(FW_calcWeblink(undef,undef)) {
        pO "</td><td>";
        pO "&nbsp;&nbsp;";
        FW_zoomLink("zoom=-1", "Zoom-in.png", "zoom in");
        FW_zoomLink("zoom=1",  "Zoom-out.png","zoom out");
        FW_zoomLink("off=-1",  "Prev.png",    "prev");
        FW_zoomLink("off=1",   "Next.png",    "next");
      }
    }
  }
  pO "</td></tr></table>";
  pO "</div>\n";

  pO "<div id=\"left\">\n";
  pO "  <table><tr><td>\n";
  pO "    <table class=\"room\" summary=\"Room list\">\n";
  $__room = "" if(!$__room);
  foreach my $r (sort keys %__rooms) {
    next if($r eq "hidden");
    pF "    <tr%s>", $r eq $__room ? " class=\"sel\"" : "";
    pO "<td><a href=\"$__ME?room=$r\">$r</a>";
    pO "</td></tr>\n";
  }
  pF "    <tr%s>",  "all" eq $__room ? " class=\"sel\"" : "";
  pO "<td><a href=\"$__ME?room=all\">All together</a></td></tr>";
  pO "  </table>\n";
  pO "  </td></tr>\n";
  pO "  <tr><td>\n";
  pO "    <table class=\"room\" summary=\"Help/Configuration\">\n";
  pO "      <tr><td><a href=\"$__ME/HOWTO.html\">Howto</a></td></tr>\n";
  pO "      <tr><td><a href=\"$__ME/faq.html\">FAQ</a></td></tr>\n";
  pO "      <tr><td><a href=\"$__ME/commandref.html\">Details</a></td></tr>\n";
  my $sel = ($cmd =~ m/examples/) ? " class=\"sel\"" : "";
  pO "      <tr$sel><td><a href=\"$__ME?cmd=style examples\">Examples</a></td></tr>\n";
  $sel = ($cmd =~ m/list/) ? " class=\"sel\"" : "";
  pO "      <tr$sel><td><a href=\"$__ME?cmd=style list\">Edit files</a></td></tr>\n";
  pO "    </table>\n";
  pO "  </td></tr>\n";
  pO "  </table>\n";
  pO "</div>\n";
  pO "</form>\n";
}


########################
# Generate the html output: i.e present the data
sub
FW_showRoom()
{
  # (re-) list the icons
  if(!$__iconsread || (time() - $__iconsread) > 5) {
    %__icons = ();
    if(opendir(DH, $__dir)) {
      while(my $l = readdir(DH)) {
        next if($l =~ m/^\./);
        my $x = $l;
        $x =~ s/\.[^.]+$//;	# Cut .gif/.jpg
        $__icons{$x} = $l;
      }
      closedir(DH);
    }
    $__iconsread = time();
  }

  pO "<form method=\"get\" action=\"$__ME\">";
  pO "<div id=\"right\">\n";
  pO "  <table><tr><td>\n";  # Need for equal width of subtables

  foreach my $type (sort keys %__types) {
    
    #################
    # Check if there is a device of this type in the room
    if($__room && $__room ne "all") {
       next if(!grep { $__rooms{$__room}{$_} } keys %{$__types{$type}} );
    }

    my $rf = ($__room ? "&amp;room=$__room" : "");

    ############################
    # Print the table headers
    my $t = $type;
    $t = "EM" if($t =~ m/^EM.*$/);
    pO "  <table class=\"$t\" summary=\"List of $type devices\">\n";

    my $h;
    if($type eq "FS20") {
      $h = "FS20 dev.</th><th>State</th><th colspan=\"2\">Set to";
    } elsif($type eq "FHT") {
      $h = "FHT dev.</th><th>Measured</th><th>Set to";
    } elsif($type eq "at")         { $h = "Scheduled commands (at)";
    } elsif($type eq "FileLog")    { $h = "Logs";
    } elsif($type eq "_internal_") { $h = "Global variables";
    } elsif($type eq "weblink")    { $h = "";
    } else {
      $h = $type;
    }
    pO "    <tr><th>$h</th></tr>\n" if($h);

    my $row=1;
    foreach my $d (sort keys %{$__types{$type}} ) {

      next if($__room && $__room ne "all" &&
             !$__rooms{$__room}{$d});

      pF "    <tr class=\"%s\">", $row?"odd":"even";
      $row = ($row+1)%2;
      my $v = $defs{$d}{STATE};

      if($type eq "FS20") {

        my $iv = $v;
        my $iname = "";

        if(defined(FW_getAttr($d, "showtime", undef))) {

          $v = $defs{$d}{READINGS}{state}{TIME};

        } elsif($iv) {

          $iv =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"
          $iname = $__icons{"$type"}     if($__icons{"$type"});
          $iname = $__icons{"$type.$iv"} if($__icons{"$type.$iv"});
          $iname = $__icons{"$d"}        if($__icons{"$d"});
          $iname = $__icons{"$d.$iv"}    if($__icons{"$d.$iv"});

        }
        $v = "" if(!defined($v));

        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td>";
        if($iname) {
          pO "<td align=\"center\"><img src=\"$__ME/icons/$iname\" ".
                  "alt=\"$v\"/></td>";
        } else {
          pO "<td align=\"center\">$v</td>";
        }
        if(getAllSets($d)) {
          pO "<td><a href=\"$__ME?cmd.$d=set $d on$rf\">on</a></td>";
          pO "<td><a href=\"$__ME?cmd.$d=set $d off$rf\">off</a></td>";
        }

      } elsif($type eq "FHT") {

        $v = $defs{$d}{READINGS}{"measured-temp"}{VAL};
        $v = "" if(!defined($v));

        $v =~ s/ .*//;
        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td>";
        pO "<td align=\"center\">$v&deg;</td>";

        $v = sprintf("%2.1f", int(2*$v)/2) if($v =~ m/[0-9.-]/);
        my @tv = map { ($_.".0", $_+0.5) } (10..29);
        $v = int($v*20)/$v if($v =~ m/^[0-9].$/);
        pO FW_hidden("arg.$d", "desired-temp");
        pO FW_hidden("dev.$d", $d);
        pO "<td>" .
            FW_select("val.$d",\@tv,$v) .
            FW_submit("cmd.$d", "set") . "</td>";

      } elsif($type eq "FileLog") {

        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td><td>$v</td>\n";
        if(defined(FW_getAttr($d, "archivedir", undef))) {
          pO "<td><a href=\"$__ME?cmd=showarchive $d\">archive</a></td>";
        }

	foreach my $f (FW_fileList($defs{$d}{logfile})) {
          pF "    </tr>";
	  pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
	  $row = ($row+1)%2;
	  foreach my $ln (split(",", FW_getAttr($d, "logtype", "text"))) {
	    my ($lt, $name) = split(":", $ln);
	    $name = $lt if(!$name);
	    pO "<td><a href=\"$__ME?cmd=logwrapper $d $lt $f\">$name</a></td>";
	  }
	}

      } elsif($type eq "weblink") {

        FW_showWeblink($d, $defs{$d}{LINK}, $defs{$d}{WLTYPE});

      } else {

        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td><td>$v</td>\n";

      }
      pO "  </tr>\n";
    }
    pO "  </table>\n";
    pO "  <br/>\n"; # Empty line
  }
  pO "  </td></tr>\n</table>\n";
  pO "</div>\n";
  pO "</form>\n";
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
    $path = FW_getAttr($d,"archivedir","") . "/$file" if(!-f $path);

    if(!open(FH, $path)) {
      pO "<div id=\"right\">$path: $!</div>\n";
      return;
    }
    my $cnt = join("", <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;

    pO "<div id=\"right\">\n";
    pO "<pre>$cnt</pre>\n";
    pO "</div>\n";

  } else {

    pO "<div id=\"right\">\n";
    pO "<table><tr><td>\n";
    pO "<table><tr><td>\n";
    pO "<td>";
    my $arg = "$__ME?cmd=showlog undef $d $type $file";
    if(FW_getAttr($d,"plotmode",$__plotmode) eq "SVG") {
      my ($w, $h) = split(",", FW_getAttr($d,"plotsize",$__plotsize));
      pO "<embed src=\"$arg\" type=\"image/svg+xml\"" .
                    "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
    } else {
      pO "<img src=\"$arg\"/>\n";
    }

    pO "<a href=\"$__ME?cmd=toweblink $d:$type:$file\"><br/>Convert to weblink</a></td>";
    pO "</td></tr></table>\n";
    pO "</td></tr></table>\n";
    pO "</div>\n";
  }
}

######################
# Generate an image from the log via gnuplot or SVG
sub
FW_showLog($)
{
  my ($cmd) = @_;
  my (undef, $wl, $d, $type, $file) = split(" ", $cmd, 5);

  my $pm = FW_getAttr($wl,"plotmode",$__plotmode);
  my $ps = FW_getAttr($wl,"plotsize",$__plotsize);

  my $gplot_pgm = "$__dir/$type.gplot";
  return FW_fatal("Cannot read $gplot_pgm") if(!-r $gplot_pgm);
  FW_calcWeblink($d,$wl);

  if($pm =~ m/gnuplot/) {

    my $tmpfile = "/tmp/file.$$";
    my $errfile = "/tmp/gnuplot.err";

    if($pm eq "gnuplot" || !$__devs{$d}{from}) {

      # Looking for the logfile....

      $defs{$d}{logfile} =~ m,^(.*)/([^/]*)$,; # Dir and File
      my $path = "$1/$file";
      $path = FW_getAttr($d,"archivedir","") . "/$file" if(!-f $path);
      return FW_fatal("Cannot read $path") if(!-r $path);

      open(FH, $gplot_pgm) || return FW_fatal("$gplot_pgm: $!"); 
      my $gplot_script = join("", <FH>);
      close(FH);

      $gplot_script =~ s/<OUT>/$tmpfile/g;
      $gplot_script =~ s/<SIZE>/$ps/g;
      $gplot_script =~ s/<IN>/$path/g;
      $gplot_script =~ s/<TL>/$file/g;

      my $fr = FW_getAttr($wl, "fixedrange", undef);
      if($fr) {
        $fr =~ s/ /\":\"/;
        $fr = "set xrange [\"$fr\"]\n";
        $gplot_script =~ s/(set timefmt ".*")/$1\n$fr/;
      }

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script;
      close(FH);

    } elsif($pm eq "gnuplot-scroll") {

      ############################
      # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
      # the plot directive with our own, as we offer a file for each line
      my (@filelog, @data, $plot);
      open(FH, $gplot_pgm) || return FW_fatal("$gplot_pgm: $!"); 
      while(my $l = <FH>) {
        if($l =~ m/^#FileLog (.*)$/) {
          push(@filelog, $1);
        } elsif($l =~ "^plot" || $plot) {
          $plot .= $l;
        } else {
          push(@data, $l);
        }
      }
      close(FH);

      my $gplot_script = join("", @data);
      $gplot_script =~ s/<OUT>/$tmpfile/g;
      $gplot_script =~ s/<SIZE>/$ps/g;
      $gplot_script =~ s/<TL>/$file/g;

      my ($f,$t)=($__devs{$d}{from}, $__devs{$d}{to});

      my $oll = $attr{global}{verbose};
      $attr{global}{verbose} = 0;         # Else the filenames will be Log'ged
      my @path = split(" ", fC("get $d $file $tmpfile $f $t " .
                                  join(" ", @filelog)));
      $attr{global}{verbose} = $oll;

      my $i = 0;
      $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
      my $xrange = "set xrange [\"$f\":\"$t\"]\n";
      foreach my $p (@path) {   # If the file is empty, write a 0 line
        next if(!-z $p);
        open(FH, ">$p");
        print FH "$f 0\n";
        close(FH);
      }

      open(FH, "|gnuplot >> $errfile 2>&1");# feed it to gnuplot
      print FH $gplot_script, $xrange, $plot;
      close(FH);
      foreach my $p (@path) {
        unlink($p);
      }
    }
    $__RETTYPE = "image/png";
    open(FH, "$tmpfile.png");         # read in the result and send it
    pO join("", <FH>);
    close(FH);
    unlink("$tmpfile.png");

  } elsif($pm eq "SVG") {

    my (@filelog, @data, $plot);
    open(FH, $gplot_pgm) || return FW_fatal("$gplot_pgm: $!"); 
    while(my $l = <FH>) {
      if($l =~ m/^#FileLog (.*)$/) {
        push(@filelog, $1);
      } elsif($l =~ "^plot" || $plot) {
        $plot .= $l;
      } else {
        push(@data, $l);
      }
    }
    close(FH);
    my ($f,$t)=($__devs{$d}{from}, $__devs{$d}{to});
    $f = 0 if(!$f);     # From the beginning of time...
    $t = 9 if(!$t);     # till the end

    my $ret;
    if(!$modules{SVG}{LOADED}) {
      $ret = CommandReload(undef, "98_SVG");
      Log 0, $ret if($ret);
    }

    $ret = fC("get $d $file INT $f $t " . join(" ", @filelog));
    SVG_render($file, $ps, $f, $t, \@data, $internal_data, $plot);
    $__RETTYPE = "image/svg+xml";

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
  $eval =~ s,<br/>,\n,g;

  if($type eq "at" || $type eq "notify") {
    pO     "<textarea name=\"val.${cmd}$name\" cols=\"60\" rows=\"10\">".
            "$eval</textarea>";
  } else {
    pO     "<input type=\"text\" name=\"val.${cmd}$name\" size=\"40\" ".
           "value=\"$eval\"/>";
  }
  pO     "<br/>" . FW_submit("cmd.${cmd}$name", "$cmd $name");
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

  my $val = $__pos{$d};
  $cmd = ($__detail ? "detail=$__detail":"room=$__room") . "&amp;pos=";

  if($d eq "zoom") {

    $val = "day" if(!$val);
    $val = $__zoom{$val};
    return if(!defined($val) || $val+$off < 0 || $val+$off >= int(@__zoom) );
    $val = $__zoom[$val+$off];
    return if(!$val);

    # Approximation of the next offset.
    my $w_off = $__pos{off};
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
    my $zoom=$__pos{zoom};
    $zoom = 0 if(!$zoom);
    $cmd .= "zoom=$zoom;off=$off";

  }


  pO "<a href=\"$__ME?$cmd\">";
  pO "<img style=\"border-color:transparent\" alt=\"$alt\" ".
                "src=\"$__ME/icons/$img\"/></a>";
}

##################
# Calculate either the number of scrollable weblinks (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
FW_calcWeblink($$)
{
  my ($d,$wl) = @_;

  my $pm = FW_getAttr($d,"plotmode",$__plotmode);
  return if($pm eq "gnuplot");

  if(!$d) {
    my $cnt = 0;
    foreach my $d (sort keys %defs ) {
      next if($defs{$d}{TYPE} ne "weblink");
      next if($defs{$d}{WLTYPE} ne "fileplot");
      next if(!$__room || ($__room ne "all" && !$__rooms{$__room}{$d}));

      next if(FW_getAttr($d, "fixedrange", undef));
      next if($pm eq "gnuplot");
      $cnt++;
    }
    return $cnt;
  }

  return if(!$defs{$wl});

  my $fr = FW_getAttr($wl, "fixedrange", undef);
  if($fr) {
    my @range = split(" ", $fr);
    my @t = localtime;
    $__devs{$d}{from} = ResolveDateWildcards($range[0], @t);
    $__devs{$d}{to} = ResolveDateWildcards($range[1], @t); 
    return;
  }

  my $off = $__pos{$d};
  $off = 0 if(!$off);
  $off += $__pos{off} if($__pos{off});

  my $now = time();
  my $zoom = $__pos{zoom};
  $zoom = "day" if(!$zoom);

  if($zoom eq "qday") {

    my $t = $now + $off*21600;
    my @l = localtime($t);
    $l[2] = int($l[2]/6)*6;
    $__devs{$d}{from}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]);
    $__devs{$d}{to}
        = sprintf("%04d-%02d-%02d_%02d",$l[5]+1900,$l[4]+1,$l[3],$l[2]+6);

  } elsif($zoom eq "day") {

    my $t = $now + $off*86400;
    my @l = localtime($t);
    $__devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);
    $__devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]+1);

  } elsif($zoom eq "week") {

    my @l = localtime($now);
    my $t = $now - ($l[6]*86400) + ($off*86400)*7;
    @l = localtime($t);
    $__devs{$d}{from} = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);

    @l = localtime($t+7*86400);
    $__devs{$d}{to}   = sprintf("%04d-%02d-%02d",$l[5]+1900,$l[4]+1,$l[3]);


  } elsif($zoom eq "month") {

    my @l = localtime($now);
    while($off < -12) {
      $off += 12; $l[5]--;
    }
    $l[4] += $off;
    $l[4] += 12, $l[5]-- if($l[4] < 0);
    $__devs{$d}{from} = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

    $l[4]++;
    $l[4] = 0, $l[5]++ if($l[4] == 12);
    $__devs{$d}{to}   = sprintf("%04d-%02d", $l[5]+1900, $l[4]+1);

  } elsif($zoom eq "year") {

    my @l = localtime($now);
    $l[5] += $off;
    $__devs{$d}{from} = sprintf("%04d", $l[5]+1900);
    $__devs{$d}{to}   = sprintf("%04d", $l[5]+1901);

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
    push(@fl, FW_fileList("$__dir/.*.css"));
    push(@fl, "<br>");
    push(@fl, FW_fileList("$__dir/.*.gplot"));
    push(@fl, "<br>");
    push(@fl, FW_fileList("$__dir/.*html"));

    pO "<div id=\"right\">\n";
    pO "  <table><tr><td>\n";
    pO "  $msg<br/><br/>\n" if($msg);
    pO "  <table class=\"at\">\n";
    my $row = 0;
    foreach my $file (@fl) {
      pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      pO "<td><a href=\"$__ME?cmd=style edit $file\">$file</a></td></tr>";
      $row = ($row+1)%2;
    }
    pO "  </table>\n";
    pO "  </td></tr></table>\n";
    pO "</div>\n";

  } elsif($a[1] eq "examples") {

    my @fl = FW_fileList("$__dir/example.*");
    pO "<div id=\"right\">\n";
    pO "  <table><tr><td>\n";
    pO "  $msg<br/><br/>\n" if($msg);
    pO "  <table class=\"at\">\n";
    my $row = 0;
    foreach my $file (@fl) {
      pO "<tr class=\"" . ($row?"odd":"even") . "\">";
      pO "<td><a href=\"$__ME/$file\">$file</a></td></tr>";
      $row = ($row+1)%2;
    }
    pO "  </table>\n";
    pO "  </td></tr></table>\n";
    pO "</div>\n";

  } elsif($a[1] eq "edit") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$__dir/$a[2]");
    if(!open(FH, $f)) {
      pO "$f: $!";
      return;
    }
    my $data = join("", <FH>);
    close(FH);

    pO "<div id=\"right\">\n";
    pO "  <form>";
    pO     FW_submit("save", "Save $f") . "<br/><br/>";
    pO     FW_hidden("cmd", "style save $a[2]");
    pO     "<textarea name=\"data\" cols=\"80\" rows=\"30\">" .
                "$data</textarea>";
    pO   "</form>";
    pO "</div>\n";

  } elsif($a[1] eq "save") {

    $a[2] =~ s,/,,g;    # little bit of security
    my $f = ($a[2] eq "fhem.cfg" ? $attr{global}{configfile} :
                                   "$__dir/$a[2]");
    if(!open(FH, ">$f")) {
      pO "$f: $!";
      return;
    }
    $__data =~ s/\r//g if($^O ne 'MSWin32');
    print FH $__data;
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
  $__RET .= shift;
}

##################
# print formatted
sub
pF($@)
{
  my $fmt = shift;
  $__RET .= sprintf $fmt, @_;
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
FW_getAttr($$$)
{
  my ($d, $aname, $def) = @_;
  return $attr{$d}{$aname} if($d && $attr{$d} && defined($attr{$d}{$aname}));
  return $def;
}

##################
sub
FW_showWeblink($$$)
{
  my ($d, $v, $t) = @_;

  if($t eq "link") {
    pO "<td><a href=\"$v\">$d</a></td>\n";
  } elsif($t eq "fileplot") {
    my @va = split(":", $v, 3);
    if(@va != 3 || !$defs{$va[0]} || !$defs{$va[0]}{currentlogfile}) {
      pO "<td>Broken definition: $v</a></td>";
    } else {
      if($va[2] eq "CURRENT") {
        $defs{$va[0]}{currentlogfile} =~ m,([^/]*)$,;
        $va[2] = $1;
      }
      pO "<table><tr><td>";

      my $wl = "&amp;pos=" . join(";", map {"$_=$__pos{$_}"} keys %__pos);

      my $arg="$__ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl";
      if(FW_getAttr($d,"plotmode",$__plotmode) eq "SVG") {
        my ($w, $h) = split(",", FW_getAttr($d,"plotsize",$__plotsize));
        pO "<embed src=\"$arg\" type=\"image/svg+xml\"" .
              "width=\"$w\" height=\"$h\" name=\"$d\"/>\n";
      } else {
        pO "<img src=\"$arg\"/>\n";
      }

      pO "</td><td>";
      pO "<a href=\"$__ME?detail=$d\">$d</a>";
      pO "</td></tr></table>";

    }
  }
}

1;
